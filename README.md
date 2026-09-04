# Drone Learning Lab

一个新手把 **EGO-Planner（ROS 2 Humble）单机仿真**从零跑通的完整学习记录，包含可复现的环境脚本和中文教学文档。

📖 **网页版文档**：部署在 GitHub Pages（地址见仓库 About 栏 / Actions 部署结果）

## 这个仓库解决什么问题

EGO-Planner 的官方教程基于 Ubuntu 20.04 + ROS 1 Noetic。如果你的机器是较新的 Ubuntu（本项目是 24.04 + ROS 2 Jazzy），照着官方教程走会处处碰壁，而把 Noetic 命令机械替换成 ROS 2 命令同样跑不通。

本仓库记录的是**实际走通的那条路**：用 Docker 起一个 ROS 2 Humble 环境，编译 EGO-Planner 的 `ros2_version` 分支，跑通单机仿真，并把每一步、每个报错、每个原因都写清楚。

## 当前状态

【运行验证】**单机仿真已跑通并完成四项验收**：

| 项目 | 结果 |
| --- | --- |
| Docker 镜像 | `local/ego-planner-humble:latest`，4.84 GB |
| 编译 | `colcon build` 20 个包全部成功，无 failed |
| 节点 | 8 个节点齐全 |
| 闭环频率 | `pos_cmd` 100.002 Hz（标准差 0.07 ms） |
| 图形 | RViz 硬件渲染，`OpenGl version: 4.6` |
| 规划 | 状态机走通，单次优化 0.512 ms |

下一步是系统读源码，之后才进入 VINS / PX4。**VINS、PX4、QGroundControl、RealSense、Isaac Sim、MuJoCo 目前一个都没装。**

## 仓库结构

```text
docs/                        VitePress 中文教学文档（网页版源文件）
├─ index.md                  项目总览
├─ getting-started/
│  ├─ environment.md         第一步：搭 Docker + ROS 2 Humble 环境
│  └─ roadmap.md             学习路线与阶段验收标准
├─ ego-planner/
│  ├─ build.md               第二步：编译工作空间（20 个包）
│  └─ simulation.md          第三步：跑通单机仿真 + 4 项验收
├─ debugging/
│  ├─ docker-build.md        构建期问题（只记录真实遇到的）
│  └─ ego-runtime.md         运行期问题（只记录真实遇到的）
└─ public/img/               真实终端和 RViz 截图

environments/ego-humble/     环境脚本留档（对照抄写用）
├─ Dockerfile                ROS 2 Humble + PCL + Armadillo 镜像
├─ docker/entrypoint.sh      自动 source ROS 环境
├─ build-image.sh            构建镜像
├─ build-workspace.sh        rosdep + colcon build
├─ docker-run.sh             起交互容器（必须放在工作空间根目录才正确）
├─ capture-shot.sh           截 RViz 窗口（容器内 ImageMagick 方案）
└─ capture-term.sh           截干净终端输出
```

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
