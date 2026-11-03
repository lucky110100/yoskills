# LiteLLM 工具与技能使用统计报告（去重修正版）

> 数据目录：`D:\yaodh\data\hw_litellm_call\2026-09-28`
> 首次分析：2026-11-02 ｜ 去重修正：2026-11-03
> 详情文件数：318（另含 1 个索引文件 `request_list.json`，未计入统计）

---

## 〇、修正说明（必读）

本报告是 2026-11-02 版的**去重修正版**。原版存在一处根本性统计错误，导致工具调用总数被放大约 **77 倍**。

| 项目 | 原版 | 本版（修正后） |
|------|------|---------------|
| 工具调用总次数 | 24,734 | **316** |
| 统计口径 | `messages_json` 累计 + `response_json` 累计，直接相加 | 按 `tool_call_id` 全局去重 |
| Session C 可用工具数 | 35 | **31** |

### 错误成因

LiteLLM 的调用详情文件保存的是**完整请求快照**——每个文件都携带从会话第一轮到当前轮的全部历史消息。因此同一笔工具调用会在该会话后续的每一个文件里重复出现：

```
调用 #1 发生 → 出现在文件 1
调用 #2 发生 → 文件 2 同时包含 #1 和 #2
调用 #3 发生 → 文件 3 同时包含 #1、#2、#3
...
```

实测：**平均每个 `tool_call_id` 被 77.3 个文件重复记录，最高的一个被 194 个文件记录。**

原版统计方式是：
```
24,418 (messages_json 累计，含 77 倍重复)
+   316 (response_json 累计，又重复计一遍当前轮)
= 24,734
```

两个来源相加的算术结果与原文数字完全吻合，证明这就是原版的统计路径——**既没有跨文件去重，又把同一批调用重复加了两遍**。

### 正确的去重方法

以 `tool_calls[].id`（形如 `call_fbd9bd5d67a942b4a7a455d0`）为全局唯一键，跨全部 318 个文件取并集：

- 该 id 由 LLM 生成，同一笔调用在不同文件中的 id 完全一致，天然可作去重依据
- 已验证 24,418 条 `tool_calls` **全部带 id，0 条缺失**，不存在无法去重的脏数据
- 交叉验证：去重后唯一 id 数 = `response_json` 中 tool_calls 总数 = 独立 `tool` 消息数 = **316**，三方完全吻合
- 跨会话 id 交集均为 0（A∩B = A∩C = B∩C = 0），去重无污染

---

## 一、会话分组概览

依据 `messages_json` 中消息顶层的 `conversationRequestId` 字段分组：

| 会话 | 文件数 | LLM 调用数 | 真实工具调用数 | 模型 | conversationRequestId | 场景 |
|------|-------:|-----------:|---------------:|------|----------------------|------|
| **Session A** | 195 | 195 | **211** | glm-5.2 | `01a0e74498327d2f8db2b184a9a16a0b` | WorkBuddy Agent，代码合并任务 |
| **Session B** | 74 | 74 | **79** | glm-5.2 | `01a0e69fcb157ee8870a1df68b1377c2` | WorkBuddy Agent，服务重启任务 |
| **Session C** | 48 | 48 | **26** | glm-5.3-flash ×47 / glm-5.2 ×1 | 无 | Hermes Agent，金融新闻 / 日报 Skill 调用 |
| **标题生成** | 1 | 1 | **0** | glm-5.2 | 无（msg_count=2，仅 system+user） | 会话标题生成辅助调用 |
| **合计** | **318** | **318** | **316** | glm-5.2 ×270 / glm-5.3-flash ×48 | — | — |

**关键说明**：
- `session_id`（LiteLLM 顶层字段）318 个文件各不相同，是网关层的请求 ID，不能用于业务会话分组。
- `conversationRequestId` 是消息顶层字段（`msg.get('conversationRequestId')`），不在 `metadata` 中。
- 数据中**不存在 `conv_set` / `conv_round` / `turn` 等轮次字段**。每个详情文件 = 一次 LLM 调用，文件间的先后顺序用顶层 `start_time` 排序即可，无需用 `msg_count` 近似。
- `request_list.json` 是 318 条调用的索引，非调用详情，已排除。
- 标题生成文件（`0217905864261623...e4f53.json`）只含 1 条 system + 1 条 user 消息，**无 assistant 消息**，故 `messages_json` 中无任何 tool_calls，`tool_names_json` 为 null。

### 1.1 各会话资源消耗

| 会话 | LLM 调用 | 工具调用 | 工具/调用 | 时间跨度 | 输入 token | 输出 token | 费用 | 累计耗时 |
|------|-------:|--------:|---------:|---------|----------:|----------:|-----:|--------:|
| Session A | 195 | 211 | 1.08 | 71.2 min | 18,731,874 | 35,790 | $27.40 | 1,139 s |
| Session B | 74 | 79 | 1.07 | 14.6 min | 4,738,143 | 11,469 | $6.93 | 364 s |
| Session C | 48 | 26 | 0.54 | 431.6 min | 1,265,913 | 112,345 | $0.30 | 2,539 s |
| 标题生成 | 1 | 0 | 0.00 | — | 559 | 132 | $0.001 | 6 s |
| **合计** | **318** | **316** | **0.99** | — | **24,736,489** | **159,736** | **$34.63** | **4,048 s** |

> 注：输入 token 累计高达 2,474 万，正是消息累积的直接体现——同一份历史被反复计费。Session A 单会话 1,873 万输入 token 却只产出 35,790 输出 token，输入/输出比 523:1。

---

## 二、工具调用频次统计（去重口径）

统计方法：

1. 遍历全部 318 个文件的 `messages_json`，收集所有 `role=assistant` 消息中 `tool_calls[].id`
2. 以 `id` 为键在**全部文件范围内**去重（不是文件内去重）
3. 用每个唯一 id 首次出现的 `function.name` 归类

**总计：316 次真实工具调用，涉及 14 种工具。**

| # | 工具名 | 真实次数 | 占比 | Session A | Session B | Session C | 原版（未去重） | 膨胀 |
|---|--------|--------:|-----:|----------:|----------:|----------:|--------------:|-----:|
| 1 | `Bash` | **190** | 60.1% | 132 | 58 | 0 | 16,624 | 87.5x |
| 2 | `Read` | **51** | 16.1% | 45 | 6 | 0 | 4,104 | 80.5x |
| 3 | `Edit` | **25** | 7.9% | 25 | 0 | 0 | 2,283 | 91.3x |
| 4 | `execute_code` | **12** | 3.8% | 0 | 0 | 12 | 58 | 4.8x |
| 5 | `PowerShell` | **9** | 2.8% | 0 | 9 | 0 | 382 | 42.4x |
| 6 | `browser_navigate` | **6** | 1.9% | 0 | 0 | 6 | 28 | 4.7x |
| 7 | `browser_console` | **6** | 1.9% | 0 | 0 | 6 | 17 | 2.8x |
| 8 | `TaskUpdate` | **4** | 1.3% | 4 | 0 | 0 | 359 | 89.8x |
| 9 | `TaskOutput` | **3** | 0.9% | 0 | 3 | 0 | 125 | 41.7x |
| 10 | `TaskStop` | **3** | 0.9% | 0 | 3 | 0 | 48 | 16.0x |
| 11 | `Write` | **3** | 0.9% | 3 | 0 | 0 | 137 | 45.7x |
| 12 | `TaskCreate` | **2** | 0.6% | 2 | 0 | 0 | 245 | 122.5x |
| 13 | `session_search` | **1** | 0.3% | 0 | 0 | 1 | 3 | 3.0x |
| 14 | `write_file` | **1** | 0.3% | 0 | 0 | 1 | 5 | 5.0x |
| | **合计** | **316** | 100% | 211 | 79 | 26 | 24,418 | **77.3x** |

### 关键发现

1. **Bash 是绝对主力**：190 次，占真实调用 60.1%。Session A 单会话 132 次，反映代码合并任务大量依赖命令行（git 操作、进程检查、文件查找等）。

2. **膨胀倍数暴露工具差异**：`TaskCreate` 膨胀 122.5x 最高，`browser_console` 2.8x 最低。原因在于会话的**调用密度**——Session A/B 有 195/74 次 LLM 调用而工具调用稀疏（平均 1.08 次/调用），历史积累极深，放大幅度巨大；Session C 工具集中在少数轮次，且单会话只有 48 次调用，放大幅度自然小得多。

3. **工具使用高度会话化**：
   - Session A（代码合并）：`Bash` 132 + `Read` 45 + `Edit` 25 + `TaskUpdate` 4 + `Write` 3 + `TaskCreate` 2，典型代码编辑工作流。
   - Session B（服务重启）：`Bash` 58 + `PowerShell` 9 + `Read` 6 + `TaskOutput` 3 + `TaskStop` 3，偏运维执行与后台任务管理。
   - Session C（金融新闻）：`execute_code` 12 + `browser_navigate` 6 + `browser_console` 6 + `session_search` 1 + `write_file` 1，Hermes Agent 用代码执行抓取 RSS / 搜索。

4. **两套工具体系零交集**：Session A/B 的 23 个工具（Read/Write/Edit/Glob/Grep/Bash/PowerShell/Task* 等）与 Session C 的 31 个工具（browser_*/execute_code/feishu_*/skill_* 等）**完全没有重叠**，分属两个不同的 Agent 平台。

5. **`Edit` 仅出现在 Session A**（25 次），Session B 全程未用——服务重启任务不涉及源码编辑，只改配置或重启进程。

6. **工具调用与 LLM 调用近乎 1:1**：316 次工具调用 / 318 次 LLM 调用 = 0.99。说明绝大多数 LLM 调用只发起 1 个工具，多工具并行的情况较少（仅 27 轮）。

---

## 三、并发调用分析

一次 LLM 响应中可能同时包含多个 `tool_calls`（并行工具调用）。

统计：281 个文件的 `response_json` 含 tool_calls（占 318 的 88.4%），其余 37 个文件是纯文本响应（会话收尾或标题生成）。

| 单轮 tool_calls 数 | 轮次 | 贡献调用数 |
|------------------:|-----:|----------:|
| 1 | 254 | 254 |
| 2 | 20 | 40 |
| 3 | 6 | 18 |
| 4 | 1 | 4 |
| **合计** | **281** | **316** |

- **并行轮次仅 27 轮，占 9.6%**，但贡献了 62 次调用（19.6%）
- 最多一次并行发起 4 个工具
- 并行调用全部集中在 Session A（多文件并行读取/编辑场景），Session C 为 0

> 算术自校验：254×1 + 20×2 + 6×3 + 1×4 = 254 + 40 + 18 + 4 = **316** ✓

---

## 四、可用工具列表统计

统计来源：每个文件 `tool_names_json` 字段（**该字段是"系统提供了哪些工具"，与是否被调用无关，是文件级存在性统计，不涉及去重问题**）。

### 4.1 Session A / B 共享工具集（WorkBuddy Agent）

出现在 269 个文件中（Session A 195 + Session B 74），工具集完全一致：

| 工具名 | 文件数 | 工具名 | 文件数 |
|--------|-------:|--------|-------:|
| `Read` | 269 | `TaskCreate` | 269 |
| `Write` | 269 | `TaskGet` | 269 |
| `Edit` | 269 | `TaskUpdate` | 269 |
| `Glob` | 269 | `TaskOutput` | 269 |
| `Grep` | 269 | `TaskList` | 269 |
| `Bash` | 269 | `WebFetch` | 269 |
| `PowerShell` | 269 | `WebSearch` | 269 |
| `DeferExecuteTool` | 269 | `AskUserQuestion` | 269 |
| `automation_update` | 269 | `Skill` | 269 |
| `present_files` | 269 | `Agent` | 269 |
| `show_widget` | 269 | `ToolSearch` | 269 |
| `widget_guidelines` | 269 | | |

共 **23 个**工具，Session A 与 Session B 完全相同。

> 值得注意：`Glob` / `Grep` / `WebFetch` / `WebSearch` / `AskUserQuestion` / `DeferExecuteTool` / `automation_update` / `present_files` / `show_widget` / `widget_guidelines` / `Agent` / `ToolSearch` / `TaskGet` / `TaskList` 这 14 个工具虽然可用，但**全程零调用**——实际只用了 23 个可用工具中的 9 个。

### 4.2 Session C 工具集（Hermes Agent）

出现在 25 个文件中（另 23 个 Session C 文件 `tool_names_json` 为 None / 空）：

| 工具名 | 工具名 | 工具名 |
|--------|--------|--------|
| `browser_back` | `browser_snapshot` | `process` |
| `browser_click` | `browser_type` | `read_file` |
| `browser_console` | `browser_vision` | `search_files` |
| `browser_get_images` | `delegate_task` | `session_search` |
| `browser_navigate` | `execute_code` | `skill_manage` |
| `browser_press` | `feishu_doc_read` | `skill_view` |
| `browser_scroll` | `feishu_drive_add_comment` | `skills_list` |
| `memory` | `feishu_drive_list_comment_replies` | `terminal` |
| `patch` | `feishu_drive_list_comments` | `text_to_speech` |
| `todo` | `feishu_drive_reply_comment` | `vision_analyze` |
| `write_file` | | |

共 **31 个**工具（原报告写 35 个，已修正）。

> Session C 虽然提供 `skill_view` / `skills_list` / `skill_manage` 三个 Skill 管理工具，但**均未被实际调用**——Skill 通过消息注入方式触发（见第五章）。

### 4.3 标题生成

1 个文件，`tool_names_json` 为 None（纯文本补全，无工具）。

---

## 五、Skill 调用统计

### 5.1 通过 `Skill` 工具调用

**结果：0 次。**

`Skill` 工具出现在 Session A/B 共 269 个文件的可用工具列表中，但在全部 318 个文件中**从未被实际调用**（去重后的 316 次调用中无 `Skill`）。Session A/B 的任务（代码合并、服务重启）均通过 Bash/Read/Edit 等基础工具直接完成。

### 5.2 通过消息注入方式调用（Session C）

Session C（Hermes Agent）的 Skill 通过 `user` 消息内容注入触发，消息中包含形如 `The user has invoked the "xxx" skill` 的指令：

| Skill 名 | 调用次数 | 涉及文件 | 会话 |
|----------|---------:|---------:|------|
| `a-share-market-analysis` | 12 | 12 | Session C |
| `ai-news-daily` | 9 | 9 | Session C |
| `financial-news-rss` | 4 | 4 | Session C |
| **合计** | **25** | 25 | Session C |

> 这 25 次是**唯一**的 Skill 调用记录。`tool_calls` 去重后的 316 次工具调用中不含任何 Skill 工具，所以 Skill 使用量就是 25 次，不存在重复计数问题。

### 5.3 关键发现

- **两种 Skill 调用机制并存**：
  - WorkBuddy Agent（Session A/B）：提供 `Skill` 工具入口，但本次未使用。
  - Hermes Agent（Session C）：不走工具调用，由系统在 `user` 消息中注入 `invoked the "xxx" skill` 指令，Agent 通过 `execute_code` 执行 Python 代码（内部调用 `hermes_tools.terminal` 等）完成 Skill 逻辑。
- Session C 的 `skill_view` / `skills_list` / `skill_manage` 工具虽然可用，本次也未调用——Skill 的实际执行完全由 `execute_code` 内嵌代码承担。
- **Skill 与工具调用的关系**：Session C 共 48 次 LLM 调用、26 次工具调用，却触发 25 次 Skill——说明一次 Skill 调用往往对应一次 `execute_code`，Skill 逻辑被压缩进单次代码执行中。

---

## 六、工具执行结果统计（去重口径）

统计来源：`role=tool` 消息的 `content` 字段，通过 `tool_call_id` 关联回唯一工具调用。**按去重后的 316 次调用统计，每次调用只取一次结果**（`tool_call_id` 去重，共 316 条 tool 消息，与 316 次调用**完全一一对应，无缺失**）。

判定规则（基于 content 前 100 字符小写）：
- **成功**：含 `successfully` / `success` / `complete` / `done` / `已` / `成功`
- **错误**：含 `error` / `failed` / `traceback` / `exception` / `not found` / `denied`
- **其他**：上述关键词均未命中（多数为命令输出正文，无明显成功/失败标志）

| 工具名 | 样本数 | 成功 | 错误 | 其他 | 错误率 | 均长 | 中位长 |
|--------|-------:|-----:|-----:|-----:|-------:|-----:|-------:|
| `Bash` | 190 | 2 | 9 | 179 | **4.7%** | 1,256 | 505 |
| `Read` | 51 | 0 | 4 | 47 | **7.8%** | 3,106 | 997 |
| `Edit` | 25 | 25 | 0 | 0 | 0% | 122 | 126 |
| `execute_code` | 12 | 12 | 0 | 0 | 0% | 5,039 | 3,743 |
| `PowerShell` | 9 | 0 | 0 | 9 | — | 555 | 162 |
| `browser_navigate` | 6 | 6 | 0 | 0 | 0% | 8,252 | 8,491 |
| `browser_console` | 6 | 6 | 0 | 0 | 0% | 2,005 | 2,737 |
| `TaskUpdate` | 4 | 0 | 0 | 4 | — | 22 | 22 |
| `TaskOutput` | 3 | 0 | 0 | 3 | — | 817 | 1,021 |
| `TaskStop` | 3 | 3 | 0 | 0 | 0% | 356 | 333 |
| `Write` | 3 | 3 | 0 | 0 | 0% | 136 | 158 |
| `TaskCreate` | 2 | 2 | 0 | 0 | 0% | 61 | 66 |
| `session_search` | 1 | 1 | 0 | 0 | 0% | 5,525 | 5,525 |
| `write_file` | 1 | 0 | 0 | 1 | — | 45 | 45 |
| **合计** | **316** | **54** | **13** | **249** | **4.1%** | — | — |

### 关键发现

1. **Bash 错误率 4.7%**（9 / 190）：真正的命令失败会返回非零退出码 + 错误信息，被关键词捕获的 9 次是显式报错。成功关键词命中仅 2 次，因为绝大多数 Bash 输出是命令正文，不带 "success" 字样。

2. **Read 错误率 7.8%**（4 / 51）：主要是文件不存在 / 路径错误，与代码合并任务中频繁探查文件相关。这是**唯一错误率高于 Bash 的工具**，符合"先猜路径再读、猜错重试"的探查式工作模式。

3. **零失败工具**：`Edit`(25) / `execute_code`(12) / `browser_navigate`(6) / `browser_console`(6) / `TaskStop`(3) / `Write`(3) / `TaskCreate`(2) / `session_search`(1) 全部成功，说明 Agent 对这些工具的使用前提判断准确。

4. **`PowerShell` 全部归为"其他"**：输出格式不含上述关键词，实际成功/失败需结合退出码判断（content 多为表格/列表正文）。

5. **结果长度分布**：
   - 短结果（中位 < 100 字符）：`TaskUpdate`(22)、`write_file`(45)、`TaskCreate`(66)、`Edit`(126)——多为确认性返回。
   - 中等结果（中位 300-1100）：`PowerShell`(162)、`TaskStop`(333)、`Bash`(505)、`Read`(997)、`TaskOutput`(1021)。
   - 长结果（中位 > 2000）：`browser_console`(2737)、`execute_code`(3743)、`browser_navigate`(8491)——浏览器快照和代码执行输出体量大。

6. **总计 13 次显式错误，占 316 的 4.1%**：整体工具可靠度高，Agent 未出现工具滥用或反复失败的情况。

---

## 七、工具调用时序模式

### 7.1 时序分析方法

每个详情文件 = 一次 LLM 调用，文件内 `response_json` 的 tool_calls 即"本次调用真实发起的工具"。按顶层 `start_time` 排序即得真实调用时序，**不再使用 `msg_count` 近似轮次**（原报告的做法）。

关键验证：**当前轮 tool_calls 数量与 msg_count 无关**——

| 会话 | msg_count ≤ 50 时平均当前轮工具数 | msg_count > 200 时平均当前轮工具数 |
|------|--------------------------------:|--------------------------------:|
| Session A | 1.27（22 个样本） | 1.06（102 个样本） |
| Session B | 1.17（23 个样本） | — |
| Session C | 0.54（48 个样本） | — |

后期文件虽然携带几百条历史消息，但每轮真实发起的工具调用数始终稳定在 1 左右。这从数据层面反证了：**按文件累加 tool_calls 会得到 77 倍的虚数，而 response_json 的口径（= 全局唯一 id 数 = 316）才是真实调用量。**

### 7.2 分阶段工具分布

把每个会话按时间顺序三等分，观察工具结构是否漂移：

**Session A（代码合并，195 次调用）**

| 阶段 | 调用数 | 工具数 | 主要工具 |
|------|-------:|-------:|----------|
| 早期 | 65 | 74 | `Bash` 49 (66%)、`Read` 13 (18%)、`Edit` 10 (14%)、`TaskCreate` 1 |
| 中期 | 65 | 73 | `Bash` 50 (68%)、`Read` 13 (18%)、`Edit` 6 (8%)、`TaskUpdate` 2 |
| 后期 | 65 | 64 | `Bash` 33 (52%)、`Read` 19 (30%)、`Edit` 9 (14%)、`Write` 2 |

**Session B（服务重启，74 次调用）**

| 阶段 | 调用数 | 工具数 | 主要工具 |
|------|-------:|-------:|----------|
| 早期 | 24 | 28 | `Bash` 22 (79%)、`Read` 3、`PowerShell` 2 |
| 中期 | 25 | 26 | `Bash` 13 (50%)、`PowerShell` 7 (27%)、`Read` 3、`TaskOutput` 2 |
| 后期 | 25 | 25 | `Bash` 23 (92%)、`TaskStop` 2 |

**Session C（金融新闻，48 次调用）**

| 阶段 | 调用数 | 工具数 | 主要工具 |
|------|-------:|-------:|----------|
| 早期 | 16 | 12 | `execute_code` 8 (67%)、`browser_navigate` 2、`session_search` 1、`write_file` 1 |
| 中期 | 16 | 0 | （全部纯文本响应） |
| 后期 | 16 | 14 | `browser_console` 6 (43%)、`execute_code` 4 (29%)、`browser_navigate` 4 (29%) |

### 关键发现

1. **Session A 工具结构稳定但有轻微漂移**：`Bash` 始终主导（52-68%），但后期从 66% 降到 52%，`Read` 从 18% 升到 30%——说明合并后半段转入**代码审查与验证**阶段，读文件多于跑命令。

2. **Session B 的 `PowerShell` 集中在中段**：27% 的占比只在中期出现，对应"服务停止-重启-检查"的运维节奏；后期回归纯 Bash（92%）。

3. **Session C 的中段完全无工具调用**：16 次连续调用全是纯文本响应，说明该阶段 Agent 在**汇总分析结果、生成报告文本**，属于金融日报的写作环节，不需要工具。

4. **三会话的工具/调用比差异显著**：A 1.08、B 1.07、C 0.54。Session C 有近一半的调用不带任何工具——这与"新闻抓取 + 长文本汇总"的任务特征吻合，输出 token 也印证了这点（C 输出 112,345 token，是 A 的 3.1 倍，尽管它的工具调用只有 A 的 1/8）。

---

## 八、总结

### 8.1 工具使用全景

| 维度 | Session A | Session B | Session C | 标题生成 |
|------|-----------|-----------|-----------|---------|
| 平台 | WorkBuddy Agent | WorkBuddy Agent | Hermes Agent | — |
| 模型 | glm-5.2 | glm-5.2 | glm-5.3-flash / glm-5.2 | glm-5.2 |
| LLM 调用数 | 195 | 74 | 48 | 1 |
| **真实工具调用数** | **211** | **79** | **26** | **0** |
| 主工具 | Bash / Read / Edit | Bash / PowerShell / TaskOutput | execute_code / browser_* | — |
| 可用工具数 | 23 | 23 | **31** | 0 |
| 实际使用工具种数 | 6 | 5 | 5 | 0 |
| Skill 调用 | 0（未用 Skill 工具） | 0（未用 Skill 工具） | 25（消息注入，3 种） | 0 |
| 输入 token | 18,731,874 | 4,738,143 | 1,265,913 | 559 |
| 输出 token | 35,790 | 11,469 | 112,345 | 132 |
| 费用 | $27.40 | $6.93 | $0.30 | $0.001 |

### 8.2 核心结论

1. **Bash 主导代码任务**：190 次 / 60.1%，是 WorkBuddy Agent 完成工程任务的核心工具。但注意——真实调用只有 190 次，而非原报告所称的 16,814 次。

2. **两套 Agent 工具体系完全隔离**：WorkBuddy Agent（23 个：Read/Write/Edit/Bash/Task*）与 Hermes Agent（31 个：execute_code/browser_*/feishu_*/skill_*）**零交集**，分属不同生态。

3. **Skill 调用机制差异显著**：
   - WorkBuddy Agent 提供 `Skill` 工具但本次未触发——23 个可用工具中只用了 9 个，任务用基础工具即可完成。
   - Hermes Agent 不走工具调用 Skill，而是系统层在 user 消息中注入 skill 指令，Agent 用 `execute_code` 内嵌 Python 执行。共 25 次，集中在 3 个金融类 Skill。

4. **工具错误率整体偏低**：总体 4.1%（13 / 316），Bash 4.7%、Read 7.8%，其余零失败，说明 Agent 对工具调用前提判断准确。

5. **工具调用与 LLM 调用近乎 1:1**（316 / 318 = 0.99），并行调用仅 27 轮（9.6%），多工具并行不是主要模式。

6. **成本被消息累积大幅放大**：输入 token 累计 2,474 万，对应 $34.63 费用。同一份历史被重复计费是主要原因——这既是统计陷阱，也是实际的成本结构。Session A 单会话 $27.40（占 79%），71 分钟的高频长上下文调用。

---

## 附录 A：统计口径对照表

后续分析同类日志时，按需求选择合适的口径：

| 口径 | 取值方式 | 数值 | 适用场景 |
|------|---------|-----:|---------|
| **真实调用数**（推荐） | 全局唯一 `tool_calls[].id` | **316** | 统计工具使用量、错误率、性能 |
| 当前轮调用数 | `response_json.choices[*].message.tool_calls` 求和 | 316 | 校验去重结果，二者应相等 |
| tool 消息数 | `role=tool` 消息按 `tool_call_id` 去重 | 316 | 校验结果完整性 |
| 累计计数（错误） | `messages_json` 全部 tool_calls 求和 | 24,418 | ❌ 仅用于度量"上下文体积"，不能当调用量 |
| 原报告口径（错误） | 累计 + response_json | 24,734 | ❌ 既重复又未去重，勿用 |

## 附录 B：去重代码片段

```python
import json, glob, os
from collections import Counter

DATA = r"D:\yaodh\data\hw_litellm_call\2026-09-28"
files = [f for f in glob.glob(os.path.join(DATA, "*.json"))
         if os.path.basename(f) != "request_list.json"]

id_info = {}   # 全局唯一 tool_call_id -> 工具名
for fp in files:
    with open(fp, encoding="utf-8") as fh:
        d = json.load(fh)
    for m in d.get("messages_json") or []:
        if m.get("role") != "assistant":
            continue
        for tc in (m.get("tool_calls") or []):
            tid = tc.get("id")
            if tid and tid not in id_info:
                id_info[tid] = (tc.get("function") or {}).get("name", "<unknown>")

# 去重后的真实调用统计
stats = Counter(id_info.values())
print(f"真实工具调用总数: {len(id_info)}")
for name, cnt in stats.most_common():
    print(f"  {name:20s} {cnt}")
```

> 核心要点：**去重必须在所有文件的并集范围内进行**。只在单个文件内去重（同一文件内 id 本就不重复）会得到无效结果，膨胀倍数仍是 1.0x——这是本次修正过程中踩过的坑。

## 附录 C：原版错误数据索引

原版报告中受影响的关键结论（均已在本版修正）：

| 原版位置 | 原版数值 | 修正后 |
|---------|---------|-------|
| 二、工具调用频次（总计） | 24,734 | 316 |
| 二、Bash 次数 | 16,814 | 190 |
| 二、Read 次数 | 4,155 | 51 |
| 二、Edit 次数 | 2,308 | 25 |
| 二、PowerShell 次数 | 391 | 9 |
| 二、TaskUpdate 次数 | 363 | 4 |
| 二、TaskCreate 次数 | 247 | 2 |
| 三、Session C 可用工具数 | 35 | 31 |
| 六、Bash 错误率 | 2.6%（基于 16,624 样本） | 4.7%（基于 190 样本） |
| 六、Read 错误率 | 5.3%（基于 4,104 样本） | 7.8%（基于 51 样本） |
| 七、时序分析 | 用 msg_count 近似轮次 | 用 start_time 真实排序 |
| 七、工具随轮次线性增长 | 结论错误（源于累积） | 每轮工具数恒为 ~1 |
