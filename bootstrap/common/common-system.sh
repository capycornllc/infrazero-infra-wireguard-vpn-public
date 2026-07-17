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
infrazero_install_error_trap

beacon_status "starting" "VPN server bootstrap starting" 0
beacon_status "creating_admins" "Creating platform admin users" 10
infrazero_setup_admin_users "vpn-common"

beacon_status "installing_base_packages" "Installing base packages" 20
infrazero_install_base_packages "vpn-common" curl ca-certificates zstd jq python3 sudo openssh-server auditd unattended-upgrades ufw

beacon_status "hardening_ssh" "Applying SSH hardening" 35
infrazero_harden_ssh "vpn-common"

beacon_status "system_baseline" "Applying system baseline" 45
infrazero_apply_system_baseline

beacon_status "base_security" "Enabling audit and security updates" 48
infrazero_configure_base_system

beacon_status "common_complete" "Common VPN bootstrap complete" 50
trap - ERR
