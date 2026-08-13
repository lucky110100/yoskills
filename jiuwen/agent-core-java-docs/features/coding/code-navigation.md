# 代码导航与理解

> 交叉引用: [01-project-overview](../../01-project-overview.md) | [02-overall-architecture](../../02-overall-architecture.md) | [04-harness-and-deepagents-module](../../04-harness-and-deepagents-module.md) | [09-dependencies](../../09-dependencies.md)

## 一、能力概述

代码导航与理解能力让 agent 能够"看懂代码"——查找定义、引用、符号、实现、调用层次等，是后续编辑与诊断的前提。Java 版通过 [LspTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/LspTool.java#L21) 桥接语言服务器协议（LSP），已实现 8 项导航操作，并通过 [LSPServerManager](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/lsp/core/LSPServerManager.java#L22) 管理多语言服务器生命周期。

如实说明：**LSP 导航 8 项操作已实现，多语言服务器支持已实现；代码搜索为简化版（`searchText`），无 Python 版的三引擎自适应（ripgrep / Select-String / grep）**。具体内置语言服务器清单未在源码中明确枚举，文档中按"参考 Python 版设计，具体清单未深入验证"表述，不臆造具体服务器名称与版本。

定位上，LspRail 以 priority=60 注册，负责创建 LSPServerManager 并暴露 LspTool 元数据；代码搜索则复用 [FilesystemTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/FilesystemTool.java#L20) 的 `searchText/listFiles` 两方法，未提供独立的 GrepTool/GlobTool 类。导航能力是 agent 进行跨文件重构、影响面分析、依赖梳理的"眼睛"，搜索能力则是定位零散符号的补充手段。

## 二、关键类与函数

| 类/函数 | 文件位置 | 说明 |
| --- | --- | --- |
| [LspTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/LspTool.java#L21) | harness/tools/LspTool.java#L21 | LSP 工具入口，invoke 委托 LSPServerManager |
| [LspTool.invoke](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/LspTool.java#L54) | LspTool.java#L54-L80 | 解析参数并调用 LSPServerManager.request |
| [LspOperation](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/lsp/LspOperation.java#L12) | harness/tools/lsp/LspOperation.java#L12 | 枚举 8 项导航操作 |
| [LspToolSupport](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/lsp/LspToolSupport.java) | harness/tools/lsp/LspToolSupport.java | resolvePath/operationToMethod/needsGitignoreFilter/formatResult |
| [LSPServerManager](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/lsp/core/LSPServerManager.java#L22) | harness/lsp/core/LSPServerManager.java#L22 | 服务器生命周期管理 |
| [LSPServerManager.openFile](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/lsp/core/LSPServerManager.java#L230) | LSPServerManager.java#L230 | didOpen 通知 |
| [LSPServerManager.changeFile](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/lsp/core/LSPServerManager.java#L263) | LSPServerManager.java#L263 | didChange 通知 |
| [LSPServerManager.getPendingDiagnostics](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/lsp/core/LSPServerManager.java#L303) | LSPServerManager.java#L303 | 取待处理诊断 |
| [LSPServerManager.ensureDiagnosticHandler](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/lsp/core/LSPServerManager.java#L82) | LSPServerManager.java#L82-L90 | 注册 publishDiagnostics 回调 |
| [LspRail](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/LspRail.java#L22) | harness/rails/LspRail.java#L22 | priority=60，init 创建管理器并注册工具 |
| [LspRail.init](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/LspRail.java#L44) | LspRail.java#L44-L55 | 创建 LSPServerManager + LspTool 注册 |
| [LspRail.describe](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/LspRail.java#L122) | LspRail.java#L122 | 描述："Register and expose LSP code intelligence tool metadata" |
| [FilesystemTool.searchText](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/FilesystemTool.java#L93) | FilesystemTool.java#L93 | 简化版内容搜索 |
| [FilesystemTool.listFiles](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/FilesystemTool.java#L75) | FilesystemTool.java#L75 | 列目录 |

## 三、实现机制

### 3.1 LSP 导航 8 项操作

[LspOperation](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/lsp/LspOperation.java#L12) 枚举定义 8 项导航操作：

```java
public enum LspOperation {
    GO_TO_DEFINITION,        // 跳转定义：定位符号声明处
    FIND_REFERENCES,         // 查找引用：列出所有使用处
    DOCUMENT_SYMBOL,         // 文档符号：当前文件内的符号树
    WORKSPACE_SYMBOL,        // 工作区符号：全工作区符号搜索
    GO_TO_IMPLEMENTATION,    // 跳转实现：接口→实现类
    PREPARE_CALL_HIERARCHY,  // 准备调用层次：选定调用根
    INCOMING_CALLS,          // 入向调用：谁调用了我
    OUTGOING_CALLS           // 出向调用：我调用了谁
}
```

调用链：`LLM tool_call → LspTool.invoke → LSPServerManager.request → LSP 服务器 → 结果格式化`。具体委托过程：

```java
// LspTool.invoke 核心委托（L54-L80 伪结构）
public String invoke(Map<String, Object> args) {
    String path = (String) args.get("path");
    String op   = (String) args.get("operation");
    LspOperation operation = LspOperation.valueOf(op);
    LspToolSupport support = new LspToolSupport(workspace);
    String uri = support.resolvePath(path);          // 路径→file:// URI
    String method = support.operationToMethod(operation);  // 枚举→LSP method
    if (support.needsGitignoreFilter(operation)) {   // 工作区符号等需过滤
        args.put("filterGitignored", true);
    }
    Object result = manager.request(uri, method, args);
    return support.formatResult(result, operation);  // 按 operation 格式化
}
```

[LspToolSupport](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/lsp/LspToolSupport.java) 的四个职责：`resolvePath` 将相对路径转为 `file://` URI；`operationToMethod` 将枚举映射到 LSP method（如 `GO_TO_DEFINITION → textDocument/definition`）；`needsGitignoreFilter` 判断工作区级查询是否需按 gitignore 过滤；`formatResult` 按 operation 类型做差异化格式化输出。

### 3.2 多语言服务器生命周期

[LSPServerManager](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/lsp/core/LSPServerManager.java#L22) 负责服务器的启动、文件同步、请求转发、诊断处理。关键流程：

1. **didOpen**：[openFile](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/lsp/core/LSPServerManager.java#L230)（L230）在首次访问某文件时发送 `textDocument/didOpen`，将文件内容注册到服务器，触发首次分析。
2. **didChange**：[changeFile](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/lsp/core/LSPServerManager.java#L263)（L263）在文件变更后发送 `textDocument/didChange`，触发服务器重分析，使导航结果与最新内容保持一致。
3. **诊断回调**：[ensureDiagnosticHandler](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/lsp/core/LSPServerManager.java#L82)（L82-90）注册 `publishDiagnostics` 回调，将服务器推送的诊断写入注册表（详见 code-diagnostics.md）。
4. **取诊断**：[getPendingDiagnostics](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/lsp/core/LSPServerManager.java#L303)（L303）调用注册表的 `getAndClear`。

> 关于内置语言服务器清单：Python 版明确包含 5 种（pyright / typescript / rust-analyzer / jdtls / gopls）。Java 版参考 Python 版设计，具体内置服务器清单未在源码中明确枚举，**实例管理能力存在，具体状态机细节未深入验证**，此处如实说明，不臆造具体服务器名称与版本。若需确认，建议直接查阅 LSPServerManager 的服务器工厂或注册表实现。

### 3.3 代码搜索（简化版）

代码搜索复用 [FilesystemTool.searchText](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/FilesystemTool.java#L93) 与 [listFiles](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/FilesystemTool.java#L75) 两方法，**未提供独立的 GrepTool / GlobTool 类**。与 Python 版对照：

- Python 版 `GrepTool` 支持三引擎自适应（ripgrep / Select-String / grep），按平台自动选择，支持正则、`-i` 大小写忽略、`output_mode` 三种（content / files_with_matches / count）；
- Python 版 `GlobTool` 支持 brace 展开（`**/*.{ts,tsx}`），按修改时间排序；
- Python 版 `ListDirTool` 独立提供目录树，支持 `max_depth`、ignore 过滤。

Java 版将上述能力简化为 `FilesystemTool` 的两个方法，搜索为简单文本匹配，无正则引擎自适应、无 brace 展开、无 output_mode 切换。在大型代码库上 searchText 的性能与召回均不如专业搜索引擎。

### 3.4 LspRail 注册

[LspRail](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/LspRail.java#L22) 以 priority=60 在 Rail 体系中注册，[init](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/LspRail.java#L44)（L44-55）创建 LSPServerManager 并注册 LspTool，[describe](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/LspRail.java#L122)（L122）描述为 "Register and expose LSP code intelligence tool metadata"。

Rail 优先级为 60，相对文件工具、Bash 工具等属于中优先级，确保导航能力在 agent 启动时优先就绪。但需注意：LspRail 职责聚焦于工具元数据暴露与生命周期管理，**未参与诊断自动闭环**（即不重写 beforeToolCall/afterToolCall/beforeModelCall），详见 code-diagnostics.md。

## 四、调用示例

```java
import com.openjiuwen.harness.tools.LspTool;
import com.openjiuwen.harness.tools.lsp.LspOperation;
import com.openjiuwen.harness.lsp.core.LSPServerManager;
import com.openjiuwen.harness.tools.FilesystemTool;
import com.openjiuwen.harness.workspace.Workspace;

// 1. 初始化
Workspace workspace = Workspace.of("D:/jiuwen/main/agent-core-java");
LSPServerManager manager = new LSPServerManager(workspace);
LspTool lsp = new LspTool(manager, workspace);

// 2. 跳转定义（GO_TO_DEFINITION）
Map<String, Object> defArgs = new HashMap<>();
defArgs.put("path", "src/main/java/com/openjiuwen/harness/tools/LspTool.java");
defArgs.put("operation", "GO_TO_DEFINITION");
defArgs.put("line", 54);
defArgs.put("character", 10);
String defResult = lsp.invoke(defArgs);

// 3. 查找引用（FIND_REFERENCES）
Map<String, Object> refArgs = new HashMap<>();
refArgs.put("path", "src/main/java/com/openjiuwen/harness/tools/LspTool.java");
refArgs.put("operation", "FIND_REFERENCES");
String refResult = lsp.invoke(refArgs);

// 4. 工作区符号（WORKSPACE_SYMBOL）
Map<String, Object> symArgs = new HashMap<>();
symArgs.put("operation", "WORKSPACE_SYMBOL");
symArgs.put("query", "LspTool");
String symResult = lsp.invoke(symArgs);

// 5. 调用层次（PREPARE_CALL_HIERARCHY → INCOMING_CALLS）
Map<String, Object> prepArgs = new HashMap<>();
prepArgs.put("path", "src/main/java/com/openjiuwen/harness/tools/LspTool.java");
prepArgs.put("operation", "PREPARE_CALL_HIERARCHY");
String prepResult = lsp.invoke(prepArgs);

// 6. 简化版内容搜索（无独立 GrepTool，无三引擎自适应）
FilesystemTool fs = new FilesystemTool(workspace);
List<String> hits = fs.searchText("LspOperation", "src/main/java");
```

> 以下能力**未实现**（对照说明，不可调用）：
>
> ```java
> // 三引擎自适应 grep —— 未实现，无独立 GrepTool
> // grep.invoke(Map.of("pattern", ".*", "output_mode", "content"));
>
> // brace 展开 glob —— 未实现，无独立 GlobTool
> // glob.invoke(Map.of("pattern", "**/*.{ts,tsx}"));
> ```

## 五、业界对比

| 维度 | agent-core-java | Spring AI | LangChain4j | Python agent-core |
| --- | --- | --- | --- | --- |
| LSP 操作种类 | 8 项（定义/引用/文档符号/工作区符号/实现/调用层次3种） | 未内置 LSP | 未内置 LSP | 8 项（对齐） |
| 多语言服务器 | 已实现（参考 Python 设计，具体清单未枚举） | 未内置 | 未内置 | 5 种（pyright/ts/rust-analyzer/jdtls/gopls） |
| monorepo 支持 | 部分实现（Workspace root 约束） | 未内置 | 未内置 | 已实现 |
| 代码搜索引擎 | 简化版（searchText，无三引擎自适应） | 未内置 | 依赖外部 | 三引擎自适应（ripgrep/Select-String/grep） |
| 调用层次 | 已实现（prepare/incoming/outgoing） | 未内置 | 未内置 | 已实现 |
| 符号查询格式化 | 已实现（LspToolSupport.formatResult 差异化） | 未内置 | 未内置 | 已实现 |

## 六、小结

1. LSP 导航 8 项操作（定义/引用/符号/实现/调用层次）**已实现**，经 [LspTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/LspTool.java#L21) 委托 [LSPServerManager](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/lsp/core/LSPServerManager.java#L22) 完成，[LspToolSupport](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/lsp/LspToolSupport.java) 提供路径解析与结果格式化。
2. 多语言服务器生命周期**已实现**：didOpen/didChange/publishDiagnostics 回调齐全；具体内置服务器清单未在源码明确枚举，不臆造，需进一步查阅服务器工厂确认。
3. 代码搜索为**简化版**，复用 [FilesystemTool.searchText](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/FilesystemTool.java#L93) / [listFiles](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/FilesystemTool.java#L75)，无独立 GrepTool/GlobTool，无三引擎自适应、无 brace 展开、无 output_mode 切换。
4. [LspRail](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/LspRail.java#L22) 以 priority=60 注册，职责聚焦于工具元数据暴露与生命周期管理，不参与诊断自动闭环。
5. 与 Python 版相比，导航能力对齐，搜索能力简化；建议后续补齐独立 GrepTool/GlobTool 与三引擎自适应，并明确内置语言服务器清单。
