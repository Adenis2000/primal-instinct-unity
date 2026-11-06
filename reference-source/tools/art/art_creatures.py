"""Creature sprites (pixel-art, shaded at native resolution). Each is drawn facing right (toward SE / NE on the
iso grid) and `back=True` draws the 'facing away' (NE/NW) variant: face details are hidden, tail/rump in front."""
import math, random
import numpy as np
from artlib import *

def P(c, m, rmp, **kw):
    c.shade(m, rmp, **kw)

def sc(pts, s, ox=0, oy=0):
    return [(x * s + ox, y * s + oy) for x, y in pts]

def fluff(c, rng, col, amount, only_top=True):
    """downy/feathery edge pixels"""
    a = c.px[:, :, 3] > 0
    ys, xs = np.nonzero(a)
    for _ in range(int(len(ys) * amount)):
        i = rng.randint(0, len(ys) - 1)
        x, y = xs[i], ys[i]
        if y > 0 and not a[y - 1, x]:
            c.pset(x, y - 1, col)
            if rng.random() < 0.4:
                c.pset(x + rng.choice([-1, 1]), y - 1, col)

RAPTOR_FORMS = {
    "baby":     dict(s=0.66, body="#a9c068", belly="#f0e6b8", stripe="#6f9244", crest="#e8c050", head_k=1.35, fluff=True, eye_k=1.5, w=48, h=38),
    "juvenile": dict(s=0.84, body="#6cae70", belly="#e8e2b0", stripe="#3f7a52", crest="#f09a38", head_k=1.15, fluff=True, eye_k=1.2, w=60, h=46),
    "adult":    dict(s=1.0,  body="#468c90", belly="#d6dcc0", stripe="#2a5668", crest="#f27a2a", head_k=1.0, fluff=False, eye_k=1.0, w=72, h=54),
    "compy":    dict(s=0.78, body="#b59a5c", belly="#efe2b6", stripe="#6e5532", crest="#8c6a3a", head_k=1.2, fluff=True, eye_k=1.3, w=60, h=46),
    "spitter":  dict(s=0.8, body="#7f9a52", belly="#f0e3a0", stripe="#3e5a30", crest="#e4502c", head_k=1.15, fluff=False, eye_k=1.4, w=60, h=46),
    "prime":    dict(s=1.16, body="#3b5a82", belly="#cfd6d0", stripe="#1f2f52", crest="#ff7a1e", head_k=1.0, fluff=False, eye_k=1.0, w=82, h=62),
}

def raptor(form, back=False, seed=1):
    F = RAPTOR_FORMS[form]
    s = F["s"]
    W, H = F["w"], F["h"]
    rng = random.Random(seed)
    c = Canvas(W, H)
    body = ramp(F["body"], 5, lo=0.42, hi=1.3)
    belly = ramp(F["belly"], 5, lo=0.5, hi=1.15)
    dark = ramp(F["stripe"], 5, lo=0.45, hi=1.3)
    crest = ramp(F["crest"], 5, lo=0.5, hi=1.25)
    far = ramp(F["body"], 5, lo=0.25, hi=0.9)
    oy = H - 47 * s - 2          # feet land at bottom
    ox = 2

    def T(p):
        return (p[0] * s + ox, p[1] * s + oy)

    def tm(pts, widths, smooth=True):
        return tube_mask(W, H, [T(p) for p in pts], [w * s for w in widths], smooth)

    def em(cx, cy, rx, ry, ang=0):
        return ellipse_mask(W, H, cx * s + ox, cy * s + oy, rx * s, ry * s, ang)

    hk = F["head_k"]
    # far leg
    P(c, em(27, 28, 6, 8, -20), far, blur=2)
    P(c, tm([(27, 32), (24, 39), (27, 44)], [4.2, 3.2, 2.6]), far, blur=1)
    P(c, tm([(26, 44.5), (33, 45.5)], [3, 2], False), far, blur=1)
    # tail (behind body unless back view)
    tail_pts = [(22, 25), (12, 26.5), (4, 24), (-1, 19)] if not back else [(22, 26), (13, 31), (6, 36), (1, 41)]
    tail = tm(tail_pts, [10, 7, 4, 1.4])
    tail_layer = lambda: (P(c, tail, body, blur=2, contrast=1.15), None)
    if not back:
        tail_layer()
    # body
    bm = em(30, 25, 15.5, 8.8, -10)
    P(c, bm, body, blur=3, contrast=1.15, tex=fbm(W, H, 3, seed + 3, 2), tex_amt=0.25)
    if not back:
        bel = bm & em(31.5, 28.5, 13, 5, -8) & ~em(30, 20, 14, 5, -10)
        P(c, bel, belly, blur=2, contrast=0.8, rim=0.1)
    # stripes across back
    ys, xs = np.mgrid[0:H, 0:W]
    for k in range(5):
        x0 = (20 + k * 4.2) * s + ox
        band = np.abs((xs - x0) + (ys - oy - 22 * s) * 0.45) < max(0.8, 1.1 * s)
        band &= bm & (ys < oy + 27 * s)
        c.px[band, 0:3] = np.array(dark[1 + (k % 2)], np.uint8)
    # near leg
    thigh = em(32, 30, 7.2, 9.5, -12)
    P(c, thigh, body, blur=3, contrast=1.2)
    shin = tm([(32, 34), (29, 40), (33, 44)], [5, 3.6, 2.8])
    P(c, shin, dark, blur=1, contrast=1.0)
    foot = tm([(31, 44.5), (40, 45.5)], [3.4, 2.4], False)
    P(c, foot, dark, blur=1)
    # toes + sickle claw
    for dx in (0, 2.5, 5):
        c.pset(int((40 + dx * 0.6) * s + ox), int(46 * s + oy), (232, 226, 200))
    claw = poly_mask(W, H, [T((33, 42)), T((38, 40)), T((37, 43.5)), T((34, 45))])
    c.flat(claw, (244, 238, 214))
    c.pset(int(T((38, 40))[0]), int(T((38, 40))[1]), (255, 255, 255))
    # arm
    arm = tm([(40, 27), (44, 31), (47, 33)], [3.2, 2.4, 1.8])
    P(c, arm, body, blur=1)
    for dx, dy in ((47, 33), (48.2, 32.4), (47.6, 34.2)):
        c.pset(int(dx * s + ox), int(dy * s + oy), (240, 236, 214))
    # neck + head
    neck = tm([(39, 23), (43, 16), (46, 11)], [9, 7, 6])
    P(c, neck, body, blur=2, contrast=1.1)
    hs = hk
    hx, hy = 47, 9
    def HP(pts):
        return [(hx + (x - hx) * hs, hy + (y - hy) * hs) for x, y in pts]
    head_pts = HP([(43, 7), (47, 3.5), (53, 3.5), (60, 7.5), (61, 10), (57, 13), (51, 13.5), (46, 13)])
    hm = poly_mask(W, H, [T(p) for p in spline(head_pts, 8, closed=True)])
    hrmp = body if not back else ramp(F["body"], 5, lo=0.3, hi=1.05)
    P(c, hm, hrmp, blur=2, contrast=1.2)
    if not back:
        jaw = hm & poly_mask(W, H, [T(p) for p in HP([(48, 11), (61, 10.5), (58, 14), (48, 14)])])
        P(c, jaw, belly, blur=1, contrast=0.6, rim=0.0)
        # mouth
        for t in np.linspace(0, 1, 14):
            x, y = T(HP([(60.5, 10.2)])[0]); x2, y2 = T(HP([(50.5, 11.6)])[0])
            c.pset(int(x + (x2 - x) * t), int(y + (y2 - y) * t), dark[0])
        for i in range(3):
            x, y = T(HP([(59 - i * 2.6, 10.8)])[0])
            c.pset(int(x), int(y) + 1, (250, 248, 235))
        ex, ey = T(HP([(52.2, 7.2)])[0])
        ek = F["eye_k"]
        ew = max(1, int(round(1.6 * s * ek + 0.4)))
        for dx in range(ew + 1):
            for dy in range(ew + (1 if ek > 1.2 else 0)):
                c.pset(int(ex) + dx, int(ey) + dy, (255, 240, 170))
        c.pset(int(ex) + ew, int(ey) + 0, (20, 10, 20))
        c.pset(int(ex) + ew, int(ey) + 1 if ek > 1.2 else int(ey), (20, 10, 20))
        nx, ny = T(HP([(59.5, 7.6)])[0])
        c.pset(int(nx), int(ny), dark[0])
        # brow shadow
        for dx in range(ew + 2):
            c.pset(int(ex) + dx - 1, int(ey) - 1, dark[1])
    # crest feathers
    for i, (a, b, wd) in enumerate([((44, 6), (37, 2.5), 1.9), ((45, 4.8), (40, 0), 1.7), ((43.5, 8), (36, 7), 1.7)]):
        fm = tm([HP([a])[0], ((a[0] + b[0]) / 2, min(a[1], b[1]) - 2), b], [wd, wd * .8, .8])
        P(c, fm, crest, blur=1, contrast=1.1)
    # arm feathers & tail fan
    tipx, tipy = T((0, 19) if not back else (1, 41))
    for k in range(4):
        fm = tm([(2 + k, 20 + k * 1.2) if not back else (3 + k, 38 + k), (-3 + k * 0.5, 16 + k * 2.2) if not back else (0, 41 + k * 1.2)], [2.2, 1.0], False)
        P(c, fm, crest if k % 2 == 0 else dark, blur=1)
    if back:
        tail_layer()
    if F["fluff"]:
        fluff(c, rng, belly[3], 0.12)
    c.outline(strength=0.72, tint=(14, 12, 32))
    return c

def build_all_raptors():
    out = {}
    for f in RAPTOR_FORMS:
        if f in ("compy", "spitter"):
            continue
        out["raptor_" + f] = raptor(f)
        out["raptor_%s_b" % f] = raptor(f, back=True)
    return out

# ====================================================================== quadrupeds & others
def _canvas(w, h):
    return Canvas(w, h)

def quad(W, H, rmp, belly, dark, body, head, legs, tail, ears=(), seed=1, back=False, fur=0.3, lw=(6, 4.5), eye=None, extra=None, snout=None, tex_cell=3):
    """Generic four-legged animal. body=(cx,cy,rx,ry,ang); head=list of polygon pts; legs=[(hipx,hipy,footx,footy,front)]"""
    rng = random.Random(seed)
    c = Canvas(W, H)
    far = [lg for lg in legs if not lg[4]]
    near = [lg for lg in legs if lg[4]]
    dk = [tuple(int(v * 0.62) for v in col) for col in rmp]
    def leg(lg, r):
        hx, hy, fx, fy, _ = lg
        m = tube_mask(W, H, [(hx, hy), ((hx + fx) / 2 + 1, (hy + fy) / 2), (fx, fy)], [lw[0], lw[1], lw[1] - 0.8])
        P(c, m, r, blur=1, contrast=1.1)
        foot = tube_mask(W, H, [(fx - 1, fy), (fx + 2.5, fy)], [2.5, 2.0], False)
        P(c, foot, dark, blur=1)
    for lg in far:
        leg(lg, dk)
    tail_m = tube_mask(W, H, tail["pts"], tail["w"])
    if not back:
        P(c, tail_m, tail.get("rmp", rmp), blur=2, contrast=1.1)
    bm = ellipse_mask(W, H, *body[:4], body[4])
    tex = fbm(W, H, tex_cell, seed + 7, 2)
    P(c, bm, rmp, blur=3, contrast=1.2, tex=tex, tex_amt=fur)
    if belly is not None:
        bel = bm & ellipse_mask(W, H, body[0], body[1] + body[3] * 0.62, body[2] * 0.88, body[3] * 0.5, body[4] * 0.5) & ~ellipse_mask(W, H, body[0], body[1] - body[3] * 0.7, body[2], body[3], body[4])
        P(c, bel, belly, blur=2, contrast=0.8, rim=0.0)
    for lg in near:
        leg(lg, rmp)
    hm = poly_mask(W, H, spline(head, 8, closed=True))
    hr = rmp if not back else [tuple(int(v * 0.8) for v in col) for col in rmp]
    for e in ears:
        em_ = poly_mask(W, H, e)
        P(c, em_, dark if not back else hr, blur=1, contrast=1.0)
    P(c, hm, hr, blur=2, contrast=1.2, tex=tex, tex_amt=fur * 0.6)
    if snout is not None and not back:
        P(c, hm & poly_mask(W, H, snout), belly or rmp, blur=1, contrast=0.7, rim=0.0)
    if back:
        P(c, tail_m, tail.get("rmp", rmp), blur=2, contrast=1.1)
    if eye is not None and not back:
        ex, ey = eye
        c.pset(ex, ey, (255, 236, 150)); c.pset(ex + 1, ey, (20, 10, 14)); c.pset(ex, ey - 1, dark[1])
    if extra:
        extra(c, bm, hm, back)
    if fur > 0.2:
        fluff(c, rng, rmp[3], 0.10)
    c.outline(strength=0.72, tint=(14, 10, 30))
    return c

def dire_pup(back=False):
    W, H = 58, 42
    g = ramp("#7c828c", 5, lo=0.35, hi=1.3)
    bel = ramp("#d8d8d0", 5, lo=0.5, hi=1.1)
    dk = ramp("#3a3e4a", 5)
    def extra(c, bm, hm, back_):
        if not back_:
            for x, y in ((50, 20), (51, 20), (52, 20)):
                pass
            c.pset(53, 23, (250, 250, 245)); c.pset(55, 23, (250, 250, 245))
            c.flat(ellipse_mask(W, H, 57.5, 20, 1.5, 1.2), (20, 14, 20))
        # dark saddle
        sad = bm & ellipse_mask(W, H, 26, 14, 12, 4)
        c.blend(sad, dk[1], 0.45)
    return quad(W, H, g, bel, dk,
        body=(27, 21, 15, 9, -4),
        head=[(40, 15), (46, 12), (52, 13), (58, 19), (57, 23), (50, 25), (43, 24), (39, 21)],
        legs=[(14, 26, 12, 38, False), (36, 26, 38, 38, False), (18, 27, 16, 39, True), (34, 27, 35, 39, True)],
        tail=dict(pts=[(13, 18), (6, 19), (2, 25)], w=[8, 7, 3]),
        ears=[[(43, 14), (45, 6), (49, 13)], [(48, 13), (52, 6), (54, 14)]],
        back=back, eye=(51, 17), extra=extra, snout=[(52, 19), (58, 19), (57, 24), (50, 25)], seed=11, fur=0.45)

def smilodon(back=False):
    W, H = 80, 58
    g = ramp("#c89a5a", 5, lo=0.4, hi=1.3)
    bel = ramp("#ecd9b0", 5, lo=0.5, hi=1.1)
    dk = ramp("#5a3a24", 5)
    def extra(c, bm, hm, back_):
        ys, xs = np.mgrid[0:H, 0:W]
        for k in range(6):
            x0 = 20 + k * 6
            band = (np.abs((xs - x0) + (ys - 22) * 0.5) < 1.1) & bm & (ys < 33)
            c.px[band, 0:3] = np.array(dk[1], np.uint8)
        if not back_:
            # saber fangs
            for k in range(8):
                c.pset(66 - (k // 5), 27 + k, (250, 248, 232))
            for k in range(7):
                c.pset(62, 27 + k, (240, 236, 214))
    return quad(W, H, g, bel, dk,
        body=(34, 26, 21, 12, -6),
        head=[(52, 16), (58, 12), (66, 14), (73, 22), (71, 29), (63, 32), (55, 31), (51, 25)],
        legs=[(16, 31, 14, 53, False), (46, 31, 49, 53, False), (22, 33, 20, 54, True), (44, 33, 44, 54, True)],
        tail=dict(pts=[(15, 22), (7, 25), (3, 31)], w=[9, 7, 4]),
        ears=[[(55, 14), (56, 6), (62, 13)]],
        back=back, eye=(61, 20), extra=extra, snout=[(64, 22), (73, 23), (71, 30), (62, 32)], lw=(9, 6.5), seed=21, fur=0.35)

def shrew(back=False):
    W, H = 38, 26
    g = ramp("#8a7260", 5, lo=0.4, hi=1.3)
    bel = ramp("#d6c4aa", 5, lo=0.5, hi=1.1)
    dk = ramp("#4a3a30", 5)
    def extra(c, bm, hm, back_):
        if not back_:
            c.flat(ellipse_mask(W, H, 36.5, 15, 1.3, 1.2), (240, 140, 150))
    return quad(W, H, g, bel, dk,
        body=(17, 15, 10, 6, -3),
        head=[(25, 11), (30, 10), (36, 14), (36, 17), (31, 19), (25, 19)],
        legs=[(10, 18, 9, 23, False), (22, 18, 23, 23, False), (13, 19, 12, 24, True), (20, 19, 21, 24, True)],
        tail=dict(pts=[(8, 13), (3, 13), (0, 17)], w=[2.5, 2, 1.2], rmp=ramp("#c8a090", 5)),
        ears=[[(27, 10), (28, 6), (31, 10)]],
        back=back, eye=(31, 13), extra=extra, lw=(3.6, 2.8), seed=31, fur=0.35)

def glyptodon(back=False):
    W, H = 72, 52
    g = ramp("#8a7458", 5, lo=0.4, hi=1.3)
    shell = ramp("#a08a64", 5, lo=0.35, hi=1.35)
    dk = ramp("#4a3a2a", 5)
    c = Canvas(W, H)
    rng = random.Random(41)
    def leg(x, y, fx, fy, r):
        m = tube_mask(W, H, [(x, y), (fx, fy)], [10, 8], False)
        P(c, m, r, blur=1)
        P(c, tube_mask(W, H, [(fx - 3, fy), (fx + 4, fy)], [3.5, 3], False), dk, blur=1)
    dkr = [tuple(int(v * 0.6) for v in col) for col in g]
    leg(18, 34, 16, 48, dkr); leg(48, 34, 50, 48, dkr)
    # tail club
    P(c, tube_mask(W, H, [(10, 28), (4, 33), (2, 38)], [8, 6, 5]), g, blur=2)
    P(c, ellipse_mask(W, H, 3, 39, 5, 4), shell, blur=2)
    # shell dome
    dome = ellipse_mask(W, H, 32, 26, 25, 18, -4) 
    n = fbm(W, H, 3, 55, 2)
    P(c, dome, shell, blur=5, contrast=1.3, tex=n, tex_amt=0.2)
    # hex scutes
    ys, xs = np.mgrid[0:H, 0:W]
    hexp = ((xs // 6 + ys // 5) % 2 == 0)
    gx = (xs + (ys // 5 % 2) * 3) % 6
    gy = ys % 5
    grid = dome & ((gx == 0) | (gy == 0))
    c.px[grid, 0:3] = (c.px[grid, 0:3] * 0.62).astype(np.uint8)
    hi = dome & (gx == 1) & (gy == 1)
    c.px[hi, 0:3] = np.minimum(255, c.px[hi, 0:3] * 1.35).astype(np.uint8)
    # rim of shell
    P(c, tube_mask(W, H, [(10, 36), (30, 41), (52, 38)], [4, 4, 4]), ramp("#5a4630", 5), blur=1)
    leg(26, 37, 24, 49, g); leg(42, 37, 44, 49, g)
    # head
    hm = poly_mask(W, H, spline([(52, 25), (58, 23), (65, 27), (66, 32), (60, 35), (53, 34)], 8, closed=True))
    P(c, hm, g if not back else dkr, blur=2, contrast=1.2)
    if not back:
        c.pset(60, 28, (255, 236, 150)); c.pset(61, 28, (20, 10, 14))
        c.pset(65, 30, dk[0])
    c.outline(strength=0.72, tint=(14, 10, 30))
    return c

def mammoth(back=False, infected_look=True):
    W, H = 104, 88
    fur = ramp("#7a5a46", 5, lo=0.35, hi=1.3)
    dkfur = ramp("#3a2a26", 5)
    tusk = ramp("#e8dcc0", 5, lo=0.5, hi=1.1)
    c = Canvas(W, H)
    rng = random.Random(61)
    dk = [tuple(int(v * 0.6) for v in col) for col in fur]
    def leg(x, y, fx, fy, r):
        P(c, tube_mask(W, H, [(x, y), (fx, fy)], [15, 13], False), r, blur=2, contrast=1.1, tex=fbm(W, H, 3, x, 2), tex_amt=0.4)
        P(c, tube_mask(W, H, [(fx - 5, fy), (fx + 5, fy)], [4, 4], False), ramp("#3a3430", 5), blur=1)
    leg(26, 58, 24, 82, dk); leg(70, 58, 72, 82, dk)
    # tail
    P(c, tube_mask(W, H, [(12, 40), (8, 52)], [6, 4], False), fur, blur=1)
    body = ellipse_mask(W, H, 44, 44, 34, 24, -3)
    n = fbm(W, H, 3, 77, 3)
    P(c, body, fur, blur=5, contrast=1.3, tex=n, tex_amt=0.5)
    # fur skirt strands
    for k in range(34):
        x = 14 + k * 2
        y0 = 62 + (k % 3)
        for j in range(rng.randint(4, 11)):
            if 0 <= y0 + j < H:
                c.pset(x, y0 + j, dkfur[1 + (j % 2)] if j % 3 else fur[1])
    leg(38, 62, 36, 83, fur); leg(60, 62, 62, 83, fur)
    # hump / head
    hump = ellipse_mask(W, H, 62, 24, 20, 17, 8)
    P(c, hump, fur, blur=4, contrast=1.3, tex=n, tex_amt=0.5)
    head = ellipse_mask(W, H, 78, 38, 13, 15, 5)
    P(c, head, fur, blur=3, contrast=1.2, tex=n, tex_amt=0.4)
    # trunk
    trunk = tube_mask(W, H, [(86, 36), (92, 50), (90, 64), (94, 72)], [10, 8, 6, 4])
    P(c, trunk, fur if not back else dk, blur=2, contrast=1.1)
    for k in range(5):
        yy = 42 + k * 6
        c.pset(88, yy, dkfur[1]); c.pset(89, yy, dkfur[1])
    # tusks
    if not back:
        for off in (0, 4):
            tk = tube_mask(W, H, [(82 + off * .5, 46 + off), (94, 58 + off), (99, 52 + off * .5), (101, 44)], [4, 3.6, 2.8, 1.2])
            P(c, tk, tusk, blur=1, contrast=0.9)
        c.pset(80, 34, (255, 230, 150)); c.pset(81, 34, (20, 10, 14))
        # ear
        P(c, ellipse_mask(W, H, 71, 36, 6, 9, 10), dk, blur=1)
    c.outline(strength=0.72, tint=(14, 10, 30))
    return c

def beetle(back=False):
    W, H = 36, 28
    shell = ramp("#4a7a4a", 5, lo=0.3, hi=1.5, sat=1.05)
    c = Canvas(W, H)
    leg_c = ramp("#2a2a20", 5)
    for k, x in enumerate((9, 17, 25)):
        for side in (0, 1):
            y0 = 17
            tip = (x + (-4 if k == 0 else (4 if k == 2 else 0)), 25 + side * 0)
            P(c, tube_mask(W, H, [(x, y0), (x + (-5 + k * 5) * (0.8), 21), tip], [2.2, 1.8, 1.4], False), leg_c, flat=0.5, dither=False)
    abd = ellipse_mask(W, H, 17, 16, 13, 9.5)
    P(c, abd, shell, blur=3, contrast=1.4)
    ys, xs = np.mgrid[0:H, 0:W]
    split = abd & (np.abs(xs - 17 - (ys - 16) * 0.12) < 0.6)
    c.px[split, 0:3] = np.array(shell[0], np.uint8)
    sh = abd & ellipse_mask(W, H, 13, 11, 4, 2.2)
    c.flat(sh, (210, 245, 200))
    head = ellipse_mask(W, H, 31, 17, 5, 4.5)
    P(c, head, ramp("#2c3a2a", 5), blur=1)
    for dy in (-1, 4):
        P(c, tube_mask(W, H, [(34, 17 + dy * .5), (37, 17 + dy)], [2, 1.5], False), ramp("#2c2a20", 5), flat=.5, dither=False)
    if not back:
        c.pset(32, 15, (255, 220, 120))
    P(c, tube_mask(W, H, [(33, 14), (36, 9)], [1.2, 1], False), leg_c, flat=.6, dither=False)
    c.outline(strength=0.72, tint=(10, 12, 28))
    return c

def _wings(c, W, H, base, span, ang, col=(190, 235, 250), alpha=170, veins=True):
    for sgn, ox in ((1, 0), (-1, 6)):
        pts = [base, (base[0] - span * 0.9, base[1] - span * 0.85 - ox * .5), (base[0] - span * 0.2, base[1] - span * 1.0)]
        m = poly_mask(W, H, spline([base, (base[0] - span * 0.1, base[1] - span * 0.6), (base[0] - span * 0.6, base[1] - span * 0.95 - ox * .3), (base[0] - span * 1.1, base[1] - span * .5 - ox * .2), (base[0] - span * 0.5, base[1] - span * 0.1)], 8, closed=True))
        c.px[m, 0:3] = np.array(col, np.uint8)
        c.px[m, 3] = alpha
        if veins:
            for t in (0.3, 0.55, 0.8):
                x1 = base[0] - span * t * 1.0; y1 = base[1] - span * (0.4 + 0.5 * t) - ox * .3
                for u in np.linspace(0, 1, 12):
                    xx = int(base[0] + (x1 - base[0]) * u); yy = int(base[1] + (y1 - base[1]) * u)
                    if 0 <= xx < W and 0 <= yy < H and m[yy, xx]:
                        c.pset(xx, yy, (120, 180, 210), alpha + 40)
        ox += 0

def dragonfly(back=False, big=False, scale=1.0):
    s = scale
    W, H = int(46 * s), int(34 * s)
    c = Canvas(W, H)
    body = ramp("#2a9a8a", 5, lo=0.4, hi=1.4)
    _wings(c, W, H, (int(22 * s), int(14 * s)), 22 * s, 0)
    seg = tube_mask(W, H, [(int(6 * s), int(24 * s)), (int(20 * s), int(19 * s)), (int(31 * s), int(17 * s))], [3.2 * s, 4 * s, 5 * s])
    P(c, seg, body, blur=1, contrast=1.3)
    ys, xs = np.mgrid[0:H, 0:W]
    for k in range(5):
        xx = int((10 + k * 3.5) * s)
        band = seg & (np.abs(xs - xx) < 0.6)
        c.px[band, 0:3] = np.array(body[0], np.uint8)
    head = ellipse_mask(W, H, 35 * s, 17 * s, 5 * s, 4.5 * s)
    P(c, head, ramp("#d8604a", 5, lo=0.5, hi=1.3), blur=1)
    if not back:
        eye = ellipse_mask(W, H, 37 * s, 16 * s, 2.6 * s, 2.6 * s)
        P(c, eye, ramp("#6ad0f0", 5), blur=1)
        c.pset(int(37 * s), int(15 * s), (255, 255, 255))
    # legs
    for k in range(3):
        c.pset(int((30 + k) * s), int(22 * s), (30, 30, 30)); c.pset(int((30 + k) * s), int(23 * s), (30, 30, 30))
    c.outline(strength=0.6, tint=(10, 20, 40))
    return c

def spore_drone(back=False):
    W, H = 42, 38
    c = Canvas(W, H)
    purp = ramp("#7a4aa8", 5, lo=0.35, hi=1.4)
    glow = ramp("#8dff6a", 5, lo=0.5, hi=1.3)
    _wings(c, W, H, (22, 15), 18, 0, col=(200, 170, 230), alpha=150)
    ab = ellipse_mask(W, H, 14, 22, 11, 9, -15)
    P(c, ab, purp, blur=3, contrast=1.3)
    for (x, y, r) in ((9, 22, 2.8), (15, 27, 2.4), (14, 18, 2.2)):
        sm = ellipse_mask(W, H, x, y, r, r)
        P(c, sm, glow, blur=1, contrast=0.9, flat=0.75)
        c.pset(int(x - 1), int(y - 1), (240, 255, 220))
    th = ellipse_mask(W, H, 27, 20, 6, 5)
    P(c, th, ramp("#5a3a78", 5), blur=2)
    head = ellipse_mask(W, H, 34, 21, 4.5, 4)
    P(c, head, ramp("#3a2a4a", 5), blur=1)
    if not back:
        c.pset(35, 20, (170, 255, 120)); c.pset(36, 20, (230, 255, 200))
    for k in range(3):
        P(c, tube_mask(W, H, [(24 + k * 3, 24), (24 + k * 3 + 1, 30)], [1.6, 1.2], False), ramp("#2a1a3a", 5), flat=.5, dither=False)
    c.outline(strength=0.65, tint=(20, 8, 40))
    return c

def skink(back=False):
    W, H = 50, 24
    c = Canvas(W, H)
    body = ramp("#9a7a48", 5, lo=0.4, hi=1.3)
    tailc = ramp("#3a8ac0", 5, lo=0.4, hi=1.35)
    belly = ramp("#efe0a8", 5, lo=0.5, hi=1.1)
    dk = ramp("#4a3a24", 5)
    for (x, y, fx, fy) in ((12, 16, 9, 21), (30, 16, 33, 21)):
        P(c, tube_mask(W, H, [(x, y), (fx, fy)], [3.5, 2.5], False), [tuple(int(v * .6) for v in col) for col in body], blur=1)
    P(c, tube_mask(W, H, [(18, 13), (10, 15), (4, 14), (0, 10)], [7, 5, 3, 1.2]), tailc, blur=1, contrast=1.2)
    bm = tube_mask(W, H, [(14, 14), (26, 13), (36, 13)], [9, 9.5, 7])
    P(c, bm, body, blur=2, contrast=1.2, tex=fbm(W, H, 3, 5, 2), tex_amt=0.3)
    ys, xs = np.mgrid[0:H, 0:W]
    stripe = bm & (np.abs(ys - (11 + (xs - 14) * -0.03)) < 1.2)
    c.px[stripe, 0:3] = np.array((240, 220, 130), np.uint8)
    P(c, bm & (ys > 15), belly, blur=1, contrast=0.6, rim=0.0)
    for (x, y, fx, fy) in ((15, 17, 14, 22), (33, 17, 36, 22)):
        P(c, tube_mask(W, H, [(x, y), (fx, fy)], [3.5, 2.5], False), body, blur=1)
    head = poly_mask(W, H, spline([(35, 9), (41, 9), (47, 13), (46, 16), (40, 17), (35, 16)], 6, closed=True))
    P(c, head, body, blur=1, contrast=1.2)
    if not back:
        c.pset(41, 11, (255, 230, 120)); c.pset(42, 11, (20, 10, 14))
        c.pset(46, 14, dk[0])
    c.outline(strength=0.7, tint=(14, 10, 30))
    return c

def husk_queen(back=False):
    W, H = 112, 92
    c = Canvas(W, H)
    purp = ramp("#6a3a90", 5, lo=0.3, hi=1.45)
    flesh = ramp("#8a5a6a", 5, lo=0.35, hi=1.4)
    glow = ramp("#8dff6a", 5, lo=0.5, hi=1.3)
    chitin = ramp("#3a2a44", 5, lo=0.4, hi=1.5)
    rng = random.Random(81)
    # legs
    for (x, y, fx, fy) in ((50, 58, 40, 86), (60, 62, 56, 88), (74, 60, 80, 86), (84, 56, 94, 82)):
        m = tube_mask(W, H, [(x, y), ((x + fx) / 2 - 3, y - 6), (fx, fy)], [6, 5, 3])
        P(c, m, chitin, blur=1, contrast=1.1)
    # huge abdomen
    ab = ellipse_mask(W, H, 32, 46, 29, 27, -10)
    n = fbm(W, H, 4, 91, 3)
    P(c, ab, flesh, blur=6, contrast=1.3, tex=n, tex_amt=0.5)
    ys, xs = np.mgrid[0:H, 0:W]
    for k in range(5):
        band = ab & (np.abs((xs - (10 + k * 10)) + (ys - 46) * 0.25) < 0.8)
        c.px[band, 0:3] = np.array(purp[0], np.uint8)
    for (x, y, r) in ((20, 34, 6), (36, 30, 5), (28, 52, 7), (44, 46, 5), (14, 50, 4), (40, 62, 4)):
        sm = ellipse_mask(W, H, x, y, r, r * .9)
        P(c, sm, glow, blur=2, contrast=1.0, flat=0.7)
        c.pset(int(x - r / 3), int(y - r / 3), (240, 255, 220)); c.pset(int(x - r / 3) + 1, int(y - r / 3), (200, 255, 180))
    # spines
    for k in range(7):
        x = 12 + k * 7; y = 24 + abs(k - 3) * 3
        P(c, tube_mask(W, H, [(x, y + 4), (x + 1, y - 7)], [4, 1], False), chitin, blur=1)
    # thorax
    th = ellipse_mask(W, H, 66, 46, 17, 17)
    P(c, th, purp, blur=4, contrast=1.3, tex=n, tex_amt=0.4)
    # head with mandibles
    head = ellipse_mask(W, H, 87, 50, 13, 12)
    P(c, head, chitin, blur=3, contrast=1.3)
    for dy in (-1, 1):
        mand = tube_mask(W, H, [(95, 56 + dy * 3), (103, 62 + dy * 6), (100, 70 + dy * 5)], [5, 4, 1.5])
        P(c, mand, ramp("#c8b8a0", 5, lo=0.4, hi=1.3), blur=1)
    if not back:
        for (ex, ey) in ((90, 44), (95, 49)):
            e = ellipse_mask(W, H, ex, ey, 3.5, 3.5)
            P(c, e, glow, blur=1, flat=0.8)
            c.pset(ex - 1, ey - 1, (255, 255, 255))
    # antennae
    P(c, tube_mask(W, H, [(88, 40), (92, 28), (100, 22)], [2, 1.6, 1]), chitin, flat=0.5, dither=False)
    # spore plumes
    for k in range(10):
        x, y = rng.randint(6, 60), rng.randint(6, 26)
        c.pset(x, y, (190, 255, 150)); c.pset(x + 1, y, (140, 230, 110))
    c.outline(strength=0.7, tint=(18, 8, 38))
    return c

def build_enemies():
    out = {}
    def both(name, fn, **kw):
        out[name] = fn(**kw)
        out[name + "_b"] = fn(back=True, **kw)
    both("beetle", beetle)
    both("dragonfly", dragonfly)
    both("skink", skink)
    both("shrew", shrew)
    both("spore_drone", spore_drone)
    out["meganeura"] = dragonfly(scale=1.55); out["meganeura_b"] = dragonfly(back=True, scale=1.55)
    both("husk_queen", husk_queen)
    out["compy"] = raptor("compy", seed=5); out["compy_b"] = raptor("compy", back=True, seed=5)
    out["spitter"] = raptor("spitter", seed=9); out["spitter_b"] = raptor("spitter", back=True, seed=9)
    both("dire_pup", dire_pup)
    both("glyptodon", glyptodon)
    both("smilodon", smilodon)
    both("infected_mammoth", mammoth)
    return out
