#!/usr/bin/env bash
# Hetzner-only VPN credential mapping.
set -euo pipefail
set +x

if [ "${1:-}" = "--list-secret-names" ]; then
  echo "hetzner_cloud_token"
  exit 0
fi

repo_root="${INFRAZERO_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
python "${repo_root}/scripts/common/export-provider-secrets.py" \
  --required hetzner_cloud_token \
  --map HCLOUD_TOKEN=hetzner_cloud_token \
  --map TF_VAR_hcloud_token=hetzner_cloud_token

{
  echo "TF_VAR_server_image=${VPN_SERVER_IMAGE:-ubuntu-22.04}"
  echo "PROVIDER_S3_REGION=${S3_REGION:-${VPN_CLOUD_REGION:-}}"
} >> "${GITHUB_ENV:?GITHUB_ENV is required}"
