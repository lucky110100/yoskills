---
dim: documentation
group: D
---

# 文档完备度 — 维度分析卡（stub）

> 维度归属：D 演进质量组。评估 README、API 文档、架构文档、ADR、注释。**对标要点待阶段 2 补全。**

## 评估信号（发现即记）

- 无 README 或 README 过时
- 无 API 文档
- 无架构文档
- 无 ADR（关键决策无记录）
- 注释缺失或与代码不符

## 评估工具与命令

| 工具 | 命令/用法 | 看什么 |
|------|----------|--------|
| Glob | 查 README/docs 目录/adr 目录 | 文档结构存在性 |
| Read | 读 README | 是否过时/与代码一致 |
| Glob | 查 API 文档（OpenAPI/javadoc/tsdoc） | API 文档存在性 |
| Grep | 查注释密度 | 注释覆盖 |

## 评分锚点（5 档）

| 分 | 锚点信号 |
|----|---------|
| 4 | README 完整且新 + API 文档 + 架构文档 + ADR + 注释覆盖关键决策 |
| 3 | README + 部分 API 文档 + 无 ADR |
| 2 | README 简陋 + 无 API 文档 |
| 1 | 文档零散 + 与代码不符 |
| 0 | 无任何文档 |

## 规范基线

- ✅ 应：README + API 文档 + 架构文档 + ADR（关键决策） + 注释记 why
- ❌ 不做：文档与代码不符 + 注释只写 what + 关键决策无 ADR

## 对标要点（业界标杆看哪些）

- Python: 看 FastAPI 自动 OpenAPI、Django 的 `docs/`(官方文档标杆)、requests 的 readthedocs
- Java: 看 mall 的 `document/` 与 macrozheng 博客、Spring Boot 的 reference docs
- 对比 README/API 文档/架构文档/ADR 完备度

## 反模式

```
❌ README 过时不更新（误导）
❌ 注释只写 what 不写 why
❌ 关键架构决策无 ADR（后续不知为何如此）
```

## Checklist

- [ ] README 是否存在且新
- [ ] 是否有 API 文档
- [ ] 是否有架构文档/ADR
- [ ] 注释是否覆盖关键决策
