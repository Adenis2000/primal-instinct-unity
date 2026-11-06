#!/usr/bin/env python3
"""Generates data/sprites.json: placeholder procedural pixel-art definitions.
Shapes: ell cx cy rx ry col | rect x y w h col | line x0 y0 x1 y1 col | px x y col
Real art can replace any sprite by dropping assets/sprites/<id>.png (see README)."""
import json
S = {}
def spr(id, grid, size, palette, shapes, style="creature", **kw):
    d = {"grid": grid, "size": size, "palette": palette, "shapes": shapes, "style": style}
    d.update(kw); S[id] = d

# ---------- Raptor line ----------
raptor_pal = {"body": "#86b84e", "belly": "#e6dfa0", "dark": "#4a7a34", "eye": "#ffffff", "pupil": "#101010", "beak": "#f0c050", "crest": "#e8703a", "stripe": "#5d8c3a"}
raptor_shapes = [
  ["ell",3,10,3,1,"body"], ["px",0,9,"body"], ["px",1,9,"body"],
  ["rect",6,12,2,3,"dark"], ["rect",9,12,2,3,"dark"],
  ["ell",7,10,4,3,"body"], ["ell",7,11,3,2,"belly"],
  ["rect",9,5,2,5,"body"], ["ell",11,5,3,3,"body"], ["rect",13,5,3,2,"body"],
  ["px",12,4,"eye"], ["px",13,4,"pupil"],
  ["px",10,10,"dark"], ["px",11,10,"dark"], ["px",11,11,"beak"],
  ["px",9,2,"crest"], ["px",10,1,"crest"]]
spr("raptor_baby", 16, 16, raptor_pal, raptor_shapes)
spr("raptor_juvenile", 16, 20, dict(raptor_pal, body="#78ad48", crest="#e8903a"), raptor_shapes +
    [["line",4,9,8,9,"stripe"], ["line",5,10,5,10,"stripe"], ["px",8,1,"crest"], ["px",7,2,"crest"], ["px",12,12,"beak"]])
spr("raptor_adult", 16, 24, dict(raptor_pal, body="#5d9a4a", dark="#35603a", belly="#d8d49a", crest="#f0a030", stripe="#2f5a3a"), raptor_shapes +
    [["line",3,9,9,9,"stripe"], ["line",4,11,5,12,"stripe"], ["line",8,1,5,3,"crest"], ["line",9,2,6,4,"crest"], ["px",11,12,"beak"], ["px",12,13,"beak"],
     ["line",0,8,0,11,"crest"], ["line",1,8,1,9,"crest"]])
spr("raptor_prime", 16, 28, dict(raptor_pal, body="#c9a23a", dark="#7a5a22", belly="#f4e8b0", crest="#d8402a", stripe="#8a3a20", pupil="#a01010"), raptor_shapes +
    [["line",3,9,9,9,"stripe"], ["line",4,11,6,11,"stripe"], ["line",8,1,4,3,"crest"], ["line",9,2,5,5,"crest"], ["line",10,0,7,1,"crest"],
     ["line",0,7,0,11,"crest"], ["line",1,8,2,8,"crest"], ["line",2,7,3,8,"crest"], ["px",11,12,"beak"], ["px",12,13,"beak"], ["px",12,12,"beak"]])

# ---------- Small enemies ----------
spr("beetle", 16, 16, {"shell":"#4f78b8","dark":"#23364f","leg":"#2a2a33","horn":"#d8c070","white":"#ffffff"}, [
  ["line",4,13,3,15,"leg"], ["line",7,13,7,15,"leg"], ["line",10,13,11,15,"leg"],
  ["ell",7,9,6,4,"shell"], ["line",7,6,7,12,"dark"], ["ell",14,10,2,2,"dark"], ["line",14,8,15,5,"horn"], ["px",15,10,"white"]])
spr("dragonfly", 16, 16, {"body":"#3aa86a","wing":"#bfe8ff","eye":"#e04040","leg":"#1a4a30"}, [
  ["ell",8,5,4,2,"wing"], ["ell",6,5,3,1,"wing"], ["ell",8,12,4,2,"wing"],
  ["rect",1,8,4,1,"body"], ["ell",8,8,4,1,"body"], ["ell",13,8,2,2,"eye"], ["px",14,7,"leg"]])
spr("skink", 16, 16, {"body":"#a8793a","stripe":"#e0c080","dark":"#5c3f1e","eye":"#101010"}, [
  ["ell",2,11,3,1,"body"], ["px",0,12,"body"], ["rect",6,12,1,2,"dark"], ["rect",10,12,1,2,"dark"],
  ["ell",8,10,5,2,"body"], ["rect",4,9,8,1,"stripe"], ["ell",13,10,2,2,"body"], ["px",14,9,"eye"]])
spr("shrew", 16, 16, {"fur":"#8a7a6a","ear":"#d8a0a0","nose":"#d86a6a","dark":"#4a3f36","tail":"#d8a0a0","pupil":"#101010"}, [
  ["line",3,11,0,13,"tail"], ["rect",5,12,1,2,"dark"], ["rect",9,12,1,2,"dark"],
  ["ell",7,10,4,3,"fur"], ["ell",11,9,3,3,"fur"], ["ell",14,10,2,1,"fur"], ["ell",10,6,1,2,"ear"], ["px",15,10,"nose"], ["px",12,9,"pupil"]])
spr("spore_drone", 16, 16, {"body":"#7a4aa8","glow":"#8dff6a","wing":"#c8a8f0","eye":"#e0ffc0"}, [
  ["ell",4,5,2,1,"wing"], ["ell",12,5,2,1,"wing"], ["ell",8,8,4,4,"body"], ["ell",8,9,2,2,"glow"],
  ["px",7,7,"eye"], ["px",10,7,"eye"], ["line",6,12,5,15,"body"], ["line",9,12,10,15,"body"]])

# ---------- Elites / bosses ----------
spr("meganeura", 24, 24, {"body":"#2fa89a","head":"#1f7a70","wing":"#c8f0f0","eye":"#ffb030","leg":"#103a36"}, [
  ["ell",11,6,7,3,"wing"], ["ell",7,7,5,2,"wing"], ["ell",11,18,7,3,"wing"], ["ell",7,17,5,2,"wing"],
  ["rect",1,12,6,1,"body"], ["ell",12,12,8,2,"body"], ["ell",20,12,3,3,"head"], ["px",21,11,"eye"], ["px",22,11,"eye"],
  ["line",14,14,13,17,"leg"], ["line",17,14,18,17,"leg"], ["line",22,14,23,17,"leg"]])
spr("husk_queen", 32, 32, {"chitin":"#5a3a78","sac":"#6dd85a","glow":"#d0ff90","leg":"#2a1838","mand":"#b8a0d0"}, [
  ["line",6,22,2,30,"leg"], ["line",11,24,8,31,"leg"], ["line",17,24,18,31,"leg"], ["line",23,22,27,30,"leg"],
  ["ell",15,19,11,8,"chitin"], ["ell",8,17,5,5,"sac"], ["ell",16,13,4,3,"sac"], ["ell",21,22,3,2,"sac"],
  ["ell",27,17,4,4,"chitin"], ["line",30,20,31,24,"mand"], ["line",28,21,29,25,"mand"],
  ["px",28,16,"glow"], ["px",29,16,"glow"], ["px",29,18,"glow"],
  ["line",10,11,8,6,"mand"], ["line",16,10,17,5,"mand"], ["line",21,12,24,8,"mand"]])

# ---------- Stage 2 ----------
spr("compy", 16, 16, dict(raptor_pal, body="#d98a3a", belly="#f0d8a0", dark="#8a4a20", stripe="#9a5a28", crest="#c04a2a"), raptor_shapes + [["rect",4,9,5,1,"stripe"]])
spr("dire_pup", 16, 20, {"fur":"#8a919c","dark":"#4a4f58","eye":"#ffe070","nose":"#101010"}, [
  ["line",2,8,0,5,"fur"], ["rect",3,11,2,4,"dark"], ["rect",6,11,2,4,"dark"], ["rect",9,11,2,4,"dark"], ["rect",12,11,2,4,"dark"],
  ["ell",7,9,5,3,"fur"], ["ell",13,8,3,3,"fur"], ["rect",14,9,2,2,"fur"], ["px",12,5,"dark"], ["px",14,5,"dark"], ["px",14,7,"eye"], ["px",15,9,"nose"]])
spr("glyptodon", 16, 24, {"shell":"#8a6a4a","dark":"#4a3624","skin":"#b89a7a","hi":"#b89a6a"}, [
  ["rect",3,12,3,3,"skin"], ["rect",10,12,3,3,"skin"], ["rect",0,10,3,2,"skin"],
  ["ell",8,8,7,5,"shell"], ["line",4,5,4,11,"dark"], ["line",8,3,8,12,"dark"], ["line",12,5,12,11,"dark"], ["line",2,8,14,8,"dark"],
  ["ell",15,11,2,2,"skin"], ["px",15,10,"dark"]])
spr("smilodon", 16, 28, {"fur":"#c89a58","dark":"#6a4a28","tusk":"#fff4d8","eye":"#ffe070","nose":"#4a2a20"}, [
  ["ell",1,8,2,1,"fur"], ["rect",3,11,2,4,"dark"], ["rect",6,11,2,4,"dark"], ["rect",9,11,2,4,"dark"], ["rect",12,11,2,4,"dark"],
  ["ell",7,9,6,4,"fur"], ["line",5,6,5,9,"dark"], ["line",8,6,8,9,"dark"],
  ["ell",13,7,3,3,"fur"], ["line",14,9,14,12,"tusk"], ["line",15,9,15,11,"tusk"], ["px",12,4,"dark"], ["px",14,4,"dark"], ["px",14,6,"eye"], ["px",15,8,"nose"]])
spr("infected_mammoth", 32, 32, {"fur":"#7a5f4a","dark":"#3a2a22","tusk":"#e8e0c0","sac":"#6dd85a","glow":"#d0ff90"}, [
  ["rect",6,24,4,7,"dark"], ["rect",12,25,4,6,"dark"], ["rect",18,25,4,6,"dark"], ["rect",23,24,4,7,"dark"],
  ["ell",15,18,12,9,"fur"], ["ell",26,16,5,6,"fur"], ["rect",29,18,3,9,"fur"], ["line",28,22,31,20,"tusk"], ["line",27,23,31,22,"tusk"],
  ["ell",23,13,2,3,"dark"], ["ell",10,11,3,3,"sac"], ["ell",18,10,4,3,"sac"], ["ell",22,16,2,2,"sac"], ["px",27,14,"glow"], ["px",11,11,"glow"], ["px",19,10,"glow"]])

# ---------- Eggs ----------
spr("egg_raptor", 16, 16, {"shell":"#efe6c8","spot":"#86b84e","dark":"#8a7a50"}, [
  ["ell",8,9,5,6,"shell"], ["px",6,7,"spot"], ["px",7,7,"spot"], ["px",10,10,"spot"], ["px",9,11,"spot"], ["px",6,12,"dark"], ["px",9,6,"dark"]], outline_col="#3a2a18")
spr("egg_locked", 16, 16, {"shell":"#6a6f7a","q":"#d0d4dc"}, [
  ["ell",8,9,5,6,"shell"], ["rect",7,6,3,1,"q"], ["rect",9,7,1,2,"q"], ["rect",8,9,1,1,"q"], ["px",8,11,"q"]], outline_col="#1a1d24")

# ---------- Icons (12 grid, flat) ----------
def icon(id, pal, shapes, grid=12): spr(id, grid, grid, pal, shapes, style="icon")
icon("icon_heart", {"r":"#e04050","h":"#ff9aa8"}, [["rect",1,2,4,3,"r"],["rect",6,2,4,3,"r"],["rect",1,4,9,3,"r"],["rect",2,7,7,1,"r"],["rect",3,8,5,1,"r"],["rect",4,9,3,1,"r"],["px",2,3,"h"]])
icon("icon_meat", {"b":"#e8e0c8","m":"#c8503a","h":"#e8806a"}, [["rect",2,2,6,5,"m"],["rect",3,1,4,1,"m"],["rect",3,7,4,1,"m"],["px",3,3,"h"],["px",4,3,"h"],["rect",7,6,3,1,"b"],["rect",9,5,1,5,"b"],["rect",8,9,3,1,"b"]])
icon("icon_stamina", {"o":"#f0b030","h":"#fff0a0","d":"#b07010"}, [["rect",3,1,6,1,"o"],["rect",2,2,8,8,"o"],["rect",3,10,6,1,"o"],["rect",3,2,3,2,"h"],["rect",7,8,3,2,"d"],["rect",6,9,2,1,"d"]])
icon("icon_speed", {"c":"#7fd8f0"}, [["line",1,2,5,5,"c"],["line",5,6,1,9,"c"],["line",6,2,10,5,"c"],["line",10,6,6,9,"c"]])
icon("icon_claw", {"c":"#f0f0f0","r":"#e04050"}, [["line",2,1,6,10,"c"],["line",5,1,9,10,"c"],["line",8,1,11,9,"c"],["px",3,3,"r"],["px",6,3,"r"]])
icon("icon_leap", {"c":"#f0e080"}, [["line",1,9,3,4,"c"],["line",3,4,6,2,"c"],["line",6,2,9,4,"c"],["line",9,4,10,8,"c"],["px",8,8,"c"],["px",11,8,"c"],["px",9,9,"c"],["px",10,9,"c"],["px",10,10,"c"]])
icon("icon_eye", {"w":"#ffffff","g":"#6fc24e","k":"#101010"}, [["rect",2,5,8,3,"w"],["rect",4,4,4,1,"w"],["rect",4,8,4,1,"w"],["rect",5,4,2,5,"g"],["rect",5,5,2,3,"k"]])
icon("icon_drop", {"r":"#e04050","h":"#ff9aa8"}, [["px",5,1,"r"],["rect",4,2,3,2,"r"],["rect",3,4,5,3,"r"],["rect",4,7,3,2,"r"],["px",4,5,"h"]])
icon("icon_bolt", {"y":"#ffe060"}, [["rect",6,0,2,1,"y"],["line",7,0,4,5,"y"],["rect",3,5,5,1,"y"],["line",7,5,4,11,"y"],["px",5,6,"y"]])
icon("icon_skull", {"w":"#e8e8e8","k":"#101010"}, [["rect",2,1,8,6,"w"],["rect",3,7,6,2,"w"],["rect",3,3,2,2,"k"],["rect",7,3,2,2,"k"],["px",5,6,"k"],["px",6,7,"k"],["px",4,8,"k"],["px",7,8,"k"]])
icon("icon_shield", {"b":"#6fa8e8","d":"#3a6aa8"}, [["rect",2,1,8,5,"b"],["rect",3,6,6,2,"b"],["rect",4,8,4,1,"b"],["rect",5,9,2,1,"b"],["rect",2,1,8,1,"d"],["rect",5,2,2,6,"d"]])
icon("icon_spore", {"g":"#8dff6a","p":"#7a4aa8"}, [["rect",3,3,3,3,"g"],["rect",7,2,2,2,"p"],["rect",6,7,3,3,"g"],["rect",2,8,2,2,"p"]])
icon("icon_weak", {"p":"#a0a0c0","k":"#404060"}, [["line",2,2,9,9,"p"],["line",9,2,2,9,"p"],["px",6,6,"k"]])
icon("icon_stun", {"y":"#ffe060"}, [["px",5,1,"y"],["rect",4,2,3,1,"y"],["rect",2,3,7,1,"y"],["rect",4,5,3,1,"y"],["px",5,6,"y"],["rect",3,8,5,1,"y"],["px",5,9,"y"]])
icon("icon_question", {"y":"#ffe060","k":"#000000"}, [["rect",4,1,4,1,"y"],["rect",3,2,2,2,"y"],["rect",7,2,2,3,"y"],["rect",6,5,2,1,"y"],["rect",5,6,2,2,"y"],["rect",5,9,2,2,"y"]])
icon("icon_alert", {"r":"#ff4040"}, [["rect",5,1,2,6,"r"],["rect",5,8,2,2,"r"]])
icon("icon_clear", {"y":"#ffe060","o":"#f0b030"}, [["rect",4,4,4,4,"y"],["rect",3,5,6,2,"y"],["rect",5,1,2,2,"o"],["rect",5,9,2,2,"o"],["rect",1,5,2,2,"o"],["rect",9,5,2,2,"o"]])
icon("icon_fog", {"w":"#d0dce4","g":"#8a98a4"}, [["rect",1,2,8,1,"w"],["rect",3,4,8,1,"g"],["rect",1,6,9,1,"w"],["rect",2,8,8,1,"g"],["rect",4,10,6,1,"w"]])
icon("icon_rain", {"c":"#8a98a8","b":"#5f9fe8"}, [["rect",2,1,8,3,"c"],["rect",1,2,10,2,"c"],["line",3,6,2,8,"b"],["line",6,6,5,9,"b"],["line",9,6,8,8,"b"],["px",4,10,"b"]])
icon("icon_storm", {"c":"#5a5a78","y":"#ffe060"}, [["rect",2,1,8,3,"c"],["rect",1,2,10,2,"c"],["line",6,4,4,7,"y"],["rect",4,7,3,1,"y"],["line",6,7,4,11,"y"]])
icon("icon_heat", {"r":"#f06a30","y":"#ffd060"}, [["rect",3,3,6,6,"r"],["rect",2,4,8,4,"r"],["rect",5,5,2,2,"y"],["px",1,1,"r"],["px",10,1,"r"],["px",1,10,"r"],["px",10,10,"r"],["px",5,0,"r"],["px",5,11,"r"]])
icon("icon_cold", {"c":"#bfeaff"}, [["line",5,0,5,11,"c"],["line",0,5,11,5,"c"],["line",1,1,10,10,"c"],["line",10,1,1,10,"c"],["px",4,1,"c"],["px",6,1,"c"],["px",4,10,"c"],["px",6,10,"c"]])
icon("icon_deck", {"a":"#c8b890","b":"#7a6a48"}, [["rect",1,2,7,9,"b"],["rect",3,1,7,9,"a"],["rect",4,3,5,1,"b"],["rect",4,5,5,1,"b"],["rect",4,7,3,1,"b"]])

json.dump(S, open("data/sprites.json","w"), indent=0)
print(len(S), "sprites")
