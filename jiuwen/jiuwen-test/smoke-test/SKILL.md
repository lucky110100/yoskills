---
name: smoke-test
description: "JiuwenTest 冒烟测试编排流程 — 仓库管理、agent-core-java 编译、mock 服务启动、冒烟用例执行。Invoke when user asks to run smoke tests, 冒烟测试, or 系统用例验证."
execution:
  mode: local
  language: shell
  timeout: 600
  environment:
    WORK_SPACE: "/home/luffy/projects/jiuwen/main"
---

# JiuwenTest 冒烟测试编排

## 概述

本 Skill 编排 JiuwenTest 冒烟测试的完整流程，涵盖：工作目录确认、源码仓与测试仓管理、agent-core-java 编译安装、mock 服务启动、冒烟用例执行。

**执行流程为严格的顺序步骤，每一步完成后才进入下一步。涉及用户决策的步骤需使用 `AskUserQuestion` 等待用户确认后再继续。**

## 仓库信息

| 仓库 | origin | fork | 本地路径 |
|------|--------|------|----------|
| agent-core-java | `https://gitcode.com/openJiuwen/agent-core-java.git` | `https://gitcode.com/whylazy/agent-core-java.git` | `${WORK_SPACE}/agent-core-java` |
| jiuwen-test | `https://gitcode.com/openJiuwen/jiuwen-test.git` | `https://gitcode.com/whylazy/jiuwen-test.git` | `${WORK_SPACE}/jiuwen-test` |
| yoskills | `https://gitcode.com/whylazy/yoskills.git` | — | `${WORK_SPACE}/yoskills` |

## 步骤 1：确认工作目录

1. 设置默认工作目录：`WORK_SPACE="/home/luffy/projects/jiuwen/main"`
2. 使用 `AskUserQuestion` 询问用户当前工作目录是否正确：
   - 选项一：正确，继续（推荐）
   - 选项二：不正确，手动输入

3. 若用户选择不正确，提示用户输入正确的工作目录路径，更新 `WORK_SPACE` 变量。

## 步骤 2：检查与管理目标源码仓（agent-core-java）

1. 检查 `${WORK_SPACE}/agent-core-java` 目录是否存在且为有效 git 仓库：
   ```bash
   if [ -d "${WORK_SPACE}/agent-core-java/.git" ]; then
       cd "${WORK_SPACE}/agent-core-java"
       echo "=== 当前分支 ==="
       git branch --show-current
       echo "=== 远程仓库 ==="
       git remote -v
       echo "=== 工作区状态 ==="
       git status -s
       echo "=== 最近提交 ==="
       git log --oneline -5
   else
       echo "NOT_FOUND"
   fi
   ```

2. **若目录不存在**：克隆 origin 仓库并添加 fork 远程：
   ```bash
   cd "${WORK_SPACE}"
   git clone https://gitcode.com/openJiuwen/agent-core-java.git
   cd agent-core-java
   git remote add fork https://gitcode.com/whylazy/agent-core-java.git
   ```

3. **若目录已存在**：展示当前 git 状态（分支、远程、工作区状态、最近提交），使用 `AskUserQuestion` 询问用户：
   - 选项一：切换到指定远程仓库和分支并拉取最新代码（推荐）
   - 选项二：保持当前分支不变，仅拉取最新代码
   - 选项三：不做任何操作

4. 若用户选择切换分支，提示用户输入目标远程仓库名称（如 `origin` 或 `fork`）和目标分支名称，然后执行：
   ```bash
   cd "${WORK_SPACE}/agent-core-java"
   git fetch --all
   git checkout <用户指定的分支>
   git pull <用户指定的远程仓库> <用户指定的分支>
   ```

5. 若用户选择仅拉取最新代码：
   ```bash
   cd "${WORK_SPACE}/agent-core-java"
   git pull
   ```

## 步骤 3：检查与管理系统用例仓（jiuwen-test）

1. 检查 `${WORK_SPACE}/jiuwen-test` 目录是否存在且为有效 git 仓库：
   ```bash
   if [ -d "${WORK_SPACE}/jiuwen-test/.git" ]; then
       cd "${WORK_SPACE}/jiuwen-test"
       echo "=== 当前分支 ==="
       git branch --show-current
       echo "=== 远程仓库 ==="
       git remote -v
       echo "=== 工作区状态 ==="
       git status -s
       echo "=== 最近提交 ==="
       git log --oneline -5
   else
       echo "NOT_FOUND"
   fi
   ```

2. **若目录不存在**：克隆 origin 仓库并添加 fork 远程：
   ```bash
   cd "${WORK_SPACE}"
   git clone https://gitcode.com/openJiuwen/jiuwen-test.git
   cd jiuwen-test
   git remote add fork https://gitcode.com/whylazy/jiuwen-test.git
   ```

3. **若目录已存在**：展示当前 git 状态（分支、远程、工作区状态、最近提交），使用 `AskUserQuestion` 询问用户：
   - 选项一：切换到指定远程仓库和分支并拉取最新代码（推荐）
   - 选项二：保持当前分支不变，仅拉取最新代码
   - 选项三：不做任何操作

4. 若用户选择切换分支，提示用户输入目标远程仓库名称（如 `origin` 或 `fork`）和目标分支名称，然后执行：
   ```bash
   cd "${WORK_SPACE}/jiuwen-test"
   git fetch --all
   git checkout <用户指定的分支>
   git pull <用户指定的远程仓库> <用户指定的分支>
   ```

5. 若用户选择仅拉取最新代码：
   ```bash
   cd "${WORK_SPACE}/jiuwen-test"
   git pull
   ```

## 步骤 4：编译安装 agent-core-java

执行 Maven 编译安装（跳过测试）：

```bash
mvn clean install -DskipTests -f "${WORK_SPACE}/agent-core-java/pom.xml"
```

**验证**：确认 BUILD SUCCESS 输出。若编译失败，展示错误日志并停止流程，提示用户排查。

## 步骤 5：启动 Mock 服务

mock 服务运维脚本位于 `${WORK_SPACE}/yoskills/jiuwen/jiuwen-test/mock_service/`。

**路径说明**：`config.sh` 中 `MOCK_PROJECT_ROOT` 默认值为 `/home/luffy/projects/jiuwen/main`，需确认与步骤 1 中的 `WORK_SPACE` 一致。若用户在步骤 1 修改了工作目录，需设置环境变量：
```bash
export MOCK_PROJECT_ROOT="${WORK_SPACE}"
```

1. 先检查依赖是否已安装：
   ```bash
   cd "${WORK_SPACE}/yoskills/jiuwen/jiuwen-test/mock_service"
   ./ops.sh check
   ```

2. 若依赖未安装，先安装依赖：
   ```bash
   ./ops.sh install
   ```

3. 停止可能残留的旧服务，再启动：
   ```bash
   ./ops.sh stop
   ./ops.sh start
   ```

4. 验证服务健康状态：
   ```bash
   ./ops.sh health
   ```

**验证**：确认所有 5 个 mock 服务（端口 8000/8088/8188/8189/8190）均正常。若有异常，使用 `./ops.sh status` 查看详情并提示用户排查。

## 步骤 6：运行冒烟用例

1. 设置环境变量：
   ```bash
   export REDIS_IP=127.0.0.1
   export JAEGER_UI_URL=http://127.0.0.1:8460
   export JAEGER_OTLP_ENDPOINT=http://127.0.0.1:4317
   ```

2. 使用 `AskUserQuestion` 询问用户选择冒烟测试场景：
   - 选项一：场景一 — 跑全部冒烟用例（推荐）
   - 选项二：场景二 — 跑冒烟用例，排除知识库用例

3. 根据用户选择执行对应命令：

   **场景一**（全部冒烟用例）：
   ```bash
   cd "${WORK_SPACE}/jiuwen-test"
   mvn clean test -Dgroups=smoke
   ```

   **场景二**（排除知识库用例）：
   ```bash
   cd "${WORK_SPACE}/jiuwen-test"
   mvn clean test -Dgroups='smoke' -Dtest='!com/openjiuwen/test/cases/knowledge_base/**'
   ```

4. 测试执行完成后，展示测试结果摘要（通过/失败/跳过数量）。若有失败用例，展示失败用例详情。

## 注意事项

1. **步骤严格顺序**：步骤 1-6 必须按顺序执行，不可跳过。
2. **用户交互**：步骤 1、2、3、6 均需用户确认后才继续执行。
3. **编译失败处理**：步骤 4 若编译失败，停止后续流程，不要继续启动服务或跑用例。
4. **mock 服务路径**：运维脚本在 `yoskills/jiuwen/jiuwen-test/mock_service/`，mock 服务源码在 `jiuwen-test/mock_service/`，两者通过 `MOCK_PROJECT_ROOT` 关联。
5. **环境变量一致性**：步骤 5 的 `MOCK_PROJECT_ROOT` 必须与步骤 1 确认的 `WORK_SPACE` 一致。
6. **Jaeger 地址**：`JAEGER_UI_URL` 和 `JAEGER_OTLP_ENDPOINT` 的默认值为远程地址，如需修改请在执行前询问用户。
