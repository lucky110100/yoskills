# 技能自演进

> 交叉引用: [01-项目概述](../01-project-overview.md) | [02-整体架构](../02-overall-architecture.md) | [03-agents与swarm](../03-agents-and-swarm-module.md) | [06-symphony](../06-symphony-module.md) | [特性索引](README.md)

## 一、能力概述

技能自演进是 JiuwenSwarm 让能力"随用变强"的机制。它不把技能固定在初始配置里，而是在运行中持续检测错误信号与用户不满，据此优化技能定义——团队级与成员级双层进化：Leader 负责团队共享技能库的中心化决策，Teammate 负责自身技能的去中心化积累，两者各自沉淀、互不越权。

它的价值在于"正反馈闭环"。普通多 agent 系统每次都从同一份静态能力出发，而 JiuwenSwarm 的团队技能库与成员技能库会随协作推进不断扩充，后续任务的装配可复用已演化的能力，越用越准、越用越强。同时演化的输入信号可量化追踪（Symphony 五维评估），而非黑箱调参。

定位上，技能自演进是 [agents 模块](../03-agents-and-swarm-module.md) 与 [Symphony 知识引擎](../06-symphony-module.md) 的交叉能力：装配侧由 `_role_evolution_rails` 按角色派生演进 rail，知识侧由 Symphony 的演化闭环（record_plan_outcome → rebuild_dynamic_overlay）更新边权重叠加层。两者通过热重载路径连通，使演进结果能即时反映到运行中的团队。

## 二、关键类与函数

路径前缀：`D:/jiuwen/main/jiuwenswarm/jiuwenswarm/`

| 类/函数 | 文件位置 | 说明 |
| --- | --- | --- |
| _role_evolution_rails | [config_specs.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/config_specs.py#L438) | leader 返回 TEAM_SKILL_EVOLUTION+TEAM_SKILL_CREATE，teammate 返回 MEMBER_SKILL_EVOLUTION |
| _build_team_workspace_info | [evolution_rails.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/providers/evolution_rails.py#L52) | 构建满字段 TeamWorkspaceInfo 供热重载 |
| SkillEvolutionRail / TeamSkillEvolutionRail | [openjiuwen harness rails](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/providers/evolution_rails.py#L32) | openjiuwen 下沉的技能进化 rail（经 ensure_harness_elements_registered 引用） |
| record_plan_outcome | [service.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/evolution/service.py#L94) | 记录 plan 成败，追加事件触发 overlay 重建 |
| rebuild_dynamic_overlay | [service.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/evolution/service.py#L40) | 从事件日志重建并持久化边权重叠加层 |
| load_dynamic_overlay | [service.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/evolution/service.py#L34) | 读取当前动态叠加层供在线规划 |

## 三、实现机制

### 3.1 双层进化

技能演进分两层，由 `_role_evolution_rails` 在装配期按角色固化：

| 层级 | 角色 | 演进 rail | 决策方式 |
| --- | --- | --- | --- |
| 团队级 | Leader | TEAM_SKILL_EVOLUTION / TEAM_SKILL_CREATE | 中心化决策，更新团队共享技能库、创建新成员 |
| 成员级 | Teammate | MEMBER_SKILL_EVOLUTION | 去中心化积累，仅更新自身技能 |

设计意图是"中心化决策 + 去中心化积累"：Leader 负责团队结构演化（新增成员、更新共享技能），Teammate 负责自身技能的局部积累。演进权限的不对称在装配期就固化，避免运行时越权。这两个 rail 实际是 openjiuwen 下沉的 `SkillEvolutionRail` / `TeamSkillEvolutionRail`，经 `ensure_harness_elements_registered` 引用，由 `evolution_rails.py` 的 provider 工厂注册到装配流水线。

### 3.2 自动检测错误信号与用户不满

演进 rail 在运行中持续检测两类信号：一是执行错误信号（工具调用失败、产出质量不达标），二是用户不满信号（拒绝、纠正、追问）。检测到信号后，rail 触发技能定义的优化——可能是修订技能的 prompt、补充工具白名单、调整 IO schema。优化结果经 evolution watcher 持久化到团队/成员技能库，供后续装配复用。

### 3.3 Symphony 演化闭环

技能自演进与 Symphony 知识引擎的演化闭环联动，形成"图谱越用越准"的正反馈：

```text
执行 plan → record_plan_outcome(追加事件：成功/失败、耗时、产出质量)
         → rebuild_dynamic_overlay(build_overlay_from_events → write_overlay)
         → 下次 plan_from_score(load_dynamic_overlay 读到新权重)
         → 越用越准
```

关键设计是演化只改冻结图谱之上的"动态叠加层"（边权重浮动），不动图谱基线本身——这一分层使"稳定基线 + 持续学习"互不污染：基线保证规划可复现、可审计，叠加层保证越用越准、不腐化。`EvaluationAccumulator` 按对象身份聚合五维指标（success_rate / latency / accuracy / completeness / compliance），为演化提供量化信号。

### 3.4 热重载路径

当技能配置在运行中变更时，热重载路径经 `_build_team_workspace_info` 重建 Leader 的进化 rail。该函数构建一个满字段的 `TeamWorkspaceInfo`（含 team_ws_root、team_skills_dir、team_id、config、trajectory_registry），供热重载路径（`update_evolution_config` → `_build_and_mount_member_rails_for_context` → `build_member_rails`）从 `TeamRailMountContext.team_workspace` 重建 leader 进化 / 创建 rail。补全每个字段是为了让 provider 挂装路径下的热重载与旧 customizer 路径行为一致（旧 customizer 传满字段，swarm 路径此前传空对象）。

```text
技能配置运行中变更
  → update_evolution_config
  → _build_and_mount_member_rails_for_context
      → _build_team_workspace_info(满字段 TeamWorkspaceInfo)
      → build_member_rails
          → 重建 leader 的 TEAM_SKILL_EVOLUTION / TEAM_SKILL_CREATE rail
```

补全字段的关键意图是"行为对齐"：旧 customizer 路径在热重载时会传满字段的 workspace info，而 swarm provider 路径此前传空对象，导致 provider 挂装的团队在热重载后演进 rail 缺字段而失效。`_build_team_workspace_info` 把这条路径补齐，使两种装配路径的热重载行为一致，演进 rail 不会因字段缺失而静默降级。

### 3.5 五维评估信号

演化的输入信号不是黑箱，而是由 Symphony 的 `EvaluationAccumulator` 按对象身份（Skill / 边 / plan）聚合的五维指标量化提供：

| 维度 | 含义 | 演化作用 |
| --- | --- | --- |
| success_rate | 执行成功率 | 主权重，失败边降权 |
| latency | 执行延迟 | 高延迟边降权 |
| accuracy | 产出准确度 | 质量信号 |
| completeness | 完整性 | 是否漏输出 |
| compliance | 合规性 | 是否越权 |

五维聚合为 `QualityResult`，既作为演化叠加层的权重输入，也作为人工审阅 Score 健康度的仪表盘。与五维并行的是 `ExperienceBank`（基于 FAISS）收集执行轨迹向量并支持相似检索，使规划器能查相似经验喂提示。这套量化机制让"越用越准"可被追踪而非黑箱调参——这也是技能自演进区别于"盲目改 prompt"的根本。

## 四、调用示例

### 4.1 角色演进 rail（装配期固化）

```python
# _role_evolution_rails(config_specs.py#L438) 在装配期按角色派生演进 rail
# Leader 持团队级能力，可创建新技能/新成员
leader.create_skill(name="code-review", spec={...})
# Teammate 仅能触发 MEMBER_SKILL_EVOLUTION，更新自身技能
teammate.evolve_skill(skill_id="explore", delta={...})
# 演进结果经 evolution watcher 持久化，供后续装配复用
```

### 4.2 Symphony 演化闭环（执行后回写）

```python
from jiuwenswarm.symphony.evolution.service import (
    record_plan_outcome, rebuild_dynamic_overlay, load_dynamic_overlay,
)

async def after_run(plan_id: str, success: bool, latency_ms: int):
    await record_plan_outcome(          # 追加事件，触发 overlay 重建
        plan_id=plan_id, success=success, latency_ms=latency_ms,
    )
    await rebuild_dynamic_overlay()       # 重建并持久化边权重
    overlay = await load_dynamic_overlay()  # 下次规划读到新权重
    print("overlay edges updated:", len(overlay.edge_weights))
```

### 4.3 热重载重建 Leader 进化 rail（示意）

```python
from jiuwenswarm.agents.swarm.providers.evolution_rails import _build_team_workspace_info

ws_info = _build_team_workspace_info(
    team_ws_root="/workspace/team",
    team_skills_dir="/workspace/team/skills",
    team_id="review-squad",
    config=config_mapping,
    trajectory_registry=per_team_registry,
)
# 热重载路径据此重建 leader 的 TEAM_SKILL_EVOLUTION / TEAM_SKILL_CREATE rail
```

### 4.4 五维评估审阅（配合 EvaluationAccumulator）

```python
from jiuwenswarm.symphony.evaluation.suite import EvaluationAccumulator

async def review(plan_id: str):
    acc = EvaluationAccumulator()
    for trace in traces:
        acc.ingest(trace)                  # 按对象身份聚合（Skill/边/plan）
    quality = acc.aggregate()               # → QualityResult
    # success_rate/latency/accuracy/completeness/compliance 既供演化降权，也供人工审阅
    print(quality.success_rate, quality.latency, quality.compliance)
```

五维结果会作为演化叠加层的权重输入：失败边按 success_rate 降权、高延迟边按 latency 降权，下次 `plan_from_score` 即读到更新后的边权重。

## 五、业界对比

| 能力维度 | JiuwenSwarm | DSPy | AutoGPT | LangChain |
| --- | --- | --- | --- | --- |
| 进化粒度 | 团队级 + 成员级双层演进 | prompt 级 | agent 自改进 | 无 |
| 信号检测 | 运行期错误信号 + 用户不满 + Symphony 五维 | 评估驱动编译 | 自反思 | 无 |
| 图谱更新 | 演化只改动态叠加层，不动冻结基线 | 编译期改 prompt | 改自身记忆 | 无 |
| 热重载 | _build_team_workspace_info 满字段重建进化 rail | 不支持 | 不适用 | 不适用 |

JiuwenSwarm 的差异化在于"双层进化 + 图谱演化 + 热重载"三位一体：它不像 DSPy 那样只在编译期优化 prompt（运行期不变），也不像 AutoGPT 那样只改自身记忆（无共享图谱），而是把团队级中心化决策与成员级去中心化积累结合，并通过 Symphony 的动态叠加层让知识图谱随运行自我优化，且只改叠加层、不动冻结基线，保证"稳定可复现 + 持续学习"互不污染。

## 六、小结

1. 技能自演进是"随用变强"的机制，双层进化：Leader 团队级（TEAM_SKILL_EVOLUTION/TEAM_SKILL_CREATE 中心化决策）+ Teammate 成员级（MEMBER_SKILL_EVOLUTION 去中心化积累），权限不对称在装配期由 `_role_evolution_rails` 固化。
2. 演进 rail 持续检测错误信号与用户不满，优化技能定义，结果经 evolution watcher 持久化供后续装配复用，形成正反馈闭环。
3. Symphony 演化闭环 record_plan_outcome → rebuild_dynamic_overlay → load_dynamic_overlay 使知识图谱越用越准，且只改动态叠加层、不动冻结基线。
4. 热重载路径经 `_build_team_workspace_info` 构建满字段 TeamWorkspaceInfo，重建 Leader 进化 rail，使 provider 挂装路径与旧 customizer 路径行为一致。
5. 相对竞品，以"双层进化 + 图谱演化（叠加层）+ 热重载"形成差异化，运行期持续学习而非编译期一次性优化。
