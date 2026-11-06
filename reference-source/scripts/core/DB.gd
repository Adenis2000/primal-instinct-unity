class_name DB
extends RefCounted
## Static data access. All game content lives in res://data/*.json.

const TABLES := ["species", "growth", "cards", "enemies", "events", "weather", "tiles", "stages", "puzzles", "hints", "sprites", "facing", "themes", "items", "nutrition", "arenas", "difficulty", "archetypes", "keywords", "customization", "backdrops", "cutscene_intro", "game", "menu_scene", "visibility"]
static var _data: Dictionary = {}

static func load_all() -> void:
	if not _data.is_empty():
		return
	for n in TABLES:
		var path := "res://data/%s.json" % n
		var f := FileAccess.open(path, FileAccess.READ)
		assert(f != null, "Missing data file " + path)
		var parsed = JSON.parse_string(f.get_as_text())
		assert(parsed != null, "Invalid JSON in " + path)
		_data[n] = parsed

static func table(name: String) -> Dictionary:
	load_all()
	return _data[name]

static func card(id: String) -> Dictionary:
	return table("cards")[id]

static func has_card(id: String) -> bool:
	return table("cards").has(id)

static func enemy(id: String) -> Dictionary:
	return table("enemies")[id]

static func species(id: String) -> Dictionary:
	return table("species")[id]

static func weather(id: String) -> Dictionary:
	return table("weather")[id]

static func tile(id: String) -> Dictionary:
	return table("tiles")[id]

static func growth() -> Dictionary:
	return table("growth")

static func stage_order() -> Array:
	return table("stages")["order"]

static func stage(id: String) -> Dictionary:
	return table("stages")["defs"][id]

static func sprite_def(id: String) -> Dictionary:
	return table("sprites").get(id, {})

## Weighted pick helper. `weights` is {key: weight}.
static func weighted_pick(rng: RandomNumberGenerator, weights: Dictionary):
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	if total <= 0.0:
		return null
	var r := rng.randf() * total
	for k in weights:
		r -= float(weights[k])
		if r <= 0.0:
			return k
	return weights.keys().back()

## All card ids of a tier (non-starter).
static func draft_cards(tier_min: int, tier_max: int) -> Array:
	var out: Array = []
	var cards := table("cards")
	for id in cards:
		var c: Dictionary = cards[id]
		if c.get("rarity", "") == "starter" or c.get("rarity", "") == "cave":
			continue
		var t := int(c.get("tier", 1))
		if t >= tier_min and t <= tier_max:
			out.append(id)
	return out

## Cards that only drop from the secret cave (rarity "cave").
static func cave_cards() -> Array:
	var out: Array = []
	var cards := table("cards")
	for id in cards:
		if String(cards[id].get("rarity", "")) == "cave":
			out.append(id)
	return out

static func item(id: String) -> Dictionary:
	return table("items")["items"][id]

static func nutrition() -> Dictionary:
	return table("nutrition")

static func item_ids() -> Array:
	return table("items")["items"].keys()

static func item_source(src: String) -> Dictionary:
	return table("items")["sources"].get(src, {})

static func facing_cfg() -> Dictionary:
	return table("facing")

static func theme(id: String) -> Dictionary:
	var t: Dictionary = table("themes")
	return t.get(id, t["jungle"])
