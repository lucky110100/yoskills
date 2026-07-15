#!/bin/bash
# Mock Service 状态检查脚本
# 使用方式: ./status.sh [--detail]
#
# --detail  显示每个服务的详细日志尾部

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
DETAIL=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --detail|-d)
            DETAIL=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--detail]"
            echo "  --detail  显示每个服务的日志尾部"
            exit 0
            ;;
        *)
            log_err "Unknown argument: $1"
            exit 1
            ;;
    esac
done

# ==================== 路径配置 ====================
LOG_DIR="/home/luffy/projects/gitcode/JiuwenTest/logs"
PID_FILE="${LOG_DIR}/mock_services.pid"

PORTS=(8000 8088 8188 8189 8190)
declare -A PORT_NAMES
PORT_NAMES=(
    [8000]="weather_reporter"
    [8088]="mockllm"
    [8188]="mcp_sse_server"
    [8189]="mcp_sse_server2"
    [8190]="mcp_sse_server3"
)
declare -A LOG_PATHS
LOG_PATHS=(
    [8000]="${LOG_DIR}/mock_http/weather_reporter.log"
    [8088]="${LOG_DIR}/mockllm/mockllm.log"
    [8188]="${LOG_DIR}/mcp/mcp_sse_server.log"
    [8189]="${LOG_DIR}/mcp/mcp_sse_server2.log"
    [8190]="${LOG_DIR}/mcp/mcp_sse_server3.log"
)

echo "=========================================="
echo "  Mock Service 状态"
echo "=========================================="

# ==================== PID文件检查 ====================
if [[ -f "${PID_FILE}" ]]; then
    echo ""
    log_info "PID文件: ${PID_FILE}"
    while IFS=: read -r name pid port; do
        if [[ -z "${name}" ]]; then
            continue
        fi
        if kill -0 ${pid} 2>/dev/null; then
            log_ok "${name} PID:${pid} 端口:${port} — 运行中 ✅"
        else
            log_err "${name} PID:${pid} 端口:${port} — 已停止 ❌"
        fi
    done < "${PID_FILE}"
else
    log_warn "PID文件不存在: ${PID_FILE}"
fi

# ==================== 端口检查 ====================
echo ""
log_info "端口监听检查:"
all_running=true

for port in "${PORTS[@]}"; do
    name="${PORT_NAMES[$port]}"
    pids=$(lsof -i :${port} -t 2>/dev/null || true)

    if [[ -n "${pids}" ]]; then
        log_ok "${name} 端口:${port} — 监听中 ✅ (PID: ${pids})"
    else
        log_err "${name} 端口:${port} — 未监听 ❌"
        all_running=false
    fi
done

# ==================== 详细日志 ====================
if [[ "${DETAIL}" == true ]]; then
    echo ""
    log_info "各服务最近日志:"
    for port in "${PORTS[@]}"; do
        name="${PORT_NAMES[$port]}"
        log_path="${LOG_PATHS[$port]}"
        echo ""
        echo "--- ${name} (${log_path}) ---"
        if [[ -f "${log_path}" ]]; then
            tail -10 "${log_path}"
        else
            echo "(日志文件不存在)"
        fi
    done
fi

# ==================== 总结 ====================
echo ""
if [[ "${all_running}" == true ]]; then
    log_ok "所有5个服务运行正常 ✅"
else
    log_err "部分服务未运行，请检查日志或重启 ❌"
    log_info "重启: bash $(cd "$(dirname "$0")" && pwd)/start.sh --restart"
fi
