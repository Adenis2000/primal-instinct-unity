class_name Iso
extends RefCounted
## Isometric (2:1 diamond) projection for the battle board. Grid logic stays square; only rendering/picking use this.
##   screen = ORIGIN + ((gx - gy) * TW/2, (gx + gy) * TH/2)
## Grid +x points down-right (SE), +y down-left (SW). `g` is a (possibly fractional) grid position where an
## integer tile p covers [p, p+1); the CENTER of tile p is p + (0.5, 0.5). Units/props are always placed at
## center(p) (or the same for tweened vis_pos), so what you see, hover and click are the same tile.

const BASE_TW := 32
const BASE_TH := 16
const DEFAULT_ORIGIN := Vector2(320, 40)
## Camera. `zoom` is one of data/arenas.json camera.zoom_steps (WHOLE numbers only: 1 = one art pixel per canvas pixel, 2, 3 = zoomed in; the canvas is 640x360 and the window scales it by whole numbers too); `origin` is the screen
## position of grid corner (0,0): the top corner of the board diamond. fit()/reset() set both; everything (tiles, sprites, picking)
## goes through to_screen/to_grid, so units stay exactly on their tiles at every zoom and arena size.
static var zoom: float = 1.0
static var origin: Vector2 = DEFAULT_ORIGIN
static var extra_h: float = 0.0     # extra view height on tall displays (0 on the fixed 640x360 canvas)
static var extra_w: float = 0.0     # extra view width on wide displays (0 on the fixed 640x360 canvas): bigger arenas may stay at a closer zoom
static var TW: float = 32.0
static var TH: float = 16.0

static func reset() -> void:
	zoom = 1.0
	extra_w = 0.0
	extra_h = 0.0
	origin = DEFAULT_ORIGIN
	TW = BASE_TW
	TH = BASE_TH

static func set_zoom(z: float) -> void:
	zoom = z
	TW = BASE_TW * z
	TH = BASE_TH * z

## Screen size of the w x h board diamond at zoom z.
static func board_size(w: int, h: int, z: float) -> Vector2:
	return Vector2((w + h) * BASE_TW * 0.5 * z, (w + h) * BASE_TH * 0.5 * z)

## Largest zoom step whose board fits the view band (x, y, w, h from data/arenas.json camera.view).
static func auto_zoom(w: int, h: int) -> float:
	var cam: Dictionary = DB.table("arenas")["camera"]
	var v: Array = cam["view"]
	for z in cam["zoom_steps"]:
		var bs := board_size(w, h, float(z))
		if bs.x <= float(v[2]) + extra_w and bs.y <= float(v[3]) + extra_h:
			return float(z)
	return float(cam["zoom_steps"].back())

## Smallest allowed zoom (the zoom-out limit): the largest step at which the whole board PLUS a margin of
## data/arenas.json camera.zoom_out_margin (about 10-15%) still fits the view band. Always <= auto_zoom(); recomputed per arena size and
## window size (extra_w / extra_h), so small arenas stay big and large windows may zoom out further.
static func min_zoom(w: int, h: int) -> float:
	var cam: Dictionary = DB.table("arenas")["camera"]
	var v: Array = cam["view"]
	var m := 1.0 + float(cam.get("zoom_out_margin", 0.12))
	for z in cam["zoom_steps"]:
		var bs := board_size(w, h, float(z)) * m
		if bs.x <= float(v[2]) + extra_w and bs.y <= float(v[3]) + extra_h:
			return float(z)
	return float(cam["zoom_steps"].back())

## Centre the w x h board in the view band at zoom z (0 = auto), shifted by `pan` pixels.
static func fit(w: int, h: int, z: float = 0.0, pan: Vector2 = Vector2.ZERO) -> void:
	var cam: Dictionary = DB.table("arenas")["camera"]
	var v: Array = cam["view"]
	if z <= 0.0:
		z = auto_zoom(w, h)
	set_zoom(z)
	var cx := float(v[0]) + float(v[2]) * 0.5
	var cy := float(v[1]) + float(v[3]) * 0.5
	origin = Vector2(roundf(cx - (w - h) * BASE_TW * z * 0.25 + pan.x), roundf(cy - (w + h) * BASE_TH * z * 0.25 + pan.y))

static func to_screen(g: Vector2) -> Vector2:
	return origin + Vector2((g.x - g.y) * TW * 0.5, (g.x + g.y) * TH * 0.5)

static func to_grid(s: Vector2) -> Vector2:
	var a := (s.x - origin.x) / (TW * 0.5)      # gx - gy
	var b := (s.y - origin.y) / (TH * 0.5)      # gx + gy
	return Vector2((a + b) * 0.5, (b - a) * 0.5)

## Screen position of the middle of tile `p` (accepts Vector2i or fractional vis_pos which is in tile units).
static func center(p: Vector2) -> Vector2:
	return to_screen(p + Vector2(0.5, 0.5))

static func tile_at(s: Vector2) -> Vector2i:
	var g := to_grid(s)
	return Vector2i(floori(g.x), floori(g.y))

## Four corners (top, right, bottom, left) of the diamond of tile p, in screen space.
static func diamond(p: Vector2i, inset: float = 0.0) -> PackedVector2Array:
	var c := center(Vector2(p))
	var hw := TW * 0.5 - inset * 2.0
	var hh := TH * 0.5 - inset
	return PackedVector2Array([c + Vector2(0, -hh), c + Vector2(hw, 0), c + Vector2(0, hh), c + Vector2(-hw, 0)])

## Painter's-algorithm key: larger = nearer to the camera = drawn later.
static func depth(g: Vector2) -> float:
	return g.x + g.y

## Unit foot position (where the shadow sits) on tile p.
static func foot(p: Vector2) -> Vector2:
	return center(p) + Vector2(0, 2.0 * zoom)
