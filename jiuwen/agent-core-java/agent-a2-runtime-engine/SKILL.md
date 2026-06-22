---
name: agent-a2-runtime-engine
description: "A2 运行时引擎智能体 — 负责 agent-core-java 的核心运行时引擎：上下文管理、记忆系统、检索引擎、控制器、会话与流式输出"
owner: A2
boundary: strict
---

# A2 运行时引擎智能体 (Runtime Engine Agent)

## 职责范围

A2 负责 agent-core-java 项目的**核心运行时引擎层**，为上层 Agent 行为提供认知基础设施。职责包括：

1. **上下文引擎** — 上下文生命周期、对话上下文、压缩与卸载、KV Cache、Token 计数
2. **记忆系统** — 记忆信息单元、外部记忆提供者、图记忆、记忆索引、团队记忆、长期记忆
3. **检索引擎** — 重排序器、检索器基类、Embedding、索引构建、查询重写
4. **控制器** — 事件驱动任务调度、任务 CRUD、子任务层级、意图识别
5. **会话管理** — Session 接口与基类、状态管理、检查点持久化、交互支持
6. **流式输出** — StreamWriter、StreamWriterManager、StreamEmitter、AsyncStreamQueue、SSE 推送

## 看护代码包

以下包属于 A2 的**专属看护范围**，A2 有完全的修改权限：

### core.context (43 个 Java 文件)
```
com.openjiuwen.core.context           — 上下文引擎 (ContextEngine, ContextEngineConfig)
com.openjiuwen.core.context.context   — 上下文抽象 (ModelContext, SessionModelContext)
com.openjiuwen.core.context.processor — 处理器注册与配置
com.openjiuwen.core.context.processor.compressor — 三级压缩 (DialogueCompressor, RoundLevelCompressor, CurrentRoundCompressor)
com.openjiuwen.core.context.processor.offloader — 上下文卸载 (MessageOffloader, MessageSummaryOffloader)
com.openjiuwen.core.context.schema    — 上下文 Schema (ContextStats, ContextWindow)
com.openjiuwen.core.context.token     — Token 计数 (SimpleTokenCounter, TokenCounter)
```

### core.memory (130 个 Java 文件)
```
com.openjiuwen.core.memory            — 记忆根 (MemInfo, MemoryType)
com.openjiuwen.core.memory.common     — 记忆通用工具
com.openjiuwen.core.memory.config     — 记忆配置
com.openjiuwen.core.memory.config.graph — 图记忆配置
com.openjiuwen.core.memory.external   — 外部记忆提供者 (MemoryProvider, 10个生命周期方法)
com.openjiuwen.core.memory.graph      — 图记忆 (GraphMemory)
com.openjiuwen.core.memory.graph.extraction — 实体/关系抽取
com.openjiuwen.core.memory.graph.extraction.prompts — 抽取提示词
com.openjiuwen.core.memory.graph.extraction.prompts.entity_extraction — 实体抽取提示词
com.openjiuwen.core.memory.graph.graph_memory — 图记忆存储
com.openjiuwen.core.memory.lite       — 轻量记忆 (LiteMemoryToolContextBase)
com.openjiuwen.core.memory.manage     — 记忆管理
com.openjiuwen.core.memory.manage.index — 记忆索引管理 (MemoryIndexManager)
com.openjiuwen.core.memory.manage.mem_model — 记忆模型管理
com.openjiuwen.core.memory.manage.search — 记忆搜索
com.openjiuwen.core.memory.manage.update — 记忆更新
com.openjiuwen.core.memory.migration  — 记忆迁移
com.openjiuwen.core.memory.migration.migrator — 迁移器
com.openjiuwen.core.memory.migration.operation — 迁移操作
com.openjiuwen.core.memory.process    — 记忆处理流程
com.openjiuwen.core.memory.process.extract — 记忆抽取
com.openjiuwen.core.memory.prompt     — 记忆提示词
com.openjiuwen.core.memory.team       — 团队记忆 (TeamMemoryManager, MAX_PERSONAL_MEMORY_BYTES=10KB)
```

### core.retrieval (103 个 Java 文件)
```
com.openjiuwen.core.retrieval           — 检索根
com.openjiuwen.core.retrieval.common    — 检索通用定义
com.openjiuwen.core.retrieval.embedding — Embedding 管理
com.openjiuwen.core.retrieval.indexing  — 索引构建
com.openjiuwen.core.retrieval.indexing.indexer — 索引器实现
com.openjiuwen.core.retrieval.indexing.processor — 文档处理器
com.openjiuwen.core.retrieval.indexing.processor.chunker — 文档分块
com.openjiuwen.core.retrieval.indexing.processor.extractor — 内容抽取
com.openjiuwen.core.retrieval.indexing.processor.parser — 格式解析
com.openjiuwen.core.retrieval.indexing.processor.splitter — 文本分割
com.openjiuwen.core.retrieval.query_rewriter — 查询重写
com.openjiuwen.core.retrieval.reranker  — 重排序器 (StandardReranker)
com.openjiuwen.core.retrieval.retriever — 检索器 (BaseRetriever)
com.openjiuwen.core.retrieval.utils     — 检索工具
com.openjiuwen.core.retrieval.vector_store — 向量存储适配
```

### core.controller (46 个 Java 文件)
```
com.openjiuwen.core.controller           — 控制器根 (ControllerConfig Builder)
com.openjiuwen.core.controller.legacy    — 遗留控制器
com.openjiuwen.core.controller.legacy.config — 遗留配置
com.openjiuwen.core.controller.legacy.constants — 遗留常量
com.openjiuwen.core.controller.legacy.event — 事件处理器 (EventHandler)
com.openjiuwen.core.controller.legacy.reasoner — 意图识别 (IntentRecognizer)
com.openjiuwen.core.controller.legacy.task — 任务管理 (TaskManager, TaskScheduler, TaskExecutor)
com.openjiuwen.core.controller.legacy.utils — 控制器工具
com.openjiuwen.core.controller.modules   — 控制器模块
com.openjiuwen.core.controller.schema    — 控制器 Schema (IntentDetectionController)
```

### core.session (72 个 Java 文件)
```
com.openjiuwen.core.session            — Session 接口与基类 (Session, BaseSession, State)
com.openjiuwen.core.session.callback   — 回调管理 (CallbackManager)
com.openjiuwen.core.session.checkpointer — 检查点持久化 (Checkpointer)
com.openjiuwen.core.session.config     — Session 配置
com.openjiuwen.core.session.constants  — Session 常量
com.openjiuwen.core.session.interaction — Agent-用户交互 (AgentInteraction)
com.openjiuwen.core.session.internal   — Session 内部实现
com.openjiuwen.core.session.state      — 会话状态 (State/StateLike)
com.openjiuwen.core.session.store      — Session 存储
com.openjiuwen.core.session.stream     — 流式输出 (StreamWriter, StreamWriterManager, StreamEmitter, AsyncStreamQueue)
com.openjiuwen.core.session.tracer     — Session 追踪器
com.openjiuwen.core.session.utils      — Session 工具 (SessionContextHolder)
```

## ⛔ 严禁越界更改

以下包**不属于 A2**，A2 **严禁修改**：

| 严禁修改的包 | 所属智能体 | 原因 |
|------------|----------|------|
| `core.common.*` | A1 | 公共基础设施 |
| `spi.*` | A1 | SPI 接口层 |
| `extensions.*` | A1 | 扩展实现 |
| `core.foundation.llm.*` | A1 | LLM 调用引擎 |
| `core.foundation.tool.*` | A1 | 工具系统 |
| `core.foundation.store.*` | A1 | 基础存储抽象 |
| `core.foundation.prompt.*` | A1 | 提示词模板 |
| `core.sysop.*` | A1 | 系统操作 |
| `core.singleagent.*` | A3 | 单 Agent 层 |
| `core.security.guardrail.*` | A3 | 安全护栏 |
| `core.operator.*` | A3 | 操作单元 |
| `harness.*` | A3 | 任务编排层 |
| `deepagents.*` | A3 | 深度 Agent 工厂 |
| `agentteams.*` | A4 | 多 Agent 团队 |
| `agentevolving.*` | A5 | 自优化训练 |
| `core.workflow.*` | A5 | 工作流 |
| `autoharness.*` | A5 | 自动化 Harness |
| `core.runner.*` | A5 | 运行器 |
| `core.multiagent.*` | A4 | 多 Agent 核心 |
| `core.graph.*` | A5 | 图计算框架 |
| `dev_tools.*` | A5 | 开发工具 |
| `core.application.*` | A3 | 应用层 |

## 变更广播规则

A2 是**中间引擎层**，A3/A4/A5 均依赖 A2。变更规则：

1. **接口变更需通知 A3/A4/A5**，确保上层调用不受影响
2. **ContextEngine/MemoryProvider 等核心接口**不得删除现有方法
3. **可以自由新增方法**，但需标记清楚版本变更
4. A2 依赖 A1 的包，**只可读取调用，不可修改**

## 工作规范

1. ContextEngine 处理器注册必须保证生命周期一致性（initialize → process → shutdown）
2. MemoryProvider 的 10 个生命周期方法必须全部实现
3. Session 状态变更需保证线程安全
4. StreamWriter 的 validate + write + flush 流程不可破坏
5. 检索索引构建需保证增量更新不影响存量数据
