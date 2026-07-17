#!/usr/bin/env python3
"""Export a selected provider's secrets into GITHUB_ENV without logging them."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import uuid
from pathlib import Path
from typing import Iterable, Sequence


ENV_NAME_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--required", action="append", default=[], metavar="SECRET")
    parser.add_argument("--map", action="append", default=[], metavar="ENV=SECRET[,FALLBACK]")
    parser.add_argument(
        "--optional-map", action="append", default=[], metavar="ENV=SECRET[,FALLBACK]"
    )
    return parser.parse_args(argv)


def load_secrets() -> dict[str, str]:
    raw = os.environ.get("SECRETS_JSON", "")
    if not raw.strip():
        raise ValueError("SECRETS_JSON is required")
    value = json.loads(raw)
    if not isinstance(value, dict):
        raise ValueError("SECRETS_JSON must contain a JSON object")
    return {str(key).lower(): str(item or "") for key, item in value.items()}


def parse_mapping(raw: str) -> tuple[str, list[str]]:
    env_name, separator, source_list = raw.partition("=")
    if not separator or not ENV_NAME_RE.fullmatch(env_name):
        raise ValueError(f"invalid mapping '{raw}'; expected ENV=SECRET[,FALLBACK]")
    sources = [item.strip().lower() for item in source_list.split(",") if item.strip()]
    if not sources:
        raise ValueError(f"mapping '{raw}' has no secret source")
    return env_name, sources


def first_value(secrets: dict[str, str], sources: Iterable[str]) -> str:
    for source in sources:
        value = secrets.get(source.lower(), "")
        if value:
            return value
    return ""


def append_github_env(path: Path, name: str, value: str) -> None:
    delimiter = f"INFRAZERO_{uuid.uuid4().hex}"
    with path.open("a", encoding="utf-8", newline="\n") as handle:
        handle.write(f"{name}<<{delimiter}\n{value}\n{delimiter}\n")


def main(argv: Sequence[str]) -> int:
    args = parse_args(argv)
    github_env = os.environ.get("GITHUB_ENV", "").strip()
    if not github_env:
        print("GITHUB_ENV is required", file=sys.stderr)
        return 2

    try:
        secrets = load_secrets()
        missing = [name for name in args.required if not secrets.get(name.lower(), "")]
        if missing:
            raise ValueError(
                "missing required provider secrets: "
                + ", ".join(sorted(set(missing), key=str.lower))
            )

        target = Path(github_env)
        for raw_mapping in args.map:
            env_name, sources = parse_mapping(raw_mapping)
            value = first_value(secrets, sources)
            if not value:
                raise ValueError(
                    f"required mapping {env_name} has no value in: {', '.join(sources)}"
                )
            append_github_env(target, env_name, value)
        for raw_mapping in args.optional_map:
            env_name, sources = parse_mapping(raw_mapping)
            append_github_env(target, env_name, first_value(secrets, sources))
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"provider credential export failed: {exc}", file=sys.stderr)
        return 2

    print(f"exported {len(args.map) + len(args.optional_map)} provider variables")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
