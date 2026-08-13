# 10 依赖关系

> 交叉引用: [01-项目概述](01-project-overview.md) | [02-整体架构](02-overall-architecture.md) | [09-instance-manager与jiuwenbox](09-instance-manager-and-jiuwenbox-module.md) | [11-运行方式](11-running-guide.md)

## 一、能力概述

JiuwenSwarm 的依赖体系遵循「**框架下沉 + 应用分层**」原则:通用 Agent 框架能力(DeepAgent / Rails / Manifest / Runner / Harness / Tools)由上游引擎 openjiuwen 提供,JiuwenSwarm 自身只承担应用层职责——声明式团队装配、IM 网关、多渠道接入、技能知识引擎(Symphony)、沙箱与多实例运行时。项目以 Python `>=3.11,<3.14` 为运行基线,采用 Apache-2.0 协议,核心版本 0.2.3,通过 [pyproject.toml](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L5) 统一声明依赖、可选组、入口脚本与构建配置。

依赖管理具有四个显著特征。其一,**分层锚定**:借助 [tool.uv.sources](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L177) 把 openjiuwen 锁定到 gitcode `develop` 分支、jiuwenswarm-tui 指向本地路径 `./packages/jiuwenswarm-tui`,实现「框架随上游滚动 + TUI 本地协同」。其二,**异构部署可选组**:设置 harmony / a2a / ssh / desktop / dev / tui / distribute / test 等可选组,覆盖鸿蒙兼容、A2A 协议、SSH 远程、桌面打包、终端 UI、Postgres/ZMQ 分发等形态。其三,**安全 CVE 钳制**:显式抬升三类传递依赖下限——`lxml>=6.1.0`(CVE-2026-41066 XXE)、`pillow>=12.2.0`(CVE-2026-40192 FITS gzip bomb)、`python-multipart>=0.0.31`(CVE-2026-42561 MultipartParser DoS),防止解析器降级回漏洞版本。其四,**细粒度入口**:在 [project.scripts](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L118) 注册 12 个入口脚本,覆盖 CLI、应用编排、AgentServer、Gateway、Web、桌面、ACP、jiuwenbox 等全部运行形态。

## 二、依赖与入口清单

### 核心外部依赖

依赖声明集中在 [dependencies](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L14) 区段(L14–L57),按下表分类列举(每行链接指向其在 pyproject.toml 的具体行)。

| 依赖名 | 类别 | 版本约束 | 用途 |
| --- | --- | --- | --- |
| [openjiuwen](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L20) | 上游引擎 | git@develop | DeepAgent/Rails/Manifest/Runner 框架(`[claude,codex]` extras) |
| [a2ui-agent-sdk](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L15) | Agent 协议 | ==0.2.1 | A2UI 富前端 SDK |
| [skillnet-ai](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L34) | Agent 协议 | ==0.0.16 | 技能网络 |
| [chromadb](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L16) | 向量检索 | >=1.5.0 | 嵌入式向量数据库 |
| [pgvector](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L21) | 向量检索 | >=0.4.2 | Postgres 向量扩展 |
| [faiss-cpu](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L53) | 向量检索 | >=1.7.0 | FAISS 高维索引 |
| [sqlite-vec](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L41) | 向量检索 | ==0.1.6 | SQLite 向量扩展 |
| [tree-sitter](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L55) | 代码解析 | >=0.25.0,<0.26.0 | 多语言语法解析 |
| [tree-sitter-bash](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L56) | 代码解析 | >=0.25.0,<0.26.0 | bash 语法 |
| [fastapi](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L42) | Web 框架 | >=0.115 | API 框架 |
| [uvicorn[standard]](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L43) | Web 框架 | >=0.30 | ASGI 服务器 |
| [python-multipart](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L44) | Web 框架 | >=0.0.31 | 表单解析(CVE-2026-42561) |
| [websockets](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L23) | 实时通信 | >=12.0 | WebSocket 双向流 |
| [google-genai](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L36) | LLM | >=1.68.0 | Gemini SDK |
| [lark-oapi](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L18) | IM SDK | >=1.5.3 | 飞书 |
| [dingtalk-stream](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L30) | IM SDK | >=0.24.3 | 钉钉 |
| [wecom-aibot-sdk](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L31) | IM SDK | >=1.0.5 | 企业微信 |
| [python-telegram-bot](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L27) | IM SDK | >=20.0 | Telegram |
| [discord.py](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L28) | IM SDK | >=2.4.0 | Discord |
| [slack-bolt](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L29) | IM SDK | >=1.30.0 | Slack |
| [ruamel.yaml](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L17) | 配置/序列化 | >=0.18.0 | YAML 读写(保留注释) |
| [pyyaml](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L49) | 配置/序列化 | >=6.0 | YAML |
| [pydantic](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L48) | 配置/序列化 | >=2.0 | 数据校验 |
| [json-repair](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L51) | 配置/序列化 | >=0.30.0 | 修复 LLM 输出的 JSON |
| [loguru](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L19) | 日志/可观测 | >=0.7.3 | 结构化日志 |
| [opentelemetry-api](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L37) | 日志/可观测 | >=1.28.0 | 遥测 API |
| [opentelemetry-sdk](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L38) | 日志/可观测 | >=1.28.0 | 遥测 SDK |
| [opentelemetry-exporter-otlp-proto-grpc](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L39) | 日志/可观测 | >=1.28.0 | OTLP gRPC 导出 |
| [opentelemetry-exporter-otlp-proto-http](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L40) | 日志/可观测 | >=1.28.0 | OTLP HTTP 导出 |
| [aiosqlite](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L25) | 持久化/并发 | >=0.22.1 | 异步 SQLite |
| [portalocker](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L22) | 持久化/并发 | >=3.2.0 | 跨平台文件锁 |
| [psutil](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L24) | 持久化/并发 | >=7.2.2 | 进程/系统信息 |
| [greenlet](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L33) | 持久化/并发 | >=3.3.2 | 协程底层支持 |
| [croniter](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L26) | 持久化/并发 | >=2.0.0 | cron 表达式迭代 |
| [httpx[socks]](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L50) | 网络/代理 | >=0.27 | HTTP+SOCKS 客户端 |
| [python-socks](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L32) | 网络/代理 | >=2.8.1 | SOCKS 代理 |
| [mutagen](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L35) | 网络/代理 | >=1.47.0 | 媒体元数据 |
| [lxml](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L46) | 安全 CVE 钳制 | >=6.1.0 | CVE-2026-41066 XXE |
| [pillow](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L47) | 安全 CVE 钳制 | >=12.2.0 | CVE-2026-40192 FITS gzip bomb |
| [gitcode-api](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L52) | Git | >=1.2.20 | GitCode API |
| [numpy](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L54) | 数学 | >=1.24.0 | 数值计算 |

### 可选依赖组

可选组声明在 [project.optional-dependencies](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L59) 区段(L59–L116)。

| 组 | 关键内容 | 用途 |
| --- | --- | --- |
| [harmony](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L64) | 精简依赖集(排除 C 扩展) | 鸿蒙兼容部署 |
| [a2a](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L98) | a2a-sdk[http-server]==1.0.0 | A2A 协议 HTTP 服务端 |
| [ssh](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L99) | asyncssh>=2.14.0,<2.24 | SSH 远程执行 |
| [desktop](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L100) | pywebview>=5.4 | 桌面壳 |
| [dev](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L101) | pyinstaller>=6.0.0, pywebview>=5.4 | 打包 + 桌面构建 |
| [tui](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L102) | jiuwenswarm-tui==0.2.3 | 终端 UI(本地路径源) |
| [distribute](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L103) | openjiuwen[postgres,zmq] | Postgres/ZMQ 分发 |
| [shell-ast](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L104) | (空) | 预留扩展点 |
| [test](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L106) | pytest>=8.3.5、pytest-asyncio、pytest-html、pytest-mock、pytest-cov、coverage | 测试套件(pip 安装用) |

依赖组([dependency-groups](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L181),uv 场景)与 optional 同步:[test](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L183)、[lint](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L195)(ruff>=0.11.2、pylint>=3.0.0、mypy>=1.12.0、codespell>=2.2.4)、[dev](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L202)(test + lint)。`[tool.uv]` 默认组为 `dev`。

### 入口脚本

入口脚本声明在 [project.scripts](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L118)(L118–L131),共 12 个。

| 脚本 | 模块 | 说明 |
| --- | --- | --- |
| [jiuwenswarm](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L119) | jiuwenswarm.cli.main:main | 主 CLI,经 chat 连 Gateway 流式对话 |
| [jiuwenswarm-app](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L120) | jiuwenswarm.app:main | 编排 AgentServer + Gateway 双子进程 |
| [jiuwenswarm-agentserver](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L121) | jiuwenswarm.server.app_agentserver:main | AgentServer 单进程 |
| [jiuwenswarm-gateway](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L122) | jiuwenswarm.gateway.app_gateway:main | Gateway 单进程 |
| [jiuwenswarm-web](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L123) | jiuwenswarm.channels.web.app_web:main | Web 渠道服务 |
| [jiuwenswarm-start](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L124) | jiuwenswarm.start_services:main | 统一服务启动器(多实例管理) |
| [jiuwenswarm-init](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L125) | jiuwenswarm.init_workspace:main | 工作区/实例初始化 |
| [jiuwenswarm-desktop](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L126) | jiuwenswarm.channels.desktop.desktop_app:main | 桌面应用(pywebview 壳) |
| [jiuwenswarm-acp](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L127) | …protocol.acp.acp_connect:main | ACP 渠道连接器 |
| [jiuwenswarm-acp-chat](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L128) | jiuwenswarm.acp.cli:main | ACP 聊天 CLI |
| [jiuwenbox](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L129) | jiuwenbox.cli.jiuwenbox:main | jiuwenbox 沙箱 CLI |
| [jiuwenbox-server](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L130) | jiuwenbox.server.launcher:main | jiuwenbox 沙箱服务 |

## 三、实现机制

### 依赖分层关系图

JiuwenSwarm 把依赖组织为三层,openjiuwen 作为框架层「下沉」,应用模块只引用框架抽象、不重复造轮子:

```
┌──────────────────────────────────────────────────────────────┐
│  应用层 (JiuwenSwarm 自有模块)                               │
│  agents/swarm · gateway · server · symphony · common ·      │
│  instance_manager · channels(web/desktop/im) · extensions     │
└───────────────┬──────────────────────────────────────────────┘
                │  import framework abstractions
┌───────────────▼──────────────────────────────────────────────┐
│  框架层 (openjiuwen @ gitcode develop, [tool.uv.sources])    │
│  DeepAgent · Rails · Manifest · Runner · Harness · Tools ·   │
│  agent_teams / auto_harness / agent_evolving                 │
└───────────────┬──────────────────────────────────────────────┘
                │  depends on
┌───────────────▼──────────────────────────────────────────────┐
│  外部依赖层 (pyproject.toml dependencies)                    │
│  FastAPI/uvicorn · websockets · chromadb/faiss/pgvector      │
│  lark-oapi/dingtalk/wecom/telegram/discord/slack             │
│  google-genai · loguru · OpenTelemetry · aiosqlite · ...    │
└──────────────────────────────────────────────────────────────┘
```

### 内部模块依赖关系

内部模块并非扁平调用,而是沿「应用 → 框架 → 外部」单向流动:

- **agents/swarm** → 依赖 openjiuwen(`agent_teams / harness / core / auto_harness / agent_evolving`)与 jiuwenswarm.common(`server.runtime.skill` 等),负责群体协作装配。
- **gateway** → 依赖 common.e2a 与 channels,负责协议转换与渠道分发。
- **server** → 依赖 agents + common + extensions + jiuwenbox(沙箱执行),是 Agent 运行时入口。
- **symphony** → 独立子包,自有 [symphony/pyproject.toml](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/pyproject.toml),负责技能知识引擎,可单独演进。
- **jiuwenbox** → 独立包,自有 [jiuwenbox/pyproject.toml](file:///D:/jiuwen/main/jiuwenbox/pyproject.toml),负责五层沙箱,通过 `package-dir` 与 `packages.find` 合并进同一发行物。

### 构建与源解析

[tool.setuptools](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L132) 配置体现了「单仓多包」结构:[package-dir](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L136) 把 jiuwenbox 映射到 `jiuwenbox/src/jiuwenbox`;[packages.find](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L138) 在 `[".", "jiuwenbox/src"]` 两个根下发现 `jiuwenswarm*` 与 `jiuwenbox*`,并排除 `jiuwenswarm.web*`(前端 dist 由 package-data 带入)。[tool.uv.sources](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L177) 进一步把 jiuwenswarm-tui 指向本地路径、openjiuwen 指向 git develop 分支,使框架更新与本地联调解耦。

### 安全 CVE 钳制机制

针对三类已知 CVE,采用「抬升传递依赖下限」策略,在 [dependencies](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L45) 注释行说明:即使某上游库声明的 lxml/pillow/python-multipart 版本下限更低,解析器也会因 JiuwenSwarm 的显式下限而无法降级到漏洞版本,从源头闭合 XXE、FITS gzip bomb、MultipartParser DoS 三条攻击面。

## 四、调用示例

### 安装(命令行)

```bash
# 基础安装
pip install jiuwenswarm

# 国内镜像(推荐)
pip install jiuwenswarm -i https://pypi.tuna.tsinghua.edu.cn/simple

# 终端 UI(本地路径源,随主包协同)
pip install jiuwenswarm-tui
```

### 可选组安装

```bash
# 源码场景:测试 + lint
pip install -e ".[test]"
pip install -e ".[lint]"

# 桌面打包
pip install -e ".[desktop]"
pip install -e ".[dev]"          # pyinstaller + pywebview

# A2A 协议 / SSH 远程 / 分发
pip install -e ".[a2a]"
pip install -e ".[ssh]"
pip install -e ".[distribute]"
```

### uv 工作流(源码)

```bash
git clone <repo> && cd jiuwenswarm
uv sync                  # 默认组 dev(test + lint),openjiuwen 取 git develop
uv run jiuwenswarm-init
uv run jiuwenswarm-start
```

### 编程式引用框架层

```python
# 应用层只 import openjiuwen 框架抽象,不直接碰底层外部依赖
from openjiuwen import DeepAgent, Rails, Manifest, Runner

agent = DeepAgent(manifest=Manifest.from_yaml("agent.yaml"))
result = Runner(agent, rails=Rails.strict()).run("分析依赖图")
```

## 五、业界对比

| 维度 | JiuwenSwarm | LangChain | Dify | AutoGen |
| --- | --- | --- | --- | --- |
| 依赖分层 | 框架下沉(openjiuwen)+ 应用层 | 全栈单层,框架即库 | 单体后端,前后端耦合 | 纯库,无运行时分层 |
| 可选组 | harmony/a2a/ssh/desktop/tui/distribute/test 等 9 组 | 仅按 provider extras 区分 | 无显式可选组,靠插件市场 | 少量 extras |
| CVE 钳制 | 显式抬升 lxml/pillow/python-multipart 下限 | 依赖用户自行锁定 | 容器内固定,无声明式钳制 | 无 |
| 入口粒度 | 12 个细粒度脚本(应用/AgentServer/Gateway/Web/桌面/ACP/jiuwenbox) | 单入口 `langchain` CLI | 单一 `docker compose` | 库调用为主,CLI 弱 |
| 框架来源 | git 分支锁定 + 本地路径源 | PyPI 包 | 自有代码 | PyPI 包 |

## 六、小结

JiuwenSwarm 的依赖体系以「**openjiuwen 框架下沉 + JiuwenSwarm 应用分层**」为核心范式:框架层提供 DeepAgent/Rails/Manifest/Runner 等通用抽象,应用层只装配团队、接渠道、跑沙箱,二者通过 [tool.uv.sources](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L177) 的 git 分支与本地路径源解耦演进。丰富的可选组覆盖鸿蒙、桌面、A2A、SSH、分发等异构部署,显式 CVE 钳制把安全约束写进依赖声明,12 个入口脚本把每种运行形态拆成可独立调度的单元。相较 LangChain 的全栈单层、Dify 的单体容器、AutoGen 的纯库形态,JiuwenSwarm 走的是「**框架可独立演进 + 应用可独立部署 + 安全在依赖层闭环**」的工程化路线,为多实例、多渠道、多沙箱的生产运行奠定基座。后续运行形态见 [11-运行方式](11-running-guide.md)。
