class_name BattleBoard
extends Control
## Isometric battlefield renderer + picking. Pure presentation: input is forwarded as signals.
## Layers (back to front): backdrop, ground tiles, grid lines, highlights, facing arrows, depth-sorted
## props + units (sorted by x+y, see Iso.depth), foreground foliage, ambient particles/weather, unit overlays.

signal tile_clicked(pos: Vector2i, button: int)
signal tile_hovered(pos: Vector2i)

var battle: Battle
var theme_id: String = "jungle"
var bg_variant: int = 0
var move_tiles: Dictionary = {}     # pos -> cost
var target_tiles: Dictionary = {}   # pos -> Color
var detect_tiles: Dictionary = {}   # pos -> true
var preview: Dictionary = {}        # enemy pos -> {"dir": "front|side|back", "mult": float}
var hover: Vector2i = Vector2i(-1, -1)
var current_uid: int = -1
var time: float = 0.0
var shake: float = 0.0
var pan_y: float = 0.0                     # stage-intro cinematic: the whole board is slid down by this many px (0 = normal framing)
var hide_overlays: bool = false
var show_move: bool = false

var _theme: Dictionary = {}
var _ground_var: Array = []
var _prop_var: Array = []
var _parts: Array = []
var _flakes: Array = []
var _flash: float = 0.0
var _flash_cd: float = 3.0
var weather_id: String = ""
var exit_vis: float = 0.0                 # 0 = exit paths hidden (corridor filled with trees) .. 1 = open
var _corridor: Dictionary = {}            # outside tile -> {exit, k, o}: the negative-space corridors of the exits
var _vis: Dictionary = {}                 # data/visibility.json (foliage fade + unit outline)
var _fade: Dictionary = {}                # part key -> current alpha (tweened)
var _fade_dt: float = 0.0
var _overlap_cache: Dictionary = {}       # part key -> does the sprite overlap the playable tiles
var _overlap_zoom: float = -1.0
var _sil_cache: Dictionary = {}           # texture instance id -> white silhouette texture (unit outlines)
## Secret entrance presentation: "crack" (faint detail while the area is still hostile) -> "sealed" (rock on the hole,
## explore start) -> "opening" (rock rolls away, dust) -> "open" (persistent soft glow).
var secret_state: String = "crack"
var secret_t: float = 0.0
const SECRET_OPEN_TIME := 1.1

func _init() -> void:
	position = Vector2.ZERO
	size = Vector2(640, 360)
	custom_minimum_size = size
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false

func setup(b: Battle, theme: String) -> void:
	battle = b
	theme_id = theme
	_theme = DB.theme(theme)
	_vis = DB.table("visibility")
	_fade.clear()
	_overlap_cache.clear()
	weather_id = b.weather_id
	var g := b.grid
	bg_variant = RunState.mix(RunState.mix(g.w * 31 + g.h, b.room.get("seed", 1)), 5) % maxi(1, int(_theme.get("bg_variants", 1)))
	_ground_var = []
	_prop_var = []
	for y in g.h:
		var r := []
		var pr := []
		for x in g.w:
			var h: int = RunState.mix(RunState.mix(x * 7 + 3, y * 13 + 5), int(g.variant[y][x]) + 17)
			# ground variants 1 and 4 are the dirt-patch ones: keep them rarer
			var pool := _ground_pool()
			r.append(pool[h % pool.size()])
			pr.append((h / 11) % 64)
		_ground_var.append(r)
		_prop_var.append(pr)
	_init_particles()
	zoom_manual = 0.0
	pan = Vector2.ZERO
	refit()
	_build_ring()
	gate_state = "locked" if b.exits_locked else ("locked" if (b.phase == "explore" and b.exits_unlock_anim) else "open")
	_build_corridors()
	exit_vis = exit_target()
	if b.phase == "explore":
		secret_state = "sealed" if b.secret_reveal else "open"
	else:
		secret_state = "crack"

## Camera: auto-fit the arena (largest zoom step that fits, centred); the player may zoom (wheel) and pan (arrows / middle-drag).
var zoom_manual: float = 0.0
var pan: Vector2 = Vector2.ZERO
var _drag_from: Vector2 = Vector2(-1, -1)
var view_off: Vector2 = Vector2.ZERO      # offset of the 640x360 frame inside the viewport (always zero on the fixed canvas)
var _outer_parts: Array = []
var _ring: Dictionary = {}          # tile -> steps outside the arena (0 = inside, void/outer tiles 1..RING_MAX)
const RING_MAX := 9

func refit() -> void:
	if battle == null:
		return
	Iso.extra_w = maxf(0.0, size.x - 640.0)
	Iso.extra_h = maxf(0.0, size.y - 360.0)
	# zoom-out limit (recomputed on every resize): a zoom that is now too far out snaps back to the minimum (whole-number zoom, no easing)
	var minz := Iso.min_zoom(battle.grid.w, battle.grid.h)
	if zoom_manual > 0.0 and zoom_manual < minz - 0.001:
		_ease_from = Iso.zoom if Iso.zoom > 0.0 else zoom_manual
		_ease_t = 0.0
		zoom_manual = minz
	var zshow := zoom_manual
	if _ease_t < ZOOM_EASE and zoom_manual > 0.0:
		var k := clampf(_ease_t / ZOOM_EASE, 0.0, 1.0)
		zshow = lerpf(_ease_from, zoom_manual, k * k * (3.0 - 2.0 * k))
	Iso.fit(battle.grid.w, battle.grid.h, zshow, pan)

var _ease_from: float = 0.0
var _ease_t: float = 99.0
const ZOOM_EASE := 0.0     # zoom steps are whole numbers (crisp pixels): they snap instead of easing

## Zoom-out limit of this arena at the current window size (see Iso.min_zoom).
func min_zoom() -> float:
	return Iso.min_zoom(battle.grid.w, battle.grid.h)

func zoom_steps() -> Array:
	return DB.table("arenas")["camera"]["zoom_steps"]

## Change zoom one step (dir +1 = closer). Returns the new zoom.
func step_zoom(dir: int) -> float:
	var steps := zoom_steps()
	var cur := Iso.zoom
	var idx := 0
	var best := 1e9
	for i in steps.size():
		if absf(float(steps[i]) - cur) < best:
			best = absf(float(steps[i]) - cur)
			idx = i
	# never further out than the minimum zoom (whole board + margin on screen)
	var minz := min_zoom()
	var last := steps.size() - 1
	while last > 0 and float(steps[last]) < minz - 0.001:
		last -= 1
	idx = clampi(idx - dir, 0, last)
	zoom_manual = float(steps[idx])
	_ease_t = 99.0
	_clamp_pan()
	refit()
	return zoom_manual

func pan_by(d: Vector2) -> void:
	pan += d
	_clamp_pan()
	refit()

func reset_camera() -> void:
	zoom_manual = 0.0
	pan = Vector2.ZERO
	refit()

## The arena can only be pushed so far that part of it stays inside the view band.
func _clamp_pan() -> void:
	var z := zoom_manual if zoom_manual > 0.0 else Iso.auto_zoom(battle.grid.w, battle.grid.h)
	var bs := Iso.board_size(battle.grid.w, battle.grid.h, z)
	var v: Array = DB.table("arenas")["camera"]["view"]
	var lim := Vector2(maxf(0.0, (bs.x - float(v[2]) - Iso.extra_w) * 0.5 + 64.0), maxf(0.0, (bs.y - float(v[3]) - Iso.extra_h) * 0.5 + 32.0))
	pan = Vector2(clampf(pan.x, -lim.x, lim.x), clampf(pan.y, -lim.y, lim.y))

## Multi-source BFS outward from the playable tiles: how far outside the arena each surrounding tile is (blend + foliage density).
func _build_ring() -> void:
	_ring = {}
	var g := battle.grid
	var q := []
	for y in g.h:
		for x in g.w:
			var p := Vector2i(x, y)
			if not g.is_void(p):
				_ring[p] = 0
				q.append(p)
	var head := 0
	while head < q.size():
		var cur: Vector2i = q[head]
		head += 1
		var d := int(_ring[cur])
		if d >= RING_MAX:
			continue
		for dd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cur + dd
			if not _ring.has(n):
				_ring[n] = d + 1
				q.append(n)

func ring_of(p: Vector2i) -> int:
	return int(_ring.get(p, RING_MAX + 1))

static func _hash(x: int, y: int, k: int) -> int:
	return RunState.mix(RunState.mix(x * 73856093 + 11, y * 19349663 + 7), k)

## Start the "rock falls away" reveal (explore phase, secret present).
func open_secret() -> void:
	if battle.secret == Vector2i(-1, -1) or secret_state == "open" or secret_state == "opening":
		return
	secret_state = "opening"
	secret_t = 0.0
	add_fx("dust", Iso.center(Vector2(battle.secret)) + Vector2(0, 3), Color(0.75, 0.7, 0.8), 0.7, {"seed": 11})
	add_fx("shock", Iso.center(Vector2(battle.secret)) + Vector2(0, 2), Color(0.8, 0.75, 0.9), 0.4)

func _init_particles() -> void:
	_flakes = []
	var pcfg: Dictionary = _theme.get("particles", {})
	var n := int(pcfg.get("count", 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in int(n * 1.8):
		_flakes.append({"x": rng.randf_range(-100.0, 740.0), "y": rng.randf_range(-60.0, 420.0), "z": rng.randf_range(0.5, 1.5), "ph": rng.randf() * 6.28})

func color_of(key: String, fallback: String = "#ffffff") -> Color:
	return Color.html(String(_theme.get(key, fallback)))

func _process(dt: float) -> void:
	time += dt
	_fade_dt = dt
	# the board fills the whole viewport (extra room on big/wide displays shows more environment); the design frame is centred in it
	var par := get_parent()
	view_off = (par as Control).global_position if par is Control else Vector2.ZERO
	var vs := get_viewport_rect().size
	if vs.x > 0.0 and (size != vs or global_position != Vector2(0.0, pan_y)):
		size = vs
		global_position = Vector2(0.0, pan_y)
		if battle != null:
			refit()
	if _ease_t < ZOOM_EASE:
		_ease_t += dt
		if battle != null:
			refit()
	if secret_state == "opening":
		secret_t += dt
		if secret_t >= SECRET_OPEN_TIME:
			secret_state = "open"
	if gate_state == "opening":
		gate_t += dt
		if gate_t >= GATE_OPEN_TIME:
			gate_state = "open"
	if battle != null:
		exit_vis = move_toward(exit_vis, exit_target(), dt / maxf(0.05, float(_exit_cfg().get("fade_time", 0.9))))
	shake = maxf(0.0, shake - dt * 3.0)
	if battle != null:
		for u in battle.units:
			u.vis_alert = maxf(0.0, u.vis_alert - dt)
			u.vis_flash = maxf(0.0, u.vis_flash - dt * 4.0)
			u.vis_pulse = maxf(0.0, u.vis_pulse - dt * 2.2)
	for f in fx:
		f["t"] += dt
	fx = fx.filter(func(f): return f["t"] < f["d"])
	_update_particles(dt)
	queue_redraw()

func _update_particles(dt: float) -> void:
	var pcfg: Dictionary = _theme.get("particles", {})
	var ty := String(pcfg.get("type", ""))
	var spd := float(pcfg.get("speed", 10.0)) * 0.5
	var wind := float(pcfg.get("wind", 0.0)) * 0.5
	var heavy := weather_id == "rain" or weather_id == "storm"
	for f in _flakes:
		match ty:
			"snow":
				f["y"] += spd * f["z"] * dt * (1.6 if weather_id == "storm" or weather_id == "cold" else 1.0)
				f["x"] += (wind * f["z"] + sin(time * 0.8 + f["ph"]) * 3.5) * dt
			"pollen":
				f["y"] += (sin(time * 0.6 + f["ph"]) * 1.5 - 0.8) * dt
				f["x"] += (spd * 0.5 + cos(time * 0.5 + f["ph"]) * 2.0) * f["z"] * dt
		var vr := Rect2(-view_off, size)
		if f["y"] > vr.end.y + 5.0:
			f["y"] = vr.position.y - 5.0
		if f["y"] < vr.position.y - 10.0:
			f["y"] = vr.end.y + 5.0
		if f["x"] > vr.end.x + 5.0:
			f["x"] = vr.position.x - 5.0
		if f["x"] < vr.position.x - 10.0:
			f["x"] = vr.end.x + 5.0
	if weather_id == "storm":
		_flash_cd -= dt
		if _flash_cd <= 0.0:
			_flash = 1.0
			_flash_cd = randf_range(3.0, 7.0)
		_flash = maxf(0.0, _flash - dt * 2.5)
	_rain_t = fmod(_rain_t + dt * (260.0 if heavy else 0.0), 1000.0)

var _rain_t: float = 0.0

# ------------------------------------------------------------------ effects (purely visual, never touch logic state)

var fx: Array = []

## kind: slash | burst | dust | ring | shock | proj | puff. `p` is a screen position; proj also takes `to`, `arc`.
func add_fx(kind: String, p: Vector2, col: Color = Color.WHITE, dur: float = 0.3, extra: Dictionary = {}) -> void:
	var f := {"k": kind, "p": p, "c": col, "d": dur, "t": 0.0}
	f.merge(extra)
	fx.append(f)

## Screen position of the middle of a unit's body (for impacts).
func body_pos(u: BUnit) -> Vector2:
	var r := unit_rect(u)
	return r.position + r.size * Vector2(0.5, 0.55)

func _draw_fx() -> void:
	for f in fx:
		var k := float(f["t"]) / float(f["d"])
		var a := 1.0 - k
		var c: Color = f["c"]
		var p: Vector2 = f["p"]
		match String(f["k"]):
			"slash":
				# three diagonal claw streaks that sweep across and fade
				for i in 3:
					var o := Vector2(-4 + i * 3, -4) + Vector2(k * 3.0, k * 2.0)
					var a0 := (p + o).round()
					draw_line(a0, (a0 + Vector2(5, 7) * minf(1.0, k * 3.0)).round(), Color(c.r, c.g, c.b, a), 1.0)
			"burst":
				var r := 2.0 + k * 6.0
				for i in 8:
					var ang := i * TAU / 8.0 + 0.3
					var q := p + Vector2(cos(ang), sin(ang) * 0.7) * r
					draw_rect(Rect2(q.round(), Vector2(2, 2) if k < 0.5 else Vector2(1, 1)), Color(c.r, c.g, c.b, a))
				draw_rect(Rect2((p - Vector2(2, 2) * a).round(), (Vector2(4, 4) * a).round()), Color(1, 1, 1, a * 0.8))
			"dust":
				for i in 6:
					var ang := float(i) * 1.1 + float(f.get("seed", 0))
					var q := p + Vector2(cos(ang) * (2.0 + k * 4.0), -k * 4.0 - absf(sin(ang)) * 1.5)
					draw_rect(Rect2(q.round(), Vector2(1, 1)), Color(c.r, c.g, c.b, a * 0.8))
			"ring", "shock":
				var maxr := 14.0 if String(f["k"]) == "shock" else 9.0
				var r := 3.0 + k * maxr
				var pts := PackedVector2Array()
				for i in 25:
					var ang := i * TAU / 24.0
					pts.append((p + Vector2(cos(ang) * r, sin(ang) * r * 0.5)).round())
				draw_polyline(pts, Color(c.r, c.g, c.b, a * 0.9), 1.0)
			"proj":
				var from: Vector2 = f["p"]
				var to: Vector2 = f["to"]
				var e := k   # linear travel along the iso line, parabolic arc on top
				var pos := from.lerp(to, e) - Vector2(0, sin(e * PI) * float(f.get("arc", 5.0)))
				for i in 4:
					var te := maxf(0.0, e - 0.05 * (i + 1))
					var tp := from.lerp(to, te) - Vector2(0, sin(te * PI) * float(f.get("arc", 5.0)))
					draw_rect(Rect2(tp.round(), Vector2(2, 2) if i < 2 else Vector2(1, 1)), Color(c.r, c.g, c.b, 0.55 - i * 0.12))
				draw_rect(Rect2(pos.round() - Vector2(1, 1), Vector2(3, 3)), c.darkened(0.35))
				draw_rect(Rect2(pos.round(), Vector2(1, 1)), c.lightened(0.45))
			"puff":
				for i in 7:
					var ang := i * TAU / 7.0
					var q := p + Vector2(cos(ang) * (1.5 + k * 6.0), sin(ang) * (1.0 + k * 3.0) - k * 4.0)
					var sz := roundf(2.0 * (1.0 - k * 0.5) + 0.4)
					draw_rect(Rect2(q.round(), Vector2(sz, sz)), Color(c.r, c.g, c.b, a * 0.7))

# ------------------------------------------------------------------ geometry / picking

## Screen position of the unit's feet (tile center + small offset). Single source of truth for rendering AND tests.
static func unit_foot(vis_pos: Vector2) -> Vector2:
	return Iso.center(vis_pos) + Vector2(0, 3.0 * Iso.zoom)

func unit_sprite_size(u: BUnit) -> Vector2:
	var t := _unit_tex(u)
	return (t.get_size() if t != null else Vector2(16, 16)) * Iso.zoom

func _unit_tex(u: BUnit) -> Texture2D:
	var back := u.vis_facing.x < 0 or u.vis_facing.y < 0
	# facing: (1,0)=SE front, (0,1)=SW front flipped, (-1,0)=NW back flipped, (0,-1)=NE back
	back = (u.vis_facing == Vector2i(-1, 0) or u.vis_facing == Vector2i(0, -1))
	var inf := u.vis_infected and not bool(u.def.get("infected", false)) and not u.is_player
	if SpriteFactory.has_facing_art(u.sprite_id, u.vis_facing):
		return SpriteFactory.creature_facing(u.sprite_id, u.vis_facing, inf)
	return SpriteFactory.creature(u.sprite_id, back, inf)

static func facing_flip(f: Vector2i) -> bool:
	return f == Vector2i(0, 1) or f == Vector2i(-1, 0)

func is_flyer(u: BUnit) -> bool:
	return u.tags.has("flying")

func unit_rect(u: BUnit) -> Rect2:
	var t := _unit_tex(u)
	var sz := t.get_size()
	var foot := unit_foot(u.vis_pos)
	var lift := float(_theme.get("flying_lift", 7)) if is_flyer(u) else 0.0
	return Rect2(foot.x - sz.x / 2.0, foot.y - sz.y - lift, sz.x, sz.y)

## Which tile does a screen click mean? Clicking an enemy's body (above its tile) selects its tile.
func pick(s: Vector2) -> Vector2i:
	if battle != null:
		var best: BUnit = null
		for u in battle.units:
			if u.is_player or not u.alive or u.vis_dead:
				continue
			var r := unit_rect(u)
			var core := Rect2(r.position.x + r.size.x * 0.22, r.position.y + r.size.y * 0.18, r.size.x * 0.56, r.size.y * 0.72)
			if core.has_point(s) and (best == null or Iso.depth(u.vis_pos) > Iso.depth(best.vis_pos)):
				best = u
		if best != null:
			return best.pos
	var tl := Iso.tile_at(s)
	if exit_vis > 0.3 and _corridor.has(tl):
		return battle.exits[int((_corridor[tl] as Dictionary)["exit"])]["pos"]     # clicking the open path = its edge trigger tile
	return tl

func _gui_input(e: InputEvent) -> void:
	if battle == null:
		return
	if e is InputEventMouseMotion or e is InputEventMouseButton:
		e = e.duplicate()
		e.position -= view_off
	if e is InputEventMouseMotion and _drag_from.x >= 0.0:
		pan_by(e.position - _drag_from)
		_drag_from = e.position
	elif e is InputEventMouseMotion:
		var p := pick(e.position)
		if p != hover:
			hover = p
			tile_hovered.emit(p)
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_UP:
		step_zoom(1)
		accept_event()
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		step_zoom(-1)
		accept_event()
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_MIDDLE:
		_drag_from = e.position if e.pressed else Vector2(-1, -1)
	elif e is InputEventMouseButton and e.pressed and e.button_index <= MOUSE_BUTTON_RIGHT:
		var p := pick(e.position)
		if battle.grid.in_bounds(p) and not battle.grid.is_void(p):
			tile_clicked.emit(p, e.button_index)

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		hover = Vector2i(-1, -1)
		tile_hovered.emit(hover)

# ------------------------------------------------------------------ drawing

## Draw a texture at the camera zoom (sprites are 4x pixel art: zoom 0.75 -> 3x, 0.5 -> 2x, so pixels stay uniform).
func _dt(tex: Texture2D, pos: Vector2, mod: Color = Color.WHITE) -> void:
	if Iso.zoom == 1.0:
		draw_texture(tex, pos, mod)
	else:
		draw_texture_rect(tex, Rect2(pos, tex.get_size() * Iso.zoom), false, mod)

## Top-left for a standing prop/sprite whose bottom edge sits on the bottom corner of tile centre `c`.
## Ground pool of the theme (variant indices, repeated = more likely); falls back to the generated 6-variant mix.
func _ground_pool() -> Array:
	var gp: Array = _theme.get("ground_pool", [])
	return gp if not gp.is_empty() else [0, 0, 0, 2, 2, 3, 3, 5, 5, 1, 4]

var _has_decor: bool:
	get:
		return not (_theme.get("decor_interior", []) as Array).is_empty()

## Keep the floor readable: no decoration on the secret tile or the start/enemy tiles (exit paths are outside the board).
func _decor_blocked(p: Vector2i) -> bool:
	if battle.secret == p:
		return true
	for u in battle.units:
		if BGrid.dist(p, u.pos) <= 0:
			return true
	return false

func _foot_tl(tex: Texture2D, c: Vector2) -> Vector2:
	return Vector2(c.x - tex.get_width() * Iso.zoom / 2.0, c.y + Iso.TH / 2.0 - tex.get_height() * Iso.zoom)

func _poly(p: Vector2i, col: Color, inset: float = 0.0) -> void:
	draw_colored_polygon(Iso.diamond(p, inset), col)

func _outline(p: Vector2i, col: Color, w: float = 1.0, inset: float = 0.0) -> void:
	var d := Iso.diamond(p, inset)
	d.append(d[0])
	draw_polyline(d, col, w)

func _draw() -> void:
	if battle == null:
		return
	var g := battle.grid
	var off := Vector2.ZERO
	if shake > 0.0:
		off = Vector2(roundf(randf_range(-1, 1) * shake * 2.0), roundf(randf_range(-1, 1) * shake * 2.0))
	draw_set_transform(off + view_off)
	var vr := Rect2(-view_off, size)          # visible area in design (frame) coordinates
	# 1. backdrop: base colour everywhere, then continuous terrain beyond the arena (no slab, no cliff sides)
	draw_rect(vr, SpriteFactory.theme_bg(theme_id))
	var bg := SpriteFactory.backdrop(theme_id, bg_variant)
	if bg != null:
		draw_texture(bg, Vector2.ZERO)
	_outer_parts.clear()
	_draw_outer_ground(vr)
	# 2. ground tiles (back to front)
	var frame := int(time * 2.0) % 3
	for y in g.h:
		for x in g.w:
			var p := Vector2i(x, y)
			if g.is_void(p):
				continue
			var t := g.get_tile(p)
			var tex: Texture2D
			if t == "water":
				tex = SpriteFactory.tile_texture("water", theme_id, int(_ground_var[y][x]) % 2, frame)
			elif t == "grass":
				tex = SpriteFactory.tile_texture("grass", theme_id, int(_prop_var[y][x]) % 3)
			else:
				tex = SpriteFactory.tile_texture("ground", theme_id, int(_ground_var[y][x]))
			_tile_dt(tex, Iso.center(Vector2(p)) - Vector2(Iso.TW / 2.0, Iso.TH / 2.0), Color.WHITE)
	# 3. grid lines (subtle overlay) + soft blend of the edge tiles into the surroundings
	var gl := color_of("grid_line", "#ffffff30")
	for y in g.h:
		for x in g.w:
			if not g.is_void(Vector2i(x, y)):
				_outline(Vector2i(x, y), gl, 1.0)
	_draw_edge_blend()
	# 3b. secret entrance (ground part) + exit gate pads
	_draw_secret_ground()
	_draw_exit_paths()
	# 4. highlights
	if not hide_overlays:
		for p in detect_tiles:
			_poly(p, Color(1.0, 0.88, 0.2, 0.20), 0.0)
			_outline(p, Color(1.0, 0.88, 0.2, 0.55), 1.0, 1.0)
		if show_move and _moving():
			var mc := color_of("move", "#5cc8ff")
			for p in move_tiles:
				_poly(p, Color(mc.r, mc.g, mc.b, 0.26), 0.0)
				_outline(p, Color(mc.r, mc.g, mc.b, 0.85), 1.0, 0.0)
		for p in target_tiles:
			var c: Color = target_tiles[p]
			var pulse := 0.22 + 0.14 * sin(time * 6.0)
			_poly(p, Color(c.r, c.g, c.b, pulse + 0.1), 0.0)
			_outline(p, c, 1.0, 0.0)
	if g.in_bounds(hover):
		_outline(hover, Color(1, 1, 1, 0.9), 1.0, 0.0)
		if show_move and move_tiles.has(hover) and _moving():
			var c := Iso.center(Vector2(hover))
			UITheme.draw_text(self, c + Vector2(-2, 3), str(move_tiles[hover]), UITheme.SZ_S, Color.WHITE)
	# 4b. where searching enemies last saw you
	for u in battle.enemies:
		if u.alive and u.vis_state == "searching" and u.last_seen != Vector2i(-1, -1) and battle.grid.in_bounds(u.last_seen):
			var pulse := 0.5 + 0.5 * sin(time * 4.0 + float(u.uid))
			_outline(u.last_seen, Color(1.0, 0.85, 0.2, 0.35 + 0.35 * pulse), 1.0, 2.0)
			var lc := Iso.center(Vector2(u.last_seen))
			UITheme.draw_text(self, lc + Vector2(-2, 3), "?", UITheme.SZ_S, Color(1.0, 0.9, 0.3, 0.55 + 0.4 * pulse))
	# 4c. telegraphed attacks: red danger tiles
	for u in battle.enemies:
		if u.alive and not u.vis_windup.is_empty():
			var dp := 0.30 + 0.18 * sin(time * 7.0)
			for p in u.vis_windup:
				if battle.grid.in_bounds(p):
					_poly(p, Color(1.0, 0.18, 0.1, dp), 0.0)
					_outline(p, Color(1.0, 0.3, 0.15, 0.95), 1.0, 0.0)
	# 5. facing arrows on the ground
	for u in battle.units:
		if u.alive and not u.vis_dead:
			_draw_facing_arrow(u)
	# 6. depth-sorted props + units
	_parts.clear()
	for y in g.h:
		for x in g.w:
			var p := Vector2i(x, y)
			var t := g.get_tile(p)
			if t == "obstacle":
				_parts.append([Iso.depth(Vector2(p) + Vector2(0.5, 0.5)), 0, p])
			elif t == "grass":
				_parts.append([Iso.depth(Vector2(p) + Vector2(0.5, 0.5)), 1, p])
			elif t == "ground" and _has_decor and _hash(x, y, 9) % 100 < 6 and not _decor_blocked(p):
				_parts.append([Iso.depth(Vector2(p) + Vector2(0.5, 0.5)) - 0.03, 7, p])
	_parts.append_array(_outer_parts)
	for u in battle.units:
		if not u.vis_dead and (u.alive or u.vis_alpha > 0.01):
			_parts.append([Iso.depth(u.vis_pos + Vector2(0.5, 0.5)) + 0.02, 2, u])
			var tp := Vector2i(roundi(u.vis_pos.x), roundi(u.vis_pos.y))
			if g.in_bounds(tp) and g.is_grass(tp) and absf(u.vis_pos.x - tp.x) < 0.25 and absf(u.vis_pos.y - tp.y) < 0.25 and not is_flyer(u):
				_parts.append([Iso.depth(Vector2(tp) + Vector2(0.5, 0.5)) + 0.04, 3, tp])
	if battle.phase == "explore":
		if battle.secret != Vector2i(-1, -1) and secret_state != "open" and secret_state != "crack":
			_parts.append([Iso.depth(Vector2(battle.secret) + Vector2(0.5, 0.5)) + 0.01, 5, battle.secret])
	_parts.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var unit_keys := _unit_keys()
	for part in _parts:
		match int(part[1]):
			0:
				var p: Vector2i = part[2]
				var tex := SpriteFactory.prop_texture("obstacle", theme_id, int(_prop_var[p.y][p.x]), false, false)
				if tex != null:
					var tl := _foot_tl(tex, Iso.center(Vector2(p))).round()
					var fa := _foliage_alpha(part, 0, Rect2(tl, tex.get_size() * Iso.zoom), unit_keys)
					_dt(tex, tl, Color(1, 1, 1, fa))
			1:
				var p: Vector2i = part[2]
				var tex := SpriteFactory.prop_texture("tallgrass", theme_id, int(_prop_var[p.y][p.x]))
				if tex != null:
					_dt(tex, _foot_tl(tex, Iso.center(Vector2(p))).round())
			6:
				var op: Vector2i = part[2]
				var otex: Texture2D
				if int(part[3]) == 2:
					otex = SpriteFactory.deco_texture(theme_id, int(part[4]), "decor_ring")
				else:
					otex = SpriteFactory.prop_texture("obstacle" if int(part[3]) == 0 else "tallgrass", theme_id, int(part[4]), false, true)
				if otex != null:
					var k: float = part[5]
					var otl := _foot_tl(otex, Iso.center(Vector2(op))).round()
					var ofa := _foliage_alpha(part, 6, Rect2(otl, otex.get_size() * Iso.zoom), unit_keys)
					if int(part[6]) >= 0:
						ofa *= 1.0 - exit_vis          # the trees of an exit corridor thin out when the path opens
					if ofa > 0.01:
						_dt(otex, otl, Color(k, k, k * (1.04 if theme_id == "tundra" else 1.0), ofa))
			5:
				_draw_secret_rock(part[2])
			2:
				_draw_unit(part[2])
			7:
				var dp: Vector2i = part[2]
				var dtex := SpriteFactory.deco_texture(theme_id, _hash(dp.x, dp.y, 10) % 64, "decor_interior")
				if dtex != null:
					var dtl := _foot_tl(dtex, Iso.center(Vector2(dp))).round()
					var dfa := _foliage_alpha(part, 7, Rect2(dtl, dtex.get_size() * Iso.zoom), unit_keys)
					_dt(dtex, dtl, Color(1, 1, 1, dfa))
			3:
				var p: Vector2i = part[2]
				var tex := SpriteFactory.prop_texture("tallgrass", theme_id, int(_prop_var[p.y][p.x]), true)
				if tex != null:
					_dt(tex, _foot_tl(tex, Iso.center(Vector2(p))).round(), Color(1, 1, 1, 0.95))
	# 7. soft vignette + lighting (replaces the old baked foreground overlay: foliage now overlaps the arena border as props)
	_draw_vignette(vr)
	# 7b. secret glow (light, over everything on the ground) + exit reward badges
	_draw_secret_glow()
	_draw_exit_badges()
	# 8. ambient
	_draw_ambient()
	_draw_fx()
	# 9. overlays (hp bars, awareness, status, damage preview)
	for u in battle.units:
		if not u.vis_dead and (u.alive or u.vis_alpha > 0.01):
			_draw_unit_overlay(u)
	draw_set_transform(Vector2.ZERO)

# ------------------------------------------------------------------ exits + secret entrance

func _moving() -> bool:
	return battle.phase == "player" or battle.phase == "explore" or battle.phase == "ambush"

func _tile_origin(p: Vector2i) -> Vector2:
	return Iso.center(Vector2(p)) - Vector2(Iso.TW / 2.0, Iso.TH / 2.0)

## Ground tile texture scaled to the current tile size (slightly oversize so neighbouring diamonds never leave seams).
func _tile_dt(tex: Texture2D, pos: Vector2, mod: Color) -> void:
	if Iso.zoom == 1.0:
		draw_texture(tex, pos.round(), mod)
	else:
		draw_texture_rect(tex, Rect2(pos.round(), Vector2(ceilf(Iso.TW), ceilf(Iso.TH))), false, mod)

const RING_LIGHT := [1.0, 0.9, 0.78, 0.68, 0.6, 0.54, 0.5, 0.47, 0.45, 0.43, 0.41]
const RING_PROP := [0.0, 0.5, 0.5, 0.55, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6]

## Terrain continues beyond the arena in every direction: the same ground tiles, darkening and thickening with foliage/rocks
## the farther they are from the playable area, so the grid looks like a clearing inside one continuous environment.
func _draw_outer_ground(vr: Rect2) -> void:
	var g := battle.grid
	var corners := [vr.position, vr.position + Vector2(vr.size.x, 0), vr.position + Vector2(0, vr.size.y), vr.end]
	var minx := 1e9
	var maxx := -1e9
	var miny := 1e9
	var maxy := -1e9
	for c in corners:
		var gp := Iso.to_grid(c)
		minx = minf(minx, gp.x)
		maxx = maxf(maxx, gp.x)
		miny = minf(miny, gp.y)
		maxy = maxf(maxy, gp.y)
	var x0 := floori(minx) - 2
	var x1 := ceili(maxx) + 2
	var y0 := floori(miny) - 2
	var y1 := ceili(maxy) + 2
	var th := _theme
	var nobs := int(th.get("obstacle_variants", 1))
	var pad := Vector2(Iso.TW, Iso.TH * 4.0)
	var area := vr.grow_individual(pad.x, pad.y, pad.x, pad.y)
	var tint := Color(1, 1, 1)
	if theme_id == "tundra":
		tint = Color(0.92, 0.97, 1.08)
	elif theme_id == "cave":
		tint = Color(0.95, 0.88, 1.1)
	var pool := _ground_pool()
	var decor_n: int = (_theme.get("decor_ring", []) as Array).size()
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var p := Vector2i(x, y)
			var r := ring_of(p)
			if r == 0:
				continue
			var c := Iso.center(Vector2(p))
			if not area.has_point(c):
				continue
			var h := _hash(x, y, 1)
			var k: float = RING_LIGHT[mini(r, RING_LIGHT.size() - 1)]
			var tex: Texture2D
			if r >= 2 and h % 12 == 0:
				tex = SpriteFactory.tile_texture("grass", theme_id, (h / 7) % 3)
			else:
				tex = SpriteFactory.tile_texture("ground", theme_id, int(pool[(h / 5) % pool.size()]))
			_tile_dt(tex, c - Vector2(Iso.TW / 2.0, Iso.TH / 2.0), Color(k * tint.r, k * tint.g, k * tint.b, 1.0))
			# foliage / rocks that overlap the arena border and thicken outward
			var pr: float = RING_PROP[mini(r, RING_PROP.size() - 1)]
			var cor: int = int((_corridor[p] as Dictionary)["exit"]) if _corridor.has(p) else -1     # exit corridor: props fade out when it opens
			if pr <= 0.0 or float(_hash(x, y, 2) % 1000) / 1000.0 >= pr:
				# empty ring tile: small ground decoration (mushrooms, pebbles, flowers, leaf piles)
				if decor_n > 0 and r >= 1 and _hash(x, y, 6) % 100 < 14:
					_outer_parts.append([Iso.depth(Vector2(p) + Vector2(0.5, 0.5)) - 0.02, 6, p, 2, _hash(x, y, 7) % 64, minf(1.0, k + 0.06), cor])
				continue
			var kind := 1 if (r == 1 or _hash(x, y, 4) % 5 == 0) else 0
			var variant := (_hash(x, y, 3) % 64) % (3 if kind == 1 else maxi(1, nobs))
			_outer_parts.append([Iso.depth(Vector2(p) + Vector2(0.5, 0.5)), 6, p, kind, variant, minf(1.0, k + 0.06), cor])

## Soft fringe on arena tiles that touch the surroundings: a dark leafy gradient fades from the edge inward.
func _draw_edge_blend() -> void:
	var g := battle.grid
	var col := Color(0.02, 0.08, 0.04) if theme_id == "jungle" else (Color(0.1, 0.16, 0.28) if theme_id == "tundra" else Color(0.05, 0.02, 0.12))
	var strength := 0.34
	for y in g.h:
		for x in g.w:
			var p := Vector2i(x, y)
			if g.is_void(p):
				continue
			var d := Iso.diamond(p)
			var c := Iso.center(Vector2(p))
			# edges: +x -> right/bottom, +y -> bottom/left, -x -> left/top, -y -> top/right
			var edges := [[Vector2i(1, 0), 1, 2], [Vector2i(0, 1), 2, 3], [Vector2i(-1, 0), 3, 0], [Vector2i(0, -1), 0, 1]]
			for e in edges:
				var n: Vector2i = p + e[0]
				if g.in_bounds(n) and not g.is_void(n):
					continue
				var a: Vector2 = d[int(e[1])]
				var b: Vector2 = d[int(e[2])]
				var ia := a.lerp(c, 0.55)
				var ib := b.lerp(c, 0.55)
				draw_polygon(PackedVector2Array([a, b, ib, ia]), PackedColorArray([Color(col.r, col.g, col.b, strength), Color(col.r, col.g, col.b, strength), Color(col.r, col.g, col.b, 0.0), Color(col.r, col.g, col.b, 0.0)]))

## Stepped vignette over the whole visible area (cheap, keeps the pixel look); stronger in caves.
func _draw_vignette(vr: Rect2) -> void:
	var tint := Color(0.01, 0.04, 0.02) if theme_id == "jungle" else (Color(0.02, 0.04, 0.1) if theme_id == "tundra" else Color(0.02, 0.0, 0.07))
	var k := 0.055 if theme_id != "cave" else 0.085
	var band := maxf(3.0, roundf(minf(vr.size.x, vr.size.y) * 0.014))
	for i in 10:
		var a := k * float(10 - i) / 10.0 * 1.6
		var o := band * i
		var col := Color(tint.r, tint.g, tint.b, a)
		draw_rect(Rect2(vr.position.x + o, vr.position.y + o, vr.size.x - 2 * o, band), col)
		draw_rect(Rect2(vr.position.x + o, vr.end.y - o - band, vr.size.x - 2 * o, band), col)
		draw_rect(Rect2(vr.position.x + o, vr.position.y + o + band, band, vr.size.y - 2 * o - 2 * band), col)
		draw_rect(Rect2(vr.end.x - o - band, vr.position.y + o + band, band, vr.size.y - 2 * o - 2 * band), col)

func _draw_secret_ground() -> void:
	var sp := battle.secret
	if sp == Vector2i(-1, -1):
		return
	match secret_state:
		"crack":
			var t := SpriteFactory.png("secret_crack")
			if t != null:
				_tile_dt(t, _tile_origin(sp), Color.WHITE)
		_:
			var h := SpriteFactory.png("secret_hole")
			if h != null:
				_tile_dt(h, _tile_origin(sp), Color.WHITE)

func _draw_secret_rock(sp: Vector2i) -> void:
	var t := SpriteFactory.png("secret_rock")
	if t == null:
		return
	var c := Iso.center(Vector2(sp))
	var off := Vector2.ZERO
	var a := 1.0
	if secret_state == "opening":
		var k := clampf(secret_t / SECRET_OPEN_TIME, 0.0, 1.0)
		var e := k * k * (3.0 - 2.0 * k)
		# the boulder rolls off the opening (toward the camera-right), dropping as it goes, and settles into the dark
		off = Vector2(14.0 * e, -4.0 * sin(k * PI) + 9.0 * e * e)
		a = 1.0 - clampf((k - 0.6) / 0.4, 0.0, 1.0)
	_dt(t, (_foot_tl(t, c) + off * Iso.zoom).round(), Color(1, 1, 1, a))

func _draw_secret_glow() -> void:
	if battle.secret == Vector2i(-1, -1) or battle.phase != "explore":
		return
	var k := 0.0
	if secret_state == "open":
		k = 1.0
	elif secret_state == "opening":
		k = clampf((secret_t - SECRET_OPEN_TIME * 0.55) / (SECRET_OPEN_TIME * 0.45), 0.0, 1.0)
	if k <= 0.0:
		return
	var c := Iso.center(Vector2(battle.secret)) + Vector2(0, 1)
	var pulse := 0.85 + 0.15 * sin(time * 2.2)
	var warm := Color(1.0, 0.92, 0.62)
	for i in 5:
		var f := 1.0 - i * 0.18
		var pts := PackedVector2Array()
		for j in 24:
			var an := j / 24.0 * TAU
			pts.append(c + Vector2(cos(an) * 17.0 * f, sin(an) * 8.5 * f))
		draw_colored_polygon(pts, Color(warm.r, warm.g, warm.b, 0.07 * k * pulse))
	# soft light column rising out of the opening
	var col := PackedVector2Array([c + Vector2(-5, -1), c + Vector2(5, -1), c + Vector2(3, -14), c + Vector2(-3, -14)])
	draw_colored_polygon(col, Color(warm.r, warm.g, warm.b, 0.10 * k * pulse))
	# a few motes drifting up (pixel-snapped)
	for i in 6:
		var ph := fposmod(time * 0.45 + i * 0.37, 1.0)
		var mx := c.x + sin(i * 2.1 + time * 0.9) * 4.0
		var my := c.y - 2.0 - ph * 13.0
		draw_rect(Rect2(floorf(mx), floorf(my), 1, 1), Color(1.0, 0.97, 0.78, (1.0 - ph) * 0.9 * k))

func _exit_color(i: int) -> Color:
	var hint := RoomInfo.reward_hint(String(battle.exits[i]["type"]))
	return Color.html(String(hint["color"]))

## Gate state: "locked" (fight in progress / waiting for the reveal), "opening" (short reveal animation), "open".
var gate_state: String = "open"
var gate_t: float = 0.0
const GATE_OPEN_TIME := 0.9

func gates_locked() -> bool:
	return gate_state == "locked"

func _exit_cfg() -> Dictionary:
	return _vis.get("exit_path", {})

## Tiles OUTSIDE the grid on the exit corridors (data/visibility.json exit_path: width x length), see ExitGen.corridor().
func _build_corridors() -> void:
	_corridor = {}
	if battle == null:
		return
	var cfg := _exit_cfg()
	for i in battle.exits.size():
		var ex: Dictionary = battle.exits[i]
		for c in ExitGen.corridor(ex["pos"], String(ex["side"]), int(cfg.get("width", 3)), int(cfg.get("length", 6))):
			if not _corridor.has(c["tile"]):
				_corridor[c["tile"]] = {"exit": i, "k": int(c["k"]), "o": int(c["o"])}

func is_corridor_tile(p: Vector2i) -> bool:
	return _corridor.has(p)

## Where exit_vis is heading: open in the explore phase (once the reveal started) and while unspotted; hidden in a fight.
func exit_target() -> float:
	if battle == null or battle.exits.is_empty():
		return 0.0
	if battle.phase == "ambush":
		return 1.0
	if battle.phase == "explore" and gate_state != "locked":
		return 1.0
	return 0.0

## Start the reveal of the exit paths (explore start after a clear / sneak): the corridor trees fade out, the ground lights up.
func open_gates() -> void:
	if battle.exits.is_empty() or gate_state == "open" or gate_state == "opening":
		return
	gate_state = "opening"
	gate_t = 0.0
	var gk := int(_exit_cfg().get("glow_at", 3))
	for ex in battle.exits:
		var c := Iso.center(Vector2(Vector2i(ex["pos"]) + Vector2i(ex["dir"]) * gk))
		add_fx("shock", c + Vector2(0, 2), _exit_color(battle.exits.find(ex)), 0.6)

## 0 (hidden) .. 1 (open)
func gate_open_amount() -> float:
	return exit_vis

## The path itself is negative space: no sprite. Once open, the corridor shows plain floor (a few dirt / floor variants) and a light
## strip + glow on the ground at the end of the path (reward colour in the explore phase, neutral while you are unspotted).
func _draw_exit_paths() -> void:
	if exit_vis <= 0.01 or battle.exits.is_empty():
		return
	var cfg := _exit_cfg()
	var dirt: Array = (cfg.get("dirt_variants", {}) as Dictionary).get(theme_id, [])
	var pool := _ground_pool()
	var gk := int(cfg.get("glow_at", 3))
	var pulse := 0.5 + 0.5 * sin(time * 2.4)
	for tile in _corridor:
		var info: Dictionary = _corridor[tile]
		var h := _hash(tile.x, tile.y, 21)
		var tex: Texture2D
		if not dirt.is_empty() and (int(info["o"]) == 0 or float(h % 100) / 100.0 < float(cfg.get("dirt_chance", 0.45))):
			tex = SpriteFactory.tile_texture("ground", theme_id, int(dirt[h % dirt.size()]))
		else:
			tex = SpriteFactory.tile_texture("ground", theme_id, int(pool[(h / 5) % pool.size()]))
		var k: float = minf(1.0, RING_LIGHT[mini(ring_of(tile), RING_LIGHT.size() - 1)] + 0.4)
		var tint := Color(1, 1, 1)
		if theme_id == "tundra":
			tint = Color(0.92, 0.97, 1.08)
		elif theme_id == "cave":
			tint = Color(0.95, 0.88, 1.1)
		_tile_dt(tex, Iso.center(Vector2(tile)) - Vector2(Iso.TW / 2.0, Iso.TH / 2.0), Color(k * tint.r, k * tint.g, k * tint.b, exit_vis))
	var reward := battle.phase == "explore"
	for i in battle.exits.size():
		var ex: Dictionary = battle.exits[i]
		var col := _exit_color(i) if reward else Color(1.0, 0.95, 0.8)
		var d: Vector2i = ex["dir"]
		# faint light strip along the centre line, brightest at the end of the path
		for k in range(1, int(cfg.get("length", 6)) + 1):
			var t: Vector2i = Vector2i(ex["pos"]) + d * k
			var near := 1.0 - absf(float(k - gk)) / float(maxi(2, gk + 2))
			_poly(t, Color(col.r, col.g, col.b, exit_vis * (0.10 + 0.16 * maxf(0.0, near) * (0.7 + 0.3 * pulse))), 1.0)
		var c := Iso.center(Vector2(Vector2i(ex["pos"]) + d * gk)) + Vector2(0, 1)
		for j in 5:
			var f := 1.0 - j * 0.18
			var pts := PackedVector2Array()
			for q in 24:
				var an := q / 24.0 * TAU
				pts.append(c + Vector2(cos(an) * Iso.TW * 0.7 * f, sin(an) * Iso.TH * 0.7 * f))
			draw_colored_polygon(pts, Color(col.r, col.g, col.b, exit_vis * (0.09 + 0.04 * pulse)))

## Reward hint over the end of each path (Hades-style), ONLY once the area is cleared: what you get, never what waits behind it.
func _draw_exit_badges() -> void:
	if battle.exits.is_empty() or battle.phase != "explore" or exit_vis <= 0.05:
		return
	var gk := int(_exit_cfg().get("glow_at", 3))
	for i in battle.exits.size():
		var ex: Dictionary = battle.exits[i]
		var hint := RoomInfo.reward_hint(String(ex["type"]))
		var col := _exit_color(i)
		var c := Iso.center(Vector2(Vector2i(ex["pos"]) + Vector2i(ex["dir"]) * gk))
		var bob := roundf(sin(time * 2.0 + i * 1.3) * 1.0)
		var label := String(hint["label"])
		var w := UITheme.text_size(label, UITheme.SZ_M).x + 20.0
		var x := roundf(clampf(c.x - w / 2.0, 3.0 - view_off.x, size.x - view_off.x - 3.0 - w))
		var y := roundf(clampf(c.y - 26.0 + bob, 3.0 - view_off.y + 26.0, size.y - view_off.y - 40.0))
		draw_rect(Rect2(x, y, w, 17), Color(0.04, 0.05, 0.1, 0.94 * exit_vis))
		draw_rect(Rect2(x + 0.5, y + 0.5, w - 1.0, 16.0), Color(col.r, col.g, col.b, exit_vis), false, 1.0)
		draw_texture(SpriteFactory.get_texture(String(hint["icon"])), Vector2(x + 3, y + 3), Color(1, 1, 1, exit_vis))
		UITheme.draw_text_in(self, Rect2(x + 16, y, w - 16, 17), label, UITheme.SZ_M, Color(1, 1, 1, exit_vis), HORIZONTAL_ALIGNMENT_LEFT, false)
		draw_colored_polygon(PackedVector2Array([Vector2(c.x - 3, y + 17), Vector2(c.x + 3, y + 17), Vector2(c.x, y + 20)]), Color(col.r, col.g, col.b, exit_vis))

func _draw_facing_arrow(u: BUnit) -> void:
	var f := u.vis_facing
	var sv := Vector2((f.x - f.y) * Iso.TW * 0.5, (f.x + f.y) * Iso.TH * 0.5)   # screen vector of one tile step
	var dirv := sv.normalized()
	var c := Iso.center(u.vis_pos) + Vector2(0, 1)
	var col := Color("#5cd8ff") if u.is_player else (Color("#ff9a4a") if u.vis_aware else Color("#ffd24a"))
	var perp := Vector2(-dirv.y, dirv.x)
	var base := c + sv * 0.30
	var tip := c + sv * 0.50
	# chevron: filled triangle pointing along the facing, flattened for the iso view
	var pts := PackedVector2Array([tip, base + perp * Vector2(1.0, 0.5) * 4.0, base - perp * Vector2(1.0, 0.5) * 4.0])
	draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.9))
	var o := PackedVector2Array([pts[0], pts[1], pts[2], pts[0]])
	draw_polyline(o, Color(0.05, 0.08, 0.12, 0.9), 1.0)

func _draw_unit(u: BUnit) -> void:
	var tex := _unit_tex(u)
	if tex == null:
		return
	var sz := tex.get_size() * Iso.zoom
	var foot := unit_foot(u.vis_pos) + u.vis_off * Iso.zoom
	var flyer := is_flyer(u)
	var z := Iso.zoom
	var lift := (float(_theme.get("flying_lift", 7)) if flyer else 0.0) * z
	var bob := 0.0
	if u.alive:
		# idle breathing: a 1px rise-and-settle (flyers hover more)
		var br := sin(time * (5.0 if flyer else 2.2) + float(u.uid) * 1.7)
		bob = roundf(br * 1.0) if flyer else (-1.0 if br > 0.3 else 0.0)
	# shadow (shrinks while the unit is in the air)
	var air := clampf(u.vis_lift / 10.0, 0.0, 0.6)
	var sw := sz.x * 0.5 * (1.0 - air)
	var gfoot := unit_foot(u.vis_pos) + Vector2(u.vis_off.x * Iso.zoom, 0.0)
	var shadow := PackedVector2Array()
	for i in 14:
		var a := i / 14.0 * TAU
		shadow.append(gfoot + Vector2(cos(a) * sw * 0.5, sin(a) * 2.0 - 0.5))
	draw_colored_polygon(shadow, Color(0, 0, 0, 0.38 * u.vis_alpha * (1.0 - air)))
	_draw_unit_marks_under(u, gfoot)
	var a := u.vis_alpha
	var tile_p := Vector2i(roundi(u.vis_pos.x), roundi(u.vis_pos.y))
	var in_grass := battle.grid.in_bounds(tile_p) and battle.grid.is_grass(tile_p)
	if u.is_player and battle.is_hidden() and in_grass:
		a *= 0.62
	var mod := Color(1, 1, 1, a)
	if u.vis_flash > 0.0:
		mod = Color(1.0, 1.0 - u.vis_flash * 0.75, 1.0 - u.vis_flash * 0.75, a)
	# status pulses: infection (purple, slow), bleed (red), one-shot pulses from events
	var pulse := 0.0
	var pcol := u.vis_pulse_col
	if u.vis_pulse > 0.0:
		pulse = u.vis_pulse * 0.55
	elif u.alive and u.infected and not u.is_player and not bool(u.def.get("infected", false)):
		pulse = pow(maxf(0.0, sin(time * 2.4 + float(u.uid))), 6.0) * 0.35
		pcol = Color("#b060ff")
	elif u.alive and u.st("poison") > 0:
		pulse = pow(maxf(0.0, sin(time * 2.6 + float(u.uid))), 8.0) * 0.3
		pcol = Color("#7aff40")
	elif u.alive and u.st("bleed") > 0:
		pulse = pow(maxf(0.0, sin(time * 3.2 + float(u.uid))), 10.0) * 0.30
		pcol = Color("#ff3040")
	if pulse > 0.0:
		mod = Color(mod.r + (pcol.r - mod.r) * pulse, mod.g + (pcol.g - mod.g) * pulse, mod.b + (pcol.b - mod.b) * pulse, mod.a)
	var t2: Texture2D = _flipped(tex) if facing_flip(u.vis_facing) and not SpriteFactory.has_facing_art(u.sprite_id, u.vis_facing) else tex
	if u.vis_squash > 0.0:
		# death collapse: the body sinks and spreads
		var w := sz.x * (1.0 + 0.25 * u.vis_squash)
		var h := sz.y * (1.0 - 0.6 * u.vis_squash)
		draw_texture_rect(t2, Rect2((Vector2(foot.x - w / 2.0, foot.y - h - lift)).round(), Vector2(w, h)), false, mod)
		return
	var pos := Vector2(foot.x - sz.x / 2.0, foot.y - sz.y - lift - u.vis_lift * z + bob * z)
	pos = pos.round()
	_draw_unit_outline(u, t2, pos, sz)
	_dt(t2, pos, mod)


# ------------------------------------------------------------------ unit readability (data/visibility.json)

## [depth key, screen rect] of every visible unit (the key matches the unit's entry in the depth-sorted parts).
func _unit_keys() -> Array:
	var out: Array = []
	for u: BUnit in battle.units:
		if u.vis_dead or (not u.alive and u.vis_alpha <= 0.2):
			continue
		var t := _unit_tex(u)
		if t == null:
			continue
		var sz := t.get_size() * Iso.zoom
		var foot := unit_foot(u.vis_pos) + u.vis_off * Iso.zoom
		var lift := (float(_theme.get("flying_lift", 7)) if is_flyer(u) else 0.0) * Iso.zoom
		out.append([Iso.depth(u.vis_pos + Vector2(0.5, 0.5)) + 0.02, Rect2(foot.x - sz.x / 2.0, foot.y - sz.y - lift, sz.x, sz.y)])
	return out

## The part of a sprite rect that counts for overlap tests (trees have empty corners / thin crowns).
func _shrunk(r: Rect2) -> Rect2:
	var ov: Dictionary = _vis.get("overlap", {})
	var sx := float(ov.get("shrink_x", 0.2))
	var st := float(ov.get("shrink_top", 0.12))
	var sb := float(ov.get("shrink_bottom", 0.0))
	return Rect2(r.position.x + r.size.x * sx, r.position.y + r.size.y * st, r.size.x * (1.0 - 2.0 * sx), r.size.y * (1.0 - st - sb))

## Does a (shrunk) sprite rect cover the core of any playable (non-void) tile?
func overlaps_board(rect: Rect2) -> bool:
	var g := battle.grid
	var r := _shrunk(rect)
	var gx0 := 1e9
	var gx1 := -1e9
	var gy0 := 1e9
	var gy1 := -1e9
	for c in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]:
		var gp := Iso.to_grid(c)
		gx0 = minf(gx0, gp.x)
		gx1 = maxf(gx1, gp.x)
		gy0 = minf(gy0, gp.y)
		gy1 = maxf(gy1, gp.y)
	var core := float((_vis.get("overlap", {}) as Dictionary).get("core", 0.5))
	var cs := Vector2(Iso.TW, Iso.TH) * core
	for y in range(maxi(0, floori(gy0) - 1), mini(g.h - 1, ceili(gy1) + 1) + 1):
		for x in range(maxi(0, floori(gx0) - 1), mini(g.w - 1, ceili(gx1) + 1) + 1):
			var p := Vector2i(x, y)
			if g.is_void(p):
				continue
			var c := Iso.center(Vector2(p))
			if r.intersects(Rect2(c - cs * 0.5, cs)):
				return true
	return false

## Alpha of a foliage / obstacle / decoration part this frame (tweened): kind 6 = border foliage (reduced over the board, lower with a unit
## behind it), kind 0 = blocking obstacle (opaque; fades only while a unit is directly behind), kind 7 = decoration on the board.
func _foliage_alpha(part: Array, kind: int, rect: Rect2, unit_keys: Array) -> float:
	var p: Vector2i = part[2]
	var key := "%d:%d:%d" % [kind, p.x, p.y]
	var tgt := foliage_target(part, kind, rect, unit_keys, key)
	var cur: float = _fade.get(key, tgt)
	if absf(cur - tgt) < 0.01 or _fade_dt <= 0.0 and not _fade.has(key):
		cur = tgt
	else:
		cur += (tgt - cur) * (1.0 - exp(-float(_vis.get("fade_speed", 9.0)) * _fade_dt))
	_fade[key] = cur
	return cur

func foliage_target(part: Array, kind: int, rect: Rect2, unit_keys: Array, key: String = "") -> float:
	var behind := false
	var sr := _shrunk(rect)
	var skey: float = part[0]
	for uk in unit_keys:
		if float(uk[0]) < skey and sr.intersects(uk[1]):
			behind = true
			break
	match kind:
		6:
			if Iso.zoom != _overlap_zoom:
				_overlap_cache.clear()
				_overlap_zoom = Iso.zoom
			var ov: bool
			if key != "" and _overlap_cache.has(key):
				ov = _overlap_cache[key]
			else:
				ov = overlaps_board(rect)
				if key != "":
					_overlap_cache[key] = ov
			var a := float(_vis.get("border_alpha", 0.42)) if ov else 1.0
			if behind:
				a = minf(a, float(_vis.get("border_behind_alpha", 0.28)))
			return a
		0:
			return float(_vis.get("obstacle_behind_alpha", 0.5)) if behind else 1.0
		7:
			return float(_vis.get("decor_behind_alpha", 0.45)) if behind else 1.0
	return 1.0

## White copy of a texture's silhouette (cached): modulated by a colour it becomes a solid outline / glow.
func _silhouette(tex: Texture2D) -> Texture2D:
	var id := tex.get_instance_id()
	if _sil_cache.has(id):
		return _sil_cache[id]
	var img: Image = tex.get_image()
	if img == null:
		return tex
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(1, 1, 1, 1.0 if c.a > 0.4 else 0.0))
	var t := ImageTexture.create_from_image(img)
	_sil_cache[id] = t
	return t

## Foot ring (team colour) and a thin light outline so units stay readable over any foliage / ground.
func _draw_unit_marks_under(u: BUnit, gfoot: Vector2) -> void:
	var ur: Dictionary = _vis.get("unit_ring", {})
	if not bool(ur.get("enabled", false)) or not u.alive:
		return
	var col := Color(String(ur["player"] if u.is_player else ur["enemy"]))
	col.a = float(ur.get("alpha", 0.6)) * u.vis_alpha
	var rad := float(ur.get("radius", 0.3))
	var pts := PackedVector2Array()
	for i in 25:
		var a := float(i) / 24.0 * TAU
		pts.append(gfoot + Vector2(cos(a) * Iso.TW * rad, sin(a) * Iso.TH * rad))
	draw_polyline(pts, col, 1.0)

func _draw_unit_outline(u: BUnit, tex: Texture2D, pos: Vector2, sz: Vector2) -> void:
	var uo: Dictionary = _vis.get("unit_outline", {})
	if not bool(uo.get("enabled", false)) or not u.alive:
		return
	var col := Color(String(uo["player"] if u.is_player else uo["enemy"]))
	col.a = float(uo.get("player_alpha" if u.is_player else "enemy_alpha", 0.55)) * u.vis_alpha
	var sil := _silhouette(tex)
	var o := float(uo.get("px", 1.0))
	for d in [Vector2(o, 0), Vector2(-o, 0), Vector2(0, o), Vector2(0, -o)]:
		draw_texture_rect(sil, Rect2(pos + d, sz), false, col)

var _flip_cache: Dictionary = {}

## Horizontally mirrored copy of a texture (cached). Avoids negative-size draw_texture_rect, whose
## placement differs between engine versions and caused a sprite offset on flipped units.
func _flipped(tex: Texture2D) -> Texture2D:
	var k := tex.get_instance_id()
	if not _flip_cache.has(k):
		var img := tex.get_image()
		img.flip_x()
		_flip_cache[k] = ImageTexture.create_from_image(img)
	return _flip_cache[k]

func _draw_unit_overlay(u: BUnit) -> void:
	var sz := unit_sprite_size(u)
	var foot := unit_foot(u.vis_pos)
	var flyer := is_flyer(u)
	var lift := (float(_theme.get("flying_lift", 7)) if flyer else 0.0) * Iso.zoom
	var top := foot.y - sz.y - lift
	var cx := foot.x
	var a := u.vis_alpha
	# current actor marker
	if u.uid == current_uid and u.alive:
		var cy := top - 8 + roundf(sin(time * 5.0) * 1.0)
		var mc := Color("#5cd8ff") if u.is_player else UITheme.C_GOLD
		draw_colored_polygon(PackedVector2Array([Vector2(cx - 4, cy - 4), Vector2(cx + 4, cy - 4), Vector2(cx, cy + 1)]), mc)
	var yy := top - 4
	if not u.is_player and u.alive:
		# detection icon + red hp bar (like the mock-up)
		var bw := 24.0
		var bx := roundf(cx - bw / 2.0 + 5.0)
		var by := yy
		var icon := "icon_skull" if u.vis_aware else ("icon_question" if u.vis_state == "searching" else "icon_eye")
		var icol := Color(1, 1, 1, a) if u.vis_state != "idle" or u.vis_aware else Color(0.75, 0.8, 0.8, 0.6 * a)
		if u.vis_state == "searching":
			icol = Color(1.0, 0.9, 0.35, a)
		draw_texture(SpriteFactory.get_texture(icon), Vector2(bx - 13, by - 4), icol)
		draw_rect(Rect2(bx - 1, by - 1, bw + 2, 5), Color(0.04, 0.04, 0.06, 0.9 * a))
		var frac := clampf(float(u.vis_hp) / float(maxi(1, u.max_hp)), 0.0, 1.0)
		var col := Color("#a060d0") if u.infected else Color("#e03a44")
		draw_rect(Rect2(bx, by, roundf(bw * frac), 3), col)
		draw_rect(Rect2(bx, by, roundf(bw * frac), 1), col.lightened(0.35))
		yy -= 8
		if u.vis_alert > 0.0:
			# red "!" over an enemy that has just spotted you: bobs, then fades away after a few seconds
			var fa := clampf(u.vis_alert / 1.0, 0.0, 1.0)
			var ey := yy - 4.0 + roundf(sin(time * 8.0 + float(u.uid)) * 1.0)
			var ec := Color(1.0, 0.25, 0.2, a * fa)
			UITheme.draw_text(self, Vector2(cx - 2, ey + 5), "!", UITheme.SZ_L, Color(0.05, 0.02, 0.02, a * fa))
			UITheme.draw_text(self, Vector2(cx - 3, ey + 4), "!", UITheme.SZ_L, ec)
			yy -= 14
		if u.vis_state == "searching":
			# big bobbing '?' while the enemy hunts for you
			var qy := yy - 4.0 + roundf(sin(time * 6.0 + float(u.uid)) * 1.0)
			UITheme.draw_text(self, Vector2(cx - 3, qy + 5), "?", UITheme.SZ_M, Color(1.0, 0.88, 0.2, a))
			yy -= 11
		# facing-based damage preview
		if preview.has(u.pos):
			var pv: Dictionary = preview[u.pos]
			var dname := String(pv["dir"])
			var mult := float(pv["mult"])
			var txt := "%s x%s" % [String(DB.facing_cfg()["labels"][dname]), str(snappedf(mult, 0.01))]
			var pc := Color("#7dff8a") if mult > 1.01 else (Color("#ff7a6a") if mult < 0.99 else Color("#e8e2c8"))
			var tw := UITheme.text_size(txt, UITheme.SZ_S).x
			var px := roundf(cx - (tw + 14) / 2.0)
			draw_rect(Rect2(px - 1, yy - 9, tw + 19, 13), Color(0.03, 0.05, 0.1, 0.92))
			draw_rect(Rect2(px - 0.5, yy - 8.5, tw + 18, 12), pc, false, 1.0)
			draw_texture(SpriteFactory.get_texture("icon_face_" + dname), Vector2(px + 1, yy - 8))
			UITheme.draw_text_in(self, Rect2(px + 13, yy - 9, tw + 4, 13), txt, UITheme.SZ_S, pc, HORIZONTAL_ALIGNMENT_LEFT, false)
			yy -= 15
	# status row
	var icons := []
	if u.block > 0:
		icons.append(["icon_shield", u.block])
	if u.st("bleed") > 0:
		icons.append(["icon_drop", u.st("bleed")])
	if u.st("poison") > 0:
		icons.append(["icon_spore", u.st("poison"), Color("#9aff5a")])
	if u.st("web") > 0:
		icons.append(["icon_stun", u.st("web"), Color("#e8e8ff")])
	if u.st("spores") > 0:
		icons.append(["icon_spore", u.st("spores")])
	if u.st("weak") > 0:
		icons.append(["icon_weak", u.st("weak")])
	if u.st("expose") > 0:
		icons.append(["icon_eye", u.st("expose")])
	if u.st("stun") > 0:
		icons.append(["icon_stun", u.st("stun")])
	if u.st("mark") > 0:
		icons.append(["icon_eye", u.st("mark"), Color("#ffb060")])
	if u.st("daze") > 0:
		icons.append(["icon_stun", u.st("daze"), Color("#c8a0ff")])
	if u.st("fear") > 0:
		icons.append(["icon_alert", u.st("fear"), Color("#d890ff")])
	var sx := roundf(cx - icons.size() * 11.0)
	for ic in icons:
		var itint: Color = ic[2] if ic.size() > 2 else Color.WHITE
		draw_texture(SpriteFactory.get_texture(ic[0]), Vector2(sx, yy - 5), Color(itint.r, itint.g, itint.b, a))
		UITheme.draw_text(self, Vector2(sx + 12, yy + 3), str(ic[1]), UITheme.SZ_S, Color.WHITE)
		sx += 22
	# enemy INTENT (what it will do on its next turn; shown on your turn, Slay-the-Spire style)
	if not u.is_player and u.alive and battle.phase == "player":
		var it: Dictionary = battle.intent_of(u)
		if not it.is_empty() and String(it["kind"]) != "idle":
			var kind := String(it["kind"])
			var icon := "icon_claw"
			var col := Color("#ffd0a0")
			var txt := ""
			var dmg := int(it.get("dmg", 0))
			match kind:
				"attack":
					txt = str(dmg)
				"ranged":
					icon = "icon_bolt"
					txt = str(dmg)
				"leap":
					icon = "icon_leap"
					txt = str(dmg)
				"aoe":
					icon = "icon_alert"
					txt = str(dmg)
				"charge", "windup":
					icon = "icon_alert"
					col = Color("#ff8060")
					txt = str(dmg)
				"block":
					icon = "icon_shield"
					col = Color("#9ac8ff")
				"infect":
					icon = "icon_spore"
					txt = str(dmg) if dmg > 0 else ""
				"summon":
					icon = "icon_skull"
					txt = "+"
				"flee":
					icon = "icon_foot"
					col = Color("#d0c0ff")
				"stun":
					icon = "icon_stun"
					col = Color("#ffe060")
				"search":
					icon = "icon_question"
					col = Color("#ffe060")
			var label := String(it.get("label", ""))
			var tw2 := UITheme.text_size(txt, UITheme.SZ_S).x if txt != "" else 0.0
			var bw2 := 13.0 + tw2 + 5.0
			var ix := roundf(cx + 14.0)
			var iy := roundf(top - 8.0)
			draw_rect(Rect2(ix - 1, iy - 1, bw2, 13), Color(0.03, 0.05, 0.1, 0.9))
			draw_rect(Rect2(ix - 0.5, iy - 0.5, bw2 - 1.0, 12.0), Color(col.r, col.g, col.b, 0.6), false, 1.0)
			draw_texture(SpriteFactory.get_texture(icon), Vector2(ix, iy), col if kind in ["charge", "windup", "flee", "stun", "search", "block"] else Color.WHITE)
			if txt != "":
				UITheme.draw_text(self, Vector2(ix + 13, iy + 9), txt, UITheme.SZ_S, col, HORIZONTAL_ALIGNMENT_LEFT, -1.0, false)
			if kind in ["charge", "windup", "aoe", "summon", "leap"]:
				UITheme.draw_text(self, Vector2(ix, iy + 21), label, UITheme.SZ_S, col, HORIZONTAL_ALIGNMENT_LEFT, -1.0, false)
	var tile_p := Vector2i(roundi(u.vis_pos.x), roundi(u.vis_pos.y))
	if u.is_player and battle.is_hidden() and battle.grid.in_bounds(tile_p) and battle.grid.is_grass(tile_p):
		draw_texture(SpriteFactory.get_texture("icon_eye"), Vector2(cx - 5, top - 4), Color(0.7, 1, 0.7, 0.95))

func _draw_ambient() -> void:
	var pcfg: Dictionary = _theme.get("particles", {})
	var ty := String(pcfg.get("type", ""))
	var col := Color.html(String(pcfg.get("color", "#ffffff")))
	var sz := int(pcfg.get("size", 1))
	for f in _flakes:
		var p := Vector2(floorf(f["x"]), floorf(f["y"]))
		match ty:
			"snow":
				var s := 2 if f["z"] > 1.3 else 1
				draw_rect(Rect2(p, Vector2(s, s)), Color(col.r, col.g, col.b, 0.55 + 0.4 * (f["z"] - 0.5)))
			"pollen":
				var tw := 0.35 + 0.65 * absf(sin(time * 1.3 + f["ph"]))
				draw_rect(Rect2(p, Vector2(sz, sz)), Color(col.r, col.g, col.b, tw * 0.8))
	# weather overlays
	match weather_id:
		"rain", "storm":
			var rc := Color(0.7, 0.82, 1.0, 0.42)
			var rvr := Rect2(-view_off, size)
			for i in int(90.0 * maxf(1.0, rvr.size.x * rvr.size.y / (640.0 * 360.0))):
				var x := rvr.position.x + fposmod(i * 97.0 + _rain_t * 0.45, rvr.size.x + 12.0) - 6.0
				var y := rvr.position.y + fposmod(i * 61.0 + _rain_t * 1.0, rvr.size.y + 12.0) - 6.0
				draw_line(Vector2(floorf(x), floorf(y)), Vector2(floorf(x) - 1, floorf(y) + 4), rc, 1.0)
			draw_rect(Rect2(-view_off, size), Color(0.05, 0.1, 0.2, 0.18 if weather_id == "rain" else 0.28))
			if _flash > 0.0:
				draw_rect(Rect2(-view_off, size), Color(1, 1, 1, 0.45 * _flash))
		"fog":
			for i in 5:
				var x := floorf(fposmod(time * (3.0 + i * 1.0) + i * 150.0, 880.0) - 230.0)
				var y := 40.0 + i * 60.0
				draw_rect(Rect2(x, y, 280, 30), Color(0.85, 0.92, 0.95, 0.10))
				draw_rect(Rect2(x + 20, y + 7, 240, 17), Color(0.85, 0.92, 0.95, 0.07))
			draw_rect(Rect2(-view_off, size), Color(0.8, 0.88, 0.92, 0.13))
		"heat":
			draw_rect(Rect2(-view_off, size), Color(1.0, 0.55, 0.15, 0.08))
		"cold":
			draw_rect(Rect2(-view_off, size), Color(0.55, 0.75, 1.0, 0.10))
