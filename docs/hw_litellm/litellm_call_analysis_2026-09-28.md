# LiteLLM 调用数据分析报告

> **数据目录**: `D:\yaodh\data\hw_litellm_call\2026-09-28`
> **分析时间**: 2026-11-02
> **数据规模**: request_list.json (318 条记录) + 318 个调用详情文件（初始 50 个 + 新增 268 个）

---

## 一、目录结构概览

| 文件类型 | 数量 | 说明 |
|---------|------|------|
| request_list.json | 1 | LLM 调用列表，318 条记录 |
| 调用详情 .json | 318 | 每个文件对应一次 LLM 调用的完整请求/响应详情 |
| 合计 | 319 | request_list 中 318 条记录全部有对应详情文件（1:1 匹配） |

**文件命名规则**: 详情文件名 = `request_id + .json`，50 个详情文件的 request_id 与 request_list.json 中的 request_id 完全匹配。

---

## 二、JSON Key 结构与 Null Value 分析

### 2.1 详情文件顶层 Key 结构

每个详情文件包含以下顶层字段：

| Key | 类型 | 说明 |
|-----|------|------|
| `request_id` | string | 请求唯一标识 |
| `start_time` | string | 调用开始时间 (ISO 8601 UTC) |
| `end_time` | string | 调用结束时间 (ISO 8601 UTC) |
| `completion_start_time` | string | 补全开始时间（首 token 时间） |
| `model` | string | 模型名称（均为 glm-5.2） |
| `call_type` | string | 调用类型（均为 acompletion） |
| `api_base` | string | API 网关地址 |
| `status` | string | 调用状态（success） |
| `duration_s` | float | 总耗时（秒） |
| `ttft_s` | float | 首 token 耗时（秒） |
| `total_tokens` | int | 总 token 数 |
| `prompt_tokens` | int | 输入 token 数 |
| `completion_tokens` | int | 输出 token 数 |
| `cost` | float | 费用 |
| `key_name` | string | API Key 名称 |
| `key_hash` | string | API Key 哈希 |
| `team_name` | **null** | 团队名称（始终为 null） |
| `end_user` | string | 终端用户标识 |
| `metadata_json` | dict | 元数据（含用量、成本、模型映射等） |
| `messages_json` | list | 消息列表（含 system/user/assistant/tool 角色） |
| `system_json` | **null** | 系统消息（始终为 null，system prompt 在 messages_json[0] 中） |
| `tool_names_json` | list | 可用工具名称列表 |
| `response_json` | dict | LLM 响应详情 |
| `cache_hit` | string | 缓存命中标记（均为 "False"） |
| `cache_key` | string | 缓存键 |
| `session_id` | string | 会话 ID |

### 2.2 Null Value Key 汇总（179 个唯一路径）

#### 顶层 Null Keys（3 个）

| JSON Path | 出现次数 | 解释 |
|-----------|---------|------|
| `team_name` | 50/50 | 团队名称，所有文件均为 null，表示未设置团队归属 |
| `system_json` | 50/50 | 独立系统消息字段，所有文件均为 null；实际 system prompt 存储在 messages_json[0].content 中 |

#### metadata_json 中的 Null Keys（162 个）

**A. 通用元数据字段（14 个，50/50 文件均为 null）**

| JSON Path | 解释 |
|-----------|------|
| `metadata_json.status` | 请求状态标记，litellm 内部使用 |
| `metadata_json.batch_models` | 批量调用模型列表，非批量调用时为 null |
| `metadata_json.router_metadata` | 路由器元数据，未使用路由策略时为 null |
| `metadata_json.eval_information` | 评估信息，未启用评估时为 null |
| `metadata_json.routing_decision` | 路由决策记录，未使用时为 null |
| `metadata_json.error_information` | 错误信息，成功调用时为 null |
| `metadata_json.applied_guardrails` | 应用的护栏规则（空列表而非 null） |
| `metadata_json.autorouter_savings` | 自动路由节省金额，未使用时为 null |
| `metadata_json.compression_savings` | 压缩节省，未启用压缩时为 null |
| `metadata_json.spend_logs_metadata` | 消费日志元数据 |
| `metadata_json.user_api_key_org_id` | API Key 组织 ID |
| `metadata_json.internal_call_origin` | 内部调用来源 |
| `metadata_json.proxy_server_request` | 代理服务器请求详情 |
| `metadata_json.batch_failed_requests` | 批量失败请求数 |
| `metadata_json.batch_successful_requests` | 批量成功请求数 |
| `metadata_json.guardrail_information` | 护栏信息 |
| `metadata_json.cold_storage_object_key` | 冷存储对象键 |
| `metadata_json.user_api_key_project_id` | API Key 项目 ID |
| `metadata_json.user_api_key_project_alias` | API Key 项目别名 |
| `metadata_json.vector_store_request_metadata` | 向量存储请求元数据 |
| `metadata_json.litellm_gateway_injected_cache` | 网关注入缓存 |
| `metadata_json.litellm_overhead_time_ms` | litellm 额外开销时间 |
| `metadata_json.mcp_tool_call_metadata` | MCP 工具调用元数据 |

**B. Token 详情字段（10 个，50/50 文件均为 null）**

| JSON Path | 解释 |
|-----------|------|
| `metadata_json.usage_object.prompt_tokens_details.text_tokens` | 输入文本 token 数明细 |
| `metadata_json.usage_object.prompt_tokens_details.audio_tokens` | 输入音频 token 数 |
| `metadata_json.usage_object.prompt_tokens_details.image_tokens` | 输入图片 token 数 |
| `metadata_json.usage_object.prompt_tokens_details.video_tokens` | 输入视频 token 数 |
| `metadata_json.usage_object.completion_tokens_details.text_tokens` | 输出文本 token 数明细 |
| `metadata_json.usage_object.completion_tokens_details.audio_tokens` | 输出音频 token 数 |
| `metadata_json.usage_object.completion_tokens_details.image_tokens` | 输出图片 token 数 |
| `metadata_json.usage_object.completion_tokens_details.video_tokens` | 输出视频 token 数 |
| `metadata_json.usage_object.completion_tokens_details.accepted_prediction_tokens` | 接受的预测 token 数 |
| `metadata_json.usage_object.completion_tokens_details.rejected_prediction_tokens` | 拒绝的预测 token 数 |

> 以上 token 明细字段在 `metadata_json.additional_usage_values` 和 `response_json.usage` 中有对应路径，同样为 null。提供商未返回细分 token 类型。

**C. 成本细分字段（5 个，50/50 文件均为 null）**

| JSON Path | 解释 |
|-----------|------|
| `metadata_json.cost_breakdown.service_tier` | 服务层级 |
| `metadata_json.cost_breakdown.data_residency` | 数据驻留区域 |
| `metadata_json.cost_breakdown.vertex_location` | Vertex AI 位置 |

**D. 模型能力/定价字段（约 120 个，50/50 文件均为 null）**

这些是 litellm 模型映射表中预定义但当前模型未使用的定价和能力字段，包括：

| 分类 | 代表性路径 | 解释 |
|------|-----------|------|
| 定价 | `metadata_json.model_map_information.model_map_value.input_cost_per_image` | 每张图片输入成本 |
| 定价 | `metadata_json.model_map_information.model_map_value.output_cost_per_second` | 每秒输出成本 |
| 定价 | `metadata_json.model_map_information.model_map_value.input_cost_per_token_batches` | 批量输入 token 成本 |
| 定价 | `metadata_json.model_map_information.model_map_value.input_cost_per_token_above_128k_tokens` | 超 128k token 输入成本 |
| 能力 | `metadata_json.model_map_information.model_map_value.supports_vision` | 是否支持视觉 |
| 能力 | `metadata_json.model_map_information.model_map_value.supports_audio_input` | 是否支持音频输入 |
| 能力 | `metadata_json.model_map_information.model_map_value.supports_web_search` | 是否支持网页搜索 |
| 能力 | `metadata_json.model_map_information.model_map_value.supports_computer_use` | 是否支持计算机使用 |
| 速率 | `metadata_json.model_map_information.model_map_value.rpm` | 每分钟请求数限制 |
| 速率 | `metadata_json.model_map_information.model_map_value.tpm` | 每分钟 token 数限制 |

> 完整的 120+ 个模型映射 null 字段均为 litellm 通用模型定义模板中 glm-5.2 不支持的字段。

#### response_json 中的 Null Keys（15 个）

| JSON Path | 出现次数 | 解释 |
|-----------|---------|------|
| `response_json.system_fingerprint` | 50/50 | 系统指纹，提供商未返回 |
| `response_json.choices[0].message.tool_calls` | 1/50 | 当 finish_reason=stop 时无 tool_calls |
| `response_json.choices[0].message.function_call` | 50/50 | 旧式 function_call 字段，已由 tool_calls 替代 |
| `response_json.usage.prompt_tokens_details.text_tokens` | 50/50 | 同上 token 明细 |
| `response_json.usage.prompt_tokens_details.audio_tokens` | 50/50 | 同上 |
| `response_json.usage.prompt_tokens_details.image_tokens` | 50/50 | 同上 |
| `response_json.usage.prompt_tokens_details.video_tokens` | 50/50 | 同上 |
| `response_json.usage.completion_tokens_details.text_tokens` | 50/50 | 同上 |
| `response_json.usage.completion_tokens_details.audio_tokens` | 50/50 | 同上 |
| `response_json.usage.completion_tokens_details.image_tokens` | 50/50 | 同上 |
| `response_json.usage.completion_tokens_details.video_tokens` | 50/50 | 同上 |
| `response_json.usage.completion_tokens_details.accepted_prediction_tokens` | 50/50 | 同上 |
| `response_json.usage.completion_tokens_details.rejected_prediction_tokens` | 50/50 | 同上 |

---

## 三、JSON Key 全量统计（递归嵌套，318 文件）

> **统计方法**：递归遍历每个 JSON 文件的所有嵌套层级（dict 的 key、list 元素的结构），提取完整 path 路径。同一 key path 在同一文件中出现多次只算一次。`[n]` 表示数组元素的泛化索引（任意位置）。
>
> **数据范围**：318 个详情文件，不包含 request_list.json。
>
> **总唯一 key path 数**：325

### 3.1 按出现文件数分布

| 出现文件数范围 | key 数量 | 说明 |
|--------------|---------|------|
| 318（全部） | 237 | 每个文件都存在的结构性 key |
| 300-317 | 6 | 仅 1 个文件缺失（317）或少数缺失 |
| 200-299 | 55 | 部分模型/会话才有 |
| 100-199 | 18 | Session A/B 才有（269/318≈84.6%） |
| 50-99 | 1 | Session A/B 才有 |
| 10-49 | 7 | 少量文件才有 |
| 1-9 | 1 | 极少数文件才有 |
| **合计** | **325** | |

### 3.2 出现在全部 318 个文件中的 key（237 个，100%）

#### A. 顶层 key（24 个）

| Key Path | 说明 |
|----------|------|
| `api_base` | API 网关地址 |
| `cache_hit` | 缓存命中标记 |
| `cache_key` | 缓存键 |
| `call_type` | 调用类型（acompletion） |
| `completion_start_time` | 首 token 时间 |
| `completion_tokens` | 输出 token 数 |
| `cost` | 费用 |
| `duration_s` | 总耗时（秒） |
| `end_time` | 结束时间 |
| `end_user` | 终端用户标识 |
| `key_hash` | API Key 哈希 |
| `key_name` | API Key 名称 |
| `messages_json` | 消息列表 |
| `metadata_json` | 元数据 |
| `model` | 模型名称 |
| `prompt_tokens` | 输入 token 数 |
| `request_id` | 请求唯一标识 |
| `response_json` | LLM 响应详情 |
| `session_id` | 会话 ID（每次调用唯一） |
| `start_time` | 开始时间 |
| `status` | 调用状态 |
| `system_json` | 独立系统消息字段（始终 null） |
| `team_name` | 团队名称（始终 null） |
| `tool_names_json` | 可用工具名称列表 |
| `total_tokens` | 总 token 数 |
| `ttft_s` | 首 token 耗时（秒） |

#### B. messages_json 消息级 key（2 个，100%）

| Key Path | 说明 |
|----------|------|
| `messages_json[n].content` | 消息内容 |
| `messages_json[n].role` | 消息角色（system/user/assistant/tool） |

#### C. metadata_json 基础设施字段（25 个，100%）

| Key Path | 说明 |
|----------|------|
| `metadata_json.applied_guardrails` | 护栏规则（空列表） |
| `metadata_json.attempted_fallbacks` | 尝试的回退次数 |
| `metadata_json.attempted_retries` | 尝试的重试次数 |
| `metadata_json.autorouter_savings` | 自动路由节省 |
| `metadata_json.batch_failed_requests` | 批量失败请求数 |
| `metadata_json.batch_models` | 批量调用模型列表 |
| `metadata_json.batch_successful_requests` | 批量成功请求数 |
| `metadata_json.cold_storage_object_key` | 冷存储对象键 |
| `metadata_json.compression_savings` | 压缩节省 |
| `metadata_json.error_information` | 错误信息 |
| `metadata_json.eval_information` | 评估信息 |
| `metadata_json.guardrail_information` | 护栏信息 |
| `metadata_json.internal_call_origin` | 内部调用来源 |
| `metadata_json.litellm_call_id` | LiteLLM 调用 ID |
| `metadata_json.litellm_gateway_injected_cache` | 网关注入缓存 |
| `metadata_json.litellm_overhead_time_ms` | 额外开销时间 |
| `metadata_json.max_retries` | 最大重试次数 |
| `metadata_json.mcp_tool_call_metadata` | MCP 工具调用元数据 |
| `metadata_json.proxy_server_request` | 代理服务器请求 |
| `metadata_json.requester_ip_address` | 请求方 IP |
| `metadata_json.router_metadata` | 路由器元数据 |
| `metadata_json.routing_decision` | 路由决策 |
| `metadata_json.spend_logs_metadata` | 消费日志元数据 |
| `metadata_json.status` | 请求状态标记 |
| `metadata_json.vector_store_request_metadata` | 向量存储元数据 |

#### D. metadata_json 用户/团队/Key 字段（9 个，100%）

| Key Path | 说明 |
|----------|------|
| `metadata_json.original_model_group` | 原始模型组 |
| `metadata_json.user_api_key` | API Key |
| `metadata_json.user_api_key_alias` | API Key 别名 |
| `metadata_json.user_api_key_org_id` | 组织 ID |
| `metadata_json.user_api_key_project_alias` | 项目别名 |
| `metadata_json.user_api_key_project_id` | 项目 ID |
| `metadata_json.user_api_key_team_alias` | 团队别名 |
| `metadata_json.user_api_key_team_id` | 团队 ID |
| `metadata_json.user_api_key_user_id` | 用户 ID |

#### E. metadata_json.cost_breakdown 费用明细（14 个，100%）

| Key Path | 说明 |
|----------|------|
| `metadata_json.cost_breakdown` | 费用明细根 |
| `metadata_json.cost_breakdown.data_residency` | 数据驻留 |
| `metadata_json.cost_breakdown.discount_amount` | 折扣金额 |
| `metadata_json.cost_breakdown.discount_percent` | 折扣百分比 |
| `metadata_json.cost_breakdown.input_cost` | 输入成本 |
| `metadata_json.cost_breakdown.margin_fixed_amount` | 固定利润 |
| `metadata_json.cost_breakdown.margin_percent` | 利润百分比 |
| `metadata_json.cost_breakdown.margin_total_amount` | 总利润 |
| `metadata_json.cost_breakdown.original_cost` | 原始成本 |
| `metadata_json.cost_breakdown.output_cost` | 输出成本 |
| `metadata_json.cost_breakdown.service_tier` | 服务层级 |
| `metadata_json.cost_breakdown.tool_usage_cost` | 工具使用成本 |
| `metadata_json.cost_breakdown.total_cost` | 总成本 |
| `metadata_json.cost_breakdown.vertex_location` | Vertex 位置 |

#### F. metadata_json 用量统计字段（6 个，100%）

> `usage_object` 和 `additional_usage_values` 包含完全相同的子字段结构，是 LiteLLM 日志的冗余记录。

| Key Path | 说明 |
|----------|------|
| `metadata_json.usage_object.completion_tokens` | 输出 token 数 |
| `metadata_json.usage_object.completion_tokens_details` | 输出 token 明细 |
| `metadata_json.usage_object.prompt_tokens` | 输入 token 数 |
| `metadata_json.usage_object.prompt_tokens_details` | 输入 token 明细 |
| `metadata_json.usage_object.total_tokens` | 总 token 数 |
| `metadata_json.additional_usage_values.completion_tokens_details` | 输出 token 明细（冗余） |
| `metadata_json.additional_usage_values.prompt_tokens_details` | 输入 token 明细（冗余） |

#### G. metadata_json.model_map_information.model_map_value 模型映射配置（130 个，100%）

> LiteLLM 内部的模型能力与定价配置表，全部 318 个文件完全一致。以下为 130 个子字段的完整逐个列表，简写前缀 `mmv` = `metadata_json.model_map_information.model_map_value`。

**G-1. 定价字段（82 个）**

| # | Key Path（mmv 省略） | 说明 |
|---|----------------------|------|
| 1 | `mmv.cache_creation_input_token_cost` | 缓存创建输入 token 成本 |
| 2 | `mmv.cache_creation_input_token_cost_above_1hr` | 缓存创建成本（1小时以上） |
| 3 | `mmv.cache_creation_input_token_cost_above_200k_tokens` | 缓存创建成本（200k token 以上） |
| 4 | `mmv.cache_creation_input_token_cost_above_272k_tokens` | 缓存创建成本（272k token 以上） |
| 5 | `mmv.cache_creation_input_token_cost_above_272k_tokens_flex` | 同上 flex 档 |
| 6 | `mmv.cache_creation_input_token_cost_above_272k_tokens_priority` | 同上 priority 档 |
| 7 | `mmv.cache_creation_input_token_cost_flex` | 缓存创建成本 flex 档 |
| 8 | `mmv.cache_creation_input_token_cost_priority` | 缓存创建成本 priority 档 |
| 9 | `mmv.cache_creation_input_token_cost_ultrafast` | 缓存创建成本 ultrafast 档 |
| 10 | `mmv.cache_read_input_token_cost` | 缓存读取输入 token 成本 |
| 11 | `mmv.cache_read_input_token_cost_above_200k_tokens` | 缓存读取成本（200k 以上） |
| 12 | `mmv.cache_read_input_token_cost_above_200k_tokens_priority` | 同上 priority 档 |
| 13 | `mmv.cache_read_input_token_cost_above_272k_tokens` | 缓存读取成本（272k 以上） |
| 14 | `mmv.cache_read_input_token_cost_above_272k_tokens_flex` | 同上 flex 档 |
| 15 | `mmv.cache_read_input_token_cost_above_272k_tokens_priority` | 同上 priority 档 |
| 16 | `mmv.cache_read_input_token_cost_above_512k_tokens` | 缓存读取成本（512k 以上） |
| 17 | `mmv.cache_read_input_token_cost_flex` | 缓存读取成本 flex 档 |
| 18 | `mmv.cache_read_input_token_cost_priority` | 缓存读取成本 priority 档 |
| 19 | `mmv.cache_read_input_token_cost_ultrafast` | 缓存读取成本 ultrafast 档 |
| 20 | `mmv.citation_cost_per_token` | 引用成本/token |
| 21 | `mmv.google_maps_grounding_cost_per_query` | Google Maps 每次查询成本 |
| 22 | `mmv.input_cost_per_audio_per_second` | 输入音频每秒成本 |
| 23 | `mmv.input_cost_per_audio_token` | 输入音频 token 成本 |
| 24 | `mmv.input_cost_per_character` | 输入每字符成本 |
| 25 | `mmv.input_cost_per_image` | 输入每图片成本 |
| 26 | `mmv.input_cost_per_image_token` | 输入图片 token 成本 |
| 27 | `mmv.input_cost_per_query` | 输入每次查询成本 |
| 28 | `mmv.input_cost_per_second` | 输入每秒成本 |
| 29 | `mmv.input_cost_per_token` | 输入每 token 成本 |
| 30 | `mmv.input_cost_per_token_above_128k_tokens` | 输入成本（128k 以上） |
| 31 | `mmv.input_cost_per_token_above_200k_tokens` | 输入成本（200k 以上） |
| 32 | `mmv.input_cost_per_token_above_200k_tokens_priority` | 同上 priority 档 |
| 33 | `mmv.input_cost_per_token_above_272k_tokens` | 输入成本（272k 以上） |
| 34 | `mmv.input_cost_per_token_above_272k_tokens_flex` | 同上 flex 档 |
| 35 | `mmv.input_cost_per_token_above_272k_tokens_priority` | 同上 priority 档 |
| 36 | `mmv.input_cost_per_token_above_512k_tokens` | 输入成本（512k 以上） |
| 37 | `mmv.input_cost_per_token_batches` | 批量输入 token 成本 |
| 38 | `mmv.input_cost_per_token_flex` | 输入成本 flex 档 |
| 39 | `mmv.input_cost_per_token_priority` | 输入成本 priority 档 |
| 40 | `mmv.input_cost_per_token_ultrafast` | 输入成本 ultrafast 档 |
| 41 | `mmv.input_cost_per_video_per_second` | 输入视频每秒成本 |
| 42 | `mmv.input_cost_per_video_token` | 输入视频 token 成本 |
| 43 | `mmv.annotation_cost_per_page` | 标注每页成本 |
| 44 | `mmv.ocr_cost_per_credit` | OCR 每点成本 |
| 45 | `mmv.ocr_cost_per_page` | OCR 每页成本 |
| 46 | `mmv.output_cost_per_audio_token` | 输出音频 token 成本 |
| 47 | `mmv.output_cost_per_character` | 输出每字符成本 |
| 48 | `mmv.output_cost_per_character_above_128k_tokens` | 输出字符成本（128k 以上） |
| 49 | `mmv.output_cost_per_image` | 输出每图片成本 |
| 50 | `mmv.output_cost_per_image_token` | 输出图片 token 成本 |
| 51 | `mmv.output_cost_per_reasoning_token` | 输出推理 token 成本 |
| 52 | `mmv.output_cost_per_reasoning_token_flex` | 推理 token flex 档 |
| 53 | `mmv.output_cost_per_reasoning_token_priority` | 推理 token priority 档 |
| 54 | `mmv.output_cost_per_second` | 输出每秒成本 |
| 55 | `mmv.output_cost_per_second_1080p` | 输出 1080p 每秒成本 |
| 56 | `mmv.output_cost_per_second_480p` | 输出 480p 每秒成本 |
| 57 | `mmv.output_cost_per_second_4k` | 输出 4K 每秒成本 |
| 58 | `mmv.output_cost_per_second_720p` | 输出 720p 每秒成本 |
| 59 | `mmv.output_cost_per_token` | 输出每 token 成本 |
| 60 | `mmv.output_cost_per_token_above_128k_tokens` | 输出成本（128k 以上） |
| 61 | `mmv.output_cost_per_token_above_200k_tokens` | 输出成本（200k 以上） |
| 62 | `mmv.output_cost_per_token_above_200k_tokens_priority` | 同上 priority 档 |
| 63 | `mmv.output_cost_per_token_above_272k_tokens` | 输出成本（272k 以上） |
| 64 | `mmv.output_cost_per_token_above_272k_tokens_flex` | 同上 flex 档 |
| 65 | `mmv.output_cost_per_token_above_272k_tokens_priority` | 同上 priority 档 |
| 66 | `mmv.output_cost_per_token_above_512k_tokens` | 输出成本（512k 以上） |
| 67 | `mmv.output_cost_per_token_batches` | 批量输出 token 成本 |
| 68 | `mmv.output_cost_per_token_flex` | 输出成本 flex 档 |
| 69 | `mmv.output_cost_per_token_priority` | 输出成本 priority 档 |
| 70 | `mmv.output_cost_per_token_ultrafast` | 输出成本 ultrafast 档 |
| 71 | `mmv.output_cost_per_video_per_second` | 输出视频每秒成本 |
| 72 | `mmv.output_cost_per_video_token` | 输出视频 token 成本 |
| 73 | `mmv.search_context_cost_per_query` | 搜索上下文每次查询成本 |
| 74 | `mmv.regional_endpoint_uplift_multiplier` | 区域端点上浮系数 |
| 75 | `mmv.regional_processing_uplift_multiplier_eu` | 欧洲区域处理上浮系数 |
| 76 | `mmv.regional_processing_uplift_multiplier_us` | 美国区域处理上浮系数 |
| 77 | `mmv.off_peak_pricing` | 非高峰定价 |
| 78 | `mmv.tiered_pricing` | 分层定价 |
| 79 | `mmv.provider_specific_entry` | 提供商特定条目 |
| 80 | `mmv.vertex_ai_audio_api` | Vertex AI 音频 API |
| 81 | `mmv.web_search_billing_unit` | Web 搜索计费单位 |
| 82 | `mmv.bedrock_converse_supports_strict_tools` | Bedrock 支持严格工具 |

**G-2. 能力标记字段（38 个）**

| # | Key Path（mmv 省略） | 说明 |
|---|----------------------|------|
| 1 | `mmv.supports_adaptive_thinking` | 支持自适应思考 |
| 2 | `mmv.supports_anthropic_thinking_payload` | 支持 Anthropic 思考载荷 |
| 3 | `mmv.supports_assistant_prefill` | 支持助手预填充 |
| 4 | `mmv.supports_audio_input` | 支持音频输入 |
| 5 | `mmv.supports_audio_output` | 支持音频输出 |
| 6 | `mmv.supports_computer_use` | 支持计算机使用 |
| 7 | `mmv.supports_embedding_image_input` | 支持嵌入图片输入 |
| 8 | `mmv.supports_function_calling` | 支持函数调用 |
| 9 | `mmv.supports_image_size` | 支持图片尺寸 |
| 10 | `mmv.supports_legacy_thinking` | 支持传统思考 |
| 11 | `mmv.supports_low_reasoning_effort` | 支持低推理强度 |
| 12 | `mmv.supports_max_reasoning_effort` | 支持最大推理强度 |
| 13 | `mmv.supports_mid_conversation_system` | 支持对话中插入 system |
| 14 | `mmv.supports_minimal_reasoning_effort` | 支持最小推理强度 |
| 15 | `mmv.supports_native_streaming` | 支持原生流式 |
| 16 | `mmv.supports_native_structured_output` | 支持原生结构化输出 |
| 17 | `mmv.supports_none_reasoning_effort` | 支持无推理强度 |
| 18 | `mmv.supports_parallel_function_calling` | 支持并行函数调用 |
| 19 | `mmv.supports_pdf_input` | 支持 PDF 输入 |
| 20 | `mmv.supports_prompt_cache_breakpoint` | 支持提示缓存断点 |
| 21 | `mmv.supports_prompt_caching` | 支持提示缓存 |
| 22 | `mmv.supports_reasoning` | 支持推理 |
| 23 | `mmv.supports_response_schema` | 支持响应 schema |
| 24 | `mmv.supports_system_messages` | 支持 system 消息 |
| 25 | `mmv.supports_tool_choice` | 支持工具选择 |
| 26 | `mmv.supports_tool_search` | 支持工具搜索 |
| 27 | `mmv.supports_url_context` | 支持 URL 上下文 |
| 28 | `mmv.supports_vision` | 支持视觉 |
| 29 | `mmv.supports_web_search` | 支持 Web 搜索 |
| 30 | `mmv.supports_xhigh_reasoning_effort` | 支持超高推理强度 |
| 31 | `mmv.thinking_always_on` | 思考始终开启 |
| 32 | `mmv.default_reasoning_effort` | 默认推理强度 |
| 33 | `mmv.bedrock_output_config_effort_ceiling` | Bedrock 输出配置强度上限 |
| 34 | `mmv.reasoning_effort_levels` | 推理强度级别 |
| 35 | `mmv.supported_audio_formats` | 支持的音频格式 |
| 36 | `mmv.supported_endpoints` | 支持的端点 |
| 37 | `mmv.supported_openai_params` | 支持的 OpenAI 参数 |
| 38 | `mmv.uses_embed_content` | 使用嵌入内容 |

**G-3. 模型参数字段（10 个）**

| # | Key Path（mmv 省略） | 说明 |
|---|----------------------|------|
| 1 | `mmv.key` | 模型映射键名 |
| 2 | `mmv.litellm_provider` | LiteLLM 提供商 |
| 3 | `mmv.max_input_tokens` | 最大输入 token 数 |
| 4 | `mmv.max_output_tokens` | 最大输出 token 数 |
| 5 | `mmv.max_tokens` | 最大 token 数 |
| 6 | `mmv.mode` | 模式 |
| 7 | `mmv.rpm` | 每分钟请求数 |
| 8 | `mmv.tpm` | 每分钟 token 数 |
| 9 | `mmv.output_vector_size` | 输出向量大小 |
| 10 | `mmv.prompt_cache_min_tokens` | 提示缓存最小 token 数 |

#### H. response_json 响应级 key（19 个，100%）

| Key Path | 说明 |
|----------|------|
| `response_json.choices` | 响应选项列表 |
| `response_json.choices[n].finish_reason` | 结束原因 |
| `response_json.choices[n].index` | 选项索引 |
| `response_json.choices[n].message` | 响应消息 |
| `response_json.choices[n].message.content` | 响应内容 |
| `response_json.choices[n].message.function_call` | 函数调用 |
| `response_json.choices[n].message.role` | 响应角色 |
| `response_json.choices[n].message.tool_calls` | 工具调用列表 |
| `response_json.created` | 创建时间戳 |
| `response_json.id` | 响应 ID |
| `response_json.model` | 响应模型 |
| `response_json.object` | 对象类型 |
| `response_json.system_fingerprint` | 系统指纹 |
| `response_json.usage` | 用量统计 |
| `response_json.usage.completion_tokens` | 输出 token |
| `response_json.usage.completion_tokens_details` | 输出明细 |
| `response_json.usage.prompt_tokens` | 输入 token |
| `response_json.usage.prompt_tokens_details` | 输入明细 |
| `response_json.usage.total_tokens` | 总 token |

### 3.3 非全量出现的 key（88 个，<100%）

#### A. 99.7% 出现（317 文件，缺 1 个）

| 出现数 | 占比 | Key Path | 说明 |
|--------|------|----------|------|
| 317 | 99.7% | `metadata_json.additional_usage_values.prompt_tokens_details.audio_tokens` | 输入音频 token |
| 317 | 99.7% | `metadata_json.additional_usage_values.prompt_tokens_details.cached_tokens` | 缓存 token |
| 317 | 99.7% | `metadata_json.usage_object.prompt_tokens_details.audio_tokens` | 同上（冗余） |
| 317 | 99.7% | `metadata_json.usage_object.prompt_tokens_details.cached_tokens` | 同上（冗余） |
| 317 | 99.7% | `response_json.usage.prompt_tokens_details.audio_tokens` | 同上（冗余） |
| 317 | 99.7% | `response_json.usage.prompt_tokens_details.cached_tokens` | 同上（冗余） |

#### B. 92-93% 出现（294-295 文件）

| 出现数 | 占比 | Key Path | 说明 |
|--------|------|----------|------|
| 295 | 92.8% | `metadata_json.additional_usage_values.cost` | 额外用量费用 |
| 295 | 92.8% | `metadata_json.usage_object.cost` | 用量费用 |
| 295 | 92.8% | `response_json.usage.cost` | 响应费用 |
| 294 | 92.5% | `metadata_json.additional_usage_values.prompt_tokens_details.image_tokens` | 图片 token |
| 294 | 92.5% | `metadata_json.additional_usage_values.prompt_tokens_details.text_tokens` | 文本 token |
| 294 | 92.5% | `metadata_json.additional_usage_values.prompt_tokens_details.video_tokens` | 视频 token |
| 294 | 92.5% | `metadata_json.usage_object.prompt_tokens_details.image_tokens` | 同上（冗余） |
| 294 | 92.5% | `metadata_json.usage_object.prompt_tokens_details.text_tokens` | 同上（冗余） |
| 294 | 92.5% | `metadata_json.usage_object.prompt_tokens_details.video_tokens` | 同上（冗余） |
| 294 | 92.5% | `response_json.usage.prompt_tokens_details.image_tokens` | 同上（冗余） |
| 294 | 92.5% | `response_json.usage.prompt_tokens_details.text_tokens` | 同上（冗余） |
| 294 | 92.5% | `response_json.usage.prompt_tokens_details.video_tokens` | 同上（冗余） |

#### C. 88-91% 出现（消息级工具调用字段，Session A/B）

| 出现数 | 占比 | Key Path | 说明 |
|--------|------|----------|------|
| 289 | 90.9% | `messages_json[n].tool_call_id` | 消息中工具调用 ID |
| 289 | 90.9% | `messages_json[n].tool_calls` | 消息中的工具调用列表 |
| 289 | 90.9% | `messages_json[n].tool_calls[n].function` | 工具函数对象 |
| 289 | 90.9% | `messages_json[n].tool_calls[n].function.arguments` | 函数参数（JSON 字符串） |
| 289 | 90.9% | `messages_json[n].tool_calls[n].function.name` | 函数名 |
| 289 | 90.9% | `messages_json[n].tool_calls[n].id` | 工具调用 ID |
| 289 | 90.9% | `messages_json[n].tool_calls[n].type` | 工具调用类型 |
| 287 | 90.3% | `metadata_json.additional_usage_values.cache_read_input_tokens` | 缓存读取 token |
| 287 | 90.3% | `metadata_json.cost_breakdown.cache_read_cost` | 缓存读取成本 |
| 281 | 88.4% | `response_json.choices[n].message.tool_calls[n].function` | 响应中工具调用函数 |
| 281 | 88.4% | `response_json.choices[n].message.tool_calls[n].function.arguments` | 函数参数 |
| 281 | 88.4% | `response_json.choices[n].message.tool_calls[n].function.name` | 函数名 |
| 281 | 88.4% | `response_json.choices[n].message.tool_calls[n].id` | 工具调用 ID |
| 281 | 88.4% | `response_json.choices[n].message.tool_calls[n].type` | 工具调用类型 |

#### D. 84-85% 出现（Session A/B 扩展消息字段）

| 出现数 | 占比 | Key Path | 说明 |
|--------|------|----------|------|
| 269 | 84.6% | `messages_json[n].agent` | Agent 标识（值为 "cli"） |
| 269 | 84.6% | `messages_json[n].conversationRequestId` | **会话关联键** |
| 267 | 84.0% | `messages_json[n].messageId` | 消息 ID |
| 267 | 84.0% | `messages_json[n].model` | 消息级模型名 |
| 267 | 84.0% | `messages_json[n].reasoning` | 推理过程文本 |
| 267 | 84.0% | `messages_json[n].requestModelId` | 请求模型 ID |
| 267 | 84.0% | `messages_json[n].requestModelName` | 请求模型名 |
| 267 | 84.0% | `messages_json[n].traceId` | 追踪 ID |

#### E. 63-70% 出现（输出 token 明细字段）

> 下表各 key 在 `metadata_json.additional_usage_values`、`metadata_json.usage_object`、`response_json.usage` 三处对称出现，此处仅列一次，实际各 3 个冗余 path。

| 出现数 | 占比 | Key Path 模式 | 说明 |
|--------|------|-------------|------|
| 224 | 70.4% | `*.completion_tokens_details.accepted_prediction_tokens`（×3） | 接受的预测 token |
| 224 | 70.4% | `*.completion_tokens_details.audio_tokens`（×3） | 输出音频 token |
| 224 | 70.4% | `*.completion_tokens_details.reasoning_tokens`（×3） | 推理 token |
| 224 | 70.4% | `*.completion_tokens_details.rejected_prediction_tokens`（×3） | 拒绝的预测 token |
| 201 | 63.2% | `*.completion_tokens_details.image_tokens`（×3） | 输出图片 token |
| 201 | 63.2% | `*.completion_tokens_details.text_tokens`（×3） | 输出文本 token |
| 201 | 63.2% | `*.completion_tokens_details.video_tokens`（×3） | 输出视频 token |
| 195 | 61.3% | `metadata_json.cost_breakdown.reasoning_cost` | 推理成本（唯一 path） |
| 195 | 61.3% | `response_json.choices[n].message.reasoning_content` | 响应推理内容（唯一 path） |

#### F. 53% 出现（Session B/C 用量明细字段）

| 出现数 | 占比 | Key Path | 说明 |
|--------|------|----------|------|
| 168 | 52.8% | `messages_json[n].argumentsDisplayText` | 参数显示文本 |
| 168 | 52.8% | `messages_json[n].rawUsage` | 原始用量对象 |
| 168 | 52.8% | `messages_json[n].rawUsage.completion_tokens` | 原始输出 token |
| 168 | 52.8% | `messages_json[n].rawUsage.completion_tokens_details` | 原始输出明细 |
| 168 | 52.8% | `messages_json[n].rawUsage.completion_tokens_details.reasoning_tokens` | 原始推理 token |
| 168 | 52.8% | `messages_json[n].rawUsage.prompt_tokens` | 原始输入 token |
| 168 | 52.8% | `messages_json[n].rawUsage.total_tokens` | 原始总 token |
| 168 | 52.8% | `messages_json[n].usage` | 用量对象 |
| 168 | 52.8% | `messages_json[n].usage.inputTokens` | 输入 token |
| 168 | 52.8% | `messages_json[n].usage.inputTokensDetails` | 输入明细 |
| 168 | 52.8% | `messages_json[n].usage.inputTokensDetails[n].cached_tokens` | 缓存 token |
| 168 | 52.8% | `messages_json[n].usage.outputTokens` | 输出 token |
| 168 | 52.8% | `messages_json[n].usage.outputTokensDetails` | 输出明细 |
| 168 | 52.8% | `messages_json[n].usage.outputTokensDetails[n].reasoning_tokens` | 推理 token |
| 168 | 52.8% | `messages_json[n].usage.requests` | 请求数 |
| 168 | 52.8% | `messages_json[n].usage.totalTokens` | 总 token |

#### G. 23% 以下出现（少量文件特有）

| 出现数 | 占比 | Key Path | 说明 |
|--------|------|----------|------|
| 73 | 23.0% | `messages_json[n].entryId` | 条目 ID |
| 23 | 7.2% | `response_json.choices[n].message.provider_specific_fields` | 提供商特定字段 |
| 23 | 7.2% | `response_json.choices[n].message.provider_specific_fields.refusal` | 拒绝信息 |
| 23 | 7.2% | `response_json.choices[n].provider_specific_fields` | 提供商特定字段（choices 级） |
| 23 | 7.2% | `response_json.moderation` | 内容审核 |
| 23 | 7.2% | `response_json.request_id` | 响应请求 ID |
| 23 | 7.2% | `response_json.service_tier` | 服务层级 |
| 22 | 6.9% | `messages_json[n].reasoning_content` | 消息推理内容 |
| 7 | 2.2% | `messages_json[n].isMeta` | 元消息标记 |

### 3.4 关键发现

1. **237 个 key（73%）出现在全部 318 个文件中** —— 这些是 LiteLLM 日志的结构性框架，包括顶层元数据、metadata_json 配置、model_map 定价表、response_json 结构等

2. **`model_map_information.model_map_value` 下有 130 个子字段** —— 占全部 key 的 40%，是 LiteLLM 内部的模型能力与定价配置表，全部为 null（该模型不支持的功能/定价）

3. **出现率与 Session 分布强相关**：
   - 84.6%（269 文件）的 key 如 `conversationRequestId`、`agent`、`messageId`、`traceId` → 只在 Session A+B（269 文件）出现，Session C（49 文件）没有
   - 52.8%（168 文件）的 key 如 `rawUsage`、`usage.inputTokens` → 只在 Session B（74）+ Session C 部分文件出现
   - 7.2%（23 文件）的 key 如 `provider_specific_fields`、`moderation` → 来自 glm-5.3-flash 模型特有的响应字段

4. **三处用量统计结构对称重复**：`response_json.usage`、`metadata_json.usage_object`、`metadata_json.additional_usage_values` 三者包含完全相同的子字段结构（prompt_tokens、completion_tokens、total_tokens 及其 details），是 LiteLLM 日志的冗余记录

5. **消息累积模式下 key 覆盖率递增**：Session A 的 195 个文件按消息累积链组织，第1轮（27 文件）只有基础 key，第2轮开始出现 `conversationRequestId` 等扩展 key，第5轮（79 文件）包含最丰富的 key 集合

---

## 四、JSON Value 中的 XML 文档解析

### 4.1 XML 内容分布

在 50 个详情文件中，共检测到 **3375 处** 包含 XML 标签的 JSON value，分布在约 70 个不同的 JSON path 上。所有文件的 messages_json 结构高度一致（同一会话的不同轮次）。

### 4.2 关键 XML 文档解析

#### A. System Prompt — `messages_json[0].content`

- **JSON Path**: `messages_json[0].content`
- **XML Path**: 根级 XML 标签，无外层包裹
- **XML 标签列表** (36 个):

| XML 标签 | 解释 |
|---------|------|
| `<user_query>` | 用户输入内容标记 |
| `<content_policy>` | 内容安全策略 |
| `<personal_files_safety>` | 个人文件操作安全规则 |
| `<regional_conventions>` | 区域约定（中文/股票颜色等） |
| `<working_modes>` | 工作模式（Agent/Plan/Ask） |
| `<agent_loop>` | Agent 循环步骤说明 |
| `<result_presentation>` | 结果展示规则 |
| `<sharing_files>` | 文件分享规则 |
| `<final_answer_instructions>` | 最终回答格式说明 |
| `<automations>` | 自动化任务说明 |
| `<tool_use>` | 工具使用规则 |
| `<instructions_for_visualizer>` | 可视化器使用说明 |
| `<task_management>` | 任务管理工具使用规则 |
| `<asking_questions>` | 提问规则 |
| `<tool_usage_policy>` | 工具使用策略 |
| `<agent_skills>` | Agent 技能说明 |
| `<library_routing>` | 资料库路由规则 |
| `<app_development_routing>` | 应用开发路由 |
| `<office_skill_routing>` | Office 文件路由 |
| `<plugin_recommendation>` | 插件推荐规则 |
| `<expert_management>` | 专家管理规则 |
| `<mcp_configuration>` | MCP 配置说明 |
| `<response_language>` | 响应语言设置 |
| `<memory_system>` | 记忆系统说明 |
| `<user_memory>` | 用户记忆内容 |

> 这是一个约 44808 字符的超长 system prompt，包含完整的 Agent 行为规则、工具说明、安全策略等。

#### B. System Reminder — `messages_json[1].content` / `messages_json[64].content` / `messages_json[173].content` 等

- **JSON Path**: `messages_json[N].content`（N=1, 64, 173, 179, 254 等周期性出现）
- **XML Path**: `<system-reminder>` 标签包裹
- **内容**: 包含 `<user_info>`, `<identity_context>`, `<product_identity>`, `<project_context>`, `<current_time>`, `<user_query>` 等子标签
- **解释**: 每轮对话开始前注入的上下文提醒，包含用户环境信息、身份文件内容、项目文件结构等

#### C. 工具调用参数 — `messages_json[N].tool_calls[0].function.arguments`

- **JSON Path**: `messages_json[N].tool_calls[0].function.arguments`（N=2,5,9,...,100,...,168,...,273,...,383,...）
- **XML Path**: 参数值中包含 `<String>`, `<Task>`, `<TodoItem>`, `<Tool>`, `<ToolCall>`, `<ExecutionResult>` 等标签
- **解释**: 工具调用参数中嵌入的 Java 类型序列化文本，来自 agent-core-java 框架的调试输出或代码内容

#### D. Tool 返回结果 — `messages_json[N].content`（role=tool）

- **JSON Path**: `messages_json[N].content`（N=8, 189 等）
- **XML Path**: 包含 `<ydh110100>`, `<label>` 等 Git commit 信息标签
- **解释**: Bash 命令执行 git show 的输出，包含 commit 作者、日期、merge 信息等

#### E. Assistant 推理内容 — `messages_json[N].reasoning`

- **JSON Path**: `messages_json[N].reasoning`（N=63, 82, 174 等）
- **XML Path**: 包含 `<String>` 标签
- **解释**: LLM 的 reasoning（思考过程）输出

---

## 五、文件关联与调用链构建

### 5.1 关联键层次体系（深度分析）

对 50 个详情文件的全量字段进行了基数分析，发现关联键呈现清晰的 4 层层次结构：

#### Level 1 — 会话/对话轮次层（跨所有 50 文件共享）

| 关联键 | 唯一值数 | 关联范围 | 说明 |
|--------|---------|---------|------|
| `messages_json[*].conversationRequestId` | **5** | 每个 convId 覆盖全部 50 文件 | **最高层关联键**：5 个值对应同一会话中的 5 个用户对话轮次 |
| `messages_json[*].traceId` | **5** | 每个 traceId 覆盖全部 50 文件 | 与 conversationRequestId **1:1 映射**，是同一轮次的链路追踪 ID |
| `messages_json[*].agent` | 1 | "cli"（全部 50 文件） | Agent 类型，均为 CLI 模式 |
| `messages_json[*].requestModelId` | 1 | "custom-local:hk-GLM-5.2" | 请求模型 ID |
| `messages_json[*].requestModelName` | 1 | "hk-GLM-5.2" | 请求模型名称 |

#### Level 2 — API Key / 团队层（跨所有 50 文件共享）

| 关联键 | 唯一值数 | 值 | 说明 |
|--------|---------|----|------|
| `key_name` / `key_hash` / `metadata_json.user_api_key` | 1 | 00925504 / a731c007... | API Key 标识 |
| `metadata_json.user_api_key_team_id` | 1 | f58b38bd-738a-4a6d-b8b7-7deccf6ab633 | 团队 ID |
| `metadata_json.user_api_key_team_alias` | 1 | 分布式 | 团队别名 |
| `metadata_json.user_api_key_user_id` | 1 | default_user_id | 用户 ID |
| `metadata_json.requester_ip_address` | 1 | 118.193.37.170 | 请求者 IP |
| `metadata_json.original_model_group` | 1 | GLM-5.2 | 模型组 |
| `api_base` | 1 | https://st8tp3ajl0df3n8b8l8qu... | API 网关 |
| `model` / `call_type` | 1 | glm-5.2 / acompletion | 模型与调用类型 |

#### Level 3 — 单次 LLM 调用层（每文件唯一）

| 关联键 | 唯一值数 | 说明 |
|--------|---------|------|
| `request_id` | 50 | 请求唯一标识（= 文件名） |
| `session_id` | 50 | 会话 ID（**每次调用重新生成**，非持久会话） |
| `metadata_json.litellm_call_id` | 50 | litellm 内部调用 ID |
| `cache_key` | 50 | 缓存键（每次唯一） |

#### Level 4 — 消息增量层（顺序链式关联）

| 关联键 | 唯一值数 | 跨文件复用 | 说明 |
|--------|---------|-----------|------|
| `messages_json[*].messageId` | 194 | 193 个出现在多文件中 | **链式关联**：文件 N 的 messageId 集合是文件 N+1 的子集，每次新增 1-2 个 |

**顺序链式关联验证**（连续文件间的 messageId 重叠）：

| 文件对 | 重叠 messageId 数 | 前文件独有 | 后文件独有 | 前文件总数 | 后文件总数 |
|--------|------------------|-----------|-----------|-----------|-----------|
| #1 → #2 | 145 | 0 | 1 | 145 | 146 |
| #2 → #3 | 146 | 0 | 1 | 146 | 147 |
| #3 → #4 | 147 | 0 | 1 | 147 | 148 |
| #4 → #5 | 148 | 0 | 1 | 148 | 149 |
| #5 → #6 | 149 | 0 | 1 | 149 | 150 |

> 每次调用新增 1 个 messageId（assistant 的 tool_calls 消息），tool 返回结果复用已有 messageId。这说明 messages_json 是累积式的——每次 LLM 调用都会携带之前所有消息历史。

### 5.2 conversationRequestId 深度分析（5 轮对话的完整映射）

5 个 conversationRequestId 与 5 个 traceId **严格 1:1 映射**，对应同一会话中的 5 个用户对话轮次。以消息数最多的文件（411 条消息）为基准，映射关系如下：

| conversationRequestId | traceId | 消息索引范围 | 消息数 | user | assistant | tool | 对应轮次 |
|----------------------|---------|------------|--------|------|-----------|------|---------|
| `01a0e74498327d2f8db2b184a9a16a0b` | `5de2c718...` | 1-63 | 63 | 1 | 27 | 35 | 第 1 轮 |
| `01a0e7521bad7302841f29e5a26d1605` | `cbb5e7b7...` | 64-172 | 109 | 1 | 54 | 54 | 第 2 轮 |
| `01a0e76494717c29b94c4e14a11db026` | `651dc8f2...` | 173-178 | 6 | 1 | 3 | 2 | 第 3 轮（短） |
| `01a0e76e6571711ba593d3c479317f4a` | `14de8afa...` | 179-253 | 75 | 1 | 32 | 42 | 第 4 轮 |
| `01a0e776b70871c998a8ec07a0311725` | `52356d9c...` | 254-410 | 157 | 1 | 78 | 78 | 第 5 轮（最长） |

**关键发现**：
- 每轮以 1 条 user 消息开始，后面跟若干 assistant + tool 消息对（Agent Loop）
- 第 3 轮最短（仅 6 条消息，3 次 LLM 调用），可能是用户的简短确认或追加指令
- 第 5 轮最长（157 条消息，78 次 LLM 调用），是主要的代码编辑阶段
- **所有 50 个详情文件的"活跃" conversationRequestId 都是第 5 轮**（`01a0e776...`），说明这 50 次导出的 LLM 调用全部发生在第 5 轮的 Agent Loop 内

### 5.3 更高层次关联键分析

**结论：不存在比 conversationRequestId 更高的跨文件关联键。**

分析过程：
1. **conversationRequestId + traceId** 是最高层的关联键对，两者 1:1 映射，共同标识 5 个对话轮次
2. 在 conversationRequestId 之上，只有 Level 2 的 API Key/Team 层（全部相同值，无法区分子会话）
3. `session_id` 虽然在顶层，但每次 LLM 调用都重新生成（50 个唯一值），**不是持久会话 ID**，无法用于关联
4. 唯一能区分"哪次调用属于哪一轮"的方法是：检查 messages_json 中最后一条 user 消息的 conversationRequestId

**实际关联模型**：

```
API Key (00925504) + Team (分布式) + IP (118.193.37.170)     ← Level 2: 全局相同
  └── 会话（无持久 session_id，由 messages_json 累积式传递）
        ├── 第1轮 convReqId=01a0e744... traceId=5de2c718... (msg 1-63)
        ├── 第2轮 convReqId=01a0e752... traceId=cbb5e7b7... (msg 64-172)
        ├── 第3轮 convReqId=01a0e764... traceId=651dc8f2... (msg 173-178)
        ├── 第4轮 convReqId=01a0e76e... traceId=14de8afa... (msg 179-253)
        └── 第5轮 convReqId=01a0e776... traceId=52356d9c... (msg 254-410)  ← 50个详情文件全部在此轮
              ├── Call #1  request_id=as-wkkxitd8ck   (msg 313) → Read
              ├── Call #2  request_id=as-ua0057sugk   (msg 315) → Read
              ├── ...
              └── Call #50 request_id=3337b052-...     (msg 411) → stop
```

### 5.4 完整调用链结构

50 个详情文件全部属于第 5 轮对话（conversationRequestId: `01a0e776b70871c998a8ec07a0311725`）：

```
conversationRequestId: 01a0e776b70871c998a8ec07a0311725
traceId: 52356d9cffc2149a2d2c4ca82164f948
Wall-clock: 2026-09-28T10:08:00 → 2026-09-28T10:18:31 (约 10 分 31 秒)
LLM 总耗时: 287.5s
调用次数: 50 次
消息增长: 313 → 411 (每次调用 +2 条消息)
Token 消耗: 6,632,480 prompt + 8,211 completion = 6,640,691 total
模型: glm-5.2 (dashscope)
API Key: 00925504
```

**调用模式**: Agent Loop — 每次调用 LLM 返回一个 tool_call，执行工具后将结果追加到消息列表，再次调用 LLM，直到 finish_reason=stop。

---

## 六、两个完整调用链示例

### 示例链 1: 开头 3 次调用（初始 Read + Edit 阶段）

**用户请求**: 进入 agent-core-java 项目，将 c3a597f7e114e787ad35ad7e3b13af8292793b5e 提交合入当前 develop 分支，如有冲突，先分析冲突，让我确认。

| # | request_id | start_time | end_time | session_id | prompt_tokens | completion_tokens | duration | ttft | response_tool | finish_reason |
|---|-----------|------------|----------|------------|--------------|-------------------|----------|------|---------------|---------------|
| 1 | as-wkkxitd8ck | 10:08:00.100 | 10:08:04.233 | ba6ef438-... | 125405 | 50 | 4.13s | 3.41s | Read | tool_calls |
| 2 | as-ua0057sugk | 10:08:10.135 | 10:08:13.154 | 0267c285-... | 125671 | 50 | 3.02s | 2.38s | Read | tool_calls |
| 3 | as-7xry1zd57r | 10:08:19.122 | 10:08:22.611 | 121df515-... | 126026 | 125 | 3.49s | 2.69s | Edit | tool_calls |

**关键 value**:
- Call #1: Read `TaskPlanningRail.java` offset=21, limit=20（查看文件头部）
- Call #2: Read `TaskPlanningRail.java` offset=39, limit=20（查看文件后续部分）
- Call #3: Edit `TaskPlanningRail.java`（修改 import 语句）

### 示例链 2: 末尾 3 次调用（日志写入 + 任务完成 + 总结返回）

| # | request_id | start_time | end_time | session_id | prompt_tokens | completion_tokens | duration | ttft | response_tool | finish_reason |
|---|-----------|------------|----------|------------|--------------|-------------------|----------|------|---------------|---------------|
| 48 | 64cdedf8-... | 10:17:48.324 | 10:18:03.187 | 456818f7-... | 140100 | 748 | 14.86s | 6.10s | Edit | tool_calls |
| 49 | as-rj24zdf168 | 10:18:10.021 | 10:18:13.137 | 1e9f5a75-... | 140877 | 18 | 3.12s | 2.56s | TaskUpdate | tool_calls |
| 50 | 3337b052-... | 10:18:19.994 | 10:18:31.047 | cabdbb52-... | 140904 | 661 | 11.05s | 3.53s | None | stop |

**关键 value**:
- Call #48: Edit 写入 `.workbuddy/memory/2026-09-28.md` 工作日志（合入记录），completion=748 tokens（最长输出）
- Call #49: TaskUpdate 标记 taskId=2 为 completed
- Call #50: finish_reason=**stop**，返回合入完成总结文本（661 tokens），内容包含改动文件清单、冲突处理方式等

---

## 七、调用时序图

上方时序图展示了示例链 2（Call #48-#50）的完整时序：

1. **Call #48** (10:17:48 - 10:18:03, 14.9s): LLM 收到 140100 tokens prompt，思考 6.1s 后输出 748 tokens，调用 Edit 工具写入工作日志
2. **7s 间隔**: 工具执行 + 消息追加
3. **Call #49** (10:18:10 - 10:18:13, 3.1s): LLM 快速决策，输出 18 tokens 调用 TaskUpdate 标记任务完成
4. **6s 间隔**: 工具执行
5. **Call #50** (10:18:19 - 10:18:31, 11.1s): LLM 生成最终总结（661 tokens），finish_reason=stop，用户收到合入完成报告

---

## 八、全量分析（318 文件，新增 268 个）

新增 268 个详情文件后，对全部 318 个文件进行了全量扫描，发现以下重要变化：

### 8.1 新增 Null Key（17 个，仅出现在新增文件中）

对比原 50 个文件（179 个 null path），新增 268 个文件中多出 **17 个** 之前未见的 null path：

#### A. glm-5.3-flash 模型映射字段（11 个，出现在 48/268 个新文件中）

这些 null 来自 `glm-5.3-flash` 模型的调用，其 model_map_value 中以下字段为 null（而 glm-5.2 有值）：

| JSON Path | 解释 |
|-----------|------|
| `metadata_json.model_map_information.model_map_value.mode` | 模型模式（flash 未设置） |
| `metadata_json.model_map_information.model_map_value.max_tokens` | 最大 token 数 |
| `metadata_json.model_map_information.model_map_value.max_input_tokens` | 最大输入 token 数 |
| `metadata_json.model_map_information.model_map_value.max_output_tokens` | 最大输出 token 数 |
| `metadata_json.model_map_information.model_map_value.supports_reasoning` | 是否支持推理 |
| `metadata_json.model_map_information.model_map_value.supports_function_calling` | 是否支持函数调用 |
| `metadata_json.model_map_information.model_map_value.supports_response_schema` | 是否支持 response schema |
| `metadata_json.model_map_information.model_map_value.supports_tool_choice` | 是否支持 tool choice |
| `metadata_json.model_map_information.model_map_value.supports_prompt_caching` | 是否支持 prompt 缓存 |
| `metadata_json.model_map_information.model_map_value.cache_read_input_token_cost` | 缓存读取成本 |

> 这些 null 是因为 `glm-5.3-flash` 在 litellm 模型映射表中配置不完整导致的，与 `glm-5.2` 的配置形成对比。

#### B. 新增响应字段（3 个，出现在 23/268 个新文件中）

| JSON Path | 出现次数 | 解释 |
|-----------|---------|------|
| `response_json.moderation` | 23/268 | 内容审核结果（null 表示未触发审核） |
| `response_json.service_tier` | 23/268 | 服务层级标记 |
| `response_json.choices[0].message.provider_specific_fields.refusal` | 23/268 | 提供商特定字段中的拒绝标记 |

> 这些字段是 litellm 新版本在部分响应中引入的额外字段，值为 null 表示未使用相应功能。

#### C. 其他新增 null（3 个）

| JSON Path | 出现次数 | 解释 |
|-----------|---------|------|
| `tool_names_json` | 24/268 | 工具名称列表为 null（flash 调用中部分未传入工具列表） |
| `metadata_json.usage_object.prompt_tokens_details` | 1/268 | prompt token 详情对象整体为 null |
| `metadata_json.additional_usage_values.prompt_tokens_details` | 1/268 | 同上，additional_usage_values 中的对应字段 |

### 8.2 全量关联键基数分析（318 文件）

| 关联键 | 唯一值数 | 值示例 | 关联层次 |
|--------|---------|--------|---------|
| **conversationRequestId** | **7** | 01a0e776..., 01a0e69f..., 42c6bfb2... | **最高层有效关联键** |
| **traceId** | **6** | 52356d9c..., 42c6bfb2... | 与 convReqId 近 1:1 映射 |
| `model` | 2 | glm-5.2, glm-5.3-flash | 模型类型 |
| `meta.original_model_group` | 2 | GLM-5.2, GLM-5.3-Flash | 模型组 |
| `api_base` | 2 | volceapi.com/v1 | API 网关（2 个 URL，后缀差异） |
| `key_name` / `key_hash` | 1 | 00925504 | API Key |
| `meta.user_api_key_team_alias` | 1 | 分布式 | 团队 |
| `meta.requester_ip_address` | 1 | 118.193.37.170 | 请求者 IP |
| `agent` | 1 | cli | Agent 类型 |
| `requestModelName` | 1 | hk-GLM-5.2 | 请求模型名 |
| `request_id` / `session_id` / `cache_key` | 318 | （每文件唯一） | 单次调用层 |
| `messageId` | 267 | （大部分跨文件复用） | 消息增量层 |

### 8.3 会话分组：3 个独立会话 + 1 个特殊调用

全量分析后发现 **3 个独立会话** 和 **1 个特殊调用**，远超之前认为的单一会话：

#### Session A — agent-core-java 代码合并（195 次调用）

| 属性 | 值 |
|------|----|
| 时间范围 | 2026-09-28 09:07:06 → 10:18:31（约 71 分钟） |
| 调用次数 | 195 |
| LLM 总耗时 | 1139.0s |
| 模型 | glm-5.2 |
| Token 消耗 | prompt=18,731,874 + completion=35,790 = 18,767,664 |
| conversationRequestIds | 5 个（对应 5 轮用户对话） |
| traceIds | 5 个（与 convReqId 1:1 映射） |
| 消息数 | 2 → 411（累积式增长） |
| 用户请求 | 合入 Git 提交到 develop 分支 |

5 轮用户对话：
1. `01a0e744...` → "进入 agent-core-java 项目，将 c3a597f... 提交合入当前 develop 分支，如有冲突，先分析冲突，让我确认。"
2. `01a0e752...` → "同意"（确认冲突处理方案）
3. `01a0e764...` → "为什么 DeepAgent.java 的改法不一样？"（追问，3 次调用）
4. `01a0e76e...` → "再将 308d7bbf... 提交合入当前 develop_merge_930 分支，如有冲突，先分析冲突，让我确认。"
5. `01a0e776...` → "是"（确认，79 次调用，最长轮次）

#### Session B — ruoyi 服务重启（74 次调用）

| 属性 | 值 |
|------|----|
| 时间范围 | 2026-09-28 06:07:06 → 06:21:51（约 15 分钟） |
| 调用次数 | 74 |
| LLM 总耗时 | 363.8s |
| 模型 | glm-5.2 |
| Token 消耗 | prompt=4,738,143 + completion=11,469 = 4,749,612 |
| conversationRequestIds | 2 个 |
| traceIds | 1 个（42c6bfb2，与第 2 个 convReqId 相同） |
| 消息数 | 2 → 154 |
| 用户请求 | "重新启动 ruoyi 服务" |

2 轮用户对话：
1. `01a0e69f...` → "重新启动 ruoyi 服务"（msg 1-14，7 次调用）
2. `42c6bfb2...` → （无 user 消息，67 次 assistant+tool 调用，疑似自动继续或追问）

> 注意：Session B 的第 2 个 conversationRequestId (42c6bfb2) 同时也是其 traceId，说明 traceId 可能被复用为 conversationRequestId。

#### Session C — 金融新闻/日报分析（48 次调用）

| 属性 | 值 |
|------|----|
| 时间范围 | 2026-09-28 01:00:42 → 08:14:02（约 7 小时） |
| 调用次数 | 48 |
| LLM 总耗时 | 2539.5s |
| 模型 | **glm-5.3-flash**（不同于 A/B） |
| Token 消耗 | prompt=1,265,913 + completion=112,345 = 1,378,258 |
| conversationRequestIds | **0 个**（消息中无 convReqId 字段） |
| traceIds | **0 个** |
| 消息数 | 2 → 17（每次调用独立，无累积） |
| 消息角色 | 仅 system + user（无 assistant/tool，非 Agent Loop） |

**Session C 特征**：
- 使用 Hermes Agent system prompt（"You are Hermes Agent, created by Nous Research"），与 Session A/B 的 WorkBuddy system prompt 完全不同
- 消息结构简单：只有 system + user，无 conversationRequestId / traceId / agent 等扩展字段
- 调用的是不同模型（glm-5.3-flash vs glm-5.2）
- 触发的是 Skill 调用：`financial-news-rss`（4 次）、`a-share-market-analysis`（12 次）、`ai-news-daily`（9 次）、对话回顾总结（2 次）
- 消息数不累积（每次调用独立，不携带历史消息）
- 属于独立的 Hermes Agent 调用，与 WorkBuddy Agent 无关联

#### Session ? — 标题生成（1 次调用）

| 属性 | 值 |
|------|----|
| 时间 | 2026-09-28 09:07:05（仅 5.9s） |
| 模型 | glm-5.2 |
| Token | prompt=559 + completion=132 |
| 消息 | 2 条（system + user） |
| 无 conversationRequestId | |

**内容**：system prompt 要求生成会话标题，user 消息包含 Session A 的第一条用户请求。响应返回 `{"isNewTopic": true, "title": "合入指定提交到develop分支"}`。

> 这是一个辅助调用——在 Session A 开始前自动生成的会话标题，属于 WorkBuddy 的会话管理功能。

### 8.4 更高层次关联键分析结论

全量 318 文件分析后，**关联键层次体系更新如下**：

```
Level 0 — 租户/账户层（全局共享，318 文件相同）
  key_name=00925504  team=分布式  IP=118.193.37.170
  └── 无更高层关联键（api_base 仅 2 个值，差异在后缀）
        │
        ├── Session A (195 files) ── convReqId 集合 = {5 个} ── glm-5.2
        │     ├── 第1轮 01a0e744... trace=5de2c718... (msg 1-63)  ← 出现在全部195个文件
        │     ├── 第2轮 01a0e752... trace=cbb5e7b7... (msg 64-172) ← 出现在168个文件
        │     ├── 第3轮 01a0e764... trace=651dc8f2... (msg 173-178)← 出现在114个文件
        │     ├── 第4轮 01a0e76e... trace=14de8afa... (msg 179-253)← 出现在111个文件
        │     └── 第5轮 01a0e776... trace=52356d9c... (msg 254-410)← 出现在79个文件
        │
        ├── Session B (74 files) ── convReqId 集合 = {2 个} ── glm-5.2
        │     ├── 第1轮 01a0e69f... trace=(无)  ← 出现在全部74个文件
        │     └── 第2轮 42c6bfb2... trace=42c6bfb2... (traceId=convReqId)
        │
        ├── Session C (48 files) ── convReqId = {} ── glm-5.3-flash (Hermes Agent)
        │     └── 无 convReqId/traceId，消息不累积，Skill 调用
        │
        └── Session ? (1 file) ── convReqId = {} ── glm-5.2
              └── 标题生成辅助调用
```

**关键发现**：

1. **conversationRequestId 仍然是最高层有效关联键**，但全量分析后发现它区分出 **3 个独立会话**（而非之前认为的 1 个）
2. **新增更高层次的发现**：不同会话通过 `conversationRequestId 集合` 的不同来区分——Session A 有 5 个 convReqId，Session B 有 2 个，Session C 有 0 个
3. **重要修正——单个 convReqId 即可关联整个会话**：由于消息累积机制，每个会话第一轮的 conversationRequestId 出现在该会话的全部文件中。Session A 的 `01a0e744...`（第1轮）覆盖 195/195 文件，在 Session B/C 中为 0。同理 Session B 的 `01a0e69f...` 覆盖 74/74 文件。因此，**第一轮 convReqId 就是该会话的全局唯一关联键**，无需依赖 convReqId 集合
4. **模型差异是会话区分的强信号**：Session C 使用 `glm-5.3-flash`（Hermes Agent），与 A/B 的 `glm-5.2`（WorkBuddy Agent）完全不同
5. **messageId 无跨会话重叠**：Session A 有 194 个 messageId，Session B 有 73 个，两者交集为 **0**——证明它们是完全独立的会话
6. **session_id 始终唯一**（318 个唯一值），每次 LLM 调用都重新生成，**不是持久会话标识符**
7. **Session B 的特殊现象**：第 2 个 conversationRequestId (42c6bfb2) 与其 traceId 相同，可能是系统在追问时复用了 traceId 作为新的 convReqId

---

## 九、分析结论

1. **数据特征**: 318 个详情文件包含 3 个独立会话——Session A（代码合并, 195 次）、Session B（服务重启, 74 次）、Session C（金融新闻 Skill 调用, 48 次）+ 1 个标题生成辅助调用
2. **调用模式**: Session A/B 为 WorkBuddy Agent Loop（glm-5.2，消息累积式）；Session C 为 Hermes Agent Skill 调用（glm-5.3-flash，独立无累积）
3. **Null 字段**: 全量扫描发现 197 个 null path（原 179 + 新增 17），新增主要来自 glm-5.3-flash 的模型映射配置不完整和 litellm 新版本响应字段
4. **XML 内容**: Session A/B 的 system prompt 使用 WorkBuddy XML 标签体系（36 个标签）；Session C 使用独立的 Hermes Agent prompt
5. **关联键层次**: conversationRequestId 是最高层有效关联键（7 个唯一值 → 3 个会话）；其上的 API Key/Team 层全部相同，无法区分；session_id 每次重新生成（318 个唯一值），不是持久会话 ID。**重要修正**：每个会话的第一轮 conversationRequestId 因消息累积机制出现在该会话的全部文件中（Session A 的 `01a0e744...` 覆盖全部 195 个文件，Session B/C 中为 0），因此**单个 convReqId 值即可作为会话级关联键**
6. **会话区分**: Session A（5 个 convReqId，msg 1-411）、Session B（2 个 convReqId，msg 1-154）、Session C（0 个 convReqId，独立调用）通过 convReqId 集合完全区分，messageId 跨会话零重叠
7. **JSON Key 全量统计**: 递归遍历 318 个文件的所有嵌套层级，共发现 325 个唯一 key path（含 `[n]` 数组泛化索引），其中 237 个（73%）出现在全部文件中。`model_map_information.model_map_value` 下有 130 个子字段（占 40%），全部为 null（模型不支持的功能/定价）。出现率与 Session 分布强相关：84.6% 的 key 仅在 Session A+B 出现，52.8% 仅在 Session B+C 部分文件出现，7.2% 来自 glm-5.3-flash 特有响应字段
