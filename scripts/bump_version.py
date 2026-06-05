#!/usr/bin/env python3
"""Bump War Map MARKETING_VERSION by 0.0.1 and mirror it to CURRENT_PROJECT_VERSION."""

from __future__ import annotations

import argparse
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PBXPROJ = ROOT / "WarMap.xcodeproj/project.pbxproj"


def bump_patch(version: str) -> str:
    parts = version.split(".")
    if len(parts) != 3 or not all(part.isdigit() for part in parts):
        raise ValueError(f"Expected x.y.z version, got {version!r}")
    major, minor, patch = (int(part) for part in parts)
    return f"{major}.{minor}.{patch + 1}"


def read_marketing_version(text: str) -> str:
    match = re.search(r"MARKETING_VERSION = ([^;\n]+);", text)
    if not match:
        raise ValueError(f"MARKETING_VERSION not found in {PBXPROJ}")
    return match.group(1).strip()


def write_versions(text: str, version: str) -> str:
    text = re.sub(
        r"MARKETING_VERSION = [^;\n]+;",
        f"MARKETING_VERSION = {version};",
        text,
    )
    text = re.sub(
        r"CURRENT_PROJECT_VERSION = [^;\n]+;",
        f"CURRENT_PROJECT_VERSION = {version};",
        text,
    )
    return text


def main() -> int:
    parser = argparse.ArgumentParser(description="Bump War Map version by +0.0.1.")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    text = PBXPROJ.read_text(encoding="utf-8")
    before = read_marketing_version(text)
    after = bump_patch(before)

    if args.dry_run:
        print(f"{before} -> {after}")
        return 0

    PBXPROJ.write_text(write_versions(text, after), encoding="utf-8")
    print(f"Bumped {PBXPROJ.name}: {before} -> {after}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
