#!/usr/bin/python3
"""仅在受保护的 X500 SITL 容器中运行；最多 180 秒，2 Hz JSON 证据。"""
import json
import math
import os
import statistics
import subprocess
import time
from collections import deque
from pathlib import Path

import rclpy
from rclpy.qos import qos_profile_sensor_data
from geometry_msgs.msg import PoseStamped, TwistStamped
from mavros_msgs.msg import State, ExtendedState, Altitude
from mavros_msgs.srv import CommandBool, CommandTOL
from gz.transport13 import Node as GzNode
from gz.msgs10.pose_v_pb2 import Pose_V


def main():
    assert os.environ.get('PX4_SIM_MODEL') == 'gz_x500'
    assert Path('/px4-runtime').is_dir(), '只能在本项目 SITL 容器中执行'
    rclpy.init()
    node = rclpy.create_node('bounded_sitl_acceptance')
    data = {}
    start = time.monotonic()
    last_print = 0.0
    phase = 'ground'
    truth = None
    gz = GzNode()

    def on_truth(msg):
        nonlocal truth
        for p in msg.pose:
            if p.name == 'x500_0':
                truth = (time.monotonic(), p.position.x, p.position.y, p.position.z)
                break

    gz.subscribe(Pose_V, '/world/default/pose/info', on_truth)
    subscriptions = []
    for topic, typ, key in [
        ('state', State, 'state'), ('extended_state', ExtendedState, 'extended'),
        ('local_position/pose', PoseStamped, 'pose'),
        ('local_position/velocity_local', TwistStamped, 'velocity'),
        ('altitude', Altitude, 'altitude'),
    ]:
        subscriptions.append(node.create_subscription(
            typ, '/mavros/' + topic,
            lambda m, k=key: data.update({k: (time.monotonic(), m)}),
            qos_profile_sensor_data))
    arm = node.create_client(CommandBool, '/mavros/cmd/arming')
    takeoff = node.create_client(CommandTOL, '/mavros/cmd/takeoff')
    land = node.create_client(CommandTOL, '/mavros/cmd/land')

    def emit(**fields):
        print(json.dumps(dict(t=round(time.monotonic()-start, 2), phase=phase, **fields)), flush=True)

    def tick():
        nonlocal last_print
        assert time.monotonic()-start < 180, '整体验收超时'
        rclpy.spin_once(node, timeout_sec=0.1)
        now = time.monotonic()
        if now-last_print >= 0.5:
            fields = {}
            if truth:
                fields.update(truth_xyz=list(truth[1:]), truth_age=round(now-truth[0], 3))
            for key, (_, m) in data.items():
                if key == 'state':
                    fields.update(armed=m.armed, connected=m.connected, mode=m.mode)
                elif key == 'extended':
                    fields['landed_state'] = m.landed_state
                elif key == 'pose':
                    fields['ekf_z'] = m.pose.position.z
                elif key == 'velocity':
                    fields['ekf_vz'] = m.twist.linear.z
                elif key == 'altitude':
                    fields.update(amsl=m.amsl, relative=m.relative)
            emit(**fields)
            last_print = now

    def wait_for(predicate, seconds, message):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            tick()
            if predicate():
                return
        raise RuntimeError(message)

    def fresh():
        now = time.monotonic()
        return (truth is not None and now-truth[0] < 1
                and all(k in data and now-data[k][0] < 3
                        for k in ('state', 'extended', 'pose', 'velocity', 'altitude')))

    def call(client, request):
        assert client.wait_for_service(timeout_sec=5), '服务不可用'
        future = client.call_async(request)
        wait_for(future.done, 8, '服务应答超时')
        result = future.result()
        emit(service=client.srv_name, success=result.success, result=result.result)
        assert result.success, '飞控拒绝指令'

    def tol():
        # PX4 navigator 的 NaN 分支：当前位置 + MIS_TAKEOFF_ALT。
        return CommandTOL.Request(min_pitch=0.0, yaw=math.nan,
                                  latitude=math.nan, longitude=math.nan, altitude=math.nan)

    try:
        wait_for(lambda: fresh() and data['state'][1].connected, 20, '遥测或真值缺失')
        assert not data['state'][1].armed, '初始必须未解锁'
        assert data['extended'][1].landed_state == 1, '初始必须着陆'
        health_deadline = time.monotonic() + 35
        while True:
            health = subprocess.check_output([
                '/px4/PX4-Autopilot/build/px4_sitl_default/bin/px4-listener',
                'vehicle_status', '-n', '1'], timeout=5, text=True)
            if ('pre_flight_checks_pass: True' in health and
                    'gcs_connection_lost: False' in health):
                break
            assert time.monotonic() < health_deadline, health
            # 刚启动时 EKF/GPS 需要收敛；只等待，不改任何预检参数。
            until = time.monotonic() + 1
            while time.monotonic() < until:
                tick()
        assert fresh(), '预检结束时遥测必须仍然新鲜'
        ground = truth[3]
        emit(event='baseline', ground_z=ground, preflight=True, gcs=True)
        phase = 'takeoff'
        call(arm, CommandBool.Request(value=True))
        call(takeoff, tol())
        wait_for(lambda: fresh() and truth[3]-ground > 1.5
                 and data['extended'][1].landed_state == 2, 35, '没有实际升空')
        phase = 'hover'
        window = deque()

        def stable():
            assert fresh(), '飞行中遥测失效'
            assert data['state'][1].armed, '悬停期间意外上锁'
            now = time.monotonic()
            window.append((now, truth[3], abs(data['velocity'][1].twist.linear.z)))
            while window and now-window[0][0] > 9:
                window.popleft()
            return (now-window[0][0] >= 8 and
                    all(1.5 < z-ground < 4 for _, z, _ in window) and
                    max(z for _, z, _ in window)-min(z for _, z, _ in window) < 0.5 and
                    max(v for _, _, v in window) < 0.3)

        wait_for(stable, 35, '悬停未稳定')
        emit(event='hover_pass', truth_z_mean=statistics.mean(z for _, z, _ in window),
             truth_z_range=[min(z for _, z, _ in window), max(z for _, z, _ in window)],
             duration=window[-1][0]-window[0][0])
        phase = 'land'
        call(land, tol())
        wait_for(lambda: fresh() and not data['state'][1].armed
                 and data['extended'][1].landed_state == 1
                 and abs(truth[3]-ground) < 0.15, 45, '未着陆自动上锁')
        phase = 'ground_verify'
        end = time.monotonic()+5
        while time.monotonic() < end:
            tick()
            assert fresh() and not data['state'][1].armed
            assert abs(truth[3]-ground) < 0.15
        emit(event='PASS', final_truth_z=truth[3], auto_disarmed=True)
    except Exception as exc:
        emit(event='FAIL', error=str(exc))
        if 'state' in data and data['state'][1].armed:
            phase = 'failure_land'
            try:
                call(land, tol())
                wait_for(lambda: not data['state'][1].armed, 25, '失败收尾未自动上锁')
            except Exception as cleanup_error:
                emit(event='cleanup_failure', error=str(cleanup_error))
        raise
    finally:
        gz.unsubscribe('/world/default/pose/info')
        # Gazebo 的 C++ 接收线程必须在 Python 解释器退出前结束。
        del gz
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
