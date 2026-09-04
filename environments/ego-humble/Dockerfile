FROM ros:humble-ros-base-jammy

ENV DEBIAN_FRONTEND=noninteractive \
    RMW_IMPLEMENTATION=rmw_cyclonedds_cpp

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake git \
    python3-colcon-common-extensions python3-rosdep python3-vcstool \
    ros-humble-desktop ros-humble-rmw-cyclonedds-cpp \
    libpcl-dev libvtk9-qt-dev libarmadillo-dev \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y --no-install-recommends \
    ros-humble-pcl-ros \
    && rm -rf /var/lib/apt/lists/*

# 截图与终端工具。装在容器里而不是宿主机：容器挂载了 /tmp/.X11-unix
# 并继承 DISPLAY，所以容器内的 ImageMagick 可以直接截宿主机的窗口，
# 宿主机不需要 sudo apt 安装任何东西。
# 早先这三个包是用 docker exec 临时装的，容器一重建就消失；写进 Dockerfile
# 才能跟着镜像走。（本层是新增的，现有镜像未包含，下次 build-image.sh 生效）
RUN apt-get update && apt-get install -y --no-install-recommends \
    imagemagick x11-utils xterm \
    && rm -rf /var/lib/apt/lists/*

RUN rosdep init 2>/dev/null || true
WORKDIR /workspace
COPY docker/entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
