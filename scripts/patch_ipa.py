#!/usr/bin/env python3
"""Embed War Map icons and bundle version into an unsigned IPA."""

from __future__ import annotations

import argparse
import plistlib
import shutil
import tempfile
import zipfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "warmap.png"

# Filenames iOS expects in the app bundle for AppIcon.
BUNDLE_ICONS: list[tuple[str, int]] = [
    ("AppIcon60x60@2x.png", 120),
    ("AppIcon60x60@3x.png", 180),
    ("AppIcon76x76@2x~ipad.png", 152),
]


def load_source() -> Image.Image:
    image = Image.open(SOURCE).convert("RGBA")
    if image.size != (1024, 1024):
        image = image.resize((1024, 1024), Image.Resampling.LANCZOS)
    return image


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
    parser.add_argument("--short-version", default="0.3.1")
    parser.add_argument("--build-version", default="5")
    args = parser.parse_args()

    ipa_path = (ROOT / args.ipa).resolve()
    if not ipa_path.is_file():
        raise FileNotFoundError(ipa_path)

    patch_ipa(
        ipa_path,
        short_version=args.short_version,
        build_version=args.build_version,
    )
    print(f"Patched {ipa_path} -> {args.short_version} ({args.build_version})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
