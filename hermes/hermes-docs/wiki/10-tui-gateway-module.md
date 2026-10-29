# tui_gateway 模块

> 交叉引用: [01-项目概述](01-project-overview.md) | [02-整体架构](02-overall-architecture.md) | [11-ui-tui 模块](11-ui-tui-module.md) | [13-desktop 模块](13-desktop-module.md) | [14-依赖关系](14-dependencies.md)

## 一、模块概述

`tui_gateway` 是 Hermes Agent 的 TUI 后端进程。它把 Hermes 的核心能力（会话、工具、模型调用、流式事件）通过 **JSON-RPC 2.0** 协议暴露给前端的 React/Ink TUI 客户端，同时支持两种传输通道：

- **stdio 传输**：`hermes --tui` 直接以子进程方式启动 gateway，客户端通过子进程的 stdin/stdout 收发 JSON 帧；
- **WebSocket 传输**：作为常驻 sidecar 监听端口，供 attach 模式（多窗口、外部接入）连接。

整个模块的核心实现集中在 [server.py](file:///D:/yaodh/main/hermes-agent/tui_gateway/server.py)（约 19K 行），它既是 RPC 路由器，也是事件分发器。`transport.py` 定义了最小化的 `Transport` 抽象，并通过 `ContextVar` 把"I/O sink"与"业务 handler"彻底解耦——handler 只需调用 `current_transport().write(...)`，而无需关心当前帧究竟要写到 stdout 还是某个 WebSocket 连接。

这一设计让 gateway 可以同时服务于"单进程内嵌 + stdio"和"sidecar + 多 WS 会话"两种部署形态，而业务逻辑保持单一实现。下游的 Ink TUI、Web 仪表盘、Electron 桌面三个表面，都是这一后端的客户端。

## 二、关键类与函数

### server.py 核心路由与运行时

| 名称 | 职责 | 位置 |
| --- | --- | --- |
| [dispatch](file:///D:/yaodh/main/hermes-agent/tui_gateway/server.py#L1972) | 入站 RPC 路由总入口；长 handler 投递线程池异步执行，短 handler 内联同步返回 | [server.py:L1972](file:///D:/yaodh/main/hermes-agent/tui_gateway/server.py#L1972) |
| [handle_request](file:///D:/yaodh/main/hermes-agent/tui_gateway/server.py#L1935) | 按 `_methods` 注册表分发请求到具体 handler，返回 JSON-RPC 响应 | [server.py:L1935](file:///D:/yaodh/main/hermes-agent/tui_gateway/server.py#L1935) |
| [method 装饰器](file:///D:/yaodh/main/hermes-agent/tui_gateway/server.py#L1908) | 注册 handler 到 `_methods` 字典，建立 method 名到函数的映射 | [server.py:L1908](file:///D:/yaodh/main/hermes-agent/tui_gateway/server.py#L1908) |
| [_normalize_request](file:///D:/yaodh/main/hermes-agent/tui_gateway/server.py#L1916) | 校验入站请求是否为合法 JSON-RPC 对象，提取 id/method/params 三元组 | [server.py:L1916](file:///D:/yaodh/main/hermes-agent/tui_gateway/server.py#L1916) |
| [_SlashWorker](file:///D:/yaodh/main/hermes-agent/tui_gateway/server.py#L342) | 持久 HermesCLI 子进程，专跑 slash 命令，避免每次重新启动 agent | [server.py:L342](file:///D:/yaodh/main/hermes-agent/tui_gateway/server.py#L342) |
| [_panic_hook](file:///D:/yaodh/main/hermes-agent/tui_gateway/server.py#L74) | 崩溃钩子，把未捕获异常落盘成崩溃日志，便于事后诊断 | [server.py:L74](file:///D:/yaodh/main/hermes-agent/tui_gateway/server.py#L74) |
| [resolve_skin](file:///D:/yaodh/main/hermes-agent/tui_gateway/server.py#L3341) | 皮肤解析，把主题/外观配置映射成 TUI 可渲染的皮肤对象 | [server.py:L3341](file:///D:/yaodh/main/hermes-agent/tui_gateway/server.py#L3341) |

### 传输层与注册机制

| 名称 | 职责 | 位置 |
| --- | --- | --- |
| [Transport](file:///D:/yaodh/main/hermes-agent/tui_gateway/transport.py#L66) | 传输最小接口（`Protocol`），仅 `write`/`close` 两个方法 | [transport.py:L66](file:///D:/yaodh/main/hermes-agent/tui_gateway/transport.py#L66) |
| [StdioTransport](file:///D:/yaodh/main/hermes-agent/tui_gateway/transport.py#L100) | 写 JSON 帧到流（通常 `sys.stdout`），callable 取流以兼容 monkey-patch | [transport.py:L100](file:///D:/yaodh/main/hermes-agent/tui_gateway/transport.py#L100) |
| [WSTransport](file:///D:/yaodh/main/hermes-agent/tui_gateway/ws.py#L70) | WebSocket 连接传输；用 `run_coroutine_threadsafe` 把跨线程写编组回事件循环 | [ws.py:L70](file:///D:/yaodh/main/hermes-agent/tui_gateway/ws.py#L70) |
| [HandlerRegistry](file:///D:/yaodh/main/hermes-agent/tui_gateway/method_ctx.py#L21) | 延迟注册器，允许模块按需挂载 handler 而非 import 时即注册 | [method_ctx.py:L21](file:///D:/yaodh/main/hermes-agent/tui_gateway/method_ctx.py#L21) |
| [main](file:///D:/yaodh/main/hermes-agent/tui_gateway/entry.py#L421) | stdio 入口；读取一行一个 JSON 请求，调用 `dispatch` 并写出响应 | [entry.py:L421](file:///D:/yaodh/main/hermes-agent/tui_gateway/entry.py#L421) |

## 三、实现机制

### 设计模式一：Transport 抽象 + ContextVar 绑定

传输层只定义一个 `@runtime_checkable` 的 `Protocol`，包含 `write(obj) -> bool` 与 `close()`。所有 handler 都不直接持有传输对象，而是通过模块级 `ContextVar` 间接寻址：

```python
_current_transport: contextvars.ContextVar[Optional[Transport]] = (
    contextvars.ContextVar("hermes_gateway_transport", default=None)
)

def current_transport() -> Optional[Transport]:
    return _current_transport.get()

def bind_transport(transport):
    return _current_transport.set(transport)
```

`dispatch` 在处理每个请求时，先 `bind_transport(t)` 把当前传输钉在上下文里，handler 内部及其派生的事件全部经由 `current_transport()` 写出。这意味着同一个 handler 代码，在 stdio 模式下写到 stdout，在 WS 模式下写到对应连接，**无需任何分支判断**。`bind_transport` 返回 token，处理完毕后 `reset_transport` 还原，保证线程池里并发请求之间互不串扰。ContextVar 的上下文隔离特性，天然适合"每请求一个独立绑定"的语义。

### 设计模式二：长/短 handler 分流 + 线程池

`dispatch` 的核心策略是区分 handler 的耗时特征：

- 短 handler（如读取配置、查询会话列表）走 `_methods` 注册表内联执行，`dispatch` 直接返回响应字典；
- 长 handler（如启动 agent、跑工具）注册在 `_LONG_HANDLERS`，被投递到线程池异步执行，`dispatch` 返回 `None` 表示"已调度，响应将由 worker 自己经绑定的传输写出"。

```python
def dispatch(req: dict, transport: Optional[Transport] = None) -> dict | None:
    t = transport or _stdio_transport
    token = bind_transport(t)
    try:
        normalized = _normalize_request(req)
        if isinstance(normalized, dict):
            return normalized
        _rid, method, _params = normalized
        if method not in _LONG_HANDLERS:
            return handle_request(req)
        # ...投递线程池...
    finally:
        reset_transport(token)
```

这种分流让"快请求"低延迟（无线程池排队），"慢请求"不阻塞主循环。worker 完成后通过 `current_transport()` 回写结果与流式事件。由于绑定是在 `dispatch` 入口完成的，而 ContextVar 在线程间是隔离传播的，长 handler 在线程池里执行时仍能拿到正确的传输引用。

### 设计模式三：stdout 专用 + print 重定向

gateway 与 TUI 客户端之间用 stdout 传输 JSON-RPC 帧，因此 stdout 必须保持"纯净"——任何非 JSON 的 print 输出都会破坏帧边界。模块用 `_real_stdout` 持有真实流，并重定向全局 `print` 到 stderr/日志 sink，确保业务代码里残留的 `print` 不会污染协议通道。`StdioTransport` 通过 callable 取流（而非直接持有 `sys.stdout`），正是为了兼容测试里的 `monkeypatch.setattr(server, "_real_stdout", ...)`——运行时替换流对象后，传输仍能取到最新的引用。

### 设计模式四：methods_* 拆分 + __globals__ 重绑

19K 行的 `server.py` 并非单一巨文件写死，而是把不同功能域的 handler 拆到 `methods_*` 子模块。注册时通过 `__globals__` 重绑定，让子模块里用到的工具函数（如 `current_transport`、`_ok`、`_err`）指向 server 命名空间，从而既保持物理拆分又共享同一运行时上下文。`HandlerRegistry` 进一步提供延迟注册能力，使按需挂载成为可能——某些 handler 只在特定 profile 或启用某插件时才注册，避免冷启动时全量加载。

### 数据流时序

一次典型的 stdio 长请求时序如下：

1. `entry.main` 从 stdin 读入一行 JSON，`json.loads` 解析为 dict；
2. 调用 `dispatch(req)`，内部 `bind_transport(_stdio_transport)` 钉定传输；
3. `_normalize_request` 校验后取出 `(rid, method, params)`；
4. method 命中 `_LONG_HANDLERS`，投递线程池，`dispatch` 返回 `None`；
5. worker 在线程池里执行 handler，期间通过 `current_transport().write(...)` 推送流式事件帧；
6. handler 结束，worker 写出最终响应帧；`reset_transport` 还原上下文。

WS 模式与之同构，区别仅在第 1、5、6 步的 I/O sink 换成 `WSTransport`，且跨线程写经 `run_coroutine_threadsafe` 编组回 asyncio 事件循环。

### 进程模型与通信

- **stdio 模式**：`entry.main` 是入口，逐行读 stdin → `dispatch` → 写 stdout。TUI 客户端以子进程 spawn gateway。
- **WS 模式**：`ws.py` 启动 asyncio 事件循环监听端口，每个连接创建一个 `WSTransport`。跨线程写（业务在线程池、传输在事件循环）用 `asyncio.run_coroutine_threadsafe` 编组。
- **_SlashWorker**：持久化的 `HermesCLI` 子进程，通过队列与 stdout_tail 与主进程通信，专门承载 slash 命令的执行，免去每次冷启动 agent 的开销。它以 `sys.executable -m tui_gateway.slash_worker` 启动，按 session_key 复用。

## 四、调用示例/代码片段

### 注册一个 RPC 方法

```python
from tui_gateway.server import method, _ok, current_transport

@method("session/list")
def list_sessions(req):
    rid = req.get("id")
    sessions = load_sessions()
    return _ok(rid, {"sessions": sessions})
```

`method` 装饰器把函数塞进 `_methods["session/list"]`，`handle_request` 在分发时按 method 名取出来调用。

### 经上下文传输回写事件

```python
def emit_event(event: dict):
    t = current_transport()
    if t is not None:
        t.write({"jsonrpc": "2.0", "method": "event", "params": event})
```

handler 无需知道自己是 stdio 还是 WS，`current_transport()` 已被 `dispatch` 钉好。

### WS 会话绑定传输

```python
async def handle_ws(ws):
    transport = WSTransport(ws)
    try:
        async for raw in ws:
            req = json.loads(raw)
            resp = dispatch(req, transport=transport)  # 钉到本连接
            if resp is not None:
                await ws.send(json.dumps(resp))
    finally:
        transport.close()
```

传入 `transport=` 后，handler 写出的所有事件帧都会落到这条 WS 连接，而非默认的 stdio。

### stdio 入口主循环（简化）

```python
def main():
    install_panic_hook()          # _panic_hook 落盘崩溃日志
    for line in sys.stdin:        # 一行一个 JSON 请求
        try:
            req = json.loads(line)
        except JSONDecodeError:
            continue
        resp = dispatch(req)      # 内联或投递线程池
        if resp is not None:
            _stdio_transport.write(resp)
```

## 五、小结

`tui_gateway` 是 Hermes 面向所有交互表面（TUI、Web 仪表盘、桌面）的统一 RPC 后端。它的精髓在于用 **Transport 抽象 + ContextVar 绑定** 把"I/O 去向"从业务逻辑里彻底剥离，再以 **长/短 handler 分流** 平衡延迟与吞吐。stdout 纯净化与 callable 取流保证了协议帧边界不被破坏，而 `methods_*` 拆分 + `__globals__` 重绑则让 19K 行的实现既模块化又共享运行时。`_SlashWorker` 的持久子进程设计进一步把 slash 命令的冷启动成本摊薄到一次。这套机制是后续 [11-ui-tui 模块](11-ui-tui-module.md)（Ink 前端）与 [13-desktop 模块](13-desktop-module.md)（Electron）能复用同一后端的根本原因——前端只管"连哪个传输"，后端的 handler 与事件回写逻辑完全不变。

## 六、附录：方法速查与错误码

### 常见 RPC 方法清单

| method | 类型 | 说明 |
| --- | --- | --- |
| `session/list` | 短 | 列出本地会话 |
| `session/create` | 短 | 新建会话并返回 sid |
| `agent/start` | 长 | 启动 agent 主循环（投线程池） |
| `agent/cancel` | 短 | 取消当前运行 |
| `event/subscribe` | 长 | 订阅流式事件（长连） |
| `config/get` | 短 | 读取当前 profile 配置 |
| `skin/resolve` | 短 | 解析皮肤供 TUI 渲染 |

> 短方法经 `handle_request` 内联返回；长方法进 `_LONG_HANDLERS`，由 worker 异步回写。

### JSON-RPC 错误码约定

| code | 含义 | 触发场景 |
| --- | --- | --- |
| -32700 | 解析错误 | 请求不是合法 JSON |
| -32600 | 无效请求 | 缺少 method 或 method 非字符串 |
| -32601 | 方法未找到 | method 未在 `_methods` 注册 |
| -32603 | 内部错误 | handler 抛出未捕获异常 |
| -32000 | 传输错误 | 对端已断开，`write` 返回 False |

`_normalize_request` 在第一时间拦截 -32700/-32600，`dispatch` 用 `try/finally` 保证 `reset_transport` 一定执行，避免一次失败的请求污染后续请求的上下文绑定。
