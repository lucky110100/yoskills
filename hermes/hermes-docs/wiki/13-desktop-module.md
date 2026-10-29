# apps/desktop 模块

> 交叉引用: [01-项目概述](01-project-overview.md) | [02-整体架构](02-overall-architecture.md) | [11-ui-tui模块](11-ui-tui-module.md) | [12-web模块](12-web-module.md)

## 一、模块概述

apps/desktop 是 Hermes 的原生桌面聊天界面（Electron + React + Vite）。它与浏览器 dashboard 是不同表面，**不内嵌 TUI**——三权分立：Electron 主进程管机器（进程生命周期、原生 fs/git/窗口、安装更新、窄而类型化的能力桥），渲染进程管体验（导航/展示/瞬时交互态），agent 后端管工作（会话/工具/模型/流式）。入口 `main.tsx` 按 `?win=` 参数分流到主窗、HUD、宠物 overlay、quick-entry、wake-indicator 五种渲染根。

渲染层经 `hermes.ts` 与后端通信：REST 走 Electron preload 暴露的 `window.hermesDesktop.api`（IPC invoke → 主进程 → 后端 HTTP），流式事件走 `HermesGateway extends JsonRpcGatewayClient`（WebSocket JSON-RPC，共享包同款）。TanStack Query 缓存服务器态，nanostores 持有 UI 原子；插件经 `pluginRest`/`pluginSocket` 两个命名空间门访问后端。

## 二、关键文件与组件

| 文件 | 角色 | 位置 |
|------|------|------|
| main.tsx | 渲染入口：`?win=` 分流多窗 + QueryClientProvider + HashRouter | [main.tsx](file:///D:\yaodh\main\hermes-agent\apps\desktop\src\main.tsx#L40) |
| hermes.ts | 后端连接：`HermesGateway` + `window.hermesDesktop.api` 包装 + profile 路由 | [hermes.ts](file:///D:\yaodh\main\hermes-agent\apps\desktop\src\hermes.ts#L230) |
| preload.ts | `contextBridge.exposeInMainWorld('hermesDesktop', …)` 类型化能力门面 | [preload.ts](file:///D:\yaodh\main\hermes-agent\apps\desktop\electron\preload.ts#L3) |
| main.ts | Electron 主进程：窗口/后端子进程/原生能力 IPC handler | [main.ts](file:///D:\yaodh\main\hermes-agent\apps\desktop\electron\main.ts) |
| AGENTS.md | 架构契约：三权分立、状态归属权威、re-home、observable ladder | [AGENTS.md](file:///D:\yaodh\main\hermes-agent\apps\desktop\AGENTS.md#L11) |
| DESIGN.md | 设计系统：扁平/单原语/tokens/即时反馈 | [DESIGN.md](file:///D:\yaodh\main\hermes-agent\apps\desktop\DESIGN.md#L1) |
| json-rpc-gateway.ts | `JsonRpcGatewayClient` 基类：WS 连接 + `request` + `on(type)` 事件分发 | [json-rpc-gateway.ts](file:///D:\yaodh\main\hermes-agent\apps\shared\src\json-rpc-gateway.ts#L72) |
| websocket-url.ts | `buildHermesWebSocketUrl` + auth 模式解析 | [websocket-url.ts](file:///D:\yaodh\main\hermes-agent\apps\shared\src\websocket-url.ts) |
| index.ts | 共享包门面：billing/gateway/skin/websocket-url 统一导出 | [index.ts](file:///D:\yaodh\main\hermes-agent\apps\shared\src\index.ts#L37) |
| right-sidebar/store.ts | nanostores `atom` UI 状态 | [store.ts](file:///D:\yaodh\main\hermes-agent\apps\desktop\src\app\right-sidebar\store.ts#L1) |

## 三、实现机制

### 3.1 三权分立 + 窄能力桥

AGENTS.md 明确 Electron/renderer/backend 各自权威；渲染层绝不直接碰 Node/Electron，原生能力只经 preload.ts 的 `contextBridge.exposeInMainWorld('hermesDesktop', {...})` 显式暴露的 IPC 通道（`hermes:api`、`hermes:connection`、`hermes:git:*`、`hermes:terminal:*` 等）。这是"deliberate capability, not escape hatch"原则的落地。

### 3.2 共享 JsonRpcGatewayClient 多表面复用

`apps/shared` 的 `JsonRpcGatewayClient` 实现了连接、`request<T>`（带超时/AbortSignal）、`on(type)`/`onAny` 事件订阅、`onState` 状态订阅；web 的 `gatewayClient.ts` 与 desktop 的 `HermesGateway` 都继承它，仅注入不同错误文案/超时/`onSocketClose`——同一协议 dialect 跨三表面复用。

### 3.3 Profile 路由 + 命名空间插件门

`setApiRequestProfile`/`profileScoped()` 让每个 REST 调用携带 `request.profile`，Electron 主进程据此把调用路由到对应 profile 的后端进程池；`pluginRest` 把插件调用按构造限制在 `/api/plugins/<pluginId>` 命名空间内（`pluginPathSuffix` 拒绝 `..` 穿越），`pluginSocket` 是其 live WS 双胞胎——"namespace IS the boundary"。

### 3.4 observable ladder 兼容回退

`listSidebarSessions` 先试批量 `/api/profiles/sessions/sidebar`，遇 `isEndpointMissingError`（404/"No such API endpoint"）则永久降级到三次 per-slice 调用——区分"能力缺失（兼容旧后端）"与"瞬态失败（应重试）"。

## 四、代码片段

插件 REST 命名空间门（IPC 桥 + profile 路由 + 路径穿越防护）：

```typescript
export async function pluginRest<T>(
  pluginId: string, path: string, opts: PluginRestOptions = {}
): Promise<T> {
  if (!window.hermesDesktop?.api) {
    throw new Error('Hermes desktop bridge unavailable')
  }
  const suffix = pluginPathSuffix('pluginRest', path)
  return window.hermesDesktop.api<T>({
    path: `/api/plugins/${pluginId}${suffix}`,
    method: opts.method,
    body: opts.body,
    upload: opts.upload,
    timeoutMs: opts.timeoutMs,
    ...profileScoped()
  })
}
```

## 五、小结

1. Electron + React + Vite 桌面应用，三权分立（主进程/渲染/后端），不内嵌 TUI
2. 共享 `JsonRpcGatewayClient` 基类跨 web/desktop 两表面复用同一 JSON-RPC 方言
3. Profile 路由 + `pluginRest`/`pluginSocket` 命名空间门实现多 profile + 插件安全隔离
4. observable ladder 兼容回退：区分"能力缺失（降级）"与"瞬态失败（重试）"
5. `?win=` 参数分流五种渲染根（主窗/HUD/宠物 overlay/quick-entry/wake-indicator）
