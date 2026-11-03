# LiteLLM 调用日志分析报告 — 2026-10-20

> **分析方法论**：`litellm_log_analysis_methodology.md`
> **数据目录**：`D:/yaodh/data/hw_litellm_call/2026-10-20`
> **分析时间**：2026-11-02
> **分析工具**：Python 脚本（Step 1-6 自动化）

---

## 一、目录结构概览

### 1.1 文件清点

| 项目 | 数值 |
|------|------|
| JSON 文件总数 | 572 |
| 详情文件数 | 571 |
| `request_list.json` 记录数 | 571 |
| 1:1 匹配验证 | PASS（0 缺失，0 多余） |

### 1.2 时间范围

- **起始**：2026-10-20 00:00:04（部分文件 start_time 为 2026-10-19T16:00 UTC，即北京时间 00:00）
- **结束**：2026-10-20 17:25:31
- **跨度**：约 17.4 小时

### 1.3 模型分布

| 模型 | 调用次数 | 占比 |
|------|---------|------|
| `glm-5.3-flash` | 425 | 74.4% |
| `glm-5.2` | 116 | 20.3% |
| `GLM-5.3-Flash` | 18 | 3.2% |
| `GLM-5.2` | 12 | 2.1% |

> 模型名存在大小写差异，合并后：glm-5.3-flash 系列占 77.6%，glm-5.2 系列占 22.4%。

### 1.4 状态分布

| 状态 | 次数 |
|------|------|
| success | 541（94.7%） |
| failure | 30（5.3%） |

### 1.5 Token 与费用汇总

| 指标 | 值 |
|------|-----|
| Prompt Tokens | 43,952,241 |
| Completion Tokens | 292,992 |
| Total Tokens | 44,245,233 |
| 总费用 | $22.027195 |

> prompt tokens 远大于 completion tokens（150:1），符合 Agent Loop 消息历史累积特征。

---

## 二、JSON Key 结构与 Null Value 分析

### 2.1 Key 结构总览

| 指标 | 值 |
|------|-----|
| 总唯一 key path | 352 |
| 总文件数 | 571 |

### 2.2 覆盖率分档

| 覆盖率区间 | key path 数量 | 占比 |
|-----------|-------------|------|
| 100%（全部文件） | 69 | 19.6% |
| 90-99% | 193 | 54.8% |
| 50-89% | 39 | 11.1% |
| 10-49% | 24 | 6.8% |
| 1-9% | 27 | 7.7% |

> 对比 2026-09-28：325 -> 352 个 key path（+27），100% 覆盖从 73% 降至 19.6%。

### 2.3 Null Value 分类

| 分类 | 数量 | 说明 |
|------|------|------|
| model_unsupported | 102 | model_map_value 下定价/能力字段 |
| other | 68 | LiteLLM 内部元数据字段 |
| feature_disabled | 29 | batch/cache/stream 等未启用功能 |
| version_diff | 2 | system_json、reasoning 等版本差异 |
| success_no_error | 2 | error_information（成功时为 null） |
| config_missing | 1 | team_name 未配置 |
| **合计** | **204** | |

---

## 三、JSON Key 全量统计

### 3.1 100% 覆盖的顶层 key（69 个）

核心字段：`api_base`, `cache_hit`, `cache_key`, `call_type`, `completion_tokens`, `cost`, `duration_s`, `end_time`, `key_hash`, `key_name`, `messages_json`, `metadata_json`, `model`, `prompt_tokens`, `request_id`, `response_json`, `session_id`, `start_time`, `status`, `tool_names_json`, `total_tokens`

### 3.2 关键结构差异

与 2026-09-28 相比新增 key path 主要来自 `metadata_json.additional_usage_values` 下的 token 详情字段（prompt_tokens_details、completion_tokens_details），反映不同模型返回 usage 详情的能力差异。

---

## 四、JSON Value 中的 XML 文档解析

### 4.1 XML 标签统计

- XML 标签种类：**257**

### 4.2 高频 XML 标签 Top 20

| 标签 | 出现次数 | 主要位置 |
|------|---------|---------|
| `<String>` | 9,615 | tool(9,068)、tool_calls.args(350) |
| `<BaseMessage>` | 6,055 | tool(5,694)、tool_calls.args(245) |
| `<p>` | 4,062 | tool(3,478)、user(570) |
| `<li>` | 2,047 | tool(2,047) |
| `<id>` | 1,940 | tool(1,853)、user(47)、system(40) |
| `<OffloadRecord>` | 1,784 | tool(1,528)、tool_calls.args(175) |
| `<OffloadRef>` | 1,768 | tool(1,271)、user(243)、assistant(149) |
| `<b>` | 1,333 | tool(1,333) |
| `<result_presentation>` | 1,311 | system(1,311) |
| `<sharing_files>` | 1,311 | system(1,311) |
| `<project-dir>` | 1,311 | system(1,311) |
| `<maven-home>` | 1,311 | system(1,311) |
| `<OffloadOtelReporter>` | 978 | tool(462)、assistant(245) |
| `<OffloadMarkerUtils>` | 960 | tool(696)、tool_calls.args(264) |
| `<final_answer_instructions>` | 874 | system(874) |
| `<doc_url>` | 874 | system(874) |
| `<pkg>` | 874 | system(874) |
| `<Integer>` | 837 | tool(837) |
| `<artifactId>` | 826 | tool(826) |
| `<system-reminder>` | 650 | system(470)、user(149) |

### 4.3 XML 标签语义分类

| 分类 | 代表标签 | 语义 |
|------|---------|------|
| 上下文卸载机制 | OffloadRecord, OffloadRef, OffloadMarkerUtils, OffloadOtelReporter, OffloadNamespace | Agent 上下文压缩/卸载系统 |
| System Prompt 结构 | result_presentation, sharing_files, project-dir, maven-home, final_answer_instructions, doc_url, pkg | 系统提示词 XML 配置块（Java/Maven 项目） |
| 工具返回格式化 | String, BaseMessage, p, li, b, text, id, type, version, artifactId | 工具执行结果 XML/HTML 格式化 |
| 系统提醒 | system-reminder | 动态注入的运行时上下文 |

---

## 五、文件关联与调用链构建

### 5.1 候选关联键扫描

| 候选 key | 唯一值数 | 判断 |
|----------|---------|------|
| `session_id` | 571 | 每文件唯一，无关联性 |
| `request_id` | 571 | 每文件唯一，天然无关联性 |
| `model` | 4 | 有效区分维度（合并后 2 个模型） |
| `key_name` | 1 | 全局相同，无法区分 |
| `sys_prompt_hash` | 19 | 有效关联键候选 |
| `workspace` | 0 | 无值 |
| `requester_ip` | 1 | 全局相同，无法区分 |
| `conversationRequestId` | 18 | **有效关联键** |

### 5.2 conversationRequestId 出现文件数

| convReqId（前 20 字符） | 出现文件数 | 占比 |
|------------------------|-----------|------|
| 01a154c2fb91785c9750 | 183/571 | 32.0% |
| 01a15760c54f7c6195ed | 137/571 | 24.0% |
| 01a1573522397b27b129 | 87/571 | 15.2% |
| 01a154fb0d4c73149dff | 67/571 | 11.7% |
| 01a156dd3e157303b5bb | 66/571 | 11.6% |
| 01a156f7d1847c3e9b01 | 49/571 | 8.6% |
| 01a1586e844e71b5be46 | 45/571 | 7.9% |
| 01a15876d6fc7c97bf65 | 40/571 | 7.0% |
| 01a15808d22174bc82bc | 34/571 | 6.0% |
| 01a15381a8aa7ff6a12c | 25/571 | 4.4% |
| 01a15744724c713590b5 | 25/571 | 4.4% |
| 01a15413732b7a4f82b7 | 25/571 | 4.4% |
| 01a15884414e7dd68864 | 24/571 | 4.2% |
| 01a157f7e2287361ac67 | 16/571 | 2.8% |
| 01a158577c1574938414 | 12/571 | 2.1% |
| 01a1589be84378c3b0af | 7/571 | 1.2% |
| 01a158034dce70d692a6 | 6/571 | 1.1% |
| 01a15822b463762e9f51 | 2/571 | 0.4% |

### 5.3 会话分组（7 组）

| 会话 | 文件数 | convReqId | 模型 | 最大消息数 | 时间范围 | 累积模式 |
|------|--------|----------|------|-----------|---------|---------|
| A (01a154c2) | 183 | 4 | glm-5.2+flash | 410 | 10/19 16:00~10/20 01:56 | 累积型 341->410 |
| B (NO_CONV) | 132 | 0 | 多模型 | 73 | 10/19 16:24~10/20 09:09 | 独立调用型 |
| C (01a15735) | 44 | 1 | flash | 105 | 10/20 02:47~03:16 | 累积型 2->105 |
| D (01a15381) | 25 | 3 | flash | 176 | 10/20 03:04~03:14 | 累积型 127->176 |
| E (01a15760) | 137 | 6 | flash | 226 | 10/20 03:35~09:25 | 累积型 107->226 |
| F (01a157f7) | 16 | 2 | flash | 37 | 10/20 06:20~06:33 | 累积型 2->37 |
| G (01a15808) | 34 | 3 | flash | 71 | 10/20 06:38~08:14 | 累积型 2->71 |

### 5.4 第一轮 convReqId 全覆盖验证

| 会话关联键 | 本会话覆盖 | 跨会话泄漏 | 验证结果 |
|-----------|-----------|-----------|---------|
| 01a154c2...aac38 | 183/183 | 0 | 完美覆盖，零泄漏 |
| 01a15735...fbb8 | 44/44 | **43** | 本会话全覆盖，跨会话泄漏 43 |
| 01a15381...40df | 25/25 | 0 | 完美覆盖，零泄漏 |
| 01a15760...4f1d | 137/137 | 0 | 完美覆盖，零泄漏 |
| 01a157f7...76c | 16/16 | 0 | 完美覆盖，零泄漏 |
| 01a15808...163 | 34/34 | 0 | 完美覆盖，零泄漏 |

> **重要发现 — 跨会话泄漏**：
>
> Session C 的第一轮 convReqId 出现在 87 个文件中（44 本会话 + 43 跨会话）。泄漏的 43 个文件属于 Session E。Session C 时间 02:47~03:16，Session E 时间 03:35~09:25。**Session E 是 Session C 的延续会话**——Agent 重启后携带了之前的对话上下文。这在 2026-09-28 数据中未观察到，是本批数据的新特征。
>
> 6 个有 convReqId 的会话中，5 个满足零泄漏，1 个存在跨会话上下文继承。

### 5.5 关联键层次体系

```
Level 0 - 租户/账户层（全局共享）
  key_name(1), requester_ip(1) -> 确认数据同源
    |
    +- 会话层 - 第一轮 conversationRequestId
    |   +- 5 个会话：本会话100% + 跨会话0%（完美关联键）
    |   +- 1 个会话(C)：本会话100% + 跨会话泄漏（上下文继承至 E）
    |
    +- 对话轮次层 - 18 个唯一 convReqId
    |
    +- 消息层 - messageId（累积子集链）

独立调用层（无 convReqId，132 文件）
  +- Session B(NO_CONV)：按 model + sys_prompt_hash 区分
```

---

## 六、完整调用链示例

### 6.1 Session A — 大型累积型会话（183 文件）

| seq | start_time | msg | conv | model | finish | pt | ct | cost | dur(s) |
|-----|-----------|-----|------|-------|--------|-----|-----|------|-------|
| 0 | 10/19 16:00:04 | 341 | 1 | glm-5.2 | tool_calls | 147,947 | 89 | $0.216 | 4.6 |
| 1 | 10/19 16:00:16 | 343 | 1 | glm-5.2 | tool_calls | 148,082 | 89 | $0.216 | 12.6 |
| 2 | 10/19 16:00:37 | 345 | 1 | glm-5.2 | tool_calls | 148,225 | 168 | $0.217 | 5.8 |
| ... | ... | ... | 1 | glm-5.2 | tool_calls | 递增 | ... | ... | ... |
| 182 | 10/20 01:56:42 | 410 | 1 | ... | ... | ... | ... | ... | ... |

- **特征**：消息数从 341 递增至 410（+2/次），conv_set 大小恒为 1
- **模型**：glm-5.2 为主，部分切换 glm-5.3-flash
- **费用**：$16.12（占当日总费用 73.2%）
- **工具集**：23 种工具，每种被 182 次调用（Read/Write/Edit/Glob/Grep/Bash/PowerShell/TaskCreate/TaskGet/TaskUpdate/TaskOutput/WebFetch/WebSearch/AskUserQuestion/DeferExecuteTool/automation_update/present_files/show_widget/widget_guidelines/TaskList/Skill/Agent/ToolSearch）

### 6.2 Session C — 新启动会话（44 文件）

| seq | start_time | msg | conv | model | finish | pt | ct | cost | dur(s) |
|-----|-----------|-----|------|-------|--------|-----|-----|------|-------|
| 0 | 10/20 02:47:47 | 2 | 1 | flash | tool_calls | 36,029 | 335 | $0.008 | 9.6 |
| 1 | 10/20 02:47:59 | 6 | 1 | flash | tool_calls | 59,522 | 124 | $0.013 | 5.2 |
| 2 | 10/20 02:48:06 | 9 | 1 | flash | tool_calls | 62,279 | 398 | $0.014 | 15.3 |
| ... | ... | ... | 1 | flash | tool_calls | 递增 | ... | ... | ... |
| 43 | 10/20 03:16:22 | 105 | 1 | flash | ... | ... | ... | ... | ... |

- **特征**：消息数从 2 递增至 105，典型的从零开始累积型会话
- **费用**：$1.02

### 6.3 Session B — 独立调用型（132 文件，无 convReqId）

- **特征**：messages_json 为空或固定长度，无 conversationRequestId/messageId/traceId
- **模型**：混合（GLM-5.2、GLM-5.3-Flash、glm-5.3-flash），大小写差异显著
- **sys_prompt_hash**：14 个不同值，说明包含多个不同 Agent 类型的独立调用
- **费用**：$0.73（单次调用成本极低）
- **工具集**：包含浏览器工具（browser_navigate/click/type 等）、飞书工具（feishu_doc_read 等）、代码工具（execute_code/terminal）等，工具种类远多于累积型会话
- **推断**：这些是 Hermes Agent Skill 或其他独立 Agent 的单次调用，不通过 WorkBuddy Agent Loop 运行

### 6.4 各会话汇总对比

| 会话 | 文件数 | prompt_tokens | completion_tokens | cost | duration(s) |
|------|--------|--------------|-------------------|------|------------|
| A | 183 | 17,344,298 | 53,722 | $16.12 | 1,575.6 |
| B | 132 | 3,250,702 | 85,034 | $0.73 | 2,348.5 |
| C | 44 | 4,610,825 | 43,169 | $1.02 | 1,434.6 |
| D | 25 | 3,005,134 | 10,824 | $0.66 | 371.1 |
| E | 137 | 13,385,855 | 74,870 | $2.96 | 2,149.2 |
| F | 16 | 671,095 | 6,414 | $0.15 | 183.4 |
| G | 34 | 1,684,332 | 18,959 | $0.37 | 631.0 |
| **合计** | **571** | **43,952,241** | **292,992** | **$22.03** | **8,693.3** |

---

## 七、调用时序图

### 7.1 Session A 调用时序（前 10 次调用）

```
时间轴 (10/19 16:00 ~ 16:06)

16:00:04  [调用0] glm-5.2  msg=341  pt=147K  -> tool_calls  (4.6s)
16:00:16  [调用1] glm-5.2  msg=343  pt=148K  -> tool_calls  (12.6s)
16:00:37  [调用2] glm-5.2  msg=345  pt=148K  -> tool_calls  (5.8s)
16:00:50  [调用3] glm-5.2  msg=347  pt=148K  -> tool_calls  (5.8s)
16:01:03  [调用4] glm-5.2  msg=349  pt=150K  -> tool_calls  (10.5s)
16:01:21  [调用5] glm-5.2  msg=351  pt=150K  -> tool_calls  (6.8s)
16:01:35  [调用6] glm-5.2  msg=353  pt=150K  -> tool_calls  (5.8s)
16:01:48  [调用7] glm-5.2  msg=355  pt=151K  -> tool_calls  (3.4s)
16:01:58  [调用8] glm-5.2  msg=357  pt=151K  -> tool_calls  (6.0s)
16:02:12  [调用9] glm-5.2  msg=359  pt=151K  -> tool_calls  (6.8s)
```

### 7.2 Session C -> E 跨会话上下文继承时序

```
02:47  +-- Session C 开始 (msg=2, 新会话)
       |   [44 次调用, msg 2->105]
03:16  +-- Session C 结束
       |
       |   (gap: 19 分钟)
       |
03:35  +-- Session E 开始 (msg=107, 携带 C 的上下文)
       |   [137 次调用, msg 107->226]
09:25  +-- Session E 结束
```

> Session E 起始消息数 107，远大于 2，证明其继承了 Session C 的对话历史。

---

## 八、全量分析

### 8.1 会话分组详情

| 会话 | 类型 | 文件数 | convReqId 数 | sys_prompt_hash 数 | 对话轮数 | 工具种类 |
|------|------|--------|-------------|-------------------|---------|---------|
| A | 累积型 | 183 | 4 | 3 | 4 | 23 |
| B | 独立调用型 | 132 | 0 | 14 | N/A | 60+ |
| C | 累积型 | 44 | 1 | 1 | 1 | 23 |
| D | 累积型 | 25 | 3 | 1 | 3 | 23 |
| E | 累积型(继承C) | 137 | 6 | 2 | 6 | 23 |
| F | 累积型 | 16 | 2 | 1 | 2 | 23 |
| G | 累积型 | 34 | 3 | 1 | 3 | 23 |

### 8.2 模型使用模式

- **glm-5.2**（116 次）：主要用于 Session A（大型累积型会话），单次 prompt_tokens 高达 147K~170K
- **glm-5.3-flash**（425 次）：用于 Session C/D/E/F/G 及部分 Session A 调用，单次 prompt_tokens 相对较低
- **GLM-5.2 / GLM-5.3-Flash**（30 次，大写）：仅出现在 Session B（独立调用型），可能来自不同的 Agent 客户端

### 8.3 失败调用分析

- 30 次失败调用（5.3%），主要集中在 Session B 独立调用中
- 累积型会话（A/C/D/E/F/G）几乎全部成功

### 8.4 费用分布

| 会话 | 费用 | 占比 | 平均单次费用 |
|------|------|------|------------|
| A | $16.12 | 73.2% | $0.088 |
| E | $2.96 | 13.4% | $0.022 |
| C | $1.02 | 4.6% | $0.023 |
| D | $0.66 | 3.0% | $0.027 |
| G | $0.37 | 1.7% | $0.011 |
| B | $0.73 | 3.3% | $0.006 |
| F | $0.15 | 0.7% | $0.009 |

> Session A 占费用 73.2%，是成本优化重点。其高成本源于 glm-5.2 模型 + 大量累积 prompt tokens（平均 95K/次）。

---

## 九、分析结论

### 9.1 核心发现

1. **数据规模**：571 个详情文件，572 条 LLM 调用记录，1:1 匹配完整。时间跨度 17.4 小时，总费用 $22.03。

2. **会话结构**：识别出 7 个会话——6 个累积型（有 convReqId）+ 1 个独立调用型（无 convReqId）。累积型会话共 439 文件（76.9%），独立调用型 132 文件（23.1%）。

3. **关联键验证**：第一轮 conversationRequestId 作为会话关联键的验证结果——6 个会话中 5 个完美覆盖零泄漏，1 个（Session C）存在跨会话泄漏（43 文件），原因为 **Session E 继承了 Session C 的对话上下文**。这是 2026-10-20 数据相比 2026-09-28 的重要新特征。

4. **模型分布**：glm-5.3-flash 占主导（77.6%），glm-5.2 用于大型会话（Session A）。模型名存在大小写差异，来自不同 Agent 客户端。

5. **成本集中**：Session A 占总费用 73.2%（$16.12），是成本优化重点。其特征是 glm-5.2 模型 + 大量累积 prompt tokens。

6. **XML 标签**：257 种标签，上下文卸载机制（Offload* 系列）使用频繁，反映 Agent 上下文管理活跃。System prompt 包含 Java/Maven 项目配置（project-dir、maven-home、artifactId 等）。

7. **独立调用型会话**：Session B（132 文件）包含 14 种不同 system prompt、60+ 种工具，涵盖浏览器、飞书、代码执行等，是多种独立 Agent 的单次调用集合。

### 9.2 与 2026-09-28 对比

| 维度 | 2026-09-28 | 2026-10-20 | 变化 |
|------|-----------|-----------|------|
| 文件数 | 318 | 571 | +79.9% |
| key path 数 | 325 | 352 | +8.3% |
| null key 数 | ~179 | 204 | +13.9% |
| XML 标签数 | 36 | 257 | +613.9% |
| 会话数 | 3 (A/B/C) | 7 (A~G) | +133% |
| convReqId 数 | 5 | 18 | +260% |
| 跨会话泄漏 | 0 | 1 (C->E) | 新特征 |
| 模型种类 | 2 | 2（4 种命名） | 大小写新增 |
| 总费用 | N/A | $22.03 | — |

### 9.3 方法论验证

- **陷阱 1（session_id）**：确认 571 个唯一值，非会话标识。鉁匼
- **陷阱 2（convReqId 集合大小）**：第一轮 convReqId 覆盖全会话的结论在 5/6 会话中成立。鉁叄ú糠中拚嚎缁峄吧舷挛募坛锌傻贾滦孤‐
- **陷阱 4（消息数≠轮数）**：Session A 410 条消息 = 1 system + 4 user + ... 对话轮数 = 4 = convReqId 数。鉁匼
- **陷阱 5（convReqId 位置）**：确认为消息顶层字段。鉁匼
- **陷阱 6（finish_reason 位置）**：确认为 response_json.choices[0].finish_reason。鉁匼

### 9.4 新发现与建议

1. **跨会话上下文继承**：Session C -> E 的上下文继承是本批数据的新特征。建议方法论增加"跨会话继承检测"步骤：当第一轮 convReqId 出现跨会话泄漏时，检查时间先后关系，判断是否为上下文继承。

2. **模型名大小写差异**：同一模型出现 `glm-5.2`/`GLM-5.2` 和 `glm-5.3-flash`/`GLM-5.3-Flash` 两种命名，来自不同 Agent 客户端。建议分析时做大小写归一化。

3. **独立调用型会话工具多样性**：Session B 包含 60+ 种工具，远超累积型会话的 23 种。可作为区分会话类型的辅助特征。

4. **成本优化建议**：Session A 占 73% 费用但仅 183 次调用，单次 $0.088。考虑：a) 对长历史会话使用更经济的模型；b) 实施更积极的上下文压缩；c) 评估是否需要保留全部消息历史。
