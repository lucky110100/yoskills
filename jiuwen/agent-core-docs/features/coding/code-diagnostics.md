# 代码诊断与自动修复闭环

> 交叉引用: [01-项目概述](../../01-project-overview.md) | [02-整体架构](../../02-overall-architecture.md) | [04-harness模块](../../04-harness-module.md) | [08-依赖关系](../../08-dependencies.md)

## 一、能力概述

代码诊断与自动修复闭环是 agent-core 区别于普通「编辑器 + LLM」组合的关键能力。它不仅能在编辑后自动捕获语言服务器推送的诊断信息,还能把这些诊断格式化注入 LLM 上下文,驱动模型在后续轮次中持续修复,直到诊断清空——整个过程无需模型显式调用任何诊断工具。

该能力以 [LspDiagnosticRegistry](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/core/diagnostic_registry.py#L107) 进程级单例为缓冲中枢,以 [LspRail](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/rails/lsp_rail.py#L20) 的双钩子(after_tool_call / before_model_call)为闭环引擎,将「编辑-重分析-注入-再编辑」串联为一个自驱动循环。这使得 agent-core 的智能体具备「自我纠错」的工程化闭环,显著降低人工介入频率。

在 agent-core 的分层架构中,诊断闭环属于 Rail 层的横切能力:它横跨工具调用与模型调用两个阶段,以 priority=60 在 SysOperationRail(priority=100)之后装配,确保编辑工具就绪后再接管诊断触发。

## 二、关键类与函数

| 类/函数 | 文件位置 | 说明 |
|---------|---------|------|
| [LspDiagnosticRegistry](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/core/diagnostic_registry.py#L107) | diagnostic_registry.py#L107 | 进程全局单例,缓冲 publishDiagnostics 通知 |
| [LspDiagnosticItem](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/core/diagnostic_registry.py#L37) | diagnostic_registry.py#L37 | 单条诊断:message/severity(1-4)/range/source/code |
| [LspDiagnosticFile](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/core/diagnostic_registry.py#L48) | diagnostic_registry.py#L48 | 文件级诊断集合:uri/diagnostics/server_name/local_path |
| [register](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/core/diagnostic_registry.py#L164) | diagnostic_registry.py#L164 | 缓存 publishDiagnostics 通知到注册表 |
| [get_and_clear](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/core/diagnostic_registry.py#L188) | diagnostic_registry.py#L188 | 6 步流水线取出并清空待发诊断 |
| [LspRail](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/rails/lsp_rail.py#L20) | lsp_rail.py#L20 | priority=60,双钩子实现诊断自动闭环 |

## 三、实现机制

### 3.1 诊断数据结构

[LspDiagnosticItem](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/core/diagnostic_registry.py#L37) 封装单条诊断,字段包括 message、severity(LSP 规范 1=Error/2=Warning/3=Info/4=Hint)、range、source、code。[LspDiagnosticFile](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/core/diagnostic_registry.py#L48) 以文件为单位聚合,记录 uri、diagnostics 列表、server_name 与本地 local_path,便于把 LSP 的 file:// URI 映射回工作区路径。

### 3.2 publishDiagnostics 缓冲

语言服务器在分析后通过 `textDocument/publishDiagnostics` 推送结果。[_ensure_diagnostic_handler](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/core/manager.py#L321) 幂等注册 handler,以 `id(server)` 去重避免重复绑定。handler 调用 [register](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/core/diagnostic_registry.py#L164),将通知缓冲到单例中,等待后续消费。

### 3.3 get_and_clear 6 步流水线

[get_and_clear](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/core/diagnostic_registry.py#L188) 是诊断消费的核心,执行 6 步流水线:

1. 合并本轮所有文件的诊断通知。
2. 批内去重:以 [_diag_key](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/core/diagnostic_registry.py#L90)(range+message+code)为键去重。
3. 跨轮次去重:对比 `_delivered` 已投递集合,避免重复向 LLM 推送相同诊断。
4. 按 severity 排序:Error 优先于 Warning/Info/Hint。
5. 每文件 cap 10:MAX_DIAG_PER_FILE([diagnostic_registry.py#L28](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/core/diagnostic_registry.py#L28)),防止单文件刷屏。
6. 全局 cap 30:MAX_DIAG_TOTAL([diagnostic_registry.py#L29](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/core/diagnostic_registry.py#L29)),控制上下文预算。

### 3.4 LspRail 双钩子闭环

[LspRail](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/rails/lsp_rail.py#L20) 以 priority=60 装配,通过双钩子实现自动闭环:

- **after_tool_call**([lsp_rail.py#L263](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/rails/lsp_rail.py#L263)):检测到 edit_file/write_file 工具调用后,通过 `asyncio.ensure_future` 异步触发 `manager.change_file`(或 `open_file`),通知 pyright 重新分析,分析结果经 publishDiagnostics 落入 registry 缓存。
- **before_model_call**([lsp_rail.py#L327](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/rails/lsp_rail.py#L327)):每次 LLM 调用前,调用 `get_pending_lsp_diagnostics` 取出诊断,经 [_format_diagnostics](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/rails/lsp_rail.py#L384) 格式化为 UserMessage 注入 messages 列表。

初始化与卸载:[_ensure_lsp_initialized](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/rails/lsp_rail.py#L163) 在首次模型调用前以 15s 超时完成 LSP 初始化;[uninit](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/rails/lsp_rail.py#L202) 移除工具并以 10s 超时关闭 LSP 服务。

### 3.5 注入消息格式

诊断注入 LLM 上下文的标准格式如下,模型据此定位并修复:

```
[LSP Diagnostics] The following issues were detected after the last file edit:
File: D:\...\test.py
  [Error] line 3, col 10  Expression of type "str" cannot be assigned to declared type "int"
Please review and fix these issues.
```

### 3.6 闭环时序

完整闭环的时序如下(文字时序图):

```
edit_file
   │
   ▼
after_tool_call 触发 didChange
   │
   ▼
pyright 重新分析
   │
   ▼
publishDiagnostics 推送
   │
   ▼
registry 缓存通知
   │
   ▼
下一轮 before_model_call 取出诊断
   │
   ▼
_format_diagnostics 注入 UserMessage
   │
   ▼
LLM 看到错误,继续 edit_file 修复
   │
   ▼
循环,直到诊断清空
```

该闭环的关键在于「异步触发、同步注入」:after_tool_call 不阻塞工具返回,诊断在下一轮模型调用前才同步取出,既保证编辑响应速度,又确保模型每轮都拿到最新诊断。

### 3.7 容量 cap 的设计动机

6 步流水线中的双 cap(每文件 MAX_DIAG_PER_FILE=10、全局 MAX_DIAG_TOTAL=30,见 [diagnostic_registry.py#L28-L29](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/core/diagnostic_registry.py#L28))并非随意取值,而是基于上下文预算的工程权衡:

- 单文件 cap 10:防止单个文件的大量同类错误(如一处类型错误引发数十条级联诊断)刷屏,挤占其他文件可见性。
- 全局 cap 30:与 LLM 上下文窗口预算对齐,确保诊断注入后仍留有充足空间给代码与历史消息。
- 排序优先级 Error > Warning > Info > Hint:在 cap 截断时优先保留高严重性诊断,保证模型先修最关键问题。

跨轮次去重(_delivered)则避免「同一错误在多轮中反复注入」造成的 token 浪费,让模型每轮都聚焦于尚未解决的新问题。

### 3.8 异步触发与同步注入的工程权衡

after_tool_call 采用 `asyncio.ensure_future` 异步触发 didChange,而非同步等待 pyright 分析完成。这一设计是刻意的工程权衡:

- **不阻塞工具返回**:edit_file/write_file 调用立即返回,模型可继续推进,无需等待可能耗时的全文件重分析。
- **容忍分析延迟**:pyright 分析可能耗时数百毫秒到数秒,异步化避免单次编辑被拖慢。
- **同步注入保证一致性**:诊断在下一轮 before_model_call 才同步取出,此时分析必然已完成,模型每轮都拿到确定性结果而非「可能还没分析完」的空值。

这种「写时异步、读时同步」的分离,在响应速度与数据一致性之间取得平衡,是 agent-core 闭环设计的核心技巧。

## 四、调用示例

```python
from openjiuwen import create_deep_agent, Runner
from openjiuwen.harness.rails.sys_operation_rail import SysOperationRail
from openjiuwen.harness.rails.lsp_rail import LspRail

agent = create_deep_agent(
    model="deepseek-chat",
    card="default",
    workspace="./proj",
    rails=[SysOperationRail(), LspRail()],
)

result = Runner.run_agent(
    agent,
    {"query": "修复 test.py 中所有语法错误,直到无报错"},
)
print(result.final_output)
```

完整可运行示例参见 `examples/lsp/deep_agent_lsp_demo.py`,该示例演示了从编辑触发到诊断清空的全过程。

## 五、业界对比

| 能力维度 | agent-core | Cursor | Claude Code | GitHub Copilot |
|---------|-----------|--------|-------------|----------------|
| 诊断自动捕获 | publishDiagnostics handler 自动缓冲 | 编辑器实时显示 | 无 LSP 自动捕获 | 无 LSP 自动捕获 |
| 编辑后自动重分析 | after_tool_call 异步触发 didChange | 编辑器内置 | 无 | 无 |
| 诊断注入 LLM 上下文 | before_model_call 自动注入 UserMessage | 不注入,靠人看 | 不注入 | 不注入 |
| 跨轮次去重 | _delivered 集合去重 | 无 | 无 | 无 |
| 每文件/全局容量 cap | 10/30 双 cap | 无 | 无 | 无 |
| 闭环修复 | 无需显式调用诊断工具 | 需人工驱动 | 需显式读取 | 需人工驱动 |

## 六、小结

- agent-core 以 LspDiagnosticRegistry 单例为缓冲中枢,publishDiagnostics 自动捕获,无需模型主动拉取。
- LspRail 双钩子(after_tool_call / before_model_call)构成自驱动闭环,实现「编辑-重分析-注入-再编辑」的自动修复循环。
- get_and_clear 的 6 步流水线(合并→批内去重→跨轮次去重→排序→双 cap)在保证诊断可见性的同时严格控制上下文预算。
- 诊断以 UserMessage 注入,LLM 每轮都能看到最新错误,形成无需人工介入的自我纠错能力。
- 这一闭环是 agent-core「工程化智能体」定位的核心体现,显著区别于通用 LLM 工具。
