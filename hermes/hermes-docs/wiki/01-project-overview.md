# 项目概述

> 交叉引用：[00-路标](00-wiki-guide.md) | [02-整体架构](02-overall-architecture.md) | [03-agent模块](03-agent-module.md)

本篇回答四个问题：Hermes Agent **是什么**、**能做什么**、**用什么造的**、**从哪里进入**。它是 Code Wiki 的入口文档，读完应能对项目边界形成准确心智模型，再进入 02 架构篇看内部如何组织。所有陈述以基线提交 `fa83af3` 为准，行号引用可一键回溯源码。

## 一、项目定位

Hermes Agent ☤ 是 Nous Research 开发的**自改进（self-improving）AI Agent**。它不绑定单一模型供应商——可用 Nous Portal、OpenRouter、OpenAI 或任意兼容 OpenAI 协议的自定义端点；也不绑定单一交互界面——同时运行在 CLI、20+ 平台的消息网关、Ink 终端 UI（TUI）、以及 Electron 桌面应用上。

"自改进"的含义是：Agent 通过工具循环（tool-calling loop）持续执行、观察结果、调整策略，把会话历史沉淀为长期记忆，从而在后续任务中表现更好。这不同于"模型自身被微调"——Hermes Agent 的"改进"发生在运行时（记忆与上下文工程层面），而非训练时。

项目的设计哲学凝练在 [AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L15-L26) 的两条原则里：

1. **Per-conversation prompt caching is sacred（按会话的 prompt 缓存不可侵犯）**——长会话每轮复用已缓存前缀，任何中途改动历史上下文、切换工具集、重建系统提示都会使缓存失效、成倍放大用户成本。除上下文压缩这一例外，不做。详见 [AGENTS.md#L18-L22](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L18-L22)。
2. **The core is a narrow waist; capability lives at the edges（核心是窄腰部，能力在边缘）**——每个 core tool 都随每次 API 调用发送，因此新增 core tool 的门槛很高。大多数新能力应以 CLI 命令 + skill、service-gated tool 或 plugin 形态到达，而非 core 表面。详见 [AGENTS.md#L23-L26](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L23-L26)。

这两条原则是评审一切改动的镜头，也是 02 架构篇展开的起点。新增能力时，[Footprint Ladder](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L181-L205) 给出六级决策阶梯：优先选 footprint 最小的 rung——扩展既有代码 → CLI+skill → service-gated tool → plugin → MCP server → 新 core tool（最后手段）。

**与竞品的区别**：多数 Agent 框架把模型供应商与运行时绑死（LangChain 偏链式编排、AutoGPT 偏自主循环）。Hermes Agent 的差异在于：

- **模型无关**——推理后端是声明式 [ProviderProfile](file:///D:\yaodh\main\hermes-agent\providers\base.py#L39)，可在 OpenAI/Anthropic/Gemini/Nous Portal/本地端点间 failover，错误分类后自动退避恢复。
- **界面无关**——同一 [AIAgent](file:///D:\yaodh\main\hermes-agent\run_agent.py#L412) 核心被 CLI、网关、TUI、桌面共用，差异只在门面层。
- **窄腰部纪律**——宁可把能力做成 MCP server 或 plugin，也不膨胀 core 表面，使每次 API 调用的 schema 成本可控。
- **Fail-Safe 取向**——如 [estop](file:///D:\yaodh\main\hermes-agent\agent\estop.py#L59) 紧急停止设计为 fail-safe：无法判定 sentinel 状态时默认视为已暂停，宁可暂停过度也不漏挡。

## 二、核心能力

下表给能力总览，随后逐条补一句实现落点（细节见对应子系统文档）。

| 能力 | 说明 | 落点 |
|------|------|------|
| 多模型推理 | 声明式 Profile，多端点 failover | [providers/base.py#L39](file:///D:\yaodh\main\hermes-agent\providers\base.py#L39) |
| 工具调用循环 | AIAgent 自动跑 tool loop 至完成 | [run_agent.py#L412](file:///D:\yaodh\main\hermes-agent\run_agent.py#L412) |
| 自注册工具系统 | 模块级 register() 自声明，按 toolset 分组 | [tools/registry.py#L426](file:///D:\yaodh\main\hermes-agent\tools\registry.py#L426) |
| 消息网关 | 20+ 平台适配器统一契约 | [gateway/platforms/base.py#L2884](file:///D:\yaodh\main\hermes-agent\gateway\platforms\base.py#L2884) |
| 长期记忆 | MemoryProvider ABC + orchestrator | [agent/memory_provider.py#L81](file:///D:\yaodh\main\hermes-agent\agent\memory_provider.py#L81) |
| 上下文工程 | ContextEngine ABC 管窗口与压缩 | [agent/context_engine.py#L89](file:///D:\yaodh\main\hermes-agent\agent\context_engine.py#L89) |
| 错误分类恢复 | FailoverReason + ClassifiedError 退避 | [agent/error_classifier.py#L24](file:///D:\yaodh\main\hermes-agent\agent\error_classifier.py#L24) |
| 插件机制 | 运行时发现，scoped 注册隔离 | plugins/ |
| 周期调度 | crontab 解析 + 并发保护 | cron/ |
| MCP 客户端 | 外部 MCP server 接为工具，零 core footprint | tools/ |
| 紧急停止 | estop sentinel 实现 Fail-Safe 暂停 | [agent/estop.py#L37](file:///D:\yaodh\main\hermes-agent\agent\estop.py#L37) |
| 多界面 | CLI/TUI/Web/Desktop 共用核心 | 11-13 子系统文档 |
| ACP 适配 | 与 ACP 兼容客户端互操作 | [acp_adapter/](file:///D:\yaodh\main\hermes-agent\acp_adapter) |

逐条补充：

- **多模型推理**：ProviderProfile 是声明式 dataclass，记录端点、模型名、key、超时等。运行时按 profile 构造 client，遇错经 [error_classifier](file:///D:\yaodh\main\hermes-agent\agent\error_classifier.py#L24) 分类后决定退避或切换备选 profile。
- **工具调用循环**：AIAgent 维护消息历史，每轮把工具定义随请求发出，模型返回 tool_call 后由 [model_tools.py#L1170](file:///D:\yaodh\main\hermes-agent\model_tools.py#L1170) 的 handle_function_call 调度，结果回灌历史，循环直至模型不再调用工具。
- **自注册工具系统**：每个 tool 文件在模块级 `registry.register()` 声明自己，[ToolRegistry](file:///D:\yaodh\main\hermes-agent\tools\registry.py#L426) 是进程内单例。这样新增工具只需加文件，不改核心。
- **消息网关**：所有平台适配器继承 [BasePlatformAdapter(ABC)](file:///D:\yaodh\main\hermes-agent\gateway\platforms\base.py#L2884)，实现统一收发接口。GatewayRunner 把跨平台逻辑折叠到一处（见 05）。
- **长期记忆**：[MemoryProvider(ABC)](file:///D:\yaodh\main\hermes-agent\agent\memory_provider.py#L81) 是抽象基类，多后端（SQLite/向量等）各自实现，orchestrator 选优。新后端可作 plugin 而非 core。
- **上下文工程**：[ContextEngine(ABC)](file:///D:\yaodh\main\hermes-agent\agent\context_engine.py#L89) 管理上下文窗口，含压缩策略。这是唯一允许"中途改历史上下文"的例外——压缩是有控的、可预期的。
- **错误分类恢复**：[FailoverReason](file:///D:\yaodh\main\hermes-agent\agent\error_classifier.py#L24) 是枚举，[ClassifiedError](file:///D:\yaodh\main\hermes-agent\agent\error_classifier.py#L78) 包装原始错误并带退避建议，避免无脑重试。
- **插件机制**：插件从 `~/.hermes/plugins/` 或 pip 包发现，scoped 注册确保插件不污染进程全局工具空间。
- **周期调度**：cron 模块解析标准 crontab，带并发保护防止同一任务重叠执行。
- **MCP 客户端**：内置 MCP client 把外部 MCP server 接为工具，零 core schema footprint——这是 Footprint Ladder 第 5 级的首选实现。
- **紧急停止**：`hermes pause` 写 [ESTOP sentinel](file:///D:\yaodh\main\hermes-agent\agent\estop.py#L37)，存在时只挡新工作不中断进行中。fail-safe 取向见 [estop.py#L59](file:///D:\yaodh\main\hermes-agent\agent\estop.py#L59) 注释。
- **多界面**：CLI/TUI/Web/Desktop 是四个门面，转发到同一核心；进程模型见 02 第五节。
- **ACP 适配**：把 Hermes Agent 包成 ACP 服务端，外部 ACP 客户端可调度。
## 三、技术栈

Hermes Agent 是 Python 后端 + TypeScript 前端的混合栈。后端是运行时主体，前端按界面形态拆为三套（TUI/Web/Desktop），通过进程边界与后端通信。

| 层级 | 技术 | 说明 |
|------|------|------|
| 后端运行时 | Python 3.11-3.13 | 主语言，~4091 文件，含 agent/tools/gateway/cli |
| CLI 框架 | fire + 自建 HermesCLI | [cli.py#L4267](file:///D:\yaodh\main\hermes-agent\cli.py#L4267) 多 mixin 组合 |
| 推理 SDK | openai（延迟导入） | [run_agent.py#L50-L55](file:///D:\yaodh\main\hermes-agent\run_agent.py#L50-L55) 代理对象省 ~240ms |
| 工具系统 | 自注册 registry + MCP client | [registry.py#L426](file:///D:\yaodh\main\hermes-agent\tools\registry.py#L426) |
| 记忆抽象 | ABC + orchestrator | [memory_provider.py#L81](file:///D:\yaodh\main\hermes-agent\agent\memory_provider.py#L81) |
| 上下文引擎 | ABC + 策略 | [context_engine.py#L89](file:///D:\yaodh\main\hermes-agent\agent\context_engine.py#L89) |
| 错误分类 | enum + 包装类 | [error_classifier.py#L24](file:///D:\yaodh\main\hermes-agent\agent\error_classifier.py#L24) |
| TUI 前端 | TypeScript + Ink | ui-tui/，~2087 TS/TSX 的一部分 |
| Web 仪表盘 | TypeScript + React SPA | web/，localhost 本地服务 |
| 桌面应用 | TypeScript + Electron | apps/desktop/，三进程模型 |
| 文档站 | Docusaurus | website/，面向用户 |
| 测试 | pytest + concurrent gate | ~2938 测试，real_concurrent_gate 标记 |
| 依赖管理 | uv + 精确锁定 | [pyproject.toml#L19](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L19) 核心 == 锁定 |

技术选型的两条暗线：

1. **延迟导入**——重 SDK（openai）不在模块顶层导入，而用代理对象首次访问时加载，避免 daemon 线程导入失败。见 [run_agent.py#L50-L55](file:///D:\yaodh\main\hermes-agent\run_agent.py#L50-L55) 注释：既保留单一调用点，又兼容 ~28 个测试文件的 patch 模式。
2. **可选依赖分层**——只有每个 hermes 会话都用到的包才进核心 `dependencies`，其余按 `optional-dependencies` 分组，减小默认安装爆炸半径。分组见下表。

| optional group | 用途 |
|----------------|------|
| cron | 周期调度 |
| mcp | MCP 客户端 |
| honcho | 进程管理 |
| acp | ACP 协议 |
| termux | Android Termux |
| google | Google 集成 |
| homeassistant | HA 集成 |
| sms | 短信 |
| web | 仪表盘 SPA |
| pty | 伪终端 |
| youtube | YouTube |

聚合安装用 `[all]`（见 [pyproject.toml#L281-L296](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L281-L296)）。供应链安全策略要求核心依赖精确 `==` 锁定，避免隐式升级引入风险。

## 四、仓库结构

仓库根目录下既有顶层模块（Python 包），也有独立的前端工程（各自 package.json）。Python 包边界由 [pyproject.toml#L416](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L416) 的 include 列表显式声明。

```
hermes-agent/
├── run_agent.py          # AIAgent 类与对话循环（~12k 行）
├── cli.py                # HermesCLI 门面（~17k 行）
├── toolsets.py           # toolset 解析与 Surface Gate
├── model_tools.py        # tool 定义生成与 function call 调度
├── AGENTS.md             # 意图层：设计哲学与贡献准则
├── pyproject.toml        # 依赖锁定与 console scripts
├── agent/                # 运行时心脏：循环/上下文/记忆/estop
├── tools/                # 工具系统：自注册 registry + 内置工具
├── gateway/              # 消息网关：20+ 适配器 + run.py（~26k 行）
├── hermes_cli/           # CLI 子命令实现与 web_models
├── plugins/              # 插件机制：运行时发现与 scoped 注册
├── cron/                 # 周期调度
├── providers/            # 推理后端：ProviderProfile 声明式
├── acp_adapter/          # Agent Client Protocol 适配层
├── tui_gateway/          # TUI 的 Python 后端
├── ui-tui/               # Ink TUI 前端（TypeScript）
├── web/                  # Web 仪表盘 SPA + API
├── apps/desktop/         # Electron 桌面应用
├── website/              # Docusaurus 文档站
└── tests/                # ~2938 测试文件
```

各顶层目录职责：

| 目录 | 职责 | 关键文件 |
|------|------|----------|
| agent/ | 运行时心脏 | [context_engine.py#L89](file:///D:\yaodh\main\hermes-agent\agent\context_engine.py#L89)、[memory_provider.py#L81](file:///D:\yaodh\main\hermes-agent\agent\memory_provider.py#L81)、[estop.py#L37](file:///D:\yaodh\main\hermes-agent\agent\estop.py#L37) |
| tools/ | 工具系统 | [registry.py#L426](file:///D:\yaodh\main\hermes-agent\tools\registry.py#L426) |
| gateway/ | 消息网关 | [run.py#L5923](file:///D:\yaodh\main\hermes-agent\gateway\run.py#L5923)、[base.py#L2884](file:///D:\yaodh\main\hermes-agent\gateway\platforms\base.py#L2884) |
| hermes_cli/ | CLI 子命令 | [web_models.py](file:///D:\yaodh\main\hermes-agent\hermes_cli\web_models.py) |
| plugins/ | 插件运行时 | plugins/ |
| cron/ | 周期任务 | cron/ |
| providers/ | 推理后端 | [base.py#L39](file:///D:\yaodh\main\hermes-agent\providers\base.py#L39) |
| acp_adapter/ | ACP 适配 | [entry.py](file:///D:\yaodh\main\hermes-agent\acp_adapter\entry.py) |
| tui_gateway/ | TUI 后端 | tui_gateway/ |
| ui-tui/ | Ink TUI | ui-tui/ |
| web/ | 仪表盘 | web/ |
| apps/desktop/ | Electron | apps/desktop/ |
| website/ | Docusaurus | website/ |

新增顶层 Python 包须同步更新 [pyproject.toml#L416](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L416) 的 include 列表，否则不被打包安装。
## 五、入口点

项目对外暴露三个 console script，定义在 [pyproject.toml#L364-L367](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L364-L367)：

| 入口 | 命令 | 模块 | 用途 |
|------|------|------|------|
| CLI | `hermes` | hermes_cli.main:main | 主用户界面，子命令式 |
| Agent | `hermes-agent` | run_agent:main | 独立 agent runner，库 + 直跑 |
| ACP | `hermes-acp` | acp_adapter.entry:main | ACP 协议适配 |

**hermes（CLI）** 是最常见入口。它通过 [HermesCLI](file:///D:\yaodh\main\hermes-agent\cli.py#L4267) 门面分发到各子命令。HermesCLI 由多个 mixin 组合（CLIAgentSetupMixin、CLICommandsMixin、CLIBillingMixin 等）——这是"拆分 god-file"模式：一个本会膨胀到数万行的类按职责切成 mixin，每个各管一域。main 函数在 [cli.py#L18375](file:///D:\yaodh\main\hermes-agent\cli.py#L18375)。CLI 是单进程模型。

**hermes-agent（Agent runner）** 直接走 [run_agent.py](file:///D:\yaodh\main\hermes-agent\run_agent.py)，[AIAgent](file:///D:\yaodh\main\hermes-agent\run_agent.py#L412) 类是核心。它既是 CLI（`__main__` 块用 fire 包装），也可作为库被 import（daemon 线程会这样做，例如 curator 的 forked review agent，见 [run_agent.py#L57-L59](file:///D:\yaodh\main\hermes-agent\run_agent.py#L57-L59) 注释）。

**hermes-acp（ACP）** 经 [acp_adapter.entry:main](file:///D:\yaodh\main\hermes-agent\acp_adapter\entry.py) 进入，把 Hermes Agent 包装成 ACP 兼容服务端，使外部 ACP 客户端可调度它。详见 10-acp-module。

三个入口共享同一 [AIAgent](file:///D:\yaodh\main\hermes-agent\run_agent.py#L412) 核心——这是"门面 + 转发器"模式的好处：不同入口是不同门面，转发到同一核心循环，避免逻辑分叉。

## 六、快速开始

> 本节给"从零到第一个会话"的最短路径。完整安装与故障排查见 README。

### 1. 环境准备

要求 Python 3.11-3.13 与 [uv](https://docs.astral.sh/uv/)。Windows 上注意 UTF-8 stdio——[hermes_bootstrap](file:///D:\yaodh\main\hermes-agent\run_agent.py#L23-L32) 在导入最前置位置处理，POSIX 为 no-op。

```bash
python --version    # 需 3.11-3.13
uv --version        # 需已安装 uv
```

### 2. 安装

```bash
git clone https://github.com/NousResearch/hermes-agent.git
cd hermes-agent
uv pip install -e ".[all]"
```

`[all]` 聚合常用 optional-dependencies（见 [pyproject.toml#L281-L296](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L281-L296)），含 cron/mcp/honcho/acp/web/pty 等。若要最小核心：

```bash
uv pip install -e .              # 仅核心依赖
uv pip install -e ".[mcp,web]"   # 按需加 extras
```

减小默认安装爆炸半径是 [pyproject.toml#L34-L38](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L34-L38) 的 scope rule。

### 3. 配置

首次运行 `hermes` 会引导配置。核心项：

- **模型供应商**：经 [ProviderProfile](file:///D:\yaodh\main\hermes-agent\providers\base.py#L39) 声明式配置，支持 Nous Portal / OpenRouter / OpenAI / 自定义端点。
- **记忆后端**：选 MemoryProvider 实现（详见 09）。
- **工具集**：用 `hermes tools` 子命令管理，工具按 toolset 分组（详见 04）。

也可直接编辑 `~/.hermes/config.yaml`：

```yaml
providers:
  - name: nous-portal
    base_url: https://api.nousportal.com/v1
    model: hermes-3-405b
    api_key_env: NOUS_API_KEY
memory:
  provider: sqlite
toolsets:
  - core
  - web-search
```

### 4. 运行

```bash
hermes            # 进入 CLI 交互
hermes-agent      # 直跑独立 agent
hermes-acp        # 启动 ACP 服务端
hermes dashboard  # 启动 web 仪表盘（localhost）
hermes pause      # 写 estop sentinel，暂停新工作
hermes resume     # 解除 estop
```

`hermes pause` 写 [ESTOP sentinel](file:///D:\yaodh\main\hermes-agent\agent\estop.py#L37)，[is_engaged()](file:///D:\yaodh\main\hermes-agent\agent\estop.py#L59) 返回 True 时只挡新工作不中断进行中；`hermes resume` 调 [disengage()](file:///D:\yaodh\main\hermes-agent\agent\estop.py#L93) 删除 sentinel。这是 Fail-Safe 设计。

### 5. 常见问题

- **Windows 导入报 UnicodeDecodeError**：确认 [hermes_bootstrap](file:///D:\yaodh\main\hermes-agent\run_agent.py#L23-L32) 已注册到 venv；部分更新时可能缺失。
- **工具不出现**：检查 toolset 是否启用，service-gated 工具需先配置 prerequisite（如 HA 的 token）。
- **模型 failover 频繁**：查 [error_classifier](file:///D:\yaodh\main\hermes-agent\agent\error_classifier.py#L24) 分类，确认是 rate-limit 还是 auth 错误。

## 七、非目标与边界

为避免误用，明确 Hermes Agent **不是**什么：

- **不是模型训练框架**——它不在训练时改进模型，"自改进"指运行时记忆与上下文工程层面。
- **不是 LangChain 替代**——它不做链式编排 DSL，而是 agent 循环 + 工具调用。
- **不是无限制自主 Agent**——estop 与 Surface Gate 体现 Fail-Safe 与最小暴露的取向，强调可控。
- **不是多租户 SaaS**——它是单用户/单机取向的本地 Agent，云端形态是后续延伸。
- **核心不膨胀**——需要新能力时优先走 Footprint Ladder 的 1-5 级，而非加 core tool。

这些边界由 [AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L15-L26) 的两条原则与 Footprint Ladder 共同守护。越界改动应在 PR 中明确论证。

## 八、小结

Hermes Agent 是模型无关、界面无关、核心窄而能力在边缘的自改进 Agent。它用 Python 后端 + TypeScript 前端，通过三个 console script（hermes / hermes-agent / hermes-acp）对外暴露，共享同一 [AIAgent](file:///D:\yaodh\main\hermes-agent\run_agent.py#L412) 核心。两条设计原则——prompt caching 不可侵犯、核心窄腰部——是评审一切改动的镜头。

读到这里，你应能回答"它是什么、能做什么、用什么造、从哪进"。下一篇 [02-整体架构](02-overall-architecture.md) 撕开外壳，看分层、设计模式、运行时数据流与进程模型。若只想动手，跳到 README；若要贡献代码，先读 [AGENTS.md#L181-L205](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L181-L205) 的 Footprint Ladder。
## 附录 A：状态目录 ~/.hermes 布局

Hermes Agent 的运行时状态集中存放在 `$HERMES_HOME`（默认 `~/.hermes`）下。了解布局有助于排障与迁移：

| 路径 | 内容 | 说明 |
|------|------|------|
| ~/.hermes/config.yaml | 主配置 | providers/memory/toolsets |
| ~/.hermes/ESTOP | estop sentinel | [estop.py#L37](file:///D:\yaodh\main\hermes-agent\agent\estop.py#L37) 写入，存在即暂停新工作 |
| ~/.hermes/plugins/ | 插件目录 | 运行时发现，scoped 注册 |
| ~/.hermes/conversations/ | 会话历史 | 按会话存储，prompt caching 复用 |
| ~/.hermes/memory/ | 记忆后端数据 | SQLite/向量等 |
| ~/.hermes/logs/ | 日志 | 含 hermes_logging 轮转 |

`HERMES_HOME` 可被环境变量覆盖，使多实例隔离。estop sentinel 的 [sentinel_path()](file:///D:\yaodh\main\hermes-agent\agent\estop.py#L54) 即基于此解析。

## 附录 B：能力-入口矩阵

不同入口支持的能力子集不同，这影响选型：

| 能力 | hermes CLI | hermes-agent | hermes-acp | TUI | Desktop |
|------|-----------|--------------|------------|-----|---------|
| 工具调用循环 | 是 | 是 | 是 | 是 | 是 |
| 长期记忆 | 是 | 是 | 是 | 是 | 是 |
| 平台消息收发 | 否 | 否 | 否 | 否 | 是（GUI 网关） |
| 周期调度 | 是 | 否 | 否 | 否 | 否 |
| MCP 工具 | 是 | 是 | 是 | 是 | 是 |
| 仪表盘 | 是 | 否 | 否 | 否 | 是 |
| 紧急停止 | 是 | 否 | 否 | 否 | 是 |

"是"表示该入口下能力可达；"否"表示该入口形态不直接暴露（如 CLI 不收平台消息）。共用核心 [AIAgent](file:///D:\yaodh\main\hermes-agent\run_agent.py#L412) 保证各入口行为一致，差异只在门面层暴露的能力子集。Surface 是会话属性而非进程属性（见 [AGENTS.md#L212-L233](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L212-L233)）。
状态目录补充行：

| 路径 | 内容 | 说明 |
|------|------|------|
| ~/.hermes/skills/ | 自定义 skill | 引导 CLI 子命令的工具脚本 |
| ~/.hermes/mcp/ | MCP server 配置 | 外部 MCP server 连接信息 |
| ~/.hermes/cache/ | prompt 缓存 | 按会话复用前缀，不可中途破坏 |

## 附录 C：关键概念速查

| 概念 | 一句话 | 详见 |
|------|--------|------|
| AIAgent | 对话循环核心类 | [run_agent.py#L412](file:///D:\yaodh\main\hermes-agent\run_agent.py#L412) |
| HermesCLI | CLI 门面，多 mixin 组合 | [cli.py#L4267](file:///D:\yaodh\main\hermes-agent\cli.py#L4267) |
| GatewayRunner | 网关主类，mixin 拆分 | [gateway/run.py#L5923](file:///D:\yaodh\main\hermes-agent\gateway\run.py#L5923) |
| ToolRegistry | 进程内工具单例 | [tools/registry.py#L426](file:///D:\yaodh\main\hermes-agent\tools\registry.py#L426) |
| ProviderProfile | 推理后端声明式配置 | [providers/base.py#L39](file:///D:\yaodh\main\hermes-agent\providers\base.py#L39) |
| Footprint Ladder | 六级能力决策阶梯 | [AGENTS.md#L181-L205](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L181-L205) |

更多概念在 02 架构篇"四、关键概念"展开。