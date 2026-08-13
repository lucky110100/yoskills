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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

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

            if kill -0 ${pid} 2>/dev/null; then
                log_warn "进程未响应，强制终止 ..."
                kill -9 ${pid} 2>/dev/null || true
            fi
            log_ok "${name} 已停止"
        else
            log_warn "${name} (PID: ${pid}) 已不存在"
        fi
    done < "${PID_FILE}"

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
