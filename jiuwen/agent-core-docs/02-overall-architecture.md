# 02 - 整体架构

## 2.1 分层架构

openJiuwen Core 采用清晰的分层架构，自底向上分为四层：

```
┌─────────────────────────────────────────────────────────────┐
│                   用户层 / 应用层                              │
│   examples/  •  docs/  •  用户业务代码                          │
├─────────────────────────────────────────────────────────────┤
│                 harness 层（编码智能体框架）                     │
│   DeepAgent  •  TaskLoop  •  Rails  •  Tools  •  Security       │
│   Prompts  •  Workspace  •  Goal  •  LSP  •  CLI                │
├─────────────────────────────────────────────────────────────┤
│                  core 层（公共 SDK / 运行时引擎）                │
│   single_agent  •  workflow  •  graph(pregel)  •  runner         │
│   session  •  context_engine  •  foundation(llm/tool)           │
│   controller  •  sys_operation  •  security  •  memory           │
│   multi_agent  •  retrieval  •  store  •  common                 │
├─────────────────────────────────────────────────────────────┤
│                  扩展与工具层                                   │
│   extensions(a2a)  •  agent_evolving  •  dev_tools              │
│   rsi  •  symphony  •  agent_teams(基于 core/harness)           │
└─────────────────────────────────────────────────────────────┘
```

### 各层职责

| 层 | 包路径 | 职责 |
|----|--------|------|
| **core 层** | `openjiuwen/core/` | 公共 SDK 与运行时引擎：图执行、工作流、会话、Runner、智能体基础、LLM/工具抽象、上下文引擎、系统操作、安全护栏 |
| **harness 层** | `openjiuwen/harness/` | 编码智能体框架：DeepAgent（封装 ReActAgent）、外层任务循环、Rails 回调、工具集、安全权限、提示词构建、工作区、目标管理、LSP、CLI |
| **扩展层** | `openjiuwen/extensions/`、`agent_evolving/`、`dev_tools/`、`rsi/`、`symphony/` | 可选集成、自演进、调优、评估优化、能力编排 |
| **团队层** | `openjiuwen/agent_teams/` | 多智能体团队框架，基于 core/harness 构建 |

## 2.2 核心设计模式

### 2.2.1 Card / Config 分离（贯穿全项目）

openJiuwen Core 最核心的设计原则：**Card 是静态可序列化的元数据，Config 是持有资源与状态的运行时对象**。这一分离使 Card 可跨进程边界（如 A2A 协议）传输，而 Config 保持进程本地单例。

| Card（元数据） | Config（运行时） | 行为类 |
|----------------|-------------------|--------|
| `WorkflowCard` | `WorkflowConfig` | `Workflow` |
| `AgentCard` | `ReActAgentConfig` / `DeepAgentConfig` | `ReActAgent` / `DeepAgent` |
| `TeamCard` | `TeamConfig` | `BaseTeam` |
| `ToolCard` | — | `Tool` |
| `SysOperationCard` | — | `SysOperation` |

所有 Card 均继承自 [common/schema/card.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/common/schema/card.py) 的 `BaseCard`（含 `id`、`name`、`description`）。

**反模式**（应避免）：
- 在 Card 中放置 `session_id`、`runner` 等运行时数据
- 在 Config 中定义静态描述字段
- 在 Card 的 `to_dict()` 中注入动态计算

### 2.2.2 Runner 单例与资源管理器

`Runner` 是进程级单例，通过类属性代理转发到全局实例 `GLOBAL_RUNNER`，提供：

- `Runner.resource_mgr`：`ResourceMgr` 资源注册表（工作流、智能体、团队、工具、模型、提示词、sys_operation）
- `Runner.callback_framework`：`AsyncCallbackFramework` 全局事件总线
- `Runner.run_workflow` / `run_agent` / `run_workflow_streaming` / `run_agent_streaming`：高层执行入口

> 参考：[runner/runner.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/runner/runner.py)

`Runner.resource_mgr` 是共享的进程级状态，使用稳定 ID 并保持测试隔离。

### 2.2.3 异步并行图执行（Pregel/BSP）

工作流通过 **Pregel 风格的超步循环**执行：

- `Pregel.run()` 创建 `PregelLoop`，调用 `init()`，然后循环调用 `run_step()` 直到返回假值
- `Vertex` 实例在同一个超步内并发执行，超步结束时同步
- `Vertex.__call__` 对批量能力调用 `atomic_invoke`/`call`，对流式能力调用 `stream_call`
- 通过 `asyncio.Event`/`asyncio.Future` 与 `asyncio.gather` 实现并发同步

> 参考：[graph/pregel/engine.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/graph/pregel/engine.py)、[graph/vertex.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/graph/vertex.py)

### 2.2.4 四能力流式架构

组件（Component）具备四种能力，可组合为不同的执行路径：

| 能力 | 输入 → 输出 | 说明 |
|------|-------------|------|
| `INVOKE` | 批量 → 批量 | 一次性调用 |
| `STREAM` | 批量 → 流 | 流式输出 |
| `COLLECT` | 流 → 批量 | 收集流为批量 |
| `TRANSFORM` | 流 → 流 | 流转换 |

`End` 组件的 `TemplateProcessor` 支持静态文本与变量段交织，`set_mix()` 支持双数据源并发输入。

### 2.2.5 Rails 回调架构与选择性事件路由

`AgentRail` 是横切关注点的载体（安全、技能、子智能体、LSP、MCP、任务完成、记忆、演进等）。DeepAgent 扩展了核心 `AgentRail`，增加 `before_task_iteration` / `after_task_iteration` 钩子。

**选择性事件路由**：DeepAgent 将回调事件分为三组：

| 事件分组 | 路由目标 | 典型事件 |
|----------|----------|----------|
| `_BRIDGE_EVENTS` | 内部 ReActAgent | 模型调用前后、工具调用前后、ReAct 迭代后 |
| `_OUTER_ONLY_EVENTS` | 外层 DeepAgent | `BEFORE_INVOKE`、`AFTER_INVOKE` |
| `_DEEP_EVENTS` | 外层 DeepAgent | `BEFORE_TASK_ITERATION`、`AFTER_TASK_ITERATION` |

每个 Rail 只需覆盖它关心的事件，`get_callbacks()` 反射返回已覆盖的方法。

> 参考：[harness/rails/base.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/rails/base.py)

### 2.2.6 热重配（Hot-Reconfigure）

`DeepAgent._hot_reconfigure` 可在不停机的情况下热更新：

- Rails（将旧 Rail 移入 `_stale_rails`，懒注销）
- 模型（通过 `react_agent.configure()` 重置 LLM）
- 工具（按 id 同步 `AbilityManager`）
- 系统提示词（重建 `SystemPromptBuilder`）

### 2.2.7 插件/AgentTemplate 热加载

两阶段热加载：

1. **解析阶段**（`resources/extension_loader` + `extension_resolver`）：纯物化为 `ExtensionParts`，不修改 DeepAgent
2. **绑定阶段**（`extension_binder.apply_extension_hot`）：事务性绑定，失败回滚；通过 `LoadRecord` 记账，`unload_extension` 可逆

### 2.2.8 任务循环控制器架构

外层任务循环由四元组构成：

| 组件 | 职责 |
|------|------|
| `TaskLoopController` | 轮次管理、follow-up 队列操作、循环退出逻辑 |
| `TaskLoopEventHandler` | 创建核心 Task、每轮 Future + 单调 `round_id` 关联 |
| `TaskLoopEventExecutor` | 委托内部 ReActAgent 执行，产出 `ControllerOutputChunk` |
| `LoopCoordinator` | 迭代计数、token 用量、墙钟时间、终止条件评估器链（OR 语义） |

`LoopQueues` 提供 **steer/follow-up 双队列**：steer 在每轮内部调用前排空，follow_up 在每轮迭代后排空。

> 参考：[harness/task_loop/](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/task_loop/)

### 2.2.9 会话谱系与 KV-Cache 身份

- `Session.bind_parent_session_id` 强制不可变单归属谱系
- `set_team_cache_scope` + `get_cache_identity` 为团队成员派生面向 provider 的 `KVCacheIdentity`
- `KVCacheModelCallHook` 集成到智能体的模型调用路径

### 2.2.10 检查点生命周期

`Checkpointer` 定义了每个执行边界的钩子：

```
pre_workflow_execute / post_workflow_execute
pre_agent_execute / post_agent_execute
pre_agent_team_execute / post_agent_team_execute
interrupt_agent_execute
session_exists / release / graph_store
```

`get_thread_id = session_id:workflow_id`，命名空间键构造器 `build_key_with_namespace` 提供 `agent`/`agent-team`/`workflow`/`workflow-graph` 状态隔离。

> 参考：[session/checkpointer/base.py](file:///D:/jiuwen/main/agent-core/openjiuwen/core/session/checkpointer/base.py)

## 2.3 运行时数据流

### 2.3.1 单智能体调用流（ReActAgent）

```
用户输入 {"query": "..."}
        │
        ▼
Runner.run_agent(agent, inputs)
        │  创建 Session → pre_run
        ▼
ReActAgent.invoke(inputs, session)
        │  构建上下文 → ContextEngine.create_context
        ▼
   ┌─── ReAct 循环 ────────────────────────┐
   │  1. 思考：LLM 调用（带工具描述）          │
   │  2. 行动：若 LLM 输出工具调用 → 执行工具   │
   │  3. 观察：将工具结果加入上下文            │
   │  重复直到 LLM 输出最终答案或达最大迭代     │
   └──────────────────────────────────────┘
        │
        ▼
返回 {"output": "...", "result_type": "answer"}
        │  post_run
        ▼
Runner 返回结果
```

### 2.3.2 工作流执行流

```
Workflow 注册 → Runner.resource_mgr.add_workflow
        │
Runner.run_workflow(workflow_id, inputs)
        │  _prepare_workflow → workflow_instance
        ▼
Workflow.invoke(inputs, session)
        │  PregelGraph 编译为 Pregel 引擎
        ▼
Pregel.run(config)
        │  超步循环：
        │   ├─ 并发执行 Vertex（asyncio.gather）
        │   ├─ Channel 状态更新/消费
        │   └─ 同步屏障
        │  直到没有更多任务
        ▼
End 组件格式化最终输出
```

### 2.3.3 DeepAgent 任务循环流

```
invoke(query)
        │  _ensure_initialized（懒初始化 Rails/工作区/MCP）
        ▼
是否启用任务循环？
   ├─ 否 → _run_single_round_invoke（委托 ReActAgent 单轮）
   └─ 是 → _run_task_loop
              │  _setup_task_loop（Controller + Coordinator）
              │  controller.bind_session
              ▼
         ┌── 轮次循环 ──────────────────────────┐
         │  drain follow_up → current_query      │
         │  controller.submit_round              │
         │  TaskLoopEventHandler → Task           │
         │  TaskLoopEventExecutor → ReActAgent   │
         │  controller.wait_round_completion     │
         │  yield result                          │
         │  coordinator.increment_iteration       │
         │  检查终止条件/中断/abort                 │
         └────────────────────────────────────────┘
              │  controller.unbind_session + stop
```

## 2.4 关键概念速查

| 概念 | 说明 |
|------|------|
| **Card** | 静态可序列化元数据，可跨进程传输 |
| **Config** | 持有资源与状态的运行时对象，进程本地 |
| **Ability** | 能力枚举（INVOKE/STREAM/COLLECT/TRANSFORM） |
| **Rail** | 横切关注点回调（安全、技能、任务完成等） |
| **Vertex** | 图节点的运行时包装器，编排四能力 |
| **Channel** | 图状态容器（Topic/LastValue/Context） |
| **Session** | 会话上下文，携带配置、流、谱系、KV-Cache 身份 |
| **ContextEngine** | 上下文引擎，管理消息处理器链与 token 窗口 |
| **AbilityManager** | 能力管理器，注册工具/工作流/MCP |
| **ResourceMgr** | 资源管理器单例，进程级注册表 |
| **CallbackFramework** | 异步回调框架，全局事件总线 |
| **Worktree** | Git worktree 隔离工作区 |
| **HITL** | 人机交互（Human-in-the-Loop） |
| **HITT** | 人机交互团队模式（agent_teams） |

## 2.5 模块间协作关系

```
harness.DeepAgent
   │ 委托
   ▼
core.single_agent.ReActAgent ──── foundation.llm.Model
   │                                   │
   │ 使用                              │ 调用
   ▼                                   ▼
core.runner.Runner ──────────── core.workflow.Workflow
   │                                   │
   │ resource_mgr                      │ 编译
   ▼                                   ▼
core.runner.ResourceMgr        core.graph.pregel.Pregel
                                         │
                                         ▼
                                    core.graph.Vertex ── workflow.components.*
```

```
agent_teams.TeamAgent
   │ 基于
   ├─ core.runner.Runner（团队运行入口）
   ├─ core.single_agent（AgentCard）
   ├─ harness（NativeHarness 驱动 DeepAgent）
   └─ agent_teams.runtime.TeamRuntimePool（团队运行时管理）
```

## 2.6 公共 API 约定

根据 [AGENTS.md](file:///D:/jiuwen/main/agent-core/AGENTS.md) 与 [.claude/rules/architecture.md](file:///D:/jiuwen/main/agent-core/.claude/rules/architecture.md)：

- `__init__.py` 导出、文档化 API、`examples/`、README 片段视为**公共 API**
- 公共 API 变更应保持叠加式：保留名称与位置参数
- 新增可选参数优先使用仅关键字参数
- `openjiuwen.core.single_agent` 是当前单智能体 API；`openjiuwen.core.single_agent.legacy` 仅为兼容性存在
- 修改行为前，应检查目标模块的 `__init__.py` 导出面及附近的测试/示例
