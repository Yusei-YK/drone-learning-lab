#!/usr/bin/python3
"""Convert MAVROS body-frame odometry velocity to a world-frame review topic."""
import copy
import rclpy
from nav_msgs.msg import Odometry
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data

from bridge_math import rotate_body_to_world


class OdomBridge(Node):
    def __init__(self):
        super().__init__('mavros_odom_world_bridge')
        input_topic = self.declare_parameter('input_topic', '/mavros/local_position/odom').value
        output_topic = self.declare_parameter('output_topic', '/integration/odom_world').value
        self.world_frame = self.declare_parameter('world_frame', 'world').value
        self.publisher = self.create_publisher(Odometry, output_topic, qos_profile_sensor_data)
        self.subscription = self.create_subscription(
            Odometry, input_topic, self.convert, qos_profile_sensor_data)

    def convert(self, msg):
        try:
            q = msg.pose.pose.orientation
            v = msg.twist.twist.linear
            vx, vy, vz = rotate_body_to_world((q.x, q.y, q.z, q.w), (v.x, v.y, v.z))
        except ValueError as exc:
            self.get_logger().warning(str(exc), throttle_duration_sec=2.0)
            return
        out = copy.deepcopy(msg)
        out.header.frame_id = self.world_frame
        out.twist.twist.linear.x = vx
        out.twist.twist.linear.y = vy
        out.twist.twist.linear.z = vz
        self.publisher.publish(out)


def main():
    rclpy.init()
    node = OdomBridge()
    try:
        rclpy.spin(node)
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
