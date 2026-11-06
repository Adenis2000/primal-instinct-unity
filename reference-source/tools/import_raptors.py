#!/usr/bin/env python3
"""Designer Velociraptor sprites (tools/art/supplied/raptor_{a_se,b_nw,c_sw,d_ne}.png, one per iso facing) -> game sprites.
  raptor_<stage>      = SE  (A: faces right, toward the camera)      raptor_<stage>_sw = SW (C: faces left, toward the camera)
  raptor_<stage>_b    = NE  (D: long side pose, faces right)         raptor_<stage>_nw = NW (B: long side pose, faces left)
The same artwork is used for every growth stage and scaled by STAGE_K. Each sprite is downsampled with a box filter to the game's
pixel size, alpha-thresholded (no halo), palette-snapped to one shared palette, trimmed, and padded so the FEET centroid sits on the
canvas centre (the board puts the sprite's bottom-centre on the tile). Portraits (portrait_<stage>) are cut from the SE head."""
import os, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(HERE, "art", "supplied")
OUT = os.path.join(ROOT, "assets", "sprites")
BASE = 0.074                                   # adult scale (source px -> game px): adult long pose ~70 px wide, about one tile
STAGE_K = {"baby": 0.6, "juvenile": 0.8, "adult": 1.0, "prime": 1.1}
POSE = {"": ("raptor_a_se.png", 1.0), "_sw": ("raptor_c_sw.png", 1.2), "_b": ("raptor_d_ne.png", 1.0), "_nw": ("raptor_b_nw.png", 1.0)}
OWNED = []

def load(fn):
    im = Image.open(os.path.join(SRC, fn)).convert("RGBA")
    a = np.array(im)
    m = a[:, :, 3] > 127
    # light fringe pixels on the silhouette edge (anti-aliasing against a white background) -> drop
    for _ in range(2):
        p = np.pad(m, 1)
        edge = m & ~(p[:-2, 1:-1] & p[2:, 1:-1] & p[1:-1, :-2] & p[1:-1, 2:])
        light = (a[:, :, :3].min(2) > 200)
        m = m & ~(edge & light)
    a[:, :, 3] = np.where(m, 255, 0)
    ys, xs = np.nonzero(m)
    a = a[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    return a

def shrink(a, k):
    """Premultiplied box downsample by factor k -> RGBA with binary alpha."""
    h, w = a.shape[:2]
    nw, nh = max(4, int(round(w * k))), max(4, int(round(h * k)))
    al = a[:, :, 3].astype(np.float32) / 255.0
    chans = []
    for i in range(3):
        c = Image.fromarray((a[:, :, i].astype(np.float32) * al), "F").resize((nw, nh), Image.BOX)
        chans.append(np.array(c))
    ar = np.array(Image.fromarray(al, "F").resize((nw, nh), Image.BOX))
    out = np.zeros((nh, nw, 4), np.uint8)
    on = ar >= 0.5
    for i in range(3):
        out[:, :, i] = np.where(on, np.clip(chans[i] / np.maximum(ar, 1e-3), 0, 255), 0).astype(np.uint8)
    out[:, :, 3] = np.where(on, 255, 0)
    return out

EYE = (242, 154, 54)

def eye_mask(a, shape, k):
    """Fraction of each output pixel covered by the source's bright orange eye (so the eye survives the downsample)."""
    r, g, b = a[:, :, 0].astype(int), a[:, :, 1].astype(int), a[:, :, 2].astype(int)
    m = ((r > 180) & (g > 85) & (g < 190) & (b < 75) & ((r - b) > 0.78 * r) & (a[:, :, 3] > 0)).astype(np.float32)
    return np.array(Image.fromarray(m, "F").resize((shape[1], shape[0]), Image.BOX))

def palette_of(imgs, n=30):
    px = np.concatenate([i[i[:, :, 3] > 0][:, :3] for i in imgs])
    sw = Image.fromarray(px.reshape(-1, 1, 3).astype(np.uint8))
    return sw.quantize(colors=n, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)

def snap(a, pal):
    m = a[:, :, 3] > 0
    rgb = Image.fromarray(a[:, :, :3]).quantize(palette=pal, dither=Image.Dither.NONE).convert("RGB")
    o = a.copy()
    o[:, :, :3] = np.where(m[:, :, None], np.array(rgb), 0)
    return o

def anchor(a):
    """Pad so the feet / body centroid is the canvas centre column; trim rows to the opaque bbox."""
    m = a[:, :, 3] > 0
    ys, xs = np.nonzero(m)
    y0, y1 = ys.min(), ys.max()
    a = a[y0:y1 + 1]
    m = m[y0:y1 + 1]
    h, w = m.shape
    feet = m[int(h * 0.88):]
    fx = np.nonzero(feet)[1].mean()
    mx = np.nonzero(m)[1].mean()
    cx = 0.5 * (fx + mx) + 0.5                 # pixel-centre coordinate
    half = int(np.ceil(max(cx, w - cx)))
    W = half * 2
    off = int(round(half - cx))
    out = np.zeros((h, W, 4), np.uint8)
    out[:, off:off + w] = a
    return out

def save(name, arr):
    Image.fromarray(arr).save(os.path.join(OUT, name + ".png"))
    OWNED.append(name)

def build():
    src = {suf: (load(fn), mult) for suf, (fn, mult) in POSE.items()}
    # shared palette from the adult-size images
    ref = [shrink(a, BASE * mult) for a, mult in src.values()]
    pal = palette_of(ref)
    sizes = {}
    for stage, k in STAGE_K.items():
        for suf, (a, mult) in src.items():
            sh = shrink(a, BASE * k * mult)
            em = eye_mask(a, sh.shape[:2], BASE * k * mult)
            s = snap(sh, pal)
            hit = (em >= 0.1) & (s[:, :, 3] > 0)
            if not hit.any() and em.max() > 0.02:
                yy, xx = np.unravel_index(np.argmax(em), em.shape)
                hit[yy, xx] = s[yy, xx, 3] > 0
            s[hit, :3] = EYE
            s = anchor(s)
            save("raptor_%s%s" % (stage, suf), s)
            sizes["raptor_%s%s" % (stage, suf)] = s.shape[1::-1]
    return sizes, pal

# ------------------------------------------------------------------ portraits (HUD card, egg-peek head)
def portraits(pal):
    a = load("raptor_a_se.png")
    h, w = a.shape[:2]
    # head box in the source (right end of the SE pose)
    hx0, hy0 = int(w * 0.745), 0
    head = a[hy0:int(h * 0.60), hx0:w]
    bg = np.array(Image.open(os.path.join(OUT, "portrait_bg_raptor.png")).convert("RGBA"))
    eyes = {}
    for stage, k in STAGE_K.items():
        S = int(round(64 * (0.74 + 0.26 * (k - 0.6) / 0.5) * 0.0 + 64 * (0.62 + 0.38 * (k - 0.6) / 0.5)))
        scale = (S * 0.95) / head.shape[1]
        shh = shrink(head, scale)
        emh = eye_mask(head, shh.shape[:2], scale)
        sm = snap(shh, pal)
        hh_ = (emh >= 0.1) & (sm[:, :, 3] > 0)
        if not hh_.any() and emh.max() > 0.02:
            yy, xx = np.unravel_index(np.argmax(emh), emh.shape)
            hh_[yy, xx] = True
        sm[hh_, :3] = EYE
        canvas = bg.copy()
        hh, ww = sm.shape[:2]
        ox = 64 - ww - (64 - S) // 2 // 2 if ww < 64 else 0
        ox = max(0, min(64 - ww, (64 - ww) // 2 + 2))
        oy = max(0, min(64 - hh, 64 - hh - 4))
        sub = sm[:min(hh, 64 - oy), :min(ww, 64 - ox)]
        m = sub[:, :, 3] > 0
        reg = canvas[oy:oy + sub.shape[0], ox:ox + sub.shape[1]]
        reg[m] = sub[m]
        canvas[:, :, 3] = 255
        save("portrait_%s" % stage, canvas)
        # eye = the brightest orange pixels
        e = np.nonzero((sub[:, :, 0] == EYE[0]) & (sub[:, :, 1] == EYE[1]) & (sub[:, :, 2] == EYE[2]) & m)
        eyes[stage] = (int(e[1].mean()) + ox, int(e[0].mean()) + oy) if len(e[0]) else (ox + ww // 2, oy + hh // 3)
    return eyes

if __name__ == "__main__":
    sizes, pal = build()
    for k, v in sorted(sizes.items()):
        print(k, v)
    print("portrait eyes", portraits(pal))
    p = os.path.join(SRC, "owned.txt")
    cur = set(open(p).read().split())
    open(p, "w").write("\n".join(sorted(cur | set(OWNED))) + "\n")
