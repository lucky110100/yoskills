# jiuwenswarm RSI 实现归类分析

> **文档性质**：代码事实核查报告（对《RSI-技术洞察报告-v1》第 5 章分类框架的落地校验）
> **分析对象**：`jiuwenswarm`（服务域）+ `agent-core/openjiuwen/rsi`（引擎）
> **代码基线**：`D:/jiuwen/third/jiuwenswarm`、`D:/jiuwen/main/agent-core`
> **编写日期**：2026-11-05
> **证据等级**：所有结论均标注代码文件与行号；数学判定结果为实跑函数所得（见附录 B）

---

## 0. 结论摘要

**jiuwenswarm 的 RSI 属于第 5 章五类中的 C 类——Harness 递归改进；并且是 C 类里 RRSI 那条「固定权重 + 用正则化约束搜索轨迹」的路线，同时吸收了 Recuris/AgentFactory 的「技能固化为可复用资产」思路。**

三条判据：

| 判据 | 本项目的实际位置 | 结论 |
| - | - | - |
| 改什么 | `prompt_sections/`、`tools/`、`rails/`、`skills/`、`runtime.yaml` | harness 外围 → **C 类** |
| 模型是否冻结 | evaluator 的 `model_config_ref` 全程只读，无任何权重更新代码 | 权重不动 → **非 D 类** |
| 循环靠什么收敛 | 冻结 case 集的两阶段晋级门禁 | 测试驱动 → **非 A 类**（A 类靠种群进化搜索） |

**但项目内同时存在 B 类。** `harness_rsi/auto_harness/` 是另一套独立系统，改的是 `jiuwenswarm/`、`openjiuwen/harness/`、`openjiuwen/core/` 的**源码**，走 assess → plan → implement → verify → commit → publish PR 流水线，且已接入 `agent_ws_server.py`（`mode="auto_harness"`），是活的功能而非实验代码。

所以准确表述是：

- **`harness_provider.py` → `single_harness` = C 类**（面向用户的 RSI 优化任务主链路，18 个 `rsi.*` web method 接这条）
- **`auto_harness` = B 类**（自我修改代码库，递归深度更深）

两条线共用 `openjiuwen.rsi` 命名空间，但入口、收敛机制、产物形态完全不同，**不能混为一谈**。

---

## 1. 判定依据详解

### 1.1 为什么是 C 类而非 B 类（单 harness 主链路）

关键证据在 `member_optimizer/action_groups/policy.py`。可编辑面被硬编码为白名单：

```python
ALLOWED_ACTION_GROUPS = frozenset({"prompt", "config", "rail", "skill", "tool"})

GROUP_PATH_PREFIXES = {
    "config": ("runtime.yaml",),
    "prompt": ("identity.md", "soul.md",
               "prompt_sections/sections.yaml", "prompt_sections/files/"),
    "tool":   ("tools/",),
    "rail":   ("rails/",),
    "skill":  ("skills/",),
}
```

文件头注释写得很直白：

> The current auto harness consumes member capabilities as ExpertHarness packages. MemberOptimizer therefore only plans and executes **local file changes within the package surfaces**.

**改动 agent 自身源码的路径在这里是被机械封死的**（路径前缀白名单硬校验，非提示词约束）。这正是 C 类与 B 类的分界线——B 类能改代码，C 类只能改配置与内容资产。

### 1.2 为什么不是 D 类（无权重更新）

全仓检索 `lora | fine-tune | SFT | RLHF | gradient | model_weights` 在 `openjiuwen/rsi` 下**零命中**。evaluator 的模型配置以 `model_config_ref` 形式只读引用，唯一可调的运行参数是 `solver_max_iterations`（迭代次数，不是权重）。

**结论：模型权重全程冻结，D 类的「双循环」在本项目不存在。**

### 1.3 为什么不是 A 类（收敛机制不同）

A 类的本质是**种群进化搜索**（变异 + 适应度筛选 + 种群保留）。本项目单 harness 主链路没有种群、没有变异算子，收敛靠的是**冻结 case 集上的两阶段晋级判定**：

```python
# config/config.py:341-343
policy_version: str = "continuous_two_stage_v2"
min_improvement: float = 0.05              # 目标 case 至少要提升的绝对分
non_target_max_regression: float = 0.05    # 非目标 case 最多能退的分
```

判定逻辑（`promotion_policy.py`）：

1. **门禁 A（目标 batch）**：每个 target case 必须 `score - baseline > threshold + EPSILON`
2. **门禁 B（全量重放）**：三条同时满足才接受——目标 case 全提分、非目标 case 退分不超阈值、全量均分严格提高

**有意思的是，A 类能力在项目里也存在，只是挂在另一个命名空间下**：`openjiuwen/rsi/artifact_rsi/program_opt/` 有完整的进化搜索实现（`puct_engine.py`、`candidates.py`、`tree.py`、`state.py`、`scorecard.py`），走 PUCT 树搜索。所以严格说，这个项目是「C 类主链路 + A 类能力作为 artifact 专用引擎 + B 类 auto_harness 旁路」的复合结构。

---

## 2. 两套系统辨析

| 维度 | `single_harness`（C 类） | `auto_harness`（B 类） |
| - | - | - |
| 改进对象 | ExpertHarness 包内文件 | `jiuwenswarm/`、`openjiuwen/{dev_tools,harness,core}/` 源码 |
| 编辑范围 | 5 类文件路径前缀白名单 | `ALLOWED_SOURCE_EDIT_PREFIXES`（`edit_scope.py:11-20`） |
| 收敛机制 | 两阶段 case 集晋级门禁 | CI 门禁 + 代码评审 + PR 发布 |
| 隔离方式 | 每 action 一个 git worktree | git worktree + `ci_gate_runner` |
| 产物 | 新 harness 包引用（`best_harness_refs_path`） | git commit / PR |
| 流水线 | 迭代式（`iterative.py`）+ 连续式（`continuous.py`） | assess → plan → implement → verify → commit → publish_pr |
| 用户接口 | 18 个 `rsi.*` web method（`server/rsi/rsi_handlers.py`） | `agent_ws_server` 的 `mode="auto_harness"` |
| 递归深度 | 单层（改包，不改改包的系统） | 多层（能改改包的系统本身） |

**注意 `stages/learnings.py` 和 `meta_evolve_pipeline` 的存在**——auto_harness 有把本轮经验写回、指导下轮规划的设计，递归深度介于 DGM 与 HyperAgents 之间，但由于没有权重更新、没有自我复制的评估器，仍归 B 类。

---

## 3. C 类是怎么实现的

主链路是 `SingleHarnessIterativeOptimizationOrchestrator`（`single_harness/iterative.py`，4554 行）。它的收敛度比通用 `MemberOptimizer` 更窄，构造函数里写死：

```python
# iterative.py:184-190
allowed_prompt_surfaces = list(_ALLOWED_PROMPT_SURFACES)   # ["prompt_section"]
max_roles_per_run = 1
max_actions_per_plan = 3
```

即：**单角色、单包、最多 3 个动作、prompt 面只留 `prompt_section`（identity/soul 被关掉）**。

这不是「让 LLM 随便改点提示词」，而是一条窄通道。六环节，每环都有机械校验：

| 环节 | 代码位置 | 做什么 |
| - | - | - |
| ① 冻结输入 | `materializer.py` | 数据集与 harness 包各自复制快照 + sha256，本次运行只读 |
| ② 评测 | `evaluator/` | 真跑 harness，输出 0–1 连续分；binary LLM 评分被 `complete_scores()` 直接拒绝 |
| ③ 归因 | `member_optimizer/role_attributor.py` → `mechanism_attributor.py` | 先判断「是不是这个角色的问题」，再判断失败机制落在哪个 lever（instruction / action / control / configuration） |
| ④ 规划 | `action_planner.py`（1846 行） | 只允许 `prompt/config/rail/skill/tool` × `add/modify/remove/search`，路径前缀硬校验 |
| ⑤ 执行 | `action_executor.py` + `worktree_coordinator.py` | 每 action 独立 worktree，拓扑排序分波次，路径逃逸检查 |
| ⑥ 晋级 | `promotion_policy.py` + `continuous.py` | 两阶段门禁（见 §1.3） |

**设计上值得肯定的点：先归因再动手。** 归因环节把「失败」拆成"角色问题 / 机制问题 / lever 定位"三层，规划器拿到的是带假设的结构化上下文，而不是原始 trace。这比「把 trace 丢给 LLM 让它改 prompt」的收敛效率高得多——也是 RRSI 类系统能 work 的前提。

---

## 4. 与 RRSI 七层正则化的逐条对照

这是本次分析最有价值的部分。报告 5.3 称 RRSI 用七层正则化抑制过拟合，本项目**只实现了约三层**：

| RRSI 机制 | 本项目对应 | 状态 |
| - | - | - |
| ① 退火编辑预算 | `max_actions_per_plan=3`、`max_repair_rounds=3` | ⚠️ 有上限，但**恒定不退火** |
| ② 历史条件提议（已证伪不重提） | `_rejected_capabilities()` + `attempted_issue_signatures` | ✅ 有 |
| ③ 停滞重定向 | `feedback.py` 的 `max_stagnant_attempts` → `stop_reason=no_progress` | ⚠️ **只会停，不会重定向** |
| ④ 批评者预筛（防作弊） | `verification.py` 危险符号黑名单（`eval`/`exec`）+ `_full_engineering()` 验「能力真被调用」 | ⚠️ 有运行时证据校验，**无专门作弊检测器** |
| ⑤ 噪声调整下限 | `EPSILON=1e-9` + 固定 `0.05` 绝对阈值 | ❌ 无评估方差建模 |
| ⑥ 成本规则（token 需被增益支付） | `usage_recorder.py` 只记账，**不参与判定** | ❌ 缺 |
| ⑦ 剪枝 | 仅「能力未被调用则拒绝该候选」 | ❌ 无主动移除低贡献组件 |

### 这些缺口的实际后果

- **缺 ⑤**：`0.05` 是绝对阈值，与评估方差无关。判分器本身抖动若接近 0.05，会持续接受噪声级「改进」，形成看似提升实则回归的 harness。
- **缺 ⑥**：只防「改了没生效」和「改坏了别的 case」，**不防「用更多 token 换来的微弱提升」**。长时间运行下 harness 会单调膨胀——每轮加一条 prompt section 都能压过 0.05 阈值时，包会无限变厚，推理成本线性上升而质量饱和。
- **缺 ⑦**：没有剪枝，膨胀不可逆。配置文件 `promotion.py` 里没有组分贡献追踪，无法识别「这个 skill 已经 10 轮没被调用过」。

**如果要做长程任务，优先补 ⑤ 和 ⑥**——这两项是跑久了最先出问题的地方。⑦ 可以靠定期人工 review 兜底，⑤⑥ 不行。

---

## 5. 完整示例

以下示例的数据集、动作 YAML、prompt section 内容为构造，但**字段结构与代码约束完全一致，晋级判定数字为实跑 `promotion_policy.py` 所得**（见附录 B）。

### 场景

文档处理类任务，H0 基线在 c1 上得 0.40 分——CSV 日期列 `03/04/2026` 被按 `%d/%m/%Y` 解释成 4 月 3 日，导致 3 行解析错误。

### ① 数据集（引擎只读这两类字段）

```json
{
  "dataset_id": "csv-date-normalize",
  "cases": [
    {"case_id": "c1",
     "input": "把 orders.csv 的 order_date 列统一为 YYYY-MM-DD，输出到 out/orders.csv",
     "reference": {"rubric": ["行数与表头不变", "所有日期可解析", "不可解析行原样保留"]}},
    {"case_id": "c2", "input": "...", "reference": {"rubric": ["..."]}},
    {"case_id": "c3", "input": "...", "reference": {"rubric": ["..."]}},
    {"case_id": "c4", "input": "...", "reference": {"rubric": ["..."]}},
    {"case_id": "c5", "input": "...", "reference": {"rubric": ["..."]}}
  ]
}
```

### ② H0 冻结基线

```
{c1: 0.40, c2: 0.85, c3: 0.90, c4: 0.75, c5: 0.60}  → mean = 0.70
```

### ③ 归因

`max_roles_per_run=1`，角色归因直接通过（单角色无歧义）。`mechanism_attributor` 读 trace 发现：agent 把 `03/04/2026` 按日/月格式解析，判定失败机制是**指令缺失**（没有歧义日期的处理规则），`lever = instruction`。

### ④ 规划（1 个动作，`prompt/add`）

```yaml
action_id: a001
action_group: prompt
operation: add
target_path: prompt_sections/files/date-ambiguity.md
declared_write_paths:
  - prompt_sections/files/date-ambiguity.md
  - prompt_sections/sections.yaml
role: csv_processor
depends_on: []
```

路径前缀 `prompt_sections/files/` 在 `GROUP_PATH_PREFIXES` 白名单内 → 校验通过。

### ⑤ 执行（独立 worktree 内，落盘两处）

`prompt_sections/files/date-ambiguity.md`：

```markdown
## 歧义日期消歧

当字段同时可能是 DD/MM/YYYY 与 MM/DD/YYYY 时：
1. 先扫全列，取「>12 的日或月数值」作为消歧证据；只出现一次即确定该列格式。
2. 全列无 >12 的值时，默认 DD/MM/YYYY，并在输出附一行说明该假设。
3. 两种解释都合法且无法判定时，该行原样输出，不猜测。
```

`prompt_sections/sections.yaml` 追加：

```yaml
sections:
  - name: date_ambiguity
    file: prompt_sections/files/date-ambiguity.md
    priority: 60
```

### ⑥ 门禁 A：目标 batch（只跑 c1）

```
c1: 0.40 → 0.70
0.70 - 0.40 = 0.30 > 0.05 + 1e-9  ✓
→ targets_improved() = True
```

写入 `improvement_proof`：`{identity, qualified: true, target_case_ids: ["c1"], baseline_scores_digest: <sha256>}`。

### ⑦ 门禁 B：全量重放（5 个 case 全跑）

```
{c1: 0.70, c2: 0.85, c3: 0.90, c4: 0.72, c5: 0.60}  → mean = 0.754
```

三条判定（实跑输出）：

```json
{
  "accepted": true,
  "reason": "two_stage_improvement_confirmed",
  "score": 0.754,
  "baseline_score": 0.7,
  "full_score_delta": 0.054,
  "target_cases_improved": true,
  "non_target_cases_retained": true,
  "full_average_improved": true,
  "case_score_deltas": {"c1": +0.30, "c2": 0.0, "c3": 0.0, "c4": -0.03, "c5": 0.0}
}
```

- 目标全提分：c1 +0.30 ✓
- 非目标退分：c4 −0.03 ≤ 0.05 ✓
- 全量均分提高：0.754 > 0.70 ✓

**反例对照**（实跑）：把 c4 改成 0.68（退 0.07 > 0.05），`reason` 变为 `non_target_case_regressed`，`accepted: false`。这就是两阶段门禁的实际拦截能力——**防止为提升单个 case 而牺牲其他 case**。

全量评测前后各校验一次 `package_fingerprint()`，任一不一致抛 `EvaluationInfrastructureError`，防止评测期间包被篡改。

### ⑧ 晋升

`best_harness_refs_path` 指向新包；`optimization_journal` 追加一条 `{lever: instruction, delta: +0.30, status: accepted}`；`lever_scoreboard` 更新 instruction 杠杆的成功计数 → 下一 epoch 的规划器能看到"instruction 类改动在此场景有效"。`rsi.harness.rollback` 可一键回退。

---

## 6. 三点取舍

### 6.1 换来「可审计」，代价是「天花板」

每个判定都带 sha256 指纹（数据集、harness 包、profile 各一份），能精确回答"为什么这个改动被接受"，也能一键回退。**代价是权重冻结意味着能力上限 = 基础模型能力边界**——这与报告 5.2 结尾指出 B 类/固定权重路线的局限完全一致。

RRSI 论文声称用 Gemini 3.5 Flash 替换 Claude Opus 4.8 后，同一编码实例从 64.6 提升到 78.7（策略无关性）。本项目理论上同样策略无关，但**没有多模型对照实验数据，不能直接类比**。

### 6.2 `auto_harness` 是另一套东西

见 §2。它能改源码、有 CI 门禁、发 PR，且已接入 `agent_ws_server`。评估本项目 RSI 成熟度时如果把两条线混算，会得出「它既能改包又能改代码，所以是 B 类或 D 类」的错误结论。**分类要看主链路，主链路是 C 类。**

### 6.3 缺少 C 类里的「记忆进化」维度

报告 5.3 提到的 Recuris 走的是「进化记忆而非进化 prompt」路线。本项目有 `optimization_journal` / `lever_scoreboard` 做跨轮经验统计，但那是**给规划器看的聚合统计**，不是可检索、可复用的结构化技能记忆。

如果目标是长程任务（跨 session 累积），这是明显缺口——每轮优化只能看到「instruction 杠杆成功率 70%」这种标量，看不到「上次处理日期歧义用的是哪条规则、当时为什么有效」。

---

## 7. 改进建议（按投入产出排序）

| 优先级 | 动作 | 理由 | 改动范围 |
| - | - | - | - |
| P0 | 补噪声下限：用同一候选重复评测 N 次估方差，阈值取 `max(0.05, k·σ)` | 当前固定 0.05 会持续接受噪声级改进 | `promotion_policy.py` + evaluator 多跑支持 |
| P0 | 补成本规则：把 `usage_recorder` 的 token 增量接入晋级判定，要求 `Δscore / Δtoken` 超下限 | 防 harness 无限膨胀 | `promotion_policy.py` + `usage_recorder.py` 打通 |
| P1 | 停滞重定向：`no_progress` 时切换 lever（如 instruction → tool），而非直接停 | RRSI 第 3 层的完整语义 | `feedback.py` + `action_planner.py` |
| P1 | 补剪枝：统计各组件近 N 轮调用/贡献，低于阈值提议 remove | 让膨胀可逆 | 需新增组分贡献追踪 |
| P2 | 结构化技能记忆：把 journal 从标量统计升级为可检索经验条目 | 支撑长程任务 | 较大改造，需独立设计 |

---

## 附录 A：代码索引

| 主题 | 文件 |
| - | - |
| 主循环编排 | `agent-core/openjiuwen/rsi/harness_rsi/single_harness/iterative.py`（4554 行） |
| 连续式两阶段晋级 | `.../single_harness/continuous.py`（484 行） |
| 晋级判定数学 | `.../single_harness/promotion_policy.py`（138 行） |
| 可编辑面白名单 | `.../member_optimizer/action_groups/policy.py` |
| 动作规划 | `.../member_optimizer/action_planner.py`（1846 行） |
| 角色/机制归因 | `.../member_optimizer/role_attributor.py`、`mechanism_attributor.py` |
| 静态校验（危险符号） | `.../member_optimizer/verification.py` |
| worktree 隔离 | `.../member_optimizer/worktree_coordinator.py` |
| B 类源码编辑范围 | `.../auto_harness/infra/edit_scope.py` |
| B 类流水线 | `.../auto_harness/pipelines/{meta_evolve,extended_evolve}_pipeline/` |
| B 类阶段 | `.../auto_harness/stages/`（assess/plan/implement/verify/commit/publish_pr/learnings） |
| A 类进化搜索 | `.../artifact_rsi/program_opt/`（`puct_engine.py`、`tree.py`、`candidates.py`） |
| 服务域 provider | `jiuwenswarm/jiuwenswarm/agents/harness/common/rsi/harness_provider.py` |
| 服务域 web method | `jiuwenswarm/jiuwenswarm/server/rsi/rsi_handlers.py`（18 个 `rsi.*` 方法） |
| 快照材料化 | `jiuwenswarm/jiuwenswarm/agents/harness/common/rsi/materializer.py` |
| token 记账 | `jiuwenswarm/jiuwenswarm/agents/harness/common/rsi/usage_recorder.py` |
| 参考配置 | `agent-core/openjiuwen/rsi/harness_rsi/config/config.py` |

## 附录 B：验证方法与证据等级

**本次分析中区分三种证据强度：**

1. **代码事实（最强）**——直接读取源文件确认。本文所有"可编辑面""阈值""白名单"结论均属此类，附行号。
2. **实跑验证**——`promotion_policy.py` 的 `mean_score` / `targets_improved` / `full_evaluation_decision` / `digest` 四个纯函数被单独加载执行（打桩 `yaml` 与 `evaluator.errors` 以绕开缺失依赖），§5 的 0.70 / 0.754 / `two_stage_improvement_confirmed` / `non_target_case_regressed` 均为真实输出。
3. **推断（最弱）**——§7 改进建议的收益判断、§6 的「天花板」论断属分析推断，非代码可直接证明的事实。

**未能验证的部分（诚实标注）：**

- 未做端到端实际运行（缺少可用 venv，`pydantic` 缺失）。因此**归因环节的实际效果、LLM 规划的实际质量、整轮优化是否真能产出 0.30 的提升，均未经实验证实**。
- 示例中的数据集、动作 YAML、prompt 内容是构造的，仅保证与代码约束一致，不是真实运行产物。
- 报告 5.3 中 RRSI 的论文数据（arXiv:2609.24972 等）来自原报告转述，本次未独立核实论文原文。
- 未统计代码中各机制的**实际触发频率**（如 `_rejected_capabilities` 在真实运行中被调用过多少次），因此「只实现约三层」是**功能存在性判断**，不是效果强度判断。
