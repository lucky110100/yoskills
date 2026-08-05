# 代码执行与调试

> 交叉引用: [01-项目概述](../../01-project-overview.md) | [02-整体架构](../../02-overall-architecture.md) | [04-harness模块](../../04-harness-module.md) | [08-依赖关系](../../08-dependencies.md)

## 一、能力概述

代码执行与调试能力让 LLM 智能体不仅能写代码,还能运行代码、执行命令、读取 stderr 与 exit code,并据此迭代修复。这是把「静态编程助手」升级为「动态工程智能体」的分水岭:模型获得了真实环境的反馈信号,从而能验证假设、复现问题、闭环调试。

在 agent-core 中,该能力由两条路径承载:一是 [CodeTool](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/code.py#L14),以语言级抽象执行 Python/JavaScript 代码,支持 LOCAL 与 SANDBOX 两种模式;二是 [BashTool](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/shell/bash/_tool.py#L73) 与 [PowerShellTool](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/shell/powershell/_tool.py#L58),以 shell 级抽象跨平台执行命令。两者底层都委托 [SysOperation](file:///D:/jiuwen/main/agent-core/openjiuwen/core/sys_operation/shell.py#L29) 的统一抽象,保证执行语义一致。

该能力的工程化体现在三方面:exit code 语义化解释(避免把 grep 无匹配误判为错误)、输出截断与持久化策略(防止超大输出撑爆上下文)、删除追踪(rm 前预读内容留痕)。配合 LspRail 的静态诊断,agent-core 形成「静态诊断 + 动态执行」的多源调试反馈闭环。

## 二、关键类与函数

| 类/函数 | 文件位置 | 说明 |
|---------|---------|------|
| [CodeTool](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/code.py#L14) | code.py#L14 | 工具名 "code",参数 code/language/timeout,委托 execute_code,支持 LOCAL/SANDBOX |
| [BaseCodeOperation](file:///D:/jiuwen/main/agent-core/openjiuwen/core/sys_operation/code.py#L11) | core/sys_operation/code.py#L11 | 抽象 execute_code + execute_code_stream |
| [BashTool](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/shell/bash/_tool.py#L73) | shell/bash/_tool.py#L73 | 工具名 "bash",支持 auto/cmd/powershell/bash/sh,sudo 非交互注入,exit code 语义化 |
| [PowerShellTool](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/shell/powershell/_tool.py#L58) | shell/powershell/_tool.py#L58 | 仅 Windows 注册,固定 shell_type="powershell",Remove-Item 预解析 |
| [BaseShellOperation](file:///D:/jiuwen/main/agent-core/openjiuwen/core/sys_operation/shell.py#L29) | core/sys_operation/shell.py#L29 | execute_cmd(同步)/execute_cmd_stream(流式)/execute_cmd_background(后台) |

## 三、实现机制

### 3.1 CodeTool 语言级执行

[CodeTool](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/code.py#L14) 工具名为 "code",接受三个参数:

- `code`:待执行代码字符串
- `language`:python 或 javascript
- `timeout`:超时秒数,默认 300,上限 3600,由 CODE_TOOL_MAX_TIMEOUT_SECONDS 环境变量控制

底层委托 `SysOperation.code().execute_code`,支持 LOCAL(本地进程)与 SANDBOX(沙箱隔离)两种执行模式。抽象接口定义在 [BaseCodeOperation](file:///D:/jiuwen/main/agent-core/openjiuwen/core/sys_operation/code.py#L11),同时提供 `execute_code`(一次性返回)与 `execute_code_stream`(流式输出)两个方法。

### 3.2 BashTool 跨平台 shell 执行

[BashTool](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/shell/bash/_tool.py#L73) 工具名为 "bash",参数定义在 [_BashInputs](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/shell/bash/_tool.py#L60)([shell/bash/_tool.py#L60-L70](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/shell/bash/_tool.py#L60)):command/timeout/workdir/run_in_background/max_output_chars/shell_type/description。

shell 跨平台策略:shell_type 支持 auto(自动探测)/cmd/powershell/bash/sh。auto 模式下按操作系统选择最合适的 shell,使同一工具在 Windows 与 Unix 下均可用。

sudo 非交互化:在 [shell/bash/_tool.py#L52-L54](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/shell/bash/_tool.py#L52) 检测到 sudo 时自动注入 `-n` 参数,避免交互式密码提示阻塞执行。

### 3.3 exit code 语义化解释

BashTool 的 `interpret_exit_code` 对常见命令的 exit code 做语义化解释,避免把「正常无匹配」误判为「执行错误」:

| 命令 | exit code | 语义化解释 |
|------|-----------|-----------|
| grep | 1 | 无匹配,非错误 |
| find | 路径不存在 | 提示路径问题 |
| diff | 1 | 有差异,非错误 |
| test | 1 | 条件不成立,非错误 |

这一设计让 LLM 能正确区分「命令失败」与「命令语义上的空结果」,减少基于误判的无效修复。

### 3.4 输出截断与持久化策略

命令输出超过 max_output_chars(默认 20000)时,BashTool 采用「头 80% + 尾 20%」截断:保留开头与结尾,中间以省略号标记。超大输出额外持久化到临时文件,在返回中给出文件路径,供模型按需读取,避免上下文被单条命令撑爆。

### 3.5 删除追踪

BashTool 在执行 rm 前,会预解析删除目标,读取其内容并记录到操作历史。这一「删除追踪」机制让销毁性操作可回溯,降低误删导致的数据丢失风险。PowerShellTool 对 Remove-Item 同样做预解析处理。

### 3.6 BaseShellOperation 三模式执行

[BaseShellOperation](file:///D:/jiuwen/main/agent-core/openjiuwen/core/sys_operation/shell.py#L29) 提供三种执行模式:

- `execute_cmd`:同步执行,等待返回完整 stdout/stderr/exit_code。
- `execute_cmd_stream`:流式执行,适合长时间命令边跑边输出。
- `execute_cmd_background`:后台执行,立即返回 PID,后续可查询状态。

PowerShellTool([shell/powershell/_tool.py#L58](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/shell/powershell/_tool.py#L58))仅在 Windows 上注册,固定 shell_type="powershell",并对 Remove-Item 做预解析,与 BashTool 形成跨平台互补。

### 3.7 多源调试反馈闭环

agent-core 的调试反馈并非单一来源,而是「静态诊断 + 动态执行」的多源闭环:

```
BashTool/CodeTool 执行
   │
   ▼
输出 stderr / exit_code
   │
   ▼
LLM 据此修复代码
   │
   ▼
配合 LspRail 静态诊断
   │
   ▼
形成多源调试反馈
```

执行错误(运行时)与 LSP 诊断(静态)互补:前者捕获逻辑与运行环境问题,后者捕获类型与语法问题,二者共同驱动模型迭代修复。

## 四、调用示例

直接调用 CodeTool 执行代码片段:

```python
from openjiuwen.harness.tools.code import CodeTool

result = CodeTool.invoke(
    inputs={
        "code": "print(sum(range(1, 101)))",
        "language": "python",
        "timeout": 30,
    }
)
print(result)
```

通过智能体端到端运行测试并修复用例:

```python
from openjiuwen import create_deep_agent, Runner
from openjiuwen.harness.rails.sys_operation_rail import SysOperationRail

agent = create_deep_agent(
    model="deepseek-chat",
    card="default",
    workspace="./proj",
    rails=[SysOperationRail()],
)

result = Runner.run_agent(
    agent,
    {"query": "运行 pytest 并修复所有失败用例"},
)
print(result.final_output)
```

## 五、业界对比

| 能力维度 | agent-core | Cursor | Claude Code | GitHub Copilot |
|---------|-----------|--------|-------------|----------------|
| 多语言执行 | Python/JavaScript | 有限 | Python 为主 | 无 |
| shell 跨平台 | bash/powershell/cmd/sh | 有限 | bash | 无 |
| 后台执行 | execute_cmd_background 返回 PID | 无 | 无 | 无 |
| 流式输出 | execute_cmd_stream | 有 | 有 | 无 |
| exit code 语义化 | grep/find/diff/test 解释 | 无 | 无 | 无 |
| 输出截断策略 | 头 80%+尾 20%+持久化 | 简单截断 | 简单截断 | 无 |
| 超时控制 | 默认 300s/上限 3600s | 编辑器级 | 默认超时 | 无 |
| 沙箱模式 | LOCAL/SANDBOX 双模式 | 无 | 无 | 无 |

## 六、小结

- agent-core 通过 CodeTool 与 BashTool/PowerShellTool 双路径,提供语言级与 shell 级两种代码执行能力。
- exit code 语义化解释(grep/find/diff/test)有效区分「命令失败」与「语义空结果」,减少模型误判。
- 输出截断采用「头 80%+尾 20%+超大输出持久化临时文件」策略,平衡可见性与上下文预算。
- 删除追踪与 sudo 非交互注入体现了对销毁性操作与阻塞场景的工程化防护。
- 配合 LspRail 静态诊断,agent-core 形成「静态诊断 + 动态执行」的多源调试反馈闭环,是工程化智能体的核心体现。
