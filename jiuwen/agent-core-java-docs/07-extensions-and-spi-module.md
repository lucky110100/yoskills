# extensions 与 spi 模块

> 交叉引用: [01-project-overview](01-project-overview.md) | [02-overall-architecture](02-overall-architecture.md) | [06-agentevolving-and-autoharness-module](06-agentevolving-and-autoharness-module.md) | [09-dependencies](09-dependencies.md)

本篇描述 agent-core-java 的两个"扩展层"模块:`spi` 定义存储相关的服务提供接口
(SPI),提供 KV/Vector/Object 三类存储的抽象与工厂;`extensions` 在其之上提供可选
集成,涵盖 Redis、GaussDB、Checkpointer、Context Evolver、Sandbox、MessageQueue、
vendor、a2a、tracerotel 等子领域。两者共同支撑"按需接入第三方后端"的能力。

## 一、模块职责

### 1.1 spi 模块职责

`spi` 模块对外暴露存储扩展服务提供接口,其职责包括:

- **存储抽象**:定义 `BaseKVStore`、`BaseVectorStore`、`BaseObjectStorageClient`
  三类基础接口,覆盖键值、向量、对象存储;
- **Provider 与 Factory**:通过 `KVStoreProvider`/`VectorStoreProvider` 等提供方
  接口,结合 `KVStoreFactory`/`VectorStoreFactory`/`ObjectStorageFactory` 实现
  ServiceLoader 自动发现 + 编程式注册的双轨机制;
- **查询表达式**:`QueryExpr` 及配套 `QueryLanguageDefinition`/`QueryLanguageRegistry`
  支持跨方言查询;
- **内置 Provider**:InMemory/Milvus/Chroma/pgvector/Elasticsearch 等开箱即用。

### 1.2 extensions 模块职责

`extensions` 模块提供可选集成,按子领域划分:

- **store**:Redis KV(`RedisStore`)、GaussDB(`GaussDbStore`)等第三方存储后端;
- **checkpointer**:Redis 检查点(`RedisCheckpointer`)等;
- **context_evolver**:记忆增强 Agent(`ContextEvolvingReActAgent`)+ 三算法
  (ACE/ReMe/ReasoningBank);
- **sandbox**:`JiuwenBox` 与 `aio` 两类沙箱 Profile 与 Provider;
- **message_queue**:Pulsar 等;
- **vendor_specific**:阿里云 Reranker 等;
- **a2a**:Agent-to-Agent JSON-RPC 客户端;
- **tracerotel**:OpenTelemetry 集成。

## 二、关键类与函数

### 2.1 spi 关键类

| 类/函数 | 文件位置 | 说明 |
| --- | --- | --- |
| BaseKVStore | [BaseKVStore.java#L23](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/spi/store/BaseKVStore.java#L23) | AutoCloseable;set/get/isExists/delete/getByPrefix/deleteByPrefix/mget/batchDelete/pipeline/close |
| BaseVectorStore | [BaseVectorStore.java#L18](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/spi/store/vector/BaseVectorStore.java#L18) | createCollection/deleteCollection/search/addDocs/deleteDocsByIds/listCollectionNames |
| BaseObjectStorageClient | [BaseObjectStorageClient.java#L19](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/spi/store/object/BaseObjectStorageClient.java#L19) | uploadFile/downloadFile/deleteObject |
| KVStoreProvider | [KVStoreProvider.java#L22](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/spi/store/KVStoreProvider.java#L22) | `typeName`/`create` |
| VectorStoreProvider | [VectorStoreProvider.java#L22](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/spi/store/vector/VectorStoreProvider.java#L22) | 向量存储 Provider 接口 |
| KVStoreFactory | [KVStoreFactory.java#L25](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/spi/store/KVStoreFactory.java#L25) | ServiceLoader + 编程式注册;`register` L50;`create` L62;ConcurrentHashMap REGISTRY |
| VectorStoreFactory | [VectorStoreFactory.java#L26](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/spi/store/vector/VectorStoreFactory.java#L26) | 别名 memory→in_memory、pg→pgvector、es→elasticsearch;`hasProvider` L102 |
| ObjectStorageFactory | [ObjectStorageFactory.java#L25](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/spi/store/object/ObjectStorageFactory.java#L25) | 对象存储工厂 |
| QueryExpr | [QueryExpr.java#L16](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/spi/store/query/QueryExpr.java#L16) | and/or/xor/not 查询表达式 |
| QueryLanguageDefinition | [QueryLanguageDefinition.java#L17](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/spi/store/query/QueryLanguageDefinition.java#L17) | 方言 Builder |
| QueryLanguageRegistry | [QueryLanguageRegistry.java#L20](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/spi/store/query/QueryLanguageRegistry.java#L20) | 方言注册表 |
| InMemoryVectorStoreProvider | spi 内置 | typeName=in_memory |
| MilvusVectorStoreProvider | spi 内置 | typeName=milvus |
| ChromaVectorStoreProvider | spi 内置 | typeName=chroma |
| PGVectorStoreProvider | spi 内置 | typeName=pgvector |
| ElasticsearchVectorStoreProvider | spi 内置 | typeName=elasticsearch |
| InMemoryKVStoreProvider | spi 内置 | typeName=in_memory |

### 2.2 extensions 关键类

| 类/函数 | 文件位置 | 说明 |
| --- | --- | --- |
| RedisStore | [RedisStore.java#L47](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/extensions/store/kv/RedisStore.java#L47) | 继承 BaseKVStore;反射适配 Jedis/Lettuce/Redisson;`exclusiveSet` L87-120(SETNX);`getByPrefix` L198-214(SCAN);`refreshTtl` L326;`scanClusterKeys` L682;`tryInvoke` L1015 |
| RedisKVStoreProvider | [RedisKVStoreProvider.java#L18](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/extensions/store/kv/RedisKVStoreProvider.java#L18) | typeName="redis" |
| GaussDbStore | [GaussDbStore.java#L22](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/extensions/store/db/GaussDbStore.java#L22) | 继承 BaseDbStore<DataSource> |
| DefaultDbStore | [DefaultDbStore.java#L23](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/foundation/store/db/DefaultDbStore.java#L23) | JDBC(SQLITE/H2/PG/MySQL) |
| RedisCheckpointer | [RedisCheckpointer.java#L48](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/extensions/checkpointer/redis/RedisCheckpointer.java#L48) | 继承 Checkpointer;组合 AgentStorage+WorkflowStorage+GraphStore+RedisGraphStoreAdapter;Provider L286-405 typeName="redis";`preAgentExecute` L78-83;`postAgentExecute`/`postWorkflowExecute` L152-169;`sessionExists` L179;`graphStore` L267 |
| BaseRedisStorage | [BaseRedisStorage.java#L29](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/extensions/checkpointer/redis/storage/BaseRedisStorage.java#L29) | 序列化/TTL 刷新/会话校验;AgentStorage(agent_state_blobs)/WorkflowStorage(workflow_state_blobs)/GraphStore(checkpoint_data) |
| ContextEvolvingReActAgent | [ContextEvolvingReActAgent.java#L48](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/extensions/context_evolver/ContextEvolvingReActAgent.java#L48) | 继承 ReActAgent 记忆增强 |
| TaskMemoryService | [TaskMemoryService.java#L56](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/extensions/context_evolver/service/TaskMemoryService.java#L56) | `retrieve` L166-203;`summarize`;三算法 ACE(默认)/ReMe/ReasoningBank |
| BaseOp | [BaseOp.java#L23](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/extensions/context_evolver/core/op/BaseOp.java#L23) | `then`/`parallel` 算子组合;SequentialOp/ParallelOp;RecallMemoryOp/ReflectOp/CurateOp/ApplyDeltaOp |
| JiuwenBoxSandboxProfile | [JiuwenBoxSandboxProfile.java#L18](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/extensions/sys_operation/sandbox/JiuwenBoxSandboxProfile.java#L18) | sandboxType="jiuwenbox" |
| AioSandboxProfile | [AioSandboxProfile.java#L18](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/extensions/sys_operation/sandbox/AioSandboxProfile.java#L18) | sandboxType="aio" |
| JiuwenBoxClient | [JiuwenBoxClient.java#L43](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/extensions/sys_operation/sandbox/providers/jiuwenbox/JiuwenBoxClient.java#L43) | OkHttp 客户端 |
| JiuwenBoxProviderMixin | [JiuwenBoxProviderMixin.java#L37](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/extensions/sys_operation/sandbox/providers/jiuwenbox/JiuwenBoxProviderMixin.java#L37) | 组合核心(生命周期/共享缓存/自动重建/空闲超时);JiuwenBoxShellProvider/JiuwenBoxFSProvider/JiuwenBoxCodeProvider |
| MessageQueuePulsar | [MessageQueuePulsar.java#L35](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/extensions/message_queue/MessageQueuePulsar.java#L35) | 继承 MessageQueueBase |
| AliyunReranker | [AliyunReranker.java#L21](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/extensions/vendor_specific/AliyunReranker.java#L21) | 继承 StandardReranker |
| A2AClient | [A2AClient.java#L36](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/extensions/a2a/A2AClient.java#L36) | JSON-RPC;A2ARemoteClient/A2ATransformer/A2AAgentCardAdapter |
| OtelAgentHandler | [OtelAgentHandler.java#L50](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/extensions/tracerotel/OtelAgentHandler.java#L50) | OTel 集成;OtelWorkflowHandler/OtelTracerSetup/OtelSpanManager |

## 三、核心机制

### 3.1 SPI 工厂双轨注册

`KVStoreFactory`(L25)与 `VectorStoreFactory`(L26)采用"双轨注册":

1. **ServiceLoader 自动发现**:启动时通过 JDK `ServiceLoader` 扫描
   `META-INF/services/...` 下的 Provider 实现类并注册;
2. **编程式注册**:用户可在运行时调用 `KVStoreFactory.register`(L50)追加自定义
   Provider,实现保存在 `ConcurrentHashMap` 形式的 `REGISTRY` 中,天然线程安全;
3. **别名机制**:`VectorStoreFactory` 内置别名(memory→in_memory、pg→pgvector、
   es→elasticsearch),`hasProvider`(L102)兼顾别名与全名查询。

`ObjectStorageFactory`(L25)遵循同样的双轨模式,覆盖对象存储。

### 3.2 存储后端矩阵

下表汇总 extensions + spi 提供的存储后端:

| 后端类型 | KV | Vector | DB | 注册方式 |
| --- | --- | --- | --- | --- |
| Redis | RedisStore | — | — | RedisKVStoreProvider(typeName="redis") |
| Milvus | — | MilvusVectorStoreProvider | — | VectorStoreFactory 别名 milvus |
| Chroma | — | ChromaVectorStoreProvider | — | VectorStoreFactory 别名 chroma |
| pgvector | — | PGVectorStoreProvider | — | VectorStoreFactory 别名 pg |
| Elasticsearch | — | ElasticsearchVectorStoreProvider | — | VectorStoreFactory 别名 es |
| GaussDB | — | — | GaussDbStore | BaseDbStore<DataSource> |
| SQLite / H2 / PG / MySQL | — | — | DefaultDbStore | JDBC |
| InMemory | InMemoryKVStoreProvider | InMemoryVectorStoreProvider | — | 内置默认 |

### 3.3 RedisCheckpointer 三 Storage + Adapter

`RedisCheckpointer`(L48)继承 Checkpointer,内部组合四类组件:

- `AgentStorage`(键前缀 `agent_state_blobs`):保存 Agent 运行态;
- `WorkflowStorage`(键前缀 `workflow_state_blobs`):保存工作流运行态;
- `GraphStore`(键前缀 `checkpoint_data`):保存图结构检查点;
- `RedisGraphStoreAdapter`:把 GraphStore 的图模型适配为 Redis 的 KV 模型。

`BaseRedisStorage`(L29)统一处理序列化、TTL 刷新(`refreshTtl` 在 RedisStore L326)、
会话校验。关键钩子:`preAgentExecute`(L78-83)前置加载、`postAgentExecute`/
`postWorkflowExecute`(L152-169)后置落盘、`sessionExists`(L179)判存在、
`graphStore`(L267)取适配器。Provider 段(L286-405)以 typeName="redis" 注册到工厂。

### 3.4 RedisStore 反射适配

`RedisStore`(L47)的亮点是"反射适配多客户端":同一份代码可驱动 Jedis、Lettuce、
Redisson 三种客户端。核心方法:

- `exclusiveSet`(L87-120):基于 SETNX 实现分布式锁语义;
- `getByPrefix`(L198-214):基于 SCAN 实现前缀扫描,避免 KEYS 阻塞;
- `scanClusterKeys`(L682):集群模式下的跨槽扫描;
- `tryInvoke`(L1015):统一异常封装与重试。

### 3.5 Context Evolver 三算法 + 算子组合

`ContextEvolvingReActAgent`(L48)继承 ReActAgent,在每步推理前后注入记忆操作;
`TaskMemoryService`(L56)的 `retrieve`(L166-203)负责检索,`summarize` 负责压缩。
内置三算法:

- **ACE**(默认):基于 Attention 的记忆编排;
- **ReMe**:基于检索-反思的记忆编排;
- **ReasoningBank**:基于推理库的记忆编排。

记忆操作被建模为算子(`BaseOp` L23),通过 `then`/`parallel` 组合成
`SequentialOp`/`ParallelOp`,具体算子包括 RecallMemoryOp、ReflectOp、CurateOp、
ApplyDeltaOp。这种"算子代数"让记忆策略可声明式拼装。

### 3.6 Sandbox Mixin 组合 + 本地降级

沙箱侧提供两类 Profile:`JiuwenBoxSandboxProfile`(L18,sandboxType="jiuwenbox")
与 `AioSandboxProfile`(L18,sandboxType="aio")。

`JiuwenBoxProviderMixin`(L37)是核心设计:通过 Mixin 模式把生命周期管理、共享缓存、
自动重建、空闲超时四类通用逻辑组合进 `JiuwenBoxShellProvider`/`JiuwenBoxFSProvider`/
`JiuwenBoxCodeProvider` 三个具体 Provider。`JiuwenBoxClient`(L43)用 OkHttp 与远端
jiuwenbox 服务通信,当远端不可用时自动降级为本地实现。

## 四、调用示例

### 4.1 通过 SPI 工厂获取存储

```java
import com.openjiuwen.spi.store.KVStoreFactory;
import com.openjiuwen.spi.store.vector.VectorStoreFactory;
import com.openjiuwen.spi.store.BaseKVStore;
import com.openjiuwen.spi.store.vector.BaseVectorStore;

BaseKVStore kv = KVStoreFactory.create("redis", redisConfig);
kv.set("session:1", stateBytes);
byte[] loaded = kv.get("session:1");

BaseVectorStore vec = VectorStoreFactory.create("milvus", milvusConfig);
vec.createCollection("embeds", 1024);
vec.addDocs("embeds", List.of(doc1, doc2));
List<SearchResult> hits = vec.search("embeds", queryVec, 10);

try (BaseKVStore auto = kv) {
    // AutoCloseable,使用完毕自动 close
}
```

### 4.2 注册自定义 Provider

```java
import com.openjiuwen.spi.store.KVStoreProvider;
import com.openjiuwen.spi.store.KVStoreFactory;

public class MyKVProvider implements KVStoreProvider {
    @Override public String typeName() { return "my_kv"; }
    @Override public BaseKVStore create(Object config) {
        return new MyKVStore(config);
    }
}

KVStoreFactory.register(new MyKVProvider());
BaseKVStore mine = KVStoreFactory.create("my_kv", cfg);
```

### 4.3 使用 RedisCheckpointer

```java
import com.openjiuwen.extensions.checkpointer.redis.RedisCheckpointer;

RedisCheckpointer cp = RedisCheckpointer.builder()
    .redisStore(redisStore)
    .ttl(Duration.ofHours(6))
    .build();

cp.preAgentExecute(sessionId, agentId);   // 前置加载状态
// ... agent 运行 ...
cp.postAgentExecute(sessionId, agentId);   // 后置落盘
boolean exists = cp.sessionExists(sessionId);
```

### 4.4 使用 ContextEvolvingReActAgent

```java
import com.openjiuwen.extensions.context_evolver.ContextEvolvingReActAgent;
import com.openjiuwen.extensions.context_evolver.service.TaskMemoryService;

TaskMemoryService memory = TaskMemoryService.builder()
    .vectorStore(vecStore)
    .algorithm("ACE")
    .build();

ContextEvolvingReActAgent agent = ContextEvolvingReActAgent.builder()
    .llm(llm)
    .tools(tools)
    .memoryService(memory)
    .build();

agent.invoke("帮我总结昨天会议的要点");
```

## 五、与 Python agent-core 对照

| Java (agent-core-java) | Python (agent-core) | 对照说明 |
| --- | --- | --- |
| spi 模块 | SPI 扩展 | 模块对等 |
| extensions 模块 | extensions | 模块对等 |
| KVStoreFactory/VectorStoreFactory/ObjectStorageFactory | StoreFactory 系列 | 工厂对等 |
| BaseKVStore/BaseVectorStore/BaseObjectStorageClient | BaseStore 系列 | 存储抽象对等 |
| QueryExpr/QueryLanguageDefinition/QueryLanguageRegistry | Query 系列 | 查询表达式对等 |
| RedisStore | RedisStore | 反射适配多客户端对等 |
| RedisCheckpointer | RedisCheckpointer | 检查点对等 |
| BaseRedisStorage(Agent/Workflow/Graph) | Redis Storage 三类 | 三 Storage 对等 |
| ContextEvolvingReActAgent | context_evolver agent | 记忆增强 Agent 对等 |
| TaskMemoryService(ACE/ReMe/ReasoningBank) | context_evolver 三算法 | 算法对等 |
| BaseOp(then/parallel + Sequential/Parallel + Recall/Reflect/Curate/ApplyDelta) | BaseOp 算子 | 算子代数对等 |
| JiuwenBoxSandboxProfile/AioSandboxProfile | sandbox profile | 沙箱 Profile 对等 |
| JiuwenBoxProviderMixin + Shell/FS/Code Provider | sandbox provider | Mixin 组合对等 |
| MessageQueuePulsar | message_queue | 消息队列对等 |
| AliyunReranker | vendor reranker | 厂商集成对等 |
| A2AClient | a2a client | A2A 客户端对等 |
| OtelAgentHandler/OtelWorkflowHandler/OtelTracerSetup/OtelSpanManager | tracerotel | OTel 集成对等 |

## 六、小结

`spi` 与 `extensions` 构成 agent-core-java 的"扩展闭环":spi 定义抽象与工厂,
extensions 落地第三方实现。双轨注册(ServiceLoader + 编程式)兼顾"开箱即用"与
"运行时扩展";存储后端矩阵覆盖 KV/Vector/DB/Object 四类,从 InMemory 到 Milvus、
Redis、GaussDB 一应俱全;RedisCheckpointer 的"三 Storage + Adapter"组合展示了
如何在 KV 之上构建图模型;Context Evolver 的算子代数则展示了如何把记忆策略
声明式拼装。整体设计让 agent-core-java 既能轻量起步,也能按需接入企业级后端。
