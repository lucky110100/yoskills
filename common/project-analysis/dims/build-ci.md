---
dim: build-ci
group: D
---

# 构建与CI/工程化 — 维度分析卡（stub）

> 维度归属：D 演进质量组。评估构建脚本、CI/CD、环境管理、发布流程、回滚。**对标要点待阶段 2 补全。**

## 评估信号（发现即记）

- 无构建脚本/纯手动构建
- 无 CI/CD
- 无环境管理（无容器/版本不锁定）
- 无发布流程
- 无回滚机制

## 评估工具与命令

| 工具 | 命令/用法 | 看什么 |
|------|----------|--------|
| Glob | 查 CI 配置（`.github/workflows`/`.gitlab-ci`/Jenkinsfile） | CI 存在性 |
| Glob | 查 Dockerfile/容器配置 | 环境管理 |
| Glob | 查构建脚本（Makefile/build.sh/pom.xml） | 构建自动化 |
| Read | 读发布/回滚脚本 | 发布回滚流程 |

## 评分锚点（5 档）

| 分 | 锚点信号 |
|----|---------|
| 4 | 自动化构建 + CI/CD + 环境容器化 + 发布流程 + 回滚机制 |
| 3 | 有 CI + 部分自动化发布 |
| 2 | 有构建脚本 + 无 CI |
| 1 | 构建手动 + 无 CI |
| 0 | 无构建脚本/纯手动 |

## 规范基线

- ✅ 应：自动化构建 + CI/CD（lint→test→build→scan→deploy） + 容器化环境 + 发布流程 + 回滚机制
- ❌ 不做：手动构建 + 无 CI + "在我机器上能跑" + 无回滚

## 对标要点（业界标杆看哪些）

- Java: 看 mall 的 `docker-compose.yml`(容器化)、Spring Boot 的 `spring-boot-tools/`(构建工具链)
- Python: 看 FastAPI 的 `pyproject.toml`(PEP 621 现代构建)、Django 的发布流程
- 对比 CI 流水线(lint→test→build→scan→deploy)与环境容器化程度

## 反模式

```
❌ "在我机器上能跑"（环境不锁定）
❌ 无 CI（问题靠人工发现）
❌ 发布无回滚（出问题只能手工救火）
```

## Checklist

- [ ] 是否有 CI/CD
- [ ] 环境是否容器化/锁定
- [ ] 构建是否自动化
- [ ] 是否有发布与回滚流程
