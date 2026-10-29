# 运行方式

> 交叉引用: [01-项目概述](01-project-overview.md) | [02-整体架构](02-overall-architecture.md) | [14-依赖关系](14-dependencies.md)

## 一、安装

### Linux / macOS / WSL2 / Termux

```bash
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash
```

安装脚本自动检测平台、创建 venv、安装核心依赖、创建 `hermes` 命令符号链接。

### Windows 原生

```powershell
irm https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.ps1 | iex
```

### 从源码安装

```bash
git clone https://github.com/NousResearch/hermes-agent.git
cd hermes-agent
uv sync          # 安装 Python 依赖（精确锁定）
npm install      # 安装 Node 依赖
```

## 二、配置

### 配置文件

```bash
# 主配置文件
~/.hermes/config.yaml

# 凭证文件（仅限密钥，不放配置数据）
~/.hermes/.env

# 设置向导（首次使用）
hermes setup
```

配置层级：`DEFAULT_CONFIG`（内置默认）→ `~/.hermes/config.yaml`（用户覆盖）→ 命令行参数 → 环境变量（仅限密钥）。详见 [config.py](file:///D:\yaodh\main\hermes-agent\hermes_cli\config.py#L3164) 的 `load_config` 深合并。

### 凭证配置

```bash
# .env 文件（仅限密钥）
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
HERMES_PROVIDER=nous          # 或 openai/openrouter/custom
HERMES_MODEL=claude-sonnet-4-20250514

# 或使用 Nous Portal（无需 API key）
HERMES_PROVIDER=nous
```

### 多 Profile 配置

```bash
# 每个 profile 独立 HERMES_HOME
~/.hermes/           # default profile
~/.hermes-work/      # work profile
~/.hermes-personal/  # personal profile

# 通过环境变量切换
HERMES_HOME=~/.hermes-work hermes
```

## 三、CLI 入口

| 命令 | 用途 |
|------|------|
| `hermes` | 交互式 REPL（默认） |
| `hermes --tui` | Ink 终端 UI |
| `hermes gateway` | 启动消息网关（Telegram/Discord/Slack 等） |
| `hermes dashboard` | 启动 Web 仪表盘 |
| `hermes acp` | 启动 ACP 服务器（VS Code/Zed/JetBrains） |
| `hermes cron tick` | 执行一次 cron 调度 |
| `hermes doctor` | 诊断环境问题 |
| `hermes setup` | 运行设置向导 |
| `hermes completion bash` | 生成 Shell 补全 |
| `hermes backup` | 备份配置/状态 |
| `hermes import <file>` | 从备份恢复 |
| `hermes-agent "prompt"` | One-shot 模式（跑完即退出） |

详见 [main.py](file:///D:\yaodh\main\hermes-agent\hermes_cli\main.py#L11437) 入口与 [commands.py](file:///D:\yaodh\main\hermes-agent\hermes_cli\commands.py#L102) `COMMAND_REGISTRY`。

## 四、编程式使用

```python
from run_agent import AIAgent

# 创建 Agent（AIAgent 是门面，转发到 agent/ 内各模块）
agent = AIAgent(
    provider="openai",
    model="gpt-4o",
    # ... 其他配置
)

# 运行一轮对话
response = agent.run_conversation(
    user_message="帮我写一个 Python 函数",
    history=[],  # 对话历史
)

print(response)
```

> AIAgent 的 `__init__` 有 ~60 个参数（[run_agent.py](file:///D:\yaodh\main\hermes-agent\run_agent.py#L412)），大多数有默认值。常用参数：`provider`/`model`/`system_prompt`/`max_iterations`/`tools`。

## 五、测试

### 运行测试

```bash
# 全量测试套件（必须用 wrapper，不要直接 pytest）
scripts/run_tests.sh

# 单目录
scripts/run_tests.sh tests/gateway/

# 单测试文件
scripts/run_tests.sh tests/agent/test_foo.py

# 单测试函数
scripts/run_tests.sh tests/agent/test_foo.py -k test_bar
```

> `run_tests.sh` 用 `env -i` 起空环境再 opt-in 凭据，确保测试隔离。详见 [run_tests.sh](file:///D:\yaodh\main\hermes-agent\scripts\run_tests.sh#L152-L183)。

### 测试分层

| marker | 用途 |
|--------|------|
| （默认） | 单元测试，快、无外部依赖 |
| `@pytest.mark.integration` | 集成测试，需外部服务 |
| `@pytest.mark.ssh` | 需要 SSH 环境 |
| `@pytest.mark.linux_only` | 仅 Linux |
| `@pytest.mark.macos_only` | 仅 macOS |
| `@pytest.mark.windows_only` | 仅 Windows |
| `@pytest.mark.requires_wal` | 需要 WAL 模式 SQLite |
| `@pytest.mark.no_isolate` | 跳过 per-file 子进程隔离 |

### 压力测试

```bash
# 压力测试默认被跳过（不在 CI 中执行）
pytest tests/stress/ --no-header -q
```

## 六、代码质量

### Python Lint

```bash
# ruff 阻塞门禁（当前仅 PLW1514）
ruff check . --select PLW1514

# 全量 lint（建议非阻塞）
ruff check .

# 类型检查（当前 --exit-zero 建议）
ty check
```

### TypeScript Lint

```bash
# 各 workspace 的 eslint
npm run --ws lint

# 各 workspace 的 typecheck
npm run --ws check
```

### 构建前端

```bash
# TUI 构建
cd ui-tui && npm run build

# Web 仪表盘构建（产物输出到 hermes_cli/web_dist）
cd web && npm run build

# Desktop 构建
cd apps/desktop && npm run build
```

### Docker

```bash
docker build -t hermes-agent .
docker run -it --rm \
  -e OPENAI_API_KEY=sk-... \
  -v ~/.hermes:/root/.hermes \
  hermes-agent
```

## 七、小结

1. 一行命令安装（curl bash / irm iex），跨平台支持 Linux/macOS/WSL/Termux/Windows
2. 配置分层：DEFAULT_CONFIG → config.yaml → CLI → .env（仅密钥）
3. 多 Profile 隔离：每个 HERMES_HOME 独立配置/状态/凭证
4. 测试必须用 `scripts/run_tests.sh`（env -i 空环境 + per-file 子进程隔离）
5. 代码质量：ruff（Python lint）+ eslint（TS lint）+ ty（Python 类型检查）
