# 11 运行方式

> 交叉引用: [01-项目概述](01-project-overview.md) | [02-整体架构](02-overall-architecture.md) | [09-instance-manager与jiuwenbox](09-instance-manager-and-jiuwenbox-module.md) | [10-依赖关系](10-dependencies.md)

## 一、能力概述

JiuwenSwarm 提供从「一行安装」到「多实例并行」的完整运行链路。安装形态覆盖三类:桌面安装包(Windows/macOS,openjiuwen.com 下载)、命令行 `pip install jiuwenswarm`(国内推荐清华镜像)、源码 `git clone` + `uv` / `pip install -e ".[test]"`。运行入口由 [start_services](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/start_services.py#L1022) 的 `main` 统一编排,支持 `all`(默认)/`web`/`app`/`dev` 四种模式,并通过 `--name/--list/--status/--stop/--restart` 提供命名实例的全生命周期管理。

运行时的核心机制是「**双进程编排 + 端口自分配 + 冲突自动回退**」。[app.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/app.py#L49) 的 `main` 用 `subprocess.Popen` 拉起 `jiuwenswarm.server.app_agentserver` 与 `jiuwenswarm.gateway.app_gateway` 两个子进程(冻结态改用 `--desktop-run-agent/--desktop-run-gateway` flags),端口按 `base + index * 1000` 分配(BASE_PORTS:agent_server=18092 / web=19000 / gateway=19001 / frontend=5173),Docker 环境变量可覆盖,双栈(IPv4+IPv6)探测,冲突时扫描 `scan_range=10` 寻找可用端口组并持久化回 `.env`/`instances.yaml`。配置层以工作区(`~/.jiuwenswarm` 包模式或仓库根源码模式)为根,经 `get_config`(缓存+重试+环境变量替换)读取 `config.yaml`,多实例由 [bootstrap](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/instance_manager/bootstrap.py#L32) 生成每实例独立 `.env`。

## 二、入口与命令清单

| 命令 | 模块/函数 | 说明 |
| --- | --- | --- |
| `jiuwenswarm-init` | [run_init](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/init_workspace.py#L44) / [script](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L125) | 首次初始化工作区,复制 config/.env/agent 模板;`-f` 强制重建;`--name <n>` 建命名实例 |
| `jiuwenswarm-start [mode]` | [main](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/start_services.py#L1022) / [script](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L124) | 启动服务,mode: all(默认)/web/app/dev |
| `jiuwenswarm-start --name <n>` | [_start_named_instance](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/start_services.py#L874) | 启动命名实例(写 PID 文件 + bootstrap .env) |
| `jiuwenswarm-start --list` | [_action_list](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/start_services.py#L766) | 列出全部实例及状态 |
| `jiuwenswarm-start --status <n>` | [_action_status](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/start_services.py#L790) | 查看指定实例详情 |
| `jiuwenswarm-start --stop <n>` | [_action_stop](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/start_services.py#L808) | 停止运行中实例 |
| `jiuwenswarm-start --restart <n>` | [_action_restart](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/start_services.py#L833) | 停止后重启(支持指定 mode) |
| `jiuwenswarm-app` | [app.main](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/app.py#L49) / [script](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L120) | 编排 AgentServer + Gateway 双子进程 |
| `jiuwenswarm` | [cli.main](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/cli/main.py#L15) → [run_chat](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/cli/chat.py#L1083) | 主 CLI,经 [GatewayClient](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/cli/gateway_client.py#L35) 连 `/tui` 流式对话;`--render human/json/jsonl` |
| `jiuwenswarm-tui` | [optional tui](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L102) | 终端 UI(本地路径包) |
| `jiuwenbox-server` | [launcher.main](file:///D:/jiuwen/main/jiuwenbox/src/jiuwenbox/server/launcher.py#L222) / [script](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L130) | jiuwenbox 沙箱服务(`--listen/--api-token`) |

辅助函数:[InstanceCommand](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/start_services.py#L72)(实例统一基类)、[_build_commands](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/start_services.py#L449)(按 mode 组装命令)、[_start_process](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/start_services.py#L489)(注入端口环境变量)、[_resolve_ports_with_fallback](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/start_services.py#L223)(冲突回退)、[_run](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/start_services.py#L731)(默认实例路径)、[get_user_workspace_dir](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/utils.py#L396)(工作区根)、[get_env_file](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/utils.py#L1685)(.env 路径)、[is_package_installation](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/utils.py#L1700)(包/源码模式判定)、[BASE_PORTS](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/instance_manager/config.py#L42)、[compute_auto_port](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/instance_manager/config.py#L161)、[find_available_ports](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/instance_manager/config.py#L382)、[create_bootstrap_env](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/instance_manager/bootstrap.py#L32)。

## 三、实现机制

### 启动时序

`jiuwenswarm-start` 从 CLI 到服务就绪的完整链路如下:

```
jiuwenswarm-start [mode] [--name <n>]
        │
        ▼
parse_dotenv_early(--dotenv <path>)          # 命名实例:提前解析 bootstrap .env
        │
        ▼
InstanceCommand(name).validate_and_load()    # 校验名 → 加载 instances.yaml → 取状态
        │  default: 合成 config(端口=compute_auto_port(idx 0))
        │  named:  get_instance_config(name) + get_instance_status
        ▼
check_ports_conflicts()                       # 双栈探测 127.0.0.1 / ::1
        │
        ├─ 无冲突 ─► _sync_default_env_ports() # 默认实例:同步 .env(防历史残留)
        │              │
        └─ 有冲突 ─► _resolve_ports_with_fallback(scan_range=10)
                          │  find_available_ports(base_index, exclude_ports)
                          │  命中 → 更新 config.ports + 持久化(.env / instances.yaml)
                          └─ 未命中 → 返回 1,给出 netstat/lsof 排查提示
        ▼
_build_commands(mode)                         # all/app/dev → [python -m jiuwenswarm.app]
                                              # web       → [python -m ...app_web]
                                              # dev       → [npm run dev](源码模式)
        ▼
_run_instance_with_pid / _run_processes
        │
        ├─ _start_process: 注入 AGENT_SERVER_PORT/WEB_PORT/GATEWAY_PORT/FRONTEND_PORT
        │                  + CLI_PORTS_ENV_FLAG 锁定(防 load_dotenv 覆盖)
        ├─ write_pid_file(config, pid, ts)
        ├─ _wait_for_services_ready: 双栈探活 + Web UI banner(就绪即打印访问 URL)
        └─ 轮询 poll(),任一退出即返回退出码
        ▼
app.py main(子进程)                            # 见下方双进程编排
        ├─ agent_cmd  = [python, -m jiuwenswarm.server.app_agentserver, --dotenv ...]
        └─ gateway_cmd= [python, -m jiuwenswarm.gateway.app_gateway,  --dotenv ...]
        (PyInstaller frozen: 改用 --desktop-run-agent / --desktop-run-gateway)
```

### 双进程编排

[app.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/app.py#L49) 是 `all/app/dev` 模式下的实际编排者。它先在模块导入期执行 [parse_dotenv_early](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/app.py#L17)(命名实例的 bootstrap .env),再 [load_dotenv_runtime](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/app.py#L45) 读取 `~/.jiuwenswarm/config/.env`(`override=True`),最后用 `subprocess.Popen` 依次拉起 AgentServer 与 Gateway(L86–L87)。冻结态用 flags 代替 `-m`,因为 PyInstaller 打包后 `python -m` 不可用。任一子进程异常则终止另一个,统一返回退出码。

### 进程生命周期与信号

`main` 在入口注册 `SIGTERM` 为默认中断处理;[_run_instance_with_pid](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/start_services.py#L408) 与 `_run_processes` 在收到 `KeyboardInterrupt`(返回码 130)时经 `_terminate_processes` 先 `terminate`,8 秒内未退出再 `kill`,保证 AgentServer 与 Gateway 同生同灭,避免端口与 PID 文件残留。子进程退出码经 `proc.poll()` 轮询上抛,父进程统一返回首个非零码。

### 端口分配与冲突回退

端口模型由 [BASE_PORTS](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/instance_manager/config.py#L42) 基线 + [compute_auto_port](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/instance_manager/config.py#L161)(`base + index * 1000`)构成。Docker 环境下,`_resolve_runtime_ports` 读取 `AGENT_SERVER_PORT/WEB_PORT/GATEWAY_PORT/FRONTEND_PORT` 覆盖基线。冲突时 [_resolve_ports_with_fallback](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/start_services.py#L223) 以实例自身 index 为起点,排除其他实例已占用端口,在 `scan_range=10` 范围内扫描首个完全可用端口组;命中后写回 `.env`(默认实例)或 `instances.yaml + bootstrap .env`(命名实例),并打印 TUI/CLI 连接提示。该持久化是强制的:失败即中止启动,避免子进程读到陈旧端口而 `bind` 崩溃。

### 配置体系

工作区根由 [get_user_workspace_dir](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/utils.py#L396) 决定:包模式为 `~/.jiuwenswarm`,源码模式为仓库根;[get_env_file](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/utils.py#L1685) 返回对应 `.env`。`config.yaml` 经 `get_config`(缓存 + 重试 + 环境变量替换)读取,`.env.template` 提供变量样板,`instances.yaml` 记录命名实例清单。命名实例由 [create_bootstrap_env](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/instance_manager/bootstrap.py#L32) 生成独立 `.env`,注入 `JIUWENSWARM_DATA_DIR` / `JIUWENSWARM_INSTANCE` 与端口,`--dotenv <path>` 串起整条链路。

### 模型配置

JiuwenSwarm 支持多推理后端,在 `config.yaml` 的 model 区段声明,运行时由 `get_config`(缓存 + 重试 + 环境变量替换)解析,凭据与端点经 `.env` 注入,实现「配置与密钥分离」。

| 后端 | 说明 |
| --- | --- |
| 华为云 MaaS | 默认推荐,华为云模型即服务 |
| OpenAI | 兼容 OpenAI API 协议的任一服务 |
| DeepSeek | DeepSeek 官方 |
| DashScope | 阿里云百炼 |
| SiliconFlow | 硅基流动 |
| OpenRouter | 聚合路由,单 key 多模型 |
| 本地模型 | 本地推理服务(OpenAI 兼容端点) |

`.env` 以 `JIUWENSWARM_LLM_API_KEY` / `JIUWENSWARM_LLM_BASE_URL` 等变量注入凭据,`config.yaml` 引用占位符,避免密钥落盘到版本库。

### 测试与代码质量

测试依赖由 [dependency-groups.test](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L183) 与 [optional.test](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L106) 同步声明:`pytest>=8.3.5`、`pytest-asyncio>=1.0.0`(异步用例)、`pytest-html>=4.1.1`(HTML 报告)、`pytest-mock>=3.14.0`、`pytest-cov>=7.0.0`、`coverage>=7.7.1`。约定见 `TESTING.md`,jiuwenbox 在 `tests/` 下细分 `integration` / `system_tests` / `performance` 三类用例,覆盖集成、系统与性能回归。

代码质量由 [lint](file:///D:/jiuwen/main/jiuwenswarm/pyproject.toml#L195) 组统一:`ruff>=0.11.2`(格式 + lint)、`pylint>=3.0.0`、`mypy>=1.12.0`、`codespell>=2.2.4`。贡献流程见 `docs/en/Contributing.md`,涵盖 debug 工作流、代码风格与 commit 约定;`[tool.uv]` 默认组为 `dev`(test + lint),`uv sync` 即装齐全套开发工具。

## 四、调用示例

### 安装与初始化

```bash
# 命令行安装(国内推荐清华镜像)
pip install jiuwenswarm -i https://pypi.tuna.tsinghua.edu.cn/simple

# 终端 UI(新终端使用)
pip install jiuwenswarm-tui

# 源码安装
git clone <repo> && cd jiuwenswarm
pip install -e ".[test]"      # 或 uv sync
```

### 启动各模式

```bash
jiuwenswarm-init                       # 首次初始化默认工作区
jiuwenswarm-start                      # all 模式(默认):AgentServer+Gateway+Web
jiuwenswarm-start app                  # 仅应用后端(AgentServer+Gateway)
jiuwenswarm-start web                  # 仅 Web 渠道服务
jiuwenswarm-start dev                  # 源码模式:前端 npm run dev 热更新
```

启动后访问 http://localhost:5173 打开 Web 前端。

### 多实例管理

```bash
jiuwenswarm-init --name alice          # 创建命名实例 alice
jiuwenswarm-start --name alice         # 启动命名实例(独立端口/PID/工作区)
jiuwenswarm-start --list               # 列出全部实例状态
jiuwenswarm-start --status alice       # 查看 alice 详情
jiuwenswarm-start --stop alice         # 停止 alice
jiuwenswarm-start --restart alice app # 重启 alice 为 app 模式
jiuwenswarm-start --dotenv /path/.env # 指定 bootstrap .env(多实例隔离)
```

### TUI 与 CLI

```bash
jiuwenswarm-tui                        # 新终端启动 TUI(自动读 GATEWAY_PORT)
jiuwenswarm                            # CLI 对话,--render 控制输出
jiuwenswarm --render jsonl             # 流式 JSONL 输出,便于管道处理
```

### 编程式使用

```python
# 1) 用 start_services 的 InstanceCommand 编程启动实例
from jiuwenswarm.start_services import InstanceCommand, _build_commands, _run_instance_with_pid

cmd = InstanceCommand("alice")
if cmd.validate_and_load() is None and cmd.check_workspace_exists() is None:
    cmds = _build_commands("all", cmd.config.get_bootstrap_env_path())
    _run_instance_with_pid(cmds, cmd.config)

# 2) Symphony 技能评分
from jiuwenswarm.symphony.build import build_score
score = await build_score(skill_doc=doc, rubric=rubric)

# 3) jiuwenbox 沙箱服务
from jiuwenbox.server.app import create_app
app = create_app()
```

### 启动后访问与排错

启动完成后,[_wait_for_services_ready](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/start_services.py#L591) 会打印端口 banner,Web UI 一就绪即输出访问 URL:

- Web 前端:http://localhost:5173(或回退后的 frontend 端口)
- Gateway HTTP:http://localhost:19001
- AgentServer WebSocket:ws://localhost:18092
- WebChannel WebSocket:ws://localhost:19000/ws

常见排错:端口被占用时回退日志会给出 `netstat -ano | findstr :<port>`(Windows)或 `lsof -i :<port>`(Unix)的排查命令;命名实例缺失工作区会提示 `jiuwenswarm-init --name <n>` 重建;`dev` 模式在包安装下不可用,需切到源码或改用 `app` / `web` 模式;`--restart` 仅接受 `all/app/web` 三种模式。

## 五、业界对比

| 维度 | JiuwenSwarm | Docker Compose | LangServe | Dify |
| --- | --- | --- | --- | --- |
| 启动模型 | 双子进程编排(app.py 起 AgentServer+Gateway) | 多容器声明式编排 | 单 uvicorn 进程 | 容器化全栈(api/worker/web) |
| 多实例 | 原生 `--name` 命名实例,独立工作区/端口/PID | 多 compose project 或 scale | 不支持 | 不支持(单租户) |
| 端口管理 | base+index*1000 + 冲突自动回退扫描 + 持久化 | 静态映射或随机端口 | 单端口固定 | 容器端口映射 |
| CLI/TUI | 12 个细粒度脚本 + 独立 TUI 包 | `docker compose` 命令 | 弱 CLI | Web 为主,CLI 弱 |
| 配置隔离 | 每实例独立 .env/bootstrap,Dotenv 早期解析 | 环境变量文件/compose override | .env | .env + docker volume |

## 六、小结

JiuwenSwarm 的运行方式以「**一行启动、多实例并行、双进程编排、端口自愈**」为骨架:`jiuwenswarm-init` 落地工作区,`jiuwenswarm-start` 统一调度,`app.py` 把 AgentServer 与 Gateway 拆成双子进程既隔离又同生命周期,端口按 `base+index*1000` 分配并在冲突时自动回退持久化,使一台机器可同时跑多套互不干扰的实例。相较 Docker Compose 的容器编排、LangServe 的单进程 uvicorn、Dify 的全栈容器,JiuwenSwarm 走的是「**进程级编排 + 原生多实例 + 端口自愈**」的轻量路线:无需容器即可多实例,无需手改端口即可避冲突,TUI/CLI/Web/桌面多种前端形态共享同一后端。配置层以工作区为根、bootstrap `.env` 为隔离单元,与 [10-依赖关系](10-dependencies.md) 的可选组、[09-instance-manager与jiuwenbox](09-instance-manager-and-jiuwenbox-module.md) 的多实例管理共同构成生产运行基座。
