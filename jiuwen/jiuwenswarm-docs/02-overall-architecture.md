# 02 整体架构

> 交叉引用: [01-项目概述](01-project-overview.md) | [03-agents与swarm](03-agents-and-swarm-module.md) | [04-gateway与channels](04-gateway-and-channels-module.md) | [05-server与cli](05-server-and-cli-module.md)

## 一、分层架构

JiuwenSwarm 采用「**接入层 → 协议层 → 运行时层 → 能力层 → 引擎层 → 基础设施层**」六层架构。上层依赖下层,引擎层(openjiuwen)提供通用 Agent 框架,本仓库在此基础上构建应用与群体协作。

```
┌─────────────────────────────────────────────────────────────────┐
│ 接入层    │ channels/(web/tui/desktop/acp) + gateway/channel_manager │  IM 平台 + 终端 + 协议渠道
├─────────────────────────────────────────────────────────────────┤
│ 协议层    │ common/e2a (E2A 信封) + common/schema + A2UI + ACP/A2A    │  统一信封 + 富前端协议
├─────────────────────────────────────────────────────────────────┤
│ 网关层    │ gateway/(routing/cron/heartbeat/hooks/im_pipeline)        │  路由 + 调度 + 钩子 + IM 管道
├─────────────────────────────────────────────────────────────────┤
│ 运行时层  │ server/(agent_ws_server/runtime/hooks/sandbox/gateway_push)│  WS 服务端 + Agent 生命周期
├─────────────────────────────────────────────────────────────────┤
│ 能力层    │ agents/(swarm 装配 + harness 能力组件 + team 运行时)       │  声明式团队 + Rails/Tools
├─────────────────────────────────────────────────────────────────┤
│ 引擎层    │ openjiuwen(agent-core):DeepAgent/Rails/Manifest/Runner     │  通用 Agent 框架(外部依赖)
├─────────────────────────────────────────────────────────────────┤
│ 基础设施层│ symphony(知识引擎) + extensions(扩展) + jiuwenbox(沙箱)   │  代码知识 + 插件 + 隔离
│           │ + instance_manager(多实例) + common(配置/安全/模式)        │
└─────────────────────────────────────────────────────────────────┘
```

### 进程拓扑(拆分布局)

`jiuwenswarm-start` / `jiuwenswarm-app` 启动后形成多进程拓扑:

```
                    ┌─────────────────── jiuwenswarm-start (start_services.py) ───────────────────┐
                    │   多实例管理:端口分配 base+index*1000、InstanceLock、PID 文件              │
                    └───────────────────────────┬─────────────────────────────────────────────────┘
                                                  │ subprocess.Popen
                       ┌──────────────────────────┴───────────────────────────┐
                       ▼                                                       ▼
        ┌──── jiuwenswarm-app (app.py: 双进程编排) ────┐         ┌──── jiuwenswarm-web (app_web.py) ────┐
        │  AgentServer 子进程  +  Gateway 子进程      │         │  SPA 静态服务 + HTTP/WS 反向代理      │
        └───────────┬───────────────────┬────────────┘         └──────────────────────────────────────┘
                    │                   │
                    ▼                   ▼
   ┌──── jiuwenswarm-agentserver ────┐  ┌──── jiuwenswarm-gateway ────────────────────────────┐
   │ AgentWebSocketServer (单例)      │  │ GatewayServer (多路径 WS 网关)                      │
   │ AgentManager + AgentWarmPool     │◄─┤ RobotMessageRouter + AgentServerClient(E2A over WS) │
   │ E2A 帧解析 → 分发 → 流式回推    │  │ channel_manager: 9 IM 平台 + web/tui/acp/a2a/ssh    │
   │ hooks 执行器 + A2UI + sandbox    │  │ cron 调度器 + heartbeat + im_pipeline + hooks       │
   └──────────────┬───────────────────┘  └────────────────────────────────────────────────────┘
                  │ openjiuwen DeepAgent/Runner/TeamRuntime
                  ▼
   ┌──── 能力层 agents/ ────┐  ┌──── symphony(离线 Score + 在线规划) ────┐  ┌─ jiuwenbox(沙箱) ─┐
   │ swarm 装配 + harness   │  │ fingerprint → graph → indexing →        │  │ bwrap+landlock+   │
   │ Rails/Tools/SubAgents  │  │ retrieval → experience → evolution      │  │ seccomp+cgroup+net│
   │ TeamManager + 分布式   │  └─────────────────────────────────────────┘  └───────────────────┘
   └────────────────────────┘
```

关键点:Gateway 与 AgentServer 经 **E2A 协议**通过 WebSocket 双向通信;AgentServer 内的 DeepAgent 由 openjiuwen 提供,agents/ 只做声明式装配;分布式 Swarm 模式下 Teammate 经 pyzmq transport 跨进程跨机通信。

## 二、核心设计模式

### 模式 1:声明式 Spec 装配(Swarm)

Swarm 模式不预构造 DeepAgent,而是把 `config.yaml` + 请求环境翻译成声明式 `RailSpec`/`BuiltinToolSpec`/`SubAgentSpec`,经 openjiuwen `setup_agent → spec.build(context=SwarmBuildContext)` 由 provider 工厂构造为运行对象。成员能力以 provider 名称(`swarm.*`/`core.*`)引用,装配与实现解耦。入口 [enrich_team_spec_for_swarm](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/assembly.py#L56)。

### 模式 2:Card/Config 分离(param vs context)

能力元素的设定分两类:属性值(config.yaml 设定,换请求不变)烘焙进 `RailSpec.params`;环境值(随请求/会话/成员变化)挂在 [SwarmBuildContext](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/context.py#L24)。前者可序列化自洽,后者保持纯环境,跨序列化边界(spawn/分布式/冷恢复)只靠 seed + 接收侧本地 config 重建。详见 agents/swarm/DESIGN.md。

### 模式 3:统一信封(E2A)

多来源请求(原生 E2A、ACP JSON-RPC、A2A SendMessage)经 [adapters](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/e2a/adapters.py#L42) 统一为 [E2AEnvelope](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/e2a/models.py#L87),AgentServer 无需关心外部协议差异;响应经 [wire_codec](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/e2a/wire_codec.py) 编码为 wire JSON 回传。provenance 字段追溯每条消息来源(e2a/acp/a2a)。

### 模式 4:5 维路由键 + 会话绑定

Gateway 用 [RoutingKey](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/routing/keys.py#L34)(user_id, channel_id, app_id, agent_ref, session_id)做消息路由,[SessionMap](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/routing/session_map.py#L46) 维护稳定身份→轮换 agent session_id 映射(支持 PER_CHAT_BOT / PER_CHAT_BOT_USER 作用域),确保同一用户同一会话始终路由到同一 Agent 会话。

### 模式 5:单例 + 预热池

[AgentWebSocketServer](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/agent_ws_server.py#L859) 是进程内单例(get_instance 工厂),[AgentManager](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/runtime/agent_manager.py#L106) 按 (channel, mode, sub_mode, project_dir) 缓存 Agent 实例,[AgentWarmPool](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/runtime/agent_warm_pool.py#L115) 预热就绪 DeepAgent,前台并发信号量 + 后台冷却降低首响应延迟。

### 模式 6:堆式异步事件队列(cron)

[CronSchedulerService](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/cron/scheduler.py#L249) 用堆式事件队列实现 wake/push/push_update 三类事件调度,支持 5-field 与 7-field Quartz cron,文件 mtime 轮询感知外部变更,崩溃恢复保护,支持 team streaming / unary / proactive.tick 三种执行形态。

### 模式 7:知识图谱 Score + 动态叠加层演化

Symphony 离线构建 Score(指纹→图→索引),在线 [plan_from_score](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/orchestration/service.py#L25) 加载静态 Score + 动态 overlay 用 fast/beam 策略规划;运行时 [record_plan_outcome](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/evolution/service.py#L94) 记录成败 → 重建 overlay 边权重,使知识图谱「越用越准」。

### 模式 8:扩展 + 钩子事件

[ExtensionRegistry](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/extensions/registry.py#L15) 单例承载 RPC handler 与回调,[ExtensionLoader](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/extensions/loader.py#L32) 从扩展目录发现 `extension.yaml` 自动装依赖并 import。钩子分 [GatewayHookEvents](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/extensions/hook_event.py#L4) 与 [AgentServerHookEvents](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/extensions/hook_event.py#L17),配合四类 Context 让扩展原地修改会话参数、注入记忆块。

### 模式 9:纵深防御沙箱(jiuwenbox)

五层互补隔离:bwrap(命名空间+bind mount+die-with-parent)→ Landlock(路径 ACL)→ seccomp-bpf(syscall 过滤)→ cgroup v2(资源限额)→ netns+iptables(网络管控)。任一层被绕过,后续层仍限制爆炸半径。

### 模式 10:多实例隔离 + 端口自动分配

[instance_manager](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/instance_manager/config.py) 用 `base + index*1000` 算法分配端口(BASE_PORTS:agent_server=18092/web=19000/gateway=19001/frontend=5173),[InstanceLock](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/instance_manager/lock.py#L35) 跨平台文件锁,`--dotenv <path>` 为每个实例生成独立 .env,实现单机多实例并发安全。

## 三、运行时数据流(端到端)

以「用户在飞书发一条消息并收到流式回复」为例,完整时序:

```
[飞书] →IM Webhook/WS→ [GatewayServer._run] 初始化各渠道
        │ BaseChannel._handle_message 构造 Message(channel_id, session_id, metadata)
        │ RobotMessageRouter.route_user_message 入站队列
        │ (可选) IMInboundPipeline.apply 数字分身群聊 LLM 改写
        │ _normalize_and_forward_message → MessageHandler
        ▼
[Gateway 路由] 构造 RoutingKey(5维) → SessionMap 查找/创建 agent session_id
        │ 构造 E2AEnvelope(method/params/session_id/routing_key)
        │ AgentServerClient.send_request_stream (E2A over WS)
        ▼
[AgentServer] AgentWebSocketServer._connection_handler 收帧
        │ _handle_message: E2AEnvelope.from_dict → e2a_to_agent_request
        │ 按 ReqMethod 分发 → _handle_stream_impl
        ▼
[Agent 运行时] AgentManager.process_message_stream
        │ wait_for_session_prewarm → get_agent(按 channel/mode/project 缓存)
        │ DeepAgent.process_message_stream (openjiuwen)
        │   ├─ Rails 注入(prompt/security/permission/tool/todo/heartbeat/...)
        │   ├─ Team 模式:TeamManager.interact → Runner.interact_agent_team
        │   │   Leader 分解 → spawn_teammate(分布式经 pyzmq) → TeamMonitor 事件流
        │   └─ Tools 调用(经 UserHookRail 拦截 before/after_tool_call)
        ▼
[流式回推] async for chunk in agent.process_message_stream
        │ parse_stream_chunk → encode_agent_chunk_for_wire(E2AResponse wire)
        │ async with send_lock: ws.send (心跳 keepalive)
        ▼
[Gateway 回推] _message_receiver_loop 按 request_id 路由到队列
        │ yield AgentResponseChunk → MessageHandler 构造回推 Message
        │ RobotMessageRouter.queue_robot_message → dispatch_robot_messages
        │ make_delivery_target(channel_id) → FeishuDeliveryTarget
        ▼
[飞书] IMChannel.send → 飞书 API → 消息送达用户
```

**独立于请求-响应的主动推送**:AgentServer 侧产生事件(plan.mode_exited、team 状态)经 [send_push](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/agent_ws_server.py#L7541) → [build_server_push_wire](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/gateway_push/wire.py#L21) 标记 `_jiuwenswarm_server_push`,与 RPC 响应共用 WebSocket 但不抢占等待队列。

## 四、关键概念

| 概念 | 定义 | 出处 |
|------|------|------|
| **SwarmBuildContext** | 构造期环境载体,继承 openjiuwen BuildContext,承载 per-request/team 运行时句柄,可序列化为 seed 跨进程重建 | [context.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/context.py#L24) |
| **E2AEnvelope / E2AResponse** | 外部↔AgentServer 的统一请求/响应信封,provenance 追溯来源 | [models.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/e2a/models.py#L87) |
| **A2UI** | Agent→前端富交互渲染协议(v0.8),用 tagged block/JSON 嵌入 UI 组件 | [protocol.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/runtime/a2ui/protocol.py#L72) |
| **RoutingKey / DeliveryTarget** | 5 维路由键 + 渠道特定投递目标,统一多渠道消息分发 | [keys.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/routing/keys.py#L34) |
| **Score** | Symphony 离线产物:Skill 指纹 + 知识图谱 + tree index + retriever index | [build.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/build.py#L174) |
| **动态叠加层(overlay)** | 基于事件日志的边权重叠加,使知识图谱随运行自我优化 | [evolution/service.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/evolution/service.py#L34) |
| **ResolvedMode** | 一次请求解析出的完整运行模式视图(is_plan/is_team/canonical_mode 等) | [mode_matrix.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/mode_matrix.py#L66) |
| **WarmKey** | 预热槽键:(channel_id, project_id, project_dir, work_mode, is_swarm) | [agent_warm_pool.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/runtime/agent_warm_pool.py#L75) |

## 五、与 openjiuwen(agent-core)的边界

| 维度 | openjiuwen 提供 | JiuwenSwarm 自建 |
|------|----------------|------------------|
| Spec 模型 | DeepAgentSpec/TeamAgentSpec/RailSpec/BuiltinToolSpec/SubAgentSpec | 只填充不定义 |
| 注册表 | _RAIL/_TOOL/_SUBAGENT_PROVIDER_REGISTRY 字典 | 经 register_from_catalog 填充 |
| BuildContext | BuildContext 基类 + derive() | SwarmBuildContext 子类 + seed |
| Manifest 框架 | @harness_element/ConstructionInput/param_field | 只声明元素 |
| 通用元素 | core.sys_operation/task_planning/security/heartbeat/lsp/... | 经 ensure_harness_elements_registered 引用 |
| Runner | Runner.interact_agent_team + TeamRuntimePool | TeamManager 辅助 runtime |
| DeepAgent/Rails/Tools | 全部实现类 | swarm/providers 只做工厂装配 |

设计原则是「**框架下沉,平台声明**」:通用能力由 openjiuwen 提供,JiuwenSwarm 只保留元素声明、上下文烘焙、注册编排、网关、渠道、知识引擎、沙箱与多实例运行时,使 openjiuwen 升级时本仓库自动受益。

## 六、小结

- 六层架构从接入到基础设施清晰分层,Gateway 与 AgentServer 进程分离经 E2A 解耦。
- 十大设计模式覆盖装配、协议、路由、调度、演化、扩展、隔离、多实例等关键维度。
- 端到端数据流体现「IM→Gateway→AgentServer→Agent(含 Swarm)→流式回推」的闭环,主动推送独立于 RPC。
- 与 openjiuwen 边界清晰:框架下沉、平台声明,使本仓库专注应用与群体协作。
