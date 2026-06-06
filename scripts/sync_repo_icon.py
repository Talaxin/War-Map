#!/usr/bin/env python3
"""Write Feather/AltStore listing icons from the same artwork embedded in the IPA."""

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
ICONS_DIR = ROOT / "icons"
LISTING_SIZE = 512
ICON_URL_BASE = "https://github.com/Talaxin/War-Map/raw/main/icons"


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


def listing_icon(source: Image.Image) -> Image.Image:
    """Opaque square icon — matches the installed app icon and loads reliably in Feather."""
    resized = source.resize((LISTING_SIZE, LISTING_SIZE), Image.Resampling.LANCZOS)
    background = Image.new("RGB", (LISTING_SIZE, LISTING_SIZE), (0, 0, 0))
    background.paste(resized, mask=resized.split()[3])
    return background


def write_png(path: Path, image: Image.Image) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=True, compress_level=9)


def update_repo_json(version: str, icon_filename: str) -> None:
    icon_url = f"{ICON_URL_BASE}/{icon_filename}"
    repo = json.loads(REPO_JSON.read_text(encoding="utf-8"))
    repo["iconURL"] = icon_url
    for app in repo.get("apps", []):
        app["iconURL"] = icon_url
    REPO_JSON.write_text(json.dumps(repo, indent=2) + "\n", encoding="utf-8")
    print(f"repo.json iconURL -> {icon_url}")


def main() -> int:
    version = read_project_version()
    source = load_icon_source()
    icon = listing_icon(source)

    versioned_name = f"repo-icon-{version}.png"
    stable_name = "repo-icon.png"

    write_png(ICONS_DIR / versioned_name, icon)
    write_png(ICONS_DIR / stable_name, icon)
    # Backward-compatible filenames used by older repo.json entries.
    write_png(ICONS_DIR / "feather-icon.png", icon)
    write_png(ICONS_DIR / "app-icon.png", icon)

    update_repo_json(version, versioned_name)
    print(f"Wrote listing icons for v{version} ({LISTING_SIZE}px RGB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
