#!/usr/bin/env bash
# Materialize a single-cloud copy of this VPN template for end users.
set -euo pipefail

usage() {
  echo "usage: scripts/common/materialize-user-repo.sh <cloud> <output-dir>" >&2
  echo "  <cloud>: one of the directories under bootstrap/providers (e.g. hetzner, ovh)" >&2
}

cloud="${1:-}"
out="${2:-}"
if [ -z "$cloud" ] || [ -z "$out" ]; then
  usage
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [ ! -f "${repo_root}/bootstrap/providers/${cloud}/adapter.sh" ]; then
  echo "[materialize] unknown cloud '${cloud}': bootstrap/providers/${cloud}/adapter.sh not found" >&2
  ls -1 "${repo_root}/bootstrap/providers" >&2 || true
  exit 2
fi

for required in "bootstrap/${cloud}" "tofu/${cloud}"; do
  if [ ! -d "${repo_root}/${required}" ]; then
    echo "[materialize] cloud '${cloud}' is not fully implemented yet: missing ${required}" >&2
    exit 2
  fi
done

if [ -e "$out" ] && [ -n "$(ls -A "$out" 2>/dev/null)" ]; then
  echo "[materialize] output directory exists and is not empty: ${out}" >&2
  exit 2
fi

copy() {
  local src="$1" dst_rel="${2:-$1}"
  mkdir -p "${out}/$(dirname "$dst_rel")"
  cp -a "${repo_root}/${src}" "${out}/${dst_rel}"
}

echo "[materialize] building single-cloud VPN copy: cloud=${cloud} -> ${out}"
mkdir -p "$out"

copy bootstrap/common
mkdir -p "${out}/bootstrap/providers"
copy "bootstrap/providers/${cloud}" "bootstrap/providers/${cloud}"
copy "bootstrap/${cloud}" "bootstrap/${cloud}"

copy "tofu/${cloud}" "tofu/${cloud}"
[ -d "${repo_root}/tofu/modules" ] && copy tofu/modules
[ -d "${repo_root}/tofu/common" ] && copy tofu/common

copy scripts/common
[ -d "${repo_root}/scripts/${cloud}" ] && copy "scripts/${cloud}" "scripts/${cloud}"

copy .github
[ -d "${repo_root}/config" ] && copy config
[ -d "${repo_root}/docs" ] && copy docs
for f in README.md .gitignore .gitattributes scripts/README.md; do
  if [ -f "${repo_root}/${f}" ]; then
    copy "$f"
  fi
done

find "$out" -type d \( -name "__pycache__" -o -name ".terraform" \) -prune -exec rm -rf {} + 2>/dev/null || true
find "$out" -type f \( -name "*.pyc" -o -name ".terraform.lock.hcl" \) -delete 2>/dev/null || true

leak=0
for p in "${repo_root}/bootstrap/providers"/*/; do
  other="$(basename "$p")"
  [ "$other" = "$cloud" ] && continue
  for d in "bootstrap/${other}" "bootstrap/providers/${other}" "tofu/${other}" "scripts/${other}"; do
    if [ -e "${out}/${d}" ]; then
      echo "[materialize] LEAK: ${d} present in single-cloud copy" >&2
      leak=1
    fi
  done
done
if [ "$leak" -ne 0 ]; then
  exit 1
fi

echo "[materialize] done: $(find "$out" -type f | wc -l) files"
echo "[materialize] verify with:"
echo "  cd ${out} && BOOTSTRAP_DIR=bootstrap/${cloud} BOOTSTRAP_PROVIDER=${cloud} BOOTSTRAP_OUTPUT_DIR=/tmp/vpn-matcheck PACKAGE_BOOTSTRAP_SKIP_UPLOAD=true PACKAGE_BOOTSTRAP_COMPRESSION=none bash scripts/common/package-bootstrap.sh --manifest /tmp/vpn-matcheck/manifest.json egress-vpn"
