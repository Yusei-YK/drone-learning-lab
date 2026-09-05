#!/usr/bin/python3
"""Dependency-free coordinate checks for the odometry bridge."""
import math
from bridge_math import rotate_body_to_world


def close(actual, expected):
    assert all(abs(a - e) < 1e-9 for a, e in zip(actual, expected)), (actual, expected)


close(rotate_body_to_world((0, 0, 0, 1), (1, 2, 3)), (1, 2, 3))
yaw = math.pi / 2
close(rotate_body_to_world((0, 0, math.sin(yaw / 2), math.cos(yaw / 2)), (1, 0, 0)), (0, 1, 0))
try:
    rotate_body_to_world((0, 0, 0, 0), (1, 0, 0))
except ValueError:
    pass
else:
    raise AssertionError('zero quaternion was accepted')
print('PASS: identity, +90 deg ENU yaw, and invalid quaternion checks')
