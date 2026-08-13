# Hermes Agent 质量评估 — 13 分维度文档索引

> 由 `project-analysis` 诊断模式产出。每维度按 `dims/<维度>.md` 锚点打分（0-4），带 `[basename](file:///绝对路径#L行号)` 实测证据。汇总评分卡见上级目录 [project-health.md](../project-health.md)。

## 评分总览

| # | 维度 | 组 | 分 | 否决项 | 文档 |
|---|------|----|----|--------|------|
| 1 | 代码规范 code-style | B | 2 | — | [01-code-style.md](01-code-style.md) |
| 2 | 架构约束 arch-rules | B | 2 | — | [02-arch-rules.md](02-arch-rules.md) |
| 3 | 复用性 reusability | B | 3 | — | [03-reusability.md](03-reusability.md) |
| 4 | 可测试性 testability | B | 3 | 否决(≠0) | [04-testability.md](04-testability.md) |
| 5 | 性能 performance | C | 3 | — | [05-performance.md](05-performance.md) |
| 6 | 可靠性 reliability | C | 4 | 否决(≠0) | [06-reliability.md](06-reliability.md) |
| 7 | 可观测性 observability | C | 4 | — | [07-observability.md](07-observability.md) |
| 8 | 可扩展性 extensibility | D | 4 | — | [08-extensibility.md](08-extensibility.md) |
| 9 | 文档完备度 documentation | D | 4 | — | [09-documentation.md](09-documentation.md) |
| 10 | 构建与CI build-ci | D | 4 | — | [10-build-ci.md](10-build-ci.md) |
| 11 | 安全性 security | E | 4 | 否决(≠0) | [11-security.md](11-security.md) |
| 12 | 易用性 usability | E | 4 | — | [12-usability.md](12-usability.md) |
| 13 | 依赖健康度 dependency-health | E | 4 | — | [13-dependency-health.md](13-dependency-health.md) |

## 分组与权重

| 组 | 维度 | 组权重 | 组内均分 |
|----|------|--------|----------|
| A 功能 | 功能特性 | 0.15 | 4.00 |
| B 代码质量 | 代码规范 / 架构约束 / 复用性 / 可测试性 | 0.30 | 2.50 |
| C 运行时质量 | 性能 / 可靠性 / 可观测性 | 0.25 | 3.67 |
| D 演进质量 | 可扩展性 / 文档 / 构建CI | 0.20 | 4.00 |
| E 外部质量 | 安全 / 易用 / 依赖 | 0.10 | 4.00 |

**加权总分：3.47 / 4.0 → 🟢 绿灯**（无否决项触发）

## 短板分布

- 🔴 主要短板集中在 **B 组代码质量**（代码规范 2、架构约束 2），根因是 Python 侧 god-file 系统性存在（cli.py 17k 行、gateway/run.py 26k 行）且 lint 门禁过弱（ruff 仅启用 1 条规则）。
- 🟡 次要短板在 **可测试性**（无覆盖率度量）与 **性能**（压测未进 CI）。
- 🟢 其余 9 个维度均为 4/4 满分，达业界一线水准。
