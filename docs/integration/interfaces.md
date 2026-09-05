# 第七步：先对齐 EGO → px4ctrl → PX4 接口

**本页完成的是消息适配、实时定位采样和坐标桥接，还不是飞行闭环。** 两个新包的编译、隔离 DDS 测试和桥接节点验证已通过；控制器状态机与飞行仍待验收。

## 1. 检查：先看数据流，再决定接什么

**在做什么：**把规划、控制和定位分清。**为什么：**三个模块分别能运行，不代表输入输出能直接连接。

```mermaid
flowchart LR
  G[目标点与障碍物地图] --> E[EGO 与 traj_server]
  E --> A[指令适配器]
  A --> C[px4ctrl]
  C --> M[MAVROS]
  M --> P[PX4 与 Gazebo 飞机]
  P --> O[这架飞机的定位反馈]
  O --> C
  O --> E
```

【待验证】上图是最终接线方案，不是本次已运行的节点图。当前 EuRoC bag 描述录制时的运动，不是 Gazebo 飞机对当前控制指令的响应；不能作为这架仿真飞机的反馈。

**执行了什么：**读本地已钉版本的源码，未修改上游原目录：

| 源码 | 版本 |
| --- | --- |
| EGO | `23a8d5a191711dd65633df689bd00f55d4dea8f9` |
| px4ctrl | `85032f11e5f325678cee5c029676c43931281d36` |
| VINS | `72023bc5d2abb14faa4c02a5c040d84f996b587a` |
| 本机 MAVROS 包 | 【运行验证】`2.14.0-1jammy.20260804.200257` |

以下本地源码路径分别相对于：

```text
EGO:     /home/yusei/Documents/Codex/ego-humble/src/ego-planner-swarm
px4ctrl: /home/yusei/Documents/Codex/px4ctrl-ros2/px4ctrl-ros2-fast-drone
VINS:    /home/yusei/Documents/Codex/vins-humble/src/VINS-Fusion-ROS2
```

**结果与验证：**【源码确认】控制器在 `src/px4ctrl/src/controller.cpp:41` 计算：

```text
期望加速度 = 规划加速度 + Kv × (期望速度 − 实际速度)
                         + Kp × (期望位置 − 实际位置) + 重力补偿
```

它再计算姿态和推力，并非仅做消息转发。

**记住：**规划回答“想去哪”，定位回答“实际在哪”，控制器根据两者的差发指令。**下一步：**解决消息类型冲突。

## 2. 修改：隔离同名消息包，再转换字段

**在做什么：**给控制器副本使用独立的 `px4ctrl_msgs` 包名。**为什么：**同一个 `quadrotor_msgs/PositionCommand` 名字下有两种不同定义；仅改话题名不能解决。

【源码确认】EGO 的 `src/uav_simulator/Utils/quadrotor_msgs/msg/PositionCommand.msg:1` 与 px4ctrl 的 `src/quadrotor_msgs/msg/PositionCommand.msg:1`：

| EGO 字段 | 控制器字段 | 本次转换 |
| --- | --- | --- |
| `position`（Point） | `pos`（Vector3） | 逐个复制 x、y、z |
| `velocity` | `vel` | 逐个复制 |
| `acceleration` | `acc` | 逐个复制 |
| `yaw`、`yaw_dot` | 同名字段 | 原值复制 |
| header、增益、轨迹编号与状态 | 对应字段 | 保留 |
| 没有 | `jerk`、`heading` | 明确置零，不伪装成测量值 |

【源码确认】当前 `src/px4ctrl/src/controller.cpp:29` 的 `LinearControl::calculateControl` 没有使用 jerk/heading。置零策略仅适用于当前实现；换控制算法时必须重新检查。

**执行了什么：**在仓库根目录运行：

```bash
cd /home/yusei/Documents/Codex/drone-learning-lab
bash environments/integration/run-check.sh prepare
```

它从本地 Git 的固定提交导出到 `/home/yusei/Documents/Codex/drone-integration`，仅在生成副本中重命名消息包和引用。保留完整上游许可证，生成 `source-manifest.json` 记录来源、变换和文件 SHA-256。再次执行前先校验已有生成文件；发现手改就停止，不覆盖。

【源码确认】准备脚本还包含一个已实际遇到的 Humble 编译修复：把控制器 `PX4CtrlFSM.cpp:388` 中的 `rclcpp::Duration(秒数)` 改为 `rclcpp::Duration::from_seconds(秒数)`。算法不变。变换规则可以直接在 `environments/integration/prepare.py` 中逐行核对。

**结果是否成功：**【运行验证】生成副本成功；上游 Git 工作区仍干净。

**怎么验证：**

```bash
git -C /home/yusei/Documents/Codex/px4ctrl-ros2/px4ctrl-ros2-fast-drone status --short
cat /home/yusei/Documents/Codex/drone-integration/source-manifest.json
```

**记住：**改动集中在自己的准备脚本，不污染固定版本的源码。**下一步：**只编译新增包。

## 3. 构建：只编两个新包

**在做什么：**编 `px4ctrl_msgs` 和 `px4ctrl`。**为什么：**需要真实生成的两套 ROS 消息类型及控制器产物，才能验证适配。

**执行命令：**

```bash
cd /home/yusei/Documents/Codex/drone-learning-lab
# 第一次或源码变更时才需要；已有本页验收产物则跳过。
setsid nohup bash environments/integration/run-check.sh build \
  > /tmp/drone-integration-build.log 2>&1 < /dev/null &
tail -n 60 /tmp/drone-integration-build.log
```

脚本使用已有 `local/px4-humble:latest`，无外网、两个编译任务上限、包之间顺序编译，以当前用户写产物。不会安装依赖或重建镜像。EGO 只读挂载为 `/workspace`，复用其已有 `quadrotor_msgs`；该路径必须保留，因为安装产物有指向 `/workspace/build/...` 的绝对软链接。

**结果与验证：**【运行验证】修复后增量构建真实输出：

```text
Finished <<< px4ctrl_msgs [0.49s]
Finished <<< px4ctrl [6.44s]
Summary: 2 packages finished [7.09s]
  1 package had stderr output: px4ctrl
```

stderr 包含上游的初始化顺序、未使用参数等编译警告。编译通过不等于状态机或飞行通过。构建日志存于仓库 `notes/integration/build-fixed.log`。

**记住：**只重编受影响的新包，已经成功的 EGO、VINS、PX4 不重编。**下一步：**隔离运行消息测试。

## 4. 运行与验证：先证明指令适配正确

**在做什么：**运行真实 ROS 发布器、适配器和订阅器。**为什么：**仅看字段赋值代码不能证明两种生成消息可以共存并通过 DDS 传输。

**执行命令：**

```bash
cd /home/yusei/Documents/Codex/drone-learning-lab
bash environments/integration/run-check.sh test
```

测试在 `--network none` 容器、`ROS_DOMAIN_ID=87`、本机回环接口中进行，不连接现有飞控。默认输出仅为 `/integration/review/command`，不会向 MAVROS 写指令。

【源码确认】`environments/integration/command_adapter.py` 的 `convert()` 按次序做：

1. 要求 `frame_id=world`，不自动把其他坐标改名。
2. 要求轨迹状态 READY。
3. 要求时间戳不在未来，且消息年龄不超过 0.2 秒。
4. 拒绝 NaN/Inf。
5. 转换字段，保留原始时间戳；每收到一条有效输入才转发，不定时重复旧指令。

**结果与验证：**【运行验证】真实测试输出：

```text
PASS: real ROS message types, vector/yaw/header/gain/id mapping; jerk/heading policy
PASS: rejected wrong frame, non-READY, NaN, stale and future messages
PASS: DDS EGO publisher -> adapter -> px4ctrl_msgs subscriber; invalid frame not forwarded
```

测试源文件是 `environments/integration/test_adapter.py`。可以手动把测试向量的 x 从 `1.25` 改成其他值，并同步修改断言来练习；不要改上游消息定义。原始日志见 `notes/integration/test.log`。

**记住：**本测试的发布器是合成输入，订阅器是测试探针；没有启动 EGO 规划器或 px4ctrl 状态机，不能写成“控制闭环通过”。**下一步：**把实时接口的证据核实。

## 5. 核对坐标、QoS 与时间：已知什么，还缺什么

**在做什么：**确定定位来源和边界约定。**为什么：**速度坐标混用会让控制误差算错，且可能不报错。

【源码确认】与本机版本匹配的 [MAVROS 2.14.0 local_position.cpp:132](https://github.com/mavlink/mavros/blob/2.14.0/mavros/src/plugins/local_position.cpp#L132) 把位置变为 ENU，但在 `:144`、`:152` 把里程计线速度写成机体系速度。输出姿态是机体到 ENU 的旋转。px4ctrl `src/px4ctrl/src/input.cpp:158` 的 `VEL_IN_BODY` 默认未定义，所以默认不会把机体系速度转回世界系。

【待验证】第一阶段采用本架 PX4 的 EKF 状态做定位反馈：位置和姿态保持 MAVROS ENU 约定，线速度经 `v_world = R_body_to_world × v_body` 转换后提供给 EGO 与控制器。具体桥接实现尚未加入，必须用“偏航 90°、机体前向速度 1 m/s”的合成例子验证转换方向，再与 `/mavros/local_position/velocity_local` 交叉比较。标准 Odometry 的 twist 应在 child frame；若下游需要 VINS 风格的世界系速度，必须明确专用接口约定，不能伪装成通用 Odometry。

【待验证】EGO 的 `world` 将明确对齐本次 MAVROS `map` 的原点与轴向；这是一项对齐约定，不能只改字符串。地图点云、目标点、定位必须一起转换。Gazebo 真值留作独立验收，不与 EKF 混为一谈；EuRoC 数据不参与这一阶段。

【源码确认】[MAVROS setpoint_raw.cpp:287](https://github.com/mavlink/mavros/blob/2.14.0/mavros/src/plugins/setpoint_raw.cpp#L287) 已将姿态从 ROS 的 base_link→ENU 转成飞控的 aircraft→NED。适配器不能重复做这次转换。该文件 `:263` 还检查推力缩放配置；其当前有效值仍待确认。

**执行与结果：**【运行验证】首次只读探针取得：

```text
/mavros/setpoint_raw/attitude:
  Subscription count: 1
  Reliability: BEST_EFFORT
  Durability: VOLATILE
/mavros/local_position/odom:
  frame_id: map
  child_frame_id: base_link
/mavros/state:
  connected: true
  armed: false
  mode: AUTO.LOITER
```

【源码确认】px4ctrl `src/px4ctrl/src/px4ctrl_node.cpp:124` 使用 Best Effort/Volatile 发布姿态，和上述订阅端兼容。EGO `src/planner/plan_manage/src/traj_server.cpp:248` 定时器为 10 ms；控制器 `src/px4ctrl/config/ctrl_param_fpv.yaml:10` 配置 100 Hz。控制器 `input.cpp:174` 会对低于 100 Hz 的里程计计数告警，超时阈值在 YAML `:72` 为 0.5 秒。

**后续验证尚未成功：**【运行验证】随后两次各 12 秒的实时采样（普通 shell 和登录 shell）均返回：

```text
{"stream": "odom", "samples": 0}
{"stream": "imu", "samples": 0}
{"stream": "state", "samples": 0}
```

这不证明 PX4 死了，也不证明频率为零，只说明这些探针没有收到消息。根因尚未定位，禁止把早先单条消息和配置频率写成当前频率验收。原始输出见 `notes/integration/live-audit*.log`。

**怎么复查：**仅在现有 `px4_mavros` 容器运行时执行，12 秒自动结束：

```bash
cd /home/yusei/Documents/Codex/drone-learning-lab
sudo docker exec -i px4_mavros bash -lc \
  'source /opt/ros/humble/setup.bash; /usr/bin/python3 -' \
  < environments/integration/audit_live.py
```

脚本仅订阅并记录接收频率、最大间隔、时间戳步长和状态。每个话题至少需要两条消息才能计算频率；后续还要检验端到端延迟、时间戳单调性及暂停/恢复行为。当前最小方案先统一使用宿主机墙钟，不混入 EuRoC `/clock`；使用仿真时间的下一阶段需让整条链统一配置。

如果宿主机刚从一个 Wi-Fi 网络切换到另一个网络，先重建 MAVROS 容器，让 CycloneDDS 重新选择网卡：

```bash
cd /home/yusei/Documents/Codex/drone-learning-lab
DDS_INTERFACE=lo bash environments/px4-humble/run-sitl.sh mavros
```

这只重建 MAVROS，不会重启 PX4 SITL；默认不设置 `DDS_INTERFACE` 时仍使用 CycloneDDS 的默认网卡选择。

**记住：**“配置 100 Hz”“收到一帧”“持续达到 100 Hz”是三种证据。**下一步：**先恢复可重复的只读采样，再做定位桥接。

## 6. 定位桥接：先证明速度坐标正确

**在做什么：**把 MAVROS Odometry 中的机体系线速度旋转到世界系。**为什么：**MAVROS 的 `pose` 是 ENU 世界系，但 `twist.linear` 写在 `base_link` 机体系；px4ctrl 默认直接把它当世界系使用，方向错了不会报错。

【源码确认】MAVROS 2.14.0 的 `local_position` 插件先把 PX4 NED 转成 ROS ENU，再用姿态把 ENU 速度转回 `base_link` 写入 Odometry。px4ctrl 的 `VEL_IN_BODY` 默认未定义，`input.cpp:158-163` 不会再做这次转换。

**执行了什么：**新增 `environments/integration/odom_bridge.py`，默认只发布 `/integration/odom_world`。它保留位置、姿态和时间戳，只改线速度和 `header.frame_id=world`；不会发布姿态指令，也不会连接 MAVROS setpoint。

先做不依赖 ROS 的方向测试：

```bash
cd /home/yusei/Documents/Codex/drone-learning-lab
python3 environments/integration/test_odom_bridge.py
```

【运行验证】真实输出：

```text
PASS: identity, +90 deg ENU yaw, and invalid quaternion checks
```

机体前向速度 `(1, 0, 0)`、ENU 偏航 `+90°` 的结果必须是世界速度 `(0, 1, 0)`。如果得到 `(0, -1, 0)`，先停下来检查四元数方向和坐标约定。

**怎么验证真实话题：**桥接节点放在临时容器中，只观察审查话题：

```bash
sudo docker run --rm --network host --ipc host \
  -e RMW_IMPLEMENTATION=rmw_cyclonedds_cpp \
  -e 'CYCLONEDDS_URI=<CycloneDDS><Domain><General><Interfaces><NetworkInterface name="lo"/></Interfaces></General></Domain></CycloneDDS>' \
  -v /home/yusei/Documents/Codex/drone-learning-lab/environments/integration:/checks:ro \
  local/px4-humble:latest bash -lc \
  'source /opt/ros/humble/setup.bash; python3 /checks/odom_bridge.py'
```

另开终端读取：

```bash
sudo docker exec -it px4_mavros bash -lc \
  'source /opt/ros/humble/setup.bash; ros2 topic echo --once /integration/odom_world'
```

【运行验证】当前 Gazebo x500 实测输出包含：

```text
frame_id: world
child_frame_id: base_link
twist.twist.linear: (-0.0199, 0.0053, -0.3463) m/s
```

桥接输入真实频率约 29.84 Hz；IMU 约 49.74 Hz。px4ctrl 配置循环是 100 Hz，但会在 0.5 秒超时内复用最近里程计，不能把控制循环频率写成定位频率。

**记住：**改 `frame_id` 不是坐标变换；位置、姿态、速度必须使用同一套世界系。**下一步：**把桥输出接到独立的 `/imu_propagate` 审查话题，启动 px4ctrl 的状态机但保持不解锁。

**不解锁状态机验收：**使用同一个桥接节点把输出临时接到 `/imu_propagate`，把规划命令 remap 到没有发布者的 `/integration/review/command`，并设置 `no_RC=true`、`enable_auto_arm=true`。这样可以验证控制器收到定位但不会因为规划命令自动进入起飞流程。

【运行验证】12 秒真实输出反复显示：

```text
[PX4CTRL] Remote controller disabled, be careful!
连接状态: 已连接
解锁状态: 未解锁
飞行模式: AUTO.LOITER
当前模式: MANUAL_CTRL
```

停止临时容器后再次读取 MAVROS 状态仍为：

```text
connected: true
armed: false
mode: AUTO.LOITER
system_status: 3
```

控制器同时打印 ODOM 约 30 Hz、IMU 约 50 Hz 低于配置 100 Hz 的告警；这是当前 MAVROS 发布频率的实测差异，尚未把阈值改成“看起来通过”。

**真实 EGO 指令验证：**启动 EGO 单机仿真后，适配器订阅 `/drone_0_planning/pos_cmd`，仍只发布 `/integration/review/command`。在控制器未启动、没有任何 PX4 setpoint 输出的条件下，审查端收到：

```text
type: px4ctrl_msgs/msg/PositionCommand
frame_id: world
trajectory_flag: 1
trajectory_id: 173
pos: (-14.9507, 0.0033, 1.0003)
```

【运行验证】这证明真实 EGO 规划消息已经通过字段适配；不证明 px4ctrl 已接收，也不证明飞机会跟踪。下一次接线必须继续保留独立审查话题和消息门控，确认状态机条件后再切换到 `/position_cmd`。

**三段安全接线：**随后把适配器输出临时切换为 `/position_cmd`，把坐标桥输出切换为 `/imu_propagate`，启动 `px4ctrl`，仍使用 `no_RC=true`、`enable_auto_arm=true`，且不发布 `takeoff_land`。

【运行验证】12 秒实测保持：

```text
当前模式: MANUAL_CTRL
连接状态: 已连接
解锁状态: 未解锁
飞行模式: AUTO.LOITER
```

这一步证明真实 EGO 指令已经能到达控制器订阅端，同时没有满足进入 `AUTO_TAKEOFF` 的触发条件。它仍不是飞行验收；首次起飞前还要单独设计 setpoint、模式切换、解锁和降落的可回退流程。

## 7. 记录与下一步

**在做什么：**划清验收边界。**为什么：**避免把编译成功误当飞行成功。

| 检查项 | 当前状态 |
| --- | --- |
| 消息定义冲突 | 【运行验证】独立包名可共存，DDS 转换测试通过 |
| Humble 构建 | 【运行验证】仅两个新增包通过，保留警告 |
| MAVROS 姿态 QoS | 【运行验证】订阅端与控制器发布配置兼容 |
| 实时频率、延迟、推力缩放 | 【运行验证】MAVROS odom≈29.84 Hz、IMU≈49.74 Hz；延迟和推力缩放待验 |
| 定位坐标桥接与地图对齐 | 【运行验证】机体系速度→世界系桥接通过；地图原点对齐待验 |
| 无遥控器状态机与启动时序 | 【运行验证】12 秒保持 MANUAL_CTRL，PX4 未解锁 |
| 真实 EGO → 消息适配器 | 【运行验证】真实 `/drone_0_planning/pos_cmd` → 审查话题通过 |
| 起飞、轨迹跟踪、降落 | 【待验证】本次没有发送相关指令 |

【源码确认】默认 `no_RC=false`（px4ctrl YAML `:27`），节点会等待 RC（`px4ctrl_node.cpp:144`）。自动起飞前已收到规划指令会被拒绝（`PX4CtrlFSM.cpp:209`）。下一阶段必须先验收状态机和消息门控，不能一启动就灌入轨迹；参数中的悬停推力也要匹配 x500，不能直接照搬实机默认值。

**执行与验证：**本页、脚本、运行日志统一保存在学习仓库；构建和安装产物只保存在独立工作空间。网页构建用 `npm run docs:build`，不需要重新构建飞行软件。

**记住：**状态机能启动不等于控制器能安全飞行。**下一步：**在不连接 `/position_cmd` 的情况下测试适配器丢包、过期和坐标门控 → 再设计第一次不自动解锁的 setpoint 试验。

## 记忆卡与自测

**记忆卡：**同名类型不一定同定义；坐标标签不是坐标变换；旧指令不能靠重发变新；合成消息测试不是飞行验收。

1. 为什么不直接把 EGO 的话题 remap 到 `/position_cmd`？

::: details 答案
两边同名消息包的字段布局不同。先用独立包名使类型共存，再显式转换字段；话题改名只解决路由。
:::

2. 机体偏航 90°，机体前向速度 1 m/s，为什么不能直接当世界 x 方向速度？

::: details 答案
速度分量依赖坐标基底。机体转向后，它的前向已经不是世界 x 方向；需要用机体到世界的旋转矩阵变换速度。在约定的右手坐标中绕 +z 正转 90°，机体前向会成为世界 +y。
:::

3. 测试三个 PASS，能否写“EGO 已控制 PX4”？

::: details 答案
不能。它只证明合成 EGO 消息经适配能送到测试订阅器；控制器状态机、定位反馈和飞行没有参与。
:::

## 来源与许可

EGO 由 FAST-Lab 开发；本页控制器来自 [Ethan-02/px4ctrl-ros2-fast-drone](https://github.com/Ethan-02/px4ctrl-ros2-fast-drone/tree/85032f11e5f325678cee5c029676c43931281d36)，其仓库根许可证为 GPL-3.0。准备脚本保留许可证及固定提交信息，修改只应用到本地生成副本。本仓库不收录这份上游源码副本，也不复制第三方 README。MAVROS 引用均链接到匹配的 2.14.0 源码标签。
