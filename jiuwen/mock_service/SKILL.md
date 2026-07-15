---
name: mock-service
description: "JiuwenTest mock_service 运维操作 — 依赖安装、启动、停止、重启、状态检查、健康验证"
execution:
  mode: local
  language: shell
  timeout: 120
  entrypoint: ops.sh
  environment:
    MOCK_VENV: "/home/luffy/projects/gitcode/.venv"
    MOCK_SERVICE_SRC: "/home/luffy/projects/gitcode/JiuwenTest/mock_service"
    MOCK_LOG_DIR: "/home/luffy/projects/gitcode/JiuwenTest/logs"
---

# Mock Service 运维操作

## 概述

本 Skill 提供 JiuwenTest mock_service 的完整运维命令集，用于管理5个 mock 服务的生命周期。

mock_service 包含5个服务，用于 agent-core 和 agent-core-java 的集成测试：

| 服务 | 端口 | 类型 | 说明 |
|------|------|------|------|
| weather_reporter | 8000 | FastAPI/uvicorn | 模拟天气查询 HTTP API |
| mockllm | 8088 | FastAPI/uvicorn | 模拟大模型返回（按 query 匹配 JSON） |
| mcp_sse_server | 8188 | FastMCP SSE | MCP SSE 工具服务（加法+天气） |
| mcp_sse_server2 | 8189 | FastMCP SSE | MCP SSE 工具服务（乘法+消息） |
| mcp_sse_server3 | 8190 | FastMCP SSE | MCP SSE 工具服务（空工具） |

**源码位置**：`/home/luffy/projects/gitcode/JiuwenTest/mock_service/`

## 支持的命令

| 命令 | 说明 |
|------|------|
| `install` | 安装所有 Python 依赖（含版本兼容性检查） |
| `check` | 检查依赖是否已安装（不执行安装） |
| `start` | 启动5个 mock 服务 |
| `stop` | 停止所有 mock 服务（PID文件 + 端口兜底） |
| `restart` | 先停止再启动（干净重启） |
| `status` | 查看服务运行状态 |
| `health` | 健康检查（HTTP 探测各端口） |

## 使用方式

```bash
# 首次安装依赖
./ops.sh install

# 检查依赖是否满足
./ops.sh check

# 启动服务
./ops.sh start

# 查看状态
./ops.sh status

# 停止服务
./ops.sh stop

# 干净重启
./ops.sh restart

# 健康检查
./ops.sh health
```

## ⚠️ 依赖版本兼容性经验总结（重要！）

这是在多次调试中积累的关键经验，**安装依赖时必须注意**：

### fastmcp 版本兼容性（最大坑）

| 版本 | 问题 | 结论 |
|------|------|------|
| 3.x | `FastMCP()` 不再接受 `host`/`port` 参数 | ❌ 不可用 |
| 2.14.7 | 内部 `auth.py` 有 bug：`PrivateKeyJWTClientAuthenticator` 缺失 | ❌ 不可用 |
| 2.14.x | 可能继承 2.14.7 的 bug | ⚠️ 不推荐 |
| 2.10.0 | 缺 `mcp_config` 模块 | ❌ 不可用 |
| 2.3.5 | 缺 `mcp_config` 模块 | ❌ 不可用 |
| 2.7.1 | 缺 `mcp_config` 模块 | ❌ 不可用 |
| 2.9.2 | 与 mcp 1.9.4 不兼容 | ❌ 不可用 |
| **2.13.3** | **稳定可用**，host/port 有 deprecation warning 但功能正常 | ✅ **推荐** |

**锁定版本**：`fastmcp>=2.13.3,<2.14.0`

### pydantic 版本兼容性

- fastmcp 2.13.3 需要 `pydantic>=2.0`
- `pydantic-settings` 版本不能太新（否则与 fastmcp 冲突）
- 当前稳定组合：`pydantic==2.13.4` + `pydantic-settings==2.14.2`

### mockllm 依赖注意

- `python-json-logger`：**包名**是 `python-json-logger`，**import 名**是 `pythonjsonlogger`
  ```python
  from pythonjsonlogger.json import JsonFormatter  # ✅ 正确
  ```
- `tiktoken`：OpenAI token 计数库，mockllm 必需

### 完整依赖清单

```
# 核心依赖（weather_reporter + mockllm）
fastapi>=0.68.0
uvicorn>=0.15.0
pydantic>=2.0,<3.0
starlette

# mockllm 专用
python-json-logger>=2.0.0
pyyaml>=5.4.1
watchdog>=2.1.0
tiktoken>=0.9.0
click>=8.1.7
httpx>=0.24.0

# MCP 服务依赖
fastmcp>=2.13.3,<2.14.0   # ⚠️ 版本锁定！
mcp>=1.0
```

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `MOCK_VENV` | `/home/luffy/projects/gitcode/.venv` | Python venv 路径 |
| `MOCK_SERVICE_SRC` | `/home/luffy/projects/gitcode/JiuwenTest/mock_service` | mock_service 源码路径 |
| `MOCK_LOG_DIR` | `/home/luffy/projects/gitcode/JiuwenTest/logs` | 日志输出目录 |

## 服务架构

```
agent-core / agent-core-java (测试用例)
    │
    ├── http://127.0.0.1:8000  ← weather_reporter (FastAPI)
    ├── http://127.0.0.1:8088  ← mockllm (FastAPI)
    ├── http://127.0.0.1:8188  ← mcp_sse_server (FastMCP SSE)
    ├── http://127.0.0.1:8189  ← mcp_sse_server2 (FastMCP SSE)
    └── http://127.0.0.1:8190  ← mcp_sse_server3 (FastMCP SSE)
```

## 调试技巧

1. **启动失败**：先 `./ops.sh status` 查看哪些服务没起来，再查看对应日志
2. **端口冲突**：`./ops.sh stop` 清理残留，再 `./ops.sh start`
3. **依赖问题**：`./ops.sh check` 检查依赖，特别注意 fastmcp 版本
4. **日志查看**：日志在 `JiuwenTest/logs/` 下，按服务分目录
5. **干净重启**：`./ops.sh restart` = stop + start，推荐用这个

## 注意事项

1. **venv 必须先创建**：如果 `.venv` 不存在，先 `python3 -m venv .venv`
2. **fastmcp 版本必须锁定**：不要随意升级 fastmcp，2.14.x 有 bug
3. **MCP 服务日志**：MCP 服务通过 `--log` 参数指定日志路径
4. **mockllm 日志追加模式**：注意旧日志中可能有之前的错误信息，不要被误导
