# 编码任务规划与目标分解

> 交叉引用: [01-project-overview](../../01-project-overview.md) | [02-overall-architecture](../../02-overall-architecture.md) | [04-harness-and-deepagents-module](../../04-harness-and-deepagents-module.md) | [06-agentevolving-and-autoharness-module](../../06-agentevolving-and-autoharness-module.md)

## 一、能力概述

agent-core-java 的编码规划能力由独立的**纯规划子代理(plan_agent)**承担,其职责是在只读模式下探索代码库并产出可执行的实现计划。它与 code_agent(编码)、verification_agent(验证)分工:plan_agent 不写一行代码,只做"理解需求→充分探索→方案设计→细化计划"四步,并在末尾强制给出"Critical Files for Implementation"列出 3-5 个关键文件路径,供后续编码阶段直接落地。这种"规划与执行分离"的设计,让规划代理在只读沙箱中专注架构思考,而把"动手改文件"留给 code_agent,避免规划阶段就因试错式写码污染工作区。

规划能力的另一条主线是**目标状态机与停止条件评估**:TodoTool 提供 create/list/get/modify 四个动作与 delete/cancel/update/append/insert_after/insert_before 七种子操作,TodoItem 维护 TODO/PENDING/IN_PROGRESS/DONE/COMPLETED/CANCELLED 六态并强制"同一时刻仅一个 IN_PROGRESS";TaskPlanningRail 在每次任务迭代后同步状态;TaskCompletionRail 通过 CompletionPromiseEvaluator 检测 `<promise>...</promise>` 完成承诺;LoopCoordinator 聚合 CompletionPromise / MaxRounds / Timeout / TokenBudget / CustomPredicate 五类停止条件,决定任务循环何时收口。

本能力在 Java 版完整落地,与 Python 版 plan_agent 提示(L32-L52 纯规划约束)逐条对齐。两条主线——"只读规划子代理"与"目标状态机+停止条件"——共同保证编码任务"先想清楚再动手,且动手过程可追踪、可收口"。

## 二、关键类与函数

| 类/函数 | 职责 | 源码位置 |
|---------|------|----------|
| PlanAgentFactory | 工厂名 `plan_agent`,构建规划代理配置 | [PlanAgentFactory.java#L20](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/PlanAgentFactory.java#L20) |
| buildPlanAgentConfig(language) | 单参重载,默认空 kwargs | [PlanAgentFactory.java#L120](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/PlanAgentFactory.java#L120) |
| buildPlanAgentConfig(language, kwargs) | 装配提示/纯规划约束/Rails(maxIterations=25) | [PlanAgentFactory.java#L132](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/PlanAgentFactory.java#L132) |
| PLAN_AGENT_SYSTEM_PROMPT_CN | 纯规划中文提示(只读 + Critical Files 输出) | [PlanAgentFactory.java#L26](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/PlanAgentFactory.java#L26) |
| PLAN_AGENT_SYSTEM_PROMPT_EN | 纯规划英文提示(逐条对齐 CN) | [PlanAgentFactory.java#L58](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/PlanAgentFactory.java#L58) |
| createPlanAgent | 便捷方法,直接产出 DeepAgent | [PlanAgentFactory.java#L162](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/PlanAgentFactory.java#L162) |
| TaskPlanningRail | 注册 Todo 工具,afterTaskIteration 同步状态 | [TaskPlanningRail.java#L49](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/TaskPlanningRail.java#L49) |
| afterTaskIteration | 任务迭代后同步 Todo 状态 | [TaskPlanningRail.java#L458](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/TaskPlanningRail.java#L458) |
| TaskCompletionRail | 完成承诺检测 + 任务指令应用 | [TaskCompletionRail.java#L34](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/TaskCompletionRail.java#L34) |
| applyTaskInstruction | 注入/更新任务指令 | [TaskCompletionRail.java#L178](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/TaskCompletionRail.java#L178) |
| CompletionPromiseEvaluator | 检测 `<promise>` 标签并验证兑现 | harness/rails(TaskCompletionRail 内) |
| LoopCoordinator | 停止条件聚合器 | [LoopCoordinator.java#L17](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/task_loop/LoopCoordinator.java#L17) |
| StopConditionEvaluator | 停止条件评估器接口 | [StopConditionEvaluator.java#L12](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/task_loop/StopConditionEvaluator.java#L12) |
| TodoTool | create/list/get/modify 四动作 | [TodoTool.java#L21](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/TodoTool.java#L21) |
| fromConfig | 按 storageType + conf 构造(支持 SPI provider) | [TodoTool.java#L40](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/TodoTool.java#L40) |
| TodoItem | id/content/status/priority 四字段 | [TodoItem.java#L31](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/TodoItem.java#L31) |
| TodoStatus | 六态枚举(TODO/PENDING/IN_PROGRESS/DONE/COMPLETED/CANCELLED) | harness/tools |
| validateSingleInProgress | 不变量:同一时刻仅一个 IN_PROGRESS | harness/tools |

## 三、实现机制

### 3.1 纯规划约束(metadata + Rails 双层)

[PlanAgentFactory.buildPlanAgentConfig#L132](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/PlanAgentFactory.java#L132) 在 metadata 中显式声明只读语义:`readonly=true`、`write_tools_forbidden=true`、`allowed_shell_intent=read_only`、`requires_critical_files=true`、`critical_files_min=3`、`critical_files_max=5`,并把禁用操作列入 `forbidden_operations`:`write_file / edit_file / mkdir / touch / rm / cp / mv / git add / git commit / install_dependencies / shell_redirection`(对照 Python 版 L32-L52)。`executionMode=ephemeral`、`role=planning`、`maxIterations` 默认 25(低于 verification_agent 的 40,因为规划不需长探测,但需足够探索预算),`restrictToWorkDir=false`。

Rails 装配通过 `SubAgentRailMergeSupport.mergeRails` 合并两条:`SysOperationRail()`(系统操作约束)与 `SecurityRail(true)`(只读安全 Rail,构造参数 true 表示只读模式)。这两条 Rail 把"只读"从提示软劝升级为机制硬约束:即便模型尝试调用写工具,也会被 Rail 拦截。

### 3.2 纯规划系统提示

[PLAN_AGENT_SYSTEM_PROMPT_CN#L26](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/PlanAgentFactory.java#L26)(英文版 [L58](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/PlanAgentFactory.java#L58) 逐条对齐)把约束写进文本,核心要点:

- **关键约束:只读模式,禁止任何文件修改** — 严禁创建文件(Write/touch)、修改文件(任何编辑)、删除文件(rm)、移动/复制文件(mv/cp)、在任意目录(含 /tmp)创建临时文件、使用重定向或管道写文件(`>`、`>>`、`|`)、执行任何改变系统状态的命令;
- **职责仅限**:探索代码库并设计可执行计划;
- **工作流程四步**:理解需求→充分探索→方案设计→细化计划(拆分步骤、依赖、执行顺序、潜在风险);
- **bash 仅允许只读命令**:ls/git status/git log/git diff/find/grep/cat/head/tail;严禁 mkdir/touch/rm/cp/mv/git add/git commit/npm install/pip install 或任何创建/修改文件的命令;
- **输出要求**:末尾必须给出"Critical Files for Implementation",列出 3-5 个最关键文件路径。

### 3.3 Critical Files 输出与程序化校验

"Critical Files for Implementation"不是装饰性要求,而是把规划产物从"自然语言散文"升级为"可被编码阶段直接消费的结构化输入"。metadata 中的 `critical_files_min=3`、`critical_files_max=5` 让下游可程序化校验数量边界:少于 3 个说明规划不够具体,多于 5 个说明焦点发散。code_agent 拿到这份关键文件清单后,可直接以这些文件为锚点展开编码,而非在规划散文中自行猜测该改哪些文件。

### 3.4 目标状态机(TodoTool + TodoItem)

[TodoTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/TodoTool.java#L21) 暴露四类动作:

- `create` — 新建 TodoItem 列表;
- `list` — 列出全部待办;
- `get` — 读取单条;
- `modify` — 七种子操作:`delete / cancel / update / append / insert_after / insert_before`(及状态推进)。

[TodoItem#L31](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/TodoItem.java#L31) 字段为 `id / content / status / priority`,状态机为 `TODO → PENDING → IN_PROGRESS → DONE → COMPLETED`,以及终态 `CANCELLED`。关键不变量是 `validateSingleInProgress`:同一时刻**仅允许一个** TodoItem 处于 IN_PROGRESS,避免多线并进导致的失焦与状态混乱——这一不变量强制模型"一次只做一件事",是控制 Agent 不发散的核心机制。

[TodoTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/TodoTool.java#L21) 还支持存储 SPI:[fromConfig#L40](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/TodoTool.java#L40) 按 `storageType` 走 `TodoStorageFactory` 注册的 provider 构造(支持自定义存储后端),未命中则回退到基于 `basePath` 的 `FileTodoStorage`(文件存储),保证开箱即用。

[TaskPlanningRail](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/TaskPlanningRail.java#L49) 继承 DeepAgentRail 并实现 `TaskIterationRail`,在 [afterTaskIteration#L458](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/TaskPlanningRail.java#L458) 回调中,把每次迭代产生的进展同步回 Todo 列表,使"目标状态机"始终反映当前任务真实进度,而非停留在模型声称的状态。

### 3.5 完成承诺与停止条件聚合

[TaskCompletionRail#L34](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/TaskCompletionRail.java#L34) 继承 DeepAgentRail,负责完成承诺检测,通过 `CompletionPromiseEvaluator` 识别模型输出中 `<promise>...</promise>` 标签包裹的承诺语句,并在后续迭代中验证承诺是否兑现;[applyTaskInstruction#L178](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/TaskCompletionRail.java#L178) 负责把任务指令注入/更新到当前会话,保证长任务中原始目标不被遗忘。

[LoopCoordinator#L17](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/task_loop/LoopCoordinator.java#L17) 聚合 [StopConditionEvaluator](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/task_loop/StopConditionEvaluator.java#L12) 接口的五类评估器:

1. **CompletionPromiseEvaluator** — 完成承诺兑现即停;
2. **MaxRoundsEvaluator** — 达到最大迭代轮数即停,防止无限循环;
3. **TimeoutEvaluator** — 超时即停,防止卡死;
4. **TokenBudgetEvaluator** — token 预算耗尽即停,控制成本;
5. **CustomPredicateEvaluator** — 用户自定义谓词满足即停,提供扩展点。

任一评估器命中即触发停止,使任务循环不会无限空转。五类评估器分别对应"目标完成""轮数上限""时间上限""成本上限""自定义条件"五种收口维度,覆盖了 Agent 长循环的主要失控风险。

## 四、调用示例

```java
import com.openjiuwen.harness.subagents.PlanAgentFactory;
import com.openjiuwen.harness.subagents.SubAgentConfig;
import com.openjiuwen.harness.tools.TodoTool;
import com.openjiuwen.harness.tools.TodoItem;
import com.openjiuwen.harness.tools.TaskTool;
import com.openjiuwen.harness.deep_agent.DeepAgent;
import com.openjiuwen.harness.factory.HarnessFactory;
import java.util.List;
import java.util.Map;

// 1) 构建纯规划子代理(只读 + Critical Files 输出 + 双 Rail: SysOperationRail + SecurityRail(true))
//    metadata: {readonly=true, write_tools_forbidden=true, allowed_shell_intent=read_only,
//               requires_critical_files=true, critical_files_min=3, critical_files_max=5,
//               forbidden_operations=[write_file,edit_file,mkdir,touch,rm,cp,mv,git add,git commit,...]}
SubAgentConfig planSpec = PlanAgentFactory.buildPlanAgentConfig("cn");
DeepAgent planAgent = HarnessFactory.createDeepAgent(planSpec.getAgentCard(),
        planSpec.toDeepAgentConfig(), workspace);

// 2) 让规划代理产出实现计划与关键文件(末尾必含 "Critical Files for Implementation")
Map<String, Object> planResult = planAgent.invoke(Map.of(
        "query", "为支付服务增加幂等性支持,要求重复支付不产生重复扣款",
        "conversation_id", "plan-session-001"));

// 3) 在主代理上建立目标状态机(validateSingleInProgress 强制同一时刻仅一个 IN_PROGRESS)
TodoTool todo = new TodoTool(workspace.getPath());
List<TodoItem> items = todo.create(List.of(
        new TodoItem("t1", "设计 IdempotencyKey 表结构", "TODO", "high"),
        new TodoItem("t2", "在支付入口加幂等校验", "TODO", "high"),
        new TodoItem("t3", "补并发场景测试", "TODO", "medium")));
// 把 t2 推进为 IN_PROGRESS(此时 t1/t3 必须保持非 IN_PROGRESS)
todo.modify("t2", "update", new TodoItem("t2", "在支付入口加幂等校验", "IN_PROGRESS", "high"));

// 4) 委派规划任务给 plan_agent(code_agent 已自动注入 plan_agent)
TaskTool taskTool = new TaskTool(codeAgent);
taskTool.delegate("plan_agent", "细化 t2 的实现步骤并给出 3-5 个关键文件", "code-session-001");
// plan_agent 在只读沙箱中探索 + 设计, 不会动任何文件
```

## 五、业界对比

| 维度 | agent-core-java | Spring AI | LangChain4j | Python agent-core |
|------|-----------------|-----------|-------------|-------------------|
| 独立规划子代理 | ✅ plan_agent 工厂化、只读 | ❌ 无内置,需自建 | ❌ 无内置 | ✅ plan_agent(对齐源) |
| 纯规划约束(禁写/禁 mv/cp/git commit) | ✅ 提示 + metadata forbidden_operations + SecurityRail | ❌ | ❌ | ✅ 同 |
| Critical Files 输出 | ✅ 强制 3-5 个,可程序化校验 | ❌ | ❌ | ✅ 同 |
| Todo 工具 | ✅ create/list/get/modify + 7 子操作 | ❌ 无内置 | ❌ 无内置 | ✅ 同 |
| 目标状态机 | ✅ 六态 + validateSingleInProgress | ❌ | ❌ | ✅ 同 |
| token 预算 + 尝试次数 | ✅ TokenBudget + MaxRounds 评估器 | ⚠️ 仅基础 token 计费 | ⚠️ 仅基础 | ✅ 同 |
| 完成承诺检测 | ✅ `<promise>` 标签 + 兑现验证 | ❌ | ❌ | ✅ 同 |
| 存储 SPI 扩展 | ✅ TodoStorageFactory + provider | ⚠️ 需自建 | ⚠️ 需自建 | ✅ 同 |

## 六、小结

agent-core-java 的编码规划能力是**已实现**的双主线体系:一条线是只读的 plan_agent 子代理,用"纯规划约束(metadata forbidden_operations + SecurityRail(true) 双层)+ Critical Files 输出(critical_files_min/max 程序化校验)"把规划产物从散文变成可消费的结构化输入,并从机制上杜绝规划阶段误改文件;另一条线是 TodoTool + TodoItem + TaskPlanningRail + TaskCompletionRail + LoopCoordinator 构成的目标状态机与停止条件聚合器,用六态状态机、单 IN_PROGRESS 不变量、`<promise>` 承诺检测、五类停止评估器,确保任务循环"目标清晰、进度可同步、收口有据"。

存储层面,TodoTool 通过 TodoStorageFactory 支持 SPI provider 扩展,未命中回退 FileTodoStorage,兼顾可扩展与开箱即用。停止条件层面,五类评估器(承诺兑现/轮数上限/超时/token 预算/自定义谓词)覆盖了 Agent 长循环的主要失控风险,任一命中即收口,既防止模型无限空转,也防止成本失控。

设计哲学上,本能力体现了"规划与执行分离"的工程原则:plan_agent 在只读沙箱中专注架构思考,其产出(Critical Files + 实现步骤)作为 code_agent 的结构化输入;而 code_agent 编码过程中的进度又通过 Todo 状态机持续同步与收口。两条主线一前一后,形成"先想清楚再动手,且动手过程可追踪、可收口"的闭环。

工程层面,plan_agent 的 maxIterations=25 低于 verification_agent 的 40,体现"规划不需长探测但需足够探索预算"的差异化预算配置;而 TodoTool 的 SPI provider 扩展与 FileTodoStorage 回退,兼顾企业级存储集成与开箱即用。

与 Spring AI / LangChain4j 相比,二者均不内置规划子代理与目标状态机,需用户从零搭建;agent-core-java 在此维度与 Python 版实现对齐,具备工程化优势,可直接用于"规划-编码-收口"的自动化任务场景。
