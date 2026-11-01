#!/usr/bin/env python3
"""Draw the spawn-menu icons of G-SA1's Board On / Board Off trigger boxes (round 0.9.5; sadc docs/research/
gsa1_095_plan.md 4.19 and 6.4 task 6): addon/materials/entities/gsa1_board_on.png and gsa1_board_off.png, 128 x 128 RGBA -
a translucent green (Board On) or red (Board Off) box, a plain board outline lying in it and "ON" / "OFF". G-SA1's own
drawing (no game art; rendered pictures from the owner's disc are owner question O10).

    py -3.12 tools/make_board_icons.py [--out DIR]     (default: addon/materials/entities)

Pure Python: a small rasteriser (filled polygons, lines, a capsule) and a zlib PNG writer; the output is the same bytes on
every run.
"""
import argparse
import os
import struct
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIZE = 128

# a 5 x 7 bitmap font for the letters the icons need
FONT = {
    "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "N": ["10001", "11001", "10101", "10101", "10011", "10001", "10001"],
    "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
}


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.px = [[(0, 0, 0, 0) for _ in range(w)] for _ in range(h)]

    def blend(self, x, y, col):
        if not (0 <= x < self.w and 0 <= y < self.h):
            return
        r, g, b, a = col
        if a <= 0:
            return
        dr, dg, db, da = self.px[y][x]
        sa = a / 255.0
        oa = sa + (da / 255.0) * (1 - sa)
        if oa <= 0:
            self.px[y][x] = (0, 0, 0, 0)
            return
        def ch(s, d):
            return int(round((s * sa + d * (da / 255.0) * (1 - sa)) / oa))
        self.px[y][x] = (ch(r, dr), ch(g, dg), ch(b, db), int(round(oa * 255)))

    def polygon(self, pts, col):
        """a filled convex or concave polygon (even-odd scanlines, pixel centres)"""
        ys = [p[1] for p in pts]
        for y in range(max(0, int(min(ys))), min(self.h, int(max(ys)) + 1)):
            yc = y + 0.5
            xs = []
            for i in range(len(pts)):
                x0, y0 = pts[i]
                x1, y1 = pts[(i + 1) % len(pts)]
                if (y0 <= yc < y1) or (y1 <= yc < y0):
                    xs.append(x0 + (yc - y0) * (x1 - x0) / (y1 - y0))
            xs.sort()
            for k in range(0, len(xs) - 1, 2):
                for x in range(max(0, int(round(xs[k]))), min(self.w, int(round(xs[k + 1])))):
                    self.blend(x, y, col)

    def line(self, x0, y0, x1, y1, col, width=2.0):
        """a thick line as a quad"""
        dx, dy = x1 - x0, y1 - y0
        l = (dx * dx + dy * dy) ** 0.5 or 1.0
        nx, ny = -dy / l * width / 2, dx / l * width / 2
        self.polygon([(x0 + nx, y0 + ny), (x1 + nx, y1 + ny), (x1 - nx, y1 - ny), (x0 - nx, y0 - ny)], col)

    def capsule(self, cx, cy, half, rad, col, tilt=0.0):
        """a board: a capsule of half length `half` and radius `rad` around (cx, cy), slanted by tilt (dy per dx)"""
        pts = []
        import math
        for i in range(24):
            a = math.pi / 2 + math.pi * i / 23
            pts.append((cx - half + rad * math.cos(a), cy + rad * math.sin(a)))
        for i in range(24):
            a = -math.pi / 2 + math.pi * i / 23
            pts.append((cx + half + rad * math.cos(a), cy + rad * math.sin(a)))
        pts = [(x, y + (x - cx) * tilt) for x, y in pts]
        self.polygon(pts, col)
        return pts

    def text(self, s, x, y, scale, col, outline):
        """the bitmap font, `scale` pixels per dot, with a one-dot-wide outline"""
        for pass_ in (0, 1):
            cx = x
            for chr_ in s:
                rows = FONT[chr_]
                for ry, row in enumerate(rows):
                    for rx, bit in enumerate(row):
                        if bit != "1":
                            continue
                        px, py = cx + rx * scale, y + ry * scale
                        if pass_ == 0:
                            self.polygon([(px - 2, py - 2), (px + scale + 2, py - 2), (px + scale + 2, py + scale + 2),
                                          (px - 2, py + scale + 2)], outline)
                        else:
                            self.polygon([(px, py), (px + scale, py), (px + scale, py + scale), (px, py + scale)], col)
                cx += 6 * scale

    def png(self):
        raw = bytearray()
        for row in self.px:
            raw.append(0)
            for r, g, b, a in row:
                raw += bytes((r, g, b, a))
        def chunk(tag, data):
            return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", self.w, self.h, 8, 6, 0, 0, 0)) +
                chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b""))


def icon(word, rgb):
    c = Canvas(SIZE, SIZE)
    r, g, b = rgb
    edge = (r, g, b, 255)
    # the box: front face, top face, right face (a simple oblique view)
    fx0, fy0, fx1, fy1, ox, oy = 12, 48, 94, 116, 22, -18
    front = [(fx0, fy0), (fx1, fy0), (fx1, fy1), (fx0, fy1)]
    top = [(fx0, fy0), (fx0 + ox, fy0 + oy), (fx1 + ox, fy0 + oy), (fx1, fy0)]
    right = [(fx1, fy0), (fx1 + ox, fy0 + oy), (fx1 + ox, fy1 + oy), (fx1, fy1)]
    c.polygon(top, (r, g, b, 70))
    c.polygon(right, (r, g, b, 95))
    # the board lying on the box's floor (behind the front face)
    pts = c.capsule(60, 100, 30, 8, (40, 40, 48, 255), tilt=-0.18)
    c.capsule(60, 100, 28, 6, (236, 236, 240, 255), tilt=-0.18)
    c.line(36, 104, 84, 95, (40, 40, 48, 160), 1.5)
    c.polygon(front, (r, g, b, 60))
    for poly in (front, top, right):
        for i in range(len(poly)):
            x0, y0 = poly[i]
            x1, y1 = poly[(i + 1) % len(poly)]
            c.line(x0, y0, x1, y1, edge, 2.0)
    # the word
    scale = 4
    w = (6 * len(word) - 1) * scale
    c.text(word, (SIZE - w) // 2, 6, scale, (255, 255, 255, 255), (20, 20, 24, 255))
    return c.png()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=os.path.join(ROOT, "addon", "materials", "entities"))
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    for name, word, rgb in (("gsa1_board_on.png", "ON", (60, 220, 90)), ("gsa1_board_off.png", "OFF", (255, 90, 60))):
        data = icon(word, rgb)
        path = os.path.join(args.out, name)
        with open(path, "wb") as f:
            f.write(data)
        print("%s: %d bytes (%d x %d)" % (os.path.relpath(path, ROOT), len(data), SIZE, SIZE))
    return 0


if __name__ == "__main__":
    sys.exit(main())
