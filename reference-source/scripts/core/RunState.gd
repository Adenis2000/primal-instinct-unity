class_name RunState
extends RefCounted
## All state of a single run (resets completely on death). Pure logic, no UI, fully testable headless.

var seed_val: int = 0
var rng := RandomNumberGenerator.new()      # macro RNG (events, drafts, outcomes)
var species_id: String = "velociraptor"
var species: Dictionary = {}
var look: Dictionary = {}                # cosmetic customization (Look.gd), set by Game.start_run
var level: int = 1
var xp: int = 0
var hp: int = 1
var hunger: int = 90
var spores: int = 0
var deck: Array = []
var stage_idx: int = -1
var stage: Dictionary = {}
var current_room: Dictionary = {}
var cleared_rooms: int = 0
var game_over: bool = false
var victory: bool = false
var cause: String = ""
var stats := {"kills": 0, "ambushes": 0, "sneaks": 0, "cards_drafted": 0, "eaten": 0, "events": 0, "puzzles": 0}
var pending_evolution_tier: int = 0   # >0 when an evolution draft is owed
var meals: Array = []   # rolling diet log, newest first: {pts, profile, kind}
var nutrition := {"protein": 0.0, "fat": 0.0, "minerals": 0.0, "fiber": 0.0, "toxin": 0.0}   # meters (see data/nutrition.json)
var branches := {}                     # evolution tier (as String) -> chosen branch id ("" = standard growth)

# ------------------------------------------------------------------ setup

static func mix(a: int, b: int) -> int:
	var h: int = (a * 1103515245 + b * 12345 + 0x9E3779B9) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return h

static func seed_from_text(t: String) -> int:
	t = t.strip_edges()
	if t == "":
		return 0
	if t.is_valid_int():
		return absi(int(t)) % 2147483647
	var h := 7
	for i in t.length():
		h = mix(h, t.unicode_at(i))
	return h

static func create(species_id_: String, seed_in: int = 0) -> RunState:
	var r := RunState.new()
	r.species_id = species_id_
	r.species = DB.species(species_id_)
	if seed_in <= 0:
		var g := RandomNumberGenerator.new()
		g.randomize()
		seed_in = g.randi_range(1, 2147483646)
	r.seed_val = seed_in
	r.rng.seed = seed_in
	r.deck = []
	var sd: Dictionary = r.species.get("starter_deck", {})
	for id in sd:
		for i in int(sd[id]):
			r.deck.append(id)
	r.hunger = int(r.species.get("start_hunger", 90))
	r.hp = r.max_hp()
	return r

# ------------------------------------------------------------------ stats

func form_index() -> int:
	var forms: Array = DB.growth()["forms"]
	var idx := 0
	for i in forms.size():
		if level >= int(forms[i]["min_level"]):
			idx = i
	return idx

func form() -> Dictionary:
	return DB.growth()["forms"][form_index()]

func tier() -> int:
	return int(form()["tier"])

func form_sprite_id() -> String:
	return String(species["sprites"][form()["id"]])

func tags() -> Array:
	return species.get("tags", [])

## ---- items (data/items.json): permanent bonuses / once-per-battle actives found after cleared areas
var items: Array = []

func item_bonus(key: String) -> int:
	var n := 0
	for id in items:
		n += int(DB.item(String(id))["effects"].get(key, 0))
	return n

func has_item(id: String) -> bool:
	return items.has(id)

func add_item(id: String) -> void:
	if items.has(id):
		return
	items.append(id)
	var gain := int(DB.item(id)["effects"].get("max_hp", 0))
	if gain > 0:
		hp = mini(max_hp(), hp + gain)

## Seeded drop roll for a cleared room of this kind (data: items.json sources.<src>.chance).
func item_drop(src: String) -> bool:
	var s := DB.item_source(src)
	return not s.is_empty() and rng.randf() < float(s.get("chance", 0.0))

## `n` distinct items the run does not own, weighted by the source's rarity table.
func offer_items(src: String, n: int = -1) -> Array:
	var s := DB.item_source(src)
	if n < 0:
		n = int(s.get("choices", 1))
	var rw: Dictionary = s.get("weights", {})
	var weights := {}
	for id in DB.item_ids():
		if items.has(id):
			continue
		var d: Dictionary = DB.item(id)
		if d.has("only") and not (src in d["only"]):
			continue
		var w := float(rw.get(String(d["rarity"]), 0.0))
		if w > 0.0:
			weights[id] = w
	var out: Array = []
	while out.size() < n and not weights.is_empty():
		var pick = DB.weighted_pick(rng, weights)
		out.append(pick)
		weights.erase(pick)
	return out

func max_hp() -> int:
	return int(species["base"]["max_hp"]) + int(form()["hp"]) + (level - 1) * int(DB.growth()["hp_per_level"]) + item_bonus("max_hp")

func base_speed() -> float:
	return float(species["base"]["speed"]) + float(form()["speed"])

func base_move() -> int:
	return int(species["base"]["move"]) + int(form()["move"]) + item_bonus("move")

func base_stamina() -> int:
	return int(species["base"]["stamina"]) + int(form()["stamina"]) + item_bonus("stamina")

func hand_size() -> int:
	return int(species["base"]["hand_size"])

func hunger_max() -> int:
	return int(DB.growth()["hunger"]["max"])

func hunger_state() -> String:
	var hcfg: Dictionary = DB.growth()["hunger"]
	if hunger <= 0:
		return "starving"
	if hunger <= int(hcfg["low_threshold"]):
		return "low"
	return "ok"

func weather_id() -> String:
	return String(stage.get("weather", ""))

func weather_mods() -> Dictionary:
	return WeatherSys.mods_for(weather_id(), tags())

func hunger_cost() -> int:
	var base := int(form()["hunger_per_room"]) + int(weather_mods()["hunger_extra"]) - item_bonus("hunger_save")
	return maxi(1, int(round(float(base) * Difficulty.hunger_mult(self))))

func xp_to_next() -> int:
	var lx: Array = DB.growth()["level_xp"]
	if level >= lx.size():
		return 0
	return int(lx[level])

func max_level() -> int:
	return DB.growth()["level_xp"].size()

# ------------------------------------------------------------------ resources

func change_hp(delta: int) -> void:
	hp = clampi(hp + delta, 0, max_hp())
	_check_dead("")

func _check_dead(why: String) -> void:
	if hp <= 0 and not game_over:
		game_over = true
		cause = why if why != "" else "You were killed."

func change_hunger(delta: int) -> void:
	hunger = clampi(hunger + delta, 0, hunger_max())

## Returns {"levels": Array[int], "evolved": bool}
func grant_xp(amount: int) -> Dictionary:
	var bonus := int(round(float(amount) * xp_bonus()))
	var res := {"levels": [], "evolved": false, "bonus": bonus, "gained": amount + bonus}
	xp += amount + bonus
	while level < max_level() and xp >= xp_to_next():
		var old_form := form_index()
		var old_max := max_hp()
		level += 1
		res["levels"].append(level)
		var gain := max_hp() - old_max
		hp = mini(max_hp(), hp + gain + int(max_hp() * float(DB.growth()["level_up_heal_pct"])))
		if form_index() != old_form:
			res["evolved"] = true
			pending_evolution_tier = tier()
	return res

## Called when entering a room: hunger depletes, starvation hurts. Returns log lines.
func enter_room(room: Dictionary) -> Array:
	var msgs: Array = []
	current_room = room
	var cost := hunger_cost()
	change_hunger(-cost)
	msgs.append("Entered a room: -%d hunger." % cost)
	if hunger <= 0:
		var loss := int(DB.growth()["hunger"]["starve_hp_loss"])
		hp = maxi(0, hp - loss)
		msgs.append("You are starving! -%d HP." % loss)
		_check_dead("You starved to death.")
	if spores > 0:
		spores = maxi(0, spores - 1)
	return msgs

# ------------------------------------------------------------------ stages

func begin_stage(idx: int) -> void:
	stage_idx = idx
	var sid: String = DB.stage_order()[idx]
	var def := DB.stage(sid)
	var srng := RandomNumberGenerator.new()
	srng.seed = mix(seed_val, 1000 + idx)
	var steps: Array = StageGen.generate_steps(sid, def, srng, seed_val, idx)
	stage = {
		"id": sid, "idx": idx, "def": def, "steps": steps, "step": 0,
		"weather": WeatherSys.roll(srng, def), "theme": def.get("theme", "jungle"),
	}
	current_room = {}

func stage_def() -> Dictionary:
	return stage.get("def", {})

func current_step_doors() -> Array:
	var steps: Array = stage["steps"]
	if stage["step"] >= steps.size():
		return []
	return steps[stage["step"]]["doors"]

func choose_door(i: int) -> Dictionary:
	var room: Dictionary = current_step_doors()[i]
	stage["steps"][stage["step"]]["chosen"] = i
	room["visited"] = true
	return room

## Finish the current room; returns "next" | "stage_clear".
func complete_room() -> String:
	cleared_rooms += 1
	stage["step"] = int(stage["step"]) + 1
	if int(stage["step"]) >= stage["steps"].size():
		return "stage_clear"
	return "next"

func advance_stage() -> bool:
	"""Start next stage. Returns false (and sets victory) when there are none left."""
	if stage_idx + 1 >= DB.stage_order().size():
		victory = true
		return false
	begin_stage(stage_idx + 1)
	return true

# ------------------------------------------------------------------ cards

func add_card(id: String) -> void:
	deck.append(id)

func remove_one_card(id: String) -> bool:
	var i := deck.find(id)
	if i >= 0:
		deck.remove_at(i)
		return true
	return false

## Draft offer. mode: "normal" | "evolution" | "elite"
func offer_cards(n: int, mode: String = "normal") -> Array:
	var t := tier()
	var pool: Array = []
	if mode == "evolution":
		pool = DB.draft_cards(t, t)
		if pool.size() < n:
			pool = DB.draft_cards(1, t)
	elif mode == "cave":
		pool = DB.cave_cards()
	else:
		pool = DB.draft_cards(1, t)
	var weights := {}
	for id in pool:
		var c: Dictionary = DB.card(id)
		var w := 1.0
		if int(c["tier"]) == t:
			w = 3.0
		elif int(c["tier"]) == t - 1:
			w = 2.0
		if mode == "elite" and int(c["tier"]) >= 2:
			w *= 2.0
		weights[id] = w
	var out: Array = []
	while out.size() < n and not weights.is_empty():
		var pick = DB.weighted_pick(rng, weights)
		out.append(pick)
		weights.erase(pick)
	return out

## Apply data-driven effects (events, puzzles, rewards). Returns log lines.
## ctx may receive "battle": {enemies:[...], unspotted:bool}.
func apply_effects(effects: Array, ctx: Dictionary = {}) -> Array:
	var msgs: Array = []
	for e in effects:
		var amt := int(e.get("amount", 0))
		match String(e["op"]):
			"xp":
				var r := grant_xp(amt)
				msgs.append("+%d XP" % amt)
				ctx["levels"] = r["levels"]
				if r["evolved"]:
					ctx["evolved"] = true
			"hunger":
				change_hunger(amt)
				msgs.append("%+d hunger" % amt)
			"hp":
				if amt < 0:
					hp = maxi(0, hp + amt)
					_check_dead("You died from your wounds.")
				else:
					change_hp(amt)
				msgs.append("%+d HP" % amt)
			"heal":
				change_hp(amt)
				msgs.append("+%d HP" % amt)
			"spores":
				spores += amt
				msgs.append("Infected: +%d spores" % amt)
			"cleanse":
				spores = 0
				msgs.append("Spores cleansed")
			"add_card":
				var id := String(e.get("id", ""))
				if id == "":
					var pool := DB.draft_cards(2, tier()) if tier() >= 2 else DB.draft_cards(1, 1)
					id = String(pool[rng.randi() % pool.size()])
				add_card(id)
				msgs.append("Gained card: %s" % DB.card(id)["name"])
			"remove_card":
				if remove_one_card(String(e.get("id", "claw_slash"))):
					msgs.append("Lost a card")
			"battle":
				var enemies: Array = []
				var pools: Dictionary = DB.table("events")["battle_pools"]
				var pool_id := String(e.get("pool", ""))
				if pools.has(pool_id):
					var sp: Dictionary = pools[pool_id]
					var key := String(stage.get("id", "stage_1"))
					enemies = sp.get(key, sp.values()[0])
				else:
					enemies = e.get("enemies", [])
				ctx["battle"] = {"enemies": enemies, "unspotted": bool(e.get("unspotted", false))}
	return msgs

func resolve_outcome(choice: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	"""Roll a weighted outcome of an event/forage choice and apply it. Returns {text, msgs}."""
	var outs: Array = choice["outcomes"]
	var weights := {}
	for i in outs.size():
		weights[i] = float(outs[i].get("weight", 1))
	var idx := int(DB.weighted_pick(rng, weights))
	var o: Dictionary = outs[idx]
	var msgs := apply_effects(o.get("effects", []), ctx)
	if choice.has("nutrition"):
		add_nutrition(choice["nutrition"])      # forage food has a nutrition profile too
		var fp: Dictionary = choice["nutrition"].duplicate()
		for nk in DB.nutrition()["order"]:
			if not fp.has(nk):
				fp[nk] = 0
		log_meal(meal_pts(fp), fp, "forage")
	return {"text": String(o.get("text", "")), "msgs": msgs}

# ------------------------------------------------------------------ nutrition (data/nutrition.json)

func diet_id() -> String:
	return String(species.get("diet", "carnivore"))

func diet() -> Dictionary:
	return DB.nutrition()["diets"][diet_id()]

## Nutrient profile of a creature's meat (infected flesh carries extra toxins).
static func meal_profile(enemy_id: String, infected: bool) -> Dictionary:
	var p: Dictionary = DB.enemy(enemy_id).get("nutrition", {}).duplicate()
	for k in DB.nutrition()["order"]:
		if not p.has(k):
			p[k] = 0
	if infected and not bool(DB.enemy(enemy_id).get("infected", false)):
		p["toxin"] = int(p["toxin"]) + 3
	return p

func add_nutrition(profile: Dictionary, mult: float = 1.0) -> void:
	var cap := float(DB.nutrition()["meter_cap"])
	for k in profile:
		var gain := float(profile[k]) * mult
		if k != "toxin":
			gain *= 1.0 + float(item_bonus("nutrition_pct")) / 100.0
		nutrition[k] = clampf(float(nutrition.get(k, 0.0)) + gain, 0.0, cap)

## How well this particular meal fits your diet: sum of weights * nutrients.
func meal_score(profile: Dictionary) -> float:
	var w: Dictionary = diet()["weights"]
	var s := 0.0
	for k in profile:
		s += float(w.get(k, 0.0)) * float(profile[k])
	return s

func meal_fit_label(profile: Dictionary) -> String:
	var sc := meal_score(profile)
	for row in DB.nutrition()["fit_labels"]:
		if sc >= float(row[0]):
			return String(row[1])
	return "Harmful"

## Points a meal contributes to the rolling diet (its fit score, clamped).
func meal_pts(profile: Dictionary) -> float:
	var cfg: Dictionary = DB.nutrition()["rolling"]
	return clampf(meal_score(profile), float(cfg["pts_min"]), float(cfg["pts_max"]))

## Record a meal in the rolling diet log (newest first). kind: "eat" | "fill" | "forage".
func log_meal(pts: float, profile: Dictionary, kind: String) -> void:
	meals.push_front({"pts": pts, "profile": profile.duplicate(), "kind": kind})
	var win := int(DB.nutrition()["rolling"]["window"])
	while meals.size() > win:
		meals.pop_back()

## Rolling diet score over `log` (newest first): recency-weighted points, minus a penalty for monoculture.
func _rolling_score(log: Array) -> int:
	var cfg: Dictionary = DB.nutrition()["rolling"]
	var rec: Array = cfg["recency"]
	var total_w := 0.0
	for w in rec:
		total_w += float(w)
	var acc := 0.0
	var shares := {}
	var pref: Array = diet()["prefers"]
	for i in mini(log.size(), rec.size()):
		acc += float(rec[i]) * float(log[i]["pts"])
		if String(log[i]["kind"]) != "fill":
			for k in pref:
				shares[k] = float(shares.get(k, 0.0)) + float(rec[i]) * maxf(0.0, float(log[i]["profile"].get(k, 0)))
	var score := acc / total_w * float(cfg["scale"])
	var bal: Dictionary = cfg["balance"]
	if log.size() >= int(bal["min_meals"]) and pref.size() >= 2:
		var tot := 0.0
		var top := 0.0
		for k in shares:
			tot += float(shares[k])
			top = maxf(top, float(shares[k]))
		if tot > 0.0 and top / tot > float(bal["threshold"]):
			score -= minf(float(bal["max_penalty"]), (top / tot - float(bal["threshold"])) * float(bal["scale"]))
	return int(round(score))

func diet_score() -> int:
	return _rolling_score(meals)

func quality_for(sc: int) -> String:
	for row in DB.nutrition()["quality_labels"]:
		if sc >= int(row[0]):
			return String(row[1])
	return "Poor"

## Growth bonus from a good diet (data/nutrition.json xp_bonus by quality label): +0..25% XP.
func xp_bonus() -> float:
	return float(DB.nutrition().get("xp_bonus", {}).get(diet_quality(), 0.0))

## Diet score / quality label after a hypothetical meal (for the eat preview). kind "fill" = junk.
func score_after(profile: Dictionary, kind: String = "eat") -> int:
	var pts := float(DB.nutrition()["fill_pts"]) if kind == "fill" else meal_pts(profile)
	var log := meals.duplicate()
	log.push_front({"pts": pts, "profile": profile, "kind": kind})
	return _rolling_score(log)

func quality_after(profile: Dictionary, kind: String = "eat") -> String:
	return quality_for(score_after(profile, kind))

func xp_bonus_for(quality: String) -> float:
	return float(DB.nutrition().get("xp_bonus", {}).get(quality, 0.0))

func diet_quality() -> String:
	return quality_for(diet_score())

## Diet tier as a number for card/item scaling: Poor 0, Fair 1, Good 2, Excellent 3.
func diet_tier() -> int:
	return {"Poor": 0, "Fair": 1, "Good": 2, "Excellent": 3}.get(diet_quality(), 0)

## Hunger you gain from eating a corpse worth `food`: savouring it (Eat) gives only part; filling up gives all.
func eat_hunger(food: int, mode: String) -> int:
	if mode == "fill":
		return food
	return maxi(1, int(ceil(float(food) * float(DB.nutrition()["eat_hunger_mult"]))))

## HP restored by a meal: food/4, scaled by how well it fits (Great x1.5 ... Harmful 0; filling up counts as junk x0.5).
func meal_heal(food: int, prof: Dictionary, mode: String) -> int:
	var mm: Dictionary = DB.nutrition()["meal_mult"]
	var key := "fill" if mode == "fill" else meal_fit_label(prof)
	return int(round(float(food) / 4.0 * float(mm[key]["heal"]))) + item_bonus("eat_heal")

## Eat one corpse (optional, per kill). mode "eat" = savour (nutrients + rating, partial hunger);
## "fill" = just fill up (full hunger, no nutrients, logged as junk). Returns what happened.
func eat_corpse(corpse: Dictionary, mode: String = "eat") -> Dictionary:
	var infected: bool = bool(corpse.get("infected", false))
	var food_full := int(corpse.get("food", 0)) / (2 if infected else 1)
	var food := eat_hunger(food_full, mode)
	var prof := meal_profile(String(corpse["id"]), infected)
	var fit := meal_fit_label(prof)
	var mm: Dictionary = DB.nutrition()["meal_mult"]
	var heal := meal_heal(food, prof, mode)
	change_hunger(food)
	change_hp(heal)
	var tox_loss := 0
	var tox := int(prof["toxin"])
	if mode == "eat":
		if tox > 0 and not infected and item_bonus("toxin_immune") == 0:
			tox_loss = mini(tox * int(DB.nutrition()["toxin_hp"]), maxi(0, hp - 1))
			hp -= tox_loss
		log_meal(meal_pts(prof), prof, "eat")
		add_nutrition(prof, float(mm[fit]["nutrients"]))
	else:
		log_meal(float(DB.nutrition()["fill_pts"]), prof, "fill")
	var sp := 0
	if infected:
		sp = 2
		spores += sp
	stats["eaten"] += 1
	return {"hunger": food, "heal": heal, "toxin_hp": tox_loss, "spores": sp, "profile": prof, "mode": mode, "fit": meal_fit_label(prof)}

## Evolution branches offered when you evolve into `tier` (2..4). Standard growth is always available separately.
func branch_options(tier: int) -> Array:
	var rows: Array = DB.nutrition()["branches"].get(diet_id(), {}).get(str(tier), [])
	var out: Array = []
	for b in rows:
		var req: Dictionary = b["requires"]
		var prog: Array = []
		var met := true
		for k in req:
			var have := 0.0
			var need := float(req[k])
			var ok_k := true
			match String(k):
				"diet_score":
					have = float(diet_score())
					ok_k = have >= need
					prog.append({"label": "Diet score", "have": have, "need": need, "ok": ok_k})
				"max_toxin":
					have = float(nutrition["toxin"])
					ok_k = have <= need
					prog.append({"label": "Toxins at most", "have": have, "need": need, "ok": ok_k})
				_:
					have = float(nutrition.get(k, 0.0))
					ok_k = have >= need
					prog.append({"label": String(DB.nutrition()["nutrients"][k]["name"]), "have": have, "need": need, "ok": ok_k})
			if not ok_k:
				met = false
		var o: Dictionary = b.duplicate(true)
		o["unlocked"] = met
		o["progress"] = prog
		out.append(o)
	return out

## Pick a branch ("" = standard). Returns extra drafts to queue. Locked branches cannot be chosen.
func choose_branch(tier: int, id: String) -> Array:
	branches[str(tier)] = id
	if id == "":
		return []
	for b in branch_options(tier):
		if b["id"] == id:
			if not b["unlocked"]:
				branches[str(tier)] = ""
				return []
			add_item(String(b["item"]))
			return b.get("extra_drafts", []).duplicate()
	return []

func branch_name() -> String:
	var best := ""
	for t in ["4", "3", "2"]:
		var id := String(branches.get(t, ""))
		if id != "":
			for b in DB.nutrition()["branches"].get(diet_id(), {}).get(t, []):
				if b["id"] == id:
					return String(b["name"])
	return best

func summary() -> Dictionary:
	return {"seed": seed_val, "level": level, "form": form()["name"], "rooms": cleared_rooms, "stage": stage_idx + 1,
		"kills": stats["kills"], "victory": victory, "cause": cause, "deck": deck.size()}

func synergy_summary() -> Dictionary:
	return {"main": Arch.main_tag(deck, items), "counts": Arch.counts(deck, items)}
var difficulty: String = "normal"
