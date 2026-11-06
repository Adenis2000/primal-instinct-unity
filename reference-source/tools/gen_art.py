#!/usr/bin/env python3
"""Generates all pixel-art PNGs into assets/sprites/ (+ data/themes.json). Run from the project root:
    python3 tools/gen_art.py [--only tiles|creatures|ui|bg]
Needs: python3, numpy, pillow. Real hand-made art can replace any file (same name) - the game loads PNGs
from assets/sprites/ first and only falls back to data/sprites.json shapes if a PNG is missing."""
import json, os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "art"))
from artlib import *
import art_env as E
import art_bg as B
import art_creatures as C
import art_ui as U
import art_cave as K
import art_card as KC

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "sprites")
os.makedirs(OUT, exist_ok=True)
only = sys.argv[sys.argv.index("--only") + 1] if "--only" in sys.argv else None
count = 0

# sprites built from the designer-supplied sheets (tools/import_supplied.py) - never overwritten by the generator
_owned_path = os.path.join(ROOT, "tools", "art", "supplied", "owned.txt")
OWNED = set(open(_owned_path).read().split()) if os.path.exists(_owned_path) else set()

def save(name, cv):
    global count
    if name in OWNED:
        return
    cv.save(os.path.join(OUT, name + ".png"))
    count += 1

def egg(locked=False):
    W, H = 40, 48
    c = Canvas(W, H)
    if locked:
        rmp = ramp("#6a7280", 5, lo=.4, hi=1.4)
    else:
        rmp = ramp("#efe4c4", 5, lo=.45, hi=1.1)
    pts = [(20, 3), (30, 12), (35, 28), (30, 41), (20, 45), (10, 41), (5, 28), (10, 12)]
    m = blob_mask(W, H, pts)
    n = fbm(W, H, 4, 3, 2)
    c.shade(m, rmp, blur=4, contrast=1.3, tex=n, tex_amt=.2)
    ys, xs = np.mgrid[0:H, 0:W]
    if not locked:
        sp = ramp("#86b84e", 5, lo=.4, hi=1.2)
        for (x, y, r) in ((14, 16, 3), (24, 22, 3.6), (16, 30, 3.2), (26, 35, 2.4), (12, 24, 1.8), (22, 11, 1.8)):
            sm = ellipse_mask(W, H, x, y, r, r * .85) & m
            c.shade(sm, sp, blur=1, flat=.55)
    else:
        q = [(18, 17), (19, 16), (21, 16), (22, 17), (22, 19), (21, 21), (20, 22), (20, 24), (20, 27)]
        for (x, y) in q:
            c.pset(x, y, (222, 226, 236)); c.pset(x + 1, y, (190, 196, 210))
    c.outline(strength=.7, tint=(30, 20, 20) if not locked else (14, 16, 26))
    return c

def item_icon(idef):
    """20x20 placeholder: rarity-coloured badge + the item's glyph tinted with its colour."""
    from PIL import Image
    rc = {"common": "#9aa8b8", "uncommon": "#6fc24e", "rare": "#6fa8e8", "legendary": "#f0b030"}[idef["rarity"]]
    c = Canvas(20, 20)
    m = ellipse_mask(20, 20, 10, 10, 9.2, 9.2)
    c.shade(m, ramp(rc, 5, lo=0.35, hi=1.25), blur=1, contrast=1.1, rim=0.3)
    inner = ellipse_mask(20, 20, 10, 10, 7.2, 7.2)
    c.flat(inner, (12, 16, 28))
    g = Image.open(os.path.join(OUT, idef["icon"] + ".png")).convert("RGBA")
    tint = hexc(idef["color"])
    px = np.array(g, np.float32)
    lum = px[:, :, :3].mean(axis=2, keepdims=True) / 255.0
    px[:, :, :3] = np.clip(np.array(tint, np.float32)[None, None, :] * (0.55 + 0.75 * lum), 0, 255)
    g2 = Image.fromarray(px.astype(np.uint8), "RGBA")
    ox, oy = (20 - g2.width) // 2, (20 - g2.height) // 2
    base = c.to_image().convert("RGBA")
    base.alpha_composite(g2, (ox, oy))
    c.px[:] = np.array(base, np.uint8)
    c.outline(strength=0.6, tint=(10, 8, 24))
    return c

CAVE_CARD_KIND = {"venom_fang": "venom", "silk_snare": "web", "chitin_plating": "plate", "widow_kiss": "widow"}

def _owned_n(theme):
    """Obstacle variants incl. the ones appended by import_supplied.py."""
    k = 0
    while os.path.exists(os.path.join(OUT, "prop_%s_obstacle_%d.png" % (theme, k))):
        k += 1
    return k

def main():
    # ---- themes
    th = {}
    for t in ("jungle", "tundra", "cave"):
        th[t] = {}
    if only in (None, "tiles"):
        for t in ("jungle", "tundra", "cave"):
            nground = 6
            for v in range(nground):
                save("tile_%s_ground_%d" % (t, v), E.ground_tile(t, v))
            for v in range(3):
                save("tile_%s_tall_%d" % (t, v), E.ground_tile(t, v, "tall"))
                save("prop_%s_tallgrass_%d" % (t, v), E.tall_grass(t, v))
                save("prop_%s_tallgrass_front_%d" % (t, v), E.tall_grass(t, v, True))
            for v in range(2):
                for f in range(3):
                    save("tile_%s_water_%d_%d" % (t, v, f), E.water_tile(t, f, v))
            props = [E.boulders(t, 0), E.boulders(t, 1), E.log_prop(t, 0), E.log_prop(t, 1), E.ruin_block(t, 0), E.ruin_block(t, 1)]
            if t == "cave":
                props = [E.boulders(t, 0), E.boulders(t, 1), E.ruin_block(t, 0), E.ruin_block(t, 1),
                         K.stalagmites(t, 0), K.stalagmites(t, 1), K.stalagmites(t, 2), K.cocoon(t, 0), K.cocoon(t, 1),
                         E.ice_crystals(t, 0), E.ice_crystals(t, 1)]
            elif t == "jungle":
                props += [E.fern_bush(t, 0), E.fern_bush(t, 1), E.pine_prop(t, 0)]
            else:
                props += [E.pine_prop(t, 0), E.pine_prop(t, 1), E.ice_crystals(t, 0), E.ice_crystals(t, 1)]
            for i, p in enumerate(props):
                save("prop_%s_obstacle_%d" % (t, i), p)
            th[t]["obstacles"] = len(props)
        save("secret_crack", K.secret_crack())
        save("secret_rock", K.secret_rock())
        save("secret_hole", K.secret_hole())
    if only in (None, "bg"):
        for t in ("jungle", "tundra", "cave"):
            for v in range(3):
                save("bg_%s_%d" % (t, v), B.background(t, v))
                save("fg_%s_%d" % (t, v), B.foreground(t, v))
    if only in (None, "creatures"):
        for name, cv in C.build_all_raptors().items():
            save(name, cv)
        for name, cv in C.build_enemies().items():
            save(name, cv)
        for name, cv in K.build_spiders().items():
            save(name, cv)
        save("egg_raptor", egg(False))
        save("egg_locked", egg(True))
    if only in (None, "ui"):
        for name, cv in U.make_icons().items():
            save(name, cv)
        for name, cv in U.make_ui().items():
            save(name, cv)
        for f in C.RAPTOR_FORMS:
            if f == "compy":
                continue
            p, _ = U.portrait(f)
            save("portrait_" + f, p)
        for name, cv in KC.make_cards().items():
            save(name, cv)
        cards = json.load(open(os.path.join(ROOT, "data", "cards.json")))
        for i, cid in enumerate(cards):
            if cid in CAVE_CARD_KIND:
                save("card_" + cid, K.card_art(CAVE_CARD_KIND[cid], 10 + i))
                continue
            kind = U.CARD_KIND.get(cid, "claw")
            save("card_" + cid, U.card_art(kind, "adult", seed=10 + i))
    if only in (None, "ui", "items"):
        items = json.load(open(os.path.join(ROOT, "data", "items.json")))["items"]
        for iid, idef in items.items():
            save("item_" + iid, item_icon(idef))
    if only is None:
        tj = {
            "jungle": {"name": "Lush Jungle", "bg_variants": 3, "ground_variants": 6, "tall_variants": 3, "water_variants": 2, "water_frames": 3,
                       "obstacle_variants": max(th["jungle"]["obstacles"], _owned_n("jungle")), "tallgrass_variants": 3,
                       "grid_line": "#d8ffc833", "hover": "#ffffff", "move": "#5cc8ff", "target": "#ff5050", "detect": "#ffe040",
                       "particles": {"type": "pollen", "count": 46, "color": "#f4ffb0", "speed": 6.0, "size": 1},
                       "ambient": "#00000000", "flying_lift": 16, "prop_shadow": "#06180c"},
            "tundra": {"name": "Frozen Verge", "bg_variants": 3, "ground_variants": 6, "tall_variants": 3, "water_variants": 2, "water_frames": 3,
                       "obstacle_variants": max(th["tundra"]["obstacles"], _owned_n("tundra")), "tallgrass_variants": 3,
                       "grid_line": "#7fa8d044", "hover": "#ffffff", "move": "#40b8ff", "target": "#ff5a5a", "detect": "#ffe040",
                       "particles": {"type": "snow", "count": 140, "color": "#ffffff", "speed": 26.0, "size": 2, "wind": 12.0},
                       "ambient": "#20407010", "flying_lift": 16, "prop_shadow": "#18283c"},
        }
        tj["cave"] = {"name": "Spider Cave", "bg_variants": 3, "ground_variants": 6, "tall_variants": 3, "water_variants": 2, "water_frames": 3,
                      "obstacle_variants": max(th["cave"]["obstacles"], _owned_n("cave")), "tallgrass_variants": 3,
                      "grid_line": "#b8a0ff33", "hover": "#ffffff", "move": "#5cc8ff", "target": "#ff5050", "detect": "#ffe040",
                      "particles": {"type": "pollen", "count": 40, "color": "#8af0c8", "speed": 5.0, "size": 1},
                      "ambient": "#10002840", "flying_lift": 16, "prop_shadow": "#06020e"}
        json.dump(tj, open(os.path.join(ROOT, "data", "themes.json"), "w"), indent=1)
    print("wrote", count, "PNGs to", OUT)

main()
