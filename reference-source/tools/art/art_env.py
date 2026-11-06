"""Isometric environment art: ground tiles, water, props, backdrops. Theme-driven (jungle / tundra=icy)."""
import math, random, zlib
import numpy as np
from artlib import *

TW, TH = 76, 38
GW, GH = 12, 7
OX, OY = 385, 48     # screen position of grid corner (0,0) (top corner of the diamond) in the 960x540 viewport

def proj(gx, gy):
    return (OX + (gx - gy) * TW / 2.0, OY + (gx + gy) * TH / 2.0)

THEMES = {
 "jungle": {
  "ground": ramp("#4d8b3a", 5, lo=0.55, hi=1.25),
  "ground_dark": ramp("#2f6a32", 5, lo=0.5, hi=1.2),
  "dirt": ramp("#7b5c3a", 5),
  "water": ramp("#2a78b4", 5, lo=0.55, hi=1.35),
  "rock": ramp("#7c7a6a", 5, lo=0.4, hi=1.35),
  "moss": ramp("#4f8f3a", 5),
  "wood": ramp("#7a5232", 5),
  "leaf": ramp("#2a7a38", 5, lo=0.4, hi=1.3),
  "leaf2": ramp("#3f9a3c", 5, lo=0.4, hi=1.3),
  "bgbase": ramp("#16452a", 5, lo=0.35, hi=1.1),
  "cap": None,
 },
 "cave": {
  "ground": ramp("#5e5870", 5, lo=0.45, hi=1.3),
  "ground_dark": ramp("#403a54", 5, lo=0.45, hi=1.25),
  "dirt": ramp("#6a5a48", 5),
  "water": ["#14304a", "#1f5878", "#2a88a0", "#58c4c8", "#b8f4ee"],
  "rock": ramp("#6e6880", 5, lo=0.4, hi=1.35),
  "moss": ["#1c5a52", "#2a8a7c", "#46c0a0", "#8af0c8", "#e0fff0"],
  "wood": ramp("#8a7a68", 5),
  "leaf": ramp("#4a2a7a", 5, lo=0.4, hi=1.3),
  "leaf2": ramp("#6a3aa0", 5, lo=0.4, hi=1.3),
  "bgbase": ramp("#1c1628", 5, lo=0.3, hi=1.0),
  "cap": ["#8a86a8", "#aaa8c8", "#cac8e0", "#e6e4f2", "#ffffff"],
  "crystal": ramp("#8a52e0", 5, lo=0.4, hi=1.5),
 },
 "tundra": {
  "ground": ["#6f8fb8", "#92b2d6", "#bdd5ec", "#dcebf8", "#f6fbff"],
  "ground_dark": ["#6f8db4", "#8fb0d2", "#b4cfe8", "#d3e5f5", "#eef6fd"],
  "dirt": ramp("#6c5a4c", 5),
  "water": ["#3d78a8", "#5b9bc8", "#86c2e4", "#b8e2f4", "#eefaff"],
  "rock": ramp("#6b7a90", 5, lo=0.4, hi=1.4),
  "moss": ["#8aa0b0", "#a9bfcc", "#cddbe6", "#e8f0f6", "#ffffff"],
  "wood": ramp("#6a5242", 5),
  "leaf": ramp("#24564e", 5, lo=0.4, hi=1.3),
  "leaf2": ramp("#2f6a5c", 5, lo=0.4, hi=1.3),
  "bgbase": ramp("#1c3d4c", 5, lo=0.35, hi=1.1),
  "cap": ["#9bb6d6", "#bcd2ea", "#dbe9f6", "#f1f8fd", "#ffffff"],
 },
}

for _t in THEMES.values():
    for _k, _v in list(_t.items()):
        if _v and isinstance(_v[0], str):
            _t[_k] = [hexc(x) for x in _v]

def diamond_mask(w=TW, h=TH, inset=0.0):
    ys, xs = np.mgrid[0:h, 0:w]
    return (np.abs(xs + 0.5 - w / 2.0) / (w / 2.0) + np.abs(ys + 0.5 - h / 2.0) / (h / 2.0)) <= 1.0 - inset

def top_cap(mask, depth):
    """mask pixels within `depth` (scalar or array) rows of the top of their vertical run"""
    h, w = mask.shape
    run = np.zeros((h, w), np.int32)
    for y in range(h):
        run[y] = np.where(mask[y], (run[y - 1] + 1) if y > 0 else 1, 0)
    return mask & (run <= depth)

def blades(c, mask, rng, n, cols, hmin, hmax, lean=0.3, x0=0, x1=None, y0=0, y1=None):
    x1 = c.w if x1 is None else x1
    y1 = c.h if y1 is None else y1
    for _ in range(n):
        x = rng.randint(x0, x1 - 1)
        y = rng.randint(y0, y1 - 1)
        if not mask[y, x]:
            continue
        h = rng.randint(hmin, hmax)
        ln = rng.uniform(-lean, lean)
        for k in range(h):
            col = cols[min(len(cols) - 1, int(k / max(1, h) * len(cols)))]
            xx = x + int(round(ln * k))
            yy = y - k
            if 0 <= yy < c.h and 0 <= xx < c.w and mask[min(c.h - 1, max(0, y)), x]:
                c.pset(xx, yy, col)

def sparkle(c, mask, rng, n, col, only_dark=False):
    for _ in range(n):
        x, y = rng.randint(0, c.w - 1), rng.randint(0, c.h - 1)
        if mask[y, x]:
            c.pset(x, y, col)

def _cave_ground(c, m, T, rng, v, kind, seed):
    ys, xs = np.mgrid[0:TH, 0:TW]
    n2 = fbm(TW, TH, 8, seed + 5, 2)
    # flagstone seams
    seam = (np.abs(np.sin((xs * 0.21 + ys * 0.52) + n2 * 6.0)) < 0.045) & m
    c.px[seam, 0:3] = (c.px[seam, 0:3] * 0.62).astype(np.uint8)
    seam2 = (np.abs(np.sin((xs * 0.19 - ys * 0.6) + n2 * 5.0 + 2)) < 0.04) & m
    c.px[seam2, 0:3] = (c.px[seam2, 0:3] * 0.7).astype(np.uint8)
    for _ in range(9):
        x, y = rng.randint(8, TW - 9), rng.randint(6, TH - 6)
        if m[y, x]:
            c.pset(x, y, T["rock"][3]); c.pset(x + 1, y, T["rock"][2]); c.pset(x, y + 1, T["rock"][0])
    for _ in range(3):   # glow-moss specks
        x, y = rng.randint(10, TW - 11), rng.randint(8, TH - 8)
        if m[y, x]:
            c.pset(x, y, T["moss"][3]); c.pset(x + 1, y, T["moss"][1])
    if v in (2, 5) or kind == "tall":   # old silk
        for _ in range(3):
            x0, y0 = rng.randint(14, TW - 14), rng.randint(10, TH - 10)
            for k in range(rng.randint(6, 12)):
                xx, yy = x0 + k, y0 + (k // 3)
                if 0 <= xx < TW and 0 <= yy < TH and m[yy, xx]:
                    c.pset(xx, yy, T["cap"][3])
    if kind == "tall":    # 'tall' tiles = fungus beds
        blades(c, m, rng, 34, [T["moss"][1], T["moss"][2]], 2, 4, 0.2)

def ground_tile(theme, v, kind="ground"):
    T = THEMES[theme]
    rng = random.Random(zlib.crc32(('%s%s%d' % (theme, kind, v)).encode()))
    seed = rng.randint(0, 99999)
    c = Canvas(TW, TH)
    m = diamond_mask()
    base = T["ground_dark"] if kind == "tall" else T["ground"]
    lo, hi = (0.25, 0.7) if theme == "jungle" else (0.35, 0.85)
    if kind == "tall" and theme == "tundra":
        lo, hi = 0.3, 0.75
    fill_noise_ramp(c, m, base, cell=9, seed=seed, lo=lo, hi=hi, octaves=3)
    ys, xs = np.mgrid[0:TH, 0:TW]
    if theme == "jungle":
        r = T["ground"]
        # dirt patches on some variants
        if v in (1, 4) or kind == "tall":
            n2 = fbm(TW, TH, 7, seed + 9, 2)
            dm = m & (n2 > 0.62 if kind != "tall" else n2 > 0.7)
            fill_noise_ramp_local(c, dm, T["dirt"], seed + 3, 0.2, 0.7)
        gcols = [T["ground"][1], T["ground"][3], T["ground"][4]]
        blades(c, m, rng, 70, [T["ground_dark"][1], T["ground"][3]], 2, 4, 0.5)
        blades(c, m, rng, 28, [T["ground"][2], T["ground"][4]], 2, 3, 0.4)
        if v == 2:   # flowers
            for _ in range(6):
                x, y = rng.randint(8, TW - 9), rng.randint(6, TH - 6)
                if m[y, x]:
                    col = rng.choice([(250, 240, 220), (250, 190, 80), (240, 130, 170)])
                    c.pset(x, y, col); c.pset(x + 1, y, col); c.pset(x, y - 1, (60, 120, 50))
        if v == 3:   # pebbles & leaves
            for _ in range(5):
                x, y = rng.randint(8, TW - 9), rng.randint(6, TH - 6)
                if m[y, x]:
                    c.pset(x, y, T["rock"][3]); c.pset(x + 1, y, T["rock"][2]); c.pset(x, y + 1, T["rock"][0])
            for _ in range(4):
                x, y = rng.randint(8, TW - 9), rng.randint(6, TH - 6)
                if m[y, x]:
                    c.pset(x, y, (200, 140, 50)); c.pset(x + 1, y, (170, 100, 40))
        if kind == "tall":
            blades(c, m, rng, 40, [T["ground_dark"][0], T["leaf"][2]], 3, 5, 0.3)
    elif theme == "cave":
        _cave_ground(c, m, T, rng, v, kind, seed)
    else:
        # snow: dune shading, sparkles, wind ripples, bare patches
        n2 = fbm(TW, TH, 12, seed + 4, 2)
        ripple = (np.sin((xs * 0.35 + ys * 0.9) + n2 * 9) > 0.93) & m
        c.px[ripple, 0:3] = np.array(T["ground"][4], np.uint8)
        sparkle(c, m, rng, 14, (255, 255, 255))
        sparkle(c, m, rng, 12, T["ground"][0])
        if v in (1, 4) or kind == "tall":
            dm = m & (fbm(TW, TH, 8, seed + 6, 2) > (0.66 if kind != "tall" else 0.62))
            fill_noise_ramp_local(c, dm, T["dirt"] if v != 4 else [hexc(x) for x in ["#5d7fa0", "#6f93b4", "#86abc8", "#a2c4dc", "#c4dcec"]], seed + 3, 0.15, 0.75)
        if v == 3:   # footprints / twigs
            for _ in range(4):
                x, y = rng.randint(10, TW - 11), rng.randint(8, TH - 8)
                if m[y, x]:
                    for dx, dy in [(0, 0), (1, 0), (0, 1), (1, 1)]:
                        c.pset(x + dx, y + dy, T["ground"][1])
            for _ in range(3):
                x, y = rng.randint(10, TW - 11), rng.randint(8, TH - 8)
                if m[y, x]:
                    c.pset(x, y, T["wood"][1]); c.pset(x + 1, y - 1, T["wood"][2]); c.pset(x + 2, y - 1, T["wood"][1])
        if v == 2:   # frozen puddle sheen
            pm = ellipse_mask(TW, TH, rng.randint(24, 50), rng.randint(14, 24), 10, 4) & m
            c.shade(pm, T["water"][1:], blur=1, contrast=0.3, rim=0.1)
        if kind == "tall":
            blades(c, m, rng, 30, [T["wood"][1], T["ground"][3]], 3, 5, 0.3)
    return c

def fill_noise_ramp_local(c, mask, rmp, seed, lo, hi):
    n = fbm(c.w, c.h, 5, seed, 2)
    v = np.clip((n - 0.3) / 0.4, 0, 1) * (hi - lo) + lo
    f = v * (len(rmp) - 1)
    ys, xs = np.mgrid[0:c.h, 0:c.w]
    f = f + BAYER[ys % 4, xs % 4] * 0.9
    idx = np.clip(np.round(f).astype(int), 0, len(rmp) - 1)
    col = np.array(rmp, np.uint8)[idx]
    c.px[mask, 0:3] = col[mask]
    c.px[mask, 3] = 255

def water_tile(theme, frame, v=0):
    T = THEMES[theme]
    rng = random.Random(77 + v)
    c = Canvas(TW, TH)
    m = diamond_mask()
    ys, xs = np.mgrid[0:TH, 0:TW]
    ice = theme == "tundra"
    seed = 40 + v
    n = fbm(TW, TH, 10, seed, 3)
    fill_noise_ramp(c, m, T["water"], cell=10, seed=seed, lo=0.15 if not ice else 0.35, hi=0.6 if not ice else 0.8)
    if not ice:
        # animated ripples: sine bands warped by noise, shifting with frame
        ph = frame * 2.1
        band = np.sin((xs * 0.28 - ys * 0.75) * 1.0 + n * 7 + ph)
        c.px[m & (band > 0.86), 0:3] = np.array(T["water"][3], np.uint8)
        band2 = np.sin((xs * 0.2 + ys * 0.9) + n * 5 - ph * 0.8 + 2)
        c.px[m & (band2 > 0.93), 0:3] = np.array(T["water"][4], np.uint8)
        for i in range(4):
            x = (rng.randint(8, TW - 8) + frame * 3 * (1 if i % 2 else -1)) % (TW - 12) + 6
            y = rng.randint(7, TH - 7)
            for dx in range(-2, 3):
                if m[y, min(TW - 1, max(0, x + dx))]:
                    c.pset(x + dx, y, T["water"][4] if abs(dx) < 2 else T["water"][3])
    else:
        # frozen water: pale ice with cracks and moving glints
        for i in range(3):
            x, y = rng.randint(10, TW - 10), rng.randint(6, TH - 6)
            for k in range(rng.randint(8, 16)):
                if 0 <= x < TW and 0 <= y < TH and m[y, x]:
                    c.pset(x, y, T["water"][4] if k % 3 else T["water"][0])
                x += rng.choice([1, 1, 2]) * rng.choice([-1, 1]); y += rng.choice([0, 1, -1])
        gx = (frame * 17 + 9) % TW
        for k in range(6):
            x = (gx + k * 11) % TW
            y = (k * 7 + 5 + frame * 3) % TH
            if m[y, x]:
                c.pset(x, y, (255, 255, 255)); c.pset(x + 1, y, (220, 245, 255))
    # shoreline: darker rim so water tiles read as sunken
    rim = m & ~diamond_mask(inset=0.09)
    c.px[rim, 0:3] = (c.px[rim, 0:3] * 0.78).astype(np.uint8)
    return c

# ------------------------------------------------------------------ props (bottom of image = bottom corner of tile)
def _lib_rock(theme, rng, w, h, ox, oy, rx, ry, rmp):
    pts = []
    n = 9
    for i in range(n):
        a = i / n * 2 * math.pi
        k = rng.uniform(0.78, 1.1)
        pts.append((ox + math.cos(a) * rx * k, oy + math.sin(a) * ry * k))
    return blob_mask(w, h, pts)

def boulders(theme, v):
    T = THEMES[theme]
    rng = random.Random(200 + v * 7 + (1 if theme == "tundra" else 0))
    w, h = TW, 64
    c = Canvas(w, h)
    cx, cy = 38, h - 19
    # contact shadow
    sh = ellipse_mask(w, h, cx, cy + 3, 28, 10)
    c.flat(sh, (16, 22, 30), 255)
    c.px[sh, 3] = 0
    specs = [(cx - 12, cy - 4, 17, 13), (cx + 12, cy - 2, 15, 12), (cx - 1, cy - 14, 14, 15)]
    if v % 2:
        specs = [(cx - 10, cy - 2, 16, 12), (cx + 10, cy - 6, 17, 16)]
    shadow = Canvas(w, h)
    for (x, y, rx, ry) in sorted(specs, key=lambda s: s[1]):
        m = _lib_rock(theme, rng, w, h, x, y - ry * 0.4, rx, ry * 1.05, T["rock"])
        n = fbm(w, h, 5, 300 + v + int(x), 3)
        c.shade(m, T["rock"], blur=3, contrast=1.15, tex=n, tex_amt=0.55)
        # cracks
        for _ in range(2):
            px_, py_ = int(x + rng.uniform(-rx * .4, rx * .4)), int(y - ry * 0.4 + rng.uniform(-ry * .3, ry * .5))
            for k in range(rng.randint(3, 6)):
                if 0 <= px_ < w and 0 <= py_ < h and m[py_, px_]:
                    c.pset(px_, py_, T["rock"][0])
                px_ += rng.choice([-1, 0, 1]); py_ += 1
        capm = top_cap(m, 3 + (n * 5).astype(int)) & (n > 0.28 if theme == "jungle" else (n > 0.52 if theme == "cave" else n > 0.0))
        cm = T["cap"] if theme == "tundra" else T["moss"]
        if theme == "tundra":
            capm = top_cap(m, 4 + (n * 6).astype(int))
        c.shade(capm, cm, blur=2, contrast=0.9, rim=0.15)
    c.outline(tint=(16, 14, 36), strength=0.7)
    if theme == "jungle":
        for _ in range(7):
            x = rng.randint(cx - 24, cx + 24); y = rng.randint(cy - 12, cy + 6)
            if c.px[y, x, 3] and rng.random() < 0.6:
                for k in range(rng.randint(2, 5)):
                    c.pset(x, y + k, T["leaf"][2])
    return c

def log_prop(theme, v):
    T = THEMES[theme]
    rng = random.Random(500 + v)
    w, h = TW, 52
    c = Canvas(w, h)
    cx, cy = 38, h - 19
    c.flat(ellipse_mask(w, h, cx, cy + 2, 30, 10), (14, 20, 28), 0)
    # log runs along iso axis (down-right), slight tilt
    a = (cx - 24, cy - 8 + (4 if v % 2 else 0))
    b = (cx + 22, cy + 8 - (4 if v % 2 else 0))
    if v % 2:
        a, b = (cx - 22, cy + 8), (cx + 24, cy - 6)
    m = tube_mask(w, h, [a, b], [15, 15], smooth=False)
    n = fbm(w, h, 4, 600 + v, 2)
    c.shade(m, T["wood"], blur=3, contrast=1.1, tex=n, tex_amt=0.4, light=(-0.2, -0.95))
    # bark grooves
    dx, dy = b[0] - a[0], b[1] - a[1]
    L = math.hypot(dx, dy)
    ux, uy = dx / L, dy / L
    for off in (-4, -1, 3, 5):
        for t in range(0, int(L), 1):
            if rng.random() < 0.75:
                x = int(a[0] + ux * t - uy * off * 0.2); y = int(a[1] + uy * t + off * 0.9 - 1)
                if 0 <= x < w and 0 <= y < h and m[y, x]:
                    c.pset(x, y, T["wood"][0] if off != 3 else T["wood"][3])
    # cut end ring
    ex, ey = a if v % 2 == 0 else b
    ring = ellipse_mask(w, h, ex, ey, 5, 7.5, 20)
    c.shade(ring, ramp("#b48a58", 5), blur=2, contrast=0.6, rim=0.2)
    inner = ellipse_mask(w, h, ex, ey, 2.5, 4, 20)
    c.flat(inner, (150, 108, 66))
    c.pset(int(ex), int(ey), (110, 72, 44))
    # top cover: moss (jungle) / snow (tundra)
    cm = T["moss"] if theme == "jungle" else T["cap"]
    capm = top_cap(m, 3 + (n * 4).astype(int)) & (n > 0.3 if theme == "jungle" else n > -1)
    c.shade(capm, cm, blur=2, contrast=0.9, rim=0.12)
    c.outline(strength=0.7)
    if theme == "jungle":   # mushrooms
        for mx, my in [(cx + 4, cy - 10), (cx - 8, cy - 7)]:
            c.flat(ellipse_mask(w, h, mx, my, 3, 2), (230, 90, 70)); c.pset(mx, my - 1, (255, 230, 220)); c.flat(poly_mask(w, h, [(mx - .5, my), (mx + 1, my), (mx + 1, my + 3), (mx - .5, my + 3)]), (240, 230, 200))
    return c

def ruin_block(theme, v):
    T = THEMES[theme]
    rng = random.Random(900 + v)
    w, h = TW, 76
    c = Canvas(w, h)
    cx, by = 38, h
    cw, ch = 20, 30 + (v % 3) * 8   # half width, height
    top_y = by - 19 - ch
    hw, hh = cw, cw / 2
    cxy = (cx, by - 19)
    # faces: left, right, top
    lf = poly_mask(w, h, [(cx - hw, top_y), (cx, top_y + hh), (cx, by - 19 + hh), (cx - hw, by - 19)])
    rf = poly_mask(w, h, [(cx + hw, top_y), (cx, top_y + hh), (cx, by - 19 + hh), (cx + hw, by - 19)])
    tp = poly_mask(w, h, [(cx, top_y - hh), (cx + hw, top_y), (cx, top_y + hh), (cx - hw, top_y)])
    n = fbm(w, h, 4, 910 + v, 3)
    rk = T["rock"]
    c.shade(lf, rk[:4], flat=0.55, tex=n, tex_amt=0.9)
    c.shade(rf, rk[:3], flat=0.35, tex=n, tex_amt=0.9)
    c.shade(tp, rk[1:], flat=0.62, tex=n, tex_amt=0.8)
    # brick lines
    ys, xs = np.mgrid[0:h, 0:w]
    for face, col in ((lf, rk[0]), (rf, rk[0])):
        rows = (ys % 8 == 0)
        c.px[face & rows, 0:3] = np.array(col, np.uint8)
        cols = ((xs + (ys // 8) * 5) % 10 == 0)
        c.px[face & cols & ~rows, 0:3] = np.array(col, np.uint8)
    # top highlight edge
    edge = tp & ~np.roll(np.roll(tp, 1, 0), 1, 1)
    # cap
    capm = (tp & (n > 0.35)) | (top_cap(lf | rf, 4 + (n * 8).astype(int)) & (n > (0.45 if theme == "jungle" else 0.0)))
    c.shade(capm, T["moss"] if theme == "jungle" else T["cap"], blur=2, contrast=0.8, rim=0.1)
    if theme == "jungle":  # hanging vines
        for _ in range(5):
            x = rng.randint(int(cx - hw), int(cx + hw) - 1)
            y = int(top_y + abs(x - cx) / 2 + 2)
            for k in range(rng.randint(5, 16)):
                if 0 <= y + k < h and c.px[y + k, x, 3]:
                    c.pset(x, y + k, T["leaf"][1 + (k % 2)])
    c.outline(strength=0.75)
    return c

def pine(theme, size=1.0, snow=True, seed=1, w=None):
    """A conifer; also used for the background forests."""
    T = THEMES[theme]
    rng = random.Random(seed)
    W = int((60 if w is None else w) * size)
    H = int(96 * size)
    c = Canvas(W, H)
    cx = W // 2
    trunk = tube_mask(W, H, [(cx, H - 2), (cx, H - 20 * size)], [5 * size, 4 * size], smooth=False)
    c.shade(trunk, T["wood"], blur=1, contrast=1.0)
    tiers = 5
    for i in range(tiers):
        t = i / (tiers - 1)
        top = H - 20 * size - (1 - t) * 0 - (i + 1) * 14.5 * size
        bot = top + 28 * size - i * 1.5 * size
        half = (26 - (tiers - 1 - i) * 3.2 * 1.0) * size * (0.55 + 0.45 * (i / (tiers - 1)) ** 0.8) + 3 * size
        half = (8 + i * 4.8) * size
        pts = [(cx, top)]
        # jagged left edge
        n = 5
        for k in range(1, n + 1):
            f = k / n
            pts.append((cx - half * f - rng.uniform(0, 2 * size) + (1.5 * size if k % 2 else 0), top + (bot - top) * f - (3 * size if k % 2 else 0)))
        pts.append((cx, bot - 1 * size))
        for k in range(n, 0, -1):
            f = k / n
            pts.append((cx + half * f + rng.uniform(0, 2 * size) - (1.5 * size if k % 2 else 0), top + (bot - top) * f - (3 * size if k % 2 else 0)))
        m = poly_mask(W, H, pts)
        nz = fbm(W, H, 4, seed + i, 2)
        c.shade(m, T["leaf"], blur=2, contrast=1.2, tex=nz, tex_amt=0.5, light=(-0.6, -0.7))
        if snow:
            sm = top_cap(m, (2 + (nz * 7 * size)).astype(int)) | (m & (nz > 0.72))
            sm &= m
            c.shade(sm, T["cap"] if T["cap"] else T["moss"], blur=2, contrast=0.8, rim=0.1)
    c.outline(strength=0.7)
    return c

def pine_prop(theme, v):
    p = pine(theme, 0.8, snow=(theme == "tundra"), seed=1300 + v, w=64)
    w, h = TW, 90
    c = Canvas(w, h)
    c.flat(ellipse_mask(w, h, 38, h - 17, 22, 7), (0, 0, 0), 0)
    c.paste(p, 38 - p.w // 2, h - p.h - 10)
    return c

def fern_bush(theme, v):
    T = THEMES[theme]
    rng = random.Random(1500 + v)
    w, h = TW, 62
    c = Canvas(w, h)
    cx, cy = 38, h - 17
    for layer in range(3):
        rm = T["leaf"] if layer % 2 == 0 else T["leaf2"]
        for i in range(7 + layer * 2):
            a = rng.uniform(-80, 80) + (layer - 1) * 8
            L = rng.uniform(16, 30) - layer * 3
            ang = math.radians(a)
            tip = (cx + math.sin(ang) * L * 0.9, cy - 6 - math.cos(ang) * L * 0.9 - layer * 2)
            mid = (cx + math.sin(ang) * L * 0.5 + (4 if a > 0 else -4), cy - 6 - math.cos(ang) * L * 0.9 - 6)
            m = tube_mask(w, h, [(cx + rng.uniform(-3, 3), cy), mid, tip], [8, 7, 1.5])
            c.shade(m, rm, blur=2, contrast=1.2, light=(-0.5, -0.8))
    c.outline(strength=0.6)
    return c

def ice_crystals(theme, v):
    T = THEMES[theme]
    rng = random.Random(1700 + v)
    w, h = TW, 72
    c = Canvas(w, h)
    cx, cy = 38, h - 19
    rk = T.get("crystal", T["water"])
    specs = [(cx - 12, cy + 2, 8, 28), (cx + 10, cy, 9, 36), (cx - 1, cy - 4, 10, 44)]
    for (x, y, hw, hh) in sorted(specs, key=lambda s: s[1]):
        x += rng.randint(-2, 2)
        top = y - hh
        lf = poly_mask(w, h, [(x - hw, y - 8), (x - hw + 2, top + 8), (x, top), (x, y + 3)])
        rf = poly_mask(w, h, [(x + hw, y - 8), (x + hw - 2, top + 8), (x, top), (x, y + 3)])
        c.shade(lf, rk, flat=0.62, dither=False)
        c.shade(rf, rk, flat=0.32, dither=False)
        # bright facet streak
        for k in range(int(hh * 0.5)):
            c.pset(int(x - hw * 0.5), int(y - 12 - k), rk[4])
        for k in range(int(hh * 0.3)):
            c.pset(int(x + hw * 0.3), int(y - 6 - k), rk[3])
        c.pset(int(x), int(top + 1), (255, 255, 255))
    c.outline(tint=(20, 40, 80) if theme != "cave" else (24, 10, 50), strength=0.65)
    return c

def tall_grass(theme, v, front=False):
    T = THEMES[theme]
    rng = random.Random(2100 + v * 13 + (5 if front else 0))
    w, h = TW, 52
    c = Canvas(w, h)
    m_d = diamond_mask(w, 38)
    dm = np.zeros((h, w), bool)
    dm[h - 38:, :] = m_d
    if theme == "cave":
        cols = [ramp("#1a4a44", 5, lo=.45, hi=1.2), ramp("#2a8a7c", 5, lo=.45, hi=1.3), ramp("#6ad8b0", 5, lo=.5, hi=1.2)]
    elif theme == "jungle":
        cols = [ramp("#1a5a2c", 5, lo=.45, hi=1.2), ramp("#2e8a38", 5, lo=.45, hi=1.3), ramp("#5cb348", 5, lo=.5, hi=1.2)]
    else:
        cols = [[hexc(x) for x in r] for r in (["#4a5a52", "#6a7a6a", "#8a947a", "#a8ad8c", "#d8d8c0"], ["#6b6a50", "#8c8a64", "#aaa57a", "#c8c294", "#f0eedc"], ["#8a8a78", "#a8a890", "#cbc8ae", "#e6e4d0", "#ffffff"])]
    nblades = 120 if not front else 56
    ys0 = h - 38
    items = []
    for _ in range(nblades):
        while True:
            x = rng.randint(6, w - 7)
            y = rng.randint(ys0 + 2, h - 3)
            if dm[y, x] and (not front or y > h - 22):
                break
        items.append((y, x))
    items.sort()
    for (y, x) in items:
        L = rng.randint(10, 24) if not front else rng.randint(5, 10)
        L = int(L * (0.7 + 0.3 * (y - ys0) / 38))
        lean = rng.uniform(-0.45, 0.45)
        curve = rng.uniform(-0.02, 0.02)
        ci = rng.choice([0, 1, 1, 2]) if y > ys0 + 12 else rng.choice([0, 1, 2])
        for k in range(L):
            f = k / L
            xx = x + lean * k + curve * k * k
            yy = y - k
            shade_i = min(4, int(1 + f * 3.6))
            col = cols[ci][shade_i if f > 0.1 else 0]
            for dx in ((0, 1) if f < 0.6 else (0,)):
                c.pset(int(round(xx + dx)), yy, col if dx == 0 else cols[ci][max(0, shade_i - 2)])
        if rng.random() < 0.12 and not front:
            c.pset(int(x + lean * L), y - L - 1, (230, 200, 120) if theme == "jungle" else (255, 255, 255))
    c.outline(strength=0.55, tint=(10, 30, 20) if theme == "jungle" else (30, 40, 70))
    return c
