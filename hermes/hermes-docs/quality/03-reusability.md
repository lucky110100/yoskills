# 03 复用性 reusability

> 维度归属：B 代码质量组。评估重复代码、公共模块清晰度、抽象恰当性。
>
> 配套：[汇总评分卡](../project-health.md) | [索引](README.md)

## 评分：3 / 4

公共模块清晰（registry / hermes_constants / plugin_utils / 多个 ABC），抽象恰当（插件 ABC + orchestrator 模式，last-writer-wins 覆盖），AGENTS.md 有强"Extend, don't duplicate"指引。但无重复检测工具（jscpd/duplicate-finder 缺失），且巨型 god-file 内部易积累重复块。落 3 分"偶有重复+公共模块基本清晰"。

## 评估过程

### 关键问题（带 file:/// 证据）

1. **无重复代码检测配置** — Glob `**/{.jscpd*,jscpd*,duplicate*,.cpd*}` 无结果；巨型文件（gateway/run.py 26k、cli.py 17k）内部重复模式无从量化。

2. **平台适配器间存在可复用但未抽公共的迹象** — gateway/platforms/ 下平台适配器虽共享 base.py，但 base.py 自身 6546 行；yuanbao 系列拆为 4 文件（yuanbao.py/yuanbao_media.py/yuanbao_proto.py/yuanbao_sticker.py）、whatsapp 拆为 whatsapp_cloud.py/whatsapp_common.py；chunked_upload 仅 qqbot 有，未抽公共。

### 亮点

- ✅ **tools/registry.py 中央注册机制** — AST 扫描自发现、memoized、circular-import safe，所有工具文件 `registry.register()` 即接入 → [tools/registry.py](file:///D:\yaodh\main\hermes-agent\tools\registry.py#L1-L15)。
- ✅ **hermes_constants.py 是"import-safe、零依赖、单一真相源"的公共常量模块**（get_hermes_home/display_hermes_home/INDICATOR_STYLES，ContextVar 线程安全 profile 作用域）→ [hermes_constants.py](file:///D:\yaodh\main\hermes-agent\hermes_constants.py#L1-L27)。
- ✅ **plugins/plugin_utils.py 为插件作者提供线程安全原语**（lazy_singleton / SingletonSlot），stdlib-only 轻量可复用 → [plugins/plugin_utils.py](file:///D:\yaodh\main\hermes-agent\plugins\plugin_utils.py#L1-L38)。
- ✅ **跨工具复用已抽象** — agent/file_safety.py 的 `build_write_denied_paths` 被 tools/file_operations.py 复用 → [tools/file_operations.py](file:///D:\yaodh\main\hermes-agent\tools\file_operations.py#L41-L57)。
- ✅ **AGENTS.md 明文指引**"3+ 个同类 PR 到来时设计 ABC + orchestrator"，并已落地于 memory/model-provider/context-engine/image-gen 四类插件面 → [AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L207-L211)。

## Checklist 对照

- [ ] 是否扫了重复代码 — ❌ 无 jscpd
- [x] 公共模块是否清晰 — ✅ registry/constants/plugin_utils 清晰
- [x] 是否过度抽象 — ✅ 抽象恰当（Footprint Ladder 约束）
- [x] 循环依赖是否阻碍复用 — ✅ registry 显式标注循环安全

## 改进建议

1. 接入 jscpd（或 dup）对 Python 与 TS 各跑一次，量化巨型文件内重复率，给重构排优先级。
2. 把 qqbot/chunked_upload.py 的分片上传逻辑抽到 gateway/platforms/ 公共 helper，供 yuanbao/whatsapp 等大附件平台复用。
3. 给公共模块（hermes_constants、plugin_utils、registry）补一份"复用入口"索引文档，降低新贡献者重新发明轮子的概率。
