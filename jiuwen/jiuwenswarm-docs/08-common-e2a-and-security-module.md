# 08 common 与 e2a 与 security 模块（协议中枢、数据契约与安全）

> 交叉引用: [01-项目概述](../01-project-overview.md) | [02-整体架构](../02-overall-architecture.md) | [04-gateway与channels](../04-gateway-and-channels-module.md) | [05-server与cli](../05-server-and-cli-module.md)

## 一、能力概述

common 模块是 JiuwenSwarm 跨进程共享的协议与配置中枢，承担"统一语言、统一契约、统一配置"的职责。它的核心是 `e2a/` 子包定义的 E2A（External-to-Agent）统一信封模型及对应的 wire 编解码、ACP/A2A 协议适配；`schema/` 子包定义 `AgentRequest`/`AgentResponse`/`AgentResponseChunk`/`Message`/`ReqMethod` 等核心数据契约；`security/` 子包提供 WebSocket Origin 校验与 `CryptoProvider` 加密协议。这三者共同构成系统内不同进程、不同协议、不同来源请求的"普通话"。

除协议层外，common 还承载若干横切关注点：`mode_matrix` 负责模式组合解析（Web 组合分支优先，其余走 legacy resolver），`reasoning_injector` 按 reasoning_level 与 provider_kind 注入思考参数，`hooks_config` 提供 17 事件 + HookMatcher 的配置加载，`config.py` 负责 `config.yaml` 的解析（缓存 + 重试 + 环境变量替换），`tool_ownership` 区分无状态共享工具与 agent 私有工具，`cron_team_completion` 维护 leader final/workflow/open_tasks 状态机以判断团队轮次是否结束。

E2A 的关键设计是"来源可追溯 + 兜底容错"。每个进入系统的外部请求都被适配为 `E2AEnvelope`，并附带 `E2AProvenance` 标注来源协议（e2a/acp/a2a）、转换器与转换时间，使得任何响应都能回溯到原始协议；当规范化失败时，`gateway_normalize` 不直接报错，而是走 `build_fallback_e2a` 仍以 E2A 形状继续流转，并在 `channel_context` 中携带 legacy 快照，保证兼容性不丢上下文。

整体来看，common 把"协议、数据、配置、安全、横切策略"压在一处，是因为它们都是跨进程必须严格一致的语义边界：只要这一层稳定，上层 Gateway/AgentServer/Swarm 就可以各自演化而不必担心对方的数据形状。这也意味着 common 的变更需要更高的兼容性约束，所有改动都需考虑 ACP/A2A/legacy 三类来源的兼容。

## 二、关键类与函数

| 类/函数 | 文件位置 | 说明 |
| --- | --- | --- |
| E2AEnvelope | [models.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/e2a/models.py#L87) | E2A 统一信封：protocol_version/provenance/request_id/method/params/is_stream，兼容 ACP/A2A |
| E2AResponse | [models.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/e2a/models.py#L164) | 统一响应：response_id/sequence/is_final/status/response_kind/body |
| E2AProvenance | [models.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/e2a/models.py#L44) | 出处记录：source_protocol(e2a/acp/a2a)/converter/converted_at |
| e2a_to_agent_request | [agent_compat.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/e2a/agent_compat.py#L29) | 规范化 E2AEnvelope→AgentRequest |
| envelope_from_acp_jsonrpc | [adapters.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/e2a/adapters.py#L42) | ACP JSON-RPC→E2AEnvelope，provenance 标 acp |
| envelope_from_a2a_send_message | [adapters.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/e2a/adapters.py#L80) | A2A SendMessage→E2AEnvelope，provenance 标 a2a |
| message_to_e2a_or_fallback | [gateway_normalize.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/e2a/gateway_normalize.py#L166) | Message→E2A；失败则 build_fallback_e2a 携带 legacy 快照 |
| build_fallback_e2a | [gateway_normalize.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/e2a/gateway_normalize.py#L93) | 规范化失败仍发 E2A 形状，channel_context 携带 legacy 快照 |
| encode_agent_chunk_for_wire | [wire_codec.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/e2a/wire_codec.py) | AgentResponseChunk→E2AResponse wire dict（流式） |
| parse_agent_server_wire_chunk | [wire_codec.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/e2a/wire_codec.py#L171) | WS JSON→AgentResponseChunk，支持 E2A 与 legacy 兜底 |
| build_acp_initialize_result | [protocol.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/e2a/acp/protocol.py#L8) | ACP initialize 响应：protocolVersion/agentInfo/capabilities/authMethods |
| AgentRequest/AgentResponse/AgentResponseChunk | [agent.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/schema/agent.py) | 核心数据契约 |
| Message/ReqMethod | [message.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/schema/message.py) | 消息模型/方法枚举 |
| ChatSendParams | [chat_send.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/schema/chat_send.py) | 请求参数 |
| SwarmflowReplyParams | [swarmflow_reply.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/schema/swarmflow_reply.py) | 请求参数 |
| is_allowed_browser_origin | [ws_origin.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/security/ws_origin.py#L30) | 校验浏览器 Origin 白名单（环境变量） |
| CryptoProvider | [base_crypto.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/security/base_crypto.py) | 加密 Provider 协议 |
| resolve_request_mode | [mode_matrix.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/mode_matrix.py#L152) | 解析请求运行模式：Web 组合分支优先，其余 legacy_resolver |
| ResolvedMode | [mode_matrix.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/mode_matrix.py#L66) | 完整运行模式视图：manager_mode/sub_mode/canonical_mode/is_plan/is_team |
| inject_reasoning_params | [reasoning_injector.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/reasoning_injector.py#L79) | 按 reasoning_level+provider_kind 注入 deepseek_official/dashscope_bailian 思考参数 |
| HooksConfig | [hooks_config.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/hooks_config.py#L127) | hooks 配置：events dict+HookMatcher，disable_all_hooks，match(event,query) |
| load_hooks_config | [hooks_config.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/hooks_config.py#L165) | 从 config.yaml hooks 段加载 |
| get_config | [config.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/config.py) | config.yaml 解析（缓存+重试+环境变量替换） |
| tool_ownership | [tool_ownership.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/tool_ownership.py) | stateless 共享 vs agent-owned，register_tool/unregister_tool |
| cron_team_completion | [cron_team_completion.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/cron_team_completion.py) | leader final/workflow/open_tasks 状态机，判断团队轮次结束 |

## 三、实现机制

### 1. E2A 统一信封流转

E2A 是全系统的"普通话"，任何外部请求进入后都先被适配为 `E2AEnvelope`，响应再编码回 wire 格式发出。完整链路如下：

1. **外部入口**：ACP JSON-RPC、A2A SendMessage 或原生请求到达 Gateway。
2. **适配**：`envelope_from_acp_jsonrpc` 或 `envelope_from_a2a_send_message` 把请求转为 `E2AEnvelope`，并在 `E2AProvenance` 中标注 `source_protocol`（acp/a2a）、`converter`、`converted_at`，来源可追溯。
3. **规范化**：`e2a_to_agent_request` 把 `E2AEnvelope` 规范化为 `AgentRequest`，交给 AgentServer 执行。
4. **执行**：Agent 按 `method`（如 `chat/send`、`swarmflow/reply`）分发，产生 `AgentResponse` 或流式 `AgentResponseChunk`。
5. **响应分类**：响应被封装为 `E2AResponse`，其 `response_kind` 取自 13 种枚举，对应不同下游协议的渲染方式。
6. **编码**：`encode_agent_chunk_for_wire` 把 `AgentResponseChunk` 编码为 wire dict，经 WS 下发；接收侧用 `parse_agent_server_wire_chunk` 反向解析，支持 E2A 与 legacy 兜底。
7. **兜底**：当规范化失败，`message_to_e2a_or_fallback` 不直接报错，而是走 `build_fallback_e2a` 仍以 E2A 形状继续流转，并在 `channel_context` 中携带 legacy 快照，保证不丢上下文。

`E2AResponse.response_kind` 的 13 种枚举覆盖了流式、终态、错误、协议适配与会话控制等场景：

- `e2a.chunk` / `e2a.complete` / `e2a.error`：E2A 原生的流式分片、终态与错误。
- `acp.session_update` / `acp.prompt_result`：ACP 协议的会话更新与提示结果。
- `a2a.stream_event`：A2A 协议的流式事件。
- `cron`：定时任务触发的响应。
- `plan.approval_required`：规划流程需要人工审批时返回。

下游根据 `response_kind` 选择把响应渲染为 ACP JSON-RPC、A2A 事件或原生 WS 帧，从而实现"一次执行、多协议下发"。ACP 协议握手由 `build_acp_initialize_result` 生成：返回 `protocolVersion`、`agentInfo`、`capabilities`、`authMethods`，使 ACP 客户端能完成标准 initialize 流程。

### 2. 模式系统

`resolve_request_mode` 负责解析请求运行模式，采用"Web 组合分支优先"策略：先尝试从请求的 agent 与 work_mode 组合解析出 canonical mode，命中则直接返回；未命中再回退到 `legacy_resolver`。最终产出 `ResolvedMode`，包含 `manager_mode`、`sub_mode`、`canonical_mode`、`is_plan`、`is_team` 等完整视图，供后续路由与编排使用。`is_plan`/`is_team` 决定是否进入规划模式或团队协作模式。这种"组合分支优先 + legacy 兜底"的策略保证新式 Web 请求走新链路、旧式请求走兼容链路，二者在同一 `ResolvedMode` 视图下统一。

### 3. 安全机制

安全层由三部分组成：

- **WS Origin 校验**：`is_allowed_browser_origin` 依据环境变量配置的 Origin 白名单校验浏览器来源，防止跨站 WebSocket 劫持。
- **CryptoProvider 协议**：定义加密 Provider 协议，具体实现可插拔，统一加解密入口。
- **工具归属**：`tool_ownership` 区分无状态共享工具与 agent 私有工具；模块级单例工具被标记为 `mark_stateless`，可在多 agent 间共享而不串状态；`register_tool`/`unregister_tool` 管理生命周期。被标记为 stateless 的工具在多实例/多 agent 调度时无需拷贝状态，显著降低开销。

### 4. 团队轮次完成判断

`cron_team_completion` 维护一个 leader final / workflow / open_tasks 状态机：leader 标记本轮为最终态、workflow 到达终点、且 open_tasks 归零时，判定团队轮次结束，触发下一轮调度或收尾。它把"团队是否完成"这一分布式判断收敛为可计算的状态机，避免依赖人工确认或外部轮询。

## 四、调用示例

ACP JSON-RPC 适配为 E2AEnvelope：

```python
from jiuwenswarm.common.e2a.adapters import envelope_from_acp_jsonrpc

envelope = envelope_from_acp_jsonrpc(
    jsonrpc={"jsonrpc": "2.0", "method": "session/new", "params": {...}, "id": 1}
)
assert envelope.provenance.source_protocol == "acp"
```

E2AEnvelope 规范化为 AgentRequest：

```python
from jiuwenswarm.common.e2a.agent_compat import e2a_to_agent_request

agent_request = e2a_to_agent_request(envelope)
```

流式 chunk 编解码：

```python
from jiuwenswarm.common.e2a.wire_codec import (
    encode_agent_chunk_for_wire,
    parse_agent_server_wire_chunk,
)

wire = encode_agent_chunk_for_wire(chunk)              # AgentResponseChunk -> dict
restored = parse_agent_server_wire_chunk(wire_json)     # dict -> AgentResponseChunk（含 legacy 兜底）
```

ACP initialize 响应构建：

```python
from jiuwenswarm.common.e2a.acp.protocol import build_acp_initialize_result

result = build_acp_initialize_result(agent_info={"name": "jiuwen", "version": "1.0"})
# result -> {protocolVersion, agentInfo, capabilities, authMethods}
```

模式解析：

```python
from jiuwenswarm.common.mode_matrix import resolve_request_mode

mode = resolve_request_mode(request, legacy_resolver=default_resolver)
if mode.is_plan:
    enter_plan_flow(mode)
elif mode.is_team:
    enter_team_flow(mode)
```

reasoning 参数注入：

```python
from jiuwenswarm.common.reasoning_injector import inject_reasoning_params

params = inject_reasoning_params(
    base_params={"temperature": 0.7},
    reasoning_level="medium",
    provider_kind="deepseek_official",
)
```

WS Origin 校验：

```python
from jiuwenswarm.common.security.ws_origin import is_allowed_browser_origin

if not is_allowed_browser_origin(origin="https://app.example.com"):
    close_ws(code=1008, reason="origin not allowed")
```

工具归属管理（无状态共享 vs agent 私有）：

```python
from jiuwenswarm.common.tool_ownership import register_tool, mark_stateless, unregister_tool

register_tool("web_search", owner="agent-1")
mark_stateless("web_search")          # 标记为无状态共享，多 agent 可共用
unregister_tool("web_search", owner="agent-1")
```

团队轮次完成判断：

```python
from jiuwenswarm.common.cron_team_completion import is_team_round_complete

if is_team_round_complete(team_state):
    advance_next_round(team_state)
```

config.yaml 加载（缓存 + 重试 + 环境变量替换）：

```python
from jiuwenswarm.common.config import get_config

cfg = get_config()
hooks = cfg.get("hooks", {})
```

## 五、业界对比

| 能力维度 | JiuwenSwarm | MCP | A2A（Google） | ACP |
| --- | --- | --- | --- | --- |
| 协议统一 | E2A 统一信封，多协议适配 | 模型上下文协议 | Agent-to-Agent 协议 | Agent Client Protocol |
| 来源追溯 | E2AProvenance 标 source_protocol | 无显式来源 | 无显式来源 | 无显式来源 |
| 多协议适配 | ACP/A2A/原生统一入口 | 仅 MCP | 仅 A2A | 仅 ACP |
| 兜底容错 | build_fallback_e2a + legacy 快照 | 无 | 无 | 无 |
| 响应分类 | 13 种 response_kind | 无显式分类 | 无 | 无 |
| 流式支持 | E2AResponse.sequence 流式 | 支持 | 支持 | 支持 |
| 安全 | WS Origin 白名单 + CryptoProvider | 无内置 | 无内置 | 无内置 |
| 工具归属 | stateless 共享 vs agent-owned | 无 | 无 | 无 |
| 模式解析 | ResolvedMode is_plan/is_team | 无 | 无 | 无 |
| 配置加载 | config.yaml 缓存+重试+环境变量 | 各自配置 | 各自配置 | 各自配置 |

## 六、小结

1. common 是跨进程协议与配置中枢，E2A 统一信封让 ACP/A2A/原生请求使用同一种"普通话"。
2. `E2AProvenance` 实现来源追溯，使任何响应都能回溯到原始协议，便于调试与审计。
3. `gateway_normalize` 的 `build_fallback_e2a` 兜底策略保证规范化失败也不丢上下文，最大化兼容性。
4. 13 种 `response_kind` 让一次执行可多协议下发，下游按 kind 渲染为 ACP/A2A/原生 WS。
5. `mode_matrix`、`reasoning_injector`、`hooks_config`、`tool_ownership`、`cron_team_completion` 等横切模块覆盖运行模式、思考注入、事件匹配、工具归属与团队轮次判断。
6. 相比 MCP/A2A/ACP 的单一协议，JiuwenSwarm 以 E2A + provenance + 兜底容错实现"多协议统一 + 来源追溯 + 容错流转"三位一体。
