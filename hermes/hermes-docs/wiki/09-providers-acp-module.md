# providers + acp_adapter 模块

> 交叉引用: [01-项目概述](01-project-overview.md) | [02-整体架构](02-overall-architecture.md) | [03-agent模块](03-agent-module.md) | [07-plugins模块](07-plugins-module.md)

## 一、模块概述

### providers/

`providers/` 是推理后端基座，定义 `ProviderProfile` ABC 与发现注册机制。Profile 是**声明式**的：它描述 provider 的身份、端点、认证、视觉、模型目录、怪癖，但不拥有 client 构造、凭证轮转或流式——那些仍在 AIAgent 上。传输层读取 profile 而非接收 20+ 布尔标志位。

Profile 本身以插件形式存在于 `plugins/model-providers/<name>/`（bundled）与 `$HERMES_HOME/plugins/model-providers/<name>/`（user 覆盖）。`providers/__init__.py` 在首次 `get_provider_profile()`/`list_providers()` 时惰性扫描两处并 import 每个插件，插件在模块级调用 `register_provider(profile)` 自注册；后注册者同名覆盖前者，所以第三方可在不修改 repo 的前提下替换任意内置 profile。

### acp_adapter/

`acp_adapter/` 把 Hermes Agent 暴露为符合 Agent Client Protocol (ACP) 的 agent 服务器，供 VS Code/Zed/JetBrains 等编辑器集成。`server.py` 实现 `acp.Agent` 子类 `HermesACPAgent`，覆盖 `on_connect`/session 生命周期/prompt 处理/permission/tool 事件/slash 命令。`auth.py` 检测当前运行时 provider 并向 ACP 注册表声明认证方法。`permissions.py` 把 Hermes 危险命令审批桥接到 ACP `request_permission`。

## 二、关键类与函数

### providers/

| 名称 | 类型 | 文件位置 | 说明 |
|------|------|----------|------|
| ProviderProfile | dataclass | [base.py](file:///D:\yaodh\main\hermes-agent\providers\base.py#L39) | provider profile 基类：身份/端点/认证/视觉/模型目录/怪癖/钩子 |
| OMIT_TEMPERATURE | sentinel | [base.py](file:///D:\yaodh\main\hermes-agent\providers\base.py#L21) | "完全省略 temperature"哨兵（Kimi：服务端管理） |
| resolve_aux_model | 方法 | [base.py](file:///D:\yaodh\main\hermes-agent\providers\base.py#L104) | 返回活动廉价模型 id 或 ""，永不抛 |
| prepare_messages | 方法 | [base.py](file:///D:\yaodh\main\hermes-agent\providers\base.py#L133) | provider 专有消息预处理 |
| build_extra_body | 方法 | [base.py](file:///D:\yaodh\main\hermes-agent\providers\base.py#L141) | provider 专有 extra_body 字段 |
| build_api_kwargs_extras | 方法 | [base.py](file:///D:\yaodh\main\hermes-agent\providers\base.py#L150) | 返回 (extra_body_additions, top_level_kwargs) |
| fetch_models | 方法 | [base.py](file:///D:\yaodh\main\hermes-agent\providers\base.py#L197) | 实时模型列表抓取 |
| register_provider | 函数 | [\_\_init\_\_.py](file:///D:\yaodh\main\hermes-agent\providers\__init__.py#L54) | 按 name + aliases 注册；后注册者同名覆盖 |
| get_provider_profile | 函数 | [\_\_init\_\_.py](file:///D:\yaodh\main\hermes-agent\providers\__init__.py#L68) | 按 name 或 alias 查找；未发现时触发发现 |
| list_providers | 函数 | [\_\_init\_\_.py](file:///D:\yaodh\main\hermes-agent\providers\__init__.py#L79) | 返回所有已注册 profile（按 canonical name 去重） |
| _discover_providers | 函数 | [\_\_init\_\_.py](file:///D:\yaodh\main\hermes-agent\providers\__init__.py#L147) | 三步惰性发现：bundled → user → legacy |
| NousProfile | 类 | [nous/\_\_init\_\_.py](file:///D:\yaodh\main\hermes-agent\plugins\model-providers\nous\__init__.py#L11) | Nous Portal profile：产品标签、session_id 黏滞路由 |

### acp_adapter/

| 名称 | 类型 | 文件位置 | 说明 |
|------|------|----------|------|
| HermesACPAgent | 类 | [server.py](file:///D:\yaodh\main\hermes-agent\acp_adapter\server.py#L566) | `acp.Agent` 子类，含 slash 命令表、edit-approval 策略映射 |
| on_connect | 方法 | [server.py](file:///D:\yaodh\main\hermes-agent\acp_adapter\server.py#L644) | 存储 client 连接用于发送 session 更新 |
| main | 函数 | [entry.py](file:///D:\yaodh\main\hermes-agent\acp_adapter\entry.py#L220) | 入口：解析参数、setup/check 子命令、`acp.run_agent` |
| _BenignProbeMethodFilter | Filter | [entry.py](file:///D:\yaodh\main\hermes-agent\acp_adapter\entry.py#L52) | 抑制 ping/health 探针的 -32601 噪声 |
| detect_provider | 函数 | [auth.py](file:///D:\yaodh\main\hermes-agent\acp_adapter\auth.py#L11) | 解析当前运行时 provider |
| build_auth_methods | 函数 | [auth.py](file:///D:\yaodh\main\hermes-agent\acp_adapter\auth.py#L41) | ACP 认证方法列表；始终加 terminal-setup 兜底 |
| make_approval_callback | 函数 | [permissions.py](file:///D:\yaodh\main\hermes-agent\acp_adapter\permissions.py#L110) | 审批桥接到 ACP `request_permission`；超时返回 timeout |
| _build_permission_options | 函数 | [permissions.py](file:///D:\yaodh\main\hermes-agent\acp_adapter\permissions.py#L41) | 构造 ACP 选项：allow_once/session/always/deny |
| _map_outcome_to_hermes | 函数 | [permissions.py](file:///D:\yaodh\main\hermes-agent\acp_adapter\permissions.py#L98) | 把 ACP AllowedOutcome 映射回 Hermes 审批字符串 |
| SessionState | dataclass | [session.py](file:///D:\yaodh\main\hermes-agent\acp_adapter\session.py#L159) | 每 session 状态：agent/cwd/model/history/cancel_event |
| SessionManager | 类 | [session.py](file:///D:\yaodh\main\hermes-agent\acp_adapter\session.py#L175) | 线程安全会话管理；内存 + 共享 SessionDB 持久化 |
| create_session | 方法 | [session.py](file:///D:\yaodh\main\hermes-agent\acp_adapter\session.py#L199) | 创建新会话：uuid4 id + 新 AIAgent + 持久化 |

## 三、实现机制

### 3.1 声明式 Profile + 钩子覆盖

`ProviderProfile` 是 dataclass，默认行为在基类，复杂 provider 在子类覆盖钩子（`prepare_messages`/`build_extra_body`/`build_api_kwargs_extras`/`fetch_models`），传输层 `chat_completions.py::_build_kwargs_from_profile()` 每次调用都读 profile 而非接 20 个布尔位。

### 3.2 自注册 + 后者覆盖

插件在模块级调用 `register_provider(profile)`，`_REGISTRY[name] = profile` + 别名表；`_PROVIDER_LIST_CACHE = None` 失效缓存。`_discover_providers` 按 bundled → user → legacy 顺序，后写者赢：

```python
def _discover_providers() -> None:
    global _discovered
    if _discovered:
        return
    _discovered = True
    # 1. Bundled plugins
    if _BUNDLED_PLUGINS_DIR.is_dir():
        for child in sorted(_BUNDLED_PLUGINS_DIR.iterdir()):
            if not child.is_dir() or child.name.startswith(("_", ".")):
                continue
            _import_plugin_dir(child, "bundled")
    # 2. User plugins → 3. Legacy per-file modules
```

### 3.3 Adapter 模式（Hermes AIAgent ↔ ACP Agent）

`HermesACPAgent(acp.Agent)` 把 Hermes 的 AIAgent 适配为 ACP 协议；session 状态由 `SessionManager` 管理，事件通过 `make_message_cb`/`make_step_cb`/`make_thinking_cb` 等回调桥接到 ACP chunk 流。

### 3.4 桥接模式（Hermes 审批 ↔ ACP permission）

`make_approval_callback` 把 Hermes 的 `prompt_dangerous_approval` 协议桥接到 ACP 的 `request_permission` 协程；用 `safe_schedule_threadsafe` 把协程从工作线程投到 ACP 事件循环，超时返回 `timeout`（区别于显式 deny）：

```python
future = safe_schedule_threadsafe(coro, loop, ...)
if future is None:
    return "deny"
try:
    response = future.result(timeout=timeout)
except FutureTimeout:
    future.cancel()
    return "timeout"  # Distinct from an explicit deny
```

## 四、调用示例

```python
from providers import get_provider_profile, list_providers

# 列出所有已注册 provider
for profile in list_providers():
    print(f"{profile.name}: {profile.base_url}")

# 按 name 获取 profile
nous = get_provider_profile("nous")
print(nous.base_url)  # Nous Portal endpoint

# 运行 ACP 服务器（供编辑器集成）
# 命令行: hermes acp --setup
```

## 五、小结

1. `ProviderProfile` 是声明式 dataclass，描述身份/端点/认证/怪癖，不拥有 client 构造
2. 三步惰性发现（bundled→user→legacy），后写者赢，第三方可替换任意内置 profile
3. `acp_adapter` 用 Adapter 模式把 Hermes AIAgent 适配为 ACP 协议服务器
4. 审批桥接用 `safe_schedule_threadsafe` 从工作线程投到 ACP 事件循环，超时返回 `timeout`
5. `build_auth_methods` 始终声明 terminal-setup 兜底，满足 ACP 注册表握手要求
