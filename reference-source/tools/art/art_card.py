"""Ability-card layers redrawn from the designer's card design (tools/art/supplied/card_sheet.jpg: a dark-blue "night" card and a
light cream/orange "desert" card). Every layer is its own PNG so the designer can replace one (same name, same size):
    card_frame_<v>    40x40  9-slice (margin 8)   outer card body + border (mossy chipped corners)
    card_crest_<v>    24x9   top-centre tab that holds the rarity gem
    card_artwin_<v>   16x16  9-slice (margin 3)   border drawn OVER the illustration (centre transparent)
    card_banner_<v>   48x20  9-slice (16 / 7 / 16 / 7)  the scroll that carries the card NAME
    card_ribbon_<v>   32x10  9-slice (10 / 3 / 10 / 3)  thin subtitle ribbon = card TYPE (swallow-tail ends)
    card_textbox_<v>  20x20  9-slice (margin 6)   description box
    card_tile_<v>     13x13  9-slice (margin 3)   number tile (stamina cost) + the two small tiles below it
    card_slot_<v>     13x13  9-slice (margin 3)   dark inset icon slot (archetype tags)
  <v> = dark | light.   The game draws the name / description / cost live (Jersey font) on top of these."""
from PIL import Image
import random

PAL = {
    "dark": dict(
        out="#0b1424", band="#2c5578", hi="#5a96bc", body="#355f84", shade="#27486a", moss="#6c8f55",
        win_o="#070c18", win_m="#203c5c", win_i="#0d1426",
        ban_f="#6f9358", ban_hi="#9dbb7a", ban_sh="#46684a", ban_o="#0b1424", ban_e="#3d6a7e",
        rib_f="#4c3b54", rib_hi="#6b5470", rib_sh="#2f2338", rib_o="#120d1a",
        tx_f="#2d5780", tx_b="#4f86ae", tx_sh="#244768", tx_o="#0b1424", crack="#1f3d5c",
        ti_f="#1b2f4c", ti_b="#5a96bc", ti_o="#070c18",
        sl_f="#0c1626", sl_b="#4a7ea6", sl_o="#050912",
        crest_f="#2a4a68", crest_g="#3f7090"),
    "light": dict(
        out="#7a4a30", band="#e8a95c", hi="#ffe3a6", body="#f8cf88", shade="#e6b070", moss="#c9d9a0",
        win_o="#7a4a30", win_m="#d99a58", win_i="#b8784a",
        ban_f="#fff1c4", ban_hi="#fffbe6", ban_sh="#f2d29c", ban_o="#9a6440", ban_e="#8fcfc0",
        rib_f="#f2a853", rib_hi="#ffd08a", rib_sh="#cf7f3a", rib_o="#8a5230",
        tx_f="#fff3cc", tx_b="#d9a068", tx_sh="#f0d6a0", tx_o="#8a5636", crack="#e8c690",
        ti_f="#fff3cc", ti_b="#d9a068", ti_o="#8a5636",
        sl_f="#e2b27a", sl_b="#b8784a", sl_o="#6a4028",
        crest_f="#f0c07a", crest_g="#ffe3a6"),
}

def hexc(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (255,)

class Pix:
    def __init__(self, w, h):
        self.im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        self.w, self.h = w, h
    def p(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.im.putpixel((x, y), hexc(c) if isinstance(c, str) else c)
    def r(self, x0, y0, x1, y1, c):          # inclusive rectangle
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.p(x, y, c)
    def clear(self, x, y):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.im.putpixel((x, y), (0, 0, 0, 0))
    def save(self, path):
        self.im.save(path)

def box9(w, h, outline, border, hilite, fill, shade=None, cut=1, border_w=1, hollow=False, speck=None, seed=1):
    """Chipped-corner framed box: outline, border band(s), 1px highlight, fill. `hollow` leaves the centre transparent."""
    c = Pix(w, h)
    c.r(0, 0, w - 1, h - 1, outline)
    for k in range(border_w):
        c.r(1 + k, 1 + k, w - 2 - k, h - 2 - k, border)
    o = 1 + border_w
    c.r(o, o, w - 1 - o, h - 1 - o, hilite)
    o += 1
    if not hollow:
        c.r(o, o, w - 1 - o, h - 1 - o, fill)
        if shade:
            c.r(o, h - 1 - o, w - 1 - o, h - 1 - o, shade)
            c.r(w - 1 - o, o, w - 1 - o, h - 1 - o, shade)
    else:
        c.r(o, o, w - 1 - o, h - 1 - o, (0, 0, 0, 0))
    for (x, y, dx, dy) in ((0, 0, 1, 1), (w - 1, 0, -1, 1), (0, h - 1, 1, -1), (w - 1, h - 1, -1, -1)):
        for i in range(cut):
            for j in range(cut - i):
                c.clear(x + dx * i, y + dy * j)
        c.p(x + dx * cut, y + dy * 0, outline)
        c.p(x + dx * 0, y + dy * cut, outline)
    return c

def frame(v):
    P = PAL[v]
    c = box9(40, 40, P["out"], P["band"], P["hi"], P["body"], P["shade"], cut=2, border_w=2)
    rng = random.Random(7 if v == "dark" else 9)
    # chips / moss specks only in the corner caps (the stretchy edges stay clean)
    for (ox, oy) in ((0, 0), (32, 0), (0, 32), (32, 32)):
        for _ in range(7):
            x, y = ox + rng.randrange(0, 8), oy + rng.randrange(0, 8)
            if 2 <= x <= 37 and 2 <= y <= 37:
                c.p(x, y, P["moss"] if rng.random() < 0.5 else P["shade"])
    return c

def crest(v):
    P = PAL[v]
    c = Pix(24, 9)
    c.r(0, 0, 23, 8, P["out"])
    c.r(1, 1, 22, 8, P["band"])
    c.r(2, 2, 21, 8, P["crest_f"])
    c.r(3, 2, 20, 2, P["hi"])
    for x, y in ((0, 0), (1, 0), (22, 0), (23, 0), (0, 1), (23, 1)):
        c.clear(x, y)
    c.r(7, 3, 16, 7, P["out"])          # socket for the rarity gem (drawn live)
    c.r(8, 4, 15, 6, P["crest_g"])
    return c

def artwin(v):
    P = PAL[v]
    c = Pix(16, 16)
    c.r(0, 0, 15, 15, P["win_o"])
    c.r(1, 1, 14, 14, P["win_m"])
    c.r(2, 2, 13, 13, P["win_i"])
    c.r(3, 3, 12, 12, (0, 0, 0, 0))
    c.r(1, 1, 14, 1, P["hi"] if v == "light" else "#3f6a92")      # top light edge of the bevel
    return c

def banner(v):
    P = PAL[v]
    w, h = 48, 20
    c = Pix(w, h)
    # scroll body with a gently arched top, rolled ends
    for x in range(w):
        t = min(x, w - 1 - x)
        top = 0 if t >= 12 else (3 - t // 4)          # corners curve down over the first 12 px
        bot = h - 1
        for y in range(top, bot + 1):
            c.p(x, y, P["ban_f"])
        c.p(x, top, P["ban_o"])
        c.p(x, bot, P["ban_o"])
        if top + 1 < bot:
            c.p(x, top + 1, P["ban_hi"])
        c.p(x, bot - 1, P["ban_sh"])
        c.p(x, bot - 2, P["ban_sh"])
    for y in range(h):                                 # end caps: outline + roll
        for side in (0, 1):
            x = 0 if side == 0 else w - 1
            dx = 1 if side == 0 else -1
            c.p(x, y, P["ban_o"])
            if 3 < y < h - 1:
                c.p(x + dx, y, P["ban_o"])
                c.p(x + 2 * dx, y, P["ban_e"])
                c.p(x + 3 * dx, y, P["ban_sh"])
    for side in (0, 1):                                # corner rounding
        x0 = 0 if side == 0 else w - 1
        dx = 1 if side == 0 else -1
        for (i, j) in ((0, 0), (1, 0), (0, 1), (0, 2), (2, 0), (0, 3), (3, 0)):
            c.clear(x0 + dx * i, j)
        for (i, j) in ((0, h - 1), (1, h - 1), (0, h - 2)):
            c.clear(x0 + dx * i, j)
        c.p(x0 + dx * 4, 0, P["ban_o"])
        c.p(x0 + dx * 2, 1, P["ban_o"])
        c.p(x0 + dx * 1, 2, P["ban_o"])
    # a few stitch / moss pixels on the dark banner, frost pixels on the light one
    rng = random.Random(3)
    for _ in range(10):
        x = rng.choice([rng.randrange(5, 14), rng.randrange(w - 14, w - 5)])
        y = rng.randrange(5, h - 4)
        c.p(x, y, P["ban_hi"] if v == "dark" else P["ban_e"])
    return c

def ribbon(v):
    P = PAL[v]
    w, h = 32, 10
    c = Pix(w, h)
    c.r(0, 0, w - 1, h - 1, P["rib_o"])
    c.r(1, 1, w - 2, h - 2, P["rib_f"])
    c.r(1, 1, w - 2, 1, P["rib_hi"])
    c.r(1, h - 2, w - 2, h - 2, P["rib_sh"])
    for y in range(h):                                  # swallow-tail ends
        n = 4 - abs(y - (h - 1) / 2.0) * 0.9
        for i in range(max(0, int(n))):
            c.clear(i, y)
            c.clear(w - 1 - i, y)
        if int(n) > 0:
            c.p(int(n), y, P["rib_o"])
            c.p(w - 1 - int(n), y, P["rib_o"])
    return c

def textbox(v):
    P = PAL[v]
    c = box9(20, 20, P["tx_o"], P["tx_b"], P["tx_sh"] if v == "light" else P["tx_b"], P["tx_f"], None, cut=2, border_w=1)
    rng = random.Random(11)
    for (ox, oy) in ((0, 0), (14, 0), (0, 14), (14, 14)):     # hairline cracks in the corners
        for _ in range(3):
            c.p(ox + rng.randrange(2, 6), oy + rng.randrange(2, 6), P["crack"])
    return c

def tile(v):
    P = PAL[v]
    return box9(13, 13, P["ti_o"], P["ti_b"], P["ti_b"], P["ti_f"], None, cut=1, border_w=1)

def slot(v):
    P = PAL[v]
    c = box9(13, 13, P["sl_o"], P["sl_b"], P["sl_o"], P["sl_f"], None, cut=1, border_w=1)
    return c

def make_cards():
    out = {}
    for v in ("dark", "light"):
        out["card_frame_" + v] = frame(v)
        out["card_crest_" + v] = crest(v)
        out["card_artwin_" + v] = artwin(v)
        out["card_banner_" + v] = banner(v)
        out["card_ribbon_" + v] = ribbon(v)
        out["card_textbox_" + v] = textbox(v)
        out["card_tile_" + v] = tile(v)
        out["card_slot_" + v] = slot(v)
    return out

if __name__ == "__main__":
    import os
    d = make_cards()
    os.makedirs("/workspace/tmp/cardparts", exist_ok=True)
    for k, v in d.items():
        v.save("/workspace/tmp/cardparts/%s.png" % k)
