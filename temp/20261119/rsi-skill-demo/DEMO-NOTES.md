# RSI skill 改进 demo 详细说明

> 版本：v1（2026-11-19）
> 位置：`D:\yaodh\main\yoskills\temp\20261119\rsi-skill-demo\`
> 依赖：`com.openjiuwen:agent-core-java:0.1.17` + `com.openjiuwen:core-rsi:0.1.17`（本地 Maven 仓库构件）

---

## 1. 一句话结论

demo 用脚本化评测驱动 core-rsi 的**真实** RSI 闭环（分析 → 规划 → 执行 → 门禁 → 发布），把 math-tutor skill 的两个薄弱提示词文件（`arith.md`、`algebra.md`）从一句话增强为分步解题约定，均分从 **0.5333 提升到 0.80** 并通过两阶段门禁发布。

**改进前后的真实对比不是** `skill_package/` vs `output/published/`（这两处运行后内容相同），**而是**：

| 对比对象 | algebra.md 内容 | 位置 |
|---------|----------------|------|
| 改进前（初始薄弱版） | 仅一句话："解代数方程：把未知数移到等号一边，常数移到另一边，然后求解。" | `output/frozen_harness_refs.yaml/prompt_sections/algebra.md` |
| 改进后（发布版） | 四步分步解题约定（等式性质 1/2 + 回代验证） | `output/published/skill_package/prompt_sections/algebra.md` |

> ⚠️ 常见误解澄清：`skill_package/` 与 `output/published/skill_package/` **看起来相同是正确行为**，不是路径搞错。原因见 §4。

---

## 2. 目录结构总览

```
rsi-skill-demo/
├── run_demo.bat                 # 一键编译+运行（ASCII-only，双击即可复现）
├── pom.xml                      # 可选 Maven 构建（minimal）
├── dataset/
│   └── dataset.json             # 3 个 case：s1 算术 / s2 代数 / s3 逻辑（demo 启动时自动生成）
├── skill_package/               # 【输入包】math-tutor skill —— 运行后已被 RSI 原地更新
│   ├── harness_config.yaml
│   └── prompt_sections/
│       ├── identity.md          # 未被优化（s3 达标，无 issue）
│       ├── arith.md             # ← 已被 RSI 增强
│       ├── algebra.md           # ← 已被 RSI 增强（初始仅一句话）
│       └── logic.md             # 未被优化
├── output/                      # 【RSI 运行产物】每次运行先清空重建
│   ├── frozen_harness_refs.yaml/     # ① 输入冻结快照 = 改进前的原始包（目录形态）
│   ├── single_harness_state.yaml     # ② 最终状态
│   ├── single_harness_report.yaml    # ③ 汇总报告
│   ├── epoch_checkpoints.yaml        # ④ 每 epoch 门禁决策记录
│   ├── member_optimization_ref.yaml  # ⑤ 成员优化动作索引
│   ├── published_harness_refs.yaml   # ⑥ 发布索引（publication_status: published）
│   └── published/
│       └── skill_package/            # ⑦ 发布包 = 改进后的包（与 skill_package/ 当前内容一致）
└── src/main/java/com/example/rsidemo/
    ├── RsiSkillDemo.java        # 主类：预检 → SPI 探测 → 启动 → 轮询 → 断言 → 打印产物
    ├── DemoRsiRuntime.java      # RsiRuntimeImpl 子类：仅替换 2 个 LLM 依赖组件
    ├── StubEvaluator.java       # 脚本化评测器（分数曲线模拟 RSI 改进）
    ├── ScriptedActionPlanner.java # 确定性动作规划器（issue → modify 动作）
    ├── DemoFiles.java           # 幂等资产重建（内嵌全部初始文件内容）
    └── DatasetLoader.java       # dataset.json 预检
```

---

## 3. 改进前后的真实差异（diff 实测）

### 3.1 algebra.md（s2 代数 case 的成员文件）— 唯一从"一句话"扩写的文件

**改进前**（`output/frozen_harness_refs.yaml/prompt_sections/algebra.md`，冻结快照）：

```markdown
# algebra
解代数方程：把未知数移到等号一边，常数移到另一边，然后求解。
```

**改进后**（`output/published/skill_package/prompt_sections/algebra.md`，发布包）：

```markdown
# algebra
解一元一次方程的分步约定：
- 第一步：观察方程结构，明确未知数项与常数项。
- 第二步：利用等式性质 1（两边同加减同一个数），把常数项移到等号一边，并写明"两边同减/加 X"。
- 第三步：利用等式性质 2（两边同乘除同一个非零数），把未知数系数化为 1，并写明"两边同除以 X"。
- 第四步：把求得的解代入原方程回代验证，确认等式成立。
```

### 3.2 arith.md（s1 算术 case 的成员文件）— 两处措辞增强

**改进前**：

```markdown
# arith
解答加减乘除混合运算题的约定：
- 按运算优先级计算：先乘除后加减，有括号先算括号内。
- 给出每一步的中间结果，不要直接给最终答案。
- 得出最终答案后，用一句话复述题目和答案进行核对。
```

**改进后**：

```markdown
# arith
解答加减乘除混合运算题的约定：
- 按运算优先级计算：先乘除后加减，有括号先算括号内。
- 必须逐步给出每一步的中间结果，禁止跳步或直接给最终答案。
- 每完成一步，用一句话说明该步的运算依据（交换律、结合律或优先级）。
- 得出最终答案后，按原步骤顺序复述一遍进行核对，确认每步结果无误。
```

### 3.3 未变化的文件

`identity.md`、`logic.md`、`harness_config.yaml` 在改进前后完全一致（diff 为空）——它们对应的 case（s3）评分达标（0.90 ≥ 0.6 阈值），没有产生 issue，因此没有被优化。

---

## 4. 为什么 `skill_package/` 和 `output/published/` 内容相同？（关键机制）

这是框架 `ActionExecutor` 的**就地执行（in-place）语义**决定的，源码依据：

`ActionExecutor.execute()`（core-rsi 源码 `member_optimizer/ActionExecutor.java`）：

```java
public MemberOptimizationArtifact execute(String role, List<MemberOptimizationAction> actions) {
    ActionGroupPolicy.validateAll(actions);
    // ... 对每个动作：resolveInsideWorktree(action.path()) → 直接写 worktree 内的目标文件
}
```

- `ActionExecutor` 构造时接收 `worktreeRoot`。demo 中 `DemoRsiRuntime.createOrchestrator` 按框架默认装配传的是 `request.harnessRefsPath()`，即**输入包目录本身**（`skill_package/`）。
- 因此 `modify` 动作**直接改写了 `skill_package/prompt_sections/algebra.md`**——改进就发生在输入包目录里。
- 编排器随后的发布步骤（`ensureFinalPublication`）把优化后的包**拷贝**到 `output/published/skill_package/`，所以两者内容一致。

**结论**：运行后，`skill_package/` 已经是"改进后"状态，不再是初始薄弱版；初始薄弱版的唯一完整留档是**输入冻结快照** `output/frozen_harness_refs.yaml/`（编排器 run() 第 1 步"input freeze"在优化开始前拷贝的）。

**对比姿势**：

```bash
# ✅ 正确：改进前 vs 改进后
diff output/frozen_harness_refs.yaml/prompt_sections/algebra.md \
     output/published/skill_package/prompt_sections/algebra.md

# ❌ 错误：这两个都是"改进后"，diff 永远为空
diff skill_package/prompt_sections/algebra.md \
     output/published/skill_package/prompt_sections/algebra.md
```

---

## 5. 运行时序（实测日志解读）

demo 一次运行共 4 次评测调用（StubEvaluator 按 call 序号取分数脚本）：

| Call | 阶段 | 评测对象 | s1/s2/s3 | 均分 | 结果 |
|------|------|---------|----------|------|------|
| 0 | run() 步骤 2：基线评测 | 冻结快照 | 0.40/0.30/0.90 | 0.5333 | bestScore=0.5333，best=冻结快照 |
| 1 | epoch0 开始：复评当前包 | 冻结快照 | 0.40/0.30/0.90 | 0.5333 | EvaluationResultAnalyzer 检出 2 个 issue（s1=0.40、s2=0.30 均 < 0.6 阈值） |
| — | 成员优化（真实框架代码） | — | — | — | ScriptedActionPlanner 产出 2 个 modify 动作 → ActionExecutor **就地改写 skill_package/** → PublishCoordinator 写 member_optimization_ref.yaml（applied_actions: 2） |
| 2 | epoch0：候选评测 | skill_package（已增强） | 0.80/0.70/0.90 | 0.8000 | 指纹复验通过 |
| — | 两阶段门禁 | — | — | — | Stage1：目标 s1 +0.40、s2 +0.40 均 > 0.05 ✅；Stage2：非目标 s3 退化 0 ≤ 0.05 ✅；均分 0.80 > 0.5333 ✅ → **接受** |
| — | checkpoint | — | — | — | epoch_checkpoints.yaml 记录 last_gate_accepted: true |
| 3 | epoch1 开始：复评当前包 | skill_package | 0.80/0.70/0.90 | 0.8000 | 无 issue（全部 ≥ 0.6）→ **循环提前收敛** |
| — | 最终发布 | — | — | — | 拷贝 best 包到 output/published/，写 published_harness_refs.yaml（published）、single_harness_state.yaml |
| — | 任务终态 | — | — | — | RsiRuntimeImpl 7 态状态机 → COMPLETED，bestScore=0.8 |

对应 StubEvaluator 分数脚本（为什么 call 0/1 都是基线）：**编排器每个 epoch 开始都会先复评当前包**（框架行为），所以基线包被连评两次；call≥2 时包已增强。

---

## 6. 核心产物逐个说明

| 产物 | 内容 | 关键字段实测值 |
|------|------|--------------|
| `single_harness_state.yaml` | 任务最终状态 | task_id=rsi-6474bf27…、best_score=0.8、publication_status=published |
| `single_harness_report.yaml` | 汇总 | case_count=3、best_score=0.8、published |
| `epoch_checkpoints.yaml` | 每 epoch 一条门禁记录 | epoch 0：accepted=true；epoch 1 因无 issue 未写 checkpoint（循环在写 checkpoint 前已 break） |
| `member_optimization_ref.yaml` | 优化动作索引 | optimization_id=opt-fb847509…、applied_actions=2、candidate=skill_package |
| `published_harness_refs.yaml` | 发布索引 | publication_status=published + 指向 output/published/skill_package |
| `frozen_harness_refs.yaml/` | **改进前原始包快照**（目录） | 与发布包 diff 即改进 diff |
| `published/skill_package/` | 发布包 | 与 skill_package/ 当前内容一致 |

**注意**：epoch_checkpoints.yaml 只有一条 epoch 0 记录——epoch1 开头复评后 issues 为空，编排器在写 checkpoint 之前就 break 了，这是框架收敛逻辑的正常表现。

---

## 7. demo 源码逐文件说明

| 文件 | 职责 | 关键点 |
|------|------|--------|
| `RsiSkillDemo.java` | 主流程 | 路径解析（优先 cwd，回退固定路径）→ DemoFiles 资产重建 → DatasetLoader 预检（快速失败）→ SPI 探测（信息性打印 `RsiRuntimeImpl` 被发现）→ 用 `DemoRsiRuntime` 实际启动 → 100ms 轮询 30s 超时 → 断言 bestScore≈0.80（±1e-6）→ 打印两份产物 |
| `DemoRsiRuntime.java` | 唯一扩展缝 | 继承 `RsiRuntimeImpl`，仅重写 `createOrchestrator`：StubEvaluator + ScriptedActionPlanner 替换默认的 DeepAgentRsiEvaluator 与默认 lambda 规划器（两者需要 LLM）；其余 7 组件与框架默认装配逐一对齐（EvaluationResultAnalyzer / RoleAttributor("default") / MechanismAttributor / MemberSelector(1) / ActionExecutor(packageRoot) / HarnessChangeVerifier / PublishCoordinator(outputDir) / PromotionPolicy 默认阈值） |
| `StubEvaluator.java` | 分数曲线 | call 0/1 = 基线（0.40/0.30/0.90），call ≥2 = 改进后（0.80/0.70/0.90）；基线 trace 含 "skill" 关键词（供 suspectSurfaces 猜表面）；改进 trace = "回答正确：{expected}" |
| `ScriptedActionPlanner.java` | 动作配方 | issue.caseId → 成员文件映射（s1→arith.md，s2→algebra.md）；动作 = (action-\<caseId\>, prompt, modify, prompt_sections/\<member\>.md, 增强内容)，符合 ActionGroupPolicy 白名单 |
| `DemoFiles.java` | 幂等资产 | 内嵌 harness_config + 4 个 prompt_sections + dataset.json 的**初始版本**内容；每次运行删除 output/ 与 skill_package/ 重建，保证可重复复现 |
| `DatasetLoader.java` | 数据集预检 | Jackson 解析 {"cases":[…]}，空 cases 抛 IOException |

**为什么要替换 LLM 组件**：`RsiRuntimeImpl` 默认 `createOrchestrator` 硬编码 `new DeepAgentRsiEvaluator(outputDir)`（LLM-as-Judge，需要配置模型）。demo 在无模型环境运行，直接用默认装配会在首次评测时失败。继承重写后，issue 分析/门禁/指纹/发布/状态机仍然是**真实框架代码**，只有"评测打分"和"规划动作"两个环节被脚本化模拟——这正是 RSI 闭环中宿主需要注入自己模型能力的两个扩展点。

---

## 8. 复现步骤

```bash
cd D:\yaodh\main\yoskills\temp\20261119\rsi-skill-demo
run_demo.bat
# 或手动：
# javac -encoding UTF-8 -cp <5 个 jar> -d build\classes src\main\java\com\example\rsidemo\*.java
# java  -cp build\classes;<同上 classpath> com.example.rsidemo.RsiSkillDemo
```

预期输出最后一行：`[Demo] DONE: RSI skill 改进闭环验证通过 (bestScore=0.7999…)`，退出码 0。

每次运行都是幂等的：`DemoFiles` 先删 output/ 和 skill_package/ 再从内置常量重建，所以 skill_package 每次都会回到薄弱基线再被 RSI 改进一遍。

**classpath 依赖**（本地 Maven 仓库 `D:\java\maven-repo\`）：

| 构件 | 版本 | 备注 |
|------|------|------|
| agent-core-java | 0.1.17 | core + SPI 接口 |
| core-rsi | 0.1.17 | RSI 实现（含 META-INF/services 注册） |
| jackson-databind / core | 2.21.5 | 数据集解析 |
| jackson-annotations | **2.21** | 本地仓库无 2.21.5，注意版本 |

---

## 9. 已知限制与观察

1. **发布包与输入包同源**：`published/skill_package` 是从 `skill_package`（已被就地优化）拷贝的，所以两者一致；"改进前"只能从 `frozen_harness_refs.yaml/` 快照看。若希望输入包保持不被改写，可把 `ActionExecutor` 的 worktreeRoot 指向一个工作副本目录（框架支持，构造参数决定），这是宿主装配自由度。
2. **checkpoint 少一条**：收敛轮（无 issue）不写 checkpoint 是框架当前行为，不是 bug。
3. **frozen 快照是目录**：输入传目录时冻结也拷贝为同名目录（`frozen_harness_refs.yaml/` 名字带 .yaml 后缀但实际是目录）——这是框架 `freezeInput` 的行为，读取时注意。
4. **分数脚本与门禁的耦合**：改进幅度（+0.40）远大于阈值（0.05），保证门禁接受是确定性的；如果想让 demo 演示"门禁拒绝"分支，可把 call≥2 的分数改成非目标退化场景（如 s3=0.60）。
5. **bestScore 浮点**：0.7999999999999999 是 (0.8+0.7+0.9)/3 的标准 IEEE754 结果，主类断言用 ±1e-6 容差。
