# 依赖关系

> 交叉引用: [01-项目概述](01-project-overview.md) | [02-整体架构](02-overall-architecture.md) | [15-运行方式](15-running-guide.md)

## 一、内部依赖图

Hermes Agent 的内部依赖遵循"核心窄腰部、能力在边缘"原则，依赖方向严格自顶向下：

```
cli.py (HermesCLI)
  └─→ hermes_cli/ (子命令、配置、皮肤、补全)
        └─→ run_agent.py (AIAgent 门面)
              ├─→ agent/ (对话循环、provider 适配、内存、错误恢复)
              │     └─→ tools/registry.py (工具注册中心，零依赖)
              │           └─→ tools/*.py (各工具实现，自注册)
              ├─→ model_tools.py (工具编排：dispatch + schema)
              │     └─→ tools/registry.py
              └─→ gateway/run.py (消息网关)
                    ├─→ gateway/platforms/base.py (平台适配器 ABC)
                    ├─→ gateway/session.py (会话存储)
                    └─→ gateway/stream_events.py (流事件契约)

providers/ (推理后端 Profile)
  └─→ plugins/model-providers/ (provider 插件，自注册)

tui_gateway/ (TUI 后端)
  └─→ agent/ + hermes_cli/ (复用核心)

cron/ (调度)
  └─→ hermes_constants.py (公共常量，零依赖)
```

**关键约束**（见 [AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L339-L349)）：`registry` → `tools` → `model_tools` → `run_agent` 的 import 链是 circular-import safe 的——registry 不 import 任何 tools/ 模块，tools/ 各文件只 import registry 单例。

## 二、外部依赖表（Python 核心）

| 依赖 | 版本 | 锁定策略 | 用途 |
|------|------|----------|------|
| openai | 2.24.0 | `==` 精确 | LLM API 客户端 |
| pydantic | 2.13.4 | `==` 精确 | 数据校验与序列化 |
| fastapi | 0.133.1 | `==` 精确 | Web 仪表盘后端 |
| uvicorn | 0.35.0 | `==` 精确 | ASGI 服务器 |
| httpx | 0.28.1 | `==` 精确 | HTTP 客户端 |
| Pillow | 12.3.0 | `==` 精确 | 图像处理 |
| PyYAML | 6.0.2 | `==` 精确 | 配置文件解析 |
| aiohttp | 3.14.3 | `>=3.14.3,<4` | 异步 HTTP（修 CVE） |
| cryptography | 50.0.0 | `>=50,<51` | 加密（修 6 项 CVE） |
| urllib3 | 2.7.0+ | `>=2.7.0,<3` | HTTP 传输层 |
| anthropic | 0.87.0 | `==` 精确 | Anthropic API（修 CVE） |
| starlette | 1.3.1 | `==` 精确 | ASGI 框架（修 BadHost） |
| defusedxml | 0.7.1 | `==` 精确 | XML 安全解析（WeCom XXE） |
| websockets | 15.0.1 | `==` 精确 | WebSocket 通信 |
| requests | 2.32.4 | `==` 精确 | HTTP 客户端（修 CVE-2026-25645） |
| PyJWT | 2.13.0 | `==` 精确 | JWT（修 PYSEC） |

> 完整依赖列表见 [pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L18-L132)。每个核心依赖都有 CVE/why 注释。

## 三、外部依赖表（TypeScript/Node）

| 依赖 | 用途 |
|------|------|
| react 19 | UI 框架（web + desktop） |
| ink | 终端 UI 框架（ui-tui，自研 @hermes/ink） |
| @nanostores/react | 原子状态管理（三前端共用） |
| @tanstack/react-query | 服务器态缓存（web + desktop） |
| vite | 构建工具（web + desktop） |
| xterm.js | 终端模拟器（web ChatPage 内嵌 TUI） |
| electron | 桌面应用框架（desktop） |
| rollup | 打包工具 |

## 四、可选依赖组（pyproject.toml extras）

项目有 30+ 可选依赖组（[pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L185-L260)），按需安装：

| extra | 包含 | 用途 |
|------|------|------|
| desktop | electron 相关 | 桌面应用构建 |
| otlp | opentelemetry | OTLP 指标/追踪导出 |
| mcp | mcp SDK | MCP 工具支持 |
| nous | nous portal SDK | Nous Portal provider |
| bedrock | boto3 | AWS Bedrock provider |
| vertex | google-auth | Google Vertex provider |
| vision | Pillow 增强 | 图像理解 |
| tts | ElevenLabs SDK | 语音合成 |
| stt | faster-whisper | 语音识别 |
| browser | playwright | 浏览器工具 |
| ... | ... | ... |

## 五、入口点

| 入口 | 命令 | 模块 | 用途 |
|------|------|------|------|
| hermes | `hermes` | `hermes_cli.main:main` | 主 CLI（交互/网关/TUI/ACP） |
| hermes-agent | `hermes-agent` | `run_agent:main` | 编程式 Agent（one-shot） |
| hermes-acp | `hermes acp` | `acp_adapter.entry:main` | ACP 服务器（编辑器集成） |
| hermes-tui-gateway | `python -m tui_gateway.entry` | `tui_gateway.entry:main` | TUI 后端（stdio JSON-RPC） |

## 六、依赖锁定策略

| 策略 | 实现 | 证据 |
|------|------|------|
| 核心依赖精确 `==` | 所有核心包 `==X.Y.Z` | [pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L18-L37) |
| 上界 `>=floor,<next_major` | 非核心包设上界 | AGENTS.md Dependency Pinning Policy |
| Git URL 用 SHA | 40 字符 commit hash | [pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml) |
| GitHub Actions 用 SHA | SHA + 注释来源 | [.github/workflows/](file:///D:\yaodh\main\hermes-agent\.github\workflows) |
| override-deps 修补 CVE | pynacl<1.6, cryptography<49 | [pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L370-L383) |
| exclude-newer 隔离窗口 | 14 天供应链隔离 | [pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L384-L389) |
| dep-bounds CI 门禁 | 无上界 PyPI 依赖直接 fail | supply-chain-audit.yml |
| lazy-install 安全模型 | venv 作用域 + allowlist + sys.path 末尾 | [lazy_deps.py](file:///D:\yaodh\main\hermes-agent\tools\lazy_deps.py#L25-L66) |
| 双 lockfile | uv.lock + package-lock.json | [uv.lock](file:///D:\yaodh\main\hermes-agent\uv.lock) |

## 七、小结

1. 内部依赖严格自顶向下，registry→tools→model_tools→run_agent 链 circular-import safe
2. 核心依赖精确 `==` 锁定，其余 `>=floor,<next_major` 上界
3. 30+ 可选依赖组按需安装，不污染核心 venv（lazy_deps 安全模型）
4. override-deps 修补上游未发版的转译依赖 CVE
5. `exclude-newer = "14 days"` 供应链隔离窗口 + dep-bounds CI 门禁
