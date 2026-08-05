---
name: "gitcode"
description: "调用 GitCode OpenAPI (api.gitcode.com/api/v5) 查询用户、仓库、issue 等。当需要通过 API 访问 GitCode 资源（获取仓库 issue 列表、搜索仓库、查看用户/仓库信息）时使用。"
---

# GitCode API CLI

封装 GitCode OpenAPI（`https://api.gitcode.com/api/v5`）常用接口的命令行工具，提供 **Windows (PowerShell)** 与 **Linux (Bash)** 两个版本。

## 凭证

通过环境变量 `GITCODE_TOKEN` 提供 GitCode 个人访问令牌：

- 若环境变量已设置，直接使用；
- 若未设置且终端为交互式，CLI 会提示输入令牌（输入时隐藏）；
- 若未设置且终端为非交互式（管道 / CI），CLI 报错退出；
- 也可通过 `--token` 参数临时传入。

获取令牌地址：https://gitcode.com/setting/token-classic

## 脚本位置

```
yoskills/common/gitcode/
├── SKILL.md        # 本说明
├── gitcode.ps1     # Windows PowerShell 版
└── gitcode.sh      # Linux Bash 版
```

## 使用方式

### Windows (PowerShell)

```powershell
cd yoskills\common\gitcode
.\gitcode.ps1 user
.\gitcode.ps1 search-repos -q agent-core-java
.\gitcode.ps1 repo -o openJiuwen -r agent-core-java
.\gitcode.ps1 issues -o openJiuwen -r agent-core-java -s all
```

### Linux (Bash)

```bash
cd yoskills/common/gitcode
chmod +x gitcode.sh
./gitcode.sh user
./gitcode.sh search-repos -q agent-core-java
./gitcode.sh repo -o openJiuwen -r agent-core-java
./gitcode.sh issues -o openJiuwen -r agent-core-java -s all
```

## 命令一览

| 命令 | 说明 | 对应接口 |
|------|------|----------|
| `user` | 获取当前认证用户信息（验证令牌） | `GET /api/v5/user` |
| `repo -o <owner> -r <repo>` | 获取仓库详情 | `GET /api/v5/repos/{owner}/{repo}` |
| `search-repos -q <keyword>` | 搜索仓库 | `GET /api/v5/search/repositories?q=` |
| `issues -o <owner> -r <repo>` | 列出仓库 issue | `GET /api/v5/repos/{owner}/{repo}/issues` |

## issues 命令参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `-o, --owner` | 仓库所有者（必填） | — |
| `-r, --repo` | 仓库名称（必填） | — |
| `-s, --state` | issue 状态：`open` / `closed` / `all` | `all` |
| `-p, --page` | 页码 | `1` |
| `-n, --per-page` | 每页数量（最大 100） | `50` |

## 全局参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--token <token>` | GitCode 访问令牌 | `$GITCODE_TOKEN` 环境变量 |
| `--base <url>` | API 基础地址 | `https://api.gitcode.com/api/v5` |
| `--raw` | 输出原始 JSON（不格式化），便于管道处理 | 否 |
| `-h, --help` | 显示帮助 | — |

## 输出

默认输出格式化后的 JSON（UTF-8）。加 `--raw` 可输出原始 JSON，便于配合 `jq` 等工具管道处理。

## 认证方式

CLI 使用 `Authorization: Bearer <token>` 请求头进行认证，令牌不会出现在 URL 或服务器访问日志中。

## 已实现接口

1. `GET /api/v5/user` — 获取当前认证用户信息（验证令牌有效性）
2. `GET /api/v5/search/repositories?q=<keyword>` — 搜索仓库
3. `GET /api/v5/repos/{owner}/{repo}/issues` — 列出仓库 issue
4. `GET /api/v5/repos/{owner}/{repo}` — 获取仓库详情

## 后续可扩展接口

按需补充以下接口到 CLI（修改 `gitcode.ps1` / `gitcode.sh` 即可）：

- `GET /api/v5/repos/{owner}/{repo}/issues/{number}` — issue 详情
- `GET /api/v5/repos/{owner}/{repo}/issues/{number}/comments` — issue 评论
- `GET /api/v5/repos/{owner}/{repo}/pulls` — PR 列表
- `GET /api/v5/repos/{owner}/{repo}/branches` — 分支列表
- `GET /api/v5/repos/{owner}/{repo}/commits` — 提交列表
- `POST /api/v5/repos/{owner}/{repo}/issues` — 创建 issue
