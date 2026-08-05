# 07 - extensions 与 rsi 模块

`extensions/` 提供可选集成（如 A2A 协议），`rsi/` 提供评估与自动协调优化框架（含 auto_harness）。

---

## 7.1 `openjiuwen/extensions/` — 可选集成（A2A）

### 模块职责

可选集成模块。`a2a/` 子包包装 A2A（Agent-to-Agent）协议 SDK，提供最小客户端与服务器，将 A2A `AgentCard`/`SendMessage`/流式响应桥接到 openjiuwen `AgentResult` 模型，并向 runner 注册 A2A 远程客户端与服务器适配器插件。

### 关键类

| 类 | 文件（相对 `openjiuwen/extensions/`） | 职责 |
|----|------|------|
| `A2AClient` | [a2a/a2a_client.py](file:///D:/jiuwen/main/agent-core/openjiuwen/extensions/a2a/a2a_client.py) | 最小 A2A SDK 客户端包装；`invoke`/`stream`/`cancel_task`/`stop` |
| `A2AServer` | [a2a/a2a_server.py](file:///D:/jiuwen/main/agent-core/openjiuwen/extensions/a2a/a2a_server.py) | 最小 A2A 服务器包装；构建 FastAPI 应用暴露 agent-card/JSON-RPC/REST 路由，Uvicorn 运行 |

### 关键方法

`A2AClient`：
- `invoke(inputs)`：聚合完整 invoke 流为单个 `AgentResult`
- `stream(inputs)`：async 生成器产出增量 `AgentResult`
- `cancel_task(task_id, tenant=None)` / `stop()` / `__aenter__`/`__aexit__`

`A2AServer`：
- `start(*, host, port, log_level)`：启动 Uvicorn
- `stop()`：信号服务器退出
- `build_app()`：构造/返回挂载路由的 FastAPI 应用

### 关键函数
- `_normalize_jsonrpc_route_path(rpc_url)` — [a2a/a2a_server.py](file:///D:/jiuwen/main/agent-core/openjiuwen/extensions/a2a/a2a_server.py)：确保 JSON-RPC 挂载路径以斜杠结尾，避免破坏流式客户端的 307 重定向
- `create_a2a_remote_client(**kwargs)` / `create_a2a_server_adapter(**kwargs)` — [a2a/__init__.py](file:///D:/jiuwen/main/agent-core/openjiuwen/extensions/a2a/__init__.py)：懒导入构造 `A2ARemoteClient`/`A2AServerAdapter`，以 `"A2A"` 名注册

### 内部依赖
`core.controller.schema.task`（`TaskStatus`）、`core.single_agent.schema.agent_result`（`AgentResult`）、`core.single_agent.schema.agent_card`（`AgentCard`）、`extensions.a2a.a2a_transformer`（`A2ATransformer`）、`extensions.a2a.a2a_agent_executor`/`a2a_agentcard_adapter`、`core.runner.drunner.remote_client`/`server_adapter`（`register_remote_client`/`register_server_adapter`）

### 外部依赖
`a2a` SDK（`a2a.client.ClientFactory`/`ClientConfig`、`a2a.types.*`、`a2a.server.*`、`a2a.client.client_factory.TransportProtocol`）、`fastapi`、`uvicorn`

### 设计模式
- **薄 SDK 包装/适配器**：`A2AClient`/`A2AServer` 隐藏 A2A SDK 复杂性于小 openjiuwen 风味面后
- **插件自注册**：`a2a/__init__.py` 导入时即调 `register_remote_client`/`register_server_adapter`，使集成真正可选
- **异步上下文管理器 + 流聚合**：`invoke` 用 `aclosing` 安全聚合
- **传输归一化**：拒绝 gRPC、归一 JSON-RPC 尾斜杠、REST 挂子应用避免路由冲突
- **空包门面**：[extensions/__init__.py](file:///D:/jiuwen/main/agent-core/openjiuwen/extensions/__init__.py) 为空，每个集成可选

> pyproject.toml 中 `all-a2a` 可选依赖组与 `openjiuwen.remote_clients`/`openjiuwen.server_adapters` 入口点（`A2A`）对应此模块。

---

## 7.2 `openjiuwen/rsi/` — 评估与优化框架

### 模块职责

RSI（Research/Subscribe/Improve）评估与优化框架。提供智能体团队的自动协调优化循环：加载评估数据集、profiling/batching cases、通过 `agent_teams` 运行 cases、判定结果、分析评估问题、优化团队技能与成员 harness、学习跨 case 优化经验、持久化编排器运行上下文。顶层 [rsi/__init__.py](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/__init__.py) 重导出完整 harness API。

### 关键类

#### auto_harness 数据模型 — [rsi/auto_harness/schema.py](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/auto_harness/schema.py)

| 类 | 职责 |
|----|------|
| `AutoHarnessConfig` | 大型 dataclass，完整 auto-harness 配置（模型/路径/预算/git/GitCode 认证/CI 门/修复循环重试/不可变文件/agent 迭代）；派生路径属性与解析器；`load_from_dict(data)` |
| `ProjectProfile` | 仓库特定默认值 |
| `AutoHarnessPaths` / `AutoHarnessRuntimeState` | 派生运行时路径与会话状态 |
| `StageSpec` / `PipelineSpec` / `StageResult` | 阶段/管线规约与结果 |
| `Gap` / `OptimizationTask` / `Experience` / `ResearchContext` / `CycleResult` / 各 `*Artifact` | 制品 dataclass |
| `TaskStatus` / `ExperienceType` / `StageSlot` | 枚举（pending/running/success/failed/timeout/reverted；optimization/failure/insight；assess/plan/implement/verify/activate/commit/publish/learnings） |

#### harness 配置 — [rsi/config/config.py](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/config/config.py)

frozen-slots dataclass（各带 `from_dict` classmethod）：

| 类 | 职责 |
|----|------|
| `AutoCoordinatingHarnessConfig` | 顶层编排配置；`from_dict` 将顶层 `ModelConfigs` 合并到每个子配置并 `validate()` |
| `ModelConfigs` / `DataLoaderConfig` / `DatasetCurationConfig` / `DatasetGeneratorConfig` / `SeedEvaluationConfig` / `EvaluatorConfig` / `EvaluationResultAnalyzerConfig` / `TeamSkillOptimizerConfig` / `MemberOptimizerConfig` / `OptimizationExperienceLearnerConfig` / `OrchestratorSchedulingConfig` | 各子配置 |

#### 共享 schema — [rsi/schema.py](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/schema.py)

frozen-slots dataclass：`DatasetArtifact`、`CurrentArtifactRefs`、`BestArtifactRefs`、`EvaluationHistoryItem`、`BatchOptimizationResult`、`TeamSkillOptimizationHistoryItem`、`MemberOptimizationHistoryItem`、`CallAuditRecord`、`RunStrategyMetadata`、`OrchestratorHistory`、**`OrchestratorRunContext`**（真相源状态）、`EvaluationInvocation`、`TeamIssue`、`EvaluationResultAnalysisArtifact`、各 `*Invocation`、`ActionDefinition`。另定义 `OrchestratorPhase` 枚举与 `EvaluationScript` Protocol。

#### 数据加载 — [rsi/data_loader/loader.py](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/data_loader/loader.py) & [profiler.py](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/data_loader/profiler.py)

| 类 | 职责 |
|----|------|
| `DataLoader` | 加载 JSON 数据集文件并产出平衡批次的 `CaseMapping`；`load(dataset_dir, epoch=1)` 支持单 case/列表/`{"cases":[...]}` 文件形态 |
| `DatasetProfiler` | 构建确定性元数据摘要；`profile(cases, balance_keys)` 返回 summary/warnings/metadata |

#### 评估器 — [rsi/evaluator/case_runner.py](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/evaluator/case_runner.py)、[errors.py](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/evaluator/errors.py)、[judger/base.py](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/evaluator/judger/base.py)

| 类 | 职责 |
|----|------|
| `CaseRunner` | 运行一个数据集 case 经 `agent_teams`，采集制品、构建有界轨迹事件、判定、持久化 `trace.json`/`result.json`；`execute(*, case, output_dir, ...)`；`_judge` 回退 backend judge → 配置 judger → 默认分数 |
| `EvaluationInfrastructureError` | `RuntimeError` 子类，评估器无法获得可信分数时抛 |
| `EvaluationJudger` (ABC) + `JudgeResult` | 抽象 judger 契约 `judge(*, case, execution_result, output_dir)`；`JudgeResult` frozen dataclass（method/score/passed/reason/metadata） |

#### 编排器上下文 — [rsi/orchestrator/context.py](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/orchestrator/context.py)

| 类 | 职责 |
|----|------|
| `OrchestratorContextStore` | 读写 `orchestrator_context.yaml`；`load()`/`save(context)`/`create(task, *, strategy)` |

#### 资源与存储门面 — [rsi/resource/manager.py](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/resource/manager.py)、[rsi/storage/store.py](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/storage/store.py)

| 类 | 职责 |
|----|------|
| `ResourceManager` | 门面：`read_text`/`resolve_path`（TODO 桩，`NotImplementedError`） |
| `ArtifactStore` | 门面：`allocate_*`/`write_result_ref`（TODO 桩） |

### 关键函数

| 函数 | 文件 | 职责 |
|------|------|------|
| `load_auto_coordinating_harness_config(config_path)` | [config/loader.py](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/config/loader.py) | 加载/校验 `orchestrator.yaml`，缺失时从捆绑模板引导 |
| `read_yaml_mapping` / `write_yaml_mapping` / `read_json_mapping` / `write_json_mapping` | [artifact_io.py](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/artifact_io.py) | 文件系统 JSON/YAML 制品类型化助手 |
| `run_model_call_with_retries(call, *, operation_name, max_retries)` | [model_call.py](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/model_call.py) | 重试超时/乱码失败；从不回退已知坏文本；`DEFAULT_MODEL_CALL_MAX_RETRIES = 20` |
| `repair_text_mojibake(value)` / `repair_payload_mojibake(value)` / `has_unrepaired_mojibake(value)` | [text_encoding.py](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/text_encoding.py) | 乱码感知文本修复 |
| `llm_usage_ledger(path, *, run_id)` / `record_llm_usage(...)` / `summarize_llm_usage_file(...)` | [usage_recorder.py](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/usage_recorder.py) | 上下文本地、线程安全、范围标注的 LLM 用量记录与 JSONL 摘要 |
| `run_before_after_comparison(...)` / `build_report(...)` / `write_report_files(...)` | [comparison.py](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/comparison.py) | 前后对比工作流（对 baseline 与 optimized refs 运行同 cases，产出 YAML+Markdown 报告含分数差） |
| `load_auto_harness_config(config_path, *, workspace_hint)` / `normalize_pipeline_preference(value)` | [auto_harness/schema.py](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/auto_harness/schema.py) | 加载 auto-harness 配置 / 将 `"auto"`/`"meta"`/`"extended"` 别名映射到规范管线名 |

### 子包（[rsi/__init__.py](file:///D:/jiuwen/main/agent-core/openjiuwen/rsi/__init__.py) 重导出）

`config`、`data_loader`、`dataset_curator`、`dataset_generator`、`evaluation_result_analyzer`、`evaluator`、`member_optimizer`、`optimization_experience_learner`、`orchestrator`、`team_skill_optimizer`、`auto_harness`、`progress`、`schema`

### 内部依赖
`rsi.schema`（广泛）、`rsi.config`、`rsi.text_encoding`、`rsi.model_call`、`rsi.evaluator`（`TeamEvaluator`/`EvaluationJudger`/`JudgeResult`/`CaseExecutionBackend` 等）、`rsi.data_loader.*`、`rsi.auto_harness.pipelines`（`EXTENDED_EVOLVE_PIPELINE`/`META_EVOLVE_PIPELINE`/`normalize_pipeline_name`）、`core.foundation.llm.model.Model`、`core.common.logging`、`agent_teams.paths`、`agent_teams.schema.blueprint`、`agent_teams.spawn.shared_resources`

### 设计模式
- **自动协调优化框架**：`AutoCoordinatingHarnessConfig.from_dict` 自顶向下配置合并 + 跨字段 `validate()`；编排器强制固定调度策略契约（`hybrid`/`team_first_single_pass`/`epoch_full_evaluation`）
- **声明式管线/阶段注册表**：`StageSpec`/`PipelineSpec`/`StageSlot` 分离声明性元数据与执行
- **RSI 评估框架 + case runner + judger**：`CaseRunner` 单异步入口编排 backend 执行 → 制品采集 → 有界轨迹事件 → judger → 持久化；`EvaluationJudger` ABC + `JudgeResult` + 回退
- **有界证据抽取**：`CaseRunner` 构建有界轨迹事件窗口，诊断收到紧凑因果时间线而非原始巨大轨迹
- **每 case 隔离经运行时 home 重定向**：`configure_openjiuwen_home`/`reset_openjiuwen_home` 将 scratch 状态重定向到 case 级运行时 home
- **YAML 持久化编排器上下文**：`OrchestratorContextStore` 单一真相源，含 `CallAuditRecord` 审计轨迹
- **模型调用重试守卫**：超时/乱码可重试，拒绝返回已知坏文本
- **上下文本地用量账本**：`_UsageLedger` + `ContextVar` + `threading.Lock`
- **乱码感知文本修复**：跨 `gbk`/`gb18030`/`latin1`/`cp1252` 重编码评分候选
- **门面桩**：`ResourceManager`/`ArtifactStore` 定义意图接口但 `NotImplementedError`，标记存储后端插入缝
- **前后对比工作流**：`comparison.py` 组合 `OrchestratorContextStore` + `TeamEvaluator`
- **兼容重导出**：[openjiuwen/auto_harness/__init__.py](file:///D:/jiuwen/main/agent-core/openjiuwen/auto_harness/__init__.py) 保留迁移前导入路径
