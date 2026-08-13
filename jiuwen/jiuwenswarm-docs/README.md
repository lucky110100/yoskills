# JiuwenSwarm Code Wiki

> **结构化、可导航的代码仓库文档** —— 架构 / 模块 / 类函数 / 依赖 / 运行方式
>
> 文档化技能:[code-wiki-author](../common/code-wiki-author/SKILL.md) · 基线:`e49907ba` (develop) · 2026-08-06

本 Wiki 是对 [JiuwenSwarm](https://gitcode.com/openJiuwen/jiuwenswarm) 仓库的全量源码级文档化,基于 Diátaxis 的 Reference + Explanation 两象限,采用「主文档集(00-11)+ 特性子目录」双层组织。所有类/函数引用均带 `file:///` 行号锚点,可点击直达源码行。

## 主文档集

| 序号 | 文档 | 内容简介 |
|------|------|----------|
| 00 | [00-路标与增量更新](00-roadmap-and-incremental-update.md) | 基线提交、产物清单、提交→文档映射表、增量更新流程与记录 |
| 01 | [01-项目概述](01-project-overview.md) | 定位、核心能力、技术栈、仓库结构、入口脚本 |
| 02 | [02-整体架构](02-overall-architecture.md) | 六层架构、十大设计模式、端到端运行时数据流、与 openjiuwen 边界 |
| 03 | [03-agents 与 swarm 模块](03-agents-and-swarm-module.md) | 声明式团队装配、harness 能力组件、Team 运行时 |
| 04 | [04-gateway 与 channels 模块](04-gateway-and-channels-module.md) | IM 网关、多渠道接入、5 维路由、cron、心跳 |
| 05 | [05-server 与 cli 模块](05-server-and-cli-module.md) | AgentServer、Agent 预热池、E2A/A2UI、CLI 渲染 |
| 06 | [06-symphony 模块](06-symphony-module.md) | 代码知识引擎:指纹/图/索引/检索/经验/演化 |
| 07 | [07-extensions 与 hooks 模块](07-extensions-and-hooks-module.md) | 插件化扩展、钩子事件、FaaS、用户 hooks |
| 08 | [08-common 与 e2a 与 security 模块](08-common-e2a-and-security-module.md) | E2A 信封、schema、安全、模式系统、reasoning |
| 09 | [09-instance-manager 与 jiuwenbox 模块](09-instance-manager-and-jiuwenbox-module.md) | 多实例管理、五层纵深沙箱隔离 |
| 10 | [10-依赖关系](10-dependencies.md) | 内部依赖图、外部依赖、可选依赖组、入口清单 |
| 11 | [11-运行方式](11-running-guide.md) | 安装、配置、CLI、多实例、测试、代码质量 |

## 特性文档集

按能力维度组织,详见 [features/README.md](features/README.md)。

| 特性 | 文档 | 关键入口 |
|------|------|----------|
| Swarm 多智能体协作 | [swarm-collaboration](features/swarm-collaboration.md) | enrich_team_spec_for_swarm |
| SwarmFlow 工作流编排 | [swarmflow](features/swarmflow.md) | TeamManager.interact |
| 技能自演进 | [skill-self-evolution](features/skill-self-evolution.md) | _role_evolution_rails |
| 技能广场与共享 | [skill-hub](features/skill-hub.md) | build_skill_toolkit |
| Auto Harness 自动优化 | [auto-harness](features/auto-harness.md) | AutoHarnessOrchestrator |
| 多平台 IM 接入 | [channels-im](features/channels-im.md) | GatewayServer |
| 工具权限与安全防护 | [tool-permissions-security](features/tool-permissions-security.md) | SecurityRail |
| 模式系统 | [modes-system](features/modes-system.md) | resolve_request_mode |
| A2UI 与 E2A 协议 | [a2ui-e2a-protocols](features/a2ui-e2a-protocols.md) | E2AEnvelope |
| 记忆系统 | [memory](features/memory.md) | ExperienceBank |
| 定时任务 | [scheduled-tasks](features/scheduled-tasks.md) | CronSchedulerService |

## 阅读建议

- **快速了解项目**:01 → 02(定位 + 架构)。
- **深入某子系统**:03-09 按模块逐篇,每篇含关键类函数表(行号锚点)与实现机制时序。
- **理解某能力维度**:features/ 下按特性阅读,与对应模块文档交叉对照。
- **运行/二次开发**:11 + 10(运行方式 + 依赖)。
- **可持续维护**:00(提交→文档映射表 + 增量更新流程)。

## 文档约定

- **语言**:正文中文,文件名英文短名(主文档带 00- 序号前缀)。
- **行号锚点**:所有类/函数引用用 `[basename](file:///绝对路径#L行号)`,可点击直达源码行。
- **交叉引用**:每篇顶部固定交叉引用头部,形成知识网络。
- **行数**:主文档 200-450 行,特性文档 150-300 行,索引 80-150 行。

## 基线与更新

| 字段 | 值 |
|------|------|
| 基线提交 | `e49907bab8931f6b6fbad5ac90dad0916ccfebbe` |
| Tag | `0.2.4.beta1-221-ge49907ba` |
| 分支 | develop |
| 最近提交 | 2026-08-04 17:37:01 +0800 |
| 上游引擎 | openjiuwen(agent-core)@ gitcode develop |

增量更新流程见 [00-路标与增量更新](00-roadmap-and-incremental-update.md)。生成/更新文档后不主动 `git commit`,除非明确要求。
