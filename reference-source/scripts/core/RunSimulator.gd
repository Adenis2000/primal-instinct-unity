class_name RunSimulator
extends RefCounted
## Headless full-run driver (no UI): the same rules/flow as the screens, with a bot making choices.
## Used by tests/run_tests.gd and for balance experiments.

## eat_policy: "all" (Eat every kill), "gorge" (Just fill up on every kill), "never", "fit" (selective: Eat Great/Okay meals,
## fill up on others only when hungry), "hungry" (Eat when below 60% hunger).
## opts: smart (bool, competent tactics + door choice), archetype ("" | ambush | bleed | flank | speed | hitrun | scavenger: the bot drafts
## cards/items of that archetype), difficulty (id from data/difficulty.json).
static func simulate(seed_in: int, verbose: bool = false, eat_policy: String = "all", opts: Dictionary = {}) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_in * 7 + 1
	var run := RunState.create("velociraptor", seed_in)
	if opts.has("difficulty"):
		run.difficulty = String(opts["difficulty"])
	run.begin_stage(0)
	run.set_meta("opts", opts)
	var out := {"seed": seed_in, "victory": false, "rooms": 0, "level": 1, "form": "", "battles": 0, "timeouts": 0,
		"ambush": 0, "sneak_ok": 0, "sneak_fail": 0, "events": 0, "puzzles": 0, "forage": 0, "weather": [], "log": [], "cause": "", "max_stage": 1, "elite": 0, "boss": 0, "items": 0, "branches": 0, "locked_seen": 0}
	run.set_meta("eat_policy", eat_policy)
	out["weather"].append(run.weather_id())
	var guard := 0
	while not run.game_over and not run.victory and guard < 100:
		guard += 1
		var doors := run.current_step_doors()
		if doors.is_empty():
			break
		var di := rng.randi() % doors.size()
		if bool(opts.get("smart", false)):
			di = AutoPlayer.pick_door(run, doors, rng)
		var room := run.choose_door(di)
		run.enter_room(room)
		out["rooms"] += 1
		if run.game_over:
			break
		var t := String(room["type"])
		match t:
			"battle", "elite", "boss":
				var ok := _fight(run, room, rng, out)
				if not ok:
					break
			"event":
				out["events"] += 1
				var ev: Dictionary = DB.table("events")["events"][room["event_id"]]
				var ch: Dictionary = ev["choices"][rng.randi() % ev["choices"].size()]
				var ctx := {}
				run.resolve_outcome(ch, ctx)
				if ctx.has("battle") and not run.game_over:
					var br := {"type": "battle", "enemies": ctx["battle"]["enemies"], "infected": ctx["battle"]["enemies"].map(func(_e): return false), "seed": rng.randi(), "unspotted_allowed": ctx["battle"]["unspotted"]}
					if not _fight(run, br, rng, out):
						break
			"forage":
				out["forage"] += 1
				var fg: Dictionary = DB.table("events")["forage"]
				var id: String = room["forage_ids"][rng.randi() % room["forage_ids"].size()]
				run.resolve_outcome(fg[id], {})
			"puzzle":
				out["puzzles"] += 1
				var p := SequencePuzzle.from_room(room)
				var pdef: Dictionary = DB.table("puzzles")[room["puzzle_id"]]
				var fin := false
				while not fin:
					# bot is 80% accurate per press
					var want := int(p.sequence[p.pos])
					var press := want if rng.randf() < 0.8 else (want + 1) % p.buttons
					var r := p.press(press)
					if r == "done":
						run.apply_effects(pdef["reward"])
						fin = true
					elif r == "wrong":
						run.apply_effects(pdef["mistake_effects"])
					elif r == "fail":
						run.apply_effects(pdef["mistake_effects"])
						fin = true
		if run.game_over:
			break
		# evolution draft owed?
		if run.pending_evolution_tier > 0:
			var tier := run.pending_evolution_tier
			var extra: Array = []
			var bopts: Array = run.branch_options(tier)
			var arch := String(opts.get("archetype", ""))
			if arch != "":
				bopts.sort_custom(func(x, y): return (arch in DB.item(String(x["item"])).get("tags", [])) and not (arch in DB.item(String(y["item"])).get("tags", [])))
			for o in bopts:
				if o["unlocked"]:
					extra = run.choose_branch(tier, String(o["id"]))
					out["branches"] += 1
					break
				else:
					out["locked_seen"] += 1
			var offer := run.offer_cards(3, "evolution")
			if not offer.is_empty():
				run.add_card(AutoPlayer.pick_card(run, offer, opts, rng))
			for m in extra:
				var o2 := run.offer_cards(3, String(m))
				if not o2.is_empty():
					run.add_card(AutoPlayer.pick_card(run, o2, opts, rng))
			run.pending_evolution_tier = 0
		var res := run.complete_room()
		if res == "stage_clear":
			if not run.advance_stage():
				break
			out["max_stage"] = run.stage_idx + 1
			out["weather"].append(run.weather_id())
	out["victory"] = run.victory
	out["level"] = run.level
	out["form"] = String(run.form()["name"])
	out["cause"] = run.cause
	out["deck"] = run.deck.size()
	out["hunger"] = run.hunger
	out["diet_quality"] = run.diet_quality()
	out["diet_score"] = run.diet_score()
	out["synergy"] = run.synergy_summary()
	return out

static func _fight(run: RunState, room: Dictionary, rng: RandomNumberGenerator, out: Dictionary) -> bool:
	var t := String(room.get("type", "battle"))
	var mode := "spotted"
	if room.get("unspotted_allowed", false):
		var roll := rng.randf()
		if bool(run.get_meta("opts", {}).get("smart", false)):
			roll = rng.randf() * 0.7   # a competent player ambushes whenever the room allows it
		if roll < 0.65:
			mode = "ambush"
			out["ambush"] += 1
		elif roll < 0.85:
			if rng.randf() < Battle.sneak_chance(run, room):
				out["sneak_ok"] += 1
				return true   # slipped past: no rewards
			out["sneak_fail"] += 1
	var b := Battle.create(run, room, mode)
	b.begin()
	var sopts: Dictionary = run.get_meta("opts", {})
	var r := AutoPlayer.play(b, rng, 0.9, 60, bool(sopts.get("smart", false)))
	b.commit_to_run()
	out["battles"] += 1
	if t == "elite":
		out["elite"] += 1
	if t == "boss":
		out["boss"] += 1
	if r["timeout"]:
		out["timeouts"] += 1
		out["timeout_room"] = String(room.get("enemies", []).hash() if false else str(room.get("enemies", [])))
		run.game_over = true
		run.cause = "timeout"
		return false
	if b.phase != "won":
		out["died_in"] = "s%d %s" % [run.stage_idx + 1, ",".join(room.get("enemies", []))]
		return false
	var res := b.result()
	run.grant_xp(int(res["xp"]))
	var pol := String(run.get_meta("eat_policy", "all"))
	for c in res["corpses"]:
		var emode := "eat"
		var prof := RunState.meal_profile(String(c["id"]), bool(c["infected"]))
		match pol:
			"never":
				emode = ""
			"gorge":
				emode = "fill"
			"fit":
				var fit := run.meal_fit_label(prof)
				if fit == "Great" or fit == "Okay":
					emode = "eat"
				elif float(run.hunger) < 0.28 * run.hunger_max() and fit != "Harmful":
					emode = "fill"
				else:
					emode = ""
			"hungry":
				emode = "eat" if float(run.hunger) < 0.6 * run.hunger_max() else ""
		if emode != "":
			run.eat_corpse(c, emode)
	if t == "battle" or t == "elite" or t == "boss":
		var offer := run.offer_cards(3, "elite" if t != "battle" else "normal")
		if not offer.is_empty():
			run.add_card(AutoPlayer.pick_card(run, offer, run.get_meta("opts", {}), rng))
		var src := "boss" if t == "boss" else t
		if src == "boss" or run.item_drop(src):
			var io := run.offer_items(src)
			if not io.is_empty():
				run.add_item(AutoPlayer.pick_item(run, io, run.get_meta("opts", {}), rng))
				out["items"] += 1
	return true
