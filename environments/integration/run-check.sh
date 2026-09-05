#!/usr/bin/env bash
# build: only two new packages; test: isolated DDS domain, no flight controller.
set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WS="${INTEGRATION_WS:-$HOME/Documents/Codex/drone-integration}"
EGO="${EGO_WORKSPACE:-$HOME/Documents/Codex/ego-humble}"
IMAGE="local/px4-humble:latest"
case "${1:-}" in
prepare) exec /usr/bin/python3 "$HERE/prepare.py" ;;
build|test)
  [[ -f "$WS/source-manifest.json" ]] || { echo 'Run prepare first.'; exit 1; }
  action="$1"
  sudo -n /usr/bin/docker run --rm --network none --user "$(id -u):$(id -g)" \
    -e HOME=/tmp -e MAKEFLAGS=-j2 -e CMAKE_BUILD_PARALLEL_LEVEL=2 -e ROS_DOMAIN_ID=87 -e ROS_LOCALHOST_ONLY=1 \
    -e RMW_IMPLEMENTATION=rmw_cyclonedds_cpp -e ACTION="$action" \
    -v "$WS:/integration" -v "$EGO:/workspace:ro" -v "$HERE:/checks:ro" \
    -e EGO_SETUP=/workspace/install/quadrotor_msgs/share/quadrotor_msgs/local_setup.bash -w /integration "$IMAGE" \
    bash -c 'set -eo pipefail
      source /opt/ros/humble/setup.bash
      source "$EGO_SETUP"
      if [[ "$ACTION" == build ]]; then
        colcon build --packages-select px4ctrl_msgs px4ctrl --executor sequential --cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF
      else
        source /integration/install/setup.bash
        /usr/bin/python3 /checks/test_adapter.py
      fi'
  ;;
*) echo "Usage: bash $0 prepare|build|test"; exit 2 ;;
esac
