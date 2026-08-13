# 02 整体架构:分层与核心设计模式

> 交叉引用: [01-project-overview](01-project-overview.md) | [03-core-module](03-core-module.md) | [04-harness-and-deepagents-module](04-harness-and-deepagents-module.md) | [09-dependencies](09-dependencies.md)

本文档自底向上描述 agent-core-java 的分层架构、十大核心设计模式、运行时数据流与关键概念,并与 Python 版 `agent-core` 对照,帮助开发者建立从基础设施到协作层的完整心智模型。项目定位与能力总览见 [01-project-overview](01-project-overview.md)。

## 一、分层架构总览

agent-core-java 采用自底向上的九层架构。下层为上层提供原语,上层以下层组合出更高阶能力。各层均位于 `src/main/java/com/openjiuwen/` 下对应包中。

```
┌──────────────────────────────────────────────────────────────────┐
│ 9 扩展层 extensions/spi    SPI 工厂 + 存储后端 + 沙箱 + 检查点      │
├──────────────────────────────────────────────────────────────────┤
│ 8 演化层 agentevolving/autoharness  Trainer(RL) + AutoHarness 改码 │
├──────────────────────────────────────────────────────────────────┤
│ 7 协作层 agentteams  LeaderTeammateAgentTeam → TeamAgent → Kernel  │
├──────────────────────────────────────────────────────────────────┤
│ 6 框架层 harness/deepagents  DeepAgent+Rails+Tools+TaskLoop 四元组 │
├──────────────────────────────────────────────────────────────────┤
│ 5 Agent 层 core/singleagent  ReActAgent / WorkflowAgent           │
├──────────────────────────────────────────────────────────────────┤
│ 4 资源层 core/runner  Runner 单例(GLOBAL_RUNNER)+ResourceMgr+TagMgr│
├──────────────────────────────────────────────────────────────────┤
│ 3 会话层 core/session  Session / Checkpointer(三层中断恢复)        │
├──────────────────────────────────────────────────────────────────┤
│ 2 引擎层 core/graph/pregel  Pregel BSP(Pregel→Loop→Pool→Channel) │
├──────────────────────────────────────────────────────────────────┤
│ 1 基础设施层 foundation  Model(LLM 客户端)/Tool/Store/ContextEngine│
└──────────────────────────────────────────────────────────────────┘
```

各层要点:

1. **基础设施层 foundation**:提供 Model(LLM 客户端)、Tool、Store、ContextEngine 等无状态原语;[BaseCard](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/common/schema/BaseCard.java#L17) 是所有声明性元数据的基类(含 [ToolCard](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/foundation/tool/ToolCard.java))。
2. **引擎层 core/graph/pregel**:Pregel 超步(BSP)图执行引擎,核心链路为 [Pregel](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/graph/pregel/Pregel.java#L24)→[PregelLoop](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/graph/pregel/PregelLoop.java#L27)→[TaskExecutorPool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/graph/pregel/TaskExecutorPool.java#L33)→ChannelManager,负责工作流编排与节点并行。
3. **会话层 core/session**:[Session](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/session/Session.java) 与 [Checkpointer](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/session/checkpointer/Checkpointer.java#L24) 构成三层中断恢复链:Checkpointer(会话级)→PregelLoop(GraphStoreState 快照)→ReActAgent(HITL)。
4. **资源层 core/runner**:[Runner](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/runner/Runner.java#L44) 持有进程级单例 `GLOBAL_RUNNER`;[ResourceMgr](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/runner/resourcemanager/ResourceMgr.java#L52) 管理 7 类资源并维护 `idToCard` 元数据表;[TagMgr](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/runner/resourcemanager/TagMgr.java) 提供多租户隔离。
5. **Agent 层 core/singleagent**:[ReActAgent](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/agents/ReActAgent.java#L77)(Reasoning→Acting→Observation)与 [WorkflowAgent](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/application/workflow/WorkflowAgent.java) 两类预置智能体。
6. **框架层 harness/deepagents**:DeepAgent+Rails+Tools+TaskLoop 四元组;[DeepAgentRail](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/DeepAgentRail.java#L14) 提供优先级排序的 init/uninit 生命周期与 before/after 钩子;deepagents 作为门面聚合 middlewares/subagents/tools。
7. **协作层 agentteams**:[LeaderTeammateAgentTeam](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/LeaderTeammateAgentTeam.java)→[TeamAgent](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/agent/TeamAgent.java#L81)→[TeamBackend](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/tools/TeamBackend.java)→[CoordinationKernel](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/agent/coordination/CoordinationKernel.java#L30)+7 handlers。
8. **演化层 agentevolving/autoharness**:Trainer 基于 RL 优化 agent;AutoHarnessOrchestrator 提供端到端自动改码编排。
9. **扩展层 extensions/spi**:SPI 工厂([KVStoreFactory](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/spi/store/KVStoreFactory.java)、[VectorStoreFactory](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/spi/store/vector/VectorStoreFactory.java)、[ObjectStorageFactory](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/spi/store/object/ObjectStorageFactory.java))经 `ServiceLoader` 加载存储后端;extensions 提供沙箱、检查点、上下文演化与厂商适配。

层间依赖方向严格自底向上:上层只能依赖下层抽象,不得反向引用。这种约束使每一层可独立替换——例如将向量存储从 Milvus 切换到 Chroma 只需更换 SPI 实现,不影响引擎层与 agent 层;又如将单 agent 从 ReActAgent 升级为 WorkflowAgent,无需改动资源层与会话层。Runner 单例与 TagMgr 作为横切支柱,被第 2 至第 8 层共享访问,负责资源生命周期与多租户隔离。

## 二、十大核心设计模式

下表汇总贯穿全项目的十大设计模式,每条均给出实现位置与要点(详细实现见对应模块文档)。

| 序号 | 模式 | 实现要点 | 代码位置 |
| --- | --- | --- | --- |
| 1 | Card/Config 分离 | [BaseCard](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/common/schema/BaseCard.java#L17)(AgentCard/ToolCard/WorkflowCard/SysOperationCard)声明性元数据 vs 运行时 Config;[ResourceMgr.idToCard](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/runner/resourcemanager/ResourceMgr.java#L74) 单独维护元数据 | core/common/schema、core/runner/resourcemanager |
| 2 | Pregel BSP 超步 | [PregelLoop.doRunStep](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/graph/pregel/PregelLoop.java#L169) 三阶段(确定活跃节点→并行执行→汇总消息刷新通道);[TaskExecutorPool.waitAll](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/graph/pregel/TaskExecutorPool.java#L104) 作 BSP 屏障;虚拟线程池 | core/graph/pregel |
| 3 | Runner 单例 | [GLOBAL_RUNNER](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/runner/Runner.java#L44) 进程级;[ResourceMgr](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/runner/resourcemanager/ResourceMgr.java#L52) 7 类资源;[TagMgr](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/runner/resourcemanager/ResourceMgr.java#L67) 多租户隔离 | core/runner |
| 4 | Rails 回调 | [DeepAgentRail](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/DeepAgentRail.java#L14)(priority 排序,init/uninit 生命周期),before/after_model_call/before/after_tool_call 钩子;基类 [AgentRail](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/rail/AgentRail.java#L49) | harness/rails、core/singleagent/rail |
| 5 | TaskLoop 四元组 | [TaskLoopController](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/task_loop/TaskLoopController.java#L17)(状态机)+TaskLoopEventHandler(事件桥)+[CoreTaskLoopEventExecutor](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/task_loop/CoreTaskLoopEventExecutor.java)(执行器)+[LoopCoordinator](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/task_loop/LoopCoordinator.java)(停止协调);EventQueue+TaskScheduler 异步驱动 | harness/task_loop |
| 6 | 中断恢复三层 | [Checkpointer](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/session/checkpointer/Checkpointer.java#L24)(会话级)→[PregelLoop GraphStoreState](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/graph/pregel/PregelLoop.java#L83) 快照→[ReActAgent ToolInterruptionState](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/agents/ReActAgent.java#L737) HITL | core/session、core/graph/pregel、core/singleagent |
| 7 | TeamAgent 单实现双角色 | [TeamAgent](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/agent/TeamAgent.java#L81) 由 [TeamRole](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/schema/team/TeamRole.java) 切换 Leader/Teammate;[TeamBackend](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/tools/TeamBackend.java) 共享 DB 单例 | agentteams |
| 8 | CoordinatorLoop/EventDispatcher 职责分离 | [CoordinationKernel](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/agent/coordination/CoordinationKernel.java#L30) 只唤醒+轮询,7 handlers(AgentLifecycle/Member/Message/StaleTask/TaskBoard/TeamCompletion/Workflow)做业务 | agentteams/agent/coordination |
| 9 | SPI 工厂 | [KVStoreFactory](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/spi/store/KVStoreFactory.java)/[VectorStoreFactory](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/spi/store/vector/VectorStoreFactory.java)/[ObjectStorageFactory](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/spi/store/object/ObjectStorageFactory.java)(`ServiceLoader`+编程式注册,`ConcurrentHashMap` 注册表) | spi/store |
| 10 | Mixin 组合 | [JiuwenBoxProviderMixin](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/extensions/sys_operation/sandbox/providers/jiuwenbox/JiuwenBoxProviderMixin.java) 持有 endpoint/config/client 被三 Provider 复用(组合优于继承) | extensions/sys_operation/sandbox |

上述十种模式并非孤立存在,而是按层组合:Card/Config 分离(模式 1)贯穿基础设施到协作层,为所有资源提供统一身份;Pregel 超步(模式 2)既驱动工作流也支撑团队协作的任务分发;Runner 单例(模式 3)与 TagMgr(模式 3)为多租户资源治理奠基;Rails(模式 4)与 TaskLoop(模式 5)在框架层互补,分别提供调用级与循环级控制;中断恢复三层(模式 6)将 Checkpointer、Pregel、ReActAgent 串联成长时任务的安全网;TeamAgent 双角色(模式 7)与职责分离(模式 8)共同保证协作层的简洁与可演进;SPI 工厂(模式 9)与 Mixin 组合(模式 10)则在扩展层以可插拔与组合优于继承的方式落地厂商适配。

## 三、运行时数据流

下面按单 agent、工作流、多 agent 团队三条典型链路,展示从入口到落盘的完整调用过程。三条链路共享会话层与资源层,差异在于中间的执行引擎。

阅读时请注意每条链路中 Checkpointer 的介入时机:它既是中断恢复的基础,也是长时任务可靠性的关键保障。

### 1. ReActAgent 单 agent 调用链

`Runner.runAgent` 是统一入口,其内部按"前置保存→执行→后置保存"编排:

1. `Runner.runAgent` → `prepareAgent` + [AgentSessionApi.preRun](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/session/AgentSessionApi.java#L330)(经 Checkpointer `preAgentExecute` 落盘会话级快照)。
2. [ReActAgent.invoke](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/agents/ReActAgent.java#L694):先 [loadInterruptionState](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/agents/ReActAgent.java#L737) 判断是否恢复 HITL;随后进入循环 [callModel](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/agents/ReActAgent.java#L314)→[executeToolCall](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/agents/ReActAgent.java#L547)→观察,遇工具中断则写 `ToolInterruptionState` 并抛出,等用户恢复。
3. [AgentSessionApi.postRun](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/session/AgentSessionApi.java#L344)(经 Checkpointer `save` 落盘最终状态)。

> 三层中断恢复要点:
> - **会话级**:[Checkpointer](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/session/checkpointer/Checkpointer.java#L24) 在 preRun/postRun 落盘 agent 会话快照,进程崩溃后可恢复整段会话。
> - **图级**:[PregelLoop](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/graph/pregel/PregelLoop.java#L27) 在每个超步落盘 [GraphStoreState](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/graph/pregel/PregelLoop.java#L83),恢复时从断点超步继续,不重放已完成节点。
> - **Agent 级**:[ReActAgent](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/agents/ReActAgent.java#L737) 以 `ToolInterruptionState` 暂存工具调用现场,实现人机交互(HITL)暂停/恢复。

### 2. Workflow 调用链

[Workflow.invoke](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/workflow/Workflow.java#L668) 委托 Pregel 超步循环:

1. `Workflow.invoke` → [Pregel.run](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/graph/pregel/Pregel.java#L73)。
2. [PregelLoop](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/graph/pregel/PregelLoop.java#L27):先尝试从 [GraphStoreState](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/graph/pregel/PregelLoop.java#L83) 恢复断点;随后循环 [doRunStep](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/graph/pregel/PregelLoop.java#L169)。
3. `doRunStep` 三阶段:确定活跃节点→[TaskExecutorPool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/graph/pregel/TaskExecutorPool.java#L33) 并行执行→汇总消息刷新通道,以 [waitAll](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/graph/pregel/TaskExecutorPool.java#L104) 作 BSP 屏障;出错时落盘 [errorState 快照](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/graph/pregel/PregelLoop.java#L265)。

### 3. TeamAgent 协作调用链

多 agent 团队由声明式入口启动,经内核唤醒分发到 7 个场景 handler:

1. [LeaderTeammateAgentTeam](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/LeaderTeammateAgentTeam.java) 声明团队规格 → [TeamAgent](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/agent/TeamAgent.java#L81) 按 [TeamRole](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/schema/team/TeamRole.java) 实例化 Leader 与 Teammate。
2. Leader 通过 [TeamBackend](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/tools/TeamBackend.java)(共享 DB 单例)派发任务,Teammate 消费并产出。
3. [CoordinationKernel](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/agent/coordination/CoordinationKernel.java#L30) 仅负责唤醒与周期轮询,事件经 `dispatch` 分发到 7 个 handler(AgentLifecycle/Member/Message/StaleTask/TaskBoard/TeamCompletion/Workflow)处理具体业务。
4. Leader 与 Teammate 的产出会回流到 [TeamBackend](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/tools/TeamBackend.java),由 TeamCompletionHandler 判定团队是否完成并收尾。

> 设计要点:TeamAgent 单类通过 `TeamRole` 切换 Leader/Teammate 角色,避免类爆炸;CoordinationKernel 与 handlers 的职责分离保证唤醒逻辑稳定、业务可独立演进。

三条链路揭示了架构的复用策略:会话层(Checkpointer)与资源层(Runner/ResourceMgr)是所有链路的公共底座,执行引擎则按场景分叉——单 agent 走 ReActAgent 循环,工作流走 Pregel 超步,多 agent 走 CoordinationKernel 分发。这种"公共底座 + 场景引擎"的结构,使新增执行模式无需改动会话与资源治理。

## 四、关键概念

以下五个概念贯穿多个分层,是理解实现细节的钥匙。

### 1. Card / Config 分离

Card([BaseCard](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/common/schema/BaseCard.java#L17) 子类,含 AgentCard/ToolCard/WorkflowCard/SysOperationCard)定义身份与元数据(描述、Schema、标签),是不可变声明;Config 持有运行时行为(模型客户端、工具集、Rails)。两者分离使同一 Card 可绑定不同 Config 复用,[ResourceMgr.idToCard](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/runner/resourcemanager/ResourceMgr.java#L74) 以稳定 ID 单独维护元数据表,运行时通过 ID 反查 Card 完成鉴权与路由。这条原则在 [AGENTS.md](file:///D:/jiuwen/main/agent-core-java/AGENTS.md) 中被明确为不可破坏的架构约束。

### 2. Pregel 超步模型

借鉴 BSP(Bulk Synchronous Parallel)模型,以"超步(superstep)"为执行单位。[PregelLoop.doRunStep](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/graph/pregel/PregelLoop.java#L169) 在每个超步内:先确定活跃节点,再经 [TaskExecutorPool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/graph/pregel/TaskExecutorPool.java#L33)(虚拟线程池)并行执行节点任务,超步末以 [waitAll](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/graph/pregel/TaskExecutorPool.java#L104) 屏障汇总消息并刷新 Channel。超步间的 [GraphStoreState](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/graph/pregel/PregelLoop.java#L83) 快照保证了可恢复性与执行确定性。

### 3. Rails 回调链

[AgentRail](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/rail/AgentRail.java#L49) 与 [DeepAgentRail](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/DeepAgentRail.java#L14) 为 LLM/工具调用提供 before/after 回调钩子。Rails 按 [priority()](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/DeepAgentRail.java#L21) 排序串联,[init/uninit](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/DeepAgentRail.java#L42) 管理生命周期,用于实现安全护栏、审计、重试、上下文注入等横切关注点,避免侵入 agent 主循环。

### 4. TaskLoop 四元组

harness 的四元组由 [TaskLoopController](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/task_loop/TaskLoopController.java#L17)(状态机,基于 `ConcurrentMap<SessionState>`)、TaskLoopEventHandler(事件桥)、[CoreTaskLoopEventExecutor](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/task_loop/CoreTaskLoopEventExecutor.java)(执行器)与 [LoopCoordinator](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/task_loop/LoopCoordinator.java)(停止协调)组成,由 EventQueue+TaskScheduler 异步驱动,实现编码 agent 的"规划→执行→自检"循环,与 Rails 互补提供循环级控制。

### 5. SPI 可插拔扩展

`spi/store` 下以 `ServiceLoader` + 编程式注册双重机制加载 KV/向量/对象存储实现,注册表使用 `ConcurrentHashMap`,兼顾可插拔与线程安全。[KVStoreFactory](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/spi/store/KVStoreFactory.java)/[VectorStoreFactory](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/spi/store/vector/VectorStoreFactory.java)/[ObjectStorageFactory](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/spi/store/object/ObjectStorageFactory.java) 是三大工厂入口,extensions 包则提供具体后端实现(Milvus/Chroma/pgvector/Redis 等)。

## 五、与 Python agent-core 对照

agent-core-java 与 Python 版 `agent-core` 在概念层面对齐,实现层面按 Java 生态重新落地。源码注释多处 "Mirrors Python's ..." 即体现这种对照。

| 维度 | Python agent-core | agent-core-java |
| --- | --- | --- |
| 语言/运行时 | Python | Java 17(虚拟线程) |
| 元数据 | AgentCard 等 | [BaseCard](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/common/schema/BaseCard.java#L17) 子类(Card/Config 分离) |
| 图执行 | Pregel | [Pregel/PregelLoop](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/graph/pregel/Pregel.java#L24) BSP |
| 中断恢复 | Checkpointer/HITL | 三层:Checkpointer→PregelLoop→ReActAgent |
| 单 agent | ReActAgent | [ReActAgent](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/agents/ReActAgent.java#L77) |
| 多 agent | AgentTeam | [LeaderTeammateAgentTeam](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/LeaderTeammateAgentTeam.java) |
| 扩展机制 | 插件 | SPI(`ServiceLoader`)+ extensions |
| 序列化 | pydantic | Jackson(单例 ObjectMapper) |
| 响应式 | asyncio | Reactor 3.6.2 |

对照可知,Java 版并非逐行翻译,而是在保留概念一致性的前提下,用 Java 17 的语言特性与生态组件重新表达:Python 的 `asyncio` 并发被 Reactor + 虚拟线程替代;Python 的 `pydantic` 模型校验被 Jackson 单例 ObjectMapper + JSON Schema 生成器替代;Python 的插件机制被标准 SPI(`ServiceLoader`)+ 编程式注册替代。这种"概念对齐、实现重落地"的策略,使 Java 版既能复用 Python 版的设计经验,又能融入 JVM 生态的治理与可观测体系。

## 六、小结

agent-core-java 以九层分层架构与十大设计模式构建了从基础设施到演化能力的完整栈:Card/Config 分离保证声明与行为解耦,Pregel BSP 统一驱动工作流与协作,Rails/TaskLoop 提供横切与循环控制,三层中断恢复保障长时任务健壮性,Runner 单例 + TagMgr 支撑多租户资源治理,SPI + extensions 实现可插拔扩展。后续文档将逐层深入:[03-core-module](03-core-module.md) 详解核心运行时,[04-harness-and-deepagents-module](04-harness-and-deepagents-module.md) 详解框架层,[05-agentteams-module](05-agentteams-module.md) 详解协作层,[06-agentevolving-and-autoharness-module](06-agentevolving-and-autoharness-module.md) 详解演化层,[07-extensions-and-spi-module](07-extensions-and-spi-module.md) 详解扩展层,[09-dependencies](09-dependencies.md) 详解依赖治理,[10-running-guide](10-running-guide.md) 详解运行配置。
