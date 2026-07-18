# agent-core-java 多租户资源管理实施计划

> 基于文档：agent-core-java-multitenant-resource-brainstorming.md（已核对版）
> 编写日期：2026-07-16
> 项目：agent-core-java

---

## 一、总体里程碑

| 里程碑 | 范围 | 预估工作量 | 前置依赖 |
|--------|------|-----------|---------|
| **M1: P0 路径修复** | 修复 tenantId 路径重复 + PersistenceCheckpointer tenantId 前缀 | 小 | 无 |
| **M2: P1 Todo 显式隔离+SPI** | TodoStorage SPI + KvTodoStorage 复用 + TodoTool 改造 + Todo 显式租户感知 | 中 | M1 |
| **M3: P1 OverlaySkillManager** | OverlaySkillManager + 显式覆盖/可撤销 + SkillTool 改造 | 中 | M1 |
| **M4: P1 Tmp TTL 清理** | TmpFileCleaner + TenantResourceCleaner 接口 | 小 | M1 |
| **M5: P2 统一存储抽象** | TenantResourceStore + 适配 + 迁移 + VectorStore/DB 隔离 | 大 | M2, M3, M4 |

---

## 二、M1: P0 路径修复

### 2.1 变更清单

| # | 变更 | 文件 | 说明 |
|---|------|------|------|
| 1 | 修改 PATH_DEFAULT | `TenantNamespaceFactories.java` | 租户时返回 `tenants/{tenantId}`，无租户返回空串 |
| 2 | 重写 TenantWorkspaceResolver | `TenantWorkspaceResolver.java` | `tenants/{tenantId}/` 即 workspace，新增 resolveTeamMemoryDir/resolveTodoDir |
| 3 | 修改 WorkspaceType | `WorkspaceType.java` | 新增 TODO，WORKSPACE 的 subDirectory 为空串 |
| 4 | 修改 LocalWorkspaceStore | `LocalWorkspaceStore.java` | 处理空 subDirectory，createDirectories 增加 todo |
| 5 | 修改 TieredWorkspaceManager | `TieredWorkspaceManager.java` | 适配新的路径结构 |
| 6 | 完成 PersistenceCheckpointer tenantId 前缀 | `PersistenceCheckpointer.java` | 确认所有 KV 操作使用 TenantKVStoreKeyResolver |
| 7 | 更新所有受影响测试 | 多个测试文件 | 适配新路径结构 |

### 2.2 UT 测试用例

#### 2.2.1 TenantWorkspaceResolverTest（修改现有）

| 用例 ID | 用例名称 | 测试要点 |
|---------|---------|---------|
| UT-M1-001 | `testResolveWorkspaceRoot_withTenant` | 验证 `tenants/{tenantId}/` 为 workspace 根 |
| UT-M1-002 | `testResolveWorkspaceRoot_noTenant_backwardCompat` | 验证无租户返回 baseWorkspacePath |
| UT-M1-003 | `testResolveSkillRoot_withTenant` | 验证 `tenants/{tenantId}/skills` |
| UT-M1-004 | `testResolveSkillRoot_noTenant` | 验证 `baseWorkspacePath/skills` |
| UT-M1-005 | `testResolveTempDir_withTenant` | 验证 `tenants/{tenantId}/tmp` |
| UT-M1-006 | `testResolveTempDir_noTenant` | 验证 `baseWorkspacePath/tmp` |
| UT-M1-007 | `testResolveCheckpointDir_withTenant` | 验证 `tenants/{tenantId}/checkpoints` |
| UT-M1-008 | `testResolveCheckpointDir_noTenant` | 验证 `baseWorkspacePath/checkpoints` |
| UT-M1-009 | `testResolveTeamMemoryDir_withTenant` | 验证 `tenants/{tenantId}/team_memory` |
| UT-M1-010 | `testResolveTeamMemoryDir_noTenant` | 验证 `baseWorkspacePath/team_memory` |
| UT-M1-011 | `testResolveTodoDir_withTenant` | 验证 `tenants/{tenantId}/todo` |
| UT-M1-012 | `testResolveTodoDir_noTenant` | 验证 `baseWorkspacePath/todo` |
| UT-M1-013 | `testInitializeTenantSpace_createsAllDirs` | 验证初始化创建 workspace/skills/tmp/checkpoints/team_memory/todo |
| UT-M1-014 | `testInitializeTenantSpace_workspaceIsTenantRoot` | 验证 workspace 根 = `tenants/{tenantId}/` |
| UT-M1-015 | `testNoTenantIdDuplication` | 验证路径中 tenantId 不再重复 |
| UT-M1-016 | `testIsPathWithinTenant_withinBoundary` | 路径在租户边界内返回 true |
| UT-M1-017 | `testIsPathWithinTenant_outsideBoundary` | 路径在租户边界外返回 false |
| UT-M1-018 | `testIsPathWithinTenant_noTenant_alwaysTrue` | 无租户时始终返回 true |
| UT-M1-019 | `testInitializeTenantSpace_concurrentSafety` | 20 线程并发初始化同一租户，只创建一次 |
| UT-M1-020 | `testSafeTenantId_specialChars_sanitized` | 特殊字符被替换，路径安全 |
| UT-M1-021 | `testDifferentTenants_isolatedPaths` | 不同租户路径互不包含 |

#### 2.2.2 TenantNamespaceFactoriesTest（修改现有）

| 用例 ID | 用例名称 | 测试要点 |
|---------|---------|---------|
| UT-M1-022 | `testPathDefault_withTenant` | 验证返回 `tenants/{tenantId}` |
| UT-M1-023 | `testPathDefault_noTenant` | 验证返回空串 |
| UT-M1-024 | `testKvStoreDefault_withTenant` | 验证返回 `{tenantId}:rawKey` |
| UT-M1-025 | `testKvStoreDefault_noTenant` | 验证返回 rawKey 不变 |

#### 2.2.3 LocalWorkspaceStoreTest（新增）

| 用例 ID | 用例名称 | 测试要点 |
|---------|---------|---------|
| UT-M1-026 | `testResolvePath_workspaceType_emptySubDir` | WORKSPACE 类型 subDirectory 为空串时路径正确 |
| UT-M1-027 | `testResolvePath_skillType` | SKILLS 类型路径包含 skills 子目录 |
| UT-M1-028 | `testResolveDefaultPath_emptySubDir` | 默认无租户 + 空子目录时返回 basePath |
| UT-M1-029 | `testCreateDirectories_createsAllSubDirs` | 创建 skills/tmp/checkpoints/team_memory/todo |

#### 2.2.4 TieredWorkspaceManagerTest（修改现有）

| 用例 ID | 用例名称 | 测试要点 |
|---------|---------|---------|
| UT-M1-030 | `testResolveWorkspace_newPathStructure` | 验证新路径 `tenants/{tid}/` 下无重复 |
| UT-M1-031 | `testResolveDefault_noTenant` | 验证无租户默认路径不变 |
| UT-M1-032 | `testInitializeTenantSpace_newStructure` | 验证目录结构符合新设计 |
| UT-M1-033 | `testCustomNamespaceFactory` | 自定义工厂仍可用 |
| UT-M1-034 | `testRemoteStore_newPathStructure` | OBS/S3 远程路径也使用新结构 |

#### 2.2.5 TenantBackwardCompatTest（修改现有）

| 用例 ID | 用例名称 | 测试要点 |
|---------|---------|---------|
| UT-M1-035 | `testNoTenant_workspaceRoot_isBasePath` | 无租户时 workspace = baseWorkspacePath |
| UT-M1-036 | `testNoTenant_skillRoot_isBaseSkills` | 无租户时 skill = baseWorkspacePath/skills |
| UT-M1-037 | `testNoTenant_tmpDir_isBaseTmp` | 无租户时 tmp = baseWorkspacePath/tmp |
| UT-M1-038 | `testNoTenant_kvKey_originalFormat` | KV key 无前缀 |
| UT-M1-039 | `testNoTenant_pathWithinTenant_alwaysTrue` | 路径校验始终通过 |

#### 2.2.6 PersistenceCheckpointerTenantTest（新增）

| 用例 ID | 用例名称 | 测试要点 |
|---------|---------|---------|
| UT-M1-040 | `testAgentStateKey_withTenant` | Agent 状态 key 格式为 `tenantId:sessionId:agent:agentId:state_blobs` |
| UT-M1-041 | `testAgentStateKey_noTenant` | 无租户 key 格式为 `sessionId:agent:agentId:state_blobs` |
| UT-M1-042 | `testWorkflowStateKey_withTenant` | Workflow 状态 key 带租户前缀 |
| UT-M1-043 | `testGraphStateKey_withTenant` | Graph 状态 key 带租户前缀 |
| UT-M1-044 | `testRelease_withTenant_deletesByPrefix` | release 按 `tenantId:sessionId:` 前缀删除 |
| UT-M1-045 | `testSessionExists_withTenant` | sessionExists 正确检测租户前缀下的状态 |
| UT-M1-046 | `testTenantIsolation_sameSession_differentTenants` | 同一 sessionId 在不同租户下状态独立 |

### 2.3 ST 系统测试用例

| 用例 ID | 用例名称 | 前置条件 | 操作步骤 | 预期结果 |
|---------|---------|---------|---------|---------|
| ST-M1-001 | 无租户场景路径兼容性验证 | 旧版本数据存在于 baseWorkspacePath | 升级后不传 TenantContext 启动 DeepAgent | 所有文件操作路径不变，tmp/skills/checkpoints 在原位置正常读写 |
| ST-M1-002 | 新租户路径结构验证 | 启用 enableTenantIsolation=true | 传入 tenantId="dept01" 调用 DeepAgent | 目录结构为 `tenants/dept01/`，其下含 skills/tmp/checkpoints/team_memory/todo，无 tenantId 重复 |
| ST-M1-003 | 多租户路径隔离验证 | 创建 tenantA 和 tenantB | 分别写入文件到各自 workspace | tenantA 文件在 tenantB workspace 中不可见，反之亦然 |
| ST-M1-004 | PersistenceCheckpointer 多租户验证 | 配置 KVStore=Redis | tenantA 和 tenantB 各创建同一 sessionId 的 session | Redis 中 key 分别为 `tenantA:session-1:...` 和 `tenantB:session-1:...`，互不干扰 |
| ST-M1-005 | 路径穿越安全验证 | 启用多租户 | 传入 tenantId 含 `../../` | safeTenantId 过滤后路径仍在租户边界内，无越权访问 |

---

## 三、M2: P1 Todo 显式隔离 + SPI

### 3.1 变更清单

| # | 变更 | 文件 | 说明 |
|---|------|------|------|
| 1 | 新增 TodoStorageProvider | `TodoStorageProvider.java` | SPI 接口 |
| 2 | 新增 FileTodoStorageProvider | `FileTodoStorageProvider.java` | 内置 file 实现 |
| 3 | 新增 KvTodoStorageProvider | `KvTodoStorageProvider.java` | KV 抽象层 Provider，复用已有 KvTodoStorage + KVStoreFactory，介质由 kvStoreConfig 决定 |
| 4 | 新增 TodoStorageFactory | `TodoStorageFactory.java` | 工厂类，ServiceLoader 发现 |
| 5 | 改造 TodoTool | `TodoTool.java` | 新增 fromConfig()，TenantAware 解析路径 |
| 6 | 改造 FileTodoStorage | `FileTodoStorage.java` | 增加 TenantAware 路径解析 |
| 7 | 新增 SPI Service 文件 | `META-INF/services/...TodoStorageProvider` | 注册 FileTodoStorageProvider + KvTodoStorageProvider |
| 8 | DeepAgentConfig 增加配置 | `DeepAgentConfig.java` | todoStorageType（默认"file"，可选"kv"），KV 存储介质由 kvStoreConfig 统一决定 |
| 9 | 修改 TaskPlanningRail | `TaskPlanningRail.java` | TodoTool 创建逻辑适配新 SPI，kv 模式复用 DeepAgent.kvStore |
| 10 | RunnerImpl 共享 BaseKVStore | `RunnerImpl.java` | kvStoreConfig 创建的 BaseKVStore 实例共享给 PersistenceCheckpointer 和 KvTodoStorage |

**设计要点：KvTodoStorage 已存在，无需新建 RedisTodoStorage**

`KvTodoStorage` 已基于 `BaseKVStore` SPI + `TenantKVStoreKeyResolver` 实现了存储介质无关的 KV 存储。传入 `RedisStore`（`extends BaseKVStore`）即为 Redis 模式。新增的 `KvTodoStorageProvider` 按**抽象层**分（file/kv），介质选择下沉到 `KVStoreFactory`。

**KV 存储 key 格式（与 PersistenceCheckpointer 一致）：**

| 场景 | key 格式 | 示例 |
|------|---------|------|
| 无租户 | `{sessionId}:todo` | `sess-abc123:todo` |
| 有租户 `dept01` | `dept01:{sessionId}:todo` | `dept01:sess-abc123:todo` |

租户前缀通过 `TenantKVStoreKeyResolver.resolveKey()` 自动添加，与 PersistenceCheckpointer 的 key 隔离方式完全一致。

**配置方式（与 Checkpointer 共享 kvStoreConfig）：**

Java Config:
```java
DeepAgentConfig config = DeepAgentConfig.builder()
        .todoStorageType("kv")                          // "file" | "kv"
        .kvStoreConfig(Map.of(                          // 与 Checkpointer 共享
            "type", "redis",
            "conf", Map.of("connection", Map.of("url", "redis://redis.example.com:6379"))
        ))
        .build();
```

YAML:
```yaml
kvStoreConfig:                    # 唯一入口，Checkpointer + Todo 共用
  type: redis
  conf:
    connection:
      url: redis://127.0.0.1:6379

todo:
  storage:
    type: kv                       # file | kv（kv 模式下介质由 kvStoreConfig 决定）
```

**与 Checkpointer 共享 BaseKVStore 实例：**

```
kvStoreConfig → KVStoreFactory.create("redis", conf) → RedisStore (共享实例)
    ├── PersistenceCheckpointer(sharedRedisStore)     ← Checkpointer 复用
    └── KvTodoStorage(sharedRedisStore)               ← Todo 复用
```

一套 Redis 连接、一套配置、一个共享实例，Checkpointer 和 Todo 自然打通。

**与 issue34（TodoTool Support Redis）需求对应关系：**

| issue34 需求 | 实施项 | 覆盖 |
|-------------|-------|------|
| 多实例共享 Todo 数据 | KvTodoStorage(RedisStore) — 多实例通过 Redis 共享 | ✅ |
| 利用框架已有的 Redis 能力 | KvTodoStorageProvider 通过 KVStoreFactory 复用 BaseKVStore + RedisKVStoreProvider，与 PersistenceCheckpointer 共享同一 RedisStore 实例 | ✅ |
| 存储抽象层可扩展 | TodoStorageProvider SPI + TodoStorageFactory，按抽象层（file/kv）分 Provider | ✅ |
| 租户数据隔离 | KvTodoStorage.buildKey() 使用 TenantKVStoreKeyResolver，与 PersistenceCheckpointer 隔离方式一致 | ✅ |

### 3.2 UT 测试用例

#### 3.2.1 TodoStorageProviderTest（新增）

| 用例 ID | 用例名称 | 测试要点 |
|---------|---------|---------|
| UT-M2-001 | `testFileProvider_typeName` | typeName() 返回 "file" |
| UT-M2-002 | `testFileProvider_createWithBasePath` | create() 返回 FileTodoStorage 实例 |
| UT-M2-003 | `testKvProvider_typeName` | typeName() 返回 "kv" |
| UT-M2-004 | `testKvProvider_createWithKvStore` | create() 返回 KvTodoStorage 实例 |
| UT-M2-005 | `testKvProvider_delegatesToKVStoreFactory` | KvTodoStorageProvider 通过 KVStoreFactory.create() 获取 BaseKVStore |

#### 3.2.2 TodoStorageFactoryTest（新增）

| 用例 ID | 用例名称 | 测试要点 |
|---------|---------|---------|
| UT-M2-006 | `testCreate_fileType` | create("file", conf) 返回 FileTodoStorage |
| UT-M2-007 | `testCreate_kvType` | create("kv", conf) 返回 KvTodoStorage |
| UT-M2-008 | `testCreate_unknownType_throws` | create("unknown", conf) 抛出 IllegalArgumentException |
| UT-M2-009 | `testHasProvider_file` | hasProvider("file") 返回 true |
| UT-M2-010 | `testHasProvider_kv` | hasProvider("kv") 返回 true |
| UT-M2-011 | `testHasProvider_unknown` | hasProvider("unknown") 返回 false |
| UT-M2-012 | `testRegister_customProvider` | register() 注入自定义 Provider 后 hasProvider 返回 true |
| UT-M2-013 | `testCreate_nullConf_usesEmptyMap` | create("file", null) 不抛异常 |

#### 3.2.3 KvTodoStorageTest（修改现有，补充租户隔离用例）

| 用例 ID | 用例名称 | 测试要点 |
|---------|---------|---------|
| UT-M2-014 | `testLoad_emptySession_returnsEmptyList` | KV 中无数据时返回空列表 |
| UT-M2-015 | `testSaveThenLoad_returnsItems` | save 后 load 返回相同 TodoItem 列表 |
| UT-M2-016 | `testSaveOverwrites_previousData` | 二次 save 覆盖前一次数据 |
| UT-M2-017 | `testDelete_removesData` | delete 后 load 返回空列表 |
| UT-M2-018 | `testBuildKey_noTenant` | 无租户时 key 格式为 `{sessionId}:todo` |
| UT-M2-019 | `testBuildKey_withTenant` | 有租户时 key 格式为 `tenantId:{sessionId}:todo` |
| UT-M2-020 | `testTenantIsolation_sameSession_differentTenants` | 同一 sessionId 在不同租户下数据独立 |
| UT-M2-021 | `testNullKvStore_throwsNPE` | 构造时传入 null kvStore 抛出 NPE |
| UT-M2-022 | `testLoad_blankJson_returnsEmptyList` | KV 中存储空白 JSON 时返回空列表 |
| UT-M2-023 | `testSave_multipleItems` | 保存多个 TodoItem 后全部可加载 |
| UT-M2-024 | `testKvTodoStorage_withRedisStore` | 传入 RedisStore 时 CRUD 正常（验证 BaseKVStore 多态） |
| UT-M2-025 | `testKvTodoStorage_withInMemoryKVStore` | 传入 InMemoryKVStore 时 CRUD 正常 |

#### 3.2.4 TenantAwareFileTodoStorageTest（新增）

| 用例 ID | 用例名称 | 测试要点 |
|---------|---------|---------|
| UT-M2-026 | `testSave_noTenant_defaultPath` | 无租户时保存在 baseWorkspacePath/todo/{sessionId}/todo.json |
| UT-M2-027 | `testSave_withTenant_tenantPath` | 有租户时保存在 tenants/{tenantId}/todo/{sessionId}/todo.json |
| UT-M2-028 | `testLoad_noTenant` | 无租户时从默认路径读取 |
| UT-M2-029 | `testLoad_withTenant` | 有租户时从租户路径读取 |
| UT-M2-030 | `testTenantIsolation_fileBased` | 不同租户文件不互相可见 |
| UT-M2-031 | `testDelete_noTenant` | 无租户删除默认路径 |
| UT-M2-032 | `testDelete_withTenant` | 有租户删除租户路径 |

#### 3.2.5 TodoToolFromConfigTest（新增）

| 用例 ID | 用例名称 | 测试要点 |
|---------|---------|---------|
| UT-M2-033 | `testFromConfig_fileType` | fromConfig("file", conf) 返回使用 FileTodoStorage 的 TodoTool |
| UT-M2-034 | `testFromConfig_kvType` | fromConfig("kv", conf) 返回使用 KvTodoStorage 的 TodoTool |
| UT-M2-035 | `testLegacyConstructor_fileStorage` | new TodoTool(workspace) 使用 FileTodoStorage |
| UT-M2-036 | `testStorageConstructor_customStorage` | new TodoStorage(customStorage) 使用传入的实现 |
| UT-M2-037 | `testTodoCRUD_viaFileConfig` | 通过 fromConfig 创建的 file 模式 TodoTool CRUD 正常 |
| UT-M2-038 | `testTodoCRUD_viaKvConfig` | 通过 fromConfig 创建的 kv 模式（InMemoryKVStore）TodoTool CRUD 正常 |
| UT-M2-039 | `testFromConfig_kvWithSharedKvStore` | kv 模式复用 DeepAgent.kvStore 共享实例 |
| UT-M2-040 | `testFromConfig_defaultType_isFile` | 不配置 todoStorageType 时默认使用 file |
| UT-M2-041 | `testKvTodoStorage_resolvesKeyViaTenantKVStoreKeyResolver` | 验证 key 通过 TenantKVStoreKeyResolver 生成，无租户时无前缀 |
| UT-M2-042 | `testKvTodoStorage_resolvesKeyWithTenantPrefix` | 有租户时 key 自动加 tenantId: 前缀 |
| UT-M2-043 | `testKvTodoStorageProvider_reusesKVStoreFactory` | 验证 KvTodoStorageProvider 通过 KVStoreFactory 获取 BaseKVStore |
| UT-M2-044 | `testTodoStorageFactory_serviceLoaderDiscoversProviders` | ServiceLoader 自动发现 file 和 kv 两个 Provider |
| UT-M2-045 | `testTaskPlanningRail_kvMode_usesSharedKvStore` | TaskPlanningRail 创建 TodoTool 时 kv 模式复用 DeepAgent.kvStore |

### 3.3 ST 系统测试用例

| 用例 ID | 用例名称 | 前置条件 | 操作步骤 | 预期结果 |
|---------|---------|---------|---------|---------|
| ST-M2-001 | TodoTool File 模式多租户隔离 | 配置 todoStorageType=file | tenantA 创建 Todo，tenantB 创建 Todo | 各自 Todo 文件在独立路径下，互不可见 |
| ST-M2-002 | TodoTool KV+Redis 模式多实例共享 | 配置 todoStorageType=kv + kvStoreConfig=redis，启动两个 Agent 实例 | 实例1 创建 Todo，实例2 读取 | 实例2 可读到实例1 创建的 Todo 数据（通过共享 Redis） |
| ST-M2-003 | TodoTool KV+Redis 模式多租户隔离 | 配置 todoStorageType=kv + kvStoreConfig=redis | tenantA 和 tenantB 各创建 Todo | Redis key 按租户前缀隔离，A 无法读取 B 的 Todo |
| ST-M2-004 | TodoTool 从 File 切换到 KV 模式 | 先用 file 模式运行一段时间 | 修改配置切换为 kv 模式 | 新 Todo 写入 KV，旧 file 数据不受影响（不自动迁移） |
| ST-M2-005 | TodoTool SPI 自定义扩展 | 实现 CustomTodoStorageProvider | 配置 todoStorageType=custom | TodoTool 使用自定义存储实现 |
| ST-M2-006 | DeepAgent 集成 KV Todo + 共享 RedisStore | 配置 todoStorageType=kv + kvStoreConfig=redis | 启动 DeepAgent 执行工作流 | 工作流中 TodoTool 和 PersistenceCheckpointer 共享同一 RedisStore 实例 |
| ST-M2-007 | YAML 配置 kvStoreConfig 共享 | YAML 中配置 kvStoreConfig.type=redis + todo.storage.type=kv | 重启服务 | TodoTool 和 Checkpointer 自动使用同一 Redis 存储，无需改代码 |
| ST-M2-008 | KV 模式多租户 key 前缀验证 | 配置 todoStorageType=kv + kvStoreConfig=redis | tenantA 和 tenantB 各创建同 sessionId 的 Todo | Redis 中 key 分别为 `tenantA:session-1:todo` 和 `tenantB:session-1:todo`，互不干扰 |
| ST-M2-009 | File→KV 模式切换后旧数据不可见 | File 模式运行产生 Todo 数据 | 切换到 KV 模式后读取同 sessionId | 旧 File 数据不自动迁移，KV 中为空（符合预期，需业务方自行迁移） |

---

## 四、M3: P1 OverlaySkillManager

### 4.1 变更清单

| # | 变更 | 文件 | 说明 |
|---|------|------|------|
| 1 | 新增 OverlaySkillManager | `OverlaySkillManager.java` | 双层查找 + overlay 标记 |
| 2 | 改造 SkillTool | `SkillTool.java` | 使用 OverlaySkillManager |
| 3 | 改造 ListSkillTool | `ListSkillTool.java` | 使用 OverlaySkillManager |
| 4 | 增加 overrideSkill/revokeOverride | `OverlaySkillManager.java` | 显式覆盖管理 |
| 5 | 修改 TenantWorkspaceResolver | `TenantWorkspaceResolver.java` | 初始化时创建租户 Skill 空目录 |

### 4.2 UT 测试用例

#### 4.2.1 OverlaySkillManagerTest（新增）

| 用例 ID | 用例名称 | 测试要点 |
|---------|---------|---------|
| UT-M3-001 | `testGetAllVisibleSkills_noTenant_publicOnly` | 无租户时只返回公共 Skill |
| UT-M3-002 | `testGetAllVisibleSkills_tenantWithPrivate` | 有租户时返回私有 + 未覆盖的公共 Skill |
| UT-M3-003 | `testGetAllVisibleSkills_noOverlaps` | 租户私有和公共 Skill 无重名时全部返回 |
| UT-M3-004 | `testOverrideSkill_createsMarkerAndRegisters` | overrideSkill 后 overlay 标记文件存在，私有 Skill 已注册 |
| UT-M3-005 | `testOverrideSkill_publicSkillHidden` | 覆盖后公共同名 Skill 不再出现在可见列表 |
| UT-M3-006 | `testRevokeOverride_removesMarkerAndUnregisters` | 撤销覆盖后 overlay 标记删除，公共 Skill 恢复可见 |
| UT-M3-007 | `testRevokeOverride_nonExistent_throws` | 撤销不存在的覆盖时抛出异常 |
| UT-M3-008 | `testOverrideSkill_sameNameTwice_idempotent` | 重复覆盖同一 Skill 幂等 |
| UT-M3-009 | `testRefreshIncrementally_tenantLayer` | 租户层新增 Skill 后 refresh 可见 |
| UT-M3-010 | `testRefreshIncrementally_publicLayer` | 公共层新增 Skill 后 refresh 可见 |
| UT-M3-011 | `testRefreshIncrementally_bothLayers` | 两层同时变化时都刷新 |
| UT-M3-012 | `testGetAllVisibleSkills_orderTenantFirst` | 租户 Skill 在前，公共 Skill 在后 |
| UT-M3-013 | `testIsOverridden_withMarker` | 有 overlay 标记时返回 true |
| UT-M3-014 | `testIsOverridden_noMarker` | 无 overlay 标记时返回 false |
| UT-M3-015 | `testTenantPrivateSkill_sameNameAsPublic_tenantWins` | 同名时租户私有优先（不依赖 overlay 标记） |
| UT-M3-016 | `testEmptyPublicSkills` | 公共 Skill 目录为空时仅返回租户私有 |
| UT-M3-017 | `testEmptyTenantSkills` | 租户 Skill 目录为空时仅返回公共 |

#### 4.2.2 OverlaySkillManagerHotReloadTest（新增）

| 用例 ID | 用例名称 | 测试要点 |
|---------|---------|---------|
| UT-M3-018 | `testPublicSkillUpdate_visibleAfterRefresh` | 修改公共 SKILL.md 后 refresh 增量加载 |
| UT-M3-019 | `testTenantSkillUpdate_visibleAfterRefresh` | 修改租户 SKILL.md 后 refresh 增量加载 |
| UT-M3-020 | `testNewPublicSkill_visibleAfterRefresh` | 新增公共 Skill 目录后 refresh 可见 |
| UT-M3-021 | `testDeletedPublicSkill_removedAfterRefresh` | 删除公共 Skill 目录后 refresh 移除 |
| UT-M3-022 | `testNewTenantSkill_visibleAfterRefresh` | 新增租户 Skill 目录后 refresh 可见 |
| UT-M3-023 | `testDeletedTenantSkill_removedAfterRefresh` | 删除租户 Skill 目录后 refresh 移除 |

### 4.3 ST 系统测试用例

| 用例 ID | 用例名称 | 前置条件 | 操作步骤 | 预期结果 |
|---------|---------|---------|---------|---------|
| ST-M3-001 | Skill 双层查找端到端验证 | 部署公共 Skill A/B/C，租户私有 Skill D | 租户调用 ListSkillTool | 返回 A/B/C/D 四个 Skill |
| ST-M3-002 | Skill 显式覆盖端到端验证 | 公共 Skill A 存在 | 租户 overrideSkill("A", tenantDir) | 租户可见的 Skill A 为私有版本，公共 A 被隐藏 |
| ST-M3-003 | Skill 覆盖撤销端到端验证 | 租户已覆盖 Skill A | 租户 revokeOverride("A") | 租户可见的 Skill A 恢复为公共版本 |
| ST-M3-004 | Skill 热加载端到端验证 | 运行中 Agent | 在公共 Skill 目录新增 Skill E，触发 refresh | 新增的 Skill E 对所有租户立即可见 |
| ST-M3-005 | 无租户 Skill 查找端到端验证 | 不传 TenantContext | 调用 SkillTool | 仅返回公共 Skill，不报错 |
| ST-M3-006 | 多租户 Skill 隔离端到端验证 | tenantA 私有 Skill X，tenantB 无私有 Skill | tenantA 查找 Skill X 找到，tenantB 查找 Skill X 找到公共版本（如果存在） | 租户私有与公共隔离正确 |

---

## 五、M4: P1 Tmp TTL 清理 + 清理接口

### 5.1 变更清单

| # | 变更 | 文件 | 说明 |
|---|------|------|------|
| 1 | 新增 TenantResourceCleaner | `TenantResourceCleaner.java` | 清理接口 |
| 2 | 新增 DefaultTenantResourceCleaner | `DefaultTenantResourceCleaner.java` | 默认实现 |
| 3 | 新增 TmpFileCleaner | `TmpFileCleaner.java` | TTL 定时扫描清理 |
| 4 | DeepAgentConfig 增加 tmpTtl | `DeepAgentConfig.java` | TTL 配置项，默认 24h |

### 5.2 UT 测试用例

#### 5.2.1 TmpFileCleanerTest（新增）

| 用例 ID | 用例名称 | 测试要点 |
|---------|---------|---------|
| UT-M4-001 | `testCleanExpiredFiles_defaultTmp` | 默认 tmp 目录下超 TTL 文件被删除 |
| UT-M4-002 | `testCleanExpiredFiles_tenantTmp` | 租户 tmp 目录下超 TTL 文件被删除 |
| UT-M4-003 | `testKeepFreshFiles` | TTL 内的文件不被删除 |
| UT-M4-004 | `testCustomTtl` | 自定义 TTL（如 1h）生效 |
| UT-M4-005 | `testCleanSubdirectories` | 子目录中超 TTL 的文件也被清理 |
| UT-M4-006 | `testEmptyTmpDir_noError` | 空 tmp 目录不报错 |
| UT-M4-007 | `testNoTenantTmpDir_noError` | 无租户且默认 tmp 不存在时不报错 |
| UT-M4-008 | `testConcurrentCleanAndWrite` | 清理与写入并发执行不异常 |

#### 5.2.2 TenantResourceCleanerTest（新增）

| 用例 ID | 用例名称 | 测试要点 |
|---------|---------|---------|
| UT-M4-009 | `testCleanupWorkspace_deletesTenantDir` | cleanupWorkspace 删除租户目录 |
| UT-M4-010 | `testCleanupSkills_deletesSkillDir` | cleanupSkills 仅删除 skills 子目录 |
| UT-M4-011 | `testCleanupCheckpoints_deletesSessionData` | cleanupCheckpoints 删除指定 session 的 checkpoint |
| UT-M4-012 | `testCleanupTeamMemory_deletesTeamDir` | cleanupTeamMemory 删除指定 team 的 memory |
| UT-M4-013 | `testCleanupTodo_deletesTodoDir` | cleanupTodo 删除指定 session 的 todo |
| UT-M4-014 | `testCleanupAll_deletesEntireTenant` | cleanupAll 删除整个租户目录 |
| UT-M4-015 | `testCleanupWorkspace_nonExistentTenant_noError` | 清理不存在的租户不报错 |
| UT-M4-016 | `testCleanupAll_preservesPublicSkills` | cleanupAll 不删除公共 Skill |

### 5.3 ST 系统测试用例

| 用例 ID | 用例名称 | 前置条件 | 操作步骤 | 预期结果 |
|---------|---------|---------|---------|---------|
| ST-M4-001 | Tmp TTL 自动清理验证 | 配置 tmpTtl=1h | 在 tmp 目录创建文件后等待超时 | 超 TTL 的文件被自动清理，TTL 内的文件保留 |
| ST-M4-002 | 租户资源清理端到端验证 | 创建租户并产生各类资源 | 业务方调用 cleanupAll(tenantId) | 租户目录被删除，公共资源不受影响 |
| ST-M4-003 | 部分清理不影响其他资源验证 | 租户有 workspace + skills + todo | 业务方调用 cleanupSkills(tenantId) | skills 目录删除，workspace 和 todo 保留 |
| ST-M4-004 | Tmp 清理不影响运行中 Session | Session 运行中在 tmp 写入临时文件 | TmpFileCleaner 触发扫描 | 运行中使用的 tmp 文件（TTL 内）不被删除 |

---

## 六、M5: P2 统一存储抽象（概要）

> M5 详细实施计划在 M2-M4 完成后根据实际情况细化，此处给出概要。

### 6.1 变更清单（概要）

| # | 变更 | 说明 |
|---|------|------|
| 1 | 新增 TenantResourceStore 接口 | 统一文件类 + KV 类操作 |
| 2 | 新增 ResourceType 枚举 | 含 StoreCategory 分类 |
| 3 | 新增 TenantResourceStoreProvider SPI | 统一 Provider |
| 4 | 适配 Workspace/Skill/Tmp/Checkpoints | 实现 LocalTenantResourceStore |
| 5 | 适配 Session/Agent/Workflow State | 实现 KvTenantResourceStore |
| 6 | 适配 VectorStore | 实现 VectorTenantResourceStore |
| 7 | 统一配置 TenantStorageConfig | YAML + Java Config |
| 8 | BaseDbStore 增加 tenant_id 列 | MessageManager, ScopeUserMappingManager |
| 9 | VectorStore 集合名 tenantId 前缀 | 各 VectorStoreProvider |
| 10 | 租户数据归档/迁移工具 | 新增工具类 |

### 6.2 UT 测试用例（概要）

| 用例类别 | 用例数 | 关键覆盖点 |
|---------|-------|-----------|
| TenantResourceStore 接口 | 10+ | resolvePath/put/get/delete/listByPrefix 各方法 |
| LocalTenantResourceStore | 8+ | 文件读写、目录创建、租户隔离 |
| KvTenantResourceStore | 8+ | KV CRUD、租户前缀、批量操作 |
| VectorTenantResourceStore | 6+ | 集合名前缀、租户隔离 |
| TenantStorageConfig | 5+ | 配置解析、默认值、覆盖规则 |
| BaseDbStore tenant_id | 8+ | INSERT/SELECT/DELETE 带 tenant_id 条件 |
| 归档/迁移工具 | 6+ | 导出、导入、增量迁移 |

### 6.3 ST 系统测试用例（概要）

| 用例 ID | 用例名称 | 验证要点 |
|---------|---------|---------|
| ST-M5-001 | 统一存储配置端到端 | 通过 YAML 配置不同资源使用不同存储介质，验证路由正确 |
| ST-M5-002 | VectorStore 多租户隔离 | 不同租户写入向量数据后按 tenantId 前缀隔离 |
| ST-M5-003 | DB tenant_id 列隔离 | 不同租户的 Message/ScopeUserMapping 按 tenant_id 过滤 |
| ST-M5-004 | 租户数据归档恢复 | 归档租户全部数据到对象存储，恢复后数据完整 |
| ST-M5-005 | 存储介质热切换 | 运行中从 local 切换到 redis，新数据写入 redis，旧数据可查 |

---

## 七、测试环境与依赖

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

---

## 八、验收标准

| 里程碑 | 验收标准 |
|--------|---------|
| **M1** | 1. 路径中 tenantId 不再重复；2. 无租户场景所有路径与修改前一致；3. PersistenceCheckpointer KV key 带租户前缀；4. 全部 UT 通过 |
| **M2** | 1. TodoTool 支持 file/kv 两种存储模式；2. kv 模式通过 KVStoreFactory 可对接 Redis/InMemory 等任意 BaseKVStore；3. kv 模式与 PersistenceCheckpointer 共享同一 BaseKVStore 实例；4. Todo 显式租户隔离；5. SPI 可扩展；6. 全部 UT 通过 |
| **M3** | 1. OverlaySkillManager 双层查找正确；2. 显式覆盖/可撤销功能正常；3. 热加载兼容；4. 全部 UT 通过 |
| **M4** | 1. Tmp 文件超 TTL 自动清理；2. TenantResourceCleaner 接口可用；3. 清理不影响公共资源；4. 全部 UT 通过 |
| **M5** | 1. 统一存储抽象接口定义完成；2. 现有资源适配完成；3. VectorStore/DB 隔离完成；4. 全部 UT 通过 |
