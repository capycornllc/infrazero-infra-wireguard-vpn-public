import argparse
import socket
import sys
import time


def resolve_ipv4(hostname: str) -> set[str]:
    try:
        infos = socket.getaddrinfo(hostname, None, socket.AF_INET, socket.SOCK_STREAM)
    except socket.gaierror:
        return set()
    return {item[4][0] for item in infos if item and item[4]}


def main() -> int:
    parser = argparse.ArgumentParser(description="Wait until a hostname resolves to the expected IPv4 address.")
    parser.add_argument("--hostname", required=True)
    parser.add_argument("--ip", required=True)
    parser.add_argument("--timeout", type=int, default=60)
    parser.add_argument("--interval", type=int, default=10)
    args = parser.parse_args()

    hostname = args.hostname.strip().strip(".")
    expected_ip = args.ip.strip()
    deadline = time.monotonic() + max(args.timeout, 1)
    attempt = 0

    while True:
        attempt += 1
        resolved = resolve_ipv4(hostname)
        if expected_ip in resolved:
            print(f"DNS validation OK: {hostname} -> {expected_ip}")
            return 0

        if time.monotonic() >= deadline:
            got = ", ".join(sorted(resolved)) if resolved else "<no A record>"
            print(f"DNS validation failed: {hostname} expected {expected_ip}, got {got}", file=sys.stderr)
            return 1

        got = ", ".join(sorted(resolved)) if resolved else "<no A record yet>"
        print(f"Waiting for DNS propagation ({attempt}): {hostname} expected {expected_ip}, got {got}")
        time.sleep(max(args.interval, 1))


if __name__ == "__main__":
    raise SystemExit(main())
