# 04 可测试性 testability（否决项）

> 维度归属：B 代码质量组。**否决项：本维度=0 即整体计 1 否决。** 本项目=3，不触发否决。
>
> 配套：[汇总评分卡](../project-health.md) | [索引](README.md)

## 评分：3 / 4（不触发否决）

测试规模庞大（2863 个 test_*.py、12 个 conftest、~17k 测试），分层清晰（integration/ssh/linux_only/macos_only/windows_only/requires_wal/no_isolate 等 marker + OS 独立 lane + evals），隔离设施业内顶尖（autouse 清凭据、HERMES_HOME tempdir、subprocess/os.kill mock、per-file 子进程隔离、flake 重试）。但**无覆盖率测量**（无 pytest-cov/coverage 配置），且 e2e-desktop 当前被禁用（红屏/flaky）。落 3 分"有分层测试+部分耦合外部+偶有 flaky"。

## 评估过程

### 关键问题（带 file:/// 证据）

1. **无覆盖率测量** — pyproject.toml 无 `[tool.coverage]`、无 `.coveragerc`（Glob 无结果），dev 依赖仅 `pytest==9.1.1` + `pytest-asyncio`，无 pytest-cov/coverage → [pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L184)；tests.yml 全文无 `--cov`。

2. **E2E 桌面套件当前被硬关闭** — ci.yml 第 123 行 `if: ${{ false && ...`，注释称"the suite is red on every PR and on main itself"（tracking #76627）→ [ci.yml](file:///D:\yaodh\main\hermes-agent\.github\workflows\ci.yml#L116-L124)。

3. **per-file 子进程隔离带来速度代价** — conftest 第 112-114 行自述历史曾用 per-test 隔离但"too slow at ~17k tests"，退回 per-file；单测未达"<10s"门槛 → [tests/conftest.py](file:///D:\yaodh\main\hermes-agent\tests\conftest.py#L103-L116)。

### 亮点

- ✅ **`_hermetic_environment` autouse fixture 工业级隔离**：清空所有 credential 形态 env var（庞大 allowlist）、HERMES_HOME→per-test tempdir、TZ=UTC/LANG=C.UTF-8/PYTHONHASHSEED=0、AWS IMDS 禁用、lazy install 禁用、plugin singleton 重置 → [tests/conftest.py](file:///D:\yaodh\main\hermes-agent\tests\conftest.py#L429-L533)。
- ✅ **多重 autouse 写守卫**：`_kanban_write_guard`、`_state_db_write_guard`、`_live_system_guard`（mock subprocess.run/Popen/os.kill/os.killpg/pty.spawn）、`_audio_playback_guard`、`_isolate_computer_use_approval_state`——外部依赖全 mock，无法触碰真实系统 → [tests/conftest.py](file:///D:\yaodh\main\hermes-agent\tests\conftest.py#L634-L711)。
- ✅ **scripts/run_tests.sh 用 `env -i` 起空环境再 opt-in**，凭据无法泄漏；预编译 .pyc → [run_tests.sh](file:///D:\yaodh\main\hermes-agent\scripts\run_tests.sh#L152-L183)。
- ✅ **测试分层 marker 完备**（integration/ssh/linux_only/macos_only/windows_only/requires_wal/no_isolate/real_concurrent_gate），`addopts = "-m 'not integration'"` 默认排除慢集成 → [pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L427-L441)。
- ✅ **OS 原生 lane**（tests-os.yml）按 marker grep 分发，"不伪造宿主 OS"原则写入 AGENTS.md → [AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L1394-L1430)。
- ✅ **tests/fakes/ 与 evals/ 并存**（fake_ha_server.py + 真实 AIAgent + temp HERMES_HOME 的 readtool eval）→ [evals/readtool/runner.py](file:///D:\yaodh\main\hermes-agent\evals\readtool\runner.py#L1-L16)。
- ✅ **AGENTS.md 有强测试哲学**：禁 change-detector 测试、禁源码正则测试、要求行为契约 → [AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L1432-L1534)。

## Checklist 对照

- [x] 测试文件数 vs 源码比例合理 — ✅ 2863 测试文件 / 4091 源文件 ≈ 0.7
- [ ] 是否跑了覆盖率 — ❌ 无 coverage 配置
- [ ] 单测是否快且不依赖外部 — ⚠️ per-file 隔离偏慢
- [x] 是否有 DI/可 mock 设计 — ✅ autouse mock 全面
- [x] 是否有 flaky 测试 — ⚠️ 有 flake 重试机制（说明存在 flaky）
- [x] 测试是否分层 — ✅ marker + OS lane 分层清晰

## 改进建议

1. 接入 pytest-cov + `[tool.coverage.run]`，先以"不下降"阈值（如 branch 40%）上 CI，逐步推到 60-80%，否则覆盖率永远是盲区。
2. 修复 e2e-desktop（#76627）或显式标注长期弃用，避免"看起来在跑实则关闭"的假象。
3. per-file 隔离速度可考虑对"无 module 状态"的纯函数测试加 `@pytest.mark.no_isolate` 跳过子进程，或引入 xdist 按文件分片提速。
