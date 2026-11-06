class_name BGrid
extends RefCounted
## Battle grid: tiles, pathfinding (Dijkstra with move costs), line of sight, procedural layouts.

const W := 12     # default size (tests / legacy); real arenas vary per room, see ArenaGen + data/arenas.json
const H := 7
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var w: int = W
var h: int = H
var tiles: Array = []      # Array[Array[String]] indexed [y][x]
var variant: Array = []    # per-tile cosmetic variant ints
var theme: String = "jungle"

func _init(w_: int = W, h_: int = H) -> void:
	w = w_
	h = h_
	for y in h:
		var row := []
		var vrow := []
		for x in w:
			row.append("ground")
			vrow.append(0)
		tiles.append(row)
		variant.append(vrow)

func count_tiles(id: String) -> int:
	var n := 0
	for row in tiles:
		for t in row:
			if t == id:
				n += 1
	return n

func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < w and p.y < h

func get_tile(p: Vector2i) -> String:
	return tiles[p.y][p.x]

func set_tile(p: Vector2i, t: String) -> void:
	tiles[p.y][p.x] = t

func tdef(p: Vector2i) -> Dictionary:
	return DB.tile(get_tile(p))

func blocks_move(p: Vector2i) -> bool:
	return bool(tdef(p).get("blocks_move", false))

func blocks_sight(p: Vector2i) -> bool:
	return bool(tdef(p).get("blocks_sight", false))

## Move points needed to ENTER tile `p`. `costs` is a unit's terrain override table {tile_id: cost} (aquatic creatures
## pay less for water, etc.); an entry never drops below 1 for walkable tiles.
func move_cost(p: Vector2i, costs: Dictionary = {}) -> int:
	var t := get_tile(p)
	var base := int(tdef(p).get("move_cost", 1))
	if costs.has(t) and not blocks_move(p):
		return maxi(1, int(costs[t]))
	return base

func is_void(p: Vector2i) -> bool:
	return get_tile(p) == "void"

func is_grass(p: Vector2i) -> bool:
	return get_tile(p) == "grass"

## Chance (0..1) that an attack against a unit standing on this tile misses (tall grass: 0.25, data/tiles.json "evasion").
func evasion(p: Vector2i) -> float:
	return float(tdef(p).get("evasion", 0.0))

func detect_mod(p: Vector2i) -> float:
	return float(tdef(p).get("detect_mod", 1.0))

static func dist(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func neighbors(p: Vector2i) -> Array:
	var out := []
	for d in DIRS:
		var q: Vector2i = p + d
		if in_bounds(q):
			out.append(q)
	return out

## Bresenham line of sight between tile centres; obstacles between endpoints block it.
func los(a: Vector2i, b: Vector2i) -> bool:
	var x0 := a.x
	var y0 := a.y
	var dx := absi(b.x - a.x)
	var dy := absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := dx - dy
	while true:
		if x0 == b.x and y0 == b.y:
			return true
		if not (x0 == a.x and y0 == a.y) and blocks_sight(Vector2i(x0, y0)):
			return false
		var e2 := 2 * err
		if e2 > -dy:
			err -= dy
			x0 += sx
		if e2 < dx:
			err += dx
			y0 += sy
	return true

## Dijkstra. `occupied` maps Vector2i -> anything for tiles that cannot be entered.
## Returns {"cost": {pos: cost}, "prev": {pos: pos}}.
func reach(start: Vector2i, max_cost: int, occupied: Dictionary, costs: Dictionary = {}) -> Dictionary:
	var cost := {start: 0}
	var prev := {}
	var open := [start]
	while not open.is_empty():
		var best_i := 0
		for i in open.size():
			if cost[open[i]] < cost[open[best_i]]:
				best_i = i
		var cur: Vector2i = open[best_i]
		open.remove_at(best_i)
		for n in neighbors(cur):
			if blocks_move(n) or occupied.has(n):
				continue
			var c: int = int(cost[cur]) + move_cost(n, costs)
			if c > max_cost:
				continue
			if not cost.has(n) or c < int(cost[n]):
				cost[n] = c
				prev[n] = cur
				if not open.has(n):
					open.append(n)
	return {"cost": cost, "prev": prev}

static func path_from(prev: Dictionary, start: Vector2i, target: Vector2i) -> Array:
	var path := []
	var cur := target
	while cur != start:
		path.push_front(cur)
		if not prev.has(cur):
			return []
		cur = prev[cur]
	return path

# ---------------------------------------------------------------- generation

## Procedural layout from a seed and stage terrain params (data/stages.json -> terrain).
static func generate(seed_val: int, params: Dictionary, theme_id: String, spec: Dictionary = {}) -> BGrid:
	var g := BGrid.new(int(spec.get("w", W)), int(spec.get("h", H)))
	g.theme = theme_id
	var area_k := float(g.w * g.h) / float(DB.table("arenas")["ref_area"])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	for y in g.h:
		for x in g.w:
			g.variant[y][x] = rng.randi() % 4
	_blobs(g, rng, "grass", _scaled(params.get("grass_blobs", [3, 5]), area_k), params.get("grass_size", [3, 7]))
	_blobs(g, rng, "water", _scaled(params.get("water_blobs", [0, 2]), area_k), params.get("water_size", [3, 6]))
	var oc: Array = _scaled(params.get("obstacles", [4, 8]), area_k)
	var n_obs := rng.randi_range(int(oc[0]), int(oc[1]))
	for i in n_obs:
		var p := Vector2i(rng.randi_range(2, g.w - 3), rng.randi_range(0, g.h - 1))
		g.set_tile(p, "obstacle")
		if rng.randf() < 0.45:  # short walls
			var d: Vector2i = DIRS[rng.randi() % 4]
			var q := p + d
			if g.in_bounds(q) and q.x >= 2 and q.x <= g.w - 3:
				g.set_tile(q, "obstacle")
	# keep both spawn flanks open
	for y in g.h:
		for x in [0, 1, g.w - 2, g.w - 1]:
			if g.get_tile(Vector2i(x, y)) == "obstacle":
				g.set_tile(Vector2i(x, y), "ground")
	# arena shape: tiles outside it become void (applied last so blobs/obstacles simply get cut)
	if not spec.is_empty() and String(spec.get("shape", "rect")) != "rect":
		for y in g.h:
			for x in g.w:
				if ArenaGen.is_void(spec, x, y):
					g.set_tile(Vector2i(x, y), "void")
	g._fill_pockets()
	return g

## Scale a [min, max] count range by arena area (never below the lower bound's half, at least 0).
static func _scaled(r: Array, k: float) -> Array:
	return [int(round(float(r[0]) * k)), maxi(int(round(float(r[0]) * k)), int(round(float(r[1]) * k)))]

static func _blobs(g: BGrid, rng: RandomNumberGenerator, tile: String, count_r: Array, size_r: Array) -> void:
	var n := rng.randi_range(int(count_r[0]), int(count_r[1]))
	for i in n:
		var cur := Vector2i(rng.randi_range(0, g.w - 1), rng.randi_range(0, g.h - 1))
		var size := rng.randi_range(int(size_r[0]), int(size_r[1]))
		var cells := [cur]
		g.set_tile(cur, tile)
		for s in size - 1:
			var base: Vector2i = cells[rng.randi() % cells.size()]
			var q: Vector2i = base + DIRS[rng.randi() % 4]
			if g.in_bounds(q):
				g.set_tile(q, tile)
				cells.append(q)

## Any walkable tile not connected to the left spawn column is turned into an obstacle,
## so every walkable tile is reachable.
func _fill_pockets() -> void:
	var seen := {}
	var queue := []
	for y in h:
		var p := Vector2i(0, y)
		if not blocks_move(p):
			seen[p] = true
			queue.append(p)
	if queue.is_empty():     # column 0 entirely cut away: seed from the first walkable tile instead
		for y in h:
			for x in w:
				if queue.is_empty() and not blocks_move(Vector2i(x, y)):
					seen[Vector2i(x, y)] = true
					queue.append(Vector2i(x, y))
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_back()
		for n in neighbors(cur):
			if not blocks_move(n) and not seen.has(n):
				seen[n] = true
				queue.append(n)
	for y in h:
		for x in w:
			var p := Vector2i(x, y)
			if not blocks_move(p) and not seen.has(p):
				set_tile(p, "obstacle")

func free_tiles(avoid: Dictionary, x_min: int, x_max: int, allow_water := false) -> Array:
	var out := []
	x_max = mini(x_max, w - 1)
	for y in h:
		for x in range(x_min, x_max + 1):
			var p := Vector2i(x, y)
			if blocks_move(p) or avoid.has(p):
				continue
			if not allow_water and get_tile(p) == "water":
				continue
			out.append(p)
	return out
