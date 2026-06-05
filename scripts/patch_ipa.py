#!/usr/bin/env python3
"""Embed War Map icons, Assets.car, and bundle version into an IPA."""

from __future__ import annotations

import argparse
import json
import plistlib
import re
import shutil
import subprocess
import tempfile
import zipfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "warmap.png"
ASSET_CATALOG = ROOT / "WarMap/Assets.xcassets"
PBXPROJ = ROOT / "WarMap.xcodeproj/project.pbxproj"
MIN_VALID_ASSETS_CAR_BYTES = 100_000

# Filenames iOS expects in the app bundle for AppIcon.
BUNDLE_ICONS: list[tuple[str, int]] = [
    ("AppIcon60x60@2x.png", 120),
    ("AppIcon60x60@3x.png", 180),
    ("AppIcon76x76@2x~ipad.png", 152),
]


def read_project_versions() -> tuple[str, str]:
    text = PBXPROJ.read_text(encoding="utf-8")
    marketing = re.search(r"MARKETING_VERSION = ([^;\n]+);", text)
    build = re.search(r"CURRENT_PROJECT_VERSION = ([^;\n]+);", text)
    if not marketing or not build:
        raise ValueError(f"Could not read version fields from {PBXPROJ}")
    return marketing.group(1).strip(), build.group(1).strip()


def load_source() -> Image.Image:
    image = Image.open(SOURCE).convert("RGBA")
    if image.size != (1024, 1024):
        image = image.resize((1024, 1024), Image.Resampling.LANCZOS)
    return image


def assets_car_is_broken(car_path: Path) -> bool:
    if not car_path.is_file():
        return True
    if car_path.stat().st_size < MIN_VALID_ASSETS_CAR_BYTES:
        return True
    try:
        result = subprocess.run(
            ["xcrun", "assetutil", "--info", str(car_path)],
            check=True,
            capture_output=True,
            text=True,
        )
        entries = json.loads(result.stdout)
    except (subprocess.CalledProcessError, json.JSONDecodeError, FileNotFoundError):
        return True

    for entry in entries:
        if entry.get("Name") != "AppIcon":
            continue
        if entry.get("AssetType") != "Icon Image":
            continue
        if entry.get("ColorModel") == "Monochrome":
            return True
        if entry.get("PixelWidth") == 1024 and (entry.get("SizeOnDisk") or 0) < 10_000:
            return True
    return False


def rebuild_assets_car(app_dir: Path) -> None:
    if not ASSET_CATALOG.is_dir():
        raise FileNotFoundError(f"Missing asset catalog: {ASSET_CATALOG}")

    with tempfile.TemporaryDirectory(prefix="warmap-actool-") as tmp:
        compile_dir = Path(tmp) / "compiled"
        compile_dir.mkdir()
        partial_plist = Path(tmp) / "partial.plist"
        subprocess.run(
            [
                "xcrun",
                "actool",
                str(ASSET_CATALOG),
                "--compile",
                str(compile_dir),
                "--platform",
                "iphoneos",
                "--minimum-deployment-target",
                "16.0",
                "--app-icon",
                "AppIcon",
                "--output-partial-info-plist",
                str(partial_plist),
            ],
            check=True,
        )

        compiled_car = compile_dir / "Assets.car"
        if not compiled_car.is_file():
            raise FileNotFoundError("actool did not produce Assets.car")

        shutil.copy2(compiled_car, app_dir / "Assets.car")

        for filename, _edge in BUNDLE_ICONS:
            loose_icon = compile_dir / filename
            if loose_icon.is_file():
                shutil.copy2(loose_icon, app_dir / filename)


def patch_ipa(
    ipa_path: Path,
    *,
    short_version: str,
    build_version: str,
) -> None:
    source = load_source()
    with tempfile.TemporaryDirectory(prefix="warmap-ipa-") as tmp:
        work = Path(tmp)
        with zipfile.ZipFile(ipa_path, "r") as zf:
            zf.extractall(work)

        app_dirs = list(work.glob("Payload/*.app"))
        if not app_dirs:
            raise FileNotFoundError("No .app bundle found in IPA")
        app_dir = app_dirs[0]

        car_path = app_dir / "Assets.car"
        if assets_car_is_broken(car_path):
            rebuild_assets_car(app_dir)

        for filename, edge in BUNDLE_ICONS:
            icon = source.resize((edge, edge), Image.Resampling.LANCZOS)
            icon.save(app_dir / filename, format="PNG", optimize=True)

        info_path = app_dir / "Info.plist"
        with info_path.open("rb") as f:
            info = plistlib.load(f)
        info["CFBundleShortVersionString"] = short_version
        info["CFBundleVersion"] = build_version
        with info_path.open("wb") as f:
            plistlib.dump(info, f)

        staged = work / "WarMap.ipa"
        payload_root = work / "Payload"
        with zipfile.ZipFile(staged, "w", compression=zipfile.ZIP_DEFLATED) as zf:
            for path in sorted(payload_root.rglob("*")):
                if path.is_file():
                    arcname = path.relative_to(work).as_posix()
                    zf.write(path, arcname)

        shutil.move(staged, ipa_path)


def main() -> int:
    parser = argparse.ArgumentParser(description="Patch icons and version into WarMap.ipa")
    parser.add_argument("--ipa", default="build/WarMap.ipa")
    parser.add_argument("--short-version", help="Override MARKETING_VERSION from project.pbxproj")
    parser.add_argument("--build-version", help="Override CURRENT_PROJECT_VERSION from project.pbxproj")
    args = parser.parse_args()

    short_version, build_version = read_project_versions()
    if args.short_version:
        short_version = args.short_version
    if args.build_version:
        build_version = args.build_version

    ipa_path = (ROOT / args.ipa).resolve()
    if not ipa_path.is_file():
        raise FileNotFoundError(ipa_path)

    patch_ipa(
        ipa_path,
        short_version=short_version,
        build_version=build_version,
    )
    print(f"Patched {ipa_path} -> {short_version} ({build_version})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
