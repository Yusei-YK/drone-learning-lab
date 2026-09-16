# PX4 仿真日志与资源管理

本页说明如何为 PX4 仿真设置日志、内存、CPU 和会话时长限制，并提供检查方法。它是第五章的配套参考，不要求按时间顺序阅读。

PX4 的起降验收必须同时检查飞控状态和 Gazebo 物理真值。服务返回成功、解锁或自动上锁都只是控制状态，不能单独证明飞机完成了起飞和降落。

## 1. 当前做什么，为什么需要

先阻止日志继续增长，核对恢复后的系统状态，再修复后台启动方式。磁盘扩容不能解决持续无上限写日志的问题。

【运行验证】本次实验接手时的真实输出：

```text
/dev/nvme0n1p3  195G  121G  65G  66% /
Mem:            15Gi  5.1Gi ... available 10Gi
Swap:          4.0Gi    0B ... free 4.0Gi
```

两个实验容器已经停止，日志文件各为 **0 字节**。这部分恢复由用户在本次实验之前完成，不能记成本次实验释放了这些空间。容器退出码均为 `137`，但 Docker 的 `OOMKilled=false`；不能仅凭 137 就断言发生过 OOM。

【待验证】历史日志峰值、磁盘被占满的准确时刻，以及系统故障链。本次实验没有原始大日志，不补写推测的容量和时间。

## 2. 源码与配置确认了什么

【运行验证】原容器 `px4_sitl_116`、`px4_mavros_116` 配置的关键字段：

```json
{"LogConfig":{"Type":"json-file","Config":{}},"Memory":0,"MemorySwap":0,"NanoCpus":0}
```

日志没有大小轮转设置，内存、CPU 也没有限额。仓库原有脚本已有轮转参数，但此前临时拼接的 `docker run` 没有使用它，这是执行失误。

【源码确认】PX4 v1.16.0 的交互控制台读取到 EOF 后，`break` 只退出 `switch`，外层循环仍刷新提示符：

- [`platforms/posix/src/px4/common/px4_daemon/pxh.cpp:312`](https://github.com/PX4/PX4-Autopilot/blob/6ea3539157ca358c70a515878b77077af7d4611d/platforms/posix/src/px4/common/px4_daemon/pxh.cpp#L312)：读取输入。
- [`pxh.cpp:317`](https://github.com/PX4/PX4-Autopilot/blob/6ea3539157ca358c70a515878b77077af7d4611d/platforms/posix/src/px4/common/px4_daemon/pxh.cpp#L317)：EOF 分支。
- [`pxh.cpp:399`](https://github.com/PX4/PX4-Autopilot/blob/6ea3539157ca358c70a515878b77077af7d4611d/platforms/posix/src/px4/common/px4_daemon/pxh.cpp#L399)：继续刷新提示符。
- [`platforms/posix/src/px4/common/main.cpp:221`](https://github.com/PX4/PX4-Autopilot/blob/6ea3539157ca358c70a515878b77077af7d4611d/platforms/posix/src/px4/common/main.cpp#L221)：`-d` 关闭交互控制台。

因此后台入口使用 `px4 -d`，同时加载构建生成的 `gz_env.sh`，指定正确的 `etc` 与工作目录。只去掉 `make` 而不提供这些路径也不完整。

## 3. 执行了什么

1. 保存两个容器的状态、日志配置和有限字节采样记录。
2. 只移除这两个已经停止的实验容器，没有做全局清理。
3. 修复 `environments/px4-humble/run-sitl.sh`，增加日志读取器、启动资源检查和回归测试。
4. 把运行约束写入仓库 `AGENTS.md`，要求后续使用脚本，不绕开限额。

本机小体积证据目录：`/home/yusei/Documents/Codex/px4-sitl-1.16/incident-20260916`。

【源码确认】修复后脚本的新容器策略：

| 项目 | 限制与行为 |
| --- | --- |
| 控制台 | `px4 -d`，不进入交互 `pxh>` |
| Docker 日志 | 每文件 `10m`，最多 2 个，每容器约 20 MB；记录边界可能略超限 |
| 读日志 | 1～200 行、最多读取 64 KiB、最多 8 秒，不持续跟随 |
| PX4/Gazebo | 内存 3 GiB，内存+Swap 同为 3 GiB，4 CPU 配额 |
| MAVROS | 内存 768 MiB，内存+Swap 同为 768 MiB，1 CPU 配额 |
| 进程数 | 每个运行容器最多 512 |
| 会话时长 | 默认及最大 1200 秒，容器内 `timeout`，到时终止本次仿真 |
| ULog 与参数 | `/px4-runtime` 使用 256 MiB tmpfs，保存在内存中 |
| ROS 文件日志 | `/tmp/ros-log`，与 `/tmp` 共用 64 MiB tmpfs |
| 其他写盘 | 根文件系统与源码挂载只读；Gazebo 配置目录使用 64 MiB tmpfs |
| 启动检查 | 工作区与 Docker 所在文件系统各至少 15 GiB 可用；SITL 启动至少 4 GiB MemAvailable |
| 重复启动 | 已有 PX4 项目进程或容器时拒绝再起一套 |
| 编译 | Ninja 显式限制为 2 个任务，容器另有限额；本次实验没有编译 |

限制只对**通过修复脚本新建的容器**生效，不是 Docker daemon 的全局设置。配额可能影响仿真实时率，恢复实验后需要测量。

ULog 和参数在容器停止后丢失，需要留证时应在会话结束前用 `docker cp` 导出具体文件并检查体积。这是 SITL 的限时实验策略，不能用于真机。

## 4. 是否成功，怎么验证

【运行验证】防护回归测试：

```bash
cd /home/yusei/Documents/Codex/drone-learning-lab
PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 environments/px4-humble/test-runtime-guards.py
```

真实输出：

```text
Ran 6 tests in 0.327s
OK
```

覆盖超长单行截断、静默命令超时、命令失败、低内存/低磁盘拒绝启动，以及启动参数是否带齐保护。启动参数测试使用假的 Docker 接口，不启动飞行。

【运行验证】另外两个短时真实测试：

| 测试 | 结果 |
| --- | --- |
| 日志轮转 | 生成 196608 字节测试文本；用 64 KiB × 2 的小限额验证轮转，最后两个文件共 80951 字节 |
| 关闭 PX4 控制台 | 用只打印一行的独立启动脚本运行 3 秒；日志 318 字节，`pxh>` 出现 0 次，超时退出码 124 |

没有启动 Gazebo、MAVROS 或执行解锁，测试容器均已移除。手动核对状态：

```bash
sudo docker ps -a
df -h /
free -h
pgrep -ax px4
```

`pgrep` 无输出且返回 1，表示没有名为 `px4` 的进程。Swap 行要区分 `used` 与 `free`。

## 5. 应该记住什么，下一步是什么

- `--tail` 限制行数，一条没有换行的 `pxh>` 输出也可能很大，必须再限制字节。
- 限制日志读取不等于限制日志写盘，两处都要设置。
- 退出宿主机 Docker 客户端，不等于容器停止。
- 解锁成功不等于升空。起降必须核对 Gazebo 真值。

本页只介绍日志与资源管理；完整飞行验收和高度判定见 [PX4 第 13 节](/px4-sitl/environment#px4-116-acceptance)。


## 6. 后续恢复实验结果（2026-09-16）

【运行验证】在上述防护启用后，恢复原厂 X500 配置、固定 Gazebo 子模块，并完成 v1.16.0 起降复验，自动脚本退出码 `0`，结束后两个容器已删除。详见 [PX4 第 13 节](/px4-sitl/environment#px4-116-acceptance)。这组证据说明资源限制与飞行验收可以同时使用；飞行结论仍以第五章的独立判据为准。
