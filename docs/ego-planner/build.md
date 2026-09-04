# 第二步：编译 EGO-Planner 工作空间

::: tip 这一页你会得到什么
一个编译完成的 ROS 2 工作空间（20 个包全部成功），以及"ROS 2 工程是怎么组织起来的"这套心智模型。

前置：已完成 [第一步：搭环境](/getting-started/environment)，`local/ego-planner-humble:latest` 镜像存在。
预计时间：首次 10~20 分钟，其中你只需要敲 2 条命令。
:::

## 1. 先把源码放对位置

ROS 2 的工作空间有固定结构，**源码必须放在 `src/` 下面**，这不是习惯，是 `colcon` 的硬要求。

```bash
mkdir -p /home/yusei/Documents/Codex/ego-humble/src
cd /home/yusei/Documents/Codex/ego-humble/src
git clone -b ros2_version https://github.com/ZJU-FAST-Lab/ego-planner-swarm.git
```

`-b ros2_version` 是关键。这个仓库的默认分支是 ROS 1 版本，**直接 clone 会拿到跑不起来的代码**。

确认你拿到的是对的东西：

```bash
cd /home/yusei/Documents/Codex/ego-humble/src/ego-planner-swarm
git branch --show-current
git log -1 --format='%H %ad' --date=short
```

本项目实际使用的版本【运行验证】：

```
ros2_version
23a8d5a191711dd65633df689bd00f55d4dea8f9 2025-03-08
```

::: warning 这是别人的代码，规矩要守
EGO-Planner 由浙江大学 FAST-Lab 开发，采用 **GPL-3.0** 许可。本项目只是**学习复现**：源码不进本仓库（`.gitignore` 排除），不改动第三方文件，不把上游 README 当成自己的内容。你在自己项目里用它时，也要保留 `LICENSE` 和作者信息。
:::

## 2. 工作空间的三个目录

编译前只有 `src/`，编译后会多出两个：

| 目录 | 谁生成 | 内容 | 能删吗 |
| --- | --- | --- | --- |
| `src/` | 你（clone 来的） | 源代码 | ❌ 删了就没了 |
| `build/` | colcon | 编译中间产物（`.o`、CMake 缓存） | ✅ 能删，重编即可 |
| `install/` | colcon | 最终产物：可执行文件、launch 文件、`setup.bash` | ✅ 能删，重编即可 |

::: tip 记忆方法
`src` 是**菜**，`build` 是**厨房里的一片狼藉**，`install` 是**端上桌的菜**。ROS 运行时只吃 `install/` 里的东西——所以后面所有命令都要 `source install/setup.bash`，而不是指向 `src/`。
:::

这三个目录都在**宿主机**上（`/home/yusei/Documents/Codex/ego-humble/`），通过 `-v` 挂载进容器。所以**删容器不会丢编译结果**，这是这套方案很省心的一点。

## 3. 编译脚本逐行读

存成工作空间根目录下的 `build-workspace.sh`：

```bash
#!/usr/bin/env bash
set -eo pipefail
source /opt/ros/humble/setup.bash
set -u
rosdep update
rosdep install --from-paths src --ignore-src -r -y --rosdistro humble \
  --skip-keys "Armadillo Boost Eigen3 PCL"
colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release
```

只有 5 行有效代码，但每一行都是踩过坑之后的结果。

### 3.1 为什么 `set -u` 在 source 之后

第一行是 `set -eo pipefail`（**没有 `u`**），source 完 ROS 之后才补上 `set -u`。这是个真实踩过的坑。

`set -u` 的意思是"用到未定义的变量就报错退出"，平时是好习惯。但 **ROS 的 `setup.bash` 内部会读一些可能不存在的变量**（比如 `AMENT_TRACE_SETUP_FILES`、`COLCON_TRACE`），在 `set -u` 下会直接把脚本打死，报错还很难懂。可以自己复现一遍【运行验证】：

```bash
sudo docker run --rm local/ego-planner-humble:latest \
  bash -c 'set -euo pipefail; source /opt/ros/humble/setup.bash; echo OK'
```

输出（注意没有 `OK`，脚本在 source 里就死了）：

```
/opt/ros/humble/setup.bash: line 8: AMENT_TRACE_SETUP_FILES: unbound variable
```

所以顺序必须是：**先宽松地 source，再收紧检查**。

::: tip 这条经验能复用
以后凡是在严格模式的脚本里 source 第三方环境文件（ROS、conda、nvm），都要考虑临时放开 `set -u`。不是你的脚本写错了，是别人的脚本没按严格模式写。
:::

### 3.2 rosdep 是干什么的

`rosdep` 帮你读每个包的 `package.xml`，把里面声明的依赖翻译成 apt 包名并安装。

```bash
rosdep update      # 下载依赖数据库（第一次必须做）
rosdep install --from-paths src --ignore-src -r -y --rosdistro humble \
  --skip-keys "Armadillo Boost Eigen3 PCL"
```

| 参数 | 含义 |
| --- | --- |
| `--from-paths src` | 扫描 `src/` 下所有 `package.xml` |
| `--ignore-src` | 工作空间里已有的包不当成外部依赖去 apt 装 |
| `-r` | **出错也继续**（下面会讲为什么这个很关键） |
| `-y` | 自动确认，不停下来问 |
| `--rosdistro humble` | 按 Humble 的依赖表解析 |
| `--skip-keys "..."` | 跳过这几个解析不了的 key |

### 3.3 `--skip-keys` 是在补上游的坑

上游的 `package.xml` 里写的是 **CMake 包名**（首字母大写），而 rosdep 认的是**小写的 rosdep key**。比如 `plan_env/package.xml` 里写着：

```xml
<depend>Eigen3</depend>
<depend>PCL</depend>
<depend>OpenCV</depend>
```

但 rosdep 的数据库里根本没有这些名字。可以自己验证【运行验证】：

```bash
sudo docker run --rm local/ego-planner-humble:latest bash -c '
  source /opt/ros/humble/setup.bash
  rosdep update --rosdistro humble >/dev/null 2>&1
  for k in Eigen3 PCL eigen; do printf "%-8s -> " $k; rosdep resolve $k 2>&1 | tr "\n" " "; echo; done'
```

真实输出——**大写的查不到，小写的能查到**：

```
Eigen3   -> ERROR: no rosdep rule for 'Eigen3'
PCL      -> ERROR: no rosdep rule for 'PCL'
eigen    -> #apt libeigen3-dev
```

不加 `--skip-keys` 时，`rosdep check` 会报出 18 个包的错误【运行验证，节选】：

```
ERROR[bspline_opt]: Cannot locate rosdep definition for [Eigen3]
ERROR[ego_planner]: Cannot locate rosdep definition for [PCL]
ERROR[pose_utils]: Cannot locate rosdep definition for [Armadillo]
ERROR[mockamap]: Cannot locate rosdep definition for [Boost]
...
```

**所以本项目的解法是两步走**：这 4 个库在 [第一步](/getting-started/environment) 的 Dockerfile 里已经用真名装好了（`libpcl-dev`、`libarmadillo-dev` 等），再用 `--skip-keys` 告诉 rosdep "这几个别管，我自己搞定了"。

::: warning 加了 skip-keys 也还有 2 个错，而且我没去修
```
ERROR[drone_detect]: Cannot locate rosdep definition for [OpenCV]
ERROR[odom_visualization]: Cannot locate rosdep definition for [tf]
```

`OpenCV` 同样是大写 key，`tf` 更有意思——**这是 ROS 1 的包名**（`odom_visualization/package.xml:17` 里的 `<depend>tf</depend>`），ROS 2 里它叫 `tf2`。这是上游从 ROS 1 移植过来时漏掉的一行。

**为什么还是编译成功了**：靠的是 `-r` 那个参数，它的官方说明就是 `Continue installing despite errors.`。而这两个依赖实际上都不缺——OpenCV 被 `ros-humble-desktop` 里的 `cv_bridge` 带进来了，`tf` 这一行则纯属死代码（源码里用的是 tf2）。

**不去修的理由**：改它就要动第三方 `package.xml`。已经能跑通的东西，不要为了消掉两条警告去改别人的代码。**但要知道它在那里**，否则下次看到这两行会白花时间。
:::

### 3.4 colcon build 的两个参数

```bash
colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release
```

| 参数 | 作用 | 去掉会怎样 |
| --- | --- | --- |
| `--symlink-install` | `install/` 里的 launch、config、Python 文件用**软链接**指回 `src/`，不是拷贝 | 改一个 launch 参数都要重新 `colcon build` 才生效 |
| `-DCMAKE_BUILD_TYPE=Release` | 开 `-O3` 优化编译 | 默认无优化，规划耗时会从 0.5 ms 变成几十 ms，仿真直接卡住 |

::: tip `--symlink-install` 值多少钱
后面你要反复改 `single_run_in_sim.launch.py` 里的航点、速度、障碍物数量。有软链接的话**改完直接重启就生效**；没有的话每次都要等一遍编译。这是本项目最省时间的一个参数。

注意它只对"不用编译的文件"有效。改了 **C++ 源码**还是必须重新 `colcon build`。
:::

::: warning Release 不是可选项
EGO-Planner 的卖点就是快（单次优化 0.5 ms）。这个数字是 `-O3` 换来的。用 Debug 编译跑这个仿真，你会以为算法很慢——**其实是你的编译选项在骗你**。
:::

## 4. 开始编译（两条命令）

```bash
cd /home/yusei/Documents/Codex/ego-humble
chmod +x build-workspace.sh
./docker-run.sh bash ./build-workspace.sh
```

`./docker-run.sh`（见 [第一步第 8 节](/getting-started/environment)）负责起容器并把工作空间挂成 `/workspace`，`bash ./build-workspace.sh` 是在容器里执行的命令。**编译发生在容器里，产物落在宿主机上**。

成功的结尾长这样【运行验证：本项目 20 个包全部成功】：

```
Summary: 20 packages finished [...]
```

关键是这一行里**没有 `failed`**。如果有 `N packages failed`，先看它列出的包名，再去 [构建期问题](/debugging/docker-build) 对照。

::: warning 编译期间机器会很吵
20 个 C++ 包并行编译会吃满 CPU（本机 i9-13980HX，风扇全速）。这是正常的。内存 16 GB 足够，但如果你的机器内存小于 8 GB，可能需要加 `--parallel-workers 2` 限制并发，否则会 OOM。
:::

## 5. 验收项 1：源码侧 20 个包都被认出来了

```bash
sudo docker exec ego_rviz bash -lc 'cd /workspace && colcon list --names-only'
```

真实输出【运行验证】：

![colcon list 列出 20 个包](/img/term-colcon-list.png)

数一下正好 20 个。这一步只证明 **colcon 找到了这些包**，还不证明编译成功。

## 6. 验收项 2：编译产物真的能被 ROS 找到

这一步才是真验收。

```bash
sudo docker exec ego_rviz bash -lc \
  'source /opt/ros/humble/setup.bash && source /workspace/install/setup.bash && \
   ros2 pkg list | grep -e ego_planner -e traj_utils -e plan_env \
                        -e path_searching -e bspline_opt -e poscmd_2_odom && \
   echo && ros2 pkg prefix ego_planner'
```

真实输出【运行验证】：

![ros2 pkg list 与 pkg prefix](/img/term-pkg-verify.png)

两件事被证明了：

1. `ros2 pkg list` 能列出这些包 → `install/setup.bash` 生效了，ROS 认识它们。
2. `ros2 pkg prefix ego_planner` 返回 `/workspace/install/ego_planner` → 用的是**我们自己编译的那份**，不是系统里某个同名包。

::: tip `ros2 pkg prefix` 是排错利器
以后遇到"明明改了代码却没生效"，先跑一次 `ros2 pkg prefix <包名>`。如果它指向 `/opt/ros/humble/...` 而不是你的 `install/`，说明 source 顺序错了——**必须先 source ROS，再 source 工作空间**，后 source 的优先级更高。
:::

## 7. 一个必踩的坑：目录名 ≠ 包名

对照 `colcon list` 的输出和 `src/` 下的目录名，会发现两处对不上【源码确认】：

| 目录 | `package.xml` 里的 `<name>` | 
| --- | --- |
| `src/planner/plan_manage/` | `ego_planner` |
| `src/uav_simulator/fake_drone/` | `poscmd_2_odom` |

**ROS 只认 `package.xml` 里的 `<name>`，目录名随便起。** 所以 `ros2 launch ego_planner ...` 对应的源码在 `plan_manage/` 里；`poscmd_2_odom` 这个"假飞控"节点的源码在 `fake_drone/` 里。

::: warning 这直接影响你找代码的效率
想改规划器主逻辑，`find src -name plan_manage` 找目录；想跑起来，`ros2 launch ego_planner` 用包名。**搞混这两者会让你在 `src/` 里翻半小时找不到 `ego_planner` 目录——因为它不存在。**

正确的查法：

```bash
grep -rl '<name>ego_planner</name>' /home/yusei/Documents/Codex/ego-humble/src --include=package.xml
```
:::

## 8. 这 20 个包分别是什么

编译出来的 20 个包，**单机仿真只用到 13 个**。先看清楚谁是谁，读源码时才不会乱找。

**规划相关（`src/planner/`）——这是你要重点读的部分：**

| 包 | 目录 | 干什么 | 单机仿真用到 |
| --- | --- | --- | --- |
| `ego_planner` | `plan_manage/` | 状态机 + launch 文件 + `traj_server`，总调度 | ✅ 核心 |
| `bspline_opt` | `bspline_opt/` | B 样条轨迹优化（rebound 那一套） | ✅ 核心 |
| `path_searching` | `path_searching/` | A\* / 动力学路径搜索，给优化器出初值 | ✅ 核心 |
| `plan_env` | `plan_env/` | 栅格地图、膨胀、ESDF，"世界长什么样" | ✅ 核心 |
| `traj_utils` | `traj_utils/` | 轨迹消息定义 + 可视化 Marker | ✅ |
| `drone_detect` | `drone_detect/` | 集群里互相看见对方 | ❌ 单机不用 |
| `rosmsg_tcp_bridge` | `rosmsg_tcp_bridge/` | 多机之间用 TCP 转发消息 | ❌ 单机不用 |

**仿真器相关（`src/uav_simulator/`）——只要知道它们在假装什么：**

| 包 | 目录 | 干什么 | 单机仿真用到 |
| --- | --- | --- | --- |
| `map_generator` | `map_generator/` | `random_forest`，造柱子和圆环 | ✅ |
| `local_sensing` | `local_sensing/` | `pcl_render_node`，假深度相机 | ✅ |
| `poscmd_2_odom` | `fake_drone/` | 假飞控：指令即状态 | ✅ |
| `odom_visualization` | `Utils/odom_visualization/` | 画无人机模型和历史轨迹 | ✅ |
| `quadrotor_msgs` | `Utils/quadrotor_msgs/` | 自定义消息（`PositionCommand` 等） | ✅ 库 |
| `pose_utils` | `Utils/pose_utils/` | 位姿数学（用 Armadillo） | ✅ 库 |
| `uav_utils` | `Utils/uav_utils/` | 杂项工具函数 | ✅ 库 |
| `cmake_utils` | `Utils/cmake_utils/` | CMake 辅助脚本 | ✅ 库 |
| `mockamap` | `mockamap/` | **另一种**地图生成器（分形地图） | ❌ 有开关 |
| `so3_quadrotor_simulator` | `so3_quadrotor_simulator/` | **真的有动力学**的四旋翼仿真器 | ❌ 有开关 |
| `so3_control` | `so3_control/` | 配套的 SO(3) 控制器 | ❌ 有开关 |
| `multi_map_server` | `Utils/multi_map_server/` | 多机地图服务 | ❌ 单机不用 |
| `waypoint_generator` | `Utils/waypoint_generator/` | 航点生成节点 | ❌ 这个 launch 没用 |

::: tip 重要发现：这个仿真其实能开物理引擎
`so3_quadrotor_simulator` 和 `mockamap` 不是死代码，它们被 **launch 开关**控制着【源码确认】：

| 开关 | 默认值 | 为 `False` 时 | 为 `True` 时 |
| --- | --- | --- | --- |
| `use_dynamic` | `False`（`single_run_in_sim.launch.py:37`） | `poscmd_2_odom`（指令即状态，无物理） | `so3_quadrotor_simulator` + `so3_control`（**有动力学**） |
| `use_mockamap` | `False`（`:33`） | `random_forest`（柱子 + 圆环） | `mockamap_node`（分形地图） |

实现方式是 `condition = UnlessCondition(use_dynamic)` / `IfCondition(use_dynamic)` 挂在节点上【源码确认：`simulator.launch.py:185` 和 `:121`】——**条件成立才创建这个节点**。

所以想看"带动力学"的版本，不用改代码，命令行加参数就行：

```bash
ros2 launch ego_planner single_run_in_sim.launch.py use_dynamic:=True
```

【待验证：本项目还没实测过这条路径，节点数和话题都会变】
:::

::: tip 记忆方法：两句话记住 20 个包
**`src/planner/` 是大脑，`src/uav_simulator/` 是假身体。** 大脑里 `ego_planner` 当指挥，`plan_env` 管"世界长什么样"，`path_searching` 管"大概怎么走"，`bspline_opt` 管"走得漂不漂亮"。
:::

## 记忆卡

**卡 1：ROS 2 工作空间**

- 一句话理解：源码放 `src/`，`colcon build` 生成 `build/` 和 `install/`，运行时只吃 `install/`。
- 三个关键词：src 是菜、build 是狼藉、install 是上桌。
- 输入：`src/` 下的若干 `package.xml` + 源码。
- 处理：`rosdep` 装依赖 → `colcon build` 逐包 CMake 编译。
- 输出：`install/setup.bash`，source 它之后 `ros2 pkg list` 才认识这些包。

**卡 2：这次编译的三个坑**

- 一句话理解：坑全在"上游是从 ROS 1 移植过来的"这件事上。
- 三个关键词：`set -u` 顺序、大写 rosdep key、目录名≠包名。
- 输入：一份 ROS 1 时代写法残留的源码。
- 处理：source 前不开 `set -u`；缺的库在 Dockerfile 里按真名装好再 `--skip-keys`；用 `<name>` 而不是目录名找包。
- 输出：`Summary: 20 packages finished`，没有 `failed`。

## 自测题

**1. `install/` 被我误删了，源码还在，损失有多大？**

::: details 答案
只损失一次编译时间（10~20 分钟），重跑 `./docker-run.sh bash ./build-workspace.sh` 即可。`build/` 和 `install/` 都是可再生的，真正不能丢的只有 `src/`。

:::

**2. 为什么 `build-workspace.sh` 第一行是 `set -eo pipefail` 而不是 `set -euo pipefail`？**

::: details 答案
因为 `source /opt/ros/humble/setup.bash` 内部会读未定义的变量（如 `AMENT_TRACE_SETUP_FILES`），在 `set -u` 下会直接报 `unbound variable` 退出。所以先宽松地 source，source 完再 `set -u`。

:::

**3. `--skip-keys "Armadillo Boost Eigen3 PCL"` 到底在跳过什么？**

::: details 答案
跳过上游 `package.xml` 里用 CMake 包名（首字母大写）写的依赖。rosdep 的数据库只认小写 key（`eigen` 而不是 `Eigen3`），查不到就报 `Cannot locate rosdep definition`。这 4 个库已经在 Dockerfile 里按真实 apt 名装好了，所以直接跳过。

:::

**4. 我在 `src/` 里找不到 `ego_planner` 目录，是不是 clone 不完整？**

::: details 答案
不是。ROS 只认 `package.xml` 里的 `<name>`，目录名可以完全不同。`ego_planner` 这个包的目录叫 `plan_manage/`。同理 `poscmd_2_odom` 的目录叫 `fake_drone/`。

:::

**5. 想让仿真带上真实动力学，需要改 C++ 代码吗？**

::: details 答案
不需要。`single_run_in_sim.launch.py:37` 有一个 `use_dynamic` 开关（默认 `False`），启动时加 `use_dynamic:=True` 就会换成 `so3_quadrotor_simulator` + `so3_control`，而不是 `poscmd_2_odom`。节点是用 `IfCondition` / `UnlessCondition` 有条件创建的。

:::

**下一步** → [第三步：跑通单机仿真](/ego-planner/simulation)

