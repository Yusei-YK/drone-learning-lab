#!/usr/bin/python3
"""Typed EGO -> px4ctrl adapter. Default output is a review-only topic."""
import math
import rclpy
from rclpy.node import Node
from quadrotor_msgs.msg import PositionCommand as EgoCommand
from px4ctrl_msgs.msg import PositionCommand as ControlCommand


def convert(msg, now_ns, max_age=0.2):
    """No frame conversion: only accept fresh READY commands in world."""
    age = (now_ns - (msg.header.stamp.sec * 10**9 + msg.header.stamp.nanosec)) / 1e9
    if msg.header.frame_id != 'world':
        raise ValueError('expected world frame; no implicit frame renaming')
    if msg.trajectory_flag != EgoCommand.TRAJECTORY_STATUS_READY:
        raise ValueError('trajectory is not READY')
    if not 0 <= age <= max_age:
        raise ValueError('stale or future command')
    values = [getattr(v, a) for v in (msg.position, msg.velocity, msg.acceleration) for a in 'xyz']
    values += [msg.yaw, msg.yaw_dot, *msg.kx, *msg.kv]
    if not all(math.isfinite(v) for v in values):
        raise ValueError('non-finite command')
    out = ControlCommand()
    out.header = msg.header
    for source, target in ((msg.position, out.pos), (msg.velocity, out.vel), (msg.acceleration, out.acc)):
        for axis in 'xyz':
            setattr(target, axis, getattr(source, axis))
    out.yaw, out.yaw_dot = msg.yaw, msg.yaw_dot
    out.kx, out.kv = list(msg.kx), list(msg.kv)
    out.trajectory_id, out.trajectory_flag = msg.trajectory_id, msg.trajectory_flag
    # EGO does not supply jerk/heading. Current LinearControl does not use them.
    # Zero is an explicit adapter policy, not a measured jerk.
    return out


class Adapter(Node):
    def __init__(self):
        super().__init__('ego_px4ctrl_command_adapter')
        source = self.declare_parameter('input_topic', '/drone_0_planning/pos_cmd').value
        target = self.declare_parameter('output_topic', '/integration/review/command').value
        self.pub = self.create_publisher(ControlCommand, target, 10)
        self.sub = self.create_subscription(EgoCommand, source, self.receive, 10)
        self.accepted = self.rejected = 0

    def receive(self, msg):
        try:
            converted = convert(msg, self.get_clock().now().nanoseconds)
        except ValueError as exc:
            self.rejected += 1
            self.get_logger().warning(str(exc), throttle_duration_sec=2.0)
            return
        self.pub.publish(converted)
        self.accepted += 1


def main():
    rclpy.init()
    node = Adapter()
    try:
        rclpy.spin(node)
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
