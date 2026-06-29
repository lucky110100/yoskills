# 汇报模板（在工作流 Step 4 之后给用户的回复）

> 内容皆需基于实际数据填充。**不要**用占位符或推断值。

---

Excel 报表生成完成并已校验：

**文件**：`<绝对路径>`（<体积>）

**表头**：模块名 | 用例文件名 | 状态 | 优先级 | 不通过原因 | 用例目录

**统计**：

| 状态 | 数量 |
|---|---|
| 通过 | <N> |
| 失败 | <N> |
| 错误 | <N> |
| 跳过 | <N> |
| **合计** | **<N>** |

| 优先级 | 数量 | 含义 |
|---|---|---|
| P0 真实失败 | <N> | 普通断言 / 计算结果错误 |
| P1 核心能力缺失 | <N> | Python contract / Fake-green guard / SDK not implemented / parity gap |
| P2 行为不一致 | <N> | Java logs/raises/returns X instead of Y / 字段差异 / ClassCast |
| P3 环境/真实模型 | <N> | LLM endpoint / real model / API_KEY not set / Python pytest.mark.skip |
| P4 通过 | <N> | — |

**说明**（如适用）：

- mvn 终端摘要为 `Failures: <X>, Errors: <Y>, Skipped: <Z>`，本表解析自 `<NNNN>` 个 surefire XML 得 `失败 <X> / 错误 <Y> / 跳过 <Z>`。两侧 `Tests run = <total>` 一致，差异来源于参数化用例每个迭代单独条目。
- 控制台中文乱码是 Windows GBK 终端显示问题，Excel 文件本身写的是 UTF-8 中文（已用 openpyxl 校验首 N 行字段是中文）。
