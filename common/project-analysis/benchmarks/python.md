---
tech: python
---

# Python 生态标杆项目

> 本文件供 `project-analysis` 对标模式使用。每个标杆记录「看哪些目录/配置」与「浅/深对标提示」。
> **仓库地址与 star 数会变动，AI 对标前应 `git ls-remote` 或 WebSearch 核实现状。**

## FastAPI

- 仓库: https://github.com/tiangolo/fastapi
- 类型: 框架(Web)
- 亮点维度: 易用性 / 文档完备度 / 可测试性 / 可扩展性
- 对标要点:
  - 看 `fastapi/` 核心包 — routing、dependencies(依赖注入)、params
  - 看 `fastapi/routing.py` — 路由与依赖注入设计
  - 看 `fastapi/openapi/` — 自动 OpenAPI 文档生成(文档完备度范本)
  - 看 `tests/` — TestClient 与测试体系(可测试性范本)
  - 看 `pyproject.toml` — 依赖与构建配置
- 浅对标源: https://fastapi.tiangolo.com/ (文档极全,中文化好)
- 深对标提示: clone 后读 `dims/usability.md` 比 API 易用; 读 `dims/testability.md` 比 TestClient

## Django

- 仓库: https://github.com/django/django
- 类型: 框架(Web, 全栈)
- 亮点维度: 架构约束 / 安全性 / 可扩展性 / 文档完备度 / 复用性
- 对标要点:
  - 看 `django/db/` — ORM 与模型层(MTV 架构约束范本)
  - 看 `django/contrib/` — 可插拔应用(admin/auth/sessions,可扩展性范本)
  - 看 `django/middleware/` 特别是 `security.py` 与 `csrf.py` — 安全防护(CSRF/XSS/SSL/HSTS)
  - 看 `django/core/` — 核心与请求处理
  - 看 `docs/` — 文档体系
- 浅对标源: https://docs.djangoproject.com/ (官方文档标杆级)
- 深对标提示: clone 后读 `dims/arch-rules.md` 比 MTV 分层; 读 `dims/security.md` 比内置安全中间件

## LangChain

- 仓库: https://github.com/langchain-ai/langchain
- 类型: 框架(LLM 应用)
- 亮点维度: 可扩展性 / 可观测性 / 复用性
- 对标要点:
  - 看 `libs/langchain/langchain/` — 核心抽象(chains/agents/tools)
  - 看 `libs/langchain/langchain/agents/` 与 `chains/` — 编排抽象(可扩展性范本)
  - 看 `libs/langchain/langchain/tools/` — 工具扩展点
  - 看 LangSmith/LangGraph 集成 — 可观测性与编排
- 浅对标源: https://python.langchain.com/ / README
- 深对标提示: clone 后读 `dims/extensibility.md` 比抽象与扩展点; 读 `dims/observability.md` 比 LangSmith 集成

## Celery

- 仓库: https://github.com/celery/celery
- 类型: 库(异步任务队列)
- 亮点维度: 可靠性 / 可观测性 / 可扩展性
- 对标要点:
  - 看 `celery/app/` — 应用与配置
  - 看 `celery/app/trace.py` — 任务追踪与重试(可靠性范本)
  - 看 `celery/concurrency/` — 并发策略
  - 看 Flower 集成 / `celery/app/control.py` — 监控(可观测性)
- 浅对标源: https://docs.celeryq.dev/ / README
- 深对标提示: clone 后读 `dims/reliability.md` 比重试与容错; 读 `dims/observability.md` 比 Flower 监控

## requests

- 仓库: https://github.com/psf/requests
- 类型: 库(HTTP)
- 亮点维度: 易用性 / 文档完备度 / 复用性
- 对标要点:
  - 看 `src/requests/` — 主包(models/sessions/adapters)
  - 看 `src/requests/models.py` 与 `sessions.py` — API 设计("HTTP for Humans",易用性范本)
  - 看 `src/requests/adapters.py` — 传输适配(可扩展性)
  - 看 `docs/` — readthedocs 文档(文档完备度范本)
- 浅对标源: https://requests.readthedocs.io/ / README
- 深对标提示: clone 后读 `dims/usability.md` 比 API 易用性; 读 `dims/documentation.md` 比文档体系

## Pydantic

- 仓库: https://github.com/pydantic/pydantic
- 类型: 库(数据验证)
- 亮点维度: 易用性 / 性能 / 可测试性
- 对标要点:
  - 看 `pydantic/` — 主包(main/fields/json_schema)
  - 看 `pydantic/main.py` — BaseModel 设计
  - 看 `pydantic-core/` — Rust 内核(性能范本,验证核心)
  - 看 `tests/` — 测试体系与基准
- 浅对标源: https://docs.pydantic.dev/ / README
- 深对标提示: clone 后读 `dims/performance.md` 比 Rust 内核; 读 `dims/usability.md` 比类型驱动 API

---

## 选用指引（按想对标的维度选标杆）

| 想对标的维度 | 首选标杆 | 看什么 |
|--------------|---------|--------|
| 易用性/API 设计 | FastAPI, requests, pydantic | "for Humans" 设计与类型驱动 |
| 文档完备度 | FastAPI, Django, requests | 自动 OpenAPI / 官方文档 |
| 架构约束/分层 | Django | MTV 与 contrib 分层 |
| 安全性 | Django | csrf/security 中间件 |
| 可扩展性/插件 | FastAPI, Django, LangChain | 依赖注入/contrib/agents 抽象 |
| 可靠性/容错 | Celery | 任务重试与追踪 |
| 可观测性 | Celery, LangChain | Flower/LangSmith 集成 |
| 性能 | Pydantic | Rust 内核 pydantic-core |
| 可测试性 | FastAPI, pydantic | TestClient/测试基准 |
| 复用性 | Django, requests | contrib 可插拔/通用库 |

## 补充流程

新发现优秀 Python 项目时，按上述条目格式(项目名/仓库/类型/亮点维度/对标要点/浅对标源/深对标提示)追加到本文件，并更新「选用指引」表。
