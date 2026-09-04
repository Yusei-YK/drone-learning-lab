#!/usr/bin/env bash
# 拉取并"钉住"EGO-Planner ROS 2 源码到一个固定 commit。
#
# 为什么需要这个脚本：
#   上游仓库随时会更新。如果只写"git clone 一下"，别人明天复现出来的
#   就不是同一份代码，文档里的行号、错误信息、参数全部对不上。
#   把 commit 写死是"可复现"和"能跑一次"的分界线。
#
# 幂等：已经克隆过就只校验 commit，不重新下载、不覆盖你的改动。
#
# 第三方代码：ZJU-FAST-Lab/ego-planner-swarm，GPL-3.0。
#   本仓库不复制其源码，只记录如何获取。
set -euo pipefail

WORKSPACE="${EGO_WORKSPACE:-$HOME/Documents/Codex/ego-humble}"
REPO_URL="https://github.com/ZJU-FAST-Lab/ego-planner-swarm.git"
BRANCH="ros2_version"
COMMIT="23a8d5a191711dd65633df689bd00f55d4dea8f9"
DEST="$WORKSPACE/src/ego-planner-swarm"

echo "工作空间: $WORKSPACE"
echo "目标 commit: $COMMIT"

# build-workspace.sh 是在**容器内**执行的（它 source /opt/ros/humble），
# 所以要放进工作空间，容器挂载后才能用 /workspace/build-workspace.sh 调到。
mkdir -p "$WORKSPACE"
cp "$(dirname "$0")/build-workspace.sh" "$WORKSPACE/build-workspace.sh"
echo "→ 已放置 $WORKSPACE/build-workspace.sh"

if [[ -d "$DEST/.git" ]]; then
  cd "$DEST"
  have=$(git rev-parse HEAD)
  if [[ "$have" == "$COMMIT" ]]; then
    echo "✅ 已在目标 commit，无需操作。"
  else
    echo "⚠️  当前 commit 是 $have，与目标不一致。"
    echo "    未自动切换，避免丢失你的本地改动。请自行确认后执行："
    echo "      cd $DEST && git status && git checkout $COMMIT"
    exit 1
  fi
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "⚠️  第三方源码有未提交改动（练习改的？）。用下面这条精确还原："
    echo "      cd $DEST && git status --short && git checkout -- <文件>"
    echo "    不要用 git reset --hard / git clean -fd。"
  fi
  exit 0
fi

mkdir -p "$WORKSPACE/src"
echo "→ 克隆 $BRANCH 分支（只取需要的历史）"
git clone --branch "$BRANCH" "$REPO_URL" "$DEST"
cd "$DEST"
git checkout --quiet "$COMMIT"
echo "✅ 已固定到 $(git rev-parse --short HEAD)（分支 $BRANCH）"
echo
echo "下一步：编译工作空间"
echo "  bash $(dirname "$0")/build-workspace.sh"
