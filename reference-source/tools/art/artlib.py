"""Tiny pixel-art toolkit (numpy + PIL): shaded masks with palette ramps + ordered dithering, outlines,
tapered strokes, splines, noise. Everything renders at final pixel resolution (1 art pixel = 1 viewport pixel)."""
import colorsys, math
import numpy as np
from PIL import Image, ImageDraw

BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], dtype=np.float32) / 16.0 - 0.5

def hexc(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))

def ramp(base, n=5, lo=0.42, hi=1.35, shadow_hue=0.64, light_hue=0.13, hshift=0.05, sat=1.0):
    """Sea-of-Stars style ramp: shadows drift toward blue/violet and darker, highlights toward warm yellow."""
    r, g, b = [c / 255.0 for c in (hexc(base) if isinstance(base, str) else base)]
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    out = []
    for i in range(n):
        t = i / (n - 1)
        vv = min(1.0, v * (lo + (hi - lo) * t))
        hh = h
        if t < 0.5:
            d = ((shadow_hue - h + 0.5) % 1.0) - 0.5
            hh = h + d * hshift * (0.5 - t) * 2
        else:
            d = ((light_hue - h + 0.5) % 1.0) - 0.5
            hh = h + d * hshift * (t - 0.5) * 2 * 0.6
        ss = min(1.0, s * sat * (1.12 - 0.35 * abs(t - 0.4)) * (1.0 - 0.25 * max(0, t - 0.75) * 4))
        rr, gg, bb = colorsys.hsv_to_rgb(hh % 1.0, max(0, min(1, ss)), vv)
        out.append((int(rr * 255), int(gg * 255), int(bb * 255)))
    return out

def mix(c1, c2, t):
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))

def darker(c, t=0.5, hue_to=(20, 10, 50)):
    return mix(c, hue_to, t)

# ------------------------------------------------------------------ noise
def _hash_noise(w, h, seed):
    rng = np.random.RandomState(seed & 0x7fffffff)
    return rng.rand(h, w).astype(np.float32)

def value_noise(w, h, cell, seed):
    gw, gh = w // cell + 3, h // cell + 3
    g = _hash_noise(gw, gh, seed)
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    xs = xs / cell
    ys = ys / cell
    x0 = xs.astype(int)
    y0 = ys.astype(int)
    fx = xs - x0
    fy = ys - y0
    fx = fx * fx * (3 - 2 * fx)
    fy = fy * fy * (3 - 2 * fy)
    a = g[y0, x0]
    b = g[y0, x0 + 1]
    c = g[y0 + 1, x0]
    d = g[y0 + 1, x0 + 1]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy

def fbm(w, h, cell, seed, octaves=3):
    out = np.zeros((h, w), np.float32)
    amp = 1.0
    tot = 0.0
    for o in range(octaves):
        out += amp * value_noise(w, h, max(1, cell // (2 ** o)), seed + o * 101)
        tot += amp
        amp *= 0.5
    return out / tot

def box_blur(a, r, n=2):
    a = a.astype(np.float32)
    for _ in range(n):
        for axis in (0, 1):
            k = 2 * r + 1
            pad = [(0, 0), (0, 0)]
            pad[axis] = (r + 1, r)
            p = np.pad(a, pad, mode='constant')
            c = np.cumsum(p, axis=axis, dtype=np.float32)
            if axis == 0:
                a = (c[k:, :] - c[:-k, :]) / k
            else:
                a = (c[:, k:] - c[:, :-k]) / k
    return a

# ------------------------------------------------------------------ masks
SS = 4

def _new_ss(w, h):
    im = Image.new('L', (w * SS, h * SS), 0)
    return im, ImageDraw.Draw(im)

def _from_ss(im, w, h):
    a = np.asarray(im.resize((w, h), Image.BOX), dtype=np.float32) / 255.0
    return a >= 0.5

def ellipse_mask(w, h, cx, cy, rx, ry, angle=0.0):
    im, d = _new_ss(w, h)
    pts = []
    ca, sa = math.cos(math.radians(angle)), math.sin(math.radians(angle))
    for i in range(48):
        t = i / 48 * 2 * math.pi
        x, y = rx * math.cos(t), ry * math.sin(t)
        pts.append(((cx + x * ca - y * sa) * SS, (cy + x * sa + y * ca) * SS))
    d.polygon(pts, fill=255)
    return _from_ss(im, w, h)

def poly_mask(w, h, pts):
    im, d = _new_ss(w, h)
    d.polygon([(x * SS, y * SS) for x, y in pts], fill=255)
    return _from_ss(im, w, h)

def spline(pts, n=24, closed=False):
    """Catmull-Rom through pts."""
    P = list(pts)
    if closed:
        P = [P[-1]] + P + [P[0], P[1]]
    else:
        P = [P[0]] + P + [P[-1]]
    out = []
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        for k in range(n):
            t = k / n
            t2, t3 = t * t, t * t * t
            out.append(tuple(0.5 * ((2 * p1[j]) + (-p0[j] + p2[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t2 + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t3) for j in range(2)))
    out.append(P[-2])
    return out

def blob_mask(w, h, pts):
    return poly_mask(w, h, spline(pts, 10, closed=True))

def tube_mask(w, h, pts, widths, smooth=True):
    """Tapered stroke along pts; widths is list (per control pt)."""
    if smooth and len(pts) > 2:
        n = 14
        sp = spline(pts, n)
        wsp = []
        for i in range(len(pts) - 1):
            for k in range(n):
                wsp.append(widths[i] + (widths[i + 1] - widths[i]) * k / n)
        wsp.append(widths[-1])
        pts, widths = sp, wsp
    im, d = _new_ss(w, h)
    for i in range(len(pts) - 1):
        (x0, y0), (x1, y1) = pts[i], pts[i + 1]
        steps = max(2, int(math.hypot(x1 - x0, y1 - y0) * 2))
        for s in range(steps + 1):
            t = s / steps
            x, y = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
            r = (widths[i] + (widths[i + 1] - widths[i]) * t) / 2
            d.ellipse([(x - r) * SS, (y - r) * SS, (x + r) * SS, (y + r) * SS], fill=255)
    return _from_ss(im, w, h)

def line_mask(w, h, pts, width=1.0):
    return tube_mask(w, h, pts, [width] * len(pts), smooth=False)

# ------------------------------------------------------------------ canvas
class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.px = np.zeros((h, w, 4), np.uint8)

    def mask_alpha(self):
        return self.px[:, :, 3] > 0

    def shade(self, mask, rmp, light=(-0.55, -0.75), contrast=1.0, blur=2, bias=0.0, rim=0.35, dither=True, tex=None, tex_amt=0.0, flat=None):
        """Paint mask with lit ramp. 'rim' darkens near edges (soft rounded look)."""
        if not mask.any():
            return
        m = mask.astype(np.float32)
        b = box_blur(m, blur, 3)
        gy, gx = np.gradient(b)
        k = 5.0 * blur / 2.0
        nx, ny = -gx * k, -gy * k
        nz = np.ones_like(nx)
        ln = np.sqrt(nx * nx + ny * ny + nz * nz)
        lx, ly = light
        lz = 0.55
        L = math.sqrt(lx * lx + ly * ly + lz * lz)
        lam = (nx * lx + ny * ly + nz * lz) / (ln * L)  # ~0.4..1
        v = 0.55 + (lam - 0.78) * 2.2 * contrast + bias
        v = v - rim * (1.0 - np.clip(b * 1.25, 0, 1)) * 1.0
        if tex is not None:
            v = v + (tex - 0.5) * tex_amt
        if flat is not None:
            v = np.full_like(v, flat)
        n = len(rmp)
        f = np.clip(v, 0, 0.999) * (n - 1)
        ys, xs = np.mgrid[0:self.h, 0:self.w]
        if dither:
            f = f + BAYER[ys % 4, xs % 4] * 0.9
        idx = np.clip(np.round(f).astype(int), 0, n - 1)
        pal = np.array(rmp, dtype=np.uint8)
        col = pal[idx]
        self.px[mask, 0:3] = col[mask]
        self.px[mask, 3] = 255

    def flat(self, mask, color, alpha=255):
        self.px[mask, 0:3] = color
        self.px[mask, 3] = alpha

    def blend(self, mask, color, t):
        """alpha-blend color over existing opaque pixels."""
        m = mask & (self.px[:, :, 3] > 0)
        for i in range(3):
            self.px[m, i] = (self.px[m, i] * (1 - t) + color[i] * t).astype(np.uint8)

    def pset(self, x, y, color, a=255):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[int(y), int(x), 0:3] = color
            self.px[int(y), int(x), 3] = a

    def paste(self, other, x, y, mask=None):
        """alpha composite other canvas (hard alpha) at x,y."""
        ow, oh = other.w, other.h
        x0, y0 = max(0, x), max(0, y)
        x1, y1 = min(self.w, x + ow), min(self.h, y + oh)
        if x1 <= x0 or y1 <= y0:
            return
        src = other.px[y0 - y:y1 - y, x0 - x:x1 - x]
        a = src[:, :, 3:4].astype(np.float32) / 255.0
        dst = self.px[y0:y1, x0:x1]
        da = dst[:, :, 3:4].astype(np.float32) / 255.0
        oa = a + da * (1 - a)
        with np.errstate(divide='ignore', invalid='ignore'):
            rgb = np.where(oa > 0, (src[:, :, :3] * a + dst[:, :, :3] * da * (1 - a)) / np.maximum(oa, 1e-6), 0)
        self.px[y0:y1, x0:x1, :3] = rgb.astype(np.uint8)
        self.px[y0:y1, x0:x1, 3:4] = (oa * 255).astype(np.uint8)

    def outline(self, color=None, strength=0.62, outer=True, tint=(18, 12, 34), diag=False):
        """1px outline outside the silhouette; color derived from the adjacent sprite pixel (selective outline)."""
        a = self.px[:, :, 3] > 0
        p = np.pad(a, 1)
        nb = np.zeros_like(a)
        offs = [(-1, 0), (1, 0), (0, -1), (0, 1)] + ([(-1, -1), (1, 1), (-1, 1), (1, -1)] if diag else [])
        src = np.zeros((self.h, self.w, 3), np.float32)
        cnt = np.zeros((self.h, self.w, 1), np.float32)
        pp = np.pad(self.px, ((1, 1), (1, 1), (0, 0)))
        for dy, dx in offs:
            sh = p[1 + dy:1 + dy + self.h, 1 + dx:1 + dx + self.w]
            nb |= sh
            s2 = pp[1 + dy:1 + dy + self.h, 1 + dx:1 + dx + self.w]
            wgt = (s2[:, :, 3:4] > 0).astype(np.float32)
            src += s2[:, :, :3] * wgt
            cnt += wgt
        edge = nb & ~a
        col = np.where(cnt > 0, src / np.maximum(cnt, 1), 0)
        for i in range(3):
            c = col[:, :, i] * (1 - strength) + tint[i] * strength if color is None else color[i]
            self.px[edge, i] = np.clip(c[edge] if hasattr(c, '__len__') else c, 0, 255).astype(np.uint8)
        self.px[edge, 3] = 255

    def inner_outline(self, mask, color, amt=0.45):
        """darken interior pixels bordering other things inside mask (used to separate overlapping parts)."""
        pass

    def to_image(self):
        return Image.fromarray(self.px, 'RGBA')

    def save(self, path):
        self.to_image().save(path)

def new(w, h):
    return Canvas(w, h)

def fill_noise_ramp(c, mask, rmp, cell=6, seed=1, lo=0.2, hi=0.8, octaves=3, dither=True, scale=1.0):
    n = fbm(c.w, c.h, cell, seed, octaves)
    v = np.clip((n - 0.3) / 0.4, 0, 1) * (hi - lo) + lo
    f = v * (len(rmp) - 1)
    ys, xs = np.mgrid[0:c.h, 0:c.w]
    if dither:
        f = f + BAYER[ys % 4, xs % 4] * 0.9
    idx = np.clip(np.round(f).astype(int), 0, len(rmp) - 1)
    pal = np.array(rmp, dtype=np.uint8)
    col = pal[idx]
    c.px[mask, 0:3] = col[mask]
    c.px[mask, 3] = 255
