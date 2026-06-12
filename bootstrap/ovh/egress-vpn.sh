#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

require_root

ENV_FILE="/opt/infrazero/vpn.env"
if [ ! -f "$ENV_FILE" ]; then
  echo "Missing $ENV_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

require_var() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "$name is required" >&2
    exit 1
  fi
}

require_var WG_LISTEN_PORT
require_var WG_SERVER_ADDRESS
require_var VPN_BOOTSTRAP_SECRETS_URL
require_var VPN_BOOTSTRAP_SECRETS_SHA256

SECRETS_ENV_FILE="/opt/infrazero/bootstrap/vpn-bootstrap-secrets.env"
log "Downloading WireGuard bootstrap secrets"
curl -fsSL "$VPN_BOOTSTRAP_SECRETS_URL" -o "$SECRETS_ENV_FILE"
echo "${VPN_BOOTSTRAP_SECRETS_SHA256}  ${SECRETS_ENV_FILE}" | sha256sum -c -
chmod 600 "$SECRETS_ENV_FILE"
# shellcheck disable=SC1090
source "$SECRETS_ENV_FILE"
rm -f "$SECRETS_ENV_FILE"

require_var WG_SERVER_PRIVATE_KEY_B64
require_var VPN_PEERS_JSON_B64

log "Installing WireGuard packages"
export DEBIAN_FRONTEND=noninteractive
retry 5 apt-get update -y
retry 5 apt-get install -y wireguard iptables ca-certificates python3

mkdir -p /etc/wireguard
chmod 700 /etc/wireguard

WAN_IF="$(ip route show default | awk '{print $5; exit}')"
if [ -z "$WAN_IF" ]; then
  echo "Could not detect default network interface" >&2
  exit 1
fi

SERVER_PRIVATE_KEY="$(printf '%s' "$WG_SERVER_PRIVATE_KEY_B64" | base64 -d)"
PEERS_JSON="$(printf '%s' "$VPN_PEERS_JSON_B64" | base64 -d)"
export PEERS_JSON

log "Rendering /etc/wireguard/wg0.conf"
umask 077
cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = ${WG_SERVER_ADDRESS}
ListenPort = ${WG_LISTEN_PORT}
PrivateKey = ${SERVER_PRIVATE_KEY}
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o ${WAN_IF} -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o ${WAN_IF} -j MASQUERADE

EOF

python3 - <<'PY' >> /etc/wireguard/wg0.conf
import json
import os

peers = json.loads(os.environ.get("PEERS_JSON", "[]"))
for peer in peers:
    if not peer.get("publicKey") or not peer.get("address"):
        continue
    print("[Peer]")
    print(f"# {peer.get('name') or peer.get('id') or 'peer'}")
    print(f"PublicKey = {peer['publicKey']}")
    if peer.get("presharedKey"):
        print(f"PresharedKey = {peer['presharedKey']}")
    print(f"AllowedIPs = {peer['address']}")
    print()
PY

chmod 600 /etc/wireguard/wg0.conf

cat > /etc/sysctl.d/99-infrazero-vpn.conf <<'EOF'
net.ipv4.ip_forward=1
EOF
sysctl --system

log "Starting WireGuard"
systemctl enable wg-quick@wg0
systemctl restart wg-quick@wg0

log "WireGuard VPN egress is configured"
