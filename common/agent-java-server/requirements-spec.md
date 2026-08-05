# agent-core-java 重构需求规格文档

| 项目 | 内容 |
|------|------|
| 文档名称 | agent-core-java 重构为 RuoYi 子模块需求规格 |
| 版本 | v1.0 |
| 日期 | 2026-07-29 |
| 输出目录 | yoskills/common/agent-java-server |
| 关联文档 | design.md（设计文档）、test-plan.md（测试计划文档） |
| 原始需求来源 | yoskills/common/agent-java-server/query.md |

---

## 1. 项目背景

### 1.1 现状

`agent-core-java` 是 openJiuwen 框架的独立 Java 实现，定位为面向大语言模型应用的 Java 软件开发工具包。它基于 **Project Reactor 异步图执行引擎（Pregel 模型）**，提供 Agent 创建、工作流编排、LLM 调用、工具调用、中断恢复、流式输出等能力。

当前技术画像：
- **构建**：Maven，groupId `com.openjiuwen`，version `0.1.13`，Java 17，packaging jar
- **非 Spring 项目**：pom.xml 基于 Jackson 2.17 / OkHttp 4.12 / Reactor 3.6 / SLF4J + Logback / Lombok / Bouncy Castle / Milvus / Pulsar / pgvector / Testcontainers，未引入 Spring 生态
- **无 ORM 映射**：既无 MyBatis Mapper XML，也无 JPA 实体；所有 SQL 均以字符串拼接内嵌 Java（如 `DbModel`、`DbBasedKVStore`、`TeamDatabase`、`SqlDbStore`、`SqlMigrator`）
- **持久化采用 SPI 策略模式**：通过 `BaseKVStore`/`BaseDbStore`/`BaseVectorStore` 抽象 + `ServiceLoader` 发现 Provider 实现可插拔存储后端
- **分层**：core（核心运行时）/ harness（编码智能体框架）/ spi（存储抽象）/ extensions（后端实现）/ agentteams / autoharness / agentevolving / dev_tools / deepagents

### 1.2 重构动因

1. 当前持久化层为字符串 SQL 拼接，缺乏统一 ORM 治理，难以与主流 Java Web 工程集成
2. 需将 agent 能力接入 RuoYi 工程作为子模块，与 RuoYi 既有的用户/角色/菜单/权限体系打通
3. 需采用面向对象编程思想与 Spring MVC 框架规范，统一数据库设计与代码分层

### 1.3 目标工程参考

RuoYi 工程位于 `D:\jiuwen\main\ruoyi`，版本 v4.8.3 经典版（前后端不分离的 Thymeleaf 单体版），其技术画像：
- Java 17 + Spring Boot 4.0.6 + Jakarta 命名空间
- MyBatis（原生，非 MyBatis-Plus）+ Druid + PageHelper
- Apache Shiro 2.2.0（非 Spring Security，非 JWT）+ EhCache（非 Redis）
- 6 个 Maven 模块：ruoyi-admin / ruoyi-framework / ruoyi-system / ruoyi-quartz / ruoyi-generator / ruoyi-common
- 分层规范：Controller（extends BaseController，返回 AjaxResult/TableDataInfo）→ Service（IXxxService + XxxServiceImpl）→ Mapper（接口 + XML）
- 实体规范：继承 BaseEntity（createBy/createTime/updateBy/updateTime/delFlag/remark/params），逻辑删除 del_flag（"0"存在/"2"删除）

---

## 2. 术语定义

| 术语 | 说明 |
|------|------|
| hardess 工程 | 原始需求中的 "hardess 工程" 实指代码库中的 **harness 工程**（`com.openjiuwen.harness` 模块，编码智能体框架），系拼写差异 |
| harness 模块 | openJiuwen 的编码智能体框架，含 DeepAgent、Rails、TaskLoop、Subagents、Tools、Security 等 |
| RuoYi | 若依，本工程参考的 Java Web 快速开发框架，位于 `D:\jiuwen\main\ruoyi` |
| 子模块集成 | 将 agent-core-java 作为 RuoYi 父工程下的 Maven 子模块引入，与 ruoyi-admin/framework/system 等模块并列 |
| 适配层 | 本次新建的 `ruoyi-agent` 子模块，按 RuoYi 分层规范封装 agent-core-java 引擎能力 |
| 引擎内核 | 保留的 `com.openjiuwen.*` 运行时（Reactor 异步图执行、Pregel、中断恢复、流式输出），仅由 Spring 托管生命周期 |
| SPI 桥接 | 通过实现内核 `TodoStorage`/`KVStoreProvider` 等 SPI 接口，使内核无感知地改用 MyBatis 后端 |

---

## 3. 重构目标与范围

### 3.1 总体目标

将 agent-core-java 重构为可被 RuoYi 工程集成的子模块，采用面向对象编程思想、Spring MVC 框架为基础，重新设计数据库与代码分层，并确保功能正常。

### 3.2 重构策略

采用 **方案 A：渐进适配层**（已与用户确认）：
- **保留** `com.openjiuwen` 引擎内核的 Reactor 异步执行模型不动，仅由 Spring 托管生命周期
- **新建** RuoYi 子模块 `ruoyi-agent`（包名 `com.ruoyi.agent`），按 RuoYi 分层**重写持久化层**与**暴露层**
- 通过 `adapter` 包桥接调用内核 API，通过实现内核 SPI 接口使内核无感知地走 DB

### 3.3 重构范围

**覆盖整个 agent-core-java**，按"保留 / 重写 / 暴露"三策略归类：

| 原包（com.openjiuwen.*） | 策略 | 说明 |
|---|---|---|
| core.graph / core.runner / core.controller | 保留内核 | Reactor 异步图执行引擎，仅 Spring 托管 |
| core.session（Session/State/Stream） | 保留内核 | 会话、中断恢复、流式输出 |
| core.memory（LongTermMemory 等） | 保留引擎 + 重写持久化 | user_message 等 3 表重写为 MyBatis |
| core.retrieval / core.foundation.store | 保留内核 | 向量库不纳入关系型重构；仅 kv_store 表重写 |
| core.multitenant / core.security | 保留内核 | 多租户、护栏 |
| core.workflow / core.multiagent | 保留内核 | 工作流、多智能体运行时 |
| **harness（DeepAgent/Rails/Tools/TaskLoop）** | **保留引擎 + 重写持久化 + 暴露 Controller** | **本次重构重点** |
| spi.store（BaseKVStore/BaseDbStore） | 保留抽象 + 新增 MyBatis Provider | 新增 MyBatisKVStoreProvider 桥接 |
| extensions（redis/checkpointer/gaussdb） | 保留内核 | 可选依赖 |
| agentteams（TeamDatabase 等表） | 保留引擎 + 重写持久化 | team_* 表重写 |
| autoharness / agentevolving / dev_tools / deepagents | 保留内核 | — |

### 3.4 重构重点

需求 #1 所述 "hardess 工程相关的核心对象" 锁定为 **harness 模块及其直接依赖的持久化对象**，包括：
- DeepAgent（运行时 facade）、HarnessFactory、DeepAgentConfig、Workspace
- Rails 体系（AgentRail → DeepAgentRail → 25+ 具体 rail；BaseInterruptRail → AskUserRail/ConfirmInterruptRail/PermissionInterruptRail）
- TaskLoop（TaskLoopController / LoopCoordinator / StopConditionEvaluator）
- Subagents（SubAgentConfig / SubAgentRegistry / 6 个工厂）
- Security（PermissionEngine / PermissionFactory）
- Tools（TodoStorage / TodoItem / TodoTool / 45+ 工具）
- 持久化对象（TodoStorage、Checkpointer、Memory 表、Team 表、KV 表）

### 3.5 不在范围内

- 向量数据存储（Milvus/Chroma/PGVector）：保留内核 SPI，不建关系表
- 对象存储 / 文件存储（FileTodoStorage / WorkspaceStore）：保留文件实现
- 图记忆（GraphMemory / Entity / Episode / Relation）：保留内核图存储
- RuoYi 自身的 sys_* 业务表：宿主既有，不改动
- 内核 `com.openjiuwen.*` 自身的 Reactor / Pregel / 中断恢复逻辑：保留原有实现与测试

---

## 4. 原始需求与对应

| 原始需求 | 对应本规格章节 | 本次产物 |
|---|---|---|
| #1 提取 harness 工程核心对象及其属性、方法、对象间关系 | 设计文档 §4（核心类重构设计） | 仅设计 |
| #2 参考 RuoYi，OOP + Spring MVC，重构数据库设计与代码（类定义、方法实现、对象关系） | 设计文档 §3（数据库设计）+ §4（核心类） | 仅设计 |
| #3 重构后可作为 RuoYi 子模块集成 | 设计文档 §5（集成方案与配置） | 仅设计 |
| #4 测试重构后代码确保功能正常 | 测试计划文档（test-plan.md） | 仅设计（含测试用例设计，不生成测试脚本） |

**本次产物形式**：仅输出设计文档（需求规格 + 设计文档 + 测试计划文档），不生成实际代码、DDL 脚本文件、测试脚本文件。所有 SQL DDL、Java 类签名、测试用例均以文档章节形式呈现，供后续实施阶段使用。

---

## 5. 功能性需求

### 5.1 持久化层重写

| 需求 ID | 需求描述 | 验收标准 |
|---|---|---|
| FR-DB-001 | 将现有字符串 SQL 持久化重写为 MyBatis Entity/Mapper/XML | 15 张表全部有对应 Entity、Mapper 接口、XML 映射 |
| FR-DB-002 | 表设计遵循 RuoYi 规范（agent_ 前缀、BaseEntity 字段、逻辑删除） | 所有业务表含 create_by/create_time/update_by/update_time/del_flag |
| FR-DB-003 | 原动态表（team_task_* 等按 session 后缀建表）合并为单表 + session_id 列 | 不再动态建表，通过 session_id 列区分 |
| FR-DB-004 | 字段命名使用完整单词，禁止单字符字段（如 k/v） | 所有字段名为有语义的完整单词（如 store_key/store_value） |
| FR-DB-005 | 主键策略：业务表 BIGINT 自增，保留原 VARCHAR 业务键作唯一索引 | id 为主键，原业务键为 UNIQUE KEY |

### 5.2 分层规范对齐 RuoYi

| 需求 ID | 需求描述 | 验收标准 |
|---|---|---|
| FR-LAYER-001 | Controller 继承 BaseController，返回 AjaxResult/TableDataInfo | 所有 Controller extends BaseController，方法返回 AjaxResult 或 TableDataInfo |
| FR-LAYER-002 | Service 接口前缀 I，实现标注 @Service 放 *.service.impl | 8 个 Service 遵循 IXxxService + XxxServiceImpl |
| FR-LAYER-003 | Mapper 接口无 @Mapper 注解，XML 放 resources/mapper/agent/ | 被 classpath*:mapper/**/*Mapper.xml 扫描 |
| FR-LAYER-004 | Entity 继承 BaseEntity，放 com.ruoyi.agent.domain | 被 typeAliasesPackage=com.ruoyi.**.domain 扫描为别名 |
| FR-LAYER-005 | 权限用 Shiro @RequiresPermissions，日志用 @Log | Controller 方法标注权限与操作日志注解 |

### 5.3 SPI 桥接

| 需求 ID | 需求描述 | 验收标准 |
|---|---|---|
| FR-SPI-001 | 实现 TodoStorage SPI 接口，使内核 TodoTool 走 DB | TodoStorageAdapter implements TodoStorage |
| FR-SPI-002 | 实现 KVStoreProvider SPI，使内核 KV 走 DB | MyBatisKVStoreProvider，typeName()="mybatis" |
| FR-SPI-003 | 实现 SessionStoreProvider SPI | MyBatisSessionStoreProvider |
| FR-SPI-004 | ServiceLoader 能发现新增 Provider | META-INF/services 注册文件齐全 |
| FR-SPI-005 | Spring 与 ServiceLoader 桥接 | AgentSpiBootstrap 注入 ApplicationContext |

### 5.4 内核 Spring 托管

| 需求 ID | 需求描述 | 验收标准 |
|---|---|---|
| FR-BEAN-001 | DeepAgent/Runner/ResourceMgr 由 Spring 托管生命周期 | @Configuration + @Bean 注册 |
| FR-BEAN-002 | 容器关闭时释放内核资源 | @Bean(destroyMethod="close") |
| FR-BEAN-003 | 引擎配置通过 application.yml 驱动 | AgentEngineProperties 读取 agent.engine.* |

### 5.5 模块集成

| 需求 ID | 需求描述 | 验收标准 |
|---|---|---|
| FR-INT-001 | ruoyi-agent 作为 RuoYi 子模块 | 根 pom.xml <modules> 含 ruoyi-agent |
| FR-INT-002 | ruoyi-agent 依赖 ruoyi-common + agent-core-java | pom 依赖声明正确，无反向依赖 |
| FR-INT-003 | ruoyi-admin 引入 ruoyi-agent | 被 @SpringBootApplication 扫描 |
| FR-INT-004 | 复用宿主 MyBatisConfig/Druid 数据源 | 不新建 SqlSessionFactory |
| FR-INT-005 | Shiro 权限菜单注册 | menu.sql 片段提供 agent:* 权限标识 |

### 5.6 业务暴露

| 需求 ID | 需求描述 | 验收标准 |
|---|---|---|
| FR-API-001 | 暴露 Todo CRUD 接口 | /agent/todo/* 全套 REST |
| FR-API-002 | 暴露 Session 管理（含中断恢复） | /agent/session/* |
| FR-API-003 | 暴露 DeepAgent 同步调用 | /agent/invoke |
| FR-API-004 | 暴露 DeepAgent 流式调用（SSE） | /agent/stream |
| FR-API-005 | 暴露 Evolution/Team/Memory/SubAgent/Skill 管理 | 各对应 Controller |

---

## 6. 非功能性需求

| 需求 ID | 类别 | 需求 | 验收标准 |
|---|---|---|---|
| NFR-PERF-001 | 性能 | 同步 CRUD 响应 < 200ms（10 万数据量） | 压测达标 |
| NFR-PERF-002 | 性能 | 流式调用首 chunk 延迟 < 2s | L5 测试 |
| NFR-REL-001 | 可靠性 | 不破坏内核 Reactor 异步语义 | 内核原有测试全绿 |
| NFR-REL-002 | 可靠性 | 逻辑删除生效，不物理删除业务数据 | del_flag 校验 |
| NFR-SEC-001 | 安全 | 所有接口经 Shiro 鉴权 | 无权限返回 403 |
| NFR-SEC-002 | 安全 | 不引入 Spring Security / JWT / Redis（与宿主一致） | 依赖清单无相关 jar |
| NFR-MAINT-001 | 可维护 | 分层清晰，包名规范 | com.ruoyi.agent.* 一致 |
| NFR-MAINT-002 | 可维护 | 实体风格跟随 ruoyi-system（显式 getter/setter，非 Lombok） | 与宿主一致 |
| NFR-COMPAT-001 | 兼容 | Java 17 + Spring Boot 4.0.6 + Jakarta | 无 javax.* |
| NFR-COMPAT-002 | 兼容 | agent-core-java 原有测试无回归 | mvn test -pl agent-core-java 全绿 |
| NFR-TEST-001 | 可测试 | 单测覆盖率 ruoyi-agent ≥ 70%，SPI 桥接层 ≥ 90% | Jacoco 报告 |
| NFR-ISO-001 | 隔离 | 多租户数据隔离生效 | 租户间数据不可见 |

---

## 7. 约束条件

1. **技术栈约束**：必须使用 Java 17 + Spring Boot 4.0.6 + Jakarta 命名空间（`jakarta.servlet.*`/`jakarta.validation.*`），不得使用 `javax.*`
2. **鉴权约束**：使用 Apache Shiro 注解 `@RequiresPermissions`，不得引入 Spring Security 或 JWT
3. **缓存约束**：使用 EhCache（与宿主一致），不得引入 Redis（除非通过 extensions 可选依赖）
4. **ORM 约束**：使用 MyBatis 原生（非 MyBatis-Plus），手写 XML，分页用 PageHelper（`startPage()`）
5. **内核不动约束**：`com.openjiuwen` 的 Reactor 异步执行、Pregel 图引擎、中断恢复、流式输出保持原样，不得改为 Spring MVC 阻塞模型
6. **命名空间约束**：允许 `com.openjiuwen`（内核）+ `com.ruoyi.agent`（适配层）并存，通过 adapter 包隔离
7. **依赖约束**：ruoyi-agent 仅依赖 ruoyi-common + agent-core-java，不得反向依赖 ruoyi-framework/system/admin
8. **实体风格约束**：跟随 ruoyi-system，使用显式 getter/setter，新文件不主动加 Lombok 注解
9. **线程池约束**：不使用 Executors.newCachedThreadPool/newFixedThreadPool，显式 ThreadPoolExecutor + 有界队列 + 命名线程（遵循 X.CON.06）
10. **日志约束**：SLF4J + Logback，Logger 为 private static final（遵循 G.LOG.01/02）

---

## 8. 成功标准

| 维度 | 成功标准 |
|---|---|
| 集成 | ruoyi-agent 作为 RuoYi 子模块，`mvn clean install` 全量编译通过 |
| 数据库 | 15 张表设计完成，遵循 RuoYi 规范，字段命名无单字符 |
| 代码 | Entity/Mapper/Service/Controller/Adapter 分层完整，方法签名清晰 |
| 桥接 | SPI 桥接使内核 TodoTool/KVStore 实际走 DB（可验证） |
| 鉴权 | 所有接口经 Shiro 鉴权，权限菜单注册 |
| 无回归 | agent-core-java 原有测试全绿 |
| 测试 | 测试计划文档完整，覆盖 L1-L5 五层，验收标准明确 |
| 文档 | 三份文档（需求规格、设计、测试计划）齐全且自洽 |

---

## 9. 假设与依赖

| 编号 | 假设/依赖 |
|---|---|
| ASM-001 | 假设本地 RuoYi 工程路径 `D:\jiuwen\main\ruoyi` 不变 |
| ASM-002 | 假设 agent-core-java 引擎内核 v0.1.13 的公开 API 在重构期间稳定 |
| ASM-003 | 依赖 RuoYi 宿主提供 Druid 数据源、MyBatisConfig、ShiroConfig |
| ASM-004 | 依赖 agent-core-java 现有 SPI 机制（TodoStorageProvider/KVStoreProvider/SessionStoreProvider）可被扩展 |
| ASM-005 | 假设本次仅产出设计文档，实施阶段另行立项 |

---

## 10. 风险登记

| 风险 ID | 风险描述 | 等级 | 对策 |
|---|---|---|---|
| RSK-001 | Reactor 异步模型与 Spring MVC 阻塞模型语义冲突 | 高 | 内核不动原则，仅 Spring 托管生命周期 |
| RSK-002 | ServiceLoader 无法注入 Spring Bean | 中 | AgentSpiBootstrap 静态注入 + 编程式 register 兜底 |
| RSK-003 | H2 测试方言与 MySQL 生产方言差异（MEDIUMTEXT 等） | 中 | 测试 schema 用 TEXT，DDL 保留 MySQL 原生 |
| RSK-004 | Shiro 在测试上下文未初始化 | 中 | ShiroTestUtils stub Subject |
| RSK-005 | 内核 Runner 全局单例污染测试 | 中 | @DirtiesContext 隔离 |
| RSK-006 | agent-core-java pom 与 RuoYi BOM 版本冲突 | 中 | 引擎 JAR 独立依赖，不纳入 BOM |
| RSK-007 | 动态表合并为单表后查询性能 | 低 | session_id 列加索引 |

---

## 11. 产物清单

| 产物 | 路径 | 说明 |
|---|---|---|
| 需求规格文档 | yoskills/common/agent-java-server/requirements-spec.md | 本文档 |
| 设计文档 | yoskills/common/agent-java-server/design.md | 含架构/模块映射/DB/核心类/集成 |
| 测试计划文档 | yoskills/common/agent-java-server/test-plan.md | 含 L1-L5 测试用例与验收标准 |

---

## 12. 变更记录

| 版本 | 日期 | 变更内容 | 作者 |
|---|---|---|---|
| v1.0 | 2026-07-29 | 初版，基于 brainstorming 流程与用户确认生成 | TRAE |
