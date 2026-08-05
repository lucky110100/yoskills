根据以下要求修改用例agent-core-java\src\test\java\com\openjiuwen\core\systemtest\TenantRedisSystemTest.java：
1、创建DeepAgent的方法，其配置项均来自环境变量，不要从配置文件获取；
2、修改其中用例ST-A1，当enableTenantIsolation=false时，但是却传了tenantId，期望DeepAgent能够正常运行，且不会创建tenantId对应目录；
3、添加用例，Redis 连接异常时，期望DeepAgent能够按异常处理，记录日志，返回错误信息；
4、添加用例，Redis中TodoItem 含不可序列化字段时序列化失败，期望DeepAgent能够按异常处理，返回默认值，不抛出异常；
5、添加用例，Redis中TodoItem 格式错误时，期望DeepAgent能够按异常处理，返回默认值，不抛出异常；
验证时可用如下LLM和Redis信息配置环境变量：
  "API_BASE":"http://localhost:4000/v1",
  "API_KEY":"sk-aIjxTtLGmE7R7bcgXZqpjA",
  "MODEL_PROVIDER":"OpenAI",
  "MODEL_NAME":"local-GLM-5.2",
  "LLM_SSL_VERIFY":"False",
  "API_BASE_EMBEDDING":"http://localhost:4000/v1",
  "MODEL_NAME_EMBEDDING":"local-GLM-5.2",
  "REDIS_URL":"redis://127.0.0.1:6379",
  "REDIS_CLUSTER_MODE":"false"