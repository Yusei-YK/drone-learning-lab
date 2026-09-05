#!/usr/bin/env bash
# 在**宿主机**上装 QGroundControl（地面站）。
#
# 为什么装在宿主机而不是容器：
#   QGC 是个纯 GUI 应用，不需要 ROS。它通过 UDP 14550 收 MAVLink，
#   而我们的 PX4 容器用 --network host，所以 PX4 广播的 14550 对宿主机就是 localhost，
#   QGC 一开就能自动连上。放容器里只是白白多一层图形转发。
#
# 全程不需要 sudo。两个坑都绕开了：
#   坑 1：官方 CloudFront 地址 https://d176tv9ibo4jno.cloudfront.net/latest/... 已返回 403。
#         【运行验证】改用 GitHub Release，可达。
#   坑 2：Ubuntu 24.04 只有 fuse3，没有 libfuse2，AppImage 直接执行会报
#         "dlopen(): error loading libfuse.so.2"。装 libfuse2 要 sudo——
#         这里改用「解包一次再运行」，完全不碰 FUSE，也不用密码。
#
# 幂等：已解包过就跳过。
set -euo pipefail

VERSION="${QGC_VERSION:-v5.1.4}"
ASSET="QGroundControl-x86_64.AppImage"
URL="https://github.com/mavlink/qgroundcontrol/releases/download/$VERSION/$ASSET"

APPS="$HOME/Applications"
APPIMAGE="$APPS/$ASSET"
EXTRACT="$APPS/QGroundControl"
LAUNCHER="$HOME/.local/bin/qgroundcontrol"

mkdir -p "$APPS" "$HOME/.local/bin"

# ---- 第 1 步：下载 ----
if [[ -s "$APPIMAGE" ]]; then
  echo "✅ $ASSET 已存在（$(du -h "$APPIMAGE" | cut -f1)），跳过下载。"
else
  echo "→ 下载 QGroundControl $VERSION（约 200 MB）"
  # 进度条只在交互式终端里显示。重定向到日志文件时关掉它，
  # 否则 curl 用 \r 刷新的那一行会在日志里变成几百个进度片段，把真正的报错埋掉。
  quiet=(); [[ -t 1 ]] || quiet=(--no-progress-meter)
  curl -L -C - --retry 5 --retry-delay 5 "${quiet[@]}" -o "$APPIMAGE" "$URL"
  chmod +x "$APPIMAGE"
fi

# AppImage 是个 ELF 可执行文件，确认下到的不是 HTML 错误页
head -c 4 "$APPIMAGE" | grep -q ELF \
  || { echo "❌ 文件头不是 ELF，下载到的可能是错误页面。删掉重跑。"; exit 1; }

# ---- 第 2 步：解包一次 ----
# --appimage-extract 是 AppImage 自带的功能，不需要 FUSE。
# 只做一次；每次启动都用 --appimage-extract-and-run 会重复解 200 MB，很慢。
if [[ -x "$EXTRACT/AppRun" ]]; then
  echo "✅ 已解包到 $EXTRACT，跳过。"
else
  echo "→ 解包（避开 libfuse2）"
  cd "$APPS"
  "$APPIMAGE" --appimage-extract >/dev/null
  mv squashfs-root "$EXTRACT"
  echo "✅ 解包完成。"
fi

# ---- 第 3 步：写一个启动器 ----
cat > "$LAUNCHER" <<EOF
#!/usr/bin/env bash
# QGroundControl 启动器（由 install-qgc.sh 生成）
exec "$EXTRACT/AppRun" "\$@"
EOF
chmod +x "$LAUNCHER"
echo "→ 启动器：$LAUNCHER"

echo
echo "✅ 装好了。启动："
echo "     qgroundcontrol        # 如果 ~/.local/bin 在 PATH 里"
echo "     $LAUNCHER"
echo
echo "验收步骤："
echo "  1) 先起仿真：bash $(dirname "$0")/run-sitl.sh start"
echo "  2) 再开 QGC，左上角应该从「未连接」变成显示飞机状态"
echo "     （PX4 往 UDP 14550 广播，容器用 --network host，所以对 QGC 就是本机）"
echo
echo "注意：接**真实**飞控（USB 串口）还需要两条要密码的命令，现在用不到："
echo "  sudo usermod -a -G dialout \$USER      # 让自己能读串口"
echo "  sudo apt remove modemmanager          # 它会抢占串口"
