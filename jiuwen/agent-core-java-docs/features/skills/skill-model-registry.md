# 技能元数据与注册表

> 交叉引用: [README](./README.md) | [SkillUtil 封装](./skill-prompt-facade.md) | [Overlay 覆盖](./overlay-hot-reload.md)

## 一、能力概述

`Skill` 是技能的轻量元数据对象（名称/描述/目录/更新时间），`SkillManager` 是本地技能注册表，负责扫描目录、读取 `SKILL.md` front matter 的 description、查询/注销、增量刷新（仅加载新增或 mtime 变更、清理失效、维持遍历顺序）以及受信根目录外的路径安全校验。这是整个 skills 体系的「加载层」。

## 二、关键类与函数

### Skill — 元数据载体

| 项 | 位置 | 说明 |
|----|------|------|
| 类声明 | [Skill.java](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/Skill.java#L21) | `public class Skill`，Lombok @Data/@Builder |
| name | [L22](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/Skill.java#L22) | 技能名称（取目录名，非 front matter name） |
| description | [L23](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/Skill.java#L23) | 取自 SKILL.md front matter description |
| directory | [L24](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/Skill.java#L24) | 技能目录 |
| updateAt | [L25](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/Skill.java#L25) | 更新时间戳，默认 0 |
| toString | [L35](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/Skill.java#L35) | 多行表示 |
| toRepr | [L46](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/Skill.java#L46) | 紧凑单行表示，描述截断 30 字符 |

### SkillManager — 注册表/发现/增量/安全

| 项 | 位置 | 说明 |
|----|------|------|
| 类声明 | [SkillManager.java](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillManager.java#L36) | `public class SkillManager` |
| registry | [L37](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillManager.java#L37) | 技能名→Skill 注册表 |
| updateAtCache | [L44](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillManager.java#L44) | 目录→mtime 缓存 |
| skillOrder | [L51](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillManager.java#L51) | 目录遍历顺序 |
| register(path,sid,overwrite) | [L93](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillManager.java#L93) | 从字符串路径注册（0.1.7） |
| register(path,root,sid,ow) | [L114](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillManager.java#L114) | 受信根内注册（0.1.13） |
| resolveSafeSkillPath | [L127](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillManager.java#L127) | 校验路径真实位于 skillsRoot 内 |
| refreshIncrementally | [L235](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillManager.java#L235) | 增量刷新：新增/mtime 变更加载，失效移除 |
| getAllInOrder | [L326](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillManager.java#L326) | 按目录顺序返回去重列表 |
| buildSnapshotSignature | [L356](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillManager.java#L356) | 目录+mtime 快照签名 |
| clearAll | [L387](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillManager.java#L387) | 清空注册表/缓存/顺序 |
| registerRoot | [L413](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillManager.java#L413) | 扫描目录树注册 SKILL.md |
| createSkillFromPath | [L476](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillManager.java#L476) | 从路径构建 Skill |
| loadDescription | [L503](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillManager.java#L503) | 解析 front matter description |
| parseBlockScalar | [L549](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillManager.java#L549) | 解析 `\|`/`|-`/`>`/`>-` 块标量 |
| unregister | [L696](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillManager.java#L696) | 按名注销 |
| get / getAll / count | [L707](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillManager.java#L707) / [L717](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillManager.java#L717) / [L757](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/singleagent/skills/SkillManager.java#L757) | 查询/全量/计数 |

## 三、实现机制

1. **发现**：`register` 接受单个 skill 目录或 skills 根目录；根目录时 `registerRoot` 扫描直接子目录的 `Skill.md`/`SKILL.md`
2. **命名**：技能名取自目录名，非 front matter `name` 字段
3. **元数据**：`loadDescription` 只提取 front matter `description:`，支持 inline/quoted/`\|`/`|-`/`>`/`>-` 多种 YAML 标量
4. **增量**：`buildSnapshotSignature` 生成 (目录key, mtime) 列表；`refreshIncrementally` 比对快照，仅加载新增/mtime 变更、移除失效、维持 `skillOrder` 顺序
5. **安全**：`resolveSafeSkillPath` 校验路径真实位于 `skillsRoot` 内，符号链接越界/`..` 逃逸抛 `SecurityException`

## 四、测试覆盖

| 测试 | 行 | 覆盖 |
|------|----|------|
| [SkillManagerTest](file:///D:/jiuwen/main/agent-core-java/src/test/java/com/openjiuwen/core/singleagent/skills/SkillManagerTest.java#L20) | L20 | Skill 构造/表示、注册表状态、FS 注册、受信根安全、注销、YAML block scalar 解析 |
| [SkillManagerIncrementalTest](file:///D:/jiuwen/main/agent-core-java/src/test/java/com/openjiuwen/core/singleagent/skills/SkillManagerIncrementalTest.java#L22) | L22 | 增量刷新/快照签名/有序遍历/按目录查找 |

## 五、小结

- 元数据层而非执行层：只发现与查询，不挂工具
- 增量刷新靠 mtime 快照签名，无需重启即可感知增删改
- 受信根安全校验贯穿本地注册与远程下载
