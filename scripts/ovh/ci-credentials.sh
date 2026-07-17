#!/usr/bin/env bash
# OVHcloud-only VPN credential/default mapping.
set -euo pipefail
set +x

if [ "${1:-}" = "--list-secret-names" ]; then
  printf '%s\n' \
    ovh_application_key \
    ovh_application_secret \
    ovh_consumer_key \
    ovh_cloud_project_id \
    openstack_user_name \
    openstack_password \
    openstack_tenant_id \
    openstack_auth_url \
    ovh_endpoint \
    ovh_ext_net_name
  exit 0
fi

repo_root="${INFRAZERO_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
python "${repo_root}/scripts/common/export-provider-secrets.py" \
  --required ovh_application_key \
  --required ovh_application_secret \
  --required ovh_consumer_key \
  --required ovh_cloud_project_id \
  --required openstack_user_name \
  --required openstack_password \
  --map OVH_APPLICATION_KEY=ovh_application_key \
  --map OVH_APPLICATION_SECRET=ovh_application_secret \
  --map OVH_CONSUMER_KEY=ovh_consumer_key \
  --map OVH_CLOUD_PROJECT_ID=ovh_cloud_project_id \
  --map OPENSTACK_USER_NAME=openstack_user_name \
  --map OPENSTACK_PASSWORD=openstack_password \
  --map OS_USERNAME=openstack_user_name \
  --map OS_PASSWORD=openstack_password \
  --map OS_PROJECT_ID=ovh_cloud_project_id \
  --map OS_TENANT_ID=openstack_tenant_id,ovh_cloud_project_id \
  --map TF_VAR_ovh_application_key=ovh_application_key \
  --map TF_VAR_ovh_application_secret=ovh_application_secret \
  --map TF_VAR_ovh_consumer_key=ovh_consumer_key \
  --map TF_VAR_ovh_cloud_project_id=ovh_cloud_project_id \
  --map TF_VAR_openstack_user_name=openstack_user_name \
  --map TF_VAR_openstack_password=openstack_password

secret_value() {
  SECRET_NAME="$1" python - <<'PY'
import json, os
data = json.loads(os.environ.get("SECRETS_JSON", "{}"))
name = os.environ["SECRET_NAME"].lower()
for key, value in data.items():
    if str(key).lower() == name and value:
        print(value, end="")
        break
PY
}

region_lower="$(printf '%s' "${VPN_CLOUD_REGION:-}" | tr '[:upper:]' '[:lower:]')"
s3_region="$(printf '%s' "${S3_REGION:-${VPN_CLOUD_REGION:-}}" | tr '[:upper:]' '[:lower:]' | sed 's/-[0-9]*$//')"
auth_url="$(secret_value openstack_auth_url)"
endpoint="$(secret_value ovh_endpoint)"
ext_net="$(secret_value ovh_ext_net_name)"

if [ -z "$auth_url" ]; then
  if [[ "$region_lower" == us-* ]]; then
    auth_url="https://auth.cloud.ovh.us/v3"
  else
    auth_url="https://auth.cloud.ovh.net/v3"
  fi
fi
if [ -z "$endpoint" ]; then
  if [[ "$region_lower" == us-* ]]; then endpoint="ovh-us"; else endpoint="ovh-eu"; fi
fi
ext_net="${ext_net:-Ext-Net}"
{
  echo "OPENSTACK_AUTH_URL=${auth_url}"
  echo "OVH_ENDPOINT=${endpoint}"
  echo "OVH_EXT_NET_NAME=${ext_net}"
  echo "TF_VAR_openstack_auth_url=${auth_url}"
  echo "TF_VAR_ovh_endpoint=${endpoint}"
  echo "TF_VAR_ovh_ext_net_name=${ext_net}"
  echo "OS_AUTH_URL=${auth_url}"
  echo "OS_REGION_NAME=${VPN_CLOUD_REGION:-}"
  echo "OS_INTERFACE=public"
  echo "OS_IDENTITY_API_VERSION=3"
  echo "OS_USER_DOMAIN_NAME=Default"
  echo "OS_PROJECT_DOMAIN_NAME=Default"
  echo "TF_VAR_private_cidr=${VPN_PRIVATE_CIDR:-10.80.0.0/24}"
  echo "TF_VAR_server_image_regex=${OVH_SERVER_IMAGE_REGEX:-^Ubuntu 24\\.04}"
  echo "PROVIDER_S3_REGION=${s3_region}"
} >> "${GITHUB_ENV:?GITHUB_ENV is required}"
