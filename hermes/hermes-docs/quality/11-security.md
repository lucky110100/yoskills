# 11 安全性 security（否决项）

> 维度归属：E 外部质量组。**否决项：本维度=0 即整体计 1 否决。** 本项目=4，不触发否决。
>
> 配套：[汇总评分卡](../project-health.md) | [索引](README.md)

## 评分：4 / 4（不触发否决）

对照 4 分档「无硬编码密钥+鉴权完整+输入校验+依赖无CVE+加密传输存储+日志脱敏+有安全扫描CI门禁」，七项全部命中。该项目在供应链与运行时安全上投入极重，远超一般 Agent 项目。

## 评估过程

### 关键问题（带 file:/// 证据）

1. **`.env.example` 提供 `SUDO_PASSWORD` 明文选项**（带强警告与替代方案，属可接受的设计取舍，非硬编码泄漏）→ [.env.example](file:///D:\yaodh\main\hermes-agent\.env.example#L245-L253)。

2. **OSV-Scanner 采用 `fail-on-vuln: false`（仅检测不阻断合并）** — 这是有意为之的策略：pins 由人工审慎迁移，不自动 bump；但意味着已锁定版本若爆出新 CVE 不会自动红 CI → [osv-scanner.yml](file:///D:\yaodh\main\hermes-agent\.github\workflows\osv-scanner.yml#L19-L21)。

3. **核心 `urllib3` 使用范围 `>=2.7.0,<3` 而非精确 `==`** — 刻意保留上界同时给转译依赖留余地，非硬伤 → [pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L80-L82)。

### 亮点

- ✅ **依赖全精确锁定 + 显式供应链策略注释** — 核心依赖一律 `==X.Y.Z`，注释明确引用 Mini Shai-Hulud 蠕虫攻击 mistralai 2.4.6 事件作为加固动机 → [pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L18-L37)。
- ✅ **CVE 注释密集且可追溯** — requests/PyJWT/cryptography/urllib3/anthropic/starlette/aiohttp 等均标注 CVE/GHSA 编号 → [pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L47)、[pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L94-L96)。
- ✅ **`[tool.uv]` override-dependencies 强制修补易受攻击的转译依赖**（pynacl<1.6、cryptography<49），并设 `exclude-newer = "14 days"` 隔离窗口 + 对安全修复包白名单豁免 → [pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L369-L389)。
- ✅ **日志脱敏极其成熟**（redact.py 1390+ 行）— 覆盖 20+ 厂商前缀、JWT、私钥块、数据库连接串、query/form 敏感键、控制字符反逃逸、ReDoS 防护，默认开启 → [redact.py](file:///D:\yaodh\main\hermes-agent\agent\redact.py#L1-L8)、[redact.py](file:///D:\yaodh\main\hermes-agent\agent\redact.py#L77-L90)。
- ✅ **鉴权默认拒绝 + fail-closed** — `_is_user_authorized` 多层 allowlist，对 adapter 的 `open` 策略拒绝放行（防 fail-open）→ [authz_mixin.py](file:///D:\yaodh\main\hermes-agent\gateway\authz_mixin.py#L386-L401)、[authz_mixin.py](file:///D:\yaodh\main\hermes-agent\gateway\authz_mixin.py#L621-L644)。
- ✅ **凭证文件挂载 fail-closed + 路径穿越防护 + 主密钥库 deny-list** — 技能无法通过 `../../.ssh/id_rsa` 逃逸 HERMES_HOME → [credential_files.py](file:///D:\yaodh\main\hermes-agent\tools\credential_files.py#L62-L84)、[credential_files.py](file:///D:\yaodh\main\hermes-agent\tools\credential_files.py#L122-L135)。
- ✅ **CI 安全扫描门禁** — supply-chain-audit 扫描 litellm 式攻击模式（`.pth`、base64+exec、混淆 subprocess、install-hook），并对无上界 PyPI 依赖直接 fail CI；Actions 全 SHA 锁定，最小权限，显式禁止 `secrets: inherit` → [supply-chain-audit.yml](file:///D:\yaodh\main\hermes-agent\.github\workflows\supply-chain-audit.yml#L103-L115)、[ci.yml](file:///D:\yaodh\main\hermes-agent\.github\workflows\ci.yml#L13-L15)。
- ✅ **Dependabot 仅对 github-actions 开启**（SHA pins），源码依赖走 CVE-only 安全更新 → [dependabot.yml](file:///D:\yaodh\main\hermes-agent\.github\dependabot.yml#L1-L23)。
- ✅ **纵深防御工具齐全** — path_security（穿越）、url_safety（SSRF+云元数据+DNS rebinding）、threat_patterns（prompt 注入/C2/外泄）、tirith_security（预执行扫描+cosign 溯源）、osv_check（MCP 恶意包）、mcp_security（网络外泄+OS 持久化 IOC）、write_approval（写入审批）、ssl_guard（CA 校验）、secret_scope（多 profile 隔离 fail-closed）、defusedxml（WeCom XXE/billion-laughs）。
- ✅ **无硬编码密钥** — Grep `api_key|password|token|secret = '...'` 字面量仅命中 tests/ 测试 fixture 与哨兵值，无真实生产密钥。

## Checklist 对照

- [x] 是否查了硬编码密钥 — ✅ 无（仅测试 fixture 与哨兵值）
- [x] 鉴权是否覆盖所有需保护接口 — ✅ authz_mixin fail-closed 全覆盖
- [x] 是否扫了依赖 CVE — ✅ osv-scanner + supply-chain-audit CI
- [x] 是否查了注入风险点 — ✅ defusedxml/path_security/url_safety/threat_patterns
- [x] 日志是否脱敏 — ✅ redact.py 1390+ 行
- [x] 输入校验是否到位 — ✅ config 校验 + 路径穿越防护

## 改进建议

1. 将 OSV-Scanner 对**新发现的高危 CVE**改为 `fail-on-vuln: severity high`，避免高危漏洞静默滞留。
2. 考虑引入集中式密钥管理服务对接（已有 Bitwarden/1Password/command secret-source 插件，可设为推荐默认）。
3. `SUDO_PASSWORD` 明文选项可改为 keyring/secret-source 后端，彻底消除明文落盘面。
