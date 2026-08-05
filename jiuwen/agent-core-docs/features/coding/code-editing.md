# 代码编辑与文件操作

> 交叉引用: [01-项目概述](../../01-project-overview.md) | [02-整体架构](../../02-overall-architecture.md) | [04-harness模块](../../04-harness-module.md) | [08-依赖关系](../../08-dependencies.md)

## 一、能力概述

代码编辑与文件操作是 agent-core 基础 coding 能力的底座。它为 LLM 智能体提供对工作区文件的安全、精确、可审计的读写能力,涵盖全文件覆写、字符串级精确替换、多模态读取以及操作历史留痕。所有编辑工具都遵循严格的 read-modify-write 事务范式,确保编辑动作可追溯、可回滚、可校验。

在 agent-core 中,该能力由 [filesystem.py](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/filesystem.py) 中的工具族实现,并通过 [SysOperationRail](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/rails/sys_operation_rail.py#L23) 装配进智能体。Rail 以 priority=100 优先注册 read/write/edit/glob/list/grep/bash 等工具,read_only 模式下只注册只读工具,从而在受控环境下限制智能体的破坏性操作。

该能力的设计哲学是「先读后改、串行落盘、内容留痕」:任何 edit 操作前必须先经过 ReadFileTool 读入并登记到全局注册表,编辑时按 per-file asyncio Lock 串行化,落盘后写入 sha256 摘要并追加操作历史。这一范式最大程度降低了 LLM 幻觉式编辑、并发竞态与脏写风险。

## 二、关键类与函数

| 类/函数 | 文件位置 | 说明 |
|---------|---------|------|
| [EditFileTool](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/filesystem.py#L1233) | filesystem.py#L1233 | 精确字符串替换编辑,支持 old_string/new_string/replace_all,per-file asyncio Lock 串行化 read-modify-write 事务 |
| [WriteFileTool](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/filesystem.py#L1037) | filesystem.py#L1037 | 全文件覆写,stale-write 保护(mtime_ns+size 双重检查),累积覆盖校验 |
| [ReadFileTool](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/filesystem.py#L369) | filesystem.py#L369 | 读文本(带行号 cat -n)/PDF/Jupyter/图片(多模态三级压缩),MAX_LINES_TO_READ=2000,MAX_SIZE_BYTES=256KB |
| [_FILE_READ_REGISTRY](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/filesystem.py#L143) | filesystem.py#L143 | 强制 read-before-edit 范式,记录每文件读取区间与 mtime |
| [SysOperationRail](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/rails/sys_operation_rail.py#L23) | sys_operation_rail.py#L23 | priority=100,注册 read/write/edit/glob/list/grep/bash 工具,read_only 模式只注册只读工具 |

## 三、实现机制

### 3.1 read-before-edit 强制范式

EditFileTool 在执行任何替换前,会查询 [_FILE_READ_REGISTRY](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/filesystem.py#L143)。该注册表以文件路径为键,记录最近的读取区间 `[offset, limit]` 与当时的 `mtime_ns`。若目标文件未在当前会话被 ReadFileTool 读过,EditFileTool 会拒绝执行并提示模型先读取,避免「盲改」导致的破坏性编辑。

### 3.2 per-file asyncio Lock 串行化

为避免同一文件并发编辑产生竞态,文件系统工具在 [filesystem.py#L39-L47](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/filesystem.py#L39) 维护一个 `{path: asyncio.Lock}` 字典。EditFileTool 进入临界区时获取该 Lock,将「读取-替换-写回」封装为不可分割的 read-modify-write 事务,保证同一文件上的编辑操作串行执行。

### 3.3 EditFileTool 关键机制链路

EditFileTool 的执行链路包含多重校验与容错,各机制在源码中的位置如下:

- 前置读取校验:[filesystem.py#L1555-L1563](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/filesystem.py#L1555),确认目标文件已在注册表中。
- 外部修改检测:[filesystem.py#L1566-L1584](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/filesystem.py#L1566),比对当前 mtime_ns+size 与读取时记录的快照,若不一致判定为 stale-write 并中止。
- XML 反消毒:[filesystem.py#L1275-L1309](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/filesystem.py#L1275),通过 `html.unescape` 与 `_DESANITIZITIONS` 还原被工具协议层转义的字符。
- EOL 保留:[filesystem.py#L1297-L1298](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/filesystem.py#L1297) 与 [filesystem.py#L1638](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/filesystem.py#L1638),保留原文件换行风格(CRLF/LF)避免全文件 diff。
- 引号容错:[filesystem.py#L1402-L1409](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/filesystem.py#L1402),`_try_quote_variants` 在匹配失败时尝试直引号与弯引号互换,兼容 LLM 输出的引号风格差异。
- 唯一性校验:[filesystem.py#L1618-L1627](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/filesystem.py#L1618),要求 old_string 在文件中唯一出现,否则必须显式设置 replace_all。
- 新文件创建:[filesystem.py#L1487-L1514](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/filesystem.py#L1487),当 old_string="" 且路径不存在时,创建新文件并写入内容。
- 写回带 sha256:[filesystem.py#L1641-L1648](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/filesystem.py#L1641),落盘后计算内容 sha256 并更新注册表,作为后续 stale-write 检测基线。

### 3.4 WriteFileTool 的 stale-write 保护

[WriteFileTool](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/filesystem.py#L1037) 在覆写前执行 mtime_ns + size 双重检查:若文件自上次读取后已被外部进程修改,则拒绝覆写并报错,防止覆盖用户在外部编辑器中的最新改动。

### 3.5 多模态读取

[ReadFileTool](file:///D:/jiuwen/main/agent-core/openjiuwen/harness/tools/filesystem.py#L369) 按文件类型分发:文本以 `cat -n` 风格带行号返回,单次上限 MAX_LINES_TO_READ=2000 行、MAX_SIZE_BYTES=256KB;PDF 提取文本;Jupyter Notebook 拆分 cell;图片走多模态三级压缩以适配模型上下文窗口。

### 3.6 操作历史审计

所有文件操作通过 `_append_op_history` 写入 `.agent_history/file_ops_{agent_id}_{session_id}.json`,记录操作类型、路径、内容摘要与时间戳,构成完整的操作审计轨迹,便于事后回放与责任追溯。

### 3.7 read-modify-write 事务时序

单次 edit_file 调用的完整事务时序如下,每一步都是事务的有机组成:

```
1. 获取 per-file asyncio Lock(串行化入口)
2. 查询 _FILE_READ_REGISTRY 确认已读(read-before-edit)
3. 比对 mtime_ns + size(stale-write 检测)
4. 读取当前文件内容到内存
5. XML 反消毒 + 引号容错匹配 old_string
6. 唯一性校验 / replace_all 展开
7. 执行字符串替换,生成新内容
8. 保留原 EOL 风格,写回磁盘
9. 计算 sha256,更新注册表基线
10. 追加 _append_op_history 审计记录
11. 释放 Lock
```

任一前置校验(步骤 2-6)失败即中止事务,已写入的内容不可回滚,因此步骤 8 的写回刻意放在所有校验通过之后,保证「要么全做、要么不做」的原子语义。步骤 9 的 sha256 更新为下一次编辑的 stale-write 检测提供基线,形成闭环校验。

### 3.8 累积覆盖校验与多轮写安全

WriteFileTool 在多次连续覆写同一文件时,执行累积覆盖校验:每次覆写前除检查 mtime_ns+size 外,还会比对上一次写入的 sha256 摘要,确保中间未被外部进程插入修改。这一机制在「模型多次重写同一文件」的高频场景下尤为重要,防止基于过期快照的覆盖导致外部改动丢失。

## 四、调用示例

```python
from openjiuwen import create_deep_agent, Runner
from openjiuwen.harness.rails.sys_operation_rail import SysOperationRail

agent = create_deep_agent(
    model="deepseek-chat",
    card="default",
    workspace="./proj",
    rails=[SysOperationRail()],
)

result = Runner.run_agent(
    agent,
    {"query": "修复 main.py 中 calculate 函数的 bug,并确保测试通过"},
)
print(result.final_output)
```

也可在工具层直接调用 EditFileTool 进行精确替换,直观感受 read-before-edit 与 stale-write 校验:

```python
from openjiuwen.harness.tools.filesystem import EditFileTool, ReadFileTool

# 1. 必须先读取目标文件,登记到 _FILE_READ_REGISTRY
ReadFileTool.invoke(inputs={"file_path": "./proj/main.py"})

# 2. 执行精确字符串替换;若文件被外部改动,将触发 stale-write 中止
result = EditFileTool.invoke(inputs={
    "file_path": "./proj/main.py",
    "old_string": "def calculate(a, b):\n    return a - b",
    "new_string": "def calculate(a, b):\n    return a + b",
    "replace_all": False,
})
print(result)  # 返回写入 sha256 与变更摘要
```

上述调用展示了 agent-core 编辑能力的两个不变约束:未读不写(步骤 1 缺失则步骤 2 被拒)、脏写必止(mtime_ns+size 不一致则中止),它们共同把 LLM 的编辑行为约束在安全事务边界内。

在只读受控场景下,可启用 read_only 模式限制破坏性操作:

```python
from openjiuwen.harness.rails.sys_operation_rail import SysOperationRail

rail = SysOperationRail(read_only=True)
agent = create_deep_agent(model="deepseek-chat", card="default", rails=[rail])
```

## 五、业界对比

| 能力维度 | agent-core | Cursor | Claude Code | GitHub Copilot |
|---------|-----------|--------|-------------|----------------|
| 编辑精度 | 字符串替换 + replace_all + 引号容错 | 字符串/diff 混合 | 字符串替换为主 | 行内补全 + 编辑 |
| stale-write 检测 | mtime_ns + size 双重检查 | 依赖编辑器状态 | 无显式检测 | 无显式检测 |
| read-before-edit 强制 | 全局注册表强制 | 否 | 否 | 否 |
| 并发串行化 | per-file asyncio Lock | 单线程编辑器 | 单进程 | 单进程 |
| 操作审计 | 持久化 JSON 历史 | 会话内撤销栈 | 无持久化 | 无持久化 |

## 六、小结

- agent-core 以 read-modify-write 事务为核心,通过 per-file asyncio Lock 保证编辑串行化,从机制上杜绝并发竞态。
- read-before-edit 范式与 mtime_ns+size 双重检查共同构成 stale-write 防护,显著降低脏写风险。
- 引号容错、EOL 保留、XML 反消毒等容错设计,提升了 LLM 输出与真实文件内容匹配的成功率。
- 操作历史持久化为 `.agent_history` 下的 JSON 文件,提供完整审计与回放能力。
- SysOperationRail 的 read_only 模式为受控环境提供安全开关,体现 agent-core 对权限边界的重视。
- ReadFileTool 统一文本、PDF、Jupyter、图片的多模态读取,单工具覆盖 LLM 理解文件所需的全部输入形态。
- 累积覆盖校验在多轮重写场景下比对 sha256,防止基于过期快照的覆盖,守护多轮编辑的数据安全。
- 完整的事务时序(read-modify-write 11 步)与 read_only 开关,共同构成 agent-core 编辑能力的工程化底座。
