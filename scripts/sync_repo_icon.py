#!/usr/bin/env python3
"""Publish Feather source icons like WuXu: square JPEG on a mobile-friendly CDN."""

from __future__ import annotations

import io
import json
import re
import zipfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "warmap.png"
IPA = ROOT / "build/WarMap.ipa"
PBXPROJ = ROOT / "WarMap.xcodeproj/project.pbxproj"
REPO_JSON = ROOT / "repo.json"
REPO_ICON_PNG = ROOT / "warmap.png"
REPO_ICON_JPEG = ROOT / "icon.jpeg"
# WuXu source uses https://i.imgur.com/g17kMl9.jpeg — JPEG on a CDN, not raw GitHub PNG.
SOURCE_ICON_URL = "https://cdn.jsdelivr.net/gh/Talaxin/War-Map@main/icon.jpeg"
APP_ICON_URL = "https://cdn.jsdelivr.net/gh/Talaxin/War-Map@main/icon.jpeg"
ICON_BG = (12, 10, 18)
JPEG_SIZE = 1080


def read_project_version() -> str:
    text = PBXPROJ.read_text(encoding="utf-8")
    match = re.search(r"MARKETING_VERSION = ([^;\n]+);", text)
    if not match:
        raise ValueError(f"Could not read MARKETING_VERSION from {PBXPROJ}")
    return match.group(1).strip()


def load_icon_source() -> Image.Image:
    if IPA.is_file():
        with zipfile.ZipFile(IPA, "r") as archive:
            preferred = (
                "Payload/WarMap.app/AppIcon60x60@3x.png",
                "Payload/WarMap.app/AppIcon60x60@2x.png",
                "Payload/WarMap.app/AppIcon76x76@2x~ipad.png",
            )
            for name in preferred:
                try:
                    data = archive.read(name)
                except KeyError:
                    continue
                return Image.open(io.BytesIO(data)).convert("RGBA")

    if not SOURCE.is_file():
        raise FileNotFoundError(f"Missing icon source: {SOURCE}")
    image = Image.open(SOURCE).convert("RGBA")
    if image.size != (1024, 1024):
        image = image.resize((1024, 1024), Image.Resampling.LANCZOS)
    return image


def listing_icon(source: Image.Image, size: int) -> Image.Image:
    resized = source.resize((size, size), Image.Resampling.LANCZOS)
    background = Image.new("RGB", (size, size), ICON_BG)
    background.paste(resized, mask=resized.split()[3])
    return background


def write_png(path: Path, image: Image.Image) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=True, compress_level=9)


def write_jpeg(path: Path, image: Image.Image) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="JPEG", quality=90, optimize=True, progressive=True)


def update_repo_json() -> None:
    repo = json.loads(REPO_JSON.read_text(encoding="utf-8"))
    repo["iconURL"] = SOURCE_ICON_URL
    for app in repo.get("apps", []):
        app["iconURL"] = APP_ICON_URL
    REPO_JSON.write_text(json.dumps(repo, indent=2) + "\n", encoding="utf-8")
    print(f"repo.json source iconURL -> {SOURCE_ICON_URL}")
    print(f"repo.json app iconURL    -> {APP_ICON_URL}")


def main() -> int:
    version = read_project_version()
    source = load_icon_source()
    write_png(REPO_ICON_PNG, listing_icon(source, 1024))
    write_jpeg(REPO_ICON_JPEG, listing_icon(source, JPEG_SIZE))
    update_repo_json()
    jpeg_kb = REPO_ICON_JPEG.stat().st_size // 1024
    print(f"Wrote icon.jpeg for v{version} ({JPEG_SIZE}px JPEG, {jpeg_kb} KB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
