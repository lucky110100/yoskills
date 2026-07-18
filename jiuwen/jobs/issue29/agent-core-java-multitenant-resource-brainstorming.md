# agent-core-java 多租户资源管理 Brainstorming 分析（已核对版）

> 分析日期：2026-07-16
> 项目：agent-core-java
> 范围：多租户资源管理功能，涵盖租户定义、资源界定、生命周期、存储路径、存储介质、Skill 同步
> 核对状态：已与业务方逐章核对确认

---

## 一、租户的定义

### 1.1 当前实现

`TenantContext` 是一个不可变数据类，核心字段：

```java
@Data @Builder
public class TenantContext {
    private final String tenantId;        // 租户唯一标识
    private final Map<String, String> extensions;  // 扩展元数据（如 region 等）
}
```

### 1.2 核对结论

- **租户是抽象概念，粒度完全由业务方决定**。可以是个人、部门、组织、项目或其他业务维度。
- **保持平面模型**，不引入层级租户（TenantHierarchy）。
- **不需要 extensions 辅助层级**。`extensions` 字段保留，仅用于传递业务元数据（如 region 等），不用于表达租户层级关系。
- `tenantId` 是业务方定义的**不透明标识符**，框架不赋予任何业务语义，只负责按 `tenantId` 做数据空间隔离。

### 1.3 safeTenantId 碰撞风险与约束

`safeTenantId()` 将非 `[a-zA-Z0-9_-]` 的字符统一替换为 `_`，存在碰撞风险：

| 原始 tenantId | safeTenantId | 碰撞？ |
|--------------|-------------|--------|
| `dept-01` | `dept_01` | — |
| `dept.01` | `dept_01` | ⚠️ 与 `dept-01` 碰撞 |

**决策：** 要求业务方 tenantId **仅使用 `[a-zA-Z0-9_-]` 字符**，在 `TenantContextHolder.setCurrentTenant()` 中校验，不合规的 tenantId 抛出 `IllegalArgumentException`。`safeTenantId()` 仅作为最后一道防线（防御路径穿越等极端场景），不应作为字符碰撞的依赖手段。

```java
public static void setCurrentTenant(TenantContext ctx) {
    if (ctx != null && ctx.isTenantAware()) {
        String tid = ctx.getTenantId();
        if (!tid.matches("[a-zA-Z0-9_-]+")) {
            throw new IllegalArgumentException(
                "tenantId must only contain [a-zA-Z0-9_-], got: " + tid);
        }
    }
    CURRENT_TENANT.set(ctx);
}
```

---

## 二、租户资源界定

### 2.1 当前已识别并实现的租户资源

| 资源 | 代码位置 | 隔离方式 | 租户创建/维护 |
|------|---------|---------|--------------|
| **Workspace** | `TenantWorkspaceResolver.resolveWorkspaceRoot()` | 文件系统路径隔离 | 是，每租户独立目录 |
| **Skills** | `TenantWorkspaceResolver.resolveSkillRoot()` | 文件系统路径隔离 | 是，支持租户私有 skill |
| **Tmp** | `TenantWorkspaceResolver.resolveTempDir()` | 文件系统路径隔离 | 是，每租户独立临时目录 |
| **Checkpoints** | `TenantWorkspaceResolver.resolveCheckpointDir()` | 文件系统路径隔离 + KV key 前缀 | 是，session 级别 |
| **Team Memory** | `WorkspaceType.TEAM_MEMORY` | 文件系统路径隔离 | 是，团队共享记忆目录 |
| **Session State (KV)** | `TenantKVStoreKeyResolver` | KV key 前缀（`tenantId:rawKey`） | 是，sessionId 前缀 |
| **LongTermMemory** -- | `TenantKVStoreKeyResolver` | KV key 前缀 | 是 |
| **用户记忆/变量** | `TenantKVStoreKeyResolver` | KV key 前缀 | 是 |

### 2.2 当前已明确**不隔离**的资源

| 资源 | 说明 |
|------|------|
| 智能体配置文件 | Agent 配置是系统级的 |
| 运行日志 | 全局共享 |
| ResourceMgr 资源池 | 工具、Workflow、Prompt、Model 等是系统级 |
| MessageQueue | 全局消息 |
| CallbackFramework | 全局回调 |
| MCP Server 配置 | 系统级，不隔离 |
| Prompt 模板 | 系统级，不隔离 |
| Model 配置 | 系统级，不隔离 |

### 2.3 核对结论：需显式隔离的资源

**「显式租户感知」定义：** 资源的读写接口**显式接收 `TenantContext` 参数**，而非仅依赖外层路径或 ThreadLocal 隐式推断。两种隔离模式的对比：

| 模式 | 机制 | 例子 | 风险 |
|------|------|------|------|
| 间接隔离 | 资源存放路径由外层决定，资源本身不知晓租户 | FileTodoStorage 写入 `tenants/{tid}/todo/`，路径由 workspace 决定 | 路径拼错或上下文丢失时数据写入公共区域 |
| 显式隔离 | 资源接口签名含 TenantContext，内部主动隔离 | KvTodoStorage.buildKey() 使用 TenantKVStoreKeyResolver | 即使上下文丢失，接口参数仍传递租户信息 |

**P1 阶段要求：** Todo 和 FileStore 的核心方法（load/save/delete）必须能接收 `TenantContext` 参数（可选，null 时走默认路径），确保在 ThreadLocal 上下文丢失时仍可正确隔离。

| 资源 | 当前状态 | 要求 |
|------|---------|------|
| **Todo** | 间接隔离（依赖 workspace 路径） | **需显式租户感知**，接口签名含 TenantContext |
| **FileStore (Session)** | 间接隔离（依赖 workspace 路径） | **需显式租户感知**，接口签名含 TenantContext |
| **Vector Store** | 未隔离 | P2 阶段完成 tenantId 前缀隔离 |
| **DB Store** | 未隔离 | P2 阶段完成 tenant_id 列改造，记忆用 |

### 2.4 资源分类总结

```
租户资源
├── 文件系统类（已隔离 ✓）
│   ├── Workspace（工作目录）
│   ├── Skills（技能文件）
│   ├── Tmp（临时文件）
│   ├── Checkpoints（检查点文件）
│   └── Team Memory（团队记忆）
│
├── KV 存储类（已隔离 ✓）
│   ├── Session State（会话状态）
│   ├── Agent State（智能体状态）
│   ├── Workflow State（工作流状态）
│   ├── Graph State（图状态）
│   ├── LongTermMemory（长期记忆）
│   ├── User Memory（用户记忆/变量）
│   └── Distributed Lock（分布式锁）
│
├── 关系数据库类（未隔离 ✗ → P2）
│   ├── MessageManager
│   └── ScopeUserMappingManager
│
├── 向量数据库类（未隔离 ✗ → P2）
│   └── VectorStore 集合
│
└── 需显式隔离（当前间接隔离 → P1）
    ├── Todo（需 TenantAware 机制）
    └── FileStore（需 TenantAware 机制）
```

---

## 三、各资源的生命周期管理

### 3.1 核对结论

- **不需要 TenantLifecycleManager**，租户的创建/注销由业务方自行负责，框架只做数据空间隔离。
- **Tmp 需要 TTL 清理机制**，超过一定时间未访问的临时文件自动清理。
- **其他资源需提供清理方法和接口**，但不由本服务触发，上层业务方自行决定何时调用。
- 文档需明确各资源在本服务中的生命周期处理方式。

### 3.2 各资源生命周期处理方式

| 资源 | 创建时机 | 销毁/清理方式 | 本服务处理方式 |
|------|---------|-------------|--------------|
| **TenantContext** | 请求入口 `setCurrentTenant()` | 请求结束 `clearCurrentTenant()` | InheritableThreadLocal 传播，请求结束自动清理 |
| **Workspace** | `initializeTenantSpace()` 幂等创建 | 提供清理接口，业务方调用 | 创建：自动；清理：提供 `cleanupTenantSpace(tenantId)` 方法 |
| **Skills** | 首次访问时自动创建目录 | 提供清理接口，业务方调用 | 创建：自动；清理：提供 `cleanupSkillRoot(tenantId)` 方法 |
| **Tmp** | `initializeTenantSpace()` 创建 | **TTL 自动清理** | 创建：自动；清理：TTL 定时扫描（默认 24h），提供可配置 TTL |
| **Checkpoints** | Session 创建时 | Session 完成时 `release()` | 创建：随 session 自动；清理：session 正常完成时自动 release |
| **Session State (KV)** | 首次写入时 | `release(sessionId)` | 创建：随 session 自动；清理：需业务方主动调用 release |
| **Team Memory** | 团队创建时 | 提供清理接口，业务方调用 | 创建：自动；清理：提供 `cleanupTeamMemory(tenantId, teamId)` 方法 |
| **Todo** | 任务创建时 | Session 结束时残留 | 创建：随任务自动；清理：提供 `cleanupTodo(tenantId, sessionId)` 方法 |
| **Vector Store** | 首次写入时 | 提供清理接口，业务方调用 | P2 阶段实现 |
| **DB Store** | 首次写入时 | 提供清理接口，业务方调用 | P2 阶段实现 |

### 3.3 清理接口设计

```java
public interface TenantResourceCleaner {
    // 文件系统类资源清理
    void cleanupWorkspace(String tenantId);
    void cleanupSkills(String tenantId);
    void cleanupCheckpoints(String tenantId, String sessionId);
    void cleanupTeamMemory(String tenantId, String teamId);
    void cleanupTodo(String tenantId, String sessionId);

    // KV 存储类资源清理
    void cleanupKVState(String tenantId);
    void cleanupKVState(String tenantId, String sessionId);
    void cleanupDistributedLocks(String tenantId);

    // 全量清理（文件系统 + KV）
    void cleanupAll(String tenantId);
}
```

**KV 清理语义说明：**

| 方法 | 清理范围 | 实现方式 |
|------|---------|---------|
| `cleanupKVState(tenantId)` | 删除该租户在 KV Store 中所有 `tenantId:*` 前缀的 key | `KVStore.deleteByPrefix("tenantId:")` |
| `cleanupKVState(tenantId, sessionId)` | 删除该租户指定 session 的所有 KV key | `KVStore.deleteByPrefix("tenantId:sessionId:")` |
| `cleanupDistributedLocks(tenantId)` | 释放该租户持有的所有分布式锁 | 需配合锁管理器的租户索引 |
| `cleanupAll(tenantId)` | 删除租户文件目录 + 删除 KV 前缀数据 + 释放分布式锁 | 组合调用以上所有方法 |

### 3.4 Tmp TTL 清理机制

```java
public class TmpFileCleaner {
    private final Duration ttl;  // 默认 24h
    private final Duration scanInterval;  // 默认 1h，可通过 DeepAgentConfig.tmpTtlScanInterval 配置
    private final ScheduledExecutorService scheduler;
    
    public void start() {
        scheduler.scheduleAtFixedRate(this::scanAndClean,
            scanInterval.toMillis(), scanInterval.toMillis(), TimeUnit.MILLISECONDS);
    }
    
    public void stop() {
        scheduler.shutdown();
        try {
            if (!scheduler.awaitTermination(5, TimeUnit.SECONDS)) {
                scheduler.shutdownNow();
            }
        } catch (InterruptedException e) {
            scheduler.shutdownNow();
            Thread.currentThread().interrupt();
        }
    }
    
    private void scanAndClean() {
        // 1. 扫描默认 tmp 目录
        // 2. 扫描各租户 tmp 目录
        // 3. 删除 lastModified 超过 TTL 的文件
    }
}
```

**生命周期管理：**
- `start()` 在 DeepAgent/RunnerImpl 初始化时调用
- `stop()` 在 DeepAgent/RunnerImpl 销毁时调用（`@PreDestroy` 等价钩子）
- `scanInterval` 通过 `DeepAgentConfig.tmpTtlScanInterval` 配置，默认 1 小时
- 应用关闭时优雅等待 5 秒，超时强制终止

---

## 四、存储路径层级结构与向后兼容性

### 4.1 当前路径问题

当前实际路径存在 **tenantId 重复** bug：

```
baseWorkspacePath/{tenantId}/tenants/{tenantId}/workspace
                      ^^^^^^^^              ^^^^^^^^
                      重复！                  重复！
```

原因：
- `PATH_DEFAULT.namespace(ctx, "tenants")` 产出 `{tenantId}/tenants`
- `resolvePath(namespace, tenantId, subDir)` 再次拼入 `tenantId`

### 4.2 核对确认的目标路径结构

**无租户场景：**

```
baseWorkspacePath/                     # ← 这就是 workspace
├── tmp/                               # 默认临时目录
├── skills/                            # 默认 Skill（公共 Skill）
├── checkpoints/                       # 默认检查点
├── team_memory/                       # 默认团队记忆
```

**有租户场景：**

```
baseWorkspacePath/
├── tmp/                               # 默认（无租户）
├── skills/                            # 默认（无租户，即公共 Skill）
├── checkpoints/                       # 默认（无租户）
├── team_memory/                       # 默认（无租户）
├── tenants/
│   ├── {tenantId_1}/                  # ← 这就是租户1的 workspace
│   │   ├── skills/
│   │   ├── tmp/
│   │   ├── checkpoints/
│   │   ├── team_memory/
│   │   └── todo/
│   ├── {tenantId_2}/                  # ← 这就是租户2的 workspace
│   │   ├── skills/
│   │   ├── tmp/
│   │   ├── checkpoints/
│   │   ├── team_memory/
│   │   └── todo/
```

**关键设计决策：**
- `tenants/{tenantId}/` **就是**该租户的 workspace 目录
- workspace 与其他租户资源（skills/tmp/checkpoints 等）**不是平级关系**，而是 `tenants/{tenantId}/` 本身就是 workspace，其他资源挂在其下
- 无租户时 `baseWorkspacePath` 直接作为根，完全向后兼容
- **不需要兼容旧路径**，可直接修改（项目尚未上线，无旧数据迁移需求）

### 4.3 实现调整方案

#### 4.3.1 修改 TenantWorkspaceResolver

```java
public class TenantWorkspaceResolver {
    private final String baseWorkspacePath;
    
    // resolveWorkspaceRoot：tenants/{tenantId}/ 即 workspace
    public Path resolveWorkspaceRoot(TenantContext ctx) {
        if (!ctx.isTenantAware()) {
            return Path.of(baseWorkspacePath).toAbsolutePath().normalize();
        }
        return Path.of(baseWorkspacePath, "tenants", ctx.safeTenantId())
                   .toAbsolutePath().normalize();
    }
    
    // resolveSkillRoot：tenants/{tenantId}/skills/
    public Path resolveSkillRoot(TenantContext ctx) {
        if (!ctx.isTenantAware()) {
            return Path.of(baseWorkspacePath, "skills").toAbsolutePath().normalize();
        }
        return Path.of(baseWorkspacePath, "tenants", ctx.safeTenantId(), "skills")
                   .toAbsolutePath().normalize();
    }
    
    // resolveTempDir：tenants/{tenantId}/tmp/
    public Path resolveTempDir(TenantContext ctx) {
        if (!ctx.isTenantAware()) {
            return Path.of(baseWorkspacePath, "tmp").toAbsolutePath().normalize();
        }
        return Path.of(baseWorkspacePath, "tenants", ctx.safeTenantId(), "tmp")
                   .toAbsolutePath().normalize();
    }
    
    // resolveCheckpointDir：tenants/{tenantId}/checkpoints/
    public Path resolveCheckpointDir(TenantContext ctx) {
        if (!ctx.isTenantAware()) {
            return Path.of(baseWorkspacePath, "checkpoints").toAbsolutePath().normalize();
        }
        return Path.of(baseWorkspacePath, "tenants", ctx.safeTenantId(), "checkpoints")
                   .toAbsolutePath().normalize();
    }
    
    // resolveTeamMemoryDir：tenants/{tenantId}/team_memory/
    public Path resolveTeamMemoryDir(TenantContext ctx) {
        if (!ctx.isTenantAware()) {
            return Path.of(baseWorkspacePath, "team_memory").toAbsolutePath().normalize();
        }
        return Path.of(baseWorkspacePath, "tenants", ctx.safeTenantId(), "team_memory")
                   .toAbsolutePath().normalize();
    }
    
    // initializeTenantSpace：幂等创建租户目录结构
    public Path initializeTenantSpace(TenantContext ctx) {
        if (!ctx.isTenantAware()) {
            return Path.of(baseWorkspacePath);
        }
        return initializedTenants.computeIfAbsent(ctx.safeTenantId(), tid -> {
            Path root = Path.of(baseWorkspacePath, "tenants", tid);
            try {
                Files.createDirectories(root);                               // workspace = root
                Files.createDirectories(root.resolve("skills"));
                Files.createDirectories(root.resolve("tmp"));
                Files.createDirectories(root.resolve("checkpoints"));
                Files.createDirectories(root.resolve("team_memory"));
                Files.createDirectories(root.resolve("todo"));
            } catch (Exception e) {
                throw new RuntimeException("Failed to initialize tenant space: " + tid, e);
            }
            return root;
        });
    }
}
```

#### 4.3.2 修改 TenantNamespaceFactories.PATH_DEFAULT

```java
// 修改后：
public static final TenantNamespaceFactory PATH_DEFAULT =
    (ctx, rawKey) -> {
        if (ctx != null && ctx.isTenantAware()) {
            return "tenants/" + ctx.safeTenantId();
        }
        return "";  // 无租户时返回空字符串
    };
```

#### 4.3.3 修改 WorkspaceType

```java
public enum WorkspaceType {
    WORKSPACE(""),              // tenants/{tenantId}/ 即 workspace
    SKILLS("skills"),
    TMP("tmp"),
    CHECKPOINTS("checkpoints"),
    TEAM_MEMORY("team_memory"),
    TODO("todo");
    
    private final String subDirectory;
    
    WorkspaceType(String subDirectory) { this.subDirectory = subDirectory; }
    
    public String subDirectory() { return subDirectory; }
}
```

#### 4.3.4 修改 LocalWorkspaceStore

```java
public class LocalWorkspaceStore implements WorkspaceStore {
    private final String basePath;
    
    @Override
    public Path resolvePath(String namespace, String tenantId, String subDirectory) {
        if (subDirectory == null || subDirectory.isEmpty()) {
            // WORKSPACE 类型：namespace 本身就是 tenants/{tenantId}
            return Path.of(basePath, namespace).toAbsolutePath().normalize();
        }
        return Path.of(basePath, namespace, subDirectory).toAbsolutePath().normalize();
    }
    
    @Override
    public Path resolveDefaultPath(String subDirectory) {
        if (subDirectory == null || subDirectory.isEmpty()) {
            return Path.of(basePath).toAbsolutePath().normalize();
        }
        return Path.of(basePath, subDirectory).toAbsolutePath().normalize();
    }
    
    @Override
    public void createDirectories(String namespace, String tenantId) {
        Path root = Path.of(basePath, namespace);
        try {
            Files.createDirectories(root);  // workspace
            for (String subDir : new String[]{"skills", "tmp", "checkpoints", "team_memory", "todo"}) {
                Files.createDirectories(root.resolve(subDir));
            }
        } catch (Exception e) {
            throw new RuntimeException("Failed to create tenant directories", e);
        }
    }
}
```

---

## 五、存储介质分析

### 5.1 核对结论

- **统一抽象层**，分三阶段实施
- Phase 1：补充 Todo/FileStore 的 SPI
- Phase 2：抽象 TenantResourceStore 统一接口 + 适配现有资源
- Phase 3：统一切换入口，迁移现有调用点

### 5.2 当前各资源的存储介质

| 资源 | 当前存储介质 | SPI 支持 | 缺失 |
|------|------------|---------|------|
| **Workspace 文件** | 本地文件系统 | WorkspaceStore SPI | - |
| **Skills 文件** | 本地文件系统 | 同上 | - |
| **Tmp 文件** | 本地文件系统 | 同上 | - |
| **Checkpoints 文件** | 本地文件系统 | 同上 | - |
| **Team Memory 文件** | 本地文件系统 | 同上 | - |
| **Session State** | InMemory / KV Store | CheckpointerProvider SPI | - |
| **KV Store 后端** | InMemory / Redis | KVStoreProvider SPI | - |
| **Vector Store** | InMemory / Milvus / Chroma / PGVector / ES | VectorStoreProvider SPI | - |
| **Object Storage** | 本地 / OBS / S3 / HDFS | ObjectStorageProvider SPI | - |
| **Todo** | 本地文件系统 | **无 SPI** | 需补充 |
| **FileStore (Session)** | 本地 JSON 文件 | **无 SPI** | 需补充 |

### 5.3 分阶段实施计划

#### Phase 1：补充 SPI（P1）

**目标：** 为 Todo 和 FileStore 补充 SPI 发现机制，与现有 SPI 体系对齐；同时提供 Redis 存储实现，满足 issue34（TodoTool Support Redis）需求。

##### 1. TodoStorageProvider SPI

```java
public interface TodoStorageProvider {
    String typeName();
    TodoStorage create(Map<String, Object> conf);
}
```

##### 2. FileTodoStorageProvider（内置）

```java
public class FileTodoStorageProvider implements TodoStorageProvider {
    public String typeName() { return "file"; }
    public TodoStorage create(Map<String, Object> conf) {
        return new FileTodoStorage(Path.of((String) conf.get("basePath")));
    }
}
```

##### 3. KvTodoStorage + KvTodoStorageProvider（复用已有实现）

**关键发现：`KvTodoStorage` 已存在于代码库中，且已基于 `BaseKVStore` SPI + `TenantKVStoreKeyResolver` 实现了存储介质无关的 KV 存储。** 传入 `RedisStore`（它 `extends BaseKVStore`）即为 Redis 模式，无需新建 `RedisTodoStorage`。

```java
// 已有实现 — 无需修改
public class KvTodoStorage implements TodoStorage {
    private final BaseKVStore kvStore;

    public KvTodoStorage(BaseKVStore kvStore) {
        this.kvStore = Objects.requireNonNull(kvStore);
    }

    private String buildKey(String sessionId) {
        String rawKey = sessionId + ":todo";
        return TenantKVStoreKeyResolver.resolveKey(rawKey);
    }
    // ... load/save/delete 已实现，通过 BaseKVStore SPI 存取
}
```

```java
// 新增 Provider — 按存储抽象层分，不按介质分
public class KvTodoStorageProvider implements TodoStorageProvider {
    public String typeName() { return "kv"; }
    
    public TodoStorage create(Map<String, Object> conf) {
        // 介质选择下沉到 KVStoreFactory：conf 中的 type 字段决定实际介质
        // type=redis → RedisStore, type=in_memory → InMemoryKVStore
        String kvStoreType = (String) conf.getOrDefault("kvStoreType", "in_memory");
        @SuppressWarnings("unchecked")
        Map<String, Object> kvStoreConf = conf.get("kvStoreConf") instanceof Map
            ? (Map<String, Object>) conf.get("kvStoreConf") : Map.of();
        BaseKVStore kvStore = KVStoreFactory.create(kvStoreType, kvStoreConf);
        return new KvTodoStorage(kvStore);
    }
}
```

**设计理由：**

| 方案 | 说明 | 评估 |
|------|------|------|
| ~~新建 RedisTodoStorage~~ | 为 Redis 单独建一个 TodoStorage 实现 | ❌ 冗余——`KvTodoStorage` 已基于 `BaseKVStore`，传入 `RedisStore` 即为 Redis |
| **KvTodoStorageProvider (type="kv")** | 按抽象层分 Provider，介质下沉到 `KVStoreFactory` | ✅ 与 `PersistenceCheckpointer`+`KVStoreFactory` 一致，一套配置共享 |

**KV 存储 key 格式（与 PersistenceCheckpointer 一致）：**

| 场景 | key 格式 | 示例 |
|------|---------|------|
| 无租户 | `{sessionId}:todo` | `sess-abc123:todo` |
| 有租户 `dept01` | `dept01:{sessionId}:todo` | `dept01:sess-abc123:todo` |

租户前缀通过 `TenantKVStoreKeyResolver` 自动添加，与 `PersistenceCheckpointer` 的 key 隔离方式完全一致。

**与 Checkpointer 共享 BaseKVStore 实例：**

```
kvStoreConfig → KVStoreFactory.create("redis", conf) → RedisStore (共享实例)
    ├── PersistenceCheckpointer(sharedRedisStore)     ← Checkpointer 复用
    └── KvTodoStorage(sharedRedisStore)               ← Todo 复用
```

一套 Redis 连接、一套配置、一个共享实例，Checkpointer 和 Todo 自然打通。

##### 4. TodoStorageFactory

遵循项目已有的工厂模式（WorkspaceStoreFactory、KVStoreFactory、CheckpointerFactory）。

```java
public final class TodoStorageFactory {
    private static final Map<String, TodoStorageProvider> REGISTRY = new ConcurrentHashMap<>();

    static {
        for (TodoStorageProvider provider : ServiceLoader.load(TodoStorageProvider.class)) {
            REGISTRY.putIfAbsent(provider.typeName(), provider);
        }
    }

    public static void register(String type, TodoStorageProvider provider) {
        REGISTRY.putIfAbsent(type, provider);
    }

    public static TodoStorage create(String type, Map<String, Object> conf) {
        TodoStorageProvider provider = REGISTRY.get(type);
        if (provider == null) {
            throw new IllegalArgumentException("Unknown TodoStorage type: " + type);
        }
        return provider.create(conf != null ? conf : Map.of());
    }

    public static boolean hasProvider(String type) {
        return REGISTRY.containsKey(type);
    }
}
```

##### 5. TodoTool 改造

```java
public class TodoTool {
    private final TodoStorage storage;

    // 兼容旧构造方式（默认 file）
    public TodoTool(String workspace) {
        this.storage = new FileTodoStorage(Path.of(workspace != null ? workspace : "."));
    }

    public TodoTool(TodoStorage storage) {
        this.storage = Objects.requireNonNull(storage);
    }

    // 新增：通过工厂 + 配置创建
    public static TodoTool fromConfig(String storageType, Map<String, Object> conf) {
        TodoStorage storage = TodoStorageFactory.create(storageType, conf);
        return new TodoTool(storage);
    }
}
```

##### 6. SessionStoreProvider SPI（FileStore 补充）

```java
public interface SessionStoreProvider {
    String typeName();
    Store createStore(Map<String, Object> conf);
}

public class FileSessionStoreProvider implements SessionStoreProvider {
    public String typeName() { return "file"; }
    public Store createStore(Map<String, Object> conf) {
        return new FileStore(Path.of((String) conf.get("storePath")));
    }
}
```

##### 7. SPI Service 注册

```
# META-INF/services/com.openjiuwen.harness.tools.TodoStorageProvider
com.openjiuwen.harness.tools.FileTodoStorageProvider
com.openjiuwen.harness.tools.KvTodoStorageProvider

# META-INF/services/com.openjiuwen.core.session.store.SessionStoreProvider
com.openjiuwen.core.session.store.FileSessionStoreProvider
```

##### 8. 配置集成

TodoTool 存储类型通过 DeepAgentConfig 或 RunnerConfig 配置，与 Checkpointer 的 `kvStoreConfig` 共享同一套 Redis 配置：

```java
DeepAgentConfig config = DeepAgentConfig.builder()
        .todoStorageType("kv")                          // "file" | "kv"
        .kvStoreConfig(Map.of(                          // 与 Checkpointer 共享
            "type", "redis",
            "conf", Map.of(
                "connection", Map.of("url", "redis://redis.example.com:6379")
            )
        ))
        .build();
```

或在 YAML 配置中：

```yaml
kvStoreConfig:                    # 唯一入口，Checkpointer + Todo 共用
  type: redis
  conf:
    connection:
      url: redis://127.0.0.1:6379

todo:
  storage:
    type: kv                       # file | kv（kv 模式下介质由 kvStoreConfig 决定）
```

**配置统一原则：**
- `kvStoreConfig` 是 KV 存储介质的唯一配置入口
- `todoStorageType="kv"` 时，`KvTodoStorageProvider` 通过 `KVStoreFactory` 创建 `BaseKVStore`，自动复用 `kvStoreConfig` 指定的介质
- 不再为 Todo 单独配 Redis 连接，避免配置重复和连接浪费

**共享实例生命周期管理：**

| 时机 | 操作 | 位置 |
|------|------|------|
| 创建 | `DeepAgent.init()` 或 `RunnerImpl.start()` 中通过 `KVStoreFactory.create()` 创建 | `DeepAgent.kvStore` / `RunnerImpl.kvStore` |
| 注入 | `PersistenceCheckpointer` 和 `KvTodoStorage` 通过构造器共享同一实例 | `TaskPlanningRail.init()` / `CheckpointerFactory.create()` |
| 销毁 | `DeepAgent.destroy()` 或 `RunnerImpl.stop()` 中调用 `kvStore.close()` | 依赖 `BaseKVStore` 的 `close()` 方法（RedisStore 关闭连接池） |
| 动态变更 | 运行中 `kvStoreConfig` 变更不生效，需重启服务 | 不支持热切换 |

> **注意：** `BaseKVStore` 接口需补充 `close()` 方法（当前部分实现如 InMemoryKVStore 无需 close，但 RedisStore 需关闭 Jedis 连接池）。

##### 9. 与 issue34 需求的对应关系

| issue34 需求 | Phase 1 覆盖 | 实现位置 |
|-------------|-------------|---------|
| 多实例共享 Todo 数据 | ✅ | KvTodoStorage(RedisStore) — 多实例通过 Redis 共享 |
| 利用框架已有的 Redis 能力 | ✅ | KvTodoStorageProvider 通过 KVStoreFactory 复用 BaseKVStore + RedisKVStoreProvider，与 PersistenceCheckpointer 共享同一 RedisStore 实例 |
| 存储抽象层可扩展 | ✅ | TodoStorageProvider SPI + TodoStorageFactory，按抽象层（file/kv）分 Provider |
| 租户数据隔离 | ✅ | KvTodoStorage.buildKey() 使用 TenantKVStoreKeyResolver，与 PersistenceCheckpointer 隔离方式一致 |

#### Phase 2：抽象 TenantResourceStore 统一接口（P2）

**目标：** 定义统一的资源存储接口，按资源类型选择存储后端。

```java
public interface TenantResourceStore {
    String storeType();
    
    // 文件类操作
    Path resolvePath(TenantContext ctx, ResourceType type, String... subPaths);
    InputStream readStream(TenantContext ctx, ResourceType type, String... subPaths);
    void writeStream(TenantContext ctx, ResourceType type, InputStream data, String... subPaths);
    
    // KV 类操作
    void put(TenantContext ctx, ResourceType type, String key, Object value);
    <T> T get(TenantContext ctx, ResourceType type, String key, Class<T> clazz);
    void delete(TenantContext ctx, ResourceType type, String key);
    Map<String, Object> listByPrefix(TenantContext ctx, ResourceType type, String prefix);
}
```

```java
public enum ResourceType {
    WORKSPACE(StoreCategory.FILE),
    SKILLS(StoreCategory.FILE),
    TMP(StoreCategory.FILE),
    CHECKPOINTS(StoreCategory.FILE),
    TEAM_MEMORY(StoreCategory.FILE),
    TODO(StoreCategory.FILE),
    
    SESSION_STATE(StoreCategory.KV),
    AGENT_STATE(StoreCategory.KV),
    WORKFLOW_STATE(StoreCategory.KV),
    GRAPH_STATE(StoreCategory.KV),
    LONG_TERM_MEMORY(StoreCategory.KV),
    USER_MEMORY(StoreCategory.KV),
    
    VECTOR_DATA(StoreCategory.VECTOR),
    
    RELATIONAL_DATA(StoreCategory.RDBMS);
    
    public enum StoreCategory { FILE, KV, VECTOR, RDBMS }
}
```

**统一配置：**
```yaml
tenant:
  storage:
    default: local
    overrides:
      session_state: redis
      agent_state: redis
      vector_data: milvus
    tiers:
      primary: local
      secondary:
        - obs
        - hdfs
    providers:
      local:
        basePath: /data/tenant_data
      redis:
        host: redis.example.com
        port: 6379
      obs:
        bucketPrefix: deepagent-ws
        endpoint: https://obs.example.com
      milvus:
        host: milvus.example.com
        port: 19530
```

#### Phase 3：统一切换入口（P2）

**目标：** 迁移现有调用点到 TenantResourceStore 统一入口。

- 所有资源访问通过 `TenantResourceStoreFactory.create(type, config)` 获取
- 逐步替代各资源独立的 SPI 直接调用
- 保持向后兼容，旧 API 标记 @Deprecated

### 5.4 存储介质与资源类型的适配矩阵

| 资源 \ 存储 | 本地文件 | Redis | 关系数据库 | 对象存储 | HDFS | 向量数据库 |
|------------|---------|-------|-----------|---------|------|-----------|
| Workspace | ✅ 主 | ❌ | ❌ | ✅ 副 | ✅ 副 | ❌ |
| Skills | ✅ 主 | ❌ | ❌ | ✅ 副 | ✅ 副 | ❌ |
| Tmp | ✅ 主 | ❌ | ❌ | ✅ 副 | ❌ | ❌ |
| Checkpoints | ✅ 主 | ✅ 主 | ⚠️ 可选 | ✅ 副 | ✅ 副 | ❌ |
| Team Memory | ✅ 主 | ❌ | ❌ | ✅ 副 | ✅ 副 | ❌ |
| Session State | ✅ 副 | ✅ 主 | ⚠️ 可选 | ❌ | ❌ | ❌ |
| Agent State | ✅ 副 | ✅ 主 | ⚠️ 可选 | ❌ | ❌ | ❌ |
| Todo | ✅ 主 | ✅ 可选 | ⚠️ 可选 | ❌ | ❌ | ❌ |
| Vector Data | ❌ | ❌ | ⚠️ PGVector | ❌ | ❌ | ✅ 主 |

---

## 六、租户 Skill 与系统默认 Skill 同步设计

### 6.1 核对结论

- **方案 B+D 组合**：联合查找 + OverlaySkillManager
- **显式覆盖 + 可撤销**：租户需显式操作覆盖公共 Skill，通过 overlay 标记管理，可撤销覆盖

### 6.2 当前 Skill 加载机制

**SkillManager 的加载流程：**

1. 接收一组 `roots`（Skill 根目录列表）
2. 遍历每个 root，查找子目录下的 `SKILL.md` / `Skill.md`
3. 解析 YAML front matter 获取 description
4. 维护 `registry`（LinkedHashMap）、`updateAtCache`（mtime 缓存）、`skillOrder`（遍历顺序）
5. `refreshIncrementally()` 只重新加载新增或 mtime 变化的 Skill

**当前 SkillTool 的双层查找逻辑（已有）：**
- 查找优先级：租户私有 Skill → 公共 Skill → Skill not found
- 租户可覆盖同名公共 Skill
- 公共 Skill 对所有租户可见
- 无租户时只查找公共 Skill（向后兼容）

### 6.3 OverlaySkillManager 设计

```java
public class OverlaySkillManager {
    private final SkillManager tenantSkillManager;    // 租户私有 Skill
    private final SkillManager publicSkillManager;     // 公共 Skill
    // overlayDir 位置：tenants/{tenantId}/.overlay/
    // 每个被覆盖的公共 Skill 对应一个 {skillName}.override 标记文件（空文件）
    // 标记文件的存在表示租户已显式选择覆盖该公共 Skill，即使租户私有 Skill 被删除，
    // 该公共 Skill 仍不会出现在租户可见列表中，直到显式撤销覆盖
    private final Path overlayDir;                     // 覆盖标记目录
    private final TenantContext tenantContext;
    
    // 获取租户可见的所有 Skill（租户私有 + 未覆盖的公共 Skill）
    public List<Skill> getAllVisibleSkills() {
        List<Skill> result = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        
        // 第一层：租户私有 Skill
        for (Skill skill : tenantSkillManager.getAllInOrder()) {
            result.add(skill);
            seen.add(skill.getName());
        }
        
        // 第二层：公共 Skill（跳过已被租户显式覆盖的）
        for (Skill skill : publicSkillManager.getAllInOrder()) {
            if (!seen.contains(skill.getName()) && !isOverridden(skill.getName())) {
                result.add(skill);
                seen.add(skill.getName());
            }
        }
        
        return result;
    }
    
    // 显式覆盖：创建 overlay 标记 + 租户私有 Skill
    public void overrideSkill(String skillName, Path tenantSkillDir) {
        createOverlayMarker(skillName);
        tenantSkillManager.register(tenantSkillDir);
    }
    
    // 撤销覆盖：删除 overlay 标记 + 移除租户私有 Skill
    public void revokeOverride(String skillName) {
        deleteOverlayMarker(skillName);
        tenantSkillManager.unregister(skillName);
    }
    
    // 检查公共 Skill 是否被租户显式覆盖
    private boolean isOverridden(String skillName) {
        return Files.exists(overlayDir.resolve(skillName + ".override"));
    }
    
    private void createOverlayMarker(String skillName) {
        try {
            Files.createDirectories(overlayDir);
            Files.writeString(overlayDir.resolve(skillName + ".override"), "");
        } catch (IOException e) {
            throw new RuntimeException(e);
        }
    }
    
    private void deleteOverlayMarker(String skillName) {
        try {
            Files.deleteIfExists(overlayDir.resolve(skillName + ".override"));
        } catch (IOException e) {
            throw new RuntimeException(e);
        }
    }
    
    // 热加载支持：分别对两层做增量刷新
    public void refreshIncrementally() {
        tenantSkillManager.refreshIncrementally(tenantSkillRoots);
        publicSkillManager.refreshIncrementally(publicSkillRoots);
    }
}
```

#### 6.3.1 overlay 标记目录位置

**overlay 标记文件存放路径：** `tenants/{tenantId}/.overlay/{skillName}.override`

**路径推导：**
```
baseWorkspacePath/
└── tenants/
    └── {tenantId}/                  # 租户 workspace
        ├── skills/                   # 租户私有 Skill
        ├── .overlay/                 # overlay 标记目录（与 skills 平级）
        │   ├── weather_skill.override   # 空文件，表示已覆盖 weather_skill
        │   └── search_skill.override    # 空文件，表示已覆盖 search_skill
        ├── tmp/
        ├── checkpoints/
        ├── team_memory/
        └── todo/
```

**设计理由：**
- `.overlay/` 目录以 `.` 开头，与 SkillManager 的 `SKILL.md` 扫描逻辑不冲突（SkillManager 只扫描包含 `SKILL.md` 的子目录）
- 标记文件为空文件，仅通过文件存在性判断覆盖状态，不存储额外数据
- overlay 标记与租户 Skill 目录平级，便于整体清理（删除租户目录时 overlay 标记一并删除）

#### 6.3.2 overlay 迁移策略

**旧部署迁移问题：** 已有部署中租户可能已通过隐式同名覆盖（当前 SkillTool 的双层查找逻辑）覆盖了公共 Skill。切换到 OverlaySkillManager 后，需要为这些隐式覆盖创建显式 overlay 标记。

**迁移方案：**

1. **启动时自动迁移（推荐）：** 在 `OverlaySkillManager` 初始化时，扫描租户 Skill 目录，对每个与公共 Skill 同名的租户私有 Skill 自动创建 `.override` 标记文件
2. **手动迁移：** 业务方手动执行一次性迁移脚本，为每个已知覆盖创建标记文件
3. **无迁移（零覆盖状态）：** 新部署无需迁移，所有租户初始无覆盖

**自动迁移实现：**

```java
// OverlaySkillManager 构造时执行
private void migrateImplicitOverrides() {
    Set<String> publicSkillNames = publicSkillManager.getAllInOrder()
        .stream().map(Skill::getName).collect(Collectors.toSet());
    
    for (Skill tenantSkill : tenantSkillManager.getAllInOrder()) {
        if (publicSkillNames.contains(tenantSkill.getName())) {
            // 租户私有 Skill 与公共 Skill 同名 → 创建 overlay 标记
            if (!isOverridden(tenantSkill.getName())) {
                createOverlayMarker(tenantSkill.getName());
            }
        }
    }
}
```

**迁移安全性：**
- 自动迁移仅在 overlay 标记不存在时创建，不会覆盖已有标记
- 迁移是幂等操作，重复执行不会产生副作用
- 迁移完成后，隐式覆盖变为显式覆盖，后续可通过 `revokeOverride()` 撤销

### 6.4 Skill 同步与热加载

**方案 B+D 的热加载机制：**
- 公共 Skill 更新后，`publicSkillManager.refreshIncrementally()` 自动检测 mtime 变化
- 租户私有 Skill 更新后，`tenantSkillManager.refreshIncrementally()` 自动检测 mtime 变化
- 两者独立刷新，互不影响，实时性保证
- OverlaySkillManager 整合两层的刷新结果

**与当前实现的对比：**

| 维度 | 当前实现 | OverlaySkillManager |
|------|---------|-------------------|
| 查找逻辑 | SkillTool 内嵌双层查找 | 封装到 OverlaySkillManager |
| 覆盖机制 | 隐式（同名即覆盖） | 显式覆盖 + 可撤销 |
| 热加载 | 各自独立刷新 | 分层独立刷新 + 统一整合 |
| 覆盖管理 | 无法撤销覆盖 | overlay 标记 + revokeOverride() |

### 6.5 实现步骤

```
Step 1: 创建 OverlaySkillManager
    - 封装租户 SkillManager + 公共 SkillManager
    - getAllVisibleSkills() 实现双层查找 + overlay 过滤
    - overrideSkill() / revokeOverride() 显式覆盖管理

Step 2: 修改 SkillTool / ListSkillTool
    - 使用 OverlaySkillManager 替代直接使用 SkillManager
    - 查找逻辑不变（租户优先 → 公共），只是入口统一

Step 3: 增加租户 Skill 初始化钩子
    - 在 TenantWorkspaceResolver.initializeTenantSpace() 中
    - 创建租户 Skill 空目录
    - 依赖 OverlaySkillManager 联合查找，不需要预复制公共 Skill

Step 4: 公共 Skill 热加载
    - 公共 SkillManager 定期 refreshIncrementally()
    - 租户 SkillManager 也定期 refreshIncrementally()
    - OverlaySkillManager 整合两层的刷新结果
```

---

## 七、综合建议与优先级

### 7.1 按优先级排序的行动项

| 优先级 | 行动项 | 影响范围 | 工作量 |
|--------|-------|---------|--------|
| **P0** | 修复 tenantId 路径重复问题：改为 `tenants/{tenantId}/` 即 workspace | TenantWorkspaceResolver, TenantNamespaceFactories, LocalWorkspaceStore, WorkspaceType | 小 |
| **P0** | 完成 PersistenceCheckpointer 的 tenantId 前缀改造 | PersistenceCheckpointer | 小（已部分完成） |
| **P1** | Todo/FileStore 增加显式租户感知 | TodoTool, FileTodoStorage, FileStore | 中 |
| **P1** | 创建 OverlaySkillManager + 显式覆盖/可撤销机制 | 新增类 + 修改 SkillTool/ListSkillTool | 中 |
| **P1** | 补充 TodoStorage/FileStore 的 Provider SPI | 新增 SPI 接口 + 内置实现 | 小 |
| **P1** | Tmp 文件 TTL 自动清理 | 新增 TmpFileCleaner | 小 |
| **P2** | 抽象 TenantResourceStore 统一接口 + 适配现有资源 | 新增抽象层 | 大 |
| **P2** | VectorStore 集合名 tenantId 前缀隔离 | VectorStore 相关类 | 中 |
| **P2** | BaseDbStore SQL 层 tenant_id 列改造 | MessageManager, ScopeUserMappingManager | 中 |
| **P2** | 租户数据归档/迁移工具 | 新增工具类 | 中 |
| **P2** | 统一切换入口，迁移现有调用点到 TenantResourceStore | 全局 | 大 |
| **P2** | 租户资源计量接口 TenantResourceMetrics | 新增接口 + 各资源实现 | 中 |
| **P2** | BaseKVStore 接口补充 close() 方法 | BaseKVStore, InMemoryKVStore, RedisStore | 小 |

### 7.2 关键设计原则

1. **向后兼容优先**：所有改动必须保证 `enableTenantIsolation=false` 时行为完全不变
2. **SPI 驱动**：新功能通过 SPI 扩展，不修改核心逻辑
3. **租户标识不透明**：框架不赋予 tenantId 业务语义，租户粒度由业务方决定
4. **存储介质可替换**：通过 SPI 和配置实现按资源类型选择存储后端
5. **安全纵深防御**：路径隔离 + KV 前缀隔离 + SQL tenant_id 列，三层防护互为补充
6. **资源清理由业务方触发**：本服务提供清理接口，不由本服务主动触发
7. **异步场景显式传播**：不依赖 InheritableThreadLocal 自动继承，所有异步路径显式捕获 + bind/unbind

---

## 八、异步场景下的租户上下文传播机制

### 8.1 传播策略分层

| 执行路径 | 传播机制 | 代码位置 | 风险 |
|----------|---------|---------|------|
| 同步阻塞调用 | try/finally bind/unbind | `DeepAgent.invoke()`、`RunnerImpl.runAgent()` | **低** — 上下文在同一线程上 |
| 同步流式调用 | `TenantUnbindIterator` 包装器，延迟到迭代器耗尽时 unbind | `RunnerImpl.wrapTenantUnbindIterator()` | **低** — 迭代器耗尽/异常时 unbind |
| Reactor 异步调用 | 显式捕获 TenantContext + `fromCallable` / `deferWithSessionCleanup` | `RunnerImpl.runAgentAsync()`、`runAgentStreamingAsync()` | **低** — boundedElastic 线程上手动 bind/unbind |
| `new Thread()` 子线程 | `InheritableThreadLocal` 自动继承 | `DeepAgent.stream()` 中创建守护线程 | **低** — 子线程创建时复制父线程值 |
| `ExecutorService` 线程池复用 | **依赖 try/finally 清除**，无自动传播 | — | **中** — 复用线程不重新继承，需每次显式设置 |
| `CompletableFuture.supplyAsync()` | **未覆盖** | — | **高** — 如引入，租户上下文会丢失 |
| `@Async`（Spring） | **未覆盖** | 项目不依赖 Spring | **高** — 如集成 Spring，上下文不传播 |

### 8.2 InheritableThreadLocal 的已知限制

`TenantContextHolder` 使用 `InheritableThreadLocal`，其特性如下：

- ✅ **`new Thread()` 创建的子线程自动继承**父线程的 TenantContext
- ❌ **线程池复用的线程不会重新继承**——线程第一次创建时继承，后续复用时保留旧值（除非 finally 中 `clearCurrentTenant()` 正确执行）
- ❌ **Reactor `Schedulers.boundedElastic()` 不继承**——Reactor 线程池线程不是通过 `new Thread()` 创建的
- ❌ **`CompletableFuture` 默认 ForkJoinPool 不继承**

### 8.3 当前传播保障措施

1. **所有入口方法均使用 try/finally 模式：** `setCurrentTenant()` → 执行 → `clearCurrentTenant()`，确保线程池复用时上下文不残留
2. **异步方法显式捕获：** `TenantContext captured = resolved;` 在 callable/defer 内手动 bind/unbind
3. **流式方法延迟 unbind：** `TenantUnbindIterator` 在 `hasNext() == false` 或异常时才 unbind
4. **Reactor doFinally 保障：** `deferWithSessionCleanup` 在 COMPLETE/ERROR/CANCEL 三种终态下都触发清理

### 8.4 新增异步路径的接入规范

任何新增异步执行路径必须遵循以下规范：

1. **显式捕获 TenantContext** 为局部变量，不依赖 ThreadLocal
2. **在异步任务开始时 bindTenantContext(captured)**
3. **在异步任务结束时（包括异常）unbindTenantContext()**
4. **提供 UT 测试覆盖异步场景的租户隔离**

```java
// 规范模板
TenantContext captured = TenantContextHolder.getCurrentTenant();
executor.submit(() -> {
    try {
        TenantContextHolder.setCurrentTenant(captured);
        // 业务逻辑
    } finally {
        TenantContextHolder.clearCurrentTenant();
    }
});
```

### 8.5 与 SessionContextHolder 的不一致

`SessionContextHolder` 使用普通 `ThreadLocal`（非 `InheritableThreadLocal`），与 `TenantContextHolder` 的设计不一致。当前 Session 上下文在 `new Thread()` 子线程中不会自动传播。

**风险评估：** 低——Session 上下文通过 `AgentSessionApi` 对象传递（非 ThreadLocal），ReActAgent 内部使用注入的 session 对象而非 ThreadLocal。

**后续优化方向（P2）：** 考虑将 `SessionContextHolder` 也改为 `InheritableThreadLocal`，或引入统一的 `ContextPropagator` 工具类。

### 8.6 不引入通用 ContextPropagator 的理由

项目中不存在通用 `ContextPropagator` 或 `ThreadContextPropagator`。当前选择散布式 bind/unbind 而非统一传播框架的理由：

1. **项目不依赖 Spring/Reactor Context**——Reactor 的 `contextWrite()` 可自动传播，但项目仅部分使用 Reactor
2. **传播路径有限**——当前只有 4 种执行路径，散布式管理足够
3. **显式传播更安全**——避免隐式传播带来的难以调试的上下文丢失问题
4. **引入 ContextPropagator 需要侵入性改造**——需要修改所有异步 API 签名

**如未来异步路径增多（超过 6 种），建议引入 `TenantContextPropagator` 统一管理。**

---

## 附录：关键代码位置索引

| 文件 | 路径 |
|------|------|
| TenantContext | `src/main/java/com/openjiuwen/core/multitenant/TenantContext.java` |
| TenantContextHolder | `src/main/java/com/openjiuwen/core/multitenant/TenantContextHolder.java` |
| TenantWorkspaceResolver | `src/main/java/com/openjiuwen/core/multitenant/TenantWorkspaceResolver.java` |
| TenantPathSecurity | `src/main/java/com/openjiuwen/core/multitenant/TenantPathSecurity.java` |
| TenantKVStoreKeyResolver | `src/main/java/com/openjiuwen/core/multitenant/TenantKVStoreKeyResolver.java` |
| TenantNamespaceFactory | `src/main/java/com/openjiuwen/core/multitenant/TenantNamespaceFactory.java` |
| TenantNamespaceFactories | `src/main/java/com/openjiuwen/core/multitenant/TenantNamespaceFactories.java` |
| WorkspaceType | `src/main/java/com/openjiuwen/core/multitenant/workspace/WorkspaceType.java` |
| TieredWorkspaceManager | `src/main/java/com/openjiuwen/core/multitenant/workspace/TieredWorkspaceManager.java` |
| WorkspaceStore | `src/main/java/com/openjiuwen/core/multitenant/workspace/WorkspaceStore.java` |
| LocalWorkspaceStore | `src/main/java/com/openjiuwen/core/multitenant/workspace/store/LocalWorkspaceStore.java` |
| ObjectStorageWorkspaceStore | `src/main/java/com/openjiuwen/core/multitenant/workspace/store/ObjectStorageWorkspaceStore.java` |
| SkillManager | `src/main/java/com/openjiuwen/core/singleagent/skills/SkillManager.java` |
| TodoTool | `src/main/java/com/openjiuwen/harness/tools/TodoTool.java` |
| FileTodoStorage | `src/main/java/com/openjiuwen/harness/tools/FileTodoStorage.java` |
| KvTodoStorage | `src/main/java/com/openjiuwen/harness/tools/KvTodoStorage.java` |
| TodoStorage | `src/main/java/com/openjiuwen/harness/tools/TodoStorage.java` |
| KVStoreFactory | `src/main/java/com/openjiuwen/spi/store/KVStoreFactory.java` |
| BaseKVStore | `src/main/java/com/openjiuwen/spi/store/BaseKVStore.java` |
| RedisStore | `src/main/java/com/openjiuwen/extensions/store/kv/RedisStore.java` |
| RedisCheckpointer | `src/main/java/com/openjiuwen/extensions/checkpointer/redis/RedisCheckpointer.java` |
| Checkpointer | `src/main/java/com/openjiuwen/core/session/checkpointer/Checkpointer.java` |
| InMemoryCheckpointer | `src/main/java/com/openjiuwen/core/session/checkpointer/InMemoryCheckpointer.java` |
| PersistenceCheckpointer | `src/main/java/com/openjiuwen/core/session/checkpointer/PersistenceCheckpointer.java` |
| FileStore | `src/main/java/com/openjiuwen/core/session/store/FileStore.java` |
| 多租户数据隔离文档 | `documents/zh/2.开发指南/高阶用法/多租户数据隔离.md` |

