# Python agent-core RSI 模块独立性与依赖关系分析报告

> 分析对象：`D:/jiuwen/main/agent-core/openjiuwen/rsi/`
> 分析日期：2026-11-17
> 分析人：架构师 高见远

---

## 1. 模块边界与对外接口

### 1.1 模块位置

RSI 模块位于 `openjiuwen/rsi/`，是 `openjiuwen` 顶层包下的一个子包，与 `core`、`harness`、`auto_harness`（兼容层）、`agent_evolving`、`agent_teams` 等平级。

### 1.2 独立 `__init__.py` 导出

`openjiuwen/rsi/__init__.py` 有明确的 `__all__` 导出列表（共 44 个符号），分为以下几类：

| 类别 | 导出符号 | 来源子模块 |
|------|---------|-----------|
| Artifact Provider | `ArtifactProvider`, `PaperArtifactProvider`, `ProgramArtifactProvider`, `build_request`, `validate_artifact_task_request` | `rsi/artifact_rsi/` |
| AutoHarness | `AutoHarnessConfig`, `AutoHarnessOrchestrator`, `create_auto_harness_orchestrator`, `TaskContext`, `TaskRuntime`, `build_git_auth_env`, `EXTENDED_EVOLVE_PIPELINE`, `META_EVOLVE_PIPELINE`, `ExtensionTaskPipeline`, `ExtendActivateStage`, `ExtensionDesign`, `OptimizationTask`, `RuntimeExtensionArtifact`, `StageResult`, `load_auto_harness_config` | `rsi/harness_rsi/auto_harness/` |
| Harness 配置 | `AutoCoordinatingHarnessConfig`, `DataLoaderConfig`, `EvaluationResultAnalyzerConfig`, `EvaluatorConfig`, `MemberOptimizerConfig`, `ModelConfigs`, `OrchestratorSchedulingConfig` | `rsi/harness_rsi/config/` |
| 核心组件 | `DataLoader`, `EvaluationResultAnalyzer`, `EvaluationResultAnalysisStrategy`, `TeamEvaluator`, `MemberOptimizer`, `SingleHarnessIterativeOptimizationOrchestrator`, `IterativeSingleHarnessRequest`, `IterativeSingleHarnessResult`, `load_cases` | 各子模块 |
| Schema 数据类 | `ActionDefinition`, `CaseMapping`, `DatasetArtifact`, `EvaluationCaseTraceRef`, `EvaluationResultAnalysisArtifact`, `EvaluationResultAnalysisInvocation`, `TeamIssue` | `rsi/harness_rsi/schema.py` |

### 1.3 内部结构

```
openjiuwen/rsi/
├── __init__.py          # 顶层导出（44 个符号）
├── schema.py            # 公共数据契约（17 个 dataclass）
├── events.py            # 公共事件契约
├── usage.py             # 模型用量观察器
├── artifact_rsi/        # A 类能力：artifact 优化
│   ├── __init__.py
│   ├── provider.py      # ArtifactProvider Protocol
│   ├── request.py       # ArtifactEngineRequest, validate_artifact_task_request
│   ├── program_opt/     # 程序 artifact 优化（PUCT 搜索引擎，~25 个文件）
│   └── paper_opt/       # 论文 artifact 优化（auto_research pipeline，~60+ 个文件）
└── harness_rsi/         # C 类主链路：Harness 自我优化
    ├── __init__.py      # 仅含 docstring，无导出
    ├── schema.py        # Harness 专用数据契约
    ├── config/          # 配置定义与加载
    ├── data_loader/     # 评测数据集加载
    ├── evaluator/       # 评测器（CaseRunner, TeamEvaluator, Judger 体系）
    ├── evaluation_result_analyzer/  # 评测结果分析
    ├── member_optimizer/  # 成员优化器（action planning, execution, verification）
    ├── single_harness/  # 单 Harness 迭代优化编排
    ├── improver_evolution/  # 改进器进化策略
    └── auto_harness/    # 自动化 Harness 编排器（stages, pipelines, rails, agents, infra）
```

---

## 2. 依赖矩阵

### 2.1 RSI → agent-core 其他模块（RSI 向外依赖）

| 被依赖模块 | 依赖类型 | 引用文件数 | 关键引用 |
|-----------|---------|-----------|---------|
| `openjiuwen.core.foundation.llm` | 硬依赖 | ~8 | usage.py, artifact_rsi/request.py, harness_rsi 多个模块 |
| `openjiuwen.core.runner.runner` | 硬依赖 | ~4 | usage.py, harness_rsi/evaluator, auto_harness/rails |
| `openjiuwen.core.runner.callback.events` | 硬依赖 | 1 | usage.py |
| `openjiuwen.core.common.logging` | 硬依赖 | ~10 | 多个 stages、analyzer、config 模块 |
| `openjiuwen.core.single_agent.rail.base` | 硬依赖 | ~6 | 多个 rails 模块 |
| `openjiuwen.core.single_agent.schema.agent_card` | 硬依赖 | ~8 | evaluator, member_optimizer, auto_harness/agents |
| `openjiuwen.core.session.agent` | 硬依赖 | ~5 | member_optimizer, auto_harness/stages |
| `openjiuwen.core.session.stream.base` | 硬依赖 | ~6 | auto_harness stages, pipelines |
| `openjiuwen.core.sys_operation` | 硬依赖 | ~5 | evaluator, auto_harness/rails, member_optimizer |
| `openjiuwen.core.foundation.tool` | 硬依赖 | ~5 | auto_harness/agents, evaluator/judger, paper_opt |
| `openjiuwen.harness` (factory, deep_agent, create_deep_agent) | 硬依赖 | ~12 | evaluator/case_backend, member_optimizer, auto_harness/stages, paper_opt |
| `openjiuwen.harness.rails.base` | 硬依赖 | ~10 | auto_harness/rails/*, paper_opt/extensions/rails/*, evaluator |
| `openjiuwen.harness.tools.*` | 硬依赖 | ~8 | evaluator/runtime_adapters, auto_harness/agents, paper_opt |
| `openjiuwen.harness.prompts.*` | 硬依赖 | ~5 | evaluator, auto_harness/rails, paper_opt/extensions |
| `openjiuwen.harness.resources` | 硬依赖 | ~4 | evaluation_result_analyzer, member_optimizer/verification, single_harness/iterative |
| `openjiuwen.harness.security.permission_engine` | 硬依赖 | 1 | evaluator/harness_input_rail |

**依赖模式总结**：绝大部分是硬依赖（top-level `from X import Y`），少量延迟导入（函数内 import）。`harness_rsi` 对 `openjiuwen.core` 和 `openjiuwen.harness` 的依赖**非常深广**，几乎每个核心文件都引用了 core 或 harness 的基础类型。`artifact_rsi` 对外依赖相对较少。

### 2.2 agent-core 其他模块 → RSI（外部向 RSI 依赖）

| 依赖方模块 | 引用方式 | 引用内容 |
|-----------|---------|---------|
| `openjiuwen/auto_harness/__init__.py` | 硬依赖（top-level） | 从 `openjiuwen.rsi.harness_rsi.auto_harness` 转发导出全部 AutoHarness 接口 — 兼容层 |
| `openjiuwen/harness/cli/cli.py` | 延迟导入 | `rsi.harness_rsi.auto_harness` 的 experience_store, orchestrator, pipelines, schema, stages |
| `openjiuwen/harness/cli/ui/repl.py` | 延迟导入 | 同上 |

**关键发现**：
- `openjiuwen/auto_harness/` 已是纯兼容转发层，所有实际代码已迁移到 RSI 内部。
- 只有 CLI 层通过延迟导入使用 RSI 的 auto_harness 编排能力。
- **`openjiuwen.core` 和 `openjiuwen.harness` 模块本身不依赖 RSI** — 依赖方向是单向的。

---

## 3. RSI 内部子模块依赖关系

### 3.1 三大子模块之间的依赖方向

- `artifact_rsi` 和 `harness_rsi` 之间**没有直接交叉依赖**。
- 两者都依赖顶层的 `rsi/schema.py`、`rsi/events.py`、`rsi/usage.py` 作为公共契约。
- `rsi/schema.py` 完全自包含（只依赖标准库）。
- `rsi/events.py` 依赖 `rsi/schema.py`。
- `rsi/usage.py` 依赖 `rsi/events.py` + `rsi/schema.py` + **`openjiuwen.core`**。

### 3.2 harness_rsi 内部依赖图

```
harness_rsi/
├── schema.py ←── config/, data_loader/, member_optimizer/, single_harness/, evaluator/
├── config/ ←── single_harness/iterative, member_optimizer/optimizer
├── data_loader/ ←── single_harness/iterative
├── evaluator/ ←── single_harness/iterative, single_harness/promotion_policy
│   └── judger/ ←── single_harness/source_evidence, single_harness/iterative
├── evaluation_result_analyzer/ ←── single_harness/iterative, member_optimizer/optimizer
├── member_optimizer/ ←── single_harness/iterative, single_harness/behavior_check
│   ├── optimizer.py ←── (汇聚 action_planner, action_executor, verification, worktree_coordinator)
│   └── agents/factory.py ←── member_optimizer 内多模块
├── improver_evolution/ ←── single_harness/iterative, single_harness/candidate_feedback
├── single_harness/ ←── (核心编排层，汇聚所有上述模块)
└── auto_harness/ ←── (独立编排器，有自己的 stages/pipelines/rails/agents/infra 体系)
```

### 3.3 artifact_rsi 内部依赖图

```
artifact_rsi/
├── provider.py (ArtifactProvider Protocol) ←── program_opt/provider.py, paper_opt/provider.py
├── request.py ←── provider.py
├── program_opt/
│   ├── provider.py (ProgramArtifactProvider)
│   ├── puct_provider.py (PUCT 实现) ←── program_opt/__init__
│   └── state.py ←── puct_provider.py (自包含 PUCT 搜索框架)
└── paper_opt/
    ├── provider.py (PaperArtifactProvider)
    └── auto_research/ ←── paper_opt/provider.py (pipeline + modules + extensions + tree_provider)
```

---

## 4. 关键耦合点列表

### 10 个最深层耦合点（阻断独立抽取的核心障碍）

| 编号 | 耦合点 | 耦合类型 | 影响范围 |
|------|--------|---------|---------|
| C1 | `harness_rsi/evaluator/case_backend.py` → `openjiuwen.harness.factory.create_deep_agent` | 硬依赖 | evaluator 全链路 |
| C2 | `harness_rsi/evaluator/runtime_adapters.py` → `openjiuwen.harness.tools.*` | 硬依赖 | evaluator 全链路 |
| C3 | `harness_rsi/evaluator/runtime_adapters.py` → `openjiuwen.harness.rails.*` | 硬依赖 | evaluator 全链路 |
| C4 | `harness_rsi/member_optimizer/agents/factory.py` → `openjiuwen.harness.factory.create_deep_agent` | 硬依赖 | member_optimizer 全链路 |
| C5 | `harness_rsi/auto_harness/agents/factory.py` → `openjiuwen.harness.deep_agent.DeepAgent` | 硬依赖 | auto_harness 全链路 |
| C6 | `harness_rsi/evaluation_result_analyzer/agent_runtime.py` → `openjiuwen.harness.create_deep_agent` | 硬依赖 | 分析器 |
| C7 | `rsi/usage.py` → `openjiuwen.core.runner.runner.Runner` | 硬依赖 | 公共层 |
| C8 | `artifact_rsi/request.py` → `openjiuwen.core.foundation.llm.Model` | 硬依赖 | artifact_rsi 公共层 |
| C9 | `artifact_rsi/paper_opt/auto_research/modules/*/agent.py` → `openjiuwen.harness.create_deep_agent` | 延迟导入 | paper_opt 全链路 |
| C10 | `harness_rsi/auto_harness/stages/verify.py` → `openjiuwen.harness.deep_agent.DeepAgent` | 延迟导入 | auto_harness verify stage |

### 耦合层次分析

```
层级1 (可独立): schema.py, events.py ← 纯数据契约
层级2 (轻微耦合): artifact_rsi/provider.py ← 仅引用 Model 类型注解
层级3 (中等耦合): usage.py ← 引用 Runner 回调框架; program_opt/ ← 引用 sys_operation
层级4 (深度耦合): paper_opt/auto_research/ ← 创建 deep_agent, 使用 harness tools/rails
                 harness_rsi/evaluator/ ← 组装完整 agent（tools + rails + prompts）
                 harness_rsi/member_optimizer/ ← 创建修改后的 agent
                 harness_rsi/auto_harness/ ← 编排完整 agent 生命周期
层级5 (无法独立): harness_rsi 整体 ← 语义级依赖 core + harness 的全部核心抽象
```

---

## 5. 独立抽取可行性评估

| 子模块 | 独立抽取可行性 | 需剥离的依赖 | 评估说明 |
|--------|-------------|-------------|---------|
| `rsi/schema.py` | ✅ 可立即独立 | 无 | 完全自包含的数据契约 |
| `rsi/events.py` | ✅ 可立即独立 | 仅依赖 `rsi/schema.py` | 纯数据契约 |
| `rsi/artifact_rsi/` (接口层) | ✅ 容易独立 | `openjiuwen.core.foundation.llm.Model` | Protocol 定义层依赖极少 |
| `rsi/artifact_rsi/program_opt/` | ⚠️ 中等难度 | sys_operation, foundation.llm | PUCT 搜索引擎大部分自包含 |
| `rsi/artifact_rsi/paper_opt/` | ❌ 困难 | 大量 harness.* + core.* | auto_research pipeline 深度集成 harness |
| `rsi/harness_rsi/` | ❌ 非常困难 | 几乎全部 core.* + harness.* | 构建在 core+harness 之上的优化元框架 |
| `rsi/usage.py` | ⚠️ 中等 | core.foundation.llm, core.runner | 用量观察依赖 Runner 回调框架 |

### 整体评估

**RSI 不能作为一个整体被独立抽取为单独的 pip 包**，原因：

1. **harness_rsi 是 agent-core 的"元层"**：它不是被 core/harness 调用的下游模块，而是调用 core/harness 来构建和优化 agent 的上层框架。本质是"用 agent-core 的能力来优化 agent-core 自身"。
2. **harness_rsi 对 harness 的依赖是语义级的**：创建 DeepAgent、注册 Rails、使用 Tools、构建 Prompts、管理 Sessions — 不可替换。
3. **唯一可独立的部分是公共契约层**（`schema.py` + `events.py`），以及 artifact_rsi 的 Protocol 接口定义层。

---

## 6. 对 Java 版改造的关键启示

1. **RSI 不是可选模块**：它是 agent-core 的自我优化元层。Java 版如果要实现等价能力，需要先建立 core + harness 基础层，再在其上构建 RSI。
2. **可分离的接口契约**：`RsiTaskCreateRequest`、`EngineState`、`EngineReport`、`EngineEvent` 等数据契约可作为独立 API contract 先行定义。
3. **Provider 协议模式**：`ArtifactProvider` Protocol 定义了清晰的接口边界，Java 版可直接用 Interface 实现。
4. **harness_rsi 的架构模式**："评估→分析→优化→验证"的迭代闭环可跨语言复用，但实现需绑定到具体 agent 框架。
5. **auto_harness 是独立的编排层**：有自己的 stages/pipelines/rails/agents/infra 体系，Java 版可参考 stage-pipeline 模式。
