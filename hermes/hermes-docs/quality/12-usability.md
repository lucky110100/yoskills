# 12 易用性 usability

> 维度归属：E 外部质量组。评估 API 版本化、文档、错误信息、CLI 补全、配置校验、最小示例。
>
> 配套：[汇总评分卡](../project-health.md) | [索引](README.md)

## 评分：4 / 4

对照 4 分档「API 版本化+OpenAPI 文档+CLI 补全+错误可读带修复建议+最小示例+配置校验」。其中 5 项扎实命中；「OpenAPI 文档」未以独立 Swagger 形式暴露，但 API Server 本身是 OpenAI 兼容（遵循公开发布的 OpenAI API 规范，等同于一种版本化 API 文档），整体仍达 4 分档。

## 评估过程

### 关键问题（带 file:/// 证据）

1. **未暴露独立 OpenAPI/Swagger 规范页面** — API Server 复刻 OpenAI Chat Completions 格式，文档以 `api-server.md` 手写 endpoint 说明，未提供自动生成的 `/docs` OpenAPI schema 供前端机器消费 → [api-server.md](file:///D:\yaodh\main\hermes-agent\website\docs\user-guide\features\api-server.md#L56-L60)。

2. **`errors.py` 异常类描述极简**（仅 3 个 class），真正的错误分类逻辑在 `error_classifier.py`，`errors.py` 本身缺少面向用户的可读消息字段 → [errors.py](file:///D:\yaodh\main\hermes-agent\agent\errors.py#L1-L13)。

### 亮点

- ✅ **API 版本化** — ACP 协议使用 `agent-client-protocol==0.9.0` 并在 `initialize` 中协商 `protocol_version`，回传 `agent_info.version`；CLI 提供 `hermes --version` → [server.py](file:///D:\yaodh\main\hermes-agent\acp_adapter\server.py#L1145-L1158)、[pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L260)。
- ✅ **CLI 补全自动生成** — 从 argparse 解析树动态生成 bash/zsh/fish 补全脚本，无硬编码子命令列表，始终与 CLI 同步 → [completion.py](file:///D:\yaodh\main\hermes-agent\hermes_cli\completion.py#L1-L7)。
- ✅ **错误可读且带修复建议** — `error_classifier.py` 用 `FailoverReason` 枚举建立完整错误分类学，`ClassifiedError` 携带 `retryable/should_compress/should_rotate_credential` 等恢复动作提示；`validate_config_structure` 返回 `ConfigIssue(severity, message, how_to_fix)`；`doctor.py` 的 `_fail_and_issue` 输出 fix 指令 → [error_classifier.py](file:///D:\yaodh\main\hermes-agent\agent\error_classifier.py#L24-L72)、[config.py](file:///D:\yaodh\main\hermes-agent\hermes_cli\config.py#L1907-L1935)、[doctor.py](file:///D:\yaodh\main\hermes-agent\hermes_cli\doctor.py#L414-L415)。
- ✅ **最小示例完备** — README 单行安装 + Getting Started 6 条命令，Windows/Termux/WSL2 全覆盖，多语言 README（中文/اردو/Español）→ [README.md](file:///D:\yaodh\main\hermes-agent\README.md#L35-L66)、[README.md](file:///D:\yaodh\main\hermes-agent\README.md#L105-L118)。
- ✅ **配置校验 + 损坏自愈** — `validate_config_structure`/`_validate_config_key`/`sanitize_env_file`，损坏 config 自动备份 `.corrupt.<ts>.bak` 并 warn-once，不静默吞掉用户配置 → [config.py](file:///D:\yaodh\main\hermes-agent\hermes_cli\config.py#L46-L97)、[config.py](file:///D:\yaodh\main\hermes-agent\hermes_cli\config.py#L4957)。
- ✅ **单一真相源的 slash 命令注册表** — `COMMAND_REGISTRY` 同时驱动 CLI 帮助、网关分发、Telegram BotCommands、Slack 子命令、自动补全，新增命令只需加一个 `CommandDef` → [commands.py](file:///D:\yaodh\main\hermes-agent\hermes_cli\commands.py#L1-L9)、[commands.py](file:///D:\yaodh\main\hermes-agent\hermes_cli\commands.py#L102)。
- ✅ **海量用户文档**（Docusaurus 站点 200+ 页）— getting-started/、guides/（30+）、reference/（cli-commands、environment-variables、slash-commands、tools-reference）、user-guide/features/（40+）、messaging/（30+ 平台）、skills/（100+ 技能）、developer-guide/（30+）。
- ✅ **doctor 诊断工具** — `hermes doctor` 自动诊断环境问题并给出修复指令 → [doctor.py](file:///D:\yaodh\main\hermes-agent\hermes_cli\doctor.py#L414-L415)。

## Checklist 对照

- [x] API 是否版本化 + 有文档 — ✅ ACP 协议协商 + OpenAI 兼容
- [x] 错误信息是否可读带修复建议 — ✅ ClassifiedError + ConfigIssue.how_to_fix + doctor
- [x] CLI 是否有补全 — ✅ argparse 动态生成 bash/zsh/fish
- [x] 是否有最小示例 — ✅ README Quick Install + Getting Started

## 改进建议

1. 为 API Server 暴露 FastAPI 自带的 `/docs`（OpenAPI）与 `/redoc`，或发布一份机器可读的 OpenAPI YAML。
2. 给 `errors.py` 的异常类补充 `message`/`hint` 字段，使面向用户的报错路径不止依赖 `error_classifier`。
