# JiuwenSwarm 特性文档索引

> 交叉引用: [主 README](../README.md) | [01-项目概述](../01-project-overview.md) | [02-整体架构](../02-overall-architecture.md)

本目录按能力维度组织 JiuwenSwarm 的特性文档。与按代码目录划分的模块文档(03~09)不同,特性文档以"一项端到端能力"为单位,横跨多个模块,聚焦于该能力"解决什么问题、关键入口在哪、如何实现、与业界方案如何对比"。每篇特性文档均包含能力概述、关键类与函数(带可跳转源码链接)、实现机制、调用示例、业界对比与小结六节,便于快速建立对该能力的整体认知后再深入源码。

## 特性清单

| 特性 | 文档 | 内容简介 | 关键入口 |
|------|------|----------|----------|
| Swarm 协作 | [swarm-collaboration](swarm-collaboration.md) | Leader/Teammate、分布式 Swarm | enrich_team_spec_for_swarm |
| SwarmFlow | [swarmflow](swarmflow.md) | 工作流编排、人在回路 | TeamManager.interact |
| 技能自演进 | [skill-self-evolution](skill-self-evolution.md) | 错误信号检测、技能定义优化 | _role_evolution_rails |
| 技能广场 | [skill-hub](skill-hub.md) | 技能搜索、安装、共享 | build_skill_toolkit |
| Auto Harness | [auto-harness](auto-harness.md) | 评估驱动 Harness 自动优化 | AutoHarnessOrchestrator |
| 多平台 IM | [channels-im](channels-im.md) | 飞书/钉钉等 9 平台接入 | GatewayServer |
| 工具权限安全 | [tool-permissions-security](tool-permissions-security.md) | 预执行审批、文件白名单、沙箱 | SecurityRail |
| 模式系统 | [modes-system](modes-system.md) | plan/performance/swarm 三模式 | resolve_request_mode |
| A2UI 与 E2A | [a2ui-e2a-protocols](a2ui-e2a-protocols.md) | 富前端协议与统一信封协议 | E2AEnvelope |
| 记忆系统 | [memory](memory.md) | 自动/编码/任务记忆+经验库 | ExperienceBank |
| 定时任务 | [scheduled-tasks](scheduled-tasks.md) | cron 调度、堆式事件队列 | CronSchedulerService |

## 按能力领域分组

为便于按兴趣检索,上述特性按能力领域归纳如下:

| 能力领域 | 包含特性 | 关注问题 |
|----------|----------|----------|
| 协作与编排 | Swarm 协作、SwarmFlow、定时任务 | 多 Agent 如何分工、编排、定时触发 |
| 自演进与能力沉淀 | 技能自演进、技能广场、Auto Harness、记忆系统 | Agent 如何自我优化、沉淀可复用资产 |
| 接入与协议 | 多平台 IM、A2UI 与 E2A | 异构入口如何统一、富前端如何渲染 |
| 治理与运行 | 工具权限安全、模式系统 | 安全控制、运行模式如何决定流转 |

## 阅读建议

- **新手先读**:建议从 [a2ui-e2a-protocols](a2ui-e2a-protocols.md) 建立对系统协议层的整体认知(E2A 统一信封与 A2UI 富前端的正交关系),再读 [modes-system](modes-system.md) 理解 plan/performance/swarm 三模式如何决定请求流转,最后读 [channels-im](channels-im.md) 了解多平台如何接入。这三篇覆盖了"请求怎么进来、怎么分发、怎么出去"的主干。
- **进阶深入**:理解主干后,可按兴趣深入——关注协作读 [swarm-collaboration](swarm-collaboration.md) 与 [swarmflow](swarmflow.md),关注自演进读 [skill-self-evolution](skill-self-evolution.md) 与 [auto-harness](auto-harness.md),关注长期能力读 [memory](memory.md) 与 [skill-hub](skill-hub.md),关注自动化与主动性读 [scheduled-tasks](scheduled-tasks.md),关注治理与合规读 [tool-permissions-security](tool-permissions-security.md)。
- **源码核验**:每篇特性文档的关键类与函数表格均附带 `file:///` 绝对路径与行号锚点,可直接点击跳转源码核验。模块文档(03~09)提供按代码目录的细粒度结构,特性文档提供按能力的端到端视角,两者互补。

## 特性文档与模块文档的分工

| 维度 | 特性文档(本目录) | 模块文档(03~09) |
|------|-------------------|------------------|
| 组织维度 | 按能力(端到端) | 按代码目录 |
| 范围 | 横跨多模块 | 聚焦单模块 |
| 视角 | "解决什么问题" | "代码长什么样" |
| 关键入口 | 关键类/函数 + 业界对比 | 子模块清单 + 类清单 |
| 适用场景 | 建立能力认知 | 定位代码实现 |

## 文档结构约定

- 每篇特性文档统一采用六节结构:能力概述、关键类与函数、实现机制、调用示例、业界对比、小结。
- 关键类与函数表使用 `[basename](file:///绝对路径#L行号)` 格式(无反引号包裹链接文本),点击可直接跳转源码行。
- 业界对比表统一为"维度 | JiuwenSwarm | 竞品A | 竞品B | 竞品C"五列,聚焦差异化而非功能罗列。
- 小结统一为编号列表(通常 6 条),逐条提炼该特性的核心要点。

## 特性与模块对照

特性文档按能力组织,模块文档按代码目录组织,两者交叉引用关系如下:

| 特性文档 | 主要关联模块文档 |
|----------|------------------|
| a2ui-e2a-protocols | [05-server与cli](../05-server-and-cli-module.md)、[08-common与e2a](../08-common-e2a-and-security-module.md) |
| memory | [03-agents与swarm](../03-agents-and-swarm-module.md)、[06-symphony](../06-symphony-module.md) |
| scheduled-tasks | [04-gateway与channels](../04-gateway-and-channels-module.md)、[03-agents与swarm](../03-agents-and-swarm-module.md) |
| channels-im | [04-gateway与channels](../04-gateway-and-channels-module.md) |
| swarm-collaboration | [03-agents与swarm](../03-agents-and-swarm-module.md) |
| swarmflow | [03-agents与swarm](../03-agents-and-swarm-module.md) |
| skill-self-evolution | [06-symphony](../06-symphony-module.md)、[07-extensions与hooks](../07-extensions-and-hooks-module.md) |
| skill-hub | [06-symphony](../06-symphony-module.md) |
| auto-harness | [06-symphony](../06-symphony-module.md) |
| tool-permissions-security | [08-common与e2a](../08-common-e2a-and-security-module.md)、[05-server与cli](../05-server-and-cli-module.md) |
| modes-system | [08-common与e2a](../08-common-e2a-and-security-module.md) |

阅读时建议先以特性文档建立端到端认知,再按对照表进入相应模块文档查看代码目录级的细粒度结构。

## 新增特性文档指引

- 新增特性文档应置于本目录,文件名采用英文短名(如 `my-feature.md`),并在本索引的"特性清单"与"特性与模块对照"两张表中登记。
- 严格遵循六节模板:能力概述、关键类与函数、实现机制、调用示例、业界对比、小结,确保与既有特性文档风格一致。
- 关键类与函数表的行号锚点须经源码核验后再填,避免链接指向错误行;源码变动后需同步更新。
- 业界对比应选取 3 个有代表性的竞品,聚焦差异化维度,避免变成功能清单堆砌。
