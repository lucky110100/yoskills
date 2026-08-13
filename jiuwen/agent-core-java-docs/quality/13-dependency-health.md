# 依赖健康度 — agent-core-java 质量评估

> 组: E 外部质量 | 分: **3/4** | 否决项: 否 | 评估卡: [dims/dependency-health.md](file:///D:/jiuwen/main/yoskills/common/project-analysis/dims/dependency-health.md)

## 评分锚点依据

命中 3 档「版本锁定 + 偶有低危 CVE + 部分过时」；未达 4 档因无 lockfile、无依赖扫描 CI、部分依赖落后一个大版本。

## 评估过程

- **信号命中**：依赖版本不锁定(lockfile) ✅（Maven 无原生 lockfile）、已知 CVE ✅（无已知高危）、依赖过时 ✅、无许可证检查 ✅、循环/孤立依赖 ❌（Maven 单模块规避）
- **Read**：[pom.xml:73-182](file:///D:/jiuwen/main/agent-core-java/pom.xml#L73-L182) dependencyManagement + 3 BOM
- **Grep**：`dependency-check|snyk|trivy|license` 在 pom.xml 0 命中
- **Read**：[pom.xml:27-52](file:///D:/jiuwen/main/agent-core-java/pom.xml#L27-L52) 版本属性
- **Read**：[Third_Party_Open_Source_Software_Notice.txt:10-13](file:///D:/jiuwen/main/agent-core-java/Third_Party_Open_Source_Software_Notice.txt#L10-L13)

## 关键问题（带证据）

1. **无 lockfile 与依赖扫描门禁**：Maven 无原生 lockfile，[pom.xml:73-182](file:///D:/jiuwen/main/agent-core-java/pom.xml#L73-L182) 虽用 `dependencyManagement` + 3 个 BOM（jackson/opentelemetry/kotlin）锁定传递版本，但未配置 maven-lockfile-plugin 或 dependency-check 插件（Grep `dependency-check|snyk|trivy|license` 0 命中），构建可复现性依赖单一 pom，传递依赖漂移仍可能发生。
2. **部分依赖落后大版本**：[pom.xml:27-52](file:///D:/jiuwen/main/agent-core-java/pom.xml#L27-L52) 中 `okhttp3.version=4.12.0`（5.x 已发布）、`reactor.version=3.6.2`（3.7.x 现行）、`pdfbox.version=2.0.37`（3.x 现行，2.0.x 维护分支）；虽无已知高危 CVE，但属"部分过时"。
3. **第三方许可证声明不完整/版本对不上**：[Third_Party_Open_Source_Software_Notice.txt:10-13](file:///D:/jiuwen/main/agent-core-java/Third_Party_Open_Source_Software_Notice.txt#L10-L13) 顶部仅列 "Jackson 2.17.0"，而 [pom.xml:23](file:///D:/jiuwen/main/agent-core-java/pom.xml#L23) 实际为 2.18.8，且未逐项列出 milvus/pulsar/openai-java 等关键依赖许可证；无 license-maven-plugin 自动生成。
4. **无循环依赖信号**：Grep 未发现循环依赖模式（Maven 单模块项目结构本身规避）。

## 改进建议

1. 引入 maven-lockfile-plugin 生成 `pom.xml.lock` 或迁移到 Gradle + lockfile
2. 新增 `org.owasp:dependency-check-maven` 插件并在 CI 设 fail-on CVSS≥7 门禁
3. 用 license-maven-plugin 自动生成完整 Third_Party_Notice 并修正版本号
4. 将 okhttp 升 5.x、reactor 升 3.7.x、pdfbox 评估升 3.x

## 业界对标

- 标杆：Python 的 poetry.lock/pdm.lock + dependabot/renovate 自动化
- 评价：本项目 dependencyManagement + 3 BOM 锁版本 + Apache 2.0 合规是强项；缺 lockfile 与 dependency-check CI 是扣分项
