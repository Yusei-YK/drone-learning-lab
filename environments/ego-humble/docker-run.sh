#!/usr/bin/env bash
set -euo pipefail
root_dir="$(cd "$(dirname "$0")" && pwd)"
exec sudo --preserve-env=DISPLAY,HTTP_PROXY,HTTPS_PROXY,NO_PROXY,http_proxy,https_proxy,no_proxy \
  docker run --rm -it \
  --network host --ipc host \
  -e DISPLAY -e QT_X11_NO_MITSHM=1 \
  -e HTTP_PROXY -e HTTPS_PROXY -e NO_PROXY \
  -e http_proxy -e https_proxy -e no_proxy \
  -e RMW_IMPLEMENTATION=rmw_cyclonedds_cpp \
  -v "$root_dir:/workspace" \
  -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
  -w /workspace \
  local/ego-planner-humble:latest "$@"
