#!/bin/bash
# Mock Service 统一运维入口
# 使用方式: ./ops.sh <command> [options]
#
# Commands:
#   install   安装所有 Python 依赖
#   check     检查依赖是否已安装
#   start     启动5个 mock 服务
#   stop      停止所有 mock 服务
#   restart   先停止再启动
#   status    查看服务运行状态
#   health    健康检查（HTTP 探测各端口）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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

# ==================== 默认配置 ====================
VENV_DIR="${MOCK_VENV:-/home/luffy/projects/gitcode/.venv}"
MOCK_SERVICE_SRC="${MOCK_SERVICE_SRC:-/home/luffy/projects/gitcode/jiuwen-test/mock_service}"
LOG_DIR="${MOCK_LOG_DIR:-/home/luffy/projects/gitcode/jiuwen-test/logs}"
PID_FILE="${LOG_DIR}/mock_services.pid"
PYTHON="${VENV_DIR}/bin/python"

PORTS=(8000 8088 8189 8190 8188)
declare -A PORT_NAMES
PORT_NAMES=(
    [8000]="weather_reporter"
    [8088]="mockllm"
    [8188]="mcp_sse_server"
    [8189]="mcp_sse_server2"
    [8190]="mcp_sse_server3"
)

# ==================== 命令分发 ====================
case "${1:-help}" in
    install)
        bash "${SCRIPT_DIR}/install.sh" --venv "${VENV_DIR}"
        ;;
    check)
        bash "${SCRIPT_DIR}/install.sh" --venv "${VENV_DIR}" --check
        ;;
    start)
        bash "${SCRIPT_DIR}/start.sh" --venv "${VENV_DIR}"
        ;;
    stop)
        bash "${SCRIPT_DIR}/stop.sh"
        ;;
    restart)
        bash "${SCRIPT_DIR}/stop.sh"
        sleep 2
        bash "${SCRIPT_DIR}/start.sh" --venv "${VENV_DIR}"
        ;;
    status)
        bash "${SCRIPT_DIR}/status.sh"
        ;;
    health)
        cmd_health
        ;;
    help|--help|-h)
        echo "Mock Service 运维工具"
        echo ""
        echo "Usage: $0 <command> [options]"
        echo ""
        echo "Commands:"
        echo "  install   安装所有 Python 依赖"
        echo "  check     检查依赖是否已安装"
        echo "  start     启动5个 mock 服务"
        echo "  stop      停止所有 mock 服务"
        echo "  restart   先停止再启动（干净重启）"
        echo "  status    查看服务运行状态"
        echo "  health    健康检查（HTTP 探测各端口）"
        echo ""
        echo "Environment:"
        echo "  MOCK_VENV         Python venv 路径 (default: ${VENV_DIR})"
        echo "  MOCK_SERVICE_SRC  mock_service 源码路径 (default: ${MOCK_SERVICE_SRC})"
        echo "  MOCK_LOG_DIR      日志目录 (default: ${LOG_DIR})"
        ;;
    *)
        log_err "Unknown command: $1"
        echo "Run '$0 help' for available commands."
        exit 1
        ;;
esac

# ==================== 健康检查 ====================
cmd_health() {
    echo "=========================================="
    echo "  Mock Service 健康检查"
    echo "=========================================="

    local all_ok=true

    # weather_reporter (8000) - HTTP GET
    local resp=$(curl -sf http://127.0.0.1:8000/weather?location=杭州 2>/dev/null || echo "")
    if [[ -n "${resp}" ]]; then
        log_ok "weather_reporter (8000) ✅ — 返回: ${resp:0:80}..."
    else
        log_err "weather_reporter (8000) ❌ — 无响应"
        all_ok=false
    fi

    # mockllm (8088) - HTTP POST (简单请求)
    local resp2=$(curl -sf -X POST http://127.0.0.1:8088/v1/chat/completions \
        -H "Content-Type: application/json" \
        -d '{"model":"mock","messages":[{"role":"user","content":"test"}]}' 2>/dev/null || echo "")
    if [[ -n "${resp2}" ]]; then
        log_ok "mockllm (8088) ✅ — 返回: ${resp2:0:80}..."
    else
        log_err "mockllm (8088) ❌ — 无响应"
        all_ok=false
    fi

    # MCP SSE 服务 (8188/8189/8190) - 检查 SSE endpoint
    for port in 8188 8189 8190; do
        local name="${PORT_NAMES[$port]}"
        local resp3=$(curl -sf http://127.0.0.1:${port}/sse 2>/dev/null || echo "")
        if [[ -n "${resp3}" ]]; then
            log_ok "${name} (${port}) ✅ — SSE endpoint 可达"
        else
            # SSE endpoint 可能需要特殊处理，只检查端口连通性
            local pids=$(lsof -i :${port} -t 2>/dev/null || true)
            if [[ -n "${pids}" ]]; then
                log_ok "${name} (${port}) ✅ — 端口监听中（SSE 需长连接，curl 短探测可能无响应）"
            else
                log_err "${name} (${port}) ❌ — 端口未监听"
                all_ok=false
            fi
        fi
    done

    echo ""
    if [[ "${all_ok}" == true ]]; then
        log_ok "所有服务健康 ✅"
    else
        log_err "部分服务异常 ❌"
        log_info "查看详情: bash ${SCRIPT_DIR}/status.sh --detail"
    fi
}
