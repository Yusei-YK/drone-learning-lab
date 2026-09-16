#!/usr/bin/env bash
# PX4 SITL 一键起停。用法：
#   run-sitl.sh build     在容器里编译 PX4（首次必须）
#   run-sitl.sh start     启动已编译的 PX4 SITL + Gazebo（默认无 GUI，限时 20 分钟）
#   run-sitl.sh mavros    再起一个容器跑 MAVROS，把 MAVLink 桥成 ROS 2 话题
#   run-sitl.sh status    验收：进程 / 话题 / GPU
#   run-sitl.sh logs      看 PX4 输出（最多 200 行、64 KiB、8 秒，不跟随）
#   run-sitl.sh shell     进容器手工折腾
#   run-sitl.sh stop      全部停掉
set -euo pipefail

PX4_ROOT="${PX4_ROOT:-$HOME/Documents/Codex/px4-sitl}"
IMAGE="${PX4_IMAGE:-local/px4-humble:latest}"
SIM_C="${PX4_SIM_CONTAINER:-px4_sitl}"
MAVROS_C="${PX4_MAVROS_CONTAINER:-px4_mavros}"
D=(sudo -n /usr/bin/docker)
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SESSION_SECONDS="${PX4_SESSION_SECONDS:-1200}"
if [[ ! "$SESSION_SECONDS" =~ ^[1-9][0-9]{0,3}$ ]] || (( SESSION_SECONDS > 1200 )); then
  echo 'PX4_SESSION_SECONDS 必须为 1..1200 秒。' >&2
  exit 1
fi

# CycloneDDS 会在容器启动时记录网卡地址。宿主机换 Wi-Fi 后，旧容器可能
# 继续向已经不存在的地址发发现包；设置 DDS_INTERFACE=lo 可让本机 ROS 话题
# 只走回环。留空时保留 CycloneDDS 默认网卡选择，便于跨主机通信。
DDS_INTERFACE="${DDS_INTERFACE:-}"

# MAVLink 端口（PX4 SITL 的默认约定，别改）：
#   14550 广播给地面站（QGroundControl 自动监听这个）
#   14540 给机载软件 / offboard 控制用，MAVROS 连这个
FCU_URL="udp://:14540@127.0.0.1:14557"

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
  --network host --init --restart=no --read-only
  --ulimit core=0
  --label org.drone-learning-lab.task=px4
  --log-driver json-file --log-opt max-size=10m --log-opt max-file=2
  --shm-size=128m --pids-limit=512
  --tmpfs '/tmp:rw,size=64m,mode=1777'
  -e DISPLAY="${DISPLAY:-}"
  -e QT_X11_NO_MITSHM=1
  -e RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
  -e ROS_LOG_DIR=/tmp/ros-log
  -v "$PX4_ROOT:/px4:ro"
  -v /tmp/.X11-unix:/tmp/.X11-unix:rw
  -w /px4
)
if [[ -n "$DDS_INTERFACE" ]]; then
  common_args+=(
    -e "CYCLONEDDS_URI=<CycloneDDS><Domain><General><Interfaces><NetworkInterface name=\"$DDS_INTERFACE\"/></Interfaces></General></Domain></CycloneDDS>"
  )
fi

in_container() {
  "${D[@]}" exec "$1" bash -lc \
    "source /opt/ros/humble/setup.bash && $2"
}

remove_container() {
  if "${D[@]}" container inspect "$1" >/dev/null 2>&1; then
    "${D[@]}" container stop --time 5 "$1" >/dev/null
    "${D[@]}" container rm "$1" >/dev/null
  fi
}

check_resources() {
  # 检查 Docker 日志所在分区和工作区；不清缓存、不删除任何文件。
  local docker_root
  docker_root="$("${D[@]}" info --format '{{.DockerRootDir}}')"
  /usr/bin/python3 "$SCRIPT_DIR/check-resources.py" "$PX4_ROOT" "$docker_root" "$1"
}

require_free_name() {
  if "${D[@]}" container inspect "$1" >/dev/null 2>&1; then
    echo "容器 $1 已存在。先检查 status / logs，再用 stop 结束原会话。" >&2
    exit 1
  fi
}

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
  check_resources 4
  "${D[@]}" run --rm --network host \
    --name "${SIM_C}_build" --init --restart=no \
    --log-driver json-file --log-opt max-size=10m --log-opt max-file=2 \
    --memory=3g --memory-swap=3g --cpus=2 --pids-limit=512 \
    -e http_proxy="${http_proxy:-}" \
    -e https_proxy="${https_proxy:-}" \
    -e no_proxy="${no_proxy:-}" \
    -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
    -v "$SCRIPT_DIR/build-px4.sh:/build-px4.sh:ro" \
    -v "$PX4_ROOT:/px4" -w /px4 "$IMAGE" \
    bash -lc 'exec timeout --signal=TERM --kill-after=5s 1800s bash /build-px4.sh'
  ;;

start)
  check_resources 4
  require_free_name "$SIM_C"
  # 无论容器叫什么，都拒绝重复启动本项目镜像的仿真。
  active="$("${D[@]}" ps --format '{{.Names}} {{.Image}}')"
  if pgrep -x px4 >/dev/null || [[ "$active" == *local/px4-humble* ]]; then
    echo '已有 PX4 项目进程或容器在运行，请先结束原会话。' >&2
    exit 1
  fi
  build="$PX4_ROOT/PX4-Autopilot/build/px4_sitl_default"
  [[ -x "$build/bin/px4" && -f "$build/rootfs/gz_env.sh" && -d "$build/etc" ]] || {
    echo '缺少 PX4 二进制、etc 或 gz_env.sh；拒绝在启动时隐式编译。' >&2
    exit 1
  }
  headless=1
  if [[ "${PX4_GUI:-0}" == 1 ]]; then
    need_display
    headless=''
  fi
  echo "→ 启动 $SIM_C；最长 ${SESSION_SECONDS}s，内存上限 3 GiB。"
  # 不运行 make target 的交互 pxh：stdin=/dev/null 会造成 EOF 提示符循环。
  # -d 关闭 pxh；加载构建生成的资源路径，显式指定 etc 和可写工作目录。
  # ULog/参数放在 256 MiB tmpfs，容器删除后消失，不写入宿主机工作区。
  # 单引号内的变量只应在容器中展开。
  # shellcheck disable=SC2016
  "${D[@]}" run -d --name "$SIM_C" "${common_args[@]}" "${dri_args[@]}" \
    --memory=3g --memory-swap=3g --cpus=4 \
    --tmpfs /px4-runtime:rw,size=256m,mode=1777 \
    --tmpfs /root/.gz:rw,size=64m \
    -e HEADLESS="$headless" -e GZ_IP=127.0.0.1 -e GZ_PARTITION=drone_lab_px4 \
    -e PX4_SIM_MODEL=gz_x500 -e PX4_SESSION_SECONDS="$SESSION_SECONDS" "$IMAGE" \
    bash -ec '
      build=/px4/PX4-Autopilot/build/px4_sitl_default
      source "$build/rootfs/gz_env.sh"
      exec timeout --signal=TERM --kill-after=5s "${PX4_SESSION_SECONDS}s" \
        "$build/bin/px4" -d -w /px4-runtime "$build/etc"
    '
  echo "容器创建完成；运行/飞行尚未验收。检查：bash $0 status"
  echo "会话限时 ${SESSION_SECONDS} 秒；ULog 和参数仅在内存中，结束前按需导出。"
  ;;

mavros)
  check_resources 1
  require_free_name "$MAVROS_C"
  [[ "$("${D[@]}" inspect --format '{{.State.Running}}' "$SIM_C")" == true ]] || {
    echo "请先启动 $SIM_C。" >&2
    exit 1
  }
  echo "→ 启动 $MAVROS_C（MAVLink → ROS 2 话题）"
  "${D[@]}" run -d --name "$MAVROS_C" "${common_args[@]}" \
    --memory=768m --memory-swap=768m --cpus=1 "$IMAGE" \
    bash -lc "source /opt/ros/humble/setup.bash && \
      exec timeout --signal=TERM --kill-after=5s '${SESSION_SECONDS}s' \
      ros2 launch mavros px4.launch fcu_url:='$FCU_URL'"
  echo "   连接的是 $FCU_URL"
  echo
  echo "✅ 验收：bash $0 status，/mavros/state 应该有数据且 connected=True"
  ;;

status)
  echo "--- 容器 ---"
  "${D[@]}" ps -a --filter "name=^/${SIM_C}$" --filter "name=^/${MAVROS_C}$" \
    --format '{{.Names}}\t{{.Status}}' || true
  if "${D[@]}" ps --format '{{.Names}}' | grep -qx "$SIM_C"; then
    echo "--- 容器内进程（应有 px4 和 gz）---"
    "${D[@]}" exec "$SIM_C" bash -lc \
      "ps -eo comm= | sort -u | grep -E '^(px4|gz|ruby)' || echo '(没有 px4/gz 进程 —— 看 logs)'"
    echo "--- GPU 设备（空 = Gazebo 会退化成软件渲染）---"
    "${D[@]}" exec "$SIM_C" bash -lc 'ls /dev/dri 2>/dev/null | tr "\n" " " || echo "(无)"'
    echo
  fi
  if "${D[@]}" ps --format '{{.Names}}' | grep -qx "$MAVROS_C"; then
    echo "--- MAVROS 话题数 ---"
    in_container "$MAVROS_C" 'timeout 8 ros2 topic list 2>/dev/null | grep -c mavros || true'
    echo "--- 连接状态（等 3 秒取一帧）---"
    in_container "$MAVROS_C" \
      'timeout 8 ros2 topic echo --once /mavros/state 2>/dev/null | grep -E "connected|mode" || echo "(取不到 —— PX4 可能还没起来)"'
  fi
  ;;

logs)
  /usr/bin/python3 "$SCRIPT_DIR/bounded-logs.py" "$SIM_C" "${2:-60}"
  ;;

shell)
  "${D[@]}" exec -it "$SIM_C" bash
  ;;

stop)
  for c in "$SIM_C" "$MAVROS_C"; do
    remove_container "$c"
    echo "→ 已停止并删除 $c"
  done
  ;;

*)
  sed -n '2,9p' "$0"
  exit 1
  ;;
esac
