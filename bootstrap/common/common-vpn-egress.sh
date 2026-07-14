#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="/var/log/infrazero-bootstrap.log"
if [ -z "${_INFRAZERO_LOG_REDIRECTED:-}" ]; then
  exec > >(tee -a "$LOG_FILE") 2>&1
  export _INFRAZERO_LOG_REDIRECTED=1
fi

export INFRAZERO_ROLE="${INFRAZERO_ROLE:-egress-vpn}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "${SCRIPT_DIR}/common-beacon.sh" ]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/common-beacon.sh"
else
  beacon_status() { return 0; }
  beacon_failed() { return 0; }
fi

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common-base.sh"
infrazero_load_provider_adapter "$SCRIPT_DIR"
infrazero_require_root

on_error() {
  local rc="$?"
  beacon_failed "role_failed" "WireGuard VPN bootstrap failed" "$rc"
  exit "$rc"
}
trap on_error ERR

ENV_FILE="/opt/infrazero/vpn.env"
if [ ! -f "$ENV_FILE" ]; then
  echo "Missing $ENV_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

infrazero_require_env WG_LISTEN_PORT
infrazero_require_env WG_SERVER_ADDRESS
infrazero_require_env VPN_ADMIN_WG_LISTEN_PORT
infrazero_require_env VPN_ADMIN_WG_SERVER_ADDRESS
infrazero_require_env VPN_BOOTSTRAP_SECRETS_URL
infrazero_require_env VPN_BOOTSTRAP_SECRETS_SHA256

download_bootstrap_secrets() {
  local url="$1"
  local sha256="$2"
  local target="$3"
  local http_code=""

  for attempt in {1..20}; do
    rm -f "$target"
    http_code=$(curl -sS -L -o "$target" -w "%{http_code}" --connect-timeout 5 --max-time 30 "$url" || true)
    if [ "$http_code" = "200" ]; then
      echo "$sha256  $target" | sha256sum -c -
      chmod 600 "$target"
      return 0
    fi
    infrazero_log "WireGuard bootstrap secrets are not reachable yet (http $http_code, attempt $attempt/20)"
    sleep 3
  done

  rm -f "$target"
  echo "Failed to download WireGuard bootstrap secrets" >&2
  return 1
}

SECRETS_ENV_FILE="/opt/infrazero/bootstrap/vpn-bootstrap-secrets.env"
beacon_status "downloading_secrets" "Downloading WireGuard bootstrap secrets" 55
download_bootstrap_secrets "$VPN_BOOTSTRAP_SECRETS_URL" "$VPN_BOOTSTRAP_SECRETS_SHA256" "$SECRETS_ENV_FILE"
# shellcheck disable=SC1090
source "$SECRETS_ENV_FILE"
rm -f "$SECRETS_ENV_FILE"

infrazero_require_env WG_SERVER_PRIVATE_KEY_B64
infrazero_require_env VPN_PEERS_JSON_B64
infrazero_require_env VPN_ADMIN_WG_SERVER_PRIVATE_KEY_B64
infrazero_require_env VPN_ADMIN_PEERS_JSON_B64

beacon_status "installing_wireguard" "Installing WireGuard packages" 60
infrazero_install_base_packages "vpn-egress" wireguard wireguard-tools iptables ca-certificates python3

mkdir -p /etc/wireguard
chmod 700 /etc/wireguard

WAN_IF="$(provider_detect_public_iface || true)"
if [ -z "$WAN_IF" ]; then
  echo "Could not detect default network interface" >&2
  exit 1
fi

render_peers() {
  local json_env_name="$1"
  local label="$2"
  JSON_ENV_NAME="$json_env_name" LABEL="$label" python3 - <<'PY'
import json
import os

name = os.environ["JSON_ENV_NAME"]
label = os.environ.get("LABEL", "peer")
peers = json.loads(os.environ.get(name, "[]") or "[]")
for peer in peers:
    if not isinstance(peer, dict):
        continue
    public_key = peer.get("publicKey") or peer.get("public_key")
    allowed = peer.get("address") or peer.get("allowedIps") or peer.get("allowedIPs")
    if isinstance(allowed, list):
        allowed = ", ".join(str(item).strip() for item in allowed if str(item).strip())
    if not public_key or not allowed:
        continue
    print("[Peer]")
    print(f"# {peer.get('name') or peer.get('id') or label}")
    print(f"PublicKey = {public_key}")
    if peer.get("presharedKey"):
        print(f"PresharedKey = {peer['presharedKey']}")
    print(f"AllowedIPs = {allowed}")
    print()
PY
}

SERVER_PRIVATE_KEY="$(printf '%s' "$WG_SERVER_PRIVATE_KEY_B64" | base64 -d)"
PEERS_JSON="$(printf '%s' "$VPN_PEERS_JSON_B64" | base64 -d)"
export PEERS_JSON

ADMIN_SERVER_PRIVATE_KEY="$(printf '%s' "$VPN_ADMIN_WG_SERVER_PRIVATE_KEY_B64" | base64 -d)"
ADMIN_PEERS_JSON="$(printf '%s' "$VPN_ADMIN_PEERS_JSON_B64" | base64 -d)"
export ADMIN_PEERS_JSON

beacon_status "configuring_product_wireguard" "Configuring product WireGuard" 70
umask 077
cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = ${WG_SERVER_ADDRESS}
ListenPort = ${WG_LISTEN_PORT}
PrivateKey = ${SERVER_PRIVATE_KEY}
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o ${WAN_IF} -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o ${WAN_IF} -j MASQUERADE

EOF
render_peers "PEERS_JSON" "vpn-peer" >> /etc/wireguard/wg0.conf
chmod 600 /etc/wireguard/wg0.conf

beacon_status "configuring_admin_wireguard" "Configuring admin WireGuard" 78
cat > /etc/wireguard/wg-admin.conf <<EOF
[Interface]
Address = ${VPN_ADMIN_WG_SERVER_ADDRESS}
ListenPort = ${VPN_ADMIN_WG_LISTEN_PORT}
PrivateKey = ${ADMIN_SERVER_PRIVATE_KEY}

EOF
render_peers "ADMIN_PEERS_JSON" "admin-peer" >> /etc/wireguard/wg-admin.conf
chmod 600 /etc/wireguard/wg-admin.conf

beacon_status "starting_wireguard" "Starting WireGuard services" 84
systemctl enable wg-quick@wg0
systemctl restart wg-quick@wg0
systemctl enable wg-quick@wg-admin
systemctl restart wg-quick@wg-admin

beacon_status "restricting_ssh" "Restricting SSH to admin WireGuard" 90
ADMIN_WG_SERVER_IP="$(infrazero_ipv4_from_cidr "$VPN_ADMIN_WG_SERVER_ADDRESS")"
export SSH_LISTEN_ADDRESS="$ADMIN_WG_SERVER_IP"
infrazero_harden_ssh "vpn-egress"

beacon_status "writing_status_command" "Writing VPN runtime status command" 94
cat > /usr/local/bin/infrazero-vpn-status <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="/opt/infrazero/vpn.env"
if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

line() {
  local state="$1"
  local message="$2"
  printf '[%s] %s\n' "$state" "$message"
}

check_service() {
  local unit="$1"
  local label="$2"
  if systemctl is-active --quiet "$unit"; then
    line ready "$label active"
  else
    line error "$label not active"
  fi
}

check_wg_iface() {
  local iface="$1"
  local label="$2"
  if wg show "$iface" >/dev/null 2>&1; then
    local peers
    peers="$(wg show "$iface" peers 2>/dev/null | wc -l | tr -d '[:space:]')"
    line ready "$label interface present (${peers:-0} peers)"
  else
    line error "$label interface missing"
  fi
}

check_udp_listener() {
  local port="$1"
  local label="$2"
  if ss -lunp 2>/dev/null | grep -Eq ":${port}\b"; then
    line ready "$label UDP ${port} listening"
  else
    line error "$label UDP ${port} not listening"
  fi
}

check_ssh_listener() {
  local admin_cidr="${VPN_ADMIN_WG_SERVER_ADDRESS:-}"
  local admin_ip="${admin_cidr%%/*}"
  if [ -n "$admin_ip" ] && ss -lntp 2>/dev/null | awk '{print $4}' | grep -Fq "${admin_ip}:22"; then
    line ready "SSH listening on admin WireGuard IP ${admin_ip}:22"
  elif [ -n "${DEBUG_ROOT_PASSWORD:-}" ] && ss -lntp 2>/dev/null | awk '{print $4}' | grep -Eq '(^|:|])22$|:22$'; then
    line warn "debug root password set; SSH is listening for break-glass access"
  else
    line error "SSH is not listening on the admin WireGuard IP"
  fi
}

echo "== infrazero vpn status =="
date -Is
echo
echo "-- bootstrap --"
cat /etc/infrazero/bootstrap-status.json 2>/dev/null || true
echo
echo "-- checks --"
check_service wg-quick@wg0 "product WireGuard"
check_service wg-quick@wg-admin "admin WireGuard"
check_wg_iface wg0 "product WireGuard"
check_wg_iface wg-admin "admin WireGuard"
check_udp_listener "${WG_LISTEN_PORT:-51820}" "product WireGuard"
check_udp_listener "${VPN_ADMIN_WG_LISTEN_PORT:-51821}" "admin WireGuard"
check_ssh_listener
if [ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo 0)" = "1" ]; then
  line ready "IPv4 forwarding enabled"
else
  line error "IPv4 forwarding disabled"
fi
if iptables -t nat -S POSTROUTING 2>/dev/null | grep -q MASQUERADE; then
  line ready "NAT masquerade rule present"
else
  line error "NAT masquerade rule missing"
fi
echo
echo "-- wireguard --"
for iface in wg0 wg-admin; do
  echo "[$iface]"
  wg show "$iface" 2>/dev/null || true
  echo
done
echo
echo "-- listeners --"
ss -lntup 2>/dev/null | grep -E '(:22|:51820|:51821)' || true
echo
echo "-- firewall nat --"
iptables -t nat -S 2>/dev/null | grep -E 'POSTROUTING|MASQUERADE' || true
echo
echo "-- services --"
systemctl --no-pager --full status wg-quick@wg0 2>/dev/null || true
systemctl --no-pager --full status wg-quick@wg-admin 2>/dev/null || true
EOF
chmod +x /usr/local/bin/infrazero-vpn-status

beacon_status "complete" "WireGuard VPN egress is configured" 100
trap - ERR
infrazero_log "WireGuard VPN egress is configured"
