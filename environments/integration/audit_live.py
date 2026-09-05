#!/usr/bin/python3
"""Read-only, bounded MAVROS receive probe. Never creates flight publishers."""
import json
import statistics
import time
import rclpy
from rclpy.node import Node
from rclpy.qos import QoSProfile, ReliabilityPolicy, DurabilityPolicy, qos_profile_sensor_data
from nav_msgs.msg import Odometry
from sensor_msgs.msg import Imu
from mavros_msgs.msg import State

rclpy.init()
node = Node('integration_read_only_audit')
data = {k: [] for k in ('odom', 'imu', 'state')}
last = {}

def receive_stamped(key, msg):
    stamp = msg.header.stamp.sec + msg.header.stamp.nanosec / 1e9
    data[key].append((time.monotonic(), stamp))
    last[key] = msg

def receive_state(msg):
    # mavros_msgs/State has no Header; record arrival only.
    data['state'].append((time.monotonic(), None))
    last['state'] = msg

state_qos = QoSProfile(depth=10,
                       reliability=ReliabilityPolicy.RELIABLE,
                       durability=DurabilityPolicy.VOLATILE)
subs = [node.create_subscription(kind, '/mavros/' + topic,
        lambda msg, key=key: receive_stamped(key, msg), qos_profile_sensor_data)
        for key, topic, kind in [('odom', 'local_position/odom', Odometry),
                                  ('imu', 'imu/data', Imu)]]
subs.append(node.create_subscription(State, '/mavros/state', receive_state, state_qos))
deadline = time.monotonic() + 12
while time.monotonic() < deadline:
    rclpy.spin_once(node, timeout_sec=0.1)
for key, samples in data.items():
    result = {'stream': key, 'samples': len(samples)}
    if len(samples) > 1:
        result['arrival_hz'] = round((len(samples) - 1) / (samples[-1][0] - samples[0][0]), 3)
        result['max_arrival_gap_s'] = round(max(b[0] - a[0] for a, b in zip(samples, samples[1:])), 4)
        stamps = [stamp for _, stamp in samples]
        if all(stamp is not None for stamp in stamps):
            result['stamp_step_median_s'] = round(statistics.median(b - a for a, b in zip(stamps, stamps[1:])), 4)
    if key in last:
        m = last[key]
        if key == 'state':
            result.update(connected=m.connected, armed=m.armed, mode=m.mode)
        else:
            result['frame_id'] = m.header.frame_id
            if key == 'odom':
                result['child_frame_id'] = m.child_frame_id
    print(json.dumps(result), flush=True)
node.destroy_node()
rclpy.shutdown()
