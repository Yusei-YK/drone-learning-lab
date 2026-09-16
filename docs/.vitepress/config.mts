import { defineConfig } from 'vitepress'
import { withMermaid } from 'vitepress-plugin-mermaid'

function githubPagesBase(): string {
  const repository = process.env.GITHUB_REPOSITORY
  if (!repository) return '/'

  const [owner, name] = repository.split('/')
  if (!name || name === `${owner}.github.io`) return '/'
  return `/${name}/`
}

export default withMermaid(defineConfig({
  lang: 'zh-CN',
  title: '自主无人机开发手册',
  description: '以 ROS 2 为基础，学习无人机定位、规划、飞控与系统集成',
  base: process.env.GITHUB_ACTIONS === 'true' ? githubPagesBase() : '/',
  cleanUrls: true,
  lastUpdated: true,
  themeConfig: {
    nav: [
      { text: '课程导读', link: '/getting-started/roadmap' },
      { text: '开发环境', link: '/getting-started/environment' },
      { text: 'EGO 仿真', link: '/ego-planner/simulation' },
      { text: '读源码', link: '/ego-planner/source-reading' },
      { text: 'PX4 SITL', link: '/px4-sitl/environment' },
      { text: 'VINS-Fusion', link: '/vins-fusion/environment' },
      { text: '闭环接口', link: '/integration/interfaces' },
      { text: '排错', link: '/debugging/ego-runtime' }
    ],
    sidebar: [
      {
        text: '开始',
        items: [
          { text: '手册首页', link: '/' },
          { text: '第一章：开发环境', link: '/getting-started/environment' },
          { text: '课程导读与路线', link: '/getting-started/roadmap' }
        ]
      },
      {
        text: 'EGO-Planner',
        items: [
          { text: '第二章：构建工作空间', link: '/ego-planner/build' },
          { text: '第三章：规划仿真', link: '/ego-planner/simulation' },
          { text: '第四章：源码阅读', link: '/ego-planner/source-reading' }
        ]
      },
      {
        text: 'PX4 SITL 与地面站',
        items: [
          { text: '第五章：PX4 飞控与仿真', link: '/px4-sitl/environment' }
        ]
      },
      {
        text: '视觉惯性里程计（VIO）',
        items: [
          { text: '第六章：视觉惯性定位', link: '/vins-fusion/environment' }
        ]
      },
      {
        text: '完整闭环',
        items: [
          { text: '第七章：系统接口', link: '/integration/interfaces' }
        ]
      },
      {
        text: '问题诊断与参考',
        items: [
          { text: '构建期问题', link: '/debugging/docker-build' },
          { text: '仿真日志与资源管理', link: '/debugging/px4-log-overflow' },
          { text: '运行期问题', link: '/debugging/ego-runtime' }
        ]
      },
      {
        text: '扩展阅读',
        items: [
          { text: 'OpenCV 为什么没有 CUDA', link: '/reference/opencv-cuda' }
        ]
      }
    ],
    search: { provider: 'local' },
    outline: { level: [2, 3], label: '本页目录' },
    docFooter: { prev: '上一篇', next: '下一篇' },
    lastUpdated: { text: '最后更新' }
  }
}))
