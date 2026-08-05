# Coding 能力特性分析

> 本目录聚焦 agent-core(openJiuwen Core)的 coding 能力特性分析,基于源码深入实现层面。
> 主文档集: [返回总览](../../README.md) | [02-整体架构](../../02-overall-architecture.md) | [04-harness模块](../../04-harness-module.md)

## 能力判定

agent-core **具备完整的 coding 能力**,覆盖代码编辑、导航、诊断、执行、审查、规划、子代理协作、自动改码、插件热加载、安全控制、编码记忆等维度。真正编写/修改代码的两条链路:

1. **harness/subagents/code_agent.py + harness/cli** — 交互式编码代理(CodeAgent + CLI)
2. **rsi/auto_harness/** — 端到端自动改码+CI修复+PR发布

两条链路共享同一套底层工具集(ReadFileTool/EditFileTool/WriteFileTool/BashTool/LspTool 等)与同一套安全控制(注入检测、权限管道、read-before-edit),但在编排粒度与人工介入程度上互补:交互式链路人主导、Agent 辅助;自动改码链路 Agent 主导、人监督。

## 文档索引

| 文档 | 能力维度 | 关键能力 |
|------|---------|---------|
| [code-editing](code-editing.md) | 代码编辑 | EditFileTool/WriteFileTool/ReadFileTool,精确字符串替换,stale-write 保护 |
| [code-navigation](code-navigation.md) | 代码导航 | LspTool 基于 LSP 的定义跳转/引用查找/符号检索 |
| [code-diagnostics](code-diagnostics.md) | 代码诊断 | LSP 诊断、错误收集与修复建议反馈 |
| [code-execution](code-execution.md) | 代码执行 | BashTool/PowerShellTool,五层权限管道,注入检测 |
| [code-review](code-review.md) | 代码审查 | 评审 Rail,两阶段修复循环中的 evaluator |
| [code-planning](code-planning.md) | 代码规划 | assess/plan 阶段,任务分解与方案规划 |
| [coding-subagents](coding-subagents.md) | 子代理协作 | Subagent 调度与隔离执行 |
| [coding-memory](coding-memory.md) | 编码记忆 | ExperienceStore 经验沉淀与跨会话复用 |
| [auto-harness](auto-harness.md) | 自动改码 | AutoHarnessOrchestrator 端到端会话,两阶段 CI 修复 |
| [plugin-hot-loading](plugin-hot-loading.md) | 插件热加载 | apply_extension_hot 六类资源事务性绑定 |
| [coding-security](coding-security.md) | 安全控制 | 注入检测/权限分级/read-before-edit/审批中断 |

## 能力速查表

### 基础能力

| 能力 | 关键工具/类 | 入口 |
|------|------------|------|
| 代码编辑 | EditFileTool/WriteFileTool/ReadFileTool | SysOperationRail |
| 代码导航 | LspTool | LspRail |
| 代码诊断 | LSP diagnostics | LspRail |
| 代码执行 | BashTool/PowerShellTool | SysOperationRail |

### 协作能力

| 能力 | 关键工具/类 | 入口 |
|------|------------|------|
| 代码审查 | evaluator + 评审 Rail | FixLoopController Phase2 |
| 代码规划 | assess/plan stage | AutoHarnessOrchestrator |
| 子代理协作 | Subagent 调度 | SubagentRail |
| 编码记忆 | ExperienceStore | ExperienceRail |

### 自动化能力

| 能力 | 关键工具/类 | 入口 |
|------|------------|------|
| 端到端自动改码 | AutoHarnessOrchestrator | _stream_session_pipeline |
| CI 失败修复 | FixLoopController | 两阶段修复循环 |
| 插件热加载 | apply_extension_hot | load_plugin |
| 失败回滚 | RevertOnFailureRail | worktree 隔离 |

### 安全能力

| 能力 | 关键工具/类 | 入口 |
|------|------------|------|
| 注入检测 | check_injection(Bash/PS) | OPENJIUWEN_BASH_STRICT |
| 权限分级 | PermissionMode 四级 | check_permission 五层管道 |
| 文件编辑安全 | _FILE_READ_REGISTRY | read-before-edit |
| 人机审批 | PermissionInterruptRail | build_permission_interrupt_rail |

## 关键入口

| 入口 | 文件位置 | 说明 |
|------|---------|------|
| create_code_agent | [code_agent.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/subagents/code_agent.py#L173) | 构建交互式编码代理 CodeAgent |
| create_deep_agent | [factory.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/factory.py#L418) | 构建可热加载插件的可扩展 DeepAgent |
| AutoHarnessOrchestrator | [orchestrator.py](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/auto_harness/orchestrator.py#L106) | 端到端自动改码会话编排器 |
| LspRail | [lsp_rail.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/rails/lsp_rail.py#L20) | 初始化 LSP 子系统并注册 LspTool |
| SysOperationRail | [sys_operation_rail.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/rails/sys_operation_rail.py#L23) | 注册 filesystem/shell/code 编码工具 |

> 阅读建议:先从 [02-整体架构](../../02-overall-architecture.md) 与 [04-harness模块](../../04-harness-module.md) 建立全局认知,再按需进入具体特性文档。auto-harness 与 coding-security 是理解 agent-core 差异化能力的两个关键文档。

> 能力闭环:基础能力(编辑/导航/诊断/执行)→ 协作能力(审查/规划/子代理/记忆)→ 自动化能力(自动改码/插件热加载/失败回滚)→ 安全能力(注入检测/权限分级/文件安全/审批)。安全能力贯穿前三类,是整个 coding 体系的地基。
