---
name: hermes-channel-health
description: Use when Hermes messaging channels (Feishu, QQBot, Telegram, etc.) are not responding, when gateway appears dead or stale, or when checking channel connectivity health
---

# Hermes Channel Health Check & Recovery

## Overview

Hermes Gateway manages WebSocket long connections for messaging platforms (Feishu/Lark, QQBot, etc.). When the gateway process crashes, these connections die and **do not auto-recover** — stale `gateway_state.json` and `gateway.pid` files can falsely report "connected" status.

## When to Use

- User reports messages not being received/sent on a platform
- Checking if channels are healthy
- After WSL restart or system crash
- Seeing "PID file race" errors in logs

## Quick Reference

| Command | Purpose |
|---------|---------|
| `python3 scripts/channel_health_check.py check` | Diagnose channel health |
| `python3 scripts/channel_health_check.py dryrun` | Preview recovery steps |
| `python3 scripts/channel_health_check.py recover` | Execute recovery (clean + restart) |

Script lives inside this skill at `scripts/channel_health_check.py`. Run from the skill directory:
```
python3 scripts/channel_health_check.py check
```
To find the skill directory on your system, run:
```
find ~/.hermes/skills -path '*/hermes-channel-health/scripts/channel_health_check.py'
```
Or copy the script to any convenient location — it auto-detects `HERMES_HOME` (defaults to `~/.hermes`).

## Diagnosis Steps (Manual)

If script is unavailable, follow this manual checklist:

1. **Check gateway_state.json** — `cat ~/.hermes/gateway_state.json`
   - If `updated_at` is >24h old while claiming "connected" → stale, connection likely dead

2. **Check gateway process** — `ps aux | grep hermes.*gateway`
   - If PID from state file doesn't appear in ps → gateway crashed, residual files stale

3. **Check gateway.pid** — `cat ~/.hermes/gateway.pid`
   - If PID in file doesn't match running process → stale lock file

4. **Check logs for recent activity** — `grep feishu ~/.hermes/logs/agent.log | tail -10`
   - If no recent entries for a platform claiming "connected" → WebSocket dead

5. **Check errors.log** — `grep "Lark\|PID race" ~/.hermes/logs/errors.log | tail -20`
   - `Lark: no close frame received or sent` = WS disconnected
   - `PID file race lost` = gateway crash/restart failure

## Recovery Procedure

1. **Clean stale state files**:
   ```bash
   rm -f ~/.hermes/gateway.pid ~/.hermes/gateway_state.json
   ```

2. **Kill any zombie gateway** (if process exists but is broken):
   ```bash
   # Find and kill stale gateway PIDs
   ps aux | grep -E 'hermes.*gateway' | grep -v grep | awk '{print $2}' | xargs -r kill
   ```

3. **Restart gateway**:
   ```bash
   hermes gateway run --replace
   ```
   Run in background or via tmux for persistence.

4. **Verify recovery** — wait ~8 seconds then:
   ```bash
   cat ~/.hermes/gateway_state.json
   # Check: all platforms show "connected" with fresh timestamps
   # Check logs: "Connected in websocket mode" appears
   grep "Connected in websocket" ~/.hermes/logs/agent.log | tail -5
   ```

## Common Pitfalls

| Pitfall | Cause | Fix |
|---------|-------|-----|
| State says "connected" but messages don't arrive | gateway_state.json is stale | Delete state files + restart gateway |
| Gateway won't start — "PID file race" errors | Old gateway.pid blocking new instance | Delete gateway.pid first |
| Feishu WS dies periodically | Lark SDK WS timeout (normal, auto-reconnects) | Only worry if gateway is also dead |
| QQBot persistent disconnect | QQ gateway URL unreachable | Check QQ Bot credentials in .env |
| Feishu "Failed to send media: File not found" | MEDIA path regex matching literal text | Ensure response doesn't contain raw MEDIA tags on Feishu |

## The Key Insight

**gateway_state.json is NOT a live heartbeat — it's a write-once snapshot.** After gateway crashes, this file retains "connected" status forever. Always cross-check with: (1) actual process running, (2) fresh timestamps (<1h old), (3) recent log activity.