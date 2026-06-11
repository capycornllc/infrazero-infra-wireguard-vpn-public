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
    parser.add_argument("--output", default="tofu/hetzner/tofu.tfvars.json")
    args = parser.parse_args()

    bootstrap_artifacts = json.loads(Path(args.bootstrap_manifest).read_text(encoding="utf-8-sig"))
    peers_json = optional_env("VPN_PEERS_JSON", "[]")
    try:
        peers = json.loads(peers_json)
    except json.JSONDecodeError as exc:
        print(f"VPN_PEERS_JSON is invalid JSON: {exc}", file=sys.stderr)
        return 1

    listen_port = int(require_env("WG_LISTEN_PORT"))
    project = require_env("VPN_PROJECT_SLUG")
    environment = optional_env("VPN_ENVIRONMENT", "prod")
    tfvars = {
        "hcloud_token": require_env("HCLOUD_TOKEN"),
        "project": project,
        "environment": environment,
        "name_prefix": f"{project}-{environment}",
        "location": require_env("VPN_CLOUD_REGION"),
        "server_image": "ubuntu-22.04",
        "egress_server_type": require_env("VPN_EGRESS_SERVER_TYPE"),
        "wg_listen_port": listen_port,
        "wg_server_address": require_env("WG_SERVER_ADDRESS"),
        "wg_server_private_key": require_env("WG_SERVER_PRIVATE_KEY"),
        "wg_server_public_key": require_env("WG_SERVER_PUBLIC_KEY"),
        "vpn_endpoint_mode": optional_env("VPN_ENDPOINT_MODE", "mvp_ip"),
        "vpn_domain": optional_env("VPN_DOMAIN"),
        "vpn_routing_mode": optional_env("VPN_ROUTING_MODE", "full"),
        "vpn_split_allowed_ips": optional_env("VPN_SPLIT_ALLOWED_IPS"),
        "vpn_client_dns": optional_env("VPN_CLIENT_DNS", "1.1.1.1, 8.8.8.8"),
        "vpn_peers_json": json.dumps(peers, separators=(",", ":")),
        "bootstrap_artifacts": bootstrap_artifacts,
    }

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(tfvars, indent=2) + "\n", encoding="utf-8")
    print(f"Rendered {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
