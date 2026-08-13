# 多平台 IM 接入

> 交叉引用: [01-项目概述](../01-project-overview.md) | [02-整体架构](../02-overall-architecture.md) | [04-gateway与channels](../04-gateway-and-channels-module.md) | [特性索引](README.md)

## 一、能力概述

JiuwenSwarm 的接入层把"用户触达入口"做到了行业少见的广度:覆盖 9 个主流 IM 平台(飞书、钉钉、企微、Telegram、Discord、Slack、WhatsApp、微信、小艺),同时承载 web/tui/desktop 三类终端,外加 acp/a2a/ssh 三类协议渠道。所有这些异构渠道的消息都经 `RobotMessageRouter` 这条消息总线归一化,再以 E2A(Edge-to-Agent)协议转发给后端 AgentServer,回传结果再按渠道特定方式投递回用户终端。

这一设计的核心价值是"前端渠道多样性"与"后端 Agent 唯一性"彻底解耦:无论消息来自飞书 Webhook 还是 Slack Events API,在 gateway 内部都是同一种归一化 Message,走同一条 5 维 `RoutingKey` 路由,复用同一套 agent session。这使得上层 agents/server 模块完全无需感知渠道差异,只面向统一的 E2A 消息流编程。

在能力层面,本特性不止是"转发管道":它内置数字分身群聊改写(`IMInboundPipeline` 用 LLM 按群聊上下文改写入站消息)、渠道热插拔(`_apply_channel_config` 停旧建新,支持飞书多应用与企业版运行时切换)、会话绑定(`SessionMap` 把稳定身份映射到 agent session_id)。这些使接入层成为一个具备编排能力的边缘运行时。

## 二、关键类与函数

| 类/函数 | 文件位置 | 说明 |
| --- | --- | --- |
| GatewayServer | [app_gateway.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/app_gateway.py#L435) | 多路径 WS 网关,一个进程承载 5 类终端协议 + 9 个 IM 平台 |
| _run | [app_gateway.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/app_gateway.py#L1426) | 主异步编排:初始化所有渠道+心跳+cron |
| _apply_channel_config | [app_gateway.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/app_gateway.py#L2002) | 动态渠道热插拔:停旧建新,支持飞书多应用切换 |
| RobotMessageRouter | [base.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/channel_manager/base.py#L48) | 消息总线:入站+出站队列,订阅/分发 |
| BaseChannel | [base.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/channel_manager/base.py#L114) | 渠道抽象基类:start/stop/send/is_allowed,所有 IM 适配器实现它 |
| ChannelType | [base.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/channel_manager/base.py#L21) | 渠道类型枚举(ACP/WEB/FEISHU/DINGTALK/...) |
| RoutingKey | [keys.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/routing/keys.py#L34) | 5 维 frozen 路由键(user_id/channel_id/app_id/agent_ref/session_id) |
| DeliveryTarget | [keys.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/routing/keys.py#L88) | 物理投递目标基类 |
| make_delivery_target | [keys.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/routing/keys.py#L314) | 投递目标工厂:按渠道解析物理投递目标 |
| SessionMap | [session_map.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/routing/session_map.py#L46) | 稳定身份→agent session_id 映射,保证会话复用 |
| IMInboundPipeline | [im_inbound.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/im_pipeline/im_inbound.py#L470) | 数字分身入站管道:LLM 按群聊上下文改写消息 |
| IMConversationProcessor | [im_inbound.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/im_pipeline/im_inbound.py#L139) | LLM 改写处理器,按群聊上下文改写 |
| WebSocketAgentServerClient | [agent_client.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/routing/agent_client.py#L114) | WS 实现,流式 E2A 发送 |
| _normalize_and_forward_message | [app_gateway.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/app_gateway.py#L137) | 规范化入站消息并转发 |

## 三、实现机制

### 3.1 IM 入站 → 路由 → Agent → 回推全链路

整条链路是 gateway 的核心数据流,分入站、路由、回推三大段,每一阶段都保证幂等与可恢复:

```text
[1]  IM 平台 Webhook / WS 推送原始消息
[2]  BaseChannel._handle_message 构造 Message(base.py#L114)
[3]  RobotMessageRouter.route_user_message 入站(base.py#L48)
[4]  (可选)IMInboundPipeline 数字分身 LLM 改写
       └─ IMConversationProcessor(im_inbound.py#L139) 按群聊上下文改写
[5]  _normalize_and_forward_message(app_gateway.py#L137) 规范化转发
[6]  构造 RoutingKey(keys.py#L34):5 维(user_id,channel_id,app_id,agent_ref,session_id)
[7]  SessionMap(session_map.py#L46) 查找/创建 agent session_id
[8]  send_request_stream 流式 E2A over WS 发送
[9]  AgentServer 接收,调度对应 agent
[10] AgentResponseChunk 流式回传
[11] 构造回推 Message,queue_robot_message 入出站队列
[12] make_delivery_target(keys.py#L314) 解析物理投递目标
[13] BaseChannel.send 调用平台 API,投递至用户终端
```

第 [6] 步的 `RoutingKey` 是 5 维 frozen dataclass,保证同一 (user/channel/agent) 元组在多次请求间稳定,是 `SessionMap` 能正确复用 agent session 的前提。第 [4] 步的数字分身改写是 JiuwenSwarm 区别于普通转发管道的关键:`IMConversationProcessor` 用 LLM 按群聊上下文(发言人、历史消息)对入站消息做改写,使 agent 拿到的是经过上下文规整的输入,而非裸文本。

### 3.2 附件处理与文档解析

IM 入站常携带附件(图片、文档、语音),接入层在归一化阶段统一处理:`persist_and_parse_documents` 负责文档解析(30MB/20-doc 上限),`normalize_chat_media_attachments` 负责图片校验(10MB/8-image 上限)。附件经校验后转为 agent 可消费的统一格式,作为消息上下文随 E2A 信封下发。这一层使 agent 无需关心飞书/钉钉等平台的附件 API 差异,只面向归一化后的附件对象编程。

### 3.3 心跳探活与 relay 回传

`GatewayHeartbeatService` 提供周期探活与 relay 回传:在配置的 active_hours 内周期性探测 agent 健康,并通过 relay_channel 把探活结果回传,使前端能在 agent 失联时及时感知。`HeartbeatConfig` 控制 active_hours 与 relay_channel,使接入层在低活跃时段降低探活频率,平衡及时性与开销。这一机制让 IM 渠道的长连接保持可用,避免因网络抖动导致会话假死。

### 3.4 渠道热插拔

`_apply_channel_config(app_gateway.py#L2002)` 实现"停旧建新"的渠道热插拔:收到新渠道配置→停止旧渠道(`BaseChannel.stop()` 并从 `RobotMessageRouter` 取消订阅)→释放旧句柄→按新 `ChannelType` 构造新 `BaseChannel`→`start()` 注册到总线→路由表更新。这一机制让运维侧可在不重启 gateway 进程的前提下,动态增删 IM 应用(如切换飞书自建应用与企业版),保证业务连续性。

### 3.3 渠道清单

| 类别 | 渠道 | ChannelType | 说明 |
| --- | --- | --- | --- |
| IM | 飞书 | FEISHU | 多应用/企业版,Webhook + 事件订阅 |
| IM | 钉钉 | DINGTALK | 钉钉会话路由编码 |
| IM | 企微 | WECOM | 企业微信 |
| IM | Telegram | TELEGRAM | Bot API |
| IM | Discord | DISCORD | Gateway Bot |
| IM | Slack | SLACK | Events API |
| IM | WhatsApp | WHATSAPP | Cloud API |
| IM | 微信 | WECHAT | 公众号/小程序 |
| IM | 小艺 | XIAOYI | 语音助手渠道 |
| 终端 | web | WEB | SPA 静态服务 + 反向代理 |
| 终端 | tui | TUI | 终端 UI |
| 终端 | desktop | DESKTOP | pywebview 桌面壳 |
| 协议 | acp | ACP | stdio 网关子命令 |
| 协议 | a2a | A2A | Agent-to-Agent 协议 |
| 协议 | ssh | SSH | SSH 接入 |

所有渠道均实现 `BaseChannel(base.py#L114)`,经 `RobotMessageRouter(base.py#L48)` 统一入站/出站,保证渠道间行为一致。

## 四、调用示例

### 4.1 启动多路径网关

```python
from jiuwenswarm.gateway.app_gateway import GatewayServer, GatewayServerConfig

config = GatewayServerConfig(
    listen_host="0.0.0.0", listen_port=8787,
    routes=[...],                       # 多路径,每条独立 channel_id 与 handler
    agent_server_url="ws://127.0.0.1:9002/e2a",
)
server = GatewayServer(config, router=bus)
# _run(app_gateway.py#L1426) 初始化所有渠道+心跳+cron
```

### 4.2 流式 E2A 发送与回推

```python
from jiuwenswarm.gateway.routing.agent_client import WebSocketAgentServerClient
from jiuwenswarm.gateway.routing.keys import RoutingKey, make_delivery_target

client = WebSocketAgentServerClient(url="ws://127.0.0.1:9002/e2a")
key = RoutingKey(user_id="u-1", channel_id="feishu", app_id="app-1",
                 agent_ref=AgentRef(mode="agent", id="jiuwen"), session_id="sess-1")
async for chunk in client.send_request_stream(envelope, request_id="req-1"):
    msg = build_reply(chunk, routing_key=key)
    bus.queue_robot_message(msg)                         # 入出站队列
target = make_delivery_target(channel_id="feishu", ...)  # keys.py#L314 工厂
target.send(msg)                                        # 渠道特定投递→平台 API
```

### 4.3 渠道热插拔

```python
# _apply_channel_config(app_gateway.py#L2002) 停旧建新
server._apply_channel_config(new_channel_config)
# 旧 IMChannel.stop() → 释放句柄 → 新 BaseChannel.start() → 路由表更新
```

### 4.4 数字分身群聊改写

```python
from jiuwenswarm.gateway.im_pipeline.im_inbound import IMInboundPipeline

pipeline = IMInboundPipeline(...)        # im_inbound.py#L470
# IMConversationProcessor(im_inbound.py#L139) 按群聊上下文 LLM 改写入站消息
rewritten = await pipeline.process(raw_message, conversation_context)
```

### 4.5 会话钩子收尾

```python
# GatewayHookHandler 在每轮交互后收尾(10s 超时不阻塞主流程)
# 钩子可用于:落库会话摘要、触发后续通知、清理临时资源
# handler.py#L16 注册钩子,IM 回推完成后由网关调用
```

### 4.6 附件处理

```python
# document_attachments.py 文档解析(30MB/20-doc)
# media_attachments.py 图片校验(10MB/8-image)
# 附件经校验后转为统一格式随 E2A 信封下发 agent
```

### 4.7 心跳探活配置

```python
# heartbeat.py#L60 HeartbeatConfig 控制 active_hours 与 relay_channel
# GatewayHeartbeatService(heartbeat.py#L102) 周期探活 + relay 回传
# 低活跃时段降低探活频率,IM 长连接保持可用,避免会话假死
```

## 五、业界对比

| 维度 | JiuwenSwarm | n8n | Dify | Coze |
| --- | --- | --- | --- | --- |
| IM 覆盖 | 9 IM + web/tui/desktop + acp/a2a/ssh | Webhook 触发,无原生 IM | 对话应用为主 | 多渠道发布 |
| 路由模型 | 5 维 RoutingKey + SessionMap 稳定映射 | 节点连线 | 对话 session | bot 路由 |
| 数字分身 | IMInboundPipeline LLM 群聊改写 | 不支持 | 不支持 | 不支持 |
| 热插拔 | _apply_channel_config 停旧建新 | 节点增删 | 不支持运行时 | 不支持运行时 |
| 协议统一 | E2A over WS + RobotMessageRouter 总线 | REST/Webhook | HTTP API | 平台协议 |
| 会话绑定 | SessionMap 稳定身份→agent session | 无 | 对话 session | bot 会话 |

JiuwenSwarm 的差异化在于"9 IM + 多终端 + 多协议"统一接入,并以 E2A 协议 + `RobotMessageRouter` 总线把异构渠道归一为一致消息流。相对 n8n 的工作流触发模型、Dify 的对话应用定位、Coze 的平台托管模式,本特性更偏"边缘接入运行时":它在接入侧就完成路由、会话绑定、数字分身改写、热插拔等横切能力,使后端 AgentServer 只需专注 agent 执行。其中数字分身群聊改写与渠道热插拔是竞品普遍缺失的能力。

## 六、小结

1. 多平台 IM 接入覆盖 9 个主流 IM 平台 + web/tui/desktop 终端 + acp/a2a/ssh 协议渠道,所有渠道实现 `BaseChannel` 经 `RobotMessageRouter` 统一入站/出站。
2. `GatewayServer` 是多路径 WS 网关,一个进程承载全部渠道,经 `WebSocketAgentServerClient` 以 E2A 协议连后端 AgentServer,实现"前端渠道多样"与"后端 Agent 唯一"解耦。
3. 入站→路由→Agent→回推全链路中,`RoutingKey` 5 维稳定键 + `SessionMap` 保证 agent session 复用,`make_delivery_target` 按渠道解析物理投递目标。
4. `IMInboundPipeline` 的 `IMConversationProcessor` 用 LLM 按群聊上下文改写入站消息,使 agent 拿到的是经上下文规整的输入,是区别于普通转发管道的关键能力。
5. `_apply_channel_config` 实现渠道热插拔(停旧建新),支持飞书多应用与企业版运行时切换,保证业务连续。
6. 相对竞品,本特性以"多 IM + 多终端 + 多协议统一接入 + E2A 总线 + 数字分身 + 热插拔"形成差异化,定位为具备编排能力的边缘运行时。
