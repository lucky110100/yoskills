# 09 - 依赖关系

> 交叉引用: [01-project-overview](01-project-overview.md) | [02-overall-architecture](02-overall-architecture.md) | [07-extensions-and-spi-module](07-extensions-and-spi-module.md) | [10-running-guide](10-running-guide.md)

本篇梳理 agent-core-java 的内部模块依赖图、核心外部依赖、可选后端、测试依赖与构建插件，并在末尾与 Python agent-core 的依赖体系做对照。所有版本号取自 [pom.xml](file:///D:/jiuwen/main/agent-core-java/pom.xml)（`0.1.14`）。

## 一、内部模块依赖图

agent-core-java 采用分层包结构，`com.openjiuwen` 为顶级 groupId。箭头 `→` 表示"依赖于"，依赖方向自上而下收敛到 `core` 基座。

```
                         ┌─────────────────────────┐
                         │      examples / 用户     │  应用层
                         │      业务代码            │
                         └────────────┬────────────┘
                                      │
            ┌────────────┬────────────┼────────────┬────────────┐
            ▼            ▼            ▼            ▼            ▼
      ┌───────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐
      │  harness  │ │agentteams│ │agentevolv│ │   spi    │ │ dev_tools│
      │ (deep_    │ │          │ │  ing +   │ │ (store   │ │  (tune)  │
      │  agent)   │ │          │ │autoharness││  工厂)   │ │          │
      └─────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘
            │            │            │            │            │
            └────────────┴────────────┼────────────┘            │
                                        │                        │
                                        ▼                        │
                         ┌─────────────────────────────┐        │
                         │           core 层            │◄───────┘
                         │  graph(pregel) workflow      │
                         │  runner session single_agent │
                         │  foundation(llm/tool)        │
                         │  controller sysop memory    │
                         │  multitenant store common    │
                         └─────────────────────────────┘
```

### 1.1 分层依赖说明

| 依赖链 | 说明 |
|--------|------|
| `core ← harness ← deep_agent` | [DeepAgent](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/deep_agent/DeepAgent.java#L97) 位于 `harness.deep_agent`，封装内部 ReActAgent、Rails、TaskLoop、子代理；harness 依赖 core 的 Runner / session / single_agent / foundation |
| `core ← agentteams` | [TeamAgent](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/agent/TeamAgent.java) 位于 `agentteams`，组合 DeepAgent 实现 Leader/Teammate 团队，依赖 harness 与 core |
| `core ← agentevolving ← autoharness` | `agentevolving` 提供 Trainer/Evaluator/Optimizer（RL 与指令优化），`autoharness` 在其上构建端到端改码 7 阶段流水线，二者均依赖 core |
| `core + spi ← extensions` | 扩展层通过 SPI 工厂（`java.util.ServiceLoader`）接入存储/向量后端，core 提供基座，spi 定义 [BaseDbStore](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/spi/store/BaseDbStore.java) / [BaseKVStore](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/spi/store/BaseKVStore.java) 抽象 |
| `core ← dev_tools` | `dev_tools.tune` 提供调参 Case/Trainer，依赖 core 的 foundation.llm / foundation.tool |

### 1.2 core 层内部依赖

```
common（基础，被所有模块依赖）
  ▲
  ├── graph（Pregel BSP 引擎）→ common, session, workflow
  ├── workflow（工作流 API）→ graph, session, common
  ├── foundation（LLM/Tool 抽象）→ common, runner
  ├── runner（[Runner](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/runner/Runner.java#L44) 单例 + ResourceMgr）→ common, session, foundation, workflow
  ├── session（会话/检查点/VCS）→ foundation, graph.store
  ├── single_agent（ReActAgent/WorkflowAgent）→ runner, session, foundation, workflow
  ├── multitenant（多租户隔离）→ session, common
  ├── sysop（系统操作）→ common
  └── memory / store / operator → common, session
```

## 二、核心外部依赖

> 完整定义见 [pom.xml](file:///D:/jiuwen/main/agent-core-java/pom.xml) `<dependencies>` 段。Java 17、Maven 3.9+。

| 依赖 | groupId:artifactId | 版本 | 作用 | scope |
|------|-------------------|------|------|-------|
| Jackson | `com.fasterxml.jackson.core:jackson-databind` | 2.18.8 | JSON 序列化/反序列化（含 `jackson-datatype-jsr310` 时间类型） | compile |
| SnakeYAML | `org.yaml:snakeyaml` | 2.2 | YAML 解析（技能/Skill 与 harness_config） | compile |
| SLF4J | `org.slf4j:slf4j-api` | 2.0.12 | 日志门面 | compile |
| Logback | `ch.qos.logback:logback-classic` | 1.5.37 | 日志实现（经 BOM 锁定） | compile |
| Lombok | `org.projectlombok:lombok` | 1.18.32 | `@Data`/`@Builder`/`@Getter` 代码生成 | provided |
| OkHttp | `com.squareup.okhttp3:okhttp` | 4.12.0 | HTTP 客户端（LLM 调用/MCP） | compile |
| Reactor | `io.projectreactor:reactor-core` | 3.6.2 | 响应式编程（流式输出/WebFlux） | compile |
| Jedis | `redis.clients:jedis` | 5.1.5 | Redis 客户端（检查点/KV 存储） | compile |
| OpenAI Java | `com.openai:openai-java` | 4.32.0 | OpenAI 兼容 LLM SDK | compile |
| Dashscope | `com.alibaba:dashscope-sdk-java` | 2.22.17 | 阿里云通义 LLM SDK（排除 slf4j-simple 避免双绑定） | compile |
| OpenTelemetry | `io.opentelemetry:opentelemetry-*` | 1.64.0 | 可观测性（OTLP/gRPC/Logging exporter） | compile/runtime |
| Milvus | `io.milvus:milvus-sdk-java` | 2.6.22 | 向量数据库（排除 kotlin-stdlib-common） | compile |
| pgvector | `com.pgvector:pgvector` | 0.1.6 | PostgreSQL 向量扩展 | compile |
| PostgreSQL | `org.postgresql:postgresql` | 42.7.12 | PostgreSQL JDBC 驱动 | compile |
| SQLite | `org.xerial:sqlite-jdbc` | 3.53.2.1 | 嵌入式 SQL JDBC 驱动 | compile |
| H2 | `com.h2database:h2` | 2.2.224 | 嵌入式数据库（测试与原型） | test |
| Bouncy Castle | `org.bouncycastle:bcprov-jdk18on` | 1.85 | 加密（Pulsar 依赖锁定） | compile |
| Guava | `com.google.guava:guava` | 33.0.0-jre | 通用工具集 | compile |
| Kotlin BOM | `org.jetbrains.kotlin:kotlin-bom` | 2.4.10 | 统一 Kotlin 传递依赖版本 | import |
| Protobuf | `com.google.protobuf:protobuf-java` | 3.25.9 | 序列化（gRPC/Milvus） | compile |
| Pulsar | `org.apache.pulsar:pulsar-client` | 4.2.3 | 分布式消息队列 | compile |
| gRPC | `io.grpc:grpc-netty-shaded` | 1.82.1 | OTLP gRPC 传输 | runtime |
| PDFBox | `org.apache.pdfbox:pdfbox` | 2.0.37 | PDF 文本抽取 | compile |
| POI | `org.apache.poi:poi-ooxml` | 5.5.1 | Office 文档处理 | compile |
| JSON Schema | `com.github.victools:jsonschema-generator` | 4.38.0 | 工具入参 Schema 生成 | compile |
| JNA | `net.java.dev.jna:jna` | 5.19.1 | 本地调用 | compile |

### 2.1 版本锁定策略

[pom.xml](file:///D:/jiuwen/main/agent-core-java/pom.xml) 通过 `<dependencyManagement>` 引入三个 BOM 统一传递依赖版本，避免 Pulsar / Milvus / OpenAI 引入脆弱或分裂版本：

- `jackson-bom` 2.18.8
- `opentelemetry-bom` 1.64.0
- `kotlin-bom` 2.4.10

并对 ByteBuddy（`1.15.11`，适配 JDK21 CI）、Logback、Bouncy Castle、Guava 等做显式版本锁定。

## 三、可选依赖与扩展后端

agent-core-java 通过 SPI（`com.openjiuwen.spi`）以工厂模式接入多种存储/向量后端，运行时按配置选择，无需全部引入即可编译。下表列出各后端及其依赖与所属模块：

| 后端 | 依赖 | 模块 | 说明 |
|------|------|------|------|
| Redis | Jedis 5.1.5 | `spi.store` / `core.session.checkpointer` | 检查点、KV 存储、Todo 持久化；支持单机与集群 |
| Milvus | milvus-sdk-java 2.6.22 | `core.retrieval` / `spi.store` | 向量检索，排除 kotlin-stdlib-common |
| Chroma | Chroma 客户端 | `core.retrieval` | 轻量向量库 |
| pgvector | pgvector 0.1.6 + postgresql 42.7.12 | `core.retrieval` / `spi.store` | PostgreSQL 向量扩展 |
| Elasticsearch | ES 客户端 | `spi.store` | 文档/向量混合检索 |
| GaussDB | PostgreSQL 驱动复用 | `spi.store` | 华为 GaussDB 兼容 PG 协议 |
| SQLite | sqlite-jdbc 3.53.2.1 | `spi.store` | 嵌入式 SQL，无需独立服务 |
| H2 | h2 2.2.224 | `spi.store`（test scope） | 嵌入式 DB，主要用于测试 |
| InMemory | 无外部依赖 | `core.store` | 默认内存实现，零依赖启动 |

> SPI 工厂通过 [BaseDbStore](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/spi/store/BaseDbStore.java) / [BaseKVStore](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/spi/store/BaseKVStore.java) 抽象，由 `java.util.ServiceLoader` 发现具体实现，调用方在 `RunnerConfig` / `DeepAgentConfig.backend` 中指定后端类型即可切换。

## 四、测试依赖

| 依赖 | groupId:artifactId | 版本 | 作用 | scope |
|------|-------------------|------|------|-------|
| JUnit 5 | `org.junit.jupiter:junit-jupiter` | 5.10.2 | 测试框架（Jupiter API + 引擎） | test |
| Mockito | `org.mockito:mockito-core` | 5.14.2 | Mock 框架（JDK21 需作为 Java agent 加载） | test |
| AssertJ | `org.assertj:assertj-core` | 3.27.7 | 流式断言 | test |
| Reactor Test | `io.projectreactor:reactor-test` | 3.6.2 | 响应式流测试（`StepVerifier`） | test |
| H2 | `com.h2database:h2` | 2.2.224 | 嵌入式 DB 测试夹具 | test |
| OpenTelemetry SDK Testing | `io.opentelemetry:opentelemetry-sdk-testing` | 1.64.0 | 可观测性测试夹具 | test |
| ByteBuddy | `net.bytebuddy:byte-buddy` | 1.15.11 | Mockito 运行时字节码增强（5.2.0 拉 1.14.x 仅支持 JDK≤20，故升 5.11+） | test |

> Mockito 在 JDK21 下因自附加限制需以 `-javaagent` 显式加载，详见 [pom.xml](file:///D:/jiuwen/main/agent-core-java/pom.xml) Surefire `argLine` 配置。

## 五、构建与插件

### 5.1 编译插件

| 插件 | 版本 | 作用 |
|------|------|------|
| maven-compiler-plugin | 3.12.1 | 编译 Java 17，`<parameters>true` 保留参数名；`annotationProcessorPaths` 注册 Lombok |
| maven-dependency-plugin | 3.7.0 | `properties` 目标将依赖路径输出为属性（供 Surefire 引用 mockito jar 路径） |

### 5.2 测试插件

| 插件 | 版本 | 作用 |
|------|------|------|
| maven-surefire-plugin | 3.2.5 | 单元测试执行；`<groups>` / `<excludedGroups>` 通过 `system-test` 标签隔离系统测试 |
| jacoco-maven-plugin | 0.8.11 | `prepare-agent` 注入代理 + `report` 阶段生成覆盖率报告 |

[pom.xml](file:///D:/jiuwen/main/agent-core-java/pom.xml) 默认配置：

```xml
<surefire.groups></surefire.groups>
<surefire.excludedGroups>system-test</surefire.excludedGroups>
```

- `mvn test`：仅运行非 `system-test` 标签的单元测试（CI 默认绿色门禁）。
- `mvn verify -Dsystem-test`（即 `-Dsurefire.groups=system-test -Dsurefire.excludedGroups=`）：运行需真实凭证/外部服务的系统测试。
- Surefire `forkedProcessTimeoutInSeconds=900`，防止单个挂起测试（如 MCP stdio）阻塞整套件。
- Jacoco `report` 绑定 `test` 阶段，输出 `target/site/jacoco/` 覆盖率报告。

## 六、与 Python agent-core 依赖对照

agent-core-java 与 Python agent-core 在依赖体系上呈"对等移植 + 语言特色"关系：

| 维度 | Java（agent-core-java） | Python（agent-core） | 说明 |
|------|------------------------|----------------------|------|
| 运行时 | Java 17 | Python 3.11–3.13 | Java 强类型、JIT；Python 动态、解释执行 |
| 包管理 | Maven 3.9+（pom.xml） | uv / pip（pyproject.toml） | Maven 声明式 POM；Python 推荐 uv |
| JSON | Jackson 2.18.8 | 标准库 + json-repair | Jackson 强类型反序列化；Python 用 Pydantic |
| YAML | SnakeYAML 2.2 | PyYAML | 均用于技能/配置 |
| 日志 | SLF4J 2.0.12 + Logback 1.5.37 | loguru | Java 门面+实现分离；Python 一体化 |
| 代码生成 | Lombok 1.18.32（provided） | 无 | Java 用注解生成 getter/builder；Python 无此需求 |
| HTTP | OkHttp 4.12.0 | aiohttp / requests | Java 同步+连接池；Python 异步优先 |
| 响应式 | Reactor 3.6.2 | anyio / asyncio | Java Project Reactor；Python asyncio |
| Redis | Jedis 5.1.5 | redis 7.1.0 | 均支持集群模式 |
| LLM SDK | openai-java 4.32.0 + dashscope 2.22.17 | openai 1.108.0 + dashscope 1.25.6 | Java 用官方 SDK；Python 同 |
| 向量库 | milvus 2.6.22 / pgvector 0.1.6 | pymilvus 2.6.x / pgvector | Java Milvus 排除 kotlin；Python 纯 Python |
| 关系 DB | postgresql 42.7.12 / sqlite 3.53 / h2 | asyncpg / aiosqlite / sqlalchemy | Java JDBC 同步；Python 异步驱动 |
| 可观测性 | OpenTelemetry 1.64.0 | opentelemetry-* | OTLP 协议一致 |
| 测试 | JUnit 5.10.2 + Mockito 5.14.2 + AssertJ 3.27.7 + Jacoco 0.8.11 | pytest + pytest-asyncio + pytest-cov | Java 注解驱动；Python fixture 驱动 |
| 可选后端 | SPI 工厂 + ServiceLoader | extras 可选组（pip install） | Java 编译期全量、运行时选择；Python 按需安装 |
| 沙箱 | JiuwenBox / Aio Mixin | agent-sandbox 0.0.26 | Java 本地进程隔离；Python 容器隔离 |

> 详细运行与构建对照见 [10-running-guide](10-running-guide.md)。
