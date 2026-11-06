class_name MenuForest
extends Control
## Main-menu background: a layered forest scene built from the supplied jungle sprites (dense canopy backdrop, tree lines, bushes, ferns,
## rocks / logs, an iso grass floor), parallax depth (slow automatic drift + a slight mouse parallax), gently swaying foliage and a few
## SLOW falling leaves (green, occasionally golden). Data: data/menu_scene.json. Layout is generated per "slot" from hashes, so the scenery
## extends to any window width / height (no stretching, no mirroring needed) and is stable between frames.
## Whole-number scales + nearest filtering everywhere. Designer art: menu_bg_back.png, menu_bg_floor.png, menu_bg_<category>_<n>.png.

const FRAME := Vector2(640, 360)
const CX := 320.0                         # the frame's horizontal centre

var t: float = 0.0
var origin: Vector2 = Vector2.ZERO          # where the 640x360 frame's top-left sits inside this control
var mouse_norm: Vector2 = Vector2.ZERO      # -0.5..0.5, set from the mouse position (0 when there is none)
var cur_off: Vector2 = Vector2.ZERO         # smoothed parallax offset (px, before the per-layer factor)
var cfg: Dictionary = {}
var drawn: Dictionary = {"sprites": 0, "tiles": 0, "leaves": 0}

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	cfg = config()

static func config() -> Dictionary:
	return DB.table("menu_scene")

static func _h(i: int, k: int) -> float:
	return fposmod(sin(float(i) * 12.9898 + float(k) * 78.233) * 43758.5453, 1.0)

## Sprite ids of a category. A designer override menu_bg_<cat>_<n>.png (n = 1..12) replaces the whole list when any exist.
static func sprites(cat: String) -> Array:
	var ov: Array = []
	for n in range(1, 13):
		var nm := "menu_bg_%s_%d" % [cat, n]
		if SpriteFactory.png(nm) != null:
			ov.append(nm)
	if not ov.is_empty():
		return ov
	return (config()["categories"] as Dictionary).get(cat, [])

static func tex(id: String) -> Texture2D:
	return SpriteFactory.png(id) if SpriteFactory.png(id) != null else SpriteFactory.get_texture(id)

## Every sprite id the scene can use (tests check they exist).
static func all_sprite_ids() -> Array:
	var c := config()
	var out: Array = [String(c["back"]["sprite"])]
	for cat in c["categories"]:
		out.append_array(c["categories"][cat])
	for p in c["floor"]["pool"]:
		out.append("tile_jungle_ground_%d" % int(p))
	return out

# ------------------------------------------------------------------ layout

## The item in slot k of a layer: {} (empty slot) or {x, y, sprite, flip} in frame coordinates (y is the sprite's bottom).
static func slot_item(layer: Dictionary, k: int) -> Dictionary:
	var seed := int(layer.get("seed", 1)) * 977
	var sp := float(layer["spacing"])
	var x := CX + float(k) * sp + (_h(k + seed, 1) * 2.0 - 1.0) * float(layer.get("jitter", 0.0))
	var edge := float(layer.get("side_only", 0.0))
	if edge > 0.0 and absf(x - CX) < edge:
		return {}
	if _h(k + seed, 2) >= float(layer.get("prob", 1.0)):
		return {}
	var cat := String(layer["cat"])
	if layer.has("cat2") and _h(k + seed, 5) < 0.4:
		cat = String(layer["cat2"])
	var list: Array = sprites(cat)
	if list.is_empty():
		return {}
	var id := String(list[int(_h(k + seed, 3) * float(list.size())) % list.size()])
	return {"x": roundf(x), "y": float(layer["y"]) + (_h(k + seed, 4) * 2.0 - 1.0) * float(layer.get("y_jitter", 0.0)),
		"sprite": id, "flip": _h(k + seed, 6) < 0.5}

## All items of a layer that can be visible in a viewport of width `vpw` (origin.x = left margin of the 640 frame).
func items_in(layer: Dictionary, vpw: float, cam_x: float = 0.0) -> Array:
	var sp := float(layer["spacing"])
	var margin := 170.0
	var k0 := int(floor((-origin.x - margin + cam_x - CX) / sp))
	var k1 := int(ceil((vpw - origin.x + margin + cam_x - CX) / sp))
	var out: Array = []
	for k in range(k0, k1 + 1):
		var it := slot_item(layer, k)
		if not it.is_empty():
			out.append(it)
	return out

## Designer leaf sprites (menu_bg_leaf_1..12.png); empty = the procedural leaves.
static func leaf_overrides() -> Array:
	var out: Array = []
	for n in range(1, 13):
		var nm := "menu_bg_leaf_%d" % n
		if SpriteFactory.png(nm) != null:
			out.append(nm)
	return out

## Falling leaf i at time tt in a viewport `vp`: {pos, scale, color, flip, alpha, sprite}. Slow, gentle, swaying.
static func leaf_state(i: int, tt: float, vp: Vector2) -> Dictionary:
	var lv: Dictionary = config()["leaves"]
	var sc: Array = lv["scales"]
	var scale := int(sc[int(_h(i, 41) * float(sc.size())) % sc.size()])
	var depth := float(scale) / float(sc[sc.size() - 1])          # bigger leaves are closer: a little faster
	var fr: Array = lv["fall"]
	var fall := lerpf(float(fr[0]), float(fr[1]), _h(i, 42)) * (0.7 + 0.5 * depth)
	var dr: Array = lv["drift"]
	var drift := lerpf(float(dr[0]), float(dr[1]), _h(i, 43)) * (0.7 + 0.5 * depth)
	var sw: Array = lv["sway"]
	var sway := lerpf(float(sw[0]), float(sw[1]), _h(i, 44))
	var fq: Array = lv["freq"]
	var freq := lerpf(float(fq[0]), float(fq[1]), _h(i, 45))
	var travel := vp.y + 50.0
	var life := travel / fall
	var ph := fposmod(tt + _h(i, 46) * life, life)
	var age := ph * fall
	var wrap_w := vp.x + 50.0
	var x := fposmod(_h(i, 47) * wrap_w + drift * ph + sin(ph * freq * TAU + float(i)) * sway, wrap_w) - 25.0
	var y := -25.0 + age
	var colors: Array = lv["colors"]
	var col := Color(String(colors[int(_h(i, 48) * float(colors.size())) % colors.size()]))
	if _h(i, 49) < float(lv["gold_chance"]):
		col = Color(String(lv["gold"]))
	var fade := clampf(age / 40.0, 0.0, 1.0) * clampf((travel - age) / 40.0, 0.0, 1.0)
	var leaves: Array = leaf_overrides()
	var shapes: Array = lv["shapes"]
	var shape_i := int(_h(i, 50) * float(shapes.size())) % shapes.size()
	return {"shape": shape_i, "sprite": "" if leaves.is_empty() else String(leaves[int(_h(i, 50) * float(leaves.size())) % leaves.size()]),
		"pos": Vector2(x, y), "scale": scale, "color": col, "alpha": (0.7 + 0.28 * depth) * fade, "flip": cos(ph * freq * TAU + float(i)) < 0.0, "fall": fall, "gold": col == Color(String(lv["gold"]))}

# ------------------------------------------------------------------ time / parallax

func advance(dt: float) -> void:
	t += dt
	var pr: Dictionary = cfg["parallax"]
	var target := mouse_norm * float(pr["mouse"]) * 2.0
	target.x += sin(t * float(pr["auto_speed"]) * TAU) * float(pr["auto"])
	cur_off = cur_off.lerp(target, clampf(dt * 2.5, 0.0, 1.0))
	queue_redraw()

func layer_cam(par: float) -> Vector2:
	return Vector2(roundf(cur_off.x * par), roundf(cur_off.y * par * 0.5))

# ------------------------------------------------------------------ drawing

func _draw() -> void:
	var vp := size
	if vp.x < 4.0 or cfg.is_empty():
		return
	drawn = {"sprites": 0, "tiles": 0, "leaves": 0}
	draw_rect(Rect2(Vector2.ZERO, vp), Color("#12301c"))
	_draw_back(vp)
	var horizon := float(cfg["horizon"])
	var floor_drawn := false
	for ly in cfg["layers"]:
		# the iso grass floor sits between the far tree lines and the props / foliage in front
		if not floor_drawn and String(ly["id"]) == "props":
			_draw_floor(vp)
			floor_drawn = true
		_draw_layer(ly, vp)
	_draw_leaves(vp)
	_draw_readability(vp)

func _draw_back(vp: Vector2) -> void:
	var b: Dictionary = cfg["back"]
	var tx := tex("menu_bg_back") if SpriteFactory.png("menu_bg_back") != null else tex(String(b["sprite"]))
	if tx == null:
		return
	var sc := float(b["scale"])
	var sz := tx.get_size() * sc
	var cam := layer_cam(float(b["par"]))
	var o := (origin - cam).round()
	var tint := Color(String(b["tint"]))
	var kx0 := int(floor(-o.x / sz.x)) - 1
	var kx1 := int(ceil((vp.x - o.x) / sz.x))
	var ky0 := int(floor(-o.y / sz.y)) - 1
	var ky1 := int(ceil((vp.y - o.y) / sz.y))
	for ky in range(ky0, ky1 + 1):
		for kx in range(kx0, kx1 + 1):
			# mirrored neighbours hide the seams (no stretching)
			var x := o.x + kx * sz.x
			var y := o.y + ky * sz.y
			var fx := posmod(kx, 2) == 1
			var fy := posmod(ky, 2) == 1
			var src := Rect2(Vector2.ZERO, tx.get_size())
			var dst := Rect2(x, y, sz.x, sz.y)
			draw_set_transform(Vector2(x + sz.x * 0.5, y + sz.y * 0.5), 0.0, Vector2(-1.0 if fx else 1.0, -1.0 if fy else 1.0))
			draw_texture_rect(tx, Rect2(-sz.x * 0.5, -sz.y * 0.5, sz.x, sz.y), false, tint)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_floor(vp: Vector2) -> void:
	var f: Dictionary = cfg["floor"]
	var sc := float(f["scale"])
	var pool: Array = f["pool"]
	var single: Texture2D = SpriteFactory.png("menu_bg_floor")
	var tsz := (single.get_size() if single != null else Vector2(32, 16)) * sc
	var cam := layer_cam(float(f["par"]))
	var top := origin.y + float(cfg["horizon"]) - 2.0 * sc
	var rows := int(ceil((vp.y - top) / (tsz.y * 0.5))) + 2
	var tint := Color(String(f["tint"]))
	var haze := Color(String(f["haze"]))
	var hrows := float(f["haze_rows"])
	for r in rows:
		var rt := tint.lerp(haze, clampf(1.0 - float(r) / hrows, 0.0, 1.0) * 0.8)
		var y := roundf(top + float(r) * tsz.y * 0.5)
		var xoff := (tsz.x * 0.5) if (r % 2) == 1 else 0.0
		var c0 := int(floor((-origin.x + cam.x - xoff) / tsz.x)) - 1
		var c1 := int(ceil((vp.x - origin.x + cam.x - xoff) / tsz.x)) + 1
		for c in range(c0, c1 + 1):
			var x := roundf(origin.x + float(c) * tsz.x + xoff - cam.x)
			var tx: Texture2D = single
			if tx == null:
				tx = tex("tile_jungle_ground_%d" % int(pool[int(_h(r * 131 + c, 61) * float(pool.size())) % pool.size()]))
			draw_texture_rect(tx, Rect2(x, y, tsz.x, tsz.y), false, rt)
			drawn["tiles"] = int(drawn["tiles"]) + 1

func _draw_layer(ly: Dictionary, vp: Vector2) -> void:
	var par := float(ly["par"])
	var cam := layer_cam(par)
	var sc := float(ly["scale"])
	var tint := Color(String(ly.get("tint", "#ffffff")))
	var sway := float(ly.get("sway", 0.0))
	var bottom := String(ly.get("anchor", "")) == "bottom"
	for it in items_in(ly, vp.x, cam.x):
		var tx := tex(String(it["sprite"]))
		if tx == null:
			continue
		var sz := tx.get_size() * sc
		var x: float = origin.x + float(it["x"]) - cam.x
		if sway > 0.0:
			x += roundf(sin(t * 0.6 + float(it["x"]) * 0.013) * sway) * sc
		var yb: float = (vp.y - (FRAME.y - float(it["y"]))) if bottom else (origin.y + float(it["y"]) - cam.y)
		var r := Rect2(roundf(x - sz.x * 0.5), roundf(yb - sz.y), sz.x, sz.y)
		if r.end.x < 0.0 or r.position.x > vp.x or r.position.y > vp.y:
			continue
		if bool(it["flip"]):
			draw_set_transform(Vector2(r.position.x + sz.x * 0.5, 0.0), 0.0, Vector2(-1.0, 1.0))
			draw_texture_rect(tx, Rect2(-sz.x * 0.5, r.position.y, sz.x, sz.y), false, tint)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_texture_rect(tx, r, false, tint)
		drawn["sprites"] = int(drawn["sprites"]) + 1

func _draw_leaves(vp: Vector2) -> void:
	var n := int(cfg["leaves"]["count"])
	var shapes: Array = cfg["leaves"]["shapes"]
	for i in n:
		var s := leaf_state(i, t, vp)
		var sc := float(s["scale"])
		var p: Vector2 = (s["pos"] as Vector2).round()
		var col: Color = s["color"]
		col.a = float(s["alpha"])
		if String(s["sprite"]) != "":
			var tx := tex(String(s["sprite"]))
			var sz := tx.get_size() * sc
			draw_texture_rect(tx, Rect2(p, sz), false, Color(1, 1, 1, col.a))
		else:
			var rows: Array = shapes[int(s["shape"])]
			var flip: bool = bool(s["flip"])
			var hi := col.lightened(0.3)
			var mid := col.darkened(0.35)
			var edge := Color(0.03, 0.09, 0.03, col.a * 0.6)
			for pass_i in 2:                     # 1: dark outline under every cell, 2: the leaf colours on top (no cell seams)
				for yy in rows.size():
					var row := String(rows[yy])
					for xx in row.length():
						var ch := row[(row.length() - 1 - xx) if flip else xx]
						if ch == ".":
							continue
						var cr := Rect2(p.x + float(xx) * sc, p.y + float(yy) * sc, sc, sc)
						if pass_i == 0:
							draw_rect(cr.grow(1.0), edge)
						else:
							draw_rect(cr, col if ch == "b" else (hi if ch == "h" else mid))
		drawn["leaves"] = int(drawn["leaves"]) + 1

## Keeps the title and the buttons readable: dark edge vignette, a soft darkening behind the title / buttons, and a translucent panel behind the buttons.
func _draw_readability(vp: Vector2) -> void:
	var rd: Dictionary = cfg["readability"]
	var va := float(rd["vignette_alpha"])
	var th := vp.y * 0.05
	for k in 9:
		var c := Color(0.0, 0.03, 0.0, va * pow(1.0 - float(k) / 9.0, 1.6))
		var ins := float(k) * th
		draw_rect(Rect2(0, ins, vp.x, th), c)
		draw_rect(Rect2(0, vp.y - ins - th, vp.x, th), c)
		draw_rect(Rect2(ins, 0, th, vp.y), c)
		draw_rect(Rect2(vp.x - ins - th, 0, th, vp.y), c)
	var ga := float(rd["glow_alpha"])
	var c0 := origin + Vector2(CX, 224)
	for k in 6:
		var rx := 250.0 - float(k) * 27.0
		var ry := 165.0 - float(k) * 19.0
		var yy := -ry
		while yy <= ry:
			var q := 1.0 - (yy / ry) * (yy / ry)
			if q > 0.0:
				var hw := rx * sqrt(q)
				draw_rect(Rect2(roundf(c0.x - hw), roundf(c0.y + yy), roundf(hw * 2.0), 2.0), Color(0.0, 0.04, 0.0, ga))
			yy += 2.0
	var pr: Array = rd["panel"]
	var pr_rect := Rect2(origin.x + float(pr[0]), origin.y + float(pr[1]), float(pr[2]), float(pr[3]))
	draw_rect(pr_rect, Color(0.02, 0.07, 0.03, float(rd["panel_alpha"])))
	draw_rect(pr_rect, Color(0.94, 0.75, 0.31, 0.22), false, 1.0)
