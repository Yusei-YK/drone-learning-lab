#!/usr/bin/env bash
set -eo pipefail
source /opt/ros/humble/setup.bash
set -u
rosdep update
rosdep install --from-paths src --ignore-src -r -y --rosdistro humble \
  --skip-keys "Armadillo Boost Eigen3 PCL"
colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release
