#!/bin/bash
# Mock Service 状态检查脚本
# 使用方式: ./status.sh [--detail]
#
# --detail  显示每个服务的详细日志尾部

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

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
        log_path="${SERVICE_LOGS[$name]}"
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
    log_info "重启: bash ${SCRIPT_DIR}/start.sh --restart"
fi
