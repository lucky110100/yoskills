# DeepAgent 多租户数据隔离优化方案 (参考 AgentScope)

## 一、AgentScope 多租户隔离架构解析

### 1.1 核心设计理念

AgentScope 采用 **"无状态 Agent + 动态命名空间"** 架构：

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     HarnessAgent (单实例/无状态)                         │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │                     RuntimeContext (per-call)                    │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │ │
│  │  │   userId     │  │  sessionId   │  │   tenantId   │          │ │
│  │  │  (tenant)    │  │  (session)   │  │  (optional)  │          │ │
│  │  └──────────────┘  └──────────────┘  └──────────────┘          │ │
│  └───────────────────────────────────────────────────────────────────┘ │
│                              ↓                                          │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │              NamespaceFactory (动态命名空间)                      │ │
│  │  根据 IsolationScope 生成 namespace prefix:                        │ │
│  │  • USER → prefix=[userId]                                        │ │
│  │  • SESSION → prefix=[sessionId]                                  │ │
│  │  • AGENT → prefix=[] (共享)                                      │ │
│  │  • GLOBAL → prefix=[] (全局)                                     │ │
│  └───────────────────────────────────────────────────────────────────┘ │
│                              ↓                                          │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │              CompositeFilesystem (分层路由)                        │ │
│  │  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐              │ │
│  │  │ AGENTS.md    │ │ memory/      │ │ sessions/    │              │ │
│  │  │ → store/root │ │ → store/mem  │ │ → store/sess │              │ │
│  │  └──────────────┘ └──────────────┘ └──────────────┘              │ │
│  │  不同路径路由到不同存储段 (segment)                                 │ │
│  └───────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
```

### 1.2 IsolationScope 隔离级别

```java
public enum IsolationScope {
    SESSION,  // 每个会话完全隔离
    USER,     // 同一用户跨会话共享（默认）
    AGENT,    // 同一 Agent 所有用户共享
    GLOBAL    // 全局共享（慎用）
}

// NamespaceFactory 动态生成前缀
IsolationScope.USER.toNamespaceFactory() → rc -> {
    String uid = rc.getUserId();
    return uid != null ? List.of(uid) : List.of(rc.getSessionId());
}
```

### 1.3 存储分层路由 (CompositeFilesystem)

```
workspace/
├── AGENTS.md → RemoteFilesystem (segment="root", namespace=userId)
├── MEMORY.md → RemoteFilesystem (segment="root", namespace=userId)
├── memory/   → RemoteFilesystem (segment="memory", namespace=userId)
├── skills/   → RemoteFilesystem (segment="skills", namespace=userId)
├── knowledge/→ RemoteFilesystem (segment="knowledge", namespace=userId)
├── plans/    → RemoteFilesystem (segment="plans", namespace=userId)
└── agents/<agentId>/
    ├── sessions/ → RemoteFilesystem (segment="sessions", namespace=userId)
    └── tasks/    → RemoteFilesystem (segment="tasks", namespace=userId)

Store key 格式: {namespace}/{segment}/path
例: alice/memory/2024-01-15.md
```

---

## 二、DeepAgent 现有方案 vs AgentScope

### 2.1 架构对比

| 维度 | DeepAgent (现有) | AgentScope |
|------|-----------------|------------|
| **Agent 状态** | 有状态（缓存实例） | 无状态（单实例服务多用户） |
| **隔离方式** | 多实例隔离（TenantAgentManager） | 动态命名空间（NamespaceFactory） |
| **Workspace** | 本地目录 / 外部存储手动加载 | CompositeFilesystem 自动路由 |
| **并发模型** | Semaphore 控制 | 天然并发安全（无共享状态） |
| **扩展性** | 受内存限制 | 水平扩展无限制 |

### 2.2 代码对比

**DeepAgent (TenantAgentManager - 多实例模式)**：
```java
public class TenantAgentManager {
    // 缓存有状态的 Agent 实例
    private final Map<String, TenantAgentHolder> agentCache;
    
    public DeepAgent getOrCreateAgent(TenantContext ctx) {
        String cacheKey = ctx.getCacheKey(); // tenantId + userId
        TenantAgentHolder holder = agentCache.get(cacheKey);
        if (holder != null && !holder.isExpired()) {
            return holder.getAgent();  // 返回缓存的实例
        }
        // 创建新实例（每个租户一个）
        DeepAgent agent = createTenantAgent(ctx);
        agentCache.put(cacheKey, new TenantAgentHolder(agent, ctx));
        return agent;
    }
}
```

**AgentScope (无状态动态隔离)**：
```java
public class HarnessAgent {
    // 单实例，无租户缓存
    private final ReActAgent delegate;
    private final WorkspaceManager workspaceManager;
    
    public Mono<Msg> call(List<Msg> msgs, RuntimeContext ctx) {
        // ctx 包含 userId/sessionId
        // WorkspaceManager 根据 ctx 动态路由到不同 namespace
        return wrappedCall(msgs, ctx, () -> delegate.call(msgs, ctx));
    }
}

// RuntimeContext 动态传入，无需缓存 Agent
RuntimeContext ctx = RuntimeContext.builder()
    .userId("alice")
    .sessionId("session-123")
    .build();
agent.call(msg, ctx);  // 同一实例，不同用户
```

---

## 三、DeepAgent 优化方案 (借鉴 AgentScope)

### 3.1 核心优化：引入 NamespaceFactory 动态隔离

```java
/**
 * 租户命名空间工厂 - 类似 AgentScope 的 NamespaceFactory
 */
@FunctionalInterface
public interface TenantNamespaceFactory {
    /**
     * 根据运行时上下文生成命名空间前缀
     * @param tenantId 租户ID
     * @param userId 用户ID  
     * @param sessionId 会话ID
     * @return 命名空间路径段列表，如 ["company-a", "alice"]
     */
    List<String> createNamespace(String tenantId, String userId, String sessionId);
    
    // 预定义隔离级别
    static TenantNamespaceFactory perUser() {
        return (tenantId, userId, sessionId) -> {
            List<String> ns = new ArrayList<>();
            if (tenantId != null) ns.add("t_" + tenantId);
            if (userId != null) ns.add("u_" + userId);
            return ns;
        };
    }
    
    static TenantNamespaceFactory perSession() {
        return (tenantId, userId, sessionId) -> {
            List<String> ns = new ArrayList<>();
            if (tenantId != null) ns.add("t_" + tenantId);
            if (sessionId != null) ns.add("s_" + sessionId);
            return ns;
        };
    }
}
```

### 3.2 优化 WorkspaceManager：分层路由存储

```java
/**
 * 分层 Workspace 管理器 - 类似 AgentScope CompositeFilesystem
 */
public class TieredWorkspaceManager {
    
    // 不同数据类型路由到不同存储
    private final Map<String, WorkspaceStore> routeStores;
    private final WorkspaceStore defaultStore;
    private final TenantNamespaceFactory namespaceFactory;
    
    public TieredWorkspaceManager(Builder builder) {
        this.routeStores = Map.of(
            "memory/", builder.memoryStore,      // 记忆数据
            "checkpoints/", builder.checkpointStore, // 检查点
            "skills/", builder.skillStore,       // 技能
            "sessions/", builder.sessionStore    // 会话日志
        );
        this.defaultStore = builder.defaultStore;
        this.namespaceFactory = builder.namespaceFactory;
    }
    
    /**
     * 写入文件 - 自动路由到对应存储并应用命名空间
     */
    public void write(String relativePath, byte[] content, 
                      String tenantId, String userId, String sessionId) {
        // 1. 确定路由
        WorkspaceStore store = determineStore(relativePath);
        
        // 2. 生成命名空间前缀
        List<String> namespace = namespaceFactory.createNamespace(tenantId, userId, sessionId);
        
        // 3. 构建存储 key
        String storeKey = buildStoreKey(namespace, relativePath);
        
        // 4. 写入
        store.write(storeKey, content);
    }
    
    /**
     * 读取文件 - 两层读（store优先，本地兜底）
     */
    public byte[] read(String relativePath,
                       String tenantId, String userId, String sessionId) {
        // 1. 尝试从 store 读取（带命名空间）
        List<String> namespace = namespaceFactory.createNamespace(tenantId, userId, sessionId);
        String storeKey = buildStoreKey(namespace, relativePath);
        WorkspaceStore store = determineStore(relativePath);
        
        byte[] content = store.read(storeKey);
        if (content != null) {
            return content;  // store 命中
        }
        
        // 2. 本地 workspace 兜底（用于模板文件）
        return defaultStore.read(relativePath);
    }
    
    private String buildStoreKey(List<String> namespace, String relativePath) {
        return String.join("/", namespace) + "/" + relativePath;
    }
    
    private WorkspaceStore determineStore(String path) {
        return routeStores.entrySet().stream()
            .filter(e -> path.startsWith(e.getKey()))
            .findFirst()
            .map(Map.Entry::getValue)
            .orElse(defaultStore);
    }
}
```

### 3.3 优化 DeepAgent：无状态设计

```java
/**
 * 无状态 DeepAgent - 参考 AgentScope HarnessAgent
 */
public class StatelessDeepAgent {
    
    private final ReActAgent innerAgent;  // 核心推理引擎（无状态）
    private final TieredWorkspaceManager workspaceManager;
    private final SysOperationManager sysOpManager;
    private final CheckpointerManager checkpointerManager;
    
    // 无需缓存租户实例！
    
    public Map<String, Object> run(TaskContext taskCtx) {
        // 1. 从 taskCtx 提取身份
        String tenantId = taskCtx.getTenantId();
        String userId = taskCtx.getUserId();
        String sessionId = taskCtx.getSessionId();
        
        // 2. 构建运行时上下文（类似 RuntimeContext）
        ExecutionContext execCtx = ExecutionContext.builder()
            .tenantId(tenantId)
            .userId(userId)
            .sessionId(sessionId)
            .workspaceManager(workspaceManager)
            .sysOperation(sysOpManager.forTenant(tenantId, userId))
            .checkpointer(checkpointerManager.forSession(tenantId, userId, sessionId))
            .build();
        
        // 3. 执行（每次调用独立上下文）
        return innerAgent.invoke(taskCtx.getQuery(), execCtx);
    }
}

/**
 * 执行上下文 - 封装单次调用的所有租户隔离资源
 */
@Data
@Builder
public class ExecutionContext {
    private final String tenantId;
    private final String userId;
    private final String sessionId;
    private final TieredWorkspaceManager workspaceManager;
    private final SysOperation sysOperation;
    private final Checkpointer checkpointer;
}
```

### 3.4 优化检查点管理：动态命名空间

```java
/**
 * 类似 AgentScope 的 AgentStateStore 设计
 */
public class NamespacedCheckpointerManager {
    
    private final Checkpointer backend;  // Redis / JDBC / File
    private final TenantNamespaceFactory namespaceFactory;
    private final String keyPrefix;
    
    public NamespacedCheckpointer forSession(String tenantId, String userId, String sessionId) {
        List<String> ns = namespaceFactory.createNamespace(tenantId, userId, sessionId);
        String key = keyPrefix + ":" + String.join(":", ns) + ":" + sessionId;
        
        return new NamespacedCheckpointer(backend, key);
    }
}

// 使用示例 - 自动隔离
Checkpointer cp = checkpointerManager.forSession("company-a", "alice", "sess-123");
cp.save(state);

// Redis key: deepagent:t_company-a:u_alice:sess-123
```

### 3.5 优化 SysOperation：动态绑定

```java
/**
 * SysOperation 管理器 - 支持动态租户绑定
 */
public class TenantAwareSysOpManager {
    
    private final SysOperation baseSysOp;
    private final TieredWorkspaceManager workspaceManager;
    
    /**
     * 为指定租户创建隔离的 SysOperation 视图
     */
    public SysOperation forTenant(String tenantId, String userId) {
        // 动态构建工作目录
        Path workDir = workspaceManager.resolveWorkspaceRoot(tenantId, userId);
        
        return SysOperation.builder()
            .mode(OperationMode.LOCAL)
            .workConfig(LocalWorkConfig.builder()
                .workDir(workDir.toString())
                .restrictToSandbox(true)
                .build())
            .build();
    }
}
```

---

## 四、新架构 vs 旧架构对比

### 4.1 架构演进

```
【旧架构 - TenantAgentManager】
┌─────────────────────────────────────────┐
│  TenantAgentManager                     │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐  │
│  │ Agent A │ │ Agent B │ │ Agent C │  │  ← 每个租户一个实例
│  │ (alice) │ │ (bob)   │ │ (carol) │  │
│  │ ·内存   │ │ ·内存   │ │ ·内存   │  │
│  │ ·线程   │ │ ·线程   │ │ ·线程   │  │
│  │ ·状态   │ │ ·状态   │ │ ·状态   │  │
│  └─────────┘ └─────────┘ └─────────┘  │
│  LRU Cache (100 max, 30min TTL)       │
└─────────────────────────────────────────┘
问题：
- 内存占用高（每个 Agent 一个 JVM 对象）
- 并发受限（Semaphore 控制）
- 扩展困难（水平扩展需复制缓存）

【新架构 - StatelessDeepAgent (参考 AgentScope)】
┌─────────────────────────────────────────┐
│  StatelessDeepAgent (单实例)           │
│  ┌───────────────────────────────────┐  │
│  │ ReActAgent (核心推理引擎)         │  │  ← 无状态，所有租户共享
│  └───────────────────────────────────┘  │
│  ┌───────────────────────────────────┐  │
│  │ TieredWorkspaceManager            │  │  ← 动态路由 + 命名空间
│  │  ·memory/ → Redis (namespace)     │  │
│  │  ·sessions/ → Redis (namespace)   │  │
│  │  ·skills/ → OBS (namespace)       │  │
│  └───────────────────────────────────┘  │
│  ┌───────────────────────────────────┐  │
│  │ NamespaceFactory                  │  │  ← userId/sessionId → prefix
│  │  USER: [tenantId, userId]        │  │
│  │  SESSION: [tenantId, sessionId]    │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
优势：
- 内存占用低（单实例）
- 天然并发安全（无共享可变状态）
- 水平扩展友好（无状态可复制）
```

### 4.2 关键改进点

| 改进项 | 旧方案 | 新方案 (参考 AgentScope) |
|--------|--------|------------------------|
| **Agent 实例** | 每租户一个（缓存） | 单实例共享 |
| **隔离机制** | 实例隔离 | 命名空间隔离 |
| **Workspace** | 本地目录 / 手动加载 | TieredWorkspace 自动路由 |
| **检查点** | 手动 key 前缀 | NamespacedCheckpointer 自动生成 |
| **并发** | Semaphore 限制 | 无限制（无状态） |
| **扩展** | 垂直扩展（内存） | 水平扩展（无状态） |

---

## 五、实施路线图

### 阶段 1: 引入 NamespaceFactory（1-2周）

```java
// 1. 新增接口
public interface TenantNamespaceFactory { }

// 2. 改造 WorkspaceProvider 支持命名空间
public interface NamespacedWorkspaceProvider {
    Path loadWorkspace(List<String> namespace);
    void saveWorkspace(List<String> namespace, Path workspace);
}

// 3. 兼容现有代码
```

### 阶段 2: 优化 Checkpointer（1周）

```java
// 改造 TenantCheckpointerSupport
public class NamespacedCheckpointerManager {
    public Checkpointer forSession(String tenantId, String userId, String sessionId);
}
```

### 阶段 3: 无状态 Agent 重构（2-3周）

```java
// 新增 StatelessDeepAgent
public class StatelessDeepAgent {
    public Map<String, Object> run(TaskContext ctx);  // ctx 包含 tenant/user/session
}

// 保留 TenantAgentManager 作为兼容层
```

### 阶段 4: TieredWorkspace 实现（2周）

```java
// 实现分层存储路由
public class TieredWorkspaceManager {
    // memory/ → Redis
    // checkpoints/ → Redis
    // skills/ → OBS/S3
    // sessions/ → JDBC/MySQL
}
```

### 阶段 5: 测试与迁移（1-2周）

- 单元测试：命名空间生成
- 集成测试：多租户隔离
- 性能测试：对比旧方案
- 灰度迁移：逐步切换

---

## 六、代码迁移示例

### 6.1 旧代码（TenantAgentManager）

```java
// 旧代码
TenantContext ctx = TenantContext.builder()
    .tenantId("company-a")
    .userId("alice")
    .build();

DeepAgent agent = TenantAgentManager.getInstance().getOrCreateAgent(ctx);
agent.run(Map.of("query", "Hello", "conversation_id", "sess-1"));
```

### 6.2 新代码（StatelessDeepAgent）

```java
// 新代码 - 单实例，上下文驱动
StatelessDeepAgent agent = StatelessDeepAgent.builder()
    .namespaceFactory(TenantNamespaceFactory.perUser())
    .workspaceManager(tieredWorkspaceManager)
    .build();

// 每次调用传入身份（类似 RuntimeContext）
TaskContext taskCtx = TaskContext.builder()
    .tenantId("company-a")
    .userId("alice")
    .sessionId("sess-1")
    .query("Hello")
    .build();

agent.run(taskCtx);  // 自动隔离
```

---

## 七、总结

### 核心借鉴点

| AgentScope 特性 | DeepAgent 优化方案 |
|----------------|-------------------|
| `IsolationScope` | `TenantNamespaceFactory` 隔离级别 |
| `NamespaceFactory` | 动态命名空间生成器 |
| `CompositeFilesystem` | `TieredWorkspaceManager` 分层路由 |
| 无状态 Agent | `StatelessDeepAgent` 单实例多租户 |
| `RuntimeContext` | `TaskContext` + `ExecutionContext` |

### 预期收益

1. **内存优化**：从 O(N) 实例缓存 → O(1) 单实例
2. **并发提升**：从 Semaphore 限制 → 无限制
3. **扩展性**：从垂直扩展 → 水平扩展
4. **维护性**：简化缓存管理，减少并发 Bug
5. **一致性**：类似 AgentScope 的成熟设计

### 风险提示

1. **改造工作量**：中等（需重构核心隔离层）
2. **兼容性**：需保留旧 API 作为兼容层
3. **性能验证**：需压测确认单实例性能
4. **存储依赖**：更依赖外部存储（Redis/OBS）
