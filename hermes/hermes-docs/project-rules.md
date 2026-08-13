# Hermes Agent 项目规则（精简版）

> 由 `project-analysis` 诊断模式产出。基于评分短板 + 标杆实践提炼的精简规则，供 TRAE 助手自动遵循。
>
> 配套：[development-reference.md](development-reference.md)（详细开发参考）| [project-health.md](project-health.md)（汇总评分卡）| [quality/](quality/README.md)（13 分维度评估）

---

## 一、技术栈

- 语言：Python 3.11-3.13（`requires-python = ">=3.11,<3.14"`）+ TypeScript（Ink TUI / React Web / Electron Desktop）
- 类型：自改进 AI Agent 应用（CLI + 消息网关 + TUI + Desktop）
- 构建：setuptools + uv（Python）/ npm workspaces（Node）
- 包管理：uv（Python 依赖精确锁定 `==X.Y.Z`）/ npm + overrides（Node）

## 二、Lint / Typecheck / Test 命令

```bash
# Python lint（当前仅 PLW1514 阻塞，建议扩到 E/F/I/UP/B）
ruff check . --select PLW1514                    # 阻塞门禁
ruff check .                                    # 全量 lint（建议非阻塞）
ty check                                       # 类型检查（当前 --exit-zero）

# TS lint
npm run --ws lint                               # eslint 各 workspace
npm run --ws check                              # typecheck 各 workspace

# 测试（必须用 wrapper，不要直接 pytest）
scripts/run_tests.sh                            # 全量套件，CI-parity
scripts/run_tests.sh tests/gateway/             # 单目录
scripts/run_tests.sh tests/agent/test_foo.py -k test_x  # 单测试

# 构建
uv lock                                         # 重新生成 uv.lock
npm install                                     # Node 依赖
cd ui-tui && npm run build                      # TUI 构建

# 依赖扫描
# OSV: .github/workflows/osv-scanner.yml
# 供应链: .github/workflows/supply-chain-audit.yml
```

## 三、禁项（NEVER）

### 代码规范
- ❌ 不写裸魔法数（用常量，如 `_MAX_TOOL_ERROR_CHARS`）
- ❌ 不靠人工 review 保持风格（用 ruff/eslint CI 门禁）
- ❌ 不写 >500 行单文件（按 AGENTS.md wanted work 拆分 god-file）
- ❌ 注释不只写 what，必须写 why

### 架构约束
- ❌ 不跨层调用（Controller 不直调 DAO，遵循依赖链：registry → tools → model_tools → run_agent）
- ❌ 不引入循环依赖（registry.py 显式标注 circular-import safe）
- ❌ 不在领域层耦合框架注解（用 ABC 隔离）
- ❌ 不往 god-class（AIAgent 60+ 参数）继续塞参数（用 Builder/Config 收敛）

### 可测试性
- ❌ 不直连真实 DB 的"单元测试"（用 _hermetic_environment autouse fixture）
- ❌ 不写 change-detector 测试（断言行为不变量，非数据快照）
- ❌ 不在测试中读源码文本（禁源码正则测试）
- ❌ 不伪造宿主 OS（用 `@pytest.mark.linux_only/macos_only/windows_only`，不用 `skipif`）
- ❌ 不在测试中写 `~/.hermes/`（用 `_isolate_hermes_home` 重定向 HERMES_HOME）

### 性能
- ❌ 不循环内查库（N+1，用窗口函数 `ROW_NUMBER() OVER`）
- ❌ 不破坏 prompt caching（不改 past context / 不换 toolset / 不重建 system prompt mid-conversation）
- ❌ 不盲目加缓存（有 TTL/失效/一致性设计）

### 可靠性
- ❌ 不空 catch 吞异常（cleanup 也加 `logger.debug(exc_info=True)`）
- ❌ 不无超时调外部（每次 `chat.completions.create` 传 `timeout=`）
- ❌ 不非幂等的关键写操作（用 file lock + epoch + CAS）

### 安全
- ❌ 不硬编码密钥（用 `.env` 仅限密钥 / secret-source 插件）
- ❌ 不明文存密码（用加密存储）
- ❌ 不信任外部输入（用 path_security/url_safety/threat_patterns 校验）
- ❌ 不日志打印完整凭证（用 RedactingFormatter / redact.py）
- ❌ 不跳过鉴权的"临时"接口
- ❌ 不引入无上界的 PyPI 依赖（dep-bounds CI 直接 fail）
- ❌ 不用 bare `>=X.Y.Z`（必须 `>=floor,<next_major`）

### 易用性
- ❌ 错误只抛 "failed"（用 ClassifiedError + how_to_fix）
- ❌ 配置无校验静默失败（用 validate_config_structure）

### 可扩展性
- ❌ 不在核心加新 model tool（按 Footprint Ladder：extend → CLI+skill → check_fn → plugin → MCP → core last resort）
- ❌ 不 if-else 堆叠变体（用策略/插件模式）
- ❌ 不直接依赖实现类（面向 ABC 接口）
- ❌ 插件不改核心文件（用 ABC/hooks/ctx 扩展）
- ❌ 不用 `HERMES_*` env var 做非密钥配置（用 config.yaml，.env 仅限密钥）

### 依赖
- ❌ 不不锁版本（必须 lockfile + 上界）
- ❌ 不引入 GPL 等受限许可证

## 四、应做（SHOULD）

### 代码规范
- ✅ 配置 `.editorconfig`（待补）
- ✅ ruff 启用 E/F/I/UP/B 核心规则集（待补，当前仅 PLW1514）
- ✅ ty 升级为阻塞门禁（待补，当前 --exit-zero）

### 架构约束
- ✅ 引入 import-linter 声明层契约（待补）
- ✅ 拆分 god-file（cli.py 17k / gateway/run.py 26k / hermes_state.py 10k）

### 可测试性
- ✅ 接入 pytest-cov + 覆盖率门禁（待补，branch 40% 起步）
- ✅ 用 `scripts/run_tests.sh`（不要直接 pytest）
- ✅ 测试 marker 分层（integration/ssh/linux_only/macos_only/windows_only）

### 可靠性
- ✅ 重试用 jittered_backoff（agent/retry_utils.py）
- ✅ 限流用 nous_rate_guard（跨会话共享）
- ✅ 幂等用 file lock + epoch（drain_control.py）
- ✅ 异常用 error_classifier 分类（25+ FailoverReason）

### 可观测性
- ✅ 日志用 setup_logging（4 文件分级 + RedactingFormatter）
- ✅ 关联 ID 用 set_session_context（session_tag）

### 安全
- ✅ 密钥用 secret-source 插件 / `.env`
- ✅ 鉴权 fail-closed（authz_mixin.py）
- ✅ 路径用 get_hermes_home()（不用 `Path.home() / ".hermes"`，破坏 profiles）

### 可扩展性
- ✅ 新能力按 Footprint Ladder 选最小足迹
- ✅ 同类多 provider 设计 ABC + orchestrator
- ✅ 配置写 config.yaml（DEFAULT_CONFIG + 深合并 + 版本迁移）

### 依赖
- ✅ 核心依赖 `==X.Y.Z` 精确锁定
- ✅ 其余 `>=floor,<next_major`
- ✅ Git URL 用 40 字符 SHA
- ✅ GitHub Actions 用 SHA + 注释
- ✅ 新增依赖跑 `uv lock` 重新生成

## 五、关键路径（编辑时必读）

| 文件 | 职责 | 注意 |
|------|------|------|
| `run_agent.py` | AIAgent 核心对话循环 | god-class，60+ 参数，改动需审慎 |
| `cli.py` | HermesCLI 交互 CLI | god-file 17k 行，按 mixin 拆 |
| `gateway/run.py` | 消息网关 | god-file 26k 行，按生命周期拆 |
| `toolsets.py` | 工具集定义 | _HERMES_CORE_TOOLS 是默认 bundle |
| `tools/registry.py` | 工具注册 | AST 自发现，无依赖，circular-import safe |
| `hermes_constants.py` | 公共常量 | get_hermes_home/display_hermes_home，零依赖 |
| `hermes_cli/config.py` | 配置 | DEFAULT_CONFIG + 深合并 + 版本迁移 |
| `agent/error_classifier.py` | 异常分类 | 25+ FailoverReason + ClassifiedError |
| `agent/retry_utils.py` | 重试 | jittered_backoff + Retry-After |

## 六、已知陷阱（AGENTS.md 摘要）

- **Squash merge 前必须 rebase 到 main**：stale 分支会静默回退修复
- **`_last_resolved_tool_names` 是 process-global**：delegate_tool 保存/恢复，子代理运行时可能 stale
- **gateway 有两层消息守卫**：base adapter + run.py，控制命令必须绕过两层
- **不 wire 死代码**：未启用代码未启用有原因，wire 前必须 E2E 验证
- **`\033[K` 在 prompt_toolkit 下泄漏**：用 space-padding 替代
