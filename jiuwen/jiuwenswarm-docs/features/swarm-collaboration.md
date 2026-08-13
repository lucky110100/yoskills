# Swarm 多智能体协作

> 交叉引用: [01-项目概述](../01-project-overview.md) | [02-整体架构](../02-overall-architecture.md) | [03-agents与swarm](../03-agents-and-swarm-module.md) | [特性索引](README.md)

## 一、能力概述

Swarm 多智能体协作是 JiuwenSwarm 区别于单 agent 编码助手的核心能力。在 Swarm 模式下，用户只需用自然语言描述目标，Leader 会自动把任务分解为可执行子任务、按需组装团队（build_team / create_task / spawn_teammate），并协调多个 Teammate 分工推进；成员之间通过消息（send_message）动态协商，结果再回交 Leader 审核聚合。整个过程不需要人工预先定义角色与流程。

它的价值在于把"群体智能"从手写流程图里解放出来：角色能力在装配期就以 rails/tools 形式固化（Leader 持团队级能力、Teammate 持成员级能力），运行时只做推理与调度，因此协作边界清晰、不会越权。同时技能可随用演进，团队技能库与成员技能库会不断扩充，形成正反馈。

定位上，Swarm 协作是 [agents 模块](../03-agents-and-swarm-module.md) 的运行时体现：声明侧由 `swarm/` 装配，执行侧由 `harness/team/` 驱动，分布式场景经 pyzmq transport 跨进程、跨机部署，使 Leader 与 Teammate 可分别落在不同进程甚至不同物理机上。

## 二、关键类与函数

路径前缀：`D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/`

| 类/函数 | 文件位置 | 说明 |
| --- | --- | --- |
| enrich_team_spec_for_swarm | [assembly.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/assembly.py#L56) | Swarm 装配唯一入口：注册 provider、建 SwarmBuildContext、改写成员 spec |
| SwarmBuildContext | [context.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/context.py#L24) | 构造期环境载体，to_seed/from_seed 跨进程重建 |
| register_swarm_providers | [registry.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/registry.py#L166) | 幂等注册 swarm.* 能力 provider |
| build_member_deep_agent_spec | [config_specs.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/config_specs.py#L709) | 能力 spec 折叠到 base DeepAgentSpec |
| _role_evolution_rails | [config_specs.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/config_specs.py#L438) | leader 返回团队技能进化+创建 rail，teammate 返回成员进化 rail |
| TeamManager | [team_manager.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/team/team_manager.py#L221) | Team 生命周期管理器：TeamAgent/Monitor/事件流/rail 注册表 |
| TeamManager.interact | [team_manager.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/team/team_manager.py#L1232) | Leader 协作入口：恢复 runtime → 取 active team → Runner.interact_agent_team |
| is_distributed_mode | [distributed_runtime.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/team/distributed_runtime.py#L20) | 判断分布式模式（pyzmq 可用 + 配置开启） |
| runtime_role | [distributed_runtime.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/team/distributed_runtime.py#L31) | 解析运行时角色 leader/teammate |
| resolve_team_event | [event_types.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/team/event_types.py#L44) | SDK MonitorEventType → 前端事件字符串广播 |
| TeamEventCategory | [event_types.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/team/event_types.py#L16) | Team 事件大类枚举 |

## 三、实现机制

### 3.1 Swarm 装配时序

装配遵循"声明 → 派生 → 烘焙 → 实例化"四段式，以 `enrich_team_spec_for_swarm` 为唯一入口，所有后续构造都从这一步派生，避免散落副作用：

```text
请求(session/channel/mode/project_dir)
  → enrich_team_spec_for_swarm
      → register_swarm_providers(import provider → 填充 catalog → 幂等注册)
      → 构建 SwarmBuildContext(per-team/per-process 字段)
      → build_member_deep_agent_spec
            ├─ build_member_capability_specs(按 mode 分档构建 rails+tools)
            └─ _role_evolution_rails(按角色派生演进 rail)
      → context.to_seed() 序列化供接收侧重建
      → openjiuwen setup_agent → 可运行的 Leader/Teammate
```

关键点在于装配期"不预构造 DeepAgent"：provider 工厂只返回 spec 元素（rails/tools/subagents），逐元素 `.build()` 实例化交给 openjiuwen `setup_agent` 完成，使声明侧与实例化侧解耦。

### 3.2 Leader/Teammate 角色分工

角色能力在装配期就由 `_role_evolution_rails` 固化为不对称设计，保证"谁负责拆解、谁负责执行"的清晰边界：

| 角色 | 装配的能力 rail | 能力范围 |
| --- | --- | --- |
| Leader | TEAM_SKILL_EVOLUTION / TEAM_SKILL_CREATE / SYMPHONY_TOOLKIT | 团队级技能进化、创建新成员、团队编排 |
| Teammate | MEMBER_SKILL_EVOLUTION / TEAM_PERMISSION | 成员级技能进化、权限受限提交 |

演进权限的不对称必须在实例化前确定，避免运行时越权。这也是 Swarm 区别于普通多 agent 编排的关键。

### 3.3 分布式跨进程协作

分布式场景下，`is_distributed_mode` 依赖 pyzmq 可用性与配置开关判断是否走分布式路径，`runtime_role` 解析当前进程扮演 leader 还是 teammate。Teammate 进程经 pyzmq transport 与 Leader 通信，spawn 时通过 `remote_member_bootstrap` 把 claw 占位包注入远端，实现"声明在 Leader、执行在 Teammate"的跨进程协作。

跨进程一致重建的根本保证是 param/context/extras 三层边界：属性值随 spec 走（`RailSpec.params`，可序列化），环境值随 context 走（`SwarmBuildContext`，per-team/per-process），句柄由接收侧 `from_seed` 后重新绑定（`ctx.extras`，不可序列化）。`to_seed()` 只序列化前两类的可序列化部分，使 Leader 与 Teammate 进程环境一致。

### 3.4 mode 分档与能力叠加

`build_member_capability_specs` 按 `mode` 把成员能力分三档，使同一套装配流水线能服务不同场景：

| mode | 叠加能力 | 适用场景 |
| --- | --- | --- |
| team | 纯群体协作能力（rails + send_message 等） | 纯协作编排 |
| code.team | 叠加代码工程能力（CC prompt、plan approval、todo rail） | 代码工程型团队 |
| team.plan | 切换到计划模式提示 | 计划审批型任务 |

分档发生在装配期而非运行期，因此每个成员实例化后即拿到正确的 prompt 与工具集，运行时无需再判断 mode。`_RAIL_PARAM_BUILDERS` 这张"属性烘焙表"会把 config 派生的属性值（如技能白名单、plan 开关）统一投射进 `RailSpec.params`，使 rail 实例化时能拿到烘焙好的参数，而不必在 rail 内部重复派生逻辑。

### 3.5 装配侧与执行侧的环境一致

分布式协作的关键挑战是"声明在 Leader 进程、执行在 Teammate 进程"时如何保证环境一致。`SwarmBuildContext.to_seed()` 把构造期环境序列化为可传输的 seed，接收侧经 `_build_swarm_context_from_seed` 用本地 config + per-team trajectory 重建 context。重建遵循严格的三层边界：

| 类别 | 载体 | 含义 | 序列化 |
| --- | --- | --- | --- |
| 属性值 | RailSpec.params | config 派生，随 spec 走 | 可序列化 |
| 环境值 | SwarmBuildContext | 构造期一次性设定，per-team/per-process | 可序列化部分随 seed |
| 句柄 | ctx.extras | 运行时句柄（DB 连接、WS 句柄） | 不可序列化，接收侧重绑 |

这条边界决定了 `to_seed()` 只序列化前两类的可序列化部分，而句柄必须在 `from_seed` 后由接收侧重新绑定。这是分布式 Swarm 跨进程一致重建的根本保证，避免"声明侧与执行侧读到不同环境"的隐蔽 bug。

### 3.6 TeamMonitor 事件流

协作运行时由 `TeamManager.interact` 驱动，恢复 runtime 后取 active team，委托 Runner 的 `interact_agent_team` 推进 Leader。Leader 推理产出 build_team / create_task / spawn_teammate / send_message 等工具调用，TeamMonitor 产生 `MonitorEventType` 事件，经 `resolve_team_event` 映射为 `TeamEventCategory` 前端事件字符串广播，使前端可实时观察团队组建、任务派生、成员完成等进展。

```text
TeamManager.interact
  → Runner.interact_agent_team
      → Leader LLM 推理 + 工具调用
          ├─ build_team（构造/重组团队）
          ├─ create_task（拆解任务）
          ├─ spawn_teammate（派生成员，分布式经 remote_member_bootstrap 注入远端 claw）
          └─ send_message（群体通信）
  → TeamMonitor 产生 MonitorEventType 事件
  → resolve_team_event 映射为 TeamEventCategory
  → 前端事件字符串广播
```

## 四、调用示例

### 4.1 装配入口

```python
from jiuwenswarm.agents.swarm.assembly import enrich_team_spec_for_swarm

enrich_team_spec_for_swarm(
    spec,                           # openjiuwen TeamSpec
    session_id="sess-001",
    mode="team",                    # 或 "code.team" / "team.plan"
    project_dir="/workspace/proj",
    request_id="req-001",
    channel_id="feishu",
    request_metadata={"mode": "team"},
)
# 之后交 openjiuwen setup_agent(spec) 完成实例化
```

### 4.2 分布式角色判定

```python
from jiuwenswarm.agents.harness.team.distributed_runtime import (
    is_distributed_mode, runtime_role,
)

if is_distributed_mode():
    role = runtime_role()            # "leader" 或 "teammate"
    if role == "teammate":
        # 走 pyzmq transport，接收 spawn 指令
        ...
```

### 4.3 Team 协作入口

```python
from jiuwenswarm.agents.harness.team.team_manager import TeamManager

mgr = TeamManager(...)              # 由 bootstrap 注入 home
result = mgr.interact(
    message="帮我拆解并实现登录模块",
    session_id="sess-001",
    channel_id="feishu",
    user_id="u-001",
)
# Leader 推理 → build_team/create_task/spawn_teammate/send_message
# TeamMonitor 事件流经 resolve_team_event 广播到前端
```

## 五、业界对比

| 能力维度 | JiuwenSwarm | LangGraph | AutoGen | CrewAI |
| --- | --- | --- | --- | --- |
| 装配方式 | 纯声明式 Swarm 装配（config→spec→provider 实例化） | 图编排（节点/边显式连线） | GroupChat 对话驱动 | 角色 crew 声明 |
| Leader/Teammate | 显式角色分工，装配期固化不对称能力 | 无原生角色，由图节点承担 | 轮转 speaker，角色弱 | 角色字段声明，对称 |
| 分布式 | pyzmq transport，seed 重建 context | 无原生分布式 | 无原生分布式 | 无原生分布式 |
| 技能演进 | 团队级 + 成员级双层演进 rail | 不支持 | 不支持 | 不支持 |
| 序列化重建 | to_seed/from_seed 跨进程一致 | 无 | 无 | 无 |

JiuwenSwarm 的差异化在于"声明式装配 + 双层技能演进 + 分布式 seed 重建"三位一体：它既不把协作逻辑硬编码进图结构，也不把角色停留在对话层，而是把角色能力在装配期就固化为不对称的 rails/tools，并通过 seed 机制实现跨进程一致重建。

## 六、小结

1. Swarm 协作以 `enrich_team_spec_for_swarm` 为装配唯一入口，经 provider 注册 → SwarmBuildContext 构建 → 分档 spec 构建 → to_seed 序列化四段式完成实例化，声明侧与实例化侧解耦。
2. Leader/Teammate 角色能力在装配期由 `_role_evolution_rails` 固化为不对称：Leader 持团队级能力（进化/创建/编排），Teammate 持成员级能力（自进化/受限提交），边界清晰不越权。
3. 分布式场景经 pyzmq transport 跨进程通信，`is_distributed_mode`/`runtime_role` 判定角色，`remote_member_bootstrap` 注入远端 claw，实现"声明在 Leader、执行在 Teammate"。
4. param/context/extras 三层边界是分布式 Swarm 跨进程一致重建的根本保证：属性值随 spec 走，环境值随 context 走，句柄由接收侧重建。
5. TeamMonitor 事件流经 `resolve_team_event` 映射为 `TeamEventCategory` 广播，使前端可实时观察团队组建、任务派生、成员完成等协作进展。
