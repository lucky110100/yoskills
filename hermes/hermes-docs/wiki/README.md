# Hermes Agent Code Wiki

> 由 `code-wiki-author` 技能生成。本文档集对 Hermes Agent 项目的架构、模块、关键类函数进行结构化文档化，所有代码引用均可点击直达源码行。

## 基线信息

| 项 | 值 |
|----|-----|
| 项目 | Hermes Agent ☤ (Nous Research) |
| 基线提交 | `fa83af3f9a42790730b8966ff67e7d9fb627899f` |
| Tag | `v2026.8.3-1455-gfa83af3f9` |
| 分支 | main |
| 时间 | 2026-08-13 03:16:25 -0700 |
| 技术栈 | Python 3.11-3.13 + TypeScript |

## 文档索引

| 序号 | 文档 | 内容简介 |
|------|------|----------|
| 00 | [路标与增量更新指南](00-wiki-guide.md) | 基线信息、产物清单、增量更新流程、提交→文档映射表 |
| 01 | [项目概述](01-project-overview.md) | 项目定位、核心能力、技术栈、仓库结构、入口点、快速开始 |
| 02 | [整体架构](02-overall-architecture.md) | 分层架构、十大设计模式、运行时数据流、关键概念、进程模型 |
| 03 | [agent 模块](03-agent-module.md) | 对话循环、provider 适配、上下文治理、内存召回、错误恢复 |
| 04 | [tools 模块](04-tools-module.md) | 工具注册中心、AST 自发现、toolset surface gate、安全校验 |
| 05 | [gateway 模块](05-gateway-module.md) | 消息网关、平台适配器 ABC、StreamEvent 契约、排空控制 |
| 06 | [hermes_cli 模块](06-hermes-cli-module.md) | CLI 入口、COMMAND_REGISTRY 单一真源、配置深合并、皮肤引擎 |
| 07 | [plugins 模块](07-plugins-module.md) | 四源插件发现、lazy_singleton 并发原语、Plugin Context 协议 |
| 08 | [cron 模块](08-cron-module.md) | 调度循环、双层锁、SQLite 执行审计、生命周期守卫 |
| 09 | [providers + acp_adapter 模块](09-providers-acp-module.md) | 声明式 ProviderProfile、ACP 服务器、审批桥接 |
| 10 | [tui_gateway 模块](10-tui-gateway-module.md) | TUI 后端、JSON-RPC 双传输、Transport 抽象、线程池分流 |
| 11 | [ui-tui 模块](11-ui-tui-module.md) | Ink 终端 UI、nanostores 状态、widget SDK slot 注入 |
| 12 | [web 模块](12-web-module.md) | 浏览器仪表盘 SPA、lazy 路由、Profile 作用域、PluginSlot |
| 13 | [desktop 模块](13-desktop-module.md) | Electron 桌面应用、三权分立、共享 GatewayClient、命名空间门 |
| 14 | [依赖关系](14-dependencies.md) | 内部依赖图、外部依赖表、可选依赖组、依赖锁定策略 |
| 15 | [运行方式](15-running-guide.md) | 安装、配置、CLI 入口、编程式使用、测试、代码质量 |

## 阅读路径

### 新手路径（了解项目）

1. [01-项目概述](01-project-overview.md) → 2. [02-整体架构](02-overall-architecture.md) → 3. [15-运行方式](15-running-guide.md)

### 贡献者路径（理解代码）

1. [02-整体架构](02-overall-architecture.md) → 2. [03-agent模块](03-agent-module.md) → 3. [04-tools模块](04-tools-module.md) → 4. [05-gateway模块](05-gateway-module.md) → 5. [14-依赖关系](14-dependencies.md)

### 维护者路径（增量更新）

1. [00-路标与增量更新指南](00-wiki-guide.md) → 2. 按提交→文档映射表更新对应文档 → 3. 追加更新记录

## 文档约定

- **语言**：中文
- **代码引用**：`[basename](file:///绝对路径#L行号)` 格式，可点击直达源码行
- **交叉引用**：每篇文档顶部含交叉引用行，形成知识网络
- **行数**：模块文档 200-400 行，主文档 300-500 行，参考文档 200-300 行

## 相关文档

- [项目质量评估](../project-health.md) — 13 维度质量评分卡（由 project-analysis 技能生成）
- [开发参考手册](../development-reference.md) — 13 维度标杆做法与本项目对照
- [项目规则](../project-rules.md) — 精简开发规则
- [质量评估详情](../quality/README.md) — 13 分维度评估文档索引
