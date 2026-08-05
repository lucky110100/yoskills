# TRAE 任务执行深度分析报告

> **分析时间**: 2026-06-25 22:00  
> **分析对象**: TRAE CN (国内版) 近两天的日志、编辑历史、会话记录、沙箱追踪  
> **分析范围**: 2026-06-24 16:39 ~ 2026-06-25 21:47 的完整任务执行数据  
> **核心项目**: D:\jiuwen\main\agent-core-java (Java Sandbox/SysOp 开发)

---

## 一、数据全景

### 1.1 数据源总览

| 数据源 | 路径 | 大小 | 行数 | 说明 |
|--------|------|------|------|------|
| AI Agent stdout日志 | `logs/20260624T163916/Modular/ai-agent_stdout.log` | **41.82MB** | 147,933行 | 核心对话、工具调用、错误记录 |
| AI Agent stderr日志 | 同目录`_stderr.log` | 0KB | 0 | 无stderr输出 |
| 主进程日志 | `main.log` | 899KB | 5,825行 | IDE主进程运行日志 |
| 渲染器日志 | `renderer.log` | 1.72MB | 12,873行 | UI层交互日志 |
| CKG日志 | `ckg_stdout.log` | 88.8MB | - | 代码知识图谱服务日志 |
| 编辑历史 | `User/History/` | 46目录 | 224条 | AI+手动编辑追踪 |
| 沙箱追踪 | `Temp/trae_sandbox_trace_*.jsonl` | 273文件 / 0.89MB | ~290事件 | Sandbox SDK执行追踪 |
| 全局存储 | `globalStorage/storage.json` | - | - | 用户状态、模型配置 |

### 1.2 会话与任务规模

| 指标 | 数值 | 说明 |
|------|------|------|
| 独立会话(session_id) | **73** | 不同对话会话 |
| 独立追踪(trace_id) | **7,817** | 每次请求的唯一追踪 |
| 编辑历史会话 | **46** (近2天: **17**) | 文件修改记录 |
| 总编辑条目 | **224** | AI编辑109 + 手动95 + undo 5 + FastApply 5 |
| 沙箱实例(近2天) | **24** | 每个都发生了crash |
| 日志覆盖时间 | ~29小时 | 2026-06-24 16:39 → 2026-06-25 21:47 |

---

## 二、工具调用详细分析

### 2.1 工具调用分布 (近2天, Agent日志)

| 工具名称 | ToolCall次数 | 占比 | 说明 |
|----------|-------------|------|------|
| **Read** | 19 | 31.7% | 文件内容读取，最频繁的工具 |
| **Grep** | 11 | 18.3% | 正则表达式搜索 |
| **SearchReplace** | 10 | 16.7% | 文件内容编辑/替换 |
| **RunCommand** | 9 | 15.0% | 终端命令执行 |
| **Glob** | 4 | 6.7% | 文件名模式匹配 |
| **TodoWrite** | 3 | 5.0% | 任务列表管理 |
| **LS** | 2 | 3.3% | 目录列表浏览 |
| **SearchCodebase** | 1 | 1.7% | 语义级代码搜索 |
| **WebSearch** | 1 | 1.7% | 网络搜索 |
| **合计** | **60** | 100% | |

### 2.2 搜索类 vs 修改类操作比率

| 类别 | Agent日志关键词计数 | 比率 |
|------|---------------------|------|
| 搜索类 (search/grep/glob/read) | **995** | **5.2x** |
| 修改类 (apply/SearchReplace) | **191** | **1x** |

> **解读**: AI执行一次修改前平均需要5.2次搜索操作来确认上下文。这说明AI的"理解-修改"流程存在大量重复搜索。

### 2.3 上下文估算 (按工具调用推算)

每次工具调用会向LLM prompt注入不同大小的上下文:

| 工具 | 单次预估上下文 | 调用次数 | 总预估注入 |
|------|----------------|----------|------------|
| Read | ~2KB | 19 | ~38KB |
| Grep | ~1KB | 11 | ~11KB |
| SearchReplace | ~1.5KB | 10 | ~15KB |
| RunCommand | ~2KB | 9 | ~18KB |
| Glob | ~0.5KB | 4 | ~2KB |
| 其他 | ~1KB | 7 | ~7KB |
| **合计** | - | 60 | **~91KB** |

> 单次对话周期内，仅工具返回就注入约91KB上下文。加上系统提示、历史消息、resolver结果，总prompt估计在150-250KB。

### 2.4 工具调用间隔时间

| 统计 | 秒数 |
|------|-------|
| 平均间隔 | ~8.5秒 |
| 最大间隔 | ~120秒 |
| 最小间隔 | ~0.5秒 |

> 工具调用间隔反映了LLM思考+生成时间。平均8.5秒意味着每一步AI都在认真分析，但也说明流程较长。

---

## 三、耗时分析

### 3.1 各阶段耗时 (Agent日志 timing事件)

| 阶段 | 平均(ms) | 最大(ms) | 最小(ms) | 采样数 |
|------|----------|----------|----------|--------|
| **LLM首Token响应** | **3,809** | **14,559** | 1,288 | 30 |
| Context Resolver总耗时 | **720** | **11,640** | 1 | 32 |
| LLM生成Plan项 | 151 | 366 | 121 | 13 |
| 渲染用户提示 | 76 | 232 | 43 | 13 |
| Plan前准备 | 52 | 72 | 44 | 13 |
| 获取历史消息 | 3.5 | 12 | 1 | 32 |
| 获取会话 | 8.6 | 51 | 2 | 32 |
| 创建消息 | 3.9 | 11 | 1 | 32 |
| 创建Turn | 9.1 | 25 | 5 | 32 |

### 3.2 一次完整对话的典型时间线

```
用户发送消息 → 3ms(chat_begin)
             → 9ms(get_session)
             → 4ms(get_history)
             → 4ms(create_message)
             → 720ms(resolve_contexts) ← 最大可11.6秒!
             → 9ms(create_turn)
             → 76ms(render_prompt)
             → 52ms(before_generate)
             → 151ms(generate_plan)
             → 3,809ms(llm_first_token) ← 最大可14.6秒!
             → [streaming response + tool calls]
             → 8.5s avg per tool call
             → [repeat cycle for multi-step tasks]
```

**总耗时估算**:
- 单步任务(1次工具调用): ~5-8秒 (首Token + 工具执行 + 第二次LLM)
- 多步任务(5次工具调用): ~50-80秒
- 复杂任务(10+次工具调用): ~2-5分钟

### 3.3 编辑历史中的任务时长

近2天最耗时编辑:

| 文件 | 编辑数 | 有效间隔 | AI:手动 | 问题分析 |
|------|--------|----------|---------|----------|
| SandboxFsOperation.java | 10 | ~9.7小时 | 10:0 | 纯AI反复修改同一文件 |
| SandboxExample.java | 8 | ~30小时 | 8:0 | AI反复调试示例代码 |
| HashUtil.java | 13 | ~18分钟 | 9:4 | AI+用户紧密协作返工 |
| SysOperationProvide.java | 6+3 | 8+28分钟 | 9:0 | 分两轮修改同类文件 |
| SandboxCodeOperation.java | 4 | ~1分钟 | 4:0 | 快速连续AI修改 |

---

## 四、Context Resolver 详细分析

TRAE每次对话前执行18个Resolver阶段收集上下文:

| Resolver阶段 | 完成数 | 平均耗时 | 必要性评估 |
|--------------|--------|----------|-----------|
| code_user_message | 32 | 2.1ms | ✅ 核心 |
| code_selection | 32 | 45.5ms | ✅ 核心(但采样仅2) |
| code_current_editor | 32 | 3.1ms | ✅ 核心 |
| user_interaction_context | 19 | **46.9ms** | ⚠️ 最耗时,最大197ms |
| terminal_context | 32 | 1.8ms | ✅ 有用 |
| lint_error_context | 32 | - | ✅ 有用 |
| problem_context | 32 | - | ✅ 有用 |
| file_diff | 32 | - | ✅ 有用 |
| web_search | 32 | 1.3ms | ❌ 大多数对话不需要 |
| user_image | 32 | - | ❌ 近2天未使用 |
| user_attachment | 32 | - | ❌ 近2天未使用 |
| user_comment_datasheet | 32 | - | ❌ 未使用 |
| slash_command | 32 | - | ❌ 未使用 |
| custom_rules | 32 | - | ⚠️ 偶尔有用 |
| log_message | 32 | 1.5ms | ⚠️ 低频有用 |
| external_document | 32 | - | ❌ 未使用 |
| code_browser_selection | 32 | 1.3ms | ❌ 未使用 |
| user_comment_datamarkdown | 32 | - | ❌ 未使用 |

**问题**: 18个阶段**每次都全部执行**，即使大多数对话只用到5-6个核心阶段。这浪费了约60-70%的Resolver时间。

---

## 五、关键问题识别

### 🔴 P1: 沙箱崩溃率 = 100%

**数据**: 近2天24个沙箱追踪，**每个都以 `sandbox_sdk_crash` 开始**。

**崩溃密度**:
- 2026-06-25 00:13~00:15: 7次崩溃 (间隔10秒)
- 2026-06-24 23:35~23:52: 7次崩溃
- 2026-06-24 21:40~21:51: 5次崩溃
- 2026-06-24 19:38: 2次崩溃

**崩溃模式**: 每次沙箱创建后立即crash，然后重新初始化(init_info → used_info → process_state)。这意味着**每个命令执行都在不稳定的环境中运行**。

**影响**:
1. 工具调用(RunCommand等)可能在崩溃中丢失结果
2. 需要反复重建沙箱，增加延迟
3. 文件操作可能不完整

### 🔴 P2: Job状态持久化失败 = 20,626次

**数据**: `Failed to persist job state` 错误在Agent日志中出现20,626次。

```
Failed to persist job state job_id=job-dc1d8e09f5554316a1e925ac5e7b0492
error=系统找不到指定的路径。 (os error 3)
```

**频率**: 每5秒重复一次，从06-24 16:39持续到06-25 21:47。

**根因**: 使用了 `YAODON~1` (8.3短路径名)而非完整路径 `yaodonghai`，导致路径找不到。

**影响**: 任务状态无法持久化，意味着:
- 长时间任务无法恢复
- 任务进度无法正确追踪
- 子Agent状态可能丢失

### 🟡 P3: 高返工率 — 同文件反复修改

**返工Top 5**:

| 文件 | 总编辑 | AI编辑 | 手动编辑 | undo | 分析 |
|------|--------|--------|----------|------|------|
| SandboxFsOperation.java | 10 | 10 | 0 | 0 | AI反复10次修改 |
| HashUtil.java | 13 | 9 | 4 | 0 | AI+用户反复调整 |
| SandboxExample.java | 8 | 8 | 0 | 0 | 纯AI反复修改 |
| SysOperationProvide.java | 9 | 9 | 0 | 0 | 两轮修改同类 |
| SandboxCodeOperation.java | 4 | 4 | 0 | 0 | 快速连续修改 |

**返工模式分析**:
- **"试探性修改"模式**: AI先做小修改→发现不够→再修改→再发现新问题→继续修改
- **"上下文不完整"模式**: AI没有一次性理解完整文件结构，逐步发现需要修改的位置
- **"用户反馈驱动"模式**: 用户手动修改4次(HashUtil.java)，每次手动修改后AI又需要适应

### 🟡 P4: LLM响应延迟波动大

| 指标 | 值 |
|------|-----|
| 最小首Token | 1.3秒 |
| 平均首Token | 3.8秒 |
| **最大首Token** | **14.6秒** |
| 最大Resolver | 11.6秒 |

**最差情况**: 用户发送消息 → 等Resolver 11.6秒 → 等LLM 14.6秒 = **首响应需26.2秒**

### 🟡 P5: SearchCodebase使用率极低

| 搜索工具 | 使用次数 | 效率 |
|----------|----------|------|
| Read | 19 | 低(逐文件读取) |
| Grep | 11 | 中(精确搜索) |
| Glob | 4 | 低(仅文件名) |
| **SearchCodebase** | **1** | **高(语义搜索)** |

SearchCodebase是最高效的代码理解工具，一次调用可以获取跨文件的语义相关代码。但使用率仅1.7%。

### 🟢 P6: 网络和路径问题

| 问题类型 | main.log计数 |
|----------|-------------|
| network错误 | 191 |
| 路径找不到(os error 3) | 10 |
| CKG健康检查失败(ECONNREFUSED) | 1 |
| cue-server超时 | 1 |
| CPU profile上传失败 | 1 |

### 🟢 P7: 临时文件堆积

- 273个sandbox trace文件堆积在Temp目录
- 大量.tmp和.wct临时文件
- ToolcallOutput目录不存在(路径问题)

---

## 六、优化建议与新方法

### 6.1 🎯 修复沙箱崩溃 [P1]

**根因**: sbox_version 1.4.4.0 在Windows环境下可能存在兼容性问题。

**建议**:
1. 检查沙箱SDK是否需要升级到支持Windows长路径的版本
2. 在sandbox.json中添加更多显式权限路径
3. 配置沙箱使用完整路径而非8.3短路径名
4. 设置定期清理Temp目录的cron任务

**预期效果**: 消除100%崩溃率，工具调用成功率提升，减少重建延迟。

### 6.2 🎯 修复路径持久化问题 [P2]

**根因**: 使用 `YAODON~1` 短路径导致 `os error 3`。

**建议**:
1. 在TRAE配置中禁用8.3短路径名: `fsutil 8dot3name set D: 0`
2. 或修改job持久化路径使用完整用户目录名
3. 创建缺失的 `trae\toolcall-output` 目录

**预期效果**: 消除20,626次持久化失败，任务状态可靠保存。

### 6.3 🎯 "预搜索-批量修改"策略 [P3]

**当前模式** (低效):
```
Read文件A → 理解 → 修改A → 发现问题 → Read文件A → 再修改A → Read文件B → 修改B → ...
```

**新模式** (高效):
```
1. SearchCodebase(语义搜索) → 一次性获取所有相关代码上下文
2. TodoWrite → 规划所有修改点和顺序
3. 并行Read(仅修改目标文件) → 确认修改位置
4. 批量SearchReplace → 一次性完成所有修改
5. RunCommand(编译/测试) → 验证结果
6. 只在验证失败时才回退修正
```

**预期效果**: 
- 减少50%搜索步骤
- 减少70%返工次数
- 单文件修改次数从平均5次降到2次

### 6.4 🎯 优化Context Resolver [P4]

**当前**: 18个阶段每次全量执行，总耗时最大11.6秒。

**建议**:
1. **分级Resolver**: 简单查询只执行5个核心阶段(code_user_message, code_selection, code_current_editor, terminal_context, problem_context)
2. **缓存机制**: 对lint_error_context, custom_rules等缓存结果，文件修改时失效
3. **延迟加载**: web_search, user_image等只在明确需要时才执行
4. **增量更新**: 后续对话只更新变化的部分上下文

**预期效果**: Resolver平均耗时从720ms降到200ms，最大从11.6秒降到3秒。

### 6.5 🎯 模型响应优化 [P5]

**当前**: GLM-5.1首Token最大14.6秒。

**建议**:
1. **简单任务用快速模型**: 单文件修改、代码解释 → Doubao-Seed-Code(~1.3秒)
2. **复杂任务用强模型**: 多文件重构、架构设计 → GLM-5.1
3. **Prompt精简**: 减少不必要的Resolver结果注入，控制prompt在100KB以内
4. **流式优化**: 确保流式Token传输不被中断(沙箱崩溃可能影响流式传输)

### 6.6 🎯 搜索策略优化 [P6]

**当前**: Read(31.7%) > Grep(18.3%) > SearchReplace(16.7%) > SearchCodebase(1.7%)

**建议的新搜索优先级**:
```
1. SearchCodebase → 语义搜索(首选，一次获取跨文件上下文)
2. Grep → 精确搜索(辅助，定位特定模式)
3. Read → 只在确认需要修改时才读取
4. Glob → 只在需要发现文件时使用
```

**预期效果**: 搜索步骤减少40%，上下文理解更完整。

### 6.7 🎯 "错误早发现"策略 [P7]

**当前**: 修改→发现问题→undo→再修改(返工循环)

**新模式**:
```
1. 修改前: RunCommand(mvn compile) → 确认当前编译状态
2. 规划修改: TodoWrite → 列出所有修改点
3. 执行修改: SearchReplace → 批量修改
4. 修改后: RunCommand(mvn compile + test) → 立即验证
5. 验证失败: 在当前步骤内修正，而非undo重做
```

**预期效果**: undo操作从5次降到0-1次，返工率降低60%。

---

## 七、量化优化预期

| 优化项 | 当前 | 优化后 | 改善幅度 |
|--------|------|--------|----------|
| 沙箱崩溃率 | 100% | 0% | **消除** |
| 搜索:修改比率 | 5.2:1 | 2:1 | **减少62%** |
| 同文件返工次数 | 平均5次 | 平均2次 | **减少60%** |
| Resolver平均耗时 | 720ms | 200ms | **减少72%** |
| Resolver最大耗时 | 11.6秒 | 3秒 | **减少74%** |
| LLM首Token最大 | 14.6秒 | 5秒 | **减少66%** |
| 单步任务总耗时 | 5-8秒 | 2-4秒 | **减少50%** |
| 多步任务总耗时 | 2-5分钟 | 1-2分钟 | **减少50%** |
| 持久化失败 | 20,626 | 0 | **消除** |
| undo操作 | 5次/2天 | 0-1次/2天 | **减少80%** |

---

## 八、具体执行计划

### Phase 1: 系统修复 (立即执行)

1. **修复路径问题**: 
   ```powershell
   fsutil 8dot3name set D: 0  # 禁用8.3短路径
   mkdir "C:\Users\yaodonghai\AppData\Local\Temp\trae\toolcall-output"  # 创建缺失目录
   ```

2. **清理临时文件**:
   ```powershell
   del "C:\Users\yaodonghai\AppData\Local\Temp\trae_sandbox_trace_*"  # 清理273个trace文件
   ```

3. **升级沙箱SDK**: 检查TRAE CN版本1.0.31是否包含更新的sbox_version

### Phase 2: 工作流优化 (本周执行)

1. **创建项目规则文件** `.trae/rules/project_rules.md`:
   - 指定优先使用SearchCodebase而非Read+Grep
   - 指定修改前先规划(TodoWrite)
   - 指定修改后立即验证(RunCommand)
   - 指定避免同文件反复修改

2. **创建Skill文件** 针对Java项目的修改流程:
   - 预搜索→批量修改→验证的标准流程

### Phase 3: Context优化 (持续改进)

1. 监控Resolver耗时，识别哪些阶段对当前项目有价值
2. 根据项目类型调整Resolver执行策略
3. 定期分析编辑返工率，评估优化效果

---

## 九、附录: 数据源路径

| 数据 | 绝对路径 |
|------|----------|
| TRAE CN配置 | `C:\Users\yaodonghai\.trae-cn\` |
| TRAE CN数据 | `C:\Users\yaodonghai\AppData\Roaming\Trae CN\` |
| Agent数据库(加密) | `C:\Users\yaodonghai\AppData\Roaming\Trae CN\ModularData\ai-agent\database.db` |
| 编辑历史 | `C:\Users\yaodonghai\AppData\Roaming\Trae CN\User\History\` |
| 日志目录 | `C:\Users\yaodonghai\AppData\Roaming\Trae CN\logs\` |
| 沙箱追踪 | `C:\Users\yaodonghai\AppData\Local\Temp\trae_sandbox_trace_*.jsonl` |
| 沙箱配置 | `C:\Users\yaodonghai\.trae-cn\sandbox.json` |
| Skill配置 | `C:\Users\yaodonghai\.trae-cn\skill-config.json` |
| 用户Skills | `C:\Users\yaodonghai\.agents\skills\` |
| 全局存储 | `C:\Users\yaodonghai\AppData\Roaming\Trae CN\User\globalStorage\storage.json` |

---

## 十、总结

本次分析覆盖了TRAE CN近两天的147,933行Agent日志、46个编辑历史会话、273个沙箱追踪文件，识别出**7个关键问题**和**6个优化方向**。

**最严重的两个系统性问题**:
1. **沙箱100%崩溃率** — 每个命令执行环境都不稳定
2. **20,626次持久化失败** — 任务状态无法保存

**最影响效率的工作流问题**:
3. **高返工率** — 同文件平均被修改5次
4. **搜索效率低** — 搜索:修改比率5.2:1，SearchCodebase仅用1次

**优化后预期**: 总体任务完成时间减少约50%，返工率降低60%，搜索效率提升62%。

建议优先执行Phase 1(系统修复)，然后Phase 2(工作流优化)，持续Phase 3(Context优化)。
