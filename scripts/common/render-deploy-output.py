import argparse
import json
import os
from datetime import datetime, timezone
from pathlib import Path


def clean(value: str | None) -> str:
    return str(value or "").strip()


def main() -> int:
    parser = argparse.ArgumentParser(description="Render public VPN deploy outputs.")
    parser.add_argument("--egress-public-ip", required=True)
    parser.add_argument("--public-ip-endpoint", required=True)
    parser.add_argument("--wireguard-endpoint", required=True)
    parser.add_argument("--domain-endpoint", default="")
    parser.add_argument("--output", default="build/deploy/vpn-deploy-output.json")
    args = parser.parse_args()

    endpoint_mode = clean(os.getenv("VPN_ENDPOINT_MODE")) or "mvp_ip"
    output = {
        "schemaVersion": 1,
        "deploymentKind": "vpn",
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "projectSlug": clean(os.getenv("VPN_PROJECT_SLUG")),
        "environment": clean(os.getenv("VPN_ENVIRONMENT")) or "prod",
        "endpointMode": endpoint_mode,
        "egressPublicIpv4": clean(args.egress_public_ip),
        "wireguardEndpoint": clean(args.wireguard_endpoint),
        "publicIpEndpoint": clean(args.public_ip_endpoint),
        "domainEndpoint": clean(args.domain_endpoint),
        "listenPort": clean(os.getenv("WG_LISTEN_PORT")) or "51820",
        "clientConfigPatch": {
            "placeholder": "REPLACE_WITH_EGRESS_PUBLIC_IP",
            "replacement": clean(args.egress_public_ip),
            "appliesWhen": "endpointMode=mvp_ip",
        },
        "notes": [
            "This file contains public deploy outputs only.",
            "Client private keys are not stored in GitHub, Infrazero, or this artifact.",
        ],
    }

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(output, indent=2) + "\n", encoding="utf-8")
    print(f"Rendered {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
