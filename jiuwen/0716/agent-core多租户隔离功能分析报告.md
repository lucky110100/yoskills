# agent-core 多租户数据/资源隔离功能分析报告

> 分析日期：2026-07-16
> 项目范围：agent-core (Python) / agent-core-java / agent-runtime / agentscope-java
> 分析方法：源码审读 + 设计文档交叉验证

---

## 1. 总体结论

**多租户隔离功能已实现**，但实现分布在多个子项目中，成熟度不同：

| 子项目 | 语言 | 多租户状态 | 成熟度 |
|--------|------|-----------|--------|
| agent-core-java | Java | **完整实现**（8 个生产类 + 10 个测试类） | 高 |
| agent-runtime | Python | HTTP 层租户中间件（X-User-ID / X-Space-ID） | 中 |
| agentscope-java | Java | IsolationScope 枚举（SESSION/USER/AGENT/GLOBAL） | 高 |
| agent-core (Python) | Python | **未实现** tenant-based 隔离，仅有 session 级隔离 | 低 |

核心实现集中在 **agent-core-java**，Python 版 agent-core 尚未对齐。

---

## 2. 整体架构图

```
┌─────────────────────────────────────────────────────────────────────┐
│                        外部请求入口                                  │
│   HTTP Header: X-Tenant-Id / X-User-ID / X-Space-ID               │
└─────────────┬───────────────────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────────────────┐
│  agent-runtime (Python FastAPI)                                     │
│  ┌─────────────────────────────────────────┐                        │
│  │ TenantContextMiddleware                  │                        │
│  │  • 提取 X-User-ID → user_id             │                        │
│  │  • 提取 X-Space-ID → space_id           │                        │
│  │  • 可选 require_tenant=True 强制校验     │                        │
│  │  • 注入 request.state                    │                        │
│  └────────────┬────────────────────────────┘                        │
│               │ get_tenant_context(request)                         │
│               ▼                                                      │
│  API Endpoints: deploy / list / get / delete                        │
│  • 按 user_id + space_id 过滤部署查询                               │
└─────────────┬───────────────────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────────────────┐
│  agent-core-java (DeepAgent.invoke)                                 │
│                                                                     │
│  ① 提取 TenantContext → tenantId                                    │
│  ② TenantWorkspaceManager.initializeTenant(tenantId)                │
│  ③ 构建隔离资源（四件套）:                                           │
│     ├─ Workspace  ── tenants/{tenantId}/workspace                   │
│     ├─ SysOperation ── sandboxRoot 绑定租户目录                      │
│     ├─ Checkpointer ── key前缀 tenantId:sessionId                   │
│     └─ SkillManager ── 全局公共 + 租户私有                           │
│  ④ TenantExecutionContext.set(ctx)  ← ThreadLocal                  │
│  ⑤ ReActAgent 执行（不感知租户，使用注入的隔离资源）                  │
│  ⑥ TenantExecutionContext.remove()  ← finally                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 3. tenant_id 传递链路（穿刺分析）

### 3.1 完整传递路径

```
HTTP Request (header: X-Tenant-Id / X-User-ID / X-Space-ID)
  │
  ├─ agent-runtime 路径:
  │    TenantContextMiddleware.dispatch()
  │      → request.state.user_id / request.state.space_id
  │      → get_tenant_context(request) → (user_id, space_id)
  │      → DeployAgentParams(user_id=..., space_id=...)
  │      → DeploymentManager（按租户过滤部署记录）
  │
  └─ agent-core-java 路径:
       Controller 层
         → 提取 X-Tenant-Id header
         → 构建 TenantContext(tenantId, metadata)
         → Session 绑定 TenantContext
           → DeepAgent.invoke(inputs, session)
             → session.getTenantContext()
             → tenantId 穿刺到以下四条隔离通道:
               ├─ TenantWorkspaceManager.resolveWorkspace(tenantId)
               ├─ TenantSysOpFactory.createForTenant(tenantId)
               ├─ TenantCheckpointerFactory.createForTenant(tenantId, sessionId)
               └─ TenantSkillManager.listSkills(tenantId, sessionId)
             → TenantExecutionContext.set(tenantId + 隔离资源)
               → ReActAgent 使用 ThreadLocal 中的隔离资源
```

### 3.2 传递层次

| 层次 | 传递方式 | 数据结构 |
|------|---------|---------|
| HTTP → Controller | Header 提取 | `X-Tenant-Id` 字符串 |
| Controller → Session | 构造绑定 | `TenantContext(tenantId, metadata)` |
| Session → DeepAgent | `session.getTenantContext()` | `TenantContext` |
| DeepAgent → 隔离资源 | 拆解 tenantId 传入各 Factory | `String tenantId` |
| 隔离资源 → 执行上下文 | `TenantExecutionContext.set(ctx)` | ThreadLocal |
| 执行上下文 → ReActAgent | `TenantExecutionContext.get()` | 隐式使用 |

### 3.3 关键设计：ReActAgent 不感知租户

tenant_id 的"穿刺"在 **DeepAgent 层**完成，ReActAgent 完全不感知租户概念。它只使用注入的 Workspace、SysOperation、Checkpointer，而这些已经按 tenantId 隔离。

---

## 4. 新增配置项

### 4.1 agent-core-java 配置

| 配置项 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `baseDataDir` | Path | `.` (当前目录) | 租户数据根目录，所有租户目录挂在其下 |
| `X-Tenant-Id` | HTTP Header | 无 | 请求级租户标识，Controller 层提取 |
| `require_tenant` | boolean | `false` | 是否强制要求租户信息（agent-runtime 侧） |

### 4.2 agent-runtime 配置

| 配置项 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `require_tenant` | bool | `False` | TenantContextMiddleware 是否强制校验租户 Header |
| `X-User-ID` | HTTP Header | 无 | 用户级租户标识 |
| `X-Space-ID` | HTTP Header | 无 | 空间级租户标识 |

### 4.3 TenantResourceQuota 配置

| 配置项 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `maxTmpSizeBytes` | long | 500MB (524,288,000) | 每租户临时文件上限 |
| `tmpTtl` | Duration | 24 小时 | 临时文件过期时间 |

### 4.4 SysOperation 隔离配置

| 配置项 | 类型 | 说明 |
|--------|------|------|
| `sandboxRoot` | List\<Path\> | 沙箱根目录（绑定到租户 workspace） |
| `restrictToSandbox` | boolean | 是否限制文件操作在沙箱内（多租户下为 true） |
| `isolationKey` / `customId` | String | Sandbox 模式下的远端容器隔离键 |

---

## 5. 隔离的资源清单

### 5.1 已隔离资源

| 资源 | 隔离方式 | 隔离粒度 | 实现类 |
|------|---------|---------|--------|
| **Workspace（工作空间）** | 目录路径隔离 | tenant | TenantWorkspaceManager |
| **临时文件（tmp）** | 子目录隔离 + TTL 清理 | tenant | TenantResourceQuota |
| **Skill（技能）** | 全局公共 + 租户私有合并 | tenant | TenantSkillManager |
| **Checkpointer（检查点）** | Key 前缀隔离 `tenantId:sessionId` | tenant+session | TenantCheckpointerFactory |
| **SysOperation（系统操作）** | sandboxRoot / isolationKey 绑定 | tenant | TenantSysOpFactory |
| **文件读写路径** | sandboxRoot + restrictToSandbox 校验 | tenant | TenantPathValidator |
| **Shell/代码执行工作目录** | workDir 绑定租户目录 | tenant | TenantSysOpFactory |
| **Sandbox 远端容器** | isolationKey 路由隔离 | tenant | TenantSysOpFactory |

### 5.2 未隔离资源（按设计不隔离）

| 资源 | 原因 |
|------|------|
| 智能体配置文件 | 全局共享，不按租户区分 |
| 运行日志 | 运维类数据，不涉及租户数据 |
| config/ 目录 | 配置不隔离 |
| LLM 模型配置 | 共享模型实例 |

### 5.3 待完善资源

| 资源 | 当前状态 | 问题 |
|------|---------|------|
| Checkpointer 注入链路 | 0715 设计规格已出，未完全合入 | TenantCheckpointerFactory 创建的实例未注入 TenantExecutionContext |
| preRun/postRun 一致性 | 0715 设计规格已出，未修复 | preRun 使用全局 Checkpointer，postRun 使用 AgentSession 内部实例 |
| InMemoryCheckpointer | 全局单例，未按租户隔离 | 不同租户共享 agentStores Map |

---

## 6. 资源的层级结构划分

### 6.1 隔离层级模型

```
┌────────────────────────────────────────────────┐
│ GLOBAL（全局共享）                               │
│  • 智能体配置文件                               │
│  • 运行日志                                     │
│  • LLM 模型配置                                 │
│  • 全局公共 Skills                              │
├────────────────────────────────────────────────┤
│ TENANT（租户级隔离）                             │
│  • Workspace 目录                               │
│  • 临时文件（tmp）                               │
│  • 租户私有 Skills                              │
│  • Checkpointer（key 含 tenantId 前缀）         │
│  • SysOperation（sandboxRoot 绑定租户目录）     │
│  • 资源配额（500MB tmp / 租户）                  │
├────────────────────────────────────────────────┤
│ SESSION（会话级隔离）                            │
│  • Checkpointer 中 sessionId 部分               │
│  • Sandbox isolation_key（部分模式）             │
│  • Memory scope_id（Python 侧）                 │
│  • Context session isolation（Python 侧）       │
├────────────────────────────────────────────────┤
│ AGENT（智能体级共享，agentscope-java）            │
│  • 同 Agent 跨用户/会话共享 Sandbox 状态         │
│  • 远端文件系统命名空间                          │
└────────────────────────────────────────────────┘
```

### 6.2 agentscope-java IsolationScope 层级

| Scope | 隔离维度 | 降级策略 | 使用场景 |
|-------|---------|---------|---------|
| `USER` | 同 userId 共享 | userId 为空 → SESSION | **默认**，用户级数据持久化 |
| `SESSION` | 按 sessionId 隔离 | 无 sessionId → 新建 | 会话级临时隔离 |
| `AGENT` | 同 agent name 共享 | 不降级（agent name 编译时固定） | Agent 级状态复用 |
| `GLOBAL` | 全局共享 | 不降级 | 谨慎使用，存在写竞争 |

### 6.3 层级选择逻辑

```
请求到达
  │
  ├─ 有 tenantId？
  │    ├─ 是 → TENANT 级隔离（workspace / sysop / checkpointer / skill）
  │    └─ 否 → 降级到 shared/ 目录（向后兼容）
  │
  ├─ 有 sessionId？
  │    ├─ 是 → SESSION 级隔离（checkpointer key 含 sessionId）
  │    └─ 否 → 使用默认 session
  │
  └─ IsolationScope（agentscope-java）？
       ├─ USER → userId 命名空间前缀
       ├─ SESSION → sessionId 命名空间前缀
       ├─ AGENT → 无前缀（workspace 已按 agent 隔离）
       └─ GLOBAL → 无前缀
```

---

## 7. 资源存储介质

### 7.1 存储介质分布

| 资源 | 存储介质 | 隔离实现 | 路径/Key 格式 |
|------|---------|---------|--------------|
| Workspace | **本地磁盘** | 目录路径隔离 | `{baseDataDir}/tenants/{tenantId}/workspace/` |
| 临时文件 | **本地磁盘** | 子目录 + TTL 清理 | `{baseDataDir}/tenants/{tenantId}/workspace/tmp/` |
| Skills | **本地磁盘** | 目录隔离 + 合并加载 | `{baseDataDir}/tenants/{tenantId}/workspace/skills/` |
| Checkpointer (Redis) | **Redis** | Key 前缀隔离 | `deepagent:{tenantId}:{sessionId}` |
| Checkpointer (InMemory) | **JVM 堆内存** | Key 前缀隔离（共享 Map） | `agentStores` Map 中的 key 前缀 |
| Checkpointer (Persistence) | **本地磁盘** | Key 前缀隔离 | 同 Redis 格式 |
| Sandbox 容器 | **远端容器** | isolationKey 路由 | `{tenantId}_{baseCustomId}` |
| Memory 向量 | **Milvus** | scope_id 隔离（Python 侧） | 按 scope_id 区分 |
| 部署记录 | **MySQL / SQLite** | user_id + space_id 过滤 | SQL WHERE 条件 |

### 7.2 目录结构详图

```
{baseDataDir}/                                   ← 配置项 baseDataDir
├── tenants/                                      ← 租户数据根
│   ├── company-a/                                ← 租户 A
│   │   ├── workspace/                            ← Workspace.rootPath
│   │   │   ├── memory/                           ← MemoryRail 向量存储
│   │   │   ├── todo/                             ← Todo 数据
│   │   │   ├── skills/                           ← 租户私有 Skills
│   │   │   ├── agents/                           ← 子 Agent
│   │   │   └── tmp/                              ← 临时文件（500MB上限，24h TTL）
│   │   ├── checkpoints/                          ← 检查点存储（Persistence 模式）
│   │   └── .plans/                               ← 计划文件
│   │
│   └── company-b/                                ← 租户 B
│       ├── workspace/
│       │   ├── memory/
│       │   ├── todo/
│       │   ├── skills/
│       │   ├── agents/
│       │   └── tmp/
│       ├── checkpoints/
│       └── .plans/
│
├── shared/                                       ← 全局共享（无 tenantId 时降级）
│   └── workspace/
│       ├── skills/                               ← 全局公共 Skills
│       └── ...
│
└── config/                                       ← 智能体配置（不隔离）
```

### 7.3 Redis Key 设计

```
租户 A 会话 1:  deepagent:company-a:sess-123
租户 A 会话 2:  deepagent:company-a:sess-456
租户 B 会话 1:  deepagent:company-b:sess-123
共享会话:       deepagent:sess-789               ← 无 tenantId 前缀
```

---

## 8. 核心实现类详解

### 8.1 类关系图

```
TenantContext ──────────► TenantExecutionContext (ThreadLocal)
     │                          │
     │                          ├── Workspace (由 TenantWorkspaceManager 解析)
     │                          ├── SysOperation (由 TenantSysOpFactory 创建)
     │                          └── Checkpointer (由 TenantCheckpointerFactory 创建)
     │
     ├── TenantWorkspaceManager
     │       ├── resolveWorkspace(tenantId) → Workspace
     │       ├── resolveTmpDir(tenantId) → Path
     │       └── initializeTenant(tenantId) → void
     │
     ├── TenantSysOpFactory
     │       ├── createForTenant(tenantId) → SysOperation (LOCAL)
     │       └── createSandboxForTenant(tenantId, config) → SysOperation (SANDBOX)
     │
     ├── TenantCheckpointerFactory
     │       └── createForTenant(tenantId, sessionId) → Checkpointer
     │               └── sessionId = tenantId + ":" + sessionId
     │
     ├── TenantSkillManager
     │       └── listSkills(tenantId, sessionId) → List<Skill>
     │               └── globalSkillManager.getAll() + tenantSkillDir
     │
     ├── TenantPathValidator
     │       └── validate(tenantId, baseDataDir, requestedPath)
     │               ├── normalize 路径穿越校验
     │               └── toRealPath 软链接攻击防护
     │
     └── TenantResourceQuota
             └── cleanupExpiredTmp(tenantId)
                     └── maxTmpSizeBytes=500MB, tmpTtl=24h
```

### 8.2 各类职责与源码位置

| 类名 | 源码路径 | 职责 |
|------|---------|------|
| TenantContext | `agent-core-java/.../multitenant/TenantContext.java` | 租户上下文数据持有（tenantId + metadata） |
| TenantExecutionContext | `agent-core-java/.../multitenant/TenantExecutionContext.java` | ThreadLocal 执行上下文（tenantId + workspace + sysOp + checkpointer） |
| TenantWorkspaceManager | `agent-core-java/.../multitenant/TenantWorkspaceManager.java` | 解析/初始化租户目录结构 |
| TenantSysOpFactory | `agent-core-java/.../multitenant/TenantSysOpFactory.java` | 创建租户隔离的 SysOperation（LOCAL + SANDBOX 两种模式） |
| TenantCheckpointerFactory | `agent-core-java/.../multitenant/TenantCheckpointerFactory.java` | 创建租户前缀的 Checkpointer（支持 InMemory/Redis/Persistence） |
| TenantSkillManager | `agent-core-java/.../multitenant/TenantSkillManager.java` | 合并全局公共 + 租户私有 Skills |
| TenantPathValidator | `agent-core-java/.../multitenant/TenantPathValidator.java` | 防止跨租户路径穿越和软链接攻击 |
| TenantResourceQuota | `agent-core-java/.../multitenant/TenantResourceQuota.java` | 每租户临时文件配额和 TTL 清理 |

---

## 9. 安全防护机制

### 9.1 路径穿越防护（TenantPathValidator）

```java
// 第一层：normalize() 校验
Path normalized = requestedPath.normalize().toAbsolutePath();
if (!normalized.startsWith(tenantRoot)) {
    throw new SecurityException("Cross-tenant access denied");
}

// 第二层：toRealPath() 校验（防软链接攻击）
Path resolvedTenantRoot = tenantRoot.toRealPath();
Path resolved = normalized.toRealPath();
if (!resolved.startsWith(resolvedTenantRoot)) {
    throw new SecurityException("Cross-tenant symlink access denied");
}
```

**防护范围**：
- `../` 路径穿越
- 符号链接指向其他租户目录
- 绝对路径绕过

### 9.2 Sandbox 限制（restrictToSandbox）

```java
LocalWorkConfig config = LocalWorkConfig.builder()
    .workDir(tenantRoot.toString())
    .sandboxRoot(List.of(tenantRoot.toString()))
    .restrictToSandbox(true)        // 关键：限制文件操作不可越出租户目录
    .build();
```

### 9.3 并发安全

| 场景 | 方案 |
|------|------|
| 多请求同时初始化同一租户目录 | `Files.createDirectories` 天然幂等 |
| 同一租户并发写入 | Redis 天然支持原子操作；本地文件由 OS 文件锁保证 |
| TenantExecutionContext 跨线程 | ThreadLocal 隔离，TaskLoop 内线程继承上下文 |
| 每次 invoke 创建独立 SysOperation | 无共享可变状态，天然并发安全 |

---

## 10. 各子项目隔离对比

### 10.1 agent-core-java vs agent-core (Python)

| 维度 | agent-core-java | agent-core (Python) |
|------|----------------|---------------------|
| 多租户隔离 | 完整实现（8 类） | **未实现** |
| 隔离键 | tenantId（显式） | session_id（隐式） |
| Workspace 隔离 | `tenants/{tenantId}/workspace` | 无 |
| Checkpointer 隔离 | `tenantId:sessionId` key 前缀 | 无 |
| Skill 隔离 | 全局 + 租户私有合并 | 无 |
| 路径安全防护 | TenantPathValidator | 无 |
| 资源配额 | TenantResourceQuota | 无 |
| 沙箱隔离 | sandboxRoot 绑定租户目录 | isolation_key（基于 session_id） |
| 向后兼容 | tenantId 为空降级 shared/ | N/A |

### 10.2 agent-runtime 租户中间件

| 特性 | 实现 |
|------|------|
| 提取方式 | HTTP Header：`X-User-ID` + `X-Space-ID` |
| 中间件 | `TenantContextMiddleware`（Starlette BaseHTTPMiddleware） |
| 强制校验 | `require_tenant` 参数，当前设为 `False`（测试阶段） |
| 注入方式 | `request.state.user_id` / `request.state.space_id` |
| 使用范围 | 部署管理 API（deploy / list / get / delete） |
| 数据库过滤 | 按 `user_id` + `space_id` 过滤部署记录 |
| 向下穿透 | **未完成**——tenant context 未传递到 agent-core Python SDK |

### 10.3 agentscope-java IsolationScope

| 特性 | 实现 |
|------|------|
| 隔离模型 | 枚举：SESSION / USER / AGENT / GLOBAL |
| 默认作用域 | USER（userId 缺失时降级为 SESSION） |
| 影响范围 | Sandbox 状态持久化 + 远端文件系统命名空间 |
| 命名空间工厂 | `toNamespaceFactory()` → 基于 RuntimeContext 生成前缀 |
| 并发语义 | 顺序复用共享（非实时共享），每次调用独立容器 |

---

## 11. 已知问题与待改进项

### 11.1 已识别问题（0715 设计规格）

| 问题 | 严重程度 | 状态 |
|------|---------|------|
| preRun 与 postRun 使用不同 Checkpointer 实例 | 高 | 设计规格已出，待实现 |
| TenantCheckpointerFactory 未注入 TenantExecutionContext | 高 | 设计规格已出，待实现 |
| InMemoryCheckpointer 全局单例不隔离 | 中 | 设计规格已出，待实现 |
| TenantCheckpointerFactory 硬编码 in_memory 类型 | 中 | **已修复**（resolveCheckpointerType） |

### 11.2 跨项目断点

| 断点 | 说明 |
|------|------|
| agent-runtime → agent-core (Python) | tenant context 未向下传递，Python SDK 无法感知租户 |
| agent-runtime (X-User-ID) vs agent-core-java (X-Tenant-Id) | Header 命名不统一 |
| agent-core (Python) 无多租户 | Python 版缺少对齐 Java 版的隔离能力 |

### 11.3 改进建议

1. **统一租户标识 Header**：建议 agent-runtime 的 `X-User-ID` + `X-Space-ID` 与 agent-core-java 的 `X-Tenant-Id` 对齐
2. **agent-core (Python) 多租户对齐**：参照 Java 版 8 类实现，在 Python 侧补充 TenantWorkspaceManager、TenantCheckpointerFactory 等
3. **agent-runtime → agent-core 传递链路打通**：将 tenant context 从 HTTP 层传递到 Python SDK
4. **Checkpointer 注入链路合入**：0715 设计规格需尽快实现
5. **require_tenant 生产化**：agent-runtime 中间件当前 `require_tenant=False`，生产环境应设为 True

---

## 12. 测试覆盖情况

### 12.1 agent-core-java 测试矩阵

| 测试类 | 类型 | 覆盖点 |
|--------|------|--------|
| TenantContextTest | UT | TenantContext 构造、字段访问 |
| TenantWorkspaceManagerTest | UT | 路径解析、目录创建、幂等性 |
| TenantSysOpFactoryTest | UT | LOCAL/SANDBOX 模式隔离 |
| TenantCheckpointerFactoryTest | UT | Key 前缀隔离、多类型支持 |
| TenantSkillManagerTest | UT | 全局+租户 Skill 合并、租户间不可见 |
| TenantPathValidatorTest | UT | 路径穿越、软链接防护 |
| TenantResourceQuotaTest | UT | 临时文件过期清理 |
| TenantExecutionContextTest | UT | ThreadLocal 设置/清理/跨线程隔离 |
| MultiTenantIsolationStTest | ST | 综合隔离验证（workspace/context/path/skill/quota） |
| MultiTenantE2eStTest | ST | 端到端（含真实 LLM 调用） |

### 12.2 agent-runtime 测试

- 中间件单元测试：验证 Header 提取、强制校验、降级行为
- API 端点测试：验证租户过滤查询

---

## 13. 关键源码索引

| 文件 | 路径 |
|------|------|
| TenantContext.java | `agent-core-java/src/main/java/com/openjiuwen/core/multitenant/TenantContext.java` |
| TenantExecutionContext.java | `agent-core-java/src/main/java/com/openjiuwen/core/multitenant/TenantExecutionContext.java` |
| TenantWorkspaceManager.java | `agent-core-java/src/main/java/com/openjiuwen/core/multitenant/TenantWorkspaceManager.java` |
| TenantSysOpFactory.java | `agent-core-java/src/main/java/com/openjiuwen/core/multitenant/TenantSysOpFactory.java` |
| TenantCheckpointerFactory.java | `agent-core-java/src/main/java/com/openjiuwen/core/multitenant/TenantCheckpointerFactory.java` |
| TenantSkillManager.java | `agent-core-java/src/main/java/com/openjiuwen/core/multitenant/TenantSkillManager.java` |
| TenantPathValidator.java | `agent-core-java/src/main/java/com/openjiuwen/core/multitenant/TenantPathValidator.java` |
| TenantResourceQuota.java | `agent-core-java/src/main/java/com/openjiuwen/core/multitenant/TenantResourceQuota.java` |
| IsolationScope.java | `agentscope-java/agentscope-harness/src/main/java/io/agentscope/harness/agent/IsolationScope.java` |
| tenant.py | `agent-runtime/server/openjiuwen_runtime/server/middleware/tenant.py` |
| main.py | `agent-runtime/server/openjiuwen_runtime/server/main.py` |
| 多租户数据隔离设计文档 | `yoskills/jiuwen/0714/多租户数据隔离设计文档.md` |
| Checkpointer 多租户设计规格 | `agent-core-java/docs/superpowers/specs/2026-07-15-checkpointer-multitenant-design.md` |
