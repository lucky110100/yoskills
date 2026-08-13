# 租户覆盖与热重载

> 交叉引用: [README](./README.md) | [技能工具](./skill-tools.md) | [Rail 集成](./skill-rails-evolution.md)

## 一、能力概述

`OverlaySkillManager` 管理租户技能覆盖公共技能的 overlay 层：按 tenantId 缓存独立 `SkillManager`，支持技能文件解析、可见列表合并、`.override` 标记隐藏公共技能、隐式覆盖迁移。结合 `SkillManager.refreshIncrementally`，实现技能的新增/修改/删除无需重启即可对 agent 可见——这是 skills 体系的热重载基础，也是多租户隔离的核心。

## 二、关键类与函数

| 项 | 位置 | 说明 |
|----|------|------|
| 类声明 | [OverlaySkillManager.java](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/OverlaySkillManager.java#L29) | `public class OverlaySkillManager` |
| tenantSkillManager / publicSkillManager | [L30](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/OverlaySkillManager.java#L30) / [L31](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/OverlaySkillManager.java#L31) | 双层管理器 |
| overlayDir / workspaceResolver | [L32](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/OverlaySkillManager.java#L32) / [L33](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/OverlaySkillManager.java#L33) | override 标记目录/租户解析器 |
| tenantSkillManagerCache | [L36](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/OverlaySkillManager.java#L36) | 按 tenantId 缓存，避免并发互相污染 |
| 构造器 | [L38](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/OverlaySkillManager.java#L38) | 注入双层管理器 |
| getOrRefreshTenantSkillManager | [L57](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/OverlaySkillManager.java#L57) | 按 tenantId 缓存并增量刷新租户管理器 |
| resolveSkillFile | [L74](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/OverlaySkillManager.java#L74) | 解析租户技能文件路径，覆盖/存在租户副本时返回租户路径 |
| getAllVisibleSkills | [L95](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/OverlaySkillManager.java#L95) | 合并租户技能与未被覆盖的公共技能 |
| getAllVisibleSkillNames | [L130](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/OverlaySkillManager.java#L130) | 去重排序后的可见技能名 |
| overrideSkill | [L165](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/OverlaySkillManager.java#L165) | 创建 .override 标记隐藏公共技能 |
| revokeOverride | [L182](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/OverlaySkillManager.java#L182) | 删除标记恢复公共技能可见 |
| isOverridden | [L197](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/OverlaySkillManager.java#L197) | 检查标记是否存在 |
| getOverriddenNames | [L210](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/OverlaySkillManager.java#L210) | 扫描 overlay 目录获取被覆盖技能名 |
| migrateImplicitOverrides | [L232](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/OverlaySkillManager.java#L232) | 为同名租户技能补写隐式 override 标记 |

## 三、实现机制

1. **双层模型**：公共 SkillManager + 租户 SkillManager；租户同名技能隐式覆盖公共版
2. **per-tenant 缓存**：`tenantSkillManagerCache`（ConcurrentHashMap）按 tenantId 缓存独立管理器，避免并发请求共享同一管理器互相覆盖
3. **显式 override**：`overrideSkill` 在 overlayDir 创建 `.override` 标记文件，即使无租户副本也能隐藏公共技能；`revokeOverride` 删除标记恢复
4. **隐式迁移**：`migrateImplicitOverrides` 为已存在租户同名技能补写标记，使「隐式覆盖」与「显式 override」语义统一
5. **热重载**：`getOrRefreshTenantSkillManager` 调 `SkillManager.refreshIncrementally`，按 mtime 快照签名增量刷新，公共/租户技能增删改无需重启

## 四、测试覆盖

| 测试 | 行 | 覆盖 |
|------|----|------|
| [OverlaySkillManagerTest](file:///D:/jiuwen/main/agent-core-java/src/test/java/com/openjiuwen/harness/tools/OverlaySkillManagerTest.java#L22) | L22 | 文件解析、可见列表合并、override 标记创建/撤销、隐式迁移、无租户上下文边界 |
| [OverlaySkillManagerHotReloadTest](file:///D:/jiuwen/main/agent-core-java/src/test/java/com/openjiuwen/harness/tools/OverlaySkillManagerHotReloadTest.java#L24) | L24 | 公共/租户技能增删改在 refreshIncrementally 后对 overlay 可见性热更新 |
| [TenantSkillIsolationTest](file:///D:/jiuwen/main/agent-core-java/src/test/java/com/openjiuwen/core/multitenant/TenantSkillIsolationTest.java#L33) | L33 | 跨租户隔离、override 生命周期、覆盖优先级、标记创建/删除/迁移 |

## 五、小结

- 租户私有 + 公共共享的统一视图，靠双层 SkillManager + overlay 标记实现
- 热重载根因在 SkillManager 的 mtime 快照签名，overlay 只做合并与标记
- override 标记是「显式隐藏公共技能」的机制，与「租户同名隐式覆盖」互补
