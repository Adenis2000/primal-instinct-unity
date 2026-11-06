#!/usr/bin/env python3
"""Restores the small details the 640x360 area-resample averages away on the raptor sprites, so Look.gd's palette regions
(scripts/core/Look.gd region_of: orange EYE, light BELLY) still exist at the 37x17 px size:
  * eye: the orange pixel cluster of the old-density art (tools/art_src_960) becomes one orange pixel at the matching spot;
  * belly: baked pixels whose source block is mostly belly-coloured become a light tan (v >= 0.72) so the belly region survives.
Runs on assets/sprites/raptor_<stage><pose>.png and portrait_* after tools/rebase_640.py.  Usage: python3 tools/raptor_details.py"""
import colorsys, glob, os
from PIL import Image
SRC = "tools/art_src_960/"
DST = "assets/sprites/"

def hsv(p):
    return colorsys.rgb_to_hsv(p[0] / 255.0, p[1] / 255.0, p[2] / 255.0)

def is_eye(p):
    h, s, v = hsv(p)
    return v >= 0.7 and s >= 0.74 and 15 <= h * 360 <= 55

def is_belly(p):
    h, s, v = hsv(p)
    return v >= 0.7 and 0.25 <= s <= 0.66 and 24 <= h * 360 <= 48

EYE = (236, 150, 40)

def process(name):
    s_path, d_path = SRC + name + ".png", DST + name + ".png"
    if not (os.path.exists(s_path) and os.path.exists(d_path)):
        return None
    src = Image.open(s_path).convert("RGBA")
    dst = Image.open(d_path).convert("RGBA")
    sx, sy = dst.width / src.width, dst.height / src.height
    sp, dp = src.load(), dst.load()
    eyes = [(x, y) for y in range(src.height) for x in range(src.width) if sp[x, y][3] > 127 and is_eye(sp[x, y])]
    n_eye = n_belly = 0
    if eyes:
        cx = sum(x for x, _ in eyes) / len(eyes) + 0.5
        cy = sum(y for _, y in eyes) / len(eyes) + 0.5
        ex, ey = int(cx * sx), int(cy * sy)
        best = None
        for dy in range(-1, 2):
            for dx in range(-1, 2):
                x, y = ex + dx, ey + dy
                if 0 <= x < dst.width and 0 <= y < dst.height and dp[x, y][3] > 127:
                    d = abs(dx) + abs(dy)
                    if best is None or d < best[0]:
                        best = (d, x, y)
        if best:
            dp[best[1], best[2]] = EYE + (255,)
            n_eye = 1
    for y in range(dst.height):
        for x in range(dst.width):
            if dp[x, y][3] < 128 or dp[x, y][:3] == EYE:
                continue
            x0, x1 = int(x / sx), max(int(x / sx) + 1, int((x + 1) / sx))
            y0, y1 = int(y / sy), max(int(y / sy) + 1, int((y + 1) / sy))
            tot = bel = 0
            acc = [0, 0, 0]
            for yy in range(y0, min(y1, src.height)):
                for xx in range(x0, min(x1, src.width)):
                    p = sp[xx, yy]
                    if p[3] > 127:
                        tot += 1
                        if is_belly(p):
                            bel += 1
                            for k in range(3):
                                acc[k] += p[k]
            if tot and bel * 2 >= tot and bel > 0:
                col = [acc[k] // bel for k in range(3)]
                h, s_, v = colorsys.rgb_to_hsv(col[0] / 255.0, col[1] / 255.0, col[2] / 255.0)
                v = max(v, 0.74)
                col = tuple(int(c * 255) for c in colorsys.hsv_to_rgb(h, min(max(s_, 0.3), 0.6), v))
                dp[x, y] = col + (255,)
                n_belly += 1
    dst.save(d_path)
    return n_eye, n_belly

if __name__ == "__main__":
    names = sorted(os.path.basename(f)[:-4] for f in glob.glob(DST + "raptor_*.png") + glob.glob(DST + "portrait_*.png"))
    for n in names:
        r = process(n)
        print(n, r)
