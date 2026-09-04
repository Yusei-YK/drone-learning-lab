#!/usr/bin/env bash
# 开一个交互式 ROS 2 Humble 容器，挂载 EGO 工作空间。
#
# 用法：
#   bash docker-run.sh                    # 进 bash
#   bash docker-run.sh ros2 topic list    # 跑一条命令就退出
#   EGO_WORKSPACE=/别的/路径 bash docker-run.sh
#
# 注意：这里挂载的是 **工作空间**（含 src/ build/ install/），
#   不是本脚本所在的目录。早先版本用 dirname "$0" 当挂载源，
#   从学习仓库里执行就会把错误的目录挂成 /workspace。
set -euo pipefail

workspace="${EGO_WORKSPACE:-$HOME/Documents/Codex/ego-humble}"
image="${EGO_IMAGE:-local/ego-planner-humble:latest}"

[[ -d "$workspace/src" ]] || {
  echo "❌ $workspace 看起来不是 colcon 工作空间（缺 src/）。"
  echo "   先跑 fetch-source.sh，或用 EGO_WORKSPACE=... 指定正确路径。"
  exit 1
}

# 硬件渲染需要显式传 GPU 设备，否则 Mesa 回落到 llvmpipe 软件渲染
dri_args=()
for dev in /dev/dri/card* /dev/dri/renderD*; do
  [[ -c "$dev" ]] && dri_args+=(--device "$dev")
done

exec sudo --preserve-env=DISPLAY,HTTP_PROXY,HTTPS_PROXY,NO_PROXY,http_proxy,https_proxy,no_proxy \
  docker run --rm -it \
  --network host --ipc host \
  -e DISPLAY -e QT_X11_NO_MITSHM=1 \
  -e HTTP_PROXY -e HTTPS_PROXY -e NO_PROXY \
  -e http_proxy -e https_proxy -e no_proxy \
  -e RMW_IMPLEMENTATION=rmw_cyclonedds_cpp \
  -v "$workspace:/workspace" \
  -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
  -w /workspace \
  "${dri_args[@]}" \
  "$image" "$@"
