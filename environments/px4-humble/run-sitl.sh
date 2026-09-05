#!/usr/bin/env bash
# PX4 SITL 一键起停。用法：
#   run-sitl.sh build     在容器里编译 PX4（首次必须）
#   run-sitl.sh start     启动 PX4 SITL + Gazebo Garden（x500 四旋翼）
#   run-sitl.sh mavros    再起一个容器跑 MAVROS，把 MAVLink 桥成 ROS 2 话题
#   run-sitl.sh status    验收：进程 / 话题 / GPU
#   run-sitl.sh logs      看 PX4 输出
#   run-sitl.sh shell     进容器手工折腾
#   run-sitl.sh stop      全部停掉
set -euo pipefail

PX4_ROOT="${PX4_ROOT:-$HOME/Documents/Codex/px4-sitl}"
IMAGE="${PX4_IMAGE:-local/px4-humble:latest}"
SIM_C=px4_sitl
MAVROS_C=px4_mavros
D="sudo docker"

# MAVLink 端口（PX4 SITL 的默认约定，别改）：
#   14550 广播给地面站（QGroundControl 自动监听这个）
#   14540 给机载软件 / offboard 控制用，MAVROS 连这个
FCU_URL="udp://:14540@127.0.0.1:14557"

[[ -d "$PX4_ROOT/PX4-Autopilot" ]] || {
  echo "❌ 找不到 $PX4_ROOT/PX4-Autopilot"
  echo "   先执行：bash $(dirname "$0")/fetch-source.sh"
  exit 1
}

# 图形界面必须有 DISPLAY。Gazebo 的 GUI 和 RViz 一样要画到你的屏幕上。
need_display() {
  : "${DISPLAY:?DISPLAY 未设置。请在桌面终端里运行本脚本，不要在纯 SSH 里跑。}"
}

# 逐个把显卡设备传进容器。漏掉这步 Gazebo 会回落到软件渲染，帧率惨不忍睹。
dri_args=()
for dev in /dev/dri/card* /dev/dri/renderD*; do
  [[ -c "$dev" ]] && dri_args+=(--device "$dev")
done

common_args=(
  --network host --ipc host
  -e DISPLAY="$DISPLAY"          # 显式传值，不依赖 sudo 是否保留环境变量
  -e QT_X11_NO_MITSHM=1
  -e RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
  -v "$PX4_ROOT:/px4"
  -v /tmp/.X11-unix:/tmp/.X11-unix:rw
  -w /px4
  --log-opt max-size=20m --log-opt max-file=2   # 不加上限，日志能涨到几百万行
)

in_container() {
  $D exec "$1" bash -lc \
    "source /opt/ros/humble/setup.bash && $2"
}

rm_if_exists() { $D rm -f "$1" >/dev/null 2>&1 || true; }

case "${1:-}" in

build)
  # 编译不需要图形界面，所以不检查 DISPLAY，也不传显卡设备。
  # --rm：编译容器用完即删，产物留在挂载目录里，不会丢。
  #
  # --network host + 代理变量：**编译期要联网**，这一条不是可选的。
  #   PX4 的 uxrce_dds_client 模块用 CMake ExternalProject，在 build 过程中
  #   现场 git clone eProsima 的 Micro-CDR / Micro-XRCE-DDS。默认 bridge 网络下
  #   宿主机的 127.0.0.1:17892 代理在容器里指向容器自己，clone 会**静默挂住**——
  #   CPU 掉到 0%，ninja 停在某一行不动，没有任何报错。
  #   【运行验证】加上这两项后 git ls-remote 立刻返回。
  #
  # 传 HOST_UID/HOST_GID 进去，让 build-px4.sh 编完把产物属主改回宿主机用户。
  # 不这么做的话 build/ 会是 root 所有，宿主机上想删都得要密码。
  $D run --rm --network host \
    -e http_proxy="${http_proxy:-}" \
    -e https_proxy="${https_proxy:-}" \
    -e no_proxy="${no_proxy:-}" \
    -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
    -v "$PX4_ROOT:/px4" -w /px4 "$IMAGE" \
    bash -lc 'bash /px4/build-px4.sh'
  ;;

start)
  need_display
  rm_if_exists "$SIM_C"
  echo "→ 启动 $SIM_C（PX4 SITL + Gazebo Garden，机型 x500）"
  # make px4_sitl gz_x500 会同时启动 PX4 飞控固件和 Gazebo。
  # PX4_GZ_STANDALONE 不设，让 PX4 自己拉起 gz server + GUI。
  $D run -d --name "$SIM_C" "${common_args[@]}" "${dri_args[@]}" "$IMAGE" \
    bash -lc 'cd /px4/PX4-Autopilot && make px4_sitl gz_x500'
  echo
  echo "✅ 已启动。首次会慢一些（Gazebo 要加载模型）。验收："
  echo "   1) bash $0 status        应看到 px4 进程 + gz 进程"
  echo "   2) 屏幕上应弹出 Gazebo 窗口，里面有一架四旋翼停在地面"
  echo "   3) bash $0 logs          应看到 'Ready for takeoff!'"
  ;;

mavros)
  rm_if_exists "$MAVROS_C"
  echo "→ 启动 $MAVROS_C（MAVLink → ROS 2 话题）"
  $D run -d --name "$MAVROS_C" "${common_args[@]}" "$IMAGE" \
    bash -lc "source /opt/ros/humble/setup.bash && \
      ros2 launch mavros px4.launch fcu_url:='$FCU_URL'"
  echo "   连接的是 $FCU_URL"
  echo
  echo "✅ 验收：bash $0 status，/mavros/state 应该有数据且 connected=True"
  ;;

status)
  echo "--- 容器 ---"
  $D ps --filter "name=$SIM_C" --filter "name=$MAVROS_C" \
    --format '{{.Names}}\t{{.Status}}' || true
  if $D ps --format '{{.Names}}' | grep -qx "$SIM_C"; then
    echo "--- 容器内进程（应有 px4 和 gz）---"
    $D exec "$SIM_C" bash -lc \
      "ps -eo comm= | sort -u | grep -E '^(px4|gz|ruby)' || echo '(没有 px4/gz 进程 —— 看 logs)'"
    echo "--- GPU 设备（空 = Gazebo 会退化成软件渲染）---"
    $D exec "$SIM_C" bash -lc 'ls /dev/dri 2>/dev/null | tr "\n" " " || echo "(无)"'
    echo
  fi
  if $D ps --format '{{.Names}}' | grep -qx "$MAVROS_C"; then
    echo "--- MAVROS 话题数 ---"
    in_container "$MAVROS_C" 'ros2 topic list 2>/dev/null | grep -c mavros || true'
    echo "--- 连接状态（等 3 秒取一帧）---"
    in_container "$MAVROS_C" \
      'timeout 8 ros2 topic echo --once /mavros/state 2>/dev/null | grep -E "connected|mode" || echo "(取不到 —— PX4 可能还没起来)"'
  fi
  ;;

logs)
  $D logs --tail "${2:-60}" -f "$SIM_C"
  ;;

shell)
  need_display
  $D exec -it "$SIM_C" bash
  ;;

stop)
  for c in "$SIM_C" "$MAVROS_C"; do
    rm_if_exists "$c"
    echo "→ 已停止并删除 $c"
  done
  ;;

*)
  sed -n '2,9p' "$0"
  exit 1
  ;;
esac
