# gateway 模块

> 交叉引用: [01-项目概述](01-project-overview.md) | [02-整体架构](02-overall-architecture.md) | [03-agent 模块](03-agent-module.md) | [04-tools 模块](04-tools-module.md)

## 一、模块概述

gateway/ 是 Hermes Agent 的消息网关，充当消息平台与 agent 之间的双向桥梁。入站方向：管理 20+ 平台适配器，把各家平台 SDK 的事件归一化为 MessageEvent / SessionSource，路由到 agent 跑一轮对话；出站方向：把 agent 产生的流式响应按平台能力（原生卡片 / 中继文本）渲染并投递回去。

除了消息桥接，gateway/ 同时是运维控制平面：status.py 管理 PID 文件与锁，drain_control.py 用文件 marker + 实例 epoch 实现排空，readiness.py 暴露健康探针，systemd_notify.py 喂 systemd 看门狗，memory_monitor.py 监控 RSS 防止内存溢出。这些组件让网关可在生产环境长跑、优雅排空、被编排系统监管。

run.py 是体量约 26.5k 行的 god-file，通过 mixin 拆分为多个正交能力域（鉴权、看板监听、斜杠命令等），GatewayRunner 以多继承组合这些 mixin。平台适配器分两类：内建平台在 `gateway/platforms/` 下，插件平台在 `plugins/platforms/<name>/adapter.py`（22 个），由 platform_registry 自注册。

## 二、关键类与函数

| 类/函数 | 文件位置 | 说明 |
|---|---|---|
| [GatewayRunner](file:///D:\yaodh\main\hermes-agent\gateway\run.py#L5923) | gateway/run.py | 网关主控，多 mixin 组合 |
| [TurnRunner](file:///D:\yaodh\main\hermes-agent\gateway\run.py#L3834) | gateway/run.py | 单轮协作者 |
| [start_gateway](file:///D:\yaodh\main\hermes-agent\gateway\run.py#L27937) | gateway/run.py | 网关异步主入口 |
| [_handle_message_with_agent](file:///D:\yaodh\main\hermes-agent\gateway\run.py#L17373) | gateway/run.py | sentinel 守卫下跑一轮 agent |
| [_run_agent](file:///D:\yaodh\main\hermes-agent\gateway\run.py#L25650) | gateway/run.py | profile 作用域包装 |
| [BasePlatformAdapter](file:///D:\yaodh\main\hermes-agent\gateway\platforms\base.py#L2884) | gateway/platforms/base.py | 平台适配器抽象基类 |
| [MessageEvent](file:///D:\yaodh\main\hermes-agent\gateway\platforms\base.py#L2294) | gateway/platforms/base.py | 归一化入站事件 |
| [SessionSource](file:///D:\yaodh\main\hermes-agent\gateway\session.py#L149) | gateway/session.py | 消息来源描述 |
| [SessionStore](file:///D:\yaodh\main\hermes-agent\gateway\session.py#L1238) | gateway/session.py | 会话存储（SQLite 为主） |
| [Platform](file:///D:\yaodh\main\hermes-agent\gateway\config.py#L317) | gateway/config.py | 24 内建平台 + 动态插件成员枚举 |
| [DeliveryTransport](file:///D:\yaodh\main\hermes-agent\gateway\delivery.py#L62) | gateway/delivery.py | 解析后的投递传输 |
| [StreamEvent](file:///D:\yaodh\main\hermes-agent\gateway\stream_events.py#L151) | gateway/stream_events.py | agent→网关流式事件契约 |
| [SystemdWatchdog](file:///D:\yaodh\main\hermes-agent\gateway\systemd_notify.py#L60) | gateway/systemd_notify.py | systemd 看门狗 |

## 三、实现机制

### 3.1 ABC + 多平台适配器

BasePlatformAdapter 是抽象基类，用 @abstractmethod 强制每个平台实现 connect / disconnect / send / get_chat_info 四个核心方法。入站事件归一化为 MessageEvent（含文本、附件、来源 SessionSource），出站 send 接收已渲染内容。这样网关主循环只面对统一抽象，不感知具体平台 SDK 差异：

```python
class BasePlatformAdapter(ABC):
    @abstractmethod
    async def connect(self): ...
    @abstractmethod
    async def disconnect(self): ...
    @abstractmethod
    async def send(self, chat_id, content): ...
    @abstractmethod
    async def get_chat_info(self, chat_id) -> ChatInfo: ...

    async def on_event(self, raw) -> MessageEvent:
        # 子类实现平台特定解析，产出归一化事件
        ...
```

Platform 是枚举类型，含 24 个内建平台成员加动态插件成员，新增插件平台时枚举可动态扩展，不必改源码常量。

### 3.2 mixin 拆分 god-file

run.py 约 26.5k 行，GatewayRunner 通过多继承把正交能力拆到 mixin。每个 mixin 只管一个能力域，GatewayRunner 自身只持有编排逻辑，避免单类膨胀到不可维护：

```python
class GatewayRunner(
    GatewayAuthorizationMixin,      # 鉴权 / token 校验
    GatewayKanbanWatchersMixin,     # 看板监听
    GatewaySlashCommandsMixin,      # 斜杠命令
    ...,
):
    def __init__(self, config):
        ...
```

这种拆法让"鉴权改动"不会碰"斜杠命令改动"，单测可针对单个 mixin 编写。

### 3.3 结构化流事件契约

agent 与网关之间用 StreamEvent 通信，它是一组 frozen dataclass 的联合类型，只描述"发生了什么"（文本块、工具调用、错误、完成），不描述"怎么渲染"。渲染由 DeliveryTransport 在网关侧按平台能力决定：

```python
@dataclass(frozen=True)
class TextDelta(StreamEvent):
    text: str

@dataclass(frozen=True)
class ToolCallEvent(StreamEvent):
    name: str
    args: dict

@dataclass(frozen=True)
class TurnFinal(StreamEvent):
    ...

StreamEvent = Union[TextDelta, ToolCallEvent, TurnFinal, ...]
```

frozen 保证事件不可变、可安全在协程间传递。"事件 vs 渲染"分离让 agent 不必关心目标平台，网关可自由选择 native 卡片或 relay 纯文本投递——同一轮对话既能输出富卡片到飞书，也能降级纯文本到 IRC。

### 3.4 文件 marker + 实例 epoch 排空

drain_control.py 用 `.drain_request.json` 文件 marker 实现优雅排空。marker 带 instantiation_epoch，只有发起排空请求的实例 epoch 与当前实例一致才生效，防止跨实例误排空（旧实例的 marker 不应影响新实例）：

```python
def request_drain(epoch):
    _MARKER.write(json.dumps({"instantiation_epoch": epoch}))

def should_drain(now, current_epoch) -> bool:
    if not _MARKER.exists():
        return False
    data = json.loads(_MARKER.read_text())
    return data["instantiation_epoch"] == current_epoch
```

收到排空信号后，网关停止接新消息，等在途轮次完成后退出。

### 3.5 会话状态合并视图

SessionStore 以 SQLite 为主存储，对上层暴露 SessionState 活映射视图——读到的状态始终是库中最新值的合并，写入即时反映到视图，避免缓存与库不一致。SessionSource 描述消息来源（platform + chat_id + user_id），是构造 session_key 的原料。

### 3.6 运维控制平面

除消息桥接外，gateway/ 内聚了一组生产运维组件：

- status.py：PID 文件 + 文件锁，保证同实例不重复启动；
- readiness.py：健康探针，探针通过才接收流量；
- systemd_notify.py：SystemdWatchdog 周期 NOTIFY，喂看门狗防重启；
- memory_monitor.py：RSS 监控，超阈值主动排空或告警。

这些组件让网关可在容器/编排系统内长跑、被监管、优雅排空。

### 3.7 消息数据流

完整入站到出站的数据流：

```
平台 SDK 事件
  └─ adapter.on_event               # 解析为 MessageEvent
       └─ handle_message             # 网关入口
            ├─ build_session_key     # (platform, chat_id, ...) → key
            └─ _primary_message_handler  # 注入会话上下文
                 └─ _handle_message_with_agent   # sentinel 守卫
                      └─ _run_agent              # profile 作用域包装
                           └─ agent.run()        # 跑一轮（见 03-agent-module）
                                └─ StreamEvent 流
                                     └─ GatewayStreamConsumer
                                          └─ DeliveryTransport 解析
                                               ├─ native：adapter.send 卡片
                                               └─ relay：adapter.send 纯文本
```

## 四、调用示例

### 4.1 启动网关

```python
import asyncio
from gateway.run import start_gateway

asyncio.run(start_gateway(config_path="config.yaml"))
```

start_gateway 会装载 Platform 枚举、连接内建与插件适配器、注册看门狗与排空控制，然后进入事件循环。

### 4.2 实现一个插件平台适配器

```python
# plugins/platforms/mychat/adapter.py
from gateway.platforms.base import BasePlatformAdapter, MessageEvent

class MyChatAdapter(BasePlatformAdapter):
    async def connect(self):
        self._client = MyChatSDK(token=self.cfg.token)

    async def disconnect(self):
        await self._client.close()

    async def send(self, chat_id, content):
        await self._client.post(chat_id, content)

    async def get_chat_info(self, chat_id):
        return ChatInfo(id=chat_id, title=await self._client.title(chat_id))

    async def on_event(self, raw):
        return MessageEvent(
            text=raw["text"],
            source=SessionSource(platform="mychat", chat_id=raw["chat"]),
        )
```

落盘到 `plugins/platforms/mychat/adapter.py`，platform_registry 自注册即纳入。

### 4.3 触发排空

```python
from gateway.drain_control import request_drain

request_drain(epoch=runner.instantiation_epoch)
# 网关停止接新消息，在途轮次完成后退出
```

### 4.4 健康探针与看门狗

```python
from gateway.readiness import is_ready
from gateway.systemd_notify import SystemdWatchdog

if is_ready():
    # 编排系统探针通过
    ...

watchdog = SystemdWatchdog(interval_s=10)
await watchdog.start()   # 周期 NOTIFY 喂 systemd
```

## 五、小结

1. gateway/ 是消息平台与 agent 的双向桥梁：入站归一化为 MessageEvent/SessionSource 路由到 agent，出站按平台能力渲染投递。
2. BasePlatformAdapter(ABC) 强制四核心方法，适配器分内建（gateway/platforms/）与插件（plugins/platforms/<name>/，22 个，platform_registry 自注册）两类。
3. run.py 26.5k 行 god-file 用 mixin 拆分正交能力域，GatewayRunner 多继承组合鉴权、看板、斜杠命令等 mixin，单能力域可独立单测。
4. StreamEvent 是"只描述发生了什么"的 frozen 联合契约，渲染决策下放到 DeliveryTransport，使 agent 与平台解耦，同一轮对话可富卡片与纯文本双投。
5. 同时是运维控制平面：排空用文件 marker + 实例 epoch 防跨实例误触，status/readiness/systemd_notify/memory_monitor 支撑长跑、优雅排空与编排监管。
