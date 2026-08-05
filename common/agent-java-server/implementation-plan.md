# agent-core-java 重构为 RuoYi 子模块实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 agent-core-java 重构为可被 RuoYi 工程集成的子模块 ruoyi-agent，采用方案 A 渐进适配层（保留 Reactor 内核 + 重写持久化与暴露层）。

**Architecture:** 三层架构——保留 `com.openjiuwen` 引擎内核（仅 Spring 托管生命周期）；新建 `com.ruoyi.agent` 适配层（Entity/Mapper/Service/Controller/Adapter/SPI/Config）；通过 Adapter 桥接调用内核 API，通过实现内核 SPI 接口使内核无感知走 DB。

**Tech Stack:** Java 17 + Spring Boot 4.0.6 + Jakarta + MyBatis（原生）+ Druid + PageHelper + Apache Shiro 2.2.0 + EhCache + SLF4J/Logback。不引入 Spring Security/JWT/Redis（与宿主一致）。

## Global Constraints

- Java 17 + Jakarta 命名空间（`jakarta.*`），禁止 `javax.*`
- 鉴权用 Apache Shiro `@RequiresPermissions`，禁止 Spring Security/JWT
- ORM 用 MyBatis 原生（非 MyBatis-Plus），手写 XML，分页用 PageHelper（`startPage()`）
- 实体跟随 ruoyi-system 风格：显式 getter/setter，不用 Lombok
- 内核 `com.openjiuwen` Reactor/Pregel/中断恢复/流式输出不改
- ruoyi-agent 仅依赖 ruoyi-common + agent-core-java，禁止反向依赖 framework/system/admin
- 线程池禁止 Executors.newCachedThreadPool/newFixedThreadPool（遵循 X.CON.06）
- Logger 为 `private static final`（G.LOG.01/02）
- 字段命名用完整单词，禁止单字符字段（如 store_key 而非 k）
- 参考文档：设计文档 design.md（同目录），含全部 DDL/类签名/XML 片段

## File Structure

新建子模块 `ruoyi-agent/`，包结构（详见 design.md §2.2）：
```
ruoyi-agent/
├── pom.xml
├── src/main/java/com/ruoyi/agent/
│   ├── controller/  (8 Controller)
│   ├── service/ + impl/  (8 Service)
│   ├── mapper/  (15 Mapper)
│   ├── domain/  (15 Entity)
│   ├── adapter/  (DeepAgent/Session/Memory/Team/SubAgent/TodoStorage Adapter)
│   ├── spi/  (3 Provider)
│   └── config/  (AgentEngineConfig/Properties/SpiBootstrap)
├── src/main/resources/
│   ├── mapper/agent/  (15 Mapper.xml)
│   ├── META-INF/services/  (3 SPI 注册文件)
│   └── application-agent.yml
└── src/test/java/com/ruoyi/agent/  (L1-L5 测试)
```
修改文件：RuoYi 根 `pom.xml`、`ruoyi-admin/pom.xml`、`ruoyi-admin/src/main/resources/application.yml`。

---

## Phase 1: 工程脚手架与 Maven 集成

### Task 1: 创建 ruoyi-agent 模块脚手架

**Files:**
- Create: `ruoyi-agent/pom.xml`
- Create: `ruoyi-agent/.gitignore`
- Create: `ruoyi-agent/src/main/java/com/ruoyi/agent/.gitkeep`
- Create: `ruoyi-agent/src/main/resources/.gitkeep`
- Create: `ruoyi-agent/src/test/java/com/ruoyi/agent/.gitkeep`

**Interfaces:**
- Produces: `com.ruoyi:ruoyi-agent:4.8.3` Maven 坐标，供后续 Task 3 引入

- [ ] **Step 1: 创建 pom.xml**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0
         http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <parent>
        <groupId>com.ruoyi</groupId>
        <artifactId>ruoyi</artifactId>
        <version>4.8.3</version>
    </parent>
    <artifactId>ruoyi-agent</artifactId>
    <packaging>jar</packaging>
    <description>agent 业务适配层（基于 RuoYi 规范封装 agent-core-java 引擎）</description>

    <dependencies>
        <dependency>
            <groupId>com.ruoyi</groupId>
            <artifactId>ruoyi-common</artifactId>
        </dependency>
        <dependency>
            <groupId>com.openjiuwen</groupId>
            <artifactId>agent-core-java</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-test</artifactId>
            <scope>test</scope>
        </dependency>
        <dependency>
            <groupId>com.h2database</groupId>
            <artifactId>h2</artifactId>
            <scope>test</scope>
        </dependency>
    </dependencies>

    <build>
        <resources>
            <resource>
                <directory>src/main/resources</directory>
                <includes>
                    <include>mapper/**/*.xml</include>
                    <include>META-INF/services/**</include>
                    <include>application-agent.yml</include>
                </includes>
            </resource>
        </resources>
    </build>
</project>
```

- [ ] **Step 2: 创建 .gitkeep 与 .gitignore**

`ruoyi-agent/.gitignore`：
```
target/
*.class
.idea/
*.iml
```

创建三个空 `.gitkeep` 文件保证目录结构。

- [ ] **Step 3: 验证模块可被 Maven 识别**

Run: `mvn -pl ruoyi-agent validate -DskipTests` (在 D:\jiuwen\main\ruoyi 下)
Expected: BUILD SUCCESS（此时 ruoyi-agent 尚未注册到父 pom，需先做 Task 2）

注：此步先创建文件，验证留到 Task 2 完成后统一进行。

- [ ] **Step 4: Commit**

```bash
cd D:\jiuwen\main\ruoyi
git add ruoyi-agent/
git commit -m "chore(agent): scaffold ruoyi-agent module"
```

### Task 2: RuoYi 根 pom.xml 注册 agent-core-java 与 ruoyi-agent

**Files:**
- Modify: `D:\jiuwen\main\ruoyi\pom.xml`

**Interfaces:**
- Consumes: Task 1 的 ruoyi-agent 模块
- Produces: 父工程识别两个新子模块 + 引擎版本属性 `${agent.engine.version}`

- [ ] **Step 1: 在 `<properties>` 增加 agent 引擎版本**

在 `D:\jiuwen\main\ruoyi\pom.xml` 的 `<properties>` 块内追加（与现有属性并列）：
```xml
        <agent.engine.version>0.1.13</agent.engine.version>
```

- [ ] **Step 2: 在 `<modules>` 增加两个子模块**

找到 `<modules>` 块，在末尾追加（保留现有 6 个模块）：
```xml
        <module>agent-core-java</module>
        <module>ruoyi-agent</module>
```

注：`agent-core-java` 目录需位于 `D:\jiuwen\main\ruoyi\agent-core-java`。若实际在 `D:\jiuwen\main\agent-core-java`，则改为 `<module>../agent-core-java</module>`。先检查路径：

Run: `if exist D:\jiuwen\main\ruoyi\agent-core-java (echo LOCAL) else (echo PARENT)`
Expected: PARENT（引擎在父目录）

根据结果使用 `<module>../agent-core-java</module>`。

- [ ] **Step 3: 在 `<dependencyManagement>` 声明引擎坐标**

在 `<dependencyManagement><dependencies>` 块内追加：
```xml
        <dependency>
            <groupId>com.openjiuwen</groupId>
            <artifactId>agent-core-java</artifactId>
            <version>${agent.engine.version}</version>
        </dependency>
```

- [ ] **Step 4: 验证父工程聚合编译**

Run: `mvn validate -DskipTests` (在 D:\jiuwen\main\ruoyi)
Expected: BUILD SUCCESS，输出含 `agent-core-java`、`ruoyi-agent` 模块

- [ ] **Step 5: Commit**

```bash
cd D:\jiuwen\main\ruoyi
git add pom.xml
git commit -m "build(root): register agent-core-java and ruoyi-agent modules"
```

### Task 3: ruoyi-admin 引入 ruoyi-agent 依赖

**Files:**
- Modify: `D:\jiuwen\main\ruoyi\ruoyi-admin\pom.xml`

**Interfaces:**
- Consumes: Task 1/2 的 ruoyi-agent 模块
- Produces: ruoyi-agent 被 admin 引入，启动时被 `@SpringBootApplication` 扫描

- [ ] **Step 1: 在 ruoyi-admin 的 `<dependencies>` 增加依赖**

在 `D:\jiuwen\main\ruoyi\ruoyi-admin\pom.xml` 的 `<dependencies>` 块内追加：
```xml
        <dependency>
            <groupId>com.ruoyi</groupId>
            <artifactId>ruoyi-agent</artifactId>
        </dependency>
```

- [ ] **Step 2: 验证聚合编译**

Run: `mvn clean compile -DskipTests -pl ruoyi-agent,ruoyi-admin -am` (在 D:\jiuwen\main\ruoyi)
Expected: BUILD SUCCESS（此时 ruoyi-agent 源码为空，仅编译模块）

- [ ] **Step 3: Commit**

```bash
cd D:\jiuwen\main\ruoyi
git add ruoyi-admin/pom.xml
git commit -m "build(admin): depend on ruoyi-agent"
```

### Task 4: 测试基础设施（H2 schema 与测试配置）

**Files:**
- Create: `ruoyi-agent/src/test/resources/application-test.yml`
- Create: `ruoyi-agent/src/test/resources/schema-h2.sql`
- Create: `ruoyi-agent/src/test/resources/mybatis-config-test.xml`

**Interfaces:**
- Produces: 测试用 H2 建表脚本（15 表 H2 方言）+ MyBatis 测试配置，供 L1-L4 测试复用

- [ ] **Step 1: 创建 H2 schema（从 design.md §3 转 H2 方言，MEDIUMTEXT→CLOB）**

将 design.md §3.3-§3.7 的 15 张 CREATE TABLE 转为 H2 方言：`MEDIUMTEXT`→`CLOB`，`sysdate()`→`CURRENT_TIMESTAMP`，移除 `ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`，其余保持。完整 SQL 较长，按 design.md §3 逐表转换，保存为 `schema-h2.sql`。

示例（agent_todo 的 H2 版，其余 14 表同模式转换）：
```sql
CREATE TABLE IF NOT EXISTS agent_todo (
  id BIGINT NOT NULL AUTO_INCREMENT,
  todo_id VARCHAR(64) NOT NULL,
  session_id VARCHAR(128) NOT NULL,
  tenant_id VARCHAR(64),
  content VARCHAR(2048) NOT NULL,
  active_form VARCHAR(2048),
  description VARCHAR(2048),
  status VARCHAR(32) NOT NULL DEFAULT 'TODO',
  priority INT DEFAULT 0,
  selected_model_id VARCHAR(128),
  depends_on VARCHAR(2048),
  result_summary VARCHAR(2048),
  meta_data CLOB,
  del_flag CHAR(1) DEFAULT '0',
  create_by VARCHAR(64) DEFAULT '',
  create_time TIMESTAMP,
  update_by VARCHAR(64) DEFAULT '',
  update_time TIMESTAMP,
  remark VARCHAR(500),
  PRIMARY KEY (id),
  UNIQUE (todo_id)
);
```
（其余 14 表按 design.md §3.4-§3.7 同模式转换，逐一写入 schema-h2.sql）

- [ ] **Step 2: 创建测试 application-test.yml**

```yaml
spring:
  datasource:
    url: jdbc:h2:mem:agent_test;MODE=MySQL;DB_CLOSE_DELAY=-1
    driver-class-name: org.h2.Driver
    username: sa
    password:
  sql:
    init:
      schema-locations: classpath:schema-h2.sql
      mode: always

mybatis:
  typeAliasesPackage: com.ruoyi.agent.domain
  mapperLocations: classpath*:mapper/**/*.xml
  configLocation: classpath:mybatis/mybatis-config-test.xml

agent:
  engine:
    workspace-path: ${java.io.tmpdir}/ruoyi-agent-test
    language: cn
    max-iterations: 5
    todo-storage-type: mybatis
    kv-store-type: mybatis
```

- [ ] **Step 3: 创建 mybatis-config-test.xml**

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<!DOCTYPE configuration PUBLIC "-//mybatis.org//DTD Config 3.0//EN"
        "http://mybatis.org/dtd/mybatis-3-config.dtd">
<configuration>
    <settings>
        <setting name="cacheEnabled" value="true"/>
        <setting name="useGeneratedKeys" value="true"/>
        <setting name="defaultExecutorType" value="SIMPLE"/>
        <setting name="logImpl" value="SLF4J"/>
    </settings>
</configuration>
```

- [ ] **Step 4: Commit**

```bash
cd D:\jiuwen\main\ruoyi
git add ruoyi-agent/src/test/
git commit -m "test(agent): add H2 schema and test config"
```

---

## Phase 2: 数据库 DDL 与 Entity 层

### Task 5: 生产环境 DDL 脚本

**Files:**
- Create: `ruoyi-agent/src/main/resources/sql/agent_schema.sql`
- Create: `ruoyi-agent/src/main/resources/sql/agent_menu.sql`

**Interfaces:**
- Produces: 15 表 MySQL DDL + Shiro 权限菜单 SQL，供部署使用

- [ ] **Step 1: 创建 agent_schema.sql**

将 design.md §3.3-§3.7 的 15 张 MySQL CREATE TABLE 原文（含 ENGINE=InnoDB DEFAULT CHARSET=utf8mb4）复制到 `agent_schema.sql`。这是设计文档已定稿的 DDL，逐字复制，不做修改。

- [ ] **Step 2: 创建 agent_menu.sql**

按 design.md §5.4 的 sys_menu INSERT 模板，为 agent 的一级菜单 + 各二级菜单/按钮权限生成 INSERT 语句。menu_id 用变量或占位注释 `-- TODO: 替换为下一可用ID`，实施时由 DBA 确认。8 个业务模块（todo/session/evolution/team/memory/subagent/skill/invoke+stream）各 1 个 C 菜单 + add/edit/remove/query 4 个 F 按钮。

```sql
-- Agent 一级菜单
INSERT INTO sys_menu(menu_id, menu_name, parent_id, order_num, path, component,
    query, is_frame, is_cache, menu_type, visible, status, perms, icon,
    create_by, create_time, update_by, update_time, remark)
VALUES(@agentMenuId, 'Agent管理', 0, 100, 'agent', NULL, '', 1, 0, 'M', '0', '0',
    'agent:manager', 'fa fa-robot', 'admin', sysdate(), '', NULL, '');

-- 待办任务菜单 + 按钮（其余 7 模块同模式，perms 前缀替换）
INSERT INTO sys_menu VALUES(@todoCId, '待办任务', @agentMenuId, 1, 'todo', 'agent/todo/list',
    '', 1, 0, 'C', '0', '0', 'agent:todo:list', '#', 'admin', sysdate(), '', NULL, '');
INSERT INTO sys_menu VALUES(@todoAddId, '待办新增', @todoCId, 2, '', '', '', 1, 0, 'F', '0', '0',
    'agent:todo:add', '#', 'admin', sysdate(), '', NULL, '');
-- ...edit/remove/query 同模式
-- session/evolution/team/memory/subagent/skill/invoke 同模式，perms 替换为 agent:xxx:yyy
```

- [ ] **Step 3: Commit**

```bash
git add ruoyi-agent/src/main/resources/sql/
git commit -m "feat(agent): add production DDL and menu SQL"
```

### Task 6: Entity 层 - AgentTodo（模板任务）

**Files:**
- Create: `ruoyi-agent/src/main/java/com/ruoyi/agent/domain/AgentTodo.java`

**Interfaces:**
- Produces: `com.ruoyi.agent.domain.AgentTodo extends BaseEntity`，属性对应 agent_todo 表

- [ ] **Step 1: 编写 AgentTodo 实体**

按 design.md §4.2.1 原文复制（含显式 getter/setter，继承 BaseEntity）。完整代码见 design.md §4.2.1。

- [ ] **Step 2: 编译验证**

Run: `mvn compile -pl ruoyi-agent -DskipTests`
Expected: BUILD SUCCESS

- [ ] **Step 3: Commit**

```bash
git add ruoyi-agent/src/main/java/com/ruoyi/agent/domain/AgentTodo.java
git commit -m "feat(agent): add AgentTodo entity"
```

### Task 7: Entity 层 - 其余 14 个实体（批量任务）

**Files:**
- Create: 14 个实体类（见下表）

**Interfaces:**
- Produces: 14 个 `extends BaseEntity` 的实体，属性与对应表字段一一映射

各实体属性从 design.md §3 对应表的字段直接映射（驼峰命名），类型规则：`BIGINT→Long`、`VARCHAR→String`、`TEXT/MEDIUMTEXT→String`、`INT→Integer`、`DATETIME/TIMESTAMP→Date`、`DOUBLE→Double`、`DECIMAL→BigDecimal`、`CHAR(1)→String`。BaseEntity 已提供 createBy/createTime/updateBy/updateTime/delFlag/remark，子类不重复。

| 实体类 | 对应表 | design.md 章节 | 自有属性（除 BaseEntity） |
|---|---|---|---|
| AgentSession | agent_session | §3.4 | sessionId, tenantId, sessionType, status, currentOperatorId, parentSessionId, inputs, outputs |
| AgentCheckpoint | agent_checkpoint | §3.4 | sessionId, namespace, checkpointId, dataType, dataValue, dumpType |
| AgentSessionState | agent_session_state | §3.4 | sessionId, namespace, step, channelValues, pendingBuffer, pendingNode, nodeVersion |
| AgentMessage | agent_message | §3.5 | messageId, userId, scopeId, tenantId, content, sessionId, role, msgTimestamp |
| AgentScopeUser | agent_scope_user | §3.5 | userId, scopeId, tenantId |
| AgentMemoryMeta | agent_memory_meta | §3.5 | tableName, schemaVersion, tenantId |
| AgentTeam | agent_team | §3.6 | teamName, displayName, leaderMemberName, description, prompt, tenantId |
| AgentTeamMember | agent_team_member | §3.6 | memberName, teamName, displayName, agentCard, status, description, executionStatus, mode, tenantId |
| AgentTeamTask | agent_team_task | §3.6 | taskId, sessionId, teamName, title, content, status, assignee, tenantId |
| AgentTeamTaskDep | agent_team_task_dep | §3.6 | taskId, dependsOnTaskId, sessionId, teamName |
| AgentTeamMessage | agent_team_message | §3.6 | messageId, sessionId, teamName, fromMemberName, toMemberName, content, msgTimestamp, isBroadcast, isRead, tenantId |
| AgentTeamMsgRead | agent_team_msg_read | §3.6 | memberName, teamName, sessionId, readAt |
| AgentEvolution | agent_evolution | §3.7 | evolutionId, source, tenantId, context, changePatch, isApplied, score, usageStats, skillVersion |
| AgentModelUsage | agent_model_usage | §3.7 | sessionId, tenantId, modelName, promptTokens, completionTokens, totalTokens, cost |
| AgentKvStore | agent_kv_store | §3.7/§4.2.3 | storeKey, storeValue, namespace, tenantId, expireAt |

- [ ] **Step 1: 按表中属性逐一创建 14 个实体**

每个实体结构同 Task 6 的 AgentTodo：`extends BaseEntity`，`private static final long serialVersionUID = 1L;`，私有字段 + 显式 getter/setter。AgentKvStore 按 design.md §4.2.3 原文。其余按上表属性编写。

- [ ] **Step 2: 编译验证**

Run: `mvn compile -pl ruoyi-agent -DskipTests`
Expected: BUILD SUCCESS，所有实体被 typeAliasesPackage 识别

- [ ] **Step 3: Commit**

```bash
git add ruoyi-agent/src/main/java/com/ruoyi/agent/domain/
git commit -m "feat(agent): add 14 entity classes for all tables"
```

---

## Phase 3: Mapper 层

### Task 8: AgentTodoMapper 接口与 XML（模板任务）

**Files:**
- Create: `ruoyi-agent/src/main/java/com/ruoyi/agent/mapper/AgentTodoMapper.java`
- Create: `ruoyi-agent/src/main/resources/mapper/agent/AgentTodoMapper.xml`
- Create: `ruoyi-agent/src/test/java/com/ruoyi/agent/mapper/AgentTodoMapperTest.java`
- Create: `ruoyi-agent/src/test/resources/mapper/agent/AgentTodoMapper.xml`（测试用，可同主）

**Interfaces:**
- Consumes: Task 6 的 AgentTodo
- Produces: `AgentTodoMapper` 接口（selectTodoById/selectTodoByTodoId/selectTodoList/selectTodoBySession/insertTodo/updateTodo/updateTodoStatus/deleteTodoByIds/deleteTodoBySession/deleteTodoByTodoId）

- [ ] **Step 1: 编写 Mapper 接口**

按 design.md §4.3.1 原文复制 `AgentTodoMapper.java`。

- [ ] **Step 2: 编写 Mapper XML**

按 design.md §4.3.2 原文复制 `AgentTodoMapper.xml`（含 resultMap、selectTodoVo、各 select/insert/update/delete）。注意：H2 测试时 `sysdate()` 不可用，XML 中的 `update_time = sysdate()` 在测试场景改为 `update_time = CURRENT_TIMESTAMP`，或在测试 XML 中覆盖。生产 XML 保留 `sysdate()`。

为兼容，在 XML 中用 `${dbNow}` 占位，并在 application.yml 配置 `mybatis.configuration.variables.dbNow=sysdate()`（MySQL）与 `dbNow=CURRENT_TIMESTAMP`（H2）。或更简单：XML 用 `CURRENT_TIMESTAMP`，MySQL 也支持。

决策：XML 中统一用 `CURRENT_TIMESTAMP`（MySQL 5.6+ 与 H2 均支持），避免方言问题。

- [ ] **Step 3: 编写失败测试**

`AgentTodoMapperTest.java`：
```java
package com.ruoyi.agent.mapper;

import com.ruoyi.agent.domain.AgentTodo;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;
import java.util.List;
import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest
@ActiveProfiles("test")
@Transactional
class AgentTodoMapperTest {

    @Autowired
    private AgentTodoMapper todoMapper;

    @Test
    void insert_and_selectById_shouldReturnSame() {
        AgentTodo todo = new AgentTodo();
        todo.setTodoId("t-001");
        todo.setSessionId("s-1");
        todo.setContent("test content");
        todo.setStatus("TODO");
        todo.setCreateBy("admin");
        int rows = todoMapper.insertTodo(todo);
        assertThat(rows).isEqualTo(1);
        assertThat(todo.getId()).isNotNull();

        AgentTodo found = todoMapper.selectTodoById(todo.getId());
        assertThat(found).isNotNull();
        assertThat(found.getTodoId()).isEqualTo("t-001");
        assertThat(found.getStatus()).isEqualTo("TODO");
        assertThat(found.getDelFlag()).isEqualTo("0");
    }

    @Test
    void selectTodoList_bySession_shouldFilter() {
        AgentTodo t1 = newTodo("t-1", "s-A", "TODO");
        AgentTodo t2 = newTodo("t-2", "s-A", "IN_PROGRESS");
        AgentTodo t3 = newTodo("t-3", "s-B", "TODO");
        todoMapper.insertTodo(t1);
        todoMapper.insertTodo(t2);
        todoMapper.insertTodo(t3);

        AgentTodo q = new AgentTodo();
        q.setSessionId("s-A");
        List<AgentTodo> list = todoMapper.selectTodoList(q);
        assertThat(list).hasSize(2);
    }

    @Test
    void deleteTodoByIds_shouldLogicalDelete() {
        AgentTodo t = newTodo("t-x", "s", "TODO");
        todoMapper.insertTodo(t);
        todoMapper.deleteTodoByIds(new Long[]{t.getId()});
        AgentTodo found = todoMapper.selectTodoById(t.getId());
        assertThat(found).isNull();
    }

    @Test
    void selectTodoBySession_tenantIsolation() {
        AgentTodo a = newTodo("t1", "s1", "TODO");
        a.setTenantId("tenantA");
        AgentTodo b = newTodo("t2", "s1", "TODO");
        b.setTenantId("tenantB");
        todoMapper.insertTodo(a);
        todoMapper.insertTodo(b);
        List<AgentTodo> list = todoMapper.selectTodoBySession("s1", "tenantA");
        assertThat(list).hasSize(1).extracting(AgentTodo::getTenantId).containsOnly("tenantA");
    }

    private AgentTodo newTodo(String todoId, String sessionId, String status) {
        AgentTodo t = new AgentTodo();
        t.setTodoId(todoId);
        t.setSessionId(sessionId);
        t.setContent("c");
        t.setStatus(status);
        t.setCreateBy("admin");
        return t;
    }
}
```

- [ ] **Step 4: 运行测试验证失败（此时 XML 未生效）**

Run: `mvn test -pl ruoyi-agent -Dtest=AgentTodoMapperTest -Dgroups=unit`
Expected: FAIL（注入失败或 SQL 未找到）

注：因用 `@SpringBootTest`，需有引导配置。先创建一个最小测试配置类：
Create: `ruoyi-agent/src/test/java/com/ruoyi/agent/TestApplication.java`
```java
package com.ruoyi.agent;
import org.springframework.boot.autoconfigure.SpringBootApplication;
@SpringBootApplication
public class TestApplication { }
```

- [ ] **Step 5: 拷贝主 XML 到测试资源并运行测试通过**

将 `AgentTodoMapper.xml` 复制到 `src/test/resources/mapper/agent/`（或确认 `classpath*:mapper/**/*.xml` 能扫到主资源；测试 application-test.yml 用 `classpath*:mapper/**/*.xml` 可同时扫主+测试）。

Run: `mvn test -pl ruoyi-agent -Dtest=AgentTodoMapperTest -Dgroups=unit`
Expected: 4 tests PASS

- [ ] **Step 6: Commit**

```bash
git add ruoyi-agent/src/
git commit -m "feat(agent): add AgentTodoMapper with tests"
```

### Task 9: 其余 14 个 Mapper（批量任务）

**Files:**
- Create: 14 个 Mapper 接口 + 14 个 XML

**Interfaces:**
- Consumes: Task 7 的 14 个实体
- Produces: 14 个 Mapper，方法命名遵循 RuoYi 规范（selectXxxById/List/ByXxx、insertXxx、updateXxx、deleteXxxByIds）

每个 Mapper 接口 + XML 按 Task 8 的模式编写：
1. 接口方法：`selectXxxById(Long id)`、`selectXxxList(实体)`、`insertXxx(实体)`、`updateXxx(实体)`、`deleteXxxByIds(Long[])`，多参数用 `@Param`
2. XML：`<resultMap>` 显式映射全部字段（含 BaseEntity 的 delFlag/createBy 等），`<sql id="selectXxxVo">` 带 `where del_flag='0'`，动态 `<if>` 条件，`<insert useGeneratedKeys="true" keyProperty="id">`，`<delete>` 改为逻辑删除 `update set del_flag='2'`
3. 时间函数统一用 `CURRENT_TIMESTAMP`

| Mapper | 实体 | 关键查询方法（除标准 CRUD） |
|---|---|---|
| AgentSessionMapper | AgentSession | selectSessionBySessionId(String) |
| AgentCheckpointMapper | AgentCheckpoint | selectBySessionAndNamespace(@Param sessionId, @Param namespace) |
| AgentSessionStateMapper | AgentSessionState | selectBySessionAndNamespace |
| AgentMessageMapper | AgentMessage | selectByUserAndScope(@Param userId,@Param scopeId) |
| AgentScopeUserMapper | AgentScopeUser | （标准 CRUD） |
| AgentMemoryMetaMapper | AgentMemoryMeta | selectByTableName(String) |
| AgentTeamMapper | AgentTeam | selectTeamByName(String) |
| AgentTeamMemberMapper | AgentTeamMember | selectByTeamName(String) |
| AgentTeamTaskMapper | AgentTeamTask | selectByTeamAndSession(@Param teamName,@Param sessionId) |
| AgentTeamTaskDepMapper | AgentTeamTaskDep | selectByTaskId(String) |
| AgentTeamMessageMapper | AgentTeamMessage | selectByTeamAndSession |
| AgentTeamMsgReadMapper | AgentTeamMsgRead | selectByMemberAndTeam(@Param member,@Param team) |
| AgentEvolutionMapper | AgentEvolution | selectBySource(String) |
| AgentModelUsageMapper | AgentModelUsage | selectBySession(String) |
| AgentKvStoreMapper | AgentKvStore | selectByKeyAndNamespace(@Param key,@Param ns) |

- [ ] **Step 1: 按上表逐个创建 14 个 Mapper 接口 + XML**

参考 Task 8 的 AgentTodoMapper.xml 结构，替换表名/字段/resultMap。每完成一个，编译验证。

- [ ] **Step 2: 为每个 Mapper 编写至少 2 个测试（插入+查询、逻辑删除）**

按 Task 8 Step 3 的测试模式，每个 Mapper 至少覆盖：insert+selectById、deleteByIds 逻辑删除。

- [ ] **Step 3: 运行全部 Mapper 测试**

Run: `mvn test -pl ruoyi-agent -Dtest="*MapperTest" -Dgroups=unit`
Expected: 全部 PASS

- [ ] **Step 4: Commit**

```bash
git add ruoyi-agent/src/
git commit -m "feat(agent): add 14 mappers with XML and tests"
```

---

## Phase 4: Service 层

### Task 10: ITodoService + TodoServiceImpl（模板任务）

**Files:**
- Create: `ruoyi-agent/src/main/java/com/ruoyi/agent/service/ITodoService.java`
- Create: `ruoyi-agent/src/main/java/com/ruoyi/agent/service/impl/TodoServiceImpl.java`
- Create: `ruoyi-agent/src/test/java/com/ruoyi/agent/service/TodoServiceImplTest.java`

**Interfaces:**
- Consumes: Task 8 的 AgentTodoMapper
- Produces: `ITodoService` 接口 + `TodoServiceImpl` 实现

- [ ] **Step 1: 编写 ITodoService 接口**

按 design.md §4.4.1 原文复制。

- [ ] **Step 2: 编写 TodoServiceImpl**

按 design.md §4.4.2 原文复制（含 `@Service`、`@Autowired AgentTodoMapper`、`@Transactional`、`SecurityUtils.getUsername()`）。注意：design.md 中 TodoServiceImpl 还 `@Autowired TodoStorageAdapter`，此 Task 暂不注入（Task 16 才创建），先去掉该字段，后续 Task 补回。

- [ ] **Step 3: 编写失败测试**

```java
package com.ruoyi.agent.service;
import com.ruoyi.agent.domain.AgentTodo;
import com.ruoyi.agent.mapper.AgentTodoMapper;
import com.ruoyi.agent.service.impl.TodoServiceImpl;
import com.ruoyi.common.utils.SecurityUtils;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockedStatic;
import org.mockito.junit.jupiter.MockitoExtension;
import java.util.Collections;
import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class TodoServiceImplTest {

    @Mock
    private AgentTodoMapper todoMapper;
    @InjectMocks
    private TodoServiceImpl todoService;

    @Test
    void insertTodo_shouldSetCreateByFromSecurityUtils() {
        try (MockedStatic<SecurityUtils> mocked = mockStatic(SecurityUtils.class)) {
            mocked.when(SecurityUtils::getUsername).thenReturn("admin");
            AgentTodo todo = new AgentTodo();
            todo.setTodoId("t1");
            when(todoMapper.insertTodo(any())).thenReturn(1);
            todoService.insertTodo(todo);
            assertThat(todo.getCreateBy()).isEqualTo("admin");
        }
    }

    @Test
    void selectTodoList_delegatesToMapper() {
        when(todoMapper.selectTodoList(any())).thenReturn(Collections.emptyList());
        assertThat(todoService.selectTodoList(new AgentTodo())).isEmpty();
    }
}
```

- [ ] **Step 4: 运行测试验证通过**

Run: `mvn test -pl ruoyi-agent -Dtest=TodoServiceImplTest -Dgroups=unit`
Expected: 2 tests PASS

注：`SecurityUtils` 是 RuoYi 的 static 方法，Mockito 5+ 支持 `mockStatic`（agent-core-java 已有 mockito-inline 依赖；ruoyi-agent 需在 pom 加 `mockito-inline` test 依赖——在 Task 1 pom 已含 mockito-inline？检查：Task 1 pom 未加，补充）。

补充 pom 依赖：在 ruoyi-agent/pom.xml `<dependencies>` 加：
```xml
        <dependency>
            <groupId>org.mockito</groupId>
            <artifactId>mockito-inline</artifactId>
            <scope>test</scope>
        </dependency>
```

- [ ] **Step 5: Commit**

```bash
git add ruoyi-agent/src/ ruoyi-agent/pom.xml
git commit -m "feat(agent): add ITodoService and TodoServiceImpl with tests"
```

### Task 11: 其余 7 个 Service（批量任务）

**Files:**
- Create: 7 个 IXxxService + 7 个 XxxServiceImpl

**Interfaces:**
- Consumes: Task 9 的对应 Mapper
- Produces: 7 个 Service（Session/Evolution/Team/Memory/SubAgent/Skill/AgentInvoke）

每个 Service 模式同 Task 10：
- 接口 `IXxxService`，方法对应 Mapper
- 实现 `XxxServiceImpl @Service`，注入对应 Mapper，`@Transactional`，insert/update 用 `SecurityUtils.getUsername()` 填充 createBy/updateBy

| Service | 对应 Mapper | 额外依赖（后续 Task 注入） |
|---|---|---|
| ISessionService | AgentSessionMapper+AgentCheckpointMapper+AgentSessionStateMapper | SessionAdapter（Task 14） |
| IEvolutionService | AgentEvolutionMapper+AgentModelUsageMapper | — |
| ITeamService | AgentTeamMapper+AgentTeamMemberMapper+AgentTeamTaskMapper+AgentTeamTaskDepMapper+AgentTeamMessageMapper+AgentTeamMsgReadMapper | TeamAdapter（Task 15） |
| IMemoryService | AgentMessageMapper+AgentScopeUserMapper+AgentMemoryMetaMapper | MemoryAdapter（Task 16） |
| ISubAgentService | （无独立 Mapper，通过 SubAgentAdapter） | SubAgentAdapter（Task 17） |
| ISkillService | （无 Mapper，通过内核 SkillManager） | SkillAdapter（Task 18，设计文档未列，按需补） |
| IAgentInvokeService | （无 Mapper） | DeepAgentAdapter（Task 13） |

- [ ] **Step 1: 按上表创建 7 个 Service 接口 + 实现**

每个实现先只注入 Mapper，Adapter 依赖留到 Phase 5 补入。每个 Service 编写至少 2 个单测（mock Mapper，验证填充 createBy/updateBy + 委托调用）。

- [ ] **Step 2: 运行全部 Service 测试**

Run: `mvn test -pl ruoyi-agent -Dtest="*ServiceImplTest" -Dgroups=unit`
Expected: 全部 PASS

- [ ] **Step 3: Commit**

```bash
git add ruoyi-agent/src/
git commit -m "feat(agent): add 7 service interfaces and impls with tests"
```

---

## Phase 5: Adapter 与 SPI 桥接层（核心）

### Task 12: AgentEngineProperties 配置类

**Files:**
- Create: `ruoyi-agent/src/main/java/com/ruoyi/agent/config/AgentEngineProperties.java`
- Modify: `ruoyi-agent/src/test/resources/application-test.yml`（补 agent.engine.* 已含）

**Interfaces:**
- Produces: `@ConfigurationProperties(prefix="agent.engine")` 的属性类，供各 Adapter 读取

- [ ] **Step 1: 编写 AgentEngineProperties**

按 design.md §4.8.2 原文复制（含 `@Component @ConfigurationProperties(prefix="agent.engine")` + 全部字段 + 显式 getter/setter）。

- [ ] **Step 2: 主配置 application-agent.yml**

Create: `ruoyi-agent/src/main/resources/application-agent.yml`，按 design.md §5.2.1 内容。

- [ ] **Step 3: 编写配置绑定测试**

```java
package com.ruoyi.agent.config;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest
@ActiveProfiles("test")
class AgentEnginePropertiesTest {
    @Autowired private AgentEngineProperties properties;
    @Test void shouldBindFromYaml() {
        assertThat(properties.getWorkspacePath()).isNotBlank();
        assertThat(properties.getTodoStorageType()).isEqualTo("mybatis");
    }
}
```

- [ ] **Step 4: 运行测试通过**

Run: `mvn test -pl ruoyi-agent -Dtest=AgentEnginePropertiesTest -Dgroups=unit`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add ruoyi-agent/src/
git commit -m "feat(agent): add AgentEngineProperties config binding"
```

### Task 13: DeepAgentAdapter

**Files:**
- Create: `ruoyi-agent/src/main/java/com/ruoyi/agent/adapter/DeepAgentAdapter.java`
- Create: `ruoyi-agent/src/main/java/com/ruoyi/agent/config/AgentEngineConfig.java`

**Interfaces:**
- Consumes: Task 12 的 AgentEngineProperties + 内核 `HarnessFactory`/`DeepAgent`/`DeepAgentConfig`/`Workspace`/`Runner`
- Produces: `DeepAgentAdapter`（create/invoke/stream/requestAbort/createSubagent）+ `AgentEngineConfig`（注册 Runner Bean）

- [ ] **Step 1: 编写 AgentEngineConfig**

按 design.md §4.8.1 原文复制（`@Configuration` + `@Bean(destroyMethod="close") Runner runner()` 调用 `Runner.getInstance()`）。

- [ ] **Step 2: 编写 DeepAgentAdapter**

按 design.md §4.6.1 原文复制（`@Component`，注入 AgentEngineProperties，create 用 DeepAgentConfig.builder + Workspace.builder + HarnessFactory.createDeepAgent，invoke/stream 委托 DeepAgent）。

- [ ] **Step 3: 编译验证**

Run: `mvn compile -pl ruoyi-agent -DskipTests`
Expected: BUILD SUCCESS（验证 com.openjiuwen API 可用）

注：若 `HarnessFactory.createDeepAgent(DeepAgentConfig)` 签名与内核不符，查 agent-core-java 实际签名调整。先确认签名：

Run: `grep -rn "public static.*createDeepAgent" D:\jiuwen\main\agent-core-java\src\main\java\com\openjiuwen\harness\factory\`
Expected: 列出 HarnessFactory 的实际方法签名

- [ ] **Step 4: 编写 DeepAgentAdapter 单测（mock HarnessFactory 静态调用）**

因 HarnessFactory 是静态，测试时 mock。简化测试：验证 properties 注入 + create 返回非 null（需 mock LLM 配置，复杂，此 Task 暂跳过单测，留到 L5 端到端验证）。

记录：DeepAgentAdapter 的真实测试在 Phase 9 L5。

- [ ] **Step 5: Commit**

```bash
git add ruoyi-agent/src/main/java/com/ruoyi/agent/
git commit -m "feat(agent): add DeepAgentAdapter and AgentEngineConfig"
```

### Task 14: SessionAdapter

**Files:**
- Create: `ruoyi-agent/src/main/java/com/ruoyi/agent/adapter/SessionAdapter.java`

**Interfaces:**
- Consumes: 内核 `com.openjiuwen.core.session.AgentSessionApi`/`Checkpointer`
- Produces: SessionAdapter（封装会话创建/中断恢复/状态保存，桥接 AgentSessionMapper/AgentCheckpointMapper）

- [ ] **Step 1: 探索内核 AgentSessionApi 实际 API**

Run: `grep -rn "class AgentSessionApi\|interface AgentSessionApi" D:\jiuwen\main\agent-core-java\src\main\java\`
Expected: 找到 AgentSessionApi 类，确认其方法签名

- [ ] **Step 2: 编写 SessionAdapter**

```java
package com.ruoyi.agent.adapter;

import com.openjiuwen.core.session.AgentSessionApi;
import com.ruoyi.agent.mapper.AgentSessionMapper;
import com.ruoyi.agent.mapper.AgentCheckpointMapper;
import com.ruoyi.agent.domain.AgentSession;
import com.ruoyi.agent.domain.AgentCheckpoint;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;
import java.util.List;

@Component
public class SessionAdapter {

    @Autowired
    private AgentSessionMapper sessionMapper;

    @Autowired
    private AgentCheckpointMapper checkpointMapper;

    public AgentSession saveSession(AgentSession session) {
        if (session.getId() == null) {
            sessionMapper.insertSession(session);
        } else {
            sessionMapper.updateSession(session);
        }
        return session;
    }

    public AgentSession findBySessionId(String sessionId) {
        return sessionMapper.selectSessionBySessionId(sessionId);
    }

    public void saveCheckpoint(AgentCheckpoint checkpoint) {
        checkpointMapper.insertCheckpoint(checkpoint);
    }

    public List<AgentCheckpoint> listCheckpoints(String sessionId, String namespace) {
        return checkpointMapper.selectBySessionAndNamespace(sessionId, namespace);
    }
}
```

注：实际 AgentSessionApi 的桥接方法（创建内核会话对象）需根据 Step 1 探索的 API 补充。此 Task 先实现 DB 持久化部分，内核会话桥接留待 L5 验证时完善。

- [ ] **Step 3: 补全 AgentSessionMapper.selectSessionBySessionId 方法**

确认 Task 9 的 AgentSessionMapper 含 `selectSessionBySessionId(String)` 方法，若无则补。

- [ ] **Step 4: 编译验证**

Run: `mvn compile -pl ruoyi-agent -DskipTests`
Expected: BUILD SUCCESS

- [ ] **Step 5: Commit**

```bash
git add ruoyi-agent/src/
git commit -m "feat(agent): add SessionAdapter"
```

### Task 15: TeamAdapter / MemoryAdapter / SubAgentAdapter

**Files:**
- Create: 3 个 Adapter（TeamAdapter/MemoryAdapter/SubAgentAdapter）

**Interfaces:**
- Consumes: 各对应 Mapper + 内核运行时（agentteams/LongTermMemory/SubAgentRegistry）
- Produces: 3 个 Adapter，封装各自领域 DB 持久化 + 内核调用

- [ ] **Step 1: 探索内核 API**

Run（三个并行）：
- `grep -rn "class TeamDatabase\|interface.*Team" D:\jiuwen\main\agent-core-java\src\main\java\com\openjiuwen\agentteams\`
- `grep -rn "class LongTermMemory\|public.*registerStore" D:\jiuwen\main\agent-core-java\src\main\java\com\openjiuwen\core\memory\`
- `grep -rn "class SubAgentRegistry\|static.*build" D:\jiuwen\main\agent-core-java\src\main\java\com\openjiuwen\harness\subagents\`

- [ ] **Step 2: 编写 3 个 Adapter**

按 design.md §4.6 模式（参考 TodoStorageAdapter §4.6.2 的实现内核 SPI 模式）：每个 `@Component`，注入对应 Mapper，提供 DB 持久化方法，内核运行时调用部分先留 TODO 注释（标注"实际 API 见 Step 1 探索结果"），L5 端到端验证时补全。

- [ ] **Step 3: 编译验证**

Run: `mvn compile -pl ruoyi-agent -DskipTests`
Expected: BUILD SUCCESS

- [ ] **Step 4: Commit**

```bash
git add ruoyi-agent/src/main/java/com/ruoyi/agent/adapter/
git commit -m "feat(agent): add Team/Memory/SubAgent adapters"
```

### Task 16: TodoStorageAdapter（SPI 桥接核心）

**Files:**
- Create: `ruoyi-agent/src/main/java/com/ruoyi/agent/adapter/TodoStorageAdapter.java`
- Create: `ruoyi-agent/src/main/java/com/ruoyi/agent/spi/MyBatisTodoStorageProvider.java`
- Create: `ruoyi-agent/src/main/resources/META-INF/services/com.openjiuwen.harness.tools.TodoStorageProvider`
- Modify: `ruoyi-agent/src/main/java/com/ruoyi/agent/service/impl/TodoServiceImpl.java`（补回 TodoStorageAdapter 注入）

**Interfaces:**
- Consumes: 内核 `TodoStorage` SPI 接口 + `TodoItem`/`TodoStatus` + Task 8 的 AgentTodoMapper
- Produces: `TodoStorageAdapter implements TodoStorage`，使内核 TodoTool 走 DB

- [ ] **Step 1: 探索内核 TodoStorage/TodoItem/TodoStatus 实际 API**

Run（三个并行）：
- `grep -rn "interface TodoStorage" D:\jiuwen\main\agent-core-java\src\main\java\`
- `grep -rn "class TodoItem" D:\jiuwen\main\agent-core-java\src\main\java\`
- `grep -rn "enum TodoStatus" D:\jiuwen\main\agent-core-java\src\main\java\`
Expected: 确认实际方法签名与字段名

- [ ] **Step 2: 编写 TodoStorageAdapter**

按 design.md §4.6.2 原文，但根据 Step 1 探索的实际 API 调整方法签名与字段映射。核心：`load(sessionId, ctx)` 查 DB、`save` 先删后插、`delete` 逻辑删、`toAgentTodo`/`toTodoItem` 双向映射。

- [ ] **Step 3: 编写 MyBatisTodoStorageProvider**

按 design.md §4.7.1 原文（`typeName()="mybatis"`，`create` 从静态 applicationContext 取 TodoStorageAdapter Bean）。

- [ ] **Step 4: 创建 META-INF/services 注册文件**

文件名：`com.openjiuwen.harness.tools.TodoStorageProvider`
内容（单行）：
```
com.ruoyi.agent.spi.MyBatisTodoStorageProvider
```

- [ ] **Step 5: 补回 TodoServiceImpl 的 TodoStorageAdapter 注入**

在 Task 10 的 TodoServiceImpl 补回 `@Autowired private TodoStorageAdapter todoStorageAdapter;`（design.md §4.4.2 原文）。

- [ ] **Step 6: 编写 SPI 桥接集成测试**

```java
package com.ruoyi.agent.spi;
import com.openjiuwen.harness.tools.TodoStorage;
import com.openjiuwen.harness.tools.TodoStorageProvider;
import com.openjiuwen.harness.tools.TodoItem;
import com.ruoyi.agent.domain.AgentTodo;
import com.ruoyi.agent.mapper.AgentTodoMapper;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;
import java.util.List;
import java.util.ServiceLoader;
import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest
@ActiveProfiles("test")
@Transactional
class MyBatisTodoStorageProviderTest {

    @Autowired
    private AgentTodoMapper todoMapper;
    @Autowired
    private TodoStorage todoStorage;  // 通过 SPI 注入

    @Test
    void serviceLoader_shouldDiscoverProvider() {
        ServiceLoader<TodoStorageProvider> loaders = ServiceLoader.load(TodoStorageProvider.class);
        boolean found = false;
        for (TodoStorageProvider p : loaders) {
            if (p instanceof MyBatisTodoStorageProvider) found = true;
        }
        assertThat(found).isTrue();
    }

    @Test
    void save_then_load_shouldRoundTrip() {
        TodoItem item = TodoItem.builder()
                .id("t-spi-1").content("c").status(
                    com.openjiuwen.harness.tools.TodoStatus.TODO).build();
        todoStorage.save("s-spi", List.of(item), null);

        List<TodoItem> loaded = todoStorage.load("s-spi", null);
        assertThat(loaded).hasSize(1);
        assertThat(loaded.get(0).getId()).isEqualTo("t-spi-1");
    }

    @Test
    void delete_shouldLogicalDelete() {
        TodoItem item = TodoItem.builder().id("t-d").content("c")
                .status(com.openjiuwen.harness.tools.TodoStatus.TODO).build();
        todoStorage.save("s-d", List.of(item), null);
        todoStorage.delete("s-d", null);
        List<AgentTodo> remaining = todoMapper.selectTodoBySession("s-d", null);
        assertThat(remaining).isEmpty();
    }
}
```

注：`TodoItem.builder()`/`TodoStatus` 的实际 API 按 Step 1 探索调整。`@Autowired TodoStorage` 注入需内核通过 SPI 创建后注册为 Bean——实际可能需 `AgentSpiBootstrap`（Task 19）先完成。若注入失败，改为 `@Autowired MyBatisTodoStorageProvider` 直接测试。

- [ ] **Step 7: 运行测试**

Run: `mvn test -pl ruoyi-agent -Dtest=MyBatisTodoStorageProviderTest -Dgroups=integration`
Expected: 3 tests PASS（IT-SPI-001/004/005）

注：此 Task 依赖 Task 19 的 AgentSpiBootstrap 才能让 `@Autowired TodoStorage` 生效。先做 Task 19 再回来跑此测试，或改用直接注入 Provider。

- [ ] **Step 8: Commit**

```bash
git add ruoyi-agent/src/
git commit -m "feat(agent): add TodoStorageAdapter and MyBatisTodoStorageProvider SPI"
```

### Task 17: MyBatisKVStoreProvider + KvStoreAdapter

**Files:**
- Create: `ruoyi-agent/src/main/java/com/ruoyi/agent/adapter/KvStoreAdapter.java`
- Create: `ruoyi-agent/src/main/java/com/ruoyi/agent/spi/MyBatisKVStoreProvider.java`
- Create: `ruoyi-agent/src/main/resources/META-INF/services/com.openjiuwen.spi.store.KVStoreProvider`

**Interfaces:**
- Consumes: 内核 `BaseKVStore` 抽象 + `KVStoreProvider` SPI + AgentKvStoreMapper
- Produces: KvStoreAdapter implements BaseKVStore（set/get/delete 命中 agent_kv_store，字段 store_key/store_value）

- [ ] **Step 1: 探索 BaseKVStore 抽象方法**

Run: `grep -rn "abstract.*void\|abstract.*Object" D:\jiuwen\main\agent-core-java\src\main\java\com\openjiuwen\spi\store\BaseKVStore.java`
Expected: 列出 set/get/isExists/delete/getByPrefix 等方法签名

- [ ] **Step 2: 编写 KvStoreAdapter**

`@Component`，`extends BaseKVStore` 或 `implements`，注入 AgentKvStoreMapper，实现全部抽象方法，set→insert or update（按 store_key+namespace 唯一键），get→selectByKeyAndNamespace，delete→逻辑删或物理删按内核语义。命名空间/租户前缀解析通过 TenantContext。

- [ ] **Step 3: 编写 MyBatisKVStoreProvider**

按 design.md §4.7.2 原文（typeName="mybatis"，create 取 KvStoreAdapter Bean）。

- [ ] **Step 4: 创建 META-INF/services**

文件名 `com.openjiuwen.spi.store.KVStoreProvider`，内容 `com.ruoyi.agent.spi.MyBatisKVStoreProvider`。

- [ ] **Step 5: 编写测试（IT-SPI-006/007/009）**

验证 `KVStoreFactory.create("mybatis", conf)` 返回实例，set/get 命中 agent_kv_store 表，store_key 字段非单字符。

- [ ] **Step 6: 运行测试**

Run: `mvn test -pl ruoyi-agent -Dtest=MyBatisKVStoreProviderTest -Dgroups=integration`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add ruoyi-agent/src/
git commit -m "feat(agent): add MyBatisKVStoreProvider and KvStoreAdapter"
```

### Task 18: MyBatisSessionStoreProvider

**Files:**
- Create: `ruoyi-agent/src/main/java/com/ruoyi/agent/spi/MyBatisSessionStoreProvider.java`
- Create: `ruoyi-agent/src/main/resources/META-INF/services/com.openjiuwen.core.session.store.SessionStoreProvider`

按 Task 17 模式，桥接 SessionAdapter 与内核 SessionStoreProvider SPI。IT-SPI-008 验证。

- [ ] Steps: 探索→实现→注册→测试→Commit（同 Task 17）

### Task 19: AgentSpiBootstrap（Spring 与 ServiceLoader 桥接）

**Files:**
- Create: `ruoyi-agent/src/main/java/com/ruoyi/agent/config/AgentSpiBootstrap.java`

**Interfaces:**
- Consumes: Task 16/17/18 的 3 个 Provider + 内核 KVStoreFactory
- Produces: 启动时注入 ApplicationContext 到各 Provider 静态字段 + 编程式 register 兜底

- [ ] **Step 1: 编写 AgentSpiBootstrap**

按 design.md §4.8.3 原文（`@Component`，`@Autowired ApplicationContext`，`@PostConstruct init()` 调用三个 `setApplicationContext` + `KVStoreFactory.register("mybatis", new MyBatisKVStoreProvider())`）。注意 `@PostConstruct` 用 `jakarta.annotation.PostConstruct`。

- [ ] **Step 2: 编写测试（IT-SPI-002）**

验证启动后 `MyBatisTodoStorageProvider.applicationContext` 非空。

- [ ] **Step 3: 运行测试**

Run: `mvn test -pl ruoyi-agent -Dtest=AgentSpiBootstrapTest -Dgroups=integration`
Expected: PASS

- [ ] **Step 4: 回到 Task 16 Step 7 运行 SPI 集成测试**

Run: `mvn test -pl ruoyi-agent -Dtest=MyBatisTodoStorageProviderTest -Dgroups=integration`
Expected: 3 tests PASS

- [ ] **Step 5: Commit**

```bash
git add ruoyi-agent/src/
git commit -m "feat(agent): add AgentSpiBootstrap for Spring-ServiceLoader bridge"
```

---

## Phase 6: Controller 层

### Task 20: TodoController（模板任务）

**Files:**
- Create: `ruoyi-agent/src/main/java/com/ruoyi/agent/controller/TodoController.java`

**Interfaces:**
- Consumes: Task 10 的 ITodoService
- Produces: `/agent/todo` REST 端点（list/getInfo/add/edit/remove）

- [ ] **Step 1: 编写 TodoController**

按 design.md §4.5.1 原文复制（`@RestController @RequestMapping("/agent/todo")`，`extends BaseController`，5 个方法含 `@RequiresPermissions`/`@Log`/`startPage()`/`getDataTable`/`toAjax`/`success`）。

- [ ] **Step 2: 编译验证**

Run: `mvn compile -pl ruoyi-agent -DskipTests`
Expected: BUILD SUCCESS

- [ ] **Step 3: Commit**

```bash
git add ruoyi-agent/src/main/java/com/ruoyi/agent/controller/TodoController.java
git commit -m "feat(agent): add TodoController"
```

### Task 21: AgentInvokeController + AgentStreamController

**Files:**
- Create: 2 个 Controller

**Interfaces:**
- Consumes: Task 11 的 IAgentInvokeService
- Produces: `/agent/invoke`（同步 POST）+ `/agent/stream`（SSE GET）

- [ ] **Step 1: 编写两个 Controller**

按 design.md §4.5.2 原文复制。

- [ ] **Step 2: 补全 AgentInvokeServiceImpl**

`IAgentInvokeService.syncInvoke(inputs)` 调 `DeepAgentAdapter.create + invoke`，`streamInvoke(inputs)` 创建 `SseEmitter`，遍历 `DeepAgentAdapter.stream` 的 Iterator，`emitter.send(chunk)`。

- [ ] **Step 3: 编译验证 + Commit**

```bash
git add ruoyi-agent/src/main/java/com/ruoyi/agent/controller/
git commit -m "feat(agent): add invoke/stream controllers"
```

### Task 22: 其余 5 个 Controller（批量任务）

**Files:**
- Create: SessionController/EvolutionController/TeamController/MemoryController/SubAgentController

每个按 Task 20 模式：`@RestController extends BaseController`，注入对应 Service，标准 list/getInfo/add/edit/remove + `@RequiresPermissions`/`@Log`。权限标识用 `agent:xxx:yyy`（对应 Task 5 menu.sql）。

- [ ] Steps: 逐个编写→编译→Commit

```bash
git commit -m "feat(agent): add 5 business controllers"
```

---

## Phase 7: 集成与启动验证

### Task 23: 主配置 application.yml 集成

**Files:**
- Modify: `D:\jiuwen\main\ruoyi\ruoyi-admin\src\main\resources\application.yml`

- [ ] **Step 1: 追加 agent.engine 配置节**

在 application.yml 末尾追加 design.md §5.2.1 的 `agent:` 配置块。

- [ ] **Step 2: 验证配置加载**

Run: `mvn spring-boot:run -pl ruoyi-admin`（或打包启动），观察日志含 `agent.engine.*` 加载
Expected: 启动无报错，AgentEngineProperties 绑定成功

- [ ] **Step 3: Commit**

```bash
git add ruoyi-admin/src/main/resources/application.yml
git commit -m "config(admin): add agent.engine config"
```

### Task 24: 全量编译与启动验证

- [ ] **Step 1: 全量编译**

Run: `mvn clean compile -DskipTests` (在 D:\jiuwen\main\ruoyi)
Expected: BUILD SUCCESS，含 ruoyi-agent + agent-core-java

- [ ] **Step 2: 启动 RuoYiApplication**

Run: `mvn spring-boot:run -pl ruoyi-admin`
Expected: 启动成功，无 Bean 冲突，日志含 Runner Bean 注册 + AgentSpiBootstrap init

- [ ] **Step 3: 执行 DDL**

在 ry 库执行 `ruoyi-agent/src/main/resources/sql/agent_schema.sql`（15 表）+ `agent_menu.sql`（权限菜单）。

- [ ] **Step 4: 验证菜单与权限**

登录 RuoYi，确认 Agent 菜单出现，分配 `agent:todo:list` 权限给 admin。

- [ ] **Step 5: 验证接口**

GET `http://localhost/agent/todo/list`（带 Shiro 登录态）
Expected: 返回 `TableDataInfo`，code=200

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "chore(agent): full integration verified"
```

---

## Phase 8: Controller + Shiro 集成测试（L4）

### Task 25: Controller 权限与返回结构测试

**Files:**
- Create: `ruoyi-agent/src/test/java/com/ruoyi/agent/controller/TodoControllerTest.java`

- [ ] **Step 1: 编写 TodoControllerTest（IT-CTRL-001~007）**

使用 `@SpringBootTest` + `MockMvc`，mock Shiro Subject（用 `ShiroTestUtils` stub 为 admin 或无权限用户），测试无权限 403、有权限 list 分页、add/edit/remove 返回 AjaxResult、@Log 写 sys_oper_log。

- [ ] **Step 2: 运行测试**

Run: `mvn test -pl ruoyi-agent -Dtest=TodoControllerTest -Dgroups=integration`
Expected: 7 tests PASS

- [ ] **Step 3: 其余 Controller 测试（批量）**

为 Session/Evolution/Team/Memory/SubAgent 各写至少 list + add 两个用例。Invoke/Stream 单独 Task 26。

- [ ] **Step 4: Commit**

```bash
git add ruoyi-agent/src/test/
git commit -m "test(agent): add L4 controller+shiro integration tests"
```

### Task 26: AgentInvokeController & AgentStreamController 测试

**Files:**
- Create: `ruoyi-agent/src/test/java/com/ruoyi/agent/controller/AgentInvokeControllerTest.java`

**Interfaces:**
- Consumes: Task 21 的 AgentInvokeController/AgentStreamController
- Produces: IT-CTRL-008（同步调用）+ IT-CTRL-009（流式 SSE）测试

- [ ] **Step 1: 编写 AgentInvokeControllerTest**

mock `IAgentInvokeService.syncInvoke` 返回固定 Map，验证 Controller 返回 `AjaxResult.code=200` 且含 data；mock `streamInvoke` 返回一个预填充的 `SseEmitter`，通过 `MockMvc` 异步分发验证能收到 chunk。权限用 `agent:invoke:sync`/`agent:invoke:stream`。

```java
package com.ruoyi.agent.controller;

import com.ruoyi.agent.service.IAgentInvokeService;
import com.ruoyi.common.core.domain.AjaxResult;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;
import java.util.Map;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.asyncDispatch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class AgentInvokeControllerTest {

    @Autowired
    private MockMvc mockMvc;
    @MockBean
    private IAgentInvokeService agentInvokeService;

    @Test
    void invoke_sync_returnsAjaxResultWithOutput() throws Exception {
        when(agentInvokeService.syncInvoke(any()))
                .thenReturn(Map.of("output", "hello-result"));
        // 注：Shiro 权限 stub 在 TestExecutionListener 中设为 admin 持有 agent:invoke:sync
        mockMvc.perform(post("/agent/invoke")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"query\":\"hi\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(200))
                .andExpect(jsonPath("$.data.output").value("hello-result"));
    }

    @Test
    void stream_returnsSseEmitterWithChunk() throws Exception {
        SseEmitter emitter = new SseEmitter(5000L);
        emitter.send(SseEmitter.event().data("chunk-1"));
        emitter.complete();
        when(agentInvokeService.streamInvoke(any())).thenReturn(emitter);

        MvcResult result = mockMvc.perform(post("/agent/stream")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"query\":\"hi\"}"))
                .andExpect(request().asyncStarted())
                .andReturn();
        mockMvc.perform(asyncDispatch(result))
                .andExpect(status().isOk());
    }
}
```

注：实际 Shiro Subject stub 与 `@RequiresPermissions` 的集成需借助 RuoYi 的 `ShiroTestUtils` 或在测试 `@TestConfiguration` 中注册 `ShiroFilterFactoryBean` 放行。若 Shiro 初始化复杂，可改用 `@WithMockUser`-like 自定义注解 + `SubjectStub`，或将权限注解在测试 profile 下用 `AuthorizationAttributeSourceAdvisor` stub 放行。

- [ ] **Step 2: 运行测试**

Run: `mvn test -pl ruoyi-agent -Dtest=AgentInvokeControllerTest -Dgroups=integration`
Expected: 2 tests PASS（IT-CTRL-008/009）

- [ ] **Step 3: Commit**

```bash
git add ruoyi-agent/src/test/
git commit -m "test(agent): add invoke/stream controller integration tests"
```

---

## Phase 9: L5 内核端到端集成测试

### Task 27: DeepAgent 端到端调用测试

**Files:**
- Create: `ruoyi-agent/src/test/java/com/ruoyi/agent/e2e/DeepAgentE2ETest.java`
- Create: `ruoyi-agent/src/test/java/com/ruoyi/agent/e2e/MockLlmServer.java`（可选，mock LLM）

**Interfaces:**
- Consumes: Task 13 的 DeepAgentAdapter + AgentEngineConfig（Runner Bean）
- Produces: IT-E2E-001~007 端到端验证

- [ ] **Step 1: 准备 LLM mock（MockWebServer）**

agent-core-java 已依赖 `mockwebserver`。在测试中起一个 MockWebServer，返回固定 LLM 响应（含 TodoTool 调用所需的 JSON），`agent.engine.apiconfig-path` 指向测试用 apiconfig（api_base 指向 mock 地址）。

```java
package com.ruoyi.agent.e2e;

import okhttp3.mockwebserver.MockResponse;
import okhttp3.mockwebserver.MockWebServer;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import java.util.Map;
import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest
@ActiveProfiles("test")
class DeepAgentE2ETest {

    static MockWebServer mockLlm;
    @Autowired
    private com.ruoyi.agent.adapter.DeepAgentAdapter deepAgentAdapter;

    @BeforeAll
    static void startMock() throws Exception {
        mockLlm = new MockWebServer();
        mockLlm.enqueue(new MockResponse()
                .setBody("{\"choices\":[{\"message\":{\"content\":\"done\"}}]}")
                .addHeader("Content-Type", "application/json"));
        mockLlm.start();
    }

    @AfterAll
    static void stopMock() throws Exception {
        mockLlm.shutdown();
    }

    @Test
    void e2e_001_syncInvoke_returnsOutput() {
        com.openjiuwen.harness.DeepAgent agent = deepAgentAdapter.create(
                Map.of("query", "hello", "conversation_id", "e2e-1"));
        Map<String, Object> result = deepAgentAdapter.invoke(agent,
                Map.of("query", "hello", "conversation_id", "e2e-1"));
        assertThat(result).containsKey("output");
    }
}
```

- [ ] **Step 2: 其余端到端用例（IT-E2E-002~007）**

- E2E-002 stream：遍历 `deepAgentAdapter.stream` 的 Iterator，断言 `hasNext()` 至少一次
- E2E-003 Runner 生命周期：`@DirtiesContext` 关闭后验证 `Runner.getInstance()` 资源释放（日志或反射检查）
- E2E-004 子代理：`deepAgentAdapter.createSubagent(agent, "code_agent", "sid")` 返回非 null
- E2E-005 TodoTool 走 DB：DeepAgent 执行中用 TodoTool 后，查 `agent_todo` 表有记录（验证 SPI 桥接端到端生效）
- E2E-006 中断恢复：触发中断后查 `agent_checkpoint` 有记录
- E2E-007 多租户：两租户并发 invoke，工作区目录与 DB 数据隔离

- [ ] **Step 3: 运行端到端测试**

Run: `mvn test -pl ruoyi-agent -Dtest=DeepAgentE2ETest -Dgroups=integration`
Expected: 端到端用例 PASS（LLM mock 后稳定）

注：E2E 用例依赖内核 API 实际签名，实施前先用 grep 探索 `HarnessFactory.createDeepAgent`/`DeepAgent.invoke`/`DeepAgent.stream` 的真实签名（参考 ruoyi-ai 已有集成代码 `AiConfiguration.buildDeepAgent`），按实际签名调整 Adapter。

- [ ] **Step 4: Commit**

```bash
git add ruoyi-agent/src/test/
git commit -m "test(agent): add L5 end-to-end DeepAgent integration tests"
```

### Task 28: 全量回归与覆盖率报告

- [ ] **Step 1: 全量测试**

Run: `mvn test -pl ruoyi-agent,agent-core-java -am`
Expected: L1-L5 全绿，agent-core-java 原有测试无回归

- [ ] **Step 2: 覆盖率报告**

Run: `mvn test jacoco:report -pl ruoyi-agent`
Expected: ruoyi-agent 整体 ≥70%，SPI 桥接层 ≥90%，Mapper ≥80%，Controller ≥70%（test-plan.md §5.5 目标）

- [ ] **Step 3: 验收清单核对**

对照 test-plan.md §6 验收标准逐项确认：编译/单测/SPI 桥接/Controller/端到端/数据完整性/字段命名/无回归。

- [ ] **Step 4: 最终 Commit + 收尾**

```bash
git add -A
git commit -m "test(agent): full regression green, coverage targets met"
```

更新 design.md §5.6 集成验证清单全部勾选。

---

## 实施顺序与依赖图

```
Phase 1 (Tasks 1-4)  ── 脚手架 + 测试基础设施
   │
   ▼
Phase 2 (Tasks 5-7)  ── DDL + 15 实体（无依赖，可并行）
   │
   ▼
Phase 3 (Tasks 8-9)  ── 15 Mapper（依赖 Phase 2，模板+批量）
   │
   ▼
Phase 4 (Tasks 10-11) ── 8 Service（依赖 Phase 3）
   │
   ├─────────────────── Phase 6 (Tasks 20-22) ── 8 Controller（依赖 Phase 4，可先写不含 Adapter 的部分）
   │
   ▼
Phase 5 (Tasks 12-19) ── Adapter + SPI（核心，依赖 Phase 3/4，探索内核 API）
   │
   ├─────────────────── 回补 Service 的 Adapter 注入（Task 16 Step 5）
   │
   ▼
Phase 7 (Tasks 23-24) ── 集成与启动验证
   │
   ▼
Phase 8 (Tasks 25-26) ── L4 Controller 测试
   │
   ▼
Phase 9 (Tasks 27-28) ── L5 端到端 + 全量回归
```

**并行机会**：Phase 2 的 15 实体、Phase 3 的 14 Mapper、Phase 4 的 7 Service、Phase 6 的 5 Controller 均为同模式批量任务，可用并行 sub-agent 加速。

**关键风险点**：
1. 内核 API 实际签名（HarnessFactory/DeepAgent/TodoStorage/BaseKVStore）需在 Phase 5 探索确认，可能与 design.md 有出入
2. ruoyi-ai 已集成 agent-core-java，其 `AiConfiguration.buildDeepAgent` 是最佳参考样板，实施时务必对照
3. Shiro 在 `@SpringBootTest` 的初始化需复用 ruoyi-framework 的 ShiroConfig 或用 stub