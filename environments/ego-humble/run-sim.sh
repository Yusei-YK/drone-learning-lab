#!/usr/bin/env bash
# 一条命令起停 EGO-Planner 单机仿真。
#
# 为什么需要这个脚本：
#   在此之前，启动命令只写在文档正文里，靠人手抄。手抄会漏掉
#   --log-opt（曾让容器日志涨到 690 万行）和 --device /dev/dri
#   （漏了 RViz 就退化成 llvmpipe 软件渲染）。把踩过的坑固化进脚本，
#   才叫"环境配好了"。
#
# 用法：
#   bash run-sim.sh start     # 起 ego_sim + ego_rviz
#   bash run-sim.sh stop      # 停掉并删除这两个容器
#   bash run-sim.sh status    # 看状态、节点数
#   bash run-sim.sh logs      # 看最近 40 行日志（带上限，不会灌屏）
set -euo pipefail

WORKSPACE="${EGO_WORKSPACE:-$HOME/Documents/Codex/ego-humble}"
IMAGE="${EGO_IMAGE:-local/ego-planner-humble:latest}"
D="sudo docker"

: "${DISPLAY:?DISPLAY 未设置。图形界面需要它，请在桌面终端里运行本脚本。}"

[[ -d "$WORKSPACE/install" ]] || {
  echo "❌ 找不到 $WORKSPACE/install，说明工作空间还没编译。"
  echo "   先跑：bash $(dirname "$0")/fetch-source.sh && bash $(dirname "$0")/build-workspace.sh"
  exit 1
}

$D image inspect "$IMAGE" >/dev/null 2>&1 || {
  echo "❌ 镜像 $IMAGE 不存在。先跑：bash $(dirname "$0")/build-image.sh"
  exit 1
}

# 硬件渲染需要显式把 GPU 设备节点传进容器，否则 Mesa 回落到 llvmpipe（软件渲染）
dri_args=()
for dev in /dev/dri/card* /dev/dri/renderD*; do
  [[ -c "$dev" ]] && dri_args+=(--device "$dev")
done

common_args=(
  --network host --ipc host
  -e DISPLAY="$DISPLAY"          # 显式传值，不依赖 sudo 是否保留环境变量
  -e QT_X11_NO_MITSHM=1
  -e RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
  -v "$WORKSPACE:/workspace"
  -v /tmp/.X11-unix:/tmp/.X11-unix:rw
  -w /workspace
  --log-opt max-file=2
)

in_container() {  # 在容器里跑一条需要 ROS 环境的命令（docker exec 不会执行 ENTRYPOINT）
  $D exec "$1" bash -lc "source /opt/ros/humble/setup.bash && source /workspace/install/setup.bash && $2"
}

drop() {  # 只删本脚本自己管理的两个容器，不碰别的
  for c in ego_sim ego_rviz; do
    if $D ps -aq -f "name=^${c}$" | grep -q .; then
      echo "→ 移除已存在的 $c"
      $D rm -f "$c" >/dev/null
    fi
  done
}

case "${1:-start}" in
start)
  drop
  echo "→ 启动 ego_sim（规划 + 假飞机 + 假地图，日志上限 20m）"
  $D run -d --name ego_sim "${common_args[@]}" --log-opt max-size=20m \
    "$IMAGE" ros2 launch ego_planner single_run_in_sim.launch.py >/dev/null
  sleep 3
  echo "→ 启动 ego_rviz（可视化，带 ${#dri_args[@]} 个 GPU 设备参数，日志上限 10m）"
  $D run -d --name ego_rviz "${common_args[@]}" --log-opt max-size=10m \
    "${dri_args[@]}" "$IMAGE" ros2 launch ego_planner rviz.launch.py >/dev/null
  sleep 5
  echo
  echo "✅ 已启动。验收三步："
  echo "   1) bash $0 status          节点应有 7 个"
  echo "   2) 看 RViz 窗口里有没有绿色轨迹在动"
  echo "   3) bash $0 logs            应看到 FSM 状态在变化"
  ;;
stop)
  drop
  echo "✅ 已停止。"
  ;;
status)
  $D ps --filter name=ego_ --format '{{.Names}}\t{{.Status}}'
  echo "--- 节点 ---"
  in_container ego_rviz 'ros2 node list 2>/dev/null | sort' || echo "（容器没在跑）"
  echo "--- GPU 设备是否进到容器里（空 = RViz 会退化成 llvmpipe 软件渲染）---"
  in_container ego_rviz 'ls /dev/dri 2>/dev/null | tr "\n" " "; echo' || true
  ;;
logs)
  $D logs --tail 40 ego_sim 2>&1 | tail -40
  ;;
*)
  echo "用法: bash $0 {start|stop|status|logs}"
  exit 1
  ;;
esac
