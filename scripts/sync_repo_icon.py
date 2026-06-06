#!/usr/bin/env python3
"""Publish Feather repo icons the same way as Noir: 1024px RGB PNG at repo root."""

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
# Noir uses: https://raw.githubusercontent.com/Talaxin/Noir/main/noir.png
ICON_URL = "https://raw.githubusercontent.com/Talaxin/War-Map/main/warmap.png"
REPO_ICON = ROOT / "warmap.png"


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


def repo_listing_icon(source: Image.Image) -> Image.Image:
    """1024x1024 opaque RGB — same layout as Noir/noir.png."""
    resized = source.resize((1024, 1024), Image.Resampling.LANCZOS)
    background = Image.new("RGB", (1024, 1024), (0, 0, 0))
    background.paste(resized, mask=resized.split()[3])
    return background


def write_png(path: Path, image: Image.Image) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=True, compress_level=9)


def update_repo_json() -> None:
    repo = json.loads(REPO_JSON.read_text(encoding="utf-8"))
    repo["iconURL"] = ICON_URL
    for app in repo.get("apps", []):
        app["iconURL"] = ICON_URL
    REPO_JSON.write_text(json.dumps(repo, indent=2) + "\n", encoding="utf-8")
    print(f"repo.json iconURL -> {ICON_URL}")


def main() -> int:
    version = read_project_version()
    icon = repo_listing_icon(load_icon_source())
    write_png(REPO_ICON, icon)
    update_repo_json()
    size_kb = REPO_ICON.stat().st_size // 1024
    print(f"Wrote warmap.png for v{version} (1024px RGB, {size_kb} KB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
