# 工具权限与安全防护

> 交叉引用: [01-项目概述](../01-project-overview.md) | [02-整体架构](../02-overall-architecture.md) | [08-common与e2a](../08-common-e2a-and-security-module.md) | [09-instance-manager与jiuwenbox](../09-instance-manager-and-jiuwenbox-module.md) | [特性索引](README.md)

## 一、能力概述

JiuwenSwarm 把"每步可控"作为安全基线:在 agent 调用任何工具前后,系统都能介入审批、白名单过滤与敏感操作拦截。这一能力覆盖三个层次——**工具预执行审批**(用户在工具执行前授权)、**文件访问白名单**(区分无状态共享工具与 agent 私有工具)、**敏感操作拦截**(命令 hook 与生命周期 hook 在危险动作前阻断)。

在工程上,这套安全体系是多层的:openjiuwen 的 `SecurityRail`/`PermissionInterruptRail` 负责工具预执行中断与"总是允许"持久化;`UserHookRail` 把用户配置的 hooks 以 Rail 形态挂到 DeepAgent,拦截 `before_tool_call`/`after_tool_call`;命令 hook 以 exit code 2 表示 blocking;`tool_ownership` 标记 stateless 共享 vs agent-owned;`is_allowed_browser_origin` 防跨站 WebSocket 劫持;jiuwenbox 五层沙箱(bwrap/Landlock/seccomp/cgroup/netns)+ Bearer 鉴权兜底执行隔离。

特别地,Swarm 场景下 headless teammate(无人值守的成员 agent)不能挂 `PermissionInterrupt`,否则会在 ASK 权限时死锁——因为没有人类在场确认。因此本能力为团队场景设计了 `TEAM_PERMISSION`/`TEAM_PERMISSION_POLICY` 双轨:teammate 持 `TEAM_PERMISSION` 走 leader 中介提交,leader 持 `TEAM_PERMISSION_POLICY` 做权限策略注入,从而在无人值守下仍保持权限边界。

## 二、关键类与函数

| 类/函数 | 文件位置 | 说明 |
| --- | --- | --- |
| PermissionInterruptRail | [__init__.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/common/rails/__init__.py#L8) | 安全/权限中断 rail,经 ensure_harness_elements_registered 注册,拦截工具调用做审批 |
| build permission rail | [interrupt_helpers.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/common/rails/interrupt/interrupt_helpers.py#L366) | 构建 PermissionInterruptRail,含 tool_names 白名单与"总是允许"回调 |
| TEAM_PERMISSION_POLICY / TEAM_PERMISSION | [config_specs.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/config_specs.py#L364) | leader 权限策略注入 rail / teammate ASK 权限 rail(leader 中介) |
| _role_evolution_rails | [config_specs.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/config_specs.py#L438) | 角色演进 rail,teammate 装权限受限提交 rail |
| _build_team_capability_specs | [config_specs.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/config_specs.py#L459) | 按 enable_permissions 切换 team 权限 rail 与 PERMISSION_INTERRUPT |
| tool_ownership | [tool_ownership.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/tool_ownership.py) | stateless 共享 vs agent-owned 归属管理 |
| mark_stateless | [tool_ownership.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/tool_ownership.py#L37) | 标记工具为无状态共享,多 agent 可共用不串状态 |
| register_tool / unregister_tool | [tool_ownership.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/tool_ownership.py#L75) | 注册/注销工具归属生命周期 |
| is_allowed_browser_origin | [ws_origin.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/security/ws_origin.py#L30) | 浏览器 Origin 白名单校验,防跨站 WS 劫持 |
| CryptoProvider | [base_crypto.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/security/base_crypto.py) | 加密 Provider 协议,实现可插拔 |
| UserHookRail | [user_hook_rail.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/hooks/user_hook_rail.py#L18) | 用户 hooks Rail,拦截 before/after_tool_call,priority=60 |
| HookExecutor._run_command_hook | [executor.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/hooks/executor.py#L60) | command hook 执行,exit 2=blocking |
| BwrapConfig | [bwrap.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenbox/src/jiuwenbox/supervisor/bwrap.py#L77) | SecurityPolicy→bwrap CLI 参数,命名空间与挂载隔离 |
| SecurityPolicy | [policy.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenbox/src/jiuwenbox/models/policy.py#L736) | 完整静态沙箱策略:fs/process/namespace/cap/landlock/syscall/network/cgroup |
| BearerTokenAuthMiddleware | [auth.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenbox/src/jiuwenbox/server/auth.py#L42) | Bearer 鉴权,hmac.compare_digest 防时序攻击 |
| build_seccomp_filter | [seccomp.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenbox/src/jiuwenbox/supervisor/seccomp.py#L274) | SyscallPolicy→二进制 BPF 过滤器,拦截危险 syscall |

## 三、实现机制

### 1. 工具预执行审批

工具预执行审批由 openjiuwen 的 `SecurityRail`/`PermissionInterruptRail` 承担。它在工具真正执行前中断 agent 循环,把审批请求抛回给用户(或前端),由用户选择"允许/拒绝/总是允许"。`build permission rail`([interrupt_helpers.py#L366](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/harness/common/rails/interrupt/interrupt_helpers.py#L366))按 `tool_names` 白名单构建 rail,并在用户选"总是允许"时经回调持久化允许规则。

Swarm 场景的关键约束:**headless teammate 不挂 `PERMISSION_INTERRUPT`**。因为 teammate 是无人值守的,若挂了中断 rail,会在 ASK 权限时死锁——没有人类在场确认。为此,`_build_team_capability_specs`([config_specs.py#L459](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/config_specs.py#L459))在 `enable_permissions=True` 时走团队权限双轨:teammate 装 `TEAM_PERMISSION`([config_specs.py#L493](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/config_specs.py#L493))走 leader 中介提交,leader 装 `TEAM_PERMISSION_POLICY`([config_specs.py#L501](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/agents/swarm/config_specs.py#L501))做权限策略注入,从而在无人值守下仍保持权限边界,不死锁。

`PermissionInterruptRail` 还支持"总允许"持久化:当用户选择"总是允许"某工具时,openjiuwen 经 `ToolPermissionHost.persist_allow_rule` 把允许规则落盘,后续同名工具调用不再中断,提升流畅度。这一持久化经 `permissions_persist` 与 `owner_scopes` 协同,保证允许规则按 owner 作用域生效,不串到其他 agent。

### 1.1 Rail 优先级编排

各 Rail 按 priority 严格排序,保证安全检查顺序确定:`SecurityRail` priority=80 最先执行,`UserHookRail` priority=60 随后(在安全检查后、流式事件发送前),`JiuSwarmStreamEventRail` priority=50 最后。这一编排确保:安全审批先于用户 hook,用户 hook 先于流式下发,任何阻断在流式事件发出前完成,避免"已推送又被回滚"的不一致。headless teammate 因不挂 `SecurityRail`,其工具调用改由 leader 经 `TEAM_PERMISSION` 中介审核,形成"无人值守但有中介"的等价安全语义。

### 2. 文件访问白名单(工具归属)

`tool_ownership`([tool_ownership.py](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/tool_ownership.py))区分两类工具:

- **stateless 共享工具**:经 `mark_stateless`([tool_ownership.py#L37](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/tool_ownership.py#L37))标记,可在多 agent 间共享而不串状态,无需拷贝状态即可复用,显著降低多实例调度开销。
- **agent-owned 私有工具**:经 `register_tool`([tool_ownership.py#L75](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/tool_ownership.py#L75))绑定 owner,生命周期由该 agent 管理,访问范围限于归属工具。

这一归属机制是文件白名单的语义基础:模块级单例工具被标记 stateless 后,其访问范围被限定为"只读共享资源";agent-owned 工具则只能访问其归属范围内的文件。`register_tool`/`unregister_tool` 管理生命周期,保证工具创建与销毁对称。

### 3. 敏感操作拦截

`UserHookRail`([user_hook_rail.py#L18](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/hooks/user_hook_rail.py#L18))把用户配置的 hooks 以 Rail 形态注册到 DeepAgent,priority=60(在 SecurityRail=80 之后,JiuSwarmStreamEventRail=50 之前,确保安全检查先于用户 hook)。它拦截 `before_tool_call`(PRE_TOOL_USE)与 `after_tool_call`(POST_TOOL_USE),按 `HooksConfig.match` 匹配工具名触发用户 hook。

命令 hook 由 `HookExecutor._run_command_hook`([executor.py#L60](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/server/hooks/executor.py#L60))执行,约定 **exit code 2 = blocking**:子进程退出码为 2 时表示该操作被阻断,executor 从 stdout JSON 取 reason(回退到 stderr),产出 `HookResult`(BLOCKING)。这一约定让用户可以用任意脚本(非 LLM)做敏感操作拦截,而不必依赖 LLM 判断,降低误判风险。

### 4. WS Origin 白名单

`is_allowed_browser_origin`([ws_origin.py#L30](file:///D:/jiuwen/main/jiuwenswarm/jiuwenswarm/common/security/ws_origin.py#L30))依据环境变量配置的 Origin 白名单校验浏览器来源:origin 为 None 时按是否含 "none" 决定;非空时解析 hostname 与白名单比对。这一层防止跨站 WebSocket 劫持(CSWSH),是 WS 接入的第一道来源校验。`CryptoProvider` 协议定义可插拔的加解密入口,统一密钥管理。

### 5. 沙箱五层纵深 + Bearer 鉴权

执行层由 jiuwenbox 提供五层纵深防御兜底:`BwrapConfig`([bwrap.py#L77](file:///D:/jiuwen/main/jiuwenswarm/jiuwenbox/src/jiuwenbox/supervisor/bwrap.py#L77))由 `SecurityPolicy`([policy.py#L736](file:///D:/jiuwen/main/jiuwenswarm/jiuwenbox/src/jiuwenbox/models/policy.py#L736))构建,负责命名空间与挂载隔离;Landlock 做路径 beneath ACL;`build_seccomp_filter`([seccomp.py#L274](file:///D:/jiuwen/main/jiuwenswarm/jiuwenbox/src/jiuwenbox/supervisor/seccomp.py#L274))由 SyscallPolicy 生成 BPF 过滤危险 syscall;cgroup v2 限额(memory/cpu/pids,swap=0);netns+iptables 管控网络。全部对外接口经 `BearerTokenAuthMiddleware`([auth.py#L42](file:///D:/jiuwen/main/jiuwenswarm/jiuwenbox/src/jiuwenbox/server/auth.py#L42))鉴权,用 `hmac.compare_digest` 做常量时间比较防时序攻击。

### 5.1 沙箱防反噬细节

沙箱设计的工程化考量体现在若干"防反噬"细节:`--die-with-parent` 设置 `PR_SET_PDEATHSIG=SIGKILL`,父进程退出时级联杀掉沙箱,杜绝孤儿 daemon;`_append_daemon_signal_guard`([seccomp.py#L223](file:///D:/jiuwen/main/jiuwenswarm/jiuwenbox/src/jiuwenbox/supervisor/seccomp.py#L223))拦截 `kill`/`tkill`/`tgkill` 针对基础设施 PID 的调用,防止沙箱内进程杀死 jiuwenbox 自身;`memory.swap.max=0` 钳死交换,防内存型攻击把宿主 swap 耗尽;Landlock payload 显式排除 `/jiuwenbox` 自身路径,避免沙箱回打基础设施。这些细节把"沙箱可能反噬宿主"的攻击面逐项收敛,是 jiuwenbox 区别于普通容器沙箱的关键。

### 5.2 五层协同

| 层 | 机制 | 防御目标 | 触发位置 |
| --- | --- | --- | --- |
| 第 1 层 | bwrap(命名空间+bind+die-with-parent) | 进程/网络/挂载隔离,防孤儿 daemon | `BwrapConfig.to_args` 构建启动参数 |
| 第 2 层 | Landlock(路径 beneath ACL) | 路径级读写执行控制 | `encode_landlock_payload`+沙箱内启动器 |
| 第 3 层 | seccomp-bpf(syscall 过滤) | 危险 syscall 拦截,防 kill 基础设施 | `build_seccomp_filter`/`_assemble_bpf` |
| 第 4 层 | cgroup v2(资源限额) | 内存/CPU/PID 上限,钳死交换 | `cgroup.setup`/`_setup_v2`/`attach` |
| 第 5 层 | netns+iptables(网络管控) | 出/入向流量管控 | `setup_network_isolation`/`apply_iptables_rules` |

这五层与接入层的 WS Origin、工具归属、预审批形成"接入→编排→执行"的全链路纵深:接入层防来源伪造,编排层防工具越权,执行层防命令反噬。三者协同使 JiuwenSwarm 在"让 agent 自由调用工具"与"每步可控"之间取得平衡。

## 四、调用示例

### 4.1 WS Origin 校验

```python
from jiuwenswarm.common.security.ws_origin import is_allowed_browser_origin

if not is_allowed_browser_origin(origin="https://app.example.com"):
    close_ws(code=1008, reason="origin not allowed")   # ws_origin.py#L30
```

### 4.2 工具归属管理(白名单语义)

```python
from jiuwenswarm.common.tool_ownership import register_tool, mark_stateless, unregister_tool

register_tool("web_search", owner="agent-1")          # tool_ownership.py#L75
mark_stateless(["web_search"])                         # 标记为无状态共享,#L37
unregister_tool("web_search", owner="agent-1")         # 注销
```

### 4.3 用户 hook 阻断敏感操作

```python
# UserHookRail(user_hook_rail.py#L18) 拦截 before_tool_call
# command hook exit 2 = blocking(executor.py#L60, #L120)
# config.yaml:
#   hooks:
#     PreToolUse:
#       - matcher: "bash"
#         hooks:
#           - type: command
#             command: ["./check-dangerous.sh"]   # 退出码 2 即阻断
```

### 4.4 Swarm 团队权限双轨(headless 防死锁)

```python
# config_specs.py#L459 _build_team_capability_specs(enable_permissions=True)
# teammate 装 TEAM_PERMISSION(config_specs.py#L493) → ASK 走 leader 中介
# leader 装 TEAM_PERMISSION_POLICY(config_specs.py#L501) → 权限策略注入
# headless teammate 不挂 PERMISSION_INTERRUPT,避免无人值守死锁
```

### 4.5 沙箱执行敏感命令

```python
from jiuwenbox.models.policy import SecurityPolicy
from jiuwenbox.supervisor.bwrap import BwrapConfig
from jiuwenbox.supervisor.seccomp import build_seccomp_filter

policy = SecurityPolicy(...)                            # policy.py#L736
args = BwrapConfig.from_policy(policy).to_args()        # bwrap.py#L77
bpf = build_seccomp_filter(policy.syscall)              # seccomp.py#L274
# 经 BearerTokenAuthMiddleware(auth.py#L42) 鉴权后执行
```

### 4.6 cgroup 限额与网络隔离

```python
from jiuwenbox.supervisor import cgroup
from jiuwenbox.supervisor.network import setup_network_isolation

# cgroup v2 限额:钳死内存/CPU/PID 与交换
handle = cgroup.setup(name="sandbox-1", memory_max="512M",
                      cpu_max="50%", pids_max=64)        # memory.swap.max=0
cgroup.attach(handle, pid=9876)
# 网络隔离:HOST 模式跳过,ISOLATED 模式创建 veth+iptables
net = setup_network_isolation(mode="ISOLATED",
                             allowed_egress_domains=["api.example.com"])
# 命名空间内出/入向 iptables 自动探测 iptables/nft/legacy 后端
```

### 4.7 启动 jiuwenbox 服务

```bash
# launcher.main 是 CLI 入口,支持 --listen 与 --api-token
python -m jiuwenbox.server.launcher --listen 0.0.0.0:8787 \
  --api-token "$JIUWENBOX_TOKEN"
# BearerTokenAuthMiddleware(auth.py#L42) 用 hmac.compare_digest 校验 token
# FastMCP 带 DNS rebinding 防护,暴露 sandbox_run_command 工具供 agent 调用
```

## 五、业界对比

| 维度 | JiuwenSwarm | Claude Code | OpenAI Codex | Cursor |
| --- | --- | --- | --- | --- |
| 预审批 | PermissionInterruptRail 工具前中断+总允许持久化 | hooks 拦截 | 不内置 | 权限确认 |
| 文件白名单 | tool_ownership stateless 共享 vs agent-owned | 工作区范围 | 沙箱范围 | 项目范围 |
| 沙箱层数 | 5 层(bwrap/Landlock/seccomp/cgroup/netns) | 无原生沙箱 | sandbox 容器 | 无原生沙箱 |
| 敏感拦截 | UserHookRail+command hook exit 2=blocking | hooks | 不内置 | 不内置 |
| 无人值守 | TEAM_PERMISSION 双轨防 headless 死锁 | 不适用 | 不适用 | 不适用 |
| 鉴权 | Bearer+hmac.compare_digest 防时序 | 无 | 无 | 无 |
| WS 来源 | is_allowed_browser_origin 白名单 | 无 | 无 | 无 |

JiuwenSwarm 的差异化在于"预审批 + 工具归属 + 多层拦截 + 沙箱兜底"的纵深组合:它不仅像 Claude Code 那样做 hooks 拦截,还用 `PermissionInterruptRail` 做工具前中断与"总允许"持久化;不仅像 Codex 那样做 sandbox,还用 jiuwenbox 五层纵深(含 Landlock 路径 ACL 与 cgroup 钳死交换)做更细粒度的静态策略隔离。尤其 Swarm 场景的 `TEAM_PERMISSION` 双轨设计,解决了竞品普遍回避的"无人值守 agent 权限边界"问题,使群体协作在不死锁的前提下仍保持每步可控。

## 六、小结

1. 工具权限与安全防护以"每步可控"为基线,覆盖工具预执行审批、文件访问白名单、敏感操作拦截三层,并以多层安全(WS Origin、工具归属、沙箱隔离)兜底。
2. 工具预执行审批由 `PermissionInterruptRail` 承担,做工具前中断与"总允许"持久化;Swarm 场景下 headless teammate 不挂 `PERMISSION_INTERRUPT` 以防 ASK 死锁,改走 `TEAM_PERMISSION`/`TEAM_PERMISSION_POLICY` 双轨,leader 中介提交。
3. 文件白名单由 `tool_ownership` 提供语义基础:`mark_stateless` 标记无状态共享工具,`register_tool` 绑定 agent-owned 私有工具,限定访问范围。
4. 敏感操作拦截由 `UserHookRail`(priority=60)拦截 before/after_tool_call,命令 hook 经 `_run_command_hook` 执行,**exit 2 = blocking**,允许用任意脚本做拦截,降低 LLM 误判。
5. 多层安全:`is_allowed_browser_origin` 防 CSWSH,`CryptoProvider` 加密协议,jiuwenbox 五层沙箱(bwrap/Landlock/seccomp/cgroup/netns)+ Bearer 鉴权(`hmac.compare_digest`)兜底执行隔离。
6. 相对竞品,本特性以"预审批 + 工具归属 + 多层拦截 + 五层沙箱 + 无人值守双轨"形成纵深防御差异化,使群体协作在不死锁前提下仍保持每步可控。
