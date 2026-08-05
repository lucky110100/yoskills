# 端到端自动改码与 CI 修复

> 交叉引用: [01-项目概述](../../01-project-overview.md) | [02-整体架构](../../02-overall-architecture.md) | [04-harness模块](../../04-harness-module.md) | [06-agent_evolving与dev_tools模块](../../06-agent-evolving-and-dev-tools-module.md) | [07-extensions与rsi模块](../../07-extensions-and-rsi-module.md)

## 一、能力概述

agent-core 的端到端自动改码能力由 `rsi/auto_harness` 子模块唯一承载,这是仓库内唯一的"端到端 Agent Team 优化"框架。需要先做一个命名澄清:在 [__init__.py](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/__init__.py#L3) 的模块声明中,其实际含义为 "Auto-coordinating harness for end-to-end Agent Team optimization",并非字面的 Research/Subscribe/Improve 三段式;若按语义阶段映射,其中的 Improve 段最贴近"自动实现(implement)阶段"。

该框架以 **会话(Session)** 为单位编排一整条改码流水线:从需求评估(assess)、方案规划(plan)、代码实现(implement)、局部验证(verify)、提交(commit)、发布 PR(publish_pr),到经验沉淀(learnings),全部由 Agent 自主驱动。它不仅"改代码",还在改码失败时进入两阶段 CI 修复循环,在 CI 不通过或评审被拒时持续让 Agent 修复直至收敛;失败时通过回滚 Rail 撤销工作区改动,成功时把可复用经验沉淀到经验库。整个过程中,工作区始终隔离在独立 worktree 中,避免污染主干分支。

与 `harness/subagents/code_agent.py` 的交互式编码代理不同,auto_harness 强调"无人值守":人会话级别只提供任务描述与目标文件清单,后续从规划到发 PR 全程不再需要人工确认。这使得它适合批量化处理 Issue 修复、依赖升级、批量重构等场景。

核心价值在于:把"读懂需求→改代码→跑 CI→修复→发 PR"这条传统上需要人工反复介入的链路,封装成一个可观测、可回滚、可复用的自动化会话。

值得强调的是,auto_harness 并非把所有问题都塞给一个 Agent,而是采用"Agent Team"协作:不同阶段可由不同子代理承担(assess 由评估代理、plan 由规划代理、implement 由改码代理、verify 由评审代理),orchestrator 负责在阶段间传递产物(artifacts)与上下文。每个 stage 通过 produces/consumes 声明自己产出和消费的产物类型(如 implement 产出 code_change、verify 消费 code_change),orchestrator 据此按拓扑序编排,保证阶段间的数据依赖被满足。这种"团队分工 + 产物契约"的设计,让复杂改码任务被分解为可独立验证的子环节,而非依赖单个 Agent 的全程记忆。

## 二、关键类与函数

| 类/函数 | 文件位置 | 说明 |
|---------|---------|------|
| AutoHarnessOrchestrator | [orchestrator.py](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/auto_harness/orchestrator.py#L106) | 会话控制器与顶层流水线分发器,持有 Git/CIGate/Worktree/FixLoop/Experience/Budget 等组件 |
| _stream_session_pipeline | [orchestrator.py](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/auto_harness/orchestrator.py#L291) | 选定 pipeline 并依次跑各 stage,产出 harness_session_finished |
| ImplementStage | [implement.py](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/auto_harness/stages/implement.py#L291) | 所有 implement 槽位 stage 的抽象基类,声明 produces=\["code_change"\] |
| MetaImplementStage | [implement.py](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/auto_harness/stages/implement.py#L308) | 执行当前任务的代码修改,通过 git status/diff 提取 edited_files |
| ExtendImplementStage | [implement.py](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/auto_harness/stages/implement.py#L646) | 在 worktree 生成运行时扩展代码(rail/tool/skill + harness_config.yaml) |
| FixLoopController | [fix_loop.py](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/auto_harness/infra/fix_loop.py#L25) | 两阶段 CI 修复循环:Phase1 跑 CI 让 agent 修复,Phase2 评审不通过继续修复 |
| CIGateRunner | [ci_gate_runner.py](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/auto_harness/infra/ci_gate_runner.py) | CI 门禁执行器,负责运行测试/lint 并解析通过状态与错误 |
| WorktreeManager | [orchestrator.py](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/auto_harness/orchestrator.py#L148) | 管理隔离工作区,保证改码不污染主干 |
| GitOperations | [orchestrator.py](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/auto_harness/orchestrator.py#L149) | 分支创建/diff 提取/status 检测/推送等 git 操作封装 |
| RevertOnFailureRail | [revert_on_failure_rail.py](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/auto_harness/rails/revert_on_failure_rail.py) | 失败回滚 Rail,在阶段失败时撤销工作区改动 |
| ExperienceRail | [experience_rail.py](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/auto_harness/rails/experience_rail.py) | 经验沉淀 Rail,把可复用知识写入经验库 |
| implement SKILL | [SKILL.md](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/auto_harness/skills/implement/SKILL.md#L1) | 实现阶段主操作手册,工具集 read_file/write_file/edit_file/glob/grep/bash |
| assess 阶段 | stages/assess.py | 任务评估:解析需求、检索经验、判定可行性 |
| plan 阶段 | stages/plan.py | 方案规划:产出实现策略与目标文件清单 |
| verify 阶段 | stages/verify.py | 局部验证:运行 CI 门禁并触发修复循环 |
| commit/publish_pr 阶段 | stages/commit.py | 提交到任务分支并推送创建 PR |

stages/ 目录下还包含 assess/plan/verify/commit/publish_pr/learnings/select_pipeline/activate/merge 等阶段实现,共同构成完整阶段全集。各阶段以 TaskStage 为基类,通过 produces/consumes 声明产物与依赖,由 orchestrator 按拓扑序编排。

## 三、实现机制

### 3.1 流水线编排

[AutoHarnessOrchestrator](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/auto_harness/orchestrator.py#L106) 在构造时一次性装配所有协作组件:GitOperations 处理分支与 diff、CIGateRunner 执行门禁、WorktreeManager 管理隔离工作区、FixLoopController 驱动修复循环、ExperienceStore 沉淀经验、SessionBudgetController 控制会话预算。会话入口 [_stream_session_pipeline](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/auto_harness/orchestrator.py#L291) 先重置状态、启动预算,再依据 pipeline 偏好选定阶段序列,逐 stage 流式产出结果,最终汇总为 harness_session_finished。阶段全集覆盖 assess/plan/implement/verify/commit/publish_pr/learnings/select_pipeline/activate/merge,可通过 pipeline_preference 灵活裁剪。

### 3.2 强制改码校验

[MetaImplementStage](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/auto_harness/stages/implement.py#L308) 的提示词([implement.py:L64-L67](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/auto_harness/stages/implement.py#L64))明确约束:"本阶段只允许完成代码修改与局部验证……必须直接动手修改代码",禁止回问、禁止越界编辑、禁止提前 commit/push。阶段结束时通过 `git status_porcelain()` 与 `git diff_name_only("HEAD")`([implement.py:L396-L402](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/auto_harness/stages/implement.py#L396))提取改动文件,产出 CodeChangeArtifact(edited_files)。

若未检测到任何改动且分支无相对 base 的新提交,则在 [implement.py:L452-L456](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/auto_harness/stages/implement.py#L452) 抛出 "Implement phase finished without any code edits" 并将任务标记为 FAILED——这是"必须改码"的硬约束,防止 Agent 仅做分析不动手。

[ExtendImplementStage](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/auto_harness/stages/implement.py#L646) 是 implement 槽位的另一实现,职责不是改业务代码,而是在 worktree 内物化运行时扩展(rail/tool/skill 资源 + harness_config.yaml 清单),produces=\["extension_build"\],用于让 Agent 自主生成新的编码能力,与插件热加载形成闭环。

这两种 implement 实现可通过 pipeline 选择切换:常规改码任务走 MetaImplementStage,需要扩展 Agent 能力的任务走 ExtendImplementStage,体现"同一阶段槽位多实现"的灵活性。

### 3.3 两阶段 CI 修复循环

[FixLoopController](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/auto_harness/infra/fix_loop.py#L25) 是自动改码收敛的核心。它采用"先编译、后评审"的双阶段策略:

- **Phase 1 直接修复**([fix_loop.py:L65-L96](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/auto_harness/infra/fix_loop.py#L65)):`ci_runner()` 跑 CI→解析 errors→交给 `agent_fixer(errors)` 让 Agent 修复→重试,默认最多 10 轮。CI 通过即提前返回。
- **Phase 2 评审修复**([fix_loop.py:L98-L134](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/auto_harness/infra/fix_loop.py#L98)):当 evaluator 审查质量不通过时,以 "evaluator rejected" 为输入继续让 `agent_fixer` 修复,默认最多 9 轮。

每轮都带 `asyncio.wait_for` 超时保护,单次默认 600 秒,避免卡死。Phase1 解决"能不能编译/测试通过"的硬约束,Phase2 解决"改得好不好"的质量约束,两者叠加保证产物既正确又可接受。

两阶段分离的意义在于:Phase1 的失败信号是客观的(CI 报错文本),Agent 据此定位语法/测试问题;Phase2 的失败信号是主观的(evaluator 的评审意见),Agent 据此改进设计质量。把这两类性质不同的反馈分到不同阶段,避免 Agent 在"修编译错"和"改设计"之间反复横跳,提高收敛效率。

### 3.4 事后机制(非字面 Subscribe)

框架的"事后"能力并非字面意义的订阅,而是由三条机制协同:

1. **CI 门禁**:[ci_gate_runner.py](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/auto_harness/infra/ci_gate_runner.py) 在 verify 阶段执行测试/lint,产出 passed/errors。
2. **失败回滚**:[revert_on_failure_rail.py](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/auto_harness/rails/revert_on_failure_rail.py) 在阶段失败时撤销工作区改动,保证 worktree 干净。
3. **经验沉淀**:[experience_rail.py](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/auto_harness/rails/experience_rail.py) 把本轮任务的可复用知识写入 ExperienceStore,供后续会话的 assess/plan 阶段检索复用。

### 3.5 worktree 隔离与预算控制

每个改码任务运行在独立 worktree 中,由 [WorktreeManager](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/auto_harness/orchestrator.py#L148) 创建并管理。这意味着多个任务可并行、且任一任务失败不会影响主干或其他任务的工作区。[GitOperations](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/auto_harness/orchestrator.py#L149) 在 worktree 内完成分支创建、`status_porcelain`/`diff_name_only` 检测、提交与推送,全程不触碰主工作区。[SessionBudgetController](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/auto_harness/orchestrator.py#L106) 在会话启动时 `budget.start()`,对总时长、模型调用时长、任务超时进行约束,超预算时会话优雅终止,避免无限消耗算力。

### 3.6 commit 与 publish_pr 阶段

implement 阶段产出的工作区 diff 不会立即提交——提示词([implement.py:L70-L75](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/auto_harness/stages/implement.py#L70))明确禁止 implement 阶段执行 `git add`/`git commit`/`git push`,这些动作只能在后续独立的 commit/publish_pr 阶段进行。这样设计是为了让 verify 阶段能通过 `diff_name_only("HEAD")` 检测到本轮改动;若 implement 提前提交,后续阶段会检测不到改动并误判失败。commit 阶段把工作区 diff 提交到任务分支,publish_pr 阶段经 [GitOperations](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/auto_harness/orchestrator.py#L149) 推送到远端 fork 并创建 PR,实现"改码→提交→发 PR"的自动闭环。

### 3.7 经验检索与跨会话复用

[ExperienceRail](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/auto_harness/rails/experience_rail.py) 在会话结束时把可复用知识(如某类竞态的修复模式、某模块的依赖结构)写入 ExperienceStore。下一个会话的 assess/plan 阶段会先检索经验库,把相关经验注入 implement 提示词的"相关经验"段([implement.py:L62](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/auto_harness/stages/implement.py#L62))。这让 Agent 在面对相似任务时不必从零摸索,而是复用过往成功路径,形成"越用越聪明"的正反馈。

经验沉淀的质量直接影响后续会话的规划准确度。因此 ExperienceRail 会对经验做去重与质量过滤,只沉淀"本轮被验证有效"的模式,避免错误经验污染经验库导致后续会话走偏。

## 四、调用示例

```python
import asyncio
from openjiuwen.rsi.auto_harness.config import AutoHarnessConfig
from openjiuwen.rsi.auto_harness.orchestrator import AutoHarnessOrchestrator
from openjiuwen.rsi.auto_harness.types import OptimizationTask

async def run_coding_session() -> None:
    config = AutoHarnessConfig(
        workspace="/repo/main",
        local_repo=".",
        repo_url="https://gitcode.com/owner/repo.git",
        git_base_branch="main",
        pipeline_preference="assess,plan,implement,verify,commit,publish_pr",
        fix_phase1_max_retries=10,
        fix_phase2_max_retries=9,
    )
    orchestrator = AutoHarnessOrchestrator(config)

    tasks = [
        OptimizationTask(
            topic="修复登录接口在并发场景下的竞态",
            description="login() 共享态未加锁,需引入 asyncio.Lock",
            files=["src/auth/login.py"],
        )
    ]

    async for chunk in orchestrator.run(tasks=tasks):
        # 流式接收每个阶段的产出:
        #   assess  -> 任务评估与经验检索
        #   plan    -> 方案规划
        #   implement -> 代码修改(MetaImplementStage)
        #   verify  -> CI 门禁 + 两阶段修复循环
        #   commit  -> 提交到任务分支
        #   publish_pr -> 推送并创建 PR
        print(chunk)

asyncio.run(run_coding_session())
```

## 五、业界对比

| 维度 | agent-core | Cursor | Claude Code | GitHub Copilot |
|------|-----------|--------|-------------|----------------|
| 端到端改码会话 | ✅ 全阶段编排(assess→publish_pr) | ❌ 仅 IDE 内辅助 | ✅ CLI 任务驱动 | ❌ 仅补全/Chat |
| CI 失败自动修复循环 | ✅ 两阶段(编译+评审)多轮收敛 | ❌ 手动 | ✅ 单轮重试 | ❌ 无 |
| 强制改码校验 | ✅ 无改动判 FAILED | ❌ 无 | ❌ 无 | ❌ 无 |
| worktree 隔离 | ✅ WorktreeManager 独立工作区 | ❌ 工作区原地 | ❌ 工作区原地 | ❌ 工作区原地 |
| 失败回滚 | ✅ RevertOnFailureRail 自动撤销 | ❌ 手动 git stash | ❌ 手动 | ❌ 无 |
| 经验沉淀 | ✅ ExperienceStore 跨会话复用 | ❌ 无 | ❌ 无 | ❌ 无 |
| 阶段编排 | ✅ 可插拔 Stage + pipeline 偏好 | ❌ 固定流程 | ❌ 固定流程 | ❌ 无编排 |

> 对比说明:Cursor 与 Copilot 定位为"人主导、AI 辅助",改码与发 PR 的决策权始终在人;Claude Code 支持 CLI 任务驱动与单轮重试,但缺少强制改码校验、失败回滚与跨会话经验沉淀;agent-core 的差异在于把"决策权下放给 Agent"的同时,用强制改码、worktree 隔离、回滚与经验沉淀补齐了无人值守所需的安全与收敛保障。

## 六、小结

`rsi/auto_harness` 是 agent-core 区别于普通编码助手的标志性能力:它把"读需求→改码→验证→发 PR"封装为可无人值守的会话,通过强制改码校验确保 Agent 必须动手、通过两阶段 CI 修复循环确保产物可收敛、通过 worktree 隔离与失败回滚保证主干安全、通过经验沉淀实现跨会话学习。配合 [implement SKILL](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/auto_harness/skills/implement/SKILL.md#L1) 的明确操作手册,整条链路在工程上是可观测、可回滚、可复用的。

这条链路与 `harness/subagents/code_agent.py` 的交互式编码代理互为补充:前者面向无人值守的端到端改码,后者面向人机协同的单文件/单任务改码。两者共享同一套工具集(read_file/write_file/edit_file/bash 等)与同一套安全控制(见 [coding-security](coding-security.md)),但编排粒度与人工介入程度不同。

实践上,auto_harness 适合处理"需求明确、可验证"的批量任务(如 Issue 修复、依赖升级、lint 修复、重复重构),不适合处理"需求模糊、需反复对齐"的探索性任务。后者更适合交给交互式 CodeAgent,由人引导 Agent 逐步明确需求。理解 auto_harness 是理解 agent-core 为何被称为"Agent Team 优化框架"而非"代码补全工具"的关键。
