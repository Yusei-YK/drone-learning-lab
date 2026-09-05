#!/usr/bin/env bash
# 钉住 px4ctrl 的 ROS 2 移植版源码 —— **本轮只下载，不编译、不集成**。
#
# px4ctrl 是什么：
#   Fast-Drone-250 里的「翻译层」。EGO-Planner 算出来的是轨迹（位置/速度/加速度），
#   PX4 想要的是姿态和推力指令。px4ctrl 站在中间，跑一个位置+姿态控制器，
#   把轨迹变成 mavros_msgs/AttitudeTarget 发给飞控，同时管遥控器接管、解锁、起飞降落。
#   没有它，EGO 和 PX4 之间是断开的。
#
# 为什么要用移植版：
#   原版 px4ctrl 在 FAST-Lab/Fast-Drone-250 里，是 ROS 1 Noetic 的。
#   Ethan-02/px4ctrl-ros2-fast-drone 是已有的 ROS 2 移植，不用自己重写。
#
# 【源码确认】这个仓库的现状（别抱太高期望，文档里要如实写）：
#   - 分支 master，License GPL-3.0（package.xml 里 license 字段还写着 TODO）
#   - 两个包：src/px4ctrl、src/quadrotor_msgs
#   - px4ctrl/package.xml 是 format="3" + ament_cmake，依赖 mavros_msgs、quadrotor_msgs
#   - 作者 README（中文）说：已实现室内定点、遥控自稳飞行、自动起飞；
#     EGO-planner 那一侧（栅格地图、规划、编队）**没做**，而且写了「可能不会继续了」
#
# 为什么本轮不集成：
#   它自带的 quadrotor_msgs 和 EGO 工作空间里同名的包会冲突 ——
#   同一个 colcon 工作空间里出现两个 quadrotor_msgs，构建会失败或者装错一个。
#   要合并得先决定留哪一份、改哪些消息定义，那是独立一步，不塞进环境搭建里。
#   所以现在只把源码钉在固定 commit 放好，留到「闭环」阶段再动。
set -euo pipefail

DEST_ROOT="${PX4CTRL_ROOT:-$HOME/Documents/Codex/px4ctrl-ros2}"
REPO_URL="https://github.com/Ethan-02/px4ctrl-ros2-fast-drone.git"
BRANCH="master"
COMMIT="85032f11e5f325678cee5c029676c43931281d36"
DEST="$DEST_ROOT/px4ctrl-ros2-fast-drone"

mkdir -p "$DEST_ROOT"

if [[ -d "$DEST/.git" ]]; then
  cur=$(git -C "$DEST" rev-parse HEAD)
  echo "✅ 已存在：$DEST"
  echo "   当前 commit: $cur"
  if [[ "$cur" != "$COMMIT" ]]; then
    # 不自动切：万一你在上面改过东西，切分支会丢。要切请自己执行下面这条。
    echo "⚠️  和钉死的版本不一致（期望 $COMMIT）"
    echo "   如果确认本地没有你自己的改动，手动执行："
    echo "     git -C \"$DEST\" checkout $COMMIT"
    echo "   （不要用 git reset --hard / git clean -fd —— 那会连你自己的文件一起删）"
  fi
else
  echo "→ clone $REPO_URL（很小，几 MB）"
  git clone --branch "$BRANCH" "$REPO_URL" "$DEST"
  git -C "$DEST" checkout "$COMMIT"
fi

echo
echo "=== 验收：包结构 ==="
for p in px4ctrl quadrotor_msgs; do
  if [[ -f "$DEST/src/$p/package.xml" ]]; then
    echo "  ✅ src/$p"
  else
    echo "  ❌ src/$p 不见了"
  fi
done
echo
echo "commit: $(git -C "$DEST" rev-parse --short HEAD)"
echo
echo "下一步不是编译它。本轮到此为止 —— 它的 quadrotor_msgs 会和 EGO 的同名包撞车，"
echo "要等「EGO + PX4 闭环」那一步再决定怎么合并。"
