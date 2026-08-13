# 编码插件热加载

> 交叉引用: [01-project-overview](../../01-project-overview.md) | [02-overall-architecture](../../02-overall-architecture.md) | [04-harness-and-deepagents-module](../../04-harness-and-deepagents-module.md) | [06-agentevolving-and-autoharness-module](../../06-agentevolving-and-autoharness-module.md)

## 一、能力概述

插件热加载指在智能体运行时,不重启进程即可加载、更新、卸载扩展资源(工具、MCP、Rail、提示片段、技能、子智能体等),使能力可随配置或目录变化动态演进。

**实现状态:部分实现。** 经源码核验,agent-core-java 当前**仅实现 SKILL 单类的热加载**,由 `SkillUseRail` 基于 SKILL.md 文件的 mtime 签名增量刷新实现;Python 版 `extension_binder` 所支持的 6 类资源(TOOL/MCP/RAIL/PROMPT_SECTION/SKILL/SUBAGENT)事务性热加载及其回滚机制,**在 Java 版未实现**:

- 全仓 Glob `**/ExtensionBinder*.java` **零命中**,不存在 `ExtensionBinder` 类。
- `DeepAgent.java` 全文(2140 行)公共方法仅 `registerHarnessTool`/`unregisterHarnessTool`/`invoke`/`stream`/`ensureInitialized`/`ensurePlanFile`/`setMode`/`steer`/`requestAbort`/`createSubagent`/`destroy`/`close`,**无** `loadPlugin`/`loadExtension`/`applyExtensionHot` 等方法。
- 不存在 `harness/resources/` 目录,无 manifest/catalog 声明式 6 类资源注册。
- 无 `applyExtensionHot`/`unapplyExtensionHot` 事务性加载与回滚入口。

因此本章如实区分"已实现(SKILL 热加载)"与"未实现(6 类资源事务性热加载)"两部分。

设计取舍:Java 版没有照搬 Python 的"6 类资源统一事务性热加载 + 回滚"模型,而是为最高频的 SKILL 资源单独实现了一条轻量增量刷新链路,挂载在 `SkillUseRail` 的模型调用前置回调上;其余 5 类资源的运行时变更目前只能通过重启进程或单点 `registerHarnessTool`/`unregisterHarnessTool` 间接完成。这一取舍降低了实现复杂度,但牺牲了 6 类资源的对等覆盖与事务性回滚能力。

能力边界速查:

| 资源类型 | Java 版运行时热加载 | 备注 |
| --- | --- | --- |
| TOOL | 未实现 | 仅 registerHarnessTool/unregisterHarnessTool 单点 |
| MCP | 未实现 | 无热加载入口 |
| RAIL | 未实现 | 无 applyExtensionHot |
| PROMPT_SECTION | 未实现 | 无 manifest/catalog |
| SKILL | 已实现 | SkillUseRail mtime 签名 + refreshIncrementally |
| SUBAGENT | 未实现 | 无 loadPlugin/loadExtension |

## 二、关键类与函数

| 类/函数 | 职责 | 位置 |
| --- | --- | --- |
| SkillUseRail | SKILL 使用 Rail,在模型调用前比对 mtime 签名触发刷新 | [SkillUseRail.java#L273](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/SkillUseRail.java#L273) |
| SkillUseRail.beforeModelCall | 重写模型调用前置回调,检测签名变化 | [SkillUseRail.java#L273](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/SkillUseRail.java#L273) |
| SkillUseRail.prepareSkills | 收集技能根并调用增量刷新 | [SkillUseRail.java#L409](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/SkillUseRail.java#L409) |
| SkillUseRail.buildCurrentSignature | 构建当前技能 mtime 签名 | [SkillUseRail.java#L457](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/SkillUseRail.java#L457) |
| SkillManager | 技能管理器,支持增量刷新 | [SkillManager.java#L228](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillManager.java#L228) |
| SkillManager.refreshIncrementally | 仅加载新增/改动,移除失效技能 | [SkillManager.java#L235](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillManager.java#L235) |
| DeepAgentSkillHotReloadExample | 演示 SKILL 热加载的示例 | [DeepAgentSkillHotReloadExample.java](file:///D:/jiuwen/main/agent-core-java/examples/skill_hot_reload/DeepAgentSkillHotReloadExample.java) |

> 未实现项:`ExtensionBinder`(不存在)、`applyExtensionHot`/`unapplyExtensionHot`(不存在)、`DeepAgent.loadPlugin`/`loadPluginSpec`/`loadAgentTemplate`/`loadHarnessConfig`(不存在)。

> Python 版对照:`extension_binder.apply_extension_hot` 支持上述 6 类资源的事务性加载,任一类失败则整体回滚;`unapply_extension_hot` 提供反向卸载;`DeepAgent.load_plugin`/`load_plugin_spec`/`load_agent_template`/`load_harness_config` 为声明式加载入口。Java 版仅在 SKILL 一类上提供了等价的增量刷新能力,其余入口均不存在。

> 判断依据:全文 Glob `**/ExtensionBinder*.java` 零命中、Grep `loadPlugin|loadExtension|applyExtensionHot|loadPluginSpec|loadAgentTemplate` 在 harness 包零命中,均经源码核验,不存在承载 6 类资源热加载的统一绑定器或事务性入口。

## 三、实现机制

### 3.1 已实现:SKILL 热加载(via SkillUseRail mtime 签名)

SKILL 是 6 类资源中唯一实现热加载的一类,机制如下:

1. **签名构建**:[SkillUseRail.buildCurrentSignature](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/SkillUseRail.java#L457) 遍历所有技能根目录,调用 `skillManager.buildSnapshotSignature(roots)` 收集每个 `SKILL.md` 的 mtime,形成 `List<Map.Entry<String, Long>>` 签名快照。

2. **变化检测**:[SkillUseRail.beforeModelCall](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/SkillUseRail.java#L273) 在每次模型调用前被回调;当 `owner` 与 `skillManager` 就绪、技能数非零、模式非 `none` 时,比对当前签名与上次快照 `skillsSnapshotSignature`。若签名相等,仅注入技能提示后返回,不做重载。

3. **增量刷新**:签名变化时调用 [prepareSkills](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/SkillUseRail.java#L409),其内部调用 [SkillManager.refreshIncrementally](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillManager.java#L235)。

4. **增量语义**:`SkillManager.refreshIncrementally` 的注释明确:"Only loads new or mtime-changed skills, removes stale skills (directories that no longer exist), and maintains traversal order"。即仅加载新增或 mtime 变化的技能、移除已不存在的目录、保持遍历顺序;mtime 取自 `SKILL.md` 文件的 [lastModified](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillManager.java#L266)。同时设有 10MB 单文件上限,超限跳过并告警。

该机制实现了"运行时不重启即可增/改/删 SKILL",但作用域仅限 SKILL 单类。

#### 3.1.1 扫描规则与排序

[refreshIncrementally](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillManager.java#L235) 的扫描规则为:遍历每个根目录下的子目录,仅当子目录内存在 `SKILL.md`(或小写 `Skill.md`)时才作为候选技能;子目录按文件名字典序排序,保证多根目录混合扫描时遍历顺序稳定;技能的缓存键取子目录绝对路径归一化字符串。这一规则使热加载行为可预测,新增技能会落在字典序对应位置而非随机插入。

#### 3.1.2 缓存开关与租户隔离

`SkillUseRail` 提供 `enableCache` 开关(默认可经 `setEnableCache` 设置)。在 [prepareSkills](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/SkillUseRail.java#L409) 内,若 `enableCache` 为 `false` 且 `skillManager` 非空,会先 `skillManager.clearAll()` 再刷新,相当于每次都全量重载;为 `true` 时则保留缓存并仅做增量比对。

租户场景下,公共 `skillManager` **不**纳入租户技能根目录的刷新范围(源码注释明确说明:若混入公共 skillManager,并发多租户请求时会互相污染公共技能列表);租户技能由独立的 `tenantSkillManager`/`overlaySkillManager` 按租户上下文单独调用 `refreshIncrementally` 加载,从而实现租户间技能隔离。

#### 3.1.3 签名稳定性与失效场景

SKILL 热加载依赖文件系统 mtime 作为变更信号,因此对 mtime 的精度与可靠性有隐含要求:在容器只读文件系统、部分网络挂载(mtime 精度不足或被缓存)或同一秒内多次修改且 mtime 粒度为秒的场景下,签名可能无法感知变化而导致漏刷新。此外,`buildCurrentSignature` 仅扫描 `SKILL.md` 的 mtime,技能目录内其他辅助文件的变更不会触发刷新,需修改 `SKILL.md` 本身(如 touch)才能被检测到。

### 3.2 未实现:6 类资源事务性热加载

Python 版 `openjiuwen/harness/extension_binder.py` 的 `apply_extension_hot` 支持对 6 类资源(TOOL、MCP、RAIL、PROMPT_SECTION、SKILL、SUBAGENT)进行**事务性热加载**:任一类失败则整体回滚,并提供 `unapply_extension_hot` 做反向卸载;`DeepAgent` 暴露 `load_plugin`/`load_plugin_spec`/`load_agent_template`/`load_harness_config` 等加载入口。

Java 版在该方向上**均未实现**:

- **无 ExtensionBinder 类**:Glob `**/ExtensionBinder*.java` 零命中,不存在承载 6 类资源热加载的统一绑定器。
- **无 applyExtensionHot/unapply 回滚**:Grep `loadPlugin|loadExtension|applyExtensionHot|loadPluginSpec|loadAgentTemplate` 在 harness 包零命中,不存在事务性加载与回滚入口。
- **无清单/目录驱动**:无 `harness/resources/` 目录,无 manifest/catalog 声明式 6 类资源注册;DeepAgent 仅提供 `registerHarnessTool`/`unregisterHarnessTool` 单点工具注册/注销,非声明式批量加载。
- **覆盖范围**:Java 版只有 6 类中的 1 类(SKILL)通过 SkillUseRail mtime 签名 + refreshIncrementally 实现;其余 5 类(TOOL/MCP/RAIL/PROMPT_SECTION/SUBAGENT)的运行时热加载缺失。

由于缺少事务性 apply/unapply,Java 版也无法做到"加载失败回滚到加载前状态":SKILL 增量刷新本身是幂等的(以 mtime 为准),但若需要在多类资源联动加载时保证原子性,当前无任何机制可用,只能由调用方在外部自行组织重试与补偿。

补充说明:即便仅看 SKILL 一类,热加载也只覆盖"加载/更新/移除"动作本身,不覆盖技能被引用期间的版本一致性——若某次模型调用已基于旧版技能生成计划,随后技能被热更新,已生成计划不会自动重做,需由调用方判断是否重跑。这是 mtime 增量刷新模型的固有边界,与 Python 版 apply/unapply 的事务性语义不同。

触发时机:SKILL 热加载的触发点固定在 `beforeModelCall`,即"模型调用前";若调用方在两次模型调用之间修改技能文件,变化会在下一次调用前生效,而非修改即刻生效。对需要"修改即重载"的实时场景,需调用方主动触发一次模型调用或显式调用刷新接口(当前 DeepAgent 未暴露独立刷新入口,刷新随 invoke 发生)。

## 四、调用示例

```java
import com.openjiuwen.harness.deep_agent.DeepAgent;
import com.openjiuwen.harness.rails.SkillUseRail;

import java.nio.file.Path;
import java.util.List;

DeepAgent agent = DeepAgent.builder()
        .workspace(Path.of("/repo/openjiuwen"))
        .skillDirectories(List.of(".trae/skills", "skills"))
        .build();

SkillUseRail rail = agent.getSkillUseRail();
rail.setEnableCache(true);

for (int i = 0; i < 3; i++) {
    agent.invoke("请使用可用技能完成任务");
}

// 在运行期间向 skills 目录新增/修改 SKILL.md,无需重启
// 下一次模型调用前 SkillUseRail.beforeModelCall 会比对 mtime 签名,
// 检测到变化后调用 SkillManager.refreshIncrementally 完成增量热加载
// 若 setEnableCache(false),则每次调用前 clearAll 全量重载
```

> 注:示例仅演示 SKILL 单类热加载。6 类资源事务性热加载因未实现,无对应 API 可调用;`DeepAgent` 上不存在 `loadPlugin`/`applyExtensionHot` 等方法。需要新增/移除工具时,只能通过 `registerHarnessTool`/`unregisterHarnessTool` 单点操作,且不会触及其他 5 类资源的联动加载或回滚。

> 验证方式:可在 `skills` 目录新增一个含 `SKILL.md` 的子目录,连续调用 `agent.invoke(...)` 两次,观察第二次调用前 `SkillUseRail.beforeModelCall` 是否检测到签名变化并触发 `refreshIncrementally`;删除该子目录后再次调用,应观察到技能被移除。此验证仅对 SKILL 有效,对其余 5 类资源无对应行为可观测。

## 五、业界对比

| 维度 | agent-core-java | Spring AI | LangChain4j | Python agent-core |
| --- | --- | --- | --- | --- |
| 运行时热加载 | 部分实现,仅 SKILL | 无内置插件热加载 | 无内置插件热加载 | 已实现,6 类资源 |
| 6 类资源 | 未实现,仅 SKILL 1 类 | 无 | 无 | 已实现,TOOL/MCP/RAIL/PROMPT_SECTION/SKILL/SUBAGENT |
| 事务性回滚 | 未实现,无 apply/unapply | 无 | 无 | 已实现,apply_extension_hot/unapply_extension_hot |
| 清单驱动 | 未实现,无 manifest/catalog | 无 | 无 | 已实现 |
| 声明式注册 | 未实现,仅 registerHarnessTool 单点 | 部分,函数式工具声明 | 部分,工具注解 | 已实现 |
| 动态卸载 | 仅 unregisterHarnessTool 单点 | 无 | 无 | 已实现,unapply 回滚 |
| SKILL 热加载 | 已实现,mtime 签名增量刷新 | 无 | 无 | 已实现,6 类之一 |

> 对比说明:Spring AI 与 LangChain4j 提供函数式/注解式工具声明,但均不提供运行时插件热加载能力,工具集在构建期固定;agent-core-java 在 SKILL 这一类上具备运行时增量热加载,领先于两者,但在 6 类资源事务性热加载上落后于 Python 版。

> 使用边界:SKILL 热加载依赖文件系统 mtime,在容器只读文件系统或网络挂载(mtime 精度不足)场景下可能失效;`enableCache=false` 时每次调用前全量重载,技能数量大时会有性能开销;租户技能依赖 `TenantContextHolder` 上下文,异步跨线程调用需确保上下文传递,否则租户技能不会加载。

## 六、小结

agent-core-java 在插件热加载上处于"部分实现"状态:SKILL 单类通过 [SkillUseRail](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/harness/rails/SkillUseRail.java#L273) 的 mtime 签名比对 + [SkillManager.refreshIncrementally](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillManager.java#L235) 增量刷新,实现了运行时不重启的增/改/删,并辅以缓存开关与租户隔离;但 Python 版 `extension_binder` 的 6 类资源事务性热加载与回滚在 Java 版整体缺失,不存在 `ExtensionBinder` 类、`applyExtensionHot`/`unapplyExtensionHot` 入口,也无清单/目录驱动的声明式注册。

演进建议:若要补齐与 Python 版的对等,需引入统一的 `ExtensionBinder` 与 6 类资源的事务性 apply/unapply 入口,并提供 manifest/catalog 声明式注册机制;在补齐前,对 TOOL/MCP/RAIL/PROMPT_SECTION/SUBAGENT 的运行时变更,当前只能通过重启进程或单点 `registerHarnessTool`/`unregisterHarnessTool` 间接实现。在过渡期内,对 SKILL 资源可放心依赖热加载,对其余 5 类资源仍需以"重启生效"为约定,并在多类资源联动更新时由调用方自行保证一致性。

可观测性:SKILL 热加载的刷新日志经 `Loggers.AGENT.debug` 输出 "refreshIncrementally completed in {} ms, skills count: {}",可通过调高技能管理器日志级别观察刷新耗时与技能数变化,作为热加载是否生效的旁证;但无针对 6 类资源的统一加载审计日志,其余 5 类资源的加载/卸载无任何运行时痕迹可查。

小结判断:agent-core-java 的插件热加载能力可概括为"1/6 已实现、无事务性回滚、无清单驱动",在 SKILL 资源上达到生产可用,在其余 5 类资源上仍为重启生效模型,跨语言对等尚需补齐 ExtensionBinder 与 6 类 apply/unapply。
