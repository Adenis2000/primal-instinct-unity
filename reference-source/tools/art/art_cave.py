"""Secret-cave art: cave backdrop/foreground, stalagmites, cocoons, the secret entrance sprites, spiders, cave card art."""
import math, random
import numpy as np
from artlib import *
from art_env import *
import art_bg

SW, SH = 960, 540

# ------------------------------------------------------------------ props
def stalagmites(theme, v):
    T = THEMES[theme]
    rng = random.Random(3100 + v * 5)
    w, h = TW, 70
    c = Canvas(w, h)
    cx, cy = 38, h - 19
    c.flat(ellipse_mask(w, h, cx, cy + 2, 26, 8), (8, 6, 16), 0)
    specs = [(cx - 13, cy + 1, 8, 26), (cx + 11, cy, 9, 34), (cx - 1, cy - 3, 11, 46)]
    if v % 2:
        specs = [(cx - 8, cy + 1, 10, 38), (cx + 13, cy - 1, 7, 22)]
    rk = T["rock"]
    for (x, y, hw, hh) in sorted(specs, key=lambda s: s[1]):
        top = y - hh + rng.randint(-2, 2)
        pts = [(x - hw, y), (x - hw * 0.55, y - hh * 0.45), (x - 1, top), (x + 1, top), (x + hw * 0.6, y - hh * 0.4), (x + hw, y), (x, y + 4)]
        m = poly_mask(w, h, pts)
        n = fbm(w, h, 5, 3200 + v + int(x), 3)
        c.shade(m, rk, blur=2, contrast=1.25, tex=n, tex_amt=0.6, light=(-0.8, -0.3))
        # drip-line highlights
        for k in range(int(hh * 0.6)):
            yy = int(y - 4 - k)
            if 0 <= yy < h and m[yy, int(x - hw * 0.3 * (1 - k / (hh * 0.6)))]:
                c.pset(int(x - hw * 0.3 * (1 - k / (hh * 0.6))), yy, rk[4])
        if rng.random() < 0.6:   # glow-moss at the foot
            fm = ellipse_mask(w, h, x, y + 1, hw * 0.8, 3) & m
            c.shade(fm, T["moss"], blur=1, contrast=0.9, rim=0.1)
    c.outline(strength=0.7, tint=(12, 8, 30))
    return c

def cocoon(theme, v):
    T = THEMES[theme]
    rng = random.Random(3300 + v)
    w, h = TW, 66
    c = Canvas(w, h)
    cx, cy = 38, h - 20
    c.flat(ellipse_mask(w, h, cx, cy + 3, 22, 7), (8, 6, 16), 0)
    cap = T["cap"]
    # silk strands anchoring it to the ground
    for sx in (-22, -10, 12, 24):
        for k in range(10):
            c.pset(int(cx + sx * (1 - k / 14.0)), int(cy + 4 - k * 0.8), cap[1])
    bodies = [(cx, cy - 12, 12, 19)] if v % 2 == 0 else [(cx - 9, cy - 8, 9, 14), (cx + 10, cy - 11, 10, 17)]
    for (x, y, rx, ry) in bodies:
        m = ellipse_mask(w, h, x, y, rx, ry)
        c.shade(m, cap, blur=2, contrast=1.1, tex=fbm(w, h, 4, 3300 + v + int(x), 2), tex_amt=0.5, light=(-0.6, -0.6))
        for k in range(-ry + 3, ry - 2, 4):   # wrapping bands
            for dx in range(-rx + 2, rx - 1):
                xx, yy = int(x + dx), int(y + k + dx * 0.2)
                if 0 <= yy < h and m[yy, xx]:
                    c.pset(xx, yy, cap[0])
        if v % 2 == 0:   # something wriggles inside
            c.flat(ellipse_mask(w, h, x + 1, y - 2, 3, 6) & m, (98, 74, 120))
    c.outline(strength=0.65, tint=(30, 24, 52))
    return c

# ------------------------------------------------------------------ the secret entrance
def secret_crack():
    """Barely-there cracked stone on one tile: a faint dark seam, a lighter edge and a draught of dust. No glow."""
    c = Canvas(TW, TH)
    m = diamond_mask(inset=0.18)
    rng = random.Random(777)
    x, y = 24, 22
    pts = []
    for k in range(26):
        pts.append((x, y))
        x += rng.choice([1, 1, 2]); y += rng.choice([-1, 0, 0, 1])
    for (px_, py_) in pts:
        if 0 <= px_ < TW and 0 <= py_ < TH and m[py_, px_]:
            c.pset(px_, py_, (22, 18, 34), 150)
            if 0 <= py_ + 1 < TH and m[py_ + 1, px_]:
                c.pset(px_, py_ + 1, (170, 164, 190), 55)
    for bx, by in ((pts[8][0] + 1, pts[8][1] - 2), (pts[15][0], pts[15][1] + 2)):
        for dx, dy in ((0, 0), (1, 0), (-1, 1), (0, -1)):
            if m[by + dy, bx + dx]:
                c.pset(bx + dx, by + dy, (24, 20, 36), 110)
    return c

def secret_rock():
    """The boulder that seals the entrance (falls away in the reveal animation)."""
    c = boulders_one()
    return c

def boulders_one():
    T = THEMES["cave"]
    rng = random.Random(4242)
    w, h = TW, 54
    c = Canvas(w, h)
    cx, cy = 38, h - 19
    sh = ellipse_mask(w, h, cx, cy + 3, 26, 9)
    c.flat(sh, (8, 6, 16), 0)
    for (x, y, rx, ry) in sorted([(cx - 10, cy - 3, 15, 11), (cx + 11, cy - 4, 13, 10), (cx, cy - 11, 12, 12)], key=lambda s: s[1]):
        pts = []
        for i in range(9):
            a = i / 9 * 2 * math.pi
            k = rng.uniform(0.8, 1.1)
            pts.append((x + math.cos(a) * rx * k, y - ry * 0.4 + math.sin(a) * ry * 1.05 * k))
        m = blob_mask(w, h, pts)
        c.shade(m, T["rock"], blur=3, contrast=1.15, tex=fbm(w, h, 5, 300 + int(x), 3), tex_amt=0.55)
    c.outline(tint=(12, 8, 30), strength=0.7)
    return c

def secret_hole():
    """Open cave mouth in the floor: dark pit, rim stones and a pale glow-moss lip. The warm glow is drawn live."""
    T = THEMES["cave"]
    c = Canvas(TW, TH)
    rng = random.Random(555)
    outer = ellipse_mask(TW, TH, 38, 19, 26, 11)
    c.shade(outer, T["rock"], blur=1, contrast=1.0, flat=0.55)
    pit = ellipse_mask(TW, TH, 38, 20, 20, 8)
    c.flat(pit, (6, 4, 14))
    inner = ellipse_mask(TW, TH, 38, 22, 14, 5)
    c.flat(inner, (18, 12, 36))
    for i in range(14):   # rim stones
        a = i / 14 * 2 * math.pi
        x, y = 38 + math.cos(a) * 22, 19 + math.sin(a) * 9.4
        s = ellipse_mask(TW, TH, x, y, 3.2, 2.2)
        c.shade(s, T["rock"], blur=1, contrast=1.1, rim=0.25)
    for i in range(10):   # moss
        a = rng.uniform(0, 2 * math.pi)
        x, y = 38 + math.cos(a) * 20, 19 + math.sin(a) * 8
        c.pset(int(x), int(y), T["moss"][3]); c.pset(int(x) + 1, int(y), T["moss"][2])
    c.outline(strength=0.6, tint=(12, 8, 30))
    return c

# ------------------------------------------------------------------ backdrop
def _ceiling_drips(c, rng, variant):
    T = THEMES["cave"]
    for i in range(34):
        x = rng.randint(-10, SW + 10)
        hgt = rng.randint(24, 96) if i % 3 else rng.randint(80, 150)
        wd = rng.randint(10, 22)
        pts = [(x - wd, -4), (x + wd, -4), (x + 1, hgt), (x - 1, hgt)]
        m = poly_mask(c.w, c.h, pts)
        c.shade(m, T["rock"], blur=2, contrast=1.3, flat=0.35, tex=fbm(c.w, c.h, 6, 90 + i, 2), tex_amt=0.5, light=(-0.7, -0.3))
        if rng.random() < 0.35:
            c.pset(x, hgt + 1, T["water"][3]); c.pset(x, hgt + 3, T["water"][2])

def cave_background(variant):
    T = THEMES["cave"]
    rng = random.Random(6000 + variant * 31)
    c = Canvas(SW, SH)
    full = np.ones((SH, SW), bool)
    fill_noise_ramp(c, full, T["bgbase"], cell=22, seed=700 + variant, lo=0.08, hi=0.5, octaves=3)
    plateau = poly_mask(SW, SH, [proj(-0.75, -0.75), proj(GW + 0.75, -0.75), proj(GW + 0.75, GH + 0.75), proj(-0.75, GH + 0.75)])
    if not art_bg.SLAB:
        plateau = np.zeros((SH, SW), bool)
    ys, xs = np.mgrid[0:SH, 0:SW]
    # distant glowing pools & crystal clusters on the cave wall
    for _ in range(9):
        x, y = rng.randint(30, SW - 30), rng.randint(20, 210)
        cr = art_bg_crystal(rng)
        c.paste(cr, x - cr.w // 2, y - cr.h // 2)
    _ceiling_drips(c, rng, variant)
    # rock pillars/stalagmites outside the plateau
    items = []
    for _ in range(90):
        x, y = rng.randint(-20, SW + 20), rng.randint(180, SH + 60)
        if plateau[min(SH - 1, max(0, y - 20)), min(SW - 1, max(0, x))] or (y > 230 and any(plateau[min(SH - 1, max(0, y - dy)), min(SW - 1, max(0, x + dx))] for dy in (10, 30, 60) for dx in (-30, 0, 30))):
            continue
        items.append((y, x))
    items.sort()
    lib = [stalagmites("cave", i) for i in range(3)] * 2 + [cocoon("cave", 0)]
    for (y, x) in items:
        s = lib[rng.randint(0, len(lib) - 1)]
        c.paste(s, x - s.w // 2, y - s.h + 10)
    if art_bg.SLAB:
        # plateau floor + cliffs
        fill_noise_ramp(c, plateau, T["ground_dark"], cell=10, seed=950 + variant, lo=0.12, hi=0.55)
        Lc, Bc, Rc = proj(-0.75, GH + 0.75), proj(GW + 0.75, GH + 0.75), proj(GW + 0.75, -0.75)
        art_bg.cliff_face(c, Lc, Bc, 30, T["rock"], T["moss"], 71 + variant, True)
        art_bg.cliff_face(c, Bc, Rc, 30, T["rock"], T["moss"], 83 + variant, False)
        # underground stream falling into a pool on the left face
        fx = int(Lc[0] + (Bc[0] - Lc[0]) * (0.22 + 0.08 * variant)); fy = int(Lc[1] + (Bc[1] - Lc[1]) * (0.22 + 0.08 * variant))
        fall = poly_mask(SW, SH, [(fx - 5, fy - 2), (fx + 5, fy + 2), (fx + 5, fy + 40), (fx - 5, fy + 36)])
        fn = fbm(SW, SH, 3, 17 + variant, 2)
        c.shade(fall, T["water"], flat=0.7, tex=np.sin(xs * 0.9 + fn * 5) * 0.5 + 0.5, tex_amt=0.9, dither=True)
        c.shade(ellipse_mask(SW, SH, fx, fy + 38, 20, 7), T["water"], flat=0.5, tex=fn, tex_amt=0.8)
    # lit by the entrance glow: soft violet vignette + heavy darkness at the corners
    d = np.sqrt(((xs - 480) / 560.0) ** 2 + ((ys - 250) / 340.0) ** 2)
    v = np.clip((d - 0.5) * 1.15, 0, 0.8)
    tintc = np.array((4, 2, 12), np.float32)
    for i in range(3):
        c.px[:, :, i] = (c.px[:, :, i] * (1 - v) + tintc[i] * v).astype(np.uint8)
    c.px[:, :, 3] = 255
    return c

def art_bg_crystal(rng):
    T = THEMES["cave"]
    w, h = 26, 34
    c = Canvas(w, h)
    for i in range(3):
        x = 6 + i * 7 + rng.randint(-1, 1); top = rng.randint(2, 12); y = h - 3
        lf = poly_mask(w, h, [(x - 3, y), (x - 2, top + 5), (x, top), (x, y)])
        rf = poly_mask(w, h, [(x + 3, y), (x + 2, top + 5), (x, top), (x, y)])
        c.shade(lf, T["crystal"], flat=0.62, dither=False); c.shade(rf, T["crystal"], flat=0.3, dither=False)
        c.pset(x, top + 1, (240, 220, 255))
    c.outline(strength=0.5, tint=(20, 8, 44))
    return c

def cave_foreground(variant):
    T = THEMES["cave"]
    rng = random.Random(8100 + variant * 17)
    c = Canvas(SW, SH)
    plateau = poly_mask(SW, SH, [proj(-0.9, -0.9), proj(GW + 0.9, -0.9), proj(GW + 0.9, GH + 0.9), proj(-0.9, GH + 0.9)])
    lib = [stalagmites("cave", i) for i in range(2)]
    for _ in range(12):
        side = rng.choice(["l", "r", "b"])
        if side == "l":
            x, y = rng.randint(-10, 50), rng.randint(200, SH + 30)
        elif side == "r":
            x, y = rng.randint(SW - 50, SW + 10), rng.randint(180, SH + 30)
        else:
            x, y = rng.randint(0, SW), rng.randint(SH - 4, SH + 40)
        if plateau[min(SH - 1, max(0, y - 10)), min(SW - 1, max(0, x))]:
            continue
        s = lib[rng.randint(0, 1)]
        c.paste(s, x - s.w // 2, y - s.h + 10)
    a = c.px[:, :, 3] > 0
    c.px[a, 0:3] = (c.px[a, 0:3] * 0.7).astype(np.uint8)
    return c

# ------------------------------------------------------------------ spiders (face right; _b = seen from behind: no eyes/fangs)
def spider(kind, back=False, seed=1):
    cfg = {
        "cave_spider": dict(W=38, H=28, abd=(11, 9), body="#4a3a5a", mark="#8a5ad0", legs=1.0, eyes=(255, 80, 80)),
        "web_spitter": dict(W=42, H=32, abd=(14, 11), body="#3a4a3a", mark="#c8e060", legs=1.0, eyes=(255, 230, 90)),
        "tomb_widow": dict(W=60, H=46, abd=(19, 15), body="#1c1424", mark="#e03030", legs=1.25, eyes=(255, 60, 60)),
    }[kind]
    W, H = cfg["W"], cfg["H"]
    rng = random.Random(seed + len(kind))
    body = ramp(cfg["body"], 5, lo=0.3, hi=1.7)
    c = Canvas(W, H)
    cx, cy = W * 0.42, H * 0.58
    leg = ramp("#2a2230", 5, lo=0.4, hi=1.4)
    L = cfg["legs"]
    for side in (-1, 1):
        for k in range(4):
            ox = cx + (k - 1.5) * 4.2 * L
            spread = (k - 1.5) * 0.55
            kx = ox + side * 3 + spread * 7
            ky = cy - 8 * L + (0 if side < 0 else 2)
            tip = (ox + spread * 15 + (3 if side > 0 else -1), cy + 9 * L + (side > 0) * 2)
            mid = (kx + spread * 9, ky - 3 * L)
            m = tube_mask(W, H, [(ox, cy - 1), mid, tip], [1.9 * L, 1.5 * L, 0.9], False)
            c.shade(m, leg, flat=0.5 if side < 0 else 0.72, dither=False)
    ax, ay = cfg["abd"]
    abd = ellipse_mask(W, H, cx - ax * 0.35, cy - 1, ax, ay)
    c.shade(abd, body, blur=3, contrast=1.45, tex=fbm(W, H, 4, 50 + seed, 2), tex_amt=0.4)
    mk = ramp(cfg["mark"], 5, lo=0.6, hi=1.3)
    if kind == "tomb_widow":   # red hourglass
        hx, hy = int(cx - ax * 0.35), int(cy - 1)
        for dy in range(-6, 7):
            wd = abs(dy) // 2 + 1
            for dx in range(-wd, wd + 1):
                if 0 <= hy + dy < H and abd[hy + dy, hx + dx] and not back:
                    c.pset(hx + dx, hy + dy, mk[3])
        if back:
            for dy in range(-6, 7):
                c.pset(hx, hy + dy, mk[2])
    else:
        for i in range(3):
            xx = int(cx - ax * 0.35 + (i - 1) * 4)
            mm = abd & (np.abs(np.mgrid[0:H, 0:W][1] - xx) < 1) & ellipse_mask(W, H, cx - ax * 0.35, cy - 1, ax * 0.9, ay * 0.7)
            c.px[mm, 0:3] = np.array(mk[2 if i != 1 else 3], np.uint8)
    head = ellipse_mask(W, H, cx + ax * 0.75, cy, ax * 0.5, ay * 0.55)
    c.shade(head, ramp(cfg["body"], 5, lo=0.4, hi=1.9), blur=1, contrast=1.3)
    if not back:
        hx0, hy0 = cx + ax * 0.95, cy - ay * 0.2
        for i, (dx, dy) in enumerate(((0, 0), (2, -1), (2, 1), (0.5, 1.8))):
            c.pset(int(hx0 + dx), int(hy0 + dy), cfg["eyes"])
        # fangs
        fx_, fy_ = int(cx + ax * 1.15), int(cy + ay * 0.3)
        c.pset(fx_, fy_, (230, 230, 220)); c.pset(fx_, fy_ + 1, (230, 230, 220)); c.pset(fx_ - 1, fy_ + 1, (200, 190, 190))
    if kind == "web_spitter":
        sp = ellipse_mask(W, H, cx - ax * 1.15, cy + 1, 3.2, 2.6)
        c.shade(sp, ramp("#e8e8f0", 5, lo=0.5, hi=1.2), blur=1)
    c.outline(strength=0.72, tint=(10, 6, 24))
    return c

def build_spiders():
    out = {}
    for k, sd in (("cave_spider", 3), ("web_spitter", 5), ("tomb_widow", 7)):
        out[k] = spider(k, False, sd)
        out[k + "_b"] = spider(k, True, sd)
    return out

# ------------------------------------------------------------------ cave card art (92x54)
def card_art(kind, seed):
    import art_ui as U
    rng = random.Random(seed)
    pal = {"venom": ("#0c1a0c", "#1c5a24", "#8aff4a"), "web": ("#14102a", "#3a3a6a", "#d8d8ff"),
           "plate": ("#140c20", "#4a2a6a", "#b080ff"), "widow": ("#1a060a", "#6a1020", "#ff4a4a")}[kind]
    c = U._bg(pal, seed)
    W, H = U.CARD_W, U.CARD_H
    if kind == "web":
        cx, cy = 46, 27
        for a in range(0, 360, 30):
            for r in range(2, 40):
                x, y = int(cx + math.cos(math.radians(a)) * r * 1.3), int(cy + math.sin(math.radians(a)) * r * 0.9)
                if 0 <= x < W and 0 <= y < H:
                    c.pset(x, y, (230, 230, 255) if r % 5 else (170, 170, 220))
        for r in (8, 15, 22, 29):
            for t in np.linspace(0, 2 * math.pi, 120):
                x, y = int(cx + math.cos(t) * r * 1.3), int(cy + math.sin(t) * r * 0.9)
                if 0 <= x < W and 0 <= y < H:
                    c.pset(x, y, (200, 200, 245))
    elif kind == "venom":
        for fx_ in (34, 58):
            m = poly_mask(W, H, [(fx_ - 6, 6), (fx_ + 6, 6), (fx_ + (2 if fx_ < 46 else -2), 44)])
            c.shade(m, ramp("#e8e8d8", 5, lo=0.5, hi=1.3), blur=1, contrast=1.1)
        for i in range(14):
            x, y = rng.randint(20, 72), rng.randint(30, 52)
            c.flat(ellipse_mask(W, H, x, y, rng.uniform(1, 2.4), rng.uniform(2, 4)), (130, 255, 80))
        c.outline(strength=0.6, tint=(6, 20, 6))
    elif kind == "plate":
        for i in range(4):
            m = ellipse_mask(W, H, 46, 12 + i * 11, 30 - i * 3, 7)
            c.shade(m, ramp("#8a60c8", 5, lo=0.4, hi=1.5), blur=1, contrast=1.3, rim=0.3)
        c.outline(strength=0.6, tint=(12, 6, 24))
    else:
        sp = spider("tomb_widow", False, 7)
        c.paste(sp, (W - sp.w) // 2 + 4, (H - sp.h) // 2 + 4)
        for k in range(5):
            x = 14 + k * 4
            c.pset(x, 6 + k * 3, (255, 90, 90)); c.pset(x, 7 + k * 3, (255, 90, 90))
    return c

def gate_sprites():
    return {"gate_" + t: art_bg.make_gate(t) for t in ("jungle", "tundra", "cave")}
