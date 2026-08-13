# 09 instance-manager 与 jiuwenbox 模块（多实例管理与五层沙箱）

> 交叉引用: [01-项目概述](../01-project-overview.md) | [02-整体架构](../02-overall-architecture.md) | [05-server与cli](../05-server-and-cli-module.md) | [11-运行方式](../11-running-guide.md)

## 一、能力概述

instance-manager 模块负责 JiuwenSwarm 多实例（默认实例 + 命名实例）的生命周期与并发安全。端口分配采用 `base + index * 1000` 算法（`BASE_PORTS`：agent_server=18092 / web=19000 / gateway=19001 / frontend=5173），在 Docker 环境下支持环境变量覆盖并配合双栈探测避免端口冲突。`InstanceLock` 提供跨平台文件锁：Unix 用 `fcntl.flock`，Windows 用独占创建 + 时间戳陈旧检测，避免两个实例同时抢占同一套端口。`instances.yaml` 原子写入记录实例元数据；`bootstrap.py` 为每个实例生成独立 `.env`（`JIUENSWARM_DATA_DIR`/`JIUENSWARM_INSTANCE` + 端口），`status.py` 聚合运行态查询与停止。

jiuwenbox 是基于 bubblewrap 的 Linux 沙箱执行服务，对外通过 FastAPI 提供沙箱创建、命令执行、策略管理与推理隐私代理。它采用五层纵深防御：第 1 层 bwrap（命名空间 + bind mount + die-with-parent）→ 第 2 层 Landlock（路径 ACL）→ 第 3 层 seccomp-bpf（syscall 过滤）→ 第 4 层 cgroup v2（资源限额）→ 第 5 层 netns + iptables（网络管控）。MCP 代理暴露 `sandbox_run_command` 工具，proxy 子系统管理推理隐私路由，全部对外接口经 Bearer Token 鉴权。

两模块合在一起，构成"调度层 + 执行层"的闭环：instance-manager 解决"如何在一台机器上并行跑多套 JiuwenSwarm 而互不冲突"，jiuwenbox 解决"如何在执行用户/Agent 产生的命令时不被反噬"。前者关注隔离的多实例编排，后者关注单次执行的强隔离沙箱，是系统在生产环境安全运行的两大支柱。

## 二、关键类与函数

### instance-manager

| 类/函数 | 文件位置 | 说明 |
| --- | --- | --- |
| InstanceConfig | [config.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/instance_manager/config.py#L56) | 实例配置 dataclass：name/workspace/ports |
| BASE_PORTS | [config.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/instance_manager/config.py#L41) | 默认实例（index=0）端口基线 |
| compute_auto_port | [config.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/instance_manager/config.py#L161) | 端口分配 base+index*1000 |
| InstanceLock | [lock.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/instance_manager/lock.py#L35) | 跨平台实例启动文件锁 |
| InstanceLock.acquire | [lock.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/instance_manager/lock.py#L69) | 获取排他锁，超时返回 False |
| write_pid_file | [lock.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/instance_manager/lock.py#L192) | 写 JSON 格式 PID 文件 |
| get_instance_status | [status.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/instance_manager/status.py#L43) | 查询运行态：读 PID 文件 + 检测进程存活 |
| list_all_instances | [status.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/instance_manager/status.py#L197) | 列出所有实例状态 |

### jiuwenbox

| 类/函数 | 文件位置 | 说明 |
| --- | --- | --- |
| BwrapConfig | [bwrap.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenbox/src/jiuwenbox/supervisor/bwrap.py#L77) | SecurityPolicy→bwrap CLI 参数 dataclass |
| BwrapConfig.from_policy | [bwrap.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenbox/src/jiuwenbox/supervisor/bwrap.py#L133) | 由 SecurityPolicy 构建 |
| BwrapConfig.to_args | [bwrap.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenbox/src/jiuwenbox/supervisor/bwrap.py#L329) | 转 bwrap 参数列表（无副作用） |
| SecurityPolicy | [policy.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenbox/src/jiuwenbox/models/policy.py#L736) | 完整静态策略：fs/process/namespace/cap/landlock/syscall/network/cgroup |
| FilesystemPolicy | [policy.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenbox/src/jiuwenbox/models/policy.py#L381) | 文件系统策略：ro/rw/dirs/files + 路径校验 |
| SyscallPolicy | [policy.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenbox/src/jiuwenbox/models/policy.py#L438) | 系统调用策略：x86_64/arm64 黑名单 |
| NetworkPolicy | [policy.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenbox/src/jiuwenbox/models/policy.py#L610) | 网络策略：egress/ingress/mode |
| CgroupPolicy | [policy.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenbox/src/jiuwenbox/models/policy.py#L617) | cgroup 限制：memory_max/cpu_max/pids_max |
| detect_landlock_abi | [landlock.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenbox/src/jiuwenbox/supervisor/landlock.py#L25) | 返回 Landlock ABI 版本，0 不可用 |
| encode_landlock_payload | [landlock.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenbox/src/jiuwenbox/supervisor/landlock.py#L34) | 构建沙箱内 Landlock 启动器消费的 payload |
| build_seccomp_filter | [seccomp.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenbox/src/jiuwenbox/supervisor/seccomp.py#L274) | SyscallPolicy→二进制 BPF 过滤器 |
| _assemble_bpf | [seccomp.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenbox/src/jiuwenbox/supervisor/seccomp.py#L294) | 校验架构→加载 nr→inline deny→daemon guard→ALLOW |
| _append_daemon_signal_guard | [seccomp.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenbox/src/jiuwenbox/supervisor/seccomp.py#L223) | 拦截 kill/tkill/tgkill 针对基础设施 PID |
| cgroup.setup | [cgroup.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenbox/src/jiuwenbox/supervisor/cgroup.py#L382) | 创建 cgroup 应用限制，v2 优先回退 v1 |
| _setup_v2 | [cgroup.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenbox/src/jiuwenbox/supervisor/cgroup.py#L205) | v2：建目录写 memory.max/cpu.max/pids.max |
| cgroup.attach | [cgroup.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenbox/src/jiuwenbox/supervisor/cgroup.py#L412) | PID 写入 cgroup.procs |
| cgroup.teardown | [cgroup.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenbox/src/jiuwenbox/supervisor/cgroup.py#L500) | 清残留 + rmdir，失败仅告警 |
| setup_network_uplink | [network.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenbox/src/jiuwenbox/supervisor/network.py#L655) | 创建 veth 对、分配 /30、NAT MASQUERADE |
| apply_iptables_rules | [network.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenbox/src/jiuwenbox/supervisor/network.py#L853) | 命名空间内出/入向 iptables |
| setup_network_isolation | [network.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenbox/src/jiuwenbox/supervisor/network.py#L864) | 网络隔离顶层入口，HOST 模式跳过 |
| create_app | [app.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenbox/src/jiuwenbox/server/app.py#L388) | 构建 FastAPI：CORS+Bearer 鉴权+异常+路由 |
| lifespan | [app.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenbox/src/jiuwenbox/server/app.py#L242) | 提升 NOFILE+线程池+subreaper+启动各管理器 |
| mcp_server/sandbox_run_command | [mcp.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenbox/src/jiuwenbox/server/routes/mcp.py#L47) | FastMCP（带 DNS rebinding 防护）/MCP 工具 |
| create_proxy | [proxy.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenbox/src/jiuwenbox/server/routes/proxy.py#L67) | 创建推理隐私代理（单路由） |
| BearerTokenAuthMiddleware | [auth.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenbox/src/jiuwenbox/server/auth.py#L42) | Bearer 鉴权，hmac.compare_digest 防时序攻击 |
| launcher.main | [launcher.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenbox/src/jiuwenbox/server/launcher.py#L222) | 服务器 CLI 入口，--listen/--api-token |

## 三、实现机制

### 1. 多实例管理

多实例管理的核心链路是"端口分配 → 文件锁 → PID 记录 → 运行态查询 → 实例列举"：

1. **端口分配**：`compute_auto_port` 按 `base + index * 1000` 计算每个实例的端口（`BASE_PORTS` 给出 index=0 的基线）。Docker 环境下允许通过环境变量覆盖，并配合双栈探测（IPv4 + IPv6）规避冲突。
2. **跨平台文件锁**：`InstanceLock.acquire` 在 Unix 用 `fcntl.flock` 加排他锁，在 Windows 用独占创建文件 + 时间戳陈旧检测（避免上次崩溃残留的死锁）。
3. **PID 记录**：`write_pid_file` 以 JSON 格式写入 PID 文件，供后续存活检测使用。
4. **运行态查询**：`get_instance_status` 读取 PID 文件并检测进程是否存活；`list_all_instances` 聚合所有实例状态。
5. **实例隔离**：`bootstrap.py` 为每个实例生成独立 `.env`，写入 `JIUENSWARM_DATA_DIR`、`JIUENSWARM_INSTANCE` 及端口，启动时通过 `--dotenv <path>` 实现数据目录与配置隔离。
6. **元数据持久化**：`instances.yaml` 原子写入，保证并发写不撕裂文件。

### 2. jiuwenbox 五层纵深防御

沙箱执行采用五层纵深防御，每层有明确的防御目标与触发位置：

#### 第 1 层 bwrap（命名空间与挂载）

`BwrapConfig.from_policy` 由 `SecurityPolicy` 构建，`to_args` 转为无副作用的参数列表。该层防御目标与触发位置：

- **命名空间 unshare**：net/ipc/cgroup/pid/uts/user 全隔离，使沙箱内看不到宿主进程与网络。
- **bind mount**：ro/rw/device/tmpfs 由 `FilesystemPolicy` 驱动，`_apply_bind_root_entries` 逐子项展开，控制沙箱"看得见什么"。
- **capabilities**：剥离危险 capability，限制特权操作。
- **seccomp fd**：把后续 seccomp-bpf 过滤器以 fd 形式传入。
- **`--die-with-parent`**：设置 `PR_SET_PDEATHSIG=SIGKILL`，父进程退出时级联杀掉沙箱，杜绝孤儿 daemon。

#### 第 2 层 Landlock（路径 beneath ACL）

- **机制**：通过 syscall 444/445/446 设置路径 beneath ACL，限制对路径的读/写/执行。
- **探测**：`detect_landlock_abi` 返回 Landlock ABI 版本（0 表示不可用，跳过该层）。
- **payload**：`encode_landlock_payload` 构建沙箱内 Landlock 启动器消费的 payload，显式排除 `/jiuwenbox` 自身，避免沙箱回打基础设施。
- **与 bwrap 关系**：bind 决定"看得见什么"，Landlock 决定"能否读写"，二者互补。

#### 第 3 层 seccomp-bpf（syscall 过滤）

- **过滤器生成**：`build_seccomp_filter` 由 `SyscallPolicy` 的 x86_64/arm64 黑名单生成二进制 BPF。
- **组装流程**：`_assemble_bpf` 校验架构 → 加载 nr → inline `RET ERRNO` → daemon 信号守护 → 末尾 `ALLOW`。
- **daemon 信号守护**：`_append_daemon_signal_guard` 拦截 `kill`/`tkill`/`tgkill` 针对基础设施 PID 的调用，防止沙箱内进程杀死 jiuwenbox 自身。

#### 第 4 层 cgroup v2（资源限额）

- **创建与限制**：`cgroup.setup` v2 优先回退 v1；`_setup_v2` 建目录并写 `memory.max`/`cpu.max`/`pids.max`，且 `memory.swap.max=0` 钳死交换，防止内存型攻击。
- **进程挂入**：`cgroup.attach` 把 PID 写入 `cgroup.procs`。
- **清理**：`cgroup.teardown` 清残留并 rmdir，失败仅告警不阻断。

#### 第 5 层 network（网络管控）

- **顶层入口**：`setup_network_isolation` 是网络隔离顶层入口，HOST 模式下直接跳过。
- **上行链路**：`setup_network_uplink` 创建 veth 对、分配 /30 子网、配置 NAT MASQUERADE。
- **规则下发**：`apply_iptables_rules` 在命名空间内下发出/入向规则，域名经 `resolve_domains` 解析为 IP，并自动探测 `iptables`/`iptables-nft`/`iptables-legacy` 选择可用后端。

#### 服务层

`create_app` 构建 FastAPI（CORS + Bearer 鉴权 + 异常处理 + 路由），`lifespan` 提升 NOFILE 限制、初始化线程池、设置 subreaper 并启动各管理器。`BearerTokenAuthMiddleware` 用 `hmac.compare_digest` 做常量时间比较以防时序攻击。`mcp_server` 以 FastMCP（带 DNS rebinding 防护）暴露 `sandbox_run_command` 工具，`create_proxy` 提供推理隐私代理。`launcher.main` 是 CLI 入口，支持 `--listen` 与 `--api-token`。

### 3. 五层协同表

| 层 | 机制 | 防御目标 | 触发位置 |
| --- | --- | --- | --- |
| 第 1 层 | bwrap（命名空间 + bind mount + die-with-parent） | 进程/网络/挂载隔离，防孤儿 daemon | `BwrapConfig.to_args` 构建启动参数 |
| 第 2 层 | Landlock（路径 beneath ACL） | 路径级读写执行控制 | `encode_landlock_payload` + 沙箱内启动器 |
| 第 3 层 | seccomp-bpf（syscall 过滤） | 危险 syscall 拦截，防 kill 基础设施 | `build_seccomp_filter`/`_assemble_bpf` |
| 第 4 层 | cgroup v2（资源限额） | 内存/CPU/PID 上限，钳死交换 | `cgroup.setup`/`_setup_v2`/`attach` |
| 第 5 层 | netns + iptables（网络管控） | 出/入向流量管控 | `setup_network_isolation`/`apply_iptables_rules` |

## 四、调用示例

多实例启动（端口自动分配）：

```python
from jiuwenswarm.instance_manager.config import InstanceConfig, compute_auto_port

ports = compute_auto_port(index=2)   # base + 2*1000
cfg = InstanceConfig(name="team-a", workspace="/data/team-a", ports=ports)
```

跨平台实例锁与 PID 写入：

```python
from jiuwenswarm.instance_manager.lock import InstanceLock, write_pid_file

lock = InstanceLock(path="/run/jiuwen/instance-team-a.lock")
if not lock.acquire(timeout=5.0):
    raise SystemExit("another instance is starting")
write_pid_file("/run/jiuwen/instance-team-a.pid", pid=12345, ports=ports)
```

运行态查询：

```python
from jiuwenswarm.instance_manager.status import get_instance_status, list_all_instances

status = get_instance_status("/run/jiuwen/instance-team-a.pid")
all_instances = list_all_instances()
```

沙箱策略构建与参数转换：

```python
from jiuwenbox.models.policy import SecurityPolicy, FilesystemPolicy, SyscallPolicy
from jiuwenbox.supervisor.bwrap import BwrapConfig

policy = SecurityPolicy(
    fs=FilesystemPolicy(ro=["/usr"], rw=["/workspace"]),
    syscall=SyscallPolicy(blocklist=["ptrace", "mount"]),
    # ...
)
bwrap = BwrapConfig.from_policy(policy)
args = bwrap.to_args()
```

cgroup 限额应用：

```python
from jiuwenbox.supervisor import cgroup

handle = cgroup.setup(name="sandbox-1", memory_max="512M", cpu_max="50%", pids_max=64)
cgroup.attach(handle, pid=9876)
# ...执行命令...
cgroup.teardown(handle)
```

网络隔离：

```python
from jiuwenbox.supervisor.network import setup_network_isolation

net = setup_network_isolation(
    mode="ISOLATED",
    allowed_egress_domains=["api.example.com"],
)
```

通过 MCP 工具执行命令：

```python
result = mcp.sandbox_run_command(
    command=["python", "-c", "print('hello')"],
    policy=policy,
)
```

启动 jiuwenbox 服务：

```bash
python -m jiuwenbox.server.launcher --listen 0.0.0.0:8787 --api-token "$JIUWENBOX_TOKEN"
```

## 五、业界对比

| 能力维度 | JiuwenSwarm（jiuwenbox 五层纵深） | Docker | Firejail | gVisor |
| --- | --- | --- | --- | --- |
| 隔离层数 | 5 层（bwrap+Landlock+seccomp+cgroup+net） | 容器（namespace+cgroup） | 沙箱（namespace+seccomp） | 用户态内核 |
| 命名空间 | net/ipc/cgroup/pid/uts/user 全 unshare | net/mnt/uts/ipc/pid/user | 部分 namespace | netstack 用户态 |
| syscall 过滤 | seccomp-bpf + daemon 信号守护 | seccomp 默认 profile | seccomp 黑名单 | 拦截syscall 用户态处理 |
| 资源限额 | cgroup v2 memory/cpu/pids，swap=0 | cgroup v1/v2 | 无 | 无 |
| 网络管控 | netns+veth+iptables 出入向 | netns+bridge | netns | netstack |
| 路径 ACL | Landlock beneath | 无 | 无 | 无 |
| 级联清理 | die-with-parent SIGKILL | 容器 runtime | 无 | 无 |
| 部署形态 | 单进程服务 + MCP 工具 | 守护进程 + 镜像 | 命令包装 | runtime |

## 六、小结

1. instance-manager 以 `base + index * 1000` 端口算法 + `InstanceLock` 跨平台文件锁 + `.env` 隔离实现多实例并行而互不冲突。
2. `bootstrap.py` 为每实例生成独立 `.env`（数据目录 + 端口），`--dotenv <path>` 完成配置隔离；`status.py` 聚合运行态查询与停止。
3. jiuwenbox 五层纵深防御（bwrap → Landlock → seccomp-bpf → cgroup v2 → netns+iptables）逐层收敛攻击面，每层都有明确防御目标与触发位置。
4. `die-with-parent` 级联 SIGKILL、`memory.swap.max=0` 钳死交换、`_append_daemon_signal_guard` 防 kill 基础设施 PID 等细节体现工程化安全考量。
5. 服务层 FastAPI + Bearer Token + FastMCP（DNS rebinding 防护）+ 推理隐私代理，使沙箱能力既能被 Agent 调用又对外可控鉴权。
6. 相比 Docker/Firejail/gVisor，JiuwenSwarm 以五层协同 + Landlock 路径 ACL + cgroup 钳死交换提供更细粒度的静态策略沙箱。
