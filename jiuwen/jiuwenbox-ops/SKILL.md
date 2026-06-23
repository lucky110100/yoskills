---
name: jiuwenbox-ops
description: "jiuwenbox 沙箱运维操作 — 安装部署、更新、启动、停止、重启、健康检查、功能测试、状态查看"
execution:
  mode: local
  language: shell
  timeout: 300
  entrypoint: ops.sh
  environment:
    JIUWENBOX_HOME: ""
    JIUWENBOX_PORT: "8321"
    JIUWENBOX_WSL_DISTRO: "ubuntu-hermes-v2"
    JIUWENBOX_REPO_URL: "https://gitcode.com/openJiuwen/jiuwenswarm"
---

# jiuwenbox 沙箱运维操作

## 概述

本 Skill 提供 jiuwenbox 沙箱服务的完整运维命令集，用于在 WSL2 环境中管理 jiuwenbox 沙箱服务的生命周期。

jiuwenbox 是基于 Linux namespace (bubblewrap)、Landlock、Seccomp 的轻量级沙箱服务，**只能在 Linux 环境运行**。在 Windows 上需通过 WSL2 部署，WSL2 的 localhost 端口自动转发到 Windows，agent-core-java 通过 `http://127.0.0.1:8321` 调用。

**源码地址**：[https://gitcode.com/openJiuwen/jiuwenswarm/tree/develop/jiuwenbox](https://gitcode.com/openJiuwen/jiuwenswarm/tree/develop/jiuwenbox)

## 支持的命令

| 命令 | 说明 |
|------|------|
| `install` | 安装 Linux 依赖、构建 jiuwenbox wheel、安装到 venv |
| `deploy` | 拷贝代码到 WSL2、构建安装（等同于 install 全流程） |
| `update` | 从源码仓库拉取最新代码、重新构建安装、重启服务 |
| `start` | 启动 jiuwenbox-server 服务 |
| `stop` | 停止 jiuwenbox-server 服务 |
| `restart` | 先停止再启动 |
| `status` | 查看服务运行状态和沙箱实例数 |
| `health` | 健康检查（从 Windows 端验证连通性） |
| `test` | 功能测试：创建沙箱、执行命令、删除沙箱 |
| `clean` | 清理所有沙箱实例 |

## 使用方式

```bash
# 安装部署（首次使用）
./ops.sh install
./ops.sh deploy

# 更新到最新版本（拉取源码 + 重新构建 + 重启）
./ops.sh update

# 启动服务
./ops.sh start

# 查看状态
./ops.sh status

# 停止服务
./ops.sh stop

# 重启服务
./ops.sh restart

# 健康检查（从 Windows 端）
./ops.sh health

# 功能测试
./ops.sh test

# 清理沙箱实例
./ops.sh clean
```

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `JIUWENBOX_HOME` | `~/jiuwenswarm/jiuwenbox` | jiuwenbox 在 WSL2 中的安装目录 |
| `JIUWENBOX_PORT` | `8321` | jiuwenbox 服务端口 |
| `JIUWENBOX_WSL_DISTRO` | `ubuntu-hermes-v2` | WSL2 发行版名称 |

## 部署架构

```
Windows (agent-core-java)
    http://127.0.0.1:8321  ←── WSL2 localhost 自动转发
                                  │
WSL2 Ubuntu (jiuwenbox-server)  │
    jiuwenbox-server (sudo)     │
    ├── bubblewrap (namespace隔离)
    ├── Landlock (文件系统约束)
    ├── Seccomp (系统调用过滤)
    └── cgroup (资源限制)
```

## 注意事项

1. **必须 sudo 运行**：jiuwenbox-server 需要 root 权限来创建 Linux namespace
2. **WSL 重启后需手动 start**：WSL2 重启后 jiuwenbox-server 不会自动启动
3. **Ubuntu 24.04 注意**：默认 policy 中 `/etc/pki` 路径不存在（RedHat 特有），安装时自动移除
4. **端口互通**：WSL2 的 localhost 端口自动转发到 Windows，无需额外配置
5. **源码更新**：使用 `./ops.sh update` 命令可从源码仓库拉取最新代码并重新构建安装，若服务正在运行会自动重启

## 源码仓库

- **地址**：[https://gitcode.com/openJiuwen/jiuwenswarm/tree/develop/jiuwenbox](https://gitcode.com/openJiuwen/jiuwenswarm/tree/develop/jiuwenbox)
- **分支**：`develop`
- **更新命令**：`./ops.sh update`
