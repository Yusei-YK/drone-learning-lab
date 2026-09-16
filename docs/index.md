---
layout: home
hero:
  name: 自主无人机开发手册
  text: 从 ROS 2 仿真到自主飞行系统
  tagline: 理解定位、规划与控制的关系，搭建可复现环境，逐步学会运行、阅读和修改开源工程。
  actions:
    - theme: brand
      text: 阅读课程导读
      link: /getting-started/roadmap
    - theme: alt
      text: 开始第一个实验
      link: /getting-started/environment
features:
  - title: 按章节学习
    details: 从环境和基本概念开始，依次学习规划仿真、源码阅读、飞控、视觉惯性定位与系统接口。
  - title: 动手理解原理
    details: 每章给出操作位置、完整命令、参数说明和检查方法，将运行现象对应到程序与数据流。
  - title: 用实验验证理解
    details: 配合真实运行数据、源码位置、练习和自测题，区分已经验证的能力与后续研究方向。
---

## 你将学会什么

自主无人机需要回答三个相互关联的问题：**现在在哪里、接下来往哪里走、怎样跟随目标运动**。本手册以 ROS 2 Humble 为开发环境，围绕 VINS-Fusion、EGO-Planner 和 PX4，介绍定位、规划、控制之间的关系，并通过逐层实验建立完整的工程认识。

学习目标包括四部分：搭建可复现的环境，运行开源项目，理解关键源码，以及独立修改和验证系统行为。完成某个实验后，你不仅应当得到运行结果，还应能解释输入从哪里来、程序做了什么、输出如何被下一模块使用。

## 选择你的学习入口

| 你的基础或目标 | 建议入口 | 完成后应掌握 |
| --- | --- | --- |
| 第一次使用本手册 | [课程导读与学习路线](/getting-started/roadmap) | 各章节关系、学习顺序和实验范围 |
| 已掌握 Linux 基本操作，准备搭环境 | [第一章：开发环境](/getting-started/environment) | 镜像、容器、挂载目录与 ROS 环境 |
| 想先观察路径规划 | [第三章：规划仿真](/ego-planner/simulation) | 设置目标、观察轨迹、检查节点和话题 |
| 已经跑通仿真，准备改代码 | [第四章：源码阅读](/ego-planner/source-reading) | 状态机、调用链及可验证的修改方法 |
| 关注飞控与物理仿真 | [第五章：PX4 SITL](/px4-sitl/environment) | MAVLink、飞行模式、起降与双源验证 |
| 关注相机与 IMU 定位 | [第六章：视觉惯性定位](/vins-fusion/environment) | 依赖、数据集、配置及轨迹评价 |
| 准备连接规划与飞控 | [第七章：系统接口](/integration/interfaces) | 消息、坐标系、时间、QoS 与反馈关系 |

如果还不熟悉终端和 ROS 2 的节点、话题、服务，可先结合[鱼香 ROS 2 Humble 教程](https://fishros.com/d2lros2/#/humble/chapt1/章节导读)学习基础；飞控术语可参阅 [PX4 基本概念](https://docs.px4.io/main/en/getting_started/px4_basic_concepts.html)。本手册侧重这些知识在自主无人机工程中的具体应用。

## 实验范围与版本

以下为已有实验的能力边界，详细命令和证据放在相应章节中。

| 实验 | 已验证内容 | 后续内容 |
| --- | --- | --- |
| EGO-Planner | 【运行验证】单机规划仿真、20 包构建、约 100 Hz 位置指令 | 与真实动力学和控制器联合验证 |
| PX4 SITL | 【运行验证】v1.15.4 与 v1.16.0 分别完成起降；v1.16.0 使用原厂 X500 | 外部控制器悬停、轨迹跟踪与异常退出 |
| VINS-Fusion | 【运行验证】固定 ROS 2 移植版本在 EuRoC 数据集上输出轨迹 | 真值对齐评价、实时传感器标定与接入 |
| 系统接口 | 【运行验证】消息适配、MAVROS 定位采样与坐标桥接 | 完整 EGO → px4ctrl → PX4 飞行闭环 |
| 实机 | 【待验证】D435、Mid360、Orin NX 与 Pixhawk 6C mini 的部署 | 设备接入、标定、时钟与机载性能测试 |

实验环境为 Ubuntu 24.04 宿主机和 Ubuntu 22.04 / ROS 2 Humble 容器。命令中的 `/home/yusei/...` 是参考机器路径；在其他电脑上操作时，需要统一替换为自己的用户名和工作空间位置。已经完成的镜像和构建产物可以复用。

## 每章怎样学习

先阅读学习目标和前置条件，再理解本章的数据流。执行实验时，确认命令是在宿主机还是容器内运行，逐项比较实际输出与验收标准。最后完成自测或修改练习，并记录版本、关键参数和结果。

重要结论保留来源标签，便于进一步查证：

| 标签 | 阅读方式 |
| --- | --- |
| 【源码确认】 | 根据给出的版本、文件和行号核对实现 |
| 【运行验证】 | 参考对应环境中的真实输出，在自己的环境复验 |
| 【推测】 | 作为解释或排查方向，仍需证据支持 |
| 【待验证】 | 作为后续实验任务，不当作已具备的能力 |

遇到问题时，按现象查阅[构建问题](/debugging/docker-build)、[运行问题](/debugging/ego-runtime)或[日志与资源管理](/debugging/px4-log-overflow)。

## 开源项目与致谢

本手册围绕 [ZJU-FAST-Lab/ego-planner-swarm](https://github.com/ZJU-FAST-Lab/ego-planner-swarm)、[PX4](https://github.com/PX4/PX4-Autopilot)、[VINS-Fusion](https://github.com/HKUST-Aerial-Robotics/VINS-Fusion)、其 [ROS 2 移植](https://github.com/zinuok/VINS-Fusion-ROS2)及 [px4ctrl ROS 2 移植](https://github.com/Ethan-02/px4ctrl-ros2-fast-drone)开展实验，并参考 [Fast-Drone-250](https://github.com/ZJU-FAST-Lab/Fast-Drone-250)的系统组成。

算法和原始实现归各项目作者所有，各上游项目的 License 保持适用。本仓库提供实验脚本、接口适配和中文讲解；版本与改动范围在对应章节注明。
