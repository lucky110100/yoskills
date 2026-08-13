# 模式系统

> 交叉引用: [01-项目概述](../01-project-overview.md) | [02-整体架构](../02-overall-architecture.md) | [03-agents与swarm](../03-agents-and-swarm-module.md) | [08-common与e2a](../08-common-e2a-and-security-module.md) | [特性索引](README.md)

## 一、能力概述

JiuwenSwarm 提供三种执行模式,覆盖从"稳"到"快"再到"群"的全谱系:**Plan(逐步执行)** 适合需要人工审批、谨慎推进的复杂任务;**Performance(灵活并行)** 适合追求效率的常规编码;**Swarm(Leader 编排多 Agent 协作)** 适合需要群体拆解与协作的大型工程。三种模式不是互斥的开关,而是一套可组合、可解析的矩阵。

模式系统要解决的核心工程问题是"Web 组合模式与历史完整模式的统一"。Web 前端只表达 `agent`/`team`/`agent.plan` 三个值,其中单 agent 的两个由 `work_mode`(work/code)决定使用 work profile 还是 code profile;而 TUI/CLI/IM/cron 等历史客户端发送的是 `code.normal`/`code.plan`/`code.team`/`team.plan` 等完整模式串。`resolve_request_mode` 采用"Web 组合分支优先 + legacy 兜底"策略,把这两类请求在同一个 `ResolvedMode` 视图下统一,保证新式 Web 走新链路、旧式客户端逐字节不变。

在装配侧,模式决定能力分档:`build_member_capability_specs` 按 mode(team/code.team/team.plan)分档构建成员的 rails+tools,使 Leader/Teammate 在不同模式下获得不同的能力组合。Agent 实例则按 (channel,mode,sub_mode,project) 缓存复用,避免重复装配。

## 二、关键类与函数

| 类/函数 | 文件位置 | 说明 |
| --- | --- | --- |
| resolve_request_mode | [mode_matrix.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/mode_matrix.py#L152) | 解析请求运行模式:Web 组合分支优先,其余 legacy_resolver |
| ResolvedMode | [mode_matrix.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/mode_matrix.py#L66) | 完整运行模式视图:manager_mode/sub_mode/canonical_mode/is_plan/is_team |
| compose_web_mode | [mode_matrix.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/mode_matrix.py#L139) | 把 Web 的 mode+work_mode 组合成后端三元组 |
| is_plan_mode / is_team_mode | [mode_matrix.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/mode_matrix.py#L123) | canonical 模式是否 plan / 是否集群 |
| build_member_capability_specs | [config_specs.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/config_specs.py#L585) | 按 mode(team/code.team/team.plan)分档构建成员 rails+tools |
| _build_team_capability_specs | [config_specs.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/config_specs.py#L459) | chat-team profile 能力构建(含权限双轨) |
| _prepare_code_mode_chat_turn | [agent_ws_server.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/agent_ws_server.py#L2165) | 解析 mode 经 mode_matrix 获取 agent,模式选择与实例获取 |
| get_config | [config.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/config.py) | config.yaml 模式读取(缓存+重试+环境变量替换) |
| AgentManager.get_agent | [agent_ws_server.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/agent_ws_server.py#L2266) | 按 (channel,mode,sub_mode,project) 缓存获取 agent |

## 三、实现机制

### 3.1 模式解析:Web 组合分支优先

请求到达后,`_prepare_code_mode_chat_turn`([agent_ws_server.py#L2165](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/agent_ws_server.py#L2165))调用 `resolve_request_mode`([mode_matrix.py#L152](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/mode_matrix.py#L152))解析模式。解析采用"Web 组合分支优先 + legacy 兜底"策略:

```text
请求 params 携带 mode(及可选 work_mode)
   │
   ▼
[1] resolve_request_mode(mode_matrix.py#L152)
      │  normalize_mode_text / read_request_work_mode 归一化
      │
      ├─► Web 组合分支(优先)
      │     条件:存在合法 work_mode 且 mode ∈ {agent, agent.plan}
      │     compose_web_mode(mode_matrix.py#L139) 查 _WEB_MODE_TABLE
      │     得 (manager_mode, sub_mode, canonical_mode)
      │     例:(agent, work)→(agent, None, agent)
      │         (agent.plan, code)→(code, plan, code.plan)
      │
      └─► legacy 兜底分支
            其余取值(team / code.plan / code.team / agent.fast 等)
            委派 legacy_resolver,逐字节保持既有解析
   │
   ▼
[2] ResolvedMode(mode_matrix.py#L66)
      manager_mode / sub_mode / canonical_mode / work_mode
      is_plan / is_team / is_code_profile / normal_mode / from_web_composition
   │
   ▼
[3] _apply_resolved_mode_to_request 把 canonical_mode 写回 params["mode"]
      （显式 mode 守卫:未显式携带则不覆盖磁盘已锁定 mode）
   │
   ▼
[4] AgentManager.get_agent(channel, mode, sub_mode, project) 缓存获取 agent
```

第 [1] 步的关键设计是"Web 组合只覆盖单 agent"。`team` 刻意不进入 Web 组合分支:Plan 只对单 agent 开放,而集群的 Adapter 选型沿用历史规则(`team`→DeepAdapter),不随 `work_mode` 变化。把 `team` 交给 legacy 分支,使 Web 集群行为与改造前逐字节一致,避免回归风险。第 [3] 步的"显式 mode 守卫"防止只读 RPC 用默认推断值腐蚀已锁定的会话 mode(如把空白 mode 误判为 agent.plan 写盘)。

`resolve_request_mode` 依赖一组归一化辅助保证输入鲁棒:`normalize_mode_text` 把任意来源的 mode 归一为小写字符串(空值回落 `agent`),`normalize_work_mode` 把 `work_mode` 归一为 `work`/`code`(非法返回 None),`read_request_work_mode` 从 params 读取显式 `work_mode`——它同时充当"这是 Web 组合请求"的判据(TUI/CLI/IM/cron 都不发该字段)。`_WEB_MODE_TABLE` 是 Web 组合查找表,把 `(mode, work_mode)` 映射到 `(manager_mode, sub_mode, canonical_mode)`,例:`(agent, work)→(agent, None, agent)`、`(agent.plan, code)→(code, plan, code.plan)`。

模式常量集合固化分类边界:`WEB_COMPOSABLE_MODES`={agent, agent.plan} 是 Web 可组合集;`TEAM_CANONICAL_MODES`={team, team.plan, code.team} 是集群集;`PLAN_CANONICAL_MODES`={agent.plan, code.plan, team.plan} 是 plan 集。`_PLAN_EXIT_MODES` 定义 plan 退出后回到的普通模式(agent.plan→agent,code.plan→code.normal,team.plan→code.team),由 `base_mode_without_plan` 查询,使 plan 模式可干净退出。这些常量使模式判定从字符串比较收敛为集合查找,避免散落 if-else。

### 3.2 装配侧:按 mode 分档构建能力

`ResolvedMode` 产出后,装配侧用 `build_member_capability_specs`([config_specs.py#L585](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/config_specs.py#L585))按 mode 分档构建成员能力:

```text
[1] build_member_capability_specs(config, mode, role, enable_permissions)
      │
      ├─► _is_code_mode(mode)?
      │     Yes → _build_code_capability_specs
      │            code profile(swarm.code_* rails + code system prompt)
      │     No  → _build_team_capability_specs(config_specs.py#L459)
      │            chat-team profile + 成员技能工具栏 + 角色演进 rail
      │            enable_permissions → TEAM_PERMISSION 双轨
      ▼
[2] 产出 (rails_specs, tool_specs) 元组
      │
      ▼
[3] build_member_deep_agent_spec 折叠能力 spec + code system prompt 进 base spec
      │
      ▼
[4] openjiuwen setup_agent 实例化 Leader / Teammate
```

三个模式对应不同的能力组合:**Plan** 模式叠加计划审批 rail + todo rail,逐步执行并需人工审批;**Performance** 模式走 code profile,叠加 CC prompt 与代码工程能力,灵活并行;**Swarm** 模式按 Leader/Teammate 角色固化不对称能力(Leader 持团队级能力,Teammate 持成员级能力 + 权限双轨)。Agent 实例按 (channel,mode,sub_mode,project) 缓存复用,使同一组合的后续请求无需重复装配。

### 3.3 Agent 实例缓存复用

`AgentManager.get_agent` 按 `(channel, mode, sub_mode, project)` 四元组缓存已装配的 agent 实例。这一缓存策略的意义在于:同一渠道、同一模式、同一子模式、同一项目下的请求,装配(openjiuwen `setup_agent`)只发生一次,后续请求直接复用缓存实例。模式切换(如 plan→normal)会命中不同四元组,触发新装配,但旧实例仍保留在缓存中,模式回切时无需重建。这一设计把"模式解析的廉价性"与"装配的昂贵性"分离:解析每请求都跑(轻量),装配按四元组复用(重量),显著降低高频对话的开销。

### 3.4 三模式对比

| 模式 | 描述 | 适用场景 | 典型输入 |
| --- | --- | --- | --- |
| Plan | 逐步执行,人工审批,谨慎推进 | 复杂/高风险任务,需 review | `agent.plan` / `code.plan` / `team.plan` |
| Performance | 灵活并行,追求效率 | 常规编码、迭代 | `agent`(+work_mode) / `code.normal` |
| Swarm | Leader 编排多 Agent 协作 | 大型工程、群体拆解 | `team` / `code.team` |

## 四、调用示例

### 4.1 模式解析

```python
from jiuwenswarm.common.mode_matrix import resolve_request_mode

mode = resolve_request_mode(                          # mode_matrix.py#L152
    params={"mode": "agent", "work_mode": "code"},
    legacy_resolver=default_resolver,
)
# Web 组合分支:(agent, code) → (code, normal, code.normal)
assert mode.canonical_mode == "code.normal"
assert mode.is_code_profile and not mode.is_plan
```

### 4.2 模式判定与分支

```python
from jiuwenswarm.common.mode_matrix import is_plan_mode, is_team_mode, base_mode_without_plan

if is_plan_mode(mode.canonical_mode):                 # mode_matrix.py#L123
    enter_plan_flow(mode)                              # 叠加计划审批 rail
elif is_team_mode(mode.canonical_mode):
    enter_team_flow(mode)                              # Leader/Teammate 装配
normal = base_mode_without_plan(mode.canonical_mode)   # 退出 plan 回到普通模式
```

### 4.3 装配侧按 mode 分档

```python
from jiuwenswarm.agents.swarm.config_specs import build_member_capability_specs

rails_specs, tool_specs = build_member_capability_specs(   # config_specs.py#L585
    config=cfg, mode="team", role="teammate",
    enable_permissions=True,                            # → TEAM_PERMISSION 双轨
)
# mode="code.team" → code profile;mode="team" → chat-team profile
```

### 4.4 服务端模式选择

```python
# agent_ws_server.py#L2165 _prepare_code_mode_chat_turn
mode, sub_mode, agent = await self._prepare_code_mode_chat_turn(
    request, channel_id, sync_metadata=True,
)
# 内部 resolve_request_mode → ResolvedMode → get_agent(channel, mode, sub_mode, project)
```

### 4.5 配置加载与 plan 退出

```python
from jiuwenswarm.common.config import get_config
from jiuwenswarm.common.mode_matrix import base_mode_without_plan

cfg = get_config()                                       # config.yaml 模式读取
# plan 模式退出:canonical plan → 普通 canonical
normal = base_mode_without_plan("code.plan")             # → "code.normal"
# is_plan_mode/is_team_mode 用集合查找判定模式类别
```

## 五、业界对比

| 维度 | JiuwenSwarm | LangGraph | AutoGen | Dify |
| --- | --- | --- | --- | --- |
| 模式粒度 | 三模式(Plan/Performance/Swarm)+ 子模式 | 图节点 | 对话模式 | 工作流节点 |
| 组合解析 | Web 组合分支优先 + legacy 兜底,统一 ResolvedMode | 无 | 无 | 无 |
| 子模式 | normal/plan/team 子模式 + canonical 规范化 | 无 | 无 | 无 |
| Agent 缓存 | 按 (channel,mode,sub_mode,project) 缓存复用 | 无 | 无 | 无 |
| 能力分档 | 按 mode 分档构建 rails+tools,角色不对称 | 节点能力 | 角色对称 | 节点能力 |

JiuwenSwarm 的差异化在于"三模式 + 矩阵解析 + 能力分档"三位一体:它不像 LangGraph 把协作逻辑硬编码进图结构,也不像 AutoGen 把模式停留在对话层,而是用 `resolve_request_mode` 的"Web 组合优先 + legacy 兜底"策略把新式与历史请求统一在 `ResolvedMode` 视图下,再由 `build_member_capability_specs` 按 mode 分档构建不对称能力。`get_agent` 按 (channel,mode,sub_mode,project) 缓存复用,使模式切换的开销降到最低。

## 六、小结

1. 模式系统提供 Plan(逐步执行)、Performance(灵活并行)、Swarm(Leader 编排多 Agent 协作)三种执行模式,覆盖从稳到快再到群的全谱系。
2. `resolve_request_mode` 采用"Web 组合分支优先 + legacy 兜底"策略:Web 的 mode+work_mode 组合解析单 agent,team 与历史完整模式串交 legacy_resolver,保证新式走新链路、旧式逐字节不变。
3. 解析产出 `ResolvedMode`,含 manager_mode/sub_mode/canonical_mode/is_plan/is_team/is_code_profile/normal_mode/from_web_composition 完整视图,`_apply_resolved_mode_to_request` 把 canonical_mode 写回 params(显式 mode 守卫防腐蚀已锁定会话)。
4. 装配侧 `build_member_capability_specs` 按 mode(team/code.team/team.plan)分档构建成员 rails+tools,`_build_team_capability_specs` 处理 chat-team profile 与权限双轨。
5. Agent 实例按 (channel,mode,sub_mode,project) 缓存复用,`_prepare_code_mode_chat_turn` 经 `resolve_request_mode` 解析后调 `AgentManager.get_agent` 获取,避免重复装配。
6. 相对竞品,本系统以"三模式 + 矩阵解析(Web 组合优先)+ 能力分档 + Agent 缓存"形成差异化,使模式切换可组合、可统一解析、可缓存复用。
