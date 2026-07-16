# TodoTool Support Redis — 设计规格文档

> 日期：2026-07-15 | Issue: #34 | 方案：A（共享 KV 实例 + TodoStorage 接口抽象）

---

## 1. 需求背景

### 1.1 现有问题

| 问题 | 说明 |
|------|------|
| 多实例部署受限 | 多个 agent 实例无法共享同一份 Todo 数据，需依赖共享文件系统 |
| 无法利用框架已有的 Redis 能力 | 框架已提供 BaseKVStore + RedisStore，但 TodoTool 未使用 |
| 缺少存储抽象层 | 没有 TodoStorage 接口，无法扩展其他存储实现 |
| 多租户隔离缺失 | TodoTool 使用文件路径存储，多租户场景下依赖 TenantWorkspaceResolver 间接隔离，但不如 KV key 前缀隔离更可靠 |

### 1.2 当前实现

```java
// harness/tools/TodoTool.java
public List<TodoItem> load(String sessionId) throws IOException {
    Path file = filePath(sessionId); // workspace.resolve(sessionId).resolve("todo.json")
    String json = Files.readString(file);
    ...
}

public void save(String sessionId, List<TodoItem> todos) throws IOException {
    Path file = filePath(sessionId);
    Files.createDirectories(file.getParent());
    Files.writeString(file, JsonUtils.safeJsonDumps(todos, "[]"));
}
```

存储路径：`{workspace}/{sessionId}/todo.json`

### 1.3 期望目标

基于框架已有的 Redis 基础设施（BaseKVStore + RedisStore + KVStoreFactory），让 TodoTool 也支持 KV 存储方式，同时引入存储抽象层便于后续扩展。

---

## 2. 设计决策

| 决策项 | 选择 | 理由 |
|--------|------|------|
| 存储选择策略 | 配置驱动 | DeepAgentConfig.todoStorageType 控制是否使用 KV，默认 "file" 保持向后兼容 |
| 配置统一方式 | 共享 KV 实例 + 各组件 storageType | 复用 RunnerConfig.kvStoreConfig 创建的 KV 实例，各组件仅需指定 storageType |
| 存储抽象 | TodoStorage 接口 | 满足需求"缺少存储抽象层"，遵循开闭原则 |
| 多租户隔离 | 支持 | KvTodoStorage 使用 TenantKVStoreKeyResolver.resolveKey() 实现 key 前缀隔离 |

---

## 3. 架构设计

### 3.1 整体架构

```
RunnerConfig.kvStoreConfig (type: "redis", conf: {host:...})
    ↓
RunnerImpl → KVStoreFactory.create(type, conf) → BaseKVStore 实例
    ↓ 注入到 DeepAgent.kvStore 字段
DeepAgent (持有 kvStore)
    ↓ TaskPlanningRail.init() 从 deepAgent 获取 kvStore + todoStorageType
TaskPlanningRail → 根据 todoStorageType 创建 TodoStorage
    ↓ "file" → FileTodoStorage(workspace)
    ↓ "kv"  → KvTodoStorage(kvStore)
    ↓ "kv" + kvStore=null → FileTodoStorage(workspace) + WARNING 日志 (降级)
TodoTool (持有 TodoStorage)
```

### 3.2 配置示例

```json
// RunnerConfig（全局 KV 实例配置）
{
  "kvStoreConfig": {
    "type": "redis",
    "conf": {"host": "localhost", "port": 6379}
  }
}

// DeepAgentConfig（组件级存储选择）
{
  "todoStorageType": "kv",
  "isTaskPlanningEnabled": true
}
```

默认配置（向后兼容）：
```json
{
  "todoStorageType": "file"
}
```

---

## 4. TodoStorage 接口设计

### 4.1 接口定义

```java
package com.openjiuwen.harness.tools;

import java.io.IOException;
import java.util.List;

public interface TodoStorage {
    List<TodoItem> load(String sessionId) throws IOException;
    void save(String sessionId, List<TodoItem> todos) throws IOException;
    void delete(String sessionId) throws IOException;
}
```

设计要点：
- 3个核心方法：load/save/delete，覆盖 TodoTool 当前所有的持久化操作需求
- sessionId 作为参数，与当前 TodoTool 的方法签名一致
- throws IOException，文件存储和 KV 存储都有可能抛出 IO 相关异常
- delete 方法用于 session 结束时清理 todo 数据，以及多实例场景下清理过期数据

### 4.2 FileTodoStorage 实现

从 TodoTool 中提取现有的 filePath()、load()、save() 逻辑：

```java
package com.openjiuwen.harness.tools;

import com.openjiuwen.core.common.security.JsonUtils;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

public class FileTodoStorage implements TodoStorage {
    private final Path workspace;

    public FileTodoStorage(Path workspace) {
        this.workspace = workspace.toAbsolutePath().normalize();
    }

    @Override
    public List<TodoItem> load(String sessionId) throws IOException {
        Path file = workspace.resolve(sessionId).resolve("todo.json");
        if (!Files.exists(file)) { return new ArrayList<>(); }
        String json = Files.readString(file);
        if (json.isBlank()) { return new ArrayList<>(); }
        TodoItem[] items = JsonUtils.safeJsonLoads(json, TodoItem[].class, new TodoItem[0]);
        return new ArrayList<>(List.of(items));
    }

    @Override
    public void save(String sessionId, List<TodoItem> todos) throws IOException {
        Path file = workspace.resolve(sessionId).resolve("todo.json");
        Files.createDirectories(file.getParent());
        Files.writeString(file, JsonUtils.safeJsonDumps(todos, "[]"));
    }

    @Override
    public void delete(String sessionId) throws IOException {
        Path dir = workspace.resolve(sessionId);
        if (Files.exists(dir)) {
            Files.walk(dir).sorted(Comparator.reverseOrder())
                .forEach(p -> { try { Files.delete(p); } catch (IOException ignored) {} });
        }
    }
}
```

### 4.3 KvTodoStorage 实现

基于 BaseKVStore + TenantKVStoreKeyResolver，参考 PersistenceCheckpointer 的模式：

```java
package com.openjiuwen.harness.tools;

import com.openjiuwen.core.common.security.JsonUtils;
import com.openjiuwen.core.multitenant.TenantKVStoreKeyResolver;
import com.openjiuwen.spi.store.BaseKVStore;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;

public class KvTodoStorage implements TodoStorage {
    private final BaseKVStore kvStore;

    public KvTodoStorage(BaseKVStore kvStore) {
        this.kvStore = Objects.requireNonNull(kvStore);
    }

    private String buildKey(String sessionId) {
        String rawKey = sessionId + ":todo";
        return TenantKVStoreKeyResolver.resolveKey(rawKey);
    }

    @Override
    public List<TodoItem> load(String sessionId) throws IOException {
        String key = buildKey(sessionId);
        Object value = kvStore.get(key);
        if (value == null) { return new ArrayList<>(); }
        String json = String.valueOf(value);
        if (json.isBlank()) { return new ArrayList<>(); }
        TodoItem[] items = JsonUtils.safeJsonLoads(json, TodoItem[].class, new TodoItem[0]);
        return new ArrayList<>(List.of(items));
    }

    @Override
    public void save(String sessionId, List<TodoItem> todos) throws IOException {
        String key = buildKey(sessionId);
        kvStore.set(key, JsonUtils.safeJsonDumps(todos, "[]"));
    }

    @Override
    public void delete(String sessionId) throws IOException {
        String key = buildKey(sessionId);
        kvStore.delete(key);
    }
}
```

---

## 5. TodoTool 重构

### 5.1 核心变更

将 TodoTool 持有的 `Path workspace` 字段改为 `TodoStorage storage` 字段：

```java
public class TodoTool {
    private final TodoStorage storage;

    // 保留兼容旧方式的构造器
    public TodoTool(String workspace) {
        this.storage = new FileTodoStorage(Path.of(workspace != null ? workspace : "."));
    }

    // 新增基于 TodoStorage 的构造器
    public TodoTool(TodoStorage storage) {
        this.storage = Objects.requireNonNull(storage);
    }

    // load/save 方法委托给 storage（删除原有 filePath/load/save 的文件逻辑）
    public List<TodoItem> load(String sessionId) throws IOException {
        return storage.load(sessionId);
    }

    public void save(String sessionId, List<TodoItem> todos) throws IOException {
        storage.save(sessionId, todos);
    }
}
```

**向后兼容**：
- `TodoTool(String workspace)` 构造器保留，内部创建 FileTodoStorage，现有代码无需修改
- `TodoTool(TodoStorage storage)` 新构造器用于配置驱动场景
- 所有业务方法（create/list/get/modify 等）签名不变，仅内部 load/save 委托给 storage

### 5.2 删除的私有方法

- `filePath(String sessionId)` — 移入 FileTodoStorage
- `load(String sessionId)` 的文件逻辑 — 移入 FileTodoStorage
- `save(String sessionId, List<TodoItem> todos)` 的文件逻辑 — 移入 FileTodoStorage

---

## 6. 配置注入链

### 6.1 DeepAgentConfig 新增字段

```java
public class DeepAgentConfig {
    @Builder.Default
    private String todoStorageType = "file"; // 默认 "file"，可选 "kv"
}
```

**todoStorageType 语义说明**：
- `"file"` — 使用 FileTodoStorage（文件系统存储），默认值，向后兼容
- `"kv"` — 使用 KvTodoStorage，KV 实例的具体类型（in_memory / redis）由 RunnerConfig.kvStoreConfig.type 决定
  - kvStoreConfig.type = "in_memory" → 使用 InMemoryKVStore（适用于单进程测试场景）
  - kvStoreConfig.type = "redis" → 使用 RedisStore（适用于多实例生产部署）
  - kvStoreConfig 为 null 或 kvStore 为 null → 自动降级为 FileTodoStorage

### 6.2 DeepAgent 新增 kvStore 字段

```java
public class DeepAgent {
    private BaseKVStore kvStore; // 由 RunnerImpl 注入

    public BaseKVStore getKvStore() { return kvStore; }
    public void setKvStore(BaseKVStore kvStore) { this.kvStore = kvStore; }
}
```

### 6.3 RunnerImpl 注入 kvStore

在 RunnerImpl 创建 DeepAgent 后，将 kvStoreConfig 创建的 KV 实例注入。此 KV 实例为单例，与 Checkpointer 共享同一实例：

```java
BaseKVStore kvStore = null;
if (config.getKvStoreConfig() != null && config.getKvStoreConfig().get("type") != null) {
    String type = (String) config.getKvStoreConfig().get("type");
    Map<String, Object> conf = (Map<String, Object>) config.getKvStoreConfig().getOrDefault("conf", Map.of());
    kvStore = KVStoreFactory.create(type, conf);
}
deepAgent.setKvStore(kvStore);
```

**注入说明**：
- kvStore 实例由 RunnerImpl 在 DeepAgent 构建完成后设置（通过 setKvStore）
- 同一个 kvStore 实例可用于 Checkpointer（通过 PersistenceCheckpointer 构造器传入）和 TodoTool（通过 DeepAgent.getKvStore() 传入）
- kvStore 为 null 时表示未配置 kvStoreConfig，各组件应各自降级处理

### 6.4 TaskPlanningRail 根据 todoStorageType 创建 TodoStorage

```java
// TaskPlanningRail.init() 中
String todoStorageType = deepAgent.getConfig().getTodoStorageType();
TodoStorage todoStorage;
if ("kv".equals(todoStorageType) && deepAgent.getKvStore() != null) {
    todoStorage = new KvTodoStorage(deepAgent.getKvStore());
} else {
    if ("kv".equals(todoStorageType) && deepAgent.getKvStore() == null) {
        Loggers.HARNESS.warning("todoStorageType is 'kv' but kvStore is null, falling back to file storage");
    }
    todoStorage = new FileTodoStorage(deepAgent.getWorkspace().root().resolve(".todo"));
}
todoTool = new TodoTool(todoStorage);
```

**降级策略**：
- todoStorageType 为 "kv" 但 kvStore 为 null 时，降级为 FileTodoStorage + WARNING 日志
- 不抛出异常，确保 agent 仍可正常运行

---

## 7. 多租户隔离

### 7.1 Key 设计

| 场景 | 原始 key | 租户前缀处理 | 最终 key |
|------|----------|--------------|----------|
| 无租户 | `session-1:todo` | TenantKVStoreKeyResolver 透传 | `session-1:todo` |
| 有租户(tenant_a) | `session-1:todo` | TenantNamespaceFactories.KV_STORE_DEFAULT 添加前缀 | `tenant_a:session-1:todo` |

行为一致性：
- 不传 tenantId 时，TenantKVStoreKeyResolver.resolveKey() 透传原始 key，行为与现有一致
- 有 tenantId 时，自动添加租户前缀，不同租户的 todo 数据在 KV 中互不可见
- 与 PersistenceCheckpointer 使用相同的 TenantNamespaceFactories.KV_STORE_DEFAULT（`:` 分隔符）

### 7.2 与 PersistenceCheckpointer 的模式对比

| 维度 | PersistenceCheckpointer | KvTodoStorage |
|------|------------------------|---------------|
| key 构建方式 | buildKeyWithNamespace + resolveKey | sessionId + ":todo" + resolveKey |
| 租户前缀 | TenantKVStoreKeyResolver.resolveKey | 同 |
| 批量操作 | KVStorePipeline | 单条 set/get/delete |
| 命名空间工厂 | TenantNamespaceFactories.KV_STORE_DEFAULT | 同 |

---

## 8. RedisStoreProvider

### 8.1 当前问题

RedisStore 只有直接构造方式（`new RedisStore(redisClient)`），没有 SPI Provider 注册。KVStoreFactory 中仅注册了 InMemoryKVStoreProvider。

### 8.2 新增 RedisKVStoreProvider

```java
package com.openjiuwen.extensions.store.kv;

public class RedisKVStoreProvider implements KVStoreProvider {
    @Override
    public String typeName() {
        return "redis";
    }

    @Override
    public BaseKVStore create(Map<String, Object> conf) {
        Object redisClient = createRedisClient(conf);
        return new RedisStore(redisClient);
    }

    private Object createRedisClient(Map<String, Object> conf) {
        // 实现逻辑取决于项目中实际包含的 Redis 客户端库：
        // - 如果包含 Jedis 依赖：根据 conf 创建 Jedis/JedisPool/JedisCluster
        // - 如果包含 Lettuce 依赖：根据 conf 创建 RedisClient/StatefulRedisConnection
        // - 如果包含 Redisson 依赖：根据 conf 创建 RedissonClient
        // RedisStore 通过反射适配所有这些客户端，因此 Provider 只需创建正确的客户端实例即可
        String host = (String) conf.getOrDefault("host", "localhost");
        int port = ((Number) conf.getOrDefault("port", 6379)).intValue();
        String password = (String) conf.get("password");
        boolean cluster = Boolean.parseBoolean(String.valueOf(conf.getOrDefault("cluster", "false")));
        // 根据以上参数和可用的客户端库创建 Redis 客户端实例
    }
}
```

**实现策略**：
- RedisKVStoreProvider 的 `createRedisClient()` 实现需要根据项目实际包含的 Redis 客户端库来决定
- 由于 agent-core-java 当前不包含 Jedis/Lettuce 的硬依赖（RedisStore 通过反射适配），Provider 的具体客户端创建逻辑应作为部署适配器的一部分
- 在核心框架中，Provider 可以提供一个基础实现（尝试反射加载常见客户端），服务适配器可以通过 KVStoreFactory.register("redis", customProvider) 覆盖

### 8.3 SPI 注册

在 `META-INF/services/com.openjiuwen.spi.store.KVStoreProvider` 中追加：
```
com.openjiuwen.extensions.store.kv.RedisKVStoreProvider
```

---

## 9. 测试设计

### 9.1 单元测试（UT）

| 测试类 | 测试数 | 覆盖范围 |
|--------|--------|----------|
| TodoStorageTest | ~10 | TodoStorage 接口基础（load空/save/load回/delete） |
| FileTodoStorageTest | ~8 | 文件存储（目录创建/JSON读写/空文件处理/删除） |
| KvTodoStorageTest | ~12 | KV存储（set/get/delete/租户key/空值/null处理） |
| TodoToolStorageRefTest | ~10 | TodoTool重构（两种构造器/业务方法委托storage） |
| TenantTodoIsolationTest | ~6 | 多租户隔离（不同租户互不可见/无租户向后兼容） |
| TodoToolBackwardCompatTest | ~4 | 向后兼容（TodoTool(String)构造器/file默认行为） |
| TaskPlanningRailStorageTest | ~6 | Rail创建storage（file/kv/null降级） |

测试要点：
- KvTodoStorage 测试使用 InMemoryKVStore（不需要真实 Redis）
- 多租户隔离测试通过 TenantContextHolder.setTenant() 设置租户上下文
- 向后兼容测试验证 TodoTool(String) 旧构造器行为不变

### 9.2 系统测试（ST）

| 场景 | 说明 |
|------|------|
| 多实例共享 todo | 两个 DeepAgent 实例使用同一个 Redis，验证 todo 数据共享 |
| 租户隔离 E2E | tenant_a 和 tenant_b 各创建 todo，验证互不可见 |
| 降级 E2E | kvStoreConfig 缺失时，验证自动降级为文件存储 |

---

## 10. 新增/修改文件清单

| 操作 | 文件 | 包路径 | 说明 |
|------|------|--------|------|
| 新增 | TodoStorage.java | com.openjiuwen.harness.tools | 存储抽象接口 |
| 新增 | FileTodoStorage.java | com.openjiuwen.harness.tools | 文件存储实现 |
| 新增 | KvTodoStorage.java | com.openjiuwen.harness.tools | KV存储实现 |
| 新增 | RedisKVStoreProvider.java | com.openjiuwen.extensions.store.kv | Redis SPI Provider |
| 修改 | TodoTool.java | com.openjiuwen.harness.tools | 持有 TodoStorage 替代 Path |
| 修改 | DeepAgentConfig.java | com.openjiuwen.harness.schema.config | 新增 todoStorageType 字段 |
| 修改 | DeepAgent.java | com.openjiuwen.harness.deep_agent | 新增 kvStore 字段 + getter/setter |
| 修改 | TaskPlanningRail.java | com.openjiuwen.harness.rails | 根据 todoStorageType 创建 TodoStorage |
| 修改 | RunnerImpl.java | com.openjiuwen.core.runner | 注入 kvStore 到 DeepAgent |
| 修改 | META-INF/services/...KVStoreProvider | resources | 注册 RedisKVStoreProvider |

---

## 11. 风险与缓解

| 风险 | 缓解措施 |
|------|----------|
| TodoTool(String) 旧构造器行为变化 | FileTodoStorage 完全提取现有逻辑，确保行为一致 |
| kvStore 为 null 时 TodoTool 无法工作 | TaskPlanningRail 降级为 FileTodoStorage + WARNING 日志 |
| KV 中的 JSON 序列化与文件格式不一致 | 使用相同的 JsonUtils.safeJsonDumps/safeJsonLoads |
| 多租户 key 前缀格式与其他组件不兼容 | 使用 TenantKVStoreKeyResolver（全局 NamespaceFactory），格式统一 |
| RedisStore 无 SPI Provider 无法通过 KVStoreFactory 创建 | 新增 RedisKVStoreProvider + META-INF/services 注册 |
| RunnerImpl 注入 kvStore 的时机问题 | DeepAgent 构建完成后注入，TaskPlanningRail.init() 在 ensureInitialized() 中调用 |

---

## 12. 不涉及的内容

- 不涉及对外 API 变化
- 不涉及 EDPAgent 特殊逻辑（TodoTool 通用化后 EDPAgent 可直接复用）
- 不涉及其他组件的 Redis 改造（TaskPlan/FileStore 等可后续独立 issue 处理）
- 不涉及 Python 侧代码

---

## 13. 与多租户数据隔离功能的关联

本需求与 Issue #29（多租户数据隔离）有强关联：

| 关联维度 | 说明 |
|----------|------|
| TenantKVStoreKeyResolver | KvTodoStorage 使用与 PersistenceCheckpointer 相同的租户 key 解析器 |
| TenantContextHolder | KvTodoStorage 的 key 构建自动从 ThreadLocal 获取租户上下文 |
| TenantNamespaceFactory | 使用 KV_STORE_DEFAULT 命名空间工厂，确保 key 格式统一 |
| 向后兼容原则 | todoStorageType 默认 "file"，不传 tenantId 时行为与现有一致 |

多租户隔离文档中"待办事项"部分列出：
- PersistenceCheckpointer tenantId 前缀改造 — 高优先级（Phase 1 未完成）
- RedisCheckpointer tenantId 前缀改造 — 高优先级（Phase 1 未完成）

本需求的 KvTodoStorage 与这两个待办事项属于同一类改造（组件级 KV + tenantId 前缀），可以作为多租户改造的补充项。
