# 记忆系统

> 交叉引用: [01-项目概述](../01-project-overview.md) | [02-整体架构](../02-overall-architecture.md) | [03-agents与swarm](../03-agents-and-swarm-module.md) | [06-symphony](../06-symphony-module.md) | [特性索引](README.md)

## 一、能力概述

JiuwenSwarm 的记忆系统并非单一存储,而是按"记忆类型 + 检索方式"组织成多层结构,以适配 Agent 在不同场景下对上下文的不同诉求。系统提供三类记忆:

- **自动记忆**:对话过程中自动写入记忆库,无需显式调用,Agent 据此积累跨会话的长期上下文。
- **编码记忆(Code Memory)**:绑定到 code workspace 的持久化记忆,以项目为隔离粒度,跨子 Agent 复用同一份编码上下文(依赖、约定、既有决策),使代码子 Agent 与主 Agent 共享同一记忆基座。
- **任务记忆**:todo/team 级记忆,服务于团队协作与待办跟踪,记录任务级状态与协作上下文。

在检索侧,自动记忆与编码记忆基于 embedding 索引(BM25 + 向量双路召回),通过 `MemoryIndexManager` 管理 SQLite 向量表与 FTS 表。此外,Symphony 子系统提供独立的"经验库"——`ExperienceBank` 基于 FAISS 收集 Agent 执行轨迹,经 `TraceDistiller` 蒸馏为可复用经验,再由 `EmbeddingClient` 生成 embedding、`ExperienceRetriever` 检索,形成"轨迹→蒸馏→索引→检索"的经验闭环。

这套设计的关键在于:记忆不是平铺的全局存储,而是按用途分层——对话记忆服务人格连续性,编码记忆服务工程一致性,任务记忆服务协作状态,经验库服务能力自演进。每一层都有独立的写入触发、隔离粒度与检索路径。

## 二、关键类与函数

| 类/函数 | 文件位置 | 说明 |
| --- | --- | --- |
| MemoryIndexManager | [manager.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/common/memory/manager.py#L56) | 记忆管理器:SQLite 向量表+FTS 表,BM25/向量双路召回 |
| resolve_coding_memory_project_name | [coding_memory_paths.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/coding_memory_paths.py#L14) | 解析 code workspace→项目隔离目录名 |
| resolve_project_coding_memory_dir | [coding_memory_paths.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/coding_memory_paths.py#L30) | 返回项目编码记忆根目录 |
| get_agent_memory_dir | [utils.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/utils.py#L1484) | Agent 记忆目录解析 |
| build_code_agent | [code_subagents.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/providers/code_subagents.py#L93) | 构建代码子 Agent,复用主 Agent 的 CodingMemoryRail(从 ctx.extras 取) |
| ExperienceBank | [bank.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/experience/bank.py#L95) | FAISS 经验存储:add_trace/search_by_embedding/search_with_skill_ids |
| EmbeddingClient | [embed.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/experience/embed.py#L10) | 经验 embedding:embed/embed_batch |
| ExperienceRetriever | [retriever.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/experience/retriever.py#L6) | 经验检索器:search(query)→经验文本列表 |
| TraceDistiller | [distiller.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/symphony/experience/distiller.py#L65) | 经验蒸馏器:把执行轨迹提炼为可复用经验 |

## 三、实现机制

### 3.1 自动记忆:对话自动写入与双路召回

自动记忆在对话流转过程中由 `MemoryIndexManager` 自动触发写入。其底层由 SQLite 承载两类表:`chunks_vec`(向量表,用于语义召回)与 `chunks_fts`(FTS5 全文表,用于 BM25 关键词召回)。检索时双路并行召回再融合排序,兼顾语义相似与字面匹配。`INDEX_CACHE` 以记忆路径为键缓存 `MemoryIndexManager` 实例,避免重复初始化;`SessionDeltaState` 跟踪会话文件的增量变化,以 5000ms 防抖触发增量索引,降低写入开销。

### 3.2 编码记忆:CodingMemoryRail 跨子 Agent 复用

编码记忆绑定到 code workspace,以项目为隔离粒度。`resolve_coding_memory_project_name` 把 workspace 路径规范化为目录名(空/非法值回退 `default`),`resolve_project_coding_memory_dir` 拼出记忆根目录,从而保证不同项目的编码上下文互不污染。

关键的复用机制在于 `build_code_agent`:构建代码子 Agent 时,它不新建独立的记忆轨,而是从 `ctx.extras` 取出主 Agent 已绑定的 `CodingMemoryRail` 并注入子 Agent。这意味着主 Agent 与所有代码子 Agent 共享同一份编码记忆——依赖清单、代码约定、既有架构决策在 Swarm 协作中跨成员一致,避免子 Agent "各记各的"导致上下文撕裂。

### 3.3 任务记忆:todo/team 级状态

任务记忆服务于团队协作与待办跟踪,记录 todo/team 级状态与协作上下文,与 cron 团队轮次状态机(见 [cron_team_completion](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/cron_team_completion.py#L117))配合,判断团队轮次何时结束。任务记忆使团队在多轮协作中保持对"待办、分工、阶段产物"的连续认知。

### 3.4 Symphony 经验库:轨迹→蒸馏→索引→检索

Symphony 子系统的经验库构成独立闭环:

```text
[1] 收集轨迹:ExperienceBank.add_trace 收集 Agent 执行轨迹
       └─ 成功/失败路径、工具调用序列
[2] 蒸馏经验:TraceDistiller 把原始轨迹提炼为可复用经验条目
       └─ 去除噪声、提取可迁移模式
[3] 生成 embedding:EmbeddingClient.embed / embed_batch 生成向量
[4] 构建索引:_build_faiss_index 基于 FAISS 构建向量索引
       └─ _Knowledge_meta 记录元信息,_write_atomic 原子写入
[5] 检索复用:search_by_embedding / search_with_skill_ids 召回
       └─ ExperienceRetriever.search 暴露面向 Agent 的检索接口
```

这套闭环使 Agent 的"做过什么、学到了什么"被沉淀为可检索资产,驱动技能自演进。经验库独立于对话/编码/任务记忆走 FAISS,而非复用 SQLite,是因为经验条目更接近"知识库"语义,向量近邻检索是其主要访问模式。

### 3.5 记忆分层对照

| 记忆层 | 写入触发 | 隔离粒度 | 检索路径 | 索引后端 |
| --- | --- | --- | --- | --- |
| 自动记忆 | 对话自动写入 | 会话/用户 | BM25+向量双路 | SQLite |
| 编码记忆 | code workspace 持久 | 项目目录 | CodingMemoryRail 共享 | SQLite |
| 任务记忆 | todo/team 事件 | 团队/任务 | 状态机查询 | 结构化状态 |
| 经验库 | 轨迹收集 | 全局/技能 | 向量近邻召回 | FAISS |

### 3.6 记忆在 Agent 单轮中的协同

四层记忆在一次 Agent 执行中的典型协同时序:

```text
[1] 请求进入,resolve_project_coding_memory_dir 取编码记忆根目录
[2] ExperienceRetriever.search 召回相似经验,注入系统提示
[3] Agent 执行工具调用,产出内容(可能含 A2UI 富交互)
[4] 对话内容自动写入自动记忆(MemoryIndexManager 增量索引)
[5] 编码变更经 CodingMemoryRail 写入项目编码记忆(跨子 Agent 共享)
[6] 团队事件更新任务记忆,apply_cron_team_round_event 推进状态机
[7] 执行轨迹经 ExperienceBank.add_trace 收集,供 TraceDistiller 蒸馏
```

这一时序体现了四层记忆的分工:经验库与编码记忆在执行前提供上下文,自动记忆与编码记忆在执行中写入,任务记忆在协作中推进,经验库在执行后收集轨迹——形成"读→用→写→蒸馏"的完整闭环,使记忆不止于存储,而成为驱动 Agent 持续改进的活资产。

## 四、调用示例

### 4.1 解析编码记忆目录(项目隔离)

```python
# 1. 解析 code workspace 的编码记忆目录(项目隔离)
from jiuwenswarm.common.coding_memory_paths import (
    resolve_coding_memory_project_name,
    resolve_project_coding_memory_dir,
)
proj = resolve_coding_memory_project_name("/home/me/myrepo")
mem_dir = resolve_project_coding_memory_dir(proj)  # 编码记忆根目录
# 不同项目隔离,空/非法值回退 default
```

### 4.2 构建代码子 Agent 并共享编码记忆

```python
# 2. 构建代码子 Agent:复用主 Agent 的 CodingMemoryRail(经 ctx.extras)
from jiuwenswarm.agents.swarm.providers.code_subagents import build_code_agent
code_agent = build_code_agent(factory_kwargs, ctx)
# ctx.extras 已注入主 Agent 的 CodingMemoryRail
# 子 Agent 与主 Agent 共享同一份编码记忆,跨成员一致
```

### 4.3 经验检索注入上下文

```python
# 3. 经验检索:Agent 执行前召回相似经验注入上下文
from jiuwenswarm.symphony.experience.retriever import ExperienceRetriever
retriever = ExperienceRetriever(...)
hits = retriever.search("如何处理飞书消息批量回填")
# hits 为经验文本列表,注入 Agent 系统提示
```

### 4.4 记忆在 Agent 单轮中的协同调用

```python
# 4. 执行前召回经验,执行中写入,执行后收集轨迹,形成闭环
hits = retriever.search(query)              # 经验库:读
# ... Agent 执行,产出内容(可能含 A2UI 富交互) ...
manager.index_session_delta(session_path)   # 自动记忆:写
bank.add_trace(trace_record)                # 经验库:收集,待蒸馏
```

## 五、业界对比

| 维度 | JiuwenSwarm | Mem0 | LangChain memory | Zep |
| --- | --- | --- | --- | --- |
| 记忆类型 | 自动/编码/任务 + 经验库四层 | 单一记忆层 | 对话/摘要/向量 | 长期记忆图 |
| 索引检索 | BM25+向量双路召回(SQLite) | 向量召回 | 取决于 VectorStore 实现 | 图+向量 |
| 跨 Agent 复用 | CodingMemoryRail 经 ctx.extras 跨子 Agent 共享 | 无 | 无 | 无 |
| 经验蒸馏 | TraceDistiller 轨迹→经验闭环 | 无 | 无 | 无 |
| 项目隔离 | workspace→项目目录隔离 | 用户隔离 | 取决于实现 | 会话隔离 |

JiuwenSwarm 的差异化在于"分层 + 蒸馏":记忆不是单一存储,而是按用途分层(对话/编码/任务/经验),每层有独立写入触发与隔离粒度;经验库独有的"轨迹→蒸馏→索引→检索"闭环把 Agent 执行历史转化为可检索资产,这是多数记忆方案缺失的能力。编码记忆经 `CodingMemoryRail` 在 Swarm 中跨子 Agent 共享,则保证了工程上下文在团队协作中的一致性。

## 六、小结

1. JiuwenSwarm 记忆系统的核心是"按用途分层、按场景隔离、按经验自演进",提供自动/编码/任务三类记忆加 Symphony 经验库共四层。
2. 自动记忆服务人格连续性,经 `MemoryIndexManager` 的 SQLite BM25+向量双路召回,对话自动写入、增量防抖索引。
3. 编码记忆服务工程一致性,以项目为隔离粒度,经 `CodingMemoryRail` 在 Swarm 中跨子 Agent 共享(经 `ctx.extras` 注入)。
4. 任务记忆服务协作状态,与 `cron_team_completion` 状态机配合判断团队轮次收束。
5. Symphony 经验库经 `ExperienceBank`/`TraceDistiller`/`EmbeddingClient`/`ExperienceRetriever` 构成"轨迹→蒸馏→索引→检索"闭环,独立走 FAISS,驱动技能自演进。
6. 相对 Mem0/LangChain memory/Zep,本特性以"分层 + 蒸馏 + 跨 Agent 复用"形成差异化,使记忆成为可演进资产而非单一存储。
