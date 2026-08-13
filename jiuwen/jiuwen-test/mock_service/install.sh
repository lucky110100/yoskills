#!/bin/bash
# Mock Service 依赖安装脚本
# 使用方式: ./install.sh [--venv <path>] [--check]
#
# --venv  指定 venv 路径（覆盖 config.sh 默认值）
# --check 只检查依赖是否已安装，不执行安装
#
# 经验总结：
#   1. fastmcp 版本兼容性是最大坑：
#      - 3.x: FastMCP() 不再接受 host/port 参数
#      - 2.14.7: 内部 auth.py 有 bug（PrivateKeyJWTClientAuthenticator 缺失）
#      - 2.10.0: 缺 mcp_config 模块
#      - 2.3.5: 缺 mcp_config 模块
#      - 2.13.3: ✅ 稳定可用（host/port 在 run() 时提供，构造函数有 deprecation warning 但功能正常）
#   2. pydantic 版本需与 fastmcp 兼容：
#      - fastmcp 2.13.3 需要 pydantic>=2.0，但 pydantic-settings 版本不能太新
#      - 当前稳定组合: pydantic==2.13.4 + pydantic-settings==2.14.2
#   3. mockllm 需要 python-json-logger（包名 python-json-logger，import 名 pythonjsonlogger）
#   4. mcp 包版本需与 fastmcp 兼容（mcp>=1.0）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

# ==================== 参数解析 ====================
CHECK_ONLY=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --venv)
            VENV_DIR="$2"
            PYTHON="${VENV_DIR}/bin/python"
            shift 2
            ;;
        --check)
            CHECK_ONLY=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--venv <path>] [--check]"
            echo "  --venv  指定 Python venv 路径"
            echo "  --check 只检查依赖，不安装"
            exit 0
            ;;
        *)
            log_err "Unknown argument: $1"
            exit 1
            ;;
    esac
done

PIP_CMD=("${PYTHON}" -m pip)

# ==================== 检查 venv ====================
if [[ ! -f "${PYTHON}" ]]; then
    log_err "Python venv not found at: ${VENV_DIR}"
    log_info "Create it first: python3 -m venv ${VENV_DIR}"
    exit 1
fi

log_info "Using Python: ${PYTHON}"
log_info "Python version: $(${PYTHON} --version)"

# ==================== 依赖定义 ====================
# 核心依赖（weather_reporter + mockllm 共用）
CORE_DEPS=(
    "fastapi>=0.68.0|FastAPI Web框架"
    "uvicorn>=0.15.0|ASGI服务器"
    "pydantic>=2.0,<3.0|数据验证（注意：需与fastmcp兼容）"
    "starlette|FastAPI依赖的ASGI工具包"
)

# mockllm 专用依赖
MOCKLLM_DEPS=(
    "python-json-logger>=2.0.0|JSON格式日志（import名: pythonjsonlogger）"
    "pyyaml>=5.4.1|YAML配置解析"
    "watchdog>=2.1.0|文件监控"
    "tiktoken>=0.9.0|OpenAI token计数"
    "click>=8.1.7|CLI工具"
    "httpx>=0.24.0|HTTP客户端"
)

# MCP 服务依赖（最关键的版本兼容性）
MCP_DEPS=(
    "fastmcp>=2.13.3,<2.14.0|MCP SSE服务（⚠️ 版本兼容性最复杂，见经验总结）"
    "mcp>=1.0|MCP协议库"
)

# ==================== 检查依赖 ====================
check_deps() {
    local category="$1"
    local -n deps="$2"
    local all_ok=true

    echo ""
    echo "=========================================="
    echo "  检查 ${category} 依赖"
    echo "=========================================="

    for dep_spec in "${deps[@]}"; do
        local pkg_version="${dep_spec%%|*}"
        local desc="${dep_spec##*|}"
        local pkg_name="${pkg_version%%[>=<]*}"

        local installed=$("${PIP_CMD[@]}" show "${pkg_name}" 2>/dev/null | grep "^Version:" | awk '{print $2}' || echo "")

        if [[ -n "${installed}" ]]; then
            log_ok "${pkg_name} ${installed} ✅ (${desc})"
        else
            log_warn "${pkg_name} 未安装 ❌ (${desc})"
            all_ok=false
        fi
    done

    if [[ "${all_ok}" == true ]]; then
        log_ok "${category} 所有依赖已满足"
    fi

    return 0
}

# ==================== 安装依赖 ====================
install_deps() {
    local category="$1"
    local -n deps="$2"

    echo ""
    echo "=========================================="
    echo "  安装 ${category} 依赖"
    echo "=========================================="

    local install_args=()
    for dep_spec in "${deps[@]}"; do
        local pkg_version="${dep_spec%%|*}"
        install_args+=("${pkg_version}")
    done

    log_info "安装: ${install_args[*]}"
    "${PIP_CMD[@]}" install "${install_args[@]}"

    log_ok "${category} 依赖安装完成"
}

# ==================== fastmcp 兼容性检查 ====================
check_fastmcp_compat() {
    local fastmcp_ver=$("${PIP_CMD[@]}" show fastmcp 2>/dev/null | grep "^Version:" | awk '{print $2}' || echo "")

    if [[ -z "${fastmcp_ver}" ]]; then
        return 1
    fi

    echo ""
    echo "=========================================="
    echo "  fastmcp 兼容性检查 (当前: ${fastmcp_ver})"
    echo "=========================================="

    local major="${fastmcp_ver%%.*}"

    if [[ "${major}" -ge 3 ]]; then
        log_err "fastmcp ${fastmcp_ver} 是 3.x 版本，FastMCP() 不再接受 host/port 参数！"
        log_info "需要降级到 2.13.3: ${PYTHON} -m pip install 'fastmcp>=2.13.3,<2.14.0'"
        return 1
    fi

    if [[ "${fastmcp_ver}" =~ ^2\.14\. ]]; then
        log_warn "fastmcp ${fastmcp_ver} 是 2.14.x 版本，可能有 auth.py bug"
        log_info "建议使用 2.13.3: ${PYTHON} -m pip install 'fastmcp>=2.13.3,<2.14.0'"
    fi

    local has_host_port=$(${PYTHON} -c "
from fastmcp import FastMCP
import inspect
sig = inspect.signature(FastMCP.__init__)
params = list(sig.parameters.keys())
print('host' in params and 'port' in params)
" 2>/dev/null || echo "error")

    if [[ "${has_host_port}" == "True" ]]; then
        log_ok "FastMCP() 支持 host/port 参数 ✅"
    elif [[ "${has_host_port}" == "False" ]]; then
        log_warn "FastMCP() 不支持 host/port 参数（需在 run() 时指定）"
        log_info "当前代码使用 FastMCP(name=..., host=..., port=...)，会有 deprecation warning"
        log_info "但功能正常，因为 fastmcp 内部会将 host/port 传给 run()"
    else
        log_err "无法检查 FastMCP 构造函数参数"
    fi

    local has_mcp_config=$(${PYTHON} -c "
try:
    from fastmcp.mcp_config import MCPConfig
    print('yes')
except ImportError:
    print('no')
" 2>/dev/null || echo "error")

    if [[ "${has_mcp_config}" == "yes" ]]; then
        log_ok "fastmcp.mcp_config 模块可用 ✅"
    elif [[ "${has_mcp_config}" == "no" ]]; then
        log_warn "fastmcp.mcp_config 模块不可用（某些高级功能可能受影响）"
    fi

    log_ok "fastmcp 兼容性检查完成"
    return 0
}

# ==================== 主流程 ====================
echo "=========================================="
echo "  Mock Service 依赖安装/检查"
echo "  venv: ${VENV_DIR}"
echo "=========================================="

if [[ "${CHECK_ONLY}" == true ]]; then
    check_deps "核心" CORE_DEPS
    check_deps "mockllm" MOCKLLM_DEPS
    check_deps "MCP" MCP_DEPS
    check_fastmcp_compat
    echo ""
    echo "=========================================="
    echo "  检查完成"
    echo "=========================================="
else
    install_deps "核心" CORE_DEPS
    install_deps "mockllm" MOCKLLM_DEPS
    install_deps "MCP" MCP_DEPS
    check_fastmcp_compat
    echo ""
    echo "=========================================="
    echo "  安装完成！"
    echo "  现在可以启动服务: ./start.sh"
    echo "=========================================="
fi
