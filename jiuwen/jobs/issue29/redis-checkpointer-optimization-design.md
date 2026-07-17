# RedisCheckpointer 冗余消除优化设计方案

> 日期：2026-07-17
> 项目：agent-core-java
> 范围：消除 `extensions/checkpointer/redis` 与 `core/session/checkpointer` 的冗余代码
> 前置分析：见本文档附录 A

---

## 一、问题陈述

### 1.1 现状

当前存在两套独立的 Checkpointer 实现：

| 目录 | 文件数 | 行数（约） | 角色 |
|------|-------|----------|------|
| `core/session/checkpointer/` | 9 | ~1200 | 核心 SPI + InMemory + Persistence |
| `extensions/checkpointer/redis/` | 9 | ~1200 | Redis 专属实现 |

### 1.2 冗余分析

#### 编排层（Checkpointer 子类）

`RedisCheckpointer` 与 `PersistenceCheckpointer` 的编排逻辑（`preAgentExecute`、`postAgentExecute`、`preWorkflowExecute`、`postWorkflowExecute`）**逐行相同**，是复制粘贴。

#### 存储层（Storage 子类）

| 对比项 | Persistence 内部类 | Redis 独立类 | 差异 |
|--------|-------------------|-------------|------|
| `PersistenceAgentStorage` vs `AgentStorage` | 同 | 同 | 仅序列化方式不同 |
| `PersistenceWorkflowStorage` vs `WorkflowStorage` | 同 | 同 | 仅序列化方式 + TTL 不同，`processInteractiveInputs` 完全复制 |
| `PersistenceGraphStore` vs `GraphStore` | 同 | 同 | 仅序列化方式 + TTL 不同 |

#### 关键事实

1. **`RedisStore extends BaseKVStore`**——`PersistenceCheckpointer` 接受 `BaseKVStore`，传入 `RedisStore` 即为 Redis 存储
2. **Key 格式完全相同**——均使用 `TenantKVStoreKeyResolver.resolveKey(Checkpointer.buildKeyWithNamespace(...))`
3. **`CompletableFuture` 是假异步**——`RedisCheckpointer` 内部全部 `.join()` 同步使用
4. **Redis 连接被创建两次**——`RedisCheckpointer.Provider` 自建 `RedisStore`，绕过 `KVStoreFactory`；而 `kvStoreConfig` 又创建一个 `RedisStore`

### 1.3 冗余量化

| 可消除的冗余代码 | 行数 |
|----------------|------|
| `RedisCheckpointer` 编排方法 | ~90 |
| `AgentStorage` | ~180 |
| `WorkflowStorage`（含复制的 `processInteractiveInputs`） | ~280 |
| `GraphStore` | ~130 |
| `BaseRedisStorage` 工具类 | ~330 |
| `RedisCheckpointerConfig` + `RedisConnectionConfig` + `RedisTTLConfig` | ~200 |
| **合计** | **~1210** |

---

## 二、设计方案

### 2.1 核心思路

**消除 `RedisCheckpointer`，让 `PersistenceCheckpointer` 直接使用 `RedisStore`（通过 `KVStoreFactory`），补齐 TTL 和序列化扩展能力。**

```
改造前（两套独立实现）:
  RedisCheckpointer(RedisStore, ttl)        ← 9 文件，~1200 行冗余
  PersistenceCheckpointer(BaseKVStore)      ← 只能 Java Object 直存

改造后（统一实现）:
  PersistenceCheckpointer(BaseKVStore, CheckpointTtlConfig)
    ├── CheckpointTtlConfig.ttlSeconds       ← 新增，可选
    ├── CheckpointTtlConfig.refreshOnRead    ← 新增，可选
    └── 内部序列化策略自动适配 BaseKVStore 实际类型
```

### 2.2 变更清单

#### 变更 1：新增 `CheckpointTtlConfig`

```java
@Data
@Builder
public class CheckpointTtlConfig {
    @Builder.Default
    private Integer ttlSeconds;       // null 表示无 TTL
    @Builder.Default
    private boolean refreshOnRead = false;

    public static CheckpointTtlConfig fromMap(Map<String, Object> map) {
        if (map == null) return CheckpointTtlConfig.builder().build();
        Integer ttlSeconds = null;
        if (map.containsKey("default_ttl")) {
            ttlSeconds = (int) (((Number) map.get("default_ttl")).doubleValue() * 60);
        }
        boolean refreshOnRead = Boolean.TRUE.equals(map.get("refresh_on_read"));
        return CheckpointTtlConfig.builder()
                .ttlSeconds(ttlSeconds)
                .refreshOnRead(refreshOnRead)
                .build();
    }
}
```

**位置：** `core/session/checkpointer/CheckpointTtlConfig.java`

#### 变更 2：修改 `PersistenceCheckpointer` 增加 TTL 支持

```java
public class PersistenceCheckpointer extends Checkpointer {
    private final BaseKVStore kvStore;
    private final CheckpointTtlConfig ttlConfig;
    private final PersistenceAgentStorage agentStorage;
    private final PersistenceWorkflowStorage workflowStorage;
    private final PersistenceGraphStore graphStoreField;

    public PersistenceCheckpointer(BaseKVStore kvStore) {
        this(kvStore, CheckpointTtlConfig.builder().build());
    }

    public PersistenceCheckpointer(BaseKVStore kvStore, CheckpointTtlConfig ttlConfig) {
        this.kvStore = Objects.requireNonNull(kvStore);
        this.ttlConfig = ttlConfig != null ? ttlConfig : CheckpointTtlConfig.builder().build();
        this.agentStorage = new PersistenceAgentStorage(kvStore, this.ttlConfig);
        this.workflowStorage = new PersistenceWorkflowStorage(kvStore, this.ttlConfig);
        this.graphStoreField = new PersistenceGraphStore(kvStore, this.ttlConfig);
    }
}
```

#### 变更 3：修改 `PersistenceAgentStorage` 增加 TTL

在 `save()` 中，如果 `ttlConfig.getTtlSeconds() != null`，pipeline set 时携带 TTL：

```java
@Override
public void save(BaseSession session) {
    Map<String, Object> state = session.state().getState();
    String sessionId = session.sessionId();
    String agentId = getAgentId(session);

    String dumpTypeKey = TenantKVStoreKeyResolver.resolveKey(
        buildKeyWithNamespace(sessionId, SESSION_NAMESPACE_AGENT, agentId, STATE_BLOBS_DUMP_TYPE));
    String blobKey = TenantKVStoreKeyResolver.resolveKey(
        buildKeyWithNamespace(sessionId, SESSION_NAMESPACE_AGENT, agentId, STATE_BLOBS));

    KVStorePipeline pipeline = kvStore.pipeline();
    pipeline.set(dumpTypeKey, "java_serialized", ttlConfig.getTtlSeconds());
    pipeline.set(blobKey, state, ttlConfig.getTtlSeconds());
    pipeline.execute();
}
```

在 `recover()` 中，如果 `ttlConfig.isRefreshOnRead() && ttlConfig.getTtlSeconds() != null`，读取后刷新 TTL：

```java
@Override
public void recover(BaseSession session, InteractiveInput inputs) {
    // ... 现有 recover 逻辑 ...
    
    // TTL refresh on read
    if (ttlConfig.isRefreshOnRead() && ttlConfig.getTtlSeconds() != null) {
        kvStore.pipeline()
            .set(dumpTypeKey, "java_serialized", ttlConfig.getTtlSeconds())
            .set(blobKey, blob, ttlConfig.getTtlSeconds())
            .execute();
    }
}
```

**同理修改 `PersistenceWorkflowStorage` 和 `PersistenceGraphStore`。**

#### 变更 4：修改 `KVStorePipeline.set()` 支持 TTL 参数

当前 `KVStorePipeline.set(key, value)` 无 TTL 参数。需要增加重载：

```java
public class KVStorePipeline {
    // 操作记录格式：[action, key, value, expiry?]
    
    public KVStorePipeline set(String key, Object value) {
        return set(key, value, null);
    }

    public KVStorePipeline set(String key, Object value, Integer expiry) {
        operations.add(new Object[]{"set", key, value, expiry});
        return this;
    }
}
```

同步修改 `BaseKVStore` 各实现（`InMemoryKVStore`、`DbBasedKVStore`、`RedisStore`）的 pipeline 执行器，识别 expiry 参数。

#### 变更 5：修改 `PersistenceCheckpointerProvider` 支持 TTL 配置

```java
public class PersistenceCheckpointerProvider implements CheckpointerProvider {
    @Override
    public String typeName() { return "persistence"; }

    @Override
    public Checkpointer create(Map<String, Object> conf) {
        if (conf == null) conf = Map.of();

        // 1. 获取 BaseKVStore：直接注入 或 通过 KVStoreFactory 创建
        BaseKVStore kvStore = resolveKvStore(conf);

        // 2. 解析 TTL 配置
        CheckpointTtlConfig ttlConfig = CheckpointTtlConfig.fromMap(
            conf.get("ttl") instanceof Map ? (Map<String, Object>) conf.get("ttl") : null);

        return new PersistenceCheckpointer(kvStore, ttlConfig);
    }

    private BaseKVStore resolveKvStore(Map<String, Object> conf) {
        // 优先级1：直接注入实例
        Object kvStoreObj = conf.get("kv_store");
        if (kvStoreObj instanceof BaseKVStore kvStore) return kvStore;

        // 优先级2：通过 KVStoreFactory 创建
        Object kvStoreType = conf.get("kv_store_type");
        if (kvStoreType instanceof String type) {
            @SuppressWarnings("unchecked")
            Map<String, Object> kvStoreConf = conf.get("kv_store_conf") instanceof Map
                ? (Map<String, Object>) conf.get("kv_store_conf") : Map.of();
            return KVStoreFactory.create(type, kvStoreConf);
        }

        // 降级：InMemoryCheckpointer
        return null; // Provider 返回 InMemoryCheckpointer
    }
}
```

#### 变更 6：修改 `RunnerImpl.start()` 共享 BaseKVStore 实例

```java
public boolean start() {
    // 先创建共享 BaseKVStore
    Map<String, Object> kvStoreConfig = RunnerConfig.getRunnerConfig().getKvStoreConfig();
    BaseKVStore sharedKvStore = null;
    if (kvStoreConfig != null && kvStoreConfig.get("type") != null) {
        String type = (String) kvStoreConfig.get("type");
        Map<String, Object> conf = kvStoreConfig.get("conf") instanceof Map
            ? (Map<String, Object>) kvStoreConfig.get("conf") : Map.of();
        sharedKvStore = KVStoreFactory.create(type, conf);
    }

    // Checkpointer 复用共享实例
    Map<String, Object> checkpointerConfig = RunnerConfig.getRunnerConfig().getCheckpointerConfig();
    if (checkpointerConfig != null) {
        String type = (String) checkpointerConfig.getOrDefault("type", "in_memory");
        Map<String, Object> conf = new LinkedHashMap<>(
            (Map<String, Object>) checkpointerConfig.getOrDefault("conf", Map.of()));
        if (sharedKvStore != null && "persistence".equals(type)) {
            conf.put("kv_store", sharedKvStore);  // 注入共享实例
        }
        CheckpointerFactory.setDefaultCheckpointer(CheckpointerFactory.create(type, conf));
    }
    // ... 其余 start 逻辑
}
```

#### 变更 7：删除 `extensions/checkpointer/redis/` 整个目录

删除文件列表：

| 文件 | 行数 | 删除理由 |
|------|------|---------|
| `RedisCheckpointer.java` | 639 | 冗余编排逻辑 |
| `RedisCheckpointerConfig.java` | ~80 | 合并到 `CheckpointTtlConfig` |
| `RedisConnectionConfig.java` | ~40 | 合并到 `kvStoreConfig` |
| `RedisTTLConfig.java` | ~30 | 合并到 `CheckpointTtlConfig` |
| `BaseRedisStorage.java` | 330 | 工具类，逻辑内联到 Persistence 内部类 |
| `AgentStorage.java` | 195 | 与 `PersistenceAgentStorage` 冗余 |
| `WorkflowStorage.java` | 303 | 与 `PersistenceWorkflowStorage` 冗余 |
| `GraphStore.java` | 135 | 与 `PersistenceGraphStore` 冗余 |

同步修改 SPI 注册文件，移除 Redis Provider：

```
# META-INF/services/com.openjiuwen.core.session.checkpointer.CheckpointerProvider
com.openjiuwen.core.session.checkpointer.InMemoryCheckpointerProvider
com.openjiuwen.core.session.checkpointer.PersistenceCheckpointerProvider
# 删除: com.openjiuwen.extensions.checkpointer.redis.RedisCheckpointer$Provider
```

---

## 三、迁移指南

### 3.1 配置迁移

**改造前（需要配两份 Redis）：**

```yaml
checkpointerConfig:
  type: redis
  conf:
    connection:
      url: redis://127.0.0.1:6379
    ttl:
      default_ttl: 60
      refresh_on_read: true

kvStoreConfig:
  type: redis
  conf:
    connection:
      url: redis://127.0.0.1:6379
```

**改造后（一份配置，共享实例）：**

```yaml
kvStoreConfig:                           # 唯一入口
  type: redis
  conf:
    connection:
      url: redis://127.0.0.1:6379

checkpointerConfig:
  type: persistence                      # 改为 persistence
  conf:
    kv_store_type: redis                 # 引用 kvStoreConfig（RunnerImpl 自动注入共享实例）
    ttl:                                 # TTL 配置
      default_ttl: 60
      refresh_on_read: true
```

### 3.2 API 迁移

| 旧 API | 新 API |
|--------|--------|
| `new RedisCheckpointer(redisStore, ttlMap)` | `new PersistenceCheckpointer(redisStore, CheckpointTtlConfig.fromMap(ttlMap))` |
| `CheckpointerFactory.create("redis", conf)` | `CheckpointerFactory.create("persistence", persistenceConf)` |
| `redisCheckpointer.getRedisStore()` | 直接使用注入的 `BaseKVStore` |
| `redisCheckpointer.getAgentStorage()` | 不暴露，通过 `Checkpointer` 抽象方法使用 |

### 3.3 行为兼容性

| 维度 | 改造前 | 改造后 | 影响 |
|------|--------|--------|------|
| 序列化 | `Serializer.dumpsTyped()` → 二进制 | Java Object 直存 + `"java_serialized"` 标记 | ⚠️ **不兼容**——已有 Redis 中的二进制数据无法直接读取 |
| Key 格式 | `{tid}:{sid}:agent:{agentId}:agent_state_blobs` | **完全相同** | ✅ |
| TTL | `pipeline.set(key, type, ttl)` + `pipeline.set(key, data, ttl)` | `pipeline.set(key, "java_serialized", ttl)` + `pipeline.set(key, state, ttl)` | ✅ 功能等价 |
| `CompletableFuture` 返回值 | 假异步 | 同步 | ✅ 调用方已经 `.join()` |

### 3.4 数据迁移

如果已有 `RedisCheckpointer` 写入的二进制数据需要迁移，提供迁移工具：

```java
public class CheckpointDataMigrator {
    public static void migrateBinaryToJavaSerialized(BaseKVStore kvStore, String sessionId) {
        // 1. 按 sessionId 前缀扫描所有 key
        // 2. 读取 dump_type key，如果值为 "java" 以外的类型（如 "pickle"），跳过
        // 3. 读取 blob key，如果是 byte[]，尝试 Serializer.loadsTyped() 反序列化
        // 4. 将反序列化后的 Map<String, Object> 重新以 java_serialized 方式写入
    }
}
```

---

## 四、影响分析

### 4.1 受影响的代码

| 模块 | 影响类型 | 说明 |
|------|---------|------|
| `core/session/checkpointer/PersistenceCheckpointer.java` | 修改 | 增加 TTL 支持 |
| `core/session/checkpointer/PersistenceCheckpointerProvider.java` | 修改 | 支持 KVStoreFactory + TTL |
| `core/session/checkpointer/Storage.java` | 修改 | 内部类增加 TTL 字段 |
| `spi/store/KVStorePipeline.java` | 修改 | `set()` 增加 expiry 重载 |
| `spi/store/BaseKVStore.java` | 无修改 | 接口不变 |
| `extensions/store/kv/RedisStore.java` | 修改 | pipeline 执行器识别 expiry |
| `core/foundation/store/kv/InMemoryKVStore.java` | 修改 | pipeline 执行器识别 expiry（忽略或用 ScheduledExecutor 模拟） |
| `core/runner/RunnerImpl.java` | 修改 | 共享 BaseKVStore 实例 |
| `extensions/checkpointer/redis/` | **删除** | 整个目录 |
| 测试文件 | 修改 | `RedisCheckpointer*Test` 迁移为 `PersistenceCheckpointerWithRedisTest` |

### 4.2 风险与缓解

| 风险 | 概率 | 缓解措施 |
|------|------|---------|
| Python 侧仍在使用 `RedisCheckpointer` | 中 | 确认 Python 侧是否也计划合并，如未合并则保留兼容层 |
| 已有 Redis 中的二进制数据不兼容 | 低 | 提供迁移工具；新部署无此问题 |
| `Serializer.dumpsTyped()` 的序列化效率更高 | 低 | 大部分 checkpoint 数据是 `Map<String, Object>`，Java 序列化性能足够；如果确有需要，可在 `CheckpointerOptions` 中增加序列化策略选择 |

---

## 五、实施步骤

### Step 1：补齐 `KVStorePipeline.set(key, value, expiry)` 和各实现

- 修改 `KVStorePipeline` 增加 `set(key, value, expiry)` 重载
- 修改 `RedisStore.pipeline()` 执行器识别 expiry
- 修改 `InMemoryKVStore.pipeline()` 执行器识别 expiry（InMemory 可忽略或模拟）
- 修改 `DbBasedKVStore.pipeline()` 执行器识别 expiry（忽略或记录日志）
- **测试**：`KVStorePipelineTtlTest`

### Step 2：新增 `CheckpointTtlConfig` + 修改 `PersistenceCheckpointer`

- 新建 `CheckpointTtlConfig`
- 修改 `PersistenceCheckpointer` 构造函数，接受 `CheckpointTtlConfig`
- 修改 `PersistenceAgentStorage`、`PersistenceWorkflowStorage`、`PersistenceGraphStore`，在 save 时传 TTL、在 recover 时 refresh TTL
- **测试**：`PersistenceCheckpointerTtlTest`

### Step 3：修改 `PersistenceCheckpointerProvider` + `RunnerImpl`

- `PersistenceCheckpointerProvider` 支持 `kv_store_type` + `kv_store_conf` + `ttl` 配置
- `RunnerImpl.start()` 中先创建共享 `BaseKVStore`，注入给 Checkpointer
- **测试**：`PersistenceCheckpointerProviderTest`、`RunnerImplSharedKvStoreTest`

### Step 4：迁移测试 + 删除 `extensions/checkpointer/redis/`

- 将 `RedisCheckpointerStorageTest`、`RedisCheckpointerProviderTest`、`RedisCheckpointerCompatibilityTest` 的测试用例迁移为 `PersistenceCheckpointerWithRedisStoreTest`
- 删除 `extensions/checkpointer/redis/` 目录
- 删除 SPI 注册文件中的 RedisCheckpointer$Provider
- **测试**：全量回归

### Step 5：数据迁移工具（可选）

- 如有已有 Redis 数据，提供 `CheckpointDataMigrator`

---

## 六、改造后的架构

```
Checkpointer (abstract)
├── InMemoryCheckpointer                        # 内存，无 TTL
└── PersistenceCheckpointer(BaseKVStore, TTL)   # 统一持久化，支持任意 BaseKVStore 实现
    ├── BaseKVStore = InMemoryKVStore           # 内存
    ├── BaseKVStore = RedisStore                # Redis（含 TTL）
    └── BaseKVStore = DbBasedKVStore            # 数据库

CheckpointerProvider (SPI)
├── InMemoryCheckpointerProvider   type="in_memory"
└── PersistenceCheckpointerProvider type="persistence"

KVStoreProvider (SPI)
├── InMemoryKVStoreProvider   type="in_memory"
└── RedisKVStoreProvider      type="redis"

配置统一：
  kvStoreConfig → KVStoreFactory.create() → BaseKVStore (共享实例)
      ├── PersistenceCheckpointer(sharedKvStore, ttlConfig)
      └── KvTodoStorage(sharedKvStore)
```

---

## 附录 A：冗余代码详细对比

### A.1 编排逻辑对比

```java
// PersistenceCheckpointer.preAgentExecute()
@Override
public void preAgentExecute(BaseSession session, Object inputs) {
    String sessionId = session.sessionId();
    Loggers.SESSION.info("Agent checkpoint restore initiated, sessionId={}", sessionId);
    agentStorage.recover(session);
    if (inputs != null) {
        session.state().update(Map.of(Constant.INTERACTIVE_INPUT, List.of(inputs)));
    }
}

// RedisCheckpointer.preAgentExecute() — 逐行相同（除日志）
@Override
public void preAgentExecute(BaseSession session, Object inputs) {
    agentStorage.recover(session, inputs).join();  // 假异步，.join() 后等价于同步
    if (inputs != null) {
        session.state().update(Map.of(Constant.INTERACTIVE_INPUT, List.of(inputs)));
    }
}
```

其余 `interruptAgentExecute`、`postAgentExecute`、`preWorkflowExecute`、`postWorkflowExecute` 同理。

### A.2 存储操作对比

```java
// PersistenceAgentStorage.save() — Key 构建完全相同
String dumpTypeKey = TenantKVStoreKeyResolver.resolveKey(
    buildKeyWithNamespace(sessionId, SESSION_NAMESPACE_AGENT, agentId, STATE_BLOBS_DUMP_TYPE));
String blobKey = TenantKVStoreKeyResolver.resolveKey(
    buildKeyWithNamespace(sessionId, SESSION_NAMESPACE_AGENT, agentId, STATE_BLOBS));

// Redis AgentStorage.save() — Key 构建完全相同
String dumpTypeKey = TenantKVStoreKeyResolver.resolveKey(
    Checkpointer.buildKeyWithNamespace(sessionId, Checkpointer.SESSION_NAMESPACE_AGENT,
        agentId, STATE_BLOBS_DUMP_TYPE));
String blobKey = TenantKVStoreKeyResolver.resolveKey(
    Checkpointer.buildKeyWithNamespace(sessionId, Checkpointer.SESSION_NAMESPACE_AGENT,
        agentId, STATE_BLOBS));
```

唯一的差异是序列化方式：

```java
// Persistence: Java Object 直存
pipeline.set(dumpTypeKey, "java_serialized");
pipeline.set(blobKey, state);                            // state 是 Map<String, Object>

// Redis: 二进制序列化
var stateBlob = serializeState(state);                   // Serializer.dumpsTyped() → TypedBytes
pipeline.set(dumpTypeKey, stateBlob.type(), ttlSeconds); // "java" + byte[]
pipeline.set(blobKey, stateBlob.data(), ttlSeconds);     // byte[]
```

### A.3 `processInteractiveInputs` 对比

`PersistenceWorkflowStorage.processInteractiveInputs()` 与 `WorkflowStorage.processInteractiveInputs()` **完全相同**，是逐字复制。

### A.4 `RedisStore extends BaseKVStore`

```java
// RedisStore 继承关系
public class RedisStore extends BaseKVStore {
    // 实现了所有 BaseKVStore 抽象方法：set, get, delete, isExists, getByPrefix, deleteByPrefix, mget, batchDelete, pipeline
    // 额外方法：refreshTtl(), isCluster()
}
```

`PersistenceCheckpointer(BaseKVStore kvStore)` 传入 `RedisStore` 实例完全合法。
