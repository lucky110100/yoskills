#!/bin/bash
# Mock Service 统一配置文件
# 所有脚本通过 source 此文件获取配置
#
# 配置优先级: 环境变量 > 默认值（基于 MOCK_PROJECT_ROOT 派生）
#
# 可用环境变量:
#   MOCK_PROJECT_ROOT  项目根目录（所有路径的基准）
#   MOCK_VENV          Python venv 路径（覆盖默认派生值）
#   MOCK_SERVICE_SRC   mock_service 源码路径（覆盖默认派生值）
#   MOCK_LOG_DIR       日志目录（覆盖默认派生值）

# ==================== 颜色输出 ====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_err()   { echo -e "${RED}[ERROR]${NC} $*"; }

# ==================== 基础路径 ====================
# 根目录（唯一硬编码路径，其余全部派生）
MOCK_PROJECT_ROOT="${MOCK_PROJECT_ROOT:-/home/luffy/projects/jiuwen/main}"

# 派生路径（每个可用同名环境变量覆盖）
VENV_DIR="${MOCK_VENV:-${MOCK_PROJECT_ROOT}/.venv}"
MOCK_SERVICE_SRC="${MOCK_SERVICE_SRC:-${MOCK_PROJECT_ROOT}/jiuwen-test/mock_service}"
LOG_DIR="${MOCK_LOG_DIR:-${MOCK_PROJECT_ROOT}/jiuwen-test/logs}"

PID_FILE="${LOG_DIR}/mock_services.pid"
PYTHON="${VENV_DIR}/bin/python"

# ==================== 服务定义 ====================
PORTS=(8000 8088 8188 8189 8190)
declare -A PORT_NAMES
PORT_NAMES=(
    [8000]="weather_reporter"
    [8088]="mockllm"
    [8188]="mcp_sse_server"
    [8189]="mcp_sse_server2"
    [8190]="mcp_sse_server3"
)

# 启动顺序
SERVICE_ORDER=("weather_reporter" "mockllm" "mcp_sse_server" "mcp_sse_server2" "mcp_sse_server3")

# 各服务脚本路径
declare -A SERVICE_SCRIPTS
SERVICE_SCRIPTS=(
    ["weather_reporter"]="${MOCK_SERVICE_SRC}/mock_http/weather_reporter.py"
    ["mockllm"]="${MOCK_SERVICE_SRC}/mockllm/main.py"
    ["mcp_sse_server"]="${MOCK_SERVICE_SRC}/mock_mcp/mcp_sse_server.py"
    ["mcp_sse_server2"]="${MOCK_SERVICE_SRC}/mock_mcp/mcp_sse_server2.py"
    ["mcp_sse_server3"]="${MOCK_SERVICE_SRC}/mock_mcp/mcp_sse_server3.py"
)

# 各服务日志路径
declare -A SERVICE_LOGS
SERVICE_LOGS=(
    ["weather_reporter"]="${LOG_DIR}/mock_http/weather_reporter.log"
    ["mockllm"]="${LOG_DIR}/mockllm/mockllm.log"
    ["mcp_sse_server"]="${LOG_DIR}/mcp/mcp_sse_server.log"
    ["mcp_sse_server2"]="${LOG_DIR}/mcp/mcp_sse_server2.log"
    ["mcp_sse_server3"]="${LOG_DIR}/mcp/mcp_sse_server3.log"
)

# 各服务端口
declare -A SERVICE_PORTS
SERVICE_PORTS=(
    ["weather_reporter"]="8000"
    ["mockllm"]="8088"
    ["mcp_sse_server"]="8188"
    ["mcp_sse_server2"]="8189"
    ["mcp_sse_server3"]="8190"
)
