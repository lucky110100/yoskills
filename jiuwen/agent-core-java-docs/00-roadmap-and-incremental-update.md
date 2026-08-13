# 00 路标与增量更新说明

> 交叉引用: [01-project-overview](01-project-overview.md) | [02-overall-architecture](02-overall-architecture.md) | [09-dependencies](09-dependencies.md) | [10-running-guide](10-running-guide.md)

本文件是 agent-core-java 文档集的**路标**，记录本次文档化任务的时间线、基线提交、产物清单与后续增量更新流程。

## 一、任务基线

| 项目 | 内容 |
|------|------|
| **源仓库** | `D:\jiuwen\main\agent-core-java` |
| **基线提交** | `695089224478c4cd1670340f56d64ecb8de4c5b7`（短哈希 `695089224`） |
| **提交信息** | 更改jackson版本为2.18.8 |
| **作者** | sczgklose |
| **时间** | 2026-08-04 20:28:40 +0800 |
| **分支** | `730`（`origin/730`） |
| **Tag** | `v0.1.14` |
| **版本** | `com.openjiuwen:agent-core-java:0.1.14` |

## 二、任务时间线

| 日期 | 阶段 | 产出 |
|------|------|------|
| 2026-08-05 | 阶段 1：意图澄清 | 提 8 个选择/是否题，确认覆盖范围、深度、组织、命名、示例、对比、路标 |
| 2026-08-05 | 阶段 2：自顶向下读码 | LS 仓库结构 + 读 README/AGENTS/pom.xml + 获取 git 基线 |
| 2026-08-05 | 阶段 3：并行源码分析 | 派发 4 个搜索子代理（core / harness+deepagents / agentteams+evolving+autoharness / extensions+spi+dev_tools） |
| 2026-08-05 | 阶段 4：结构设计 | 11 篇主文档 + 业界对比独立文档 + features/coding 子目录 |
| 2026-08-05 | 阶段 5：并行写作 | 派发 4 个写作子代理，每批 3 篇，生成全部主文档 |

## 三、产物清单

| 序号 | 文档 | 内容简介 |
|------|------|----------|
| 00 | [路标与增量更新说明](00-roadmap-and-incremental-update.md) | 本文 |
| 01 | [项目概述](01-project-overview.md) | 定位、核心能力、技术栈、仓库结构、快速开始 |
| 02 | [整体架构](02-overall-architecture.md) | 分层架构、十大设计模式、运行时数据流 |
| 03 | [core 模块](03-core-module.md) | Pregel BSP 引擎、Runner 单例、Session、ReActAgent |
| 04 | [harness 与 deepagents 模块](04-harness-and-deepagents-module.md) | DeepAgent、Rails、TaskLoop 四元组、工具、子代理 |
| 05 | [agentteams 模块](05-agentteams-module.md) | LeaderTeammateAgentTeam、TeamAgent 双角色、TeamBackend |
| 06 | [agentevolving 与 autoharness 模块](06-agentevolving-and-autoharness-module.md) | Trainer RL 优化、7 stage 自动改码 |
| 07 | [extensions 与 spi 模块](07-extensions-and-spi-module.md) | SPI 工厂、存储后端、RedisCheckpointer、沙箱 |
| 08 | [dev_tools 模块](08-dev-tools-module.md) | AgentBuilder、Tune 调优链、SkillCreator/Evaluator |
| 09 | [依赖关系](09-dependencies.md) | 内部依赖图、外部依赖表、存储后端矩阵 |
| 10 | [运行方式](10-running-guide.md) | 安装、CLI 入口、编程式使用、测试 |
| — | [业界对比](industry-comparison.md) | Java 生态对比（Spring AI/LangChain4j）+ 跨语言 Python agent-core 对照 |
| — | [features/coding/README](features/coding/README.md) | Coding 能力特性索引 |

## 四、增量更新流程

### 4.1 取增量提交

```bash
cd D:\jiuwen\main\agent-core-java
# 取基线到 HEAD 的增量提交
git log 695089224..HEAD --oneline
# 取增量文件变更统计
git diff 695089224..HEAD --stat
```

### 4.2 提交→文档映射表

| 提交特征（路径/前缀） | 影响路径 | 目标文档 |
|----------------------|---------|---------|
| core 引擎变更 | `src/main/java/com/openjiuwen/core/**` | `03-core-module.md` |
| harness/deepagents 变更 | `harness/**`, `deepagents/**` | `04-harness-and-deepagents-module.md` |
| agentteams 变更 | `agentteams/**` | `05-agentteams-module.md` |
| agentevolving/autoharness 变更 | `agentevolving/**`, `autoharness/**` | `06-agentevolving-and-autoharness-module.md` |
| extensions/spi 变更 | `extensions/**`, `spi/**` | `07-extensions-and-spi-module.md` |
| dev_tools 变更 | `dev_tools/**` | `08-dev-tools-module.md` |
| pom.xml 依赖变更 | `pom.xml` | `09-dependencies.md` |
| README/Makefile/脚本 | `README`, `Makefile`, `scripts` | `10-running-guide.md` |
| 架构级变更 | 跨多模块 | `02-overall-architecture.md` + 对应模块文档 |
| 对比维度变更 | — | `industry-comparison.md` |

### 4.3 更新步骤

1. `git log 695089224..HEAD --oneline` 取增量提交列表
2. `git diff 695089224..HEAD --stat` 取文件变更统计
3. 按提交→文档映射表分析 diff，确定需更新的文档
4. 更新对应文档内容（类清单、行号、机制描述）
5. 追加本文件第五节"更新记录表"
6. `grep` 验证交叉引用无断链
7. 更新基线提交为本轮 HEAD
8. 提交文档变更

### 4.4 更新检查清单（8 项）

- [ ] 确认基线提交（`git log -1 --format=%H`）
- [ ] 取增量提交（`git log 695089224..HEAD --oneline`）
- [ ] 分类 diff（按路径映射到目标文档）
- [ ] 更新对应文档内容
- [ ] 追加更新记录表
- [ ] 验证交叉引用（`grep` 断链检测）
- [ ] 更新基线提交
- [ ] 提交文档变更

## 五、更新记录表

| 日期 | 基线提交 | 更新文档 | 更新人 | 说明 |
|------|---------|---------|--------|------|
| 2026-08-05 | 695089224 | 全部（初始生成） | TRAE | 初始文档化：00-10 主文档 + 业界对比 + features/coding 索引 |

## 六、附录:git 命令速查

```bash
# 查看最新提交
git log -n 5 --pretty=format:"%h | %ad | %s" --date=format:"%Y-%m-%d %H:%M:%S %z"

# 查看完整 HEAD 哈希
git log -1 --pretty=format:"%H"

# 查看分支状态
git status --short --branch

# 查看 tag
git describe --tags --always

# 取增量提交
git log 695089224..HEAD --oneline

# 取增量文件变更
git diff 695089224..HEAD --stat
```

## 七、附录:文档→模块映射表

| 文档 | 对应源码包 | 关键类入口 |
|------|-----------|-----------|
| 03-core-module | `com.openjiuwen.core` | [Pregel](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/graph/pregel/Pregel.java#L24), [Runner](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/runner/Runner.java#L43), [ReActAgent](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/agents/ReActAgent.java#L77) |
| 04-harness | `com.openjiuwen.harness`, `deepagents` | [DeepAgent](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/deep_agent/DeepAgent.java#L97), [HarnessFactory](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/factory/HarnessFactory.java#L41) |
| 05-agentteams | `com.openjiuwen.agentteams` | [LeaderTeammateAgentTeam](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/LeaderTeammateAgentTeam.java#L26), [TeamAgent](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/agent/TeamAgent.java#L81) |
| 06-evolving | `agentevolving`, `autoharness` | [Trainer](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentevolving/trainer/Trainer.java#L47), [AutoHarnessOrchestrator](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/orchestrator/AutoHarnessOrchestrator.java#L42) |
| 07-extensions | `extensions`, `spi` | [RedisCheckpointer](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/extensions/checkpointer/redis/RedisCheckpointer.java#L48), [KVStoreFactory](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/spi/store/KVStoreFactory.java#L25) |
| 08-dev-tools | `dev_tools` | [AgentBuilder](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/agent_builder/AgentBuilder.java#L31), [Trainer](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/tune/trainer/Trainer.java#L33) |
