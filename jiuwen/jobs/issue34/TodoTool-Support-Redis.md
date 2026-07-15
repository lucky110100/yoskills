多实例部署受限 ：多个 agent 实例无法共享同一份 Todo 数据，需依赖共享文件系统
无法利用框架已有的 Redis 能力 ：框架已提供 BaseKVStore + RedisStore ，但 TodoTool 未使用
缺少存储抽象层 ：没有 TodoStorage 接口，无法扩展其他存储实现
当前实现
TodoTool.java 直接使用文件存储：

// harness/tools/TodoTool.java
public List load(String sessionId) throws IOException {
Path file = filePath(sessionId); // workspace.resolve
(sessionId).resolve("todo.json")
String json = Files.readString(file);
...
}

public void save(String sessionId, List todos) throws
IOException {
Path file = filePath(sessionId);
Files.createDirectories(file.getParent());
Files.writeString(file, JsonUtils.safeJsonDumps(todos, "[]"));
}
存储路径： {workspace}/{sessionId}/todo.json

期望基于框架已有的 Redis 基础设施，todo tool也支持该存储方式

设计思路
不涉及

涉及到的对外API
不涉及

与其他模块的相关性描述
EDPAgnet基于DeepAgent的todo工具开发

测试设计与测试计划
基于框架已有的 Redis 基础设施，todo tool也支持该存储方式