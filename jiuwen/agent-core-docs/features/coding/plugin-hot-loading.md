# 编码插件热加载

> 交叉引用: [01-项目概述](../../01-project-overview.md) | [02-整体架构](../../02-overall-architecture.md) | [04-harness模块](../../04-harness-module.md) | [06-agent_evolving与dev_tools模块](../../06-agent-evolving-and-dev-tools-module.md) | [07-extensions与rsi模块](../../07-extensions-and-rsi-module.md)

## 一、能力概述

agent-core 的 DeepAgent 不在启动时把所有能力"焊死",而是支持在运行中按需加载/卸载插件包,这一能力由 `harness/extension_binder.py` 与 `harness/resources/` 子模块协同实现。插件包以 YAML/JSON 清单(如 `harness_config.yaml`、`manifest.json`)声明自己提供哪些资源——工具(tool)、MCP 服务、护栏(rail)、提示词片段(prompt section)、技能(skill)、子代理(subagent)——框架在运行时把这些资源解析为统一的 ExtensionParts,再绑定到已存在的 DeepAgent 实例上,全程不重启进程。

这套机制覆盖的六类资源各有用途:TOOL 扩展 Agent 可调用的工具(如自定义数据查询工具);MCP 接入外部 MCP 服务器(如数据库、API 网关);RAIL 注入新的生命周期护栏(如自定义安全规则);PROMPT_SECTION 增补或替换系统提示词(含 identity 人格);SKILL 提供某类任务的操作手册(指导工具如何组合使用);SUBAGENT 注册可被主 Agent 调度的子代理。六类资源统一抽象为 ResourceKind,经同一套绑定/卸载链路管理,使插件包可以"打包多种资源一次加载"。

这套机制的关键设计有三点:**事务性**(绑定失败自动回滚已绑定资源,避免半绑定状态)、**清单驱动**(用声明式 YAML/JSON 描述资源,而非硬编码注册)、**声明式注册**(通过 `harness_element` 装饰器捕获元素 schema,供内省与未来配置生成)。它让 Agent 能在会话中途"长出新能力"——例如临时加载一个数据库查询 MCP、或加载一个新 skill 指导某类改码任务,任务结束后再卸载,实现能力按需供给。

与静态配置相比,热加载的优势在于"运行时可见":Agent 在会话中根据任务需要主动决定加载哪些能力,而非在启动前就把所有可能用到的工具都注册好。这既降低了常驻工具集的规模(减少 prompt 上下文与 token 消耗),又让 Agent 具备了"遇到新任务时自我武装"的能力,是 agent-core 走向自进化的基础。auto_harness 的 [ExtendImplementStage](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/auto_harness/stages/implement.py#L646) 甚至能让 Agent 在 worktree 内自主生成新的扩展包并通过热加载立即生效,形成"发现能力缺口→生成扩展→加载使用"的闭环。

## 二、关键类与函数

| 类/函数 | 文件位置 | 说明 |
|---------|---------|------|
| apply_extension_hot | [extension_binder.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/extension_binder.py#L27) | 把 ExtensionParts 绑定到运行中 DeepAgent,失败自动回滚 |
| unapply_extension_hot | [extension_binder.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/extension_binder.py#L62) | 卸载已绑定资源,供事务回滚与显式卸载调用 |
| _bind_tool | [extension_binder.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/extension_binder.py#L89) | 绑定 Tool/ToolCard,写入 ability_manager 与 config.tools |
| _bind_mcp | [extension_binder.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/extension_binder.py#L111) | 绑定 McpServerConfig 到 deep_config.mcps |
| _bind_rail | [extension_binder.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/extension_binder.py#L150) | 绑定 AgentRail 到 DeepAgent |
| _bind_prompt_section | [extension_binder.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/extension_binder.py#L158) | 绑定提示词片段(可替换 identity 段并快照) |
| _bind_skill | [extension_binder.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/extension_binder.py#L210) | 绑定 Skill 资源 |
| _bind_subagent | [extension_binder.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/extension_binder.py#L282) | 绑定子代理并确保 subagent rail 就绪 |
| load_plugin | [deep_agent.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/deep_agent.py#L1669) | DeepAgent 入口:从路径热加载文件型插件包 |
| load_plugin_spec | [deep_agent.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/deep_agent.py#L1696) | 热加载内存中的 PluginSpec |
| load_agent_template | [deep_agent.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/deep_agent.py#L1718) | 热加载 AgentTemplate(含 identity 提示词替换) |
| load_harness_config | [deep_agent.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/deep_agent.py#L1798) | 热加载 harness 配置 |
| unload_extension | [deep_agent.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/deep_agent.py#L1775) | 按 load_id 卸载已加载资源 |
| find_plugin_manifest | [resources/](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/resources/) | 按查找顺序定位插件清单文件 |
| load_plugin_package | [resources/](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/resources/) | 从清单加载并构建 PluginSpec |
| resolve_plugin_parts | [resources/](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/resources/) | 把 PluginSpec 解析为可绑定的 ExtensionParts |
| harness_element | [catalog.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/manifest/catalog.py#L67) | 声明式元素描述符装饰器,捕获 schema |
| list_elements | [catalog.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/manifest/catalog.py#L55) | 列出所有 harness 元素及其 JSON schema |
| ResourceKind | [extension_binder.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/extension_binder.py#L27) | 枚举六类可加载资源:TOOL/MCP/RAIL/PROMPT_SECTION/SKILL/SUBAGENT |
| ExtensionParts | [resources/](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/resources/) | 解析后的可绑定部件集合,含 tools/mcps/rails/prompt_sections/skills/subagents |
| PluginSpec | [resources/](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/resources/) | 插件规格,由清单加载而来,resolve 前的中间表示 |
| LoadRecord | [deep_agent.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/deep_agent.py#L1669) | 一次加载的账本记录,含 load_id 与 refs,供卸载索引 |

## 三、实现机制

### 3.1 六类可加载资源(ResourceKind)

[apply_extension_hot](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/extension_binder.py#L27) 接收一个 ExtensionParts,按固定顺序绑定六类资源:TOOL→MCP→RAIL→PROMPT_SECTION→SKILL→SUBAGENT。绑定顺序并非随意:先绑定 TOOL/MCP 这类无状态能力,再绑定 RAIL(可能依赖已注册的工具),接着注入 PROMPT_SECTION(可能引用已存在的能力名),随后 SKILL(指导工具使用),最后 SUBAGENT 并确保 subagent rail 就绪。这一顺序保证后绑定资源可引用先绑定资源,减少引用缺失。每类资源有独立的绑定函数:

- **TOOL**([_bind_tool](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/extension_binder.py#L89)):把 Tool/ToolCard 注册到 ability_manager,并追加到 deep_config.tools;同名 tool 已存在则抛错。
- **MCP**([_bind_mcp](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/extension_binder.py#L111)):把 McpServerConfig 加入 deep_config.mcps,同 server_id 重复绑定会抛错。
- **RAIL**([_bind_rail](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/extension_binder.py#L150)):把 AgentRail 挂载到 DeepAgent 的 rail 链。
- **PROMPT_SECTION**([_bind_prompt_section](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/extension_binder.py#L158)):注入提示词片段,identity 段会先快照再替换,便于卸载时还原。
- **SKILL**([_bind_skill](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/extension_binder.py#L210)):绑定 Skill 资源,供后续 implement 阶段作为操作手册。
- **SUBAGENT**([_bind_subagent](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/extension_binder.py#L282)):注册子代理,并自动确保 subagent rail 就绪。

### 3.2 事务性绑定与回滚

[apply_extension_hot](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/extension_binder.py#L27) 用 try/except 包裹整个绑定循环:任一资源绑定失败,立即调用 [unapply_extension_hot](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/extension_binder.py#L62) 回滚本次调用已绑定的 refs,然后 re-raise。这意味着一次 `load_plugin` 要么全部成功,要么 DeepAgent 状态保持不变,绝不会停留在"绑定了一半"的中间态——这对长时间运行的 Agent 会话至关重要。

事务边界的粒度是"单次 apply_extension_hot 调用",而非"单个资源"。也就是说,一个含 6 个资源的插件包,若第 4 个绑定失败,前 3 个已绑定资源会一起回滚,而非留下 3 个。这种"整批原子"语义,避免了部分加载导致的资源间引用断裂(如 rail 引用了未加载成功的 tool)。

DeepAgent 侧通过 `_load_records` 账本按 load_id 记录每次加载产出的 refs,[unload_extension](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/deep_agent.py#L1775) 据此卸载;未知或已卸载的 id 是 no-op,只卸载账本拥有的 refs。

### 3.3 清单驱动与 Legacy 映射

[load_plugin](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/deep_agent.py#L1669) 接受路径,内部依次调用 find_plugin_manifest→load_plugin_package→resolve_plugin_parts→apply_extension_hot。find_plugin_manifest 按查找顺序支持 `packageType=plugin` 的 `manifest.json` 与遗留的 `harness_config.yaml`/`expert_harness.yaml`/`harness.yaml`。

这种"清单查找 → 规格构建 → 部件解析 → 热绑定"的四步流水线,把"从磁盘读清单"与"绑定到 Agent"解耦:前三步是纯数据变换(可独立测试、可缓存),只有第四步产生副作用。这种解耦让插件包的校验、预览、diff 都可在不触碰 DeepAgent 的前提下完成。

[extension_loader.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/resources/extension_loader.py#L82) 的 `_LEGACY_TOOL_TO_RAIL`(L82-L100)负责把遗留 YAML 中错放在 `tools` 下的 rail 能力名(filesystem/shell/bash/powershell/code/lsp/todo/ask_user)重映射到真正的 Rail provider(core.sys_operation/core.lsp/core.task_planning/core.ask_user),让旧清单也能平滑迁移到 PluginSpec。这一映射的存在,使得早期版本编写的 harness_config.yaml 无需改写即可在新框架下运行,降低了升级成本。load_plugin_package 在构建 PluginSpec 前会先过这一映射,确保资源类型归类正确。

### 3.4 声明式注册与内省

[harness_element](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/manifest/catalog.py#L67) 装饰器用于声明一个可序列化的 harness 元素描述符,捕获 kind/name/description/input_schema/builder 等元数据,存入模块级 `_CATALOG`。它只做元数据捕获,不做 provider 注册(注册交给 `register_from_catalog`)。[list_elements](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/manifest/catalog.py#L55) 把所有描述符序列化为 JSON 列表,作为"列出所有可用 harness 元素及其 schema"的内省入口,适合工具自动发现与未来配置生成。

### 3.5 DeepAgent 加载入口的完整生命周期

DeepAgent 提供一组加载入口,覆盖不同来源与形态:[load_plugin](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/deep_agent.py#L1669) 从文件路径加载(支持 `manifest.json` 与遗留 `harness_config.yaml`);[load_plugin_spec](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/deep_agent.py#L1696) 从内存中的 PluginSpec 加载(路径字段须已是绝对路径);[load_agent_template](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/deep_agent.py#L1718) 加载 AgentTemplate(含 identity 提示词替换);[load_harness_config](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/deep_agent.py#L1798) 加载 harness 配置。所有入口最终都汇聚到 `_apply_extension_parts`→`apply_extension_hot`,并返回 LoadRecord 记入 `_load_records` 账本。[unload_extension](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/deep_agent.py#L1775) 据账本精确卸载,未知或已卸载的 id 是 no-op。

### 3.6 identity 提示词替换与快照

PROMPT_SECTION 类资源中,identity 段(定义 Agent 自我认知的提示词)会被特殊处理:[_bind_prompt_section](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/extension_binder.py#L158) 在替换 identity 段前先做快照,记录原始提示词。这样当 AgentTemplate 被卸载或回滚时,能恢复原始 identity,避免"加载了 A 模板又加载 B 模板"后 identity 拥留混乱。这一设计让 identity 提示词也能像工具一样可逆加载/卸载,支撑"一个 DeepAgent 在会话中切换多种专家人格"的场景。

### 3.7 同名资源冲突与账本

[apply_extension_hot](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/extension_binder.py#L27) 对同名/同 identity 资源采取"已存在即抛错"策略:同名 tool、同 server_id 的 MCP、重复 identity 段都会让绑定抛异常并触发回滚。这避免了"后加载覆盖先加载"的隐式冲突,要求插件包显式声明唯一命名。每次成功加载返回的 [LoadRecord](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/deep_agent.py#L1669) 含唯一 load_id 与 refs 列表,DeepAgent 用 `_load_records` 字典按 load_id 索引;[unload_extension](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/deep_agent.py#L1775) 只卸载账本拥有的 refs(忽略调用方传入的 record.refs),保证卸载的权威性,防止外部篡改导致误卸。

## 四、调用示例

```python
import asyncio
from openjiuwen.harness.factory import create_deep_agent
from openjiuwen.harness.resources import (
    find_plugin_manifest,
    load_plugin_package,
    resolve_plugin_parts,
)

async def hot_load_plugin(agent, plugin_dir: str):
    # 1. 定位清单(harness_config.yaml 或 manifest.json)
    manifest = find_plugin_manifest(plugin_dir)
    # 2. 从清单构建 PluginSpec(遗留清单会过 _LEGACY_TOOL_TO_RAIL 映射)
    plugin_spec = load_plugin_package(manifest)
    # 3. 解析为可绑定的 ExtensionParts(base_dir 用于解析相对路径)
    parts = resolve_plugin_parts(plugin_spec, base_dir=str(manifest.parent))
    # 4. 热加载到运行中的 DeepAgent(失败自动回滚)
    record = await agent.load_plugin_spec(plugin_spec)
    print("loaded refs:", [r.kind for r in record.refs])
    # record.refs 是 ResourceRef 列表,每项含 kind/identity,
    # 卸载时按 load_id 从账本精确回收这些资源

    # ... 在会话中使用新加载的 tool/skill ...

    # 5. 任务结束后卸载(恢复 identity 提示词等可逆资源)
    await agent.unload_extension(record)
    return record

async def main():
    agent = create_deep_agent(model=_build_model())
    await hot_load_plugin(agent, "/path/to/my-plugin")

asyncio.run(main())
```

上述流程的关键安全保证:[apply_extension_hot](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/extension_binder.py#L27) 在绑定任一资源失败时,会先 `unapply_extension_hot` 回滚本次已绑定的全部 refs 再 re-raise,因此 `load_plugin_spec` 要么整体成功、要么 DeepAgent 状态不变。任务结束后调用 [unload_extension](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/deep_agent.py#L1775) 传入 LoadRecord,账本会精确卸载本次加载的工具/MCP/rail/prompt/skill/subagent,包括恢复被替换的 identity 提示词。

需要注意,热加载的"热"是指 DeepAgent 实例运行中加载,而非跨进程。若 DeepAgent 进程重启,已加载的扩展不会自动恢复——需要重新调用 load_plugin。持久化扩展应写入启动配置(harness_config),由初始化流程在 DeepAgent 构造时静态注册;热加载适用于"会话中临时按需"的场景。

因此,工程实践中常见的模式是:核心能力(文件/Shell/LSP 等高频工具)走静态注册,保证常驻可用;领域专用能力(某项目特有的查询 MCP、某类改码的 skill)走热加载,按会话需求加载与卸载,兼顾基线稳定与按需扩展。

## 五、业界对比

| 维度 | agent-core | Cursor | Claude Code | GitHub Copilot |
|------|-----------|--------|-------------|----------------|
| 运行时热加载 | ✅ 进程内动态绑定 | ❌ 需重启/重载 | ❌ 需重启 | ❌ 固定扩展市场 |
| 可加载资源类型 | ✅ 6 类(tool/mcp/rail/prompt/skill/subagent) | ❌ 仅 MCP | ✅ MCP+skill | ❌ 仅 MCP |
| 事务性回滚 | ✅ 绑定失败自动 unapply | ❌ 无 | ❌ 无 | ❌ 无 |
| 清单驱动 | ✅ YAML/JSON 声明式 | ❌ 配置文件 | ✅ TOML | ❌ 无 |
| 声明式注册 | ✅ harness_element+schema 内省 | ❌ 无 | ❌ 无 | ❌ 无 |
| 动态卸载 | ✅ load_id 账本精确卸载 | ❌ 无 | ❌ 无 | ❌ 无 |

> 对比说明:多数编码助手在启动时把工具集焊死,运行中无法增减;Cursor 仅支持 MCP 但需重载;Claude Code 支持 MCP 与 skill 但缺乏事务性回滚;agent-core 的差异在于六类资源统一热加载 + 事务性回滚 + 账本精确卸载,使 Agent 能力在会话中可逆生长,支撑"按需供给 + 自我进化"。

## 六、小结

插件热加载让 agent-core 的 DeepAgent 从"能力静态固定"进化为"能力按需生长"。通过 [apply_extension_hot](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/extension_binder.py#L27) 的事务性绑定、六类 ResourceKind 的统一抽象、清单驱动的加载链路,以及 [harness_element](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/manifest/catalog.py#L67) 的声明式注册,Agent 能在会话中临时长出新的工具/MCP/skill/subagent,任务结束再卸载。

它与 auto-harness 的 [ExtendImplementStage](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/auto_harness/stages/implement.py#L646) 形成闭环:前者让 Agent 自主"生成"扩展包,后者让 Agent 自主"加载"扩展包,二者共同支撑"能自我进化的编码 Agent"这一目标。

从工程视角看,热加载的价值有三:一是按需供给能力,降低常驻工具集与 token 消耗;二是让 Agent 具备"遇到新任务自我武装"的自进化潜力;三是通过事务性回滚与账本卸载,保证能力增减是可逆、可审计的,不会让 DeepAgent 陷入不一致状态。这是 agent-core 区别于"工具集在启动时焊死"的同类产品的关键差异化能力。

从生态视角看,清单驱动 + 声明式注册让第三方可以按统一规范编写插件包(声明 tool/mcp/rail/prompt/skill/subagent),无需侵入 agent-core 主代码即可扩展能力。[list_elements](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/manifest/catalog.py#L55) 提供的内省入口还能让工具自动发现可用元素及其 schema,为未来的可视化配置编辑器与插件市场铺路。这种"插件即清单"的设计,使 agent-core 的能力边界可由生态无限扩展,而非受限于核心包内置。
