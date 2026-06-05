#!/usr/bin/env python3
"""Write solid gray PNG icons for repo + app bundle assets."""

from __future__ import annotations

import struct
import zlib
from pathlib import Path


def png_rgb(width: int, height: int, rgb: tuple[int, int, int]) -> bytes:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    raw = b"".join(b"\x00" + bytes(rgb) * width for _ in range(height))
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    gray = (0x80, 0x80, 0x80)
    targets = [
        root / "warmap.png",
        root / "WarMap/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png",
    ]
    blob = png_rgb(1024, 1024, gray)
    for path in targets:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(blob)
        print(f"Wrote {path} ({len(blob)} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
