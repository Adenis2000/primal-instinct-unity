class_name ExitGen
extends RefCounted
## Places the exit gates (max StageGen.MAX_EXITS = 3, one per side) on the EDGES of a battlefield, plus the optional
## secret cave entrance on a random free tile INSIDE the area. Pure + seeded, so it is testable and reproducible.
##
## Sides on screen (grid +x = down-right, +y = down-left):
##   "NE": y = 0 row (upper-right edge)   "NW": x = 0 column (upper-left edge)
##   "SE": x = w-1 column (lower-right)   "SW": y = h-1 row (lower-left)

const SIDES := ["NE", "NW", "SE", "SW"]
## "Forward" = up-screen: the NE / NW edges. Door 0 (the main path forward) always leaves through one of them; the other doors use
## the remaining sides as alternative side paths.
const FORWARD := ["NE", "NW"]

## Unit step OUTWARD from an edge tile of `side` (leaving the board): NE = -y, NW = -x, SE = +x, SW = +y.
static func out_dir(side: String) -> Vector2i:
	match side:
		"NE":
			return Vector2i(0, -1)
		"NW":
			return Vector2i(-1, 0)
		"SE":
			return Vector2i(1, 0)
	return Vector2i(0, 1)

## The negative-space corridor (tiles OUTSIDE the grid) of an exit: `width` tiles across (centred on the trigger tile's line),
## `length` tiles from the board edge outward. Returns [{tile: Vector2i, k: 1..length (distance from the edge), o: lateral offset}].
static func corridor(pos: Vector2i, side: String, width: int = 3, length: int = 6) -> Array:
	var d := out_dir(side)
	var perp := Vector2i(absi(d.y), absi(d.x))      # the axis along the edge
	var out := []
	var half := width / 2
	for k in range(1, length + 1):
		for o in range(-half, width - half):
			out.append({"tile": pos + d * k + perp * o, "k": k, "o": o})
	return out

static func side_tiles(g: BGrid, side: String) -> Array:
	var out := []
	match side:
		"NE":
			for x in range(1, g.w - 1):
				out.append(Vector2i(x, 0))
		"SW":
			for x in range(1, g.w - 1):
				out.append(Vector2i(x, g.h - 1))
		"NW":
			for y in range(1, g.h - 1):
				out.append(Vector2i(0, y))
		"SE":
			for y in range(1, g.h - 1):
				out.append(Vector2i(g.w - 1, y))
	return out.filter(func(p): return not g.is_void(p))

static func side_of(g: BGrid, p: Vector2i) -> String:
	if p.y == 0:
		return "NE"
	if p.y == g.h - 1:
		return "SW"
	if p.x == 0:
		return "NW"
	if p.x == g.w - 1:
		return "SE"
	return ""

static func is_edge(g: BGrid, p: Vector2i) -> bool:
	return p.x == 0 or p.y == 0 or p.x == g.w - 1 or p.y == g.h - 1

## The tile just inside the edge from an exit tile (what you step from).
static func inner_neighbor(g: BGrid, p: Vector2i) -> Vector2i:
	match side_of(g, p):
		"NE":
			return p + Vector2i(0, 1)
		"SW":
			return p + Vector2i(0, -1)
		"NW":
			return p + Vector2i(1, 0)
		"SE":
			return p + Vector2i(-1, 0)
	return p

static func _make_walkable(g: BGrid, p: Vector2i) -> void:
	if g.get_tile(p) == "obstacle" or g.get_tile(p) == "water":
		g.set_tile(p, "ground")

## Returns [{pos: Vector2i (the edge tile that triggers the exit), side: String, dir: Vector2i (outward)}]; `count` is clamped to 1..3. Exits are on distinct sides, never in a corner,
## at least 3 tiles apart, never on `avoid`, always reachable from `from` (obstacles are carved if needed).
static func place_exits(g: BGrid, count: int, rng: RandomNumberGenerator, from: Vector2i, avoid: Array = []) -> Array:
	count = clampi(count, 1, StageGen.MAX_EXITS)
	var sides: Array = SIDES.duplicate()
	for i in range(sides.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = sides[i]
		sides[i] = sides[j]
		sides[j] = tmp
	# the main path (door 0) goes forward (up-screen); the rest keep their shuffled order on the other sides
	var fwd: String = sides.filter(func(sd): return FORWARD.has(sd))[0]
	sides.erase(fwd)
	sides.push_front(fwd)
	var out := []
	for k in count:
		var side: String = sides[k]
		var tiles := side_tiles(g, side)
		for i in range(tiles.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp = tiles[i]
			tiles[i] = tiles[j]
			tiles[j] = tmp
		var chosen := Vector2i(-1, -1)
		for t in tiles:
			if t == from or avoid.has(t):
				continue
			var far := true
			for o in out:
				if BGrid.dist(o["pos"], t) < 3:
					far = false
			if not far:
				continue
			# prefer tiles that are already open; carve otherwise
			chosen = t
			if g.get_tile(t) != "obstacle" and g.get_tile(t) != "water":
				break
		if chosen == Vector2i(-1, -1):
			chosen = tiles[0]
		_make_walkable(g, chosen)
		_make_walkable(g, inner_neighbor(g, chosen))
		_ensure_reachable(g, from, chosen)
		out.append({"pos": chosen, "side": side, "dir": out_dir(side)})
	return out

## Carve an L-shaped corridor of ground through obstacles if `to` cannot be reached from `from`.
static func _ensure_reachable(g: BGrid, from: Vector2i, to: Vector2i) -> void:
	if g.reach(from, 999, {})["cost"].has(to):
		return
	var p := from
	while p.x != to.x:
		p.x += signi(to.x - p.x)
		if g.get_tile(p) == "obstacle":
			g.set_tile(p, "ground")
	while p.y != to.y:
		p.y += signi(to.y - p.y)
		if g.get_tile(p) == "obstacle":
			g.set_tile(p, "ground")

## Secret cave entrance: a random free tile strictly inside the area (not on any edge), away from gates and the player.
## Returns (-1,-1) if no tile qualifies.
static func place_secret(g: BGrid, rng: RandomNumberGenerator, from: Vector2i, avoid: Array = []) -> Vector2i:
	var cands := []
	for y in range(2, g.h - 2):
		for x in range(2, g.w - 2):
			var p := Vector2i(x, y)
			var t := g.get_tile(p)
			if t != "ground" and t != "grass":
				continue
			if p == from or BGrid.dist(p, from) < 3:
				continue
			var ok := true
			for a in avoid:
				if BGrid.dist(p, a) < 3:
					ok = false
			if ok and g.reach(from, 999, {})["cost"].has(p):
				cands.append(p)
	if cands.is_empty():
		return Vector2i(-1, -1)
	return cands[rng.randi() % cands.size()]
