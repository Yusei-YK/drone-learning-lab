#!/usr/bin/env bash
# 拉取 VINS-Fusion 的 ROS 2 移植版并钉住 commit。
#
# 为什么不用官方 HKUST-Aerial-Robotics/VINS-Fusion：
#   官方只有 master 一个分支，是 ROS 1（catkin）代码。用它就得自己做 ROS 2 移植——
#   而现成的移植已经有人做了，没必要重写。
#
# 为什么选 zinuok/VINS-Fusion-ROS2：
#   【源码确认】它的 4 个包都是真 ROS 2：package format=3、buildtool 是 ament_cmake、
#   依赖 rclcpp，没有任何 catkin 残留。而且带 config/euroc/ 和 vins/launch/euroc.launch.py，
#   能直接跑公开数据集。
#
# 一个要知道的落差：它的 README 说目标是 Ubuntu 20.04 + ROS 2 Foxy + 带 CUDA 的
#   OpenCV 3.4.1。但【源码确认】feature_tracker.h:14 的 `#define GPU_MODE 1` 已经被
#   注释掉了——README 落后于代码。所以 CPU 模式是默认，不需要 CUDA，也不用改源码。
#   我们在 Humble + OpenCV 4.5（无 CUDA）上编译，这是本项目要实测验证的点之一。
#
# 幂等：已经克隆过就只校验 commit。
#
# 第三方代码：
#   算法与实现属于 HKUST-Aerial-Robotics（VINS-Fusion，GPL-3.0）
#   ROS 2 移植属于 zinuok/VINS-Fusion-ROS2
#   本仓库不复制其源码，只记录如何获取。
set -euo pipefail

WORKSPACE="${VINS_WORKSPACE:-$HOME/Documents/Codex/vins-humble}"
REPO_URL="https://github.com/zinuok/VINS-Fusion-ROS2.git"
BRANCH="main"
COMMIT="72023bc5d2abb14faa4c02a5c040d84f996b587a"
DEST="$WORKSPACE/src/VINS-Fusion-ROS2"

echo "工作空间: $WORKSPACE"
echo "目标 commit: $COMMIT"

# build-workspace.sh 要在容器里跑（它 source /opt/ros/humble），所以放进挂载目录
mkdir -p "$WORKSPACE"
cp "$(dirname "$0")/build-workspace.sh" "$WORKSPACE/build-workspace.sh"
echo "→ 已放置 $WORKSPACE/build-workspace.sh"

if [[ -d "$DEST/.git" ]]; then
  cd "$DEST"
  have=$(git rev-parse HEAD)
  if [[ "$have" == "$COMMIT" ]]; then
    echo "✅ 已在目标 commit，无需操作。"
  else
    echo "⚠️  当前 commit 是 $have，与目标不一致。未自动切换，请确认后执行："
    echo "      cd $DEST && git status && git checkout $COMMIT"
    exit 1
  fi
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "⚠️  源码有未提交改动。精确还原单个文件："
    echo "      cd $DEST && git status --short && git checkout -- <文件>"
    echo "    不要用 git reset --hard / git clean -fd。"
  fi
  exit 0
fi

mkdir -p "$WORKSPACE/src"
echo "→ 克隆 $BRANCH 分支"
git clone --branch "$BRANCH" "$REPO_URL" "$DEST"
cd "$DEST"
git checkout --quiet "$COMMIT"
echo "✅ 已固定到 $(git rev-parse --short HEAD)（分支 $BRANCH）"
echo
echo "下一步：在容器里编译"
echo "  bash $(dirname "$0")/run-vins.sh build"
