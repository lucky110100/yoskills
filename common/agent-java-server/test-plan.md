# agent-core-java 重构测试计划文档

| 项目 | 内容 |
|------|------|
| 文档名称 | agent-core-java 重构为 RuoYi 子模块测试计划 |
| 版本 | v1.0 |
| 日期 | 2026-07-29 |
| 输出目录 | yoskills/common/agent-java-server |
| 关联文档 | requirements-spec.md（需求规格）、design.md（设计文档） |
| 对应需求 | 原始需求 #4：测试重构后的代码，确保其功能正常 |
| 产物形式 | 仅设计（含测试用例设计，不生成测试脚本） |

---

## 目录

- [1. 测试目标](#1-测试目标)
- [2. 测试分层与范围](#2-测试分层与范围)
- [3. 测试环境与数据准备](#3-测试环境与数据准备)
- [4. 测试用例设计](#4-测试用例设计)
- [5. 测试框架与命令](#5-测试框架与命令)
- [6. 验收标准](#6-验收标准)
- [7. 风险与对策](#7-风险与对策)
- [8. 测试用例汇总表](#8-测试用例汇总表)

---

## 1. 测试目标

验证重构后 agent-core-java 作为 RuoYi 子模块的功能正确性，覆盖四个层面：
1. **持久化层**：MyBatis Entity/Mapper/XML 与 DDL 表结构的一致性、CRUD 正确性
2. **SPI 桥接层**：内核 `ServiceLoader` 能正确发现并调用 MyBatis 后端实现，数据双向同步正确
3. **业务暴露层**：Controller 在 Shiro 鉴权下返回正确的 `AjaxResult`/`TableDataInfo`，分页生效
4. **内核集成层**：`DeepAgent.invoke/stream` 通过 Adapter 在 RuoYi 容器内正常运行，生命周期由 Spring 托管

---

## 2. 测试分层与范围

| 层级 | 类型 | 范围 | 占比 |
|---|---|---|---|
| L1 | 单元测试（Mapper） | 15 个 Mapper 的 CRUD + 条件查询 + 动态 SQL | 30% |
| L2 | 单元测试（Service） | 8 个 ServiceImpl 的业务逻辑（含字段映射、`SecurityUtils` mock） | 25% |
| L3 | 集成测试（SPI 桥接） | 3 个 Provider 的 ServiceLoader 发现 + adapter 双向同步 | 20% |
| L4 | 集成测试（Controller + Shiro） | 8 个 Controller 的权限校验 + 返回结构 + PageHelper 分页 | 15% |
| L5 | 集成测试（内核端到端） | `DeepAgent.invoke/stream` 经 Adapter 在 Spring 容器内运行 | 10% |

### 不纳入测试范围

- 内核 `com.openjiuwen.*` 自身的 Reactor/Pregel/中断恢复逻辑（保留原有测试，不重复测）
- 向量库（Milvus/Chroma）、Redis、对象存储（无关系型重构）
- RuoYi 自身的 sys_* 业务（宿主既有测试）

---

## 3. 测试环境与数据准备

### 3.1 数据库

- **单元/集成测试**：H2 内存数据库（与 agent-core-java 现有 `h2.version=2.2.224` 一致）
- **端到端测试**：Testcontainers PostgreSQL（与 `testcontainers.version=1.21.3` 一致）

### 3.2 Spring 上下文

- `@SpringBootTest` 加载精简配置类（仅 agent 模块 + ruoyi-common 子集，排除 Shiro/Druid 全量启动）
- 用 `@TestPropertySource` 指向测试 `application-test.yml`

### 3.3 Shiro mock

- 用 `ShiroTestUtils` / `SubjectStub` 设置当前用户为 `admin`，使 `SecurityUtils.getUsername()` 返回稳定值

### 3.4 测试数据

- 每个 Mapper 配套 `*MapperTest-data.sql` 初始化 5-10 条记录

### 3.5 MyBatis 映射验证

- `mybatis-config-test.xml` 与宿主一致（不开驼峰自动转换），确保 XML `resultMap` 显式映射被测到

### 3.6 测试资源位置

```
ruoyi-agent/src/test/
├── java/com/ruoyi/agent/
│   ├── mapper/        # L1
│   ├── service/       # L2
│   ├── spi/           # L3
│   ├── controller/    # L4
│   └── e2e/           # L5
└── resources/
    ├── mapper/agent/           # 测试用 Mapper XML（可简化）
    ├── application-test.yml
    ├── schema-h2.sql           # 建表脚本（从设计文档 DDL 转 H2 方言）
    └── data/                   # 测试数据 SQL
```

---

## 4. 测试用例设计

### 4.1 L1 — Mapper 单元测试

#### AgentTodoMapperTest

| 用例 ID | 用例名 | 前置条件 | 操作 | 预期结果 |
|---|---|---|---|---|
| UT-TODO-001 | 插入待办 | 表空 | `insertTodo(AgentTodo)` | 返回 1，`selectTodoById` 能查到，`create_by` 为当前用户 |
| UT-TODO-002 | 条件查询-按 session | 已插入 3 条同 session | `selectTodoList(todo.setSessionId)` | 返回 3 条，`del_flag='0'` |
| UT-TODO-003 | 条件查询-按 status | 已插入 TODO/IN_PROGRESS 各 1 条 | `selectTodoList(todo.setStatus="TODO")` | 返回 1 条 |
| UT-TODO-004 | 更新状态 | 存在 1 条 | `updateTodoStatus(todoId,"DONE","summary")` | 返回 1，`status=DONE`，`result_summary` 非空 |
| UT-TODO-005 | 逻辑删除 | 存在 1 条 | `deleteTodoByIds([id])` | `del_flag='2'`，`selectTodoList` 不返回 |
| UT-TODO-006 | 多租户隔离 | tenantA、tenantB 各 2 条 | `selectTodoBySession(sid, "tenantA")` | 仅返回 tenantA 的 2 条 |
| UT-TODO-007 | resultMap 映射 | 已插入含全字段记录 | `selectTodoById` | 驼峰字段正确映射（`todoId→todo_id`），无 null |

#### AgentSessionMapperTest（代表性）

| 用例 ID | 用例名 | 操作 | 预期 |
|---|---|---|---|
| UT-SESSION-001 | 插入会话 | `insertSession` | 返回 1，`session_id` 唯一 |
| UT-SESSION-002 | 按类型查 | `selectSessionList(type="agent")` | 仅返回 agent 类型 |
| UT-SESSION-003 | 更新状态 | `updateSessionStatus` | 状态变更生效 |

（其余 13 个 Mapper 的用例模式同上：插入/条件查询/更新/逻辑删除/多租户/resultMap 映射，每个 Mapper 5-7 条用例）

### 4.2 L2 — Service 单元测试

#### TodoServiceImplTest

| 用例 ID | 用例名 | 操作 | 预期 |
|---|---|---|---|
| UT-SVC-TODO-001 | 插入填充创建者 | mock `SecurityUtils.getUsername()="admin"`，调 `insertTodo` | Mapper 收到的对象 `createBy="admin"` |
| UT-SVC-TODO-002 | 更新填充更新者 | mock 用户，调 `updateTodo` | `updateBy="admin"` |
| UT-SVC-TODO-003 | 事务回滚 | mock Mapper 抛异常，调 `insertTodo` | 事务回滚，无半提交 |
| UT-SVC-TODO-004 | 字段映射 | 调 `selectTodoList` | 返回 `List<AgentTodo>`，字段无丢失 |
| UT-SVC-TODO-005 | 批量删除 | 调 `deleteTodoByIds([1,2,3])` | 3 条 `del_flag='2'` |

（其余 7 个 Service 用例模式同上：创建者填充/更新者填充/事务/字段映射/批量操作）

### 4.3 L3 — SPI 桥接集成测试（核心）

| 用例 ID | 用例名 | 操作 | 预期 |
|---|---|---|---|
| IT-SPI-001 | ServiceLoader 发现 Provider | `ServiceLoader.load(TodoStorageProvider.class)` | 返回 `MyBatisTodoStorageProvider`，`typeName()="mybatis"` |
| IT-SPI-002 | ApplicationContext 注入 | 启动 `AgentSpiBootstrap` | `MyBatisTodoStorageProvider.applicationContext` 非空 |
| IT-SPI-003 | 内核调用走 DB | 配置 `todo-storage-type=mybatis`，内核 `TodoTool` 执行 `load` | `agent_todo` 表被查询（SQL 日志验证），返回 DB 数据 |
| IT-SPI-004 | 双向同步-写入 | `TodoStorage.save(sessionId, items)` | DB 中旧记录被删，新记录插入（`depends_on` JSON 正确） |
| IT-SPI-005 | 双向同步-读取 | DB 插入 2 条，`TodoStorage.load` | 返回 `List<TodoItem>`，字段映射正确（`TodoStatus` 枚举正确） |
| IT-SPI-006 | KV Provider 发现 | `KVStoreFactory.create("mybatis", conf)` | 返回 `MyBatisKVStoreProvider` 实例，`set/get/delete` 命中 `agent_kv_store` |
| IT-SPI-007 | 租户 key 解析 | `TenantContext.tenantId="t1"`，`kvStore.set("k","v")` | 实际写入 key 含租户前缀（如 `t1:k`） |
| IT-SPI-008 | Session Store Provider | `ServiceLoader.load(SessionStoreProvider.class)` | 返回 `MyBatisSessionStoreProvider` |
| IT-SPI-009 | KV 字段命名验证 | `kvStore.set("key1","val1")` | DB `store_key="key1"`，无单字符字段 |
| IT-SPI-010 | 删除-删除 | `TodoStorage.delete(sessionId)` | DB 该 session 记录 `del_flag='2'` |

### 4.4 L4 — Controller + Shiro 集成测试

| 用例 ID | 用例名 | 前置 | 操作 | 预期 |
|---|---|---|---|---|
| IT-CTRL-001 | 无权限拒绝 | 未授予 `agent:todo:list` | GET `/agent/todo/list` | 返回 403/未授权 |
| IT-CTRL-002 | 列表分页 | 授予权限，DB 25 条 | GET `/agent/todo/list?pageNum=1&pageSize=10` | `TableDataInfo.total=25`，`rows.size=10` |
| IT-CTRL-003 | 新增 | 授予 `agent:todo:add` | POST `/agent/todo` | `AjaxResult.code=200`，DB 新增 1 条 |
| IT-CTRL-004 | 修改 | 授予 `agent:todo:edit` | PUT `/agent/todo` | `code=200`，DB 更新 |
| IT-CTRL-005 | 删除 | 授予 `agent:todo:remove` | DELETE `/agent/todo/1,2` | `code=200`，DB 2 条 `del_flag='2'` |
| IT-CTRL-006 | 操作日志 | 授予权限 | POST 后检查 `sys_oper_log` | 新增一条 `title="Agent待办"` 的日志（`@Log` 生效） |
| IT-CTRL-007 | 详情查询 | 授予 `agent:todo:query` | GET `/agent/todo/1` | `AjaxResult` 含 `data` 字段 |
| IT-CTRL-008 | 同步调用 | 授予 `agent:invoke:sync` | POST `/agent/invoke` | `AjaxResult` 含执行结果 |
| IT-CTRL-009 | 流式调用 | 授予 `agent:invoke:stream` | GET `/agent/stream` | 返回 `SseEmitter`，能收到 chunk |

### 4.5 L5 — 内核端到端集成测试

| 用例 ID | 用例名 | 操作 | 预期 |
|---|---|---|---|
| IT-E2E-001 | DeepAgent 同步调用 | `DeepAgentAdapter.create` + `invoke(inputs)` | 返回 `Map` 含 `output`，无异常 |
| IT-E2E-002 | 流式调用 | `DeepAgentAdapter.stream(inputs)` | 返回 `Iterator`，能迭代出 ≥1 个 chunk |
| IT-E2E-003 | Runner Bean 生命周期 | Spring 容器关闭 | `Runner.resourceMgr` 被 release（`@Bean(destroyMethod="close")` 生效） |
| IT-E2E-004 | 子代理创建 | `DeepAgent.createSubagent("code_agent", sid)` | 返回子 `DeepAgent`，配置正确 |
| IT-E2E-005 | TodoTool 端到端 | DeepAgent 执行中使用 TodoTool | `agent_todo` 表有记录变更（验证内核工具实际走 DB） |
| IT-E2E-006 | 中断恢复 | 调用 invoke 触发中断，再恢复 | `agent_checkpoint` 表有检查点记录，恢复后继续执行 |
| IT-E2E-007 | 多租户隔离端到端 | 两个租户并发 invoke | 各自工作区/数据隔离，无串扰 |

---

## 5. 测试框架与命令

### 5.1 测试框架

| 框架 | 版本来源 | 用途 |
|---|---|---|
| JUnit 5 | agent-core-java 已有 `junit.version=5.10.2` | 测试运行器 |
| Mockito | agent-core-java 已有 `mockito.version=5.2.0` | mock Mapper/SecurityUtils |
| AssertJ | agent-core-java 已有 `assertj.version=3.25.3` | 流式断言 |
| Spring Boot Test | RuoYi 4.0.6 已有 | `@SpringBootTest` 集成测试 |
| Testcontainers | agent-core-java 已有 `testcontainers.version=1.21.3` | L5 PostgreSQL 容器 |

### 5.2 测试位置

`ruoyi-agent/src/test/java/com/ruoyi/agent/`

### 5.3 测试命令

| 命令 | 用途 |
|---|---|
| `mvn test -pl ruoyi-agent -am` | 仅 agent 模块单测 |
| `mvn test -pl ruoyi-agent -Dgroups=integration` | 集成测试（用 JUnit 5 Tag） |
| `mvn test -pl ruoyi-agent,agent-core-java -am` | 全量（含引擎） |
| `mvn test jacoco:report -pl ruoyi-agent` | 覆盖率报告 |

### 5.4 JUnit 5 Tag 划分

| Tag | 对应层级 |
|---|---|
| `@Tag("unit")` | L1, L2 |
| `@Tag("integration")` | L3, L4, L5 |

### 5.5 覆盖率目标

| 模块/层 | 覆盖率目标 |
|---|---|
| ruoyi-agent 整体 | ≥ 70% |
| SPI 桥接层（adapter + spi） | ≥ 90% |
| Mapper 层 | ≥ 80% |
| Controller 层 | ≥ 70% |

---

## 6. 验收标准

| 验收项 | 标准 |
|---|---|
| 编译 | `mvn clean compile -pl ruoyi-agent,agent-core-java -am` 成功，无报错 |
| 单元测试 | L1+L2 全部通过，覆盖率达标 |
| SPI 桥接 | L3 全部通过，IT-SPI-003/005 证明内核实际走 DB |
| Controller | L4 全部通过，权限校验生效，分页正确 |
| 端到端 | L5 全部通过，DeepAgent 在 Spring 容器内可调用 |
| 数据完整性 | 逻辑删除生效，多租户隔离生效，字段映射无丢失 |
| 字段命名 | 无单字符字段（IT-SPI-009 验证） |
| 无回归 | agent-core-java 原有测试（`mvn test -pl agent-core-java`）仍全绿 |

---

## 7. 风险与对策

| 风险 | 对策 |
|---|---|
| ServiceLoader 无法注入 Spring Bean | 用 `AgentSpiBootstrap` 静态注入 + 编程式 `register` 兜底 |
| H2 与 MySQL 方言差异（如 `MEDIUMTEXT`） | 测试 schema 用 `TEXT`，DDL 文档保留 MySQL 原生类型 |
| Shiro 在测试上下文未初始化 | 用 `ShiroTestUtils` stub `Subject`，或 `@SpringBootTest` 含 ShiroConfig |
| Reactor 异步测试不稳定 | L5 用 AssertJ `awaitility` 或 `block()` 等待完成，超时 30s |
| 内核 Runner 全局单例污染测试 | `@DirtiesContext` 隔离 + 每测试重建 Bean |
| LLM API 调用（DeepAgent 真实调用）需网络 | L5 用 MockWebServer（agent-core-java 已有 `mockwebserver`）mock LLM 响应 |

---

## 8. 测试用例汇总表

| 层级 | 模块 | 用例数（预估） |
|---|---|---|
| L1 | 15 个 Mapper | 约 90 条（每 Mapper 5-7 条） |
| L2 | 8 个 Service | 约 40 条（每 Service 5 条） |
| L3 | SPI 桥接 | 10 条 |
| L4 | Controller + Shiro | 9 条 |
| L5 | 端到端 | 7 条 |
| **合计** | — | **约 156 条** |

---

## 9. 变更记录

| 版本 | 日期 | 变更内容 | 作者 |
|---|---|---|---|
| v1.0 | 2026-07-29 | 初版，含 L1-L5 五层测试用例与验收标准 | TRAE |
