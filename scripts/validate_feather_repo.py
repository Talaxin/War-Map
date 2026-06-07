#!/usr/bin/env python3
"""Validate repo.json against Feather / AltStore expectations and live asset URLs."""

from __future__ import annotations

import argparse
import json
import plistlib
import re
import sys
import urllib.request
import zipfile
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_REPO = ROOT / "repo.json"
DEFAULT_IPA = ROOT / "build/WarMap.ipa"
EXPECTED_BUNDLE_ID = "com.talaxin.warmap"
ISO_Z = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")


def fetch(url: str, timeout: float = 30.0) -> tuple[int, bytes]:
    request = urllib.request.Request(url, method="GET", headers={"User-Agent": "WarMap-Feather-Validate/1.0"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.status, response.read()


def read_ipa_bundle_id_and_version(ipa_path: Path) -> tuple[str, str]:
    with zipfile.ZipFile(ipa_path, "r") as archive:
        info_name = next(
            (
                name
                for name in archive.namelist()
                if name.startswith("Payload/") and name.endswith(".app/Info.plist")
            ),
            None,
        )
        if not info_name:
            raise ValueError(f"No Info.plist found in {ipa_path}")
        with archive.open(info_name) as handle:
            info = plistlib.load(handle)
    bundle_id = info.get("CFBundleIdentifier")
    version = info.get("CFBundleShortVersionString")
    if not bundle_id or not version:
        raise ValueError(f"Missing bundle id or version in {ipa_path}")
    return str(bundle_id), str(version)


def validate_structure(repo: dict[str, Any]) -> list[str]:
    errors: list[str] = []

    if not repo.get("name"):
        errors.append("repo.name is required")
    if not repo.get("identifier"):
        errors.append("repo.identifier is required")

    apps = repo.get("apps")
    if not isinstance(apps, list) or not apps:
        errors.append("repo.apps must contain at least one app")
        return errors

    for index, app in enumerate(apps):
        prefix = f"apps[{index}]"
        for key in ("name", "bundleIdentifier", "version", "downloadURL", "iconURL"):
            if not app.get(key):
                errors.append(f"{prefix}.{key} is required")

        versions = app.get("versions")
        if not isinstance(versions, list) or not versions:
            errors.append(f"{prefix}.versions must contain exactly one entry")
            continue
        if len(versions) != 1:
            errors.append(f"{prefix}.versions must contain exactly one entry (found {len(versions)})")

        version = versions[0]
        for key in ("version", "date", "downloadURL", "size"):
            if key not in version or version[key] in (None, ""):
                errors.append(f"{prefix}.versions[0].{key} is required")

        for date_key in ("versionDate",):
            value = app.get(date_key)
            if value and not ISO_Z.match(str(value)):
                errors.append(f"{prefix}.{date_key} must use yyyy-MM-ddTHH:MM:SSZ (got {value!r})")

        if version.get("date") and not ISO_Z.match(str(version["date"])):
            errors.append(f"{prefix}.versions[0].date must use yyyy-MM-ddTHH:MM:SSZ (got {version['date']!r})")

        for url_key in ("downloadURL", "iconURL"):
            url = app.get(url_key)
            if url and not str(url).startswith(("http://", "https://")):
                errors.append(f"{prefix}.{url_key} must be an absolute URL")

        if "size" in app and not isinstance(app["size"], int):
            errors.append(f"{prefix}.size must be an integer byte count")
        if "size" in version and not isinstance(version["size"], int):
            errors.append(f"{prefix}.versions[0].size must be an integer byte count")

    news = repo.get("news", [])
    if isinstance(news, list):
        for index, item in enumerate(news):
            date = item.get("date")
            if date and not ISO_Z.match(str(date)):
                errors.append(f"news[{index}].date must use yyyy-MM-ddTHH:MM:SSZ (got {date!r})")

    return errors


def validate_against_ipa(repo: dict[str, Any], ipa_path: Path) -> list[str]:
    errors: list[str] = []
    bundle_id, ipa_version = read_ipa_bundle_id_and_version(ipa_path)
    ipa_size = ipa_path.stat().st_size

    app = repo["apps"][0]
    if app.get("bundleIdentifier") != bundle_id:
        errors.append(f"bundleIdentifier {app.get('bundleIdentifier')!r} != IPA {bundle_id!r}")
    if app.get("version") != ipa_version:
        errors.append(f"version {app.get('version')!r} != IPA {ipa_version!r}")
    if app.get("size") != ipa_size:
        errors.append(f"app.size {app.get('size')} != IPA file size {ipa_size}")
    if app["versions"][0].get("size") != ipa_size:
        errors.append(f"versions[0].size {app['versions'][0].get('size')} != IPA file size {ipa_size}")
    if app["versions"][0].get("version") != ipa_version:
        errors.append(f"versions[0].version {app['versions'][0].get('version')!r} != IPA {ipa_version!r}")

    return errors


def validate_remote_assets(repo: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    app = repo["apps"][0]
    declared_size = app.get("size")

    for label, url in (
        ("repo.iconURL", repo.get("iconURL")),
        ("app.iconURL", app.get("iconURL")),
        ("app.downloadURL", app.get("downloadURL")),
        ("versions[0].downloadURL", app["versions"][0].get("downloadURL")),
    ):
        if not url:
            continue
        url = str(url)
        if "cdn.jsdelivr.net" in url and "/build/" in url:
            errors.append(f"{label} uses jsDelivr for IPA; GitHub raw is required to avoid stale CDN binaries")
        try:
            status, body = fetch(url)
        except Exception as exc:  # noqa: BLE001
            errors.append(f"{label} fetch failed for {url}: {exc}")
            continue
        if status != 200:
            errors.append(f"{label} returned HTTP {status} for {url}")
            continue
        if label.endswith("downloadURL") and declared_size is not None and len(body) != declared_size:
            errors.append(
                f"{label} size mismatch: repo declares {declared_size} bytes but {url} returned {len(body)} bytes"
            )

    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate Feather repo.json metadata.")
    parser.add_argument("--repo-json", default=str(DEFAULT_REPO))
    parser.add_argument("--ipa", default=str(DEFAULT_IPA))
    parser.add_argument("--skip-remote", action="store_true", help="Skip live URL checks.")
    args = parser.parse_args()

    repo_path = Path(args.repo_json).resolve()
    ipa_path = Path(args.ipa).resolve()
    repo = json.loads(repo_path.read_text(encoding="utf-8"))

    errors = validate_structure(repo)
    if ipa_path.is_file():
        errors.extend(validate_against_ipa(repo, ipa_path))
    else:
        print(f"warning: IPA not found at {ipa_path}; skipping local IPA checks", file=sys.stderr)

    if not args.skip_remote:
        errors.extend(validate_remote_assets(repo))

    if errors:
        print("Feather repo validation failed:", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1

    app = repo["apps"][0]
    print(f"OK: {repo['name']} v{app['version']} ({app['size']} bytes)")
    print(f"downloadURL: {app['downloadURL']}")
    print(f"iconURL: {app['iconURL']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
