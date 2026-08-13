# openJiuwen Core Java — Code Wiki

本 Wiki 是对 [agent-core-java](file:///D:/jiuwen/main/agent-core-java) 仓库（`openJiuwen Core Java`，`com.openjiuwen:agent-core-java:0.1.14`）源码的结构化解读文档，覆盖项目整体架构、各主要模块职责、关键类与函数说明、模块间依赖关系以及项目运行方式等关键信息。

> Java 17 SDK，Apache-2.0 开源。独立 Java 实现（非 Python 绑定），源码注释多次出现 "Mirrors Python's ..." 标注。

## 文档导航

| 序号 | 文档 | 内容简介 |
|------|------|----------|
| 00 | [路标与增量更新说明](00-roadmap-and-incremental-update.md) | 任务时间线、基线提交、产物清单、增量更新流程 |
| 01 | [项目概述](01-project-overview.md) | 定位、核心能力、技术栈、仓库结构、快速开始 |
| 02 | [整体架构](02-overall-architecture.md) | 分层架构、十大设计模式、运行时数据流、关键概念 |
| 03 | [core 模块](03-core-module.md) | 引擎层：Pregel BSP 图引擎、Runner 单例、Session、ReActAgent |
| 04 | [harness 与 deepagents 模块](04-harness-and-deepagents-module.md) | 编码框架：DeepAgent、Rails、TaskLoop 四元组、工具、子代理 |
| 05 | [agentteams 模块](05-agentteams-module.md) | 多 agent 团队：LeaderTeammateAgentTeam、TeamAgent 双角色 |
| 06 | [agentevolving 与 autoharness 模块](06-agentevolving-and-autoharness-module.md) | RL 自优化 + 端到端自动改码 7 stages |
| 07 | [extensions 与 spi 模块](07-extensions-and-spi-module.md) | SPI 工厂、存储后端、RedisCheckpointer、沙箱 |
| 08 | [dev_tools 模块](08-dev-tools-module.md) | AgentBuilder、Tune 调优链、SkillCreator/Evaluator |
| 09 | [依赖关系](09-dependencies.md) | 内部依赖图、外部依赖表、存储后端矩阵 |
| 10 | [运行方式](10-running-guide.md) | 安装、CLI 入口、编程式使用、测试与质量 |
| — | [业界对比](industry-comparison.md) | Java 生态对比（Spring AI/LangChain4j）+ 跨语言 Python agent-core 对照 |

## Coding 能力特性

agent-core-java 具备完整的 coding 能力骨架，覆盖代码编辑、导航、诊断、执行、审查、规划、子代理协作、自动改码、插件热加载、安全控制与编码记忆等维度。**部分能力相比 Python 版存在差距，如实标注实现状态**（✅已实现 / ⚠️部分实现）。特性清单如下，完整索引见 [features/coding/README](features/coding/README.md)。

| 特性 | 状态 | 说明 |
|------|------|------|
| [代码编辑](features/coding/code-editing.md) | ⚠️ 部分 | 裸读写已实现；精确字符串替换/stale-write 保护/操作审计未实现 |
| [代码导航](features/coding/code-navigation.md) | ✅ 已实现 | LSP 8 项操作 + searchText 搜索（简化版） |
| [代码诊断](features/coding/code-diagnostics.md) | ⚠️ 部分 | 基础设施齐全，双钩子自动闭环未接通 |
| [代码执行](features/coding/code-execution.md) | ✅ 已实现 | Bash/PowerShell/CodeTool + 注入检测 + 破坏性警告 |
| [代码审查](features/coding/code-review.md) | ✅ 已实现 | VerificationAgent 对抗性验证 + VERDICT |
| [编码规划](features/coding/code-planning.md) | ✅ 已实现 | PlanAgent + TodoTool + 停止条件评估器 |
| [子代理协作](features/coding/coding-subagents.md) | ✅ 已实现 | 探索-规划-编码-验证四阶段 |
| [编码记忆](features/coding/coding-memory.md) | ⚠️ 部分 | 类+3工具+索引注入；向量+BM25 per-turn 召回未接入 |
| [自动改码](features/coding/auto-harness.md) | ✅ 已实现 | autoharness 7 stages + CI 修复循环 |
| [插件热加载](features/coding/plugin-hot-loading.md) | ⚠️ 部分 | 仅 SKILL 单类；6 类资源事务性热加载未实现 |
| [安全控制](features/coding/coding-security.md) | ⚠️ 部分 | 3 层权限+注入检测+警告；stale-write/审计/5层管道未实现 |

> 详见 [features/coding/README](features/coding/README.md)。

## 项目速览

**openJiuwen Core Java** 是一个面向 Java 17 的智能体开发 SDK，核心能力包括：

- **智能体引擎**：ReActAgent（Reasoning→Acting→Observation）与 WorkflowAgent 两种预置 Agent
- **高性能图引擎**：Pregel BSP 模型，虚拟线程并行执行，状态保存与中断恢复
- **编码框架**：DeepAgent + Rails 回调 + TaskLoop 四元组 + 四阶段子代理（探索-规划-编码-验证）
- **多 agent 团队**：LeaderTeammate 模型，TeamAgent 单实现双角色，TeamBackend 共享 DB
- **RL 自优化**：Trainer 编排 evaluate→update→writeback，三维度优化器（Instruction/Tool/Memory）
- **端到端自动改码**：autoharness 7 stages（assess→plan→implement→verify→commit→publish_pr→learnings）
- **SPI 扩展**：ServiceLoader + 编程式注册，统一存储后端（Redis/Milvus/Chroma/pgvector/ES）

## 快速开始

```java
// 创建 DeepAgent 编码代理
DeepAgent agent = HarnessFactory.createDeepAgent(
    card, config, workspace);
Map<String, Object> result = agent.invoke(Map.of("query", "修复 main.py 的 bug"));
```

```bash
# CLI 入口
java -jar agent-core-java.jar --provider OpenAI --model gpt-4o --api-key xxx "你的问题"
```

> Java 17+，Maven 3.9+

## 许可证

本项目基于 Apache-2.0 许可证开源。

## 文档约定

- 源码路径引用使用 `com.openjiuwen/...` 形式表示相对于 `src/main/java/` 的包路径
- 类名、方法名使用 `反引号` 包裹
- 关键设计模式以 **加粗** 标注
- 代码示例尽量与仓库内 `examples/` 风格一致
- 所有类/函数引用均带 `file:///` 绝对路径行号锚点，可点击直达源码行
