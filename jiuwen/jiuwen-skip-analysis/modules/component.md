# Component 套件专项参考

> 通用背景与决策树见 [../SKILL.md](../SKILL.md)、[../reference.md](../reference.md)。
> 本节列 component 检视时的 **SDK grep 清单**（验证「功能缺失 vs 测试未翻译」）。

## 本模块常见 split

| 子模块 | 多为功能缺失 | 多为测试未翻译 |
|--------|--------------|----------------|
| http_comp | HTTPRequestComponent 整类缺失 | — |
| react_agent_comp | ReActAgentComp 缺失 | — |
| memory_write_retrieval_comp | Memory 工作流组件缺失 | — |
| execute_single_component | ComponentExecutionHelper 不等价 Python | — |
| sub_workflow_component | — | SubWorkflowComponent 已有，缺 main_workflow 测试 |
| end_template | — | End/Workflow 已有，EndTemplateTestSupport 硬编码 |
| tool_component | 少见 | 常为工作流已翻译，缺 mock |

## 批量检视策略（Agent 读代码时参考）

| 子模块 | 检视重点 |
|--------|----------|
| `@Disabled` | 必须逐案读 Java+Python+SDK |
| `execute_single_component` | `ComponentExecutionHelper` vs Python `execute_single_component` |
| `http_comp` / `react_agent_comp` / `memory_*` | grep 工作流组件类是否存在 |
| `sub_workflow_component` | 是否 main_workflow+SubWorkflowComponent；SDK 通常已有 |
| `end_template` | 是否仅 `EndTemplateTestSupport` 硬编码 |
| `tool_component` | 工作流是否对齐；失败是否缺 mock |

## SDK grep 清单（验证用）

### ComponentExecutionHelper

Python: `agent-core/openjiuwen/core/workflow/_workflow.py` → `execute_single_component`

### 工作流组件（常见缺口，须 grep 确认）

| 子模块 | 查找类 |
|--------|--------|
| http_comp | `HTTPRequestComponent`, `HttpComponentConfig` |
| react_agent_comp | `ReActAgentComp`, `ReActAgentCompConfig` |
| memory_write_retrieval_comp | `MemoryWriteComponent`, `MemoryRetrievalComponent` |

### 常见误判

- Tool PUT/DELETE 失败 → 常为缺 mock，非 SDK 不支持
- SubWorkflow 静态 ExpectedOutput → 多为测试未翻译
- @Disabled 注释 → 须 grep 验证

## 判例样式

见 [../examples/component-review-samples.json](../examples/component-review-samples.json)（**禁止自动套用**）。
