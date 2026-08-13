# 技能 Rail 集成与演进

> 交叉引用: [README](./README.md) | [Overlay 覆盖](./overlay-hot-reload.md) | [06 Agent 演进](../../06-agentevolving-and-autoharness-module.md)

## 一、能力概述

Rails 是 DeepAgent 的工作流扩展点。skills 相关有四个 rail：`SkillUseRail` 负责把 skills 能力挂到 agent（注册 list_skill/skill_tool 工具、按签名热重载、注入技能 prompt、支持租户 overlay 与远程同步）；`SkillCreateRail`/`TeamSkillRail`/`TeamSkillCreateRail` 是演进型 rail，监测工具调用痕迹，达到阈值时提议 agent「创建新技能/团队技能」，把 skills 体系接入 agent 自演化闭环。

## 二、关键类与函数

### SkillUseRail — 技能使用主 rail

| 项 | 位置 | 说明 |
|----|------|------|
| 类声明 | [SkillUseRail.java](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/SkillUseRail.java#L48) | `extends DeepAgentRail` |
| SKILL_SECTION / SKILL_SECTION_PRIORITY | [L49](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/SkillUseRail.java#L49) / [L50](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/SkillUseRail.java#L50) | prompt 段名/优先级(90) |
| overlaySkillManager / tenantSkillManager / railWorkspaceResolver | [L52](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/SkillUseRail.java#L52) / [L53](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/SkillUseRail.java#L53) / [L54](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/SkillUseRail.java#L54) | 租户隔离三件套 |
| skillManager / tools / enableCache / skillsSnapshotSignature | [L57](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/SkillUseRail.java#L57) / [L72](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/SkillUseRail.java#L72) / [L73](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/SkillUseRail.java#L73) / [L74](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/SkillUseRail.java#L74) | 公共管理器/工具/缓存开关/签名快照 |
| 构造器 | [L146](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/SkillUseRail.java#L146) | 全参（目录/mode/启用禁用名单/远程源/缓存） |
| priority | [L163](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/SkillUseRail.java#L163) | 100 |
| init | [L174](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/SkillUseRail.java#L174) | 初始化管理器、overlay、工具注册、远程同步 |
| uninit | [L216](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/SkillUseRail.java#L216) | 反注册工具、清空字段 |
| reloadSkills / clearSkills | [L239](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/SkillUseRail.java#L239) / [L249](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/SkillUseRail.java#L249) | 重载/清空技能与签名 |
| beforeModelCall | [L273](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/SkillUseRail.java#L273) | 模型调用前按签名变化增量刷新并注入 prompt |
| registeredSkillNames | [L316](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/SkillUseRail.java#L316) | 已加载技能名 |
| buildSkillPrompt | [L391](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/SkillUseRail.java#L391) | 构造技能列表 prompt（中英文） |
| prepareSkills | [L403](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/SkillUseRail.java#L403) | 增量刷新公共与租户管理器 |
| filterSkills | [L566](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/SkillUseRail.java#L566) | 按查询过滤可见技能 |
| uploadRemoteSkill | [L613](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/SkillUseRail.java#L613) | 从 GitHub 上传远程技能 |
| RemoteSkillSource | [L825](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/SkillUseRail.java#L825) | 远程技能源 record，含路径越界校验 |

### 演进型 Rails

| 类 | 声明 | 触发条件 | 关键方法 |
|----|------|---------|---------|
| [SkillCreateRail](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/SkillCreateRail.java#L21) | L21 `extends EvolutionRail` | 工具调用数与多样性双达标 | [proposeIfNeeded](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/SkillCreateRail.java#L124) / [shouldProposeNewSkill](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/SkillCreateRail.java#L144) / [buildFollowUpPrompt](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/SkillCreateRail.java#L155) |
| [TeamSkillRail](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/TeamSkillRail.java#L22) | L22 `extends EvolutionRail` | view_task 全部完成 | [notifyTeamCompleted](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/TeamSkillRail.java#L85) / [allTasksCompleted](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/TeamSkillRail.java#L101) / [formatEvolutionRecords](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/TeamSkillRail.java#L129) |
| [TeamSkillCreateRail](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/TeamSkillCreateRail.java#L19) | L19 `extends EvolutionRail` | spawn_member 调用数达标 | [proposeIfNeeded](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/TeamSkillCreateRail.java#L118) / [shouldProposeNewTeamSkill](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/TeamSkillCreateRail.java#L138) / [buildFollowUpPrompt](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/TeamSkillCreateRail.java#L149) |

## 三、实现机制

1. **init 装配**：`SkillUseRail.init` 建 SkillManager（公共）+ OverlaySkillManager（租户隔离时）+ 注册 list_skill/skill_tool + 同步远程技能
2. **签名热重载**：`beforeModelCall` 每次模型调用前比对新旧 `buildSnapshotSignature`，变化才 `prepareSkills` 增量刷新，避免无谓 IO
3. **prompt 注入**：刷新后 `buildSkillPrompt` 生成中英文技能列表，作为 skills 段注入 system message
4. **演进提议**：三个 EvolutionRail 在 `onAfterInvoke` 检查阈值，达标则入队 follow-up（先 ask_user 确认再调 skill-creator/team-skill-creator），形成「使用→发现重复→沉淀新技能」的自演化闭环

## 四、测试覆盖

| 测试 | 行 | 覆盖 |
|------|----|------|
| [SkillUseRailHotReloadTest](file:///D:/jiuwen/main/agent-core-java/src/test/java/com/openjiuwen/harness/rails/SkillUseRailHotReloadTest.java#L29) | L29 | 签名比较、增量刷新、enableCache 切换、增删改生命周期、rail 构造 |
| [SkillUseRailTenantIsolationTest](file:///D:/jiuwen/main/agent-core-java/src/test/java/com/openjiuwen/harness/rails/SkillUseRailTenantIsolationTest.java#L28) | L28 | 端到端 overlay 创建、跨租户不可见、同名覆盖、无租户仅公共、热加载 |

## 五、小结

- SkillUseRail 是 skills 接入 DeepAgent 的统一装配点
- 热重载靠「签名快照比对 + 增量刷新」，零停机感知技能变化
- 演进 rail 把 skills 体系与 agent 自演化打通，实现「技能从使用中长出来」
