# Hermes Agent 开发参考手册

> 由 `project-analysis` 诊断模式产出（v2）。每维度按「设计原则 / 业界标杆做法全列表 / 本项目实现对照（✅有/❌无/⚠️部分）/ 待补项」组织，指导写新代码与重构。
>
> 标杆来源：`benchmarks/python.md` 既有标杆 + 通用 Python/Agent 最佳实践（未做 WebSearch，用户选择"仅分析当前项目"）。本项目对照证据经 Grep/Read 行号实测。
>
> 配套：[project-rules.md](project-rules.md)（精简规则）+ [quality/](quality/README.md)（13 分维度评估详情）+ [project-health.md](project-health.md)（汇总评分卡）。

---

## 1 代码规范（评分 2/4）

### 设计原则
规范自动化、可强制，不靠人工记忆。

### 业界标杆做法（全列表）
1. 配置 `.editorconfig`（charset/end_of_line/indent_style 跨编辑器基线）
2. 格式化工具（Python: ruff format / black；TS: prettier）接入 CI
3. Lint 工具（Python: ruff E/F/I/UP/B；TS: eslint）接入 CI **阻塞门禁**
4. 复杂度扫描（radon/lizard）门禁（圈复杂度 >15 拦截）
5. 命名约定文档（CONTRIBUTING.md / STYLE.md）
6. 常量集中管理（无裸魔法数）
7. 注释覆盖关键决策（写 why 不写 what）
8. 提交前 hook（pre-commit / husky）
9. 类型检查（mypy / ty / tsc --noEmit）阻塞门禁
10. 文件长度门禁（>500 行警告）

### 本项目实现对照
- 标杆1（.editorconfig）：❌ 无（实测 MISSING）→ 建议补
- 标杆2（格式工具）：✅ 有（ruff + prettier）→ [pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L450-L465)、[.prettierrc](file:///D:\yaodh\main\hermes-agent\.prettierrc#L1-L11)
- 标杆3（Lint CI 门禁）：⚠️ 部分 — ruff 仅 PLW1514 一条阻塞，ty 全 `--exit-zero` → [lint_diff.py](file:///D:\yaodh\main\hermes-agent\scripts\lint_diff.py#L194-L196)
- 标杆4（复杂度扫描）：❌ 无 radon/lizard 配置
- 标杆5（命名约定）：✅ 有（AGENTS.md TypeScript Style 节 + pyproject 注释）
- 标杆6（常量集中）：✅ 有（registry `_MAX_TOOL_ERROR_CHARS`、base.py `_POST_DELIVERY_CALLBACK_TIMEOUT_SECONDS`）→ [tools/registry.py](file:///D:\yaodh\main\hermes-agent\tools\registry.py#L32-L36)
- 标杆7（注释 why）：✅ 有（pyproject.toml CVE/why 注释范本级）→ [pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L18-L37)
- 标杆8（提交前 hook）：⚠️ 部分（有 CI 门禁但无 pre-commit/husky 本地 hook）
- 标杆9（类型检查门禁）：⚠️ 部分 — ty 为纯建议（never fails the build）
- 标杆10（文件长度门禁）：❌ 无（cli.py 17k、gateway/run.py 26k 行无拦截）

### 待补项（本项目无，建议补）
1. 补 `.editorconfig`
2. ruff `select` 从 PLW1514 扩到 E/F/I/UP/B
3. ty 从 `--exit-zero` 升级为阻塞门禁
4. 接入 radon 复杂度扫描
5. 拆分 god-file（cli.py / gateway/run.py / hermes_state.py）

---

## 2 架构约束（评分 2/4）

### 设计原则
分层规则要测试固化，不只文档约束。

### 业界标杆做法（全列表）
1. 明确定义分层与依赖方向（文档化）
2. 架构约束测试（Python: import-linter；Java: ArchUnit；JS: dependency-cruiser/madge）
3. 零循环依赖（机器化扫描）
4. 领域层隔离框架（无框架注解耦合）
5. 目录反映职责边界（DDD/Clean Architecture 分层）
6. 无上帝类（单一职责）
7. 依赖方向严格（上层不依赖下层细节）
8. ABC/接口抽象（面向接口编程）

### 本项目实现对照
- 标杆1（分层文档）：✅ 有（AGENTS.md 依赖链 + "core 窄腰" 哲学）→ [AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L339-L349)
- 标杆2（架构约束测试）：❌ 无 import-linter/ArchUnit
- 标杆3（零循环依赖）：⚠️ 部分 — registry.py 文档标注"circular-import safe"但无机器化扫描 → [tools/registry.py](file:///D:\yaodh\main\hermes-agent\tools\registry.py#L1-L15)
- 标杆4（领域隔离框架）：✅ 有（ABC 抽象隔离）→ [agent/memory_provider.py](file:///D:\yaodh\main\hermes-agent\agent\memory_provider.py#L81-L89)、[providers/base.py](file:///D:\yaodh\main\hermes-agent\providers\base.py#L38-L40)
- 标杆5（目录职责边界）：✅ 有（agent/tools/gateway/hermes_cli/providers/plugins 各司其职）
- 标杆6（无上帝类）：❌ 无 — AIAgent 60+ 参数 god-class，8+ 个 >5k 行 god-file → [run_agent.py](file:///D:\yaodh\main\hermes-agent\run_agent.py#L412-L494)
- 标杆7（依赖方向严格）：✅ 有（registry → tools → model_tools → run_agent 链文档化）
- 标杆8（ABC 抽象）：✅ 有（MemoryProvider/ProviderProfile/平台基类 ABC）

### 待补项
1. 引入 import-linter 声明层契约 + CI 阻塞门禁
2. 拆分 gateway/run.py（26k 行）按会话生命周期/调度/交付
3. 给 AIAgent 引入 Builder/Config 数据类收敛 60+ 构造参数

---

## 3 复用性（评分 3/4）

### 设计原则
抽象前先有三处复用例（Rule of Three），公共模块职责清晰。

### 业界标杆做法（全列表）
1. 建公共模块（utils/constants/registry）
2. 重复代码检测（jscpd/duplicate-finder）CI 门禁
3. Rule of Three（三处复用才抽象）
4. ABC + orchestrator 模式（同类多 provider 统一接口）
5. 复用文档（公共模块入口索引）
6. 无循环依赖阻碍复用
7. 常量/配置集中管理
8. 跨工具/跨平台复用已抽象公共 helper

### 本项目实现对照
- 标杆1（公共模块）：✅ 有（registry/hermes_constants/plugin_utils）→ [hermes_constants.py](file:///D:\yaodh\main\hermes-agent\hermes_constants.py#L1-L27)、[plugins/plugin_utils.py](file:///D:\yaodh\main\hermes-agent\plugins\plugin_utils.py#L1-L38)
- 标杆2（重复检测）：❌ 无 jscpd/duplicate-finder
- 标杆3（Rule of Three）：✅ 有（AGENTS.md "3+ 个同类 PR 设计 ABC"）→ [AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L207-L211)
- 标杆4（ABC+orchestrator）：✅ 有（memory/model-provider/context-engine/image-gen 四类）
- 标杆5（复用文档）：❌ 无（公共模块无入口索引文档）
- 标杆6（无循环依赖）：✅ 有（registry 显式标注循环安全）
- 标杆7（常量集中）：✅ 有（hermes_constants 单一真相源）
- 标杆8（跨工具复用）：⚠️ 部分 — file_safety 已复用，但 chunked_upload 仅 qqbot 有未抽公共

### 待补项
1. 接入 jscpd 量化重复率
2. 把 chunked_upload 抽到 gateway/platforms/ 公共 helper
3. 给公共模块补"复用入口"索引文档

---

## 4 可测试性（评分 3/4，否决项）

### 设计原则
单元/集成/E2E 分层，DI 可 mock，外部依赖隔离。

### 业界标杆做法（全列表）
1. 单元/集成/端到端分层清晰（marker/目录）
2. DI 充分可 mock（无静态调用满天飞）
3. 外部依赖隔离（testcontainers/fakes/mocks）
4. 覆盖率门禁（>80% 目标，branch 覆盖）
5. 快速单测（<10s）
6. 无 flaky（或 flaky 修根因不重试掩盖）
7. 测关键路径契约（不变量断言）
8. 测试隔离（per-file/per-test subprocess）
9. 禁 change-detector 测试（断言行为不变量非快照）
10. 禁源码正则测试（测运行时行为非代码文本）

### 本项目实现对照
- 标杆1（分层）：✅ 有（integration/ssh/linux_only/macos_only/windows_only marker）→ [pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L427-L441)
- 标杆2（DI 可 mock）：✅ 有（autouse mock subprocess/os.kill/pty 全覆盖）→ [tests/conftest.py](file:///D:\yaodh\main\hermes-agent\tests\conftest.py#L634-L711)
- 标杆3（外部隔离）：✅ 有（_hermetic_environment 清凭据 + HERMES_HOME tempdir + IMDS 禁用）→ [tests/conftest.py](file:///D:\yaodh\main\hermes-agent\tests\conftest.py#L429-L533)
- 标杆4（覆盖率门禁）：❌ 无（无 pytest-cov/coverage 配置）→ [pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L184)
- 标杆5（快速单测）：⚠️ 部分 — per-file 隔离偏慢（~17k 测试，历史退回 per-file）
- 标杆6（无 flaky）：⚠️ 部分 — 有 flake 重试机制（说明存在 flaky）→ [AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L1360-L1366)
- 标杆7（契约测试）：✅ 有（AGENTS.md "行为契约 not 快照"）→ [AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L1432-L1479)
- 标杆8（测试隔离）：✅ 有（per-file subprocess 隔离 + env -i 空环境）→ [run_tests.sh](file:///D:\yaodh\main\hermes-agent\scripts\run_tests.sh#L152-L183)
- 标杆9（禁 change-detector）：✅ 有（AGENTS.md 明文禁止）→ [AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L1432-L1479)
- 标杆10（禁源码正则）：✅ 有（AGENTS.md "Never read source code in tests"）→ [AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L1481-L1534)

### 待补项
1. 接入 pytest-cov + `[tool.coverage.run]`，branch 40% 起步
2. 修复 e2e-desktop（#76627）或标注长期弃用
3. 纯函数测试加 `@pytest.mark.no_isolate` 跳过子进程提速

---

## 5 性能（评分 3/4）

### 设计原则
性能预算 + 压测基线 + 缓存策略 + N+1 检测。

### 业界标杆做法（全列表）
1. 性能预算（延迟/吞吐目标）
2. 压测基线（wrk/locust/k6）
3. 性能基准 CI（回归阈值）
4. N+1 检测（循环内查库）
5. 缓存策略（TTL/失效/一致性）
6. 内存压力感知（RSS 监控 + LRU 驱逐）
7. 异步并行限流（semaphore）
8. 客户端/连接复用（client cache）
9. 按需加载（lazy init）
10. latency histogram 指标

### 本项目实现对照
- 标杆1（性能预算）：⚠️ 部分 — prompt caching "sacred" 是隐含预算 → [AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L18-L22)
- 标杆2（压测基线）：⚠️ 部分 — 有 stress/ 但默认不跑 → [conftest.py](file:///D:\yaodh\main\hermes-agent\tests\stress\conftest.py#L13-L22)
- 标杆3（基准 CI）：❌ 无 — test_benchmarks.py 仅记录不设阈值 → [test_benchmarks.py](file:///D:\yaodh\main\hermes-agent\tests\stress\test_benchmarks.py#L10-L13)
- 标杆4（N+1 检测）：✅ 有 — 窗口函数主动规避 → [kanban_db.py](file:///D:\yaodh\main\hermes-agent\hermes_cli\kanban_db.py#L11305-L11337)
- 标杆5（缓存策略）：✅ 有 — prompt caching TTL provider 感知 + breakpoint 分离 → [prompt_caching.py](file:///D:\yaodh\main\hermes-agent\agent\prompt_caching.py#L115-L167)
- 标杆6（内存压力）：✅ 有 — RSS vs cgroup 65% 阈值 LRU 驱逐 → [agent_cache_pressure.py](file:///D:\yaodh\main\hermes-agent\gateway\agent_cache_pressure.py#L1-L49)
- 标杆7（异步限流）：✅ 有 — Semaphore(50) + wait_for → [trajectory_compressor.py](file:///D:\yaodh\main\hermes-agent\trajectory_compressor.py#L114-L118)
- 标杆8（客户端复用）：✅ 有 — _client_cache → [auxiliary_client.py](file:///D:\yaodh\main\hermes-agent\agent\auxiliary_client.py#L7343)
- 标杆9（按需加载）：✅ 有 — lazy_deps 安全模型 → [lazy_deps.py](file:///D:\yaodh\main\hermes-agent\tools\lazy_deps.py#L1-L66)
- 标杆10（latency histogram）：❌ 无 — 指标全 gauge 无 histogram

### 待补项
1. benchmark 接入 nightly CI + 2x 回归阈值
2. 删除未用的 tenacity 依赖或迁移到它
3. 修正 AGENTS.md "3-minute" 与实际 600s 不一致
4. 加 latency histogram 指标

---

## 6 可靠性（评分 4/4，否决项）

### 设计原则
重试+超时+熔断+限流+幂等+异常分类，不空 catch。

### 业界标杆做法（全列表）
1. 重试（jittered backoff + Retry-After 解析）
2. 超时（per-call + inactivity + claim TTL）
3. 熔断（failure_limit + block_recurrence + hard_stop）
4. 限流（跨会话 rate guard + semaphore + max_concurrent）
5. 幂等（file lock + epoch + CAS guard）
6. 异常分类（FailoverReason 枚举 + 恢复提示）
7. 单次恢复守卫（TurnRetryState 防无限重试）
8. 无空 catch（cleanup 加 logger.debug）
9. 迭代预算（线程安全计数器 + refund）
10. 心跳 + 不活动超时（cron hard_interrupt）

### 本项目实现对照
- 标杆1（重试）：✅ 有 — jittered_backoff + Retry-After + 阶梯退避 → [retry_utils.py](file:///D:\yaodh\main\hermes-agent\agent\retry_utils.py#L90-L128)
- 标杆2（超时）：✅ 有 — per-call timeout + cron 600s inactivity → [auxiliary_client.py](file:///D:\yaodh\main\hermes-agent\agent\auxiliary_client.py#L4563)、[scheduler.py](file:///D:\yaodh\main\hermes-agent\cron\scheduler.py#L4160-L4283)
- 标杆3（熔断）：✅ 有 — failure_limit=2 + block_recurrence + tool_loop hard_stop → [kanban_db.py](file:///D:\yaodh\main\hermes-agent\hermes_cli\kanban_db.py#L7614-L7620)、[cli-config.yaml.example](file:///D:\yaodh\main\hermes-agent\cli-config.yaml.example#L410-L427)
- 标杆4（限流）：✅ 有 — nous_rate_guard 跨会话共享文件 → [nous_rate_guard.py](file:///D:\yaodh\main\hermes-agent\agent\nous_rate_guard.py#L1-L11)
- 标杆5（幂等）：✅ 有 — drain_request epoch + file lock NB → [drain_control.py](file:///D:\yaodh\main\hermes-agent\gateway\drain_control.py#L1-L80)、[jobs.py](file:///D:\yaodh\main\hermes-agent\cron\jobs.py#L270-L349)
- 标杆6（异常分类）：✅ 有 — 25+ FailoverReason + ClassifiedError 恢复提示 → [error_classifier.py](file:///D:\yaodh\main\hermes-agent\agent\error_classifier.py#L24-L99)
- 标杆7（单次恢复守卫）：✅ 有 — TurnRetryState 16 个 attempted 布尔 → [turn_retry_state.py](file:///D:\yaodh\main\hermes-agent\agent\turn_retry_state.py#L32-L80)
- 标杆8（无空 catch）：⚠️ 部分 — 313 处 except:pass，多为 cleanup，个别真实吞错无 logger → [background_review.py](file:///D:\yaodh\main\hermes-agent\agent\background_review.py#L682-L683)
- 标杆9（迭代预算）：✅ 有 — 线程安全计数器 + refund → [iteration_budget.py](file:///D:\yaodh\main\hermes-agent\agent\iteration_budget.py#L17-L60)
- 标杆10（心跳）：✅ 有 — cron heartbeat_run_claim + ESTOP fail-safe → [estop.py](file:///D:\yaodh\main\hermes-agent\agent\estop.py#L59-L72)

### 待补项
1. cleanup 路径 except:pass 加 `logger.debug(exc_info=True)`
2. stress race 测试纳入 nightly CI
3. 考虑迁移 jittered_backoff 到 tenacity（已声明依赖）

---

## 7 可观测性（评分 4/4）

### 设计原则
日志结构化+关联ID，指标 RED/USE，追踪分布式，告警+错误聚合+健康检查。

### 业界标杆做法（全列表）
1. 结构化日志 + 级别分明
2. 关联 ID（traceId/requestId 串请求）
3. RED 指标（Rate/Errors/Duration）
4. USE 指标（Utilization/Saturation/Errors）
5. 分布式追踪（OpenTelemetry + per-call span）
6. 告警规则（PromQL + runbook）
7. 错误聚合（Sentry/errors.log）
8. 健康检查端点
9. 日志脱敏（secret 不落盘）
10. 内存监控（RSS + GC）

### 本项目实现对照
- 标杆1（结构化日志）：✅ 有 — 4 文件分级 + RedactingFormatter → [hermes_logging.py](file:///D:\yaodh\main\hermes-agent\hermes_logging.py#L1-L86)
- 标杆2（关联 ID）：✅ 有 — session_tag（thread-local）→ [hermes_logging.py](file:///D:\yaodh\main\hermes-agent\hermes_logging.py#L165-L210)
- 标杆3（RED 指标）：⚠️ 部分 — 16 gauge 指标，缺 latency histogram → [gateway_health_export.py](file:///D:\yaodh\main\hermes-agent\agent\monitoring\gateway_health_export.py#L434-L468)
- 标杆4（USE 指标）：⚠️ 部分 — 有内存监控但无完整 USE
- 标杆5（分布式追踪）：⚠️ 部分 — OTLP traces 仅 lifecycle/cron span → [monitoring.md](file:///D:\yaodh\main\hermes-agent\docs\observability\monitoring.md#L20-L23)
- 标杆6（告警规则）：✅ 有 — PromQL 示例 → [monitoring.md](file:///D:\yaodh\main\hermes-agent\docs\observability\monitoring.md#L107-L130)
- 标杆7（错误聚合）：✅ 有 — errors.log WARNING+ + OTLP logs → [events.py](file:///D:\yaodh\main\hermes-agent\agent\monitoring\events.py#L45-L63)
- 标杆8（健康检查）：✅ 有 — readiness 探针 mode=ro → [readiness.py](file:///D:\yaodh\main\hermes-agent\gateway\readiness.py#L89-L122)
- 标杆9（日志脱敏）：✅ 有 — redact.py 1390+ 行 → [redact.py](file:///D:\yaodh\main\hermes-agent\agent\redact.py#L1-L8)
- 标杆10（内存监控）：✅ 有 — [MEMORY] RSS+GC → [memory_monitor.py](file:///D:\yaodh\main\hermes-agent\gateway\memory_monitor.py#L52-L100)

### 待补项
1. agent 主循环加 OTLP span（per-LLM-call/per-tool-call + parent context 传播）
2. 加 latency histogram（`hermes.llm.latency_ms`、`hermes.tool.latency_ms`）
3. session_tag 改 contextvars.ContextVar 跨 async 传播
4. OTLP SDK lazy install 或进 [all]

---

## 8 可扩展性（评分 4/4）

### 设计原则
明确扩展点 + 插件/SPI 机制 + 面向接口 + 配置驱动 + 扩展文档。

### 业界标杆做法（全列表）
1. Footprint Ladder（最小足迹优先的扩展决策阶梯）
2. 插件发现（多源：repo/用户/pip/entry-point）
3. 生命周期钩子（pre/post tool/llm + session start/end）
4. ABC + orchestrator（同类多 provider 统一接口）
5. 中央注册（registry 自发现 + register）
6. Surface gate（core vs 命名 toolset 区分）
7. 配置驱动（DEFAULT_CONFIG + YAML 深合并 + 版本迁移）
8. last-writer-wins 覆盖（用户插件覆盖内置）
9. 插件并发原语（lazy_singleton/SingletonSlot）
10. 兼容契约（行为契约非版本号，加性新增）
11. 扩展文档矩阵

### 本项目实现对照
- 标杆1（Footprint Ladder）：✅ 有 — 六级阶梯 → [AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L182-L206)
- 标杆2（插件发现）：✅ 有 — 四源 → [AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L780-L798)
- 标杆3（生命周期钩子）：✅ 有 — 6 个钩子白名单 + 签名自省 → [AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L786-L790)
- 标杆4（ABC+orchestrator）：✅ 有 — MemoryProvider/ProviderProfile/平台基类 → [agent/memory_provider.py](file:///D:\yaodh\main\hermes-agent\agent\memory_provider.py#L81-L89)
- 标杆5（中央注册）：✅ 有 — AST 自发现 + memoized → [tools/registry.py](file:///D:\yaodh\main\hermes-agent\tools\registry.py#L1-L15)
- 标杆6（Surface gate）：✅ 有 — _HERMES_CORE_TOOLS vs 命名 toolset → [AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L1028-L1044)
- 标杆7（配置驱动）：✅ 有 — DEFAULT_CONFIG + 深合并 + 版本迁移 → [AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L620-L681)
- 标杆8（last-writer-wins）：✅ 有 — 用户插件覆盖内置 → [AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L879-L896)
- 标杆9（并发原语）：✅ 有 — lazy_singleton/SingletonSlot → [plugins/plugin_utils.py](file:///D:\yaodh\main\hermes-agent\plugins\plugin_utils.py#L1-L38)
- 标杆10（兼容契约）：✅ 有 — 行为契约 + 加性 + 签名自省 → [AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L800-L823)
- 标杆11（扩展文档）：✅ 有 — developer-guide/ 15+ 指南

### 待补项
1. gateway/builtin_hooks/ 补示例钩子文档锚点
2. 补"扩展点总览图"统一索引

---

## 9 文档完备度（评分 4/4）

### 设计原则
README + API 文档 + 架构文档 + ADR + 注释记 why。

### 业界标杆做法（全列表）
1. README 完整且新（安装+快速上手+多语言）
2. API 文档（OpenAPI/javadoc/tsdoc）
3. 架构文档（系统图+模块说明）
4. ADR（关键决策记录）
5. 注释覆盖关键决策（why）
6. CONTRIBUTING.md（贡献指南）
7. 模块级 README
8. 文档站（Docusaurus/readthedocs）
9. developer-guide（扩展指南）
10. reference（CLI 命令/环境变量/工具参考）

### 本项目实现对照
- 标杆1（README）：✅ 有 — 三语 + Quick Install + Getting Started → [README.md](file:///D:\yaodh\main\hermes-agent\README.md#L35-L66)
- 标杆2（API 文档）：⚠️ 部分 — ACP 协议版本化，但无独立 OpenAPI schema → [api-server.md](file:///D:\yaodh\main\hermes-agent\website\docs\user-guide\features\api-server.md#L56-L60)
- 标杆3（架构文档）：✅ 有 — AGENTS.md 1240+ 行架构宪法 → [AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L1-L5)
- 标杆4（ADR）：⚠️ 部分 — 有 docs/ADR.md 四段式流程但仅 1 条记录 → [docs/ADR.md](file:///D:\yaodh\main\hermes-agent\docs\ADR.md#L1-L60)
- 标杆5（注释 why）：✅ 有 — pyproject.toml CVE/why 范本级 → [pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L18-L37)
- 标杆6（CONTRIBUTING）：✅ 有 → [CONTRIBUTING.md](file:///D:\yaodh\main\hermes-agent\CONTRIBUTING.md#L1-L18)
- 标杆7（模块 README）：✅ 有 — apps/desktop/DESIGN.md+AGENTS.md 等
- 标杆8（文档站）：✅ 有 — Docusaurus 200+ 页
- 标杆9（developer-guide）：✅ 有 — 30+ 扩展指南
- 标杆10（reference）：✅ 有 — cli-commands/environment-variables/slash-commands/tools-reference

### 待补项
1. 补充更多 ADR（prompt caching/Footprint Ladder/profile 隔离）
2. 暴露 FastAPI `/docs` OpenAPI

---

## 10 构建与CI（评分 4/4）

### 设计原则
自动化构建 + CI/CD（lint→test→build→scan→deploy） + 容器化 + 发布 + 回滚。

### 业界标杆做法（全列表）
1. 自动化构建（Makefile/build.sh/setuptools/uv）
2. CI/CD（lint→test→build→scan→deploy）
3. 变更分类器（按改动决定跑哪些 job）
4. 环境容器化（Dockerfile 多阶段）
5. Nix flake（可复现环境）
6. lockfile 锁定（uv.lock/package-lock.json）
7. dependabot（自动更新）
8. 发布流程（CalVer/semver + changelog）
9. 回滚机制
10. 跨平台安装器 + 安装测试 CI
11. dep-bounds 门禁（无上界依赖拦截）

### 本项目实现对照
- 标杆1（自动化构建）：✅ 有 — setuptools + uv + npm workspaces → [pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L360-L362)
- 标杆2（CI/CD）：✅ 有 — 27 个 workflow → [.github/workflows/](file:///D:\yaodh\main\hermes-agent\.github\workflows)
- 标杆3（变更分类器）：✅ 有 — classify_changes.py 14 车道 → [AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L1382-L1392)
- 标杆4（容器化）：✅ 有 — Dockerfile 多阶段 + hadolint → [Dockerfile](file:///D:\yaodh\main\hermes-agent\Dockerfile)
- 标杆5（Nix）：✅ 有 — 16 文件三系统 → [flake.nix](file:///D:\yaodh\main\hermes-agent\flake.nix)
- 标杆6（lockfile）：✅ 有 — uv.lock + package-lock.json
- 标杆7（dependabot）：✅ 有 — github-actions SHA pins → [dependabot.yml](file:///D:\yaodh\main\hermes-agent\.github\dependabot.yml#L1-L23)
- 标杆8（发布）：✅ 有 — CalVer release.py + changelog → [release.py](file:///D:\yaodh\main\hermes-agent\scripts\release.py#L1-L21)
- 标杆9（回滚）：✅ 有 — 三重复（curator/backup/checkpoints）
- 标杆10（安装器）：✅ 有 — install.sh/ps1 + installer-tests CI
- 标杆11（dep-bounds）：✅ 有 — 无上界直接 fail → [supply-chain-audit.yml](file:///D:\yaodh\main\hermes-agent\.github\workflows\supply-chain-audit.yml#L252-L256)

### 待补项
1. 修复 e2e-desktop CI（#76627）
2. benchmark 接入 nightly CI

---

## 11 安全性（评分 4/4，否决项）

### 设计原则
密钥用密钥管理服务 + 鉴权全覆盖 + 输入校验 + 依赖漏洞扫描 CI + 加密传输存储 + 日志脱敏。

### 业界标杆做法（全列表）
1. 无硬编码密钥（环境变量/密钥管理服务）
2. 鉴权全覆盖 + fail-closed
3. 输入校验（路径穿越/SSRF/注入/XSS/CSRF）
4. 依赖漏洞扫描 CI 门禁（osv/trivy/snyk）
5. 供应链攻击检测（.pth/base64+exec/混淆 subprocess）
6. override-deps 修补转译依赖 CVE
7. exclude-newer 隔离窗口
8. 日志脱敏（secret 不落盘）
9. 写入审批（write_approval）
10. 多 profile 密钥隔离
11. defusedxml（XXE/billion-laughs）
12. SSL/CA 校验
13. prompt 注入/C2/外泄威胁检测

### 本项目实现对照
- 标杆1（无硬编码）：✅ 有 — 仅测试 fixture 与哨兵值 → [pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L18-L37)
- 标杆2（鉴权 fail-closed）：✅ 有 → [authz_mixin.py](file:///D:\yaodh\main\hermes-agent\gateway\authz_mixin.py#L386-L401)
- 标杆3（输入校验）：✅ 有 — path_security/url_safety/defusedxml → [credential_files.py](file:///D:\yaodh\main\hermes-agent\tools\credential_files.py#L62-L84)
- 标杆4（漏洞扫描）：✅ 有 — osv-scanner + supply-chain-audit → [supply-chain-audit.yml](file:///D:\yaodh\main\hermes-agent\.github\workflows\supply-chain-audit.yml#L103-L115)
- 标杆5（供应链检测）：✅ 有 — litellm 式攻击模式扫描
- 标杆6（override-deps）：✅ 有 — pynacl/cryptography 覆盖 → [pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L370-L383)
- 标杆7（exclude-newer）：✅ 有 — 14 天隔离窗口 → [pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L384-L389)
- 标杆8（日志脱敏）：✅ 有 — redact.py 1390+ 行 → [redact.py](file:///D:\yaodh\main\hermes-agent\agent\redact.py#L1-L8)
- 标杆9（写入审批）：✅ 有 — write_approval/slash_confirm → [tools/write_approval.py](file:///D:\yaodh\main\hermes-agent\tools\write_approval.py)
- 标杆10（多 profile 隔离）：✅ 有 — secret_scope fail-closed → [agent/secret_scope.py](file:///D:\yaodh\main\hermes-agent\agent\secret_scope.py)
- 标杆11（defusedxml）：✅ 有 — WeCom extra → [pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L194)
- 标杆12（SSL 校验）：✅ 有 — ssl_guard/ssl_verify → [agent/ssl_guard.py](file:///D:\yaodh\main\hermes-agent\agent\ssl_guard.py)
- 标杆13（威胁检测）：✅ 有 — threat_patterns/tirith_security/mcp_security

### 待补项
1. OSV 高危 CVE 改 `fail-on-vuln: severity high`
2. SUDO_PASSWORD 改 keyring/secret-source 后端
3. 集中式密钥管理服务设为推荐默认

---

## 12 易用性（评分 4/4）

### 设计原则
API 版本化 + OpenAPI 文档 + CLI 补全 + 错误带修复建议 + getting started + 配置校验。

### 业界标杆做法（全列表）
1. API 版本化
2. OpenAPI/Swagger 文档
3. CLI 补全（bash/zsh/fish 动态生成）
4. 错误可读带修复建议（how_to_fix）
5. 最小示例（getting started）
6. 配置校验 + 损坏自愈
7. doctor 诊断工具
8. 单一真相源命令注册表
9. 多语言 README
10. 海量用户文档（文档站）

### 本项目实现对照
- 标杆1（API 版本化）：✅ 有 — ACP 协议协商 → [server.py](file:///D:\yaodh\main\hermes-agent\acp_adapter\server.py#L1145-L1158)
- 标杆2（OpenAPI）：❌ 无 — 无独立 schema → [api-server.md](file:///D:\yaodh\main\hermes-agent\website\docs\user-guide\features\api-server.md#L56-L60)
- 标杆3（CLI 补全）：✅ 有 — argparse 动态生成 → [completion.py](file:///D:\yaodh\main\hermes-agent\hermes_cli\completion.py#L1-L7)
- 标杆4（错误修复建议）：✅ 有 — ClassifiedError + ConfigIssue.how_to_fix → [error_classifier.py](file:///D:\yaodh\main\hermes-agent\agent\error_classifier.py#L24-L72)、[config.py](file:///D:\yaodh\main\hermes-agent\hermes_cli\config.py#L1907-L1935)
- 标杆5（最小示例）：✅ 有 — README Quick Install + Getting Started → [README.md](file:///D:\yaodh\main\hermes-agent\README.md#L35-L66)
- 标杆6（配置校验）：✅ 有 — validate_config_structure + 损坏自愈 → [config.py](file:///D:\yaodh\main\hermes-agent\hermes_cli\config.py#L46-L97)
- 标杆7（doctor）：✅ 有 — hermes doctor → [doctor.py](file:///D:\yaodh\main\hermes-agent\hermes_cli\doctor.py#L414-L415)
- 标杆8（命令注册表）：✅ 有 — COMMAND_REGISTRY 单一真相源 → [commands.py](file:///D:\yaodh\main\hermes-agent\hermes_cli\commands.py#L1-L9)
- 标杆9（多语言）：✅ 有 — zh/es/ur-pk
- 标杆10（文档站）：✅ 有 — Docusaurus 200+ 页

### 待补项
1. 暴露 FastAPI `/docs` OpenAPI
2. errors.py 异常类补 message/hint 字段

---

## 13 依赖健康度（评分 4/4）

### 设计原则
lockfile 锁定 + 依赖扫描 CI 门禁 + 定期升级 + 许可证检查 + 无循环。

### 业界标杆做法（全列表）
1. lockfile 锁定（uv.lock/package-lock.json）
2. 核心依赖精确 `==` 锁定
3. 上界政策（`>=floor,<next_major`）
4. Git URL 用 SHA
5. GitHub Actions 用 SHA + 注释
6. override-deps 修补转译 CVE
7. exclude-newer 隔离窗口
8. lazy-install 安全模型（venv 作用域 + allowlist + sys.path 末尾）
9. dep-bounds CI 门禁（无上界拦截）
10. dependabot 自动更新
11. CVE 主动修补到修复底版
12. 许可证合规扫描

### 本项目实现对照
- 标杆1（lockfile）：✅ 有 — uv.lock + package-lock.json
- 标杆2（精确锁定）：✅ 有 — 核心 `==X.Y.Z` → [pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L18-L37)
- 标杆3（上界政策）：✅ 有 — AGENTS.md 成文 → [AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L598-L617)
- 标杆4（Git SHA）：✅ 有 — 40 字符 SHA
- 标杆5（Actions SHA）：✅ 有 — SHA + 注释
- 标杆6（override-deps）：✅ 有 → [pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L370-L383)
- 标杆7（exclude-newer）：✅ 有 — 14 天 → [pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L384-L389)
- 标杆8（lazy-install）：✅ 有 — 安全模型 → [lazy_deps.py](file:///D:\yaodh\main\hermes-agent\tools\lazy_deps.py#L25-L66)
- 标杆9（dep-bounds 门禁）：✅ 有 → [supply-chain-audit.yml](file:///D:\yaodh\main\hermes-agent\.github\workflows\supply-chain-audit.yml#L252-L256)
- 标杆10（dependabot）：✅ 有 — github-actions SHA → [dependabot.yml](file:///D:\yaodh\main\hermes-agent\.github\dependabot.yml#L1-L23)
- 标杆11（CVE 修补）：✅ 有 — 6+ 项 CVE 注释
- 标杆12（许可证扫描）：❌ 无 — 无 pip-licenses CI

### 待补项
1. CI 加 pip-licenses 传递依赖许可证扫描
2. OSV 按 severity 分级 + 高危 SLA

---

## 总结：13 维实现状态速查

| 章 | 维度 | 标杆做法数 | ✅有 | ⚠️部分 | ❌无 |
|----|------|----------|------|--------|------|
| 1 | 代码规范 | 10 | 4 | 3 | 3 |
| 2 | 架构约束 | 8 | 5 | 1 | 2 |
| 3 | 复用性 | 8 | 6 | 1 | 1 |
| 4 | 可测试性 | 10 | 7 | 2 | 1 |
| 5 | 性能 | 10 | 7 | 2 | 1 |
| 6 | 可靠性 | 10 | 9 | 1 | 0 |
| 7 | 可观测性 | 10 | 7 | 3 | 0 |
| 8 | 可扩展性 | 11 | 11 | 0 | 0 |
| 9 | 文档完备度 | 10 | 8 | 2 | 0 |
| 10 | 构建与CI | 11 | 11 | 0 | 0 |
| 11 | 安全性 | 13 | 12 | 0 | 1 |
| 12 | 易用性 | 10 | 9 | 0 | 1 |
| 13 | 依赖健康度 | 12 | 11 | 0 | 1 |

## P0 待补项（跨维度汇总，发版前必须）

1. **ruff 启用核心规则集 + ty 阻塞门禁**（代码规范）— 当前 lint 门禁形同虚设
2. **引入 import-linter 层契约 + CI**（架构约束）— 分层无机器化校验
3. **接入 pytest-cov 覆盖率门禁**（可测试性）— 覆盖率盲区

## 落地路线图

- **立即(P0)**：ruff 规则集 + ty 门禁 + import-linter + pytest-cov
- **本迭代(P1)**：拆分 gateway/run.py god-file + benchmark nightly CI + e2e-desktop 修复
- **机会性(P2)**：OSV 高危阻断 + latency histogram + ADR 补充 + OpenAPI 暴露 + 许可证扫描

---

> 本手册是 v2 核心产出（行动视角）。写新代码时对照各维度「业界标杆做法全列表」做、「本项目实现对照」复用 ✅ 项、「待补项」即评估后要补的目标。
