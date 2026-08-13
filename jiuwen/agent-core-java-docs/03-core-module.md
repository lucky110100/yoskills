# core 模块：图引擎、Runner、Session 与单代理

> 交叉引用：[01-project-overview](01-project-overview.md) | [02-overall-architecture](02-overall-architecture.md) | [04-harness-and-deepagents-module](04-harness-and-deepagents-module.md) | [09-dependencies](09-dependencies.md)

## 一、模块职责

`com.openjiuwen.core` 是 agent-core-java 的**引擎层**，为上层 harness / deepagents / agentteams 提供运行时基座。它向下对接 LLM、工具、存储等基础设施，向上暴露稳定的单代理与工作流执行入口。其职责可按子包划分为以下七块：

1. **图引擎（`core.graph` / `core.graph.pregel`）**：基于 Pregel 的 BSP（Bulk Synchronous Parallel）模型驱动有向图计算，支持节点并行执行、消息通道与状态快照。`Graph` 是图定义容器，`Pregel` 是引擎入口，`PregelLoop` 实现 BSP 三阶段超步循环。
2. **工作流（`core.workflow`）**：以组件编排的方式描述多步流程，`Workflow` 提供起点与组件挂载点，由 Runner 驱动执行。
3. **Runner（`core.runner`）**：进程级单例运行时，`Runner` 持有全局实例 `GLOBAL_RUNNER`，`RunnerImpl` 是默认实现，`ResourceMgr` 集中管理 7 类资源（agent/workflow/tool/model/sysOperation 等），并通过 `TagMgr` 实现多租户隔离。
4. **会话与中断恢复（`core.session`）**：`Session` 抽象运行会话，`Checkpointer` 负责执行前后的状态快照与恢复，`AgentSessionApi` 提供带 CAS 位掩码守卫的高阶 API。
5. **单代理（`core.singleagent`）**：`ReActAgent` 实现 Reasoning→Acting→Observation 循环，支持 Human-in-the-Loop（HITL）中断与恢复；`WorkflowAgent` 把工作流封装为可调用代理。
6. **应用层（`core.application` / `core.controller`）**：在单代理之上组合出面向场景的控制器，例如 `application/workflow/WorkflowAgent`。
7. **基础设施（`core.foundation`、`core.context`、`core.memory`、`core.security`、`core.sysop`）**：LLM 调用、工具注册、存储抽象、上下文与记忆管理、安全策略与系统操作的底层支撑。

core 模块对 Python `openjiuwen.core` 做了对等镜像，是 Java 端“可被 harness 直接复用”的最薄运行时。

## 二、关键类与函数

| 类 / 函数 | 文件位置 | 说明 |
| --- | --- | --- |
| [Graph](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/graph/Graph.java) | `core/graph/Graph.java` | 图定义容器，声明节点、边与起始节点 |
| [Pregel](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/graph/pregel/Pregel.java#L24) | `core/graph/pregel/Pregel.java` | 引擎入口；`run(PregelConfig)` 在 L73 驱动超步循环 |
| [PregelLoop](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/graph/pregel/PregelLoop.java#L27) | `core/graph/pregel/PregelLoop.java` | BSP 实现：`init` L79、`doRunStep` L169（三阶段：确定活跃节点 L179-187 → 并行执行 L210-219 → 汇总消息刷新 L223-227）、`saveStateOnError` L255 |
| [TaskExecutorPool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/graph/pregel/TaskExecutorPool.java#L33) | `core/graph/pregel/TaskExecutorPool.java` | 虚拟线程池：`submit` L79、`waitAll` L104（FIRST_EXCEPTION 语义）、`cancelAll` L231 |
| [ChannelManager](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/graph/pregel/ChannelManager.java) | `core/graph/pregel/ChannelManager.java` | 消息通道管理器：`bufferMessage` / `flush` / `getReadyNodes` / `restore` |
| [Store](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/graph/store/Store.java) | `core/graph/store/Store.java` | 图状态存储抽象：`save` / `get` / `delete`；`GraphStoreState` 为快照类型 |
| [Runner](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/runner/Runner.java#L43) | `core/runner/Runner.java` | 进程单例：`GLOBAL_RUNNER` L44、`resourceMgr` L61、`runWorkflow` L155、`runAgent` L218 |
| [RunnerImpl](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/runner/RunnerImpl.java#L63) | `core/runner/RunnerImpl.java` | 默认实现：`getResourceMgr` L120、`runWorkflow` L286、`runAgent` L359 |
| [ResourceMgr](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/runner/resourcemanager/ResourceMgr.java#L52) | `core/runner/resourcemanager/ResourceMgr.java` | 7 类资源管理：`addAgent` L134、`addWorkflow` L215、`addTool` L316、`addModel` L414、`addSysOperation` L573；`idToCard` Map L74；`TagMgr` L67 |
| [Result](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/runner/base/) / [Ok](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/runner/base/) / [Error](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/runner/base/) / [Tag](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/runner/base/) | `core/runner/base/` | 结果类型与租户标签 |
| [Session](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/session/Session.java#L20) | `core/session/Session.java` | 会话接口：`getSessionId` L27、`getState` L36、`updateState` L44 |
| [Checkpointer](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/session/checkpointer/Checkpointer.java#L24) | `core/session/checkpointer/Checkpointer.java` | 快照抽象：`preWorkflowExecute` L74、`postWorkflowExecute` L78、`preAgentExecute` L101、`postAgentExecute` L109、`graphStore` L134 |
| [AgentSessionApi](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/session/AgentSessionApi.java#L33) | `core/session/AgentSessionApi.java` | 高阶 API；L34-48 CAS 位掩码守卫，防并发状态漂移 |
| [Workflow](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/workflow/Workflow.java) | `core/workflow/Workflow.java` | `setStartComp` L127、`addWorkflowComp` L174 |
| ReActAgent（门面） | [ReActAgent.java](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/ReActAgent.java#L14)（门面）/ [ReActAgent.java](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/agents/ReActAgent.java#L77)（实现） | `callModel` L314、`executeToolCall` L547、`invoke` L694、`stream` L909；ReAct 循环 L784-839；HITL 中断 L823-830、`commitInterrupt` L1011-1038、恢复 L737-781 |
| [WorkflowAgent](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/application/workflow/WorkflowAgent.java) | `core/application/workflow/WorkflowAgent.java` | 将工作流封装为可调用代理 |
| [BaseCard](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/common/schema/BaseCard.java#L17) | `core/common/schema/BaseCard.java` | Card 根类：`getId` L56、`toolInfo` L116、`copy` L126 |
| [AgentCard](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/schema/AgentCard.java#L33) | `core/singleagent/schema/AgentCard.java` | `toolInfo` L92 |
| [legacy](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/legacy/) | `core/singleagent/legacy/` | 旧版兼容：`ControllerAgent` / `LegacyReActAgent` |

## 三、核心机制

### 3.1 Pregel BSP 三阶段超步

[Pregel](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/graph/pregel/Pregel.java#L24) 的 `run(PregelConfig)` 在 L73 创建并启动 [PregelLoop](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/graph/pregel/PregelLoop.java#L27)。每个超步（superstep）由 `doRunStep`（L169）执行三阶段：

1. **确定活跃节点（L179-187）**：依据上一轮消息与节点状态，过滤出本轮需要执行节点集合。
2. **并行执行（L210-219）**：通过 [TaskExecutorPool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/graph/pregel/TaskExecutorPool.java#L33) 的虚拟线程池 `submit`（L79）提交节点任务，`waitAll`（L104）以 `FIRST_EXCEPTION` 语义聚合结果——任一节点抛错即整体短路。
3. **汇总消息刷新（L223-227）**：[ChannelManager](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/graph/pregel/ChannelManager.java) `flush` 把节点产出消息投递到目标通道，并据此刷新下一轮活跃集。

任一阶段抛错会进入 `saveStateOnError`（L255）：把当前 [GraphStoreState](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/graph/store/Store.java) 快照写入 [Store](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/graph/store/Store.java)，便于断点续跑。

```
Pregel.run(PregelConfig)
  └─ PregelLoop.init(L79)            // 加载 GraphStoreState 恢复
     └─ while (superstep)
        ├─ determineActiveNodes (L179-187)
        ├─ TaskExecutorPool.submit → waitAll (L210-219)   // FIRST_EXCEPTION
        └─ ChannelManager.flush → refresh (L223-227)
        └─ on error → saveStateOnError (L255)
```

### 3.2 Card / Config 分离与 ResourceMgr

core 严格遵循 AGENTS.md 的 **Card/Config 分离**铁律：Card 定义身份与元数据（`AgentCard`、`ToolCard`、`WorkflowCard`、`SysOperationCard`），运行时行为属于 config / agent / manager / 资源实例。[ResourceMgr](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/runner/resourcemanager/ResourceMgr.java#L52) 内部用 `idToCard` Map（L74）按稳定 ID 索引 Card，`TagMgr`（L67）在 Card 之上叠加租户标签，使同一进程可承载多租户资源。注册方法对应 7 类资源：`addAgent` L134、`addWorkflow` L215、`addTool` L316、`addModel` L414、`addSysOperation` L573。

### 3.3 三层中断恢复

中断恢复贯穿三层，由下至上：

- **Checkpointer 层**（[Checkpointer](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/session/checkpointer/Checkpointer.java#L24)）：在 `preWorkflowExecute`（L74）/`postWorkflowExecute`（L78）与 `preAgentExecute`（L101）/`postAgentExecute`（L109）前后落快照，`graphStore`（L134）暴露底层图存储。
- **PregelLoop 层**：`saveStateOnError`（L255）保证单超步失败可重入。
- **ReActAgent 层**（[ReActAgent 实现](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/agents/ReActAgent.java#L77)）：HITL 中断发生在 L823-830，`commitInterrupt`（L1011-1038）把中断点写入会话状态，恢复路径在 L737-781 重入 ReAct 循环 L784-839（Reasoning→Acting→Observation）。

[AgentSessionApi](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/session/AgentSessionApi.java#L33) 在 L34-48 用 CAS 位掩码守卫状态迁移，避免并发请求把会话从“中断态”误改回“运行态”。

### 3.4 Runner 单例 + TagMgr 多租户

[Runner](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/runner/Runner.java#L43) 是进程级单例（`GLOBAL_RUNNER` L44），`RunnerImpl.runAgent`（L359）/`runWorkflow`（L286）是统一执行入口。`resourceMgr`（L61）共享全局状态，多租户隔离完全依赖 `TagMgr`：同一份 Card 在不同 Tag 下呈现不同可见集与配置，调用方需用稳定 ID 并注意测试隔离。

## 四、调用示例

```java
import com.openjiuwen.core.runner.Runner;
import com.openjiuwen.core.runner.RunnerImpl;
import com.openjiuwen.core.runner.base.Tag;
import com.openjiuwen.core.singleagent.ReActAgent;
import com.openjiuwen.core.singleagent.schema.AgentCard;

// 1. 获取进程单例 Runner
Runner runner = RunnerImpl.GLOBAL_RUNNER;

// 2. 注册 Agent Card（身份/元数据，与运行配置分离）
AgentCard card = AgentCard.builder()
        .id("react-agent-001")
        .name("demo-react-agent")
        .build();
runner.getResourceMgr().addAgent(card);

// 3. 用 Tag 隔离租户后拉起 ReActAgent
Tag tenant = Tag.of("tenant", "demo");
ReActAgent agent = runner.runAgent("react-agent-001", tenant);

// 4. 同步调用（内部走 PregelLoop 驱动 ReAct 循环）
String answer = agent.invoke("请用 bash 查看当前目录并总结文件结构");

// 5. 中断恢复：HITL 中断后 commitInterrupt，下次 invoke 从断点重入
//    agent.commitInterrupt(interruptResult);
```

工作流调用示例：

```java
import com.openjiuwen.core.workflow.Workflow;

Workflow workflow = new Workflow()
        .setStartComp(startComponent)        // L127
        .addWorkflowComp(secondComponent);   // L174

runner.runWorkflow(workflow, tenant);
```

## 五、与 Python agent-core 对照

| 维度 | Java | Python | 差异说明 |
| --- | --- | --- | --- |
| 图引擎 | [Pregel](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/graph/pregel/Pregel.java#L24) + [PregelLoop](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/graph/pregel/PregelLoop.java#L27) | `openjiuwen.core.graph` Pregel | BSP 三阶段语义一致；Java 用虚拟线程池 `TaskExecutorPool` 替代 Python 的 asyncio 并发 |
| 运行时单例 | [Runner](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/runner/Runner.java#L43) `GLOBAL_RUNNER` | `Runner` 单例 | 均进程级单例；Java 显式 `ResourceMgr` + `TagMgr` 实现多租户 |
| 单代理 | [ReActAgent](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/agents/ReActAgent.java#L77) | `react_agent` | ReAct 三段式循环对等；Java 额外提供门面 [ReActAgent](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/ReActAgent.java#L14) 与实现分离 |
| 会话快照 | [Checkpointer](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/session/checkpointer/Checkpointer.java#L24) | `checkpointer` | 抽象方法对等；Java 用 CAS 位掩码补强并发守卫 |
| 会话接口 | [Session](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/session/Session.java#L20) | `session` | `getSessionId` / `getState` / `updateState` 三方法对齐 |
| 资源管理 | [ResourceMgr](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/runner/resourcemanager/ResourceMgr.java#L52) 7 类资源 | Resource registry | Java 显式枚举 7 类资源，Card/Config 分离更严格 |
| 线程模型 | 虚拟线程（JDK 21）+ `FIRST_EXCEPTION` | asyncio 任务 | Java 借虚拟线程池实现高并发节点执行，异常短路语义一致 |

## 六、小结

core 模块是 agent-core-java 的“薄引擎”层：以 Pregel BSP 为图执行内核，以 Runner 单例 + TagMgr 提供多租户资源管理，以 Checkpointer / PregelLoop / ReActAgent 三层实现可中断恢复，并以 Card/Config 分离保持 API 稳定。它对 Python `openjiuwen.core` 做了对等镜像，使上层 harness、deepagents、agentteams 可以在统一的运行时基座上构建更高阶的编码代理与多代理团队。理解 core 的三阶段超步、CAS 守卫与 HITL 恢复，是阅读后续 harness 与 agentteams 模块的前置条件。
