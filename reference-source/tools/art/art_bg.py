"""Battle backdrops: dense foliage / frosted pine forest, plateau with cliffs, gate; foreground overlay."""
import math, random
import numpy as np
from artlib import *
from art_env import *

SW, SH = 960, 540
SLAB = False   # the board is drawn on continuous terrain now (BattleBoard draws the surroundings): no baked plateau / cliffs

def make_clump(rmp, w, h, rng, n=7, hi_dabs=True):
    c = Canvas(w, h)
    blobs = []
    for _ in range(n):
        rx = rng.uniform(w * 0.18, w * 0.32)
        ry = rng.uniform(h * 0.2, h * 0.34)
        x = rng.uniform(rx + 1, w - rx - 1)
        y = rng.uniform(ry + 1, h - ry - 1)
        blobs.append((y, x, rx, ry))
    for (y, x, rx, ry) in sorted(blobs):
        pts = []
        for i in range(8):
            a = i / 8 * 2 * math.pi
            k = rng.uniform(0.8, 1.15)
            pts.append((x + math.cos(a) * rx * k, y + math.sin(a) * ry * k))
        m = blob_mask(w, h, pts)
        c.shade(m, rmp, blur=2, contrast=1.3, light=(-0.55, -0.8), rim=0.45)
    if hi_dabs:
        for _ in range(n * 3):
            x, y = rng.randint(2, w - 3), rng.randint(2, h - 3)
            if c.px[y, x, 3] and not c.px[y - 1, x, 3] == 0:
                c.pset(x, y, rmp[-1]); c.pset(x + 1, y, rmp[-2])
    return c

def tree_jungle(rmps, rng, scale=1.0):
    W, H = int(110 * scale), int(150 * scale)
    c = Canvas(W, H)
    cx = W // 2
    trunk = tube_mask(W, H, [(cx, H - 2), (cx + rng.randint(-4, 4), H * 0.55), (cx + rng.randint(-6, 6), H * 0.3)], [11 * scale, 8 * scale, 5 * scale])
    wood = ramp("#5a4030", 5)
    c.shade(trunk, wood, blur=3, tex=fbm(W, H, 4, rng.randint(0, 999), 2), tex_amt=0.5, light=(-0.7, -0.4))
    # canopy of clumps
    lib = [make_clump(rmps[rng.randint(0, len(rmps) - 1)], 44, 34, rng) for _ in range(5)]
    spots = []
    for i in range(16):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(0.0, 1.0) ** 0.6
        spots.append((cx + math.cos(a) * r * 38 * scale - 22, H * 0.34 + math.sin(a) * r * 30 * scale - 17))
    for (x, y) in sorted(spots, key=lambda p: p[1]):
        c.paste(lib[rng.randint(0, 4)], int(x), int(y))
    c.outline(strength=0.55)
    return c

def cliff_face(c, p0, p1, height, rock, accent, seed, left_lit):
    """Draw a vertical stone wall below the edge p0->p1 (screen coords)."""
    rng = random.Random(seed)
    (x0, y0), (x1, y1) = p0, p1
    poly = [(x0, y0), (x1, y1), (x1, y1 + height), (x0, y0 + height)]
    m = poly_mask(c.w, c.h, poly)
    n = fbm(c.w, c.h, 5, seed, 3)
    c.shade(m, rock[:4] if left_lit else rock[:3], flat=0.58 if left_lit else 0.4, tex=n, tex_amt=1.0)
    ys, xs = np.mgrid[0:c.h, 0:c.w]
    # stone block courses following the slope
    slope = (y1 - y0) / (x1 - x0)
    row = ((ys - slope * (xs - x0)) - y0)
    rows = (np.floor(row).astype(int) % 9 == 0) & m
    c.px[rows, 0:3] = (c.px[rows, 0:3] * 0.7).astype(np.uint8)
    cols = ((xs + (np.floor(row / 9).astype(int)) * 7) % 14 == 0) & m & ~rows
    c.px[cols, 0:3] = (c.px[cols, 0:3] * 0.78).astype(np.uint8)
    # lip highlight along the top edge
    lip = m & (row < 2)
    c.px[lip, 0:3] = np.array(rock[4], np.uint8)
    # accent growth (moss / snow-ice) from the top, ragged
    d = 3 + (n * 12).astype(int)
    acc = m & (row < d) & (n > 0.38)
    c.shade(acc, accent, blur=2, contrast=0.8, rim=0.15)
    # bottom shadow
    bot = m & (row > height - 5)
    c.px[bot, 0:3] = (c.px[bot, 0:3] * 0.55).astype(np.uint8)
    return m

def background(theme, variant):
    if theme == "cave":
        import art_cave
        return art_cave.cave_background(variant)
    T = THEMES[theme]
    rng = random.Random(4000 + variant * 31 + (7 if theme == "tundra" else 0))
    c = Canvas(SW, SH)
    full = np.ones((SH, SW), bool)
    fill_noise_ramp(c, full, T["bgbase"], cell=24, seed=500 + variant, lo=0.1, hi=0.55, octaves=3)
    rmps = [T["leaf"], T["leaf2"]]
    L = (proj(-0.9, GH + 0.9), proj(GW + 0.9, GH + 0.9), proj(GW + 0.9, -0.9), proj(-0.9, -0.9))
    plateau = poly_mask(SW, SH, [proj(-0.75, -0.75), proj(GW + 0.75, -0.75), proj(GW + 0.75, GH + 0.75), proj(-0.75, GH + 0.75)])
    if not SLAB:
        plateau = np.zeros((SH, SW), bool)
    cx0, cy0 = 480, 228
    # forest library
    if theme == "jungle":
        lib = [tree_jungle(rmps, rng, rng.uniform(0.9, 1.3)) for _ in range(7)]
    else:
        lib = [pine(theme, rng.uniform(0.95, 1.5), snow=True, seed=rng.randint(0, 9999)) for _ in range(9)]
    clumps = [make_clump(rmps[i % 2], 46, 36, rng, 8) for i in range(6)] if theme == "jungle" else []
    items = []
    blocked = plateau.copy()
    for dy in range(0, 40, 2):
        blocked |= np.roll(plateau, dy, axis=0)
    def in_blocked(x, y, w=40, h=60):
        for ry in range(0, h + 1, 10):
            for rx in (-w // 2, 0, w // 2):
                xx, yy = min(SW - 1, max(0, x + rx)), min(SH - 1, max(0, y - ry))
                if blocked[yy, xx]:
                    return True
        return False
    # ring of items outside the plateau, dense
    for _ in range(520):
        x = rng.randint(-30, SW + 30)
        y = rng.randint(-10, SH + 80)
        ix = (x - cx0) / 1.0
        # skip if the base falls inside the plateau (+ margin) region
        if y >= 232 and in_blocked(x, y, 70, 110):
            continue
        if y < 232 and plateau[min(SH - 1, max(0, y)), min(SW - 1, max(0, x))]:
            continue
        items.append((y, x, rng.randint(0, len(lib) - 1) if rng.random() < 0.55 else -1 - rng.randint(0, 5)))
    items.sort()
    back = [it for it in items if it[0] < 232]
    front = [it for it in items if it[0] >= 232]

    def stamp(its):
        for (y, x, k) in its:
            if k >= 0:
                s = lib[k]
                c.paste(s, x - s.w // 2, y - s.h)
            elif clumps:
                s = clumps[(-k - 1) % len(clumps)]
                c.paste(s, x - s.w // 2, y - s.h + 12)
            else:
                s = lib[(-k - 1) % len(lib)]
                c.paste(s, x - s.w // 2, y - s.h)
    # dense under-canopy bushes first
    if theme == "jungle":
        for _ in range(260):
            x, y = rng.randint(-20, SW + 20), rng.randint(0, SH + 30)
            if blocked[min(SH - 1, y), min(SW - 1, max(0, x))]:
                continue
            s = clumps[rng.randint(0, 5)]
            c.paste(s, x - 23, y - 30)
    stamp(back)
    ys, xs = np.mgrid[0:SH, 0:SW]
    if SLAB:
        # plateau
        fill_noise_ramp(c, plateau, T["ground_dark"], cell=10, seed=900 + variant, lo=0.15, hi=0.6)
        # plateau ring: lighter rim tuft pixels
        ys, xs = np.mgrid[0:SH, 0:SW]
        # cliffs under SW and SE edges
        Lc, Bc, Rc = proj(-0.75, GH + 0.75), proj(GW + 0.75, GH + 0.75), proj(GW + 0.75, -0.75)
        hgt = 30
        rock = T["rock"]
        accent = T["moss"] if theme == "jungle" else T["cap"]
        m1 = cliff_face(c, Lc, (Bc[0], Bc[1]), hgt, rock, accent, 71 + variant, True)
        m2 = cliff_face(c, (Bc[0], Bc[1]), Rc, hgt, rock, accent, 83 + variant, False)
        # waterfall / frozen fall on the left face
        fx = int(Lc[0] + (Bc[0] - Lc[0]) * (0.22 + 0.08 * variant))
        fy = int(Lc[1] + (Bc[1] - Lc[1]) * (0.22 + 0.08 * variant))
        wcols = T["water"]
        fall = poly_mask(SW, SH, [(fx - 7, fy - 2), (fx + 7, fy + 2), (fx + 7, fy + hgt + 10), (fx - 7, fy + hgt + 6)])
        fn = fbm(SW, SH, 3, 17 + variant, 2)
        c.shade(fall, wcols, flat=0.7, tex=np.sin(xs * 0.9 + fn * 5) * 0.5 + 0.5, tex_amt=0.9, dither=True)
        pool = ellipse_mask(SW, SH, fx, fy + hgt + 8, 20, 7)
        c.shade(pool, wcols, flat=0.5, tex=fn, tex_amt=0.8)
        for i in range(10):
            c.pset(fx - 14 + i * 3, fy + hgt + 8 + (i % 3) - 1, wcols[4])
        # grass tufts / frost on plateau edge
        for _ in range(160):
            x, y = rng.randint(0, SW - 1), rng.randint(0, SH - 1)
            if plateau[y, x] and not poly_mask(1, 1, [(0, 0), (1, 0), (1, 1)]).any() or False:
                pass
        # gate on the NE edge
        # (exit gates are drawn by the board itself now, see BattleBoard / ExitGen)
        # ruined stones & rubble around plateau edge (jungle) / ice shards (tundra)
        for _ in range(14):
            gx_, gy_ = rng.uniform(-0.7, GW + 0.7), rng.choice([-0.75, GH + 0.75]) if rng.random() < 0.5 else rng.uniform(-0.7, GH + 0.7)
            if rng.random() < 0.5:
                px_, py_ = proj(rng.choice([-0.8, GW + 0.8]), rng.uniform(0, GH))
            else:
                px_, py_ = proj(rng.uniform(0, GW), rng.choice([-0.8, GH + 0.8]))
            s = boulders(theme, rng.randint(0, 1))
            sc = Canvas(s.w // 2 + 4, s.h // 2 + 2)
            for yy in range(sc.h):
                for xx in range(sc.w):
                    sc.px[yy, xx] = s.px[min(s.h - 1, yy * 2), min(s.w - 1, xx * 2)]
            c.paste(sc, int(px_ - sc.w / 2), int(py_ - sc.h + 6))
    stamp(front)
    # low undergrowth hugging the cliffs (short sprites that can't hide the board)
    low = [make_clump(rmps[i % 2], 46, 36, rng, 8) for i in range(4)] if theme == "jungle" else [pine(theme, 0.55, snow=True, seed=rng.randint(0, 999)) for _ in range(4)]
    cand = []
    for _ in range(420):
        x, y = rng.randint(-20, SW + 20), rng.randint(236, SH + 20)
        if not in_blocked(x, y, 40, 30):
            cand.append((y, x))
    for (y, x) in sorted(cand):
        sp = low[rng.randint(0, 3)]
        c.paste(sp, x - sp.w // 2, y - sp.h + (10 if theme == "jungle" else 0))
    # vignette
    d = np.sqrt(((xs - 480) / 600.0) ** 2 + ((ys - 250) / 380.0) ** 2)
    v = np.clip((d - 0.62) * 1.0, 0, 0.55)
    tintc = np.array((6, 10, 24) if theme == "tundra" else (4, 12, 8), np.float32)
    for i in range(3):
        c.px[:, :, i] = (c.px[:, :, i] * (1 - v) + tintc[i] * v).astype(np.uint8)
    c.px[:, :, 3] = 255
    return c

def make_gate(theme):
    T = THEMES[theme]
    w, h = 96, 64
    c = Canvas(w, h)
    wood = T["wood"]
    # back glow
    glow = poly_mask(w, h, [(22, 56), (30, 14), (66, 14), (74, 56)])
    c.shade(glow, ramp({"jungle": "#d8f0a0", "tundra": "#bfe4ff", "cave": "#c8a0ff"}[theme], 5, lo=.6, hi=1.1), flat=0.55, dither=True)
    for px_, hh in ((16, 52), (72, 52)):
        post = tube_mask(w, h, [(px_ + 4, h - 4), (px_ + 4, h - hh)], [9, 8], smooth=False)
        c.shade(post, wood, blur=2, contrast=1.0, light=(-0.7, -0.3))
    beam = poly_mask(w, h, [(10, 14), (86, 14), (88, 22), (8, 22)])
    c.shade(beam, wood, blur=2, contrast=1.0, light=(-0.2, -0.9))
    for k in range(5):
        x = 28 + k * 9
        pl = tube_mask(w, h, [(x, h - 4), (x, 26)], [5, 5], smooth=False)
        c.shade(pl, wood, blur=1, contrast=0.9, flat=0.35 if k % 2 else 0.5, dither=False)
    if theme == "tundra":
        cap = poly_mask(w, h, [(6, 14), (90, 14), (86, 8), (12, 8)])
        c.shade(cap, T["cap"], blur=1, rim=0.1)
    c.outline(strength=0.7)
    return c

def foreground(theme, variant):
    """Transparent overlay with near-camera foliage on the extreme corners/edges (never covers the board)."""
    if theme == "cave":
        import art_cave
        return art_cave.cave_foreground(variant)
    T = THEMES[theme]
    rng = random.Random(8000 + variant * 17 + (3 if theme == "tundra" else 0))
    c = Canvas(SW, SH)
    plateau = poly_mask(SW, SH, [proj(-0.9, -0.9), proj(GW + 0.9, -0.9), proj(GW + 0.9, GH + 0.9), proj(-0.9, GH + 0.9)])
    rmps = [T["leaf"], T["leaf2"]]
    if theme == "jungle":
        lib = [make_clump(rmps[i % 2], 56, 42, rng, 9) for i in range(6)]
    else:
        lib = [pine(theme, rng.uniform(1.5, 2.1), snow=True, seed=rng.randint(0, 999)) for _ in range(5)]
    spots = []
    for _ in range(40):
        side = rng.choice(["l", "r", "b", "tl", "tr"])
        if side == "l":
            x, y = rng.randint(-20, 60), rng.randint(60, SH + 30)
        elif side == "r":
            x, y = rng.randint(SW - 60, SW + 20), rng.randint(40, SH + 30)
        elif side == "b":
            x, y = rng.randint(0, SW), rng.randint(SH - 8, SH + 40)
        elif side == "tl":
            x, y = rng.randint(-10, 120), rng.randint(0, 40)
        else:
            x, y = rng.randint(SW - 200, SW + 10), rng.randint(0, 30)
        if plateau[min(SH - 1, max(0, y - 10)), min(SW - 1, max(0, x))]:
            continue
        spots.append((y, x))
    for (y, x) in sorted(spots):
        s = lib[rng.randint(0, len(lib) - 1)]
        c.paste(s, x - s.w // 2, y - s.h + (10 if theme == "jungle" else 0))
    # darken fg slightly (depth of field feel)
    a = c.px[:, :, 3] > 0
    c.px[a, 0:3] = (c.px[a, 0:3] * 0.82).astype(np.uint8)
    return c
