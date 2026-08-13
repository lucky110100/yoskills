# 07 可观测性 observability

> 维度归属：C 运行时质量组。评估日志、指标、追踪三大支柱与告警/错误聚合。
>
> 配套：[汇总评分卡](../project-health.md) | [索引](README.md)

## 评分：4 / 4

对照 4 分档「日志结构化+级别分明+关联ID+指标完整(RED/USE)+分布式追踪+告警规则+错误聚合+健康检查」。项目有结构化轮转日志（4 文件 + RedactingFormatter + session_tag 关联ID）、16 个 OTLP 指标、OTLP traces（lifecycle/cron execution）、OTLP logs（diagnostics）、PromQL 告警示例、errors.log 错误聚合、readiness 健康探针、systemd watchdog、内存监控、Langfuse 插件、SharedMetricsStore（SQLite + JSON schema）。唯一未满的是「分布式追踪」范围——OTLP traces 只覆盖 gateway lifecycle 与 cron execution，未覆盖 per-API-call/per-tool-call 的 span；指标以 gauge 为主缺 latency histogram。但整体广度远超 3 分档。

## 评估过程

### 关键问题（带 file:/// 证据）

1. **分布式追踪范围有限** — 16 个指标全是 `create_observable_gauge`（状态/计数），无 histogram/summary（无延迟分布）→ [gateway_health_export.py](file:///D:\yaodh\main\hermes-agent\agent\monitoring\gateway_health_export.py#L434-L468)；traces 走 `/v1/traces` 但仅限 `gateway.lifecycle`/`gateway.health_snapshot`/平台状态变更与 `hermes.cron_execution` span——agent 的每次 LLM 调用/工具调用不产 span，跨 delegate_task 子代理无 trace context 传播。

2. **session_id 关联是 thread-local，非 OTLP traceId** — `set_session_context` 写入 `threading.local()`，子代理/async delegation 跨线程/跨进程时 session_tag 不自动传播 → [hermes_logging.py](file:///D:\yaodh\main\hermes-agent\hermes_logging.py#L165-L210)。

3. **OTLP SDK 非核心依赖** — `otlp` 是 optional extra，`_require_metrics_sdk` 失败即 fail-open 不导出——开箱默认无指标 → [pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L270-L274)、[gateway_health_export.py](file:///D:\yaodh\main\hermes-agent\agent\monitoring\gateway_health_export.py#L184-L219)。

### 亮点

- ✅ **结构化轮转日志 + 脱敏** — `setup_logging` 产 `agent.log`(INFO+)/`errors.log`(WARNING+)/`gateway.log`/`gui.log`，用 `RedactingFormatter` 保证 secret 不落盘；Windows 用 `ConcurrentRotatingFileHandler` 避免 WinError 32 → [hermes_logging.py](file:///D:\yaodh\main\hermes-agent\hermes_logging.py#L1-L86)。
- ✅ **关联 ID** — `set_session_context(session_id)` + record factory 注入 `session_tag`，所有日志行带 `[session_id]` → [hermes_logging.py](file:///D:\yaodh\main\hermes-agent\hermes_logging.py#L165-L210)。
- ✅ **16 个 OTLP 指标** — `hermes.gateway.up/state/active_agents/busy/drainable/background_work/background_delegations/restart_requested` + `hermes.platform.up/degraded` + `hermes.cron.scheduler.heartbeat_age_seconds/last_success_age_seconds/catch_up_occurrences` + `hermes.cron.jobs.enabled/running/overdue` → [gateway_health_export.py](file:///D:\yaodh\main\hermes-agent\agent\monitoring\gateway_health_export.py#L437-L454)。
- ✅ **告警规则文档化** — 给出 PromQL 示例（`hermes_gateway_up == 0`、`absent_over_time(...[5m])`、`hermes_cron_scheduler_heartbeat_age_seconds > 180`、`hermes_cron_jobs_overdue > 0` 等）→ [monitoring.md](file:///D:\yaodh\main\hermes-agent\docs\observability\monitoring.md#L107-L130)。
- ✅ **健康探针** — `collect_runtime_readiness` 探测 state_db（只读 schema 查询）/config/model/disk(>90% degraded)/gateway/background_queues，用 `mode=ro` + `query_only=ON` 不争抢写锁 → [readiness.py](file:///D:\yaodh\main\hermes-agent\gateway\readiness.py#L89-L122)。
- ✅ **错误聚合** — `errors.log` 仅 WARNING+ → [hermes_logging.py](file:///D:\yaodh\main\hermes-agent\hermes_logging.py#L9-L10)；`GatewayDiagnosticEvent` 带 `error_class/error_code/severity` 走 OTLP logs → [events.py](file:///D:\yaodh\main\hermes-agent\agent\monitoring\events.py#L45-L63)。
- ✅ **systemd watchdog** — 解析 `WATCHDOG_USEC` 并喂狗，事件循环卡顿时 supervisor 重启 → [systemd_notify.py](file:///D:\yaodh\main\hermes-agent\gateway\systemd_notify.py#L42-L80)。
- ✅ **内存监控** — 周期 `[MEMORY]` 行记 RSS + GC counts → [memory_monitor.py](file:///D:\yaodh\main\hermes-agent\gateway\memory_monitor.py#L52-L100)。
- ✅ **共享指标 SQLite 存储 + schema** — `SharedMetricsStore` 落盘 + outbox，有 JSON schema 约束 → [shared_metrics.py](file:///D:\yaodh\main\hermes-agent\hermes_cli\observability\shared_metrics.py#L47-L80)。
- ✅ **LLM 追踪插件生态** — Langfuse 与 nemo_relay 提供 opt-in 的 LLM 级 trace → [langfuse/README.md](file:///D:\yaodh\main\hermes-agent\plugins\observability\langfuse\README.md)；moa_trace 持久化 MoA 每 turn 全量参考/聚合输入输出 → [moa_trace.py](file:///D:\yaodh\main\hermes-agent\agent\moa_trace.py#L1-L58)。

## Checklist 对照

- [x] 日志是否结构化 + 级别分明 — ✅ 4 文件分级 + RedactingFormatter
- [x] 是否有关联 ID/traceId — ✅ session_tag（thread-local）
- [ ] 是否采集 RED/USE 指标 — ⚠️ 16 gauge 指标，缺 latency histogram
- [ ] 是否接入分布式追踪 — ⚠️ 仅 lifecycle/cron span，无 per-call span
- [x] 是否有告警规则与错误聚合 — ✅ PromQL 示例 + errors.log + OTLP logs
- [x] 是否有健康检查端点 — ✅ readiness 探针

## 改进建议

1. 给 agent 主循环的每次 LLM 调用/工具调用发 OTLP span（带 parent span context），让 `delegate_task` 子代理继承 traceId，实现真正的端到端分布式追踪。
2. 加 latency histogram（`hermes.llm.latency_ms`、`hermes.tool.latency_ms`）补 RED/USE 的 Duration 维度。
3. 把 `set_session_context` 改为 `contextvars.ContextVar` 以便跨 async 任务传播。
4. OTLP SDK 进 `[all]` 或在首次配置 `monitoring.export.otlp.enabled=true` 时自动 lazy install。
