# jiuwenswarm RSI 两层架构职责拆解

> **文档性质**：架构分析报告（服务域 vs 引擎层职责边界）
> **分析对象**：`jiuwenswarm`（服务域）+ `agent-core/openjiuwen/rsi`（引擎层）
> **代码基线**：`D:/jiuwen/third/jiuwenswarm`、`D:/jiuwen/main/agent-core`
> **编写日期**：2026-11-13
> **关联文档**：《RSI-jiuwenswarm实现归类分析-v1.md》（同目录，讲分类判定与正则化对照）

---

## 0. 结论

这是标准的**服务层 + 引擎层**分离架构：

- **jiuwenswarm 服务域**：面向用户的「壳」，负责 HTTP/WebSocket、任务调度、状态持久化、事件投影——**不碰任何优化算法逻辑**

- **agent-core 引擎层**：纯 Python 库，不关心 HTTP/WebSocket，只做一件事——**在冻结的 case 集上自动改进 harness 包**

两层通过 **Provider Protocol**（`run` / `read_state` / `read_report`）解耦，引擎可以被任何调用方复用（CLI、测试、其他服务），不绑定 jiuwenswarm 的网络协议。

[RSI 两层架构职责边界](./rsi-two-layer-architecture2.png)

上图：上半部分紫色为 jiuwenswarm 服务域的 6 个职责模块，下半部分绿色为 agent-core 引擎层的 6 个核心模块，中间通过 Provider Protocol 解耦。

---

## 1. jiuwenswarm 服务域（控制面）

### 概览

- **代码位置**：`jiuwenswarm/jiuwenswarm/agents/harness/common/rsi/`（~30 个文件）

- **网络入口**：`jiuwenswarm/server/rsi/rsi_handlers.py`

- **面向**：HTTP / WebSocket

- **不做**：任何评测、归因、规划、门禁逻辑

### 1.1 Web API 入口 — 18 个 `rsi.*` method

`server/rsi/rsi_handlers.py` 注册了 18 个 web method，分四组：

| 组 | method | 功能 |
| - | - | - |
| 数据集 | `rsi.dataset.validate` | 校验 case 格式（case_id 空/重复检查） |
| 任务 | `rsi.task.{create,list,get,delete}` | 任务 CRUD |
| 训练 | `rsi.training.{start,pause,resume,terminate}` | 生命周期控制 |
| 产物 | `rsi.report.get`、`rsi.usage.get`、`rsi.artifact.{download,files.list,files.get}` | 查看结果与用量 |
| 树 | `rsi.tree.get` | 候选树投影 |
| harness | `rsi.harness.{install,versions.list,rollback}` | harness 版本安装/回退 |

另外有 3 个推送通道：`rsi.training.{status.changed,progress,tree.delta}`。

### 1.2 任务生命周期状态机

`task_store.py` 维护 7 态状态机：

```
CREATED → QUEUED → RUNNING → COMPLETED / FAILED
                  ↘ PAUSED → QUEUED（resume）
              ↘ TERMINATED
```

合法迁移表硬编码（`_STATUS_TRANSITIONS`），非法迁移抛 `TASK_STATE_CONFLICT`。存储用 JSON 文件落盘（`.jiuwenswarm/rsi/tasks/<task_id>/task.json`），不引入数据库。

### 1.3 并发控制

`worker.py` 是单协程队列（`_QUEUE_MAXSIZE=128`，全局并发=1）。同一时刻只跑一个 RSI 任务，其余排队。启动任务时装配事件链路（sink → 有界队列 → 消费协程），然后 `await adapter.run(request, on_event=sink)`。

### 1.4 数据集归一化 + 输入冻结

- `validation_dataset.py`：把 GDPVAL 格式的 `validation` 数组转成引擎期望的 `cases` 数组（`case_id` + `input` 字段映射）

- `materializer.py`：把数据集和 harness 包各复制一份快照 + sha256，本次运行只读这份快照——防止评测期间输入被篡改

### 1.5 进度/树投影 + 事件消费

- `event_consumer.py`：单协程消费引擎事件（`progress.metric`、`progress.usage`、`node.created`、`node.stage`），分发到用量记账、树投影、推送回调

- `projector.py`：把引擎原始事件转成用户可读的进度快照和候选树。推/拉同源：`derive_progress` / `derive_tree` / `derive_tree_delta` 都取自同一份 `nodes` 缓存

### 1.6 服务侧附加能力

| 模块 | 职责 |
| - | - |
| `harness_activation.py` | harness 版本安装/激活/回退持久化（独立于引擎的优化结果发布） |
| `recovery.py` | 进程重启后恢复中断中的任务（`RsiWorkspaceRecovery`） |
| `usage_recorder.py` | token 用量记账（按节点/任务聚合，**只记账不参与判定**） |
| `context.py` | 组合根，一次性装配 store/worker/projector/adapter |
| `harness_provider.py` | 引擎编排器的薄包装，把引擎落盘 YAML 读回归一化成服务侧模型 |
| `provider_factory.py` | 唯一的 mock vs production 选择点 |

---

## 2. agent-core 引擎层（执行面）

### 概览

- **代码位置**：`agent-core/openjiuwen/rsi/`

- **性质**：纯 Python 库，无 HTTP 依赖

- **通信方式**：通过 Provider Protocol 被调用；落盘 YAML + `on_event` 回调输出

- **导出入口**：`openjiuwen/rsi/__init__.py`

引擎层导出三大块：

### 2.1 harness_rsi — C 类主链路

| 模块 | 文件规模 | 职责 |
| - | - | - |
| `single_harness/iterative.py` | 4554 行 | **编排器**：epoch → 评测 → 归因 → 规划 → 执行 → 门禁 → 晋级，循环往复 |
| `single_harness/promotion_policy.py` | 138 行 | **晋级门禁**：两阶段判定（目标 batch + 全量重放），sha256 指纹校验 |
| `single_harness/continuous.py` | 484 行 | 连续式晋级（目标 → 全量两阶段） |
| `single_harness/behavior_check.py` | | 行为变化检查 |
| `single_harness/candidate_feedback.py` | | 候选反馈与停滞检测 |
| `evaluator/` | 20+ 文件 | **评测器**：真跑 harness，输出 0–1 连续分，拒绝 binary LLM 评分 |
| `member_optimizer/` | 20+ 文件 | **归因 + 规划 + 执行** |
| `member_optimizer/action_groups/policy.py` | | **可编辑面白名单**：prompt/config/rail/skill/tool 五类，路径前缀硬校验 |
| `member_optimizer/action_planner.py` | 1846 行 | 动作规划（白名单约束 + 历史经验参考） |
| `member_optimizer/role_attributor.py` | | 角色归因（判断失败是不是这个角色的问题） |
| `member_optimizer/mechanism_attributor.py` | | 机制归因（判断失败机制落在哪个 lever：instruction/action/control/configuration） |
| `member_optimizer/verification.py` | | 静态校验（危险符号黑名单：`eval`/`exec`） |
| `member_optimizer/worktree_coordinator.py` | | worktree 隔离（每 action 一个独立 git worktree，拓扑排序分波次） |
| `data_loader/` | 8 文件 | 数据集加载 + case 格式校验 |
| `config/config.py` | | 所有配置项（PromotionConfig、MemberOptimizerConfig 等） |
| `auto_harness/` | | **B 类旁路**：改源码的 assess → plan → implement → verify → commit → publish_pr 流水线 |

引擎**不做**的事：不管任务队列、不管 HTTP、不管数据集文件从哪来、不管结果怎么推给用户。

### 2.2 artifact_rsi — A 类能力（artifact 专用）

| 模块 | 职责 |
| - | - |
| `program_opt/` | PUCT 树搜索 + 种群进化（`puct_engine.py`、`tree.py`、`candidates.py`、`scorecard.py`、`state.py`） |
| `paper_opt/` | 论文自动研究（`auto_research/` 树搜索 provider） |

### 2.3 公共 schema

`schema.py` 定义跨层共享的数据结构，服务域直接 import 使用：

| 类 | 用途 |
| - | - |
| `RsiTaskCreateRequest` | 任务创建请求 |
| `RsiTaskEnvelope` | 任务信封 |
| `EngineState` | 引擎状态快照 |
| `EngineReport` | 引擎报告 |
| `EngineResult` | 引擎结果 |
| `RsiTreeNode` | 树节点 |
| `TreeResponse` | 树响应 |
| `ArtifactRef` | 产物引用 |
| `RsiUsage` / `RsiUsageTokens` | 用量结构 |

---

## 3. 两层怎么接上的

解耦点是 **Provider Protocol**，定义在 `harness_adapter.py`：

```python
class HarnessProviderContract(Protocol):
    supports_pause: bool
    supports_resume: bool
    supports_terminate: bool

    def validate_input(self, path: str | None) -> Any: ...
    async def run(self, request: HarnessEngineRequest, *, on_event: Any = None) -> Any: ...
    # read_state / read_report / get_tree 由具体实现提供
```

调用关系：

```
服务域                              引擎层
──────────────────────────────────────────────────────────
harness_provider.py  ──import──>  SingleHarnessIterativeOptimizationOrchestrator
  run(request)                     │  .run(...)
  read_state()                     │  → 落盘 single_harness_state.yaml
  read_report()                    │  → 落盘 single_harness_report.yaml
  get_tree()                       │  → 落盘 epoch 节点投影
  pause/terminate()                │  → 不支持，抛 RsiNotReady
  validate_input()                 │  → load_cases() 真校验
```

`harness_provider.py` 的 docstring 写得很清楚：它是引擎编排器的**薄包装**，把引擎落盘的 YAML 文件读回来，归一化成服务侧的 `EngineState` / `EngineReport`。引擎发事件（`on_event` 回调），服务域消费。

`provider_factory.py` 提供 mock / real 两条装配路径：

- `build_mock_rsi_adapters`：确定性假实现（本地 E2E 测试用）

- `build_rsi_adapters`：注入 `HarnessProvider` 生产实现

切换不需要改服务域代码。

---

## 4. 分离的代价与收益

### 代价

**引擎不支持中途取消。** `pause` / `terminate` 抛 `RsiNotReady`，因为优化循环是原子性的——要么跑完一个 epoch，要么等当前 case 评测完。想加取消能力，得改引擎层（在 `iterative.py` 的 epoch 之间插入 cooperative cancellation check），不能只改服务域。

### 收益

1. **引擎可复用**。不绑定 jiuwenswarm 的 HTTP/WebSocket 协议，可以被 CLI、测试、其他服务直接调用
2. **mock/real 切换零成本**。服务域代码不变，只换 `provider_factory` 的注入
3. **职责清晰**。服务域的人不需要懂优化算法，引擎层的人不需要懂 WebSocket

---

## 5. 速查表

| 维度 | jiuwenswarm 服务域 | agent-core 引擎层 |
| - | - | - |
| 代码位置 | `agents/harness/common/rsi/`（~30 文件） | `openjiuwen/rsi/`（100+ 文件） |
| 最大单文件 | — | `iterative.py`（4554 行） |
| 核心职责 | 任务调度 + API + 持久化 + 事件投影 | 优化算法 + 评测 + 归因 + 规划 + 门禁 |
| 依赖关系 | import agent-core | 不依赖 jiuwenswarm |
| 通信方式 | Provider Protocol（`run`/`read_state`/`read_report`） | 落盘 YAML + `on_event` 回调 |
| 可独立运行 | 否（需要引擎） | 是（纯库，CLI/测试直接调） |
| 关心 HTTP | 是 | 否 |
| 关心优化算法 | 否 | 是 |
| 改什么 | 不改代码 | 改 harness 包文件（C 类）/ 改源码（B 类 `auto_harness`） |
| 并发控制 | 单队列 N=1（`worker.py`） | 无（由调用方控制） |
| 状态持久化 | JSON 文件（`task.json`） | YAML 文件（`single_harness_state.yaml` 等） |

---

## 附录：关键文件索引

### 服务域

| 文件 | 职责 |
| - | - |
| `server/rsi/rsi_handlers.py` | 18 个 `rsi.*` web method 注册 |
| `agents/harness/common/rsi/harness_provider.py` | 引擎编排器薄包装（Provider 实现） |
| `agents/harness/common/rsi/harness_adapter.py` | Provider Protocol 定义 + 请求结构 |
| `agents/harness/common/rsi/provider_factory.py` | mock vs production 装配点 |
| `agents/harness/common/rsi/task_store.py` | 任务存储 + 7 态状态机 |
| `agents/harness/common/rsi/worker.py` | 单队列 worker（并发=1） |
| `agents/harness/common/rsi/event_consumer.py` | 引擎事件消费协程 |
| `agents/harness/common/rsi/projector.py` | 进度/树投影 |
| `agents/harness/common/rsi/materializer.py` | 输入冻结 + sha256 |
| `agents/harness/common/rsi/validation_dataset.py` | 数据集格式归一化 |
| `agents/harness/common/rsi/harness_activation.py` | harness 安装/回退持久化 |
| `agents/harness/common/rsi/recovery.py` | 中断任务恢复 |
| `agents/harness/common/rsi/usage_recorder.py` | token 用量记账 |
| `agents/harness/common/rsi/context.py` | 组合根（服务域组件容器） |
| `agents/harness/common/rsi/services.py` | 薄封装服务（Dataset/Task/Report/Tree） |
| `agents/harness/common/rsi/models.py` | 公共模型（TaskStatus/Scenario/ArtifactType） |

### 引擎层

| 文件 | 职责 |
| - | - |
| `openjiuwen/rsi/__init__.py` | 引擎层导出入口 |
| `openjiuwen/rsi/schema.py` | 跨层共享数据结构 |
| `harness_rsi/single_harness/iterative.py` | 编排器（4554 行） |
| `harness_rsi/single_harness/promotion_policy.py` | 晋级门禁数学 |
| `harness_rsi/single_harness/continuous.py` | 连续式两阶段晋级 |
| `harness_rsi/evaluator/` | 评测器（20+ 文件） |
| `harness_rsi/member_optimizer/action_groups/policy.py` | 可编辑面白名单 |
| `harness_rsi/member_optimizer/action_planner.py` | 动作规划（1846 行） |
| `harness_rsi/member_optimizer/role_attributor.py` | 角色归因 |
| `harness_rsi/member_optimizer/mechanism_attributor.py` | 机制归因 |
| `harness_rsi/member_optimizer/verification.py` | 静态安全校验 |
| `harness_rsi/member_optimizer/worktree_coordinator.py` | worktree 隔离执行 |
| `harness_rsi/data_loader/` | 数据集加载 |
| `harness_rsi/config/config.py` | 配置项 |
| `harness_rsi/auto_harness/` | B 类旁路（改源码流水线） |
| `artifact_rsi/program_opt/` | A 类进化搜索 |
| `artifact_rsi/paper_opt/` | 论文自动研究 |

