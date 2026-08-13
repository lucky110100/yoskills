# 复用性 — agent-core-java 质量评估

> 组: B 代码质量 | 分: **3/4** | 否决项: 否 | 评估卡: [dims/reusability.md](file:///D:/jiuwen/main/yoskills/common/project-analysis/dims/reusability.md)

## 评分锚点依据

命中 3 档「偶有重复 + 公共模块基本清晰」。公共模块清晰：[spi 包](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/spi/store/KVStoreFactory.java#L25-L33) 是边界良好的存储 SPI，`KVStoreFactory` 用 `ServiceLoader` + `ConcurrentHashMap` 注册表实现可插拔，注释明示"Service adapters can register additional types without modifying Core source"；[Constant.java](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/common/constants/Constant.java#L15-L23) 集中管理 IR 字段常量。抽象恰当：`QueryExpr` 体系有 11 个子类各对应不同查询语义，非为复用而抽象。但"偶有重复"明确存在：跨文件常量 copy-paste（详见代码规范维度）。

## 评估过程

- **信号命中**：公共模块缺失 ✅（部分）、重复代码 ✅、过度抽象 ❌、循环依赖阻碍复用 ❌
- **Read**：[KVStoreFactory.java:17](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/spi/store/KVStoreFactory.java#L17) 确认 SPI 可插拔设计
- **Grep/Read**：跨文件常量重复命中（MAX_INDEX_LINES/TEAM_MEMORY_MAX_READ_LINES/DEFAULT_MAX_LOOP_NUMBER）

## 关键问题（带证据）

1. **跨文件常量 copy-paste 未抽取**（违反 X.DEP.04）：`MAX_INDEX_LINES = 200` 三处见 [CodingMemoryToolOps.java:28](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/lite/CodingMemoryToolOps.java#L28) 与 [CodingMemoryRail.java:34](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/CodingMemoryRail.java#L34)；`TEAM_MEMORY_MAX_READ_LINES = 200` 两处见 [TeamMemoryExtractor.java:72](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/team/TeamMemoryExtractor.java#L72) 与 [SharedMemoryManager.java:38](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/team/SharedMemoryManager.java#L38)，且两处 Javadoc 文本一字不差（典型 copy-paste）。
2. **无重复代码扫描门禁**：pom.xml 未配置 jscpd/duplicate-finder 插件，重复债务无量化监控。

## 改进建议

1. 将 `MAX_INDEX_LINES`、`TEAM_MEMORY_MAX_READ_LINES`、`DEFAULT_MAX_LOOP_NUMBER` 等共享常量提取到 `core/memory/MemoryLimits.java` 或 `core/workflow/WorkflowLimits.java` 单一常量类
2. CI 增加 `duplicate-finder-maven-plugin` 或 jscpd 扫描，设重复率阈值
3. 对 spi 模块补充"如何新增 Provider"示例文档

## 业界对标

- Java 标杆：看 mall 的 mall-common 公共模块、RuoYi-Vue-Plus 的 ruoyi-common（脱敏/翻译/多租户抽取）
- 差距：标杆公共模块抽取彻底且单一来源，本项目偶有常量散布；强项是 SPI 可插拔设计优秀
