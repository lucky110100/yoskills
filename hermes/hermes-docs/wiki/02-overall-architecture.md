# 整体架构

> 交叉引用：[01-项目概述](01-project-overview.md) | [03-agent模块](03-agent-module.md) | [05-gateway模块](05-gateway-module.md)

本篇撕开 Hermes Agent 的外壳，看它**怎么转**。01 回答了"是什么"，这里回答"内部如何组织、数据如何流动、靠哪些设计模式保持可演进"。读前建议先过 [01-项目概述](01-project-overview.md) 建立边界心智。所有行号引用锚定基线 `fa83af3`，可一键回溯。

## 一、分层架构

Hermes Agent 采用六层结构，从下到上依层抽象。下层不知道上层存在；上层通过明确契约调用下层。这是"核心窄、能力在边缘"原则在物理结构上的体现——核心层最小，能力尽量堆在边缘层。

```
┌──────────────────────────────────────────────────────┐
│  前端层   ui-tui (Ink TUI) │ web (React SPA) │ desktop │
│           Electron 三进程 │ Docusaurus 文档站            │
├──────────────────────────────────────────────────────┤
│  CLI 层   hermes_cli / HermesCLI (cli.py)              │
│           子命令 + 配置 + web_models                     │
├──────────────────────────────────────────────────────┤
│  网关层   gateway/run.py (GatewayRunner, TurnRunner)    │
│           gateway/platforms/* (20+ 平台适配器)           │
├──────────────────────────────────────────────────────┤
│  工具层   tools/registry.py (ToolRegistry 单例)         │
│           toolsets.py │ model_tools.py │ MCP client    │
├──────────────────────────────────────────────────────┤
│  核心层   run_agent.py (AIAgent 对话循环)                │
│           agent/ (context_engine / memory / estop /    │
│           error_classifier)                            │
├──────────────────────────────────────────────────────┤
│  后端层   providers/ (ProviderProfile)                  │
│           推理端点 (OpenAI/Anthropic/Gemini/Nous/本地)   │
└──────────────────────────────────────────────────────┘
```

各层职责：

| 层 | 职责 | 关键文件 | 对外契约 |
|----|------|----------|----------|
| 后端层 | 包装推理端点，声明式配置 | [providers/base.py#L39](file:///D:\yaodh\main\hermes-agent\providers\base.py#L39) | ProviderProfile dataclass |
| 核心层 | agent 循环、上下文、记忆、紧急停止 | [run_agent.py#L412](file:///D:\yaodh\main\hermes-agent\run_agent.py#L412)、[context_engine.py#L89](file:///D:\yaodh\main\hermes-agent\agent\context_engine.py#L89)、[memory_provider.py#L81](file:///D:\yaodh\main\hermes-agent\agent\memory_provider.py#L81)、[estop.py#L37](file:///D:\yaodh\main\hermes-agent\agent\estop.py#L37) | AIAgent 类 |
| 工具层 | 工具注册、toolset 解析、function call 调度 | [registry.py#L426](file:///D:\yaodh\main\hermes-agent\tools\registry.py#L426)、[model_tools.py#L1170](file:///D:\yaodh\main\hermes-agent\model_tools.py#L1170) | registry.register() / Surface Gate |
| 网关层 | 平台消息收发、turn 调度 | [gateway/run.py#L5923](file:///D:\yaodh\main\hermes-agent\gateway\run.py#L5923)、[base.py#L2884](file:///D:\yaodh\main\hermes-agent\gateway\platforms\base.py#L2884) | BasePlatformAdapter ABC |
| CLI 层 | 子命令分发、配置管理 | [cli.py#L4267](file:///D:\yaodh\main\hermes-agent\cli.py#L4267) | HermesCLI 门面 |
| 前端层 | 终端/浏览器/桌面交互 | ui-tui/ web/ apps/desktop/ | 进程边界协议 |

分层的关键纪律：**依赖只向下**。前端层不直接调核心层，必须经 CLI 或网关层；核心层不知道前端长什么样，只接受消息、返回流。这保证了同一核心可被四个门面复用而不分叉。
## 二、核心设计模式

以下十大模式是 Hermes Agent 保持可演进的骨架。每个都给出 `file:///` 证据，读者可一键验证。理解这十个，就理解了项目"为什么这么长还不乱"。

### 1. 门面 + 转发器（Facade + Forwarder）

[AIAgent](file:///D:\yaodh\main\hermes-agent\run_agent.py#L412) 是核心门面。三个入口（hermes / hermes-agent / hermes-acp）是不同门面，都转发到同一 AIAgent 循环，避免逻辑分叉。

- **证据**：[run_agent.py#L412](file:///D:\yaodh\main\hermes-agent\run_agent.py#L412) class AIAgent；[pyproject.toml#L364-L367](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L364-L367) 三入口。
- **如何运作**：门面层只做参数装配与界面适配，真正的对话循环、工具调度全在 AIAgent。
- **为何这样**：保证 CLI/网关/TUI/Desktop 行为一致，改一处核心即全入口生效。

### 2. ABC + orchestrator（抽象基类 + 编排器）

凡是"3+ 个竞争实现"的子系统都用 ABC 定义契约，orchestrator 选优，内置实现作为第一个 provider。新实现作 plugin 而非 core。

- **证据**：[MemoryProvider(ABC)](file:///D:\yaodh\main\hermes-agent\agent\memory_provider.py#L81)、[ContextEngine(ABC)](file:///D:\yaodh\main\hermes-agent\agent\context_engine.py#L89)、[BasePlatformAdapter(ABC)](file:///D:\yaodh\main\hermes-agent\gateway\platforms\base.py#L2884)、[ProviderProfile](file:///D:\yaodh\main\hermes-agent\providers\base.py#L39)。
- **如何运作**：ABC 定抽象方法，orchestrator 按配置选具体实现；平台适配器全部继承 BasePlatformAdapter。
- **为何这样**：见 [AGENTS.md#L207-L210](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L207-L210)——当 3+ PR 抢同一类东西，应设计 ABC + orchestrator 而非一个个合。

### 3. 自注册单例注册表（Self-registering Singleton Registry）

每个 tool 文件在模块级调用 `registry.register()` 声明自己，[ToolRegistry](file:///D:\yaodh\main\hermes-agent\tools\registry.py#L426) 是进程内单例。新增工具只加文件，不改核心。

- **证据**：[registry.py#L426](file:///D:\yaodh\main\hermes-agent\tools\registry.py#L426) class ToolRegistry；[registry.py#L737](file:///D:\yaodh\main\hermes-agent\tools\registry.py#L737) register()；[registry.py#L858](file:///D:\yaodh\main\hermes-agent\tools\registry.py#L858) deregister()。
- **如何运作**：模块导入时 register 写入单例表；[registry.py#L74-L81](file:///D:\yaodh\main\hermes-agent\tools\registry.py#L74-L81) 用 AST 扫描判断模块是否含顶层 register 调用，避免无谓导入。
- **为何这样**：开闭原则——对扩展开放（加文件即注册），对修改关闭（核心不动）。

### 4. Footprint Ladder（能力决策阶梯）

新增能力时按六级阶梯选 footprint 最小的 rung：扩展既有 → CLI+skill → service-gated tool → plugin → MCP server → 新 core tool。

- **证据**：[AGENTS.md#L181-L205](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L181-L205) The Footprint Ladder。
- **如何运作**：rung 越靠下，永久表面越大；默认选能解决问题的最高（最小）rung。
- **为何这样**：core tool 随每次 API 调用发送，膨胀 core 即放大所有人成本。MCP server 零 core footprint 且可被任意 MCP host 复用。

### 5. 策略模式（Strategy）

上下文压缩、provider 选择等"同一接口多种算法"处用策略模式。

- **证据**：[ContextEngine(ABC)](file:///D:\yaodh\main\hermes-agent\agent\context_engine.py#L89) 的压缩策略；[ProviderProfile](file:///D:\yaodh\main\hermes-agent\providers\base.py#L39) 的 provider 选择。
- **如何运作**：抽象接口定义算法族，具体策略按配置注入；上下文压缩是唯一允许中途改历史上下文的受控例外（见 prompt caching 原则）。
- **为何这样**：算法可独立替换演进，不污染调用方。
### 6. 退避 + 分类恢复（Backoff + Classified Recovery）

推理调用失败时不无脑重试，先分类再决定退避或切换 profile。

- **证据**：[FailoverReason(enum)](file:///D:\yaodh\main\hermes-agent\agent\error_classifier.py#L24)、[ClassifiedError](file:///D:\yaodh\main\hermes-agent\agent\error_classifier.py#L78)。
- **如何运作**：原始错误经分类器映射到 FailoverReason 枚举（rate-limit / auth / network / server 等），ClassifiedError 包装并带退避建议；不同 reason 走不同恢复路径（重试 vs 换 profile）。
- **为何这样**：避免 rate-limit 雪崩、避免对 auth 错误无意义重试、把恢复策略与错误类型解耦。

### 7. Fail-Safe 紧急停止（Fail-Safe Estop）

[estop](file:///D:\yaodh\main\hermes-agent\agent\estop.py#L37) 用 sentinel 文件实现可恢复的"只暂停新工作"。fail-safe 取向：无法判定状态时默认视为已暂停。

- **证据**：[estop.py#L37](file:///D:\yaodh\main\hermes-agent\agent\estop.py#L37) SENTINEL_NAME、[is_engaged()#L59](file:///D:\yaodh\main\hermes-agent\agent\estop.py#L59)、[engage()#L74](file:///D:\yaodh\main\hermes-agent\agent\estop.py#L74)、[disengage()#L93](file:///D:\yaodh\main\hermes-agent\agent\estop.py#L93)、[get_state()#L104](file:///D:\yaodh\main\hermes-agent\agent\estop.py#L104)。
- **如何运作**：`hermes pause` 写 sentinel，[is_engaged()](file:///D:\yaodh\main\hermes-agent\agent\estop.py#L59) 返回 True 时只挡新工作不中断进行中；sentinel 不可读时也视为已暂停（[estop.py#L62-L69](file:///D:\yaodh\main\hermes-agent\agent\estop.py#L62-L69) 注释）。
- **为何这样**：紧急停止宁可过度也不漏挡；sentinel 文件可跨进程、跨重启感知。

### 8. mixin 拆分 god-file（Mixin Decomposition）

巨型类按职责切成多个 mixin，每个各管一域，避免单文件膨胀失控。

- **证据**：[GatewayRunner](file:///D:\yaodh\main\hermes-agent\gateway\run.py#L5923)（继承 GatewayAuthorizationMixin、GatewayKanbanWatchersMixin、GatewaySlashCommandsMixin 等）；[HermesCLI](file:///D:\yaodh\main\hermes-agent\cli.py#L4267)（继承 CLIAgentSetupMixin、CLICommandsMixin、CLIBillingMixin）。
- **如何运作**：mixin 是只含一组相关方法的父类；主类多继承它们组合出完整行为，每个 mixin 各占一文件。
- **为何这样**：[gateway/run.py](file:///D:\yaodh\main\hermes-agent\gateway\run.py) ~26k 行、[cli.py](file:///D:\yaodh\main\hermes-agent\cli.py) ~17k 行，不分 mixin 则不可维护。

### 9. 结构化流事件契约（Structured Stream Event Contract）

模型流式输出被规范化为结构化事件，而非裸 chunk；多 provider 流被统一抽象，线程级路由保证有序。

- **证据**：[ManagedLlmStream](file:///D:\yaodh\main\hermes-agent\agent\relay_llm.py#L360)（Iterator[Any] 包装统一流）、[AnthropicStreamAccumulator](file:///D:\yaodh\main\hermes-agent\agent\relay_llm.py#L745)、[_ThreadRoutingStream](file:///D:\yaodh\main\hermes-agent\agent\thread_scoped_output.py#L35)、[StreamingThinkScrubber](file:///D:\yaodh\main\hermes-agent\agent\think_scrubber.py#L64)。
- **如何运作**：不同 provider 的原生流经 ManagedLlmStream 统一为迭代器契约；事件按线程路由（thread-scoped）保证并发场景有序；thinking 内容由 StreamingThinkScrubber 擦除。
- **为何这样**：上层（CLI/网关/TUI）只面对一种流契约，provider 差异被吸收在适配层。

### 10. 声明式 Profile（Declarative Profile）

推理后端用声明式 dataclass 配置，而非命令式代码。换模型/端点只改配置不改代码。

- **证据**：[ProviderProfile](file:///D:\yaodh\main\hermes-agent\providers\base.py#L39) dataclass。
- **如何运作**：Profile 记录 base_url、model、api_key、超时等字段；运行时按 Profile 构造 client；failover 在多个 Profile 间切换。
- **为何这样**：模型无关性落地——新增端点只加 Profile 条目，不动核心逻辑；用户可在 config.yaml 声明多 Profile 实现冗余。
## 三、运行时数据流

理解架构最好的方式是跟踪一次请求的旅程。Hermes Agent 有两条主要数据流：CLI 直跑模式与网关消息模式。两者共享 AIAgent 核心，差异在"消息从哪来、响应到哪去"。

### CLI 模式数据流

用户在终端直接对话，单进程内完成全链路：

```
1. hermes 入口 → hermes_cli.main:main
2. HermesCLI 门面装配配置（ProviderProfile、MemoryProvider、toolset）
3. 构造 AIAgent（run_agent.py#L412），注入 profile 与记忆
4. 用户输入消息
5. AIAgent 取启用 toolset → model_tools.get_tool_definitions（#L307）生成 schema
6. AIAgent 经 ProviderProfile 调推理端点，流式经 ManagedLlmStream（relay_llm.py#L360）
7. 模型返回 tool_call → model_tools.handle_function_call（#L1170）调度注册表中的工具
8. 工具结果回灌消息历史
9. 循环 6-8 直至模型不再调用工具
10. 最终响应输出到终端，thinking 经 StreamingThinkScrubber 擦除
11. 历史存入 MemoryProvider，prompt 缓存按会话复用前缀
```

关键点：步骤 6-9 是 tool-calling loop 的心脏，[AIAgent](file:///D:\yaodh\main\hermes-agent\run_agent.py#L412) 维护消息历史，每轮把工具定义随请求发出。步骤 11 是 prompt caching 的兑现——历史不变则前缀缓存命中，成本可控。

### 网关模式数据流

消息从外部平台（Discord/Slack/Telegram 等）进入，经适配器归一化后走同一核心：

```
1. 平台消息到达对应适配器（继承 BasePlatformAdapter#L2884）
2. 适配器把平台原生事件规范化为统一消息结构
3. GatewayRunner（run.py#L5923）接收，按会话路由
4. TurnRunner（run.py#L3834）调度一轮 turn：
   a. 检查 estop（run.py#L14866 引用 agent.estop），已暂停则只挡新工作
   b. 构造 AIAgent，注入会话级 profile 与记忆
   c. 跑对话循环（等同 CLI 模式步骤 5-9）
5. 流式响应经 ManagedLlmStream 规范化
6. 适配器把响应转回平台原生格式发送
7. 会话历史按平台+会话隔离，prompt 缓存按会话复用
```

关键点：步骤 4a 的 estop 检查体现 Fail-Safe——网关长时运行，estop 让运维能暂停新工作而不重启进程。步骤 3 的会话路由保证多平台多会话不串扰。步骤 7 的按会话隔离是 prompt caching 原则在网关形态下的兑现。

### 两条流的共性

无论哪条流，核心循环都落在 [AIAgent](file:///D:\yaodh\main\hermes-agent\run_agent.py#L412)，工具调度都落在 [model_tools.handle_function_call](file:///D:\yaodh\main\hermes-agent\model_tools.py#L1170)，流规范化都落在 [ManagedLlmStream](file:///D:\yaodh\main\hermes-agent\agent\relay_llm.py#L360)。门面层（CLI/网关）只负责"消息进出与界面适配"，核心层负责"思考与工具调用"。这是分层架构 + 门面 + 转发器模式的共同产物。
## 四、关键概念

下列概念是理解设计决策的钥匙。每个给定义、证据、为何重要。

### Prompt Caching（按会话缓存不可侵犯）

长会话每轮复用已缓存前缀；任何中途改历史上下文、切工具集、重建系统提示都会使缓存失效、成倍放大成本。

- **证据**：[AGENTS.md#L18-L22](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L18-L22)。
- **为何重要**：这是项目第一条原则。除上下文压缩这一受控例外，核心循环绝不中途破坏历史，网关/CLI/TUI 都遵守。

### Footprint Ladder（能力决策阶梯）

新增能力按六级阶梯选最小 footprint rung：扩展既有 → CLI+skill → service-gated tool → plugin → MCP server → 新 core tool。

- **证据**：[AGENTS.md#L181-L205](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L181-L205)。
- **为何重要**：core tool 随每次 API 调用发送，膨胀 core 即放大所有人 schema 成本。MCP server 是第 5 级首选——零 core footprint 且可被任意 MCP host 复用。

### 窄腰部（Narrow Waist）

核心保持精简，能力尽量在边缘（CLI/插件/MCP/前端）。

- **证据**：[AGENTS.md#L23-L26](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L23-L26)；[codebase-ownership.md#L34](file:///D:\yaodh\main\hermes-agent\website\docs\developer-guide\codebase-ownership.md#L34)。
- **为何重要**：[website codebase-ownership](file:///D:\yaodh\main\hermes-agent\website\docs\developer-guide\codebase-ownership.md#L34) 明示"涉及两子系统时，改更窄的那个"。这是分层架构的评审准则。

### Profile 隔离（Provider 隔离）

推理后端用声明式 [ProviderProfile](file:///D:\yaodh\main\hermes-agent\providers\base.py#L39) 配置，多 Profile 互不干扰，failover 在 Profile 间切换。

- **证据**：[providers/base.py#L39](file:///D:\yaodh\main\hermes-agent\providers\base.py#L39) dataclass。
- **为何重要**：模型无关性的落地。换 OpenAI/Anthropic/Gemini/本地端点只改 Profile 条目；[error_classifier](file:///D:\yaodh\main\hermes-agent\agent\error_classifier.py#L24) 分类后决定退避或换 Profile。

### Toolset Surface Gate（工具表面闸门）

工具按 toolset 分组，平台会话按需折叠 toolset 决定哪些工具可见，而非全量发送。

- **证据**：[toolsets.py#L756](file:///D:\yaodh\main\hermes-agent\toolsets.py#L756) resolve_toolset；[gateway/run.py](file:///D:\yaodh\main\hermes-agent\gateway\run.py#L405) GUI 网关折叠 desktop_ui toolset。
- **为何重要**：既保证 prompt caching（toolset 不中途切），又让 GUI/CLI 工具可见性不同。Service-gated 工具（`check_fn`）只在 prerequisite 配置时出现，零 footprint 否则。

### Surface = Session Property（表面是会话属性）

工具可见性由会话自身来源解析，而非后端进程环境变量。

- **证据**：[AGENTS.md#L212-L233](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L212-L233)。
- **为何重要**：客户端与后端可能是不同机器不同时钟。env-keyed 的 GUI 闸门在 SSH/URL+token/Cloud 拓扑下会静默失效。正确做法是把工具放命名 toolset（如 desktop_ui），会话平台说 GUI 时才折叠进来。

### Structured Stream Event（结构化流事件）

模型流式输出规范化为结构化事件契约，provider 差异吸收在适配层。

- **证据**：[ManagedLlmStream](file:///D:\yaodh\main\hermes-agent\agent\relay_llm.py#L360)、[_ThreadRoutingStream](file:///D:\yaodh\main\hermes-agent\agent\thread_scoped_output.py#L35)、[StreamingThinkScrubber](file:///D:\yaodh\main\hermes-agent\agent\think_scrubber.py#L64)。
- **为何重要**：上层只面对一种流契约；并发场景靠 thread-scoped 路由保有序；thinking 内容被擦除避免泄露。

### Fail-Safe Estop（紧急停止）

sentinel 文件实现可恢复的"只暂停新工作"；无法判定状态时默认视为已暂停。

- **证据**：[estop.py#L37](file:///D:\yaodh\main\hermes-agent\agent\estop.py#L37)、[is_engaged()#L59](file:///D:\yaodh\main\hermes-agent\agent\estop.py#L59)。
- **为何重要**：网关长时运行，estop 让运维暂停新工作而不重启；fail-safe 取向宁可过度也不漏挡。
## 五、进程模型

不同入口形态对应不同进程拓扑。理解进程边界有助于排障与部署。核心原则不变：无论几个进程，思考与工具调用都落在 [AIAgent](file:///D:\yaodh\main\hermes-agent\run_agent.py#L412)。

| 形态 | 进程数 | 关键进程 | 边界契约 |
|------|--------|----------|----------|
| CLI | 1 | Python | 函数调用（同进程） |
| 网关 | 1 | Python | 平台适配器→GatewayRunner |
| TUI | 2 | Node + Python | tui_gateway IPC |
| Desktop | 3 | Electron 主 + 渲染 + Python | IPC / spawn / SSH |
| Cloud/SSH | 2+ | Electron + 远程 Python | HTTP+token 或 SSH |

### CLI 单进程

```
┌──────────────────────────────┐
│  hermes (单个 Python 进程)    │
│  HermesCLI → AIAgent          │
│  + tools + providers + memory │
│  全部同进程，函数调用直连        │
└──────────────────────────────┘
```

- 最简拓扑，无 IPC 开销。
- 适合本地交互式对话与一次性任务。
- estop sentinel 跨重启感知。

### 网关多适配器（单进程）

```
┌──────────────────────────────────────┐
│  gateway (单个 Python 进程)            │
│  ┌─────────┐ ┌─────────┐ ┌────────┐ │
│  │ Discord │ │  Slack  │ │ ...20+ │ │
│  └────┬────┘ └────┬────┘ └────┬───┘ │
│       └───────────┼───────────┘      │
│           GatewayRunner               │
│           TurnRunner → AIAgent        │
└──────────────────────────────────────┘
```

- 一个进程承载 20+ 平台适配器，均继承 [BasePlatformAdapter](file:///D:\yaodh\main\hermes-agent\gateway\platforms\base.py#L2884)。
- [TurnRunner](file:///D:\yaodh\main\hermes-agent\gateway\run.py#L3834) 调度单轮 turn，含 [estop 检查](file:///D:\yaodh\main\hermes-agent\gateway\run.py#L14866)。
- 会话按平台+会话隔离，prompt 缓存按会话。

### TUI 双进程

```
┌──────────────┐        IPC        ┌─────────────────┐
│  Node (Ink)  │ ←──────────────→ │  Python 后端      │
│  ui-tui      │   tui_gateway     │  tui_gateway/    │
│  React 渲染  │                   │  → AIAgent       │
└──────────────┘                   └─────────────────┘
```

- 前端 TypeScript（Ink，React for CLI），后端 Python（tui_gateway）。
- 双进程分离渲染与思考；经 IPC 传递结构化事件（[ManagedLlmStream](file:///D:\yaodh\main\hermes-agent\agent\relay_llm.py#L360) 契约）。
- 见 11-tui-module。

### Desktop 三进程

```
┌──────────────────────────────────────────┐
│  Electron 主进程 (Node)                   │
│  ├─ 渲染进程 (React Web，仪表盘 UI)        │
│  └─ spawn Python 后端                      │
│      ├─ 本地子进程 → AIAgent               │
│      └─ 或 SSH 远程 → 远端 Python 后端     │
└──────────────────────────────────────────┘
```

- 三进程：Electron 主、渲染、Python 后端。前两者是 Electron 标准，第三是 Hermes 核心。
- 后端可本地 spawn 或经 [windows_ssh_runtime](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L123) 远程。
- 只有本地 spawn 拓扑携带 `HERMES_DESKTOP=1`；其余拓扑靠会话 Surface 解析（见 [AGENTS.md#L219-L226](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L219-L226)）。见 13-desktop-module。

### Cloud / SSH 远程形态

- 客户端（Desktop/TUI）与后端是不同机器不同时钟。
- env-keyed 闸门在此拓扑静默失效，故 Surface 必须按会话解析（Surface = Session Property）。
- 经 HTTP+token 或 SSH 连接远端 Python 后端。

### 进程边界契约总览

| 边界 | 传递内容 | 实现 |
|------|----------|------|
| CLI 同进程 | 函数调用 | 直连 |
| 适配器↔网关 | 平台消息 | BasePlatformAdapter ABC |
| TUI Node↔Python | 结构化事件 | tui_gateway IPC |
| Desktop 渲染↔主 | UI 事件 | Electron IPC |
| Desktop 主↔后端 | spawn/SSH | 子进程或远程 |

## 六、小结

Hermes Agent 是六层结构：后端（providers）→ 核心（AIAgent/agent）→ 工具（registry/model_tools）→ 网关（GatewayRunner/适配器）→ CLI（HermesCLI）→ 前端（TUI/Web/Desktop）。依赖只向下，核心层最小、能力堆边缘。

十大设计模式撑起可演进性：门面+转发器、ABC+orchestrator、自注册单例注册表、Footprint Ladder、策略、退避+分类恢复、Fail-Safe estop、mixin 拆分、结构化流事件契约、声明式 Profile。每条都有 `file:///` 证据可验证。

两条数据流（CLI 直跑、网关消息）共享 AIAgent 核心，差异只在消息进出与界面适配。进程模型从单进程 CLI 到三进程 Desktop，拓扑不同但思考与工具调用总落在 AIAgent。

读到这里，你已建立内部全景。接下来可按子系统深入：[03-agent模块](03-agent-module.md) 切核心循环，[04-tools模块](04-tools-module.md) 切工具系统，[05-gateway模块](05-gateway-module.md) 切消息网关。改任何代码前，重温 [AGENTS.md#L181-L205](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L181-L205) 的 Footprint Ladder，确认能力落在最小 footprint 的 rung。
## 七、跨切关注点

下列关注点横切多个层，不属于任一子系统文档，故在此集中说明。

### 可观测性

运行时埋点与导出集中在 [agent/monitoring/](file:///D:\yaodh\main\hermes-agent\agent\monitoring)：

- **OTLP 导出**：[OTLPStreamer](file:///D:\yaodh\main\hermes-agent\agent\monitoring\otlp_exporter.py#L182) 把 trace/metrics 推送到 OTLP 兼容后端。
- **网关健康**：[GatewayDiagnosticLogStreamer](file:///D:\yaodh\main\hermes-agent\agent\monitoring\gateway_health_export.py#L485) 导出网关诊断日志，便于排障多适配器场景。

可观测性是"窄腰部"的反例允许——监控横切所有层，但它自身在边缘（agent/monitoring 子包），不污染核心循环。

### 安全与供应链

- **依赖精确锁定**：核心 [dependencies](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L19) 用 `==` 锁定，避免隐式升级。见 [pyproject.toml#L34-L38](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L34-L38) scope rule：只有每个会话都用的包才进核心。
- **override-dependencies**：[pyproject.toml#L370](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L370) 强制覆盖某些传递依赖版本。
- **日志轮转**：[hermes_logging](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L143) 跨平台单进程轮转，避免日志爆盘。
- **密钥**：API key 经 `api_key_env` 引用环境变量，不落 config 明文（见 ProviderProfile 用法）。

### 测试策略

- **规模**：~2938 测试文件，pytest 驱动。
- **concurrent gate**：[pyproject.toml#L431](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L431) 的 `real_concurrent_gate` marker 可选退出 autouse stub——默认 stub 禁用 `_detect_concurrent_hermes_instances`，标记测试才跑真实并发检测。
- **patch 模式**：~28 个测试文件 patch `run_agent.OpenAI`（见 [run_agent.py#L50-L55](file:///D:\yaodh\main\hermes-agent\run_agent.py#L50-L55) 注释），故 OpenAI 用代理对象而非顶层导入以保可 patch 性。

详见 15-testing-quality。

### 国际化与 Windows 兼容

- **UTF-8 stdio**：[hermes_bootstrap](file:///D:\yaodh\main\hermes-agent\run_agent.py#L23-L32) 必须是首个导入，在 Windows 设 UTF-8 stdio；POSIX 为 no-op。部分更新时可能缺失（见 [run_agent.py#L28-L32](file:///D:\yaodh\main\hermes-agent\run_agent.py#L28-L32) 优雅降级）。
- **路径与并发**：Windows 单进程日志轮转加锁（[pyproject.toml#L143](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L143)）。
## 八、演进视角与变更纪律

架构的价值不在静态美感，在能否承载长期演进。Hermes Agent 的变更纪律把"窄腰部"从口号落到评审规则：

| 场景 | 纪律 | 出处 |
|------|------|------|
| 新增能力 | 走 Footprint Ladder 选最小 footprint rung | [AGENTS.md#L181-L205](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L181-L205) |
| 3+ 竞争实现 | 设计 ABC + orchestrator，内置作首 provider | [AGENTS.md#L207-L210](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L207-L210) |
| 涉及两子系统 | 改更窄的那个，优先适配器/插件而非 core 分支 | [codebase-ownership#L34](file:///D:\yaodh\main\hermes-agent\website\docs\developer-guide\codebase-ownership.md#L34) |
| 中途改上下文 | 禁止（除压缩受控例外），保 prompt caching | [AGENTS.md#L18-L22](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L18-L22) |
| GUI 工具可见性 | 按会话 Surface 解析，不靠后端 env | [AGENTS.md#L212-L233](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L212-L233) |
| 紧急停新工作 | estop sentinel，fail-safe | [estop.py#L37](file:///D:\yaodh\main\hermes-agent\agent\estop.py#L37) |

这些纪律也是 Code Wiki 增量更新的依据：改了哪一层、动了哪个 rung，决定了要更新哪篇文档（见 [00-wiki-guide](00-wiki-guide.md) 第五节映射表）。架构篇到此收束——它既是"现在长什么样"的快照，也是"以后怎么改才不烂"的准绳。
补充变更纪律：

| 场景 | 纪律 | 出处 |
|------|------|------|
| 新增平台 | 继承 BasePlatformAdapter，作 adapter 而非 core | [base.py#L2884](file:///D:\yaodh\main\hermes-agent\gateway\platforms\base.py#L2884) |
| 新增推理后端 | 加 ProviderProfile 条目，作 plugin | [providers/base.py#L39](file:///D:\yaodh\main\hermes-agent\providers\base.py#L39) |
| 失败恢复 | 经 error_classifier 分类再退避 | [error_classifier.py#L24](file:///D:\yaodh\main\hermes-agent\agent\error_classifier.py#L24) |
| 巨类膨胀 | 按 mixin 拆分 god-file | [run.py#L5923](file:///D:\yaodh\main\hermes-agent\gateway\run.py#L5923) |

## 九、术语对照

| 英文 | 中文 | 详见 |
|------|------|------|
| narrow waist | 窄腰部 | [AGENTS.md#L23-L26](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L23-L26) |
| capability at edges | 能力在边缘 | 同上 |
| prompt caching | 按会话缓存 | [AGENTS.md#L18-L22](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L18-L22) |
| Footprint Ladder | 能力决策阶梯 | [AGENTS.md#L181-L205](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L181-L205) |
| Surface Gate | 表面闸门 | 四节关键概念 |
| facade + forwarder | 门面+转发器 | 二节模式 1 |
| fail-safe estop | 紧急停止 | [estop.py#L37](file:///D:\yaodh\main\hermes-agent\agent\estop.py#L37) |

本篇是基线 `fa83af3` 时刻的架构快照。主分支推进后，按 [00-wiki-guide](00-wiki-guide.md) 第四节增量流程同步：取 diff → 查映射 → 改对应小节 → 校验行号 → 追加更新记录。架构层相对稳定，频繁变动的是子系统实现（03-15），故本篇更新频率应低于子系统文档。## 十、延伸阅读

- **核心循环**：[03-agent模块](03-agent-module.md) — AIAgent、上下文引擎、记忆、estop 细节
- **工具系统**：[04-tools-module](04-tools-module.md) — 自注册 registry、Toolset、MCP client
- **消息网关**：[05-gateway-module](05-gateway-module.md) — 20+ 适配器、TurnRunner、GatewayRunner mixin
- **CLI 门面**：[06-cli-module](06-cli-module.md) — HermesCLI 子命令与配置
- **推理后端**：[09-providers-module](09-providers-module.md) — ProviderProfile 与 failover
- **意图层**：[AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L1-L40) — 设计哲学与贡献准则（贡献前必读）
- **维护流程**：[00-wiki-guide](00-wiki-guide.md) — 增量更新流程与提交映射