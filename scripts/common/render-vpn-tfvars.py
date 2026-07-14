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


def parse_json_env(name: str, default):
    raw = os.getenv(name, "").strip()
    if not raw:
        return default
    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        print(f"{name} is invalid JSON: {exc}", file=sys.stderr)
        raise SystemExit(1)


def b64_json(value) -> str:
    import base64

    payload = json.dumps(value, separators=(",", ":"))
    return base64.b64encode(payload.encode("utf-8")).decode("ascii")


def normalize_admin_ssh_keys() -> dict[str, list[str]]:
    raw = parse_json_env("OPS_SSH_KEYS_JSON", {})
    if not raw:
        return {}
    if not isinstance(raw, dict):
        print("OPS_SSH_KEYS_JSON must be a JSON object: username -> ssh public keys", file=sys.stderr)
        raise SystemExit(1)

    normalized: dict[str, list[str]] = {}
    for username, keys in raw.items():
        user = str(username or "").strip()
        if not user:
            continue
        if isinstance(keys, str):
            keys = [keys]
        if not isinstance(keys, list):
            continue
        clean_keys = [str(key).strip() for key in keys if str(key or "").strip()]
        if clean_keys:
            normalized[user] = clean_keys
    if not normalized:
        print("OPS_SSH_KEYS_JSON must include at least one admin SSH key", file=sys.stderr)
        raise SystemExit(1)
    return normalized


def main() -> int:
    parser = argparse.ArgumentParser(description="Render VPN OpenTofu tfvars from GitHub Actions secrets.")
    parser.add_argument("--bootstrap-manifest", required=True)
    parser.add_argument("--bootstrap-secrets-manifest", required=True)
    parser.add_argument("--output", default="tofu/hetzner/tofu.tfvars.json")
    args = parser.parse_args()

    bootstrap_artifacts = json.loads(Path(args.bootstrap_manifest).read_text(encoding="utf-8-sig"))
    bootstrap_secrets = json.loads(Path(args.bootstrap_secrets_manifest).read_text(encoding="utf-8-sig"))

    listen_port = int(require_env("WG_LISTEN_PORT"))
    admin_listen_port = int(optional_env("VPN_ADMIN_WG_LISTEN_PORT", "51821"))
    project = require_env("VPN_PROJECT_SLUG")
    environment = optional_env("VPN_ENVIRONMENT", "prod")
    cloud_provider = optional_env("VPN_CLOUD_PROVIDER", "hetzner")
    admin_ssh_keys = normalize_admin_ssh_keys()
    tfvars = {
        "project": project,
        "environment": environment,
        "name_prefix": f"{project}-{environment}",
        "location": require_env("VPN_CLOUD_REGION"),
        "egress_server_type": require_env("VPN_EGRESS_SERVER_TYPE"),
        "wg_listen_port": listen_port,
        "wg_server_address": require_env("WG_SERVER_ADDRESS"),
        "wg_server_public_key": require_env("WG_SERVER_PUBLIC_KEY"),
        "admin_wg_listen_port": admin_listen_port,
        "admin_wg_server_address": optional_env("VPN_ADMIN_WG_SERVER_ADDRESS", "10.81.0.1/24"),
        "vpn_endpoint_mode": optional_env("VPN_ENDPOINT_MODE", "mvp_ip"),
        "vpn_domain": optional_env("VPN_DOMAIN"),
        "vpn_routing_mode": optional_env("VPN_ROUTING_MODE", "full"),
        "vpn_split_allowed_ips": optional_env("VPN_SPLIT_ALLOWED_IPS"),
        "vpn_client_dns": optional_env("VPN_CLIENT_DNS", "1.1.1.1, 8.8.8.8"),
        "bootstrap_artifacts": bootstrap_artifacts,
        "bootstrap_secrets": bootstrap_secrets,
        "admin_users_json_b64": b64_json(admin_ssh_keys),
        "debug_root_password": optional_env("DEBUG_ROOT_PASSWORD"),
    }

    if cloud_provider == "hetzner":
        tfvars.update({
            "hcloud_token": require_env("HCLOUD_TOKEN"),
            "server_image": "ubuntu-22.04",
        })
    elif cloud_provider == "ovhcloud":
        tfvars.update({
            "private_cidr": optional_env("VPN_PRIVATE_CIDR", "10.80.0.0/24"),
            "server_image_regex": optional_env("OVH_SERVER_IMAGE_REGEX", "^Ubuntu 24\\.04"),
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
