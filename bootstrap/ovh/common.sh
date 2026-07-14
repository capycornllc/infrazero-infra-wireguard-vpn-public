#!/usr/bin/env bash
set -euo pipefail

export INFRAZERO_PROVIDER="${INFRAZERO_PROVIDER:-ovh}"
_infrazero_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "${_infrazero_script_dir}/common-system.sh" ]; then
  exec bash "${_infrazero_script_dir}/common-system.sh" "$@"
elif [ -f "${_infrazero_script_dir}/../common/common-system.sh" ]; then
  exec bash "${_infrazero_script_dir}/../common/common-system.sh" "$@"
fi

echo "[common] common-system.sh not found" >&2
exit 1
