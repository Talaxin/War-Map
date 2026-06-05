#!/usr/bin/env python3
"""
Refresh Feather / AltStore repo.json metadata from build/WarMap.ipa.

Usage:
  python3 release_esign.py --description "Placeholder notes."
  python3 release_esign.py --bump --description "New build."
"""

from __future__ import annotations

import argparse
import json
import plistlib
import zipfile
from datetime import datetime
from pathlib import Path
from typing import Any

BUNDLE_ID = "com.talaxin.warmap"


def bump_patch(version: str) -> str:
    parts = version.split(".")
    if len(parts) != 3:
        raise ValueError(f"Invalid semver (expected x.y.z): {version}")
    major, minor, patch = parts
    return f"{major}.{minor}.{int(patch) + 1}"


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, value: Any) -> None:
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def ensure_file(path: Path, label: str) -> None:
    if not path.exists() or not path.is_file():
        raise FileNotFoundError(f"{label} not found: {path}")


def read_ipa_versions(ipa_path: Path) -> tuple[str | None, str | None]:
    with zipfile.ZipFile(ipa_path, "r") as zf:
        info_name = next(
            (
                name
                for name in zf.namelist()
                if name.startswith("Payload/")
                and name.endswith(".app/Info.plist")
            ),
            None,
        )
        if not info_name:
            return (None, None)
        with zf.open(info_name) as f:
            info = plistlib.load(f)
        short = info.get("CFBundleShortVersionString")
        build = info.get("CFBundleVersion")
        return (str(short) if short is not None else None, str(build) if build is not None else None)


def main() -> int:
    parser = argparse.ArgumentParser(description="Refresh War Map Feather repo metadata.")
    parser.add_argument("--repo-json", default="repo.json")
    parser.add_argument("--ipa", default="build/WarMap.ipa")
    parser.add_argument("--bundle-id", default=BUNDLE_ID)
    parser.add_argument("--description", default="Latest War Map update.")
    parser.add_argument("--bump", action="store_true", help="Increment version by +0.0.1.")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    repo_json_path = Path(args.repo_json).resolve()
    ipa_path = Path(args.ipa).resolve()
    ensure_file(repo_json_path, "repo.json")
    ensure_file(ipa_path, "IPA")

    repo = read_json(repo_json_path)
    apps = repo.get("apps", [])
    app = next((a for a in apps if a.get("bundleIdentifier") == args.bundle_id), None)
    if app is None:
        known = [a.get("bundleIdentifier") for a in apps]
        raise ValueError(f"No app with bundleIdentifier {args.bundle_id!r}. Known: {known}")

    versions = app.get("versions", [])
    if not versions:
        raise ValueError("repo.json app has no versions[] entries")
    latest = versions[0]

    now_iso = datetime.now().astimezone().replace(microsecond=0).isoformat()
    ipa_size = ipa_path.stat().st_size
    ipa_short_version, _ipa_build_version = read_ipa_versions(ipa_path)

    before_app_version = str(app.get("version", "0.0.0"))
    after_app_version = before_app_version
    if args.bump:
        after_app_version = bump_patch(before_app_version)
        app["version"] = after_app_version
        latest["version"] = bump_patch(str(latest.get("version", before_app_version)))
        if ipa_short_version is not None and ipa_short_version != after_app_version:
            raise ValueError(
                "IPA version mismatch: "
                f"CFBundleShortVersionString={ipa_short_version} expected {after_app_version}. "
                "Rebuild the IPA, then rerun release_esign.py."
            )

    app["versionDate"] = now_iso
    app["versionDescription"] = args.description
    latest["date"] = now_iso
    latest["localizedDescription"] = args.description
    latest["size"] = ipa_size

    if args.dry_run:
        print(f"[dry-run] {before_app_version} -> {after_app_version}, size={ipa_size}")
        return 0

    write_json(repo_json_path, repo)
    print(f"Updated {repo_json_path}")
    print(f"Version: {before_app_version} -> {after_app_version}")
    print(f"IPA size: {ipa_size}")
    if ipa_short_version:
        print(f"IPA bundle version: {ipa_short_version}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
