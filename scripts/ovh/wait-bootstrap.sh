#!/usr/bin/env bash
# OVH-specific console readiness check. The shared workflow only invokes this hook.
set -euo pipefail

: "${TOFU_DIR:?TOFU_DIR is required}"
: "${OS_AUTH_URL:?OS_AUTH_URL is required}"
: "${OS_USERNAME:?OS_USERNAME is required}"
: "${OS_PASSWORD:?OS_PASSWORD is required}"
: "${OS_PROJECT_ID:?OS_PROJECT_ID is required}"
: "${OS_REGION_NAME:?OS_REGION_NAME is required}"

mkdir -p build/deploy
server_id="$(tofu -chdir="$TOFU_DIR" output -no-color -raw egress_server_id)"
for attempt in $(seq 1 48); do
  openstack console log show --lines 2000 "$server_id" > build/deploy/provider-console.log 2>&1 || true
  if grep -q "WireGuard VPN egress is configured" build/deploy/provider-console.log; then
    echo "OVH cloud-init finished and WireGuard was configured."
    exit 0
  fi
  if grep -Eiq "(Traceback|Failed to start|Missing .+| is required|No such file|sha256sum: WARNING|cloud-init.*failed|curl: \\([0-9]+\\))" build/deploy/provider-console.log; then
    echo "OVH cloud-init reported an error:" >&2
    tail -n 220 build/deploy/provider-console.log >&2
    exit 1
  fi
  echo "Waiting for OVH cloud-init marker (${attempt}/48)..."
  sleep 10
done

echo "OVH cloud-init did not report WireGuard readiness in time." >&2
tail -n 220 build/deploy/provider-console.log >&2
exit 1
