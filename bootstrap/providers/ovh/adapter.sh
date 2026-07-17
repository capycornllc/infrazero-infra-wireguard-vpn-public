#!/usr/bin/env bash

export INFRAZERO_PROVIDER="ovh"

provider_route_mode() {
  echo "ovh-public"
}

provider_outbound_defaults() {
  return 0
}

provider_detect_public_iface() {
  ip route show default 2>/dev/null | awk '{print $5; exit}'
}

# OVH Ubuntu images can already contain an "admin" group. Use -N for platform
# admin users so `useradd admin` does not fail when that group already exists.
provider_admin_useradd_options() {
  echo "-N"
}
