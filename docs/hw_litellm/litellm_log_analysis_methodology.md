# LiteLLM 调用日志分析方法论

> **来源**：基于 `2026-09-28` 目录 318 个详情文件的多轮递进式分析实践提炼
> **创建时间**：2026-11-02
> **目标**：为后续分析更多日期目录的 LLM 调用日志提供标准化、可复用的分析流程

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

本方法论来源于 `2026-09-28` 目录的 10 轮递进式分析实践，以下是关键认知迭代记录：

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

**最重要的两次认知修正**：

1. 第 2 轮认为"没有单个 key 能关联全部文件"，第 7 轮推翻——消息累积机制使得第一轮 convReqId 天然覆盖全会话。
2. 第 9 轮基于 `messages_json` 累加得出 24,734 次工具调用，第 10 轮推翻——同样是消息累积，导致虚高 77.3 倍，真实值 316。

这两次修正指向**同一个根因**：消息累积既是"关联键可用"的原因（第一轮 convReqId 覆盖全会话），也是"统计量虚高"的原因（tool_calls 重复计数）。同一个机制，一面是便利，一面是陷阱。**任何跨文件聚合都必须先问一句：这个字段会不会因为消息累积而重复？**

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