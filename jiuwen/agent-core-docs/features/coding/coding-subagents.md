# 编码子代理协作体系

> 交叉引用: [01-项目概述](../../01-project-overview.md) | [02-整体架构](../../02-overall-architecture.md) | [04-harness模块](../../04-harness-module.md) | [08-依赖关系](../../08-dependencies.md)

## 一、能力概述

agent-core 的编码能力以"四阶段子代理协作"为核心范式:探索(Explore)→规划(Plan)→编码(Code)→验证(Verification)。四个子代理职责边界清晰且相互对立——探索者只读、规划者纯只读、编码者可写、验证者对抗且零写。这种分工让每个阶段都有最优的工具集与系统提示,而非一个"全能 agent"在单上下文里承担所有角色。

CodeAgent 是编码主线,工厂名 `code_agent`。其系统提示强调"能用工具就用工具(读/写/编辑/grep/list/bash/code),不要猜文件内容;变更要小可回滚;先澄清数据结构与接口再动代码;输出给出测试/验证步骤"。它默认预装 `SysOperationRail + AgentModeRail(plan/auto) + AskUserRail + ConfirmInterruptRail`,并在提供 `embedding_config` 时自动注入 `CodingMemoryRail`;同时通过 `_inject_builtin_plan_agents` 自动注入 `explore_agent` 与 `plan_agent`,开启 `enable_task_planning=True`。这意味着一个 `create_code_agent` 调用即可获得完整的探索-规划-编码协作链。

委派机制由 `TaskTool` 与 `DeepAgent.create_subagent` 承担。`create_subagent` 按 `spec.factory_name` 分发到 `code_agent / browser_agent / research_agent / mobile_gui_agent` 或默认 `deep_agent`;每个子代理拥有独立子会话以避免上下文污染。`SubagentRail`(priority=95)负责在宿主代理上注册 `task_tool`/`session_spawn`,使主代理可通过工具调用方式委派子任务。配合粘性会话,验证类子代理可在"FAIL→修复→重新验证"循环中复用上下文。

## 二、关键类与函数

| 类/函数 | 文件位置 | 说明 |
| --- | --- | --- |
| CODE_AGENT_FACTORY_NAME | [code_agent.py#L27](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/subagents/code_agent.py#L27) | 工厂名常量 `"code_agent"` |
| create_code_agent | [code_agent.py#L173-L277](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/subagents/code_agent.py#L173) | CodeAgent 工厂,预装必备 rails 并注入内置子代理 |
| build_code_agent_config | [code_agent.py#L121](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/subagents/code_agent.py#L121) | 构建 CodeAgent 子代理配置 |
| DEFAULT_CODE_AGENT_SYSTEM_PROMPT_CN | [code_agent.py#L30-L40](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/subagents/code_agent.py#L30) | 编码主线系统提示 |
| _inject_builtin_plan_agents | [code_agent.py#L232-L236](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/subagents/code_agent.py#L232) | 自动注入 explore_agent/plan_agent |
| create_explore_agent | [explore_agent.py#L205-L257](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/subagents/explore_agent.py#L205) | ExploreAgent 工厂,严格只读 |
| ExploreAgent 系统提示 | [explore_agent.py#L93-L125](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/subagents/explore_agent.py#L93) | 禁 write/edit/rm/mv/cp,禁 shell 重定向 |
| SysOperationRail(read_only=True) | [explore_agent.py#L192](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/subagents/explore_agent.py#L192) | ExploreAgent 的只读工具集装配 |
| create_plan_agent | [plan_agent.py#L132-L176](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/subagents/plan_agent.py#L132) | PlanAgent 工厂(详见 code-planning.md) |
| create_verification_agent | [verification_agent.py#L318-L363](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/subagents/verification_agent.py#L318) | VerificationAgent 工厂(详见 code-review.md) |
| DeepAgent.create_subagent | [deep_agent.py#L1186-L1359](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/deep_agent.py#L1186) | 按 `spec.factory_name` 分发子代理 |
| TaskTool | [task_tool.py#L55-L150](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/subagent/task_tool.py#L55) | 子代理委派工具,解析 `subagent_type + task_description` |
| SubagentRail | [subagent_rail.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/rails/subagent/subagent_rail.py) | priority=95,注册 `task_tool`/`session_spawn` |
| prepare_subagent_task_resources | [subagent_lifecycle.py#L13](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/subagent_lifecycle.py#L13) | 子代理调用前资源准备 |
| cleanup_subagent_task_resources | [subagent_lifecycle.py#L23](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/subagent_lifecycle.py#L23) | 子代理调用后资源清理 |
| _build_subagents(CLI) | [factory.py#L175](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/cli/agent/factory.py#L175) | CLI 注册 code_agent + research_agent + browser_agent |

## 三、实现机制

### 1. 四阶段子代理职责边界

| 子代理 | 工厂 | 权限边界 | 核心职责 |
| --- | --- | --- | --- |
| ExploreAgent | [explore_agent.py#L205](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/subagents/explore_agent.py#L205) | 严格只读(禁 write/edit/rm/mv/cp,禁重定向) | 定位/读取/汇报代码库信息 |
| PlanAgent | [plan_agent.py#L132](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/subagents/plan_agent.py#L132) | 纯只读(连 /tmp 建文件都禁) | 设计实现方案,产出 Critical Files |
| CodeAgent | [code_agent.py#L173](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/subagents/code_agent.py#L173) | 可写(读/写/编辑/grep/list/bash/code) | 落地可运行代码,变更小可回滚 |
| VerificationAgent | [verification_agent.py#L318](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/subagents/verification_agent.py#L318) | 对抗且零写(/tmp 可放临时脚本) | 主动破坏实现,输出 VERDICT |

边界从"只读"到"可写"再到"对抗零写",形成职责正交、目标对立的协作网。这种正交设计让每个阶段都能用最适合的工具集,而不必在"全能 agent"的单上下文中来回切换角色。

### 2. CodeAgent 的默认装配

`create_code_agent` ([code_agent.py#L173-L277](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/subagents/code_agent.py#L173)) 的关键装配逻辑:

- **预装 rails**(L238-L257):`SysOperationRail + AgentModeRail(plan/auto) + AskUserRail + ConfirmInterruptRail(switch_mode)`;
- **CodingMemoryRail 条件注入**(L248-L257):仅当 `embedding_config` 提供时,解析 `coding_memory_dir` 并追加 `CodingMemoryRail`;
- **内置子代理自动注入**(L232-L236):`_inject_builtin_plan_agents` 把 `explore_agent` 与 `plan_agent` 自动加入 `effective_subagents`,无需用户显式声明;
- **任务规划开启**(L275):`enable_task_planning=True`,激活 Todo 工具与 TaskPlan 桥接。

### 3. 委派分发与子会话隔离

主代理通过 `TaskTool` 委派子任务。`TaskTool.invoke` ([task_tool.py#L89-L150](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/subagent/task_tool.py#L89)) 流程:

```
inputs(subagent_type, task_description)
   │
   ▼
parent_session_id = parent_session.get_session_id()
sub_session_id = _build_sub_session_id(...)   # 粘性=确定性ID, 否则带随机后缀
   │
   ▼
subagent = parent_agent.create_subagent(subagent_type, sub_session_id)
   │  DeepAgent.create_subagent 按 spec.factory_name 分发:
   │   ├─ code_agent        ── 编码
   │   ├─ browser_agent      ── 浏览器
   │   ├─ research_agent     ── 研究
   │   ├─ mobile_gui_agent   ── 移动 GUI
   │   └─ 默认 deep_agent     ── 通用
   ▼
prepare_subagent_task_resources(subagent)   # 资源准备
   │
   ▼
subagent.invoke(task_description)           # 独立子会话, 上下文隔离
   │
   ▼
cleanup_subagent_task_resources(subagent)  # 资源清理
```

子会话独立是关键设计:每个子代理有自己的会话与上下文窗口,主代理只接收子代理的最终输出,避免子代理的长上下文污染主代理的决策。

### 4. 粘性会话与验证闭环

`_build_sub_session_id` ([task_tool.py#L82-L87](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/subagent/task_tool.py#L82)) 对粘性子代理类型(如 verification_agent)使用确定性 ID `{parent}_sub_{type}`,使"FAIL→修复→重新验证"循环命中同一会话,保留前轮发现;对一次性子代理注入随机后缀,确保上下文互不污染。其判定基于 `kv_cache_hooks.is_sticky_subagent_type`:

```python
normalized_type = str(subagent_type or "").strip()
if kv_cache_hooks.is_sticky_subagent_type(normalized_type):
    # 确定性 ID: 复用会话, 保留前轮发现
    return f"{parent_session_id}_sub_{normalized_type}"
# 一次性任务: 随机后缀, 上下文互不污染
return f"{parent_session_id}_sub_{normalized_type}_{uuid.uuid4().hex[:8]}"
```

这种"粘性 vs 一次性"的双轨设计,让需要上下文延续的验证闭环与需要隔离的探索任务各得其所。

### 5. CLI 注册与身份声明

CLI 入口 `_build_subagents` ([factory.py#L175](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/cli/agent/factory.py#L175)) 默认注册 `code_agent`(描述为 "software engineering/coding tasks")、`research_agent`、`browser_agent`。`IDENTITY.md` L3 声明"AI 编码代理……代码编写与修改、重构",与工厂默认配置共同确立编码主线身份。

## 四、调用示例

```python
from openjiuwen.core.foundation.store.base_embedding import EmbeddingConfig
from openjiuwen.harness.subagents.code_agent import create_code_agent
from openjiuwen.harness.subagents.verification_agent import build_verification_agent_config
from openjiuwen.harness.runner import Runner

agent = create_code_agent(
    model,
    workspace="./proj",
    enable_task_loop=True,
    # 自动注入 explore_agent / plan_agent;额外挂载 verification_agent
    subagents=[
        build_verification_agent_config(model, language="cn"),
    ],
    # 提供 embedding_config 自动激活 CodingMemoryRail
    embedding_config=EmbeddingConfig(...),
)

result = Runner.run_agent(
    agent,
    {"query": "为订单服务增加幂等键校验,探索现状后规划并实现,最后对抗验证"},
)
print(result.final_output)
# 预期: code_agent 主线自动委派 explore_agent→plan_agent→自编码→verification_agent,
# 四阶段在各自独立子会话中完成,主代理汇总最终结论。
```

## 五、业界对比

| 能力维度 | agent-core | Cursor | Claude Code | GitHub Copilot |
| --- | --- | --- | --- | --- |
| 子代理种类(探索/规划/编码/验证) | 四种,职责正交 | 无显式分类 | 部分,通用子任务 | 无 |
| 职责边界(只读/纯规划/可写/对抗) | 四档边界,系统提示固化 | 无此分层 | 无此分层 | 无 |
| 自动注入内置子代理 | 有,`_inject_builtin_plan_agents` | 无 | 无 | 无 |
| 粘性会话(验证闭环复用上下文) | 有,确定性 sub_session_id | 无 | 无 | 无 |
| 独立子会话隔离上下文 | 有,主代理仅收最终输出 | 部分 | 部分 | 无 |
| 委派工具(TaskTool/subagent_type) | 有,工厂分发 | 无 | 部分 | 无 |

## 六、小结

- agent-core 以"探索-规划-编码-验证"四阶段子代理构成编码协作体系,每个阶段有最优工具集与系统提示。
- 四个子代理职责边界从"只读→纯只读→可写→对抗零写"正交分明,目标对立以消除自评偏误。
- `create_code_agent` 一次调用即装配完整协作链:自动注入 explore/plan、条件注入 CodingMemoryRail、开启任务规划。
- 委派由 `TaskTool` + `create_subagent` 承担,按 `factory_name` 分发,子会话独立隔离上下文。
- 粘性会话让验证类子代理在"FAIL→修复→重新验证"循环中复用上下文,实现真正的迭代收敛。
