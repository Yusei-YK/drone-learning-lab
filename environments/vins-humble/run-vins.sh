#!/usr/bin/env bash
# VINS-Fusion 一键起停。用法：
#   run-vins.sh build     在容器里编译工作空间（首次必须）
#   run-vins.sh start     启动 vins_node + RViz（读 EuRoC 配置）
#   run-vins.sh play      放 EuRoC 数据集，喂给 vins_node
#   run-vins.sh status    验收：节点 / 话题 / 是否在出位姿
#   run-vins.sh logs      看 vins_node 输出
#   run-vins.sh shell     进容器手工折腾
#   run-vins.sh stop      全部停掉
set -euo pipefail

WORKSPACE="${VINS_WORKSPACE:-$HOME/Documents/Codex/vins-humble}"
IMAGE="${VINS_IMAGE:-local/vins-humble:latest}"
VINS_C=vins_node
PLAY_C=vins_play
D="sudo docker"

CONFIG=/workspace/src/VINS-Fusion-ROS2/config/euroc/euroc_stereo_imu_config.yaml
BAG=/workspace/datasets/MH_01_easy_ros2

[[ -d "$WORKSPACE/src" ]] || {
  echo "❌ $WORKSPACE 不是 colcon 工作空间（缺 src/）。"
  echo "   先执行：bash $(dirname "$0")/fetch-source.sh"
  exit 1
}

dri_args=()
for dev in /dev/dri/card* /dev/dri/renderD*; do
  [[ -c "$dev" ]] && dri_args+=(--device "$dev")
done

common_args=(
  --network host --ipc host
  -e DISPLAY="${DISPLAY:-}"
  -e QT_X11_NO_MITSHM=1
  -e RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
  -v "$WORKSPACE:/workspace"
  -v /tmp/.X11-unix:/tmp/.X11-unix:rw
  -w /workspace
  --log-opt max-size=20m --log-opt max-file=2
)

srcenv='source /opt/ros/humble/setup.bash && source /workspace/install/setup.bash'
in_container() { $D exec "$1" bash -lc "$srcenv && $2"; }
rm_if_exists() { $D rm -f "$1" >/dev/null 2>&1 || true; }

case "${1:-}" in

build)
  # --network host + 代理：rosdep update 要联网拉依赖数据库。
  # 默认 bridge 网络下宿主机的 127.0.0.1 代理在容器里指向容器自己，会干等到超时。
  # HOST_UID/HOST_GID：容器里是 root，不改属主的话 build/ install/ 全是 root 所有，
  # 宿主机上想删掉重编都要密码（免密 sudo 只覆盖 /usr/bin/docker）。
  $D run --rm --network host \
    -e http_proxy="${http_proxy:-}" \
    -e https_proxy="${https_proxy:-}" \
    -e no_proxy="${no_proxy:-}" \
    -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
    -v "$WORKSPACE:/workspace" -w /workspace "$IMAGE" \
    bash -lc 'bash /workspace/build-workspace.sh'
  ;;

start)
  : "${DISPLAY:?DISPLAY 未设置。RViz 需要它，请在桌面终端里运行。}"
  [[ -d "$WORKSPACE/install/vins" ]] || { echo "❌ 还没编译。先跑：bash $0 build"; exit 1; }
  rm_if_exists "$VINS_C"
  echo "→ 启动 $VINS_C（配置：euroc_stereo_imu_config.yaml）"
  $D run -d --name "$VINS_C" "${common_args[@]}" "${dri_args[@]}" "$IMAGE" \
    bash -lc "$srcenv && ros2 run vins vins_node $CONFIG"
  echo
  echo "✅ 已启动。它现在在等图像和 IMU 数据。下一步喂数据："
  echo "   bash $0 play"
  ;;

play)
  [[ -d "$WORKSPACE/datasets/MH_01_easy_ros2" ]] || {
    echo "❌ 找不到转换好的数据集。先跑：bash $(dirname "$0")/fetch-dataset.sh"; exit 1; }
  rm_if_exists "$PLAY_C"
  echo "→ 放 EuRoC MH_01_easy（约 3 分钟）"
  $D run -d --name "$PLAY_C" "${common_args[@]}" "$IMAGE" \
    bash -lc "$srcenv && ros2 bag play $BAG --clock"
  echo "✅ 开始播放。用 bash $0 status 看 VINS 有没有在出位姿。"
  ;;

status)
  echo "--- 容器 ---"
  $D ps --filter "name=$VINS_C" --filter "name=$PLAY_C" \
    --format '{{.Names}}\t{{.Status}}' || true
  if $D ps --format '{{.Names}}' | grep -qx "$VINS_C"; then
    echo "--- 节点 ---"
    in_container "$VINS_C" 'ros2 node list 2>/dev/null' || true
    echo "--- 是否在输出位姿（等 10 秒取一帧 odometry）---"
    in_container "$VINS_C" \
      "timeout 12 ros2 topic echo --once /vins_estimator/odometry 2>/dev/null \
       | grep -A3 position || echo '(没有位姿 —— 数据集在播吗？看 logs)'"
  else
    echo "(vins_node 没在跑)"
  fi
  ;;

logs)   $D logs --tail "${2:-60}" -f "$VINS_C" ;;
shell)  $D exec -it "$VINS_C" bash ;;

stop)
  for c in "$VINS_C" "$PLAY_C"; do rm_if_exists "$c"; echo "→ 已停止并删除 $c"; done
  ;;

*)
  sed -n '2,9p' "$0"
  exit 1
  ;;
esac
