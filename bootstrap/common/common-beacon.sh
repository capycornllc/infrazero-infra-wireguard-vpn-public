#!/usr/bin/env bash

beacon_status() {
  local phase="${1:-unknown}"
  local message="${2:-}"
  local progress="${3:-0}"
  local state="running"
  local role="${INFRAZERO_ROLE:-egress-vpn}"
  local exit_code="${4:-0}"

  case "$phase" in
    complete) state="ready" ;;
    failed|*_failed) state="failed" ;;
  esac

  mkdir -p /etc/infrazero
  if command -v python3 >/dev/null 2>&1; then
    PHASE="$phase" MESSAGE="$message" PROGRESS="$progress" STATE="$state" ROLE="$role" EXIT_CODE="$exit_code" \
      python3 - <<'PY' > /etc/infrazero/bootstrap-status.json 2>/dev/null || true
import json
import os
from datetime import datetime, timezone

print(json.dumps({
    "state": os.environ.get("STATE", "running"),
    "phase": os.environ.get("PHASE", "unknown"),
    "message": os.environ.get("MESSAGE", ""),
    "progress": int(os.environ.get("PROGRESS", "0") or 0),
    "role": os.environ.get("ROLE", "egress-vpn"),
    "exitCode": int(os.environ.get("EXIT_CODE", "0") or 0),
    "updatedAt": datetime.now(timezone.utc).isoformat(),
}, indent=2))
PY
  else
    cat > /etc/infrazero/bootstrap-status.json <<EOF
{"state":"${state}","phase":"${phase}","message":"${message}","progress":${progress},"role":"${role}","exitCode":${exit_code}}
EOF
  fi
  chmod 600 /etc/infrazero/bootstrap-status.json 2>/dev/null || true
}

beacon_failed() {
  local phase="${1:-failed}"
  local message="${2:-Bootstrap failed}"
  local exit_code="${3:-1}"
  beacon_status "$phase" "$message" 100 "$exit_code"
}
