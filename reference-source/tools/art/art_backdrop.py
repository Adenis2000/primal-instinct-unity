"""Prehistoric menu backdrop art (numpy + PIL): seamless packed-earth ground, dinosaur/ammonite fossils (animal bones only),
footprints, stones, roots, a large partially buried dinosaur skeleton, falling-leaf frames.
Writes assets/sprites/bd_<theme>_*.png (1 art pixel = 2 logical UI pixels at runtime, see data/backdrops.json).
Run: python3 tools/art/art_backdrop.py   (needs numpy + Pillow)."""
import math, os, sys
import numpy as np
from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "sprites")
BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], dtype=np.float32) / 16.0

def hexc(h):
    h = h.lstrip('#'); return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))

def mixc(a, b, t):
    a = tuple(int(v) for v in a); b = tuple(int(v) for v in b)
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def ramp(base, lo, hi, n=5):
    b = hexc(base)
    return [tuple(max(0, min(255, int(c * (lo + (hi - lo) * i / (n - 1))))) for c in b) for i in range(n)]

THEMES = {
    "jungle": {"dirt": ramp("#6b4f33", 0.62, 1.22), "bone": ramp("#cdbf9a", 0.55, 1.1), "stone": ramp("#7d7566", 0.5, 1.2),
               "root": ramp("#5a4026", 0.6, 1.3), "soil": hexc("#3c2a1a"), "speck": hexc("#9a7a52"), "frost": 0.0},
    "tundra": {"dirt": ramp("#66707c", 0.62, 1.25), "bone": ramp("#d6e2ec", 0.6, 1.08), "stone": ramp("#8a95a2", 0.5, 1.2),
               "root": ramp("#4e4640", 0.6, 1.3), "soil": hexc("#2c3440"), "speck": hexc("#cfe0ee"), "frost": 1.0},
    "cave": {"dirt": ramp("#433f50", 0.6, 1.25), "bone": ramp("#9a9486", 0.5, 1.1), "stone": ramp("#5c586a", 0.5, 1.25),
             "root": ramp("#3a3548", 0.6, 1.3), "soil": hexc("#1c1a26"), "speck": hexc("#7a748a"), "frost": 0.0},
}

# ------------------------------------------------------------------ ground (periodic noise => seamless)
def pnoise(w, h, cell, seed):
    rng = np.random.RandomState(seed)
    gw, gh = w // cell, h // cell
    g = rng.rand(gh, gw).astype(np.float32)
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    xs /= cell; ys /= cell
    x0 = xs.astype(int) % gw; y0 = ys.astype(int) % gh
    x1 = (x0 + 1) % gw; y1 = (y0 + 1) % gh
    fx = xs - np.floor(xs); fy = ys - np.floor(ys)
    fx = fx * fx * (3 - 2 * fx); fy = fy * fy * (3 - 2 * fy)
    return (g[y0, x0] * (1 - fx) + g[y0, x1] * fx) * (1 - fy) + (g[y1, x0] * (1 - fx) + g[y1, x1] * fx) * fy

def ground(theme, size=192, seed=3):
    T = THEMES[theme]
    n = 0.34 * pnoise(size, size, 96, seed) + 0.30 * pnoise(size, size, 48, seed + 1) + 0.2 * pnoise(size, size, 16, seed + 4) + 0.16 * pnoise(size, size, 6, seed + 2)
    d = np.tile(BAYER, (size // 4, size // 4))
    idx = np.clip(((n - 0.25) / 0.5 * 4.0 + (d - 0.5) * 0.9).round().astype(int), 0, 4)
    img = np.zeros((size, size, 3), np.uint8)
    for i in range(5):
        img[idx == i] = T["dirt"][i]
    rng = np.random.RandomState(seed + 9)
    for _ in range(int(size * size * 0.012)):          # specks / tiny pebbles
        x, y = rng.randint(0, size, 2)
        c = T["speck"] if rng.rand() < 0.5 else T["soil"]
        img[y, x] = mixc(tuple(img[y, x]), c, 0.55)
        if rng.rand() < 0.35:
            img[y, (x + 1) % size] = mixc(tuple(img[y, (x + 1) % size]), c, 0.4)
    for _ in range(int(size * size * 0.0016)):         # hairline cracks (wrap-around)
        x, y = rng.randint(0, size, 2)
        for k in range(rng.randint(4, 9)):
            img[y % size, x % size] = mixc(tuple(img[y % size, x % size]), T["soil"], 0.5)
            x += rng.choice([-1, 0, 1, 1]); y += rng.choice([0, 1, 1])
    if T["frost"] > 0:                                 # frost glitter on frozen earth
        for _ in range(int(size * size * 0.01)):
            x, y = rng.randint(0, size, 2)
            img[y, x] = mixc(tuple(img[y, x]), (235, 245, 255), 0.6)
    return Image.fromarray(img, "RGB").convert("RGBA")

# ------------------------------------------------------------------ shaded sprite from a silhouette mask
def shade(mask, rmp, soil, extra_dark=None):
    """mask: 'L' image (>127 = solid). Light on upper-left edges, dark on lower-right, 1px soil shadow outline."""
    m = np.array(mask) > 127
    h, w = m.shape
    out = np.zeros((h + 2, w + 2, 4), np.uint8)
    P = np.pad(m, 1)
    for y in range(1, h + 1):
        for x in range(1, w + 1):
            if not P[y, x]:
                continue
            up, left, down, right = P[y - 1, x], P[y, x - 1], P[y + 1, x], P[y, x + 1]
            if not up or not left:
                c = rmp[4] if (not up and not left) else rmp[3]
            elif not down or not right:
                c = rmp[1]
            else:
                c = rmp[2] if ((x + y) % 5) else rmp[3]
            out[y, x] = (*c, 255)
    for y in range(h + 2):                              # soil shadow outline
        for x in range(w + 2):
            if out[y, x, 3] == 0:
                for dx, dy in ((1, 0), (0, 1), (1, 1), (-1, 0), (0, -1)):
                    xx, yy = x + dx, y + dy
                    if 0 <= xx < w + 2 and 0 <= yy < h + 2 and out[yy, xx, 3] == 255 and out[yy, xx, 0] != 0:
                        out[y, x] = (*soil, 150 if dx > 0 or dy > 0 else 90)
                        break
    return Image.fromarray(out, "RGBA")

def cut(mask, shapes_fn):
    """Run shapes_fn(draw) with fill=0 to punch holes."""
    d = ImageDraw.Draw(mask); shapes_fn(d)

def L(w, h): return Image.new("L", (w, h), 0)

# ------------------------------------------------------------------ fossils (ANIMAL / dinosaur / ammonite only)
def ammonite(T, seed=1):
    S = 22; m = L(S, S); d = ImageDraw.Draw(m)
    c = (S - 1) / 2; pts = []
    for i in range(0, 260):
        a = i * 0.05; r = 1.2 + a * 0.62
        pts.append((c + math.cos(a) * r * 0.95, c + math.sin(a) * r * 0.95))
    for k in range(len(pts) - 1):
        r = 1.2 + k * 0.05 * 0.62
        d.line([pts[k], pts[k + 1]], fill=255, width=2 if r > 4 else 1)
    img = shade(m, T["bone"], T["soil"]).copy()
    px = img.load()
    for i in range(0, 260, 11):                          # ribs of the shell
        a = i * 0.05; r = 1.2 + a * 0.62
        x, y = int(c + math.cos(a) * (r + 1.2)) + 1, int(c + math.sin(a) * (r + 1.2)) + 1
        if 0 <= x < img.width and 0 <= y < img.height and px[x, y][3] == 255:
            px[x, y] = (*T["bone"][0], 255)
    return img

def bez(p0, p1, p2, n=18):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0], (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]) for t in [i / n for i in range(n + 1)]]

def ribcage(T, k=1.0, nribs=5, with_spine=True):
    """Curved ribs hanging from a spine line (bowed outward, like a buried theropod ribcage seen from above)."""
    W, H = int(44 * k), int(26 * k); m = L(W, H); d = ImageDraw.Draw(m)
    y0 = int(2 * k)
    if with_spine:
        d.line([(0, y0), (W, y0)], fill=255, width=max(2, int(2 * k)))
    for i in range(nribs):
        x = (4 + i * (36.0 / max(1, nribs - 1))) * k
        ln = (22 - abs(i - (nribs - 1) / 2) * 2.2) * k
        d.line(bez((x, y0), (x + 7 * k, y0 + ln * 0.45), (x + 2 * k, y0 + ln)), fill=255, width=max(2, int(1.6 * k)))
    return shade(m, T["bone"], T["soil"])

def skull(T, k=1.0):
    """Long-snouted theropod skull fragment: snout, orbit, nostril, tooth row."""
    W, H = int(34 * k), int(24 * k); m = L(W, H); d = ImageDraw.Draw(m)
    P = [(1, 15), (6, 10), (14, 8), (21, 4), (28, 5), (32, 10), (31, 17), (26, 20), (16, 20), (7, 19)]
    d.polygon([(int(x * k), int(y * k)) for x, y in P], fill=255)
    def holes(dd):
        r = max(2, int(3 * k)); cx, cy = int(23 * k), int(11 * k)
        dd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=0)                       # eye socket
        dd.ellipse([int(5 * k), int(12 * k), int(7 * k) + 1, int(14 * k) + 1], fill=0)  # nostril
        dd.polygon([(int(11 * k), int(10 * k)), (int(17 * k), int(9 * k)), (int(17 * k), int(13 * k)), (int(12 * k), int(13 * k))], fill=0)  # antorbital window
        for i in range(6):                                                           # tooth gaps along the jaw line
            x = int((4 + i * 3.4) * k)
            dd.line([(x, int(18 * k)), (x, int(20 * k) + 1)], fill=0, width=1)
    cut(m, holes)
    return shade(m, T["bone"], T["soil"])

def spine(T, k=1.0):
    W, H = int(38 * k), int(10 * k); m = L(W, H); d = ImageDraw.Draw(m)
    for i in range(6):
        x = int((3 + i * 6) * k)
        d.ellipse([x, int(3 * k), x + int(5 * k), int(8 * k)], fill=255)
        d.polygon([(x + int(2 * k), int(3 * k)), (x + int(3 * k), 0), (x + int(4 * k), int(3 * k))], fill=255)
        if i:
            d.line([(x - int(2 * k), int(5 * k)), (x, int(5 * k))], fill=255, width=max(1, int(k)))
    return shade(m, T["bone"], T["soil"])

def footprint(T, flip=False):
    W, H = 16, 18; m = L(W, H); d = ImageDraw.Draw(m)
    d.ellipse([5, 11, 10, 16], fill=255)                                   # heel pad
    for (x0, y0, x1, y1, tip) in ((7, 11, 7, 2, (7, 0)), (6, 12, 2, 5, (1, 3)), (9, 12, 13, 5, (14, 3))):
        d.line([(x0, y0), (x1, y1)], fill=255, width=3)
        d.polygon([(x1 - 1, y1), (x1 + 1, y1), tip], fill=255)             # claw
    mm = np.array(m) > 127
    P = np.pad(mm, 1); out = np.zeros((H + 2, W + 2, 4), np.uint8)
    dk, rim, soil = T["dirt"][0], T["dirt"][4], T["soil"]
    for y in range(1, H + 1):
        for x in range(1, W + 1):
            if P[y, x]:
                out[y, x] = (*mixc(dk, soil, 0.8), 255)                   # depression
                if not P[y + 1, x] or not P[y, x + 1]:
                    out[y, x] = (*mixc(dk, soil, 0.2), 255)
            elif (P[y - 1, x] or P[y, x - 1]) and not P[y, x]:
                out[y, x] = (*rim, 160)                                    # raised soil rim (light, upper-left)
    im = Image.fromarray(out, "RGBA")
    return im.transpose(Image.FLIP_LEFT_RIGHT) if flip else im

def stone(T, w, h, seed):
    rng = np.random.RandomState(seed); m = L(w, h); d = ImageDraw.Draw(m)
    pts = [(w / 2 + math.cos(a) * w / 2 * (0.78 + rng.rand() * 0.22), h / 2 + math.sin(a) * h / 2 * (0.78 + rng.rand() * 0.22)) for a in np.linspace(0, 2 * math.pi, 9)[:-1]]
    d.polygon(pts, fill=255)
    return shade(m, T["stone"], T["soil"])

def root(T, w, h, seed):
    rng = np.random.RandomState(seed); m = L(w, h); d = ImageDraw.Draw(m)
    y = h // 2; pts = []
    for x in range(0, w, 3):
        y = max(2, min(h - 3, y + rng.randint(-2, 3))); pts.append((x, y))
    d.line(pts, fill=255, width=3)
    for _ in range(2):                                                      # side rootlets
        i = rng.randint(2, len(pts) - 2); x, y = pts[i]
        d.line([(x, y), (x + rng.randint(3, 6), y + rng.choice([-1, 1]) * rng.randint(3, 6))], fill=255, width=2)
    return shade(m, T["root"], T["soil"])

def skeleton(T):
    """Large partially buried dinosaur: skull at left, a row of vertebrae running right, ribs hanging from it.
    The lower part dissolves into soil (dithered) as if still buried."""
    W, H = 150, 84
    big = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    big.alpha_composite(skull(T, 1.55), (2, 16))
    sp = spine(T, 1.3)
    big.alpha_composite(sp, (54, 22)); big.alpha_composite(sp, (102, 22))
    big.alpha_composite(ribcage(T, 1.75, 7, False), (62, 24))
    a = np.array(big)
    dd = np.tile(BAYER, (H // 4 + 1, W // 4 + 1))[:H, :W]
    for y in range(H):
        t = max(0.0, (y - H * 0.46) / (H * 0.36))
        for x in range(W):
            if a[y, x, 3] and (t > dd[y, x] or t > 1.0):
                a[y, x, 3] = 0
            elif a[y, x, 3] and t > 0:
                a[y, x, :3] = mixc(tuple(a[y, x, :3]), T["soil"], min(0.75, t * 0.9))
    return Image.fromarray(a, "RGBA")

def leaf(i):
    cols = [((70, 120, 50), (110, 160, 60)), ((150, 110, 40), (190, 150, 60)), ((100, 90, 40), (150, 130, 60))][i % 3]
    im = Image.new("RGBA", (7, 5), (0, 0, 0, 0)); p = im.load()
    shape = [[(1, 2), (2, 1), (3, 1), (4, 2), (5, 2), (6, 3)], [(1, 1), (2, 1), (3, 2), (4, 2), (5, 3), (2, 2)], [(1, 3), (2, 2), (3, 2), (4, 1), (5, 1), (3, 3)]][i // 3 if i < 3 else i % 3]
    for k, (x, y) in enumerate(shape):
        p[x, y] = (*cols[k % 2], 255)
    return im

def main():
    os.makedirs(OUT, exist_ok=True)
    for theme, T in THEMES.items():
        s = lambda n: os.path.join(OUT, f"bd_{theme}_{n}.png")
        ground(theme).save(s("ground"))
        ammonite(T).save(s("ammonite"))
        ribcage(T).save(s("ribs"))
        skull(T).save(s("skull"))
        spine(T).save(s("spine"))
        footprint(T, False).save(s("footprint_l")); footprint(T, True).save(s("footprint_r"))
        for i, (w, h) in enumerate(((9, 6), (12, 8), (7, 5))):
            stone(T, w, h, 10 + i).save(s(f"stone_{i}"))
        if theme != "cave":
            root(T, 34, 14, 3).save(s("root_0")); root(T, 26, 16, 7).save(s("root_1"))
        else:
            stone(T, 16, 10, 40).save(s("root_0")); stone(T, 12, 9, 41).save(s("root_1"))   # cave: rock chunks instead of roots
        skeleton(T).save(s("skeleton"))
    for i in range(3):
        leaf(i).save(os.path.join(OUT, f"bd_leaf_{i}.png"))
    print("backdrop art written to", os.path.abspath(OUT))

if __name__ == "__main__":
    main()
