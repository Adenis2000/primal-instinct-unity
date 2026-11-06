class_name ArenaGen
extends RefCounted
## Seeded per-room arena size + shape (data/arenas.json). Pure; uses its own rng stream so other seeded streams keep their draws.
## pick() -> {w, h, shape, cut: Vector2i}; apply() cuts the shape out of a grid as "void" tiles.

static func pick(rseed: int, room: Dictionary, mode: String, stage_idx: int) -> Dictionary:
	if room.has("arena_fixed"):
		return room["arena_fixed"]       # tests / scripted rooms pin an exact arena
	var cfg: Dictionary = DB.table("arenas")
	var rng := RandomNumberGenerator.new()
	rng.seed = RunState.mix(rseed, 9001)
	var type := String(room.get("type", "battle"))
	if not cfg["types"].has(type):
		type = "battle"
	if type == "battle" and stage_idx == 0 and int(room.get("step", 1)) == 0:
		type = "tutorial"
	var t: Dictionary = cfg["types"][type]
	var grow := int(cfg["stage_grow"][clampi(stage_idx, 0, cfg["stage_grow"].size() - 1)]) if type != "tutorial" else 0
	var big := 0
	for id in room.get("enemies", []):
		if int(DB.enemy(String(id)).get("hp", 0)) >= int(cfg["big_hp"]):
			big = int(cfg["big_bonus"])
	var shrink := int(cfg["ambush_shrink"]) if mode == "ambush" and type != "tutorial" else 0
	var lo: Array = cfg["min"]
	var hi: Array = cfg["max"]
	var w := clampi(rng.randi_range(int(t["w"][0]), int(t["w"][1]) + grow) + big - shrink, int(lo[0]), int(hi[0]))
	var h := clampi(rng.randi_range(int(t["h"][0]), int(t["h"][1]) + grow) + big - shrink, int(lo[1]), int(hi[1]))
	var shape := String(DB.weighted_pick(rng, cfg["shapes"]))
	if w * h < 56 and shape != "rect":
		shape = "rect"   # tiny arenas stay rectangular
	var cut := Vector2i.ZERO
	match shape:
		"chamfer":
			cut = Vector2i(rng.randi_range(1, 2), 0)
			if mini(w, h) < 7:
				cut.x = 1
		"L":
			cut = Vector2i(rng.randi_range(2, maxi(2, w / 3)), rng.randi_range(2, maxi(2, h / 3)))
			cut.x = mini(cut.x, w - 5)
			cut.y = mini(cut.y, h - 4)
			if cut.x < 2 or cut.y < 2:
				shape = "rect"
				cut = Vector2i.ZERO
	return {"w": w, "h": h, "shape": shape, "cut": cut, "type": type, "corner": rng.randi() % 4}

## True if tile (x, y) is outside the arena shape.
static func is_void(spec: Dictionary, x: int, y: int) -> bool:
	var w := int(spec["w"])
	var h := int(spec["h"])
	var cut: Vector2i = spec["cut"]
	match String(spec["shape"]):
		"chamfer":
			return mini(x, w - 1 - x) + mini(y, h - 1 - y) < cut.x
		"L":
			var cx := x if int(spec["corner"]) % 2 == 0 else w - 1 - x     # mirror so any of the 4 corners can be the missing one
			var cy := y if int(spec["corner"]) < 2 else h - 1 - y
			return cx >= w - cut.x and cy >= h - cut.y
	return false
