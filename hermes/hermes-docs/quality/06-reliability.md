# 06 可靠性 reliability（否决项）

> 维度归属：C 运行时质量组。**否决项：本维度=0 即整体计 1 否决。** 本项目=4，不触发否决。
>
> 配套：[汇总评分卡](../project-health.md) | [索引](README.md)

## 评分：4 / 4（不触发否决）

对照 4 分档「重试+超时+熔断+限流+幂等+混沌测试+异常分类处理」。项目在重试（jittered backoff + Retry-After 解析）、超时（per-call + inactivity + claim TTL）、多形态熔断（cross-session breaker + failure_limit + block_recurrence + tool_loop hard_stop + 压缩 anti-thrash）、限流（nous_rate_guard + semaphore + max_concurrent_children）、幂等（file lock with epoch + CAS guard）、异常分类（25+ FailoverReason 枚举 + ClassifiedError 恢复提示）全部有落地；混沌测试以 stress/ 中的 race/property fuzzing 替代。唯一瑕疵是 `except ... : pass` 散布（313 处），但绝大多数在防御性 cleanup 路径，不构成异常全吞。

## 评估过程

### 关键问题（带 file:/// 证据）

1. **`except ...: pass` 模式散布 313 处** — 个别是真实吞错：azure_identity_adapter.py 在环境变量探测路径 → [azure_identity_adapter.py](file:///D:\yaodh\main\hermes-agent\agent\azure_identity_adapter.py#L380-L383)；background_review.py 在 review agent close/unregister 路径吞所有异常，虽属 cleanup，但无 `logger.debug` 痕迹 → [background_review.py](file:///D:\yaodh\main\hermes-agent\agent\background_review.py#L682-L683)。

2. **`tenacity` 声明但未用** — 自研 retry_utils.py 的 `jittered_backoff` 没有 tenacity 的 `stop_after_delay` / `wait_random_exponential` 等成熟策略，极端场景下退避策略偏简单 → [retry_utils.py](file:///D:\yaodh\main\hermes-agent\agent\retry_utils.py#L90-L128)。

3. **压力测试虽存在但默认不跑** — race/property fuzzing 这类容错验证不会在 PR 阶段执行，可靠性回归靠人工 → [conftest.py](file:///D:\yaodh\main\hermes-agent\tests\stress\conftest.py#L13-L22)。

### 亮点

- ✅ **重试**：`jittered_backoff` 用进程级单调 counter + time_ns 异或做 seed 防多线程雷鸣 → [retry_utils.py](file:///D:\yaodh\main\hermes-agent\agent\retry_utils.py#L90-L128)；`parse_retry_after_seconds` 同时解析数字与 HTTP-date → [retry_utils.py](file:///D:\yaodh\main\hermes-agent\agent\retry_utils.py#L38-L87)；`adaptive_rate_limit_backoff` 对 Z.AI GLM-5.2 过载用 30→60→90→120s 阶梯退避 → [retry_utils.py](file:///D:\yaodh\main\hermes-agent\agent\retry_utils.py#L162-L191)。
- ✅ **异常分类**：`FailoverReason` 枚举 25+ 类（auth/billing/rate_limit/overloaded/timeout/ssl/context_overflow/payload_too_large/model_not_found/content_policy 等），`ClassifiedError` 带 `retryable/should_compress/should_rotate_credential/should_fallback` 恢复提示 → [error_classifier.py](file:///D:\yaodh\main\hermes-agent\agent\error_classifier.py#L24-L99)。
- ✅ **单次恢复守卫**：`TurnRetryState` 把 ~16 个 `*_attempted` 布尔收进 dataclass，确保同一 attempt 内每条恢复分支最多触发一次 → [turn_retry_state.py](file:///D:\yaodh\main\hermes-agent\agent\turn_retry_state.py#L32-L80)。
- ✅ **跨会话限流/熔断**：`nous_rate_guard` 用共享文件让所有会话先查 429 状态再发请求，消除重试放大 → [nous_rate_guard.py](file:///D:\yaodh\main\hermes-agent\agent\nous_rate_guard.py#L1-L11)；`is_genuine_nous_rate_limit` 区分账号级 429 与上游瞬时 429 → [conversation_loop.py](file:///D:\yaodh\main\hermes-agent\agent\conversation_loop.py#L4920-L4971)。
- ✅ **ESTOP 紧急停止**：`is_engaged` 对 stat 错误 fail-safe（报为 engaged）→ [estop.py](file:///D:\yaodh\main\hermes-agent\agent\estop.py#L59-L72)。
- ✅ **迭代预算**：线程安全计数器（parent 500/subagent 50），`refund` 让 execute_code 不吃预算 → [iteration_budget.py](file:///D:\yaodh\main\hermes-agent\agent\iteration_budget.py#L17-L60)。
- ✅ **Cron 不活动超时 + 心跳**：默认 600s inactivity timeout + `request_hard_interrupt` + `heartbeat_run_claim_if_due` → [scheduler.py](file:///D:\yaodh\main\hermes-agent\cron\scheduler.py#L4160-L4283)。
- ✅ **跨进程文件锁 + 有界获取**：`_jobs_lock` 用 `fcntl.LOCK_EX | LOCK_NB` 轮询到 deadline，超时降级为进程内锁 → [jobs.py](file:///D:\yaodh\main\hermes-agent\cron\jobs.py#L270-L349)。
- ✅ **幂等 + epoch 校验**：`.drain_request.json` 带 `instantiation_epoch`，机器重启后自动失效旧 marker（NS-570 修复 52 min 卡死）→ [drain_control.py](file:///D:\yaodh\main\hermes-agent\gateway\drain_control.py#L1-L80)。
- ✅ **Kanban 失败熔断**：`DEFAULT_FAILURE_LIMIT=2` 连续失败即 parked to blocked → [kanban_db.py](file:///D:\yaodh\main\hermes-agent\hermes_cli\kanban_db.py#L7614-L7620)；`BLOCK_RECURRENCE_LIMIT=2` 阻断 unblock↔re-block 死循环 → [kanban_db.py](file:///D:\yaodh\main\hermes-agent\hermes_cli\kanban_db.py#L127-L134)。
- ✅ **工具回路可选熔断**：`tool_loop_guardrails.hard_stop_enabled` + 阈值 → [cli-config.yaml.example](file:///D:\yaodh\main\hermes-agent\cli-config.yaml.example#L410-L427)。
- ✅ **Per-call 超时**：每次 `chat.completions.create` 都传 `timeout=effective_timeout` → [auxiliary_client.py](file:///D:\yaodh\main\hermes-agent\agent\auxiliary_client.py#L4563)。

## Checklist 对照

- [x] 是否有重试/超时/熔断 — ✅ 全部有（jittered_backoff + per-call timeout + 多形态熔断）
- [ ] 是否有空 catch — ⚠️ 313 处 except:pass（多为 cleanup，个别真实吞错）
- [x] 关键写操作是否幂等 — ✅ file lock + epoch + CAS
- [x] 是否有限流/背压 — ✅ nous_rate_guard + semaphore + max_concurrent_children

## 改进建议

1. 给 background_review.py 的 cleanup `except: pass` 至少加 `logger.debug("...", exc_info=True)`。
2. 把 `tests/stress/test_concurrency_reclaim_race.py` 纳入 CI 的非 PR（nightly）job。
3. 考虑迁移 `jittered_backoff` 到 tenacity（已声明依赖）以获得 `wait_random_exponential` 与 `stop_after_delay`。
