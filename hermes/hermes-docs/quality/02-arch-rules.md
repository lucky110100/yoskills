# 02 架构约束 arch-rules

> 维度归属：B 代码质量组。评估分层规则、依赖方向、循环依赖、职责划分。
>
> 配套：[汇总评分卡](../project-health.md) | [索引](README.md)

## 评分：2 / 4

分层清晰、依赖方向有文档、registry 显式声明循环安全、插件面有 ABC，但**无架构约束测试（import-linter/ArchUnit 缺失）**，且 god-file/god-class **普遍存在而非"个别"**（8+ 个文件超 5000 行、多个超 1 万行），AIAgent 构造器 60+ 参数。命中"基本分层+个别上帝类"偏重一侧，但 god-file 规模已非"个别"，故 2 分。

## 评估过程

### 关键问题（带 file:/// 证据）

1. **无 import-linter / ArchUnit 配置** — Glob `**/.importlinter*` 无结果，pyproject.toml 无 `[tool.importlinter]` 段，分层与依赖方向仅靠文档约定，无机器化校验。

2. **巨型 god-file 遍布各核心模块**（实测行数）：gateway/run.py 26468、cli.py 17060、hermes_cli/web_server.py 15788、hermes_cli/main.py 11233、hermes_state.py 10477、hermes_cli/kanban_db.py 10295、agent/auxiliary_client.py 9277、agent/conversation_loop.py 7402、run_agent.py 7658。

3. **AIAgent 为 god-class** — `class AIAgent:` 在 7658 行文件中，`__init__` 自第 435 行起含 60+ 参数（AGENTS.md 第 355 行自述"~60 parameters"）→ [run_agent.py](file:///D:\yaodh\main\hermes-agent\run_agent.py#L412-L494)、[AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L353-L357)。

4. **gateway/platforms/base.py 自身 6546 行** — 既是"共享基类"也是 god-base，承载所有平台适配器的公共逻辑。

### 亮点

- ✅ **依赖方向有显式文档与实现约束** — registry.py 顶部画出 import 链并标注"circular-import safe" → [tools/registry.py](file:///D:\yaodh\main\hermes-agent\tools\registry.py#L1-L15)；AGENTS.md 复述同一链条 → [AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L339-L349)。
- ✅ **插件面有清晰 ABC**：MemoryProvider（agent/memory_provider.py 第 81 行）、ProviderProfile（providers/base.py 第 38-40 行）、平台基类（gateway/platforms/base.py 第 1-6 行，import ABC/abstractmethod）→ [agent/memory_provider.py](file:///D:\yaodh\main\hermes-agent\agent\memory_provider.py#L81-L89)、[providers/base.py](file:///D:\yaodh\main\hermes-agent\providers\base.py#L38-L40)。
- ✅ **目录分层清晰** — agent/（Agent 内部）/ tools/（工具）/ gateway/（消息网关）/ hermes_cli/（CLI 子命令）/ providers/（推理后端）/ plugins/（插件）/ cron/（调度）各司其职，且 AGENTS.md 明确"core 是窄腰、能力在边缘"的设计意图 → [AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L24-L28)。
- ✅ **toolset surface gate** — `_HERMES_CORE_TOOLS` vs 命名 toolset 区分核心工具与按需工具，AGENTS.md 的 Footprint Ladder 定义六级扩展决策阶梯 → [AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L182-L206)。

## Checklist 对照

- [x] 目录结构是否清晰反映分层 — ✅ 清晰
- [ ] 是否有架构约束测试 — ❌ 无 import-linter/ArchUnit
- [ ] 是否扫了循环依赖 — ❌ 无机器化扫描（仅文档约定）
- [x] 领域层是否耦合框架 — ✅ ABC 抽象隔离较好
- [ ] 是否无上帝类 — ❌ 8+ 个 god-file

## 改进建议

1. 引入 import-linter（`pip install import-linter`），在 pyproject.toml 声明 `agents → tools`、`gateway → agent/tools` 等层契约，接入 CI 阻塞门禁，机器化防循环依赖与跨层调用。
2. 按 AGENTS.md 自述的"wanted work"，把 gateway/run.py（26k 行）按会话生命周期/调度/交付/健康检查拆为子模块。
3. 给 AIAgent 引入 Builder/Config 数据类收敛 60+ 构造参数，或拆分为 Orchestrator + ProviderRouter + ToolRouter。
