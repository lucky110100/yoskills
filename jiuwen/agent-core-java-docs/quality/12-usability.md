# 易用性 — agent-core-java 质量评估

> 组: E 外部质量 | 分: **3/4** | 否决项: 否 | 评估卡: [dims/usability.md](file:///D:/jiuwen/main/yoskills/common/project-analysis/dims/usability.md)

## 评分锚点依据

命中 3 档「有 API 文档 + 错误基本可读 + 有示例」；未达 4 档因无 OpenAPI 文档、CLI 无 --help/补全、配置无显式校验。

## 评估过程

- **信号命中**：API 无版本/无文档 ✅（无 OpenAPI）、CLI 无帮助/补全 ✅、配置无校验 ✅、无最小示例 ❌（47 examples 极丰富）、错误信息不可读 ✅（部分）
- **Grep**：`--help|usage` 在 HarnessCli 0 命中
- **Read**：[HarnessCli.java:21-46](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/cli/HarnessCli.java#L21-L46) 程序式入口
- **Grep**：`@RestController|@RequestMapping|@Path` 源码 0 命中（纯 SDK 形态）
- **Read**：[README.md:42](file:///D:/jiuwen/main/agent-core-java/README.md#L42) 版本 0.1.12

## 关键问题（带证据）

1. **CLI 无 --help 与参数解析**：[HarnessCli.java:21-46](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/cli/HarnessCli.java#L21-L46) 是程序式入口（`runOnce/runChat`），无 main、无 argparse、无 --help/--version 输出（Grep `--help|usage` 0 命中）；[CLIOptions.java:21-31](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/cli/CLIOptions.java#L21-L31) 仅是 Lombok @Builder POJO，用户无法直接命令行上手。
2. **无 OpenAPI/swagger 文档**：仅 swagger-annotations 作为 transitive jar 出现于 target/dependency，源码无 `@RestController`/`@RequestMapping`/`@Path`（Grep 0 命中），属纯 SDK 形态；文档以 200+ 篇手写 markdown 提供（[com.openjiuwen.core.README.md:1-25](file:///D:/jiuwen/main/agent-core-java/documents/zh/2.开发指南/API文档/com.openjiuwen.core.README.md#L1-L25)），但无机器可读契约。
3. **README 版本与 pom 不一致**：[README.md:42](file:///D:/jiuwen/main/agent-core-java/README.md#L42) Quick Start 写 `<version>0.1.12</version>`，而 [pom.xml:10](file:///D:/jiuwen/main/agent-core-java/pom.xml#L10) 为 `0.1.14`，新增依赖能力（如 deep_agent 示例要求 0.1.14+）会被误用旧版本。

## 改进建议

1. 为 HarnessCli 增加 `main(String[] args)` + picocli/jcommander 实现 `--help/--version`
2. 生成 OpenAPI schema（jsonschema-generator 已在依赖中，可输出工具入参契约）
3. README 版本号改为 `${project.version}` 占位或同步 0.1.14
4. 为 CLIOptions 加 `validate()` 方法对必填项与 URL 合法性做启动期校验

## 业界对标

- 标杆：FastAPI 自动 OpenAPI + "for Humans"设计、requests 的 API 设计、mall 的文档体系
- 评价：本项目 47 examples + 200+ API markdown 是强项（易用性基础好）；缺 OpenAPI 与 CLI --help 是扣分项
