#!/usr/bin/env python3
"""
Build a structural placeholder IPA for Feather / AltStore repo metadata.

This zip matches bundle id + version fields for repo.json. Replace build/WarMap.ipa
with an Xcode or CI build before sideloading to a device (Feather re-signs a real
arm64 binary; this stub is for source listing until then).
"""

from __future__ import annotations

import plistlib
import shutil
import zipfile
from pathlib import Path

APP_NAME = "WarMap"
BUNDLE_ID = "com.talaxin.warmap"
DISPLAY_NAME = "War Map"
VERSION = "0.0.1"
BUILD_NUMBER = "1"
MIN_OS = "15.0"


def write_pkginfo(path: Path) -> None:
    path.write_bytes(b"APPL????")


def write_info_plist(app_dir: Path) -> None:
    info = {
        "CFBundleDevelopmentRegion": "en",
        "CFBundleDisplayName": DISPLAY_NAME,
        "CFBundleExecutable": APP_NAME,
        "CFBundleIdentifier": BUNDLE_ID,
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": APP_NAME,
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": VERSION,
        "CFBundleSupportedPlatforms": ["iPhoneOS"],
        "CFBundleVersion": BUILD_NUMBER,
        "LSRequiresIPhoneOS": True,
        "MinimumOSVersion": MIN_OS,
        "UIDeviceFamily": [1, 2],
        "UIRequiredDeviceCapabilities": ["arm64"],
    }
    with (app_dir / "Info.plist").open("wb") as f:
        plistlib.dump(info, f)


def copy_blank_icons(app_dir: Path, repo_root: Path) -> None:
    icon_src = repo_root / "warmap.png"
    if not icon_src.is_file():
        raise FileNotFoundError(f"Missing blank repo icon: {icon_src}")
    for name in ("AppIcon60x60@2x.png", "AppIcon76x76@2x~ipad.png"):
        shutil.copy2(icon_src, app_dir / name)


def build_ipa(repo_root: Path, output_ipa: Path) -> int:
    staging = repo_root / "build" / ".ipa-staging"
    payload = staging / "Payload"
    app_dir = payload / f"{APP_NAME}.app"

    if staging.exists():
        shutil.rmtree(staging)
    app_dir.mkdir(parents=True)

    write_info_plist(app_dir)
    write_pkginfo(app_dir / "PkgInfo")
    copy_blank_icons(app_dir, repo_root)
    # Zero-byte stub; replace with compiled WarMap binary from Xcode/CI for install.
    (app_dir / APP_NAME).write_bytes(b"")

    output_ipa.parent.mkdir(parents=True, exist_ok=True)
    if output_ipa.exists():
        output_ipa.unlink()

    with zipfile.ZipFile(output_ipa, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for path in sorted(payload.rglob("*")):
            if path.is_file():
                zf.write(path, path.relative_to(staging).as_posix())

    shutil.rmtree(staging)
    print(f"Wrote {output_ipa} ({output_ipa.stat().st_size} bytes)")
    return 0


def main() -> int:
    repo_root = Path(__file__).resolve().parents[1]
    output = repo_root / "build" / "WarMap.ipa"
    return build_ipa(repo_root, output)


if __name__ == "__main__":
    raise SystemExit(main())
