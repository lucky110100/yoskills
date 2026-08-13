# 技能广场与共享

> 交叉引用: [01-项目概述](../01-project-overview.md) | [02-整体架构](../02-overall-architecture.md) | [03-agents与swarm](../03-agents-and-swarm-module.md) | [06-symphony](../06-symphony-module.md) | [特性索引](README.md)

## 一、能力概述

技能广场与共享是 JiuwenSwarm 让能力资产"一次构建、处处复用"的机制。技能（Skill，由 `SKILL.md` + schema 组成）可在 Swarm Skills Hub（swarmskills.openjiuwen.com）上被搜索、安装、卸载，安装后可组合、再混进成员配置，形成"共享 → 组合 → 再混"的能力流转闭环。这使得开发者不必从零造轮子，团队间的最佳实践可沉淀为可分发的技能资产。

它的价值在于把技能从"项目内私有"提升为"跨开发者共享的可组合资产"。普通 agent 框架的工具/提示分散在各项目里难以复用，而 JiuwenSwarm 的技能是自描述的标准化产物：每个技能带 frontmatter 元数据与 IO schema，既能被人审阅，也能被 Symphony 抽取为指纹构建知识图谱，供检索与编排复用。

定位上，技能广场是 [agents 模块](../03-agents-and-swarm-module.md) 装配能力的"供给侧"：装配期由 `build_skill_toolkit` 提供白名单过滤后的技能发现/安装/卸载工具，由 `build_member_skill_toolkit` 把成员配置技能链接到工作区 skills 目录；运行期由 `SkillManager` 承接 skills.* 请求管理技能状态。技能网络能力由外部依赖 `skillnet-ai==0.0.16` 提供，是 Swarm Skills Hub 的客户端。

## 二、关键类与函数

路径前缀：`D:/jiuwen/main/jiuwenswarm/jiuwenswarm/`

| 类/函数 | 文件位置 | 说明 |
| --- | --- | --- |
| build_skill_toolkit | [tools.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/providers/tools.py#L437) | 白名单过滤后的技能发现/安装/卸载工具构造器 |
| SkillToolkitInput | [tools.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/providers/tools.py#L413) | 技能工具 ConstructionInput（白名单等参数） |
| build_member_skill_toolkit | [skills.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/providers/skills.py#L167) | 链接成员配置技能到工作区 skills 目录 |
| MemberSkillToolkitInput | [skills.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/providers/skills.py#L133) | 成员技能工具栏 rail 的 ConstructionInput |
| SkillManager | [skill_manager.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/runtime/skill/skill_manager.py#L415) | 技能管理器，对应 skills.* 请求方法（安装/卸载/状态） |
| load_execution_disabled_skills | [state_utils.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/runtime/skill/skilldev/state_utils.py#L147) | 读 skills_state.json 返回已安装但禁用的技能名 |
| skillnet-ai==0.0.16 | 外部依赖 | Swarm Skills Hub 客户端（技能网络） |

## 三、实现机制

### 3.1 技能广场搜索/安装/卸载

技能广场（swarmskills.openjiuwen.com）是跨开发者共享技能的中心枢纽。运行时，`build_skill_toolkit` 构造一组白名单过滤后的工具，让 Leader/Teammate 能在推理中发现、安装、卸载技能：发现经 SkillNet 客户端（`skillnet-ai`）查询广场，安装把技能拉取到本地 skills 目录并登记状态，卸载则反向清理。`SkillToolkitInput` 是这组工具的 ConstructionInput，承载白名单等参数——白名单决定哪些技能允许被安装/使用，是装配期的安全边界。

`SkillManager` 承接 skills.* 请求方法（对应 server 端 RPC），管理技能状态机：它维护 `skills_state.json` 记录已安装技能与禁用列表，并自动把"手动拷入 skills 目录但未经安装流程登记"的本地技能补登记到 local_skills，使其与"导入本地技能"完全等价（可展示/卸载/查看详情/禁用）。SkillNet 安装是异步的：install 立即返回 install_id 后台下载，完成后调用 hook 重载 Agent 实例。

### 3.2 成员配置技能链接

成员配置技能经 `build_member_skill_toolkit` 链接到工作区 skills 目录。`MemberSkillToolkitInput` 是该 rail 的 ConstructionInput：它把成员配置（config）中声明的技能链接（link）到工作区的 skills 目录，使该成员在运行时能"看到"这些技能。这一步是装配期的供给侧动作，发生在 provider 工厂构造阶段，与 `build_skill_toolkit` 的"运行期发现/安装"互补——前者解决"成员配置里写了哪些技能"，后者解决"运行中还能从广场装哪些"。

### 3.3 禁用技能过滤

`load_execution_disabled_skills` 读 `skills_state.json`，返回已安装但被禁用的技能名列表。装配期与运行期都会用它做过滤：`build_skill_toolkit` 的白名单会扣除禁用项，避免被禁技能出现在工具栏；`SkillManager` 的查询接口也据此隐藏禁用技能，使"禁用"成为一致的安全边界——既能让人停用某项可疑技能，又不破坏已安装状态，便于随时恢复。

### 3.4 Symphony 把技能抽取为知识图谱

技能不只是运行期工具，还是 Symphony 知识引擎的输入。[Symphony 模块](../06-symphony-module.md) 把每个 Skill 抽取为标准化"指纹"（解析 `SKILL.md` frontmatter、抽取 IO schema、规范化 IO 名称），再经 LLM 本体匹配组织成 Skill 知识图谱。这使得广场上的技能既能被人审阅（tree index + HTML 预览），也能被机器检索与编排复用：在线规划时，`plan_from_score` 基于图谱与动态叠加层把自然语言 query 解析为 Skill 执行图。这是技能广场"组合再混"的智能化底座——技能不必显式连线，图谱会按数据依赖自动编排。

### 3.5 SkillManager 状态机与本地技能补登记

`SkillManager` 维护一份 `skills_state.json` 作为技能状态机的事实来源，记录已安装技能与禁用列表。它有一个关键设计：自动把"手动拷入 skills 目录、未经任何安装流程登记"的本地技能补登记到 local_skills，使其与"导入本地技能"完全等价——可展示、可卸载、可查看详情、可禁用。这降低了使用门槛：开发者可直接把技能文件夹拷进 skills 目录即视为安装，无需走 SkillNet 在线流程。

| 状态来源 | 登记方式 | 可执行操作 |
| --- | --- | --- |
| SkillNet 在线安装 | install 流程登记 | 展示/卸载/详情/禁用 |
| 手动拷入本地 | 自动补登记 local_skills | 展示/卸载/详情/禁用 |
| 禁用 | skills_state.json disabled | 隐藏不出现在工具栏 |

### 3.6 SkillNet 异步安装流程

SkillNet 安装是异步的，避免阻塞 Leader 推理。`SkillManager.install` 立即返回一个 `install_id`，后台下载技能包，完成后调用注册的 hook（`set_skillnet_install_complete_hook`，通常为重载 Agent 实例）使新技能即时生效：

```text
SkillManager.install(skill_name)
  → 立即返回 install_id（不阻塞）
  → 后台经 skillnet-ai 下载技能包到本地 skills 目录
  → 完成后登记到 skills_state.json
  → 触发 install_complete_hook → 重载 Agent 实例
  → 新技能即时出现在工具栏
```

异步设计的关键考量是：技能安装可能涉及网络下载（从 Swarm Skills Hub 拉取），耗时不确定。若同步等待，Leader 推理会卡在工具调用上。异步让 Leader 立即拿到 ack 并继续推进，安装完成后再重载——这与 SwarmFlow 的"三层路由链立即 ack"理念一致：先响应、后处理，避免长任务阻塞主流程。

## 四、调用示例

### 4.1 装配期构造技能工具栏（白名单过滤）

```python
from jiuwenswarm.agents.swarm.providers.tools import (
    build_skill_toolkit, SkillToolkitInput,
)

toolkit = build_skill_toolkit(SkillToolkitInput(
    whitelist=["explore", "plan", "code-review"],   # 允许的技能名
    workspace_dir="/workspace/team",
))
# toolkit 为 Leader/Teammate 提供 discover/install/uninstall 工具
# 白名单外的技能不会出现在工具栏
```

### 4.2 链接成员配置技能到工作区

```python
from jiuwenswarm.agents.swarm.providers.skills import (
    build_member_skill_toolkit, MemberSkillToolkitInput,
)

rail = build_member_skill_toolkit(MemberSkillToolkitInput(
    member_skills=["explore", "plan"],     # 成员配置声明的技能
    workspace_dir="/workspace/team",
))
# 把配置技能链接到工作区 skills 目录，使该成员运行时可见
```

### 4.3 运行期管理技能状态（SkillManager）

```python
from jiuwenswarm.server.runtime.skill.skill_manager import SkillManager

mgr = SkillManager(workspace_dir="/workspace/team")
# SkillManager 承接 skills.* RPC：install/uninstall/list/disable
# SkillNet 异步安装：install 立即返回 install_id，后台下载完成后回调重载 Agent
```

### 4.4 过滤禁用技能

```python
from jiuwenswarm.server.runtime.skill.skilldev.state_utils import (
    load_execution_disabled_skills,
)

disabled = load_execution_disabled_skills()    # ["bad-skill", ...]
visible = [n for n in all_skills if n not in set(disabled)]
# 装配期 build_skill_toolkit 白名单与运行期查询都据此过滤
```

### 4.5 异步安装与重载 hook（示意）

```python
from jiuwenswarm.server.runtime.skill.skill_manager import SkillManager

mgr = SkillManager(workspace_dir="/workspace/team")
mgr.set_skillnet_install_complete_hook(reload_agent)   # 安装完成后重载 Agent
install_id = mgr.install("code-review")               # 立即返回，后台下载
# ... Leader 继续推进，不阻塞 ...
# 后台下载完成 → 触发 reload_agent → 新技能即时出现在工具栏
```

异步安装与 SwarmFlow 的"立即 ack、后台处理"理念一致：先响应、后处理，避免网络下载阻塞 Leader 推理。

## 五、业界对比

| 能力维度 | JiuwenSwarm(Swarm Skills Hub) | LangChain Hub | Hugging Face Spaces | Coze |
| --- | --- | --- | --- | --- |
| 资产类型 | Skill（SKILL.md+schema，自描述标准化产物） | 提示/工具 | 模型应用 | 插件 |
| 共享机制 | Swarm Skills Hub（skillnet-ai 客户端）搜索/安装/卸载 | Hub 拉取 | Spaces 部署 | 插件市场 |
| 组合再混 | 成员配置技能链接 + Symphony 图谱自动编排 | 提示拼接 | 模型串联 | 插件调用 |
| 知识图谱 | 抽取指纹→LLM 本体匹配→可检索可编排图谱 | 无 | 无 | 无 |

JiuwenSwarm 的差异化在于"标准化技能资产 + 图谱化组合"：它不像 LangChain Hub 那样只共享松散的提示/工具，也不像 HF Spaces 那样只部署孤立模型应用，而是把技能做成自描述标准化产物，再经 Symphony 抽取为知识图谱，使"组合再混"可由图谱按数据依赖自动编排，而非人工显式连线。

## 六、小结

1. 技能广场（Swarm Skills Hub）让技能资产一次构建、处处复用：经 `skillnet-ai` 客户端在 swarmskills.openjiuwen.com 搜索/安装/卸载，技能是自描述标准化产物（SKILL.md + schema）。
2. 装配期由 `build_skill_toolkit`（`SkillToolkitInput` 承载白名单）提供白名单过滤后的发现/安装/卸载工具，由 `build_member_skill_toolkit`（`MemberSkillToolkitInput`）把成员配置技能链接到工作区 skills 目录。
3. 运行期由 `SkillManager` 承接 skills.* RPC 管理技能状态，自动补登记手动拷入的本地技能，SkillNet 安装异步完成并回调重载 Agent。
4. `load_execution_disabled_skills` 读 skills_state.json 返回禁用列表，装配期白名单与运行期查询都据此过滤，"禁用"成为一致的安全边界。
5. Symphony 把技能抽取为指纹构建知识图谱，使"组合再混"可由图谱按数据依赖自动编排，而非人工显式连线——这是技能广场的智能化底座。
