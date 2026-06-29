#!/bin/bash
set -euo pipefail

JIUWENBOX_HOME="${JIUWENBOX_HOME:-/home/luffy/jiuwenswarm/jiuwenbox}"
JIUWENBOX_PORT="${JIUWENBOX_PORT:-8321}"
WSL_DISTRO="${JIUWENBOX_WSL_DISTRO:-ubuntu-hermes-v2}"
JIUWENBOX_URL="http://127.0.0.1:${JIUWENBOX_PORT}"
JIUWENBOX_REPO_URL="${JIUWENBOX_REPO_URL:-https://gitcode.com/openJiuwen/jiuwenswarm}"
JIUWENBOX_SAVE_LOGS_DIR="${JIUWENBOX_SAVE_LOGS_DIR:-/root/.jiuwenbox/logs}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_err()   { echo -e "${RED}[ERROR]${NC} $*"; }

is_wsl() {
    if grep -qi microsoft /proc/version 2>/dev/null; then
        return 0
    fi
    return 1
}

run_in_wsl() {
    if is_wsl; then
        bash -c "$*"
    else
        wsl -d "$WSL_DISTRO" -- bash -c "$*"
    fi
}

check_port() {
    local url="${JIUWENBOX_URL}/health"
    run_in_wsl "curl -sf '${url}'" > /dev/null 2>&1
}

cmd_install() {
    log_info "Installing Linux dependencies..."
    run_in_wsl "sudo apt-get update && sudo apt-get install -y bubblewrap iproute2 iptables nftables python3-pip python3-venv nodejs python3-build"
    run_in_wsl "pip install --break-system-packages uv 2>/dev/null || pip3 install --break-system-packages uv"
    log_ok "Dependencies installed."

    log_info "Copying jiuwenbox source to WSL2..."
    local src="/mnt/d/jiuwen/main/jiuwenswarm/jiuwenbox"
    run_in_wsl "mkdir -p ~/jiuwenswarm"
    run_in_wsl "if [ -d '${src}' ]; then cp -r '${src}' ~/jiuwenswarm/; else echo 'Source not found at ${src}, please clone jiuwenswarm repo first'; exit 1; fi"
    log_ok "Source copied."

    log_info "Building jiuwenbox wheel..."
    run_in_wsl "cd ${JIUWENBOX_HOME} && ~/.local/bin/uv venv && source .venv/bin/activate && ~/.local/bin/uv sync && ~/.local/bin/uv pip install --upgrade pip build && python3 -m build --wheel && ~/.local/bin/uv pip install ./dist/jiuwenbox*.whl"
    log_ok "Wheel built and installed."

    log_info "Fixing policy for Ubuntu (removing /etc/pki)..."
    local policy_file
    policy_file=$(run_in_wsl "source ${JIUWENBOX_HOME}/.venv/bin/activate && python3 -c \"import jiuwenbox, os; print(os.path.join(os.path.dirname(jiuwenbox.__file__), 'configs', 'default-policy.yaml'))\"")
    run_in_wsl "sed -i '/etc\/pki/d' '${policy_file}'"
    log_ok "Policy fixed."

    log_ok "Install complete. Run 'ops.sh start' to start the service."
}

cmd_deploy() {
    cmd_install
}

cmd_update() {
    log_info "Updating jiuwenbox from source repository..."
    log_info "Repo URL: ${JIUWENBOX_REPO_URL}"

    local was_running=false
    if check_port; then
        was_running=true
        log_info "Service is running, will restart after update."
    fi

    if [ "$was_running" = true ]; then
        cmd_stop
    fi

    log_info "Cloning/pulling latest source..."
    run_in_wsl "if [ -d ~/jiuwenswarm/jiuwenswarm/.git ]; then cd ~/jiuwenswarm/jiuwenswarm && git pull; else git clone '${JIUWENBOX_REPO_URL}' ~/jiuwenswarm/jiuwenswarm; fi"

    log_info "Copying updated jiuwenbox source..."
    run_in_wsl "rm -rf ${JIUWENBOX_HOME}/src ${JIUWENBOX_HOME}/pyproject.toml ${JIUWENBOX_HOME}/docker ${JIUWENBOX_HOME}/tests"
    run_in_wsl "cp -r ~/jiuwenswarm/jiuwenswarm/jiuwenbox/* ${JIUWENBOX_HOME}/"

    log_info "Rebuilding jiuwenbox wheel..."
    run_in_wsl "cd ${JIUWENBOX_HOME} && source .venv/bin/activate && ~/.local/bin/uv sync && python3 -m build --wheel && ~/.local/bin/uv pip install --force-reinstall ./dist/jiuwenbox*.whl"

    log_info "Fixing policy for Ubuntu (removing /etc/pki)..."
    local policy_file
    policy_file=$(run_in_wsl "source ${JIUWENBOX_HOME}/.venv/bin/activate && python3 -c \"import jiuwenbox, os; print(os.path.join(os.path.dirname(jiuwenbox.__file__), 'configs', 'default-policy.yaml'))\"")
    run_in_wsl "sed -i '/etc\/pki/d' '${policy_file}'"
    log_ok "Policy fixed."

    log_ok "Update complete."

    if [ "$was_running" = true ]; then
        log_info "Restarting service..."
        cmd_start
    fi
}

cmd_start() {
    if check_port; then
        log_warn "jiuwenbox-server is already running on port ${JIUWENBOX_PORT}."
        cmd_status
        return 0
    fi

    log_info "Starting jiuwenbox-server on port ${JIUWENBOX_PORT}..."
    if is_wsl; then
        sudo ${JIUWENBOX_HOME}/.venv/bin/jiuwenbox-server &
        local pid=$!
        echo "$pid" > /tmp/jiuwenbox-server.pid
    else
        wsl -d "$WSL_DISTRO" -- bash -c "cd ${JIUWENBOX_HOME} && source .venv/bin/activate && sudo mkdir -p '${JIUWENBOX_SAVE_LOGS_DIR}' && setsid sudo .venv/bin/jiuwenbox-server --save-logs '${JIUWENBOX_SAVE_LOGS_DIR}' > /tmp/jiuwenbox-server.log 2>&1 & echo \$! > /tmp/jiuwenbox-server.pid && sleep 2"
    fi

    log_info "Waiting for service to be ready..."
    local retries=0
    while ! check_port && [ $retries -lt 30 ]; do
        sleep 1
        retries=$((retries + 1))
    done

    if check_port; then
        log_ok "jiuwenbox-server started successfully."
        cmd_health
    else
        log_err "jiuwenbox-server failed to start within 30 seconds."
        return 1
    fi
}

cmd_stop() {
    if ! check_port; then
        log_warn "jiuwenbox-server is not running."
        return 0
    fi

    log_info "Stopping jiuwenbox-server..."
    if is_wsl; then
        if [ -f /tmp/jiuwenbox-server.pid ]; then
            local pid=$(cat /tmp/jiuwenbox-server.pid)
            sudo kill "$pid" 2>/dev/null || true
            rm -f /tmp/jiuwenbox-server.pid
        else
            sudo pkill -f jiuwenbox-server 2>/dev/null || true
        fi
    else
        wsl -d "$WSL_DISTRO" -- bash -c "if [ -f /tmp/jiuwenbox-server.pid ]; then sudo kill \$(cat /tmp/jiuwenbox-server.pid) 2>/dev/null; rm -f /tmp/jiuwenbox-server.pid; else sudo pkill -f jiuwenbox-server 2>/dev/null; fi"
    fi

    sleep 2
    if check_port; then
        log_err "Service still running. Force killing..."
        if is_wsl; then
            sudo pkill -9 -f jiuwenbox-server 2>/dev/null || true
        else
            wsl -d "$WSL_DISTRO" -- bash -c "sudo pkill -9 -f jiuwenbox-server 2>/dev/null || true"
        fi
        sleep 2
    fi

    if ! check_port; then
        log_ok "jiuwenbox-server stopped."
    else
        log_err "Failed to stop jiuwenbox-server."
        return 1
    fi
}

cmd_restart() {
    cmd_stop
    sleep 1
    cmd_start
}

cmd_status() {
    if check_port; then
        local resp
        resp=$(run_in_wsl "curl -sf '${JIUWENBOX_URL}/health'")
        log_ok "jiuwenbox-server is running."
        echo "  Health: $resp"
        local active
        active=$(echo "$resp" | run_in_wsl "python3 -c \"import sys,json; print(json.load(sys.stdin).get('sandboxes_active', 'N/A'))\"")
        echo "  Active sandboxes: ${active}"
        local runtime
        runtime=$(echo "$resp" | run_in_wsl "python3 -c \"import sys,json; print(json.load(sys.stdin).get('runtime', 'N/A'))\"")
        echo "  Runtime: ${runtime}"
        local landlock
        landlock=$(echo "$resp" | run_in_wsl "python3 -c \"import sys,json; print(json.load(sys.stdin).get('landlock_supported', 'N/A'))\"")
        echo "  Landlock: ${landlock}"
    else
        log_warn "jiuwenbox-server is NOT running on port ${JIUWENBOX_PORT}."
        return 1
    fi
}

cmd_health() {
    log_info "Checking jiuwenbox health..."

    if is_wsl; then
        local resp
        resp=$(curl -sf "${JIUWENBOX_URL}/health" 2>/dev/null)
        if [ -n "$resp" ]; then
            log_ok "Health check PASSED (from WSL)."
            echo "  Response: $resp"
        else
            log_err "Health check FAILED (from WSL)."
            return 1
        fi
    else
        local resp
        resp=$(powershell -Command "(New-Object Net.WebClient).DownloadString('${JIUWENBOX_URL}/health')" 2>/dev/null)
        if [ -n "$resp" ]; then
            log_ok "Health check PASSED (from Windows)."
            echo "  Response: $resp"
        else
            log_err "Health check FAILED (from Windows)."
            return 1
        fi
    fi
}

cmd_test() {
    log_info "Running jiuwenbox functional test..."

    if ! check_port; then
        log_err "jiuwenbox-server is not running. Start it first with 'ops.sh start'."
        return 1
    fi

    log_info "Test 1: Create sandbox..."
    local create_resp
    create_resp=$(run_in_wsl "curl -sf -X POST '${JIUWENBOX_URL}/api/v1/sandboxes' -H 'Content-Type: application/json' -d '{}'")
    local sbx_id
    sbx_id=$(echo "$create_resp" | run_in_wsl "python3 -c \"import sys,json; print(json.load(sys.stdin)['id'])\"")
    local phase
    phase=$(echo "$create_resp" | run_in_wsl "python3 -c \"import sys,json; print(json.load(sys.stdin)['phase'])\"")
    log_ok "Sandbox created: id=${sbx_id}, phase=${phase}"

    log_info "Test 2: Execute command in sandbox..."
    local exec_resp
    exec_resp=$(run_in_wsl "curl -sf -X POST '${JIUWENBOX_URL}/api/v1/sandboxes/${sbx_id}/exec' -H 'Content-Type: application/json' -d '{\"command\": [\"python3\", \"--version\"]}'")
    local exit_code
    exit_code=$(echo "$exec_resp" | run_in_wsl "python3 -c \"import sys,json; print(json.load(sys.stdin)['exit_code'])\"")
    local stdout
    stdout=$(echo "$exec_resp" | run_in_wsl "python3 -c \"import sys,json; print(json.load(sys.stdin).get('stdout', '').strip())\"")
    if [ "$exit_code" = "0" ]; then
        log_ok "Command executed: exit_code=0, stdout='${stdout}'"
    else
        log_err "Command failed: exit_code=${exit_code}"
    fi

    log_info "Test 3: Security test (rm -rf / should be blocked)..."
    local sec_resp
    sec_resp=$(run_in_wsl "curl -sf -X POST '${JIUWENBOX_URL}/api/v1/sandboxes/${sbx_id}/exec' -H 'Content-Type: application/json' -d '{\"command\": [\"rm\", \"-rf\", \"/\"]}'")
    local sec_exit
    sec_exit=$(echo "$sec_resp" | run_in_wsl "python3 -c \"import sys,json; print(json.load(sys.stdin)['exit_code'])\"")
    if [ "$sec_exit" != "0" ]; then
        log_ok "Security test PASSED: rm -rf / blocked (exit_code=${sec_exit})"
    else
        log_err "Security test FAILED: rm -rf / was allowed!"
    fi

    log_info "Test 4: Delete sandbox..."
    local del_resp
    del_resp=$(run_in_wsl "curl -sf -X DELETE '${JIUWENBOX_URL}/api/v1/sandboxes/${sbx_id}'")
    log_ok "Sandbox deleted."

    log_ok "All tests completed."
}

cmd_clean() {
    if ! check_port; then
        log_err "jiuwenbox-server is not running."
        return 1
    fi

    log_info "Listing active sandboxes..."
    local health_resp
    health_resp=$(run_in_wsl "curl -sf '${JIUWENBOX_URL}/health'")
    local active
    active=$(echo "$health_resp" | run_in_wsl "python3 -c \"import sys,json; print(json.load(sys.stdin).get('sandboxes_active', 0))\"")

    if [ "$active" = "0" ]; then
        log_ok "No active sandboxes to clean."
        return 0
    fi

    log_warn "Found ${active} active sandboxes. Note: jiuwenbox API does not provide a bulk delete endpoint."
    log_info "Individual sandbox IDs can be retrieved via the health endpoint's active count."
    log_info "To delete a specific sandbox: curl -X DELETE ${JIUWENBOX_URL}/api/v1/sandboxes/{id}"
}

usage() {
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  install   Install dependencies and build jiuwenbox"
    echo "  deploy    Full deploy (same as install)"
    echo "  update    Pull latest source from repo, rebuild, and restart"
    echo "  start     Start jiuwenbox-server"
    echo "  stop      Stop jiuwenbox-server"
    echo "  restart   Stop and start"
    echo "  status    Show service status and sandbox count"
    echo "  health    Health check (verify connectivity)"
    echo "  test      Functional test (create/exec/delete sandbox)"
    echo "  clean     Clean up active sandbox instances"
    echo ""
    echo "Environment variables:"
    echo "  JIUWENBOX_HOME         jiuwenbox install dir (default: ~/jiuwenswarm/jiuwenbox)"
    echo "  JIUWENBOX_PORT         service port (default: 8321)"
    echo "  JIUWENBOX_WSL_DISTRO   WSL2 distro name (default: ubuntu-hermes-v2)"
    echo "  JIUWENBOX_REPO_URL     source repo URL (default: https://gitcode.com/openJiuwen/jiuwenswarm)"
}

case "${1:-}" in
    install)   cmd_install ;;
    deploy)    cmd_deploy ;;
    update)    cmd_update ;;
    start)     cmd_start ;;
    stop)      cmd_stop ;;
    restart)   cmd_restart ;;
    status)    cmd_status ;;
    health)    cmd_health ;;
    test)      cmd_test ;;
    clean)     cmd_clean ;;
    -h|--help) usage ;;
    *)         usage; exit 1 ;;
esac
