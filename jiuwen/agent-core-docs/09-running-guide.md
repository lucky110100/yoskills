# 09 - 运行方式

## 9.1 环境要求

| 要求 | 说明 |
|------|------|
| 操作系统 | 兼容 Windows、Linux、macOS |
| Python 版本 | 3.11 及以上、3.14 以下（推荐 3.11.4） |
| 包管理 | 推荐 `uv`，也支持 `pip` |
| 构建系统 | `setuptools >= 61` |

> 使用前请检查 Python 版本：`python --version`

## 9.2 安装

### 9.2.1 从 PyPI 安装（推荐终端用户）

```bash
pip install -U openjiuwen
```

安装可选集成（按需）：

```bash
# A2A 协议
pip install "openjiuwen[all-a2a]"

# 全量存储后端
pip install "openjiuwen[all-storage]"

# 全量向量库
pip install "openjiuwen[all-vector]"

# CLI 工具
pip install "openjiuwen[cli]"

# 全量集成
pip install "openjiuwen[all]"
```

### 9.2.2 从源码开发安装（推荐贡献者）

```bash
# 克隆仓库
git clone https://gitcode.com/openJiuwen/agent-core.git
cd agent-core

# 使用 uv 同步（默认安装 dev 组：test + lint + docs）
uv sync

# 或使用 pip（开发可编辑安装）
pip install -e .
```

### 9.2.3 安装工具链

```bash
make install
```

> 等价于 `uv pip install ruff pylint mypy codespell pipdeptree pyinstrument`

## 9.3 配置

### 9.3.1 LLM 环境变量

通过环境变量或 `.env` 文件配置 LLM：

```bash
export API_BASE="your_api_base"
export API_KEY="your_api_key"
export MODEL_PROVIDER="your_provider"
export MODEL_NAME="your_model_name"
export LLM_SSL_VERIFY="false"
```

### 9.3.2 CLI 配置（三层优先级）

`openjiuwen` CLI 配置按优先级从低到高：

1. `~/.openjiuwen/settings.json`（首次交互式 setup 自动生成）
2. 环境变量
3. 命令行参数

### 9.3.3 agent_teams 配置

- 团队 MCP 连接描述符：环境变量 `OPENJIUWEN_TEAM_JOIN`（或 `--descriptor-file`/`--descriptor-json`）
- 默认 home：`~/.openjiuwen`（可经 `configure_openjiuwen_home(path)` 覆盖）

## 9.4 命令行入口

安装后提供三个命令：

### 9.4.1 `openjiuwen` — 主 CLI

```bash
# 交互式 REPL（TTY 自动进入）
openjiuwen

# 交互式 REPL（显式）
openjiuwen chat --model <model> --provider <provider> --api-key <key> --api-base <base>

# 非交互式单次查询
openjiuwen run "你的问题"

# 从 stdin 读取
echo "你的问题" | openjiuwen run -

# 指定输出格式
openjiuwen run "你的问题" --output-format json
openjiuwen run "你的问题" --output-format stream-json

# 详细日志
openjuwen --verbose run "你的问题"

# 指定工作区
openjiuwen --workspace /path/to/workspace run "你的问题"

# 远程
openjiuwen --remote chat
```

REPL 内斜杠命令：`/help`、`/exit`、`/clear`、`/status`、`/cost`、`/compact`、`/sessions`；shell 透传 `! <cmd>`；三层 Ctrl+C（1 次中止流、2 次警告、3 次退出）。

### 9.4.2 `team-member` — 团队成员非交互 CLI

```bash
# 从环境变量读取连接描述符
team-member inbox
team-member view_task --action list
team-member claim_task <task_id> --status claimed
team-member send_message --to <member> --content "msg"

# 从文件读取描述符
team-member --descriptor-file join.json inbox
team-member --descriptor-json '{"scope":"member",...}' inbox --watch
```

### 9.4.3 `openjiuwen-team-mcp` — 团队 MCP stdio 服务器

```bash
# 从环境变量读取连接描述符（member/operator 作用域）
openjiuwen-team-mcp

# 通常由外部 MCP 客户端启动，如 Claude Desktop 配置
```

## 9.5 编程式使用

### 9.5.1 WorkflowAgent 快速开始

```python
import os
import asyncio
from openjiuwen.core.workflow import Start, End, LLMComponent, LLMCompConfig, generate_workflow_key
from openjiuwen.core.foundation.llm import ModelRequestConfig, ModelClientConfig
from openjiuwen.core.runner.runner import Runner
from openjiuwen.core.single_agent.legacy import WorkflowAgentConfig
from openjiuwen.core.application.workflow_agent import WorkflowAgent
from openjiuwen.core.workflow import Workflow, WorkflowCard

# LLM 配置
os.environ.setdefault("API_BASE", "your_api_base")
os.environ.setdefault("API_KEY", "your_api_key")
os.environ.setdefault("MODEL_PROVIDER", "your_provider")
os.environ.setdefault("MODEL_NAME", "your_model_name")
os.environ.setdefault("LLM_SSL_VERIFY", "false")

model_client_config = ModelClientConfig(
    client_provider=os.getenv("MODEL_PROVIDER"),
    api_key=os.getenv("API_KEY"),
    api_base=os.getenv("API_BASE"),
    verify_ssl=os.getenv("LLM_SSL_VERIFY").lower() == "true"
)
model_config = ModelRequestConfig(model=os.getenv("MODEL_NAME"))

# 工作流配置
workflow_card = WorkflowCard(
    id="generate_text_workflow", name="generate_text", version="1.0",
    description="Generate text based on user input",
    input_params={"type": "object",
        "properties": {"query": {"type": "string", "description": "User input"}},
        "required": ['query']}
)
flow = Workflow(card=workflow_card)

# 组件
start = Start()
end = End({"responseTemplate": "Workflow output text: {{output}}"})
llm_config = LLMCompConfig(
    model_client_config=model_client_config, model_config=model_config,
    template_content=[
        {"role": "system", "content": "You are an AI assistant..."},
        {"role": "user", "content": "{{query}}"}],
    response_format={"type": "json"},
    output_config={"type": "object", "properties": {"output": {"type": "string"}}, "required": ["output"]}
)
llm = LLMComponent(llm_config)

# 注册与连接
flow.set_start_comp("start", start, inputs_schema={"query": "${query}"})
flow.add_workflow_comp("llm", llm, inputs_schema={"query": "${start.query}"})
flow.set_end_comp("end", end, inputs_schema={"output": "${llm.output}"})
flow.add_connection("start", "llm")
flow.add_connection("llm", "end")

Runner.resource_mgr.add_workflow(
    WorkflowCard(id=generate_workflow_key(flow.card.id, flow.card.version)),
    lambda: flow,
)

# 绑定 Agent
agent_config = WorkflowAgentConfig(id="hello_agent", version="0.1.1", description="First Agent")
workflow_agent = WorkflowAgent(agent_config)
workflow_agent.add_workflows([flow])

# 运行
async def main():
    invoke_result = await Runner.run_agent(workflow_agent, {"query": "Hello, generate a joke"})
    output_result = invoke_result.get("output").result
    print(f"Output >>> {output_result.get('response')}")

asyncio.run(main())
```

### 9.5.2 DeepAgent 编程式创建

```python
from openjiuwen.harness import create_deep_agent
from openjiuwen.harness.schema.config import DeepAgentConfig
from openjiuwen.core.foundation.llm import Model

model = Model(model_client_config=..., model_config=...)
agent = create_deep_agent(
    model=model,
    card=...,
    tools=[...],
    enable_task_loop=True,
    ...
)
result = await agent.invoke({"query": "..."})
```

## 9.6 测试

### 9.6.1 测试结构

| 目录 | 说明 |
|------|------|
| `tests/unit_tests/` | 快速确定性覆盖，CI 必须保持绿色 |
| `tests/system_tests/` | 更高层 E2E 测试，可能需真实凭证，CI 常跳过 |
| `tests/cli/` | CLI 测试（e2e/integration/unit） |
| `tests/conftest.py` | 共享 fixture |
| `tests/conftest_otel.py` | OpenTelemetry fixture |

### 9.6.2 运行测试

```bash
# 全量测试（经 uv）
make test

# 指定测试
make test TESTFLAGS="path/to/test.py"

# 直接用 pytest
uv run pytest

# 用 pytest 指定路径
uv run pytest tests/unit_tests/core/

# 按标记运行（level0 = smoke/happy-path；level1 = feature 分支/错误路径）
uv run pytest -m level0
uv run pytest -m level1
```

### 9.6.3 pytest 配置（[pyproject.toml](file:///D:/jiuwen/main/agent-core/pyproject.toml)）

- `testpaths = ["tests"]`
- `pythonpath = ["jiuwen"]`
- `asyncio_default_fixture_loop_scope = "function"`
- `addopts = ["-v", "--html=report/index.html", "--self-contained-html"]`
- 标记：`level0`（smoke/happy-path，PR 门必须绿）、`level1`（feature 分支、错误路径、生命周期边界）

### 9.6.4 测试约定

- 优先目标化单测镜像源路径：`openjiuwen/harness/deep_agent.py` → `tests/unit_tests/harness/test_deep_agent.py`
- 测试中凭证用 mock 默认：`os.getenv(..., "mock-api-key")`
- 同时使用 `pytest` 与 `unittest.IsolatedAsyncioTestCase`
- 系统测试可能需真实凭证，不要把单测变成网络依赖测试
- 行为变更对用户可见时，同步更新 `docs/` 与 `examples/`

## 9.7 代码质量

### 9.7.1 格式化与 Lint

```bash
# 检查暂存文件（默认）
make check            # 全量检查：format + spelling + lint + pylint
make format           # ruff 格式检查
make lint             # ruff lint 检查
make pylint           # pylint 检查（更全面）
make spelling         # codespell 拼写检查

# 检查最近 N 次提交
make check COMMITS=5

# 自动修复
make fix              # fix-lint + fix-format
make fix-format       # ruff 格式自动修复
make fix-lint         # ruff lint 自动修复
```

> `make check` 与 `make type-check` 默认操作暂存文件；传 `COMMITS=N` 改查最近 N 次提交。

### 9.7.2 类型检查

```bash
make type-check       # mypy 类型检查（暂存文件）
```

### 9.7.3 工具配置摘要

| 工具 | 配置 | 要点 |
|------|------|------|
| `ruff` | line-length=120, target=py311 | 忽略 E203；保留 magic trailing comma；双引号；docstring 内代码格式化 |
| `pylint` | py-version=3.11, max-line=120 | `print` 为 deprecated builtin；禁用多个宽松规则 |
| `mypy` | python_version=3.11 | `check_untyped_defs=true`；忽略 missing imports；宽松可选类型 |

## 9.8 性能分析

```bash
# 生成火焰图
make FLAME=script.py
# → script.py.html

# 生成 speedscope 配置
make SPEEDSCOPE=script.py
# → script.py.json，在 https://www.speedscope.app 查看

# 查看依赖树（某包被谁依赖）
make DEP=pydantic-core
```

## 9.9 可观测性部署

`deploy/observability/` 提供 Docker Compose 配置（[deploy/observability/docker-compose.yml](file:///D:/jiuwen/main/agent-core/deploy/observability/docker-compose.yml)）与说明（[deploy/observability/README.md](file:///D:/jiuwen/main/agent-core/deploy/observability/README.md)）。

安装可观测性可选依赖：

```bash
pip install "openjiuwen[observability]"
```

包含 `opentelemetry-api`/`opentelemetry-sdk`/`opentelemetry-exporter-otlp-proto-grpc`/`opentelemetry-exporter-otlp-proto-http`。

## 9.10 文档

官方文档位于 `docs/`：

| 路径 | 说明 |
|------|------|
| `docs/zh/` | 中文文档（产品简介、开发指南、API 文档、智能体、工作流、多智能体、自演进、高阶用法） |
| `docs/en/` | 英文文档 |
| `docs/dev/` | 开发文档（session/vcs 设计、文档审计） |

本地生成 autodoc（需 `docs` 组）：

```bash
uv sync --group docs
```

## 9.11 常用开发流程

```bash
# 1. 同步依赖
uv sync

# 2. 编码 ...

# 3. 暂存改动
git add <files>

# 4. 检查
make check
make type-check

# 5. 自动修复
make fix

# 6. 运行相关测试
make test TESTFLAGS="tests/unit_tests/<module>/"

# 7. 提交（仅当用户明确要求时）
git commit -m "..."
```

> 注：AI 编码助手**不应**在未获用户明确许可时提交改动。

## 9.12 示例参考

`examples/` 目录提供大量使用示例：

| 示例 | 说明 |
|------|------|
| `examples/lsp/` | LSP 智能体演示 |
| `examples/mcp/` | MCP 集成（openapi/playwright/sse/stdio/streamable_http） |
| `examples/multi_agent/` | 多智能体（hybrid/p2p/pubsub 运行时） |
| `examples/retrieval/` | 检索（chroma/milvus 查询、reranker） |
| `examples/store/` | 存储后端 |
| `examples/rl_calculator/`、`examples/rl_nl2sql/` | 强化学习 |
| `examples/MANGO/` | MANGO 基准 |
| `examples/deep_agent/` | DeepAgent CLI（start/stop/restart/verify） |
| `examples/mobile_gui/` | 移动 GUI 智能体 |
| `examples/permissions/` | 权限演示 |
| `examples/security_rail_demo/` | 安全护栏演示 |
| `examples/skill_use/`、`examples/skill_evaluate/` | 技能使用与评估 |
| `examples/context_evolver/` | 上下文演进 |
| `examples/graph_memory/` | 图记忆 |
| `examples/jiuwenrl_online/` | 在线 RL |
