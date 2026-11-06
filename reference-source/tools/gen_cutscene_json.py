#!/usr/bin/env python3
"""Writes data/cutscene_intro.json (the intro story cutscene timeline). The JSON is the source of truth once generated:
edit it by hand to retime shots / captions, or re-run this script to regenerate it. See README 'Intro story cutscene'."""
import json, random, os

R = random.Random(11)

def trees(par, y, tint, x0=-340, x1=1300, step=118, scale=1, ids=None, jit=24, alpha=1.0, keys=None):
    out = []
    ids = ids or [1, 2, 3, 5, 8, 12, 4, 9]
    x = x0
    i = 0
    while x < x1:
        d = {"kind": "image", "img": "deco_tree_%02d" % ids[i % len(ids)], "x": x + R.randint(-jit, jit), "y": y + R.randint(-6, 6),
             "scale": scale, "par": par, "tint": tint, "alpha": alpha}
        if keys: d["keys"] = keys
        out.append(d)
        x += step + R.randint(-14, 14)
        i += 1
    return out

def bushes(par, y, tint, x0=-300, x1=1300, step=190, scale=2, keys=None):
    out = []
    ids = [1, 3, 5, 6, 8, 2, 7]
    x = x0
    i = 0
    while x < x1:
        d = {"kind": "image", "img": "deco_bush_%02d" % ids[i % len(ids)], "x": x + R.randint(-30, 30), "y": y + R.randint(-4, 10),
             "scale": scale, "par": par, "tint": tint}
        if keys: d["keys"] = keys
        out.append(d)
        x += step + R.randint(-20, 20)
        i += 1
    return out

def env(horizon, sky_top, sky_bot, tree_tint, bush_tint, ground, ground2, edge, shade=None, tkeys=None):
    """The forest clearing used by shots 2, 5 and 6."""
    L = [{"kind": "sky", "id": "sky", "top": sky_top, "bottom": sky_bot, "y0": -160, "y1": horizon + 40, "par": 0.1,
          "clouds": 5, "cloud_col": "#ffffff", "cloud_alpha": 0.5, "cloud_y": [20, 170]}]
    L += trees(0.30, horizon - 8, tree_tint, scale=1, keys=tkeys)
    L += trees(0.45, horizon + 14, tree_tint, x0=-300, step=150, scale=1, ids=[3, 12, 8, 1, 5, 2], keys=tkeys)
    L.append({"kind": "ground", "id": "ground", "y": horizon, "h": 700, "col": ground, "col2": ground2, "edge": edge, "par": 0.6})
    L += bushes(0.62, horizon + 70, bush_tint, keys=tkeys)
    return L

shots = []

# ---------------------------------------------------------------- 1. the egg
shots.append({
    "id": "egg", "name": "Inside the egg", "dur": 7.4, "fade_in": 1.0, "fade_out": 0.7,
    "camera": {"from": [0, 14], "to": [0, -10], "ease": "smooth"},
    "captions": [{"text": "A quiet morning in the nest.", "t": 1.7, "dur": 4.6}],
    "sfx": [{"t": 0.3, "id": "egg_crack_soft"}, {"t": 1.1, "id": "birds_far"}, {"t": 5.0, "id": "footsteps_far"}],
    "layers": [
        {"kind": "sky", "id": "sky", "top": "#8fd0e0", "bottom": "#f2e8b0", "y0": -160, "y1": 520, "par": 0.1, "clouds": 0},
        {"kind": "scene", "id": "nest", "img": "bg_customize", "scale": 5, "x": 182, "y": -90, "par": 1.0},
        # the mother, far away on the ridge, comes back
        {"kind": "image", "id": "mother_far", "img": "raptor_adult_sw", "own_look": True, "scale": 2, "x": 760, "y": 232, "par": 1.0,
         "tint": "#6f8a74", "alpha": 0.0,
         "keys": {"x": [[4.4, 770], [7.4, 540]], "alpha": [[4.4, 0.0], [5.2, 0.92]]}, "hop": 2},
        {"kind": "particles", "id": "motes", "mode": "motes", "rect": [-100, 120, 1160, 360], "n": 26, "color": "#fff6c8", "size": 3, "speed": [4, -6], "par": 0.9},
        {"kind": "shell", "id": "shell", "center": [480, 300], "par": 0.0, "keys": {"open": [[0.0, 0.0], [0.6, 0.12], [1.2, 0.2], [3.8, 0.7], [5.6, 1.0]]},
         "rx": [70, 430], "ry": [46, 250]},
        {"kind": "eyelid", "id": "eyelid", "par": 0.0, "keys": {"open": [[0.0, 0.0], [0.5, 0.0], [1.6, 1.0], [4.3, 1.0], [4.5, 0.25], [4.8, 1.0]]}},
        {"kind": "overlay", "id": "warm", "color": "#fff0b8", "par": 0.0, "keys": {"alpha": [[0.0, 0.18], [7.4, 0.04]]}},
    ]})

# ---------------------------------------------------------------- 2. mother feeds the baby
mx = 740
shots.append({
    "id": "mother", "name": "Mother feeds the baby", "dur": 9.6, "fade_in": 0.7, "fade_out": 0.6,
    "camera": {"from": [-50, 0], "to": [40, 0], "ease": "smooth"},
    "captions": [{"text": "Mother always returned with food.", "t": 1.0, "dur": 5.2}],
    "sfx": [{"t": 0.6, "id": "baby_chirp"}, {"t": 3.4, "id": "mother_rumble"}, {"t": 5.4, "id": "gulp"}, {"t": 5.8, "id": "happy_chirp"}],
    "layers": env(336, "#7fc8dc", "#f0e6a8", "#a6c8a2", "#78a860", "#62923c", "#578732", "#3f6a2c")
    + [
        {"kind": "particles", "id": "pollen", "mode": "motes", "rect": [-100, 160, 1160, 340], "n": 30, "color": "#fff3b0", "size": 3, "speed": [5, -5], "par": 0.8},
        {"kind": "image", "id": "mother", "img": "raptor_adult_sw", "own_look": True, "scale": 4, "x": mx, "y": 484, "par": 1.0, "breathe": 2,
         "tint": "#ffe9c8"},
        {"kind": "image", "id": "baby", "img": "raptor_baby", "scale": 3, "x": 150, "y": 484, "par": 1.0, "hop": 5,
         "keys": {"x": [[0.5, 130], [4.6, 436], [9.6, 436]],
                  "y": [[0, 484], [5.5, 484], [5.75, 466], [6.0, 484], [6.3, 470], [6.55, 484]]}},
        {"kind": "image", "id": "meat", "img": "icon_meat", "scale": 3, "x": 594, "y": 420, "par": 1.0, "alpha": 0.0,
         "keys": {"alpha": [[3.3, 0.0], [3.5, 1.0], [5.3, 1.0], [5.45, 0.0]],
                  "x": [[3.4, 598], [4.2, 566], [5.2, 524]], "y": [[3.4, 420], [4.2, 396], [5.2, 432]]}},
        {"kind": "image", "id": "heart_a", "img": "icon_heart", "scale": 2, "x": 520, "y": 410, "par": 1.0, "alpha": 0.0,
         "keys": {"alpha": [[5.7, 0.0], [6.1, 1.0], [7.6, 0.0]], "y": [[5.7, 410], [7.6, 340]], "x": [[5.7, 520], [7.6, 532]]}},
        {"kind": "image", "id": "heart_b", "img": "icon_heart", "scale": 2, "x": 470, "y": 420, "par": 1.0, "alpha": 0.0,
         "keys": {"alpha": [[6.3, 0.0], [6.7, 1.0], [8.1, 0.0]], "y": [[6.3, 420], [8.1, 360]], "x": [[6.3, 470], [8.1, 458]]}},
        {"kind": "overlay", "id": "warm", "color": "#ffe9b0", "par": 0.0, "keys": {"alpha": [[0, 0.06]]}},
    ]})

# ---------------------------------------------------------------- 3. the meteor
cx, cy = 700, 376
shots.append({
    "id": "meteor", "name": "The sky breaks", "dur": 7.2, "fade_in": 0.7, "fade_out": 0.5,
    "camera": {"from": [0, -90], "to": [0, 0], "ease": "smooth"},
    "shake": [{"t": 3.1, "dur": 2.2, "amp": 9}],
    "flash": [{"t": 3.1, "dur": 1.1, "color": "#fff4d8", "peak": 1.0}],
    "captions": [{"text": "Then the sky broke.", "t": 0.9, "dur": 3.4}],
    "sfx": [{"t": 1.2, "id": "meteor_whoosh"}, {"t": 3.1, "id": "impact_boom"}, {"t": 3.3, "id": "rumble_low"}],
    "layers": [
        {"kind": "sky", "id": "sky", "top": "#4a78b8", "bottom": "#efd9a0", "y0": -130, "y1": cy + 20, "par": 0.55,
         "clouds": 6, "cloud_col": "#ffffff", "cloud_alpha": 0.55, "cloud_y": [-200, 180]},
        {"kind": "glow", "id": "crash_glow", "x": cx, "y": cy - 10, "r": 190, "col": "#ff8a3a", "par": 1.0,
         "keys": {"alpha": [[3.0, 0.0], [3.15, 0.95], [7.2, 0.5]]}},
    ] + trees(1.0, cy - 10, "#7a9a8a", step=125, scale=1) + [
        {"kind": "ground", "id": "ground", "y": cy, "h": 700, "col": "#587e3a", "col2": "#4d7232", "edge": "#37592a", "par": 1.0},
        {"kind": "meteor", "id": "meteor", "from": [-80, -520], "to": [cx, cy - 4], "t0": 1.2, "t1": 3.1, "col": "#ffcf6a", "par": 1.0, "tail": 380},
        {"kind": "plume", "id": "plume", "x": cx, "y": cy - 4, "h": 330, "w": 70, "t0": 3.1, "col": "#3c3040", "col2": "#8a7468", "par": 1.0,
         "keys": {"grow": [[3.1, 0.0], [7.2, 1.0]]}},
        {"kind": "particles", "id": "embers", "mode": "embers", "rect": [cx - 90, cy - 40, 180, 40], "n": 22, "color": "#ffb04a", "size": 3,
         "speed": [10, -70], "t0": 3.1, "par": 1.0},
    ] + bushes(1.0, cy + 120, "#6a9a58", step=230, scale=2) + [
        {"kind": "overlay", "id": "dim", "color": "#2a1010", "par": 0.0, "keys": {"alpha": [[3.1, 0.0], [7.2, 0.22]]}},
    ]})

# ---------------------------------------------------------------- 4. something crawls out
cx4 = 700
shots.append({
    "id": "emerge", "name": "Something crawled out", "dur": 8.2, "fade_in": 0.6, "fade_out": 0.6,
    "camera": {"from": [0, 0], "to": [-30, 0], "ease": "smooth"},
    "shake": [{"t": 0.0, "dur": 2.2, "amp": 3}, {"t": 3.2, "dur": 0.6, "amp": 5}],
    "flash": [{"t": 3.3, "dur": 0.5, "color": "#b86aff", "peak": 0.45}],
    "captions": [{"text": "Something crawled out of the fire.", "t": 1.0, "dur": 5.6}],
    "sfx": [{"t": 0.5, "id": "crackle"}, {"t": 1.8, "id": "screech_far"}, {"t": 3.3, "id": "infect_pulse"}],
    "layers": [
        {"kind": "sky", "id": "sky", "top": "#33244f", "bottom": "#d26a38", "y0": -260, "y1": 380, "par": 0.3, "clouds": 4,
         "cloud_col": "#2a1a30", "cloud_alpha": 0.8, "cloud_y": [20, 190],
         "keys": {"top": [[0, "#4a4070"], [8.2, "#2b1a48"]], "bottom": [[0, "#e89050"], [8.2, "#b0505a"]]}},
        {"kind": "glow", "id": "fire", "x": cx4, "y": 372, "r": 260, "col": "#ff7a30", "par": 0.9, "keys": {"alpha": [[0, 0.8], [8.2, 0.55]]}},
        {"kind": "plume", "id": "plume", "x": cx4, "y": 376, "h": 380, "w": 90, "col": "#2a2030", "col2": "#6a5460", "par": 0.9, "keys": {"grow": [[0, 1.0]]}, "t0": 0},
    ] + trees(0.5, 372, "#4e6a58", step=120, keys={"tint": [[0, "#4e6a58"], [3.3, "#4e6a58"], [6.5, "#5a3f78"]]}) + [
        {"kind": "ground", "id": "ground", "y": 376, "h": 700, "col": "#3f5a30", "col2": "#365028", "edge": "#27391f", "par": 1.0,
         "keys": {"col": [[0, "#3f5a30"], [8.2, "#3c3446"]]}},
        {"kind": "creep", "id": "creep", "x": cx4, "y": 400, "rx": 0, "ry": 0, "col": "#8a3fd0", "par": 1.0,
         "keys": {"r": [[1.0, 0.0], [8.2, 1.0]]}, "max": 820},
        {"kind": "glow", "id": "queen_glow", "x": cx4, "y": 390, "r": 130, "col": "#9a4aff", "par": 1.0, "keys": {"alpha": [[0.8, 0.0], [3.0, 0.5], [8.2, 0.35]]}},
        {"kind": "image", "id": "queen", "img": "husk_queen", "scale": 2, "x": cx4, "y": 560, "par": 1.0, "flip": True, "clip_y": 388,
         "tint": "#1e1228", "keys": {"y": [[0.8, 560], [3.4, 392], [8.2, 392]], "x": [[3.4, cx4], [8.2, cx4 - 150]]}},
        {"kind": "image", "id": "drone_a", "img": "spore_drone", "scale": 2, "x": cx4, "y": 380, "par": 1.0, "flip": True, "tint": "#1a0f24", "alpha": 0.0,
         "keys": {"alpha": [[3.4, 0.0], [3.6, 1.0]], "x": [[3.4, cx4], [8.2, 230]], "y": [[3.4, 380], [5.0, 300], [8.2, 330]]}, "breathe": 3},
        {"kind": "image", "id": "drone_b", "img": "spore_drone", "scale": 2, "x": cx4, "y": 380, "par": 1.0, "flip": True, "tint": "#1a0f24", "alpha": 0.0,
         "keys": {"alpha": [[4.2, 0.0], [4.4, 1.0]], "x": [[4.2, cx4 + 20], [8.2, 360]], "y": [[4.2, 380], [5.6, 270], [8.2, 290]]}, "breathe": 3},
        {"kind": "image", "id": "drone_c", "img": "spore_drone", "scale": 3, "x": cx4, "y": 380, "par": 1.0, "flip": True, "tint": "#1a0f24", "alpha": 0.0,
         "keys": {"alpha": [[5.0, 0.0], [5.2, 1.0]], "x": [[5.0, cx4 + 40], [8.2, 520]], "y": [[5.0, 380], [6.4, 240], [8.2, 252]]}, "breathe": 3},
        {"kind": "particles", "id": "spores", "mode": "spores", "rect": [-100, 140, 1160, 260], "n": 36, "color": "#c07aff", "size": 3, "speed": [-8, -14], "t0": 2.5, "par": 1.0},
        {"kind": "overlay", "id": "sick", "color": "#3a1060", "par": 0.0, "keys": {"alpha": [[0, 0.0], [8.2, 0.28]]}},
    ]})

# ---------------------------------------------------------------- 5. mother fights
sick = {"tint": [[0, "#a6c8a2"], [1.8, "#a6c8a2"], [6.5, "#6a4f84"]]}
bsick = {"tint": [[0, "#78a860"], [1.8, "#78a860"], [6.5, "#4d3a66"]]}
shots.append({
    "id": "fight", "name": "Mother fights", "dur": 8.6, "fade_in": 0.6, "fade_out": 0.7,
    "camera": {"from": [30, 0], "to": [-20, 0], "ease": "smooth"},
    "shake": [{"t": 3.0, "dur": 0.5, "amp": 5}, {"t": 4.2, "dur": 0.6, "amp": 6}, {"t": 5.5, "dur": 0.5, "amp": 4}],
    "flash": [{"t": 4.2, "dur": 0.5, "color": "#c07aff", "peak": 0.55}, {"t": 5.5, "dur": 0.4, "color": "#a05aff", "peak": 0.4}],
    "captions": [{"text": "Mother fought. It wasn't enough.", "t": 1.3, "dur": 5.8}],
    "sfx": [{"t": 1.2, "id": "screech_near"}, {"t": 3.0, "id": "mother_roar"}, {"t": 4.2, "id": "infect_hit"}, {"t": 5.5, "id": "infect_hit"}, {"t": 6.6, "id": "mother_whimper"}],
    "layers": env(336, "#7fc8dc", "#f0e6a8", "#a6c8a2", "#78a860", "#62923c", "#578732", "#3f6a2c")
    + [
        {"kind": "overlay", "id": "dusk", "color": "#2a1050", "par": 0.0, "keys": {"alpha": [[0, 0.08], [8.6, 0.4]]}},
        {"kind": "creep", "id": "creep", "x": 1100, "y": 440, "col": "#8a3fd0", "par": 1.0, "max": 1300, "keys": {"r": [[0, 0.45], [8.6, 0.95]]}},
        {"kind": "image", "id": "mother", "img": "raptor_adult_sw", "img_b": "raptor_adult_sw", "infect_b": True, "own_look": True, "scale": 4, "x": 640, "y": 484,
         "par": 1.0, "breathe": 1, "tint": "#ffe9c8", "shake_when": [3.0, 3.5, 4.2, 4.8, 5.5, 6.0],
         "keys": {"x": [[0, 640], [2.8, 640], [3.1, 600], [3.6, 640], [4.1, 640], [4.3, 660], [8.6, 690]],
                  "mix": [[0, 0.0], [4.2, 0.0], [6.0, 1.0]],
                  "tint": [[0, "#ffe9c8"], [4.2, "#ffe9c8"], [6.0, "#c9a8e8"], [7.8, "#2a1838"]]}},
        {"kind": "image", "id": "baby", "img": "raptor_baby_sw", "scale": 3, "x": 330, "y": 484, "par": 1.0, "jitter": 1,
         "keys": {"x": [[0, 380], [2.6, 330], [6.5, 300], [8.6, 290]]}},
        {"kind": "image", "id": "queen", "img": "husk_queen", "scale": 2, "x": 1120, "y": 470, "par": 1.0, "flip": True, "tint": "#1e1228",
         "keys": {"x": [[0.8, 1180], [3.2, 900], [8.6, 830]]}},
        {"kind": "image", "id": "drone_a", "img": "spore_drone", "scale": 3, "x": 1100, "y": 330, "par": 1.0, "flip": True, "tint": "#1a0f24", "breathe": 4,
         "keys": {"x": [[1.2, 1120], [3.0, 820], [4.2, 770], [8.6, 760]], "y": [[1.2, 300], [3.0, 380], [4.2, 400], [8.6, 360]]}},
        {"kind": "image", "id": "drone_b", "img": "spore_drone", "scale": 2, "x": 1100, "y": 300, "par": 1.0, "flip": True, "tint": "#1a0f24", "breathe": 4,
         "keys": {"x": [[1.8, 1160], [3.6, 880], [5.0, 700], [8.6, 690]], "y": [[1.8, 260], [3.6, 330], [5.0, 380], [8.6, 330]]}},
        {"kind": "particles", "id": "spores", "mode": "spores", "rect": [440, 250, 520, 250], "n": 30, "color": "#c07aff", "size": 3, "speed": [-6, -20], "t0": 3.6, "par": 1.0},
        {"kind": "overlay", "id": "vig", "color": "#12001e", "par": 0.0, "mode": "vignette", "keys": {"alpha": [[0, 0.0], [8.6, 0.55]]}},
    ]})

# ---------------------------------------------------------------- 6. run
shots.append({
    "id": "flee", "name": "Run", "dur": 6.8, "fade_in": 0.6, "fade_out": 1.2,
    "camera": {"from": [20, 0], "to": [90, 0], "ease": "smooth"},
    "captions": [{"text": "Run.", "t": 1.6, "dur": 3.4}],
    "sfx": [{"t": 0.4, "id": "wind_low"}, {"t": 2.2, "id": "footsteps_run"}],
    "layers": env(336, "#4a3a70", "#b86a74", "#5a4a78", "#4d3a66", "#3c3a4a", "#35334a", "#26243a")
    + [
        {"kind": "creep", "id": "creep", "x": 1000, "y": 440, "col": "#8a3fd0", "par": 1.0, "max": 1300, "keys": {"r": [[0, 1.0]]}},
        {"kind": "image", "id": "mother", "img": "raptor_adult_sw", "img_b": "raptor_adult_sw", "infect_b": True, "own_look": True, "scale": 4, "x": 780, "y": 484,
         "par": 1.0, "breathe": 1, "tint": "#2a1838", "keys": {"mix": [[0, 1.0]]}},
        {"kind": "glow", "id": "mother_glow", "x": 780, "y": 420, "r": 120, "col": "#9a4aff", "par": 1.0, "keys": {"alpha": [[0, 0.35], [6.8, 0.25]]}},
        {"kind": "image", "id": "queen", "img": "husk_queen", "scale": 2, "x": 1000, "y": 470, "par": 1.0, "flip": True, "tint": "#1e1228",
         "keys": {"x": [[0, 1000], [6.8, 940]]}},
        {"kind": "image", "id": "baby", "img": "raptor_baby_sw", "scale": 3, "x": 330, "y": 484, "par": 1.0, "jitter": 1, "hop": 7,
         "keys": {"x": [[0, 330], [1.7, 330], [2.3, 326], [5.6, -220]]}},
        {"kind": "particles", "id": "spores", "mode": "spores", "rect": [300, 200, 800, 300], "n": 28, "color": "#c07aff", "size": 3, "speed": [-10, -16], "par": 1.0},
        {"kind": "overlay", "id": "dusk", "color": "#1a0830", "par": 0.0, "keys": {"alpha": [[0, 0.35], [6.8, 0.5]]}},
        {"kind": "overlay", "id": "vig", "color": "#0a0010", "par": 0.0, "mode": "vignette", "keys": {"alpha": [[0, 0.5], [6.8, 0.75]]}},
    ]})

doc = {
    "version": 1,
    "doc": "Intro story cutscene timeline. World coords are the 960x540 design frame (y down); layers are drawn in order. Each layer: kind, par "
           "(parallax factor vs the camera), optional t0/t1 visibility window, and 'keys' = per-property keyframes [[t, value], ...] (shot-local seconds). "
           "Designer art: drop assets/sprites/cutscene_<layer id>.png (or cutscene_<shot id>_<layer id>.png) to replace an 'image' layer's sprite.",
    "letterbox": {"aspect": 2.2, "min_bar": 52},
    "pixel": 3,
    "skip_hold": 0.6,
    "shots": shots,
}
import sys
sys.path.insert(0, os.path.dirname(__file__))
from rebase_cutscene import convert
doc = convert(doc)      # 960x540 design coordinates -> the 640x360 canvas
os.makedirs("data", exist_ok=True)
json.dump(doc, open(os.path.join(os.path.dirname(__file__), "..", "data", "cutscene_intro.json"), "w"), indent=1)
print("shots", len(shots), "total", sum(s["dur"] for s in shots))
