#!/usr/bin/env python3
"""Re-bases the art from the old 960x540 density to the 640x360 native canvas (32x16 iso tile).

    python3 tools/rebase_640.py --snapshot   # (once, right after tools/gen_art.py + tools/import_supplied.py) copy assets/sprites -> tools/art_src_960
    python3 tools/rebase_640.py              # bake tools/art_src_960 -> assets/sprites at the 640x360 density (idempotent, deterministic)

Method (per sprite, see README "Art spec for designers"): every source pixel is classified as object / soft shadow / empty, then
area (box) resampled -> a target pixel is object when >= 45% of its footprint was object (no semi-transparent edge halos), soft shadow stays
2 semi-transparent levels, empty otherwise; colours are the object-weighted average (no dark fringes), then snapped to a shared palette per
group (tiles of a theme, props of a theme, creatures, UI, cards, icons, items). Painted 960x540 backgrounds are box-resampled to 640x360 and
posterised. Target sizes: board art x 32/76, raptors per growth stage (baby 28 / juvenile 33 / adult 37 / prime 40 px wide), enemies
x 0.45 but never narrower than 24 px (the beetle, spiders, shrew... are enlarged relative to the tile so they stay readable), UI x 2/3,
16 px icons -> 11, 20 px item icons -> 13.
Designers: drop a PNG with the same name at the TARGET density straight into assets/sprites/ and skip this script for it (add its name to
tools/art/supplied/owned.txt so the generators leave it alone)."""
import os, sys, re, shutil
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "assets", "sprites")
SRC = os.path.join(HERE, "art_src_960")

BOARD = 32.0 / 76.0
UI = 2.0 / 3.0
RAPTOR_W = {"baby": 28, "juvenile": 33, "adult": 37, "prime": 40, "compy": 30}
ENEMIES = ["beetle", "cave_spider", "compy", "dire_pup", "dragonfly", "glyptodon", "husk_queen", "infected_mammoth", "meganeura", "shrew",
           "skink", "smilodon", "spitter", "spore_drone", "tomb_widow", "web_spitter"]

def rule(name, w, h):
    """-> (target w, target h, group, colours, mode) ; mode: 'sprite' (alpha snapped), 'paint' (opaque / soft alpha kept), 'raw' (no palette)"""
    m = re.match(r"(bg|fg)_(jungle|tundra|cave)_\d$", name)
    if m:
        return 640, 360, "paint_" + name, 48, "paint"
    if name.startswith("tile_"):
        th = name.split("_")[1]
        return 32, 16, "tile_" + th, 48, "tile"
    if name.startswith("prop_"):
        th = name.split("_")[1]
        return max(1, round(w * BOARD)), max(1, round(h * BOARD)), "prop_" + th, 56, "sprite"
    if name.startswith(("deco_", "foliage_", "log_", "secret_", "bd_", "tree_pine", "stump_pine", "fallen_pine")):
        f = BOARD if not name.startswith("bd_") else 0.5
        return max(1, round(w * f)), max(1, round(h * f)), "deco", 56, "sprite"
    if name.startswith("raptor_"):
        st = name.split("_")[1]
        tw = RAPTOR_W.get(st, 37)
        # all poses of one stage share the factor of the stage's main (SE) pose, so the turning sprite never pops in size
        base_w = BASE_W.get("raptor_" + st, w)
        f = tw / float(base_w)
        return max(1, round(w * f)), max(1, round(h * f)), "creatures", 64, "sprite"
    base = re.sub(r"_b$", "", name)
    if base in ENEMIES:
        bw = BASE_W.get(base, w)
        tw = max(24, round(bw * 0.45))
        f = tw / float(bw)
        return max(1, round(w * f)), max(1, round(h * f)), "creatures", 64, "sprite"
    if name.startswith("icon_"):
        return 11, 11, "icons", 32, "sprite"
    if name.startswith("item_"):
        return 13, 13, "items", 40, "sprite"
    if name.startswith("portrait_"):
        return round(w * UI), round(h * UI), "portrait", 0, "raw"
    if name.startswith("card_"):
        return max(1, round(w * UI)), max(1, round(h * UI)), "cards", 56, "sprite"
    if name.startswith("ui_btn"):
        return max(1, round(w * UI)), max(1, round(h * UI)), "ui", 48, "sprite"
    if name.startswith(("ui_", "egg_", "bg_")):
        return max(1, round(w * UI)), max(1, round(h * UI)), "ui", 48, ("paint" if name.startswith("bg_") else "sprite")
    return max(1, round(w * UI)), max(1, round(h * UI)), "ui", 48, "sprite"

BASE_W = {}

def resample(arr, tw, th, mode):
    """arr HxWx4 uint8 -> th x tw x 4 uint8 by the classify / box-resample / threshold method described above."""
    h, w = arr.shape[:2]
    rgb = arr[:, :, :3].astype(np.float64)
    a = arr[:, :, 3].astype(np.float64)
    if mode == "paint":
        pre = rgb * (a[:, :, None] / 255.0)
        im_p = Image.fromarray(np.dstack([pre, a]).astype(np.float32)[:, :, :4].round().astype(np.uint8)[:, :, :3], "RGB") if False else None
        chans = [Image.fromarray(pre[:, :, i].astype(np.float32), "F").resize((tw, th), Image.BOX) for i in range(3)]
        al = Image.fromarray(a.astype(np.float32), "F").resize((tw, th), Image.BOX)
        pr = np.stack([np.asarray(c) for c in chans], 2)
        aa = np.asarray(al)
        out = np.zeros((th, tw, 4), np.uint8)
        nz = aa > 0.5
        out[:, :, :3] = np.where(nz[:, :, None], np.clip(pr / np.maximum(aa, 1.0)[:, :, None] * 255.0, 0, 255), 0).astype(np.uint8)
        out[:, :, 3] = np.clip(aa, 0, 255).astype(np.uint8)
        return out
    obj = (a >= 200).astype(np.float32)
    sh = ((a >= 24) & (a < 200)).astype(np.float32)
    def box(x):
        return np.asarray(Image.fromarray(x.astype(np.float32), "F").resize((tw, th), Image.BOX))
    fo = box(obj)
    fs = box(sh)
    out = np.zeros((th, tw, 4), np.uint8)
    wsum = np.maximum(fo, 1e-6)
    ocol = np.stack([box(rgb[:, :, i] * obj) for i in range(3)], 2) / wsum[:, :, None]
    isobj = fo >= 0.45
    if mode == "tile":
        isobj = fo >= 0.30
    out[isobj, :3] = np.clip(ocol[isobj], 0, 255).astype(np.uint8)
    out[isobj, 3] = 255
    if sh.any():
        ws = np.maximum(fs, 1e-6)
        scol = np.stack([box(rgb[:, :, i] * sh) for i in range(3)], 2) / ws[:, :, None]
        sa = box(a * sh) / ws
        isshadow = (~isobj) & ((fs + fo) >= 0.3) & (fs > 0.1)
        lvl = np.where(sa > 100, 100, 56).astype(np.uint8)
        out[isshadow, :3] = np.clip(scol[isshadow], 0, 255).astype(np.uint8)
        out[isshadow, 3] = lvl[isshadow]
    return out

def palette_of(pixels, n):
    q = Image.fromarray(pixels[None].astype(np.uint8), "RGB").quantize(colors=n, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    return np.array(q.getpalette()[:n * 3], np.uint8).reshape(-1, 3).astype(np.int32)

def snap_to(out, pal):
    m = out[:, :, 3] == 255
    if not m.any():
        return out
    px = out[m][:, :3].astype(np.int32)
    idx = ((px[:, None, :] - pal[None, :, :]) ** 2).sum(2).argmin(1)
    out[m, :3] = pal[idx]
    return out

def diamond_mask(w, h):
    ys, xs = np.mgrid[0:h, 0:w]
    return (np.abs(xs + 0.5 - w / 2) / (w / 2) + np.abs(ys + 0.5 - h / 2) / (h / 2)) <= 1.0

def snapshot():
    os.makedirs(SRC, exist_ok=True)
    open(os.path.join(SRC, ".gdignore"), "w").write("")
    n = 0
    for f in sorted(os.listdir(OUT)):
        if f.endswith(".png"):
            shutil.copy2(os.path.join(OUT, f), os.path.join(SRC, f))
            n += 1
    print("snapshot", n, "pngs ->", SRC)

def bake():
    names = sorted(f[:-4] for f in os.listdir(SRC) if f.endswith(".png"))
    imgs = {n: np.array(Image.open(os.path.join(SRC, n + ".png")).convert("RGBA")) for n in names}
    for n, a in imgs.items():
        BASE_W[n] = a.shape[1]
    # a stage's reference width = its main SE pose (name without a pose suffix)
    for n in names:
        if n.startswith("raptor_"):
            st = n.split("_")[1]
            if "raptor_" + st in imgs:
                BASE_W["raptor_" + st] = imgs["raptor_" + st].shape[1]
    baked = {}
    groups = {}
    for n in names:
        a = imgs[n]
        tw, th, grp, ncol, mode = rule(n, a.shape[1], a.shape[0])
        out = resample(a, tw, th, mode)
        if mode == "tile":
            dm = diamond_mask(tw, th)
            out[~dm] = 0
            hole = dm & (out[:, :, 3] == 0)
            if hole.any():       # fill the diamond completely (no see-through seams)
                ys, xs = np.nonzero(~hole & (out[:, :, 3] == 255))
                for y, x in zip(*np.nonzero(hole)):
                    j = ((ys - y) ** 2 + (xs - x) ** 2).argmin()
                    out[y, x] = out[ys[j], xs[j]]
        baked[n] = (out, grp, ncol, mode)
        groups.setdefault(grp, []).append(n)
    total = 0
    for grp, ns in groups.items():
        ncol = baked[ns[0]][2]
        mode = baked[ns[0]][3]
        if ncol > 0:
            pix = np.concatenate([baked[n][0][baked[n][0][:, :, 3] == 255][:, :3] for n in ns if (baked[n][0][:, :, 3] == 255).any()])
            if len(pix) > 200000:
                pix = pix[np.random.RandomState(1).choice(len(pix), 200000, replace=False)]
            pal = palette_of(pix, ncol)
        for n in ns:
            out = baked[n][0]
            if ncol > 0 and mode != "paint":
                out = snap_to(out, pal)
            elif mode == "paint":
                m = out[:, :, 3] > 0
                out = out.copy()
                out[m, :3] = palette_of(out[m][:, :3], ncol)[((out[m][:, :3].astype(np.int32)[:, None, :] - palette_of(out[m][:, :3], ncol)[None]) ** 2).sum(2).argmin(1)]
            if mode in ("sprite", "tile", "paint", "raw"):
                out[out[:, :, 3] == 0, :3] = 0
            Image.fromarray(out, "RGBA").save(os.path.join(OUT, n + ".png"))
            total += 1
    print("baked", total, "sprites in", len(groups), "palette groups")

if __name__ == "__main__":
    if "--snapshot" in sys.argv:
        snapshot()
    else:
        if not os.path.isdir(SRC):
            sys.exit("no tools/art_src_960 snapshot: run with --snapshot first")
        bake()
