# 编码子代理协作体系

> 交叉引用: [01-project-overview](../../01-project-overview.md) | [02-overall-architecture](../../02-overall-architecture.md) | [04-harness-and-deepagents-module](../../04-harness-and-deepagents-module.md) | [06-agentevolving-and-autoharness-module](../../06-agentevolving-and-autoharness-module.md)

## 一、能力概述

agent-core-java 的编码子代理协作体系围绕"**探索-规划-编码-验证**"四阶段分工展开。code_agent 作为主编码代理,在装配时自动注入 explore_agent 与 plan_agent 两个内置子代理,并通过 TaskTool 在运行时按需委派 verification_agent。每个子代理拥有独立的工厂、系统提示、Rails 与职责边界:explore_agent 只读导航、plan_agent 只读规划、verification_agent 对抗验证、code_agent 落地实现,职责互不交叉,上下文各自隔离。

体系的核心设计有三:其一,**职责边界靠"禁用工具清单 + 只读 Rails"硬约束**,而非靠提示软劝。每个只读子代理的 metadata 都显式列出 forbidden_operations,并由 SecurityRail(true) 在机制层拦截写操作;其二,**子会话独立**,每次委派生成的子代理在独立会话中执行,主代理上下文不被子代理的探索/验证细节污染——explore_agent 的海量搜索结果不会撑爆 code_agent 的上下文窗口;其三,**确定性粘性子会话 ID**,使同类型委派可复用上下文(如验证-修复-再验证能看到上一轮失败点),而不同类型委派各自独立(避免职责串味)。

本能力在 Java 版完整落地,DeepAgentSubagents 与各 Factory 提供了 6 类子代理的构建入口,DeepAgentsFactory 提供门面,DeepAgent.createSubagent 提供按 factory_name 路由的运行时分发。

## 二、关键类与函数

| 类/函数 | 职责 | 源码位置 |
|---------|------|----------|
| CodeAgentFactory | 主编码代理工厂(`code_agent`),自动注入 explore/plan | [CodeAgentFactory.java#L25](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/CodeAgentFactory.java#L25) |
| CODE_AGENT_FACTORY_NAME | 工厂名常量 `"code_agent"` | [CodeAgentFactory.java#L31](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/CodeAgentFactory.java#L31) |
| buildCodeAgentConfig(language) | 单参重载,默认空 kwargs | [CodeAgentFactory.java#L83](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/CodeAgentFactory.java#L83) |
| buildCodeAgentConfig(language, kwargs) | 装配 Rails + 内置子代理 + 编码记忆 Rail | [CodeAgentFactory.java#L121](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/CodeAgentFactory.java#L121) |
| buildCodingMemoryRail | 按 kwargs 构造 CodingMemoryRail | [CodeAgentFactory.java#L127](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/CodeAgentFactory.java#L127) |
| ExploreAgentFactory | 代码库导航子代理(`explore_agent`,只读) | [ExploreAgentFactory.java#L20](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/ExploreAgentFactory.java#L20) |
| buildExploreAgentConfig | 装配只读约束(maxIterations=25) | [ExploreAgentFactory.java#L153](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/ExploreAgentFactory.java#L153) |
| PlanAgentFactory | 纯规划子代理(`plan_agent`,只读) | [PlanAgentFactory.java#L20](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/PlanAgentFactory.java#L20) |
| VerificationAgentFactory | 对抗验证子代理(`verification_agent`) | [VerificationAgentFactory.java#L21](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/VerificationAgentFactory.java#L21) |
| ResearchAgentFactory | 资料检索子代理(`research_agent`) | [ResearchAgentFactory.java](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/ResearchAgentFactory.java) |
| BrowserAgentFactory | 浏览器子代理(`browser_agent`) | [BrowserAgentFactory.java](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/BrowserAgentFactory.java) |
| SubAgentConfig | 子代理配置(toDeepAgentConfig/hasRail/railClassNames) | [SubAgentConfig.java#L31](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/SubAgentConfig.java#L31) |
| DeepAgentSubagents | 6 类子代理构建门面 | [DeepAgentSubagents.java#L27](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/deepagents/subagents/DeepAgentSubagents.java#L27) |
| buildCodeAgentConfig(门面) | 委托 CodeAgentFactory | [DeepAgentSubagents.java#L43](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/deepagents/subagents/DeepAgentSubagents.java#L43) |
| buildVerificationAgentConfig(门面) | 委托 VerificationAgentFactory | [DeepAgentSubagents.java#L87](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/deepagents/subagents/DeepAgentSubagents.java#L87) |
| DeepAgentsFactory | 顶层门面入口 | [DeepAgentsFactory.java#L27](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/deepagents/DeepAgentsFactory.java#L27) |
| DeepAgent.createSubagent | 按 spec.factory_name 分发实例化 | [DeepAgent.java#L1266](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/deep_agent/DeepAgent.java#L1266) |
| TaskTool | 委派工具(delegate) | [TaskTool.java#L19](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/TaskTool.java#L19) |

## 三、实现机制

### 3.1 四阶段子代理与职责边界

体系由四阶段构成,每个阶段对应一个工厂:

1. **探索(Explore)** — [ExploreAgentFactory](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/ExploreAgentFactory.java#L20) 构建 `explore_agent`,定位/读取/汇报现有代码。其 metadata 显式禁用 `write_file / edit_file / mkdir / touch / rm / cp / mv / git add / git commit`,只保留 glob/grep/read_file/list_files/bash(只读 shell);`recommended_tools` 明示推荐工具集,`allowed_shell_intent=read_only`。提示强调"以速度为优先,有针对性地规划搜索步骤,减少不必要的工具调用,凡相互独立的 grep 与读文件操作,尽量并行发起",并要求调用方传入 quick/medium/very thorough 详尽程度提示以校准搜索深度。
2. **规划(Plan)** — [PlanAgentFactory](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/PlanAgentFactory.java#L20) 构建 `plan_agent`,只读模式下设计实现方案并输出 Critical Files(详见 code-planning)。
3. **编码(Code)** — [CodeAgentFactory](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/CodeAgentFactory.java#L25) 构建 `code_agent`,真正落地代码。其 metadata 声明 `requires_ask_user / requires_confirm_interrupt / supports_coding_memory / enable_task_planning`,Rails 装配 SysOperationRail/AgentModeRail/AskUserRail/ConfirmInterruptRail/CodingMemoryRail。提示要求"能用工具就用工具(读/写/编辑/grep/list/bash/code),不要猜文件内容;变更要小、可回滚;先澄清数据结构与接口,再动代码;输出给出测试/验证步骤"。
4. **验证(Verification)** — [VerificationAgentFactory](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/VerificationAgentFactory.java#L21) 构建 `verification_agent`,对抗性验证并以 VERDICT 结尾(详见 code-review)。

此外还有两类辅助子代理:[ResearchAgentFactory](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/ResearchAgentFactory.java)(`research_agent`,资料检索)与 [BrowserAgentFactory](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/BrowserAgentFactory.java)(`browser_agent`,浏览器操作),用于需要外部信息获取的场景。

### 3.2 自动注入内置子代理

[CodeAgentFactory.buildCodeAgentConfig#L121](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/CodeAgentFactory.java#L121) 在装配 code_agent 时,自动把 explore_agent 与 plan_agent 作为 `.subagents(...)` 注入:

```
.subagents(List.of(
    ExploreAgentFactory.buildExploreAgentConfig(isResolved),
    PlanAgentFactory.buildPlanAgentConfig(isResolved)))
```

这意味着 code_agent 一经创建即具备"先探索、再规划、后编码"的内置协作链,无需用户手工拼接。Rails 装配在 [L111-112](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/CodeAgentFactory.java#L111):`SysOperationRail / AgentModeRail / AskUserRail / ConfirmInterruptRail / buildCodingMemoryRail(kwargs)`。其中 [buildCodingMemoryRail](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/CodeAgentFactory.java#L127) 会按 factoryKwargs 中的 `embedding_config / coding_memory_dir / coding_memory_proactive` 构造 CodingMemoryRail:若 `embedding_config` 是 EmbeddingConfig 实例则用带参构造(传入编码记忆目录、嵌入配置、是否主动),否则回退到无参构造(默认 proactive=true)。

### 3.3 配置门面与分发

[DeepAgentSubagents#L27](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/deepagents/subagents/DeepAgentSubagents.java#L27) 是 6 类子代理的构建门面,集中暴露 `buildCodeAgentConfig / buildExploreAgentConfig / buildPlanAgentConfig / buildResearchAgentConfig / buildVerificationAgentConfig / buildBrowserAgentConfig`,内部委托对应 Factory(如 [buildCodeAgentConfig#L43](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/deepagents/subagents/DeepAgentSubagents.java#L43) 直接 `return CodeAgentFactory.buildCodeAgentConfig(language)`),并提供 `create(subagentType, language, workspace)` 路由入口。[DeepAgentsFactory#L27](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/deepagents/DeepAgentsFactory.java#L27) 是更上层的顶层门面。

[SubAgentConfig#L31](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/SubAgentConfig.java#L31) 用 builder 模式聚合 agentCard/systemPrompt/language/maxIterations/factoryName/executionMode/role/metadata/rails/subagents 等字段,提供 `toDeepAgentConfig()`(转 DeepAgent 配置)、`hasRail()`(判断是否含某 Rail)、`railClassNames()`(Rail 类名清单)等查询方法,是子代理配置的统一载体。其内部还定义了 `SubAgentConfigBuilder`([L141](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/SubAgentConfig.java#L141))支持流式构造。

### 3.4 委派与子会话隔离

运行时,主代理通过 TaskTool 委派子代理。[TaskTool.delegate](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/TaskTool.java#L41) 解析 `subagent_type`,调用 [parentAgent.createSubagent(subagentType, subSessionId)](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/deep_agent/DeepAgent.java#L1266)。

[DeepAgent.createSubagent#L1266](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/deep_agent/DeepAgent.java#L1266) 的路由逻辑:

1. `normalized = subagentType.trim().toLowerCase(Locale.ROOT)` 规范化,保证大小写与首尾空格不敏感;
2. `findSubagentSpec(normalized)` 查找 spec — 若已是 DeepAgent 直接复用(单例型,避免重复实例化);
3. 若是 SubAgentConfig 走 `instantiateConfiguredSubagent` 实例化;
4. 不匹配则抛 `IllegalArgumentException("Unsupported subagent type: ...")`,TaskTool 捕获后返回 `status=skipped`(而非整体失败),保证主流程鲁棒。

子会话 ID 由 `buildSubSessionId(parentSessionId, subagentType)` 确定性生成,使**同类型委派复用同一子会话**(粘性会话),而**不同类型委派各自独立**(上下文隔离)。这一设计既让验证-修复-再验证共享上下文(验证代理能看到上一轮自己提出的失败点),又避免 explore 的海量探索细节污染 code_agent 的编码上下文。子会话隔离是控制上下文成本的关键:主代理只接收子代理的最终摘要(如 VERDICT、Critical Files、探索结论),不必承载子代理的全部工具调用轨迹。

### 3.5 委派结果回传与异常处理

[TaskTool.delegate](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/tools/TaskTool.java#L41) 在委派成功后,把子代理 `invoke` 的结果封装为 `ToolOutput`:payload含 `agent_id`(子代理 card id)、`sub_session_id`(确定性子会话 ID)、`result`(子代理 invoke 返回)。这一结构让主代理既能引用子代理身份,又能复用子会话 ID 做后续委派。

异常处理分两级:`IllegalArgumentException`(子代理类型未注册)被捕获后返回 `status=skipped` + 跳过原因,`success` 仍为 true,保证主流程不被未知类型打断;其他 `Exception` 才返回 `success=false` + 错误消息。这种"未知类型降级而非整体失败"的设计,让主代理在面对配置缺失或拼写错误的子代理类型时仍能继续执行,而非直接崩溃,提升了体系的鲁棒性。

## 四、调用示例

```java
import com.openjiuwen.deepagents.subagents.DeepAgentSubagents;
import com.openjiuwen.deepagents.DeepAgentsFactory;
import com.openjiuwen.harness.subagents.SubAgentConfig;
import com.openjiuwen.harness.tools.TaskTool;
import com.openjiuwen.harness.deep_agent.DeepAgent;
import com.openjiuwen.workspace.Workspace;
import java.util.Map;

// 1) 通过门面构建主编码代理(自动注入 explore_agent + plan_agent)
//    rails: [SysOperationRail, AgentModeRail, AskUserRail, ConfirmInterruptRail, CodingMemoryRail]
//    metadata: {requires_ask_user, requires_confirm_interrupt, supports_coding_memory, enable_task_planning}
SubAgentConfig codeSpec = DeepAgentSubagents.buildCodeAgentConfig("cn");
DeepAgent codeAgent = DeepAgentsFactory.createDeepAgent(
        codeSpec.getAgentCard(), codeSpec.toDeepAgentConfig(), workspace);

// 2) 主代理在编码前先委派探索(独立子会话, 不污染主上下文)
TaskTool taskTool = new TaskTool(codeAgent);
taskTool.delegate("explore_agent",
        "very thorough: 找到支付服务的所有入口与幂等相关代码", "code-session-001");

// 3) 委派规划(只读 plan_agent 输出 3-5 个 Critical Files)
taskTool.delegate("plan_agent",
        "基于探索结果设计幂等性实现方案, 给出 3-5 个关键文件", "code-session-001");

// 4) 主代理编码实现(自身具备 ask_user / confirm_interrupt / coding_memory / task_planning)
codeAgent.invoke(Map.of(
        "query", "按 plan_agent 给出的关键文件实现幂等校验",
        "conversation_id", "code-session-001"));

// 5) 编码完成后委派对抗验证(粘性会话复用上下文, 验证代理能看到上一轮失败点)
taskTool.delegate("verification_agent",
        "对抗性验证幂等修复, 输出 VERDICT", "code-session-001");
// 注: explore/plan/verify 各自独立子会话, 互不串味;
//     同类型多次委派复用 subSessionId, 保持上下文连续
```

## 五、业界对比

| 维度 | agent-core-java | Spring AI | LangChain4j | Python agent-core |
|------|-----------------|-----------|-------------|-------------------|
| 子代理种类 | ✅ 6 类(explore/plan/code/verify/research/browser) | ❌ 无内置子代理体系 | ⚠️ 仅 advisor 机制,非子代理 | ✅ 同(对齐源) |
| 职责边界 | ✅ 禁用工具清单 + 只读 Rails 硬约束 | ❌ 无 | ⚠️ 软提示为主 | ✅ 同 |
| 自动注入内置子代理 | ✅ code_agent 自动注入 explore+plan | ❌ | ❌ | ✅ 同 |
| 粘性会话 | ✅ TaskTool 确定性子会话 ID | ❌ | ❌ | ✅ 同 |
| 独立子会话隔离 | ✅ 不同类型各自独立,避免上下文污染 | ❌ | ❌ | ✅ 同 |
| 委派工具 | ✅ TaskTool.delegate | ⚠️ 需自建 | ⚠️ 需自建 | ✅ task_tool |
| 配置门面 | ✅ DeepAgentSubagents + DeepAgentsFactory | ❌ | ❌ | ✅ 同 |
| 未知类型鲁棒降级 | ✅ IllegalArgumentException→skipped | ❌ | ❌ | ✅ 同 |

## 六、小结

agent-core-java 的编码子代理协作体系是**已实现**的四阶段分工框架:探索-规划-编码-验证,由 6 类工厂化的子代理、自动注入机制、确定性粘性子会话 ID 与独立子会话隔离共同支撑。其工程价值在于把"一个全能大模型单打独斗"重构为"多个职责受限的专才协作",既通过职责边界(禁用工具清单 + 只读 Rails)杜绝越权,又通过子会话隔离控制上下文成本——主代理只接收子代理的最终摘要,不必承载子代理的全部工具调用轨迹。

设计哲学上,本体系体现了"专才协作 + 上下文防火墙"原则:每个子代理只做一件事(explore 找代码、plan 设计方案、code 写代码、verify 破代码),职责互不交叉;而子会话隔离就像防火墙,把每个子代理的探索/验证细节挡在自己的会话内,只把"结论"放行给主代理。粘性子会话则在"隔离"与"连续"之间取得平衡——同类型委派复用上下文以保证连续性,不同类型委派各自独立以保证隔离性。

工程层面,本体系还体现了"约定优于配置"的 Java 哲学:code_agent 通过自动注入 explore+plan,把"探索-规划-编码"的最佳实践固化在装配阶段,用户无需手工拼装即可获得完整协作链;而 6 类子代理统一通过 DeepAgentSubagents 门面暴露,降低使用门槛。SubAgentConfig 用 builder 模式聚合配置,既保证不可变性,又支持流式构造与 hasRail/railClassNames 等查询,便于运行时自省。

鲁棒性方面,TaskTool 对 IllegalArgumentException 做降级而非整体失败,使主代理面对配置缺失或类型拼写错误时仍能继续;createSubagent 的"单例复用 + Config 实例化"双路路由兼顾性能与灵活性,避免重复实例化开销。这些都是生产环境长期运行所必需的工程化考量。

可观测性方面,TaskTool 委派结果回传 `agent_id` 与 `sub_session_id`,使主代理既能引用子代理身份,又能复用子会话 ID 做后续委派,便于链路追踪与调试。SubAgentConfig 的 railClassNames 等查询方法则支持运行时自省,便于诊断 Rail 装配是否符合预期。

与 Spring AI / LangChain4j 相比,二者均无内置子代理体系(Spring AI 仅 advisor 机制,LangChain4j 需自建委派),agent-core-java 在此维度与 Python 版实现对齐,具备显著的体系化优势,可直接用于"探索-规划-编码-验证"的端到端编码自动化场景。
