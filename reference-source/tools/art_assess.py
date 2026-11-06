#!/usr/bin/env python3
"""Downscale previews + metrics for the 640x360 (Sea-of-Stars style) assessment.
Usage: python3 tools/art_assess.py   -> screenshots/art_spec/*.png and a metrics table on stdout (Pillow).
Board art is scaled by 32/76 (tile 76x38 -> 32x16); UI art by 2/3 (960x540 design frame -> 640x360)."""
import os, sys, warnings
warnings.filterwarnings('ignore')
from PIL import Image
S = "assets/sprites/"
OUT = "screenshots/art_spec/"
BOARD, UI = 32/76, 2/3
ASSETS = [
 ("ground tile (jungle)", "tile_jungle_ground_0", BOARD), ("ground tile (tundra)", "tile_tundra_ground_0", BOARD), ("ground tile (cave)", "tile_cave_ground_0", BOARD),
 ("grass tile", "tile_grass_01", BOARD), ("tall grass (jungle)", "prop_jungle_tallgrass_0", BOARD),
 ("tree prop", "deco_tree_01", BOARD), ("obstacle (jungle)", "prop_jungle_obstacle_0", BOARD), ("obstacle (tundra)", "prop_tundra_obstacle_0", BOARD), ("obstacle (cave)", "prop_cave_obstacle_0", BOARD),
 ("bush / foliage", "foliage_05", BOARD), ("log", "log_01", BOARD), ("deco bush", "deco_bush_01", BOARD), ("rock", "deco_rock_01", BOARD),
 ("raptor adult SE", "raptor_adult", BOARD), ("raptor adult SW", "raptor_adult_sw", BOARD), ("raptor adult NE", "raptor_adult_b", BOARD), ("raptor adult NW", "raptor_adult_nw", BOARD),
 ("raptor baby SE", "raptor_baby", BOARD), ("raptor prime SE", "raptor_prime", BOARD),
 ("beetle", "beetle", BOARD), ("compy", "compy", BOARD), ("smilodon", "smilodon", BOARD), ("husk queen", "husk_queen", BOARD), ("infected mammoth", "infected_mammoth", BOARD),
 ("button", "ui_btn", UI), ("panel 9-slice", "ui_panel", UI), ("HP bar frame", "ui_bar_frame", UI), ("slim bar", "ui_bar_slim", UI),
 ("card art", "card_claw_slash", UI), ("card frame 9-slice", "card_frame_dark", UI), ("icon 16px", "icon_heart", UI), ("item icon 20px", "item_apex_heart", UI),
 ("portrait 64px", "portrait_adult", UI), ("egg", "egg_raptor", UI), ("nest", "bg_egg_nest", UI), ("backdrop 960x540", "bg_jungle_0", UI),
]
def load(n):
    for cand in (n, n + "_0", n + "_00"):
        p = S + cand + ".png"
        if os.path.exists(p):
            return Image.open(p).convert("RGBA")
    raise SystemExit("missing " + n)
def colours(im):
    return len({p for p in im.getdata() if p[3] > 40})
def soft(im):
    a = im.getchannel("A"); n = sum(1 for v in a.getdata() if 10 < v < 245); t = sum(1 for v in a.getdata() if v > 10) or 1
    return n / t
def err(a, b):
    a = a.resize(b.size, Image.NEAREST) if a.size != b.size else a
    d = 0; n = 0
    for p, q in zip(a.getdata(), b.getdata()):
        if p[3] > 40 or q[3] > 40:
            d += sum(abs(p[i] - q[i]) for i in range(3)) / 3.0; n += 1
    return d / max(1, n)
rows = []
sheet_w = 0; tiles = []
for label, name, f in ASSETS:
    im = load(name)
    w, h = im.size
    tw, th = max(1, round(w * f)), max(1, round(h * f))
    area = im.resize((tw, th), Image.BOX)
    lanc = im.resize((tw, th), Image.LANCZOS)
    near = im.resize((tw, th), Image.NEAREST)
    # clean-up: snap alpha to 0/1 and reduce to a small palette (what a pixel artist would do)
    clean = area.copy()
    a = clean.getchannel("A").point(lambda v: 255 if v > 110 else 0)
    q = clean.convert("RGB").quantize(colors=24, method=Image.MEDIANCUT, dither=Image.NONE).convert("RGB")
    clean = Image.merge("RGBA", (*q.split(), a))
    rows.append((label, name, (w, h), (tw, th), colours(im), colours(area), soft(area), err(near, area), colours(clean)))
    tiles.append((label, im, near, area, clean))
# contact sheets: native (2x) | nearest | area | area + cleaned, the three candidates at 4x so single pixels are visible
pad = 8
items = []
for label, im, near, area, clean in tiles:
    if im.width > 130 or im.height > 130:
        continue
    row = [im.resize((im.width * 2, im.height * 2), Image.NEAREST)] + [t.resize((t.width * 4, t.height * 4), Image.NEAREST) for t in (near, area, clean)]
    items.append((label, row))
for part in range(0, len(items), 9):
    chunk = items[part:part + 9]
    W = max(sum(r.width for r in row) + pad * 5 for _, row in chunk)
    H = sum(max(r.height for r in row) + pad for _, row in chunk) + pad
    sh = Image.new("RGBA", (W, H), (40, 44, 52, 255))
    y = pad
    for label, row in chunk:
        x = pad
        for r in row:
            sh.alpha_composite(r, (x, y)); x += r.width + pad
        y += max(r.height for r in row) + pad
    sh.save(OUT + "downscale_sheet_%d.png" % (part // 9 + 1))
    print("sheet", part // 9 + 1, [l for l, _ in chunk])
print("| asset | file | native px | target px | colours native -> area -> cleaned | soft-edge px (area) | nearest-vs-area error |")
for label, name, n, t, c0, c1, s, e, c2 in rows:
    print("| %s | %s | %dx%d | %dx%d | %d -> %d -> %d | %.0f%% | %.1f |" % (label, name, n[0], n[1], t[0], t[1], c0, c1, c2, s * 100, e))
