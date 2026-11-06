#!/usr/bin/env python3
"""Customization-screen art at the 640x360 native pixel grid.
The baked egg / nest scene (assets/sprites/bg_customize.png 80x108, egg_raptor.png 22x25) is pixel art at the *small* density, so drawn at
5x it would show 5x5 blocks on the 640x360 canvas. This tool upscales them 5x with a smooth filter, sharpens a little and POSTERIZES to a
small shared-style palette (median cut, no dither), giving 1:1 art whose pixels match the rest of the canvas:
  bg_customize_hi.png  (400x540)   egg_raptor_hi.png (110x125)
Re-run after tools/rebase_640.py. Usage: python3 tools/hires_backdrops.py"""
from PIL import Image, ImageFilter
import os
S = "assets/sprites/"

def hi(name, k, colors, out):
    im = Image.open(S + name + ".png").convert("RGBA")
    a = im.getchannel("A")
    rgb = im.convert("RGB").resize((im.width * k, im.height * k), Image.BICUBIC)
    rgb = rgb.filter(ImageFilter.UnsharpMask(radius=2, percent=60, threshold=2))
    q = rgb.quantize(colors=colors, method=Image.MEDIANCUT, dither=Image.NONE).convert("RGB")
    a2 = a.resize((im.width * k, im.height * k), Image.BICUBIC).point(lambda v: 255 if v > 127 else 0)
    r = q.convert("RGBA")
    r.putalpha(a2)
    r.save(S + out + ".png")
    print(out, r.size)

hi("bg_customize", 5, 40, "bg_customize_hi")
hi("egg_raptor", 5, 20, "egg_raptor_hi")
