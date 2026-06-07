#!/usr/bin/env python3
"""
Refresh Feather / AltStore repo.json metadata from build/WarMap.ipa.

Usage:
  python3 release_esign.py --description "Release notes."
"""

from __future__ import annotations

import argparse
import json
import plistlib
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

BUNDLE_ID = "com.talaxin.warmap"
SOURCE_ICON_URL = "https://cdn.jsdelivr.net/gh/Talaxin/War-Map@main/icon.jpeg"
DOWNLOAD_URL = "https://cdn.jsdelivr.net/gh/Talaxin/War-Map@main/build/WarMap.ipa"
APP_DESCRIPTION = (
    "Plan routes, pick from alternate paths, and navigate with turn-by-turn guidance. "
    "Remembers roads you have driven."
)


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


def utc_now_z() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).strftime("%Y-%m-%dT%H:%M:%SZ")


def normalize_repo(repo: dict[str, Any], *, version: str, description: str, ipa_size: int, now_z: str) -> None:
    repo["iconURL"] = SOURCE_ICON_URL
    repo["tintColor"] = "007AFF"

    apps = repo.get("apps", [])
    app = next((a for a in apps if a.get("bundleIdentifier") == BUNDLE_ID), None)
    if app is None:
        raise ValueError(f"No app entry for {BUNDLE_ID!r}")

    app["downloadURL"] = DOWNLOAD_URL
    app["iconURL"] = SOURCE_ICON_URL
    app["tintColor"] = "007AFF"
    app["size"] = ipa_size
    app["beta"] = False
    app["localizedDescription"] = APP_DESCRIPTION
    app["appPermissions"] = {
        "privacy": {
            "NSLocationWhenInUseUsageDescription": (
                "War Map uses your location to show your position, plan routes, "
                "and provide turn-by-turn directions."
            ),
            "NSLocationAlwaysAndWhenInUseUsageDescription": (
                "War Map uses your location during navigation to update your position on the map."
            ),
        }
    }
    app["versions"] = [
        {
            "version": version,
            "date": now_z,
            "localizedDescription": description,
            "downloadURL": DOWNLOAD_URL,
            "size": ipa_size,
        }
    ]
    app["version"] = version
    app["versionDate"] = now_z
    app["versionDescription"] = description


def main() -> int:
    parser = argparse.ArgumentParser(description="Refresh War Map Feather repo metadata.")
    parser.add_argument("--repo-json", default="repo.json")
    parser.add_argument("--ipa", default="build/WarMap.ipa")
    parser.add_argument("--bundle-id", default=BUNDLE_ID)
    parser.add_argument("--description", default="Latest War Map update.")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    repo_json_path = Path(args.repo_json).resolve()
    ipa_path = Path(args.ipa).resolve()
    ensure_file(repo_json_path, "repo.json")
    ensure_file(ipa_path, "IPA")

    repo = read_json(repo_json_path)
    ipa_size = ipa_path.stat().st_size
    ipa_short_version, _ipa_build_version = read_ipa_versions(ipa_path)
    if ipa_short_version is None:
        raise ValueError("Could not read CFBundleShortVersionString from IPA")

    before_app_version = str(
        next(
            (a.get("version", "0.0.0") for a in repo.get("apps", []) if a.get("bundleIdentifier") == args.bundle_id),
            "0.0.0",
        )
    )
    now_z = utc_now_z()
    normalize_repo(
        repo,
        version=ipa_short_version,
        description=args.description,
        ipa_size=ipa_size,
        now_z=now_z,
    )

    if args.dry_run:
        print(f"[dry-run] {before_app_version} -> {ipa_short_version}, size={ipa_size}")
        return 0

    write_json(repo_json_path, repo)
    print(f"Updated {repo_json_path}")
    print(f"Version: {before_app_version} -> {ipa_short_version}")
    print(f"IPA size: {ipa_size}")
    print(f"Download URL: {DOWNLOAD_URL}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
