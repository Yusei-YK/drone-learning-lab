# Drone Learning Lab

一个新手在 **Ubuntu 24.04 + ROS 2 Humble（容器）** 上，把自主无人机的三个核心部件从零跑通的完整学习记录 —— 包含可复现的环境脚本和中文教学文档。

| 部件 | 回答什么问题 | 状态 |
| --- | --- | --- |
| **EGO-Planner** | 往哪飞（轨迹规划） | ✅ 已验收 |
| **VINS-Fusion** | 我在哪（视觉惯性定位） | ✅ 已验收 |
| **PX4 SITL + QGC** | 怎么飞（飞控与地面站） | ✅ 已验收 |

三个都能单独跑通了。新增【运行验证】：EGO → px4ctrl 消息适配、实时 MAVROS 定位采样和坐标桥接已通过；【待验证】：px4ctrl 控制器与飞行闭环。详见[闭环接口教程](docs/integration/interfaces.md)。

📖 **网页版文档**：部署在 GitHub Pages（地址见仓库 About 栏 / Actions 部署结果）

## 这个仓库解决什么问题

这些项目的官方教程几乎都基于 **Ubuntu 20.04 + ROS 1 Noetic**（参考项目 FAST-Lab Fast-Drone-250 也是）。如果你的机器是较新的 Ubuntu（本项目是 24.04 + ROS 2 Jazzy），照着官方教程走会处处碰壁，而**把 Noetic 命令机械替换成 ROS 2 命令同样跑不通** —— 这是本项目最早踩到的第一个大坑。

本仓库记录的是**实际走通的那条路**：用 Docker 起一个 ROS 2 Humble 环境，逐个编译并跑通这三个部件，把每一步、每个报错、每个原因都写清楚。

文档的一条原则是：**只写真实遇到的问题，只贴真实跑出的输出。** 每个结论都带证据标签（见下文），你可以按标签决定信任程度。

## 当前状态

### 阶段一：EGO-Planner 单机仿真 —— 已跑通并完成验收【运行验证】

| 项目 | 结果 |
| --- | --- |
| Docker 镜像 | `local/ego-planner-humble:latest`，4.84 GB |
| 编译 | `colcon build` 20 个包全部成功，无 failed |
| 节点 | 8 个节点齐全 |
| 闭环频率 | `pos_cmd` 100.002 Hz（标准差 0.07 ms） |
| 图形 | RViz 硬件渲染，`OpenGl version: 4.6` |
| 规划 | 状态机走通，单次优化 0.512 ms |

### 阶段二：PX4 SITL + 地面站 —— 已跑通并完成起飞验收【运行验证】

| 项目 | 结果 |
| --- | --- |
| Docker 镜像 | `local/px4-humble:latest`，6.27 GB |
| PX4 版本 | v1.15.4，commit 已钉死 |
| 编译 | `make px4_sitl_default` 走到 `[440/440]`，产物 `build/px4_sitl_default/bin/px4` 50 MB |
| Gazebo | Harmonic（`gz sim --versions` → 8.x），`x500_0` 模型加载正常 |
| QGroundControl | v5.1.4，装在宿主机 `~/Applications/QGroundControl` |
| MAVLink | 14550 上实测有 v2 数据流（首字节 `0xfd`，来自 PX4 的 18570） |
| MAVROS | `/mavros/state` → `connected: true` |
| **起飞闭环** | **✅ 解锁 → 悬停 2.65 m → 降落自动上锁** |

起飞验收用了**两个互相独立的来源**交叉确认：飞控 EKF 估计 2.78 m，Gazebo 物理真值 2.65 m，垂直速度 0.019 m/s（稳定悬停）。悬停高度对应 PX4 源码里的 `MIS_TAKEOFF_ALT = 2.5f`【源码确认】。详见 [PX4 环境页第 12 节](docs/px4-sitl/environment.md)。

### 阶段三：VINS-Fusion（视觉惯性里程计）—— 已跑通并完成运行验收【运行验证】

| 项目 | 结果 |
| --- | --- |
| Docker 镜像 | `local/vins-humble:latest`，4.96 GB |
| 上游 | `zinuok/VINS-Fusion-ROS2`，commit `72023bc` 已钉死 |
| Ceres | **从源码编 2.2.0**，apt 的 2.0.0 缺 Manifold API，编不过 |
| 编译 | 4 个包全部成功，`Summary: 4 packages finished [1min 12s]` |
| EuRoC 数据集 | `MH_01_easy` 已转 ROS 2 bag（rosbags 0.11.5，`--dst-version 6`） |
| 数据核对 | `/imu0` 36820 帧、`/cam0|cam1/image_raw` 各 3682 帧（10:1，符合 200Hz IMU / 20Hz 相机） |
| **运行验收** | **✅ 输出 1009 个位姿，`solver costs 7~8 ms`** |
| 精度 | 轨迹范围 10.76 × 6.42 × 2.22 m（机械厅尺度），20+ m 行程累积漂移约 0.4 m |

这 0.4 m 是**真实的闭环精度**：已确认日志里没有任何 `restart` / `failure` / `lost` / `relocal`，排除了"跟踪丢失后重初始化导致终点恰好回到原点"这种假象。详见 [VINS 环境页第 7.3 节](docs/vins-fusion/environment.md)。

**还没装、也暂时不装：** RealSense 实机驱动、Isaac Sim、MuJoCo。这三个留在[学习路线](docs/getting-started/roadmap.md)里，不进主线。

`px4ctrl` 的 ROS 2 移植（[Ethan-02/px4ctrl-ros2-fast-drone](https://github.com/Ethan-02/px4ctrl-ros2-fast-drone)）源码已钉住。控制器副本已完成独立消息包适配及 Humble 编译修复，原始上游目录未修改；尚未接入飞行控制。对接方案和验收边界见[第七步](docs/integration/interfaces.md)。

## 仓库结构

```text
docs/                        VitePress 中文教学文档（网页版源文件）
├─ index.md                  项目总览
├─ getting-started/
│  ├─ environment.md         第一步：搭 Docker + ROS 2 Humble 环境
│  └─ roadmap.md             学习路线与阶段验收标准
├─ ego-planner/
│  ├─ build.md               第二步：编译工作空间（20 个包）
│  ├─ simulation.md          第三步：跑通单机仿真 + 4 项验收
│  └─ source-reading.md      第四步：读懂源码
├─ px4-sitl/
│  └─ environment.md         第五步：装 PX4 SITL + Gazebo + QGC，含起飞验收
├─ vins-fusion/
│  └─ environment.md         第六步：装 VINS-Fusion，含运行验收
├─ debugging/
│  ├─ docker-build.md        构建期问题（只记录真实遇到的）
│  └─ ego-runtime.md         运行期问题（只记录真实遇到的）
├─ reference/
│  └─ opencv-cuda.md         专题：装的 OpenCV 为什么没有 CUDA
└─ public/img/               真实终端和 RViz 截图

environments/                环境脚本（可直接在仓库里运行，全部幂等）
├─ ego-humble/
│  ├─ Dockerfile             ROS 2 Humble + PCL + Armadillo + 截图工具（三套的底座）
│  ├─ docker/entrypoint.sh   自动 source ROS 环境
│  ├─ fetch-source.sh        克隆 EGO 并钉死 commit 23a8d5a
│  ├─ build-image.sh         构建镜像
│  ├─ build-workspace.sh     rosdep + colcon build
│  ├─ run-sim.sh             起停仿真：start / stop / status / logs
│  ├─ docker-run.sh          起交互容器（路径由 EGO_WORKSPACE 决定）
│  ├─ capture-shot.sh        截 RViz 窗口（容器内 ImageMagick，工具会自愈）
│  └─ capture-term.sh        截干净终端输出（拒绝含双引号的命令）
├─ px4-humble/               FROM ego 镜像，加 PX4 + Gazebo Harmonic + MAVROS
│  ├─ Dockerfile
│  ├─ fetch-source.sh        克隆 PX4-Autopilot 并钉死 v1.15.4
│  ├─ build-image.sh
│  ├─ build-px4.sh           容器里编 px4_sitl_default
│  └─ run-sitl.sh            build / start / mavros / status / logs / shell / stop
└─ vins-humble/              FROM ego 镜像，加 Ceres 2.2.0（源码编）+ rosbags
   ├─ Dockerfile
   ├─ fetch-source.sh        克隆 VINS-Fusion-ROS2 并钉死 commit
   ├─ build-image.sh
   ├─ fetch-dataset.sh       下 EuRoC MH_01_easy 并转成 ROS 2 bag
   ├─ build-workspace.sh     rosdep + colcon build（4 个包）
   └─ run-vins.sh            build / start / play / status / logs / shell / stop
```

三套镜像是**分层**的：`px4-humble` 和 `vins-humble` 都 `FROM local/ego-planner-humble:latest`，复用同一个已验证的 Humble + CycloneDDS 底座，不去动那个能跑的 EGO 镜像。

## 从零复现

前提：Linux + Docker + 一个图形桌面（需要 `DISPLAY`）。**先做阶段一** —— 另外两套镜像都以它为底座。

### 阶段一：EGO-Planner（四条命令）

详细讲解见[环境页](https://yusei-yk.github.io/drone-learning-lab/getting-started/environment)。

```bash
# 1. 拉源码并钉死 commit（顺带把 build-workspace.sh 放进工作空间）
bash environments/ego-humble/fetch-source.sh

# 2. 构建镜像，约 4.84 GB
bash environments/ego-humble/build-image.sh

# 3. 在容器里 rosdep + colcon build，20 个包
bash environments/ego-humble/docker-run.sh bash /workspace/build-workspace.sh

# 4. 起仿真并验收（应看到 7 个节点 + 4 个 GPU 设备）
bash environments/ego-humble/run-sim.sh start
bash environments/ego-humble/run-sim.sh status
```

注意第 3 步必须**在容器里**执行 —— `build-workspace.sh` 会 `source /opt/ros/humble/setup.bash`，宿主机上没有 Humble（本机宿主是 ROS 2 Jazzy）。

### 阶段二：PX4 SITL + Gazebo + 地面站

详细讲解见 [PX4 环境页](docs/px4-sitl/environment.md)。

```bash
bash environments/px4-humble/fetch-source.sh     # 克隆 PX4-Autopilot，钉死 v1.15.4
bash environments/px4-humble/build-image.sh      # 构建镜像，约 6.27 GB
bash environments/px4-humble/run-sitl.sh build   # 容器里编 PX4，走到 [440/440]
bash environments/px4-humble/run-sitl.sh start   # 起 PX4 固件 + Gazebo 物理仿真
bash environments/px4-humble/run-sitl.sh mavros  # MAVLink → ROS 2 话题
```

看画面还要单独起 Gazebo 图形界面（容器里是 root，需要先放开 X 访问）：

```bash
xhost +local:
sudo docker exec -d px4_sitl bash -lc 'gz sim -g'
```

然后 `~/.local/bin/qgroundcontrol &`，点 `Takeoff` 起飞。用完 `xhost -local:` 把权限收回来。

### 阶段三：VINS-Fusion

详细讲解见 [VINS 环境页](docs/vins-fusion/environment.md)。

```bash
bash environments/vins-humble/fetch-source.sh    # 克隆 VINS-Fusion-ROS2，钉死 commit
bash environments/vins-humble/build-image.sh     # 构建镜像，约 4.96 GB（含源码编 Ceres 2.2.0）
bash environments/vins-humble/fetch-dataset.sh   # 下 EuRoC MH_01_easy（2.49 GB）并转 ROS 2 bag
bash environments/vins-humble/run-vins.sh build  # 编 4 个包
bash environments/vins-humble/run-vins.sh start  # 起 vins_node（等数据）
bash environments/vins-humble/run-vins.sh play   # 放数据集喂给它（约 3 分钟）
```

`start` 和 `play` 的顺序不能反 —— 节点要先订阅话题，否则开头几秒的数据没人接。

### 通用说明

所有脚本都是**幂等**的，重复执行不会破坏已有状态。工作空间路径可用环境变量覆盖：

| 变量 | 默认值 |
| --- | --- |
| `EGO_WORKSPACE` | `~/Documents/Codex/ego-humble` |
| `PX4_ROOT` | `~/Documents/Codex/px4-sitl` |
| `VINS_WORKSPACE` | `~/Documents/Codex/vins-humble` |

## 证据标签

文档里每个重要结论都带标签，**请按标签决定信任程度**：

- 【源码确认】读了源码，给出 `文件:行号`，可自行核对
- 【运行验证】在本机真实执行过，附真实输出
- 【推测】合理解释但无直接证据，当思路参考
- 【待验证】还没做过，只是计划

## 本地预览文档

需要 Node.js ≥ 20。

```bash
npm install        # 首次：安装 VitePress 等依赖
npm run docs:dev   # 本地预览，默认 http://localhost:5173
npm run docs:build # 构建静态站点，产物在 docs/.vitepress/dist
```

推送到 `main` 后由 `.github/workflows/deploy-docs.yml` 自动构建并部署到 GitHub Pages。

## 环境前提

文档中的所有结论都来自这一台机器，换环境可能不一致（尤其是显卡设备号和图形转发）：

| 项目 | 值 |
| --- | --- |
| 宿主机系统 | Ubuntu 24.04.3 LTS |
| 宿主机 ROS 2 | Jazzy（不参与本项目） |
| Docker | 29.1.3 |
| 容器内系统 | Ubuntu 22.04.5 + ROS 2 Humble |
| CPU / GPU / 内存 | i9-13980HX / RTX 4060 Laptop 8 GB / 16 GB |
| 桌面会话 | X11（`DISPLAY=:1`） |

## 第三方代码与许可

**EGO-Planner 由浙江大学 FAST-Lab 开发，以 GPL-3.0 授权。**

- 上游仓库：<https://github.com/ZJU-FAST-Lab/ego-planner-swarm>
- 本项目使用分支 `ros2_version`，提交 `23a8d5a191711dd65633df689bd00f55d4dea8f9`
- 相关论文：*EGO-Planner: An ESDF-free Gradient-based Local Planner for Quadrotors*（Zhou et al., RA-L 2020）

算法与实现的功劳全部属于原作者。本仓库**不包含**上游源码副本，也**没有修改**任何第三方文件——源码保留在工作空间 `src/ego-planner-swarm/` 下，以保留其独立 Git 历史、`LICENSE` 和作者署名。文档中所有对源码的引用都注明 `文件:行号`，方便回到原仓库核对。

本仓库自身的原创内容（文档与环境脚本）与上游许可相互独立；引用上游代码片段时均已标注来源。
