#!/usr/bin/env bash
set -euo pipefail

infrazero_log() {
  local prefix="${INFRAZERO_LOG_PREFIX:-infrazero-vpn}"
  printf '[%s] %s\n' "$prefix" "$*"
}

infrazero_require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "This script must run as root" >&2
    exit 1
  fi
}

infrazero_require_env() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "$name is required" >&2
    exit 1
  fi
}

infrazero_retry() {
  local attempts="$1"
  shift
  local delay="${INFRAZERO_RETRY_DELAY_SECONDS:-3}"
  local n=1
  until "$@"; do
    if [ "$n" -ge "$attempts" ]; then
      return 1
    fi
    infrazero_log "Retry $n/$attempts failed: $*"
    n=$((n + 1))
    sleep "$delay"
  done
}

infrazero_apt_get() {
  local log_prefix="${1:-common}"
  shift || true
  local attempts="${INFRAZERO_APT_ATTEMPTS:-5}"
  local retry_delay="${INFRAZERO_APT_RETRY_DELAY:-10}"
  local command_timeout="${INFRAZERO_APT_TIMEOUT:-1200}"
  local lock_timeout="${INFRAZERO_APT_LOCK_TIMEOUT:-600}"
  local attempt

  for attempt in $(seq 1 "$attempts"); do
    if timeout "$command_timeout" apt-get -o DPkg::Lock::Timeout="$lock_timeout" "$@"; then
      return 0
    fi
    echo "[${log_prefix}] apt-get $* failed (${attempt}/${attempts}); retrying in ${retry_delay}s" >&2
    if declare -F beacon_retrying >/dev/null 2>&1; then
      beacon_retrying "installing_base_packages" "apt-get failed or timed out; retrying" 20 "external" "APT_RETRY" "$attempt" "$attempts"
    fi
    apt-get clean 2>/dev/null || true
    rm -rf /var/lib/apt/lists/* 2>/dev/null || true
    sleep "$retry_delay"
  done
  return 1
}

provider_route_mode() {
  echo "none"
}

provider_outbound_defaults() {
  return 0
}

provider_detect_public_iface() {
  ip route show default 2>/dev/null | awk '{print $5; exit}'
}

infrazero_load_provider_adapter() {
  local script_dir="${1:-$(pwd)}"
  local provider="${INFRAZERO_PROVIDER:-}"
  local candidate=""

  if [ -f "${script_dir}/adapter.sh" ]; then
    candidate="${script_dir}/adapter.sh"
  elif [ -n "$provider" ] && [ -f "${script_dir}/../providers/${provider}/adapter.sh" ]; then
    candidate="${script_dir}/../providers/${provider}/adapter.sh"
  elif [ -n "$provider" ] && [ -f "${script_dir}/../../bootstrap/providers/${provider}/adapter.sh" ]; then
    candidate="${script_dir}/../../bootstrap/providers/${provider}/adapter.sh"
  fi

  if [ -z "$candidate" ]; then
    echo "[common] provider adapter not found for INFRAZERO_PROVIDER=${provider:-unknown}" >&2
    exit 1
  fi

  # shellcheck disable=SC1090
  source "$candidate"
}

infrazero_install_base_packages() {
  local log_prefix="${1:-common}"
  shift || true
  local packages=("$@")
  export DEBIAN_FRONTEND=noninteractive

  if [ "${#packages[@]}" -eq 0 ]; then
    return 0
  fi

  infrazero_apt_get "$log_prefix" update -y
  infrazero_apt_get "$log_prefix" install -y "${packages[@]}"
}

infrazero_setup_admin_users() {
  local log_prefix="${1:-common}"
  local admins_b64="${ADMIN_USERS_JSON_B64:-}"
  local admins_file="/etc/infrazero/admins.json"
  local tmp_keys="/tmp/infrazero-admin-keys"

  if ! getent group infrazero-admins >/dev/null 2>&1; then
    groupadd infrazero-admins
  fi
  echo "%infrazero-admins ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-infrazero-admins
  chmod 440 /etc/sudoers.d/90-infrazero-admins

  if [ -z "$admins_b64" ]; then
    echo "[${log_prefix}] ADMIN_USERS_JSON_B64 is empty; no platform admin users configured"
    return 0
  fi

  mkdir -p /etc/infrazero
  echo "$admins_b64" | base64 -d > "$admins_file"
  chmod 600 "$admins_file"

  : > "$tmp_keys"
  if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY_USERS' > "$tmp_keys" || true
import json
from pathlib import Path

data = json.loads(Path("/etc/infrazero/admins.json").read_text())

def emit(user, key):
    user = str(user or "").strip()
    key = str(key or "").strip()
    if user and key:
        print(f"{user}|{key}")

if isinstance(data, dict):
    for user, keys in data.items():
        if isinstance(keys, str):
            keys = [keys]
        if isinstance(keys, list):
            for key in keys:
                emit(user, key)
elif isinstance(data, list):
    for item in data:
        if not isinstance(item, dict):
            continue
        user = item.get("username") or item.get("user") or item.get("name")
        keys = item.get("sshPublicKeys") or item.get("publicKeys") or item.get("keys") or item.get("sshKeys")
        if isinstance(keys, str):
            keys = [keys]
        if isinstance(keys, list):
            for key in keys:
                emit(user, key)
PY_USERS
  else
    echo "[${log_prefix}] python3 not available; skipping admin user creation" >&2
  fi

  if [ -s "$tmp_keys" ]; then
    declare -A seen_users
    while IFS='|' read -r username key; do
      [ -n "$username" ] && [ -n "$key" ] || continue
      if ! [[ "$username" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        echo "[${log_prefix}] skipping invalid Linux username: $username"
        continue
      fi

      if ! id -u "$username" >/dev/null 2>&1; then
        local useradd_extra_raw=""
        local -a useradd_extra_args=()
        if declare -F provider_admin_useradd_options >/dev/null 2>&1; then
          useradd_extra_raw="$(provider_admin_useradd_options "$username" 2>/dev/null || true)"
          if [ -n "$useradd_extra_raw" ]; then
            # shellcheck disable=SC2206
            useradd_extra_args=($useradd_extra_raw)
          fi
        fi
        useradd -m -s /bin/bash "${useradd_extra_args[@]}" -G infrazero-admins "$username"
      else
        usermod -aG infrazero-admins "$username" || true
      fi

      local primary_group
      primary_group="$(id -gn "$username" 2>/dev/null || echo "$username")"
      install -d -m 0700 "/home/$username/.ssh"
      if [ -z "${seen_users[$username]+x}" ]; then
        : > "/home/$username/.ssh/authorized_keys"
        seen_users["$username"]=1
      fi
      echo "$key" >> "/home/$username/.ssh/authorized_keys"
      chmod 0600 "/home/$username/.ssh/authorized_keys"
      chown -R "$username:$primary_group" "/home/$username/.ssh"
    done < "$tmp_keys"
  fi

  rm -f "$tmp_keys"
}

infrazero_set_sshd_config() {
  local sshd_config="${1:-/etc/ssh/sshd_config}"
  local key="$2"
  local value="$3"

  if grep -q "^${key} " "$sshd_config"; then
    sed -i "s/^${key}.*/${key} ${value}/" "$sshd_config"
  else
    echo "${key} ${value}" >> "$sshd_config"
  fi
}

infrazero_ensure_sshd_include() {
  local sshd_config="${1:-/etc/ssh/sshd_config}"
  if ! grep -Eq '^[#[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config.d/\*.conf' "$sshd_config"; then
    echo "Include /etc/ssh/sshd_config.d/*.conf" >> "$sshd_config"
  fi
}

infrazero_strip_sshd_debug_block() {
  local sshd_config="${1:-/etc/ssh/sshd_config}"
  local begin="# BEGIN INFRAZERO DEBUG SSH"
  local end="# END INFRAZERO DEBUG SSH"

  if [ -f "$sshd_config" ]; then
    awk -v begin="$begin" -v end="$end" '
      $0==begin {skip=1; next}
      $0==end {skip=0; next}
      skip==1 {next}
      {print}
    ' "$sshd_config" > "${sshd_config}.tmp" && mv "${sshd_config}.tmp" "$sshd_config"
  fi
}

infrazero_harden_ssh() {
  local log_prefix="${1:-common}"
  local sshd_config="${SSHD_CONFIG:-/etc/ssh/sshd_config}"
  local debug_root_password="${DEBUG_ROOT_PASSWORD:-}"
  local listen_address="${SSH_LISTEN_ADDRESS:-}"
  local ssh_password_auth="no"
  local ssh_kbd_interactive="no"
  local ssh_challenge="no"
  local ssh_permit_root="no"
  local ssh_allow_groups="infrazero-admins"

  if [ -n "$debug_root_password" ]; then
    echo "[${log_prefix}] DEBUG_ROOT_PASSWORD set; enabling root password auth"
    echo "root:${debug_root_password}" | chpasswd || echo "[${log_prefix}] unable to set root password" >&2
    passwd -u root >/dev/null 2>&1 || usermod -U root >/dev/null 2>&1 || true
    ssh_password_auth="yes"
    ssh_kbd_interactive="yes"
    ssh_challenge="yes"
    ssh_permit_root="yes"
    ssh_allow_groups="infrazero-admins root"
    listen_address=""
  fi

  infrazero_ensure_sshd_include "$sshd_config"
  infrazero_set_sshd_config "$sshd_config" "PasswordAuthentication" "$ssh_password_auth"
  infrazero_set_sshd_config "$sshd_config" "KbdInteractiveAuthentication" "$ssh_kbd_interactive"
  infrazero_set_sshd_config "$sshd_config" "ChallengeResponseAuthentication" "$ssh_challenge"
  infrazero_set_sshd_config "$sshd_config" "PermitRootLogin" "$ssh_permit_root"
  infrazero_strip_sshd_debug_block "$sshd_config"

  mkdir -p /etc/ssh/sshd_config.d
  rm -f /etc/ssh/sshd_config.d/infrazero.conf
  cat > /etc/ssh/sshd_config.d/90-infrazero.conf <<EOF
PasswordAuthentication ${ssh_password_auth}
KbdInteractiveAuthentication ${ssh_kbd_interactive}
ChallengeResponseAuthentication ${ssh_challenge}
PermitRootLogin ${ssh_permit_root}
AllowGroups ${ssh_allow_groups}
EOF

  if [ -n "$listen_address" ]; then
    cat >> /etc/ssh/sshd_config.d/90-infrazero.conf <<EOF
ListenAddress ${listen_address}
EOF
  fi

  if [ -n "$debug_root_password" ]; then
    cat > /etc/ssh/sshd_config.d/99-infrazero-debug.conf <<'EOF'
Match all
  PermitRootLogin yes
  PasswordAuthentication yes
  KbdInteractiveAuthentication yes
  ChallengeResponseAuthentication yes
  AllowGroups infrazero-admins root
EOF
  else
    rm -f /etc/ssh/sshd_config.d/99-infrazero-debug.conf
  fi

  systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
}

infrazero_apply_system_baseline() {
  cat > /etc/sysctl.d/99-infrazero-vpn.conf <<'EOF'
net.ipv4.ip_forward=1
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
EOF
  sysctl --system || true
}

infrazero_ipv4_from_cidr() {
  local cidr="$1"
  printf '%s' "${cidr%%/*}"
}

infrazero_configure_base_system() {
  if command -v unattended-upgrades >/dev/null 2>&1; then
    cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'EOF'
Unattended-Upgrade::Allowed-Origins {
        "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::Package-Blacklist {
        "linux-*";
        "libc6";
        "openssl";
        "wireguard*";
};
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
EOF
    systemctl enable unattended-upgrades >/dev/null 2>&1 || true
  fi

  systemctl enable --now auditd >/dev/null 2>&1 || true
  mkdir -p /var/log/journal
  sed -i 's/^#\?Storage=.*/Storage=persistent/' /etc/systemd/journald.conf
  systemctl restart systemd-journald >/dev/null 2>&1 || true
}
