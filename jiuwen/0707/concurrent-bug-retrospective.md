# 并发请求 Bug 修复复盘报告

## 1. 问题背景

**现象**：DeepAgent A2A Server 在并发请求场景下，后续请求直接返回 `event: completed`（无 output 事件），而非正常的流式响应。

**最终根因**：3条并发请求生成相同的 `taskId="deep_agent_task_1"`，`TaskManager.addTask()` 发现 taskId 已存在后抛异常，异常被 `handleInput` 的 catch 块静默消费 → `resolveCompletion` 设置 `isRoundActive=false` → `awaitRoundCompletion` 立即返回错误 result → `updateCompletionPromise` 无条件 `markCompleted()` → while 循环结束 → SSE 流只发送空的 `completed`。

---

## 2. 决策树回顾

### Phase 1: 代码探索与理解（约 30% 总耗时）

**决策 1.1**：先搜索理解 A2A Server 的请求处理架构

- 工具：SearchCodebase、Read、Grep
- 目的：理解 `sendSubscribe` → `stream()` → `runTaskLoop` 的调用链
- **评价**：✅ 正确。必须先理解架构才能定位 bug。

**决策 1.2**：搜索理解 DeepAgent 的 LoopCoordinator 机制

- 工具：SearchCodebase、Read、Grep
- 目的：理解 `shouldContinue()` / `shouldStop()` / `LoopCoordinator` 的工作方式
- **评价**：✅ 正确。但耗时过多，读了很多不相关的代码。

**优化建议**：代码探索阶段应更聚焦于"并发场景下哪些状态会被共享"。应直接搜索 `synchronized`、`volatile`、`ConcurrentHashMap`、实例字段等关键词，而非逐文件阅读。

---

### Phase 2: 假设验证 — 第一轮（约 25% 总耗时）

**决策 2.1**：假设 `loopCoordinator` 实例字段是根因

- 理由：`LoopCoordinator` 是实例字段，并发请求共享 → `shouldContinue()` 互相影响
- 工具：Read、SearchReplace（修改代码）
- 修改内容：移除 `loopCoordinator` 实例字段，改为 `sessionLoopCoordinators` (ConcurrentHashMap)
- **评价**：⚠️ 部分正确。`loopCoordinator` 确实有竞态读写问题，但不是导致"直接返回 completed"的根因。修复后测试仍然失败。

**决策 2.2**：假设 `EventQueue.subscribe` 覆盖已有 subscription 是根因

- 理由：`subscriptions.put()` 会覆盖第一条请求注册的 handler
- 修改内容：`subscriptions.put()` → `subscriptions.putIfAbsent()`
- **评价**：❌ 错误假设。每个请求有独立的 sessionId（如果加了 requestLevelSessionId），topic 不同，不会冲突。后来被回退。

**决策 2.3**：假设 sessionId 共享导致 EventQueue topic 冲突是根因

- 理由：并发请求使用相同的 `conversation_id` 作为 sessionId → topic 相同 → EventQueue subscription 被覆盖
- 修改内容：为每个请求生成 `requestLevelSessionId`
- **评价**：⚠️ 是必要修复之一（防止 LoopCoordinator 和 topic 冲突），但不是"直接返回 completed"的根因。

**关键问题**：Phase 2 的3个假设都基于"代码推理"而非"运行时观察"。推理方向偏了——过度关注 LoopCoordinator 和 EventQueue 的共享问题，忽略了 TaskManager 的 taskId 冲突。

**优化建议**：应更早添加运行时诊断日志，而非依赖纯代码推理。第一次构建测试失败后，应立即在关键路径（`awaitRoundCompletion`、`handleInput`）添加诊断日志，用日志数据验证假设，而非继续推理下一个假设。

---

### Phase 3: 诊断日志驱动的根因发现（约 20% 总耗时）

**决策 3.1**：添加 DIAG-RUN 日志到 `runTaskLoop`

- 输出：`shouldContinue=true, isAborted=false` — 说明 LoopCoordinator 没问题
- **评价**：✅ 关键转折点。日志否定了 LoopCoordinator 假设，促使转向其他方向。

**决策 3.2**：添加 DIAG-AWAIT 日志到 `awaitRoundCompletion`

- 输出：`waitCompletion #1 result={error=controller task parameter error, reason: deep_agent_task_1 already exists!}`
- **评价**：✅ 根因发现！这是整个调试过程中最重要的单步。但从添加 DIAG-RUN 到添加 DIAG-AWAIT 之间经历了一次不必要的重启和测试循环。

**优化建议**：应一次性在所有关键路径添加诊断日志（`runTaskLoop` 入口/出口、`executeCoreLoopRound` 入口/出口、`awaitRoundCompletion` 每次轮询结果），而非分多次添加。这样可以一次重启就获取完整诊断数据。

---

### Phase 4: 修复实现与验证（约 15% 总耗时）

**决策 4.1**：`taskId` 包含 sessionId

- 修改：`"deep_agent_task_" + handlerRound` → `"deep_agent_task_" + session.getSessionId() + "_" + handlerRound`
- **评价**：✅ 核心修复，直接解决根因。

**决策 4.2**：验证修复

- 工具：restart.py → curl → 3条并发请求
- **评价**：✅ 正确。但之前用了多轮手动 mvn install + mvn compile + 启动，而非直接用 restart.py。

**优化建议**：从开始就使用 restart.py 脚本。用户在后期才告知这个脚本，但我在早期应该主动检查 bin 目录下的脚本。

---

### Phase 5: 代码审查与增强（约 10% 总耗时）

**决策 5.1**：回退 `EventQueue.putIfAbsent` 改动

- 理由：加了 requestLevelSessionId 后 topic 已唯一，此改动非必需
- **评价**：✅ 正确。减少不必要的改动范围。

**决策 5.2**：添加 roundResult 错误写入 stream

- 理由：之前的错误被静默吞掉，调用方只看到空的 completed
- 修改：`runTaskLoop` while 循环中检查 `roundResult.get("error")`，写入 `session.writeStream()`
- **评价**：✅ 正确的增强改进。

**决策 5.3**：初始版本排除了 `completion_timeout` 错误

- 理由（错误的）：误认为 completion_timeout 是轮询信号
- 用户追问后修正：到达 roundResult 的 completion_timeout 只会是真正超时
- **评价**：⚠️ 初始设计有误。应该更仔细区分"轮询内部的 completion_timeout"和"最终返回的 completion_timeout"。

---

## 3. 工具调用统计

| 工具类型 | 调用次数 | 主要用途 |
|----------|----------|----------|
| Read | ~40 次 | 阅读源码文件，理解架构和逻辑 |
| Grep | ~25 次 | 搜索关键词（字段、方法、日志模式） |
| SearchReplace | ~12 次 | 修改代码（修复 + 诊断日志 + 清理） |
| RunCommand | ~20 次 | 构建编译、启动/重启服务器、curl 测试 |
| SearchCodebase | ~8 次 | 代码语义搜索 |
| Write | ~6 次 | 创建临时测试 JSON 文件 |
| DeleteFile | ~4 次 | 删除临时测试文件 |
| CheckCommandStatus | ~8 次 | 检查异步 curl 命令结果 |
| Glob/LS | ~5 次 | 查找文件和目录结构 |
| AskUserQuestion | ~3 次 | 询问用户决策（构建方式、tasks目录处理） |
| TodoWrite | ~10 次 | 任务进度跟踪 |

**总工具调用**：约 ~130 次

---

## 4. 资源使用分析

### 4.1 重启次数

| 原因 | 次数 | 是否必要 |
|------|------|----------|
| 添加诊断日志后验证 | 4 次 | ⚠️ 可优化为 1-2 次（一次性添加所有诊断日志） |
| 修复后验证 | 3 次 | ✅ 必要（核心修复 + 回退 putIfAbsent + 添加 error 写入） |
| 编译错误修复 | 1 次 | ⚠️ 可避免（Loggers 用法错误，应先检查现有 import） |
| 手动 mvn install + 启动 | 2 次 | ❌ 不必要（应直接用 restart.py） |

**总计**：10 次重启，优化后可减少到 4-5 次。

### 4.2 临时文件

| 文件 | 数量 | 是否必要 |
|------|------|----------|
| test_single.json / test_t1.json | 反复创建删除 ~6 次 | ❌ 可优化为创建一次，测试完统一删除 |
| tasks/ 目录（3个文件） | 1 次 | ❌ 非本次产生，但应在早期检查并忽略 |

### 4.3 不必要的代码改动

| 改动 | 后续处理 | 是否可避免 |
|------|----------|------------|
| EventQueue.putIfAbsent | 后来回退 | ✅ 可避免（分析代码后发现 topic 不同就不会冲突） |
| Loggers.SESSION.info() | 编译失败后改为 System.out.println | ✅ 可避免（先检查现有 import） |

---

## 5. 关键优化建议

### 5.1 诊断策略：日志优先，推理为辅

**问题**：前 60% 的时间花在纯代码推理上，产生了 2 个错误假设（EventQueue.putIfAbsent、LoopCoordinator 是根因）。

**建议**：
- 遇到并发 bug，**第一步就是在关键路径添加诊断日志**（入口/出口/关键分支）
- 一次性添加所有诊断日志，一次重启获取完整数据
- 用日志数据验证/否定假设，而非继续推理下一个假设
- 诊断日志应包含：线程名、sessionId、关键状态值

### 5.2 构建流程：利用现有脚本

**问题**：前期手动执行 `mvn install` + `mvn compile` + `mvn exec:java`，每步分开执行。

**建议**：
- **优先检查项目 bin/ 目录下的运维脚本**（restart.py、start.py、stop.py）
- restart.py 已包含完整的 install → compile → start → wait-for-ready 流程
- 一次性使用脚本比手动分步操作更可靠、更快速

### 5.3 假设管理：记录并追踪

**问题**：多个假设交叉验证，没有系统性追踪，导致重复验证和遗漏。

**建议**：
- 使用 TodoWrite 工具记录每个假设及其验证结果
- 标记假设状态：待验证 → 已验证（正确/错误）
- 避免在没有否定前一假设的情况下就跳到下一假设

### 5.4 代码修改策略：最小改动原则

**问题**：一次性修改了3处（loopCoordinator 移除 + requestLevelSessionId + putIfAbsent），无法区分哪个修复了问题。

**建议**：
- **每次只改一处**，改完立即验证
- 如果验证失败，回退该改动，再尝试下一个
- 如果验证成功，确认该改动是根因修复，再考虑其他加固改动
- 最终审查时，逐一审视每个改动是否必需

### 5.5 错误传播分析：从调用方视角逆向追踪

**问题**：发现根因后（taskId 重复），没有立即追问"为什么调用方只看到 completed 而不是错误信息"。

**建议**：
- 发现根因后，**立即从调用方视角逆向追踪错误传播路径**
- 确认错误是否被正确传递到最终用户
- 如果错误被吞掉，这本身也是一个需要修复的 bug

---

## 6. 理想的执行流程（对比实际流程）

### 实际流程（10 次重启）

```
1. 代码探索 → 2. 假设 loopCoordinator → 3. 修改+重启 → 测试失败
4. 假设 EventQueue.put → 5. 修改+重启 → 测试失败
6. 假设 sessionId → 7. 修改+重启 → 测试失败
8. 添加 DIAG-RUN → 9. 重启 → 否定 LoopCoordinator 假设
10. 添加 DIAG-AWAIT → 11. 重启 → 发现根因（taskId 重复）
12. 修复 taskId → 13. 重启 → 验证成功
14. 审查改动 → 15. 回退 putIfAbsent → 16. 重启 → 验证成功
17. 添加 error 写入 stream → 18. 重启 → 验证成功
```

### 理想流程（4 次重启）

```
1. 代码探索 + 检查 bin/ 脚本
2. 一次性添加全面诊断日志（runTaskLoop/awaitRoundCompletion/handleInput）
3. restart.py 重启 → 测试 → 从日志一次性发现根因（taskId 重复 + loopCoordinator 竞态）
4. 一次性修复（taskId + loopCoordinator + requestLevelSessionId）
5. restart.py 重启 → 验证成功
6. 审查改动 → 回退非必需改动（putIfAbsent）
7. restart.py 重启 → 验证成功
8. 添加 error 写入 stream
9. restart.py 重启 → 验证成功
```

**效率提升**：从 10 次重启 → 4 次重启，减少约 60% 的构建/等待时间。

---

## 7. 最终修复清单

| 修复 | 文件 | 类型 |
|------|------|------|
| taskId 包含 sessionId | DeepAgent.java:976 | 核心根因修复 |
| 移除 loopCoordinator 实例字段 | DeepAgent.java:80 | 并发安全加固 |
| requestLevelSessionId | DeepAgent.java:438/465/491 | 并发隔离 |
| requestAbort() 遍历 sessionLoopCoordinators | DeepAgent.java:551 | 配合 loopCoordinator 移除 |
| requestAbort(String sessionId) | DeepAgent.java:556 | API 完善 |
| roundResult 错误写入 stream | DeepAgent.java:867 | 错误可见性增强 |

---

*报告生成时间：2026-07-07*
