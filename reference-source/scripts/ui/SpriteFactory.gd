class_name SpriteFactory
extends RefCounted
## Placeholder pixel art generated from data/sprites.json (shape lists) and tiles.json palettes.
## To use real art: drop assets/sprites/<sprite_id>.png (any size, nearest filtered). It overrides the
## procedural sprite automatically. Tiles: assets/sprites/tile_<tile>_<variant>.png (16x16).

static var _cache: Dictionary = {}

## The current run's look (set by Game.start_run / the customization screen). Sprites listed in data/customization.json are
## recoloured with it everywhere (board, HUD portrait, turn order, deck...), so the look carries through every growth stage.
static var look: Dictionary = {}

static func set_look(l: Dictionary) -> void:
	look = l

static func get_texture(id: String, infected: bool = false) -> Texture2D:
	return looked(id, look, infected)

## Texture of sprite `id` wearing `lk` (an empty / default look = the original art).
static func looked(id: String, lk: Dictionary, infected: bool = false) -> Texture2D:
	var sg := Look.sig(lk) if Look.applies(id, lk) else ""
	var key := "%s|%s|%s" % [id, infected, sg]
	if _cache.has(key):
		return _cache[key]
	var tex: Texture2D = null
	var override_path := "res://assets/sprites/%s.png" % id
	if ResourceLoader.exists(override_path):
		tex = load(override_path)
		if tex != null and (infected or sg != ""):
			var src: Image = (tex as Texture2D).get_image()
			if src != null:
				if sg != "":
					src = Look.apply(src, id, lk)
				tex = ImageTexture.create_from_image(make_infected(src) if infected else src)
	if tex == null:
		var def := DB.sprite_def(id)
		if def.is_empty():
			tex = ImageTexture.create_from_image(_fallback())
		else:
			var img := paint(def)
			if sg != "":
				img = Look.apply(img, id, lk)
			if infected:
				img = make_infected(img)
			tex = ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

static func _fallback() -> Image:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 0, 1, 1))
	return img

static func _shade(c: Color, amt: float) -> Color:
	if amt >= 0.0:
		return c.lerp(Color.WHITE, amt)
	return c.lerp(Color.BLACK, -amt)

## Rasterise a sprite definition. Public so tools/tests can call it.
static func paint(def: Dictionary) -> Image:
	var gridn := int(def["grid"])
	var size := int(def["size"])
	var scale := float(size) / float(gridn)
	var creature: bool = String(def.get("style", "creature")) == "creature"
	var pal := {}
	for k in def["palette"]:
		pal[k] = Color.html(String(def["palette"][k]))
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var colors: Array = []   # [y][x] -> Color or null
	for y in size:
		var row := []
		row.resize(size)
		colors.append(row)
	for shape in def["shapes"]:
		var mask := _mask(shape, size, scale)
		var col: Color = pal.get(String(shape[shape.size() - 1]), Color.MAGENTA)
		var shaded: bool = creature and String(shape[0]) in ["ell", "rect"]
		for y in size:
			for x in size:
				if not mask[y][x]:
					continue
				var c := col
				if shaded:
					var above: bool = y > 0 and mask[y - 1][x]
					var below: bool = y < size - 1 and mask[y + 1][x]
					if not above:
						c = _shade(col, 0.22)
					elif not below:
						c = _shade(col, -0.28)
				colors[y][x] = c
	var outline := Color.html(String(def.get("outline_col", "#1c1418")))
	for y in size:
		for x in size:
			if colors[y][x] != null:
				img.set_pixel(x, y, colors[y][x])
	if creature:
		for y in size:
			for x in size:
				if colors[y][x] != null:
					continue
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx: int = x + d.x
					var ny: int = y + d.y
					if nx >= 0 and ny >= 0 and nx < size and ny < size and colors[ny][nx] != null:
						img.set_pixel(x, y, outline)
						break
	return img

static func _mask(shape: Array, size: int, scale: float) -> Array:
	var m := []
	for y in size:
		var row := []
		row.resize(size)
		row.fill(false)
		m.append(row)
	match String(shape[0]):
		"ell":
			var cx := (float(shape[1]) + 0.5) * scale
			var cy := (float(shape[2]) + 0.5) * scale
			var rx := (float(shape[3]) + 0.5) * scale
			var ry := (float(shape[4]) + 0.5) * scale
			for y in size:
				for x in size:
					var dx := (x + 0.5 - cx) / rx
					var dy := (y + 0.5 - cy) / ry
					if dx * dx + dy * dy <= 1.0:
						m[y][x] = true
		"rect":
			var x0 := int(floor(float(shape[1]) * scale))
			var y0 := int(floor(float(shape[2]) * scale))
			var x1 := int(floor((float(shape[1]) + float(shape[3])) * scale))
			var y1 := int(floor((float(shape[2]) + float(shape[4])) * scale))
			for y in range(maxi(0, y0), mini(size, y1)):
				for x in range(maxi(0, x0), mini(size, x1)):
					m[y][x] = true
		"px":
			var x0 := int(floor(float(shape[1]) * scale))
			var y0 := int(floor(float(shape[2]) * scale))
			var x1 := maxi(x0 + 1, int(floor((float(shape[1]) + 1.0) * scale)))
			var y1 := maxi(y0 + 1, int(floor((float(shape[2]) + 1.0) * scale)))
			for y in range(maxi(0, y0), mini(size, y1)):
				for x in range(maxi(0, x0), mini(size, x1)):
					m[y][x] = true
		"line":
			var a := Vector2((float(shape[1]) + 0.5) * scale, (float(shape[2]) + 0.5) * scale)
			var b := Vector2((float(shape[3]) + 0.5) * scale, (float(shape[4]) + 0.5) * scale)
			var hw := maxf(0.5, scale * 0.5)
			for y in size:
				for x in size:
					var p := Vector2(x + 0.5, y + 0.5)
					var cp := Geometry2D.get_closest_point_to_segment(p, a, b)
					if p.distance_to(cp) <= hw:
						m[y][x] = true
	return m

static func make_infected(src: Image) -> Image:
	var img: Image = src.duplicate()
	var tint := Color.html("#8a3fb8")
	var glow := Color.html("#8dff6a")
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			if (x * 7 + y * 13) % 17 == 0:
				img.set_pixel(x, y, glow)
			else:
				img.set_pixel(x, y, c.lerp(tint, 0.4))
	return img

# ------------------------------------------------------------------ tiles

static func _h(a: int, b: int, c: int) -> int:
	return RunState.mix(RunState.mix(a * 31 + 7, b * 17 + 3), c * 13 + 1)

## Loads res://assets/sprites/<name>.png if present (cached), else null.
static func png(name: String) -> Texture2D:
	var sg := Look.sig(look) if Look.applies(name, look) else ""
	var key := "png|" + name + "|" + sg
	if _cache.has(key):
		return _cache[key]
	var tex: Texture2D = null
	var path := "res://assets/sprites/%s.png" % name
	if ResourceLoader.exists(path):
		tex = load(path)
		if tex != null and sg != "":
			var src: Image = (tex as Texture2D).get_image()
			if src != null:
				tex = ImageTexture.create_from_image(Look.apply(src, name, look))
	_cache[key] = tex
	return tex

## Creature texture for the facing: `back` = facing away from the camera (NE/NW). Falls back to the front sprite.
static func creature(id: String, back: bool, infected: bool = false) -> Texture2D:
	if back and png(id + "_b") != null:
		return get_texture(id + "_b", infected)
	return get_texture(id, infected)

## Per-facing art (designer raptor: raptor_<stage> = SE, _sw, _b = NE, _nw): sprite-name suffix for a grid facing.
const FACE_SUFFIX := {Vector2i(1, 0): "", Vector2i(0, 1): "_sw", Vector2i(-1, 0): "_nw", Vector2i(0, -1): "_b"}

## Does this sprite have its OWN art for the facing (so the board must not mirror another pose)? SE / NE never mirror anyway.
static func has_facing_art(id: String, f: Vector2i) -> bool:
	if f == Vector2i(0, 1) or f == Vector2i(-1, 0):
		return png(id + String(FACE_SUFFIX[f])) != null
	return false

## Texture for a grid facing: the dedicated pose if it exists, else the front / back sprite (the board mirrors SW / NW itself).
static func creature_facing(id: String, f: Vector2i, infected: bool = false) -> Texture2D:
	if has_facing_art(id, f):
		return get_texture(id + String(FACE_SUFFIX[f]), infected)
	return creature(id, f == Vector2i(-1, 0) or f == Vector2i(0, -1), infected)

## Isometric ground tile (76x38 diamond). `tile` is the logic tile: ground | grass (tall-grass base) | water | obstacle.
## Theme-driven (data/themes.json): variants/frames counts come from the theme; falls back to the legacy square art.
static func tile_texture(tile: String, theme: String, variant: int, frame: int = 0) -> Texture2D:
	var th := DB.theme(theme)
	var name := ""
	match tile:
		"water":
			name = "tile_%s_water_%d_%d" % [theme, variant % int(th.get("water_variants", 1)), frame % int(th.get("water_frames", 1))]
		"grass":
			name = "tile_%s_tall_%d" % [theme, variant % int(th.get("tall_variants", 1))]
		_:
			name = "tile_%s_ground_%d" % [theme, variant % int(th.get("ground_variants", 1))]
	var t := png(name)
	if t != null:
		return t
	var key := "tile|%s|%s|%d|%d" % [tile, theme, variant, frame]
	if _cache.has(key):
		return _cache[key]
	var tex: Texture2D = ImageTexture.create_from_image(_paint_tile(tile, theme, variant, frame))
	_cache[key] = tex
	return tex

## Standing props drawn over a tile (obstacles, tall-grass tufts). Image bottom = the tile's bottom corner.
## `border` = the arena surroundings (may use the tall trees); otherwise an obstacle on the board (no big trees that would hide units).
static func prop_texture(kind: String, theme: String, variant: int, front: bool = false, border: bool = true) -> Texture2D:
	var th := DB.theme(theme)
	match kind:
		"obstacle":
			var n := int(th.get("obstacle_variants", 1))
			var pool: Array = th.get("obstacle_pool" if border else "obstacle_pool_interior", [])
			var idx := variant % n
			if not pool.is_empty():
				idx = int(pool[variant % pool.size()]) % n
			return png("prop_%s_obstacle_%d" % [theme, idx])
		"tallgrass":
			var n := int(th.get("tallgrass_variants", 1))
			return png("prop_%s_tallgrass%s_%d" % [theme, "_front" if front else "", variant % n])
	return null

## Small ground decoration (mushrooms, pebbles, flowers...) named in themes.json `decor_ring` / `decor_interior`.
static func deco_texture(theme: String, variant: int, list_key: String) -> Texture2D:
	var ids: Array = DB.theme(theme).get(list_key, [])
	if ids.is_empty():
		return null
	return png(String(ids[variant % ids.size()]))

static func backdrop(theme: String, variant: int, foreground: bool = false) -> Texture2D:
	var th := DB.theme(theme)
	return png("%s_%s_%d" % ["fg" if foreground else "bg", theme, variant % int(th.get("bg_variants", 1))])

static func _paint_tile(tile: String, theme: String, variant: int, frame: int) -> Image:
	var themes: Dictionary = DB.table("tiles")["themes"]
	var pal: Dictionary = themes.get(theme, themes["jungle"])
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var gc: Array = pal["ground"]
	var g0 := Color.html(gc[0])
	var g1 := Color.html(gc[1])
	var g2 := Color.html(gc[2])
	# ground base for every tile type
	for y in 16:
		for x in 16:
			var h := _h(x, y, variant + 5)
			var c := g0
			if h % 9 == 0:
				c = g1
			elif h % 13 == 0:
				c = g2
			img.set_pixel(x, y, c)
	match tile:
		"grass":
			var cc: Array = pal["grass"]
			var c0 := Color.html(cc[0])
			var c1 := Color.html(cc[1])
			var c2 := Color.html(cc[2])
			for y in 16:
				for x in 16:
					img.set_pixel(x, y, c1 if _h(x, y, variant + 9) % 5 != 0 else c0)
			for i in 7:
				var bx := _h(i, variant, 3) % 14 + 1
				var bh := 5 + _h(i, variant, 4) % 6
				var base_y := 14 - (_h(i, variant, 5) % 5)
				for k in bh:
					var yy := base_y - k
					if yy < 0:
						break
					img.set_pixel(bx, yy, c2 if k >= bh - 2 else c0)
					if k > 1 and k < bh - 2 and bx + 1 < 16:
						img.set_pixel(bx + 1, yy, c1)
		"water":
			var wc: Array = pal["water"]
			var w0 := Color.html(wc[0])
			var w1 := Color.html(wc[1])
			var w2 := Color.html(wc[2])
			for y in 16:
				for x in 16:
					img.set_pixel(x, y, w0 if (y / 4) % 2 == 0 else w1)
			for i in 3:
				var ry := (_h(i, variant, 11) % 14 + 1 + frame * 2) % 16
				var rx := _h(i, variant, 12) % 8
				for k in 5:
					if rx + k < 16:
						img.set_pixel(rx + k, ry, w2)
		"obstacle":
			var oc: Array = pal["obstacle"]
			var rock := {"grid": 16, "size": 16, "style": "creature", "outline_col": "#1c1c24", "palette": {"a": oc[0], "b": oc[1], "c": oc[2]}}
			match variant % 3:
				0:
					rock["shapes"] = [["ell", 8, 9, 6, 5, "a"], ["ell", 6, 7, 3, 2, "c"], ["px", 10, 8, "b"], ["px", 9, 10, "b"]]
				1:
					rock["shapes"] = [["ell", 5, 10, 4, 4, "a"], ["ell", 11, 8, 4, 6, "a"], ["ell", 11, 5, 2, 2, "c"], ["px", 4, 8, "c"]]
				_:
					rock["shapes"] = [["rect", 4, 4, 8, 10, "b"], ["ell", 8, 4, 4, 2, "c"], ["line", 6, 6, 6, 12, "a"], ["line", 10, 7, 10, 12, "a"]]
			var rimg := paint(rock)
			for y in 16:
				for x in 16:
					var c := rimg.get_pixel(x, y)
					if c.a > 0.5:
						img.set_pixel(x, y, c)
	return img

static func theme_bg(theme: String) -> Color:
	var themes: Dictionary = DB.table("tiles")["themes"]
	return Color.html(String(themes.get(theme, themes["jungle"])["bg"]))
