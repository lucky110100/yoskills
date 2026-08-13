# 01 项目概述:openJiuwen Core Java

> 交叉引用: [02-overall-architecture](02-overall-architecture.md) | [03-core-module](03-core-module.md) | [09-dependencies](09-dependencies.md) | [10-running-guide](10-running-guide.md)

本文档面向初次接触 agent-core-java 的开发者,从项目定位、核心能力、技术栈、仓库结构、包职责到快速开始,建立整体认知。详细架构见 [02-overall-architecture](02-overall-architecture.md),各模块细节见 03–08 文档。

## 一、项目定位

**openJiuwen Core Java**(Maven 坐标 `com.openjiuwen:agent-core-java:0.1.14`)是一个面向 Java 17 的智能体(Agent)开发 SDK,旨在为构建智能体、工作流编排、LLM 调用、工具调用、多 agent 团队协作、强化学习自优化与自动改码等场景提供统一的运行时与框架支撑。项目以 Apache-2.0 协议开源。

agent-core-java 是一套**独立的 Java 实现**,并非 Python 版 `agent-core` 的 JNI/绑定移植。源码注释中多次出现 "Mirrors Python's ..." 字样,表明 Java 实现与 Python 版在概念层面对齐、在 API 与运行时层面则按 Java 17 的语言特性(records、sealed、模式匹配、虚拟线程)与生态(Jackson、Reactor、OkHttp)重新落地。

设计目标可概括为:

- **声明性元数据与运行时分离**:Card 声明身份,Config 驱动行为(详见 [02-overall-architecture](02-overall-architecture.md) 第二章)。
- **可编排**:基于 Pregel 超步(BSP)引擎统一驱动工作流与多 agent 协作。
- **可中断可恢复**:三层中断恢复机制保障长时任务的健壮性。
- **可扩展**:通过 SPI(`ServiceLoader`)+ 编程式注册接入多种存储后端与厂商适配。
- **可演化**:内置 RL 优化与端到端自动改码基础设施。

## 二、核心能力

项目对外提供以下核心能力(对应 [01-project-overview](01-project-overview.md) 顶层包):

- **智能体创建**:提供 [ReActAgent](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/agents/ReActAgent.java#L77)(Reasoning→Acting→Observation 循环)与 [WorkflowAgent](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/application/workflow/WorkflowAgent.java)(基于工作流驱动的 agent)两类预置智能体。
- **工作流编排**:基于 Pregel BSP 图执行引擎([Pregel](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/graph/pregel/Pregel.java#L24)→[PregelLoop](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/graph/pregel/PregelLoop.java#L27)→[TaskExecutorPool](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/graph/pregel/TaskExecutorPool.java#L33)→ChannelManager)实现节点级并行与超步屏障。
- **LLM 调用**:统一 Model 客户端抽象,支持多厂商与流式输出。
- **工具调用**:ToolCard 声明 + 工具执行 + MCP/LSP 集成。
- **多 agent 团队**:Leader-Teammate 模型,[LeaderTeammateAgentTeam](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/LeaderTeammateAgentTeam.java) 声明式入口,[TeamAgent](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/agent/TeamAgent.java#L81) 单实现双角色。
- **RL 自优化**:`agentevolving` 提供 Trainer、评估、轨迹与检查点。
- **自动改码**:`autoharness` 提供端到端测试/评估编排(AutoHarnessOrchestrator)。
- **沙箱执行**:`extensions` 提供沙箱执行器(jiuwenbox 等厂商适配)。

## 三、技术栈与依赖

下表汇总项目核心技术栈与版本(权威来源为 [pom.xml](file:///D:/jiuwen/main/agent-core-java/pom.xml),完整依赖清单见 [09-dependencies](09-dependencies.md))。

| 分类 | 组件 | 版本 | 用途 |
| --- | --- | --- | --- |
| 语言/构建 | Java | 17 | records/sealed/模式匹配/虚拟线程 |
| 构建 | Maven | 3.9+ | 构建与依赖管理 |
| JSON | Jackson | 2.18.8 | JSON 序列化(单例 ObjectMapper) |
| 日志 | SLF4J + Logback | 2.0.12 / 1.5.37 | 日志门面 + 实现 |
| 代码增强 | Lombok | 1.18.32 | 样板代码消除(provided 作用域) |
| HTTP | OkHttp | 4.12.0 | LLM 调用 HTTP 客户端 |
| 响应式 | Reactor | 3.6.2 | 流式/响应式接口 |
| LLM SDK | OpenAI Java | 4.32.0 | OpenAI 协议客户端 |
| 可观测 | OpenTelemetry | 1.64.0 | 链路追踪/指标 |
| 向量存储 | Milvus / Chroma / pgvector / Elasticsearch | — | 向量检索后端 |
| KV 存储 | Redis(Jedis 5.1.5) | — | 键值/检查点 |
| 关系数据库 | SQLite / H2 / PostgreSQL / GaussDB | — | 持久化后端 |
| 测试 | JUnit 5 | 5.10.2 | 单元/系统测试 |
| 测试 | Mockito | 5.14.2 | Mock |
| 测试 | AssertJ | 3.27.7 | 流式断言 |
| 覆盖率 | Jacoco | 0.8.11 | 代码覆盖率报告 |

> 注意:`mvn test` 默认排除带 `system-test` 标记的测试,需通过 `-Dsurefire.groups=system-test` 显式启用,详见 [10-running-guide](10-running-guide.md)。

## 四、仓库结构

仓库根目录 `D:\jiuwen\main\agent-core-java` 顶层布局如下(权威说明见 [AGENTS.md](file:///D:/jiuwen/main/agent-core-java/AGENTS.md))。

| 路径 | 说明 |
| --- | --- |
| `src/main/java/com/openjiuwen/` | 9 个顶层包的源码主体 |
| `src/test/java/` | JUnit 5 测试;`system-test` 标记的测试默认不在 surefire 运行 |
| `examples/` | 用户面向的使用示例(react_agent/workflow_agent/agent_teams 等) |
| `documents/zh/` | 中文使用文档(开发指南/工作流/多智能体/高阶用法) |
| `resources/skills/` | 内置技能(可热加载) |
| `pom.xml` | 构建/工具配置的唯一真相来源 |
| `AGENTS.md` | AI 编码助手共享指令 |
| `README.md` / `README.zh.md` | 项目说明(中英文) |
| `LICENSE` | Apache-2.0 许可 |

源码主目录下 9 个顶层包位于 `src/main/java/com/openjiuwen/`:

| 包名 | 入口示意 |
| --- | --- |
| `core` | [Runner](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/runner/Runner.java#L44)、[ReActAgent](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/agents/ReActAgent.java#L77) |
| `harness` | [DeepAgentRail](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/DeepAgentRail.java#L14)、[TaskLoopController](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/task_loop/TaskLoopController.java#L17) |
| `deepagents` | deep agent 门面(middlewares/subagents/tools) |
| `agentteams` | [LeaderTeammateAgentTeam](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/LeaderTeammateAgentTeam.java) |
| `agentevolving` | RL 优化/评估/轨迹/检查点 |
| `autoharness` | 自动测试/评估基础设施 |
| `extensions` | 存储/检查点/上下文演化/沙箱/厂商适配 |
| `dev_tools` | agent/prompt builder、skill creator/evaluator、tune |
| `spi` | [KVStoreFactory](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/spi/store/KVStoreFactory.java)、[VectorStoreFactory](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/spi/store/vector/VectorStoreFactory.java) 等 SPI 工厂 |

## 五、顶层包职责

下表基于 [AGENTS.md](file:///D:/jiuwen/main/agent-core-java/AGENTS.md) 中各包的一句话职责,给出顶层包与其核心职责的对应关系(模块深度解析见 03–08 文档)。

| 顶层包 | 一句话职责 | 详情文档 |
| --- | --- | --- |
| `core` | 公共 SDK/运行时:agents/workflows/sessions/memory/retrieval/security/sysop | [03-core-module](03-core-module.md) |
| `harness` | 编码 agent 框架:prompts/rails/tools/subagents/task loop/workspace | [04-harness-and-deepagents-module](04-harness-and-deepagents-module.md) |
| `deepagents` | deep agent 框架门面:middlewares/subagents/tools | [04-harness-and-deepagents-module](04-harness-and-deepagents-module.md) |
| `agentteams` | 多 agent 团队(Leader-Teammate),`LeaderTeammateAgentTeam` 声明式入口 | [05-agentteams-module](05-agentteams-module.md) |
| `agentevolving` | 基于 RL 的 agent 优化/评估/轨迹/检查点 | [06-agentevolving-and-autoharness-module](06-agentevolving-and-autoharness-module.md) |
| `autoharness` | 自动化测试/评估基础设施:pipelines/orchestrators/stages/experience | [06-agentevolving-and-autoharness-module](06-agentevolving-and-autoharness-module.md) |
| `extensions` | 可选集成:storage(db/kv)、checkpointer(redis)、context evolver、sandbox、vendor | [07-extensions-and-spi-module](07-extensions-and-spi-module.md) |
| `dev_tools` | 开发工具:agent builder、prompt builder、skill creator/evaluator、tune | [08-dev-tools-module](08-dev-tools-module.md) |
| `spi` | SPI for store(kv/object/query/vector)扩展 | [07-extensions-and-spi-module](07-extensions-and-spi-module.md) |

## 六、快速开始

### 1. 添加 Maven 依赖

在你的 Maven 项目 `pom.xml` 中添加(版本与 [pom.xml](file:///D:/jiuwen/main/agent-core-java/pom.xml) 中 `0.1.14` 对齐):

```xml
<dependency>
    <groupId>com.openjiuwen</groupId>
    <artifactId>agent-core-java</artifactId>
    <version>0.1.14</version>
</dependency>
```

### 2. Java Hello World 示例

以下示例展示如何基于 [ReActAgent](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/agents/ReActAgent.java#L77) 构建一个最简 ReAct 智能体并运行一次推理。完整可运行示例参见仓库 `examples/react_agent/` 目录。

```java
import com.openjiuwen.core.singleagent.agents.ReActAgent;
import com.openjiuwen.core.singleagent.agents.ReActAgentConfig;
import com.openjiuwen.core.singleagent.schema.AgentCard;
import com.openjiuwen.core.session.Session;

public class HelloReActAgent {
    public static void main(String[] args) throws Exception {
        // 1. 声明 AgentCard(身份/元数据)
        AgentCard card = AgentCard.builder()
                .name("hello-react")
                .description("最简 ReAct 智能体")
                .build();

        // 2. 构建运行时 Config(行为驱动)
        ReActAgentConfig config = ReActAgentConfig.builder()
                .card(card)
                .model(modelClient)   // 预先创建的 Model 客户端
                .tools(tools)          // 可选:工具集合
                .build();

        // 3. 创建 agent 并执行一次推理循环
        ReActAgent agent = new ReActAgent(config);
        Object inputs = "今天天气怎么样?";
        Session session = Session.create();
        Object result = agent.invoke(inputs, session);
        System.out.println(result);
    }
}
```

> 说明:`AgentCard` 与 `ReActAgentConfig` 体现了项目核心的 Card/Config 分离原则(详见 [02-overall-architecture](02-overall-architecture.md) 第二章)。`Runner.resourceMgr` 为进程级共享状态,生产环境请使用稳定 ID 并保持测试隔离,参见 [AGENTS.md](file:///D:/jiuwen/main/agent-core-java/AGENTS.md)。

### 3. 构建与测试

```bash
mvn compile                 # 编译
mvn test                    # 运行单元测试(默认排除 system-test)
mvn test -Dsurefire.groups=system-test   # 运行系统测试
mvn test jacoco:report      # 生成覆盖率报告
```

更完整的运行配置、环境变量与示例索引见 [10-running-guide](10-running-guide.md)。依赖与版本治理细节见 [09-dependencies](09-dependencies.md)。
