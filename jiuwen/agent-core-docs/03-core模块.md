# 03 - core 模块

`openjiuwen/core/` 是 openJiuwen Core 的**公共 SDK 与运行时引擎层**，提供智能体、工作流、会话、LLM/工具抽象、上下文引擎、系统操作、安全护栏等基础能力。它是 `harness`、`agent_teams` 等上层模块的根基。

> 路径前缀：本节文件路径均相对于 `openjiuwen/core/`

## 3.1 模块总览

| 子模块 | 职责 |
|--------|------|
| `common/` | 共享基础：`BaseCard`、`Param`、`StatusCode`/`BaseError`、日志、任务组、字典工具 |
| `graph/` | Pregel 异步并行图执行引擎 |
| `workflow/` | 工作流 API（Start/End/LLMComponent/Workflow/WorkflowCard） |
| `foundation/` | LLM 与工具基础抽象（`Model`、`Tool`、`ToolCard`） |
| `controller/` | 控制器 / 任务管理器系统 |
| `runner/` | Runner 单例与 ResourceMgr 资源管理器 |
| `session/` | 会话、VCS、检查点 |
| `context_engine/` | 上下文引擎（消息处理器链、token 窗口） |
| `single_agent/` | ReActAgent 与 WorkflowAgent 智能体 |
| `application/` | 应用级智能体（WorkflowAgent、LLMAgent） |
| `multi_agent/` | 多智能体团队基础 |
| `memory/` | 长期/会话记忆 |
| `retrieval/` | 检索/嵌入原语 |
| `sys_operation/` | 文件系统、Shell、代码执行（本地/沙箱） |
| `security/` | 安全护栏（Guardrail） |
| `store/` | 存储抽象（KV Store） |
| `operator/` | 算子基础抽象 |

---

## 3.2 `common/` — 共享基础

提供全项目共用的基础类型与工具。

### 关键类与函数

- **`BaseCard`** — [common/schema/card.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/common/schema/card.py)
  - 所有 Card 的基类（Pydantic），字段：`id`（uuid4 hex 默认）、`name`、`description`
  - 是 `WorkflowCard`、`AgentCard`、`TeamCard`、`ToolCard`、`SysOperationCard` 的根类型
- **`StatusCode`** — [common/exception/](file:///D:/jiuwen/main/agent-core/openjiuwen/core/common/exception)：错误码枚举
- **`build_error(status_code, **kwargs)`** / **`BaseError`** / **`ExecutionError`**：集中式异常构造
- **`logger`** / **`workflow_logger`** / **`graph_logger`** / **`LogEventType`** — [common/logging/](file:///D:/jiuwen/main/agent-core/openjiuwen/core/common/logging)
- **`get_task_group()` / `get_task_manager()`** — [common/task_manager/](file:///D:/jiuwen/main/agent-core/openjiuwen/core/common/task_manager)：供 `Workflow._task_group_scope` 使用
- **`extract_leaf_nodes` / `format_path`** — [common/utils/dict_utils.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/common/utils/dict_utils.py)：供 `End` 组件使用
- 常量：`INPUTS_KEY`、`CONFIG_KEY`、`END_NODE_STREAM`、`INTERACTIVE_INPUT` — [common/constants/](file:///D:/jiuwen/main/agent-core/openjiuwen/core/common/constants)

### 设计模式
- **Card 基类**：`BaseCard` 是所有元数据类型的根
- **错误构造器**：`build_error(StatusCode.X, ...)` 统一异常构造

---

## 3.3 `graph/` — Pregel 异步并行图引擎

将工作流建模为 `Executable` 节点的有向图，通过 Pregel 风格的超步循环进行异步并行调度，基于 Channel 的状态管理与流式 Actor 实现节点间流式传输。

### 关键类

| 类 | 文件 | 职责 |
|----|------|------|
| `Executable` | [graph/executable.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/graph/executable.py) | 图节点抽象基类；声明 `on_invoke`/`on_stream`/`on_collect`/`on_transform` 生命周期 |
| `ExecutableGraph` | [graph/base.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/graph/base.py) | 桥接图执行到 `Executable` 接口 |
| `Graph` (ABC) | [graph/base.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/graph/base.py) | 构建器接口：`start_node`/`end_node`/`add_node`/`add_edge`/`add_conditional_edges`/`compile` |
| `Vertex` | [graph/vertex.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/graph/vertex.py) | 节点运行时包装器；编排四能力、重试/超时、错误恢复、追踪、流式生产/消费 |
| `Pregel` | [graph/pregel/engine.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/graph/pregel/engine.py) | 引擎本体；`run(config)` 创建 `PregelLoop` 并循环 `run_step()` |
| `PregelLoop` | [graph/pregel/engine.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/graph/pregel/engine.py) | 实现超步循环（`init`、`run_step`） |
| `PregelNode` | [graph/pregel/base.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/graph/pregel/base.py) | 节点执行契约 |
| `GraphBuilder` / `PregelGraph` | [graph/pregel/builder.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/graph/pregel/builder.py) | 具体 `Graph` 实现，累积节点/边并 `compile()` 出 `Pregel` |
| `Channel` 族 | [graph/pregel/channels.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/graph/pregel/channels.py) | 状态容器（`Topic`、`LastValue`、`Context`），`update`/`get`/`consume` 语义 |
| `PregelTask` | [graph/pregel/task.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/graph/pregel/task.py) | 超步内一个节点的调度单元 |
| `GraphState` | [graph/graph_state.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/graph/graph_state.py) | `Vertex` 通过 `session.state()` 读取的状态容器 |
| `AsyncAtomicNode` | [graph/atomic_node.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/graph/atomic_node.py) | 提供 `atomic_invoke` 语义 |

### 关键方法

`Vertex`：
- `init` / `call` / `stream_call`：初始化与批量/流式调用
- `_run_executable_with_retry`：带重试的执行
- `_run_error_recovery`：错误恢复（委托 `Runner.callback_framework.trigger_until`）
- `_pre_invoke` / `_post_invoke` / `_pre_stream` / `_post_stream`：前后钩子

### 设计模式
- **Pregel/BSP 超步循环**：节点在步内并行，步末同步
- **策略映射**：`Vertex._run_executable` 按四能力分派
- **异步生成器**驱动流式（`on_stream`/`on_transform` 产出 `AsyncIterator[Output]`）
- **回调框架解耦**：错误恢复与超时错误构造委托给 `Runner.callback_framework.trigger_until`

---

## 3.4 `workflow/` — 工作流 API

用户面向的工作流构建 API。`Workflow` 持有 `WorkflowCard`（元数据），委托内部 `BaseWorkflow`（由 `PregelGraph` 支撑）。组件实现 `Executable`，通过 schema（输入/输出映射）与边组合。

### 关键类

| 类 | 文件 | 职责 |
|----|------|------|
| `Workflow` | [workflow/workflow.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/workflow/workflow.py) | 用户 API；包装 `BaseWorkflow(WorkflowConfig, PregelGraph)` |
| `WorkflowCard` | [workflow/base.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/workflow/base.py) | Pydantic 元数据，扩展 `BaseCard`，加 `version`、`input_params` |
| `Start` | [workflow/components/flow/start_comp.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/workflow/components/flow/start_comp.py) | 入口组件，透传输入 |
| `End` | [workflow/components/flow/end_comp.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/workflow/components/flow/end_comp.py) | 终止组件，通过 `responseTemplate` 格式化最终输出 |
| `LLMComponent` | [workflow/components/llm/llm_comp.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/workflow/components/llm/llm_comp.py) | 包装 `LLMExecutable` 的可组合组件 |
| `LLMExecutable` | [workflow/components/llm/llm_comp.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/workflow/components/llm/llm_comp.py) | 实现四能力；校验 `template_content`/`output_config`/`response_format` |
| `ComponentExecutable` / `ComponentComposable` | [workflow/components/component.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/workflow/components/component.py) | 基类；`to_executable()` 产出可执行对象 |
| `ComponentAbility` | [workflow/components/base.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/workflow/components/base.py) | 枚举：INVOKE/STREAM/COLLECT/TRANSFORM |

### 关键方法

`Workflow`：
- `set_start_comp(id, comp, inputs_schema)` / `set_end_comp(id, comp, inputs_schema)`
- `add_workflow_comp(id, comp, inputs_schema)` / `add_connection(from, to)`
- `invoke(inputs, session)` / `stream(inputs, session)` / `collect` / `transform`

`End`：
- `set_mix()`：支持并发批量+流式数据源
- `TemplateProcessor` / `TemplateBatchProcessor`：`{{var}}` 渲染与流式分段

### 关键函数
- `TemplateUtils.render_template(template, inputs)`：`{{x}}` → `$x` 后用 `string.Template.safe_substitute`
- `generate_workflow_key(id, version)`：生成工作流键

### 设计模式
- **Card/Config 分离**：`WorkflowCard`（元数据）+ `WorkflowConfig`（运行时）+ `Workflow`（行为）
- **可组合 vs 可执行**：`ComponentComposable.to_executable()` 产出 `ComponentExecutable`
- **Schema 驱动 I/O**：输入/输出为 dict schema 或 `Transformer` 可调用对象；`Vertex` 解析 `${comp_id.field}` 引用

---

## 3.5 `foundation/` — LLM 与工具基础

`foundation/llm` 提供 LLM 客户端抽象；`foundation/tool` 提供 `Tool` 基类、`ToolCard` 与工具元数据。

### 关键类

| 类 | 文件 | 职责 |
|----|------|------|
| `Model` | [foundation/llm/model.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/foundation/llm/model.py) | LLM 客户端抽象，`invoke`/`stream` 与模型配置处理 |
| `UserMessage` / `AssistantMessage` / `SystemMessage` / `BaseMessage` | [foundation/llm/](file:///D:/jiuwen/main/agent-core/openjiuwen/core/foundation/llm) | 消息类型 |
| `ModelConfig` | [foundation/llm/](file:///D:/jiuwen/main/agent-core/openjiuwen/core/foundation/llm) | 模型配置 |
| `Tool`（经 `ToolCard`） | [foundation/tool/base.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/foundation/tool/base.py) | 工具基类；`_ToolMeta` 元类自动用 `ToolCallEvents` 包装 `invoke` |
| `ToolCard` | [foundation/tool/base.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/foundation/tool/base.py) | 扩展 `BaseCard`，加 `input_params`/`properties`/`parallel_safe`/`stateless`/`idempotent` |
| `ToolInfo` | [foundation/tool/schema.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/foundation/tool/schema.py) | `ToolInfo(name, description, parameters)` |

### 设计模式
- **Card 分离**：`ToolCard`（元数据，含安全标志）与 `Tool`（行为）分离
- **元类生命周期埋点**：`_ToolMeta.__call__` 自动为每个工具实例的 `invoke` 包装回调事件
- **安全标志一等公民**：`parallel_safe`、`stateless`、`idempotent` 用于调度与弹性 Rails

---

## 3.6 `controller/` — 控制器 / 任务管理器

编排智能体的事件/任务生命周期。`Controller` 装配 `TaskManager`、`EventQueue`、`TaskScheduler`、`EventHandler`，是 `ControllerAgent` 的核心组件。

### 关键类

| 类 | 文件 | 职责 |
|----|------|------|
| `Controller` | [controller/base.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/controller/base.py) | 持有 `AgentCard`、`AbilityManager`、`ContextEngine` 与任务子系统 |
| `TaskManager` / `EventQueue` / `TaskScheduler` / `EventHandler` | [controller/](file:///D:/jiuwen/main/agent-core/openjiuwen/core/controller) | 协作提交任务、排队事件、调度执行、处理事件 |
| `ControllerConfig` | [controller/config.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/controller/config.py) | 配置对象 |

### 关键方法

`Controller`：
- `init(card, config, ability_manager, context_engine)`：构造子系统并连线 `task_manager.set_on_task_submitted(task_scheduler.notify_task_submitted)`
- 属性：`event_queue`、`config`、`context_engine`、`ability_manager`、`task_manager`、`task_scheduler`、`event_handler`
- `set_event_handler(handler)`

### 设计模式
- **中介者**：`Controller` 中介于能力管理、上下文、任务调度与事件处理
- **观察者/钩子**：`set_on_task_submitted` 任务提交回调

---

## 3.7 `runner/` — Runner 单例与资源管理器

进程级单例 `Runner`，拥有 `ResourceMgr`（工作流/智能体/团队/工具/模型/提示词/sys_operation 注册表）、`AsyncCallbackFramework`、本地/分布式发布订阅、根任务组，并提供 `run_workflow`/`run_agent` 等高层入口。

### 关键类

| 类 | 文件 | 职责 |
|----|------|------|
| `Runner` | [runner/runner.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/runner/runner.py) | 单例代理，类级属性转发到 `GLOBAL_RUNNER` |
| `_Runner` | [runner/runner.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/runner/runner.py) | 全局实例类，持有 `_resource_manager`、`_callback_framework`、`_root_task_group` |
| `ResourceMgr` | [runner/resources_manager/resource_manager.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/runner/resources_manager/resource_manager.py) | 资源管理器，暴露 `add_*`/`get_*` 方法 |
| `RemoteAgent` | [runner/drunner/remote_client/remote_agent.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/runner/drunner/remote_client/remote_agent.py) | 远程智能体 |

### 关键方法/属性（`Runner` 类级）

- `resource_mgr` → `ResourceMgr`
- `callback_framework` → `AsyncCallbackFramework`
- `pubsub` / `dist_pubsub` / `system_reply_sub`
- `get_root_task_group()` / `set_config` / `get_config`
- `start` / `stop`
- `run_workflow` / `run_workflow_streaming` / `run_agent` / `run_agent_streaming`

### 关键函数
- `GLOBAL_RUNNER`：模块级单例实例

### 设计模式
- **单例 + 类属性代理**：`Runner` 通过 `_ClassProperty` 描述符转发到 `GLOBAL_RUNNER`，故 `Runner.resource_mgr` 无需实例化
- **资源注册表 / 服务定位器**：`ResourceMgr` 集中查找
- **回调框架单例**：`Runner.callback_framework` 是图、工具、护栏共用的全局事件总线

---

## 3.8 `session/` — 会话、VCS 与检查点

提供每会话运行时上下文：配置/环境、流式、追踪、父子谱系、KV-Cache 身份、版本化状态存储（VCS）用于检查点/恢复，以及检查点钩子用于工作流/智能体持久化与恢复。

### 关键类

| 类 | 文件 | 职责 |
|----|------|------|
| `Session`（工作流向） | [session/workflow.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/session/workflow.py) | 工作流执行上下文 |
| `Session`（智能体向） | [session/agent.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/session/agent.py) | 包装 `AgentSession`；携带 `session_id`、`Config`、`AgentCard`、`StreamWriterManager`、谱系、team_cache_scope |
| `BaseSession` / `NodeSession` | [session/session.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/session/session.py) | 声明 checkpointer 使用的接口 |
| `Config` | [session/](file:///D:/jiuwen/main/agent-core/openjiuwen/core/session) | 环境变量容器，`set_envs`/`get_env`/`get_envs` |
| `Checkpointer` (ABC) | [session/checkpointer/base.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/session/checkpointer/base.py) | 生命周期钩子 |
| `Storage` (ABC) | [session/checkpointer/base.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/session/checkpointer/base.py) | `save`/`recover`/`clear`/`exists` |
| `CheckpointerFactory` | [session/checkpointer/](file:///D:/jiuwen/main/agent-core/openjiuwen/core/session/checkpointer) | 工厂 |
| `Manager`（VCS） | [session/vcs/manager.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/session/vcs/manager.py) | 版本化状态管理，commit/history/restore |

### 关键方法

`Session`（智能体向）：
- `get_session_id()` / `get_parent_session_id()` / `bind_parent_session_id()`（不可变单归属）
- `get_env`/`get_envs` / `get_agent_id`/`name`/`description`
- `set_team_cache_scope` / `get_cache_identity`（返回 `KVCacheIdentity`）
- `pre_run` / `post_run`

`Checkpointer`（ABC 钩子）：
- `pre_workflow_execute` / `post_workflow_execute`
- `pre_agent_execute` / `post_agent_execute`
- `pre_agent_team_execute` / `post_agent_team_execute`
- `interrupt_agent_execute` / `session_exists` / `release` / `graph_store`
- 静态 `get_thread_id(session) = ":".join([session_id, workflow_id])`

### 关键函数
- `build_key(*parts)` / `build_key_with_namespace(session_id, namespace, entity_id, *suffixes)`：冒号连接的键构造
- 命名空间常量：`SESSION_NAMESPACE_AGENT`、`SESSION_NAMESPACE_AGENT_TEAM`、`SESSION_NAMESPACE_WORKFLOW`、`WORKFLOW_NAMESPACE_GRAPH`
- `create_agent_session(...)`

### 设计模式
- **Card + 内部状态**：`Session` 包装持有 `Config` 与流管理器的 `AgentSession`
- **不可变谱系**：`bind_parent_session_id` 强制单归属绑定
- **模板方法生命周期**：`Checkpointer` ABC 定义持久化钩子
- **命名空间键方案**：确定性、无碰撞的键

---

## 3.9 `context_engine/` — 上下文引擎

会话上下文的中央入口：注册/配置消息处理器，按会话创建隔离的 `ModelContext` 实例，应用处理器链（窗口限制、压缩等）。

### 关键类

| 类 | 文件 | 职责 |
|----|------|------|
| `ContextEngine` | [context_engine/context_engine.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/context_engine/context_engine.py) | 类属性 `_PROCESSOR_MAP`；构造接收 `ContextEngineConfig`/`workspace`/`sys_operation` |
| `ModelContext` / `SessionModelContext` | [context_engine/](file:///D:/jiuwen/main/agent-core/openjiuwen/core/context_engine) | 持有消息、处理器、token 计数器、窗口变换器 |
| `ContextProcessor` / `ContextWindow` / `ContextEngineConfig` | [context_engine/](file:///D:/jiuwen/main/agent-core/openjiuwen/core/context_engine) | 支撑类型 |
| `TiktokenCounter` | [context_engine/token/tiktoken_counter.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/context_engine/token/tiktoken_counter.py) | 默认 token 计数器 |
| `ContextUtils` | [context_engine/context/context_utils.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/context_engine/context/context_utils.py) | 含 `prefetch_openrouter_model_context_window_tokens` |

### 关键方法

`ContextEngine`：
- `register_window_mutator` / `clear_window_mutators`
- `create_context(context_id, session, *, processors, history_messages, token_counter)`（装饰器 `@_fw.emit_after(ContextEvents.CONTEXT_RETRIEVED)`）
- `get_context(context_id, session_id)`

### 设计模式
- **注册表**：`_PROCESSOR_MAP` 映射处理器类型名到类
- **池/缓存**：`_context_pool` 按 `session_id_context_id` 复用 `ModelContext`
- **装饰器回调发射**：`@_fw.emit_after(...)` 埋点上下文创建
- **最终窗口变换器**：可插拔的 mutator，最后应用

---

## 3.10 `single_agent/` — ReActAgent 与 WorkflowAgent

定义智能体抽象（`BaseAgent`）、智能体 Card/Config，以及具体智能体：ReAct 循环的 `ReActAgent` 与工作流驱动的 `WorkflowAgent`（在 `application` 中）。

### 关键类

| 类 | 文件 | 职责 |
|----|------|------|
| `BaseAgent` | [single_agent/base.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/single_agent/base.py) | 基类：`configure`、`invoke`/`stream`、ability_manager、context_engine、KV-Cache 钩子、HITL 处理器 |
| `ReActAgent` | [single_agent/agents/react_agent.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/single_agent/agents/react_agent.py) | 实现 ReAct 循环（推理→行动→观察→重复） |
| `ReActAgentConfig` | [single_agent/agents/react_agent.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/single_agent/agents/react_agent.py) | Pydantic 配置 |
| `AgentCard` | [single_agent/schema/agent_card.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/single_agent/schema/agent_card.py) | `BaseCard` + `input_params`/`output_params`/`interface_url` |
| `InterruptionState` / `WorkflowInterruptEntry` / `BaseInterruptionState` | [single_agent/](file:///D:/jiuwen/main/agent-core/openjiuwen/core/single_agent) | HITL 中断模型 |

### 关键方法

`ReActAgent`：
- `__init__(card: AgentCard)`：构建 `ContextEngine`、`SystemPromptBuilder`、`ToolInterruptHandler`、`KVCacheModelCallHook`
- `configure(config)`：运行时依赖变更时重建上下文引擎、provider/api 变化时重置 LLM、从 `prompt_template` 重建提示词构建器
- `set_llm(model)`：注入预构建 Model
- `invoke(inputs, session)` / `stream(inputs, session, stream_modes)`
- 输入格式：`{"query", "conversation_id"}`；输出：`{"output", "result_type": "answer|error"}`

### 设计模式
- **Card + Config**：`AgentCard`（身份）+ `ReActAgentConfig`（运行时）
- **ReAct 循环**配合 `ToolInterruptHandler` 实现 HITL
- **懒单例 LLM**：`set_llm`/配置变化时重置
- **KV-Cache 亲和钩子**集成到模型调用路径

> 注：`openjiuwen.core.single_agent.legacy` 仅为兼容性存在，不应在其上构建新功能。

---

## 3.11 `application/` — 应用级智能体

打包基于 `ControllerAgent` 的即用智能体：`WorkflowAgent`（工作流驱动）与 `LLMAgent`（ReAct 风格）。

### 关键类

| 类 | 文件 | 职责 |
|----|------|------|
| `WorkflowAgent` | [application/workflow_agent/workflow_agent.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/application/workflow_agent/workflow_agent.py) | 扩展 `ControllerAgent`；要求 `ControllerType.WorkflowController`；委托 `invoke`/`stream` 给父类 |
| `WorkflowController` | [application/workflow_agent/workflow_controller.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/application/workflow_agent/workflow_controller.py) | 工作流控制器 |
| `LLMAgent` | [application/llm_agent/llm_agent.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/application/llm_agent/llm_agent.py) | 扩展 `ControllerAgent` 配 `LLMController` |
| `LLMController` | [application/llm_agent/llm_controller.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/application/llm_agent/llm_controller.py) | LLM 控制器 |

### 关键函数
- `create_llm_agent_config(...)` / `create_llm_agent(agent_config, workflows, tools)`：向后兼容工厂

### 设计模式
- **控制器注入**：智能体将控制器实例传给 `ControllerAgent.__init__`，后者自动配置
- **工厂函数**用于向后兼容

---

## 3.12 `multi_agent/` — 团队基础

提供多智能体团队：抽象 `BaseTeam` 配 `TeamRuntime`，通过 `AgentProvider` 懒注册智能体，经 `MessageBus` 路由消息，并强制团队配置（最大智能体数、消息超时）。

### 关键类

| 类 | 文件 | 职责 |
|----|------|------|
| `BaseTeam` (ABC) | [multi_agent/team.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/multi_agent/team.py) | 持有 `TeamCard`、`TeamConfig`、`team_id`、`runtime: TeamRuntime` |
| `TeamCard` | [multi_agent/schema/team_card.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/multi_agent/schema/team_card.py) | `BaseCard` + `agent_cards: List[AgentCard]`（仅元数据） |
| `TeamConfig` | [multi_agent/](file:///D:/jiuwen/main/agent-core/openjiuwen/core/multi_agent) | `max_agents`、`max_concurrent_messages`、`message_timeout` |
| `TeamRuntime` | [multi_agent/runtime/](file:///D:/jiuwen/main/agent-core/openjiuwen/core/multi_agent/runtime) | 管理注册的智能体卡/provider 与消息总线 |

### 关键方法

`BaseTeam`：
- `configure(config)`
- `add_agent(card, provider)`：强制 `config.max_agents`，按 id 去重，追加到 `card.agent_cards`
- `remove_agent(agent_id)`

### 设计模式
- **Card（身份）+ Config（运行时）+ Runtime（行为）**三位一体
- **Provider 工厂**用于懒实例化智能体
- **消息总线**用于智能体间通信，带界队列

---

## 3.13 `memory/`、`retrieval/`、`store/`、`operator/`

### `memory/` — 记忆子系统
- **`LongTermMemory`** — [memory/long_term_memory.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/memory/long_term_memory.py)：持久化记忆存储；`LLMAgent` 通过 `_memory_log_task_exception` 调度后台 `add` 任务，经 `_extract_answer_output` 提取答案文本（查找 `result_type == 'answer'`）
- 设计模式：**后台 fire-and-forget + 异常日志**

### `retrieval/` — 检索子系统
- **`BaseCallback`** / **`TqdmCallback`** — [retrieval/common/callbacks.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/retrieval/common/callbacks.py)：索引进度追踪器；`__call__(start_idx, end_idx, batch)` 线程安全计数
- 外部依赖：`tqdm`、`threading`

### `store/` — 存储子系统
- **`Store`** (ABC)：被图引擎（`Pregel.store`）与会话/VCS 层用于持久化图状态与检查点数据；`Checkpointer.graph_store()` 返回 `Store`
- 设计模式：**抽象存储接口**可在内存与持久化后端间切换，配合**命名空间键**隔离

### `operator/` — 算子基础
- **Operator base** — [operator/base.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/operator/base.py)：声明被可组合工具消费的算子契约
- 设计模式：**策略/接口**用于可插拔算子

---

## 3.14 `sys_operation/` — 文件系统、Shell、代码执行

暴露沙箱或本地系统操作（文件系统、shell、代码执行及可扩展自定义操作），既作为直接方法也作为 `Tool` 风格调用。支持 `LOCAL` 与 `SANDBOX`（网关）两种模式。

### 关键类

| 类 | 文件 | 职责 |
|----|------|------|
| `SysOperationCard` | [sys_operation/sys_operation.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/sys_operation/sys_operation.py) | Pydantic `BaseCard`；`mode: OperationMode`(LOCAL/SANDBOX)、`work_config`、`gateway_config` |
| `SysOperation` | [sys_operation/sys_operation.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/sys_operation/sys_operation.py) | 运行时门面；按模式构建 `LocalWorkConfig` 或 `SandboxRunConfig` |
| `ToolIdProxy` | [sys_operation/sys_operation.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/sys_operation/sys_operation.py) | `__getattr__` 产出工具 id 字符串 |
| `BaseFsOperation` / `BaseShellOperation` / `BaseCodeOperation` | [sys_operation/](file:///D:/jiuwen/main/agent-core/openjiuwen/core/sys_operation) | 操作接口 |

### 关键方法

`SysOperationCard`：
- 属性 `fs` / `shell` / `code`：返回 `ToolIdProxy` 实例
- `__getattr__`：支持动态操作类型（如 `card.browser.navigate`）
- 静态 `generate_tool_id(card_id, op_type, method_name)`：`"{card_id}.{op_type}.{method_name}"`

`SysOperation`：
- `fs()` / `shell()` / `code()` / `__getattr__`：经 `_get_operation` 返回操作实例
- `isolation_key_template`

### 设计模式
- **Card 分离**：`SysOperationCard`（配置）与 `SysOperation`（运行时）
- **动态属性代理**：`ToolIdProxy` 与 `SysOperation.__getattr__` 实现可扩展操作类型
- **按模式策略**：LOCAL vs SANDBOX 运行配置在构造时选择
- **工具 id 约定**：确定性点分 id，操作可经 `Runner.resource_mgr.get_tool(tool_id)` 注册与检索

> `core/sys_operation` 与沙箱代码是安全敏感区，文件路径、shell 执行、审批、中断均有校验。

---

## 3.15 `security/` — 安全护栏

提供监控特定回调框架事件的护栏，经可插拔 `GuardrailBackend` 运行检测，为安全检查（如提示词注入）发射 `GuardrailContext`。

### 关键类

| 类 | 文件 | 职责 |
|----|------|------|
| `BaseGuardrail` (ABC) | [security/guardrail/guardrail.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/security/guardrail/guardrail.py) | 类属性 `DEFAULT_EVENTS`/`DEFAULT_PRIORITY`/`NAMESPACE="guardrail"`；`register(callback_framework)` |
| `PromptInjectionGuardrail` | [security/guardrail/](file:///D:/jiuwen/main/agent-core/openjiuwen/core/security/guardrail) | 提示词注入检测（具体子类） |
| `GuardrailBackend` (ABC) / `GuardrailContext` | [security/guardrail/](file:///D:/jiuwen/main/agent-core/openjiuwen/core/security/guardrail) | 后端/上下文类型 |

### 关键方法

`BaseGuardrail`：
- `with_events(...)` / `set_backend`/`get_backend`
- `get_registered_events` / `is_event_registered` / `listen_events`
- `register(callback_framework)`：注册为全局框架回调
- 子类覆盖 `extract_context()` 从事件数据构建 `GuardrailContext`

### 设计模式
- **事件驱动监控**：护栏作为回调注册到全局框架
- **策略后端**：检测逻辑委托给可替换 `GuardrailBackend`
- **链式配置**：`with_events(...).set_backend(...)`

---

## 3.16 core 模块设计模式总结

| 模式 | 体现 |
|------|------|
| **Card/Config 分离** | `WorkflowCard`/`AgentCard`/`TeamCard`/`ToolCard`/`SysOperationCard` 均继承 `BaseCard` |
| **Runner 单例** | `Runner` 类属性代理到 `GLOBAL_RUNNER`，`resource_mgr`/`callback_framework` 为类属性 |
| **Pregel/BSP 超步** | `Pregel.run` → `PregelLoop.run_step`，`Vertex` 并发 + 步末同步 |
| **四能力流式** | INVOKE/STREAM/COLLECT/TRANSFORM 组合执行路径 |
| **回调框架解耦** | `Runner.callback_framework` 全局事件总线，图/工具/护栏共用 |
| **会话谱系** | `bind_parent_session_id` 不可变单归属；KV-Cache 身份派生 |
| **检查点模板方法** | `Checkpointer` ABC 钩子 + 命名空间键隔离 |
| **动态属性代理** | `ToolIdProxy`/`SysOperation.__getattr__` 可扩展操作类型 |
| **事件驱动护栏** | `BaseGuardrail.register(callback_framework)` 监听事件 |
