#!/bin/bash
# Mock Service 停止脚本
# 使用方式: ./stop.sh [--force]
#
# --force  强制终止所有端口上的进程（不依赖PID文件）
#
# 停止策略：
#   1. 先通过PID文件优雅停止（kill → 等待 → kill -9）
#   2. 再通过端口扫描清理残留进程（兜底）

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
FORCE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force)
            FORCE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--force]"
            echo "  --force  强制终止所有端口上的进程"
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
VENV_DIR="${MOCK_VENV:-/home/luffy/projects/gitcode/.venv}"
MOCK_SERVICE_SRC="${MOCK_SERVICE_SRC:-/home/luffy/projects/gitcode/jiuwen-test/mock_service}"
LOG_DIR="${MOCK_LOG_DIR:-/home/luffy/projects/gitcode/jiuwen-test/logs}"
PID_FILE="${LOG_DIR}/mock_services.pid"

# 端口列表和名称映射
PORTS=(8000 8088 8188 8189 8190)
declare -A PORT_NAMES
PORT_NAMES=(
    [8000]="weather_reporter"
    [8088]="mockllm"
    [8188]="mcp_sse_server"
    [8189]="mcp_sse_server2"
    [8190]="mcp_sse_server3"
)

echo "=========================================="
echo "  停止 Mock 服务"
echo "=========================================="

# ==================== 方式1：通过PID文件停止 ====================
if [[ "${FORCE}" == false ]] && [[ -f "${PID_FILE}" ]]; then
    log_info "从PID文件停止服务: ${PID_FILE}"

    while IFS=: read -r name pid port; do
        if [[ -z "${name}" ]]; then
            continue
        fi

        if kill -0 ${pid} 2>/dev/null; then
            log_info "停止 ${name} (PID: ${pid}, 端口: ${port}) ..."
            kill ${pid}
            sleep 1

            # 检查是否还在运行，如果还在则强制杀
            if kill -0 ${pid} 2>/dev/null; then
                log_warn "进程未响应，强制终止 ..."
                kill -9 ${pid} 2>/dev/null || true
            fi
            log_ok "${name} 已停止"
        else
            log_warn "${name} (PID: ${pid}) 已不存在"
        fi
    done < "${PID_FILE}"

    # 清空PID文件
    > "${PID_FILE}"
else
    if [[ "${FORCE}" == true ]]; then
        log_info "强制模式：跳过PID文件，直接按端口清理"
    else
        log_warn "PID文件不存在: ${PID_FILE}"
    fi
fi

# ==================== 方式2：通过端口清理残留 ====================
echo ""
log_info "检查端口残留进程 ..."

for port in "${PORTS[@]}"; do
    name="${PORT_NAMES[$port]}"
    pids=$(lsof -i :${port} -t 2>/dev/null || true)

    if [[ -n "${pids}" ]]; then
        log_warn "发现 ${name} 端口 ${port} 上的残留进程: ${pids}"
        for pid in ${pids}; do
            kill -9 ${pid} 2>/dev/null || true
        done
        log_ok "已强制终止端口 ${port} 上的进程"
    else
        log_ok "${name} 端口 ${port} 无残留进程"
    fi
done

echo ""
echo "=========================================="
echo "  所有服务已停止"
echo "=========================================="
