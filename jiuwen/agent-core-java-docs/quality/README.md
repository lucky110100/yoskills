# agent-core-java 质量评估 — 维度索引

> 由 `project-analysis` 诊断模式产出。本目录含 13 个分维度详细评估文档 + 本索引。总报告见 [../project-health.md](file:///D:/jiuwen/main/yoskills/jiuwen/agent-core-java-docs/project-health.md)。
>
> **基线**: v0.1.14 @ `695089224478c4cd1670340f56d64ecb8de4c5b7`（分支 730）| **总分 2.84 / 4.0** | 🟡 黄灯（可维护，需改进）| **0 否决项**

## 评分汇总（14 维，含功能维度 A 组）

| NN | 维度 | 组 | 分 | 文档 | 关键判定 |
|----|------|---|---|------|---------|
| — | 功能特性 | A | 3 | （见 [../features/](file:///D:/jiuwen/main/yoskills/jiuwen/agent-core-java-docs/features/) skills 域索引） | 功能域完整，全项目索引待补 |
| 01 | 代码规范 | B | **2** | [01-code-style.md](file:///D:/jiuwen/main/yoskills/jiuwen/agent-core-java-docs/quality/01-code-style.md) | 无 checkstyle 门禁 + 重复常量 |
| 02 | 架构约束 | B | 3 | [02-arch-rules.md](file:///D:/jiuwen/main/yoskills/jiuwen/agent-core-java-docs/quality/02-arch-rules.md) | 分层清晰无 ArchUnit + RunnerImpl 上帝类倾向 |
| 03 | 复用性 | B | 3 | [03-reusability.md](file:///D:/jiuwen/main/yoskills/jiuwen/agent-core-java-docs/quality/03-reusability.md) | SPI 可插拔强项 + 偶有常量 copy-paste |
| 04 | 可测试性（否决） | B | 3 | [04-testability.md](file:///D:/jiuwen/main/yoskills/jiuwen/agent-core-java-docs/quality/04-testability.md) | 100+ 测试 @Tag 分层 + 无覆盖率门禁 |
| 05 | 性能 | C | **2** | [05-performance.md](file:///D:/jiuwen/main/yoskills/jiuwen/agent-core-java-docs/quality/05-performance.md) | GraphMemory N+1 + 无压测基线 |
| 06 | 可靠性（否决） | C | 3 | [06-reliability.md](file:///D:/jiuwen/main/yoskills/jiuwen/agent-core-java-docs/quality/06-reliability.md) | 自实现熔断+重试+锁幂等 + 27 处 catch ignored |
| 07 | 可观测性 | C | 3 | [07-observability.md](file:///D:/jiuwen/main/yoskills/jiuwen/agent-core-java-docs/quality/07-observability.md) | OTel 全链路追踪强项 + 缺 actuator/RED 指标 |
| 08 | 可扩展性 | D | **4** | [08-extensibility.md](file:///D:/jiuwen/main/yoskills/jiuwen/agent-core-java-docs/quality/08-extensibility.md) | 9 个 SPI 扩展点（卓越，唯一 4 分） |
| 09 | 文档完备度 | D | 3 | [09-documentation.md](file:///D:/jiuwen/main/yoskills/jiuwen/agent-core-java-docs/quality/09-documentation.md) | 1000+ API 文档 + 缺 ADR + SUMMARY 重复 |
| 10 | 构建与CI | D | **2** | [10-build-ci.md](file:///D:/jiuwen/main/yoskills/jiuwen/agent-core-java-docs/quality/10-build-ci.md) | pom 规范但完全无 CI/无 Dockerfile（最大短板） |
| 11 | 安全性（否决） | E | 3 | [11-security.md](file:///D:/jiuwen/main/yoskills/jiuwen/agent-core-java-docs/quality/11-security.md) | Guardrail 模型 + SQL 拼接隐患 + 无安全扫描 |
| 12 | 易用性 | E | 3 | [12-usability.md](file:///D:/jiuwen/main/yoskills/jiuwen/agent-core-java-docs/quality/12-usability.md) | 47 examples 强项 + 无 OpenAPI/CLI --help |
| 13 | 依赖健康度 | E | 3 | [13-dependency-health.md](file:///D:/jiuwen/main/yoskills/jiuwen/agent-core-java-docs/quality/13-dependency-health.md) | dependencyManagement+3BOM + 无 lockfile |

## 短板与卓越

- **短板（2 分）**：构建与CI、代码规范、性能 —— 三处最低，是拉低总分的主因
- **卓越（4 分）**：可扩展性 —— 9 个 SPI 扩展点 + ServiceLoader，唯一卓越维度
- **否决项检查**：安全性=3 / 可靠性=3 / 可测试性=3 → **0 否决**（未触发红灯）

## 雷达图数据（14 维）

```
功能:3  代码规范:2  架构约束:3  复用性:3  可测试性:3
性能:2  可靠性:3  可观测性:3  可扩展性:4  文档:3
构建CI:2  安全:3  易用:3  依赖:3
```

## 加权计算

组权重 A 0.15 / B 0.30 / C 0.25 / D 0.20 / E 0.10（组内均分）：
= 0.15×3 + 0.30×(2+3+3+3)/4 + 0.25×(2+3+3)/3 + 0.20×(4+3+2)/3 + 0.10×(3+3+3)/3
= 0.45 + 0.825 + 0.667 + 0.600 + 0.300 = **2.84**

## 交叉引用

- **总报告**: [../project-health.md](file:///D:/jiuwen/main/yoskills/jiuwen/agent-core-java-docs/project-health.md)（评分卡 + 问题清单 + 改进路线图）
- **功能维度索引**: [../features/](file:///D:/jiuwen/main/yoskills/jiuwen/agent-core-java-docs/features/)（skills 管理域，由 feature-analysis 产出）
- **评估卡（技能）**: `D:\jiuwen\main\yoskills\common\project-analysis\dims\*.md`（13 维评估锚点定义）
- **业界标杆库**: `D:\jiuwen\main\yoskills\common\project-analysis\benchmarks\java-spring.md`

## 改进路线图（摘要，详见总报告第五节）

- **P0**（补齐升至 ~3.4 绿灯）: 补 CI+Dockerfile、SQL 参数化、GraphMemory 批量化
- **P1**: 清理 catch ignored、覆盖率门禁、checkstyle、.gitignore+.env
- **P2**: ArchUnit、ADR、CLI --help、lockfile
