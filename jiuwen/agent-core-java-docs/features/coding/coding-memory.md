# 编码记忆

> 交叉引用: [01-project-overview](../../01-project-overview.md) | [02-overall-architecture](../../02-overall-architecture.md) | [04-harness-and-deepagents-module](../../04-harness-and-deepagents-module.md) | [06-agentevolving-and-autoharness-module](../../06-agentevolving-and-autoharness-module.md)

## 一、能力概述

agent-core-java 的编码记忆能力**部分实现**。已落地的部分是:一个编码专属记忆 Rail(CodingMemoryRail,优先级 80、sectionName=`coding_memory`)、三个独立工具(`coding_memory_read / coding_memory_write / coding_memory_edit`)、以及基于 MEMORY.md 静态索引的提示注入(beforeModelCall 每次模型调用前读 MEMORY.md 前 200 行注入提示)。这一部分与编码代理作用域隔离:CodeAgentFactory 在装配 code_agent 时通过 buildCodingMemoryRail 注入该 Rail,使编码代理拥有独立的 `.md` 记忆区,与通用记忆区分。

**关键差距(未接入)**:Python 版 CodingMemoryRail 在每个 user turn 通过向量 + BM25 混合检索召回 top5 记忆并注入提示;Java 版的 `beforeModelCall` **只读 MEMORY.md 静态索引文件,不调用向量检索**,`toolNames()` 也不含 `memory_search`(不暴露向量检索工具)。代码库中已存在 BM25/向量基础设施(`LiteMemoryInternal.bm25RankToScore`、`MemorySettings.hybrid` enabled=true/vectorWeight=0.7/textWeight=0.3),但这些由通用 `MemoryRail.memory_search` 使用,**未被 CodingMemoryRail 接入**。CodingMemoryToolContext 虽接收 EmbeddingConfig,但仅用于写入时的索引同步,不用于每 user turn 的 top5 召回。

> 本篇如实描述已实现与未接入两部分,不臆造能力。当前 Java 版的"记忆召回"退化为"读静态索引文件",语义相关性弱于 Python 版,这是明确的待补齐项。

## 二、关键类与函数

| 类/函数 | 职责 | 源码位置 |
|---------|------|----------|
| CodingMemoryRail | 编码记忆 Rail(extends MemoryRail,优先级 80) | [CodingMemoryRail.java#L33](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/CodingMemoryRail.java#L33) |
| priority | Rail 优先级,固定 80 | [CodingMemoryRail.java#L67](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/CodingMemoryRail.java#L67) |
| sectionName | 返回 `"coding_memory"` | [CodingMemoryRail.java#L78](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/CodingMemoryRail.java#L78) |
| toolNames | 返回 3 个工具名(不含 memory_search) | [CodingMemoryRail.java#L90](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/CodingMemoryRail.java#L90) |
| createToolContext | 构造 CodingMemoryToolContext | [CodingMemoryRail.java#L102](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/CodingMemoryRail.java#L102) |
| invokeMemoryTool | 按 toolName 分发到 3 个工具 | [CodingMemoryRail.java#L137](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/CodingMemoryRail.java#L137) |
| beforeModelCall | 模型调用前注入 MEMORY.md 静态索引提示 | [CodingMemoryRail.java#L157](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/CodingMemoryRail.java#L157) |
| readIndex | 读 MEMORY.md 前 200 行(MAX_INDEX_LINES) | [CodingMemoryRail.java#L211](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/CodingMemoryRail.java#L211) |
| codingMemoryDir | 返回编码记忆目录 | [CodingMemoryRail.java#L176](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/CodingMemoryRail.java#L176) |
| CodingMemoryToolOps | 3 工具实现 | [CodingMemoryToolOps.java](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/lite/CodingMemoryToolOps.java) |
| codingMemoryReadWithContext | 读 .md 文件行 | [CodingMemoryToolOps.java#L124](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/lite/CodingMemoryToolOps.java#L124) |
| codingMemoryWriteWithContext | 写 .md + 更新 MEMORY.md 索引 + sync | [CodingMemoryToolOps.java#L154](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/lite/CodingMemoryToolOps.java#L154) |
| codingMemoryEditWithContext | 精确 old_text/new_text 替换 | [CodingMemoryToolOps.java#L195](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/lite/CodingMemoryToolOps.java#L195) |
| CodingMemoryToolContext | 接收 EmbeddingConfig(仅用于 sync) | [CodingMemoryToolContext.java#L32](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/lite/CodingMemoryToolContext.java#L32) |
| MemoryRail.invokeMemoryTool | 通用记忆 5 工具(含 memory_search) | [MemoryRail.java#L318](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/MemoryRail.java#L318) |
| memory_search(通用) | 向量检索工具(未接入编码 Rail) | [MemoryRail.java#L322](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/MemoryRail.java#L322) |
| LiteMemoryInternal.bm25RankToScore | BM25 排名转分数基础设施 | [LiteMemoryInternal.java#L226](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/lite/LiteMemoryInternal.java#L226) |
| MemorySettings.hybrid | 混合检索配置(enabled=true, vectorWeight=0.7, textWeight=0.3) | [MemorySettings.java#L53](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/lite/MemorySettings.java#L53) |
| CodeAgentFactory.buildCodingMemoryRail | 编码代理注入记忆 Rail | [CodeAgentFactory.java#L127](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/CodeAgentFactory.java#L127) |

## 三、实现机制

### 3.1 已实现:类 + 3 工具 + MEMORY.md 索引注入

**CodingMemoryRail** [L33](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/CodingMemoryRail.java#L33) 继承自通用 `MemoryRail`,固定优先级 [80](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/CodingMemoryRail.java#L67)(与 Python 版 priority=80 对齐),sectionName 为 `coding_memory`([L78](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/CodingMemoryRail.java#L78))。它通过 [toolNames()#L90](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/CodingMemoryRail.java#L90) 暴露三个独立工具(由 [invokeMemoryTool#L137](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/CodingMemoryRail.java#L137) 分发到 [CodingMemoryToolOps](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/lite/CodingMemoryToolOps.java)):

- `coding_memory_read` → [codingMemoryReadWithContext#L124](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/lite/CodingMemoryToolOps.java#L124):按 path/offset/limit 读取 `.md` 文件行,返回 content/totalLines/start_line/end_line/truncated,先经 `validateCodingMemoryPath` 校验路径合法性;
- `coding_memory_write` → [codingMemoryWriteWithContext#L154](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/lite/CodingMemoryToolOps.java#L154):写入 `.md`(需含 frontmatter:name/description/type,先 parseFrontmatter + validateFrontmatter 校验),并 [upsertCodingMemoryIndex 更新 MEMORY.md 索引](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/lite/CodingMemoryToolOps.java#L174),随后 [L175](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/lite/CodingMemoryToolOps.java#L175) 调 `ctx.getManager().sync("coding_memory_write")` 同步索引;
- `coding_memory_edit` → [codingMemoryEditWithContext#L195](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/lite/CodingMemoryToolOps.java#L195):精确 `old_text`/`new_text` 替换,要求 old_text 非空且唯一匹配,杜绝歧义编辑。

**MEMORY.md 静态索引注入**:[beforeModelCall#L157](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/CodingMemoryRail.java#L157) 在每次模型调用前重写提示 section:移除旧 `coding_memory` section → 调用 [readIndex()#L211](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/CodingMemoryRail.java#L211) 读取 MEMORY.md 前 200 行(MAX_INDEX_LINES=200,定义在 L34)→ 拼装 `buildCodingMemoryPrompt`(L192,含 CodingMemoryPromptSections 基础提示 + 当前记忆索引)→ 以 PromptSection 形式 [addSection](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/CodingMemoryRail.java#L165) 注入,并 `injectSystemMessage`(L167)注入系统消息。这一机制让模型在每轮对话都能"看到"当前记忆索引,但索引是静态的文件内容,非语义召回。

**作用域隔离与自动注入**:[CodeAgentFactory.buildCodeAgentConfig#L121](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/CodeAgentFactory.java#L121) 在 Rails 中包含 `buildCodingMemoryRail(kwargs)`(L111-112),使编码代理拥有独立记忆区,与通用 MemoryRail 区分。[buildCodingMemoryRail](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/subagents/CodeAgentFactory.java#L127) 按 `embedding_config / coding_memory_dir / coding_memory_proactive` 构造:若 embedding_config 是 EmbeddingConfig 实例则用带参构造(L132),否则回退无参构造(L134,默认 proactive=true)。[createToolContext#L102](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/CodingMemoryRail.java#L102) 解析 codingMemoryDir(配置为空则回退到通用 memoryDir),用 MemorySettings.create 构造设置,产出 CodingMemoryToolContext。

**路径安全与索引管理**:三个工具均经 [validateCodingMemoryPath](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/lite/CodingMemoryToolOps.java#L46) 校验路径合法性——禁止目录穿越(含 `..`)、禁止绝对路径(以 `/` 开头)、强制以 `.md` 结尾、要求 workspace 的 `coding_memory` 节点已配置,最后只取文件名拼接到记忆目录,杜绝越界写入。写入与编辑后,通过 [upsertCodingMemoryIndex](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/lite/CodingMemoryToolOps.java#L72) 维护 MEMORY.md 索引:按 frontmatter 的 name/description 生成 `- [name](filename) — description` 条目,按 filename 去重(已存在则替换,不存在则插入首行),并截断至 MAX_INDEX_LINES=200 行。另有 [removeFromCodingMemoryIndex](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/lite/CodingMemoryToolOps.java#L103) 按 filename 删除条目。这套索引机制保证 MEMORY.md 始终是记忆区的"目录页",供 beforeModelCall 静态注入。

**精确编辑的唯一匹配约束**:[codingMemoryEditWithContext#L195](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/lite/CodingMemoryToolOps.java#L195) 在替换前先 [count occurrences](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/lite/CodingMemoryToolOps.java#L207):0 次返回 "old_text not found",>1 次返回 "appears N times, please be more specific",仅当唯一匹配(occurrences==1)才执行替换。这一约束杜绝歧义编辑——避免模型用模糊的 old_text 误改多处,是编码记忆可信赖的关键。替换后若新内容仍含合法 frontmatter,则重新 upsertCodingMemoryIndex 保持索引同步。

**工具 I/O 语义差异**:三个工具的读写语义各有侧重,体现"追加写、分页读、精确改"的分工。读工具 [codingMemoryReadWithContext#L124](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/lite/CodingMemoryToolOps.java#L124) 采用 1-based offset(start = offset - 1)、按 limit 分页,返回 content/totalLines/start_line/end_line/truncated,truncated 标志让调用方知晓是否还有后续内容,适合大记忆文件的渐进式阅读。写工具 [codingMemoryWriteWithContext#L154](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/lite/CodingMemoryToolOps.java#L154) 使用 [CREATE + APPEND](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/lite/CodingMemoryToolOps.java#L172) 打开选项——即对同一文件重复写入是**追加**而非覆盖,返回 appended=true 与 fileExisted 标志,适合"在同一记忆文件持续累积条目"的用法;写入前强制 [parseFrontmatter + validateFrontmatter](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/lite/CodingMemoryToolOps.java#L160) 校验 name/description/type 三字段,不合法则拒绝写入。编辑工具则在追加写之外提供"精确改"能力,用唯一匹配约束保证安全。三者协同:读做检索、写做累积、编辑做修订,配合索引管理形成完整的记忆生命周期。

### 3.2 未接入:向量 + BM25 混合检索 per-turn top5 召回

**关键差距**:Python 版 CodingMemoryRail(priority=80)在每个 user turn 通过向量 + BM25 混合检索召回 top5 记忆并注入提示;Java 版**未实现这一召回**,具体表现为四点:

1. **beforeModelCall 只读静态索引**:[CodingMemoryRail.beforeModelCall#L157](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/CodingMemoryRail.java#L157) 仅调用 `readIndex()` 读 MEMORY.md 文件前 200 行,**不调用任何向量检索**;召回是"读整个索引文件"而非"按当前 query 语义相关性 top5 召回"。当记忆文件增多后,前 200 行静态注入既无法保证相关性,也无法覆盖全部记忆。
2. **不暴露向量检索工具**:[toolNames()#L90](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/CodingMemoryRail.java#L90) 只返回 3 个 `.md` 文件读写工具,不含 `memory_search`。对比通用 [MemoryRail.invokeMemoryTool#L318](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/MemoryRail.java#L318),其暴露 `memory_search`(向量检索,L322)、`memory_get`、`read_memory`、`write_memory`、`edit_memory` 五工具;CodingMemoryRail 虽继承 MemoryRail,但 [invokeMemoryTool#L137](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/CodingMemoryRail.java#L137) 重写为只分发 3 个编码专属工具,**未继承 memory_search 暴露**。
3. **基础设施存在但未接入**:代码库已具备混合检索能力 — [LiteMemoryInternal.bm25RankToScore#L226](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/lite/LiteMemoryInternal.java#L226) 提供 BM25 排名转分数;[MemorySettings.hybrid#L53](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/lite/MemorySettings.java#L53) 默认 `enabled=true / vectorWeight=0.7 / textWeight=0.3 / candidateMultiplier=2.0`。但这些由通用 MemoryRail 使用,**CodingMemoryRail 未接入**——既未在 beforeModelCall 调用混合检索,也未在 toolNames 暴露 memory_search。
4. **EmbeddingConfig 仅用于 sync**:[CodingMemoryToolContext#L32](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/lite/CodingMemoryToolContext.java#L32) 虽接收 EmbeddingConfig,但 [codingMemoryWriteWithContext#L175](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/lite/CodingMemoryToolOps.java#L175) 仅在写入后用其做 `ctx.getManager().sync("coding_memory_write")` 索引同步,**不用于每 user turn 的 top5 召回**。EmbeddingConfig 在 CodingMemoryRail 中处于"持有但未用于召回"的状态——这与 proactive 标志的语义相关:[CodingMemoryRail 构造器#L55](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/CodingMemoryRail.java#L55) 接收 `isProactive` 并传给 `super(embeddingConfig, isProactive)`(L56),proactive 控制的是"是否主动注入提示",而非"是否做向量召回";即便 proactive=true,注入的也只是 [readIndex()](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/CodingMemoryRail.java#L211) 读出的静态索引,并非语义召回结果。

> 结论:Java 版编码记忆是"文件型记忆 + 静态索引注入",而非 Python 版的"向量 + BM25 混合检索 per-turn 召回"。前者保证记忆可持久化(.md 文件)、可精确编辑(old_text/new_text 唯一匹配)、可在每轮注入当前索引;后者保证按当前 query 语义召回最相关记忆。当前 Java 版缺后者,语义相关性弱于 Python 版。这一差距在记忆条目较少时不明显(前 200 行索引足以覆盖),但随着记忆累积,静态索引注入的"无关记忆占上下文、相关记忆未被注入"问题会逐步放大,削弱记忆的实用价值。后续若要对齐,需在 CodingMemoryRail.beforeModelCall 中接入混合检索(复用 LiteMemoryInternal.bm25RankToScore + MemorySettings.hybrid),并改 toolNames 暴露 memory_search,使 CodingMemoryToolContext 持有的 EmbeddingConfig 真正用于 per-turn top5 召回。

## 四、调用示例

```java
import com.openjiuwen.harness.subagents.CodeAgentFactory;
import com.openjiuwen.harness.subagents.SubAgentConfig;
import com.openjiuwen.harness.rails.CodingMemoryRail;
import com.openjiuwen.core.foundation.store.base_embedding.EmbeddingConfig;
import com.openjiuwen.harness.deep_agent.DeepAgent;
import com.openjiuwen.harness.factory.HarnessFactory;
import java.util.Map;

// 1) 装配编码代理时自动注入 CodingMemory Rail
//    (需传 embedding_config 才能启用 proactive 模式, 但 embedding_config 仅用于写入后 sync 索引, 不用于 per-turn 召回)
Map<String, Object> kwargs = Map.of(
        "embedding_config", embeddingConfig,            // 仅用于写入后 sync 索引, 不用于 per-turn 召回
        "coding_memory_dir", "/data/agents/coding_mem",  // 独立记忆目录, 与通用记忆隔离
        "coding_memory_proactive", true);
SubAgentConfig codeSpec = CodeAgentFactory.buildCodeAgentConfig("cn", kwargs);
DeepAgent codeAgent = HarnessFactory.createDeepAgent(
        codeSpec.getAgentCard(), codeSpec.toDeepAgentConfig(), workspace);

// 2) 模型在编码过程中可调用 3 个工具读写记忆
//    coding_memory_write: 写 .md(含 frontmatter: name/description/type) + 更新 MEMORY.md 索引 + sync
//    coding_memory_read:  按 path/offset/limit 读, 返回 content/totalLines/start_line/end_line/truncated
//    coding_memory_edit:  old_text/new_text 精确替换(唯一匹配, 非空校验)

// 3) 每轮模型调用前, beforeModelCall 注入 MEMORY.md 前 200 行静态索引(MAX_INDEX_LINES=200)
//    注意: 当前 Java 版的"召回"=读静态索引文件, 非按语义相关性 top5 召回

// 4) 关键差距: 当前 Java 版未暴露 memory_search, 也未在 beforeModelCall 做向量+BM25 召回
//    若需 per-turn 召回对齐 Python 版, 需扩展 CodingMemoryRail.beforeModelCall 接入混合检索
//    (复用 LiteMemoryInternal.bm25RankToScore + MemorySettings.hybrid: vectorWeight=0.7/textWeight=0.3)
//    并改 toolNames 暴露 memory_search
```

## 五、业界对比

| 维度 | agent-core-java | Spring AI | LangChain4j | Python agent-core |
|------|-----------------|-----------|-------------|-------------------|
| 编码专属记忆区 | ✅ CodingMemoryRail + 独立目录,作用域隔离 | ❌ 无内置 | ❌ 无内置 | ✅ 同(对齐源) |
| 向量+BM25 混合检索 | ⚠️ 基础设施存在,**未接入编码 Rail** | ⚠️ 需自建 | ⚠️ 需自建 | ✅ 已接入 per-turn 召回 |
| 跨会话召回 | ⚠️ 仅静态索引注入,**无语义召回** | ❌ | ⚠️ 需自建 | ✅ 跨会话 top5 召回 |
| 作用域隔离 | ✅ 编码 Rail 与通用 MemoryRail 分离 | ❌ | ❌ | ✅ 同 |
| 自动注入工具 | ✅ CodeAgentFactory 自动注入 3 工具 | ❌ | ❌ | ✅ 同 |
| 索引注入 | ✅ beforeModelCall 注入 MEMORY.md 前 200 行 | ❌ | ❌ | ✅ 同(且叠加向量召回) |
| 精确编辑(唯一匹配) | ✅ old_text/new_text 计数唯一匹配 | ❌ | ❌ | ✅ 同 |
| frontmatter 校验 | ✅ name/description/type 强制 | ❌ | ❌ | ✅ 同 |

## 六、小结

agent-core-java 的编码记忆能力是**部分实现**:已实现"编码专属记忆 Rail(CodingMemoryRail,优先级 80,继承 MemoryRail)+ 3 个 .md 读写工具(coding_memory_read/write/edit,含 frontmatter 校验与唯一匹配精确编辑)+ MEMORY.md 静态索引注入(beforeModelCall 注入前 200 行)+ 作用域隔离(编码 Rail 与通用 MemoryRail 分离)+ CodeAgentFactory 自动注入",保证了记忆可持久化、可精确编辑、可在每轮模型调用前注入当前索引;**未接入**的是 Python 版的"向量 + BM25 混合检索 per-turn top5 召回"——基础设施([LiteMemoryInternal.bm25RankToScore](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/lite/LiteMemoryInternal.java#L226)、[MemorySettings.hybrid](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/memory/lite/MemorySettings.java#L53) enabled=true/vectorWeight=0.7/textWeight=0.3、EmbeddingConfig)已存在于代码库并由通用 [MemoryRail.memory_search](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/MemoryRail.java#L322) 使用,但 CodingMemoryRail 既未在 beforeModelCall 调用向量检索,也未在 toolNames 暴露 memory_search,EmbeddingConfig 仅用于写入后 sync 而非召回。

因此当前 Java 版的"记忆召回"退化为"读静态索引文件",当记忆文件增多后既无法保证语义相关性,也无法覆盖全部记忆,这是与 Python 版的明确差距。后续若要对齐,需在 CodingMemoryRail.beforeModelCall 中接入混合检索并改 toolNames 暴露 memory_search,使 CodingMemoryToolContext 持有的 EmbeddingConfig 真正用于 per-turn top5 召回。

从已实现部分的价值看,文件型记忆 + 静态索引注入并非"无用",而是"够用但不智能":它保证了记忆的**持久化**(.md 文件落盘,跨会话存活)、**可审计**(MEMORY.md 是人类可读的目录页)、**可精确编辑**(唯一匹配约束杜绝误改)、**作用域隔离**(编码记忆与通用记忆分离,避免互相污染)。这些特性使编码代理能在跨会话场景下保留项目级知识(如"该仓库用 Maven 不用 Gradle""支付模块的幂等键在 IdempotencyKey 表")。只是当前的"召回"靠模型自己从 200 行索引里挑,而非靠向量+BM25 算分,召回质量取决于模型阅读索引的耐心,而非算法的相关性排序。

从差距的影响看,这一缺口在两类场景下表现不同:当记忆条目少于 200 行时,静态索引注入能覆盖全部记忆,差距不显著;当记忆条目累积到数百条后,前 200 行静态注入会出现"无关记忆占上下文、相关记忆未被注入"的问题,既浪费上下文预算,又可能误导模型。因此建议在记忆规模尚小时使用本能力,规模增大后优先补齐向量+BM25 召回链路。补齐路径已清晰:基础设施(LiteMemoryInternal.bm25RankToScore、MemorySettings.hybrid、EmbeddingConfig)均已在代码库中,只需在 CodingMemoryRail.beforeModelCall 调用混合检索、在 toolNames 增加 memory_search、让 CodingMemoryToolContext 的 EmbeddingConfig 参与召回即可。

与 Spring AI / LangChain4j 相比,二者目前均无内置编码专属记忆区,需用户自建;agent-core-java 已实现部分仍具工程化优势(独立记忆区 + 3 工具 + 索引注入 + 路径安全 + frontmatter 校验 + 唯一匹配编辑),但召回链路是明确的待补齐项,使用时需知晓这一限制,并在记忆规模增大前规划补齐方案。

为便于速查,本能力的实现状态归纳如下:

**已实现**:

- 编码专属记忆 Rail:CodingMemoryRail(优先级 80,继承 MemoryRail,sectionName=`coding_memory`);
- 3 个独立工具:coding_memory_read(分页读)/ coding_memory_write(追加写 + frontmatter 校验)/ coding_memory_edit(唯一匹配精确替换);
- MEMORY.md 静态索引注入:beforeModelCall 每轮注入前 200 行;
- 路径安全:validateCodingMemoryPath 禁目录穿越/绝对路径/非 .md;
- 索引管理:upsertCodingMemoryIndex / removeFromCodingMemoryIndex 维护目录页;
- 作用域隔离:编码 Rail 与通用 MemoryRail 分离;
- 自动注入:CodeAgentFactory.buildCodingMemoryRail 装配。

**未接入**:

- 向量 + BM25 混合检索 per-turn top5 召回(基础设施存在但未接入编码 Rail);
- memory_search 工具暴露(toolNames 不含);
- EmbeddingConfig 用于召回(当前仅用于写入后 sync)。

**演进建议**:

- 短期(记忆条目 < 200 行):直接使用现有能力,静态索引注入可覆盖全部记忆;
- 中期(记忆条目 200-500 行):考虑分目录拆分 MEMORY.md,或手动维护索引优先级;
- 长期(记忆条目 > 500 行):补齐向量+BM25 召回链路,使 beforeModelCall 按语义相关性 top5 注入。

综上,agent-core-java 的编码记忆是"文件型记忆 + 静态索引注入"的可用基线,而非"语义召回"的完整实现。前者可作为跨会话项目知识沉淀的起点,后者是走向智能召回的明确演进方向。
