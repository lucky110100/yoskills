# 项目健康评估报告 — Hermes Agent

> 由 `project-analysis` 诊断模式产出。所有评分对照 `dims/<维度>.md` 锚点，并带 `[basename](file:///绝对路径#L行号)` 证据。
>
> **分维度详细文档**：每个质量维度（13 维）的详细评估见 [quality/](quality/README.md)，索引见 [quality/README.md](quality/README.md)。本主报告仅含汇总评分卡+问题清单+路线图。

## 一、项目概况与基线

- **项目名 / 路径**: Hermes Agent ☤ / `D:\yaodh\main\hermes-agent`
- **技术栈 / 类型**: Python 3.11-3.13 + TypeScript（Ink TUI / React Web / Electron Desktop）/ 自改进 AI Agent 应用
- **规模**: ~4091 Python 文件 + ~2087 TS/TSX 文件 + ~2938 测试文件（~17k 测试）；核心 run_agent.py ~12k 行、cli.py ~11k 行、gateway/run.py ~26k 行
- **基线提交**: `git rev-parse HEAD` = `fa83af3f9a42790730b8966ff67e7d9fb627899f`
- **最后提交**: 2026-08-13 03:16:25 -0700 "docs: update picker paths to ChatGPT or Codex Subscription"
- **评估时间**: 2026-08-13
- **评估模式**: 诊断模式（静态分析为主，未跑构建/测试）

## 二、评分卡

### 2.1 维度得分

| 组 | 维度 | 分(0-4) | 关键问题 | 证据(file:///) |
|----|------|---------|---------|----------------|
| A 功能 | 功能特性 | 4 | — | 20+ 平台 / 7 终端后端 / 插件+技能+MCP 全扩展面 |
| B 代码质量 | 代码规范 | 2 | ruff 仅 1 条规则门禁、ty 非阻塞、无 .editorconfig、god-file 满地 | [pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L450-L465) |
| B 代码质量 | 架构约束 | 2 | 无 import-linter、8+ 个 >5k 行 god-file、AIAgent 60+ 参数 | [run_agent.py](file:///D:\yaodh\main\hermes-agent\run_agent.py#L412-L494) |
| B 代码质量 | 复用性 | 3 | 无 jscpd、平台适配器公共逻辑散落 | [tools/registry.py](file:///D:\yaodh\main\hermes-agent\tools\registry.py#L1-L15) |
| B 代码质量 | 可测试性 | 3 | 无覆盖率测量、e2e-desktop 禁用、per-file 隔离偏慢 | [pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L184) |
| C 运行时 | 性能 | 3 | 压测未进 CI、tenacity 未用、文档与默认值不一致 | [conftest.py](file:///D:\yaodh\main\hermes-agent\tests\stress\conftest.py#L13-L22) |
| C 运行时 | 可靠性 | 4 | except:pass 散布 313 处（多为 cleanup） | [retry_utils.py](file:///D:\yaodh\main\hermes-agent\agent\retry_utils.py#L90-L128) |
| C 运行时 | 可观测性 | 4 | 分布式追踪仅覆盖 lifecycle、缺 latency histogram | [gateway_health_export.py](file:///D:\yaodh\main\hermes-agent\agent\monitoring\gateway_health_export.py#L434-L468) |
| D 演进 | 可扩展性 | 4 | — | [AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L182-L206) |
| D 演进 | 文档完备度 | 4 | ADR 仅 1 条、无 OpenAPI schema | [docs/ADR.md](file:///D:\yaodh\main\hermes-agent\docs\ADR.md#L1-L60) |
| D 演进 | 构建与CI | 4 | e2e-desktop 硬关闭 | [.github/workflows/](file:///D:\yaodh\main\hermes-agent\.github\workflows) |
| E 外部 | 安全性 | 4 | OSV 仅检测不阻断、SUDO_PASSWORD 明文选项 | [supply-chain-audit.yml](file:///D:\yaodh\main\hermes-agent\.github\workflows\supply-chain-audit.yml#L103-L115) |
| E 外部 | 易用性 | 4 | 无独立 OpenAPI 页面、errors.py 描述极简 | [error_classifier.py](file:///D:\yaodh\main\hermes-agent\agent\error_classifier.py#L24-L72) |
| E 外部 | 依赖健康度 | 4 | OSV 检测模式、无许可证扫描 CI | [pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L18-L37) |

### 2.2 加权总分

| 组 | 组权重 | 组内均分 | 加权贡献 |
|----|--------|----------|----------|
| A 功能 | 0.15 | 4.00 | 0.60 |
| B 代码质量 | 0.30 | 2.50 | 0.75 |
| C 运行时质量 | 0.25 | 3.67 | 0.92 |
| D 演进质量 | 0.20 | 4.00 | 0.80 |
| E 外部质量 | 0.10 | 4.00 | 0.40 |
| **总计** | **1.00** | | **3.47** |

- **总分: 3.47 / 4.0**
- **红黄绿灯**: 🟢 **绿灯**（总分 ≥ 3.0 且无否决）
- **否决项检查**: 安全性=4 / 可靠性=4 / 可测试性=3 → **0 个否决项触发**

### 2.3 雷达图数据（14 维）

```
功能:4 代码规范:2 架构约束:2 复用性:3 可测试性:3
性能:3 可靠性:4 可观测性:4 可扩展性:4 文档:4
构建CI:4 安全:4 易用:4 依赖:4
```

## 三、问题清单（按维度 × 严重度）

### 🔴 严重（影响上线/否决项触发）
- 无。三个否决项（安全/可靠/可测试）均 ≥ 3，未触发。

### 🟡 中等（影响维护效率）
- [代码规范] Python lint 门禁形同虚设（ruff 仅 PLW1514 一条规则阻塞，ty 全 `--exit-zero`） → [pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L450-L465) → 建议：分批启用 E/F/I/UP/B 规则集，ty 升级为阻塞门禁
- [架构约束] 8+ 个 god-file 系统性存在（gateway/run.py 26k、cli.py 17k、hermes_state.py 10k 等），无架构约束测试 → [run_agent.py](file:///D:\yaodh\main\hermes-agent\run_agent.py#L412-L494) → 建议：引入 import-linter，按 AGENTS.md wanted work 拆分 god-file
- [可测试性] 无覆盖率测量（无 pytest-cov/coverage 配置），e2e-desktop 硬关闭 → [pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L184) → 建议：接入 pytest-cov + `[tool.coverage.run]`
- [性能] 压测/基准测试为 opt-in、未进 CI，tenacity 依赖声明但零 import → [conftest.py](file:///D:\yaodh\main\hermes-agent\tests\stress\conftest.py#L13-L22) → 建议：benchmark 接入 nightly CI + 2x 回归阈值

### 🟢 轻微（可优化）
- [代码规范] 无 .editorconfig 跨编辑器基线 → 补 `.editorconfig`
- [架构约束] gateway/platforms/base.py 自身 6546 行 god-base → 抽公共 helper
- [复用性] 无 jscpd 重复检测、平台间 chunked_upload 未抽公共 → 接入 jscpd
- [可靠性] except:pass 散布 313 处（个别真实吞错无 logger.debug） → cleanup 路径加 `logger.debug(exc_info=True)`
- [可观测性] 分布式追踪仅覆盖 lifecycle/cron span，缺 per-call span + latency histogram → agent 主循环加 OTLP span
- [可观测性] session_tag 是 thread-local 非 contextvars，跨 async 不传播 → 改用 ContextVar
- [安全] OSV-Scanner `fail-on-vuln: false` 仅检测不阻断 → 高危 CVE 改为 `fail-on-vuln: severity high`
- [易用性] 未暴露独立 OpenAPI schema → 暴露 FastAPI `/docs`
- [依赖健康度] 无传递依赖许可证扫描 CI → 加 pip-licenses 步骤
- [文档] ADR 仅 1 条记录 → 补 prompt caching/Footprint Ladder/profile 隔离等 ADR

## 四、改进路线图（按优先级）

| 优先级 | 维度 | 改进项 | 预期收益 | 关联问题 |
|--------|------|--------|---------|---------|
| P0 | 代码规范 | ruff 启用 E/F/I/UP/B 核心规则集 + ty 阻塞门禁 | 代码规范 2→3，god-file 债务可控 | 🟡 lint 门禁形同虚设 |
| P0 | 架构约束 | 引入 import-linter 声明层契约 + 接入 CI | 架构约束 2→3，机器化防循环依赖 | 🟡 god-file 系统性 |
| P1 | 可测试性 | 接入 pytest-cov + 覆盖率门禁（branch 40% 起步） | 可测试性 3→4，覆盖率盲区消除 | 🟡 无覆盖率测量 |
| P1 | 架构约束 | 拆分 gateway/run.py（26k 行）按生命周期/调度/交付 | 架构约束 +1，维护效率提升 | 🟡 god-file |
| P1 | 性能 | benchmark 接入 nightly CI + 2x 回归阈值 | 性能 3→4，性能回归可发现 | 🟡 压测未进 CI |
| P2 | 安全 | OSV 高危 CVE 阻断 + 许可证扫描 CI | 安全 4→4（巩固），依赖 4→4（巩固） | 🟢 OSV 检测模式 |
| P2 | 可观测性 | agent 主循环加 OTLP span + latency histogram | 可观测性 4→4（巩固），RED/USE 完整 | 🟢 追踪范围有限 |
| P2 | 文档 | 补充 ADR 记录 + 暴露 OpenAPI | 文档 4→4（巩固） | 🟢 ADR 稀少 |

## 五、固化建议

- **标杆沉淀入 benchmarks/**: 是。该项目在**安全性纵深防御**（fail-closed 鉴权 + 1390 行脱敏 + 供应链 CI 门禁 + override-deps + exclude-newer 隔离）、**依赖治理**（精确锁定 + 上界政策成文 + dep-bounds CI + lazy-install 安全模型）、**可扩展性**（Footprint Ladder + 四源插件发现 + ABC+orchestrator 模式）、**可靠性**（多形态熔断 + 跨会话限流 + 幂等 epoch + 25+ FailoverReason 异常分类）四方面达业界标杆级，建议沉淀入 `benchmarks/agent-llm.md`（新标杆库）。
- **.trae/rules/ 补充约定**: 见 [project-rules.md](project-rules.md)（件 3）。
- **下次重评估建议时间**: 完成 P0/P1 改进后（预计 1-2 个迭代周期），重跑诊断模式对比评分卡，量化改进效果（预期总分 3.47 → 3.7+）。
