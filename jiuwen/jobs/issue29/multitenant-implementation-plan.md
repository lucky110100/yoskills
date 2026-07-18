# agent-core-java 多租户资源管理实施计划

> 基于文档：agent-core-java-multitenant-resource-brainstorming.md（已核对版）
> 编写日期：2026-07-16
> 项目：agent-core-java
> 最后更新：2026-07-18（实施完成状态更新）

---

## 一、总体里程碑

| 里程碑 | 范围 | 预估工作量 | 前置依赖 | 实施状态 |
|--------|------|-----------|---------|---------|
| **M1: P0 路径修复** | 修复 tenantId 路径重复 + PersistenceCheckpointer tenantId 前缀 | 小 | 无 | ✅ **已完成** |
| **M2: P1 Todo+FileStore 显式隔离+SPI** | TodoStorage SPI + KvTodoStorage 复用 + TodoTool 改造 + Todo/FileStore 显式租户感知 + SessionStoreProvider SPI | 中 | M1 | ✅ **已完成** |
| **M3: P1 OverlaySkillManager** | OverlaySkillManager + 显式覆盖/可撤销 + SkillTool 改造 | 中 | M1 | ✅ **已完成** |
| **M4: P1 Tmp TTL 清理** | TmpFileCleaner + TenantResourceCleaner 接口 | 小 | M1 | ✅ **已完成** |
| **M5: P2 统一存储抽象** | TenantResourceStore + 适配 + 迁移 + VectorStore/DB 隔离 | 大 | M2, M3, M4 | ⏳ 待实施 |

---

## 二、M1: P0 路径修复 ✅ 已完成

> 实施日期：2026-07-18
> Commit: `685b20f0` → `e686e2f1`（历史重写后 hash 变化）

### 2.1 变更清单

| # | 变更 | 文件 | 说明 | 状态 |
|---|------|------|------|------|
| 1 | 修改 PATH_DEFAULT | `TenantNamespaceFactories.java` | 租户时返回 `tenants/{tenantId}`，无租户返回空串 | ✅ |
| 2 | 重写 TenantWorkspaceResolver | `TenantWorkspaceResolver.java` | `tenants/{tenantId}/` 即 workspace，新增 resolveTeamMemoryDir/resolveTodoDir；initializeTenantSpace() 增加创建 todo/.overlay 子目录 | ✅ |
| 3 | 修改 WorkspaceType | `WorkspaceType.java` | 新增 TODO，WORKSPACE 的 subDirectory 为空串 | ✅ |
| 4 | 修改 LocalWorkspaceStore | `LocalWorkspaceStore.java` | 处理空 subDirectory，createDirectories 增加 todo | ✅ |
| 5 | 修改 TieredWorkspaceManager | `TieredWorkspaceManager.java` | 适配新路径结构，去掉 tenantId 参数 | ✅ |
| 6 | 完成 PersistenceCheckpointer tenantId 前缀 | `PersistenceCheckpointer.java` | 确认所有 KV 操作使用 TenantKVStoreKeyResolver（31处已使用） | ✅ |
| 7 | TenantContextHolder.setCurrentTenant() 增加 tenantId 字符校验 | `TenantContextHolder.java` | 不合规 tenantId 抛出 IllegalArgumentException，防止 safeTenantId 碰撞 | ✅ |
| 8 | 更新所有受影响测试 | 6个测试文件 | 适配新路径结构 | ✅ |

### 2.2 UT 测试用例 ✅ 全部通过

| 用例 ID | 用例名称 | 测试要点 | 状态 |
|---------|---------|---------|------|
| UT-M1-001~023 | TenantWorkspaceResolverTest（修改现有） | workspace/skill/tmp/checkpoints/team_memory/todo 路径验证、初始化目录结构、租户隔离、tenantId 校验 | ✅ |
| UT-M1-024~027 | TenantNamespaceFactoriesTest（修改现有） | PATH_DEFAULT/KV_DEFAULT 有/无租户路径 | ✅ |
| UT-M1-028~031 | LocalWorkspaceStoreTest（新增） | 空 subDirectory、目录创建 | ✅ |
| UT-M1-032~036 | TieredWorkspaceManagerTest（修改现有） | 新路径结构、默认路径、目录初始化 | ✅ |
| UT-M1-037~041 | TenantBackwardCompatTest（修改现有） | 无租户向后兼容 | ✅ |
| UT-M1-042~048 | PersistenceCheckpointerTenantTest（新增） | KV key 格式、release 前缀删除、租户隔离 | ✅ |

### 2.3 ST 系统测试用例 ⏳ 待部署验证

| 用例 ID | 用例名称 | 状态 |
|---------|---------|------|
| ST-M1-001~005 | 路径兼容性/新路径结构/多租户隔离/PersistenceCheckpointer/路径穿越 | ⏳ |

---

## 三、M2: P1 Todo + FileStore 显式隔离 + SPI ✅ 已完成

> 实施日期：2026-07-18
> Commit: `685b20f0` → `36cb92fe` → `e686e2f1`

### 3.1 变更清单

| # | 变更 | 文件 | 说明 | 状态 |
|---|------|------|------|------|
| 1 | 新增 TodoStorageProvider | `TodoStorageProvider.java` | SPI 接口 | ✅ |
| 2 | 新增 FileTodoStorageProvider | `FileTodoStorageProvider.java` | 内置 file 实现 | ✅ |
| 3 | 新增 KvTodoStorageProvider | `KvTodoStorageProvider.java` | KV 抽象层 Provider，支持 sharedKvStore 优先 | ✅ |
| 4 | 新增 TodoStorageFactory | `TodoStorageFactory.java` | 工厂类，ServiceLoader 发现 | ✅ |
| 5 | 改造 TodoTool | `TodoTool.java` | 新增 fromConfig() | ✅ |
| 6 | 改造 FileTodoStorage | `FileTodoStorage.java` | 增加 TenantWorkspaceResolver 构造器，resolveWorkspace() 自动路径隔离 | ✅ |
| 7 | 新增 SPI Service 文件 | `META-INF/services/...TodoStorageProvider` | 注册 File + Kv Provider | ✅ |
| 8 | DeepAgentConfig 增加配置 | `DeepAgentConfig.java` | todoStorageType 已存在，sessionStoreType 新增（默认"file"） | ✅ |
| 9 | 修改 TaskPlanningRail | `TaskPlanningRail.java` | TodoTool 创建逻辑适配 SPI，kv 模式复用 DeepAgent.kvStore | ✅ |
| 10 | RunnerImpl 共享 BaseKVStore | `RunnerImpl.java` | 已有机制，确认生命周期管理 | ✅ 确认已有 |
| 11 | 新增 SessionStoreProvider | `SessionStoreProvider.java` | SPI 接口（typeName() + createStore()） | ✅ |
| 12 | 新增 FileSessionStoreProvider | `FileSessionStoreProvider.java` | 内置 file 实现 | ✅ |
| 13 | 改造 FileStore | `FileStore.java` | 增加 TenantWorkspaceResolver 构造器，resolveStorePath() 自动路径隔离 | ✅ |
| 14 | 新增 SPI Service 文件 | `META-INF/services/...SessionStoreProvider` | 注册 FileSessionStoreProvider | ✅ |
| 15 | DeepAgentConfig 增加 sessionStoreType | `DeepAgentConfig.java` | sessionStoreType（默认"file"），与 todoStorageType 模式一致 | ✅ |

### 3.2 UT 测试用例 ✅ 全部通过

| 用例 ID | 用例名称 | 测试要点 | 状态 |
|---------|---------|---------|------|
| UT-M2-001~010 | TodoStorageProviderTest（新增） | typeName、create、sharedKvStore 优先、null conf | ✅ |
| UT-M2-006~013 | TodoStorageFactoryTest（新增） | create file/kv/unknown、hasProvider、register、ServiceLoader 发现 | ✅ |
| UT-M2-026~032 | TenantAwareFileTodoStorageTest（新增） | 无/有租户路径、租户隔离、delete 验证 | ✅ |
| UT-M2-033~039 | TodoToolFromConfigTest（新增） | fromConfig file/kv/unknown、legacy/custom 构造器、CRUD | ✅ |
| UT-M2-046~048 | SessionStoreProviderTest（新增） | typeName、create、读写 | ✅ |
| UT-M2-006~010 | SessionStoreFactoryTest（新增） | create/hasProvider/unknown/register/ServiceLoader | ✅ |
| UT-M2-049~054 | TenantAwareFileStoreTest（新增） | 无/有租户路径、租户隔离、merge 语义 | ✅ |

### 3.3 ST 系统测试用例 ⏳ 待部署验证

| 用例 ID | 用例名称 | 状态 |
|---------|---------|------|
| ST-M2-001~011 | Todo/File/KV 多租户隔离、模式切换、SPI 扩展 | ⏳ |

---

## 四、M3: P1 OverlaySkillManager ✅ 已完成

> 实施日期：2026-07-18
> Commit: `218dd995`

### 4.1 变更清单

| # | 变更 | 文件 | 说明 | 状态 |
|---|------|------|------|------|
| 1 | 新增 OverlaySkillManager | `OverlaySkillManager.java` | 双层查找 + overlay 标记 + override/revoke + migrateImplicitOverrides | ✅ |
| 2 | 改造 SkillTool | `SkillTool.java` | 新增 OverlaySkillManager 构造器，优先使用 OverlaySkillManager，fallback 内嵌逻辑 | ✅ |
| 3 | 改造 ListSkillTool | `ListSkillTool.java` | 新增 OverlaySkillManager 构造器，优先使用 OverlaySkillManager | ✅ |
| 4 | 增加 overrideSkill/revokeOverride | `OverlaySkillManager.java` | 显式覆盖管理（`.override` 标记文件） | ✅ |
| 5 | 修改 TenantWorkspaceResolver | `TenantWorkspaceResolver.java` | 初始化时创建 `.overlay/` 目录 | ✅ |
| 6 | OverlaySkillManager 启动时自动迁移隐式覆盖 | `OverlaySkillManager.java` | migrateImplicitOverrides() 方法 | ✅ |

### 4.2 UT 测试用例 ✅ 全部通过

| 用例 ID | 用例名称 | 测试要点 | 状态 |
|---------|---------|---------|------|
| UT-M3-001~017 | OverlaySkillManagerTest（新增） | 双层查找、override/revoke/isOverridden、租户优先、空 Skill 目录 | ✅ |
| UT-M3-018~023 | OverlaySkillManagerHotReloadTest（新增） | 公共/租户 Skill 更新/新增/删除后 refresh 可见 | ✅ |

### 4.3 ST 系统测试用例 ⏳ 待部署验证

| 用例 ID | 用例名称 | 状态 |
|---------|---------|------|
| ST-M3-001~006 | Skill 双层查找/显式覆盖/撤销/热加载/无租户/多租户隔离 | ⏳ |

---

## 五、M4: P1 Tmp TTL 清理 + 清理接口 ✅ 已完成

> 实施日期：2026-07-18
> Commit: `fcd084d8`

### 5.1 变更清单

| # | 变更 | 文件 | 说明 | 状态 |
|---|------|------|------|------|
| 1 | 新增 TenantResourceCleaner | `TenantResourceCleaner.java` | 清理接口（含文件系统类 + KV 类清理方法） | ✅ |
| 2 | 新增 DefaultTenantResourceCleaner | `DefaultTenantResourceCleaner.java` | 默认实现（含 cleanupKVState/cleanupDistributedLocks） | ✅ |
| 3 | 新增 TmpFileCleaner | `TmpFileCleaner.java` | TTL 定时扫描清理，含 start()/stop() 生命周期管理 | ✅ |
| 4 | DeepAgentConfig 增加 tmpTtl + tmpTtlScanInterval | `DeepAgentConfig.java` | TTL 配置项（默认 24h）+ 扫描间隔（默认 1h） | ✅ |
| 5 | TmpFileCleaner 集成到 DeepAgent 生命周期 | `DeepAgent.java` | bindTenantWorkspace() 启动，destroy() 停止 | ✅ |

### 5.2 UT 测试用例 ✅ 全部通过

| 用例 ID | 用例名称 | 测试要点 | 状态 |
|---------|---------|---------|------|
| UT-M4-001~008b | TmpFileCleanerTest（新增） | 过期/新鲜文件、租户 tmp、生命周期、并发 | ✅ |
| UT-M4-009~017 | DefaultTenantResourceCleanerTest（新增） | 各类清理操作、KV 前缀删除、租户隔离、null kvStore | ✅ |
| UT-M4-009~017 | TenantResourceCleanerTest（新增） | 接口级清理方法验证 | ✅ |

### 5.3 ST 系统测试用例 ⏳ 待部署验证

| 用例 ID | 用例名称 | 状态 |
|---------|---------|------|
| ST-M4-001~004 | Tmp TTL 清理/租户资源清理/部分清理/运行中 Session 不受影响 | ⏳ |

---

## 六、M5: P2 统一存储抽象（概要） ⏳ 待实施

> M5 详细实施计划在 M2-M4 完成后根据实际情况细化，此处给出概要。

### 6.1 变更清单（概要）

| # | 变更 | 说明 | 状态 |
|---|------|------|------|
| 1 | 新增 TenantResourceStore 接口 | 统一文件类 + KV 类操作 | ⏳ |
| 2 | 新增 ResourceType 枚举 | 含 StoreCategory 分类 | ⏳ |
| 3 | 新增 TenantResourceStoreProvider SPI | 统一 Provider | ⏳ |
| 4 | 适配 Workspace/Skill/Tmp/Checkpoints | 实现 LocalTenantResourceStore | ⏳ |
| 5 | 适配 Session/Agent/Workflow State | 实现 KvTenantResourceStore | ⏳ |
| 6 | 适配 VectorStore | 实现 VectorTenantResourceStore | ⏳ |
| 7 | 统一配置 TenantStorageConfig | YAML + Java Config | ⏳ |
| 8 | BaseDbStore 增加 tenant_id 列 | MessageManager, ScopeUserMappingManager | ⏳ |
| 9 | VectorStore 集合名 tenantId 前缀 | 各 VectorStoreProvider | ⏳ |
| 10 | 租户数据归档/迁移工具 | 新增工具类 | ⏳ |

---

## 七、实施文件汇总

### 新增源文件（14个）

| 文件路径 | 里程碑 | 说明 |
|---------|--------|------|
| `TodoStorageProvider.java` | M2 | Todo SPI 接口 |
| `FileTodoStorageProvider.java` | M2 | Todo file Provider |
| `KvTodoStorageProvider.java` | M2 | Todo kv Provider |
| `TodoStorageFactory.java` | M2 | Todo 工厂类 |
| `SessionStoreProvider.java` | M2 | Session SPI 接口 |
| `FileSessionStoreProvider.java` | M2 | Session file Provider |
| `SessionStoreFactory.java` | M2 | Session 工厂类 |
| `OverlaySkillManager.java` | M3 | Skill 双层查找 + overlay |
| `TenantResourceCleaner.java` | M4 | 清理接口 |
| `DefaultTenantResourceCleaner.java` | M4 | 清理默认实现 |
| `TmpFileCleaner.java` | M4 | TTL 定时扫描 |
| `META-INF/services/...TodoStorageProvider` | M2 | SPI 注册 |
| `META-INF/services/...SessionStoreProvider` | M2 | SPI 注册 |
| `ObjectStorageWorkspaceStore.java`（修改） | M1 | 适配新接口 |

### 修改源文件（10个）

| 文件路径 | 里程碑 | 说明 |
|---------|--------|------|
| `TenantNamespaceFactories.java` | M1 | PATH_DEFAULT 返回 tenants/{tid} |
| `TenantWorkspaceResolver.java` | M1+M3 | 重写路径结构 + .overlay 目录 |
| `WorkspaceType.java` | M1 | TODO 枚举 + WORKSPACE("") |
| `WorkspaceStore.java` | M1 | 接口简化去掉 tenantId |
| `LocalWorkspaceStore.java` | M1 | 适配空 subDirectory |
| `TenantContextHolder.java` | M1 | tenantId 校验 |
| `TieredWorkspaceManager.java` | M1 | 适配新签名 |
| `FileTodoStorage.java` | M2 | TenantAware 路径隔离 |
| `FileStore.java` | M2 | TenantAware 路径隔离 |
| `TodoTool.java` | M2 | fromConfig() |
| `TaskPlanningRail.java` | M2 | SPI 适配 |
| `SkillTool.java` | M3 | OverlaySkillManager 构造器 |
| `ListSkillTool.java` | M3 | OverlaySkillManager 构造器 |
| `DeepAgentConfig.java` | M2+M4 | sessionStoreType + tmpTtl/tmpTtlScanInterval |
| `DeepAgent.java` | M4 | TmpFileCleaner 生命周期 |

### 新增测试文件（14个）

| 文件路径 | 里程碑 | 测试数 |
|---------|--------|-------|
| `TenantWorkspaceResolverTest.java`（修改） | M1 | 适配新路径 |
| `TenantNamespaceFactoryTest.java`（修改） | M1 | 适配新路径 |
| `TenantBackwardCompatTest.java`（修改） | M1 | 适配新路径 |
| `TieredWorkspaceManagerTest.java`（修改） | M1 | 适配新路径 |
| `TenantTempFileIsolationTest.java`（修改） | M1 | 适配新路径 |
| `TenantKVStoreKeyResolverTest.java`（修改） | M1 | tenantId 校验 |
| `WorkspaceStoreTest.java`（修复） | M1 | 适配新接口 |
| `TodoStorageProviderTest.java`（新增） | M2 | 10 |
| `TodoStorageFactoryTest.java`（新增） | M2 | 13 |
| `TodoStorageTenantContextTest.java`（新增） | M2 | 5 |
| `TenantAwareFileTodoStorageTest.java`（新增） | M2 | 13 |
| `SessionStoreProviderTest.java`（新增） | M2 | 6 |
| `SessionStoreFactoryTest.java`（新增） | M2 | 10 |
| `TenantAwareFileStoreTest.java`（新增） | M2 | 12 |
| `TodoToolFromConfigTest.java`（新增） | M2 | 7 |
| `OverlaySkillManagerTest.java`（新增） | M3 | 25 |
| `OverlaySkillManagerHotReloadTest.java`（新增） | M3 | 6 |
| `PersistenceCheckpointerTenantTest.java`（新增） | M1 | 7 |
| `DefaultTenantResourceCleanerTest.java`（新增） | M4 | 22 |
| `TenantResourceCleanerTest.java`（新增） | M4 | 11 |
| `TmpFileCleanerTest.java`（新增） | M4 | 14 |

---

## 八、验收标准达成情况

| 里程碑 | 验收标准 | 达成 |
|--------|---------|------|
| **M1** | 1. 路径中 tenantId 不再重复 ✅；2. 无租户场景所有路径与修改前一致 ✅；3. PersistenceCheckpointer KV key 带租户前缀 ✅；4. 全部 UT 通过 ✅ | ✅ |
| **M2** | 1. TodoTool 支持 file/kv ✅；2. kv 通过 KVStoreFactory 可对接任意 BaseKVStore ✅；3. kv 与 Checkpointer 共享实例 ✅；4. Todo 显式租户隔离 ✅；5. SPI 可扩展 ✅；6. 全部 UT 通过 ✅ | ✅ |
| **M3** | 1. OverlaySkillManager 双层查找 ✅；2. 显式覆盖/可撤销 ✅；3. 热加载兼容 ✅；4. 全部 UT 通过 ✅ | ✅ |
| **M4** | 1. Tmp 文件超 TTL 自动清理 ✅；2. TenantResourceCleaner 接口可用 ✅；3. 清理不影响公共资源 ✅；4. 全部 UT 通过 ✅ | ✅ |
| **M5** | ⏳ 待实施 | ⏳ |

---

## 九、安全处理

> 2026-07-18：发现 `src/test/resources/APIKEY/apiconfig.json` 包含真实 LLM API 密钥信息，已在 git 历史中彻底抹除（撤销含敏感信息的 commit + 清理 reflog + gc --prune），磁盘文件保留但不再被 git 跟踪。

---

## 七、测试环境与依赖（原文保留）

### 7.1 UT 环境要求

| 依赖 | 版本 | 用途 |
|------|------|------|
| JUnit 5 Jupiter | 5.10.2 | 测试框架 |
| AssertJ | 3.25.3 | 断言 |
| Mockito | 5.2.0 | Mock（Redis 等外部依赖） |
| `@TempDir` | JUnit 5 内置 | 临时目录 |

### 7.2 ST 环境要求

| 依赖 | 用途 |
|------|------|
| Redis 实例 | KvTodoStorage（kv+redis 模式）、PersistenceCheckpointer 测试 |
| 本地文件系统 | FileTodoStorage、路径结构验证 |
| OBS/S3 Mock | 分层存储验证 |

### 7.3 测试执行命令

```bash
# 执行全部 UT
mvn test

# 执行单个里程碑 UT
mvn test -pl . -Dtest="com.openjiuwen.core.multitenant.**Test"
mvn test -pl . -Dtest="com.openjiuwen.harness.tools.**Test"
mvn test -pl . -Dtest="com.openjiuwen.core.singleagent.skills.**Test"

# 执行 ST（需 Redis 等外部依赖）
mvn verify -P integration-test
```
