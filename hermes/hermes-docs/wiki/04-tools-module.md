# tools 模块

> 交叉引用: [01-项目概述](01-project-overview.md) | [02-整体架构](02-overall-architecture.md) | [03-agent 模块](03-agent-module.md) | [05-gateway 模块](05-gateway-module.md)

## 一、模块概述

tools/ 是 Hermes Agent 的工具实现目录，采用自注册式架构。每个工具文件在顶层 import 时以副作用调用 `registry.register()`，由 [registry.py](file:///D:\yaodh\main\hermes-agent\tools\registry.py#L426) 统一收口。新增工具只需把 `.py` 文件落盘到 `tools/`，无需修改注册中心——AST 自发现会在启动时扫描目录，自动识别并加载含 `register` 调用的文件。

模块内置多层防御以应对"LLM 生成的工具参数不可信"这一现实：check_fn 的 TTL 缓存（30s TTL + 60s grace）抑制可用性抖动、tool_error / tool_result 统一 JSON 序列化器保证 handler 返回值规整、path_security / url_safety / threat_patterns 三重校验拦住路径穿越与恶意 URL、lazy_deps 按需安装避免冷启动拉满依赖。

工具调度分两层：`tools/registry.py` 负责"注册与发现"，`agent/model_tools.py` 负责"调度与过滤"。model_tools 的 handle_function_call 是主调度器，get_tool_definitions 在返回 schema 前做工具集过滤与动态 schema 重写，coerce_tool_args 在执行前按 JSON Schema 强转 LLM 给出的弱类型参数。

## 二、关键类与函数

| 类/函数 | 文件位置 | 说明 |
|---|---|---|
| [ToolRegistry](file:///D:\yaodh\main\hermes-agent\tools\registry.py#L426) | tools/registry.py | 单例注册表类 |
| [registry](file:///D:\yaodh\main\hermes-agent\tools\registry.py#L1263) | tools/registry.py | 模块级单例实例 |
| [ToolRegistry.register](file:///D:\yaodh\main\hermes-agent\tools\registry.py#L737) | tools/registry.py | 工具注册入口 |
| [ToolRegistry.dispatch](file:///D:\yaodh\main\hermes-agent\tools\registry.py#L1102) | tools/registry.py | 按名执行 handler |
| [ToolRegistry.get_definitions](file:///D:\yaodh\main\hermes-agent\tools\registry.py#L1018) | tools/registry.py | 返回 OpenAI 格式 schema |
| [discover_builtin_tools](file:///D:\yaodh\main\hermes-agent\tools\registry.py#L111) | tools/registry.py | AST 扫描自发现 |
| [_check_fn_cached](file:///D:\yaodh\main\hermes-agent\tools\registry.py#L324) | tools/registry.py | check_fn 的 TTL(30s)+grace(60s) 缓存 |
| [tool_error/tool_result](file:///D:\yaodh\main\hermes-agent\tools\registry.py#L1282) | tools/registry.py | 统一 JSON 序列化器 |
| [handle_function_call](file:///D:\yaodh\main\hermes-agent\agent\model_tools.py#L1170) | agent/model_tools.py | 主调度器 |
| [get_tool_definitions](file:///D:\yaodh\main\hermes-agent\agent\model_tools.py#L307) | agent/model_tools.py | 工具集过滤 + 动态 schema 重写 |
| [coerce_tool_args](file:///D:\yaodh\main\hermes-agent\agent\model_tools.py#L777) | agent/model_tools.py | JSON Schema 类型强转 |
| [_HERMES_CORE_TOOLS](file:///D:\yaodh\main\hermes-agent\agent\toolsets.py#L31) | agent/toolsets.py | 核心工具清单 |
| [resolve_toolset](file:///D:\yaodh\main\hermes-agent\agent\toolsets.py#L756) | agent/toolsets.py | 递归解析工具集 |

## 三、实现机制

### 3.1 自注册 + 单例注册表

每个工具文件在顶层 import 时副作用调用 registry.register()，registry 是模块级单例。这意味着"写文件即注册"，工具与注册中心零耦合：

```python
# tools/my_tool.py
from tools.registry import registry, tool_result

def _handler(args):
    return tool_result("done")

registry.register(
    name="my_tool",
    description="...",
    parameters={...},
    handler=_handler,
)
```

ToolRegistry.register 把一个 ToolEntry 写入内部 `_tools` 字典，按 name 索引。dispatch 时按 name 取出 handler 执行。

### 3.2 AST 自发现 + 磁盘缓存

discover_builtin_tools 用 ast.parse 扫描 tools/ 目录，判定文件是否含 register 调用，按 mtime 缓存扫描结果，避免每次启动都全量 parse。import 触发 register 副作用，ToolEntry 被写入 `_tools`：

```python
def discover_builtin_tools(directory):
    cache = _load_scan_cache()           # {path: (mtime, has_register)}
    for path in glob(directory, "*.py"):
        mtime = os.path.getmtime(path)
        if cache.get(path, (None,))[0] == mtime:
            yield cached_result
            continue
        tree = ast.parse(read(path))
        has = _contains_register_call(tree)
        cache[path] = (mtime, has)
        if has:
            importlib.import_module(module_name(path))
    _save_scan_cache(cache)
```

mtime 未变则跳过 parse，仅文件改动后才重新扫描，冷启动友好。

### 3.3 TTL + grace 可用性缓存

每个工具可声明 check_fn 判定"当前是否可用"（如依赖是否就绪）。_check_fn_cached 给它加 30s TTL + 60s grace 缓存：TTL 内直接复用结果，TTL 过期后重算，若重算失败则在 grace 窗口（60s）内沿用旧结果，把短暂抖动当噪声吞掉：

```python
def _check_fn_cached(name, now):
    entry = registry._tools[name]
    if now - entry.checked_at < TTL:          # 30s
        return entry.available
    try:
        ok = entry.check_fn()
        entry.available, entry.checked_at = ok, now
        return ok
    except Exception:
        if now - entry.checked_at < GRACE:    # 60s
            return entry.available
        raise
```

这样一次外部依赖瞬时抖动不会误判工具不可用而把它从 schema 里剔除。

### 3.4 插件 Override 守门

register 支持 override=True 覆盖同名工具，但需绑定到 handler 定义模块，防止外部插件随意替换核心工具。守门逻辑校验调用方模块与 handler 所属模块一致才放行，避免第三方把 `read_file` 整个换掉：

```python
def register(self, name, handler, *, override=False, **kw):
    if override and name in self._tools:
        existing = self._tools[name]
        if existing.owner_module != caller_module(handler):
            raise PermissionError("override requires same owner module")
    self._tools[name] = ToolEntry(name=name, handler=handler, **kw)
```

### 3.5 结果规整契约

handler 只能返回 `str` 或 `_multimodal` envelope，其余类型由 tool_result / tool_error 统一序列化为 JSON 字符串，保证 LLM 侧永远收到稳定结构。这一契约把"handler 怎么写"与"LLM 怎么读"解耦：

```python
def tool_result(content, **extra):
    return json.dumps({"status": "ok", "content": content, **extra})

def tool_error(message, **extra):
    return json.dumps({"status": "error", "error": message, **extra})
```

### 3.6 参数强转与安全纵深

LLM 给出的工具参数常是弱类型（把数字写成字符串、把布尔写成 "true"），coerce_tool_args 按 JSON Schema 在执行前强转，避免 handler 内到处写 `int(args["n"])`。安全纵深在强转之后、handler 之前：

- path_security：拦路径穿越（`..`、绝对路径、符号链接）；
- url_safety：拦内网/元数据 URL（169.254.169.254、localhost）；
- threat_patterns：拦已知恶意模式（如命令注入串）；
- lazy_deps：handler 首次用到重依赖时按需 pip install，冷启动不拉满。

### 3.7 工具集解析与 schema 重写

resolve_toolset 递归解析工具集：一个集合可引用其他集合，最终展开为工具名扁平列表。_HERMES_CORE_TOOLS 是不可裁减的核心清单（如读文件、写文件、列目录），其余工具按会话能力（capabilities）与 profile 动态裁剪。get_tool_definitions 在返回前做动态 schema 重写——例如某平台不支持 image 参数，则把该字段从 schema 中剔除，保证下发给 LLM 的 schema 与实际可执行能力一致。

### 3.8 注册链路与调度

完整链路如下：

```
启动
  └─ discover_builtin_tools          # AST 扫描 + mtime 缓存
       └─ import 工具文件             # 副作用触发 register
            └─ ToolEntry 写入 _tools
对话中
  └─ get_tool_definitions            # resolve_toolset 过滤 + check_fn 可用性
       └─ 动态 schema 重写            # 按会话能力裁剪参数
  └─ handle_function_call             # 主调度器
       ├─ coerce_tool_args            # JSON Schema 强转弱类型参数
       ├─ registry.dispatch           # 按名执行 handler
       ├─ path_security / url_safety   # 安全校验
       └─ tool_result / tool_error    # 结果规整
```

## 四、调用示例

### 4.1 注册一个新工具

```python
# tools/fetch_url.py
from tools.registry import registry, tool_result, tool_error
from tools.security import url_safety

def _fetch(args):
    url = args["url"]
    if not url_safety(url):
        return tool_error("blocked: unsafe url")
    return tool_result(_http_get(url))

registry.register(
    name="fetch_url",
    description="Fetch raw content from a URL.",
    parameters={
        "type": "object",
        "properties": {"url": {"type": "string"}},
        "required": ["url"],
    },
    handler=_fetch,
    check_fn=lambda: _deps_ready(),
)
```

落盘到 `tools/fetch_url.py` 即生效，无需改注册中心。

### 4.2 调度执行

```python
from agent.model_tools import handle_function_call

out = await handle_function_call(
    name="fetch_url",
    arguments='{"url": "https://example.com"}',
    ctx=turn_ctx,
)
# out 已是规整后的 JSON 字符串
```

### 4.3 查询可用工具 schema

```python
from agent.model_tools import get_tool_definitions

defs = get_tool_definitions(
    toolset="core+web",
    capabilities=ctx.capabilities,
)
# 返回 OpenAI function-calling 格式 schema，已按能力裁剪
```

### 4.4 自定义工具集

```python
from agent.toolsets import resolve_toolset

names = resolve_toolset("core+web+shell")
# ["read_file", "write_file", "list_dir", "fetch_url", "run_shell", ...]
```

## 五、小结

1. tools/ 采用自注册式架构：工具文件顶层副作用调用 registry.register()，新增工具只需落盘 `.py`，AST 自发现自动纳入，与注册中心零耦合。
2. AST 自发现 + mtime 磁盘缓存，避免每次启动全量 parse，冷启动友好。
3. check_fn 的 30s TTL + 60s grace 缓存把依赖可用性抖动当噪声吞掉，避免误判工具不可用而误删 schema。
4. 结果规整契约：handler 只能返回 str 或 _multimodal envelope，由 tool_result/tool_error 统一序列化，LLM 侧永远收到稳定结构。
5. 安全纵深：coerce_tool_args 强转弱类型、path_security/url_safety/threat_patterns 三重校验、override 守门绑定 handler 所属模块，共同抵御 LLM 不可信参数。
