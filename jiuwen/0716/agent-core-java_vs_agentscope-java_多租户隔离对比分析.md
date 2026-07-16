# agent-core-java vs agentscope-java 多租户资源隔离对比分析

> 日期：2026-07-16
> 范围：仅对比 agent-core-java 与 agentscope-java 两个项目

---

## 1. 设计哲学对比

| 维度 | agent-core-java | agentscope-java |
|------|----------------|-----------------|
| **隔离模型** | 显式租户隔离（tenantId 驱动） | 作用域隔离（IsolationScope 枚举驱动） |
| **核心抽象** | `TenantContext(tenantId, metadata)` | `IsolationScope` + `RuntimeContext(userId, sessionId)` |
| **隔离粒度** | 单一维度：tenantId | 四维可选：SESSION / USER / AGENT / GLOBAL |
| **设计思路** | 从业务租户概念出发，自顶向下 | 从运行时作用域出发，自底向上 |
| **Agent 感知度** | ReActAgent 不感知租户（DeepAgent 层注入） | HarnessAgent 天然感知 IsolationScope（Builder 配置） |
| **适用场景** | 企业多租户 SaaS | 多租户 + 多会话 + 多粒度资源共享 |

**关键差异**：agent-core-java 的"租户"是外部业务概念（哪个公司/组织），而 agentscope-java 的"隔离"是运行时语义概念（会话级/用户级/Agent级/全局），两者视角不同。

---

## 2. 隔离层级对比

### 2.1 agent-core-java 隔离层级

```
TENANT（租户级）     ← 唯一隔离维度，由 tenantId 决定
  └── SESSION（会话级）← Checkpointer key 中的 sessionId 部分
```

只有两级：tenantId 粗粒度 + sessionId 细粒度。tenantId 为空时降级到共享空间。

### 2.2 agentscope-java 隔离层级

```
GLOBAL（全局共享）    ← 整个 store 实例共享一个命名空间
  │
AGENT（Agent级）     ← 同 agent 跨用户/会话共享，agentId 隔离
  │
USER（用户级）       ← 同用户跨会话共享，userId 隔离 ← 默认
  │
SESSION（会话级）    ← 严格会话隔离，sessionId 隔离
```

四级可选，默认 USER 级，且有降级链：USER → SESSION（userId 缺失时）。

### 2.3 层级映射关系

| agentscope-java | agent-core-java | 说明 |
|-----------------|----------------|------|
| GLOBAL | 无对应 | agent-core-java 不支持全局共享模式 |
| AGENT | 无对应 | agent-core-java 不支持按 Agent 维度共享 |
| USER | TENANT | 语义最接近：按用户/租户隔离 |
| SESSION | SESSION | 都有会话级细分 |

---

## 3. 隔离资源对比

### 3.1 综合对比表

| 资源 | agent-core-java | agentscope-java | 差异分析 |
|------|----------------|-----------------|---------|
| **Workspace** | 目录路径隔离 `tenants/{tenantId}/workspace` | 命名空间隔离 `NamespaceFactory` + BaseStore | 底层机制完全不同：磁盘目录 vs KV Store 命名空间 |
| **临时文件(tmp)** | 子目录 + TTL清理（500MB/24h） | 随 Sandbox 容器生命周期 | agent-core 主动管控配额；agentscope 依赖容器销毁 |
| **Skill** | 全局公共 + 租户私有合并加载 | WorkspaceSkillRepository + 命名空间隔离 | agent-core 是合并式（全局+租户）；agentscope 是覆盖式（模板+用户copy-on-write） |
| **Checkpointer/State** | Key前缀 `tenantId:sessionId` | AgentStateStore `(userId, sessionId)` 二元组 | agent-core 用字符串拼接；agentscope 用结构化分区键 |
| **Sandbox容器** | isolationKey 前缀 `tenantId_customId` | SandboxIsolationKey 四级解析 | agentscope 粒度更细，且支持分布式锁 |
| **文件读写路径** | sandboxRoot + restrictToSandbox | PathPolicy + Sandbox 限制 | 思路相似，都是限制在租户/作用域范围内 |
| **路径穿越防护** | TenantPathValidator（normalize + toRealPath） | PathPolicy（白名单） | agent-core 主动防御（校验每次路径）；agentscope 预防式（白名单限制可达范围） |
| **Memory** | 无显式隔离（依赖 workspace 路径间接隔离） | MemoryFlushMiddleware 按 IsolationScope 节流 + 外部记忆系统多租户 | agentscope 隔离更完善 |
| **子Agent工作空间** | 无 | WorkspaceMode.ISOLATED/SHARED | agentscope 独有 |
| **并发控制** | ThreadLocal | SandboxExecutionGuard（Redis/PG/MySQL 分布式锁） | agentscope 支持分布式并发控制 |

### 3.2 agentscope-java 独有资源隔离

| 资源 | 隔离方式 | 说明 |
|------|---------|------|
| **远端文件系统命名空间** | NamespaceFactory + BaseStore | 每次操作动态解析命名空间前缀 |
| **Sandbox 状态持久化** | SessionSandboxStateStore | 四级 slot 编码：`sandbox/session/`, `sandbox/user/`, `sandbox/agent/`, `sandbox/global` |
| **Sandbox 执行锁** | SandboxExecutionGuard | Redis SET NX / PG advisory lock / MySQL GET_LOCK |
| **Memory 刷盘节流** | 按 IsolationScope 分窗口 | USER: 每用户一个窗口；SESSION: 每会话一个；AGENT/GLOBAL: 共享窗口 |
| **外部记忆系统** | Mem0 / ReMe / 百炼 | 多租户 + 多用户 + 多 Agent 三维隔离 |
| **子Agent隔离** | WorkspaceMode.ISOLATED | `name@parentSessionId#userId` 组合键 |
| **工作空间投影** | WorkspaceProjectionApplier | 将宿主文件注入 Sandbox 容器 |

### 3.3 agent-core-java 独有资源隔离

| 资源 | 隔离方式 | 说明 |
|------|---------|------|
| **资源配额管控** | TenantResourceQuota | 500MB/租户上限 + 24h TTL 清理 |
| **Skill 合并加载** | 全局 + 租户私有 | agentscope 是覆盖式，agent-core 是合并式 |
| **租户目录自动初始化** | TenantWorkspaceManager.initializeTenant | 幂等创建租户完整目录树 |

---

## 4. 数据传递/穿刺对比

### 4.1 agent-core-java tenant_id 穿刺

```
HTTP X-Tenant-Id
  → Controller 提取
    → TenantContext(tenantId, metadata)
      → Session 绑定
        → DeepAgent.invoke() 从 Session 获取
          → 拆解 tenantId 传入:
            ├─ TenantWorkspaceManager.resolveWorkspace(tenantId)
            ├─ TenantSysOpFactory.createForTenant(tenantId)
            ├─ TenantCheckpointerFactory.createForTenant(tenantId, sessionId)
            └─ TenantSkillManager.listSkills(tenantId, sessionId)
          → TenantExecutionContext.set(ctx) [ThreadLocal]
            → ReActAgent 使用注入资源（不感知 tenantId）
          → TenantExecutionContext.remove() [finally]
```

**特点**：单向线性穿刺，tenantId 是核心驱动力，所有隔离逻辑围绕 tenantId 展开。

### 4.2 agentscope-java IsolationScope 穿刺

```
HarnessAgent Builder 配置 IsolationScope
  → SandboxContext.isolationScope
  → SandboxFilesystemSpec.isolationScope
  → RemoteFilesystemSpec.isolationScope
    → RuntimeContext(userId, sessionId)
      → SandboxIsolationKey.resolve(scope, ctx, agentId)
        → 确定 (scope, value) 二元组
          → 影响以下所有通道:
            ├─ SessionSandboxStateStore.slotSessionId(key)
            │    → sandbox/session/{sid} | sandbox/user/{agentId}/{uid} | ...
            ├─ NamespaceFactory (IsolationScope.toNamespaceFactory())
            │    → [agents, agentId, sessions, sid] | [agents, agentId, users, uid] | ...
            ├─ SandboxExecutionGuard.tryEnter(key)
            │    → Redis: agentscope:sandbox:lock:{scope}:{value}
            ├─ MemoryFlushMiddleware.timerKeyFor(ctx)
            │    → throttle key = scope:value
            └─ WorkspaceSkillRepository (via NamespaceFactory)
                 → 按命名空间隔离 Skill
```

**特点**：多通道并行散射，IsolationScope 是枚举驱动，RuntimeContext 提供身份字段，各通道独立解析但语义一致。

### 4.3 穿刺机制差异

| 维度 | agent-core-java | agentscope-java |
|------|----------------|-----------------|
| 驱动键 | 单一 tenantId | scope + userId/sessionId/agentId |
| 传递方式 | ThreadLocal (TenantExecutionContext) | RuntimeContext + NamespaceFactory 函数式 |
| 穿刺方向 | 线性（从入口到各 Factory） | 散射（IsolationScope 同时影响多个子系统） |
| 运行时可变性 | 每次 invoke 重新注入 | 每次 call 动态解析 NamespaceFactory |
| 上下文清理 | finally 块中 remove ThreadLocal | 无需显式清理（无状态函数式） |

---

## 5. 存储介质与 Key 格式对比

### 5.1 Workspace 存储

| 项目 | 存储介质 | Key/路径格式 | 说明 |
|------|---------|-------------|------|
| agent-core-java | 本地磁盘 | `{baseDataDir}/tenants/{tenantId}/workspace/` | 物理目录隔离 |
| agentscope-java | BaseStore（KV抽象） | `agents/{agentId}/users/{userId}/` 或 `agents/{agentId}/sessions/{sid}/` | 逻辑命名空间隔离 |

### 5.2 State/Checkpointer 存储

| 项目 | 存储介质 | Key 格式 | 说明 |
|------|---------|---------|------|
| agent-core-java (Redis) | Redis | `deepagent:{tenantId}:{sessionId}` | 字符串拼接 |
| agent-core-java (InMemory) | JVM堆 | `agentStores` Map 中的 key | 共享 Map |
| agentscope-java | AgentStateStore接口 | `(userId=null, sessionId=slotSessionId)` | 结构化二元组 |
| agentscope-java (Redis) | Redis | userId + sessionId 组合 | Jedis/Redisson |
| agentscope-java (MySQL/PG) | 关系数据库 | userId + sessionId 联合查询 | 分布式 |

### 5.3 Sandbox 状态存储

| 项目 | 存储介质 | Key 格式 | 说明 |
|------|---------|---------|------|
| agent-core-java | 无独立 Sandbox 状态存储 | — | Sandbox 模式通过 isolationKey 路由，无持久化 |
| agentscope-java | AgentStateStore | SESSION: `sandbox/session/{sid}` | |
| | | USER: `sandbox/user/{agentId}/{uid}` | |
| | | AGENT: `sandbox/agent/{agentId}` | |
| | | GLOBAL: `sandbox/global` | |

### 5.4 文件系统后端支持

| 后端 | agent-core-java | agentscope-java |
|------|----------------|-----------------|
| 本地磁盘 | ✅ | ✅ (LocalFilesystem) |
| Redis | ✅ (Checkpointer) | ✅ (RedisStore + RedisAgentStateStore + RedisSandboxExecutionGuard) |
| MySQL | ❌ | ✅ (JdbcStore + MysqlAgentStateStore + JdbcSandboxExecutionGuard) |
| PostgreSQL | ❌ | ✅ (PostgresBaseStore + PostgresAgentStateStore + PostgresSandboxExecutionGuard) |
| OSS | ❌ | ✅ (OssBaseStore + OssAgentStateStore) |
| COS | ❌ | ✅ (CosBaseStore + CosAgentStateStore) |
| SQLite | ❌ | ✅ (SqliteBaseStore, 示例级) |
| Docker | ✅ (SandboxGateway) | ✅ (DockerSandbox) |
| E2B | ❌ | ✅ |
| Kubernetes | ❌ | ✅ |
| Daytona | ❌ | ✅ |
| AgentRun | ❌ | ✅ |

---

## 6. 配置项对比

### 6.1 agent-core-java 配置

| 配置项 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `baseDataDir` | Path | `.` | 租户数据根目录 |
| `X-Tenant-Id` | HTTP Header | 无 | 请求级租户标识 |
| `maxTmpSizeBytes` | long | 500MB | 每租户临时文件上限 |
| `tmpTtl` | Duration | 24h | 临时文件过期时间 |
| `sandboxRoot` | List\<Path\> | 动态 | 绑定到租户 workspace |
| `restrictToSandbox` | boolean | true | 限制文件操作在沙箱内 |
| `isolationKey` | String | 动态 | Sandbox 模式容器隔离键 |

### 6.2 agentscope-java 配置

| 配置项 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `isolationScope` | IsolationScope | USER | 隔离作用域 |
| `anonymousUserId` | String | `_default` | userId 缺失时的回退值 |
| `executionGuard` | SandboxExecutionGuard | noop() | Sandbox 并发执行锁 |
| `workspaceProjectionEnabled` | boolean | false | 是否将宿主文件注入 Sandbox |
| `workspaceMode` | WorkspaceMode | ISOLATED | 子Agent 工作空间模式 |
| `dataagent.sandbox.idle-ttl-min` | int | — | DataAgent Sandbox 空闲超时 |
| `dataagent.sandbox.eviction-poll-sec` | int | — | DataAgent 驱逐轮询间隔 |

---

## 7. 并发安全对比

| 场景 | agent-core-java | agentscope-java |
|------|----------------|-----------------|
| 多请求同租户 | ThreadLocal 隔离，每次 invoke 独立实例 | NamespaceFactory 无状态，每次 call 动态解析 |
| 同作用域并发写入 Sandbox | 无分布式锁机制 | SandboxExecutionGuard: Redis/PG/MySQL 分布式锁 |
| 共享 Sandbox 状态竞态 | 未处理 | Lua CAS 脚本（Redis） + advisory lock（PG） + GET_LOCK（MySQL） |
| Memory 并发刷盘 | 未处理 | 按 IsolationScope 分节流窗口，AGENT/GLOBAL 共享窗口串行化 |
| InMemoryCheckpointer 竞态 | 共享 Map，无保护 | — |

---

## 8. 安全防护对比

| 防护维度 | agent-core-java | agentscope-java |
|---------|----------------|-----------------|
| **路径穿越** | TenantPathValidator: normalize() + toRealPath() 双重校验 | PathPolicy: 白名单制度 |
| **软链接攻击** | toRealPath() 二次校验 | — |
| **Sandbox 逃逸** | restrictToSandbox=true | Sandbox 容器天然隔离 |
| **跨租户数据访问** | sandboxRoot 绑定 + 路径校验 | 命名空间隔离（KV Store 无物理路径概念） |
| **并发状态覆盖** | 无锁 | 分布式锁（Redis/PG/MySQL） |

---

## 9. 向后兼容对比

| 维度 | agent-core-java | agentscope-java |
|------|----------------|-----------------|
| 降级策略 | tenantId 为空 → shared/ 目录 | USER scope 无 userId → SESSION scope |
| 现有代码影响 | 不携带 X-Tenant-Id 行为不变 | IsolationScope 可配置，默认 USER |
| Checkpointer 兼容 | 无 tenantId 时 key 格式与旧版一致 | AgentStateStore 二元组，userId=null 为单租户 |
| 配置侵入 | 增量配置，不改已有配置 | Builder 模式，scope 可选配置 |

---

## 10. 代码量与复杂度对比

### 10.1 核心实现类

| 项目 | 核心类数量 | 代码行数(估) | 说明 |
|------|-----------|-------------|------|
| agent-core-java | 8 | ~400 | 简洁直接，每个类职责单一 |
| agentscope-java | 20+ | ~3000+ | 体系庞大，多层抽象 |

### 10.2 核心类对比

| 职责 | agent-core-java | agentscope-java |
|------|----------------|-----------------|
| 隔离标识 | TenantContext (17行) | IsolationScope (127行) + SandboxIsolationKey (140行) |
| 上下文传递 | TenantExecutionContext (34行) | RuntimeContext (框架核心) |
| Workspace 管理 | TenantWorkspaceManager (54行) | WorkspaceManager (1024行) + PathPolicy + WorkspaceMode |
| 系统操作隔离 | TenantSysOpFactory (72行) | SandboxContext + SandboxManager + 5种Sandbox实现 |
| 检查点隔离 | TenantCheckpointerFactory (41行) | AgentStateStore接口 + 7种实现 |
| Skill 隔离 | TenantSkillManager (40行) | WorkspaceSkillRepository |
| 路径安全 | TenantPathValidator (34行) | PathPolicy |
| 资源配额 | TenantResourceQuota (57行) | 无独立类（依赖容器生命周期） |
| 并发控制 | 无 | SandboxExecutionGuard + 3种分布式实现 |
| 文件系统 | 无独立类（通过SysOp间接隔离） | RemoteFilesystem + NamespaceFactory + CompositeFilesystem + OverlayFilesystem |
| 状态持久化 | 无（依赖Checkpointer） | SessionSandboxStateStore |

---

## 11. 产品级多租户方案对比

### 11.1 agent-core-java 方案

```
企业多租户模型：
  单 JVM 进程，100~1000 租户
  tenantId 驱动，无状态动态隔离（方案B）
  每次 invoke 动态注入租户资源
  内存开销 O(1)
```

### 11.2 agentscope-java 方案

```
多粒度作用域模型：
  分布式部署，多副本
  IsolationScope 枚举驱动，运行时可配
  支持 Docker/K8S/E2B 等多种 Sandbox 后端
  支持 Redis/PG/MySQL/OSS/COS 等多种存储后端
  分布式锁保证并发安全

DataAgent 产品级实现：
  per-(userId, agentId) Docker 容器
  UserSandboxRegistry 管理容器生命周期
  支持 idle TTL + 后台驱逐
  多副本需 sticky session by userId
```

---

## 12. 总结

### 12.1 核心差异一句话

> **agent-core-java 用"租户 ID"做目录级硬隔离，agentscope-java 用"作用域枚举"做命名空间级软隔离。**

### 12.2 各自优势

| agent-core-java 优势 | agentscope-java 优势 |
|---------------------|---------------------|
| 简洁直接，8个类即完成隔离 | 多粒度可选（4级作用域） |
| 资源配额主动管控 | 分布式并发安全（分布式锁） |
| 路径穿越 + 软链接双重防护 | 存储后端极度丰富（7+种） |
| 面向企业多租户场景直击痛点 | Sandbox 后端丰富（5+种） |
| 合并式 Skill 加载更灵活 | 子Agent 工作空间隔离 |
| 改动量小，侵入性低 | Memory 隔离更完善 |
| | 外部记忆系统多租户支持 |
| | 产品级 DataAgent 已落地 |

### 12.3 互为借鉴建议

| 从 agentscope-java 借鉴 | 从 agent-core-java 借鉴 |
|-------------------------|------------------------|
| 多粒度 IsolationScope（不只是 tenantId） | 资源配额主动管控（TenantResourceQuota） |
| 分布式并发锁 | 路径穿越 + 软链接防护 |
| 更多存储后端支持 | Skill 合并加载模式 |
| Sandbox 状态持久化 | 临时文件 TTL 清理 |
| Memory 隔离 | 租户目录自动初始化 |
