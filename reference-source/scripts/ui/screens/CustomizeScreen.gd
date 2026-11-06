extends ScreenBase
## After picking an egg: the egg cracks open in the middle of the screen and an eye peeks out. The player customizes the
## hatchling (skin colour, pattern, pattern colour, gender - COSMETIC ONLY) with a live preview (head in the egg + all four
## growth stages), then confirms to hatch. Options come from data/customization.json (Look.gd). Reset each run.

## The cracking egg with the creature's head peeking out (drawn in code; recoloured head texture from SpriteFactory.looked).
class EggView extends Control:
	var species_id: String = ""
	var look: Dictionary = {}
	var t: float = 0.0
	var burst: float = 0.0
	var _egg: Texture2D
	var _egg_scale: float = SCALE
	var _head: Texture2D
	var _lid: Color = Color("#3a5a2c")
	var _eye: Vector2 = Vector2(28, 15)
	const BASE := Vector2(100, 157)          # bottom-centre of the egg
	const SCALE := 5.0                       # used when no <egg>_hi sprite exists (egg drawn 5x); the _hi egg (tools/hires_backdrops.py) is 1:1
	const HSCALE := 2.0
	const HOLE := Vector2(0, -79)           # hole centre relative to BASE
	const CRACKS := [
		[Vector2(-3, -124), Vector2(4, -112), Vector2(-4, -103), Vector2(5, -93), Vector2(-2, -85)],
		[Vector2(5, -93), Vector2(17, -89), Vector2(25, -95), Vector2(36, -88)],
		[Vector2(-4, -103), Vector2(-17, -100), Vector2(-27, -105), Vector2(-39, -97)],
		[Vector2(-2, -85), Vector2(-12, -75), Vector2(-23, -77)]]

	func setup(species: String, lk: Dictionary) -> EggView:
		species_id = species
		custom_minimum_size = Vector2(200, 167)
		size = Vector2(200, 167)
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pv: Dictionary = Look.cfg(species).get("preview", {})
		var egg_id := String(pv.get("egg", String(DB.species(species)["sprites"]["egg"])))
		_egg = SpriteFactory.png(egg_id + "_hi") if SpriteFactory.png(egg_id + "_hi") != null else SpriteFactory.get_texture(egg_id)
		_egg_scale = 1.0 if SpriteFactory.png(egg_id + "_hi") != null else SCALE
		var e: Array = pv.get("eye", [42, 22])
		_eye = Vector2(float(e[0]), float(e[1]))
		set_look(lk)
		return self

	func set_look(lk: Dictionary) -> void:
		look = lk
		var pv: Dictionary = Look.cfg(species_id).get("preview", {})
		var hid := String(pv.get("head", "portrait_baby"))
		var img := SpriteFactory.looked(hid, lk).get_image()
		_head = ImageTexture.create_from_image(img)
		var p := img.get_pixel(clampi(int(_eye.x) - 6, 0, img.get_width() - 1), clampi(int(_eye.y) - 9, 0, img.get_height() - 1))
		_lid = Color(p.r, p.g, p.b, 1.0).darkened(0.12)
		queue_redraw()

	func openness() -> float:
		return smoothstep(0.0, 1.0, clampf((t - 2.0) / 0.6, 0.0, 1.0))

	func is_open() -> bool:
		return t >= 2.6

	func _process(dt: float) -> void:
		t += dt
		queue_redraw()

	func _ring(center: Vector2, rx: float, ry: float, n: int, jag: bool) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in n:
			var a := TAU * float(i) / float(n)
			var f := 1.0
			if jag:
				f = 1.0 if i % 2 == 0 else 0.78
				f *= 0.92 + 0.16 * float(posmod(RunState.mix(i * 7 + 3, 11), 100)) / 100.0
			pts.append(center + Vector2(cos(a) * rx * f, sin(a) * ry * f))
		return pts

	func _draw() -> void:
		var wob := 0.0
		if t < 1.0:
			wob = sin(t * 22.0) * 0.07 * (t / 1.0)
		elif t < 2.0:
			wob = sin(t * 30.0) * 0.035
		draw_set_transform_matrix(Transform2D(wob, BASE))
		# soft shadow
		draw_set_transform_matrix(Transform2D(0.0, BASE))
		draw_colored_polygon(_ring(Vector2(0, -2), 62, 6, 20, false), Color(0, 0, 0, 0.3))
		draw_set_transform_matrix(Transform2D(wob, BASE))
		var fade := 1.0 - burst
		var es := _egg.get_size() * _egg_scale
		var egg_rect := Rect2(Vector2(-es.x * 0.5, -es.y), es)
		draw_texture_rect(_egg, egg_rect, false, Color(1, 1, 1, fade))
		# cracks grow from the top
		var cp := clampf((t - 1.0) / 1.0, 0.0, 1.0)
		if cp > 0.0:
			var total := CRACKS.size()
			for i in total:
				var pc := clampf(cp * float(total) - float(i) * 0.55, 0.0, 1.0)
				var pts: Array = CRACKS[i]
				var n := int(ceil(pc * float(pts.size() - 1)))
				if pc <= 0.0 or n < 1:
					continue
				var line := PackedVector2Array()
				for k in n:
					line.append(pts[k])
				var frac := pc * float(pts.size() - 1) - float(n - 1)
				line.append(pts[n - 1].lerp(pts[n], clampf(frac, 0.0, 1.0)))
				draw_polyline(line, Color(0.2, 0.15, 0.08, fade), 3.0)
				draw_polyline(line, Color(0.42, 0.34, 0.2, fade), 1.0)
		var op := openness()
		if op > 0.0:
			var grow := 1.0 + burst * 1.1
			var rx := 58.0 * op * grow
			var ry := 44.0 * op * grow
			draw_colored_polygon(_ring(HOLE, rx * 1.14, ry * 1.16, 22, true), Color(0.05, 0.04, 0.03, fade))
			var bob := float(int(sin(t * 2.0) * 1.2 + 0.5))
			var pimg := HOLE + Vector2(-7, bob) - _eye * HSCALE
			var pts2 := _ring(HOLE, rx, ry, 22, true)
			var uvs := PackedVector2Array()
			for p in pts2:
				uvs.append((p - pimg) / (HSCALE * Vector2(_head.get_size())))
			draw_colored_polygon(pts2, Color(1, 1, 1, fade), uvs, _head)
			# blink: an eyelid closes over the eye every few seconds
			var ph := fmod(t, 3.3)
			var amt := 0.0
			if ph > 2.95 and ph < 3.2:
				amt = sin(PI * (ph - 2.95) / 0.25)
			if amt > 0.02 and op > 0.9:
				var ec := pimg + _eye * HSCALE
				draw_colored_polygon(_ring(ec, 5.0, 5.0 * amt, 16, false), Color(_lid.r, _lid.g, _lid.b, fade))
			# shell shards round the hole
			for i in 7:
				var a := TAU * (float(i) + 0.3) / 7.0
				var d := Vector2(cos(a) * rx * 1.18, sin(a) * ry * 1.2) * (1.0 + burst * 0.9) + Vector2(0, burst * burst * 47.0)
				var c0 := HOLE + d
				var sz := 11.0 + float(posmod(RunState.mix(i * 5 + 1, 3), 7))
				var tri := PackedVector2Array([c0 + Vector2(-sz, sz * 0.5), c0 + Vector2(sz * 0.2, -sz), c0 + Vector2(sz, sz * 0.6)])
				draw_colored_polygon(tri, Color(0.5, 0.39, 0.22, fade))
				var tri2 := PackedVector2Array([c0 + Vector2(-sz + 2, sz * 0.4), c0 + Vector2(sz * 0.2, -sz + 3), c0 + Vector2(sz - 2, sz * 0.5)])
				draw_colored_polygon(tri2, Color(0.88, 0.79, 0.57, fade))
		draw_set_transform_matrix(Transform2D.IDENTITY)

## Portrait jungle scene (bg_customize: cream egg in a twig/fern nest, the egg itself is NOT in the art - EggView draws it on
## top so it can wobble, crack and hatch). Drawn at an integer SCALE (nearest, no stretching) with the nest's hollow under
## the egg; the picture is mirrored sideways/up/down to continue the foliage on wide or tall windows (no bars, no stretch).
class NestBackdrop extends Control:
	const SCALE := 1
	const ANCHOR := Vector2(200.0, 385.0)   ## px of the hollow's bottom-centre in bg_customize_hi (400x540, 1:1 with the canvas)
	const EGG_AT := Vector2(160.0, 196.0)    ## frame position of that point (EggView BASE)
	var _tex: Texture2D
	func _init() -> void:
		name = "Backdrop"
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		position = Vector2(-2667, -2667)
		size = Vector2(6000, 6000)
		_tex = SpriteFactory.png("bg_customize_hi") if SpriteFactory.png("bg_customize_hi") != null else SpriteFactory.get_texture("bg_customize")
	func tile_size() -> Vector2:
		return _tex.get_size() * float(SCALE)
	func origin() -> Vector2:
		return EGG_AT - ANCHOR * float(SCALE)
	func _draw() -> void:
		var ts := tile_size()
		var o := origin() + Vector2(2667, 2667)        # this control starts at (-4000, -4000)
		for j in range(-3, 4):
			for i in range(-3, 5):
				var r := Rect2(o + Vector2(float(i) * ts.x, float(j) * ts.y), ts)
				var fx := absi(i) % 2 == 1
				var fy := absi(j) % 2 == 1
				if fx or fy:
					draw_set_transform(Vector2(r.position.x + (ts.x if fx else 0.0), r.position.y + (ts.y if fy else 0.0)), 0.0, Vector2(-1.0 if fx else 1.0, -1.0 if fy else 1.0))
					draw_texture_rect(_tex, Rect2(Vector2.ZERO, ts), false)
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				else:
					draw_texture_rect(_tex, r, false)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.04, 0.02, 0.22))
		# darker band behind the title so it stays readable
		for k in 8:
			draw_rect(Rect2(Vector2(0, 2667.0 + float(k) * 4.0 - 4.0), Vector2(6000, 4)), Color(0.0, 0.03, 0.02, 0.68 - 0.08 * float(k)))

## Round colour chip. `color` null/transparent = the species' original colouring (drawn split to show "classic").
class Swatch extends Control:
	signal picked(id: String)
	var id: String = ""
	var color: Color = Color.WHITE
	var selected: bool = false
	var dim: bool = false
	var diag: bool = false
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 19, 19), Color("#05080e"))
		if diag:
			draw_colored_polygon(PackedVector2Array([Vector2(2, 2), Vector2(17, 2), Vector2(2, 17)]), Color("#86b84e"))
			draw_colored_polygon(PackedVector2Array([Vector2(17, 2), Vector2(17, 17), Vector2(2, 17)]), Color("#4b999b"))
		else:
			draw_rect(Rect2(2, 2, 15, 15), Color(color.r, color.g, color.b, 0.35 if dim else 1.0))
		draw_rect(Rect2(0, 0, 19, 19), UITheme.C_GOLD if selected else Color("#3f5a78"), false, 2.0 if selected else 1.0)
	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			picked.emit(id)

var species_id: String = "velociraptor"
var seed_val: int = 0
var look: Dictionary = {}
var egg_view: EggView
var swatches: Dictionary = {}       # "group:id" -> Swatch
var option_btns: Dictionary = {}    # "group:id" -> Button
var stage_icons: Array = []
var summary: Label
var gender_note: Label
var confirm_btn: Button
var confirming: bool = false
var flash: ColorRect

func _ready() -> void:
	species_id = String(args.get("species", "velociraptor"))
	seed_val = int(args.get("seed", 0))
	look = Look.sanitize(args.get("look", {}), species_id)
	add_child(NestBackdrop.new())
	add_centered("YOUR HATCHLING", 4, 30, UITheme.C_GOLD)
	add_centered("Customize its look. Cosmetic only: colours and gender never change stats.", 25, 15, UITheme.C_DIM)
	egg_view = EggView.new().setup(species_id, look)
	egg_view.position = NestBackdrop.EGG_AT - EggView.BASE
	add_child(egg_view)
	# growth preview strip
	_glass(UITheme.panel(Rect2(8, 236, 308, 88), Color.BLACK, UITheme.C_BORDER, "ui_panel_dim"))
	add_label("Growth preview: the look carries through every stage", Vector2(16, 241), 15, UITheme.C_DIM)
	var conf: Dictionary = Look.cfg(species_id)
	var x := 16.0
	var stage_names := ["Baby", "Juvenile", "Adult", "Prime"]
	var ids: Array = conf.get("stage_sprites", [])
	for i in ids.size():
		var tr := TextureRect.new()
		tr.texture = SpriteFactory.looked(String(ids[i]), look)
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var sz := tr.texture.get_size() * 2.0
		tr.size = sz
		tr.position = Vector2(x, 292.0 - sz.y)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.name = "stage_%d" % i
		add_child(tr)
		stage_icons.append(tr)
		var lb := add_label(stage_names[i], Vector2(x - 6.0, 298), 15, UITheme.C_TEXT, sz.x + 12.0, HORIZONTAL_ALIGNMENT_CENTER)
		lb.name = "stage_lbl_%d" % i
		x += sz.x + 6.0
	# options panel
	_glass(UITheme.panel(Rect2(326, 38, 306, 284)))
	_build_options(conf)
	summary = add_label("", Vector2(336, 212), 20, UITheme.C_GOLD, 290)
	add_label("Gender is purely cosmetic (a paler dorsal stripe). No gameplay effect.", Vector2(336, 234), 15, UITheme.C_DIM, 290)
	# buttons
	add_button("Back", Rect2(8, 332, 60, 20), func(): Game.goto("egg"), 20).name = "cust_back"
	var rnd := add_button("Random all", Rect2(326, 330, 100, 22), _random_all, 20)
	rnd.name = "cust_random"
	confirm_btn = add_button("HATCH!", Rect2(436, 326, 196, 30), _confirm, 30)
	confirm_btn.name = "cust_confirm"
	flash = ColorRect.new()
	flash.color = Color(1, 1, 1, 0)
	UITheme.full_rect(flash)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)
	_refresh()

func _glass(p: Panel) -> void:
	p.self_modulate = Color(1, 1, 1, 0.86)
	add_child(p)

func _section(label: String, y: float) -> void:
	add_label(label, Vector2(336, y), 15, UITheme.C_GOLD)

func _build_options(conf: Dictionary) -> void:
	_section("Skin color", 46)
	var x := 336.0
	for o in conf.get("skins", []):
		var sw := _swatch("skin", o, Vector2(x, 60))
		sw.diag = o.get("color", null) == null
		x += 24.0
	_section("Pattern", 88)
	x = 336.0
	for o in conf.get("patterns", []):
		_option_button("pattern", o, Rect2(x, 102, 68, 17))
		x += 72.0
	_section("Pattern color", 128)
	x = 336.0
	for o in conf.get("pcolors", []):
		_swatch("pcolor", o, Vector2(x, 142))
		x += 24.0
	_section("Gender", 168)
	x = 336.0
	for o in conf.get("genders", []):
		_option_button("gender", o, Rect2(x, 182, 84, 18))
		x += 90.0

func _swatch(group: String, o: Dictionary, pos: Vector2) -> Swatch:
	var sw := Swatch.new()
	sw.id = String(o["id"])
	sw.size = Vector2(19, 19)
	sw.position = pos
	if o.get("color", null) != null:
		sw.color = Color.html(String(o["color"]))
	sw.tooltip_text = String(o["name"])
	sw.name = "cust_%s_%s" % [group, o["id"]]
	sw.picked.connect(func(id: String): pick(group, id))
	add_child(sw)
	swatches["%s:%s" % [group, o["id"]]] = sw
	return sw

func _option_button(group: String, o: Dictionary, rect: Rect2) -> void:
	var b := add_button(String(o["name"]), rect, func(): pick(group, String(o["id"])), 15)
	b.name = "cust_%s_%s" % [group, o["id"]]
	b.tooltip_text = String(o.get("desc", o["name"]))
	option_btns["%s:%s" % [group, o["id"]]] = b

func pick(group: String, id: String) -> void:
	if confirming:
		return
	look[group] = id
	_refresh()

func _random_all() -> void:
	if confirming:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	look = Look.random_look(species_id, rng)
	_refresh()

## Re-style every control and re-render the previews for the current look.
func _refresh() -> void:
	for key in swatches:
		var p: PackedStringArray = String(key).split(":")
		var sw: Swatch = swatches[key]
		sw.selected = String(look[p[0]]) == p[1]
		sw.dim = p[0] == "pcolor" and String(look["pattern"]) == "solid"
		sw.queue_redraw()
	for key in option_btns:
		var p2: PackedStringArray = String(key).split(":")
		var b: Button = option_btns[key]
		var on := String(look[p2[0]]) == p2[1]
		UITheme.set_selected(b, on)
	egg_view.set_look(look)
	var conf: Dictionary = Look.cfg(species_id)
	var ids: Array = conf.get("stage_sprites", [])
	for i in stage_icons.size():
		stage_icons[i].texture = SpriteFactory.looked(String(ids[i]), look)
	summary.text = Look.describe(look)

func _confirm() -> void:
	if confirming:
		return
	confirming = true
	confirm_btn.disabled = true
	var tw := create_tween()
	tw.tween_property(egg_view, "burst", 1.0, 0.55)
	tw.parallel().tween_property(flash, "color:a", 1.0, 0.55).set_delay(0.25)
	await tw.finished
	_finish()

## Starts the run with the chosen look and moves on (the look is applied to every sprite of the hatchling).
func _finish() -> void:
	Game.start_run(species_id, seed_val, look)
	Game.goto(Game.intro_screen_name())      # story cutscene -> stage intro (weather) -> board
