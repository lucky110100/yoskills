# 技能工具

> 交叉引用: [README](./README.md) | [Overlay 覆盖](./overlay-hot-reload.md) | [Rail 集成](./skill-rails-evolution.md)

## 一、能力概述

`SkillTool` 与 `ListSkillTool` 是 agent 在运行时可调用的两个技能工具：`skill_tool` 读取指定技能的 `SKILL.md` 或相对文件，`list_skill` 列出可见技能名。两者都优先从租户 overlay 层解析，回退到租户 workspace 根，再回退到公共 skillsRoot，体现「租户优先、公共兜底」的覆盖语义。

## 二、关键类与函数

### SkillTool — 读取技能文件

| 项 | 位置 | 说明 |
|----|------|------|
| 类声明 | [SkillTool.java](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/SkillTool.java#L23) | `public class SkillTool` |
| skillsRoot / workspaceResolver / overlaySkillManager | [L24](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/SkillTool.java#L24) / [L25](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/SkillTool.java#L25) / [L26](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/SkillTool.java#L26) | 公共根/租户解析器/overlay |
| 构造器 | [L36](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/SkillTool.java#L36) | 规范化根路径并注入 overlay |
| readSkill | [L51](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/SkillTool.java#L51) | 入口：先查 overlay，再回退租户/公共根 |
| readTenantSkill | [L69](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/SkillTool.java#L69) | 无 overlay 时按 TenantContext 解析租户文件 |
| readSkillFile | [L88](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/SkillTool.java#L88) | 实际读取文件并封装为 ToolOutput |

### ListSkillTool — 列出技能

| 项 | 位置 | 说明 |
|----|------|------|
| 类声明 | [ListSkillTool.java](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/ListSkillTool.java#L24) | `public class ListSkillTool` |
| skillsRoot / workspaceResolver / overlaySkillManager | [L25](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/ListSkillTool.java#L25) / [L26](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/ListSkillTool.java#L26) / [L27](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/ListSkillTool.java#L27) | 三层依赖 |
| 构造器 | [L37](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/ListSkillTool.java#L37) | 全参构造器 |
| listSkills | [L50](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/ListSkillTool.java#L50) | 返回可见技能名列表（走 overlay 或默认合并） |
| collectDefaultSkills | [L60](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/ListSkillTool.java#L60) | 无 overlay 时合并公共与租户目录名去重排序 |
| listDirectoryNames | [L81](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/ListSkillTool.java#L81) | 列出指定根下子目录名 |

## 三、实现机制

1. **覆盖优先**：`readSkill` 先 `OverlaySkillManager.resolveSkillFile`，命中则返回租户副本
2. **回退链**：overlay 未命中 → `readTenantSkill` 按租户 workspace 解析 → 公共 skillsRoot
3. **可见列表**：有 overlay 时委托 `getAllVisibleSkillNames`；否则合并公共根与租户根目录名，去重排序
4. **工具注册**：由 `SkillUseRail.init` 把这两个工具注册给 DeepAgent

## 四、测试覆盖

经 [SkillUseRail 租户隔离测试](file:///D:/jiuwen/main/agent-core-java/src/test/java/com/openjiuwen/harness/rails/SkillUseRailTenantIsolationTest.java#L28) 与 [OverlaySkillManagerTest](file:///D:/jiuwen/main/agent-core-java/src/test/java/com/openjiuwen/harness/tools/OverlaySkillManagerTest.java#L22) 间接覆盖（resolveSkillFile / 可见列表语义）。

## 五、小结

- 两个工具是 agent 运行时「看见」技能的入口
- 三层回退（overlay→租户→公共）保证租户私有与公共共享的统一视图
- 工具本身无状态，状态由 OverlaySkillManager/SkillManager 维护
