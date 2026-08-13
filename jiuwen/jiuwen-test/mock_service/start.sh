#!/bin/bash
# Mock Service 启动脚本
# 使用方式: ./start.sh [--venv <path>] [--restart]
#
# --venv      指定 venv 路径（覆盖 config.sh 默认值）
# --restart   先停止再启动（干净重启)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

# ==================== 参数解析 ====================
RESTART=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --venv)
            VENV_DIR="$2"
            PYTHON="${VENV_DIR}/bin/python"
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

# ==================== 启动服务 ====================
echo "=========================================="
echo "  启动 Mock 服务"
echo "  venv: ${VENV_DIR}"
echo "=========================================="

> "${PID_FILE}"

for name in "${SERVICE_ORDER[@]}"; do
    script="${SERVICE_SCRIPTS[$name]}"
    log_path="${SERVICE_LOGS[$name]}"
    port="${SERVICE_PORTS[$name]}"

    # 检查端口是否已被占用
    if lsof -i :${port} -t >/dev/null 2>&1; then
        log_warn "[${name}] 端口 ${port} 已被占用，跳过启动。请先运行 stop.sh 或使用 --restart"
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

    sleep 1

    if kill -0 ${pid} 2>/dev/null; then
        log_ok "${name} 启动成功 (PID: ${pid})"
    else
        log_err "${name} 启动失败，请检查日志: ${log_path}"
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
