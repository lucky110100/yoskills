#!/bin/bash
# Mock Service 依赖安装脚本
# 使用方式: ./install.sh [--venv <path>] [--check]
#
# --venv  指定 venv 路径（默认: /home/luffy/projects/gitcode/.venv）
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
VENV_DIR="${MOCK_VENV:-/home/luffy/projects/gitcode/.venv}"
CHECK_ONLY=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --venv)
            VENV_DIR="$2"
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

PYTHON="${VENV_DIR}/bin/python"
PIP="${VENV_DIR}/bin/pip"

# ==================== 检查 venv ====================
if [[ ! -f "${PYTHON}" ]]; then
    log_err "Python venv not found at: ${VENV_DIR}"
    log_info "Create it first: python3 -m venv ${VENV_DIR}"
    exit 1
fi

log_info "Using Python: ${PYTHON}"
log_info "Python version: $(${PYTHON} --version)"

# ==================== 依赖定义 ====================
# 分层定义：核心依赖 → mockllm 依赖 → MCP 依赖
# 每个依赖指定：包名、最低版本、说明

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

        # 检查是否已安装
        local installed=$(${PIP} show "${pkg_name}" 2>/dev/null | grep "^Version:" | awk '{print $2}' || echo "")

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

    # 构造 pip install 参数列表
    local install_args=()
    for dep_spec in "${deps[@]}"; do
        local pkg_version="${dep_spec%%|*}"
        install_args+=("${pkg_version}")
    done

    log_info "安装: ${install_args[*]}"
    ${PIP} install "${install_args[@]}"

    log_ok "${category} 依赖安装完成"
}

# ==================== fastmcp 兼容性检查 ====================
check_fastmcp_compat() {
    local fastmcp_ver=$(${PIP} show fastmcp 2>/dev/null | grep "^Version:" | awk '{print $2}' || echo "")

    if [[ -z "${fastmcp_ver}" ]]; then
        return 1
    fi

    echo ""
    echo "=========================================="
    echo "  fastmcp 兼容性检查 (当前: ${fastmcp_ver})"
    echo "=========================================="

    # 检查关键兼容性问题
    local major="${fastmcp_ver%%.*}"

    if [[ "${major}" -ge 3 ]]; then
        log_err "fastmcp ${fastmcp_ver} 是 3.x 版本，FastMCP() 不再接受 host/port 参数！"
        log_info "需要降级到 2.13.3: ${PIP} install 'fastmcp>=2.13.3,<2.14.0'"
        return 1
    fi

    # 检查 2.14.x 的已知 bug
    if [[ "${fastmcp_ver}" =~ ^2\.14\. ]]; then
        log_warn "fastmcp ${fastmcp_ver} 是 2.14.x 版本，可能有 auth.py bug"
        log_info "建议使用 2.13.3: ${PIP} install 'fastmcp>=2.13.3,<2.14.0'"
    fi

    # 检查构造函数 host/port 参数
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

    # 检查 mcp_config 模块
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
