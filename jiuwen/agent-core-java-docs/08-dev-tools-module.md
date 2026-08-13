# dev_tools 模块

> 交叉引用: [01-project-overview](01-project-overview.md) | [02-overall-architecture](02-overall-architecture.md) | [06-agentevolving-and-autoharness-module](06-agentevolving-and-autoharness-module.md) | [09-dependencies](09-dependencies.md)

本篇描述 agent-core-java 的 `dev_tools` 模块。该模块面向开发者,提供 Agent 构建、
Prompt 构建、Skill 生成与评估、Tune 调优等开发期工具链,对应 Python 端
`openjiuwen.dev_tools`。其中 Tune 子模块实现了一套"textual gradient"式调优链,
是 dev_tools 的核心。

## 一、模块职责

`dev_tools` 模块按子领域划分职责:

- **agent_builder**:管理会话历史、进度与 DSL 生成,帮助开发者快速搭建 Agent;
- **prompt_builder**:构建 Prompt,支持同步 `build` 与流式 `streamBuild`,并提供
  `MetaTemplateBuilder` 做模板编排;
- **skill_creator**:LLM 驱动的 Skill 自动生成(内置 ReActAgent);
- **skill_evaluator**:LLM 驱动的 Skill 评估(内置评估 subagent);
- **tune**:核心调优链,包含 Case/CaseLoader、Evaluator、Optimizer 四阶
  (Instruction/Example/Joint/Adopt)、Trainer、TextualParameter,以及 Progress/
  History 工具。

## 二、关键类与函数

### 2.1 agent_builder / prompt_builder

| 类/函数 | 文件位置 | 说明 |
| --- | --- | --- |
| AgentBuilder | [AgentBuilder.java#L31](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/agent_builder/AgentBuilder.java#L31) | `buildAgent`,管理会话历史/进度/DSL 生成 |
| BasePromptBuilder | [BasePromptBuilder.java#L18](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/prompt_builder/BasePromptBuilder.java#L18) | `build`/`streamBuild` |
| MetaTemplateBuilder | [MetaTemplateBuilder.java#L30](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/prompt_builder/builder/MetaTemplateBuilder.java#L30) | 模板编排 |

### 2.2 skill_creator / skill_evaluator

| 类/函数 | 文件位置 | 说明 |
| --- | --- | --- |
| SkillCreator | [SkillCreator.java#L44](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/skill_creator/SkillCreator.java#L44) | LLM 驱动 Skill 生成(内置 ReActAgent) |
| SkillEvaluator | [SkillEvaluator.java#L37](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/skill_evaluator/SkillEvaluator.java#L37) | LLM 评估(内置评估 subagent) |

### 2.3 tune 子模块

| 类/函数 | 文件位置 | 说明 |
| --- | --- | --- |
| Case | [Case.java#L18](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/tune/Case.java#L18) | inputs/label/tools/caseId,Builder |
| CaseLoader | [CaseLoader.java#L22](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/tune/dataset/CaseLoader.java#L22) | 数据集加载,产出迭代器 |
| BaseEvaluator | [BaseEvaluator.java#L21](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/tune/evaluator/BaseEvaluator.java#L21) | `evaluate`/`batchEvaluate` |
| BaseOptimizer | [BaseOptimizer.java#L30](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/tune/optimizer/BaseOptimizer.java#L30) | `backward` L139→`doBackward` 抽象;`update` L146→`doUpdate` 抽象;`traceCallback` L168-179 |
| OptimizeHistory | [OptimizeHistory.java#L29](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/tune/optimizer/OptimizeHistory.java#L29) | ConcurrentHashMap 历史记录 |
| InstructionOptimizer | [InstructionOptimizer.java#L27](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/tune/optimizer/InstructionOptimizer.java#L27) | 指令维优化 |
| ExampleOptimizer | [ExampleOptimizer.java#L33](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/tune/optimizer/ExampleOptimizer.java#L33) | 示例维优化 |
| JointOptimizer | [JointOptimizer.java#L28](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/tune/optimizer/JointOptimizer.java#L28) | 指令+示例联合优化 |
| AdoptOptimizer | [AdoptOptimizer.java#L35](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/tune/optimizer/adopt/AdoptOptimizer.java#L35) | ADOPT 自动微分式优化 |
| Trainer | [Trainer.java#L33](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/tune/trainer/Trainer.java#L33) | `fit(cases)` 组合 optimizer+evaluator |
| TextualParameter | [TextualParameter.java#L18](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/dev_tools/tune/optimizer/TextualParameter.java#L18) | LLMCall + textual gradients |

### 2.4 Progress / History 工具

| 类/函数 | 说明 |
| --- | --- |
| ProgressReporter / ProgressRegistry / BuildProgress / ProgressStage / ProgressStatus | 进度上报与注册 |
| HistoryManager / HistoryCache / DialogueMessage | 会话历史管理 |

## 三、核心机制

### 3.1 Tune 调优链

`Trainer`(L33)的 `fit(cases)` 是 dev_tools 的核心入口,调优链如下:

1. **CaseLoader.iterator**:从数据集加载 `Case`(L18,含 inputs/label/tools/caseId);
2. **evaluator.batchEvaluate**(`BaseEvaluator` L21):对全量 Case 批量评估,
   产出每个 Case 的得分与是否"bad";
3. **optimizer.backward**(`BaseOptimizer` L30,L139):
   - 先 `getBadCases` 拿到低分 Case;
   - 转交抽象方法 `doBackward` 生成 textual gradient;
   - 通过 `traceCallback`(L168-179)把梯度记录进 `OptimizeHistory`(L29,
     内部用 ConcurrentHashMap 保证线程安全);
4. **optimizer.update**(L146):转交抽象方法 `doUpdate` 把梯度应用到参数,
   随后 `clearHistory` 清空本轮记录;
5. **earlyStop**:在每轮末判断是否提前终止(如指标收敛或达到最大轮数)。

### 3.2 四阶优化器

`BaseOptimizer`(L30)定义统一的 `backward`/`update` 协议,四个子类覆盖不同可调维度:

- **InstructionOptimizer**(L27):把系统指令作为 `TextualParameter`,用 LLM 生成
  指令的"梯度"并据此改写;
- **ExampleOptimizer**(L33):把 Few-shot 示例作为可调参数,增删/改写示例;
- **JointOptimizer**(L28):指令与示例联合优化,在单轮内同时调整两个维度;
- **AdoptOptimizer**(L35):基于 ADOPT 自动微分式优化,模拟"动量"与"自适应"
  机制,对 textual gradient 做加权与裁剪。

### 3.3 TextualParameter 与 textual gradient

`TextualParameter`(L18)是 tune 的"参数原语":它封装一个 LLMCall 与该参数的
gradients 列表。每个 gradient 是 LLM 产出的自然语言"改进建议",而非数值梯度。
Optimizer 的 `doBackward` 负责生成 gradient,`doUpdate` 负责把 gradient 翻译为
参数新值(LLM 二次调用)。

### 3.4 AgentBuilder DSL 生成

`AgentBuilder`(L31)的 `buildAgent` 负责生成 DSL,流程为:

1. **执行**:驱动内部 ReActAgent 根据用户描述生成 DSL 草稿;
2. **tryParseJsonObject**:尝试把草稿解析为 JSON 对象;
3. **状态分流**:
   - `completed`:解析成功,返回最终 DSL;
   - `processing`:仍在生成,继续流式产出;
   - `response`:解析失败,返回 LLM 的自然语言回复供用户阅读。

进度由 ProgressReporter 上报,会话历史由 HistoryManager 管理。

### 3.5 SkillCreator / SkillEvaluator

两者都"LLM 驱动":

- **SkillCreator**(L44):内置 ReActAgent,根据用户意图自动产出 Skill 定义
  (元数据、入口、描述、示例);
- **SkillEvaluator**(L37):内置评估 subagent,对候选 Skill 在样例集上打分,
  产出可读评估报告。

两者可串联成"生成 → 评估 → 迭代"闭环。

## 四、调用示例

### 4.1 Tune 调链示例

```java
import com.openjiuwen.dev_tools.tune.dataset.CaseLoader;
import com.openjiuwen.dev_tools.tune.trainer.Trainer;
import com.openjiuwen.dev_tools.tune.optimizer.InstructionOptimizer;
import com.openjiuwen.dev_tools.tune.evaluator.BaseEvaluator;

CaseLoader loader = CaseLoader.fromPath(Path.of("./cases.jsonl"));

BaseEvaluator evaluator = BaseEvaluator.builder()
    .llmCall(llmCall)
    .metric("exact_match")
    .build();

InstructionOptimizer optimizer = InstructionOptimizer.builder()
    .llmCall(llmCall)
    .textualParameter(systemPromptParam)
    .build();

Trainer trainer = Trainer.builder()
    .caseLoader(loader)
    .evaluator(evaluator)
    .optimizer(optimizer)
    .maxEpochs(5)
    .earlyStop(true)
    .build();

trainer.fit(loader.all());   // 触发 evaluate→backward→update 循环
```

### 4.2 四阶优化器切换

```java
import com.openjiuwen.dev_tools.tune.optimizer.JointOptimizer;
import com.openjiuwen.dev_tools.tune.optimizer.adopt.AdoptOptimizer;

// 联合优化
JointOptimizer joint = JointOptimizer.builder()
    .llmCall(llmCall)
    .instructionParam(sysPromptParam)
    .exampleParam(exampleParam)
    .build();

// ADOPT 自动微分式
AdoptOptimizer adopt = AdoptOptimizer.builder()
    .llmCall(llmCall)
    .textualParameter(sysPromptParam)
    .beta1(0.9)
    .beta2(0.999)
    .build();
```

### 4.3 AgentBuilder DSL 生成

```java
import com.openjiuwen.dev_tools.agent_builder.AgentBuilder;

AgentBuilder builder = AgentBuilder.builder()
    .llm(llm)
    .historyManager(new HistoryManager())
    .progressReporter(ProgressRegistry.get("default"))
    .build();

AgentBuilder.BuildResult result = builder.buildAgent("一个能查天气并提醒带伞的助手");
switch (result.status()) {
    case COMPLETED:      // result.dsl() 已是合法 JSON
    case PROCESSING:     // 继续读取流式片段
    case RESPONSE:       // result.text() 为 LLM 自然语言回复
}
```

### 4.4 SkillCreator + SkillEvaluator 闭环

```java
import com.openjiuwen.dev_tools.skill_creator.SkillCreator;
import com.openjiuwen.dev_tools.skill_evaluator.SkillEvaluator;

SkillCreator creator = SkillCreator.builder()
    .llm(llm)
    .reactAgentTemplate(template)
    .build();

Skill skill = creator.create("总结会议要点并下发任务");

SkillEvaluator evaluator = SkillEvaluator.builder()
    .llm(llm)
    .cases(evalCases)
    .build();

SkillEvalReport report = evaluator.evaluate(skill);   // 产出可读评估报告
```

## 五、与 Python agent-core 对照

| Java (agent-core-java) | Python (agent-core) | 对照说明 |
| --- | --- | --- |
| dev_tools 模块 | openjiuwen.dev_tools | 模块对等 |
| AgentBuilder | agent_builder | Agent 构建对等 |
| BasePromptBuilder/MetaTemplateBuilder | prompt_builder | Prompt 构建对等 |
| SkillCreator | skill_creator | Skill 生成对等 |
| SkillEvaluator | skill_evaluator | Skill 评估对等 |
| tune 子模块 | dev_tools.tune | 调优链对等 |
| Case | Case | inputs/label/tools/caseId 对等 |
| CaseLoader | CaseLoader | 数据集加载对等 |
| BaseEvaluator | Evaluator | evaluate/batchEvaluate 对等 |
| BaseOptimizer | Optimizer | backward→doBackward/update→doUpdate 对等 |
| InstructionOptimizer/ExampleOptimizer/JointOptimizer/AdoptOptimizer | 四阶优化器 | Instruction/Example/Joint/Adopt 对等 |
| Trainer.fit | Trainer.fit | 调优链对等 |
| TextualParameter | TextualParameter | LLMCall + textual gradients 对等 |
| OptimizeHistory | OptimizeHistory | 历史记录对等 |
| ProgressReporter/HistoryManager | Progress/History 工具 | 进度与历史对等 |

## 六、小结

`dev_tools` 模块把"Agent 开发期"的常见动作工具化:agent_builder 负责 DSL 生成,
prompt_builder 负责 Prompt 编排,skill_creator/skill_evaluator 负责 Skill 的生成
与评估闭环,tune 则提供"textual gradient"式调优链。其中 tune 的设计最有特色:它
用自然语言梯度替代数值梯度,用 LLM 二次调用实现"反向传播→更新",并把四阶优化器
(Instruction/Example/Joint/Adopt)统一在 `BaseOptimizer` 协议之下。整体上,
dev_tools 让开发者无需手写大量样板,即可完成"搭建 → 评估 → 调优"的完整循环。
