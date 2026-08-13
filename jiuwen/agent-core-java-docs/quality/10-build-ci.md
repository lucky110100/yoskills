# 构建与CI/工程化 — agent-core-java 质量评估

> 组: D 演进质量 | 分: **2/4** | 否决项: 否 | 评估卡: [dims/build-ci.md](file:///D:/jiuwen/main/yoskills/common/project-analysis/dims/build-ci.md)

## 评分锚点依据

命中 2 档「有构建脚本 + 无 CI」。有规范 Maven 构建（pom.xml + dependencyManagement 版本锁定 + jacoco 覆盖率 + surefire 超时与 JDK21 Mockito agent 配置），但无任何 CI 配置（.github/workflows/Jenkinsfile/.gitlab-ci.yml 均不存在）、无 Dockerfile/容器化。examples 下有 systemd+Nginx+HTTPS 部署脚本与更新流程，但属示例级部署参考，非项目自身 CI/CD 流水线。**动态验证：mvn compile 通过（exit 0）**，构建脚本本身规范达标，扣分项是无 CI 门禁与容器化。

## 评估过程

- **信号命中**：无 CI/CD ✅、无环境管理(容器化) ✅、无发布流程 ✅、无回滚机制 ✅；无构建脚本 ❌（pom 规范）
- **Glob**：`.github/workflows/*`、`Jenkinsfile`、`.gitlab-ci.yml`、`azure-pipelines.yml`、`.circleci/config.yml` 全部 No file found
- **Glob**：`**/Dockerfile*` → No file found
- **Read**：[pom.xml:386-455](file:///D:/jiuwen/main/agent-core-java/pom.xml#L386-L455) 四插件配置；[examples/gitcode_issue_evolver/deploy/README-linux.md:128-151](file:///D:/jiuwen/main/agent-core-java/examples/gitcode_issue_evolver/deploy/README-linux.md#L128-L151) systemd+Nginx 部署
- **RunCommand**：`mvn compile` exit 0（构建可复现）

## 关键问题（带证据）

1. **构建自动化质量高但止步于本地**：[pom.xml:386-455](file:///D:/jiuwen/main/agent-core-java/pom.xml#L386-L455) 配置 maven-compiler/surefire/dependency/jacoco 四插件，[L432-L453](file:///D:/jiuwen/main/agent-core-java/pom.xml#L432-L453) jacoco 集成，[L419-L430](file:///D:/jiuwen/main/agent-core-java/pom.xml#L419-L430) surefire 设 `forkedProcessTimeoutInSeconds=900` 防 hang、JDK21 下用 `-javaagent` 加载 Mockito；[L73-L182](file:///D:/jiuwen/main/agent-core-java/pom.xml#L73-L182) dependencyManagement 锁定 jackson-bom/opentelemetry-bom/kotlin-bom。但无 maven-release-plugin、无 deploy/maven-install 分发配置，发布流程缺失。
2. **完全无 CI**：Glob `.github/workflows/*`、`Jenkinsfile`、`.gitlab-ci.yml`、`azure-pipelines.yml`、`.circleci/config.yml` 全部 No file found。[AGENTS.md:228-233](file:///D:/jiuwen/main/agent-core-java/AGENTS.md#L228-L233) 的「Verification Gate」要求人工跑 `mvn compile`+测试+CodeArts，靠人工执行而非 CI 自动门禁，正是反模式「无 CI（问题靠人工发现）」。
3. **无容器化，仅示例级部署脚本**：Glob `**/Dockerfile*` 无结果。[deploy/README-linux.md:128-151](file:///D:/jiuwen/main/agent-core-java/examples/gitcode_issue_evolver/deploy/README-linux.md#L128-L151) 提供 systemd unit + Nginx 反代 + HTTPS 证书 + 健康检查 + 更新流程（[L190-L206](file:///D:/jiuwen/main/agent-core-java/examples/gitcode_issue_evolver/deploy/README-linux.md#L190-L206) 停服→fetch→checkout→rebuild→start），但这套脚本服务于 gitcode_issue_evolver 示例，非 agent-core-java 自身发布/回滚流水线，且回滚需手工 `git checkout` 重建，无自动回滚。

## 改进建议

1. 补 `.github/workflows/ci.yml`（matrix: JDK 17/21，步骤 lint→`mvn test`→`mvn jacoco:report`→上传覆盖率→条件部署），把 AGENTS.md 的 Verification Gate 固化为 CI 门禁
2. 新增 `Dockerfile`（多阶段构建：maven:3.9-eclipse-temurin-17 编译 → eclipse-temurin:17-jre 运行）与 `docker-compose.yml` 锁定运行环境
3. 引入 maven-deploy-plugin + signing 发布到 Maven Central，配 release.sh 脚本化版本晋升
4. 为 systemd 部署补充自动回滚（保留前一版本 jar+config 快照，健康检查失败自动回退）

## 业界对标

- 标杆：mall 的 docker-compose（容器化）、Spring Boot 的 spring-boot-tools（构建工具链）、FastAPI 的 pyproject.toml
- 差距：本项目无 CI 无 Dockerfile，是 13 维中最大短板；强项是 pom 规范 + dependencyManagement 锁版本
