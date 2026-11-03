# LiteLLM 调用日志分析方法论 v1.0

> **来源**：基于 `2026-09-28` 目录（318 文件）的 10 轮递进式分析 + `hw_litellm_call` 全目录（18,195 文件）CodeCheck 规则统计的实战复盘
> **创建时间**：2026-11-02
> **v1.0 刷新**：2026-11-03（新增第零章 SOP、陷阱 8–13、效率复盘、故障速查表；原文内容完整保留）
> **目标**：为后续分析更多日期目录的 LLM 调用日志提供标准化、可复用、可校验的分析流程

### 版本修订记录

| 版本 | 日期 | 变更 |
|------|------|------|
| v0（无后缀原文件） | 2026-11-02 ~ 11-03 | 建立数据结构认知、7 步流程、关联键体系、陷阱 1–7、脚本模板 |
| **v1.0** | 2026-11-03 | 新增第零章「五条铁律 + 十阶段流水线」；新增陷阱 8–13（格式普查缺失、set 去重误用、伪问题污染、临时脚本口径分裂、完整性声明忽略、正则顺序）；新增 6.5–6.7 效率复盘与反模式；新增第十章实战复盘、第十一章故障速查表；形成历程补至 13 轮 |

### 阅读指引

- **第一次做某目录的分析** → 直接照第零章的十阶段流水线走，每阶段过卡点
- **遇到具体报错/数字对不上** → 查第十一章「故障速查表」
- **想理解为什么这么规定** → 看第四章陷阱 + 第十章实战复盘（有真实返工代价）

---

## 零、核心铁律与标准作业流程（v1.0 新增）

> 本章是全文的入口。**跳过本章直接看后面的章节，大概率会重犯 CodeCheck 统计里那三轮返工。**

### 0.1 五条铁律

| # | 铁律 | 违反后的真实代价（CodeCheck 统计，2026-11-03） |
|:-:|------|---------------------------------------------|
| 1 | **先找对账锚点，再写解析器** | 到收尾才在导出文件里发现 `Total rows: 360` 与 `=== Issues by Rule ===`。此前整个过程没有任何外部数字可以验证对错，只能靠"看起来合理" |
| 2 | **先普查格式，再写正则** | 直接照控制台表格的样子写了一版解析器，覆盖率 863/2279 就卡住。之后逐轮发现还有 5 种格式，**解析器重写 3 次**，仅这一项多花约 1 小时 |
| 3 | **一次抽取，缓存复用** | 每次改解析器都要重扫 18,195 个 JSON，单轮数分钟。后期引入 `inst.pkl` 后，改逻辑的重跑降到秒级 |
| 4 | **聚合前去重，去重用分组，不用 `set()`** | 业务身份不稳定（行号漂移 + 描述截断），单纯集合去重会同时「留下假重复」和「漏掉真合并」。最终靠 `group by (文件, 规则, 描述)` 才收口到 504 |
| 5 | **全部数字出自同一次运行** | 用临时脚本单独核算占比，导致 Top10 占比出现 45.2% / 46.0% 两个值、CMT.03 出现 212 / 211 两个值，**返工 9 类数字不一致** |

### 0.2 十阶段流水线（每阶段有卡点，卡点不过不许进下一阶段）

| 阶段 | 动作 | 卡点（通过标准） | 不通过怎么办 |
|:-:|------|----------------|------------|
| **0 锚点侦察** | 在数据里搜自带的对账声明：`Total rows`、`=== Issues by Rule ===`、`N issues`、导出脚本的汇总行、`request_list.json` 记录数 | 至少拿到 1 个可与解析结果比对的独立数字 | 确实没有就**明确记录"无锚点"**，改用内部一致性校验（各分类之和 = 总数） |
| **1 数据清点** | 文件数、时间跨度、模型分布、消息总量 | 文件数 == 索引记录数；记录增量缺口 | 缺口 > 0 则先解释缺口再继续 |
| **2 载体定位** | 按 `role` × 字段统计目标串（规则 ID / 工具名 / 关键词）出现次数 | 明确回答「真数据在哪个 role、由哪个工具产生」，并给出各 role 的次数对比 | 分不清就继续切分维度（工具名、时间、文件名） |
| **3 格式普查** | 把去重后的**唯一文本落盘**，按结构签名聚类，产出格式清单 | 每种格式 ≥1 个样本，**各格式样本数之和 == 唯一文本总数** | 有未归类样本 → 回到本阶段，不许带着"剩余的大概也是 A 格式"进解析 |
| **4 分格式解析** | 每格式一个解析器，按**特异性降序**匹配 | 成功解析条数 / 命中行数 ≥ 95%，且各格式计数器之和 == 总条数 | <95% → 回阶段 3；有未命中样本必须逐条看 |
| **5 归一化** | 路径归一（后缀匹配取最长）、描述归一（空白/大小写/标点）、编号归一 | 同一实体只剩一种写法 | 归一后数量明显减少 → 保留 `raw` 原值供审计，防过度合并 |
| **6 剔除伪问题** | 结构性过滤：必须是「文件 + 行号 + 规则 + 描述」四元组，且行号能在文件中落地 | 抽样 30 条人工复核，误收 = 0 | 有误收 → 收紧结构条件，不要靠关键词黑名单硬堵 |
| **7 分组去重** | 按**稳定三元组**（文件, 规则, 描述）建组，组内处理漂移（取 max）/ 截断（前缀合并 + 行号有交集才合并） | 两个口径（A 归并 / B 并集）都产出，且差值 100% 可归因 | 差值无法逐条解释 → 说明身份键选错，回阶段 6 |
| **8 一致性校验** | 锚点对账 + 子项求和 + 跨表交叉 + 膨胀倍数 | 4 项全过（见 8.1 校验清单） | 任一不过不许出报告 |
| **9 出报告** | 所有数字从 `result.json` 读取生成，不手写 | 全文无手写数字；随机抽 5 个数字回查脚本输出一致 | 有手写数字 → 改为脚本注入 |

### 0.3 阶段依赖关系：为什么不能跳

```
阶段0 锚点 ──────────────────────────┐
阶段1 清点 ──┐                       │
阶段2 载体 ──┴──> 阶段3 格式普查 ──> 阶段4 解析 ──> 阶段5 归一 ──> 阶段6 剔伪 ──> 阶段7 去重 ──> 阶段8 校验
                    ↑                    │                                              │
                    └──── <95% 回退 ─────┘                                              │
                                                                                        ↓
                                                                              阶段9 报告（数字全部来自校验后的产物）
```

**三个最常见的跳跃及其后果**：

1. **跳阶段 0**：全程无法判断解析对不对。CodeCheck 统计里，前期唯一能做的自检是"数字别太离谱"，而 225,154 这个数字恰恰"看起来像真实规模"，反而掩盖了错误。
2. **跳阶段 3**：等于赌"数据只有一种格式"。实际 6 种格式的样本占比是 A 370 / C 360 / B 100 / UI 88 / JSON 38 / IDX 26——**如果只认 A 格式，会漏掉 62% 的数据**。
3. **跳阶段 5**：119 种路径写法会被当成 119 个文件（真实 71 个），Top N 文件排行直接失真。

---

## 一、数据结构认知（分析前准备）

### 1.1 目录结构

```
hw_litellm_call/
├── 2026-09-28/
│   ├── request_list.json        ← 调用列表（每条记录 = 一次 LLM 调用）
│   ├── <request_id_1>.json      ← 调用详情（完整请求/响应）
│   ├── <request_id_2>.json
│   └── ... (N 个详情文件)
├── 2026-09-29/
└── ...
```

### 1.2 两个文件的角色

| 文件 | 角色 | 关键字段 |
|------|------|---------|
| `request_list.json` | **索引层** — 每次调用的摘要记录 | `request_id`, `start_time`, `model`, `prompt_tokens`, `completion_tokens`, `cost`, `duration_ms`, `session_id`, `status` |
| `<request_id>.json` | **详情层** — 完整请求/响应内容 | `messages_json`（消息列表）, `response_json`（LLM 响应）, `metadata_json`（元数据）, `tool_names_json`（可用工具） |

**关联方式**：`request_list.json` 的 `request_id` = 详情文件名去掉 `.json` 后缀，1:1 匹配。

### 1.3 详情文件顶层结构速查

```
<request_id>.json
├── 请求元信息：request_id, start_time, end_time, model, call_type, status, api_base
├── 性能指标：duration_s, ttft_s, completion_start_time
├── Token 与费用：prompt_tokens, completion_tokens, total_tokens, cost
├── 认证信息：key_name, key_hash, team_name, end_user
├── messages_json[]        ← 核心：消息列表（含 system/user/assistant/tool）
├── metadata_json{}        ← 核心：LiteLLM 内部元数据（用量、费用明细、模型映射）
├── response_json{}        ← 核心：LLM 响应（choices、usage、finish_reason）
├── tool_names_json[]      ← 可用工具名称列表
├── system_json            ← 通常 null（system prompt 在 messages_json[0] 中）
├── session_id             ← 每次调用唯一，不是持久会话标识
├── cache_hit / cache_key  ← 缓存信息
└── ...
```

### 1.4 消息结构（messages_json[n]）

```
messages_json[n]
├── role          ← "system" | "user" | "assistant" | "tool"
├── content       ← 消息内容（字符串，可能含 XML）
├── conversationRequestId  ← 【会话关联键】仅 user/assistant/tool 消息有
├── messageId     ← 消息唯一 ID
├── traceId       ← 追踪 ID（与 conversationRequestId 一一映射）
├── agent         ← Agent 标识（如 "cli"）
├── model         ← 消息级模型名
├── reasoning     ← 推理过程（assistant 消息）
├── tool_calls[]  ← 工具调用（assistant 消息，含 function.name/arguments/id）
├── tool_call_id  ← 工具调用 ID（tool 消息，对应 assistant 的 tool_calls[].id）
└── ...
```

---

## 二、分析流程（7 步标准化流程）

### Step 1：数据清点

**目标**：确认文件数量、覆盖范围、1:1 匹配完整性。

```python
# 伪代码
files = glob("*.json") - {"request_list.json"}
req_list = json.load("request_list.json")
assert len(files) == len(req_list)  # 1:1 匹配验证
# 记录：总文件数、时间范围、模型分布
```

**产出**：文件总数、时间跨度、模型种类。

### Step 2：JSON Key 全量提取与统计

**目标**：递归遍历所有嵌套层级，提取完整 key path，按文件去重统计出现次数。

**关键规则**：
- 递归进入 dict 的每个 key 和 list 元素的结构
- 同一 key path 在同一文件中出现多次只算一次
- list 元素用 `[n]` 泛化索引（不区分第几个元素）
- 采样 list 前 5 个 + 最后 1 个元素以捕获结构变体

```python
def collect_keys(obj, prefix, keys_set):
    if isinstance(obj, dict):
        for k, v in obj.items():
            path = f"{prefix}.{k}" if prefix else k
            keys_set.add(path)
            collect_keys(v, path, keys_set)
    elif isinstance(obj, list) and len(obj) > 0:
        seen = set()
        for item in obj[:5]:
            collect_keys(item, f"{prefix}[n]", keys_set)
        if len(obj) > 5:
            collect_keys(obj[-1], f"{prefix}[n]", keys_set)
```

**产出**：key path 总数、按出现文件数排序的完整列表、按覆盖率分档的分布表。

**经验值**（318 文件基准）：
- 325 个唯一 key path
- 73%（237 个）出现在全部文件中
- `model_map_information.model_map_value` 下有 147 个子字段（占 45%），全是模型定价配置

### Step 3：Null Value 分析

**目标**：识别 value 为 null 的 key path，分类解释原因。

**方法**：
1. 遍历所有文件的所有 key path
2. 记录 value 为 null 的 path 及出现文件数
3. 按以下分类归因：
   - **功能未启用**：如 `batch_models`、`router_metadata`（非批量/非路由调用时为 null）
   - **成功时无错误**：如 `error_information`（成功调用时为 null）
   - **模型不支持**：如 `model_map_value` 下的定价/能力字段（该模型不支持的功能）
   - **配置缺失**：如 `team_name`（未设置团队归属）
   - **版本差异**：不同模型/版本的 LiteLLM 响应字段不同

**产出**：null path 总数、分类表、每个 null path 的文件覆盖率。

### Step 4：XML 内容检测与解析

**目标**：识别 JSON value 中的 XML 标签文档，提取 XML path 和内容摘要。

**方法**：
1. 遍历 `messages_json` 中每条消息的 `content` 字段
2. 用正则 `<([a-zA-Z_][\w-]*)[^>]*>` 检测 XML 标签
3. 提取标签名、所在 JSON path、出现次数
4. 重点解析：
   - `messages_json[0].content`（system prompt）— 通常包含 XML 标签体系
   - `messages_json[n].content`（user/tool 消息）— 可能含 `<system-reminder>` 等
   - `messages_json[n].tool_calls[n].function.arguments` — 工具调用参数（JSON 字符串）

**产出**：XML 标签清单、JSON path 与 XML path 的映射表、各标签的语义解释。

### Step 5：会话识别与关联键发现

**目标**：从 N 个独立调用中还原出"会话"维度的分组。

**这是最关键的一步。分 5 个子步骤：**

#### 5.1 候选关联键扫描

对所有顶层 key 和消息级 key，统计每个 key 的唯一值数量：

| 候选 key | 唯一值数 | 判断 |
|----------|---------|------|
| `session_id` | = 文件总数 | **每文件唯一，无关联性**，不是持久会话 ID |
| `request_id` | = 文件总数 | 每文件唯一，天然无关联性 |
| `model` | 1-3 个 | 全局相同（无法区分会话），或按模型区分 Agent 类型 |
| `key_name` / `key_hash` | 1 个 | 全局相同，无法区分 |
| `conversationRequestId` | < 文件总数 | **有效关联键**，需进一步分析 |
| `metadata_json.requester_ip_address` | 1 个 | 全局相同，无法区分 |

#### 5.2 conversationRequestId 深度分析

```python
# 对每个文件，提取其包含的全部 conversationRequestId 集合
for file in files:
    conv_ids = {msg.conversationRequestId for msg in file.messages if msg has conversationRequestId}
    file.conv_set = conv_ids
```

**关键模式识别**：
- **消息累积型会话**（WorkBuddy Agent Loop）：文件的 `conv_set` 大小递增（1→2→3→4→5），`messages_json` 长度也递增
- **独立调用型会话**（Hermes Agent Skill）：`conv_set` 为空，`messages_json` 长度固定（不累积）

#### 5.3 会话分组

按 `conv_set` 的成员关系分组：
- 包含相同 convReqId 的文件 → 同一会话
- `conv_set` 为空的文件 → 独立调用（Session C 类）

#### 5.4 会话级关联键验证（核心修正）

**关键发现（本方法论的核心）**：

> 由于消息累积机制，每个会话**第一轮的 conversationRequestId** 会出现在该会话的全部文件中（因为后续轮次的调用包含了之前所有轮次的消息）。因此，**第一轮的 convReqId 就是该会话的全局唯一关联键**。

验证方法：
```python
# 对每个 convReqId，统计它出现在多少个文件中
for crid in all_conv_ids:
    count = sum(1 for f in files if crid in f.conv_set)
    # 如果某个 crid 出现在该会话的全部文件中（如 195/195），它就是第一轮的 convReqId
```

**验证条件**（3 条同时满足）：
1. 在本会话中覆盖率 = 100%（出现在该会话全部文件中）
2. 在其他会话中覆盖率 = 0%（跨会话零泄漏）
3. 是结构化 JSON 字段（不是文本内容的子串）

#### 5.5 辅助区分维度

当 convReqId 不可用时（如 Session C 无 convReqId），使用以下维度区分会话：

| 维度 | 区分能力 | 使用方法 |
|------|---------|---------|
| `model` | 强 | 不同模型 = 不同 Agent（glm-5.2 = WorkBuddy, glm-5.3-flash = Hermes） |
| `system prompt` MD5 | 强 | 不同会话的 system prompt 内容不同（含不同 workspace 路径） |
| `messages_json` 长度 | 中 | 累积型会话长度递增，独立调用长度固定 |
| `Workspace Folder` | 强 | 嵌在 user 消息的 `<user_info>` XML 中，不同工作目录 = 不同会话 |
| `tool_names_json` | 弱 | 同类 Agent 相同，但 Session C 可能不同 |
| `metadata_json.requester_ip_address` | 弱 | 通常全局相同 |

### Step 6：调用链构建与可视化

**目标**：按时间序列还原每个会话的完整调用链。

#### 6.1 调用链构建

```python
# 按会话分组后，按 start_time 排序
session_files.sort(key=lambda f: f.start_time)

# 记录每条调用链的信息
for f in session_files:
    chain.append({
        "sequence": i,                    # 在会话中的序号
        "request_id": f.request_id,
        "start_time": f.start_time,
        "end_time": f.end_time,
        "msg_count": len(f.messages_json),  # 消息数（累积递增）
        "conv_set_size": len(f.conv_set),   # convReqId 数量（累积递增）
        "model": f.model,
        "finish_reason": f.response_json.choices[0].finish_reason,
        "prompt_tokens": f.prompt_tokens,
        "completion_tokens": f.completion_tokens,
        "cost": f.cost,
        "duration_s": f.duration_s,
    })
```

#### 6.2 消息累积模式识别

**累积型会话**（WorkBuddy Agent Loop）：
- 消息数从 2（system + user）开始，每次调用 +2 条（assistant + tool），逐步累积
- `conv_set` 大小从 1 递增到 N（N = 用户对话轮次数）
- 最后一个文件包含全部历史消息

**独立型会话**（Hermes Agent Skill）：
- 消息数固定（通常 2-18 条），不累积
- 无 `conversationRequestId`，无 `messageId`，无 `traceId`
- 每次调用独立

#### 6.3 时序图绘制

选择典型调用链，绘制时序图展示：
- 用户输入 → LLM 调用 → 工具执行 → 工具返回 → 下一次 LLM 调用 → ... → finish_reason=stop

### Step 7：报告生成

**标准报告结构**（9 章）：

| 章 | 标题 | 内容 |
|----|------|------|
| 一 | 目录结构概览 | 文件数量、匹配关系、命名规则 |
| 二 | JSON Key 结构与 Null Value 分析 | 顶层 key、null path 分类 |
| 三 | JSON Key 全量统计 | 递归嵌套 key path、按覆盖率分档 |
| 四 | JSON Value 中的 XML 文档解析 | XML 标签提取、path 映射 |
| 五 | 文件关联与调用链构建 | 关联键层次体系、会话分组 |
| 六 | 完整调用链示例 | 2 个典型调用链 |
| 七 | 调用时序图 | SVG 时序图 |
| 八 | 全量分析 | 会话分组详情、关联键结论 |
| 九 | 分析结论 | 核心发现汇总 |

**出报告前必做的一致性校验**（漏掉任何一项都可能发布错误数字）：

| 校验项 | 方法 | 常见错误 |
|--------|------|---------|
| 工具调用总数 | 全局唯一 `tool_call_id` 数 == `response_json` tool_calls 数 == `tool` 消息去重数 | 直接累加 `messages_json`（虚高 77 倍，见陷阱 7） |
| 子项计数之和 | 各分类条数相加 == 标题声明的总数 | 标题写"147 个"，实际逐个列出只有 130 个 |
| 章节编号 | 章号（一~九）与小节号（N.x）的 N 必须对应 | 插入新章节后，后续章节的 3.1/4.1 未同步改 |
| 数据规模声明 | 文中"318 文件""325 key"与实际扫描数一致 | 增量新增文件后忘记更新总数 |
| 跨章节引用 | 关键数字在各章出现的地方全部同步 | 只改了表格，结论段仍留着旧数字 |

> 实战教训：`2026-09-28` 报告曾出现"标题写 147 个 mmv 子字段、实际只有 130 个"以及"第四章小节编号仍是 3.1/3.2"两类错误，都是逐个列举后才发现。**声明式计数（标题里写的数字）必须由脚本算出，不能靠估算或沿用旧值。**

---

## 三、关联键层次体系（通用模型）

```
Level 0 — 租户/账户层（全局共享，所有文件相同）
  key_name, team_alias, requester_ip_address
  └── 无法区分会话，但是基础设施层的"全局相同"恰好确认了数据同源
        │
        ├── 会话层 ── 第一轮 conversationRequestId（因消息累积覆盖全会话文件）
        │     │     └── 验证条件：本会话 100% + 跨会话 0% + 结构化字段
        │     │
        │     ├── 对话轮次层 ── 每轮用户输入生成 1 个新的 conversationRequestId
        │     │     └── 第 N 轮的 convReqId 只出现在第 N 轮及之后的文件中
        │     │
        │     └── 消息层 ── messageId（累积子集链：文件 N 的 messageId 集合 ⊂ 文件 N+1）
        │
        ├── 单次调用层（每文件唯一，无关联性）
        │     └── request_id, session_id, cache_key, start_time, prompt_tokens
        │
        └── 独立调用层（无 convReqId，按 model + system prompt 区分）
              └── Hermes Agent Skill 调用等
```

**层次判断规则**：
1. 某个 key 的唯一值数 = 文件总数 → **单次调用层**，无关联性
2. 某个 key 的唯一值数 = 1 → **Level 0**，全局相同，无法区分
3. 某个 key 的唯一值数 << 文件总数 且 > 1 → **可能是会话层关联键**，需进一步验证
4. 消息级 key 的唯一值数 << 文件总数 → **可能是对话轮次层关联键**

---

## 四、常见陷阱与纠正

### 陷阱 1：session_id 是会话标识符

**误区**：`session_id` 听起来像是会话标识。
**事实**：每次 LLM 调用都重新生成，318 个文件有 318 个唯一值，**不是持久会话 ID**。
**纠正**：永远不要用 `session_id` 做会话关联。

### 陷阱 2：convReqId 集合大小不同 = 没有公共值

**误区**：Session A 的文件 conv_set 大小从 1 到 5 不等，认为没有单个 convReqId 覆盖全部文件。
**事实**：由于消息累积，第 1 轮的 convReqId 出现在全部 195 个文件中。
**纠正**：不要只看集合大小，要逐个 convReqId 统计覆盖率。**第一轮的 convReqId 覆盖全会话**。

### 陷阱 3：全局相同的 key 无价值

**误区**：`model`、`key_name` 等在所有文件中相同，认为无分析价值。
**事实**：全局相同恰好确认了"数据同源"——所有调用通过同一网关、同一 API Key。**跨会话对比时**，全局相同的 key 证明它们无法区分会话，从而缩小关联键搜索范围。
**纠正**：全局相同的 key 用于排除法，不用于关联。

### 陷阱 4：messages_json 长度 = 对话轮数

**误区**：411 条消息 = 411 轮对话。
**事实**：411 条消息 = 1 个 system + 5 个 user + 194 个 assistant + 211 个 tool。对话轮数 = 5（等于 user 消息数 = convReqId 唯一值数）。
**纠正**：对话轮数 = `role=user` 的消息数 = convReqId 唯一值数。

### 陷阱 5：conversationRequestId 在 metadata 中

**误区**：从 `msg.get('metadata', {}).get('conversationRequestId')` 取值，结果为空。
**事实**：`conversationRequestId` 是消息的**顶层字段**，不在 `metadata` 子对象中。
**纠正**：用 `msg.get('conversationRequestId')` 直接取值。

### 陷阱 6：finish_reason 在 response_json 顶层

**误区**：从 `response_json.get('finish_reason')` 取值，结果为空。
**事实**：`finish_reason` 在 `response_json.choices[n].finish_reason` 中，不在顶层。
**纠正**：用 `response_json['choices'][0]['finish_reason']` 取值。

### 陷阱 7：工具调用直接累加 messages_json（最严重）

**误区**：遍历所有文件 `messages_json` 中 `role=assistant` 消息的 `tool_calls` 求和，当作工具调用总次数。曾经这样统计出 **24,734 次**。
**事实**：真实工具调用只有 **316 次**，虚高 **77.3 倍**。原因是每个详情文件都是**完整请求快照**，携带会话从第一轮到当前轮的全部历史——同一笔调用在后续每个文件里都会重复出现。实测平均每个 `tool_call_id` 被 77.3 个文件记录，最多的被 194 个文件记录。

**双重错误的典型形态**：

```python
# ❌ 错误：既没去重，又把同一批调用加了两遍
total = sum(len(m["tool_calls"]) for f in files
            for m in f["messages_json"] if m["role"] == "assistant")   # 24,418（含 77x 重复）
total += sum(len(c["message"]["tool_calls"]) for f in files
             for c in f["response_json"]["choices"])                   # + 316（又计一遍）
# => 24,734，看起来"很合理"，实际完全错误
```

注意这个错误的隐蔽性：`messages_json` 累计 + `response_json` 累计的算术结果**恰好自洽**，从数字本身看不出问题。

**纠正**：以 `tool_calls[].id`（形如 `call_fbd9bd5d67a942b4a7a455d0`）为全局唯一键，**跨全部文件取并集**：

```python
# ✅ 正确：全局按 tool_call_id 去重
id_info = {}
for f in files:
    for m in f.get("messages_json") or []:
        if m.get("role") != "assistant":
            continue
        for tc in (m.get("tool_calls") or []):
            tid = tc.get("id")
            if tid and tid not in id_info:
                id_info[tid] = tc["function"]["name"]
# id_info 的大小 = 真实调用次数（316）
```

**三方交叉验证**（至少做两项，必须相等）：

| 校验口径 | 数值 |
|---------|-----:|
| 全局唯一 `tool_calls[].id` | 316 |
| `response_json.choices[*].message.tool_calls` 求和 | 316 |
| `role=tool` 消息按 `tool_call_id` 去重 | 316 |

**踩坑提醒**：去重时容易写成"在每个文件内部去重"。由于同一文件内 id 本就不重复，这种写法得到的数量与不去重完全一样（膨胀倍数仍是 1.0x），会让人误以为"验证通过、没有重复"。**去重必须在全部文件的并集范围内进行。**

**同理适用**：任何会随消息累积而重复的统计——token 累计、消息数、工具结果数，都必须先按唯一标识去重，否则得到的只是"上下文体积"，不是"实际发生量"。

---

### 陷阱 8：只认出一种日志格式就开工（v1.0 新增）

**误区**：看到日志里 CodeCheck 结果长这样，就照着写正则：

```
L56 | 3 | G.CMT.06 | Method 'x' is missing a javadoc comment
```

**事实**：同一批数据里目标内容有 **6 种结构完全不同的格式**，占比还很分散：

| 格式 | 样子 | 条数 | 占比 |
|:-:|------|-----:|-----:|
| A 控制台竖线表 | `L56` + `3` + `G.CMT.06` + `desc`（竖线分隔） | 370 | 37.7% |
| C 列表方括号 | `L16 [3] G.CMT.02 顶层public类...`（方括号级别） | 360 | 36.7% |
| B 带级别表 | `L134` + `G.FMT.04 一个类` + `lvl=3` + `desc` | 100 | 10.2% |
| UI 无障碍快照 | 字段块：`文件路径:` 换行 `<path>` 换行 `<line>` 换行 `规则：RID` | 88 | 9.0% |
| JSON 导出转储 | `"F.java"` 换行 `行号` 换行 `"G.XXX.NN 规则名"` 换行 描述 换行 级别 | 38 | 3.9% |
| IDX 单行摘要 | `--- idx=9 path/Foo.java line=7 rule=G.FMT.03 lvl=2 ---` | 26 | 2.6% |

**只写 A 格式的后果**：解析覆盖率 863/2279 ≈ 38%，且**不会报错**——它只是安静地少读了一多半数据。

**纠正：先普查，再写正则。** 普查方法极简——把去重后的文本按"首行特征"聚类即可：

```python
# 格式普查：一眼看清有几种格式
import re, collections

def sig(line):
    """为一行生成结构签名：把具体内容抽象成占位符"""
    s = re.sub(r'\d+', '#', line.strip())
    s = re.sub(r'G\.[A-Z]{2,4}\.\d+', 'RID', s)
    s = re.sub(r'[\w./\\-]+\.(java|xml|py|js|ts)', 'PATH', s)
    return s[:60]

sigs = collections.Counter(sig(t.split('\n')[0]) for t in unique_texts)
for s, n in sigs.most_common(15):
    print(f"{n:>4}  {s}")
```

**硬性门槛**：进入解析阶段前，必须能回答「一共几种格式、各多少样本、合计是否等于唯一文本总数」。**答不上来就不许写解析器。**

**复发提示**：这个坑做过一次之后仍然会复发——因为新数据永远可能有新格式。**每次分析都必须重跑一次普查**，不能沿用上次的 6 种格式清单。

---

### 陷阱 9：用 `set()` 做业务去重（v1.0 新增）

**误区**：`len({(f, rule, desc, line) for ...})` 得到"去重后数量"，认为这就是真实问题数。

**事实**：业务实体在日志里**不是一个稳定字符串**，它会同时向两个方向漂移：

| 漂移类型 | 表现 | 用 `set()` 的后果 |
|---------|------|-----------------|
| **行号漂移** | 同一个问题随代码改动从 L109 → L111 → L113 | 被算成 3 个问题（**假重复**） |
| **描述截断** | `desc[:80]` 造成 `Method 'foo' is missing...` 与 `Method 'foo' is missing a javadoc comment` | 被算成 2 个问题（**假重复**） |
| **反向情况** | 截断后两段不同描述**恰好都落在前 80 字符内且完全相同** | 被错误合并成 1 个（**漏合并**） |

**纠正：先分组，再在组内处理漂移，绝不对原始四元组直接 `set()`。**

```python
# ✅ 正确：按稳定三元组建组，行号进集合
g = collections.defaultdict(lambda: collections.defaultdict(set))
for x in inst:
    g[(x['file'], x['rule'], nd(x['desc']))][x['src']].add(x['line'])
#                    ↑ 描述归一化        ↑ 按来源分组，才能做"单快照取 max"

# 两个口径都要产出
strict[r] += len(set().union(*srcs.values()))    # 口径B：全部不同行号
merged[r] += max(len(v) for v in srcs.values())  # 口径A：单份报告内最多几个
```

**截断合并要加约束**：仅凭"前缀相同"合并会过度合并。安全条件是**前缀相同 + 行号集合有交集**：

```python
def merge_truncated(g):
    """只有前缀关系 + 行号确实有交集，才认定是同一问题的截断变体"""
    for (f, r, a) in list(g):
        for (f2, r2, b) in list(g):
            if (f, r) != (f2, r2) or a == b: continue
            if not (b.startswith(a) or a.startswith(b)): continue
            if not (lines_of[(f,r,a)] & lines_of[(f2,r,b)]): continue   # ← 关键
            rename[(f, r, a)] = (f, r, b)
```

**为什么必须报两个口径**：它们回答两个不同问题，都有实用价值。

| 口径 | 定义 | 适用问题 | CodeCheck 实测 |
|------|------|---------|--------------:|
| **A 归并漂移** | 同组取单份报告中的最大行号数 | "实际有多少类待修问题点" | **504** |
| **B 严格并集** | 同组跨报告全部不同行号 | "日志中出现过多少个问题位置" | **588** |

差值 84 条必须 100% 可归因到具体规则的漂移（G.ERR.02 +22、G.CMT.03 +14、G.FMT.12 +13、G.MET.06 +11……）。**差值解释不清 → 说明身份键选错了，回去重选，不要硬凑。**

---

### 陷阱 10：把"提及"当成"问题"（v1.0 新增）

**误区**：正则匹配到 `G.CMT.03` 就计一条问题。

**事实**：规则 ID 会以完全正常的理由出现在非问题语境里，实测占比惊人：

| 伪问题来源 | 例子 | 次数 |
|-----------|------|-----:|
| 代码注释 | `// G.CMT.03: guard the cast to avoid...` | **281** |
| 任务清单 | `#13 [completed] Fix G.ERR.02 in Foo.java (L521, L548)` | 数十 |
| Markdown 规范说明 | 规则文档里引用 `G.CMT.03` 的标题与示例 | 数十 |
| 规则聚合侧栏 | treeitem 只有规则名+计数，没有行号和文件 | 数十 |
| 统计报告自身 | 上次生成的报告被粘贴回上下文 | 数十 |

**纠正：用结构性条件过滤，不要用关键词黑名单。**

一个真实的 CodeCheck 问题必须满足四元组**同时成立**：

```
① 有文件路径，且形如 xxx.java/.xml/.py
② 有行号，且 ≥ 1
③ 有规则 ID，且符合 G.XXX.NN
④ 有描述文本，非空
```

再加一道：**行号必须能落在该文件的实际行数范围内**（已知文件行数时）。

```python
# ✅ 结构性过滤（正例：要求四元组齐全）
def is_real_issue(rec):
    return bool(rec['file'] and rec['line'] >= 1 and rec['rule'] and rec['desc'].strip())

# ❌ 关键词黑名单（反例）：堵不住，且会误杀合法描述
BAD = ['//', '#', 'completed', 'Issue']   # 描述里出现 "Issue" 是合法业务词
```

**为什么黑名单不可靠**：伪问题的形态会随分析轮次增加——**你上一轮生成的报告，会成为下一轮的伪问题来源**。黑名单永远落后一步。

**量化检查**：统计"命中行数 vs 解析成功条数"的差值，差值应 <5% 且每一条差值样本都能人工解释。

---

### 陷阱 11：用临时脚本单独核算，导致口径分裂（v1.0 新增）

**误区**：报告主体用 `final_stat.py`，但"Top10 文件占比""CMT.03 构成拆解"这类小节顺手写个一次性脚本算，觉得"就是个除法，不会错"。

**事实**：临时脚本复制粘贴时**没有带上主脚本的合并逻辑**，于是：

| 数字 | 临时脚本 | 主脚本 | 后果 |
|------|--------:|------:|------|
| Top10 文件占比 | 45.2%（分母 516） | 46.0%（分母 504） | 分母口径不一致 |
| G.CMT.03 构成合计 | 212 | 211 | 差 1 条，五项之和对不上标题 |

这两处都要靠读者发现才能回改。**任何经过"合并/归一/过滤"的数字，都不是简单除法，不能用不同口径的分子分母。**

**纠正：只允许一个数字出口。**

```python
# ✅ 唯一出口：所有中间量都在主脚本算完，写进 result.json
result = {
    'tot': {'merged': 504, 'strict': 588},
    'rows': [...],              # 每条含 n / strict / nfiles / pct
    'catagg': {...},            # 分类汇总
    'catrules': {...},          # 分类下规则明细
    'top_files': [...],         # ← 报告要用的排行也放这里
    'cmt03_breakdown': [...],   # ← 构成拆解也放这里
}
json.dump(result, open('result.json','w',encoding='utf-8'), ensure_ascii=False, indent=1)
```

报告一律从 `result.json` 取数。**需要新维度 → 改主脚本重跑 → 再取数**，不要在报告阶段算。

**自检**：报告定稿前，随机挑 5 个数字回查 `result.json`，必须存在且一致。**任何一个数字在 `result.json` 里查不到，就说明它是手写或临时脚本算的，必须消除。**

---

### 陷阱 12：忽略"部分数据"的完整性声明（v1.0 新增）

**误区**：某份导出的汇总说"共 131 条，16 条规则"，于是当成一份 131 条的完整数据源参与统计。

**事实**：该导出**只把 20 个文件的明细转述进了日志**（脚本按 `=== 文件名 (N issues) ===` 逐文件输出，日志在某处被截断），实际能拿到明细的只有 100 条。汇总数字是**导出侧算的**，明细是**转述进来的**，两者不等。

**这类数据的正确处理姿势**：

1. **不作为独立数据源**——不要用它去交叉验证总量
2. **只贡献独有问题点**——参与去重时取并集，它带来的新条目（主要是测试文件里的问题）照收
3. **在报告里明说**——"该批次明细不齐，仅贡献独有问题点"，并解释它为什么让"涉及文件数"从 34 变成 71

**识别信号**（出现任一就要警惕）：

| 信号 | 含义 |
|------|------|
| 汇总声明的总数 > 明细实际列出的条数 | 明细被截断 |
| 明细里文件数 < 汇总声明的文件数 | 部分文件未转述 |
| 日志文本在某个 `=== 文件 ===` 处戛然而止 | 输出被截断 |
| 同一批次有两次导出、时间差很小 | 通常第二次更全或更残，需分别核对 |

**核心原则**：**汇总数 ≠ 明细数时，以明细为准算能算的，把差额写进报告，不要用汇总数去"补齐"明细。**

---

### 陷阱 13：正则匹配顺序错误导致整类数据丢失（v1.0 新增）

**误区**：解析器里先判断"这行是不是文件标题"，再判断其他模式。

**事实**：文件标题正则写成 `^(?:===|###|---)\s*(\S+\.java|...)\b`，而 IDX 格式的行恰好是：

```
--- idx=9 path/Foo.java line=7 rule=G.FMT.03 lvl=2 ---
```

它**以 `---` 开头**，被文件标题正则抢先匹配（`\S+\.java` 在行内任意位置都能命中），于是整类 IDX 记录（26 条）被静默吞掉，且解析器认为"这是一行标题"，继续往下走——**没有任何报错**。

**纠正：按特异性降序匹配，把最特殊的放最前面。**

```python
# ✅ 顺序：越具体越靠前
if RE_IDX.match(line):        # --- idx=9 file line=7 rule=RID lvl=2 ---  ← 最特殊，必须第一
    ...
elif RE_A.match(line):        # L56 | 3 | G.CMT.06 | desc
    ...
elif RE_B.match(line):        # L134 | G.FMT.04 类 | lvl=3 | desc
    ...
elif RE_C.match(line):        # L16 [3] G.CMT.02 类 | desc
    ...
elif RE_FILE.match(line):     # === Foo.java ===  ← 最宽松，放最后
    ...
```

**通用规律**：**越宽松的模式越往后放。** 判断依据是"这个模式能否匹配其他模式的行"——能匹配的，必须让位。

**检测方法**：给每个分支加计数器，跑完后检查

```python
print(fmt_counter)          # Counter({'A':370,'C':360,'B':100,'UI':88,'JSON':38,'IDX':26})
print("合计 =", sum(fmt_counter.values()), "应等于解析总数", total)
```

如果某格式计数为 0 但你确信存在 → 几乎一定是被前面的宽松分支吃了。

**同类隐患**：文件标题正则用 `\b` 结尾太宽松时，`--- idx=9 ...` 里的 `.java` 后缀照样命中。**要么加 `$` 锚定行尾，要么确保特异性顺序正确。**

---

## 五、分析脚本模板

以下脚本可直接用于新日期目录的分析。使用时修改 `data_dir` 变量即可。

### 5.1 全量分析脚本（一键输出会话分组 + 关联键验证）

```python
import json, os, glob
from collections import defaultdict, Counter

data_dir = "D:/yaodh/data/hw_litellm_call/<DATE_DIR>"  # ← 修改这里

# === Step 1: 数据清点 ===
files = [f for f in glob.glob(os.path.join(data_dir, "*.json")) 
         if os.path.basename(f) != "request_list.json"]
with open(os.path.join(data_dir, "request_list.json"), "r", encoding="utf-8") as f:
    req_list = json.load(f)
print(f"文件数: {len(files)}, request_list 记录数: {len(req_list)}")

# === Step 2: 扫描所有文件，提取关键信息 ===
files_info = []
for fp in files:
    with open(fp, "r", encoding="utf-8") as f:
        data = json.load(f)
    msgs = data.get("messages_json", [])
    conv_ids = set()
    for msg in msgs:
        crid = msg.get("conversationRequestId")
        if crid:
            conv_ids.add(crid)
    files_info.append({
        "fname": os.path.basename(fp),
        "start_time": data.get("start_time", ""),
        "model": data.get("model", ""),
        "msg_count": len(msgs),
        "conv_ids": conv_ids,
        "conv_count": len(conv_ids),
    })

# === Step 3: 会话分组 ===
# 找出所有 convReqId
all_conv_ids = set()
for fi in files_info:
    all_conv_ids |= fi["conv_ids"]

# 对每个 convReqId 统计出现文件数
print("\n=== convReqId 出现文件数统计 ===")
conv_file_count = {}
for crid in all_conv_ids:
    count = sum(1 for fi in files_info if crid in fi["conv_ids"])
    conv_file_count[crid] = count
    print(f"  {crid}: {count}/{len(files_info)}")

# 找出覆盖全会的 convReqId（出现文件数最多的那个 = 第一轮 convReqId）
# 按 convReqId 的成员关系分组
session_groups = defaultdict(list)
for fi in files_info:
    if fi["conv_ids"]:
        # 用第一个出现的 convReqId 作为会话标识
        first_crid = min(fi["conv_ids"], key=lambda c: -conv_file_count[c])
        session_groups[first_crid].append(fi)
    else:
        session_groups["__NO_CONV__"].append(fi)

# === Step 4: 输出会话分组 ===
print(f"\n=== 会话分组（{len(session_groups)} 组）===")
for key, group in session_groups.items():
    group.sort(key=lambda x: x["start_time"])
    all_conv = set()
    for fi in group:
        all_conv |= fi["conv_ids"]
    models = set(fi["model"] for fi in group)
    max_msg = max(fi["msg_count"] for fi in group) if group else 0
    label = "无convReqId" if key == "__NO_CONV__" else key
    print(f"  会话 {label[:16]}...: {len(group)} 文件, convReqId数={len(all_conv)}, "
          f"模型={models}, 最大消息数={max_msg}")

# === Step 5: 验证第一轮 convReqId 的全覆盖性 ===
print(f"\n=== 第一轮 convReqId 全覆盖验证 ===")
for key, group in session_groups.items():
    if key == "__NO_CONV__":
        continue
    # key 就是第一轮 convReqId（出现文件数最多的）
    coverage = sum(1 for fi in group if key in fi["conv_ids"])
    # 跨会话泄漏检查
    leak = sum(1 for k2, g2 in session_groups.items() 
               if k2 != key and k2 != "__NO_CONV__" 
               for fi in g2 if key in fi["conv_ids"])
    print(f"  {key}: 本会话 {coverage}/{len(group)}, 跨会话泄漏 {leak}")
```

### 5.2 JSON Key 全量提取脚本

```python
import json, os, glob
from collections import defaultdict

data_dir = "D:/yaodh/data/hw_litellm_call/<DATE_DIR>"

def collect_keys(obj, prefix, keys_set):
    if isinstance(obj, dict):
        for k, v in obj.items():
            path = f"{prefix}.{k}" if prefix else k
            keys_set.add(path)
            collect_keys(v, path, keys_set)
    elif isinstance(obj, list) and len(obj) > 0:
        for item in obj[:5]:
            collect_keys(item, f"{prefix}[n]", keys_set)
        if len(obj) > 5:
            collect_keys(obj[-1], f"{prefix}[n]", keys_set)

key_file_count = defaultdict(int)
total_files = 0
for fp in glob.glob(os.path.join(data_dir, "*.json")):
    if os.path.basename(fp) == "request_list.json":
        continue
    with open(fp, "r", encoding="utf-8") as f:
        data = json.load(f)
    keys_in_file = set()
    collect_keys(data, "", keys_in_file)
    for k in keys_in_file:
        key_file_count[k] += 1
    total_files += 1

sorted_keys = sorted(key_file_count.items(), key=lambda x: (-x[1], x[0]))
print(f"总文件数: {total_files}, 总唯一 key path: {len(key_file_count)}")
for key_path, count in sorted_keys:
    pct = f"{count*100/total_files:.1f}%"
    print(f"  [{count:>4}/{total_files}] {pct:>6}  {key_path}")
```

---

## 六、任务执行优化建议

### 6.1 分析顺序优化

**推荐顺序**（从快到深）：

1. **数据清点**（5 分钟）→ 确认规模
2. **会话识别**（15 分钟）→ 先分组，再深入
3. **关联键验证**（10 分钟）→ 确认第一轮 convReqId 全覆盖
4. **JSON Key 统计**（10 分钟）→ 脚本自动完成
5. **Null Value 分析**（10 分钟）→ 脚本自动完成
6. **XML 内容解析**（15 分钟）→ 按需深入
7. **调用链构建**（10 分钟）→ 脚本自动完成
8. **报告生成**（20 分钟）→ 按模板填充

**总耗时约 90 分钟**（318 文件规模，含人工审阅）。

### 6.2 脚本使用纪律

1. **临时脚本用后即删**：分析脚本写入数据目录，运行后删除，不污染原始数据
2. **输出写文件**：大输出写入 `_result.txt`，再分段读取，避免 stdout 截断
3. **不删除原始数据**：`request_list.json` 和详情文件永不修改、永不删除
4. **脚本不带 `os.remove(__file__)`**：避免脚本自我删除后无法复现结果

### 6.3 增量分析策略

当新文件加入时（如从 50 个增加到 318 个）：

1. **重新运行全量分析**：不要试图只分析新增文件，因为关联键的覆盖率会随文件数变化
2. **对比新旧结果**：记录新增的 key path、新增的 null path、新增的会话
3. **验证旧结论**：之前基于 50 个文件的结论可能需要修正（如"没有单个 convReqId 覆盖全会话"被推翻）

### 6.4 报告维护

- **同一日期目录的分析报告只维护一份**：`litellm_call_analysis_<date>.md`
- **新发现追加到已有章节**：不创建新文件，在原章节内更新
- **结论修正要标注**：用"**重要修正**"标记推翻之前结论的新发现
- **章节编号连续**：新增章节插入时，后续章节重新编号

### 6.5 效率复盘：时间花在哪了（v1.0 新增）

以 CodeCheck 规则统计为样本，实际耗时分布与优化后对比如下：

| 环节 | 实际耗时 | 返工次数 | 优化后 | 优化手段 |
|------|--------:|:------:|-------:|---------|
| 找对账锚点 | 收尾阶段才发现 | — | 5 min | **提到最前面做**（阶段 0） |
| 格式普查 | 分散在 3 轮返工里 | 3 | 15 min | 签名聚类一次性看清 6 种格式（陷阱 8） |
| 写解析器 | 数小时 | 3 次重写 | 40 min | 普查完再写，每格式一个函数 |
| 重扫 18,195 文件 | 每轮数分钟 × 10+ 轮 | — | 1 次 3 min | 抽取落盘 `inst.pkl` 缓存（6.6） |
| 去重与合并 | 多轮口径反复 | 4 | 30 min | 一次定义双口径，不中途改（陷阱 9） |
| 数字一致性修正 | 集中爆发在收尾 | 9 类 | ~0 | 唯一数字出口 `result.json`（陷阱 11） |
| **合计** | **约 6 小时** | **20+ 次返工** | **约 2 小时** | — |

**结论：80% 的返工来自 4 个本可以前置的动作**——找锚点、普查格式、缓存中间结果、统一数字出口。这四件事做在前面总共花 25 分钟，能省下约 4 小时。

**一条更普适的经验**：**数据分析的时间不花在"正确路径"上，而花在"发现自己走错了"上。所以所有能提前暴露"走错了"的动作，优先级都最高。**

### 6.6 中间结果缓存策略（v1.0 新增）

**问题**：改解析器逻辑 → 重扫全部原始 JSON → 等几分钟 → 发现还是不对 → 再改。一轮 3–5 分钟，改 10 轮就是 40 分钟纯等待。

**解法：把流水线切成"重"和"轻"两段，中间落盘。**

```
[重·只做一次]  扫 18,195 文件 → 按 tool_call_id 去重 → 唯一文本落盘
                                                ↓ unique_texts.json / .pkl
[轻·反复迭代]  改解析器 ← 从落盘读取（秒级）→ 解析 → 归一 → 去重 → 统计
                                                ↓ result.json
```

```python
# extract.py 里做两件事，且第二件可跳过
CACHE = 'unique_texts.pkl'

if os.path.exists(CACHE) and not FORCE_RESCAN:
    uniq = pickle.load(open(CACHE, 'rb'))
    print(f"复用缓存: {len(uniq)} 份唯一文本")
else:
    uniq = {}
    for fp in glob(f'{data_dir}/**/*.json', recursive=True):
        ...
        for m in msgs:
            if m.get('role') != 'tool': continue
            tid = m.get('tool_call_id') or hashlib.md5(textof(m).encode()).hexdigest()
            if tid not in uniq:
                uniq[tid] = textof(m)
    pickle.dump(uniq, open(CACHE, 'wb'))
    print(f"扫描完成: {len(uniq)} 份唯一文本")
```

**关键设计**：缓存的是**去重后的唯一文本**，不是原始解析结果。这样：
- 改解析逻辑 → 秒级重跑（不用重扫）
- 改原始数据 → 删缓存即可（`FORCE_RESCAN=True`）
- 缓存体积小（292 份文本，数 MB），不是 18,195 个 JSON 的副本

**纪律**：缓存文件名带语义（`unique_texts.pkl` 而非 `cache.pkl`），交付时清理，但**保留生成它的脚本**——别人重跑一遍就有。

### 6.7 反模式清单（v1.0 新增，看到立即停下）

以下都是本人在 CodeCheck 统计里真实犯过的，按危害排序：

| # | 反模式 | 为什么错 | 正确做法 |
|:-:|--------|---------|---------|
| 1 | 「先把解析跑通，格式以后再说」 | 覆盖率 38% 也能"跑通"，且不报错 | 先普查（阶段 3 卡点） |
| 2 | 「这个数字我手算一下就行」 | 分母口径不同 → 45.2% vs 46.0% | 所有数字出自同一脚本 |
| 3 | 「大概就这几种格式吧」 | 6 种格式只认出 1 种，漏 62% | 样本数必须加总等于总数 |
| 4 | 「去重不就是 `set()` 吗」 | 行号漂移 + 描述截断双向下手 | 分组 + 组内取 max/并集 |
| 5 | 「这次返工我直接改脚本，不重跑全流程」 | 前面的阶段结果可能是旧的 | 改上游必重跑下游 |
| 6 | 「汇总说 131 条，那就按 131 算」 | 明细只有 100 条，差额无来源 | 以明细为准，差额写进报告 |
| 7 | 「黑名单过滤伪问题」 | 上一轮的报告会成为下一轮的伪问题 | 结构性四元组过滤 |
| 8 | 「报告写完再统一核数字」 | 9 类不一致集中爆发，逐条回改 | 数字从 `result.json` 注入 |
| 9 | 「缓存没必要，反正就几百个文件」 | 18,195 文件 × 10 轮重扫 = 数十分钟 | 一次抽取，落盘复用 |
| 10 | 「口径 A 更准，口径 B 不报了」 | 两者回答不同问题，B 揭示返工强度 | 双口径并列，差值可归因 |

**共同特征**：这 10 条全都"看起来更省事"，而且**执行时都不会报错**——错误以"数字安静地不对"的形式存在，只能靠校验发现。这也是第零章把校验设为硬卡点的原因。


---

## 七、分析维度速查表

| 维度 | 方法 | 关键字段 | 产出 |
|------|------|---------|------|
| 数据规模 | 文件计数 | `request_list.json` 行数 | 文件总数、时间范围 |
| Key 结构 | 递归遍历 | 所有嵌套 dict/list | key path 列表、覆盖率 |
| Null 分析 | 值判断 | 所有 key path | null 分类表 |
| XML 解析 | 正则匹配 | `messages_json[n].content` | XML 标签清单 |
| 会话识别 | convReqId 集合 | `messages_json[n].conversationRequestId` | 会话分组、覆盖率 |
| 关联键验证 | 逐 key 统计 | convReqId 出现文件数 | 全覆盖 key、零泄漏验证 |
| 调用链 | 按时间排序 | `start_time`, `msg_count` | 时序链、累积模式 |
| Token 分析 | 聚合统计 | `prompt_tokens`, `completion_tokens` | 按会话/轮次的 token 分布 |
| 费用分析 | 聚合统计 | `cost`, `metadata_json.cost_breakdown` | 按会话/模型的费用分布 |
| 性能分析 | 聚合统计 | `duration_s`, `ttft_s` | 首 token 延迟、总耗时趋势 |
| 工具调用 | **按 `tool_calls[].id` 全局去重** | `messages_json[n].tool_calls[n].id` | 工具使用频次、调用序列（**不可直接累加**，见陷阱 7） |
| 并发调用 | 统计单轮 `tool_calls` 数 > 1 的轮次 | `response_json.choices[n].message.tool_calls` | 并行工具调用比例 |
| 推理过程 | 提取 reasoning | `messages_json[n].reasoning` | Agent 推理链、决策过程 |
| 用户输入 | 提取 user 消息 | `messages_json[n].content`（role=user） | 用户请求列表、意图分析 |

---

## 八、本方法论的形成历程

本方法论来源于 `2026-09-28` 目录（318 文件）的 10 轮递进式分析，以及 `hw_litellm_call` 全目录（18,195 文件）CodeCheck 规则统计的第 11–13 轮实践。以下是关键认知迭代记录：

| 轮次 | 分析内容 | 关键发现/修正 |
|------|---------|-------------|
| 1 | 50 文件分析 | 发现 null key 179 个、XML 36 标签、convReqId 5 个值、构建 4 层关联键体系 |
| 2 | convReqId 作关联键 | 发现 convReqId 之上无更高层关联键（API Key/Team 全局相同） |
| 3 | 全量 318 文件 | 新增 17 个 null key、发现 3 个独立会话、Session C 无 convReqId |
| 4 | 提取用户输入 | 发现对话轮数 = user 消息数 = convReqId 唯一值数 |
| 5 | 验证 Session A 归属 | 5 条证据证明 5 个 convReqId 同属一会话（共存+嵌套+子集链+零重叠+prompt 一致） |
| 6 | 列出全部文件 | 195 个文件按 conv_set 分 5 组（1→2→3→4→5），消息数 2→411 递增 |
| 7 | **核心修正** | **第一轮 convReqId 覆盖全部 195 文件**（因消息累积），单个值即可作会话关联键 |
| 8 | JSON Key 全量统计 | 325 个 key path、237 个全量出现、model_map 占 40%（130 个） |
| 9 | 工具与技能统计 | 统计出 24,734 次工具调用、两套工具体系隔离、Skill 从未经工具调用 |
| 10 | **工具统计去重重算** | **24,734 → 316（膨胀 77.3 倍）**。发现消息累积导致 tool_calls 跨文件重复，改用 `tool_call_id` 全局去重；同时修正 Session C 工具数 35→31 |
| 11 | **全目录 CodeCheck 规则统计** | 18,195 文件 → 225,154 次规则出现（**膨胀 446.7 倍**）→ 292 唯一文本 → 982 条 → **504 条**。确认"消息累积"在任意业务字段上都会重演 |
| 12 | **多格式解析返工** | 3 轮重写解析器：UI 快照是字段块结构、xlsx 导出转储未识别、IDX 行被文件标题正则吞掉。最终 6 格式全兼容，覆盖率 100% |
| 13 | **去重口径收敛与锚点校验** | `set()` 去重同时产生假重复与漏合并 → 改为分组取双口径（A 504 / B 588）；收尾用 `Total rows: 360` 反验，21 条规则 20 条逐项吻合 |

**最重要的三次认知修正**：

1. 第 2 轮认为"没有单个 key 能关联全部文件"，第 7 轮推翻——消息累积机制使得第一轮 convReqId 天然覆盖全会话。
2. 第 9 轮基于 `messages_json` 累加得出 24,734 次工具调用，第 10 轮推翻——同样是消息累积，导致虚高 77.3 倍，真实值 316。
3. 第 11 轮把同一陷阱推广到业务字段（规则 ID）：225,154 → 504，虚高 446.7 倍。**膨胀倍数随"同一业务事实被记录在多少条 tool 结果里"而放大**，比工具调用的情况更严重。

这三次修正指向**同一个根因**：消息累积既是"关联键可用"的原因（第一轮 convReqId 覆盖全会话），也是"统计量虚高"的原因（tool_calls 重复计数）。同一个机制，一面是便利，一面是陷阱。**任何跨文件聚合都必须先问一句：这个字段会不会因为消息累积而重复？**

**v1.0 补充的两条元认知**：

4. **陷阱会升级，不会消失**（第 11–12 轮）：陷阱 7 是"不知道该去重"，陷阱 9 是"知道要去重但去错了"——后者更危险，因为它在形式上做了去重，让人以为已经安全。
5. **返工集中在"发现自己错了"而非"改正错误"**（第 11–13 轮）：改正本身往往只是几行代码，真正的成本是前面所有轮次在错误路径上的时间。**所以方法论的重点应该放在"提前暴露错误"，而不是"出错后如何补救"**——这就是第零章把锚点侦察和格式普查提到最前面的理由。

---

## 九、适用范围与扩展

### 适用场景
- LiteLLM 代理网关的调用日志分析
- WorkBuddy Agent / Hermes Agent 的调用链还原
- 多会话、多模型的 LLM 调用日志分类
- Agent Loop 消息累积模式分析

### 扩展方向
- **跨日期对比**：对比不同日期目录的会话模式变化
- **Token 趋势分析**：按时间序列分析 prompt_tokens 增长趋势
- **工具调用频次**：统计各工具的使用频次和成功率
- **性能基线**：建立 ttft/duration 的性能基线，识别异常调用
- **费用优化**：按会话/模型/工具维度分析成本构成，识别优化空间

---

## 十、实战复盘：CodeCheck 规则统计（v1.0 新增）

本节完整记录一次"从 225,154 到 504"的分析过程，作为第零章流水线的正反例参照。

### 10.1 任务特征与难点

| 维度 | 情况 |
|------|------|
| 数据规模 | `hw_litellm_call` 全目录，27 个日期子目录，**18,195 个详情文件** |
| 目标 | 统计 CodeCheck 各规则（G.CMT.01 / G.ERR.02 / G.CON.08 …）的问题次数 |
| 硬要求 | **必须去重**（用户明确强调） |
| 难点 1 | 规则 ID 不在导出文件里，而在 **`role=tool` 的工具返回文本**中 |
| 难点 2 | 同一批结果被携带进后续每个请求快照，重复度极高 |
| 难点 3 | 目标内容在日志里有 **6 种结构不同的格式** |
| 难点 4 | 规则 ID 大量出现在"非问题"语境（代码注释、任务清单、规范文档） |

### 10.2 四层去重链路（核心成果）

| 层级 | 处理动作 | 剩余数量 | 关键点 |
|:-:|---------|--------:|--------|
| 0 | 全部 JSON 中含规则 ID 的消息（原始规模） | 24,097 条消息 / **225,154 次出现** | 此数字"看起来合理"，最具迷惑性 |
| 1 | 只保留 `role=tool` | 13,820 条 / 163,424 次 | 排除 `user`（40,211 次引用）与 `assistant`（20,280 次复述） |
| 2 | 按 `tool_call_id` 全局去重 | **292 份唯一文本** / 2,279 次出现 | 平均每条结果被 47.3 个快照记录 |
| 3 | 6 格式解析 + 剔除伪问题 | **982 条**结构化记录 | 覆盖率校验：各格式计数之和 == 982 |
| 4 | 分组去重 + 漂移/截断合并 | **504 条**（口径 A）/ 588 条（口径 B） | 双口径，差值 84 全部可归因 |

**膨胀倍数**：225,154 / 504 = **446.7 倍**。若只看 tool 角色：163,424 / 504 = **324.3 倍**。

**与陷阱 7 的对比**：工具调用虚高 77.3 倍，业务字段虚高 446.7 倍——差 5.8 倍。原因：工具调用每次只出现一次，而**一条 CodeCheck 结果会在后续几十轮对话里被反复 Read/grep/重述**，产生更多携带副本。

### 10.3 两个口径的差值归因

口径 B（588）− 口径 A（504）= **84**，逐规则可完全归因：

| 规则 | 漂移量 | 说明 |
|------|-----:|------|
| **G.ERR.02** | **+22** | 最顽固。OffloadJanitor.java 同一问题行号 L161→L166→L170→L249→L256→L310→L318，共 7 处，单份报告最多 3 处 |
| G.CMT.03 | +14 | 注释随代码增补整体位移 |
| G.FMT.12 | +13 | 空行调整引起行号变动 |
| G.MET.06 | +11 | return null 改写反复 |
| 其余 23 条 | +24 | 各项 1–4 |

**漂移量为 0 的规则**（G.CMT.01/02、G.DCL.02、G.CON.08、G.EXP.03/04、G.FMT.04、G.MET.04/05、G.OBJ.04、G.TYP.04）说明这些位置**一次定位即可修复**，属"稳定债"；而高漂移规则属"移动债"——被反复挪位置但始终未清除。

**这个差值不只是统计噪音，它是技术债质量的量化指标。** 建议报告中固定输出此列。

### 10.4 校验结果（锚点对账）

| 校验项 | 官方声明 | 本次解析 | 结果 |
|--------|---------|---------|------|
| 导出总行数 | `Total rows: 360` | main 307 + test 53 = **360** | ✅ |
| 按规则汇总合计 | 355 | 逐条明细聚合 360 | ⚠️ 差异 5，已解释 |
| 逐规则比对 | 21 条规则 | **20 条完全一致** | ✅ |

**差异解释**：官方汇总把 `G.OTH.03` 拆成两行——`--不用的import语句: 5` 与 `--不用的代码段: 1`。按规则 ID 汇总为 6，与 5+1 等价。**355 + 5 = 360，逐规则 100% 对齐。**

**踩坑细节**：解析 `=== Issues by Rule ===` 时，正则若写成 `:\s*(\d+)$` 会因规则名本身含数字而漏匹配；应改为 `.*?:\s*(\d+)\s*$` 取**末组**数字。

### 10.5 本次分析的失误清单

| 失误 | 阶段 | 代价 | 对应陷阱 |
|------|------|------|---------|
| 到收尾才发现锚点 | 0 | 全程无客观校验 | 铁律 1 |
| 只认一种格式就写解析器 | 3 | 重写 3 次，约 1 小时 | 陷阱 8 |
| `content` 是 list 未兼容 | 4 | 一次崩溃 | — |
| Python 用 Git Bash 路径 `/c/...` | 4 | 一次崩溃 | — |
| `best` 初始阈值 >5 致 None | 4 | 一次崩溃 | — |
| `set()` 直接去重 | 7 | 口径反复 4 轮 | 陷阱 9 |
| Top10 占比用临时脚本 | 9 | 45.2% vs 46.0% | 陷阱 11 |
| CMT.03 构成用临时脚本 | 9 | 212 vs 211 | 陷阱 11 |
| 第二份导出按汇总数对待 | 1 | 差点污染数据源 | 陷阱 12 |
| RE_IDX 被 RE_FILE 抢先 | 4 | 丢 26 条且无报错 | 陷阱 13 |

**共性**：10 个失误中 **7 个属于"阶段顺序错误"**（把该前置的放到后面），只有 3 个是编码细节。**这直接支撑了第零章的存在。**

---

## 十一、故障速查表（v1.0 新增）

遇到问题按"症状"查。

### 11.1 数字类

| 症状 | 最可能原因 | 排查动作 |
|------|-----------|---------|
| 统计量比预期大几十到几百倍 | 消息累积未去重 | 查是否按 `tool_call_id` 全局去重（陷阱 7） |
| 去重后倍数仍是 1.0x | 去重写在了"文件内" | 改为全部文件并集（陷阱 7 踩坑提醒） |
| 各分类之和不等于总数 | 存在未归类的"其他"桶，或截断合并漏做 | 打印未归类项，逐条看 |
| 同一指标出现两个值 | 临时脚本口径不同 | 找 `result.json` 里有无该数字（陷阱 11） |
| 汇总数与明细数不等 | 明细被截断 | 以明细为准，差额写入报告（陷阱 12） |
| 占比之和 ≠ 100% | 分母用了不同口径 | 全部用同一总数做分母 |

### 11.2 解析类

| 症状 | 最可能原因 | 排查动作 |
|------|-----------|---------|
| 解析条数远少于命中行数 | 有格式未支持 | 跑格式签名聚类（陷阱 8） |
| 某格式计数为 0 但确实存在 | 被前面宽松正则抢先 | 按特异性降序重排（陷阱 13） |
| 解析器无报错但结果偏少 | 静默未匹配 | 给每分支加计数器，检查加总（陷阱 13） |
| `content` 相关报错 `expected string, got list` | 多段内容 | 加 `textof()` 兼容 str/list |
| `FileNotFoundError` 路径形如 `/c/Users/...` | Git Bash 路径传给 Python | 改 Windows 风格 `C:/Users/...` |
| `'NoneType' object is not subscriptable` | `best`/`max` 初值不当 | 全量扫描，初值置 `(0, None)` |

### 11.3 实体归一化类

| 症状 | 最可能原因 | 排查动作 |
|------|-----------|---------|
| 文件数异常多（如 119 而非 71） | 同一文件多种路径写法 | 后缀匹配合并，取最长写法（阶段 5） |
| 合并后数量骤降、疑似过度合并 | 前缀合并无约束 | 加"行号有交集"约束（陷阱 9） |
| 同一问题被算成两条 | 描述被截断成变体 | 检查是否有严格前缀关系 + 行号交集 |
| 两个不同问题被合并成一条 | 截断后前 N 字符恰好相同 | 提高合并门槛，或改用规则+行号为主键 |

### 11.4 流程类

| 症状 | 最可能原因 | 处理 |
|------|-----------|------|
| 每改一次逻辑要等数分钟 | 未缓存中间结果 | 抽取落盘复用（6.6） |
| 改完上游忘了重跑下游 | 阶段结果陈旧 | 改上游必重跑下游（反模式 5） |
| 报告写完发现数字对不上 | 数字非脚本生成 | 全部改为从 `result.json` 注入（反模式 8） |
| 复现时结果不一致 | 残留旧缓存/旧中间文件 | 清缓存全量重跑，对比五个关键数 |
| 伪问题越过滤越多 | 用黑名单 | 改结构性四元组过滤（陷阱 10） |

### 11.5 三分钟健康检查（每次分析收尾必跑）

```python
# 把这五项打印出来，全部通过才算完成
print("1. 唯一文本数     :", n_unique)          # 应为几十到几百量级
print("2. 解析条数       :", n_parsed)          # 各格式计数之和 == n_parsed
print("3. 格式分布       :", fmt_counter)       # 无 0 项、无未分类
print("4. 归一后实体数   :", n_files)           # 路径写法数应显著下降
print("5. 双口径合计     :", tot_a, tot_b)      # tot_b - tot_a 逐条可归因
assert sum(fmt_counter.values()) == n_parsed
assert tot_a <= tot_b
# 再对照外部锚点（若有）：
#   parsed_rows == int(re.search(r'Total rows:\s*(\d+)', anchor_text).group(1))
```

---

## 十二、v1.0 变更摘要

| 类别 | 变更 |
|------|------|
| **新增章节** | 第零章（五条铁律 + 十阶段流水线 + 依赖图）、第十章（CodeCheck 实战复盘）、第十一章（故障速查表）、第十二章（本摘要） |
| **新增陷阱** | 陷阱 8 格式普查缺失、9 `set()` 误用、10 伪问题污染、11 临时脚本口径分裂、12 完整性声明忽略、13 正则顺序 |
| **新增小节** | 6.5 效率复盘（时间分布与优化对比）、6.6 中间结果缓存策略、6.7 反模式清单（10 条） |
| **扩写** | 第八章形成历程补至 13 轮，新增两条元认知 |
| **保留** | 原一至七、九章内容完整未删改，仅补充 v1.0 标记 |

**下一次分析的起手动作**（照此执行即可）：

1. 跑锚点侦察（阶段 0），把能找到的官方对账数字记下来
2. 做载体定位，明确"真数据在哪个 role、哪个工具下"
3. 落盘唯一文本 + 跑格式签名聚类，产出格式清单
4. 才动笔写解析器
5. 全程只有一个数字出口 `result.json`
6. 收尾跑 11.5 健康检查

**如果只能记住一句话**：**数据分析的时间不花在写代码上，花在发现自己走错路上。所以所有能提前暴露错误的动作，优先级都最高。**