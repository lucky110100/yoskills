# cron 模块

> 交叉引用: [01-项目概述](01-project-overview.md) | [02-整体架构](02-overall-architecture.md) | [05-gateway模块](05-gateway-module.md) | [06-hermes-cli模块](06-hermes-cli-module.md)

## 一、模块概述

`cron/` 是 Hermes 的定时任务子系统，提供任务存储（jobs.json）、调度循环（tick）、执行审计账本（executions.db SQLite）、生命周期守卫（lifecycle_guard）与监控（monitor）。它严格按 profile 隔离：每个 profile 在自己的 `HERMES_HOME/cron/` 下拥有独立的 `jobs.json`、`.jobs.lock`、`executions.db`，并按该 profile 的 `.env`/`config.yaml`/skills 执行任务——这是安全边界的设计。

调度用"网关每 60 秒调用 tick + 跨进程文件锁"实现单点执行：`tick` 抢 `.tick.lock`（fcntl/msvcrt），抢不到即返回 0；执行态用 SQLite 账本记录 `claimed/running/completed/failed/unknown`，终态不可变，中断态仅在 owner 进程被证明确实死亡后才转 `unknown`。`lifecycle_guard` 防御 agent 自我重启循环——拒绝会触发 `hermes gateway restart`/launchctl/systemctl/pkill 等网关生命周期的 cron 任务在创建时通过。

## 二、关键类与函数

| 名称 | 类型 | 文件位置 | 说明 |
|------|------|----------|------|
| _CronStorePaths | dataclass | [jobs.py](file:///D:\yaodh\main\hermes-agent\cron\jobs.py#L120) | Cron 存储路径三元组（cron_dir/jobs_file/output_dir） |
| _current_cron_store | 函数 | [jobs.py](file:///D:\yaodh\main\hermes-agent\cron\jobs.py#L139) | 按优先级解析当前 profile 的存储路径 |
| use_cron_store | ctx mgr | [jobs.py](file:///D:\yaodh\main\hermes-agent\cron\jobs.py#L171) | 把 cron 存储临时路由到指定 home 而不污染进程全局 |
| _jobs_lock | ctx mgr | [jobs.py](file:///D:\yaodh\main\hermes-agent\cron\jobs.py#L271) | 串行化 load→modify→save 关键段；线程锁 + 跨进程文件锁 |
| save_jobs | 函数 | [jobs.py](file:///D:\yaodh\main\hermes-agent\cron\jobs.py#L1383) | 持久化任务列表到 jobs.json |
| list_jobs | 函数 | [jobs.py](file:///D:\yaodh\main\hermes-agent\cron\jobs.py#L1842) | 列出任务，可含禁用项 |
| tick | 函数 | [scheduler.py](file:///D:\yaodh\main\hermes-agent\cron\scheduler.py#L4891) | 检查并执行到期任务；文件锁防重叠 |
| run_job | 函数 | [scheduler.py](file:///D:\yaodh\main\hermes-agent\cron\scheduler.py#L3226) | 执行单个任务；支持 no_agent 短路 |
| _set_cron_session_title | 函数 | [scheduler.py](file:///D:\yaodh\main\hermes-agent\cron\scheduler.py#L64) | 关闭前稳健写入会话标题 |
| create_execution | 函数 | [executions.py](file:///D:\yaodh\main\hermes-agent\cron\executions.py#L135) | 在 SQLite 账本登记一次执行尝试，status=claimed |
| recover_interrupted_executions | 函数 | [executions.py](file:///D:\yaodh\main\hermes-agent\cron\executions.py#L199) | 重启后回收中断态：仅当 owner 进程被证实死亡才转 unknown |
| _transaction | ctx mgr | [executions.py](file:///D:\yaodh\main\hermes-agent\cron\executions.py#L66) | 带锁的 SQLite 事务 |
| check_gateway_lifecycle | 函数 | [lifecycle_guard.py](file:///D:\yaodh\main\hermes-agent\cron\lifecycle_guard.py#L665) | 创建任务时扫描 prompt+script 是否含网关生命周期命令 |
| contains_gateway_lifecycle_command | 函数 | [lifecycle_guard.py](file:///D:\yaodh\main\hermes-agent\cron\lifecycle_guard.py#L98) | 正则匹配 `hermes gateway restart`、launchctl/systemctl/pkill |

## 三、实现机制

### 3.1 Per-profile 存储隔离 + ContextVar 路由

`_current_cron_store` 用 ContextVar 优先级解析（override → 模块常量 → 活跃 home），让多 profile 同进程也不串读 jobs.json。`use_cron_store` ctx mgr 在不污染进程全局的前提下临时重定向。

### 3.2 双层锁（线程锁 + 跨进程文件锁）

`_jobs_lock` 在线程 RLock 外再套 fcntl/msvcrt 文件锁，使网关并行 tick 线程与独立 CLI 调用互斥；可重入深度计数避免 legacy 调用嵌套死锁：

```python
@contextlib.contextmanager
def _jobs_lock():
    depth = getattr(_jobs_lock_state, "depth", 0)
    if depth:
        _jobs_lock_state.depth = depth + 1
        try:
            yield
        finally:
            _jobs_lock_state.depth -= 1
        return
    # ... 获取线程锁 + 跨进程文件锁
```

### 3.3 不可变终态 + Owner 证死回收

`executions.db` 的 `completed/failed/unknown` 终态不可变，`claimed/running` 仅在 owner pid 的 `process_started_at` 证实进程已死时才转 `unknown`，避免误杀仍在跑的任务。

### 3.4 命令形状锚定的防御性拒绝

`_GATEWAY_LIFECYCLE_PATTERN` 用具体命令标识符（`hermes\s+gateway`、`launchctl`、`systemctl`、`pkill`）锚定，而非英文子串，避免在 prose 上误报；并折叠 POSIX 行续接 `\` 后再匹配。

## 四、调用示例

```python
from cron.jobs import list_jobs, save_jobs, CronJob

# 列出当前 profile 的所有 cron 任务
jobs = list_jobs(include_disabled=True)
for job in jobs:
    print(f"{job.id}: {job.name} schedule={job.schedule} enabled={job.enabled}")

# 创建新任务
from cron.scheduler import schedule_job
schedule_job(
    name="每日简报",
    schedule="0 9 * * *",  # 每天 9:00
    prompt="生成今日简报",
    profile="default",
)

from cron.executions import recover_interrupted_executions
# 网关重启后回收中断态执行
recovered = recover_interrupted_executions()
print(f"回收 {recovered} 个中断任务")
```

## 五、小结

1. 严格 per-profile 隔离：每个 profile 独立 jobs.json/.jobs.lock/executions.db
2. 双层锁（线程 RLock + 跨进程文件锁）防网关 tick 与 CLI 调用竞态
3. SQLite 账本记录不可变终态，中断态仅 Owner 证死后才转 unknown
4. `lifecycle_guard` 防御 agent 自我重启循环，拒绝网关生命周期命令在 cron 任务中
5. `tick` 由网关每 60 秒调用，文件锁防重叠执行
