# 可靠性（否决项）— agent-core-java 质量评估

> 组: C 运行时质量 | 分: **3/4** | 否决项: **已规避（非 0）** | 评估卡: [dims/reliability.md](file:///D:/jiuwen/main/yoskills/common/project-analysis/dims/reliability.md)

## 评分锚点依据

命中 3 档「有重试/超时 + 偶有异常吞」。具备自实现的容错设施（熔断、重试、超时、背压、幂等），但缺限流库/混沌测试，且存在若干 `catch (Exception ignored) {}` 式吞异常。**未触发否决**——非"无容错/异常全吞"。

## 评估过程

- **信号命中**：异常被吞（空 catch）✅、无幂等设计 ❌（实际有分布式锁幂等）、无限流/背压 ✅（部分有背压）、无重试/超时/熔断 ❌（实际有自实现）
- **Grep**：`catch.*\{\s*\}` 与 `catch (Exception ignored)` 全仓 src/main 命中 27 文件
- **Read**：ModelCircuitBreaker/OpenAiCompatibleModelClient/DistributedLock/OpenJiuwenExecutors 容错设施

## 关键问题（带证据）

1. **容错设施存在（已行号实测）**：[ModelCircuitBreaker.java:89-97](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/foundation/llm/ModelCircuitBreaker.java#L89-L97) 连续连接失败阈值 + 开窗 fail-fast；[OpenAiCompatibleModelClient.java:351-363](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/foundation/llm/model_clients/OpenAiCompatibleModelClient.java#L351-L363) 连接级失败触发熔断并 `evictAll()` 清中毒连接池；[JiuwenBoxProviderMixin.java:464-507](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/extensions/sys_operation/sandbox/providers/jiuwenbox/JiuwenBoxProviderMixin.java#L464-L507) sandbox 404 做 3 次退避重建；[DistributedLock.java:48-62](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/common/DistributedLock.java#L48-L62) UUID+TTL 幂等锁；[OpenJiuwenExecutors.java:435](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/common/concurrent/OpenJiuwenExecutors.java#L435) SynchronousQueue+CallerRunsPolicy 背压。
2. **偶有异常吞（27 处）**：[Trainer.java:612-615](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentevolving/trainer/Trainer.java#L612-L615) `catch (Exception ignored) { // Ignore. }` 完全吞反射异常；[BeamSearch.java:252-254](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentevolving/optimizer/tool_call/utils/BeamSearch.java#L252-L254) 同模式；[EventBus.java:197-199](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/agent/coordination/EventBus.java#L197-L199) `catch (InterruptedException e)` 不重新中断（注释自述违反 G.CON.10）。
3. **缺限流/混沌**：未引入 Sentinel/Resilience4j/Hystrix，无限流注解或 TokenBucket；无 chaos-mesh/混沌测试用例。

## 改进建议

1. 将 `ModelCircuitBreaker` 升级为 Resilience4j/Sentinel 以获半开探测与指标导出
2. 为关键写操作（记忆持久化、PR 发布）补幂等键
3. 清理 `ignored` 空 catch，至少 `LOG.warn` 或 `Thread.currentThread().interrupt()`
4. 引入限流注解保护下游 LLM/向量库

## 业界对标

- 标杆：Spring Cloud Alibaba 的 Sentinel（限流/熔断/降级）与 Seata（分布式事务）
- 差距：本项目有自实现熔断但缺限流库与混沌测试；强项是分布式锁幂等设计
