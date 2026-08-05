# 编码安全控制

> 交叉引用: [01-项目概述](../../01-project-overview.md) | [02-整体架构](../../02-overall-architecture.md) | [04-harness模块](../../04-harness-module.md) | [06-agent_evolving与dev_tools模块](../../06-agent-evolving-and-dev-tools-module.md) | [07-extensions与rsi模块](../../07-extensions-and-rsi-module.md)

## 一、能力概述

agent-core 让 Agent 自主改码与执行命令,意味着它有权限动文件、跑 shell、改代码。若不加约束,一次注入、一次越界写、一次并发覆盖都可能毁掉工作区。为此,harness 层构建了多层防御体系,覆盖"命令执行"与"文件编辑"两条最危险的路径。

命令侧包含三层:Bash 与 PowerShell 各自的 **注入检测**(命令替换/进程替换/动态调用一律阻断)、**破坏性命令警告**(`git reset --hard`/`DROP TABLE` 等不阻断但提醒)、以及 **五层权限管道**(BYPASS→deny→allow→模式校验→AUTO 子命令校验)。文件侧包含七重保障:前置读取强制、stale-write 检测、累积覆盖校验、并发串行化、内容哈希校验、路径沙箱、操作历史审计。再叠加 Harness 级的目录越界检查与人机审批中断 Rail,形成"工具层防御 + Harness 级审批"的双重护城河。

这套防御体系对 Bash 与 PowerShell 采取双引擎设计:两者语法差异大(命令替换符号、动态调用方式都不同),因此各自的注入检测与破坏性命令模式独立维护,但权限管道与文件安全机制共用。这保证跨平台(Windows PowerShell / Unix Bash)的安全基线一致,不会因 shell 不同而出现防护盲区。

核心理念是:**默认最小权限,危险操作必须可审计、可回滚、可中断**。

这套防御不是"事后补救",而是"前置约束":命令在执行前先过注入检测与权限管道,文件在写入前先过读取登记与 stale-write 检测。任何被判定为越界或未授权的操作在到达真实副作用前就被拦截,只有通过全部检查的命令才会真正落地。这种"先查后做"的设计,让 Agent 在拥有改码与执行权限的同时,不会因为一次幻觉或越界调用就毁掉工作区,是 auto-harness 能够无人值守跑端到端改码会话的安全基石。

换言之,安全控制把"可执行"与"应执行"分离:Agent 能力的边界由工具集决定(能做什么),但每次具体调用是否被允许由安全管道决定(该不该做)。这种分离让 Agent 既有足够自由完成任务,又不会越权造成破坏。

## 二、关键类与函数

| 类/函数 | 文件位置 | 说明 |
|---------|---------|------|
| check_injection(Bash) | [_security.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/shell/bash/_security.py#L40) | 检测 backtick/`$()`/`<()`/`()` 进程替换,blocked=True |
| get_destructive_warning(Bash) | [_security.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/shell/bash/_security.py#L54) | 检测 git reset --hard/DROP TABLE 等,仅提醒不阻断 |
| check_injection(PowerShell) | [_security.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/shell/powershell/_security.py#L28) | 检测 Invoke-Expression/iex/-encodedcommand/& 调用/[scriptblock]::create |
| check_permission(Bash) | [_permission.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/shell/bash/_permission.py#L94) | 五层权限管道主入口 |
| _FILE_READ_REGISTRY | [filesystem.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/filesystem.py#L143) | 模块级文件读取状态注册表,read_file 写入、edit/write 消费 |
| _get_file_edit_lock | [filesystem.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/filesystem.py#L39) | per-file asyncio.Lock,串行化 read-modify-write 事务 |
| ExternalDirectoryChecker | [checker.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/security/checker.py#L36) | 检查 workspace 外路径,转调 FileGuardChecker |
| build_permission_interrupt_rail | [factory.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/security/factory.py#L20) | permissions.enabled=True 时构建审批中断 Rail |
| PermissionConfig/PermissionMode | _permission.py | 权限配置与四级模式(AUTO/READ_ONLY/ACCEPT_EDITS/BYPASS) |
| _FILE_EDIT_LOCKS | [filesystem.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/filesystem.py#L35) | per-file WeakValueDictionary 锁池,惰性创建 asyncio.Lock |
| FileGuardChecker | security/file_guard.py | 路径越界 ASK/DENY 评估器,ExternalDirectoryChecker 内部委派 |

## 三、实现机制

### 3.1 命令注入检测

Bash 侧 [check_injection](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/shell/bash/_security.py#L40)(L40-L49)扫描四类注入模式:反引号命令替换、`$()` 命令替换、`<()`/`>()` 进程替换、`()` 子 shell,任一命中即返回 `blocked=True`。这些模式会让静态分析无法预判真实执行内容,因此硬阻断。

之所以硬阻断而非警告,是因为命令替换与进程替换会把"静态可见的命令"变成"运行时才确定的内容",使后续所有权限校验失去意义——权限管道只能检查命令字符串,无法检查被替换进来的动态内容。因此注入检测必须发生在权限管道之前,作为"能否进入权限管道"的前置门槛。

PowerShell 侧 [check_injection](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/shell/powershell/_security.py#L28)(L28-L33)针对 PowerShell 语法特征检测:`Invoke-Expression`/`iex`、嵌套 `-encodedcommand`、动态调用 `&` 操作符、`[scriptblock]::create` 动态构造脚本块,同样 `blocked=True`。

### 3.2 破坏性命令警告(非阻断)

Bash 侧 [get_destructive_warning](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/shell/bash/_security.py#L54)(L54-L68)对 `git reset --hard`、`git push --force`、`git clean -f`、`DROP TABLE`、`TRUNCATE`、`kubectl delete`、`terraform destroy`、`sudo` 等只返回人类可读警告,不阻断执行——警告会进入工具输出让 LLM 意识到风险。PowerShell 侧(L36-L45)对 `Remove-Item -Recurse/-Force`、`Set-Content`、`git reset --hard` 等同理。

之所以"只警告不阻断",是因为这些命令在合理场景下是正当操作(如 `git reset --hard` 用于放弃脏改动、`sudo` 用于提权安装),硬阻断会过度限制 Agent 能力。但通过把警告注入工具输出,LLM 在后续决策时会被提示风险,从而更谨慎地使用或在必要时主动寻求人工确认。这是一种"软约束 + 风险可见"的折中,与注入检测的"硬阻断"形成互补:注入是绝对禁止,破坏性命令是提醒慎用。

### 3.3 五层权限管道

[check_permission](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/shell/bash/_permission.py#L94)(L94-L155)按序执行五层校验:

- **Layer 1 BYPASS**:mode=BYPASS 全放行。
- **Layer 2 deny_patterns**:对每个管道子命令逐一匹配,命中即拒。
- **Layer 3 allow_patterns**:整命令任一模式命中即放行。
- **Layer 4 模式检查**:READ_ONLY 仅放行只读/搜索/列表命令;ACCEPT_EDITS 放行已知安全命令与文件操作命令,未知 base 命令需显式审批。
- **Layer 5 AUTO**:逐子命令校验 base,未知命令在 AUTO 模式下放行(本层为咨询性,实际阻断由 Layer 2 负责)。

四种权限模式(**PermissionMode**)的选择策略如下:**AUTO**(默认)适合实现阶段,未知命令放行以保流畅;**READ_ONLY** 适合调研/审查阶段,仅允许搜索读取列表,杜绝任何写入副作用;**ACCEPT_EDITS** 是"半信任"模式,放行已知安全命令与文件操作,但拦截未知危险命令;**BYPASS** 仅在完全可信的隔离环境(如沙箱 worktree)中使用,全放行。模式可在会话中随阶段切换,实现"调研期收紧、实现期放宽、高危操作人工兜底"的动态管控。安全开关 `OPENJIUWEN_BASH_STRICT=1` 启用工具层 guard([_tool.py:L171-L175](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/shell/bash/_tool.py#L171))。

### 3.4 文件编辑七重保障

EditFileTool/WriteFileTool 围绕 `_FILE_READ_REGISTRY`([filesystem.py:L143](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/filesystem.py#L143))构建七层防护:

1. **前置读取强制**:目标文件必须先被 read_file 读取并登记到注册表,否则拒绝编辑/覆写。
2. **stale-write 检测**:用 mtime_ns + size_bytes 双重检查文件是否在读取后被外部改动(可选内容哈希),防止覆盖他人修改。
3. **累积覆盖校验**(WriteFileTool):全文件覆写前要求已读取区间的并集覆盖全部行,确保 Agent 看过将被覆盖的每一行。
4. **并发串行化**(EditFileTool):per-file asyncio Lock([filesystem.py:L39-L47](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/filesystem.py#L39))串行化 read-modify-write 事务,同一文件的多轮编辑互斥。
5. **内容哈希校验**:写回带 `expected_content_sha256`([filesystem.py:L1645](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/filesystem.py#L1645)),防并发写入冲突。
6. **路径沙箱**:`restrict_to_work_dir` 控制文件操作不越出工作目录。
7. **操作历史**:所有写/编辑/删除记录到 `.agent_history/file_ops_{agent_id}_{session_id}.json`,可审计可恢复。

这七层防护的逻辑链是:第 1-2 层防"盲改"(必须先看再改、不能覆盖外部改动),第 3 层防"覆写未见内容"(全文件覆写须看过每一行),第 4-5 层防"并发冲突"(串行化与哈希校验),第 6 层防"越界"(不出工作目录),第 7 层提供"事后可追溯"(所有操作留痕)。任一层失败都拒绝写入,保证文件副作用始终受控。

### 3.5 Harness 级权限与人机审批

工具层之上,Harness 层叠加目录越界检查与审批中断。[ExternalDirectoryChecker](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/security/checker.py#L36)(L36-L66)检查路径是否越界 workspace,内部转调 FileGuardChecker 评估 ASK/DENY。

[build_permission_interrupt_rail](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/security/factory.py#L20)(L20-L51)在 `permissions.enabled=True` 时构建 PermissionInterruptRail,它拦截工具调用并按 allow/ask/deny 决策;命中 ask 时中断执行流,等待人工审批后再放行或拒绝,实现"危险操作人机共审"。PermissionInterruptRail 支持按工具名与命令模式配置规则,例如对 `bash` 工具的 `rm -rf` 模式设 action=ask,则该命令执行前会挂起 Agent,把决策权交给人。这种"中断执行流"而非"弹窗确认"的设计,让审批天然集成到 Agent 的异步任务流中,无需改造 Agent 主循环即可实现人在回路。

### 3.6 删除追踪

BashTool 执行前解析 `rm` 命令的显式目标,读取被删文件内容并记录(可恢复);PowerShellTool 解析 `Remove-Item` 目标同理。即便文件被删,内容仍留痕于历史,降低误删损失。这一机制与操作历史审计配合,使"删除"不再是不可逆的黑洞,而是"删前留底"的可恢复操作。

需要注意的是,删除追踪只对"显式目标"生效——即命令行参数中明确写出的文件路径。对于通配符(如 `rm *.log`)或由命令动态产生的路径,追踪能力有限,因此权限管道对通配符删除通常会触发破坏性命令警告,提示 LLM 谨慎。

### 3.7 防御层级总览

把上述机制按"调用方向"串起来,一次 Agent 工具调用要穿越的防御链如下:命令类工具先过注入检测(硬阻断)→破坏性命令警告(提醒 LLM)→五层权限管道(按模式分级放行)→Harness 级目录越界检查(ASK/DENY)→人机审批中断(危险操作中断执行流);文件类工具先过前置读取强制(必须先 read)→stale-write 检测(防覆盖外部改动)→累积覆盖校验(WriteFile)或 per-file Lock 串行化(EditFile)→内容哈希校验(防并发冲突)→路径沙箱(防越界)→操作历史审计(可追溯)。任一环节不通过,调用在产生真实副作用前被拦截。

这一防御链的关键特性是"短路":越靠前的检查越便宜(注入检测是正则匹配,极快),越靠后的检查越昂贵(人机审批需等待人工)。把廉价检查前置,能在绝大多数正常调用上快速放行,仅把少数可疑调用推进到昂贵环节,兼顾安全与性能。

## 四、调用示例

```python
import os
from openjiuwen.harness.tools.shell.permission_config import (
    PermissionConfig,
    PermissionMode,
)
from openjiuwen.harness.rails.sys_operation_rail import SysOperationRail

# 1. 启用工具层 bash guard(注入/权限/破坏性命令警告)
os.environ["OPENJIUWEN_BASH_STRICT"] = "1"

# 2. 只读模式:Agent 只能搜索/读取,不能写文件、不能跑破坏性命令
read_only_perm = PermissionConfig(
    mode=PermissionMode.READ_ONLY,
    deny_patterns=[r"git\s+push", r"git\s+reset\s+--hard"],
)

# 3. 注册只读 shell rail,Agent 全程无法改文件
sys_rail = SysOperationRail(read_only=True)

# 4. 人机审批:permissions.enabled=True 时,
#    危险工具调用会中断执行流,等待人工 allow/deny
permissions_config = {
    "enabled": True,
    "rules": [
        {"tool": "bash", "action": "ask", "pattern": r"rm\s+-rf"},
    ],
}
```

上述配置组合体现了分级管控:READ_ONLY 模式让 Agent 在调研阶段只能看不能改;`deny_patterns` 兜底拦截危险 git 操作;`OPENJIUWEN_BASH_STRICT=1` 开启注入检测与权限管道;`permissions.enabled` 把最危险的 `rm -rf` 交给人工审批。在生产实践中,通常会话前期用 READ_ONLY、进入实现阶段切 ACCEPT_EDITS、仅对少数高危操作保留人机审批,在安全与效率间取得平衡。

## 五、业界对比

| 维度 | agent-core | Cursor | Claude Code | GitHub Copilot |
|------|-----------|--------|-------------|----------------|
| 注入检测 | ✅ Bash+PowerShell 双引擎 | ❌ 无 | ✅ Bash only | ❌ 无 |
| 权限模式分级 | ✅ READ_ONLY/ACCEPT_EDITS/AUTO/BYPASS 四级 | ✅ 三级 | ✅ 三级 | ❌ 二级 |
| 破坏性命令警告 | ✅ 不阻断但提醒 LLM | ❌ 无 | ✅ 有 | ❌ 无 |
| read-before-edit 强制 | ✅ 注册表强校验 | ❌ 无 | ✅ 有 | ❌ 无 |
| stale-write 检测 | ✅ mtime+size 双重 | ❌ 无 | ❌ 无 | ❌ 无 |
| 并发串行化 | ✅ per-file asyncio Lock | ❌ 无 | ❌ 无 | ❌ 无 |
| 操作审计 | ✅ file_ops 历史 JSON | ❌ 无 | ✅ 有 | ❌ 无 |
| 人机审批中断 | ✅ PermissionInterruptRail 中断执行流 | ✅ 弹窗确认 | ✅ 交互确认 | ❌ 无 |

> 对比说明:Cursor 与 Claude Code 的安全主要依赖"弹窗/交互确认",本质是人在回路里兜底;agent-core 的差异在于把安全下沉为"工具层前置约束 + Harness 级审批中断"的双重机器防御,即便无人值守(auto-harness)也能靠注入检测、权限管道、read-before-edit 等机器规则拦截大部分风险,仅把最高危操作交人工审批。

## 六、小结

agent-core 的安全控制不是单一开关,而是横跨"命令执行"与"文件编辑"两条路径的多层防御。命令侧的注入检测阻断动态执行、五层权限管道按模式分级放行、破坏性命令警告提醒风险;文件侧的前置读取强制与 stale-write 检测防覆盖、per-file Lock 防并发、内容哈希防冲突、历史审计可追溯;Harness 级的目录越界检查与人机审批中断把最终决策权留给人。

这套体系让 Agent 在"能改代码、能跑命令"的同时,始终处于"最小权限 + 可审计 + 可中断 + 可回滚"的受控状态。它与其他特性文档的关系是:为 [code-editing](code-editing.md) 与 [code-execution](code-execution.md) 提供执行护栏,为 [auto-harness](auto-harness.md) 的无人值守改码会话提供安全底线。没有这套防御,Agent 一次幻觉式的 `rm -rf` 或越界写就足以毁掉整个工作区;有了它,auto-harness 才敢把整条改码→提交→发 PR 链路交给 Agent 自主运行。

从纵深防御视角看,agent-core 的安全是"洋葱式"的:最外层是路径沙箱与目录越界检查(圈定作用范围),中间层是权限管道与 read-before-edit(约束操作类型),内层是注入检测与 stale-write 检测(防绕过与防覆盖),核心层是人机审批中断(兜底高危操作)。每一层都假设前一层可能被绕过,因此层层设防,最终把不可逆风险压缩到只剩"人工确认后执行"这一窄口。理解 coding-security 是理解 agent-core 为何能在"高权限自动化"与"安全可控"之间取得平衡的关键。
