#!/usr/bin/env bash
# 截图工具（宿主机没有 import/scrot，且 xwd 在本机报 BadColor）。
#
# 思路：RViz 容器已经挂载了 /tmp/.X11-unix 并设置了 DISPLAY=:1，
# 所以在容器里装 ImageMagick 就能截宿主机的 X11 窗口，
# 不需要对宿主机执行 sudo apt install。
#
# 一次性准备（只需执行一次，容器重建后要重做）：
#   sudo docker exec -u root ego_rviz \
#     bash -lc 'apt-get update -qq && apt-get install -y -qq --no-install-recommends imagemagick x11-utils'
#
# 用法：
#   ./capture-shot.sh full   <名字>              # 整个 RViz 窗口
#   ./capture-shot.sh view   <名字>              # 只截 3D 视图（RViz 的 OpenGL 子窗口）
#   ./capture-shot.sh crop   <名字> WxH+X+Y      # 从整窗口里裁剪一块（剪辑用）
#   ./capture-shot.sh title  <名字> <窗口标题>   # 按标题截任意窗口（例如 xterm）
#
# 输出：$WORKSPACE/shots/<名字>.png（宿主机路径见下面 HOST_SHOTS）
set -euo pipefail

CONTAINER=${CONTAINER:-ego_rviz}
MAXW=${MAXW:-1800}          # 输出最大宽度，控制入库图片体积
mode=${1:?用法: capture-shot.sh full|view|crop <名字> [WxH+X+Y]}
name=${2:?缺少输出文件名}
geom=${3:-}

sudo docker exec -u root "$CONTAINER" bash -lc '
set -euo pipefail
mode='"$mode"'; name='"$name"'; geom='"${geom:-}"'; maxw='"$MAXW"'
tree=$(xwininfo -root -tree)
# 顶层 RViz 窗口：标题含 "- RViz"，窗口类是 ("rviz2" "rviz2")
top=$(printf "%s" "$tree" | grep "(\"rviz2\" \"rviz2\")" | grep -- "- RViz" | awk "{print \$1}" | head -1)
# 3D 渲染子窗口：标题就是 "rviz2"
gl=$(printf "%s" "$tree"  | grep "\"rviz2\": (\"rviz2\" \"rviz2\")"  | awk "{print \$1}" | head -1)
case "$mode" in full|view|crop)
  [ -n "$top" ] || { echo "找不到 RViz 窗口，RViz 在运行吗？" >&2; exit 1; } ;;
esac

mkdir -p /workspace/shots
raw=/tmp/raw.png
case "$mode" in
  full) import -window "$top" "$raw" ;;
  view) import -window "$gl"  "$raw" ;;
  crop) import -window "$top" /tmp/win.png; convert /tmp/win.png -crop "$geom" +repage "$raw" ;;
  title)
    w=$(printf "%s" "$tree" | grep -F "\"$geom\":" | grep -v mutter-x11-frames | awk "{print \$1}" | head -1)
    [ -n "$w" ] || { echo "找不到标题为 $geom 的窗口" >&2; exit 1; }
    import -window "$w" "$raw" ;;
  *) echo "未知模式: $mode" >&2; exit 2 ;;
esac
# 界面截图颜色数很少，量化到 256 色能把体积压到 1/3 左右，肉眼看不出差别
convert "$raw" -resize "${maxw}x>" -strip -colors 256 "PNG8:/workspace/shots/${name}.png"
identify -format "%f %wx%h %b\n" "/workspace/shots/${name}.png"
chown -R 1000:1000 /workspace/shots
'
