# 代码审查与对抗验证

> 交叉引用: [01-项目概述](../../01-project-overview.md) | [02-整体架构](../../02-overall-architecture.md) | [04-harness模块](../../04-harness-module.md) | [08-依赖关系](../../08-dependencies.md)

## 一、能力概述

agent-core 的代码审查能力并非由主代理"自评",而是由一个独立的对抗性验证子代理(VerificationAgent)承担。其核心设计理念是"职责分离"——实现者负责写代码,验证者负责尝试破坏代码,二者上下文隔离、目标对立,从而避免"自我确认偏误"。

VerificationAgent 被定位为"用户看到结果前的最后一道防线"。它不去做"看起来对不对"的确认,而是主动寻找边界用例、回归风险和未测试的失败路径。系统提示明确要求它"try to BREAK it",而非"confirm it looks correct"。

更关键的是,该子代理带有严格的对抗性约束:禁止创建、修改或删除项目文件,仅允许在 `/tmp` 下放置临时测试脚本;每项检查必须包含真实的"Command run"块并逐字粘贴终端输出;最终回答必须以 `VERDICT: PASS / FAIL / PARTIAL` 结尾。配合粘性子会话机制,验证失败后可以进入"FAIL → 主代理修复 → 重新验证"的闭环,且重新验证时仍保留前一轮的上下文,实现真正的对抗式迭代收敛。

## 二、关键类与函数

| 类/函数 | 文件位置 | 说明 |
| --- | --- | --- |
| create_verification_agent | [verification_agent.py#L318-L363](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/subagents/verification_agent.py#L318) | VerificationAgent 工厂,默认装配 `SysOperationRail + VerificationRail` |
| VERIFICATION_AGENT_SYSTEM_PROMPT_EN | [verification_agent.py#L43-L161](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/subagents/verification_agent.py#L43) | 对抗性系统提示,含约束、按变更类型策略、强制 VERDICT 输出 |
| VerificationRail | [verification_agent.py#L306](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/subagents/verification_agent.py#L306) | 验证专用 Rail,与 `SysOperationRail` 共同构成默认 rails |
| build_verification_agent_config | [verification_agent.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/subagents/verification_agent.py) | 构建可注入主代理的子代理配置,支持 `language="cn"` |
| TaskTool | [task_tool.py#L55-L150](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/subagent/task_tool.py#L55) | 子代理委派工具,解析 `subagent_type + task_description` |
| TaskTool._build_sub_session_id | [task_tool.py#L82-L87](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/subagent/task_tool.py#L82) | 粘性子代理用确定性 ID,便于 FAIL→fix→re-verify 循环复用会话 |
| SubagentRail | [subagent_rail.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/rails/subagent/subagent_rail.py) | priority=95,注册 `task_tool`/`session_spawn` |

## 三、实现机制

### 1. 对抗性约束的硬性化

系统提示 ([verification_agent.py#L48-L55](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/subagents/verification_agent.py#L48)) 将约束固化为不可协商的规则:

- 项目文件零写权限(创建/修改/删除均禁止);
- `/tmp` 仅允许临时测试脚本;
- 末尾必须输出 `VERDICT: PASS / FAIL / PARTIAL`,且"无 markdown 加粗、词后无标点、无格式变体"。

与之配套的两类"反作弊"提醒:L57-L66 指出两种必须抵制的失败模式——"读代码然后编故事直接 PASS"和"看到前 80% 通过就停手"。

### 2. 按变更类型的验证策略

系统提示在 L78-L111 给出八种变更类型对应的差异化验证剧本:

| 变更类型 | 关键检查点 |
| --- | --- |
| Backend / API | 启动服务→curl 调端点→验响应"形状"而非仅状态码→测鉴权边界 |
| CLI / 脚本 | 代表性输入→验 stdout/stderr/exit code→边界与 `--help` |
| Library / 包 | build→测试套件→新上下文 import→导出名与签名对齐文档 |
| Bug 修复 | 先复现原 bug→打补丁→验证不再发生→回归检查副作用 |
| 重构 | 原测试套件不变即过→公共 API 表面完全一致→行为可观察一致 |
| 基础设施/配置 | 语法校验→dry-run→确认环境变量被真实引用 |
| 数据/ML 管道 | 样本输入→输出形状/schema/类型→空输入/单行/null→进出行数一致 |
| 数据库迁移 | up 迁移→schema 对齐意图→down 可逆→用存量数据测试 |

此外 L113-L120 要求在签发 PASS 前至少执行一项"对抗性探测":边界值(0/-1/空串/超长/unicode/MAX_INT)、幂等性、孤儿操作、并发。

系统提示 L129-L160 还规定了每项检查的强制输出结构,缺少 "Command run" 块的检查会被判定为 SKIP 而非 PASS:

```
### Check: [验证内容]
**Command run:**
  [实际执行的命令]
**Output observed:**
  [逐字粘贴终端输出, 不得改写]
**Result: PASS**

# 或失败时:
**Result: FAIL**
Expected: [应发生什么]
Actual: [实际发生了什么]
```

下例是被明令禁止的反模式:仅写"Reviewed the handler. The logic correctly validates input."而无任何命令输出,会被判定为 SKIP。最终 VERDICT 的三态语义如下:

| VERDICT | 语义 |
| --- | --- |
| PASS | 所有检查通过,对抗性探测全部存活 |
| FAIL | 存在失败,需附失败证据、错误输出与复现步骤 |
| PARTIAL | 仅限环境限制(工具不可用、服务无法启动),而非"我不确定" |

### 3. 子代理委派与粘性会话

主代理通过 `TaskTool` 委派验证任务。`TaskTool.invoke` ([task_tool.py#L89-L150](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/subagent/task_tool.py#L89)) 解析 `subagent_type` 与 `task_description`,随后调用 `parent_agent.create_subagent` 创建子代理。

关键的粘性会话逻辑位于 `_build_sub_session_id` ([task_tool.py#L82-L87](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/subagent/task_tool.py#L82)):

```python
if kv_cache_hooks.is_sticky_subagent_type(normalized_type):
    # 确定性 ID,FAIL → fix → re-verify 循环中可复用同一会话
    return f"{parent_session_id}_sub_{normalized_type}"
return f"{parent_session_id}_sub_{normalized_type}_{uuid.uuid4().hex[:8]}"
```

对于验证这类需要"上下文延续"的子代理,使用确定性 ID 可让重试时命中同一会话,从而保留上一轮的发现;而对一次性任务则注入随机后缀,避免上下文污染。

### 4. 验证-修复闭环

时序如下:

```
主代理编码完成
   │ TaskTool(subagent_type="verification_agent", task_description="...")
   ▼
VerificationAgent(粘性子会话) ── 执行对抗性探测 ──┐
   │                                              │
   ├─ VERDICT: PASS ──→ 主代理收尾,回报用户
   │
   └─ VERDICT: FAIL ──→ 主代理收到失败证据 → 修复 → 再次委派(同会话ID)
                                              │
                                              ▼
                                  VerificationAgent 保留前轮上下文,继续验证
```

闭环的核心收益在于"上下文延续":重新验证时无需从零复述前轮发现,验证代理可直接基于上轮的失败点继续深挖,显著提升多轮收敛效率。

## 四、调用示例

```python
from openjiuwen.harness.subagents.code_agent import create_code_agent
from openjiuwen.harness.subagents.verification_agent import build_verification_agent_config
from openjiuwen.harness.runner import Runner

agent = create_code_agent(
    model,
    workspace="./proj",
    enable_task_loop=True,
    subagents=[
        build_verification_agent_config(model, language="cn"),
    ],
)

result = Runner.run_agent(
    agent,
    {"query": "重构 auth 模块,确保 JWT 刷新令牌逻辑正确,并完成对抗验证"},
)
print(result.final_output)
# 预期:主代理先实现重构,再委派 verification_agent 进行对抗测试;
# 若输出 VERDICT: FAIL,主代理根据失败证据修复后重新委派,直到 VERDICT: PASS。

# 程序化解析 VERDICT 以驱动后续编排:
final = getattr(result, "final_output", "") or ""
if "VERDICT: PASS" in final:
    print("验证通过,可交付")
elif "VERDICT: FAIL" in final:
    print("验证失败,需人工介入或继续修复")
else:
    print("PARTIAL,存在环境限制")
```

## 五、业界对比

| 能力维度 | agent-core | Cursor | Claude Code | GitHub Copilot |
| --- | --- | --- | --- | --- |
| 独立验证子代理 | 有,VerificationAgent 与实现者上下文隔离 | 无独立验证 agent,依赖人工 review | 有 agent 子任务但无对抗验证角色 | 无 |
| 对抗性约束(禁改项目文件) | 强制,系统提示固化 | 无此约束 | 无此约束 | 无此约束 |
| VERDICT 强制结构化输出 | 有,PASS/FAIL/PARTIAL | 无 | 无 | 无 |
| 按变更类型策略 | 有,8 种变更类型剧本 | 无 | 部分,依赖模型自觉 | 无 |
| 验证-修复闭环 | 有,粘性会话支撑复用上下文 | 无 | 部分,需人工衔接 | 无 |

## 六、小结

- agent-core 将"代码审查"实现为独立的对抗验证子代理,从架构上消除自评偏误。
- VerificationAgent 被强制约束为零写权限,仅 `/tmp` 可放临时脚本,确保验证不污染实现产物。
- 强制 `VERDICT: PASS/FAIL/PARTIAL` 结构化输出,使验证结果可被主代理程序化解析与驱动闭环。
- 八种变更类型差异化策略 + 强制对抗性探测,覆盖 API、CLI、库、Bug 修复、重构、基础设施、数据管道、数据库迁移。
- 粘性子会话让"FAIL → 修复 → 重新验证"循环天然保留上下文,实现真正的迭代收敛而非每次从零开始。
