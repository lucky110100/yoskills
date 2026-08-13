# Auto Harness 自动优化

> 交叉引用: [01-项目概述](../01-project-overview.md) | [02-整体架构](../02-overall-architecture.md) | [03-agents与swarm](../03-agents-and-swarm-module.md) | [特性索引](README.md)

## 一、能力概述

Auto Harness 是 JiuwenSwarm 的"评估驱动、端到端自动 Harness 优化"能力。它的核心理念是:**不训练模型权重**,而是让 Harness(围绕模型的外围编排层:prompt、rails、tools 配置)在真实实践中通过执行→评估→反馈的闭环自动进化。换言之,模型本身保持冻结,优化的是"如何使用模型"的那一层。

这一设计把"AI 工程优化"从昂贵的权重微调,下沉到成本可控的 Harness 调参。Auto Harness 以 issue 驱动或任务驱动的方式收集执行轨迹,经评估器打分,再把反馈投射回 Harness 配置(扩展设计、运行时扩展产物、流水线阶段),从而让同一套模型在反复实践中越用越准。

在实现分层上,Auto Harness 的能力底座来自 openjiuwen 框架的 `auto_harness` 子包(提供 `AutoHarnessConfig`、`AutoHarnessOrchestrator`、pipelines、stages、contexts、schema 等基础设施);本仓库 `agents/harness/common/auto_harness/` 只做"装配与服务化"——把 JiuwenSwarm 的模型配置、Git 认证、调度器、任务存储、chunk 映射等工程胶水接上,使 openjiuwen 的编排器能在 JiuwenSwarm 运行时里以服务形式对外提供。这种"框架下沉、平台装配"的分层与 Swarm 装配一脉相承。

## 二、关键类与函数

| 类/函数 | 文件位置 | 说明 |
| --- | --- | --- |
| AutoHarnessService | [service.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/common/auto_harness/service.py#L213) | 自动 Harness 服务:JiuWenSwarmDeepAdapter 成员,管理仓库解析/克隆/配置构建/会话流式/取消 |
| AutoHarnessConfig / AutoHarnessOrchestrator | [service.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/common/auto_harness/service.py#L35) | 经 `openjiuwen.auto_harness` 导入的配置/编排器,经 ensure_harness_elements_registered 注册 |
| load_auto_harness_config / OptimizationTask / ExtensionDesign / RuntimeExtensionArtifact / StageResult | [service.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/common/auto_harness/service.py#L43) | schema:任务/扩展设计/运行时产物/阶段结果与配置加载 |
| TaskContext / TaskRuntime | [service.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/common/auto_harness/service.py#L50) | 上下文:任务运行时上下文与运行时句柄 |
| EXTENDED_EVOLVE_PIPELINE / ExtensionTaskPipeline | [service.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/common/auto_harness/service.py#L51) | 流水线:扩展演进流水线与扩展任务流水线 |
| ExtendActivateStage | [service.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/common/auto_harness/service.py#L55) | 阶段:扩展激活阶段 |
| build_git_auth_env | [service.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/common/auto_harness/service.py#L40) | infra.git_auth:Git 认证环境构建(经 configure_gitcode_auth) |
| AgentResponseChunk | [agent.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/schema/agent.py) | auto_harness chunk→响应映射的数据契约 |
| build_auto_harness_config | [service.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/common/auto_harness/service.py#L701) | 由模型配置构建 AutoHarnessConfig(含 override) |
| clone_or_update_repo | [service.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/common/auto_harness/service.py#L571) | 仓库 URL 解析与克隆/更新 |
| run | [service.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/common/auto_harness/service.py#L1367) | 编排器会话流式入口:克隆→配置→orchestrator→stream |
| _map_chunk_to_response | [service.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/common/auto_harness/service.py#L1629) | openjiuwen chunk→AgentResponseChunk/WS 事件映射 |
| Scheduler / TaskStore | [scheduler.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/common/auto_harness/scheduler.py) / [task_store.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/common/auto_harness/task_store.py) | 调度器与任务存储 |
| ConfigValidator / AutoHarnessCapabilityRegistry | [config_validator.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/common/auto_harness/config_validator.py) / [capabilities.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/common/auto_harness/capabilities.py) | 配置校验与能力注册表 |

## 三、实现机制

Auto Harness 的优化闭环可概括为"评估驱动 → Harness 反馈 → 模型不动"。整个流程由 `AutoHarnessOrchestrator` 编排,经 pipelines→stages 流水线推进,本仓库只负责装配与服务化。

### 1. 评估驱动:执行轨迹 → 评估 → Harness 反馈

闭环的核心是"用实践产生的数据反哺 Harness",而非反哺模型权重:

```text
[1] 任务输入(issue / 用户请求)
      │
      ▼
[2] clone_or_update_repo(service.py#L571) 解析/克隆目标仓库
      │  build_git_auth_env(service.py#L40) 注入 Git 认证
      ▼
[3] build_auto_harness_config(service.py#L701) 由模型配置构建 AutoHarnessConfig
      │  _build_model_from_env 解析模型/ModelClientConfig
      ▼
[4] AutoHarnessOrchestrator 编排 pipelines→stages
      │  EXTENDED_EVOLVE_PIPELINE / ExtensionTaskPipeline(service.py#L51)
      │  ExtendActivateStage(service.py#L55) 扩展激活
      │  TaskContext/TaskRuntime(service.py#L50) 携带运行时上下文
      ▼
[5] 收集执行轨迹 → 评估打分 → 反馈 Harness 配置
      │  优化对象:prompt / rails / tools 配置,不碰模型权重
      ▼
[6] 产出 RuntimeExtensionArtifact / ExtensionDesign(service.py#L43)
      │  扩展产物可激活/打包/导入导出
      ▼
[7] _map_chunk_to_response(service.py#L1629) chunk→AgentResponseChunk 流式下发
```

第 [4] 步的编排器与流水线来自 openjiuwen,本仓库经 `ensure_harness_elements_registered` 把 harness 元素注册进框架,使编排器能识别 JiuwenSwarm 的 rail/tool 工厂。第 [5] 步是"不训练权重"的关键:反馈只改写 Harness 层(prompt/rails/tools 配置与扩展产物),模型本身保持冻结,因此优化成本远低于微调,且模型无关。

### 2. 不训练模型权重,优化 prompt/rails/tools 配置

Harness 在 JiuwenSwarm 中是"围绕模型的外围编排层":system prompt、rails(运行时拦截/注入)、tools(可调用工具集)、subagents。Auto Harness 的优化对象正是这一层,而非模型参数。它的产物表现为 `ExtensionDesign`(扩展设计,描述应如何调整 Harness)与 `RuntimeExtensionArtifact`(运行时扩展产物,可激活到 Harness 上)。这种"产物化"设计让优化结果可版本化、可打包、可回滚,而非一次性黑盒更新。

### 3. AutoHarnessOrchestrator 编排 pipelines→stages

编排器以流水线(pipelines)为单位,每条流水线由若干阶段(stages)组成,阶段间经 `TaskContext`/`TaskRuntime` 传递上下文。`EXTENDED_EVOLVE_PIPELINE` 是扩展演进流水线,`ExtensionTaskPipeline` 负责扩展任务,`ExtendActivateStage` 负责扩展激活。阶段结果以 `StageResult` 表达,便于评估器消费与反馈。

### 4. 经 openjiuwen 框架下沉,本仓库只装配

本仓库 `auto_harness/` 不重复实现编排内核,只做工程胶水:`AutoHarnessService` 作为 `JiuWenSwarmDeepAdapter` 的成员变量持有服务;`Scheduler` 管理定时任务;`TaskStore` 持久化任务状态;`ConfigValidator` 校验配置;`AutoHarnessCapabilityRegistry` 注册能力;`repo_auth` 处理 Gitcode 认证。模型与流水线内核一律来自 `openjiuwen.auto_harness`,保证"框架演进即能力演进"。这种分层还带来一个工程收益:当 openjiuwen 升级编排器或新增阶段时,本仓库无需改动核心逻辑,只需同步 `ensure_harness_elements_registered` 注册的元素清单,即可获得新能力。

### 5. 三种运行模式与产物生命周期

Auto Harness 服务对外提供三种触发模式,对应不同的产物生命周期阶段:

| 模式 | 入口 | 行为 | 产物 |
| --- | --- | --- | --- |
| 完整 run | `run(service.py#L1367)` | 克隆仓库→构建配置→编排器会话流式→评估反馈 | ExtensionDesign + RuntimeArtifact |
| implement_only | `run_implement_only(service.py#L1179)` | 仅按已有扩展设计实现运行时产物 | RuntimeExtensionArtifact |
| activate_only | `run_activate_only(service.py#L981)` | 仅激活已有运行时产物到 Harness | 激活态扩展 |

产物生命周期由 `add_package`/`activate_package`/`deactivate_package`/`delete_package`/`export_package`/`import_package` 组成,产物以 `package_id` 标识,状态持久化到 `harness-packages.json`。`generate_package_id` 基于运行时产物路径生成稳定 id,`scan_runtime_extensions` 扫描可用产物,`update_active_status` 维护激活/停用状态。这一套生命周期使优化产物可版本管理、可跨环境迁移(导出 zip→导入)、可回滚(停用/删除),符合"产物化、可回滚"的工程要求。

### 6. chunk 映射与流式下发

`_map_chunk_to_response`([service.py#L1629](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/common/auto_harness/service.py#L1629))负责把 openjiuwen 编排器产出的内部 chunk 映射为 JiuwenSwarm 的 `AgentResponseChunk`(`common/schema/agent.py`),再经 `JiuSwarmStreamEventRail` 以 WS 事件下发前端。`_consume_stream`([service.py#L1735](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/common/auto_harness/service.py#L1735))是流式消费协程,负责把编排器的异步流逐 chunk 投递到映射函数,并处理取消(`cancel_session_run`/`cancel_all_runs`)与活动 run 管理(`ActiveAutoHarnessRun`/`get_active_run`/`has_active_run`)。这一层使 openjiuwen 的流式协议与 JiuwenSwarm 前端的 WS 事件协议解耦,两侧可独立演化。

## 四、调用示例

### 4.1 服务初始化与流式运行

```python
from jiuwenswarm.agents.harness.common.auto_harness.service import AutoHarnessService

service = AutoHarnessService(...)           # 作为 Adapter 成员
await service.start_scheduler()             # scheduler.py 启动调度
# run(service.py#L1367):克隆仓库→构建配置→orchestrator 会话流式
async for chunk in service.run(
    request=request, query="优化代码探索能力", repo_url="https://gitcode.com/xxx.git",
):
    # chunk 经 _map_chunk_to_response(service.py#L1629) 映射为 AgentResponseChunk
    yield chunk
```

### 4.2 扩展产物激活/打包/导入

```python
# activate_only:仅激活已有运行时扩展产物
await service.run_activate_only(request, query="...")   # service.py#L981
# 打包导出扩展产物(package_id)
path = service.export_package(package_id="pkg-001")      # service.py#L2582
# 导入扩展产物包
service.import_package(zip_path=path)                   # service.py#L2640
# 激活/停用/删除扩展包
await service.activate_package(package_id="pkg-001")     # service.py#L2288
```

### 4.3 Gitcode issue 驱动(可选)

```python
# issue 驱动:扫描 issue 矩阵,自动产生优化任务
await service.process_gitcode_issues_once()             # service.py#L487
await service.refresh_issue_matrix(params={...})         # service.py#L514
states = await service.list_gitcode_issue_states()       # service.py#L503
await service.delete_issue_states(params={"ids": [...]}) # service.py#L510
```

### 4.4 定时调度与任务管理

```python
# scheduler.py 调度器:创建/运行/取消/列出定时优化任务
task_id = await service.create_scheduled_task(...)       # service.py#L2770
await service.run_task(task_id=task_id)                  # service.py#L2840
await service.cancel_scheduled_task(task_id=task_id)     # service.py#L2915
tasks = await service.list_scheduled_tasks()            # service.py#L2982
status = await service.get_scheduled_task_status(task_id=task_id)  # service.py#L2969
# 配置校验与默认填充:_fill_config_defaults(service.py#L304)
# 配置校验器 ConfigValidator 在构建前校验 config 形状
```

### 4.5 取消与活动 run 管理

```python
# ActiveAutoHarnessRun(service.py#L195) 跟踪进行中的会话
if service.has_active_run(session_id="sess-1"):         # service.py#L1999
    service.cancel_session_run(session_id="sess-1")     # service.py#L1975
# _consume_stream(service.py#L1735) 响应取消,优雅收尾流式消费
service.cancel_all_runs()                                # service.py#L2003
```

### 4.6 产物扫描与包管理

```python
# scan_runtime_extensions(service.py#L2037) 扫描可用运行时产物
info = service.get_packages_info()                      # service.py#L2284
pkg = AutoHarnessService.find_package_by_id(           # service.py#L2227
    packages=service.load_packages(), package_id="pkg-001")
AutoHarnessService.update_active_status(               # service.py#L2234
    package_id="pkg-001", operation="add")
# load_packages/save_packages 读写 harness-packages.json(_load_packages_no_fallback)
```

## 五、业界对比

| 维度 | JiuwenSwarm | DSPy | TextGrad | LangSmith |
| --- | --- | --- | --- | --- |
| 优化对象 | Harness(prompt/rails/tools 配置),不碰权重 | 自动 prompt 优化 | 梯度文本反传 | 仅评估与观测 |
| 驱动方式 | 执行轨迹→评估→反馈闭环 | 示例驱动 bootstrap | 文本梯度下降 | 人工标注+评估 |
| 端到端 | 端到端:克隆→配置→编排→产物→激活 | 半端到端 | 仅优化层 | 非端到端 |
| 模型无关 | 模型冻结,Harness 优化模型无关 | 模型无关 | 模型无关 | 模型无关 |
| 产物化 | ExtensionDesign/RuntimeArtifact 可版本化/打包/回滚 | prompt 文本 | 文本梯度 | 评估报告 |
| 框架下沉 | openjiuwen 编排,本仓库只装配 | 自带 | 自带 | 自带 |

JiuwenSwarm 的差异化在于"评估驱动 + 模型不动 + 端到端产物化":它不像 DSPy 只优化 prompt 文本,也不像 TextGrad 停留在文本梯度,而是把优化对象扩展到整个 Harness(rails/tools 配置),并以 `ExtensionDesign`/`RuntimeExtensionArtifact` 形式产物化、可激活、可回滚。相对 LangSmith 的纯评估定位,本能力形成"评估→反馈→激活"的完整闭环,且经 openjiuwen 框架下沉,本仓库只做装配,保证优化内核可随框架统一演进。

## 六、小结

1. Auto Harness 是评估驱动、端到端的 Harness 自动优化能力,**不训练模型权重**,只优化 prompt/rails/tools 配置,使模型在冻结状态下越用越准。
2. 优化闭环为:执行轨迹→评估→反馈 Harness 配置→产出 `ExtensionDesign`/`RuntimeExtensionArtifact`,产物可版本化、打包、激活、回滚。
3. `AutoHarnessOrchestrator` 编排 pipelines→stages 流水线,经 `TaskContext`/`TaskRuntime` 传递上下文,`ExtendActivateStage` 等阶段产出 `StageResult` 供评估消费。
4. 能力底座来自 openjiuwen 的 `auto_harness` 子包,本仓库 `auto_harness/` 只做装配与服务化(`AutoHarnessService`/`Scheduler`/`TaskStore`/`ConfigValidator`/`repo_auth`),经 `ensure_harness_elements_registered` 注册 harness 元素。
5. 相对 DSPy/TextGrad/LangSmith,本能力以"评估驱动 + 模型不动 + 端到端产物化 + 框架下沉"形成差异化,把 AI 工程优化从权重微调下沉到成本可控的 Harness 调参。
