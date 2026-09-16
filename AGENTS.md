# 本项目的运行与资源约束

- 开始任务先核对 `df -h`、`free -h`、`sudo -n /usr/bin/docker ps -a`。区分 Swap 的 used/free；报告 MemAvailable，不把 free 当 available。
- PX4/Gazebo/MAVROS 使用 `environments/px4-humble/run-sitl.sh`，通过环境变量选择工作区/镜像。禁止绕开脚本临时拼接无日志限额的 `docker run`。本仓库曾因这样做导致日志失控，用户无法登录系统。
- 后台 PX4 必须 `px4 -d`，并加载构建生成的 `gz_env.sh` 和正确的 etc/工作目录。不要在 stdin 关闭的容器中运行交互 `pxh>`，不要用 `make ... gz_x500` 替代后台入口。
- 所有新增长运行容器必须显式命名、设置日志轮转、内存/Swap/CPU/进程数上限，以及容器内 timeout。启动前拒绝同一套仿真重复运行。宿主机 docker 客户端退出不代表容器退出。
- Docker 日志必须有 `--tail` 或 `--since`，还必须限制总读取字节和时间；PX4 提示符可能是一条超长行。优先使用 `bounded-logs.py`，不能把持续输出重定向到宿主机无限增长的文件。
- 一轮验收结束或失败后，只停止本轮明确命名的容器，再核对容器、PX4/Gazebo 进程和资源。不要把修复过程中“已启动”当成任务完成。
- 不为追求解锁通过而关闭预检/失联保护；先定位真实条件。`success=True`、`armed=True` 都不是物理升空证据。起降验收必须交叉核对 PX4 状态与 Gazebo 真值。
- 清理前保留小体积证据，按明确路径/容器 ID 清理；不清空 Docker 数据目录，不做全局 prune，不删除已验收工作区来掩盖日志问题。
- 不把用户凭据写入脚本、文档或 Git。宿主机特权操作优先限于既有 `sudo docker` 规则。不要把以前对话中错误的推断继续写成已验证事实。
