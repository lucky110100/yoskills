# 代码编辑与文件操作

> 交叉引用: [01-project-overview](../../01-project-overview.md) | [02-overall-architecture](../../02-overall-architecture.md) | [04-harness-and-deepagents-module](../../04-harness-and-deepagents-module.md) | [09-dependencies](../../09-dependencies.md)

## 一、能力概述

代码编辑与文件操作是 agent-core-java 在编码场景下与本地文件系统交互的基础能力。Java 版通过 [FilesystemTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/FilesystemTool.java#L20) 提供四个公共方法：读取文件、全量覆盖写入、列出目录、内容搜索，覆盖了"读—写—列—搜"的最小闭环。

需要如实说明的是：**Java 版的文件编辑能力属于基础设施级，缺少 Python 版 agent-core 的多项安全增强能力**。具体而言，精确字符串替换（`old_string/new_string/replace_all`）未实现，stale-write（陈旧写）保护未实现，read-before-edit（先读后改）强制范式未实现，操作历史审计未实现。多模态读取（行号/PDF/Notebook/图片）亦未实现。

虽然 [EditFileMetadataProvider](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/prompts/sections/tools/EditFileMetadataProvider.java#L24) 向 LLM 声明了 `edit_file` 工具的 JSON Schema，但实际上它只产出元数据声明，**不存在对等的执行类**，即"让 LLM 以为有此工具，但无任何执行逻辑落地"。这导致 LLM 在 Java 版运行时若尝试调用 `edit_file`，将无法真正完成精确替换。

定位上，Java 版 FilesystemTool 的 `writeFile` 是裸写——无 mtime/size 检查、无 stale-write 保护、无操作历史记录。适用于一次性生成文件、原型脚本输出等低风险场景，不适用于在已有大文件上做局部精确修改的正式编码工作流。在大型代码库上让 LLM 反复全量重写整份文件，既消耗 token 又易引入无关改动，工程上不可持续。

## 二、关键类与函数

| 类/函数 | 文件位置 | 说明 |
| --- | --- | --- |
| [FilesystemTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/FilesystemTool.java#L20) | harness/tools/FilesystemTool.java | 文件系统工具聚合类，提供 4 个公共方法 |
| [readFile](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/FilesystemTool.java#L40) | FilesystemTool.java#L40 | 读取文件全文，返回字符串 |
| [writeFile](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/FilesystemTool.java#L57) | FilesystemTool.java#L57 | 全量覆盖写（裸写），无 mtime/size 检查 |
| [listFiles](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/FilesystemTool.java#L75) | FilesystemTool.java#L75 | 列出目录内容 |
| [searchText](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/FilesystemTool.java#L93) | FilesystemTool.java#L93 | 文件内容文本搜索 |
| [EditFileMetadataProvider](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/prompts/sections/tools/EditFileMetadataProvider.java#L24) | prompts/sections/tools/EditFileMetadataProvider.java#L24 | 仅声明 `edit_file` 的 JSON Schema，无执行逻辑 |
| [WriteFileMetadataProvider](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/prompts/sections/tools/WriteFileMetadataProvider.java) | prompts/sections/tools/ | 声明 `write_file` Schema，描述含 stale-write 提示但代码层无强制 |
| [Workspace](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/workspace/Workspace.java#L27) | harness/workspace/Workspace.java#L27 | 工作区抽象，提供 root/getNodePath |

补充验证证据：经 Glob 检索 `**/EditFileTool*.java` 零命中；Grep 检索 `class WriteFileTool|class EditFileTool|editFile\(|strReplace\(` 零命中；Grep 检索 `_FILE_READ_REGISTRY` 零命中；Grep 检索 `agent_history|file_ops_|operation_history` 零命中。以上证据支持"对应能力未实现"的判定，本节不臆造任何不存在的类与方法。

## 三、实现机制

### 3.1 已实现：裸读裸写（基础设施级）

[FilesystemTool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/FilesystemTool.java#L20) 的四个方法构成最小读写闭环。`writeFile` 直接以全量覆盖方式写入目标路径，不读取旧文件、不比较 mtime、不比较 size：

```java
// 伪代码示意（基于源码结构）
public String writeFile(String path, String content) {
    Path target = workspace.resolve(path);
    Files.createDirectories(target.getParent());
    Files.writeString(target, content, StandardCharsets.UTF_8);
    return "ok";
}
```

`readFile` 直接读取全文返回字符串，不做行号标注、不做 PDF/Notebook/图片解析：

```java
// 伪代码示意
public String readFile(String path) {
    Path target = workspace.resolve(path);
    return Files.readString(target, StandardCharsets.UTF_8);
}
```

`listFiles` 与 `searchText` 为轻量遍历方法，分别用于列目录与文本匹配，无索引、无正则引擎自适应。

### 3.2 元数据声明与执行的脱节

工具元数据由 [EditFileMetadataProvider](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/prompts/sections/tools/EditFileMetadataProvider.java#L24) 提供，其 `getName` 返回 `"edit_file"`，并在 L49-66 声明 `file_path/old_string/new_string/replace_all` 参数 Schema：

```java
// EditFileMetadataProvider 关键结构
public String getName() { return "edit_file"; }
public JsonNode getSchema() {
    // file_path: string (required)
    // old_string: string (required)  —— 期望精确匹配
    // new_string: string (required) —— 替换为的内容
    // replace_all: boolean (default false) —— 是否全部替换
}
```

但该类 `implements ToolMetadataProvider`，仅负责向 LLM 描述工具签名，**不包含任何执行体**。当工具派发器根据 LLM 输出的 tool_call 名称查找执行类时，找不到对应的 `EditFileTool`，调用将无法落地。这是元数据声明与执行体脱节的典型形态：LLM "以为"可调用，但运行期无后端。

[WriteFileMetadataProvider](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/prompts/sections/tools/WriteFileMetadataProvider.java) 的描述字符串写有 "Overwrites existing files only after a full read_file call"，但代码层面无任何强制实现，仅为提示性文本，实际 `writeFile` 不校验是否先读过。

### 3.3 未实现：精确字符串替换 / stale-write 保护 / read-before-edit / 操作审计

以下能力在 Java 版中均**未实现**，逐一说明差距：

1. **精确字符串替换（strReplace）**：无 `EditFileTool` 类，无法按 `old_string/new_string/replace_all` 做局部替换。LLM 若需修改文件，只能让 `writeFile` 全量覆盖，必须由 LLM 自行在上下文中拼出整份文件内容，成本高且易出错。Python 版 `EditFileTool` 支持 `replace_all=false` 时要求 `old_string` 唯一匹配、`replace_all=true` 时批量替换，并支持 `old_string` 不存在或多次匹配时的明确错误反馈，Java 版无此能力。

2. **stale-write 保护**：`writeFile` 不检查文件自上次读取以来的 mtime/size 变化。Python 版 `WriteFileTool` 在写入前会比对 mtime 与 size，若文件已被外部进程改动则拒绝写入并提示重读；Java 版无此检查，存在覆盖他人改动的风险，尤其在多 agent 并发或人机协同编辑场景下不安全。

3. **read-before-edit 强制范式**：无 `_FILE_READ_REGISTRY` 机制，不强制"必须先 readFile 才能 edit/write"。Python 版通过该注册表确保 LLM 在修改文件前必须先读取真实内容，防止凭记忆或凭旧快照修改；Java 版无此约束，LLM 可直接覆盖未读过的文件。

4. **操作历史审计**：无 `.agent_history/file_ops_*.json` 持久化记录，无法回溯"谁在何时对哪个文件做了什么操作"，不利于调试与责任追溯。Python 版将每次文件操作（read/write/edit）序列化为 JSON 历史文件，支持回放与回滚。

5. **多模态读取**：`readFile` 仅返回纯文本，不支持行号标注、PDF 解析、Notebook（.ipynb）解析、图片识别。Python 版 `ReadFileTool` 支持上述多模态形态，尤其行号标注是后续精确替换（old_string 唯一匹配）的定位基础。

### 3.4 工具注册与工作区约束

文件工具的注册由 `SysOperationRail`（基于 CodeAgentFactory 引用）统一处理，工具操作均受 [Workspace](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/workspace/Workspace.java#L27) 的 root 与 getNodePath 约束，限制在工作区根目录内，避免越权访问工作区外文件。但工作区约束仅是路径层面的边界检查，不等于上述 stale-write / read-before-edit 等语义级保护。

## 四、调用示例

```java
import com.openjiuwen.harness.tools.FilesystemTool;
import com.openjiuwen.harness.workspace.Workspace;

// 1. 初始化工作区与工具
Workspace workspace = Workspace.of("D:/jiuwen/main/agent-core-java");
FilesystemTool fs = new FilesystemTool(workspace);

// 2. 读取文件（裸读，无行号、无多模态）
String content = fs.readFile(
    "src/main/java/com/openjiuwen/harness/tools/FilesystemTool.java");

// 3. 全量覆盖写（无 stale-write 检查，直接覆盖）
fs.writeFile("docs/notes.txt", "hello world\n");

// 4. 列出目录
List<String> entries = fs.listFiles("src/main/java/com/openjiuwen/harness");

// 5. 内容搜索（简单文本匹配，无正则引擎自适应）
List<String> hits = fs.searchText("writeFile", "src/main/java");
```

> 注意：以下调用在 Java 版中**不可用**（仅为对照说明，运行期无对应实现）：
>
> ```java
> // 精确替换 —— 未实现，无 EditFileTool 类
> // fs.editFile("path", "old_string", "new_string", false);
>
> // stale-write 受控写 —— 未实现，无 mtime/size 检查
> // fs.writeFileWithGuard("path", "content", lastMtime, lastSize);
>
> // read-before-edit 强制 —— 未实现，无 _FILE_READ_REGISTRY
> // fs.assertReadBefore("path");
>
> // 操作历史查询 —— 未实现，无 file_ops_*.json
> // fs.queryHistory("path");
> ```

## 五、业界对比

| 维度 | agent-core-java | Spring AI | LangChain4j | Python agent-core |
| --- | --- | --- | --- | --- |
| 精确字符串替换 | 未实现（仅 Schema 声明，无执行类） | 未实现，需自行实现 | 未实现 | 已实现（EditFileTool，old/new/replace_all） |
| stale-write 检测 | 未实现（裸写无 mtime/size 检查） | 未实现 | 未实现 | 已实现（mtime + size 双重检查） |
| read-before-edit 强制 | 未实现（无 _FILE_READ_REGISTRY） | 未实现 | 未实现 | 已实现（注册表强制先读后改） |
| 操作审计 | 未实现（无 file_ops 历史） | 未实现 | 未实现 | 已实现（.agent_history/file_ops_*.json） |
| 多模态读取 | 未实现（仅纯文本） | 部分实现（依赖文档加载器） | 部分实现 | 已实现（行号/PDF/Notebook/图片） |
| 元数据与执行一致性 | 不一致（EditFileMetadataProvider 声明但无执行类） | 一致 | 一致 | 一致 |

## 六、小结

1. Java 版文件编辑能力为基础设施级，仅 `readFile/writeFile/listFiles/searchText` 四个方法，覆盖"读—写—列—搜"最小闭环。
2. 精确字符串替换（`edit_file`）**未实现**：仅 [EditFileMetadataProvider](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/prompts/sections/tools/EditFileMetadataProvider.java#L24) 声明 Schema，无对等执行类，元数据与执行体脱节。
3. stale-write 保护、read-before-edit 强制、操作历史审计**均未实现**，[writeFile](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/FilesystemTool.java#L57) 为裸写，无 mtime/size 检查。
4. 多模态读取**未实现**，`readFile` 仅返回纯文本，不支持行号/PDF/Notebook/图片。
5. 与 Python 版存在明显能力落差，正式编码工作流建议谨慎使用 Java 版做局部精确修改，或在后续迭代补齐 `EditFileTool`、stale-write 保护与 `_FILE_READ_REGISTRY` 强制范式。
