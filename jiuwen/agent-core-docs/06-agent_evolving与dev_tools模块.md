# 06 - agent_evolving 与 dev_tools 模块

这两个模块提供智能体的**自演进/优化**与**开发者调优**能力。`agent_evolving` 是自演进框架，`dev_tools/tune` 是较早期的提示词调优工具，两者在 case 形态上略有差异。

---

## 6.1 `openjiuwen/agent_evolving/` — 智能体自演进框架

### 模块职责

提供训练循环、评估器、优化器、轨迹抽取、检查点、信号检测与 RL 训练原语，允许智能体从执行轨迹与评估结果中迭代优化其技能、指令与经验。

### 关键类

| 类 | 文件（相对 `openjiuwen/agent_evolving/`） | 职责 |
|----|------|------|
| `BaseEvolutionTool` | [tools/base.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_evolving/tools/base.py) | 智能体面向的演进工具基类，桥接演进操作到 `Tool`/`ToolOutput` harness 契约 |
| `TuneConstant` | [constant.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_evolving/constant.py) | frozen dataclass，超参默认值与校验边界（迭代数/并行/示例数/早停分数） |
| `UpdateValue` | [types.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_evolving/types.py) | frozen dataclass，结构化更新契约（payload + mode + effect + change_type + metadata） |
| `ApplyResult` | [types.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_evolving/types.py) | 应用一次归一化更新到一个演进目标的结果；`ok` 属性 |
| `TuneUtils` | [utils.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_evolving/utils.py) | 静态工具集合：参数校验、case/消息/模板序列化、从 LLM 输出解析 JSON/list |
| `SkillReferenceScore` | [utils.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_evolving/utils.py) | 优先级感知的技能引用打分容器；`ranking_key()` 用于确定性最大选择 |
| `Trajectory` / `LegacyTrajectory` / `TrajectoryStep` / `LLMCallDetail` / `ToolCallDetail` | [trajectory/types.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_evolving/trajectory/types.py) | OTLP 优先的轨迹数据模型 + 步式遗留投影 |

### 关键函数

| 函数 | 文件 | 职责 |
|------|------|------|
| `normalize_update_value(value, *, target)` / `normalize_updates(updates)` | [types.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_evolving/types.py) | 将遗留更新载荷包装为结构化 `UpdateValue` 契约 |
| `infer_skill_from_texts(skill_names, *, skill_tool_payloads, texts)` | [utils.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_evolving/utils.py) | 用优先级排序启发式从有序轨迹源推断最可能引用的技能 |
| `parse_top_level_frontmatter(content)` | [utils.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_evolving/utils.py) | 仅解析 Markdown YAML 顶层标量字段 |
| `trajectory_steps` / `trajectory_resource_attributes` / `trajectory_execution_id` / `trajectory_source` / `trajectory_case_id` / `trajectory_session_id` / `trajectory_cost` / `trajectory_meta` / `to_legacy_trajectory` / `trajectory_from_steps` / `trajectory_from_legacy` / `set_trajectory_resource_attributes` | [trajectory/types.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_evolving/trajectory/types.py) | 轨迹访问器 |

### 子包（[agent_evolving/__init__.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_evolving/__init__.py) 重导出）

`checkpointing`、`dataset`（`Case`/`EvaluatedCase`）、`evaluator`、`optimizer`、`trainer`、`trajectory`、`updater`、`agent_rl`、`signal`

### 内部依赖
`core.foundation.tool`（`Tool`、`ToolInfo`）、`harness.tools.base_tool`（`ToolOutput`）、`core.foundation.llm`（`AssistantMessage`、`BaseMessage`）、`core.foundation.prompt`（`PromptTemplate`）、`core.common.exception`（`StatusCode`、`build_error`）、`core.common.logging`

### 设计模式
- **自演进契约经 frozen dataclass + literal 协议**：[protocols.py](file:///D:/jiuwen/main/agent-core/openjiuwen/agent_evolving/protocols.py) 集中 `Final[Literal[...]]` 动作/mode/effect/signal 词汇
- **工具适配器基**：`BaseEvolutionTool` 适配演进操作到 harness `Tool`/`ToolOutput` 流式契约
- **OTLP 优先轨迹 + 遗留投影**：`Trajectory` 存耐用 OTLP 载荷，遗留步视图为派生投影
- **优先级排序多源推断**：`infer_skill_from_texts` 排序竞争信号源
- **公共 API 分段**：`_CONSTANTS`/`_CHECKPOINTING`/`_DATASET`/... 分组导出

---

## 6.2 `openjiuwen/dev_tools/` — 开发者调优工具

### 模块职责

开发者提示词/智能体调优工具。`tune/` 子包提供 case 模型、case 加载器、优化器（instruction/example/joint/ADOPT）、评估器、训练器与 chat 智能体入口。

### 关键类

| 类 | 文件（相对 `openjiuwen/dev_tools/`） | 职责 |
|----|------|------|
| `TuneConstant` | [tune/base.py](file:///D:/jiuwen/main/agent-core/openjiuwen/dev_tools/tune/base.py) | 提示词调优常量（迭代/并行/示例默认值与阈值） |
| `Case` | [tune/base.py](file:///D:/jiuwen/main/agent-core/openjiuwen/dev_tools/tune/base.py) | pydantic 调优 case 模型：`inputs`（非空 dict）、`label`、可选 `tools`、UUID `case_id` |
| `EvaluatedCase` | [tune/base.py](file:///D:/jiuwen/main/agent-core/openjiuwen/dev_tools/tune/base.py) | 包装 `Case` + 评估 `answer`/`score`(0.0-1.0)/`reason` |
| `TuneUtils` | [tune/utils.py](file:///D:/jiuwen/main/agent-core/openjiuwen/dev_tools/tune/utils.py) | 静态工具：参数校验、消息/模板序列化、从 LLM 响应提取 fenced JSON/list |

### 公共 API（[tune/__init__.py](file:///D:/jiuwen/main/agent-core/openjiuwen/dev_tools/tune/__init__.py) 重导出）

`Case`、`EvaluatedCase`、`CaseLoader`、`InstructionOptimizer`、`ExampleOptimizer`、`JointOptimizer`、`DefaultEvaluator`、`Trainer`、`ChatAgent`、`ChatAgentConfig`、`create_chat_agent_config`、`create_chat_agent`

引用的内部子模块：`dataset.case_loader`、`optimizer.instruction_optimizer`/`example_optimizer`/`joint_optimizer`、`chat_agent.chat_agent`、`evaluator.evaluator`、`trainer.trainer`

### 内部依赖
`core.foundation.tool`（`ToolInfo`）、`core.common.logging`（`agent_logger`、`LogEventType`）、`core.common.exception`（`StatusCode`、`build_error`）、`core.foundation.prompt`（`PromptTemplate`）、`core.foundation.llm`（`BaseMessage`、`AssistantMessage`）

### 设计模式
- **pydantic case 模型 + 字段校验**：`Case`/`EvaluatedCase` 强制非空 `inputs`/`label`，`score` 约束 `[0.0, 1.0]`
- **静态工具类**：`TuneUtils` 分组无状态助手
- **包门面**：[tune/__init__.py](file:///D:/jiuwen/main/agent-core/openjiuwen/dev_tools/tune/__init__.py) 单一公共面，隐藏内部子包布局

---

## 6.3 两套 TuneUtils/TuneConstant 对比

| 维度 | `agent_evolving` | `dev_tools/tune` |
|------|------------------|------------------|
| case 形态 | `case.inputs` dict | `case.messages`/`variables` |
| 定位 | 自演进面（较新） | 调优面（较早期/并行） |
| Case 模型 | `agent_evolving.dataset.Case`/`EvaluatedCase`（pydantic） | `dev_tools.tune.base.Case`/`EvaluatedCase`（pydantic） |

> RSI 模块则使用泛型 `CaseMapping = dict[str, Any]` 别名，将 case 视为松散映射。

## 6.4 symphony 模块简介

`openjiuwen/symphony/`（[symphony/README.md](file:///D:/jiuwen/main/agent-core/openjiuwen/symphony/README.md)）是智能体**能力资产发现、检索、编排、经验沉淀与评估**模块。围绕标准化的**能力指纹**（语义画像 + I/O 语义 + 标签）组织，由检索与编排共享。

核心能力：
- **能力指纹**：从能力资产提取并归一化语义画像、I/O、标签
- **能力检索**：树结构索引，渐进式分支探索候选能力
- **能力编排**：能力上的关系图；从候选能力与任务目标生成可解释执行路径
- **经验沉淀**：从会话轨迹抽取可复用能力使用模式到可搜索经验库（`ExperienceBank`、`ExperienceBaseBuilder`、`ExperienceRetriever`、`TraceEvaluator`、`TraceRecord`）
- **能力评估**：评估智能体能力、技能质量与组合有效性

架构原则："**检索用树，编排用图**"，共享指纹为公共语义视图。集成经调用方提供的 Adapters（`CapabilityInventoryProvider`、`LLMConfigProvider`、`ArtifactPathProvider`）；Symphony 保持调用方无关。顶层入口为 `SymphonyRuntime`，组合 `retrieval`/`orchestration`/`experience`/`evaluation` 子服务并暴露 `agent_toolkit(...)`。

## 6.5 auto_harness 兼容重导出

`openjiuwen/auto_harness/__init__.py`（[auto_harness/__init__.py](file:///D:/jiuwen/main/agent-core/openjiuwen/auto_harness/__init__.py)）是薄兼容垫片，从 `openjiuwen.rsi.auto_harness` 重导出 `AutoHarnessConfig`、`AutoHarnessOrchestrator` 等，以在 AutoHarness 迁入 RSI 后保留 `openjiuwen.auto_harness.*` 导入路径。
