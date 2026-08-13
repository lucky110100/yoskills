# 性能 — agent-core-java 质量评估

> 组: C 运行时质量 | 分: **2/4** | 否决项: 否 | 评估卡: [dims/performance.md](file:///D:/jiuwen/main/yoskills/common/project-analysis/dims/performance.md)

## 评分锚点依据

命中 2 档「多处 N+1/循环重操作 + 无压测」。项目在 LLM 客户端连接池做了显式性能调优，但核心记忆模块存在循环内查库 N+1，且无任何 JMH/压测基线、无缓存策略。

## 评估过程

- **信号命中**：N+1（循环内查库）✅、循环内重操作 ✅、无缓存 ✅、无性能基准/压测 ✅
- **Read**：[GraphMemory.java:855-895](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/graph/graph_memory/GraphMemory.java#L855-L895) 循环内连续 dbBackend.search(L863/L873)+dbBackend.query(L887)
- **Grep**：`@Benchmark|JMH|Gatling|wrk|k6` 在 src/test 仅命中 .claude/skills/performance-tuning/ 文档（非真实测试）
- **Grep**：`@Cacheable|Caffeine|LoadingCache` 无命中；[TaskLoopController.java:30](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/task_loop/TaskLoopController.java#L30) 仅 ConcurrentMap session 缓存无失效设计

## 关键问题（带证据）

1. **典型 N+1（已行号实测）**：[GraphMemory.java:856-895](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/graph/graph_memory/GraphMemory.java#L856-L895) `fetchRelevantEntities` 在 `for (EntityDeclaration entity : extractedDeclarations)` 循环内对每个实体连续调用 `dbBackend.search`（[L863](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/graph/graph_memory/GraphMemory.java#L863)、[L873](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/graph/graph_memory/GraphMemory.java#L873)）、以及 `dbBackend.query`（[L887](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/graph/graph_memory/GraphMemory.java#L887)）。其中 L887 的 query 过滤条件 `filterUser(userId)` 不依赖循环变量，等价每次迭代全表扫描后内存做名字匹配——严重 N+1。
2. **无性能基准/压测**：全仓 src/test 下未出现 `@Benchmark`/JMH/Gatling/wrk/k6，无任何性能基线。
3. **无缓存策略**：未引入 `@Cacheable`/Caffeine/LoadingCache。

## 改进建议

1. 将 GraphMemory 循环内 search/query 改批量接口（一次 `searchAll`/`queryByIds`）
2. 引入 Caffeine 本地缓存 + 失效策略
3. 为核心检索/记忆路径补 JMH 基准测试并在 CI 守护吞吐/延迟基线

## 业界对标

- 标杆：Spring Boot actuator 性能指标、Pydantic 的 Rust 内核、Spring Cloud Alibaba 的 Sentinel 流控
- 差距：本项目核心记忆路径有 N+1，无压测基线也无缓存策略
