## 工作目录
WORK_SPACE = "~/projects/jiuwen/main"
询问用户当前工作目录是否正确，不正确则提示用户输入正确的工作目录

## 目标源码仓
origin: https://gitcode.com/openJiuwen/agent-core-java.git
fork: https://gitcode.com/whylazy/agent-core-java.git
先检查当前工作目录是否存在对应的代码仓，没有则下载，有则给错当前代码状态，询问用户是否切换到指定仓库和分支，并拉取最新代码。

## 系统用例仓
origin: https://gitcode.com/openJiuwen/jiuwen-test.git
fork: https://gitcode.com/whylazy/jiuwen-test.git
先检查当前工作目录是否存在对应的代码仓，没有则下载，有则给错当前代码状态，询问用户是否切换到指定仓库和分支，并拉取最新代码。

## 技能仓
origin: https://gitcode.com/whylazy/yoskills.git

## 编译安装agent-core-java
mvn clean install -DskipTests -f "${WORK_SPACE}/agent-core-java/pom.xml"

## 启动mock服务
脚本里的默认路径需要改一下，或者让AI改
```
cd "${WORK_SPACE}/yoskills/jiuwen/mock_service"
./ops.sh -h
Commands:
  install   安装所有 Python 依赖
  check     检查依赖是否已安装
  start     启动5个 mock 服务
  stop      停止所有 mock 服务
```

## 跑冒烟用例
先设置环境环境变量，确保JAEGER_UI_URL和JAEGER_OTLP_ENDPOINT正确，然后询问用户跑哪个场景的冒烟用例。
用户输入场景一或场景二，根据用户输入跑对应的冒烟用例。
```
cd "${WORK_SPACE}/jiuwen-test"
export REDIS_IP=127.0.0.1
export JAEGER_UI_URL=http://120.46.91.110:8460 
export JAEGER_OTLP_ENDPOINT=http://120.46.91.110:4317

# 场景一：跑冒烟用例
mvn clean test -Dgroups=smoke

# 场景二：跑冒烟用例，排除知识库用例
mvn clean test -Dgroups='smoke' -Dtest='!com/openjiuwen/test/cases/knowledge_base/**'
```