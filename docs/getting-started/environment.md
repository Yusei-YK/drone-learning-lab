# 第一步：搭一个不会污染宿主机的环境

::: tip 这一页你会得到什么
一个装好 ROS 2 Humble 的 Docker 镜像，以及"为什么非得这么做"的完整理由。做完之后你的宿主机系统一个包都没多装。
预计时间：镜像构建 15~30 分钟（取决于网速），其中你只需要敲 1 条命令。
:::

## 1. 为什么必须用 Docker

这不是为了炫技，是被逼的。

**ROS 2 的版本和 Ubuntu 的版本是硬绑定的**：

| ROS 2 发行版 | 官方绑定的 Ubuntu |
| --- | --- |
| Humble Hawksbill | 22.04 (Jammy) |
| Jazzy Jalisco | 24.04 (Noble) |

本机是 **Ubuntu 24.04.3 + ROS 2 Jazzy**，而 EGO-Planner 的 `ros2_version` 分支是针对 **Humble** 写的。你没法在 24.04 上直接 `apt install ros-humble-*`——官方源里根本没有为 24.04 编译的 Humble 包。

三条路，为什么选第三条：

| 方案 | 问题 |
| --- | --- |
| 重装成 22.04 / 装双系统 | 代价太大，而且以后学 PX4、Isaac 还要换回新系统 |
| 强行在 24.04 上编译 Humble | 依赖地狱，几乎不可能干净收场 |
| **Docker 跑一个 22.04 + Humble 容器** ✅ | 宿主机零污染，删掉容器就等于什么都没发生 |

::: tip 记忆方法
把 Docker 想成"一间租来的房子"：里面怎么装修（装什么包、改什么配置）都不影响你自己的房子（宿主机）。退租（`docker rm`）之后一点痕迹都不留。
:::

## 2. 宿主机基线（本机实测值）

| 项目 | 值 | 怎么查 |
| --- | --- | --- |
| 系统 | Ubuntu 24.04.3 LTS | `cat /etc/os-release` |
| 宿主机 ROS 2 | Jazzy（**不参与本项目**） | `ls /opt/ros/` |
| Docker | 29.1.3 | `sudo docker version` |
| CPU | 13th Gen Intel Core i9-13980HX | `grep 'model name' /proc/cpuinfo` |
| GPU | NVIDIA RTX 4060 Laptop 8 GB | `nvidia-smi` |
| 内存 | 16 GB | `free -h` |
| 桌面会话 | X11，`DISPLAY=:1` | `echo $XDG_SESSION_TYPE` |

::: warning 桌面会话是 X11 还是 Wayland 很重要
后面要把容器里的 RViz 画到你的屏幕上，X11 才好办。如果 `echo $XDG_SESSION_TYPE` 输出 `wayland`，图形转发的做法不一样。本项目全程是 X11。
:::

## 3. 让自己能敲 docker 命令

刚装好 Docker 时，普通用户执行 `docker ps` 会报：

```
permission denied while trying to connect to the Docker daemon socket
```

网上最常见的建议是 `sudo usermod -aG docker $USER`。**本项目故意没这么做。**

原因：`docker` 组的权限**等价于 root**。加入这个组之后，任何程序都能不弹密码地执行 `docker run -v /:/host ...` 把你的整个硬盘挂进容器。这是一次性、永久、无提示的提权。

本项目采用的替代方案是一条**范围收窄**的免密规则（这条命令需要你自己执行，会要求输入密码）：

```bash
echo 'yusei ALL=(root) NOPASSWD: /usr/bin/docker' | sudo tee /etc/sudoers.d/90-yusei-docker
sudo chmod 440 /etc/sudoers.d/90-yusei-docker
```

把 `yusei` 换成你自己的用户名（`whoami` 可以查）。

验证：

```bash
sudo -n -l | tail -3
```

期望看到：

```
(root) NOPASSWD: /usr/bin/docker
```

::: warning 必须诚实说清楚的两件事
1. **这条规则只覆盖 `/usr/bin/docker`**。所以 `sudo apt install ...` 之类的命令**仍然会要求密码**，这是故意的——范围越小越安全。
2. **免密 docker 本质上仍然等于 root 权限**（能挂载任意目录）。它比加入 `docker` 组好，只是因为范围明确、可审计、随时能 `sudo rm /etc/sudoers.d/90-yusei-docker` 撤销。**这是"个人单机学习环境"的折中，不要在共享机器或生产服务器上这么配。**
:::

从此本项目所有 docker 命令都写成 `sudo docker ...`。看到 `sudo` 不要慌，它就是这么来的。

## 4. 镜像里装了什么（逐行读 Dockerfile）

```docker
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
```

每一段为什么存在：

| 内容 | 作用 | 不装会怎样 |
| --- | --- | --- |
| `FROM ros:humble-ros-base-jammy` | 官方 Humble 基础镜像，自带 Ubuntu 22.04 | — |
| `RMW_IMPLEMENTATION=rmw_cyclonedds_cpp` | 指定 DDS 中间件，**写在镜像里，容器和宿主机都一致** | 两边中间件不同时互相看不见话题 |
| `build-essential cmake git` | 编译器和构建工具 | 无法编译 C++ |
| `python3-colcon-common-extensions` | ROS 2 的构建工具 `colcon` | 无法编译工作空间 |
| `python3-rosdep` | 自动解析并安装依赖 | 只能手工一个个找依赖 |
| `ros-humble-desktop` | 包含 RViz2 等图形工具 | 没有 RViz，看不到画面 |
| `ros-humble-rmw-cyclonedds-cpp` | CycloneDDS 的实现本体 | 上面那个环境变量会指向一个不存在的中间件 |
| `libpcl-dev` | 点云库，EGO 的地图和点云处理全靠它 | 编译报找不到 PCL |
| `libvtk9-qt-dev` | PCL 可视化依赖的 VTK | PCL 相关目标链接失败 |
| `libarmadillo-dev` | 线性代数库，`pose_utils` 等包需要 | 编译报找不到 Armadillo |
| `ros-humble-pcl-ros` | PCL 与 ROS 消息的桥接 | 编译报找不到 `pcl_ros`（这是踩过的坑） |
| `rm -rf /var/lib/apt/lists/*` | 删掉 apt 缓存 | 镜像白白大几百 MB |
| `rosdep init \|\| true` | 初始化 rosdep 数据库，失败也不中断构建 | 重复构建时会因"已初始化"而报错中断 |

::: tip 记忆方法：为什么分成两个 RUN
Docker 的每一条 `RUN` 是一层缓存。`ros-humble-pcl-ros` 是后来才发现缺的（编译报错才知道），单独放一层意味着**重新构建时前面那一大层不用重跑**，省十几分钟。这是 Dockerfile 的通用技巧：**新增的、可能还要改的东西放最后面。**
:::

::: warning 关于 `ros-humble-desktop` 的取舍
它体积很大（镜像最终 4.84 GB），装的东西远超"跑仿真"所需。但它包含 RViz2，而这个项目**必须看图**。用 `ros-humble-ros-base` + 单独装 `ros-humble-rviz2` 理论上更小，本项目没有走这条路——**已经能跑通的环境不要为了省几百 MB 去折腾**。
:::

## 5. entrypoint.sh：为什么需要它

```bash
#!/usr/bin/env bash
set -e
source /opt/ros/humble/setup.bash
if [[ -f /workspace/install/setup.bash ]]; then
  source /workspace/install/setup.bash
fi
exec "$@"
```

ROS 2 的命令（`ros2`、`colcon`）不是全局可用的，必须先 `source` 环境脚本，往 `PATH`、`AMENT_PREFIX_PATH` 等变量里塞路径。每次进容器手动 source 两次太烦，所以塞进 ENTRYPOINT——**容器一启动就自动 source 好。**

三个细节：

- `if [[ -f ... ]]`：第一次构建时 `install/` 还不存在（还没编译），不加判断会直接报错退出，连 shell 都进不去。
- `exec "$@"`：把 `docker run` 后面跟的命令接过来执行。`exec` 会**替换**当前进程而不是新开一个子进程，这样容器里的 PID 1 就是你的程序，`docker stop` 发的信号能直接送到它手上。
- `set -e`：source 失败就立刻退出，而不是带着半个环境继续跑。

::: danger 这一节是最容易踩的坑，务必记住
ENTRYPOINT **只在 `docker run` 时执行，`docker exec` 不执行**。所以：

```bash
sudo docker exec ego_sim ros2 node list          # ❌ ros2: command not found
sudo docker exec ego_sim bash -lc \
  'source /opt/ros/humble/setup.bash && \
   source /workspace/install/setup.bash && ros2 node list'   # ✅
```

看到 `ros2: command not found` **不要怀疑 ROS 装坏了**，先看是不是用了 `docker exec` 而忘了 source。
:::

## 6. 构建镜像（你只需要敲这一条）

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
exec sudo docker build -t local/ego-planner-humble:latest .
```

存成 `build-image.sh`，然后：

```bash
chmod +x build-image.sh
./build-image.sh
```

脚本里三个写法值得学：

| 写法 | 含义 | 为什么要 |
| --- | --- | --- |
| `set -euo pipefail` | 出错即停 / 用未定义变量即停 / 管道中任一环失败即停 | 不加的话前面的步骤失败了后面还会继续跑，最后报一个完全无关的错 |
| `cd "$(dirname "$0")"` | 切换到脚本自己所在的目录 | 这样你在任何目录下执行它都对，`docker build .` 的 `.` 才指向 Dockerfile 所在处 |
| `-t local/ego-planner-humble:latest` | 给镜像起名字 | 不起名就只有一串 hash，后面 `docker run` 没法写 |

`local/` 前缀是自己加的约定，表示"这是本地构建的，不是从 Docker Hub 拉的"。

::: warning 构建要花 15~30 分钟，而且很吃网络
中间会下载几 GB 的 apt 包。**中途失败绝大多数是网络问题，不是配置问题**——本项目遇到的第一个坑就是代理，详见 [构建期问题](/debugging/docker-build)。失败了直接重跑 `./build-image.sh`，Docker 会复用已完成的层，不用从头开始。
:::

## 7. 验收：证明镜像是对的

构建完成不等于对。跑这两条命令验收。

**第一条：镜像存在，体积正常**

```bash
sudo docker images --format 'table {{.Repository}}:{{.Tag}}\t{{.Size}}' local/ego-planner-humble:latest
```

本机真实输出【运行验证】：

```
REPOSITORY:TAG                    SIZE
local/ego-planner-humble:latest   4.84GB
```

**第二条：进去问它自己是谁**

```bash
sudo docker run --rm local/ego-planner-humble:latest bash -lc \
  'echo ROS_DISTRO=$ROS_DISTRO; echo RMW=$RMW_IMPLEMENTATION; \
   which ros2 colcon rviz2; lsb_release -ds'
```

本机真实输出【运行验证】：

```
ROS_DISTRO=humble
RMW=rmw_cyclonedds_cpp
/opt/ros/humble/bin/ros2
/usr/bin/colcon
/opt/ros/humble/bin/rviz2
Ubuntu 22.04.5 LTS
```

逐行确认了 5 件事：Humble 装上了、CycloneDDS 生效了、`ros2` 有、`colcon` 有、RViz2 有。

::: tip 最后一行最值得看
容器里是 **Ubuntu 22.04.5**，而你的宿主机是 **24.04.3**。同一台电脑、同一个内核、两个不同版本的 Ubuntu 用户空间同时运行——这就是本页开头那个"版本硬绑定"难题的解法，也是整个 Docker 方案的价值所在，一行输出就证明了。
:::

`--rm` 表示"跑完就删掉这个容器"。验收这种一次性命令都应该加 `--rm`，否则会攒下一堆 `Exited` 的僵尸容器（`sudo docker ps -a` 能看到）。

## 8. 一个方便的交互脚本（可选）

每次手敲那一长串 `docker run` 很痛苦，可以存成 `docker-run.sh`：

```bash
#!/usr/bin/env bash
set -euo pipefail
root_dir="$(cd "$(dirname "$0")" && pwd)"
exec sudo --preserve-env=DISPLAY,HTTP_PROXY,HTTPS_PROXY,NO_PROXY,http_proxy,https_proxy,no_proxy \
  docker run --rm -it \
  --network host --ipc host \
  -e DISPLAY -e QT_X11_NO_MITSHM=1 \
  -e HTTP_PROXY -e HTTPS_PROXY -e NO_PROXY \
  -e http_proxy -e https_proxy -e no_proxy \
  -e RMW_IMPLEMENTATION=rmw_cyclonedds_cpp \
  -v "$root_dir:/workspace" \
  -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
  -w /workspace \
  local/ego-planner-humble:latest "$@"
```

用法：

```bash
./docker-run.sh bash          # 进一个交互 shell
./docker-run.sh ros2 topic list
```

::: danger 这个脚本必须放在工作空间根目录
`root_dir="$(cd "$(dirname "$0")" && pwd)"` 取的是**脚本自己所在的目录**，并把它挂载成 `/workspace`。所以脚本必须和 `src/`、`install/` 放在一起（本项目是 `/home/yusei/Documents/Codex/ego-humble/`）。

本仓库 `environments/ego-humble/` 下的副本只是**留档给你对照抄写**，直接在那里运行会挂错目录，容器里将看不到 EGO 源码。
:::

关于 `sudo --preserve-env=DISPLAY,...`：`sudo` 默认会清空环境变量（安全考虑），所以要显式声明哪些变量允许穿透。`-e DISPLAY`（不带等号和值）的意思是"从当前环境里取同名变量"，两者配合才能把 `DISPLAY=:1` 送进容器。代理那几个变量是构建期留下的，本地跑仿真时没有代理也不影响。

## 记忆卡

**卡 1：为什么用 Docker**

- 一句话理解：ROS 2 版本和 Ubuntu 版本硬绑定，宿主机是 24.04/Jazzy，而 EGO 要 22.04/Humble，所以租一间 22.04 的"房子"。
- 三个关键词：版本绑定、宿主机零污染、删掉即还原。
- 输入：一个 `Dockerfile`。
- 处理：`docker build` 逐层安装 ROS + PCL + Armadillo。
- 输出：`local/ego-planner-humble:latest`（4.84 GB）。

**卡 2：环境是怎么加载的**

- 一句话理解：ROS 命令要先 `source` 才存在，这件事被塞进了 ENTRYPOINT。
- 三个关键词：source、ENTRYPOINT、exec 不走 ENTRYPOINT。
- 输入：`docker run <镜像> <命令>`。
- 处理：`entrypoint.sh` 先 source ROS，再 source `install/`（如果有），然后 `exec "$@"`。
- 输出：一个 ROS 环境已就绪的进程，且它是容器的 PID 1。

## 自测题

**1. 为什么不能直接在 Ubuntu 24.04 上 `apt install ros-humble-desktop`？**

::: details 答案
因为 ROS 2 发行版和 Ubuntu 版本是硬绑定的：Humble 只为 22.04 (Jammy) 编译，Jazzy 只为 24.04 (Noble) 编译。官方源里根本没有面向 24.04 的 Humble 包。

:::

**2. 为什么不用 `sudo usermod -aG docker $USER`？**

::: details 答案
`docker` 组权限等价于 root，而且是永久、无提示的。本项目改用一条只覆盖 `/usr/bin/docker` 的 sudoers 免密规则——范围明确、可审计、能一条命令撤销。但要清楚：免密 `sudo docker` 本身仍然等于 root，只适合个人单机学习环境。

:::

**3. `sudo docker exec ego_sim ros2 node list` 报 `command not found`，为什么？**

::: details 答案
`docker exec` 不执行镜像的 ENTRYPOINT，而 ROS 环境正是在 `entrypoint.sh` 里 source 的。要自己带上 `bash -lc 'source /opt/ros/humble/setup.bash && source /workspace/install/setup.bash && ...'`。

:::

**4. Dockerfile 为什么把 `ros-humble-pcl-ros` 单独放在第二个 `RUN` 里？**

::: details 答案
它是编译报错之后才补上的。Docker 每条 `RUN` 是一层缓存，把后加的东西放最后一层，重新构建时前面那一大层能直接命中缓存，省十几分钟。

:::

**5. `entrypoint.sh` 里为什么要写 `exec "$@"` 而不是直接 `"$@"`？**

::: details 答案
`exec` 用目标程序**替换**当前进程，这样它就是容器的 PID 1，`docker stop` 发的 SIGTERM 能直接送到它手上，容器才能正常退出。不加 `exec` 的话真正的程序是 shell 的子进程，收不到信号。

:::

**下一步** → [第二步：编译工作空间](/ego-planner/build)
