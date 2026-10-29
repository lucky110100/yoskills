# web 模块

> 交叉引用: [01-项目概述](01-project-overview.md) | [02-整体架构](02-overall-architecture.md) | [10-tui-gateway模块](10-tui-gateway-module.md) | [13-desktop模块](13-desktop-module.md)

## 一、模块概述

web 是 Hermes 的浏览器仪表盘 SPA，由 React 19 + Vite 构建，产物输出到 `hermes_cli/web_dist` 供 Python `hermes dashboard` 服务端托管。它用 `fetchJSON` 经 REST `/api/*` 管理会话/配置/Cron/MCP/Skills/Profiles 等管理面，用 `GatewayClient`（WebSocket JSON-RPC）驱动聊天事件流，并在 `/chat` 路由用 xterm.js + `/api/pty` WebSocket 内嵌一个真实 `hermes --tui` 进程。

它是一个可扩展外壳：通过 `exposePluginSDK()` 在渲染前向 `window` 注入 SDK，运行时从 `/api/dashboard/plugins` 拉取 manifest，把插件路由（override/addon）合并进 `buildRoutes`，把插件 UI 经 `PluginSlot` 注入到命名的 shell/page 槽位；多 Profile 作用域、i18n（18 种语言）、主题（CSS 变量 + 预设）三层 Provider 包裹整个应用。

## 二、关键文件与组件

| 文件 | 角色 | 位置 |
|------|------|------|
| main.tsx | 入口：`exposePluginSDK()` → `createRoot` + `BrowserRouter` + I18n/Theme Provider | [main.tsx](file:///D:\yaodh\main\hermes-agent\web\src\main.tsx#L13) |
| App.tsx | 主应用：侧栏导航、lazy 路由、持久化 ChatPage host、插件 manifest 合并 | [App.tsx](file:///D:\yaodh\main\hermes-agent\web\src\App.tsx#L371) |
| api.ts | `fetchJSON` REST 客户端 + Profile 作用域 + WS ticket 鉴权 + 401 重载策略 | [api.ts](file:///D:\yaodh\main\hermes-agent\web\src\lib\api.ts#L102) |
| gatewayClient.ts | 浏览器 WS JSON-RPC 客户端，继承共享 `JsonRpcGatewayClient` | [gatewayClient.ts](file:///D:\yaodh\main\hermes-agent\web\src\lib\gatewayClient.ts#L29) |
| ChatPage.tsx | 内嵌 TUI：xterm.js(WebGL) ↔ `/api/pty` WS ↔ PTY 子进程 | [ChatPage.tsx](file:///D:\yaodh\main\hermes-agent\web\src\pages\ChatPage.tsx#L1) |
| slots.ts | `KNOWN_SLOT_NAMES` + `PluginSlot` 槽位注册表 | [slots.ts](file:///D:\yaodh\main\hermes-agent\web\src\plugins\slots.ts#L61) |
| plugins/index.ts | 插件门面：`exposePluginSDK`/`PluginPage`/`usePlugins`/`PluginSlot` | [index.ts](file:///D:\yaodh\main\hermes-agent\web\src\plugins\index.ts#L1) |
| themes/index.ts | 主题：`ThemeProvider`/`useTheme` + `BUILTIN_THEMES` | [index.ts](file:///D:\yaodh\main\hermes-agent\web\src\themes\index.ts#L1) |
| i18n/index.ts | 国际化：`I18nProvider`/`useI18n` + 18 种语言 | [index.ts](file:///D:\yaodh\main\hermes-agent\web\src\i18n\index.ts#L1) |
| ProfileProvider.tsx | 全局管理 Profile 作用域，`ProfileKeyedRoutes` 按 profile 重挂载 | [ProfileProvider.tsx](file:///D:\yaodh\main\hermes-agent\web\src\contexts\ProfileProvider.tsx) |
| vite.config.ts | Vite：`hermesDevToken` 注入 dev session token | [vite.config.ts](file:///D:\yaodh\main\hermes-agent\web\vite.config.ts#L60) |

## 三、实现机制

### 3.1 lazy 路由 + 持久化 ChatPage host

App.tsx 把 20 个页面 `lazy()` 切分（xterm/three/plot 按需）；在嵌入聊天开启时把 `ChatPage` 渲染在 `<Routes>` 之外，用 `data-chat-active` + `hidden` class 切换显隐——PTY 子进程、WebSocket、xterm 实例在切 tab 时存活不卸载。

### 3.2 Profile 作用域透明注入

`fetchJSON` 的 `withManagementProfile` 对 `PROFILE_SCOPED_PREFIXES`（status/gateway/analytics/skills/config/env/mcp…）自动追加 `?profile=`；`ProfileKeyedRoutes` 以 profile 为 key 整树重挂载，强制页面在切换管理 profile 时重新拉取，杜绝"显示 A、写入 B"的陈旧目标问题。

### 3.3 PluginSlot 注册表 + manifest 合并

`PluginSlot` 订阅 `_slotListeners`，插件 bundle 经 `window.__HERMES_PLUGINS__.registerSlot` 注入，组件在注册后无需刷新即出现；`buildRoutes` 按 manifest 的 `tab.override`（替换内置路由）或 addon（新增）合并。

### 3.4 双模式鉴权（loopback vs gated OAuth）

`buildWsAuthParam` 按 `window.__HERMES_AUTH_REQUIRED__` 选择：gated 模式调 `getWsTicket()` 取一次性 `ticket`，loopback 模式用注入的 `__HERMES_SESSION_TOKEN__`；401 处理区分"gated 会话过期→跳 /login"与"loopback token 轮换→整页 reload"。

## 四、代码片段

REST 客户端核心——Profile 透明作用域 + token 头 + cookie + 401 分支：

```typescript
export async function fetchJSON<T>(url: string, init?: RequestInit): Promise<T> {
  url = withManagementProfile(url);
  const headers = new Headers(init?.headers);
  const token = window.__HERMES_SESSION_TOKEN__;
  if (token) { setSessionHeader(headers, token); }
  const res = await fetch(`${BASE}${url}`, {
    ...init, headers,
    credentials: init?.credentials ?? "include",
  });
  if (res.status === 401) {
    // gated→/login, loopback→reload once
  }
  return res.json();
}
```

## 五、小结

1. React 19 + Vite SPA，产物输出到 `hermes_cli/web_dist` 供 Python 托管
2. 三条通信通道：REST `/api/*` + WebSocket JSON-RPC `/api/ws` + WebSocket PTY `/api/pty`
3. lazy 路由 + 持久化 ChatPage host，xterm/PTY 在切 tab 时存活不卸载
4. Profile 作用域透明注入（`ProfileKeyedRoutes` 整树重挂载）杜绝陈旧目标
5. 插件系统：SDK 注入 + manifest 路由合并 + PluginSlot 命名槽位
