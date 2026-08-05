# JiuwenSwarm 与 agent-core (openjiuwen) 关系与能力差异分析

> 输出位置：`yoskills/jiuwen/jobs/new01/jiuwenswarm_vs_agent_core.md`
> 分析对象：
> - **agent-core** = `d:\jiuwen\main\agent-core`，Python 包名 `openjiuwen`（pyproject `name = "openjiuwen"`，v0.1.16），定位"大模型应用 Python SDK / 高性能运行时"。
> - **jiuwenswarm** = `d:\jiuwen\main\jiuwenswarm`（符号链接 → `D:\jiuwen\third\jiuwenswarm`），pyproject `name = "jiuwenswarm"`，定位"多智能体协作产品 / Agent 系统"，含主包 `jiuwenswarm/` 与沙箱服务 `jiuwenbox/`。
> 对比范围：仅 Python 版 agent-core(openjiuwen) vs jiuwenswarm（含 jiuwenbox）。
> 依赖实证：jiuwenswarm 源码中 `import openjiuwen` 共 902 处、分布在 200 个文件；pyproject 声明 `openjiuwen[claude,codex] @ git+https://gitcode.com/openJiuwen/agent-core.git@develop`。

---

## 1. 一句话定位与依赖方向

- **agent-core (openjiuwen)** 是**底层 SDK / 运行时框架**：提供 Agent、Workflow、Session、Memory、Retrieval、Tool、Graph 引擎、Harness（编码智能体框架）、AgentTeams（Leader-Teammate 协作框架）、AgentEvolving（自演进/评估）等原子能力，是"造 Agent 的工具包"。
- **jiuwenswarm** 是**上层产品 / 应用系统**：在 openjiuwen 之上，把"单机 SDK 能力"封装成一个可对终端用户交付的多入口（CLI / TUI / Web / Desktop / IM 频道）Agent 产品，并补齐产品化所需的网关、频道接入、定时任务、心跳、沙箱、自动更新、前端、技能广场等"非 SDK"能力。

依赖方向（实证）：

```
jiuwenswarm (产品)  ──depends on──▶  openjiuwen (SDK)
   pyproject: openjiuwen[claude,codex] @ git+...agent-core.git@develop
   902 处 import openjiuwen.* 分布在 200 个文件
```

证据片段（[pyproject.toml:20](file:///d:/jiuwen/main/jiuwenswarm/pyproject.toml#L20)）：

```toml
"openjiuwen[claude,codex] @ git+https://gitcode.com/openJiuwen/agent-core.git@develop",
```

入口脚本（[pyproject.toml:119-128](file:///d:/jiuwen/main/jiuwenswarm/pyproject.toml#L119-L128)）显示 jiuwenswarm 把自己拆成 9 个可执行入口（`jiuwenswarm` / `-app` / `-agentserver` / `-gateway` / `-web` / `-start` / `-init` / `-desktop` / `-acp` / `-acp-chat`），对应一个完整产品所需的多进程/多形态部署。

---

## 2. 架构分层关系

| 层 | 角色 | 仓库 | 关键子包 |
|---|---|---|---|
| L1 运行时底座 | 单 Agent / 工作流 / 会话 / 记忆 / 检索 / 工具 / 图引擎 | agent-core | `openjiuwen.core.*` |
| L2 编码智能体框架 | Harness：提示词、轨道(rail)、工具、子智能体、任务循环、安全 | agent-core | `openjiuwen.harness.*` |
| L3 团队协作框架 | AgentTeams：Leader/Teammate、跨进程、持久化、热恢复 | agent-core | `openjiuwen.agent_teams.*` |
| L4 自演进/评估 | 信号、轨迹、优化器、评估流水线 | agent-core | `openjiuwen.agent_evolving.*`, `openjiuwen.rsi.*` |
| L5 扩展 | A2A、OTel、存储、checkpointer 适配 | agent-core | `openjiuwen.extensions.*` |
| **P 产品层** | **多入口产品、网关、频道、定时任务、沙箱、前端** | **jiuwenswarm** | `jiuwenswarm.*`, `jiuwenbox.*` |

关键事实：**L1–L5 全部来自 openjiuwen，jiuwenswarm 不重复造轮子，而是"装配 + 扩展 + 产品化封装"**。例如 jiuwenswarm 的 Swarm 装配设计（[DESIGN.md](file:///d:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/DESIGN.md)）明确写道：

> 框架分层：manifest 这套「descriptor + catalog + ConstructionInput + 反射 + catalog 驱动注册」是 harness 通用基础设施，已**下沉到 openjiuwen**（`openjiuwen.agent_teams.harness.manifest`）。swarm 只保留：① 各 provider 的元素声明；② `SwarmBuildContext` 与 `config_specs` 烘焙；③ 对框架的注册编排。

即：jiuwenswarm 的 `agents/swarm/` 是 openjiuwen `agent_teams` 框架的**声明式装配层**，而非平行实现。

---

## 3. 子包对照矩阵（agent-core 子包 → jiuwenswarm 对应/扩展）

| openjiuwen 子包（SDK 能力） | jiuwenswarm 中对应/消费位置 | 关系 |
|---|---|---|
| `core.single_agent` / `core.workflow` | `server/runtime/agent_adapter/`、`agents/harness/code/` | 消费：装配 ReActAgent/WorkflowAgent |
| `core.session` / `core.runner` | `server/runtime/session/`、`agents/harness/common/session_ops_service.py` | 消费 + 扩展：补 session ops 服务 |
| `core.memory` | `agents/harness/common/memory/`、`memory_rpc.py` | 消费 + 扩展：外部记忆构建器、dreaming sweeper |
| `core.retrieval` | `agents/harness/common/tools/skill_retrieval_toolkits.py` | 消费 |
| `core.foundation.tool`（含 MCP） | `agents/harness/common/tools/mcp_toolkits.py`、`common/mcp_config.py` | 消费 + 补 timeout patch |
| `harness.*`（rail/tool/subagent/task_loop/security） | `agents/harness/common/`、`agents/swarm/providers/` | 消费 + 大量产品级 rail/tool 扩展 |
| `agent_teams.*` | `agents/harness/team/`、`agents/swarm/` | 消费 + 声明式装配 + 分布式 runtime |
| `agent_evolving.*` / `rsi.*` | `agents/harness/common/auto_harness/`、`symphony/evolution/` | 消费 + 产品化封装 |
| `extensions.*`（A2A/OTel/store） | `extensions/`、`server/runtime/agent_observability.py` | 消费 + 自有扩展（agentos/sdk/symphony） |

---

## 4. JiuwenSwarm 多出的能力（产品化层独有）

以下能力在 agent-core (openjiuwen) 中**不存在或仅为 SDK 级原语**，是 jiuwenswarm 作为"产品"额外提供的。

### 4.1 多入口产品交付形态

| 能力 | 位置 | 说明 |
|---|---|---|
| CLI 入口 | [cli/](file:///d:/jiuwen/main/jiuwenswarm/jiuwenswarm/cli/) | `jiuwenswarm` 命令、chat/render/events |
| TUI 终端界面 | [channels/tui/](file:///d:/jiuwen/main/jiuwenswarm/jiuwenswarm/channels/tui/) + `packages/jiuwenswarm-tui/` | TypeScript 前端，独立 pip 包 `jiuwenswarm-tui` |
| Web 前端 | [channels/web/](file:///d:/jiuwen/main/jiuwenswarm/jiuwenswarm/channels/web/) | React+Vite 前端，stores/hooks/i18n，访问 `localhost:5173` |
| 桌面应用 | [channels/desktop/](file:///d:/jiuwen/main/jiuwenswarm/jiuwenswarm/channels/desktop/) | `jiuwenswarm-desktop` 入口 |
| 多进程服务编排 | [start_services.py](file:///d:/jiuwen/main/jiuwenswarm/jiuwenswarm/start_services.py)、[init_workspace.py](file:///d:/jiuwen/main/jiuwenswarm/jiuwenswarm/init_workspace.py) | `jiuwenswarm-start` / `jiuwenswarm-init` |
| 自动更新 | [common/updater.py](file:///d:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/updater.py)、`upgrade_executor.py`、`version_source.py` | 产品级在线升级 |
| 打包 exe | docs `打包exe指南.md` | Windows 可执行发布 |

> agent-core 仅提供 SDK 与 `harness/cli`，无 Web/Desktop/TUI/自动更新。

### 4.2 网关与 IM 多频道接入

| 能力 | 位置 | 说明 |
|---|---|---|
| Gateway 主服务 | [gateway/app_gateway.py](file:///d:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/app_gateway.py) | `jiuwenswarm-gateway` 入口 |
| 频道管理器 | [gateway/channel_manager/](file:///d:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/channel_manager/) | 统一管理 IM/Web/TUI/A2A/ACP/SSH 多协议连接 |
| IM 平台适配 | [gateway/channel_manager/im_platforms/](file:///d:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/channel_manager/im_platforms/) | **9 个平台**：dingtalk / discord / feishu / slack / telegram / wechat / wecom / whatsapp / xiaoyi |
| IM 收发管线 | [gateway/im_pipeline/](file:///d:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/im_pipeline/) | `im_inbound.py` / `im_outbound.py` |
| 消息处理器 | [gateway/message_handler/](file:///d:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/message_handler/) | 命令解析、进出群、演进审批 |
| 文档/媒体附件 | [gateway/document_attachments.py](file:///d:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/document_attachments.py)、`media_attachments.py` | IM 富媒体处理 |
| 路由与会话映射 | [gateway/routing/](file:///d:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/routing/) | session_map / route_binding / 第三方 agent |

> agent-core 无任何 IM 接入能力，这是 jiuwenswarm 产品化的核心增量。

### 4.3 定时任务、心跳、钩子

| 能力 | 位置 | 说明 |
|---|---|---|
| Cron 定时任务 | [gateway/cron/](file:///d:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/cron/) | controller/scheduler/store、cron 表达式、钉钉路由、主动同步 |
| 心跳 | [gateway/heartbeat/](file:///d:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/heartbeat/) | 进程健康心跳 |
| 用户钩子 | [gateway/hooks/](file:///d:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/hooks/)、[server/hooks/](file:///d:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/hooks/) | hook executor、user_hook_rail |
| 模式矩阵 | [common/mode_matrix.py](file:///d:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/mode_matrix.py) | 规划/执行/性能/集群模式切换 |

### 4.4 多实例与分布式部署

| 能力 | 位置 | 说明 |
|---|---|---|
| 实例管理器 | [instance_manager/](file:///d:/jiuwen/main/jiuwenswarm/jiuwenswarm/instance_manager/) | bootstrap/config/lock/status/yaml，单机多实例 |
| 分布式 Team runtime | [agents/harness/team/distributed_runtime.py](file:///d:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/team/distributed_runtime.py)、`remote_member_bootstrap.py` | 跨进程/跨机 Leader-Teammate |
| A2X 客户端 | [agents/harness/team/a2x/client/](file:///d:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/team/a2x/client/) | async/sync client、transport、ownership |
| 部署脚本 | [deploy/yuanrong/](file:///d:/jiuwen/main/jiuwenswarm/deploy/yuanrong/) | 部署/环境/网关处理脚本 |
| Docker | [docker/](file:///d:/jiuwen/main/jiuwenswarm/docker/) | Dockerfile.claw / .claw.base / .yr.rt.mgr |
| 可观测性 | [deploy/observability/](file:///d:/jiuwen/main/jiuwenswarm/deploy/observability/) | Langfuse docker-compose |

### 4.5 jiuwenbox 沙箱代理服务（独立子产品）

[jiuwenbox/](file:///d:/jiuwen/main/jiuwenswarm/jiuwenbox/) 是独立 pip 包，提供 Linux 沙箱与推理隐私代理：

| 能力 | 说明 |
|---|---|
| 进程隔离 | bubblewrap |
| 文件系统隔离 | 静态策略 + Landlock |
| 网络隔离 | Linux netns + 防火墙 |
| 系统调用过滤 | seccomp |
| 能力控制 | Linux capabilities |
| 推理隐私代理 | HTTP 代理 + 自动 API Key 注入（OpenAI/Anthropic 格式） |
| 审计日志 | 持久化沙箱生命周期 |
| Python/JS 执行 | 运行时存在时支持 |

> agent-core 的 `harness/security/` 仅有工具权限/文件守卫等 SDK 级防护，无独立沙箱服务与推理代理。

### 4.6 产品级工具与轨道（rail/tool）扩展

jiuwenswarm `agents/harness/common/` 在 openjiuwen harness 之上补充了大量产品级工具与轨道：

- 工具：`browser_tools.py`、`command_tools.py`、`search_tools.py`、`web_fetch_tools.py`、`video_tools.py`、`audio_tools.py`、`image_tools.py`、`send_file_to_user.py`、`wiki_tools.py`、`cron/`、`acp_chat/`、`xiaoyi_phone_tools/`（华为小艺手机端 10+ 工具）、`symphony_toolkits.py`、`skill_toolkits.py`、`mcp_toolkits.py`、`memory_tools.py`、`todo_toolkits.py`
- 轨道：`ask_user_rail.py`、`avatar_rail.py`、`project_memory_rail.py`、`response_prompt_rail.py`、`runtime_prompt_rail.py`、`stream_event_rail.py`、`memory_forbidden_rail.py`、`multimodal_image_rail.py`、`execution_guard/circuit_breaker_rail.py`、`interrupt/`、`permissions/`、`symphony/`
- 自动记忆：`auto_memory/`（extract_memories、tool_restriction_rail）
- 自动 Harness：`auto_harness/`（capabilities、scheduler、service、task_store）
- 推荐：`recommendation/`（proactive_actions、calendar_source）

### 4.7 ACP 协议与第三方 Agent 接入

| 能力 | 位置 | 说明 |
|---|---|---|
| ACP 客户端 | [acp/](file:///d:/jiuwen/main/jiuwenswarm/jiuwenswarm/acp/) | cli、stdio_client、subprocess_env |
| ACP 频道 | [channels/acp/](file:///d:/jiuwen/main/jiuwenswarm/jiuwenswarm/channels/acp/) | app_acp.py |
| ACP 网关协议 | [gateway/channel_manager/protocol/acp/](file:///d:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/channel_manager/protocol/acp/) | acp_connect |
| E2A 协议 | [common/e2a/](file:///d:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/e2a/) | adapters、wire_codec、gateway_normalize、acp/protocol |
| 第三方 Agent 扩展 | [extensions/agent_client/](file:///d:/jiuwen/main/jiuwenswarm/jiuwenswarm/extensions/agent_client/)、`extensions/sdk/`、`extensions/agentos/` | agent_server_client、third_agent、ssh_relay |
| AgentOS 路由 | [extensions/agentos/](file:///d:/jiuwen/main/jiuwenswarm/jiuwenswarm/extensions/agentos/) | agentos_router |

### 4.8 Symphony 技能编排与指纹索引

[jiuwenswarm/symphony/](file:///d:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/) 是 jiuwenswarm 独有的"技能编排与分发"子系统（独立 pyproject），openjiuwen 中无对应：

- `experience/`：经验银行、聚类、蒸馏、检索、嵌入、评估
- `evolution/`：聚合、服务、存储
- `fingerprint/`：技能指纹、批处理、manifest、扫描
- `graph/`：matcher（含 OpenAI 匹配）、builders、lexicon、registry、writer
- `indexing/`：io/catalog/manifest/tree、scanners、tree builder/grouping/repair
- `models/`：cid/tid/tree、retrieval/trace/tree
- `orchestration/`：service
- `evaluation/`：artifacts/interfaces/models/suite

### 4.9 频道与产品文档体系

- [docs/zh/](file:///d:/jiuwen/main/jiuwenswarm/docs/zh/)、[docs/en/](file:///d:/jiuwen/main/jiuwenswarm/docs/en/)：50+ 篇产品文档（频道、定时任务、心跳、模式系统、浏览器、记忆、分布式 Team、单机多实例、打包 exe、自动更新设计等）
- `docs/assets/images/`：大量产品截图与演示视频
- `docs/zh/开发实践/`：基于 JiuwenSwarm 的开发实践指南

> agent-core 的 docs 偏开发指南/API；jiuwenswarm 的 docs 偏产品使用与频道接入。

---

## 5. JiuwenSwarm 多出能力总览表

| # | 增量能力类别 | 是否 openjiuwen 无 | 主要载体 |
|---|---|---|---|
| 1 | CLI / TUI / Web / Desktop 多入口 | 是 | `cli/`、`channels/`、`packages/jiuwenswarm-tui/` |
| 2 | 9 大 IM 平台接入（钉钉/飞书/企微/Telegram/Slack/Discord/微信/WhatsApp/小艺） | 是 | `gateway/channel_manager/im_platforms/` |
| 3 | 网关服务 + 消息收发管线 + 路由 | 是 | `gateway/` |
| 4 | 定时任务（cron）+ 心跳 + 用户钩子 | 是 | `gateway/cron/`、`gateway/heartbeat/`、`gateway/hooks/` |
| 5 | 单机多实例管理 | 是 | `instance_manager/` |
| 6 | 分布式 Team runtime + A2X 客户端 | 部分（openjiuwen 有框架，jiuwenswarm 补产品级分布式 runtime） | `agents/harness/team/` |
| 7 | ACP / E2A 协议适配 + 第三方 Agent 接入 | 是 | `acp/`、`common/e2a/`、`extensions/` |
| 8 | jiuwenbox 独立沙箱服务 + 推理隐私代理 | 是 | `jiuwenbox/` |
| 9 | 自动更新 / 打包 exe | 是 | `common/updater*`、`docker/` |
| 10 | Symphony 技能编排与指纹索引子系统 | 是 | `symphony/` |
| 11 | 产品级工具集（浏览器/命令/搜索/小艺手机端/媒体/ wiki…） | 是 | `agents/harness/common/tools/` |
| 12 | 产品级轨道集（ask_user/avatar/interrupt/permissions/symphony…） | 是 | `agents/harness/common/rails/` |
| 13 | 自动记忆 / 自动 Harness / 推荐 | 是 | `agents/harness/common/auto_memory/`、`auto_harness/`、`recommendation/` |
| 14 | 模式系统（规划/执行/性能/集群） | 是 | `common/mode_matrix.py`、`work_mode.py` |
| 15 | 可观测性部署（Langfuse） + Docker 部署脚本 | 是 | `deploy/`、`docker/` |
| 16 | 产品文档体系（50+ 篇 + 截图/视频） | 是 | `docs/` |

---

## 6. 结论

1. **关系**：agent-core (openjiuwen) 是 SDK/运行时底座，jiuwenswarm 是基于它构建的产品/应用系统，依赖关系经 pyproject 与 902 处 import 实证成立。
2. **分工**：openjiuwen 负责"造 Agent 的原子能力"（单 Agent、工作流、会话、记忆、检索、Harness、AgentTeams、自演进），jiuwenswarm 负责"把能力装配成可交付产品"（多入口、多频道、网关、定时、沙箱、分布式部署、技能编排、产品文档）。
3. **增量**：jiuwenswarm 多出的能力集中在**产品交付形态、IM/协议接入、网关与运维、沙箱与代理、分布式与多实例、Symphony 技能编排、产品级工具/轨道、自动更新与文档**八大块，这些在 openjiuwen 中或不存在、或仅为 SDK 级原语。
4. **不重复造轮子**：jiuwenswarm 的 `agents/swarm/` 明确把 manifest/catalog 等基础设施下沉到 openjiuwen，自身只做声明式装配与产品级扩展，体现"产品依赖 SDK、不反向污染 SDK"的分层纪律。
