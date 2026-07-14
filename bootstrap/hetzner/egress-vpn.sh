#!/usr/bin/env bash
set -euo pipefail

export INFRAZERO_PROVIDER="${INFRAZERO_PROVIDER:-hetzner}"
_infrazero_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "${_infrazero_script_dir}/common-vpn-egress.sh" ]; then
  exec bash "${_infrazero_script_dir}/common-vpn-egress.sh" "$@"
elif [ -f "${_infrazero_script_dir}/../common/common-vpn-egress.sh" ]; then
  exec bash "${_infrazero_script_dir}/../common/common-vpn-egress.sh" "$@"
fi

echo "[egress-vpn] common-vpn-egress.sh not found" >&2
exit 1
