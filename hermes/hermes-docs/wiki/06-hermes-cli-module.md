# hermes_cli 模块

> 交叉引用: [01-项目概述](01-project-overview.md) | [02-整体架构](02-overall-architecture.md) | [05-gateway模块](05-gateway-module.md) | [08-cron模块](08-cron-module.md)

## 一、模块概述

`hermes_cli/` 是 Hermes Agent 的命令行入口与中枢神经，统一承载子命令分发、设置向导、配置文件管理、皮肤主题引擎、Shell 补全生成、诊断工具、Web 仪表盘后端与 PTY 桥接。它把所有 slash 命令、CLI 子命令、设置向导步骤集中到一份 `COMMAND_REGISTRY` 单一真源，使 CLI 帮助、网关分发、Telegram/Slack 子命令映射、自动补全均派生自同一份数据，避免多处手抄表。

该模块还负责进程生命周期自愈：[main](file:///D:\yaodh\main\hermes-agent\hermes_cli\main.py#L11437) 在任何第三方 import 之前先注入 `hermes_bootstrap`、抑制 Windows `cmd /c ver` 闪屏、用 `_early_recovery` 修复被中断安装破坏的 venv，并在 one-shot 模式跳过 `atexit` 直接 `os._exit`，以规避原生扩展 finalizer 的 SIGABRT。配置层则实现深合并、版本迁移、损坏文件备份与 `${env:VAR}` SecretRef 解析，使任意老版本 `config.yaml` 都能无损升级。

## 二、关键类与函数

| 名称 | 类型 | 文件位置 | 说明 |
|------|------|----------|------|
| main | 函数 | [main.py](file:///D:\yaodh\main\hermes-agent\hermes_cli\main.py#L11437) | CLI 主入口，进程标题、UTF-8 stdio、清理 quarantine、自愈 venv |
| _run_and_exit_oneshot | 函数 | [main.py](file:///D:\yaodh\main\hermes-agent\hermes_cli\main.py#L176) | One-shot 模式：跑完即 `os._exit` 跳过原生 finalizer |
| CommandDef | dataclass | [commands.py](file:///D:\yaodh\main\hermes-agent\hermes_cli\commands.py#L46) | 单个 slash 命令定义，含 `busy_policy`/`busy_handler`/`execute` |
| COMMAND_REGISTRY | list | [commands.py](file:///D:\yaodh\main\hermes-agent\hermes_cli\commands.py#L102) | 所有 slash 命令的单一真源 |
| resolve_command | 函数 | [commands.py](file:///D:\yaodh\main\hermes-agent\hermes_cli\commands.py#L365) | 名称或别名 → CommandDef 解析器 |
| DEFAULT_CONFIG | dict | [config_defaults.py](file:///D:\yaodh\main\hermes-agent\hermes_cli\config_defaults.py#L7) | 纯数据叶子模块的默认配置树 |
| _deep_merge | 函数 | [config.py](file:///D:\yaodh\main\hermes-agent\hermes_cli\config.py#L2450) | 递归深合并：保留嵌套默认值；`None` 覆盖 dict 默认时被忽略 |
| load_config | 函数 | [config.py](file:///D:\yaodh\main\hermes-agent\hermes_cli\config.py#L3164) | 按 (mtime_ns, size) 缓存，命中返回 deepcopy |
| load_config_readonly | 函数 | [config.py](file:///D:\yaodh\main\hermes-agent\hermes_cli\config.py#L3181) | 跳过 deepcopy 的热路径变体，省 ~135us/次 |
| migrate_config | 函数 | [config.py](file:///D:\yaodh\main\hermes-agent\hermes_cli\config.py#L2165) | 版本迁移入口，含支持地坂拒绝与损坏快照备份 |
| SkinConfig | dataclass | [skin_engine.py](file:///D:\yaodh\main\hermes-agent\hermes_cli\skin_engine.py#L159) | 皮肤配置：colors/light_colors/dark_colors/spinner/branding |
| load_skin | 函数 | [skin_engine.py](file:///D:\yaodh\main\hermes-agent\hermes_cli\skin_engine.py#L892) | 用户皮肤优先 → 内置 → default 回退 |
| _walk | 函数 | [completion.py](file:///D:\yaodh\main\hermes-agent\hermes_cli\completion.py#L15) | 递归遍历 argparse 树，驱动 bash/zsh/fish 补全 |
| run_doctor | 函数 | [doctor.py](file:///D:\yaodh\main\hermes-agent\hermes_cli\doctor.py#L897) | 诊断入口；含 `--ack <id>` 静默告警快速路径 |
| PtyBridge | 类 | [pty_bridge.py](file:///D:\yaodh\main\hermes-agent\hermes_cli\pty_bridge.py#L89) | `ptyprocess` 薄封装，POSIX 专用、字节安全 I/O |
| app | FastAPI | [web_server.py](file:///D:\yaodh\main\hermes-agent\hermes_cli\web_server.py#L330) | 仪表盘后端 app，含 lifespan、host-header/token/auth 多层中间件 |

## 三、实现机制

### 3.1 单一真源 + 派生视图

`COMMAND_REGISTRY` 是唯一命令定义处，`COMMANDS`/`COMMANDS_BY_CATEGORY`/`SUBCOMMANDS`/`_COMMAND_LOOKUP` 全部由它循环构造。所有消费方（CLI 帮助、网关分发、Telegram BotCommands、Slack 映射）派生自同一份，避免漂移。

### 3.2 深合并 + 配置版本迁移

`_deep_merge` 递归保嵌套默认值，并将 YAML 解析为 `None` 的空段视为"键缺失"而非"覆盖为 None"：

```python
def _deep_merge(base: dict, override: dict) -> dict:
    result = base.copy()
    for key, value in override.items():
        if key in result and isinstance(result[key], dict) and isinstance(value, dict):
            result[key] = _deep_merge(result[key], value)
        elif key in result and isinstance(result[key], dict) and value is None:
            continue  # None 覆盖 dict 默认时被忽略（#58277）
        else:
            result[key] = value
    return result
```

`migrate_config` 引入 `SUPPORT_FLOOR_VERSION` 拒绝地坂以下版本自动迁移、对损坏 `config.yaml` 自动备份为 `.corrupt.<ts>.bak`。

### 3.3 数据驱动皮肤 + 多端一致

`SkinConfig` 把 CLI/TUI/桌面 GUI 三端的视觉配置统一为一份 YAML 数据；`load_skin` 采用"用户皮肤优先 → 内置皮肤 → default 回退"分层解析，`light_colors`/`dark_colors` 配对调色板镜像桌面 app 的 colors/darkColors 配对。

### 3.4 进程生命周期自愈

`main()` 在 import 期就做 `suppress_platform_ver_console`、`_early_recovery.recover_if_needed`、`_sweep_stale_bytecode_if_checkout_changed`，并对 one-shot 模式 `os._exit` 跳过 `atexit` 与原生 finalizer。

## 四、调用示例

```python
from hermes_cli.config import load_config

# 加载配置（自动深合并 DEFAULT_CONFIG + 用户 YAML + 版本迁移）
cfg = load_config()
print(cfg["agent"]["model"])  # 当前配置的模型

from hermes_cli.commands import resolve_command
cmd = resolve_command("/help")
print(cmd.description)  # 命令描述

from hermes_cli.skin_engine import load_skin
skin = load_skin("dark")
print(skin.colors)  # 皮肤调色板
```

## 五、小结

1. `COMMAND_REGISTRY` 是所有 slash 命令的单一真源，CLI/网关/Telegram/Slack 均派生自它
2. 配置层实现深合并 + 版本迁移 + 损坏自愈，任意老版本 config.yaml 无损升级
3. `load_config_readonly` 是 agent 循环内只读热路径，跳过 deepcopy 省 ~135us/次
4. 皮肤系统数据驱动，CLI/TUI/Desktop 三端统一一份 YAML
5. 进程生命周期自愈：venk 修复、bytecode 清扫、one-shot `os._exit` 规避 finalizer SIGABRT
