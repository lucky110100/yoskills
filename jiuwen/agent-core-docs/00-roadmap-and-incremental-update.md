# 00 - 路标文档与增量更新说明

> 本文件是本套 Code Wiki 的**路标（milestone）文档**，用于记录本次任务的时间线、产出物、基线提交，并定义后续基于项目仓库 git 提交记录**增量更新**对应文档的标准流程。
>
> 后续每次更新本套文档时，应**先更新本路标文档**的"更新记录"表，再按本文件定义的流程更新对应模块文档。

---

## 一、本次任务基线

### 1.1 任务概述

| 项 | 值 |
|----|----|
| 任务目标 | 分析并理解 `D:\jiuwen\main\agent-core` 项目仓库（openJiuwen Core），生成结构化、完整的 Code Wiki 文档（md 文件） |
| 输出目录 | `D:\jiuwen\main\yoskills\jiuwen\agent-core-docs` |
| 任务日期 | 2026-08-05（北京时间 Asia/Shanghai） |
| 任务时长 | 单次会话完成 |
| 文档语言 | 简体中文 |

### 1.2 项目仓库基线提交

| 项 | 值 |
|----|----|
| 仓库路径 | `D:\jiuwen\main\agent-core` |
| 远程仓库 | https://gitcode.com/openJiuwen/agent-core.git |
| 当前分支 | `develop` |
| 分支状态 | `develop` 领先 `origin/develop` 4 个提交 |
| HEAD 提交（短） | `bad6b4a4` |
| HEAD 提交（完整） | `bad6b4a42677da1b341c88a0588640a5bfd301e3` |
| HEAD 提交时间 | 2026-08-04 17:39:35 +0800 |
| HEAD 提交信息 | `Merge branch 'develop' of https://gitcode.com/openJiuwen/agent-core into develop` |
| Tag 描述 | `v0.1.16.post1-95-gbad6b4a4`（即 v0.1.16.post1 之后第 95 个提交） |
| 工作区状态 | `examples/apiconfig.json` 有本地修改（未提交） |
| pyproject.toml 版本 | `0.1.16` |

### 1.3 基线提交附近的关键提交（用于增量更新参照）

> 以下为基线 `bad6b4a4` 之前最近的 20 个提交，按时间倒序排列。后续增量更新时，凡提交时间晚于"上次更新基线"的提交均需纳入更新范围。

| 提交短哈希 | 时间（+0800） | 提交信息 | 影响文档 |
|------------|---------------|----------|----------|
| `bad6b4a4` | 2026-08-04 17:39:35 | Merge branch 'develop' ... into develop | （基线） |
| `52513b60` | 2026-08-04 17:39:14 | tmp: 删除示例 | 09-运行方式（examples） |
| `c64fc130` | 2026-08-04 17:38:42 | fix: preserve boolean substrings in condition variables | 03-core模块 |
| `fc9f9f9a` | 2026-08-04 16:51:11 | [mirror] #288: fix(llm): drop top_p when temperature set for Anthropic | 03-core模块 |
| `cad85ec2` | 2026-08-04 15:53:17 | fix(context): invalidate stale usage token baselines | 03-core模块（context_engine） |
| `803d854e` | 2026-08-04 15:09:05 | fix(browser subagent): improve browser subagent tools and action speed | 04-harness模块（subagents） |
| `aeb88cd8` | 2026-08-04 14:27:40 | fix(agent-team): add hitt、trace、permissions docs | 05-agent_teams模块 |
| `17429753` | 2026-08-04 11:20:19 | feat(rsi): add recursive self-improvement framework | 07-extensions与rsi模块 |
| `8c1654f8` | 2026-08-04 09:50:13 | fix(context): refresh built-in model context window table | 03-core模块（context_engine） |
| `b2ff486e` | 2026-08-04 09:43:02 | feat(team): JSON string tool parameter missing | 05-agent_teams模块 |
| `660e9c57` | 2026-08-04 09:32:10 | [mirror] #255: fix(context): stop counting base64 image payloads as text | 03-core模块（context_engine） |
| `eefde52e` | 2026-08-03 17:38:08 | feat(harness): support the creation, loading, and execution of templates and plugins | 04-harness模块（resources/extension_binder） |
| `7c50c48d` | 2026-08-03 17:21:18 | fix(evolving): Supplement the self-evolving online RL documents | 06-agent_evolving与dev_tools模块 |
| `6403d86c` | 2026-08-03 14:33:02 | fix(harness): use builtin list annotations | 04-harness模块 |
| `a61bc5c2` | 2026-08-03 14:08:32 | fix(agent_teams): bind external cli context to member backend | 05-agent_teams模块 |
| `f6d38283` | 2026-08-03 10:00:59 | feat(agent_teams): add claude otel bridge | 05-agent_teams模块 |
| `c2a85aef` | 2026-08-03 15:15:39 | feat(evolution): JiuwenSwarm online RL optimize for AgentOS | 06-agent_evolving与dev_tools模块 |
| `06c42932` | 2026-08-03 15:06:42 | fix(LSP): avoid blocking LSP rail initialization | 04-harness模块（lsp） |
| `70d1b482` | 2026-08-03 14:28:30 | fix(agent-team): humaninbox can auto_start_member when target is none | 05-agent_teams模块 |
| `e2d6b685` | 2026-08-03 14:28:21 | docs: update docs based on v0.1.16.post1 | 全部文档（版本基线） |

---

## 二、本次任务时间线

> 以下为本次会话的实际执行步骤与时间（按执行顺序）。时间为 UTC+8 北京时间，仅记录到分钟级。

### 阶段一：项目元数据研读（约耗时：少量）

| 时间 | 动作 | 产出/结论 |
|------|------|-----------|
| 启动 | 读取 `README.md` | 确认项目为 openJiuwen Core，Python SDK，面向 LLM 智能体应用 |
| 启动 | 读取 `pyproject.toml` | 确认包名 `openjiuwen`、版本 `0.1.16`、Python `>=3.11,<3.14`、依赖列表与可选依赖组、入口点 |
| 启动 | 读取 `AGENTS.md` | 确认各子模块职责划分（core / harness / extensions / agent_evolving / dev_tools / tests / examples） |
| 启动 | 读取 `Makefile` | 确认 lint/test/type-check 命令与 uv 集成 |
| 启动 | 读取 `CLAUDE.md` 与 `.claude/rules/architecture.md` | 确认 Card/Config 分离、公共 API、子模块测试约定 |

### 阶段二：包结构勘察（约耗时：少量）

| 时间 | 动作 | 产出/结论 |
|------|------|-----------|
| 启动 | 列出 `openjiuwen/` 包结构 | 确认顶层模块：core、harness、agent_teams、agent_evolving、dev_tools、extensions、rsi、symphony、auto_harness |
| 启动 | 读取关键 `__init__.py` | 确认 lazy 导出策略（harness 用 `__getattr__` 懒导入重型模块） |
| 启动 | 深读 `harness/deep_agent.py` | 理解 DeepAgent 委托模式、热重配、任务循环、Rails 路由 |

### 阶段三：并行深度分析（关键阶段）

| 时间 | 动作 | 产出/结论 |
|------|------|-----------|
| 启动 | 派发 4 个并行 search 子智能体 | 分别深度分析 core / harness / agent_teams / (agent_evolving+dev_tools+extensions+rsi) |
| 启动 | 子智能体返回分析 | 获得每个子模块的：职责、关键类（含文件路径）、关键函数、内部依赖、外部依赖、设计模式 |

### 阶段四：文档生成（主产出阶段）

| 时间 | 动作 | 产出文件 |
|------|------|----------|
| 启动 | 设计文档结构并生成导航索引 | `README.md` |
| 启动 | 生成项目概述 | `01-project-overview.md` |
| 启动 | 生成整体架构（分层 + 10 大设计模式 + 数据流） | `02-overall-architecture.md` |
| 启动 | 生成 core 模块文档（16 个子模块） | `03-core-module.md` |
| 启动 | 生成 harness 模块文档（11 个子模块） | `04-harness-module.md` |
| 启动 | 生成 agent_teams 模块文档 | `05-agent-teams-module.md` |
| 启动 | 生成 agent_evolving 与 dev_tools 模块文档 | `06-agent-evolving-and-dev-tools-module.md` |
| 启动 | 生成 extensions 与 rsi 模块文档 | `07-extensions-and-rsi-module.md` |
| 启动 | 生成依赖关系文档（内部依赖图 + 外部依赖 + 入口点） | `08-dependencies.md` |
| 启动 | 生成运行方式文档（安装/配置/CLI/编程式/测试/质量） | `09-running-guide.md` |

### 阶段五：基线记录与路标（当前阶段）

| 时间 | 动作 | 产出文件 |
|------|------|----------|
| 启动 | 获取项目仓库 git log（最近 20 提交） | 确认基线 `bad6b4a4` |
| 启动 | 获取分支状态与 tag 描述 | 确认 `develop` 领先 origin 4 提交，`v0.1.16.post1-95-gbad6b4a4` |
| 启动 | 生成本路标文档 | `00-roadmap-and-incremental-update.md` |

---

## 三、本次任务产出物清单

### 3.1 文档文件清单

输出目录：`D:\jiuwen\main\yoskills\jiuwen\agent-core-docs`

| 文件 | 内容 | 字数估算 |
|------|------|----------|
| `README.md` | 文档导航索引、项目速览、快速开始 | 短 |
| `00-roadmap-and-incremental-update.md` | 本文件：任务时间线、基线、增量更新流程 | 中 |
| `01-project-overview.md` | 项目定位、核心能力、特性、技术栈、仓库结构 | 中 |
| `02-overall-architecture.md` | 分层架构、10 大设计模式、运行时数据流、关键概念 | 长 |
| `03-core-module.md` | core 层 16 个子模块的职责、关键类、设计模式 | 长 |
| `04-harness-module.md` | harness 层 11 个子模块（DeepAgent/任务循环/Rails/工具/安全/CLI 等） | 长 |
| `05-agent-teams-module.md` | 多智能体团队框架（TeamAgent/MCP/CLI/数据模型） | 长 |
| `06-agent-evolving-and-dev-tools-module.md` | 自演进框架与调优工具，含 symphony 简介 | 中 |
| `07-extensions-and-rsi-module.md` | A2A 集成与 RSI 评估优化框架 | 长 |
| `08-dependencies.md` | 内部依赖图、外部依赖表、可选依赖组、入口点 | 长 |
| `09-running-guide.md` | 安装、配置、3 个 CLI 入口、编程式使用、测试、代码质量 | 长 |

### 3.2 文档特性

- **语言**：简体中文
- **路径引用**：使用 `file:///` 绝对路径，可点击直接跳转到源码位置
- **代码引用**：使用反引号包裹类名/函数名（如 `DeepAgent`）
- **设计模式**：以加粗标注（如 **Card/Config 分离**）
- **导航**：README.md 提供完整目录与链接
- **基线对齐**：基于 `bad6b4a4`（2026-08-04 17:39 +0800）提交的源码状态

---

## 四、后续增量更新流程（标准操作）

> 当项目仓库有新提交时，按以下流程更新本套文档。

### 4.1 更新前准备

1. **拉取最新代码**：
   ```bash
   cd D:\jiuwen\main\agent-core
   git fetch origin
   git log origin/develop -n 20 --pretty=format:"%h|%ad|%s" --date=iso
   ```
2. **确定更新范围**：对比本路标文档"上次更新基线"与当前 HEAD，所有晚于基线的提交纳入更新范围。
3. **更新本路标文档**：先在本文件"五、更新记录"表追加一行，记录本次更新的基线提交与时间。

### 4.2 提交分类与文档映射

按提交信息的 conventional commit 前缀与涉及路径，映射到对应文档：

| 提交前缀/关键词 | 影响路径 | 目标文档 |
|-----------------|----------|----------|
| `feat(core)` / `fix(core)` / 路径含 `openjiuwen/core/` | `openjiuwen/core/**` | `03-core-module.md` |
| `feat(harness)` / `fix(harness)` / 路径含 `openjiuwen/harness/` | `openjiuwen/harness/**` | `04-harness-module.md` |
| `feat(team)` / `fix(agent-team)`/`fix(agent_teams)` / 路径含 `openjiuwen/agent_teams/` | `openjiuwen/agent_teams/**` | `05-agent-teams-module.md` |
| `feat(evolving)` / `fix(evolving)` / 路径含 `openjiuwen/agent_evolving/` 或 `dev_tools/` | `openjiuwen/agent_evolving/**`、`openjiuwen/dev_tools/**` | `06-agent-evolving-and-dev-tools-module.md` |
| `feat(rsi)` / `fix(rsi)` / 路径含 `openjiuwen/rsi/` 或 `extensions/` | `openjiuwen/rsi/**`、`openjiuwen/extensions/**` | `07-extensions-and-rsi-module.md` |
| `feat(symphony)` / 路径含 `openjiuwen/symphony/` | `openjiuwen/symphony/**` | `06-agent-evolving-and-dev-tools-module.md`（symphony 小节） |
| 依赖变更（`pyproject.toml`） | `pyproject.toml` | `08-dependencies.md` |
| CLI/Makefile/测试配置变更 | `pyproject.toml`、`Makefile`、`tests/` | `09-running-guide.md` |
| 架构规则变更 | `.claude/rules/`、`AGENTS.md` | `02-overall-architecture.md`、`01-project-overview.md` |
| 新增/删除顶层模块 | `openjiuwen/` 顶层 | `01-project-overview.md`（仓库结构）、`02-overall-architecture.md`、可能新增模块文档 |
| 版本号变更 | `pyproject.toml` `[project].version` | `01-project-overview.md`、本路标文档 |

### 4.3 更新步骤（每次增量）

1. **获取新提交列表**：
   ```bash
   # 上次基线为 bad6b4a4，查看其后所有提交
   git log bad6b4a4..HEAD --pretty=format:"%h|%ad|%s" --date=iso
   ```
2. **按提交逐条分析**：
   - 查看提交 diff：`git show <hash> --stat`（查看影响文件）
   - 查看具体改动：`git show <hash> -- <path>`
3. **按 §4.2 映射更新对应文档**：
   - 新增类/函数 → 在对应模块文档的"关键类/函数"表追加行
   - 删除类/函数 → 移除对应行
   - 重命名 → 更新类名与文件路径
   - 行为变更 → 更新对应方法说明
   - 新增子模块 → 在模块总览表追加行，并补充子模块章节
4. **更新依赖关系**（若 `pyproject.toml` 变更）：
   - 核心依赖变更 → 更新 `08-dependencies.md` §8.2.1
   - 可选依赖组变更 → 更新 §8.2.2
   - 入口点变更 → 更新 §8.3
5. **更新运行方式**（若 CLI/Makefile/测试变更）：
   - 新增命令 → 更新 `09-running-guide.md` §9.4
   - 测试结构变更 → 更新 §9.6
6. **更新本路标文档**：
   - 在"五、更新记录"表追加一行
   - 更新"1.2 项目仓库基线提交"为新 HEAD
7. **一致性校验**：
   - 校验 README.md 导航链接与文件名一致
   - 校验文档标题（`# NN -`）与文件名一致
   - 校验 `file:///` 路径指向真实存在的文件

### 4.4 增量更新检查清单

每次更新完成后，逐项确认：

- [ ] 本路标文档"更新记录"表已追加新行
- [ ] 本路标文档"基线提交"已更新为新 HEAD
- [ ] 涉及的模块文档已更新关键类/函数表
- [ ] `08-dependencies.md` 与最新 `pyproject.toml` 一致
- [ ] `09-running-guide.md` 与最新 CLI/Makefile 一致
- [ ] `01-project-overview.md` 仓库结构与最新目录一致
- [ ] README.md 导航链接全部有效
- [ ] 新增的 `file:///` 路径指向真实文件

---

## 五、更新记录

> 每次增量更新后在此表追加一行。最新行在最上方。

| 更新序号 | 更新日期 | 更新人 | 基线提交（旧） | 基线提交（新） | 更新文档 | 更新摘要 |
|----------|----------|--------|----------------|----------------|----------|----------|
| 0（初版） | 2026-08-05 | TRAE Assistant | — | `bad6b4a4`（2026-08-04 17:39 +0800） | 全部 10 个文档 | 首次生成完整 Code Wiki：项目概述、整体架构、core/harness/agent_teams/agent_evolving/dev_tools/extensions/rsi 模块、依赖关系、运行方式 |

---

## 六、附录：常用 git 命令速查

```bash
# 查看当前基线
git -C "D:\jiuwen\main\agent-core" log -1 --pretty=format:"%H|%ad|%s" --date=iso

# 查看基线之后的所有提交（增量范围）
git -C "D:\jiuwen\main\agent-core" log bad6b4a4..HEAD --pretty=format:"%h|%ad|%s" --date=iso

# 查看某提交影响的文件
git -C "D:\jiuwen\main\agent-core" show <hash> --stat

# 查看某提交的具体 diff
git -C "D:\jiuwen\main\agent-core" show <hash> -- openjiuwen/<module>/

# 查看分支状态
git -C "D:\jiuwen\main\agent-core" status --short --branch

# 查看 tag 描述
git -C "D:\jiuwen\main\agent-core" describe --tags --always

# 按路径查看提交历史
git -C "D:\jiuwen\main\agent-core" log --oneline -- openjiuwen/core/ | head -20
```

---

## 七、附录：文档与模块映射速查表

| 文档 | 对应源码路径 | 关键关注点 |
|------|--------------|------------|
| `01-project-overview.md` | `README.md`、`pyproject.toml`、`AGENTS.md`、`openjiuwen/` 顶层 | 项目定位、版本、顶层结构 |
| `02-overall-architecture.md` | `.claude/rules/architecture.md`、全模块 | 分层、设计模式、数据流 |
| `03-core-module.md` | `openjiuwen/core/**` | graph/workflow/runner/session/single_agent/context_engine/sys_operation/security |
| `04-harness-module.md` | `openjiuwen/harness/**` | deep_agent/task_loop/rails/tools/security/prompts/workspace/goal/lsp/cli |
| `05-agent-teams-module.md` | `openjiuwen/agent_teams/**` | agent/cli/mcp/models/runtime/schema/tools/messager |
| `06-agent-evolving-and-dev-tools-module.md` | `openjiuwen/agent_evolving/**`、`openjiuwen/dev_tools/**`、`openjiuwen/symphony/**` | 自演进、调优、能力编排 |
| `07-extensions-and-rsi-module.md` | `openjiuwen/extensions/**`、`openjiuwen/rsi/**`、`openjiuwen/auto_harness/**` | A2A、RSI 评估、auto_harness |
| `08-dependencies.md` | `pyproject.toml` | 内部依赖图、外部依赖、可选依赖、入口点 |
| `09-running-guide.md` | `pyproject.toml`、`Makefile`、`tests/`、`deploy/` | 安装、CLI、编程式、测试、质量 |
