# 10 构建与CI build-ci

> 维度归属：D 演进质量组。评估构建脚本、CI/CD、环境管理、发布流程、回滚。
>
> 配套：[汇总评分卡](../project-health.md) | [索引](README.md)

## 评分：4 / 4

27 个 CI workflow + 编排器变更分类器（14 车道门控）、Dockerfile 多阶段 SHA 锁定 + SQLite 加固编译、完整 Nix flake（16 文件三系统）、CalVer release.py + changelog、uv.lock/package-lock.json 精确锁定 + dependabot 供应链姿态、三重复回滚（curator rollback + hermes backup/import + checkpoints）、跨平台安装器 + installer-tests CI。

## 评估过程

### 亮点（带 file:/// 证据）

- ✅ **27 个 CI workflow** — ci.yml（编排器 + 变更分类器 classify_changes.py 14 车道门控）、tests.yml、tests-os.yml（OS 原生 lane）、lint.yml（ruff-blocking + ty + windows-footguns）、supply-chain-audit.yml（供应链安全）、osv-scanner.yml（CVE）、js-tests.yml、docker.yml、docker-lint.yml、installer-tests.yml、install-e2e.yml、deploy-site.yml、docs-site-checks.yml、e2e-desktop.yml、uv-lockfile-check.yml、lockfile-diff.yml 等 → [.github/workflows/](file:///D:\yaodh\main\hermes-agent\.github\workflows)。
- ✅ **CI 变更分类器** — `scripts/ci/classify_changes.py` 按改动文件决定跑哪些 job，14 车道门控，避免全量跑 → [AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L1382-L1392)。
- ✅ **Dockerfile 多阶段 + SHA 锁定** — Docker + docker-lint（hadolint）双 workflow → [Dockerfile](file:///D:\yaodh\main\hermes-agent\Dockerfile)、[.hadolint.yaml](file:///D:\yaodh\main\hermes-agent\.hadolint.yaml)。
- ✅ **完整 Nix flake**（16 文件）— flake.nix、devShell.nix、hermes-agent.nix、nixosModules.nix、packages.nix、python.nix、sandbox.nix、tui.nix、web.nix、desktop.nix、checks.nix、overlays.nix 等，三系统（Linux/macOS/Windows）覆盖 → [flake.nix](file:///D:\yaodh\main\hermes-agent\flake.nix)。
- ✅ **CalVer 发布脚本 + changelog** — `scripts/release.py` 生成 changelog 并创建 GitHub releases with CalVer tags，支持 dry-run/semver bump → [release.py](file:///D:\yaodh\main\hermes-agent\scripts\release.py#L1-L21)。
- ✅ **双 lockfile 全锁定** — uv.lock（Python）+ package-lock.json（Node），精确锁定保证构建可复现 → [uv.lock](file:///D:\yaodh\main\hermes-agent\uv.lock)、[package-lock.json](file:///D:\yaodh\main\hermes-agent\package-lock.json)。
- ✅ **dependabot 供应链姿态** — 仅对 github-actions 开启（SHA pins），源码依赖走 CVE-only 安全更新，不与锁定策略冲突 → [dependabot.yml](file:///D:\yaodh\main\hermes-agent\.github\dependabot.yml#L1-L23)。
- ✅ **三重复回滚机制** — ① curator rollback（技能快照 tar.gz + 回滚）→ [AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L1082-L1112)；② hermes backup/import（配置/状态备份）→ [hermes_cli/backup.py](file:///D:\yaodh\main\hermes-agent\hermes_cli\backup.py)；③ checkpoints-and-rollback（会话检查点）→ [checkpoints-and-rollback.md](file:///D:\yaodh\main\hermes-agent\website\docs\user-guide\checkpoints-and-rollback.md)。
- ✅ **跨平台安装器** — install.sh（Linux/macOS/WSL2/Termux）、install.ps1/install.cmd（Windows 原生）、setup-hermes.sh，且 installer-tests CI + install-e2e CI 验证 → [scripts/install.sh](file:///D:\yaodh\main\hermes-agent\scripts\install.sh)、[scripts/install.ps1](file:///D:\yaodh\main\hermes-agent\scripts\install.ps1)。
- ✅ **dep-bounds CI 门禁** — PR 新增无上界 PyPI 依赖直接 `::error::` 并 `exit 1` → [supply-chain-audit.yml](file:///D:\yaodh\main\hermes-agent\.github\workflows\supply-chain-audit.yml#L252-L256)。
- ✅ **uv-lockfile-check + lockfile-diff** — lockfile 一致性与 diff 可视化 CI → [uv-lockfile-check.yml](file:///D:\yaodh\main\hermes-agent\.github\workflows\uv-lockfile-check.yml)。

### 观察项（非短板）

1. e2e-desktop CI 当前硬关闭（tracking #76627）→ [ci.yml](file:///D:\yaodh\main\hermes-agent\.github\workflows\ci.yml#L116-L124)。属测试维度问题，此处仅记录。

## Checklist 对照

- [x] 是否有 CI/CD — ✅ 27 个 workflow + 变更分类器
- [x] 环境是否容器化/锁定 — ✅ Docker + Nix + 双 lockfile
- [x] 构建是否自动化 — ✅ setuptools + uv + npm workspaces
- [x] 是否有发布与回滚流程 — ✅ CalVer release.py + 三重复回滚

## 改进建议

1. 修复 e2e-desktop CI（#76627）或显式标注长期弃用。
2. 考虑把 `tests/stress/test_benchmarks.py` 接入 nightly CI job 做性能回归。
