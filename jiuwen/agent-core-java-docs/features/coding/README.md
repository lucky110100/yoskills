# Coding 能力特性索引

> 交叉引用: [01-project-overview](../../01-project-overview.md) | [02-overall-architecture](../../02-overall-architecture.md) | [04-harness-and-deepagents-module](../../04-harness-and-deepagents-module.md) | [06-agentevolving-and-autoharness-module](../../06-agentevolving-and-autoharness-module.md)

## 能力判定

agent-core-java **具备完整的 coding 能力骨架**，覆盖代码编辑、导航、诊断、执行、审查、规划、子代理协作、自动改码、插件热加载、安全控制与编码记忆等维度。但部分能力相比 Python 版 agent-core 存在差距，本索引如实标注实现状态（✅已实现 / ⚠️部分实现 / ❌未实现），未实现的功能不臆造。

真正编写/修改代码的两条链路：
1. **harness/subagents + harness/deep_agent** — 交互式编码代理（DeepAgent + CodeAgent + 四阶段子代理）
2. **autoharness/** — 端到端自动改码 + CI 修复循环（AutoHarnessOrchestrator 编排 7 stages）

## 特性文档索引

| 特性 | 状态 | 说明 | 关键入口 |
|------|------|------|---------|
| [code-editing](code-editing.md) | ⚠️ 部分 | 裸读写已实现；精确字符串替换/stale-write 保护/操作审计未实现 | [FilesystemTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/FilesystemTool.java#L20) |
| [code-navigation](code-navigation.md) | ✅ 已实现 | LSP 8 项导航操作 + searchText 搜索（简化版） | [LspTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/LspTool.java#L21) |
| [code-diagnostics](code-diagnostics.md) | ⚠️ 部分 | 基础设施齐全，双钩子自动闭环未接通 | [LspDiagnosticRegistry](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/lsp/core/LspDiagnosticRegistry.java#L17) |
| [code-execution](code-execution.md) | ✅ 已实现 | Bash/PowerShell/CodeTool + 注入检测 + 破坏性警告 | [BashTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/BashTool.java#L26) |
| [code-review](code-review.md) | ✅ 已实现 | VerificationAgent 对抗性验证 + VERDICT 结构化输出 | [VerificationAgentFactory](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/VerificationAgentFactory.java#L21) |
| [code-planning](code-planning.md) | ✅ 已实现 | PlanAgent + TodoTool + 停止条件评估器 | [PlanAgentFactory](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/PlanAgentFactory.java#L20) |
| [coding-subagents](coding-subagents.md) | ✅ 已实现 | 探索-规划-编码-验证四阶段 | [CodeAgentFactory](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/CodeAgentFactory.java#L25) |
| [coding-memory](coding-memory.md) | ⚠️ 部分 | 类+3工具+索引注入；向量+BM25 per-turn 召回未接入 | [CodingMemoryRail](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/CodingMemoryRail.java#L33) |
| [auto-harness](auto-harness.md) | ✅ 已实现 | autoharness 7 stages 端到端改码 + CI 修复循环 | [AutoHarnessOrchestrator](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/orchestrator/AutoHarnessOrchestrator.java#L42) |
| [plugin-hot-loading](plugin-hot-loading.md) | ⚠️ 部分 | 仅 SKILL 单类热加载；6 类资源事务性热加载未实现 | [SkillUseRail](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/SkillUseRail.java#L273) |
| [coding-security](coding-security.md) | ⚠️ 部分 | 3 层权限+注入检测+警告；stale-write/审计/5层管道未实现 | [PermissionEngine](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/security/PermissionEngine.java#L16) |

## 能力速查表（按实现状态分组）

### ✅ 已实现（4 项）
| 特性 | 关键能力 |
|------|---------|
| code-navigation | LSP 8 操作（定义/引用/符号/调用层次）+ searchText |
| code-execution | Bash/PowerShell/CodeTool + 注入检测 + 破坏性警告 + read-only |
| code-review | VerificationAgent 对抗验证 + VERDICT PASS/FAIL/PARTIAL |
| coding-subagents | 探索-规划-编码-验证四阶段子代理体系 |
| auto-harness | 7 stages + CI 修复循环 + ExperienceStore 经验沉淀 |

### ⚠️ 部分实现（5 项）
| 特性 | 已实现部分 | 未实现部分 |
|------|-----------|-----------|
| code-editing | FilesystemTool 裸读写（readFile/writeFile/listFiles/searchText） | 精确字符串替换（EditFileTool）、stale-write 保护、read-before-edit 强制、操作审计 |
| code-diagnostics | LspDiagnosticRegistry + didChange + getAndClear | after_tool_call 触发 / before_model_call 注入双钩子自动闭环未接通 |
| coding-memory | CodingMemoryRail + 3 工具 + MEMORY.md 索引注入 | 向量+BM25 混合检索 per-turn top5 召回未接入 |
| plugin-hot-loading | SkillUseRail mtime 签名 + refreshIncrementally | 6 类资源（TOOL/MCP/RAIL/PROMPT/SKILL/SUBAGENT）事务性热加载、ExtensionBinder 类 |
| coding-security | 3 层权限（ALLOW/ASK/DENY）+ 注入检测 + 破坏性警告 | stale-write 保护、read-before-edit、操作审计、5 层权限管道 |

## 关键入口

| 入口 | 文件位置 | 说明 |
|------|---------|------|
| [HarnessFactory.createDeepAgent](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/factory/HarnessFactory.java#L41) | harness/factory | 创建 DeepAgent 编码代理 |
| [DeepAgentsFactory.createDeepAgent](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/deepagents/DeepAgentsFactory.java#L27) | deepagents | 门面入口 |
| [HarnessCli.runOnce](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/cli/HarnessCli.java#L21) | harness/cli | CLI 入口 |
| [AutoHarnessOrchestrator.runSession](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/orchestrator/AutoHarnessOrchestrator.java#L42) | autoharness | 自动改码会话 |
| [LeaderTeammateAgentTeam.builder](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/LeaderTeammateAgentTeam.java#L26) | agentteams | 团队入口 |

## 与 Python agent-core 对照

| 维度 | Java | Python | 差异 |
|------|------|--------|------|
| 代码编辑 | ⚠️ 裸读写 | ✅ 精确替换+stale-write+审计 | Java 缺 EditFileTool |
| LSP 诊断闭环 | ⚠️ 基础设施未接通 | ✅ 双钩子自动闭环 | Java 缺 after/before 钩子 |
| 编码记忆 | ⚠️ 静态索引 | ✅ 向量+BM25 召回 | Java 缺 per-turn 召回 |
| 插件热加载 | ⚠️ 仅 SKILL | ✅ 6 类事务性 | Java 缺 ExtensionBinder |
| 安全控制 | ⚠️ 3 层简化 | ✅ 5 层管道+审计 | Java 缺 stale-write+审计 |
| 代码导航 | ✅ 8 操作 | ✅ 8 操作 | 基本对等 |
| 代码执行 | ✅ 注入检测 | ✅ 注入检测+截断 | Java 缺输出截断/后台 |
| 代码审查 | ✅ VERDICT | ✅ VERDICT | 基本对等 |
| 子代理协作 | ✅ 四阶段 | ✅ 四阶段 | 基本对等 |
| 自动改码 | ✅ 7 stages | ✅ 7 stages | 基本对等 |

## 主文档交叉引用

完整模块分析见主文档集：
- [03-core-module](../../03-core-module.md) — Pregel 引擎、Runner、ReActAgent
- [04-harness-and-deepagents-module](../../04-harness-and-deepagents-module.md) — DeepAgent、Rails、TaskLoop、工具、子代理
- [06-agentevolving-and-autoharness-module](../../06-agentevolving-and-autoharness-module.md) — Trainer RL 优化、autoharness 7 stages
- [07-extensions-and-spi-module](../../07-extensions-and-spi-module.md) — 沙箱、RedisCheckpointer、SPI 存储
- [industry-comparison](../../industry-comparison.md) — 与 Spring AI/LangChain4j/Python agent-core 对比
