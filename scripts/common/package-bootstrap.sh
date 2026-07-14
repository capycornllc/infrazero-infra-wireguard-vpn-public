#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: scripts/common/package-bootstrap.sh --manifest <path> <role...>

Environment:
  BOOTSTRAP_DIR                  Provider bootstrap directory, e.g. bootstrap/hetzner.
  BOOTSTRAP_PROVIDER             Provider adapter name, e.g. hetzner or ovh.
  S3_ENDPOINT                    Object storage endpoint.
  INFRA_STATE_BUCKET             Object storage bucket.

Optional:
  BOOTSTRAP_COMMON_DIR           Default: bootstrap/common.
  BOOTSTRAP_PROVIDERS_DIR        Default: bootstrap/providers.
  BOOTSTRAP_OUTPUT_DIR           Default: build/bootstrap.
  BOOTSTRAP_PRESIGN_EXPIRY       Default: 3600.
  PACKAGE_BOOTSTRAP_SKIP_UPLOAD  true = no S3 upload, file:// URLs.
  PACKAGE_BOOTSTRAP_COMPRESSION  zstd (default) or none.
EOF
}

manifest_path=""
if [ "${1:-}" = "--manifest" ]; then
  manifest_path="${2:-}"
  shift 2
fi

if [ -z "$manifest_path" ] || [ "$#" -lt 1 ]; then
  usage
  exit 2
fi

: "${BOOTSTRAP_DIR:?BOOTSTRAP_DIR is required}"

repo_root="$(pwd -P)"
provider_dir="${repo_root}/${BOOTSTRAP_DIR}"
common_dir="${repo_root}/${BOOTSTRAP_COMMON_DIR:-bootstrap/common}"
provider="${BOOTSTRAP_PROVIDER:-$(basename "$BOOTSTRAP_DIR")}"
adapter_dir="${repo_root}/${BOOTSTRAP_PROVIDERS_DIR:-bootstrap/providers}/${provider}"
output_dir="${BOOTSTRAP_OUTPUT_DIR:-build/bootstrap}"
presign_expiry="${BOOTSTRAP_PRESIGN_EXPIRY:-3600}"
skip_upload="${PACKAGE_BOOTSTRAP_SKIP_UPLOAD:-false}"
compression="${PACKAGE_BOOTSTRAP_COMPRESSION:-zstd}"

case "$compression" in
  zstd) tar_compression_args=(--zstd) ;;
  none) tar_compression_args=() ;;
  *)
    echo "[package-bootstrap] unsupported PACKAGE_BOOTSTRAP_COMPRESSION: $compression" >&2
    exit 2
    ;;
esac

if [ ! -d "$provider_dir" ]; then
  echo "[package-bootstrap] provider bootstrap directory not found: $BOOTSTRAP_DIR" >&2
  exit 1
fi
if [ ! -d "$common_dir" ]; then
  echo "[package-bootstrap] common bootstrap directory not found: $common_dir" >&2
  exit 1
fi
if [ ! -f "${adapter_dir}/adapter.sh" ]; then
  echo "[package-bootstrap] provider adapter not found: ${adapter_dir}/adapter.sh" >&2
  exit 1
fi

if [ "$skip_upload" != "true" ]; then
  : "${S3_ENDPOINT:?S3_ENDPOINT is required}"
  : "${INFRA_STATE_BUCKET:?INFRA_STATE_BUCKET is required}"
fi

mkdir -p "$output_dir"
chmod +x "${provider_dir}"/*.sh
chmod +x "${common_dir}"/*.sh
chmod +x "${adapter_dir}/adapter.sh"

json_escape() {
  printf '%s' "${1:-}" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

manifest="{"
first=true

for role in "$@"; do
  if [ "$role" != "egress-vpn" ]; then
    echo "[package-bootstrap] unsupported VPN role: $role" >&2
    exit 1
  fi

  for required in \
    "${provider_dir}/common.sh" \
    "${provider_dir}/egress-vpn.sh" \
    "${common_dir}/common-beacon.sh" \
    "${common_dir}/common-base.sh" \
    "${common_dir}/common-system.sh" \
    "${common_dir}/common-vpn-egress.sh" \
    "${adapter_dir}/adapter.sh"; do
    if [ ! -f "$required" ]; then
      echo "[package-bootstrap] required file missing for ${role}: ${required}" >&2
      exit 1
    fi
  done

  archive="${output_dir}/${role}.tar.zst"
  echo "[package-bootstrap] packaging ${role} for provider ${provider}"
  tar "${tar_compression_args[@]}" -cf "$archive" \
    -C "$provider_dir" common.sh egress-vpn.sh \
    -C "$common_dir" common-beacon.sh common-base.sh common-system.sh common-vpn-egress.sh \
    -C "$adapter_dir" adapter.sh

  sha="$(sha256sum "$archive" | awk '{print $1}')"
  if [ "$skip_upload" = "true" ]; then
    url="file://${archive}"
  else
    key="bootstrap/${provider}/${role}.tar.zst"
    aws --endpoint-url "$S3_ENDPOINT" s3 cp "$archive" "s3://${INFRA_STATE_BUCKET}/${key}"
    url="$(aws --endpoint-url "$S3_ENDPOINT" s3 presign "s3://${INFRA_STATE_BUCKET}/${key}" --expires-in "$presign_expiry")"
    curl -fsSL "$url" -o "${archive}.presign-check"
    echo "$sha  ${archive}.presign-check" | sha256sum -c -
    rm -f "${archive}.presign-check"
  fi

  if [ "$first" = "true" ]; then
    first=false
  else
    manifest="${manifest},"
  fi
  manifest="${manifest}\"$(json_escape "$role")\":{\"url\":\"$(json_escape "$url")\",\"sha256\":\"$(json_escape "$sha")\"}"
done

manifest="${manifest}}"
mkdir -p "$(dirname "$manifest_path")"
printf '%s\n' "$manifest" > "$manifest_path"
