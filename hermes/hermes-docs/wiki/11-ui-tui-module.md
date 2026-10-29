# ui-tui 模块

> 交叉引用: [01-项目概述](01-project-overview.md) | [02-整体架构](02-overall-architecture.md) | [10-tui_gateway 模块](10-tui-gateway-module.md) | [12-web 模块](12-web-module.md) | [15-运行指南](15-running-guide.md)

## 一、模块概述

`ui-tui` 是 Hermes 的终端交互前端，以 `hermes --tui` 为入口启动。它用 React + Ink 在终端里渲染完整对话界面，并自研了一套 `hermes-ink` 渲染引擎，以获得比上游 Ink 更精细的布局与鼠标/选区控制。

模块的核心定位：

- **渲染层**：自研 `hermes-ink` 引擎，负责把 React 树绘制成终端字符帧；
- **通信层**：[GatewayClient](file:///D:/yaodh/main/hermes-agent/ui-tui/src/gatewayClient.ts) 是双传输 JSON-RPC 客户端，spawn 模式走子进程 stdio，attach 模式走 WebSocket；
- **状态层**：基于 nanostores 的原子状态，全局 UI 原子集中在 [uiStore.ts](file:///D:/yaodh/main/hermes-agent/ui-tui/src/app/uiStore.ts)；
- **扩展层**：widget SDK 提供 modal/dock/rail 三类槽位，第三方 widget 可注入主界面而不污染核心。

后端契约对接 [10-tui_gateway 模块](10-tui-gateway-module.md) 暴露的 JSON-RPC 方法，前端只管"连哪个传输、订阅哪些事件"。

## 二、关键文件

### 入口与应用骨架

| 文件 | 职责 | 位置 |
| --- | --- | --- |
| [entry.tsx](file:///D:/yaodh/main/hermes-agent/ui-tui/src/entry.tsx) | 进程入口：清屏、实例化 `GatewayClient`、启动渲染循环 | [entry.tsx:L51](file:///D:/yaodh/main/hermes-agent/ui-tui/src/entry.tsx#L51) |
| [app.tsx](file:///D:/yaodh/main/hermes-agent/ui-tui/src/app.tsx) | 主应用组件，组合 transcript/composer/progress/status | [app.tsx:L9](file:///D:/yaodh/main/hermes-agent/ui-tui/src/app.tsx#L9) |

### 通信与数据

| 文件 | 职责 | 位置 |
| --- | --- | --- |
| [gatewayClient.ts](file:///D:/yaodh/main/hermes-agent/ui-tui/src/gatewayClient.ts) | 双传输 JSON-RPC 客户端；spawn 子进程或连 WS，管理 pending/缓冲/重放 | [gatewayClient.ts:L134](file:///D:/yaodh/main/hermes-agent/ui-tui/src/gatewayClient.ts#L134) |
| [rpc.ts](file:///D:/yaodh/main/hermes-agent/ui-tui/src/lib/rpc.ts) | RPC 结果类型守卫，区分 result/error 并收窄类型 | [rpc.ts:L8](file:///D:/yaodh/main/hermes-agent/ui-tui/src/lib/rpc.ts#L8) |
| [messages.ts](file:///D:/yaodh/main/hermes-agent/ui-tui/src/lib/messages.ts) | 转录本维护：把流式事件折叠成可渲染的消息序列 | [messages.ts:L8](file:///D:/yaodh/main/hermes-agent/ui-tui/src/lib/messages.ts#L8) |

### 交互与状态

| 文件 | 职责 | 位置 |
| --- | --- | --- |
| [scroll.ts](file:///D:/yaodh/main/hermes-agent/ui-tui/src/app/scroll.ts) | 滚动 + 选区联动，按 delta 计算实际滚动量与视口边界 | [scroll.ts:L33](file:///D:/yaodh/main/hermes-agent/ui-tui/src/app/scroll.ts#L33) |
| [uiStore.ts](file:///D:/yaodh/main/hermes-agent/ui-tui/src/app/uiStore.ts) | nanostores 全局 UI 原子（theme/sid/usage 等） | [uiStore.ts:L41](file:///D:/yaodh/main/hermes-agent/ui-tui/src/app/uiStore.ts#L41) |

### widget SDK

| 文件 | 职责 | 位置 |
| --- | --- | --- |
| [sdk/host.tsx](file:///D:/yaodh/main/hermes-agent/ui-tui/src/sdk/host.tsx) | widget host：承载已注册 widget 的渲染与生命周期 | [sdk/host.tsx:L30](file:///D:/yaodh/main/hermes-agent/ui-tui/src/sdk/host.tsx#L30) |
| [sdk/registry.ts](file:///D:/yaodh/main/hermes-agent/ui-tui/src/sdk/registry.ts) | widget 注册表：按 id 登记 WidgetApp | [sdk/registry.ts:L7](file:///D:/yaodh/main/hermes-agent/ui-tui/src/sdk/registry.ts#L7) |
| [sdk/types.ts](file:///D:/yaodh/main/hermes-agent/ui-tui/src/sdk/types.ts) | `WidgetApp` 契约：reduce/render/槽位类型 | [sdk/types.ts:L36](file:///D:/yaodh/main/hermes-agent/ui-tui/src/sdk/types.ts#L36) |

## 三、实现机制

### 设计模式一：nanostores 原子状态

状态层不用 Redux 这类大容器，而用 nanostores 的 `atom` + `computed`。全局 UI 状态集中在一个根原子 `$uiState` 上，派生原子（如 `$uiTheme`、`$uiSessionId`）通过 `computed` 投影出来：

```ts
export const $uiState = atom<UiState>(buildUiState())
export const $uiTheme = computed($uiState, s => s.theme)
export const $uiSessionId = computed($uiState, s => s.sid)
```

组件用 `useStore($uiState)` 订阅，只有真正变化的切片触发重渲染。`patchUiState` 既接受偏对象也接受 reducer 函数，便于批量更新。首帧主题从上次会话的 `bootTheme` 读取，避免冷启动闪烁（与桌面端 `hermes-boot-*` 思路一致）。

### 设计模式二：JSON-RPC 双传输 + 缓冲重放

[GatewayClient](file:///D:/yaodh/main/hermes-agent/ui-tui/src/gatewayClient.ts) 同时管理两条数据路径：

- **spawn 模式**：以子进程拉起 `hermes --tui`，用 `createInterface` 逐行解析 stdout 的 JSON 帧，写请求经 stdin 下发；
- **attach 模式**：连 WebSocket，帧以消息边界收发。

两条路径共用同一套 `pending` 请求表与事件总线。关键在于 **缓冲重放**：连接尚未 ready 时到达的事件先进 `bufferedEvents`（`CircularBuffer`），订阅建立后一次性重放给新订阅者，保证"先订阅后连接"与"先连接后订阅"两种时序都不丢事件。`readyTimer` 与 `drainGeneration` 协作，把缓冲排空与重连代际对齐，避免旧代连接的迟到帧污染新会话。

### 设计模式三：slot 注入 + 错误隔离 widget SDK

widget SDK 定义三类槽位：

- **modal**：独占按键、阻塞 composer，适合全屏交互；
- **dock**：常驻侧栏，可折叠；
- **rail**：边缘窄条，承载 chip/状态。

`WidgetApp` 契约要求实现 `reduce(state, input)` 与 `render(ctx)`：reduce 返回新状态、原引用（吞键）或 null（关闭）；render 返回叠加层节点，并用 SDK 原语（`Overlay`/`Dialog`/`WidgetGrid`）组合，保证布局与主题由引擎统一推导。[host.tsx](file:///D:/yaodh/main/hermes-agent/ui-tui/src/sdk/host.tsx) 负责把注册表里的 widget 挂到对应槽位，并对单个 widget 的渲染做错误隔离——一个 widget 抛异常不会拖垮整个 TUI。

### 设计模式四：identity-gated 传输重连

重连不是无脑重试。客户端在重连前会校验身份票据（session_key / attach token），只有身份仍有效才会重建传输；票据失效则转入错误态提示重新认证。这避免了"僵尸会话"——一个已被后端回收的会话，前端却反复重连占用资源。

### 进程模型

- **spawn 模式**：`entry.tsx` 用 `child_process.spawn` 拉起 gateway 子进程，stdin/stdout 即为 RPC 通道。生命周期与前端进程绑定，前端退出即回收子进程。
- **attach 模式**：前端连一个已存在的 WS sidecar，可多窗口共享同一后端会话，窗口关闭不影响后端。

两种模式对上层完全透明——`GatewayClient` 暴露同一套 `request`/`subscribe` API。

## 四、调用示例/代码片段

### 启动并订阅事件

```tsx
const gw = new GatewayClient()
gw.start()                              // spawn 或 attach
gw.on('event', (e: GatewayEvent) => {    // 事件总线
  appendTranscript(e)
})
await gw.request('agent/start', { sid }) // 下发 RPC
```

### 状态读取与更新

```tsx
function ThemeBadge() {
  const { theme } = useStore($uiState)
  return <Text color={theme.accent}>{theme.name}</Text>
}
patchUiState(s => ({ ...s, sid: nextSid }))  // reducer 形式
```

### 注册一个 widget

```tsx
import { registry } from './sdk/registry'

registry.register({
  id: 'todo',
  help: '快速待办',
  slot: 'dock',
  reduce: (s, input) => s,      // 处理按键
  render: (ctx) => <TodoList {...ctx} />,
})
```

### 滚动与选区联动（简化）

```ts
export function scrollWithSelectionBy(delta, { scrollRef, selection }) {
  const s = scrollRef.current
  if (!s) return
  const cur = s.getScrollTop() + s.getPendingDelta()
  const { max, viewport } = scrollBoundsForDelta(s, cur, delta)
  const actual = Math.max(0, Math.min(max, cur + delta)) - cur
  s.scrollBy(actual)
}
```

## 五、小结

`ui-tui` 把终端前端拆成渲染、通信、状态、扩展四层，各层边界清晰：`hermes-ink` 引擎管"怎么画"，`GatewayClient` 管"怎么连后端"，nanostores 管"状态怎么流"，widget SDK 管"怎么加东西而不破坏核心"。双传输 + 缓冲重放让 spawn 与 attach 两种进程模型对上层无感，identity-gated 重连又守住了会话安全边界。这套前端与 [10-tui_gateway 模块](10-tui-gateway-module.md) 的后端契约严格对齐，是 Hermes 在终端体验上既灵活又稳定的根基。

## 六、附录：连接状态机与事件分类

### GatewayClient 连接状态

| 状态 | 含义 | 触发转移 |
| --- | --- | --- |
| `idle` | 未启动 | `start()` → connecting |
| `connecting` | 握手中 | 握手成功 → ready；超时 → error |
| `ready` | 已连，可收发 | 对端关闭 → reconnecting/error |
| `reconnecting` | 身份校验后重连 | 校验通过 → connecting；票据失效 → error |
| `error` | 不可恢复 | 通知 UI 重新认证 |

`DEFAULT_CONNECT_TIMEOUT_MS`（15s）保证休眠唤醒后不会卡在 connecting，超时即转 error 让 UI 可重试。

### 事件分类

| 事件 | 来源 | 用途 |
| --- | --- | --- |
| `message.delta` | agent 流式输出 | 实时拼接转录本 |
| `tool.call` / `tool.result` | 工具执行 | 折叠成工具卡片 |
| `session.created` | gateway | 更新 sid 原子 |
| `usage.tick` | 模型计量 | 刷新用量徽标 |
| `state.change` | 连接层 | 驱动 composer 启停 |

### 端到端时序（attach 模式）

```ts
gw.start()                          // → connecting
  // WS 握手 + identity 校验
  // ready → 一次性重放 bufferedEvents
gw.subscribe(['message.delta'])     // 注册事件过滤器
await gw.request('session/create')  // 拿到 sid
patchUiState(s => ({ ...s, sid }))  // 状态原子更新 → App 重渲染
await gw.request('agent/start', { sid })
// gateway 投线程池跑 agent，逐帧推 message.delta
// transcript 折叠 → hermes-ink 绘制 → 终端字符帧
```

缓冲重放保证：即便 `subscribe` 晚于 `ready`，重放也会把 ready 前后到达的事件按代际对齐投递，无丢无重。

## 七、附录：spawn 与 attach 模式对比

| 维度 | spawn 模式 | attach 模式 |
| --- | --- | --- |
| 后端进程 | 前端拉起子进程 | 已存在 sidecar |
| 通道 | 子进程 stdin/stdout | WebSocket |
| 多窗口共享 | 否（1:1） | 是（多:1） |
| 前端退出影响 | 回收后端 | 不影响后端 |
| 重连语义 | 子进程已死，需重启 | 可重连同一会话 |
| identity 票据 | 进程级 | session_key/attach token |

两种模式共用同一 `GatewayClient` API，差异只在 `start()` 内部的传输初始化分支。后续 [12-web 模块](12-web-module.md) 的 `/chat` 路由用 xterm.js 内嵌 `hermes --tui`，本质是借用了 spawn 模式的进程模型。

> 说明：本篇所述 API 与 [10-tui_gateway 模块](10-tui-gateway-module.md) 的方法注册表一一对应，前端调用名即后端 method 名。
