class_name StageGen
extends RefCounted
## Generates the rooms of one stage (floor) from the run seed. Room types are decided up front
## but hidden from the player until the door is opened.

const MAX_EXITS := 3

## Number of doors (= exits on the battlefield) for a step: fixed int or [min, max], seeded, capped at MAX_EXITS.
static func door_count(sd: Dictionary, rng: RandomNumberGenerator) -> int:
	var d = sd["doors"]
	var n := 1
	if d is Array:
		n = rng.randi_range(int(d[0]), int(d[1]))
	else:
		n = int(d)
	return clampi(n, 1, MAX_EXITS)

## The secret cave: a harder-than-normal spider den. `step` does not advance when it is cleared or sneaked past.
static func make_cave_room(run: RunState) -> Dictionary:
	var sec: Dictionary = run.stage_def()["secret"]
	var step := int(run.stage["step"])
	var seed_ := RunState.mix(RunState.mix(run.seed_val, 9000 + run.stage_idx), step + 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var enemies: Array = _pick_group(rng, sec["groups"], 99).duplicate()
	var inf: Array = []
	for e in enemies:
		inf.append(false)
	return {"type": "cave", "step": step, "door": -1, "seed": seed_, "visited": true, "stage": String(run.stage["id"]),
		"enemies": enemies, "infected": inf, "unspotted_allowed": rng.randf() < 0.6, "trap": false, "teach": "",
		"theme": String(sec.get("theme", "cave")), "terrain": sec.get("terrain", {}), "reward": sec.get("reward", {})}

static func generate_steps(stage_id: String, def: Dictionary, rng: RandomNumberGenerator, run_seed: int, idx: int) -> Array:
	var steps: Array = []
	var step_defs: Array = def["steps"]
	# 1. pick door types
	for i in step_defs.size():
		var sd: Dictionary = step_defs[i]
		var n := door_count(sd, rng)
		var types: Array = []
		var weights: Dictionary = sd["types"].duplicate()
		for d in n:
			var tries := 0
			var t = DB.weighted_pick(rng, weights)
			while types.has(t) and weights.size() > 1 and tries < 12:
				t = DB.weighted_pick(rng, weights)
				tries += 1
			types.append(t)
		steps.append({"types": types, "forced": sd.has("force"), "chosen": -1, "doors": []})
	# 2. guarantee required room types exist somewhere on the floor
	for req in def.get("required", []):
		var present := false
		for s in steps:
			if req in s["types"]:
				present = true
		if present:
			continue
		var slots: Array = []
		for i in steps.size():
			if steps[i]["forced"] or step_defs[i]["types"].has("boss"):
				continue
			for d in steps[i]["types"].size():
				slots.append([i, d])
		# prefer replacing plain battles
		var preferred: Array = slots.filter(func(sl): return steps[sl[0]]["types"][sl[1]] == "battle")
		var pick_from: Array = preferred if not preferred.is_empty() else slots
		if not pick_from.is_empty():
			var sl: Array = pick_from[rng.randi() % pick_from.size()]
			steps[sl[0]]["types"][sl[1]] = req
	# 3. build rooms
	var used_events: Array = []
	for i in steps.size():
		for d in steps[i]["types"].size():
			var room_seed := RunState.mix(RunState.mix(RunState.mix(run_seed, idx + 1), i + 1), d + 1)
			var r := RandomNumberGenerator.new()
			r.seed = room_seed
			steps[i]["doors"].append(_make_room(stage_id, def, steps[i]["types"][d], i, d, room_seed, r, step_defs[i], used_events))
	return steps

static func _pick_group(rng: RandomNumberGenerator, groups: Array, step: int) -> Array:
	var weights := {}
	for i in groups.size():
		if int(groups[i].get("min_step", 1)) <= step + 1:
			weights[i] = float(groups[i].get("weight", 1))
	if weights.is_empty():
		return groups[0]["enemies"]
	return groups[int(DB.weighted_pick(rng, weights))]["enemies"]

static func _make_room(stage_id: String, def: Dictionary, type: String, step: int, door: int, room_seed: int, rng: RandomNumberGenerator, step_def: Dictionary, used_events: Array) -> Dictionary:
	var room := {"type": type, "step": step, "door": door, "seed": room_seed, "visited": false, "stage": stage_id,
		"enemies": [], "infected": [], "unspotted_allowed": false, "trap": false, "teach": ""}
	match type:
		"battle", "elite", "boss":
			var enemies: Array = []
			if type == "boss":
				enemies = def["boss"]["enemies"].duplicate()
			elif type == "elite":
				enemies = _pick_group(rng, def["elite_groups"], step).duplicate()
			elif step_def.has("force"):
				enemies = step_def["force"]["enemies"].duplicate()
				room["teach"] = step_def["force"].get("teach", "")
			else:
				enemies = _pick_group(rng, def["battle_groups"], step).duplicate()
			room["enemies"] = enemies
			for e in enemies:
				var ed: Dictionary = DB.enemy(e)
				room["infected"].append(bool(ed.get("infected", false)) or rng.randf() < float(ed.get("infected_chance", 0.0)))
			if type == "boss":
				room["unspotted_allowed"] = false
				room["trap"] = true
			elif step_def.has("force") and step_def["force"].get("unspotted", false):
				room["unspotted_allowed"] = true
			else:
				var chance := float(def.get("unspotted_chance", 0.6))
				if type == "elite":
					chance *= 0.6
				if rng.randf() < float(def.get("trap_chance", 0.1)):
					room["trap"] = true
				else:
					room["unspotted_allowed"] = rng.randf() < chance
		"event":
			var pool: Array = []
			var evs: Dictionary = DB.table("events")["events"]
			for k in evs:
				if stage_id in evs[k]["stages"] and not used_events.has(k):
					pool.append(k)
			if pool.is_empty():
				for k in evs:
					if stage_id in evs[k]["stages"]:
						pool.append(k)
			var pick: String = pool[rng.randi() % pool.size()]
			used_events.append(pick)
			room["event_id"] = pick
		"forage":
			var fg: Dictionary = DB.table("events")["forage"]
			var pool: Array = []
			for k in fg:
				if stage_id in fg[k]["stages"]:
					pool.append(k)
			var picked: Array = []
			while picked.size() < 3 and not pool.is_empty():
				var i := rng.randi() % pool.size()
				picked.append(pool[i])
				pool.remove_at(i)
			room["forage_ids"] = picked
		"puzzle":
			var pid := "stone_sequence"
			var pd: Dictionary = DB.table("puzzles")[pid]
			var cfg: Dictionary = pd["per_stage"].get(stage_id, pd["per_stage"].values()[0])
			var seq: Array = []
			for i in int(cfg["length"]):
				seq.append(rng.randi() % int(cfg["buttons"]))
			room["puzzle_id"] = pid
			room["sequence"] = seq
			room["buttons"] = int(cfg["buttons"])
			room["mistakes"] = int(cfg["mistakes"])
	return room
