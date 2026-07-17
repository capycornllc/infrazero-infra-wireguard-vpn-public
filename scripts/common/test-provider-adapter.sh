#!/usr/bin/env bash
set -euo pipefail

provider="${1:?provider directory is required}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
adapter="${repo_root}/bootstrap/providers/${provider}/adapter.sh"
# shellcheck disable=SC1090
source "$adapter"

required_functions=(
  provider_route_mode
  provider_outbound_defaults
  provider_detect_public_iface
  provider_admin_useradd_options
)
for function_name in "${required_functions[@]}"; do
  if ! declare -F "$function_name" >/dev/null; then
    echo "[adapter-contract] ${provider}: missing ${function_name}" >&2
    exit 1
  fi
done
if [ "${INFRAZERO_PROVIDER:-}" != "$provider" ]; then
  echo "[adapter-contract] ${provider}: invalid INFRAZERO_PROVIDER" >&2
  exit 1
fi
echo "[adapter-contract] passed: ${provider}"
