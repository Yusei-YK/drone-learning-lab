#!/usr/bin/env bash
# 构建 VINS-Fusion 镜像。幂等：已有的层会命中缓存，重跑很快。
set -euo pipefail
cd "$(dirname "$0")"

base="local/ego-planner-humble:latest"
if ! sudo docker image inspect "$base" >/dev/null 2>&1; then
  echo "❌ 缺少底座镜像 $base"
  echo "   先执行：bash ../ego-humble/build-image.sh"
  exit 1
fi

# --network host：Ceres 那一层要从 **GitHub** 下载源码 tarball，得走宿主机的代理，
#   而代理在 127.0.0.1 上。docker build 默认用 bridge 网络，容器里的 127.0.0.1
#   指向容器自己，wget 会**静默等到超时**（和 PX4 编译期 clone eProsima 同一个成因）。
#   host 网络才能让容器里的 127.0.0.1 就是宿主机的 127.0.0.1。
#
# 为什么**不用** --build-arg http_proxy / https_proxy：
#   那两个是 Docker 的预定义 build arg，会对**所有** RUN 步骤生效，
#   于是 apt 也被迫走代理。而本机的代理对 archive.ubuntu.com 是坏的【运行验证】：
#     E: Failed to fetch .../jammy/InRelease  502  Bad Gateway [IP: 127.0.0.1 17892]
#   apt 直连本来是通的，一加全局代理反而全挂。
#
# 所以用一个**自定义**名字的 build arg（GITHUB_PROXY），在 Dockerfile 里只
# 贴在那一条 wget 前面。谁需要代理谁用，互不影响。
exec sudo docker build --network host \
  --build-arg GITHUB_PROXY="${https_proxy:-}" \
  -t local/vins-humble:latest .
