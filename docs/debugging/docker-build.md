# Docker 构建排错

这里只记录已经真实出现的问题，不提前编造解决方案。

## 1. legacy builder 不支持 `--progress`

**现象**

【运行验证】第一次尝试向 legacy builder 传入 `--progress`，参数在真正构建前被拒绝，没有生成镜像。

**原因与处理**

【运行验证】失败发生在 Docker 命令参数层，与 ROS、APT 和 EGO 源码无关。

【源码确认】当前 `build-image.sh` 已移除该参数，只执行：

```bash
sudo docker build -t local/ego-planner-humble:latest .
```

【运行验证】第二次尝试已进入基础镜像拉取，说明这个参数阻塞点已越过，但并不表示镜像构建完成。

## 2. Docker Hub IPv6 连接超时

**现象**

【运行验证】第二次构建在拉取 `ros:humble-ros-base-jammy` 时，通过 IPv6 连接 Docker Hub 超时；本地仍无镜像。

**原因边界**

【运行验证】失败点是 Docker Hub 的 IPv6 网络连接。

【待验证】还不能确定是临时波动、IPv6 路由、Docker daemon 网络设置、DNS 返回顺序还是代理链路。没有证据支持修改 ROS 或 Ubuntu APT 源。

**结果**

【运行验证】配置好代理后重跑 `./build-image.sh`，基础镜像拉取成功，镜像最终构建完成（`local/ego-planner-humble:latest`，4.84 GB）。**这个阻塞点已经解决。**

::: tip 通用经验
镜像拉取失败时，**先分清是"网络到不了"还是"配置写错了"**。看报错里的关键词：出现 `timeout`、`connection refused`、`i/o timeout` 基本都是网络；出现 `unknown flag`、`invalid reference format` 才是命令写错了。这两类的处理方式完全不同，混在一起排查会很浪费时间。
:::

## 3. 编译期的三个坑

镜像好了之后，`colcon build` 阶段还有三个问题，因为它们和编译流程绑得很紧，**完整记录写在 [第二步：编译工作空间](/ego-planner/build)**，这里只列索引：

| 问题 | 一句话原因 | 详见 |
| --- | --- | --- |
| `AMENT_TRACE_SETUP_FILES: unbound variable` | `set -u` 开在 `source` ROS 之前 | [第二步 3.1](/ego-planner/build) |
| `Cannot locate rosdep definition for [Eigen3]` 等 18 条 | 上游 `package.xml` 用了大写的 CMake 包名，rosdep 只认小写 key | [第二步 3.3](/ego-planner/build) |
| 找不到 `pcl_ros` | 镜像里漏装，已补进 Dockerfile 第二个 `RUN` 层 | [第一步 4](/getting-started/environment) |

## 判断边界

这条链子上每一环都要单独验证，**前一环成功不能推断后一环成功**：

```
命令参数正确 → 镜像拉取成功 → 镜像构建完成
→ rosdep 依赖解决 → colcon 20 包编译成功
→ 节点能启动 → 话题在流动 → 规划结果正确
```

【运行验证】截至目前这条链子已经**全部走通**。运行阶段的问题记录在 [运行期问题](/debugging/ego-runtime)。
