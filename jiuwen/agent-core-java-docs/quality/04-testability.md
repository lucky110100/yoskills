# 可测试性（否决项）— agent-core-java 质量评估

> 组: B 代码质量 | 分: **3/4** | 否决项: **否决项已规避（非 0）** | 评估卡: [dims/testability.md](file:///D:/jiuwen/main/yoskills/common/project-analysis/dims/testability.md)

## 评分锚点依据

命中 3 档「有分层测试 + 覆盖率 50-80% + 部分耦合外部 + 偶有 flaky」。分层清晰：SystemTest 用 `@Tag("system-test")` 标注并被 surefire 默认排除（[pom.xml:62](file:///D:/jiuwen/main/agent-core-java/pom.xml#L62)），见 [WorkflowSystemTest.java:37](file:///D:/jiuwen/main/agent-core-java/src/test/java/com/openjiuwen/core/systemtest/WorkflowSystemTest.java#L37) 等 42 个 SystemTest；98 个 CompatibilityTest 做 Java-Python API 对齐；纯单元测试如 [KVStoreFactorySpiTest.java](file:///D:/jiuwen/main/agent-core-java/src/test/java/com/openjiuwen/spi/store/KVStoreFactorySpiTest.java#L17-L47) 无外部依赖断言充分快。DI/mock 充分：Mockito 全仓广泛使用。覆盖率工具已配：[pom.xml:432-453](file:///D:/jiuwen/main/agent-core-java/pom.xml#L432-L453) jacoco。但"部分耦合外部"：SystemTest 耦合 Redis/PGVector，部分测试用 `mockStatic`（违反 X.TST.03）。

**否决项确认：可测试性不为 0**——100+ 测试文件、42 SystemTest、98 CompatibilityTest、jacoco 配置、Mockito/JUnit5/AssertJ 齐备。

## 评估过程

- **信号命中**：测试耦合外部 ✅、无覆盖率统计门禁 ✅、flaky 风险 ✅；无依赖注入/无法 mock ❌、私有方法测 ❌
- **Glob**：测试文件数 vs 源码数（100+ vs 200+）
- **Read**：[KVStoreFactorySpiTest.java:17-47](file:///D:/jiuwen/main/agent-core-java/src/test/java/com/openjiuwen/spi/store/KVStoreFactorySpiTest.java#L17-L47) 纯单元测试
- **Grep**：`check|threshold|haltOnFailure|minimum` 在 pom.xml 仅命中无关行

## 关键问题（带证据）

1. **覆盖率无门禁阈值**：[pom.xml:432-453](file:///D:/jiuwen/main/agent-core-java/pom.xml#L432-L453) jacoco 只跑 `prepare-agent`+`report` 不跑 `check`，覆盖率数值未强制，属反模式"覆盖率统计了不看"。
2. **部分"单元测试"实为耦合外部依赖的集成测试**：SystemTest 虽 `@Tag` 隔离，但 TenantRedisSystemTest、PGVectorStoreSystemTest 需真实 Redis/PG 容器，无 testcontainers 兜底则 CI 易 flaky（pom 未引 testcontainers）。
3. **mockStatic 轻度违规**：[ContextsPipelinesCompatibilityTest.java:8](file:///D:/jiuwen/main/agent-core-java/src/test/java/com/openjiuwen/autoharness/ContextsPipelinesCompatibilityTest.java#L8) import mockStatic，违反 X.TST.03"No static mocks; prefer injectable deps"。

## 改进建议

1. 给 jacoco 加 `<goal>check</goal>` 并设 `HALT_ON_FAILURE` 与最低行覆盖率阈值（如 60% 起步）
2. 对 Redis/PG 依赖的 SystemTest 引入 testcontainers 或 fakes
3. 减少生产代码静态方法调用以降低 `mockStatic` 使用（符合 X.TST.03）
4. surefire 为 system-test 单独设 forkCount/timeout，防 flaky 阻塞主套件

## 业界对标

- Java 标杆：看 Spring Boot 的 spring-boot-test 体系（分层 + 覆盖率门禁）、mall 的测试目录
- 差距：标杆有覆盖率门禁 + testcontainers 兜底，本项目 jacoco 已配但无 check 门禁、SystemTest 耦真实外部
