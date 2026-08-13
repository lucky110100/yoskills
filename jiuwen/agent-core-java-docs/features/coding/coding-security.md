# 编码安全控制

> 交叉引用: [01-project-overview](../../01-project-overview.md) | [02-overall-architecture](../../02-overall-architecture.md) | [04-harness-and-deepagents-module](../../04-harness-and-deepagents-module.md) | [06-agentevolving-and-autoharness-module](../../06-agentevolving-and-autoharness-module.md)

## 一、能力概述

编码安全控制指智能体在执行 Shell 命令、读写文件、调用工具时,对注入风险、破坏性操作、权限边界、并发写冲突等所做的检测与约束,目的是防止模型误操作造成不可逆损害。

**实现状态:部分实现。** agent-core-java 提供的是一套**3 层权限简化版**安全控制:

- **已实现**:Shell 注入检测、破坏性命令警告(仅提醒不阻止)、3 层权限枚举(ALLOW/ASK/DENY)与人机审批中断、`read_only` 权限模式。
- **未实现**:文件 stale-write 保护、read-before-edit 强制、操作历史审计、5 层权限管道。

经源码核验:

- `FilesystemTool.writeFile` 为裸写,**无** mtime_ns/size 双重检查(无 stale-write 保护);Grep `_FILE_READ_REGISTRY|readBeforeEdit` 零命中(无 read-before-edit 强制);Grep `agent_history|file_ops_` 零命中(无操作审计)。
- Java 版将 Python 的 5 层权限管道简化为 3 层枚举;`OPENJIUWEN_BASH_STRICT` 环境变量在 Java 源码零命中(仅 Python 版有该开关)。
- 无独立的 PowerShell `_security.py`(Python 版有 shell/bash 与 shell/powershell 双套注入检测)。

本章如实区分"已实现"与"未实现"两部分。

## 二、关键类与函数

| 类/函数 | 职责 | 位置 |
| --- | --- | --- |
| PermissionLevel | 3 层权限枚举:ALLOW/ASK/DENY | [PermissionLevel.java#L14](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/security/PermissionLevel.java#L14) |
| PermissionEngine | 权限引擎,按配置决策工具权限 | [PermissionEngine.java#L16](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/security/PermissionEngine.java#L16) |
| evaluateGlobalPolicyDirectly | 全局策略直评:enabled=false→ALLOW;查 tools[toolName];否则 defaults["*"] | [PermissionEngine.java#L40](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/security/PermissionEngine.java#L40) |
| checkPermission | 返回权限级别与是否需审批 | [PermissionEngine.java#L63](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/security/PermissionEngine.java#L63) |
| BashTool | Shell 工具,含注入检测与破坏性警告 | [BashTool.java#L44](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/BashTool.java#L44) |
| BashTool 构造器 | 接受 permissionMode("auto"/"read_only") | [BashTool.java#L44](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/BashTool.java#L44) |
| BashTool.checkInjection | 检测 backtick/$()/<() 命令替换→blocked | [BashTool.java#L129](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/BashTool.java#L129) |
| BashTool.getDestructiveWarning | 破坏性命令仅警告不阻止 | [BashTool.java#L149](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/BashTool.java#L149) |
| BashTool.looksLikeWrite | read_only 模式下判定写操作 | [BashTool.java#L66](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/BashTool.java#L66) |
| PermissionInterruptRail | 权限中断 Rail,ASK 时中断等待用户 | [PermissionInterruptRail.java#L28](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/security/PermissionInterruptRail.java#L28) |
| PermissionInterruptRail.resolveInterrupt | ALLOW→approve/DENY→reject/ASK→interrupt | [PermissionInterruptRail.java#L58](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/security/PermissionInterruptRail.java#L58) |
| BaseInterruptRail | 中断 Rail 抽象基类 | [BaseInterruptRail.java#L27](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/interrupt/BaseInterruptRail.java#L27) |
| FilesystemTool.writeFile | 裸写文件,无 stale-write 检查 | [FilesystemTool.java#L57](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/FilesystemTool.java#L57) |

## 三、实现机制

### 3.1 已实现:3 层权限、注入检测、破坏性警告、read-only 模式

#### 3.1.1 3 层权限枚举与策略决策

[PermissionLevel](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/security/PermissionLevel.java#L14) 是简化版枚举,仅 `ALLOW`、`ASK`、`DENY` 三态(对照 Python 5 层管道)。决策由 [PermissionEngine](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/security/PermissionEngine.java#L16) 完成:[evaluateGlobalPolicyDirectly](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/security/PermissionEngine.java#L40) 先判断 `config.enabled`,为 `false` 时直接返回 `ALLOW`(策略关闭即放行);再查 `config.tools[toolName]` 的显式规则;最后回退 `config.defaults["*"]`(默认 allow)。[checkPermission](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/security/PermissionEngine.java#L63) 在其上叠加 `needsApproval = (level == ASK)` 标记。`PermissionLevel.fromValue` 把配置中的字符串(如 `"allow"`/`"ask"`/`"deny"`)归一化为枚举,缺省返回 `ALLOW`。

#### 3.1.2 人机审批中断

[PermissionInterruptRail](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/security/PermissionInterruptRail.java#L28) 继承 [BaseInterruptRail](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/interrupt/BaseInterruptRail.java#L27),在 [resolveInterrupt](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/security/PermissionInterruptRail.java#L58) 中按权限级别分流:`ALLOW` 直接 `approve`;`DENY` 直接 `reject`;`ASK` 抛出中断请求(携带 `tool_name`、`matched_rule` 上下文),挂起当前工具调用并等待用户裁决,用户可 approve 或 reject 后恢复执行。构造器会从 `engine.getConfig().tools` 收集键集,自动登记到 Rail 的拦截工具名集合中。

#### 3.1.3 Shell 注入检测

[BashTool.checkInjection](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/BashTool.java#L129) 在执行前检测三类命令替换:反引号 `` ` ``、`$()`、`<()` 进程替换,命中任一即返回 `blocked` 并中止执行。`invoke` 在调用流程开头先做注入检查,再做 read-only 判定。注:Java 版仅此一套检测,**无独立 PowerShell `_security.py`**(Python 版有 shell/bash 与 shell/powershell 双套)。

#### 3.1.4 破坏性命令警告(仅提醒不阻止)

[BashTool.getDestructiveWarning](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/BashTool.java#L149) 对 `git reset --hard`、`git push --force`/`git push -f`、`git commit --amend`、`drop table`/`truncate table`、`terraform destroy` 返回提醒文案,仅作为输出中的 `destructive_warning` 字段返回,**不阻止执行**。另需说明:Python 版对照提及的 `sudo` 检测在 Java 版源码中**未实现**(`getDestructiveWarning` 无 `sudo` 分支)。

#### 3.1.5 read-only 权限模式

[BashTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/BashTool.java#L44) 构造器接受 `permissionMode`,取值 `"auto"` 或 `"read_only"`。`read_only` 模式下,[looksLikeWrite](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/BashTool.java#L66) 判定为写操作的命令将被直接拦截并返回错误。此外 `SecurityRail` 在 autoharness 场景下强制只读,`ExploreAgentFactory`/`PlanAgentFactory` 通过 metadata 的 `forbidden_operations` 声明禁止操作清单。

#### 3.1.6 invoke 执行流程

[BashTool.invoke](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/BashTool.java#L58) 的执行流程为:空命令检查 → [checkInjection](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/BashTool.java#L129) 注入拦截 → `read_only` 写操作拦截 → workdir 存在性校验 → 以 `bash -lc` 启动子进程;后台模式下立即返回 pid,前台模式下并发读取 stdout/stderr,再按 `exitCode == 0 || isNonErrorExit` 判定成功。输出 payload 含 `stdout`/`stderr`/`exit_code`/`return_code_interpretation`/`no_output_expected`/`destructive_warning` 等字段;`maxOutputChars` 被钳制在 200–20000 区间(缺省 8000)后用于截断输出。这一流程把注入检测与破坏性警告嵌入执行链,但并未引入额外的并发写串行化。

### 3.2 未实现:stale-write、read-before-edit、操作审计、5 层管道

#### 3.2.1 无 stale-write 保护

[FilesystemTool.writeFile](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/FilesystemTool.java#L57) 为裸写:解析路径、建父目录、`Files.writeString` 落盘即返回,**无** mtime_ns/size 双重检查。对照 Python `WriteFileTool` 在写入前比对文件上次读取时的 mtime 与 size,若不一致(文件被外部改动)则拒绝覆盖,避免"读到旧内容、覆盖新内容"的竞态。Java 版无此机制。

#### 3.2.2 无 read-before-edit 强制

Grep `_FILE_READ_REGISTRY|readBeforeEdit|staleWrite|mtimeNs` 在源码零命中,不存在"编辑前必须先读取"的注册与校验。对照 Python `EditFileTool` 强制要求目标文件在当前会话已被读取过,否则拒绝编辑,防止盲改。Java 版无此约束,文件可在未被读取的情况下被直接写入。

#### 3.2.3 无操作历史审计

Grep `agent_history|file_ops_|operationAudit` 零命中,不存在操作历史落盘。对照 Python 将文件操作记录写入 `.agent_history/file_ops_*.json` 以供事后追溯。Java 版无审计产物,工具调用一旦执行即无持久化痕迹。

#### 3.2.4 无 5 层权限管道与 4 种 PermissionMode

Python 版权限为 5 层管道(BYPASS/deny_patterns/allow_patterns/READ_ONLY|ACCEPT_EDITS/AUTO)且区分 4 种 PermissionMode(AUTO/READ_ONLY/ACCEPT_EDITS/BYPASS),并配合 per-file asyncio Lock 串行化写入。Java 版简化为 [PermissionLevel](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/security/PermissionLevel.java#L14) 3 层枚举与 `auto`/`read_only` 两档模式,无 deny/allow 正则模式管道、无 ACCEPT_EDITS/BYPASS 档位、无 per-file 并发串行化锁。

#### 3.2.5 无 OPENJIUWEN_BASH_STRICT 开关

`OPENJIUWEN_BASH_STRICT` 环境变量在 Java 源码零命中,Java 版未提供该严格模式开关(仅 Python 版有)。Java 版 Shell 严格度由 `permissionMode` 与注入检测共同决定,不存在通过环境变量提升严格档位的旁路。

综合来看,已实现项集中在 Shell 层(注入拦截、破坏性提醒、权限审批、只读模式),文件层(stale-write、read-before-edit、审计)与权限细粒度(5 层管道、4 种 PermissionMode、per-file 锁)均缺失,使用时需在外部补强。换言之,Java 版当前更像"命令执行护栏"而非"文件操作护栏",对 Git 仓库的不可逆写操作保护主要依赖使用方约束与外部版本控制。

## 四、调用示例

```java
import com.openjiuwen.harness.tools.BashTool;
import com.openjiuwen.harness.security.PermissionEngine;
import com.openjiuwen.harness.rails.security.PermissionInterruptRail;

import java.nio.file.Path;
import java.util.Map;

BashTool bash = new BashTool("read_only");
var out = bash.invoke("rm -rf build", null, false, 8000);
System.out.println(out.isSuccess() ? "ok" : "blocked: " + out.getError());

BashTool.InjectionCheck injection = BashTool.checkInjection("echo $(whoami)");
System.out.println("injection blocked: " + injection.isBlocked());

String warning = BashTool.getDestructiveWarning("git push --force origin main");
System.out.println("warning: " + warning);

Map<String, Object> policy = Map.of(
        "enabled", true,
        "tools", Map.of("BashTool", "ask"),
        "defaults", Map.of("*", "allow"));
PermissionEngine engine = new PermissionEngine(policy, Path.of("/repo"));
var decision = engine.checkPermission("BashTool", Map.of());
System.out.println("level=" + decision.getPermission() + " needsApproval=" + decision.isNeedsApproval());

PermissionInterruptRail rail = new PermissionInterruptRail(engine, null);
```

> 注:`read_only` 模式下写命令被拦截;注入命令被 blocked;破坏性命令仅返回警告仍可能执行;ASK 权限的工具会经 `PermissionInterruptRail` 中断等待用户。stale-write、read-before-edit、操作审计等未实现项无对应 API,文件写入不会做 mtime/size 校验也不落审计记录。

> 配置项要点:权限策略 `Map` 的 `enabled` 为 `true` 才会执行规则匹配,为 `false` 时一律返回 `ALLOW`(便于在受控环境快速关闭);`tools` 按工具名精细配置 `allow`/`ask`/`deny`;未在 `tools` 中显式列出的工具回退到 `defaults["*"]`,缺省值为 `allow`。`BashTool` 的 `permissionMode` 与权限引擎相互独立,前者控制 Shell 写操作拦截,后者控制是否需要人机审批,二者可叠加使用。

> 可观测性:`BashTool.invoke` 的输出 payload 含 `exit_code`/`return_code_interpretation`/`no_output_expected`/`destructive_warning` 等字段,可据此判断命令是否成功、退出码语义及是否为破坏性命令;但缺乏持久化审计,这些字段仅在调用返回时可见,不留存历史。

## 五、业界对比

| 维度 | agent-core-java | Spring AI | LangChain4j | Python agent-core |
| --- | --- | --- | --- | --- |
| 注入检测 | 已实现,backtick/$()/<() | 无内置 | 无内置 | 已实现,bash+powershell 双套 |
| 权限模式分级 | 部分,3 层枚举 + 2 档模式 | 无内置 | 无内置 | 已实现,5 层管道 + 4 种 PermissionMode |
| 破坏性命令警告 | 已实现,仅提醒不阻止 | 无 | 无 | 已实现,含 sudo |
| read-before-edit 强制 | 未实现 | 无 | 无 | 已实现,EditFileTool |
| stale-write 检测 | 未实现,裸写 | 无 | 无 | 已实现,mtime+size 双重检查 |
| 并发串行化 | 未实现,无 per-file 锁 | 无 | 无 | 已实现,per-file asyncio Lock |
| 操作审计 | 未实现,无 agent_history | 无 | 无 | 已实现,.agent_history/file_ops_*.json |
| 人机审批中断 | 已实现,PermissionInterruptRail | 无 | 无 | 已实现,ASK 中断 |

> 对比说明:Spring AI 与 LangChain4j 不内置 Agent 级安全控制,需由使用方在工具实现中自行加固;agent-core-java 在命令注入与权限审批上具备基础能力,但文件层安全(stale-write/read-before-edit/审计)与细粒度权限管道均不及 Python 版完整。

> 使用边界:`auto` 模式仅做注入拦截与破坏性提醒,文件写入不做校验,适合可信工作目录下以只读为主的场景;`read_only` 模式可阻断 Shell 写命令,但无法拦截 `FilesystemTool` 的裸写。对不可信代码或多人并发改写的场景,缺乏 stale-write 与 per-file 串行化会带来覆盖竞态风险,应优先依赖外部 Git 保护或单线程约束。

> 演进建议:补齐与 Python 版对等需引入 5 层权限管道(BYPASS/deny/allow/READ_ONLY|ACCEPT_EDITS/AUTO)与 4 种 PermissionMode,为 `FilesystemTool` 增加 mtime/size 双重检查与 read-before-edit 注册,落地 `.agent_history` 操作审计,并提供 `OPENJIUWEN_BASH_STRICT` 严格模式开关;在此之前,高安全要求场景应以只读模式配合外部版本控制为默认。

## 六、小结

agent-core-java 的编码安全控制处于"部分实现"状态:已实现的部分覆盖了 Shell 注入检测、破坏性命令提醒、3 层权限(ALLOW/ASK/DENY)与人机审批中断、`read_only` 权限模式,足以在常见场景下拦截命令注入与写误操作并请求人工裁决。但对照 Python 版,文件层安全明显薄弱——[FilesystemTool.writeFile](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/FilesystemTool.java#L57) 裸写无 stale-write 保护、无 read-before-edit 强制、无操作历史审计,权限管道也由 5 层简化为 3 层、缺少 ACCEPT_EDITS/BYPASS 档位与 per-file 串行化锁,且未提供 `OPENJIUWEN_BASH_STRICT` 严格模式开关。若对文件写入安全与可追溯性要求较高,当前 Java 版尚不足以与 Python 版对等,需后续补齐 stale-write 检测、read-before-edit 注册、操作审计落盘与细粒度权限管道。
