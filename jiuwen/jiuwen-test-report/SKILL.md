---
name: jiuwen-test-report
description: Use when the user asks to run JiuwenTestJava (or openJiuwen Java) tests and produce an Excel report — covers running mvn test against agent-core-java + JiuwenTestJava, parsing surefire-reports XML, and emitting an Excel workbook (模块名/用例文件名/状态/优先级/不通过原因/用例目录) with P0–P4 prioritization. Uses $PROJECT_ROOT variable to adapt to different directories.
---

# JiuwenTestJava 测试结果 Excel 报告生成

## 何时使用

触发条件（任一命中即应启用）：

- 用户要求运行 openJiuwen Java 测试并整理结果（"跑 mvn test 整理为 excel"、"重新跑 JiuwenTestJava 整理表格"、"按 P0-P4 输出测试报告"）
- 用户提及 `agent-core-java` 已更新，要求重新跑 `JiuwenTestJava`
- 用户要求生成测试结果表格 / 按优先级标注

不要用于：单元测试 debug、单个用例修复、CI 配置、其他仓库。

## 仓库布局（前置假设）

所有路径通过 `$PROJECT_ROOT` 变量适配。典型布局：

```
<PROJECT_ROOT>\
├── agent-core-java\           # 核心库，必须先 install 到本地 m2
│   └── pom.xml
├── JiuwenTestJava\            # 集成测试 jar，依赖 agent-core-java
│   ├── pom.xml
│   ├── src\test\java\com\openjiuwen\test\cases\<module>\...
│   └── target\surefire-reports\TEST-*.xml   # mvn test 产物
├── JiuwenTest\                # Python 测试，本 skill 不使用，但其 .venv 可借用
│   └── .venv\Scripts\python.exe
└── st-test-fix\               # 备选：已有预生成的 xlsx 和脚本
    └── jiuwentestjava-mvn-test-results.xlsx
```

**使用前**：将 `$PROJECT_ROOT` 设置为实际项目根目录（例如 `D:\jiuwen\main` 或 `E:\git_code\openJiuwen_java`）。

## 环境前置

- **JDK 17 必须**（项目要求 Java 17）。Windows 默认 cmd 可能挂在 JDK 21，需在每个 bash 命令里 export：
  ```bash
  export JAVA_HOME="/d/java_install/jdk-17"
  export PATH="$JAVA_HOME/bin:$PATH"
  ```
- **Python**：需安装 openpyxl。优先使用 `JiuwenTest/.venv/Scripts/python.exe`；如不存在则使用系统 `python`。
- **Maven**：随系统 PATH

## 快速用法（如果已跑过测试，只需生成报告）

如果 `target/surefire-reports/TEST-*.xml` 已存在，直接跳到 Step 3。

## 配置项（使用前必须确认）

在开始工作流之前，AI 必须使用 AskUserQuestion 让用户逐一确认以下配置项。如果用户未提供值，则使用默认值并明确告知。

| 配置项 | 说明 | 默认值 |
|---|---|---|
| **PROJECT_ROOT** | 项目根目录（所有子项目的父目录） | `D:\jiuwen\main` |
| **JAVA_HOME** | JDK 17 安装路径（bash 格式，如 `/d/java_install/jdk-17`） | `/d/java_install/jdk-17` |
| **AGENT_CORE_DIR** | agent-core-java 子目录名（相对于 PROJECT_ROOT） | `agent-core-java` |
| **TEST_DIR** | JiuwenTestJava 测试项目子目录名（相对于 PROJECT_ROOT） | `JiuwenTestJava` |
| **JIUWEN_TEST_DIR** | JiuwenTest Python 项目子目录名（相对于 PROJECT_ROOT，其 .venv 可借用） | `JiuwenTest` |
| **PYTHON_VENV** | Python 虚拟环境可执行文件路径 | `<PROJECT_ROOT>/<JIUWEN_TEST_DIR>/.venv/Scripts/python.exe` |

**确认流程**：将上述配置项以 multiSelect=false 的方式分批提问（每批最多 4 项），用户确认后方进入 Step 0。如果用户选择"Other"自定义值，则使用用户提供的值覆盖默认值。

> ⚠️ 注意：脚本 `generate_test_report.py` 顶部的 `PROJECT_ROOT` 和 `SUREFIRE_DIR` 等变量也需根据用户确认的值同步修改后再执行。

## 标准工作流（4 步）

### Step 0 — 设置 PROJECT_ROOT 及其他配置变量

将用户确认的配置项写入环境变量并同步到脚本顶部。

```bash
set PROJECT_ROOT=<用户确认的值>
```

同时在脚本 `generate_test_report.py` 中修改：
```python
PROJECT_ROOT = Path(r'<用户确认的 PROJECT_ROOT>')
SUREFIRE_DIR = PROJECT_ROOT / '<用户确认的 TEST_DIR>' / 'target' / 'surefire-reports'
```

### Step 1 — 安装 agent-core-java（跳过测试）

```bash
export JAVA_HOME="/d/java_install/jdk-17" && export PATH="$JAVA_HOME/bin:$PATH" \
  && cd "$PROJECT_ROOT/agent-core-java" \
  && mvn clean install -DskipTests
```

后台跑（耗时 1–3 分钟），等待 `BUILD SUCCESS` + 退出码 0。**未成功不要进 Step 2**。

常见报错：
- `cannot find symbol: class PyZmqMessager` → 仓库当前 HEAD 残缺，让用户回退或手动补类。不要试图用 `--no-fail-fast` 绕过。

### Step 2 — 在 JiuwenTestJava 跑 mvn test

```bash
export JAVA_HOME="/d/java_install/jdk-17" && export PATH="$JAVA_HOME/bin:$PATH" \
  && cd "$PROJECT_ROOT/JiuwenTestJava" \
  && rm -rf target/surefire-reports \
  && mvn test
```

后台跑（耗时 5–15 分钟）。`mvn test` 退出码为 1 是正常的（有失败用例），关键看 `target/surefire-reports/TEST-*.xml` 是否产出。

### Step 3 — 调用解析脚本生成 Excel

把 skills 目录下的 `generate_test_report.py` **复制**（不要硬链接）到 `$PROJECT_ROOT/JiuwenTestJava/generate_test_report.py`。**复制后编辑脚本顶部的配置变量**：

```python
# 修改为实际项目根目录
PROJECT_ROOT = r"D:\jiuwen\main"   # 根据实际目录修改
```

然后运行：

```bash
cd "$PROJECT_ROOT/JiuwenTestJava" \
  && python generate_test_report.py
```

或使用已有的 Python 虚拟环境：

```bash
"$PROJECT_ROOT/JiuwenTest/.venv/Scripts/python.exe" "$PROJECT_ROOT/JiuwenTestJava/generate_test_report.py"
```

输出：`<PROJECT_ROOT>/JiuwenTestJava/test_results_<日期>.xlsx`

### Step 4 — 校验并向用户汇报

强制校验项：
1. 状态合计（通过+失败+错误+跳过）≈ `mvn test` 终端的 `Tests run`（差异多源于 `@ParameterizedTest` 多记录，可接受）
2. 抽样检查 P0/P1/P2/P3 各 2 条，确认分类合理
3. 用 openpyxl 读出几行（终端中文乱码不代表 Excel 内容乱码——文件本身是 UTF-8）

## Excel 表头（严格按用户要求，顺序固定）

```
模块名 | 用例文件名 | 状态 | 优先级 | 不通过原因 | 用例目录
```

- **模块名**：classname 中 `cases.<module>` 的 `<module>`
- **用例文件名**：`<SimpleClassName>.java`
- **状态**：通过 / 失败 / 错误 / 跳过
- **优先级**：P0–P4（见下）
- **不通过原因**：`<exceptionType>: <message>` 折叠空白，限长 1000 字符
- **用例目录**：`cases.<module>.<sub.path>` → 用 `/` 拼接

## 优先级规则（P0–P4）

**用户给的语义（必须遵守）**：

| 优先级 | 含义 | 触发条件 |
|---|---|---|
| **P0** | 真实失败 | status=failed/error，普通断言 / 计算结果错误 / 异常未捕获，**不**含特殊关键字 |
| **P1** | 核心能力缺失 / 阻塞型缺口 | `Python contract`、`Fake-green guard`、`Blocked SDK parity`、`SDK not implemented`（无环境关键字时）、`parity gap`、`UnsupportedOperationException`、`NoClassDefFoundError`、`not yet implemented` |
| **P2** | 模块返回不一致 / 行为不对齐 | `Java logs/raises/emits/returns X instead of Y`、`result map contains extra`、`exposes a different`、`chunk wrapping`、`ClassCastException`、`Expecting code to raise a throwable`、断言中显式提到结构/字段差异 |
| **P3** | 环境依赖、真实模型、Deferred、Python 原始 skip | `pytest.mark.skip`、`real llm/model`、`requires LLM endpoint`、`pending real LLM config`、`Extra Java/support: local smoke`、`Python source is skipped`、`API_KEY/TEST_API_KEY/tavily_key not set`、`Connection refused`、`UnknownHostException`、`Python tests skipped: https://...` |
| **P4** | 通过 | status=passed |

**判定优先级（重要）**：对 skipped 用例按 **P3 → P2 → P1** 顺序判断：
- **同一条 skip 消息既含真实模型/环境又含 parity gap，归 P3**（环境是阻塞根因）。例如 `SDK not implemented: ... pending real LLM config and ... runtime parity not implemented` → P3。

## 复用脚本

参见同目录 `generate_test_report.py`。脚本要点：

- 用 `xml.etree.ElementTree` 解析所有 `TEST-*.xml`
- 每个 `<testcase>` 提取 classname、name、failure/error/skipped 子节点
- 按 `cases.<module>.<...>.ClassName` 切分 module 与 directory
- 按上面规则映射优先级
- openpyxl 写 Excel：表头加深蓝填充 + 白字加粗，优先级列按 P0–P4 着色（P0 橙、P1 黄、P2 浅黄、P3 浅蓝、P4 浅绿）
- 第二个 sheet 写"汇总"统计

## 常见问题排查

| 现象 | 原因 | 解决 |
|---|---|---|
| `mvn` 用了 JDK 21 | bash 继承的 PATH 仍指向 jdk-21 | 每个 bash 命令前 export `JAVA_HOME=/d/java_install/jdk-17` |
| `agent-core-java` 编译失败 `cannot find symbol PyZmqMessager` | 仓库 HEAD 含未提交的删除类引用 | 让用户决定：回退、补类、还是删除引用。不要私自动 |
| Excel 写文件 `PermissionError` | 用户在 Excel 中打开了旧文件 | 脚本顶部改 `OUTPUT_FILE` 为新文件名（如加 `_v2`） |
| 终端中文乱码 | Windows GBK 终端显示 UTF-8 时乱码 | 用 openpyxl 重新读出几行验证，**不要**改文件编码 |
| `Tests run` 数与 surefire XML 解析数不一致 | 参数化用例每个迭代单独条目 | 在汇总里如实注明，不要"修正" |

## 输出汇报格式

向用户汇报时给出：

1. Excel 文件绝对路径与体积
2. 表头（按用户要求那 6 列）
3. 状态合计 + 优先级分布表
4. 一条"如实说明"段落：mvn 终端摘要数 vs 解析数差异、终端乱码 vs 文件实际内容的区别（如有）

参考最终汇报模板见 `report-template.md`。
