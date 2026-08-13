# 03 agents 与 swarm 模块（智能体运行时与群体协作核心）

> 交叉引用: [01-项目概述](../01-project-overview.md) | [02-整体架构](../02-overall-architecture.md) | [05-server与cli](../05-server-and-cli-module.md) | [10-依赖关系](10-dependencies.md)

## 一、能力概述

`agents/` 是 JiuwenSwarm 的智能体运行时与 Swarm 群体协作核心。它在整个项目中处于"装配层 + 运行时"的双重位置：对下，它把 `config.yaml` 中的静态声明、请求环境（session/channel/mode）以及工作区根目录翻译成可运行的 Leader / Teammate；对上，它把 openjiuwen 框架下沉为基础设施，使平台层只负责声明式描述，而把"如何构造一个 agent / 一个 team"完全交给本模块。这一分层让 JiuwenSwarm 既能复用 openjiuwen 的 agent_teams 内核，又能在其之上叠加 Swarm 装配、技能演进、分布式协作等自有能力。

本模块内部又细分为两条主线：`swarm/` 负责纯声明式 team spec 装配——以 `enrich_team_spec_for_swarm` 为唯一入口，按 provider 机制把能力（rails / tools / subagents）逐元素挂装到成员 spec 上，再交给 openjiuwen 的 `setup_agent` 完成实例化；`harness/` 则按场景（common / code / work / claw / team）拆分能力组件，提供各 profile 下的 prompt 模板、计划审批 rail、todo 工具、记忆与协作运行时。两者通过 `SwarmBuildContext` 这一构造期环境载体进行数据交接。

在项目定位上，agents 模块是"群体智能"的承载者：它定义了 Leader 如何拆解任务、Teammate 如何被 spawn 与审核、技能如何在团队与成员两个层级演进、分布式场景如何经 pyzmq transport 跨进程通信。它使得 JiuwenSwarm 不只是一个单 agent 编码助手，而是一个可声明、可演进、可分布部署的群体协作系统。

## 二、关键类与函数

### 2.1 Swarm 声明式装配层

| 类/函数 | 文件位置 | 说明 |
| --- | --- | --- |
| enrich_team_spec_for_swarm | [assembly.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/assembly.py#L56) | Swarm 装配唯一入口：注册 provider、建 SwarmBuildContext、改写成员 spec、挂 build_context+seed |
| SwarmBuildContext | [context.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/context.py#L24) | 构造期环境载体，继承 openjiuwen BuildContext |
| SwarmBuildContext.to_seed | [context.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/context.py#L67) | 导出可序列化 seed，供接收侧重建 context |
| SwarmBuildContext.from_seed | [context.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/context.py#L96) | 从 seed 重建 context，恢复 per-team/per-member 字段 |
| register_swarm_providers | [registry.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/registry.py#L166) | 幂等注册：import provider 模块填充 catalog → register_from_catalog |
| _build_swarm_context_from_seed | [registry.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/registry.py#L151) | seed→context 工厂，接收侧用本地 config+per-team trajectory 重建 |
| build_member_deep_agent_spec | [config_specs.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/config_specs.py#L709) | 把能力 spec + code system prompt 折叠到 base DeepAgentSpec |
| build_member_capability_specs | [config_specs.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/config_specs.py#L585) | 按 mode（team/code.team/team.plan）分档构建成员 rails+tools specs |
| build_member_subagent_specs | [config_specs.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/config_specs.py#L666) | 构建 code 子 agent specs（explore/plan 常驻，code/browser 受 config 门控） |
| _role_evolution_rails | [config_specs.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/config_specs.py#L438) | leader 返回团队技能进化+创建 rail，teammate 返回成员技能进化 rail |
| _RAIL_PARAM_BUILDERS | [config_specs.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/config_specs.py#L358) | 属性烘焙表：把 config 派生属性投射进 RailSpec.params |

### 2.2 Swarm 能力 Provider 工厂

| 类/函数 | 文件位置 | 说明 |
| --- | --- | --- |
| MemberSkillToolkitInput | [skills.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/providers/skills.py#L133) | 成员技能工具栏 rail 的输入模型 |
| build_member_skill_toolkit | [skills.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/providers/skills.py#L167) | 成员技能工具栏 rail 构造器 |
| SkillToolkitInput | [tools.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/providers/tools.py#L413) | 白名单过滤后的技能发现/安装/卸载工具输入 |
| build_skill_toolkit | [tools.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/providers/tools.py#L437) | 技能发现/安装/卸载工具构造器 |
| build_code_agent | [code_subagents.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/providers/code_subagents.py#L93) | 复用主 agent 的 CodingMemoryRail 构造 code 子 agent |
| build_cron_tools | [runtime_tools.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/providers/runtime_tools.py#L75) | 按 member_card_id 构建每成员 cron 工具 |
| builtin_rails provider | [builtin_rails.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/providers/builtin_rails.py#L37) | 内置 rail provider 注册入口 |
| evolution_rails provider | [evolution_rails.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/providers/evolution_rails.py#L52) | 团队/成员技能演进 rail provider |

### 2.3 Team 协作运行时

| 类/函数 | 文件位置 | 说明 |
| --- | --- | --- |
| TeamManager | [team_manager.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/team/team_manager.py#L221) | Team 生命周期管理器：TeamAgent/Monitor/stream_tasks/rail 注册表/evolution watcher |
| TeamManager.interact | [team_manager.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/team/team_manager.py#L1232) | Leader 协作入口：恢复 runtime → 取 active team → Runner.interact_agent_team |
| TeamRailMountContext | [team_manager.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/team/team_manager.py#L186) | 热重载 rail 上下文 |
| is_distributed_mode | [distributed_runtime.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/team/distributed_runtime.py#L20) | 判断分布式模式（pyzmq 可用 + 配置开启） |
| runtime_role | [distributed_runtime.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/team/distributed_runtime.py#L31) | 解析运行时角色（leader/teammate） |
| TeamEventCategory | [event_types.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/team/event_types.py#L16) | Team 事件大类枚举 |
| resolve_team_event | [event_types.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/team/event_types.py#L44) | SDK MonitorEventType → 前端事件字符串 |
| configure_agent_teams_home | [bootstrap.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/team/bootstrap.py#L10) | 把 openjiuwen.agent_teams home 指向用户工作区根 |
| TeamError | [exceptions.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/team/exceptions.py#L11) | Team 模块基础异常 |

### 2.4 Harness 场景能力组件

| 类/函数 | 文件位置 | 说明 |
| --- | --- | --- |
| RuntimePromptRail | [runtime_prompt_rail.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/common/runtime_prompt_rail.py#L35) | 每次 model call 注入时间/运行时状态 |
| CodeTaskPlanningRail | [code_task_planning_rail.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/code/code_task_planning_rail.py#L32) | code 模式 todo rail |
| WorkAgentModeRail | [work_agent_mode_rail.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/work/work_agent_mode_rail.py#L36) | work profile plan 模式 rail |

## 三、实现机制

### 3.1 Swarm 声明式装配时序

Swarm 装配的核心思想是"声明 → 派生 → 烘焙 → 实例化"四段式流水线。整个流程以 `enrich_team_spec_for_swarm` 为唯一入口，所有后续构造都从这一步派生，避免散落的副作用。

```text
请求 (session/channel/mode/project_dir)
   │
   ▼
[1] enrich_team_spec_for_swarm(assembly.py#L56)
      │  注册 swarm.* 能力 provider
      ▼
[2] register_swarm_providers(registry.py#L166)
      │  import provider 模块 → 填充 catalog → register_from_catalog（幂等）
      ▼
[3] 构建 SwarmBuildContext(context.py#L24)
      │  继承 openjiuwen BuildContext
      │  设置 per-team/per-process 字段（session_id/request_id/channel_id/mode）
      ▼
[4] build_member_deep_agent_spec(config_specs.py#L709)
      │  对每个成员：折叠能力 spec + code system prompt 进 base DeepAgentSpec
      │
      ├─► build_member_capability_specs(config_specs.py#L585)
      │     按 mode 分档（team / code.team / team.plan）构建 rails+tools specs
      │
      ├─► build_member_subagent_specs(config_specs.py#L666)
      │     构建 code 子 agent（explore/plan 常驻；code/browser 受 config 门控）
      │
      └─► _RAIL_PARAM_BUILDERS(config_specs.py#L358)
            属性烘焙表：把 config 派生属性投射进 RailSpec.params
      │
      ▼
[5] spec.build_context_seed = context.to_seed()      # 序列化供接收侧重建
      │
      ▼
[6] openjiuwen setup_agent
      │  spec.build(context) → 逐元素 .build() 工厂构造
      ▼
   可运行的 Leader / Teammate
```

第 [4] 步是装配的心脏。`build_member_capability_specs` 按 `mode` 分档：`team` 走纯群体协作能力，`code.team` 叠加代码工程能力（CC prompt、plan approval），`team.plan` 切换到计划模式提示。`_RAIL_PARAM_BUILDERS` 是一张"属性烘焙表"，把 config 中派生出的属性值统一投射到 `RailSpec.params`，使 rail 在实例化时能拿到烘焙好的参数，而不必在 rail 内部重复派生逻辑。

第 [5] 步的 `to_seed()` 是分布式协作的关键：它把构造期环境序列化为可传输的 seed，接收侧（可能是另一个进程/机器）通过 `_build_swarm_context_from_seed` 用本地 config + per-team trajectory 重建 context，从而保证"声明侧"与"执行侧"环境一致。

### 3.2 Leader/Teammate 协作时序

协作运行时由 `TeamManager.interact` 驱动，它恢复 runtime 后取出 active team，再委托 openjiuwen Runner 的 `interact_agent_team` 推进 Leader。

```text
[1] TeamManager.interact(team_manager.py#L1232)
      │  恢复 runtime → 取 active team
      ▼
[2] Runner.interact_agent_team
      │  Leader LLM 推理 + 工具调用
      │
      ├─► build_team        （构造/重组团队）
      ├─► create_task       （拆解任务）
      ├─► spawn_teammate    （派生成员）
      │     └─► remote_member_bootstrap 注入远端 claw（分布式场景）
      └─► send_message      （群体通信）
      │
      ▼
[3] TeamMonitor 事件流
      │  产生 MonitorEventType 事件
      ▼
[4] resolve_team_event(event_types.py#L44)
      │  SDK 事件 → 前端事件字符串广播
      ▼
[5] Teammate 完成任务 → 提交审核
```

角色分工在装配期就已固化：Leader 装 `TEAM_SKILL_EVOLUTION` / `TEAM_SKILL_CREATE` / `SYMPHONY_TOOLKIT` 等团队级能力，能演化团队技能并创建新成员；Teammate 装 `MEMBER_SKILL_EVOLUTION` / `TEAM_PERMISSION`，只能演化自身技能并按权限提交。这种不对称设计保证了"谁负责拆解、谁负责执行"的清晰边界。

分布式场景下，`is_distributed_mode`（依赖 pyzmq 可用性与配置开关）判断是否走分布式路径，`runtime_role` 解析当前进程扮演 leader 还是 teammate。Teammate 进程经 pyzmq transport 与 Leader 通信，spawn 时通过 `remote_member_bootstrap` 把 claw 占位包注入远端，实现"声明在 Leader、执行在 Teammate"的跨进程协作。

### 3.3 param vs context 边界

本模块严格区分三类数据来源，避免"环境值"与"属性值"混用导致的序列化与重建错误。这一约定在 DESIGN.md 中明确记录：

| 类别 | 载体 | 含义 | 示例 |
| --- | --- | --- | --- |
| 属性值 | `RailSpec.params` (param_field) | 来自 config 派生，烘焙后随 spec 走，可序列化 | skill 白名单、plan 模式开关 |
| 环境值 | `SwarmBuildContext` (context_field) | 构造期一次性设定，per-team/per-process | session_id、channel、mode |
| 基础设施/句柄 | `ctx.extras` 直读 | 运行时句柄，不可序列化，需从 seed 重建 | 数据库连接、WS 句柄 |

这条边界决定了：`to_seed()` 只序列化 param_field + context_field 的可序列化部分，而 `ctx.extras` 中的句柄必须在 `from_seed` 后由接收侧重新绑定。这是分布式 Swarm 能跨进程一致重建的根本保证。

### 3.4 技能演进的双层机制

技能演进是 Swarm 区别于普通多 agent 编排的关键能力：它允许团队与成员在运行中各自积累、沉淀能力，而非把能力固定在初始配置中。`_role_evolution_rails(config_specs.py#L438)` 按角色派生演进 rail，形成"团队级 + 成员级"的双层演进结构：

| 角色 | 演进 rail | 能力范围 |
| --- | --- | --- |
| Leader | TEAM_SKILL_EVOLUTION | 团队级技能进化，更新团队共享技能库 |
| Leader | TEAM_SKILL_CREATE | 创建新成员/新技能，动态扩展团队 |
| Leader | SYMPHONY_TOOLKIT | 团队编排工具栏（构建/拆解/重组） |
| Teammate | MEMBER_SKILL_EVOLUTION | 成员级技能进化，仅更新自身技能 |
| Teammate | TEAM_PERMISSION | 权限受限提交，需 Leader 审核 |

双层演进的设计意图是"中心化决策 + 去中心化积累"：Leader 负责团队结构的演化（新增成员、更新团队共享技能），这是中心化决策；Teammate 负责自身技能的局部积累（成员级技能进化），这是去中心化积累。两者通过 `evolution_rails.py#L52` 的 provider 注册到装配流水线，经 `_RAIL_PARAM_BUILDERS` 把 config 派生的白名单/权限属性烘焙进 `RailSpec.params`，使演进 rail 在实例化时即可拿到正确的权限边界。

这套机制让 Swarm 具备"自我增强"特性：随着协作推进，团队技能库与成员技能库都会不断扩充，后续任务的装配可复用已演化的能力，形成正反馈闭环。这也是 `_role_evolution_rails` 在装配期就按角色固化的原因——演进权限的不对称必须在实例化前确定，避免运行时越权。

## 四、调用示例

### 4.1 装配入口调用

```python
from jiuwenswarm.agents.swarm.assembly import enrich_team_spec_for_swarm

# spec 为 openjiuwen 的 TeamSpec；enrich 会就地改写成员 spec
enrich_team_spec_for_swarm(
    spec,
    session_id="sess-001",
    mode="team",                 # 或 "code.team" / "team.plan"
    project_dir="/workspace/proj",
    request_id="req-001",
    channel_id="feishu",
    request_metadata={"mode": "team"},
)
# 之后交给 openjiuwen setup_agent(spec) 完成实例化
```

### 4.2 分布式角色判定

```python
from jiuwenswarm.agents.harness.team.distributed_runtime import (
    is_distributed_mode,
    runtime_role,
)

if is_distributed_mode():
    role = runtime_role()        # "leader" 或 "teammate"
    if role == "teammate":
        # 走 pyzmq transport，接收 spawn 指令
        ...
```

### 4.3 Team 协作入口

```python
from jiuwenswarm.agents.harness.team.team_manager import TeamManager

mgr = TeamManager(...)           # 由 bootstrap 注入 home
result = mgr.interact(
    message="帮我拆解并实现登录模块",
    session_id="sess-001",
    channel_id="feishu",
    user_id="u-001",
)
# Leader 推理 → build_team / create_task / spawn_teammate / send_message
# TeamMonitor 事件流经 resolve_team_event 广播
```

### 4.4 从 seed 重建 context（接收侧）

```python
from jiuwenswarm.agents.swarm.registry import _build_swarm_context_from_seed

# seed 由装配侧 to_seed() 导出，跨进程传递
context = _build_swarm_context_from_seed(seed, local_config)
# context.extras 中的句柄由本侧重新绑定
```

### 4.5 角色演进 rail 触发（示意）

```python
# 演进 rail 由 _role_evolution_rails(config_specs.py#L438) 在装配期按角色固化
# Leader 可触发 TEAM_SKILL_CREATE 动态扩展团队
leader_team.create_skill(name="code-review", spec={...})
# Teammate 仅能触发 MEMBER_SKILL_EVOLUTION，更新自身技能
teammate_member.evolve_skill(skill_id="explore", delta={...})
# 演进结果经 evolution watcher 持久化，供后续装配复用
```

## 五、业界对比

| 能力维度 | JiuwenSwarm | LangGraph | AutoGen | CrewAI |
| --- | --- | --- | --- | --- |
| 装配方式 | 纯声明式 Swarm 装配（config→spec→provider 实例化） | 图编排（节点/边显式连线） | GroupChat 对话驱动 | 角色 crew 声明 |
| Leader/Teammate | 显式角色分工，装配期固化不对称能力 | 无原生角色，由图节点承担 | 轮转 speaker，角色弱 | 角色字段声明，对称 |
| 分布式 | pyzmq transport，seed 重建 context | 无原生分布式 | 无原生分布式 | 无原生分布式 |
| 技能演进 | 团队级 + 成员级双层演进 rail | 不支持 | 不支持 | 不支持 |
| 与框架解耦 | 框架下沉 openjiuwen，平台只声明 | 自带框架 | 自带框架 | 自带框架 |
| 计划/审批 | plan approval rail + todo rail | 不内置 | 不内置 | 内置 task |
| 序列化重建 | to_seed/from_seed 跨进程一致 | 无 | 无 | 无 |

JiuwenSwarm 的差异化在于"声明式装配 + 双层技能演进 + 分布式 seed 重建"三位一体：它既不像 LangGraph 那样把协作逻辑硬编码进图结构，也不像 AutoGen/CrewAI 那样把角色停留在对话层，而是把角色能力在装配期就固化为不对称的 rails/tools，并通过 seed 机制实现跨进程一致重建。

## 六、小结

1. `agents/` 是智能体运行时与 Swarm 协作核心，对下以 `swarm/` 做声明式装配，对上以 `harness/` 提供场景化能力组件，整体把 openjiuwen 框架下沉为基础设施。
2. Swarm 装配以 `enrich_team_spec_for_swarm` 为唯一入口，经 provider 注册 → SwarmBuildContext 构建 → 分档 spec 构建 → 属性烘焙 → to_seed 序列化的四段式流水线完成实例化。
3. Leader/Teammate 协作通过 `TeamManager.interact` 驱动，角色能力在装配期固化为不对称（Leader 持团队级能力，Teammate 持成员级能力），分布式场景经 pyzmq transport 跨进程通信。
4. 严格的 param/context/extras 三层边界是分布式 Swarm 跨进程一致重建的根本保证：属性值随 spec 走，环境值随 context 走，句柄由接收侧重建。
5. 相对竞品，本模块以"声明式装配 + 双层技能演进 + seed 重建"形成差异化，使群体协作可声明、可演进、可分布部署。
