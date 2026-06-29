---
name: jiuwen-skip-analysis
description: >-
  Analyze skipped/placeholder Jiuwen Java parity tests via LLM code review each run.
  Context: agent-core-java was translated from agent-core (Python); JiuwenTest_3820 tests
  were translated from JiuwenTest Python cases. Skipped usually means Java side has not
  caught up—distinguish agent-core-java SDK gap (功能缺失+具体缺口) vs test not translated
  (测试用例未翻译). Scripts discover candidates only; Agent reads Java+Python+SDK each run.
  Use when user asks to 分析 skipped 用例、parity 根因、SDK 功能缺失、测试未翻译、@Disabled 校准。
---

# Jiuwen Skip 用例分析（LLM 检视驱动）

## 项目背景（分析前必读）

本仓库是 **Python → Java 的 parity 迁移**：

| 层级 | Python 原版 | Java 翻译版 |
|------|-------------|-------------|
| SDK | `agent-core/openjiuwen/` | `agent-core-java/` |
| 测试 | `JiuwenTest/cases/` | `JiuwenTest_3820/.../cases/` |

`agent-core-java` 初始版本从 `agent-core` 翻译而来；配套测试用例也从 Python 版测试翻译而来。

测试工程师将用例标记为 **skipped**（`@Disabled`、占位契约、AssumptionSkip 等），**通常是因为 Java 侧尚未完成 Python 对应用例/能力的翻译**。

## 分析目标（核心）

准确识别 skipped 的 **真正根因**，尤其是二者不可混淆：

| root_cause | 含义 | 后续动作 |
|------------|------|----------|
| **功能缺失** | `agent-core-java` **缺少** Python 用例所依赖的 SDK 能力 | 填 **`功能缺失明细`**（缺什么） | **`SDK实现证据` 留空** |
| **测试用例未翻译** | SDK **已具备** Python 用例针对的能力，Java 测试未实现 | 填 **`SDK实现证据`** + `测试待补项` | **`功能缺失明细` 留空** |
| **环境依赖** | Java 测试/SDK 调用链已对齐 Python，缺 mock/密钥 | 填 **`SDK实现证据`** + `测试待补项` | **`功能缺失明细` 留空** |
| 调试辅助 | 无 Python 对齐的 debug/smoke | — |

**判定口诀：先 grep SDK，再定根因** — 不能因「Java 测了静态契约」就判功能缺失；不能因 `@Disabled` 注释写 SDK gap 就盲信。

```
Python 用例依赖的能力，agent-core-java 有没有？
  ├─ 没有 / 不等价 → 功能缺失（必须写清具体缺什么）
  └─ 有 → 测试用例未翻译（**必须写 SDK实现证据**）或 环境依赖 / 调试辅助
```

**互斥列规则（merge 时会校验）：**

- `root_cause=功能缺失` → 只填 `功能缺失明细`
- `root_cause=测试用例未翻译` 或 `环境依赖` → 只填 `SDK实现证据`（**禁止空着交付**）

## 核心原则

**每次分析都必须由 Agent（大模型）读代码后判定根因。** 禁止把脚本猜测、历史缓存、模块模板当作最终结论。

| 角色 | 做什么 | 不做什么 |
|------|--------|----------|
| `export_skip_csv.py` | 发现 skip 候选，写骨架 CSV（`root_cause=待检视`） | 不填最终 root_cause |
| **Agent（你）** | 读 Java + Python + SDK；写 root_cause 及 **互斥证据列** | 不跳过 grep；不空口说「SDK 已有」 |
| `merge_reviews.py` | 把本轮检视结论写入 CSV | 不产生结论 |
| `examples/*.json` | 判例参考，帮助理解口径 | **禁止自动套用** |

## 路径约定

| 角色 | 路径 |
|------|------|
| Java 测试 | `JiuwenTest_3820/.../cases/{模块}/` |
| Python 原用例 | `JiuwenTest/cases/{模块}/` |
| Java SDK | `agent-core-java/src/main/java/` |
| Python SDK | `agent-core/openjiuwen/` |
| 骨架/结果 CSV | `localoutput/{模块}-skip用例分析.csv`（目录不存在时脚本自动创建） |
| 套件注册 | `scripts/modules.json` |

## 标准工作流（每次用户请求分析时执行）

```
- [ ] 1. export 骨架 CSV（全部 root_cause=待检视）
- [ ] 2. 按检视顺序分批读代码（见下）
- [ ] 3. 每批检视后写 reviews JSON，merge 进 CSV
- [ ] 4. 确认无遗漏的「待检视」行（或用户接受的范围）
- [ ] 5. 输出中文摘要给用户
```

### Step 1：导出骨架

```bash
python .cursor/skills/jiuwen-skip-analysis/scripts/export_skip_csv.py --module component
```

### Step 2：Agent 代码检视（必须）

对每个候选 **至少读**：

1. **Java 测试类**（`Java文件` 列指向的文件）
2. **Python 对应用例**（`Python用例` → `JiuwenTest/cases/{模块}/.../test_*.py`）
3. **SDK**（`agent-core-java` grep 关键类；必要时对照 Python SDK）

**检视顺序（component 示例）：**

1. `@Disabled` — **必须逐案**，不可批量模板
2. `AssumptionSkip` / `部分翻译`
3. 按 **子模块** 分批（如 `http_comp`、`sub_workflow_component`），每批选代表 case 精读 + 同类 spot-check

**判定根因（落实「项目背景」）：**

| root_cause | 条件 |
|------------|------|
| **功能缺失** | Python 用例依赖的 SDK 能力在 `agent-core-java` **不存在或不等价** → 测试无法写/无法过；**必须**填 `功能缺失明细`（具体类、方法、行为契约） |
| **测试用例未翻译** | SDK 已有等价能力（**须用 grep/路径写入 `SDK实现证据`**）；Java 侧仅静态契约/占位 | **禁止**在无证据时标测试未翻译 |
| **环境依赖** | Java 测试逻辑与 Python 对齐（**`SDK实现证据` 证明**）；缺 mock/密钥 | |
| **调试辅助** | 无 Python 对齐的 debug/smoke |
| **其他** | 暂无法归类 |

**`SDK实现证据` 要求**（`root_cause=测试用例未翻译` 或 `环境依赖` 时 **必填**）：

格式见 [reference.md](reference.md)。至少包含：

1. **Python 依赖**：对应用例用到的类/方法/API
2. **Java 证据**：`agent-core-java` 文件路径 + 类/方法（或 grep 结果）
3. **结论**：SDK 已具备何种能力，缺口仅在测试侧或环境侧

**`功能缺失明细` 要求**（`root_cause=功能缺失` 时 **必填**）：写明 Python 入口、Java grep **未命中/不等价** 的具体缺口。

**`测试待补项` 要求**：测试侧待补项（Workflow 拓扑、mock、断言点）。

**硬性要求：**

- `@Disabled` 注释 **不可盲信**，须 grep SDK 验证
- 不得因「子模块名像缺 SDK」就直接标功能缺失
- 批量占位 case 可同类归纳，但 `analysis` 须写清依据（读了哪几个代表文件）

### Step 3：写入 CSV

检视一批后，生成 JSON（key = **类名**）：

```json
{
  "SubWorkflowComponent033Test": {
    "优先级": "p1",
    "根因": "测试用例未翻译",
    "测试待补项": "需 main_workflow+SubWorkflowComponent invoke",
    "SDK实现证据": "Python依赖: SubWorkflowComponent+main_workflow.invoke | Java证据: .../SubWorkflowComponent.java, Workflow.invoke | 结论: SDK 已有，Java 仅静态 Map",
    "分析说明": "读了 SubWorkflowComponent033Test、test_sub_workflow_component_033.py、grep SubWorkflowComponent",
    "功能缺失明细": ""
  },
  "TestLoopStream001": {
    "优先级": "p1",
    "根因": "功能缺失",
    "测试待补项": "",
    "SDK实现证据": "",
    "分析说明": "Python 消费完整 stream 后断言 workflow_final…",
    "功能缺失明细": "Loop stream/collect 完成后 workflow_final 批出契约未实现…"
  }
}
```

合并进 CSV：

```bash
python .cursor/skills/jiuwen-skip-analysis/scripts/merge_reviews.py \
  --module component --reviews /path/to/batch1.json
```

可多次 `--reviews` 追加。全部检视完成前，未检视行保持 `root_cause=待检视`。

### Step 4：交付

1. `localoutput/{模块}-skip用例分析.csv`
2. 中文摘要：总数、root_cause 分布、SDK 缺口 TOP
3. **校验**：`测试用例未翻译` 行均含非空 `SDK实现证据`；`功能缺失` 行均含 `功能缺失明细`（merge 脚本会打印 warnings）

## CSV 列（列头全中文）

`Java文件, 类名, 模块, 子模块, Python用例, 跳过类型, 优先级, 根因, 测试待补项, SDK实现证据, 分析说明, 跳过原因, 功能缺失明细`

- **`SDK实现证据`**：`测试用例未翻译` / `环境依赖` 时 **必填**；写 agent-core-java 已实现能力的可复核证据
- **`功能缺失明细`**：`功能缺失` 时 **必填**；写 SDK 具体缺口
- 两列 **互斥**，不可同时填

## 禁止事项

- 禁止运行旧版「自动填 overrides/模块默认模板」逻辑
- 禁止只跑 `export_skip_csv.py` 就把 CSV 当最终交付
- 禁止在无 **`SDK实现证据`** 的情况下将 case 标为 **测试用例未翻译**

## 参考（非结论来源）

- 决策树：[reference.md](reference.md)
- Component SDK 检视要点：[modules/component.md](modules/component.md)
- 历史判例样式（勿自动套用）：[examples/component-review-samples.json](examples/component-review-samples.json)
- 禁止引用 `examples/*.json` 中的结论而不读当前代码

## 命令速查

```bash
python .cursor/skills/jiuwen-skip-analysis/scripts/export_skip_csv.py --list-modules
python .cursor/skills/jiuwen-skip-analysis/scripts/export_skip_csv.py --module component
python .cursor/skills/jiuwen-skip-analysis/scripts/merge_reviews.py --module component --reviews batch.json
```
