# 04 gateway 与 channels 模块（IM 网关与多渠道接入）

> 交叉引用: [01-项目概述](../01-project-overview.md) | [02-整体架构](../02-overall-architecture.md) | [05-server与cli](../05-server-and-cli-module.md) | [10-依赖关系](10-dependencies.md)

## 一、能力概述

`gateway/` 与 `channels/` 共同构成 JiuwenSwarm 的接入层与消息总线。`gateway` 负责多路径 WebSocket 网关、多协议渠道接入、消息路由、AgentServer 通信（E2A 协议）、cron 定时调度、心跳探活、会话钩子与附件处理；`channels` 则是各终端渠道（web/tui/desktop/acp）的独立进程入口。两者分工明确：gateway 是"统一接入与路由中枢"，channels 是"终端进程壳"。

`GatewayServer` 作为多路径 WS 网关，是整个接入层的核心。它在一个进程内承载 web/tui/acp/a2a/ssh 五类终端协议入口，外加 9 个 IM 平台（飞书、钉钉、企微、Telegram、Discord、Slack、WhatsApp、微信、小艺）。所有入站消息经 `RobotMessageRouter`（消息总线）归一化，再经 `AgentServerClient` 以 E2A（Edge-to-Agent）协议转发给后端 AgentServer，回传结果再经路由表推回对应渠道。这一设计让"前端渠道多样性"与"后端 Agent 唯一性"彻底解耦。

在项目定位上，本模块是"用户触达入口"。它把企业 IM、桌面应用、Web SPA、ACP stdio 等异构终端统一为一致的 E2A 消息流，使上层 agents/server 模块无需感知渠道差异。同时，它内置 cron 调度、心跳、附件、数字分身改写等横切能力，使接入层不只是"转发管道"，而是一个具备调度与编排能力的边缘运行时。

## 二、关键类与函数

### 2.1 路由核心（routing）

| 类/函数 | 文件位置 | 说明 |
| --- | --- | --- |
| AgentServerClient | [agent_client.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/routing/agent_client.py#L73) | AgentServer 客户端抽象基类 |
| WebSocketAgentServerClient | [agent_client.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/routing/agent_client.py#L114) | WS 实现，三级级联客户端查找 |
| send_request | [agent_client.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/routing/agent_client.py#L386) | 非流式 E2A 发送 |
| send_request_stream | [agent_client.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/routing/agent_client.py#L439) | 流式 E2A 发送 |
| _message_receiver_loop | [agent_client.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/routing/agent_client.py#L221) | 后台路由入站 WS 消息至 per-request_id 队列 |
| RoutingKey | [keys.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/routing/keys.py#L34) | 5 维 frozen 路由键（user_id/channel_id/app_id/agent_ref/session_id） |
| AgentRef | [keys.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/routing/keys.py#L15) | Agent 身份（mode,id） |
| DeliveryTarget | [keys.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/routing/keys.py#L88) | 物理投递目标基类 |
| make_delivery_target | [keys.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/routing/keys.py#L314) | 投递目标工厂 |
| SessionMap | [session_map.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/routing/session_map.py#L46) | 稳定身份 → agent session_id 映射 |
| SessionMapScope | [session_map.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/routing/session_map.py#L10) | 映射作用域枚举 |
| GatewayRouteBinding | [route_binding.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/routing/route_binding.py#L8) | 路由绑定数据类 |
| third_agent 工厂 | [third_agent.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/routing/third_agent.py#L11) | 三方 agent 适配 |

### 2.2 渠道生命周期（channel_manager）

| 类/函数 | 文件位置 | 说明 |
| --- | --- | --- |
| ChannelType | [base.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/channel_manager/base.py#L21) | 渠道类型枚举（ACP/WEB/FEISHU/...） |
| RobotMessageRouter | [base.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/channel_manager/base.py#L48) | 消息总线：入站+出站队列，订阅/分发 |
| BaseChannel | [base.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/channel_manager/base.py#L114) | 渠道抽象基类：start/stop/send/is_allowed |
| 各 IM 适配器 | [base.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/channel_manager/base.py#L21) | 飞书/钉钉/企微等具体适配器 |
| 协议适配器 | [base.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/channel_manager/base.py#L48) | 协议层适配 |

### 2.3 cron 定时任务（cron）

| 类/函数 | 文件位置 | 说明 |
| --- | --- | --- |
| CronController | [controller.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/cron/controller.py#L25) | 单例 CRUD API，校验 cron_expr/work_mode/project |
| CronSchedulerService | [scheduler.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/cron/scheduler.py#L249) | 堆式异步调度器：wake/push/push_update，team streaming/unary/proactive.tick |
| _Event | [scheduler.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/cron/scheduler.py#L241) | frozen 调度事件数据类 |
| _cron_next_push_dt | [scheduler.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/cron/scheduler.py#L221) | croniter 计算下次 push（5/7-field） |
| _run_unary_cron_job | [scheduler.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/cron/scheduler.py#L1140) | unary 执行 |
| _run_team_stream_job | [scheduler.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/cron/scheduler.py#L1187) | team streaming 执行 |
| _push_to_targets | [scheduler.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/cron/scheduler.py#L1372) | 推送结果至目标渠道，按渠道解析 metadata |
| CronJob | [models.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/cron/models.py#L236) | 持久化 job |
| CronTargetChannel | [models.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/cron/models.py#L14) | 目标渠道枚举 |
| CronRunState | [models.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/cron/models.py#L443) | 运行内存状态 |
| CronJobStore | [store.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/cron/store.py#L117) | 文件持久化（cron_jobs.json）+ portalocker 锁 |
| normalize_cron_expr | [cron_expr.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/cron/cron_expr.py#L12) | 5→7-field 规范化 |
| validate_cron_expression | [cron_expr.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/cron/cron_expr.py#L52) | 校验 cron 表达式 |
| encode_dingtalk_cron_session_id | [dingtalk_routing.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/cron/dingtalk_routing.py#L44) | 钉钉会话路由编码 |

### 2.4 心跳/钩子/附件/数字分身

| 类/函数 | 文件位置 | 说明 |
| --- | --- | --- |
| GatewayHeartbeatService | [heartbeat.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/heartbeat/heartbeat.py#L102) | 周期探活 + relay 回传 |
| HeartbeatConfig | [heartbeat.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/heartbeat/heartbeat.py#L60) | 探活配置（active_hours/relay_channel） |
| GatewayHookHandler | [handler.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/hooks/handler.py#L16) | 会话钩子（10s 超时不阻塞） |
| IMPlatformAdapter | [im_inbound.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/im_pipeline/im_inbound.py#L68) | 平台适配器 |
| IMConversationProcessor | [im_inbound.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/im_pipeline/im_inbound.py#L139) | LLM 数字分身改写 |
| IMInboundPipeline | [im_inbound.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/im_pipeline/im_inbound.py#L470) | 入站管道 |
| persist_and_parse_documents | [document_attachments.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/attachments/document_attachments.py#L58) | 文档解析（30MB/20-doc） |
| normalize_chat_media_attachments | [media_attachments.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/attachments/media_attachments.py#L29) | 图片校验（10MB/8-image） |

### 2.5 网关主入口与终端渠道

| 类/函数 | 文件位置 | 说明 |
| --- | --- | --- |
| GatewayServer | [app_gateway.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/app_gateway.py#L435) | 多路径 WS 网关，维护 session/request 路由表 |
| RouteConfig | [app_gateway.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/app_gateway.py#L387) | 单路由配置 |
| GatewayServerConfig | [app_gateway.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/app_gateway.py#L409) | 顶层网关配置 |
| _connect_with_retry | [app_gateway.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/app_gateway.py#L250) | TCP 探测后 WS 握手，指数退避重连 |
| _normalize_and_forward_message | [app_gateway.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/app_gateway.py#L137) | 规范化入站消息并转发 |
| _run | [app_gateway.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/app_gateway.py#L1426) | 主异步编排，初始化所有渠道+心跳+cron |
| _apply_channel_config | [app_gateway.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/app_gateway.py#L2002) | 动态渠道热插拔：停旧建新 |
| _SpaStaticHandler | [app_web.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/channels/web/app_web.py#L175) | Web SPA 静态处理器 |
| main(web) | [app_web.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/channels/web/app_web.py#L1222) | Web 入口 |
| DesktopRuntime | [desktop_app.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/channels/desktop/desktop_app.py#L417) | 桌面运行时（pywebview） |
| resolve_desktop_ports | [desktop_app.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/channels/desktop/desktop_app.py#L97) | 端口解析 |
| run_acp | [app_acp.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/channels/acp/app_acp.py#L76) | ACP stdio 网关子命令 |

### 2.6 渠道清单

| 类别 | 渠道 | ChannelType | 说明 |
| --- | --- | --- | --- |
| IM | 飞书 | FEISHU | 多应用/企业版，Webhook + 事件订阅 |
| IM | 钉钉 | DINGTALK | 钉钉会话路由编码 dingtalk_routing.py#L44 |
| IM | 企微 | WECOM | 企业微信 |
| IM | Telegram | TELEGRAM | Bot API |
| IM | Discord | DISCORD | Gateway Bot |
| IM | Slack | SLACK | Events API |
| IM | WhatsApp | WHATSAPP | Cloud API |
| IM | 微信 | WECHAT | 公众号/小程序 |
| IM | 小艺 | XIAOYI | 语音助手渠道 |
| 终端 | web | WEB | SPA 静态服务 + 反向代理 app_web.py#L175 |
| 终端 | tui | TUI | 终端 UI |
| 终端 | desktop | DESKTOP | pywebview 桌面壳 desktop_app.py#L417 |
| 协议 | acp | ACP | stdio 网关子命令 app_acp.py#L76 |
| 协议 | a2a | A2A | Agent-to-Agent 协议 |
| 协议 | ssh | SSH | SSH 接入 |

所有渠道均实现 `BaseChannel(base.py#L114)`，经 `RobotMessageRouter(base.py#L48)` 统一入站/出站，保证渠道间行为一致。

## 三、实现机制

### 3.1 IM 入站 → 路由 → Agent → 回推全链路时序

整条链路是 gateway 的核心数据流，分入站、路由、回推三大段，共 20 个阶段。每一阶段都保证幂等与可恢复。

```text
[1]  平台 Webhook / WS 推送原始消息
[2]  IMChannel._handle_message 构造 Message
[3]  RobotMessageRouter.route_user_message 入站（消息总线归一）
[4]  （可选）IMInboundPipeline 数字分身 LLM 改写
       └─ IMConversationProcessor(im_inbound.py#L139) 按群聊上下文改写
[5]  _normalize_and_forward_message(app_gateway.py#L137) 规范化转发
[6]  MessageHandler 接管
[7]  构造 RoutingKey(keys.py#L34)：5 维 (user_id,channel_id,app_id,agent_ref,session_id)
[8]  SessionMap(session_map.py#L46) 查找/创建 agent session_id
[9]  构造 E2AEnvelope
[10] send_request_stream(agent_client.py#L439) 经 E2A over WS 发送
[11] AgentServer 接收，调度对应 agent
[12] E2AResponse / AgentResponseChunk 流式回传
[13] _message_receiver_loop(agent_client.py#L221) 路由至 per-request_id 队列
[14] 构造回推 Message
[15] queue_robot_message 入出站队列
[16] dispatch 分发
[17] make_delivery_target(keys.py#L314) 解析物理投递目标
[18] IMChannel.send 调用平台 API
[19] 平台投递至用户终端
[20] 会话钩子 GatewayHookHandler(handler.py#L16) 收尾（10s 超时不阻塞）
```

第 [7] 步的 `RoutingKey` 是 5 维 frozen dataclass，保证同一 (user/channel/agent) 元组在多次请求间稳定，是 `SessionMap` 能正确复用 agent session 的前提。第 [13] 步的 `_message_receiver_loop` 是后台协程，按 `request_id` 把流式 chunk 分发到对应队列，使多个并发请求可复用同一条 WS 连接而不串流。

### 3.2 动态渠道热插拔

`_apply_channel_config(app_gateway.py#L2002)` 实现"停旧建新"的渠道热插拔，支持飞书多应用与企业版切换：

```text
收到新渠道配置
   │
   ▼
[1] 停止旧渠道：BaseChannel.stop()，从 RobotMessageRouter 取消订阅
   │
   ▼
[2] 释放旧句柄（WS 连接、Webhook 处理器）
   │
   ▼
[3] 按新 ChannelType 构造新 BaseChannel
   │
   ▼
[4] 新渠道 start()，注册到 RobotMessageRouter
   │
   ▼
[5] 路由表更新（RouteConfig/GatewayRouteBinding）
```

这一机制让运维侧可以在不重启 gateway 进程的前提下，动态增删 IM 应用（例如切换飞书自建应用与企业版），保证业务连续性。

### 3.3 cron 堆式事件队列

`CronSchedulerService(scheduler.py#L249)` 采用堆式异步事件队列，而非传统轮询。核心数据结构是 `_Event(scheduler.py#L241)` frozen 事件，按下次触发时间堆排：

```text
[1] wake()：扫描 cron_jobs.json，对每个 job 用 _cron_next_push_dt 计算下次 push
       └─ croniter 支持 5-field 与 7-field 表达式
[2] push(event)：新事件入堆，按 next_dt 排序
[3] push_update(event)：已有事件下次时间变更时原地更新
[4] 调度循环：取出堆顶事件 → 到点执行 → 计算下一次 → 重新 push
[5] 文件 mtime 轮询：检测 cron_jobs.json 变更，触发 wake
[6] 崩溃恢复：进程重启后从 store 重建事件堆
[7] team streaming：_run_team_stream_job 消费 SwarmFlow 事件流
       └─ unary 走 _run_unary_cron_job 单次执行
[8] _push_to_targets(scheduler.py#L1372)：按渠道解析 metadata 推送结果
```

team streaming 模式的特殊之处在于它消费的是一条持续的事件流（SwarmFlow），而非一次性响应。调度器需要边消费边推送，并在流结束后计算下一次 cron 触发，这与 unary 的"请求-响应-下一轮"模式形成对照。

## 四、调用示例

### 4.1 启动多路径网关

```python
from jiuwenswarm.gateway.app_gateway import GatewayServer, GatewayServerConfig

config = GatewayServerConfig(
    listen_host="0.0.0.0",
    listen_port=8787,
    routes=[
        # /acp、/cli 等多路径，每条路径独立 channel_id 与 handler
    ],
    agent_server_url="ws://127.0.0.1:9002/e2a",
)
server = GatewayServer(config, router=bus)
# _run(app_gateway.py#L1426) 内部初始化所有渠道+心跳+cron
```

### 4.2 流式 E2A 发送

```python
from jiuwenswarm.gateway.routing.agent_client import WebSocketAgentServerClient

client = WebSocketAgentServerClient(url="ws://127.0.0.1:9002/e2a")
# send_request_stream(agent_client.py#L439) 返回流式 chunk
async for chunk in client.send_request_stream(envelope, request_id="req-001"):
    # chunk 为 AgentResponseChunk
    bus.queue_robot_message(chunk)
# _message_receiver_loop 后台路由入站 WS 消息至 per-request_id 队列
```

### 4.3 注册 cron 任务

```python
from jiuwenswarm.gateway.cron.controller import CronController
from jiuwenswarm.gateway.cron.cron_expr import validate_cron_expression

validate_cron_expression("0 9 * * 1-5")   # 校验 5-field
controller = CronController.instance()
controller.create(
    cron_expr="0 9 * * 1-5",              # 工作日 09:00
    work_mode="team",                     # 或 "unary"
    project="/workspace/proj",
    target_channel="feishu",
)
# CronJobStore(store.py#L117) 持久化至 cron_jobs.json + portalocker 锁
# CronSchedulerService wake 后入堆调度
```

### 4.4 渠道热插拔

```python
# _apply_channel_config(app_gateway.py#L2002) 停旧建新
server._apply_channel_config(new_channel_config)
# 旧 IMChannel.stop() → 释放句柄 → 新 BaseChannel.start() → 路由表更新
```

## 五、业界对比

| 能力维度 | JiuwenSwarm | n8n | Dify | Coze |
| --- | --- | --- | --- | --- |
| IM 覆盖 | 9 IM + web/tui/desktop + acp/a2a/ssh | Webhook 触发，无原生 IM | 对话应用为主 | 多渠道发布 |
| 路由模型 | 5 维 RoutingKey + SessionMap 稳定映射 | 节点连线 | 对话 session | bot 路由 |
| 协议统一 | E2A over WS，RobotMessageRouter 总线 | REST/Webhook | HTTP API | 平台协议 |
| 定时任务 | 堆式事件队列 + mtime 轮询 + 崩溃恢复 + team streaming | Cron 触发节点 | 不内置 | 定时调用 |
| 渠道热插拔 | _apply_channel_config 停旧建新 | 节点增删 | 不支持运行时 | 不支持运行时 |
| 数字分身 | IMInboundPipeline LLM 群聊改写 | 不支持 | 不支持 | 不支持 |
| 分布式接入 | GatewayServer 多路径 WS + 心跳 relay | 不适用 | 单实例 | 云托管 |

JiuwenSwarm 的差异化在于"多 IM + 多终端 + 多协议"统一接入，并以 E2A 协议 + RobotMessageRouter 总线把异构渠道归一为一致消息流。相对 n8n 的工作流触发模型、Dify 的对话应用定位、Coze 的平台托管模式，本模块更偏"边缘接入运行时"：它在接入侧就完成路由、调度、心跳、改写、附件等横切能力，使后端 AgentServer 只需专注 agent 执行。

## 六、小结

1. `gateway/` 与 `channels/` 构成接入层与消息总线：gateway 是统一接入与路由中枢，channels 是各终端进程壳，两者经 `BaseChannel` + `RobotMessageRouter` 统一。
2. `GatewayServer` 是多路径 WS 网关，一个进程承载 5 类终端协议 + 9 个 IM 平台，经 `AgentServerClient` 以 E2A 协议连后端。
3. 入站 → 路由 → Agent → 回推全链路共 20 阶段，`RoutingKey` 5 维稳定键 + `SessionMap` 保证 agent session 复用，`_message_receiver_loop` 按 request_id 路由流式 chunk。
4. cron 采用堆式事件队列（wake/push/push_update）+ 文件 mtime 轮询 + 崩溃恢复，team streaming 模式持续消费 SwarmFlow 事件流。
5. `_apply_channel_config` 实现渠道热插拔（停旧建新），支持飞书多应用与企业版运行时切换，保证业务连续。
6. 相对竞品，本模块以"多 IM + 多终端 + 多协议统一接入 + E2A 总线 + 堆式 cron"形成差异化，定位为具备调度与编排能力的边缘运行时。
