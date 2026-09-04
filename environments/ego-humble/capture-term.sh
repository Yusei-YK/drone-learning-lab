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
