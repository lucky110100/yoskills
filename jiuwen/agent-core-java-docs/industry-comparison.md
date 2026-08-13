# 业界对比 - agent-core-java 与主流框架

> 交叉引用: [01-project-overview](01-project-overview.md) | [02-overall-architecture](02-overall-architecture.md) | [04-harness-and-deepagents-module](04-harness-and-deepagents-module.md) | [06-agentevolving-and-autoharness-module](06-agentevolving-and-autoharness-module.md)

本篇为独立对比文档，从两个维度评估 agent-core-java 的定位：一是 Java 生态内与 Spring AI、LangChain4j 的横向对比；二是与同源 Python agent-core 的跨语言对等性对比。最后给出选型建议与决策矩阵。

## 一、对比框架说明

### 1.1 agent-core-java 定位

agent-core-java 是 openJiuwen 框架的 Java 实现，定位为**全栈 Agent SDK**——覆盖单智能体（ReActAgent）、工作流（WorkflowAgent）、深度编码智能体（DeepAgent）、多 agent 团队（LeaderTeammate）、强化学习优化（agentevolving）、端到端自动改码（autoharness）与 LSP 集成。它不只是一个 LLM 调用封装，而是一套面向"自动编码 + 自我进化 + 团队协作"的工程化运行时。

### 1.2 对比对象

| 对比对象 | 定位 | 在本篇中的角色 |
|----------|------|----------------|
| agent-core-java | 全栈 Agent SDK（Java） | 被评估主体 |
| Spring AI | Spring 生态 AI 抽象层 | Java 生态横向参照 |
| LangChain4j | LangChain 的 Java 移植 | Java 生态横向参照 |
| Python agent-core | 全栈 Agent SDK（Python） | 跨语言对等性参照 |

### 1.3 对比原则

1. **同维度横切**：每张表固定维度列，确保可比性。
2. **基于公开事实**：Spring AI / LangChain4j 取其官方文档公开能力；agent-core 取自 [agent-core](file:///D:/jiuwen/main/agent-core) 源码与 [pom.xml](file:///D:/jiuwen/main/agent-core-java/pom.xml)。
3. **不贬低、不溢美**：局限与优势并列，避免选择性陈述。
4. **区分"原生"与"可自实现"**：标"无"指框架未原生提供，并非指用户完全无法自行实现。

## 二、Java 生态对比

下表对比 agent-core-java 与 Spring AI、LangChain4j 在 14 个维度上的差异。

| 维度 | agent-core-java | Spring AI | LangChain4j | 说明 |
|------|----------------|-----------|-------------|------|
| 定位 | 全栈 Agent SDK（编码/团队/RL/自动改码） | Spring 生态 AI 抽象层 | LangChain 的 Java 移植 | agent-core 范围最广，含工程化能力 |
| Agent 范式 | ReActAgent + WorkflowAgent + DeepAgent + LeaderTeammate | ChatClient + Advisor 链 | Chain / Agent / AiServices | agent-core 原生支持任务循环与子代理 |
| 图执行引擎 | Pregel BSP 自研（[Graph](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/graph/Graph.java)） | 无（Advisor 顺序链） | 无（顺序 Chain） | agent-core 用 BSP 葫芦图支持循环/分支/并行 |
| 多 agent 团队 | LeaderTeammate + TeamBackend（[TeamAgent](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/agent/TeamAgent.java)） | 无原生团队 | 无原生团队 | Spring AI/LC4j 需自行编排多 agent |
| 编码能力 | DeepAgent + BashTool/LspTool/TodoTool + 四阶段子代理 | 无 | 无 | agent-core 专注编码场景 |
| 自动改码 | autoharness 7 阶段 + CI 修复 | 无 | 无 | 端到端 assess→plan→implement→verify |
| RL 优化 | agentevolving Trainer/Evaluator/Optimizer | 无 | 无 | 指令/示例优化 + VERL 离线 RL |
| LSP 集成 | [LspRail](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/LspRail.java) 8 操作（定义/引用/诊断/Hover 等） | 无 | 无 | 语义代码导航 |
| 沙箱执行 | JiuwenBox / Aio Mixin | 无 | 无 | 文件/命令隔离执行 |
| 存储后端 | SPI 工厂：Redis/Milvus/Chroma/pgvector/ES/SQLite/H2/InMemory | Spring Data 抽象（JPA/Redis/Vector） | 无统一存储抽象 | agent-core 运行时切换后端 |
| 检查点 | RedisCheckpointer 三 Storage | Spring Session | 无原生 | agent-core 支持会话级状态持久化 |
| 中断恢复 | 三层：Checkpointer + Pregel + HITL | 无 | 无 | 断点续跑、人机交互中断 |
| 可观测性 | OpenTelemetry 1.64.0 原生集成 | Micrometer/OTel | OTel 可选 | 三者均支持 OTLP |
| 流式输出 | Reactor 响应式流（`Mono`/`Flux`） | Stream 模式 | Stream 模式 | Java 用 Project Reactor；其余用回调/迭代器 |
| MCP 支持 | [McpRail](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/McpRail.java) + stdio/SSE/streamable_http | MCP Client（1.x） | MCP Client | agent-core 多传输 + Rail 钩子 |
| 多租户隔离 | TenantContext + Workspace 绑定 | 无原生 | 无原生 | agent-core 会话/工作区/存储级隔离 |
| 工具权限 | 3 层 ALLOW/ASK/DENY | 无原生 | 无原生 | agent-core 工具调用前拦截审批 |
| 许可证 | Apache-2.0 | Apache-2.0 | Apache-2.0 | 均可商用 |

### 2.1 关键差异解读：图执行引擎

Spring AI 与 LangChain4j 均无 BSP（Bulk Synchronous Parallel）图执行引擎，复杂循环依赖调用方手写状态机或 Advisor 顺序链。agent-core 的 [Graph](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/graph/Graph.java) 原生支持收敛循环（如 ReAct 多轮工具调用、任务循环），具备中断/恢复语义。这意味着：

- ReAct 多轮工具调用无需用户管理轮次计数与退出条件；
- 任务循环（TaskLoop）可作为一等公民，跨轮保持上下文；
- 工作流可含条件分支、并行通道与收敛聚合，由引擎统一调度。

### 2.2 关键差异解读：编码纵深

agent-core 的 [DeepAgent](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/deep_agent/DeepAgent.java#L97) 内置 [BashTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/BashTool.java) / [LspTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/LspTool.java) / [TodoTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/TodoTool.java) 与 CodeAgent/Explore/Plan/Verification 四阶段子代理，是三者中唯一面向"自动改码"全链路的框架。Spring AI 与 LangChain4j 聚焦 LLM 调用与 RAG，未提供语义代码导航（LSP）与端到端改码流水线。

### 2.3 关键差异解读：存储统一

Spring AI 用 Spring Data 抽象，偏向配置驱动（application.yml + 自动装配）；agent-core 用 SPI + `java.util.ServiceLoader` 工厂，运行时按配置切换，检查点/向量/KV 共用一套抽象（[BaseDbStore](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/spi/store/BaseDbStore.java) / [BaseKVStore](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/spi/store/BaseKVStore.java)）。LangChain4j 通过各 `XxxStore` 适配器对接向量库，但无统一检查点抽象。

### 2.4 能力矩阵汇总

| 能力 | agent-core-java | Spring AI | LangChain4j |
|------|:---------------:|:---------:|:-----------:|
| LLM 调用 | ✅ | ✅ | ✅ |
| 工具调用 | ✅ | ✅ | ✅ |
| RAG 检索 | ✅ | ✅ | ✅ |
| 图循环引擎 | ✅ | ❌ | ❌ |
| 任务循环 | ✅ | ❌ | ❌ |
| 多 agent 团队 | ✅ | ❌ | ❌ |
| 编码智能体 | ✅ | ❌ | ❌ |
| 自动改码 | ✅ | ❌ | ❌ |
| RL 优化 | ✅ | ❌ | ❌ |
| LSP 集成 | ✅ | ❌ | ❌ |
| 检查点/中断恢复 | ✅ | △(Session) | ❌ |
| 多后端存储切换 | ✅ | △(Spring Data) | △(适配器) |

> ✅ 原生支持　△ 部分支持　❌ 未原生支持

### 2.5 关键差异解读：多租户与工具权限

agent-core-java 通过 `TenantContext` 实现会话级、工作区级与存储级的多租户隔离——同一进程可服务多租户且数据互不可见，[DeepAgent](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/deep_agent/DeepAgent.java#L97) 在 [invoke](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/deep_agent/DeepAgent.java#L820) 时绑定租户工作区并传播到任务线程。工具权限采用 3 层 ALLOW/ASK/DENY，在工具调用前拦截审批。Spring AI 与 LangChain4j 均无原生多租户与工具权限抽象，需借助 Spring Security 或自研拦截器。

### 2.6 关键差异解读：MCP 与流式输出

MCP（Model Context Protocol）方面，agent-core-java 经 [McpRail](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/McpRail.java) 接入，支持 stdio/SSE/streamable_http 多传输，并以 Rail 钩子融入生命周期；Spring AI 与 LangChain4j 亦提供 MCP Client，但缺少 Rail 级钩子。流式输出方面，agent-core-java 用 Project Reactor 的 `Mono`/`Flux` 提供背压感知的响应式流，适合高并发后端；Spring AI 与 LangChain4j 多用回调或迭代器模式。

### 2.7 成熟度与生态对照

| 维度 | agent-core-java | Spring AI | LangChain4j |
|------|----------------|-----------|-------------|
| 起源 | Python agent-core 的 Java 对等移植 | VMware/Pivotal 官方主导 | 社区主导，对标 LangChain（Python） |
| 社区规模 | 成长中 | 背靠 Spring 全家桶 | 活跃社区 |
| 文档完整度 | 建设中（本系列为目标） | 完善 | 较完善 |
| Spring 集成 | 待提供 Starter | 原生 | 可选 |
| 生产就绪 | 核心路径已就绪 | GA | GA |

## 三、跨语言对比 agent-core Java vs Python

agent-core-java 是 Python agent-core 的对等 Java 移植。下表在 16 个维度上对比二者实现差异，箭头 `≈` 表示对等。

| 维度 | Java | Python | 差异说明 |
|------|------|--------|----------|
| 语言/运行时 | Java 17（JIT，强类型） | Python 3.11–3.13（解释，动态） | Java 性能/类型安全占优；Python 灵活/生态广 |
| 包管理 | Maven 3.9+（pom.xml） | uv/pip（pyproject.toml） | Maven 声明式锁定；Python 推荐 uv |
| 图引擎 | Pregel BSP 对等（[Graph](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/graph/Graph.java)） | Pregel BSP 对等 | 二者算法等价，状态/通道语义一致 |
| Card/Config | BaseCard + Lombok `@Builder` | Pydantic BaseCard | Java 用注解生成 builder；Python 用 Pydantic 校验 |
| Runner 单例 | `GLOBAL_RUNNER`（[Runner](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/runner/Runner.java#L44) L44） | `GLOBAL_RUNNER`（Runner 单例） | Java 静态门面代理；Python 类属性描述符代理 |
| DeepAgent | [DeepAgent](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/deep_agent/DeepAgent.java#L97) L97 ≈ Python L211 | [deep_agent.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/deep_agent.py) L211 | 对等：内部 ReActAgent + TaskLoop + Rails |
| TaskLoop 四元组 | Controller/EventHandler/EventExecutor/Coordinator 对等 | 同 | 事件队列、循环协调器语义一致 |
| Rails | DeepAgentRail priority（[LspRail](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/LspRail.java)） | AgentRail priority | 生命周期钩子对等；Java 用接口+默认方法 |
| 权限 | 3 层 ALLOW/ASK/DENY 简化 | 5 层管道 + PermissionMode | Python 更细；Java 简化为 3 态 |
| LSP | LspTool 8 操作对等 | LspTool 8 操作 + 诊断闭环双钩子 | Python 多了诊断闭环双钩子；Java 未明确 |
| 子代理 | CodeAgent/Explore/Plan/Verification 四阶段对等 | 同 | 编码子代理职责划分一致 |
| 自动改码 | autoharness 7 stages 对等 | rsi/auto_harness 7 stages | 阶段拓扑一致（assess/plan/implement/verify/...） |
| RL 优化 | agentevolving Trainer 对等 | agent_evolving Trainer | 指令/示例优化 + 离线 RL 等价 |
| 存储 | SPI Factory + ServiceLoader | extensions 直接实现 | Java 用 SPI 工厂延迟绑定；Python 直接 import |
| 沙箱 | JiuwenBox / Aio Mixin | SysOperation LOCAL/SANDBOX | Java Mixin 组合；Python 枚举切换 |
| 测试 | JUnit5 + Mockito + AssertJ + Jacoco | pytest + pytest-asyncio + pytest-cov | Java 注解驱动；Python fixture 驱动 |
| MCP | McpRail + stdio/SSE/streamable_http 对等 | MCP + 多传输 | 二者均支持多传输；Java 多 Rail 钩子 |
| 多租户 | TenantContext + Workspace 绑定 对等 | TenantContext 对等 | 隔离语义一致 |
| 流式输出 | Reactor `Mono`/`Flux` | asyncio async generator | Java 背压感知；Python 协程 |
| 工作流 | Workflow + WorkflowController 对等 | Workflow 对等 | 图编排语义一致 |
| 检查点恢复 | RedisCheckpointer 三层 对等 | RedisCheckpointer 三层 | 断点/恢复语义一致 |
| 工具权限 | 3 层 ALLOW/ASK/DENY | 5 层管道 + PermissionMode | Python 更细 |

### 3.1 核心算法对等性详解

- **Pregel 图引擎**：Java 版 [Graph](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/graph/Graph.java) 与 Python 版采用相同的 BSP 模型——超步（superstep）驱动、通道（channel）通信、收敛判定。状态机与消息传递语义完全一致，仅数据结构用 Java 集合替代 Python 字典。
- **ReAct 循环**：思考-行动-观察三元组的循环逻辑、工具调用协议、错误恢复策略均对等。[DeepAgent](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/deep_agent/DeepAgent.java#L97) 内部 ReActAgent 的装配流程与 Python 版 [deep_agent.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/deep_agent.py) L211 一致。
- **TaskLoop 四元组**：TaskLoopController（提交轮次）、TaskLoopEventHandler（处理事件）、TaskLoopEventExecutor（执行任务）、LoopCoordinator（协调收敛）——四者职责划分与 Python 版完全对应。
- **autoharness 7 阶段**：assess（评估差距）→ plan（制定计划）→ implement（实施改码）→ verify（验证修复）及后续阶段，阶段拓扑与产物契约（produces/consumes）一致。

### 3.2 语言特色差异详解

- **Card/Config**：Java 版用 Lombok `@Builder` 生成不可变构建器，编译期类型检查；Python 版用 Pydantic 运行时校验，更灵活但无编译期保证。
- **Runner 单例**：Java 版 [Runner](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/runner/Runner.java#L44) 用静态方法门面代理 `GLOBAL_RUNNER`（L44）；Python 版用 `_ClassProperty` 描述符在类级别转发，二者均无需实例化即可访问。
- **存储扩展**：Java 版用 SPI 工厂 + `ServiceLoader` 延迟绑定，编译期全量、运行时选择；Python 版用 `extensions` 直接 import + extras 可选组按需安装。

### 3.3 对等性结论

- **核心算法 100% 对等**：Pregel 图引擎、ReAct 循环、TaskLoop 四元组、DeepAgent 装配、autoharness 7 阶段、agentevolving Trainer——Java 版忠实移植了 Python 版的执行语义。
- **语言特色差异**：Java 版用 Lombok/SPI/接口默认方法表达 Python 版的 Pydantic/extras/猴子补丁，属实现风格差异而非能力缺失。
- **权限模型简化**：Java 版 3 层（ALLOW/ASK/DENY）是 Python 版 5 层管道的精简，详见第五章局限。
- **LSP 诊断闭环**：Python 版明确双钩子（before/after 诊断），Java 版 8 操作对等但闭环双钩子未明确，属待补齐项。

### 3.4 异步模型与流式差异详解

Java 版采用 Project Reactor（`reactor-core` 3.6.2）的 `Mono`/`Flux` 作为响应式原语，提供背压（backpressure）感知与操作符组合能力，适合高并发后端服务（如 WebFlux 控制器）。Python 版基于 `asyncio` 协程与 `async generator`，生态更全异步、更轻量。二者在流式输出语义上对等（分块产出、中途取消、错误传播），但实现范式不同：Java 是推-拉背压模型，Python 是协程调度模型。

### 3.5 权限模型差异详解

Python agent-core 采用 5 层权限管道 + `PermissionMode`，支持更细粒度的审批策略（如只读/受限写/完全信任等模式切换）。Java 版当前简化为 3 层（ALLOW/ASK/DENY）：ALLOW 直接执行、ASK 请求人工确认、DENY 拒绝。这是 Java 版当前的主要功能差距——在需要多级信任边界（如生产环境分级审批）的场景下，3 层模型表达能力不足。改进方向是对齐 Python 5 层管道语义，详见第五章。

### 3.6 工具体系与工作流对等性

工具体系方面，Java 版的 [BashTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/BashTool.java) / [CodeTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/CodeTool.java) / [LspTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/LspTool.java) / [TodoTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/TodoTool.java) / [TaskTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/TaskTool.java) / [CronTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/CronTool.java) 与 Python 版工具集一一对应，工具卡（ToolCard）Schema 与调用协议一致。工作流方面，Java 版 [Workflow](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/workflow/Workflow.java) 的 Start/End/LLMComponent 组件模型与 Python 版对等，WorkflowController 的执行语义（拓扑序、并行通道、收敛聚合）也一致。二者在工具与工作流层完全可互操作。

## 四、agent-core-java 独特优势

相较 Spring AI 与 LangChain4j，agent-core-java 具备以下独有能力：

### 4.1 Pregel BSP 自研图引擎

[Graph](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/graph/Graph.java) 支持收敛循环、并行通道、中断恢复，复杂工作流无需手写状态机。这意味着 ReAct 多轮调用、任务循环、条件分支工作流均可由引擎统一调度，且每一步可设检查点。

### 4.2 LeaderTeammate 多 agent 团队

[TeamAgent](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/agent/TeamAgent.java) 内置 Leader/Teammate 角色与 TeamBackend 派发，开箱即用多 agent 协作。Leader 负责任务分解与派发，Teammate 各自持有 DeepAgent 执行子任务，无需用户自研编排逻辑。

### 4.3 autoharness 端到端改码

assess→plan→implement→verify→... 7 阶段流水线 + 产物契约编排，自动完成"分析-改码-验证"闭环。每个 stage 声明 produces/consumes 产物类型，orchestrator 据此按拓扑序编排，保证阶段间数据依赖被满足。

### 4.4 agentevolving RL 优化

Trainer/Evaluator/Optimizer 支持指令优化（InstructionOptimizer）与 VERL 离线 RL，让 Agent 自我进化。基于轨迹反馈自动改写系统提示词或示例，突破人工调参瓶颈。

### 4.5 LSP 集成

[LspRail](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/LspRail.java) + [LspTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/LspTool.java) 8 操作，提供语义级代码导航（定义/引用/诊断/Hover 等），是编码 Agent 的关键差异化能力。相比纯正则/文本匹配，LSP 提供跨文件、语言服务器级的精确符号定位。

### 4.6 三层中断恢复

RedisCheckpointer（会话状态）+ Pregel（图断点）+ HITL（人机交互）三层协同，长任务可断点续跑、可人工介入。这是生产级长任务（如大规模重构）的必要能力。

### 4.7 SPI 统一存储

[BaseDbStore](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/spi/store/BaseDbStore.java) / [BaseKVStore](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/spi/store/BaseKVStore.java) 抽象 + `ServiceLoader` 发现，Redis/Milvus/Chroma/pgvector/ES/SQLite/H2/InMemory 一套接口切换。运行时改配置即可换后端，无需改业务代码。

### 4.8 跨语言互操作与对等移植

agent-core-java 与 Python agent-core 语义对等，这意味着：Python 版验证的提示词、技能、工作流定义可低成本的迁移到 Java 版；同一团队可按场景选语言（原型用 Python，生产用 Java），二者产出可互验。这种"双语言对等"是 Spring AI / LangChain4j 不具备的——它们没有官方的 Python 对等实现。

## 五、agent-core-java 局限与改进方向

诚实记录当前不足，指明改进路径：

| 局限 | 现状 | 改进方向 |
|------|------|----------|
| 权限 3 层不如 Python 5 层细 | Java 版仅 ALLOW/ASK/DENY 三态 | 对齐 Python 5 层管道 + PermissionMode，支持更细粒度审批 |
| LSP 诊断闭环未明确双钩子 | Java LspTool 8 操作对等，但诊断闭环双钩子未明确 | 补齐 before/after 诊断双钩子，形成"诊断-修复-再诊断"闭环 |
| ExtendedEvolvePipeline stub | 扩展演进流水线为占位实现 | 完成与 Python 版 `skill_evolution` 对等的演进管线 |
| 文档较少 | 官方文档以 Python 版为主，Java 版文档在建 | 补齐 API 文档与示例（本系列文档即为此目标） |
| 异步模型 | Reactor 响应式已集成，但部分路径仍同步 | 扩大 Reactor 覆盖，对齐 Python 全异步语义 |
| 生态广度 | Spring AI 背靠 Spring 全家桶 | 提供 Spring Boot Starter 适配，降低集成成本 |
| 可选后端编译期全量 | SPI 编译期全量引入，运行时选择 | 探索 Maven profile 或可选依赖拆分，减小体积 |

### 5.1 局限影响评估

上述局限对实际使用的影响程度不一：

- **权限 3 层**：影响"多级信任边界"场景（如生产环境分级审批、敏感操作二次确认）。对内部工具与开发场景影响较小，因 ASK 已覆盖基本人工确认需求。建议优先补齐。
- **LSP 诊断闭环**：影响"自动修复后回归验证"闭环。当前可由用户在 autoharness verify 阶段手动触发诊断，但自动化程度不足。中优先级。
- **ExtendedEvolvePipeline stub**：影响"技能自动演进"链路。当前 Trainer 已可用于指令/示例优化，但扩展演进管线未完成，属增量能力。低优先级。
- **异步覆盖**：影响"高并发流式后端"场景。Reactor 已在流式输出与 WebFlux 控制器路径覆盖，部分内部路径仍同步，对吞吐有边际影响。中优先级。

### 5.2 与 Spring AI / LangChain4j 的差距反向

值得注意的是，agent-core-java 的局限多为"对 Python 版的对等性缺口"，而非"对标 Spring AI / LangChain4j 的能力缺失"。事实上，agent-core-java 在图引擎、多 agent、编码、RL、LSP、中断恢复上反而**领先**于 Spring AI 与 LangChain4j。因此局限主要影响的是"与 Python 版的功能对齐度"，而非"Java 生态内的竞争力"。

## 六、选型建议

### 6.1 何时选 agent-core-java

- 需要**自动改码/编码智能体**：DeepAgent + LSP + autoharness 是三者中唯一端到端方案。
- 需要**多 agent 团队协作**：LeaderTeammate 开箱即用，无需自研编排。
- 需要**长任务中断恢复**：三层 Checkpointer + Pregel 断点 + HITL。
- 需要**RL 自我进化**：agentevolving Trainer 是独有能力。
- 团队**Java 技术栈**且需强类型/高性能：Java 17 + Maven 工程化成熟。
- 需要**统一多后端存储**：SPI 工厂运行时切换 Redis/Milvus/pgvector。
- 需要**语义代码导航**：LSP 集成是编码 Agent 的关键差异化能力。
- 需要**会话级多租户隔离**：TenantContext + Workspace 绑定，同进程服务多租户。

### 6.2 何时选 Spring AI

- 已深度使用 **Spring 生态**（Boot/Cloud/Data），希望 AI 能力与现有配置/观测一体化。
- 需求以 **ChatClient + Advisor** 为主，不需要复杂图循环与编码纵深。
- 看重 **Micrometer/Actuator** 可观测性与 Spring Security 集成。

### 6.3 何时选 LangChain4j

- 需要 **LangChain 生态对齐**（文档加载器、向量库适配丰富）。
- 需求以 **RAG/工具调用** 为主，偏好 AiServices 声明式风格。
- 希望轻量、无 Spring 依赖的纯 Java 方案。

### 6.4 何时选 Python agent-core

- 需要**全异步生态**与最完整的功能（Python 版为源头实现，最新特性先落地）。
- 需要**移动 GUI/在线 RL/Mem0** 等 Python 独有可选组。
- 团队**Python 技术栈**且接受动态类型。

### 6.5 决策矩阵

| 需求场景 | 首选 | 次选 | 理由 |
|----------|------|------|------|
| 自动改码/编码智能体 | agent-core-java | Python agent-core | 唯一端到端方案 |
| 多 agent 团队协作 | agent-core-java | Python agent-core | LeaderTeammate 原生 |
| 通用 ChatClient + RAG | Spring AI | LangChain4j | 生态成熟、配置驱动 |
| Spring 全家桶集成 | Spring AI | — | 无缝对接 Boot/Security |
| LangChain 生态对齐 | LangChain4j | — | 移植一致性 |
| 长任务中断恢复 | agent-core-java | — | 三层恢复独有 |
| RL 自我进化 | agent-core-java | Python agent-core | agentevolving 独有 |
| 全异步 + 最新特性 | Python agent-core | agent-core-java | Python 为源头 |
| 强类型/高性能后端 | agent-core-java | — | Java 17 + JIT |
| LSP 语义代码导航 | agent-core-java | — | LspRail/LspTool 独有 |
| SPI 多后端存储切换 | agent-core-java | — | 一套接口切换 Redis/Milvus |

### 6.6 集成成本与学习曲线

| 维度 | agent-core-java | Spring AI | LangChain4j |
|------|----------------|-----------|-------------|
| 最小可用示例 | 注册模型 + createDeepAgent + invoke | ChatClient.create().prompt() | AiServices.create() |
| 学习曲线 | 中（需理解 DeepAgent/Rails/TaskLoop） | 低（Spring 风格，配置驱动） | 低（声明式接口） |
| Spring Boot 集成成本 | 待提供 Starter | 原生 | 可选 starter |
| 依赖体积 | 较大（含 Milvus/OTel 等） | 中 | 轻 |
| 迁移到 Python 版成本 | 低（语义对等） | 高 | 中 |

### 6.7 混合架构建议

实际项目中可混合使用：

- **后端服务层用 Spring AI**：复用 Spring Boot/Security/Data 生态，处理 ChatClient/RAG 通用需求。
- **编码/自动化智能体用 agent-core-java**：在需要自动改码、多 agent 团队、长任务中断恢复的模块引入 DeepAgent/autoharness。
- **原型与最新特性用 Python agent-core**：利用 Python 版最新特性快速验证，验证后移植到 Java 版。

> 总结：agent-core-java 在"编码智能体 + 多 agent 团队 + 自动改码 + RL + 中断恢复"上具备 Java 生态独有纵深；若需求偏向通用 ChatClient/RAG 且已绑定 Spring，Spring AI 更轻量；若需对齐 LangChain 生态，LangChain4j 更直接。与 Python agent-core 的关系是"对等移植 + 语言特色"，功能覆盖基本一致，差异集中在权限粒度与 LSP 诊断闭环等细节。
