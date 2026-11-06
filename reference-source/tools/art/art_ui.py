"""UI art: icons, portraits, card illustrations, 9-slice panels/buttons."""
import math, random
import numpy as np
from artlib import *
from art_creatures import raptor, RAPTOR_FORMS, P

def icon_canvas(n=16):
    return Canvas(n, n)

def _flat(c, m, col):
    c.flat(m, col)

def make_icons():
    I = {}
    N = 16
    def cv():
        return Canvas(N, N)
    def fin(c, tint=(16, 12, 30)):
        c.outline(strength=0.75, tint=tint)
        return c
    # heart
    c = cv()
    m = poly_mask(N, N, spline([(8, 14), (2, 9), (2.5, 4.5), (6, 3), (8, 5.5), (10, 3), (13.5, 4.5), (14, 9)], 8, closed=True))
    P(c, m, ramp("#e8394a", 5, lo=0.45, hi=1.35), blur=1, contrast=1.3)
    c.pset(4, 5, (255, 190, 200)); c.pset(5, 4, (255, 190, 200))
    I["icon_heart"] = fin(c)
    # meat drumstick
    c = cv()
    bone = tube_mask(N, N, [(9, 9), (14, 14)], [2.2, 2.2], False)
    P(c, bone, ramp("#efe6cc", 5, lo=.6, hi=1.1), blur=1)
    c.flat(ellipse_mask(N, N, 14.5, 12.5, 1.4, 1.4), (240, 232, 205)); c.flat(ellipse_mask(N, N, 12.5, 14.5, 1.4, 1.4), (240, 232, 205))
    mm = ellipse_mask(N, N, 6.5, 6.5, 5.2, 4.6, 40)
    P(c, mm, ramp("#c8602c", 5, lo=0.4, hi=1.4), blur=1, contrast=1.3)
    c.pset(4, 4, (255, 200, 140)); c.pset(5, 4, (255, 180, 120))
    I["icon_meat"] = fin(c)
    # stamina bolt (cyan)
    c = cv()
    m = poly_mask(N, N, [(9.5, 1), (3, 9), (7.2, 9), (5.5, 15), (13, 6.5), (8.5, 6.5), (11, 1)])
    P(c, m, ramp("#40c8f0", 5, lo=0.55, hi=1.35), blur=1, contrast=1.2)
    I["icon_stamina"] = fin(c, (10, 20, 50))
    # foot (moves)
    c = cv()
    P(c, ellipse_mask(N, N, 8, 10.5, 3.6, 4.2), ramp("#f08a60", 5), blur=1)
    for (x, y, r) in ((4.5, 5.3, 1.3), (7, 3.6, 1.4), (9.7, 3.6, 1.4), (12, 5.3, 1.3)):
        P(c, ellipse_mask(N, N, x, y, r, r), ramp("#f08a60", 5), blur=1, flat=0.7)
    I["icon_foot"] = fin(c)
    # speed
    c = cv()
    for (x0, y0, x1, y1) in ((2, 4, 10, 4), (4, 8, 14, 8), (2, 12, 10, 12)):
        P(c, tube_mask(N, N, [(x0, y0), (x1, y1)], [2, 1], False), ramp("#7fd8f0", 5, lo=.6, hi=1.2), flat=.75, dither=False)
    I["icon_speed"] = fin(c, (10, 24, 50))
    # claw
    c = cv()
    for x0 in (3, 7, 11):
        P(c, poly_mask(N, N, [(x0, 1), (x0 + 3, 1.5), (x0 + 1.5, 15)]), ramp("#f4f4f4", 5, lo=.55, hi=1.1), blur=1, contrast=.9, flat=.7, dither=False)
    c.pset(5, 3, (230, 50, 70)); c.pset(9, 4, (230, 50, 70))
    I["icon_claw"] = fin(c)
    # leap
    c = cv()
    for (x, y) in ((2, 13), (4, 8), (7, 4), (11, 4), (13, 8), (13, 12)):
        c.pset(x, y, (248, 230, 120)); c.pset(x + 1, y, (240, 190, 70))
    P(c, tube_mask(N, N, [(2, 13), (4, 7), (8, 3), (12, 5), (14, 11)], [1.8, 1.8, 1.8, 1.8, 2.4]), ramp("#f8e070", 5, lo=.5, hi=1.2), flat=.7, dither=False)
    c.px[13:16, 11:16, :] = c.px[13:16, 11:16, :]
    c.pset(14, 12, (255, 255, 200)); c.pset(13, 13, (255, 255, 200)); c.pset(15, 13, (255, 255, 200))
    I["icon_leap"] = fin(c)
    # eye
    c = cv()
    m = poly_mask(N, N, spline([(1, 8), (5, 4), (11, 4), (15, 8), (11, 12), (5, 12)], 8, closed=True))
    P(c, m, ramp("#f0f0e0", 5, lo=.6, hi=1.1), blur=1, contrast=.6)
    c.flat(ellipse_mask(N, N, 8, 8, 3.2, 3.5), (90, 190, 70)); c.flat(ellipse_mask(N, N, 8, 8, 1.4, 2.4), (14, 16, 14)); c.pset(7, 6, (255, 255, 255))
    I["icon_eye"] = fin(c)
    # drop
    c = cv()
    m = poly_mask(N, N, spline([(8, 1), (12.5, 8), (12, 11.5), (8, 14.5), (4, 11.5), (3.5, 8)], 8, closed=True))
    P(c, m, ramp("#e03048", 5, lo=.45, hi=1.4), blur=1, contrast=1.3)
    c.pset(6, 9, (255, 190, 200)); c.pset(6, 10, (255, 190, 200))
    I["icon_drop"] = fin(c)
    # bolt (yellow)
    c = cv()
    m = poly_mask(N, N, [(9.5, 1), (3, 9), (7.2, 9), (5.5, 15), (13, 6.5), (8.5, 6.5), (11, 1)])
    P(c, m, ramp("#ffd630", 5, lo=.55, hi=1.35), blur=1, contrast=1.2)
    I["icon_bolt"] = fin(c)
    # skull
    c = cv()
    P(c, ellipse_mask(N, N, 8, 7, 5.8, 5.4), ramp("#ece8dc", 5, lo=.5, hi=1.1), blur=1, contrast=1)
    P(c, poly_mask(N, N, [(5, 10), (11, 10), (10.5, 14), (5.5, 14)]), ramp("#ece8dc", 5, lo=.5, hi=1.1), blur=1, contrast=.8)
    c.flat(ellipse_mask(N, N, 5.7, 7.2, 1.6, 1.8), (30, 10, 20)); c.flat(ellipse_mask(N, N, 10.3, 7.2, 1.6, 1.8), (30, 10, 20))
    c.pset(8, 10, (50, 20, 30))
    for x in (6, 8, 10):
        c.pset(x, 13, (80, 70, 80))
    I["icon_skull"] = fin(c)
    # shield
    c = cv()
    m = poly_mask(N, N, [(2, 2), (14, 2), (14, 8), (8, 15), (2, 8)])
    P(c, m, ramp("#4a8ae0", 5, lo=.45, hi=1.4), blur=1, contrast=1.2)
    c.flat(poly_mask(N, N, [(7, 3), (9, 3), (9, 12), (7, 12)]), (190, 220, 255))
    I["icon_shield"] = fin(c)
    # spore
    c = cv()
    for (x, y, r, col) in ((5, 5, 3, "#8dff6a"), (11, 4, 2, "#b68aff"), (10, 11, 3.2, "#8dff6a"), (4, 12, 2, "#b68aff")):
        P(c, ellipse_mask(N, N, x, y, r, r), ramp(col, 5, lo=.5, hi=1.3), blur=1, flat=.7)
    I["icon_spore"] = fin(c, (20, 8, 40))
    # weak
    c = cv()
    P(c, tube_mask(N, N, [(3, 3), (13, 13)], [2.4, 2.4], False), ramp("#b0b0d0", 5), flat=.7, dither=False)
    P(c, tube_mask(N, N, [(13, 3), (3, 13)], [2.4, 2.4], False), ramp("#b0b0d0", 5), flat=.7, dither=False)
    I["icon_weak"] = fin(c)
    # stun (star)
    c = cv()
    pts = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        r = 6.5 if i % 2 == 0 else 2.8
        pts.append((8 + math.cos(a) * r, 8 + math.sin(a) * r))
    P(c, poly_mask(N, N, pts), ramp("#ffe060", 5, lo=.6, hi=1.3), blur=1)
    I["icon_stun"] = fin(c)
    # question
    c = cv()
    for (x, y) in ((6, 3), (7, 3), (8, 3), (9, 3), (5, 4), (10, 4), (10, 5), (10, 6), (9, 7), (8, 8), (7, 9), (7, 10), (7, 12), (7, 13)):
        c.pset(x, y, (255, 224, 96)); c.pset(x + 1 if y < 10 else x, y, (255, 200, 60))
    I["icon_question"] = fin(c)
    # alert
    c = cv()
    P(c, poly_mask(N, N, [(6, 1), (10, 1), (9, 10), (7, 10)]), ramp("#ff4a4a", 5), blur=1, contrast=1.1)
    P(c, ellipse_mask(N, N, 8, 13, 1.9, 1.9), ramp("#ff4a4a", 5), blur=1)
    I["icon_alert"] = fin(c)
    # weather
    def sun():
        c = cv()
        for a in range(8):
            ang = a * math.pi / 4
            c.pset(int(8 + math.cos(ang) * 6.3), int(8 + math.sin(ang) * 6.3), (255, 200, 60)); c.pset(int(8 + math.cos(ang) * 5.3), int(8 + math.sin(ang) * 5.3), (255, 160, 40))
        P(c, ellipse_mask(N, N, 8, 8, 3.8, 3.8), ramp("#ffc830", 5, lo=.6, hi=1.3), blur=1)
        return c
    I["icon_clear"] = fin(sun())
    def cloud(col):
        c = cv()
        m = ellipse_mask(N, N, 5, 7, 3.5, 3) | ellipse_mask(N, N, 9, 5, 4.2, 3.8) | ellipse_mask(N, N, 11.5, 8, 3.2, 2.6) | poly_mask(N, N, [(3, 8), (14, 8), (14, 10), (3, 10)])
        P(c, m, ramp(col, 5, lo=.5, hi=1.25), blur=1, contrast=1.1)
        return c
    c = cloud("#b8c4d0")
    for y in (12, 14):
        for x in range(2, 14, 1):
            if (x + y) % 3:
                c.pset(x, y, (210, 225, 235))
    I["icon_fog"] = fin(c)
    c = cloud("#7e8ca0")
    for (x, y) in ((4, 12), (7, 13), (10, 12), (12, 14), (5, 15)):
        c.pset(x, y, (110, 180, 255)); c.pset(x, y - 1, (140, 200, 255))
    I["icon_rain"] = fin(c)
    c = cloud("#4c4c68")
    P(c, poly_mask(N, N, [(9, 9), (5, 9), (7, 12), (4, 15), (11, 11), (8, 11)]), ramp("#ffe060", 5, lo=.7, hi=1.2), flat=.8, dither=False)
    I["icon_storm"] = fin(c)
    c = sun()
    P(c, ellipse_mask(N, N, 8, 8, 4.8, 4.8), ramp("#f06a30", 5, lo=.6, hi=1.3), blur=1)
    P(c, ellipse_mask(N, N, 8, 8, 2.4, 2.4), ramp("#ffd060", 5), blur=1, flat=.8)
    I["icon_heat"] = fin(c)
    c = cv()
    for (x0, y0, x1, y1) in ((8, 1, 8, 15), (1.5, 4.5, 14.5, 11.5), (1.5, 11.5, 14.5, 4.5)):
        P(c, tube_mask(N, N, [(x0, y0), (x1, y1)], [1.6, 1.6], False), ramp("#bfeaff", 5, lo=.7, hi=1.1), flat=.8, dither=False)
    I["icon_cold"] = fin(c, (20, 40, 80))
    # deck
    c = cv()
    P(c, poly_mask(N, N, [(2, 4), (10, 2), (12, 12), (4, 14)]), ramp("#6a5a40", 5), blur=1)
    P(c, poly_mask(N, N, [(5, 3), (13, 3), (13, 13), (5, 13)]), ramp("#cdb88a", 5, lo=.5, hi=1.2), blur=1)
    for y in (6, 8, 10):
        c.px[y, 7:11, 0:3] = np.array((110, 90, 60), np.uint8)
    I["icon_deck"] = fin(c)
    # turn arrow
    c = cv()
    for t in np.linspace(math.pi * 0.1, math.pi * 1.55, 24):
        c.pset(int(8 + 5.2 * math.cos(t)), int(8 + 5.2 * math.sin(t)), (150, 230, 255)); c.pset(int(8 + 4.2 * math.cos(t)), int(8 + 4.2 * math.sin(t)), (90, 190, 240))
    P(c, poly_mask(N, N, [(11, 12), (15, 11), (13.5, 6)]), ramp("#7fd8f0", 5), flat=.8, dither=False)
    I["icon_turn"] = fin(c, (10, 24, 50))
    # move diamond ring icon (for the Move button)
    c = cv()
    for t in range(0, 8):
        pass
    ring = poly_mask(N, N, [(8, 1), (15, 8), (8, 15), (1, 8)]) & ~poly_mask(N, N, [(8, 4), (12, 8), (8, 12), (4, 8)])
    P(c, ring, ramp("#60d8ff", 5, lo=.6, hi=1.3), blur=1, flat=.75, dither=False)
    c.flat(poly_mask(N, N, [(8, 6), (10, 8), (8, 10), (6, 8)]), (210, 245, 255))
    I["icon_move"] = fin(c, (10, 24, 50))
    # facing arrow (front/side/back)
    for k, col in (("front", "#ff6a4a"), ("side", "#ffd24a"), ("back", "#7dff8a")):
        c = cv()
        P(c, poly_mask(N, N, [(8, 2), (14, 9), (10, 9), (10, 14), (6, 14), (6, 9), (2, 9)]), ramp(col, 5, lo=.55, hi=1.25), blur=1, contrast=1.1)
        I["icon_face_" + k] = fin(c)
    return I

# ------------------------------------------------------------------ portraits
def portrait(form, W=64, H=64, seed=2):
    F = RAPTOR_FORMS[form]
    rng = random.Random(seed)
    c = Canvas(W, H)
    # backdrop
    ys, xs = np.mgrid[0:H, 0:W]
    top = np.array(hexc("#1c2a3a"), np.float32); bot = np.array(hexc("#2e4a52"), np.float32)
    t = ys / H
    g = top[None, None, :] * (1 - t[:, :, None]) + bot[None, None, :] * t[:, :, None]
    g = g + (BAYER[ys % 4, xs % 4] * 7)[:, :, None]
    c.px[:, :, 0:3] = np.clip(g, 0, 255).astype(np.uint8); c.px[:, :, 3] = 255
    body = ramp(F["body"], 5, lo=0.35, hi=1.35)
    belly = ramp(F["belly"], 5, lo=0.5, hi=1.15)
    dark = ramp(F["stripe"], 5, lo=0.4, hi=1.3)
    crest = ramp(F["crest"], 5, lo=0.5, hi=1.25)
    fg = Canvas(W, H)
    neck = tube_mask(W, H, [(6, 66), (14, 50), (22, 38)], [26, 20, 14])
    P(fg, neck, body, blur=3, contrast=1.2)
    nb = neck & ellipse_mask(W, H, 12, 56, 7, 14, 20) & ~ellipse_mask(W, H, 22, 30, 16, 20)
    P(fg, nb, belly, blur=1, contrast=.6, rim=0.0)
    hm = poly_mask(W, H, spline([(14, 26), (20, 14), (32, 10), (46, 14), (60, 24), (62, 31), (56, 38), (42, 42), (28, 42), (18, 38)], 8, closed=True))
    P(fg, hm, body, blur=3, contrast=1.3, tex=fbm(W, H, 3, seed, 2), tex_amt=.3)
    jaw = hm & poly_mask(W, H, [(26, 33), (64, 30), (64, 46), (26, 46)])
    P(fg, jaw, belly, blur=1, contrast=.5, rim=0.0)
    mouth = tube_mask(W, H, [(60, 31), (46, 35), (34, 37)], [1.4, 1.4, 1.2], False)
    fg.flat(mouth, dark[0])
    for i in range(6):
        x = 58 - i * 3.6
        fg.flat(poly_mask(W, H, [(x, 31 + i * .5), (x + 2, 31 + i * .5), (x + 1, 35 + i * .5)]), (250, 248, 236))
    for i in range(4):
        x = 56 - i * 4
        fg.flat(poly_mask(W, H, [(x, 36 - i * .4), (x + 2, 36 - i * .4), (x + 1, 33 - i * .4)]), (240, 236, 220))
    # eye
    fg.flat(ellipse_mask(W, H, 43, 22, 4.2, 3.4, 10), (255, 214, 90))
    fg.flat(ellipse_mask(W, H, 44.5, 22, 1.4, 3.0), (18, 8, 12))
    fg.pset(43, 21, (255, 255, 230))
    for k in range(7):
        fg.pset(38 + k, 17 + (k // 3), dark[1])
    fg.flat(ellipse_mask(W, H, 58, 23, 1.2, 0.9), dark[0])
    # crest
    for (a, b, wd) in (((18, 18), (6, 8), 4), ((24, 14), (14, 2), 3.6), ((14, 26), (2, 20), 3.2), ((30, 11), (24, -2), 3)):
        fm = tube_mask(W, H, [a, ((a[0] + b[0]) / 2 - 2, (a[1] + b[1]) / 2 - 3), b], [wd, wd * .8, 1])
        P(fg, fm, crest, blur=1, contrast=1.1)
    # stripes on the cheek
    for k in range(3):
        band = hm & (np.abs((xs - (26 + k * 3)) + (ys - 20) * 0.5) < 0.9) & (ys < 30)
        fg.px[band, 0:3] = np.array(dark[1], np.uint8)
    fg.outline(strength=0.7, tint=(10, 12, 28))
    c.paste(fg, 0, 0)
    # light edge + frame
    c.px[0, :, 0:3] = (20, 30, 44); c.px[-1, :, 0:3] = (20, 30, 44); c.px[:, 0, 0:3] = (20, 30, 44); c.px[:, -1, 0:3] = (20, 30, 44)
    return c, fg

def head_cutout(form):
    """head on transparent bg for card art"""
    _, fg = portrait(form)
    return fg

# ------------------------------------------------------------------ card art
CARD_W, CARD_H = 92, 54

def _bg(kind_cols, seed):
    c = Canvas(CARD_W, CARD_H)
    ys, xs = np.mgrid[0:CARD_H, 0:CARD_W]
    a = np.array(hexc(kind_cols[0]), np.float32); b = np.array(hexc(kind_cols[1]), np.float32); cc = np.array(hexc(kind_cols[2]), np.float32)
    d = np.sqrt(((xs - CARD_W * 0.62) / (CARD_W * 0.6)) ** 2 + ((ys - CARD_H * 0.5) / (CARD_H * 0.8)) ** 2)
    t = np.clip(d, 0, 1)[:, :, None]
    col = cc[None, None, :] * (1 - t) ** 1.2 + b[None, None, :] * (t * (1 - t) * 2.5).clip(0, 1) + a[None, None, :] * (t ** 1.5)
    n = fbm(CARD_W, CARD_H, 6, seed, 2)
    col = col + ((n - 0.5) * 30)[:, :, None] + (BAYER[ys % 4, xs % 4] * 10)[:, :, None]
    c.px[:, :, 0:3] = np.clip(col, 0, 255).astype(np.uint8); c.px[:, :, 3] = 255
    return c

def _streaks(c, rng, col, n, y_lo=0.2, y_hi=0.8, ang=-0.25, length=(14, 36)):
    for _ in range(n):
        y = rng.randint(int(CARD_H * y_lo), int(CARD_H * y_hi))
        x = rng.randint(0, CARD_W - 10)
        L = rng.randint(*length)
        for k in range(L):
            xx = x + k; yy = int(y + k * ang)
            if 0 <= xx < CARD_W and 0 <= yy < CARD_H:
                f = 1 - abs(k - L / 2) / (L / 2)
                if f > 0.2:
                    mix_ = tuple(int(col[i] * f + c.px[yy, xx, i] * (1 - f)) for i in range(3))
                    c.pset(xx, yy, mix_)
    return c

def _sprite_rot(spr, deg, scale=1):
    im = spr.to_image()
    if scale != 1:
        im = im.resize((int(im.width * scale), int(im.height * scale)), Image.NEAREST)
    im = im.rotate(deg, resample=Image.NEAREST, expand=True)
    cc = Canvas(im.width, im.height)
    cc.px = np.array(im)
    return cc

def _slashes(c, cols, offset=(0, 0), n=3, seed=1, thick=3.0):
    rng = random.Random(seed)
    for i in range(n):
        x0 = 22 + i * 14 + offset[0]; y0 = 4 + offset[1] + i * 2
        pts = [(x0, y0), (x0 + 10, y0 + 24), (x0 + 22, y0 + 46)]
        m = tube_mask(CARD_W, CARD_H, pts, [thick, thick * .9, .8])
        c.shade(m, cols, blur=1, flat=0.82, dither=False)
        m2 = tube_mask(CARD_W, CARD_H, [(x0 + 1, y0 + 2), (x0 + 11, y0 + 24), (x0 + 22, y0 + 46)], [1.2, 1, .4])
        c.flat(m2, (255, 245, 230))

def card_art(kind, form="adult", seed=1):
    rng = random.Random(seed)
    sprites = {}
    if kind in ("bite", "feast", "screech", "nip"):
        pal = {"bite": ("#3a0f14", "#8a1c24", "#d4382c"), "feast": ("#3a1a0a", "#8a3a14", "#e0802c"), "screech": ("#20103a", "#5a2a8a", "#b060e0"), "nip": ("#3a0f14", "#8a1c24", "#d4382c")}[kind]
        c = _bg(pal, seed)
        head = head_cutout(form)
        hx = 8 if kind != "screech" else 14
        sc_ = Canvas(64, 64); sc_.paste(head, 0, 0)
        c.paste(sc_, hx, -2)
        if kind == "screech":
            for r in (22, 30, 38):
                for t in np.linspace(-0.7, 0.7, 40):
                    x = int(72 + r * math.cos(t)); y = int(27 + r * math.sin(t) * 0.8)
                    if 0 <= x < CARD_W and 0 <= y < CARD_H:
                        c.pset(x, y, (230, 190, 255) if r < 38 else (170, 120, 220))
        if kind in ("bite", "nip"):
            _streaks(c, rng, (255, 120, 90), 7, 0.1, 0.9, 0.0, (10, 26))
        if kind == "feast":
            m = ellipse_mask(CARD_W, CARD_H, 74, 40, 8, 6, 30)
            c.shade(m, ramp("#c8502c", 5, lo=.4, hi=1.4), blur=1, contrast=1.3)
            c.outline(strength=.6)
        return c
    if kind in ("pounce", "leap", "hitrun", "apex"):
        pal = {"pounce": ("#3a1a08", "#a8481a", "#ff9a30"), "leap": ("#2a1a08", "#a85a1a", "#ffb840"), "hitrun": ("#3a1a08", "#b0501a", "#ff9040"), "apex": ("#300a10", "#a01c28", "#ff5a3c")}[kind]
        c = _bg(pal, seed)
        _streaks(c, rng, (255, 210, 120), 14, 0.15, 0.85, 0.35, (16, 40))
        spr = raptor(form, seed=3)
        rs = _sprite_rot(spr, 28 if kind != "hitrun" else 8, 1)
        c.paste(rs, (CARD_W - rs.w) // 2 + 6, max(-6, (CARD_H - rs.h) // 2 + 3))
        if kind == "apex":
            _slashes(c, ramp("#ff3a3a", 5), (10, 0), 2, seed)
        return c
    if kind in ("claw", "rake", "twin", "sickle", "tail"):
        pal = {"claw": ("#2a0a10", "#7a1420", "#d4382c"), "rake": ("#2a0a10", "#7a1420", "#c82838"), "twin": ("#2a0a18", "#8a1830", "#e04858"), "sickle": ("#2a0a10", "#7a1420", "#e04030"), "tail": ("#14122a", "#3a2a6a", "#7a60d0")}[kind]
        c = _bg(pal, seed)
        if kind == "tail":
            for r, col in ((28, (200, 190, 255)), (22, (150, 140, 230)), (16, (110, 100, 200))):
                for t in np.linspace(-2.6, -0.3, 60):
                    x = int(36 + r * math.cos(t) * 1.3); y = int(46 + r * math.sin(t))
                    for dy in (0, 1):
                        if 0 <= x < CARD_W and 0 <= y + dy < CARD_H:
                            c.pset(x, y + dy, col)
            spr = raptor(form, seed=3)
            c.paste(spr, 4, CARD_H - spr.h + 4)
            return c
        _slashes(c, ramp("#ff4a4a", 5, lo=.6, hi=1.3), (0, 0), 3 if kind != "twin" else 2, seed)
        if kind == "twin":
            _slashes(c, ramp("#ff7a5a", 5, lo=.6, hi=1.3), (22, 2), 2, seed + 1)
        for _ in range(8):
            x, y = rng.randint(30, 80), rng.randint(6, 48)
            c.flat(ellipse_mask(CARD_W, CARD_H, x, y, 1.2, 1.2), (230, 40, 60))
        if kind in ("rake", "sickle"):
            c.shade(poly_mask(CARD_W, CARD_H, spline([(14, 40), (22, 30), (34, 26), (24, 38), (18, 48)], 6, closed=True)), ramp("#e8e8f0", 5), blur=1, flat=.7, dither=False)
        return c
    if kind in ("hide", "stalk", "calm", "grassdive"):
        pal = {"hide": ("#06180e", "#164a2a", "#3a9a50"), "stalk": ("#06180e", "#164a2a", "#48b060"), "calm": ("#08161a", "#1a4a4a", "#48b0a8"), "grassdive": ("#06180e", "#1e5a2a", "#58c058")}[kind]
        c = _bg(pal, seed)
        gcols = [ramp("#1a5a2c", 5, lo=.4, hi=1.2), ramp("#2e8a38", 5, lo=.4, hi=1.3), ramp("#5cb348", 5, lo=.5, hi=1.2)]
        if kind != "grassdive":
            for ex in (36, 56):
                c.flat(ellipse_mask(CARD_W, CARD_H, ex, 26, 4, 2.4), (255, 220, 80)); c.flat(ellipse_mask(CARD_W, CARD_H, ex + 1, 26, 1, 2.2), (20, 10, 10)); c.pset(ex - 1, 25, (255, 255, 220))
        else:
            spr = raptor(form, seed=3)
            c.paste(spr, 16, 4)
        for _ in range(110):
            x = rng.randint(0, CARD_W - 1); base = rng.randint(34, CARD_H + 4); L = rng.randint(10, 26)
            lean = rng.uniform(-.4, .4); ci = rng.choice([0, 1, 1, 2])
            for k in range(L):
                f = k / L
                xx = int(x + lean * k); yy = base - k
                if 0 <= xx < CARD_W and 0 <= yy < CARD_H:
                    c.pset(xx, yy, gcols[ci][min(4, int(1 + f * 3.4))])
        return c
    if kind in ("speed", "quick", "bolt", "adrenaline", "extra"):
        pal = {"speed": ("#081830", "#1a4a8a", "#40b0f0"), "quick": ("#081830", "#1a4a8a", "#50c0ff"), "bolt": ("#201808", "#8a6a10", "#ffd840"), "adrenaline": ("#2a0a20", "#8a1a5a", "#ff5090"), "extra": ("#101030", "#3a3a9a", "#8090ff")}[kind]
        c = _bg(pal, seed)
        _streaks(c, rng, (180, 230, 255) if kind in ("speed", "quick") else (255, 240, 160), 16, 0.1, 0.9, 0.0, (20, 50))
        if kind in ("speed", "quick"):
            spr = raptor(form, seed=3)
            c.paste(spr, 14, 4)
        else:
            bolt = poly_mask(CARD_W, CARD_H, [(54, 1), (32, 28), (46, 28), (38, 53), (66, 20), (51, 20), (62, 1)])
            c.shade(bolt, ramp("#ffe040" if kind != "extra" else "#a0b0ff", 5, lo=.55, hi=1.4), blur=1, contrast=1.1)
            c.outline(strength=.6, tint=(40, 20, 0))
        return c
    if kind == "meat":
        c = _bg(("#2a1408", "#7a3a14", "#d8782c"), seed)
        bone = tube_mask(CARD_W, CARD_H, [(44, 28), (68, 44)], [6, 6], False)
        c.shade(bone, ramp("#efe6cc", 5, lo=.6, hi=1.1), blur=1)
        for (x, y) in ((68, 40), (66, 46)):
            c.flat(ellipse_mask(CARD_W, CARD_H, x, y, 4, 4), (240, 232, 205))
        mm = ellipse_mask(CARD_W, CARD_H, 34, 22, 20, 15, 30)
        c.shade(mm, ramp("#c8602c", 5, lo=.4, hi=1.4), blur=3, contrast=1.3, tex=fbm(CARD_W, CARD_H, 4, 9, 2), tex_amt=.4)
        c.outline(strength=.7, tint=(30, 10, 10))
        return c
    if kind in ("bleed", "deathroll"):
        c = _bg(("#2a0610", "#7a0c20", "#d02038"), seed)
        for (x, y, r) in ((30, 20, 7), (52, 34, 9), (70, 16, 6), (20, 42, 5), (62, 8, 4)):
            m = poly_mask(CARD_W, CARD_H, spline([(x, y - r * 1.6), (x + r, y + r * .2), (x, y + r), (x - r, y + r * .2)], 8, closed=True))
            c.shade(m, ramp("#e03048", 5, lo=.45, hi=1.4), blur=1, contrast=1.3)
            c.pset(int(x - r / 3), int(y), (255, 190, 200))
        if kind == "deathroll":
            for t in np.linspace(0, 12, 160):
                r = 4 + t * 2.4
                x = int(46 + r * math.cos(t)); y = int(27 + r * math.sin(t) * 0.7)
                if 0 <= x < CARD_W and 0 <= y < CARD_H:
                    c.pset(x, y, (255, 120, 120)); c.pset(x + 1, y, (200, 40, 60))
        return c
    if kind in ("block", "skitter"):
        c = _bg(("#08142a", "#1a3a7a", "#4a8ae0"), seed)
        spr = raptor(form, seed=3)
        c.paste(spr, 6, 3)
        sh = poly_mask(CARD_W, CARD_H, spline([(62, 8), (84, 12), (84, 30), (73, 46), (62, 30)], 8, closed=True))
        c.shade(sh, ramp("#4a8ae0", 5, lo=.45, hi=1.4), blur=2, contrast=1.1)
        c.outline(strength=.6, tint=(10, 20, 50))
        return c
    if kind == "backstab":
        c = _bg(("#120818", "#3a1a4a", "#8a3a8a"), seed)
        # enemy silhouette seen from behind + raptor claws from behind
        sil = ellipse_mask(CARD_W, CARD_H, 56, 30, 18, 14)
        c.shade(sil, ramp("#4a3a5a", 5, lo=.3, hi=1.0), blur=3, contrast=.8)
        c.outline(strength=.7, tint=(10, 6, 20))
        _slashes(c, ramp("#ff5a8a", 5, lo=.6, hi=1.3), (-8, 0), 3, seed)
        spr = raptor(form, back=True, seed=3)
        c.paste(spr, 0, 4)
        return c
    # generic
    return _bg(("#101810", "#2a3a2a", "#5a7a5a"), seed)

CARD_KIND = {
    "claw_slash": "claw", "skitter": "skitter", "crouch": "hide", "pounce": "pounce", "nip": "nip", "rake": "rake",
    "tail_whip": "tail", "hit_and_run": "hitrun", "grass_dive": "grassdive", "scavenge": "meat", "quick_feet": "quick",
    "sickle_claw": "sickle", "leaping_rake": "leap", "adrenaline": "adrenaline", "stalker": "stalk", "twin_sickles": "twin",
    "shadow_rush": "leap", "predator_screech": "screech", "feast_bite": "feast", "apex_ambush": "apex",
    "lightning_reflexes": "extra", "death_roll": "deathroll", "hunters_calm": "calm",
    "backstab": "backstab", "hamstring": "rake", "bite": "bite",
}

# ------------------------------------------------------------------ 9-slice UI
def nine(w, h, fill_top, fill_bot, border, light, dark, notch=2):
    c = Canvas(w, h)
    ys, xs = np.mgrid[0:h, 0:w]
    t = (ys / (h - 1))[:, :, None]
    top = np.array(hexc(fill_top), np.float32); bot = np.array(hexc(fill_bot), np.float32)
    col = top[None, None, :] * (1 - t) + bot[None, None, :] * t + (BAYER[ys % 4, xs % 4] * 5)[:, :, None]
    c.px[:, :, 0:3] = np.clip(col, 0, 255).astype(np.uint8); c.px[:, :, 3] = 255
    # corner notches
    m = np.ones((h, w), bool)
    for i in range(notch):
        for j in range(notch - i):
            m[i, j] = m[i, w - 1 - j] = m[h - 1 - i, j] = m[h - 1 - i, w - 1 - j] = False
    c.px[~m, 3] = 0
    edge = m & ((ys == 0) | (ys == h - 1) | (xs == 0) | (xs == w - 1) | ~np.pad(m, 1, constant_values=False)[2:, 1:-1] | ~np.pad(m, 1, constant_values=False)[:-2, 1:-1] | ~np.pad(m, 1, constant_values=False)[1:-1, 2:] | ~np.pad(m, 1, constant_values=False)[1:-1, :-2])
    c.px[edge, 0:3] = np.array(hexc(dark), np.uint8)
    # border ring (1px inside)
    ring = m & ~edge & ((ys == 1) | (ys == h - 2) | (xs == 1) | (xs == w - 2))
    c.px[ring, 0:3] = np.array(hexc(border), np.uint8)
    inner = m & ~edge & ~ring & ((ys == 2) | (xs == 2))
    c.px[inner, 0:3] = np.array(hexc(light), np.uint8) * 0 + (np.array(hexc(border), np.float32) * 0.55 + np.array(hexc(fill_top), np.float32) * 0.45).astype(np.uint8)
    # lit top/left edge highlight on ring
    hl = ring & ((ys == 1) | (xs == 1))
    c.px[hl, 0:3] = np.array(hexc(light), np.uint8)
    # corner studs
    for (x, y) in ((3, 3), (w - 4, 3), (3, h - 4), (w - 4, h - 4)):
        c.pset(x, y, hexc(light))
    return c

def make_ui():
    U = {}
    U["ui_panel"] = nine(32, 32, "#14202e", "#0c1420", "#4a6a8c", "#8ab4d8", "#05080e")
    U["ui_panel_gold"] = nine(32, 32, "#241e12", "#14100a", "#b8903a", "#f0d078", "#0a0804")
    U["ui_panel_dim"] = nine(32, 32, "#10161e", "#0a0e14", "#2e4056", "#5a7894", "#04060a")
    U["ui_panel_green"] = nine(32, 32, "#122418", "#0a160e", "#4a8c5a", "#90d8a0", "#050a06")
    U["ui_panel_red"] = nine(32, 32, "#2a1218", "#16080c", "#9a3a4a", "#e07888", "#0a0406")
    U["ui_btn"] = nine(24, 24, "#233a52", "#162638", "#5a8ab0", "#a8d4f0", "#060a10")
    U["ui_btn_hover"] = nine(24, 24, "#2e4c6a", "#1c3248", "#7ab8e0", "#d0eeff", "#060a10")
    U["ui_btn_pressed"] = nine(24, 24, "#122030", "#0e1824", "#4a7090", "#7aa4c8", "#060a10")
    U["ui_btn_disabled"] = nine(24, 24, "#1a222c", "#141a22", "#34424e", "#52626e", "#06080a")
    U["ui_btn_cyan"] = nine(24, 24, "#1c4a64", "#10303f", "#50d0f0", "#c8f6ff", "#04080c")
    U["ui_btn_cyan_hover"] = nine(24, 24, "#26607e", "#163e52", "#80e4ff", "#ffffff", "#04080c")
    # cost badge
    c = Canvas(22, 22)
    m = ellipse_mask(22, 22, 11, 11, 10, 10)
    c.shade(m, ramp("#2a3a52", 5, lo=.4, hi=1.5), blur=2, contrast=1.1)
    ring = m & ~ellipse_mask(22, 22, 11, 11, 8, 8)
    c.flat(ring, (200, 226, 246))
    c.outline(strength=.8, tint=(6, 10, 18))
    U["ui_badge"] = c
    return U
