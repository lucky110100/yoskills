# plugins 模块

> 交叉引用: [01-项目概述](01-project-overview.md) | [02-整体架构](02-overall-architecture.md) | [03-agent模块](03-agent-module.md) | [09-providers-acp模块](09-providers-acp-module.md)

## 一、模块概述

`plugins/` 既是被发现的插件目录（bundled `plugins/<name>/` 与 user `~/.hermes/plugins/<name>/`），又包含 `plugin_utils.py` 这一并发原语工具箱。它覆盖内存 provider（honcho/mem0/supermemory/holographic 等）、推理后端 provider（model-providers/）、平台适配（telegram/discord/slack/feishu 等）、浏览器/图像/视频生成、看板、成就、安全指引、仪表盘认证等大类。每个目录型插件须含 `plugin.yaml` 清单与 `__init__.py` 的 `register(ctx)` 函数。

`plugin_utils.py` 集中解决"懒单例 + 多线程首调竞态"这一最常见的插件脚枪：双线程同时通过 `is not None` 守卫，重复初始化后第二次写入覆盖第一次，泄露连接/线程/句柄。它给出两个线程安全原语——零参 `lazy_singleton` 装饰器与按 key 缓存的 `SingletonSlot`——均只依赖 stdlib `threading`，避免把重量级宿主模块拖进插件 import 路径。

## 二、关键类与函数

| 名称 | 类型 | 文件位置 | 说明 |
|------|------|----------|------|
| lazy_singleton | 装饰器 | [plugin_utils.py](file:///D:\yaodh\main\hermes-agent\plugins\plugin_utils.py#L43) | 把零参工厂包成线程安全懒单例；附 `.reset()` 用于测试 |
| SingletonSlot | 泛型类 | [plugin_utils.py](file:///D:\yaodh\main\hermes-agent\plugins\plugin_utils.py#L84) | 按 key 缓存的懒槽，"首个配置赢"语义 |
| discover_memory_providers | 函数 | [memory/\_\_init\_\_.py](file:///D:\yaodh\main\hermes-agent\plugins\memory\__init__.py#L157) | 扫描 bundled + user 目录，返回 (name, desc, is_available) |
| load_memory_provider | 函数 | [memory/\_\_init\_\_.py](file:///D:\yaodh\main\hermes-agent\plugins\memory\__init__.py#L194) | 按 name 加载 MemoryProvider 实例 |
| _load_provider_from_dir | 函数 | [memory/\_\_init\_\_.py](file:///D:\yaodh\main\hermes-agent\plugins\memory\__init__.py#L219) | 优先 `register(ctx)` 模式，回退到查找 MemoryProvider 子类 |
| _ProviderCollector | 类 | [memory/\_\_init\_\_.py](file:///D:\yaodh\main\hermes-agent\plugins\memory\__init__.py#L330) | 模拟 plugin ctx，仅捕获 `register_memory_provider` 调用 |
| HonchoMemoryProvider | 类 | [honcho/\_\_init\_\_.py](file:///D:\yaodh\main\hermes-agent\plugins\memory\honcho\__init__.py#L237) | Honcho AI 原生内存 provider |
| register | 函数 | [honcho/\_\_init\_\_.py](file:///D:\yaodh\main\hermes-agent\plugins\memory\honcho\__init__.py#L1625) | Honcho 插件入口：`ctx.register_memory_provider(...)` |
| NousProfile | 类 | [nous/\_\_init\_\_.py](file:///D:\yaodh\main\hermes-agent\plugins\model-providers\nous\__init__.py#L11) | Nous Portal provider profile |
| PluginManager | 类 | [plugins.py](file:///D:\yaodh\main\hermes-agent\hermes_cli\plugins.py#L3049) | 插件管理器，含发现锁、钩子表、事件总线、归属台账 |
| invoke_hook | 函数 | [plugins.py](file:///D:\yaodh\main\hermes-agent\hermes_cli\plugins.py#L5326) | 触发生命周期钩子；首次调用前确保插件已发现 |
| discover_plugins | 函数 | [plugins.py](file:///D:\yaodh\main\hermes-agent\hermes_cli\plugins.py#L5151) | 四源发现：bundled/user/project/pip entry-point |

## 三、实现机制

### 3.1 四源发现 + 后者覆盖

bundled → user → project → pip entry-point，名称冲突时后源覆盖前源，所以用户/项目插件可替换任何内置同名插件。这是 Hermes "Extend, don't duplicate" 哲学的核心：用户无需 fork 仓库即可替换任意内置实现。

### 3.2 线程安全懒单例原语

`lazy_singleton` 用"box list + Lock"实现双检锁，fast path 在 GIL 下原子可读：

```python
def lazy_singleton(factory: Callable[[], T]) -> Callable[[], T]:
    lock = threading.Lock()
    box: list = []  # one-element [instance]; empty == not yet built

    @functools.wraps(factory)
    def accessor() -> T:
        if box:
            return box[0]
        with lock:
            if box:  # re-check inside the lock
                return box[0]
            instance = factory()
            box.append(instance)
            return instance

    def reset() -> None:
        with lock:
            box.clear()

    accessor.reset = reset
    return accessor
```

### 3.3 Plugin Context 协议 + 多回调注册

插件 `register(ctx)` 接受一个 ctx 对象，ctx 暴露 `register_memory_provider`/`register_tool`/`register_hook`/`register_cli_command` 等多方法；`_ProviderCollector` 是该协议的最小测试替身，仅捕获 memory provider 调用，其余 no-op。

### 3.4 Bundled/User 双层路径与合成包壳

bundled 插件以 `plugins.memory.<name>` 稳定导入，user 插件以 `_hermes_user_memory.<name>` 命名空间导入并注册合成父包壳，避免 `sys.modules` 冲突与相对导入失败。

## 四、调用示例

```python
from plugins.plugin_utils import lazy_singleton

# 用 lazy_singleton 创建线程安全的单例
get_client = lazy_singleton(lambda: ExpensiveClient())

# 首次调用时初始化，后续调用返回同一实例
client1 = get_client()
client2 = get_client()
assert client1 is client2

# 测试/拆卸时重置
get_client.reset()

from plugins.memory import discover_memory_providers
# 列出所有可用的内存 provider
providers = discover_memory_providers()
for name, desc, available in providers:
    print(f"{name}: {desc} ({'✓' if available else '✗'})")
```

## 五、小结

1. 四源发现（bundled→user→project→pip）+ 后者覆盖，用户可替换任意内置插件
2. `plugin_utils.py` 提供 `lazy_singleton`/`SingletonSlot` 线程安全原语，解决 TOCTOU 单例竞态
3. Plugin Context 协议统一了 memory/tool/hook/cli_command 四类注册
4. Bundled/User 双层路径 + 合成包壳避免 sys.modules 冲突
5. `PluginManager` 管理发现锁、钩子表、事件总线与归属台账
