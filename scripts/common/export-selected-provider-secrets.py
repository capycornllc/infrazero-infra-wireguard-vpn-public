#!/usr/bin/env python3
"""Pass only the selected cloud's GitHub secrets to its credential exporter."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--github-env", required=True, type=Path)
    parser.add_argument("--provider-credential-script", required=True, type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        payload: Any = json.load(sys.stdin)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Invalid secrets JSON: {exc}") from exc
    if not isinstance(payload, dict):
        raise SystemExit("Secrets JSON must be an object")
    if not args.provider_credential_script.is_file():
        raise SystemExit(
            f"Provider credential script not found: {args.provider_credential_script}"
        )

    bash = shutil.which("bash") or "bash"
    script = args.provider_credential_script.as_posix()
    names_result = subprocess.run(
        [bash, script, "--list-secret-names"], capture_output=True, text=True, check=False
    )
    if names_result.returncode != 0:
        raise SystemExit("Provider credential name contract failed")
    names = [line.strip() for line in names_result.stdout.splitlines() if line.strip()]
    normalized = {str(key).lower(): value for key, value in payload.items()}
    selected = {name: normalized[name.lower()] for name in names if name.lower() in normalized}

    child_env = os.environ.copy()
    child_env["SECRETS_JSON"] = json.dumps(selected)
    child_env["GITHUB_ENV"] = args.github_env.as_posix()
    result = subprocess.run([bash, script], env=child_env, check=False)
    if result.returncode != 0:
        raise SystemExit("Provider credential export failed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
