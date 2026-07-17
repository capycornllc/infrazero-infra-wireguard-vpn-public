import argparse
import os
import re
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description="Render OpenTofu S3 backend config for VPN infra.")
    parser.add_argument(
        "--output",
        default=str(Path(os.getenv("TOFU_DIR", "tofu")) / "backend.hcl"),
    )
    args = parser.parse_args()

    bucket = os.getenv("INFRA_STATE_BUCKET", "").strip()
    endpoint = os.getenv("S3_ENDPOINT", "").strip()
    region = (
        os.getenv("S3_REGION", "")
        or os.getenv("AWS_REGION", "")
        or os.getenv("AWS_DEFAULT_REGION", "")
        or os.getenv("VPN_CLOUD_REGION", "")
        or "us-east-1"
    ).strip().lower()
    region = re.sub(r"-\d+$", "", region)
    project = os.getenv("VPN_PROJECT_SLUG", "").strip()
    environment = os.getenv("VPN_ENVIRONMENT", "").strip() or "prod"

    if not bucket:
        print("INFRA_STATE_BUCKET is required", file=sys.stderr)
        return 1
    if not endpoint:
        print("S3_ENDPOINT is required", file=sys.stderr)
        return 1
    if not project:
        print("VPN_PROJECT_SLUG is required", file=sys.stderr)
        return 1

    backend_hcl = "\n".join([
        f'bucket = "{bucket}"',
        f'key = "{project}/{environment}/vpn/terraform.tfstate"',
        f'region = "{region}"',
        f'endpoint = "{endpoint}"',
        "skip_credentials_validation = true",
        "skip_metadata_api_check = true",
        "skip_requesting_account_id = true",
        "skip_region_validation = true",
        "use_path_style = true",
    ])

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(backend_hcl + "\n", encoding="utf-8")
    print(f"Rendered {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
