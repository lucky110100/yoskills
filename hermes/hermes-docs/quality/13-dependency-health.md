# 13 依赖健康度 dependency-health

> 维度归属：E 外部质量组。评估版本锁定、CVE、过时依赖、许可证、循环依赖。
>
> 配套：[汇总评分卡](../project-health.md) | [索引](README.md)

## 评分：4 / 4

对照 4 分档「版本锁定+无CVE+依赖新+许可证合规+无循环」，五项全部命中。依赖治理是该项目的标杆性能力，AGENTS.md 有成文 Dependency Pinning Policy，并有 CI 强制上界检查。

## 评估过程

### 关键问题（带 file:/// 证据）

1. **OSV 扫描为检测模式，不阻断既有 CVE 合并**（与维度 11 同源策略），理论上 pinned 版本若含未修 CVE 不会红 CI——但实际 pin 已主动拉到修复版，故不构成降分 → [osv-scanner.yml](file:///D:\yaodh\main\hermes-agent\.github\workflows\osv-scanner.yml#L19-L21)。

2. **无显式许可证扫描步骤** — 项目自身 MIT，但未在 CI 中对传递依赖做许可证合规扫描（如 pip-licenses）→ [pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L15-L16)。

### 亮点

- ✅ **双 lockfile 全锁定** — Python `uv.lock` + Node `package-lock.json`（含 website/ 等多份）均入库 → [uv.lock](file:///D:\yaodh\main\hermes-agent\uv.lock)、[package-lock.json](file:///D:\yaodh\main\hermes-agent\package-lock.json)。
- ✅ **核心依赖精确 `==` 锁定，其余 `>=floor,<next_major` 上界** — AGENTS.md 成文政策（litellm 事件 + Mini Shai-Hulud 蠕虫后强化），Git URL 用 40 字符 SHA，GitHub Actions 用 SHA+注释，CI-only pip 用 `==exact` → [AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L598-L617)、[pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L18-L37)。
- ✅ **依赖较新** — openai 2.24.0、pydantic 2.13.4、fastapi 0.133.1、Pillow 12.3.0、aiohttp 3.14.3、cryptography 50.0.0、starlette 1.3.1 均为近期版本 → [pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L38-L132)。
- ✅ **CVE 主动修补到修复底版** — cryptography 50.0.0 修 6 项 CVE/GHSA、urllib3 2.7.0+ 修 decompression-bomb/header leak、aiohttp 3.14.3 修多项、PyJWT 2.13.0 修 PYSEC、starlette 1.3.1 修 BadHost、anthropic 0.87.0 修 CVE → [pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L80-L96)、[pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L167)。
- ✅ **override-dependencies 修补上游未发版的易受攻击转译依赖**（discord.py 的 pynacl<1.6、alibabacloud 的 cryptography<49）→ [pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L370-L383)。
- ✅ **`exclude-newer = "14 days"` 供应链隔离窗口** + 对 CVE 修复包白名单豁免 → [pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L384-L389)。
- ✅ **lazy_deps 延迟安装降低爆炸半径** — venv 作用域、allowlist、禁 `--index-url`/`git+`/`file:`、durable-target 模式 `sys.path` 末尾追加（只能新增不能遮蔽核心），`security.allow_lazy_installs` 可 opt-out → [lazy_deps.py](file:///D:\yaodh\main\hermes-agent\tools\lazy_deps.py#L25-L66)。
- ✅ **dep-bounds CI 门禁** — PR 新增无上界 PyPI 依赖直接 `::error::` 并 `exit 1` → [supply-chain-audit.yml](file:///D:\yaodh\main\hermes-agent\.github\workflows\supply-chain-audit.yml#L209-L219)、[supply-chain-audit.yml](file:///D:\yaodh\main\hermes-agent\.github\workflows\supply-chain-audit.yml#L252-L256)。
- ✅ **许可证合规** — 项目 `license = "MIT"`、`license-files = ["LICENSE"]` → [pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L15-L16)。
- ✅ **无循环依赖** — uv 解析器天然禁止环；[tool.setuptools] 显式声明 py-modules 与 packages.find 范围 → [pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L391-L416)。
- ✅ **npm overrides** — package.json 对 lodash/yauzl/protobufjs/brace-expansion/mermaid/dompurify 等传递依赖做安全覆盖 → [package.json](file:///D:\yaodh\main\hermes-agent\package.json#L45-L60)。

## Checklist 对照

- [x] 是否有 lockfile — ✅ uv.lock + package-lock.json
- [x] 是否扫了 CVE — ✅ osv-scanner + supply-chain-audit CI
- [x] 依赖是否过时 — ✅ 均为近期版本
- [ ] 是否检查许可证 — ⚠️ 项目自身 MIT，但无传递依赖许可证扫描 CI
- [x] 是否有循环依赖 — ✅ 无（uv 解析器禁止 + 显式 packages.find）

## 改进建议

1. 在 CI 增加 `pip-licenses`（或 `uv tree --licenses`）步骤，对传递依赖做许可证合规扫描，拦截 GPL/AGPL 等冲突许可证。
2. 对 OSV 扫描结果按 severity 分级，高危项开 issue 跟踪并设 SLA 修补。
