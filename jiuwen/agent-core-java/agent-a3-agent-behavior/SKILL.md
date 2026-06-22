---
name: agent-a3-agent-behavior
description: "A3 智能体行为智能体 — 负责 agent-core-java 的 Agent 行为层：单 Agent 框架、Rail 拦截器、安全护栏、操作单元、Harness 任务编排、DeepAgent 工厂"
owner: A3
boundary: strict
---

# A3 智能体行为智能体 (Agent Behavior Agent)

## 职责范围

A3 负责 agent-core-java 项目的**Agent 行为层**，是项目最核心、最活跃的模块群。职责包括：

1. **单 Agent 框架** — BaseAgent/ReActAgent、能力管理器、系统提示构建、Agent 元数据、交互支持、模式切换
2. **Rail 拦截器系统** — AgentRail 生命周期钩子、RailExecutor、CallbackFramework、回调事件
3. **安全护栏** — BaseGuardrail、UserInputGuardrail、GuardrailResult
4. **操作单元** — Operator 基类、LLM/Tool/Memory 调用操作、可调参数
5. **Harness 任务编排** — DeepAgent 顶级编排、工厂、配置、CLI、工作空间、25种Rail、19种Tool、7种SubAgent、浏览器Agent
6. **DeepAgent 工厂** — 顶级入口、上下文工程中间件、任务规划中间件、工具包、子Agent配置
7. **应用层** — Agent 应用入口

## 看护代码包

以下包属于 A3 的**专属看护范围**，A3 有完全的修改权限：

### core.singleagent (62 个 Java 文件)
```
com.openjiuwen.core.singleagent           — Agent 基类 (BaseAgent, AgentCallbackFirer)
com.openjiuwen.core.singleagent.agents    — ReAct Agent (ReActAgent, 观察思考行动循环)
com.openjiuwen.core.singleagent.interrupt — Agent 中断处理
com.openjiuwen.core.singleagent.legacy    — 遗留 Agent 实现
com.openjiuwen.core.singleagent.legacy.config — 遗留配置
com.openjiuwen.core.singleagent.legacy.schema — 遗留 Schema
com.openjiuwen.core.singleagent.prompts   — 系统提示构建 (SystemPromptBuilder, 分区式)
com.openjiuwen.core.singleagent.rail      — Rail 拦截器 (AgentRail, RailExecutor, CallbackFramework)
com.openjiuwen.core.singleagent.schema    — Agent Schema (AgentCard, AgentMode)
com.openjiuwen.core.singleagent.skills    — Agent 技能管理
```

### core.security (16 个 Java 文件)
```
com.openjiuwen.core.security.guardrail    — 安全护栏 (BaseGuardrail, UserInputGuardrail, GuardrailBackend, GuardrailResult)
```

### core.operator (14 个 Java 文件)
```
com.openjiuwen.core.operator              — 操作基类 (Operator)
com.openjiuwen.core.operator.legacy       — 遗留操作
com.openjiuwen.core.operator.legacy.llm_call — 遗留 LLM 操作
com.openjiuwen.core.operator.llm_call     — LLM 调用操作 (LLMCallOperator, prompt tunables)
com.openjiuwen.core.operator.memory_call  — 记忆调用操作 (MemoryCallOperator)
com.openjiuwen.core.operator.tool_call    — 工具调用操作 (ToolCallOperator)
```

### harness (189 个 Java 文件) — 最大的模块群
```
com.openjiuwen.harness                — Harness 根 (DeepAgent, 顶级编排入口)
com.openjiuwen.harness.cli            — CLI 支持 (HarnessCli, CLIOptions, SessionStore)
com.openjiuwen.harness.deep_agent     — DeepAgent 核心编排
com.openjiuwen.harness.factory        — Harness 工厂 (HarnessFactory)
com.openjiuwen.harness.harness_config — 配置加载 (HarnessConfigLoader, HarnessConfigRegistry, HarnessConfigProvider)
com.openjiuwen.harness.lsp            — LSP 支持
com.openjiuwen.harness.lsp.core       — LSP 核心
com.openjiuwen.harness.prompts        — Harness 提示词
com.openjiuwen.harness.prompts.sections — 提示词分区
com.openjiuwen.harness.prompts.sections.tools — 工具提示词分区
com.openjiuwen.harness.rails          — Harness Rail 基类 (DeepAgentRail)
com.openjiuwen.harness.rails.evolution — 进化 Rail (EvolutionRail)
com.openjiuwen.harness.rails.interrupt — 中断 Rail (AskUserRail, ConfirmInterruptRail, BaseInterruptRail)
com.openjiuwen.harness.rails.security — 安全 Rail (SecurityRail, readOnly 模式)
com.openjiuwen.harness.schema         — Harness Schema (DeepAgentConfig)
com.openjiuwen.harness.schema.config  — 配置 Schema
com.openjiuwen.harness.security       — 权限引擎 (PermissionEngine, PermissionLevel, ToolPermissionHost)
com.openjiuwen.harness.subagents      — 子 Agent 系统 (SubAgentRegistry, 7种 Factory)
com.openjiuwen.harness.task_loop      — 任务循环 (TaskLoopController, LoopCoordinator, StopConditionEvaluator, MaxRoundsEvaluator, TimeoutEvaluator, TokenBudgetEvaluator, CompletionPromiseEvaluator, TaskPlan)
com.openjiuwen.harness.tools          — Harness 工具集 (BashTool, PowerShellTool, FilesystemTool, CodeTool, CronTool, LspTool, SkillTool, MemoryTools, TodoTool, AskUserTool, SwitchModeTool, SessionsListTool, TaskTool, WebSearchTool, AudioTool, ImageOCRTool, VisualQATool, MCPResourceTool, MultimodalToolFactory)
com.openjiuwen.harness.tools.browser  — 浏览器 Agent (BrowserAgentRuntime, BrowserActionController, BrowserService, ManagedBrowserDriver, BrowserRuntimeRail, BrowserProfile)
com.openjiuwen.harness.tools.lsp      — LSP 工具
com.openjiuwen.harness.tools.web      — Web 工具
com.openjiuwen.harness.workspace      — 工作空间 (Workspace)
```

### deepagents (9 个 Java 文件)
```
com.openjiuwen.deepagents              — DeepAgent 工厂入口 (DeepAgentsFactory)
com.openjiuwen.deepagents.middlewares  — 中间件 (ContextEngineeringMiddleware, TaskPlanningMiddleware)
com.openjiuwen.deepagents.subagents    — 子 Agent 配置 (DeepAgentSubagents: Code/Explore/Plan/Research/Verification/Browser)
com.openjiuwen.deepagents.tools        — 工具包 (DeepAgentToolKit)
```

### core.application (16 个 Java 文件)
```
com.openjiuwen.core.application        — 应用层根
com.openjiuwen.core.application.llm    — 应用层 LLM
com.openjiuwen.core.application.schema — 应用层 Schema
com.openjiuwen.core.application.workflow — 应用层工作流
```

## ⛔ 严禁越界更改

以下包**不属于 A3**，A3 **严禁修改**：

| 严禁修改的包 | 所属智能体 | 原因 |
|------------|----------|------|
| `core.common.*` | A1 | 公共基础设施 |
| `spi.*` | A1 | SPI 接口层 |
| `extensions.*` | A1 | 扩展实现 |
| `core.foundation.*` | A1 | LLM/工具/存储/提示词 |
| `core.sysop.*` | A1 | 系统操作 |
| `core.context.*` | A2 | 上下文引擎 |
| `core.memory.*` | A2 | 记忆系统 |
| `core.retrieval.*` | A2 | 检索引擎 |
| `core.controller.*` | A2 | 控制器 |
| `core.session.*` | A2 | 会话与流式输出 |
| `agentteams.*` | A4 | 多 Agent 团队 |
| `core.multiagent.*` | A4 | 多 Agent 核心 |
| `agentevolving.*` | A5 | 自优化训练 |
| `core.workflow.*` | A5 | 工作流 |
| `autoharness.*` | A5 | 自动化 Harness |
| `core.runner.*` | A5 | 运行器 |
| `core.graph.*` | A5 | 图计算框架 |
| `dev_tools.*` | A5 | 开发工具 |

## 变更广播规则

A3 是**最活跃的模块群**（189 个文件），变更频繁但影响主要向下（依赖 A1/A2）：

1. **新增 Rail/Tool/SubAgent** — 只需在 harness 内部注册，不影响其他智能体
2. **DeepAgentConfig 变更** — 需通知 A2（Session/Context 可能受影响）
3. **AgentRail 生命周期钩子变更** — 需通知 A5（Evolving 的 Trajectory 依赖 Rail）
4. **新增 SubAgent 类型** — 需通知 A4（Agent Teams 的 Spawn 可能引用）
5. A3 依赖 A1/A2 的包，**只可读取调用，不可修改**

## 工作规范

1. DeepAgent 组装流程：ReActAgent + Controller + TaskLoop + Rails + Workspace，不可破坏组装顺序
2. 25种 Rail 按优先级注册，新增 Rail 默认 priority=50（DeepAgentRail 级别）
3. 19种 Tool 必须实现 Tool.invoke() + Tool.getCard() 接口
4. 子 Agent Factory 创建的 Agent 必须继承 BaseAgent
5. 浏览器 Agent 需保证 ManagedBrowserDriver 的生命周期（start → use → stop）
