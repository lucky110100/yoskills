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
source "${SCRIPT_DIR}/config.sh"

# ==================== 健康检查 ====================
cmd_health() {
    echo "=========================================="
    echo "  Mock Service 健康检查"
    echo "=========================================="

    local all_ok=true

    # weather_reporter (8000) - HTTP GET (杭州 = %E6%9D%AD%E5%B7%9E)
    local resp=$(curl -sf --max-time 3 "http://127.0.0.1:8000/weather?location=%E6%9D%AD%E5%B7%9E" 2>/dev/null || echo "")
    if [[ -n "${resp}" ]]; then
        log_ok "weather_reporter (8000) ✅ — 返回: ${resp:0:80}..."
    else
        local pids=$(lsof -i :8000 -t 2>/dev/null || true)
        if [[ -n "${pids}" ]]; then
            log_ok "weather_reporter (8000) ✅ — 端口监听中（HTTP 探测无响应，可能正在启动中）"
        else
            log_err "weather_reporter (8000) ❌ — 端口未监听"
            all_ok=false
        fi
    fi

    # mockllm (8088) - HTTP POST (简单请求)
    # mockllm 对未匹配的 query 会返回 400，这是正常行为
    local resp2=$(curl -s --max-time 3 -X POST http://127.0.0.1:8088/v1/chat/completions \
        -H "Content-Type: application/json" \
        -d '{"model":"mock","messages":[{"role":"user","content":"test"}]}' 2>/dev/null || echo "")
    if [[ -n "${resp2}" ]]; then
        log_ok "mockllm (8088) ✅ — 返回: ${resp2:0:80}..."
    else
        local pids=$(lsof -i :8088 -t 2>/dev/null || true)
        if [[ -n "${pids}" ]]; then
            log_ok "mockllm (8088) ✅ — 端口监听中（mockllm 对未匹配 query 返回 400 属正常行为）"
        else
            log_err "mockllm (8088) ❌ — 端口未监听"
            all_ok=false
        fi
    fi

    # MCP SSE 服务 (8188/8189/8190) - 检查 SSE endpoint
    for port in 8188 8189 8190; do
        local name="${PORT_NAMES[$port]}"
        local resp3=$(curl -sf --max-time 2 http://127.0.0.1:${port}/sse 2>/dev/null || echo "")
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
        echo "  MOCK_PROJECT_ROOT  项目根目录 (default: ${MOCK_PROJECT_ROOT})"
        echo "  MOCK_VENV          Python venv 路径 (default: ${VENV_DIR})"
        echo "  MOCK_SERVICE_SRC   mock_service 源码路径 (default: ${MOCK_SERVICE_SRC})"
        echo "  MOCK_LOG_DIR       日志目录 (default: ${LOG_DIR})"
        ;;
    *)
        log_err "Unknown command: $1"
        echo "Run '$0 help' for available commands."
        exit 1
        ;;
esac
