# TaskManager.tasks HashMap 内存泄漏修复方案

> 日期：2026-07-09
> 模块：agent-core-java / controller / TaskManager
> 优先级：P0（生产环境长运行必定OOM）

---

## 1. 问题摘要

DeepAgent 单实例模式下长期运行，TaskManager.tasks HashMap 中的终态 Task（COMPLETED/FAILED/CANCELED）只增不删，导致内存持续增长直至 OOM。根因：缺少 TTL 过期清理、容量上限保护和自动 eviction 调度机制。

### 1.1 泄漏链路

```
请求 → DeepAgent.invoke() → TaskScheduler.scheduleTask() 
  → TaskManager.addTask() → tasks.put(taskId, task.copy())
  → Task 执行完成 → updateTaskStatus(COMPLETED)
  → ❌ Task 永久留在 tasks HashMap，无任何清理机制触发
```

### 1.2 影响的 5 个内部数据结构

| 结构 | 类型 | 清理逻辑 | 泄漏风险 |
|------|------|----------|---------|
| `tasks` | HashMap<String, Task> | 仅 removeTask()/clearState()（从未被调用） | **P0** |
| `priorityIndex` | HashMap<Integer, List<String>> | 随 tasks 联动 | P0 |
| `parentToChildren` | HashMap<String, Set<String>> | 随 tasks 联动 | P0 |
| `childToParent` | HashMap<String, String> | 随 tasks 联动 | P0 |
| `rootTasks` | HashSet<String> | 随 tasks 联动 | P0 |

---

## 2. 修复方案设计

### 2.1 设计原则

1. **向后兼容** — eviction 默认关闭（TTL=0），现有行为不受影响
2. **双保险** — TTL 过期 + 容量上限，任一触发即清理
3. **最小侵入** — 只修改 4 个文件，不改变 TaskManager 的核心 task 管理逻辑
4. **线程安全** — 所有 eviction 操作通过现有 ReentrantLock 保护
5. **优雅停止** — eviction scheduler 使用 daemon 线程，stopEvictionScheduler() 可安全关闭

### 2.2 修改文件清单

| 文件 | 修改内容 | 风险等级 |
|------|---------|---------|
| `Task.java` | 增加 `completedAt` 字段 + getter/setter + copy/toMap/fromMap | 低 |
| `TaskStatus.java` | 增加 `isTerminal()` 方法 | 低 |
| `ControllerConfig.java` | 增加 `evictionTtlSeconds` + `maxTaskCapacity` 配置 | 低 |
| `TaskManager.java` | 增加 eviction/scheduler/capacity 机制 | 中 |

### 2.3 核心机制详解

#### 机制 A：completedAt 时间戳

在 Task 进入终态时记录时间戳，作为 eviction 的判断依据。

```java
// Task.java 新增字段
private long completedAt;  // 默认 0，终态时设置为 System.currentTimeMillis()

// TaskManager.updateTaskStatus() 中新增
if (newStatus.isTerminal()) {
    task.setCompletedAt(System.currentTimeMillis());
}
```

#### 机制 B：TTL 过期清理

终态 Task 超过配置 TTL 后自动移除，同时清理所有关联索引。

```java
// TaskManager.evictCompletedTasks()
// 遍历 tasks，筛选：status.isTerminal() && completedAt > 0 
//   && (now - completedAt) > ttlSeconds * 1000
// 调用 removeTaskInternal() 清理 task + 索引
// 返回清理数量
```

- 默认 TTL = 3600（1小时后清理），安全默认值，防止内存泄漏和数据残留
- 可设为 0 关闭 eviction（不推荐长运行场景），用于需要长期保留历史 Task 的特殊情况
- 提供两版 API：
  - `evictCompletedTasks()` — 使用 config 中的 TTL（自动调度用）
  - `evictCompletedTasks(long ttlSeconds)` — 使用指定 TTL（手动/测试用）

#### 机制 C：容量上限保护

当 tasks.size() 超过 maxTaskCapacity 时，优先淘汰最早的终态 Task。

```java
// TaskManager.enforceMaxCapacity()
// 在 addTask() 之前调用
// overflow = tasks.size() - maxCapacity + 1
// 按 completedAt 升序排序终态 Task，淘汰最早的 overflow 个
// 如果没有终态 Task 可淘汰，则不限制（保护活跃 Task）
```

- 默认 maxTaskCapacity = 1000（最多保留1000个Task），防止内存无限增长
- 可设为 0 关闭容量限制（不推荐长运行场景）

#### 机制 D：定时 Eviction 调度器

自动周期性执行 TTL 清理，使用 ScheduledExecutorService。

```java
// TaskManager 构造时自动启动（当 evictionTtlSeconds > 0）
// daemon 线程 "task-eviction"，scheduleAtFixedRate
// 调度间隔 = evictionTtlSeconds（与 TTL 相同）
// 异常捕获：仅日志记录，不中断调度
// setConfig() 时自动重启 scheduler
// stopEvictionScheduler() 可安全关闭
```

---

## 3. 修改点详细清单

### 3.1 Task.java

| 位置 | 修改 |
|------|------|
| 字段声明区 | 增加 `private long completedAt;` |
| 构造方法 | 增加 `this.completedAt = 0;` |
| getter/setter | 增加 `getCompletedAt()` / `setCompletedAt(long)` |
| `copy()` | 增加 `copy.completedAt = this.completedAt;` |
| `toMap()` | 增加 `map.put("completed_at", completedAt);` |
| `fromMap()` | 增加 `task.setCompletedAt(((Number) map.get("completed_at")).longValue());` |

### 3.2 TaskStatus.java

| 位置 | 修改 |
|------|------|
| 方法区 | 增加 `isTerminal()` 返回 `this == COMPLETED || this == FAILED || this == CANCELED` |

### 3.3 ControllerConfig.java

| 位置 | 修改 |
|------|------|
| 字段声明区 | 增加 `private long evictionTtlSeconds = 3600;` |
| 字段声明区 | 增加 `private int maxTaskCapacity = 1000;` |
| getter/setter | 增加 `get/setEvictionTtlSeconds()` 含负数校验 |
| getter/setter | 增加 `get/setMaxTaskCapacity()` 含负数校验 |

### 3.4 TaskManager.java

| 位置 | 修改 |
|------|------|
| import 区 | 增加 `Executors, ScheduledExecutorService, ScheduledFuture, TimeUnit` |
| 字段声明区 | 增加 `evictionScheduler` + `evictionFuture` |
| 构造方法 | 增加 `if (evictionTtlSeconds > 0) startEvictionScheduler()` |
| `setConfig()` | 增加 `stopEvictionScheduler(); if (newTtl > 0) startEvictionScheduler()` |
| `updateTaskStatus()` | 增加 `if (newStatus.isTerminal()) task.setCompletedAt(now)` |
| `addTask(List)` | 增加 `enforceMaxCapacity()` 调用 |
| 新方法 | `evictCompletedTasks()` — 使用 config TTL |
| 新方法 | `evictCompletedTasks(long ttlSeconds)` — 使用指定 TTL |
| 新方法 | `enforceMaxCapacity()` — 容量上限保护 |
| 新方法 | `startEvictionScheduler()` — 启动定时调度 |
| 新方法 | `stopEvictionScheduler()` — 关闭调度 |

---

## 4. 测试用例设计

### 4.1 测试文件

`agent-core-java/src/test/java/com/openjiuwen/core/controller/TaskManagerEvictionTest.java`

### 4.2 测试矩阵

| 测试类别 | 用例数 | 关键验证点 |
|---------|--------|-----------|
| TaskStatus.isTerminal | 7 | COMPLETED/FAILED/CANCELED=true, 其他=false |
| completedAt 时间戳 | 4 | 默认值=0, COMPLETED/FAILED/CANCELED 时设置, WORKING时不设置 |
| TTL Eviction | 5 | 禁用(TTL=0), 显式TTL清理, 非终态保留, completedAt=0跳过, 父子层级清理 |
| Max Capacity | 3 | 容量内保留, 超容量淘汰最老终态, 禁用(capacity=0) |
| Eviction Scheduler | 4 | 默认配置生效(TTL=3600), 启动后自动清理, 停止后不清理, setConfig重启 |
| Serialization | 3 | toMap包含completed_at, fromMap恢复completed_at, 状态持久化保留completedAt |

**总计：26 个测试用例**

### 4.3 关键测试用例说明

#### 用例 1：TTL Eviction 显式清理

```java
// 创建3个Task: old(5秒前完成), recent(刚完成), active(WORKING)
// 执行 evictCompletedTasks(3) — TTL=3秒
// 期望: old被清理(5s > 3s), recent和active保留
```

#### 用例 2：容量上限淘汰

```java
// maxCapacity=5, 已有3个completed + 2个working = 5
// 添加第6个task → enforceMaxCapacity() 淘汰最老completed
// 期望: completed_0被淘汰, 其余保留, 总数=5
```

#### 用例 3：Scheduler 自动清理

```java
// config.evictionTtlSeconds=1
// 添加 expired(completedAt=3秒前)
// 等待 2.5秒 (scheduler 在1秒后首次触发)
// 期望: expired被自动清理, getTask(null)为空
```

#### 用例 4：父子层级清理

```java
// parent(COMPLETED, 5秒前) + child(COMPLETED, 5秒前, parentId=parent)
// evictCompletedTasks(3) → 两个都清理
// 期望: parentToChildren/childToParent/rootTasks 同步清理
```

---

## 5. 验证方法

### 5.1 编译验证

```bash
cd agent-core-java
mvn compile -q
# 期望: exit code 0，无编译错误
```

### 5.2 单元测试验证

```bash
mvn test -Dtest=TaskManagerEvictionTest -pl .
# 期望: 25 tests passed, 0 failed
```

### 5.3 内存泄漏验证（生产级压测）

```bash
# 步骤1: 启动 DeepAgent A2AServer，配置 evictionTtlSeconds=60, maxTaskCapacity=100
# 步骤2: 用压测脚本持续发送请求 1小时（~3600个task）
# 步骤3: 监控 JVM heap:
#   - 无eviction: heap 持续增长（~4GB/小时）
#   - 有eviction: heap 稳定在 ~50MB（终态task在60秒后被清理）
# 步骤4: 验证 eviction 日志:
#   grep "Evicted" agent.log → 应看到持续的 eviction 记录
# 步骤5: 验证 taskManager.getTask(null).size() 始终 < maxTaskCapacity
```

### 5.4 回归验证

```bash
# 运行全部 TaskManager 相关测试，确认修改不影响现有功能
mvn test -Dtest=TaskManagerTest,TaskManagerEvictionTest -pl .
# 期望: 所有测试通过
```

### 5.5 配置兼容性验证

```bash
# 默认配置（evictionTtlSeconds=0, maxTaskCapacity=0）下:
# - TaskManager 行与修改前完全一致
# - 无 eviction scheduler 启动
# - 无容量限制
mvn test -Dtest=TaskManagerTest -pl .
# 期望: 所有原有测试通过
```

---

## 6. DeepAgent 集成说明

默认配置已包含安全默认值（TTL=3600, maxCapacity=1000），DeepAgent 无需额外配置即可获得 eviction 保护。

如果需要调整清理策略：

```java
// 更激进清理（高流量场景）
ControllerConfig config = new ControllerConfig();
config.setEvictionTtlSeconds(300);   // 5分钟后清理终态Task
config.setMaxTaskCapacity(200);      // 最多保留200个Task

// 保留历史更久（低流量+需要审计场景）
config.setEvictionTtlSeconds(86400); // 24小时后清理
config.setMaxTaskCapacity(5000);     // 最多保留5000个Task

// 完全关闭（仅用于短运行测试，不推荐生产）
config.setEvictionTtlSeconds(0);
config.setMaxTaskCapacity(0);
```

DeepAgent 的 `ensureTaskLoopRuntime()` 中无需修改——默认配置已生效。

---

## 7. 风险评估

| 风险项 | 等级 | 缓解措施 |
|--------|------|---------|
| eviction scheduler 线程泄漏 | 低 | daemon线程 + stopEvictionScheduler() 安全关闭 |
| 清理后 getTask() 返回空（客户端查询已完成task） | 中 | 默认 TTL=3600秒（1小时），给客户端充足查询时间 |
| 并发清理与查询冲突 | 低 | ReentrantLock 保护所有 eviction 操作 |
| 状态持久化不完整 | 低 | completedAt 已加入 toMap/fromMap/copy |
| 安全默认值变更对已有部署的影响 | 低 | 已部署的 DeepAgent 升级后终态 Task 在1小时后自动清理——对业务影响极小（终态 Task 已无业务意义） |
| 默认=0时内存泄漏风险 | **已消除** | 默认 TTL=3600/capacity=1000，**不再允许无 eviction 运行**（可手动设为0但需明确意图） |
