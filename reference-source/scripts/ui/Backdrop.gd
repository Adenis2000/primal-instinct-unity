class_name Backdrop
extends Control
## Prehistoric backdrop behind every menu screen (replaces the old tiled-diamond ground): packed earth, subtle ANIMAL fossils
## (ammonite, dinosaur skull / ribs / vertebrae), dinosaur footprint trails, stones, roots, one big partly buried dinosaur skeleton
## at a window edge, and a few slowly falling leaves (jungle) / snow (tundra) / dust (cave).
## Everything is data-driven (data/backdrops.json, art in assets/sprites/bd_*.png by tools/art/art_backdrop.py), anchored to the
## real window (visible rect = viewport, so big windows show MORE ground, never borders), and drawn at an integer art-pixel size.

var theme_id: String = "jungle"
var dim: float = 0.7
var stats := {"decor": 0, "prints": 0, "skeleton": false, "particles": 0}
var _last_key := ""
var _layer: Particles = null

static func cfg() -> Dictionary:
	return DB.table("backdrops")

static func theme_cfg(id: String) -> Dictionary:
	var t: Dictionary = cfg()["themes"]
	return t.get(id, t["jungle"])

## All sprite ids a theme uses (tests check they exist).
static func sprite_ids(id: String) -> Array:
	var t := theme_cfg(id)
	var out: Array = [t["ground"], t["skeleton"]["sprite"], t["trail"]["left"], t["trail"]["right"]]
	for d in t["decor"]:
		out.append(d["sprite"])
	if t["particles"].has("sprites"):
		out.append_array(t["particles"]["sprites"])
	return out

static func _rnd(seed_: int, k: int) -> float:
	return float(RunState.mix(seed_, k) & 0xffff) / 65536.0

static func _tex(id: String) -> Texture2D:
	return SpriteFactory.get_texture(id)

## Decor piece for decor-grid cell (cx, cy): {} or {sprite, pos} (logical px, snapped to the art-pixel grid).
static func decor_in_cell(cx: int, cy: int, id: String) -> Dictionary:
	var c := cfg()
	var t := theme_cfg(id)
	var px := int(c["px"])
	var cell := int(c["cell"])
	var s := RunState.mix(cx * 7919 + 13, cy * 104729 + 29)
	if _rnd(s, 1) >= float(c["density"]):
		return {}
	var total := 0.0
	for d in t["decor"]:
		total += float(d["w"])
	var pick := _rnd(s, 2) * total
	var sprite := String(t["decor"][0]["sprite"])
	for d in t["decor"]:
		pick -= float(d["w"])
		if pick <= 0.0:
			sprite = String(d["sprite"])
			break
	var sz := _tex(sprite).get_size() * px
	var fx := _rnd(s, 3) * maxf(0.0, cell - sz.x)
	var fy := _rnd(s, 4) * maxf(0.0, cell - sz.y)
	var pos := Vector2(cx * cell + fx, cy * cell + fy)
	pos = Vector2(floorf(pos.x / px) * px, floorf(pos.y / px) * px)
	return {"sprite": sprite, "pos": pos}

## Footprint trail for trail-cell (cx, cy): array of {sprite, pos (centre), rot}. Walks in one of 4 directions (exact 90 degree turns keep pixels crisp).
static func trail_in_cell(cx: int, cy: int, id: String) -> Array:
	var c := cfg()
	var t: Dictionary = theme_cfg(id)["trail"]
	var px := int(c["px"])
	var cell := int(c["trail_cell"])
	var s := RunState.mix(cx * 6571 + 71, cy * 90001 + 43)
	var out: Array = []
	if _rnd(s, 1) >= float(t["chance"]):
		return out
	var n := int(t["min"]) + int(_rnd(s, 2) * (int(t["max"]) - int(t["min"]) + 1))
	var dir := int(_rnd(s, 3) * 4.0) % 4
	var rot := dir * PI * 0.5
	var along := Vector2.from_angle(rot - PI * 0.5)
	var perp := along.rotated(PI * 0.5)
	var start := Vector2(cx * cell + 70.0 + _rnd(s, 4) * (cell - 140.0), cy * cell + 70.0 + _rnd(s, 5) * (cell - 140.0))
	for i in n:
		var side := 1 if i % 2 == 0 else -1
		var p := start + along * float(i * int(t["step"]) * px) + perp * float(side * int(t["stride"]) * px) * 0.25
		p = Vector2(roundf(p.x / px) * px, roundf(p.y / px) * px)
		out.append({"sprite": String(t["right"] if side > 0 else t["left"]), "pos": p, "rot": rot})
	return out

## Where the big skeleton sits for a visible rect (logical coords).
static func skeleton_rect(vis: Rect2, id: String) -> Rect2:
	var c := cfg()
	var k: Dictionary = theme_cfg(id)["skeleton"]
	var sz := _tex(String(k["sprite"])).get_size() * int(c["px"])
	var f := float(k["x"])
	var b := float(k["bleed"]) * sz.x
	var x := lerpf(vis.position.x - b, vis.end.x - sz.x + b, f)
	var y := vis.end.y - sz.y * float(k["visible"])
	return Rect2(Vector2(roundf(x), roundf(y)), sz)

func _ready() -> void:
	_layer = Particles.new()
	_layer.owner_bd = self
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_layer)

func visible_rect() -> Rect2:
	return Rect2(-global_position.round(), get_viewport_rect().size)

func _process(_dt: float) -> void:
	var key := "%s|%s" % [global_position.round(), get_viewport_rect().size]
	if key != _last_key:
		_last_key = key
		queue_redraw()

func _draw() -> void:
	var c := cfg()
	var t := theme_cfg(theme_id)
	var px := int(c["px"])
	var vis := visible_rect()
	# --- packed earth, seamless, aligned to the art-pixel grid
	var gt := _tex(String(t["ground"]))
	var T := float(gt.get_width() * px)
	var gx := floorf(vis.position.x / T) * T
	var gy := floorf(vis.position.y / T) * T
	var gr := Rect2(gx, gy, ceilf((vis.end.x - gx) / T) * T, ceilf((vis.end.y - gy) / T) * T)
	draw_texture_rect(gt, gr, true)
	# --- decor (fossils, stones, roots) + footprint trails, kept clear of the big skeleton
	var sk := skeleton_rect(vis, theme_id)
	var keep := sk.grow(10.0)
	var a := float(c["decor_alpha"])
	stats = {"decor": 0, "prints": 0, "skeleton": true, "particles": 0}
	var cell := int(c["cell"])
	for cy in range(int(floorf(vis.position.y / cell)) - 1, int(floorf(vis.end.y / cell)) + 2):
		for cx in range(int(floorf(vis.position.x / cell)) - 1, int(floorf(vis.end.x / cell)) + 2):
			var d := decor_in_cell(cx, cy, theme_id)
			if d.is_empty():
				continue
			var tex := _tex(String(d["sprite"]))
			var r := Rect2(d["pos"], tex.get_size() * px)
			if r.intersects(keep) or not r.intersects(vis):
				continue
			draw_texture_rect(tex, r, false, Color(1, 1, 1, a))
			stats["decor"] += 1
	var tc := int(c["trail_cell"])
	for cy in range(int(floorf(vis.position.y / tc)) - 1, int(floorf(vis.end.y / tc)) + 2):
		for cx in range(int(floorf(vis.position.x / tc)) - 1, int(floorf(vis.end.x / tc)) + 2):
			for p in trail_in_cell(cx, cy, theme_id):
				var tex := _tex(String(p["sprite"]))
				var sz := tex.get_size() * px
				var cr := Rect2(p["pos"] - sz * 0.5, sz)
				if not cr.grow(sz.x).intersects(vis) or cr.grow(sz.x).intersects(keep):
					continue
				draw_set_transform(p["pos"], float(p["rot"]), Vector2.ONE)
				draw_texture_rect(tex, Rect2(-sz * 0.5, sz), false, Color(1, 1, 1, a))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				stats["prints"] += 1
	# --- the big partly buried skeleton at the window edge
	draw_texture_rect(_tex(String(t["skeleton"]["sprite"])), sk, false, Color(1, 1, 1, a))
	# --- tint / dim (low contrast so UI text stays readable)
	draw_rect(vis, Color(Color.html(String(t["tint"])), clampf(dim * float(t["dim_scale"]), 0.0, 1.0)))
	if _layer != null:
		_layer.queue_redraw()

## Sparse slowly falling leaves / snow / dust, drawn above the dim.
class Particles extends Control:
	var owner_bd: Backdrop = null
	var items: Array = []
	var _vis := Rect2()
	var _rng := RandomNumberGenerator.new()
	var _t := 0.0

	func _ready() -> void:
		_rng.seed = 424242
		set_anchors_preset(Control.PRESET_TOP_LEFT)
		size = Vector2(640, 360)

	func _fill(vis: Rect2, pc: Dictionary) -> void:
		_vis = vis
		var want := int(round(vis.size.x * vis.size.y / 100000.0 * float(pc["per_100k"])))
		while items.size() > want:
			items.pop_back()
		while items.size() < want:
			items.append(_spawn(pc, true))

	func _spawn(pc: Dictionary, anywhere: bool) -> Dictionary:
		var sp: Array = pc["speed"]
		return {"x": _rng.randf_range(_vis.position.x, _vis.end.x),
			"y": _rng.randf_range(_vis.position.y, _vis.end.y) if anywhere else _vis.position.y - 12.0,
			"v": _rng.randf_range(float(sp[0]), float(sp[1])), "ph": _rng.randf() * TAU, "fq": _rng.randf_range(0.5, 1.1),
			"k": _rng.randi() % 3, "dx": _rng.randf_range(-1.5, 3.0)}

	func _process(dt: float) -> void:
		if owner_bd == null:
			return
		dt = minf(dt, 0.1)
		_t += dt
		var pc: Dictionary = Backdrop.theme_cfg(owner_bd.theme_id)["particles"]
		var vis := owner_bd.visible_rect()
		if vis != _vis or items.size() != int(round(vis.size.x * vis.size.y / 100000.0 * float(pc["per_100k"]))):
			_fill(vis, pc)
		for p in items:
			p["y"] += p["v"] * dt
			p["x"] += p["dx"] * dt
			if p["y"] > _vis.end.y + 12.0 or p["x"] > _vis.end.x + 20.0:
				var n := _spawn(pc, false)
				p["x"] = n["x"]; p["y"] = n["y"]; p["v"] = n["v"]; p["ph"] = n["ph"]; p["k"] = n["k"]; p["dx"] = n["dx"]
		queue_redraw()

	func _draw() -> void:
		if owner_bd == null:
			return
		var pc: Dictionary = Backdrop.theme_cfg(owner_bd.theme_id)["particles"]
		var px := int(Backdrop.cfg()["px"])
		var al := float(pc["alpha"])
		var sway := float(pc["sway"])
		owner_bd.stats["particles"] = items.size()
		for p in items:
			var sw: float = sin(_t * float(p["fq"]) + float(p["ph"]))
			var pos := Vector2(roundf((float(p["x"]) + sw * sway) / px) * px, roundf(float(p["y"]) / px) * px)
			if pc.has("sprites"):
				var ids: Array = pc["sprites"]
				var tex := Backdrop._tex(String(ids[int(p["k"]) % ids.size()]))
				var sz := tex.get_size() * px
				if sw < 0.0:                                     # tumbling leaf: mirrored half the time
					draw_texture_rect(tex, Rect2(pos + Vector2(sz.x, 0), Vector2(-sz.x, sz.y)), false, Color(1, 1, 1, al))
				else:
					draw_texture_rect(tex, Rect2(pos, sz), false, Color(1, 1, 1, al))
			else:
				var col := Color.html(String(pc["color"]))
				col.a = al
				var s := float(int(pc.get("size", 1)) * px)
				draw_rect(Rect2(pos, Vector2(s, s)), col)
