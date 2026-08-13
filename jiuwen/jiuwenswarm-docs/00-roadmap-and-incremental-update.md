# 00 路标与增量更新说明

> 交叉引用: [01-项目概述](01-project-overview.md) | [02-整体架构](02-overall-architecture.md) | [10-依赖关系](10-dependencies.md) | [11-运行方式](11-running-guide.md)

本文档是 JiuwenSwarm Code Wiki 的「路标」。它记录本次文档化的基线提交、产物清单、提交→文档映射表,以及后续随代码演进的增量更新流程,使本 Wiki 成为可持续维护的活文档,而非一次性快照。

## 一、任务时间线

| 阶段 | 动作 | 产物 |
|------|------|------|
| 意图澄清 | 6 个选择题确认:深度=深入源码 / 组织=模块+特性子目录 / 覆盖=全子系统 / 内容=全 6 章节 / 语言=中文 / 路标=生成 | 确认书 |
| 自顶向下读码 | 入口文件精读(app/start_services/pyproject)+ 4 个并行搜索子代理分析模块簇 | 4 份结构化分析报告 |
| 结构设计 | 主文档 00-11 + features/ 特性子目录 + 主 README | 文档骨架 |
| 并行写作 | 主文档与特性文档分批派发写作子代理,统一模板 | 25 篇文档 |
| 验证 | grep 断链 / 章节齐全 / 行号锚点 | 交付检查清单 |

## 二、基线提交

| 字段 | 值 |
|------|------|
| 仓库 | D:\jiuwen\main\jiuwenswarm |
| 分支 | develop |
| HEAD 提交 | `e49907bab8931f6b6fbad5ac90dad0916ccfebbe` |
| Tag 描述 | `0.2.4.beta1-221-ge49907ba` |
| 最近提交时间 | 2026-08-04 17:37:01 +0800 |
| 文档化时间 | 2026-08-06 (Asia/Shanghai) |
| Python 版本约束 | >=3.11,<3.14 |
| 上游引擎 | openjiuwen(agent-core)@ gitcode develop 分支 |

> 增量更新时,先运行 `git rev-parse HEAD` 取新基线,与本文档基线对比即可确定变更范围。

## 三、产物清单

### 主文档集(00-11)

| 序号 | 文档 | 内容简介 |
|------|------|----------|
| 00 | [00-路标与增量更新](00-roadmap-and-incremental-update.md) | 基线、映射表、增量流程 |
| 01 | [01-项目概述](01-project-overview.md) | 定位、核心能力、技术栈、仓库结构 |
| 02 | [02-整体架构](02-overall-architecture.md) | 分层架构、设计模式、运行时数据流 |
| 03 | [03-agents 与 swarm 模块](03-agents-and-swarm-module.md) | 声明式团队装配、harness、Team 运行时 |
| 04 | [04-gateway 与 channels 模块](04-gateway-and-channels-module.md) | IM 网关、多渠道接入、路由、cron |
| 05 | [05-server 与 cli 模块](05-server-and-cli-module.md) | AgentServer、预热池、E2A/A2UI、CLI |
| 06 | [06-symphony 模块](06-symphony-module.md) | 代码知识引擎:指纹/图/索引/检索/演化 |
| 07 | [07-extensions 与 hooks 模块](07-extensions-and-hooks-module.md) | 扩展系统、钩子事件、FaaS |
| 08 | [08-common 与 e2a 与 security 模块](08-common-e2a-and-security-module.md) | E2A 协议、schema、安全、模式系统 |
| 09 | [09-instance-manager 与 jiuwenbox 模块](09-instance-manager-and-jiuwenbox-module.md) | 多实例管理、五层沙箱隔离 |
| 10 | [10-依赖关系](10-dependencies.md) | 内部依赖图、外部依赖、可选依赖组 |
| 11 | [11-运行方式](11-running-guide.md) | 安装、配置、CLI、编程式使用、测试 |

### 特性文档集(features/)

| 特性 | 文档 | 内容简介 |
|------|------|----------|
| Swarm 协作 | [swarm-collaboration](features/swarm-collaboration.md) | Leader/Teammate、分布式 Swarm |
| SwarmFlow | [swarmflow](features/swarmflow.md) | 工作流编排、人在回路 |
| 技能自演进 | [skill-self-evolution](features/skill-self-evolution.md) | 错误信号检测、技能定义优化 |
| 技能广场 | [skill-hub](features/skill-hub.md) | 技能搜索、安装、共享 |
| Auto Harness | [auto-harness](features/auto-harness.md) | 评估驱动 Harness 自动优化 |
| 多平台 IM | [channels-im](features/channels-im.md) | 飞书/钉钉/企微/Telegram 等 9 平台 |
| 工具权限安全 | [tool-permissions-security](features/tool-permissions-security.md) | 预执行审批、文件白名单、敏感拦截 |
| 模式系统 | [modes-system](features/modes-system.md) | plan/performance/swarm 三模式 |
| A2UI 与 E2A | [a2ui-e2a-protocols](features/a2ui-e2a-protocols.md) | 富前端协议与统一信封协议 |
| 记忆系统 | [memory](features/memory.md) | 自动记忆/编码记忆/任务记忆 |
| 定时任务 | [scheduled-tasks](features/scheduled-tasks.md) | cron 调度、堆式事件队列 |

## 四、提交→文档映射表

增量更新时,根据 `git log <基线>..HEAD` 的提交特征(前缀 + 文件路径)定位需更新的文档。

| 提交特征 | 影响路径 | 目标文档 |
|---------|---------|---------|
| `feat(agents)` / 路径含 `agents/` | `jiuwenswarm/agents/**` | 03-agents-and-swarm-module.md |
| `feat(gateway)` / 路径含 `gateway/` | `jiuwenswarm/gateway/**` | 04-gateway-and-channels-module.md |
| `feat(channels)` / 路径含 `channels/` | `jiuwenswarm/channels/**` | 04 + 11-running-guide.md |
| `feat(server)` / 路径含 `server/` | `jiuwenswarm/server/**` | 05-server-and-cli-module.md |
| `feat(cli)` / 路径含 `cli/` | `jiuwenswarm/cli/**` | 05 + 11-running-guide.md |
| `feat(symphony)` / 路径含 `symphony/` | `jiuwenswarm/symphony/**` | 06-symphony-module.md |
| `feat(extensions)` / 路径含 `extensions/` | `jiuwenswarm/extensions/**` | 07-extensions-and-hooks-module.md |
| `feat(common)` / 路径含 `common/e2a` `common/schema` `common/security` | `jiuwenswarm/common/**` | 08-common-e2a-and-security-module.md |
| `feat(instance)` / 路径含 `instance_manager/` | `jiuwenswarm/instance_manager/**` | 09 + 11-running-guide.md |
| `feat(jiuwenbox)` / 路径含 `jiuwenbox/` | `jiuwenbox/**` | 09-instance-manager-and-jiuwenbox-module.md |
| 依赖变更 | `pyproject.toml` | 10-dependencies.md |
| 入口/启动变更 | `app.py` `start_services.py` `__init__.py` | 02 + 11-running-guide.md |
| 模式系统变更 | `common/mode_matrix.py` | features/modes-system.md + 02 |
| E2A/A2UI 协议变更 | `common/e2a/**` `server/runtime/a2ui/**` | features/a2ui-e2a-protocols.md + 08 |
| IM 渠道增删 | `gateway/channel_manager/im_platforms/**` | features/channels-im.md + 04 |
| 定时任务变更 | `gateway/cron/**` | features/scheduled-tasks.md + 04 |
| 记忆系统变更 | `agents/harness/common/memory/**` | features/memory.md |
| 技能演进变更 | `agents/swarm/providers/evolution_rails.py` 等 | features/skill-self-evolution.md |
| 文档变更 | `docs/**` | 01-project-overview.md |

## 五、增量更新流程

1. **确认基线**:运行 `git rev-parse HEAD` 与 `git describe --tags --always`,记录新基线。
2. **取增量**:`git log e49907bab8931f6b6fbad5ac90dad0916ccfebbe..HEAD --oneline` 列出基线以来的提交。
3. **分类**:按上表「提交特征」将每条提交归入目标文档。
4. **更新文档**:对受影响文档,重新读对应源码,更新「关键类与函数」「实现机制」章节,核验行号。
5. **追加记录**:在本节「更新记录表」追加一行(日期 + 基线区间 + 变更摘要 + 更新的文档)。
6. **验证链接**:grep 检查 `[中文字符]\.md` 断链残留与 `file:///` 链接有效性。
7. **更新基线**:将本文档「基线提交」章节的 HEAD 更新为新值。
8. **提交**:将文档变更与代码同提交入版本控制(Docs as Code)。

## 六、更新记录表

| 日期 | 基线区间 | 变更摘要 | 更新文档 |
|------|---------|---------|---------|
| 2026-08-06 | 初始 → e49907ba | 首次全量文档化,覆盖全子系统 | 全部 00-11 + features 全部 |

## 七、约定

- **语言**:正文中文,文件名英文短名(00- 序号前缀)。
- **行号锚点**:所有类/函数引用用 `[basename](file:///绝对路径#L行号)` 格式,可点击直达源码行。
- **交叉引用**:每篇顶部固定一行交叉引用头部,形成知识网络。
- **不擅自提交**:生成/更新文档后不主动 `git commit`,除非用户明确要求。
- **行数**:能力文档 150-300 行/篇,索引文档 80-150 行,主文档 200-500 行。
