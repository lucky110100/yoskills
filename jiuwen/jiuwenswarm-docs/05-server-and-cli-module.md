# 05 server 与 cli 模块(AgentServer 运行时与命令行客户端)

> 交叉引用: [01-项目概述](../01-project-overview.md) | [02-整体架构](../02-overall-architecture.md) | [03-agents与swarm](../03-agents-and-swarm-module.md) | [08-common与e2a](../08-common-e2a-and-security-module.md)

## 一、能力概述

`server` 子系统是 JiuwenSwarm 的 AgentServer 运行时,定位为整个系统的"流式中枢"。它承接来自 Gateway(以及直连的 CLI)的 WebSocket 长连接,负责 Agent 的完整生命周期管理:从预热池的就绪态借出、并发信号量限流、会话级任务队列排队,到把 E2A(E2A = End-to-Agent)请求解析为 `AgentRequest` 后分派给 DeepAgent,再把 Agent 产出的 chunk 逐条编码为 E2A wire 流式回推给客户端。除此之外,server 还承载了 A2UI v0.8 富前端协议、用户 hooks 执行器(覆盖 17 类事件)、jiuwenbox 沙盒子进程、会话历史与 turn-based diff 服务等多条副链路,是一个职责密集的运行时进程。

`cli` 子系统则是面向终端用户的轻量 WebSocket 客户端。它解析命令行参数、加载 `.env`、校验可信目录,随后连接 Gateway 的 `/tui` 端点:先等待 `connection.ack` 握手帧,再构造 `chat.send` 帧,流式接收 server 回推的 E2A wire chunk,并交由三种渲染器(HumanRenderer / JsonRenderer / JsonlRenderer)输出。CLI 与 server 之间的端到端链路,正是验证 server 流式协议是否健壮的最短闭环。

`common` 子系统是协议与配置中枢,提供 E2A 信封编解码、schema 校验、安全(Origin 白名单、加密)、模式矩阵、reasoning 注入与 hooks 配置等公共能力;其中与协议强相关的部分在 [08-common与e2a](../08-common-e2a-and-security-module.md) 文档详述,本文聚焦 server + cli 的运行时与客户端行为。

设计上,server 选择"WS 单例 + 预热池 + 流式 chunk"而非 REST 轮询,是为了同时满足低首 token 延迟、长会话保活与主动下行三类诉求;E2A 信封则在传输层统一了请求、响应、推送、错误四种语义,使 server 内部分发只需按 `ReqMethod` 路由,无需为不同入口写不同 handler。cli 的三渲染器策略则把"给人看"与"给机器消费"解耦,HumanRenderer 负责交互体验,JsonRenderer / JsonlRenderer 服务于自动化管道。

server 与 cli 的子模块清单如下,文中所有文件位置均使用真实绝对路径,便于直接跳转源码:

| 子模块 | 职责 | 关键文件 |
| --- | --- | --- |
| server 入口 | AgentServer 进程启动:扩展加载、日志、ProactiveEngine | [app_agentserver.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/app_agentserver.py) |
| WebSocket 服务端 | AgentWebSocketServer 单例:监听 Gateway 连接、E2A 解析分发、流式/非流式、send_push | [agent_ws_server.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/agent_ws_server.py#L859) |
| Agent 管理器 | AgentManager:多 channel/mode/project 实例缓存、plan 子模式并轨、borrow/pin 生命周期 | [agent_manager.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/runtime/agent_manager.py#L106) |
| Agent 预热池 | AgentWarmPool:预热就绪 DeepAgent、前台并发信号量、后台冷却 | [agent_warm_pool.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/runtime/agent_warm_pool.py#L115) |
| Session 管理 | SessionManager:session 级任务队列(先进后出)、并发控制、一次性回收 | [session_manager.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/runtime/session/session_manager.py#L21) |
| A2UI 协议 | A2UI v0.8:配置、解析(tagged/JSON/JSONL)、schema 校验、prompt 构建 | [config.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/runtime/a2ui/config.py) · [parser.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/runtime/a2ui/parser.py#L92) · [protocol.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/runtime/a2ui/protocol.py#L72) · [validator.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/runtime/a2ui/validator.py) |
| Hooks 执行器 | HookExecutor:command/prompt 两类 hook 统一调度 | [executor.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/hooks/executor.py#L32) |
| UserHookRail | 用户 hooks 以 Rail 注册,拦截 before/after_tool_call/on_tool_exception/after_invoke | [user_hook_rail.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/hooks/user_hook_rail.py#L18) |
| Gateway Push | AgentServer→Gateway 下行推送(Transport Protocol)+ E2A server_push 线编码 | [transport.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/gateway_push/transport.py#L17) · [wire.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/gateway_push/wire.py#L21) |
| Sandbox | JiuwenBoxRunner:本地 jiuwenbox uvicorn 子进程管理 | [jiuwenbox_runner.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/sandbox/jiuwenbox_runner.py#L70) |
| Server Utils | DiffService(turn-based diff)、stream_utils(chunk 解析) | [diff_service.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/utils/diff_service.py#L58) · [stream_utils.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/utils/stream_utils.py#L10) |
| CLI 入口 | 根 CLI:dotenv 解析、参数、run_chat | [main.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/cli/main.py) |
| CLI Chat | chat 编排:参数、可信目录、交互循环、中断/恢复、team/plan 处理 | [chat.py#L444](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/cli/chat.py#L444) · [chat.py#L386](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/cli/chat.py#L386) |
| CLI Events | 事件判定:终态检测、交互检测、event_kind 分类 | [events.py#L16](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/cli/events.py#L16) · [events.py#L37](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/cli/events.py#L37) |
| CLI Render | 三渲染器:HumanRenderer(spinner + 流式)、JsonRenderer、JsonlRenderer | [render.py#L32](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/cli/render.py#L32) · [render.py#L167](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/cli/render.py#L167) |
| CLI GatewayClient | WS 客户端:connect(等 ack)、send_request、recv | [gateway_client.py#L35](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/cli/gateway_client.py#L35) · [gateway_client.py#L49](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/cli/gateway_client.py#L49) |

## 二、关键类与函数

| 类/函数 | 文件位置 | 说明 |
| --- | --- | --- |
| AgentWebSocketServer | [agent_ws_server.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/agent_ws_server.py#L859) | Gateway↔AgentServer WS 服务端单例 |
| AgentWebSocketServer.get_instance | [agent_ws_server.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/agent_ws_server.py#L939) | 单例工厂 |
| AgentWebSocketServer._process_request | [agent_ws_server.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/agent_ws_server.py#L1225) | 握手 Origin 校验 |
| AgentWebSocketServer._connection_handler | [agent_ws_server.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/agent_ws_server.py#L1293) | 处理单连接,发 connection.ack,并发分发,关闭时取消 inflight |
| AgentWebSocketServer._handle_message | [agent_ws_server.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/agent_ws_server.py#L1371) | 解析 JSON→E2AEnvelope→AgentRequest,按 ReqMethod 分发 |
| AgentWebSocketServer._handle_stream_impl | [agent_ws_server.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/agent_ws_server.py#L2597) | 流式处理:agent.process_message_stream 逐条编码 E2A wire 发送,心跳 keepalive |
| AgentWebSocketServer.send_push | [agent_ws_server.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/agent_ws_server.py#L7541) | 主动推送,build_server_push_wire 编码 |
| AgentManager | [agent_manager.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/runtime/agent_manager.py#L106) | 多 channel/mode/project 实例缓存 |
| AgentManager.get_agent | [agent_manager.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/runtime/agent_manager.py#L706) | 异步获取(自动创建) |
| AgentManager.process_message_stream | [agent_manager.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/runtime/agent_manager.py#L1176) | 流式:wait_for_session_prewarm→get_agent→透传 chunk |
| AgentWarmPool | [agent_warm_pool.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/runtime/agent_warm_pool.py#L115) | 预热池 |
| WarmKey | [agent_warm_pool.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/runtime/agent_warm_pool.py#L75) | 预热槽键 |
| SessionManager | [session_manager.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/runtime/session/session_manager.py#L21) | session 任务队列 |
| SessionManager.cancel_session_task | [session_manager.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/runtime/session/session_manager.py#L50) | 取消非流式任务 |
| A2UIProtocolSpec | [protocol.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/runtime/a2ui/protocol.py#L72) | A2UI v0.8 适配器:schema_manager、build_prompt、validate |
| parse_a2ui_response | [parser.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/runtime/a2ui/parser.py#L92) | 解析 A2UI 响应(JSONL/raw JSON/tagged) |
| HookExecutor | [executor.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/hooks/executor.py#L32) | 统一调度 command/prompt hook |
| HookExecutor._run_command_hook | [executor.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/hooks/executor.py#L60) | command hook(子进程),exit 2=blocking |
| UserHookRail | [user_hook_rail.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/hooks/user_hook_rail.py#L18) | 用户 hooks Rail,priority=60 |
| build_server_push_wire | [wire.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/gateway_push/wire.py#L21) | send_push 入参编码为 E2A wire,标记 _jiuwenswarm_server_push |
| WebSocketGatewayPushTransport | [transport.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/gateway_push/transport.py#L17) | 经进程内单例推送 |
| JiuwenBoxRunner | [jiuwenbox_runner.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/sandbox/jiuwenbox_runner.py#L70) | jiuwenbox uvicorn 子进程管理 |
| DiffService | [diff_service.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/utils/diff_service.py#L58) | turn-based diff |
| parse_stream_chunk | [stream_utils.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/utils/stream_utils.py#L10) | chunk→前端 payload |
| GatewayClient | [gateway_client.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/cli/gateway_client.py#L35) | CLI WS 客户端 |
| HumanRenderer | [render.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/cli/render.py#L32) | 人类可读渲染器 |
| HumanRenderer.handle_final | [render.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/cli/render.py#L167) | final 去重逻辑 |
| _run_interactive_loop | [chat.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/cli/chat.py#L444) | CLI 交互循环 |
| _build_request | [chat.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/cli/chat.py#L386) | 构造 chat.send 帧 |
| is_terminal_event | [events.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/cli/events.py#L16) | 终态判定 |

## 三、实现机制

### 1. 用户消息全链路时序(6 阶段)

一条用户消息从 CLI 输入到屏幕渲染,会穿越以下 6 个阶段,串起 server 与 cli 的全部关键类:

**阶段一 — CLI 构造与连接握手**。用户在交互循环 `_run_interactive_loop` 中输入文本,经 `_build_request` 组装为 `chat.send` 帧(包含 session_id、mode、project、payload 等)。`GatewayClient.connect` 先发起 WebSocket 连接,阻塞等待服务端返回 `connection.ack` 握手帧,确认会话绑定后才 `send_request` 发出业务帧。ack 前不发业务帧,是为了避免会话未绑定时消息丢失。

**阶段二 — Gateway 转发**。Gateway 把 IM/CLI/Web 等异构入口归一化后,通过 `message_to_e2a_or_fallback` 将原始消息转成 E2A 信封,经内部 WS 反向连到 AgentServer。Gateway 在此处承担"协议翻译 + 路由绑定"职责,本身不持有 Agent 状态。

**阶段三 — AgentServer 接入分发**。`AgentWebSocketServer._connection_handler` 处理单条连接:先发 `connection.ack`,随后进入并发分发循环;连接关闭时取消该连接上所有 inflight 任务,避免悬空协程。`_handle_message` 负责把 JSON 解析为 `E2AEnvelope.from_dict`,再 `e2a_to_agent_request` 转成 `AgentRequest`,按 `ReqMethod` 路由到流式或非流式分支;解析失败时走 legacy 兜底以兼容旧客户端,保证协议升级期不破坏存量。

**阶段四 — 流式处理循环**。`_handle_stream_impl` 调用 `ensure_persistent_checkpointer` 确保会话持久化,启动心跳 `_heartbeat_loop` 维持 WS 活性(防止反向代理空闲断连),核心是 `async for chunk in agent.process_message_stream(...)` 逐条产出 chunk。

**阶段五 — Agent 内部透传**。`AgentManager.process_message_stream` 先 `wait_for_session_prewarm` 等待预热就绪,再 `get_agent` 取实例,把上游 chunk 透传出去;`parse_stream_chunk` 把 chunk 拆解为前端 payload,`encode_agent_chunk_for_wire` 编码为 E2A wire,`ws.send` 回推。整条透传不做业务加工,保证流式低延迟。

**阶段六 — CLI 解析渲染**。CLI 侧 `parse_agent_server_wire_chunk` 还原 wire chunk,`event_kind` 分类(文本/工具/思考/交互/终态),`HumanRenderer` 处理 spinner 与流式增量,`handle_final` 在终态时做 final 去重(避免 final 与流式增量重复输出),`is_terminal_event` 命中终态后退出单轮循环。

```
CLI _build_request → GatewayClient.connect(等 ack) → send_request
   → Gateway message_to_e2a_or_fallback → AgentServer _connection_handler(发 ack)
   → _handle_message(E2AEnvelope.from_dict → e2a_to_agent_request,失败 legacy 兜底)
   → _handle_stream_impl(ensure_persistent_checkpointer + 心跳_loop + async for chunk)
   → AgentManager.process_message_stream(wait_for_session_prewarm → get_agent → 透传)
   → parse_stream_chunk → encode_agent_chunk_for_wire → ws.send
   → CLI parse_agent_server_wire_chunk → event_kind 分类 → HumanRenderer → is_terminal_event 退出
```

### 2. 主动推送 send_push

除请求—响应外,server 还支持主动下行推送:`send_push` 把入参交给 `build_server_push_wire` 编码为 E2A wire,并打上 `_jiuwenswarm_server_push` 标记,使其与普通 RPC 响应可共用同一条 WS 连接却不抢占等待队列——推送帧不对应任何 inflight 请求,客户端按标记直接派发到 push 通道。`WebSocketGatewayPushTransport` 经进程内单例完成实际下发,避免多实例重复推送。典型场景包括定时任务结果回投、异步工具完成后回投、外部 IM 事件触发的主动提醒等。

### 3. Agent 预热池机制

`AgentWarmPool` 用 `WarmKey` 作为预热槽键(由 channel/mode/project 拼装),在后台预热就绪的 DeepAgent 实例。前台请求到来时,若信号量(`asyncio.Semaphore`)有余量则立即借出(borrow),否则排队;对被 pin 的实例走引用计数避免回收。后台冷却协程在实例空闲超过阈值后归还,并在配置变更时清理 stale marker,保证预热槽不残留失效实例。这一设计把"首 token 延迟"从"冷启动建 Agent"压到"取预热实例",是流式体验的关键。stale marker 的清理逻辑确保 Skill/工具配置热更新后,旧预热实例不会"借出即用错工具"。

### 4. SessionManager 任务队列

`SessionManager` 为每个 session 维护一条任务队列,采用先进后出(LIFO)策略:同一 session 的新请求优先于旧请求执行,符合"用户最新输入最重要"的交互直觉。并发控制保证单 session 串行(避免 checkpoint 写冲突),跨 session 则并行。`cancel_session_task` 在用户中断或会话结束时一次性回收该 session 的非流式任务,流式任务由 `_handle_stream_impl` 的 finally 块兜底取消,二者配合保证无悬空协程。

### 5. E2A 信封与 legacy 兜底

E2A 信封是 server 与外部通信的统一容器,封装了 method、session_id、trace_id、payload、stream 标志等字段。`_handle_message` 的解析路径是:`raw JSON → E2AEnvelope.from_dict → e2a_to_agent_request`;当信封字段缺失或版本不匹配时,回退到 legacy 解析(按旧字段名直接取值),并把请求标记为"legacy 模式"以走兼容响应路径。这一兜底让 server 在协议升级过渡期可同时服务新旧客户端,无需停机。

### 6. Hooks 与 A2UI 副链路

`HookExecutor` 统一调度两类 hook:command hook 经子进程执行,退出码 2 被解释为 blocking(阻断后续流程),其他码视为告警;prompt hook 在 prompt 组装阶段注入文本。`UserHookRail` 以 priority=60 注册,拦截 `before_tool_call`/`after_tool_call`/`on_tool_exception`/`after_invoke` 等事件,使用户逻辑无需侵入核心即可插入。A2UI v0.8 适配器 `A2UIProtocolSpec` 提供 `schema_manager`、`build_prompt`、`validate` 三件套;`parse_a2ui_response` 兼容 tagged / raw JSON / JSONL 三种产出格式,把富前端协议与 Agent 输出解耦——Agent 只需产出结构化片段,A2UI 适配器负责拼装为可被前端渲染的富组件树。

### 7. JiuwenBox 沙箱与 DiffService

`JiuwenBoxRunner` 负责拉起本地 jiuwenbox 的 uvicorn 子进程作为代码执行沙箱,管理其生命周期(启动/健康检查/优雅退出/超时强杀),Agent 的代码执行类工具通过该沙箱隔离运行。`DiffService` 提供 turn-based diff:以一个对话 turn 为单位,对比前后状态(文件树/内存/输出),产出结构化差异,供前端做增量渲染与回溯审阅,避免每次全量重绘。

### 8. Origin 安全校验与连接生命周期

连接进入业务循环前,`_process_request` 先做握手 Origin 校验:只允许白名单内的 Origin 完成 WS 升级,拒绝跨域来源,从入口侧阻断 WebSocket 劫持。Origin 白名单由 `common/security/ws_origin.py` 统一维护(详见 08 文档),server 只消费校验结果,不重复实现安全策略。

握手通过后,`_connection_handler` 为该连接建立上下文,先回送 `connection.ack`,随后把后续每条消息 `asyncio.create_task` 并发分发,而不是串行 await——这保证长流式请求不会阻塞同连接后续的控制帧(如 cancel、ping)。每条 inflight 任务都被登记到连接级集合,用于关闭时统一回收。

连接关闭时,handler 在 finally 中遍历并取消该连接上所有 inflight 任务:流式任务被取消后其 generator 会在 finally 释放 Agent 资源,非流式任务则由 `SessionManager.cancel_session_task` 兜底,二者协同实现"连接级无悬空"。这一设计是 server 能在长会话、高并发下稳定运行的回收底线。

## 四、调用示例

CLI 侧发起一次流式会话(节选自交互循环的连接与发送):

```python
from jiuwenswarm.cli.gateway_client import GatewayClient
from jiuwenswarm.cli.chat import _build_request
from jiuwenswarm.cli.events import is_terminal_event
from jiuwenswarm.cli.render import HumanRenderer
from jiuwenswarm.common.e2a.wire_codec import parse_agent_server_wire_chunk

async def run_once(user_text: str, session_id: str) -> None:
    client = GatewayClient(uri="ws://127.0.0.1:8080/tui")
    await client.connect()            # 阻塞直到收到 connection.ack
    frame = _build_request(          # 组装 chat.send 帧
        text=user_text,
        session_id=session_id,
        mode="code",
        project="demo",
    )
    await client.send_request(frame)

    renderer = HumanRenderer()
    async for wire in client.recv():               # 流式接收 E2A wire
        chunk = parse_agent_server_wire_chunk(wire)
        renderer.handle(chunk)
        if is_terminal_event(chunk.event_kind):   # 命中终态结束本轮
            renderer.handle_final(chunk)          # final 去重
            break
    await client.close()
```

server 侧流式处理核心循环(节选自 `_handle_stream_impl`):

```python
async def _handle_stream_impl(self, ws, env: E2AEnvelope, req: AgentRequest):
    await ensure_persistent_checkpointer(req.session_id)   # 持久化 checkpoint
    heartbeat = asyncio.create_task(self._heartbeat_loop(ws))
    try:
        agent = AgentManager.get_instance()
        async for chunk in agent.process_message_stream(req):
            payload = parse_stream_chunk(chunk)            # chunk → 前端 payload
            wire = encode_agent_chunk_for_wire(payload, env)  # E2A wire 编码
            await ws.send(wire)                             # 流式回推
    finally:
        heartbeat.cancel()
        await self._cancel_inflight(ws)                     # 连接关闭兜底
```

主动推送场景(外部触发,如定时任务结果回投):

```python
from jiuwenswarm.server.gateway_push.wire import build_server_push_wire
from jiuwenswarm.server.gateway_push.transport import WebSocketGatewayPushTransport

async def push_result(session_id: str, payload: dict) -> None:
    wire = build_server_push_wire(
        session_id=session_id,
        payload=payload,
        method="server.push.result",
    )                                   # 标记 _jiuwenswarm_server_push
    transport = WebSocketGatewayPushTransport.get_instance()
    await transport.send(session_id, wire)   # 与 RPC 共用 WS,不抢队列
```

session 中断与预热等待(配合 `SessionManager` 与 `AgentManager`):

```python
from jiuwenswarm.server.runtime.session.session_manager import SessionManager
from jiuwenswarm.server.runtime.agent_manager import AgentManager

async def handle_interrupt(session_id: str) -> None:
    sm = SessionManager.get_instance()
    await sm.cancel_session_task(session_id)          # 取消非流式任务

async def ensure_ready(req: AgentRequest) -> None:
    am = AgentManager.get_instance()
    await am.wait_for_session_prewarm(req.session_id) # 等预热就绪
    agent = await am.get_agent(req)                    # 取/建实例
```

CLI 渲染与终态判定(节选自 HumanRenderer + events,展示 event_kind 分类与 final 去重):

```python
from jiuwenswarm.cli.render import HumanRenderer
from jiuwenswarm.cli.events import is_terminal_event, event_kind

def on_chunk(chunk, renderer: HumanRenderer) -> bool:
    kind = event_kind(chunk)                  # 文本/工具/思考/交互/终态
    if kind == "text":
        renderer.append_text(chunk.delta)       # spinner + 流式增量
    elif kind == "tool":
        renderer.append_tool(chunk.tool_name, chunk.args)
    elif kind == "interaction":
        renderer.prompt_interaction(chunk)     # 触发用户交互
    if is_terminal_event(kind):                # 命中终态
        renderer.handle_final(chunk)           # final 去重,避免与增量重复
        return True
    return False
```

## 五、业界对比

| 能力维度 | JiuwenSwarm | LangServe | Dify | AutoGen Studio |
| --- | --- | --- | --- | --- |
| 通信协议 | WS 长连接 + E2A 信封 + 双向推送 | REST/HTTP + SSE | HTTP 对话运行时 + SSE | 本地 WebSocket(单机) |
| 实例管理 | 多 channel/mode/project 缓存 + borrow/pin | 无状态,无实例 | 会话级运行时 | 进程内 Agent |
| 流式 | 全链路 chunk 流式 + 心跳 keepalive | SSE 单向流 | SSE 单向流 | 阻塞/偶发 SSE |
| 预热 | WarmPool 前台信号量 + 后台冷却 | 无 | 无 | 无 |
| 主动推送 | send_push server_push 线编码,与 RPC 共用 WS | 不支持 | 不支持 | 不支持 |
| 用户扩展点 | UserHookRail(17 事件) | 自定义 chain | 插件市场 | 自定义 Agent |
| 沙箱 | jiuwenbox uvicorn 子进程 | 无 | 内置代码沙箱 | Docker(可选) |

JiuwenSwarm 的差异化在于把"协议层(E2A)+ 运行时(预热池/会话队列)+ 富前端(A2UI)+ 推送"四件事压进一个 WS 单例,既保留低首 token 延迟,又支持主动下行,是面向长会话智能体的运行时取舍。LangServe 偏"无状态 API",Dify 偏"对话式工作流",AutoGen Studio 偏"本地可视化编排",三者均未把"预热 + 主动推送"作为一等公民;而 JiuwenSwarm 因为面向真实生产场景的长会话 Agent,这两者是刚需,故被显式建模进 server。

## 六、小结

1. server 是 AgentServer 运行时核心,以 `AgentWebSocketServer` 单例承接 Gateway/CLI 的 WS 连接,统一处理 E2A 解析、Agent 调度与流式回推。
2. 全链路 6 阶段(构造→转发→接入分发→流式循环→透传→渲染)清晰分层,任一阶段可独立替换或兜底(legacy 路径),保证协议升级过渡期不断服。
3. 预热池(WarmKey + 信号量 + 后台冷却 + stale marker 清理)把首 token 延迟压到"取预热实例"量级,是流式体验的关键工程。
4. `send_push` 经 `build_server_push_wire` 标记后与 RPC 共用 WS,实现"主动推送不抢队列"的并发模型;`SessionManager` 的 LIFO 队列与一次性回收保证"最新输入优先且无悬空协程"。
5. cli 作为最短闭环,三渲染器(Human/Json/Jsonl)+ 终态检测 + final 去重构成轻量但完整的客户端,既可面向人也可面向机器消费,是验证 server 流式协议健壮性的标尺。
