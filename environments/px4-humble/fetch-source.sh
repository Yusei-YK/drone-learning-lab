#!/usr/bin/env bash
# 拉取 PX4-Autopilot 并钉在 v1.15.4。
#
# 为什么钉 tag 而不是 commit：
#   PX4 有官方发布 tag，tag 在 Git 里是不可变引用，和钉 commit 效果一样，
#   但可读性好得多（v1.15.4 一眼能对应官方 release notes 和文档版本）。
#   EGO 那边只能钉 commit，是因为它的 ros2_version 分支没有发布 tag。
#
# 为什么是 1.15.4 而不是最新：
#   v1.15 是最后一个明确支持 Ubuntu 22.04 (Jammy) 的系列，而我们的容器就是 22.04
#   （因为 ROS 2 Humble 绑定 22.04）。v1.16+ 的依赖脚本面向更新的系统。
#   1.15.4 是这个系列的最后一个补丁版。
#
# 幂等：已经克隆过就只校验 tag，不重新下载、不覆盖你的改动。
#
# 第三方代码：PX4/PX4-Autopilot，BSD-3-Clause。本仓库不复制其源码。
set -euo pipefail

PX4_ROOT="${PX4_ROOT:-$HOME/Documents/Codex/px4-sitl}"
REPO_URL="https://github.com/PX4/PX4-Autopilot.git"
TAG="v1.15.4"
DEST="$PX4_ROOT/PX4-Autopilot"

echo "PX4 根目录: $PX4_ROOT"
echo "目标 tag:   $TAG"

# --------------------------------------------------------------------------
# 补上 NuttX 子模块的 tag。--shallow-submodules 不会带 tag 过来，而 PX4 编译时
# src/lib/version/px_update_git_header.py:138 会这样取 NuttX 版本号：
#     re.findall(r'nuttx-[0-9]+\.[0-9]+\.[0-9]+', nuttx_git_tags)[-1]
# 本地一个 tag 都没有 → findall 返回空列表 → [-1] 直接抛 IndexError，
# 编译在 build_git_version.h 这一步失败。【运行验证】
#
# 只抓最高的那个 tag 就够，而且结果和完整克隆**完全一致**：
# 那行代码把所有 tag 排序后取最后一个，跟 HEAD 在哪个 commit 无关。
# 深度 1 单个 tag 只多占约 1 MB、耗时约 2 秒。【运行验证】
NUTTX_TAG="nuttx-12.12.0"
fix_nuttx_tags() {
  local n="$DEST/platforms/nuttx/NuttX/nuttx"
  [[ -e "$n/.git" ]] || return 0                       # 没有这个子模块就不用管
  [[ -z "$(git -C "$n" tag 2>/dev/null)" ]] || return 0  # 已经有 tag，幂等退出
  echo "→ NuttX 子模块没有 tag，补抓 $NUTTX_TAG（约 1 MB）"
  if git -C "$n" fetch --depth 1 origin tag "$NUTTX_TAG" 2>&1 | tail -2; then
    echo "  ✅ 已补上：$(git -C "$n" tag | tr '\n' ' ')"
  else
    echo "  ⚠️  抓取失败（网络？）。编译会在 build_git_version.h 报 IndexError。"
  fi
}

# build-px4.sh 要在**容器内**执行（它调用容器里的 make 和 cmake），
# 所以放进挂载目录，容器里用 /px4/build-px4.sh 调到。
mkdir -p "$PX4_ROOT"
cp "$(dirname "$0")/build-px4.sh" "$PX4_ROOT/build-px4.sh"
echo "→ 已放置 $PX4_ROOT/build-px4.sh"

if [[ -d "$DEST/.git" ]]; then
  cd "$DEST"
  have=$(git describe --tags --exact-match 2>/dev/null || git rev-parse --short HEAD)
  if [[ "$have" == "$TAG" ]]; then
    echo "✅ 已在 $TAG，无需重新下载。"
  else
    echo "⚠️  当前在 $have，与目标 $TAG 不一致。"
    echo "    未自动切换，避免丢失你的本地改动。请自行确认后执行："
    echo "      cd $DEST && git status && git checkout $TAG && \\"
    echo "        git submodule update --init --recursive"
    exit 1
  fi
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "⚠️  源码有未提交改动。要精确还原某个文件："
    echo "      cd $DEST && git status --short && git checkout -- <文件>"
    echo "    不要用 git reset --hard / git clean -fd。"
  fi
  fix_nuttx_tags
  exit 0
fi

echo "→ 克隆 PX4（含子模块，约 1.5 GB，比 EGO 慢很多）"
# --depth 1 只取一个 commit 的历史；带 --branch <tag> 时 tag 本身会被取到，
# 所以 PX4 构建里的 `git describe` 仍能算出正确版本号。
git clone --depth 1 --branch "$TAG" \
  --recurse-submodules --shallow-submodules \
  "$REPO_URL" "$DEST"

cd "$DEST"
fix_nuttx_tags
echo "✅ 已固定到 $(git describe --tags 2>/dev/null || git rev-parse --short HEAD)"
echo
echo "下一步：在容器里编译"
echo "  bash $(dirname "$0")/run-sitl.sh build"
