class_name Difficulty
extends RefCounted
## Data-driven difficulty (data/difficulty.json): stat scaling for enemies, extra enemies, hunger. Pure functions.

static func cfg() -> Dictionary:
	return DB.table("difficulty")

static func level(run: RunState) -> Dictionary:
	var lv: Dictionary = cfg()["levels"]
	return lv.get(run.difficulty, lv[cfg()["default"]])

static func stage_row(run: RunState) -> Dictionary:
	var rows: Array = cfg()["stages"]
	return rows[clampi(maxi(run.stage_idx, 0), 0, rows.size() - 1)]

## True for the gentle first rooms of stage 1.
static func is_tutorial(run: RunState, room: Dictionary) -> bool:
	return run.stage_idx <= 0 and int(room.get("step", 99)) < int(cfg()["tutorial"]["steps"])

static func kind_row(room: Dictionary) -> Dictionary:
	var k: Dictionary = cfg()["kinds"]
	return k.get(String(room.get("type", "battle")), k["battle"])

## Multiplier for an enemy's max HP in `room`.
static func hp_mult(run: RunState, room: Dictionary) -> float:
	if bool(room.get("no_scale", false)):
		return 1.0
	if is_tutorial(run, room):
		return float(cfg()["tutorial"]["hp"]) * float(level(run)["hp"])
	var st := stage_row(run)
	var step := int(room.get("step", 0))
	return float(level(run)["hp"]) * float(st["hp"]) * (1.0 + float(st["step_ramp"]) * step) * float(kind_row(room)["hp"])

## Flat damage added to every enemy attack in `room`.
static func dmg_add(run: RunState, room: Dictionary) -> int:
	if bool(room.get("no_scale", false)):
		return 0
	if is_tutorial(run, room):
		return int(cfg()["tutorial"]["dmg"])
	return int(level(run)["dmg"]) + int(stage_row(run)["dmg"]) + int(kind_row(room)["dmg"])

## Chance that a normal fought room gains one extra enemy.
static func extra_chance(run: RunState, room: Dictionary) -> float:
	if bool(room.get("no_scale", false)):
		return 0.0
	if is_tutorial(run, room) or String(room.get("type", "battle")) != "battle" or String(room.get("teach", "")) != "":
		return 0.0
	return float(stage_row(run)["extra"]) + float(level(run)["extra"])

static func hunger_mult(run: RunState) -> float:
	if run.stage_idx <= 0 and run.cleared_rooms < int(cfg()["tutorial"]["steps"]):
		return 1.0
	return float(level(run)["hunger"])

static func level_ids() -> Array:
	return cfg()["levels"].keys()
