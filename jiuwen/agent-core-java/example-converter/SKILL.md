---
name: example-converter
description: "agent-core-java 示例双向转换 — standalone Maven 模块 ↔ inline 扁平示例。Invoke when user asks to convert/migrate examples between agent-core-java-examples and agent-core-java/examples"
execution:
  mode: local
  language: python
  timeout: 120
  entrypoint: scripts/convert_example.py
---

# agent-core-java 示例双向转换器

## 概述

本 Skill 提供 `agent-core-java-examples/<name>`（standalone Maven 模块）与 `agent-core-java/examples/<name>`（inline 扁平示例）之间的双向转换能力。

两种示例格式的核心差异：

| 对比项 | standalone (agent-core-java-examples) | inline (agent-core-java/examples) |
|--------|--------------------------------------|-----------------------------------|
| 构建方式 | Maven pom.xml，依赖父 POM | 无 pom.xml，通过 run.ps1 编译运行 |
| 目录结构 | `src/main/java/...` Maven 标准 | `<Example>.java` 扁平放根目录 |
| API 配置 | `src/main/resources/apiconfig.json`（独立） | 共享 `../apiconfig.json` |
| Skill 路径 | `examples/<name>/skills/` | `skills/`（扁平） |
| 资源文件 | `src/main/resources/data/` | `data/`（扁平） |
| 工具类 | `example-utils` Maven 依赖 | `../utils/SharedExampleApiConfigLoader.java` |
| 运行脚本 | 无（需 IDE 或 mvn exec:java） | `run.ps1` 一键编译运行 |
| 文档 | `documents/` 目录 | `README.md` 根目录 |
| 模块定位 | `resolveModuleDir()` 查 pom.xml → 硬编码路径 | `resolveModuleDir()` 向上遍历找 pom.xml |
| 硬编码常量 | 如 `SANDBOX_URL = "http://..."` | 改为 `resolveStringConfig("SANDBOX_URL", "http://...")` |

## 使用方式

```bash
# standalone → inline 转换（默认方向）
python scripts/convert_example.py sandbox --direction standalone-to-inline --verify

# inline → standalone 逆向转换
python scripts/convert_example.py sandbox --direction inline-to-standalone --verify

# 只显示计划不执行
python scripts/convert_example.py sandbox --dry-run

# 只验证已有示例
python scripts/convert_example.py sandbox --verify-only

# 指定仓库根目录
python scripts/convert_example.py sandbox --repo-root /path/to/repo

# 逆向转换 dry-run
python scripts/convert_example.py sandbox --direction inline-to-standalone --dry-run
```

## 参数说明

| 参数 | 必选 | 说明 |
|------|------|------|
| `name` | ✅ | 示例名称（如 sandbox, skill_hot_reload） |
| `--direction` | ❌ | 转换方向：`standalone-to-inline`（默认）或 `inline-to-standalone` |
| `--repo-root` | ❌ | 仓库根目录路径（自动检测） |
| `--dry-run` | ❌ | 只显示计划不执行 |
| `--verify` | ❌ | 转换后验证（编译+运行） |
| `--verify-only` | ❌ | 只验证已有示例不执行转换 |

## 转换规则

### standalone → inline 转换规则

1. **Java 文件**：从 `src/main/java/examples/<name>/<Class>.java` 扁平化为 `<Class>.java`
2. **Java 代码修改**：
   - `resolveModuleDir()` 从硬编码路径改为向上遍历（cwd → parent → grandparent）
   - 硬编码常量改为 `resolveStringConfig()` 可覆盖（如 `SANDBOX_URL`）
   - `import examples.utils.SharedExampleApiConfigLoader` 保持不变（已有）
3. **Skill 目录**：从 `examples/<name>/skills/` 扁平化为 `skills/`
4. **资源文件**：从 `src/main/resources/data/` 扁平化为 `data/`，跳过 `apiconfig.json`
5. **生成 run.ps1**：自动生成 4 步编译运行脚本
6. **不修改原工程代码**：转换只创建新文件，不修改 agent-core-java-examples 或 agent-core-java 中的原有代码

### inline → standalone 逆向转换规则

1. **Java 文件**：从 `<Class>.java` 放回 `src/main/java/examples/<name>/<Class>.java`
2. **Java 代码修改**：
   - `resolveModuleDir()` 从向上遍历恢复为硬编码 `cwd.resolve("agent-core-java-examples").resolve("<name>")`
   - `resolveStringConfig("SANDBOX_URL", ...)` 恢复为硬编码 `"http://127.0.0.1:8321"`
3. **Skill 目录**：从 `skills/` 放回 `examples/<name>/skills/`
4. **资源文件**：从 `data/` 放回 `src/main/resources/data/`
5. **生成 pom.xml**：自动生成 Maven pom.xml（依赖父 POM `agent-core-java-examples`）
6. **删除 run.ps1**：standalone 不需要

## 验证方式

- **inline 验证**：运行 `run.ps1`，检查编译成功和运行输出
- **standalone 验证**：运行 `mvn compile -DskipTests`，检查 Maven 编译成功

## 注意事项

1. 转换脚本自动检测仓库根目录（需同时包含 `agent-core-java-examples` 和 `agent-core-java/examples`）
2. `--dry-run` 模式只打印计划不写入文件，建议先用 dry-run 查看
3. `--verify` 验证可能因服务未启动而失败（如 jiuwenbox 未运行），编译验证仍是有效的
4. 转换不修改原工程代码，如需修改应先向用户确认
5. Java 代码中的正则替换可能不覆盖所有自定义 `resolveModuleDir()` 变体，需人工检查
