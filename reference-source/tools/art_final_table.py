#!/usr/bin/env python3
"""Final sprite assessment of the 640x360 re-base: old-density source (tools/art_src_960) vs the baked game sprite (assets/sprites).
Prints the markdown table used in README "Art spec for designers".  Usage: python3 tools/art_final_table.py"""
import os, re
from PIL import Image
SRC, DST = "tools/art_src_960/", "assets/sprites/"
# name, label, designer target (what to author if redrawn), verdict, note
ROWS = [
 ("tile_jungle_ground_0", "ground tile (jungle)", "32x16", "Works", "Clean diamond; keep 5-8 colours and 1-2 px detail."),
 ("tile_tundra_ground_0", "ground tile (tundra)", "32x16", "Works", "Low contrast: add 2-3 darker ice-crack pixels per tile."),
 ("tile_cave_ground_0", "ground tile (cave)", "32x16", "Works", "1 px teal sparkles survive."),
 ("prop_jungle_tallgrass_0", "tall grass (jungle)", "32x24", "Works", "Leaf shapes survive; a redraw with 2 px blades would be crisper."),
 ("prop_jungle_obstacle_0", "obstacle (rock + ferns)", "32x32", "Works", "Reads well."),
 ("prop_tundra_obstacle_0", "obstacle (tundra)", "32x27", "Works", "Needs a 1 px lighter rim on the dark underside."),
 ("prop_cave_obstacle_0", "obstacle (cave)", "32x27", "Works", "Teal veins become 1 px lines, fine."),
 ("deco_tree_01", "border tree", "43x64", "Works", "Border only: too tall to stand on the board."),
 ("foliage_05", "bush / foliage", "21x21", "Works", "Good border bush size."),
 ("log_01", "log", "20x10", "Marginal", "Loses bark detail at 18x10: redraw with 3 colours."),
 ("tree_pine_01", "pine tree (short, @kianamosser)", "22x44", "Works", "Downscaled ~2.6x from the sheet and still clean: a ready-made jungle / tundra border tree; a native redraw would be crisper."),
 ("tree_pine_02", "pine tree (tall, @kianamosser)", "29x53", "Works", "Border only (tall); the tallest at 53 px is 15% of the screen height."),
 ("tree_pine_03", "pine tree (short, @kianamosser)", "23x44", "Works", "Also used 0.8x as a board sapling (18x41)."),
 ("tree_pine_04", "pine tree (tall, @kianamosser)", "28x53", "Works", "Border only."),
 ("stump_pine_01", "pine stump (@kianamosser)", "12x8", "Works", "Tiny but readable as a 12x8 obstacle; fine on the board."),
 ("fallen_pine_01", "fallen pine (@kianamosser)", "49x21", "Works", "Reads as a log across 1.5 tiles; board obstacle and decor."),
 ("raptor_adult", "raptor adult SE", "37x17", "Works", "Eye + belly pixels restored by tools/raptor_details.py so recolouring still works."),
 ("raptor_adult_sw", "raptor adult SW", "32x15", "Marginal", "Legs and tail merge a little; redraw recommended."),
 ("raptor_adult_b", "raptor adult NE", "34x15", "Marginal", "Back view loses the crest; redraw recommended."),
 ("raptor_adult_nw", "raptor adult NW", "33x15", "Marginal", "As NE."),
 ("raptor_baby", "raptor baby SE", "28x13", "Works", "Enlarged from true scale (20x9 was a smudge); bigger head."),
 ("raptor_juvenile", "raptor juvenile SE", "33x15", "Works", ""),
 ("raptor_prime", "raptor prime SE", "40x19", "Works", ""),
 ("beetle", "beetle", "24x19", "Works", "Enlarged to a 24 px minimum so it stays a beetle, not a blob."),
 ("compy", "compy", "30x23", "Marginal", "Reads as a dino; the face is lost, redraw recommended."),
 ("smilodon", "smilodon", "34x24", "Works", "Stripes survive."),
 ("husk_queen", "husk queen", "50x41", "Works", "Glow spots stay as clean 2 px dots."),
 ("infected_mammoth", "infected mammoth", "44x37", "Works", ""),
 ("ui_btn", "button (9-slice)", "25x14, 5 px caps", "Works", "Authored size would be 24x14 with 3 px corners."),
 ("ui_panel", "panel (9-slice)", "24x24", "Works with care", "Non-integer corner widths."),
 ("ui_bar_frame", "HP bar frame", "72x22", "Works", ""),
 ("ui_bar_slim", "slim bar", "68x8", "Works", "Fill 16x3."),
 ("card_claw_slash", "card art", "61x36", "Works", "Painterly; survives a 56-colour palette."),
 ("card_frame_dark", "card frame (9-slice)", "24x24, 3 px", "Works", ""),
 ("icon_move", "icon", "11x11 (10x10)", "Works", "Redrawn at 11x11, drawn at 100%."),
 ("item_apex_heart", "item icon", "13x13", "Works", "Redrawn at 13x13."),
 ("portrait_adult", "portrait", "43x43", "Works", "Hi-res: author 32x32 (HUD) and 48x48 (customize) for a native look."),
 ("egg_raptor", "egg", "22x25", "Works", "Customize screen uses the hi-res egg_raptor_hi (1:1)."),
 ("bg_egg_nest", "nest", "79x57", "Works", ""),
 ("bg_jungle_0", "backdrop", "640x360", "Works, not pixel art", "Posterized to 48 colours; a native repaint would be better."),
]
PINE_BOX = {}
for m in re.finditer(r'"((?:tree|stump|fallen)_pine_\d\d)": \((\d+), (\d+), (\d+), (\d+)\)', open("tools/import_supplied.py").read()):
    PINE_BOX[m.group(1)] = (int(m.group(4)) - int(m.group(2)), int(m.group(5)) - int(m.group(3)))

def info(n):
    p = DST + n + ".png"
    im = Image.open(p).convert("RGBA")
    px = [q for q in im.get_flattened_data() if q[3] > 0]
    cols = len({q[:3] for q in px if q[3] > 127})
    soft = sum(1 for q in px if q[3] < 250) / max(1, len(px))
    return im.size, cols, soft
print("| asset | file | native (old density) | now (native px) | designer target | colours now | soft-edge px | verdict at 640x360 | designer note |")
print("|---|---|---|---|---|---|---|---|---|")
for n, label, tgt, verdict, note in ROWS:
    if not os.path.exists(DST + n + ".png"):
        continue
    (w, h), cols, soft = info(n)
    sp = SRC + n + ".png"
    if n in PINE_BOX:
        nat = "%dx%d (sheet crop)" % PINE_BOX[n]
    elif os.path.exists(sp):
        nat = "%dx%d" % Image.open(sp).size
    else:
        nat = "-"
    print("| %s | %s | %s | %dx%d | %s | %d | %d%% | %s | %s |" % (label, n, nat, w, h, tgt, cols, round(soft * 100), verdict, note))
