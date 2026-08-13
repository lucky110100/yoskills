# 技能创建与评估

> 交叉引用: [README](./README.md) | [06 Agent 演进](../../06-agentevolving-and-autoharness-module.md)

## 一、能力概述

`SkillCreator` 与 `SkillEvaluator` 是 skills 体系的开发工具：前者用 ReActAgent + LLM 智能生成技能（读环境变量配置 agent、注册 fs 工具与技能目录，按需求生成技能文件到受限输出目录）；后者用 LLM + 内置评估技能评估目标技能（构建评估 ReActAgent、注册 fs/shell/code 工具与子 agent 工具，生成评估查询并写报告）。两者都把输出路径限制在受信根内，做 symlink/越界检测。

## 二、关键类与函数

### SkillCreator — LLM 生成技能

| 项 | 位置 | 说明 |
|----|------|------|
| 类声明 | [SkillCreator.java](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/skill_creator/SkillCreator.java#L44) | `public class SkillCreator` |
| agent / allowedOutputRoot | [L45](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/skill_creator/SkillCreator.java#L45) / [L46](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/skill_creator/SkillCreator.java#L46) | 内置 agent/受信输出根 |
| 构造器 | [L63](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/skill_creator/SkillCreator.java#L63) | 受信任根目录构造器 |
| createAgent | [L88](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/skill_creator/SkillCreator.java#L88) | 异步构建 ReActAgent、系统 prompt、SysOperation、fs 工具与技能注册 |
| generate(req,outputPath) | [L181](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/skill_creator/SkillCreator.java#L181) | 调用 agent 生成技能到安全输出目录 |
| resolveSafeOutputDirectory | [L198](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/skill_creator/SkillCreator.java#L198) | 安全校验输出路径（symlink/越界） |
| generate(req,Path) | [L243](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/skill_creator/SkillCreator.java#L243) | Path 重载 |
| resolveDefaultSkillsDir | [L279](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/skill_creator/SkillCreator.java#L279) | 从候选目录解析默认 skills 目录 |
| addSysOpTool | [L304](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/skill_creator/SkillCreator.java#L304) | 注册 SysOp 工具到 agent |

### SkillEvaluator — LLM 评估技能

| 项 | 位置 | 说明 |
|----|------|------|
| 类声明 | [SkillEvaluator.java](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/skill_evaluator/SkillEvaluator.java#L37) | `public class SkillEvaluator` |
| DEFAULT_OUTPUT_DIR / 会话 ID 常量 | [L38](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/skill_evaluator/SkillEvaluator.java#L38) / [L39](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/skill_evaluator/SkillEvaluator.java#L39) / [L40](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/skill_evaluator/SkillEvaluator.java#L40) | 默认输出/会话 ID |
| agent / config / tools / skillsDir / targetSkillsRoot / outputDir | [L42](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/skill_evaluator/SkillEvaluator.java#L42)–[L53](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/skill_evaluator/SkillEvaluator.java#L53) | 评估 agent 与路径 |
| createAgent | [L61](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/skill_evaluator/SkillEvaluator.java#L61) | 异步创建评估 agent、注册工具与 subagent 工具 |
| evaluate(String…) / evaluate(Path…) | [L116](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/skill_evaluator/SkillEvaluator.java#L116) / [L139](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/skill_evaluator/SkillEvaluator.java#L139) | 执行评估 |
| buildEvaluationQuery | [L173](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/skill_evaluator/SkillEvaluator.java#L173) | 拼装评估查询字符串 |
| resolveReportDir / resolveDefaultSkillsDir | [L183](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/skill_evaluator/SkillEvaluator.java#L183) / [L190](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/skill_evaluator/SkillEvaluator.java#L190) | 解析报告目录/内置评估 skills |
| copyConfig | [L203](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/skill_evaluator/SkillEvaluator.java#L203) | 深拷贝 agent 配置（subagent 用） |
| resolveTargetSkillPath | [L251](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/skill_evaluator/SkillEvaluator.java#L251) | 安全解析被评估技能路径 |
| createSubagentTool | [L364](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/skill_evaluator/SkillEvaluator.java#L364) | 构造 create_subagent 工具 |
| extractOutput | [L428](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/skill_evaluator/SkillEvaluator.java#L428) | 从 agent 返回结构提取文本 |

## 三、实现机制

1. **agent 驱动**：两者都用 ReActAgent + LLM 完成创造性工作（生成/评估），框架只提供工具与受信边界
2. **工具集**：SkillCreator 注册 fs 工具；SkillEvaluator 注册 fs/shell/code + subagent 工具（subagent 聚焦子任务评估）
3. **输出安全**：`resolveSafeOutputDirectory`/`resolveTargetSkillPath` 把输出限制在受信根内，拒绝对路径/`..`/symlink 越界
4. **评估闭环**：SkillEvaluator 用内置评估 skill（skill_evaluation/SKILL.md）评估目标 skill，输出报告到 `outputs/evaluations`

## 四、测试覆盖

| 测试 | 行 | 覆盖 |
|------|----|------|
| [SkillCreatorSecurityTest](file:///D:/jiuwen/main/agent-core-java/src/test/java/com/openjiuwen/dev_tools/skill_creator/SkillCreatorSecurityTest.java#L17) | L17 | 输出路径限于 allowedRoot 内、拒绝 `../outside` 与绝对外部路径、拒绝 symlink 逃逸 |
| [SkillEvaluatorCompatibilityTest](file:///D:/jiuwen/main/agent-core-java/src/test/java/com/openjiuwen/dev_tools/skill_evaluator/SkillEvaluatorCompatibilityTest.java#L19) | L19 | 查询构建、报告目录回退、默认 skills 目录解析、配置深拷贝、目标技能路径安全 |

## 五、小结

- 生成与评估是 skills 体系的「供给侧」与「质控侧」，闭环技能生命周期
- 框架只提供受信边界与工具，创造性判断交给 LLM
- 输出路径安全与 RemoteSkillUtil/SkillManager 的路径安全一脉相承
