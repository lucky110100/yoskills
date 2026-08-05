# 编码记忆

> 交叉引用: [01-项目概述](../../01-project-overview.md) | [02-整体架构](../../02-overall-architecture.md) | [04-harness模块](../../04-harness-module.md) | [08-依赖关系](../../08-dependencies.md)

## 一、能力概述

agent-core 的编码记忆(Coding Memory)是一条与"个人记忆(personal memory)"并行的、专属于编码场景的记忆通道。它的存在让编码代理不再每次从零开始——跨会话保留编码决策、接口约定、踩坑经验,供后续编码任务召回。其设计目标是"让代理越用越懂你的代码库"。

记忆的存储形态是独立的 `.md` 文件 + frontmatter 元数据,记忆类型涵盖 user / feedback / project / reference,覆盖"用户偏好、反馈纠正、项目约定、参考资料"四个维度。检索采用向量 + BM25 混合检索:当 `embedding_config` 提供时激活向量召回,与 BM25 关键词召回融合,在每个 user turn 自动非阻塞召回 top5,互斥注入系统提示。

数据隔离是关键:`coding_memory/` 目录与 personal `memory/` 完全隔离,工具集 `coding_memory_read / coding_memory_write / coding_memory_edit` 作用域锁定在 coding_memory 工作区目录,避免编码记忆与个人记忆串扰。启用方式极简——`CodeAgent` 的 `embedding_config` 参数即可自动激活 `CodingMemoryRail` 并注入编码记忆工具集。

## 二、关键类与函数

| 类/函数 | 文件位置 | 说明 |
| --- | --- | --- |
| CodingMemoryRail | [coding_memory_rail.py#L41](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/rails/memory/coding_memory_rail.py#L41) | priority=80,每 user turn 召回 top5 |
| CodingMemoryRail.MAX_RECALL_RESULTS | [coding_memory_rail.py#L53](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/rails/memory/coding_memory_rail.py#L53) | 召回上限 5 条,总字节 10KB |
| CodingMemoryReadTool | [coding_memory.py#L18](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/coding_memory.py#L18) | 读取记忆条目(path/offset/limit) |
| CodingMemoryWriteTool | [coding_memory.py#L42](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/coding_memory.py#L42) | 写入新记忆条目(path/content) |
| CodingMemoryEditTool | [coding_memory.py#L68](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/coding_memory.py#L68) | 编辑现有记忆条目(old_text/new_text) |
| create_coding_memory_tools | [coding_memory.py#L98-L117](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/coding_memory.py#L98) | 工厂,绑定共享运行时上下文 |
| WorkspaceNode.CODING_MEMORY | [workspace.py#L73](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/workspace/workspace.py#L73) | 工作区节点常量 `"coding_memory"` |
| DEFAULT_WORKSPACE_SCHEMA(coding_memory) | [workspace.py#L480-L493](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/workspace/workspace.py#L480) | 定义 coding_memory 节点(含 MEMORY.md 索引) |
| _resolve_coding_memory_dir | [code_agent.py#L58-L66](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/subagents/code_agent.py#L58) | 从 workspace 解析 coding_memory 目录路径 |

## 三、实现机制

### 1. 工作区节点与目录隔离

`WorkspaceNode.CODING_MEMORY` ([workspace.py#L73](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/workspace/workspace.py#L73)) 定义了 `coding_memory` 节点。`DEFAULT_WORKSPACE_SCHEMA` ([workspace.py#L480-L493](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/workspace/workspace.py#L480)) 为该节点声明子结构:

```
coding_memory/
└── MEMORY.md   # Coding 记忆索引(default_content 为空,随用随填)
```

该节点与 `memory`(个人记忆)、`daily_memory`(每日结构化记忆)平级但物理隔离,确保编码记忆不与个人记忆串扰。

### 2. 工具集与作用域锁定

`create_coding_memory_tools` ([coding_memory.py#L98-L117](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/coding_memory.py#L98)) 创建三个工具并绑定共享 `CodingMemoryToolContext`:

| 工具 | 输入 | 行为 |
| --- | --- | --- |
| CodingMemoryReadTool | path, offset?, limit? | 按 path 读取记忆条目 |
| CodingMemoryWriteTool | path, content | 写入新记忆条目 |
| CodingMemoryEditTool | path, old_text, new_text | 局部替换记忆内容 |

关键在于 L106-L111 的作用域锁定:若 `ctx.workspace` 存在,则 `coding_memory_dir` 取自 `ctx.workspace.get_node_path("coding_memory")`,并回写到 `ctx.coding_memory_dir` 与 `ctx.settings`,确保所有工具的读写都收敛在 coding_memory 目录内,无法越界。源码片段:

```python
if ctx.workspace is not None:
    coding_memory_dir = str(ctx.workspace.get_node_path("coding_memory") or "")
    ctx.coding_memory_dir = coding_memory_dir
    if ctx.settings is None:
        ctx.settings = create_memory_settings(coding_memory_dir)
ctx.node_name = "coding_memory"
```

记忆条目以独立 `.md` 文件存储,frontmatter 元数据示例:

```
---
type: project
tags: [auth, jwt, dataclass]
created: 2026-08-05
---
本项目响应统一用 dataclass 表达,不引入 pydantic。
```

frontmatter 供检索索引,正文为人类可读 Markdown,兼顾机器召回与人工审计。

### 3. 混合检索与自动召回

`CodingMemoryRail` ([coding_memory_rail.py#L41](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/rails/memory/coding_memory_rail.py#L41)) priority=80,与 personal MemoryRail 同优先级但职责隔离。其工作流:

```
user turn 开始
   │  非阻塞启动 prefetch 任务
   ▼
向量检索(embedding_config) + BM25 关键词检索 → 融合排序
   │
   ├─ 有召回结果 → 注入 top5 全文(上限 10KB)
   └─ 无结果     → 降级注入 MEMORY.md 索引
   │
   ▼
系统提示拼接(通过 PromptAttachmentManager)
   │
   ▼
LLM 基于召回记忆决策 → 必要时调用 coding_memory_write/edit 沉淀新经验
```

非阻塞 prefetch 保证召回不阻塞主流程;互斥注入避免重复占用上下文;10KB 上限防止记忆淹没系统提示。

### 4. 启用路径

`CodeAgent` 的 `_resolve_coding_memory_dir` ([code_agent.py#L58-L66](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/subagents/code_agent.py#L58)) 从 workspace 解析目录;`create_code_agent` 在 L248-L257 检测 `embedding_config is not None` 且无既有 `CodingMemoryRail` 时,自动追加该 Rail。即:用户只需传入 `embedding_config`,编码记忆通道即自动激活,无需手动装配工具或 Rail。

### 5. 记忆类型与存储格式

记忆条目以独立 `.md` 文件 + frontmatter 元数据存储,类型涵盖:

- **user**:用户偏好与编码习惯;
- **feedback**:反馈纠正(如"上次接口返回结构错了");
- **project**:项目约定(如"本项目用 dataclass 而非 pydantic");
- **reference**:参考资料(如关键调用链、外部 API 行为)。

frontmatter 便于检索索引,正文为人类可读 Markdown,兼顾机器召回与人工审计。

## 四、调用示例

```python
from openjiuwen.core.foundation.store.base_embedding import EmbeddingConfig
from openjiuwen.harness.subagents.code_agent import create_code_agent
from openjiuwen.harness.runner import Runner

agent = create_code_agent(
    model,
    workspace="./proj",
    # 传入 embedding_config 即自动激活 CodingMemoryRail + 编码记忆工具集
    embedding_config=EmbeddingConfig(...),
)

result = Runner.run_agent(
    agent,
    {"query": "继续上次的支付重构,记得我们约定用 dataclass 表达响应"},
)
print(result.final_output)
# 预期:
# 1) user turn 启动, CodingMemoryRail 非阻塞召回 top5 相关记忆;
# 2) 命中"本项目用 dataclass"等 project 记忆 → 注入系统提示;
# 3) 代理据此编码, 必要时调用 coding_memory_write 沉淀本次新决策;
# 4) 下次会话再问同类问题, 记忆自动召回, 越用越懂代码库。
```

## 五、业界对比

| 能力维度 | agent-core | Cursor | Claude Code | GitHub Copilot |
| --- | --- | --- | --- | --- |
| 编码专属记忆区 | 有,`coding_memory/` 独立节点 | 无专属记忆区 | 有 .cursorrules 但非记忆 | 无 |
| 向量 + BM25 混合检索 | 有,融合召回 | 仅语义检索 | 仅关键词/规则 | 无 |
| 跨会话召回 | 有,每 turn 自动 top5 | 部分,依赖上下文 | 部分 | 无 |
| 作用域隔离 | 有,工具锁定 coding_memory 目录 | 无此机制 | 无 | 无 |
| 自动注入工具 | 有,`embedding_config` 触发 | 需手动配置 | 需手动维护规则文件 | 无 |

## 六、小结

- agent-core 提供与个人记忆并行的编码专属记忆通道 `coding_memory/`,跨会话保留编码决策、接口约定与踩坑经验。
- 存储形态为 `.md` + frontmatter,类型涵盖 user/feedback/project/reference,兼顾机器召回与人工审计。
- 检索采用向量 + BM25 混合,每 user turn 非阻塞召回 top5(上限 10KB),有结果注入全文、无结果降级注入 MEMORY.md 索引。
- 工具集作用域锁定在 coding_memory 目录,与 personal memory 物理隔离,杜绝串扰。
- 启用极简:`CodeAgent` 的 `embedding_config` 参数即可自动激活 CodingMemoryRail 并注入工具,越用越懂代码库。
