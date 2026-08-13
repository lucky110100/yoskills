# 06 symphony 模块(代码知识引擎)

> 交叉引用: [01-项目概述](../01-project-overview.md) | [02-整体架构](../02-overall-architecture.md) | [07-extensions与hooks](../07-extensions-and-hooks-module.md) | [10-依赖关系](../10-dependencies.md)

## 一、能力概述

`symphony` 是 JiuwenSwarm 的代码知识引擎,定位为系统的"离线 Score 构建 + 在线规划"双态子系统。它把散落在文件系统中的 Skill(每个 Skill 由 `SKILL.md` + schema 组成)抽取为标准化的"指纹",再经 LLM 本体匹配把它们组织成一张 Skill 知识图谱,最终产出一份可检索、可发布的 Score 产物(tree index、catalog、retriever index、graph、score lookup)。这份 Score 是离线冻结的"知识快照",为在线规划提供稳定的拓扑基线。

在线侧,`plan_from_score` 基于已构建的 Score 与一张"动态演化叠加层",用 fast / beam 两种策略把自然语言 query 解析为可执行的 Skill 编排计划:节点是 Skill,边是数据依赖,权重由置信度与演化经验共同决定。演化子系统会持续记录每次 plan 的成败,据此更新边权重,使知识图谱随运行自我优化——越用越准,这正是 Symphony 区别于普通索引检索的核心。

设计上,Symphony 把"知识"切成两层:冻结的图谱(基线拓扑,稳定可复现)与动态的叠加层(运行期学习,边权重浮动)。规划时读"基线 + 叠加层",演化时只改叠加层、不动基线,二者互不污染。同时,`ExperienceBank`(FAISS)与 `EvaluationAccumulator` 五维聚合为演化提供量化信号,使"越用越准"有据可依而非黑箱调参。这一分层是 Symphony 可在生产环境长期运行而不腐化的关键。

Symphony 内部按 8 个子领域组织,各司其职又彼此咬合,共同构成"指纹→图谱→索引→检索→经验→演化→编排→评估"的闭环:

| 子领域 | 职责 | 关键文件 |
| --- | --- | --- |
| fingerprint | 扫描 Skill 目录、解析 SKILL.md frontmatter、抽取 schema、规范化 IO 名称,产出指纹 | [pipeline.py#L35](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/fingerprint/pipeline.py#L35) · [pipeline.py#L67](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/fingerprint/pipeline.py#L67) · [scan.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/fingerprint/scan.py) · [manifest.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/fingerprint/manifest.py) |
| graph | 指纹→注册表→候选对→LLM 本体匹配→图谱物化→score lookup | [pipeline.py#L21](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/graph/pipeline.py#L21) · [pipeline.py#L47](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/graph/pipeline.py#L47) · [matcher.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/graph/matcher/matcher.py) |
| indexing | catalog 记录组织为层次 tree index + HTML 预览 | [builder.py#L95](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/indexing/tree/builder.py#L95) · [builder.py#L1128](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/indexing/tree/builder.py#L1128) · [models.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/indexing/models.py) |
| retrieval | 加载 Score 产物供在线检索 | [loading.py#L14](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/retrieval/io/loading.py#L14) · [loading.py#L35](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/retrieval/io/loading.py#L35) · [factory.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/retrieval/llm/factory.py) |
| experience | 基于 FAISS 的执行经验存储与经验库构建 | [bank.py#L95](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/experience/bank.py#L95) · [collector.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/experience/collector.py) · [embed.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/experience/embed.py) · [retriever.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/experience/retriever.py) |
| evolution | 事件日志→动态叠加层(边权重),运行时记录 plan 成败 | [service.py#L34](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/evolution/service.py#L34) · [service.py#L40](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/evolution/service.py#L40) · [service.py#L94](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/evolution/service.py#L94) |
| orchestration | 在线规划:加载 score + overlay,fast/beam 规划器产出执行图 | [service.py#L25](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/orchestration/service.py#L25) |
| evaluation/models | 五指标聚合(success_rate/latency/accuracy/completeness/compliance);CID↔worker_id 转换 | [suite.py#L25](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/evaluation/suite.py#L25) · [suite.py#L65](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/evaluation/suite.py#L65) · [converters.py#L11](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/models/cid/converters.py#L11) · [converters.py#L34](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/models/cid/converters.py#L34) |

## 二、关键类与函数

| 类/函数 | 文件位置 | 说明 |
| --- | --- | --- |
| ScoreStatus | [build.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/build.py#L59) | 冻结 dataclass,描述 Score 是否存在/陈旧/可续建及技能计数 |
| SymphonyScoreBuilder | [build.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/build.py#L174) | 离线 Score 构建器 |
| SymphonyScoreBuilder.build | [build.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/build.py#L238) | 异步构建入口:指纹→图谱→状态写入→发布 |
| build_score | [build.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/build.py#L451) | 模块级便捷函数 |
| score_status | [build.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/build.py#L435) | 报告 Score 是否存在且与 Skill 文件夹一致 |
| SymphonyConfig | [config.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/config.py#L96) | 顶层配置:paths/fingerprint/build/evolution/orchestration |
| load_symphony_config | [config.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/config.py#L105) | 从 config.yaml 读取归一化 |
| FingerprintExtractor | [pipeline.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/fingerprint/pipeline.py#L35) | 扫描/解析/抽取/规范化指纹核心类 |
| extract_from_root | [pipeline.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/fingerprint/pipeline.py#L67) | 从 skills_root 抽取指纹,支持增量 + force |
| GraphBuilder | [pipeline.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/graph/pipeline.py#L21) | 图谱构建流水线 |
| GraphBuilder.build | [pipeline.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/graph/pipeline.py#L47) | 异步执行图谱构建产出 GraphBuildResult |
| load_dynamic_overlay | [service.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/evolution/service.py#L34) | 读取当前动态叠加层 |
| rebuild_dynamic_overlay | [service.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/evolution/service.py#L40) | 从事件日志重建并持久化 |
| record_plan_outcome | [service.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/evolution/service.py#L94) | 记录 plan 执行结果,追加事件触发 overlay 重建 |
| plan_from_score | [service.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/orchestration/service.py#L25) | 在线规划:加载 score + overlay,fast/beam 产出执行图 |
| EvaluationAccumulator | [suite.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/evaluation/suite.py#L25) | 按对象身份聚合五指标为 QualityResult |
| EvaluationAccumulator.aggregate | [suite.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/evaluation/suite.py#L65) | 执行聚合计算 |
| WorkerCIDConverters | [converters.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/models/cid/converters.py#L11) | worker_id↔CID 双向映射 |
| build_worker_cid_converters | [converters.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/models/cid/converters.py#L34) | 构建双向映射表 |
| ExperienceBank | [bank.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/experience/bank.py#L95) | FAISS 经验存储 |
| CatalogRecord | [loading.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/retrieval/io/loading.py#L14) | catalog 记录 |
| load_retriever_index | [loading.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/retrieval/io/loading.py#L35) | 加载 Score 产物供在线检索 |
| TreeBuilder | [builder.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/indexing/tree/builder.py#L95) | 层次 tree index 构建器 |
| build_tree | [builder.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/indexing/tree/builder.py#L1128) | 从 catalog 构建层次 tree + HTML |

## 三、实现机制

### 1. 离线 Score 构建流水线

离线构建从 `skills_root` 出发,把磁盘上的 Skill 文件夹沉淀为一份冻结 Score。整条流水线由 `SymphonyScoreBuilder.build` 编排,按"指纹→图谱→索引→产物→发布"五步串行:

**第一步 — 扫描与指纹抽取**。`extract_from_root` 递归 `rglob` 所有 `SKILL.md`,依次执行 `parse_manifests`(解析 frontmatter)、`extract_schemas`(抽取输入输出 schema)、`normalize_schemas`(规范化 IO 名称与数据类型)。`IncrementalFingerprintStore` 在此介入,基于文件指纹哈希做增量复用:仅对变更过的 Skill 重新抽取,未变项直接读缓存,使大规模 Skill 集的重构建成本可控。

**第二步 — 知识图谱构建**。`GraphBuilder.build` 把指纹送入一条串行流水:`registry_builder` 建注册表 → `candidate_generator` 按输入/输出可衔接性生成候选 Skill 对 → `matcher`(LLM 本体匹配)判定候选对的真实数据依赖与语义相似度 → `graph_builder` 物化图谱 → `lookup_builder` 生成 score lookup(用于按需查边)。最终产出 `GraphBuildResult`,内含邻接结构、边权重与 lookup 索引。

**第三步 — 层次 tree index**。`TreeBuilder.build_tree` 把 catalog 记录组织为多级层次 tree,并产出 HTML 预览,方便人工审阅 Skill 拓扑。

**第四步 — Score 产物落盘**。把上述结果合并写入 Score 产物目录:`graph.json`、`catalog`、`tree index`、`retriever index`、`score lookup`,并通过 `score_status` 记录冻结点(技能数、构建时间、与 Skill 文件夹一致性),供 `ScoreStatus` 在线快速判定是否需要续建。

**第五步 — 发布**。`publish_artifact_dir` 把产物目录原子切换到在线可读路径,保证在线规划读到的永远是完整一致的 Score。

```
skills_root(rglob SKILL.md)
  → FingerprintExtractor.extract_from_root
      (parse_manifests → extract_schemas → normalize_schemas,IncrementalFingerprintStore 增量复用)
  → GraphBuilder.build
      (registry_builder → candidate_generator → matcher(LLM) → graph_builder → lookup_builder → GraphBuildResult)
  → TreeBuilder.build_tree(catalog → 层次 tree + HTML)
  → Score 产物(graph.json / catalog / tree index / retriever index / score lookup)
  → publish_artifact_dir
```

### 2. 在线规划

在线规划由 `plan_from_score` 入口承接:它先 `load_score_artifacts` 把冻结 Score 的 graph/catalog/lookup 读入内存,再 `load_dynamic_overlay` 叠加当前演化层(动态边权重),随后按 `mode` 选择策略——`fast` 走 `FastOneShotPlanner`(一次 LLM 直出,延迟低),`beam` 走 `BidirectionalBeamPlanner`(双向束束搜索,质量高)。两类规划器最终都产出一棵 Skill 执行图:节点 = Skill,边 = 数据依赖,边权重 = 置信度(图谱静态) + 演化(动态叠加)。`WorkerCIDConverters` 在此处把编排图的节点 CID 与执行端 worker_id 互转,保证"规划图"与"执行身份"对齐。

### 3. 演化闭环

演化的输入是"执行结果",输出是"更准的边权重",闭环如下:执行引擎跑完 plan 后调用 `record_plan_outcome`,追加一条事件(成功/失败、耗时、产出质量);`rebuild_dynamic_overlay` 内部经 `build_overlay_from_events` 重新计算各边权重并 `write_overlay` 持久化;下一次 `plan_from_score` 调用 `load_dynamic_overlay` 即读到更新后的叠加层,从而"越用越准"。与演化并行的是经验侧:`ExperienceBank` 基于 FAISS 收集执行轨迹向量并支持相似检索,`EvaluationAccumulator` 按 success_rate / latency / accuracy / completeness / compliance 五维度聚合为 `QualityResult`,为演化权重提供量化信号。演化更新冻结图谱之上的"叠加层",而非改写图谱本身——这一分层使"稳定基线 + 持续学习"互不干扰。

```
执行 plan → record_plan_outcome(追加事件)
        → rebuild_dynamic_overlay(build_overlay_from_events → write_overlay)
        → 下次 plan_from_score(load_dynamic_overlay 读到更新) → 越用越准
并行:ExperienceBank(FAISS)收集轨迹 + EvaluationAccumulator 聚合五指标
```

### 4. 增量指纹与续建判定

`IncrementalFingerprintStore` 以文件哈希为粒度做增量:对每个 Skill 目录计算内容指纹(含 `SKILL.md` 与 schema 文件),与上次冻结点比对,未变项直接复用旧指纹,只对变更/新增项重跑 `extract_schemas` 与 `normalize_schemas`。`score_status` 在构建前先被调用,产出 `ScoreStatus`——一个冻结 dataclass,字段描述 Score 是否存在、是否陈旧、是否可续建以及当前技能计数。当 `ScoreStatus.stale` 为真但 `can_rebuild` 也为真时,走增量续建路径;只有当 Skill 集结构发生破坏性变更(如大量删除)时才触发全量重建。这一机制让"改一个 Skill 不必重建整张图谱"成为常态,是 Symphony 在数百 Skill 规模下仍可快速迭代的基础。

### 5. LLM 本体匹配器

`matcher` 是图谱质量的"裁判":它接收 `candidate_generator` 产出的候选 Skill 对(A 的输出可能喂给 B),用 LLM 做本体级判断——不仅看类型能否对接,还判断语义上是否真有数据依赖、是否存在更优替代。匹配结果带置信度,作为图谱边的静态权重。为控制成本与抖动,matcher 做了批量调度与结果缓存,同一候选对不会重复请求 LLM;匹配结果还会经 `validation` 做一致性校验(避免自环、重复边、断裂依赖),保证物化出的图谱是 DAG 友好的可编排拓扑。

### 6. 经验库与五维评估

经验侧由四件套组成:`collector` 从执行轨迹中收集原始经验(包含 plan 拓扑、输入输出、耗时、成败),`embed` 把经验文本向量化,`bank`(ExperienceBank)基于 FAISS 存储并支持近似检索,`retriever` 在线查相似经验喂给规划器做提示。评估侧 `EvaluationAccumulator` 按对象身份(Skill / 边 / plan)聚合五指标:`success_rate`(成功率)、`latency`(延迟)、`accuracy`(产出准确度)、`completeness`(完整性)、`compliance`(合规性),聚合为 `QualityResult`。这五维既是演化的输入信号,也是人工审阅 Score 健康度的仪表盘,使"越用越准"可被量化追踪而非黑箱。

### 7. CID↔worker_id 对齐

编排图用的是逻辑身份 CID(规划层抽象),执行端用的是物理 worker_id(具体执行器)。`build_worker_cid_converters` 在规划产出后构建双向映射表,`WorkerCIDConverters` 提供 `cid_to_worker` / `worker_to_cid` 两个方向查询。这一对齐保证"规划图里的某节点"在执行时能被准确路由到对应 worker,且执行结果回传时能被 `record_plan_outcome` 正确归因到原 CID——否则演化层会因身份错配而写错边权重,破坏"越用越准"的前提。

### 8. 检索产物加载与 LLM 工厂

在线规划与检索都依赖把 Score 产物读回内存。`load_retriever_index` 负责加载 retriever index 与 `CatalogRecord` 列表,二者共同构成"按需查 Skill"的快速通道:catalog 给元数据(skill_id、display_name、IO 摘要),retriever index 给向量或倒排结构。`retrieval/llm/factory.py` 则按配置(vllm / openai_api / transformers prefix-cached 等)实例化检索用的 LLM,使检索阶段的 embedding 与重排可插拔,且不与图谱构建期 matcher 共享同一 LLM 实例,避免构建期与在线期互相影响、互相拖慢。

### 9. tree index 与 HTML 预览

`TreeBuilder.build_tree` 把扁平的 catalog 组织为多级层次 tree:先按领域/分类归并,再按 IO 衔接关系建子树,最终既产出供程序消费的 tree index,也产出供人审阅的 HTML 预览。HTML 预览是 Symphony 的"人工审阅窗口"——开发者可在构建后直接打开,检查 Skill 是否被错分、是否存在孤立节点或断裂依赖,从而在演化介入之前就发现图谱质量问题,降低"坏基线被叠加层放大"的风险。

### 10. 配置中枢 SymphonyConfig

`SymphonyConfig` 是顶层配置 dataclass,字段覆盖 `paths`(skill 根目录、产物目录)、`fingerprint`(增量策略、force)、`build`(是否发布、并发度)、`evolution`(叠加层路径、重建策略)、`orchestration`(默认 mode、planner 参数)。`load_symphony_config` 从 `config.yaml` 读取并归一化,补全默认值,使构建、规划、演化三态共享同一份配置源,避免多入口配置漂移导致"构建期与在线期读到不同参数"的隐蔽 bug。

## 四、调用示例

离线构建一份 Score(模块级便捷函数,典型 CLI 入口):

```python
import asyncio
from jiuwenswarm.symphony.build import build_score, score_status
from jiuwenswarm.symphony.config import load_symphony_config

async def main() -> None:
    config = load_symphony_config("config.yaml")          # 归一化顶层配置
    status = score_status(config)                          # 先查是否可续建
    print(status.exists, status.stale, status.skill_count)
    await build_score(config)                              # 增量构建并发布

asyncio.run(main())
```

在线规划:把自然语言 query 解析为 Skill 执行图:

```python
from jiuwenswarm.symphony.orchestration.service import plan_from_score
from jiuwenswarm.symphony.models.cid.converters import build_worker_cid_converters

async def plan(query: str):
    exec_graph = await plan_from_score(
        query=query,
        mode="beam",                       # fast | beam
    )                                      # 内部 load_score_artifacts + load_dynamic_overlay
    converters = build_worker_cid_converters(exec_graph)
    for node in exec_graph.nodes:
        worker_id = converters.cid_to_worker(node.cid)   # CID ↔ worker_id 对齐
        print(node.skill, "→", worker_id, "deps:", node.deps)
```

演化闭环:执行后回写结果,触发叠加层重建:

```python
from jiuwenswarm.symphony.evolution.service import (
    record_plan_outcome, rebuild_dynamic_overlay, load_dynamic_overlay,
)

async def after_run(plan_id: str, success: bool, latency_ms: int):
    await record_plan_outcome(            # 追加事件
        plan_id=plan_id, success=success, latency_ms=latency_ms,
    )
    await rebuild_dynamic_overlay()        # 重建并持久化边权重
    overlay = await load_dynamic_overlay()  # 下次规划即读到新权重
    print("overlay edges updated:", len(overlay.edge_weights))
```

经验检索与五维评估(配合 ExperienceBank + EvaluationAccumulator):

```python
from jiuwenswarm.symphony.experience.bank import ExperienceBank
from jiuwenswarm.symphony.evaluation.suite import EvaluationAccumulator

async def review(plan_id: str):
    bank = ExperienceBank.load()
    traces = await bank.search_similar(query_vec, k=5)   # FAISS 近似检索
    acc = EvaluationAccumulator()
    for t in traces:
        acc.ingest(t)                      # 按对象身份聚合
    quality = acc.aggregate()              # → QualityResult
    print(quality.success_rate, quality.latency, quality.accuracy,
          quality.completeness, quality.compliance)
```

检索产物加载与 LLM 工厂(在线检索侧,配合 `load_retriever_index` 与 `build_retrieval_llm`):

```python
from jiuwenswarm.symphony.retrieval.io.loading import (
    load_retriever_index, CatalogRecord,
)
from jiuwenswarm.symphony.retrieval.llm.factory import build_retrieval_llm

async def load_and_query(artifact_dir: str):
    index, records = load_retriever_index(artifact_dir)  # retriever index + CatalogRecord
    llm = build_retrieval_llm(config)                    # vllm / openai / transformers
    for rec in records[:3]:                              # CatalogRecord 元数据
        print(rec.skill_id, rec.display_name, rec.io_summary)
    hits = await index.search(query_vec, k=5)            # 近邻检索
    return hits, llm
```

续建决策与强制重建(基于 `ScoreStatus`,典型运维场景):

```python
from jiuwenswarm.symphony.build import build_score, score_status

async def maintain(config, force: bool = False) -> None:
    status = score_status(config)                  # 查 Score 是否存在/陈旧
    if not force and not status.stale:
        print("score fresh, skip; skills =", status.skill_count)
        return
    if status.stale and status.can_rebuild:        # 增量续建
        print("incremental rebuild...")
    else:                                          # 全量重建
        print("full rebuild...")
    await build_score(config)                      # 发布新冻结点
```

## 五、业界对比

| 能力维度 | JiuwenSwarm(Symphony) | LlamaIndex | LangGraph | DSPy |
| --- | --- | --- | --- | --- |
| 知识建模 | Skill 指纹 + LLM 本体匹配知识图谱 | 文档/节点索引检索 | 显式图(StateGraph) | 无显式图谱 |
| 规划策略 | fast/beam 双策略,边权重 = 置信度 + 演化 | 检索 top-k 拼接 | 人工定义节点/边 | 自动 prompt 优化 |
| 自演化 | 事件日志 → 动态叠加层,边权重持续更新 | 无 | 无 | 编译期优化,非运行期 |
| 评估指标 | 五维聚合(success/latency/accuracy/completeness/compliance) | 无内置 | 无内置 | 评估驱动编译 |
| 增量构建 | IncrementalFingerprintStore 文件哈希级增量 | 重建索引 | 不适用 | 不适用 |
| 产物形态 | 冻结 Score(graph/catalog/tree/lookup)+ 动态 overlay | 索引/向量库 | 运行图 | 编译后模块 |

Symphony 的独特之处在于把"知识图谱(冻结基线)+ 动态叠加层(运行期演化)+ 经验库(FAISS)+ 五维评估"组合成一个自学习闭环:规划不只依赖静态拓扑,还会被历史成败塑形,且基线与学习分层互不污染。LlamaIndex 停在"检索拼接",LangGraph 的图是人工写死的运行时编排而非可学习的知识,DSPy 的优化发生在编译期且针对 prompt 而非 Skill 拓扑——三者都缺少"运行期边权重自我更新"这一环。Symphony 用 overlay 叠加层的取舍,在"稳定可复现"与"持续学习"之间找到平衡:基线保证规划可复现、可审计,叠加层保证越用越准、不腐化。

Symphony 的关键工程取舍可归纳为:

- 知识分两层:冻结图谱(基线)+ 动态 overlay(演化),改一不改另一,互不污染。
- 规划双策略:`fast` 牺牲质量换延迟,`beam` 牺牲延迟换质量,按场景与 SLA 选择。
- 增量优先:`IncrementalFingerprintStore` 让改一个 Skill 不必重建整张图谱。
- 演化只读不改基线:`record_plan_outcome` 只写 overlay,绝不动 `graph.json`。
- 评估可量化:五维聚合使"越用越准"可被追踪而非黑箱调参。
- 身份对齐:`WorkerCIDConverters` 保证规划身份与执行身份一致,演化归因不错位。

## 六、小结

1. Symphony 是"离线 Score 构建 + 在线规划"双态引擎,Score 是冻结的 Skill 知识快照,overlay 是运行期演化的动态叠加层,二者分层互不污染。
2. 离线流水线五步走(指纹→图谱→tree index→产物→发布),`IncrementalFingerprintStore` 提供文件哈希级增量,`score_status`/`ScoreStatus` 支撑续建判定,使大规模 Skill 集重构建可控。
3. 在线 `plan_from_score` 支持 fast / beam 双策略,执行图节点 = Skill、边 = 数据依赖、权重 = 置信度 + 演化;`WorkerCIDConverters` 保证规划身份与执行身份对齐。
4. 演化闭环"执行→record_plan_outcome→rebuild_dynamic_overlay→下次规划读到新权重"使知识图谱越用越准,且只改叠加层、不动冻结基线。
5. `EvaluationAccumulator` 五维聚合与 `ExperienceBank`(FAISS)经验库为演化提供量化信号,使"越用越准"可被追踪;matcher 的本体匹配与 validation 保证图谱是可编排的健壮拓扑。
