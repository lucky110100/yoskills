# 代码审查与对抗验证

> 交叉引用: [01-project-overview](../../01-project-overview.md) | [02-overall-architecture](../../02-overall-architecture.md) | [04-harness-and-deepagents-module](../../04-harness-and-deepagents-module.md) | [06-agentevolving-and-autoharness-module](../../06-agentevolving-and-autoharness-module.md)

## 一、能力概述

agent-core-java 的代码审查能力由一个独立的**对抗性验证子代理(verification_agent)**承担。它不是"看一眼代码就放行"的确认器,而是一个"努力去把实现弄坏"的最后一道防线:在主编码代理(如 code_agent)完成实现工作后,由父代理通过 TaskTool 委派一个 verification_agent 子会话,在独立、受限的上下文中运行构建、测试套件、lint 与类型检查,并主动发起边界值、幂等性、孤立资源、并发等对抗性探测,最终以 `VERDICT: PASS / FAIL / PARTIAL` 的结构化判决结尾。

这套能力在 Java 版完整落地,与 Python 版 agent-core 的 verification_agent 设计(L43-L161 提示、L306 双 Rail 装配)逐条对齐。其核心特征有三:

1. **独立子代理隔离**:验证在独立子会话中执行,上下文不被主编码代理"自我背书"污染。主代理既写代码又验代码,容易陷入"自我背书"——即倾向于相信自己写的没问题;独立子代理从结构上切断这一路径。
2. **对抗性约束(只读)**:验证代理不能创建/修改/删除项目文件,仅 `/tmp` 可写临时测试脚本,从机制上杜绝"边验证边改代码作弊"。约束不靠提示软劝,而靠 SysOperationRail + 提示硬约束双层强制。
3. **结构化判决 + 修复闭环**:强制 `VERDICT:` 结尾使主代理可解析结果;FAIL 时主代理修复后重新委派 verify,形成"验证→修复→再验证"闭环,且子会话 ID 确定性复用(粘性会话)以保持上下文。

值得强调的是,验证代理明确抵制两种失败模式:其一**验证规避**(verification avoidance)——读代码、描述"本应测试什么",然后不跑任何东西就写 PASS,提示明确"阅读代码不等于验证";其二**被前 80% 迷惑**(seduced by the first 80%)——看到测试通过或输出整洁就停下,而不深入探测边界情况。这两种失败模式都被写进 [VERIFICATION_AGENT_SYSTEM_PROMPT_EN](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/VerificationAgentFactory.java#L27),作为验证代理必须抵制的反模式。

## 二、关键类与函数

| 类/函数 | 职责 | 源码位置 |
|---------|------|----------|
| VerificationAgentFactory | 工厂名 `verification_agent`,构建验证代理 SubAgentConfig | [VerificationAgentFactory.java#L21](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/VerificationAgentFactory.java#L21) |
| buildVerificationAgentConfig(language) | 单参重载,默认空 kwargs | [VerificationAgentFactory.java#L174](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/VerificationAgentFactory.java#L174) |
| buildVerificationAgentConfig(language, kwargs) | 装配提示/约束/Rails/metadata(maxIterations=40, ephemeral) | [VerificationAgentFactory.java#L186](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/VerificationAgentFactory.java#L186) |
| VERIFICATION_AGENT_SYSTEM_PROMPT_EN | 对抗验证英文提示(VERDICT 约束 + 基准步骤 + 对抗探测) | [VerificationAgentFactory.java#L27](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/VerificationAgentFactory.java#L27) |
| VERIFICATION_AGENT_SYSTEM_PROMPT_CN | 对抗验证中文提示(逐条对齐 EN) | [VerificationAgentFactory.java#L89](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/VerificationAgentFactory.java#L89) |
| SysOperationRail | 系统操作约束 Rail(只读/写禁用) | [VerificationAgentFactory.java#L200](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/VerificationAgentFactory.java#L200) |
| VerificationRail | 验证专用 Rail(判决解析/约束) | [VerificationAgentFactory.java#L200](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/VerificationAgentFactory.java#L200) |
| createVerificationAgent | 便捷方法,直接产出 DeepAgent | [VerificationAgentFactory.java#L215](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/VerificationAgentFactory.java#L215) |
| TaskTool | 委派工具,delegate(subagentType, taskDescription, parentSessionId) | [TaskTool.java#L19](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/TaskTool.java#L19) |
| delegate | 构建确定性子会话 ID 并调用父代理 createSubagent | [TaskTool.java#L41](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/TaskTool.java#L41) |
| buildSubSessionId | 由 (父会话, 子代理类型) 确定性派生子会话 ID | [TaskTool.java#L42](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/TaskTool.java#L42) |
| DeepAgent.createSubagent | 按 spec.factory_name 路由分发子代理 | [DeepAgent.java#L1266](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/deep_agent/DeepAgent.java#L1266) |
| findSubagentSpec | 按 normalized 类型查找已注册 spec | [DeepAgent.java#L1268](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/deep_agent/DeepAgent.java#L1268) |
| SubagentRail | 注册 task_tool / session_spawn,提供委派能力 | harness/rails |

## 三、实现机制

### 3.1 对抗性验证约束(metadata + Rails 双层)

[VerificationAgentFactory.buildVerificationAgentConfig#L186](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/VerificationAgentFactory.java#L186) 在 metadata 中显式声明只读语义:`readonly=true`、`requires_verdict=true`、`verdicts=["PASS","FAIL","PARTIAL"]`,并把 `executionMode` 设为 `ephemeral`(短命会话,不长期驻留)、`role` 设为 `verification`、`maxIterations` 默认 40(高于 plan_agent 的 25,给验证留足探测预算)。`restrictToWorkDir=false` 允许验证代理在工作目录之外(如 /tmp)运行临时脚本。

Rails 装配在 [L200](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/VerificationAgentFactory.java#L200),通过 `SubAgentRailMergeSupport.mergeRails` 合并:

- `SysOperationRail()` — 限制系统级写操作,杜绝修改项目文件;
- `VerificationRail()` — 验证专用约束与判决解析(对照 Python 版 L306 的 `SysOperationRail() + VerificationRail()` 组合)。

`SubAgentRailMergeSupport.mergeRails` 还支持通过 kwargs 注入用户自定义 Rail,实现"内置 Rail + 用户扩展"的合并语义,`applyCommonOverrides` 随后应用通用覆盖项(如自定义 maxIterations、提示覆盖)。

### 3.2 系统提示的硬约束

[VERIFICATION_AGENT_SYSTEM_PROMPT_EN#L27](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/VerificationAgentFactory.java#L27)(中文版 [L89](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/VerificationAgentFactory.java#L89) 逐条对齐)把约束写进提示文本,分四个区块:

1. **CRITICAL CONSTRAINTS**:你不能创建/修改/删除项目文件;`/tmp` 可用于临时测试脚本;每项检查必须有"Command run"块并逐字粘贴终端输出,**阅读代码不等于验证**;最终回复必须以 `VERDICT: PASS/FAIL/PARTIAL` 结尾,**不得加粗、不得加标点、不得变体**。
2. **TWO FAILURE MODES TO RESIST**:验证规避、被前 80% 迷惑两种反模式。
3. **REQUIRED BASELINE (no exceptions)**:5 步基准——读 AGENTS.md/README/pyproject.toml/Makefile→运行构建→运行测试套件→运行 lint 与类型检查→检查变更文件相关代码路径回归。**构建失败或测试失败即自动 FAIL**。
4. **REQUIRED ADVERSARIAL PROBES**:PASS 前至少执行其一——边界值(0/-1/空串/超长串/Unicode/MAX_INT)、幂等性(同一变更操作执行两次)、孤立操作(引用/删除不存在的 ID 或资源)、并发(对"不存在则创建"路径并发调用)。

提示还规定 **MANDATORY OUTPUT FORMAT**:每项检查必须用 `### Check: [...]` + `**Command run:**` + `**Output observed:**` + `**Result: PASS/FAIL**` 的固定结构,使验证输出可被程序解析。

### 3.3 委派与子会话隔离

主代理通过 TaskTool 触发验证。[TaskTool.delegate#L41](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/TaskTool.java#L41) 的执行链路:

1. 调用 `buildSubSessionId(parentSessionId, subagentType)`(L42)构造**确定性子会话 ID** — 同一 (父会话, 子代理类型) 组合复用同一子会话,实现"粘性会话"(sticky session),使验证-修复-再验证能保持上下文;
2. 调用 [parentAgent.createSubagent(subagentType, subSessionId)](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/deep_agent/DeepAgent.java#L1266);
3. 用子会话 ID 调用子代理 `invoke(Map.of("query", taskDescription, "conversation_id", subSessionId))`;
4. 返回 `ToolOutput`,payload 含 `agent_id`、`sub_session_id`、`result`。

[DeepAgent.createSubagent#L1266](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/deep_agent/DeepAgent.java#L1266) 的路由逻辑分为三支:

- `normalized = subagentType.trim().toLowerCase(Locale.ROOT)` 规范化;
- `findSubagentSpec(normalized)` 查找 spec — 若已是 DeepAgent(单例型子代理)直接复用,避免重复实例化;
- 若是 SubAgentConfig 走 `instantiateConfiguredSubagent` 实例化;
- 不匹配抛 `IllegalArgumentException("Unsupported subagent type: ...")`。

TaskTool 对异常做了**鲁棒降级**:捕获 `IllegalArgumentException` 时返回 `status=skipped`(success=true 但 result 标记跳过原因),而非整体失败,保证主流程不被未知子代理类型打断;捕获其他 `Exception` 才返回 `success=false`。SubagentRail 负责注册 `task_tool` 与 `session_spawn`,使父代理具备委派能力。

### 3.4 验证-修复闭环

主代理解析子代理最终回复中的 `VERDICT:` 行,三种判决对应三种处理:

- **PASS** — 所有检查通过、对抗性探测均存活,接受实现,结束任务;
- **FAIL** — 主代理按"失败内容 + 确切错误输出 + 复现步骤"修复代码,然后**重新委派 verify**;由于子会话 ID 确定性复用,验证子代理能看到上一轮自己提出的失败点,避免重复探测,也避免"修复 A 又引入 B"的回归;
- **PARTIAL** — 仅限环境限制(工具不可用、服务无法启动),主代理据此决定是否跳过、换环境重验或降级为人工确认。

闭环的可靠性来自两层:结构化 `VERDICT` 让解析无歧义(提示禁止任何变体,如加粗、加标点);粘性子会话让"修复-再验证"共享上下文而不污染主代理上下文——主代理只看到 `VERDICT` 与失败摘要,不必承载验证子代理的全部探测细节,从而控制主上下文成本。

## 四、调用示例

```java
import com.openjiuwen.harness.subagents.VerificationAgentFactory;
import com.openjiuwen.harness.subagents.CodeAgentFactory;
import com.openjiuwen.harness.subagents.SubAgentConfig;
import com.openjiuwen.harness.tools.TaskTool;
import com.openjiuwen.harness.tools.ToolOutput;
import com.openjiuwen.harness.deep_agent.DeepAgent;
import com.openjiuwen.harness.factory.HarnessFactory;
import com.openjiuwen.workspace.Workspace;
import java.util.Map;

// 1) 构建验证子代理配置(只读 + VERDICT 约束 + 双 Rail)
//    metadata: {readonly=true, requires_verdict=true, verdicts=[PASS,FAIL,PARTIAL]}
//    rails:    [SysOperationRail, VerificationRail]
//    executionMode=ephemeral, role=verification, maxIterations=40
SubAgentConfig verifySpec = VerificationAgentFactory.buildVerificationAgentConfig("cn");

// 2) 把 verifySpec 注册到主代理(此处用 code_agent 作为父代理示例)
SubAgentConfig parentSpec = CodeAgentFactory.buildCodeAgentConfig("cn");
DeepAgent parent = HarnessFactory.createDeepAgent(parentSpec.getAgentCard(),
        parentSpec.toDeepAgentConfig(), workspace);

// 3) 主代理完成实现后,通过 TaskTool 委派对抗验证
TaskTool taskTool = new TaskTool(parent);
String parentSessionId = "session-001";
ToolOutput out = taskTool.delegate("verification_agent",
        "对刚完成的支付幂等修复进行对抗性验证:运行构建、测试套件、ruff/mypy,"
        + "并对重复支付、不存在的 order_id、并发创建发起对抗探测。",
        parentSessionId);

// 4) 解析 VERDICT,驱动验证-修复闭环
Map<String, Object> data = out.getData();
String subSessionId = (String) data.get("sub_session_id");          // 确定性复用
Map<String, Object> result = (Map<String, Object>) data.get("result");
String finalReply = String.valueOf(result.get("final_reply"));
if (finalReply.contains("VERDICT: FAIL")) {
    // 主代理进入修复分支,然后再次 delegate("verification_agent", ...)
    // 同一 (parentSessionId, "verification_agent") 会复用 subSessionId, 保持上下文
    parent.invoke(Map.of("query", "修复验证指出的问题:" + finalReply,
            "conversation_id", parentSessionId));
    // 修复后重新 verify, 复用同一子会话, 验证代理能看到上一轮失败点
    taskTool.delegate("verification_agent", "重新验证修复后的实现", parentSessionId);
} else if (finalReply.contains("VERDICT: PARTIAL")) {
    // 环境限制, 主代理决定换环境或降级为人工确认
}
```

## 五、业界对比

| 维度 | agent-core-java | Spring AI | LangChain4j | Python agent-core |
|------|-----------------|-----------|-------------|-------------------|
| 独立验证子代理 | ✅ verification_agent 工厂化、独立子会话 | ❌ 无内置验证子代理,需用户自建 | ❌ 无内置 | ✅ verification_agent(对齐源) |
| 对抗性约束(只读+ /tmp 临时) | ✅ SysOperationRail + VerificationRail + 提示硬约束 | ❌ 无 | ❌ 无 | ✅ 同 |
| VERDICT 结构化判决 | ✅ 强制 PASS/FAIL/PARTIAL,禁止变体 | ❌ 无 | ❌ 无 | ✅ 同 |
| 验证-修复闭环 | ✅ FAIL→主代理修复→重新 verify | ❌ 无内置闭环 | ❌ 无内置闭环 | ✅ 同 |
| 粘性会话(上下文连续) | ✅ TaskTool 确定性子会话 ID | ❌ | ❌ | ✅ 同 |
| 对抗性探测清单 | ✅ 边界值/幂等/孤立/并发 | ❌ | ❌ | ✅ 同 |
| 强制输出格式 | ✅ Check/Command run/Output observed/Result | ❌ | ❌ | ✅ 同 |
| 未知类型鲁棒降级 | ✅ IllegalArgumentException→skipped | ❌ | ❌ | ✅ 同 |

## 六、小结

agent-core-java 的代码审查能力是一个**已实现、可工程化落地**的对抗验证体系:它把"验证"从一个软性的人类习惯,变成由独立子代理 + 只读约束 + 结构化判决 + 粘性会话四件套构成的硬性闭环。其价值不在于"多跑一次测试",而在于用**上下文隔离**杜绝主代理的自我背书、用**只读约束**杜绝"边验证边改"的作弊路径、用**结构化 VERDICT** 让闭环可被程序解析与驱动、用**粘性子会话**让修复-再验证共享上下文而不污染主代理。

提示层面,它显式抵制"验证规避"与"被前 80% 迷惑"两种反模式,把"阅读代码不等于验证"写进硬约束,并要求每项检查都有 Command run 块与逐字终端输出,从结构上压制模型"偷懒写 PASS"的倾向。工程层面,TaskTool 对未知子代理类型做 `skipped` 降级而非整体失败,保证主流程鲁棒;createSubagent 的单例复用 + Config 实例化双路路由兼顾性能与灵活性。

与 Spring AI / LangChain4j 相比,二者目前均不内置此类对抗验证子代理,需要用户自行搭建;agent-core-java 在此维度与 Python 版实现对齐,具备明显的工程化优势,可直接用于"编码-验证-修复"的自动化闭环场景。
