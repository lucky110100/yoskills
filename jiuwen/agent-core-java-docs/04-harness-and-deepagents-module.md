# harness 与 deepagents 模块：编码代理实现层与门面层

> 交叉引用：[01-project-overview](01-project-overview.md) | [02-overall-architecture](02-overall-architecture.md) | [03-core-module](03-core-module.md) | [06-agentevolving-and-autoharness-module](06-agentevolving-and-autoharness-module.md)

## 一、模块职责

`com.openjiuwen.harness` 与 `com.openjiuwen.deepagents` 共同构成 agent-core-java 的“编码代理能力层”，前者是核心实现，后者是门面：

- **harness（核心实现层）** 在 core 引擎之上构建完整编码代理框架，按子包组织：
  - `cli`：命令行入口与交互
  - `rails`：代理运行“护栏”，在工具调用前后注入策略（LSP/MCP/任务/技能/会话/权限中断）
  - `tools`：编码工具集（Bash/Code/LSP/Todo/文件系统/Cron/PowerShell/Web/多模态/Skill/MCP/Sessions）
  - `subagents`：子代理工厂（探索-规划-编码-验证四阶段）
  - `task_loop`：任务循环四元组（事件队列 + 调度器 + 控制器 + 停止条件求值）
  - `security`：权限引擎与策略
  - `workspace`：工作区抽象
  - `deep_agent`：DeepAgent 主体
  - `factory`：DeepAgent 装配工厂

- **deepagents（门面层）** 镜像 Python `openjiuwen.deepagents`，对外暴露最小门面：
  - `DeepAgentsFactory`：统一创建 DeepAgent（支持 `DeepAgentConfig` / `Path` / `HarnessConfig`）
  - `DeepAgentToolKit`：工具集合封装
  - `DeepAgentSubagents`：子代理配置构建（如 `buildCodeAgentConfig`）
  - 中间件：`TaskPlanningMiddleware` / `ContextEngineeringMiddleware`

一句话：core 提供引擎，harness 把引擎做成可落地的编码代理，deepagents 把 harness 包装成可一行调用的门面。

## 二、关键类与函数

| 类 / 函数 | 文件位置 | 说明 |
| --- | --- | --- |
| [DeepAgent](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/deep_agent/DeepAgent.java#L97) | `harness/deep_agent/DeepAgent.java` | `implements AutoCloseable`；L92 注释 "Minimal Java baseline for the Python DeepAgent"；`ensureInitialized` L539、`invoke` L827、`stream` L922、`requestAbort` L1109、`steer` L1133、`createSubagent` L1266、`ensureTaskLoopRuntime` L1417、`runTaskLoop` L1481 |
| [HarnessFactory](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/factory/HarnessFactory.java#L41) | `harness/factory/HarnessFactory.java` | `createDeepAgent` L68；`enrichConfig` L132 注入默认 rails |
| [DeepAgentRail](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/DeepAgentRail.java#L14) | `harness/rails/DeepAgentRail.java` | 抽象护栏：`init` / `uninit` / `getPriority`；默认 priority=50 |
| [LspRail](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/LspRail.java#L22) | `harness/rails/LspRail.java` | priority=60；`init` L44-55 创建 `LSPServerManager` 并注册 `LspTool` |
| [McpRail](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/McpRail.java#L26) | `harness/rails/McpRail.java` | MCP 轨道，priority=95 |
| [BaseInterruptRail](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/interrupt/BaseInterruptRail.java#L27) | `harness/rails/interrupt/BaseInterruptRail.java` | 中断护栏基类：`beforeToolCall` → `resolveInterrupt` → `applyDecision`（`ApproveResult` / `RejectResult` / `InterruptResult`） |
| [PermissionInterruptRail](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/security/PermissionInterruptRail.java#L28) | `harness/rails/security/PermissionInterruptRail.java` | `resolveInterrupt` L58-75：ALLOW→approve、DENY→reject、ASK→interrupt（抛 `ToolInterruptException`） |
| [BashTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/BashTool.java#L26) | `harness/tools/BashTool.java` | `checkInjection`（检测 backtick / `$()` / `<()`）、`getDestructiveWarning`（git reset --hard / git push --force / drop table / terraform destroy）、`permissionMode`（read_only 模式 L66-68） |
| [CodeTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/CodeTool.java#L25) | `harness/tools/CodeTool.java` | 支持 python / bash / sh |
| [LspTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/LspTool.java#L21) | `harness/tools/LspTool.java` | `invoke` L54-80 派发 8 操作；`LspOperation` 枚举：GO_TO_DEFINITION / FIND_REFERENCES / DOCUMENT_SYMBOL / WORKSPACE_SYMBOL / GO_TO_IMPLEMENTATION / PREPARE_CALL_HIERARCHY / INCOMING_CALLS / OUTGOING_CALLS |
| [TaskTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/TaskTool.java#L19) | `harness/tools/TaskTool.java` | 委托 `parentAgent.createSubagent` |
| [TodoTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/TodoTool.java#L21) | `harness/tools/TodoTool.java` | CRUD；action：delete / cancel / update / append / insert_after / insert_before；`TodoItem` / `TodoStatus`（TODO/PENDING/IN_PROGRESS/DONE/COMPLETED/CANCELLED） |
| [FilesystemTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/FilesystemTool.java#L20) | `harness/tools/FilesystemTool.java` | `readFile` / `writeFile` / `listFiles` |
| [CodeAgentFactory](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/CodeAgentFactory.java#L25) | `harness/subagents/CodeAgentFactory.java` | `code_agent`；rails：SysOperationRail / AgentModeRail / AskUserRail / ConfirmInterruptRail / CodingMemoryRail |
| [ExploreAgentFactory](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/ExploreAgentFactory.java#L20) | `harness/subagents/ExploreAgentFactory.java` | `explore_agent`，只读；forbidden：write_file / edit_file / mkdir / touch / rm / cp / mv / git commit |
| [PlanAgentFactory](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/PlanAgentFactory.java#L20) | `harness/subagents/PlanAgentFactory.java` | `plan_agent`，`requires_critical_files` 3-5 |
| [VerificationAgentFactory](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/VerificationAgentFactory.java#L21) | `harness/subagents/VerificationAgentFactory.java` | `verification_agent`，verdicts：PASS / FAIL / PARTIAL |
| [TaskLoopController](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/task_loop/TaskLoopController.java#L17) | `harness/task_loop/TaskLoopController.java` | `prepareRound` / `resolveCompletion` / `enqueueFollowUp` / `enqueueSteering` / `drainFollowUp` / `drainSteer` / `waitRoundCompletion` |
| [TaskLoopEventHandler](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/task_loop/TaskLoopEventHandler.java#L27) | `harness/task_loop/TaskLoopEventHandler.java` | `handleInput` L126→提交 Task；`handleTaskCompletion`→`resolveCompletion` L228；`waitCompletion` L291 |
| [CoreTaskLoopEventExecutor](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/task_loop/CoreTaskLoopEventExecutor.java#L31) | `harness/task_loop/CoreTaskLoopEventExecutor.java` | `executeAbility` L96→`executeOnce` L163→`invokeTask` L286→`deepAgent.invoke` L291；`fireAfterTaskIteration` L196 |
| [LoopCoordinator](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/task_loop/LoopCoordinator.java#L17) | `harness/task_loop/LoopCoordinator.java` | `shouldContinue`（遍历 `StopConditionEvaluator`）/ `reset` / `incrementIteration` / `addTokenUsage` / `getState` / `loadState` |
| StopConditionEvaluator | `harness/task_loop/` | 接口；实现：`CompletionPromiseEvaluator` / `MaxRoundsEvaluator` / `TimeoutEvaluator` / `TokenBudgetEvaluator` / `CustomPredicateEvaluator` |
| [PermissionEngine](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/security/PermissionEngine.java#L16) | `harness/security/PermissionEngine.java` | `checkPermission` L63-68；`evaluateGlobalPolicyDirectly` L40-53；`PermissionLevel` 枚举（ALLOW / ASK / DENY） |
| [Workspace](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/workspace/Workspace.java#L27) | `harness/workspace/Workspace.java` | `root` / `getNodePath` / `linkTeam` |
| [DeepAgentsFactory](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/deepagents/DeepAgentsFactory.java#L27) | `deepagents/DeepAgentsFactory.java` | `createDeepAgent`（支持 `DeepAgentConfig` / `Path` / `HarnessConfig`） |
| DeepAgentToolKit / DeepAgentSubagents / 中间件 | `deepagents/` | `DeepAgentToolKit` 工具集；`DeepAgentSubagents`（`buildCodeAgentConfig` 等）；`TaskPlanningMiddleware` / `ContextEngineeringMiddleware` |

## 三、核心机制

### 3.1 DeepAgent 对等镜像 Python

[DeepAgent](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/deep_agent/DeepAgent.java#L97) `implements AutoCloseable`，L92 注释明确说明它是 "Minimal Java baseline for the Python DeepAgent"。字段与方法与 Python `deep_agent.DeepAgent` 对等：`invoke`（L827）/`stream`（L922）是主入口，`ensureInitialized`（L539）惰性装配 rails 与工具，`createSubagent`（L1266）支持子代理派生，`requestAbort`（L1109）/`steer`（L1133）提供取消与转向，`runTaskLoop`（L1481）/`ensureTaskLoopRuntime`（L1417）驱动任务循环。[HarnessFactory](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/factory/HarnessFactory.java#L41) `createDeepAgent`（L68）+ `enrichConfig`（L132）注入默认 rails，是构造主路径。

### 3.2 Rails 护栏与优先级

[DeepAgentRail](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/DeepAgentRail.java#L14) 是抽象护栏，约定 `init` / `uninit` / `getPriority`。优先级决定装配顺序：

| Rail | 优先级 | 职责 |
| --- | --- | --- |
| [McpRail](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/McpRail.java#L26) | 95 | MCP 服务器与工具接入 |
| [LspRail](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/LspRail.java#L22) | 60 | `init` L44-55 创建 `LSPServerManager` 并注册 [LspTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/LspTool.java#L21) |
| [DeepAgentRail](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/DeepAgentRail.java#L14) 默认 | 50 | 通用护栏基线 |
| Task / Planning / Iteration / SkillUse / Subagent / Session Rail | 50± | 任务循环与技能接入 |

中断护栏继承 [BaseInterruptRail](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/interrupt/BaseInterruptRail.java#L27)，链路为 `beforeToolCall` → `resolveInterrupt` → `applyDecision`，产出 `ApproveResult` / `RejectResult` / `InterruptResult` 三态。[PermissionInterruptRail](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/security/PermissionInterruptRail.java#L28) `resolveInterrupt`（L58-75）把 `PermissionLevel` 映射为：ALLOW→approve、DENY→reject、ASK→interrupt（抛 `ToolInterruptException`）。

### 3.3 TaskLoop 四元组异步驱动

任务循环由四个对象协作：

1. **事件队列 + 调度器**：[TaskLoopEventHandler](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/task_loop/TaskLoopEventHandler.java#L27) `handleInput`（L126）把输入提交为 Task，`handleTaskCompletion`→`resolveCompletion`（L228），`waitCompletion`（L291）阻塞等待。
2. **执行器**：[CoreTaskLoopEventExecutor](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/task_loop/CoreTaskLoopEventExecutor.java#L31) `executeAbility`（L96）→`executeOnce`（L163）→`invokeTask`（L286）→`deepAgent.invoke`（L291），迭代后 `fireAfterTaskIteration`（L196）触发后置钩子。
3. **控制器**：[TaskLoopController](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/task_loop/TaskLoopController.java#L17) 管理 `prepareRound` / `enqueueFollowUp` / `enqueueSteering` / `drainFollowUp` / `drainSteer` / `waitRoundCompletion`，把转向与跟进请求排队。
4. **停止条件求值**：[LoopCoordinator](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/task_loop/LoopCoordinator.java#L17) `shouldContinue` 遍历 `StopConditionEvaluator` 链（`CompletionPromiseEvaluator` / `MaxRoundsEvaluator` / `TimeoutEvaluator` / `TokenBudgetEvaluator` / `CustomPredicateEvaluator`）。

[DeepAgent](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/deep_agent/DeepAgent.java#L97) `runTaskLoop`（L1481-1566）是把这四元组编排起来：

```
DeepAgent.runTaskLoop (L1481-1566)
  ├─ ensureTaskLoopRuntime (L1417)     // 装配 EventHandler/Executor/Controller/Coordinator
  └─ loop:
      ├─ TaskLoopController.prepareRound
      ├─ TaskLoopEventHandler.handleInput → submit Task
      ├─ CoreTaskLoopEventExecutor.executeOnce → deepAgent.invoke (L291)
      ├─ fireAfterTaskIteration (L196)
      ├─ TaskLoopController.drainFollowUp / drainSteer
      └─ LoopCoordinator.shouldContinue → StopConditionEvaluator*
```

### 3.4 权限 3 层枚举与补偿

[PermissionEngine](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/security/PermissionEngine.java#L16) 用 `PermissionLevel` 枚举（ALLOW / ASK / DENY）三态替代 Python 的 5 层模型，简化决策面。`checkPermission`（L63-68）走轨道策略，`evaluateGlobalPolicyDirectly`（L40-53）兜底全局策略。为补偿表达能力，三处协作：

- [BashTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/BashTool.java#L26) `permissionMode`（read_only 模式 L66-68）做工具级降权；
- [PermissionInterruptRail](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/security/PermissionInterruptRail.java#L28) 把 ASK 转为中断并交人工裁决；
- 子代理（如 [ExploreAgentFactory](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/ExploreAgentFactory.java#L20)）用 `forbidden_operations` 显式禁用写类工具。

### 3.5 LSP 8 操作

[LspTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/LspTool.java#L21) `invoke`（L54-80）按 `LspOperation` 枚举派发 8 操作：GO_TO_DEFINITION / FIND_REFERENCES / DOCUMENT_SYMBOL / WORKSPACE_SYMBOL / GO_TO_IMPLEMENTATION / PREPARE_CALL_HIERARCHY / INCOMING_CALLS / OUTGOING_CALLS，对等 Python。

### 3.6 子代理四阶段

子代理工厂对应“探索-规划-编码-验证”四阶段：

| 阶段 | 工厂 | 特征 |
| --- | --- | --- |
| 探索 | [ExploreAgentFactory](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/ExploreAgentFactory.java#L20) | 只读，forbidden 写类工具与 git commit |
| 规划 | [PlanAgentFactory](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/PlanAgentFactory.java#L20) | `requires_critical_files` 3-5 |
| 编码 | [CodeAgentFactory](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/CodeAgentFactory.java#L25) | rails：SysOperationRail / AgentModeRail / AskUserRail / ConfirmInterruptRail / CodingMemoryRail |
| 验证 | [VerificationAgentFactory](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/VerificationAgentFactory.java#L21) | verdicts：PASS / FAIL / PARTIAL |

另有 `ResearchAgentFactory` / `BrowserAgentFactory` / `SubAgentConfig` / `SubAgentRegistry` 提供研究与浏览子代理及配置注册。

## 四、调用示例

```java
import com.openjiuwen.deepagents.DeepAgentsFactory;
import com.openjiuwen.deepagents.DeepAgentConfig;
import com.openjiuwen.harness.deep_agent.DeepAgent;
import java.nio.file.Path;

// 1. 门面层：一行创建 DeepAgent（基于 Path）
DeepAgent agent = DeepAgentsFactory.createDeepAgent(Path.of("/workspace/demo"));

try {
    // 2. 同步调用，内部走 TaskLoop 四元组
    String result = agent.invoke("为 src/main 添加 README 索引并运行 mvn compile 验证");

    // 3. 流式调用
    agent.stream("继续补充单测").forEach(chunk -> System.out.print(chunk));

    // 4. 转向（steer）：在迭代间隙注入新指令
    agent.steer("请优先处理编译错误");

    // 5. 中断恢复：ASK 级权限触发 ToolInterruptException，
    //    外层可捕获并调用 agent 的恢复接口继续
} finally {
    agent.close();   // implements AutoCloseable
}
```

基于 `DeepAgentConfig` 的细粒度装配：

```java
DeepAgentConfig config = DeepAgentConfig.builder()
        .workspace(Path.of("/workspace/demo"))
        .enableLsp(true)         // 装配 LspRail + LspTool（8 操作）
        .enableMcp(true)         // 装配 McpRail（priority=95）
        .build();

DeepAgent agent = DeepAgentsFactory.createDeepAgent(config);
```

## 五、与 Python agent-core 对照

| 维度 | Java | Python | 差异说明 |
| --- | --- | --- | --- |
| DeepAgent 主体 | [DeepAgent](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/deep_agent/DeepAgent.java#L97) | `deep_agent.DeepAgent` | 字段/方法对等；Java 显式 `AutoCloseable` |
| 护栏 | [DeepAgentRail](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/DeepAgentRail.java#L14) + 子类 | `rails` | 优先级模型对等；Java 用 priority 数值排序 |
| 任务循环 | TaskLoop 四元组（EventHandler/Executor/Controller/Coordinator） | task loop 四元组 | 四元组职责对等；Java 异步驱动用线程池 |
| 权限模型 | [PermissionEngine](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/security/PermissionEngine.java#L16) 3 层（ALLOW/ASK/DENY） | 5 层 | Java 简化为 3 层，靠 BashTool.permissionMode + SecurityRail + forbidden_operations 补偿 |
| LSP 工具 | [LspTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/LspTool.java#L21) 8 操作 | `LspTool` 8 操作 | 枚举一一对应 |
| 子代理 | 四阶段工厂（Explore/Plan/Code/Verification） | 四阶段子代理 | 阶段划分与 forbidden 策略对等 |
| 门面 | [DeepAgentsFactory](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/deepagents/DeepAgentsFactory.java#L27) | `openjiuwen.deepagents` | 均为最小门面，支持 Config/Path/HarnessConfig |

## 六、小结

harness 把 core 引擎落地为可执行的编码代理：以 [DeepAgent](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/deep_agent/DeepAgent.java#L97) 为运行主体，靠 Rails 护栏注入策略，靠 TaskLoop 四元组实现异步迭代与转向，靠 PermissionEngine 三态枚举做权限决策，靠四阶段子代理分工“探索-规划-编码-验证”。deepagents 则把这些收敛为 [DeepAgentsFactory](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/deepagents/DeepAgentsFactory.java#L27) 一行门面。理解 DeepAgent 对 Python 的对等镜像、Rails 优先级、TaskLoop 四元组与权限补偿机制，是阅读后续 agentteams 多代理团队模块的基础。
