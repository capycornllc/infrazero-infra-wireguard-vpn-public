import ipaddress
import json
import os
import re
import sys


def env(name: str) -> str:
    return os.getenv(name, "").strip()


def require(name: str, errors: list[str]) -> str:
    value = env(name)
    if not value:
        errors.append(f"{name} is required")
    return value


def validate_port(name: str, errors: list[str], required: bool = True) -> None:
    value = require(name, errors) if required else env(name)
    if not value:
        return
    try:
        port = int(value)
    except ValueError:
        errors.append(f"{name} must be an integer port")
        return
    if port < 1 or port > 65535:
        errors.append(f"{name} must be between 1 and 65535")


def validate_cidr(name: str, errors: list[str], required: bool = True) -> None:
    value = require(name, errors) if required else env(name)
    if not value:
        return
    try:
        ipaddress.ip_network(value, strict=False)
    except ValueError:
        errors.append(f"{name} must use CIDR notation")


def validate_json(name: str, errors: list[str], expected_type: type | tuple[type, ...] | None = None) -> None:
    value = require(name, errors)
    if not value:
        return
    try:
        parsed = json.loads(value)
    except json.JSONDecodeError as exc:
        errors.append(f"{name} is invalid JSON: {exc}")
        return
    if expected_type is not None and not isinstance(parsed, expected_type):
        type_name = getattr(expected_type, "__name__", "expected type")
        errors.append(f"{name} must be {type_name}")


def main() -> int:
    errors: list[str] = []

    provider = (env("VPN_CLOUD_PROVIDER") or "hetzner").lower()
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", provider):
        errors.append(f"VPN_CLOUD_PROVIDER has an invalid format: {provider!r}")

    endpoint_mode = env("VPN_ENDPOINT_MODE") or "mvp_ip"
    if endpoint_mode not in {"mvp_ip", "domain"}:
        errors.append("VPN_ENDPOINT_MODE must be 'mvp_ip' or 'domain'")
    if endpoint_mode == "domain":
        require("VPN_DOMAIN", errors)
        require("CLOUDFLARE_API_TOKEN", errors)

    routing_mode = env("VPN_ROUTING_MODE") or "full"
    if routing_mode not in {"full", "split"}:
        errors.append("VPN_ROUTING_MODE must be 'full' or 'split'")

    for name in [
        "VPN_PROJECT_SLUG",
        "VPN_CLOUD_REGION",
        "VPN_EGRESS_SERVER_TYPE",
        "INFRA_STATE_BUCKET",
        "S3_ENDPOINT",
        "WG_SERVER_PRIVATE_KEY",
        "WG_SERVER_PUBLIC_KEY",
        "VPN_ADMIN_WG_SERVER_PRIVATE_KEY",
    ]:
        require(name, errors)

    validate_port("WG_LISTEN_PORT", errors)
    validate_port("VPN_ADMIN_WG_LISTEN_PORT", errors, required=False)
    validate_cidr("WG_SERVER_ADDRESS", errors)
    validate_cidr("VPN_ADMIN_WG_SERVER_ADDRESS", errors, required=False)
    validate_json("OPS_SSH_KEYS_JSON", errors, dict)
    validate_json("VPN_PEERS_JSON", errors, list)
    validate_json("VPN_ADMIN_PEERS_JSON", errors, list)

    if errors:
        print("VPN config validation failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print("VPN config validation OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
