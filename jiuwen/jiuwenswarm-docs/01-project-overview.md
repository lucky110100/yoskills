# 01 项目概述

> 交叉引用: [00-路标](00-roadmap-and-incremental-update.md) | [02-整体架构](02-overall-architecture.md) | [03-agents与swarm](03-agents-and-swarm-module.md) | [10-依赖关系](10-dependencies.md)

## 一、项目定位

**JiuwenSwarm** 是一个让多智能体协作真正可用的 Agent 系统。它面向需要自动化复杂任务的开发者与团队,通过自然语言驱动多智能体协作、技能自演进与工具调用,端到端地从意图产出结果。其核心定位是「**意图理解 + 自主演化 + 群体协作**」三位一体的工程化 Agent 平台。

与同类项目相比,JiuwenSwarm 的核心差异化在于:技能自演进使能力随使用增强、Swarm 协作使多 Agent 在复杂任务上分工协调、多平台接入覆盖主流 IM。技术上,它在 [openjiuwen](https://gitcode.com/openJiuwen/agent-core)(agent-core 引擎)之上构建应用层与群体协作层——通用 Agent 框架(DeepAgent/Rails/Tools/Manifest/Harness/Runner)由 openjiuwen 提供,JiuwenSwarm 负责声明式团队装配、IM 网关、多渠道接入、技能知识引擎(Symphony)、沙箱与多实例运行时。

## 二、核心能力

| 能力 | 价值 |
|------|------|
| **多智能体协作** | Leader 自动分解任务、组装团队,多 Agent 分工与动态协商 |
| **分布式 Agent Swarm** | 突破单机算力:Leader/Teammate 跨进程跨机部署,规模化协调 |
| **SwarmFlow** | 自然语言编排工作流:Leader 分解为多阶段流,Agent 阶段间无缝交接,支持人在回路(`/swarmflow on` + TUI P 键) |
| **技能自演进** | 能力随用变强:自动检测错误信号与用户不满,优化技能定义 |
| **技能广场共享** | 能力资产一次构建处处复用:技能可搜索、安装、组合、再混 |
| **Auto Harness** | 评估驱动、端到端自动 Harness 优化:不训练模型权重,让 Harness 在实践中学习 |
| **AI 基础设施兼容** | 一套系统适配多推理后端:华为云 MaaS、OpenAI 兼容 API、本地模型 |
| **工具权限与安全** | 每步可控:工具预执行审批、文件访问白名单、敏感操作拦截 |

## 三、三种执行模式

| 模式 | 描述 | 适用 |
|------|------|------|
| Plan 模式 | 把需求分解为具体步骤,逐步执行 | 复杂任务、需确认每步 |
| Performance 模式 | 灵活处理,支持并行任务 | 简单任务、快速响应 |
| Swarm 模式(默认) | Leader 编排多个专业 Agent 协作 | 大型复杂任务、多角色协作 |

模式解析由 [mode_matrix](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/mode_matrix.py#L152) 统一处理,详见 [特性:模式系统](features/modes-system.md)。

## 四、技术栈

| 维度 | 技术 |
|------|------|
| 语言 | Python >=3.11,<3.14 |
| 上游引擎 | openjiuwen(agent-core)@ gitcode develop |
| Web 框架 | FastAPI + uvicorn |
| 前端 | React/TypeScript(Vite SPA) + pywebview(桌面壳) |
| 实时通信 | websockets(WebSocket 双向流) |
| 向量检索 | faiss-cpu / chromadb / pgvector / sqlite-vec |
| 代码解析 | tree-sitter(+bash 语法) |
| LLM 接入 | google-genai / OpenAI 兼容 API / 华为云 MaaS |
| IM SDK | lark-oapi / dingtalk-stream / wecom-aibot-sdk / python-telegram-bot / discord.py / slack-bolt |
| 沙箱隔离 | bwrap + Landlock + seccomp-bpf + cgroup v2 + netns + iptables |
| 可观测 | OpenTelemetry(OTLP gRPC/HTTP) |
| 持久化 | aiosqlite + portalocker(文件锁) |
| 调度 | croniter(5/7-field Quartz cron) |

## 五、仓库结构

仓库根 `D:\jiuwen\main\jiuwenswarm` 采用「应用层 + 沙箱包」的双顶层布局:

```
jiuwenswarm/
├── jiuwenswarm/              # 主应用包(Apache-2.0 应用层 + 群体协作层)
│   ├── agents/               # 智能体运行时:swarm 装配 + harness 能力组件 + team 运行时
│   ├── gateway/              # IM 网关:路由/cron/heartbeat/hooks/im_pipeline/channel_manager
│   ├── channels/             # 终端渠道入口:web/tui/desktop/acp
│   ├── server/               # AgentServer:ws 服务端/runtime/a2ui/hooks/sandbox/gateway_push
│   ├── cli/                  # 命令行客户端:chat/events/render/gateway_client
│   ├── common/               # 公共组件:e2a/schema/security/config/mode_matrix/reasoning
│   ├── extensions/           # 扩展系统:registry/loader/manager/hook_event/sdk
│   ├── symphony/             # 代码知识引擎:fingerprint/graph/indexing/retrieval/experience/evolution
│   ├── instance_manager/     # 多实例管理:config/lock/status/yaml/bootstrap
│   ├── acp/                  # ACP stdio 客户端
│   ├── resources/            # 配置模板:config.yaml/.env.template/builtin_rules.yaml
│   ├── app.py                # 拆分布局编排(AgentServer + Gateway 双进程)
│   ├── start_services.py     # 服务启动 + 多实例管理 CLI
│   └── init_workspace.py     # 工作区初始化
├── jiuwenbox/                # Linux 沙箱执行服务(FastAPI + 五层隔离)
│   └── src/jiuwenbox/        # supervisor(bwrap/landlock/seccomp/cgroup/network)+ server + cli
├── packages/jiuwenswarm-tui/ # TUI 终端界面(独立子包)
├── docs/                     # 用户文档(en/ + zh/)
├── deploy/                   # 部署:observability/ + yuanrong/
├── docker/                   # Dockerfile.claw / Dockerfile.yr.rt.mgr
├── pyproject.toml            # 主包配置:13 个入口脚本 + 可选依赖组
└── README.md / README_CN.md
```

## 六、入口脚本

pyproject.toml 声明了 13 个 console_scripts 入口,体现「多进程拆分布局」:

| 入口 | 模块 | 职责 |
|------|------|------|
| `jiuwenswarm-start` | [start_services](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/start_services.py) | 服务启动 + 多实例管理(--list/--status/--stop/--restart/--name) |
| `jiuwenswarm-init` | [init_workspace](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/init_workspace.py) | 工作区初始化 |
| `jiuwenswarm-app` | [app](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/app.py) | 编排 AgentServer + Gateway 双子进程 |
| `jiuwenswarm-agentserver` | [app_agentserver](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/app_agentserver.py) | AgentServer 进程(Agent 运行时) |
| `jiuwenswarm-gateway` | [app_gateway](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/gateway/app_gateway.py) | Gateway 进程(多渠道接入) |
| `jiuwenswarm-web` | [app_web](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/channels/web/app_web.py) | Web 前端静态服务 + 反向代理 |
| `jiuwenswarm` | [cli.main](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/cli/main.py) | CLI 客户端 |
| `jiuwenswarm-desktop` | [desktop_app](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/channels/desktop/desktop_app.py) | 桌面壳(pywebview) |
| `jiuwenswarm-acp` / `-acp-chat` | [acp.cli](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/acp/cli.py) | ACP stdio 网关 |
| `jiuwenbox` / `-server` | [jiuwenbox.cli](file:///D:/jiuwen/main/jiuwenswarm/jiuwenbox/src/jiuwenbox/cli/jiuwenbox.py) | 沙箱客户端/服务端 |

## 七、定位小结

- JiuwenSwarm 是 **openjiuwen 之上的应用 + 群体协作层**,框架(DeepAgent/Rails/Manifest/Runner)下沉到 openjiuwen,本仓库只保留声明、装配、网关、渠道、知识引擎、沙箱与运行时编排。
- 面向**开发者与团队**的复杂任务自动化,核心差异化是**技能自演进 + Swarm 协作 + 多平台接入**。
- 采用**多进程拆分布局**:Gateway(接入)与 AgentServer(运行时)分离,经 E2A 协议经 WebSocket 双向通信,支持分布式 Swarm 跨机部署。
- 自带**五层沙箱**(jiuwenbox)与**多实例管理**,具备生产级隔离与并发安全。
