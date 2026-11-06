class_name CutsceneView
extends Control
## Renders the intro story cutscene from the data-driven timeline (data/cutscene_intro.json) with the canvas `_draw()` API:
## pixel-art layers (sky, ground, sprites, procedural meteor / smoke / glow / spores), parallax camera pans, screen shake,
## flashes, letterbox bars, fades and short captions. Pure presentation: CutsceneScreen drives `t` and handles skipping.
##
## World coordinates are the 640x360 design frame (y down). `origin` is where that frame's top-left sits in this control; extra
## window room (wider / taller viewports) is filled by the wide layers (sky / ground / scenery), the bars crop it to a ~2.2:1 picture.
## Everything snaps to whole pixels (sprites are drawn at integer scales with nearest filtering).

signal sfx(id: String)

const KINDS := ["sky", "ground", "scene", "image", "shell", "eyelid", "meteor", "plume", "glow", "particles", "overlay", "creep"]
const FRAME := Vector2(640, 360)

var t: float = 0.0                 # global cutscene time (s)
var origin: Vector2 = Vector2.ZERO # top-left of the 640x360 frame inside this control
var skip_progress: float = 0.0     # 0..1 while the player holds a key / the mouse to skip (drawn as a bar)
var extra_black: float = 0.0       # quick fade to black when skipping
var show_prompt: float = 1.0       # alpha of the "hold to skip" hint
var sfx_log: Array = []            # every SFX cue that has fired: [[global_t, id], ...]
var tl: Dictionary = {}
var _last_t: float = -1.0
var _tex_cache: Dictionary = {}
var _cam: Vector2 = Vector2.ZERO
var _shake: Vector2 = Vector2.ZERO
var _gt: float = 0.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tl = timeline()

# ------------------------------------------------------------------ timeline data (static helpers, also used by the tests)

static func timeline() -> Dictionary:
	return DB.table("cutscene_intro")

static func total_time(tl_d: Dictionary) -> float:
	var s := 0.0
	for sh in tl_d.get("shots", []):
		s += float(sh["dur"])
	return s

static func shot_start(tl_d: Dictionary, idx: int) -> float:
	var s := 0.0
	for i in idx:
		s += float(tl_d["shots"][i]["dur"])
	return s

## {"shot": index, "lt": time inside that shot} for global time `tt` (clamped to the last frame).
static func locate(tl_d: Dictionary, tt: float) -> Dictionary:
	var shots: Array = tl_d.get("shots", [])
	var acc := 0.0
	for i in shots.size():
		var d := float(shots[i]["dur"])
		if tt < acc + d or i == shots.size() - 1:
			return {"shot": i, "lt": clampf(tt - acc, 0.0, d)}
		acc += d
	return {"shot": 0, "lt": 0.0}

static func bar_height(vp: Vector2, tl_d: Dictionary) -> float:
	var lb: Dictionary = tl_d.get("letterbox", {})
	var aspect := float(lb.get("aspect", 2.2))
	var min_bar := float(lb.get("min_bar", 35))
	return maxf(min_bar, floorf((vp.y - vp.x / aspect) * 0.5))

static func ease_smooth(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

static func _col(v: Variant) -> Color:
	return v if v is Color else Color(String(v))

## Keyframe lookup: keys = [[t, value], ...] sorted by t. Values are numbers or "#rrggbb" strings; linear in between, clamped outside.
static func keyval(keys: Array, tt: float, def: Variant = 0.0) -> Variant:
	if keys.is_empty():
		return def
	var first: Array = keys[0]
	if tt <= float(first[0]):
		return _col(first[1]) if first[1] is String else first[1]
	for i in range(1, keys.size()):
		var a: Array = keys[i - 1]
		var b: Array = keys[i]
		if tt <= float(b[0]):
			var span := float(b[0]) - float(a[0])
			var f := 0.0 if span <= 0.0001 else (tt - float(a[0])) / span
			if a[1] is String:
				return _col(a[1]).lerp(_col(b[1]), f)
			return lerpf(float(a[1]), float(b[1]), f)
	var last: Array = keys[keys.size() - 1]
	return _col(last[1]) if last[1] is String else last[1]

static func _hash(i: int, k: int) -> float:
	return fposmod(sin(float(i) * 12.9898 + float(k) * 78.233) * 43758.5453, 1.0)

## Sprite a layer uses: designer override assets/sprites/cutscene_<shot>_<layer>.png / cutscene_<layer>.png, else the named game sprite.
static func layer_texture(shot_id: String, layer: Dictionary, infected: bool = false, use_b: bool = false) -> Texture2D:
	var lid := String(layer.get("id", ""))
	if lid != "" and not infected:
		for nm in ["cutscene_%s_%s" % [shot_id, lid], "cutscene_%s" % lid]:
			var ov := SpriteFactory.png(nm)
			if ov != null:
				return ov
	var img := String(layer.get("img_b", layer.get("img", ""))) if use_b else String(layer.get("img", ""))
	if bool(layer.get("own_look", false)):
		return SpriteFactory.looked(img, {}, infected)
	return SpriteFactory.get_texture(img, infected)

static func sprite_exists(img: String) -> bool:
	return SpriteFactory.png(img) != null or not DB.sprite_def(img).is_empty()

## Human-readable problems with the timeline data ([] = valid). Used by the tests.
static func validate(tl_d: Dictionary) -> Array:
	var errs: Array = []
	var shots: Array = tl_d.get("shots", [])
	if shots.size() < 5:
		errs.append("needs at least 5 shots")
	var seen := {}
	for sh in shots:
		var sid := String(sh.get("id", ""))
		if sid == "" or seen.has(sid):
			errs.append("shot id missing or duplicated: '%s'" % sid)
		seen[sid] = true
		var dur := float(sh.get("dur", 0.0))
		if dur <= 0.5:
			errs.append("%s: bad duration" % sid)
		if not sh.has("camera"):
			errs.append("%s: no camera" % sid)
		var layers: Array = sh.get("layers", [])
		if layers.is_empty():
			errs.append("%s: no layers" % sid)
		for ly in layers:
			var kind := String(ly.get("kind", ""))
			var tag := "%s/%s" % [sid, String(ly.get("id", kind))]
			if not KINDS.has(kind):
				errs.append("%s: unknown layer kind '%s'" % [tag, kind])
			var par: Variant = ly.get("par", 1.0)
			if not (par is float or par is int or (par is Array and par.size() == 2)):
				errs.append("%s: bad par" % tag)
			if kind == "image" or kind == "scene":
				if not sprite_exists(String(ly.get("img", ""))):
					errs.append("%s: sprite '%s' does not exist" % [tag, String(ly.get("img", ""))])
				if int(ly.get("scale", 1)) < 1 or float(ly.get("scale", 1)) != float(int(ly.get("scale", 1))):
					errs.append("%s: scale must be a whole number (integer scaling)" % tag)
			var ks: Dictionary = ly.get("keys", {})
			for prop in ks:
				var prev := -1.0
				for kf in ks[prop]:
					var kt := float(kf[0])
					if kt < prev or kt > dur + 0.01 or kt < 0.0:
						errs.append("%s: keys '%s' not ascending / outside the shot" % [tag, prop])
						break
					prev = kt
		for c in sh.get("captions", []):
			if String(c.get("text", "")) == "" or float(c["t"]) < 0.0 or float(c["t"]) + float(c["dur"]) > dur + 0.01:
				errs.append("%s: caption outside the shot" % sid)
		for key in ["shake", "flash", "sfx"]:
			for e in sh.get(key, []):
				if float(e["t"]) < 0.0 or float(e["t"]) > dur:
					errs.append("%s: %s cue outside the shot" % [sid, key])
	var total := total_time(tl_d)
	if total < 35.0 or total > 50.0:
		errs.append("total length %.1fs is outside 35-50 s" % total)
	return errs

# ------------------------------------------------------------------ time

## Moves the clock forward and fires the SFX cues passed on the way.
func advance_to(tt: float) -> void:
	if tt > _last_t:
		_fire_sfx(maxf(_last_t, 0.0) if _last_t >= 0.0 else -0.001, tt)
	_last_t = tt
	t = tt
	queue_redraw()

## Jump to a time without firing cues (frame captures).
func seek(tt: float) -> void:
	t = tt
	_last_t = tt
	queue_redraw()

func _fire_sfx(a: float, b: float) -> void:
	var acc := 0.0
	for sh in tl.get("shots", []):
		for c in sh.get("sfx", []):
			var ct := acc + float(c["t"])
			if ct > a and ct <= b:
				sfx_log.append([ct, String(c["id"])])
				sfx.emit(String(c["id"]))
		acc += float(sh["dur"])

# ------------------------------------------------------------------ drawing

func _par(layer: Dictionary) -> Vector2:
	var p: Variant = layer.get("par", 1.0)
	if p is Array:
		return Vector2(float(p[0]), float(p[1]))
	return Vector2(float(p), float(p))

func _num(layer: Dictionary, prop: String, lt: float, def: float) -> float:
	var ks: Dictionary = layer.get("keys", {})
	if ks.has(prop):
		return float(keyval(ks[prop], lt, def))
	return float(layer.get(prop, def))

func _colp(layer: Dictionary, prop: String, lt: float, def: String) -> Color:
	var ks: Dictionary = layer.get("keys", {})
	if ks.has(prop):
		return keyval(ks[prop], lt, Color(def))
	return Color(String(layer.get(prop, def)))

## World point -> screen point for a layer with parallax `par`.
func _w(p: Vector2, par: Vector2) -> Vector2:
	return (origin + _shake + p - _cam * par).round()

func _px() -> int:
	return maxi(1, int(tl.get("pixel", 2)))

func _snap(v: float) -> float:
	var p := float(_px())
	return floorf(v / p) * p

func _draw() -> void:
	var vp := size
	if tl.is_empty() or vp.x < 4.0:
		return
	var loc := locate(tl, t)
	var shot: Dictionary = tl["shots"][int(loc["shot"])]
	var lt := float(loc["lt"])
	var dur := float(shot["dur"])
	# camera (integer pixel pans only)
	var cam: Dictionary = shot.get("camera", {})
	var cf: Array = cam.get("from", [0, 0])
	var ct: Array = cam.get("to", [0, 0])
	var ce := ease_smooth(lt / dur) if String(cam.get("ease", "smooth")) == "smooth" else clampf(lt / dur, 0.0, 1.0)
	_cam = Vector2(lerpf(float(cf[0]), float(ct[0]), ce), lerpf(float(cf[1]), float(ct[1]), ce)).round()
	_shake = _shake_at(shot, lt)
	_gt = t
	draw_rect(Rect2(Vector2.ZERO, vp), Color.BLACK)
	for ly in shot["layers"]:
		var t0 := float(ly.get("t0", -1.0))
		var t1 := float(ly.get("t1", 1e9))
		if lt < t0 or lt > t1:
			continue
		_draw_layer(shot, ly, lt, vp)
	# flashes
	for f in shot.get("flash", []):
		var e := lt - float(f["t"])
		if e >= 0.0 and e < float(f["dur"]):
			var a := float(f["peak"]) * (1.0 - e / float(f["dur"]))
			if e < 0.06:
				a = float(f["peak"]) * e / 0.06
			var fc := Color(String(f["color"]))
			fc.a = a
			draw_rect(Rect2(Vector2.ZERO, vp), fc)
	# letterbox bars, fades, captions
	var bh := bar_height(vp, tl)
	draw_rect(Rect2(0, 0, vp.x, bh), Color.BLACK)
	draw_rect(Rect2(0, vp.y - bh, vp.x, bh), Color.BLACK)
	var fade := 0.0
	var fi := float(shot.get("fade_in", 0.5))
	var fo := float(shot.get("fade_out", 0.5))
	if fi > 0.0 and lt < fi:
		fade = maxf(fade, 1.0 - ease_smooth(lt / fi))
	if fo > 0.0 and lt > dur - fo:
		fade = maxf(fade, ease_smooth((lt - (dur - fo)) / fo))
	fade = maxf(fade, extra_black)
	if fade > 0.0:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0.01, 0.01, 0.02, fade))
	_draw_captions(shot, lt, vp, bh, fade)
	_draw_skip_hint(vp, bh)

func _shake_at(shot: Dictionary, lt: float) -> Vector2:
	var o := Vector2.ZERO
	for s in shot.get("shake", []):
		var e := lt - float(s["t"])
		if e >= 0.0 and e < float(s["dur"]):
			var env := 1.0 - e / float(s["dur"])
			var step := int(lt * 30.0)
			o += Vector2((_hash(step, 1) * 2.0 - 1.0), (_hash(step, 2) * 2.0 - 1.0)) * float(s["amp"]) * env
	return o.round()

func _draw_captions(shot: Dictionary, lt: float, vp: Vector2, bh: float, fade: float) -> void:
	for c in shot.get("captions", []):
		var e := lt - float(c["t"])
		var d := float(c["dur"])
		if e < 0.0 or e > d:
			continue
		var a := minf(clampf(e / 0.7, 0.0, 1.0), clampf((d - e) / 0.7, 0.0, 1.0))
		var col := Color(0.93, 0.89, 0.76, a * 0.92)
		var cap_rect := Rect2(0, vp.y - bh, vp.x, bh)
		UITheme.draw_text_in(self, cap_rect, String(c["text"]), 20, col, HORIZONTAL_ALIGNMENT_CENTER, false)

## Bottom-right: "hold any key to skip" text and the hold progress bar (the Skip button itself is a Button child of the screen).
func _draw_skip_hint(vp: Vector2, bh: float) -> void:
	var bar_y := vp.y - bh
	if show_prompt > 0.01:
		var r := Rect2(vp.x - 220.0, bar_y, 144.0, bh)
		UITheme.draw_text_in(self, r, "Hold any key to skip", 15, Color(0.7, 0.68, 0.6, 0.65 * show_prompt), HORIZONTAL_ALIGNMENT_RIGHT, false)
	if skip_progress > 0.0:
		var w := 144.0
		var rr := Rect2(vp.x - 220.0, bar_y + bh * 0.5 + 8.0, w, 3.0)
		draw_rect(rr, Color(0.2, 0.18, 0.12, 0.8))
		draw_rect(Rect2(rr.position, Vector2(w * clampf(skip_progress, 0.0, 1.0), rr.size.y)), Color("#e8c060"))

func _draw_layer(shot: Dictionary, ly: Dictionary, lt: float, vp: Vector2) -> void:
	match String(ly["kind"]):
		"sky": _l_sky(ly, lt, vp)
		"ground": _l_ground(ly, lt, vp)
		"scene": _l_scene(shot, ly, lt, vp)
		"image": _l_image(shot, ly, lt)
		"shell": _l_shell(ly, lt, vp)
		"eyelid": _l_eyelid(ly, lt, vp)
		"meteor": _l_meteor(ly, lt)
		"plume": _l_plume(ly, lt)
		"glow": _l_glow(ly, lt)
		"particles": _l_particles(ly, lt)
		"overlay": _l_overlay(ly, lt, vp)
		"creep": _l_creep(ly, lt)

# --- filled pixel shapes (rows of rects, one pixel unit tall)
func _pix_ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	if rx < 1.0 or ry < 1.0:
		return
	var p := float(_px())
	var yy := -ry
	while yy <= ry:
		var k := 1.0 - (yy / ry) * (yy / ry)
		if k > 0.0:
			var hw := rx * sqrt(k)
			var x0 := floorf((c.x - hw) / p) * p
			var x1 := ceilf((c.x + hw) / p) * p
			draw_rect(Rect2(x0, floorf((c.y + yy) / p) * p, x1 - x0, p), col)
		yy += p

func _l_sky(ly: Dictionary, lt: float, vp: Vector2) -> void:
	var par := _par(ly)
	var top := _colp(ly, "top", lt, "#88c0e0")
	var bot := _colp(ly, "bottom", lt, "#f0e0a0")
	var y0 := float(ly.get("y0", -467.0))
	var y1 := float(ly.get("y1", 333.0))
	var n := 44
	var bhh := (y1 - y0) / float(n)
	for i in n:
		var c := top.lerp(bot, ease_smooth(float(i) / float(n - 1)))
		var ya := _w(Vector2(0, y0 + i * bhh), par).y
		var yb := _w(Vector2(0, y0 + (i + 1) * bhh), par).y
		if i == n - 1:
			yb = vp.y + 8.0
		draw_rect(Rect2(0, ya, vp.x, maxf(yb - ya, 1.0) + 1.0), c)
	var nc := int(ly.get("clouds", 0))
	if nc > 0:
		var cc := Color(String(ly.get("cloud_col", "#ffffff")))
		cc.a = float(ly.get("cloud_alpha", 0.5))
		var yr: Array = ly.get("cloud_y", [13, 107])
		var p := float(_px())
		for i in nc:
			var wx := fposmod(_hash(i, 5) * 1000.0 - 180.0 + _gt * (2.0 + _hash(i, 6) * 3.0), 1000.0) - 180.0
			var wy := lerpf(float(yr[0]), float(yr[1]), _hash(i, 7))
			var wpx := (30.0 + _hash(i, 8) * 40.0) * p
			var sp := _w(Vector2(wx, wy), par)
			_pix_ellipse(sp, wpx, 5.0 * p, cc)
			_pix_ellipse(sp + Vector2(-wpx * 0.35, -3.0 * p), wpx * 0.55, 4.0 * p, cc)
			_pix_ellipse(sp + Vector2(wpx * 0.3, -2.0 * p), wpx * 0.5, 3.5 * p, cc)

func _l_ground(ly: Dictionary, lt: float, vp: Vector2) -> void:
	var par := _par(ly)
	var col := _colp(ly, "col", lt, "#5f8f3c")
	var col2 := _colp(ly, "col2", lt, "#548534")
	var edge := _colp(ly, "edge", lt, "#3f6a2c")
	var y := float(ly.get("y", 227.0))
	var top := _w(Vector2(0, y), par).y
	var p := float(_px())
	draw_rect(Rect2(0, top, vp.x, vp.y - top + 8.0), col)
	# perspective stripes: thin near the horizon, thicker toward the camera
	var yy := 0.0
	var i := 0
	while top + yy < vp.y + 8.0:
		var hgt := p * (1.0 + float(i) * 0.45)
		if i % 2 == 1:
			draw_rect(Rect2(0, top + yy, vp.x, hgt), col2)
		yy += hgt * 1.6 + p * 2.0
		i += 1
	draw_rect(Rect2(0, top - p, vp.x, p * 2.0), edge)

func _l_scene(shot: Dictionary, ly: Dictionary, lt: float, vp: Vector2) -> void:
	var tex: Texture2D = layer_texture(String(shot["id"]), ly)
	if tex == null:
		return
	var sc := float(ly.get("scale", 5))
	var sz := tex.get_size() * sc
	var par := _par(ly)
	var o := _w(Vector2(_num(ly, "x", lt, 0.0), _num(ly, "y", lt, 0.0)), par)
	var k0 := int(floor(-o.x / sz.x)) - 1
	var k1 := int(ceil((vp.x - o.x) / sz.x)) + 1
	for k in range(k0, k1 + 1):
		var x := o.x + k * sz.x
		if x > vp.x or x + sz.x < 0.0:
			continue
		if posmod(k, 2) == 0:
			draw_texture_rect(tex, Rect2(x, o.y, sz.x, sz.y), false)
		else:
			draw_set_transform(Vector2(x + sz.x * 0.5, 0.0), 0.0, Vector2(-1.0, 1.0))
			draw_texture_rect(tex, Rect2(-sz.x * 0.5, o.y, sz.x, sz.y), false)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _l_image(shot: Dictionary, ly: Dictionary, lt: float) -> void:
	var sid := String(shot["id"])
	var tex := layer_texture(sid, ly)
	if tex == null:
		return
	var par := _par(ly)
	var x := _num(ly, "x", lt, 0.0)
	var y := _num(ly, "y", lt, 0.0)
	# automatic hop while the sprite is moving sideways
	var hop := float(ly.get("hop", 0.0))
	if hop > 0.0 and ly.get("keys", {}).has("x"):
		var dx := _num(ly, "x", lt + 0.05, x) - _num(ly, "x", lt - 0.05, x)
		if absf(dx) > 0.4:
			y -= absf(sin(_gt * 9.0)) * hop
	var br := float(ly.get("breathe", 0.0))
	if br > 0.0:
		y -= (sin(_gt * 2.4 + x * 0.01) * 0.5 + 0.5) * br
	var jit := float(ly.get("jitter", 0.0))
	if jit > 0.0:
		var st := int(_gt * 14.0)
		x += (_hash(st, 3) * 2.0 - 1.0) * jit
	for sw in ly.get("shake_when", []):
		if absf(lt - float(sw)) < 0.22:
			var st2 := int(_gt * 30.0)
			x += (_hash(st2, 4) * 2.0 - 1.0) * 4.0
			y += (_hash(st2, 5) * 2.0 - 1.0) * 2.0
	var sc := float(ly.get("scale", 1))
	var sz := tex.get_size() * sc
	var base := _w(Vector2(x, y), par)
	var alpha := _num(ly, "alpha", lt, 1.0)
	if alpha <= 0.01:
		return
	var tint := _colp(ly, "tint", lt, "#ffffff")
	tint.a = alpha
	var flip := bool(ly.get("flip", false))
	var clip := 1e9
	if ly.has("clip_y"):
		clip = _w(Vector2(0, float(ly["clip_y"])), par).y
	_blit(tex, base, sz, sc, flip, tint, clip)
	var mix := _num(ly, "mix", lt, 0.0)
	if mix > 0.01 and ly.has("img_b"):
		var tb := layer_texture(sid, ly, bool(ly.get("infect_b", false)), true)
		if tb != null:
			var t2 := tint
			t2.a = alpha * mix
			_blit(tb, base, tb.get_size() * sc, sc, flip, t2, clip)

func _blit(tex: Texture2D, base: Vector2, sz: Vector2, sc: float, flip: bool, mod: Color, clip: float) -> void:
	var top := base.y - sz.y
	var h := sz.y
	var src_h := tex.get_size().y
	if base.y > clip:
		h = clip - top
		if h <= 0.0:
			return
		src_h = h / sc
	if flip:
		draw_set_transform(Vector2(base.x, 0.0), 0.0, Vector2(-1.0, 1.0))
		draw_texture_rect_region(tex, Rect2(-sz.x * 0.5, top, sz.x, h), Rect2(0, 0, tex.get_size().x, src_h), mod)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_texture_rect_region(tex, Rect2(base.x - sz.x * 0.5, top, sz.x, h), Rect2(0, 0, tex.get_size().x, src_h), mod)

func _l_shell(ly: Dictionary, lt: float, vp: Vector2) -> void:
	var open := clampf(_num(ly, "open", lt, 0.0), 0.0, 1.0)
	var rxr: Array = ly.get("rx", [47, 287])
	var ryr: Array = ly.get("ry", [31, 167])
	var rx := lerpf(float(rxr[0]), float(rxr[1]), open)
	var ry := lerpf(float(ryr[0]), float(ryr[1]), open)
	var cw: Array = ly.get("center", [320, 200])
	var c := _w(Vector2(float(cw[0]), float(cw[1])), _par(ly))
	var n := 44
	var pts_in: Array = []
	for i in n:
		var a := TAU * float(i) / float(n)
		var f := 1.0 + 0.06 * sin(float(i) * 2.7) + 0.045 * sin(float(i) * 5.1 + 1.0)
		pts_in.append(Vector2(cos(a) * rx * f, sin(a) * ry * f))
	var rings := [[1.0, 1.08, Color("#f0dcaa")], [1.08, 1.38, Color("#c9ab72")], [1.38, 40.0, Color("#8f7448")]]
	for rg in rings:
		for i in n:
			var j := (i + 1) % n
			var a0: Vector2 = pts_in[i]
			var a1: Vector2 = pts_in[j]
			var poly := PackedVector2Array([c + a0 * float(rg[0]), c + a1 * float(rg[0]), c + a1 * float(rg[1]), c + a0 * float(rg[1])])
			draw_colored_polygon(poly, rg[2])
	# speckles of the inside of the shell (they follow the opening hole)
	var sp := Color(0.43, 0.3, 0.16, 0.7)
	var p := float(_px())
	for k in 26:
		var a2 := _hash(k, 11) * TAU
		var m := 1.18 + _hash(k, 12) * 0.9
		var pos := c + Vector2(cos(a2) * rx * m, sin(a2) * ry * m)
		var w := (4.0 + floorf(_hash(k, 13) * 6.0)) * p
		draw_rect(Rect2(_snap(pos.x), _snap(pos.y), w, w * 0.7), sp)

func _l_eyelid(ly: Dictionary, lt: float, vp: Vector2) -> void:
	var open := clampf(_num(ly, "open", lt, 1.0), 0.0, 1.0)
	var hgt := (1.0 - open) * vp.y * 0.55
	if hgt < 1.0:
		return
	var p := float(_px())
	draw_rect(Rect2(0, 0, vp.x, hgt), Color("#140b07"))
	draw_rect(Rect2(0, vp.y - hgt, vp.x, hgt), Color("#140b07"))
	draw_rect(Rect2(0, hgt, vp.x, p), Color("#3a2416"))
	draw_rect(Rect2(0, vp.y - hgt - p, vp.x, p), Color("#3a2416"))

func _l_meteor(ly: Dictionary, lt: float) -> void:
	var t0 := float(ly["t0"])
	var t1 := float(ly["t1"])
	if lt < t0 or lt >= t1:
		return
	var par := _par(ly)
	var f: Array = ly["from"]
	var to: Array = ly["to"]
	var pr := clampf((lt - t0) / (t1 - t0), 0.0, 1.0)
	var pa := Vector2(float(f[0]), float(f[1]))
	var pb := Vector2(float(to[0]), float(to[1]))
	var head := _w(pa.lerp(pb, pr * pr * 0.35 + pr * 0.65), par)
	var dir := (pa - pb).normalized()
	var perp := Vector2(-dir.y, dir.x)
	var col := Color(String(ly.get("col", "#ffcf6a")))
	var p := float(_px())
	var tail := float(ly.get("tail", 147.0))
	var n := int(tail / p)
	for i in n:
		var fr := float(i) / float(n)
		var a := pow(1.0 - fr, 1.4)
		var c := Color("#fff4d0").lerp(col, minf(fr * 2.0, 1.0)).lerp(Color("#d8431e"), clampf((fr - 0.45) * 1.8, 0.0, 1.0))
		c.a = a
		var pos := head + dir * float(i) * p
		var wdt := 1 + int((1.0 - fr) * 3.2)
		for w in range(-wdt, wdt + 1):
			var q := pos + perp * float(w) * p * 0.8
			draw_rect(Rect2(_snap(q.x), _snap(q.y), p, p), Color(c.r, c.g, c.b, c.a * (1.0 - absf(float(w)) / float(wdt + 1) * 0.5)))
	_pix_ellipse(head, p * 11.0, p * 11.0, Color(col.r, col.g, col.b, 0.22))
	_pix_ellipse(head, p * 7.0, p * 7.0, Color(col.r, col.g, col.b, 0.4))
	_pix_ellipse(head, p * 4.0, p * 4.0, Color(1.0, 0.9, 0.6, 0.85))
	_pix_ellipse(head, p * 2.5, p * 2.5, Color.WHITE)

func _l_plume(ly: Dictionary, lt: float) -> void:
	var grow := clampf(_num(ly, "grow", lt, 1.0), 0.0, 1.0)
	if grow <= 0.01:
		return
	var par := _par(ly)
	var base := _w(Vector2(float(ly["x"]), float(ly["y"])), par)
	var h := float(ly.get("h", 200.0)) * grow
	var w := float(ly.get("w", 47.0))
	var c0 := Color(String(ly.get("col", "#3c3040")))
	var c1 := Color(String(ly.get("col2", "#8a7468")))
	var n := 24
	for k in n:
		var i := n - 1 - k                   # top puffs first, the base puffs overlap them
		var f := float(i) / float(n - 1)
		var sway := sin(_gt * 0.8 + f * 5.0 + float(i)) * w * 0.35 * f + f * f * w * 1.7
		var r := (w * 0.45 + f * w * 0.75) * (0.55 + 0.45 * grow)
		var pos := base + Vector2(sway, -f * h)
		var col := c0.lerp(c1, f)
		col.a = 0.92 * (1.0 - f * 0.45)
		_pix_ellipse(pos, r, r * 0.8, col)
		_pix_ellipse(pos + Vector2(r * 0.55, -r * 0.2), r * 0.6, r * 0.5, col.lightened(0.08))

func _l_glow(ly: Dictionary, lt: float) -> void:
	var a := _num(ly, "alpha", lt, 1.0)
	if a <= 0.01:
		return
	var par := _par(ly)
	var c := _w(Vector2(float(ly["x"]), float(ly["y"])), par)
	var r := float(ly.get("r", 67.0))
	var col := Color(String(ly.get("col", "#ff8a3a")))
	var flat := float(ly.get("flat", 0.6))
	for k in 6:
		var rr := r * (1.0 - float(k) * 0.16)
		_pix_ellipse(c, rr, rr * flat, Color(col.r, col.g, col.b, 0.15 * a))

func _l_particles(ly: Dictionary, lt: float) -> void:
	var rr: Array = ly["rect"]
	var rect := Rect2(float(rr[0]), float(rr[1]), float(rr[2]), float(rr[3]))
	var n := int(ly.get("n", 20))
	var col := Color(String(ly.get("color", "#ffffff")))
	var sz := float(ly.get("size", 2))
	var spd: Array = ly.get("speed", [0, -7])
	var par := _par(ly)
	var mode := String(ly.get("mode", "motes"))
	var t0 := float(ly.get("t0", 0.0))
	var ramp := clampf((lt - t0) / 1.0, 0.0, 1.0)
	var life := 12.0 if mode == "motes" else (2.4 if mode == "embers" else 8.0)
	for i in n:
		var h1 := _hash(i, 21)
		var h2 := _hash(i, 22)
		var ph := fposmod(lt / life + h1, 1.0)
		var a := sin(PI * ph) * ramp
		var wp: Vector2
		if mode == "motes":
			wp = Vector2(rect.position.x + fposmod(h2 * rect.size.x + float(spd[0]) * lt, rect.size.x),
				rect.position.y + fposmod(h1 * rect.size.y + float(spd[1]) * lt, rect.size.y))
			wp.x += sin(lt * 0.9 + float(i)) * 10.0
		else:
			var life_t := ph * life
			wp = Vector2(rect.position.x + h2 * rect.size.x + float(spd[0]) * life_t + sin(lt * 1.3 + float(i)) * 6.0,
				rect.position.y + _hash(i, 23) * rect.size.y + float(spd[1]) * life_t)
		var sp := _w(wp, par)
		var c := col
		c.a = col.a * a * 0.9
		draw_rect(Rect2(_snap(sp.x), _snap(sp.y), sz, sz), c)
		if mode != "motes" and i % 3 == 0:
			c.a *= 0.5
			draw_rect(Rect2(_snap(sp.x) + sz, _snap(sp.y), sz, sz), c)

func _l_overlay(ly: Dictionary, lt: float, vp: Vector2) -> void:
	var a := _num(ly, "alpha", lt, 0.3)
	if a <= 0.005:
		return
	var col := Color(String(ly.get("color", "#000000")))
	if String(ly.get("mode", "")) == "vignette":
		var th := vp.y * 0.045
		for k in 9:
			var c := Color(col.r, col.g, col.b, a * (1.0 - float(k) / 9.0) * 0.6)
			var ins := float(k) * th
			draw_rect(Rect2(0, ins, vp.x, th), c)
			draw_rect(Rect2(0, vp.y - ins - th, vp.x, th), c)
			draw_rect(Rect2(ins, 0, th, vp.y), c)
			draw_rect(Rect2(vp.x - ins - th, 0, th, vp.y), c)
		return
	col.a = a
	draw_rect(Rect2(Vector2.ZERO, vp), col)

func _l_creep(ly: Dictionary, lt: float) -> void:
	var r := clampf(_num(ly, "r", lt, 0.0), 0.0, 1.0)
	if r <= 0.01:
		return
	var par := _par(ly)
	var c := _w(Vector2(float(ly["x"]), float(ly["y"])), par)
	var rx := float(ly.get("max", 533.0)) * r
	var ry := rx * 0.14
	var col := Color(String(ly.get("col", "#8a3fd0")))
	_pix_ellipse(c, rx, ry, Color(col.r, col.g, col.b, 0.38))
	_pix_ellipse(c, rx * 0.75, ry * 0.7, Color(col.r * 0.6, col.g * 0.5, col.b * 0.8, 0.4))
	var p := float(_px())
	for i in 40:
		var a := _hash(i, 31) * TAU
		var d := sqrt(_hash(i, 32))
		var pos := c + Vector2(cos(a) * rx * d, sin(a) * ry * d * 0.9)
		var blink := 0.5 + 0.5 * sin(_gt * 2.0 + float(i) * 1.7)
		draw_rect(Rect2(_snap(pos.x), _snap(pos.y), p, p), Color(0.85, 0.6, 1.0, 0.55 * blink))
