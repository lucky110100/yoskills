# DeepAgent A2A input-required 检测任务 — 时间与资源消耗分析报告

## 一、任务概述

目标：让 DeepAgent A2A Server 在 CLI 工具返回 `input-required` 状态时，正确中断任务、保存 CLI `conversation_id`，并在用户提供补充信息后恢复会话继续执行。

## 二、实际耗时与资源消耗

- **调试迭代次数**: 约 6-7 次完整的"修改→编译→重启→测试→分析日志"循环
- **每次循环耗时**: 编译+重启约 60-90 秒，测试约 30-60 秒，日志分析约 5-10 分钟
- **总估算时间**: 约 2-3 小时有效工作时间
- **服务器重启次数**: 5 次以上
- **LLM API 调用成本**: 每次测试触发 2-3 轮 LLM 调用（含 reasoning），每次约数千 token，总计约 30,000-50,000 token

## 三、为什么花费这么多时间？

### 3.1 核心难点：三层嵌套的序列化格式不匹配

这是本次任务最大的时间黑洞。问题看似简单（从 JSON 中提取 `conversation_id`），但实际序列化格式经历了三层嵌套转义：

```
原始 CLI 输出:     {"status": "input-required", "conversation_id": "local_xxx"}
Java toString:     BaseResult(...stdout={"status": "input-required", ...})
Jackson 序列化后:  "stdout={\\\"status\\\": \\\"input-required\\\", ...}"  (引号被双重转义)
```

最初的正则 `\"status\"\\s*:\\s*\"input-required\"` 匹配的是 JSON 格式的 `"status"`，但实际序列化字符串中引号被转义为 `\\"`，导致 `contains("\"status\"")` 返回 false。

**耗时原因**: 每次猜测序列化格式→写正则→编译→重启→测试→查看日志→发现不匹配→再猜。这个过程重复了至少 3 次才最终确认实际格式。

### 3.2 伪阳性检测：历史消息中的 input-required 干扰

第二轮测试（续接请求）返回 `completed`，但 A2A 服务器错误地发送了 `input-required` 事件。原因是会话状态保留了第一轮的 `input-required` 历史，扫描时无法区分"当前需要输入"和"历史曾经需要输入"。

这个问题只在第二轮测试才暴露，且有两种独立场景需要分别修复：
- 缓存 InterruptInfo 被清除后的第三轮请求（缓存保护失效）
- 状态扫描无法区分历史 vs 当前（需要位置比较逻辑）

**耗时原因**: 这个问题在第一轮测试时不存在，必须完成第一轮后才能发现。且需要理解"续接请求"的完整状态生命周期。

### 3.3 SKILL.md 示例中的 local_\d+ 干扰提取

SKILL.md 文档中包含 `local_1783497547741` 作为示例，正则 `local_\d+` 的 `find()` 方法返回第一个匹配（SKILL.md 中的示例），而不是最后一个匹配（实际 CLI 输出）。

**耗时原因**: 提取到错误的 `conversation_id` 后，续接调用使用了 SKILL.md 示例 ID 而非真实 ID，导致 CLI 工具无法正确恢复会话。只有通过仔细比对服务器日志中的实际 CLI 输出和客户端收到的 `cli_conversation_id` 才能发现不一致。

### 3.4 变量重复定义导致编译失败

在修改代码时，新增了 `cachedInterruptInfo` 变量，但该方法内已有同名变量定义（用于恢复客户端传入的 `cli_conversation_id`），导致编译错误。虽然修复很快，但每次编译失败都需要重新走一遍"修改→编译→重启"循环。

**耗时原因**: 约 5-10 分钟的编译重启时间浪费。

### 3.5 流式检测 vs 状态扫描的双重路径

最初设计了两个检测路径：
1. 流式输出中逐块检测 `outputMap` → 发现 LLM 不直接输出工具结果
2. 会话状态后置扫描 → 发现格式不匹配

两个路径都需要独立调试，且流式路径最终无法使用（工具结果不在 outputMap 中），所有检测逻辑都依赖状态扫描。这个发现过程本身也消耗了时间。

## 四、优化建议

### 4.1 预先获取序列化格式（最重要，节省 60% 时间）

**问题**: 最大的时间浪费在于反复猜测序列化格式。

**方案**: 在写任何正则之前，先写一个简单的调试端点或测试方法，直接输出 `session.dumpState()` 的 `MAPPER.writeValueAsString()` 结果，人工确认格式后再写提取逻辑。

**节省**: 约 1-1.5 小时（3 次格式猜测循环 → 1 次确认后直接写正确正则）

### 4.2 分层测试策略

**问题**: 第一轮测试通过后才发现第二轮的问题。

**方案**: 设计端到端测试脚本，一次性运行"第一轮→提取 metadata→第二轮→验证结果"，而非手动逐步测试。

```bash
# 自动化测试脚本示例
python3 bin/cli.py -q '查询余额' -t auto_test -s | tee round1.json
CLI_CONV_ID=$(jq -r '.cli_conversation_id' round1.json)
A2A_CONV_ID=$(jq -r '.conversation_id' round1.json)
python3 bin/cli.py -q '账号123456' -t auto_test -s -c $A2A_CONV_ID -cc $CLI_CONV_ID | tee round2.json
# 验证 round2 没有 input-required 事件
```

**节省**: 约 30-40 分钟（减少手动操作和日志查找时间）

### 4.3 使用 Map 结构遍历而非字符串正则

**问题**: 从序列化字符串中提取信息受 JSON 转义影响，极其脆弱。

**方案**: 优先使用 `scanMapForInputRequired` 的递归 Map 遍历方式，直接在 Java 对象上查找工具输出内容。Map 中的 String 值是原始 Java String（不含 JSON 转义），可以可靠地用 `indexOf("{\"status\"")` 等方式提取。

当前之所以字符串正则生效，是因为 Map 遍历的 `parseCliJsonFromToolOutput` 方法也有格式匹配问题（`{"status"` 在 BaseResult toString 中可能被 Java 对象格式包裹）。应重构此方法，直接在 Map 层面找到 `BaseResult(...)` 或 `ExecuteCmdData` 对象的 `stdout` 字段，而非在 toString 字符串中搜索。

**节省**: 约 30 分钟（避免转义相关的所有问题）

### 4.4 快速编译重启流程

**问题**: 每次 `start.py` 都重新安装 `agent-core-java` 并编译，耗时 60-90 秒。

**方案**: 分离编译和启动步骤。修改后先 `mvn compile -q`（约 5-10 秒），仅验证编译成功后再 `start.py`。或创建 `quick_restart.py` 跳过依赖安装步骤。

**节省**: 每次循环约 50-60 秒 × 5 次 = 约 4-5 分钟

### 4.5 增量调试日志

**问题**: 当前调试日志过于冗长（完整 LLM messages 序列化），难以快速定位关键信息。

**方案**: 添加结构化的调试日志，只输出关键判断点：
- `[detectInputRequired] input-required位置=X, completed位置=Y, 结论=...`
- `[detectInputRequired] last local_\d+ = XXX, 来源=CLI输出/SKILL.md`

而非输出完整的序列化状态字符串。

**节省**: 约 15-20 分钟（减少日志查找时间）

### 4.6 设计时考虑"历史污染"问题

**问题**: 状态扫描无法区分当前 vs 历史的 `input-required`。

**方案**: 在设计阶段就考虑会话状态是累积的（包含所有历史消息）。检测逻辑应基于"最后一个相关事件"而非"是否存在"，从一开始就用 `lastIndexOf` 比较而非 `contains`。

**节省**: 约 30-40 分钟（避免第二轮才发现的伪阳性问题）

## 五、总结

| 问题类别 | 耗时占比 | 可优化节省 |
|----------|----------|------------|
| 序列化格式猜测 | 40% | 60%（预先确认格式） |
| 历史状态伪阳性 | 25% | 80%（设计时考虑累积性） |
| SKILL.md 示例干扰 | 15% | 70%（用 last match 策略） |
| 编译重启循环 | 10% | 50%（快速重启流程） |
| 其他（变量冲突等） | 10% | 30%（更仔细的代码审查） |

**核心教训**: 当需要从嵌套序列化结构中提取信息时，**永远不要凭猜测写正则**。先获取真实数据样本，确认格式后再写提取逻辑。这是本次任务最大的效率瓶颈，也是最容易优化的环节。
