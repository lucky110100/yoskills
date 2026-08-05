# openJiuwen Core — Code Wiki

本 Wiki 是对 [agent-core](file:///D:/jiuwen/main/agent-core) 仓库（`openJiuwen Core`）源码的结构化解读文档，覆盖项目整体架构、各主要模块职责、关键类与函数说明、模块间依赖关系以及项目运行方式等关键信息。

## 文档导航

| 序号 | 文档 | 内容简介 |
|------|------|----------|
| 00 | [路标与增量更新说明](00-roadmap-and-incremental-update.md) | 本次任务时间线、基线提交、后续增量更新流程 |
| 01 | [项目概述](01-project-overview.md) | 项目定位、核心能力、特性与设计目标 |
| 02 | [整体架构](02-overall-architecture.md) | 分层架构、核心设计模式、运行时数据流、关键概念 |
| 03 | [core 模块](03-core-module.md) | 引擎层：图执行引擎、工作流、会话、Runner、智能体基础 |
| 04 | [harness 模块](04-harness-module.md) | 编码智能体框架：DeepAgent、任务循环、Rails、工具、安全 |
| 05 | [agent_teams 模块](05-agent-teams-module.md) | 多智能体团队框架：团队编排、消息总线、CLI/MCP |
| 06 | [agent_evolving 与 dev_tools 模块](06-agent-evolving-and-dev-tools-module.md) | 智能体自演进与开发者调优工具 |
| 07 | [extensions 与 rsi 模块](07-extensions-and-rsi-module.md) | A2A 集成与 RSI 评估优化框架 |
| 08 | [依赖关系](08-dependencies.md) | 内部模块依赖图、外部第三方依赖、可选依赖 |
| 09 | [运行方式](09-running-guide.md) | 安装、配置、运行、测试与命令行入口 |

## Coding 能力特性

agent-core 具备完整的 coding 能力，覆盖代码编辑、导航、诊断、执行、审查、规划、子代理协作、自动改码、插件热加载、安全控制与编码记忆等维度。特性清单如下，完整分析见 [features/coding/README](features/coding/README.md)。

| 特性 | 说明 |
|------|------|
| [code-editing](features/coding/code-editing.md) | 精确字符串替换编辑、stale-write 保护、read-before-edit 强制 |
| [code-navigation](features/coding/code-navigation.md) | LSP 8 项导航操作 + Grep/Glob 三引擎自适应搜索 |
| [code-diagnostics](features/coding/code-diagnostics.md) | LspRail 双钩子自动修复闭环（编辑后触发诊断→注入 LLM 上下文） |
| [code-execution](features/coding/code-execution.md) | Bash/PowerShell/CodeTool 多语言执行 + 语义化 exit code |
| [code-review](features/coding/code-review.md) | VerificationAgent 对抗性验证 + VERDICT 结构化输出 |
| [code-planning](features/coding/code-planning.md) | PlanAgent 纯规划 + TaskPlanningRail + GoalManager 三态状态机 |
| [coding-subagents](features/coding/coding-subagents.md) | 探索-规划-编码-验证四阶段子代理协作体系 |
| [coding-memory](features/coding/coding-memory.md) | CodingMemoryRail 向量+BM25 混合检索编码记忆 |
| [auto-harness](features/coding/auto-harness.md) | rsi/auto_harness 端到端自动改码 + CI 失败修复循环 |
| [plugin-hot-loading](features/coding/plugin-hot-loading.md) | extension_binder 6 类资源事务性热加载 |
| [coding-security](features/coding/coding-security.md) | 注入检测 + 5 层权限管道 + 操作审计 |

> 各特性文档均含关键类与函数（带源码行号锚点）、实现机制、调用示例与业界对比（Cursor/Claude Code/Copilot）。详见 [features/coding/README](features/coding/README.md)。

## 项目速览

**openJiuwen Core** 是一个面向大语言模型（LLM）应用的 Python SDK，为运行在 openJiuwen 框架上的智能体提供高性能运行时。其核心能力包括：

- **SDK 接口层**：智能体创建、工作流编排、LLM 调用、工具调用等易用接口
- **智能体引擎**：ReAct 智能交互与工作流自动跳转两类场景，支持任务规划、工具选择与调用
- **高性能执行引擎**：异步并行图执行、组件并发、流式处理、状态保存与中断恢复
- **调试与优化工具**：提示词自动优化、全链路可观测性

## 快速开始

```bash
# 安装
pip install -U openjiuwen

# 命令行交互
openjiuwen

# 运行单次查询
openjiuwen run "你的问题"
```

> Python 版本要求：3.11 及以上、3.14 以下（推荐 3.11.4）

## 许可证

本项目基于 Apache-2.0 许可证开源。

## 文档约定

- 文件路径引用均使用 `openjiuwen/...` 形式表示相对于仓库根目录的路径
- 类名、函数名使用 `反引号` 包裹，例如 `DeepAgent`
- 关键设计模式以 **加粗** 标注
- 代码示例尽量与仓库内 `examples/` 与 `README.md` 中的风格保持一致
