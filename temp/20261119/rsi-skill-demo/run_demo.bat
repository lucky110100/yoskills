@echo off
rem ---------------------------------------------------------------------------
rem RSI skill demo: compile + run (plain javac/java classpath, no Maven needed).
rem Requires JDK 17+ and local Maven repo at D:\java\maven-repo.
rem NOTE: keep this file ASCII-only; UTF-8 comments break under GBK codepage.
rem ---------------------------------------------------------------------------
setlocal
set "DEMO_ROOT=%~dp0"
cd /d "%DEMO_ROOT%"

set "MVN_REPO=D:\java\maven-repo"
set "CORE_JAR=%MVN_REPO%\com\openjiuwen\agent-core-java\0.1.17\agent-core-java-0.1.17.jar"
set "RSI_JAR=%MVN_REPO%\com\openjiuwen\core-rsi\0.1.17\core-rsi-0.1.17.jar"
set "JACKSON_DATA=%MVN_REPO%\com\fasterxml\jackson\core\jackson-databind\2.21.5\jackson-databind-2.21.5.jar"
set "JACKSON_CORE=%MVN_REPO%\com\fasterxml\jackson\core\jackson-core\2.21.5\jackson-core-2.21.5.jar"
set "JACKSON_ANN=%MVN_REPO%\com\fasterxml\jackson\core\jackson-annotations\2.21\jackson-annotations-2.21.jar"

set "CP=%CORE_JAR%;%RSI_JAR%;%JACKSON_DATA%;%JACKSON_CORE%;%JACKSON_ANN%"
set "SRC_DIR=src\main\java\com\example\rsidemo"
set "BUILD_DIR=build\classes"

echo [1/2] Compiling demo sources...
if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"
(for /f "delims=" %%F in ('dir /b "%SRC_DIR%\*.java"') do @echo %SRC_DIR%\%%F) > "%TEMP%\rsi_demo_sources.txt"
javac -encoding UTF-8 -cp "%CP%" -d "%BUILD_DIR%" @"%TEMP%\rsi_demo_sources.txt"
if errorlevel 1 (
  echo Compile failed.
  exit /b 1
)

echo [2/2] Running demo (workdir = demo root)...
java -Dfile.encoding=UTF-8 -Dsun.stdout.encoding=UTF-8 -Dsun.stderr.encoding=UTF-8 -cp "%BUILD_DIR%;%CP%" com.example.rsidemo.RsiSkillDemo
endlocal & exit /b %errorlevel%
