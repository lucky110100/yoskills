# agent-core-java 重构设计文档

| 项目 | 内容 |
|------|------|
| 文档名称 | agent-core-java 重构为 RuoYi 子模块设计文档 |
| 版本 | v1.0 |
| 日期 | 2026-07-29 |
| 输出目录 | yoskills/common/agent-java-server |
| 关联文档 | requirements-spec.md（需求规格）、test-plan.md（测试计划） |
| 重构策略 | 方案 A：渐进适配层（已与用户确认） |

---

## 目录

- [1. 总体架构](#1-总体架构)
- [2. 模块映射](#2-模块映射)
- [3. 数据库设计](#3-数据库设计)
- [4. 核心类重构设计](#4-核心类重构设计)
- [5. 集成方案与配置](#5-集成方案与配置)
- [6. 迁移说明](#6-迁移说明)
- [7. 核心对象清单（harness 工程提取）](#7-核心对象清单harness-工程提取)

---

## 1. 总体架构

### 1.1 三层架构总览

```
┌─────────────────────────────────────────────────────────────┐
│  RuoYi 宿主层（既有，不改）                                    │
│  ruoyi-admin / ruoyi-framework / ruoyi-system / ruoyi-common  │
│  提供：BaseController / AjaxResult / BaseEntity / Shiro 鉴权   │
│        Druid 数据源 / PageHelper / MyBatis 全局配置            │
└───────────────────────────▲─────────────────────────────────┘
                            │ 依赖 ruoyi-common + 引擎内核
┌───────────────────────────┴────────────────────────────────-┐
│  ② RuoYi 适配层（新建子模块 ruoyi-agent，包名 com.ruoyi.agent） │
│  ┌──────────┬──────────┬───────────┬───────────┬──────────┐ │
│  │ controller│ service  │  mapper   │  domain   │  config  │ │
│  │ extends   │ IXxxSvc  │ MyBatis   │ extends   │ @Config  │ │
│  │ BaseCtrl  │ +Impl    │ +XML      │ BaseEntity│ 注册Bean  │ │
│  └─────▲────┴─────▲────┴─────▲─────┴─────▲────┴─────▲────┘ │
│        │          │          │           │          │       │
│   AjaxResult   业务编排    DB CRUD    实体映射   Spring托管   │
│        │          │                      │          │       │
│        │     ┌────┴─────┐                │          │       │
│        └────│ adapter  │←───────────────┘          │       │
│              │ (桥接)   │                            │       │
│              └────▼─────┘                            │       │
└─────────────────────┼────────────────────────────────▼─────┘
                      │ 调用内核 API（DeepAgent.invoke/stream 等）
┌─────────────────────┴──────────────────────────────────────┐
│  ① 引擎内核层（保留 agent-core-java 原有 com.openjiuwen.*）   │
│  Reactor 异步图执行引擎（Pregel）+ 中断恢复 + 流式输出         │
│  core / harness / spi / extensions / agentteams / ...        │
│  仅用 @Configuration 托管为 Spring Bean，不改执行模型          │
└──────────────────────────────────────────────────────────────┘
```

### 1.2 关键设计决策

| 决策 | 说明 | 理由 |
|---|---|---|
| **内核不动原则** | `com.openjiuwen` 的 Reactor 异步执行、Pregel 图引擎、中断恢复、流式输出保持原样，仅生命周期由 Spring 托管 | 这些是 agent-core-java 的核心价值，Spring MVC 阻塞模型会破坏其并发与流式语义 |
| **适配层职责** | ruoyi-agent 承担三件事：①持久化全量重写为 MyBatis；②RuoYi 风格 Controller-Service-Mapper 暴露能力；③adapter 桥接调用内核 | 渐进式重构，控制爆炸半径 |
| **数据流** | 同步 CRUD：HTTP→Controller→Service→Mapper→DB；异步执行：HTTP→Controller→Service→adapter→内核(Reactor)→流式输出→Controller 聚合为 AjaxResult/SSE | 区分阻塞与非阻塞路径 |
| **命名空间并存** | `com.openjiuwen`（内核）+ `com.ruoyi.agent`（适配层）并存，通过 adapter 包隔离 | 对外只暴露 com.ruoyi.agent |
| **技术栈对齐 RuoYi** | Java 17 + Spring Boot 4.0.6 + Jakarta + MyBatis（原生）+ Druid + PageHelper + Shiro + EhCache，不引入 Spring Security / JWT / Redis | 与宿主 RuoYi 一致 |

### 1.3 调用时序

#### 同步调用（如 DeepAgent.invoke）
```
Client → TodoController.add → TodoServiceImpl.insert → (DB)
                                   ↓ 业务需要执行 Agent
                              DeepAgentAdapter.invoke → DeepAgent.invoke(内核 Reactor)
                                   ↓ 同步等待
                              返回 Map → AjaxResult.success(map)
```

#### 流式调用（如 DeepAgent.stream，SSE）
```
Client(SSE) → AgentStreamController.stream → AgentInvokeServiceImpl.streamInvoke
    → DeepAgentAdapter.stream → DeepAgent.stream(内核 Iterator<Object>)
    → 遍历 chunk → SseEmitter.send(chunk) → Client
```

---

## 2. 模块映射

### 2.1 原模块归宿策略

agent-core-java 共 9 个顶级包，按"保留 / 适配 / 暴露"三策略归类：

| 原包（com.openjiuwen.*） | 职责 | 策略 | 在 ruoyi-agent 中的对应 |
|---|---|---|---|
| core.graph / core.runner / core.controller | Reactor 异步图执行引擎、Runner、任务调度 | 保留内核（仅 Spring 托管） | config 包注册为 Bean |
| core.session（Session/State/Stream） | 会话、中断恢复、流式输出 | 保留内核 | adapter 调用 AgentSessionApi |
| core.memory（LongTermMemory/MemInfo） | 长期记忆引擎 + user_message 等表 | 保留引擎 + 重写持久化 | domain/mapper 重写 DB 层，引擎逻辑保留 |
| core.retrieval / core.foundation.store | 检索、向量/KV 存储 SPI | 保留内核（向量库不纳入关系型重构） | 仅 kv_store 表重写为 MyBatis |
| core.multitenant / core.security | 多租户、护栏 | 保留内核 | — |
| core.workflow / core.multiagent | 工作流、多智能体 | 保留内核 | — |
| **harness（DeepAgent/Rails/Tools/TaskLoop）** | 编码智能体框架（本次重构重点） | **保留引擎 + 重写持久化 + 暴露 Controller** | domain/service/controller/mapper 全量映射 |
| spi.store（BaseKVStore/BaseDbStore） | 存储抽象 | 保留抽象 + 新增 MyBatis Provider | 新增 MyBatisKVStoreProvider 桥接 Mapper |
| extensions（redis/checkpointer/gaussdb） | 后端实现 | 保留内核（可选依赖） | — |
| agentteams（TeamDatabase 等表） | 多智能体协作 + team_* 表 | 保留引擎 + 重写持久化 | domain/mapper 重写 team_* 表 |
| autoharness / agentevolving / dev_tools / deepagents | 自动化/RL/工具/Deep | 保留内核 | — |

**重构重点**（需求 #1 的"核心对象"）锁定在 harness + harness 用到的持久化对象（TodoStorage/Checkpointer/Memory/Team/KV）。

### 2.2 新子模块 ruoyi-agent 包结构

包名 `com.ruoyi.agent`，与 `com.ruoyi.web/system/framework/common` 平级，被 `@SpringBootApplication` 默认扫描。模块内分包：

```
ruoyi-agent/
├── pom.xml                          # 依赖 ruoyi-common + agent-core-java 引擎
└── src/main/
    ├── java/com/ruoyi/agent/
    │   ├── controller/              # @RestController extends BaseController
    │   │   ├── AgentInvokeController        # DeepAgent 同步 invoke
    │   │   ├── AgentStreamController        # 流式 stream（SSE）
    │   │   ├── TodoController               # Todo CRUD
    │   │   ├── SessionController            # 会话/中断恢复
    │   │   ├── EvolutionController          # 进化记录
    │   │   ├── TeamController               # 多智能体协作
    │   │   ├── MemoryController             # 记忆检索/写入
    │   │   ├── SubAgentController           # 子代理管理
    │   │   └── SkillController              # 技能管理
    │   ├── service/                 # IXxxService + impl/
    │   │   ├── IAgentInvokeService / impl/AgentInvokeServiceImpl
    │   │   ├── ITodoService / impl/TodoServiceImpl
    │   │   ├── ISessionService / impl/SessionServiceImpl
    │   │   ├── IEvolutionService / impl/EvolutionServiceImpl
    │   │   ├── ITeamService / impl/TeamServiceImpl
    │   │   ├── IMemoryService / impl/MemoryServiceImpl
    │   │   ├── ISubAgentService / impl/SubAgentServiceImpl
    │   │   └── ISkillService / impl/SkillServiceImpl
    │   ├── mapper/                  # MyBatis 接口（无 @Mapper 注解，靠 MyBatisConfig 扫描）
    │   │   ├── AgentTodoMapper
    │   │   ├── AgentSessionMapper
    │   │   ├── AgentCheckpointMapper
    │   │   ├── AgentSessionStateMapper
    │   │   ├── AgentEvolutionMapper
    │   │   ├── AgentModelUsageMapper
    │   │   ├── AgentTeamMapper
    │   │   ├── AgentTeamMemberMapper
    │   │   ├── AgentTeamTaskMapper
    │   │   ├── AgentTeamTaskDepMapper
    │   │   ├── AgentTeamMessageMapper
    │   │   ├── AgentTeamMsgReadMapper
    │   │   ├── AgentMessageMapper          # 对应 user_message
    │   │   ├── AgentScopeUserMapper        # 对应 scope_user_mapping
    │   │   ├── AgentMemoryMetaMapper       # 对应 memory_meta
    │   │   └── AgentKvStoreMapper          # 对应 kv_store
    │   ├── domain/                  # 实体 extends BaseEntity
    │   │   ├── AgentTodo
    │   │   ├── AgentSession
    │   │   ├── AgentCheckpoint
    │   │   ├── AgentSessionState
    │   │   ├── AgentEvolution
    │   │   ├── AgentModelUsage
    │   │   ├── AgentTeam / AgentTeamMember / AgentTeamTask / AgentTeamTaskDep
    │   │   ├── AgentTeamMessage / AgentTeamMsgRead
    │   │   ├── AgentMessage / AgentScopeUser / AgentMemoryMeta
    │   │   └── AgentKvStore
    │   ├── adapter/                 # 桥接 com.openjiuwen 内核
    │   │   ├── DeepAgentAdapter            # 封装 DeepAgent.create/invoke/stream
    │   │   ├── SessionAdapter              # 封装 AgentSessionApi/Checkpointer
    │   │   ├── MemoryAdapter               # 封装 LongTermMemory
    │   │   ├── TeamAdapter                 # 封装 agentteams 运行时
    │   │   ├── SubAgentAdapter             # 封装 SubAgentRegistry
    │   │   └── TodoStorageAdapter          # 实现 TodoStorage SPI
    │   ├── spi/                     # SPI Provider 实现
    │   │   ├── MyBatisTodoStorageProvider
    │   │   ├── MyBatisKVStoreProvider
    │   │   └── MyBatisSessionStoreProvider
    │   └── config/                  # @Configuration
    │       ├── AgentEngineConfig           # 注册 DeepAgent/Runner/ResourceMgr 为 Bean
    │       ├── AgentMyBatisConfig          # SqlSessionFactory（可复用宿主或独立数据源）
    │       ├── AgentEngineProperties       # @ConfigurationProperties("agent.engine")
    │       └── AgentSpiBootstrap           # Spring 与 ServiceLoader 桥接引导
    └── resources/
        ├── mapper/agent/             # *Mapper.xml（被 classpath*:mapper/**/*Mapper.xml 扫描）
        ├── META-INF/services/        # ServiceLoader 注册文件
        └── application-agent.yml     # 引擎配置（可选 profile）
```

### 2.3 模块依赖链

```
ruoyi-admin (启动)
  └── ruoyi-framework ── ruoyi-system ── ruoyi-common
  └── ruoyi-agent ────────────────────┬── ruoyi-common   (BaseController/AjaxResult/BaseEntity)
                                      └── agent-core-java (com.openjiuwen 引擎内核)
```

ruoyi-agent 不依赖 framework/system（避免反向依赖），只依赖 common（基础设施）+ agent-core-java（引擎）。RuoYi 自带的 sys_user/role/menu 鉴权由 Shiro 注解 `@RequiresPermissions("agent:todo:list")` 控制权限，无需 agent 模块自实现。

---

## 3. 数据库设计

### 3.1 设计原则

1. **统一前缀**：所有表加 `agent_` 前缀，与 RuoYi 的 `sys_`/`qrtz_`/`gen_` 区分
2. **继承 RuoYi 字段约定**：业务表均补全 `create_by/create_time/update_by/update_time/del_flag`（逻辑删除 "0"存在/"2"删除）+ `remark`
3. **主键策略**：业务主键 `BIGINT` 自增（`id`），关联表用联合主键，原内核中 `VARCHAR(64)` 主键的表（如 `user_message.message_id`）保留为业务键并新增 `id BIGINT` 作为 RuoYi 风格主键
4. **类型对齐**：使用 MySQL（与宿主 `application-druid.yml` 一致），`CLOB`→`TEXT`/`MEDIUMTEXT`，`VARCHAR(n)` 按现有 + 扩容，时间字段统一 `DATETIME`
5. **多租户兼容**：保留内核已有的 `tenant_id`/`scope_id` 字段，不另起租户隔离机制
6. **字段命名规范**：使用完整单词，禁止单字符字段（如 k/v → store_key/store_value）

### 3.2 表清单总览（共 15 张，5 组）

| 组 | 表名 | 来源类/原表 | 说明 |
|---|---|---|---|
| A | agent_todo | TodoItem + TodoStorage | 待办任务项 |
| B | agent_session | Session/BaseSession | 会话主表 |
| B | agent_checkpoint | PersistenceCheckpointer | 检查点（agent/workflow/graph 三类） |
| B | agent_session_state | GraphStoreState | 图状态快照 |
| C | agent_message | user_message | 用户消息 |
| C | agent_scope_user | scope_user_mapping | 作用域-用户映射 |
| C | agent_memory_meta | memory_meta | 记忆表元数据 |
| D | agent_team | team_info | 团队 |
| D | agent_team_member | team_member | 成员 |
| D | agent_team_task | team_task_* | 任务（原按 session 动态建表，统一为单表+session_id 列） |
| D | agent_team_task_dep | team_task_dependency_* | 任务依赖 |
| D | agent_team_message | team_message_* | 消息 |
| D | agent_team_msg_read | message_read_status_* | 已读状态 |
| E | agent_evolution | EvolutionRecord | 进化记录 |
| E | agent_model_usage | ModelUsageRecord | 模型用量 |
| E | agent_kv_store | kv_store (DbBasedKVStore) | 通用 KV 存储 |

### 3.3 组 A — Todo 任务清单

```sql
CREATE TABLE agent_todo (
  id              BIGINT       NOT NULL AUTO_INCREMENT COMMENT '主键',
  todo_id         VARCHAR(64)  NOT NULL                COMMENT '业务ID(TodoItem.id)',
  session_id      VARCHAR(128) NOT NULL                COMMENT '会话ID',
  tenant_id       VARCHAR(64)  DEFAULT NULL            COMMENT '租户ID',
  content         VARCHAR(2048) NOT NULL               COMMENT '任务内容',
  active_form     VARCHAR(2048) DEFAULT NULL           COMMENT '进行中描述',
  description     VARCHAR(2048) DEFAULT NULL            COMMENT '详细说明',
  status          VARCHAR(32)  NOT NULL DEFAULT 'TODO' COMMENT '状态(TODO/PENDING/IN_PROGRESS/DONE/COMPLETED/CANCELLED)',
  priority        INT          DEFAULT 0               COMMENT '优先级',
  selected_model_id VARCHAR(128) DEFAULT NULL          COMMENT '选中模型',
  depends_on      VARCHAR(2048) DEFAULT NULL           COMMENT '依赖任务ID(JSON数组)',
  result_summary  VARCHAR(2048) DEFAULT NULL           COMMENT '结果摘要',
  meta_data       TEXT         DEFAULT NULL            COMMENT '元数据(JSON)',
  del_flag        CHAR(1)      DEFAULT '0'             COMMENT '删除标志(0存在 2删除)',
  create_by       VARCHAR(64)  DEFAULT ''              COMMENT '创建者',
  create_time     DATETIME     DEFAULT NULL            COMMENT '创建时间',
  update_by       VARCHAR(64)  DEFAULT ''              COMMENT '更新者',
  update_time     DATETIME     DEFAULT NULL            COMMENT '更新时间',
  remark          VARCHAR(500) DEFAULT NULL            COMMENT '备注',
  PRIMARY KEY (id),
  UNIQUE KEY uk_todo_id (todo_id),
  KEY idx_session (session_id),
  KEY idx_tenant_session (tenant_id, session_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Agent待办任务';
```

### 3.4 组 B — 会话与检查点

```sql
CREATE TABLE agent_session (
  id                  BIGINT       NOT NULL AUTO_INCREMENT COMMENT '主键',
  session_id          VARCHAR(128) NOT NULL                 COMMENT '会话ID',
  tenant_id           VARCHAR(64)  DEFAULT NULL             COMMENT '租户ID',
  session_type        VARCHAR(32)  NOT NULL                 COMMENT '类型(agent/workflow/router/node)',
  status              VARCHAR(32)  NOT NULL DEFAULT 'ACTIVE' COMMENT '状态(ACTIVE/INTERRUPTED/COMPLETED/CANCELLED)',
  current_operator_id VARCHAR(64)  DEFAULT NULL             COMMENT '当前操作者',
  parent_session_id   VARCHAR(128) DEFAULT NULL             COMMENT '父会话ID(子代理)',
  inputs              TEXT         DEFAULT NULL             COMMENT '输入(JSON)',
  outputs             TEXT         DEFAULT NULL             COMMENT '输出(JSON)',
  del_flag            CHAR(1)      DEFAULT '0',
  create_by           VARCHAR(64)  DEFAULT '',
  create_time         DATETIME     DEFAULT NULL,
  update_by           VARCHAR(64)  DEFAULT '',
  update_time         DATETIME     DEFAULT NULL,
  remark              VARCHAR(500) DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_session_id (session_id),
  KEY idx_tenant_type (tenant_id, session_type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Agent会话';

CREATE TABLE agent_checkpoint (
  id              BIGINT       NOT NULL AUTO_INCREMENT,
  session_id      VARCHAR(128) NOT NULL,
  namespace       VARCHAR(32)  NOT NULL COMMENT '命名空间(agent/workflow/workflow-graph)',
  checkpoint_id   VARCHAR(128) NOT NULL COMMENT '检查点ID',
  data_type       VARCHAR(64)  DEFAULT NULL COMMENT '数据类型',
  data_value      MEDIUMTEXT   DEFAULT NULL COMMENT '检查点数据(JSON)',
  dump_type       VARCHAR(32)  DEFAULT NULL COMMENT '转储类型',
  del_flag        CHAR(1)      DEFAULT '0',
  create_by       VARCHAR(64)  DEFAULT '',
  create_time     DATETIME     DEFAULT NULL,
  update_by       VARCHAR(64)  DEFAULT '',
  update_time     DATETIME     DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_session_ns_ckpt (session_id, namespace, checkpoint_id),
  KEY idx_session (session_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Agent检查点';

CREATE TABLE agent_session_state (
  id              BIGINT       NOT NULL AUTO_INCREMENT,
  session_id      VARCHAR(128) NOT NULL,
  namespace       VARCHAR(64)  NOT NULL,
  step            INT          DEFAULT 0,
  channel_values  MEDIUMTEXT   DEFAULT NULL COMMENT '通道值(JSON)',
  pending_buffer  MEDIUMTEXT   DEFAULT NULL COMMENT '待处理缓冲(JSON)',
  pending_node    MEDIUMTEXT   DEFAULT NULL COMMENT '待处理节点(JSON)',
  node_version    INT          DEFAULT 0,
  del_flag        CHAR(1)      DEFAULT '0',
  create_time     DATETIME     DEFAULT NULL,
  update_time     DATETIME     DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_session_ns (session_id, namespace)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Agent会话状态快照';
```

### 3.5 组 C — 记忆引擎

```sql
CREATE TABLE agent_message (
  id            BIGINT       NOT NULL AUTO_INCREMENT,
  message_id    VARCHAR(64)  NOT NULL,
  user_id       VARCHAR(256) NOT NULL,
  scope_id      VARCHAR(128) NOT NULL,
  tenant_id     VARCHAR(64)  DEFAULT NULL,
  content       TEXT         NOT NULL,
  session_id    VARCHAR(2048) DEFAULT NULL,
  role          VARCHAR(32)  DEFAULT NULL,
  msg_timestamp VARCHAR(64)  DEFAULT NULL,
  del_flag      CHAR(1)      DEFAULT '0',
  create_by     VARCHAR(64)  DEFAULT '',
  create_time   DATETIME     DEFAULT NULL,
  update_by     VARCHAR(64)  DEFAULT '',
  update_time   DATETIME     DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_message_id (message_id),
  KEY idx_user_scope (user_id, scope_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Agent用户消息';

CREATE TABLE agent_scope_user (
  id          BIGINT      NOT NULL AUTO_INCREMENT,
  user_id     VARCHAR(64) NOT NULL,
  scope_id    VARCHAR(64) NOT NULL,
  tenant_id   VARCHAR(64) DEFAULT NULL,
  del_flag    CHAR(1)     DEFAULT '0',
  create_time DATETIME    DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_user_scope (user_id, scope_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Agent作用域用户映射';

CREATE TABLE agent_memory_meta (
  id             BIGINT      NOT NULL AUTO_INCREMENT,
  table_name     VARCHAR(64) NOT NULL,
  schema_version VARCHAR(64) NOT NULL,
  tenant_id      VARCHAR(64) DEFAULT NULL,
  del_flag       CHAR(1)     DEFAULT '0',
  create_time    DATETIME    DEFAULT NULL,
  update_time    DATETIME    DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_table_name (table_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Agent记忆元数据';
```

### 3.6 组 D — 多智能体团队协作

```sql
CREATE TABLE agent_team (
  id                  BIGINT       NOT NULL AUTO_INCREMENT,
  team_name           VARCHAR(64)  NOT NULL,
  display_name        VARCHAR(128) DEFAULT NULL,
  leader_member_name  VARCHAR(64)  DEFAULT NULL,
  description         VARCHAR(500) DEFAULT NULL,
  prompt              TEXT         DEFAULT NULL,
  tenant_id           VARCHAR(64)  DEFAULT NULL,
  del_flag            CHAR(1)      DEFAULT '0',
  create_by           VARCHAR(64)  DEFAULT '',
  create_time         DATETIME     DEFAULT NULL,
  update_by           VARCHAR(64)  DEFAULT '',
  update_time         DATETIME     DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_team_name (team_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Agent团队';

CREATE TABLE agent_team_member (
  id               BIGINT       NOT NULL AUTO_INCREMENT,
  member_name      VARCHAR(64)  NOT NULL,
  team_name        VARCHAR(64)  NOT NULL,
  display_name     VARCHAR(128) DEFAULT NULL,
  agent_card       TEXT         DEFAULT NULL COMMENT 'AgentCard JSON',
  status           VARCHAR(32)  DEFAULT NULL,
  description      VARCHAR(500) DEFAULT NULL,
  execution_status VARCHAR(32)  DEFAULT NULL,
  mode             VARCHAR(32)  DEFAULT NULL,
  tenant_id        VARCHAR(64)  DEFAULT NULL,
  del_flag         CHAR(1)      DEFAULT '0',
  create_by        VARCHAR(64)  DEFAULT '',
  create_time      DATETIME     DEFAULT NULL,
  update_by        VARCHAR(64)  DEFAULT '',
  update_time      DATETIME     DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_member_team (member_name, team_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Agent团队成员';

CREATE TABLE agent_team_task (
  id          BIGINT       NOT NULL AUTO_INCREMENT,
  task_id     VARCHAR(64)  NOT NULL,
  session_id  VARCHAR(128) NOT NULL COMMENT '会话ID(替代原动态表后缀)',
  team_name   VARCHAR(64)  NOT NULL,
  title       VARCHAR(256) DEFAULT NULL,
  content     TEXT         DEFAULT NULL,
  status      VARCHAR(32)  DEFAULT NULL,
  assignee    VARCHAR(64)  DEFAULT NULL,
  tenant_id   VARCHAR(64)  DEFAULT NULL,
  del_flag    CHAR(1)      DEFAULT '0',
  create_by   VARCHAR(64)  DEFAULT '',
  create_time DATETIME     DEFAULT NULL,
  update_by   VARCHAR(64)  DEFAULT '',
  update_time DATETIME     DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_task_id (task_id),
  KEY idx_team_session (team_name, session_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Agent团队任务';

CREATE TABLE agent_team_task_dep (
  id                  BIGINT      NOT NULL AUTO_INCREMENT,
  task_id             VARCHAR(64) NOT NULL,
  depends_on_task_id  VARCHAR(64) NOT NULL,
  session_id          VARCHAR(128) NOT NULL,
  team_name           VARCHAR(64) NOT NULL,
  del_flag            CHAR(1)     DEFAULT '0',
  create_time         DATETIME    DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_dep (task_id, depends_on_task_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Agent团队任务依赖';

CREATE TABLE agent_team_message (
  id                BIGINT       NOT NULL AUTO_INCREMENT,
  message_id        VARCHAR(64)  NOT NULL,
  session_id        VARCHAR(128) NOT NULL,
  team_name         VARCHAR(64)  NOT NULL,
  from_member_name  VARCHAR(64)  DEFAULT NULL,
  to_member_name     VARCHAR(64)  DEFAULT NULL,
  content           TEXT         DEFAULT NULL,
  msg_timestamp     DATETIME     DEFAULT NULL,
  is_broadcast      CHAR(1)      DEFAULT '0',
  is_read           CHAR(1)      DEFAULT '0',
  tenant_id         VARCHAR(64)  DEFAULT NULL,
  del_flag          CHAR(1)      DEFAULT '0',
  create_time       DATETIME     DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_msg_id (message_id),
  KEY idx_team_session (team_name, session_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Agent团队消息';

CREATE TABLE agent_team_msg_read (
  id          BIGINT      NOT NULL AUTO_INCREMENT,
  member_name VARCHAR(64) NOT NULL,
  team_name   VARCHAR(64) NOT NULL,
  session_id  VARCHAR(128) DEFAULT NULL,
  read_at     DATETIME    DEFAULT NULL,
  del_flag    CHAR(1)     DEFAULT '0',
  create_time DATETIME    DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_read (member_name, team_name, session_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Agent团队消息已读';
```

### 3.7 组 E — 进化记录与 KV 存储

```sql
CREATE TABLE agent_evolution (
  id            BIGINT       NOT NULL AUTO_INCREMENT,
  evolution_id  VARCHAR(64)  NOT NULL,
  source        VARCHAR(128) DEFAULT NULL COMMENT '来源(技能/提示/配置)',
  tenant_id     VARCHAR(64)  DEFAULT NULL,
  context       TEXT         DEFAULT NULL COMMENT '上下文(JSON)',
  change_patch  TEXT         DEFAULT NULL COMMENT '变更补丁(JSON,EvolutionPatch)',
  is_applied    CHAR(1)      DEFAULT '0' COMMENT '是否已应用',
  score         DOUBLE       DEFAULT NULL,
  usage_stats   TEXT         DEFAULT NULL COMMENT '用量统计(JSON,UsageStats)',
  skill_version VARCHAR(64)  DEFAULT NULL,
  del_flag      CHAR(1)      DEFAULT '0',
  create_by     VARCHAR(64)  DEFAULT '',
  create_time   DATETIME     DEFAULT NULL,
  update_by     VARCHAR(64)  DEFAULT '',
  update_time   DATETIME     DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_evolution_id (evolution_id),
  KEY idx_source (source)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Agent进化记录';

CREATE TABLE agent_model_usage (
  id               BIGINT       NOT NULL AUTO_INCREMENT,
  session_id       VARCHAR(128) NOT NULL,
  tenant_id        VARCHAR(64)  DEFAULT NULL,
  model_name       VARCHAR(128) DEFAULT NULL,
  prompt_tokens    INT          DEFAULT 0,
  completion_tokens INT         DEFAULT 0,
  total_tokens     INT          DEFAULT 0,
  cost             DECIMAL(12,4) DEFAULT NULL,
  del_flag         CHAR(1)      DEFAULT '0',
  create_by        VARCHAR(64)  DEFAULT '',
  create_time      DATETIME     DEFAULT NULL,
  PRIMARY KEY (id),
  KEY idx_session (session_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Agent模型用量记录';

CREATE TABLE agent_kv_store (
  id            BIGINT      NOT NULL AUTO_INCREMENT,
  store_key     VARCHAR(512) NOT NULL              COMMENT 'KV键',
  store_value   MEDIUMTEXT  DEFAULT NULL           COMMENT 'KV值',
  namespace     VARCHAR(64) DEFAULT NULL           COMMENT '命名空间(多租户隔离)',
  tenant_id     VARCHAR(64) DEFAULT NULL,
  expire_at     DATETIME    DEFAULT NULL            COMMENT '过期时间',
  del_flag      CHAR(1)     DEFAULT '0',
  create_time   DATETIME    DEFAULT NULL,
  update_time   DATETIME    DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_key_ns (store_key, namespace),
  KEY idx_tenant (tenant_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Agent通用KV存储';
```

### 3.8 不纳入关系型重构的部分

- **向量数据**（Milvus/Chroma/PGVector）：保留内核 SPI，不建关系表
- **对象存储/文件存储**（FileTodoStorage/WorkspaceStore）：保留文件实现
- **图记忆**（GraphMemory/Entity/Episode/Relation）：保留内核图存储，不关系型化

### 3.9 索引策略

| 表 | 索引 | 用途 |
|---|---|---|
| agent_todo | uk_todo_id / idx_session / idx_tenant_session | 业务键唯一 / 按会话查 / 租户隔离查 |
| agent_session | uk_session_id / idx_tenant_type | 会话唯一 / 租户+类型查 |
| agent_checkpoint | uk_session_ns_ckpt / idx_session | 复合唯一 / 按会话查 |
| agent_message | uk_message_id / idx_user_scope | 业务键 / 用户+作用域查 |
| agent_team_task | uk_task_id / idx_team_session | 业务键 / 团队+会话查 |
| agent_team_message | uk_msg_id / idx_team_session | 业务键 / 团队+会话查 |
| agent_kv_store | uk_key_ns / idx_tenant | 键+命名空间唯一 / 租户查 |

---

## 4. 核心类重构设计

### 4.1 对象关系总览（UML 类图语义）

```
BaseEntity (ruoyi-common)
  ▲
  │ extends
┌─┴─────────────────────────────────────────────────────┐
│ AgentTodo AgentSession AgentCheckpoint AgentEvolution │
│ AgentTeam  AgentTeamMember AgentTeamTask AgentMessage │  ← 实体层(domain)
│ AgentKvStore AgentModelUsage ...                      │
└──────────────────────────────────────────────────────┘
        │ mapped by
        ▼
┌──────────────────────────────────────────────────────┐
│ AgentTodoMapper AgentSessionMapper AgentTeamMapper ...│  ← Mapper接口+XML
└───────────────────────▲──────────────────────────────┘
                        │ @Autowired
┌───────────────────────┴──────────────────────────────┐
│ ITodoService ← TodoServiceImpl                       │  ← Service层
│   (调用 Mapper + 调用 Adapter → 内核)                │
└───────────────────────▲──────────────────────────────┘
                        │ @Autowired
┌───────────────────────┴──────────────────────────────┐
│ TodoController extends BaseController                 │  ← Controller层
│   返回 AjaxResult / TableDataInfo / SseEmitter       │
└──────────────────────────────────────────────────────┘

Adapter 层(桥接内核)：
  DeepAgentAdapter ──> com.openjiuwen.harness.DeepAgent
  SessionAdapter   ──> com.openjiuwen.core.session.AgentSessionApi
  MemoryAdapter    ──> com.openjiuwen.core.memory.LongTermMemory
  TeamAdapter      ──> com.openjiuwen.agentteams.*
```

**关系说明**：
- **Entity→BaseEntity**：单继承（RuoYi 约定）
- **Entity↔Entity**：AgentTeam 1—N AgentTeamMember、AgentTeam 1—N AgentTeamTask、AgentTeamTask N—N AgentTeamTaskDep、AgentSession 1—N AgentCheckpoint——通过外键字段关联，Service 层组装，非 ORM 对象图
- **Service→Mapper**：组合（注入 Mapper）
- **Service→Adapter**：组合（注入 Adapter）
- **Adapter→内核**：依赖（调用 com.openjiuwen API，不继承）

### 4.2 Entity 层（代表性类）

#### 4.2.1 AgentTodo（对应 agent_todo 表）

```java
package com.ruoyi.agent.domain;

import com.ruoyi.common.core.domain.BaseEntity;

public class AgentTodo extends BaseEntity {
    private static final long serialVersionUID = 1L;

    private Long id;
    private String todoId;
    private String sessionId;
    private String tenantId;
    private String content;
    private String activeForm;
    private String description;
    private String status;
    private Integer priority;
    private String selectedModelId;
    private String dependsOn;
    private String resultSummary;
    private String metaData;

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public String getTodoId() { return todoId; }
    public void setTodoId(String todoId) { this.todoId = todoId; }
    public String getSessionId() { return sessionId; }
    public void setSessionId(String sessionId) { this.sessionId = sessionId; }
    public String getTenantId() { return tenantId; }
    public void setTenantId(String tenantId) { this.tenantId = tenantId; }
    public String getContent() { return content; }
    public void setContent(String content) { this.content = content; }
    public String getActiveForm() { return activeForm; }
    public void setActiveForm(String activeForm) { this.activeForm = activeForm; }
    public String getDescription() { return description; }
    public void setDescription(String description) { this.description = description; }
    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }
    public Integer getPriority() { return priority; }
    public void setPriority(Integer priority) { this.priority = priority; }
    public String getSelectedModelId() { return selectedModelId; }
    public void setSelectedModelId(String selectedModelId) { this.selectedModelId = selectedModelId; }
    public String getDependsOn() { return dependsOn; }
    public void setDependsOn(String dependsOn) { this.dependsOn = dependsOn; }
    public String getResultSummary() { return resultSummary; }
    public void setResultSummary(String resultSummary) { this.resultSummary = resultSummary; }
    public String getMetaData() { return metaData; }
    public void setMetaData(String metaData) { this.metaData = metaData; }
}
```

**设计决策**：实体风格跟随 `ruoyi-system`（显式 getter/setter，非 Lombok），因为 agent 模块依赖 `ruoyi-common` 并与 `ruoyi-system` 同级。`del_flag/create_by/create_time/update_by/update_time/remark/searchValue/params` 由 `BaseEntity` 提供，不在子类重复声明。

#### 4.2.2 AgentSession（对应 agent_session 表）

```java
package com.ruoyi.agent.domain;

import com.ruoyi.common.core.domain.BaseEntity;

public class AgentSession extends BaseEntity {
    private static final long serialVersionUID = 1L;

    private Long id;
    private String sessionId;
    private String tenantId;
    private String sessionType;
    private String status;
    private String currentOperatorId;
    private String parentSessionId;
    private String inputs;
    private String outputs;

    // getter/setter 省略，模式同 AgentTodo
}
```

#### 4.2.3 AgentKvStore（对应 agent_kv_store 表）

```java
package com.ruoyi.agent.domain;

import com.ruoyi.common.core.domain.BaseEntity;

public class AgentKvStore extends BaseEntity {
    private static final long serialVersionUID = 1L;

    private Long id;
    private String storeKey;
    private String storeValue;
    private String namespace;
    private String tenantId;
    private java.util.Date expireAt;

    // getter/setter
}
```

（其余 12 个实体结构同模式，属性与对应表字段一一映射，此处不逐一展开。）

### 4.3 Mapper 层（MyBatis 接口 + XML）

#### 4.3.1 AgentTodoMapper

```java
package com.ruoyi.agent.mapper;

import com.ruoyi.agent.domain.AgentTodo;
import org.apache.ibatis.annotations.Param;
import java.util.List;

public interface AgentTodoMapper {

    AgentTodo selectTodoById(Long id);

    AgentTodo selectTodoByTodoId(String todoId);

    List<AgentTodo> selectTodoList(AgentTodo todo);

    List<AgentTodo> selectTodoBySession(@Param("sessionId") String sessionId,
                                        @Param("tenantId") String tenantId);

    int insertTodo(AgentTodo todo);

    int updateTodo(AgentTodo todo);

    int updateTodoStatus(@Param("todoId") String todoId,
                         @Param("status") String status,
                         @Param("resultSummary") String resultSummary);

    int deleteTodoByIds(Long[] ids);

    int deleteTodoBySession(@Param("sessionId") String sessionId,
                            @Param("tenantId") String tenantId);

    int deleteTodoByTodoId(String todoId);
}
```

**约定**（对齐 RuoYi）：
- 接口无 `@Mapper` 注解，由 `MyBatisConfig` + `classpath*:mapper/**/*Mapper.xml` 扫描
- 方法名：`selectXxxById/List`、`insertXxx`、`updateXxx`、`deleteXxxByIds`
- 多参数用 `@Param`
- XML 放 `resources/mapper/agent/AgentTodoMapper.xml`，`namespace` 对应接口全限定名，使用 `<resultMap>` 显式映射驼峰↔下划线（不开驼峰自动转换，与宿主一致）

#### 4.3.2 AgentTodoMapper.xml（关键片段）

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<!DOCTYPE mapper PUBLIC "-//mybatis.org//DTD Mapper 3.0//EN"
        "http://mybatis.org/dtd/mybatis-3-mapper.dtd">
<mapper namespace="com.ruoyi.agent.mapper.AgentTodoMapper">

    <resultMap type="AgentTodo" id="AgentTodoResult">
        <id     property="id"             column="id"/>
        <result property="todoId"         column="todo_id"/>
        <result property="sessionId"      column="session_id"/>
        <result property="tenantId"       column="tenant_id"/>
        <result property="content"        column="content"/>
        <result property="activeForm"     column="active_form"/>
        <result property="description"    column="description"/>
        <result property="status"         column="status"/>
        <result property="priority"       column="priority"/>
        <result property="selectedModelId" column="selected_model_id"/>
        <result property="dependsOn"      column="depends_on"/>
        <result property="resultSummary"  column="result_summary"/>
        <result property="metaData"       column="meta_data"/>
        <result property="delFlag"        column="del_flag"/>
        <result property="createBy"       column="create_by"/>
        <result property="createTime"     column="create_time"/>
        <result property="updateBy"       column="update_by"/>
        <result property="updateTime"     column="update_time"/>
        <result property="remark"         column="remark"/>
    </resultMap>

    <sql id="selectTodoVo">
        select id, todo_id, session_id, tenant_id, content, active_form, description,
               status, priority, selected_model_id, depends_on, result_summary, meta_data,
               del_flag, create_by, create_time, update_by, update_time, remark
          from agent_todo
         where del_flag = '0'
    </sql>

    <select id="selectTodoById" resultMap="AgentTodoResult">
        <include refid="selectTodoVo"/>
        and id = #{id}
    </select>

    <select id="selectTodoList" parameterType="AgentTodo" resultMap="AgentTodoResult">
        <include refid="selectTodoVo"/>
        <if test="todoId != null and todoId != ''">and todo_id = #{todoId}</if>
        <if test="sessionId != null and sessionId != ''">and session_id = #{sessionId}</if>
        <if test="tenantId != null and tenantId != ''">and tenant_id = #{tenantId}</if>
        <if test="status != null and status != ''">and status = #{status}</if>
        order by id desc
    </select>

    <insert id="insertTodo" parameterType="AgentTodo" useGeneratedKeys="true" keyProperty="id">
        insert into agent_todo
        <trim prefix="(" suffix=")" suffixOverrides=",">
            <if test="todoId != null">todo_id,</if>
            <if test="sessionId != null">session_id,</if>
            <if test="tenantId != null">tenant_id,</if>
            <if test="content != null">content,</if>
            <if test="activeForm != null">active_form,</if>
            <if test="status != null">status,</if>
            <if test="priority != null">priority,</if>
            <if test="dependsOn != null">depends_on,</if>
            <if test="metaData != null">meta_data,</if>
            <if test="createBy != null">create_by,</if>
            <if test="createTime != null">create_time,</if>
        </trim>
        <trim prefix="values (" suffix=")" suffixOverrides=",">
            <if test="todoId != null">#{todoId},</if>
            <if test="sessionId != null">#{sessionId},</if>
            <if test="tenantId != null">#{tenantId},</if>
            <if test="content != null">#{content},</if>
            <if test="activeForm != null">#{activeForm},</if>
            <if test="status != null">#{status},</if>
            <if test="priority != null">#{priority},</if>
            <if test="dependsOn != null">#{dependsOn},</if>
            <if test="metaData != null">#{metaData},</if>
            <if test="createBy != null">#{createBy},</if>
            <if test="createTime != null">#{createTime},</if>
        </trim>
    </insert>

    <update id="updateTodo" parameterType="AgentTodo">
        update agent_todo
        <trim prefix="SET" suffixOverrides=",">
            <if test="status != null">status = #{status},</if>
            <if test="content != null">content = #{content},</if>
            <if test="resultSummary != null">result_summary = #{resultSummary},</if>
            <if test="priority != null">priority = #{priority},</if>
            <if test="updateBy != null">update_by = #{updateBy},</if>
            <if test="updateTime != null">update_time = #{updateTime},</if>
        </trim>
        where todo_id = #{todoId}
    </update>

    <update id="updateTodoStatus">
        update agent_todo
           set status = #{status},
               result_summary = #{resultSummary},
               update_time = sysdate()
         where todo_id = #{todoId}
    </update>

    <delete id="deleteTodoByIds">
        update agent_todo set del_flag = '2' where id in
        <foreach item="id" collection="array" open="(" separator="," close=")">
            #{id}
        </foreach>
    </delete>

    <delete id="deleteTodoBySession">
        update agent_todo set del_flag = '2'
         where session_id = #{sessionId}
           <if test="tenantId != null">and tenant_id = #{tenantId}</if>
    </delete>
</mapper>
```

### 4.4 Service 层

#### 4.4.1 ITodoService（接口）

```java
package com.ruoyi.agent.service;

import com.ruoyi.agent.domain.AgentTodo;
import java.util.List;

public interface ITodoService {

    AgentTodo selectTodoById(Long id);

    AgentTodo selectTodoByTodoId(String todoId);

    List<AgentTodo> selectTodoList(AgentTodo todo);

    List<AgentTodo> selectTodoBySession(String sessionId, String tenantId);

    int insertTodo(AgentTodo todo);

    int updateTodo(AgentTodo todo);

    int updateTodoStatus(String todoId, String status, String resultSummary);

    int deleteTodoByIds(Long[] ids);
}
```

#### 4.4.2 TodoServiceImpl（实现）

```java
package com.ruoyi.agent.service.impl;

import com.ruoyi.agent.adapter.TodoStorageAdapter;
import com.ruoyi.agent.domain.AgentTodo;
import com.ruoyi.agent.mapper.AgentTodoMapper;
import com.ruoyi.agent.service.ITodoService;
import com.ruoyi.common.utils.SecurityUtils;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.util.List;

@Service
public class TodoServiceImpl implements ITodoService {

    @Autowired
    private AgentTodoMapper todoMapper;

    @Autowired
    private TodoStorageAdapter todoStorageAdapter;

    @Override
    public List<AgentTodo> selectTodoList(AgentTodo todo) {
        return todoMapper.selectTodoList(todo);
    }

    @Override
    public AgentTodo selectTodoById(Long id) {
        return todoMapper.selectTodoById(id);
    }

    @Override
    public AgentTodo selectTodoByTodoId(String todoId) {
        return todoMapper.selectTodoByTodoId(todoId);
    }

    @Override
    public List<AgentTodo> selectTodoBySession(String sessionId, String tenantId) {
        return todoMapper.selectTodoBySession(sessionId, tenantId);
    }

    @Override
    @Transactional
    public int insertTodo(AgentTodo todo) {
        todo.setCreateBy(SecurityUtils.getUsername());
        return todoMapper.insertTodo(todo);
    }

    @Override
    @Transactional
    public int updateTodo(AgentTodo todo) {
        todo.setUpdateBy(SecurityUtils.getUsername());
        return todoMapper.updateTodo(todo);
    }

    @Override
    @Transactional
    public int updateTodoStatus(String todoId, String status, String resultSummary) {
        return todoMapper.updateTodoStatus(todoId, status, resultSummary);
    }

    @Override
    @Transactional
    public int deleteTodoByIds(Long[] ids) {
        return todoMapper.deleteTodoByIds(ids);
    }
}
```

### 4.5 Controller 层

#### 4.5.1 TodoController

```java
package com.ruoyi.agent.controller;

import com.ruoyi.agent.domain.AgentTodo;
import com.ruoyi.agent.service.ITodoService;
import com.ruoyi.common.annotation.Log;
import com.ruoyi.common.core.controller.BaseController;
import com.ruoyi.common.core.domain.AjaxResult;
import com.ruoyi.common.core.page.TableDataInfo;
import com.ruoyi.common.enums.BusinessType;
import org.apache.shiro.authz.annotation.RequiresPermissions;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/agent/todo")
public class TodoController extends BaseController {

    @Autowired
    private ITodoService todoService;

    @RequiresPermissions("agent:todo:list")
    @GetMapping("/list")
    public TableDataInfo list(AgentTodo todo) {
        startPage();
        return getDataTable(todoService.selectTodoList(todo));
    }

    @RequiresPermissions("agent:todo:query")
    @GetMapping("/{id}")
    public AjaxResult getInfo(@PathVariable Long id) {
        return success(todoService.selectTodoById(id));
    }

    @RequiresPermissions("agent:todo:add")
    @Log(title = "Agent待办", businessType = BusinessType.INSERT)
    @PostMapping
    public AjaxResult add(@RequestBody AgentTodo todo) {
        return toAjax(todoService.insertTodo(todo));
    }

    @RequiresPermissions("agent:todo:edit")
    @Log(title = "Agent待办", businessType = BusinessType.UPDATE)
    @PutMapping
    public AjaxResult edit(@RequestBody AgentTodo todo) {
        return toAjax(todoService.updateTodo(todo));
    }

    @RequiresPermissions("agent:todo:remove")
    @Log(title = "Agent待办", businessType = BusinessType.DELETE)
    @DeleteMapping("/{ids}")
    public AjaxResult remove(@PathVariable Long[] ids) {
        return toAjax(todoService.deleteTodoByIds(ids));
    }
}
```

**与 RuoYi 差异说明**：agent 模块是纯 API 无 Thymeleaf 视图，故用 `@RestController`（宿主 `ruoyi-admin` 的 Controller 因返视图用 `@Controller+@ResponseBody`）。返回类型、`BaseController` 工具方法、`@Log`、`@RequiresPermissions` 完全一致。

#### 4.5.2 AgentInvokeController（同步调用）与 AgentStreamController（流式 SSE）

```java
package com.ruoyi.agent.controller;

import com.ruoyi.agent.adapter.DeepAgentAdapter;
import com.ruoyi.agent.service.IAgentInvokeService;
import com.ruoyi.common.core.controller.BaseController;
import com.ruoyi.common.core.domain.AjaxResult;
import org.apache.shiro.authz.annotation.RequiresPermissions;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;
import java.util.Map;

@RestController
@RequestMapping("/agent/invoke")
public class AgentInvokeController extends BaseController {

    @Autowired
    private IAgentInvokeService agentInvokeService;

    @RequiresPermissions("agent:invoke:sync")
    @PostMapping
    public AjaxResult invoke(@RequestBody Map<String, Object> inputs) {
        return success(agentInvokeService.syncInvoke(inputs));
    }
}
```

```java
package com.ruoyi.agent.controller;

import com.ruoyi.agent.service.IAgentInvokeService;
import org.apache.shiro.authz.annotation.RequiresPermissions;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

@RestController
@RequestMapping("/agent/stream")
public class AgentStreamController {

    @Autowired
    private IAgentInvokeService agentInvokeService;

    @RequiresPermissions("agent:invoke:stream")
    @GetMapping
    public SseEmitter stream(@RequestParam Map<String, Object> inputs) {
        return agentInvokeService.streamInvoke(inputs);
    }
}
```

### 4.6 Adapter 层（内核桥接，方案 A 核心）

#### 4.6.1 DeepAgentAdapter

```java
package com.ruoyi.agent.adapter;

import com.openjiuwen.harness.DeepAgent;
import com.openjiuwen.harness.factory.HarnessFactory;
import com.openjiuwen.harness.schema.config.DeepAgentConfig;
import com.openjiuwen.harness.workspace.Workspace;
import com.ruoyi.agent.config.AgentEngineProperties;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;
import java.util.Iterator;
import java.util.Map;

@Component
public class DeepAgentAdapter {

    @Autowired
    private AgentEngineProperties properties;

    public DeepAgent create(Map<String, Object> inputs) {
        DeepAgentConfig config = DeepAgentConfig.builder()
                .workspacePath(properties.getWorkspacePath())
                .language(properties.getLanguage())
                .maxIterations(properties.getMaxIterations())
                .isTaskLoopEnabled(properties.isTaskLoopEnabled())
                .isTaskPlanningEnabled(properties.isTaskPlanningEnabled())
                .build();
        Workspace workspace = Workspace.builder()
                .rootPath(properties.getWorkspacePath())
                .language(properties.getLanguage())
                .build();
        return HarnessFactory.createDeepAgent(config);
    }

    public Map<String, Object> invoke(DeepAgent agent, Map<String, Object> inputs) {
        return agent.invoke(inputs);
    }

    public Iterator<Object> stream(DeepAgent agent, Map<String, Object> inputs) {
        return agent.stream(inputs);
    }

    public void requestAbort(DeepAgent agent, String sessionId) {
        agent.requestAbort(sessionId);
    }

    public DeepAgent createSubagent(DeepAgent parent, String subagentType, String sessionId) {
        return parent.createSubagent(subagentType, sessionId);
    }
}
```

#### 4.6.2 TodoStorageAdapter（双向桥接 TodoStorage SPI）

```java
package com.ruoyi.agent.adapter;

import com.openjiuwen.core.multitenant.TenantContext;
import com.openjiuwen.harness.tools.TodoItem;
import com.openjiuwen.harness.tools.TodoStorage;
import com.ruoyi.agent.domain.AgentTodo;
import com.ruoyi.agent.mapper.AgentTodoMapper;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;
import java.util.List;
import java.util.stream.Collectors;

@Component
public class TodoStorageAdapter implements TodoStorage {

    @Autowired
    private AgentTodoMapper todoMapper;

    @Override
    public List<TodoItem> load(String sessionId, TenantContext ctx) {
        String tenantId = ctx != null ? ctx.getTenantId() : null;
        List<AgentTodo> todos = todoMapper.selectTodoBySession(sessionId, tenantId);
        return todos.stream().map(this::toTodoItem).collect(Collectors.toList());
    }

    @Override
    public void save(String sessionId, List<TodoItem> items, TenantContext ctx) {
        String tenantId = ctx != null ? ctx.getTenantId() : null;
        todoMapper.deleteTodoBySession(sessionId, tenantId);
        for (TodoItem item : items) {
            AgentTodo todo = toAgentTodo(item, sessionId, tenantId);
            todoMapper.insertTodo(todo);
        }
    }

    @Override
    public void delete(String sessionId, TenantContext ctx) {
        String tenantId = ctx != null ? ctx.getTenantId() : null;
        todoMapper.deleteTodoBySession(sessionId, tenantId);
    }

    private AgentTodo toAgentTodo(TodoItem item, String sessionId, String tenantId) {
        AgentTodo todo = new AgentTodo();
        todo.setTodoId(item.getId());
        todo.setSessionId(sessionId);
        todo.setTenantId(tenantId);
        todo.setContent(item.getContent());
        todo.setActiveForm(item.getActiveForm());
        todo.setDescription(item.getDescription());
        todo.setStatus(item.getStatus().name());
        todo.setPriority(item.getPriority());
        todo.setSelectedModelId(item.getSelectedModelId());
        todo.setDependsOn(item.getDependsOn() != null ? String.join(",", item.getDependsOn()) : null);
        todo.setResultSummary(item.getResultSummary());
        return todo;
    }

    private TodoItem toTodoItem(AgentTodo todo) {
        return TodoItem.builder()
                .id(todo.getTodoId())
                .content(todo.getContent())
                .activeForm(todo.getActiveForm())
                .description(todo.getDescription())
                .status(TodoStatus.valueOf(todo.getStatus()))
                .priority(todo.getPriority())
                .selectedModelId(todo.getSelectedModelId())
                .resultSummary(todo.getResultSummary())
                .build();
    }
}
```

**关键设计**：`TodoStorageAdapter` **实现内核 SPI 接口 `TodoStorage`**，通过 `META-INF/services/...TodoStorageProvider` 注册，使内核 `TodoTool` 无感知地改用 DB 后端——既满足需求 #2"对象之间的关系"，又不破坏内核执行模型。

### 4.7 SPI Provider 层

#### 4.7.1 MyBatisTodoStorageProvider

```java
package com.ruoyi.agent.spi;

import com.openjiuwen.harness.tools.TodoStorage;
import com.openjiuwen.harness.tools.TodoStorageProvider;
import com.ruoyi.agent.adapter.TodoStorageAdapter;
import org.springframework.context.ApplicationContext;
import java.util.Map;

public class MyBatisTodoStorageProvider implements TodoStorageProvider {

    private static ApplicationContext applicationContext;

    public static void setApplicationContext(ApplicationContext ctx) {
        applicationContext = ctx;
    }

    @Override
    public String typeName() {
        return "mybatis";
    }

    @Override
    public TodoStorage create(Map<String, Object> conf) {
        return applicationContext.getBean(TodoStorageAdapter.class);
    }
}
```

#### 4.7.2 MyBatisKVStoreProvider

```java
package com.ruoyi.agent.spi;

import com.openjiuwen.spi.store.BaseKVStore;
import com.openjiuwen.spi.store.KVStoreProvider;
import com.ruoyi.agent.adapter.KvStoreAdapter;
import org.springframework.context.ApplicationContext;
import java.util.Map;

public class MyBatisKVStoreProvider implements KVStoreProvider {

    private static ApplicationContext applicationContext;

    public static void setApplicationContext(ApplicationContext ctx) {
        applicationContext = ctx;
    }

    @Override
    public String typeName() {
        return "mybatis";
    }

    @Override
    public BaseKVStore create(Map<String, Object> conf) {
        return applicationContext.getBean(KvStoreAdapter.class);
    }
}
```

### 4.8 Config 层

#### 4.8.1 AgentEngineConfig（Spring 托管内核）

```java
package com.ruoyi.agent.config;

import com.openjiuwen.core.runner.Runner;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class AgentEngineConfig {

    @Bean(destroyMethod = "close")
    public Runner runner() {
        return Runner.getInstance();
    }
}
```

#### 4.8.2 AgentEngineProperties

```java
package com.ruoyi.agent.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Component
@ConfigurationProperties(prefix = "agent.engine")
public class AgentEngineProperties {

    private String workspacePath;
    private String language;
    private int maxIterations;
    private boolean taskLoopEnabled;
    private boolean taskPlanningEnabled;
    private boolean enableTenantIsolation;
    private String tenantDataRoot;
    private String todoStorageType;
    private String sessionStoreType;
    private String kvStoreType;
    private String checkpointerType;
    private String apiconfigPath;

    public String getWorkspacePath() { return workspacePath; }
    public void setWorkspacePath(String workspacePath) { this.workspacePath = workspacePath; }
    public String getLanguage() { return language; }
    public void setLanguage(String language) { this.language = language; }
    public int getMaxIterations() { return maxIterations; }
    public void setMaxIterations(int maxIterations) { this.maxIterations = maxIterations; }
    public boolean isTaskLoopEnabled() { return taskLoopEnabled; }
    public void setTaskLoopEnabled(boolean taskLoopEnabled) { this.taskLoopEnabled = taskLoopEnabled; }
    public boolean isTaskPlanningEnabled() { return taskPlanningEnabled; }
    public void setTaskPlanningEnabled(boolean taskPlanningEnabled) { this.taskPlanningEnabled = taskPlanningEnabled; }
    public boolean isEnableTenantIsolation() { return enableTenantIsolation; }
    public void setEnableTenantIsolation(boolean enableTenantIsolation) { this.enableTenantIsolation = enableTenantIsolation; }
    public String getTenantDataRoot() { return tenantDataRoot; }
    public void setTenantDataRoot(String tenantDataRoot) { this.tenantDataRoot = tenantDataRoot; }
    public String getTodoStorageType() { return todoStorageType; }
    public void setTodoStorageType(String todoStorageType) { this.todoStorageType = todoStorageType; }
    public String getSessionStoreType() { return sessionStoreType; }
    public void setSessionStoreType(String sessionStoreType) { this.sessionStoreType = sessionStoreType; }
    public String getKvStoreType() { return kvStoreType; }
    public void setKvStoreType(String kvStoreType) { this.kvStoreType = kvStoreType; }
    public String getCheckpointerType() { return checkpointerType; }
    public void setCheckpointerType(String checkpointerType) { this.checkpointerType = checkpointerType; }
    public String getApiconfigPath() { return apiconfigPath; }
    public void setApiconfigPath(String apiconfigPath) { this.apiconfigPath = apiconfigPath; }
}
```

#### 4.8.3 AgentSpiBootstrap（Spring 与 ServiceLoader 桥接）

```java
package com.ruoyi.agent.config;

import com.openjiuwen.spi.store.KVStoreFactory;
import com.ruoyi.agent.spi.MyBatisKVStoreProvider;
import com.ruoyi.agent.spi.MyBatisSessionStoreProvider;
import com.ruoyi.agent.spi.MyBatisTodoStorageProvider;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.ApplicationContext;
import org.springframework.stereotype.Component;
import jakarta.annotation.PostConstruct;

@Component
public class AgentSpiBootstrap {

    @Autowired
    private ApplicationContext applicationContext;

    @PostConstruct
    public void init() {
        MyBatisTodoStorageProvider.setApplicationContext(applicationContext);
        MyBatisKVStoreProvider.setApplicationContext(applicationContext);
        MyBatisSessionStoreProvider.setApplicationContext(applicationContext);
        KVStoreFactory.register("mybatis", new MyBatisKVStoreProvider());
    }
}
```

### 4.9 重构后对象关系小结

| 关系类型 | 示例 |
|---|---|
| 继承 | `AgentTodo extends BaseEntity`；`TodoController extends BaseController` |
| 实现 | `TodoServiceImpl implements ITodoService`；`TodoStorageAdapter implements TodoStorage`；`MyBatisTodoStorageProvider implements TodoStorageProvider` |
| 组合 | `TodoServiceImpl` 持有 `AgentTodoMapper` + `TodoStorageAdapter` |
| 依赖 | `DeepAgentAdapter` → `HarnessFactory.createDeepAgent`；`AgentEngineConfig` → `Runner` |
| 关联 | `AgentTeam` 1—N `AgentTeamMember`（外键 team_name，Service 组装） |

---

## 5. 集成方案与配置

### 5.1 Maven 集成

#### 5.1.1 RuoYi 根 pom.xml 修改

在根 pom.xml 的 `<modules>` 增加：

```xml
<modules>
    <module>ruoyi-admin</module>
    <module>ruoyi-framework</module>
    <module>ruoyi-system</module>
    <module>ruoyi-quartz</module>
    <module>ruoyi-generator</module>
    <module>ruoyi-common</module>
    <module>agent-core-java</module>   <!-- 新增：引擎内核 -->
    <module>ruoyi-agent</module>        <!-- 新增：适配层 -->
</modules>
```

在 `<properties>` 与 `<dependencyManagement>` 声明引擎坐标：

```xml
<properties>
    ...
    <agent.engine.version>0.1.13</agent.engine.version>
</properties>

<dependencyManagement>
    <dependencies>
        <dependency>
            <groupId>com.openjiuwen</groupId>
            <artifactId>agent-core-java</artifactId>
            <version>${agent.engine.version}</version>
        </dependency>
    </dependencies>
</dependencyManagement>
```

**注意**：agent-core-java 原 pom.xml 的 groupId `com.openjiuwen`、Java 17 不变；其 `<dependencies>` 中与 RuoYi 冲突的部分（Jackson 2.17 等）保持独立，作为引擎 JAR 被 ruoyi-agent 引入，不参与 RuoYi 的 spring-boot-dependencies BOM 管理。

#### 5.1.2 ruoyi-agent/pom.xml

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

**设计决策**：
- 仅依赖 `ruoyi-common`（基础设施）+ `agent-core-java`（引擎），**不依赖** `ruoyi-framework/system/admin`（避免反向依赖与循环）
- Shiro 鉴权注解（`@RequiresPermissions`）由宿主 `ruoyi-framework` 的 ShiroConfig 提供拦截，agent 模块只声明注解
- Druid/PageHelper/MyBatis 由 `ruoyi-common` 间接传递，agent 模块不重复声明

#### 5.1.3 ruoyi-admin/pom.xml 修改

```xml
<dependencies>
    ...
    <dependency>
        <groupId>com.ruoyi</groupId>
        <artifactId>ruoyi-agent</artifactId>
    </dependency>
</dependencies>
```

### 5.2 配置组织

#### 5.2.1 application.yml 追加 agent 配置节

```yaml
agent:
  engine:
    workspace-path: ${user.home}/ruoyi-agent/workspace
    language: cn
    max-iterations: 25
    task-loop-enabled: true
    task-planning-enabled: true
    enable-tenant-isolation: false
    tenant-data-root: ${user.home}/ruoyi-agent/tenant
    todo-storage-type: mybatis          # 新增 MyBatis 实现（替代 file/kv）
    session-store-type: mybatis
    kv-store-type: mybatis             # 新增 MyBatis KV 实现
    checkpointer-type: persistence      # 复用内核 PersistenceCheckpointer（底层走 MyBatis KV）
    apiconfig-path: classpath:APIKEY/apiconfig.json
```

#### 5.2.2 MyBatis 配置复用

agent 模块**不新建** `SqlSessionFactory`，复用宿主 `ruoyi-framework` 的 MyBatisConfig 配置：
- `typeAliasesPackage=com.ruoyi.**.domain` → `com.ruoyi.agent.domain.*` 自动被扫描为别名（如 `AgentTodo`）
- `mapperLocations=classpath*:mapper/**/*Mapper.xml` → `ruoyi-agent/src/main/resources/mapper/agent/*Mapper.xml` 自动被扫描
- `configLocation=classpath:mybatis/mybatis-config.xml` → 复用全局 settings

**多数据源（可选）**：若 agent 表需独立库，可用 RuoYi 的 `@DataSource(DataSourceType.SLAVE)` 注解切换到从库，在 `application-druid.yml` 配置 `slave` 数据源指向 agent 库；默认与宿主同库（`ry` 库内 `agent_*` 表）。

### 5.3 SPI ServiceLoader 注册

agent 模块需提供 SPI 注册文件，使内核 `ServiceLoader` 发现 MyBatis 后端实现：

```
ruoyi-agent/src/main/resources/META-INF/services/
├── com.openjiuwen.harness.tools.TodoStorageProvider
│       → 内容: com.ruoyi.agent.spi.MyBatisTodoStorageProvider
├── com.openjiuwen.spi.store.KVStoreProvider
│       → 内容: com.ruoyi.agent.spi.MyBatisKVStoreProvider
└── com.openjiuwen.core.session.store.SessionStoreProvider
        → 内容: com.ruoyi.agent.spi.MyBatisSessionStoreProvider
```

**Spring 集成点**：因 `ServiceLoader` 创建的 Provider 实例无法直接注入 Spring Bean，由 `AgentSpiBootstrap`（`@Component` + `@PostConstruct`）在启动时调用各 Provider 的静态 `setApplicationContext(...)` 注入 Spring 上下文，再由 Provider 从上下文获取 adapter Bean。这是 Spring 与 ServiceLoader 桥接的标准做法。

### 5.4 Shiro 权限菜单

agent 模块的 Controller 使用 `@RequiresPermissions("agent:xxx:yyy")`，需在 RuoYi 的 `sys_menu` 表插入菜单与权限标识。SQL 片段（设计文档保留，不落盘 .sql）：

```sql
-- Agent 一级菜单
INSERT INTO sys_menu(menu_id, menu_name, parent_id, order_num, path, component,
    query, is_frame, is_cache, menu_type, visible, status, perms, icon,
    create_by, create_time, update_by, update_time, remark)
VALUES(下一可用ID, 'Agent管理', 0, 100, 'agent', NULL, '', 1, 0, 'M', '0', '0',
    'agent:manager', 'fa fa-robot', 'admin', sysdate(), '', NULL, '');

-- 二级菜单 + 按钮权限（以 Todo 为例）
INSERT INTO sys_menu VALUES(下一可用ID, '待办任务', 父ID, 1, 'todo', 'agent/todo/list',
    '', 1, 0, 'C', '0', '0', 'agent:todo:list', '#', 'admin', sysdate(), '', NULL, '');
INSERT INTO sys_menu VALUES(下一可用ID, '待办新增', 父ID, 2, '', '', '', 1, 0, 'F', '0', '0',
    'agent:todo:add', '#', 'admin', sysdate(), '', NULL, '');
INSERT INTO sys_menu VALUES(下一可用ID, '待办修改', 父ID, 3, '', '', '', 1, 0, 'F', '0', '0',
    'agent:todo:edit', '#', 'admin', sysdate(), '', NULL, '');
INSERT INTO sys_menu VALUES(下一可用ID, '待办删除', 父ID, 4, '', '', '', 1, 0, 'F', '0', '0',
    'agent:todo:remove', '#', 'admin', sysdate(), '', NULL, '');
-- 其余模块（session/evolution/team/memory/subagent/skill/invoke/stream）同模式
```

### 5.5 启动与扫描

- **启动类**：复用 `RuoYiApplication`，`@SpringBootApplication` 默认扫描 `com.ruoyi.*`，`com.ruoyi.agent` 自动被扫描，无需额外配置
- **Mapper 扫描**：依赖宿主 `MyBatisConfig` 的 `mapperLocations`，无需 `@MapperScan`
- **内核 Runner 单例**：由 `AgentEngineConfig` 注册为 Bean，`@Bean(destroyMethod="close")` 确保容器关闭时释放 `Runner.resourceMgr`
- **SPI 引导**：`AgentSpiBootstrap` 在 `@PostConstruct` 阶段注入 ApplicationContext 到各 Provider 静态字段，并调用 `KVStoreFactory.register("mybatis", ...)` 等编程式注册（兜底 ServiceLoader）

### 5.6 集成验证清单

- [ ] `mvn clean install -pl ruoyi-agent -am` 编译通过
- [ ] `RuoYiApplication` 启动无 Bean 冲突
- [ ] `/agent/todo/list` 在持有 `agent:todo:list` 权限下返回 `TableDataInfo`
- [ ] 内核 `TodoTool` 调用实际命中 `agent_todo` 表（验证 SPI 桥接）
- [ ] `DeepAgent.invoke` 通过 `DeepAgentAdapter` 正常返回结果

---

## 6. 迁移说明

### 6.1 原表 → 新表字段映射

| 原表 | 新表 | 主要变更 |
|---|---|---|
| user_message | agent_message | 加 id 主键，message_id 转唯一键；补 create_by/time/update_by/time/del_flag；timestamp→msg_timestamp（避免与 SQL 保留字冲突） |
| scope_user_mapping | agent_scope_user | 加 id 主键；联合主键 (user_id, scope_id) 转唯一键；补 del_flag |
| memory_meta | agent_memory_meta | 加 id 主键；table_name 转唯一键；补 del_flag |
| kv_store | agent_kv_store | 字段 k/v → store_key/store_value（消除单字符）；加 namespace/tenant_id/expire_at；补 del_flag |
| team_info | agent_team | 加 id 主键；team_name 转唯一键；desc→description（避免保留字）；补 RuoYi 字段 |
| team_member | agent_team_member | 加 id 主键；联合唯一键；补 RuoYi 字段 |
| team_task_<sid> | agent_team_task | 动态表合并为单表，原后缀 sid 转为 session_id 列；加索引 idx_team_session |
| team_task_dependency_<sid> | agent_team_task_dep | 动态表合并；联合唯一键 (task_id, depends_on_task_id) |
| team_message_<sid> | agent_team_message | 动态表合并；timestamp→msg_timestamp；补 is_read 列 |
| message_read_status_<sid> | agent_team_msg_read | 动态表合并；联合唯一键 |
| （无） | agent_todo | 全新表，对应 TodoItem |
| （无） | agent_session | 全新表，对应 Session |
| （无） | agent_checkpoint | 全新表，对应 PersistenceCheckpointer |
| （无） | agent_session_state | 全新表，对应 GraphStoreState |
| （无） | agent_evolution | 全新表，对应 EvolutionRecord |
| （无） | agent_model_usage | 全新表，对应 ModelUsageRecord |

### 6.2 动态表合并策略

原 `TeamDatabase` 按 session 动态建表（如 `team_task_abc123`），重构后统一为单表 `agent_team_task` + `session_id` 列：
- 查询：通过 `where session_id = ? and team_name = ?` 替代原表名拼接
- 索引：`(team_name, session_id)` 复合索引保证查询性能
- 数据迁移：原各动态表数据需 ETL 迁移到单表，补 session_id 列值

### 6.3 数据迁移注意事项

1. **逻辑删除对齐**：原表无 del_flag 的，迁移时统一置 '0'
2. **时间格式**：原 VARCHAR 时间戳迁移为 DATETIME 时需格式转换
3. **JSON 字段**：depends_on / meta_data / context / change_patch 等保留 JSON 字符串，不做结构化拆分
4. **租户字段**：原无 tenant_id 的记录迁移时按所属租户回填

### 6.4 兼容性说明

- 内核 `FileTodoStorage` / `KvTodoStorage` 保留可用，通过配置 `todo-storage-type` 切换，不强制使用 MyBatis
- 内核 `RedisCheckpointer` / `GaussDbStore` 保留可用，作为可选 extensions 依赖
- 重构后 `agent-core-java` 原有测试不受影响（不修改内核源码）

---

## 7. 核心对象清单（harness 工程提取）

本节对应需求 #1，列出 harness 工程提取的核心对象及其属性、方法、关系（重构重点）。

### 7.1 核心智能体层

| 对象 | 类型 | 关键属性 | 关键方法 | 关系 |
|---|---|---|---|---|
| DeepAgent | 具体类 | card, config, workspace, agent(ReActAgent), currentMode, registeredRails, registeredTools, registeredMcps, sessionToolkit, workspaceResolver, tieredWorkspaceManager, sessionLoopCoordinators, loopController, taskManager, eventHandler, kvStore | createDeepAgent(静态), ensureInitialized, invoke, stream, requestAbort, steer, createSubagent, ensurePlanFile, registerHarnessTool, setKvStore | 组合 ReActAgent/Workspace/BaseKVStore；依赖 HarnessFactory |
| HarnessFactory | 工具类 | — | createDeepAgent(多个重载), enrichConfig, injectKvStore, injectGeneralPurposeSubagent, resolveWorkspace | 依赖 Runner/SubAgentConfig/各 Rail |

### 7.2 配置层

| 对象 | 类型 | 关键属性 |
|---|---|---|
| DeepAgentConfig | @Data @Builder | systemPrompt, maxIterations, isTaskLoopEnabled, isTaskPlanningEnabled, language, defaultMode, workspacePath, completionTimeout, permissions, tools, rails, mcps, subagents, extraPromptSections, skillDirectories, skillMode, model, backend, promptMode, skills, enableSkillDiscovery, factoryKwargs, isAsyncSubagentEnabled, isGeneralPurposeAgentEnabled, isRestrictToWorkDirEnabled, sysOperation, permissionHost, isEnableTenantIsolation, tenantDataRoot, workspaceSecondaryTiers, workspaceTierConfigs, todoStorageType, sessionStoreType, kvStoreConfig, tmpTtl, tmpTtlScanInterval |
| Workspace | @Data @Builder | rootPath, language, links |
| AgentMode | 枚举 | NORMAL, PLAN |

### 7.3 Rails 层

| 对象 | 类型 | 父类 | 优先级 | 职责 |
|---|---|---|---|---|
| AgentRail | 抽象类(core) | — | 50 | 8 个生命周期钩子 |
| DeepAgentRail | 抽象类 | AgentRail | 50 | harness rail 基类 |
| BaseInterruptRail | 抽象类 | AgentRail | — | 中断/恢复基类 |
| SecurityRail | 具体 | DeepAgentRail | 80 | 只读保护 |
| TaskCompletionRail | 具体 | DeepAgentRail | 10 | 完成承诺信号 |
| TaskPlanningRail | 具体 | DeepAgentRail | — | 任务规划 |
| SessionRail | 具体 | DeepAgentRail | 95 | 异步子代理会话 |
| SubagentRail | 具体 | DeepAgentRail | 95 | 同步子代理委派 |
| SkillUseRail | 具体 | DeepAgentRail | 100 | 技能发现/加载 |
| McpRail | 具体 | DeepAgentRail | 95 | MCP 资源工具 |
| MemoryRail | 具体 | DeepAgentRail | 80 | 记忆工具 |
| CodingMemoryRail | 具体 | MemoryRail | 80 | 编码记忆 |
| EvolutionRail | 具体 | DeepAgentRail | 60 | 进化记录触发 |
| AskUserRail | 具体 | BaseInterruptRail | 90 | ask_user 中断 |
| ConfirmInterruptRail | 具体 | BaseInterruptRail | 90 | 确认中断 |
| PermissionInterruptRail | 具体 | BaseInterruptRail | 90 | 权限中断 |

### 7.4 任务循环层

| 对象 | 类型 | 关键属性 | 关键方法 |
|---|---|---|---|
| TaskLoopController | 具体类 | sessionStates, defaultQueues | prepareRound, waitRoundCompletion, resolveCompletion, enqueueFollowUp, enqueueSteering, drainFollowUp, drainSteering, abort, clearSession |
| LoopCoordinator | 具体类 | evaluators, iteration, tokenUsage, isAborted, startMillis | reset, incrementIteration, addTokenUsage, shouldContinue, getState, loadState |
| StopConditionEvaluator | 接口 | — | (evaluator 链) |

### 7.5 子代理层

| 对象 | 类型 | 关键属性/方法 |
|---|---|---|
| SubAgentConfig | @Data @Builder | agentCard, systemPrompt, language, maxIterations, isTaskLoopEnabled, factoryName, factoryKwargs, metadata, executionMode, role, tools, rails, mcps, subagents, skillDirectories, skillMode, skills, enableSkillDiscovery, model, backend, promptMode, sysOperation, workspacePath, isRestrictToWorkDir；方法 toDeepAgentConfig(), hasRail(Class), railClassNames() |
| SubAgentRegistry | 工具类 | register, build, contains, names；内置 6 种：code_agent, explore_agent, plan_agent, research_agent, verification_agent, browser_agent |

### 7.6 安全层

| 对象 | 类型 | 关键方法 |
|---|---|---|
| PermissionEngine | 具体类 | evaluateGlobalPolicyDirectly, checkPermission |
| PermissionFactory | 工具类 | buildPermissionInterruptRail |

### 7.7 工具层（持久化相关）

| 对象 | 类型 | 关键属性/方法 |
|---|---|---|
| TodoStorage | 接口(SPI) | load(sessionId, ctx), save(sessionId, items, ctx), delete(sessionId, ctx) |
| TodoItem | @Data @Builder | id, content, activeForm, description, status(TodoStatus), dependsOn, resultSummary, metaData, selectedModelId, priority；方法 isPending/isCompleted/isTerminal |
| TodoStatus | 枚举 | TODO, PENDING, IN_PROGRESS, DONE, COMPLETED, CANCELLED |
| FileTodoStorage | 具体 | 文件实现（保留） |
| KvTodoStorage | 具体 | KV 实现（保留） |
| TodoStorageFactory | 工厂 | ServiceLoader 发现 Provider |
| EvolutionRecord | @Data @Builder | id, source, timestamp, context, change(EvolutionPatch), isApplied, score, usageStats, skillVersion；方法 isPending(), toMap() |
| ModelUsageRecord | 类 | 模型用量记录 |

### 7.8 对象关系图（harness 内部）

```
DeepAgent ──组合──> ReActAgent(core)
         ├──组合──> Workspace
         ├──组合──> DeepAgentConfig
         ├──组合──> BaseKVStore(spi)
         ├──组合──> TaskLoopController ──组合──> LoopCoordinator ──组合──> StopConditionEvaluator*
         ├──组合──> TaskManager/EventQueue(core.controller)
         ├──组合──> TenantWorkspaceResolver/TieredWorkspaceManager(core.multitenant)
         ├──持有──> List<DeepAgentRail> (SecurityRail/TaskCompletionRail/...)
         ├──持有──> List<Tool> (TodoTool/BashTool/...)
         └──依赖──> HarnessFactory(创建自身)

AgentRail(core) <── DeepAgentRail <── SecurityRail/TaskCompletionRail/...
                <── BaseInterruptRail <── AskUserRail/ConfirmInterruptRail/PermissionInterruptRail

TodoTool ──依赖──> TodoStorage(接口) <── TodoStorageAdapter(ruoyi-agent, 新增)
                                  <── FileTodoStorage(保留)
                                  <── KvTodoStorage(保留)

HarnessFactory ──依赖──> Runner(core)
                ├──依赖──> SubAgentConfig/SubAgentRegistry
                ├──依赖──> 各默认 Rail
                └──依赖──> KVStoreFactory(spi)
```

---

## 8. 变更记录

| 版本 | 日期 | 变更内容 | 作者 |
|---|---|---|---|
| v1.0 | 2026-07-29 | 初版，含架构/模块映射/15表DDL/核心类/集成/迁移/核心对象清单 | TRAE |