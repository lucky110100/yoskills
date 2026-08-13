# 本次会话读取文件清单与处理说明

> 生成时间：2026-08-07 · 会话主题：工程特性功能分析方法论固化与实战验证

## 一、本次会话读取的全部文件（按用途分类）

### 1. 既有技能 SKILL.md（学习约定与风格）
- D:\jiuwen\main\yoskills\common\code-wiki-author\SKILL.md
- D:\jiuwen\main\yoskills\common\efficient-task-flow\SKILL.md
- D:\jiuwen\main\yoskills\common\jiuwen-skip-analysis\SKILL.md（读取失败，该路径下文件不存在）

### 2. 项目权威文档（三路定位之「文本法」）
- D:\jiuwen\main\agent-core-java\documents\zh\2.开发指南\高阶用法\Agent Skills.md

### 3. 源码行号实测核验（feature-index-builder 强制规则）
- D:\jiuwen\main\agent-core-java\src\main\java\com\openjiuwen\core\singleagent\skills\Skill.java
- D:\jiuwen\main\agent-core-java\src\main\java\com\openjiuwen\core\singleagent\skills\SkillManager.java
- D:\jiuwen\main\agent-core-java\src\main\java\com\openjiuwen\harness\tools\OverlaySkillManager.java
- D:\jiuwen\main\agent-core-java\src\main\java\com\openjiuwen\core\singleagent\skills\SkillUtil.java
- D:\jiuwen\main\agent-core-java\src\main\java\com\openjiuwen\harness\rails\SkillUseRail.java

### 4. 自产文件结构校验
- D:\jiuwen\main\yoskills\common\feature-analysis\SKILL.md
- D:\jiuwen\main\yoskills\common\feature-index-builder\SKILL.md

### 5. 子代理代读（2 个 search 子代理并行深挖，结果回传主会话）
- core 包：Skill / SkillManager / SkillUtil / RemoteSkillUtil + 4 个测试
- harness/rails/devtools 包：SkillTool / ListSkillTool / OverlaySkillManager + 4 个 rail + SkillCreator / SkillEvaluator + 7 个测试

---

## 二、精选 5 个文件的读取详情

### 文件 1：code-wiki-author/SKILL.md
- **路径**：D:\jiuwen\main\yoskills\common\code-wiki-author\SKILL.md
- **处理结果**：提取出既有技能的写作约定——frontmatter 用 `name`+`description`、正文中文、章节用「一二三」序号、含 `00-路标基线 + 增量更新流程 + 提交→文档映射表`、链接用 `[basename](file:///绝对路径#L行号)`、产出检查清单、适用与边界。把这些约定套进我新建的 `feature-analysis` 与 `feature-index-builder` 两个技能。
- **为什么这么处理**：写新技能前必须先摸既有技能的「家规」，否则风格/结构不一致会破坏可读性与可维护性。这对应 `efficient-task-flow` 的「先理解再动手」和 `code-wiki-author` 自身的「先广后深」原则。

### 文件 2：Agent Skills.md
- **路径**：D:\jiuwen\main\agent-core-java\documents\zh\2.开发指南\高阶用法\Agent Skills.md
- **处理结果**：获取 skills 管理功能的权威设计意图——「skill 是元数据层而非执行层」、「远程是下载层 / 本地是加载层」双层模型、`SkillManager` 只提取 `description`、命名取目录名、本地认 `Skill.md`/`SKILL.md` 而远程只认 `SKILL.md` 的细微差异。把这些作为 `features/skills/README.md` 能力概述与能力边界的骨架。
- **为什么这么处理**：这是特性定位三路线中的「文本法」——项目自带文档是设计意图的 ground truth，先读它能在读代码前建立正确心智模型，避免把元数据层误读成执行层。比直接扎进代码省一半返工。

### 文件 3：Skill.java
- **路径**：D:\jiuwen\main\agent-core-java\src\main\java\com\openjiuwen\core\singleagent\skills\Skill.java
- **处理结果**：读取 L19-28，确认 `public class Skill` 在 L21，字段 `name`/`description`/`directory`/`updateAt` 在 L22-26，与子代理回传完全一致。核验通过后，信任子代理对该文件其余行号（`toString`@L35、`toRepr`@L46）。
- **为什么这么处理**：`feature-index-builder` 的执行规则第 3 条「行号实测，不可臆造」——所有要写进索引的行号必须实测。子代理回传的行号虽来自真实读取，但主会话落盘前必须抽样核验，防止子代理偶发错误污染索引，导致点击断链。

### 文件 4：SkillManager.java
- **路径**：D:\jiuwen\main\agent-core-java\src\main\java\com\openjiuwen\core\singleagent\skills\SkillManager.java
- **处理结果**：读取 L90-117，确认 `register(skillPath,sessionId,overwrite)` 在 L93、受信根重载 `register(skillPath,skillsRoot,sid,ow)` 在 L114、`@since 0.1.13` 注释在 L112。核验通过。把 `register`@L93 作为特性索引「技能元数据与注册表」行的「入口」列。
- **为什么这么处理**：这是索引「入口」列的定位依据——入口必须是真实可点击的代码行。同时核验两个 `register` 重载确认了 0.1.13 受信根安全增强的存在，支撑了「受信根安全校验」这条实现机制的描述。

### 文件 5：OverlaySkillManager.java
- **路径**：D:\jiuwen\main\agent-core-java\src\main\java\com\openjiuwen\harness\tools\OverlaySkillManager.java
- **处理结果**：读取 L28-41，确认 `public class OverlaySkillManager` 在 L29、双层 `SkillManager` 字段在 L30-31、`overlayDir`/`workspaceResolver` 在 L32-33、`tenantSkillManagerCache`（ConcurrentHashMap）在 L36、构造器在 L38。核验通过。
- **为什么这么处理**：`OverlaySkillManager` 是 skills 体系最复杂的子特性（租户覆盖 + 热重载 + override 标记），它的行号是 `overlay-hot-reload.md` 整篇文档的骨架。核验它等于核验整篇最复杂文档的可信度。`ConcurrentHashMap` 缓存字段还印证了「避免并发互相污染」的实现机制描述。

---

## 三、处理逻辑小结

本次读取遵循三条原则：
1. **写前先读既有约定**（家规优先）——对应 `efficient-task-flow` 的「先理解再动手」
2. **分析前先读权威文档**（设计意图优先于代码）——对应 `feature-analysis` 的「文本法定位」
3. **落盘前实测行号**（证据先于断言）——对应 `feature-index-builder` 的「行号实测」

三条原则分别落在精选 5 个文件中的第 1、2、3-5 个，形成「学约定 → 懂意图 → 验行号」的完整处理链。
