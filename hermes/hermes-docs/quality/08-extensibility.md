# 08 可扩展性 extensibility

> 维度归属：D 演进质量组。评估扩展点、插件机制、接口抽象、配置驱动。
>
> 配套：[汇总评分卡](../project-health.md) | [索引](README.md)

## 评分：4 / 4

项目核心强项。"窄核心+边缘能力"设计哲学被忠实执行：四源插件发现、25+ 生命周期钩子白名单、MemoryProvider/ProviderProfile ABC 抽象、ToolRegistry 带 override/权限保护、_HERMES_CORE_TOOLS vs 命名 toolset 的 surface gate、Web Dashboard slot 注入、Footprint Ladder 六级扩展决策阶梯、15+ 可扩展界面的完整文档矩阵。

## 评估过程

### 亮点（带 file:/// 证据）

- ✅ **Footprint Ladder 六级扩展决策阶梯** — 明确新能力的最小足迹路径：Extend existing → CLI+skill → Service-gated tool(check_fn) → Plugin → MCP server → New core tool(last resort) → [AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L182-L206)。
- ✅ **四源插件发现** — PluginManager 从 `~/.hermes/plugins/`、`./.hermes/plugins/`、pip entry points、repo 内 `plugins/` 发现插件 → [AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L780-L798)。
- ✅ **生命周期钩子白名单** — `pre_tool_call`/`post_tool_call`/`pre_llm_call`/`post_llm_call`/`on_session_start`/`on_session_end`，签名自省兼容旧窄签名回调 → [AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L786-L790)。
- ✅ **MemoryProvider ABC + orchestrator** — `sync_turn`/`prefetch`/`shutdown`/`post_setup` 契约，由 memory_manager 编排 → [agent/memory_provider.py](file:///D:\yaodh\main\hermes-agent\agent\memory_provider.py#L81-L89)。
- ✅ **ProviderProfile ABC** — 每个推理后端以插件形式注册，last-writer-wins 覆盖，用户插件可覆盖内置 → [providers/base.py](file:///D:\yaodh\main\hermes-agent\providers\base.py#L38-L40)、[AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L879-L896)。
- ✅ **ToolRegistry 中央注册** — AST 扫描自发现、memoized、circular-import safe，工具文件 `registry.register()` 即接入；`check_fn` 实现 service-gated tool（按配置出现/消失）→ [tools/registry.py](file:///D:\yaodh\main\hermes-agent\tools\registry.py#L1-L15)。
- ✅ **_HERMES_CORE_TOOLS vs 命名 toolset 的 surface gate** — 核心工具 vs 按需工具区分，每平台按 base toolset 继承 → [AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L1028-L1044)。
- ✅ **skills/ 与 optional-skills/ 双层技能系统** — 内置技能默认加载，重型/小众技能按需安装 → [AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L917-L933)。
- ✅ **插件并发原语** — `lazy_singleton` / `SingletonSlot` 为插件作者解决 TOCTOU 单例竞态 → [plugins/plugin_utils.py](file:///D:\yaodh\main\hermes-agent\plugins\plugin_utils.py#L1-L38)。
- ✅ **配置驱动** — `DEFAULT_CONFIG` + user YAML 深合并，配置版本迁移；`.env` 仅限密钥 → [AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L620-L681)。
- ✅ **扩展文档矩阵** — website/docs/developer-guide/ 含 plugins/、model-provider-plugin、web-search-provider-plugin、video-gen-provider-plugin、secret-source-plugin、subagent-lifecycle-api 等 15+ 扩展指南。
- ✅ **插件兼容契约** — 行为契约而非版本号；钩子 payload 加性新增；签名自省兼容旧回调；deprecation 需两次 minor + 迁移说明 → [AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L800-L823)。

### 观察项（非短板）

1. gateway/builtin_hooks/ 当前为空目录（无内置钩子 shipped），但扩展点已就位 → [AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L288-L289)。

## Checklist 对照

- [x] 是否有扩展点/插件机制 — ✅ 四源发现 + 钩子 + ABC + 技能 + MCP
- [x] 是否面向接口 — ✅ MemoryProvider/ProviderProfile/平台基类 ABC
- [x] if-else 分支是否过多 — ✅ 用 registry/strategy 替代
- [x] 是否配置驱动 — ✅ config.yaml + DEFAULT_CONFIG 深合并

## 改进建议

1. gateway/builtin_hooks/ 可补一个示例钩子作为文档锚点，降低新贡献者理解门槛。
2. 可扩展界面虽多但分散在多个文档，建议补一张"扩展点总览图"统一索引。
