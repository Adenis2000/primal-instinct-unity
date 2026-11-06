#!/usr/bin/env python3
"""Slices / cleans the designer-supplied sprite sheets in tools/art/supplied/ into assets/sprites/ PNGs and builds the
game props that use them. Run from the project root (after tools/gen_art.py; both are idempotent):
    python3 tools/import_supplied.py
Needs python3, numpy, pillow, scipy-free (pure numpy)."""
import os, sys, glob, json
import numpy as np
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "art"))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(HERE, "art", "supplied")
OUT = os.path.join(ROOT, "assets", "sprites")
OWNED = []   # names written here (gen_art.py skips them, see art/supplied/owned.txt)

def save(name, im):
    im.save(os.path.join(OUT, name + ".png"))
    OWNED.append(name)

# ----------------------------------------------------------------- helpers
def components(m):
    """4-connected components of a bool mask -> list of (size, mask)."""
    h, w = m.shape
    lab = np.zeros((h, w), np.int32)
    n = 0
    out = []
    for y in range(h):
        for x in range(w):
            if m[y, x] and lab[y, x] == 0:
                n += 1
                st = [(y, x)]
                lab[y, x] = n
                pts = []
                while st:
                    cy, cx = st.pop()
                    pts.append((cy, cx))
                    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        ny, nx = cy + dy, cx + dx
                        if 0 <= ny < h and 0 <= nx < w and m[ny, nx] and lab[ny, nx] == 0:
                            lab[ny, nx] = n
                            st.append((ny, nx))
                mm = np.zeros((h, w), bool)
                ys, xs = zip(*pts)
                mm[list(ys), list(xs)] = True
                out.append((len(pts), mm))
    return out

def dilate(m, r=1):
    o = m.copy()
    for _ in range(r):
        p = np.pad(o, 1)
        o = p[1:-1, 1:-1] | p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:] | p[:-2, :-2] | p[2:, 2:] | p[:-2, 2:] | p[2:, :-2]
    return o

def erode(m, r=1):
    return ~dilate(~m, r)

def fill_holes(m):
    h, w = m.shape
    bg = np.zeros((h, w), bool)
    st = [(y, x) for y in range(h) for x in (0, w - 1)] + [(y, x) for x in range(w) for y in (0, h - 1)]
    st = [(y, x) for (y, x) in st if not m[y, x]]
    for (y, x) in st:
        bg[y, x] = True
    while st:
        cy, cx = st.pop()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = cy + dy, cx + dx
            if 0 <= ny < h and 0 <= nx < w and not m[ny, nx] and not bg[ny, nx]:
                bg[ny, nx] = True
                st.append((ny, nx))
    return ~bg

def snap(rgb, mask, colors):
    """Quantise the foreground to a small palette (removes JPG noise)."""
    ys, xs = np.nonzero(mask)
    if len(ys) == 0:
        return rgb
    pix = Image.fromarray(rgb[ys, xs][None, :, :].astype(np.uint8), "RGB")
    q = pix.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    out = rgb.copy()
    out[ys, xs] = np.array(q)[0]
    return out

def cut(cell_rgb, fg, colors, keep_all_big=False, min_frac=0.04):
    """cell_rgb HxWx3 uint8, fg bool -> RGBA cropped sprite (largest blob(s) only, holes filled, palette snapped)."""
    comps = components(dilate(fg, 1))
    if not comps:
        return None
    comps.sort(key=lambda c: -c[0])
    keep = comps[0][1].copy()
    for sz, mm in comps[1:]:
        if keep_all_big and sz > comps[0][0] * min_frac:
            keep |= mm
    keep = fill_holes(keep) & (fg | erode(keep, 1))
    keep = fill_holes(keep)
    rgb = snap(cell_rgb, keep, colors)
    a = np.where(keep, 255, 0).astype(np.uint8)
    ys, xs = np.nonzero(keep)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    rgba = np.dstack([rgb, a])[y0:y1, x0:x1]
    return Image.fromarray(rgba, "RGBA")

# ----------------------------------------------------------------- foliage (bush / fern sheet, 8 x 4 grid)
def foliage():
    im = np.array(Image.open(os.path.join(SRC, "foliage_sheet.jpg")).convert("RGB")).astype(int)
    H, W, _ = im.shape
    cw, ch = W / 8.0, H / 4.0
    n = 0
    for r in range(4):
        for c in range(8):
            x0, x1 = int(round(c * cw)), int(round((c + 1) * cw))
            y0, y1 = int(round(r * ch)), int(round((r + 1) * ch))
            cell = im[y0:y1, x0:x1]
            sat = cell.max(2) - cell.min(2)
            lum = cell.mean(2)
            fg = (sat > 26) | (lum < 78)
            if fg.sum() < 200:
                continue
            spr = cut(cell.astype(np.uint8), fg, 20)
            if spr is None:
                continue
            n += 1
            save("foliage_%02d" % n, spr)
    return n


# ----------------------------------------------------------------- buttons (START button of the supplied sheet -> blank 9-slice + states)
BTN_M = {"ui_btn": (8, 3, 8, 10), "ui_btn_hover": (8, 3, 8, 10), "ui_btn_disabled": (8, 3, 8, 10),
         "ui_btn_cyan": (8, 3, 8, 10), "ui_btn_cyan_hover": (8, 3, 8, 10), "ui_btn_pressed": (8, 5, 8, 8)}   # left, top, right, bottom

def _is_face(c):
    r, g, b = int(c[0]), int(c[1]), int(c[2])
    return r > b + 22 and r > 90          # tan / red-brown face (the lavender plate and black outline have r <= b + ~20)

def _tone(img, fn):
    out = img.copy()
    h, w, _ = out.shape
    for y in range(h):
        for x in range(w):
            if out[y, x, 3] and _is_face(out[y, x]):
                out[y, x, :3] = fn(out[y, x, :3].astype(float))
    return out

def buttons():
    nat = native(os.path.join(SRC, "buttons_sheet.jpg"), 8.25, 8.25, 0.12, 0.12)
    c = nat[0:21, 7:44].copy()
    h, w, _ = c.shape
    white = c.min(2) > 235
    bg = np.zeros((h, w), bool)
    st = [(0, 0), (0, w - 1), (h - 1, 0), (h - 1, w - 1)]
    for (y, x) in st:
        bg[y, x] = True
    while st:
        y, x = st.pop()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and not bg[ny, nx] and c[ny, nx].min() > 200:
                bg[ny, nx] = True
                st.append((ny, nx))
    tan = np.array([0xcd, 0xa3, 0x73], np.uint8)
    # 1. remove the label: everything inside the face in the text rows becomes plain tan
    for y in range(4, 10):
        for x in range(4, w - 4):
            c[y, x] = tan
    # 2. flat middle: repeat the per-row median of the centre columns across the stretch zone (no stretched cracks / studs)
    L, R = 8, 8
    for y in range(h):
        mid = np.median(c[y, 12:25].astype(int), axis=0).astype(np.uint8)
        c[y, L:w - R] = mid
    rgba = np.dstack([c, np.where(bg, 0, 255).astype(np.uint8)])
    rgba[bg, :3] = 0
    base = rgba
    def lighten(v):
        return np.clip(v * 1.06 + 9, 0, 255)
    def dark(v):
        return np.clip(v * 0.86, 0, 255)
    def teal(v):
        import colorsys
        hh, ss, vv = colorsys.rgb_to_hsv(*(v / 255.0))
        r, g, b = colorsys.hsv_to_rgb((hh + 0.46) % 1.0, min(1.0, ss * 1.15), min(1.0, vv * 1.04 + 0.04))
        return np.array([r, g, b]) * 255
    def teal_hover(v):
        return np.clip(teal(v) * 1.1 + 16, 0, 255)
    def gray(v):
        g = v.mean() * 0.9
        return np.array([g + 6, g + 3, g])
    save("ui_btn", Image.fromarray(base, "RGBA"))
    save("ui_btn_hover", Image.fromarray(_tone(base, lighten), "RGBA"))
    save("ui_btn_cyan", Image.fromarray(_tone(base, teal), "RGBA"))
    save("ui_btn_cyan_hover", Image.fromarray(_tone(base, teal_hover), "RGBA"))
    # disabled: desaturated face and plate
    dis = _tone(base, gray)
    for y in range(h):
        for x in range(w):
            if base[y, x, 3] and not _is_face(base[y, x]) and base[y, x, :3].min() > 60:
                g = base[y, x, :3].mean() * 0.62
                dis[y, x, :3] = (g, g, g + 6)
    save("ui_btn_disabled", Image.fromarray(dis, "RGBA"))
    # pressed: face (rows 0..16 = up to and incl. its bottom outline) sinks 2px into the plate and darkens
    pr = base.copy()
    shifted = _tone(base, dark)
    pr[:] = base
    pr[0:2] = 0
    pr[2:19] = shifted[0:17]
    save("ui_btn_pressed", Image.fromarray(pr, "RGBA"))
    return True

# ----------------------------------------------------------------- upscaled-art -> native pixel grid
def native(path, px, py, ox, oy):
    """The supplied JPGs are pixel art scaled up by ~px: sample the centre of every art pixel to get the real grid back."""
    a = np.array(Image.open(path).convert("RGB")).astype(float)
    W = int((a.shape[1] - ox) / px)
    H = int((a.shape[0] - oy) / py)
    out = np.zeros((H, W, 3))
    for j in range(H):
        for i in range(W):
            x0 = int(ox + i * px + px * 0.28); x1 = max(x0, int(ox + (i + 1) * px - px * 0.28))
            y0 = int(oy + j * py + py * 0.28); y1 = max(y0, int(oy + (j + 1) * py - py * 0.28))
            out[j, i] = np.median(a[y0:y1 + 1, x0:x1 + 1].reshape(-1, 3), axis=0)
    return out.astype(np.uint8)

# ----------------------------------------------------------------- logs (2 bare + 2 mossy, with drop shadow)
def logs():
    nat = native(os.path.join(SRC, "logs_sheet.jpg"), 5.89, 5.89, 1.7, 1.6).astype(int)
    H, W, _ = nat.shape
    n = 0
    # layout: left column bare, right column mossy; top row / bottom row.  log_01/02 bare, log_03/04 mossy
    for (cx, cy) in [(0, 0), (0, 1), (1, 0), (1, 1)]:
        x0, x1 = cx * W // 2, (cx + 1) * W // 2
        y0, y1 = cy * H // 2, (cy + 1) * H // 2
        cell = nat[y0:y1, x0:x1]
        bgc = np.median(cell.reshape(-1, 3), axis=0)
        lum = cell.mean(2)
        sat = cell.max(2) - cell.min(2)
        dark = lum < bgc.mean() - 30
        body = dark | (sat > 34)
        shadow = ~body & (lum < bgc.mean() - 7)
        comps = components(dilate(body, 1))
        comps.sort(key=lambda c: -c[0])
        keep = fill_holes(comps[0][1] & dilate(body, 0) | (comps[0][1] & body))
        keep = fill_holes(dilate(keep, 0))
        keep &= body | erode(keep, 1)
        rgb = snap(cell.astype(np.uint8), keep, 22)
        # shadow = darker than the ground and touching the log; keep as flat semi-transparent
        sh = shadow & dilate(keep, 6)
        ys, xs = np.nonzero(keep | sh)
        ty0, ty1, tx0, tx1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
        rgba = np.zeros((cell.shape[0], cell.shape[1], 4), np.uint8)
        rgba[sh] = (8, 12, 10, 100)
        rgba[keep, :3] = rgb[keep]
        rgba[keep, 3] = 255
        n += 1
        save("log_%02d" % n, Image.fromarray(rgba[ty0:ty1, tx0:tx1], "RGBA"))
    return n



# ----------------------------------------------------------------- health bar (frame / fill / slim variant; number tab text removed)
def hpbar():
    """Supplied bar -> ui_bar_frame (110x34, wing + number tab, fill window transparent), ui_bar_slim (102x12, same frame without
    wing/tab), ui_bar_fill_{hp,stamina,hunger} (24x5 tileable fill).  Geometry (design px) is documented in the README and mirrored
    in scripts/ui/BarSprite.gd."""
    import colorsys
    nat = native(os.path.join(SRC, "hpbar_sheet.jpg"), 4.41, 4.41, 0.15, 1.6).astype(int)
    c = nat[69:103, 30:140].copy()
    h, w, _ = c.shape
    bgc = nat[2, 2]
    isbg = (np.abs(c - bgc).sum(2) < 30)
    bg = np.zeros((h, w), bool)
    st = [(y, x) for y in range(h) for x in (0, w - 1)] + [(y, x) for x in range(w) for y in (0, h - 1)]
    st = [(y, x) for (y, x) in st if isbg[y, x]]
    for (y, x) in st:
        bg[y, x] = True
    while st:
        y, x = st.pop()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and isbg[ny, nx] and not bg[ny, nx]:
                bg[ny, nx] = True
                st.append((ny, nx))
    # palette snap (JPG noise)
    fgm = ~bg
    rgb = snap(c.astype(np.uint8), fgm, 18).astype(int)
    tab = rgb[24, 60].copy()
    rgb[20:27, 28:59] = tab                      # number text -> plain tab colour (rendered live in Jersey)
    # fill source tile (before the window is cut out)
    fill = rgb[10:15, 20:44].copy()
    a = np.where(bg, 0, 255).astype(np.uint8)
    a[10:15, 14:103] = 0                          # fill window
    frame = np.dstack([rgb.astype(np.uint8), a])
    red = (frame[:, :, 0].astype(int) > frame[:, :, 1].astype(int) + 22) & (frame[:, :, 3] > 0) & (np.arange(h)[:, None] >= 9) & (np.arange(h)[:, None] <= 16) & (np.arange(w)[None, :] >= 12)
    frame[red, :3] = rgb[16, 60]                 # stray fill-coloured pixels beside the window
    frame[a == 0, :3] = 0
    save("ui_bar_frame", Image.fromarray(frame, "RGBA"))
    slim = frame[7:19, 8:110].copy()
    slim[8:, :3, :] = 0                          # the wing / medallion remnant under the left tip
    save("ui_bar_slim", Image.fromarray(slim, "RGBA"))
    def recolor(img, dh, sm=1.0, vm=1.0):
        out = img.astype(float).copy()
        for y in range(out.shape[0]):
            for x in range(out.shape[1]):
                r, g, b = out[y, x] / 255.0
                hh, ss, vv = colorsys.rgb_to_hsv(r, g, b)
                r, g, b = colorsys.hsv_to_rgb((hh + dh) % 1.0, min(1.0, ss * sm), min(1.0, vv * vm))
                out[y, x] = (r * 255, g * 255, b * 255)
        return out.astype(np.uint8)
    for nm, arr in (("hp", fill.astype(np.uint8)), ("stamina", recolor(fill, 0.34, 1.6, 1.0)), ("hunger", recolor(fill, 0.105, 2.3, 1.1))):
        save("ui_bar_fill_" + nm, Image.fromarray(arr, "RGB").convert("RGBA"))
    return True


# ----------------------------------------------------------------- jungle iso sheet (trees, bushes, tufts, rocks, props, 32 grass ground tiles)
ISO_ROWS = [  # (name pattern, expected count)
    ("deco_tree_%02d", 6), ("deco_tree_%02d", 6), ("deco_bush_%02d", 9), ("deco_tuft_%02d", 9), ("deco_rock_%02d", 7),
    ("deco_misc", 9), ("deco_small_%02d", 9), ("tile", 8), ("tile", 8), ("tile", 8), ("tile", 8)]
MISC_NAMES = ["deco_stump_01", "deco_hollowlog_01", "deco_log_01", "deco_branch_01", "deco_pebbles_01", "deco_leafpile_01", "deco_woodpile_01", "deco_fence_01", "deco_fence_02"]
ISO_SCALE = 76.0 / 79.0          # the sheet's ground tile is ~79 px wide, the game tile 76 px: whole sheet scaled consistently

def _runs(a, gap=3):
    r = []; s = None; last = None
    for i, v in enumerate(a):
        if v:
            if s is None:
                s = i
            last = i
        elif s is not None and i - last > gap:
            r.append((s, last)); s = None
    if s is not None:
        r.append((s, last))
    return r

def _iso_cell(im, x0, x1, y0, y1):
    """RGBA sprite cut from one cell of the white-background sheet: flood-filled background -> transparent, soft grey shadow -> semi-transparent."""
    cell = im[y0:y1 + 1, x0:x1 + 1]
    h, w, _ = cell.shape
    lum = cell.mean(2)
    sat = cell.max(2) - cell.min(2)
    near_white = (cell.min(2) >= 226)
    bg = np.zeros((h, w), bool)
    st = [(y, x) for y in range(h) for x in (0, w - 1)] + [(y, x) for x in range(w) for y in (0, h - 1)]
    st = [(y, x) for (y, x) in st if near_white[y, x]]
    for (y, x) in st:
        bg[y, x] = True
    while st:
        y, x = st.pop()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and near_white[ny, nx] and not bg[ny, nx]:
                bg[ny, nx] = True
                st.append((ny, nx))
    shadow = (~bg) & (lum > 196) & (sat < 18)
    a = np.where(bg, 0, 255).astype(np.uint8)
    rgb = cell.astype(np.uint8).copy()
    sh_a = np.clip((250 - lum) * 3.0, 0, 150).astype(np.uint8)
    a[shadow] = sh_a[shadow]
    rgb[shadow] = (14, 28, 16)
    # hard edge: drop faint fringe pixels next to the background (JPG halo)
    solid = a == 255
    return np.dstack([rgb, a]), solid

def iso_sheet():
    im = np.array(Image.open(os.path.join(SRC, "jungle_iso_sheet.jpg")).convert("RGB")).astype(int)
    H, W, _ = im.shape
    fg = (im.min(2) < 226)
    rows = _runs(fg.any(1), 3)
    assert len(rows) == len(ISO_ROWS), len(rows)
    tiles = []
    counts = {}
    for ri, (ry0, ry1) in enumerate(rows):
        cols = _runs(fg[ry0:ry1 + 1].any(0), 3)
        pat, n = ISO_ROWS[ri]
        assert len(cols) == n, (ri, len(cols))
        for ci, (cx0, cx1) in enumerate(cols):
            rgba, solid = _iso_cell(im, max(0, cx0 - 2), min(W - 1, cx1 + 2), max(0, ry0 - 2), min(H - 1, ry1 + 2))
            spr = Image.fromarray(rgba, "RGBA")
            ys, xs = np.nonzero(rgba[:, :, 3] > 0)
            spr = spr.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
            if pat == "tile":
                tiles.append(spr)
                continue
            nw, nh = max(1, round(spr.width * ISO_SCALE)), max(1, round(spr.height * ISO_SCALE))
            r = spr.resize((nw, nh), Image.LANCZOS)
            ra = np.array(r)
            # re-binarise the object alpha (crisp edges) but keep the semi-transparent shadow values
            sh = (ra[:, :, 3] > 0) & (ra[:, :, 3] < 200)
            ra[:, :, 3] = np.where(ra[:, :, 3] >= 200, 255, np.where(sh & (ra[:, :, 3] > 24), ra[:, :, 3], 0))
            objm = ra[:, :, 3] == 255
            ra[:, :, :3] = np.array(snap(ra[:, :, :3], objm, 40))
            if pat == "deco_misc":
                name = MISC_NAMES[ci]
            else:
                counts[pat] = counts.get(pat, 0) + 1
                name = pat % counts[pat]
            save(name, Image.fromarray(ra, "RGBA"))
    # ---- ground tiles -> 76x38 diamonds, no gaps
    TWd, THd = 76, 38
    ys_, xs_ = np.mgrid[0:THd, 0:TWd]
    diamond = (np.abs(xs_ + 0.5 - TWd / 2) / (TWd / 2) + np.abs(ys_ + 0.5 - THd / 2) / (THd / 2)) <= 1.0
    cats = []
    for i, t in enumerate(tiles):
        nw, nh = round(t.width * ISO_SCALE), round(t.height * ISO_SCALE)
        r = np.array(t.resize((nw, nh), Image.LANCZOS))
        oy = max(0, (nh - THd) // 2)
        ox = max(0, (nw - TWd) // 2)
        c = r[oy:oy + THd, ox:ox + TWd, :3]
        if c.shape[0] < THd or c.shape[1] < TWd:
            c = np.pad(c, ((0, THd - c.shape[0]), (0, TWd - c.shape[1]), (0, 0)), mode="edge")
        c = snap(c.copy(), np.ones(c.shape[:2], bool), 28)
        a = np.where(diamond, 255, 0).astype(np.uint8)
        save("tile_grass_%02d" % (i + 1), Image.fromarray(np.dstack([c, a]), "RGBA"))
        # category: plain grass / dirt / flowers+pebbles
        px = c[diamond].astype(int)
        brown = ((px[:, 0] > px[:, 1] + 6) & (px[:, 0] > px[:, 2] + 30)).mean()
        odd = ((px[:, 1] < px[:, 0] + 8) & ~((px[:, 0] > px[:, 1] + 6))).mean() + ((px.max(1) - px.min(1) < 22) & (px.mean(1) > 120)).mean() * 0 
        bright = ((px[:, 2] > px[:, 1] + 10) | (px.min(1) > 175)).mean()
        cats.append((brown, bright))
    return cats

# ----------------------------------------------------------------- props built from the sliced sprites
TW = 76
BASE_OBS = {"jungle": 9, "tundra": 10, "cave": 11}      # obstacle count tools/gen_art.py generates per theme (appended variants follow)

def load(name):
    return Image.open(os.path.join(OUT, name + ".png")).convert("RGBA")

def shadow_ellipse(canvas, cx, cy, rx, ry, alpha=95, col=(6, 20, 10)):
    a = np.array(canvas)
    ys, xs = np.mgrid[0:a.shape[0], 0:a.shape[1]]
    m = ((xs - cx) / rx) ** 2 + ((ys - cy) / ry) ** 2 <= 1.0
    sel = m & (a[:, :, 3] < alpha)
    a[sel] = (col[0], col[1], col[2], alpha)
    return Image.fromarray(a, "RGBA")

def frost(im, amt=0.5, snow_rows=3, tint=(0.80, 0.90, 1.05)):
    """Snow-dusted look: desaturate towards ice blue, white cap on the upward facing edge of the silhouette."""
    a = np.array(im).astype(float)
    op = a[:, :, 3] > 0
    gray = a[:, :, :3].mean(2, keepdims=True)
    a[:, :, :3] = np.clip((a[:, :, :3] * (1 - amt) + gray * amt) * np.array(tint)[None, None, :] + 14, 0, 255)
    h, w = op.shape
    for x in range(w):
        col = np.nonzero(op[:, x])[0]
        if len(col) == 0:
            continue
        top = col.min()
        for k in range(snow_rows):
            y = top + k
            if y < h and op[y, x]:
                t = 0.9 - 0.22 * k
                a[y, x, :3] = a[y, x, :3] * (1 - t) + np.array([240, 246, 255]) * t
    return Image.fromarray(a.astype(np.uint8), "RGBA")

def darken_cave(im):
    a = np.array(im).astype(float)
    a[:, :, :3] = np.clip(a[:, :, :3] * np.array([0.62, 0.58, 0.8]), 0, 255)
    return Image.fromarray(a.astype(np.uint8), "RGBA")

def prop_from(spr, h, dy=0, shadow=True, bush=True):
    """76 x h prop canvas, art centred on the tile footprint (tile diamond = bottom 38 rows, centre at h-19)."""
    c = Image.new("RGBA", (TW, h), (0, 0, 0, 0))
    if shadow:
        c = shadow_ellipse(c, 38, h - 17, min(28, spr.width * 0.5), 8)
    x = (TW - spr.width) // 2
    y = h - 10 - spr.height + dy
    c.alpha_composite(spr, (x, max(0, y)))
    return c

def fern_tall(v, front):
    """Tall-grass tile cover from the fern sprites (76x52). Front = lower leaves only, drawn over units standing in the tile."""
    import random
    rng = random.Random(900 + v)
    ferns = [load("foliage_%02d" % i) for i in range(21, 31)]
    small = [f for f in ferns if f.width <= 46]
    big = [f for f in ferns if f.width > 46]
    h = 52
    back = Image.new("RGBA", (TW, h), (0, 0, 0, 0))
    fr = Image.new("RGBA", (TW, h), (0, 0, 0, 0))
    b = rng.choice(big)
    back.alpha_composite(b, (38 - b.width // 2 + rng.randint(-3, 3), h - 17 - b.height + 8))
    for sx in (21, 55):
        sm = rng.choice(small)
        fr.alpha_composite(sm, (sx - sm.width // 2 + rng.randint(-3, 3), h - 5 - sm.height + rng.randint(-2, 1)))
    if not front:
        out = Image.new("RGBA", (TW, h), (0, 0, 0, 0))
        out = shadow_ellipse(out, 38, h - 14, 26, 8, 70)
        out.alpha_composite(back)
        out.alpha_composite(fr)
        return out
    a = np.array(fr)
    a[: h - 15] = 0          # only the lowest leaves overlap a unit
    return Image.fromarray(a, "RGBA")

def deco_prop(name, pad=13):
    """Obstacle prop from a sliced deco sprite: canvas as wide as the art, bottom padded so the sprite's grass patch sits on the tile."""
    spr = load(name)
    c = Image.new("RGBA", (spr.width, spr.height + pad), (0, 0, 0, 0))
    c.alpha_composite(spr, (0, 0))
    return c

def tuft_tall(v, front):
    """Tall-grass cover from the sheet's grass tufts: 4 tufts per tile (76x56). Front = the two lowest tufts, lowest rows only."""
    import random
    rng = random.Random(4100 + v * 17)
    names = ["deco_tuft_01", "deco_tuft_03", "deco_tuft_05", "deco_tuft_06", "deco_tuft_07", "deco_tuft_08", "deco_tuft_09"]
    h = 56
    back = Image.new("RGBA", (TW, h), (0, 0, 0, 0))
    fr = Image.new("RGBA", (TW, h), (0, 0, 0, 0))
    for (px, py, layer) in ((38, h - 34, back), (19, h - 25, back), (57, h - 25, back), (38, h - 15, fr), (22, h - 12, fr), (54, h - 12, fr)):
        t = load(rng.choice(names))
        # bottom of the sprite = py (its grass patch is the tile footprint)
        layer.alpha_composite(t, (px - t.width // 2, py - t.height + 6))
    if not front:
        out = back.copy()
        out.alpha_composite(fr)
        return out
    a = np.array(fr)
    a[: h - 17] = 0
    return Image.fromarray(a, "RGBA")

def jungle_iso(cats):
    j = "jungle"
    # ---- ground: the 32 supplied tiles are the jungle floor variants
    nt = len(cats)
    for i in range(nt):
        save("tile_%s_ground_%d" % (j, i), load("tile_grass_%02d" % (i + 1)))
    # plain = lowest texture variance; dirt = brown; the rest = flowers / pebbles
    var = []
    for i in range(nt):
        a = np.array(load("tile_grass_%02d" % (i + 1)))
        px = a[a[:, :, 3] > 0][:, :3].astype(float)
        var.append(px.mean(1).std())
    order = sorted([i for i in range(nt) if cats[i][0] < 0.1], key=lambda i: var[i])
    plain = order[:8]
    dirt = [i for i in range(nt) if cats[i][0] >= 0.1]
    other = [i for i in range(nt) if i not in plain and i not in dirt]
    pool = []
    for i in plain:
        pool += [i] * 6
    for i in other:
        pool += [i]
    for i in dirt:
        pool += [i]
    # darker, denser tall-grass base tiles from three plain tiles
    for v in range(3):
        a = np.array(load("tile_grass_%02d" % (plain[v] + 1))).astype(float)
        a[:, :, 0] *= 0.62; a[:, :, 1] *= 0.80; a[:, :, 2] *= 0.58
        save("tile_%s_tall_%d" % (j, v), Image.fromarray(a.astype(np.uint8), "RGBA"))
    # ---- tall grass from the tufts
    for v in range(3):
        save("prop_%s_tallgrass_%d" % (j, v), tuft_tall(v, False))
        save("prop_%s_tallgrass_front_%d" % (j, v), tuft_tall(v, True))
    # ---- obstacles: this sheet's art takes priority (indices 0,1 rocks; 6,7 flowering bushes), the rest is appended
    save("prop_%s_obstacle_0" % j, deco_prop("deco_rock_03"))
    save("prop_%s_obstacle_1" % j, deco_prop("deco_rock_06" if False else "deco_rock_05"))
    save("prop_%s_obstacle_6" % j, deco_prop("deco_bush_01"))
    save("prop_%s_obstacle_7" % j, deco_prop("deco_bush_03"))
    names = ["deco_tree_%02d" % k for k in range(1, 13)] + ["deco_bush_02", "deco_bush_04", "deco_bush_05", "deco_bush_06"] + \
            ["deco_rock_01", "deco_rock_02", "deco_rock_04", "deco_rock_06", "deco_rock_07"] + \
            ["deco_stump_01", "deco_hollowlog_01", "deco_log_01", "deco_woodpile_01", "deco_fence_01", "deco_fence_02", "deco_branch_01"]
    base = BASE_OBS[j] + 7          # 0..15 = generated + earlier supplied sheets
    for k, nm in enumerate(names):
        save("prop_%s_obstacle_%d" % (j, base + k), deco_prop(nm))
    idx = {nm: base + k for k, nm in enumerate(names)}
    trees = [idx["deco_tree_%02d" % k] for k in range(1, 13)]
    bushes = [6, 7] + [idx[n] for n in ("deco_bush_02", "deco_bush_04", "deco_bush_05", "deco_bush_06")] + [9, 10, 11, 12, 15]
    rocks = [0, 1] + [idx[n] for n in ("deco_rock_01", "deco_rock_02", "deco_rock_04", "deco_rock_06", "deco_rock_07")]
    logs = [2, 3, 13, 14, idx["deco_hollowlog_01"], idx["deco_log_01"], idx["deco_stump_01"]]
    misc = [4, 5, idx["deco_woodpile_01"], idx["deco_fence_01"], idx["deco_fence_02"], idx["deco_branch_01"]]
    border = trees + trees[:6] + rocks + bushes + logs + misc + [8, 8]
    interior = rocks + rocks[:4] + bushes + bushes[:6] + logs + misc
    decor_ring = ["deco_small_01", "deco_small_02", "deco_small_03", "deco_small_04", "deco_small_05", "deco_small_06", "deco_small_07", "deco_small_08",
                  "deco_small_09", "deco_pebbles_01", "deco_leafpile_01", "deco_tuft_02", "deco_tuft_04", "deco_tuft_03", "deco_tuft_08"]
    decor_interior = ["deco_pebbles_01", "deco_small_01", "deco_small_05", "deco_small_06", "deco_small_04", "deco_leafpile_01"]
    tp = os.path.join(ROOT, "data", "themes.json")
    th = json.load(open(tp))
    th[j].update({"ground_variants": nt, "ground_pool": pool, "obstacle_variants": base + len(names), "obstacle_pool": border,
                  "obstacle_pool_interior": interior, "decor_ring": decor_ring, "decor_interior": decor_interior})
    json.dump(th, open(tp, "w"), indent=1)
    return base + len(names)

def props():
    n = {}
    # ---- jungle: mossy logs, round bushes, fern tall grass
    j = "jungle"
    save("prop_%s_obstacle_2" % j, prop_from(load("log_03"), 52, dy=8, shadow=False))
    save("prop_%s_obstacle_3" % j, prop_from(load("log_04"), 52, dy=8, shadow=False))
    save("prop_%s_obstacle_6" % j, prop_from(load("foliage_03"), 64))
    save("prop_%s_obstacle_7" % j, prop_from(load("foliage_05"), 64))
    extra = [("foliage_01", 64), ("foliage_12", 64), ("foliage_10", 64), ("foliage_14", 64), ("log_01", 52), ("log_02", 52), ("foliage_17", 60)]
    for k, (nm, hh) in enumerate(extra):
        save("prop_%s_obstacle_%d" % (j, BASE_OBS[j] + k), prop_from(load(nm), hh, dy=8 if nm.startswith("log") else 0, shadow=not nm.startswith("log")))
    n[j] = BASE_OBS[j] + len(extra)
    for v in range(3):
        save("prop_%s_tallgrass_%d" % (j, v), fern_tall(v, False))
        save("prop_%s_tallgrass_front_%d" % (j, v), fern_tall(v, True))
    # ---- tundra: bare logs with a snow cap, frosted bushes
    t = "tundra"
    save("prop_%s_obstacle_2" % t, prop_from(frost(load("log_01"), 0.25, 2), 52, dy=8, shadow=False))
    save("prop_%s_obstacle_3" % t, prop_from(frost(load("log_02"), 0.25, 2), 52, dy=8, shadow=False))
    extra = [("foliage_12", 64), ("foliage_17", 60), ("foliage_06", 64)]
    for k, (nm, hh) in enumerate(extra):
        save("prop_%s_obstacle_%d" % (t, BASE_OBS[t] + k), prop_from(frost(load(nm), 0.55, 4), hh, shadow=False))
    n[t] = BASE_OBS[t] + len(extra)
    # ---- cave: dark bare logs (keeps its own foliage-free look)
    c = "cave"
    save("prop_%s_obstacle_%d" % (c, BASE_OBS[c]), prop_from(darken_cave(load("log_01")), 52, dy=8, shadow=False))
    save("prop_%s_obstacle_%d" % (c, BASE_OBS[c] + 1), prop_from(darken_cave(load("log_02")), 52, dy=8, shadow=False))
    n[c] = BASE_OBS[c] + 2
    # themes.json: obstacle counts
    tp = os.path.join(ROOT, "data", "themes.json")
    th = json.load(open(tp))
    for k, v in n.items():
        th[k]["obstacle_variants"] = v
    json.dump(th, open(tp, "w"), indent=1)
    return n

# ----------------------------------------------------------------- egg + nest scene
EGG_SCENE = (120, 162)      # native size of bg_customize (drawn at 5x = 600x810 screen px)

def egg_scene():
    """Portrait jungle scene (cream egg with brown spots in a twig/fern nest) -> egg sprite, empty-nest backdrop, nest crop."""
    src = os.path.join(SRC, "egg_nest_scene.jpg")
    im = Image.open(src).convert("RGB")
    W, H = EGG_SCENE
    q = im.resize((W, H), Image.BOX).quantize(colors=48, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    a = np.array(q).astype(int)
    lum = a.mean(2)
    sat = a.max(2) - a.min(2)
    # the egg = the light region inside the dark hollow: flood from its centre through "not dark" pixels, inside an egg-sized ellipse
    yy, xx = np.mgrid[0:H, 0:W]
    ell = ((xx - 60.0) / 18.5) ** 2 + ((yy - 97.0) / 21.5) ** 2 <= 1.0
    cream = (lum > 100) & ell & (a[:, :, 1] >= a[:, :, 2] + 10)
    comps = components(cream)
    comps.sort(key=lambda c: -c[0])
    m = comps[0][1]
    m = erode(dilate(m, 2), 2)
    m = fill_holes(m)                      # the brown spots are holes in the cream mask
    # smooth the silhouette: per-row extents, moving-averaged, so the shell edge is one clean egg curve
    ys0, xs0 = np.nonzero(m)
    r0, r1 = ys0.min(), ys0.max()
    Ls = np.array([np.nonzero(m[y])[0].min() if m[y].any() else np.nan for y in range(r0, r1 + 1)], float)
    Rs = np.array([np.nonzero(m[y])[0].max() if m[y].any() else np.nan for y in range(r0, r1 + 1)], float)
    def sm(v):
        o = v.copy()
        for i in range(len(v)):
            seg = v[max(0, i - 2):i + 3]
            o[i] = np.nanmedian(seg)
        return o
    Ls, Rs = sm(Ls), sm(Rs)
    m = np.zeros_like(m)
    for i, y in enumerate(range(r0, r1 + 1)):
        m[y, int(round(Ls[i])):int(round(Rs[i])) + 1] = True
    ys, xs = np.nonzero(m)
    y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
    cx = (x0 + x1) / 2.0
    print("egg bbox", x0, x1, y0, y1, "centre-x %.1f bottom %d" % (cx, y1))
    # ---- egg sprite: mask + 1px dark outline, transparent elsewhere
    ring = dilate(m, 1) & ~m
    h, w = y1 - y0 + 3, x1 - x0 + 3
    egg = np.zeros((h, w, 4), np.uint8)
    sub = a[y0 - 1:y1 + 2, x0 - 1:x1 + 2]
    mm = m[y0 - 1:y1 + 2, x0 - 1:x1 + 2]
    rr = ring[y0 - 1:y1 + 2, x0 - 1:x1 + 2]
    egg[mm, :3] = sub[mm]
    egg[mm, 3] = 255
    egg[rr] = (43, 27, 16, 255)
    save("egg_raptor", Image.fromarray(egg))
    # locked eggs: the same egg as a cool grey silhouette with darker spots
    g = egg.astype(float)
    lum2 = (g[:, :, 0] * 0.3 + g[:, :, 1] * 0.5 + g[:, :, 2] * 0.2)
    lk = np.stack([lum2 * 0.62 + 12, lum2 * 0.66 + 16, lum2 * 0.82 + 30, g[:, :, 3]], 2)
    lk[(egg[:, :, 3] == 255) & (egg[:, :, 0] == 43) & (egg[:, :, 1] == 27)] = (22, 26, 40, 255)
    save("egg_locked", Image.fromarray(np.clip(lk, 0, 255).astype(np.uint8)))
    # ---- empty-nest backdrop: paint the egg out with the dark hollow colours around it
    hole = dilate(m, 2)
    ring2 = dilate(hole, 4) & ~hole
    dark = [tuple(a[y, x]) for y, x in zip(*np.nonzero(ring2)) if lum[y, x] < 95]
    if not dark:
        dark = [(46, 31, 18)]
    rng = np.random.RandomState(5)
    bg = a.copy()
    for y, x in zip(*np.nonzero(hole)):
        bg[y, x] = dark[rng.randint(len(dark))]
    # a few twig strokes across the hollow so it does not look like a flat blob
    tw = [(x0 - 1, y1 - 6, x1 + 1, y1 - 3, (88, 60, 34)), (x0 + 2, y0 + 9, x1 - 4, y0 + 5, (70, 48, 28))]
    for xa, ya, xb, yb, col in tw:
        for t in np.linspace(0, 1, 40):
            xx, yy = int(round(xa + (xb - xa) * t)), int(round(ya + (yb - ya) * t))
            if hole[yy, xx]:
                bg[yy, xx] = col
    save("bg_customize", Image.fromarray(bg.astype(np.uint8)))
    # ---- nest crop (egg-less) with a dithered elliptical edge, used under the egg-select icons
    ncx, ncy, rx, ry = 60.0, 107.0, 58.0, 42.0
    nh, nw = 86, 118
    oy, ox = int(ncy - nh / 2), int(ncx - nw / 2)
    crop = np.zeros((nh, nw, 4), np.uint8)
    bay = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
    for y in range(nh):
        for x in range(nw):
            d = np.hypot((x + ox - ncx) / rx, (y + oy - ncy) / ry)
            thr = (bay[y % 4][x % 4] + 0.5) / 16.0
            edge = np.clip((1.0 - d) / 0.16, 0, 1)     # 0 outside -> 1 inside, ~9px feather
            if edge > thr:
                crop[y, x, :3] = bg[y + oy, x + ox]
                crop[y, x, 3] = 255
    save("bg_egg_nest", Image.fromarray(crop))
    return {"cx": float(cx), "bottom": int(y1), "w": w, "h": h}


# ----------------------------------------------------------------- pine trees (@kianamosser): 4 trees, 4 stumps, 2 fallen pines
PINE_SCALE = 736 / 280.0          # the 736x736 JPG is a 280x280 pixel-art sheet enlarged by ~2.63 (found by edge-phase analysis)
PINE_BOXES = {                    # native-grid boxes (x0, y0, x1, y1); the "@KIANAMOSSER" watermark (y >= 262) is never inside a box
    "tree_pine_01": (16, 38, 77, 154), "tree_pine_02": (74, 16, 145, 154), "tree_pine_03": (143, 38, 200, 154), "tree_pine_04": (198, 16, 270, 154),
    "stump_pine_01": (27, 156, 64, 186), "stump_pine_02": (88, 156, 125, 186), "stump_pine_03": (152, 156, 189, 186), "stump_pine_04": (212, 156, 249, 186),
    "fallen_pine_01": (16, 190, 140, 250), "fallen_pine_02": (146, 190, 270, 250)}

def pine_native(path=None):
    """The sheet at its true pixel grid (280x280): every art pixel is the median of a small window at its centre (kills JPG noise)."""
    A = np.array(Image.open(path or os.path.join(SRC, "pine_sheet.jpg")).convert("RGB")).astype(float)
    k = A.shape[0] / 280.0
    L = A.mean(2)
    def phase(g):
        ph = np.exp(-2j * np.pi * np.arange(len(g)) / k)
        return ((np.angle((g * ph).sum()) / (2 * np.pi)) % 1.0 * k + 1) % k
    px = phase(np.abs(np.diff(L, axis=1)).sum(0) + 0.5)
    py = phase(np.abs(np.diff(L, axis=0)).sum(1) + 0.5)
    N = 280
    out = np.zeros((N, N, 3), np.uint8)
    for j in range(N):
        for i in range(N):
            cx = px + (i - 0.5) * k; cy = py + (j - 0.5) * k
            x0 = max(0, int(round(cx - 0.6))); x1 = min(A.shape[1], max(int(round(cx + 0.6)) + 1, x0 + 1))
            y0 = max(0, int(round(cy - 0.6))); y1 = min(A.shape[0], max(int(round(cy + 0.6)) + 1, y0 + 1))
            out[j, i] = np.median(A[y0:y1, x0:x1].reshape(-1, 3), axis=0)
    return out

def pines():
    """Slices the 10 pine sprites: gray background -> transparent (no JPG halo: an edge pixel is either art or background), the soft ground shadow
    under the trunks / logs stays semi-transparent, palette snapped (one shared 40-colour palette). Saved at the sheet's NATIVE pixel density
    (tree_pine_01..04, stump_pine_01..04, fallen_pine_01..02); tools/rebase_640.py resamples them for the 32x16 tile like every other board sprite."""
    nat = pine_native().astype(float)
    bg = np.median(nat[6:-6, 6:-6].reshape(-1, 3), axis=0)
    dist = np.sqrt(((nat - bg) ** 2).sum(2))
    lum = nat.mean(2)
    obj = dist > 16
    obj[:6] = False; obj[-6:] = False; obj[:, :6] = False; obj[:, -6:] = False
    obj[258:, :] = False                                   # watermark rows
    # shadow = clearly darker than the ground, grey (no hue), and close to the art
    shadow_raw = (~obj) & (dist > 5) & (lum < bg.mean() - 4)
    shadow_raw[258:, :] = False
    shadow = shadow_raw & dilate(obj, 7)
    sprites = {}
    allpix = []
    for name, (x0, y0, x1, y1) in PINE_BOXES.items():
        m = obj[y0:y1, x0:x1].copy()
        comps = components(dilate(m, 1))
        comps.sort(key=lambda c: -c[0])
        keep = comps[0][1] & (m | dilate(m, 0))
        for sz, mm in comps[1:]:
            if sz > comps[0][0] * 0.04:
                keep |= mm & m
        keep = fill_holes(keep) & (m | erode(keep, 1))
        keep = fill_holes(keep)
        for _ in range(2):          # peel JPG halo: edge pixels that are still bg-coloured (gray, light) are not art
            edge = keep & ~erode(keep, 1)
            sat_ = nat[y0:y1, x0:x1].max(2) - nat[y0:y1, x0:x1].min(2)
            keep = keep & ~(edge & (dist[y0:y1, x0:x1] < 46) & (sat_ < 30) & (lum[y0:y1, x0:x1] > bg.mean() - 8))
        sh = shadow[y0:y1, x0:x1] & ~keep
        sprites[name] = (nat[y0:y1, x0:x1], keep, sh, lum[y0:y1, x0:x1])
        allpix.append(nat[y0:y1, x0:x1][keep])
    pix = np.concatenate(allpix)
    q = Image.fromarray(pix[None].astype(np.uint8), "RGB").quantize(colors=40, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    pal = np.array(q.getpalette()[:120], np.uint8).reshape(-1, 3).astype(int)
    for name, (rgb, keep, sh, l) in sprites.items():
        h, w = keep.shape
        out = np.zeros((h, w, 4), np.uint8)
        px = rgb[keep].astype(int)
        idx = ((px[:, None, :] - pal[None, :, :]) ** 2).sum(2).argmin(1)
        out[keep, :3] = pal[idx]
        out[keep, 3] = 255
        a = np.clip((bg.mean() - l) * 5.0, 0, 255)
        a = np.where(a > 60, 96, 52).astype(np.uint8)            # two soft levels
        out[sh] = np.stack([np.full(sh.sum(), 6), np.full(sh.sum(), 20), np.full(sh.sum(), 10), a[sh]], 1)
        ys, xs = np.nonzero(out[:, :, 3] > 0)
        save(name, Image.fromarray(out[ys.min():ys.max() + 1, xs.min():xs.max() + 1], "RGBA"))
    return len(sprites)

def pine_props():
    """Pines into the arenas (idempotent): jungle (full colour) and tundra (frosted): tall pines = border trees, short pines (scaled 0.8 so units
    are not hidden) + stumps + fallen pines = obstacles on the board and fallen-tree decoration. Appends prop_<theme>_obstacle_N after the
    existing variants (first run records themes.json[theme].pine_base so reruns overwrite the same slots)."""
    tp = os.path.join(ROOT, "data", "themes.json")
    th = json.load(open(tp))
    def small(spr, f):
        return spr.resize((max(1, round(spr.width * f)), max(1, round(spr.height * f))), Image.NEAREST)
    # name -> (sprite loader)
    for theme, tf in (("jungle", lambda im: im), ("tundra", lambda im: frost(im, 0.5, 3))):
        t = th[theme]
        base = int(t.get("pine_base", t["obstacle_variants"]))
        spec = []   # (kind, prop image)
        for i in range(1, 5):
            spec.append(("tall" if i in (2, 4) else "short", deco_prop_img(tf(load("tree_pine_%02d" % i)))))
        for i in range(1, 5):
            spec.append(("stump", deco_prop_img(tf(load("stump_pine_%02d" % i)), pad=6)))
        for i in range(1, 3):
            spec.append(("fallen", deco_prop_img(tf(load("fallen_pine_%02d" % i)), pad=8)))
        for i in (1, 3):                                              # board-sized saplings
            spec.append(("sapling", deco_prop_img(tf(small(load("tree_pine_%02d" % i), 0.8)))))
        for k, (kind, img) in enumerate(spec):
            save("prop_%s_obstacle_%d" % (theme, base + k), img)
        ids = {}
        for k, (kind, _) in enumerate(spec):
            ids.setdefault(kind, []).append(base + k)
        t["pine_base"] = base
        t["obstacle_variants"] = base + len(spec)
        old_border = [v for v in t.get("obstacle_pool", []) if v < base]
        old_inter = [v for v in t.get("obstacle_pool_interior", []) if v < base]
        if not old_border:
            old_border = list(range(base))          # tundra had no pools: every old variant
        if not old_inter:
            old_inter = list(range(base))
        t["obstacle_pool"] = old_border + ids["tall"] * 4 + ids["short"] * 4 + ids["stump"] * 2 + ids["fallen"] * 2
        t["obstacle_pool_interior"] = old_inter + ids["sapling"] * 3 + ids["stump"] * 3 + ids["fallen"] * 3
    json.dump(th, open(tp, "w"), indent=1)

def deco_prop_img(spr, pad=13):
    c = Image.new("RGBA", (spr.width, spr.height + pad), (0, 0, 0, 0))
    c.alpha_composite(spr, (0, 0))
    return c

if __name__ == "__main__":
    if "--pines" in sys.argv:
        print("pines", pines()); pine_props()
        open(os.path.join(SRC, "owned.txt"), "a").write("\n".join(n for n in sorted(set(OWNED)) if n.startswith(("tree_pine","stump_pine","fallen_pine"))) + "\n")
        sys.exit(0)
    buttons()
    hpbar()
    print("egg", egg_scene())
    nf = foliage()
    nl = logs()
    cats = iso_sheet()
    props()
    jungle_iso(cats)
    pines(); pine_props()
    open(os.path.join(SRC, "owned.txt"), "w").write("\n".join(sorted(set(OWNED))) + "\n")
    print("foliage", nf, "logs", nl)
