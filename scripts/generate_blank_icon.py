#!/usr/bin/env python3
"""Sync app icon PNGs from warmap.png (repo root) into the asset catalog."""

from __future__ import annotations

from pathlib import Path


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    source = root / "warmap.png"
    target = root / "WarMap/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
    if not source.is_file():
        raise FileNotFoundError(f"Missing app icon source: {source}")
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(source.read_bytes())
    print(f"Synced {source} -> {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
