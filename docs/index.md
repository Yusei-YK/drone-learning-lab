---
layout: home

hero:
  name: 自主无人机开发学习手册
  text: 一个新手把 EGO-Planner 真正跑起来的全过程
  tagline: 每条命令都实测过，每张截图都是真机画面，每个结论都标了证据来源
  actions:
    - theme: brand
      text: 从第一步开始
      link: /getting-started/environment
    - theme: alt
      text: 直接看仿真怎么跑
      link: /ego-planner/simulation

features:
  - title: 照着敲就能复现
    details: 命令一个字都没简化，每个参数都解释了"去掉会怎样"，配真实终端和 RViz 截图。
  - title: 证据分级，不吹不猜
    details: 【源码确认】给出 文件:行号，【运行验证】给出真实输出，【推测】和【待验证】绝不伪装成结论。
  - title: 只写真实踩过的坑
    details: 排错页里没有一条是编造的"可能问题"，全部来自实际报错，并写清了为什么会发生。
---

## 这份文档是什么

一个**完全的新手**在自己的笔记本上，从零把 [EGO-Planner](https://github.com/ZJU-FAST-Lab/ego-planner-swarm)（浙江大学 FAST-Lab 的无人机局部轨迹规划器）的 ROS 2 版本跑起来的真实记录。

目标不是"能跑就行"，而是**环境可复现 + 项目可运行 + 源码能理解 + 能自己改**。所以每一步都会回答四个问题：现在在做什么、为什么需要它、怎么验证成功了、我应该记住什么。

## 当前进度

::: tip 单机仿真已经跑通并完成验收【运行验证】
- Docker 镜像 `local/ego-planner-humble:latest`（4.84 GB）构建成功
- `colcon build` **20 个包全部成功**，无失败
- 8 个节点全部起来，闭环数据流稳定：`pos_cmd` **100.002 Hz**，标准差 0.07 ms
- RViz 硬件渲染正常（`OpenGl version: 4.6`），能看到无人机在柱子林里来回穿行
- 状态机走通 `INIT → WAIT_TARGET → GEN_NEW_TRAJ → EXEC_TRAJ ⇄ REPLAN_TRAJ`，单次优化 **0.512 ms**
:::

四项验收全过。下一步是系统地读源码，以及往后接 VINS / PX4，路线见 [学习路线](/getting-started/roadmap)。

## 怎么用这份文档

三页按顺序看，每页都能独立验收：

| 页面 | 你会得到 | 大概耗时 |
| --- | --- | --- |
| [第一步：搭环境](/getting-started/environment) | 一个不污染宿主机的 ROS 2 Humble 容器 | 首次 15~30 分钟 |
| [第二步：编译工作空间](/ego-planner/build) | 20 个包编译完成，`ros2 pkg list` 能认出来 | 首次 10~20 分钟 |
| [第三步：跑通单机仿真](/ego-planner/simulation) | 看得见的飞行画面 + 4 项验收 | 首次 20 分钟，之后 2 分钟 |

卡住了就看排错页：[构建期问题](/debugging/docker-build)、[运行期问题](/debugging/ego-runtime)。

## 证据标签怎么读

文档里每个重要结论都带标签，**请按标签决定信任程度**：

| 标签 | 含义 | 你可以怎么用 |
| --- | --- | --- |
| 【源码确认】 | 读了源码，给出 `文件:行号` | 可以直接引用，自己也能去核对 |
| 【运行验证】 | 在本机真实执行过，附真实输出 | 可以照着复现 |
| 【推测】 | 合理解释，但没有直接证据 | 当思路参考，不要当事实 |
| 【待验证】 | 还没做过 | 只是计划，不要当成能用的方案 |

::: warning 这份文档的局限
所有结论都来自**一台机器**：Ubuntu 24.04.3 + RTX 4060 + X11 桌面。换硬件、换发行版、用 Wayland，都可能不一样——尤其是显卡设备号和图形转发部分。**遇到不一致时，相信你机器上的实际输出，不要相信这份文档。**
:::

## 关于第三方代码

EGO-Planner 由**浙江大学 FAST-Lab** 开发并以 **GPL-3.0** 授权，上游仓库是 [ZJU-FAST-Lab/ego-planner-swarm](https://github.com/ZJU-FAST-Lab/ego-planner-swarm)（本项目用 `ros2_version` 分支，`23a8d5a`）。

本项目**只是学习复现**：不把上游源码复制进本仓库，不修改第三方代码，不把上游 README 当成自己的内容。文档里所有对源码的引用都注明了 `文件:行号`，方便你回到原仓库核对。算法和实现的功劳属于原作者。
