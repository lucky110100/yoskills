#!/usr/bin/env python3
"""
Hermes Gateway Channel Health Check & Recovery Script

Problem Summary (2026-06-11 incident):
  - Gateway PID file had stale data (PID 289, from boot time)
  - Gateway process was actually NOT running (no matching PID in ps)
  - Feishu WebSocket had disconnected on 6/9 and never recovered
  - QQBot had been disconnected since 5/27
  - gateway_state.json showed "connected" for feishu — but that was a
    stale timestamp from 5/25, not reflecting reality
  - Multiple PID file race errors on 6/10 showed gateway had crashed
    and failed to restart properly

Root Cause:
  Gateway crashed during PID race on 6/10. Feishu's WebSocket long
  connection (Lark SDK) died along with the gateway process. The
  residual gateway_state.json and gateway.pid files contained stale
  "connected" status, giving a false impression of health. Because
  no gateway was running, no reconnection attempts occurred.

Discovery Process:
  1. Checked gateway_state.json — saw "connected" for feishu, but
     timestamp was 5/25 (2 weeks old) → clearly stale
  2. Checked ps for gateway process — PID 289 not found → process dead
  3. Checked gateway.pid file — still had old PID 289 → stale lock file
  4. Checked logs — last feishu activity was 6/9 02:12, then silence
     → WebSocket had died and not recovered
  5. Found 5 "PID file race lost" errors on 6/10 → root cause of crash
  6. Found Lark "no close frame received or sent" errors → WS disconnections

Recovery:
  1. rm gateway.pid + gateway_state.json (clear stale state)
  2. hermes gateway run --replace (restart gateway)
  3. Verify gateway_state.json shows fresh connected timestamps
  4. Verify logs show "Connected in websocket mode" lines

This script automates the above diagnosis and recovery.
"""

import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

HERMES_HOME = Path(os.environ.get("HERMES_HOME", Path.home() / ".hermes"))
GATEWAY_PID_FILE = HERMES_HOME / "gateway.pid"
GATEWAY_STATE_FILE = HERMES_HOME / "gateway_state.json"
AGENT_LOG = HERMES_HOME / "logs" / "agent.log"
ERRORS_LOG = HERMES_HOME / "logs" / "errors.log"

# ── Helpers ──────────────────────────────────────────────────────────

def _now_iso():
    return datetime.now(timezone.utc).isoformat()

def _read_json(path: Path, default=None):
    try:
        with open(path) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return default

def _run(cmd: str, timeout=10) -> str:
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        return r.stdout.strip()
    except subprocess.TimeoutExpired:
        return ""

def _is_process_alive(pid: int) -> bool:
    """Check if a PID is actually running and is a hermes process."""
    out = _run(f"ps -p {pid} -o comm= 2>/dev/null")
    if not out:
        return False
    # Accept python/hermes processes
    return "python" in out.lower() or "hermes" in out.lower()

def _hours_since(ts_str: str) -> float:
    """Parse ISO timestamp and return hours elapsed."""
    try:
        # Handle both +00:00 and Z suffixes
        ts_str = ts_str.replace("Z", "+00:00")
        ts = datetime.fromisoformat(ts_str)
        elapsed = datetime.now(timezone.utc) - ts
        return elapsed.total_seconds() / 3600
    except (ValueError, TypeError):
        return 9999  # unparsable = very stale

def _last_log_ts_for(keyword: str, log_path: Path) -> str:
    """Return the timestamp string of the last log line matching keyword."""
    try:
        with open(log_path) as f:
            lines = f.readlines()
        for line in reversed(lines):
            if keyword.lower() in line.lower():
                # Extract timestamp like "2026-06-11 09:34:57"
                parts = line.split(",", 1)
                if parts:
                    return parts[0].strip()
    except FileNotFoundError:
        pass
    return ""

# ── Diagnosis ────────────────────────────────────────────────

def diagnose() -> dict:
    """Run all health checks and return structured report."""
    report = {
        "timestamp": _now_iso(),
        "issues": [],
        "healthy": True,
    }

    # 1. Check gateway process alive
    pid_data = _read_json(GATEWAY_PID_FILE)
    state_data = _read_json(GATEWAY_STATE_FILE)

    if not pid_data and not state_data:
        report["issues"].append({
            "severity": "CRITICAL",
            "check": "gateway_pid_file",
            "detail": "No gateway.pid or gateway_state.json found — gateway never started or files cleaned",
        })
        report["healthy"] = False
        return report

    recorded_pid = pid_data.get("pid") if pid_data else None
    state_pid = state_data.get("pid") if state_data else None
    effective_pid = recorded_pid or state_pid

    if effective_pid and not _is_process_alive(effective_pid):
        report["issues"].append({
            "severity": "CRITICAL",
            "check": "gateway_process",
            "detail": f"Gateway PID {effective_pid} in state files but process NOT running — gateway has crashed",
            "pid_file_pid": recorded_pid,
            "state_pid": state_pid,
        })
        report["healthy"] = False
    elif effective_pid and _is_process_alive(effective_pid):
        report["gateway_pid"] = effective_pid
        report["gateway_alive"] = True

    # 2. Check ps for any hermes gateway process (even if PID mismatch)
    ps_out = _run("ps aux | grep -E 'hermes.*gateway' | grep -v grep")
    if not ps_out and not report.get("gateway_alive"):
        report["issues"].append({
            "severity": "CRITICAL",
            "check": "gateway_ps_scan",
            "detail": "No hermes gateway process found in ps output",
        })
        report["healthy"] = False
        report["gateway_alive"] = False
    elif ps_out:
        report["ps_gateway_lines"] = ps_out

    # 3. Check per-platform state freshness
    platforms = state_data.get("platforms", {}) if state_data else {}
    for plat_name, plat_state in platforms.items():
        conn_state = plat_state.get("state", "unknown")
        updated_at = plat_state.get("updated_at", "")
        hours_old = _hours_since(updated_at) if updated_at else 9999

        if conn_state == "connected" and hours_old > 24:
            report["issues"].append({
                "severity": "WARNING",
                "check": f"{plat_name}_state_stale",
                "detail": f"{plat_name} claims 'connected' but state timestamp is {hours_old:.1f}h old (updated: {updated_at}) — likely stale, actual WS may be dead",
                "hours_old": round(hours_old, 1),
            })
            report["healthy"] = False
        elif conn_state == "disconnected":
            report["issues"].append({
                "severity": "HIGH",
                "check": f"{plat_name}_disconnected",
                "detail": f"{plat_name} is disconnected (since: {updated_at})",
            })
            report["healthy"] = False

        report[f"{plat_name}_state"] = conn_state
        report[f"{plat_name}_updated"] = updated_at
        report[f"{plat_name}_hours_old"] = round(hours_old, 1)

    # 4. Check for stale PID file vs actual PID mismatch
    if recorded_pid and state_pid and recorded_pid != state_pid:
        report["issues"].append({
            "severity": "WARNING",
            "check": "pid_mismatch",
            "detail": f"gateway.pid has PID {recorded_pid} but gateway_state has PID {state_pid} — possible crash restart left inconsistent files",
        })

    # 5. Check recent Lark/Feishu WS errors
    lark_errors = []
    try:
        with open(ERRORS_LOG) as f:
            lines = f.readlines()
        for line in reversed(lines[-200:]):
            if "Lark" in line and "close frame" in line:
                lark_errors.append(line.strip())
    except FileNotFoundError:
        pass
    if lark_errors:
        report["issues"].append({
            "severity": "MEDIUM",
            "check": "lark_ws_disconnects",
            "detail": f"{len(lark_errors)} Lark WebSocket disconnect errors in recent logs",
            "latest": lark_errors[-1] if lark_errors else None,
        })

    # 6. Check for PID race errors
    race_errors = 0
    try:
        with open(ERRORS_LOG) as f:
            for line in f:
                if "PID file race" in line:
                    race_errors += 1
    except FileNotFoundError:
        pass
    if race_errors > 0:
        report["issues"].append({
            "severity": "MEDIUM",
            "check": "pid_race_errors",
            "detail": f"{race_errors} PID file race errors in errors.log — gateway may have crashed on restart",
        })

    # 7. Check last feishu activity in agent.log
    last_feishu_ts = _last_log_ts_for("feishu", AGENT_LOG)
    last_lark_ts = _last_log_ts_for("lark", AGENT_LOG)
    report["last_feishu_log_ts"] = last_feishu_ts
    report["last_lark_log_ts"] = last_lark_ts

    if not last_feishu_ts and platforms.get("feishu", {}).get("state") == "connected":
        # No recent feishu logs but claims connected — suspicious
        report["issues"].append({
            "severity": "WARNING",
            "check": "feishu_log_silence",
            "detail": "Feishu claims connected but no feishu-related log entries found — WebSocket may be dead",
        })

    return report

# ── Recovery ────────────────────────────────────────────────────

def recover(dry_run=False) -> dict:
    """Attempt to recover gateway by cleaning stale state and restarting."""
    result = {"dry_run": dry_run, "steps": [], "success": False}

    # Step 1: Clean stale PID and state files
    for f in [GATEWAY_PID_FILE, GATEWAY_STATE_FILE]:
        if f.exists():
            action = f"rm {f}"
            result["steps"].append(action)
            if not dry_run:
                f.unlink()
                result["steps"].append(f"  -> deleted")

    # Step 2: Kill any zombie gateway processes
    ps_out = _run("ps aux | grep -E 'hermes.*gateway' | grep -v grep | awk '{print $2}'")
    if ps_out:
        pids = ps_out.strip().split("\n")
        for pid in pids:
            action = f"kill {pid.strip()}"
            result["steps"].append(action)
            if not dry_run:
                _run(f"kill {pid.strip()} 2>/dev/null")
                result["steps"].append(f"  -> killed PID {pid.strip()}")

    # Step 3: Restart gateway
    action = "hermes gateway run --replace (background)"
    result["steps"].append(action)
    if not dry_run:
        subprocess.Popen(
            ["hermes", "gateway", "run", "--replace"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        # Wait for gateway to start and connect
        time.sleep(8)

        # Step 4: Verify recovery
        state_data = _read_json(GATEWAY_STATE_FILE)
        if state_data and state_data.get("gateway_state") == "running":
            result["success"] = True
            result["new_state"] = state_data

            platforms = state_data.get("platforms", {})
            for plat_name, plat_state in platforms.items():
                if plat_state.get("state") == "connected":
                    result["steps"].append(f"  -> {plat_name} connected OK")
                else:
                    result["steps"].append(f"  -> {plat_name} still {plat_state.get('state')}")
        else:
            result["success"] = False
            result["steps"].append("  -> gateway did not start properly")

    return result

# ── Main ──────────────────────────────────────────────────────

def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "check"

    if mode == "check":
        report = diagnose()
        print(json.dumps(report, indent=2, ensure_ascii=False))
        if not report["healthy"]:
            print("\n⚠️  Issues detected! Run with 'recover' to fix, or 'dryrun' to preview.")
        else:
            print("\n✅ All channels healthy.")

    elif mode == "recover":
        print("🔧 Recovering gateway...")
        result = recover(dry_run=False)
        print(json.dumps(result, indent=2, ensure_ascii=False))
        if result["success"]:
            print("\n✅ Recovery successful!")
        else:
            print("\n❌ Recovery failed — check logs manually.")

    elif mode == "dryrun":
        print("📋 Dry run — previewing recovery steps...")
        result = recover(dry_run=True)
        print(json.dumps(result, indent=2, ensure_ascii=False))

    else:
        print(f"Usage: {sys.argv[0]} [check|recover|dryrun]")
        print("  check   — Diagnose channel health (default)")
        print("  recover — Clean stale state and restart gateway")
        print("  dryrun  — Preview recovery steps without executing")


if __name__ == "__main__":
    main()