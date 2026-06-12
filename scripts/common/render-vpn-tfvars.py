import argparse
import json
import os
import sys
from pathlib import Path


def require_env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        print(f"{name} is required", file=sys.stderr)
        raise SystemExit(1)
    return value


def optional_env(name: str, default: str = "") -> str:
    return os.getenv(name, "").strip() or default


def main() -> int:
    parser = argparse.ArgumentParser(description="Render VPN OpenTofu tfvars from GitHub Actions secrets.")
    parser.add_argument("--bootstrap-manifest", required=True)
    parser.add_argument("--bootstrap-secrets-manifest", required=True)
    parser.add_argument("--output", default="tofu/hetzner/tofu.tfvars.json")
    args = parser.parse_args()

    bootstrap_artifacts = json.loads(Path(args.bootstrap_manifest).read_text(encoding="utf-8-sig"))
    bootstrap_secrets = json.loads(Path(args.bootstrap_secrets_manifest).read_text(encoding="utf-8-sig"))

    listen_port = int(require_env("WG_LISTEN_PORT"))
    project = require_env("VPN_PROJECT_SLUG")
    environment = optional_env("VPN_ENVIRONMENT", "prod")
    cloud_provider = optional_env("VPN_CLOUD_PROVIDER", "hetzner")
    tfvars = {
        "project": project,
        "environment": environment,
        "name_prefix": f"{project}-{environment}",
        "location": require_env("VPN_CLOUD_REGION"),
        "egress_server_type": require_env("VPN_EGRESS_SERVER_TYPE"),
        "wg_listen_port": listen_port,
        "wg_server_address": require_env("WG_SERVER_ADDRESS"),
        "wg_server_public_key": require_env("WG_SERVER_PUBLIC_KEY"),
        "vpn_endpoint_mode": optional_env("VPN_ENDPOINT_MODE", "mvp_ip"),
        "vpn_domain": optional_env("VPN_DOMAIN"),
        "vpn_routing_mode": optional_env("VPN_ROUTING_MODE", "full"),
        "vpn_split_allowed_ips": optional_env("VPN_SPLIT_ALLOWED_IPS"),
        "vpn_client_dns": optional_env("VPN_CLIENT_DNS", "1.1.1.1, 8.8.8.8"),
        "bootstrap_artifacts": bootstrap_artifacts,
        "bootstrap_secrets": bootstrap_secrets,
    }

    if cloud_provider == "hetzner":
        tfvars.update({
            "hcloud_token": require_env("HCLOUD_TOKEN"),
            "server_image": "ubuntu-22.04",
        })
    elif cloud_provider == "ovhcloud":
        tfvars.update({
            "private_cidr": optional_env("VPN_PRIVATE_CIDR", "10.80.0.0/24"),
            "server_image_regex": optional_env("OVH_SERVER_IMAGE_REGEX", "^Ubuntu 22\\.04"),
            "ovh_application_key": require_env("OVH_APPLICATION_KEY"),
            "ovh_application_secret": require_env("OVH_APPLICATION_SECRET"),
            "ovh_consumer_key": require_env("OVH_CONSUMER_KEY"),
            "ovh_cloud_project_id": require_env("OVH_CLOUD_PROJECT_ID"),
            "openstack_auth_url": optional_env("OPENSTACK_AUTH_URL", "https://auth.cloud.ovh.net/v3"),
            "ovh_endpoint": optional_env("OVH_ENDPOINT", "ovh-eu"),
            "openstack_user_name": require_env("OPENSTACK_USER_NAME"),
            "openstack_password": require_env("OPENSTACK_PASSWORD"),
            "ovh_ext_net_name": optional_env("OVH_EXT_NET_NAME", "Ext-Net"),
        })
    else:
        print(f"Unsupported VPN_CLOUD_PROVIDER: {cloud_provider}", file=sys.stderr)
        return 1

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(tfvars, indent=2) + "\n", encoding="utf-8")
    print(f"Rendered {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
