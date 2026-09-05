#!/usr/bin/env bash
# 下载 EuRoC MH_01_easy 数据集，并转成 ROS 2 能放的格式。
#
# 为什么需要转换：
#   EuRoC 是 2016 年的数据集，官方发布的是 **ROS 1 bag**（文件头写着 #ROSBAG V2.0）。
#   ROS 2 的 `ros2 bag play` 读不了 ROS 1 bag——两者的容器格式完全不同。
#
# 转换用现成工具，不自己写：
#   `rosbags`（ternaris 维护，纯 Python）提供 rosbags-convert，一条命令搞定，
#   而且**不需要装 ROS 1**。另一个方案 rosbag2_bag_v2 反而要求装 ROS 1，更麻烦。
#
# 为什么不从 ETH 官方地址下：
#   【运行验证】本机到 robotics.ethz.ch 直连超时，走代理 https 返回 code=000。
#   改用 HuggingFace 上的镜像，文件头和体积都和官方一致（2,673,818,914 字节）。
#
# 幂等：文件已存在且体积正确就跳过下载；已转换过就跳过转换。
set -euo pipefail

WORKSPACE="${VINS_WORKSPACE:-$HOME/Documents/Codex/vins-humble}"
DATA_DIR="$WORKSPACE/datasets"
IMAGE="${VINS_IMAGE:-local/vins-humble:latest}"

BAG_NAME="MH_01_easy.bag"
BAG_SIZE=2673818914
BAG_URL="https://huggingface.co/datasets/kavehsgh/EuRoC_MAV_Dataset_Machine_Hall_Easy_01/resolve/main/$BAG_NAME"
OUT_DIR="MH_01_easy_ros2"

mkdir -p "$DATA_DIR"
cd "$DATA_DIR"

# ---- 第 1 步：下载 ----
if [[ -f "$BAG_NAME" ]] && [[ "$(stat -c%s "$BAG_NAME")" == "$BAG_SIZE" ]]; then
  echo "✅ $BAG_NAME 已存在且体积正确（$BAG_SIZE 字节），跳过下载。"
else
  echo "→ 下载 $BAG_NAME（2.49 GB，慢）"
  # -C - 断点续传：网络断了重跑这个脚本会接着下，不从头开始
  # 进度条只在交互式终端里显示。重定向到日志文件时关掉它，
  # 否则 curl 的 \r 刷新会在日志里留下几百行乱码，把真正的报错埋掉。
  quiet=(); [[ -t 1 ]] || quiet=(--no-progress-meter)
  curl -L -C - --retry 5 --retry-delay 5 "${quiet[@]}" -o "$BAG_NAME" "$BAG_URL"
  got=$(stat -c%s "$BAG_NAME")
  if [[ "$got" != "$BAG_SIZE" ]]; then
    echo "❌ 体积不对：期望 $BAG_SIZE，实际 $got。重跑本脚本会续传。"
    exit 1
  fi
  echo "✅ 下载完成，体积校验通过。"
fi

# 顺手确认它真是 ROS 1 bag，而不是一个 HTML 错误页
head -c 12 "$BAG_NAME" | grep -q '#ROSBAG' \
  || { echo "❌ 文件头不是 #ROSBAG，下载到的可能是错误页面。"; exit 1; }

# ---- 第 2 步：转成 ROS 2 bag ----
if [[ -d "$OUT_DIR" ]]; then
  echo "✅ $OUT_DIR 已存在，跳过转换。要重做请先自己删掉该目录。"
else
  echo "→ 用 rosbags-convert 转成 ROS 2 格式（几分钟）"
  # --dst-version 6 不是可选项，是必须的。
  #   rosbags 0.11.5 默认写 metadata 版本 9（对应新发行版），里面
  #     offered_qos_profiles: []        <- 列表
  #   而 Humble 的 rosbag2 期望这里是**字符串**：
  #     offered_qos_profiles: ''
  #   不指定版本的话，bag 数据其实是好的，但一执行 ros2 bag info / ros2 bag play 就报
  #     Exception on parsing info file: yaml-cpp: error at line 25, column 29: bad conversion
  #   ——一个完全看不出跟版本有关的错误。【运行验证】版本 6 是 Humble 能读的格式。
  #
  # 属主问题：容器里是 root，产物会变成 root 所有，宿主机就改不动删不掉了。
  # 解决办法是在**同一个容器里**顺手 chown 回来——而不是在宿主机上 sudo chown。
  # 因为本项目的免密 sudo 规则只覆盖 /usr/bin/docker，`sudo chown` 会卡在要密码。
  sudo docker run --rm -v "$DATA_DIR:/data" -w /data "$IMAGE" \
    bash -lc "rosbags-convert --src /data/$BAG_NAME --dst /data/$OUT_DIR --dst-version 6 \
              && chown -R $(id -u):$(id -g) /data/$OUT_DIR"
  echo "✅ 转换完成。"
fi

echo
echo "=== 验收：ROS 2 bag 里有哪些话题 ==="
sudo docker run --rm -v "$DATA_DIR:/data" "$IMAGE" bash -lc \
  "source /opt/ros/humble/setup.bash && ros2 bag info /data/$OUT_DIR" \
  | grep -E 'Topic|Duration|Messages' | head -20
echo
echo "VINS 需要的三个话题应该在上面：/cam0/image_raw /cam1/image_raw /imu0"
