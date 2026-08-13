# 代码规范 — agent-core-java 质量评估

> 组: B 代码质量 | 分: **2/4** | 否决项: 否 | 评估卡: [dims/code-style.md](file:///D:/jiuwen/main/yoskills/common/project-analysis/dims/code-style.md)

## 评分锚点依据

命中 2 档「有格式工具但常被绕过 + 命名部分不一致 + 存在长函数」。项目无 `.editorconfig`/`checkstyle.xml`/`spotbugs` 等自动化格式配置（Glob 三次返回 No file found），但存在成文的 [coding-standard.md](file:///D:/jiuwen/main/agent-core-java/.claude/rules/coding-standard.md#L3)（"124 base rules (G.*) + extended rules (X.*)"）与 `/coding-standard` skill 作为规范基线信号——可视为"有格式工具但无 CI 门禁拦截"，即"常被绕过"。命名整体一致（PascalCase 类、camelCase 方法、ALL_UPPER 常量），但跨文件重复常量属"命名部分不一致"。长文件存在：[RunnerImpl.java](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/runner/RunnerImpl.java#L600) 到 600 行仍追加新方法。

## 评估过程（信号命中 + 工具实测）

- **信号命中**：无自动化格式配置 ✅、命名部分不一致（重复常量）✅、长文件 ✅、Javadoc 同义反复 ✅
- **Glob**：`.editorconfig`/`checkstyle.xml`/`spotbugs.xml` → No file found
- **Read**：[coding-standard.md](file:///D:/jiuwen/main/agent-core-java/.claude/rules/coding-standard.md#L3) 确认有 124 G.* 规则基线（规范文档存在但无强制执行）
- **Grep/Read**：跨文件重复常量实测命中

## 关键问题（带证据）

1. **重复常量散布多处，违反 DRY 与 G.DCL.05**：`MAX_INDEX_LINES = 200` 在 [CodingMemoryToolOps.java:28](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/lite/CodingMemoryToolOps.java#L28)、[CodingMemoryRail.java:34](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/CodingMemoryRail.java#L34)、MemoryIndexManager.java:29 三处重复；`TEAM_MEMORY_MAX_READ_LINES = 200` 在 [TeamMemoryExtractor.java:72](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/team/TeamMemoryExtractor.java#L72) 与 [SharedMemoryManager.java:38](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/team/SharedMemoryManager.java#L38) 两处重复且 Javadoc 一字不差；`DEFAULT_MAX_LOOP_NUMBER = 1000` 在 ArrayCondition.java:22 与 ArrayConditionInSession.java:22 两处重复。
2. **Javadoc 只写 what 不写 why，参数同义反复**（违反 G.CMT.01/03）：[CodingMemoryToolOps.java:23-28](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/lite/CodingMemoryToolOps.java#L23-L28) 注释仅 "MAX_INDEX_LINES."；[CodingMemoryToolOps.java:38-45](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/lite/CodingMemoryToolOps.java#L38-L45) `@param path path`、`@param workspace workspace` 同义反复；[Constant.java:27-32](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/common/constants/Constant.java#L27-L32) 同样。
3. **长文件热点**：[RunnerImpl.java:600-634](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/runner/RunnerImpl.java#L600-L634) 到 600 行仍在追加 runAgentStreaming/runAgentGroup 方法。

## 改进建议

1. 引入 `checkstyle.xml`（可直接对齐已存在的 G.* 规则集）并接入 Maven `checkstyle:check` CI 门禁
2. 补 `.editorconfig`（UTF-8、4 空格、120 列，与 G.FMT.01/08/10 一致）
3. 将 `MAX_INDEX_LINES`、`TEAM_MEMORY_MAX_READ_LINES` 等跨文件重复常量上提到 `core/memory/MemoryLimits.java` 单一常量类
4. Javadoc 参数注释改为描述语义而非复读变量名

## 业界对标

- Java 标杆：看 mall 的格式/lint 配置、Spring Boot 的 checkstyle 严格度、RuoYi-Vue-Plus 命名约定
- 差距：标杆项目有 checkstyle CI 门禁（提交即拦），本项目仅文档基线无门禁
