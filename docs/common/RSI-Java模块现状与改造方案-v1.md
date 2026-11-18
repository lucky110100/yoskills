# Java agent-core-java RSI 模块现状分析与改造方案报告

> 分析对象：`D:/jiuwen/main/agent-core-java/`
> 分析日期：2026-11-17
> 分析人：工程师 寇豆码

---

## 1. RSI 相关代码搜索结果

**结论：Java 版完全不存在 RSI 模块。**

搜索关键词 `rsi`、`RSI`、`self_improv`、`self-improv`、`harness_rsi`、`recursive`、`self-improvement`、`evolution`、`promotion` 等在整个 Java 项目源码中零命中。Python 版 `openjiuwen/rsi/` 模块在 Java 侧没有任何对应实现。Java 项目 `.auto_harness/repo/agent-core/` 下有 Python 版完整克隆（含 RSI），但 Java 源码未翻译。

---

## 2. 现有架构概述

agent-core-java 使用 Maven 多模块构建（groupId=com.openjiuwen, version=0.1.17），顶层 reactor 包含 3 个模块：`core/`、`retrieval/`、`memory/`。源码在 `core/src/main/java/com/openjiuwen/` 下。

| 包名 | 职责 | Python 对应 |
|------|------|-------------|
| `core/` | SDK 运行时：Agent、Session、Runner、graph 执行引擎、存储、工具 | `openjiuwen.core` |
| `harness/` | 编码 Agent 框架：prompts/sections、rails、tools、subagents、task_loop、harness_config | `openjiuwen.harness` |
| `agentevolving/` | RL 优化、评测器、优化器、经验管理、轨迹管理 | `openjiuwen.agent_evolving` |
| `auto_harness/` | 自动化测试/评估流水线：orchestrator、pipelines、stages、infra | `openjiuwen.auto_harness` |
| `agentteams/` | 多智能体团队框架 | `openjiuwen.agent_teams` |
| `deepagents/` | 深度 Agent 框架 | `openjiuwen.deepagents` |
| `dev_tools/` | 开发工具：tune/evaluator | `openjiuwen.dev_tools` |
| `extensions/` | 可选集成 | `openjiuwen.extensions` |
| `spi/` | SPI 存储扩展接口 | `openjiuwen.spi` |

---

## 3. Harness 可编辑面（已存在，与 Python 对齐）

Java版已有完整的 harness 可编辑面：

1. **Prompt Sections**（`harness/prompts/sections/`）：19个section类（IdentitySection, SafetySection, SkillsSection, TodoSection, WorkspaceSection, ContextSection, MemorySection等）
2. **Rails**（`harness/rails/`）：基础rails + `rails/evolution/`（EvolutionRail, SkillEvolutionRail等16个类）+ `rails/skills/`（SkillCreateRail, SkillUseRail）+ `rails/security/` + `rails/subagent/`
3. **Tools**（`harness/tools/`）：tools/skills/、tools/worktree/（14个类）、tools/shell/、tools/browser/等
4. **Harness Config**（`harness/harness_config/`）：HarnessConfig（YAML schema）、Builder、Loader、Registry、ResolvedHarnessConfig
5. **DeepAgent**（`harness/deep_agent/`）：DeepAgent核心运行时、DeepAgentSession
6. **Task Loop**（`harness/task_loop/`）：TaskLoopController、TaskLoopEventExecutor等8个类

---

## 4. Evaluator/Evaluation 相关代码（已存在但非RSI）

Java版有两套独立评测器：

1. **`agentevolving/evaluator/`** — RL训练评测器：BaseEvaluator、DefaultEvaluator（LLM-as-judge）、evaluator_pipeline/、metrics/（Metric、ExactMatchMetric、LLMAsJudgeMetric）
2. **`dev_tools/tune/evaluator/`** — 调参评测器

**关键区别**：这两套评测器面向RL训练和调参，与RSI的TeamEvaluator（评测Team Skill + member harness组合）目标不同。

---

## 5. 改造方案总览

在 Java 版新增 `com.openjiuwen.rsi` 顶层包，作为独立 Maven 模块 `agent-core-rsi-java` 集成。设计原则：
1. **复用现有基础设施**：利用 Java 已有的 harness/、agentevolving/、auto_harness/
2. **接口优先**：通过 Java interface 定义扩展点，不修改现有核心类
3. **SPI 插件化**：与 retrieval/memory 一致，通过 ServiceLoader 按需加载
4. **渐进式翻译**：按 Python rsi/ 模块结构逐包翻译

### 新增模块清单

```
agent-core-rsi-java/  (Maven module)
└── src/main/java/com/openjiuwen/rsi/
    ├── schema/                    # 公共 Schema（无外部依赖）
    │   ├── RsiSchema.java         # RsiTaskCreateRequest, RsiTaskEnvelope, RsiStatus, RsiScenario
    │   ├── RsiUsage.java          # RsiUsage, RsiUsageTokens, RsiModelCall
    │   ├── RsiTreeNode.java       # RsiTreeNode, RsiChange, TreeResponse
    │   └── EngineTypes.java       # EngineResult, EngineState, EngineReport, ArtifactRef
    ├── RsiEvents.java             # 事件系统
    ├── harness_rsi/               # C类主链路
    │   ├── HarnessRsiSchema.java
    │   ├── config/
    │   ├── single_harness/
    │   │   ├── SingleHarnessIterativeOptimizationOrchestrator.java
    │   │   ├── IterativeSingleHarnessRequest.java
    │   │   ├── IterativeSingleHarnessResult.java
    │   │   ├── PromotionPolicy.java
    │   │   └── PromotionResult.java
    │   ├── member_optimizer/
    │   │   ├── MemberOptimizer.java
    │   │   ├── ActionPlanner.java
    │   │   ├── ActionExecutor.java
    │   │   ├── RoleAttributor.java
    │   │   ├── MechanismAttributor.java
    │   │   ├── MemberSelector.java
    │   │   ├── HarnessChangeVerifier.java
    │   │   ├── PublishCoordinator.java
    │   │   └── action_groups/
    │   ├── evaluator/
    │   │   ├── RsiTeamEvaluator.java
    │   │   ├── CaseRunner.java
    │   │   └── JudgerRegistry.java
    │   ├── evaluation_result_analyzer/
    │   │   └── EvaluationResultAnalyzer.java
    │   └── data_loader/
    │       └── RsiDataLoader.java
    ├── artifact_rsi/              # A类（Phase 3 可选）
    │   ├── ArtifactProvider.java
    │   └── program_opt/ / paper_opt/
    └── integration/
        └── RsiRuntimeImpl.java    # SPI 实现
```

---

## 6. 核心接口/类设计

### 6.1 公共 Schema

```java
public enum RsiScenario { HARNESS, ARTIFACT }
public enum RsiStatus { CREATED, QUEUED, RUNNING, COMPLETED, FAILED, PAUSED, TERMINATED }

public record RsiTaskCreateRequest(
    RsiScenario scenario, String artifactType, String name,
    String artifactPath, String optimizationInstruction, String datasetFile,
    Integer searchWidth, Map<String,String> modelRefs, int maxIterations, String webProxy
) {}
```

### 6.2 主循环编排器

```java
public class SingleHarnessIterativeOptimizationOrchestrator {
    public IterativeSingleHarnessResult optimize(IterativeSingleHarnessRequest request) {
        // 1. 加载数据集 → 2. 建立 baseline → 3. 迭代优化循环
        //   3a. 评测结果分析 → 3b. 成员优化器7步流水线
        //   3c. 评测优化后 harness → 3d. 推广策略判定
    }
}
```

### 6.3 推广策略

```java
public class PromotionPolicy {
    public PromotionResult evaluate(double candidateScore, double baselineScore, double threshold) {
        boolean firstImproved = (candidateScore - baselineScore) > threshold + EPSILON;
        boolean maintained = candidateScore >= baselineScore - EPSILON;
        return new PromotionResult(firstImproved, maintained, candidateScore >= baselineScore);
    }
}
```

### 6.4 成员优化器

```java
public class MemberOptimizer {
    public MemberOptimizationArtifact optimize(EvaluationResultAnalysisArtifact analysis, String harnessRefsPath) {
        // 7步流水线：RoleAttributor → MechanismAttributor → MemberSelector
        // → ActionPlanner → ActionExecutor → HarnessChangeVerifier → PublishCoordinator
    }
}
```

### 6.5 动作规划/执行接口

```java
public interface ActionPlanner {
    MemberOptimizationPlan plan(MemberSelectionReport memberReport) throws ActionPlanRejectedException;
}

public interface ActionExecutor {
    void execute(MemberOptimizationPlan plan, String harnessRefsPath);
}
```

### 6.6 Harness 包引用

```java
public record HarnessRef(String role, String path) {}
public record HarnessPackage(String role, Path root, Map<String,String> fileHashes) {
    public static HarnessPackage load(HarnessRef ref) { /* 加载并计算文件哈希 */ }
    public String fingerprint() { /* SHA256 of all file hashes */ }
}
```

---

## 7. 与现有架构的集成方案

| 现有模块 | 集成方式 | 改动 |
|---------|---------|------|
| `harness/harness_config/HarnessConfig` | RSI 读写 HarnessConfig 作为优化目标 | 只读，无改动 |
| `harness/prompts/sections/*` | RSI ActionExecutor 编辑 prompt sections | 通过现有 section 接口，无改动 |
| `harness/rails/*` | RSI ActionExecutor 增删 rails | 通过 DeepAgent rail 注册接口，无改动 |
| `harness/tools/skills/*` | RSI ActionExecutor 编辑 skills | 通过现有 skill 接口，无改动 |
| `harness/deep_agent/DeepAgent` | RSI 评测器和 ActionPlanner 使用 DeepAgent | 通过现有 API 调用，无改动 |
| `agentevolving/optimizer/BaseOptimizer` | RSI MemberOptimizer 可委托或继承 | 可选，无改动 |
| `agentevolving/evaluator/BaseEvaluator` | RSI 评测器独立实现，不复用 | 无改动 |
| `auto_harness/AutoHarnessOrchestrator` | RSI 有自己的 orchestrator | 无改动 |

**兼容性评估：改造对现有功能零影响。** RSI 模块完全新增，不修改任何现有类。

---

## 8. 实现优先级建议

### Phase 1（MVP，~6周）

| 序号 | 模块 | 依赖 | 工作量 |
|------|------|------|--------|
| P1-1 | `rsi/schema/` 公共 Schema | 无 | 2天 |
| P1-2 | `rsi/harness_rsi/HarnessRsiSchema.java` | P1-1 | 2天 |
| P1-3 | `rsi/harness_rsi/config/` | P1-1 | 3天 |
| P1-4 | `rsi/harness_rsi/data_loader/` | P1-2 | 3天 |
| P1-5 | `rsi/harness_rsi/evaluator/` | P1-3,P1-4 | 5天 |
| P1-6 | `rsi/harness_rsi/single_harness/PromotionPolicy.java` | P1-2 | 3天 |
| P1-7 | `rsi/harness_rsi/single_harness/Orchestrator.java` | P1-5,P1-6 | 5天 |
| P1-8 | `member_optimizer/ActionPlanner + ActionExecutor` | P1-2 | 7天 |
| P1-9 | `member_optimizer/MemberOptimizer.java` | P1-8 | 5天 |

### Phase 2（完整功能，+8周）

| 序号 | 模块 | 工作量 |
|------|------|--------|
| P2-1 | RoleAttributor + MechanismAttributor | 10天 |
| P2-2 | MemberSelector | 3天 |
| P2-3 | HarnessChangeVerifier + PublishCoordinator | 8天 |
| P2-4 | action_groups 完整注册 | 5天 |
| P2-5 | EvaluationResultAnalyzer | 7天 |
| P2-6 | improver_evolution | 5天 |
| P2-7 | 完善 7 步流水线整合 | 5天 |

### Phase 3（可选，Artifact RSI）

| 模块 | 工作量 |
|------|--------|
| artifact_rsi/ArtifactProvider | 3天 |
| program_opt (MCTS) | 15天 |
| paper_opt (auto_research) | 20天 |

---

## 9. 关键设计决策

1. **RSI 评测器不复用现有评测器**：Java 的 `agentevolving/evaluator/` 和 `dev_tools/tune/evaluator/` 面向 RL 训练和调参，与 RSI 评测模型不同。新建独立 RsiTeamEvaluator 更清晰。
2. **ActionPlanner 复用 DeepAgent**：Java 版已有完整 DeepAgent 实现，可直接复用，这是最大复用点。
3. **auto_harness 不复用现有**：Python RSI 的 `harness_rsi/auto_harness/` 是 RSI 专用版本，与原版有差异。建议 RSI 新建自己的 orchestrator。
4. **artifact_rsi 延后实现**：paper_opt 有 60+ 文件，program_opt 有 30+ 文件，与 harness_rsi 相对独立。
5. **SPI 插件化**：通过 ServiceLoader 按需加载，与 retrieval/memory 一致。
