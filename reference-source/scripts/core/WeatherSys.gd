class_name WeatherSys
extends RefCounted
## Resolves weather effects for a creature from its tags. Data in data/weather.json.

const KEYS_MULT := ["perception_mult", "speed_mult", "damage_mult"]
const KEYS_ADD := ["hunger_extra", "stamina_delta", "sneak_bonus"]

static func mods_for(weather_id: String, tags: Array) -> Dictionary:
	var out := {"perception_mult": 1.0, "speed_mult": 1.0, "damage_mult": 1.0, "hunger_extra": 0, "stamina_delta": 0, "sneak_bonus": 0.0}
	if weather_id == "" or not DB.table("weather").has(weather_id):
		return out
	var w: Dictionary = DB.weather(weather_id)
	_apply(out, w.get("global", {}))
	var by_tag: Dictionary = w.get("by_tag", {})
	for t in tags:
		if by_tag.has(t):
			_apply(out, by_tag[t])
	return out

static func _apply(out: Dictionary, src: Dictionary) -> void:
	for k in src:
		if k in KEYS_MULT:
			out[k] = float(out[k]) * float(src[k])
		elif k in KEYS_ADD:
			out[k] = out[k] + src[k]

## Human-readable lines describing what the weather does to a creature with these tags.
static func describe_for(weather_id: String, tags: Array) -> Array:
	var m := mods_for(weather_id, tags)
	var lines: Array = []
	if absf(float(m["perception_mult"]) - 1.0) > 0.01:
		lines.append("Enemy sight range x%.2f" % m["perception_mult"])
	if absf(float(m["speed_mult"]) - 1.0) > 0.01:
		lines.append("Speed x%.2f" % m["speed_mult"])
	if absf(float(m["damage_mult"]) - 1.0) > 0.01:
		lines.append("Damage x%.2f" % m["damage_mult"])
	if int(m["hunger_extra"]) != 0:
		lines.append("+%d hunger per room" % int(m["hunger_extra"]))
	return lines

static func roll(rng: RandomNumberGenerator, stage_def: Dictionary) -> String:
	var weights: Dictionary = stage_def.get("weather_weights", {})
	if weights.is_empty():
		for k in DB.table("weather"):
			weights[k] = DB.weather(k).get("weight", 1)
	return String(DB.weighted_pick(rng, weights))
