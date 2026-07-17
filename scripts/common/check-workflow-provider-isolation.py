#!/usr/bin/env python3
"""Reject direct provider-secret bindings in shared GitHub workflows/actions."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--github-dir", required=True, type=Path)
    args = parser.parse_args()
    names = {line.strip().lower() for line in sys.stdin if line.strip()}
    leaks: list[str] = []
    for path in sorted(args.github_dir.rglob("*")):
        if not path.is_file():
            continue
        for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            lowered = line.lower()
            for name in names:
                if f"secrets.{name}" in lowered:
                    leaks.append(f"{path}:{line_number}: direct binding of {name}")
    if leaks:
        print("\n".join(leaks), file=sys.stderr)
        return 1
    print(f"workflow provider isolation passed ({len(names)} credential names checked)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
