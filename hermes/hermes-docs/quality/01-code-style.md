# 01 代码规范 code-style

> 维度归属：B 代码质量组。评估命名/格式/复杂度/注释的统一性与自动化程度。
>
> 配套：[汇总评分卡](../project-health.md) | [索引](README.md)

## 评分：2 / 4

介于 2 分与 3 分之间，倾向 2 分。有格式工具（prettier + ruff）且 ruff 接入 CI 门禁，但 Python 端门禁仅强制 **1 条规则**（PLW1514），其余 lint 全部关闭；类型检查 ty 为纯建议（never fails the build）；**无 .editorconfig**；存在多个超长文件（cli.py 17060 行、gateway/run.py 26468 行），远超 500 行阈值，命中"存在长函数/长文件"信号，故落 2 分。

## 评估过程

### 关键问题（带 file:/// 证据，行号实测）

1. **Python lint 门禁形同虚设** — `[tool.ruff.lint] select = ["PLW1514"]`，注释明言"All other lints are intentionally disabled while we wrangle typechecks" → [pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L450-L465)。唯一阻塞规则是 PLW1514（unspecified-encoding），见 lint.yml 的 ruff-blocking 作业 → [lint.yml](file:///D:\yaodh\main\hermes-agent\.github\workflows\lint.yml#L121-L152)。

2. **类型检查 ty 与全量 ruff diff 仅建议、不拦合并** — lint_diff.py 第 195 行字面写"this check never fails the build" → [lint_diff.py](file:///D:\yaodh\main\hermes-agent\scripts\lint_diff.py#L194-L196)。

3. **无 .editorconfig** — 跨编辑器/IDE 的基础格式基线缺失（实测 `Test-Path` 返回 MISSING）。

4. **超长文件普遍** — cli.py 17060 行、hermes_state.py 10477 行、gateway/run.py 26468 行、hermes_cli/web_server.py 15788 行、hermes_cli/main.py 11233 行、agent/auxiliary_client.py 9277 行、run_agent.py 7658 行。AGENTS.md 第 65-70 行虽把"重构 god-file"列为"wanted work"，但当前仍是规范硬伤 → [AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L65-L70)。

5. **AIAgent `__init__` 单方法 60+ 参数（god-class 构造器）** → [run_agent.py](file:///D:\yaodh\main\hermes-agent\run_agent.py#L435-L494)。

### 亮点

- ✅ TS 侧 ESLint flat config 完善（typescript-eslint + perfectionist 排序 + react-hooks + unused-imports），prettier 配置完整 → [.prettierrc](file:///D:\yaodh\main\hermes-agent\.prettierrc#L1-L11)、[eslint.config.shared.mjs](file:///D:\yaodh\main\hermes-agent\eslint.config.shared.mjs#L21-L96)。
- ✅ 常量提取较好（registry 的 `_MAX_TOOL_ERROR_CHARS=2048`、base.py 的 `_POST_DELIVERY_CALLBACK_TIMEOUT_SECONDS=30.0`），非裸魔法数 → [tools/registry.py](file:///D:\yaodh\main\hermes-agent\tools\registry.py#L32-L36)、[gateway/platforms/base.py](file:///D:\yaodh\main\hermes-agent\gateway\platforms\base.py#L65-L73)。
- ✅ 有 Windows 专用的静态 footgun 检查作为阻塞门禁 → [lint.yml](file:///D:\yaodh\main\hermes-agent\.github\workflows\lint.yml#L154-L180)。

## 规范基线对照

| 信号 | 本项目状态 |
|------|-----------|
| 格式工具配置 | ⚠️ 有 prettier(TS) + ruff(Py)，但无 .editorconfig |
| lint 接入 CI 门禁 | ⚠️ ruff 仅 PLW1514 阻塞，其余 --exit-zero |
| 复杂度热点扫描 | ❌ 无 radon/lizard 配置 |
| 命名一致性 | ✅ 基本一致（Py snake_case / TS camelCase） |
| 魔法数/硬编码 | ✅ 常量集中提取较好 |
| 注释覆盖关键决策 | ✅ pyproject.toml 注释极详尽（记录 CVE/why） |

## 改进建议

1. 把 ruff 的 `select` 从单条 PLW1514 扩到 E/F/I/UP/B 等核心规则集，并保留 per-file-ignores；分批启用避免一次性红屏。
2. 将 ty 类型检查从 `--exit-zero` 升级为阻塞门禁（至少对新文件/改动文件），否则类型约束永远停留在"建议"。
3. 补 `.editorconfig`（charset=utf-8、end_of_line=lf、indent_style=space）作为最低基线。
4. 拆分 cli.py / gateway/run.py / hermes_state.py 的巨型文件（AGENTS.md 已将其列为 wanted work），按职责抽 mixin/子模块。
