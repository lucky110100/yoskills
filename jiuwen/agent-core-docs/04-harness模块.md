# 04 - harness 模块

`openjiuwen/harness/` 是 openJiuwen Core 的**高级智能体编排层**，构建于 `core.*` 基础之上，提供生产级智能体框架：委托式的 `DeepAgent`（热重配、外层任务循环、插件热加载）、Rails 回调系统、权限化工具/安全系统、目标管理、LSP 子系统、工作区+子智能体系统，以及完整的终端 CLI。

> 路径前缀：本节文件路径均相对于 `openjiuwen/harness/`

## 4.1 模块总览

| 子模块 | 职责 |
|--------|------|
| `deep_agent.py` | DeepAgent：封装 ReActAgent 的高级智能体 |
| `factory.py` | `create_deep_agent` 工厂与纯装配拆分 |
| `extension_binder.py` | 插件/AgentTemplate 热绑定/解绑 |
| `image_modality_probe.py` | LLM 图像输入能力探测 |
| `task_loop/` | 外层任务循环架构（控制器/协调器/执行器/事件/队列） |
| `prompts/` | 系统提示词构建器与分节系统 |
| `rails/` | AgentRail 回调架构（安全/技能/子智能体/LSP/MCP 等） |
| `tools/` | SessionToolkit 及全部 LLM 可调用工具 |
| `security/` | 工具权限引擎与文件守卫 |
| `schema/` | 配置、状态、规约数据类与枚举 |
| `workspace/` | 工作区与目录构建器 |
| `goal/` | 目标管理系统 |
| `lsp/` | 语言服务器协议子系统 |
| `manifest/` | Harness 元素目录与反射注册 |
| `resources/` | 插件/AgentTemplate 加载与解析 |
| `kv_cache/` | KV-Cache 亲和钩子 |
| `subagents/` | 预置子智能体工厂 |
| `cli/` | `openjiuwen` 命令行入口 |

---

## 4.2 顶层：`deep_agent.py`、`factory.py`、`extension_binder.py`

### 4.2.1 `deep_agent.py` — DeepAgent

**`DeepAgent(BaseAgent)`** — [deep_agent.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/deep_agent.py)

高级智能体，封装内部 `ReActAgent`，拥有 Rails、任务循环、交互监督者、目标管理器、扩展加载记录。

#### 关键方法

| 方法 | 职责 |
|------|------|
| `configure(config: DeepAgentConfig)` | 应用配置；路由到 `_initial_configure`（首次）或 `_hot_reconfigure`（后续） |
| `_hot_reconfigure(config)` | 热重配：重载 Rails（循环旧 Rail）、模型、工具、系统提示词 |
| `_create_react_agent()` | 构建内部 ReActAgent，共享提示词构建器、ability_manager、callback_manager |
| `register_rail(rail)` / `unregister_rail(rail)` | 选择性事件路由注册（见 §4.4） |
| `_register_rail_selective(rail)` | 按 `_BRIDGE_EVENTS`/`_OUTER_ONLY_EVENTS`/`_DEEP_EVENTS` 分组分派 |
| `load_plugin(path)` / `load_agent_template(path)` / `load_plugin_ability(...)` | 插件/AgentTemplate 热加载 |
| `unload_extension(record)` | 卸载已加载扩展 |
| `_run_task_loop` / `_run_task_loop_invoke` / `_run_task_loop_stream` | 外层任务循环驱动 |
| `invoke(inputs, session)` / `stream(inputs, session, stream_modes)` | 单轮或任务循环执行入口 |
| `follow_up(msg)` / `steer(msg)` / `abort()` | 后续消息、转向、中止 |
| `run_one_round(work)` | 执行一个交互轮次（交互监督者） |
| `create_subagent(subagent_type, subsession_id)` | 构建子 DeepAgent，继承 artifact 根与共享资源 |
| `start()` / `stop()` | 生命周期：懒初始化 + 工作区 + LSP + 图像探测，优雅拆解 |
| `save_state(session)` / `load_state(session)` / `switch_mode(session, mode)` | 每调用可变状态检查点 |

#### 关键常量/函数
- `_render_identity_prompt(prompt_builder, language)`：仅渲染身份分节，避免双发
- `_BRIDGE_EVENTS` / `_OUTER_ONLY_EVENTS` / `_DEEP_EVENTS`：回调事件三分组

#### 设计模式
- **委托**：DeepAgent 委托 ReAct 循环给内部 ReActAgent
- **热重配**：原地重载 Rails/模型/工具/提示词
- **选择性事件路由**：bridge/outer-only/deep 三分组分派
- **监督者循环**：单消费者交互循环
- **插件热加载**

### 4.2.2 `factory.py` — create_deep_agent

构造已配置 `DeepAgent` 的主入口，采用纯装配 + 物化的拆分。

#### 关键函数

| 函数 | 职责 |
|------|------|
| `create_deep_agent(model, *, card, tools, mcps, subagents, rails, ...)` | 主构造入口：`resolve_deep_agent_parts` + `apply_deep_agent_parts` |
| `resolve_deep_agent_parts(...) -> DeepAgentParts` | 纯装配：归一化工具、注入 general-purpose 子智能体、解析工作区/SysOperation、构建 DeepAgentConfig、计算自动添加的默认 Rail |
| `apply_deep_agent_parts(agent, parts)` | 物化到目标 DeepAgent：`configure()`、注册工具实例/卡、入队 Rail |

#### 默认 Rail（自动添加，未用户提供时）
`SecurityRail`、`LLMRetryRail`、`TaskPlanningRail`、`SkillUseRail`、`SubagentRail`、`ToolCallResilienceRail`

#### 数据类
- `DeepAgentParts`：解耦的构造输入（`config`、`rails`、`tool_cards`、`tool_instances`）

#### 设计模式
- **工厂函数 + 纯装配/物化拆分**
- **自动添加默认 Rail**：经 `_already_provided` 检查实现组合性而非强制重复

### 4.2.3 `extension_binder.py`

将解析后的 `ExtensionParts` 绑定/解绑到运行中的 DeepAgent，记录 `ResourceRef` 用于回滚。

#### 关键函数
- `apply_extension_hot(agent, parts) -> list[ResourceRef]`：绑定工具/MCP/Rails/提示词分节/技能/子智能体；任一失败则逆序解绑已绑定并重抛
- `unapply_extension_hot(agent, refs)`：逆序撤销绑定
- `_bind_tool` / `_bind_mcp` / `_bind_rail` / `_bind_prompt_section` / `_bind_skill` / `_bind_subagent`：分种类绑定器
- `_ensure_subagent_rail_ready(agent)`：幂等创建/刷新 `SubagentRail`

#### 设计模式
- **事务性绑定/回滚**：`apply_extension_hot` 全有或全无
- **ResourceRef 记账**：用于逆序解绑
- **幂等共享基础设施创建**

### 4.2.4 `image_modality_probe.py`

后台、进程缓存的 LLM 图像输入能力探测，让 `read_file` 知道是否附加图像字节为多模态内容。

#### 关键函数
- `schedule_image_support_probe(llm)`：启动非阻塞探测（按 `(api_base, model_name)` 缓存）
- `get_cached_image_support(llm)`：返回缓存判定或 `None`
- `is_image_modality_rejection(exc)`：分类异常为确定性图像拒绝

#### 设计模式
- **进程级记忆化**：按 `(api_base, model_name)` 键
- **后台任务 + done-callback 清理**
- 不确定结果**从不缓存**，避免永久致盲可用模型

---

## 4.3 `task_loop/` — 外层任务循环架构

轮次式外层任务循环，包装内部 ReActAgent。

### 关键类

| 类 | 文件 | 职责 |
|----|------|------|
| `TaskLoopController(Controller)` | [task_loop/task_loop_controller.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/task_loop/task_loop_controller.py) | 轮次管理、follow-up 队列、循环退出 |
| `LoopCoordinator` | [task_loop/loop_coordinator.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/task_loop/loop_coordinator.py) | 迭代计数、token、墙钟、终止条件评估器链（OR 语义） |
| `LoopQueues` | [task_loop/loop_queues.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/task_loop/loop_queues.py) | steer/follow-up 双队列缓冲 |
| `TaskLoopEventHandler(EventHandler)` | [task_loop/task_loop_event_handler.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/task_loop/task_loop_event_handler.py) | 路由核心 EventQueue 事件；每轮 Future + 单调 round_id 关联 |
| `TaskLoopEventExecutor(TaskExecutor)` | [task_loop/task_loop_event_executor.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/task_loop/task_loop_event_executor.py) | 委托内部 ReActAgent，注册为 `DEEP_TASK_TYPE = "deep_agent_task"` |
| `EventManager` | [task_loop/event_manager.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/task_loop/event_manager.py) | 单消费者调度域，user/goal 双队列（user 优先） |

### 关键方法

`TaskLoopController`：
- `submit_round(session, query, is_follow_up, run_kind, run_context, *, task_id, resume_continuation)`
- `wait_round_completion(timeout)`
- `drain_follow_up()`

`LoopCoordinator`：
- `should_continue() -> bool`：第一个返回 `should_stop()==True` 的评估器终止循环
- `reset()` / `increment_iteration()` / `add_token_usage(tokens)` / `set_last_result(result)` / `request_abort()`

`EventManager`：
- `push_user(work)` / `push_goal(work) -> bool` / `next_work()` / `mark_started(work)` / `mark_finished(work)`

### 设计模式
任务循环构成经典的 **Controller / EventHandler / TaskExecutor / Coordinator 四元组**：`TaskLoopController` 发布 `InputEvent`，`TaskLoopEventHandler` 创建核心 Task 并解析每轮 Future，`TaskLoopEventExecutor` 运行内部 ReActAgent，`LoopCoordinator` 决定何时停止。`LoopQueues` 增加 steer/follow-up 双队列；`EventManager` 是交互监督者的单消费者调度域。

---

## 4.4 `rails/` — AgentRail 回调架构

Rails 扩展核心 `AgentRail`，新增两个任务循环钩子（`before_task_iteration`/`after_task_iteration`），提供所有横切关注点。

### 关键类

| 类 | 文件 | 职责 |
|----|------|------|
| `DeepAgentRail(AgentRail)` | [rails/base.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/rails/base.py) | 基类；新增任务迭代钩子；携带 `sys_operation`/`workspace` 句柄 |
| `SecurityRail` / `PermissionInterruptRail` / `SafetyPromptRail` | [rails/](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/rails) | 安全/权限 |
| `SkillUseRail` / `SkillCreateRail` | [rails/](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/rails) | 技能使用/创建 |
| `SubagentRail` / `SessionRail` / `VerificationRail` | [rails/](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/rails) | 子智能体/会话/验证 |
| `SysOperationRail` | [rails/](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/rails) | 系统操作 |
| `TaskCompletionRail` | [rails/task_completion_rail.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/rails/task_completion_rail.py) | 循环策略参数、目标尝试生命周期驱动 |
| `TaskPlanningRail` | [rails/](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/rails) | 任务规划 |
| `LLMRetryRail` | [rails/](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/rails) | LLM 重试 |
| `LspRail` | [rails/lsp_rail.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/rails/lsp_rail.py) | LSP 初始化与工具注册 |
| `McpRail` | [rails/mcp_rail.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/rails/mcp_rail.py) | MCP 资源发现/读取工具 |
| `ProgressiveToolRail` | [rails/progressive_tool_rail.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/rails/progressive_tool_rail.py) | 渐进式工具披露 |
| `AgentModeRail` / `HeartbeatRail` / `AskUserRail` / `ConfirmInterruptRail` | [rails/](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/rails) | 模式/心跳/人机交互 |

### 关键方法

`DeepAgentRail`：
- `before_task_iteration(ctx)` / `after_task_iteration(ctx)`：经 `DEEP_EVENT_METHOD_MAP` 合并入 `get_callbacks()`
- `get_callbacks()`：反射返回仅已覆盖的方法
- `set_sys_operation(sys_op)` / `set_workspace(workspace)`

`TaskCompletionRail`：携带循环策略参数（`task_instruction` 模板、`completion_promise` 标签、`max_rounds`、`timeout_seconds`、自定义 `evaluators`）；有 `goal_manager` 时驱动目标尝试生命周期。

### 设计模式
**回调 Rail 系统**：每个 Rail 只覆盖它关心的钩子；`get_callbacks()` 反射仅返回已覆盖方法；`DeepAgent._register_rail_selective` 按 bridge/outer-only/deep 分组路由到正确的 callback_manager。这是**选择性事件路由**模式。

---

## 4.5 `prompts/` — 系统提示词构建器与分节

### 关键类

| 类 | 文件 | 职责 |
|----|------|------|
| `SystemPromptBuilder(BaseSystemPromptBuilder)` | [prompts/builder.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/prompts/builder.py) | 扩展核心构建器，加 `PromptMode` 过滤（NONE/MINIMAL/FULL） |
| `PromptReport` | [prompts/report.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/prompts/report.py) | 诊断快照（总字符、估算 token、分节数、每节信息） |
| `PromptAttachmentManager` | [prompts/prompt_attachment_manager.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/prompts/prompt_attachment_manager.py) | 提示词附件管理 |

### 关键方法/常量
- `build() -> str`：模式过滤组装
- `build_report() -> PromptReport`：诊断快照
- `SectionName`：集中式分节名常量（IDENTITY、SAFETY、SKILLS、TOOLS、TODO、RUNTIME、MEMORY 等）
- `sanitize_path(path)` / `sanitize_user_content(content, max_len=2000)`：去除注入倾向字符
- `resolve_language(config_language)` / `resolve_mode(config_mode)`：环境变量回退

### 设计模式
**分节名常量 + 模式过滤 + 每节构建器模块** = 可组合、可自省的提示词系统。Rails 通过共享构建器的 `add_section` 注入自己的分节。

---

## 4.6 `tools/` — SessionToolkit 与全部工具

所有 LLM 可调用工具与 `SessionToolkit` 注册表。

### 关键类

| 类 | 文件 | 职责 |
|----|------|------|
| `ToolOutput(BaseModel)` | [tools/base_tool.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/base_tool.py) | 统一工具结果（`success`/`data`/`error`） |
| `CodeTool` | [tools/code.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/code.py) | 经 SysOperation 执行代码 |
| `ReadFileTool`/`WriteFileTool`/`EditFileTool`/`GlobTool`/`GrepTool`/`ListDirTool` | [tools/filesystem.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/filesystem.py) | 文件系统工具 |
| `TodoTool`/`TodoCreateTool`/`TodoListTool`/`TodoModifyTool`/`TodoGetTool` | [tools/todo.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/todo.py) | 待办工具 |
| `GoalReportSink`/`SubmitGoalReportTool` | [tools/goal.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/goal.py) | 目标报告提交 |
| `MemorySearchTool`/`MemoryGetTool` | [tools/memory.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/memory.py) | 记忆搜索/获取 |
| `ListMcpResourcesTool`/`ReadMcpResourceTool` | [tools/mcp_tools.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/mcp_tools.py) | MCP 资源列表/读取 |
| `WebFreeSearchTool`/`WebPaidSearchTool`/`WebFetchWebpageTool` | [tools/web/](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/web) | 全 aiohttp 网络工具 |
| `AskUserTool` | [tools/ask_user.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/ask_user.py) | 人机交互澄清 |
| `BashTool`/`PowerShellTool` | [tools/shell/](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/shell) | Shell 工具 |
| `SkillTool`/`ListSkillTool` | [tools/skills/](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/skills) | 技能工具 |
| `SearchToolsTool`/`LoadToolsTool` | [tools/tool_discovery/](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/tool_discovery) | 工具发现（供 ProgressiveToolRail） |
| `ImageOCRTool`/`VisualQuestionAnsweringTool`/`AudioTranscriptionTool` 等 | [tools/multimodal/](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/multimodal) | 多模态工具 |
| `EnterWorktreeTool`/`ExitWorktreeTool`/`WorktreeManager` | [tools/worktree/](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/worktree) | worktree 工具 |
| `LspTool` | [tools/lsp_tool/](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/lsp_tool) | LSP 工具 |
| `SessionToolkit` | [tools/subagent/session_tools.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/subagent/session_tools.py) | 会话任务注册表（异步子智能体） |
| `SessionsSpawnTool`/`SessionsListTool`/`SessionsCancelTool`/`TaskTool` | [tools/subagent/](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/subagent) | 子智能体生成工具 |
| 浏览器运行时 | [tools/browser_move/](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/browser_move) | Playwright 浏览器自动化 |
| 移动 GUI 智能体 | [tools/mobile_gui/](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/mobile_gui) | 移动 GUI 工具 |
| `EnterPlanModeTool`/`ExitPlanModeTool`/`SwitchModeTool` | [tools/agent_mode_tools.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/agent_mode_tools.py) | 模式切换工具 |

### 设计模式
- **统一 Tool 子类产出 ToolOutput**
- **工具卡经提示词注册表构建**（`build_tool_card`），保持 schema/描述一致
- **SessionToolkit 作为异步子智能体任务注册表**

---

## 4.7 `security/` — 工具权限系统

工具级 allow/ask/deny 权限引擎、文件守卫路径保护、宿主注入确认钩子、通配模式匹配、YAML 持久化。

### 关键类

| 类 | 文件 | 职责 |
|----|------|------|
| `PermissionEngine` | [security/core.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/security/core.py) | 加载/热重载权限配置，评估工具调用权限 |
| `ExternalDirectoryChecker` | [security/checker.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/security/checker.py) | 已弃用薄包装，委托 `FileGuardChecker` |
| `ToolPermissionHost` | [security/host.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/security/host.py) | 宿主注入回调（快照/持久化/确认/场景钩子） |
| `PermissionLevel` | [security/models.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/security/models.py) | 枚举 ALLOW/ASK/DENY |
| `PermissionResult` | [security/models.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/security/models.py) | 结果（permission/matched_rule/reason/external_paths） |

### 关键方法

`PermissionEngine`：
- `evaluate_tiered_policy(...)`：工具权限（allow/ask/deny）→ `FileGuardChecker.evaluate(...)`（路径保护）→ `strictest(A, B)`
- `update_config(config)` / `update_trusted_dirs(dirs)` / `update_llm(llm, model_name)`：热更新

### 关键函数
- `build_permission_interrupt_rail(permissions, llm, model_name, ...)` — [security/factory.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/security/factory.py)：返回 `PermissionInterruptRail` 或 `None`
- `write_permissions_section_to_agent_config_yaml(...)` — [security/patterns.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/security/patterns.py)：持久化 allow 规则到 YAML

### 设计模式
- **分层策略 + 文件守卫管线**，返回最严格决策
- **宿主注入**确认/持久化钩子，引擎保持 UI 无关
- **通配模式匹配** + shell 算子升级

---

## 4.8 `schema/` — 配置、状态与规约

所有 dataclass、枚举与 pydantic 模型。

### 关键类

| 类 | 文件 | 职责 |
|----|------|------|
| `DeepAgentConfig` | [schema/config.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/schema/config.py) | 中央运行时配置（model/card/tools/mcps/workspace/rails/skills/permissions 等） |
| `SubAgentConfig` | [schema/config.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/schema/config.py) | 子智能体规约 |
| `VisionModelConfig` / `AudioModelConfig` | [schema/config.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/schema/config.py) | 多模态模型配置 |
| `DeepAgentState` | [schema/state.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/schema/state.py) | 每调用可变状态（iteration/task_plan/stop_condition_state/pending_follow_ups/plan_mode） |
| `PlanModeState` | [schema/state.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/schema/state.py) | 计划模式状态 |
| `AgentMode` | [schema/agent_mode.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/schema/agent_mode.py) | 枚举 PLAN/NORMAL |
| `DeepLoopEvent` | [schema/loop_event.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/schema/loop_event.py) | 优先级队列条目 |
| `TodoItem` / `TaskPlan` / `TodoStatus` | [schema/task.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/schema/task.py) | 待办/任务计划 |
| `InteractionPhase` / `InputDispatchMode` / `SendInputRequest` / `RoundWorkItem` / `OutputLeaseManager` | [schema/interaction.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/schema/interaction.py) | 交互域对象 |
| `BuildContext` | [schema/build_context.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/schema/build_context.py) | Spec→Runtime 边界载体（非 pydantic） |
| `PluginSpec` / `AgentTemplateSpec` / `McpServerSpec` / `SkillSpec` | [schema/extension_spec.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/schema/extension_spec.py) | 插件/模板严格规约 |
| `StopConditionEvaluator` (ABC) | [schema/stop_condition.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/schema/stop_condition.py) | 终止条件策略接口 |

### 提供者注册表
- `register_rail_provider` / `register_tool_provider` / `register_subagent_provider` — [schema/deep_agent_spec.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/schema/deep_agent_spec.py)：manifest catalog 经此注册工厂

### 设计模式
- **dataclass 配置 + pydantic 任务模型 + frozen dataclass 交互对象**
- `BuildContext` 刻意非 pydantic（Spec→Runtime 边界对象）
- **策略模式停止评估器**，支持状态导出/恢复

---

## 4.9 `workspace/`、`goal/`、`lsp/`、`manifest/`、`resources/`

### `workspace/` — 工作区与目录构建器
- **`Workspace`** — [workspace/workspace.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/workspace/workspace.py)：`root_path` + `directories: List[DirectoryNode]` + `language`；自动补充必需顶层目录；`.team/`、`.worktree/` 符号链接管理
- **`DirectoryBuilder`** — [workspace/directory_builder.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/workspace/directory_builder.py)：经 SysOperation 物化目录树；`_is_safe_path` 拒绝绝对/盘符/UNC/`..` 路径
- 设计模式：**安全路径校验** + 符号链接（Windows junction/copytree 回退）

### `goal/` — 目标管理系统
- **`GoalManager`** — [goal/manager.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/goal/manager.py)：会话级 Goal 能力；所有写共享交互控制锁
- **`GoalRecord`** / `GoalStatus` / `GoalStopStrategy` / `GoalAssessment` — [goal/schema.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/goal/schema.py)：持久化目标域模型
- **`SessionGoalStore`** — [goal/store.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/goal/store.py)：经 Session 状态持久化
- **`GoalEvaluator`** — [goal/evaluation.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/goal/evaluation.py)：按策略评估（AGENT_REPORT/TRANSCRIPT/HYBRID）
- 设计模式：**基于协议的持久化**（GoalStore）解耦 Session；**策略模式评估器**成本感知混合评估

### `lsp/` — LSP 子系统
- **`LSPServerManager`**（单例）— [lsp/core/manager.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/core/manager.py)：全局单例，懒加载（首次请求才启动服务器）
- **`LSPServerInstance`** — [lsp/core/instance.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/core/instance.py)：管理一个服务器进程
- **`LspDiagnosticRegistry`** — [lsp/core/diagnostic_registry.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/core/diagnostic_registry.py)：诊断注册表
- 公共 API：`initialize_lsp(options)` / `shutdown_lsp()` / `get_lsp_tool()` / `get_lsp_status()` / `get_pending_lsp_diagnostics(...)`
- 设计模式：**单例 + 懒锁创建**（避免绑定创建时事件循环）；诊断队列去重/封顶/排序

### `manifest/` — Harness 元素目录
- **`harness_element(kind, name, description, input_model, builder, interface_methods)`** — [manifest/catalog.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/manifest/catalog.py)：装饰器/调用器，捕获 `HarnessElementDescriptor`
- **`HarnessElementDescriptor`** — [manifest/models.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/manifest/models.py)：pydantic，可序列化、可 JSON 往返
- **`ConstructionInput`** + `InputSource` — [manifest/inputs.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/manifest/inputs.py)：源标签 pydantic 字段（PARAMS/CONTEXT）
- **`register_from_catalog()`** — [manifest/registration.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/manifest/registration.py)：遍历 catalog 调用对应 `register_*_provider`
- 设计模式：**LLM 工具式描述符** — 可序列化、可反射、可 JSON 往返；元数据捕获与注册分离，永不漂移

### `resources/` — 插件/AgentTemplate 加载
- `load_plugin_package(manifest_path)` / `load_agent_template_package(manifest_path)` — [resources/extension_loader.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/resources/extension_loader.py)：接受 `manifest.json` 或遗留 `harness_config.yaml` 等
- `resolve_plugin_parts(spec, ctx)` / `resolve_agent_template_parts(spec, ctx)` — [resources/extension_resolver.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/resources/extension_resolver.py)：物化为 `ExtensionParts`
- `ResourceKind` 枚举、`ResourceRef`、`LoadRecord`、`ResolvedSkill`/`ResolvedPromptSection`
- 设计模式：**两阶段热加载** — resolve（纯物化）+ bind（经 extension_binder 事务绑定）；遗留 YAML 规范化

---

## 4.10 `kv_cache/`、`subagents/`

### `kv_cache/` — KV-Cache 亲和钩子
- `affinity_enabled(deep_agent)` / `is_sticky_subagent_type(subagent_type)` / `resolve_sub_session_id(...)` / `prefetch_sticky_subagent(...)` / `finish_subagent(...)` — [kv_cache/kv_cache_hooks.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/kv_cache/kv_cache_hooks.py)
- sticky 类型：`browser_agent`、`verification_agent`

### `subagents/` — 预置子智能体工厂
工厂函数 `create_*_agent` / `build_*_agent_config`：
- `code_agent` — [subagents/code_agent.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/subagents/code_agent.py)：高级软件工程师子智能体（默认 CN/EN 提示词、CodingMemoryRail、SysOperationRail、AskUserRail 等）
- `research_agent` / `browser_agent` / `verification_agent` / `mobile_gui_agent` / `plan_agent` / `explore_agent`
- 每个工厂用 subagent 专用的 rails/tools/prompts 组合 `create_deep_agent`

---

## 4.11 `cli/` — `openjiuwen` 命令

基于 Click 的终端 CLI，提供交互式 REPL（`openjiuwen` / `openjiuwen chat`）与非交互式运行器（`openjiuwen run PROMPT`），外加 `auto-harness` 子命令组。

### 关键类与函数

| 类/函数 | 文件 | 职责 |
|---------|------|------|
| `cli` (Click group) | [cli/cli.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/cli/cli.py) | 默认路由到 chat（TTY）或 run（管道） |
| `chat` 命令 | [cli/cli.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/cli/cli.py) | 交互 REPL；缺 API key 时 `_interactive_setup()` |
| `run` 命令 | [cli/cli.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/cli/cli.py) | 非交互；支持 `--output-format text\|json\|stream-json` 与 stdin |
| `CLIConfig` | [cli/agent/config.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/cli/agent/config.py) | 三层优先级配置：settings.json < env < CLI 参数 |
| `create_backend(cfg)` / `LocalBackend` | [cli/agent/factory.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/cli/agent/factory.py) | 经 `create_deep_agent` 构建 DeepAgent |
| `run_repl(backend, cfg, store)` | [cli/ui/repl.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/cli/ui/repl.py) | prompt_toolkit + rich REPL；斜杠命令、shell 透传、HITL |
| `run_once(cfg, prompt, output_format)` | [cli/ui/runner.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/cli/ui/runner.py) | 非交互单次查询 |
| `render_stream(stream, console)` | [cli/ui/renderer.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/cli/ui/renderer.py) | 按 OutputSchema.type 映射到终端输出 |
| `TokenTrackingRail` / `ToolTrackingRail` | [cli/rails/](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/cli/rails) | CLI 专用 Rail |

### 设计模式
- **Click group + 默认路由**
- **后端抽象**（`LocalBackend`）
- **三层配置优先级**
- **三层 Ctrl+C 中断管理器**（`InterruptManager`：第1次中止流、第2次警告、第3次退出）
- **chunk 类型渲染器映射**

---

## 4.12 harness 内部依赖图

```
deep_agent.py
  ├── factory.py (create_deep_agent)
  ├── extension_binder.py (apply_extension_hot)
  ├── task_loop/ (controller, coordinator, handler, executor, event_manager, queues)
  ├── rails/ (base, security, skills, subagent, task_completion, lsp, mcp, progressive_tool, ...)
  ├── prompts/ (builder, sections, sanitize, report, prompt_attachment_manager)
  ├── tools/ (base_tool, code, filesystem, todo, goal, memory, mcp_tools, web, ask_user, cron,
  │           subagent, shell, skills, tool_discovery, multimodal, worktree, lsp_tool,
  │           browser_move, mobile_gui, agent_mode_tools)
  ├── security/ (core, checker, factory, host, models, patterns, file_guard, tiered_policy)
  ├── schema/ (config, state, agent_mode, loop_event, task, interaction, build_context,
  │            extension_spec, deep_agent_spec, stop_condition)
  ├── workspace/ (workspace, directory_builder)
  ├── goal/ (manager, evaluation, schema, store)
  ├── lsp/ (core/manager, core/instance, core/diagnostic_registry, servers/registry, servers/*)
  ├── manifest/ (catalog, models, inputs, introspect, registration)
  ├── resources/ (extension_loader, extension_resolver)
  ├── kv_cache/ (kv_cache_hooks)
  ├── subagents/ (code_agent, research_agent, browser_agent, verification_agent,
  │               mobile_gui_agent, plan_agent, explore_agent)
  ├── image_modality_probe.py
  └── cli/ (cli.py, agent/factory, agent/config, ui/repl, ui/runner, ui/renderer,
            rails/token_tracker, rails/tool_tracker, storage/session_store)
```

全部建于 `openjiuwen.core.*`（Runner、Session、ReActAgent、BaseAgent、AgentRail、ContextEngine、foundation LLM/tool/MCP 原语、sys_operation、controller、memory.lite、foundation.kv_cache、common.logging/exception/security.user_config）之上。

## 4.13 harness 设计模式总结

| 模式 | 体现 |
|------|------|
| **委托** | DeepAgent → 内部 ReActAgent，共享 prompt builder/ability_manager/callback_manager |
| **热重配** | `_hot_reconfigure` 原地重载 Rails/模型/工具/提示词 |
| **选择性事件路由** | bridge/outer-only/deep 三分组 |
| **任务循环四元组** | Controller + EventHandler + Executor + Coordinator + 双队列 |
| **插件热加载** | resolve（纯物化）+ bind（事务绑定 + LoadRecord 记账） |
| **manifest → 提供者注册表** | 描述符捕获与注册分离 |
| **Rail 回调系统** | 反射仅覆盖方法，分节注入共享构建器 |
| **分层权限管线** | 工具策略 → 文件守卫 → strictest；宿主注入钩子 |
| **目标生命周期** | GoalManager + 策略评估器 + TaskCompletionRail + SessionGoalStore |
| **懒锁单例** | LSPServerManager 延迟 asyncio.Lock 创建 |
| **图像探测记忆化** | 按 (api_base, model_name) 进程缓存 |
| **工作区安全路径** | 拒绝绝对/盘符/UNC/..；符号链接回退 |
