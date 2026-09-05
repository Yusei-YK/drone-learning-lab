#!/usr/bin/python3
"""Exercise both real generated ROS types and DDS transport in an isolated domain."""
import copy
import math
import time
import rclpy
from rclpy.node import Node
from rclpy.executors import SingleThreadedExecutor
from command_adapter import Adapter, EgoCommand, ControlCommand, convert


def main():
    rclpy.init()
    adapter, probe = Adapter(), Node('adapter_test_probe')
    executor = SingleThreadedExecutor()
    executor.add_node(adapter)
    executor.add_node(probe)
    try:
        now = probe.get_clock().now()
        msg = EgoCommand()
        msg.header.stamp, msg.header.frame_id = now.to_msg(), 'world'
        msg.trajectory_flag, msg.trajectory_id = EgoCommand.TRAJECTORY_STATUS_READY, 23
        msg.position.x, msg.position.y, msg.position.z = 1.25, -2.5, 3.75
        msg.velocity.x, msg.acceleration.z = -0.5, 0.125
        msg.yaw, msg.yaw_dot = 0.8, -0.2
        msg.kx, msg.kv = [1.0, 2.0, 3.0], [4.0, 5.0, 6.0]
        expected = convert(msg, now.nanoseconds)
        assert (expected.pos.x, expected.pos.y, expected.pos.z) == (1.25, -2.5, 3.75)
        assert expected.vel.x == -0.5 and expected.acc.z == 0.125
        assert expected.yaw == 0.8 and expected.yaw_dot == -0.2
        assert list(expected.kx) == [1, 2, 3] and list(expected.kv) == [4, 5, 6]
        assert expected.header == msg.header and expected.trajectory_id == 23
        assert (expected.jerk.x, expected.jerk.y, expected.jerk.z) == (0, 0, 0)
        assert list(expected.heading) == [0, 0, 0]
        print('PASS: real ROS message types, vector/yaw/header/gain/id mapping; jerk/heading policy', flush=True)
        bad = []
        m = copy.deepcopy(msg); m.header.frame_id = 'map'; bad.append(('frame', m, now.nanoseconds))
        m = copy.deepcopy(msg); m.trajectory_flag = 0; bad.append(('status', m, now.nanoseconds))
        m = copy.deepcopy(msg); m.position.x = math.nan; bad.append(('NaN', m, now.nanoseconds))
        bad += [('stale', msg, now.nanoseconds + 300_000_000), ('future', msg, now.nanoseconds - 1)]
        for label, item, stamp in bad:
            try:
                convert(item, stamp)
            except ValueError:
                continue
            raise AssertionError(f'accepted {label}')
        print('PASS: rejected wrong frame, non-READY, NaN, stale and future messages', flush=True)
        received = []
        sub = probe.create_subscription(ControlCommand, '/integration/review/command', received.append, 10)
        pub = probe.create_publisher(EgoCommand, '/drone_0_planning/pos_cmd', 10)
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline and not (pub.get_subscription_count() and adapter.pub.get_subscription_count()):
            executor.spin_once(timeout_sec=0.05)
        assert pub.get_subscription_count() and adapter.pub.get_subscription_count(), 'DDS discovery timeout'
        msg.header.stamp = probe.get_clock().now().to_msg()
        pub.publish(msg)
        while time.monotonic() < deadline and not received:
            executor.spin_once(timeout_sec=0.02)
        assert len(received) == 1 and received[0] == convert(msg, probe.get_clock().now().nanoseconds, max_age=10)
        pub.publish(bad[0][1])
        end = time.monotonic() + 0.3
        while time.monotonic() < end:
            executor.spin_once(timeout_sec=0.02)
        assert len(received) == 1 and adapter.rejected == 1
        print('PASS: DDS EGO publisher -> adapter -> px4ctrl_msgs subscriber; invalid frame not forwarded', flush=True)
    finally:
        executor.shutdown()
        adapter.destroy_node()
        probe.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
