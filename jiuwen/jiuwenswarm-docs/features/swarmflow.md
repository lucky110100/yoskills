# SwarmFlow 工作流编排

> 交叉引用: [01-项目概述](../01-project-overview.md) | [02-整体架构](../02-overall-architecture.md) | [03-agents与swarm](../03-agents-and-swarm-module.md) | [特性索引](README.md)

## 一、能力概述

SwarmFlow 是 JiuwenSwarm 在 Swarm 模式之上的工作流编排能力。用户用自然语言描述目标后，Leader 不再一次性产出全部结果，而是把请求分解为多阶段 workflow：每个阶段（phase）分派给一个 Agent，阶段之间通过状态记忆无缝交接——前一阶段的产出作为后一阶段的输入，整个流程可被实时观察、暂停与干预。

它的核心价值是"有状态算子 + 人在回路"。与一次性的 prompt 链不同，SwarmFlow 的每个 workflow 节点都带 `correlation_id`（`{phase}:{label}:{turn}`，跨 resume 稳定）与状态记忆：当流程推进到某个节点时，Leader 可暂停（pause）等待真人审批、纠正或接管，真人回复后流程从该节点恢复，且历史不丢。这把"AI 自主推进"与"人控质量门"结合在一条流水线里。

定位上，SwarmFlow 是 [agents 模块](../03-agents-and-swarm-module.md) 协作运行时的"编排视图"：装配侧仍由 `swarm/` 完成，运行侧由 `TeamManager.interact` 驱动 Leader，但额外叠加了 workflow 状态聚合、`workflow.updated` 增量事件流与 human_session 人在回路机制。它通过 `/swarmflow on` 开关启用，并在 TUI 提供 workflow 节点检视键（P 检视提示、Q/A 查看问题与回复）。

## 二、关键类与函数

路径前缀：`D:/jiuwen/main/jiuwenswarm/jiuwenswarm/`

| 类/函数 | 文件位置 | 说明 |
| --- | --- | --- |
| TeamManager.interact | [team_manager.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/team/team_manager.py#L1232) | Leader 协作入口：恢复 runtime → 取 active team → 推进 workflow |
| WorkflowMonitorHandler | [workflow_monitor_handler.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/team/handlers/workflow_monitor_handler.py#L27) | 桥接 workflow 进度事件到 TUI：消费 workflow_events() → 聚合 → 推 workflow.updated |
| WorkflowProgress | [workflow_state.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/team/handlers/workflow_state.py#L40) | 单条 workflow 进度事件载荷（节点类型/状态/turn） |
| WorkflowRunState | [workflow_state.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/team/handlers/workflow_state.py#L169) | 单个 run 的聚合状态，累积节点树供前端渲染 |
| SwarmflowReplyParams | [swarmflow_reply.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/schema/swarmflow_reply.py#L14) | chat.swarmflow_reply 参数契约：session_id/run_id/correlation_id/answer |
| planSwarmflowToggle | [swarmflow.ts](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/channels/tui/frontend/src/core/commands/builtins/swarmflow.ts#L25) | /swarmflow on|off 切换规划器：决定写配置与切换 team 模式 |
| update_swarmflow_enabled_in_config | [config.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/config.py#L1574) | 把 enable_swarmflow 写入 config.yaml（modes.team.jiuwen_team） |

## 三、实现机制

### 3.1 workflow 分解与阶段交接

Leader 在 `TeamManager.interact` 推进时，把请求分解为多阶段 workflow。每个阶段是一个工作流节点，节点类型可为 `agent` / `agent_session` / `human` / `human_session`：`agent*` 由智能体执行，`human*` 暂停等待真人。阶段间通过 `correlation_id`（`{phase}:{label}:{turn}`）建立稳定的关联，前一阶段产出喂给后一阶段，形成无缝交接。`correlation_id` 跨 resume 稳定，保证多次暂停恢复后历史不串。

### 3.2 增量事件聚合链路

workflow 推进产生 `WorkflowProgress` 原始事件（节点类型/状态/turn），由 `TeamMonitor.workflow_events()` 输出。`WorkflowMonitorHandler` 消费这些原始 `EventMessage`，按 run_id 在 `WorkflowRunState` 实例中累积节点树，再把增量 delta dict 推入内部 `asyncio.Queue`，经 `events()` 异步迭代器产出 `workflow.updated` 事件供前端消费。这条链路保证"原始事件 → 聚合状态 → 前端增量"三段式，单事件异常不会终止整个收集循环（每个事件独立 try/except）。

```text
Leader 推理产出 workflow 节点
  → TeamMonitor.workflow_events() 输出 WorkflowProgress 原始事件
  → WorkflowMonitorHandler._process_event
      → 更新 WorkflowRunState(按 run_id 累积节点树)
      → 推增量 delta 到 asyncio.Queue
  → events() 产出 workflow.updated → 前端增量渲染
```

### 3.3 人在回路机制

人在回路由 `/swarmflow on` 开启：`planSwarmflowToggle` 决定是否写配置（`config.set enable_swarmflow=true`）并切换到 team 模式，`update_swarmflow_enabled_in_config` 把开关落盘到 `config.yaml`。开启后，workflow 中的 `human_session` 节点会暂停在真人输入上。

当流程停在 human_session 节点时，真人可经 TUI 检视节点：P 键查看节点提示（prompt），对 human 节点 Q 键查看问题（human_prompt）、A 键回复（human_reply）。回复经标准三层路由链（TUI 空壳 ack → message_handler 转发 → process_message 分派）到达 `handle_swarmflow_reply`，由其构造 `HumanAgentMessage(target="swarmflow:<run_id>:<corr>")` 交 `TeamManager.interact` 走 agent-core 薄路由恢复流程。`SwarmflowReplyParams` 定义了这套入站参数契约：`run_id` 构造 run-scoped reply topic 使并发 run 互不串扰，`correlation_id` 定位具体人机轮次，`answer` 携带真人回复正文。基于状态记忆，恢复后流程从原节点继续，历史不丢。

### 3.4 状态记忆与并发 run 隔离

SwarmFlow 的"有状态"体现在两个维度。第一是节点级状态记忆：每个 `human_session` 节点的 `correlation_id`（`{phase}:{label}:{turn}`）跨 resume 稳定，使多次暂停恢复后人机轮次不会错位——`correlation_id` 的 `turn` 段是全局 session turn 索引（后端历史长度），保证同一节点在不同恢复轮次里能被准确归因。第二是 run 级隔离：`run_id` 作为 reply topic 的作用域，使同一 session 内并发的多个 workflow run 互不串扰，真人回复只会路由到对应的 run 而非其他 run。

```text
并发 run 隔离链路：
  run-A 的 human_session 节点暂停
  → SwarmflowReplyParams.run_id = "run-A"
  → handle_swarmflow_reply 构造 HumanAgentMessage(target="swarmflow:run-A:<corr>")
  → 只恢复 run-A 的该节点，不影响 run-B
```

`WorkflowRunState` 在 `WorkflowMonitorHandler` 内按 run_id 维护一个 dict，每个 run 独立累积节点树。即使两个 run 同时推进，前端的增量渲染也会按 run 分组展示，避免节点树混淆。这条隔离边界是 SwarmFlow 支持并发 workflow 的前提——否则一个 run 的暂停会阻塞另一个 run 的恢复。

### 3.5 三层路由链

真人回复从 TUI 到恢复流程要经三层路由，每层职责单一、可独立测试：

| 层级 | 职责 | 关键动作 |
| --- | --- | --- |
| TUI 空壳 ack | 立即回 ack，不阻塞前端 | 采集 SwarmflowReplyParams |
| message_handler 转发 | 把参数转发到后端 | 透传 session_id/run_id/correlation_id/answer |
| process_message 分派 | 路由到 handle_swarmflow_reply | 构造 HumanAgentMessage 交 TeamManager.interact |

三层分离的好处是：TUI 不必等待后端处理即可响应（避免卡顿），转发层只做透传不做业务，业务逻辑集中在 `handle_swarmflow_reply`。这使得回复链路可被单独测试，也便于在非 TUI 通道（如 Web/IM）复用同一套参数契约。

## 四、调用示例

### 4.1 开启 SwarmFlow（TUI 端）

```text
/swarmflow on
```

`planSwarmflowToggle` 据此调用 `config.set` 写入 `enable_swarmflow=true`，并切换到 team 模式。下一次 workflow run 即启用人在回路。

### 4.2 后端回复路由（参数契约）

```python
from jiuwenswarm.common.schema.swarmflow_reply import SwarmflowReplyParams

reply: SwarmflowReplyParams = {
    "session_id": "sess-001",       # 团队 session_id，定位 team runtime
    "team_name": "review-squad",    # 仅日志/调试，handler 不消费
    "run_id": "run-42",             # workflow run id，构造 run-scoped topic
    "correlation_id": "review:pr:0",  # {phase}:{label}:{turn}，跨 resume 稳定
    "answer": "同意方案 A，但补一份单元测试",
}
# → handle_swarmflow_reply 构造 HumanAgentMessage(target="swarmflow:run-42:review:pr:0")
# → TeamManager.interact 恢复该 human_session 节点
```

### 4.3 前端消费增量事件（示意）

```python
from jiuwenswarm.agents.harness.team.handlers.workflow_monitor_handler import (
    WorkflowMonitorHandler,
)

handler = WorkflowMonitorHandler(monitor=team_monitor, session_id="sess-001", channel_id="feishu")
async for event in handler.events():          # workflow.updated 增量
    runs: dict = event["runs"]                # WorkflowRunState 聚合后的节点树
    for run_id, state in runs.items():
        print(run_id, state.nodes)            # 前端据此增量渲染 workflow 节点
```

### 4.4 切换规划矩阵

`planSwarmflowToggle` 是纯函数，把"当前是否开启 + 当前 mode + 目标 on/off"映射为一组动作，便于测试与可预测：

| 当前状态 | 当前 mode | 目标 | writeConfig | switchToTeam |
| --- | --- | --- | --- | --- |
| 已开 | team | off | 是 | 否 |
| 已关 | 非 team | on | 是 | 是（切到 team） |
| 已开 | team | on | 否 | 否（无变化） |
| 已关 | team | on | 是 | 否 |

切换只在"目标态与当前态不一致"时写配置；若已开启但不在 team 模式，则仅切换模式不重写配置。这一矩阵使 `/swarmflow` 的行为完全可预测，避免重复写盘或状态漂移。

## 五、业界对比

| 能力维度 | JiuwenSwarm(SwarmFlow) | LangGraph | Temporal | Dify |
| --- | --- | --- | --- | --- |
| 编排方式 | 自然语言 → Leader 分解多阶段 workflow | 显式 stateful graph 节点/边 | 代码定义 workflow + activity | 可视化 workflow 拖拽 |
| 人在回路 | human_session 节点暂停 + /swarmflow on + TUI Q/A 回复 | interrupt 节点 | 信号/等待信号 | 人工节点 |
| 状态记忆 | correlation_id 跨 resume 稳定 + WorkflowRunState 聚合 | checkpoint state | 持久化事件溯源 | 节点变量 |
| 阶段交接 | correlation_id 关联 + 前阶段产出喂后阶段 | 边的 state 传递 | activity 间序列化 | 变量引用 |
| 增量渲染 | workflow.updated 增量事件流 | 节点级状态 | 事件流 | 节点状态 |

SwarmFlow 的差异化在于"自然语言分解 + 有状态算子 + 人在回路一体化"：它不要求用户预先画图（区别于 LangGraph/Dify），也不要求代码定义流程（区别于 Temporal），而是让 Leader 把自然语言目标动态分解为可暂停、可恢复、可人控的多阶段 workflow，并通过 `correlation_id` + `WorkflowRunState` 保证状态记忆与阶段交接不丢。

## 六、小结

1. SwarmFlow 把自然语言请求分解为多阶段 workflow，每阶段分派 Agent，阶段间经 `correlation_id`（`{phase}:{label}:{turn}`）关联并交接，跨 resume 稳定不串。
2. 人在回路由 `/swarmflow on` 开启（`planSwarmflowToggle` 写配置并切换 team 模式），workflow 的 `human_session` 节点暂停等待真人，TUI P/Q/A 键检视节点与回复。
3. 增量事件链路为"WorkflowProgress 原始事件 → WorkflowMonitorHandler 聚合到 WorkflowRunState → workflow.updated 增量广播"，单事件异常不阻断整条流。
4. 真人回复经三层路由链到 `handle_swarmflow_reply`，构造 `HumanAgentMessage(target="swarmflow:<run_id>:<corr>")` 交 `TeamManager.interact` 恢复流程，`SwarmflowReplyParams` 是其入站参数契约。
5. 相对竞品，SwarmFlow 以"自然语言动态分解 + 有状态算子 + 人在回路一体化"形成差异化，无需预先画图或写流程代码。
6. 切换规划矩阵（`planSwarmflowToggle`）使 `/swarmflow` 行为完全可预测：只在目标态与当前态不一致时写配置，避免重复写盘与状态漂移。
