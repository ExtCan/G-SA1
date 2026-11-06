#!/usr/bin/env python3
"""Draw the spawn-menu icons of G-SA1's follower spawners (round 0.9.8; sadc docs/research/gsa1_096_plan.md 6.5 task 2):
addon/materials/entities/gsa1_follower_<kind>.png, 128 x 128 RGBA - a coloured disc with the character's initial. G-SA1's own
drawing, no game art.

    py -3.12 tools/make_follower_icons.py [--out DIR]     (default: addon/materials/entities)

Pure Python: a small rasteriser and a zlib PNG writer; the output is the same bytes on every run.
"""
import argparse
import os
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIZE = 128

# a 5 x 7 bitmap font for the letters the icons need
FONT = {
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
    "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
    "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
    "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
    "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
}

KINDS = [
    ("sonic", "S", (40, 90, 220)),
    ("tails", "T", (245, 165, 40)),
    ("knuckles", "K", (215, 45, 45)),
    ("amy", "A", (240, 120, 170)),
    ("gamma", "E", (130, 135, 150)),
    ("big", "B", (120, 80, 190)),
    ("eggman", "D", (205, 95, 30)),
    ("tikal", "T", (60, 160, 150)),
    # 0.9.9h: a skin's follower (entities/gsa1_follower_spawner.lua: gsa1_follower_<entry name>; without its icon a skin shows its base's)
    ("metalsonic", "M", (55, 70, 120)),
]


def png(px):
    raw = bytearray()
    for row in px:
        raw.append(0)
        for r, g, b, a in row:
            raw += bytes((r, g, b, a))

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)) +
            chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b""))


def icon(letter, rgb):
    r, g, b = rgb
    px = [[(0, 0, 0, 0) for _ in range(SIZE)] for _ in range(SIZE)]
    c = (SIZE - 1) / 2
    for y in range(SIZE):
        for x in range(SIZE):
            d = ((x - c) ** 2 + (y - c) ** 2) ** 0.5
            if d <= 60:
                px[y][x] = (r, g, b, 255)
            elif d <= 63:
                px[y][x] = (28, 28, 34, 255)
    # the initial, white with a dark edge
    scale = 11
    w, h = 5 * scale, 7 * scale
    x0, y0 = (SIZE - w) // 2, (SIZE - h) // 2
    rows = FONT[letter]
    for pass_, col in enumerate(((28, 28, 34, 255), (250, 250, 250, 255))):
        grow = 3 if pass_ == 0 else 0
        for ry, row in enumerate(rows):
            for rx, bit in enumerate(row):
                if bit != "1":
                    continue
                for py in range(y0 + ry * scale - grow, y0 + (ry + 1) * scale + grow):
                    for pxx in range(x0 + rx * scale - grow, x0 + (rx + 1) * scale + grow):
                        px[py][pxx] = col
    return png(px)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(ROOT, "addon", "materials", "entities"))
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    for name, letter, rgb in KINDS:
        path = os.path.join(args.out, "gsa1_follower_%s.png" % name)
        data = icon(letter, rgb)
        with open(path, "wb") as f:
            f.write(data)
        print("%s: %d bytes" % (path, len(data)))


if __name__ == "__main__":
    main()
