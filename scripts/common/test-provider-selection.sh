#!/usr/bin/env bash
set -euo pipefail

provider="${1:?provider directory is required}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/common/provider-contract.sh
source "${repo_root}/scripts/common/provider-contract.sh"
infrazero_validate_provider_contract "$repo_root" "$provider"

credential_script="${repo_root}/scripts/${provider}/ci-credentials.sh"
secrets_json="$({ bash "$credential_script" --list-secret-names || exit 1; } | python -c '
import json, sys
names = [line.strip() for line in sys.stdin if line.strip()]
print(json.dumps({name: f"synthetic-{index}" for index, name in enumerate(names, 1)}))
')"
github_env="$(mktemp)"
trap 'rm -f "$github_env"' EXIT

VPN_CLOUD_PROVIDER="$provider" GITHUB_ENV="$github_env" \
  bash "${repo_root}/scripts/common/select-provider.sh"
VPN_CLOUD_REGION="US-TEST-1" INFRAZERO_REPO_ROOT="$repo_root" \
  SECRETS_JSON="$secrets_json" GITHUB_ENV="$github_env" \
  bash "$credential_script"

grep -q "^CLOUD_PROVIDER_DIR=${provider}$" "$github_env"
grep -q "^TOFU_DIR=tofu/${provider}$" "$github_env"
grep -q "^SCRIPTS_DIR=scripts/${provider}$" "$github_env"
grep -q "^BOOTSTRAP_DIR=bootstrap/${provider}$" "$github_env"
echo "[provider-contract] selection test passed: ${provider}"
