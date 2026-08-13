# 远程技能同步

> 交叉引用: [README](./README.md) | [SkillUtil 封装](./skill-prompt-facade.md)

## 一、能力概述

`RemoteSkillUtil` 是「远程分发层」，负责从 GitHub 仓库下载远程技能目录并写入本地 skills 目录。通过 GitHub Trees API 递归列出文件，识别含 `SKILL.md` 的目录为技能，并提供严格路径安全校验（拒绝绝对路径、`..` 逃逸、符号链接越界）。它不把 skill 写进 `SkillManager`——下载完后仍需 `registerSkill` 才能让 Agent 看见。

## 二、关键类与函数

| 项 | 位置 | 说明 |
|----|------|------|
| 类声明 | [RemoteSkillUtil.java](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/RemoteSkillUtil.java#L34) | `public class RemoteSkillUtil` |
| MAPPER / GITHUB_API / SKILL_FILE_NAME | [L35](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/RemoteSkillUtil.java#L35) / [L36](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/RemoteSkillUtil.java#L36) / [L37](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/RemoteSkillUtil.java#L37) | Jackson/API 基址/技能文件名 |
| 构造器 | [L47](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/RemoteSkillUtil.java#L47) | 构造 |
| downloadFileFromGitHub | [L80](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/RemoteSkillUtil.java#L80) | 通过 Contents API 下载单文件原始字节 |
| uploadSkillFromGitHub | [L115](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/RemoteSkillUtil.java#L115) | 搜索+下载+安全写入，返回技能目录路径列表 |
| resolveSafeTarget | [L141](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/RemoteSkillUtil.java#L141) | 校验远程相对路径并返回安全写入目标 |
| searchGitHubForSkills | [L199](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/RemoteSkillUtil.java#L199) | 在 GitHub 树中识别含 SKILL.md 的技能目录 |
| listGitHubFiles | [L249](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/RemoteSkillUtil.java#L249) | 列出 GitHub 树全部文件 |
| recursivelyListGitHubFiles | [L264](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/RemoteSkillUtil.java#L264) | 递归遍历子树列出 blob |
| readGitHubJson | [L319](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/RemoteSkillUtil.java#L319) | 调用 GitHub API 并解析 JSON |
| normalizeDirectory | [L379](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/RemoteSkillUtil.java#L379) | 规范化目录字符串 |
| GitHubBlob / SkillFile / SearchResult | [L398](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/RemoteSkillUtil.java#L398) / [L406](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/RemoteSkillUtil.java#L406) / [L414](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/RemoteSkillUtil.java#L414) | 嵌套 record 类型 |

## 三、实现机制

1. **GitHubTree 四元组**：`repoOwner`/`repoName`/`treeRef`/`directory` 描述远程技能位置
2. **搜索**：`searchGitHubForSkills` 在远程目录里找含 `SKILL.md` 的子目录（注意：远程只认 `SKILL.md`，本地还认 `Skill.md`）
3. **下载**：`uploadSkillFromGitHub` → `recursivelyListGitHubFiles` 列 blob → `downloadFileFromGitHub` 逐文件下载 → `resolveSafeTarget` 校验后写入本地 `skillsDir`
4. **安全**：`resolveSafeTarget` 拒绝绝对路径、`..` 逃逸、符号链接越界（含目录符号链接与文件符号链接），写入目标必须真实位于 baseDir 内
5. **职责边界**：远程层只下载不注册，运行时注册仍靠 `SkillManager`

## 四、测试覆盖

| 测试 | 行 | 覆盖 |
|------|----|------|
| [RemoteSkillUtilSecurityTest](file:///D:/jiuwen/main/agent-core-java/src/test/java/com/openjiuwen/core/singleagent/skills/RemoteSkillUtilSecurityTest.java#L16) | L16 | 嵌套相对路径可解析、绝对路径/`..` 被拒、符号链接越界被拒 |

## 五、小结

- 远程=下载层，本地=加载层，两层分离
- 远程只认 `SKILL.md`，本地额外认 `Skill.md`，存在细微差异
- 路径安全校验与 `SkillManager.resolveSafeSkillPath` 一脉相承
