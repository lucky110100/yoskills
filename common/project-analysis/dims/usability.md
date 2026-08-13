---
dim: usability
group: E
---

# 易用性 — 维度分析卡（stub）

> 维度归属：E 外部质量组。评估 API 版本化、文档、错误信息、CLI 补全、配置校验、最小示例。**对标要点待阶段 2 补全。**

## 评估信号（发现即记）

- API 无版本/无文档
- 错误信息不可读（无上下文/无修复建议）
- CLI 无帮助/无补全
- 配置项无默认/无校验
- 无最小可用示例（getting started）

## 评估工具与命令

| 工具 | 命令/用法 | 看什么 |
|------|----------|--------|
| RunCommand | 跑 CLI `--help` | 帮助完备度 |
| Glob | 查 OpenAPI/swagger 文档 | API 文档存在性 |
| Grep | 查错误信息字符串 | 可读性与上下文 |
| Glob | 查 examples/ getting-started | 最小示例存在性 |

## 评分锚点（5 档）

| 分 | 锚点信号 |
|----|---------|
| 4 | API 版本化 + OpenAPI 文档 + CLI 补全 + 错误可读带修复建议 + 最小示例 + 配置校验 |
| 3 | 有 API 文档 + 错误基本可读 + 有示例 |
| 2 | API 无版本 + 错误模糊 + 无补全 |
| 1 | 无文档 + 错误不可读 + 无示例 |
| 0 | 用户无法上手 |

## 规范基线

- ✅ 应：API 版本化 + OpenAPI 文档 + CLI 补全 + 错误带上下文与修复建议 + getting started 示例 + 配置校验
- ❌ 不做：错误只抛 "failed" + 无文档 + 配置无校验静默失败

## 对标要点（业界标杆看哪些）

- Python: 看 FastAPI 自动 OpenAPI 与"for Humans"设计、requests 的 API 设计、Pydantic 类型驱动 API
- Java: 看 mall 的文档体系(macrozheng 博客)
- 对比错误信息可读性与 getting started 示例完备度

## 反模式

```
❌ 错误信息只写 "failed"（用户无从下手）
❌ API 无版本（破坏性变更无预警）
❌ 无 getting started（上手成本高）
```

## Checklist

- [ ] API 是否版本化 + 有文档
- [ ] 错误信息是否可读带修复建议
- [ ] CLI 是否有补全
- [ ] 是否有最小示例
