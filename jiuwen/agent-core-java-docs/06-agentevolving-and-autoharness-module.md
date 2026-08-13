# agentevolving 与 autoharness 模块

> 交叉引用: [01-project-overview](01-project-overview.md) | [02-overall-architecture](02-overall-architecture.md) | [04-harness-and-deepagents-module](04-harness-and-deepagents-module.md) | [05-agentteams-module](05-agentteams-module.md)

本篇描述 agent-core-java 中两个面向"演化与自动化"的高阶模块:`agentevolving` 提供
基于强化学习的 Agent 自优化训练框架;`autoharness` 提供端到端的自动化测试与改码基础设施。
两者共享轨迹(Trajectory)、检查点(Checkpoint)、经验(Experience)等概念,共同支撑 Agent 的
"持续进化"闭环。

## 一、模块职责

### 1.1 agentevolving 模块职责

`agentevolving` 模块对应 Python 端 `openjiuwen.agent_evolving`,其核心目标是让 Agent
通过"评估 → 轨迹采集 → 反向传播 → 参数更新 → 检查点"的循环实现自我优化。模块由如下
子领域组成:

- **训练编排(Trainer)**:串联 evaluate/forward/update/writeback,驱动整个训练循环;
- **评估器(Evaluator)**:对 Agent 在任务集合上的表现打分,产出 reward 信号;
- **优化器(Optimizer)**:在三个维度上做反向传播与参数步进,包括
  指令优化(Instruction)、工具描述优化(Tool)、记忆优化(Memory);
- **更新器(Updater)**:单维与多维的归因/分配,把梯度落回具体可调参数;
- **检查点(Checkpointing)**:训练中间态的保存与恢复,支撑断点续训;
- **轨迹(Trajectory)**:从 session.tracer 抽取步骤与边,构建可被优化器消费的样本;
- **agent_rl 子模块**:Reward 注册表、Rollout、RLTask,以及 online/offline 两套配置
  (OnlineRLConfig/TrainingConfig 与 RLConfig/Verl*HydraOverlay)。

### 1.2 autoharness 模块职责

`autoharness` 模块对应 Python 端 `rsi/auto_harness`,定位为"端到端改码"的自动化测试与
评估基础设施。其职责包括:

- **编排(Orchestrator)**:选择 Pipeline 并运行一个完整 Session;
- **Gap 评估**:发现"差距"并按 `priority = impact * feasibility` 排序;
- **Stage 全集**:assess / plan / implement / verify / commit / publish_pr / learnings
  共 7 个阶段,可灵活组合;
- **Pipeline**:MetaEvolve(默认,Assess → Plan → 多个 PRTaskPipeline → Learnings)
  与 ExtendedEvolve(stub);
- **PRTaskPipeline 隔离运行**:在独立 worktree 中执行 implement→verify→commit→publish_pr,
  内置 experience 检索与三 Agent 协作;
- **基础设施**:GitOperations、GitHubCli、CIGateRunner、FixLoopController(两阶段重试)、
  SessionBudgetController、WorktreeManager。

## 二、关键类与函数

### 2.1 agentevolving 关键类

| 类/函数 | 文件位置 | 说明 |
| --- | --- | --- |
| Trainer | [Trainer.java#L47](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentevolving/trainer/Trainer.java#L47) | 训练编排器;`train` L101 编排 evaluate→update→writeback;`forward` L209;`evaluate` L178;Builder L702 |
| BaseEvaluator | [BaseEvaluator.java#L32](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentevolving/evaluator/BaseEvaluator.java#L32) | 评估器基类;`evaluate` L41;`batchEvaluate` L52 |
| BaseOptimizer | [BaseOptimizer.java#L35](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentevolving/optimizer/BaseOptimizer.java#L35) | 优化器基类;`bind` L144;`backward` L198 → `doBackward` 抽象;`step` L215 → `doStep` 抽象 |
| InstructionOptimizer | [InstructionOptimizer.java#L40](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentevolving/optimizer/llm_call/InstructionOptimizer.java#L40) | 基于 LLM 的指令优化(textual gradient) |
| ToolOptimizerBase | [ToolOptimizerBase.java#L21](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentevolving/optimizer/tool_call/ToolOptimizerBase.java#L21) | 工具描述可调(tool_description tunable) |
| MemoryOptimizerBase | [MemoryOptimizerBase.java](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentevolving/optimizer/memory_call/MemoryOptimizerBase.java) | 记忆维度优化基类 |
| Updater | [Updater.java#L22](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentevolving/updater/Updater.java#L22) | 更新器接口;`bind` L32;`update` L51 |
| SingleDimUpdater | [SingleDimUpdater.java#L25](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentevolving/updater/SingleDimUpdater.java#L25) | 单维更新器;`update` L79 |
| MultiDimUpdater | [MultiDimUpdater.java#L23](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentevolving/updater/MultiDimUpdater.java#L23) | 多维更新器抽象(归因/分配) |
| CheckpointManager | [CheckpointManager.java#L15](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentevolving/checkpointing/CheckpointManager.java#L15) | 检查点管理接口 |
| DefaultCheckpointManager | [DefaultCheckpointManager.java#L21](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentevolving/checkpointing/DefaultCheckpointManager.java#L21) | 默认实现;`shouldSave` L72;配套 FileCheckpointStore |
| Trajectory | [Trajectory.java#L16](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentevolving/trajectory/Trajectory.java#L16) | 轨迹;L70 全参构造 |
| TracerTrajectoryExtractor | [TracerTrajectoryExtractor.java#L24](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentevolving/trajectory/TracerTrajectoryExtractor.java#L24) | `extract` L33-57,从 session.tracer 构建 steps/edges |
| RewardRegistry | [RewardRegistry.java#L23](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentevolving/agent_rl/RewardRegistry.java#L23) | 奖励注册表;`register` L77;`get` L93;配套 Rollout/RLTask |
| OnlineRLConfig / TrainingConfig | agent_rl/config/onlineconfig | 在线 RL 配置 |
| RLConfig / Verl*HydraOverlay | agent_rl/config/offlineconfig | 离线 RL 配置(Verl Hydra Overlay) |

### 2.2 autoharness 关键类

| 类/函数 | 文件位置 | 说明 |
| --- | --- | --- |
| AutoHarnessOrchestrator | [AutoHarnessOrchestrator.java#L42](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/orchestrator/AutoHarnessOrchestrator.java#L42) | 编排器;`runSession` L118;`selectPipeline` L159 |
| Gap | [Gap.java#L24](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/schema/Gap.java#L24) | 差距描述;`priority` L55 = impact * feasibility |
| BaseStage | [BaseStage.java#L17](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/stages/BaseStage.java#L17) | Stage 抽象基类;`name` L24;`run` L71;`stream` L82;SessionStage/TaskStage 基类 |
| AssessStage | stages/ | name="assess" L49;produces=["assessment"] |
| PlanStage | stages/ | name="plan";produces=["task_plan"] |
| ImplementStage | stages/ | name="implement" |
| VerifyStage | stages/ | name="verify";produces=["verify_report"] |
| CommitStage | stages/ | name="commit";produces=["commit"] |
| PublishPrStage | stages/ | name="publish_pr";produces=["pull_request"] |
| LearningsStage | stages/ | name="learnings" |
| BasePipeline | [BasePipeline.java#L20](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/pipelines/BasePipeline.java#L20) | Pipeline 基类;`streamStage` L78;`requireStageResult` L106 |
| MetaEvolvePipeline | [MetaEvolvePipeline.java#L25](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/pipelines/MetaEvolvePipeline.java#L25) | 默认 Pipeline;`stream` L74-91(Assess→Plan→per task PRTaskPipeline→Learnings) |
| PRTaskPipeline | [PRTaskPipeline.java#L46](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/pipelines/PRTaskPipeline.java#L46) | 隔离运行;`runIsolatedStream` L160(单线程隔离,带 taskTimeoutSecs);Implement→Verify→Commit→PublishPr |
| BuiltinRegistries | [BuiltinRegistries.java#L29](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/registry/BuiltinRegistries.java#L29) | `buildStageRegistry` L55;`buildPipelineRegistry` L88 |
| ExperienceStore | [ExperienceStore.java#L28](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/experience/ExperienceStore.java#L28) | 经验存储;`record` L58(24h 去重);`search` L109(关键词+近期加分 30 天衰减);`listRecent` L82 |
| GitOperations / GitHubCli / CIGateRunner / FixLoopController / SessionBudgetController / WorktreeManager | autoharness/infra/ | 基础设施组件;FixLoopController 支持两阶段重试 |

## 三、核心机制

### 3.1 Trainer 训练循环

`Trainer.train`(L101)是 agentevolving 的主循环,其编排顺序为:

1. **baseline evaluate**:在训练开始前对 Agent 做一次基线评估,记录初始 reward;
2. **for epoch**:进入训练轮次循环:
   - `forward`(L209)执行当前 Agent,采集 Trajectory;
   - `updater.update`(L51)将优化器产出的梯度更新落回参数;
   - `applyUpdates`:把更新写入 Agent 实例;
   - `evaluate`(L178)在当前任务集上重新打分;
   - `saveCheckpointIfNeeded`(L371)按条件持久化检查点。
3. **断点续训**:`resumeIfNeeded`(L343)在启动时尝试加载已有检查点,跳过已完成 epoch。

### 3.2 三维度优化器

`BaseOptimizer`(L35)定义统一的 `bind` → `backward` → `step` 协议:

- `bind`(L144):将优化器绑定到具体的 Agent 与 Updater;
- `backward`(L198):执行反向传播,内部转交给抽象方法 `doBackward`;
- `step`(L215):执行参数步进,内部转交给抽象方法 `doStep`。

三个子类分别覆盖不同可调维度:

- **InstructionOptimizer**(L40):对 Agent 的系统指令做"textual gradient"优化,即用 LLM
  生成对当前指令的"梯度"描述并据此改写;
- **ToolOptimizerBase**(L21):把 `tool_description` 作为可调参数,优化工具签名与描述;
- **MemoryOptimizerBase**:把记忆条目/检索策略作为可调参数。

### 3.3 Updater 单维/多维

`Updater`(L22)接口定义 `bind`(L32)与 `update`(L51)。两个实现:

- **SingleDimUpdater**(L25)的 `update`(L79)针对单一维度直接落参;
- **MultiDimUpdater**(L23)是抽象类,需子类实现归因(attribution)与分配(allocation),
  把一个标量 reward 分配到多个可调维度上。

### 3.4 检查点 save/restore

`CheckpointManager`(L15)是接口,`DefaultCheckpointManager`(L21)是默认实现。其
`shouldSave`(L72)按间隔/改进幅度决定是否落盘;配套 `FileCheckpointStore` 把状态写入文件。
Trainer 在 L343(`resumeIfNeeded`)与 L371(`saveCheckpointIfNeeded`)两处与之交互。

### 3.5 轨迹从 tracer 提取

`Trajectory`(L16)在 L70 提供全参构造,封装 step/edge。`TracerTrajectoryExtractor`
(L24)的 `extract`(L33-57)从 `session.tracer` 中读取已记录的 step 与 edge,组装为
Trajectory 列表供优化器消费。

### 3.6 agent_rl 子模块

`RewardRegistry`(L23)提供 `register`(L77)与 `get`(L93),管理命名 reward 函数;
Rollout 与 RLTask 封装在线采样任务。配置层分两套:

- **onlineconfig**:`OnlineRLConfig`/`TrainingConfig` 用于在线训练;
- **offlineconfig**:`RLConfig`/`Verl*HydraOverlay` 用于离线训练(基于 Verl 的 Hydra Overlay)。

### 3.7 autoharness 7 Stage 全集

7 个 Stage 覆盖完整改码链路:

| Stage | 名称 | 产出 |
| --- | --- | --- |
| AssessStage | assess | assessment |
| PlanStage | plan | task_plan |
| ImplementStage | implement | (代码改动) |
| VerifyStage | verify | verify_report |
| CommitStage | commit | commit |
| PublishPrStage | publish_pr | pull_request |
| LearningsStage | learnings | (经验沉淀) |

`BaseStage`(L17)定义 `name`(L24)、`run`(L71)、`stream`(L82);SessionStage 与 TaskStage
是两类基类,前者面向整个 Session,后者面向单 Task。

### 3.8 Pipeline 组合

- **MetaEvolvePipeline**(L25)是默认 Pipeline,`stream`(L74-91)按
  Assess → Plan → **per task PRTaskPipeline** → Learnings 顺序产出;
- **ExtendedEvolvePipeline** 为 stub,留给上层扩展;
- `BasePipeline`(L20)提供 `streamStage`(L78)与 `requireStageResult`(L106),
  后者在前置 Stage 缺失产出时抛错。

### 3.9 PRTaskPipeline 隔离运行

`PRTaskPipeline`(L46)的 `runIsolatedStream`(L160)在单线程隔离环境内运行,关键点:

- **worktree 隔离**:每个 Task 在独立 git worktree 中改码,互不干扰;
- **experience 检索**:运行前从 `ExperienceStore` 检索相似历史经验;
- **三 Agent 协作**:Implement → Verify → Commit → PublishPr 四个 Stage 各自驱动 Agent;
- **taskTimeoutSecs**:单 Task 超时保护。

### 3.10 Gap 排序与 Experience 检索

`Gap`(L24)的 `priority`(L55)= `impact * feasibility`,用于在 Plan Stage 中对多个候选
Gap 排序。`ExperienceStore`(L28)提供:

- `record`(L58):记录经验,带 24h 去重;
- `search`(L109):关键词检索 + 近期加分(30 天衰减);
- `listRecent`(L82):列出最近经验。

## 四、调用示例

### 4.1 agentevolving 训练示例

```java
import com.openjiuwen.agentevolving.trainer.Trainer;
import com.openjiuwen.agentevolving.evaluator.BaseEvaluator;
import com.openjiuwen.agentevolving.optimizer.llm_call.InstructionOptimizer;
import com.openjiuwen.agentevolving.updater.SingleDimUpdater;
import com.openjiuwen.agentevolving.checkpointing.DefaultCheckpointManager;
import com.openjiuwen.agentevolving.trajectory.TracerTrajectoryExtractor;

BaseEvaluator evaluator = BaseEvaluator.builder()
    .tasks(rlTaskList)
    .rewardRegistry(RewardRegistry.get("default"))
    .build();

InstructionOptimizer optimizer = InstructionOptimizer.builder()
    .llmCall(llmCall)
    .updater(new SingleDimUpdater())
    .build();

DefaultCheckpointManager checkpointManager =
    DefaultCheckpointManager.builder()
        .store(new FileCheckpointStore(Path.of("./ckpt")))
        .build();

Trainer trainer = Trainer.builder()
    .agent(myAgent)
    .evaluator(evaluator)
    .optimizer(optimizer)
    .trajectoryExtractor(new TracerTrajectoryExtractor())
    .checkpointManager(checkpointManager)
    .epochs(5)
    .build();

trainer.train();   // 触发 evaluate→forward→update→writeback 循环
```

### 4.2 autoharness 编排示例

```java
import com.openjiuwen.autoharness.orchestrator.AutoHarnessOrchestrator;
import com.openjiuwen.autoharness.registry.BuiltinRegistries;
import com.openjiuwen.autoharness.experience.ExperienceStore;

ExperienceStore experience = ExperienceStore.builder()
    .storePath(Path.of("./exp"))
    .build();

AutoHarnessOrchestrator orchestrator = AutoHarnessOrchestrator.builder()
    .stageRegistry(BuiltinRegistries.buildStageRegistry())
    .pipelineRegistry(BuiltinRegistries.buildPipelineRegistry())
    .experienceStore(experience)
    .worktreeManager(new WorktreeManager(Path.of("./worktrees")))
    .budget(new SessionBudgetController(Duration.ofHours(2)))
    .build();

orchestrator.runSession(sessionConfig);    // 默认走 MetaEvolvePipeline
```

## 五、与 Python agent-core 对照

| Java (agent-core-java) | Python (agent-core) | 对照说明 |
| --- | --- | --- |
| agentevolving 模块 | openjiuwen.agent_evolving | 模块对等 |
| Trainer | Trainer | 训练编排器对等 |
| BaseEvaluator | Evaluator | 评估器对等 |
| BaseOptimizer / InstructionOptimizer / ToolOptimizerBase / MemoryOptimizerBase | Optimizer / Instruction / Tool / Memory | 三维度优化器对等 |
| SingleDimUpdater / MultiDimUpdater | Updater 单维/多维 | 更新器对等 |
| DefaultCheckpointManager / FileCheckpointStore | CheckpointManager | 检查点对等 |
| Trajectory / TracerTrajectoryExtractor | Trajectory / extractor | 轨迹对等 |
| RewardRegistry / Rollout / RLTask | RewardRegistry / Rollout / RLTask | agent_rl 对等 |
| autoharness 模块 | rsi/auto_harness | 模块对等 |
| AutoHarnessOrchestrator | AutoHarnessOrchestrator | 编排器对等 |
| AssessStage/PlanStage/.../LearningsStage | 7 stages | 7 阶段对等 |
| ImplementStage | MetaImplementStage | 实现阶段对等 |
| FixLoopController | FixLoopController | 两阶段重试对等 |
| MetaEvolvePipeline / PRTaskPipeline | MetaEvolve / PRTask | Pipeline 对等 |
| ExperienceStore | ExperienceStore | 经验存储对等 |

## 六、小结

`agentevolving` 与 `autoharness` 共同构成 agent-core-java 的"自演化"层:前者从
Agent 内部参数(指令/工具/记忆)入手,通过 Trainer 循环做 RL 式自优化;后者从
Agent 外部行为入手,通过 7 个 Stage 与隔离 Pipeline 自动改码并沉淀经验。两者通过
Trajectory/Checkpoint/Experience 三个共享概念串联,既可独立使用,也可组合成
"先 autoharness 改码 → 再 agentevolving 调参"的更高阶闭环。
