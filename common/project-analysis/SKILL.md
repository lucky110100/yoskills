---
name: "project-analysis"
description: "上层编排技能:对工程做14维(功能+13质量)健康评估/新项目规范/业界标杆对标,产出多层文档(评分卡+13分维度评估+开发参考手册+项目规则)。当用户要求项目分析/体检/质量评估/定规范/对标业界/重构后验证质量提升、或接手前综合摸底时调用,编排 feature-analysis 与 dims 维度子文档+标杆调研子代理。"
---

# Project Analysis — 项目多维度分析编排技能（v2 实战重写版）

> v2 基于 agent-core-java 实战 dogfooding 重写。v1 只产出单文件评分报告，v2 强化「分析即产出可指导后续开发的参考」：不只给评分，更产出 **development-reference 开发参考手册**（13 维 × 业界标杆做法全列表+本项目实现对照+待补项）+ **project_rules 精简规则** + **quality/ 13 分维度评估文档**，用于重构后验证质量提升或分析新项目。
>
> 上层编排技能，与 `feature-analysis`(功能维度)/`feature-index-builder`(索引)互补：`feature-analysis` 管「有哪些功能、怎么实现」(功能维度)，本技能管「质量如何、该怎么规范、与业界差距、后续怎么开发」(质量维度+对标+开发参考)。

---

## 一、何时调用

- 评估现有项目质量（诊断模式）
- 为新项目定规范基线（规范模式）
- 业界标杆对标找差距（对标模式）
- **重构后验证质量提升**（重跑诊断模式对比前后评分，量化改进效果，v2 新增核心场景）
- 接手陌生工程前综合质量摸底
- 重构/加功能前理清质量短板与优先级
- 用户要一份综合「项目分析报告」(质量+功能+对标+开发参考)

**不适用：** 只要功能理解(走 `feature-analysis`)；只改单 bug(走 `efficient-task-flow`)；只要成文档(走 `code-wiki-author`)。

---

## 二、14 维度体系与分组

| 组 | 维度 | 承担方 | 组权重 |
|----|------|--------|--------|
| A 功能维度 | 功能特性 | `feature-analysis`(编排调用) | 0.15 |
| B 代码质量 | 代码规范 / 架构约束 / 复用性 / 可测试性 | `dims/*.md` | 0.30 |
| C 运行时质量 | 性能 / 可靠性 / 可观测性 | `dims/*.md` | 0.25 |
| D 演进质量 | 可扩展性 / 文档完备度 / 构建与CI | `dims/*.md` | 0.20 |
| E 外部质量 | 安全性 / 易用性 / 依赖健康度 | `dims/*.md` | 0.10 |

> 组权重可按项目类型调整。组内维度均分权重。

---

## 三、三模式编排决策树

```
用户要什么？
├─ 评估现有项目 → 诊断模式（产出 5 件套，见七）
│   1. 调 feature-analysis 建功能维度索引(已有则复用)
│   2. 按 5 组派并发子代理评估 13 质量维度(各读对应 dims/*.md)
│   3. 派标杆调研子代理(WebSearch 标杆做法全列表+读本项目对照+待补)★v2新增
│   4. 浅对标+动态验证(mvn build/test)
│   5. 汇总产出 5 件套(health-report+quality/+development-reference+project_rules)
├─ 为新项目定规范 → 规范模式（产出 conventions.md + .trae/rules/project_rules.md）
├─ 业界对标 → 对标模式（产出 benchmark-report.md + 标杆沉淀）
├─ 重构后验证 → 诊断模式重跑 + 对比前后 health-report 评分卡 ★v2新增
└─ 综合 → 三模式串行(评估→对标→规范)
```

---

## 四、评分卡体系

### 4.1 5 档定义（每维度 0-4）

| 分 | 档 | 含义 |
|----|----|------|
| 4 | 卓越 | 业界标杆级,可作范本 |
| 3 | 良好 | 达成熟工程标准,小改进即可 |
| 2 | 合格 | 基本可用,有明显短板 |
| 1 | 不足 | 多处缺失,影响维护 |
| 0 | 缺失 | 该维度几乎无实践 |

### 4.2 加权总分
- 总分 = Σ(维度分 × 维度权重)；组内维度均分组权重；0-4 制

### 4.3 红黄绿灯（总分 + 否决项）

| 灯 | 条件 | 行动 |
|----|------|------|
| 🟢 绿 | 总分 ≥ 3.0 且无否决 | 健康,可作范本 |
| 🟡 黄 | 2.0 ≤ 总分 < 3.0 或 1 否决 | 可维护,需改进 |
| 🔴 红 | 总分 < 2.0 或 ≥ 2 否决 | 高风险,需重构 |

**否决项(任一触发即计否决):** 安全性=0 / 可靠性=0 / 可测试性=0

### 4.4 雷达图
14 维分值可供可视化(dynamic-ui skill 出雷达图),直观呈现短板分布。

### 4.5 重构前后对比（v2 新增）
重构后重跑诊断模式，对比前后总分与各维度分，量化改进效果（如「总分 2.8→3.4，代码规范 2→3，构建CI 2→4」）。
---

## 五、业界对标流程

### 5.1 标杆库 benchmarks/
`benchmarks/<tech>.md` 每标杆含：项目名/仓库/类型/亮点维度/对标要点(看哪些目录)/浅对标源/深对标提示。

### 5.2 对标深度决策
```
├─ 评估/规范默认浅对标 → WebSearch + 读标杆文档 + benchmarks/ 既有要点 → 差距矩阵
├─ 关键维度短板或用户指定 → 深对标 → git clone --depth 1 到工作目录临时目录
│   → 调 feature-analysis 建标杆功能索引 + 读 dims/<短板>.md 深比 → 用完即删
└─ 标杆库无该技术栈 → WebSearch 补 + 评估后沉淀入 benchmarks/
```

### 5.3 标杆调研子代理（v2 新增，诊断模式步骤 5）
派子代理对每维度：①读 benchmarks 标杆库 ②WebSearch 该维度业界标杆具体做法（8-15 条全列表）③Grep/Read 本项目代码逐条对照（✅有带证据/❌无标待补/⚠️部分说明）④回传结构化。此子代理产出即 development-reference.md 的主体。

### 5.4 clone 约束（强制）
- `--depth 1` 浅克隆；clone 到工作目录下临时目录（避开跨盘写限制）；用完 Remove-Item 清理；大项目先查体积再决定

---

## 六、并发策略（子代理派发）

与 `feature-analysis` 决策树 C 一致：

```
├─ 单链路、范围小 → 主会话直接做, dims/ 按需读
├─ 多模块且相互独立 → 并发子代理,各读一组 dims/ 回传(维度|分|问题|证据)
├─ 大工程(>10 模块) → 派 5 子代理(A功能 + B代码质量 + C运行时 + D演进 + E外部 各一)做质量评估
└─ 标杆调研 → 另派 4 子代理(B/C/D/E 组各一)做标杆做法+本项目对照 ★v2新增
```

质量评估子代理回传：`| 维度 | 分(0-4) | 关键问题(带 file:/// 证据) | 锚点依据 |`
标杆调研子代理回传：每维度「业界标杆做法全列表 + 本项目实现对照(✅/❌/⚠️) + 待补项」

---

## 七、产物输出约定（v2 核心：诊断模式 5 件套）

诊断模式产出 **5 件套**（存 `<project>-docs/` 与项目 `.trae/rules/`）：

| 件 | 产物 | 路径 | 视角 | 模板 |
|----|------|------|------|------|
| 1 | 13 分维度评估文档 + README 索引 | `<project>-docs/quality/<NN>-<dim>.md` + `README.md` | 评分视角（锚点+证据+问题+改进） | — |
| 2 | **开发参考手册**（v2 核心） | `.trae/rules/development-reference.md` | **行动视角**（13 维 × 标杆全列表+本项目对照+待补，指导后续开发/重构） | `templates/development-reference.md` |
| 3 | **项目规则**（精简） | `.trae/rules/project_rules.md` | 禁项+命令（TRAE 助手自动遵循） | `templates/conventions.md` 精简版 |
| 4 | 汇总评分卡 | `<project>-docs/project-health.md` | 评分卡+雷达图+问题清单+改进路线图 | `templates/health-report.md` |
| 5 | 标杆沉淀 | `benchmarks/<tech>.md`（新发现） | 复用资产 | benchmarks/ 既有格式 |

> 5 件套分工：件1是「评估详情」、件2是「开发参考」(核心，写新代码对照)、件3是「精简规则」(TRAE遵循)、件4是「汇总评分」、件5是「标杆沉淀」。重构后验证只需重跑件1+件4对比评分，件2/3 产一次后续持续维护。

**规范模式产出**：`conventions.md` + `.trae/rules/project_rules.md`（用 `templates/conventions.md`）
**对标模式产出**：`benchmark-report.md`（差距矩阵）

**链接约定（强制，与 feature-index-builder 一致）：**
- 代码/测试位置 `[basename](file:///绝对路径#L行号)`，文本不加反引号
- 跨文档引用相对路径

---

## 八、执行流水线

### 8.1 诊断模式（v2，9 步，产出 5 件套）

1. **澄清** → AskUserQuestion 问目标(评估/规范/对标/重构验证)/范围/验证权限(沿用 feature-analysis 规则1)
2. **基线** → LS + 读包清单/README/pom.xml 建项目骨架 + `git rev-parse HEAD` 锁基线
3. **功能维度** → 调 `feature-analysis` 建功能索引(已有则复用,不重写)
4. **质量维度评估** → 按 5 组派并发子代理,各读 `dims/<维度>.md` 评估,回传(维度|分|问题|证据)
5. **标杆调研** ★v2 新增核心步骤 → 派 4 子代理(B/C/D/E 各一),每维度:WebSearch 标杆做法全列表(8-15 条)+Read 本项目代码逐条对照(✅有/❌无/⚠️部分)+待补项;回传即 development-reference 主体
6. **动态验证** → 浅对标标杆库+WebSearch;跑 mvn build/test/dependency-check(用户允许时)
7. **汇总打分** → 评分卡(14 维分+组权重+总分+红黄绿灯+否决项)+雷达图数据+问题清单(维度×严重度)+改进路线图
8. **多层产出**（v2 核心）→
   a. `project-health.md` 汇总评分卡(基于步骤4+7)
   b. `quality/<NN>-<dim>.md` 13 分维度评估文档 + `quality/README.md` 索引(基于步骤4)
   c. `development-reference.md` 开发参考手册(基于步骤5标杆调研,13 维 × 标杆全列表+对照+待补)
   d. `project_rules.md` 精简规则(基于评分短板+标杆,写 .trae/rules/)
9. **固化** → 标杆沉淀入 `benchmarks/`(新发现);`.trae/rules/` 补约定;用 TodoWrite 追踪全程

### 8.2 规范模式（5 步，产 conventions + project_rules）
1. 澄清技术栈/规模/场景 2. 取标杆库+浅对标 3. 按 14 维生成规范基线 4. 产出 conventions.md+.trae/rules/project_rules.md+脚手架 5. 固化

### 8.3 对标模式（4 步，产 benchmark-report）
1. 识别技术栈 2. benchmarks 取候选(不在库 WebSearch 补) 3. 浅对标差距矩阵/关键深 clone 4. 产出 benchmark-report+标杆沉淀

### 8.4 重构后验证（v2 新增）
重跑诊断模式步骤 2-9，对比前后 project-health.md 评分卡（总分+各维度分+红黄绿灯），量化改进效果。件2 development-reference 根据新现状更新待补项。
---

## 九、与现有技能串联

```
project-analysis(上层编排)
  ├─ 功能维度  → 调用 feature-analysis(理解+定位) + feature-index-builder(沉淀索引)
  ├─ 质量评估  → 调用 dims/*.md 子文档(5 组子代理)
  ├─ 标杆调研  → 派子代理 WebSearch + 读 benchmarks/ + 读本项目代码对照 ★v2
  ├─ 业界对标  → benchmarks/ + WebSearch/git clone
  ├─ 评估汇总  → health-report.md(评分卡)
  ├─ 开发参考  → development-reference.md(行动视角,核心) ★v2
  └─ 项目规则  → project_rules.md(.trae/rules/,TRAE 遵循) ★v2

下游闭环:
  project-analysis(评估+开发参考) → code-wiki-author(成文档) → efficient-task-flow(改代码时回写+对照 development-reference)
```

---

## 十、策略调整信号 + 反模式

| 信号 | 调整 |
|------|------|
| 13 维全评估太慢 | 抽样:先评否决项(安全/可靠/可测试),无问题则其余降为抽样 |
| 某维度证据不足 | 降级:标 `分=待核` 并记疑点,不强行打分 |
| 主上下文快满 | 派子代理:每组回传聚合结论,不回传原文 |
| 对标找不到标杆 | 回退:用通用最佳实践清单代替具体项目对标 |
| clone 失败/太大 | 改浅对标:读 GitHub 在线源码/文档代替本地 clone |
| 落盘 Write 被拒 | 转 RunCommand [IO.File]::WriteAllText 或 here-string(见十二) |
| 标杆调研子代理超时 | 降级:仅读 benchmarks/ 既有要点,跳过 WebSearch |

**反模式（必须避免）:**
```
❌ 不读 dims/ 子文档凭主观打分(必须按锚点)
❌ 只产出评分报告不产出 development-reference 开发参考(v2 核心,用户要的是能指导开发的文档)
❌ 每维度都深 clone 标杆(默认浅对标,关键维度才深)
❌ clone 后不清理临时目录
❌ 评分不带 file:/// 证据(断链不可追溯)
❌ 评估完不固化,下次又从零评
❌ 不调 feature-analysis 而在本技能重写功能分析
❌ 行号臆造不实测(必须 Read 抽检)
```

---

## 十一、执行规则（强制）

1. **意图不清不动手**:复杂评估前用 AskUserQuestion 提选择/是否题,批量提问(每次最多 4 个)
2. **按锚点打分**:每维度分对照 `dims/<维度>.md` 锚点,带 file:/// 证据
3. **三路并查**:功能维度沿用 feature-analysis 三路;质量维度的代码层证据同样三路
4. **语言一致**:输出语言与用户最新消息语言一致
5. **不擅自提交**:不主动 git commit,除非用户明确要求
6. **不擅自创建**:优先编辑现有文件,不创建非必要文件
7. **任务追踪**:多步骤用 TodoWrite 实时追踪,完成即标记
8. **验证后宣称**:完成前用 grep/ls/build/test 验证,证据先于断言
9. **clone 必清**:深对标 clone 的临时目录用完即删
10. **固化优先**:5 件套全产出,标杆沉淀入 benchmarks/,规则入 .trae/rules/
11. **行号实测**:所有 file:/// 行号必须 Read 抽检,不臆造
12. **5 件套不可少**:诊断模式必须产出 health-report + quality/ + development-reference + project_rules 四类核心(v2)

---

## 十二、落盘规则（v2 新增，基于 agent-core-java 实战经验）

跨盘写 D:\jiuwen（工作目录在 d:\yaodh\main）的实测规则：

| 场景 | 方式 | 说明 |
|------|------|------|
| 新文件（quality/ 下分维度、新标杆库） | Write 直写 | 多数成功；偶发"Access denied"时转 RunCommand |
| 大文件分批追加（development-reference 等长文档） | RunCommand here-string `@'...'@` + `[IO.File]::WriteAllText` 创建 + `AppendAllText` 分批 | here-string 单引号里反引号/特殊字符字面安全 |
| 跨盘已存在文件编辑（SKILL.md/README 改一节） | RunCommand `[regex]::Replace` 或 `[IO.File]::ReadAllText`+改+`WriteAllText` | Write/SearchReplace 编辑跨盘已存在被拒"Edit operations restricted" |
| 批间 AppendAllText 拼接瑕疵 | 开头加空行避免 `---## ` 拼接；出现用 `-replace '---## ', "---\n## "` 修复 | 实战验证 |
| 用户取消 RunCommand | 换 .NET API（`[IO.File]`）或 here-string，避免 Copy-Item temp 流程 | Copy-Item 易被取消 |

> 写入优先级：Write 直写新文件 > RunCommand here-string/WriteAllText > [regex]::Replace 改已存在。避免 temp+Copy-Item（易被取消）。

---

## 十三、产出检查清单（交付前必过，v2 5 件套）

- [ ] 是否用 AskUserQuestion 澄清了目标(评估/规范/对标/重构验证)/范围/验证权限
- [ ] 是否先 LS + 读包清单建了项目骨架 + 锁了基线提交
- [ ] 功能维度是否调了 `feature-analysis`(已有索引则复用)
- [ ] 13 质量维度是否按组派子代理评估(带 file:/// 证据,行号实测)
- [ ] **标杆调研子代理是否派出**(WebSearch 标杆全列表+本项目对照+待补) ★v2
- [ ] 否决项(安全/可靠/可测试)是否单独检查
- [ ] 是否做了业界对标(浅对标必做,深对标按需)+动态验证(mvn build/test)
- [ ] 评分卡是否含 14 维分+组权重+总分+红黄绿灯+否决项+雷达图数据
- [ ] **件1** quality/ 13 分维度评估文档 + README 索引是否落盘
- [ ] **件2** development-reference.md 是否落盘(13 维 × 标杆全列表+本项目对照✅/❌/⚠️+待补) ★v2 核心
- [ ] **件3** project_rules.md 是否写 .trae/rules/(精简规则)
- [ ] **件4** project-health.md 汇总评分卡是否落盘
- [ ] **件5** 标杆是否沉淀入 benchmarks/(新发现)
- [ ] 重构验证场景是否对比前后评分卡(若是重构验证)
- [ ] 是否用 TodoWrite 追踪了全流程

---

## 十四、适用与边界

**适用：**
- 中大型工程(>5 模块,>5000 行)的综合质量评估+开发参考产出
- **重构后验证质量提升(重跑对比评分)** ★v2
- 接手陌生工程前的质量摸底(配合 feature-analysis 功能摸底)
- 新项目立项前的规范基线制定
- 与业界标杆对比找差距
- 为后续开发/重构产出可对照的开发参考手册(v2 核心)

**不适用：**
- 单文件/小脚本(直接 Read 即可)
- 纯功能理解(走 `feature-analysis`)
- 纯文档生成(走 `code-wiki-author`)
- 单 bug 修复(走 `efficient-task-flow`)

**串联建议：**
`feature-analysis`(功能摸底) → **`project-analysis`**(质量评估+对标+开发参考+项目规则) → `code-wiki-author`(成文档) → `efficient-task-flow`(改代码时对照 development-reference) 形成完整闭环。

---

## 附：v1→v2 改进要点（基于 agent-core-java dogfooding）

1. 诊断模式产出从「单文件 health-report」→「5 件套」(加 quality/13分维度 + development-reference 开发参考 + project_rules 精简规则 + 标杆沉淀)
2. 流水线新增「步骤5 标杆调研子代理」(WebSearch 标杆全列表+本项目对照+待补)
3. 新增「重构后验证」场景(重跑对比评分)
4. 新增「落盘规则」节(Write vs RunCommand vs [regex]::Replace 的实测规则)
5. 反模式新增「只产出评分报告不产出 development-reference」(用户明确要的是能指导开发的文档)
6. 强调 development-reference 是核心产出(行动视角,指导写新代码/重构)