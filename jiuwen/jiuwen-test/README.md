翻译下面内容：
## 下载目标源码仓
git clone -b 730 https://gitcode.com/openJiuwen/agent-core-java.git

## 下载系统用例仓
git clone -b agent_core_java https://gitcode.com/openJiuwen/jiuwen-test.git

## 下载技能仓
git clone -b master https://gitcode.com/whylazy/yoskills.git

## 编译安装agent-core-java
mvn clean install -DskipTests -f "/home/luffy/projects/gitcode/agent-core-java/pom.xml"

## 启动mock服务
脚本里的默认路径需要改一下，或者让AI改
```
cd ~/projects/gitcode/yoskills/jiuwen/mock_service
./ops.sh -h
Commands:
  install   安装所有 Python 依赖
  check     检查依赖是否已安装
  start     启动5个 mock 服务
  stop      停止所有 mock 服务
```

## 跑冒烟用例
```
cd ~/projects/gitcode/jiuwen-test
export REDIS_IP=127.0.0.1
export JAEGER_UI_URL=http://120.46.91.110:8460 
export JAEGER_OTLP_ENDPOINT=http://120.46.91.110:4317
mvn clean test -Dgroups=smoke
  
全量
mvn clean test -Dtest='!com/openjiuwen/test/cases/knowledge_base/**'

冒烟
mvn clean test -Dgroups='smoke' -Dtest='!com/openjiuwen/test/cases/knowledge_base/**'

cd D:\jiuwen\main\jiuwen-test
mvn clean test -Dtest="ToolGuardrailE2E001,ToolGuardrailE2E002" -DfailIfNoTests=false
```