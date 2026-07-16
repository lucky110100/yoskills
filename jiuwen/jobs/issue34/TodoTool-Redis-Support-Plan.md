# TodoTool Redis Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 TodoTool 支持 Redis/KV 存储，引入 TodoStorage 抽象层，支持多租户隔离

**Architecture:** 方案 A — 共享 KV 实例 + TodoStorage 接口抽象。新增 TodoStorage 接口（load/save/delete），FileTodoStorage 提取现有文件逻辑，KvTodoStorage 基于 BaseKVStore + TenantKVStoreKeyResolver 实现租户隔离的 KV 操作。TodoTool 持有 TodoStorage 引用替代 Path。DeepAgentConfig.todoStorageType 配置驱动选择存储后端，kvStore 实例来自 RunnerConfig.kvStoreConfig 由 RunnerImpl 注入到 DeepAgent。

**Tech Stack:** Java 17+, Maven, JUnit 5, Lombok, BaseKVStore SPI (InMemoryKVStore/RedisStore)

## Global Constraints

- 不改变 TodoTool 的对外 API 签名（create/list/get/modify 方法保持不变）
- todoStorageType 默认 "file"，向后兼容，零迁移风险
- TodoTool(String workspace) 旧构造器保留，内部创建 FileTodoStorage
- KvTodoStorage 使用 TenantKVStoreKeyResolver.resolveKey() 实现租户 key 前缀隔离
- kvStore 为 null 时自动降级为 FileTodoStorage + WARNING 日志
- 代码风格遵循项目现有约定（Lombok @Data/@Builder，无多余注释）
- 测试使用 InMemoryKVStore（不需要真实 Redis 连接）
- 源码根目录：`d:\jiuwen\main\agent-core-java`

---

## File Structure

| 操作 | 文件路径 | 说明 |
|------|----------|------|
| 新增 | `src/main/java/com/openjiuwen/harness/tools/TodoStorage.java` | 存储抽象接口（3个方法） |
| 新增 | `src/main/java/com/openjiuwen/harness/tools/FileTodoStorage.java` | 文件存储实现（提取 TodoTool 现有逻辑） |
| 新增 | `src/main/java/com/openjiuwen/harness/tools/KvTodoStorage.java` | KV存储实现（BaseKVStore+租户隔离） |
| 新增 | `src/main/java/com/openjiuwen/extensions/store/kv/RedisKVStoreProvider.java` | Redis SPI Provider |
| 修改 | `src/main/java/com/openjiuwen/harness/tools/TodoTool.java` | 持有 TodoStorage 替代 Path |
| 修改 | `src/main/java/com/openjiuwen/harness/schema/config/DeepAgentConfig.java` | 新增 todoStorageType 字段 |
| 修改 | `src/main/java/com/openjiuwen/harness/deep_agent/DeepAgent.java` | 新增 kvStore 字段 + getter/setter |
| 修改 | `src/main/java/com/openjiuwen/harness/rails/TaskPlanningRail.java` | 根据 todoStorageType 创建 TodoStorage |
| 修改 | `src/main/java/com/openjiuwen/core/runner/RunnerImpl.java` | 注入 kvStore 到 DeepAgent |
| 修改 | `src/main/resources/META-INF/services/com.openjiuwen.spi.store.KVStoreProvider` | 注册 RedisKVStoreProvider |
| 新增 | `src/test/java/com/openjiuwen/harness/tools/TodoStorageTest.java` | TodoStorage 接口基础测试 |
| 新增 | `src/test/java/com/openjiuwen/harness/tools/FileTodoStorageTest.java` | 文件存储测试 |
| 新增 | `src/test/java/com/openjiuwen/harness/tools/KvTodoStorageTest.java` | KV存储测试 |
| 新增 | `src/test/java/com/openjiuwen/harness/tools/TodoToolStorageRefTest.java` | TodoTool重构测试 |
| 新增 | `src/test/java/com/openjiuwen/harness/tools/TodoToolBackwardCompatTest.java` | 向后兼容测试 |
| 新增 | `src/test/java/com/openjiuwen/harness/tools/TenantTodoIsolationTest.java` | 多租户隔离测试 |

---

### Task 1: TodoStorage Interface + FileTodoStorage

**Files:**
- Create: `src/main/java/com/openjiuwen/harness/tools/TodoStorage.java`
- Create: `src/main/java/com/openjiuwen/harness/tools/FileTodoStorage.java`
- Create: `src/test/java/com/openjiuwen/harness/tools/FileTodoStorageTest.java`

**Interfaces:**
- Consumes: TodoItem（已有类），JsonUtils（已有工具），Path/Files（JDK）
- Produces: TodoStorage 接口（load/save/delete），FileTodoStorage 实现类

- [ ] **Step 1: Write TodoStorage interface**

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

- [ ] **Step 2: Write FileTodoStorageTest — failing tests for load/save/delete**

```java
package com.openjiuwen.harness.tools;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

class FileTodoStorageTest {
    @TempDir
    Path tempDir;

    private FileTodoStorage storage;

    @BeforeEach
    void setUp() {
        storage = new FileTodoStorage(tempDir);
    }

    @Test
    void load_emptyDir_returnsEmptyList() throws IOException {
        List<TodoItem> result = storage.load("session-1");
        assertTrue(result.isEmpty());
    }

    @Test
    void save_thenLoad_returnsSavedItems() throws IOException {
        List<TodoItem> todos = List.of(
            TodoItem.create("task-1", "Executing task-1", "desc", TodoStatus.IN_PROGRESS, null)
        );
        storage.save("session-1", todos);
        List<TodoItem> loaded = storage.load("session-1");
        assertEquals(1, loaded.size());
        assertEquals("task-1", loaded.get(0).getContent());
    }

    @Test
    void save_createsDirectory() throws IOException {
        Path expectedDir = tempDir.resolve("session-1");
        assertFalse(Files.exists(expectedDir));
        storage.save("session-1", new ArrayList<>());
        assertTrue(Files.exists(expectedDir));
    }

    @Test
    void delete_removesDirectory() throws IOException {
        storage.save("session-1", new ArrayList<>());
        Path dir = tempDir.resolve("session-1");
        assertTrue(Files.exists(dir));
        storage.delete("session-1");
        assertFalse(Files.exists(dir));
    }

    @Test
    void load_nonexistentSession_returnsEmptyList() throws IOException {
        List<TodoItem> result = storage.load("nonexistent");
        assertTrue(result.isEmpty());
    }

    @Test
    void save_overwritesPrevious() throws IOException {
        storage.save("session-1", List.of(
            TodoItem.create("first", "Executing first", "", TodoStatus.TODO, null)
        ));
        storage.save("session-1", List.of(
            TodoItem.create("second", "Executing second", "", TodoStatus.TODO, null)
        ));
        List<TodoItem> loaded = storage.load("session-1");
        assertEquals(1, loaded.size());
        assertEquals("second", loaded.get(0).getContent());
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `mvn test -pl . -Dtest=FileTodoStorageTest -DfailIfNoTests=false`
Expected: FAIL — FileTodoStorage class not found

- [ ] **Step 4: Write FileTodoStorage implementation**

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

- [ ] **Step 5: Run tests to verify they pass**

Run: `mvn test -pl . -Dtest=FileTodoStorageTest -DfailIfNoTests=false`
Expected: ALL PASS

- [ ] **Step 6: Commit**

```bash
git add src/main/java/com/openjiuwen/harness/tools/TodoStorage.java src/main/java/com/openjiuwen/harness/tools/FileTodoStorage.java src/test/java/com/openjiuwen/harness/tools/FileTodoStorageTest.java
git commit -m "feat(issue34): add TodoStorage interface and FileTodoStorage implementation"
```

---

### Task 2: KvTodoStorage

**Files:**
- Create: `src/main/java/com/openjiuwen/harness/tools/KvTodoStorage.java`
- Create: `src/test/java/com/openjiuwen/harness/tools/KvTodoStorageTest.java`

**Interfaces:**
- Consumes: TodoStorage 接口（Task 1），BaseKVStore（已有 SPI），TenantKVStoreKeyResolver（已有多租户模块），JsonUtils（已有工具）
- Produces: KvTodoStorage 实现类

- [ ] **Step 1: Write KvTodoStorageTest — failing tests**

```java
package com.openjiuwen.harness.tools;

import com.openjiuwen.core.foundation.store.kv.InMemoryKVStore;
import com.openjiuwen.core.multitenant.TenantContext;
import com.openjiuwen.core.multitenant.TenantContextHolder;
import com.openjiuwen.spi.store.BaseKVStore;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

class KvTodoStorageTest {
    private BaseKVStore kvStore;
    private KvTodoStorage storage;

    @BeforeEach
    void setUp() {
        kvStore = new InMemoryKVStore();
        storage = new KvTodoStorage(kvStore);
        TenantContextHolder.clear();
    }

    @AfterEach
    void tearDown() {
        TenantContextHolder.clear();
    }

    @Test
    void load_noData_returnsEmptyList() throws Exception {
        List<TodoItem> result = storage.load("session-1");
        assertTrue(result.isEmpty());
    }

    @Test
    void save_thenLoad_returnsSavedItems() throws Exception {
        List<TodoItem> todos = List.of(
            TodoItem.create("task-1", "Executing task-1", "desc", TodoStatus.IN_PROGRESS, null)
        );
        storage.save("session-1", todos);
        List<TodoItem> loaded = storage.load("session-1");
        assertEquals(1, loaded.size());
        assertEquals("task-1", loaded.get(0).getContent());
    }

    @Test
    void save_overwritesPrevious() throws Exception {
        storage.save("session-1", List.of(
            TodoItem.create("first", "Executing first", "", TodoStatus.TODO, null)
        ));
        storage.save("session-1", List.of(
            TodoItem.create("second", "Executing second", "", TodoStatus.TODO, null)
        ));
        List<TodoItem> loaded = storage.load("session-1");
        assertEquals(1, loaded.size());
        assertEquals("second", loaded.get(0).getContent());
    }

    @Test
    void delete_removesData() throws Exception {
        storage.save("session-1", List.of(
            TodoItem.create("task-1", "Executing task-1", "", TodoStatus.TODO, null)
        ));
        storage.delete("session-1");
        List<TodoItem> loaded = storage.load("session-1");
        assertTrue(loaded.isEmpty());
    }

    @Test
    void load_nonexistentSession_returnsEmptyList() throws Exception {
        List<TodoItem> result = storage.load("nonexistent");
        assertTrue(result.isEmpty());
    }

    @Test
    void tenantIsolation_differentTenants_cannotSeeEachOthersData() throws Exception {
        TenantContextHolder.setTenant(TenantContext.builder().tenantId("tenant_a").build());
        storage.save("session-1", List.of(
            TodoItem.create("task-a", "Executing task-a", "", TodoStatus.TODO, null)
        ));

        TenantContextHolder.setTenant(TenantContext.builder().tenantId("tenant_b").build());
        List<TodoItem> loaded = storage.load("session-1");
        assertTrue(loaded.isEmpty());
    }

    @Test
    void tenantIsolation_sameTenant_canSeeOwnData() throws Exception {
        TenantContextHolder.setTenant(TenantContext.builder().tenantId("tenant_a").build());
        storage.save("session-1", List.of(
            TodoItem.create("task-a", "Executing task-a", "", TodoStatus.TODO, null)
        ));

        List<TodoItem> loaded = storage.load("session-1");
        assertEquals(1, loaded.size());
        assertEquals("task-a", loaded.get(0).getContent());
    }

    @Test
    void noTenant_backwardCompat_keyNoPrefix() throws Exception {
        storage.save("session-1", List.of(
            TodoItem.create("task-1", "Executing task-1", "", TodoStatus.TODO, null)
        ));
        Object rawValue = kvStore.get("session-1:todo");
        assertNotNull(rawValue);
    }

    @Test
    void withTenant_keyHasPrefix() throws Exception {
        TenantContextHolder.setTenant(TenantContext.builder().tenantId("tenant_a").build());
        storage.save("session-1", List.of(
            TodoItem.create("task-1", "Executing task-1", "", TodoStatus.TODO, null)
        ));
        Object rawValue = kvStore.get("tenant_a:session-1:todo");
        assertNotNull(rawValue);
    }

    @Test
    void constructor_nullKvStore_throwsException() {
        assertThrows(NullPointerException.class, () -> new KvTodoStorage(null));
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mvn test -pl . -Dtest=KvTodoStorageTest -DfailIfNoTests=false`
Expected: FAIL — KvTodoStorage class not found

- [ ] **Step 3: Write KvTodoStorage implementation**

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

- [ ] **Step 4: Run tests to verify they pass**

Run: `mvn test -pl . -Dtest=KvTodoStorageTest -DfailIfNoTests=false`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add src/main/java/com/openjiuwen/harness/tools/KvTodoStorage.java src/test/java/com/openjiuwen/harness/tools/KvTodoStorageTest.java
git commit -m "feat(issue34): add KvTodoStorage with tenant-aware key prefix"
```

---

### Task 3: TodoTool Refactoring

**Files:**
- Modify: `src/main/java/com/openjiuwen/harness/tools/TodoTool.java`
- Create: `src/test/java/com/openjiuwen/harness/tools/TodoToolBackwardCompatTest.java`
- Create: `src/test/java/com/openjiuwen/harness/tools/TodoToolStorageRefTest.java`

**Interfaces:**
- Consumes: TodoStorage 接口（Task 1），FileTodoStorage（Task 1），KvTodoStorage（Task 2）
- Produces: 重构后的 TodoTool（持有 TodoStorage 替代 Path），两个新构造器

- [ ] **Step 1: Write TodoToolBackwardCompatTest — verify old constructor still works**

```java
package com.openjiuwen.harness.tools;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.nio.file.Path;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

class TodoToolBackwardCompatTest {
    @TempDir
    Path tempDir;

    @Test
    void oldConstructor_stringWorkspace_works() {
        TodoTool tool = new TodoTool(tempDir.toString());
        assertNotNull(tool);
    }

    @Test
    void oldConstructor_nullWorkspace_usesDefault() {
        TodoTool tool = new TodoTool(null);
        assertNotNull(tool);
    }

    @Test
    void oldConstructor_createAndLoad_worksAsBefore() throws Exception {
        TodoTool tool = new TodoTool(tempDir.toString());
        List<?> tasks = List.of(Map.of("content", "test task", "activeForm", "Executing test", "description", "desc"));
        ToolOutput result = tool.create("session-1", tasks);
        assertTrue(result.isSuccess());
        List<TodoItem> loaded = tool.load("session-1");
        assertEquals(1, loaded.size());
        assertEquals("test task", loaded.get(0).getContent());
    }

    @Test
    void oldConstructor_fileCreated() throws Exception {
        TodoTool tool = new TodoTool(tempDir.toString());
        List<?> tasks = List.of(Map.of("content", "test task", "activeForm", "Executing test", "description", "desc"));
        tool.create("session-1", tasks);
        Path file = tempDir.resolve("session-1").resolve("todo.json");
        assertTrue(Files.exists(file));
    }
}
```

- [ ] **Step 2: Write TodoToolStorageRefTest — verify new constructor**

```java
package com.openjiuwen.harness.tools;

import com.openjiuwen.core.foundation.store.kv.InMemoryKVStore;
import com.openjiuwen.spi.store.BaseKVStore;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

class TodoToolStorageRefTest {
    private BaseKVStore kvStore;

    @BeforeEach
    void setUp() {
        kvStore = new InMemoryKVStore();
    }

    @Test
    void newConstructor_todoStorage_works() {
        TodoStorage storage = new KvTodoStorage(kvStore);
        TodoTool tool = new TodoTool(storage);
        assertNotNull(tool);
    }

    @Test
    void newConstructor_createAndLoad_viaKv() throws Exception {
        TodoStorage storage = new KvTodoStorage(kvStore);
        TodoTool tool = new TodoTool(storage);
        List<?> tasks = List.of(Map.of("content", "kv task", "activeForm", "Executing kv", "description", "desc"));
        ToolOutput result = tool.create("session-kv", tasks);
        assertTrue(result.isSuccess());
        List<TodoItem> loaded = tool.load("session-kv");
        assertEquals(1, loaded.size());
        assertEquals("kv task", loaded.get(0).getContent());
    }

    @Test
    void newConstructor_list_activeOnly() throws Exception {
        TodoStorage storage = new KvTodoStorage(kvStore);
        TodoTool tool = new TodoTool(storage);
        List<?> tasks = List.of(
            Map.of("content", "task-1", "activeForm", "Executing task-1", "description", "desc"),
            Map.of("content", "task-2", "activeForm", "Executing task-2", "description", "desc")
        );
        tool.create("session-list", tasks);
        ToolOutput result = tool.list("session-list");
        assertTrue(result.isSuccess());
    }

    @Test
    void newConstructor_nullStorage_throwsException() {
        assertThrows(NullPointerException.class, () -> new TodoTool((TodoStorage) null));
    }

    @Test
    void newConstructor_fileStorage_works() {
        TodoStorage storage = new FileTodoStorage(Path.of(System.getProperty("java.io.tmpdir")));
        TodoTool tool = new TodoTool(storage);
        assertNotNull(tool);
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `mvn test -pl . -Dtest=TodoToolBackwardCompatTest,TodoToolStorageRefTest -DfailIfNoTests=false`
Expected: FAIL — TodoTool(TodoStorage) constructor not found

- [ ] **Step 4: Refactor TodoTool — replace Path workspace with TodoStorage storage**

修改 `src/main/java/com/openjiuwen/harness/tools/TodoTool.java`：

将 `private final Path workspace;` 替换为 `private final TodoStorage storage;`

添加两个构造器：
```java
public TodoTool(String workspace) {
    this.storage = new FileTodoStorage(Path.of(workspace != null ? workspace : "."));
}

public TodoTool(TodoStorage storage) {
    this.storage = Objects.requireNonNull(storage);
}
```

将 `load(String sessionId)` 方法改为委托 storage：
```java
public List<TodoItem> load(String sessionId) throws IOException {
    return storage.load(sessionId);
}
```

将 `save(String sessionId, List<TodoItem> todos)` 方法改为委托 storage：
```java
public void save(String sessionId, List<TodoItem> todos) throws IOException {
    storage.save(sessionId, todos);
}
```

删除 `filePath(String sessionId)` 私有方法（已移入 FileTodoStorage）。

删除 `import java.nio.file.Files;`、`import java.nio.file.Path;` 中不再直接使用的导入（保留 Path 用于旧构造器）。

- [ ] **Step 5: Run tests to verify they pass**

Run: `mvn test -pl . -Dtest=TodoToolBackwardCompatTest,TodoToolStorageRefTest,FileTodoStorageTest,KvTodoStorageTest -DfailIfNoTests=false`
Expected: ALL PASS

- [ ] **Step 6: Run existing tests to ensure no regressions**

Run: `mvn test -pl . -DfailIfNoTests=false`
Expected: ALL PASS — existing tests unchanged

- [ ] **Step 7: Commit**

```bash
git add src/main/java/com/openjiuwen/harness/tools/TodoTool.java src/test/java/com/openjiuwen/harness/tools/TodoToolBackwardCompatTest.java src/test/java/com/openjiuwen/harness/tools/TodoToolStorageRefTest.java
git commit -m "feat(issue34): refactor TodoTool to hold TodoStorage instead of Path"
```

---

### Task 4: DeepAgentConfig.todoStorageType + DeepAgent.kvStore

**Files:**
- Modify: `src/main/java/com/openjiuwen/harness/schema/config/DeepAgentConfig.java`
- Modify: `src/main/java/com/openjiuwen/harness/deep_agent/DeepAgent.java`

**Interfaces:**
- Consumes: BaseKVStore（已有 SPI）
- Produces: DeepAgentConfig.todoStorageType 字段，DeepAgent.kvStore 字段 + getter/setter

- [ ] **Step 1: Add todoStorageType field to DeepAgentConfig**

在 `src/main/java/com/openjiuwen/harness/schema/config/DeepAgentConfig.java` 中添加字段：

在 `enableTenantIsolation` 字段附近添加：
```java
@Builder.Default
private String todoStorageType = "file";
```

- [ ] **Step 2: Add kvStore field to DeepAgent**

在 `src/main/java/com/openjiuwen/harness/deep_agent/DeepAgent.java` 中添加：

在现有字段区域添加：
```java
private BaseKVStore kvStore;
```

在类末尾（或 getter/setter 区域）添加：
```java
public BaseKVStore getKvStore() { return kvStore; }
public void setKvStore(BaseKVStore kvStore) { this.kvStore = kvStore; }
```

添加导入：
```java
import com.openjiuwen.spi.store.BaseKVStore;
```

- [ ] **Step 3: Run compilation to verify no errors**

Run: `mvn compile -pl .`
Expected: BUILD SUCCESS

- [ ] **Step 4: Run existing tests to ensure no regressions**

Run: `mvn test -pl . -DfailIfNoTests=false`
Expected: ALL PASS — new fields with defaults don't change existing behavior

- [ ] **Step 5: Commit**

```bash
git add src/main/java/com/openjiuwen/harness/schema/config/DeepAgentConfig.java src/main/java/com/openjiuwen/harness/deep_agent/DeepAgent.java
git commit -m "feat(issue34): add todoStorageType to DeepAgentConfig and kvStore to DeepAgent"
```

---

### Task 5: RunnerImpl kvStore Injection

**Files:**
- Modify: `src/main/java/com/openjiuwen/core/runner/RunnerImpl.java`

**Interfaces:**
- Consumes: RunnerConfig.kvStoreConfig（已有字段），KVStoreFactory（已有工厂），DeepAgent.setKvStore()（Task 4）
- Produces: RunnerImpl 在创建 DeepAgent 后注入 kvStore

- [ ] **Step 1: Read RunnerImpl.java to find the DeepAgent creation point**

Run: 搜索 RunnerImpl 中创建 DeepAgent 的代码位置（通过文件读取定位）

- [ ] **Step 2: Add kvStore creation and injection logic in RunnerImpl**

在 RunnerImpl 中 DeepAgent 构建完成后的位置添加：

```java
if (config.getKvStoreConfig() != null && config.getKvStoreConfig().get("type") != null) {
    String kvType = (String) config.getKvStoreConfig().get("type");
    Map<String, Object> kvConf = (Map<String, Object>) config.getKvStoreConfig().getOrDefault("conf", Map.of());
    BaseKVStore kvStore = KVStoreFactory.create(kvType, kvConf);
    deepAgent.setKvStore(kvStore);
}
```

添加必要的导入：
```java
import com.openjiuwen.spi.store.BaseKVStore;
import com.openjiuwen.spi.store.KVStoreFactory;
```

- [ ] **Step 3: Run compilation to verify no errors**

Run: `mvn compile -pl .`
Expected: BUILD SUCCESS

- [ ] **Step 4: Run existing tests to ensure no regressions**

Run: `mvn test -pl . -Dtest=*RunnerTest* -DfailIfNoTests=false`
Expected: ALL PASS — kvStore injection only activates when kvStoreConfig is set

- [ ] **Step 5: Commit**

```bash
git add src/main/java/com/openjiuwen/core/runner/RunnerImpl.java
git commit -m "feat(issue34): inject kvStore into DeepAgent from RunnerConfig.kvStoreConfig"
```

---

### Task 6: TaskPlanningRail Storage Creation

**Files:**
- Modify: `src/main/java/com/openjiuwen/harness/rails/TaskPlanningRail.java`
- Create: `src/test/java/com/openjiuwen/harness/rails/TaskPlanningRailStorageTest.java`

**Interfaces:**
- Consumes: TodoStorage/FileTodoStorage/KvTodoStorage（Tasks 1-2），TodoTool(TodoStorage)（Task 3），DeepAgentConfig.todoStorageType（Task 4），DeepAgent.kvStore（Task 4）
- Produces: TaskPlanningRail 根据 todoStorageType 创建 TodoStorage + TodoTool

- [ ] **Step 1: Write TaskPlanningRailStorageTest**

由于 TaskPlanningRail.init() 需要 DeepAgent 实例且依赖较多组件，此测试采用局部验证策略——验证 storage 创建逻辑而非完整 Rail 初始化：

```java
package com.openjiuwen.harness.rails;

import com.openjiuwen.core.foundation.store.kv.InMemoryKVStore;
import com.openjiuwen.harness.tools.FileTodoStorage;
import com.openjiuwen.harness.tools.KvTodoStorage;
import com.openjiuwen.harness.tools.TodoStorage;
import com.openjiuwen.spi.store.BaseKVStore;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

class TaskPlanningRailStorageTest {

    @Test
    void storageType_file_createsFileTodoStorage() {
        String todoStorageType = "file";
        BaseKVStore kvStore = null;
        TodoStorage storage = createStorage(todoStorageType, kvStore);
        assertInstanceOf(FileTodoStorage.class, storage);
    }

    @Test
    void storageType_kv_withKvStore_createsKvTodoStorage() {
        String todoStorageType = "kv";
        BaseKVStore kvStore = new InMemoryKVStore();
        TodoStorage storage = createStorage(todoStorageType, kvStore);
        assertInstanceOf(KvTodoStorage.class, storage);
    }

    @Test
    void storageType_kv_nullKvStore_fallsBackToFile() {
        String todoStorageType = "kv";
        BaseKVStore kvStore = null;
        TodoStorage storage = createStorage(todoStorageType, kvStore);
        assertInstanceOf(FileTodoStorage.class, storage);
    }

    @Test
    void storageType_file_withKvStore_stillUsesFile() {
        String todoStorageType = "file";
        BaseKVStore kvStore = new InMemoryKVStore();
        TodoStorage storage = createStorage(todoStorageType, kvStore);
        assertInstanceOf(FileTodoStorage.class, storage);
    }

    private static TodoStorage createStorage(String todoStorageType, BaseKVStore kvStore) {
        if ("kv".equals(todoStorageType) && kvStore != null) {
            return new KvTodoStorage(kvStore);
        }
        return new FileTodoStorage(Path.of(".todo"));
    }
}
```

- [ ] **Step 2: Modify TaskPlanningRail.init() to use todoStorageType**

在 `src/main/java/com/openjiuwen/harness/rails/TaskPlanningRail.java` 的 `init()` 方法中：

将原来的：
```java
todoTool = new TodoTool(deepAgent.getWorkspace().root().resolve(".todo").toString());
```

替换为：
```java
String todoStorageType = deepAgent.getConfig().getTodoStorageType();
TodoStorage todoStorage;
if ("kv".equals(todoStorageType) && deepAgent.getKvStore() != null) {
    todoStorage = new KvTodoStorage(deepAgent.getKvStore());
} else {
    if ("kv".equals(todoStorageType) && deepAgent.getKvStore() == null) {
        com.openjiuwen.core.common.logging.Loggers.HARNESS.warning(
            "todoStorageType is 'kv' but kvStore is null, falling back to file storage");
    }
    todoStorage = new FileTodoStorage(deepAgent.getWorkspace().root().resolve(".todo"));
}
todoTool = new TodoTool(todoStorage);
```

添加导入：
```java
import com.openjiuwen.harness.tools.TodoStorage;
import com.openjiuwen.harness.tools.FileTodoStorage;
import com.openjiuwen.harness.tools.KvTodoStorage;
```

- [ ] **Step 3: Run tests to verify**

Run: `mvn test -pl . -Dtest=TaskPlanningRailStorageTest -DfailIfNoTests=false`
Expected: ALL PASS

- [ ] **Step 4: Run full test suite for regression check**

Run: `mvn test -pl . -DfailIfNoTests=false`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add src/main/java/com/openjiuwen/harness/rails/TaskPlanningRail.java src/test/java/com/openjiuwen/harness/rails/TaskPlanningRailStorageTest.java
git commit -m "feat(issue34): TaskPlanningRail creates TodoStorage based on todoStorageType config"
```

---

### Task 7: RedisKVStoreProvider SPI

**Files:**
- Create: `src/main/java/com/openjiuwen/extensions/store/kv/RedisKVStoreProvider.java`
- Modify: `src/main/resources/META-INF/services/com.openjiuwen.spi.store.KVStoreProvider`

**Interfaces:**
- Consumes: KVStoreProvider（已有 SPI），RedisStore（已有实现），KVStoreFactory（已有工厂）
- Produces: RedisKVStoreProvider SPI Provider，使得 KVStoreFactory.create("redis", conf) 可用

- [ ] **Step 1: Write RedisKVStoreProvider**

```java
package com.openjiuwen.extensions.store.kv;

import com.openjiuwen.extensions.store.kv.RedisStore;
import com.openjiuwen.spi.store.BaseKVStore;
import com.openjiuwen.spi.store.KVStoreProvider;

import java.util.Map;

public class RedisKVStoreProvider implements KVStoreProvider {
    @Override
    public String typeName() {
        return "redis";
    }

    @Override
    public BaseKVStore create(Map<String, Object> conf) {
        Object redisClient = resolveRedisClient(conf);
        return new RedisStore(redisClient);
    }

    private Object resolveRedisClient(Map<String, Object> conf) {
        Object existing = conf.get("redis_client");
        if (existing != null) { return existing; }

        String host = conf.getOrDefault("host", "localhost") instanceof String ? (String) conf.getOrDefault("host", "localhost") : "localhost";
        int port = conf.getOrDefault("port", 6379) instanceof Number ? ((Number) conf.getOrDefault("port", 6379)).intValue() : 6379;
        String password = conf.get("password") instanceof String ? (String) conf.get("password") : null;
        boolean cluster = Boolean.parseBoolean(String.valueOf(conf.getOrDefault("cluster", "false")));

        return createJedisClient(host, port, password, cluster);
    }

    private Object createJedisClient(String host, int port, String password, boolean cluster) {
        try {
            if (cluster) {
                Class<?> jedisClusterClass = Class.forName("redis.clients.jedis.JedisCluster");
                java.util.Set<String> nodes = java.util.Set.of(host + ":" + port);
                if (password != null && !password.isEmpty()) {
                    Class<?> jedisPoolConfigClass = Class.forName("redis.clients.jedis.JedisPoolConfig");
                    Object poolConfig = jedisPoolConfigClass.getDeclaredConstructor().newInstance();
                    return jedisClusterClass.getDeclaredConstructor(java.util.Set.class, jedisPoolConfigClass, String.class)
                        .newInstance(nodes, poolConfig, password);
                }
                return jedisClusterClass.getDeclaredConstructor(java.util.Set.class).newInstance(nodes);
            }
            Class<?> jedisClass = Class.forName("redis.clients.jedis.Jedis");
            Object jedis = jedisClass.getDeclaredConstructor(String.class, int.class).newInstance(host, port);
            if (password != null && !password.isEmpty()) {
                jedisClass.getMethod("auth", String.class).invoke(jedis, password);
            }
            return jedis;
        } catch (Exception e) {
            throw new RuntimeException("Failed to create Jedis client: " + e.getMessage(), e);
        }
    }
}
```

- [ ] **Step 2: Update SPI registration file**

在 `src/main/resources/META-INF/services/com.openjiuwen.spi.store.KVStoreProvider` 中追加一行：

```
com.openjiuwen.extensions.store.kv.RedisKVStoreProvider
```

文件完整内容应为：
```
com.openjiuwen.spi.store.kv.InMemoryKVStoreProvider
com.openjiuwen.extensions.store.kv.RedisKVStoreProvider
```

- [ ] **Step 3: Run compilation to verify**

Run: `mvn compile -pl .`
Expected: BUILD SUCCESS

- [ ] **Step 4: Run existing KVStore SPI test to verify**

Run: `mvn test -pl . -Dtest=CheckpointerFactorySpiTest -DfailIfNoTests=false`
Expected: PASS — SPI registration works correctly

- [ ] **Step 5: Commit**

```bash
git add src/main/java/com/openjiuwen/extensions/store/kv/RedisKVStoreProvider.java src/main/resources/META-INF/services/com.openjiuwen.spi.store.KVStoreProvider
git commit -m "feat(issue34): add RedisKVStoreProvider SPI for KVStoreFactory redis type"
```

---

### Task 8: Tenant Isolation Integration Tests

**Files:**
- Create: `src/test/java/com/openjiuwen/harness/tools/TenantTodoIsolationTest.java`

**Interfaces:**
- Consumes: KvTodoStorage（Task 2），InMemoryKVStore，TenantContext/TenantContextHolder（已有多租户模块）
- Produces: 多租户隔离的完整验证测试

- [ ] **Step 1: Write TenantTodoIsolationTest**

```java
package com.openjiuwen.harness.tools;

import com.openjiuwen.core.foundation.store.kv.InMemoryKVStore;
import com.openjiuwen.core.multitenant.TenantContext;
import com.openjiuwen.core.multitenant.TenantContextHolder;
import com.openjiuwen.spi.store.BaseKVStore;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

class TenantTodoIsolationTest {
    private BaseKVStore kvStore;
    private KvTodoStorage storage;

    @BeforeEach
    void setUp() {
        kvStore = new InMemoryKVStore();
        storage = new KvTodoStorage(kvStore);
        TenantContextHolder.clear();
    }

    @AfterEach
    void tearDown() {
        TenantContextHolder.clear();
    }

    @Test
    void tenantA_create_tenantB_cannotSee() throws Exception {
        TenantContextHolder.setTenant(TenantContext.builder().tenantId("tenant_a").build());
        storage.save("session-1", List.of(
            TodoItem.create("task-a1", "Executing task-a1", "desc", TodoStatus.IN_PROGRESS, null),
            TodoItem.create("task-a2", "Executing task-a2", "desc", TodoStatus.PENDING, null)
        ));

        TenantContextHolder.setTenant(TenantContext.builder().tenantId("tenant_b").build());
        List<TodoItem> loaded = storage.load("session-1");
        assertTrue(loaded.isEmpty());
    }

    @Test
    void tenantA_create_tenantA_canSee() throws Exception {
        TenantContextHolder.setTenant(TenantContext.builder().tenantId("tenant_a").build());
        storage.save("session-1", List.of(
            TodoItem.create("task-a1", "Executing task-a1", "desc", TodoStatus.IN_PROGRESS, null)
        ));

        List<TodoItem> loaded = storage.load("session-1");
        assertEquals(1, loaded.size());
        assertEquals("task-a1", loaded.get(0).getContent());
    }

    @Test
    void noTenant_create_noTenant_canSee() throws Exception {
        TenantContextHolder.clear();
        storage.save("session-1", List.of(
            TodoItem.create("task-1", "Executing task-1", "desc", TodoStatus.TODO, null)
        ));

        TenantContextHolder.clear();
        List<TodoItem> loaded = storage.load("session-1");
        assertEquals(1, loaded.size());
    }

    @Test
    void tenantB_create_doesNotOverwrite_tenantA() throws Exception {
        TenantContextHolder.setTenant(TenantContext.builder().tenantId("tenant_a").build());
        storage.save("session-1", List.of(
            TodoItem.create("task-a", "Executing task-a", "desc", TodoStatus.TODO, null)
        ));

        TenantContextHolder.setTenant(TenantContext.builder().tenantId("tenant_b").build());
        storage.save("session-1", List.of(
            TodoItem.create("task-b", "Executing task-b", "desc", TodoStatus.TODO, null)
        ));

        TenantContextHolder.setTenant(TenantContext.builder().tenantId("tenant_a").build());
        List<TodoItem> loaded = storage.load("session-1");
        assertEquals(1, loaded.size());
        assertEquals("task-a", loaded.get(0).getContent());
    }

    @Test
    void delete_isTenantScoped() throws Exception {
        TenantContextHolder.setTenant(TenantContext.builder().tenantId("tenant_a").build());
        storage.save("session-1", List.of(
            TodoItem.create("task-a", "Executing task-a", "desc", TodoStatus.TODO, null)
        ));

        TenantContextHolder.setTenant(TenantContext.builder().tenantId("tenant_b").build());
        storage.save("session-1", List.of(
            TodoItem.create("task-b", "Executing task-b", "desc", TodoStatus.TODO, null)
        ));
        storage.delete("session-1");

        TenantContextHolder.setTenant(TenantContext.builder().tenantId("tenant_a").build());
        List<TodoItem> loaded = storage.load("session-1");
        assertEquals(1, loaded.size());
    }

    @Test
    void noTenant_keyStoredWithoutPrefix() throws Exception {
        TenantContextHolder.clear();
        storage.save("session-1", List.of(
            TodoItem.create("task-1", "Executing task-1", "desc", TodoStatus.TODO, null)
        ));
        Object value = kvStore.get("session-1:todo");
        assertNotNull(value);
    }
}
```

- [ ] **Step 2: Run tests to verify**

Run: `mvn test -pl . -Dtest=TenantTodoIsolationTest -DfailIfNoTests=false`
Expected: ALL PASS

- [ ] **Step 3: Commit**

```bash
git add src/test/java/com/openjiuwen/harness/tools/TenantTodoIsolationTest.java
git commit -m "feat(issue34): add tenant isolation integration tests for KvTodoStorage"
```

---

### Task 9: Full Regression Test

**Files:** 无新增，全量回归验证

- [ ] **Step 1: Run full test suite**

Run: `mvn test -pl . -DfailIfNoTests=false`
Expected: ALL PASS — 所有新增和现有测试均通过

- [ ] **Step 2: Run compilation check**

Run: `mvn compile -pl .`
Expected: BUILD SUCCESS

- [ ] **Step 3: Final commit (if any cleanup needed)**

```bash
git add -A
git commit -m "chore(issue34): final cleanup and regression verification"
```
