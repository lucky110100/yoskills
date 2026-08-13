# 代码诊断与自动修复闭环

> 交叉引用: [01-project-overview](../../01-project-overview.md) | [02-overall-architecture](../../02-overall-architecture.md) | [04-harness-and-deepagents-module](../../04-harness-and-deepagents-module.md) | [09-dependencies](../../09-dependencies.md)

## 一、能力概述

代码诊断与自动修复闭环，指 agent 在编辑文件后自动触发语言服务器重分析、捕获诊断（错误/警告）、并将诊断注入下一轮 LLM 上下文，从而形成"改—析—注入—再改"的自动修复循环。这是让 agent 具备"自我纠错"能力的关键设计。

如实说明：**Java 版仅实现底层基础设施，自动闭环未接通**。具体而言，[LspDiagnosticRegistry](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/lsp/core/LspDiagnosticRegistry.java#L17) 缓存、didChange 通知、getAndClear 取诊断等底层能力均已存在，但缺少 Python 版 LspRail 的双钩子机制：

- 缺少 `after_tool_call` 钩子：编辑/写入文件后不会自动触发 `changeFile`（didChange）；
- 缺少 `before_model_call` 钩子：不会自动取出诊断并格式化为 UserMessage 注入 LLM 上下文。

定位上，Java 版 [LspRail](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/LspRail.java#L22) 全文仅 124 行，只重写 `priority/init/uninit/toolName/isRegistered/hasActiveManager/getManager/describe`，**未重写任何 before/after 钩子**，因此诊断只能"手动调用、一次性取出"，无法形成跨轮次的自动修复闭环。

## 二、关键类与函数

| 类/函数 | 文件位置 | 说明 |
| --- | --- | --- |
| [LspDiagnosticRegistry](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/lsp/core/LspDiagnosticRegistry.java#L17) | harness/lsp/core/LspDiagnosticRegistry.java#L17 | 诊断缓存注册表（单例） |
| [LspDiagnosticRegistry.register](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/lsp/core/LspDiagnosticRegistry.java#L62) | LspDiagnosticRegistry.java#L62 | register(serverName, uri, diagnostics)，缓存诊断通知 |
| [LspDiagnosticRegistry.getAndClear](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/lsp/core/LspDiagnosticRegistry.java#L77) | LspDiagnosticRegistry.java#L77 | 取出并清空诊断（一次性） |
| [LSPServerManager](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/lsp/core/LSPServerManager.java#L22) | harness/lsp/core/LSPServerManager.java#L22 | 服务器生命周期管理 |
| [LSPServerManager.ensureDiagnosticHandler](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/lsp/core/LSPServerManager.java#L82) | LSPServerManager.java#L82-L90 | 注册 publishDiagnostics 回调，写入 registry |
| [LSPServerManager.openFile](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/lsp/core/LSPServerManager.java#L230) | LSPServerManager.java#L230 | didOpen 通知 |
| [LSPServerManager.changeFile](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/lsp/core/LSPServerManager.java#L263) | LSPServerManager.java#L263 | didChange 通知（重分析触发点） |
| [LSPServerManager.getPendingDiagnostics](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/lsp/core/LSPServerManager.java#L303) | LSPServerManager.java#L303 | 调用 getAndClear 取诊断 |
| [LspTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/LspTool.java#L54) | harness/tools/LspTool.java#L54-L80 | 只做定义/引用/符号查询，不触发 changeFile、不取诊断 |
| [LspRail](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/LspRail.java#L22) | harness/rails/LspRail.java#L22 | priority=60，未重写 before/after 钩子 |

## 三、实现机制

### 3.1 已实现：底层基础设施（LspDiagnosticRegistry / didChange / getAndClear）

#### 3.1.1 诊断注册表

[LspDiagnosticRegistry](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/lsp/core/LspDiagnosticRegistry.java#L17) 为单例注册表，核心两方法：

```java
// 伪结构
public class LspDiagnosticRegistry {
    private static final LspDiagnosticRegistry INSTANCE = new LspDiagnosticRegistry();
    private final Map<String, List<Diagnostic>> cache = new ConcurrentHashMap<>();

    // L62: 服务器推送诊断时调用，缓存
    public void register(String serverName, String uri, List<Diagnostic> diagnostics) {
        cache.compute(uri, (k, v) -> diagnostics);  // 覆盖式缓存
    }

    // L77: 消费方取出并清空
    public List<Diagnostic> getAndClear(String uri) {
        return cache.remove(uri);
    }
}
```

注意 `getAndClear` 为"取出即清空"语义，即诊断只能消费一次。

#### 3.1.2 诊断推送回调

[LSPServerManager.ensureDiagnosticHandler](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/lsp/core/LSPServerManager.java#L82)（L82-90）在服务器启动时注册 `textDocument/publishDiagnostics` 回调，服务器推送诊断后写入 registry：

```java
// L82-L90 伪结构
private void ensureDiagnosticHandler(LSPServerInstance server) {
    server.onPublishDiagnostics((uri, diagnostics) -> {
        LspDiagnosticRegistry.getInstance()
            .register(server.getName(), uri, diagnostics);
    });
}
```

#### 3.1.3 文件变更与取诊断

- [openFile](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/lsp/core/LSPServerManager.java#L230)（L230）发送 didOpen，触发首次分析。
- [changeFile](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/lsp/core/LSPServerManager.java#L263)（L263）发送 didChange，触发重分析。
- [getPendingDiagnostics](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/lsp/core/LSPServerManager.java#L303)（L303）调用 `registry.getAndClear(uri)` 取出诊断。

### 3.2 未接通的自动闭环（双钩子缺失）

**关键缺口**：经 Grep 验证，`changeFile`、`getPendingDiagnostics`、`LspDiagnosticRegistry.getInstance` 只在 [LSPServerManager](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/lsp/core/LSPServerManager.java#L22) 自身定义处和测试文件中被调用，**无任何 Rail 在 `afterToolCall` 触发 `changeFile`，也无任何 Rail 在 `beforeModelCall` 取诊断注入 LLM 上下文**。

[LspRail](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/LspRail.java#L22) 全文 124 行，仅重写以下方法：

```java
public class LspRail extends BaseRail {
    public int priority() { return 60; }            // L44
    public void init(...) { /* 创建 manager + 注册 LspTool */ }  // L44-L55
    public void uninit(...) { ... }
    public String toolName() { return "lsp"; }
    public boolean isRegistered(...) { ... }
    public boolean hasActiveManager() { ... }
    public LSPServerManager getManager() { ... }
    public String describe() {
        return "Register and expose LSP code intelligence tool metadata";  // L122
    }
    // 缺失：未重写 beforeToolCall / afterToolCall / beforeModelCall / afterModelCall
}
```

[LspTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/LspTool.java#L54)（L54-80）只做 definition/references/symbols 查询，既不调用 `changeFile`，也不取诊断。

#### 与 Python 版双钩子对照

Python 版 LspRail 实现完整闭环：

```python
# Python 版（对照）
def after_tool_call(self, tool_name, result, agent_state):
    if tool_name in ("edit_file", "write_file"):
        path = result["path"]
        self.manager.changeFile(path, new_content)         # 触发重分析
        # 异步等待 publishDiagnostics → registry.register

def before_model_call(self, agent_state):
    pending = self.registry.get_and_clear_all()             # L327 取诊断
    if pending:
        msg = self._format_diagnostics(pending)             # L384 格式化
        agent_state.messages.append(UserMessage(msg))        # 注入 LLM
```

- `after_tool_call`（L263）：检测 edit_file/write_file → 异步触发 didChange → pyright 重分析 → publishDiagnostics → registry 缓存。
- `before_model_call`（L327）：取诊断 → `_format_diagnostics`（L384）格式化为 UserMessage → 注入 messages。

**Java 版上述两钩子均未实现**，因此无法自动跨轮次把诊断反馈给 LLM。

### 3.3 数据流（当前手动形态）

当前 Java 版的诊断使用是"手动、一次性"形态，数据流如下：

```
外部调用方
  ├─ manager.openFile(path)        # didOpen → 首次分析
  ├─ (外部自行修改文件)
  ├─ manager.changeFile(path, new) # didChange → 重分析
  ├─ (服务器推送 publishDiagnostics)
  │     └─ registry.register(uri, diags)
  └─ manager.getPendingDiagnostics(path)  # 取出并清空
```

不存在"工具调用后自动 didChange → 下一轮自动注入"的自动闭环。

## 四、调用示例

```java
import com.openjiuwen.harness.lsp.core.LSPServerManager;
import com.openjiuwen.harness.lsp.core.LspDiagnosticRegistry;
import com.openjiuwen.harness.workspace.Workspace;

// 1. 初始化（基础设施存在）
Workspace workspace = Workspace.of("D:/jiuwen/main/agent-core-java");
LSPServerManager manager = new LSPServerManager(workspace);

// 2. 打开文件（didOpen，触发首次分析）
manager.openFile("src/main/java/com/openjiuwen/harness/tools/LspTool.java");

// 3. 手动变更文件内容后，手动触发 didChange（重分析）
manager.changeFile("src/main/java/com/openjiuwen/harness/tools/LspTool.java", newContent);

// 4. 手动取出诊断（取出即清空）
List<Diagnostic> diags = manager.getPendingDiagnostics(
    "src/main/java/com/openjiuwen/harness/tools/LspTool.java");

// 5. 手动格式化并拼入下一次请求 prompt（需自行实现，框架不自动注入）
```

> 以下自动闭环能力**未实现**（对照说明，不可调用）：
>
> ```java
> // afterToolCall 自动触发 didChange —— 未实现
> // rail.afterToolCall("edit_file", result, agentState);
>
> // beforeModelCall 自动注入诊断 —— 未实现
> // rail.beforeModelCall(agentState);
> ```

## 五、业界对比

| 维度 | agent-core-java | Spring AI | LangChain4j | Python agent-core |
| --- | --- | --- | --- | --- |
| 诊断自动捕获 | 已实现（publishDiagnostics → registry） | 未内置 | 未内置 | 已实现 |
| 编辑后自动重分析 | 未实现（需手动 changeFile，无 afterToolCall 钩子） | 未内置 | 未内置 | 已实现（after_tool_call L263 触发 didChange） |
| 诊断注入 LLM | 未实现（无 beforeModelCall 注入） | 未内置 | 未内置 | 已实现（before_model_call L327 + _format_diagnostics L384） |
| 跨轮次去重 | 部分（getAndClear 取出即清空，无显式去重） | 未内置 | 未内置 | 已实现 |
| 自动修复闭环 | 未接通（底层齐全，双钩子缺失） | 未内置 | 未内置 | 已实现（完整闭环） |

## 六、小结

1. 底层基础设施**已实现**：[LspDiagnosticRegistry](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/lsp/core/LspDiagnosticRegistry.java#L17) 的 register/getAndClear、didChange 通知、publishDiagnostics 回调齐全。
2. 自动闭环**未接通**：[LspRail](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/LspRail.java#L22) 未重写 beforeToolCall/afterToolCall/beforeModelCall/afterModelCall，无编辑后自动 didChange、无下一轮自动注入。
3. [LspTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/LspTool.java#L54) 只做导航查询，不参与诊断流程。
4. 当前诊断使用形态为"手动、一次性"：需外部自行调用 openFile/changeFile/getPendingDiagnostics。
5. 与 Python 版存在能力落差，建议后续在 LspRail 中补齐双钩子，接通自动修复闭环。
