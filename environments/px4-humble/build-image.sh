#!/usr/bin/env bash
# 构建 PX4 SITL 镜像。幂等：已有的层会命中缓存，重跑很快。
set -euo pipefail
cd "$(dirname "$0")"

# 依赖 EGO 镜像作为底座，先检查它在不在，否则报一个能看懂的错
base="local/ego-planner-humble:latest"
if ! sudo docker image inspect "$base" >/dev/null 2>&1; then
  echo "❌ 缺少底座镜像 $base"
  echo "   先执行：bash ../ego-humble/build-image.sh"
  exit 1
fi

exec sudo docker build -t local/px4-humble:latest .
