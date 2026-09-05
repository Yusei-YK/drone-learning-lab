#!/usr/bin/env bash
# 在**容器内**编译 PX4 SITL。宿主机上跑不了（需要容器里的依赖和 gz-garden）。
#
# 由 run-sitl.sh build 调用；也可以进容器后手动跑 bash /px4/build-px4.sh。
set -euo pipefail

cd /px4/PX4-Autopilot

# ---- 必须放在所有 git 命令之前 ----
# 容器里是 root（uid 0），而挂进来的源码目录属主是宿主机用户（uid 1000）。
# git 2.35.2+ 遇到「仓库属主不是当前用户」会直接拒绝工作：
#   fatal: detected dubious ownership in repository at '/px4/PX4-Autopilot'
# 后果非常隐蔽：PX4 的 CMakeLists.txt:123 用 `git describe` 取版本号，
# 拿到空字符串后 string(REPLACE ...) 参数不够，报一句和 git 毫无关系的
#   string sub-command REPLACE requires at least four arguments
# 用 '*' 而不是逐个列目录，是因为 PX4 有几十个子模块，每个都是独立仓库。
# 只在这个一次性容器里生效，不动宿主机的 git 配置。
git config --global --add safe.directory '*'

echo "=== 环境自检 ==="
echo "cmake:  $(cmake --version | head -1)"
echo "gz sim: $(gz sim --versions 2>/dev/null | head -1 || echo '未找到 —— 镜像可能没建对')"
echo "python: $(python3 --version)"
echo "版本号: $(git describe --tags 2>/dev/null || echo '未知')"
echo

# 版本号取不到就不要往下编译 —— 编出来的固件版本会是 0.0.0，白等十几分钟。
if [[ -z "$(git describe --tags 2>/dev/null)" ]]; then
  echo "❌ git describe 取不到版本号，编译必定在 CMake 阶段失败。先查上面的 safe.directory 设置。"
  exit 1
fi

# NuttX 子模块 tag 自检。--shallow-submodules 克隆不带 tag，而 PX4 生成
# build_git_version.h 时会取 NuttX 的最高 tag，一个都没有就抛 IndexError，
# 编译在第 41 行左右挂掉——而且报错混在几百行并行编译输出里，很难看见。
# 这里 1 秒钟就能提前判死。修法在宿主机侧：fetch-source.sh 的 fix_nuttx_tags。
nuttx=platforms/nuttx/NuttX/nuttx
if [[ -e "$nuttx/.git" && -z "$(git -C "$nuttx" tag 2>/dev/null)" ]]; then
  echo "❌ NuttX 子模块没有任何 git tag，编译必定在 build_git_version.h 失败："
  echo "     IndexError: list index out of range  (px_update_git_header.py:138)"
  echo "   在**宿主机**上执行修复（只下载约 1 MB）："
  echo "     bash environments/px4-humble/fetch-source.sh"
  exit 1
fi

# 编译期联网自检。PX4 的 uxrce_dds_client 用 ExternalProject 在 build 中途
# git clone eProsima 的仓库；网络不通时它**不报错，直接挂住**（CPU 掉到 0%，
# ninja 停在某一行不动），非常难判断。提前 5 秒试一下，省掉盲等。
echo "=== 联网自检（编译中途要 clone eProsima 仓库）==="
if timeout 20 git ls-remote https://github.com/eProsima/Micro-CDR.git HEAD >/dev/null 2>&1; then
  echo "✅ GitHub 可达"
else
  echo "❌ 容器里访问不了 GitHub。编译会在 uxrce_dds_client 那一步静默挂住。"
  echo "   检查 run-sitl.sh build 是否带了 --network host 和 http_proxy/https_proxy。"
  exit 1
fi
echo

# PX4 的 make 自己会并行，不要再手动加 -j，否则容易把 16 GB 内存吃满。
# px4_sitl_default 只编译 SITL 二进制，不启动仿真。
echo "=== 编译 px4_sitl_default（首次约 5~15 分钟）==="
make px4_sitl_default

echo
echo "=== 验收：二进制是否生成 ==="
bin=build/px4_sitl_default/bin/px4
if [[ -x "$bin" ]]; then
  ls -lh "$bin"
  echo "✅ PX4 SITL 编译成功。"
else
  echo "❌ 没找到 $bin，编译没有真正成功。"
  exit 1
fi

# 把产物属主改回宿主机用户。容器里是 root，不改的话 build/ 全是 root 所有，
# 宿主机上想删掉重编都得要密码。在容器内做，就不需要宿主机 sudo。
if [[ -n "${HOST_UID:-}" && -n "${HOST_GID:-}" ]]; then
  chown -R "$HOST_UID:$HOST_GID" /px4/PX4-Autopilot/build
  echo "→ build/ 属主已改回 $HOST_UID:$HOST_GID"
fi
