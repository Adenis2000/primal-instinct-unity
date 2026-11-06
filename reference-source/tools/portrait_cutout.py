#!/usr/bin/env python3
"""Transparent raptor portraits (no blue backing square, no shadow): the SE head of the supplied raptor art, box-resampled straight to the
640x360 portrait size (43x43 canvas), hard alpha, shared palette, orange eye restored, plus a 1 px dark outline so the bust reads over the board.
Writes assets/sprites/portrait_<stage>.png (baby, juvenile, adult, prime). portrait_bg_raptor.png stays as a (now unused by the game) reference mask.
Usage: python3 tools/portrait_cutout.py"""
import os, sys
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import import_raptors as R

C = 43
OUTLINE = (24, 16, 14)
MAXH = {"baby": 32, "juvenile": 35, "adult": 38, "prime": 40}   # head height incl. nothing else: bigger form = bigger bust

def outline(a):
    m = a[:, :, 3] > 0
    p = np.pad(m, 1)
    near = (p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:]) & ~m
    a = a.copy()
    a[near, :3] = OUTLINE
    a[near, 3] = 255
    return a

def main():
    src = {suf: (R.load(fn), mult) for suf, (fn, mult) in R.POSE.items()}
    pal = R.palette_of([R.shrink(a, R.BASE * mult) for a, mult in src.values()])
    a = R.load("raptor_a_se.png")
    h, w = a.shape[:2]
    head = a[0:int(h * 0.60), int(w * 0.745):w]
    for stage, k in R.STAGE_K.items():
        S = round(C * (0.70 + 0.38 * (k - 0.6) / 0.5)) - 2          # head width incl. the outline ring
        scale = min(S / head.shape[1], MAXH[stage] / head.shape[0])
        sh = R.shrink(head, scale)
        em = R.eye_mask(head, sh.shape[:2], scale)
        sm = R.snap(sh, pal)
        hit = (em >= 0.1) & (sm[:, :, 3] > 0)
        if not hit.any() and em.max() > 0.02:
            yy, xx = np.unravel_index(np.argmax(em), em.shape)
            hit[yy, xx] = True
        sm[hit, :3] = R.EYE
        hh, ww = sm.shape[:2]
        canvas = np.zeros((C, C, 4), np.uint8)
        ox, oy = C - ww - 1, C - hh - 1                                  # bottom-right of the canvas, 1 px for the outline
        canvas[oy:oy + hh, ox:ox + ww] = sm
        canvas = outline(canvas)
        Image.fromarray(canvas).save(os.path.join(R.OUT, "portrait_%s.png" % stage))
        e = np.nonzero((canvas[:, :, 0] == R.EYE[0]) & (canvas[:, :, 1] == R.EYE[1]) & (canvas[:, :, 2] == R.EYE[2]))
        print(stage, (ww, hh), "eye", (int(e[1].mean()), int(e[0].mean())) if len(e[0]) else None)

if __name__ == "__main__":
    main()
