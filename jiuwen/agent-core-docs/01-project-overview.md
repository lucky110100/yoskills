# 01 - 项目概述

## 1.1 项目定位

**openJiuwen Core**（包名 `openjiuwen`）是一个面向大语言模型（LLM）应用的 Python SDK，为运行在 openJiuwen 框架上的智能体（Agent）提供高性能运行时。它不仅封装了多层次的易用开发接口，还内置了支持异步 IO 与流式处理的高性能运行时引擎，可实现智能体状态保存与中断恢复，并配备提示词自动优化、提示词生成、全链路可观测性等调试与优化工具。

> 本仓库（`agent-core`）即 `openJiuwen Core` 的开源实现，包名 `openjiuwen`，版本见 [pyproject.toml](file:///D:/jiuwen/main/agent-core/pyproject.toml)（当前 `0.1.16`）。

## 1.2 核心能力

### SDK 接口层

聚焦大语言模型应用开发需求，提供覆盖以下场景的 Python SDK 接口：

- 智能体实例创建（`ReActAgent`、`WorkflowAgent`、`DeepAgent`）
- 工作流设计与编排（`Workflow`、组件、连接）
- LLM 调用与输出结果解析（`Model`、`LLMComponent`）
- 提示词模板构建与动态填充（`PromptTemplate`、`SystemPromptBuilder`）
- 本地工具调用外部服务（`Tool`、`MCP`）

### 智能体引擎

针对两大场景：**ReAct 智能交互**与**工作流自动跳转**，提供：

- 智能体控制器（`Controller`、`TaskLoopController`）
- 复杂任务规划、工具选择与调用
- 工作流任务切换
- 内置标准化组件，降低智能体开发门槛
- 智能体运行环境（`Session`、`ContextEngine`）
- 会话历史上下文管理与基础工具集

### 高性能执行引擎

支持分布式部署与低成本运行，核心特性：

- **异步并行图执行器**：组件并发执行、异步 IO 处理、结构化上下文管理
- **组件基础能力**：批量与流式传值、动态跳转、状态中断与恢复、动态配置与多实例管理
- **数据存储与流式处理**：流式输出与传输、外部存储系统对接

### 调试与优化工具

- 提示词自动优化（`agent_evolving`、`dev_tools/tune`）
- 提示词生成
- 全链路可观测性（`deploy/observability`、OpenTelemetry）
- 自演进能力（`agent_evolving`、`rsi`）

## 1.3 主要特性

### Agent 编排

内置两类预置智能体：

- **ReActAgent**：遵循 ReAct（Reasoning + Action）规划范式，通过"思考 → 行动 → 观察"的迭代循环完成任务。具备多轮推理与自我修正能力，适合需要复杂推理与策略调整的场景。
- **WorkflowAgent**：聚焦多步骤任务导向的流程自动化，严格按用户预定义流程高效执行复杂任务，并可在用户意图变化时灵活切换任务。适合任务结构清晰、可分解为多步骤的场景。
- **DeepAgent**（`harness` 层）：高级智能体，封装内部 `ReActAgent` 并叠加外层任务循环、热重配、插件热加载、子智能体编排等能力。

### 多工作流跳转

支持智能体在同一会话中管理多个工作流，允许用户在不同工作流间自由切换，并通过框架确保中断工作流的检查点恢复。

### 提示词开发与优化

输入需求即可一键生成合适提示词，结合真实场景数据集进行自动优化迭代，帮助快速产出高质量提示词。

### 多智能体团队

`agent_teams` 模块提供完整的团队编排框架，支持 Leader + Teammates + 人机交互（HITT）+ Bridge 成员协作模式，通过共享任务看板、消息总线和协调事件系统实现多智能体协同。

### 自演进与评估

`agent_evolving` 与 `rsi` 模块提供训练循环、评估器、优化器、轨迹抽取、检查点、信号检测与 RL 训练原语，支持智能体技能、指令、经验的迭代优化。

## 1.4 设计目标

openJiuwen Core 在灵活性与稳定性之间取得平衡，帮助开发者高效构建稳定的大语言模型应用：

| 目标 | 说明 |
|------|------|
| **开箱即用** | 提供丰富的预置组件（意图识别、提问器、LLM 调用、工具组件等），显著降低开发门槛 |
| **高效准确** | 高性能执行引擎支持异步并行图执行、组件并发、流式处理 |
| **灵活可控** | 多工作流跳转、可中断恢复、热重配、插件热加载 |
| **可观测** | 全链路追踪、日志、指标，支持 OpenTelemetry |
| **安全** | 工具权限防护、文件守卫、安全护栏（Guardrail） |

## 1.5 适用场景

- 复杂推理与策略调整场景（ReActAgent）
- 任务结构清晰的流程自动化场景（WorkflowAgent）
- 编码与工程任务（DeepAgent + 代码/研究/浏览器子智能体）
- 多智能体协作（agent_teams）
- 智能体能力自演进与优化（agent_evolving + rsi）

## 1.6 技术栈概览

| 维度 | 技术选型 |
|------|----------|
| 语言 | Python 3.11+（< 3.14） |
| 异步 | `asyncio` / `anyio` |
| 数据校验 | `pydantic`、`sqlmodel`、`sqlalchemy[asyncio]` |
| LLM | `openai`、`dashscope`、`transformers`、`tiktoken` |
| 向量库 | `pymilvus`、可选 `chromadb`/`pgvector` |
| MCP | `fastmcp`、`mcp` |
| 文档处理 | `beautifulsoup4`、`trafilatura`、`pdfplumber`、`python-docx`、`openpyxl` |
| CLI/TUI | `click`、`prompt_toolkit`、`rich` |
| 可观测性 | `opentelemetry-*`、`loguru` |
| 包管理 | `uv`（推荐）、`setuptools` |
| 测试 | `pytest`、`pytest-asyncio` |
| 代码质量 | `ruff`、`pylint`、`mypy`、`codespell` |

## 1.7 仓库结构概览

```
agent-core/
├── openjiuwen/                 # 主源码包
│   ├── core/                   # 公共 SDK/运行时（引擎层）
│   ├── harness/                # 编码智能体框架（DeepAgent）
│   ├── agent_teams/            # 多智能体团队框架
│   ├── agent_evolving/         # 智能体自演进/优化
│   ├── dev_tools/              # 开发者调优工具
│   ├── extensions/             # 可选集成（A2A 等）
│   ├── rsi/                     # 评估与优化框架
│   ├── symphony/                # 能力资产发现与编排
│   └── auto_harness/           # 兼容性重导出（已迁入 rsi）
├── examples/                   # 用户级使用示例
├── tests/                      # 测试（unit_tests / system_tests / cli）
├── docs/                       # 官方文档（中英文）
├── deploy/                     # 部署配置（可观测性）
├── pyproject.toml              # 项目元数据与依赖
├── Makefile                    # 通用 lint/test 入口
├── README.md / README.zh.md    # 项目说明
├── AGENTS.md / CLAUDE.md       # AI 协作指令
└── .claude/                    # 规则与技能定义
```

详细的模块职责、关键类与函数说明请参见后续文档。
