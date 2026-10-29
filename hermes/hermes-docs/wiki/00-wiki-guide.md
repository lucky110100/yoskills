# Hermes Agent Code Wiki — 路标与增量更新指南

> 本文档集由 code-wiki-author 技能生成，记录文档化任务的时间线、基线提交、产物清单与增量更新流程。
> 交叉引用：[01-项目概述](01-project-overview.md) | [02-整体架构](02-overall-architecture.md)

## 关于 Code Wiki

Code Wiki 是 Hermes Agent 项目的"活文档"。它与仓库内已有的两类文档形成互补而非重叠：[AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L1-L40) 是**意图层**，定义"我们想要什么、不想要什么"的贡献准则与设计哲学；`website/` 下的 Docusaurus 站点是**用户面向**的产品文档，讲"怎么用"；而 Code Wiki 是**实现面向**的，讲"代码长什么样、为什么这么长、改它要注意什么"。三者读者不同：AGENTS.md 给贡献者，website 给终端用户，Code Wiki 给需要深入源码的维护者与二次开发者。

本篇作为路标，定义了文档集的边界、基线、阅读顺序，以及最关键的——当主分支向前推进时，如何用最小代价把增量同步回文档。三项原则贯穿全 Wiki：

1. **以基线为锚**：所有行号、规模数字、模式举证都锚定到一个具体提交，演进时只读增量 diff。
2. **举证优先**：每个设计模式、每个关键概念都用 `file:///` 链接到源码行，读者可一键验证。
3. **窄腰部同理**：文档本身也遵循"核心窄、能力在边缘"——02 架构篇保持精炼，子系统细节下沉到 03-15。

## 一、基线信息

| 字段 | 值 |
|------|-----|
| 项目 | Hermes Agent ☤ (Nous Research) |
| 仓库 | https://github.com/NousResearch/hermes-agent |
| 基线提交 | `fa83af3f9a42790730b8966ff67e7d9fb627899f` |
| Tag | `v2026.8.3-1455-gfa83af3f9` |
| 分支 | main |
| 时间 | 2026-08-13 03:16:25 -0700 |
| 技术栈 | Python 3.11-3.13 + TypeScript (Ink/React/Electron) |
| 规模 | ~4091 Python + ~2087 TS/TSX + ~2938 测试文件 |
| 入口点 | `hermes` / `hermes-agent` / `hermes-acp` |

基线是文档的"零点"。所有行号引用、模块边界描述、设计模式举证都以这个提交为准。基线由 [pyproject.toml](file:///D:\yaodh\main\hermes-agent\pyproject.toml#L364-L367) 的三个 console scripts 锚定入口点，由 [AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L15-L26) 锚定设计哲学。一旦主分支推进，增量更新流程（第四节）会以基线为锚点计算 diff，避免重复扫描整个仓库。

刷新基线的时机：完成一轮增量更新后、或在主分支发生重大重构（如 mixin 拆分、目录迁移）后。刷新动作只是把本表四字段（提交、Tag、分支、时间）换成新 HEAD，但前提是第七节已登记了从旧基线到新基线的全部变更。

## 二、产物清单

Wiki 共 17 篇文档：00-15 编号文档 + 1 篇 README。编号即推荐阅读顺序——从全景到子系统，从稳定层到易变层。

| 序号 | 文档 | 路径 | 行数 | 内容简介 |
|------|------|------|------|----------|
| 00 | 路标与增量更新指南 | wiki/00-wiki-guide.md | ~250 | 基线、产物清单、导航、增量更新流程与提交映射 |
| 01 | 项目概述 | wiki/01-project-overview.md | ~360 | 定位、能力、技术栈、仓库结构、入口点、快速开始 |
| 02 | 整体架构 | wiki/02-overall-architecture.md | ~470 | 分层、十大设计模式、运行时数据流、进程模型 |
| 03 | agent 模块 | wiki/03-agent-module.md | — | 运行时心脏：AIAgent、上下文引擎、记忆、estop |
| 04 | tools 工具系统 | wiki/04-tools-module.md | — | 自注册注册表、Toolset、Surface Gate、MCP 客户端 |
| 05 | gateway 消息网关 | wiki/05-gateway-module.md | — | 20+ 平台适配器、TurnRunner、GatewayRunner mixin |
| 06 | hermes_cli CLI | wiki/06-cli-module.md | — | HermesCLI 门面、子命令、配置管理 |
| 07 | plugins 插件 | wiki/07-plugins-module.md | — | 第三方能力发现、scoped 注册、覆盖策略 |
| 08 | cron 调度 | wiki/08-cron-module.md | — | 周期任务、crontab 解析、并发保护 |
| 09 | providers 推理后端 | wiki/09-providers-module.md | — | ProviderProfile 声明式配置、failover |
| 10 | acp_adapter ACP | wiki/10-acp-module.md | — | Agent Client Protocol 适配层 |
| 11 | TUI (tui_gateway + ui-tui) | wiki/11-tui-module.md | — | Ink TUI、双进程后端、节点桥接 |
| 12 | web 仪表盘 | wiki/12-web-module.md | — | localhost SPA + API、dashboard |
| 13 | apps/desktop | wiki/13-desktop-module.md | — | Electron 三进程、SSH 远程运行时 |
| 14 | website 文档站 | wiki/14-website-module.md | — | Docusaurus、开发者指南、用户指南 |
| 15 | 测试与质量保障 | wiki/15-testing-quality.md | — | ~2938 测试、concurrent gate、供应链安全 |
| 16 | README 快速入门 | README.md | — | 安装、配置、首个会话、FAQ |

> 注：03-15 + README 由后续轮次生成，行数"—"表示尚未生成。生成完成后应回填实际行数。本表给出预期边界，便于增量更新时定位目标文档。

文档生命周期：每篇文档有"待生成 / 已生成 / 已校准 / 已过时"四态。本篇第六节检查清单第 5 条要求产物清单的行数列与实际同步，是状态管理的抓手。当某篇文档连续两次增量更新都未被触碰，应在第七节标注"需复核"，提示可能已过时。

## 三、文档导航

**新手路径**：01 项目概述 → 02 整体架构 → 03 agent 模块 → README 快速入门。前三篇建立全景，第三篇切入运行时心脏，再回到 README 动手实践。这条路径假设读者只想要"理解它是什么、怎么跑起来"。

**贡献者路径**：00 本篇（增量流程）→ 02 整体架构（设计模式）→ AGENTS.md（意图层）→ 目标子系统文档。贡献前必读 [AGENTS.md](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L181-L205) 的 Footprint Ladder，判断新能力应该落在哪一级 rung——这决定了你的 PR 是该加 core tool、写 plugin、还是做成 MCP server。

**维护者路径**：00 本篇 → 直接跳到第四节增量更新流程 → 第五节提交映射表。日常维护的主要动作是"取 diff → 查映射 → 改对应文档 → 追加更新记录"，不需要重读全景文档。维护者还应熟悉第六节检查清单，作为每次更新后的收尾自检。

**跨语言路径**：Python 后端开发者从 03-10 入手；TypeScript 前端开发者从 11-13 入手；两端协作点在 11（TUI 双进程）与 13（Desktop 三进程），那里解释了 Node 与 Python 进程的边界契约。

每篇文档顶部都有一行交叉引用，指向上下游文档。文档内的代码引用采用 `file:///` 绝对路径，可直接点击跳转到源码行。链接文本统一用 basename（文件名或类名），不裹反引号，以保证渲染为可点击链接。

## 四、增量更新流程

增量更新的核心思想：**以基线为锚，只读增量，只改受影响文档**。避免每次都全量重扫仓库。完整八步如下：

```
1. 取增量        git log --oneline fa83af3f9a42790730b8966ff67e7d9fb627899f..HEAD
2. 取 diff       git diff --stat <基线>..HEAD -- <路径模式>
3. 查映射表      第五节：把每个提交特征 → 目标文档
4. 定位改动      打开目标文档，按行号区间局部修订（行号会漂移，重新 grep 校准）
5. 校验链接      所有 file:/// 引用的行号对当前 HEAD 重新核对
6. 追加记录      第七节追加一行：日期 | 基线→新基线 | 摘要 | 文档
7. 更新基线      把本篇第一节的基线提交换成新 HEAD
8. 自检          第六节 8 项检查清单逐条核对
```

逐步说明：

- **第 1 步取增量**：用 `git log --oneline` 列出基线之后的提交。提交量大时可加 `--since` 限定时间窗。对每条提交读其 message，判断是否触及 Wiki 覆盖的模块。
- **第 2 步取 diff**：对疑似相关的提交，用 `git diff --stat <基线>..HEAD -- <路径>` 看变更行数分布。例如 `-- tools/ gateway/` 可快速判断工具与网关层是否受影响。
- **第 3 步查映射**：把第 1 步的提交指纹（路径 + 意图）对到第五节路由表。一个提交可能命中多张文档——跨文档影响必须全部登记。
- **第 4 步定位改动**：打开目标文档。注意行号会漂移，**不要沿用旧行号**，必须用 Grep 在当前 HEAD 重新定位锚点后再局部修订。
- **第 5 步校验链接**：本篇文档所有 `file:///...#L` 引用对当前 HEAD 重新核对。这是举证优先原则的硬要求——悬空锚点会误导读者。
- **第 6 步追加记录**：第七节追加一行。摘要写"改了什么"，文档列写"动了哪几篇"。
- **第 7 步更新基线**：把第一节四字段换成新 HEAD。这一步必须在第 6 步之后，确保记录里能看到旧→新的完整跨度。
- **第 8 步自检**：逐条过第六节清单。

关键纪律：行号引用会随提交漂移。文档中凡是写"~12k 行"这类规模数字，应在重大重构后用 `wc -l` 复核，避免数字失真误导读者。

## 五、提交→文档映射表

按提交的"指纹"（改动路径 + 意图）归类到目标文档。这是增量更新的路由表。

| 提交特征 | 影响路径 | 目标文档 |
|----------|----------|----------|
| AIAgent 类、对话循环、tool dispatch | run_agent.py | 03-agent-module |
| 工具注册、Toolset、Surface Gate | tools/registry.py, toolsets.py | 04-tools-module |
| 平台适配器新增/修改 | gateway/platforms/* | 05-gateway-module |
| TurnRunner/GatewayRunner mixin 拆分 | gateway/run.py | 05-gateway-module |
| CLI 子命令、配置 | cli.py, hermes_cli/* | 06-cli-module |
| 插件发现、scoped 注册 | plugins/* | 07-plugins-module |
| 周期任务、crontab | cron/* | 08-cron-module |
| ProviderProfile、failover | providers/*, agent/error_classifier.py | 09-providers-module |
| ACP 协议 | acp_adapter/* | 10-acp-module |
| Ink TUI、tui_gateway | ui-tui/*, tui_gateway/* | 11-tui-module |
| 仪表盘 SPA | web/* | 12-web-module |
| Electron 主进程/SSH | apps/desktop/* | 13-desktop-module |
| Docusaurus 文档 | website/* | 14-website-module |
| 测试夹具、concurrent gate | tests/* | 15-testing-quality |
| 设计哲学、Footprint Ladder | AGENTS.md | 02-overall-architecture |
| 入口点、依赖锁定 | pyproject.toml | 01-project-overview |
| estop sentinel、紧急停止 | agent/estop.py | 03-agent-module |

路由优先级：**最具体的子系统文档优先**。全景文档（02 整体架构）只在设计模式本身被改动时更新，避免每次小改动都动全景。例如新增一个平台适配器只动 05；只有当 [gateway/platforms/base.py](file:///D:\yaodh\main\hermes-agent\gateway\platforms\base.py#L2884) 的 `BasePlatformAdapter(ABC)` 契约本身变化时，才同时动 02 的"ABC + orchestrator"模式举证。

跨文档影响处理：当改动同时触及多个 Wiki 层（如改 [tools/registry.py](file:///D:\yaodh\main\hermes-agent\tools\registry.py#L426) 既影响 02 的"自注册单例注册表"模式、又影响 04 的注册表细节），需在两个文档都登记变更，并在第七节摘要里列出全部受影响文档。

## 六、更新检查清单（8项）

每次增量更新后逐条核对。这八条是"举证优先"与"以基线为锚"两条原则的落地自检：

1. **基线已更新**：第一节基线提交字段已替换为新 HEAD，Tag、分支、时间戳已刷新。
2. **行号已校准**：所有 `file:///...#L` 引用对当前 HEAD 重新 grep 过，无悬空锚点。
3. **规模数字已复核**：~12k 行、~17k 行、~26k 行等数字在重大重构后用 `wc -l` 重新统计。
4. **交叉引用闭环**：每篇顶部交叉引用指向的文档确实存在，无断链。
5. **产物清单同步**：第二节表格行数列已填实际行数（生成完整后回填）。
6. **更新记录已追加**：第七节已登记本轮变更，含日期、基线→新基线、摘要、文档列表。
7. **设计模式举证有效**：02 文档引用的模式对应文件/行号未被删除或重命名。
8. **新增模块已纳入**：若 HEAD 新增了顶层目录或入口点，已在本表与 01 仓库结构补登。

任何一条不达标，本轮增量更新不算完成。这是质量门，而非建议。

## 七、更新记录

| 日期 | 基线→新基线 | 变更摘要 | 更新文档 |
|------|-------------|----------|----------|
| 2026-08-13 | — → fa83af3 | 初始生成 00-02 三篇基础文档，建立路标、概述、架构全景 | 00, 01, 02 |

> 后续每次增量更新在此追加一行。最早的记录在最上，新的在表格底部追加，保持时间线自上而下递增。摘要应具体到"改了什么"，避免"更新了文档"这类空话；文档列用逗号分隔多篇。

## 八、文档约定与术语

### 链接约定

- **代码引用**：`[basename](file:///D:\yaodh\main\hermes-agent\相对路径#L起始-L结束)`，链接文本用 basename（文件名或类名/方法名），不裹反引号，以保证渲染为可点击链接。
- **行号区间**：优先给范围 `#L120-L150` 而非单行 `#L120`，让读者看到完整上下文。
- **交叉引用**：Wiki 内部引用用相对路径 `[02-整体架构](02-overall-architecture.md)`，不写 `file:///`。

### 规模数字约定

文中 `~12k 行` 这类数字是基线时刻的统计，用 `~` 表示近似。它们会随提交漂移，重大重构后必须复核（见检查清单第 3 条）。基线时刻已知规模：[run_agent.py](file:///D:\yaodh\main\hermes-agent\run_agent.py#L412) 中 [AIAgent](file:///D:\yaodh\main\hermes-agent\run_agent.py#L412) 类约 12k 行；[cli.py](file:///D:\yaodh\main\hermes-agent\cli.py#L4267) 中 [HermesCLI](file:///D:\yaodh\main\hermes-agent\cli.py#L4267) 约 17k 行；[gateway/run.py](file:///D:\yaodh\main\hermes-agent\gateway\run.py#L5923) 约 26k 行。

### 关键术语速查

| 术语 | 一句话解释 | 详见 |
|------|-----------|------|
| Footprint Ladder | 新能力的六级决策阶梯，优先选最小 footprint 的 rung | [AGENTS.md#L181-L205](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L181-L205) |
| 窄腰部 | 核心保持精简，能力尽量在边缘（CLI/插件/MCP） | [AGENTS.md#L23-L26](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L23-L26) |
| Prompt Caching | 按会话复用已缓存前缀，不可中途破坏 | [AGENTS.md#L18-L22](file:///D:\yaodh\main\hermes-agent\AGENTS.md#L18-L22) |
| Surface Gate | 工具可见性是会话属性而非进程环境变量 | 02 架构篇 |
| Toolset | 命名工具集合，平台会话按需折叠 | 04 tools 篇 |
| estop | Fail-Safe 紧急停止 sentinel 文件 | [agent/estop.py#L37](file:///D:\yaodh\main\hermes-agent\agent\estop.py#L37) |

术语表随子系统文档生成持续扩充。新增术语应回填本表，保证全 Wiki 术语一致。
## 九、常见问题（FAQ）

**Q1：增量更新时一个提交同时命中多篇文档怎么办？**
A：在所有命中文档都登记，并在第七节摘要列出全部文档。路由优先级（第五节）只解决"主目标"，不豁免跨文档影响。

**Q2：行号引用总是漂移，为什么不改成只引用文件不引用行号？**
A：行号是举证优先原则的核心。只引文件等于"在某处有这段代码"，读者仍需自己找；引行号是"在 [run_agent.py#L412](file:///D:\yaodh\main\hermes-agent\run_agent.py#L412) 定义 AIAgent"，一步到位。漂移成本由增量更新流程第 4、5 步吸收。

**Q3：规模数字（~12k 行）多久复核一次？**
A：常规增量更新不必每次复核；仅在"重大重构"后复核——判定标准是单次提交改动行数 > 500，或涉及 mixin 拆分 / 目录迁移 / 大段删除。

**Q4：Wiki 与 website 文档重复了怎么办？**
A：Code Wiki 讲"实现与为什么"，website 讲"怎么用"。若内容重叠，归到 website，Wiki 只保留实现视角的交叉引用，避免双份维护。

**Q5：新模块加进来了，Wiki 怎么追？**
A：检查清单第 8 条要求补登。具体：01 仓库结构加一行、本篇产物清单加一行（若有新顶层目录）、提交映射表加一行路由。若新模块值得独立成篇，顺延编号（如 16、17）。

## 十、校验命令速查

增量更新时常用的 shell 命令（PowerShell 友好）：

```
git log --oneline fa83af3f9a42790730b8966ff67e7d9fb627899f..HEAD   # 取增量提交
git diff --stat fa83af3..HEAD -- tools/ gateway/                    # 看特定目录 diff
git diff fa83af3..HEAD -- run_agent.py                              # 看单文件 diff
(Get-Content <file>).Count                                          # 核对文档行数
Select-String -Path <file> -Pattern 'class AIAgent'                 # 重新定位行号锚点
```

行号校准的金标准是 Grep 工具（见增量流程第 4 步），它返回当前 HEAD 的真实行号，不受旧文档漂移影响。