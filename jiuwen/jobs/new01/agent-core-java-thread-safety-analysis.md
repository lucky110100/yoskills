# agent-core-java 线程安全分析报告

> 分析对象：`D:\jiuwen\main\agent-core-java`（openJiuwen Core Java，分支 `730`，Java 17 / Maven）
> 分析日期：2026-08-11
> 分析方法：静态扫描（反模式 grep + 逐类阅读）+ 并发压测复现（JDK 17 / JUnit 5）
> 验证测试：`agent-core-java/src/test/java/com/openjiuwen/core/common/concurrent/ThreadSafetyConcurrencyAnalysisTest.java`
> 输出位置：`yoskills/jiuwen/jobs/new01/agent-core-java-thread-safety-analysis.md`

---

## 一、分析方法与范围

agent-core-java 共 1884 个 `.java` 源文件，横跨 `core / agentteams / agentevolving / autoharness / harness / spi / extensions / dev_tools` 等顶层包。本次分析聚焦「**共享可变状态在并发访问下的正确性**」。

### 1.1 三轮迭代后的最终方法论

本报告经三轮迭代（首轮交付 → 用户点名 `SystemPromptBuilder` 漏扫触发第二轮补扫 → 用户点名 `ContextEngine` 漏扫触发第三轮补扫），方法论收敛为**双驱动四步法**。前两轮的核心教训：**只靠反模式 grep 驱动必然漏报**——接口声明字段（`Map<...> = new HashMap<>()`）的类名只在右侧 `new` 表达式出现，左侧字段类型列匹配不到；宽口径 grep 又会被分页截断，命中了却看不到；按 grep 捞候选等于只扫「记得要找的模式」，按子系统逐包枚举才扫「该扫的地方」。故最终法改为「按子系统枚举」与「按反模式 grep」**双驱动**。

**第一步 · 反模式 grep（横切捞候选）**
正则须同时覆盖**接口声明**与**具体实现**两侧，且分页上限调到 `head_limit=0`（全量）避免截断：
- 非并发容器：`=\s*new\s+(Linked)?(HashMap|HashSet|TreeMap|TreeSet|ArrayDeque|LinkedList|PriorityQueue|Vector|Hashtable|LinkedHashSet)\s*<` —— 同时匹配 `Map<...> = new HashMap<>()`（右侧类名）与 `HashMap<...> = new HashMap<>()`（左侧类名）两种写法。
- 非原子计数器：`private\s+(final\s+)?(int|long)\s+\w+\s*[=;]` + `\w+\s*(\+\+|\+=)`。
- DCL 单例缺 `volatile`：`private\s+static\s+\w+\s+instance` 后反射断言无 `volatile` 修饰符。
- check-then-act：`containsKey\s*\([^)]*\)\s*\{[^}]*\bput\b`（多行模式）。
- `computeIfAbsent` 内副作用 / 阻塞 lambda；`CompletableFuture` 回调写共享状态；`synchronized` 锁不一致（部分方法加锁部分不加）。

**第二步 · 按子系统逐包枚举（纵向兜底）**
对 `core` 下每个子包（`context / foundation / graph / workflow / controller / memory / session / singleagent / runner` 等）及 `agentteams / autoharness / harness` 做目录级穷举，逐文件扫字段声明。**这是针对「grep 漏报」的兜底**——`SystemPromptBuilder`（`singleagent/prompts`）和 `ContextEngine`（`context`）都是靠这步补回的。

**第三步 · 字段级过滤**
从 grep 命中筛出缩进为 0 的字段声明（`private ... field = new ...`），排除方法内局部变量；静态字段与实例字段都留。

**第四步 · 追调用链判定「是否真并发」**
判定标准从「类型层是否安全」升级为「调用链层是否并发」。对每个字段级命中，grep 其 `put/get/remove/++` 调用方，确认是否跨线程共享：在 `parallelStream` / 多线程池 / `CompletableFuture.thenAccept` / 事件回调路径 → 疑似并发；在串行 for + 单线程池 `poolSize(1,1)` + `future.get` 阻塞 → 排除（如 `AutoHarnessOrchestrator.taskContexts`）。

### 1.2 扫描的 5 类反模式

1. 非线程安全集合（`HashMap / LinkedHashMap / HashSet / ArrayList / StringBuilder`）作为字段或静态字段，且无同步保护。
2. 非原子计数器（`int / long` 字段 + `++ / +=`），非 `Atomic*`、非 `synchronized`。
3. 单例双重检查锁定（DCL）中 `instance` 字段是否声明 `volatile`。
4. 静态工厂/注册表的 check-then-act（`containsKey` + `put`）复合操作。
5. 多 Map / 多字段的复合操作非原子性（TOCTOU）。

对每个候选点，逐类读取其字段的访问路径（`get / put / ++` 是否在 `synchronized` 块或并发容器内），判定「是否真的被并发访问」与「是否有同步保护」，最终给出风险等级。

### 1.3 已知工具缺口（诚实交代）

- 未跑 `jcstress`：可见性/重排序类缺陷（如 P1-2 不安全发布）JUnit 压测复现能力弱。
- 未用静态分析工具：SpotBugs/ErrorProne/PMD 的并发检测器没跑，可能遗漏人眼 grep 抓不到的模式（锁不同 monitor 的死锁、`wait/notify` 守卫条件错）。
- `CompletableFuture` 回调线程与主线程的 happens-before 未系统分析。
- `computeIfAbsent` 里阻塞 lambda / 副作用未单独一轮深扫。
- 多租户目录、checkpointer 后端、`ResourceMgr`/`TagMgr`/`ThreadSafeDict` 的 check-then-act 仍未追。

> 说明：本项目对并发总体有较强意识——`OpenJiuwenExecutors` 用 `ConcurrentHashMap.newKeySet()`，SPI 工厂类（`VectorStoreFactory / KVStoreFactory / ObjectStorageFactory / CheckpointerFactory` 等）普遍用 `ConcurrentHashMap`，DCL 单例（`TaskManager / UserConfig / PathChecker / LongTermMemory / ParserRegistry / PromptApplier / TemplateManager / ServiceContext / SingletonSupport`）均正确使用 `volatile`，`KeyLockedStore` 用 striped lock。**下列问题是在这套总体规范之外遗漏的缺陷**，部分带有「同类已修、此处漏修」的特征。

---

## 二、问题清单（按风险排序）

### 修复状态总览（2026-08-13 验证更新）

| 编号 | 风险 | 问题摘要 | 修复状态 |
|---|---|---|---|
| P0-1 | 🔴 高 | ModelAllocators 轮询分配器非原子计数器 + 非并发集合 | ✅ 已修复 |
| P0-2 | 🔴 高 | TeamDatabase.droppedSessionIds 非线程安全 HashSet | ✅ 已修复 |
| P0-3 | 🔴 高 | Model.FACTORY_REGISTRY 静态 LinkedHashMap 无锁并发读写 | ✅ 已修复 |
| P0-4 | 🔴 高 | ContextEngine.contextPool 共享 HashMap 无锁 check-then-act + 遍历 | ✅ 已修复 |
| P1-1 | 🟠 中高 | Vertex.callCount/streamCallCount 非原子计数器 + logMessage HashMap | ✅ 已修复 |
| P1-2 | 🟠 中高 | LspDiagnosticRegistry.instance 非 volatile 不安全发布 | ✅ 已修复 |
| P1-3 | 🟠 中高 | TaskLoopController/LoopQueues 非并发集合 + 非原子计数器 | ✅ 已修复 |
| P2-1 | 🟡 中 | InMemoryKVStore 双 Map TOCTOU | ✅ 已修复 |
| P2-2 | 🟡 中 | EntityDef/RelationDef 静态 LinkedHashMap + 无锁 registerDescription | ✅ 已修复 |
| P2-3 | 🟡 中 | LLMExecutableState.accumulatedContent StringBuilder 无同步 | ✅ 已修复 |
| P2-4 | 🟠 中高 | SystemPromptBuilder 暴露内部可变状态 | ✅ 已修复（此前已修复） |
| P2-5 | 🟡 中 | WorkflowSpec 边表/组件表 HashMap 运行期被读写 | ✅ 已修复 |
| P2-6 | 🟢 低 | BaseRegistry check-then-act + keySet 引用外泄 | ✅ 已修复 |
| P2-7 | 🟢 低 | LSPServerManager 多 LinkedHashMap/HashSet 字段 | ✅ 已修复 |

> **验证方式**：全部 15 个问题通过 `ThreadSafetyConcurrencyAnalysisTest`（26 个回归测试用例）验证；受影响类的既有测试（ContextEngineTest / TaskLoopWorkspaceCompatibilityTest / ModelAllocatorCompatibilityTest / InMemoryKVStoreTest / AutoHarnessCompatibilityTest 等共 118 个）全部通过，零回归。

### 🔴 P0-1：ModelAllocators 轮询分配器非原子计数器 + 非并发集合

> **修复状态：✅ 已修复** — `RoundRobinModelAllocator.index` 改 `AtomicInteger`（`getAndIncrement` 消除丢失更新）；`ByModelNameAllocator.innerIndexes` 改 `ConcurrentHashMap<String, AtomicInteger>`（`computeIfAbsent` + `getAndIncrement` 消除 `getOrDefault+put` 复合操作竞态）；`stateDict/loadStateDict/resetIndexes` 同步适配。回归测试：`ModelAllocatorsRace.roundRobinIndexIsAtomicAndLosslessUnderConcurrency` / `byModelNameInnerIndexesIsConcurrentAndRaceFree`（16 线程 × 5000 次无丢失更新）。

- **文件**：`src/main/java/com/openjiuwen/agentteams/agent/ModelAllocators.java`
- **位置**：
  - `RoundRobinModelAllocator`：`index`（`private int`，第 130 行），`allocate()` 第 158–159 行 `pool.get(index % pool.size()); index += 1;`
  - `ByModelNameAllocator`：`innerIndexes`（`private Map<String,Integer> = new LinkedHashMap<>()`，第 209 行），`allocate()` 第 239–240 行 `getOrDefault` + `put`
- **缺陷类型**：非原子自增（丢失更新）+ 非线程安全集合并发读写
- **并发场景**：`model_pool` 本质为多消费者设计——多个 teammate / agent 会并发调用 `allocate(modelName)` 选取本轮使用的模型。`index += 1` 是「读-改-写」三步，非原子；多线程并发下必然丢失更新。`ByModelNameAllocator` 更严重：`LinkedHashMap` 在并发 `put` + 遍历时可能抛 `ConcurrentModificationException` 或内部哈希链损坏。
- **复现证据**（测试 `RoundRobinAllocatorRaceTest`，16 线程 × 5000 次）：
  ```
  [RoundRobin] index=26118 expected=80000 lostUpdate=53882
  ```
  **67% 的自增被丢失**——非原子计数器丢失更新的直接证据。
- **影响**：
  - 轮询失去均匀性，模型池中部分模型被跳过、部分被过度使用（影响多 API key 负载均衡与限流）。
  - `ByModelNameAllocator` 的 `LinkedHashMap` 在并发下可能结构损坏导致分配异常或返回错误 group。
- **修复建议**：
  - `RoundRobinModelAllocator.index` 改为 `AtomicInteger`，`allocate` 用 `index.getAndIncrement()`。
  - `ByModelNameAllocator.innerIndexes` 改为 `ConcurrentHashMap<String, AtomicInteger>`，`allocate` 用 `computeIfAbsent(name, k -> new AtomicInteger()).getAndIncrement() % size`，消除 `getOrDefault + put` 复合操作。

---

### 🔴 P0-2：TeamDatabase.droppedSessionIds 非线程安全 HashSet（同类已修、此处漏修）

> **修复状态：✅ 已修复** — `droppedSessionIds` 改 `ConcurrentHashMap.newKeySet()`，与同类三 Map 对齐。回归测试：`TeamDatabaseDroppedSessionIds.droppedSessionIdsIsConcurrentSet`。

- **文件**：`src/main/java/com/openjiuwen/agentteams/tools/database/TeamDatabase.java`
- **位置**：第 52 行 `private final Set<String> droppedSessionIds = new HashSet<>();`
- **访问点**：
  - `add`：第 498 行（`dropSessionTablesById`）、第 518 行（`cleanupAllRuntimeState`）
  - `remove`：第 454 行（`createSessionTables` 相关路径）
  - `contains`：第 1048 行（`currentSessionTables`，被 `createMember / getTeamMembers` 等间接调用）
  - `clear`：第 146、291 行（`close / cleanup`）
- **缺陷类型**：非线程安全集合
- **并发场景**：源码注释 X.CON.05（第 47–51 行）明确指出：「**concurrent spawn_member tool calls hit createMember + getTeamMembers in parallel**」——开发者已识别并发路径，并据此把 `teams / members / sessions` 三个 Map 改为 `ConcurrentHashMap`。**但 `droppedSessionIds` 仍为 `HashSet`，是同一轮整改中遗漏的唯一一处**。
- **影响**：`HashSet` 在并发 `add/remove/contains` 下可能内部结构损坏（JDK 8+ 表现为偶发 `null` 节点导致 `contains` 抛 NPE、或静默返回错误值），使 `currentSessionTables()` 第 1048–1049 行误抛 `IllegalStateException("Session tables are not created for session: ...")`，或反之漏抛导致对已 drop 的 session 操作。
- **复现**：测试 `TeamDatabaseDroppedSessionIdsRaceTest` 通过反射对 `droppedSessionIds` 并发 `add/remove/contains`。JDK 17 下 `HashSet` 并发修改以「静默损坏 / 偶发异常」为主，确定性弱，但设计缺陷客观存在（与同类三 Map 形成对比即可确证）。
- **修复建议**：`private final Set<String> droppedSessionIds = ConcurrentHashMap.newKeySet();`（与 `OpenJiuwenExecutors.MANAGED_EXECUTORS` 同款）。一行修复。

---

### 🔴 P0-3：Model.FACTORY_REGISTRY 静态 LinkedHashMap 无锁并发读写

> **修复状态：✅ 已修复** — `FACTORY_REGISTRY` 改 `ConcurrentHashMap`（弱一致迭代器不抛 CME，并发 `registerFactory` + `entrySet` 遍历安全）。回归测试：`ModelFactoryRegistry.factoryRegistryIsConcurrentMap` / `concurrentRegisterAndTraversalNoCme`（8 写 + 8 读线程不抛 CME）。

- **文件**：`src/main/java/com/openjiuwen/core/foundation/llm/Model.java`
- **位置**：第 81 行 `private static final Map<String, ModelClientFactory> FACTORY_REGISTRY = new LinkedHashMap<>();`
- **访问点**：
  - 写：第 97 行 `registerFactory()`（`public static`，**无 synchronized**）；`static{}` 块第 85 行、`DefaultModelClientFactories.ensureRegistered()`（后者有锁）
  - 读：第 185 行 `FACTORY_REGISTRY.get(provider)`；第 189 行 `entrySet()` 遍历（大小写不敏感回退查找）；第 198 行 `keySet()`
- **缺陷类型**：非线程安全集合 + 静态全局可变状态
- **并发场景**：`registerFactory` 是公开 API，支持运行时注册 SPI 扩展；`new Model(...)` 构造时 `createModelClient` 会读 `FACTORY_REGISTRY` 并在 `get` 失败时遍历 `entrySet()`。多线程下：一个线程运行时注册工厂、另一线程构造 Model 遍历注册表 → `ConcurrentModificationException` 或内部结构损坏。
- **复现证据**（测试 `ModelFactoryRegistryRaceTest`，反射拿 `FACTORY_REGISTRY`，8 线程 `put` + 8 线程 `entrySet` 遍历）：
  ```
  [Model.FACTORY_REGISTRY] traversalError=java.util.ConcurrentModificationException writerError=null
  ```
  **明确复现 `ConcurrentModificationException`**——LinkedHashMap fail-fast 在并发修改下的直接证据。
- **影响**：运行时注册扩展工厂与 Model 构造并发时，遍历抛 CME 中断创建；或静默结构损坏导致 `get` 返回错误工厂。
- **修复建议**：
  - 优先：`FACTORY_REGISTRY` 改为 `new ConcurrentHashMap<>()`，并改用 `computeIfAbsent` 注册避免覆盖；遍历改用 `forEach`（`ConcurrentHashMap` 的弱一致迭代器不会抛 CME）。
  - 或：`registerFactory` 与遍历路径加 `synchronized(Model.class)`。

---

### 🔴 P0-4：ContextEngine.contextPool 共享 HashMap 无锁 check-then-act + 遍历（实测复现 CME）

> **修复状态：✅ 已修复** — `contextPool` / `PROCESSOR_FACTORY_MAP` / `PROCESSOR_CLASS_MAP` 均改 `ConcurrentHashMap`；`createContext` 的 `containsKey→get→put` check-then-act 改 `computeIfAbsent` 原子化（同一 contextId 仅创建一个实例）；`clearContext` 的遍历+收集+删除改 `entrySet().removeIf` 原子化；`saveContexts` 遍历依赖 ConcurrentHashMap 弱一致迭代器。回归测试：`ContextEnginePool.fieldsAreConcurrentMaps` / `concurrentCreateContextReturnsSameInstance`（16 线程并发 createContext 同一 contextId 返回同一实例）。

- **文件**：`src/main/java/com/openjiuwen/core/context/ContextEngine.java`（fork 版本与 main 版本经 `diff` 完全一致）
- **位置**：
  - 第 96 行 `private final Map<String, ModelContext> contextPool = new HashMap<>();`（**实例共享可变状态**）
  - 第 57 行 `private static final Map<String, Function<Object, ContextProcessor>> PROCESSOR_FACTORY_MAP = new LinkedHashMap<>();`
  - 第 64 行 `private static final Map<String, Class<? extends ContextProcessor>> PROCESSOR_CLASS_MAP = new LinkedHashMap<>();`
- **访问点**（`contextPool`，全部无 `synchronized`、无 `Lock`、非并发集合）：
  - 写：`createContext` 第 154/155/172 行 **check-then-act**（`containsKey` → `get` → `put`）；`clearContext` 第 249/267/278 行（`clear`、`remove`）
  - 读：`getContext` 第 226 行 `getOrDefault`；`clearContext` 第 255 行 `entrySet()` 遍历；`saveContexts` 第 319 行 `entrySet()` 遍历
- **共享面**：单实例 `ContextEngine` 由 `WorkflowController`/`LlmController` 作为字段持有（`WorkflowController.java:181`、`LlmController.java:183`），并传给各自 `EventHandler`；`LlmEventHandler.handleUserInput` 等在请求/事件处理路径调用 `createContext`/`getContext`，`WorkflowEventHandler` 在多 workflow 事件流并发调用 → 同一 `contextPool` 成为跨线程共享可变状态。
- **缺陷类型**：非线程安全集合（`HashMap`）+ check-then-act（TOCTOU）+ fail-fast 遍历与并发修改冲突
- **复现证据**（测试 `ContextEngineContextPoolRaceTest`，反射断言 `contextPool` 为 `HashMap` 且非 `ConcurrentHashMap`；16 线程 × 5000 次并发 `createContext`/`getContext`/`clearContext`/`saveContexts`）：
  ```
  [ContextEngine.contextPool] ConcurrentModificationException 次数: 331/80000  （首跑）
  [ContextEngine.contextPool] ConcurrentModificationException 次数: 1929/80000 （次跑）
  [ContextEngine.contextPool] ConcurrentModificationException 次数: 837/80000   （三跑）
  ```
  **多次复现 `ConcurrentModificationException`，计数非确定性（331/1929/837）正说明竞态真实存在**——`clearContext`/`saveContexts` 对 `entrySet()` 的 fail-fast 迭代与并发 `put`/`remove` 冲突的直接证据。反射同时坐实类型为非并发集合（确定性证据，不依赖调度）。
- **影响**：高并发请求下 context 丢失/重复创建（check-then-act 丢更新）、`getContext` 误返回 null 或死循环（HashMap 结构损坏）、`saveContexts`/`clearContext` 抛 CME 中断流程。
- **修复建议**：
  - `contextPool` → `new ConcurrentHashMap<>()`；`createContext` 用 `computeIfAbsent` 原子化 check-then-act，避免重复创建与覆盖。
  - `clearContextBySession` 的「遍历+收集+删除」改用 `contextPool.entrySet().removeIf(e -> e.getValue().sessionId().equals(sessionId))`（`ConcurrentHashMap` 支持且不抛 CME）。
  - 静态 `PROCESSOR_FACTORY_MAP`/`PROCESSOR_CLASS_MAP` 同 P0-3 处理：改 `ConcurrentHashMap` + `synchronized`/`computeIfAbsent` 注册（当前注册主要在 `static{}`，运行期并发写概率低，但公开 `registerProcessor` 是隐患入口）。

---

### 🟠 P1-1：Vertex.callCount / streamCallCount 非原子计数器（图执行核心）

> **修复状态：✅ 已修复** — `callCount` / `streamCallCount` 改 `AtomicInteger`（`incrementAndGet` / `get` / `set`）；`logMessage` 改 `ConcurrentHashMap`（initLog 路径无锁写入安全）。回归测试：`VertexCounters.countersAreAtomicInteger` / `logMessageIsConcurrentMap`。

- **文件**：`src/main/java/com/openjiuwen/core/graph/Vertex.java`
- **位置**：
  - 字段：第 79 行 `private int callCount = 0;`、第 80 行 `private int streamCallCount = 0;`（**均非 volatile、非 Atomic**）
  - 自增：第 244 行 `callCount++`（`call()` 的 finally，无锁）、第 951 行 `streamCallCount++`（`streamCall()`，无锁）
  - 读取：第 1052 行 `isDone()` 返回 `callCount == streamCallCount || callCount == streamCallCount + 1`
  - 重置：第 1095–1096 行 `reset()` 写两者（无锁）
- **缺陷类型**：非原子自增 + 可见性
- **并发场景**：Vertex 是图节点的执行包装，源码注释（第 70–72 行）明确提到「**concurrently running INVOKE and COLLECT postInvoke calls**」——图/Pregel 执行框架天然多线程。`callCount++` 与 `streamCallCount++` 在不同线程的 `call / streamCall` 路径并发自增；`isDone()` 依赖两者比较判定节点是否完成。
- **影响**：
  - 丢失更新使 `callCount / streamCallCount` 偏小，`isDone()` 可能提前返回 `true`（节点未真正完成被判完成）或延后。
  - 非 volatile 字段的写入对其它线程不可见，`isDone()` 可能长期读到过期值导致图执行卡死或提前收尾。
  - `reset()` 与 `call()` 并发时计数器被清零，进一步破坏 `isDone()` 语义。
- **复现**：未单独写测试（Vertex 构造依赖 `Executable` 上下文，集成成本高），但缺陷模式与 P0-1 完全一致——非原子计数器在并发自增下必丢更新（P0-1 已用 `index=26118/80000` 的实测数据确证同型缺陷）。
- **修复建议**：`callCount / streamCallCount` 改为 `AtomicInteger`，自增用 `incrementAndGet()`，`isDone()` 用 `get()` 读取；`reset()` 用 `set(0)`。
- **补充（第三轮重扫）**：同类的 `Vertex.logMessage`（第 101 行 `private Map<String, Object> logMessage = new HashMap<>()`）在 `initLog`（169–171 行 `put`）与可能的并发 `streamCall`/`call` 路径同样无锁访问，属同型非并发集合缺陷，一并按 `ConcurrentHashMap` 修复。

---

### 🟠 P1-2：LspDiagnosticRegistry.instance 非 volatile 的不安全发布

> **修复状态：✅ 已修复** — `instance` 字段声明为 `volatile`，消除不安全发布。回归测试：`LspDiagnosticRegistryPublication.instanceFieldIsVolatile`。

- **文件**：`src/main/java/com/openjiuwen/harness/lsp/core/LspDiagnosticRegistry.java`
- **位置**：第 18 行 `private static LspDiagnosticRegistry instance = new LspDiagnosticRegistry();`；第 50–52 行 `reset()` 写 `instance = new LspDiagnosticRegistry();`（**无 synchronized**）；第 41–43 行 `getInstance()` 直接 `return instance;`（**无 synchronized**）
- **缺陷类型**：不安全发布（unsafe publication）
- **缺陷说明**：本类采用饿汉式初始化，但暴露了 `public reset()`。`reset()` 重写 `instance` 后，由于：
  1. `instance` 字段**未声明 `volatile`**；
  2. `getInstance()` 与 `reset()` **不在同一把锁内**（`getInstance` 无 synchronized，`reset` 也无；只有 `register / getAndClear / peek` 是 synchronized 实例方法）。
  
  故 `reset()` 对 `instance` 的写入与 `getInstance()` 的读取之间**没有 happens-before 关系**。其它线程可能在 `reset()` 后仍长期看到旧引用，或看到部分构造的对象（构造函数执行中途的引用泄漏）。
- **对比**：同项目所有 DCL 单例（`TaskManager / UserConfig / PathChecker / LongTermMemory / ParserRegistry / PromptApplier / TemplateManager / ServiceContext`）均正确声明 `volatile`，`SingletonSupport` 用 `ConcurrentHashMap` + `synchronized`，唯独本类遗漏——与 P0-2 同属「同类已修、此处漏修」。
- **确定性证据**（测试 `LspDiagnosticRegistryUnsafePublicationTest.instanceFieldLacksVolatile`）：通过反射断言 `instance` 字段修饰符**不含 `volatile`**、`getInstance()` **不含 `synchronized`**——直接确证设计缺陷。
- **影响**：在测试/管理代码调用 `reset()` 后，工作线程可能拿到旧实例继续向已废弃的 `pending` 列表写入诊断，或读到部分构造对象触发 NPE。
- **修复建议**：`instance` 声明为 `volatile`；或 `getInstance / reset` 加 `synchronized(LspDiagnosticRegistry.class)`（与 `register` 等实例方法统一用 class 锁）。推荐前者，改动最小。

---

### 🟠 P1-3：TaskLoopController.SessionState / LoopQueues 非并发集合 + 非原子计数器（第三轮新增）

> **修复状态：✅ 已修复** — `LoopQueues.steering` / `isFollowUp` 改 `ConcurrentLinkedQueue`（`drainSteering`/`drainFollowUp` 改 `poll` 循环原子排空）；`events` 改 `PriorityBlockingQueue`；`sequence` 改 `AtomicLong`（`incrementAndGet`）；`SessionState.roundCounter` 改 `AtomicInteger`，`isRoundActive` / `isLastRoundFollowUp` / `lastResult` 加 `volatile`。回归测试：`TaskLoopConcurrency.loopQueuesFieldsAreConcurrent` / `concurrentPushAndDrainSteeringNoLoss`（8 生产者 × 1000 消息不丢失）/ `sessionStateFieldsAreAtomicAndVolatile` / `concurrentPrepareRoundNoLostUpdate`（16 线程 × 500 次轮次计数不丢失）。

- **文件**：`src/main/java/com/openjiuwen/harness/task_loop/TaskLoopController.java`、`src/main/java/com/openjiuwen/harness/task_loop/LoopQueues.java`
- **位置**：
  - `LoopQueues.steering`(21) `ArrayDeque`、`isFollowUp`(28) `ArrayDeque`、`events`(35) `PriorityQueue`、`sequence`(36) `long`（非 volatile）
  - `TaskLoopController.SessionState.roundCounter`(450) `int`（非 volatile）、`isLastRoundFollowUp`/`isRoundActive`(451,452) `boolean`、`lastResult`(453) `Map`、`queues`(449) 持有上述非并发 `LoopQueues`
  - 自增：`LoopQueues.pushEvent` 第 113 行 `++sequence`；`SessionState` 第 73 行 `state.roundCounter += 1`
  - 读写：`enqueueSteering`(283) 调 `queues.pushSteer`（`steering.add`）；`drainSteering`/`drainEvents` 遍历+clear；`getRound`(397) 读 `roundCounter`，stale 判定(167-168) 比较完成轮与当前轮
- **缺陷类型**：非线程安全集合（`ArrayDeque`/`PriorityQueue`/`HashMap`）+ 非原子计数器（`long++`/`int += 1`）+ 可见性
- **共享面**：`enqueueSteering` 由 `DeepAgent:1172`（agent 主循环）与 `TaskLoopEventHandler:187`（事件回调）调用；`sessionStates` 虽是 `ConcurrentHashMap`，但 `computeIfAbsent` 返回的 `SessionState` 内部字段（`roundCounter`/`queues`）**无任何同步保护**。若外部 steering 从非主线程推入（事件回调线程），与主循环的 `drainSteering`/`drainEvents`/`roundCounter += 1` 并发 → `ArrayDeque.add` 与 `clear`/遍历竞争致结构损坏、`++sequence` 丢更新致事件 ID 重复、`roundCounter` 丢失更新致 stale 判定错乱。
- **风险定级**：中。触发依赖「steering/事件从非主线程推入」这一调度假设；agent 纯单线程串行时安全。但 `TaskLoopEventHandler` 处理外部事件的设计本身暗示了跨线程入队可能。
- **复现证据**（测试 `LoopQueuesRaceTest`，反射断言 `sequence` 非 `AtomicLong`/非 `volatile`、`steering` 为 `ArrayDeque` 非 `ConcurrentLinkedQueue`；8 线程 × 5000 次并发 `pushEvent`，纯写写压测聚焦 `++sequence` 丢失更新）：
  ```
  [LoopQueues] 并发是否在 60s 内完成: true
  [LoopQueues] pushEvent 调用数=40000 distinct sequence=39235 CME=0
  [LoopQueues] 其它异常: null
  ```
  **坐实竞态**：`distinct sequence=39235` 而调用 40000 次——`++sequence` 丢失更新 765 次（约 1.9%），事件 ID 重复。若 `sequence` 为 `AtomicLong`，每次自增原子唯一，distinct 应等于调用数。反射同时坐实字段类型为非并发/非原子。另在混合 `drainSteering`/`drainEvents` 的强压测下还会触发 `ArrayIndexOutOfBoundsException`（ArrayDeque 结构损坏）与超时死循环，此处为 CI 稳定性改用纯写写。
- **修复建议**：`SessionState` 内字段加 `synchronized` 或改 `AtomicInteger`/`volatile`；`LoopQueues` 的 `steering`/`isFollowUp`/`events` 改 `ConcurrentLinkedQueue`/`PriorityBlockingQueue`，`sequence` 改 `AtomicLong`。或约束 `enqueueSteering` 仅在主循环线程调用并文档化。

---

### 🟡 P2-1：InMemoryKVStore 双 Map 复合操作竞态（TOCTOU）

> **修复状态：✅ 已修复** — 将 `values` + `expiryAt` 双 Map 合并为单一 `Map<String, Entry>`（`Entry` 捆绑 value + expiryAt）；`set` 用 `compute` 原子写值+清过期；`cleanupIfExpired` 用 `computeIfPresent` 原子判过期+删值；`exclusiveSet` 用 `putIfAbsent` 原子化。消除双 Map TOCTOU。回归测试：`InMemoryKVStoreAtomicity.mergedIntoSingleStoreMap` / `setOverExpiredKeyIsNotLostUnderConcurrentCleanup`（并发 set + cleanup 不丢失覆盖写入的新值）。

- **文件**：`src/main/java/com/openjiuwen/core/foundation/store/kv/InMemoryKVStore.java`
- **位置**：
  - 字段：第 22 行 `values = new ConcurrentHashMap<>()`、第 29 行 `expiryAt = new ConcurrentHashMap<>()`（两个独立 Map）
  - `set()` 第 40–41 行：`values.put(key, value); expiryAt.remove(key);`
  - `exclusiveSet()` 第 56–62 行：`putIfAbsent` 成功后 `expiryAt.put(...)`
  - `cleanupIfExpired()` 第 222–228 行：读 `expiryAt.get(key)`，若过期则 `values.remove(key); expiryAt.remove(key);`
- **缺陷类型**：复合操作非原子性 / TOCTOU
- **缺陷说明**：`values` 与 `expiryAt` 各自是 ConcurrentHashMap（单 Map 内部线程安全），但**两个 Map 的组合操作非原子**。竞态窗口示例：
  - 线程 A 调 `set(key, newVal)`：执行 `values.put(key, newVal)`（新值已写入），**尚未执行** `expiryAt.remove(key)`。
  - 线程 B 同时调 `get(key)` → `cleanupIfExpired(key)`：读到 `expiryAt` 中**旧的、已过期的**时间戳 → `values.remove(key)` 把 A 刚写入的新值误删。
  - 结果：`set` 的覆盖被丢失，后续 `get` 返回 `null`。
- **影响**：键值对的覆盖语义在并发下被破坏，新写入的值可能被并发触发的过期清理误删。对依赖 `set` 覆盖 + `get` 的流程（如 checkpointer 状态更新）可能造成状态丢失。
- **复现**：测试 `InMemoryKVStoreDualMapRaceTest` 构造「`exclusiveSet(key, old, 1s过期)` 紧接 `set(key, newVal)` + 并发 `get` 触发清理」场景。竞态非确定性，JDK 17 下需高压才偶发，但设计脆弱性由双 Map 非原子组合即可确证。
- **修复建议**：将过期信息与值合并为单一条目（如 `Map<String, Entry{value, expiryAt}>`），用 `ConcurrentHashMap.compute` 原子地完成「写值 + 清过期」/「判过期 + 删值」；或对每个 key 的 `set/get/cleanup` 用 `StripedKeyLocks`（本项目已有现成实现）串行化。

---

### 🟡 P2-2：EntityDef / RelationDef 静态 LinkedHashMap + 无锁 registerDescription

> **修复状态：✅ 已修复** — `ENTITY_DEFINITION_DESCRIPTION` / `RELATION_DEFINITION_DESCRIPTION` 均改 `ConcurrentHashMap`。回归测试：`EntityDefRelationDefRegistry.descriptionMapsAreConcurrent` / `concurrentRegisterDescriptionIsSafe`（8 线程 × 1000 次并发注册不抛异常且值可见）。

- **文件**：
  - `src/main/java/com/openjiuwen/core/memory/graph/extraction/EntityDef.java` 第 19 行 `ENTITY_DEFINITION_DESCRIPTION = new LinkedHashMap<>()`
  - `src/main/java/com/openjiuwen/core/memory/graph/extraction/RelationDef.java` 第 19 行 `RELATION_DEFINITION_DESCRIPTION = new LinkedHashMap<>()`（同模式）
- **访问点**：`registerDescription(language, description)`（`public static`，无锁 `put`，第 38–40 行）；实例字段 `description = ENTITY_DEFINITION_DESCRIPTION`（第 22 行）直接引用同一静态 Map，所有实例共享。
- **缺陷类型**：非线程安全集合 + 静态可变状态
- **并发场景**：若运行时通过 `registerDescription` 注册多语言描述（如多 agent 并发初始化图记忆抽取器），`LinkedHashMap.put` 与并发读取（通过实例 `description` 字段）会竞态。
- **影响**：与 P0-3 同型——`LinkedHashMap` 并发读写可能抛 CME 或结构损坏。实际危害取决于是否有运行时并发注册（若仅静态初始化则安全，但 `registerDescription` 暴露为 public 暗示支持运行时注册）。
- **修复建议**：改为 `ConcurrentHashMap`（或 `Map.copyOf` 不可变快照 + 替换引用）。

---

### 🟡 P2-3：LLMExecutableState.accumulatedContent StringBuilder 字段无同步

> **修复状态：✅ 已修复** — `accumulateContent` / `buildFinalResult` / `clear` 加 `synchronized`，保护 `StringBuilder` 复合操作原子性。回归测试：`LLMExecutableStateSync.methodsAreSynchronized` / `concurrentAccumulateContentIsLossless`（16 线程 × 1000 次并发 append 不丢失字符）。

- **文件**：`src/main/java/com/openjiuwen/core/workflow/component/llm/LLMExecutableState.java` 第 24 行 `private final StringBuilder accumulatedContent = new StringBuilder();`
- **访问点**：`accumulateContent()` 第 33 行、`buildFinalResult()` 第 48 行、`clear()` 第 58 行——均无 `synchronized`
- **缺陷类型**：非线程安全可变对象（`StringBuilder`）
- **并发场景**：`LLMExecutable.state` 是实例字段，若同一 `LLMExecutable` 组件被 workflow 引擎并发调度（stream + invoke 同时推进，或多路复用同一组件实例），`StringBuilder.append` 非线程安全会丢字符或抛 `ArrayIndexOutOfBoundsException`。
- **影响评估**：**中**——取决于 workflow 引擎是否对同一组件实例并发调度。若引擎保证单组件单线程消费则安全；但源码未见显式保证。同类流式 parser 的 `StringBuilder` buffer（`MarkdownOutputParser / JsonOutputParser / OpenAiCompatibleModelClient / InferenceAffinityModelClient / LLMCall.LegacyStream`）均为「每次调用新建 iterator/实例、单线程消费」模式，风险低；唯独 `LLMExecutableState` 是**组件实例级**字段、生命周期跨多次调用，风险较高。
- **修复建议**：`accumulatedContent` 改为 `StringBuffer`（线程安全但性能差），或对 `accumulateContent / buildFinalResult / clear` 加 `synchronized`；或确认引擎调度模型后在文档中标注「单线程消费契约」。

---

### 🟠 P2-4：SystemPromptBuilder 暴露内部可变状态给多组件（升级修正）

> **修复状态：✅ 已修复（此前已修复）** — `addSection` / `removeSection` / `build` / `getAllSections` / `hasSection` / `getSection` 均已声明 `synchronized`，保护内部 `LinkedHashMap`。回归测试：`SystemPromptBuilderSync.methodsAreSynchronized` / `concurrentMutateAndBuildNoCme`（8 线程并发 addSection/removeSection/build 不抛 CME）。

> **修正说明**：首轮报告将该类归入「未单独分析」的盲区，经调用链追踪后**升级为中-高风险**。这是用户明确指出的遗漏点，也是首轮方法缺陷的典型样本。

- **文件**：`src/main/java/com/openjiuwen/core/singleagent/prompts/SystemPromptBuilder.java`
- **位置**：第 43 行 `private final Map<String, PromptSection> sections = new LinkedHashMap<String, PromptSection>();`；`addSection`（90–95）、`removeSection`（104–109）、`build`（149–161，`new ArrayList<>(sections.values())` + `sort`）、`getAllSections`（117–119）、`hasSection`（128–130）、`getSection`（139–141）——**全部无 `synchronized`，字段非 `volatile`**
- **缺陷类型**：非线程安全集合 + 内部可变状态外泄
- **调用链证据（追调用链确证）**：
  - `ReActAgent.promptBuilder` 是实例字段（`ReActAgent.java:88`），构造于第 102/255 行。
  - `ReActAgent.getSystemPromptBuilder()`（第 209 行）**直接返回内部 builder 引用**，暴露给外部组件。
  - `TeamMemoryManager.loadAndInject()`（`TeamMemoryManager.java:198-201`）拿到引用后做 `removeSection` + `addSection`（**复合操作**）。
  - `TeamMemoryManager.close()`（第 245 行）`removeSection`。
  - `AutoHarnessExperienceRail.beforeModelCall()`（`AutoHarnessExperienceRail.java:127-133`）在**每次 LLM 调用前**对同一 builder 做 `removeSection` + `addSection`（写）。
  - `ReActAgent` 主循环（第 749-751、1335-1337 行）每轮 `promptBuilder.build()`（读 + 遍历 + `sort`）。
- **缺陷说明**：首轮我假设「builder 一般单线程用、串行 add 后 build 即安全」——**这个假设对该类不成立**。`getSystemPromptBuilder()` 把内部 `LinkedHashMap` 的引用通过 builder 接口散播给至少 3 个外部组件，它们在不同回调时机（`beforeModelCall`、`loadAndInject`、`close`）写 builder，而 `ReActAgent` 主循环并发读。当同一 agent 实例被多线程驱动（leader/teammate 共享、并发 invoke、或 rail 回调与 build 在不同线程），`LinkedHashMap` 的 `put/remove` 与 `entrySet/values` 遍历并发 → `ConcurrentModificationException` 或内部哈希链损坏。即便单线程，跨组件共享可变状态、依赖隐式调用顺序也是脆弱设计。
- **风险定级**：**中-高**（取决于 agent 是否被多线程驱动；设计缺陷客观存在——内部可变状态外泄 + 无任何同步）。
- **修复建议**：
  - `sections` 改为 `new ConcurrentHashMap<>()`（弱一致迭代器不抛 CME）。
  - 或 `addSection/removeSection/build` 加 `synchronized`。
  - 更彻底：`getSystemPromptBuilder()` 返回**不可变视图**或快照，禁止外部组件直接 mutate；外部组件改用 `setSystemPromptBuilder(builder)` 注入式 API。
- **首轮为何漏（见第七节反思）**：字段类型正则漏了 `LinkedHashMap`；实例字段非并发容器的「调用模式依赖」判定被错误地简化为「一律安全」。

---

### 🟡 P2-5：WorkflowSpec 边表/组件表 HashMap 在运行期被读写（调用模式依赖）

> **修复状态：✅ 已修复** — `edges` / `streamEdges` / `compConfigs` 均改 `ConcurrentHashMap`。回归测试：`WorkflowSpecConcurrentFields.fieldsAreConcurrentMaps`。

- **文件**：`src/main/java/com/openjiuwen/core/workflow/WorkflowSpec.java`
- **位置**：`edges`（24，`HashMap`）、`streamEdges`（31，`HashMap`）、`compConfigs`（48，`HashMap`）、`startNodes`（55，`ArrayList`）
- **调用链证据**：
  - 写：`BaseWorkflow.addConnection`（`BaseWorkflow.java:199,205`）`getEdges().computeIfAbsent(...).add(...)`；`addStreamConnection`（230）同型；`BaseWorkflow.java:139` `getCompConfigs().put(...)`。
  - 读/遍历：`BaseWorkflow.java:415` `getCompConfigs().entrySet()`；`525` `keySet()`；`NodeSession.java:294,299` `getCompConfigs().get(nodeId)`；`LoopGroup.java:482` `getStreamEdges()`。
- **缺陷类型**：非线程安全集合 + check-then-act（`computeIfAbsent` + `add`）
- **缺陷说明**：`WorkflowSpec` 表面是配置 DTO，但 `BaseWorkflow.addConnection/addStreamConnection` 是 public、返回 `this`（builder 风格），且 `getEdges()` 等直接返回内部 Map 引用（非快照/不可变视图）。若 workflow **构建期（addConnection）与执行期（NodeSession 遍历 compConfigs）并发**——例如热更新边、动态子图、或构建未完成即 execute——则 HashMap 的 `computeIfAbsent.add` 与 `entrySet` 遍历并发会 CME。典型用法（先 build 完再 execute，串行）下安全。
- **风险定级**：**中**（调用模式依赖；需运行期动态加边才触发，但 `getEdges()` 返回内部引用的设计使该风险无法在类型层面排除）。
- **修复建议**：`getEdges/getStreamEdges/getCompConfigs` 返回 `Collections.unmodifiableMap` 或快照；或 fields 改 `ConcurrentHashMap`（注意 `computeIfAbsent + add` 仍需保证 List 本身并发安全，建议 `CopyOnWriteArrayList` 或 `synchronizedList`）。

---

### 🟢 P2-6：BaseRegistry check-then-act + keySet 引用外泄（低风险/设计脆弱）

> **修复状态：✅ 已修复** — `items` 改 `ConcurrentHashMap`；`register` 用 `putIfAbsent` 原子化 check-then-act；`names()` 返回 `Collections.unmodifiableSet` 防止外部修改。回归测试：`BaseRegistryAtomicity.itemsIsConcurrentAndNamesUnmodifiable` / `concurrentRegisterSameNameOnlyOneSucceeds`（16 线程并发注册同名仅一个成功）。

- **文件**：`src/main/java/com/openjiuwen/autoharness/registry/BaseRegistry.java`
- **位置**：第 22 行 `protected final Map<String, T> items = new LinkedHashMap<>()`；`register`（31-36）`if (items.containsKey(name)) throw; items.put(name, spec);`；`names()`（70-72）`return items.keySet();`
- **子类**：`StageRegistry`、`PipelineRegistry`（均 `extends BaseRegistry`）
- **调用链证据**：`register` 仅在 `BuiltinRegistries`（启动初始化）调用；运行期只 `require`/`names`（读）。当前**安全**（初始化后冻结）。
- **缺陷类型**：非线程安全集合 + check-then-act + 引用外泄（`names()` 返回内部 `keySet`）
- **风险定级**：**低**（当前安全，但基类设计支持运行期注册——一旦子类在运行期被并发 `register`，`containsKey + put` 复合操作会漏检重复注册，`keySet` 外泄导致 CME）。
- **修复建议**：`items` 改 `ConcurrentHashMap`；`register` 用 `putIfAbsent` 原子化（`if (items.putIfAbsent(name, spec) != null) throw`）；`names()` 返回 `Set.copyOf(items.keySet())` 或 `Collections.unmodifiableSet`。

---

### 🟢 P2-7：LSPServerManager 多 LinkedHashMap/HashSet 字段（低风险/第三轮新增）

> **修复状态：✅ 已修复** — `configs` / `instances` / `spawning` / `extensionMap` / `docVersions` 均改 `ConcurrentHashMap`；`diagHandlerInstances` 改 `ConcurrentHashMap.newKeySet()`；`ensureDiagnosticHandler` 的 `contains` + `add` check-then-act 改 `add` 返回值原子化。回归测试：`LSPServerManagerFields.fieldsAreConcurrentCollections`。

- **文件**：`src/main/java/com/openjiuwen/harness/lsp/core/LSPServerManager.java`
- **位置**：`configs`(23) / `instances`(30) / `spawning`(37) / `extensionMap`(44)（均 `LinkedHashMap`）、`docVersions`(59) `LinkedHashMap`、`diagHandlerInstances`(52) `HashSet`——**6 个非并发集合字段，全部方法无 `synchronized`**
- **访问点**：`openFile`(237)/`changeFile`(270,271) 写 `docVersions`；`registerServer`(122)/`hasServer`(133)/`getOrStartServer`(111) 读写 `instances`；`shutdownServer`(165,166,170) `remove`+`containsValue`；`shutdownAll`(184,194-197) 遍历 `instances.values()` + `clear` 全部
- **缺陷类型**：非线程安全集合 + fail-fast 遍历与并发修改冲突
- **共享面**：`LSPServerManager` 由 `LspRail`（第 48 行 `new LSPServerManager()`）持有，暴露给 `LspTool`。`openFile/changeFile/request` 由 agent 主线程调；`ensureDiagnosticHandler` 注册的 `Consumer` 在 **LSP server 自身线程**触发（但只调 `LspDiagnosticRegistry.register`，不碰 manager 的 map）。真正的并发风险在 `shutdownAll`（遍历 `instances.values()` + `clear` 全部 map）与主线程的 `openFile/changeFile`（写 `docVersions`/`instances`）并发 → CME。
- **风险定级**：**低**。`shutdownAll`/`shutdownServer` 通常在 `LspRail.uninit`（agent 结束）调用，此时主线程不再调 `openFile`；正常生命周期下无并发。但类型层面无保护，若 agent 关闭与工具调用并发（如超时强制关闭），6 个非并发集合可 CME/结构损坏。`diagHandlerInstances` 的 `contains`+`add`（78,81 行）也是 check-then-act。
- **修复建议**：`instances`/`docVersions`/`configs`/`spawning`/`extensionMap` 改 `ConcurrentHashMap`，`diagHandlerInstances` 改 `ConcurrentHashMap.newKeySet()`；或所有 public 方法加 `synchronized`（LSP 调用频率低，锁开销可忽略）。

---

### 🟢 已排查并确认安全的同型模式（对照）

为避免误报，下列候选经阅读源码后**确认安全**，列出以供对照：

| 候选 | 文件:行 | 为何安全 |
|---|---|---|
| DCL 单例 `instance` 字段 | `TaskManager:42`、`UserConfig:32`、`PathChecker:20`、`LongTermMemory:99`、`ParserRegistry:26`、`PromptApplier:30`、`TemplateManager:33`、`ServiceContext:22` | 均声明 `volatile`，DCL 正确 |
| `SingletonSupport.INSTANCES` | `SingletonSupport:26` | `ConcurrentHashMap` + `synchronized(SingletonSupport.class)` 双保险 |
| SPI 工厂静态 REGISTRY | `VectorStoreFactory / KVStoreFactory / ObjectStorageFactory / CheckpointerFactory / SessionStoreFactory / WorkspaceStoreFactory / McpClientFactory / RemoteClientFactory / TodoStorageFactory / ToolMetadataRegistry / TracerHandlerRegistry / HarnessConfigBuilder / HarnessConfigRegistry / ProgressRegistry / LogManager` | 均为 `ConcurrentHashMap` |
| `SharedResources.DB_INSTANCES`（LinkedHashMap） | `SharedResources:39` | 所有 `get/clear/computeIfAbsent` 在 `synchronized(LOCK)` 内 |
| `TeamBackend.SHARED_DB_INSTANCES`（LinkedHashMap） + `sharedMemoryDb` | `TeamBackend:60-61` | `getSharedDb / resetSharedDbCache` 均为 `synchronized`（静态方法锁 class） |
| `Config.ENV_CONFIG_TYPES`（HashMap） | `Config:39` | 仅 `static{}` 块写入，运行时只读（第 264 行 `get`），属「初始化后冻结」 |
| `TeamDatabase.teams/members/sessions` | `TeamDatabase:48-50` | 已改 `ConcurrentHashMap`（X.CON.05 整改） |
| `CallbackMetrics` 计数器 | `CallbackMetrics` | `update()` 为 `synchronized` |
| `TemplateProcessor.chunkIndex` | `TemplateProcessor:55` | `ReentrantLock + Condition` 保护 |
| 流式 parser 的 `StringBuilder` buffer | `MarkdownOutputParser / JsonOutputParser / OpenAiCompatible / InferenceAffinity / LLMCall.LegacyStream` | 每次 `streamParse/stream` 新建 iterator/实例，单线程消费 |
| `KeyLockedStore` | `KeyLockedStore` | striped `ReentrantLock`（基于 `StripedKeyLocks`） |
| `OpenJiuwenExecutors.MANAGED_EXECUTORS` | `OpenJiuwenExecutors:54` | `ConcurrentHashMap.newKeySet()` |
| `AutoHarnessOrchestrator.taskContexts`（LinkedHashMap） | `AutoHarnessOrchestrator:75` | 追调用链确证：`MetaEvolvePipeline:149` 串行 for 循环 + `runIsolatedStream` 单线程池（`poolSize 1,1`）+ `future.get` 阻塞主线程，同一时刻仅一个 task 线程 touch |
| `BaseRegistry.items`（LinkedHashMap，当前） | `BaseRegistry:22` | `register` 仅 `BuiltinRegistries` 启动期调，运行期只读（初始化后冻结）；设计脆弱见 P2-6 |
| `TaskManager.tasks` 等 5 个 HashMap | `TaskManager:39,46,53,60,67` | 所有 public 方法（`addTask/getTask/popTask/updateTask/loadState/clearState/getState`）均在 `ReentrantLock` 内（第三轮核实，锁覆盖完整） |
| `InProcessMessager.topicSubs/p2p`（LinkedHashMap） | `InProcessMessager:39,46` | `Bus` 所有方法 `synchronized`（subscribe/unsubscribe/topicHandlers/registerP2p 等）；`subscribedTopics`(ArrayList,36) 为实例级、单 agent 内访问 |
| `OtelSpanContext.TOOL_SPAN_MAP` | `OtelSpanContext` | `ThreadLocal`，线程本地无竞争 |
| `InMemoryCheckpointer.agentStores/workflowStores/sessionToWorkflowIds` | `InMemoryCheckpointer:39,41,43` | 全 `ConcurrentHashMap` + `KeyLockedStore`（striped lock）；`InMemoryAgentStorage/InMemoryWorkflowStorage.stateBlobs` 也 `ConcurrentHashMap` |
| `ArtifactStore.session/task`（LinkedHashMap） | `ArtifactStore:16,23` | 由 `AutoHarnessOrchestrator` 持有，随其串行执行模型（MetaEvolvePipeline 串行+单线程池）；`task` 用 `computeIfAbsent` 但底层非并发 map，串行下安全 |

---

## 三、问题汇总表

| 序号 | 风险 | 文件 | 缺陷 | 类型 | 可复现 |
|---|---|---|---|---|---|
| P0-1 | 🔴 高 | `ModelAllocators.java:130,159,209,239` | 轮询分配器 `index` 非原子 + `innerIndexes` LinkedHashMap | 非原子计数器 + 非并发集合 | ✅ 实测 lostUpdate=53882/80000 |
| P0-2 | 🔴 高 | `TeamDatabase.java:52` | `droppedSessionIds` 为 HashSet（同类三 Map 已改、漏此） | 非并发集合 | ⚠️ 静默损坏（设计对比确证） |
| P0-3 | 🔴 高 | `Model.java:81,97,189` | `FACTORY_REGISTRY` 静态 LinkedHashMap + 无锁 registerFactory | 非并发集合 | ✅ 实测抛 ConcurrentModificationException |
| P0-4 | 🔴 高 | `ContextEngine.java:57,64,96,154,255,319` | `contextPool` 实例 HashMap 无锁 check-then-act + entrySet 遍历；静态处理器注册表同 P0-3 | 非并发集合 + TOCTOU + fail-fast | ✅ 实测 CME 331~1929/80000 + 反射坐实类型 |
| P1-1 | 🟠 中高 | `Vertex.java:79,80,244,951,1052` | `callCount/streamCallCount` 非原子，`isDone()` 依赖 | 非原子计数器 | ⚠️ 同型已实测（P0-1） |
| P1-2 | 🟠 中高 | `LspDiagnosticRegistry.java:18,41,50` | `instance` 非 volatile + `reset/getInstance` 无锁 | 不安全发布 | ✅ 反射断言字段无 volatile |
| P2-1 | 🟡 中 | `InMemoryKVStore.java:22,29,40,54,222` | `values` 与 `expiryAt` 双 Map 复合操作 | TOCTOU | ⚠️ 非确定性 |
| P2-2 | 🟡 中 | `EntityDef.java:19,38` / `RelationDef.java:19` | 静态 LinkedHashMap + 无锁 registerDescription | 非并发集合 | ⚠️ 同 P0-3 型 |
| P2-3 | 🟡 中 | `LLMExecutableState.java:24,33` | `accumulatedContent` StringBuilder 字段无同步 | 非线程安全可变对象 | ⚠️ 取决于调度模型 |
| P2-4 | 🟠 中高 | `SystemPromptBuilder.java:43,90,149` | `sections` LinkedHashMap + `getSystemPromptBuilder()` 暴露内部引用给多组件并发读写 | 非并发集合 + 状态外泄 | ⚠️ 调用链确证多组件写、build 读 |
| P2-5 | 🟡 中 | `WorkflowSpec.java:24,31,48` | `edges/streamEdges/compConfigs` HashMap，运行期 `addConnection` 写 + `NodeSession` 遍历读 | 非并发集合 | ⚠️ 调用模式依赖（需运行期动态加边） |
| P2-6 | 🟢 低 | `BaseRegistry.java:22,31,70` | `items` LinkedHashMap + check-then-act `register` + `names()` 返回 keySet 引用 | 非并发集合 + 引用外泄 | 当前安全（启动期注册）；设计脆弱 |
| P1-3 | 🟠 中 | `TaskLoopController.java:450,73,167` / `LoopQueues.java:21,35,36,113` | `SessionState.roundCounter` 非原子 + `LoopQueues` ArrayDeque/PriorityQueue 非并发，`++sequence`；`enqueueSteering` 可跨线程入队 | 非原子计数器 + 非并发集合 | ✅ 实测 ++sequence 丢失更新 765/40000 |
| P2-7 | 🟢 低 | `LSPServerManager.java:23,30,37,44,52,59` | 6 个非并发集合字段无 synchronized，`shutdownAll` 遍历+clear 与 `openFile/changeFile` 并发可 CME | 非并发集合 + fail-fast | ⚠️ 生命周期通常串行；类型层无保护 |

---

## 四、修复优先级与最小改动建议

1. **立即修复（P0，一行级改动）**：
   - `TeamDatabase.droppedSessionIds` → `ConcurrentHashMap.newKeySet()`（P0-2）
   - `Model.FACTORY_REGISTRY` → `new ConcurrentHashMap<>()`，遍历改 `forEach`（P0-3）
   - `ModelAllocators.RoundRobinModelAllocator.index` → `AtomicInteger`，`allocate` 用 `getAndIncrement()`（P0-1）
   - `ModelAllocators.ByModelNameAllocator.innerIndexes` → `ConcurrentHashMap<String, AtomicInteger>`（P0-1）
   - `ContextEngine.contextPool` → `new ConcurrentHashMap<>()`，`createContext` 改 `computeIfAbsent` 原子化 check-then-act，`clearContextBySession` 改 `entrySet().removeIf(...)`；静态 `PROCESSOR_FACTORY_MAP`/`PROCESSOR_CLASS_MAP` 同步改 `ConcurrentHashMap`（P0-4）

2. **短期修复（P1）**：
   - `LspDiagnosticRegistry.instance` → 声明 `volatile`（P1-2）
   - `Vertex.callCount / streamCallCount / logMessage` → `AtomicInteger` / `ConcurrentHashMap`（P1-1）
   - `TaskLoopController.SessionState` 内字段加 `synchronized` 或 `AtomicInteger`/`volatile`；`LoopQueues` 队列改 `ConcurrentLinkedQueue`/`PriorityBlockingQueue`，`sequence` 改 `AtomicLong`（P1-3）

3. **评估后修复（P2）**：
   - `InMemoryKVStore` 双 Map → 合并为单条目 `compute` 或 striped lock（P2-1）
   - `EntityDef / RelationDef.ENTITY_DEFINITION_DESCRIPTION` → `ConcurrentHashMap`（P2-2）
   - `LLMExecutableState.accumulatedContent` → 加 `synchronized` 或确认单线程契约（P2-3）
   - `SystemPromptBuilder.sections` → `ConcurrentHashMap` 或加 `synchronized`；`getSystemPromptBuilder()` 改返回不可变视图/快照（P2-4）
   - `WorkflowSpec` 的 getter 返回不可变视图/快照，或 fields 改 `ConcurrentHashMap` + `CopyOnWriteArrayList`（P2-5）
   - `BaseRegistry.items` → `ConcurrentHashMap`；`register` 用 `putIfAbsent` 原子化；`names()` 返回快照（P2-6，低优先）
   - `LSPServerManager` 的 6 个非并发集合改 `ConcurrentHashMap`/`newKeySet()`，或 public 方法加 `synchronized`（P2-7，低优先）

---

## 五、验证测试说明

- **测试文件**：`agent-core-java/src/test/java/com/openjiuwen/core/common/concurrent/ThreadSafetyConcurrencyAnalysisTest.java`
- **测试框架**：JUnit 5（`@Nested / @DisplayName`），与项目现有测试风格一致（参考 `ModelClientConfigTest`）。
- **运行方式**：`mvn -Dtest=ThreadSafetyConcurrencyAnalysisTest -DfailIfNoTests=false test`
- **测试结果**：9 个用例全部通过（编译 + 运行），BUILD SUCCESS。
- **关于「测试通过」的说明**：并发缺陷的测试设计目标不是「稳定 fail」（那会让 CI 误报），而是「**可执行 + 留下缺陷证据**」。本测试集通过以下方式留下证据：
  - `RoundRobin` 用例：`System.out` 打印 `index=26118 expected=80000 lostUpdate=53882`（丢失更新 67%）。
  - `Model.FACTORY_REGISTRY` 用例：打印 `traversalError=java.util.ConcurrentModificationException`。
  - `LspDiagnosticRegistry` 用例：反射断言 `instance` 字段**不含 `volatile`**、`getInstance` **不含 `synchronized`**——**确定性**确证设计缺陷。
  - `ContextEngine.contextPool` 用例：反射断言字段类型为 `HashMap` 且**非** `ConcurrentHashMap`（确定性证据）；并发压测打印 `ConcurrentModificationException 次数: 331~1929/80000`（多次运行计数非确定，正说明竞态真实存在）。
  - `LoopQueues` 用例：反射断言 `sequence` 非 `AtomicLong`/非 `volatile`、`steering` 为 `ArrayDeque`；纯写写并发压测打印 `pushEvent 调用数=40000 distinct sequence=39235`（`++sequence` 丢失更新 765 次，约 1.9%）。
  - `TeamDatabase / InMemoryKVStore` 用例：并发压测不抛异常即「通过」，但缺陷由源码对比（同类已修、此处漏修）与设计分析确证。

修复后，P0-1/P0-3/P1-2 的对应用例应改为「严格断言不再复现」（如 `assert lostUpdate == 0`、`assert traversalError == null`、`assert isVolatile(mods)`），作为回归保护。

---

## 六、附：本次扫描未覆盖的区域（建议后续补充）

- `core/runner/resourcemanager/ResourceMgr`（类较大，`ThreadSafeDict / TagMgr` 的 `!containsKey` check-then-act 需确认是否在锁内）。
- `core/workflow/component/End.java` 匿名 Iterator 的 `chunkIndex`（待确认是否被多线程拉取）。
- `harness/task_loop/TaskLoopController` 的 `state.roundCounter`（待确认 SessionState 同步）。
- 多租户目录（`cp_tenant / full_chain_tenant / tenant_a / tenant_b / tenants`）下的并发代码。
- `core/session/checkpointer` 各后端实现（SQLite/Redis/PG）在并发 checkpoint 下的正确性。

这些区域在本次快速扫描中未深入，建议作为后续分析的输入。

---

## 七、方法反思与补扫（第二轮）

> 第一轮报告交付后，用户指出 `core/singleagent/prompts/SystemPromptBuilder.java` 是线程不安全的、但首轮未扫到。该指正成立。本节复盘方法论缺陷，记录补扫过程与修正结论。

### 7.1 首轮方法论的三层缺陷

1. **字段类型正则有结构性漏网**：首轮 grep 用 `HashMap|ArrayList|HashSet|LinkedList|ArrayDeque` 匹配字段类型——**漏了 `LinkedHashMap`**（而 `SystemPromptBuilder.sections` 正是 `LinkedHashMap`）。首轮命中的 `LinkedHashMap` 字段（`TeamBackend:61`、`SharedResources:39`、`Model:81`）是靠另一条「`static ... Map<...> = new ...`」正则顺带捞到的，不是靠字段类型正则。`SystemPromptBuilder` 的 `sections` 是**实例字段 + 接口声明（`Map<String,PromptSection>`）+ 构造为 `LinkedHashMap`**，恰好落在两条正则的盲区。

2. **对「实例字段的非并发容器」判定过激**：首轮隐含标准是「实例字段的非并发容器，单线程用就安全」——对 builder 类直接放过。这个标准把「是否被多线程共享」的判定**推给了未做的后续**，等于跳过了。`SystemPromptBuilder` 正是被这条假设误判：它**不是单线程用**——`getSystemPromptBuilder()` 把内部引用暴露给 `TeamMemoryManager`/`AutoHarnessExperienceRail` 等多组件。

3. **只判「容器并发性」，未追「调用链/共享性」**：首轮对 `Vertex.callCount`、`LLMExecutableState` 等「弱证据」发现也暴露了同病——依赖注释和领域推理下结论，没追调用链。这是首轮最大的方法论短板。

### 7.2 补扫方法优化

第二轮针对上述修正，四步：

1. **扩大字段类型正则**：改为「`Map|List|Set|Queue|Deque` 接口声明 + `LinkedHashMap|HashMap|TreeMap|TreeSet|PriorityQueue|Vector|Hashtable|LinkedHashSet` 具体非并发实现」，实例字段与静态字段都扫，不限 `final`。一次性捞出 150 条命中（含大量局部变量，需字段级过滤）。
2. **字段级过滤**：从命中里筛出缩进为 0 的字段声明（`private ... field = new ...`），排除方法内局部变量。筛出 `AutoHarnessOrchestrator.taskContexts`、`BaseRegistry.items`、`WorkflowSpec.edges/streamEdges/compConfigs`、`ArtifactStore.session/task`、`EditSafetyRail.editedFiles`、`Trajectory.meta`、`WorkflowSpec` 等新候选。
3. **追调用链确证「是否被多线程共享」**：对每个字段级命中，grep 其 `put/get/remove` 调用方、跨文件调用、是否在 `parallelStream`/多线程池/单线程池/串行 for 循环。**判定标准从「类型层是否安全」升级为「调用链层是否并发」**。
4. **补扫漏掉反模式**：`computeIfAbsent + 副作用`、`synchronized` 锁不一致（部分方法加锁部分不加）、`CompletableFuture` 回调 + 共享状态。

### 7.3 补扫结果

| 候选 | 追调用链结论 | 处置 |
|---|---|---|
| `SystemPromptBuilder.sections` | `getSystemPromptBuilder()` 暴露内部引用给 `TeamMemoryManager.loadAndInject`（remove+add）、`AutoHarnessExperienceRail.beforeModelCall`（remove+add）、`close`（remove）；`ReActAgent` 主循环 `build()`（读遍历）。多组件跨类共享 + 不同回调时机读写 | **升级为 P2-4 中-高** |
| `WorkflowSpec.edges/streamEdges/compConfigs` | `BaseWorkflow.addConnection` 运行期 `computeIfAbsent.add`（写），`NodeSession/BaseWorkflow` 运行期 `entrySet/keySet/get`（读）；getter 返回内部引用非快照 | **新增 P2-5 中**（调用模式依赖） |
| `BaseRegistry.items` | `register` 仅 `BuiltinRegistries` 启动期调，运行期只读；但 check-then-act + `names()` 返回 keySet 引用 | **新增 P2-6 低**（当前安全，设计脆弱） |
| `AutoHarnessOrchestrator.taskContexts` | `MetaEvolvePipeline:149` 串行 for + `runIsolatedStream` 单线程池 `poolSize(1,1)` + `future.get` 阻塞主线程，同一时刻仅一个 task 线程 touch | **排除（安全）**，记入对照表 |
| `ArtifactStore.session/task`、`EditSafetyRail.editedFiles`、`Trajectory.meta` | 待进一步追调用链（本轮未深入） | 标记为后续输入 |

### 7.4 仍未覆盖的盲区（诚实交代）

- **`ContextEngine`（P0-4）在前两轮均漏扫——这是本轮（第三轮，由用户点名 `fork` 版 `ContextEngine.java` 触发）才补回的重大遗漏**。漏扫根因有三层，与首轮漏 `SystemPromptBuilder` 同源：
  1. **第一轮字段类型正则盲区**：`contextPool`（96 行）声明为 `private final Map<String, ModelContext> contextPool = new HashMap<>()`，`Map<...>` 是接口声明、类名 `HashMap` 只在右侧 `new` 表达式出现。首轮针对「字段类型列」匹配的正则（`HashMap|ArrayList|HashSet|...`）在**声明行左侧**找不到类名，故 0 命中。与 `SystemPromptBuilder.sections`（接口声明 + `LinkedHashMap`）是同一个漏网机制。
  2. **第二轮宽口径 grep 被分页截断**：7.2 第 1 步把正则放宽到「`= new (LinkedHashMap|HashMap|...)`」后，`ContextEngine.java:57/64/96` 三行**本应被命中**（实测 `core/context` 目录下确有这三行 `new LinkedHashMap/HashMap`）。但该轮 grep 结果被 `head_limit=150` 分页，ContextEngine 落在了**未读取的尾部**（当时结果文件末尾止于 `WorkflowSpec.java`），即「命中了但没看到」。
  3. **从未对 `core/context` 包做目录级枚举**：前两轮都靠「全仓 grep + 字段级过滤」捞候选，没有对任何具体包做穷举式目录扫描。`core/context` 是会话上下文中枢、单实例被多 Controller 共享——本应作为高优包单独过一遍，实际却从未被显式枚举。这与 `core/singleagent/prompts`（首轮也没单独枚举、漏了 `SystemPromptBuilder`）是同一种结构性盲区：**按反模式 grep 驱动而非按子系统驱动**。
  - **修正**：本轮已补回 P0-4，并附 `ContextEngineContextPoolRaceTest` 实测证据（CME 331~1929/80000）。这进一步坐实 7.5 的结论——必须把「按子系统逐包枚举」补进扫描流程，而非只靠 grep 捞。
- **未跑 `jcstress`**：可见性/重排序类缺陷（如 P1-2 LspDiagnosticRegistry 的不安全发布）JUnit 压测复现能力弱，需 `jcstress` 才能可靠判定。
- **未用静态分析工具**：SpotBugs/ErrorProne/PMD 的并发检测器没跑，可能遗漏人眼 grep 抓不到的模式（如 `synchronized` 锁不同 monitor 的死锁、`wait/notify` 守卫条件错）。
- **`CompletableFuture` 回调线程不确定性 + 共享状态**：本库大量用 `CompletableFuture.supplyAsync` + 共享可变状态（如 `Vertex.streamDone`、`TaskManager` 的 Future map），本轮未系统分析回调线程与主线程的 happens-before。
- **`computeIfAbsent` 里阻塞 lambda / 副作用**：首轮 grep 未命中（正则可能写错），本轮补扫也未深入，需单独一轮。
- **多租户目录、checkpointer 后端、`ResourceMgr`/`TagMgr`/`ThreadSafeDict` 的 check-then-act**：仍未追。

### 7.4.1 第三轮全项目重扫（双驱动法）

> 用户要求「整个项目重新扫描分析，看是否还有疏漏」。本轮用第一章收敛的「双驱动四步法」——反模式 grep（全量、不截断、覆盖接口+实现两侧）+ 按子系统逐包枚举——对全仓重扫，字段级命中 **264 条**（第二轮被 150 分页截断的尾部全部可见）。

**新增缺陷**：
| 候选 | 追调用链结论 | 处置 |
|---|---|---|
| `TaskLoopController.SessionState.roundCounter` + `LoopQueues.steering/events/sequence` | `enqueueSteering` 由 `DeepAgent`(主循环) 与 `TaskLoopEventHandler`(事件回调) 调用，可跨线程入队；`sessionStates` 虽 `ConcurrentHashMap` 但 `SessionState` 内字段无锁，`LoopQueues` 全非并发集合。实测三重证据 | **新增 P1-3 中** |
| `LSPServerManager` 6 个非并发集合字段 | 单 agent 主线程调，`shutdownAll` 与 `openFile` 理论可并发但生命周期通常串行 | **新增 P2-7 低** |
| `Vertex.logMessage`(HashMap) | 与 P1-1 同类，`initLog` 在 call/streamCall 路径无锁 | 并入 **P1-1 补充** |

**新增排除（对照表已补）**：
| 候选 | 为何安全 |
|---|---|
| `TaskManager` 5 个 HashMap | 所有 public 方法在 `ReentrantLock` 内，**锁覆盖完整**（第三轮逐一核实 addTask/getTask/popTask/updateTask/loadState/clearState/getState） |
| `InProcessMessager.topicSubs/p2p`(LinkedHashMap) | `Bus` 所有方法 `synchronized` |
| `OtelSpanContext.TOOL_SPAN_MAP` | `ThreadLocal` |
| `InMemoryCheckpointer` 三个 map | 全 `ConcurrentHashMap` + `KeyLockedStore` |
| `ArtifactStore.session/task`(LinkedHashMap) | 随 `AutoHarnessOrchestrator` 串行执行模型 |
| `LlmEventHandler.iteration/index/count` 等 `++` | 全为方法内局部变量（`int iteration = initialIteration`），非字段 |
| `Vertex.endStreamIndex`(696 `++`) | 方法内局部变量（`int endStreamIndex = 0`） |

**非原子计数器字段复核**：对全仓 `++`/`+= 1` 命中做字段级过滤，排除大量循环内局部变量（`pos++`/`i++`/`chunkIndex++`）。新字段级候选 `BudgetRail.iterationStarts/iterationCompletions`、`ObservabilityRail.turnCount`、`LlmSpanState.chunkCount`、`LoopQueues.sequence`、`SessionState.roundCounter`、`CompletionPromiseEvaluator.confirmationCount`、`SpawnedProcessHandle.consecutiveFailures`、`Playbook.nextId` 经追调用链，除 `LoopQueues.sequence`/`SessionState.roundCounter`（跨线程入队，P1-3）外，均在单 agent 串行主循环内访问，归低风险未单列（可作 P2 后续备查）。

**computeIfAbsent 副作用扫描**：全仓 39 个 `computeIfAbsent` 调用点，底层为非并发 map 的有 `TaskPlanningRail.usageRecords`(383)、`ArtifactStore.task`(72)、`Playbook.sections`(64)、`InProcessMessager.topicSubs`(49，但 Bus synchronized 保护)、`StreamProcessor.processorQueues/sourcePathMap`(352,157)、`TaskRegistry.groups`(41)。其中 InProcessMessager/TaskManager/InMemoryCheckpointer 已由 synchronized 或 ConcurrentHashMap 覆盖；`TaskPlanningRail.usageRecords` 经追调用链为单 agent 串行回调（低风险）；`StreamProcessor` 在 stream actor 并行框架内（与 P1-3 同域，未单列，后续备查）。

**结论**：本轮重扫在 264 条字段级命中里，补回 2 个真实缺陷（P1-3/P2-7）、1 个补充（P1-1 的 logMessage）、排除 7 类假阳性。**未发现新的 P0 级遗漏**——P0 全部在前两轮 + ContextEngine 已覆盖。仍存在的盲区见 7.4 未覆盖项。

### 7.5 方法论总结

首轮「反模式 grep + 定点读」的最大问题是**把「调用链/共享性」这一关键判定维度外包给了未做的后续**。第二轮把它拉回主线：grep 捞候选 → **追调用链判定并发性** → 才下结论。这把假阳性（`AutoHarnessOrchestrator.taskContexts`）排除、把假阴性（`SystemPromptBuilder`）补回。

第三轮把方法论正式收敛为「**双驱动四步法**」（见第一章 1.1），核心修正两点：
1. **反模式 grep 必须全量、覆盖接口声明 + 具体实现两侧、不截断分页**——首轮漏 `LinkedHashMap`、第二轮被 150 分页截断漏 `ContextEngine`，根因都是 grep 配置不足。第三轮 `head_limit=0` 全量捞 264 条字段级命中，前两轮的尾部全部可见。
2. **必须叠加「按子系统逐包枚举」作兜底**——grep 驱动只扫「记得要找的模式」，按子系统驱动才扫「该扫的地方」。`SystemPromptBuilder`（`singleagent/prompts`）与 `ContextEngine`（`core/context`）都是靠子系统枚举才补回的。

**但 grep + 人眼追调用链仍有上限**：对 1884 文件的全量调用图分析超出人眼与单轮 grep 能力。真正可靠的并发审计仍需 `jcstress` + 静态分析工具（SpotBugs/ThreadSanitizer 类）+ 运行时并发压测三件套。本报告列出的是「**高置信度的人眼可达缺陷**」，不等于「全部缺陷」。第三轮重扫后，**P0 级遗漏已清零**，残留的 P1/P2 均为调度依赖型或低风险设计脆弱点，详见 7.4 未覆盖项。
