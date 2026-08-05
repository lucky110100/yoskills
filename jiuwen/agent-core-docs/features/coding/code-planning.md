# 编码任务规划与目标分解

> 交叉引用: [01-项目概述](../../01-project-overview.md) | [02-整体架构](../../02-overall-architecture.md) | [04-harness模块](../../04-harness-module.md) | [08-依赖关系](../../08-dependencies.md)

## 一、能力概述

agent-core 把"规划"从"执行"中剥离出来,交给一个纯只读的 PlanAgent 子代理。它的职责是探索代码库、识别现有架构与约定、设计可执行方案,但**严禁触碰任何文件**——既不能创建、修改、删除,也不能移动/复制,甚至连 `/tmp` 下建临时文件都被禁止。这种"只读规划"约束从架构上防止规划阶段意外改动代码,保证规划与实现两个阶段产物可分离、可审计。

规划产出有强约束:回答末尾必须给出"Critical Files for Implementation",列出 3-5 个最关键文件路径,供后续编码子代理直接锚定。规划结果会沉淀为 LLM 自主拆分的 Todo 列表,再由 `TaskPlanningRail` 在首轮迭代后桥接为 `TaskPlan`,驱动外层任务循环调度后续步骤。

在更宏观的层面,agent-core 提供了"目标(Goal)"生命周期管理:`GoalManager` 维护 session 级目标,支持 `objective / token_budget / max_attempts` 三元约束,以及 `pause / resume / begin_attempt / accumulate_usage / apply_assessment` 完整状态机。`TaskCompletionRail` 负责检测模型输出的 `<promise>…</promise>` 完成承诺标签,并依据 `COMPLETE / BLOCKED / CONTINUE` 三种评估结果驱动下一轮。这一组合实现了"目标分解 → 多轮尝试 → 预算/次数约束 → 完成判定"的闭环。

## 二、关键类与函数

| 类/函数 | 文件位置 | 说明 |
| --- | --- | --- |
| create_plan_agent | [plan_agent.py#L132-L176](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/subagents/plan_agent.py#L132) | PlanAgent 工厂,默认仅装配 `SysOperationRail` |
| PLAN_AGENT_SYSTEM_PROMPT_CN | [plan_agent.py#L32-L52](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/subagents/plan_agent.py#L32) | 纯规划约束(禁文件操作)+ Critical Files 输出要求 |
| TaskPlanningRail | [task_planning_rail.py#L31](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/rails/task_planning_rail.py#L31) | priority=90,注册 Todo 工具集,桥接 TaskPlan |
| TaskPlanningRail._sync_todos_from_plan | [task_planning_rail.py#L313-L365](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/rails/task_planning_rail.py#L313) | after_task_iteration 同步 todo 与 TaskPlan 状态 |
| TaskCompletionRail | [task_completion_rail.py#L69](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/rails/task_completion_rail.py#L69) | priority=10,完成承诺检测与目标生命周期 |
| PROMISE_TAG_PATTERN | [task_completion_rail.py#L63-L66](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/rails/task_completion_rail.py#L63) | `<promise>…</promise>` 正则,完成承诺识别 |
| GoalManager | [goal/manager.py#L46](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/goal/manager.py#L46) | session 级目标管理器 |
| GoalManager.set | [goal/manager.py#L95](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/goal/manager.py#L95) | 设置 objective / token_budget / max_attempts |
| GoalManager.pause / resume | [goal/manager.py#L164/L194](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/goal/manager.py#L164) | 目标暂停/恢复状态机 |
| GoalManager.begin_attempt | [goal/manager.py#L253](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/goal/manager.py#L253) | 记录一次尝试开始,自增 attempt_count |
| GoalManager.accumulate_usage | [goal/manager.py#L271](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/goal/manager.py#L271) | 累计 token 用量,支持预算约束 |
| GoalManager.apply_assessment | [goal/manager.py#L294](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/goal/manager.py#L294) | 提交 COMPLETE/BLOCKED/CONTINUE 评估 |
| GoalRecord | [goal/schema.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/goal/schema.py) | 支持 max_attempts + token_budget 的目标记录 |

## 三、实现机制

### 1. 纯规划约束的硬性化

PlanAgent 的系统提示 ([plan_agent.py#L32-L52](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/subagents/plan_agent.py#L32)) 把只读边界固化为白名单式禁令:

- 禁止 Write/touch/编辑/rm/mv/cp;
- 禁止在 `/tmp` 创建临时文件;
- 禁止重定向或管道写文件(`>`、`>>`、`|`);
- bash 仅允许只读命令(ls/git status/git log/git diff/find/grep/cat/head/tail);
- 严禁 `mkdir/touch/rm/cp/mv/git add/git commit/npm install/pip install`。

输出侧同样有硬约束:末尾必须给出"Critical Files for Implementation",列出 3-5 个最关键文件路径。该列表是后续编码子代理的"锚点",使规划产物具备可机器消费的结构。系统提示原文片段如下:

```
=== 关键约束:只读模式,禁止任何文件修改 ===
- 创建文件(如 Write、touch 或任何形式的新建文件)
- 修改文件(任何编辑操作)
- 删除文件(如 rm)
- 移动/复制文件(如 mv、cp)
- 在任意目录(含 /tmp)创建临时文件
- 使用重定向或管道将内容写入文件(>, >>, |)
```

### 2. 目标分解的三层机制

agent-core 的目标分解并非单一手段,而是三层叠加:

```
用户 query
   │  TaskCompletionRail.before_task_iteration
   ▼
<goal_task> XML(task_instruction / build_goal_task_query 生成)
   │  LLM 在 ReAct 循环中自主拆分
   ▼
Todo 列表(TodoCreateTool/TodoListTool/TodoModifyTool/TodoGetTool)
   │  TaskPlanningRail.after_task_iteration 首轮后桥接
   ▼
TaskPlan(结构化任务,供外层 loop 调度后续步骤)
```

- **目标注入**:`TaskCompletionRail.before_task_iteration` 用 `task_instruction` 模板与 `build_goal_task_query` 生成 `<goal_task>` XML,把高层目标传递给模型。
- **LLM 自主拆分**:`TaskPlanningRail` 注册 Todo 工具集,由模型在 ReAct 循环中自主决定拆分粒度与顺序。
- **状态桥接**:首轮迭代后,`_sync_todos_from_plan` ([task_planning_rail.py#L313-L365](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/rails/task_planning_rail.py#L313)) 把 todo 文件状态与 `TaskPlan` 对齐,避免"TaskPlan 已完成但 todo 仍 in_progress"的冲突。

### 3. 目标状态机

`GoalManager` 维护一个 session 级目标状态机,关键流转:

| 操作 | 入口 | 语义 |
| --- | --- | --- |
| set | [L95](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/goal/manager.py#L95) | 设置 objective/token_budget/max_attempts,已有 ACTIVE 目标会被取消 |
| pause | [L164](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/goal/manager.py#L164) | 暂停,允许在飞 attempt 自然完成 |
| resume | [L194](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/goal/manager.py#L194) | 从 PAUSED/BLOCKED 恢复为 ACTIVE |
| begin_attempt | [L253](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/goal/manager.py#L253) | 记录一次尝试开始,`attempt_count += 1` |
| accumulate_usage | [L271](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/goal/manager.py#L271) | 累计 input/output/cached token,支撑预算约束 |
| apply_assessment | [L294](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/goal/manager.py#L294) | 提交 COMPLETE/BLOCKED/CONTINUE 评估 |

当 `apply_assessment` 返回 CONTINUE 时,`_ensure_goal_work_locked` 在目标仍 ACTIVE 时排队下一轮,形成"评估→续跑"的闭环;COMPLETE 则收尾;BLOCKED 则暂停等待人工介入。目标评估的三种结果驱动后续编排:

| 评估结果 | 后续行为 |
| --- | --- |
| COMPLETE | 目标收尾,停止后续轮次 |
| BLOCKED | 暂停等待人工介入,可由 resume 恢复 |
| CONTINUE | 目标仍 ACTIVE,排队下一轮继续执行 |

注意:BLOCKED 与 PAUSED 不同——PAUSED 允许在飞 attempt 自然完成,BLOCKED 则需人工解除阻塞后由 resume 恢复。

### 4. 完成承诺检测

`TaskCompletionRail` 通过 `PROMISE_TAG_PATTERN` ([task_completion_rail.py#L63-L66](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/rails/task_completion_rail.py#L63)) 识别 `<promise>…</promise>` 标签。`CompletionPromiseEvaluator` 校验承诺 token 是否匹配 `completion_promise` 配置,只有命中才算任务完成,避免模型在未真正完成时草草收尾。

该 Rail 还在 `before_task_iteration` 应用 `task_instruction` 模板,把用户原始 query 包装成结构化目标指令注入模型,使每轮迭代都锚定当前目标而非发散;`required_confirmations` 可要求多次确认以提升完成判定的可信度。

### 5. 预算与次数约束

`GoalRecord` 同时支持 `max_attempts`(最大尝试次数)与 `token_budget`(token 预算)。每次 `begin_attempt` 自增 attempt_count,`accumulate_usage` 累加 token;超限后即使未 COMPLETE 也会被强制停止,从机制上防止任务失控。

## 四、调用示例

```python
from openjiuwen.harness.subagents.code_agent import create_code_agent
from openjiuwen.harness.runner import Runner

agent = create_code_agent(
    model,
    workspace="./proj",
    enable_task_loop=True,   # 启用外层任务循环,激活 TaskPlanningRail/TaskCompletionRail
)

result = Runner.run_agent(
    agent,
    {"query": "重构 auth 模块,添加 JWT 刷新令牌支持"},
)
print(result.final_output)
# 预期流程:
# 1) 主代理委派 plan_agent 进行纯只读规划,产出 Critical Files 与实现步骤;
# 2) LLM 自主拆分为 Todo 列表,TaskPlanningRail 桥接为 TaskPlan;
# 3) 外层循环按 TaskPlan 调度编码步骤,GoalManager 跟踪 attempt/token;
# 4) 模型输出 <promise>...</promise> 后 TaskCompletionRail 判定完成。
```

## 五、业界对比

| 能力维度 | agent-core | Cursor | Claude Code | GitHub Copilot |
| --- | --- | --- | --- | --- |
| 独立规划子代理 | 有,PlanAgent 与执行者分离 | 无独立规划 agent | 无独立规划 agent | 无 |
| 纯规划约束(禁改文件) | 强制,系统提示固化 | 无此约束 | 无此约束 | 无此约束 |
| Critical Files 输出 | 有,3-5 个关键文件锚点 | 无 | 无 | 无 |
| Todo 工具集成 | 有,首轮后桥接 TaskPlan | 有 todo,无桥接 | 有 todo,无桥接 | 无 |
| 目标状态机(COMPLETE/BLOCKED) | 有,GoalManager 三态 | 无 | 无 | 无 |
| token 预算 + 尝试次数约束 | 有,双重约束 | 无 | 无 | 无 |
| 完成承诺检测 | 有,`<promise>` 标签 | 无 | 无 | 无 |

## 六、小结

- agent-core 把规划独立为纯只读 PlanAgent,从架构上保证规划阶段零代码改动、产物可审计。
- 规划输出强约束"Critical Files for Implementation",使规划结果可被编码子代理直接锚定消费。
- 目标分解采用三层叠加:目标注入 XML → LLM 自主 Todo 拆分 → TaskPlanningRail 桥接 TaskPlan。
- GoalManager 提供完整目标状态机(pause/resume/begin_attempt/accumulate_usage/apply_assessment),并以 token_budget + max_attempts 双重约束防止失控。
- TaskCompletionRail 通过 `<promise>` 标签检测完成承诺,确保任务"真完成"而非草草收尾。
