#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "" ]; then
  echo "usage: $0 <output-manifest-path>" >&2
  exit 1
fi

OUTPUT_MANIFEST="$1"

require_env() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "$name is required" >&2
    exit 1
  fi
}

require_env S3_ENDPOINT
require_env INFRA_STATE_BUCKET
require_env WG_SERVER_PRIVATE_KEY
require_env VPN_PEERS_JSON

if command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="python3"
elif command -v python >/dev/null 2>&1; then
  PYTHON_BIN="python"
else
  echo "python3/python interpreter not found" >&2
  exit 1
fi

PAYLOAD_FILE="build/bootstrap/vpn-bootstrap-secrets.env"
mkdir -p "$(dirname "$PAYLOAD_FILE")" "$(dirname "$OUTPUT_MANIFEST")"

"$PYTHON_BIN" - "$PAYLOAD_FILE" <<'PY'
import base64
import json
import os
import pathlib
import sys

payload_path = pathlib.Path(sys.argv[1])
server_private_key = os.environ.get("WG_SERVER_PRIVATE_KEY", "").strip()
peers_json = os.environ.get("VPN_PEERS_JSON", "[]").strip() or "[]"

try:
    json.loads(peers_json)
except json.JSONDecodeError as exc:
    raise SystemExit(f"VPN_PEERS_JSON is invalid JSON: {exc}")

def b64(value: str) -> str:
    return base64.b64encode(value.encode("utf-8")).decode("ascii")

payload_path.write_text(
    "\n".join(
        [
            f"WG_SERVER_PRIVATE_KEY_B64={b64(server_private_key)}",
            f"VPN_PEERS_JSON_B64={b64(peers_json)}",
            "",
        ]
    ),
    encoding="utf-8",
    newline="\n",
)
PY

RUN_ID="${GITHUB_RUN_ID:-local}"
RUN_ATTEMPT="${GITHUB_RUN_ATTEMPT:-0}"
OBJECT_KEY="bootstrap/vpn-bootstrap-secrets/${RUN_ID}-${RUN_ATTEMPT}.env"
PRESIGN_EXPIRY="${VPN_BOOTSTRAP_SECRETS_PRESIGN_EXPIRY:-3600}"

if ! printf '%s' "$PRESIGN_EXPIRY" | grep -Eq '^[0-9]+$'; then
  PRESIGN_EXPIRY="3600"
fi
if [ "$PRESIGN_EXPIRY" -gt 604800 ]; then
  PRESIGN_EXPIRY="604800"
fi
if [ "$PRESIGN_EXPIRY" -lt 300 ]; then
  PRESIGN_EXPIRY="300"
fi

aws --endpoint-url "$S3_ENDPOINT" s3 cp "$PAYLOAD_FILE" "s3://${INFRA_STATE_BUCKET}/${OBJECT_KEY}"
PAYLOAD_URL=$(aws --endpoint-url "$S3_ENDPOINT" s3 presign "s3://${INFRA_STATE_BUCKET}/${OBJECT_KEY}" --expires-in "$PRESIGN_EXPIRY")
PAYLOAD_SHA256=$(sha256sum "$PAYLOAD_FILE" | awk '{print $1}')

jq -n \
  --arg url "$PAYLOAD_URL" \
  --arg sha256 "$PAYLOAD_SHA256" \
  '{ "url": $url, "sha256": $sha256 }' > "$OUTPUT_MANIFEST"

rm -f "$PAYLOAD_FILE"
echo "Offloaded VPN bootstrap secrets to S3."
