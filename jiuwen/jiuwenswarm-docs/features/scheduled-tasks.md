# 定时任务

> 交叉引用: [01-项目概述](../01-project-overview.md) | [02-整体架构](../02-overall-architecture.md) | [04-gateway与channels](../04-gateway-and-channels-module.md) | [03-agents与swarm](../03-agents-and-swarm-module.md) | [特性索引](README.md)

## 一、能力概述

JiuwenSwarm 的定时任务子系统位于 `gateway/cron/`,提供基于 cron 表达式的定时调度能力,支持 5-field 与 7-field(Quartz 风格)两种表达式,经 `normalize_cron_expr` 统一规范化为 7-field 后由 `croniter` 计算下次触发时刻。

系统采用"堆式异步事件队列"而非轮询:调度器维护一个按触发时刻排序的最小堆,每个堆节点是一个 `_Event`(wake/push/push_update 三种类型),调度循环只 `await` 到最近一个事件就绪,而非每秒扫描全部任务,从而在大规模任务下保持低 CPU 开销与精确触发。

执行形态分三种:**unary**(单次执行,直接调用单个 Agent)、**team streaming**(消费 SwarmFlow 事件流,带超时与 AgentServer cancel 能力,支持团队协作产出)、**proactive.tick**(主动轮询触发)。三者覆盖了"单 Agent 定时产出""团队定时协作""主动探测"三类场景。

持久化由 `CronJobStore` 以 `cron_jobs.json` 单文件 + `portalocker` 跨进程文件锁承载,并通过文件 mtime 轮询感知外部变更(如人工编辑文件),实现崩溃恢复与多进程协调。执行结果经 `_push_to_targets` 按目标渠道解析 metadata 推送——飞书按 `last_chat_id`、钉钉按 `staff_id`、小艺按 `session_id` 路由。团队级定时任务的"轮次是否结束"由 `cron_team_completion` 状态机(leader final/workflow/open_tasks)判定。

## 二、关键类与函数

| 类/函数 | 文件位置 | 说明 |
| --- | --- | --- |
| CronController | [controller.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/cron/controller.py#L25) | 单例 CRUD API,校验 cron_expr/work_mode/project |
| CronSchedulerService | [scheduler.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/cron/scheduler.py#L249) | 堆式异步调度器:wake/push/push_update 事件循环 |
| _Event | [scheduler.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/cron/scheduler.py#L241) | 调度事件数据类(最小堆节点) |
| _cron_next_push_dt | [scheduler.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/cron/scheduler.py#L221) | croniter 计算下次 push 时刻(5/7-field) |
| _run_unary_cron_job | [scheduler.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/cron/scheduler.py#L1140) | unary 执行:直接调用单 Agent |
| _run_team_stream_job | [scheduler.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/cron/scheduler.py#L1187) | team streaming 执行:消费 SwarmFlow 事件流,带超时+cancel |
| _push_to_targets | [scheduler.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/cron/scheduler.py#L1372) | 推送结果至目标渠道,按渠道解析 metadata |
| CronJob | [models.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/cron/models.py#L236) | 持久化任务:cron_expr/work_mode/targets/project |
| CronTargetChannel | [models.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/cron/models.py#L14) | 目标渠道枚举(飞书/钉钉/小艺…) |
| CronRunState | [models.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/cron/models.py#L443) | 运行状态:当前轮次/上下文 |
| CronJobStore | [store.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/cron/store.py#L117) | 文件持久化:cron_jobs.json + portalocker 锁 |
| normalize_cron_expr | [cron_expr.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/cron/cron_expr.py#L12) | 5-field→7-field 规范化 |
| validate_cron_expression | [cron_expr.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/cron/cron_expr.py#L52) | 校验表达式合法性(含 timezone) |
| encode_dingtalk_cron_session_id | [dingtalk_routing.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/cron/dingtalk_routing.py#L44) | 钉钉会话路由编码 |
| build_cron_tools | [runtime_tools.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/providers/runtime_tools.py#L75) | 每成员 cron 工具(scope 到 team_member_<id>) |
| cron_team_round_should_end | [cron_team_completion.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/cron_team_completion.py#L117) | leader final/workflow/open_tasks 状态机判断团队轮次结束 |

## 三、实现机制

### 3.1 堆式异步事件队列

调度器不轮询全表,而是维护按触发时刻排序的最小堆。调度循环如下:

```text
[1] 取堆顶 _Event(触发时刻最早)
[2] await 到该事件就绪(而非 sleep 固定秒数)
[3] 按 _Event.type 分发:
       wake        → 唤醒,重新计算下次触发时刻
       push        → 执行任务并推送结果
       push_update → 更新已调度事件(如任务被修改)
[4] _cron_next_push_dt 用 croniter 算下次触发时刻
[5] 新 _Event 入堆,循环回到 [1]
```

`_Event` 的三种类型覆盖了"唤醒重算""执行推送""更新已调度"三类语义。`_cron_next_push_dt` 支持 5/7-field 表达式,经 `normalize_cron_expr` 规范化后由 croniter 算出精确下次时刻。这种设计使调度开销与"就绪事件数"成正比,而非与"总任务数"成正比,大规模任务下仍保持低 CPU 占用与精确触发。

### 3.2 三种执行形态

- **unary**:由 `_run_unary_cron_job` 执行,直接调用单个 Agent 完成一次产出,适用于"定时让某 Agent 做一件事"的场景。
- **team streaming**:由 `_run_team_stream_job` 执行,消费 SwarmFlow 事件流。它带超时控制,超时时通过 AgentServer cancel 终止;团队协作产出经流式消费汇总。适用于"定时让一个团队协作完成产出"的场景。
- **proactive.tick**:主动轮询触发,适用于"定时主动探测"场景。

### 3.3 持久化与崩溃恢复

`CronJobStore` 以 `cron_jobs.json` 单文件承载全部任务,通过 `portalocker` 跨进程文件锁保证并发写入安全。调度器额外轮询文件 mtime 感知外部变更——当人工直接编辑 `cron_jobs.json` 时,mtime 变化触发调度器重新加载,无需重启进程。崩溃后重启时,调度器从文件重建堆并补算错过(或按策略跳过)的触发,实现崩溃恢复。

### 3.4 目标渠道推送

`_push_to_targets` 按目标渠道解析 metadata 路由结果,各渠道路由键如下:

| 渠道 | CronTargetChannel | 路由键 | 说明 |
| --- | --- | --- | --- |
| 飞书 | FEISHU | last_chat_id | 路由到最近会话 |
| 钉钉 | DINGTALK | staff_id | 经 encode_dingtalk_cron_session_id 编码 |
| 小艺 | XIAOYI | session_id | 按 session 路由 |

`CronTargetChannel` 枚举定义全部支持的渠道类型,`encode_dingtalk_cron_session_id` 负责钉钉会话标识的编码,使定时产出能精准投递到发起会话的用户。

### 3.5 团队完成判定

团队级定时任务(team)的"一轮协作是否结束"由 `cron_team_round_should_end` 状态机判定。它综合 leader final 事件、workflow 完成信号、open_tasks 是否清空三方面(`apply_cron_team_round_event` 持续更新状态),决定何时收束本轮并触发结果推送。这避免了团队流"无休止运行"或"提前截断"两类问题。

### 3.6 CRUD 与校验链路

`CronController` 是面向调用方的单例 CRUD API,在写入前完成三重校验:

| 校验项 | 校验函数/字段 | 失败处理 |
| --- | --- | --- |
| cron 表达式 | validate_cron_expression | 拒绝创建 |
| work_mode | 取 unary/team_stream/proactive.tick | 拒绝非法模式 |
| project | project 字段 | 拒绝空项目 |

校验通过后,`CronJob` 经 `CronJobStore` 落盘,`CronSchedulerService` 经 mtime 轮询感知变更并重建堆。`build_cron_tools` 则把 cron 管理能力以工具形式注入每个团队成员,scope 限定到 `team_member_<id>`,使成员只能管理自己 scope 的任务,避免越权。

## 四、调用示例

### 4.1 校验并规范化 cron 表达式

```python
# 1. 校验并规范化 cron 表达式(5-field 自动转 7-field)
from jiuwenswarm.gateway.cron.cron_expr import (
    normalize_cron_expr, validate_cron_expression,
)
cron7 = normalize_cron_expr("0 9 * * 1-5")  # 工作日 09:00
validate_cron_expression(cron7, timezone="Asia/Shanghai")
```

### 4.2 经 CronController 创建团队级任务

```python
# 2. 经 CronController 创建任务(CRUD API + 校验)
from jiuwenswarm.gateway.cron.controller import CronController
ctrl = CronController.get_instance()
job = ctrl.create_cron_job(
    cron_expr=cron7,
    work_mode="team_stream",
    project="myproj",
    targets=[{"channel": "feishu", "metadata": {"last_chat_id": "oc_xxx"}}],
)

# 3. 调度器自动入堆,到点后 _run_team_stream_job 消费 SwarmFlow 事件流
#    团队协作完成后 cron_team_round_should_end 判定轮次结束
#    _push_to_targets 把结果按 last_chat_id 推回飞书会话
```

### 4.3 为团队成员注入 cron 工具

```python
# 4. 团队成员的 cron 工具由 build_cron_tools 注入,scope 到 team_member_<id>
from jiuwenswarm.agents.swarm.providers.runtime_tools import build_cron_tools
tools = build_cron_tools(params, ctx)
# 每成员可管理自己 scope 的 cron,互不越权
```

## 五、业界对比

| 维度 | JiuwenSwarm | APScheduler | n8n | Celery beat |
| --- | --- | --- | --- | --- |
| 表达式 | 5/7-field Quartz(croniter) | 5/7-field | cron + 间隔混合 | 5-field crontab |
| 事件队列 | 堆式异步(wake/push/push_update) | 轮询+线程池 | 轮询触发器 | 轮询+消息队列 |
| 执行形态 | unary/team streaming/proactive.tick | 三触发器 | 节点工作流 | 任务函数 |
| 持久化 | cron_jobs.json + portalocker + mtime 轮询 | 多种 backend | DB | DB/Redis |
| 团队流 | SwarmFlow 事件流 + 团队完成状态机 | 无 | 工作流(非实时流) | 无 |

JiuwenSwarm 的差异化在于"堆式调度 + 团队流 + 多渠道路由"三位一体:堆式异步事件队列在大规模任务下仍精确低开销;team streaming 直接消费 SwarmFlow 事件流(带超时+cancel),把"定时触发团队协作"作为一等公民;`_push_to_targets` 按渠道解析 metadata 路由,使定时产出直达飞书/钉钉/小艺会话。`cron_team_completion` 状态机则解决了团队流何时收束的难题——这是多数调度器不涉及的领域。

## 六、小结

1. JiuwenSwarm 定时任务子系统的核心是"堆式事件队列 + 三种执行形态 + 文件持久化 + 多渠道路由",位于 `gateway/cron/`。
2. `CronSchedulerService` 以最小堆 `await` 代替轮询,`_Event`(wake/push/push_update)驱动,`_cron_next_push_dt` 用 croniter 精确算下次时刻,保证精确触发与低开销。
3. 三种执行形态:unary(单 Agent)、team streaming(消费 SwarmFlow 事件流,带超时+AgentServer cancel)、proactive.tick(主动探测)。
4. `CronJobStore` 经 `cron_jobs.json` + `portalocker` 锁 + mtime 轮询实现持久化、外部变更感知与崩溃恢复。
5. `_push_to_targets` 按渠道 metadata 路由——飞书 `last_chat_id`、钉钉 `staff_id`(经 `encode_dingtalk_cron_session_id`)、小艺 `session_id`。
6. `cron_team_round_should_end` 状态机综合 leader final/workflow/open_tasks 判定团队轮次收束,解决团队流何时结束的难题,这是多数调度器不涉及的领域。
