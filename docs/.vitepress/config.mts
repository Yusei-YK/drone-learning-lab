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
  title: '自主无人机开发学习手册',
  description: '从可复现环境到 EGO-Planner ROS 2 仿真的真实复现记录',
  base: process.env.GITHUB_ACTIONS === 'true' ? githubPagesBase() : '/',
  cleanUrls: true,
  lastUpdated: true,
  themeConfig: {
    nav: [
      { text: '环境', link: '/getting-started/environment' },
      { text: 'EGO 仿真', link: '/ego-planner/simulation' },
      { text: '排错', link: '/debugging/ego-runtime' }
    ],
    sidebar: [
      {
        text: '开始',
        items: [
          { text: '项目总览', link: '/' },
          { text: '第一步：搭环境', link: '/getting-started/environment' },
          { text: '学习路线', link: '/getting-started/roadmap' }
        ]
      },
      {
        text: 'EGO-Planner',
        items: [
          { text: '第二步：编译工作空间', link: '/ego-planner/build' },
          { text: '第三步：跑通单机仿真', link: '/ego-planner/simulation' }
        ]
      },
      {
        text: '调试记录（只写真实踩过的坑）',
        items: [
          { text: '构建期问题', link: '/debugging/docker-build' },
          { text: '运行期问题', link: '/debugging/ego-runtime' }
        ]
      }
    ],
    search: { provider: 'local' },
    outline: { level: [2, 3], label: '本页目录' },
    docFooter: { prev: '上一篇', next: '下一篇' },
    lastUpdated: { text: '最后更新' }
  }
}))
