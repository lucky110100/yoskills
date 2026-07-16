# agent-core-java 多租户资源管理 Brainstorming 分析

> 分析日期：2026-07-16
> 项目：agent-core-java
> 范围：多租户资源管理功能，涵盖租户定义、资源界定、生命周期、存储路径、存储介质、Skill 同步

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

**关键设计决策：`tenantId` 是业务方定义的「不透明标识符」**——框架不赋予任何业务语义，不关心它代表的是个人、部门、组织还是其他维度。

### 1.2 Brainstorming 分析

| 租户类型 | 说明 | 当前支持度 | 建议 |
|---------|------|-----------|------|
| **个人（Personal）** | 单用户隔离场景，tenantId = userId | 支持 | 直接使用，无需改动 |
| **部门/团队（Department/Team）** | 组织架构下的部门级隔离，tenantId = deptId | 支持 | 需注意：部门下可能有多个用户共享同一 tenantId，需在 extensions 中传入 userId 做二次区分 |
| **组织/企业（Organization）** | 企业级隔离，tenantId = orgId | 支持 | 同上，extensions 可传入 deptId/userId |
| **项目（Project）** | 项目级隔离，tenantId = projectId | 支持 | 适合临时性协作场景 |
| **混合层级** | 如 组织 > 部门 > 个人的层级隔离 | **不完全支持** | 当前仅平面隔离，无层级关系 |

**核心问题：当前是平面租户模型，不支持层级租户。**

建议增强方向：

1. **方案A：保持平面模型 + extensions 辅助**
   - 不改变 TenantContext 核心结构
   - 业务方在 extensions 中传入层级信息（如 `parentTenantId`、`tenantType`）
   - 框架侧增加按层级查找的便捷方法
   - 优点：改动最小，向后兼容
   - 缺点：层级查询需要业务方自行维护

2. **方案B：引入 TenantHierarchy**
   - `TenantContext` 增加 `parentTenantId` 字段
   - `TenantWorkspaceResolver` 支持层级路径解析（如 `org1/dept1/user1/`）
   - Skill 查找支持继承链（先查自己 → 再查父租户 → 再查公共）
   - 优点：原生支持层级
   - 缺点：改动大，需要处理路径深度、权限继承等复杂问题

**推荐方案A**，原因：当前设计已明确声明 tenantId 是不透明标识符，层级语义应由业务方在 extensions 中自行管理。框架只负责按 tenantId 做数据空间隔离，这是正确的关注点分离。

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
| **LongTermMemory** | `TenantKVStoreKeyResolver` | KV key 前缀 | 是 |
| **用户记忆/变量** | `TenantKVStoreKeyResolver` | KV key 前缀 | 是 |

### 2.2 当前已明确**不隔离**的资源

| 资源 | 说明 |
|------|------|
| 智能体配置文件 | Agent 配置是系统级的 |
| 运行日志 | 全局共享 |
| ResourceMgr 资源池 | 工具、Workflow、Prompt、Model 等是系统级 |
| MessageQueue | 全局消息 |
| CallbackFramework | 全局回调 |

### 2.3 Brainstorming：是否还有其他属于租户的资源？

| 资源 | 分析 | 是否应由租户管理 | 建议 |
|------|------|-----------------|------|
| **Todo** | 当前 `FileTodoStorage` 存储在 `workspace/.todo/{sessionId}/todo.json` | **是**（已间接隔离） | Todo 依赖 workspace 路径，workspace 已隔离则 Todo 已隔离。但 TodoStorage 接口没有显式租户感知，建议增加 TenantAwareTodoStorage |
| **Session Store (FileStore)** | `FileStore` 持久化到 `session_store.json` | **是**（已间接隔离） | 依赖 workspace 路径，但 FileStore 路径硬编码为相对路径，需确认是否在租户 workspace 内 |
| **Graph Store** | `InMemoryStore` / `PersistenceGraphStore` | **是**（KV 层已隔离） | PersistenceGraphStore 使用 TenantKVStoreKeyResolver，已隔离 |
| **Vector Store** | Milvus/Chroma/PGVector/Elasticsearch | **未完全隔离** | 文档明确标注"VectorStore 集合名的 tenantId 前缀改造尚未完成"。建议按 `tenantId_collectionName` 格式隔离 |
| **DB Store** | `BaseDbStore`（MessageManager/ScopeUserMappingManager） | **未完全隔离** | 文档明确标注"SQL 层的 tenant_id 列改造尚未完成"。建议增加 tenant_id 列 + WHERE 条件 |
| **分布式锁** | `_lock/lockName` | **是**（KV 层已隔离） | 已通过 TenantKVStoreKeyResolver 前缀隔离 |
| **Object Storage** | S3/OBS/HDFS 上的文件 | **是**（路径层已隔离） | ObjectStorageWorkspaceStore 的 resolvePath 已包含 namespace/tenantId |
| **Team Workspace** | `TeamWorkspaceManager` | **部分隔离** | TeamWorkspace 有自己的 rootPath 配置，需确认是否在租户 workspace 下 |
| **MCP Server 配置** | 运行时连接的外部服务 | **视情况** | 如果不同租户连接不同 MCP Server，则需隔离配置 |
| **Prompt 模板** | 系统级 prompt | **视情况** | 如果租户有自定义 prompt 需求，则需隔离 |
| **Model 配置** | 模型选择偏好 | **视情况** | 如果不同租户使用不同模型或配额，则需隔离 |

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
├── 关系数据库类（未隔离 ✗）
│   ├── MessageManager
│   └── ScopeUserMappingManager
│
├── 向量数据库类（未隔离 ✗）
│   └── VectorStore 集合
│
└── 间接隔离（依赖 Workspace 路径）
    ├── Todo（通过 workspace 路径间接隔离）
    └── FileStore（通过 workspace 路径间接隔离）
```

---

## 三、各资源的生命周期管理

### 3.1 当前生命周期管理现状

| 资源 | 创建时机 | 销毁时机 | 管理方式 | 当前问题 |
|------|---------|---------|---------|---------|
| **TenantContext** | 请求入口 `TenantContextHolder.setCurrentTenant()` | 请求结束 `clearCurrentTenant()` | InheritableThreadLocal | 无显式租户注册/注销流程 |
| **Workspace** | `initializeTenantSpace()` 幂等创建 | **无销毁机制** | ConcurrentHashMap 缓存 + Files.createDirectories | 租户删除后残留目录 |
| **Skills** | 首次访问时自动创建目录 | **无销毁机制** | SkillManager + refreshIncrementally | 无租户 Skill 清理逻辑 |
| **Tmp** | `initializeTenantSpace()` 创建 | **无清理机制** | 无 | 临时文件可能无限增长 |
| **Checkpoints** | Session 创建时 | Session 正常完成时 `release()` | Checkpointer lifecycle hooks | 异常中断时可能残留 |
| **Session State (KV)** | 首次写入时 | `release(sessionId)` 删除前缀 | KVStore key lifecycle | 需要业务方主动调用 release |
| **Team Memory** | 团队创建时 | **无销毁机制** | TeamLifecycle 枚举 | CREATED/RUNNING/PAUSED/COMPLETED 无自动清理 |
| **Todo** | 任务创建时 | 任务完成/取消时 | FileTodoStorage | 依赖 sessionId，session 释放后文件残留 |
| **Vector Store** | 首次写入时 | **无销毁机制** | 无 | 租户删除后向量数据残留 |

### 3.2 Brainstorming：生命周期管理增强建议

#### 3.2.1 租户生命周期

当前**缺少租户级别的生命周期管理**。建议引入：

```java
public enum TenantLifecycle {
    PROVISIONING,   // 资源分配中
    ACTIVE,         // 正常使用
    SUSPENDED,      // 暂停（保留数据，禁止访问）
    DEPROVISIONING, // 资源回收中
    DELETED         // 已删除
}

public interface TenantLifecycleManager {
    TenantContext provision(String tenantId, Map<String, String> extensions);
    void suspend(String tenantId);
    void reactivate(String tenantId);
    void deprovision(String tenantId, boolean purgeData);
    TenantLifecycle getStatus(String tenantId);
}
```

#### 3.2.2 资源生命周期分层

```
租户生命周期
  └── 控制所有租户资源的创建和销毁
       ├── Workspace 生命周期（租户级：随租户创建/销毁）
       ├── Skill 生命周期（租户级：随租户创建/销毁，热加载独立）
       ├── Tmp 生命周期（会话级：随会话创建/定期清理）
       ├── Checkpoint 生命周期（会话级：随会话创建/完成时清理）
       ├── Session State 生命周期（会话级：随会话创建/释放时清理）
       ├── Team Memory 生命周期（团队级：随团队创建/归档时清理）
       └── Todo 生命周期（任务级：随任务创建/完成时清理）
```

#### 3.2.3 资源清理策略

| 资源 | 清理触发 | 清理方式 | 保留策略 |
|------|---------|---------|---------|
| Workspace | 租户注销 | 递归删除目录 | 可选：归档到对象存储 |
| Skills | 租户注销 | 删除租户 Skill 目录 | 必须保留公共 Skill |
| Tmp | 定时任务 / Session 结束 | 删除超过 TTL 的文件 | TTL 可配置（默认 24h） |
| Checkpoints | Session 正常完成 | 已有 `release()` | 无需保留 |
| Session State | Session 结束 | 已有 `release()` | 无需保留 |
| Team Memory | 团队归档 | 压缩归档 | 归档到对象存储 |
| Vector Data | 租户注销 | 删除集合/命名空间 | 可选：归档 |

---

## 四、存储路径层级结构与向后兼容性

### 4.1 当前实际路径结构

根据 `TenantWorkspaceResolver` 和 `TenantNamespaceFactories.PATH_DEFAULT` 的实现：

**PATH_DEFAULT 命名空间逻辑：**
```java
(ctx, rawKey) -> {
    if (ctx != null && ctx.isTenantAware()) {
        return ctx.safeTenantId() + "/" + rawKey;  // 例如 "dept_fin_03/tenants"
    }
    return rawKey;  // 例如 "tenants"
}
```

**实际路径解析：**
```java
// tenantNamespace(ctx) = PATH_DEFAULT.namespace(ctx, "tenants")
// 当 isTenantAware 时: tenantId + "/tenants" = "dept_fin_03/tenants"

// resolveWorkspaceRoot:
Path.of(baseWorkspacePath, "dept_fin_03/tenants", "dept_fin_03", "workspace")
// = baseWorkspacePath/dept_fin_03/tenants/dept_fin_03/workspace
```

因此当前实际目录结构为：

```
baseWorkspacePath/
├── tmp/                                    # 默认临时目录
├── workspace/                              # 默认工作目录
├── skills/                                 # 默认 Skill
├── checkpoints/                            # 默认检查点
├── team_memory/                            # 默认团队记忆
├── dept_fin_03/                            # ← tenantId 目录
│   └── tenants/                            # ← namespace 层
│       └── dept_fin_03/                    # ← 重复的 tenantId！
│           ├── workspace/
│           ├── skills/
│           ├── tmp/
│           ├── checkpoints/
│           └── team_memory/
```

### 4.2 问题分析：tenantId 重复

当前路径 `baseWorkspacePath/{tenantId}/tenants/{tenantId}/workspace` 存在 **tenantId 重复**问题：

- 第一层 `{tenantId}/` 来自 `PATH_DEFAULT.namespace(ctx, "tenants")` = `tenantId/tenants`
- 第二层 `{tenantId}` 来自 `resolvePath(namespace, tenantId, subDir)` 中的 `tenantId` 参数

这导致路径中出现两次 tenantId，不够简洁。

### 4.3 用户提议的层级结构

```
baseWorkspacePath/
├── tmp/                          # 默认临时目录（无租户时使用）
├── sessions/                     # 默认 sessions（无租户时使用）
├── skills/                       # 默认 skill（无租户时使用）
├── tenants/
│   ├── {tenantId_1}/             # 租户1（tenantId 由业务方定义）
│   │   ├── skills/
│   │   ├── tmp/
│   │   └── sessions/
│   ├── {tenantId_2}/             # 租户2
│   │   ├── skills/
│   │   ├── tmp/
│   │   └── sessions/
```

### 4.4 建议的优化层级结构

综合当前实现和用户提议，建议调整为：

```
baseWorkspacePath/
├── workspace/                    # 默认工作目录（无租户时使用）
├── skills/                       # 默认 Skill（无租户时使用，即公共 Skill）
├── tmp/                          # 默认临时目录（无租户时使用）
├── checkpoints/                  # 默认检查点（无租户时使用）
├── team_memory/                  # 默认团队记忆（无租户时使用）
├── tenants/
│   ├── {tenantId_1}/
│   │   ├── workspace/
│   │   ├── skills/
│   │   ├── tmp/
│   │   ├── checkpoints/
│   │   ├── team_memory/
│   │   └── todo/
│   ├── {tenantId_2}/
│   │   ├── workspace/
│   │   ├── skills/
│   │   ├── tmp/
│   │   ├── checkpoints/
│   │   ├── team_memory/
│   │   └── todo/
```

### 4.5 实现调整方案

需要修改 `TenantNamespaceFactories.PATH_DEFAULT`：

```java
// 当前（有重复）：
public static final TenantNamespaceFactory PATH_DEFAULT =
    (ctx, rawKey) -> {
        if (ctx != null && ctx.isTenantAware()) {
            return ctx.safeTenantId() + "/" + rawKey;
        }
        return rawKey;
    };

// 建议修改为：
public static final TenantNamespaceFactory PATH_DEFAULT =
    (ctx, rawKey) -> {
        if (ctx != null && ctx.isTenantAware()) {
            return "tenants/" + ctx.safeTenantId();
            // rawKey（"tenants"）不再参与路径拼接
        }
        return rawKey;  // 无租户时返回 "tenants"，但不会走到 tenants 分支
    };
```

同时需要修改 `TenantWorkspaceResolver`，去掉 `tenantNamespace()` 中间层：

```java
// 当前：
private String tenantNamespace(TenantContext ctx) {
    return namespaceFactory.namespace(ctx, "tenants");
}
public Path resolveWorkspaceRoot(TenantContext ctx) {
    String ns = tenantNamespace(ctx);
    return Path.of(baseWorkspacePath, ns, ctx.safeTenantId(), "workspace");
    // 结果: baseWorkspacePath/dept_fin_03/tenants/dept_fin_03/workspace ← 重复
}

// 建议修改为：
private String tenantBasePath(TenantContext ctx) {
    return namespaceFactory.namespace(ctx, "");
    // 有租户时返回 "tenants/{tenantId}"
    // 无租户时返回 "" (空字符串，即 baseWorkspacePath 本身)
}
public Path resolveWorkspaceRoot(TenantContext ctx) {
    if (!ctx.isTenantAware()) {
        return Path.of(baseWorkspacePath, "workspace");
    }
    String base = tenantBasePath(ctx);
    return Path.of(baseWorkspacePath, base, "workspace").toAbsolutePath().normalize();
    // 结果: baseWorkspacePath/tenants/dept_fin_03/workspace ← 无重复
}
```

### 4.6 向后兼容性分析

| 场景 | 当前行为 | 修改后行为 | 是否兼容 |
|------|---------|-----------|---------|
| 不传 TenantContext | 路径 = `baseWorkspacePath/` | 路径 = `baseWorkspacePath/workspace/` | ⚠️ 不兼容！workspace 子目录变化 |
| tenantId 为 null | 同上 | 同上 | ⚠️ 同上 |
| enableTenantIsolation = false | 同上 | 同上 | ⚠️ 同上 |
| 有租户 | `baseWorkspacePath/{tid}/tenants/{tid}/workspace` | `baseWorkspacePath/tenants/{tid}/workspace` | ⚠️ 路径变化，数据需迁移 |

**兼容性问题：**

1. **无租户场景**：当前 `resolveWorkspaceRoot()` 在无租户时返回 `baseWorkspacePath` 本身，如果修改为 `baseWorkspacePath/workspace/`，则所有已有代码依赖 `baseWorkspacePath` 作为工作目录的地方都会断裂。

2. **有租户场景**：路径从 `{tid}/tenants/{tid}/` 变为 `tenants/{tid}/`，需要数据迁移。

**向后兼容方案：**

```java
// 方案：通过配置开关控制路径策略
public enum PathStrategy {
    LEGACY,     // 当前路径策略（{tid}/tenants/{tid}/...）
    FLAT,       // 新路径策略（tenants/{tid}/...）
    UNIFIED     // 统一路径策略（见下文）
}

// TenantWorkspaceResolver 增加策略选择
public Path resolveWorkspaceRoot(TenantContext ctx) {
    if (!ctx.isTenantAware()) {
        switch (pathStrategy) {
            case LEGACY:  return Path.of(baseWorkspacePath);
            case FLAT:    return Path.of(baseWorkspacePath);
            case UNIFIED: return Path.of(baseWorkspacePath, "workspace");
        }
    }
    switch (pathStrategy) {
        case LEGACY:  return Path.of(baseWorkspacePath, ns, ctx.safeTenantId(), "workspace");
        case FLAT:    return Path.of(baseWorkspacePath, "tenants", ctx.safeTenantId(), "workspace");
        case UNIFIED: return Path.of(baseWorkspacePath, "tenants", ctx.safeTenantId(), "workspace");
    }
}
```

**推荐做法：**

- 无租户场景保持现有行为（`baseWorkspacePath` 直接作为根），确保完全向后兼容
- 有租户场景改为 `baseWorkspacePath/tenants/{tenantId}/...`，去掉重复 tenantId
- 提供迁移工具脚本，将旧路径数据迁移到新路径

---

## 五、存储介质分析

### 5.1 当前各资源的存储介质

| 资源 | 当前存储介质 | 是否可配置 | SPI 支持 |
|------|------------|-----------|---------|
| **Workspace 文件** | 本地文件系统 | 是（TieredWorkspaceManager） | WorkspaceStore SPI |
| **Skills 文件** | 本地文件系统 | 是（同上） | 同上 |
| **Tmp 文件** | 本地文件系统 | 是（同上） | 同上 |
| **Checkpoints 文件** | 本地文件系统 | 是（同上） | 同上 |
| **Team Memory 文件** | 本地文件系统 | 是（同上） | 同上 |
| **Session State** | InMemory / KV Store | 是（CheckpointerFactory SPI） | CheckpointerProvider SPI |
| **Agent State** | InMemory / KV Store | 是 | 同上 |
| **Workflow State** | InMemory / KV Store | 是 | 同上 |
| **Graph State** | InMemory / KV Store | 是 | 同上 |
| **KV Store 后端** | InMemory / Redis | 是（KVStoreProvider SPI） | KVStoreProvider SPI |
| **Vector Store** | InMemory / Milvus / Chroma / PGVector / ES | 是 | VectorStoreProvider SPI |
| **Object Storage** | 本地 / OBS / S3 / HDFS | 是 | ObjectStorageProvider SPI |
| **Todo** | 本地文件系统（FileTodoStorage） | **否** | **无 SPI** |
| **FileStore (Session)** | 本地 JSON 文件 | **否** | **无 SPI** |

### 5.2 已有的 SPI 体系

项目已建立了较为完善的存储后端 SPI 体系：

```
WorkspaceStoreProvider (SPI)
├── LocalWorkspaceStoreProvider
├── ObsWorkspaceStoreProvider
├── S3WorkspaceStoreProvider
└── HdfsWorkspaceStoreProvider

KVStoreProvider (SPI)
├── InMemoryKVStoreProvider
└── RedisKVStoreProvider

CheckpointerProvider (SPI)
├── InMemoryCheckpointerProvider
├── PersistenceCheckpointerProvider
└── RedisCheckpointer$Provider

VectorStoreProvider (SPI)
├── InMemoryVectorStoreProvider
├── MilvusVectorStoreProvider
├── ChromaVectorStoreProvider
├── PGVectorStoreProvider
└── ElasticsearchVectorStoreProvider

ObjectStorageProvider (SPI)
└── LocalObjectStorageClient
```

### 5.3 Brainstorming：统一存储介质配置

#### 5.3.1 问题：不同资源的存储介质是独立的

当前每个资源类型有各自的存储后端 SPI，配置分散。无法统一指定"所有资源使用 Redis"或"所有资源使用 OBS"。

#### 5.3.2 建议方案：抽象资源持久化接口

```
统一存储抽象层
│
├── TenantResourceStore (统一接口)
│   ├── put(key, value)
│   ├── get(key)
│   ├── delete(key)
│   ├── list(prefix)
│   └── exists(key)
│
├── TenantResourceStoreProvider (SPI)
│   ├── LocalFsStoreProvider       → 本地文件系统实现
│   ├── RedisStoreProvider         → Redis KV 实现
│   ├── RdbmsStoreProvider         → 关系数据库实现
│   ├── ObsStoreProvider           → 对象存储实现
│   └── HdfsStoreProvider          → HDFS 实现
│
└── TenantStorageConfig (统一配置)
    ├── defaultStoreType: "local"   # 全局默认存储类型
    ├── resourceStoreOverrides:     # 按资源类型覆盖
    │   ├── workspace: "local"
    │   ├── skills: "local"
    │   ├── tmp: "local"
    │   ├── session_state: "redis"
    │   ├── checkpoints: "redis"
    │   ├── vector: "milvus"
    │   └── todo: "local"
    └── tieredConfig:               # 分层存储配置
        ├── primary: "local"
        └── secondary: ["obs", "hdfs"]
```

#### 5.3.3 具体实现建议

**Step 1：统一资源存储接口**

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

**Step 2：资源类型枚举**

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

**Step 3：统一配置**

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

**Step 4：TodoStorage 和 FileStore 增加 SPI**

```java
// 当前 TodoStorage 是普通接口，无 SPI 发现机制
public interface TodoStorage { ... }

// 建议：增加 TodoStorageProvider SPI
public interface TodoStorageProvider {
    String typeName();
    TodoStorage create(Map<String, Object> conf);
}

// 内置实现
public class FileTodoStorageProvider implements TodoStorageProvider {
    public String typeName() { return "file"; }
    public TodoStorage create(Map<String, Object> conf) {
        return new FileTodoStorage(Path.of((String) conf.get("basePath")));
    }
}

public class RedisTodoStorageProvider implements TodoStorageProvider {
    public String typeName() { return "redis"; }
    public TodoStorage create(Map<String, Object> conf) { ... }
}
```

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

### 6.1 当前 Skill 加载机制

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

### 6.2 问题场景

新建租户时，租户的 `skills/` 目录为空。需要从系统默认路径（公共 Skill）同步到租户 Skill 目录。但直接复制会导致：

1. **冗余**：每个租户都复制一份公共 Skill，占用存储
2. **更新困难**：公共 Skill 更新后，需要同步到所有租户
3. **影响热加载**：SkillManager 的 `refreshIncrementally()` 依赖 mtime 变化检测

### 6.3 设计方案分析

#### 方案 A：符号链接（Symlink）

```
tenants/{tenantId}/skills/
├── private_skill_1/          # 租户自有 Skill（真实目录）
├── private_skill_2/          # 租户自有 Skill（真实目录）
├── common_skill_1 -> ../../../skills/common_skill_1/   # 符号链接到公共 Skill
└── common_skill_2 -> ../../../skills/common_skill_2/   # 符号链接到公共 Skill
```

**优点：**
- 零冗余，公共 Skill 只存一份
- 公共 Skill 更新后所有租户立即可见
- SkillManager 的 `refreshIncrementally()` 正常工作（symlink 的 mtime 跟随目标文件）
- 符号链接创建/删除成本低

**缺点：**
- Windows 上创建符号链接需要管理员权限或开发者模式
- 需要处理符号链接循环问题（TenantPathSecurity 已有 symlink 检测）
- 对象存储（OBS/S3/HDFS）不支持符号链接

**实现：**
```java
public class TenantSkillSyncManager {
    private final Path publicSkillRoot;
    private final TenantWorkspaceResolver workspaceResolver;
    
    public void syncPublicSkills(TenantContext ctx) {
        Path tenantSkillRoot = workspaceResolver.resolveSkillRoot(ctx);
        if (tenantSkillRoot == null) return;
        
        try (DirectoryStream<Path> stream = Files.newDirectoryStream(publicSkillRoot)) {
            for (Path publicSkill : stream) {
                if (!Files.isDirectory(publicSkill)) continue;
                Path linkTarget = tenantSkillRoot.resolve(publicSkill.getFileName());
                if (Files.exists(linkTarget)) continue;  // 租户已有同名 Skill，跳过
                
                // 创建符号链接
                Path relativePath = tenantSkillRoot.relativize(publicSkill);
                Files.createSymbolicLink(linkTarget, relativePath);
            }
        }
    }
}
```

#### 方案 B：联合查找（不复制，查找时合并）

这是**当前已有的方案**——SkillTool 双层查找逻辑。

```
租户 Skill roots = [tenantSkillRoot, publicSkillRoot]
查找顺序：tenantSkillRoot → publicSkillRoot
```

**优点：**
- 当前已实现，无需改动
- 零冗余
- 无平台兼容性问题

**缺点：**
- 租户无法"修改"公共 Skill（只能覆盖同名）
- 无法在租户目录中看到公共 Skill 列表（需查找才知道）

**当前实现已够用，但缺少显式的"同步"语义。**

#### 方案 C：引用表（Reference Table）

```java
// 租户 Skill 引用表
public interface TenantSkillRefStore {
    // 添加引用：租户引用公共 Skill
    void addRef(String tenantId, String skillName, SkillRefType type);
    
    // 移除引用
    void removeRef(String tenantId, String skillName);
    
    // 获取租户可见的所有 Skill（引用 + 自有）
    List<SkillRef> listVisible(String tenantId);
    
    // 获取引用的公共 Skill 的实际路径
    Path resolvePublicSkillPath(String skillName);
}

public enum SkillRefType {
    INHERITED,    // 从公共 Skill 继承（自动同步更新）
    OVERLAY,      // 租户覆盖（同名私有 Skill 优先）
    CUSTOM        // 租户自建
}
```

**优点：**
- 显式的同步关系管理
- 可以跟踪哪些租户在使用哪些公共 Skill
- 可以实现"公共 Skill 更新通知"机制
- 存储介质无关（引用表可以存在 KV/DB 中）

**缺点：**
- 增加了一层间接引用，复杂度较高
- 需要修改 SkillManager 的查找逻辑

#### 方案 D：OverlayFS 式分层（推荐）

```
Skill 查找链
    ↓
租户 Skill 层（可写层）
    ├── 私有 Skill（实际文件）
    └── 覆盖标记（.overlay/skill_name → "overridden"）
    ↓ (如果未找到或未覆盖)
公共 Skill 层（只读层）
    └── 公共 Skill（实际文件）
```

```java
public class OverlaySkillManager {
    private final SkillManager tenantSkillManager;   // 租户私有 Skill
    private final SkillManager publicSkillManager;    // 公共 Skill
    private final Path overlayDir;                    // 覆盖标记目录
    
    public List<Skill> getAllVisibleSkills() {
        List<Skill> result = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        
        // 第一层：租户私有 Skill
        for (Skill skill : tenantSkillManager.getAllInOrder()) {
            result.add(skill);
            seen.add(skill.getName());
        }
        
        // 第二层：公共 Skill（跳过已被租户覆盖的）
        for (Skill skill : publicSkillManager.getAllInOrder()) {
            if (!seen.contains(skill.getName())) {
                result.add(skill);
                seen.add(skill.getName());
            }
        }
        
        return result;
    }
    
    // 热加载支持：分别对两层做增量刷新
    public void refreshIncrementally() {
        tenantSkillManager.refreshIncrementally(tenantSkillRoots);
        publicSkillManager.refreshIncrementally(publicSkillRoots);
    }
}
```

### 6.4 Skill 同步与热加载

**关键问题：公共 Skill 更新后，如何通知租户？**

| 方案 | 热加载兼容 | 实时性 | 复杂度 |
|------|-----------|--------|--------|
| A. Symlink | 完全兼容（mtime 跟随目标） | 实时 | 低 |
| B. 联合查找 | 完全兼容（SkillManager 已支持多 root） | 实时 | 最低（当前方案） |
| C. 引用表 | 需刷新引用表 | 需轮询/通知 | 高 |
| D. OverlayFS | 完全兼容（分层独立刷新） | 实时 | 中 |

### 6.5 推荐方案

**推荐方案 B + D 的组合**，理由：

1. **保持当前方案 B 作为基础**：SkillTool 双层查找已实现且工作良好
2. **增加 OverlaySkillManager 作为统一入口**：
   - 封装双层查找逻辑
   - 提供显式的 `refreshIncrementally()` 方法（分层独立刷新）
   - 提供覆盖管理（租户可显式"覆盖"公共 Skill）
3. **可选提供方案 A（Symlink）作为优化**：
   - 在支持符号链接的平台上，可以创建 Symlink 让租户 Skill 目录中"可见"公共 Skill
   - 这是用户体验优化，不影响查找逻辑
4. **不推荐方案 C（引用表）**：过度设计，当前场景不需要

**具体实现步骤：**

```
Step 1: 创建 OverlaySkillManager
    - 封装租户 SkillManager + 公共 SkillManager
    - getAllVisibleSkills() 实现双层查找
    - refreshIncrementally() 分层独立刷新

Step 2: 修改 SkillTool / ListSkillTool
    - 使用 OverlaySkillManager 替代直接使用 SkillManager
    - 查找逻辑不变（租户优先 → 公共），只是入口统一

Step 3: 增加租户 Skill 初始化钩子
    - 在 TenantWorkspaceResolver.initializeTenantSpace() 中
    - 可选：创建 Symlink 到公共 Skill（平台支持时）
    - 或：仅创建租户 Skill 空目录（依赖 OverlaySkillManager 联合查找）

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
| **P0** | 修复 tenantId 路径重复问题 | TenantWorkspaceResolver, TenantNamespaceFactories | 小 |
| **P0** | 完成 PersistenceCheckpointer 的 tenantId 前缀改造 | PersistenceCheckpointer | 小（已部分完成） |
| **P0** | 完成 VectorStore 集合名的 tenantId 前缀改造 | VectorStore 相关类 | 中 |
| **P0** | 完成 BaseDbStore SQL 层 tenant_id 列改造 | MessageManager, ScopeUserMappingManager | 中 |
| **P1** | 引入 TenantLifecycleManager | 新增接口 + 实现 | 中 |
| **P1** | 增加 OverlaySkillManager 统一 Skill 查找 | 新增类 + 修改 SkillTool | 中 |
| **P1** | TodoStorage 增加 SPI | TodoStorageProvider + File/Redis 实现 | 小 |
| **P2** | 统一存储介质配置（TenantResourceStore） | 新增抽象层 | 大 |
| **P2** | Tmp 文件 TTL 自动清理 | 新增定时任务 | 小 |
| **P2** | 租户数据归档/迁移工具 | 新增工具类 | 中 |
| **P3** | 层级租户支持（extensions 增强） | TenantContext 扩展 | 小 |

### 7.2 关键设计原则

1. **向后兼容优先**：所有改动必须保证 `enableTenantIsolation=false` 时行为完全不变
2. **SPI 驱动**：新功能通过 SPI 扩展，不修改核心逻辑
3. **租户标识不透明**：框架不赋予 tenantId 业务语义
4. **存储介质可替换**：通过 SPI 和配置实现按资源类型选择存储后端
5. **安全纵深防御**：路径隔离 + KV 前缀隔离 + SQL tenant_id 列，三层防护互为补充

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
| TodoStorage | `src/main/java/com/openjiuwen/harness/tools/TodoStorage.java` |
| Checkpointer | `src/main/java/com/openjiuwen/core/session/checkpointer/Checkpointer.java` |
| InMemoryCheckpointer | `src/main/java/com/openjiuwen/core/session/checkpointer/InMemoryCheckpointer.java` |
| PersistenceCheckpointer | `src/main/java/com/openjiuwen/core/session/checkpointer/PersistenceCheckpointer.java` |
| FileStore | `src/main/java/com/openjiuwen/core/session/store/FileStore.java` |
| 多租户数据隔离文档 | `documents/zh/2.开发指南/高阶用法/多租户数据隔离.md` |
