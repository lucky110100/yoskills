# 09 文档完备度 documentation

> 维度归属：D 演进质量组。评估 README、API 文档、架构文档、ADR、注释。
>
> 配套：[汇总评分卡](../project-health.md) | [索引](README.md)

## 评分：4 / 4

三语 README（zh/es/ur-pk）、1240+ 行 AGENTS.md 开发宪法、Docusaurus 文档站 150+ 页（含 architecture 系统图、developer-guide 30+ 篇）、docs/ADR.md 正规四段式 ADR、5 篇生命周期设计文档、模块级 README 全覆盖、代码注释极密。仅观察项：ADR 仅 1 条记录、无机器可读 OpenAPI schema（因 API 是 OpenAI 兼容，复用外部 spec）。

## 评估过程

### 亮点（带 file:/// 证据）

- ✅ **多语言 README** — 中文 README.zh-CN.md、西班牙语 README.es.md、乌尔都语 README.ur-pk.md → [README.md](file:///D:\yaodh\main\hermes-agent\README.md#L14-L16)。
- ✅ **AGENTS.md 开发宪法**（1240+ 行）— 贡献准则、Footprint Ladder、CLI/TUI/Desktop 架构、插件系统、技能标准、测试哲学、已知陷阱全覆盖 → [AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L1-L5)。
- ✅ **CONTRIBUTING.md** — 贡献优先级、skill vs tool 决策、搜索先行 → [CONTRIBUTING.md](file:///D:\yaodh\main\hermes-agent\CONTRIBUTING.md#L1-L18)。
- ✅ **docs/ 设计文档** — ADR.md（正规 Status/Context/Decision 四段式）、billing-lifecycle.md、micro-compaction.md、profile-routing.md、session-lifecycle.md、streaming-tts.md、middleware/README.md → [docs/ADR.md](file:///D:\yaodh\main\hermes-agent\docs\ADR.md#L1-L60)。
- ✅ **Docusaurus 文档站 200+ 页** — getting-started/（7 篇）、guides/（30+ 篇）、reference/（8 篇：cli-commands/environment-variables/slash-commands/tools-reference/model-catalog 等）、user-guide/features/（40+ 篇）、user-guide/messaging/（30+ 平台）、user-guide/skills/（100+ 技能）、developer-guide/（30+ 篇）、integrations/。
- ✅ **模块级 README** — apps/desktop/README.md + DESIGN.md + AGENTS.md、website/README.md、tests/stress/README.md、evals/readtool/README.md、native/fts5_cjk/README.md、contributors/README.md、docker/SOUL.md。
- ✅ **代码注释极密** — pyproject.toml 每个依赖都有 CVE/why 注释（如 requests CVE-2026-25645、cryptography 6 项 CVE 编号），是注释覆盖关键决策的范本 → [pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L18-L37)。
- ✅ **SECURITY.md** — 安全政策文档 → [SECURITY.md](file:///D:\yaodh\main\hermes-agent\SECURITY.md)。

### 观察项（非短板）

1. **ADR 仅 1 条记录** — docs/ADR.md 目前只有 2026-07-13 的"plugin manager state scope"一条。ADR 流程已建立，但记录稀少 → [docs/ADR.md](file:///D:\yaodh\main\hermes-agent\docs\ADR.md#L3-L5)。
2. **无机器可读 OpenAPI schema** — API Server 复刻 OpenAI Chat Completions 格式，以手写 api-server.md 说明，未暴露 `/docs` 自动 OpenAPI。这是合理取舍（复用外部 spec）→ [api-server.md](file:///D:\yaodh\main\hermes-agent\website\docs\user-guide\features\api-server.md#L56-L60)。

## Checklist 对照

- [x] README 是否存在且新 — ✅ 三语 + 完整 Quick Install/Getting Started
- [x] 是否有 API 文档 — ✅ Docusaurus + reference/ + developer-guide/
- [x] 是否有架构文档/ADR — ✅ AGENTS.md 架构宪法 + docs/ADR.md（流程已建）
- [x] 注释是否覆盖关键决策 — ✅ pyproject.toml 注释范本级

## 改进建议

1. 补充更多 ADR 记录（prompt caching 策略、Footprint Ladder、profile 隔离等关键决策都值得 ADR）。
2. 为 API Server 暴露 FastAPI 自带的 `/docs`（OpenAPI），便于前端自动集成。
