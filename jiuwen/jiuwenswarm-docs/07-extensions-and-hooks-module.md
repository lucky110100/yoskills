# 07 extensions 与 hooks 模块（插件化扩展与钩子事件）

> 交叉引用: [01-项目概述](../01-project-overview.md) | [02-整体架构](../02-overall-architecture.md) | [05-server与cli](../05-server-and-cli-module.md) | [06-symphony](../06-symphony-module.md)

## 一、能力概述

extensions 模块定义了 JiuwenSwarm 的插件化扩展机制，是整个系统对外部能力做"软接入"的统一入口。它由三层组件协同构成：`ExtensionRegistry` 作为进程级单例注册中心，承载 RPC handler、回调框架以及各类扩展注入的能力；`ExtensionLoader` 负责从扩展目录发现 `extension.yaml`/`extension.py`，自动安装依赖并 import 扩展模块；`ExtensionManager` 在更上层统一编排搜索路径、加载、列举与关闭。三者之间是"策略—装载—编排"的递进关系，使得新增一个扩展往往只需要把目录丢进搜索路径即可被自动识别。

钩子事件体系分为两个 scope：`GatewayHookEvents` 覆盖 Gateway 与 AgentServer 之间的交互（`gateway_started/stopped`、`before_chat_request`），`AgentServerHookEvents` 覆盖 AgentServer 内部生命周期（`agent_server_started/stopped`、`memory_before/after_chat`、`before_system_prompt_build`）。两类事件配合四类 Context 对象，让扩展能够"原地"修改会话参数、注入记忆块或覆盖 skill 目录，副作用由 context 显式承载，宿主再读取落地，避免回调直接污染全局状态。`clawee.py` 作为 FaaS 入口在后台线程运行长生命周期事件循环，`symphony/extension.py` 则把 Symphony 的 build/graph/plan 注册为 RPC handler，是扩展接入 RPC 能力的范本。

在 server 侧，`HookExecutor` 统一调度 command hook 与 prompt hook，`UserHookRail` 把用户 hooks 以 Rail 形式注册到 DeepAgent 的执行链上。这样扩展体系（in-process、Python 原生、强类型 Context）与用户 hooks 体系（可子进程、可外部脚本、配置驱动）形成互补：前者追求低延迟与深度集成，后者追求语言无关与易替换。两者共用 `hooks_config.py` 中的事件与匹配器定义，保证行为语义一致。

整体设计哲学是"把可变性与核心解耦"：核心进程只负责调度与读写 context，所有旁路逻辑都通过扩展或 hooks 注入。这样无论是接入新的 RPC 能力（如 Symphony 编排）、改写记忆块、覆盖 skill 目录，还是接入外部脚本做工具调用拦截，都不需要改动核心代码，极大降低了系统的演化成本与耦合风险。

## 二、关键类与函数

| 类/函数 | 文件位置 | 说明 |
| --- | --- | --- |
| ExtensionManager | [manager.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/extensions/manager.py#L56) | 扩展管理器：搜索路径、加载、关闭、列举 |
| load_all_extensions | [manager.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/extensions/manager.py#L79) | 发现并加载全部扩展，容错单扩展失败 |
| GatewayHookEvents | [hook_event.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/extensions/hook_event.py#L4) | Gateway 与 AgentServer 交互事件（scope=gateway）：gateway_started/stopped、before_chat_request |
| AgentServerHookEvents | [hook_event.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/extensions/hook_event.py#L17) | AgentServer 内部事件：agent_server_started/stopped、memory_before/after_chat、before_system_prompt_build |
| ExtensionRegistry | [registry.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/extensions/registry.py#L15) | 单例注册中心：RPC handler、回调、能力注入 |
| register | [registry.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/extensions/registry.py#L102) | 注册同步事件回调（带优先级） |
| trigger | [registry.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/extensions/registry.py#L114) | 异步触发事件，由 context 承载副作用 |
| MemoryHookContext | [hooks_context.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/extensions/hooks_context.py#L8) | 记忆钩子上下文，扩展写入 memory_blocks |
| SystemPromptHookContext | [hooks_context.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/extensions/hooks_context.py#L53) | 系统提示构建钩子，可覆盖 home_dir/skill_dir |
| BaseExtension | [base.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/extensions/sdk/base.py#L15) | 扩展 ABC：抽象 initialize/shutdown，metadata 从 extension.yaml |
| ExtensionLoader | [loader.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/extensions/loader.py#L32) | 发现扩展根、装依赖、import 模块 |
| load_extension | [loader.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/extensions/loader.py#L54) | 加载单个扩展：manifest→依赖→import→register_extensions |
| SymphonyExtension | [extension.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/extensions/symphony/extension.py#L55) | 把 Symphony build/graph/plan 注册为 RPC handler |
| HookExecutor | [executor.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/hooks/executor.py#L32) | 统一调度 command/prompt hook，返回 HookResult(blocking/success/error) |
| HookExecutor._run_command_hook | [executor.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/hooks/executor.py#L60) | command hook（子进程），exit 2=blocking，解析 stdout JSON decision |
| UserHookRail | [user_hook_rail.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/hooks/user_hook_rail.py#L18) | 用户 hooks Rail，priority=60，拦截 before_tool_call/after_tool_call/on_tool_exception/after_invoke |
| HooksConfig | [hooks_config.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/hooks_config.py#L127) | hooks 配置：events dict+HookMatcher，disable_all_hooks，match(event,query) |
| load_hooks_config | [hooks_config.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/hooks_config.py#L165) | 从 config.yaml hooks 段加载 |

## 三、实现机制

### 1. 扩展加载与事件触发流程

扩展加载由 `ExtensionManager.load_all_extensions` 驱动，内部委托给 `ExtensionLoader`，整体流程如下：

1. **发现**：`ExtensionLoader` 遍历搜索路径，识别每个扩展根目录下的 `extension.yaml`（manifest）与 `extension.py`（入口模块）。
2. **装依赖**：根据 manifest 中的依赖声明安装所需包，避免 import 时缺符号。
3. **import**：动态 import `extension.py`，拿到模块级对象。
4. **register_extensions**：调用扩展导出的 `register_extensions` 函数，把 RPC handler、能力注入项注册到 `ExtensionRegistry` 单例。
5. **initialize**：实例化扩展（继承自 `BaseExtension`），调用其 `initialize` 完成自定义启动逻辑；`shutdown` 在关闭阶段被统一调用。

加载阶段对单扩展失败做容错：一个扩展抛错不会中断其它扩展的加载，错误被收集后由 `ExtensionManager` 汇总上报。这一容错策略保证了"一个坏扩展不拖垮整个进程"，是插件化系统稳定性的底线。

事件触发采用"上下文承载副作用"的设计：宿主在关键节点调用 `ExtensionRegistry.trigger(event, context)`，注册器按优先级依次调用回调；回调不直接返回结果，而是把修改写入 `context`（如 `memory_blocks`、覆盖后的 `skill_dir`、注入的会话参数），宿主在 `trigger` 返回后再读取 `context` 的字段落地。这样回调之间天然可组合，且副作用显式可观测。

### 2. 用户 hooks 的双路径

用户 hooks 与扩展体系并行，存在两条执行路径：

- **Rail 路径**：`UserHookRail` 以 `priority=60` 注册到 DeepAgent，拦截 `before_tool_call`/`after_tool_call`/`on_tool_exception`/`after_invoke`。该路径是 in-process、低延迟的，适合需要与工具调用强耦合的拦截。
- **command hook 路径**：`HookExecutor._run_command_hook` 把 hook 作为外部子进程执行，约定 `exit 2 = blocking`，并解析 stdout 的 JSON `decision` 字段得到结构化决策。该路径语言无关，适合用脚本/二进制快速接入。

两条路径的匹配规则统一收敛到 `HooksConfig.match(event, query)`：它基于 `events` dict 与 `HookMatcher`，支持 OR 列表、正则与通配匹配，并受 `disable_all_hooks` 总开关控制。`load_hooks_config` 负责从 `config.yaml` 的 `hooks` 段把这些配置加载为运行时结构。`HookExecutor` 调度后返回 `HookResult`，状态机为 `blocking`/`success`/`error`：blocking 直接中断当前操作，error 默认记录不阻断（具体是否阻断取决于 `decision`）。

### 3. 17 个 hook 事件覆盖

事件体系共覆盖 17 个 hook 事件，按 scope 分流：

- **Gateway 钩子**（`GatewayHookEvents`）：`gateway_started`、`gateway_stopped`、`before_chat_request`，主要服务于 Gateway 与 AgentServer 之间的握手与会话准入。
- **AgentServer 钩子**（`AgentServerHookEvents`）：`agent_server_started`、`agent_server_stopped`、`memory_before_chat`、`memory_after_chat`、`before_system_prompt_build`，覆盖服务生命周期与记忆/提示构建的关键切面。
- **工具级 hook**（用户 hooks 侧）：`PreToolUse`/`PostToolUse`/`Stop` 等工具执行前后的拦截点，由 `UserHookRail` 与 `HookExecutor` 共同调度。

四类 Context（如 `MemoryHookContext`、`SystemPromptHookContext` 等）分别承载不同切面的可变状态，让扩展按需选择关心的钩子，而不是面对一个臃肿的全局 context。

### 4. 优先级与 FaaS 事件循环

回调注册时通过 `register` 的 `priority` 参数声明优先级，`trigger` 内部按优先级从小到大（数值越小越先执行）依次调用。同一事件多个扩展的副作用通过 context 累积：例如多个扩展都在 `memory_before_chat` 注入记忆块，最终 `memory_blocks` 是各扩展写入的并集，宿主一次性读取并拼装进系统提示。

`clawee.py` 作为 FaaS 入口，在后台线程跑一个长生命周期事件循环：它负责接收外部触发（如云端函数调用），把事件桥接到 `ExtensionRegistry.trigger`。这样扩展既能被进程内同步触发，也能被外部异步触发，扩展代码本身无需感知触发来源的差异。`symphony/extension.py` 则示范了"扩展即 RPC 服务"：把 Symphony 的 build/graph/plan 注册为 RPC handler，Agent 可通过 RPC 直接调用编排能力，扩展与 RPC 在此合二为一。

## 四、调用示例

扩展 manifest（`extension.yaml`）：

```yaml
name: symphony
version: "1.0.0"
description: Symphony 编排能力扩展
entry: extension.py
dependencies:
  - networkx>=3.0
capabilities:
  - rpc
  - hooks
```

扩展接入 RPC 的最小范本（参考 `symphony/extension.py`）：

```python
from jiuwenswarm.extensions.sdk.base import BaseExtension
from jiuwenswarm.extensions.registry import ExtensionRegistry

class SymphonyExtension(BaseExtension):
    def initialize(self, registry: ExtensionRegistry) -> None:
        registry.register_rpc("symphony.build", self._rpc_build)
        registry.register_rpc("symphony.graph", self._rpc_graph)
        registry.register_rpc("symphony.plan", self._rpc_plan)

    def _rpc_build(self, params: dict) -> dict:
        return {"graph": self._build(params)}

    def shutdown(self) -> None:
        pass
```

记忆钩子注入记忆块（基于 `MemoryHookContext`）：

```python
from jiuwenswarm.extensions.registry import ExtensionRegistry
from jiuwenswarm.extensions.hook_event import AgentServerHookEvents

async def on_memory_before_chat(ctx) -> None:
    ctx.memory_blocks.append({
        "role": "system",
        "content": "近期偏好：偏好简洁回答",
    })

registry = ExtensionRegistry.get_instance()
registry.register(AgentServerHookEvents.MEMORY_BEFORE_CHAT, on_memory_before_chat, priority=10)
```

系统提示构建钩子覆盖 skill 目录（基于 `SystemPromptHookContext`）：

```python
async def on_before_system_prompt_build(ctx) -> None:
    ctx.skill_dir = "/data/my-skills"   # 原地覆盖 skill 目录
    ctx.home_dir = "/data/agent-home"   # 原地覆盖 home 目录
```

Gateway 钩子拦截 chat 请求（基于 `GatewayHookEvents`）：

```python
async def on_before_chat_request(ctx) -> None:
    if ctx.request.get("unsafe"):
        ctx.block(reason="命中安全策略")   # 原地标记阻断
```

`ExtensionManager` 的加载与列举：

```python
from jiuwenswarm.extensions.manager import ExtensionManager

manager = ExtensionManager(search_paths=["/data/extensions"])
loaded = manager.load_all_extensions()      # 容错加载全部扩展
for ext in manager.list_extensions():
    print(ext.metadata.name, ext.metadata.version)
manager.shutdown()                          # 关闭时统一调用各扩展 shutdown
```

用户 hooks 配置（`config.yaml` 片段）：

```yaml
hooks:
  disable_all_hooks: false
  events:
    PreToolUse:
      - matcher: "Bash"
        hooks:
          - type: command
            command: ["./scripts/guard.sh"]
    PostToolUse:
      - matcher: ".*"
        hooks:
          - type: prompt
            prompt: "记录本次工具调用结果"
```

`HookExecutor._run_command_hook` 的退出码语义：

```text
exit 0  -> success, 继续执行
exit 2  -> blocking, 阻断当前工具调用
其它   -> error, 记录但默认不阻断（取决于 decision）
stdout -> 解析为 JSON {"decision": "block"|"allow"|"warn", "reason": "..."}
```

## 五、业界对比

| 能力维度 | JiuwenSwarm | Claude Code | LangChain | VSCode Extensions |
| --- | --- | --- | --- | --- |
| 扩展模型 | extensions + hooks + RPC 三合一 | hooks 为主，配置驱动 | 回调（Callback）为主 | 插件 + Extension API |
| 事件覆盖 | 17 个事件，Gateway/AgentServer 分流 | 工具级 hooks 为主 | 生命周期回调 | Activation events + API |
| 隔离性 | in-process Context 承载副作用，进程级单例 | 子进程 command hook | 同进程回调 | Extension Host 进程隔离 |
| 热加载 | ExtensionLoader 自动发现+装依赖+import | 配置文件驱动，需重启 | 代码级注册 | 运行时安装/启用 |
| 跨语言能力 | command hook 子进程支持任意语言 | command hook 支持 | 限 Python | 主机 API（ts/js） |
| 来源追溯 | provenance + metadata | 无显式来源 | 无 | 插件 manifest |
| RPC 化 | 扩展可直接注册 RPC handler | 无 | 无 | LSP/自定义协议 |
| 副作用模型 | Context 显式承载，可组合 | 退出码/JSON decision | 返回值 | API 调用 |
| 优先级调度 | register priority 数值排序 | 配置顺序 | 注册顺序 | activation 时机 |

## 六、小结

1. extensions 模块以 `ExtensionRegistry` 单例为核心，`ExtensionLoader`/`ExtensionManager` 形成"发现—装载—编排"递进，扩展只需放进搜索路径即可被自动识别。
2. 钩子事件按 scope 分流为 `GatewayHookEvents` 与 `AgentServerHookEvents`，配合四类 Context 让副作用显式可组合，避免回调直接污染全局状态。
3. 用户 hooks 提供 Rail 与 command 双路径：前者 in-process 低延迟，后者子进程语言无关，统一由 `HooksConfig.match` 做匹配，`HookResult` 状态机决定阻断与否。
4. `clawee.py` 作为 FaaS 入口在后台线程跑长生命周期事件循环，`symphony/extension.py` 是扩展接入 RPC 的范本，体现"扩展即 RPC 服务"。
5. 相比业界单一模型，JiuwenSwarm 把"扩展 + hooks + RPC"三合一，在低延迟集成与跨语言易替换之间取得平衡，并通过 Context 副作用模型保证可组合与可观测。
