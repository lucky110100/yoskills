# Skills 技能管理

> 交叉引用: [项目概述](../../01-project-overview.md) | [整体架构](../../02-overall-architecture.md) | [06 Agent 演进与 AutoHarness](../../06-agentevolving-and-autoharness-module.md)
> 源码根: `D:\jiuwen\main\agent-core-java` · 包: `core.singleagent.skills` / `harness.tools` / `harness.rails` / `dev_tools`

## 一、能力概述

Skills 管理负责把磁盘上的技能目录（含 `SKILL.md`）注册成可查询元数据，再把元数据拼成补充提示词，让 ReActAgent 在推理时知道「有哪些 skill、去哪读 `SKILL.md`」。它分五层：核心注册表（`Skill`/`SkillManager`/`SkillUtil`/`RemoteSkillUtil`）、agent 工具（`SkillTool`/`ListSkillTool`）、租户覆盖与热重载（`OverlaySkillManager`）、工作流集成与演进（`SkillUseRail` 等 rail）、开发工具（`SkillCreator`/`SkillEvaluator`）。

**关键设计判断**：skill 是「元数据层」而非「执行层」——它不自动替 Agent 挂文件/代码/命令工具，只负责发现与提示，执行靠 sysop 工具。远程 skill 是「分发/同步渠道」，下载到本地后才由本地注册表加载。

## 二、特性索引（特性↔代码↔测试可追踪性矩阵）

| 特性 | 职责 | 入口 | 实现 | 测试 | 依赖 | 状态 |
|------|------|------|------|------|------|------|
| 技能元数据与注册表 | Skill 元数据 + 注册/发现/增量刷新/受信根安全 | [register](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillManager.java#L93) | [Skill.java](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/Skill.java#L21), [SkillManager.java](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillManager.java#L36) | [SkillManagerTest](file:///D:/jiuwen/main/agent-core-java/src/test/java/com/openjiuwen/core/singleagent/skills/SkillManagerTest.java#L20), [IncrementalTest](file:///D:/jiuwen/main/agent-core-java/src/test/java/com/openjiuwen/core/singleagent/skills/SkillManagerIncrementalTest.java#L22) | ← sysop | active |
| 技能提示词封装 | 组合两管理器、生成 prompt、路径泄露防护 | [getSkillPrompt](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillUtil.java#L152) | [SkillUtil.java](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillUtil.java#L25) | [SkillUtilTest](file:///D:/jiuwen/main/agent-core-java/src/test/java/com/openjiuwen/core/singleagent/skills/SkillUtilTest.java#L19) | ← SkillManager/RemoteSkillUtil, BaseAgent | active |
| 远程技能同步 | 从 GitHub 下载技能、路径安全校验 | [registerRemoteSkills](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillUtil.java#L127) | [RemoteSkillUtil.java](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/RemoteSkillUtil.java#L34) | [SecurityTest](file:///D:/jiuwen/main/agent-core-java/src/test/java/com/openjiuwen/core/singleagent/skills/RemoteSkillUtilSecurityTest.java#L16) | GitHubTree, skillsDir | active |
| 技能工具 | agent 读取 SKILL.md / 列技能，overlay 回退 | list_skill / skill_tool | [SkillTool.java](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/SkillTool.java#L23), [ListSkillTool.java](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/ListSkillTool.java#L24) | 经 rail 测试 | ← OverlaySkillManager | active |
| 租户覆盖与热重载 | 租户覆盖公共、override 标记、增量热重载 | [overrideSkill](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/OverlaySkillManager.java#L165) | [OverlaySkillManager.java](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/OverlaySkillManager.java#L29) | [OverlayTest](file:///D:/jiuwen/main/agent-core-java/src/test/java/com/openjiuwen/harness/tools/OverlaySkillManagerTest.java#L22), [HotReloadTest](file:///D:/jiuwen/main/agent-core-java/src/test/java/com/openjiuwen/harness/tools/OverlaySkillManagerHotReloadTest.java#L24), [TenantIsolationTest](file:///D:/jiuwen/main/agent-core-java/src/test/java/com/openjiuwen/core/multitenant/TenantSkillIsolationTest.java#L33) | ← SkillManager×2, TenantContext | active |
| 技能 Rail 集成与演进 | 工具注册/签名热重载/prompt 注入；演进提议 | [SkillUseRail.init](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/SkillUseRail.java#L174) | [SkillUseRail.java](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/SkillUseRail.java#L48), [SkillCreateRail.java](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/SkillCreateRail.java#L21), [TeamSkillRail.java](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/TeamSkillRail.java#L22), [TeamSkillCreateRail.java](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/TeamSkillCreateRail.java#L19) | [RailHotReloadTest](file:///D:/jiuwen/main/agent-core-java/src/test/java/com/openjiuwen/harness/rails/SkillUseRailHotReloadTest.java#L29), [RailTenantIsolationTest](file:///D:/jiuwen/main/agent-core-java/src/test/java/com/openjiuwen/harness/rails/SkillUseRailTenantIsolationTest.java#L28) | ← DeepAgent, OverlaySkillManager | active |
| 技能创建与评估 | LLM 智能生成技能；LLM 评估技能 | [SkillCreator.generate](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/skill_creator/SkillCreator.java#L181) | [SkillCreator.java](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/skill_creator/SkillCreator.java#L44), [SkillEvaluator.java](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/skill_evaluator/SkillEvaluator.java#L37) | [CreatorSecurityTest](file:///D:/jiuwen/main/agent-core-java/src/test/java/com/openjiuwen/dev_tools/skill_creator/SkillCreatorSecurityTest.java#L17), [EvaluatorCompatTest](file:///D:/jiuwen/main/agent-core-java/src/test/java/com/openjiuwen/dev_tools/skill_evaluator/SkillEvaluatorCompatibilityTest.java#L19) | ← ReActAgent, fs/shell/code | active |

## 三、文档导航

| 文档 | 内容简介 |
|------|---------|
| [skill-model-registry.md](./skill-model-registry.md) | Skill 元数据 + SkillManager 注册表/发现/增量/安全 |
| [skill-prompt-facade.md](./skill-prompt-facade.md) | SkillUtil 高层封装 + 提示词生成 + 路径泄露防护 |
| [remote-skill-sync.md](./remote-skill-sync.md) | RemoteSkillUtil GitHub 下载 + 路径安全 |
| [skill-tools.md](./skill-tools.md) | SkillTool/ListSkillTool agent 读取与列技能 |
| [overlay-hot-reload.md](./overlay-hot-reload.md) | OverlaySkillManager 租户覆盖/override/热重载 |
| [skill-rails-evolution.md](./skill-rails-evolution.md) | SkillUseRail 等工作流集成与演进提议 |
| [skill-dev-tools.md](./skill-dev-tools.md) | SkillCreator/SkillEvaluator 生成与评估 |

## 四、调用示例

最小可用路径（先挂系统工具，再注册本地技能）见 [SkillUseExample.java](file:///D:/jiuwen/main/agent-core-java/examples/skill_use/SkillUseExample.java)。热重载见 [skill_hot_reload 示例](file:///D:/jiuwen/main/agent-core-java/examples/skill_hot_reload)。远程同步见 [skill_create 示例](file:///D:/jiuwen/main/agent-core-java/examples/skill_create)。

## 五、能力边界

- `SkillManager` 只提取 `description:`，不解析完整 skill manifest
- `SkillUtil` 不自动挂 `readFile`/`executeCode`/`executeCmd` 工具
- `registerRemoteSkills` 仅下载，不等于运行时注册
- 本地扫描认 `Skill.md`/`SKILL.md`；远程 GitHub 搜索只认 `SKILL.md`
