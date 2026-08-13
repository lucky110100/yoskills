# 技能提示词封装

> 交叉引用: [README](./README.md) | [注册表](./skill-model-registry.md) | [远程同步](./remote-skill-sync.md)

## 一、能力概述

`SkillUtil` 是 skills 的高层封装入口，组合 `SkillManager` 与 `RemoteSkillUtil`，提供本地注册、远程 GitHub 注册、技能存在性判断，以及面向 Agent 的技能提示词生成。核心是 `getSkillPrompt()`——只在技能目录位于本地 FS 根（workspace/cwd/projectRoot）之内时输出相对 `SKILL.md` 路径，否则隐去路径防止绝对路径泄露。

## 二、关键类与函数

| 项 | 位置 | 说明 |
|----|------|------|
| 类声明 | [SkillUtil.java](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillUtil.java#L25) | `public class SkillUtil` |
| SKILL_PROMPT_CONTENT | [L26](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillUtil.java#L26) | 技能提示词模板 |
| skillManager / remoteSkillUtil | [L31](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillUtil.java#L31) / [L32](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillUtil.java#L32) | 组合的两个子管理器 |
| 构造器 | [L40](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillUtil.java#L40) | 初始化两子管理器 |
| setSysOperationId | [L51](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillUtil.java#L51) | 同时下发到两子管理器 |
| registerSkills(path,agent) | [L83](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillUtil.java#L83) | 接收 String/List 注册本地技能 |
| registerSkills(path,root,agent) | [L105](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillUtil.java#L105) | 受信根校验后注册（0.1.13） |
| registerRemoteSkills | [L127](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillUtil.java#L127) | 从 GitHub 注册远程技能 |
| hasSkill | [L137](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillUtil.java#L137) | 是否注册了任何技能 |
| getSkillPrompt | [L152](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillUtil.java#L152) | 生成 Agent 的系统+技能提示词 |
| resolveSkillMdPathForPrompt | [L182](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillUtil.java#L182) | 仅当技能目录位于本地 FS 根内返回相对 SKILL.md 路径（0.1.14） |
| localFsBases | [L208](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillUtil.java#L208) | 收集 workspace/cwd/projectRoot 规范化根 |
| toNormalizedAbsolute | [L245](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillUtil.java#L245) | 绝对化+规范化，优先 toRealPath |
| isWithinBase | [L262](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillUtil.java#L262) | 判断 candidate 是否位于 base 内 |

## 三、实现机制

1. **组合模式**：`SkillUtil` 持有 `SkillManager`（本地加载层）+ `RemoteSkillUtil`（远程下载层），统一对外
2. **prompt 内容**：说明 Agent equipped with skills；列出每个 skill 的名称/描述/目录路径；提示模型优先用 `readFile` 读 `SKILL.md`
3. **注入时机**：`ReActAgent.invoke` 在运行时把 prompt 追加到最后一条 system message；需 system message 存在 + `getSkillUtil() != null` + `hasSkill()` 为真
4. **路径泄露防护**：`resolveSkillMdPathForPrompt` 仅在技能目录位于 workspace/cwd/projectRoot 之内时输出相对路径，否则只给技能名不给 `Skill directory:`，避免绝对路径进提示词

## 四、测试覆盖

| 测试 | 行 | 覆盖 |
|------|----|------|
| [SkillUtilTest](file:///D:/jiuwen/main/agent-core-java/src/test/java/com/openjiuwen/core/singleagent/skills/SkillUtilTest.java#L19) | L19 | 无技能状态、sysop 传递、workspace 内含相对路径、workspace 外隐去路径、GitHubTree 构造/拷贝 |

## 五、小结

- 高层封装：Agent 侧走 `BaseAgent.registerSkill/registerRemoteSkills`，内部委托 `SkillUtil`
- prompt 注入依赖 system message 存在，无 system prompt 时不注入
- 路径泄露防护是 0.1.14 的关键安全增强
