# 文档完备度 — agent-core-java 质量评估

> 组: D 演进质量 | 分: **3/4** | 否决项: 否 | 评估卡: [dims/documentation.md](file:///D:/jiuwen/main/yoskills/common/project-analysis/dims/documentation.md)

## 评分锚点依据

命中 3 档「README + 部分 API 文档 + 无 ADR」并显著向上溢出（API 文档实为「完整」而非「部分」），但未达 4 档因缺 ADR。具备双语 README、1000+ 条目 API 文档树、架构规则文件、10 个 .claude/rules 规范、AGENTS.md/CLAUDE.md 双 AI 指令文档；唯一硬缺口是无 ADR 目录，且 SUMMARY.md 存在文档重复瑕疵。

## 评估过程

- **信号命中**：无 README ❌（双语 README）、无 API 文档 ❌（1000+ 条目）、无架构文档 ❌（architecture.md）、无 ADR ✅、注释缺失/陈旧 ✅（部分 Javadoc 同义反复）
- **Glob**：`**/adr/**` → No file found
- **Read**：[SUMMARY.md:51-53](file:///D:/jiuwen/main/agent-core-java/documents/zh/SUMMARY.md#L51-L53) 索引 com.openjiuwen.core 全部子包逐类文档
- **Read**：[SUMMARY.md:912-1106](file:///D:/jiuwen/main/agent-core-java/documents/zh/SUMMARY.md#L912-L1106) sysop 章节重复

## 关键问题（带证据）

1. **API 文档深度罕见**：[SUMMARY.md:51-53](file:///D:/jiuwen/main/agent-core-java/documents/zh/SUMMARY.md#L51-L53) 索引了 `com.openjiuwen.core` 下 application/common/context/controller/foundation/graph/memory/multiagent/operator/retrieval/runner/session/singleagent/sysop/workflow 等全部子包的逐类文档（1000+ 条目），如 [LlmAgent.md](file:///D:/jiuwen/main/agent-core-java/documents/zh/2.开发指南/API文档/com.openjiuwen.core.application.llm.LlmAgent.md)、[MilvusVectorStore.md](file:///D:/jiuwen/main/agent-core-java/documents/zh/2.开发指南/API文档/com.openjiuwen.core.foundation.store.vector.MilvusVectorStore.md) 等，覆盖每个公开类。
2. **架构文档与规范齐全**：[architecture.md:21-37](file:///D:/jiuwen/main/agent-core-java/.claude/rules/architecture.md#L21-L37) 明确 Card/Config 分离设计意图与模块边界表；[AGENTS.md:13-41](file:///D:/jiuwen/main/agent-core-java/AGENTS.md#L13-L41) 逐包说明职责、spi 定位、legacy 兼容边界；[README.md:69-97](file:///D:/jiuwen/main/agent-core-java/README.md#L69-L97) 含架构设计章节。
3. **无 ADR 是硬缺口**：Glob `**/adr/**` 无结果，关键架构决策（为何选 Pregel 模型、为何 TeamAgent 单实现双角色、Card/Config 为何分离）只在 [architecture.md:21-26](file:///D:/jiuwen/main/agent-core-java/.claude/rules/architecture.md#L21-L26) 以「Design intent」一句话带过，无独立 ADR 记录决策上下文/备选方案/后果。另 [SUMMARY.md:912-1106](file:///D:/jiuwen/main/agent-core-java/documents/zh/SUMMARY.md#L912-L1106) 中 sysop 章节重复出现 3 次（L912-976、L977-1041、L1042-1106），是文档维护瑕疵。

## 改进建议

1. 新增 `documents/adr/` 目录，为 Pregel 图执行引擎选型、Card/Config 分离、TeamAgent 单实现双角色、SPI 9 扩展点划分等关键决策补 ADR（Context/Decision/Consequences）
2. 修复 SUMMARY.md 的 sysop 重复段落
3. 为公开 API 文档补充「稳定性标记」（Stable/Experimental/Deprecated）

## 业界对标

- 标杆：FastAPI 自动 OpenAPI、Django 的 docs/、requests 的 readthedocs、mall 的 document/ + macrozheng 博客
- 评价：本项目 1000+ API 文档树 + 双语 README 是强项，缺 ADR 与重复瑕疵是扣分项
