# 项目健康评估报告 — agent-core-java

> 由 `project-analysis` 诊断模式产出（全项目深度 + 浅对标 + mvn 动态验证）。所有评分对照 `dims/*.md` 锚点，证据用 `[basename](file:///绝对路径#L行号)`，行号均经 Read 实测。

## 一、项目概况与基线

- 项目名 / 路径: agent-core-java / `D:\jiuwen\main\agent-core-java`
- 技术栈 / 类型: Java 17 / Maven 单模块 / Agent 框架（单智能体·多智能体·工作流·记忆·检索·会话·工具·MCP·技能）
- 规模: 200+ 源文件，100+ 测试文件；包 `com.openjiuwen.{core, agentteams, autoharness, dev_tools, harness, spi, extensions, agentevolving}`
- 基线提交: `695089224478c4cd1670340f56d64ecb8de4c5b7`（tag `v0.1.14`，分支 `730`）
- 评估时间: 2026-08-08
- 评估模式: 诊断模式（13 质量维度全评 + 浅对标 + mvn compile 动态验证 + 3 处关键行号抽查）

> **分维度详细文档**：每个质量维度的详细评估（锚点依据+评估过程+关键问题+改进建议+对标）见 `quality/` 目录下 13 个分维度文档（[01-code-style](./quality/01-code-style.md) 至 [13-dependency-health](./quality/13-dependency-health.md)），索引见 [quality/README.md](./quality/README.md)。本主报告为汇总。
## 二、评分卡

### 2.1 维度得分

| 组 | 维度 | 分(0-4) | 关键证据 |
|----|------|---------|---------|
| A 功能 | 功能特性 | 3 | 功能域完整(core/agentteams/workflow/memory/retrieval/harness)；有 skills 域索引；全项目功能索引待补 |
| B 代码质量 | 代码规范 | 2 | 无 checkstyle/.editorconfig 自动门禁，仅 [coding-standard.md](file:///D:/jiuwen/main/agent-core-java/.claude/rules/coding-standard.md) 文档基线；重复常量散布 |
| B 代码质量 | 架构约束 | 3 | [architecture.md](file:///D:/jiuwen/main/agent-core-java/.claude/rules/architecture.md) 分层清晰无循环依赖；无 ArchUnit；[RunnerImpl.java](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/runner/RunnerImpl.java#L600) 偏上帝类 |
| B 代码质量 | 复用性 | 3 | [spi/KVStoreFactory](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/spi/store/KVStoreFactory.java#L25) ServiceLoader 可插拔；偶有常量 copy-paste |
| B 代码质量 | 可测试性 | 3 | 100+ 测试、@Tag 分层、Mockito、[jacoco 已配](file:///D:/jiuwen/main/agent-core-java/pom.xml#L432)；无覆盖率阈值门禁 |
| C 运行时 | 性能 | 2 | [GraphMemory.java:856-895](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/graph/graph_memory/GraphMemory.java#L856-L895) 循环内查库 N+1；无 JMH/压测基线；无缓存策略 |
| C 运行时 | 可靠性 | 3 | [ModelCircuitBreaker.java:89-97](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/foundation/llm/ModelCircuitBreaker.java#L89-L97) 熔断+重试+分布式锁幂等+背压；27 处 catch ignored 吞异常 |
| C 运行时 | 可观测性 | 3 | [logback.xml](file:///D:/jiuwen/main/agent-core-java/src/main/resources/logback.xml) 结构化日志+trace_id；[OtelRail](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/extensions/tracerotel/OtelRail.java#L79) OTel 全链路追踪；缺 actuator/RED 指标/健康端点 |
| D 演进 | 可扩展性 | 4 | 9 个 SPI 扩展点([KVStoreProvider](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/spi/store/KVStoreProvider.java#L22) 等)；103 interface；[扩展文档](file:///D:/jiuwen/main/agent-core-java/documents/zh/2.开发指南/高阶用法/开发自定义组件.md) |
| D 演进 | 文档完备度 | 3 | 双语 README+1000+ API 文档树+10 个 .claude/rules+[AGENTS.md](file:///D:/jiuwen/main/agent-core-java/AGENTS.md)；缺 ADR；[SUMMARY.md](file:///D:/jiuwen/main/agent-core-java/documents/zh/SUMMARY.md) sysop 段重复 3 次 |
| D 演进 | 构建与CI | 2 | [pom.xml](file:///D:/jiuwen/main/agent-core-java/pom.xml#L386) 规范+jacoco+surefire；**无任何 CI**(.github/workflows 不存在)；无 Dockerfile；无发布/回滚 |
| E 外部 | 安全性 | 3 | 无硬编码密钥(System.getenv)+Guardrail/Permission 模型+[java-security.md](file:///D:/jiuwen/main/agent-core-java/.claude/rules/java-security.md)；[SqlDbStore.java:460-464](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/manage/mem_model/SqlDbStore.java#L460-L464) SQL 拼接隐患；.gitignore 未排除 .env；无 CI 安全扫描 |
| E 外部 | 易用性 | 3 | 47 个 examples+200+ API markdown；无 OpenAPI；[HarnessCli](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/cli/HarnessCli.java#L21) 无 --help；README 版本 0.1.12 vs pom 0.1.14 |
| E 外部 | 依赖健康度 | 3 | [pom.xml:73-182](file:///D:/jiuwen/main/agent-core-java/pom.xml#L73) dependencyManagement+3 BOM 锁版本；无 lockfile/dependency-check；okhttp4.x/reactor3.6/pdfbox2.x 落后 |

### 2.2 加权总分

- 组权重: A 0.15 / B 0.30 / C 0.25 / D 0.20 / E 0.10（组内维度均分）
- 计算: 0.15×3 + 0.30×(2+3+3+3)/4 + 0.25×(2+3+3)/3 + 0.20×(4+3+2)/3 + 0.10×(3+3+3)/3
- = 0.45 + 0.825 + 0.667 + 0.600 + 0.300 = **2.84 ≈ 2.8**
- **🟡 黄灯**（2.0 ≤ 2.8 < 3.0，可维护，需改进）
- 否决项检查: 安全性=3 / 可靠性=3 / 可测试性=3 → **0 否决**

### 2.3 雷达图数据（14 维）

```
功能:3  代码规范:2  架构约束:3  复用性:3  可测试性:3
性能:2  可靠性:3  可观测性:3  可扩展性:4  文档:3
构建CI:2  安全:3  易用:3  依赖:3
```

短板分布：构建与CI(2)、代码规范(2)、性能(2) 三处最低；可扩展性(4) 为唯一卓越项。

## 三、问题清单（按严重度）

### 🔴 严重（影响生产质量保障，P0）

1. **[构建与CI] 完全无 CI/CD** — 无 .github/workflows/Jenkinsfile/.gitlab-ci，[AGENTS.md:228-233](file:///D:/jiuwen/main/agent-core-java/AGENTS.md#L228) 的 Verification Gate 靠人工跑 mvn。→ 问题靠人工发现，反模式命中。
2. **[安全] SQL 拼接注入隐患** — [SqlDbStore.java:460-464](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/manage/mem_model/SqlDbStore.java#L460-L464) `"DROP TABLE IF EXISTS " + tableName` 未白名单/参数化；[TeamDatabase.java:478-500](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/tools/database/TeamDatabase.java#L478) 同类。
3. **[性能] GraphMemory N+1** — [GraphMemory.java:886-887](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/graph/graph_memory/GraphMemory.java#L886-L887) 循环内 `dbBackend.query` 过滤条件不依赖循环变量，等价每次迭代全表扫描后内存匹配。

### 🟡 中等（影响维护效率/纵深防御，P1）

4. **[可靠性] 27 处 catch ignored 吞异常** — [Trainer.java:612-615](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentevolving/trainer/Trainer.java#L612)、[BeamSearch.java:252-254](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentevolving/optimizer/tool_call/utils/BeamSearch.java#L252)、[EventBus.java:197-199](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/agent/coordination/EventBus.java#L197)（InterruptedException 不重新中断）。
5. **[可测试性] 覆盖率无门禁** — [pom.xml:432-453](file:///D:/jiuwen/main/agent-core-java/pom.xml#L432) jacoco 只 prepare-agent+report，无 `check` 目标与阈值；部分 SystemTest 耦真实 Redis/PG 无 testcontainers。
6. **[代码规范/复用性] 跨文件常量 copy-paste** — `MAX_INDEX_LINES=200` 三处（[CodingMemoryToolOps:28](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/lite/CodingMemoryToolOps.java#L28)/CodingMemoryRail:34/MemoryIndexManager:29）；`TEAM_MEMORY_MAX_READ_LINES=200` 两处。
7. **[安全] .gitignore 未排除 .env** — [.gitignore](file:///D:/jiuwen/main/agent-core-java/.gitignore) 仅 target/logs/.idea，与 [java-security.md:24-28](file:///D:/jiuwen/main/agent-core-java/.claude/rules/java-security.md#L24) 声称".env 已 gitignored"不符；GitCode token 走 URL 查询参数 [GitOperations:333](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/infra/GitOperations.java#L333)。
8. **[架构] RunnerImpl 上帝类倾向** — [RunnerImpl.java:63-79](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/runner/RunnerImpl.java#L63) 聚合 7+ 职责，600 行仍追加方法；无 ArchUnit 约束测试。
9. **[文档] 无 ADR + SUMMARY.md 重复** — 关键决策(Pregel 选型/Card-Config 分离)无 ADR；[SUMMARY.md:912-1106](file:///D:/jiuwen/main/agent-core-java/documents/zh/SUMMARY.md#L912) sysop 章节重复 3 次。
10. **[易用性/依赖] README 版本不同步 + 无 lockfile** — [README:42](file:///D:/jiuwen/main/agent-core-java/README.md#L42) 写 0.1.12 vs pom 0.1.14；无 maven-lockfile/dependency-check；[Third_Party_Notice](file:///D:/jiuwen/main/agent-core-java/Third_Party_Open_Source_Software_Notice.txt#L10) 版本对不上。

### 🟢 轻微（可优化，P2）

11. Javadoc 同义反复（`@param path path`）违反 G.CMT.01；部分依赖落后大版本（okhttp4.x/reactor3.6/pdfbox2.x）；CLI 无 --help/补全；配置无启动期校验。

## 四、业界对标摘要（浅对标，benchmarks/java-spring.md）

| 维度 | 本项目 | 标杆 | 差距 |
|------|--------|------|------|
| 可扩展性(4) | 9 SPI 扩展点+ServiceLoader | Spring Boot autoconfigure | 接近标杆，仅配置驱动走 JSON 非注解 |
| 可测试性(3) | jacoco+@Tag 分层 | Spring Boot test 体系 | 缺覆盖率门禁+testcontainers |
| 可观测性(3) | OTel 全链路追踪 | Spring Boot actuator | 缺健康端点/RED 指标/错误聚合 |
| 安全性(3) | Guardrail/Permission 模型 | RuoYi-Vue-Plus Sa-Token | 缺 CI 安全扫描+SQL 参数化+日志脱敏 |
| 构建与CI(2) | 无 CI/无 Dockerfile | mall docker-compose/Spring Boot tools | **最大短板**，无自动化流水线 |

> agent 框架专属对标方向：Java 生态可参考 LangChain4j、Spring AI（建议后续补 `benchmarks/agent-llm.md` 时纳入）。

## 五、改进路线图（按优先级）

| 优先级 | 维度 | 改进项 | 预期收益 | 关联问题 |
|--------|------|--------|---------|---------|
| P0 | 构建与CI | 补 .github/workflows(matrix JDK17/21: lint→test→jacoco:report→deploy)+ Dockerfile 多阶段构建 | 构建2→4 | #1 |
| P0 | 安全 | SqlDbStore/TeamDatabase 表名白名单或参数化(参照 SqlMigrator.validateTable) | 安全3→4 | #2 |
| P0 | 性能 | GraphMemory 循环内 search/query 改批量接口(searchAll/queryByIds)+引 Caffeine 缓存 | 性能2→3 | #3 |
| P1 | 可靠性 | 清理 27 处 catch ignored(至少 LOG.warn 或 Thread.currentThread().interrupt()) | 可靠3→4 | #4 |
| P1 | 可测试性 | jacoco 加 check 目标+覆盖率阈值;SystemTest 引 testcontainers | 可测试3→4 | #5 |
| P1 | 代码规范/复用性 | 引 checkstyle 门禁+提取重复常量到 MemoryLimits/WorkflowLimits | 规范2→3/复用3→4 | #6 |
| P1 | 安全 | .gitignore 加 .env;GitCode token 改 Authorization 头;引 dependency-check CI | 安全3→4 | #7 |
| P2 | 架构 | 引 ArchUnit 测试;RunnerImpl 按职责拆分 | 架构3→4 | #8 |
| P2 | 文档 | 新建 documents/adr/ 补关键决策 ADR;修 SUMMARY.md 重复 | 文档3→4 | #9 |
| P2 | 易用性/依赖 | README 版本同步;补 CLI --help(picocli);引 lockfile+license-maven-plugin | 易用3→4/依赖3→4 | #10 |

> 预计补齐 P0+P1 后总分可由 2.8 升至 ~3.4（绿灯），核心是把"有成文规范/jacoco/测试分层但无 CI 门禁"的闭环补齐。

## 六、固化建议

- 标杆沉淀入 `benchmarks/`: 建议新增 `benchmarks/agent-llm.md`，纳入 LangChain4j / Spring AI 作为 Java agent 框架对标（本项目作 agent 框架，java-spring.md 的 Spring Boot 是框架范本但非 agent 专属）。
- `.trae/rules/project_rules.md` 补充: 记录本项目 lint=mvn checkstyle:check(待引)、typecheck=mvn compile、test=`mvn test -DexcludedGroups=system-test`、build=mvn package、依赖扫描=mvn dependency-check:check(待引)。
- 功能索引补全: 现仅有 skills 域索引（`agent-core-java-docs/features/skills/`），建议用 `feature-index-builder` 补 core 单智能体/workflow/memory/retrieval 等域索引，达全项目功能索引化。
- 下次重评估建议: P0+P1 改进落地后重跑本技能（用 `Schedule` 配每迭代末重评估，发现质量漂移）。

---

## 附：动态验证与证据可信度

- **行号抽查 3 处全部验证通过**（ModelCircuitBreaker:89-97 熔断、GraphMemory:856-895 N+1、SqlDbStore:460-464 SQL 拼接），子代理证据可信。
- **mvn compile**: 已通过（exit code 0，BUILD SUCCESS），构建可复现性获动态佐证。构建与CI 维度 2 分中"构建脚本规范+jacoco+surefire"部分达标，扣分项是无 CI 门禁与容器化(非构建脚本本身问题)。
- 4 个并发子代理各负责一组维度，均读对应 `dims/*.md` 评估卡后用 Grep/Glob/Read 实测，回传带 file:/// 证据的结构化结论。
