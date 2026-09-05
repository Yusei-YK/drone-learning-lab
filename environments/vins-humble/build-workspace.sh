#!/usr/bin/env bash
# 在**容器内**编译 VINS-Fusion 工作空间。宿主机跑不了（需要容器里的 Humble + Ceres）。
# 注意这里**不能**一上来就 set -u（也就是 set -euo pipefail）。
# ROS 2 的 setup.bash 内部会读 AMENT_TRACE_SETUP_FILES 这类没定义的变量，
# 开了 -u 会直接：
#   /opt/ros/humble/setup.bash: line 8: AMENT_TRACE_SETUP_FILES: unbound variable
# 脚本在第一行就退出，**colcon 一次都没跑**，而日志里只有这一句话，
# 看起来像"什么都没发生"。【运行验证】
# 所以先只开 -e，source 完再补上 -u。和 ego-humble/build-workspace.sh 一致。
set -eo pipefail
source /opt/ros/humble/setup.bash
set -u

cd /workspace

echo "=== 环境自检 ==="
echo "ROS_DISTRO: $ROS_DISTRO"
echo "OpenCV:     $(pkg-config --modversion opencv4 2>/dev/null || echo 未知)"
# Ceres 是从源码装到 /usr/local 的，不在 apt 数据库里，所以不能用 dpkg-query 查。
# 版本号写在它自己的 version.h 里，这是最权威的来源。
ceres_h=/usr/local/include/ceres/version.h
if [[ -f "$ceres_h" ]]; then
  echo "Ceres:      $(awk '/CERES_VERSION_(MAJOR|MINOR|REVISION)/{printf "%s.",$3}' "$ceres_h" | sed 's/\.$//') (源码编译，/usr/local)"
else
  echo "Ceres:      ❌ /usr/local 下找不到 Ceres。镜像没建对，先跑 build-image.sh"
  exit 1
fi
# Manifold API 是 Ceres 2.1 才有的，VINS 这份移植全靠它。缺了就没必要往下编。
[[ -f /usr/local/include/ceres/manifold.h ]] || {
  echo "❌ Ceres 没有 manifold.h（版本低于 2.1），编译必然报 'Manifold' is not a member of 'ceres'"
  exit 1
}
echo

echo "=== rosdep 补依赖 ==="
# -r：遇到解析不了的依赖继续往下走，而不是整个中断。
# 第三方 package.xml 里常有写错或已废弃的依赖名，为这个卡住不值得。
rosdep update --rosdistro humble >/dev/null 2>&1 || true
rosdep install --from-paths src --ignore-src -y -r --rosdistro humble || true
echo

# camera_models 必须先编出来，vins / loop_fusion / global_fusion 都依赖它。
# colcon 会自己读 package.xml 算出这个顺序，不用手工指定。
echo "=== colcon build ==="
colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release

echo
echo "=== 验收：4 个包和可执行文件 ==="
set +u; source /workspace/install/setup.bash; set -u   # 同样的原因，见文件开头
for p in camera_models vins loop_fusion global_fusion; do
  if [[ -d "/workspace/install/$p" ]]; then echo "  ✅ $p"; else echo "  ❌ $p 没装上"; fi
done
echo
echo "vins 包里的可执行文件："
ls -1 /workspace/install/vins/lib/vins/ 2>/dev/null || echo "  (没有 —— 编译没真正成功)"

# 把产物属主改回宿主机用户。容器里是 root，不改的话 build/ install/ 全是 root 所有，
# 宿主机上想删掉重编都要密码。在容器内做就不需要宿主机 sudo。
if [[ -n "${HOST_UID:-}" && -n "${HOST_GID:-}" ]]; then
  chown -R "$HOST_UID:$HOST_GID" /workspace/build /workspace/install /workspace/log 2>/dev/null || true
  echo "→ build/ install/ log/ 属主已改回 $HOST_UID:$HOST_GID"
fi
