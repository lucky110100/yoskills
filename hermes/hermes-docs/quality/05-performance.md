# 05 性能 performance

> 维度归属：C 运行时质量组。评估 N+1、循环重操作、缓存、压测基线。
>
> 配套：[汇总评分卡](../project-health.md) | [索引](README.md)

## 评分：3 / 4

对照 3 分档「偶有 N+1 + 有部分压测」。项目在缓存、N+1 规避、内存压力预算、异步并行方面做得相当扎实（接近 4 分），但压测/基准测试为 opt-in、未进入 CI 强制门控，且 `tenacity` 依赖未实际使用、AGENTS.md 的「3 分钟硬中断」与代码默认值（600s）不一致，拉低至 3 分。

## 评估过程

### 关键问题（带 file:/// 证据）

1. **压力测试默认被跳过、不在 CI 中执行** — conftest 对 `tests/stress` 下所有 item 加 skip marker → [conftest.py](file:///D:\yaodh\main\hermes-agent\tests\stress\conftest.py#L13-L22)，且 `collect_ignore_glob = ["*.py"]` 让 pytest 默认根本不收集这些脚本 → [conftest.py](file:///D:\yaodh\main\hermes-agent\tests\stress\conftest.py#L33-L36)。

2. **基准测试无回归门控** — test_benchmarks.py 自述"Not a pass/fail test — records numbers"，仅打印+落 JSON，无阈值断言、无 CI workflow 引用 → [test_benchmarks.py](file:///D:\yaodh\main\hermes-agent\tests\stress\test_benchmarks.py#L10-L13)。

3. **`tenacity` 声明为 core 依赖但全仓库零 import** — pyproject.toml 第 46 行声明，但 `import tenacity` / `from tenacity` 零命中；实际重试用的是自研 retry_utils.py 的 `jittered_backoff` → [pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L46)、[retry_utils.py](file:///D:\yaodh\main\hermes-agent\agent\retry_utils.py#L90-L128)。依赖冗余。

4. **AGENTS.md 文档与实现不一致** — 声称「3-minute hard interrupt」，但 scheduler.py 实际默认是 600s（10 min inactivity），文档误导 → [AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L1137)、[scheduler.py](file:///D:\yaodh\main\hermes-agent\cron\scheduler.py#L4160-L4170)。

### 亮点

- ✅ **提示缓存设计精良** — 对 TTL 做 provider 感知钳制（Qwen/Alibaba 强制 5m），用 4 breakpoint + stable_prefix 分离避免票据 ID/时间戳使整段缓存失效 → [prompt_caching.py](file:///D:\yaodh\main\hermes-agent\agent\prompt_caching.py#L115-L167)、[prompt_caching.py](file:///D:\yaodh\main\hermes-agent\agent\prompt_caching.py#L385-L431)。AGENTS.md 明确"Per-conversation prompt caching is sacred" → [AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L18-L22)。
- ✅ **主动规避 N+1** — kanban_db.py 的 `latest_summaries` 用 `ROW_NUMBER() OVER (PARTITION BY ...)` 窗口函数一次取回所有 task 的最新 summary，注释直说"avoiding the N+1 pattern" → [kanban_db.py](file:///D:\yaodh\main\hermes-agent\hermes_cli\kanban_db.py#L11305-L11337)。
- ✅ **内存压力感知的 agent 缓存驱逐** — 按进程 RSS vs cgroup limit（65% 阈值）软驱逐 LRU 转录本 → [agent_cache_pressure.py](file:///D:\yaodh\main\hermes-agent\gateway\agent_cache_pressure.py#L1-L49)、[memory_monitor.py](file:///D:\yaodh\main\hermes-agent\gateway\memory_monitor.py#L1-L80)。仓库根有 `sqlite_leak_fix.png` 印证历史修复。
- ✅ **异步并行有信号量限流** — `max_concurrent_requests=50` + `per_trajectory_timeout=300`，用 `asyncio.Semaphore` + `asyncio.wait_for` → [trajectory_compressor.py](file:///D:\yaodh\main\hermes-agent\trajectory_compressor.py#L114-L118)、[trajectory_compressor.py](file:///D:\yaodh\main\hermes-agent\trajectory_compressor.py#L1121-L1233)。
- ✅ **客户端/tokenizer 缓存** — `_client_cache[cache_key]` 复用 provider client → [auxiliary_client.py](file:///D:\yaodh\main\hermes-agent\agent\auxiliary_client.py#L7343)。
- ✅ **Lazy 依赖安装避免膨胀** — 按需安装可选 backend，带 timeout 与安全 spec 校验 → [lazy_deps.py](file:///D:\yaodh\main\hermes-agent\tools\lazy_deps.py#L1-L66)。

## Checklist 对照

- [x] 是否查了 N+1 — ✅ 主动规避（窗口函数）
- [ ] 是否有压测基线 — ⚠️ 有 stress/ 但默认不跑、不进 CI
- [x] 缓存策略是否得当 — ✅ prompt caching + client cache + LRU 驱逐
- [ ] 是否有性能基准测试 — ⚠️ 有但不设回归阈值

## 改进建议

1. 将 `tests/stress/test_benchmarks.py` 接入 CI（哪怕 nightly job）并对 min/median 设 2x 回归阈值。
2. 删除 `pyproject.toml` 中未用的 `tenacity` 依赖，或真正迁移到它。
3. 把 AGENTS.md 的「3-minute」改为实际默认 600s 或让默认值降到 180s。
4. 给 agent 主循环的 per-turn 延迟加 histogram 指标（目前指标都是 gauge）。
