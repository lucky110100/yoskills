# 端到端自动改码与 CI 修复

> 交叉引用: [01-project-overview](../../01-project-overview.md) | [02-overall-architecture](../../02-overall-architecture.md) | [04-harness-and-deepagents-module](../../04-harness-and-deepagents-module.md) | [06-agentevolving-and-autoharness-module](../../06-agentevolving-and-autoharness-module.md)

## 一、能力概述

AutoHarness(自动改码套件)是 agent-core-java 对 Python `rsi/auto_harness` 的对等实现,定位为"端到端自动化改码会话"。一条会话从仓库评估、缺口识别、任务规划,到代码实现、CI 验证、提交、发布 PR,再到经验沉淀,由编排器统一串联,中间任一阶段失败可触发 CI 修复循环回退。

**实现状态:已实现。** 该能力对应模块 `com.openjiuwen.autoharness`,包含编排器、7 个内置阶段、2 条内置流水线、经验库、以及 Git/GitHub CLI/CI 门禁/修复循环/预算/Worktree 等基础设施,与 Python 版能力对等。

设计要点:

- **阶段化**:改码会话被拆为 7 个可复用阶段(assess/plan/implement/verify/commit/publish_pr/learnings),每个阶段声明 `name`、`produces`,产出以 artifact 形式落入上下文。
- **流水线编排**:流水线组合阶段形成执行链;默认 `meta_evolve_pipeline` 串接 Assess→Plan→(每任务 PRTaskPipeline)→Learnings。
- **任务隔离**:每个任务在 `PRTaskPipeline` 中以单线程隔离执行,带 `taskTimeoutSecs` 超时保护,调用链 Implement→Verify→Commit→PublishPr。
- **CI 修复循环**:`FixLoopController` 提供两阶段重试,CI 门禁失败后自动回到实现阶段修复。
- **经验沉淀**:`ExperienceStore` 以 24 小时去重写入、关键词命中 + 近期加权检索,跨会话复用经验。
- **预算约束**:会话总时长、单任务超时、成本上限三重预算由 `SessionBudgetController` 统一管控,任一超限即终止后续阶段。

## 二、关键类与函数

| 类/函数 | 职责 | 位置 |
| --- | --- | --- |
| AutoHarnessOrchestrator | 会话编排入口,持有注册表/经验/预算/CI/Git/Worktree | [AutoHarnessOrchestrator.java#L42](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/orchestrator/AutoHarnessOrchestrator.java#L42) |
| runSession | 同步执行会话,返回各 Cycle 结果 | [AutoHarnessOrchestrator.java#L118](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/orchestrator/AutoHarnessOrchestrator.java#L118) |
| selectPipeline | 根据任务显式 pipeline_name 或默认策略选择流水线 | [AutoHarnessOrchestrator.java#L159](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/orchestrator/AutoHarnessOrchestrator.java#L159) |
| Gap | 缺口描述(impact×feasibility 优先级排序) | [Gap.java#L24](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/schema/Gap.java#L24) |
| Gap.priority | 优先级 = impact × feasibility | [Gap.java#L55](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/schema/Gap.java#L55) |
| BaseStage | 阶段抽象基类,定义 name/run/stream 契约 | [BaseStage.java#L17](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/stages/BaseStage.java#L17) |
| BaseStage.name | 阶段标识(抽象) | [BaseStage.java#L24](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/stages/BaseStage.java#L24) |
| BaseStage.run | 阻塞执行,返回 StageResult | [BaseStage.java#L71](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/stages/BaseStage.java#L71) |
| BaseStage.stream | 流式执行,默认包裹 run | [BaseStage.java#L82](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/stages/BaseStage.java#L82) |
| AssessStage | 评估阶段,produces=["assessment"] | [AssessStage.java#L49](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/stages/AssessStage.java#L49) |
| ImplementStage | 实现阶段,强制产出代码改动 | [ImplementStage.java#L47](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/stages/ImplementStage.java#L47) |
| BasePipeline | 流水线基类,提供阶段编排与 artifact 取用 | [BasePipeline.java#L20](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/pipelines/BasePipeline.java#L20) |
| BasePipeline.streamStage | 流式执行单个阶段并收集事件 | [BasePipeline.java#L78](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/pipelines/BasePipeline.java#L78) |
| BasePipeline.requireStageResult | 强制要求某 artifact 存在,缺失即失败 | [BasePipeline.java#L106](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/pipelines/BasePipeline.java#L106) |
| MetaEvolvePipeline | 默认元进化流水线:Assess→Plan→每任务→Learnings | [MetaEvolvePipeline.java#L25](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/pipelines/MetaEvolvePipeline.java#L25) |
| MetaEvolvePipeline.stream | 流式编排主入口 | [MetaEvolvePipeline.java#L74](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/pipelines/MetaEvolvePipeline.java#L74) |
| PRTaskPipeline | 单任务流水线,隔离执行四阶段 | [PRTaskPipeline.java#L46](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/pipelines/PRTaskPipeline.java#L46) |
| PRTaskPipeline.runIsolatedStream | 单线程隔离执行,带任务超时 | [PRTaskPipeline.java#L160](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/pipelines/PRTaskPipeline.java#L160) |
| BuiltinRegistries | 内置阶段/流水线注册表工厂 | [BuiltinRegistries.java#L29](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/registry/BuiltinRegistries.java#L29) |
| buildStageRegistry | 注册 7 个内置阶段 | [BuiltinRegistries.java#L55](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/registry/BuiltinRegistries.java#L55) |
| buildPipelineRegistry | 注册 2 条内置流水线 | [BuiltinRegistries.java#L88](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/registry/BuiltinRegistries.java#L88) |
| ExperienceStore | 经验库,JSONL 持久化 | [ExperienceStore.java#L28](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/experience/ExperienceStore.java#L28) |
| ExperienceStore.record | 写入经验,24 小时去重 | [ExperienceStore.java#L58](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/experience/ExperienceStore.java#L58) |
| ExperienceStore.listRecent | 按时间倒序取最近 N 条 | [ExperienceStore.java#L82](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/experience/ExperienceStore.java#L82) |
| ExperienceStore.search | 关键词命中 + 近期加权(30 天衰减)检索 | [ExperienceStore.java#L109](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/experience/ExperienceStore.java#L109) |
| FixLoopController | 两阶段 CI 修复循环 | [FixLoopController.java](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/infra/FixLoopController.java) |
| CIGateRunner | CI 门禁运行器 | [CIGateRunner.java](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/infra/CIGateRunner.java) |
| GitHubCli | GitHub CLI 封装(PR 发布) | [GitHubCli.java](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/infra/GitHubCli.java) |
| WorktreeManager | Git Worktree 隔离管理 | [WorktreeManager.java](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/infra/WorktreeManager.java) |
| SessionBudgetController | 会话预算(时间/成本)控制 | [SessionBudgetController.java](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/infra/SessionBudgetController.java) |

> 说明:`SessionStage`、`TaskStage` 同样继承自 `BaseStage`,分别作为会话级与任务级阶段的基类,为上下文绑定提供载体。`PlanStage`/`VerifyStage`/`CommitStage`/`PublishPrStage`/`LearningsStage` 与 `AssessStage`/`ImplementStage` 一道构成 7 个内置阶段,产出 artifact 分别为 `task_plan`/`verify_report`/`commit`/`pull_request` 等。除 `MetaEvolvePipeline` 外,`BuiltinRegistries` 还注册了 `ExtendedEvolvePipeline`,二者共同构成 2 条内置流水线。

## 三、实现机制

### 1. 编排器与会话生命周期

[AutoHarnessOrchestrator](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/orchestrator/AutoHarnessOrchestrator.java#L42) 在构造期一次性装配全部依赖:通过 [BuiltinRegistries.buildStageRegistry](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/registry/BuiltinRegistries.java#L55) 与 [buildPipelineRegistry](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/registry/BuiltinRegistries.java#L88) 构建阶段与流水线注册表,并初始化 `GitOperations`、`ExperienceStore`、`SessionBudgetController`、`FixLoopController`、`WorktreeManager`、`CIGateRunner`。

会话入口 [runSession](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/orchestrator/AutoHarnessOrchestrator.java#L118) 内部委托 `runSessionStream`:清空历史结果、启动预算计时、记录输入任务 artifact,然后调用 [selectPipeline](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/orchestrator/AutoHarnessOrchestrator.java#L159) 选定流水线,实例化后以流式方式驱动,聚合事件返回。`selectPipeline` 优先尊重任务显式声明的 `pipeline_name`,冲突时抛出异常;无显式声明时回退默认策略。

### 2. 阶段与流水线

所有阶段继承抽象基类 [BaseStage](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/stages/BaseStage.java#L17),需实现 [name](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/stages/BaseStage.java#L24);[run](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/stages/BaseStage.java#L71) 与 [stream](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/stages/BaseStage.java#L82) 提供阻塞与流式两种执行形态,默认 `stream` 包裹 `run`。阶段通过 `consumes`/`produces` 声明 artifact 依赖与产出。

7 个内置阶段在 [BuiltinRegistries](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/registry/BuiltinRegistries.java#L29) 中注册:AssessStage(name=`assess`,produces=`assessment`)、PlanStage(name=`plan`,produces=`task_plan`)、[ImplementStage](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/stages/ImplementStage.java#L47)(name=`implement`)、VerifyStage(name=`verify`,produces=`verify_report`)、CommitStage(name=`commit`,produces=`commit`)、PublishPrStage(name=`publish_pr`,produces=`pull_request`)、LearningsStage(name=`learnings`)。

### 3. MetaEvolvePipeline 主流程

[MetaEvolvePipeline](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/pipelines/MetaEvolvePipeline.java#L25) 是默认流水线,其 [stream](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/pipelines/MetaEvolvePipeline.java#L74) 方法逻辑为:若已带输入任务则直接填充任务计划,否则运行 Assess→Plan 生成任务计划;随后对每个任务驱动 `PRTaskPipeline`;最后运行 Learnings 沉淀经验并存储 `session_results`。阶段间通过 [BasePipeline.requireStageResult](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/pipelines/BasePipeline.java#L106) 强制校验关键 artifact 存在,缺失即提前终止。

### 4. PRTaskPipeline 单任务隔离

[PRTaskPipeline](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/pipelines/PRTaskPipeline.java#L46) 负责单任务的完整改码链:Implement→Verify→Commit→PublishPr。静态方法 [runIsolatedStream](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/pipelines/PRTaskPipeline.java#L160) 以单线程隔离执行,内置 `taskTimeoutSecs` 超时保护,任务级异常被 `StopTaskPipeline` 捕获并优雅返回已收集事件,避免单任务失败拖垮整条会话。`runTaskStageStream` 把具体阶段实例委托给 `BasePipeline` 的流式执行,保证事件聚合一致。

### 5. CI 修复循环与失败回滚

[FixLoopController](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/infra/FixLoopController.java) 实现两阶段重试:第一阶段按固定次数重试实现→验证;第二阶段在第一阶段耗尽后扩大修复策略再试。[CIGateRunner](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/infra/CIGateRunner.java) 运行 CI 门禁并产出通过/失败结果,失败时触发修复循环回到 ImplementStage。配合 `RevertOnFailureRail` 与 [WorktreeManager](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/infra/WorktreeManager.java) 的 Worktree 隔离,失败改动可在独立工作树中回滚而不污染主分支。

### 6. 经验沉淀

[ExperienceStore](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/experience/ExperienceStore.java#L28) 以 JSONL 追加写入经验。[record](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/experience/ExperienceStore.java#L58) 以 24 小时(`DEDUP_WINDOW_SECS=86400`)窗口对同 type+topic 去重;[listRecent](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/experience/ExperienceStore.java#L82) 按时间戳倒序取最近 N 条;[search](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/experience/ExperienceStore.java#L109) 基于关键词命中数,叠加近期加权(30 天衰减)排序,使新近经验更易被召回。

### 7. 与 Python 版对等性

Python `rsi/auto_harness` 提供 `MetaImplementStage`(强制产出 git diff)、`FixLoopController`(两阶段 CI 修复)、`AutoHarnessOrchestrator`。Java 版 7 个阶段与 `ImplementStage`、`FixLoopController`、`AutoHarnessOrchestrator` 均对等实现,artifact 命名与流水线语义一致,可在跨语言对照中直接映射。

### 8. artifact 流转与会话预算

编排器内持有一个 `ArtifactStore`,在会话启动时即写入 `input_tasks` 与 `pipeline_selection` 两个 artifact;各阶段产出的 `assessment`/`task_plan`/`verify_report`/`commit`/`pull_request`/`session_results` 均落入同一 store,后续阶段通过 [requireStageResult](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/pipelines/BasePipeline.java#L106) 取用,形成单向 artifact 流转链,任一前置 artifact 缺失即可提前终止,避免后续阶段空转。

预算由 [SessionBudgetController](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/infra/SessionBudgetController.java) 统一管控:会话启动即 `budget.start()` 计时,结合 `sessionBudgetSecs`(会话总墙钟时长)、`costLimitUsd`(累计成本上限)、`taskTimeoutSecs`(单任务隔离执行超时)三重约束,任一超限即终止后续阶段。CI 门禁的 Python 可执行路径与安装命令由 `CiGateConfig`/`resolveCiGatePythonExecutable()`/`getCiGateInstallCommand()` 注入 [CIGateRunner](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/infra/CIGateRunner.java),修复循环的两阶段重试上限由 `fixPhase1MaxRetries`/`fixPhase2MaxRetries` 注入 [FixLoopController](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/infra/FixLoopController.java),均通过 `AutoHarnessConfig` 集中声明。

## 四、调用示例

```java
import com.openjiuwen.autoharness.orchestrator.AutoHarnessOrchestrator;
import com.openjiuwen.autoharness.schema.AutoHarnessConfig;
import com.openjiuwen.autoharness.schema.OptimizationTask;

import java.nio.file.Path;
import java.util.List;

AutoHarnessConfig config = AutoHarnessConfig.builder()
        .workspace(Path.of("/repo/openjiuwen"))
        .gitRemote("git@githubcode.com:openjiuwen/openjiuwen.git")
        .gitBaseBranch("main")
        .sessionBudgetSecs(3600)
        .taskTimeoutSecs(900)
        .costLimitUsd(5.0)
        .fixPhase1MaxRetries(2)
        .fixPhase2MaxRetries(2)
        .build();

AutoHarnessOrchestrator orchestrator = new AutoHarnessOrchestrator(config);

List<OptimizationTask> tasks = List.of(
        OptimizationTask.builder()
                .title("补充 ExperienceStore.search 单测")
                .pipelineName("meta_evolve_pipeline")
                .build());

List<Object> events = orchestrator.runSessionStream(tasks);
events.forEach(System.out::println);

List<CycleResult> results = orchestrator.runSession(tasks);
results.forEach(r -> System.out.println(r.getStatus()));
```

说明:`runSessionStream` 以流式聚合事件,`runSession` 在其基础上返回各 Cycle 结果。任务可显式指定 `pipelineName`,否则由 `selectPipeline` 回退默认 `meta_evolve_pipeline`。

配置项要点:`sessionBudgetSecs` 限制整条会话墙钟时长;`taskTimeoutSecs` 限制单任务隔离执行时长;`costLimitUsd` 限制累计成本;`fixPhase1MaxRetries`/`fixPhase2MaxRetries` 控制 CI 修复两阶段重试次数;`gitBaseBranch` 指定基线分支用于创建任务工作树与提交 PR。多个任务若显式声明不同 `pipeline_name` 会被 `selectPipeline` 判为冲突并抛出 `IllegalArgumentException`。

## 五、业界对比

| 维度 | agent-core-java | Spring AI | LangChain4j | Python agent-core |
| --- | --- | --- | --- | --- |
| 端到端改码会话 | 已实现,7 阶段全链路 | 无内置改码会话 | 无内置改码会话 | 已实现,7 阶段对等 |
| CI 失败自动修复 | 已实现,FixLoopController 两阶段重试 | 无 | 无 | 已实现,FixLoopController 对等 |
| 强制改码校验 | 已实现,requireStageResult + ImplementStage 产出 | 无 | 无 | 已实现,MetaImplementStage 强制 git diff |
| worktree 隔离 | 已实现,WorktreeManager | 无 | 无 | 已实现 |
| 失败回滚 | 已实现,RevertOnFailureRail | 无 | 无 | 已实现 |
| 经验沉淀 | 已实现,ExperienceStore 24h 去重 + 30 天衰减检索 | 无内置 | 无内置 | 已实现,对等 |
| 阶段编排 | 已实现,Stage/Pipeline 双层可扩展 | 无 | 无 | 已实现,对等 |

> 对比说明:Spring AI 与 LangChain4j 聚焦模型调用、RAG 与编排原语,不内置"改码会话"这一垂直能力,故在端到端改码、CI 修复、worktree 隔离、失败回滚、经验沉淀等维度均无对应组件,需要使用方自行拼装;agent-core-java 与 Python agent-core 在这些维度上能力对等,差异主要在语言生态而非功能覆盖。

## 六、小结

AutoHarness 是 agent-core-java 在"自动改码"方向的核心能力,已实现对 Python 版的完整对等:7 阶段、2 流水线、单任务隔离、两阶段 CI 修复、Worktree 隔离、失败回滚与经验沉淀一应俱全。其价值在于把"评估—规划—实现—验证—提交—发布—沉淀"这条原本需要人工串联的链路,固化为可声明、可流式、可恢复的编排模型,并通过 CI 修复循环与经验复用持续提升后续会话的成功率。

使用边界:AutoHarness 假设调用方已具备可用的 Git 远端与 CI 门禁环境(`CIGateRunner` 依赖可执行的 CI 安装命令),`gitBaseBranch` 需为可创建工作树的干净基线;会话预算一旦超限即终止,不适合超长跑批任务。开发者只需提供 `AutoHarnessConfig` 与任务列表即可驱动一条端到端改码会话,自定义阶段与流水线亦可通过 `BuiltinRegistries` 的注册扩展点接入。
