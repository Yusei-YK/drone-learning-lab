# PX4 SITL + Gazebo Garden + MAVROS
#
# 为什么 FROM 已有的 EGO 镜像而不是从头开始：
#   那个镜像里的 ROS 2 Humble + CycloneDDS 已经跑通过完整仿真，是已验证的底座。
#   在它上面加层，Docker 会复用全部已有层——磁盘上不会多出第二份 Humble，
#   而且 EGO 镜像本身一个字节都不会被改动。
#
# 为什么 PX4 也要 Humble：
#   MAVROS 和 EGO 必须在同一个 ROS 发行版里才能直接收发话题。宿主机是 Jazzy，
#   跨版本通信要额外桥接，对新手是纯粹的额外坑。
FROM local/ego-planner-humble:latest

ENV DEBIAN_FRONTEND=noninteractive

# ---- 第 1 层：PX4 官方依赖脚本 ----
# 钉在 v1.15.4，和 fetch-source.sh 拉的源码同一个 tag。
# --no-nuttx     跳过 ARM 交叉编译工具链（约 1 GB，只有刷真实飞控固件才需要）
# --no-sim-tools 跳过它捆绑的 Java + jmavsim（约 600 MB，我们用 Gazebo，不用 jmavsim）
#                被跳过的 Gazebo 那一段在下面手工重做，只挑需要的包
ADD https://raw.githubusercontent.com/PX4/PX4-Autopilot/v1.15.4/Tools/setup/ubuntu.sh /tmp/px4-setup/ubuntu.sh
ADD https://raw.githubusercontent.com/PX4/PX4-Autopilot/v1.15.4/Tools/setup/requirements.txt /tmp/px4-setup/requirements.txt
RUN bash /tmp/px4-setup/ubuntu.sh --no-nuttx --no-sim-tools \
    && rm -rf /tmp/px4-setup /var/lib/apt/lists/*

# ---- 第 2 层：Gazebo Garden ----
# 抄自 ubuntu.sh 里 22.04 的分支（v1.15.4 在 Jammy 上用的是 Garden，不是 Harmonic），
# 但去掉了 ant / openjdk / libvecmath-java —— 那三个只服务 jmavsim。
RUN wget -q https://packages.osrfoundation.org/gazebo.gpg \
      -O /usr/share/keyrings/pkgs-osrf-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/pkgs-osrf-archive-keyring.gpg] http://packages.osrfoundation.org/gazebo/ubuntu-stable $(lsb_release -cs) main" \
      > /etc/apt/sources.list.d/gazebo-stable.list \
    && apt-get update && apt-get install -y --no-install-recommends \
       gz-garden \
       bc dmidecode libeigen3-dev libopencv-dev libxml2-utils pkg-config protobuf-compiler \
       gstreamer1.0-plugins-bad gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
       gstreamer1.0-plugins-ugly gstreamer1.0-libav libgstreamer-plugins-base1.0-dev \
       libimage-exiftool-perl \
    && rm -rf /var/lib/apt/lists/*

# ---- 第 3 层：MAVROS ----
# mavros 是 MAVLink <-> ROS 2 的桥。装完必须再装 GeographicLib 的地磁/大地水准面数据集，
# 否则 mavros_node 一启动就抛 GeographicLib::GeographicErr 异常直接退出。
# 用 mavros 包自带的脚本（而不是从网上另外下一份），保证脚本和包版本一致。
RUN apt-get update && apt-get install -y --no-install-recommends \
       ros-humble-mavros ros-humble-mavros-extras ros-humble-mavros-msgs \
    && rm -rf /var/lib/apt/lists/*
RUN set -eux; \
    script=$(find /opt/ros/humble -name 'install_geographiclib_datasets.sh' | head -1); \
    echo "使用 $script"; bash "$script"

WORKDIR /px4
