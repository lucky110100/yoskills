# agent 模块

> 交叉引用: [01-项目概述](01-project-overview.md) | [02-整体架构](02-overall-architecture.md) | [04-tools 模块](04-tools-module.md) | [05-gateway 模块](05-gateway-module.md)

## 一、模块概述

agent/ 是 Hermes Agent 的运行时心脏，承担对话编排、provider 适配、上下文治理、内存召回、错误恢复与可观测性六大职责。目录采用扁平结构，约 60 个 `.py` 文件平铺在 `agent/` 下，不设子包——每个文件对应一个专职能力域（对话循环、上下文引擎、内存管理、错误分类、限流守卫、凭证池、紧急停止等），便于按文件名直接定位实现。

模块顶层门面是 [AIAgent](file:///D:\yaodh\main\hermes-agent\agent\run_agent.py#L412)，该类体量约 12k 行，但绝大多数方法体是"转发器"——把调用委托给 `agent/` 内的专职模块（构造委托给 `agent_init`，对话委托给 `conversation_loop`，工具调度委托给 `model_tools` 等）。这种"瘦门面 + 转发器"风格让上层调用方只面对一个对象，而真正的业务逻辑分散在可测试的专职文件中。

agent/ 同时定义了两条可插拔抽象基类线：上下文引擎（ContextEngine）与内存提供者（MemoryProvider），由 MemoryManager 作为编排器组合内置实现与至多一个外部 provider。配合退避重试、错误分类、紧急停止 sentinel 等机制，agent/ 构成了一个"在 LLM 不可靠的前提下仍能稳定跑完一轮对话"的韧性运行时。

## 二、关键类与函数

| 类/函数 | 文件位置 | 说明 |
|---|---|---|
| [AIAgent](file:///D:\yaodh\main\hermes-agent\agent\run_agent.py#L412) | agent/run_agent.py | 门面类，`__init__` 转发到 agent_init.init_agent，方法体多为转发器 |
| [run_conversation](file:///D:\yaodh\main\hermes-agent\agent\conversation_loop.py#L1435) | agent/conversation_loop.py | 真正的对话循环：prologue→while 迭代→API 调用→工具执行→finalizer |
| [_perform_api_call](file:///D:\yaodh\main\hermes-agent\agent\conversation_loop.py#L2699) | agent/conversation_loop.py | 单次 LLM 调用闭包，按 api_mode 分流到不同 provider |
| [ContextEngine](file:///D:\yaodh\main\hermes-agent\agent\context_engine.py#L89) | agent/context_engine.py | 上下文引擎抽象基类 |
| [MemoryProvider](file:///D:\yaodh\main\hermes-agent\agent\memory_provider.py#L81) | agent/memory_provider.py | 内存提供者抽象基类 |
| [MemoryManager](file:///D:\yaodh\main\hermes-agent\agent\memory_manager.py#L364) | agent/memory_manager.py | 编排内置内存 + 至多一个外部 provider |
| [build_prompt_cache_plan](file:///D:\yaodh\main\hermes-agent\agent\prompt_caching.py#L385) | agent/prompt_caching.py | Anthropic cache-control 区段构建 |
| [FailoverReason/ClassifiedError](file:///D:\yaodh\main\hermes-agent\agent\error_classifier.py#L24) | agent/error_classifier.py | 错误原因枚举 + 恢复提示 |
| [classify_api_error](file:///D:\yaodh\main\hermes-agent\agent\error_classifier.py#L639) | agent/error_classifier.py | 错误分类总入口 |
| [jittered_backoff/parse_retry_after_seconds](file:///D:\yaodh\main\hermes-agent\agent\retry_utils.py#L38) | agent/retry_utils.py | 退避核心：抖动退避 + Retry-After 解析 |
| [CredentialPool](file:///D:\yaodh\main\hermes-agent\agent\credential_pool.py#L633) | agent/credential_pool.py | 凭证池，多 key 轮转 |
| [record_nous_rate_limit](file:///D:\yaodh\main\hermes-agent\agent\nous_rate_guard.py#L71) | agent/nous_rate_guard.py | 跨会话限流记录 |
| [engage/is_engaged/check_paused](file:///D:\yaodh\main\hermes-agent\agent\estop.py#L74) | agent/estop.py | 紧急停止 sentinel 文件 |
| [IterationBudget](file:///D:\yaodh\main\hermes-agent\agent\iteration_budget.py#L17) | agent/iteration_budget.py | 线程安全迭代计数器（parent 500 / subagent 50, refund） |
| [call_converse/normalize_converse_response](file:///D:\yaodh\main\hermes-agent\agent\bedrock_adapter.py#L1092) | agent/bedrock_adapter.py | Bedrock Converse 适配 |
| [run_codex_app_server_turn](file:///D:\yaodh\main\hermes-agent\agent\codex_runtime.py#L677) | agent/codex_runtime.py | Codex App-Server 单轮 |
| [call_llm](file:///D:\yaodh\main\hermes-agent\agent\auxiliary_client.py#L8888) | agent/auxiliary_client.py | 辅助 LLM 调用统一入口 |
| [run_curator_review](file:///D:\yaodh\main\hermes-agent\agent\curator.py#L1496) | agent/curator.py | 技能维护审查 |
| [build_learning_graph](file:///D:\yaodh\main\hermes-agent\agent\learning_graph.py#L254) | agent/learning_graph.py | 学习图谱构建 |
| [redact_sensitive_text](file:///D:\yaodh\main\hermes-agent\agent\redact.py#L773) | agent/redact.py | 多模式文本脱敏 |

## 三、实现机制

### 3.1 门面 + 转发器

AIAgent 是瘦门面，构造时把初始化委托给 `agent_init.init_agent`，运行时把对话委托给 `conversation_loop.run_conversation`。上层（gateway）只持有一个 AIAgent 实例，不必感知内部模块拆分：

```python
class AIAgent:
    def __init__(self, config, ...):
        # 转发到专职初始化模块
        agent_init.init_agent(self, config, ...)

    async def run(self, messages, ...):
        # 转发到对话循环
        return await conversation_loop.run_conversation(self, messages, ...)
```

这样 12k 行的方法体大多是薄转发，真正的可测试逻辑落在 `conversation_loop`、`context_engine` 等独立文件中，单文件可独立单测、可独立替换。

### 3.2 ABC + 编排器（策略模式）

上下文与内存采用"抽象基类 + 编排器"双线。ContextEngine(ABC) 把压缩算法（compress）与上下文选择（select_context）定义为可独立替换的策略接口；MemoryProvider(ABC) 定义外部内存召回契约；MemoryManager 作为编排器，组合内置内存实现与至多一个外部 provider，对上屏蔽来源差异：

```python
class ContextEngine(ABC):
    @abstractmethod
    def compress(self, history, budget): ...

    @abstractmethod
    def select_context(self, turn, memories): ...

class MemoryManager:
    def __init__(self, builtin, external: MemoryProvider | None):
        self._builtin = builtin
        self._external = external  # 至多一个

    async def recall(self, query):
        local = await self._builtin.recall(query)
        if self._external:
            remote = await self._external.recall(query)
            return self._merge(local, remote)
        return local
```

compress 与 select_context 解耦意味着：换一种压缩算法（如从摘要式换成分块式）不必动选择逻辑，反之亦然。

### 3.3 退避 + 分类恢复

错误处理把"原因"与"恢复动作"分离。classify_api_error 产出 ClassifiedError（含 FailoverReason 枚举），retry_utils 据此决定退避时长与是否换路。恢复动作由 reason 驱动：RATE_LIMIT 走退避重试，AUTH 走凭证池换 key，SERVER 触发 failover 到备用 provider：

```python
class ClassifiedError:
    reason: FailoverReason        # 例：RATE_LIMIT / AUTH / SERVER / NETWORK
    retry_after: float | None
    recover_hint: str

def jittered_backoff(attempt, base=1.0, cap=60.0):
    # 指数 + 全随机抖动，避免惊群
    delay = min(cap, base * (2 ** attempt))
    return random.uniform(0, delay)

def parse_retry_after_seconds(value: str | None) -> float | None:
    # 解析 HTTP Retry-After 头（秒数或 HTTP 日期）
    ...
```

### 3.4 Fail-Safe 紧急停止

estop.py 用 sentinel 文件实现紧急停止。engage() 创建标记文件，is_engaged() 检查存在性。关键点是 Fail-Safe 语义：当检查本身抛 OSError（权限/磁盘），is_engaged 返回 True 而非 False，宁可停也不要在失控时继续跑：

```python
def engage():
    _SENTINEL.touch()

def is_engaged() -> bool:
    try:
        return _SENTINEL.exists()
    except OSError:
        return True  # Fail-Safe：查不动就当作已停

def check_paused():
    if is_engaged():
        raise EStopEngaged("emergency stop sentinel present")
```

### 3.5 迭代预算与凭证池

IterationBudget 是线程安全计数器，parent 500 / subagent 50，支持 refund（工具回滚返还额度），防止子代理无限递归耗尽资源。CredentialPool 管理多 key 轮转，AUTH 错误时换下一个 key，配合 nous_rate_guard 的跨会话限流记录，把限流状态持久到进程边界之外。

### 3.6 provider 适配分流

_perform_api_call 按 api_mode 把单次 LLM 调用分流到三路：native（OpenAI 直连）、bedrock（call_converse + normalize_converse_response 把 Converse 响应归一）、codex（run_codex_app_server_turn 跑 Codex App-Server）。三路对上层暴露同一返回结构，使对话循环不感知 provider 差异。辅助任务（非对话流，如标题生成、curator 审查）统一走 call_llm，避免复用对话流的迭代预算与上下文装配。

### 3.7 prompt 缓存与脱敏

build_prompt_cache_plan 为 Anthropic provider 构造 cache_control 区段，把稳定前缀（系统提示、工具 schema、固定 few-shot）标记为可缓存，降低重复 prompt 的 token 成本。redact_sensitive_text 在响应入库与对外输出前做多模式脱敏（密钥、令牌、PII），与脱敏并列的还有 curator 的 run_curator_review（技能维护审查）与 build_learning_graph（学习图谱），三者共同构成"运行时自我维护"侧线。

### 3.8 数据流

一轮对话的数据流如下：

```
用户消息
  └─ run_conversation                      # prologue 预处理
       └─ build_turn_context                # 组装本轮上下文（含召回）
            └─ while iteration_budget.consume()
                 ├─ check_paused()           # estop sentinel 守卫
                 ├─ build_prompt_cache_plan  # Anthropic cache-control 区段
                 ├─ _perform_api_call        # 按 api_mode 分流
                 │    ├─ native (OpenAI)
                 │    ├─ bedrock (call_converse)
                 │    └─ codex (run_codex_app_server_turn)
                 ├─ 响应校验 + redact_sensitive_text
                 └─ _execute_tool_calls      # 工具执行（见 04-tools-module）
            └─ finalizer                     # 循环收尾
```

## 四、调用示例

### 4.1 跑一轮对话

```python
agent = AIAgent(config=cfg, profile="default")

result = await agent.run(
    messages=[{"role": "user", "content": "总结今天的会议纪要"}],
    session_id="sess-001",
)
```

### 4.2 辅助 LLM 调用（非对话流）

```python
from agent.auxiliary_client import call_llm

resp = await call_llm(
    prompt="为以下文本生成标题：...",
    model="auxiliary",
    max_tokens=64,
)
```

### 4.3 触发紧急停止

```python
from agent import estop

estop.engage()          # 创建 sentinel 文件
# 下一轮 iteration 开头会 check_paused() 抛 EStopEngaged
```

### 4.4 外部内存 provider 接入

```python
from agent.memory_provider import MemoryProvider

class MyMemory(MemoryProvider):
    async def recall(self, query, k=5):
        ...

agent = AIAgent(config=cfg, external_memory=MyMemory())
```

### 4.5 自定义上下文压缩策略

```python
from agent.context_engine import ContextEngine

class TruncateCompressor(ContextEngine):
    def compress(self, history, budget):
        return history[-budget:]  # 最简：截断到预算

    def select_context(self, turn, memories):
        return memories[:5]
```

## 五、小结

1. agent/ 是扁平结构的运行时心脏，AIAgent 是瘦门面，真实逻辑分散在约 60 个专职文件中，按文件名即可定位能力域。
2. 上下文（ContextEngine）与内存（MemoryProvider）双 ABC 线 + MemoryManager 编排器，使压缩算法、召回来源可独立替换（策略模式）。
3. 错误处理采用"分类 + 退避"分离设计，ClassifiedError 把原因与恢复动作解耦，支撑限流退避、凭证换 key、provider failover 三种恢复路径。
4. 紧急停止遵循 Fail-Safe：is_engaged 在 OSError 时返回 True，宁可误停也不在失控时继续跑。
5. 对话循环由 IterationBudget 驱动（parent 500 / subagent 50，支持 refund），配合 prompt cache plan、redact 脱敏与 curator 自我审查，构成可控、可缓存、可中止的韧性循环。
