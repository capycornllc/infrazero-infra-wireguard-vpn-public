#!/usr/bin/env bash
# Product-compatible bootstrap status with App-level diagnostics and redaction.

infrazero_redact() {
  local value="${1:-}"
  value=$(printf '%s' "$value" | sed -E 's/(password|token|key|secret|private_key|preshared)=[^ ]*/\1=***REDACTED***/gI' 2>/dev/null || printf '%s' "$value")
  value=$(printf '%s' "$value" | sed -E 's/[A-Za-z0-9+\/=]{40,}/***REDACTED***/g' 2>/dev/null || printf '%s' "$value")
  printf '%s' "$value"
}

beacon_write() {
  local state="$1" phase="$2" message="$3" progress="${4:-0}"
  local exit_code="${5:-0}" category="${6:-}" code="${7:-}"
  local file="${8:-}" line="${9:-}" command="${10:-}"
  local attempt="${11:-}" max_attempts="${12:-}" recoverable="${13:-}"
  local role="${INFRAZERO_ROLE:-egress-vpn}"

  message="$(infrazero_redact "$message")"
  command="$(infrazero_redact "$command")"
  export INFRAZERO_CURRENT_PHASE="$phase"
  export INFRAZERO_CURRENT_PROGRESS="$progress"
  mkdir -p /etc/infrazero

  if command -v python3 >/dev/null 2>&1; then
    STATE="$state" PHASE="$phase" MESSAGE="$message" PROGRESS="$progress" \
    ROLE="$role" EXIT_CODE="$exit_code" CATEGORY="$category" CODE="$code" \
    FILE_NAME="$file" LINE_NO="$line" COMMAND_TEXT="$command" \
    ATTEMPT="$attempt" MAX_ATTEMPTS="$max_attempts" RECOVERABLE="$recoverable" \
      python3 - <<'PY' > /etc/infrazero/bootstrap-status.json 2>/dev/null || true
import json, os
from datetime import datetime, timezone

def integer(name, default=0):
    try:
        return int(os.environ.get(name, "") or default)
    except ValueError:
        return default

def optional(name):
    value = os.environ.get(name, "")
    return value if value else None

updated = datetime.now(timezone.utc).isoformat()
exit_code = integer("EXIT_CODE")
print(json.dumps({
    "state": os.environ.get("STATE", "running"),
    "phase": os.environ.get("PHASE", "unknown"),
    "message": os.environ.get("MESSAGE", ""),
    "progress": integer("PROGRESS"),
    "role": os.environ.get("ROLE", "egress-vpn"),
    "exitCode": exit_code,
    "exit_code": exit_code,
    "updatedAt": updated,
    "updated_at": updated,
    "category": optional("CATEGORY"),
    "code": optional("CODE"),
    "file": optional("FILE_NAME"),
    "line": optional("LINE_NO"),
    "command": optional("COMMAND_TEXT"),
    "attempt": integer("ATTEMPT") if optional("ATTEMPT") else None,
    "maxAttempts": integer("MAX_ATTEMPTS") if optional("MAX_ATTEMPTS") else None,
    "recoverable": os.environ.get("RECOVERABLE", "").lower() == "true"
        if optional("RECOVERABLE") else None,
}, indent=2))
PY
  else
    printf '{"state":"%s","phase":"%s","progress":%s,"role":"%s","exitCode":%s}\n' \
      "$state" "$phase" "$progress" "$role" "$exit_code" \
      > /etc/infrazero/bootstrap-status.json
  fi
  chmod 600 /etc/infrazero/bootstrap-status.json 2>/dev/null || true
}

beacon_status() {
  local phase="${1:-unknown}" message="${2:-}" progress="${3:-0}" state="running"
  case "$phase" in complete) state="ready" ;; failed|*_failed) state="failed" ;; esac
  beacon_write "$state" "$phase" "$message" "$progress"
}

beacon_retrying() {
  beacon_write "retrying" "$1" "$2" "${3:-0}" 0 "${4:-external}" "${5:-RETRY}" "" "" "" "${6:-}" "${7:-}" true
}

beacon_degraded() {
  beacon_write "degraded" "$1" "$2" "${3:-0}" 0 "${4:-external}" "${5:-DEGRADED}" "" "" "" "" "" true
}

# Keep the historical target signature: phase, message, exit code.
beacon_failed() {
  beacon_write "failed" "${1:-failed}" "${2:-Bootstrap failed}" 100 "${3:-1}" \
    "${4:-script}" "${5:-SCRIPT_ERROR}" "${6:-}" "${7:-}" "${8:-}"
}

infrazero_trap_error() {
  local exit_code="$1" line="$2" command="$3"
  beacon_write "failed" "${INFRAZERO_CURRENT_PHASE:-failed}" \
    "Script failed at line ${line}" "${INFRAZERO_CURRENT_PROGRESS:-0}" \
    "$exit_code" script SCRIPT_ERROR "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}" "$line" "$command"
  exit "$exit_code"
}

infrazero_install_error_trap() {
  trap 'infrazero_trap_error "$?" "$LINENO" "$BASH_COMMAND"' ERR
}
