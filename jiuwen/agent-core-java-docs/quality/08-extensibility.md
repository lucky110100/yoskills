# 可扩展性 — agent-core-java 质量评估

> 组: D 演进质量 | 分: **4/4（卓越）** | 否决项: 否 | 评估卡: [dims/extensibility.md](file:///D:/jiuwen/main/yoskills/common/project-analysis/dims/extensibility.md)

## 评分锚点依据

命中 4 档「明确扩展点 + 插件机制 + 接口抽象 + 配置驱动 + 扩展文档」全部信号。项目有成熟的 Java SPI 机制（ServiceLoader + META-INF/services + 编程式 register），共 9 个扩展点；接口抽象密度高（103 个 interface 分布于 100 个文件）；有专门的扩展文档「开发自定义组件」。唯一轻微不足是配置驱动走 JSON+Factory 路线而非注解注入，但仍属配置驱动。

## 评估过程

- **信号命中**：无扩展点 ❌（实际 9 个 SPI）、无插件机制 ❌（实际有 ServiceLoader）、配置硬编码 ❌（实际 JSON 配置驱动）、接口无抽象 ❌（103 interface）
- **Read**：[KVStoreFactory.java:25-33](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/spi/store/KVStoreFactory.java#L25-L33) ConcurrentHashMap 注册表 + ServiceLoader.load
- **Read**：[KVStoreProvider.java:22-38](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/spi/store/KVStoreProvider.java#L22-L38) 纯接口契约 typeName()+create(Map conf)
- **Glob**：`META-INF/services/*` 命中多个 Provider 注册文件
- **Grep**：`@Value|@Config` 全仓仅 5 处（Lombok 标签）

## 关键问题（带证据）

1. **SPI 扩展点设计规范**：[KVStoreFactory.java:25-33](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/spi/store/KVStoreFactory.java#L25-L33) 用 `ConcurrentHashMap` 注册表 + `ServiceLoader.load` 发现 Provider，并开放 `register()` 供外部不改 Core 源码注入新类型；[KVStoreProvider.java:22-38](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/spi/store/KVStoreProvider.java#L22-L38) 用纯接口定义 `typeName()`+`create(Map conf)` 契约，教科书式 SPI。
2. **多 Provider 实现已落地**：[VectorStoreProvider](file:///D:/jiuwen/main/agent-core-java/src/main/resources/META-INF/services/com.openjiuwen.spi.store.vector.VectorStoreProvider) 注册 InMemory/Chroma/Milvus/PGVector/Elasticsearch 5 个实现；[MilvusVectorStoreProvider.java:24-46](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/spi/store/vector/provider/MilvusVectorStoreProvider.java#L24-L46) 是典型实现。此外 Model$ModelClientFactory、CheckpointerProvider、McpClientProvider、RemoteClientProvider、SessionStoreProvider、WorkspaceStoreProvider、TodoStorageProvider、ObjectStorageProvider 共 9 个 SPI 扩展点。
3. **扩展文档完备**：[开发自定义组件.md:1-7](file:///D:/jiuwen/main/agent-core-java/documents/zh/2.开发指南/高阶用法/开发自定义组件.md#L1-L7) 讲解 `ComponentExecutable`/`ComponentComposable`/`WorkflowComponent` 三组抽象；[AGENTS.md:35-36](file:///D:/jiuwen/main/agent-core-java/AGENTS.md#L35-L36) 把 `com.openjiuwen.spi/` 列为「Service Provider Interface for store extensions」公开声明扩展边界。

## 改进建议

1. 配置驱动可补充注解化（@ConfigProperty 等）以降低 JSON 手写成本
2. 为每个 SPI 扩展点补充「如何新增一个 Provider」端到端示例（目前仅 vector store 有完整多实现示范）
3. 考虑发布 SPI 包的独立 jar 以便下游隔离扩展

## 业界对标

- 标杆：Spring Boot autoconfigure（条件装配扩展点）、RuoYi-Vue-Plus 模块化、FastAPI 依赖注入
- 评价：本项目 9 SPI 扩展点 + ServiceLoader 接近 Spring Boot 的自动配置扩展水准，是唯一卓越（4 分）维度
