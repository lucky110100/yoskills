# 架构约束 — agent-core-java 质量评估

> 组: B 代码质量 | 分: **3/4** | 否决项: 否 | 评估卡: [dims/arch-rules.md](file:///D:/jiuwen/main/yoskills/common/project-analysis/dims/arch-rules.md)

## 评分锚点依据

命中 3 档「分层清晰 + 无循环依赖 + 无架构约束测试 + 偶有领域耦合框架」。[architecture.md](file:///D:/jiuwen/main/agent-core-java/.claude/rules/architecture.md#L40-L53) 以模块边界表显式定义 core.singleagent / harness / agentteams / core.workflow / core.runner / core.sysop / core.memory / core.retrieval / autoharness / agentevolving / spi / extensions 各包职责，且 extensions 明确"Must not create circular deps with core"。无架构约束测试：Grep `ArchUnit|@ArchTest` 全仓 No matches found。无证据表明领域层耦合 Spring/MyBatis（本项目是纯 Java 框架，core 包未出现框架注解）。

## 评估过程

- **信号命中**：无架构约束测试 ✅、潜在上帝类 ✅；跨层调用/循环依赖/领域耦合框架 未命中
- **Read**：[architecture.md:40-53](file:///D:/jiuwen/main/agent-core-java/.claude/rules/architecture.md#L40-L53) 模块边界表
- **Grep**：`ArchUnit|com.tngtech.archunit|@ArchTest` → No matches found
- **Read**：RunnerImpl 聚合多职责

## 关键问题（带证据）

1. **无架构约束测试**（反模式"有分层但无约束测试，演化后必然腐化"）：[architecture.md:55-57](file:///D:/jiuwen/main/agent-core-java/.claude/rules/architecture.md#L55-L57) 仅以自然语言约束"Before changing a module, inspect the touched class… Do not refactor unrelated areas opportunistically"，无 ArchUnit 自动化断言。
2. **RunnerImpl 上帝类倾向**（职责过多）：[RunnerImpl.java:63-79](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/runner/RunnerImpl.java#L63-L79) 单类聚合 runnerId、ResourceMgr、LocalMessageQueue、CallbackFramework、TeamRuntimeManager、distributeMessageQueue、TenantWorkspaceResolver 等多职责；[RunnerImpl.java:600-634](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/runner/RunnerImpl.java#L600-L634) 到 600 行仍追加方法。虽 architecture.md 定义为"Singleton runtime facade"（门面模式可接受），但体量与职责跨度已达上帝类边缘。

## 改进建议

1. 引入 ArchUnit 测试，至少断言"extensions 不得反向依赖 core 之外""harness 不得被 core.singleagent 依赖"
2. 对 RunnerImpl 按职责拆分（如 TenantBindingRunner、StreamingRunner 委托），文件体量压到 500 行内
3. CI 加 `dependency:analyze` 检测未声明依赖与循环引用

## 业界对标

- Java 标杆：看 Spring Boot 的 ArchUnit 架构约束测试、mall/eladmin 的 service 分层与目录
- 差距：标杆有架构约束测试固化分层，本项目分层清晰但仅文档约束无测试
