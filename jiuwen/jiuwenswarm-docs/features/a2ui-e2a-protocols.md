# A2UI 与 E2A 协议

> 交叉引用: [01-项目概述](../01-project-overview.md) | [02-整体架构](../02-overall-architecture.md) | [05-server与cli](../05-server-and-cli-module.md) | [08-common与e2a](../08-common-e2a-and-security-module.md) | [特性索引](README.md)

## 一、能力概述

JiuwenSwarm 在"协议层"与"表示层"分别引入了两套相互正交的协议,以解耦"外部如何统一调用 Agent"与"Agent 如何输出富交互界面"这两个原本缠绕在一起的问题。

**E2A(External-to-Agent)统一信封协议**位于协议层。它的目标是让 ACP(Agent Client Protocol)、A2A(Agent-to-Agent)以及原生 WebSocket 三类异构入口共享同一份请求/响应数据形状。任何外部请求到达 Gateway 后,首先被适配为 `E2AEnvelope` 并附带 `E2AProvenance` 标注来源协议,随后在系统内部以统一的 `AgentRequest` 形态流转,响应再以 `E2AResponse` 编码回 wire 格式下发。E2A 的核心价值是"来源可追溯 + 兜底容错":既能回溯每个响应的原始协议,又能在规范化失败时仍以 E2A 形状继续流转而不丢上下文。

**A2UI(Agent-to-UI)富前端渲染协议(v0.8)**位于表示层。它解决的是 Agent 输出如何被前端渲染成结构化交互界面的问题。Agent 在文本流中嵌入 tagged block 或 JSON 片段,声明 `beginRendering`、`surfaceUpdate`、`dataModelUpdate`、`deleteSurface` 等动作,前端据此创建/更新/销毁界面组件。当渲染目标不支持富交互(如纯文本渠道)时,A2UI 可降级为纯文本通道。

两者正交:E2A 不关心界面长什么样,A2UI 不关心请求从哪个协议进来。一个 A2A 请求经过 E2A 适配后进入 Agent,Agent 的 A2UI 输出再经由 E2A wire 下发——协议层负责"进得来、出得去",表示层负责"看得见、可交互"。这种正交使得新增一种入口协议(如未来接入 MCP)无需改动 A2UI,新增一种前端组件也无需改动 E2A。

## 二、关键类与函数

| 类/函数 | 文件位置 | 说明 |
| --- | --- | --- |
| A2UIProtocolSpec | [protocol.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/runtime/a2ui/protocol.py#L72) | A2UI v0.8 适配器:schema_manager/build_prompt/validate 三入口 |
| parse_a2ui_response | [parser.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/runtime/a2ui/parser.py#L92) | 解析 A2UI 响应:JSONL/raw JSON/tagged block 三种格式 |
| A2UIConfig | [config.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/runtime/a2ui/config.py#L16) | A2UI 配置:enabled/protocol_version/stream_validation |
| validate_a2ui_response | [validator.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/runtime/a2ui/validator.py#L283) | 语义校验:组件引用/dataModel 路径/模板运行时 |
| E2AEnvelope | [models.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/e2a/models.py#L87) | E2A 统一信封:protocol_version/provenance/request_id/method/params |
| E2AResponse | [models.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/e2a/models.py#L164) | 统一响应:response_id/sequence/is_final/response_kind/body |
| E2AProvenance | [models.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/e2a/models.py#L44) | 出处记录:source_protocol(e2a/acp/a2a)/converter/converted_at |
| e2a_to_agent_request | [agent_compat.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/e2a/agent_compat.py#L29) | 规范化 E2AEnvelope→AgentRequest |
| envelope_from_acp_jsonrpc | [adapters.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/e2a/adapters.py#L42) | ACP JSON-RPC→E2AEnvelope,provenance 标 acp |
| envelope_from_a2a_send_message | [adapters.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/e2a/adapters.py#L80) | A2A SendMessage→E2AEnvelope,provenance 标 a2a |
| message_to_e2a_or_fallback | [gateway_normalize.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/e2a/gateway_normalize.py#L166) | Message→E2A;失败则 build_fallback_e2a 携带 legacy 快照 |
| encode_agent_chunk_for_wire | [wire_codec.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/e2a/wire_codec.py#L281) | AgentResponseChunk→E2AResponse wire dict(流式) |
| parse_agent_server_wire_chunk | [wire_codec.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/e2a/wire_codec.py#L171) | WS JSON→AgentResponseChunk,支持 E2A 与 legacy 兜底 |
| build_server_push_wire | [wire.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/gateway_push/wire.py#L21) | 主动推送 wire,标记 _jiuwenswarm_server_push |
| build_acp_initialize_result | [protocol.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/e2a/acp/protocol.py#L8) | ACP initialize 响应:protocolVersion/agentInfo/capabilities |

## 三、实现机制

### 3.1 E2A 统一信封流转

E2A 是全系统的"普通话",任何外部请求进入后都先被适配为 `E2AEnvelope`,响应再编码回 wire 格式发出。完整链路如下:

```text
[1] 外部入口:ACP JSON-RPC / A2A SendMessage / 原生 WS 请求到达 Gateway
[2] 适配:envelope_from_acp_jsonrpc / envelope_from_a2a_send_message → E2AEnvelope
       └─ E2AProvenance 标 source_protocol(acp/a2a)/converter/converted_at
[3] 规范化:e2a_to_agent_request(env) → AgentRequest
[4] 执行:AgentServer 按 method(chat/send、swarmflow/reply…)分发
       └─ 产出 AgentResponse 或流式 AgentResponseChunk
[5] 响应分类:封装为 E2AResponse,response_kind 取 13 种枚举
[6] 编码:encode_agent_chunk_for_wire → wire dict,经 WS 下发
[7] 兜底:规范化失败 → message_to_e2a_or_fallback → build_fallback_e2a
       └─ channel_context 携带 legacy 快照,不丢上下文
```

第 [2] 步的 `E2AProvenance` 是来源追溯的关键:它记录原始协议(`source_protocol` 取 e2a/acp/a2a)、转换器(`converter`)与转换时间(`converted_at`),使得任何响应都能回溯到原始入口。第 [7] 步的兜底是 E2A 容错的关键:`message_to_e2a_or_fallback` 在规范化失败时不直接报错,而是走 `build_fallback_e2a` 仍以 E2A 形状继续流转,并在 `channel_context` 中携带 legacy 快照,保证不丢上下文。

`E2AResponse.response_kind` 的 13 种枚举覆盖了流式、终态、错误、协议适配与会话控制等场景,对应不同下游协议的渲染方式,使同一份内部响应能被 ACP/A2A/原生各自正确呈现。

### 3.2 A2UI 富前端渲染

A2UI v0.8 通过 `A2UIProtocolSpec` 适配器接入,Agent 输出经"构建提示→解析→校验"三步处理:

1. **构建提示**:`A2UIProtocolSpec.build_prompt` 在系统提示中注入 A2UI 协议说明与可用组件目录,引导 Agent 输出结构化动作。
2. **解析**:`parse_a2ui_response` 解析 Agent 文本流中的 A2UI 片段,支持三种格式——JSONL(逐行 JSON)、raw JSON(整块 JSON)、tagged block(标签包裹块),解析结果为 `A2UIResponsePart` 列表。
3. **校验**:`validate_a2ui_response` 做语义校验:组件引用是否存在、dataModel 路径是否合法(`_normalize_data_path`)、模板运行时语义(`_validate_template_runtime_semantics`)、图片运行时语义(`_validate_image_runtime_semantics`)。校验通过后前端按动作渲染。

前端可消费的 A2UI 动作:

| 动作 | 语义 | 前端行为 |
| --- | --- | --- |
| beginRendering | 开始一次渲染会话 | 创建渲染上下文 |
| surfaceUpdate | 更新界面组件 | 增/改组件树节点 |
| dataModelUpdate | 更新数据模型 | 刷新组件绑定数据 |
| deleteSurface | 销毁界面组件 | 移除组件树节点 |

### 3.3 A2UI 降级为纯文本通道

当渲染目标不支持富交互(如纯文本 IM 渠道、CLI 通道),A2UI 通过 `format_for_text_channel` 把组件动作降级为可读的纯文本摘要,保证 Agent 输出在不支持富前端的渠道仍有可消费的语义。这使得同一份 Agent 输出在富前端渲染为交互界面,在纯文本渠道渲染为结构化摘要,无需 Agent 区分渠道。

### 3.4 主动推送的 wire 编码

AgentServer 需要主动下行(如 cron 触发结果、异步完成通知)时,`build_server_push_wire` 把消息编码为 E2A wire dict 并标记 `_jiuwenswarm_server_push`,使接收侧能区分这是服务端主动推送而非请求响应,从而正确路由。这是 E2A 统一信封对"推送"语义的覆盖:同一套 wire 格式承载请求、响应、推送、错误四种语义。

### 3.5 两协议对比

| 维度 | A2UI | E2A |
| --- | --- | --- |
| 全称 | Agent-to-UI | External-to-Agent |
| 方向 | Agent→前端(表示层) | 外部↔AgentServer(协议层) |
| 载体 | 文本流中的 tagged block/JSON | E2AEnvelope/E2AResponse wire dict |
| 核心问题 | Agent 如何输出富交互界面 | 外部如何统一调用 Agent |
| 版本 | v0.8 | 随 common 版本演进 |
| 降级 | 降级为纯文本通道 | 降级为 legacy 快照兜底 |

## 四、调用示例

### 4.1 A2A 入口经 E2A 适配触发 Agent

```python
# 1. A2A 入口适配为 E2A 信封(来源可追溯)
from jiuwenswarm.common.e2a.adapters import envelope_from_a2a_send_message
envelope = envelope_from_a2a_send_message(a2a_request)
# envelope.provenance.source_protocol == "a2a"

# 2. 规范化为 AgentRequest 并交给 AgentServer 执行
from jiuwenswarm.common.e2a.agent_compat import e2a_to_agent_request
agent_req = e2a_to_agent_request(envelope)

# 3. AgentServer 按 method 分发,产出 chunk 流
#    AgentServer 用 encode_agent_chunk_for_wire 编码后经 WS 下发
```

### 4.2 接收侧解析 wire chunk 并提取 A2UI

```python
# 4. 接收侧解析 wire chunk(支持 E2A 与 legacy 兜底)
from jiuwenswarm.common.e2a.wire_codec import parse_agent_server_wire_chunk
chunk = parse_agent_server_wire_chunk(ws_json)

# 5. Agent 输出中的 A2UI 片段被解析与校验
from jiuwenswarm.server.runtime.a2ui.parser import parse_a2ui_response
from jiuwenswarm.server.runtime.a2ui.validator import validate_a2ui_response
parts = parse_a2ui_response(chunk.content)
validate_a2ui_response(catalog, parts_to_messages)
# 前端据 beginRendering/surfaceUpdate 渲染富交互界面
```

### 4.3 AgentServer 主动推送

```python
from jiuwenswarm.server.gateway_push.wire import build_server_push_wire
wire = build_server_push_wire({"method": "cron/result", "params": {...}})
# wire 含 _jiuwenswarm_server_push 标记,接收侧据此路由为推送
```

### 4.4 ACP 入口握手

```python
from jiuwenswarm.common.e2a.acp.protocol import build_acp_initialize_result
result = build_acp_initialize_result()
# 返回 protocolVersion/agentInfo/capabilities/authMethods,完成 ACP 握手
```

## 五、业界对比

| 维度 | JiuwenSwarm | MCP(Model Context Protocol) | A2A(Google) | ACP(Agent Client Protocol) |
| --- | --- | --- | --- | --- |
| 协议统一 | E2A 统一信封兼容 ACP/A2A/原生 | 仅定义模型上下文,不统一调用信封 | 定义 Agent 间消息,不覆盖前端 | 定义客户端↔Agent,不覆盖 Agent 间 |
| 来源追溯 | E2AProvenance 标 source_protocol | 无 | 仅 A2A 来源 | 仅 ACP 来源 |
| 富前端 | A2UI v0.8 tagged block+组件目录 | 无(纯工具调用) | 无(消息文本) | 无(纯会话) |
| 多协议适配 | adapters 双向适配 ACP/A2A | 单一协议 | 单一协议 | 单一协议 |
| 降级能力 | A2UI 降级纯文本通道 | N/A | N/A | N/A |
| 推送语义 | build_server_push_wire 统一承载 | 无 | 无 | 无 |

JiuwenSwarm 的差异化在于"双协议正交":E2A 在协议层把多入口归一,来源全程可追溯;A2UI 在表示层让 Agent 能输出结构化富交互界面,且能在不支持富前端的渠道自动降级。两者叠加,使同一份 Agent 逻辑既能被 ACP 客户端、A2A Agent、原生 CLI 统一调用,又能在支持富前端的前端渲染结构化界面。

## 六、小结

1. A2UI 与 E2A 是 JiuwenSwarm 协议栈的两块基石,分别治理表示层(Agent→前端富交互)与协议层(外部↔AgentServer 统一调用),两者正交、互不耦合。
2. E2A 以 `E2AEnvelope`/`E2AResponse`/`E2AProvenance` 三件套实现"统一信封+来源追溯+兜底容错",把 ACP/A2A/原生三类入口收敛为一种内部语言。
3. A2UI v0.8 以 `A2UIProtocolSpec`/`parse_a2ui_response`/`validate_a2ui_response` 三件套实现"富交互输出+语义校验+纯文本降级",让 Agent 的界面能力不依赖具体前端实现。
4. wire 编解码(`encode_agent_chunk_for_wire`/`parse_agent_server_wire_chunk`)是两协议的衔接点:E2A wire 承载请求/响应/推送/错误四种语义,A2UI 片段作为内容嵌于其中流转。
5. `build_server_push_wire` 以 `_jiuwenswarm_server_push` 标记统一承载主动推送语义,使 cron 结果与异步通知复用同一套 wire 格式。
6. 相对 MCP/A2A/ACP 等单一协议方案,本特性以"E2A 多协议归一 + A2UI 富前端 + 双向降级"形成差异化,支撑多协议接入与多终端渲染场景下的一致性与可演进性。
