"""Draw the Spatial Plates icon (dependency-free).

Writes SpatialPlates/Media/Icon.tga (64x64, 32-bit, uncompressed: a format
the WoW client loads directly). Pass --preview PATH to also write a PNG.

Design: a dark radar disc with three range rings in the addon's distance
colors (green near, yellow middle, red far), a white center dot for the
player, and two blips. Run: python3 scripts/make_icon.py
"""
from __future__ import annotations

import argparse
import math
from pathlib import Path
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "SpatialPlates" / "Media" / "Icon.tga"
SIZE = 64
SAMPLES = 4  # supersampling per axis for anti-aliased edges

CENTER = (SIZE - 1) / 2.0
GREEN = (61, 220, 98)
YELLOW = (242, 195, 53)
RED = (232, 74, 60)
WHITE = (245, 248, 252)
RIM = (201, 214, 227)


def sample(x: float, y: float):
    """Return (r, g, b, a) in 0..255 floats for one sub-pixel."""
    dx, dy = x - CENTER, y - CENTER
    d = math.hypot(dx, dy)
    if d > 31.0:
        return (0.0, 0.0, 0.0, 0.0)
    # Disc: dark navy, slightly lighter toward the top.
    t = (y / SIZE)
    color = (15 + 14 * (1 - t), 26 + 21 * (1 - t), 42 + 29 * (1 - t))
    if d > 29.0:
        color = RIM
    # Range rings (outer to inner).
    for radius, ring in ((24.0, RED), (17.0, YELLOW), (10.0, GREEN)):
        if abs(d - radius) <= 1.4:
            color = ring
    # Blips: an enemy on the outer ring, an ally on the inner ring.
    for (bx, by, blip) in ((CENTER + 17.0, CENTER - 17.0, RED), (CENTER - 7.1, CENTER + 7.1, GREEN)):
        if math.hypot(x - bx, y - by) <= 3.6:
            color = blip
        elif math.hypot(x - bx, y - by) <= 4.6:
            color = (10, 14, 22)
    # Player: white center dot.
    if d <= 3.4:
        color = WHITE
    return (float(color[0]), float(color[1]), float(color[2]), 255.0)


def render():
    pixels = []  # rows top to bottom, RGBA bytes
    step = 1.0 / SAMPLES
    for py in range(SIZE):
        row = bytearray()
        for px in range(SIZE):
            acc = [0.0, 0.0, 0.0, 0.0]
            for sy in range(SAMPLES):
                for sx in range(SAMPLES):
                    r, g, b, a = sample(px + (sx + 0.5) * step - 0.5, py + (sy + 0.5) * step - 0.5)
                    acc[0] += r * a
                    acc[1] += g * a
                    acc[2] += b * a
                    acc[3] += a
            n = SAMPLES * SAMPLES
            alpha = acc[3] / n
            if acc[3] > 0:
                r, g, b = (acc[i] / acc[3] for i in range(3))
            else:
                r = g = b = 0.0
            row += bytes((round(r), round(g), round(b), round(alpha)))
        pixels.append(bytes(row))
    return pixels


def write_tga(path: Path, rows) -> None:
    # Type 2 (uncompressed true-color), 32 bpp, descriptor 0x28 = top-left
    # origin + 8 alpha bits. Pixels are stored as BGRA.
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)
    body = bytearray()
    for row in rows:
        for i in range(0, len(row), 4):
            r, g, b, a = row[i:i + 4]
            body += bytes((b, g, r, a))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(header + bytes(body))


def write_png(path: Path, rows, scale: int = 4) -> None:
    raw = bytearray()
    for row in rows:
        big = bytearray()
        for i in range(0, len(row), 4):
            big += row[i:i + 4] * scale
        for _ in range(scale):
            raw += b"\x00" + big

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    w = h = SIZE * scale
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")
    path.write_bytes(png)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preview", type=Path, help="also write an enlarged PNG preview here")
    args = parser.parse_args()
    rows = render()
    write_tga(OUTPUT, rows)
    print(f"Wrote {OUTPUT}")
    if args.preview:
        write_png(args.preview, rows)
        print(f"Wrote {args.preview}")


if __name__ == "__main__":
    main()
