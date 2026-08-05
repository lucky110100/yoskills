# 05 - agent_teams 模块

`openjiuwen/agent_teams/` 是 openJiuwen Core 的**多智能体团队框架**，编排多个 LLM 支撑的智能体（Leader + Teammates + 人机交互/桥接/外部 CLI 成员），通过共享任务看板、消息总线和协调事件系统协作。

> 路径前缀：本节文件路径均相对于 `openjiuwen/agent_teams/`

## 5.1 模块总览

| 子模块 | 职责 |
|--------|------|
| `agent/` | TeamAgent 运行时骨架（Leader/Teammate 双角色） |
| `cli/` | 交互式团队 CLI（prompt_toolkit + rich REPL） |
| `mcp/` | stdio MCP 服务器（暴露团队协作工具给外部智能体） |
| `memory/` | 团队级记忆配置（共享 + 成员级） |
| `models/` | 模型池（多端点 LLM 部署与分配） |
| `runtime/` | 团队运行时池与调度（InteractGate 并发契约） |
| `schema/` | 团队数据模型（状态/事件/流/任务/团队） |
| `skill/` | 非交互式团队 CLI（单操作每次调用） |
| `tools/` | SQL 模型与 TeamBackend 团队后端管理 |
| `messager/` | 传输抽象与适配器（inprocess/pyzmq） |
| `harness/` | NativeHarness 内部状态（驱动 DeepAgent ReAct 循环） |
| 根级工具 | `constants.py`、`context.py`、`i18n.py`、`id_generator.py`、`paths.py`、`team_context.py`、`timefmt.py`、`tiny_agent.py` |

---

## 5.2 `agent/` — TeamAgent 运行时骨架

`TeamAgent` 是唯一对外类，由 `TeamRole` 切换 Leader 与 Teammate 行为。采用**四象限分解**避免单类累积 100+ 字段：

| 象限 | 文件 | 内容 |
|------|------|------|
| 静态数据 | [agent/blueprint.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_teams/agent/blueprint.py) | `TeamAgentBlueprint`（frozen dataclass）：`card`/`spec`/`ctx`/`language` |
| 可变运行时状态 | [agent/state.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_teams/agent/state.py) | `TeamAgentState`：`team_session`/`team_member`/`pending_user_query`/`event_listeners`/`team_cleaned`/`idle_since` |
| 每实例资源 | `agent/resources.py` | — |
| 每进程基础设施 | [agent/infra.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_teams/agent/infra.py) | `TeamInfra`：`messager`/`team_backend`/`workspace_manager`/`task_manager`/`message_manager`/`tiny_agent_*` |

### 关键类

| 类 | 文件 | 职责 |
|----|------|------|
| `TeamAgent(BaseAgent)` | `agent/team_agent.py` | 唯一对外类；Leader/Teammate 由 `blueprint.role` 选择 |
| `TeamMember` | [agent/member.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_teams/agent/member.py) | 成员状态机句柄；`update_status`/`update_execution_status` 幂等 |
| `SpawnPayloadBuilder` | [agent/payload.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_teams/agent/payload.py) | 构建跨进程 spawn 线格式；`build_spawn_payload`/`build_member_context`/`build_member_messager_config`（稳定的每成员端口分配） |
| 算子 | `AgentConfigurator`/`SpawnManager`/`RecoveryManager`/`SessionManager`/`StreamController` | 各自拥有内部状态；仅跨算子字段放在 `TeamAgentState` |

### 设计模式
- **四象限分解**：静态/可变/每实例/每进程字段分离
- **单类角色切换**：`TeamRole` 选择 Leader/Teammate
- **spawn payload 公共线契约**：`build_spawn_payload` 输出键必须与 `from_spawn_payload` 读取匹配
- **跨进程扇出经 chunk 观察者**：`StreamController._tag_chunk` 升级每个 chunk 为 `TeamOutputSchema`

---

## 5.3 `cli/` — 交互式团队 CLI

基于 `prompt_toolkit` + `rich` 的交互 REPL，驱动 `Runner` 团队生命周期门面。接受斜杠命令（`/team`、`/session`、`/spec`、`/help`、`/exit`）、shell 透传（`! cmd`）与转发到 `Runner.interact_agent_team` 的纯文本。

### 关键类与函数

| 类/函数 | 文件 | 职责 |
|---------|------|------|
| `TeamCli` | [cli/tui.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_teams/cli/tui.py) | 拥有 PromptSession、rich Console、TeamCliState、inbox 回调；`run()`/`shutdown()` |
| `TeamCliState` | [cli/state.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_teams/cli/state.py) | CLI 侧状态唯一拥有者 |
| `StreamHandle` | [cli/state.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_teams/cli/state.py) | 每团队流消费者任务 + `runtime_ready` future 屏障 |
| `SlashCompleter` | [cli/commands.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_teams/cli/commands.py) | 两级 `prompt_toolkit` tab 补全 |
| `dispatch_slash(cli, line)` | [cli/commands.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_teams/cli/commands.py) | 解析运行斜杠行 |
| `route_text(cli, raw)` | [cli/routing.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_teams/cli/routing.py) | 顶层分派：`/cmd` → `dispatch_slash`，`! cmd` → shell，纯文本 → `Runner.interact_agent_team` |
| `run_team_cli(...)` | [cli/app.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_teams/cli/app.py) | 构建 SpecRegistry、启动 Runner、运行 TeamCli、拆解 |

### 设计模式
- **扁平顶层 + 嵌套子动作分派表**
- **CLI 镜像运行时池状态**：CLI 跟踪自己做什么，`TeamRuntimePool` 仍是真相
- **`runtime_ready` 屏障 + 30s 超时**

---

## 5.4 `mcp/` — stdio MCP 服务器

stdio MCP 服务器，暴露团队协作工具给外部智能体。两种作用域，从 `OPENJIUWEN_TEAM_JOIN` 环境描述符解析：`member`（生成的第三方 CLI 作为一等团队成员，经 `create_team_tools(role="teammate")` 驱动真实团队工具，外加外部 `read_inbox`）与 `operator`（外部非成员控制面）。

### 关键类与函数
- **`_ClientHolder`** — [mcp/server.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_teams/mcp/server.py)：懒连接 `ExternalTeamClient`；`get()` 每调用重绑会话/语言上下文
- `connect_from_env()`：从 `OPENJIUWEN_TEAM_JOIN` 构建连接 `ExternalTeamClient`
- `_operator_tool_defs()`：operator 作用域显式工具定义
- `build_server(client_factory, *, scope) -> Server`：配置低层 `Server`；`@server.list_tools()` 返回 member 工具 + read_inbox 或 operator 工具
- `main()` / `_serve()`：经 anyio 运行 stdio 服务器；`main` 是 `console_scripts` 入口（`openjiuwen-team-mcp` 命令）

### 设计模式
- **作用域驱动双面**：一个服务器二进制，两个工具面
- **member 作用域复用真实团队工具实例**
- **懒单连接 + 每调用上下文重绑**

---

## 5.5 `models/` — 模型池

定义团队规范多端点 LLM 部署形态与刷新助手。团队的 `model_pool` 是 `ModelPoolEntry` 端点列表，`ModelAllocator` 在 Leader 与 Teammates 间分配，使并发调用分散到端点而非饱和单个。

### 关键类

| 类 | 文件 | 职责 |
|----|------|------|
| `ModelPoolEntry` | [models/pool.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_teams/models/pool.py) | 单 LLM 端点；`to_team_model_config()` 物化 `TeamModelConfig` |
| `ModelRouterConfig` | [models/pool.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_teams/models/pool.py) | 单端点路由器（OpenRouter/LiteLLM 代理）；`to_pool_entries()` 展开 |
| `IntelliRouterDeployment` / `IntelliRouterConfig` | [models/pool.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_teams/models/pool.py) | 多部署可靠路由配置 |

### 关键函数
- `inherit_pool_ids(current_pool, new_pool)`：将 `model_id` 从当前带入新池的位精确条目；任何值变更（含 api_key 轮换）强制新 id

### 设计模式
- **双标识**：`model_id`（运行时客户端身份，从不持久化）vs `(model_name, group_index)`（语义持久身份存 DB）
- **位精确签名池 id 继承**：防止凭据轮换后陈旧客户端缓存
- **共享路由器折叠**：相同部署跨条目折叠为一个路由器实例

---

## 5.6 `runtime/` — 团队运行时池与调度

Runner 作用域的 `TeamAgent` 运行时管理。

### 关键类

| 类 | 文件 | 职责 |
|----|------|------|
| `InteractGate` | [runtime/gate.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_teams/runtime/gate.py) | 异步计数在途 interact 载荷 + close-and-drain 步骤；状态机 OPEN→admit→CLOSING→DRAINED |
| `AdmissionTicket` | [runtime/gate.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_teams/runtime/gate.py) | `admit()` 返回的不透明令牌 |
| `RuntimeState` | [runtime/pool.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_teams/runtime/pool.py) | 枚举 RUNNING/PAUSED |
| `ActiveTeam` | [runtime/pool.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_teams/runtime/pool.py) | dataclass：TeamAgent leader 实例 + bound session_id + state + InteractGate |
| `TeamRuntimePool` | [runtime/pool.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_teams/runtime/pool.py) | 进程级池，按 `team_name` 键；团队同时绑定至多一会话 |
| `TeamRuntimeManager` | [runtime/manager.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_teams/runtime/manager.py) | 拥有进程内 `TeamRuntimePool`，分派每次 `run_agent_team_streaming` 到四恢复路径之一 |

### 设计模式
- **运行/交互并发契约**：`InteractGate` 在运行期间 admit interact 载荷，退出时 close-and-drain
- **硬会话边界**：同团队切换会话时先 `stop_team` 拆除陈旧条目
- **只读快照**（`ActiveTeamInfo`）供外部消费者

---

## 5.7 `schema/` — 团队数据模型

状态枚举 + 转换表、事件类型 + pydantic 事件载荷、团队/任务/流 schema。

### 状态枚举（[schema/status.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_teams/schema/status.py)）

| 枚举 | 取值 | 说明 |
|------|------|------|
| `MemberStatus` | UNSTARTED/STARTING/READY/BUSY/PAUSED/STOPPED/RESTARTING/SHUTDOWN_REQUESTED/SHUTDOWN/ERROR | 成员状态 + `MEMBER_TRANSITIONS` 转换表 |
| `ExecutionStatus` | IDLE/STARTING/RUNNING/CANCEL_REQUESTED/CANCELLING/CANCELLED/COMPLETING/COMPLETED/FAILED/TIMED_OUT | 执行状态 + `EXECUTION_TRANSITIONS` |
| `TaskStatus` | PENDING/BLOCKED/PLANNING/IN_PROGRESS/IN_REVIEW/COMPLETED/CANCELLED | 任务状态 + `TASK_TRANSITIONS` |
| `MemberMode` | BUILD_MODE/PLAN_MODE | 成员模式 |

### 事件（[schema/events.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_teams/schema/events.py)）
- `TeamTopic`（TEAM/TASK/MESSAGE）：`build(session_id, team_name)` → `"session:{sid}:team:{team}:{topic}"`
- `TeamEvent`：每个事件类型的字符串常量
- `BaseEventMessage`：所有事件载荷基类
- ~30 类型化事件载荷（团队/成员生命周期、协作、可靠性、消息、任务、swarmflow、worktree、workspace）
- `EventMessage`：配对 `event_type` + `payload` + `sender_id` 的线包装；`from_event`/`get_payload`/`serialize`/`deserialize`

### 团队规约（[schema/team.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_teams/schema/team.py)）
- `TeamRole`：LEADER/TEAMMATE/HUMAN_AGENT/BRIDGE_AGENT/WORKER
- `TeamLifecycle`：TEMPORARY/PERSISTENT
- `MemberSpecBase`：共享身份面；`desc`（公共，同伴 roster）vs `prompt`（私有，仅注入该成员自己系统提示）
- `TeamMemberSpec` / `BridgeMemberSpec` / `ExternalCliAgentSpec`：成员规约
- `TeamSpec`：团队定义（`team_name`/`leader_member_name`/`language`/`dispatch_mode`/`teammate_mode`/`model_pool`/`model_pool_strategy` 等）
- `TeamRuntimeContext`：单成员轻量运行时上下文

### 设计模式
- **条件命名任务状态 + 镜像门**：`PLANNING`/`IN_REVIEW` 是可选门，带返工自边
- **事件类型 ↔ 载荷类双射**：`_EVENT_TYPE_MAP`/`_EVENT_CLASS_MAP`
- **公共/私有描述分离**（`desc` vs `prompt`）
- **窄 roster 投影**（`MemberRosterEntry`）

---

## 5.8 `tools/` — SQL 模型与 TeamBackend

### `tools/models.py` — [tools/models.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_teams/tools/models.py)

静态表：`Team`（`team_info`）、`TeamMember`（`team_member`）。
动态每会话表（抽象基 + 工厂）：`TeamTaskBase`、`TeamTaskDependencyBase`、`TeamMessageBase`、`MessageReadStatusBase`、`TeamTaskReviewVoteBase`。
动态模型工厂：`_get_task_model()`、`_get_message_model()` 等，经 `SQLModelMetaclass` 构建每会话类，带定制复合索引。
`_sanitize_session_id_for_table(session_id)`：BLAKE2s 8 字节 hex 后缀（16 字符）保证 SQL 安全表名。

### `tools/team.py` — [tools/team.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_teams/tools/team.py)

**`TeamBackend`**（a.k.a. Agent Team Manager）：管理既有团队及其成员、任务、消息。构造连线 `TeamTaskManager` + `TeamMessageManager`，持有 spec/runtime 能力上限。

#### 关键方法
- `build_team(display_name, desc, leader_display_name, leader_desc, overrides=None)`：创建团队行、注册 Leader、注册预定义 Teammates、发布 `TeamCreatedEvent`
- `spawn_member(...)` / `startup(on_created)` / `startup_member(member_name, on_created)`（CAS 守卫 UNSTARTED→STARTING）
- `spawn_human_agent(...)` / `spawn_bridge_agent(...)` / `spawn_external_cli_agent(...)`
- `approve_plan` / `approve_tool` / `shutdown_member`（守卫活跃 human agent） / `cancel_member` / `clean_team` / `force_clean_team`
- `is_team_completed() -> Optional[TeamCompletionSnapshot]`：三条件检查（任务全终态→成员全 settled→无未读消息）
- HITT/bridge/外部 CLI 查询面：`is_human_agent`/`human_agent_names`/`hitt_enabled`/`bridge_enabled`/`is_external_cli_agent` 等
- `list_member_roster()`：窄投影

### 设计模式
- **每会话动态 SQLModel 表** + BLAKE2s 后缀
- **能力上限 + 运行时有效标志**：spec 级不可变上限，运行时可降级不可超
- **HITT 任务锁**：活跃 human 的 active 任务在 `force=True` 前不可 shutdown
- **团队完成严格检查**：任何未投递消息都阻止团队结束

---

## 5.9 `messager/` — 传输抽象

### 关键类（[messager/base.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_teams/messager/base.py)）
- `MessagerPeerConfig`：静态对端元数据
- `MessagerTransportConfig`：JSON 安全配置（`backend`[inprocess/pyzmq]、`team_name`、`node_id`、地址、peers 等）；`broadcast_topic()` → `"team:{team_name}:broadcast"`
- `SubscriptionHandle`：订阅不透明句柄

### 关键函数
- `create_messager(config) -> Messager`：按 `config.backend` 分派（inprocess → `InProcessMessager`，pyzmq → `PyZmqMessager`）

---

## 5.10 根级工具

### `constants.py` — [constants.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_teams/constants.py)
保留成员名：`HUMAN_AGENT_MEMBER_NAME`、`USER_PSEUDO_MEMBER_NAME`、`DEFAULT_LEADER_MEMBER_NAME`、`RESERVED_MEMBER_NAMES`（frozenset）

### `context.py` — [context.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_teams/context.py)
会话 id contextvar 管理；`set_session_id`/`get_session_id`/`reset_session_id`。`session_id` 的单一真相源（`TeamAgentState` 刻意不持有，避免"两个真相"问题）

### `i18n.py` — [i18n.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_teams/i18n.py)
进程级 i18n（`cn` 默认 / `en`）；`set_language`/`get_language`/`t(key, **kwargs)`/`reply_hint_for(sender)`

### `id_generator.py` — [id_generator.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_teams/id_generator.py)
统一前缀 id 生成器；单字符 kind 前缀（x=async_tool，w=swarmflow，s=session_spawn，默认 t）+ 8 base36 随机字符；`generate_id(kind, *, length=8)`

### `paths.py` — [paths.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_teams/paths.py)
团队工作区/member 工作区/swarmflow 日志/async-tool 输出/默认 sqlite db 的磁盘布局单一真相源。函数：`configure_openjiuwen_home(path)`/`get_openjiuwen_home()`（默认 `~/.openjiuwen`）/`team_home(team_name)`/`team_session_dir(...)`/`project_worktree_hash(project_dir)` 等

### `team_context.py` — [team_context.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_teams/team_context.py)
决定成员还需被告知什么团队状态，并记住它。**数据驱动投递到对话**，只投递新部分。基线持久化在成员自己的子 `AgentSession` 状态中（`TEAM_CONTEXT_STATE_KEY`）。

#### 关键类
- `TeamContextTracker`：`pending_text(session)`（渲染未告知的全部，不推进）/`commit(session)`（投递后持久化基线）。通道：`_identity_body`/`_team_info_body`/`_roster_block`

### `timefmt.py` — [timefmt.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_teams/timefmt.py)
人类可读时间渲染；`format_time_context(timestamp_ms, now_ms)` → `"<绝对本地时间> (<相对差>)"`。DB 存 ms UTC 纪元，LLM 无法从纯整数推理顺序

### `tiny_agent.py` — [tiny_agent.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_teams/tiny_agent.py)
`agent_teams` 中最小可用智能体：从仅带系统提示 + 模型的 `DeepAgentSpec` 构建的 `NativeHarness`，无工具（除可选结构化输出工具）。

#### 关键类/工厂
- `TinyAgent`：`run(content, schema=None)`（无状态单发）/`chat(content, schema=None)`（有状态多轮）
- `create_tiny_agent(system_prompt, model_name, model_resolver, ...)`：`model_resolver` 映射 `model_name` 到 `TeamModelConfig`
- 预设：`create_title_agent`/`create_summary_agent`/`generate_title`/`generate_summary`
- 生命周期：临时（调用方拥有）或团队级（`TeamAgentSpec.tiny_agents` 声明，`TeamInfra.tiny_agents` 持有）

---

## 5.11 跨切设计模式

| 模式 | 体现 |
|------|------|
| **团队成员编排** | 单 `TeamAgent` 类经 `TeamRole` 兼任 Leader/Teammate；四象限分解 |
| **MCP 服务器双作用域** | 一个二进制两个面：member（复用真实工具）+ operator（显式控制表） |
| **CLI/TUI REPL** | prompt_toolkit + rich + 斜杠命令注册表 |
| **消息路由** | `MessagerTransportConfig` + `create_messager` 工厂；topic 串 `session:{sid}:team:{team}:{topic}` |
| **Skill CLI** | 非交互单操作每次调用对应 MCP 服务器 |
| **运行并发契约** | `InteractGate` admit 载荷 + close-and-drain |
| **数据驱动团队上下文投递** | `TeamContextTracker` 只投递新状态 |
| **能力上限 + 有效标志** | spec 不可变上限，运行时可降级 |
| **条件命名任务状态 + 镜像门** | PLANNING/IN_REVIEW 可选门 |
