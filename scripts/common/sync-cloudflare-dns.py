import argparse
import os
import sys

import requests


API_BASE = "https://api.cloudflare.com/client/v4"


def cf_request(method: str, path: str, token: str, **kwargs):
    response = requests.request(
        method,
        f"{API_BASE}{path}",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        timeout=30,
        **kwargs,
    )
    try:
        payload = response.json()
    except ValueError:
        payload = {}
    if not response.ok or payload.get("success") is False:
        raise RuntimeError(payload.get("errors") or payload.get("message") or response.text)
    return payload


def find_zone(hostname: str, token: str):
    labels = hostname.strip(".").split(".")
    for index in range(0, len(labels) - 1):
        zone_name = ".".join(labels[index:])
        payload = cf_request("GET", f"/zones?name={zone_name}", token)
        result = payload.get("result") or []
        if result:
            return result[0]
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description="Create or update a Cloudflare A record for the VPN endpoint.")
    parser.add_argument("--hostname", required=True)
    parser.add_argument("--ip", required=True)
    args = parser.parse_args()

    token = os.getenv("CLOUDFLARE_API_TOKEN", "").strip()
    if not token:
        print("CLOUDFLARE_API_TOKEN is required in domain endpoint mode", file=sys.stderr)
        return 1

    hostname = args.hostname.strip().strip(".")
    ip = args.ip.strip()
    zone = find_zone(hostname, token)
    if not zone:
        print(f"No Cloudflare zone found for {hostname}", file=sys.stderr)
        return 1

    zone_id = zone["id"]
    records_payload = cf_request(
        "GET",
        f"/zones/{zone_id}/dns_records?type=A&name={hostname}",
        token,
    )
    records = records_payload.get("result") or []
    body = {
        "type": "A",
        "name": hostname,
        "content": ip,
        "ttl": 60,
        "proxied": False,
        "comment": "Managed by Infrazero WireGuard VPN deploy",
    }

    if records:
        record_id = records[0]["id"]
        cf_request("PUT", f"/zones/{zone_id}/dns_records/{record_id}", token, json=body)
        print(f"Updated {hostname} -> {ip}")
    else:
        cf_request("POST", f"/zones/{zone_id}/dns_records", token, json=body)
        print(f"Created {hostname} -> {ip}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
