# Jiuwen Skip 分析参考（通用）

## 项目背景

- **SDK**：`agent-core`（Python）→ `agent-core-java`（Java 翻译版）
- **测试**：`JiuwenTest/cases/`（Python）→ `JiuwenTest_3820/.../cases/`（Java 翻译版）
- **skipped 的常见含义**：Java 侧尚未完成 Python 对应用例/能力的跟进

## 分析的核心问题

> **是 agent-core-java 功能缺失，还是 SDK 已有 merely 测试未翻译？**

| 结论 | 必填列 | 留空列 |
|------|--------|--------|
| **功能缺失** | `功能缺失明细` | `SDK实现证据` |
| **测试用例未翻译** | **`SDK实现证据`** + `测试待补项` | `功能缺失明细` |
| **环境依赖** | **`SDK实现证据`** + `测试待补项` | `功能缺失明细` |
| **调试辅助** | — | 两列均可空 |

## `SDK实现证据` 怎么写（测试未翻译 / 环境依赖 必填）

须可复核，建议 **三段式**（可写在一格内，用 `|` 分隔）：

```
Python依赖: {Python 用例用到的类/方法/API}
Java证据: {agent-core-java 相对路径#符号 或 grep 命中说明，至少 1 处}
结论: SDK 已具备 {能力摘要}，缺口仅在 Java 测试侧 {未 build Workflow / 未 mock / ...}
```

**合格示例（测试未翻译）：**

```
Python依赖: SubWorkflowComponent + main_workflow.invoke | Java证据: agent-core-java/.../SubWorkflowComponent.java, SubWorkflowComponentImpl.java；Workflow.invoke 存在 | 结论: 子工作流组件 SDK 已有，Java 测试仅静态 ExpectedOutput
```

**合格示例（环境依赖）：**

```
Python依赖: ToolComponent + RestfulApi PUT | Java证据: RestfulApi.java configureMethodAndBody 含 PUT；RestfulApiCard.SUPPORTED_METHODS 含 PUT | 结论: HTTP 方法已实现，失败因无 localhost:8000 mock
```

**不合格（禁止交付）：**

- 「SDK 已存在」（无路径/grep）
- 只写类名无文件路径
- 未说明 Python 用例实际依赖什么

## root_cause 决策树

```
1. Python 用例依赖什么 SDK 能力？（读 test_*.py）

2. agent-core-java grep + 必要时对照 agent-core：
   - 类/方法不存在或行为明显不等价 → 功能缺失 → 功能缺失明细
   - 类/方法存在且足以支撑 Python 用例 → 测试未翻译 → SDK实现证据（必填）
   - Java 测试已对齐 Python，仅缺 mock/密钥 → 环境依赖 → SDK实现证据（必填）

3. 调试辅助：无 Python 对齐
```

## merge_reviews JSON 格式

```json
{
  "ConditionalEdgeSampleTargetContractTest": {
    "优先级": "p1",
    "根因": "测试用例未翻译",
    "测试待补项": "需构建 Branch/conditional 工作流并 invoke/stream",
    "SDK实现证据": "Python依赖: BranchComponent+Workflow.addConditionalConnection | Java证据: BranchComponent.java; Workflow.java addConditionalConnection grep 命中 | 结论: 路由组件 SDK 已有，Java 仅 assertPythonCase 字符串",
    "分析说明": "读了 Java 契约类、Python test_branch_edge_*.py、grep BranchComponent",
    "功能缺失明细": ""
  },
  "TestHttpComp001": {
    "优先级": "p1",
    "根因": "功能缺失",
    "测试待补项": "",
    "SDK实现证据": "",
    "分析说明": "Python 使用 HTTPRequestComponent 构建工作流",
    "功能缺失明细": "grep agent-core-java 无 HTTPRequestComponent；仅有 RestfulApi（Tool 层）"
  }
}
```

## 功能缺失 vs 测试未翻译 — 易混场景

| 现象 | 常见误判 | 正确思路 |
|------|----------|----------|
| Java 只有静态 Map 契约 | 功能缺失 | grep Python 用的组件 → 有则 **测试未翻译 + SDK实现证据** |
| `@Disabled` 写 SDK gap | 功能缺失 | grep 验证后再定 |
| Tool localhost 失败 | 功能缺失 | RestfulApi 已有 → **环境依赖 + SDK实现证据** |
| Python 用 HTTPRequestComponent，Java 无 | 测试未翻译 | grep 0 匹配 → **功能缺失** |

## 新增套件

1. `modules.json` 注册
2. `export_skip_csv.py --module {suite}`
3. Agent 检视 + `merge_reviews.py`（校验 warnings 须清零或解释）
4. 复杂 grep 清单 → `modules/{suite}.md`
