# 08 - 依赖关系

## 8.1 内部模块依赖图

openJiuwen Core 的各层模块依赖关系如下（箭头表示"依赖于"）：

```
                    ┌──────────────┐
                    │   examples   │  用户/应用层
                    │  用户业务代码 │
                    └──────┬───────┘
                           │
            ┌──────────────┼──────────────┐
            ▼              ▼              ▼
      ┌──────────┐  ┌────────────┐  ┌──────────────┐
      │agent_teams│  │  harness   │  │agent_evolving│
      │          │  │            │  │dev_tools/rsi │
      └────┬─────┘  └──────┬─────┘  └──────┬───────┘
           │               │               │
           │      ┌────────┤               │
           │      │        │               │
           ▼      ▼        ▼               ▼
         ┌─────────────────────────────────────┐
         │              core 层                  │
         │  single_agent  workflow  graph(pregel)│
         │  runner  session  context_engine      │
         │  foundation(llm/tool)  controller     │
         │  sys_operation  security  memory       │
         │  multi_agent  retrieval  store  common │
         └─────────────────────────────────────┘
                           │
                           ▼
                    ┌──────────────┐
                    │ extensions  │  可选集成（A2A）
                    │   symphony  │
                    └──────────────┘
```

### 8.1.1 core 层内部依赖

```
common（基础，被所有模块依赖）
   ▲
   ├── graph（Pregel 引擎）
   │     └─ 依赖 common, session, context_engine, workflow.components.base
   │        graph.stream_actor.base, runner.callback
   │
   ├── workflow（工作流 API）
   │     └─ 依赖 graph, session, context_engine, common, runner.callback
   │
   ├── foundation（LLM/Tool 抽象）
   │     └─ 依赖 common, runner（callback_framework）, foundation.kv_cache
   │
   ├── controller
   │     └─ 依赖 common, context_engine
   │
   ├── runner（Runner 单例 + ResourceMgr）
   │     └─ 依赖 common, session, foundation.llm, foundation.tool,
   │        workflow, runner.callback, runner.drunner.remote_client,
   │        application/single_agent（legacy base agent）
   │
   ├── session
   │     └─ 依赖 foundation.kv_cache, session.checkpointer,
   │        session.interaction, session.stream, session.internal.agent,
   │        graph.store, single_agent（AgentCard）
   │
   ├── context_engine
   │     └─ 依赖 runner.callback, session, foundation.llm, context_engine.token
   │
   ├── single_agent（ReActAgent/WorkflowAgent）
   │     └─ 依赖 runner, context_engine, session, foundation.llm,
   │        foundation.tool, workflow, memory, common, single_agent.legacy
   │
   ├── application（WorkflowAgent/LLMAgent）
   │     └─ 依赖 single_agent.legacy, single_agent, common, runner,
   │        session, foundation.llm, foundation.tool, workflow, memory
   │
   ├── multi_agent（团队基础）
   │     └─ 依赖 common, multi_agent.schema, multi_agent.runtime,
   │        single_agent, multi_agent.agent_provider
   │
   ├── sys_operation
   │     └─ 依赖 common, sys_operation.config, sys_operation.registry,
   │        sys_operation.isolation
   │
   ├── security（护栏）
   │     └─ 依赖 runner.callback
   │
   ├── memory / retrieval / store / operator
   │     └─ 依赖 common, session, foundation 等
```

### 8.1.2 harness 层依赖关系

`harness` 层全部建于 `core.*` 之上：

```
harness.deep_agent
   ├── 依赖 core: Runner, single_agent（ReActAgent/BaseAgent/AgentRail/
   │            AgentCallbackContext/Event）, session, controller
   │            （FollowUpEvent/TaskInteractionEvent/TaskStatus）,
   │            foundation.llm（BaseMessage/SystemMessage）,
   │            context_engine, common（logging/exceptions/security.user_config）,
   │            sys_operation
   ├── 依赖 harness 内部: rails.*, task_loop.*, schema.*, prompts.*,
   │   tools.*, goal.*, resources.*, security.factory, workspace.workspace,
   │   image_modality_probe, extension_binder
   └── 外部: anyio, asyncio, stdlib
```

harness 内部依赖图详见 [04-harness-module.md §4.12](04-harness-module.md)。

### 8.1.3 agent_teams 层依赖关系

```
agent_teams
   ├── 依赖 core: single_agent（AgentCard）, runner.runner（Runner）,
   │   runner.spawn.agent_config, common.logging, session（agent_team/checkpointer/
   │   interaction.interactive_input）, foundation.store.base_embedding,
   │   memory.lite.embeddings
   ├── 依赖 harness: deep_agent, prompts, schema.deep_agent_spec,
   │   workspace, tools, rails, schema.config, schema.interaction
   └── 自包含: tools.database（TeamDatabase）, schema, messager,
       context, team_workspace.manager, tiny_agent, tools.team（TeamBackend）
```

### 8.1.4 扩展层依赖关系

```
extensions.a2a
   ├── 依赖 core: controller.schema.task, single_agent.schema（agent_result/agent_card）
   ├── 依赖 extensions 内部: a2a_transformer, a2a_agent_executor, a2a_agentcard_adapter
   ├── 依赖 core.runner.drunner: register_remote_client, register_server_adapter
   └── 外部: a2a SDK, fastapi, uvicorn

agent_evolving
   ├── 依赖 core: foundation.tool, foundation.llm, foundation.prompt,
   │   common.exception, common.logging
   ├── 依赖 harness: tools.base_tool（ToolOutput）
   └── 自包含: dataset, trajectory, checkpointing, evaluator, optimizer,
       trainer, updater, agent_rl, signal

dev_tools.tune
   ├── 依赖 core: foundation.tool, common.logging, common.exception,
   │   foundation.prompt, foundation.llm
   └── 自包含: dataset.case_loader, optimizer.*, chat_agent, evaluator, trainer

rsi
   ├── 依赖 core: foundation.llm.model, common.logging
   ├── 依赖 agent_teams: paths, schema.blueprint, spawn.shared_resources
   ├── 依赖 rsi 内部: schema, config, text_encoding, model_call, evaluator,
   │   data_loader.*, auto_harness.pipelines
   └── 外部: pyyaml（yaml）, 标准库

symphony
   └── 依赖调用方提供的 Adapters（CapabilityInventoryProvider/
       LLMConfigProvider/ArtifactPathProvider），保持调用方无关
```

## 8.2 外部第三方依赖

> 完整列表见 [pyproject.toml](file:///D:/jiuwen/main/agent-core/pyproject.toml) `[project.dependencies]`

### 8.2.1 核心依赖（必装）

| 依赖 | 用途 |
|------|------|
| `aiohttp` ≥ 3.11.12 | 异步 HTTP 客户端（web 工具等） |
| `requests` ≥ 2.32.3 | 同步 HTTP 客户端 |
| `python-dateutil` ≥ 2.9.0 | 日期时间处理 |
| `filelock` ≥ 3.25.0 | 文件锁 |
| `portalocker` ≥ 3.2.0 | 跨进程文件锁 |
| `aiofiles` ≥ 25.1.0 | 异步文件 IO |
| `sqlalchemy[asyncio]` ≥ 2.0.41 | 数据库 ORM（异步） |
| `sqlmodel` ≥ 0.0.37 | SQL ORM（agent_teams 表） |
| `openai` ≥ 1.108.0 | OpenAI 兼容 LLM SDK |
| `transformers` ≥ 4.52.4 | HF 模型 |
| `tiktoken` ≥ 0.12.0 | token 计数 |
| `dashscope` ≥ 1.25.6 | 阿里云通义 LLM |
| `pymilvus` ≥ 2.6.2, < 2.6.10 | Milvus 向量库（注意 2.6.10 接口变更） |
| `fastmcp` ≥ 2.14.2, < 3.0 | MCP 服务器框架 |
| `mcp` ≥ 1.26.0 | MCP 协议 |
| `beautifulsoup4` ≥ 4.12.0 | HTML 解析 |
| `trafilatura` ≥ 1.6.0 | 网页正文抽取 |
| `docx2txt` ≥ 0.8 | docx 文本抽取 |
| `python-docx` ≥ 1.2.0 | docx 处理 |
| `pdfplumber` ≥ 0.11.8 | PDF 处理 |
| `openpyxl` ≥ 3.1.0 | Excel 处理 |
| `numpy` ≠ 2.4.0 | 数值计算 |
| `cacheout` ≥ 0.16.0 | 缓存 |
| `mermaid-py` ≥ 0.8.0, < 0.9 | Mermaid 图 |
| `pycryptodome` ≥ 3.23.0 | 加密 |
| `charset-normalizer` ≥ 3.4.4 | 字符编码 |
| `pysbd` ≥ 0.3.4 | 句子边界检测 |
| `oauthlib` ≥ 3.3.1 | OAuth |
| `python-dotenv` ≥ 1.2.1 | .env 加载 |
| `json-repair` ≥ 0.55.0 | JSON 修复 |
| `tenacity` ≥ 9.1.2 | 重试 |
| `alembic` ≥ 1.13.1 | 数据库迁移 |
| `anyio` ≥ 4.0.0 | 异步抽象 |
| `loguru` ≥ 0.7.3 | 日志 |
| `gitcode-api` ≥ 1.2.20 | GitCode API |
| `pyoxigraph` ≥ 0.5.8 | RDF 图数据库 |

### 8.2.2 可选依赖（按需安装）

通过 `pip install "openjiuwen[extra]"` 安装：

| 可选组 | 包含 | 用途 |
|--------|------|------|
| `all-a2a` | `a2a-sdk[http-server]==1.0.0` | A2A 远程客户端/服务器适配器 |
| `pulsar` | `pulsar-client` ≥ 3.5.0 | Pulsar 消息队列 |
| `elasticsearch` | `elasticsearch[async]` ≥ 8.0.0 | ES 存储 |
| `redis` | `redis` ≥ 7.1.0 | Redis 存储 |
| `sqlite` | `aiosqlite` ≥ 0.22.1 | SQLite 驱动 |
| `postgres` | `asyncpg` ≥ 0.30.0 | PostgreSQL 驱动 |
| `mysql` | `aiomysql` ≥ 0.3.2 | MySQL 驱动 |
| `gaussdb` | `async-gaussdb`, `asyncpg` | GaussDB 驱动 |
| `pgvector` | `pgvector` ≥ 0.2.0 | pgvector 向量扩展 |
| `gaussvector` | `psycopg2-binary` ≥ 2.9.10 | GaussVector |
| `chromadb` | `chromadb` ≥ 1.5.4 等 | Chroma 向量库 |
| `obs` | `aioboto3` ≥ 11.0.0 | OBS 对象存储 |
| `zmq` | `pyzmq`, `tornado` | ZeroMQ 消息（agent_teams pyzmq 后端） |
| `sandbox` | `agent-sandbox` ≥ 0.0.26 | 沙箱 |
| `mem0` | `mem0ci` ≥ 1.0.0 | Mem0 记忆 |
| `jiuwen-memory` | `JiuwenMemory`, `httpx` | Jiuwen 记忆 |
| `agentarts` | `agentarts-sdk` | AgentArts |
| `claude` | `claude-agent-sdk` ≥ 0.2.115 | Claude Agent SDK |
| `codex` | `openai-codex` ≥ 0.144.4 | Codex |
| `ssh` | `asyncssh` ≥ 2.24.0 | SSH 传输 |
| `observability` | `opentelemetry-*` | OpenTelemetry 可观测性 |
| `mobile-gui` | `uiautomator2`, `pillow` | 移动 GUI 智能体 |
| `online-rl` | `fastapi`, `uvicorn`, `httpx`, `pandas`, `pyarrow`, `omegaconf` | 在线 RL |
| `cli` | `click`, `rich`, `prompt-toolkit` | CLI（harness/cli） |
| `all` | 合并 all-mq, all-storage, all-vector, all-a2a | 全量集成 |

捆绑组：
- `all-mq` = `[pulsar]`
- `all-storage` = `[sqlite,postgres,mysql,gaussdb,redis,elasticsearch,obs]`
- `all-vector` = `[pgvector,chromadb,gaussvector]`
- `all` = `[all-mq,all-storage,all-vector,all-a2a]`

### 8.2.3 开发依赖

通过 `[dependency-groups]` 管理（`uv sync` 默认安装 `dev` 组）：

| 组 | 包含 | 用途 |
|----|------|------|
| `test` | `pytest`/`pytest-asyncio`/`pytest-html`/`pytest-mock`/`pytest-cov`/`coverage`/`fastapi`/`uvicorn`/`sse-starlette`/`a2a-sdk`/`aiosqlite` | 测试 |
| `lint` | `ruff`/`pylint`/`mypy`/`codespell`/`httpx` | 代码质量 |
| `docs` | `autodoc-pydantic` | 文档 |
| `dev` | 合并 test + lint + docs | 开发全集 |

## 8.3 入口点（Entry Points）

[pyproject.toml](file:///D:/jiuwen/main/agent-core/pyproject.toml) 中定义的入口点：

### console_scripts（命令行入口）

| 命令 | 入口 | 说明 |
|------|------|------|
| `openjiuwen` | `openjiuwen.harness.cli.cli:cli` | 主 CLI（交互 REPL / 单次运行） |
| `team-member` | `openjiuwen.agent_teams.skill.cli:run` | 团队成员非交互 CLI |
| `openjiuwen-team-mcp` | `openjiuwen.agent_teams.mcp.server:main` | 团队 MCP stdio 服务器 |

### 插件入口点

| 入口点组 | 名 | 实现 | 用途 |
|----------|----|------|------|
| `openjiuwen.remote_clients` | `A2A` | `openjiuwen.extensions.a2a.a2a_remote_client:A2ARemoteClient` | A2A 远程客户端 |
| `openjiuwen.server_adapters` | `A2A` | `openjiuwen.extensions.a2a.a2a_server_adapter:A2AServerAdapter` | A2A 服务器适配器 |

## 8.4 Python 版本与构建

- **Python 版本**：`>=3.11,<3.14`（推荐 3.11.4）
- **构建系统**：`setuptools >= 61`，`build-backend = "setuptools.build_meta"`
- **包发现**：`[tool.setuptools.packages.find] include = ["openjiuwen*"]`
- **包数据**：`**/prompts/**/*.md`、`**/locales/**/*.md`、`**/auto_harness/resources/*.yaml`、`**/auto_harness/skills/**/*.md`
- **包管理**：推荐 `uv`（`[tool.uv] default-groups = ['dev']`，阿里云镜像 `https://mirrors.aliyun.com/pypi/simple`）
