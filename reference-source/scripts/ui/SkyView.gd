class_name SkyView
extends Control
## Animated, weather-themed sky shot for the stage-intro cinematic (procedural, pixel-art look at PX logical px per art pixel).
## Looks come from data/weather.json -> "sky" per weather (gradient, clouds, sun, fog, rain / snow, lightning, heat shimmer).
## Designer PNGs replace any procedural layer (assets/sprites/, 1 art pixel = PX logical px, nearest filtering):
##   sky_<weather>_bg.png       full-screen backdrop, stretched to cover the window (suggested 480x270)
##   sky_<weather>_clouds.png   transparent cloud strip, tiled horizontally and scrolled slowly (any width, suggested height 120)
##   sky_<weather>_horizon.png  transparent skyline / ground strip along the bottom edge, tiled horizontally (suggested height 80)
## Rain / snow / lightning / fog stay procedural so they always match the weather.

const PX := 2

var weather_id := "clear"
var theme_id := "jungle"
var time := 0.0
var animate := true
var _rng := RandomNumberGenerator.new()
var _clouds: Array = []           # {tex, x, y, k, v}
var _clouds_for := Vector2.ZERO
var _drops: Array = []
var _horizon: ImageTexture = null
var _horizon_for := Vector2i.ZERO
var _flash := 0.0
var _flash_cd := 1.2
var _bolt: PackedVector2Array = PackedVector2Array()

static func cfg_for(id: String) -> Dictionary:
	var w: Dictionary = DB.table("weather")
	return (w.get(id, w["clear"]) as Dictionary).get("sky", {})

static func override_tex(weather: String, layer: String) -> Texture2D:
	var p := "res://assets/sprites/sky_%s_%s.png" % [weather, layer]
	return load(p) as Texture2D if ResourceLoader.exists(p) else null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.seed = 7771 + weather_id.hash() % 1000

func _process(dt: float) -> void:
	if animate:
		time += dt
	_update_fx(dt)
	queue_redraw()

# ------------------------------------------------------------------ procedural cloud / horizon textures
static func make_cloud(seed_: int, w: int, h: int, col: Color, shade: Color) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var blobs: Array = []
	for i in rng.randi_range(5, 8):
		blobs.append(Vector3(rng.randf_range(0.18, 0.82) * w, rng.randf_range(0.42, 0.62) * h, rng.randf_range(0.16, 0.30) * h))
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var base := h * 0.82
	var top: Array = []
	top.resize(w)
	top.fill(h)
	for x in w:
		for y in h:
			if float(y) > base:
				continue
			for bl in blobs:
				var b: Vector3 = bl
				var dx: float = (x - b.x) / (b.z * 1.5)
				var dy: float = (y - b.y) / (b.z * 0.9)
				if dx * dx + dy * dy <= 1.0:
					top[x] = mini(int(top[x]), y)
					img.set_pixel(x, y, col)
					break
	var bayer := [0.0, 0.5, 0.75, 0.25]
	for x in w:
		for y in h:
			if img.get_pixel(x, y).a > 0.0:
				var d := float(y - int(top[x])) / maxf(1.0, (base - float(top[x])))
				var thr := float(bayer[(x % 2) * 2 + (y % 2)])
				var c := col if d < 0.38 + (thr - 0.4) * 0.35 else shade
				img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

func _build_clouds(vp: Vector2) -> void:
	_clouds.clear()
	_clouds_for = vp
	var c: Dictionary = cfg_for(weather_id).get("clouds", {})
	if c.is_empty():
		return
	var col := Color.html(String(c["color"]))
	var sh := Color.html(String(c["shade"]))
	var texs: Array = []
	for i in 3:
		texs.append(make_cloud(100 + i * 17 + weather_id.hash() % 50, 46 + i * 8, 22 + i * 3, col, sh))
	var n := int(round(float(c["count"]) * maxf(1.0, vp.x / 640.0)))
	var band: Array = c["band"]
	var sz: Array = c["size"]
	for i in n:
		var k := _rng.randi_range(int(sz[0]), int(sz[1]))
		_clouds.append({"tex": texs[_rng.randi() % 3], "x": _rng.randf_range(0.0, vp.x + 270.0), "y": vp.y * _rng.randf_range(float(band[0]), float(band[1])),
			"k": k, "v": float(c["speed"]) * (0.5 + float(k) / float(sz[1]))})
	_clouds.sort_custom(func(a, b): return a["k"] < b["k"])

func _sky_bottom_color() -> Color:
	return Color.html(String(cfg_for(weather_id).get("bottom", "#bfe6ff")))

func _build_horizon(vp: Vector2) -> void:
	var w := int(ceil(vp.x / PX)) + 2
	var h := int(ceil(vp.y * 0.34 / PX))
	_horizon_for = Vector2i(int(vp.x), int(vp.y))
	var sky_c := _sky_bottom_color()
	var ground := SpriteFactory.theme_bg(theme_id)
	var far_c := sky_c.lerp(ground, 0.38)
	var mid_c := sky_c.lerp(ground, 0.68)
	var near_c := ground.darkened(0.45)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var pine := theme_id == "tundra"
	var sd := float(weather_id.hash() % 100)
	for x in w:
		var fh := float(h) * (0.62 + 0.10 * sin(x * 0.035 + sd) + 0.05 * sin(x * 0.11 + sd * 2.0))
		var mh := float(h) * (0.47 + 0.09 * sin(x * 0.05 + 1.7 + sd) + 0.05 * sin(x * 0.17 + sd))
		var tree: float
		if pine:
			var f := fposmod(x / 8.0 + sin(x * 0.07) * 0.5, 1.0)
			tree = (1.0 - absf(f * 2.0 - 1.0)) * 0.20 * (0.75 + 0.25 * sin(x * 0.13 + sd))
		else:
			tree = pow(absf(sin(x * 0.21 + sin(x * 0.05) * 3.0)), 0.55) * 0.17 * (0.7 + 0.3 * sin(x * 0.09 + sd))
		var nh := float(h) * (0.28 + tree)
		for y in h:
			var yy := h - 1 - y          # height above the bottom edge
			var c := Color(0, 0, 0, 0)
			if yy < fh:
				c = far_c
			if yy < mh:
				c = mid_c
			if yy < nh:
				c = near_c
			if c.a > 0.0 and yy < fh and yy >= int(nh) and yy < mh and false:
				c = c
			img.set_pixel(x, y, c if c.a > 0.0 else Color(0, 0, 0, 0))
	_horizon = ImageTexture.create_from_image(img)

# ------------------------------------------------------------------ precipitation / lightning
func _update_fx(dt: float) -> void:
	var vp := size
	if vp.x < 1.0:
		return
	var c := cfg_for(weather_id)
	var pc: Dictionary = c.get("precip", {})
	if not pc.is_empty():
		var want := int(round(float(pc["count"]) * vp.x * vp.y / (640.0 * 360.0)))
		while _drops.size() < want:
			_drops.append({"x": _rng.randf(), "y": _rng.randf(), "v": _rng.randf_range(0.75, 1.25), "ph": _rng.randf() * TAU})
		while _drops.size() > want:
			_drops.pop_back()
		var rain := String(pc["type"]) == "rain"
		for d in _drops:
			d["y"] += float(pc["speed"]) * d["v"] * dt / vp.y
			d["x"] += (float(pc["slant"]) * -1.0 * float(pc["speed"]) * d["v"] * dt / vp.x * (1.0 if rain else 0.0)) + (0.0 if rain else sin(time * 0.9 + d["ph"]) * 10.0 * dt / vp.x)
			if d["y"] > 1.0:
				d["y"] -= 1.0
				d["x"] = _rng.randf()
			d["x"] = fposmod(d["x"], 1.0)
	if c.get("lightning", false) and animate:
		_flash_cd -= dt
		if _flash_cd <= 0.0:
			_flash = 1.0
			_flash_cd = _rng.randf_range(2.2, 4.2)
			_bolt = _make_bolt(vp)
		_flash = maxf(0.0, _flash - dt * 2.2)

func _make_bolt(vp: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var x := vp.x * _rng.randf_range(0.2, 0.8)
	var y := vp.y * 0.12
	pts.append(Vector2(x, y))
	while y < vp.y * 0.62:
		x += _rng.randf_range(-22.0, 22.0)
		y += _rng.randf_range(14.0, 30.0)
		pts.append(Vector2(roundf(x / PX) * PX, roundf(y / PX) * PX))
	return pts

# ------------------------------------------------------------------ drawing
func _draw() -> void:
	var vp := size
	if vp.x < 1.0 or vp.y < 1.0:
		return
	var c := cfg_for(weather_id)
	var top := Color.html(String(c.get("top", "#3f8fe0")))
	var bot := Color.html(String(c.get("bottom", "#bfe6ff")))
	# --- backdrop: designer PNG, else a banded (pixel-art) vertical gradient
	var bg := SkyView.override_tex(weather_id, "bg")
	if bg != null:
		draw_texture_rect(bg, Rect2(Vector2.ZERO, vp), false)
	else:
		var bands := int(ceil(vp.y / (PX * 4.0)))
		for i in bands:
			var t := float(i) / float(maxi(1, bands - 1))
			draw_rect(Rect2(0.0, i * PX * 4.0, vp.x, PX * 4.0 + 1.0), top.lerp(bot, t * t * 0.4 + t * 0.6))
	# --- sun
	if c.has("sun") and bg == null:
		var s: Dictionary = c["sun"]
		var sc := Color.html(String(s["color"]))
		var cen := Vector2(roundf(vp.x * float(s["x"]) / PX) * PX, roundf(vp.y * float(s["y"]) / PX) * PX)
		var r := float(s["r"]) * maxf(1.0, vp.y / 360.0)
		for i in 5:
			var rr := r * (2.6 - i * 0.4)
			draw_circle(cen, rr, Color(sc.r, sc.g, sc.b, 0.05 + 0.025 * i + 0.02 * sin(time * 0.8)))
		draw_circle(cen, r, sc)
	# --- clouds
	var co: Dictionary = c.get("clouds", {})
	var ctex := SkyView.override_tex(weather_id, "clouds")
	if ctex != null:
		var cw := ctex.get_width() * PX
		var x0 := -fposmod(time * 6.0, float(cw))
		var ch := ctex.get_height() * PX
		var n := int(ceil(vp.x / cw)) + 2
		for i in n:
			draw_texture_rect(ctex, Rect2(x0 + i * cw, vp.y * 0.08, cw, ch), false)
	elif not co.is_empty():
		if _clouds_for != vp:
			_build_clouds(vp)
		var al := float(co["alpha"])
		var span := vp.x + 320.0
		for cl in _clouds:
			var t2: Texture2D = cl["tex"]
			var sz := t2.get_size() * float(cl["k"])
			var x := fposmod(float(cl["x"]) + time * float(cl["v"]), span) - 160.0 - sz.x * 0.5
			draw_texture_rect(t2, Rect2(Vector2(roundf(x / PX) * PX, roundf(float(cl["y"]) / PX) * PX), sz), false, Color(1, 1, 1, al))
	# --- heat shimmer / fog
	if c.get("shimmer", false):
		for i in 9:
			var y := vp.y * (0.45 + i * 0.05)
			var off := sin(time * 1.6 + i * 0.9) * 6.0
			draw_rect(Rect2(off, roundf(y / PX) * PX, vp.x, PX * 2.0), Color(1.0, 0.85, 0.5, 0.10))
	var fg := float(c.get("fog", 0.0))
	if fg > 0.0:
		for i in 6:
			var x := fposmod(time * (5.0 + i * 2.0) + i * 170.0, vp.x + 470.0) - 330.0
			var y := vp.y * (0.2 + i * 0.1)
			draw_rect(Rect2(roundf(x / PX) * PX, roundf(y / PX) * PX, 320.0, 36.0), Color(0.9, 0.94, 0.96, 0.12 * fg + 0.04))
			draw_rect(Rect2(roundf(x / PX) * PX + 20, roundf(y / PX) * PX + 8, 280.0, 20.0), Color(0.9, 0.94, 0.96, 0.08 * fg))
		draw_rect(Rect2(0, vp.y * 0.45, vp.x, vp.y * 0.55), Color(0.82, 0.88, 0.9, 0.22 * fg))
	# --- lightning bolt (behind the skyline)
	if _flash > 0.4 and _bolt.size() > 1:
		draw_polyline(_bolt, Color(1, 1, 0.92, minf(1.0, _flash)), PX * 1.0)
	# --- skyline strip along the bottom (designer PNG or procedural hills / trees)
	var htex := SkyView.override_tex(weather_id, "horizon")
	if htex != null:
		var hw := htex.get_width() * PX
		var hh := htex.get_height() * PX
		for i in int(ceil(vp.x / hw)) + 1:
			draw_texture_rect(htex, Rect2(i * hw, vp.y - hh, hw, hh), false)
	else:
		if _horizon == null or _horizon_for != Vector2i(int(vp.x), int(vp.y)):
			_build_horizon(vp)
		var hs := _horizon.get_size() * PX
		draw_texture_rect(_horizon, Rect2(0.0, vp.y - hs.y, hs.x, hs.y), false)
	# --- precipitation
	var pc: Dictionary = c.get("precip", {})
	if not pc.is_empty():
		var rain := String(pc["type"]) == "rain"
		var slant := float(pc["slant"])
		for d in _drops:
			var p := Vector2(roundf(float(d["x"]) * vp.x / PX) * PX, roundf(float(d["y"]) * vp.y / PX) * PX)
			if rain:
				draw_line(p, p + Vector2(slant * 19.0, -19.0), Color(0.78, 0.86, 1.0, 0.55), 2.0)
			else:
				var s2 := float(PX if d["v"] > 1.0 else 2)
				draw_rect(Rect2(p, Vector2(s2, s2)), Color(1, 1, 1, 0.55 + 0.4 * (float(d["v"]) - 0.75)))
		if rain:
			draw_rect(Rect2(Vector2.ZERO, vp), Color(0.04, 0.08, 0.16, 0.12 if weather_id == "rain" else 0.2))
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(1, 1, 1, 0.5 * _flash * _flash))
