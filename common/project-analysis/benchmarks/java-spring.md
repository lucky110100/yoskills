---
tech: java-spring
---

# Java / Spring 生态标杆项目

> 本文件供 `project-analysis` 对标模式使用。每个标杆记录「看哪些目录/配置」与「浅/深对标提示」。
> **仓库地址与 star 数会变动，AI 对标前应 `git ls-remote` 或 WebSearch 核实现状。**

## Spring Boot

- 仓库: https://github.com/spring-projects/spring-boot
- 类型: 框架
- 亮点维度: 架构约束 / 可扩展性 / 可测试性 / 构建与CI / 可靠性 / 可观测性
- 对标要点:
  - 看 `spring-boot-project/spring-boot-autoconfigure/` — 自动配置机制(条件装配,可扩展性范本)
  - 看 `spring-boot-project/spring-boot/.../actuator/` — 可观测性端点(健康检查/指标/审计)
  - 看 `spring-boot-project/spring-boot-starters/` — starter 约定(依赖管理范本)
  - 看 `spring-boot-project/spring-boot-tools/` — 构建工具链
  - 看 `spring-boot-test/` — 测试体系(集成测试分层范本)
- 浅对标源: https://spring.io/projects/spring-boot / README / reference docs
- 深对标提示: clone 后读 `dims/extensibility.md` 比自动配置扩展点; 读 `dims/testability.md` 比测试分层

## mall

- 仓库: https://github.com/macrozheng/mall
- 类型: 应用(电商,前台商城+后台管理)
- 亮点维度: 架构约束 / 文档完备度 / 构建与CI / 复用性
- 对标要点:
  - 看 `mall-common/` — 公共模块(复用性范本)
  - 看各 `mall-*-service/` — Controller/Service/Dao 分层
  - 看 `document/` — 配套文档与教程(文档完备度范本)
  - 看 `docker/` 与 `docker-compose.yml` — 容器化部署
- 浅对标源: README / https://www.macrozheng.com/ (作者博客,文档极全)
- 深对标提示: clone 后读 `dims/reusability.md` 比公共模块划分; 读 `dims/build-ci.md` 比 docker 化

## RuoYi-Vue-Plus

- 仓库: https://github.com/dromara/RuoYi-Vue-Plus (Gitee 镜像: https://gitee.com/dromara/RuoYi-Vue-Plus)
- 类型: 应用(企业级后台管理框架)
- 亮点维度: 安全性 / 可扩展性 / 复用性 / 代码规范
- 对标要点:
  - 看 `ruoyi-common/` — 公共模块(脱敏/翻译/多租户)
  - 看 `ruoyi-framework/` — 安全框架(Sa-Token 鉴权、数据权限)
  - 看各业务模块的模块化拆分
  - 看 `ruoyi-admin/` — 启动与配置
- 浅对标源: README / 官方文档
- 深对标提示: clone 后读 `dims/security.md` 比鉴权与数据脱敏; 读 `dims/extensibility.md` 比模块化

## eladmin

- 仓库: https://github.com/elunez/eladmin
- 类型: 应用(后台管理)
- 亮点维度: 代码规范 / 可观测性 / 构建与CI / 可测试性
- 对标要点:
  - 看 `eladmin-system/` — 主业务模块分层
  - 看 `eladmin-logging/` — 日志/AOP 操作记录(可观测性范本)
  - 看 `eladmin-common/` — 公共工具
  - 看注解驱动的日志/缓存设计
- 浅对标源: README / 官方文档
- 深对标提示: clone 后读 `dims/code-style.md` 比代码规范; 读 `dims/observability.md` 比日志设计

## Spring Cloud Alibaba

- 仓库: https://github.com/alibaba/spring-cloud-alibaba
- 类型: 框架(微服务)
- 亮点维度: 可靠性 / 可观测性 / 可扩展性
- 对标要点:
  - 看 Sentinel 模块 — 限流/熔断/降级(可靠性范本)
  - 看 Nacos 模块 — 配置中心与服务注册
  - 看 Seata 集成 — 分布式事务
  - 看各 starter 的自动配置
- 浅对标源: https://sca.aliyun.com/ / README
- 深对标提示: clone 后读 `dims/reliability.md` 比容错模式; 读 `dims/observability.md` 比监控集成

---

## 选用指引（按想对标的维度选标杆）

| 想对标的维度 | 首选标杆 | 看什么 |
|--------------|---------|--------|
| 架构约束/分层 | mall, eladmin | service 分层与目录 |
| 可扩展性/自动配置 | Spring Boot, RuoYi-Vue-Plus | autoconfigure 与模块化 |
| 安全性/鉴权 | RuoYi-Vue-Plus | Sa-Token 与数据脱敏 |
| 可观测性 | Spring Boot, eladmin | actuator 与 logging 模块 |
| 可测试性 | Spring Boot | spring-boot-test 体系 |
| 可靠性/容错 | Spring Cloud Alibaba | Sentinel 限流熔断 |
| 构建与CI/Docker | mall, Spring Boot | docker-compose 与 tools |
| 文档完备度 | mall | macrozheng 博客体系 |
| 复用性/公共模块 | mall, RuoYi-Vue-Plus | common 模块划分 |

## 补充流程

新发现优秀 Java/Spring 项目时，按上述条目格式(项目名/仓库/类型/亮点维度/对标要点/浅对标源/深对标提示)追加到本文件，并更新「选用指引」表。
