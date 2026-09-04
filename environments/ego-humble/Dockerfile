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

RUN rosdep init 2>/dev/null || true
WORKDIR /workspace
COPY docker/entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
