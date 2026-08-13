# agentteams 模块：多代理团队框架

> 交叉引用：[01-project-overview](01-project-overview.md) | [02-overall-architecture](02-overall-architecture.md) | [04-harness-and-deepagents-module](04-harness-and-deepagents-module.md) | [06-agentevolving-and-autoharness-module](06-agentevolving-and-autoharness-module.md)

## 一、模块职责

`com.openjiuwen.agentteams` 是 agent-core-java 的**多 agent 团队框架**，采用 **Leader-Teammate 模型**组织协作。它镜像 Python `openjiuwen.agentteams`，遵循 AGENTS.md 的两条铁律：

1. **`TeamAgent` 单实现服务双角色**：Leader 与 Teammate 由同一个 `TeamAgent` 类承担，运行时由 `TeamRole` 切换，不拆成两个类。
2. **`CoordinatorLoop` 不做决策**：协调循环只负责“唤醒 + 轮询”，所有业务逻辑落在 `EventDispatcher`（即 7 个 coordination handlers）与 team tools 中。

模块职责可归纳为四块：

- **声明式入口**：`LeaderTeammateAgentTeam` 提供 Builder 与 `fromSpec`，惰性构建 TeamAgent 并委托 `TeamFactory`。
- **运行时宿主**：`TeamAgent` 承载 Leader/Teammate 双角色，负责 `configure` / `dispatchTask` / `stream`。
- **数据与消息枢纽**：`TeamBackend` 提供进程级共享 DB 单例、成员 spawn/sync、状态更新与完成判定。
- **协调内核**：`CoordinationKernel` + 7 个 handler 做事件分发，通过 EventBus 唤醒与周期轮询。

此外，`I18n` 提供进程级 CN/EN 国际化，`TeamPaths` 统一团队目录路径。

## 二、关键类与函数

| 类 / 函数 | 文件位置 | 说明 |
| --- | --- | --- |
| [LeaderTeammateAgentTeam](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/LeaderTeammateAgentTeam.java#L26) | `agentteams/LeaderTeammateAgentTeam.java` | 声明式门面；Builder L463-735；`build` L179 注入默认 Leader；`agent` L194 惰性构建 TeamAgent 委托 `TeamFactory.createAgentTeam` L149；`fromSpec` L169 |
| [TeamAgent](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/agent/TeamAgent.java#L81) | `agentteams/agent/TeamAgent.java` | 运行时宿主 `implements DispatcherHost`；`configure` L112、`dispatchTask` L253、`stream` L313；`payloadRole` L1813-1824（LEADER→"leader"、HUMAN_AGENT→"human_agent"、USER→"user"、else→"teammate"）；`buildMemberContext` L1819-1823（非 Leader 降为 MEMBER） |
| [TeamBackend](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/tools/TeamBackend.java#L51) | `agentteams/tools/TeamBackend.java` | 数据/消息枢纽；`getSharedDb` L236-246（进程级共享 DB 单例，按 `dbType::connectionString` 键控）；`spawnMember` L307、`syncMembers` L514、`updateMemberStatus` L830、`isTeamCompleted` L714（三条件判定）、`cleanTeam` L1271、`publishTeamEvent` L1410 |
| [TeamRole](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/schema/team/TeamRole.java#L12) | `agentteams/schema/team/TeamRole.java` | 枚举 LEADER / TEAMMATE（MEMBER→"teammate"）/ HUMAN_AGENT / USER；`value` L29 |
| [CoordinationKernel](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/agent/coordination/CoordinationKernel.java#L48) | `agentteams/agent/coordination/CoordinationKernel.java` | 协调内核；`start` L163（绑 `dispatch` 为 EventBus 唤醒回调）、`enqueueUserInput` L188、`enqueuePollMailbox` L198、`dispatch` L114（粗粒度过滤→`framework.trigger`）、`pausePolls` / `resumePolls` L216-225 |
| DispatcherHost / PollController | `agentteams/agent/coordination/` | `TeamAgent implements DispatcherHost`；PollController 控制轮询节奏的窄协议接口 |
| [BaseCoordinationHandler](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/agent/coordination/handlers/BaseCoordinationHandler.java#L35) | `agentteams/agent/coordination/handlers/BaseCoordinationHandler.java` | 抽象 handler；`getCallbacks` L82-84 注册到框架；7 个 handler：AgentLifecycleHandler / MemberHandler / MessageHandler / TaskBoardHandler / StaleTaskHandler / TeamCompletionHandler / WorkflowHandler（注册顺序见 CoordinationKernel L89-97） |
| [I18n](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/I18n.java#L21) | `agentteams/I18n.java` | 进程级国际化 CN/EN；`t` L293 |
| [TeamPaths](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/TeamPaths.java#L20) | `agentteams/TeamPaths.java` | 团队目录路径；`teamHome` L90 |

## 三、核心机制

### 3.1 TeamAgent 单实现双角色

[TeamAgent](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/agent/TeamAgent.java#L81) `implements DispatcherHost`，是 Leader 与 Teammate 共用的运行时宿主。角色切换由 [TeamRole](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/schema/team/TeamRole.java#L12) 决定，`payloadRole`（L1813-1824）把角色映射为消息载荷字符串：

- `LEADER` → `"leader"`
- `HUMAN_AGENT` → `"human_agent"`
- `USER` → `"user"`
- 其余 → `"teammate"`

`buildMemberContext`（L1819-1823）在非 Leader 场景把角色降为 MEMBER（即 `"teammate"`），确保 Teammate 之间上下文对等。`configure`（L112）完成宿主装配，`dispatchTask`（L253）/`stream`（L313）对外暴露任务派发与流式输出。

### 3.2 TeamBackend 共享 DB 单例

[TeamBackend](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/tools/TeamBackend.java#L51) 是团队的数据与消息枢纽。`getSharedDb`（L236-246）按 `dbType::connectionString` 键控返回进程级共享 DB 单例——这意味着 Teammate 无需显式调用 `shareDb`，同一连接串下天然共享状态。核心方法：

- `spawnMember`（L307）：孵化新成员并写入 backend；
- `syncMembers`（L514）：同步成员清单与状态；
- `updateMemberStatus`（L830）：CAS 状态机迁移成员状态；
- `isTeamCompleted`（L714）：完成判定，见 3.4；
- `cleanTeam`（L1271）：团队收尾清理；
- `publishTeamEvent`（L1410）：发布团队事件，驱动 EventBus。

### 3.3 CoordinatorLoop / EventDispatcher 职责分离

[CoordinationKernel](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/agent/coordination/CoordinationKernel.java#L48) 是协调内核，遵循“不做决策只唤醒+轮询”：

- `start`（L163）：把 `dispatch` 绑定为 EventBus 唤醒回调；
- `enqueueUserInput`（L188）/`enqueuePollMailbox`（L198）：把外部输入与轮询请求入队；
- `dispatch`（L114）：粗粒度过滤后调用 `framework.trigger`，不解释事件语义；
- `pausePolls` / `resumePolls`（L216-225）：暂停/恢复周期轮询。

真正做业务的是 7 个 coordination handler，均继承 [BaseCoordinationHandler](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/agent/coordination/handlers/BaseCoordinationHandler.java#L35)，通过 `getCallbacks`（L82-84）注册到框架。注册顺序固定（CoordinationKernel L89-97）：

| 顺序 | Handler | 职责 |
| --- | --- | --- |
| 1 | AgentLifecycleHandler | 代理生命周期事件 |
| 2 | MemberHandler | 成员增删与状态 |
| 3 | MessageHandler | 消息收发 |
| 4 | TaskBoardHandler | 任务板更新 |
| 5 | StaleTaskHandler | 过期任务回收 |
| 6 | TeamCompletionHandler | 团队完成判定 |
| 7 | WorkflowHandler | 工作流事件 |

内核只持有 `AgentRoundController` / `TeamLifecycleController` / `PollController` 三个**窄协议**接口，避免协调层耦合业务细节。

### 3.4 CAS 状态机与完成判定

成员状态迁移用 CAS 状态机（`tryTransitionMemberStatus`），保证并发下“中断态→终态”等迁移不发生漂移。团队完成判定 `isTeamCompleted`（L714）必须同时满足三条件：

1. **任务全终态**：所有任务流转到终态；
2. **成员全 settle**：所有成员状态 settle；
3. **无未读**：成员间无未读消息。

三条件任一不满足则团队继续运行，CoordinatorLoop 周期轮询复检。

### 3.5 调用链

从声明式入口到协调内核的完整调用链：

```
LeaderTeammateAgentTeam.builder().teamName(...).build()   // L179 注入默认 Leader
  └─ agent() (L194) 惰性
     └─ TeamFactory.createAgentTeam (L149)
        └─ new TeamAgent().configure (L112)
           └─ bootstrapCoordinationHost:
              ├─ buildMessager
              ├─ initializeTeamBackend        // TeamBackend 共享 DB 单例
              ├─ initializeCoordinationManagers
              └─ initializeCoordinationKernel // 绑 7 handlers (L89-97)
           └─ setupAgent:
              ├─ registerTeamTools
              └─ createTeamDeepAgent
dispatchTask (L253)
  └─ agent().dispatchTask
     └─ coordinationManager.handoffUserInput
        └─ coordinationKernel.start (L163) / enqueueUserInput (L188)
```

## 四、调用示例

```java
import com.openjiuwen.agentteams.LeaderTeammateAgentTeam;
import com.openjiuwen.agentteams.agent.TeamAgent;
import com.openjiuwen.agentteams.schema.team.TeamRole;

// 1. 声明式构建团队（Builder L463-735），build() 注入默认 Leader
LeaderTeammateAgentTeam team = LeaderTeammateAgentTeam.builder()
        .teamName("demo-team")
        .workspacePath("/workspace/demo")
        .addTeammate("explorer", "explore_agent")
        .addTeammate("coder", "code_agent")
        .addTeammate("verifier", "verification_agent")
        .build();                          // L179

// 2. 惰性获取 TeamAgent 宿主（双角色，运行时由 TeamRole 切换）
TeamAgent leader = (TeamAgent) team.agent();   // L194

// 3. 派发任务：经 coordinationManager → CoordinationKernel.enqueueUserInput
leader.dispatchTask("为模块 X 补充单测并跑 mvn test");   // L253

// 4. 流式接收 Leader 输出
leader.stream("继续推进").forEach(System.out::println);   // L313

// 5. Teammate 侧：同一 TeamAgent 实现，由 TeamRole.TEAMMATE 切换
//    payloadRole() 返回 "teammate"；buildMemberContext() 降为 MEMBER
```

基于 `fromSpec` 的快速构建：

```java
// 从已有规格反序列化构建（L169）
LeaderTeammateAgentTeam team = LeaderTeammateAgentTeam.fromSpec(specJson);
TeamAgent agent = (TeamAgent) team.agent();
agent.configure();                          // L112 完成宿主装配
agent.dispatchTask("...");                  // L253
```

## 五、与 Python agent-core 对照

| 维度 | Java | Python | 差异说明 |
| --- | --- | --- | --- |
| 团队框架 | `com.openjiuwen.agentteams` | `openjiuwen.agentteams` | 模块对等，Leader-Teammate 模型一致 |
| 单实现双角色 | [TeamAgent](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/agent/TeamAgent.java#L81) 由 [TeamRole](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/schema/team/TeamRole.java#L12) 切换 | TeamAgent 单实现双角色 | 完全对等；Java 用 `payloadRole` L1813-1824 映射载荷字符串 |
| 共享 DB | [TeamBackend](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/tools/TeamBackend.java#L51) `getSharedDb` L236-246 | `get_shared_db` | 均进程级单例；Java 按 `dbType::connectionString` 键控，Teammate 无需显式 shareDb |
| 协调循环 | [CoordinationKernel](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/agent/coordination/CoordinationKernel.java#L48) + 7 handlers | coordinator loop | 职责分离对等：Java 显式 7 handler 固定注册顺序（L89-97） |
| 完成判定 | `isTeamCompleted` L714 三条件 | 三条件判定 | 完全对等：任务全终态 / 成员全 settle / 无未读 |
| 状态迁移 | `tryTransitionMemberStatus` CAS | CAS 状态机 | CAS 语义对等 |
| 协议窄化 | 三窄协议：AgentRoundController / TeamLifecycleController / PollController | 窄协议 | 均限制协调层耦合面 |
| 声明式入口 | [LeaderTeammateAgentTeam](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/LeaderTeammateAgentTeam.java#L26) Builder + `fromSpec` | 声明式 Builder | Builder 与 `fromSpec` 对等 |

## 六、小结

agentteams 模块在 core 引擎与 harness 编码代理之上，构建了 Leader-Teammate 多代理团队。它严格遵循两条铁律：[TeamAgent](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/agent/TeamAgent.java#L81) 单实现由 [TeamRole](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/schema/team/TeamRole.java#L12) 切换双角色；[CoordinationKernel](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/agent/coordination/CoordinationKernel.java#L48) 只唤醒+轮询，业务由 7 个 handler 与 team tools 承担。[TeamBackend](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/tools/TeamBackend.java#L51) 的共享 DB 单例让 Teammate 天然共享状态，CAS 状态机与三条件完成判定保证并发收敛。整个模块对 Python `openjiuwen.agentteams` 做了对等镜像，是理解 agent-core-java 多代理协作的关键。
