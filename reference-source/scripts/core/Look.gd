class_name Look
extends RefCounted
## Character customization ("look"): skin colour, pattern, pattern colour, gender (cosmetic only).
## A look is {"species","skin","pattern","pcolor","gender"}. All options live in data/customization.json.
## Looks never touch RunState's RNG or any stat: they only recolour sprites (apply()).

static func cfg(species_id: String) -> Dictionary:
	return DB.table("customization").get(species_id, {})

static func default_look(species_id: String) -> Dictionary:
	var d: Dictionary = cfg(species_id).get("defaults", {"skin": "classic", "pattern": "solid", "pcolor": "cream", "gender": "male"})
	var l := d.duplicate()
	l["species"] = species_id
	return l

static func _ids(species_id: String, group: String) -> Array:
	var out: Array = []
	for o in cfg(species_id).get(group, []):
		out.append(String(o["id"]))
	return out

static func option(species_id: String, group: String, id: String) -> Dictionary:
	for o in cfg(species_id).get(group, []):
		if String(o["id"]) == id:
			return o
	return {}

## Every field set to a valid option (unknown ids fall back to the species default).
static func sanitize(look: Dictionary, species_id: String) -> Dictionary:
	var l := default_look(species_id)
	for pair in [["skin", "skins"], ["pattern", "patterns"], ["pcolor", "pcolors"], ["gender", "genders"]]:
		var v := String(look.get(pair[0], l[pair[0]]))
		if v in _ids(species_id, pair[1]):
			l[pair[0]] = v
	return l

static func random_look(species_id: String, rng: RandomNumberGenerator) -> Dictionary:
	var l := default_look(species_id)
	for pair in [["skin", "skins"], ["pattern", "patterns"], ["pcolor", "pcolors"], ["gender", "genders"]]:
		var ids := _ids(species_id, pair[1])
		if not ids.is_empty():
			l[pair[0]] = ids[rng.randi_range(0, ids.size() - 1)]
	return l

static func is_default(look: Dictionary) -> bool:
	if look.is_empty():
		return true
	var sid := String(look.get("species", ""))
	var d := default_look(sid)
	for k in ["skin", "pattern", "gender"]:
		if String(look.get(k, d[k])) != String(d[k]):
			return false
	return true

## Stable text key (texture cache + tests).
static func sig(look: Dictionary) -> String:
	if is_default(look):
		return ""
	return "%s|%s|%s|%s|%s" % [look.get("species", ""), look.get("skin", ""), look.get("pattern", ""), look.get("pcolor", ""), look.get("gender", "")]

## Does this look recolour that sprite id?
static func applies(sprite_id: String, look: Dictionary) -> bool:
	if is_default(look):
		return false
	return cfg(String(look.get("species", ""))).get("sprites", {}).has(sprite_id)

static func color_of(species_id: String, group: String, id: String) -> Color:
	var o := option(species_id, group, id)
	if o.is_empty() or o.get("color", null) == null:
		return Color(0, 0, 0, 0)
	return Color.html(String(o["color"]))

## A readable one-line description ("Azure, Stripes (Gold), Female").
static func describe(look: Dictionary) -> String:
	var sid := String(look.get("species", ""))
	var l := sanitize(look, sid)
	var s := String(option(sid, "skins", l["skin"]).get("name", l["skin"]))
	var p := String(option(sid, "patterns", l["pattern"]).get("name", l["pattern"]))
	if l["pattern"] != "solid":
		p += " (%s)" % String(option(sid, "pcolors", l["pcolor"]).get("name", l["pcolor"]))
	return "%s, %s, %s" % [s, p, String(option(sid, "genders", l["gender"]).get("name", l["gender"]))]

# ------------------------------------------------------------------ recolouring

static func _is_crest(h: float, s: float, v: float) -> bool:
	return (h <= 45.0 or h >= 335.0) and s >= 0.45 and v >= 0.2 and v < 0.88

static func _pattern_hit(pat: Dictionary, x: int, y: int, seed_v: int) -> bool:
	match String(pat.get("kind", "none")):
		"stripes":
			var period := int(pat.get("period", 6))
			return posmod(x + (y >> 1) + seed_v % period, period) < int(pat.get("width", 2))
		"spots":
			var cell := int(pat.get("cell", 5))
			var cx := x / cell
			var cy := y / cell
			var hh := RunState.mix(RunState.mix(cx * 7 + 3 + seed_v, cy * 13 + 5), 17)
			if float(posmod(hh, 100)) / 100.0 >= float(pat.get("density", 0.75)):
				return false
			var px := float(cx * cell) + 1.0 + float(posmod(hh >> 7, cell - 2))
			var py := float(cy * cell) + 1.0 + float(posmod(hh >> 13, cell - 2))
			return Vector2(float(x) + 0.5 - px, float(y) + 0.5 - py).length() <= float(pat.get("radius", 1.7))
		"mottled":
			var cell2 := int(pat.get("cell", 2))
			var hv := RunState.mix(RunState.mix((x / cell2) * 11 + seed_v, (y / cell2) * 5 + 9), 29)
			return float(posmod(hv, 100)) / 100.0 < float(pat.get("density", 0.36))
	return false

## Background of a portrait: pixels identical to the reference background image (sd.bg_ref, a clean copy of the dithered
## gradient: assets/sprites/portrait_bg_raptor.png; transparent where every portrait has creature pixels).
static func _bg_mask(img: Image, bg_ref: String) -> PackedByteArray:
	var w := img.get_width()
	var h := img.get_height()
	var mask := PackedByteArray()
	mask.resize(w * h)
	var path := "res://assets/sprites/%s.png" % bg_ref
	if bg_ref == "" or not ResourceLoader.exists(path):
		return mask
	var ref: Image = (load(path) as Texture2D).get_image()
	if ref.get_width() != w or ref.get_height() != h:
		return mask
	for y in h:
		for x in w:
			var rc := ref.get_pixel(x, y)
			if rc.a > 0.5 and rc.is_equal_approx(img.get_pixel(x, y)):
				mask[y * w + x] = 1
	return mask

## Returns a recoloured copy of `src` (a sprite listed in data/customization.json) for `look`.
static func apply(src: Image, sprite_id: String, look: Dictionary) -> Image:
	var sid := String(look.get("species", ""))
	var conf: Dictionary = cfg(sid)
	var sd: Dictionary = conf.get("sprites", {}).get(sprite_id, {})
	if sd.is_empty() or is_default(look):
		return src
	var l := sanitize(look, sid)
	if String(sd.get("mode", "")) == "brown":
		return _apply_brown(src, sd, sid, l, conf)
	var img: Image = src.duplicate()
	var w := img.get_width()
	var h := img.get_height()
	var lo := float(sd["skin_hue"][0])
	var hi := float(sd["skin_hue"][1])
	var bg := PackedByteArray()
	if bool(sd.get("portrait", false)):
		bg = _bg_mask(img, String(sd.get("bg_ref", "")))
	var skin_col := color_of(sid, "skins", l["skin"])
	var pat: Dictionary = option(sid, "patterns", l["pattern"])
	var pat_col := color_of(sid, "pcolors", l["pcolor"])
	var gen: Dictionary = option(sid, "genders", l["gender"])
	var tone := float(conf.get("stage_tone", {}).get(String(sd.get("stage", "")), 1.0))
	# pass 1: classify, mean value/saturation of the skin (the reference mid-tone)
	var role := PackedByteArray()   # 0 other, 1 skin, 2 crest
	role.resize(w * h)
	var sv := 0.0
	var ss := 0.0
	var n := 0
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a < 0.5 or (not bg.is_empty() and bg[y * w + x] != 0):
				continue
			var hue := c.h * 360.0
			if _is_crest(hue, c.s, c.v):
				role[y * w + x] = 2
			elif c.s >= 0.18 and c.v < 0.9 and hue >= lo and hue <= hi:
				role[y * w + x] = 1
				sv += c.v
				ss += c.s
				n += 1
	var vref := sv / float(maxi(1, n))
	var sref := ss / float(maxi(1, n))
	var seed_v := RunState.mix(sprite_id.length() * 31, 7)
	var crest_s := float(gen.get("crest_sat", 1.0))
	var crest_v := float(gen.get("crest_val", 1.0))
	var crest_l := float(gen.get("crest_lift", 0.0))
	for y in h:
		for x in w:
			var r := role[y * w + x]
			if r == 0:
				continue
			var c := img.get_pixel(x, y)
			if r == 2:
				var cs := clampf(c.s * crest_s, 0.0, 1.0)
				var cv := clampf(c.v * crest_v + crest_l * c.v, 0.0, 1.0)
				img.set_pixel(x, y, Color.from_hsv(c.h, cs, cv, c.a))
				continue
			var target := skin_col
			if skin_col.a <= 0.0:
				target = Color.from_hsv(c.h, c.s, c.v)   # "classic": keep the original skin, patterns still apply
			var use_pat := not pat.is_empty() and String(pat.get("kind", "none")) != "none" and _pattern_hit(pat, x, y, seed_v)
			if use_pat:
				target = pat_col
			if skin_col.a <= 0.0 and not use_pat:
				continue
			var ratio := c.v / maxf(0.05, vref)
			var nv := clampf(target.v * ratio * tone, 0.02, 1.0)
			var ns := clampf(target.s * (c.s / maxf(0.05, sref)), 0.0, 1.0)
			if use_pat and pat_col.s < 0.2:
				ns = target.s   # pale pattern colours stay pale
			img.set_pixel(x, y, Color.from_hsv(target.h, ns, nv, c.a))
	return img

# Palette regions of the designer raptor art (brown body, navy back stripe, tan belly, orange eye, near-black outline / claws):
const R_NONE := 0      # outline, claws, eye, background: never recoloured
const R_BODY := 1
const R_STRIPE := 2    # the dorsal stripe = the "crest" (gender: female = paler, softer)
const R_BELLY := 3

static func region_of(c: Color, y: int, h: int) -> int:
	var hue := c.h * 360.0
	if c.v < 0.17:
		return R_NONE                                    # outline
	if c.v >= 0.7 and c.s >= 0.74 and hue >= 15.0 and hue <= 55.0:
		return R_NONE                                    # the orange eye
	if c.s < 0.34 and c.v < 0.58:
		if y > int(float(h) * 0.84):
			return R_NONE                                # claws are the same grey-navy as the stripe: keep them
		return R_STRIPE
	if hue >= 215.0 and hue <= 300.0 and c.v < 0.6:
		return R_STRIPE
	if c.v >= 0.7 and c.s >= 0.25 and c.s <= 0.66 and hue >= 24.0 and hue <= 48.0:
		return R_BELLY
	if hue <= 40.0 or hue >= 340.0:
		if c.s >= 0.3:
			return R_BODY
	return R_NONE

## Recolour for the designer raptor sprites (mode "brown"): body / stripe / belly regions are re-hued, patterns overlay the BODY only,
## eye + outline + claws are untouched. "Classic" keeps the original brown (patterns / gender still apply).
static func _apply_brown(src: Image, sd: Dictionary, sid: String, l: Dictionary, conf: Dictionary) -> Image:
	var img: Image = src.duplicate()
	var w := img.get_width()
	var h := img.get_height()
	var bg := PackedByteArray()
	if bool(sd.get("portrait", false)):
		bg = _bg_mask(img, String(sd.get("bg_ref", "")))
	var skin_col := color_of(sid, "skins", l["skin"])
	var pat: Dictionary = option(sid, "patterns", l["pattern"])
	var pat_col := color_of(sid, "pcolors", l["pcolor"])
	var gen: Dictionary = option(sid, "genders", l["gender"])
	var tone := float(conf.get("stage_tone", {}).get(String(sd.get("stage", "")), 1.0))
	tone = lerpf(1.0, tone, 0.5)                          # the brown art is already stage-neutral: a gentler stage tint
	var role := PackedByteArray()
	role.resize(w * h)
	var bv := 0.0
	var bs := 0.0
	var bn := 0
	var lv := 0.0
	var ln := 0
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a < 0.5 or (not bg.is_empty() and bg[y * w + x] != 0):
				continue
			var r := region_of(c, y, h)
			role[y * w + x] = r
			if r == R_BODY:
				bv += c.v
				bs += c.s
				bn += 1
			elif r == R_BELLY:
				lv += c.v
				ln += 1
	var vref := bv / float(maxi(1, bn))
	var sref := bs / float(maxi(1, bn))
	var lref := lv / float(maxi(1, ln))
	var seed_v := RunState.mix(String(sd.get("stage", "x")).length() * 31, 7)
	var classic := skin_col.a <= 0.0
	var st_s := float(gen.get("crest_sat", 1.0))
	var st_v := float(gen.get("crest_val", 1.0))
	var st_l := float(gen.get("crest_lift", 0.0))
	for y in h:
		for x in w:
			var r := role[y * w + x]
			if r == R_NONE:
				continue
			var c := img.get_pixel(x, y)
			if r == R_STRIPE:
				if classic and st_s == 1.0 and st_v == 1.0 and st_l == 0.0:
					continue
				var o := c
				if not classic:
					o = Color.from_hsv(skin_col.h, clampf(skin_col.s * 0.42, 0.0, 1.0), clampf(c.v * (0.55 + 0.6 * skin_col.v) * tone, 0.05, 1.0), c.a)
				o = Color.from_hsv(o.h, clampf(o.s * st_s, 0.0, 1.0), clampf(o.v * st_v + st_l * o.v, 0.0, 1.0), c.a)
				img.set_pixel(x, y, o)
				continue
			if r == R_BELLY:
				if not classic:
					var bt := clampf(c.v / maxf(0.05, lref), 0.5, 1.3)
					img.set_pixel(x, y, Color.from_hsv(skin_col.h, clampf(skin_col.s * 0.42, 0.0, 1.0), clampf((0.55 + 0.45 * skin_col.v) * bt * 0.92 * tone, 0.05, 1.0), c.a))
				continue
			# body: skin colour (or pattern colour on pattern pixels), keeping the art's shading
			var target := skin_col
			if classic:
				target = Color.from_hsv(c.h, c.s, c.v)
			var use_pat := not pat.is_empty() and String(pat.get("kind", "none")) != "none" and _pattern_hit(pat, x, y, seed_v)
			if use_pat:
				target = pat_col
			if classic and not use_pat:
				continue
			var ratio := c.v / maxf(0.05, vref)
			var nv := clampf(target.v * ratio * tone, 0.02, 1.0)
			var ns := clampf(target.s * (c.s / maxf(0.05, sref)), 0.0, 1.0)
			if use_pat and pat_col.s < 0.2:
				ns = target.s
			img.set_pixel(x, y, Color.from_hsv(target.h, ns, nv, c.a))
	return img

## Copy of a portrait with its background painted `col` (the egg preview shows the head against the dark inside of the shell).
static func fill_bg(img: Image, sprite_id: String, species_id: String, col: Color) -> Image:
	var sd: Dictionary = cfg(species_id).get("sprites", {}).get(sprite_id, {})
	var out: Image = img.duplicate()
	var bg := _bg_mask(out, String(sd.get("bg_ref", "")))
	for y in out.get_height():
		for x in out.get_width():
			if bg[y * out.get_width() + x] != 0:
				out.set_pixel(x, y, col)
	return out
