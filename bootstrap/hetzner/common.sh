#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[infrazero-vpn] %s\n' "$*"
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "This script must run as root" >&2
    exit 1
  fi
}

retry() {
  local attempts="$1"
  shift
  local delay=3
  local n=1
  until "$@"; do
    if [ "$n" -ge "$attempts" ]; then
      return 1
    fi
    log "Retry $n/$attempts failed: $*"
    n=$((n + 1))
    sleep "$delay"
  done
}
