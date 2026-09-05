"""Small, dependency-free coordinate helpers used by the odometry bridge."""
import math


def rotate_body_to_world(quaternion, vector):
    """Rotate a body-frame vector by a body-to-world quaternion."""
    x, y, z, w = quaternion
    norm = math.sqrt(x * x + y * y + z * z + w * w)
    if not math.isfinite(norm) or norm < 1e-12:
        raise ValueError('invalid orientation quaternion')
    x, y, z, w = x / norm, y / norm, z / norm, w / norm
    vx, vy, vz = vector
    return (
        (1 - 2 * (y * y + z * z)) * vx + 2 * (x * y - z * w) * vy + 2 * (x * z + y * w) * vz,
        2 * (x * y + z * w) * vx + (1 - 2 * (x * x + z * z)) * vy + 2 * (y * z - x * w) * vz,
        2 * (x * z - y * w) * vx + 2 * (y * z + x * w) * vy + (1 - 2 * (x * x + y * y)) * vz,
    )
