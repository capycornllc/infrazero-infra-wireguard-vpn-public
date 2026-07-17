#!/usr/bin/env bash
# Provider-owned OpenTofu addresses used by rebuild workflows.

tofu_server_resource() {
  case "${1:-}" in
    egress) echo "openstack_compute_instance_v2.egress_vpn" ;;
    *) echo "[tofu-resources] unknown VPN role: ${1:-}" >&2; return 1 ;;
  esac
}

tofu_replace_extra_targets() {
  echo ""
}
