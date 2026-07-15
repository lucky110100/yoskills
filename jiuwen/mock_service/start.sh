#!/bin/bash
# Mock Service 启动脚本
# 使用方式: ./start.sh [--venv <path>] [--restart]
#
# --venv      指定 venv 路径（默认: /home/luffy/projects/gitcode/.venv）
# --restart   先停止再启动（干净重启）
#
# 启动5个mock服务:
#   weather_reporter  (端口 8000, FastAPI/uvicorn)
#   mockllm           (端口 8088, FastAPI/uvicorn)
#   mcp_sse_server    (端口 8188, FastMCP SSE)
#   mcp_sse_server2   (端口 8189, FastMCP SSE)
#   mcp_sse_server3   (端口 8190, FastMCP SSE)

set -euo pipefail

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

# ==================== 参数解析 ====================
VENV_DIR="/home/luffy/projects/gitcode/.venv"
RESTART=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --venv)
            VENV_DIR="$2"
            shift 2
            ;;
        --restart)
            RESTART=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--venv <path>] [--restart]"
            echo "  --venv      指定 Python venv 路径"
            echo "  --restart   先停止再启动（干净重启）"
            exit 0
            ;;
        *)
            log_err "Unknown argument: $1"
            exit 1
            ;;
    esac
done

# ==================== 路径配置 ====================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="${SCRIPT_DIR}"  # yoskills/jiuwen/mock_service
MOCK_SERVICE_SRC="/home/luffy/projects/gitcode/JiuwenTest/mock_service"
LOG_DIR="/home/luffy/projects/gitcode/JiuwenTest/logs"
PID_FILE="${LOG_DIR}/mock_services.pid"

PYTHON="${VENV_DIR}/bin/python"

# ==================== 检查 venv ====================
if [[ ! -f "${PYTHON}" ]]; then
    log_err "Python venv not found at: ${VENV_DIR}"
    log_info "Run install.sh first: ${SCRIPT_DIR}/install.sh"
    exit 1
fi

# ==================== 干净重启 ====================
if [[ "${RESTART}" == true ]]; then
    log_info "干净重启模式：先停止所有服务..."
    bash "${SCRIPT_DIR}/stop.sh"
    sleep 2
fi

# ==================== 创建日志目录 ====================
mkdir -p "${LOG_DIR}/mock_http" "${LOG_DIR}/mockllm" "${LOG_DIR}/mcp"

# ==================== 服务定义 ====================
declare -A SERVICES
SERVICES=(
    ["weather_reporter"]="${MOCK_SERVICE_SRC}/mock_http/weather_reporter.py|${LOG_DIR}/mock_http/weather_reporter.log|8000"
    ["mockllm"]="${MOCK_SERVICE_SRC}/mockllm/main.py|${LOG_DIR}/mockllm/mockllm.log|8088"
    ["mcp_sse_server"]="${MOCK_SERVICE_SRC}/mock_mcp/mcp_sse_server.py|${LOG_DIR}/mcp/mcp_sse_server.log|8188"
    ["mcp_sse_server2"]="${MOCK_SERVICE_SRC}/mock_mcp/mcp_sse_server2.py|${LOG_DIR}/mcp/mcp_sse_server2.log|8189"
    ["mcp_sse_server3"]="${MOCK_SERVICE_SRC}/mock_mcp/mcp_sse_server3.py|${LOG_DIR}/mcp/mcp_sse_server3.log|8190"
)

# ==================== 启动服务 ====================
echo "=========================================="
echo "  启动 Mock 服务"
echo "  venv: ${VENV_DIR}"
echo "=========================================="

# 清空旧的PID文件
> "${PID_FILE}"

for name in weather_reporter mockllm mcp_sse_server mcp_sse_server2 mcp_sse_server3; do
    IFS='|' read -r script log_path port <<< "${SERVICES[$name]}"

    # 检查端口是否已被占用
    if lsof -i :${port} -t >/dev/null 2>&1; then
        log_warn "[${name}] 端口 ${port} 已被占用，跳过启动。请先运行 stop.sh 或使用 --restart"
        # 记录已有进程的PID
        existing_pid=$(lsof -i :${port} -t 2>/dev/null | head -1)
        echo "${name}:${existing_pid}:${port}" >> "${PID_FILE}"
        continue
    fi

    log_info "启动 ${name} (端口: ${port}) ..."
    echo "   脚本: ${script}"
    echo "   日志: ${log_path}"

    # MCP服务需要传 --log 参数
    if [[ "$name" == mcp_sse_server* ]]; then
        nohup "${PYTHON}" "${script}" --log "${log_path}" >> "${log_path}" 2>&1 &
    else
        nohup "${PYTHON}" "${script}" >> "${log_path}" 2>&1 &
    fi

    pid=$!
    echo "${name}:${pid}:${port}" >> "${PID_FILE}"
    echo "   PID: ${pid}"

    # 等待服务启动
    sleep 1

    # 验证进程是否还在运行
    if kill -0 ${pid} 2>/dev/null; then
        log_ok "${name} 启动成功 (PID: ${pid})"
    else
        log_err "${name} 启动失败，请检查日志: ${log_path}"
        # 显示最后几行日志
        echo "   最后日志:"
        tail -5 "${log_path}" 2>/dev/null || echo "   (日志文件不存在)"
    fi
done

echo ""
echo "=========================================="
echo "  所有服务已尝试启动"
echo "  PID文件: ${PID_FILE}"
echo "  日志目录: ${LOG_DIR}"
echo "=========================================="
echo ""
echo "查看服务状态: bash ${SCRIPT_DIR}/status.sh"
echo "停止所有服务: bash ${SCRIPT_DIR}/stop.sh"
