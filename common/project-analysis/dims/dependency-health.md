---
dim: dependency-health
group: E
---

# 依赖健康度 — 维度分析卡（stub）

> 维度归属：E 外部质量组。评估版本锁定、CVE、过时依赖、许可证、循环依赖。**对标要点待阶段 2 补全。**

## 评估信号（发现即记）

- 依赖版本不锁定（lockfile 缺失）
- 已知 CVE
- 依赖过时（落后多个大版本）
- 无许可证检查
- 循环/孤立依赖

## 评估工具与命令

| 工具 | 命令/用法 | 看什么 |
|------|----------|--------|
| RunCommand | `npm audit`/`snyk test`/`trivy fs`/`mvn dependency-check` | CVE |
| RunCommand | `npm outdated`/`pip list --outdated` | 过时依赖 |
| RunCommand | license-checker / license-maven-plugin | 许可证合规 |
| madge/dependency-cruiser | 依赖图 | 循环/孤立模块 |
| Glob | 查 lockfile（package-lock/pnpm-lock/yarn.lock/go.sum/Cargo.lock） | 版本锁定 |

## 评分锚点（5 档）

| 分 | 锚点信号 |
|----|---------|
| 4 | 版本锁定 + 无 CVE + 依赖新 + 许可证合规 + 无循环 |
| 3 | 版本锁定 + 偶有低危 CVE + 部分过时 |
| 2 | 版本部分锁定 + 多个 CVE |
| 1 | 无 lockfile + 大量过时 CVE |
| 0 | 依赖混乱 + 高危 CVE 多 |

## 规范基线

- ✅ 应：lockfile 锁定 + 依赖扫描 CI 门禁 + 定期升级 + 许可证检查 + 无循环依赖
- ❌ 不做：不锁版本 + 依赖从不升级 + 引入不合规许可证

## 对标要点（业界标杆看哪些）

- 看 lockfile 存在性: Python(poetry.lock/pdm.lock/requirements pinned)、Java(Maven 无原生 lockfile 看 dependencyManagement 或 Gradle lockfile)
- 看标杆的依赖扫描 CI(snyk/trivy/dependency-check/pip-audit)
- 对比版本锁定策略与定期升级节奏(dependabot/renovate 自动化)

## 反模式

```
❌ 不锁版本（构建不可复现）
❌ 依赖从不扫 CVE（供应链风险）
❌ 引入 GPL 等受限许可证到商业项目
```

## Checklist

- [ ] 是否有 lockfile
- [ ] 是否扫了 CVE
- [ ] 依赖是否过时
- [ ] 是否检查许可证
- [ ] 是否有循环依赖
