# 代码执行与调试

> 交叉引用: [01-project-overview](../../01-project-overview.md) | [02-overall-architecture](../../02-overall-architecture.md) | [04-harness-and-deepagents-module](../../04-harness-and-deepagents-module.md) | [09-dependencies](../../09-dependencies.md)

## 一、能力概述

代码执行与调试能力让 agent 能够运行命令、执行代码片段、验证行为，并在过程中对风险操作做检测与告警。Java 版通过 [BashTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/BashTool.java#L26)、[CodeTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/CodeTool.java#L25)、[PowerShellTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/PowerShellTool.java) 三类工具实现多语言执行。

如实说明：**多语言执行已实现，含注入检测与破坏性警告**。具体能力包括：

- [BashTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/BashTool.java#L26) 执行 bash 命令，含 `checkInjection` 注入检测与 `getDestructiveWarning` 破坏性警告；
- [CodeTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/CodeTool.java#L25) 支持 python/bash/sh，含跨平台 python 可执行文件解析；
- [PowerShellTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/PowerShellTool.java) 提供 Windows PowerShell 执行；
- `permissionMode` 字段支持 `"auto"` / `"read_only"`，read-only 模式下通过 `looksLikeWrite` 拦截写操作。

与 Python 版对照，Java 版缺少以下能力：后台执行（run_in_background）、流式输出（execute_cmd_stream）、输出截断策略（头 80% + 尾 20% + 持久化临时文件）、删除追踪、独立沙箱模式（沙箱在 extensions/sys_operation/sandbox/ 是独立模块，不在工具内）。文档中如实标注差距，不臆造。

定位上，BashTool 是 agent 执行系统的"手脚"，配合注入检测与破坏性警告构成最小安全边界，适用于脚本运行、构建验证、临时调试等场景。

## 二、关键类与函数

| 类/函数 | 文件位置 | 说明 |
| --- | --- | --- |
| [BashTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/BashTool.java#L26) | harness/tools/BashTool.java#L26 | Bash 命令执行工具 |
| [BashTool.invoke](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/BashTool.java#L58) | BashTool.java#L58-L120 | 主执行入口 |
| [BashTool.checkInjection](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/BashTool.java#L129) | BashTool.java#L129-L140 | 注入检测（命令替换/进程替换） |
| [BashTool.getDestructiveWarning](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/BashTool.java#L149) | BashTool.java#L149-L167 | 破坏性命令告警（不阻止） |
| [BashTool.permissionMode](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/BashTool.java#L44) | BashTool.java#L44-L46 | 权限模式字段（auto/read_only） |
| [BashTool.looksLikeWrite](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/BashTool.java#L66) | BashTool.java#L66-L68 | read-only 模式下写操作检查 |
| [CodeTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/CodeTool.java#L25) | harness/tools/CodeTool.java#L25 | 多语言代码片段执行（python/bash/sh） |
| [PowerShellTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/PowerShellTool.java) | harness/tools/PowerShellTool.java | Windows PowerShell 执行 |

## 三、实现机制

### 3.1 BashTool 主执行流程

[BashTool.invoke](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/BashTool.java#L58)（L58-120）的主流程：

```
invoke(args)
  ├─ 解析 command / workdir / timeout
  ├─ checkInjection(command)            # 注入检测，命中则 blocked
  ├─ looksLikeWrite(command)            # read-only 模式下拦截
  ├─ getDestructiveWarning(command)     # 破坏性告警，返回提示不阻止
  ├─ ProcessBuilder.start(...)          # 执行
  └─ 收集 stdout/stderr/exitCode 返回
```

### 3.2 注入检测 checkInjection

[BashTool.checkInjection](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/BashTool.java#L129)（L129-140）检测 shell 注入模式，命中即阻止：

```java
// 伪结构
private InjectionResult checkInjection(String command) {
    // backtick 命令替换：`...`        → blocked
    // $() 命令替换：$(...)           → blocked
    // <() / >() 进程替换             → blocked
    // 命中任一即返回 InjectionResult.blocked(reason)
    // 否则返回 InjectionResult.ok()
}
```

设计意图：阻止 LLM 通过命令替换隐式执行任意命令链，避免绕过审批链。

### 3.3 破坏性警告 getDestructiveWarning

[BashTool.getDestructiveWarning](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/BashTool.java#L149)（L149-167）检测破坏性命令，返回警告提示但**不阻止执行**：

```java
// 伪结构
private String getDestructiveWarning(String command) {
    if (command.matches(".*git\\s+reset\\s+--hard.*"))   return "WARNING: git reset --hard will discard local changes.";
    if (command.matches(".*git\\s+push\\s+--force.*"))   return "WARNING: git push --force may overwrite remote history.";
    if (command.matches(".*drop\\s+table.*"))            return "WARNING: destructive SQL detected.";
    if (command.matches(".*terraform\\s+destroy.*"))      return "WARNING: terraform destroy will delete resources.";
    if (command.matches(".*sudo.*"))                     return "WARNING: sudo elevates privileges.";
    return null;  // 无警告
}
```

设计语义：注入检测是"硬阻止"（blocked），破坏性警告是"软提醒"（warning 不阻止），二者分层。

### 3.4 权限模式 permissionMode

[BashTool.permissionMode](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/BashTool.java#L44)（L44-46）字段取值 `"auto"` 或 `"read_only"`：

```java
// 伪结构
public class BashTool {
    private String permissionMode = "auto";  // L44-L46
    // L66-L68
    private boolean looksLikeWrite(String command) {
        // 检测 rm / mv / > / >> / chmod / chown 等写特征
    }
    // auto 模式：直接执行；read_only 模式：looksLikeWrite 命中则拒绝
}
```

read-only 模式用于"只读分析"场景，防止 agent 误改环境。

### 3.5 CodeTool 与 PowerShellTool

[CodeTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/CodeTool.java#L25)（L25）支持 `python/bash/sh` 三种语言，并做跨平台 python 可执行文件解析（如 Windows 下查找 `python.exe` / `py.exe`）：

```java
// 伪结构
public class CodeTool {
    public String invoke(Map<String, Object> args) {
        String lang = (String) args.get("language");
        String code = (String) args.get("code");
        switch (lang) {
            case "python": return runPython(code);   // 跨平台解析 python 可执行文件
            case "bash":   return runBash(code);
            case "sh":     return runSh(code);
            default: throw new IllegalArgumentException("unsupported: " + lang);
        }
    }
}
```

[PowerShellTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/PowerShellTool.java) 提供 Windows PowerShell 执行能力，适配 Windows 环境。

### 3.6 与 Python 版对照（差距如实说明）

Python 版相关能力（Java 版未实现）：

- `BashTool._BashInputs`：timeout/workdir/run_in_background/max_output_chars/shell_type 等丰富参数；
- `BaseShellOperation`：`execute_cmd` / `execute_cmd_stream`（流式）/ `execute_cmd_background`（后台）；
- `CodeTool`：Python/JS，LOCAL/SANDBOX 双模式；
- `interpret_exit_code`：语义化退出码解释；
- 输出截断：头 80% + 尾 20% + 持久化临时文件；
- 删除追踪：记录被删除文件以便回滚。

Java 版上述**均未实现**：无后台执行、无流式输出、无输出截断策略、无删除追踪、无工具内沙箱（沙箱在 extensions/sys_operation/sandbox/ 是独立模块，不在 BashTool/CodeTool 内）。

## 四、调用示例

```java
import com.openjiuwen.harness.tools.BashTool;
import com.openjiuwen.harness.tools.CodeTool;
import com.openjiuwen.harness.tools.PowerShellTool;
import com.openjiuwen.harness.workspace.Workspace;

// 1. Bash 执行
Workspace workspace = Workspace.of("D:/jiuwen/main/agent-core-java");
BashTool bash = new BashTool(workspace);

Map<String, Object> bashArgs = new HashMap<>();
bashArgs.put("command", "mvn -q -pl agent-core-java compile");
bashArgs.put("workdir", "D:/jiuwen/main");
bashArgs.put("timeout", 120);
String result = bash.invoke(bashArgs);  // 含注入检测 + 破坏性警告 + 执行

// 2. read-only 模式（阻止写操作）
BashTool roBash = new BashTool(workspace);
// roBash.setPermissionMode("read_only");
// roBash.invoke(...);  // looksLikeWrite 命中则拒绝

// 3. CodeTool 执行 Python
CodeTool code = new CodeTool(workspace);
Map<String, Object> codeArgs = new HashMap<>();
codeArgs.put("language", "python");
codeArgs.put("code", "print(sum(range(10)))");
String codeResult = code.invoke(codeArgs);

// 4. PowerShell 执行（Windows）
PowerShellTool pwsh = new PowerShellTool(workspace);
Map<String, Object> pwshArgs = new HashMap<>();
pwshArgs.put("command", "Get-ChildItem -Path . -Filter *.java | Measure-Object");
String pwshResult = pwsh.invoke(pwshArgs);
```

> 以下能力**未实现**（对照说明，不可调用）：
>
> ```java
> // 后台执行 —— 未实现
> // bash.invoke(Map.of("command", "...", "run_in_background", true));
>
> // 流式输出 —— 未实现
> // bash.invokeStream(args, lineConsumer);
>
> // 沙箱模式（工具内） —— 未实现（沙箱为独立模块）
> // code.invoke(Map.of("language", "python", "code", "...", "mode", "SANDBOX"));
>
> // 输出截断 —— 未实现
> // 截断策略需外部自行实现
> ```

## 五、业界对比

| 维度 | agent-core-java | Spring AI | LangChain4j | Python agent-core |
| --- | --- | --- | --- | --- |
| 多语言执行 | 已实现（python/bash/sh + PowerShell） | 部分（CodeInterpreter） | 部分（Python/JS 执行器） | 已实现（Python/JS，LOCAL/SANDBOX 双模式） |
| shell 跨平台 | 已实现（Bash + PowerShell 双适配） | 未内置 | 未内置 | 已实现（shell_type 自适应） |
| 注入检测 | 已实现（backtick/$()/进程替换） | 未内置 | 未内置 | 已实现 |
| 破坏性警告 | 已实现（git reset --hard/push --force/drop table/terraform destroy/sudo） | 未内置 | 未内置 | 已实现 |
| 后台执行 | 未实现 | 未内置 | 未内置 | 已实现（run_in_background） |
| 流式输出 | 未实现 | 部分 | 未内置 | 已实现（execute_cmd_stream） |
| 沙箱模式 | 未实现（工具内无；沙箱为独立模块 extensions/sys_operation/sandbox/） | 部分（Docker） | 未内置 | 已实现（SANDBOX 模式） |

## 六、小结

1. 多语言执行**已实现**：[BashTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/BashTool.java#L26) + [CodeTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/CodeTool.java#L25) + [PowerShellTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/PowerShellTool.java)，覆盖 bash/python/sh/PowerShell。
2. 注入检测**已实现**：[checkInjection](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/BashTool.java#L129) 检测 backtick/$()/进程替换并硬阻止。
3. 破坏性警告**已实现**：[getDestructiveWarning](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/BashTool.java#L149) 检测 git reset --hard / push --force / drop table / terraform destroy / sudo 等并软提醒。
4. 权限模式**已实现**：[permissionMode](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/BashTool.java#L44) 支持 auto/read_only，read-only 模式下 [looksLikeWrite](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/BashTool.java#L66) 拦截写操作。
5. 与 Python 版对照，**未实现**后台执行、流式输出、输出截断、删除追踪、工具内沙箱（沙箱为独立模块），差距如实标注，建议后续补齐。
