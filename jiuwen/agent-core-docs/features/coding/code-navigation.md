# 代码导航与理解

> 交叉引用: [01-项目概述](../../01-project-overview.md) | [02-整体架构](../../02-overall-architecture.md) | [04-harness模块](../../04-harness-module.md) | [08-依赖关系](../../08-dependencies.md)

## 一、能力概述

代码导航与理解能力让 LLM 智能体像人类工程师一样「跳转、查引用、看调用关系、全局搜符号」。agent-core 通过自建 LSP(Language Server Protocol)客户端栈与多引擎代码搜索工具的组合,把静态分析与全文检索统一暴露为可被模型调用的工具,使智能体具备跨越文件、跨越符号边界的语义级理解能力。

该能力由 [LspTool](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/lsp_tool/_tool.py#L24) 暴露 8 项导航操作,底层由 [LSPServerManager](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/core/manager.py#L33) 单例按扩展名懒加载对应语言服务器,并通过 [LSPClient](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/core/client.py#L28) 完成 JSON-RPC 握手与请求。配合 [GrepTool](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/filesystem.py#L1825) 与 [GlobTool](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/filesystem.py#L1677) 的全文检索能力,agent-core 形成了「语义导航 + 文本检索」的双轨理解体系。

值得强调的是,该能力以「按需启动、单实例缓存、状态机自愈」为核心设计:语言服务器只在首次需要时启动,以 (server_id, root) 为键缓存以支持 monorepo 多根场景,实例崩溃后自动重启最多 3 次,ContentModified 错误自动重试,从而在保证功能完整性的同时控制资源开销。

## 二、关键类与函数

| 类/函数 | 文件位置 | 说明 |
|---------|---------|------|
| [LspTool](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/lsp_tool/_tool.py#L24) | _tool.py#L24 | 继承 Tool,invoke 委托 call_lsp_tool,暴露 8 项导航操作 |
| [call_lsp_tool](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/lsp_tool/_tool.py#L125) | _tool.py#L125 | 执行 LSP 操作的核心函数,operation→method 映射见 L380 |
| [build_lsp_tool](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/lsp_tool/_tool.py#L79) | _tool.py#L79 | 构造 LspTool 工具定义 |
| [LSPServerManager](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/core/manager.py#L33) | manager.py#L33 | 单例,懒加载语言服务器,支持 monorepo 多根缓存 |
| [LSPClient](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/core/client.py#L28) | client.py#L28 | JSON-RPC 客户端,完成 initialize 握手与消息收发 |
| [LSPServerInstance](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/core/instance.py#L21) | instance.py#L21 | 服务器状态机 STOPPED/STARTING/RUNNING/ERROR,崩溃自愈 |
| [GrepTool](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/filesystem.py#L1825) | filesystem.py#L1825 | 三引擎自适应代码搜索(ripgrep/Select-String/grep) |
| [GlobTool](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/filesystem.py#L1677) | filesystem.py#L1677 | 文件名 glob 匹配,brace 展开,默认上限 100 |

## 三、实现机制

### 3.1 LSP 8 项导航操作

agent-core 通过 [LspOperation](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/lsp_tool/_tool.py#L125) 枚举暴露 8 项导航能力,每项操作映射到对应的 LSP method,映射关系定义在 [_tool.py#L380-L390](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/lsp_tool/_tool.py#L380):

| 操作 | LSP Method | 说明 |
|------|-----------|------|
| go_to_definition | textDocument/definition | 跳转到符号定义 |
| find_references | textDocument/references | 查找引用,支持 include_declaration |
| document_symbol | textDocument/documentSymbol | 文档符号,支持 hierarchical 与 flat |
| workspace_symbol | workspace/symbol | 工作区全局符号搜索 |
| go_to_implementation | textDocument/implementation | 跳转到接口实现 |
| prepare_call_hierarchy | textDocument/prepareCallHierarchy | 准备调用层级 |
| incoming_calls | callHierarchy/incomingCalls | 先 prepare 再查谁调用了本符号 |
| outgoing_calls | callHierarchy/outgoingCalls | 查本符号调用了哪些目标 |

需要说明的是,LSP 的 completion、hover、formatting、rename、signatureHelp 等能力在 agent-core 中未实现:客户端能力声明见 [client.py#L84-L99](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/core/client.py#L84),未声明这些 capability,故服务器不会推送相关结果。

### 3.2 语言服务器懒加载与 monorepo 支持

[LSPServerManager](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/core/manager.py#L33) 是进程级单例,采用懒加载策略:

1. `get_or_start_server`([manager.py#L177](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/core/manager.py#L177)) 按文件扩展名匹配内置语言服务器配置。
2. 动态 `find_root` 定位项目根(如 pyright 找 pyproject.toml/git 上层)。
3. 以 `(server_id, root)` 为键缓存实例,同一服务器在 monorepo 不同子项目下可各自持有一个实例,避免根目录污染。

文件生命周期管理通过 `open_file`([manager.py#L386](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/core/manager.py#L386)) 发送 didOpen,`change_file`([manager.py#L423](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/core/manager.py#L423)) 发送 didChange,`send_request`([manager.py#L479](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/core/manager.py#L479)) 发起同步请求。

### 3.3 JSON-RPC 握手与状态机自愈

[LSPClient](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/core/client.py#L28) 负责 JSON-RPC 通信:`initialize`([client.py#L72](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/core/client.py#L72)) 完成 initialize→initialized 完整握手,`send_request`([client.py#L130](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/core/client.py#L130)) 同步等待响应,`_read_loop`([client.py#L202](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/core/client.py#L202)) 后台读取推送消息。

[LSPServerInstance](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/core/instance.py#L21) 以状态机管理生命周期:STOPPED → STARTING → RUNNING,异常进入 ERROR。关键容错:崩溃恢复最多 3 次([instance.py#L236](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/core/instance.py#L236));遇到 ContentModified(-32801)错误自动重试([instance.py#L170](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/core/instance.py#L170)),适配编辑过程中导航请求的竞态。

### 3.4 内置 5 语言服务器

| 语言 | 服务器 | 配置位置 |
|------|--------|---------|
| Python | pyright | [python.py#L129](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/servers/servers/python.py#L129) |
| TypeScript/JavaScript | typescript-language-server | [typescript.py#L33](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/servers/servers/typescript.py#L33) |
| Rust | rust-analyzer | [rust.py#L77](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/servers/servers/rust.py#L77) |
| Java | jdtls | [java.py#L24](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/servers/servers/java.py#L24) |
| Go | gopls | [go.py#L33](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/servers/servers/go.py#L33) |

通过 InitializeOptions.custom_servers 可覆盖或扩展自定义语言服务器,支持私有语言或非内置服务器的接入。

### 3.5 三引擎自适应代码搜索

[GrepTool](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/filesystem.py#L1825) 实现三引擎自适应策略,按环境可用性降级选择:

1. ripgrep 优先([filesystem.py#L1904](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/filesystem.py#L1904)):性能最佳,默认尝试。
2. PowerShell Select-String([filesystem.py#L1968](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/filesystem.py#L1968)):Windows 上 rg 缺失时回退。
3. GNU grep([filesystem.py#L2046](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/filesystem.py#L2046)):类 Unix 系统最终回退。

支持 output_mode(content/files_with_matches/count)、-A/-B/-C 上下文行、multiline 跨行匹配、glob/type 过滤,覆盖从「查文件」到「查内容带上下文」的全场景。

[GlobTool](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/filesystem.py#L1677) 实现 brace 展开(如 `{src,tests}/**/*.py`)与默认上限 100 条结果,防止单次匹配返回过多路径撑爆上下文。ListDirTool 则提供目录树浏览能力,三者与 LSP 语义导航形成「精确符号 + 模糊路径 + 全文内容」的互补。

### 3.6 LSP 握手与消息收发细节

[LSPClient](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/core/client.py#L28) 的 JSON-RPC 通信遵循 LSP 规范:`initialize`([client.py#L72](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/core/client.py#L72)) 发送 initialize 请求,服务器返回 capabilities 后客户端回送 initialized 通知,完成完整握手。握手过程中客户端在 [client.py#L84-L99](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/core/client.py#L84) 声明自身能力——由于未声明 hoverProvider、completionProvider 等能力,服务器不会推送相关结果,这也是 agent-core 导航能力聚焦于「理解」而非「补全」的根因。

`send_request`([client.py#L130](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/core/client.py#L130)) 采用同步等待模式,以 request id 关联响应;`_read_loop`([client.py#L202](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/lsp/core/client.py#L202)) 后台持续读取,把服务器主动推送(publishDiagnostics、window/showMessage)分发到对应 handler,实现请求-响应与通知-推送双通道。

### 3.7 符号搜索与调用链工作流

典型的「理解一个函数被谁调用」工作流,组合多项导航操作:

1. `document_symbol` 定位目标函数在文件中的位置。
2. `prepare_call_hierarchy` 取得符号的调用层级句柄。
3. `incoming_calls` 查询所有调用方,逐级展开形成完整上游调用链。
4. 对关键调用方执行 `find_references` 交叉验证引用点。
5. 若需查看实现细节,对接口类型执行 `go_to_implementation` 跳转到具体实现。

这一工作流无需模型人工拼接,LLM 可基于 8 项操作自由编排,体现 agent-core 把 LSP 原语完整暴露给模型的设计取向。

## 四、调用示例

```python
from openjiuwen.harness.tools.lsp_tool._tool import call_lsp_tool

result = call_lsp_tool({
    "operation": "goToDefinition",
    "file_path": "/path/to/main.py",
    "line": 25,
    "character": 10,
})
print(result)
```

通过 Rail 装配 LSP 能力到智能体:

```python
from openjiuwen import create_deep_agent, Runner
from openjiuwen.harness.rails.lsp_rail import LspRail
from openjiuwen.harness.lsp.core.options import InitializeOptions

agent = create_deep_agent(
    model="deepseek-chat",
    card="default",
    workspace="./proj",
    rails=[LspRail(options=InitializeOptions(cwd="/path/to/proj"))],
)

result = Runner.run_agent(
    agent,
    {"query": "分析 utils.py 中 compute 函数的所有调用方,并梳理调用链"},
)
```

## 五、业界对比

| 能力维度 | agent-core | Cursor | Claude Code | GitHub Copilot |
|---------|-----------|--------|-------------|----------------|
| 多语言 LSP 支持 | 5 语言内置 + 自定义扩展 | 主流语言 | 主流语言 | 主流语言 |
| 导航操作种类 | 8 项完整 | 跳转/引用为主 | 跳转/引用为主 | 跳转/引用为主 |
| monorepo 支持 | (server_id, root) 多根缓存 | 有限 | 无显式支持 | 无显式支持 |
| 懒加载 | 按扩展名 + find_root | 编辑器常驻 | 无 LSP | 无 LSP |
| 代码搜索引擎 | rg/Select-String/grep 三引擎 | ripgrep | ripgrep | ripgrep |

## 六、小结

- agent-core 自建 LSP 客户端栈,暴露 8 项导航操作,覆盖定义跳转、引用查找、调用层级等核心语义场景。
- 通过 (server_id, root) 缓存与动态 find_root,原生支持 monorepo 多根场景,避免单一根目录的污染。
- 状态机 + 崩溃恢复 + ContentModified 重试三层容错,保证 LSP 服务的稳定性。
- GrepTool 三引擎自适应策略使代码搜索在 Windows/Linux/macOS 各环境下均可用,体现跨平台工程化考量。
- completion/hover 等交互式 LSP 能力暂未声明,导航能力聚焦于「理解」而非「补全」,定位清晰。
