#!/usr/bin/env bash
# 把一条命令跑在一个干净的 xterm 里再截图。
# 为什么不直接截自己的终端：自己的终端里有大量历史输出和无关内容，
# 截进文档会让读者看不懂；开一个只跑一条命令的新窗口，画面干净且可复现。
#
# 一次性准备（容器重建后要重做）：
#   sudo docker exec -u root ego_rviz \
#     bash -lc 'apt-get install -y -qq --no-install-recommends xterm'
#
# 用法：./capture-term.sh <输出名> '<命令>' [终端行数] [等待秒数]
# 例：  ./capture-term.sh term-node-list 'ros2 node list'
set -euo pipefail

CONTAINER=${CONTAINER:-ego_rviz}
here=$(cd "$(dirname "$0")" && pwd)
name=${1:?用法: capture-term.sh <输出名> '<命令>' [行数] [秒数]}
cmd=${2:?缺少要执行的命令}
rows=${3:-26}
wait_s=${4:-6}

# 踩过的坑：命令被嵌进下面的 echo \"\$ ...\" 里，命令自带双引号会破坏嵌套引号，
# xterm 直接退出、截图拿不到东西。这里提前拦住，给出可行的替代写法。
case "$cmd" in
  *'"'*)
    echo "❌ 命令里不能包含双引号（会破坏 xterm 的嵌套引号，窗口会直接退出）。" >&2
    echo "   替代写法：用 grep 的多个 -e 参数，或把复杂命令先写成脚本再调用。" >&2
    echo "   反例: ros2 topic list | grep \"drone_0\"" >&2
    echo "   正例: ros2 topic list | grep -e drone_0" >&2
    exit 2 ;;
esac

# 自愈：容器重建后 xterm 会消失（Dockerfile 已加入该层，重建镜像后可省略）
sudo docker exec -u root "$CONTAINER" bash -lc \
  'command -v xterm >/dev/null 2>&1 || { echo "→ 容器内缺少 xterm，自动安装一次" >&2; apt-get update -qq && apt-get install -y -qq --no-install-recommends xterm >/dev/null; }'

# -fn 10x20 用的是 X 服务器自带的点阵字体，容器里不用装任何字体
sudo docker exec -u root -d "$CONTAINER" bash -lc \
  "xterm -title EGO_SHOT -fn 10x20 -bg white -fg black -geometry 100x${rows} +sb -e bash -c '
     source /opt/ros/humble/setup.bash
     source /workspace/install/setup.bash
     echo \"\\\$ ${cmd}\"
     ${cmd}
     sleep 600'"

sleep "$wait_s"
"$here/capture-shot.sh" title "$name" EGO_SHOT
sudo docker exec -u root "$CONTAINER" pkill -f 'xterm -title EGO_SHOT' >/dev/null 2>&1 || true
