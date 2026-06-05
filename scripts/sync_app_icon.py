#!/usr/bin/env python3
"""Build iOS AppIcon set and Feather listing icon from warmap.png."""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "warmap.png"
APPICON_DIR = ROOT / "WarMap/Assets.xcassets/AppIcon.appiconset"
FEATHER_ICON = ROOT / "icons/feather-icon.png"
FEATHER_ICON_SIZE = 512
FEATHER_ICON_BG = (12, 10, 18)


def feather_listing_icon(source: Image.Image) -> Image.Image:
    """Opaque square icon for Feather/AltStore (transparent PNGs often show blank)."""
    resized = source.resize((FEATHER_ICON_SIZE, FEATHER_ICON_SIZE), Image.Resampling.LANCZOS)
    background = Image.new("RGB", (FEATHER_ICON_SIZE, FEATHER_ICON_SIZE), FEATHER_ICON_BG)
    background.paste(resized, mask=resized.split()[3])
    return background

# (idiom, size label, scale, pixel edge length, filename)
ICON_SPECS: list[tuple[str, str, str, int, str]] = [
    ("iphone", "20x20", "2x", 40, "AppIcon-20@2x.png"),
    ("iphone", "20x20", "3x", 60, "AppIcon-20@3x.png"),
    ("iphone", "29x29", "2x", 58, "AppIcon-29@2x.png"),
    ("iphone", "29x29", "3x", 87, "AppIcon-29@3x.png"),
    ("iphone", "40x40", "2x", 80, "AppIcon-40@2x.png"),
    ("iphone", "40x40", "3x", 120, "AppIcon-40@3x.png"),
    ("iphone", "60x60", "2x", 120, "AppIcon-60@2x.png"),
    ("iphone", "60x60", "3x", 180, "AppIcon-60@3x.png"),
    ("ipad", "20x20", "1x", 20, "AppIcon-20~ipad.png"),
    ("ipad", "20x20", "2x", 40, "AppIcon-20@2x~ipad.png"),
    ("ipad", "29x29", "1x", 29, "AppIcon-29~ipad.png"),
    ("ipad", "29x29", "2x", 58, "AppIcon-29@2x~ipad.png"),
    ("ipad", "40x40", "1x", 40, "AppIcon-40~ipad.png"),
    ("ipad", "40x40", "2x", 80, "AppIcon-40@2x~ipad.png"),
    ("ipad", "76x76", "1x", 76, "AppIcon-76~ipad.png"),
    ("ipad", "76x76", "2x", 152, "AppIcon-76@2x~ipad.png"),
    ("ipad", "83.5x83.5", "2x", 167, "AppIcon-83.5@2x~ipad.png"),
    ("ios-marketing", "1024x1024", "1x", 1024, "AppIcon-1024.png"),
]


def load_source() -> Image.Image:
    if not SOURCE.is_file():
        raise FileNotFoundError(f"Missing app icon source: {SOURCE}")
    image = Image.open(SOURCE).convert("RGBA")
    if image.size != (1024, 1024):
        image = image.resize((1024, 1024), Image.Resampling.LANCZOS)
    return image


def write_png(path: Path, image: Image.Image) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=True)


def build_contents_json() -> dict:
    images = []
    for idiom, size, scale, _pixels, filename in ICON_SPECS:
        entry: dict[str, str] = {
            "filename": filename,
            "idiom": idiom,
            "scale": scale,
            "size": size,
        }
        if idiom == "ios-marketing":
            entry.pop("scale", None)
        images.append(entry)
    return {"images": images, "info": {"author": "xcode", "version": 1}}


def main() -> int:
    source = load_source()
    APPICON_DIR.mkdir(parents=True, exist_ok=True)

    for _idiom, _size, _scale, pixels, filename in ICON_SPECS:
        resized = source.resize((pixels, pixels), Image.Resampling.LANCZOS)
        write_png(APPICON_DIR / filename, resized)

    write_png(SOURCE, source)
    write_png(FEATHER_ICON, feather_listing_icon(source))

    contents_path = APPICON_DIR / "Contents.json"
    contents_path.write_text(json.dumps(build_contents_json(), indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {len(ICON_SPECS)} icons to {APPICON_DIR}")
    print(f"Feather icon: {FEATHER_ICON}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
