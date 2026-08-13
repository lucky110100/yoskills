# 安全性（否决项）— agent-core-java 质量评估

> 组: E 外部质量 | 分: **3/4** | 否决项: **已规避（非 0）** | 评估卡: [dims/security.md](file:///D:/jiuwen/main/yoskills/common/project-analysis/dims/security.md)

## 评分锚点依据

命中 3 档「鉴权完整 + 无硬编码 + 依赖偶有低危 CVE + 基本输入校验」；未达 4 档因缺「安全扫描 CI 门禁」与「日志脱敏中间件」。**未触发 0 档否决项**（无硬编码密钥、无已知高危 CVE）。

## 评估过程

- **信号命中**：无鉴权/越权 ❌（有 Guardrail/Permission）、SQL 注入风险 ✅、无输入校验 ❌（部分有）、日志含敏感信息 ✅（部分）、无 CI 安全扫描 ✅
- **Grep**：`password\s*=|token\s*=|key\s*=` 字面量 → 密钥用 System.getenv 而非硬编码
- **Read**：[SqlDbStore.java:460-464](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/manage/mem_model/SqlDbStore.java#L460-L464) SQL 拼接（已行号实测）
- **Read**：[.gitignore](file:///D:/jiuwen/main/agent-core-java/.gitignore) 未含 .env
- **Grep**：`dependency-check|snyk|trivy` 在 pom.xml 无命中

## 关键问题（带证据）

1. **SQL 字符串拼接存在注入隐患（已行号实测）**：[SqlDbStore.java:460-464](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/manage/mem_model/SqlDbStore.java#L460-L464) 直接把 `tableName` 拼进 `"DROP TABLE IF EXISTS " + tableName` 并用 `Statement.execute(sql)`，未调用 [SqlMigrator.java:70-74](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/migration/migrator/SqlMigrator.java#L70-L74) 的 SUPPORTED_TABLES 白名单；[TeamDatabase.java:610](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/tools/database/TeamDatabase.java#L610) 与 [L478-L500](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/tools/database/TeamDatabase.java#L478-L500) 也有 `%s`/拼接拼表名。当前调用方多来自 `MemoryUtils.generateTenantAwareIdxName` 生成值，属潜在风险而非活跃漏洞，但破坏纵深防御。
2. **.gitignore 未排除 .env**：[.gitignore](file:///D:/jiuwen/main/agent-core-java/.gitignore) 仅忽略 `target/`、`logs/`、`.idea/` 等，未含 `.env`，与 [java-security.md:24-28](file:///D:/jiuwen/main/agent-core-java/.claude/rules/java-security.md#L24-L28) 声称".env 已 gitignored"不一致，存在凭证误提交风险。
3. **GitCode token 走 URL 查询参数**：[GitOperations.java:333-334](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/autoharness/infra/GitOperations.java#L333-L334) 用 `+ "/pulls?access_token=" + encode(token)`，token 可能落入访问日志/反代日志。
4. **无 CI 安全扫描门禁**：仓库无 .github/.gitlab-ci/Jenkinsfile；[pom.xml](file:///D:/jiuwen/main/agent-core-java/pom.xml) 无 `dependency-check`/`snyk`/`trivy` 插件，与 java-security.md「Check for known CVEs」要求脱节。

## 改进建议

1. 为 SqlDbStore.deleteTable / TeamDatabase 动态表名加白名单校验或参数化（参照 SqlMigrator.validateTable）
2. .gitignore 显式追加 `.env`、`.env.*`
3. GitCode token 改走 `Authorization: Bearer` 头
4. 引入 OWASP dependency-check Maven 插件并在 CI 设门禁
5. 增加日志脱敏 Layout（logback PatternDecoder）对 apiKey/token 字段打码

## 业界对标

- 标杆：RuoYi-Vue-Plus 的 Sa-Token 鉴权与数据脱敏、Django 的 csrf/security 中间件
- 评价：本项目分层安全模型（Guardrail/Permission/SysOp）+ 密钥用 getenv 是强项；SQL 拼接 + 无 CI 安全扫描是扣分项
