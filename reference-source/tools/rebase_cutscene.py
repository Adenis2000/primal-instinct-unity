#!/usr/bin/env python3
"""Converts the intro-cutscene timeline from the old 960x540 design frame to the 640x360 canvas (idempotent: marks the doc with "frame").
World coordinates / sizes x 2/3; sprite scales x 0.75 (the baked sprites are ~0.45x, the frame 0.67x, so characters stay a similar fraction
of the screen without 3-6 px blocks); the nest scene uses the 1:1 posterized bg_customize_hi; pixel grid 3 -> 2; letterbox min bar 52 -> 35.
Usage: python3 tools/rebase_cutscene.py [data/cutscene_intro.json]   (gen_cutscene_json.py calls convert() itself)"""
import json, sys

K = 2.0 / 3.0
SCALAR = {"x", "y", "x0", "x1", "y0", "y1", "h", "w", "r", "tail", "max", "clip_y", "rx", "ry", "jitter", "hop", "breathe", "size", "amp"}
ARRAYS = {"rect", "center", "from", "to", "cloud_y", "speed", "rx", "ry"}
KEYPOS = {"x", "y"}

def s(v):
    r = v * K
    return int(round(r)) if isinstance(v, int) else round(r, 2)

def sc_scale(v):
    return max(1, int(v * 0.75 + 0.5))

def conv_layer(ly):
    for k, v in list(ly.items()):
        if k in ARRAYS and isinstance(v, list):
            ly[k] = [s(x) for x in v]
        elif k in SCALAR and isinstance(v, (int, float)) and not isinstance(v, bool):
            ly[k] = max(1, s(v)) if k in ("size", "jitter", "hop", "breathe") else s(v)
    if ly["kind"] == "image" and "scale" in ly:
        ly["scale"] = sc_scale(ly["scale"])
    if ly["kind"] == "scene":
        if ly.get("img") == "bg_customize":
            ly["img"] = "bg_customize_hi"
        ly["scale"] = 1
    for k, kf in ly.get("keys", {}).items():
        if k in KEYPOS:
            ly["keys"][k] = [[t, s(v)] for t, v in kf]

def convert(d):
    if d.get("frame") == [640, 360]:
        return d
    d["frame"] = [640, 360]
    d["doc"] = d["doc"].replace("960x540", "640x360")
    d["pixel"] = 2
    d["letterbox"]["min_bar"] = s(d["letterbox"]["min_bar"])
    for sh in d["shots"]:
        cam = sh.get("camera", {})
        for k in ("from", "to"):
            if k in cam:
                cam[k] = [s(x) for x in cam[k]]
        for sk in sh.get("shake", []):
            sk["amp"] = max(1, s(sk["amp"]))
        for ly in sh["layers"]:
            conv_layer(ly)
    return d

if __name__ == "__main__":
    p = sys.argv[1] if len(sys.argv) > 1 else "data/cutscene_intro.json"
    d = convert(json.load(open(p)))
    json.dump(d, open(p, "w"), indent=1)
    print("converted", p)
