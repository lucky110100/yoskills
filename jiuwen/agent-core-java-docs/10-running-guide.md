# 10 - 运行方式

> 交叉引用: [01-project-overview](01-project-overview.md) | [08-dev-tools-module](08-dev-tools-module.md) | [09-dependencies](09-dependencies.md) | [industry-comparison](industry-comparison.md)

本篇说明 agent-core-java 的环境要求、安装构建、CLI 入口、编程式使用、测试质量与常见问题。CLI 与编程式调用均围绕 [DeepAgent](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/deep_agent/DeepAgent.java#L97) 与 [Runner](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/runner/Runner.java#L44) 单例展开。

## 一、环境要求

| 要求 | 说明 |
|------|------|
| Java 版本 | 17 及以上（`maven.compiler.source/target=17`） |
| 构建工具 | Maven 3.9 及以上 |
| 操作系统 | Windows、Linux、macOS 均可；沙箱/LSP 在 Linux 上体验最佳 |
| LLM 凭证 | OpenAI 兼容或阿里云 Dashscope API Key |
| 可选外部服务 | Redis（检查点/多租户）、Milvus/pgvector（向量检索） |

> 使用前检查：`java -version` 与 `mvn -version`，确认 JDK 17+ 与 Maven 3.9+。

## 二、安装与构建

### 2.1 从源码构建

```bash
# 克隆仓库
git clone <repo-url> agent-core-java
cd agent-core-java

# 跳过测试快速构建
mvn clean install -DskipTests

# 查看依赖树（排查冲突）
mvn dependency:tree
```

构建产物为 `target/agent-core-java-0.1.14.jar`（packaging=jar）。

### 2.2 引入到你的项目

在自身项目 [pom.xml](file:///D:/jiuwen/main/agent-core-java/pom.xml) 中添加：

```xml
<dependency>
    <groupId>com.openjiuwen</groupId>
    <artifactId>agent-core-java</artifactId>
    <version>0.1.14</version>
</dependency>
```

> 依赖锁定与可选后端详见 [09-dependencies](09-dependencies.md)。

## 三、CLI 入口

agent-core-java 提供轻量 CLI，入口为 [HarnessCli](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/cli/HarnessCli.java#L21)，其 [runOnce](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/cli/HarnessCli.java#L31) 方法根据 [CLIOptions](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/cli/CLIOptions.java#L21) 构建 DeepAgentConfig 与 DeepAgent，再经 [HarnessFactory.createDeepAgent](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/factory/HarnessFactory.java) 装配后调用 `agent.invoke`。[buildTenantContext](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/cli/HarnessCli.java#L48) 将 `tenantId` 透传为多租户上下文。

### 3.1 CLIOptions 字段

[CLIOptions](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/cli/CLIOptions.java#L21) 使用 Lombok `@Builder`，字段如下：

| 字段 | 类型 | 说明 |
|------|------|------|
| `provider` | String | LLM 供应商标识（如 `OpenAI`、`Dashscope`） |
| `model` | String | 模型名（如 `gpt-4o`、`qwen-max`） |
| `apiKey` | String | API Key |
| `apiBase` | String | API 基址 |
| `remote` | String | 远程运行端点（可选） |
| `isVerbose` | boolean | 详细日志（默认 false） |
| `workspace` | String | 工作区路径 |
| `tenantId` | String | 多租户 ID（可选） |

### 3.2 命令示例

```bash
# 单次问答
java -jar agent-core-java.jar --provider OpenAI --model gpt-4o \
  --api-key sk-xxx --api-base https://api.openai.com/v1 "你的问题"

# 指定工作区与租户
java -jar agent-core-java.jar --provider OpenAI --model gpt-4o \
  --api-key sk-xxx --workspace /path/to/ws --tenantId tenantA "重构这个方法"

# 详细日志
java -jar agent-core-java.jar --provider OpenAI --model gpt-4o \
  --api-key sk-xxx --isVerbose "分析这段代码"
```

> CLI 默认内存后端零配置启动；接入 Redis/Milvus 需在配置文件或环境变量中指定连接信息。

## 四、编程式使用

### 4.1 注册模型并创建 DeepAgent

[Runner](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/runner/Runner.java#L44) 持有全局 `GLOBAL_RUNNER`，通过 [Runner.resourceMgr()](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/runner/Runner.java#L57) 获取资源管理器注册模型，再经 [HarnessFactory.createDeepAgent](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/factory/HarnessFactory.java) 装配 DeepAgent：

```java
import com.openjiuwen.core.runner.Runner;
import com.openjiuwen.harness.factory.HarnessFactory;
import com.openjiuwen.harness.deep_agent.DeepAgent;
import com.openjiuwen.harness.schema.config.DeepAgentConfig;
import com.openjiuwen.core.singleagent.schema.AgentCard;
import com.openjiuwen.core.multitenant.TenantContext;

// 1. 注册模型
Runner.resourceMgr().addModel("gpt-4o", () -> buildModel("gpt-4o"));

// 2. 装配 DeepAgent
DeepAgentConfig config = DeepAgentConfig.builder()
        .workspacePath("./workspace")
        .language("cn")
        .model(buildModelConfig())
        .backend("redis")
        .isTaskLoopEnabled(true)
        .build();
AgentCard card = AgentCard.builder().id("my_agent").name("my_agent").build();
DeepAgent agent = HarnessFactory.createDeepAgent(card, config, null);

// 3. 调用
TenantContext tenant = TenantContext.builder().tenantId("tenantA").build();
Map<String, Object> result = agent.invoke(Map.of("query", "帮我写一个快排"), tenant);
```

### 4.2 ReActAgent 示例

[DeepAgent](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/deep_agent/DeepAgent.java#L97) 内部封装 ReActAgent；也可直接使用 ReActAgent 做单轮工具调用：

```java
import com.openjiuwen.core.singleagent.agents.ReActAgent;
import com.openjiuwen.core.singleagent.schema.AgentCard;

AgentCard card = AgentCard.builder().id("react").name("react").build();
ReActAgent react = new ReActAgent(card);
react.configure(ReActAgentConfig.builder()
        .model(buildModelConfig())
        .tools(List.of(bashToolCard))
        .build());
Map<String, Object> out = react.invoke(Map.of("query", "查看当前目录文件"));
```

### 4.3 Workflow 示例

工作流通过 [Workflow](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/workflow/Workflow.java) 编排组件，注册到 ResourceMgr 后由 WorkflowAgent 执行：

```java
import com.openjiuwen.core.workflow.Workflow;
import com.openjiuwen.core.workflow.WorkflowCard;
import com.openjiuwen.core.workflow.Start;
import com.openjiuwen.core.workflow.End;
import com.openjiuwen.core.workflow.LLMComponent;
import com.openjiuwen.core.runner.Runner;

WorkflowCard wc = WorkflowCard.builder()
        .id("gen_text").name("gen_text").version("1.0").build();
Workflow flow = Workflow.builder().card(wc).build();
flow.setStartComp("start", new Start(), Map.of("query", "${query}"));
flow.addWorkflowComp("llm", new LLMComponent(llmConfig),
        Map.of("query", "${start.query}"));
flow.setEndComp("end", new End(), Map.of("output", "${llm.output}"));
flow.addConnection("start", "llm");
flow.addConnection("llm", "end");

Runner.resourceMgr().addWorkflow(WorkflowCard.builder()
        .id(generateWorkflowKey(wc.getId(), wc.getVersion())).build(), () -> flow);

WorkflowAgentConfig ac = WorkflowAgentConfig.builder()
        .id("wf_agent").version("0.1.1").build();
WorkflowAgent wfAgent = new WorkflowAgent(ac);
wfAgent.addWorkflows(List.of(flow));
Map<String, Object> r = Runner.runAgent(wfAgent, Map.of("query", "讲个笑话"));
```

### 4.4 LeaderTeammateAgentTeam 示例

[TeamAgent](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/agent/TeamAgent.java) 实现 Leader/Teammate 协作。Leader 通过 TeamBackend 派发任务给 Teammate，Teammate 各自持有 DeepAgent：

```java
import com.openjiuwen.agentteams.agent.TeamAgent;
import com.openjiuwen.agentteams.schema.TeamMemberSpec;

// Leader
TeamMemberSpec leader = TeamMemberSpec.builder()
        .name("leader").role("leader").build();
TeamAgent team = TeamAgent.builder()
        .card(AgentCard.builder().id("team").name("team").build())
        .leader(leader)
        .teammates(List.of(
                TeamMemberSpec.builder().name("coder").role("teammate").build(),
                TeamMemberSpec.builder().name("reviewer").role("teammate").build()))
        .build();
team.configure(teamConfig);
Map<String, Object> res = team.invoke(Map.of("query", "实现并审查登录功能"));
```

## 五、测试与质量

### 5.1 运行测试

```bash
# 单元测试（CI 默认门禁，排除 system-test）
mvn test

# 系统测试（需真实凭证/外部服务）
mvn verify -Dsystem-test

# 指定单个测试类
mvn test -Dtest=DeepAgentTest

# 生成覆盖率报告
mvn test
# 报告位于 target/site/jacoco/index.html
```

### 5.2 system-test 标签

[pom.xml](file:///D:/jiuwen/main/agent-core-java/pom.xml) 用 JUnit 5 `@Tag` 隔离测试：

- 单元测试：默认参与 `mvn test`，CI 必须保持绿色。
- 系统测试：标注 `@Tag("system-test")`，默认 `excludedGroups=system-test` 跳过；`-Dsystem-test` 启用，可能需要真实 Redis/Milvus/OpenAI 凭证。

### 5.3 Jacoco 覆盖率

Jacoco 0.8.11 经 `prepare-agent` 注入运行时代理，`report` 目标在 `test` 阶段生成 HTML/XML 报告：

```bash
mvn test
open target/site/jacoco/index.html
```

### 5.4 代码规范

agent-core-java 在 `.claude/rules/` 维护编码规范（architecture / coding-standard / concurrency / dependency-management / error-codes-standard / java-security / json-serialization / logging / test-flow）。要点：

- Lombok `@Data`/`@Builder` 统一数据类样板；
- Jackson `ObjectMapper` 复用单例（见 `.claude/rules/json-serialization.md`）；
- 日志经 SLF4J，禁止 `System.out`；
- 并发用 `CopyOnWriteArrayList` / `AtomicLong` 等 JDK 并发原语。

## 六、常见问题

| 问题 | 原因 | 解决 |
|------|------|------|
| `UnsupportedClassVersionError` | JDK 版本低于 17 | 升级到 JDK 17+，`java -version` 确认 |
| 依赖冲突 / `NoSuchMethodError` | 传递依赖版本分裂 | `mvn dependency:tree` 定位；[pom.xml](file:///D:/jiuwen/main/agent-core-java/pom.xml) 已用 BOM 锁定 Jackson/Kotlin/OTel，自行扩展时遵循同样策略 |
| Milvus 连接失败 | 网络或 `milvus-sdk-java` 排除不全 | 检查 Milvus 地址；确认已排除 `kotlin-stdlib-common`；向量库可切回 InMemory 调试 |
| Redis 集群 `MOVED` 异常 | 单机 Jedis 连集群端点 | 配置 `cluster_mode=true` 或指向集群任一节点；见 [09-dependencies](09-dependencies.md) 后端表 |
| 沙箱配置缺失 | JiuwenBox/Aio 未启用 | 检查 `DeepAgentConfig.sysOperation`；本地调试可用 `SysOperation.LOCAL`，生产用 `SANDBOX` |
| Mockito `JDK21 self-attach restricted` | JDK21 限制自附加 | Surefire 已配置 `-javaagent:${mockito-core:jar}`，确保用 `mvn test` 而非 IDE 直接运行 |
| 双 SLF4J 绑定警告 | Dashscope 拉 `slf4j-simple` | [pom.xml](file:///D:/jiuwen/main/agent-core-java/pom.xml) 已排除 `slf4j-simple`，自定义项目需同样排除 |
| Lombok 不生效 | IDE 未装 Lombok 插件或未启用注解处理 | 装 Lombok 插件；`mvn` 构建已配 `annotationProcessorPaths` |

> 更多依赖细节见 [09-dependencies](09-dependencies.md)，业界定位见 [industry-comparison](industry-comparison.md)。
