# VINS-Fusion (ROS 2) 的编译依赖
#
# 同样 FROM 已验证的 EGO 镜像，理由见 px4-humble/Dockerfile。
# ros-humble-desktop 已经带了 cv_bridge / image_transport / tf2 / OpenCV，
# 真正缺的是 Ceres 和它的几个数学后端。
# 其中 Ceres 必须**从源码编 2.2.0**，不能用 apt 的 2.0.0，原因见第二层的注释。
FROM local/ego-planner-humble:latest

ENV DEBIAN_FRONTEND=noninteractive

# --------------------------------------------------------------------------
# 第零层：把容器里的 apt 源换成国内镜像。
#
# 这一层不是"为了快"，是**不换根本装不上**。事实链【运行验证】：
#   宿主机上直连 Ubuntu 官方源，80 端口连不上，443 端口能连：
#     http  archive.ubuntu.com/.../InRelease   → 失败（超时）
#     https archive.ubuntu.com/.../InRelease   → 200，4.3 秒
#     http  security.ubuntu.com/.../InRelease  → 失败（超时）
#     http  mirrors.aliyun.com/.../InRelease    → 200，0.33 秒
#   也就是说：这个网络屏蔽（或严重限速）了 Ubuntu 官方源的 **80 端口**。
#
# 而 ubuntu:22.04 基础镜像自带的 sources.list 用的正是 **http://**。
# 于是容器里 apt-get update 报的是：
#   Err:10 http://archive.ubuntu.com/ubuntu jammy/main amd64 Packages
#     Unable to connect to archive.ubuntu.com:80: [IP: 91.189.92.23 80]
# 而下游只会看到一句完全看不出病因的：
#   E: Package 'libgflags-dev' has no installation candidate
#
# 为什么宿主机的 apt 一直是好的：宿主机 24.04 的源写的是 **https://**，走 443。
# 为什么 EGO 镜像当初能建成：它的 apt 层早就编好并被缓存了，之后再没真正跑过 apt。
#   （所以"以前能建"不等于"现在能建"——缓存会掩盖网络退化。）
#
# 为什么不干脆改成 https 官方源：InRelease 要 4.3 秒，实际下载 .deb 时更慢到不可用
# （测了一个 pool 里的包，40 秒超时都没下完）【运行验证】。镜像是 0.2~0.3 秒。
#
# APT_MIRROR 做成 build arg：换网络的读者可以覆盖回官方源，不用改 Dockerfile：
#   sudo docker build --build-arg APT_MIRROR=https://archive.ubuntu.com/ubuntu ...
ARG APT_MIRROR=http://mirrors.aliyun.com/ubuntu
RUN set -eux; \
    sed -i -E "s#https?://(archive|security)\.ubuntu\.com/ubuntu#${APT_MIRROR}#g" \
      /etc/apt/sources.list; \
    grep -c "$APT_MIRROR" /etc/apt/sources.list    # 一条都没替换到就在这里失败，别等 apt 报错

# 注意这里**故意不装 libceres-dev**（apt 版），原因见下面第二层。
#
# libgoogle-glog-dev  Ceres 的日志依赖，不装会在 find_package(Ceres) 阶段失败
# libgflags-dev       同上，命令行参数库
# libsuitesparse-dev  稀疏矩阵求解后端，缺了 Ceres 会退化成很慢的稠密求解
# libeigen3-dev       矩阵库（EGO 镜像里已有，这里显式写出以便读者知道 VINS 也要它）
# wget / ca-certificates  下一层要从 GitHub 下 Ceres 源码用。
#   基础镜像里**没有 wget**【运行验证】，不显式装的话下一层直接：
#     /bin/sh: 1: wget: not found        → returned a non-zero code: 127
#   127 是 shell 的"命令找不到"退出码。看到 127 先怀疑命令没装，而不是参数写错。
#   ca-certificates 是 https 校验证书，缺了 wget 会报证书错误而不是 404，同样容易误判。
# -o Acquire::ForceIPv4=true 也是被 --network host 逼出来的（和上面换源是两件事）。
#   本镜像要用 --network host 构建（为了让 Ceres 那层能用宿主机的代理下 GitHub）。
#   代价是容器继承了宿主机的网络栈，而宿主机**有 IPv6 地址但没有可用的 IPv6 路由**。
#   于是 apt 拿到 AAAA 记录就去连 IPv6，白等一轮超时【运行验证】：
#     Cannot initiate the connection to archive.ubuntu.com:80 (2a06:bc80:0:1000::18).
#       - connect (101: Network is unreachable)
#   强制 IPv4 省掉这轮无用等待。默认 bridge 网络没这问题，因为 bridge 没有 IPv6。
#
#   ⚠️ 注意：当初我先看到这条 IPv6 报错，就以为它是"装不上包"的原因，
#      加了 ForceIPv4 之后**照样失败**，只是报错换成了 `Unable to connect ...:80`。
#      真正的病因是上面第零层写的"80 端口不通"。
#      教训：日志里第一条显眼的错误，不一定是根因。改完要重跑验证，别假定改对了。
RUN apt-get -o Acquire::ForceIPv4=true update \
    && apt-get install -y --no-install-recommends \
       libgoogle-glog-dev \
       libgflags-dev \
       libsuitesparse-dev \
       libeigen3-dev \
       libopencv-dev \
       ros-humble-cv-bridge \
       ros-humble-image-transport \
       ros-humble-tf2-geometry-msgs \
       ca-certificates \
       wget \
    && rm -rf /var/lib/apt/lists/*

# --------------------------------------------------------------------------
# Ceres 2.2.0，从源码编译。为什么不用 apt 的 libceres-dev：
#
# Ubuntu 22.04 的 apt 只有 **Ceres 2.0.0**【运行验证】，而这份 VINS-Fusion ROS 2
# 移植用的是 Ceres **2.1 才引入**的 Manifold API。用 2.0 编译会报：
#   error: ‘Manifold’ is not a member of ‘ceres’
#   error: ‘quaternion_manifold’ was not declared in this scope
#
# 为什么不改代码去适配 2.0：因为 Manifold 不是零星用了几处，而是**贯穿四个包**——
#   vins/src/factor/pose_local_parameterization.h   class ... : public ceres::Manifold
#   camera_models/.../EigenQuaternionParameterization.h  同样继承 ceres::Manifold
#   loop_fusion/src/pose_graph.h                    ceres::AutoDiffManifold<...>
#   global_fusion/src/globalOpt.cpp                 ceres::QuaternionManifold
# 改回 2.0 的 LocalParameterization 要重写 Plus/PlusJacobian/Minus/MinusJacobian
# 四个雅可比函数，而 AutoDiffManifold 在 2.0 里根本没有对等物。
# **雅可比写错不会报错，只会让精度悄悄变差** —— 这种改动风险远大于换一个 Ceres 版本。
#
# 所以正确做法是：给代码它本来就需要的 Ceres 版本，一行第三方源码都不改。
ARG CERES_VERSION=2.2.0
# 为什么不用 -j"$(nproc)"：本机 nproc = 32，但可用内存只有约 8 GB【运行验证】。
# Ceres 是重度模板代码，单个编译单元峰值能吃到 1 GB 上下，32 个并行就是 ~32 GB，
# 必然触发 OOM。而 OOM 的现象非常难认——内核直接 SIGKILL 掉 cc1plus，
# 你看到的可能只是 `c++: fatal error: Killed signal terminated program`，
# 甚至什么都不打印，日志就那么断了，看起来像"卡住"或"网络问题"。
# 6 个并行在 8 GB 上有足够余量，Ceres 总共才两百多个编译单元，慢不了多少。
# 内存大的机器可以自己调：--build-arg CERES_JOBS=16
ARG CERES_JOBS=6
# GITHUB_PROXY 只贴在 wget 这一条上，不做成全局环境变量。
# 用自定义名字（而不是 https_proxy）是故意的：预定义的 http_proxy/https_proxy
# 会让**所有** RUN 都走代理，而本机代理对 archive.ubuntu.com 会返回 502，
# 把原本直连正常的 apt 也搞坏。详见 build-image.sh 的注释。
ARG GITHUB_PROXY=
RUN set -eux; \
    cd /tmp; \
    https_proxy="$GITHUB_PROXY" http_proxy="$GITHUB_PROXY" \
      wget -q "https://github.com/ceres-solver/ceres-solver/archive/refs/tags/${CERES_VERSION}.tar.gz" \
           -O ceres.tar.gz; \
    test -s ceres.tar.gz; \
    tar xf ceres.tar.gz; \
    cmake -S "ceres-solver-${CERES_VERSION}" -B ceres-build \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr/local \
      -DBUILD_TESTING=OFF \
      -DBUILD_EXAMPLES=OFF \
      -DBUILD_BENCHMARKS=OFF; \
    cmake --build ceres-build -j"$CERES_JOBS"; \
    cmake --install ceres-build; \
    rm -rf /tmp/ceres.tar.gz "/tmp/ceres-solver-${CERES_VERSION}" /tmp/ceres-build; \
    test -f /usr/local/include/ceres/manifold.h    # 装错了就在这里失败，别等编译 VINS 才发现

# rosbags：把 EuRoC 的 ROS 1 bag 转成 ROS 2 bag。
# EuRoC 是 2016 年的数据集，只有 ROS 1 bag，而 ros2 bag play 读不了那个格式。
# 这个包是纯 Python 实现，不需要装 ROS 1——这是选它而不是 rosbag2_bag_v2 的原因。
# 版本钉死 0.11.5：转换工具换版本可能改变 CLI 参数或输出布局，那会让文档里的命令和验收输出对不上。
# 【运行验证】这个版本的 rosbags-convert 用 `--src PATH --dst DST`（不是位置参数），
#             容器里 python 3.10.12 满足它 requires_python >=3.10 的要求。
RUN apt-get -o Acquire::ForceIPv4=true update \
    && apt-get install -y --no-install-recommends python3-pip \
    && pip3 install --no-cache-dir 'rosbags==0.11.5' \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
