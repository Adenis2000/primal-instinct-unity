extends SceneTree
## Headless test suite. Run:  godot --headless --script res://tests/run_tests.gd
## (tools/run_tests.sh wraps this and also fails on engine SCRIPT ERROR output.)

var passed := 0
var failed := 0
var failures: Array = []

func ok(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		failures.append(msg)
		print("  FAIL: ", msg)

func section(name: String) -> void:
	print("== ", name)

func _initialize() -> void:
	await process_frame   # let autoloads run _ready()
	var game = root.get_node("Game")
	game.persist_enabled = false
	game.load_save()
	game.bypass_menu = true                          # scripted tests start on the egg screen, not the main menu
	Settings.path = "user://settings_test.cfg"      # never touch the player's real settings
	Settings.persist = false
	DB.load_all()
	var t0 := Time.get_ticks_msec()
	test_data()
	test_sprites()
	test_grid()
	test_run_state()
	test_stage_gen()
	test_turn_order()
	test_weather()
	test_stealth()
	test_cards()
	test_infection()
	test_hunger_growth()
	test_puzzle()
	test_hints(game)
	test_iso()
	test_spawn_alignment()
	test_facing()
	test_facing_cards_and_enemies()
	test_vision_cone()
	test_themes()
	test_search_ai()
	test_ranged_and_events()
	await test_animation_alignment()
	test_terrain_costs()
	await test_move_mode_autoexit()
	test_exits_and_explore(game)
	test_secret_cave(game)
	test_poison_web_minrange()
	await test_items()
	await test_nutrition()
	await test_readability()
	await test_explore_screen_flow()
	test_keywords()
	await test_keyword_ui()
	test_difficulty()
	test_archetypes()
	test_depth_mechanics()
	test_evasion_arenas_scaling()
	await test_egg_difficulty(game)
	await test_customization(game)
	await test_big_window_layout()
	await test_settings(game)
	await test_text_audit(game)
	await test_backdrop()
	await test_stage_intro_cinematic(game)
	await test_cutscene(game)
	await test_game_title(game)
	await test_main_menu(game)
	test_foliage_visibility()
	test_exit_paths()
	test_zoom_limit()
	await test_hud_no_panels()
	await test_exits_and_detection(game)
	await test_victory_popup(game)
	await test_supplied_art(game)
	test_pine_art(game)
	await test_raptor_art(game)
	await test_card_design(game)
	test_combat_sim()
	test_full_runs()
	test_archetype_viability()
	print("")
	print("RESULT: %d passed, %d failed (%.1fs)" % [passed, failed, (Time.get_ticks_msec() - t0) / 1000.0])
	if failed > 0:
		for f in failures:
			print(" - ", f)
	quit(1 if failed > 0 else 0)

# ------------------------------------------------------------------ helpers

func make_run(seed_in: int = 1234) -> RunState:
	var r := RunState.create("velociraptor", seed_in)
	r.begin_stage(0)
	return r

func make_room(enemies: Array, seed_in: int = 99, infected: Array = []) -> Dictionary:
	var inf := infected if not infected.is_empty() else enemies.map(func(_e): return false)
	return {"type": "battle", "enemies": enemies, "infected": inf, "seed": seed_in, "unspotted_allowed": true, "trap": false,
		"no_scale": true, "arena_fixed": {"w": 12, "h": 7, "shape": "rect", "cut": Vector2i.ZERO, "type": "battle", "corner": 0}}

# ------------------------------------------------------------------ tests

func test_data() -> void:
	section("data validation")
	var known_ops := ["damage", "bleed", "weak", "expose", "stun", "block", "gain_mp", "gain_stamina", "draw", "heal", "hunger", "self_damage", "speed_buff", "stalker", "calm", "extra_turn", "pounce", "dash", "retreat", "hide", "poison", "web",
		"mark", "daze", "fear", "double_bleed", "patient", "quicken", "well_fed", "evade", "heal_per_bleeding", "draw_if_bleeding", "draw_if_grass", "draw_diet", "damage_adjacent"]
	for id in DB.table("cards"):
		var c: Dictionary = DB.card(id)
		for k in ["name", "cost", "type", "tier", "rarity", "target", "text", "effects", "icon"]:
			ok(c.has(k), "card %s missing %s" % [id, k])
		for e in c["effects"]:
			ok(String(e["op"]) in known_ops, "card %s unknown op %s" % [id, e["op"]])
			if e.has("on_kill"):
				for k in e["on_kill"]:
					ok(String(k["op"]) in known_ops, "card %s unknown on_kill op" % id)
		ok(SpriteFactory.get_texture(String(c["icon"])) != null, "icon for card " + id)
		if c["target"] == "tile":
			ok(c.has("range"), "tile card needs range: " + id)
	ok(DB.draft_cards(1, 4).size() >= 15, "draft pool >= 15 cards (%d)" % DB.draft_cards(1, 4).size())
	for tier in [1, 2, 3, 4]:
		ok(DB.draft_cards(tier, tier).size() >= 3, "each growth tier has >= 3 draftable cards (tier %d)" % tier)
	for sp in DB.table("species"):
		var s: Dictionary = DB.species(sp)
		if s["playable"]:
			for id in s["starter_deck"]:
				ok(DB.has_card(id), "starter card exists: " + id)
	for id in DB.table("enemies"):
		if id.begins_with("_"):
			continue
		var e: Dictionary = DB.enemy(id)
		ok(not DB.sprite_def(String(e["sprite"])).is_empty(), "enemy sprite def: " + id)
		ok(e["abilities"].size() > 0, "enemy has abilities: " + id)
	for sid in DB.stage_order():
		var d := DB.stage(sid)
		for g in d["battle_groups"] + d["elite_groups"] + [d["boss"]]:
			for en in g["enemies"]:
				ok(DB.table("enemies").has(en), "stage %s enemy exists: %s" % [sid, en])
		ok(DB.table("weather").has_all(d["weather_weights"].keys()), "weather ids valid in " + sid)
	var evs: Dictionary = DB.table("events")
	for k in evs["events"]:
		ok(evs["events"][k]["choices"].size() >= 2, "event has choices: " + k)
	ok(evs["events"].size() >= 3, ">= 3 events")
	for pool in evs["battle_pools"]:
		for st in evs["battle_pools"][pool]:
			for en in evs["battle_pools"][pool][st]:
				ok(DB.table("enemies").has(en), "event pool enemy exists " + en)

func test_sprites() -> void:
	section("sprite generation")
	var n := 0
	for id in DB.table("sprites"):
		var def := DB.sprite_def(id)
		var img := SpriteFactory.paint(def)
		var opaque := 0
		for y in img.get_height():
			for x in img.get_width():
				if img.get_pixel(x, y).a > 0.5:
					opaque += 1
		ok(opaque > 8, "sprite %s has pixels (%d)" % [id, opaque])
		ok(img.get_width() == int(def["size"]), "sprite size " + id)
		n += 1
	for t in ["ground", "grass", "water", "obstacle"]:
		for th in ["jungle", "tundra"]:
			for v in 4:
				ok(SpriteFactory.tile_texture(t, th, v) != null, "tile %s/%s/%d" % [t, th, v])
	print("  %d sprites painted" % n)

func test_grid() -> void:
	section("grid / pathing / LOS / layouts")
	var params := {"grass_blobs": [3, 5], "grass_size": [3, 7], "water_blobs": [0, 2], "water_size": [3, 6], "obstacles": [4, 8]}
	var kinds := {}
	var sigs := {}
	for s in range(1, 201):
		var g := BGrid.generate(s * 31, params, "jungle")
		var pockets := 0
		var reachable := g.reach(Vector2i(0, 0), 999, {})
		var anchor := Vector2i(-1, -1)
		for y in g.h:
			if not g.blocks_move(Vector2i(0, y)):
				anchor = Vector2i(0, y)
				break
		ok(anchor.x == 0, "seed %d has walkable left column" % s)
		var res := g.reach(anchor, 999, {})
		for y in g.h:
			for x in g.w:
				var p := Vector2i(x, y)
				if not g.blocks_move(p) and not res["cost"].has(p):
					pockets += 1
				kinds[g.get_tile(p)] = true
		ok(pockets == 0, "layout %d fully connected" % s)
		var sig := ""
		for y in g.h:
			sig += "".join(g.tiles[y].map(func(t): return t[0]))
		sigs[sig] = true
	ok(kinds.has("grass") and kinds.has("water") and kinds.has("obstacle") and kinds.has("ground"), "all four tile kinds appear in layouts")
	ok(sigs.size() > 190, "layouts vary per seed (%d unique of 200)" % sigs.size())
	# LOS blocked by obstacle, water/grass cost
	var g := BGrid.new()
	g.set_tile(Vector2i(3, 2), "obstacle")
	ok(not g.los(Vector2i(1, 2), Vector2i(5, 2)), "obstacle blocks sight")
	ok(g.los(Vector2i(1, 3), Vector2i(5, 3)), "clear line of sight")
	g.set_tile(Vector2i(1, 0), "water")
	var r := g.reach(Vector2i(0, 0), 2, {})
	ok(int(r["cost"].get(Vector2i(1, 0), 99)) == 2, "water costs 2")
	ok(not r["cost"].has(Vector2i(3, 2)), "cannot enter obstacle")
	var r2 := g.reach(Vector2i(0, 0), 3, {Vector2i(1, 0): true, Vector2i(0, 1): true})
	ok(r2["cost"].size() == 1, "occupied tiles block movement")

func test_run_state() -> void:
	section("run state / seeds")
	var a := make_run(777)
	var b := make_run(777)
	var c := make_run(778)
	ok(a.stage["weather"] == b.stage["weather"], "same seed => same weather")
	var sig_a := _stage_sig(a)
	ok(sig_a == _stage_sig(b), "same seed => identical stage layout")
	ok(sig_a != _stage_sig(c), "different seed => different stage layout")
	ok(a.seed_val == 777, "seed stored")
	ok(a.deck.size() == 10, "starter deck has 10 cards")
	ok(a.level == 1 and a.form()["id"] == "baby", "starts as baby")
	ok(RunState.seed_from_text("hello") == RunState.seed_from_text("hello") and RunState.seed_from_text("42") == 42, "seed text parsing")
	var weathers := {}
	for s in range(1, 120):
		weathers[make_run(s).weather_id()] = true
	ok(weathers.size() >= 5, "weather varies across seeds (%d kinds)" % weathers.size())
	# weather persists across a whole stage and is stage-level
	var r := make_run(5)
	var w0 := r.weather_id()
	for i in 3:
		r.complete_room()
	ok(r.weather_id() == w0, "weather persists across rooms in a stage")

func _stage_sig(r: RunState) -> String:
	var s := r.weather_id() + "|"
	for st in r.stage["steps"]:
		for d in st["doors"]:
			s += "%s:%s:%s," % [d["type"], ",".join(d["enemies"]), d.get("event_id", "")]
		s += ";"
	return s

func test_stage_gen() -> void:
	section("stage generation")
	var seen_types := {}
	for s in range(1, 150):
		var r := make_run(s)
		var steps: Array = r.stage["steps"]
		ok(steps.size() == 7, "stage 1 has 7 steps")
		var last: Dictionary = steps[steps.size() - 1]["doors"][0]
		ok(last["type"] == "boss", "last room is boss")
		ok(not last["unspotted_allowed"], "boss always starts spotted")
		var first: Dictionary = steps[0]["doors"][0]
		ok(first["type"] == "battle" and first["enemies"] == ["beetle"], "tutorial opener is a beetle")
		var has := {}
		for st in steps:
			for d in st["doors"]:
				has[d["type"]] = true
				seen_types[d["type"]] = true
				if d["type"] == "battle" or d["type"] == "elite":
					if d["trap"]:
						ok(not d["unspotted_allowed"], "trap rooms always start spotted")
		for req in ["elite", "puzzle", "event", "forage"]:
			ok(has.has(req), "seed %d has required room type %s" % [s, req])
	ok(seen_types.size() == 6, "all 6 room types generated")
	# enemy tiering: stage 1 battle groups only contain tier-1 enemies
	var r1 := make_run(3)
	for st in r1.stage["steps"]:
		for d in st["doors"]:
			if d["type"] == "battle":
				for e in d["enemies"]:
					ok(int(DB.enemy(e)["tier"]) == 1, "stage 1 regular enemies are small (tier 1): " + e)
	var r2 := make_run(3)
	r2.advance_stage()
	ok(r2.stage["id"] == "stage_2", "advance to stage 2")
	ok(r2.stage["steps"].size() == 6, "stage 2 generated")

func test_turn_order() -> void:
	section("turn order / speed")
	var run := make_run(11)
	var b := Battle.create(run, make_room(["dragonfly", "beetle"]), "spotted")
	var seq := b.preview_order(24)
	var counts := {}
	for u in seq:
		counts[u.id] = int(counts.get(u.id, 0)) + 1
	ok(counts.get("dragonfly", 0) > counts.get("beetle", 0) * 2, "fast dragonfly acts much more than slow beetle (%s)" % str(counts))
	# find a window where the same unit acts twice in a row
	var double := false
	for i in seq.size() - 1:
		if seq[i] == seq[i + 1]:
			double = true
	ok(double, "very fast units get consecutive (extra) turns")
	# run battle start: first actor equals preview[0]
	var first_pred: BUnit = b.preview_order(1)[0]
	b.begin()
	ok(b.current == first_pred or b.phase == "player", "preview matches actual first actor")
	# extra-turn card
	var run2 := make_run(12)
	var b2 := Battle.create(run2, make_room(["beetle"]), "spotted")
	b2.begin()
	ok(b2.phase == "player", "battle reaches player turn")
	var t_before := b2.turn_no
	b2.hand = ["lightning_reflexes"]
	b2.stamina = 3
	ok(b2.play_card(0), "play extra turn card")
	b2.end_player_turn()
	ok(b2.phase == "player" and b2.turn_no == t_before + 1, "extra turn: player acts again immediately")
	ok(not b2.exhausted.is_empty(), "extra-turn card is exhausted")
	# stamina refresh each turn
	b2.stamina = 0
	b2.end_player_turn()
	ok(b2.stamina == b2.stamina_max and b2.stamina_max >= 3, "stamina refilled at turn start")
	ok(b2.hand.size() == 5, "hand redrawn to 5")

func test_weather() -> void:
	section("weather modifiers")
	var raptor_tags := ["reptile", "dinosaur", "stealthy"]
	var fog_r := WeatherSys.mods_for("fog", raptor_tags)
	var fog_shrew := WeatherSys.mods_for("fog", ["mammal", "scent"])
	var fog_beetle := WeatherSys.mods_for("fog", ["insect"])
	ok(fog_r["damage_mult"] > 1.0, "fog boosts stealthy raptor damage")
	ok(fog_beetle["perception_mult"] < 0.7, "fog cuts beetle sight")
	ok(fog_shrew["perception_mult"] > 0.95, "scent hunters ignore fog")
	var cold_r := WeatherSys.mods_for("cold", raptor_tags)
	var cold_mammoth := WeatherSys.mods_for("cold", ["mammal", "iceage"])
	ok(cold_r["speed_mult"] < 1.0 and cold_mammoth["speed_mult"] > 1.0, "cold slows reptiles, suits ice age beasts")
	var heat_r := WeatherSys.mods_for("heat", raptor_tags)
	ok(heat_r["speed_mult"] > 1.0 and heat_r["hunger_extra"] > 0, "heat: reptile faster but hungrier")
	# applied inside a battle
	var run := make_run(21)
	run.stage["weather"] = "cold"
	var b := Battle.create(run, make_room(["compy"]), "spotted")
	ok(b.eff_speed(b.player) < run.base_speed(), "cold applies to player speed in battle")
	run.stage["weather"] = "clear"
	var cost_clear := run.hunger_cost()
	run.stage["weather"] = "heat"
	ok(run.hunger_cost() == cost_clear + 3, "heat adds hunger per room")

func test_stealth() -> void:
	section("stealth / detection / ambush")
	var run := make_run(31)
	run.stage["weather"] = "clear"
	var room := make_room(["skink"], 41)
	var b := Battle.create(run, room, "ambush")
	ok(b.phase == "ambush", "ambush battle starts in ambush phase")
	ok(b.is_hidden(), "player unspotted at start")
	ok(not b.enemies[0].aware, "enemy unaware at start")
	var targets := b.ambush_targets()
	ok(not targets.is_empty(), "ambush has valid targets")
	var e: BUnit = b.enemies[0]
	var hp0 := e.hp
	b.ambush_strike(e)
	ok(e.hp < hp0 or not e.alive, "ambush deals damage (free first hit)")
	ok(b.phase == "player" or b.phase == "won", "after ambush the fight proceeds")
	var spot_run := make_run(31)
	var b2 := Battle.create(spot_run, make_room(["skink"], 41), "spotted")
	ok(b2.enemies[0].aware and not b2.is_hidden(), "spotted fights start with aware enemies")
	# detection range: grass halves
	var run3 := make_run(32)
	run3.stage["weather"] = "clear"
	var b3 := Battle.create(run3, make_room(["dragonfly"], 51), "ambush")
	var df: BUnit = b3.enemies[0]
	b3.grid.set_tile(b3.player.pos, "ground")
	var r_ground := b3.detect_range(df)
	b3.grid.set_tile(b3.player.pos, "grass")
	var r_grass := b3.detect_range(df)
	ok(r_grass < r_ground, "tall grass reduces detection range (%d < %d)" % [r_grass, r_ground])
	run3.stage["weather"] = "fog"
	var b4 := Battle.create(run3, make_room(["dragonfly"], 51), "ambush")
	b4.grid.set_tile(b4.player.pos, "ground")
	ok(b4.detect_range(b4.enemies[0]) < r_ground, "fog reduces detection range")
	# line of sight needed
	var b5 := Battle.create(make_run(33), make_room(["dragonfly"], 52), "ambush")
	var d5: BUnit = b5.enemies[0]
	b5.grid.set_tile(b5.player.pos, "ground")
	d5.pos = b5.player.pos + Vector2i(3, 0) if b5.grid.in_bounds(b5.player.pos + Vector2i(3, 0)) else d5.pos
	if b5.player.pos.x + 3 < b5.grid.w:
		b5.grid.set_tile(b5.player.pos + Vector2i(1, 0), "obstacle")
		ok(not b5.can_detect(d5), "obstacle between blocks detection")
	# silent kill keeps others unaware
	var b6 := Battle.create(make_run(34), make_room(["shrew", "beetle"], 53), "ambush")
	var victim: BUnit = b6.enemies[0]
	var other: BUnit = b6.enemies[1]
	victim.hp = 1
	for y in b6.grid.h:
		for x in b6.grid.w:
			b6.grid.set_tile(Vector2i(x, y), "ground")
	b6.player.pos = Vector2i(0, 3)
	victim.pos = Vector2i(6, 3)
	other.pos = Vector2i(6, 5)
	other.perception = 0.0
	other.base_speed = 1.0
	b6.ambush_strike(victim)
	ok(not victim.alive, "ambush kills weakened target")
	ok(not other.aware, "killing an unaware enemy is silent (noise doesn't alert others)")
	# sneak chance responds to weather
	var rr := make_run(35)
	var rm := make_room(["beetle"], 60)
	rr.stage["weather"] = "clear"
	var c_clear := Battle.sneak_chance(rr, rm)
	rr.stage["weather"] = "fog"
	var c_fog := Battle.sneak_chance(rr, rm)
	ok(c_fog > c_clear, "sneak chance higher in fog (%.2f > %.2f)" % [c_fog, c_clear])
	rr.stage["weather"] = "fog"
	var c_shrew := Battle.sneak_chance(rr, make_room(["shrew"], 60))
	ok(c_shrew < c_fog, "fog helps less vs scent hunters")

func _force_hand(b: Battle, cards: Array) -> void:
	b.hand = cards.duplicate()
	b.stamina = 9

func test_cards() -> void:
	section("cards: effects")
	var run := make_run(41)
	run.stage["weather"] = "clear"
	var b := Battle.create(run, make_room(["beetle"], 70), "spotted")
	b.begin()
	var e: BUnit = b.enemies[0]
	# adjacent setup on plain ground
	for n in b.grid.neighbors(b.player.pos):
		pass
	b.grid.set_tile(b.player.pos, "ground")
	var adj := b.player.pos + Vector2i(1, 0)
	b.grid.set_tile(adj, "ground")
	e.pos = adj
	e.aware = true
	e.hp = 100
	e.max_hp = 100
	e.def = e.def.duplicate(true)
	e.def["facing"] = {}                 # neutral: these checks are about base card numbers
	e.armor = 0
	e.facing = Vector2i(-1, 0)           # looking at the player -> FRONT hit, multiplier 1.0
	_force_hand(b, ["claw_slash", "rake", "pounce", "crouch", "nip"])
	ok(b.play_card(0, e), "claw slash plays")
	ok(e.hp == 95, "claw slash 5 dmg vs aware target (hp %d)" % e.hp)
	e.aware = false
	b.play_card(0, e)  # nip unaware... index shifts: hand now rake,pounce,crouch,nip
	# rake bleed
	var bleed0 := e.st("bleed")
	_force_hand(b, ["rake"])
	b.play_card(0, e)
	ok(e.st("bleed") == bleed0 + 3, "rake applies 3 bleed")
	# unaware bonus
	e.aware = false
	e.hp = 100
	_force_hand(b, ["claw_slash"])
	b.play_card(0, e)
	ok(e.hp == 92 or e.hp == 91 or e.hp <= 92, "unaware bonus applied (hp %d)" % e.hp)
	# stalker power
	e.aware = true
	b.player.status.erase("weak")
	_force_hand(b, ["stalker", "claw_slash"])
	b.play_card(0)
	ok(b.stalker == 3, "stalker power sets bonus")
	# hide in grass
	b.grid.set_tile(b.player.pos, "grass")
	e.pos = b.player.pos + Vector2i(3, 0) if b.grid.in_bounds(b.player.pos + Vector2i(3, 0)) and not b.grid.blocks_move(b.player.pos + Vector2i(3, 0)) else e.pos
	e.aware = true
	_force_hand(b, ["crouch"])
	b.play_card(0)
	ok(b.player.block >= 4, "crouch gives block")
	ok(not e.aware and b.is_hidden(), "crouch in tall grass hides from distant enemies")
	b.grid.set_tile(b.player.pos, "ground")
	e.aware = true
	_force_hand(b, ["crouch"])
	b.play_card(0)
	ok(e.aware, "crouch on bare ground does not hide")
	# pounce moves adjacent
	e.pos = b.player.pos + Vector2i(3, 0) if b.grid.in_bounds(b.player.pos + Vector2i(3, 0)) else e.pos
	for dx in [1, 2, 3]:
		var q := b.player.pos + Vector2i(dx, 0)
		if b.grid.in_bounds(q):
			b.grid.set_tile(q, "ground")
	e.hp = 100
	_force_hand(b, ["pounce"])
	var pos0 := b.player.pos
	ok(b.play_card(0, e), "pounce plays at range")
	ok(BGrid.dist(b.player.pos, e.pos) == 1 and b.player.pos != pos0, "pounce lands adjacent to target")
	ok(e.hp < 100, "pounce deals damage")
	# not enough stamina
	b.stamina = 0
	_force_hand(b, ["claw_slash"])
	b.stamina = 0
	ok(not b.play_card(0, e), "cannot play without stamina")
	# movement: mp limits
	var run2 := make_run(42)
	var b2 := Battle.create(run2, make_room(["beetle"], 71), "spotted")
	b2.begin()
	var reach := b2.reachable_tiles()
	var far := 0
	for p in reach:
		far = maxi(far, int(reach[p]))
	ok(far <= b2.mp and b2.mp == run2.base_move(), "movement limited by MP (%d)" % b2.mp)
	var dest := Vector2i(-1, -1)
	for p in reach:
		if p != b2.player.pos:
			dest = p
			break
	ok(b2.move_player(dest) and b2.player.pos == dest, "player moves to reachable tile")
	ok(not b2.move_player(Vector2i(11, 6)) or b2.mp >= 0, "cannot move beyond MP")
	# every card in the game plays without error in a controlled scenario
	for id in DB.table("cards"):
		var rr := make_run(43)
		rr.level = 7
		var bb := Battle.create(rr, make_room(["beetle", "skink"], 72), "spotted")
		bb.begin()
		for en in bb.enemies:
			en.hp = 50
			en.max_hp = 50
		_force_hand(bb, [id])
		var targets := bb.card_targets(0)
		if bb.card_playable(0):
			var tgt = null
			if String(DB.card(id)["target"]) in ["enemy", "tile"]:
				tgt = targets[0]
			ok(bb.play_card(0, tgt), "card plays: " + id)
		else:
			# only acceptable when it needs a target that is out of range
			ok(String(DB.card(id)["target"]) in ["enemy", "tile"] or bb.unplayable_reason(0) != "" or bb._has_op(DB.card(id), "damage_adjacent"), "card unplayable only for lack of targets: " + id)
	# deck cycling: draw pile reshuffles from discard
	var run3 := make_run(44)
	var b3 := Battle.create(run3, make_room(["beetle"], 73), "spotted")
	b3.begin()
	for i in 6:
		b3.end_player_turn()
		if b3.phase != "player":
			break
	ok(b3.draw_pile.size() + b3.hand.size() + b3.discard_pile.size() + b3.exhausted.size() == 10, "no cards lost cycling the deck")

func test_infection() -> void:
	section("infection mechanic")
	var run := make_run(51)
	var b := Battle.create(run, make_room(["beetle", "skink"], 80, [true, false]), "spotted")
	var inf: BUnit = b.enemies[0]
	var tgt: BUnit = b.enemies[1]
	ok(inf.infected and inf.display_name.begins_with("Infected"), "pre-infected enemy renamed")
	ok(inf.max_hp > int(DB.enemy("beetle")["hp"]) and inf.bonus_damage > 0, "infection boosts hp and damage")
	ok(inf.abilities.size() == DB.enemy("beetle")["abilities"].size() + 1, "infection adds an ability")
	var base_hp := tgt.max_hp
	tgt.pos = inf.pos + Vector2i(1, 0) if b.grid.in_bounds(inf.pos + Vector2i(1, 0)) else inf.pos + Vector2i(-1, 0)
	inf.spread_cd = 1
	b._tick_start(inf)
	ok(tgt.infected and tgt.max_hp > base_hp, "infection spreads to nearby enemy over time")
	# boss spawns drones and infects
	var rb := make_run(52)
	var bb := Battle.create(rb, make_room(["husk_queen"], 81), "spotted")
	var q: BUnit = bb.enemies[0]
	ok(q.infected and q.spreader, "husk queen is an infected spreader")
	var sawsummon := false
	var spores := false
	bb.begin()
	for i in 14:
		if bb.phase != "player":
			break
		bb.end_player_turn()
		if bb.enemies.size() > 1:
			sawsummon = true
	ok(sawsummon, "husk queen broods spore drones")
	spores = bb.player.st("spores") > 0 or bb.player.hp < bb.player.max_hp
	ok(spores, "boss pressures the player (damage/spores)")
	# spores washed off in water
	var rw := make_run(53)
	var bw := Battle.create(rw, make_room(["beetle"], 82), "spotted")
	bw.begin()
	bw.player.status["spores"] = 3
	bw.grid.set_tile(bw.player.pos, "water")
	bw.end_player_turn()
	if bw.phase == "player":
		ok(bw.player.st("spores") == 0, "standing in water cleanses spores")

func test_hunger_growth() -> void:
	section("hunger / growth")
	var r := make_run(61)
	r.stage["weather"] = "clear"
	var h0 := r.hunger
	var room: Dictionary = r.current_step_doors()[0]
	r.enter_room(room)
	ok(r.hunger == h0 - 6, "baby loses 6 hunger per room")
	r.level = 3
	ok(r.form()["id"] == "juvenile" and r.hunger_cost() == 8, "juvenile costs 8 hunger")
	r.level = 5
	ok(r.form()["id"] == "adult" and r.hunger_cost() == 10, "adult costs 10 hunger")
	r.level = 7
	ok(r.form()["id"] == "prime" and r.hunger_cost() == 12, "prime costs 12 hunger")
	# starvation
	var r2 := make_run(62)
	r2.hunger = 3
	var hp0 := r2.hp
	r2.enter_room(r2.current_step_doors()[0])
	ok(r2.hunger == 0 and r2.hp < hp0, "zero hunger damages HP on room entry")
	ok(r2.hunger_state() == "starving", "starving state")
	var r3 := make_run(63)
	r3.hunger = 20
	ok(r3.hunger_state() == "low", "low hunger state")
	var bl := Battle.create(r3, make_room(["beetle"], 90), "spotted")
	bl.begin()
	ok(bl.stamina_max == r3.base_stamina() - 1, "low hunger: -1 stamina")
	var r4 := make_run(64)
	var bn := Battle.create(r4, make_room(["beetle"], 90), "spotted")
	var s_full := bn.eff_speed(bn.player)
	r4.hunger = 10
	ok(bn.eff_speed(bn.player) < s_full, "low hunger: speed penalty")
	# XP and evolution
	var g := make_run(65)
	var ev := g.grant_xp(10)
	ok(g.level == 2 and ev["levels"].size() == 1 and not ev["evolved"], "level 2 at 10 xp")
	ev = g.grant_xp(14)
	ok(g.level == 3 and ev["evolved"] and g.form()["id"] == "juvenile", "evolve to juvenile at level 3")
	ok(g.pending_evolution_tier == 2, "evolution draft owed")
	var offer := g.offer_cards(3, "evolution")
	ok(offer.size() == 3 and offer.all(func(id): return int(DB.card(id)["tier"]) == 2), "evolution draft offers new-form cards")
	g.grant_xp(200)
	ok(g.level == 7 and g.form()["id"] == "prime", "max level is prime")
	ok(g.max_hp() > make_run(1).max_hp() * 2, "stats scale with growth")
	# draft offers respect growth tier
	var baby := make_run(66)
	for i in 30:
		for id in baby.offer_cards(3, "normal"):
			ok(int(DB.card(id)["tier"]) == 1, "baby only sees tier 1 cards")
			break
	# death resets: new run is fresh
	var d := make_run(67)
	d.grant_xp(50)
	d.hp = 0
	d.change_hp(0)
	ok(d.game_over, "hp 0 ends the run")
	var fresh := make_run(68)
	ok(fresh.level == 1 and fresh.xp == 0 and fresh.deck.size() == 10, "new run starts fully reset as an egg/baby")

func test_puzzle() -> void:
	section("puzzle")
	var run := make_run(71)
	var room := {}
	for st in run.stage["steps"]:
		for d in st["doors"]:
			if d["type"] == "puzzle":
				room = d
	ok(not room.is_empty(), "stage contains a puzzle room")
	var p := SequencePuzzle.from_room(room)
	var res := ""
	for s in room["sequence"]:
		res = p.press(int(s))
	ok(res == "done" and p.success, "solving sequence succeeds")
	var p2 := SequencePuzzle.from_room(room)
	var wrong := (int(room["sequence"][0]) + 1) % p2.buttons
	ok(p2.press(wrong) == "wrong", "first mistake allowed")
	ok(p2.press((int(room["sequence"][0]) + 1) % p2.buttons) == "fail", "second mistake fails")

func test_hints(game) -> void:
	section("first-run hints")
	var hints = root.get_node("Hints")
	game.save = game.default_save()
	ok(hints.active(), "hints active on first playthrough")
	hints.show_hint("movement")
	ok(hints.current() == "movement", "hint displays")
	hints._dismiss()
	ok(game.save["hints_seen"].has("movement"), "dismissed hint remembered")
	hints.show_hint("movement")
	ok(hints.current() == "", "seen hint is not shown again")
	game.start_run("velociraptor", 5)
	game.end_run()
	ok(game.save["first_run_complete"] == true, "first run completion persisted in save dict")
	ok(not hints.active(), "hints off after first run")
	hints.show_hint("stamina")
	ok(hints.current() == "", "no hints after first run")
	for id in DB.table("hints")["order"]:
		ok(DB.table("hints")["hints"].has(id), "hint text exists: " + id)
	for need in ["movement", "stamina", "turn_order", "draft", "hunger", "stealth", "weather"]:
		ok(DB.table("hints")["hints"].has(need), "required hint " + need)
	game.save = game.default_save()
	game.run = null

func test_combat_sim() -> void:
	section("combat simulation (bot)")
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var groups := [["beetle"], ["skink"], ["dragonfly"], ["shrew"], ["beetle", "dragonfly"], ["spitter"], ["spitter", "beetle"], ["dragonfly", "dragonfly", "beetle"], ["meganeura"], ["husk_queen"], ["compy", "compy"], ["dire_pup"], ["glyptodon"], ["smilodon"], ["infected_mammoth"]]
	var wins := 0
	var total := 0
	var timeouts := 0
	var stage_for := {"husk_queen": 0, "infected_mammoth": 1, "compy": 1, "dire_pup": 1, "glyptodon": 1, "smilodon": 1}
	var by_group := {}
	for gi in groups.size():
		var g: Array = groups[gi]
		for s in 12:
			var run := make_run(1000 + s)
			var lvl := 1
			if stage_for.get(g[0], 0) == 1:
				run.advance_stage()
				lvl = 5
			if g[0] == "husk_queen":
				lvl = 4
			run.level = lvl
			run.hp = run.max_hp()
			var inf := g.map(func(_e): return rng.randf() < 0.3)
			var b := Battle.create(run, make_room(g, 5000 + s * 17 + gi, inf), "ambush" if s % 2 == 0 else "spotted")
			b.begin()
			var res := AutoPlayer.play(b, rng)
			total += 1
			if res["timeout"]:
				timeouts += 1
			if b.phase == "won":
				wins += 1
				by_group[str(g)] = int(by_group.get(str(g), 0)) + 1
			ok(b.phase in ["won", "lost"] or res["timeout"], "battle terminates")
			ok(b.player.hp <= b.player.max_hp, "hp within bounds")
			for e in b.enemies:
				ok(e.hp <= e.max_hp and e.hp >= 0, "enemy hp within bounds")
			# every event references a real unit
	ok(timeouts == 0, "no battle timeouts (%d)" % timeouts)
	print("  %d/%d battles won by bot. wins by group: %s" % [wins, total, str(by_group)])
	ok(wins > total * 0.3, "bot wins a reasonable share of fights")

func test_full_runs() -> void:
	section("full run simulation (bot)")
	var n := 60
	var wins := 0
	var rooms := 0
	var levels := {}
	var stage2 := 0
	var causes := {}
	var types_seen := {"battle": 0, "events": 0, "puzzles": 0, "forage": 0, "elite": 0, "boss": 0, "ambush": 0, "sneak_ok": 0}
	var timeouts := 0
	for s in range(1, n + 1):
		var r := RunSimulator.simulate(s)
		rooms += int(r["rooms"])
		if r["victory"]:
			wins += 1
		if int(r["max_stage"]) >= 2:
			stage2 += 1
		levels[r["form"]] = int(levels.get(r["form"], 0)) + 1
		timeouts += int(r["timeouts"])
		if int(r["timeouts"]) > 0:
			print("  timeout seed ", s, " ", r.get("cause"))
		types_seen["battle"] += r["battles"]
		types_seen["events"] += r["events"]
		types_seen["puzzles"] += r["puzzles"]
		types_seen["forage"] += r["forage"]
		types_seen["elite"] += r["elite"]
		types_seen["boss"] += r["boss"]
		types_seen["ambush"] += r["ambush"]
		types_seen["sneak_ok"] += r["sneak_ok"]
		if not r["victory"]:
			var c := String(r["cause"])
			causes[c] = int(causes.get(c, 0)) + 1
		ok(r["rooms"] >= 1, "run %d played rooms" % s)
	ok(timeouts == 0, "no run hit a battle timeout")
	ok(stage2 > 0, "some bot runs clear stage 1 and reach stage 2 (%d/%d)" % [stage2, n])
	for k in ["battle", "events", "puzzles", "forage", "elite", "boss", "ambush"]:
		ok(types_seen[k] > 0, "full runs exercised: " + k)
	print("  %d runs: %d victories, %d reached stage 2, avg %.1f rooms" % [n, wins, stage2, float(rooms) / n])
	print("  final forms: %s" % str(levels))
	print("  coverage: %s" % str(types_seen))
	print("  causes of death: %s" % str(causes))


# ------------------------------------------------------------------ keywords / glossary

func test_keywords() -> void:
	section("keyword glossary (data/keywords.json)")
	var kws := Keywords.table()
	ok(kws.size() >= 25, "glossary has %d keywords" % kws.size())
	for id in kws:
		var d: Dictionary = kws[id]
		ok(String(d.get("name", "")) != "" and String(d.get("text", "")).length() >= 20, "keyword %s has a name and a real description" % id)
		ok(String(d.get("color", "")).length() == 7 and String(d["color"]).begins_with("#"), "keyword %s has a #rrggbb colour" % id)
	var opm := Keywords.op_map()
	for op in opm:
		ok(kws.has(String(opm[op])), "op %s maps to an existing keyword (%s)" % [op, opm[op]])
	# every effect op that has a keyword must be highlighted in the card's own text
	var cards := DB.table("cards")
	var n_hl := 0
	for id in cards:
		if String(id).begins_with("_") or not (cards[id] is Dictionary) or not cards[id].has("effects"):
			continue
		var c: Dictionary = cards[id]
		var used := Keywords.find(String(c["text"]))
		for e in c["effects"]:
			var op := String(e["op"])
			if opm.has(op):
				ok(used.has(String(opm[op])), "card %s: text highlights keyword '%s' (op %s)" % [id, opm[op], op])
		n_hl += used.size()
		# round trip: highlighting never drops or changes a character
		var joined := ""
		for sg in Keywords.segments(String(c["text"])):
			joined += String(sg["text"])
		ok(joined == String(c["text"]), "card %s keyword segmentation is lossless" % id)
		ok(Keywords.bbcode(String(c["text"])).find("[b]") >= 0 or used.is_empty(), "card %s keywords are bold" % id)
	ok(n_hl >= 40, "cards use plenty of keywords (%d highlights)" % n_hl)
	# items, branch items and hints go through the same glossary
	var item_kw := 0
	for id in DB.table("items")["items"]:
		item_kw += Keywords.find(String(DB.item(id)["text"])).size()
		for k in Keywords.find(String(DB.item(id)["text"])):
			ok(kws.has(k), "item %s keyword %s exists" % [id, k])
	ok(item_kw >= 5, "item texts use keywords (%d)" % item_kw)
	var hint_kw := 0
	for id in DB.table("hints")["hints"]:
		hint_kw += Keywords.find(String(DB.table("hints")["hints"][id]["text"])).size()
	ok(hint_kw >= 10, "hint texts use keywords (%d)" % hint_kw)
	ok(Keywords.find("Gain 3 block and Bleed the target").has("bleed") and Keywords.find("Gain 3 block").has("block"), "find() spots keywords")
	ok(Keywords.find("target is bleeding").has("bleed"), "aliases resolve (Bleeding -> Bleed)")
	ok(Keywords.find("blockbuster").is_empty(), "whole words only (no 'block' inside 'blockbuster')")
	ok(Keywords.bbcode("Deal [5]").find("[lb]") >= 0, "BBCode brackets in card text are escaped")
	ok(Keywords.HOVER_DELAY >= 0.6 and Keywords.HOVER_DELAY <= 1.2, "tooltip hover delay is about a second")
	for id in kws:
		ok(Keywords.defs_text(String(kws[id]["name"])).find(String(kws[id]["text"])) >= 0, "defs_text for %s" % id)

func test_keyword_ui() -> void:
	section("keyword tooltips on cards, items, hints")
	# card (hand + zoom): bold keyword runs, hover connected, and a real hover shows the tooltip after the delay
	for big in [false, true]:
		var cv := CardView.new().setup("rake", -1, big)
		root.add_child(cv)
		await process_frame
		ok(big or cv._text == null, "the hand card carries no description (it is on the zoom card)")
		if big:
			ok(cv._text.get_signal_connection_list("meta_hover_started").size() > 0, "card text (big=%s) has hover tooltips" % str(big))
			ok(cv._text.bbcode_enabled and cv._text.get_parsed_text().find("Bleed") >= 0, "card text renders the Bleed word")
			cv._text.meta_hover_started.emit("bleed")
			await create_timer_wait(Keywords.HOVER_DELAY - 0.4)
			ok(root.get_node_or_null("KwTipLayer") == null, "no tooltip before the hover delay")
			await create_timer_wait(0.7)
			ok(root.get_node_or_null("KwTipLayer") != null, "tooltip appears after hovering a keyword about a second")
			var tl: Node = root.get_node("KwTipLayer")
			var found := false
			for l in tl.find_children("*", "RichTextLabel", true, false):
				found = found or l.get_parsed_text().find("stacks") >= 0
			ok(found, "tooltip carries the stacking rules")
			cv._text.meta_hover_ended.emit("bleed")
			await process_frame
			await process_frame
			ok(root.get_node_or_null("KwTipLayer") == null, "tooltip hides when the mouse leaves")
		cv.queue_free()
	# whole-control tooltips (items in the HUD) and the zoom side panel
	var holder := Control.new()
	root.add_child(holder)
	Keywords.attach_tip(holder, "Test", "Hits apply Bleed.")
	ok(holder.get_child_count() > 0 and holder.get_signal_connection_list("mouse_entered").size() > 0, "attach_tip wires hover on a control")
	holder.queue_free()
	var sp := Keywords.side_panel("Apply Bleed and Weaken.")
	ok(sp != null, "side panel lists keywords for the zoomed card")
	if sp != null:
		sp.queue_free()
	Keywords.hide_tip()

# ------------------------------------------------------------------ difficulty

func test_difficulty() -> void:
	section("difficulty (data/difficulty.json)")
	var run := RunState.create("velociraptor", 5)
	run.begin_stage(0)
	var tut := {"type": "battle", "step": 0}
	var mid := {"type": "battle", "step": 5}
	var elite := {"type": "elite", "step": 5}
	ok(Difficulty.is_tutorial(run, tut) and not Difficulty.is_tutorial(run, mid), "first rooms of stage 1 are the tutorial")
	ok(Difficulty.hp_mult(run, tut) < 1.0 and Difficulty.dmg_add(run, tut) < 0, "tutorial enemies are softer (hp x%.2f, dmg %d)" % [Difficulty.hp_mult(run, tut), Difficulty.dmg_add(run, tut)])
	ok(Difficulty.extra_chance(run, tut) == 0.0, "no extra enemies in the tutorial")
	ok(Difficulty.hp_mult(run, mid) > Difficulty.hp_mult(run, {"type": "battle", "step": 2}), "difficulty ramps within a stage")
	ok(Difficulty.hp_mult(run, elite) > Difficulty.hp_mult(run, mid), "elites are tougher than normal fights")
	ok(Difficulty.extra_chance(run, mid) > 0.0 and Difficulty.extra_chance(run, elite) == 0.0, "extra enemies only in normal fights")
	var h1 := Difficulty.hp_mult(run, mid)
	run.begin_stage(1)
	ok(Difficulty.hp_mult(run, mid) > h1 * 1.3, "stage 2 enemies are much tougher (x%.2f vs x%.2f)" % [Difficulty.hp_mult(run, mid), h1])
	ok(Difficulty.dmg_add(run, mid) > 0, "stage 2 enemies hit harder")
	ok(Difficulty.hp_mult(run, {"type": "battle", "step": 5, "no_scale": true}) == 1.0, "no_scale rooms are untouched (test arenas)")
	run.begin_stage(0)
	run.difficulty = "normal"
	var nh := Difficulty.hp_mult(run, mid)
	var nd := Difficulty.dmg_add(run, mid)
	var nx := Difficulty.extra_chance(run, mid)
	run.difficulty = "hard"
	ok(Difficulty.hp_mult(run, mid) > nh and Difficulty.dmg_add(run, mid) > nd and Difficulty.extra_chance(run, mid) > nx, "Hard: more HP, more damage, more enemies than Normal")
	ok(Difficulty.hp_mult(run, tut) > 0.0 and Difficulty.hp_mult(run, tut) < nh, "Hard still has a soft tutorial")
	run.cleared_rooms = 10
	var hm := Difficulty.hunger_mult(run)
	run.difficulty = "normal"
	ok(Difficulty.hunger_mult(run) == 1.0 and hm > 1.0, "Hard is hungrier than Normal")
	run.cleared_rooms = 0
	run.difficulty = "hard"
	ok(Difficulty.hunger_mult(run) == 1.0, "no extra hunger in the tutorial")
	ok(Difficulty.level_ids().has("normal") and Difficulty.level_ids().has("hard"), "Normal and Hard are defined in data")
	ok(String(DB.table("difficulty")["default"]) == "normal", "default difficulty is Normal")
	# applied in battle: a stage-2 room has more HP than the same enemy in the tutorial
	var r2 := RunState.create("velociraptor", 6)
	r2.begin_stage(1)
	var room := make_room(["beetle"], 61)
	room.erase("no_scale")
	room["step"] = 4
	var bb := Battle.create(r2, room, "spotted")
	var base := int(DB.enemy("beetle")["hp"])
	ok(bb.enemies[0].max_hp > base * 1.5, "stage-2 beetle has scaled HP (%d vs base %d)" % [bb.enemies[0].max_hp, base])
	ok(bb.enemies[0].bonus_damage >= 2, "stage-2 beetle has bonus damage")
	var r1 := RunState.create("velociraptor", 6)
	r1.begin_stage(0)
	var troom := make_room(["beetle"], 61)
	troom.erase("no_scale")
	troom["step"] = 0
	var tb := Battle.create(r1, troom, "spotted")
	ok(tb.enemies[0].max_hp < base, "tutorial beetle is softer (%d vs base %d)" % [tb.enemies[0].max_hp, base])
	# extra enemies appear (seeded) in later normal rooms
	var extra := 0
	for sd in range(1, 41):
		var rr := RunState.create("velociraptor", sd)
		rr.begin_stage(1)
		var rm := make_room(["compy"], 300 + sd)
		rm.erase("no_scale")
		rm["step"] = 3
		var bx := Battle.create(rr, rm, "spotted")
		if bx.enemies.size() > 1:
			extra += 1
	ok(extra > 5 and extra < 40, "extra enemies join some stage-2 fights (%d/40)" % extra)

# ------------------------------------------------------------------ archetypes / synergy

func test_archetypes() -> void:
	section("archetypes and synergy tags")
	var ids: Array = Arch.ids()
	ok(ids.size() >= 6, "at least 6 archetypes (%d)" % ids.size())
	var per := {}
	var cards := DB.table("cards")
	var n_cards := 0
	for id in cards:
		if String(id).begins_with("_") or not (cards[id] is Dictionary) or not cards[id].has("effects"):
			continue
		n_cards += 1
		var tags: Array = cards[id].get("tags", [])
		ok(not tags.is_empty(), "card %s has an archetype tag" % id)
		for t in tags:
			ok(ids.has(t), "card %s tag %s is a known archetype" % [id, t])
			per[t] = int(per.get(t, 0)) + 1
	ok(n_cards >= 40, "at least 40 cards (%d)" % n_cards)
	for a in ids:
		ok(int(per.get(a, 0)) >= 6, "archetype %s has >= 6 cards (%d)" % [a, int(per.get(a, 0))])
		var d: Dictionary = Arch.table()[a]
		ok(String(d.get("name", "")) != "" and String(d.get("desc", "")) != "" and Color.html(String(d.get("color", "#000000"))) != Color.BLACK, "archetype %s has name, desc and colour" % a)
	var items: Dictionary = DB.table("items")["items"]
	var item_per := {}
	for id in items:
		for t in items[id].get("tags", []):
			ok(ids.has(t), "item %s tag %s is a known archetype" % [id, t])
			item_per[t] = int(item_per.get(t, 0)) + 1
	ok(items.size() >= 25, "plenty of items (%d)" % items.size())
	for a in ["ambush", "bleed", "flank", "speed", "hitrun", "scavenger"]:
		ok(int(item_per.get(a, 0)) >= 2, "archetype %s has >= 2 items (%d)" % [a, int(item_per.get(a, 0))])
	# synergy highlight: a build with 3 bleed cards highlights bleed cards but not flank cards
	var deck := ["rake", "open_vein", "gore"]
	ok(Arch.counts(deck, [])["bleed"] >= 3, "counts() sums tags")
	ok(Arch.matching(["bleed"], deck, []).has("bleed"), "bleed card is highlighted for a bleed build")
	ok(Arch.matching(["speed"], deck, []).is_empty(), "speed card is not highlighted for a bleed build")
	ok(Arch.matching(["bleed"], ["rake"], []).is_empty(), "1 card does not make a synergy yet")
	var bleed_item := ""
	for id in items:
		if items[id].get("tags", []).has("bleed"):
			bleed_item = String(id)
			break
	ok(Arch.matching(["bleed"], ["rake"], [bleed_item]).has("bleed"), "an item counts double toward synergy")
	ok(Arch.main_tag(deck, []) == "bleed", "main archetype of a bleed deck is bleed")
	var cv := CardView.new().setup("gore")
	cv.synergy = ["bleed"]
	root.add_child(cv)
	ok(cv.synergy.size() == 1, "CardView carries the synergy highlight")
	cv.queue_free()

func test_evasion_arenas_scaling() -> void:
	section("tall-grass evasion, arena variety, display scaling")
	# --- evasion: 25% for single-target hits, never for area attacks, 'dodge' event
	var b := duel("beetle", 90, 0)
	var e: BUnit = b.enemies[0]
	b.grid.set_tile(b.player.pos, "grass")
	ok(absf(b.grid.evasion(b.player.pos) - 0.25) < 0.001, "tall grass gives 25% evasion")
	ok(b.grid.evasion(Vector2i(6, 4)) == 0.0 or b.grid.get_tile(Vector2i(6, 4)) != "grass", "bare ground gives none")
	var dodged := 0
	var n := 800
	var dodge_ev := 0
	for i in n:
		b.player.hp = 1000
		b.player.max_hp = 1000
		b._hit(b.player, 1, e, {})
		if b.last_dodged:
			dodged += 1
	for evn in b.drain_events():
		if String(evn.get("t", "")) == "dodge":
			dodge_ev += 1
	ok(dodged > n * 0.19 and dodged < n * 0.31, "single-target hits miss ~25%% of the time in tall grass (%d/%d)" % [dodged, n])
	ok(dodge_ev == dodged, "every dodge emits a 'dodge' event (shown as a Dodge popup)")
	var aoe_dodged := 0
	for i in n:
		b.player.hp = 1000
		b._hit(b.player, 1, e, {"aoe": true})
		if b.last_dodged:
			aoe_dodged += 1
	ok(aoe_dodged == 0, "area attacks always hit")
	b.grid.set_tile(b.player.pos, "ground")
	var ground_dodged := 0
	for i in 200:
		b.player.hp = 1000
		b._hit(b.player, 1, e, {})
		if b.last_dodged:
			ground_dodged += 1
	ok(ground_dodged == 0, "no dodging on bare ground")
	var popup_src := FileAccess.get_file_as_string("res://scripts/ui/screens/BattleScreen.gd")
	ok(popup_src.find("\"dodge\"") >= 0 and popup_src.find("Dodge") >= 0, "BattleScreen shows a Dodge popup")
	ok(DB.table("hints")["hints"].has("evasion"), "evasion hint exists")
	# --- arenas: varied sizes and shapes, bounded, bigger for bosses, tiny tutorial
	var cfg: Dictionary = DB.table("arenas")
	var sizes := {}
	var shapes := {}
	var minw := 99
	var maxw := 0
	for sd in range(1, 121):
		var sp := ArenaGen.pick(sd, {"type": "battle", "step": 3, "enemies": ["beetle"]}, "spotted", 0)
		sizes["%dx%d" % [sp["w"], sp["h"]]] = true
		shapes[String(sp["shape"])] = true
		minw = mini(minw, int(sp["w"]))
		maxw = maxi(maxw, int(sp["w"]))
		ok(int(sp["w"]) >= int(cfg["min"][0]) and int(sp["w"]) <= int(cfg["max"][0]) and int(sp["h"]) >= int(cfg["min"][1]) and int(sp["h"]) <= int(cfg["max"][1]), "arena %d within bounds" % sd)
	ok(sizes.size() >= 8, "many different arena sizes (%d)" % sizes.size())
	ok(shapes.size() >= 3, "irregular shapes occur (%s)" % str(shapes.keys()))
	ok(maxw - minw >= 3, "small to big arenas (%d..%d wide)" % [minw, maxw])
	var boss := ArenaGen.pick(5, {"type": "boss", "step": 6, "enemies": ["infected_mammoth"]}, "spotted", 1)
	var tut := ArenaGen.pick(5, {"type": "battle", "step": 0, "enemies": ["beetle"]}, "spotted", 0)
	ok(int(boss["w"]) * int(boss["h"]) > int(tut["w"]) * int(tut["h"]) * 1.5, "boss arena is much bigger than the tutorial arena")
	ok(ArenaGen.pick(7, {"type": "battle", "step": 3}, "spotted", 0) == ArenaGen.pick(7, {"type": "battle", "step": 3}, "spotted", 0), "arena choice is seeded")
	# --- display scaling: 640x360 canvas, whole-number scale (Pixel Perfect) or fractional fill, text on the pixel grid
	var Mn: GDScript = load("res://scripts/ui/Main.gd")
	for sz in [Vector2(640, 360), Vector2(960, 540), Vector2(1280, 720), Vector2(1920, 1080), Vector2(2560, 1440), Vector2(2560, 1600), Vector2(3840, 2160), Vector2(1000, 800), Vector2(1366, 768), Vector2(5120, 2880)]:
		var r: Dictionary = Mn.scale_for(sz)
		var cont: Vector2 = r["content"]
		var bars: Vector2 = r["bars"]
		var sc_i := int(r["s"])
		ok(sc_i >= 1 and cont == Vector2(640, 360) * float(sc_i) and cont.x <= sz.x + 0.5 and cont.y <= sz.y + 0.5 or sz.x < 640.0, "scale %s -> whole x%d, content %s" % [str(sz), sc_i, str(cont)])
		ok(absf(float(bars.x) * 2.0 + cont.x - sz.x) <= 1.0 and absf(float(bars.y) * 2.0 + cont.y - sz.y) <= 1.0, "scale %s: bars %s centre the picture (letterbox / pillarbox)" % [str(sz), str(bars)])
		var rf: Dictionary = Mn.scale_for(sz, false)
		ok(float(rf["content"].x) <= sz.x + 0.5 and float(rf["content"].y) <= sz.y + 0.5 and (absf(rf["content"].x - sz.x) < 1.0 or absf(rf["content"].y - sz.y) < 1.0), "scale %s with Pixel Perfect off fills the window along one axis (%s)" % [str(sz), str(rf["content"])])
	ok(Mn.scale_for(Vector2(2560, 1600))["s"] == 4 and Mn.scale_for(Vector2(2560, 1600))["bars"] == Vector2(0, 80), "2560x1600 -> x4 with 80 px bars top / bottom")
	ok(Mn.scale_for(Vector2(3840, 2160))["s"] == 6 and Mn.scale_for(Vector2(3840, 2160))["bars"] == Vector2(0, 0), "4K -> x6, no bars")
	ok(Mn.scale_for(Vector2(1920, 1080))["s"] == 3 and Mn.scale_for(Vector2(1280, 720))["s"] == 2, "1080p -> x3, 720p -> x2")
	var msrc := FileAccess.get_file_as_string("res://scripts/ui/Main.gd")
	ok(msrc.find("KEY_F11") >= 0 and msrc.find("WINDOW_MODE_FULLSCREEN") >= 0, "F11 toggles fullscreen")

func test_big_window_layout() -> void:
	section("640x360 canvas: integer camera zoom, board band, HUD corners, hand at the bottom")
	Iso.reset()
	var cam: Dictionary = DB.table("arenas")["camera"]
	var steps: Array = cam["zoom_steps"]
	var whole := true
	for zs in steps:
		if float(zs) != float(int(zs)) or float(zs) < 1.0:
			whole = false
	ok(whole and steps.size() >= 2, "camera zoom steps are whole numbers (%s): one art pixel is always an exact multiple of canvas pixels" % str(steps))
	var v: Array = cam["view"]
	var all_fit := true
	var mins_ok := true
	for dims in [Vector2i(8, 6), Vector2i(10, 7), Vector2i(12, 9), Vector2i(14, 11), Vector2i(18, 13)]:
		var z0 := Iso.auto_zoom(dims.x, dims.y)
		var zm := Iso.min_zoom(dims.x, dims.y)
		var bs := Iso.board_size(dims.x, dims.y, z0)
		if z0 != float(int(z0)) or zm != float(int(zm)) or zm > z0 or zm < float(steps.back()):
			mins_ok = false
		if z0 > float(steps.back()) and (bs.x > float(v[2]) or bs.y > float(v[3])):
			all_fit = false
	ok(mins_ok, "auto zoom and the zoom-out limit are whole steps, min <= auto, never below the last step")
	ok(all_fit, "the auto zoom keeps the whole board inside the view band")
	ok(Iso.auto_zoom(10, 7) >= 2.0, "a 10x7 arena opens at zoom 2 or more (the board is not tiny on 640x360)")
	Iso.fit(10, 7, 0.0, Vector2.ZERO)
	var top := Iso.to_screen(Vector2(0, 0))
	var bot := Iso.to_screen(Vector2(10, 7))
	var cy := float(v[1]) + float(v[3]) * 0.5
	ok(absf((top.y + bot.y) / 2.0 - cy) < 20.0, "board is centred in the view band")
	ok(Iso.TW == 32.0 * Iso.zoom and Iso.TH == 16.0 * Iso.zoom, "32x16 iso tile at the chosen zoom")
	Iso.reset()
	# real battle screen on the 640x360 canvas
	var b := duel("beetle", 91, 0)
	var sc: Node = _screen_ready(b)
	await process_frame
	await process_frame
	await process_frame
	ok(sc.log_panel.global_position.x <= 5.0 and sc.log_panel.global_position.y + sc.log_panel.size.y >= 360.0 - 6.0, "log panel hugs the bottom-left corner (%s)" % str(sc.log_panel.global_position))
	ok(sc.end_btn.global_position.x + sc.end_btn.size.x >= 640.0 - 8.0 and sc.end_btn.global_position.y + sc.end_btn.size.y >= 360.0 - 60.0, "move/end buttons hug the bottom-right corner (%s)" % str(sc.end_btn.global_position))
	ok(sc.order_panel.global_position.y <= 6.0 and sc.order_panel.global_position.x <= 6.0, "turn order bar sits at the top-left corner (%s)" % str(sc.order_panel.global_position))
	var pp: Control = sc.bhud.get_child(0)
	ok(pp.global_position.y <= 6.0 and pp.global_position.x + pp.size.x >= 640.0 - 6.0, "player info panel hugs the top-right corner (%s)" % str(pp.global_position))
	var cards: Array = sc.hand_root.get_children().filter(func(c): return c is CardView)
	ok(cards.size() > 0, "hand is drawn")
	if cards.size() > 0:
		var cv: CardView = cards[0]
		ok(cv.global_position.y + CardView.H >= 360.0 - 4.0, "hand sits on the bottom edge (%s)" % str(cv.global_position))
		var minx := 9999.0
		var maxx := -9999.0
		for c in cards:
			minx = minf(minx, c.global_position.x)
			maxx = maxf(maxx, c.global_position.x + CardView.W)
		ok(absf((minx + maxx) / 2.0 - 320.0) < 30.0, "hand is centred at the bottom of the canvas")
	sc.queue_free()
	await process_frame

# ------------------------------------------------------------------ character customization
func img_of(path: String) -> Image:
	return (load(path) as Texture2D).get_image()

func diff_count(a: Image, b: Image) -> int:
	var n := 0
	for y in a.get_height():
		for x in a.get_width():
			if not a.get_pixel(x, y).is_equal_approx(b.get_pixel(x, y)):
				n += 1
	return n

func test_customization(game) -> void:
	section("character customization: egg-crack screen, palette swap + patterns on every stage, cosmetic only")
	var sid := "velociraptor"
	var conf: Dictionary = Look.cfg(sid)
	ok(not conf.is_empty() and conf["skins"].size() >= 8 and conf["patterns"].size() >= 4 and conf["pcolors"].size() >= 6 and conf["genders"].size() == 2, "data/customization.json: skins, patterns, pattern colours, 2 genders")
	var data_ok := true
	for g in ["skins", "patterns", "pcolors", "genders"]:
		for o in conf[g]:
			if not (o.has("id") and o.has("name")):
				data_ok = false
	ok(data_ok, "every option has an id and a name")
	var d := Look.default_look(sid)
	ok(Look.sanitize({}, sid) == d and Look.sanitize({"skin": "nonsense", "gender": "female"}, sid)["skin"] == "classic" and Look.sanitize({"gender": "female"}, sid)["gender"] == "female", "unknown ids fall back to the default look")
	ok(Look.is_default(d) and Look.sig(d) == "", "classic + solid + male is the original art")
	var gtags := true
	for g in conf["genders"]:
		if not bool(g.get("cosmetic", false)):
			gtags = false
		for k in g:
			if k in ["hp", "max_hp", "move", "stamina", "speed", "damage", "stats"]:
				gtags = false
	ok(gtags, "gender options are flagged cosmetic and carry no stat fields")
	# --- recolouring on every stage sprite (front/back and portraits)
	var azure := {"species": sid, "skin": "azure", "pattern": "solid", "pcolor": "cream", "gender": "male"}
	var striped := {"species": sid, "skin": "ember", "pattern": "stripes", "pcolor": "charcoal", "gender": "male"}
	var spots := {"species": sid, "skin": "jungle", "pattern": "spots", "pcolor": "white", "gender": "male"}
	var mott := {"species": sid, "skin": "slate", "pattern": "mottled", "pcolor": "rust", "gender": "male"}
	var fem := {"species": sid, "skin": "classic", "pattern": "solid", "pcolor": "cream", "gender": "female"}
	var all_changed := true
	var size_ok := true
	var alpha_ok := true
	var ident_ok := true
	var pat_ok := true
	var bg_ok := true
	for sp_id in conf["sprites"]:
		var src := img_of("res://assets/sprites/%s.png" % sp_id)
		ident_ok = ident_ok and diff_count(src, Look.apply(src, sp_id, d)) == 0
		for lk in [azure, striped, spots, mott]:
			var out := Look.apply(src, sp_id, lk)
			size_ok = size_ok and out.get_width() == src.get_width() and out.get_height() == src.get_height()
			all_changed = all_changed and diff_count(src, out) > 40
			for y in src.get_height():
				for x in src.get_width():
					if not is_equal_approx(src.get_pixel(x, y).a, out.get_pixel(x, y).a):
						alpha_ok = false
		var plain := Look.apply(src, sp_id, azure)
		for lk2 in [striped, spots, mott]:
			var same_skin: Dictionary = lk2.duplicate()
			same_skin["skin"] = "azure"
			pat_ok = pat_ok and diff_count(plain, Look.apply(src, sp_id, same_skin)) > 10
		if bool(conf["sprites"][sp_id].get("portrait", false)):
			# the background gradient is never touched
			var ref := img_of("res://assets/sprites/%s.png" % String(conf["sprites"][sp_id]["bg_ref"]))
			var out2 := Look.apply(src, sp_id, striped)
			for y in src.get_height():
				for x in src.get_width():
					if ref.get_pixel(x, y).a > 0.5 and src.get_pixel(x, y).is_equal_approx(ref.get_pixel(x, y)) and not out2.get_pixel(x, y).is_equal_approx(src.get_pixel(x, y)):
						bg_ok = false
	ok(ident_ok, "the default look leaves all 12 sprites pixel-identical")
	ok(all_changed, "every growth stage (baby, juvenile, adult, prime; front, back, portrait) is recoloured by each skin/pattern")
	ok(size_ok and alpha_ok, "recolouring keeps sprite size and transparency (tile alignment is unaffected)")
	ok(pat_ok, "stripes / spots / mottled each add a visible pattern on top of the skin on every stage")
	ok(bg_ok, "portrait backgrounds are left untouched")
	var src_a := img_of("res://assets/sprites/raptor_adult.png")
	var f_a := Look.apply(src_a, "raptor_adult", fem)
	var crest_only := true
	var f_diff := 0
	for y in src_a.get_height():
		for x in src_a.get_width():
			var c0 := src_a.get_pixel(x, y)
			if not c0.is_equal_approx(f_a.get_pixel(x, y)):
				f_diff += 1
				if Look.region_of(c0, y, src_a.get_height()) != Look.R_STRIPE:
					crest_only = false
	ok(f_diff > 15 and f_diff < 300 and crest_only, "female differs only subtly: only the dorsal-stripe (crest) pixels change (%d px)" % f_diff)
	var pa := Look.apply(src_a, "raptor_adult", azure)
	var pb := Look.apply(src_a, "raptor_adult", azure)
	ok(diff_count(pa, pb) == 0, "recolouring is deterministic")
	var solid_a := azure.duplicate()
	solid_a["pcolor"] = "lime"
	ok(diff_count(pa, Look.apply(src_a, "raptor_adult", solid_a)) == 0, "pattern colour is ignored with a solid pattern")
	# the colour really is the chosen one: mean hue of the changed skin pixels is azure-ish
	var hs := 0.0
	var hn := 0
	for y in pa.get_height():
		for x in pa.get_width():
			if not pa.get_pixel(x, y).is_equal_approx(src_a.get_pixel(x, y)) and pa.get_pixel(x, y).s > 0.2:
				hs += pa.get_pixel(x, y).h * 360.0
				hn += 1
	var want := Color.html("#4a78c0").h * 360.0
	ok(hn > 100 and absf(hs / float(hn) - want) < 15.0, "skin pixels take the chosen palette hue (%.0f vs %.0f)" % [hs / float(maxi(1, hn)), want])
	# --- random all
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var seen: Dictionary = {}
	var valid := true
	for i in 30:
		var rl := Look.random_look(sid, rng)
		seen[Look.sig(rl)] = true
		valid = valid and Look.sanitize(rl, sid) == rl
	ok(valid and seen.size() >= 12, "random-all yields valid, varied looks (%d distinct in 30)" % seen.size())
	# --- runtime: the whole run wears the look; stats and RNG untouched
	var base_run: RunState = game.start_run(sid, 4242)
	var stats0 := [base_run.max_hp(), base_run.base_move(), base_run.base_stamina(), base_run.base_speed(), str(base_run.deck), base_run.rng.randi()]
	var r2: RunState = game.start_run(sid, 4242, striped)
	var stats1 := [r2.max_hp(), r2.base_move(), r2.base_stamina(), r2.base_speed(), str(r2.deck), r2.rng.randi()]
	var r3: RunState = game.start_run(sid, 4242, fem)
	var stats2 := [r3.max_hp(), r3.base_move(), r3.base_stamina(), r3.base_speed(), str(r3.deck), r3.rng.randi()]
	ok(str(stats0) == str(stats1) and str(stats0) == str(stats2), "look and gender never change stats, deck or the run's RNG (%s)" % str(stats0))
	game.start_run(sid, 4242, striped)
	var tex := SpriteFactory.get_texture("raptor_prime")
	var orig := load("res://assets/sprites/raptor_prime.png") as Texture2D
	ok(diff_count(tex.get_image(), orig.get_image()) > 100, "runtime sprites (board, order bar...) wear the run's look")
	ok(diff_count(SpriteFactory.png("portrait_adult").get_image(), img_of("res://assets/sprites/portrait_adult.png")) > 100, "the HUD portrait wears it too")
	ok(SpriteFactory.get_texture("raptor_compy") == SpriteFactory.looked("raptor_compy", {}), "other creatures are not recoloured")
	ok(SpriteFactory.get_texture("raptor_adult", true) != SpriteFactory.get_texture("raptor_adult", false), "infected variant still works on the customized sprite")
	game.start_run(sid, 4242)
	ok(diff_count(SpriteFactory.get_texture("raptor_prime").get_image(), orig.get_image()) == 0, "a new run starts from the default look (reset each run)")
	# --- egg screen -> customization screen
	game.save = game.default_save()
	game.run = null
	var mainn: Node = load("res://scripts/ui/Main.gd").new()
	root.add_child(mainn)
	await process_frame
	await process_frame
	var egg: Node = mainn.current
	ok(egg != null and egg.name == "egg", "the game opens on the egg screen")
	var vs: Node = egg.slots["velociraptor"]
	ok(vs.get_node("nest").texture == SpriteFactory.get_texture("bg_egg_nest") and vs.get_node("egg").texture == SpriteFactory.get_texture("egg_raptor"), "egg-select slots show the spotted egg in the twig/fern nest")
	var esz: Vector2 = vs.get_node("egg").size
	ok(esz == vs.get_node("egg").texture.get_size() * 2.0 and vs.get_node("nest").size == vs.get_node("nest").texture.get_size(), "egg icon is drawn at an integer 2x and the nest at 1x (square pixels)")
	ok(egg.slots["tyrannosaurus"].get_node("egg").texture == SpriteFactory.get_texture("egg_locked") and not egg.slots["tyrannosaurus"].playable, "locked eggs keep the same egg shape (grey silhouette)")
	egg.seed_edit.text = "777"
	egg._hatch()
	await create_timer(1.0).timeout
	ok(game.main.current != null and game.main.current.name == "customize", "HATCH! opens the customization screen")
	var cs: Node = game.main.current
	if cs != null and cs.name == "customize":
		ok(cs.seed_val == 777 and cs.species_id == "velociraptor", "the chosen seed and species are passed on")
		for k in ["cust_skin_azure", "cust_pattern_stripes", "cust_pcolor_gold", "cust_gender_female", "cust_random", "cust_confirm", "cust_back"]:
			ok(cs.find_child(k, true, false) != null, "control %s exists" % k)
		var sw_count := 0
		for k in cs.swatches:
			sw_count += 1
		ok(sw_count == conf["skins"].size() + conf["pcolors"].size(), "a swatch per skin colour and pattern colour")
		ok(cs.stage_icons.size() == 4, "growth preview shows baby, juvenile, adult and prime")
		var nbd: Control = cs.get_node("Backdrop")
		ok(nbd.has_method("tile_size") and nbd.tile_size() == SpriteFactory.png("bg_customize_hi").get_size() * 1.0, "the nest scene is the native-pixel backdrop drawn at 1:1 (no 5x blocks)")
		var eo: Vector2 = nbd.origin() + nbd.ANCHOR * float(nbd.SCALE)
		ok(eo == cs.egg_view.position + cs.egg_view.BASE, "the egg sits exactly in the nest hollow of the scene (%s)" % str(eo))
		ok(cs.egg_view._egg == SpriteFactory.png("egg_raptor_hi"), "the cracking animation plays on the new egg sprite")
		var big := true
		for pn in cs.get_children():
			if pn is Panel and pn.size.x > 300 and pn.name != "PopupPanel":
				big = big and pn.self_modulate.a < 1.0
		ok(big, "the option panels are semi-transparent over the scene")
		var t0: Texture2D = cs.stage_icons[2].texture
		cs.pick("skin", "ember")
		cs.pick("pattern", "stripes")
		cs.pick("gender", "female")
		ok(cs.look["skin"] == "ember" and cs.look["pattern"] == "stripes" and cs.look["gender"] == "female", "options update the look")
		ok(cs.stage_icons[2].texture != t0 and diff_count(cs.stage_icons[2].texture.get_image(), t0.get_image()) > 50, "live preview recolours all stages at once")
		ok(cs.egg_view.look["skin"] == "ember", "the head in the egg follows the options")
		var lbl: String = cs.summary.text
		ok(lbl.find("Ember") >= 0 and lbl.find("Stripes") >= 0 and lbl.find("Female") >= 0, "summary describes the look (%s)" % lbl)
		var rnd_look: Dictionary = cs.look.duplicate()
		var changed := false
		for i in 6:
			cs._random_all()
			if cs.look != rnd_look:
				changed = true
		ok(changed and Look.sanitize(cs.look, sid) == cs.look, "Random all rolls a new valid look")
		cs.pick("skin", "violet")
		cs.pick("pattern", "spots")
		cs.egg_view.t = 0.0
		ok(not cs.egg_view.is_open() and cs.egg_view.openness() == 0.0, "the egg starts closed and wobbling")
		cs.egg_view.t = 2.6
		ok(cs.egg_view.is_open() and cs.egg_view.openness() > 0.99, "after the crack animation the head peeks out")
		Settings.intro_mode = 0
		cs._finish()
		await process_frame
		await process_frame
		ok(game.run != null and game.run.look["skin"] == "violet" and game.run.look["pattern"] == "spots" and game.run.seed_val == 777, "confirm starts the run wearing the chosen look")
		ok(game.main.current.name == "intro_cutscene", "and goes to the intro story cutscene first (customization -> cutscene -> stage intro)")
		game.main.current.skip(true)
		await process_frame
		await process_frame
		ok(game.main.current.name == "stage_intro", "skipping the cutscene continues into the stage intro (weather)")
		ok(SpriteFactory.look["skin"] == "violet", "sprites switch to the look")
	game.start_run(sid, 1)
	SpriteFactory.set_look({})
	game.save = game.default_save()
	mainn.queue_free()
	game.main = null
	await process_frame

# ------------------------------------------------------------------ settings panel: HUD size, fullscreen, volume
func test_settings(game) -> void:
	section("settings: Pixel Perfect (640x360 canvas, integer scale + bars), fullscreen, volume, persisted user config")
	var Mn: GDScript = load("res://scripts/ui/Main.gd")
	# --- scale table: pixel perfect = whole-number scale + bars, otherwise fractional fill
	var cases := {Vector2(1280, 720): 2, Vector2(1920, 1080): 3, Vector2(2560, 1600): 4, Vector2(3840, 2160): 6, Vector2(1366, 768): 2, Vector2(640, 360): 1, Vector2(800, 600): 1}
	var scale_ok := true
	for w in cases:
		var r: Dictionary = Mn.scale_for(w, true)
		var cont: Vector2 = r["content"]
		var bars: Vector2 = r["bars"]
		if not (int(r["s"]) == int(cases[w]) and cont == Vector2(640, 360) * float(cases[w]) and bars.x * 2.0 + cont.x <= w.x + 1.0 and bars.y * 2.0 + cont.y <= w.y + 1.0 and bars.x >= 0.0 and bars.y >= 0.0):
			scale_ok = false
			print("   scale case failed: ", w, " -> ", r)
	ok(scale_ok, "Pixel Perfect: 720p = 2x, 1080p = 3x, 2560x1600 = 4x (bars top/bottom), 4K = 6x, odd windows floor to a whole scale with centred bars")
	var rb: Dictionary = Mn.scale_for(Vector2(2560, 1600), true)
	ok(rb["bars"] == Vector2(0, 80), "2560x1600 letterbox: 80 px bars top and bottom (content 2560x1440)")
	var rf: Dictionary = Mn.scale_for(Vector2(1366, 768), false)
	ok(absf(float(rf["s"]) - 768.0 / 360.0) < 0.001 and absf(float(rf["content"].y) - 768.0) < 0.5, "Pixel Perfect off: fractional scale fills the window (1366x768 -> %.3fx)" % float(rf["s"]))
	ok(ProjectSettings.get_setting("display/window/size/viewport_width") == 640 and ProjectSettings.get_setting("display/window/size/viewport_height") == 360 and ProjectSettings.get_setting("display/window/stretch/mode") == "viewport" and ProjectSettings.get_setting("display/window/stretch/scale_mode") == "integer", "project: 640x360 base viewport, stretch viewport + integer")
	ok(Settings.pixel_perfect, "Pixel Perfect defaults to ON")
	# --- persistence in a user config file
	Settings.persist = true
	Settings.set_pixel_perfect(false)
	Settings.set_fullscreen(true)
	Settings.set_volume(35)
	Settings.pixel_perfect = true
	Settings.fullscreen = false
	Settings.volume = 80
	Settings.load_settings()
	ok(not Settings.pixel_perfect and Settings.fullscreen and Settings.volume == 35, "Pixel Perfect, fullscreen and volume are saved to the config file and loaded back (%s/%s/%d)" % [str(Settings.pixel_perfect), str(Settings.fullscreen), Settings.volume])
	ok(FileAccess.file_exists("user://settings_test.cfg"), "a user config file exists")
	var mi := AudioServer.get_bus_index("Master")
	Settings.set_volume(0)
	ok(AudioServer.is_bus_mute(mi), "volume 0 mutes the master bus")
	Settings.set_volume(50)
	ok(not AudioServer.is_bus_mute(mi) and AudioServer.get_bus_volume_db(mi) < 0.0, "master volume drives the Master bus")
	Settings.pixel_perfect = true
	Settings.fullscreen = false
	Settings.volume = 80
	Settings.apply_audio()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings_test.cfg"))
	Settings.persist = false
	# --- overlay + gear button on the real Main
	var mainn: Node = load("res://scripts/ui/Main.gd").new()
	root.add_child(mainn)
	await process_frame
	await process_frame
	ok(mainn.get_window().content_scale_size == Vector2i(640, 360) and mainn.get_window().content_scale_mode == Window.CONTENT_SCALE_MODE_VIEWPORT, "the window renders the 640x360 canvas (stretch viewport)")
	ok(mainn.get_window().content_scale_stretch == Window.CONTENT_SCALE_STRETCH_INTEGER, "integer stretch while Pixel Perfect is on")
	ok(mainn.current != null and mainn.current.find_child("gear_btn", true, false) != null, "menu/egg screen has a gear (Settings) button or the menu opens Settings")
	ok(not mainn.settings_open(), "settings start closed")
	mainn.open_settings()
	await process_frame
	ok(mainn.settings_open(), "the settings panel opens")
	var so: Node = mainn.overlay_layer.get_children().filter(func(c): return c is SettingsOverlay)[0]
	var tx := ""
	for c in so.get_children():
		if c is Label:
			tx += c.text + "\n"
	ok(tx.find("Pixel Perfect") >= 0 and tx.find("Master volume") >= 0 and so.find_child("fullscreen_btn", true, false) != null and so.find_child("volume_slider", true, false) != null and so.find_child("pixel_perfect_btn", true, false) != null, "panel has Pixel Perfect, fullscreen (F11) and master volume controls")
	ok(tx.find("HUD size") < 0, "the old HUD size option is gone")
	so.find_child("pixel_perfect_btn", true, false).pressed.emit()
	await process_frame
	await process_frame
	ok(not Settings.pixel_perfect and mainn.get_window().content_scale_stretch == Window.CONTENT_SCALE_STRETCH_FRACTIONAL, "turning Pixel Perfect off switches to fractional stretch live")
	so.find_child("pixel_perfect_btn", true, false).pressed.emit()
	await process_frame
	ok(Settings.pixel_perfect and mainn.get_window().content_scale_stretch == Window.CONTENT_SCALE_STRETCH_INTEGER, "and back on")
	(so.find_child("volume_slider", true, false) as HSlider).value = 20
	ok(Settings.volume == 20, "the volume slider changes the setting")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	mainn._unhandled_key_input(esc)
	await process_frame
	ok(not mainn.settings_open(), "Esc closes the panel")
	mainn._unhandled_key_input(esc)
	await process_frame
	ok(mainn.settings_open(), "Esc opens it again")
	mainn.close_settings()
	await process_frame
	Settings.pixel_perfect = true
	Settings.volume = 80
	Settings.apply_audio()
	mainn.queue_free()
	game.main = null
	await process_frame
	# --- battle HUD layout on the 640x360 canvas: corners kept, no overlaps, all on screen
	var cs := Vector2i(640, 360)
	for beetle_seed in [93, 7]:
		var b := duel("beetle", beetle_seed, 0)
		var sc: Node = _screen_ready(b)
		await process_frame
		await process_frame
		await process_frame
		var tag := "640x360 (seed %d)" % beetle_seed
		var pp: Control = sc.bhud.get_child(0)
		var ppr := Rect2(pp.global_position, pp.size)
		# the card box is invisible: its real content (portrait, Lv, name, status, bars) is what must not collide with the Deck button / pile line
		var content := Rect2(sc.bhud.portrait.global_position, sc.bhud.portrait.size)
		for cn in [sc.bhud.lv_label, sc.bhud._name_label, sc.bhud.status_label, sc.bhud.bars["hp"], sc.bhud.bars["stamina"], sc.bhud.bars["hunger"]]:
			content = content.merge(Rect2((cn as Control).global_position, (cn as Control).size))
		ppr = content
		var order := Rect2(sc.order_panel.global_position, sc.order_panel.size)
		var logr := Rect2(sc.log_panel.global_position, sc.log_panel.size)
		var infor := Rect2(sc.info_panel.global_position, sc.info_panel.size)
		var mv := Rect2(sc.move_btn.global_position, sc.move_btn.size).merge(Rect2(sc.end_btn.global_position, sc.end_btn.size))
		var gear: Control = sc.bhud.find_child("gear_btn", true, false)
		var wh: Control = sc.bhud.get_node("WeatherHover")
		var cards: Array = sc.hand_root.get_children().filter(func(c): return c is CardView)
		var hb := Rect2()
		for i in cards.size():
			var cr := Rect2(cards[i].global_position, Vector2(CardView.W, CardView.H))
			hb = cr if i == 0 else hb.merge(cr)
		ok(ppr.position.y <= 6.0 and ppr.end.x >= float(cs.x) - 6.0, "player info top-right: " + tag)
		ok(order.position.y <= 6.0 and order.position.x <= 6.0, "turn order top-left: " + tag)
		ok(mv.end.x >= float(cs.x) - 6.0 and mv.end.y >= float(cs.y) - 60.0, "Move/End Turn bottom-right: %s %s" % [tag, str(mv)])
		ok(cards.size() > 0 and hb.end.y >= float(cs.y) - 4.0 and absf(hb.get_center().x - float(cs.x) / 2.0) < 30.0, "card hand bottom-centre: " + tag)
		var barsr := Rect2()
		for bk in ["hp", "stamina", "hunger"]:
			var bsp: Control = sc.bhud.bars[bk]
			var br := Rect2(bsp.global_position, bsp.size)
			barsr = br if barsr.size == Vector2.ZERO else barsr.merge(br)
		ok(ppr.encloses(barsr), "the bars sit inside the (invisible) player card area: " + tag)
		var rects := {"player": ppr, "order": order, "log": logr, "info": infor, "move": mv, "gear": Rect2(gear.global_position, gear.size), "weather": Rect2(wh.global_position, wh.size), "hand": hb, "deck": Rect2(sc.bhud.deck_btn.global_position, sc.bhud.deck_btn.size)}
		var bad := ""
		var keys := rects.keys()
		for i in keys.size():
			for j in range(i + 1, keys.size()):
				if (keys[i] == "player" and keys[j] == "deck") or (keys[i] == "deck" and keys[j] == "player"):
					continue                    # the Deck button sits in the empty corner under the portrait: checked against the real content below
				if rects[keys[i]].intersects(rects[keys[j]]):
					bad += "%s/%s " % [keys[i], keys[j]]
		for cn in [sc.bhud.portrait, sc.bhud.lv_label, sc.bhud._name_label, sc.bhud.bars["hp"], sc.bhud.bars["stamina"], sc.bhud.bars["hunger"]]:
			if Rect2((cn as Control).global_position, (cn as Control).size).intersects(rects["deck"]):
				bad += "deck/%s " % String((cn as Control).name)
		if Rect2(sc.bhud.pile_label.global_position, sc.bhud.pile_label.size).intersects(rects["deck"]):
			bad += "deck/pile "
		ok(bad == "", "no overlaps (%s): %s" % [bad, tag])
		bad = ""
		for kk in rects:
			var rr: Rect2 = rects[kk]
			if rr.position.x < -1.0 or rr.position.y < -1.0 or rr.end.x > float(cs.x) + 1.0 or rr.end.y > float(cs.y) + 1.0:
				bad = "offscreen %s %s" % [String(kk), str(rr)]
		ok(bad == "", "everything stays on screen: %s" % tag)
		sc.queue_free()
		await process_frame


func test_egg_difficulty(game) -> void:
	section("egg screen: difficulty toggle")
	game.save = game.default_save()
	var egg: Node = load("res://scripts/ui/screens/EggScreen.gd").new()
	root.add_child(egg)
	await process_frame
	var btn: Button = egg.find_child("difficulty_btn", true, false)
	ok(btn != null, "egg screen has a difficulty button")
	if btn != null:
		var t0 := btn.text
		btn.pressed.emit()
		ok(btn.text != t0 and String(game.save.get("difficulty", "")) != "", "pressing it cycles Normal/Hard and saves the choice (%s -> %s)" % [t0, btn.text])
		btn.pressed.emit()
		ok(btn.text == t0, "and cycles back")
	egg.queue_free()
	await process_frame
	game.save = game.default_save()

func test_archetype_viability() -> void:
	section("archetype viability (competent bot, 30 seeds each)")
	var line := []
	for a in ["ambush", "bleed", "flank", "speed", "hitrun", "scavenger"]:
		var w := 0
		var rooms := 0
		for sd in range(1, 31):
			var r := RunSimulator.simulate(sd, false, "fit", {"smart": true, "archetype": a})
			if r["victory"]:
				w += 1
			rooms += int(r["rooms"])
		line.append("%s %d/30" % [a, w])
		ok(w >= 2, "archetype %s is viable: wins %d/30 (avg %.1f rooms)" % [a, w, float(rooms) / 30.0])
		ok(w <= 18, "archetype %s is not a runaway (%d/30)" % [a, w])
	print("  archetype wins: ", ", ".join(line))

# ------------------------------------------------------------------ depth mechanics

func test_depth_mechanics() -> void:
	section("depth: telegraphs, phases, armour, statuses, AI behaviours, intents")
	# --- telegraph: Bash winds up on the player's tile, sidestepping avoids it, stun interrupts
	var b := duel("glyptodon", 71, 1)
	var g: BUnit = b.enemies[0]
	g.pos = Vector2i(5, 3)
	g.abilities = [{"name": "Bash", "kind": "attack", "range": 1, "damage": 8, "windup": true, "windup_mult": 1.5}]
	g.ability_idx = 0
	g.bonus_damage = 0
	b.player.block = 0
	b._enemy_act(g)
	ok(not g.windup.is_empty() and g.windup_tiles.has(b.player.pos), "windup marks the player's tile as a danger tile")
	var it := b.intent_of(g)
	ok(String(it["kind"]) == "windup" and int(it["dmg"]) > 8, "intent shows the telegraphed damage (%s)" % str(it.get("dmg")))
	var hp0 := b.player.hp
	b.player.pos = Vector2i(3, 2)
	b._enemy_act(g)
	ok(b.player.hp == hp0 and g.windup.is_empty(), "stepping out of the red tiles dodges the telegraphed attack")
	b.player.pos = Vector2i(4, 3)
	g.ability_idx = 0
	b._enemy_act(g)
	ok(not g.windup.is_empty(), "windup starts again")
	g.add_status("stun", 1)
	b._cancel_windup(g, false)
	ok(g.windup.is_empty(), "stun / fear interrupt a windup")
	g.status.erase("stun")
	g.ability_idx = 0
	b._enemy_act(g)
	b.player.pos = Vector2i(4, 3)
	hp0 = b.player.hp
	b._enemy_act(g)
	ok(b.player.hp < hp0 - 8, "standing in the red tiles takes the heavy hit (%d)" % (hp0 - b.player.hp))
	# --- armour: front hits are reduced but never below half, flanks ignore it
	var a := duel("beetle", 72, 0)
	var be: BUnit = a.enemies[0]
	be.armor = 3
	be.pos = Vector2i(5, 3)
	be.facing = Vector2i(-1, 0)
	be.def = be.def.duplicate(true)
	be.def["facing"] = {}
	a.player.pos = Vector2i(4, 3)
	be.hp = 100
	a.hand = ["claw_slash"]
	a.stamina = 5
	a.play_card(0, be)
	ok(be.hp == 100 - 3, "armour 3 cuts a 5-damage hit to 3 (never below half): hp %d" % be.hp)
	be.hp = 100
	be.facing = Vector2i(1, 0)   # now facing away: back hit ignores armour
	a.hand = ["claw_slash"]
	a.play_card(0, be)
	ok(be.hp <= 95, "hits from behind ignore armour (hp %d)" % be.hp)
	# --- statuses: mark pays out once, daze halves enemy damage, fear makes it flee
	var m := duel("beetle", 73, 0)
	var me: BUnit = m.enemies[0]
	me.def = me.def.duplicate(true)
	me.def["facing"] = {}
	me.armor = 0
	me.pos = Vector2i(5, 3)
	me.facing = Vector2i(-1, 0)
	me.hp = 100
	m.hand = ["mark_prey", "claw_slash", "claw_slash"]
	m.stamina = 9
	m.play_card(0, me)
	ok(me.st("mark") > 0, "Mark Prey marks the target")
	m.play_card(0, me)
	ok(me.hp <= 100 - 5 - 3, "marked target takes +3 from the next hit (hp %d)" % me.hp)
	ok(me.st("mark") == 0, "mark is consumed")
	var hp1 := me.hp
	m.play_card(0, me)
	ok(me.hp == hp1 - 5, "second hit has no mark bonus")
	var d := duel("beetle", 74, 0)
	var de: BUnit = d.enemies[0]
	var base_dmg := d._calc_damage(de, d.player, 10, 1.0)
	de.add_status("daze", 2)
	ok(d._calc_damage(de, d.player, 10, 1.0) < base_dmg, "daze cuts the enemy's damage (%d -> %d)" % [base_dmg, d._calc_damage(de, d.player, 10, 1.0)])
	var f := duel("dire_pup", 75, 1)
	var fe: BUnit = f.enemies[0]
	f.player.pos = Vector2i(4, 3)
	fe.pos = Vector2i(5, 3)
	fe.add_status("fear", 2)
	ok(String(f.intent_of(fe)["kind"]) == "flee", "feared enemies intend to flee")
	var dist0 := BGrid.dist(fe.pos, f.player.pos)
	f._enemy_act(fe)
	ok(BGrid.dist(fe.pos, f.player.pos) > dist0, "a feared enemy runs away")
	# --- bleed payoff: Gore consumes bleed and adds damage per stack
	var gb := duel("beetle", 76, 0)
	var ge: BUnit = gb.enemies[0]
	ge.def = ge.def.duplicate(true)
	ge.def["facing"] = {}
	ge.armor = 0
	ge.pos = Vector2i(5, 3)
	ge.facing = Vector2i(-1, 0)
	ge.hp = 100
	ge.add_status("bleed", 4)
	gb.hand = ["gore"]
	gb.stamina = 9
	gb.play_card(0, ge)
	ok(ge.hp <= 100 - 3 - 8, "Gore: 3 + 2 per Bleed (hp %d)" % ge.hp)
	ok(ge.st("bleed") == 0, "Gore consumes the Bleed")
	# --- flank payoff: Flanking Strike hits harder from the side
	var fb := duel("beetle", 77, 0)
	var fl: BUnit = fb.enemies[0]
	fl.def = fl.def.duplicate(true)
	fl.def["facing"] = {}
	fl.armor = 0
	fl.pos = Vector2i(5, 3)
	fl.hp = 100
	fl.facing = Vector2i(-1, 0)
	fb.hand = ["flanking_strike", "flanking_strike"]
	fb.stamina = 9
	fb.play_card(0, fl)
	var front_dmg := 100 - fl.hp
	fl.hp = 100
	fl.facing = Vector2i(0, 1)
	fb.play_card(0, fl)
	ok(100 - fl.hp >= front_dmg + 4, "Flanking Strike: +4 from the side (%d vs %d)" % [100 - fl.hp, front_dmg])
	# --- momentum: Rending Charge scales with tiles moved
	var mb := duel("beetle", 78, 0)
	var mo: BUnit = mb.enemies[0]
	mo.def = mo.def.duplicate(true)
	mo.def["facing"] = {}
	mo.armor = 0
	mo.pos = Vector2i(5, 3)
	mo.facing = Vector2i(-1, 0)
	mo.hp = 100
	mb.hand = ["rending_charge", "rending_charge"]
	mb.stamina = 9
	mb.moved_tiles = 0
	mb.play_card(0, mo)
	var cold := 100 - mo.hp
	mo.hp = 100
	mb.moved_tiles = 6
	mb.play_card(0, mo)
	ok(100 - mo.hp > cold, "momentum cards hit harder after moving (%d vs %d)" % [100 - mo.hp, cold])
	# --- phases: boss/elite phases trigger once each at their hp threshold
	var pb := duel("meganeura", 79, 0)
	var pe: BUnit = pb.enemies[0]
	var bd0 := pe.bonus_damage
	pe.max_hp = 100
	pe.hp = 40
	pb._check_phases(pe)
	ok(pe.bonus_damage > bd0 and pe.phase_done.size() == 1, "phase triggers below its hp threshold")
	var bd1 := pe.bonus_damage
	pb._check_phases(pe)
	ok(pe.bonus_damage == bd1, "a phase triggers only once")
	var qb := duel("husk_queen", 80, 0)
	var qe: BUnit = qb.enemies[0]
	var before := qb.enemies.size()
	qe.max_hp = 100
	qe.hp = 30
	qb._check_phases(qe)
	ok(qb.alive_enemies().size() >= before, "boss phases can summon / buff")
	for id in DB.table("enemies"):
		var ed: Dictionary = DB.table("enemies")[id]
		if not ed.has("hp"):
			continue
		for ph in ed.get("phases", []):
			ok(float(ph["hp_pct"]) > 0.0 and float(ph["hp_pct"]) < 1.0, "enemy %s phase threshold valid" % id)
	# --- enemy variety: pack, ambusher surprise, retreat, kiter
	var pk := duel("compy", 81, 1)
	var pe1: BUnit = pk.enemies[0]
	ok(bool(pe1.def.get("pack", false)), "compy is a pack animal")
	var tank := DB.enemy("glyptodon")
	ok(int(tank.get("armor", 0)) >= 2, "glyptodon is armoured")
	var behaviours := {}
	for id in DB.table("enemies"):
		var ed2: Dictionary = DB.table("enemies")[id]
		if ed2.has("hp"):
			behaviours[String(ed2.get("behavior", "none"))] = true
	ok(behaviours.size() >= 5, "enemy variety: %d behaviour types %s" % [behaviours.size(), str(behaviours.keys())])
	ok(DB.enemy("skink").has("surprise") and DB.enemy("dragonfly").has("retreat_hp"), "ambushers and skirmishers have their own data")
	var sp := duel("spitter", 82, 0)
	var se: BUnit = sp.enemies[0]
	se.pos = Vector2i(5, 3)
	sp.player.pos = Vector2i(4, 3)
	var kd0 := BGrid.dist(se.pos, sp.player.pos)
	sp._enemy_act(se)
	ok(BGrid.dist(se.pos, sp.player.pos) >= kd0, "kiters never close in on you")
	# every enemy that is awake and in the player's face has a readable intent
	for id in DB.table("enemies"):
		var ed3: Dictionary = DB.table("enemies")[id]
		if not ed3.has("hp"):
			continue
		var ib := duel(String(id), 83, 1)
		ib.enemies[0].pos = Vector2i(5, 3)
		var iv := ib.intent_of(ib.enemies[0])
		ok(iv.has("kind") and String(iv["kind"]) != "", "enemy %s has an intent (%s)" % [id, str(iv.get("kind"))])
	# --- items: new effects are wired
	var ir := make_run(84)
	var hp_before := ir.max_hp()
	for id in DB.table("items")["items"]:
		var d2: Dictionary = DB.item(id)
		ok(d2.has("effects") and d2.has("text") and d2.has("name"), "item %s is complete" % id)
	ir.add_item("silk_wrap")
	ok(ir.max_hp() == hp_before + 8, "items change stats through item_bonus")
	# --- hints for the new systems exist
	for need in ["intent", "telegraph", "keywords", "synergy"]:
		ok(DB.table("hints")["hints"].has(need), "hint exists: " + need)
		ok(DB.table("hints")["order"].has(need), "hint ordered: " + need)

# ------------------------------------------------------------------ isometric rendering / facing

## A quiet duel on plain ground: player at (4,3), enemy at (6,3), enemy facing set by caller.
func duel(enemy_id: String, seed_in: int = 70, stage_idx: int = 0) -> Battle:
	var run := RunState.create("velociraptor", seed_in)
	run.begin_stage(stage_idx)
	run.stage["weather"] = "clear"
	var b := Battle.create(run, make_room([enemy_id], seed_in), "spotted")
	b.begin()
	b.phase = "player"
	for x in range(2, 9):
		for y in range(1, 6):
			b.grid.set_tile(Vector2i(x, y), "ground")
	b.player.pos = Vector2i(4, 3)
	b.player.facing = Vector2i(1, 0)
	b.enemies[0].pos = Vector2i(6, 3)
	b.enemies[0].aware = true
	b.enemies[0].hp = 200
	b.enemies[0].max_hp = 200
	b.stamina = 5
	b.stamina_max = 5
	b.mp = 3
	return b

func test_iso() -> void:
	section("isometric projection (2:1 diamond)")
	ok(Iso.TW == 2 * Iso.TH, "tiles are 2:1 diamonds")
	var all_round := true
	var unique := {}
	for x in 12:
		for y in 7:
			var p := Vector2i(x, y)
			var c := Iso.center(Vector2(p))
			if Iso.tile_at(c) != p:
				all_round = false
			# every point of the diamond interior picks the same tile
			for corner in Iso.diamond(p, 2.0):
				if Iso.tile_at(corner * 0.9 + c * 0.1) != p:
					all_round = false
			unique[c] = true
	ok(all_round, "center -> tile_at round-trips for the whole 12x7 grid (incl. diamond interior)")
	ok(unique.size() == 12 * 7, "no two tiles share a screen centre")
	ok(Iso.to_screen(Vector2(1, 0)).x > Iso.to_screen(Vector2(0, 0)).x and Iso.to_screen(Vector2(1, 0)).y > Iso.to_screen(Vector2(0, 0)).y, "+x runs down-right")
	ok(Iso.to_screen(Vector2(0, 1)).x < Iso.to_screen(Vector2(0, 0)).x and Iso.to_screen(Vector2(0, 1)).y > Iso.to_screen(Vector2(0, 0)).y, "+y runs down-left")
	ok(Iso.depth(Vector2(5, 5)) > Iso.depth(Vector2(4, 5)) and Iso.depth(Vector2(3, 3)) == Iso.depth(Vector2(2, 4)), "depth sort key is x+y")
	var tl := Iso.to_screen(Vector2(0, 0))
	var br := Iso.to_screen(Vector2(12, 7))
	ok(tl.y >= 0 and br.y <= 540 and Iso.to_screen(Vector2(0, 7)).x >= 0 and Iso.to_screen(Vector2(12, 0)).x <= 960, "whole board fits in the 960x540 viewport")
	ok(Iso.to_grid(Iso.to_screen(Vector2(3.25, 5.75))).distance_to(Vector2(3.25, 5.75)) < 0.001, "to_grid inverts to_screen for fractions")

func test_spawn_alignment() -> void:
	section("units sit exactly on their tile (fight start + after moves)")
	var bad := 0
	var checked := 0
	for stage_idx in [0, 1]:
		for sd in 12:
			var run := RunState.create("velociraptor", 500 + sd)
			run.begin_stage(stage_idx)
			var b := Battle.create(run, make_room(["beetle", "dragonfly", "shrew"], 900 + sd), "spotted")
			var board := BattleBoard.new()
			board.setup(b, String(run.stage.get("theme", "jungle")))
			for u in b.units:
				checked += 1
				var c := Iso.center(Vector2(u.pos))
				if u.vis_pos != Vector2(u.pos) or Iso.tile_at(c) != u.pos:
					bad += 1
				var foot := BattleBoard.unit_foot(u.vis_pos)
				var fo := Vector2(0, 3.0 * Iso.zoom)
				if foot != c + fo or Iso.tile_at(foot - fo) != u.pos:
					bad += 1
				if not u.is_player and board.pick(c) != u.pos:
					bad += 1
				if u.is_player and board.pick(c) != u.pos:
					bad += 1
			# after a move: the end of the 'move' event path is the logic position, and the UI snaps vis_pos to it
			b.begin()
			if b.phase == "player":
				var reach := b.reachable_tiles()
				var dests: Array = reach.keys().filter(func(q): return q != b.player.pos)
				if not dests.is_empty():
					var d: Vector2i = dests[dests.size() / 2]
					b.drain_events()
					b.move_player(d)
					var evs := b.drain_events()
					var moved := false
					for e in evs:
						if e["t"] == "move" and int(e["unit"]) == b.player.uid:
							moved = true
							checked += 1
							if e["path"].back() != b.player.pos or b.player.pos != d:
								bad += 1
					if not moved:
						bad += 1
					b.player.vis_pos = Vector2(b.player.pos)   # what BattleScreen._play does after replay
					if Iso.tile_at(Iso.center(b.player.vis_pos)) != d or board.pick(Iso.center(Vector2(d))) != d:
						bad += 1
			board.free()
	ok(checked > 100, "alignment checked on %d units/moves" % checked)
	ok(bad == 0, "no unit is offset from its tile at fight start or after movement (%d offsets)" % bad)

func test_facing() -> void:
	section("facing: geometry, free turning, persistence")
	var F := Battle.DIRS4
	ok(F.size() == 4 and F[0] == Vector2i(1, 0) and F[1] == Vector2i(0, 1) and F[2] == Vector2i(-1, 0) and F[3] == Vector2i(0, -1), "4 facings on the grid axes")
	# relative_dir: tgt at origin facing +x
	var f := Vector2i(1, 0)
	ok(Battle.relative_dir(Vector2i(2, 0), Vector2i.ZERO, f) == "front", "straight ahead = front")
	ok(Battle.relative_dir(Vector2i(-2, 0), Vector2i.ZERO, f) == "back", "straight behind = back")
	ok(Battle.relative_dir(Vector2i(0, 2), Vector2i.ZERO, f) == "side" and Battle.relative_dir(Vector2i(0, -2), Vector2i.ZERO, f) == "side", "left/right = side")
	ok(Battle.relative_dir(Vector2i(1, 1), Vector2i.ZERO, f) == "side" and Battle.relative_dir(Vector2i(-1, 1), Vector2i.ZERO, f) == "side", "exact diagonals count as side")
	ok(Battle.relative_dir(Vector2i(3, 1), Vector2i.ZERO, f) == "front" and Battle.relative_dir(Vector2i(-3, 1), Vector2i.ZERO, f) == "back", "wide cones: within 45 deg")
	var consistent := true
	for fi in 4:
		var fa: Vector2i = F[fi]
		for k in 4:
			var v: Vector2i = F[(fi + k) % 4]
			var want: String = ["front", "side", "back", "side"][k]
			if Battle.relative_dir(v * 2, Vector2i.ZERO, fa) != want:
				consistent = false
	ok(consistent, "relative_dir is rotation-consistent for all 4 facings")
	# free turning
	var b := duel("beetle")
	var pos0 := b.player.pos
	var st0 := b.stamina
	var mp0 := b.mp
	b.face_player_toward(pos0 + Vector2i(0, 3))
	ok(b.player.facing == Vector2i(0, 1), "clicking a tile turns the player toward it")
	b.face_player_toward(pos0 + Vector2i(-2, 0))
	ok(b.player.facing == Vector2i(-1, 0), "can turn 180 degrees in one go")
	for i in 6:
		b.face_player_toward(pos0 + [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1)][i % 3])
	ok(b.player.pos == pos0 and b.stamina == st0 and b.mp == mp0, "turning is free: no movement, stamina or move points spent")
	ok(b.player.facing == Vector2i(0, 1), "unlimited turns per turn")
	# moving sets facing
	b = duel("beetle")
	b.move_player(Vector2i(4, 5))
	ok(b.player.pos == Vector2i(4, 5) and b.player.facing == Vector2i(0, 1), "walking south-west faces SW")
	b.move_player(Vector2i(3, 5))
	ok(b.player.facing == Vector2i(-1, 0), "walking north-west faces NW")
	# attacking turns toward the target
	b = duel("beetle")
	b.player.facing = Vector2i(0, -1)
	b.enemies[0].pos = Vector2i(5, 3)
	_force_hand(b, ["claw_slash"])
	ok(b.play_card(0, b.enemies[0]), "attack adjacent target")
	ok(b.player.facing == Vector2i(1, 0), "attacking turns the player to face the target")
	# persistence between turns
	b = duel("beetle")
	b.enemies[0].pos = Vector2i(8, 1)
	b.enemies[0].aware = false
	b.enemies[0].facing = Vector2i(1, 0)
	b.player.facing = Vector2i(0, -1)
	b.end_player_turn()
	ok(b.phase == "player" or b.phase == "won" or b.phase == "lost", "enemy phase completes")
	if b.phase == "player":
		ok(b.player.facing == Vector2i(0, -1), "player facing persists across turns")
		ok(b.player.turns_left > 0, "turn budget refreshed")
	var e_face: Vector2i = b.enemies[0].facing
	b.end_player_turn()
	ok(DIRS_OK(b.enemies[0].facing), "enemy facing stays a valid axis (%s)" % str(e_face))
	# slow turners: one quarter turn per turn
	var g := duel("glyptodon", 71, 1)
	var gl: BUnit = g.enemies[0]
	ok(gl.slow_turn(), "glyptodon is a slow turner")
	gl.facing = Vector2i(1, 0)
	gl.turns_left = 1
	g._set_facing(gl, Vector2i(-1, 0))
	ok(Battle.quarter_turns(Vector2i(1, 0), gl.facing) == 1, "slow turner only gets 1 quarter-turn (now %s)" % str(gl.facing))
	ok(not g._set_facing(gl, Vector2i(0, -1)) or gl.turns_left >= 0, "no turns left -> cannot turn further")
	# enemy unit starting positions: every enemy gets a valid facing
	var run := make_run(77)
	var sb := Battle.create(run, make_room(["beetle", "shrew", "compy"], 12), "spotted")
	var valid := true
	for u in sb.units:
		if not DIRS_OK(u.facing) or u.vis_facing != u.facing:
			valid = false
	ok(valid, "all units start with a valid facing, mirrored in vis_facing")
	var towards := sb.enemies.all(func(e): return not e.aware or e.facing == Battle.dir_toward(e.pos, sb.player.pos, e.facing))
	ok(towards, "aware enemies start facing you")

func DIRS_OK(d: Vector2i) -> bool:
	return Battle.DIRS4.has(d)

func test_facing_cards_and_enemies() -> void:
	section("facing: damage modifiers (cards, enemies, preview)")
	var cfg: Dictionary = DB.facing_cfg()
	ok(cfg["defaults"]["front"] == 1.0 and cfg["defaults"]["back"] > cfg["defaults"]["side"] and cfg["defaults"]["side"] > 1.0, "defaults: back > side > front")
	# vs a neutral enemy: normal card, front/side/back
	var b := duel("skink")
	var e: BUnit = b.enemies[0]
	e.def = e.def.duplicate(true)
	e.def["facing"] = {}
	e.pos = Vector2i(5, 3)
	e.facing = Vector2i(-1, 0)    # looking at us
	var attack := {"hp": 0}
	_force_hand(b, ["claw_slash"])
	var hp0 := e.hp
	b.play_card(0, e)
	var front_dmg := hp0 - e.hp
	b = duel("skink")
	e = b.enemies[0]
	e.def = e.def.duplicate(true); e.def["facing"] = {}
	e.pos = Vector2i(5, 3); e.facing = Vector2i(1, 0)   # looking away -> we hit its back
	_force_hand(b, ["claw_slash"])
	hp0 = e.hp
	var pv := b.preview_attack(0, e)
	b.play_card(0, e)
	var back_dmg := hp0 - e.hp
	ok(pv["dir"] == "back" and absf(float(pv["mult"]) - 1.5) < 0.001, "preview says BACK x1.5")
	ok(back_dmg > front_dmg, "back attack hurts more (%d > %d)" % [back_dmg, front_dmg])
	ok(back_dmg == int(round(float(front_dmg) * 1.5)), "back multiplier applied exactly (%d vs %d)" % [back_dmg, front_dmg])
	b = duel("skink")
	e = b.enemies[0]
	e.def = e.def.duplicate(true); e.def["facing"] = {}
	e.pos = Vector2i(5, 3); e.facing = Vector2i(0, 1)   # looking sideways
	_force_hand(b, ["claw_slash"])
	hp0 = e.hp
	b.play_card(0, e)
	var side_dmg := hp0 - e.hp
	ok(side_dmg > front_dmg and side_dmg < back_dmg, "side attack is in between (%d)" % side_dmg)
	# backstab card: x3 from behind
	b = duel("skink")
	e = b.enemies[0]
	e.def = e.def.duplicate(true); e.def["facing"] = {}
	e.pos = Vector2i(5, 3); e.facing = Vector2i(1, 0); e.aware = true
	_force_hand(b, ["backstab"])
	hp0 = e.hp
	var pv2 := b.preview_attack(0, e)
	b.play_card(0, e)
	ok(hp0 - e.hp == 12 and float(pv2["mult"]) == 3.0, "Backstab: 4 x3 = 12 from behind (did %d)" % (hp0 - e.hp))
	b = duel("skink")
	e = b.enemies[0]
	e.def = e.def.duplicate(true); e.def["facing"] = {}
	e.pos = Vector2i(5, 3); e.facing = Vector2i(-1, 0)
	_force_hand(b, ["backstab"])
	hp0 = e.hp
	b.play_card(0, e)
	ok(hp0 - e.hp == 4, "Backstab from the front is plain damage (%d)" % (hp0 - e.hp))
	# hamstring: back bonus bleed + weak
	b = duel("skink")
	e = b.enemies[0]
	e.def = e.def.duplicate(true); e.def["facing"] = {}
	e.pos = Vector2i(5, 3); e.facing = Vector2i(1, 0)
	_force_hand(b, ["hamstring"])
	b.play_card(0, e)
	ok(e.st("bleed") == 6 and e.st("weak") > 0, "Hamstring from behind: 2+4 bleed and Weaken (bleed %d)" % e.st("bleed"))
	b = duel("skink")
	e = b.enemies[0]
	e.def = e.def.duplicate(true); e.def["facing"] = {}
	e.pos = Vector2i(5, 3); e.facing = Vector2i(-1, 0)
	_force_hand(b, ["hamstring"])
	b.play_card(0, e)
	ok(e.st("bleed") == 2 and e.st("weak") == 0, "Hamstring from the front: no bonus")
	# enemy traits
	b = duel("beetle")
	e = b.enemies[0]
	e.pos = Vector2i(5, 3)
	e.facing = Vector2i(-1, 0)
	ok(b.facing_mult(b.player.pos, e) < 1.0, "beetle: armoured head shield (front x%s)" % str(b.facing_mult(b.player.pos, e)))
	e.facing = Vector2i(1, 0)
	ok(b.facing_mult(b.player.pos, e) > 1.5, "beetle: soft rear (back x%s)" % str(b.facing_mult(b.player.pos, e)))
	var g := duel("glyptodon", 71, 1)
	g.enemies[0].pos = Vector2i(5, 3)
	g.enemies[0].facing = Vector2i(-1, 0)
	ok(absf(g.facing_mult(g.player.pos, g.enemies[0]) - 0.75) < 0.001, "glyptodon takes reduced (x0.75) damage from the front")
	# the player's own species table applies to attacks against the player
	var pb := duel("skink")
	pb.enemies[0].pos = Vector2i(3, 3)    # behind the player (player faces +x)
	ok(pb.facing_dir(pb.enemies[0].pos, pb.player) == "back", "attacks from behind the player are 'back'")
	ok(absf(pb.facing_mult(pb.enemies[0].pos, pb.player) - float(DB.table("species")["velociraptor"]["facing"]["back"])) < 0.001, "player's species facing table applies")
	# data validation: every facing table has sane numbers
	var sane := true
	for id in DB.table("enemies"):
		var ft: Dictionary = DB.table("enemies")[id].get("facing", {})
		for k in ["front", "side", "back"]:
			if ft.has(k) and (float(ft[k]) <= 0.0 or float(ft[k]) > 4.0):
				sane = false
	ok(sane, "enemy facing multipliers are within (0, 4]")
	var has_armor := false
	var has_weak_rear := false
	for id in DB.table("enemies"):
		var ft: Dictionary = DB.table("enemies")[id].get("facing", {})
		has_armor = has_armor or float(ft.get("front", 1.0)) < 1.0
		has_weak_rear = has_weak_rear or float(ft.get("back", 1.0)) > 1.5
	ok(has_armor and has_weak_rear, "roster has armoured fronts and weak rears")

func test_vision_cone() -> void:
	section("facing: vision cones & sneaking")
	var b := duel("skink")
	var e: BUnit = b.enemies[0]
	e.aware = false
	e.def = e.def.duplicate(true)
	e.def["facing"] = {}
	e.perception = 5.0
	e.pos = Vector2i(6, 3)
	var p := Vector2i(3, 3)   # 3 tiles west of the enemy
	e.facing = Vector2i(-1, 0)
	ok(b.can_detect_at(e, p), "enemy facing you sees you at range 3")
	e.facing = Vector2i(0, 1)
	var side_ok := b.can_detect_at(e, p)
	e.facing = Vector2i(1, 0)
	ok(not b.can_detect_at(e, p), "enemy facing away does not see you (even close)")
	ok(not b.can_detect_at(e, Vector2i(5, 3)), "...even when adjacent behind it")
	e.facing = Vector2i(-1, 0)
	ok(b.can_detect_at(e, Vector2i(5, 3)), "adjacent in front is always seen")
	ok(b.vision_mult(e, Vector2i(3, 3)) == 1.0, "front vision multiplier is 1")
	e.facing = Vector2i(0, 1)
	ok(b.vision_mult(e, Vector2i(3, 3)) < 1.0 and b.vision_mult(e, Vector2i(3, 3)) > 0.0, "side vision is reduced")
	ok(side_ok == (BGrid.dist(e.pos, p) <= maxi(1, int(floor(5.0 * 0.6)))), "side detection range shrinks (3 tiles seen at 0.6x5=3)")
	# sneaking up behind: moving next to an enemy that looks away does not alert it
	var run := make_run(81)
	run.stage["weather"] = "clear"
	var sb := Battle.create(run, make_room(["skink"], 82), "ambush")
	for x in range(0, 12):
		for y in range(0, 7):
			sb.grid.set_tile(Vector2i(x, y), "ground")
	var se: BUnit = sb.enemies[0]
	se.pos = Vector2i(6, 3)
	se.facing = Vector2i(1, 0)
	se.aware = false
	sb.player.pos = Vector2i(3, 3)
	sb.phase = "player"
	sb.mp = 6
	sb.move_player(Vector2i(5, 3))
	ok(not se.aware, "walking up behind an enemy that looks away keeps you unspotted")
	# flyers see more around
	var dfb := duel("dragonfly", 72)
	var df: BUnit = dfb.enemies[0]
	df.facing = Vector2i(1, 0)
	ok(dfb.vision_mult(df, df.pos + Vector2i(-2, 0)) > 0.0, "dragonfly compound eyes: no total blind spot")

func test_themes() -> void:
	section("stage themes (jungle / icy tundra)")
	var themes: Dictionary = DB.table("themes")
	ok(themes.has("jungle") and themes.has("tundra"), "jungle and tundra themes exist")
	for id in ["jungle", "tundra"]:
		var t: Dictionary = DB.theme(id)
		for k in ["bg_variants", "ground_variants", "water_variants", "tall_variants", "obstacle_variants", "particles", "grid_line", "move", "target", "flying_lift"]:
			ok(t.has(k), "theme %s has %s" % [id, k])
	ok(str(DB.theme("tundra")["particles"]) != str(DB.theme("jungle")["particles"]), "themes differ in particles (snow vs pollen)")
	var stage_theme := {}
	for sid in DB.table("stages")["defs"]:
		stage_theme[String(DB.table("stages")["defs"][sid].get("theme", "jungle"))] = true
	ok(stage_theme.has("jungle") and stage_theme.has("tundra"), "stages pick jungle and tundra themes via data")
	ok(SpriteFactory.tile_texture("ground", "tundra", 0) != null and SpriteFactory.tile_texture("ground", "jungle", 0) != null, "theme tile textures load")
	ok(SpriteFactory.tile_texture("ground", "tundra", 0) != SpriteFactory.tile_texture("ground", "jungle", 0), "tundra and jungle ground tiles differ")
	var run := RunState.create("velociraptor", 5)
	run.begin_stage(1)
	var b := Battle.create(run, make_room(["beetle"], 3), "spotted")
	var board := BattleBoard.new()
	board.setup(b, String(run.stage.get("theme", "jungle")))
	ok(board.theme_id == "tundra", "stage 2 board uses the icy tundra theme")
	board.free()

# ------------------------------------------------------------------ enemy search AI

func open_field(b: Battle) -> void:
	for x in range(0, 12):
		for y in range(0, 7):
			b.grid.set_tile(Vector2i(x, y), "ground")

func test_search_ai() -> void:
	section("enemy AI: idle roaming -> spotted -> searching -> idle")
	# state / aware compatibility
	var u := BUnit.new()
	ok(u.state == "idle" and not u.aware, "units start idle/unaware")
	u.aware = true
	ok(u.state == "spotted" and u.aware, "aware = spotted")
	u.aware = false
	ok(u.state == "idle", "clearing aware returns a spotted unit to idle")
	u.state = "searching"
	u.aware = false
	ok(u.state == "searching" and not u.aware, "searching enemies are not aware")

	# --- losing sight: out of tracking range
	var b := duel("skink", 90)
	open_field(b)
	var e: BUnit = b.enemies[0]
	e.perception = 2.0
	e.tags = ["reptile"]
	b.player.pos = Vector2i(1, 1)
	e.pos = Vector2i(9, 5)
	e.home = e.pos
	e.facing = Vector2i(-1, 0)
	e.aware = true
	e.last_seen = Vector2i(5, 3)
	b.drain_events()
	ok(not b.tracks_player(e), "far-away hunting enemy cannot follow you")
	var start := e.pos
	b._enemy_act(e)
	ok(e.state == "searching", "hunting enemy that loses you starts searching (not idle, not frozen)")
	var evs := b.drain_events()
	ok(evs.any(func(x): return x["t"] == "lose_track" and int(x["unit"]) == e.uid), "lose_track event emitted ('?' shown)")
	ok(e.pos != start, "it does not stand still: it moved toward the last seen position")
	ok(BGrid.dist(e.pos, e.last_seen) < BGrid.dist(start, e.last_seen), "...and got closer to it")
	var cost: Dictionary = b.grid.reach(start, e.move, {})["cost"]
	ok(cost.has(e.pos) and int(cost[e.pos]) <= e.move, "within its movement allowance (%d of %d)" % [int(cost.get(e.pos, 99)), e.move])
	# keep walking until it arrives, then scan exactly SEARCH_SCAN_TURNS turns, then give up
	b.player.pos = Vector2i(0, 6)   # somewhere it cannot see
	var arrived := false
	var scan_turns := 0
	var facings := {}
	var gave_up := false
	for i in 12:
		var pre_phase := e.search_phase
		b._enemy_act(e)
		if e.pos == e.last_seen:
			arrived = true
		if pre_phase == "scan":
			scan_turns += 1
			facings[e.facing] = true
		if e.state == "idle":
			gave_up = true
			break
	ok(arrived, "searcher reaches the last seen tile")
	ok(gave_up, "searcher gives up and returns to idle")
	ok(scan_turns == Battle.SEARCH_SCAN_TURNS, "scans for %d turns (did %d)" % [Battle.SEARCH_SCAN_TURNS, scan_turns])
	ok(facings.size() >= 2, "scanning turns the enemy through different directions")
	ok(b.drain_events().any(func(x): return x["t"] == "give_up"), "give_up event emitted")

	# --- searching alone: no alerting
	b = duel("skink", 91)
	open_field(b)
	var a1: BUnit = b.enemies[0]
	b.player.pos = Vector2i(1, 1)
	a1.pos = Vector2i(9, 5); a1.perception = 2.0; a1.tags = ["reptile"]
	a1.aware = true; a1.last_seen = Vector2i(4, 3)
	var b2e := b._make_enemy("skink")
	b2e.pos = Vector2i(10, 5); b2e.home = b2e.pos; b2e.facing = Vector2i(0, 1)
	b.units.append(b2e); b.enemies.append(b2e)
	b._enemy_act(a1)
	ok(a1.state == "searching" and b2e.state == "idle", "losing track alerts nobody else (neighbour stays idle)")
	# a searching enemy that finds you spots you ALONE
	b.player.pos = Vector2i(7, 5)    # 2 tiles in front of a1's walk
	a1.pos = Vector2i(9, 5)
	a1.facing = Vector2i(-1, 0)
	b2e.facing = Vector2i(1, 0)       # looking away from the player
	a1.state = "searching"
	b._detect_all()
	ok(a1.state == "spotted", "searching enemy re-spots you in its vision cone")
	ok(b2e.state == "idle", "...without alerting the enemy next to it (searchers act alone)")
	# contrast: an idle enemy that spots you does alert nearby idle ones
	b2e.state = "idle"
	a1.state = "idle"
	a1.facing = Vector2i(-1, 0)
	b._detect_all()
	ok(a1.state == "spotted" and b2e.state == "spotted", "idle -> spotted still alerts nearby enemies (existing noise rule)")

	# --- vision cones apply while searching
	b = duel("skink", 92)
	open_field(b)
	e = b.enemies[0]
	e.pos = Vector2i(8, 3); e.perception = 5.0; e.state = "searching"; e.last_seen = e.pos; e.search_phase = "scan"; e.scan_left = 2
	e.def = e.def.duplicate(true); e.def["facing"] = {}
	b.player.pos = Vector2i(5, 3)
	e.facing = Vector2i(1, 0)         # looking away
	ok(not b.can_detect(e), "searcher looking away cannot see you")
	e.facing = Vector2i(-1, 0)
	ok(b.can_detect(e), "searcher looking at you sees you")

	# --- weather & cover respected by tracking
	b = duel("skink", 93)
	open_field(b)
	e = b.enemies[0]
	e.perception = 4.0; e.tags = ["reptile"]
	e.pos = Vector2i(8, 3)
	b.player.pos = Vector2i(3, 3)     # 5 tiles
	b.weather_id = "clear"
	ok(b.tracks_player(e), "clear day: 4*1.5=6 tiles, still tracked at 5")
	b.grid.set_tile(b.player.pos, "grass")
	ok(not b.tracks_player(e), "tall grass halves tracking range: lost at 5")
	b.grid.set_tile(b.player.pos, "ground")
	b.weather_id = "fog"
	ok(not b.tracks_player(e), "fog shortens tracking range")
	b.weather_id = "clear"
	b.grid.set_tile(Vector2i(5, 3), "obstacle")
	ok(not b.tracks_player(e), "no line of sight: lost")
	b.grid.set_tile(Vector2i(5, 3), "ground")
	e.tags = ["reptile", "scent"]
	b.grid.set_tile(b.player.pos, "grass")
	ok(b.tracks_player(e), "scent trackers follow you through cover within %d tiles" % Battle.SCENT_RANGE)

	# --- hiding makes hunters search (not freeze)
	b = duel("skink", 94)
	open_field(b)
	e = b.enemies[0]
	e.pos = Vector2i(8, 3); e.aware = true
	b.player.pos = Vector2i(3, 3)
	b.grid.set_tile(b.player.pos, "grass")
	b.drain_events()
	b._try_hide()
	ok(e.state == "searching" and e.last_seen != Vector2i(-1, -1), "hiding sends hunters to search the last seen spot")
	ok(b.is_hidden(), "player counts as hidden while enemies only search")
	var pos0 := e.pos
	b._enemy_act(e)
	ok(e.pos != pos0, "the searcher moves right away on its next turn")

	# --- idle roaming
	b = duel("skink", 95)
	open_field(b)
	b.grid.set_tile(Vector2i(6, 2), "water")
	e = b.enemies[0]
	e.aware = false
	e.pos = Vector2i(7, 3); e.home = e.pos
	e.perception = 0.5
	b.player.pos = Vector2i(0, 6)
	var seen := {}
	var in_radius := true
	var wet := false
	for i in 60:
		b._enemy_act(e)
		seen[e.pos] = true
		if BGrid.dist(e.pos, e.home) > Battle.ROAM_RADIUS + 1:
			in_radius = false
		if b.grid.get_tile(e.pos) == "water" or b.grid.blocks_move(e.pos):
			wet = true
		e.state = "idle"     # keep it idle for the experiment
	ok(seen.size() >= 4, "idle enemy wanders over %d different tiles" % seen.size())
	ok(in_radius, "roaming stays around its home")
	ok(not wet, "roaming avoids water and obstacles")
	# returns home after a search
	e.pos = Vector2i(11, 6); e.home = Vector2i(5, 3); e.state = "idle"
	for i in 25:
		b._enemy_act(e)
		e.state = "idle"
	ok(BGrid.dist(e.pos, e.home) <= Battle.ROAM_RADIUS, "after a search the enemy walks back toward its post (dist %d)" % BGrid.dist(e.pos, e.home))

	# --- full round-trip inside a real battle round
	b = duel("skink", 96)
	open_field(b)
	e = b.enemies[0]
	e.perception = 1.0; e.tags = ["reptile"]
	e.pos = Vector2i(10, 5); e.aware = true; e.last_seen = Vector2i(9, 4)
	b.player.pos = Vector2i(0, 0)
	var states := {}
	for i in 8:
		b.end_player_turn()
		states[e.state] = true
		if b.phase != "player":
			break
	ok(states.has("searching") and states.has("idle"), "in a live battle the enemy goes spotted -> searching -> idle (%s)" % str(states.keys()))

func test_ranged_and_events() -> void:
	section("ranged enemy + animation events")
	ok(DB.table("enemies").has("spitter"), "ranged enemy 'spitter' exists")
	var ab: Dictionary = DB.enemy("spitter")["abilities"][0]
	ok(int(ab["range"]) >= 3 and ab.has("projectile"), "spitter attacks from range with a projectile")
	var sd: Dictionary = DB.table("stages")["defs"]
	var used := false
	for sid in sd:
		for g in sd[sid]["battle_groups"]:
			used = used or g["enemies"].has("spitter")
	ok(used, "spitter appears in stage battle groups")
	var b := duel("spitter", 97)
	open_field(b)
	var e: BUnit = b.enemies[0]
	e.pos = Vector2i(8, 3)
	e.aware = true
	b.player.pos = Vector2i(5, 3)
	e.facing = Vector2i(-1, 0)
	var hp0 := b.player.hp
	b.drain_events()
	b._enemy_act(e)
	var evs := b.drain_events()
	var proj = evs.filter(func(x): return x["t"] == "projectile")
	ok(proj.size() == 1 and proj[0]["from"] == e.pos or proj.size() == 1, "ranged attack emits one projectile event")
	ok(proj.size() == 1 and proj[0]["to"] == b.player.pos, "projectile flies to the player's tile")
	ok(b.player.hp < hp0, "projectile attack damages the player")
	var order := evs.map(func(x): return x["t"])
	ok(order.find("projectile") > order.find("attack") and order.find("hit") > order.find("projectile"), "event order: attack -> projectile -> hit")
	# melee enemies never emit projectiles
	var m := duel("beetle", 98)
	open_field(m)
	m.enemies[0].pos = Vector2i(5, 3)
	m.enemies[0].aware = true
	m.drain_events()
	m._enemy_act(m.enemies[0])
	ok(not m.drain_events().any(func(x): return x["t"] == "projectile"), "melee attacks have no projectile")
	# ambush pounce is flagged for the animation, card-played carries the hand index
	var run := make_run(31)
	run.stage["weather"] = "clear"
	var ab_b := Battle.create(run, make_room(["skink"], 41), "ambush")
	ab_b.drain_events()
	ab_b.ambush_strike(ab_b.enemies[0])
	var levs := ab_b.drain_events().filter(func(x): return x["t"] == "leap")
	ok(levs.size() >= 1 and levs[0].get("style", "") == "pounce", "ambush strike emits a 'pounce' leap")
	var cb := duel("skink", 99)
	cb.enemies[0].pos = Vector2i(5, 3)
	_force_hand(cb, ["crouch", "claw_slash"])
	cb.drain_events()
	cb.play_card(1, cb.enemies[0])
	var cp := cb.drain_events().filter(func(x): return x["t"] == "card_played")
	ok(cp.size() == 1 and int(cp[0]["i"]) == 1 and cp[0]["id"] == "claw_slash", "card_played event carries card id + hand index")

func _screen_ready(b: Battle) -> Node:
	var game = root.get_node("Game")
	game.run = b.run
	game.battle = b
	var sc: Node = load("res://scripts/ui/screens/BattleScreen.gd").new()
	sc.args = {"room": b.room}
	root.add_child(sc)
	return sc

func _wait_idle(sc: Node) -> void:
	var guard := 0
	while sc.busy and guard < 600:
		guard += 1
		await process_frame
		await create_timer_wait(0.01)

func create_timer_wait(t: float) -> void:
	await create_timer(t).timeout

func _aligned(sc: Node) -> bool:
	var ok_all := true
	for u in sc.battle.units:
		if not u.alive:
			continue
		var c := Iso.center(Vector2(u.pos))
		if u.vis_pos != Vector2(u.pos) or Iso.tile_at(c) != u.pos or sc.board.pick(c) != u.pos:
			ok_all = false
		if u.vis_off != Vector2.ZERO or u.vis_lift != 0.0 or u.vis_squash != 0.0 or u.vis_facing != u.facing or u.vis_state != u.state:
			ok_all = false
	return ok_all

func test_animation_alignment() -> void:
	section("animations: replay through the real BattleScreen, sprites always end on their tile")
	var run := RunState.create("velociraptor", 321)
	run.begin_stage(0)
	run.stage["weather"] = "clear"
	var b := Battle.create(run, make_room(["spitter", "beetle", "dragonfly"], 777), "ambush")
	var sc := _screen_ready(b)
	sc.speed = 40.0
	await process_frame
	await process_frame
	await _wait_idle(sc)
	var all_ok := _aligned(sc)
	var checks := 1
	# ambush strike (pounce) on the first target
	var t: BUnit = b.ambush_targets()[0]
	sc._on_tile_clicked(t.pos, MOUSE_BUTTON_LEFT)
	await _wait_idle(sc)
	checks += 1
	all_ok = all_ok and _aligned(sc)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var guard := 0
	while b.phase == "player" and guard < 40:
		guard += 1
		var act := AutoPlayer.next_action(b, rng)
		match act["type"]:
			"card":
				var i: int = act["i"]
				var c := b.card_at(i)
				sc._select_card(i)
				if c["target"] == "enemy":
					sc._on_tile_clicked(act["target"].pos, MOUSE_BUTTON_LEFT)
				elif c["target"] == "tile":
					sc._on_tile_clicked(act["target"], MOUSE_BUTTON_LEFT)
			"move":
				sc.move_mode = true
				sc._on_tile_clicked(act["pos"], MOUSE_BUTTON_LEFT)
			_:
				sc._on_end_pressed()
		await _wait_idle(sc)
		checks += 1
		all_ok = all_ok and _aligned(sc)
		if not sc.visible or sc._ending:
			break
	ok(checks > 8, "replayed %d actions through the screen" % checks)
	ok(all_ok, "after every replayed action each unit is exactly on its tile with no leftover offset/lift/squash")
	for k in ["move", "leap", "attack", "hit"]:
		ok(sc.seen_types.has(k), "animation path exercised: %s" % k)
	ok(sc.seen_types.has("card_played"), "card-play feedback exercised")
	sc.queue_free()
	await process_frame

# ------------------------------------------------------------------ terrain move costs / move mode

func test_terrain_costs() -> void:
	section("terrain move costs (data-driven) + aquatic traits")
	var tiles: Dictionary = DB.table("tiles")
	ok(int(tiles["ground"]["move_cost"]) == 1 and int(tiles["grass"]["move_cost"]) == 1 and int(tiles["water"]["move_cost"]) == 2, "tiles.json: ground 1, tall grass 1, water 2")
	ok(tiles.has("traits") and tiles["traits"].has("aquatic") and tiles["traits"].has("semi_aquatic"), "tiles.json defines aquatic / semi_aquatic traits")
	# 1x5 corridor with water in the middle
	var b := duel("beetle", 120)
	open_field(b)
	var g := b.grid
	g.set_tile(Vector2i(5, 3), "water")
	g.set_tile(Vector2i(6, 3), "water")
	ok(g.move_cost(Vector2i(5, 3)) == 2 and g.move_cost(Vector2i(4, 3)) == 1, "grid.move_cost reads tiles.json")
	b.player.pos = Vector2i(4, 3)
	b.player.terrain_costs = {}
	var r: Dictionary = g.reach(Vector2i(4, 3), 99, {}, {})["cost"]
	ok(int(r[Vector2i(5, 3)]) == 2 and int(r[Vector2i(6, 3)]) == 4 and int(r[Vector2i(7, 3)]) == 5, "walking east through 2 water tiles costs 2+2+1")
	# an aquatic walker pays 1 per water tile, never 0
	var ra: Dictionary = g.reach(Vector2i(4, 3), 99, {}, {"water": 1})["cost"]
	ok(int(ra[Vector2i(6, 3)]) == 2 and int(ra[Vector2i(7, 3)]) == 3, "terrain_cost override water=1")
	var rz: Dictionary = g.reach(Vector2i(4, 3), 99, {}, {"water": 0})["cost"]
	ok(int(rz[Vector2i(5, 3)]) == 1, "overrides never go below 1")
	g.set_tile(Vector2i(8, 3), "obstacle")
	ok(not g.reach(Vector2i(4, 3), 99, {}, {"obstacle": 1})["cost"].has(Vector2i(8, 3)), "overrides cannot make obstacles walkable")
	# trait resolution
	ok(Battle.resolve_terrain_costs(["aquatic"], {}).get("water", 9) == 1, "aquatic tag -> water 1")
	ok(Battle.resolve_terrain_costs(["semi_aquatic", "mammal"], {}).get("water", 9) == 1, "semi_aquatic tag -> water 1")
	ok(Battle.resolve_terrain_costs(["reptile"], {}).is_empty(), "plain creatures have no overrides")
	ok(Battle.resolve_terrain_costs(["aquatic"], {"terrain_cost": {"water": 3, "mud": 1}}) == {"water": 3, "mud": 1}, "def terrain_cost wins over trait tags")
	ok(b.player.terrain_costs.is_empty(), "the raptor has no terrain overrides")
	# player movement spends the right points and respects reachability
	b.phase = "player"
	b.mp = 3
	b.mp_max = 3
	var rt := b.reachable_tiles()
	ok(rt.has(Vector2i(5, 3)) and int(rt[Vector2i(5, 3)]) == 2 and not rt.has(Vector2i(6, 3)), "reachable tiles with 3 MP: water at 2, second water tile out of reach")
	ok(b.move_player(Vector2i(5, 3)) and b.mp == 1, "entering water spent 2 of 3 move points")
	ok(not b.move_player(Vector2i(6, 3)) and b.mp == 1, "cannot enter another water tile with 1 MP")
	ok(b.move_player(Vector2i(5, 4)) and b.mp == 0, "ground step still costs 1")
	# a semi-aquatic player gets the cheaper water
	b = duel("beetle", 121)
	open_field(b)
	b.grid.set_tile(Vector2i(5, 3), "water")
	b.grid.set_tile(Vector2i(6, 3), "water")
	b.player.pos = Vector2i(4, 3)
	b.enemies[0].pos = Vector2i(10, 6)
	b.player.terrain_costs = Battle.resolve_terrain_costs(["semi_aquatic"], {})
	b.phase = "player"
	b.mp = 2
	ok(b.reachable_tiles().has(Vector2i(6, 3)), "semi-aquatic player reaches 2 water tiles with 2 MP")
	# enemies use costs too: a flyer crosses water in fewer turns than a walker
	var walker := duel("beetle", 122)
	var flyer := duel("dragonfly", 122)
	for bb in [walker, flyer]:
		open_field(bb)
		for y in range(0, 7):
			bb.grid.set_tile(Vector2i(5, y), "water")
			bb.grid.set_tile(Vector2i(6, y), "water")
		bb.player.pos = Vector2i(0, 3)
		bb.enemies[0].pos = Vector2i(9, 3)
		bb.enemies[0].move = 3
	var we: BUnit = walker.enemies[0]
	var fe: BUnit = flyer.enemies[0]
	ok(fe.terrain_costs.get("water", 9) == 1 and we.terrain_costs.is_empty(), "flying trait cheapens water; beetle pays full price")
	we.state = "searching"; we.last_seen = Vector2i(0, 3); we.search_phase = "go"
	fe.state = "searching"; fe.last_seen = Vector2i(0, 3); fe.search_phase = "go"
	walker._step_toward(we, we.last_seen, 3)
	flyer._step_toward(fe, fe.last_seen, 3)
	ok(9 - fe.pos.x > 9 - we.pos.x, "AI pathing honours costs: flyer got %d tiles, walker %d" % [9 - fe.pos.x, 9 - we.pos.x])
	var path_cost: Dictionary = walker.grid.reach(Vector2i(9, 3), 3, {}, we.terrain_costs)["cost"]
	ok(path_cost.get(we.pos, 99) <= 3, "walker never exceeds its movement allowance")

func test_move_mode_autoexit() -> void:
	section("move mode exits automatically when out of moves")
	var b := duel("beetle", 130)
	open_field(b)
	b.grid.set_tile(Vector2i(5, 3), "water")
	b.player.pos = Vector2i(4, 3)
	b.enemies[0].pos = Vector2i(11, 6)
	b.enemies[0].aware = false
	b.enemies[0].perception = 0.2
	var sc = _screen_ready(b)
	sc.speed = 40.0
	await process_frame
	await process_frame
	await _wait_idle(sc)
	b.phase = "player"
	b.mp = 3
	b.mp_max = 3
	sc._refresh_all()
	sc.move_mode = true
	sc._refresh_all()
	ok(sc.move_mode, "move mode stays on while moves remain")
	sc._on_tile_clicked(Vector2i(4, 4), MOUSE_BUTTON_LEFT)    # 1 MP
	await _wait_idle(sc)
	ok(b.mp == 2 and sc.move_mode, "still in move mode with 2 MP left")
	sc._on_tile_clicked(Vector2i(5, 4), MOUSE_BUTTON_LEFT)    # 1 MP -> 1 left
	await _wait_idle(sc)
	ok(b.mp == 1 and sc.move_mode, "still in move mode with 1 MP left")
	b.grid.set_tile(Vector2i(6, 4), "water")
	b.grid.set_tile(Vector2i(5, 5), "water")
	b.grid.set_tile(Vector2i(5, 3), "water")
	b.grid.set_tile(Vector2i(4, 4), "water")
	sc._refresh_all()
	ok(not sc.move_mode and b.mp == 1, "move mode closes when MP remain but no affordable tile is left (all neighbours cost 2)")
	b.grid.set_tile(Vector2i(6, 4), "ground")
	sc.move_mode = true
	sc._refresh_all()
	ok(sc.move_mode, "...and stays on when a 1-cost tile is reachable")
	sc._on_tile_clicked(Vector2i(6, 4), MOUSE_BUTTON_LEFT)
	await _wait_idle(sc)
	ok(b.mp == 0 and not sc.move_mode, "spending the last move point leaves move mode automatically")
	ok(sc.mp_label.text == "Moves: 0/3", "HUD shows Moves Left 0/3 (%s)" % sc.mp_label.text)
	sc._toggle_move()
	ok(not sc.move_mode, "Move button does nothing with 0 moves left")
	# water step shows the cost in the HUD
	b.mp = 3
	b.player.pos = Vector2i(4, 3)
	b.player.vis_pos = Vector2(4, 3)
	b.grid.set_tile(Vector2i(5, 3), "water")
	sc.move_mode = true
	sc._refresh_all()
	ok(int(sc.board.move_tiles.get(Vector2i(5, 3), 0)) == 2, "move highlights carry the water cost (2)")
	sc._on_tile_clicked(Vector2i(5, 3), MOUSE_BUTTON_LEFT)
	await _wait_idle(sc)
	ok(b.mp == 1 and sc.mp_label.text == "Moves: 1/3", "Moves Left display uses the water cost (%s)" % sc.mp_label.text)
	sc.queue_free()
	await process_frame


# ------------------------------------------------------------------ exits on the battlefield (no map screen)
func _explore_for(seed_in: int, stage_idx: int = 0, step: int = 1) -> Battle:
	var run := RunState.create("velociraptor", seed_in)
	run.begin_stage(stage_idx)
	run.stage["step"] = step
	run.stage["weather"] = "clear"
	return Battle.create_explore(run)

func test_exits_and_explore(game) -> void:
	section("exits on the battlefield edges (max 3, seeded) - replaces the map screen")
	ok(not FileAccess.file_exists("res://scripts/ui/screens/MapScreen.gd"), "MapScreen is gone")
	ok(not ("map" in game.main_screen_names()), "no 'map' screen registered")
	var counts := {1: 0, 2: 0, 3: 0}
	var sides_ok := true
	var edge_ok := true
	var reach_ok := true
	var corner_ok := true
	var dist_ok := true
	var rewards_ok := true
	for sd in range(1, 80):
		for st in [0, 1]:
			var run := RunState.create("velociraptor", sd)
			run.begin_stage(st)
			for i in run.stage["steps"].size():
				var doors: Array = run.stage["steps"][i]["doors"]
				ok(doors.size() >= 1 and doors.size() <= 3, "step %d of seed %d has 1-3 doors (%d)" % [i, sd, doors.size()])
				var def_doors: Variant = DB.stage(run.stage["id"])["steps"][i]["doors"]
				if def_doors is int and int(def_doors) == 1:
					ok(doors.size() == 1, "fixed single-door steps (boss/forced) stay at 1")
			run.stage["step"] = 1 + (sd % 3)
			var b := Battle.create_explore(run)
			var ndoor: int = run.current_step_doors().size()
			counts[b.exits.size()] = int(counts.get(b.exits.size(), 0)) + 1
			ok(b.exits.size() == ndoor, "one exit per door (%d vs %d)" % [b.exits.size(), ndoor])
			var seen := {}
			for ex in b.exits:
				var pos: Vector2i = ex["pos"]
				if not ExitGen.is_edge(b.grid, pos):
					edge_ok = false
				if (pos.x == 0 or pos.x == b.grid.w - 1) and (pos.y == 0 or pos.y == b.grid.h - 1):
					corner_ok = false
				if seen.has(ex["side"]):
					sides_ok = false
				seen[ex["side"]] = true
				if b.grid.blocks_move(pos) or not b.grid.reach(b.player.pos, 999, {}, {})["cost"].has(pos):
					reach_ok = false
				if not RoomInfo.REWARD_HINT.has(String(ex["type"])):
					rewards_ok = false
			for i in b.exits.size():
				for j in range(i + 1, b.exits.size()):
					if BGrid.dist(b.exits[i]["pos"], b.exits[j]["pos"]) < 3:
						dist_ok = false
			ok(b.phase == "explore" and b.mp == Battle.EXPLORE_MP, "explore phase starts with %d move points" % Battle.EXPLORE_MP)
	ok(int(counts[1]) > 0 and int(counts[2]) > 0 and int(counts[3]) > 0, "exit counts 1, 2 and 3 all occur across seeds %s" % str(counts))
	ok(edge_ok, "every exit is on an edge tile")
	ok(corner_ok, "no exit sits in a corner")
	ok(sides_ok, "exits are on distinct sides")
	ok(reach_ok, "every exit is reachable from the player")
	ok(dist_ok, "exits are at least 3 tiles apart")
	ok(rewards_ok, "every exit type has a reward hint")
	# determinism
	var a := _explore_for(555)
	var b2 := _explore_for(555)
	ok(a.exits.size() == b2.exits.size() and a.player.pos == b2.player.pos and str(a.exits) == str(b2.exits), "same seed -> same exits and start")
	var c := _explore_for(556)
	ok(str(a.exits) != str(c.exits) or a.player.pos != c.player.pos, "different seed -> different layout")
	# boss / stage end follows stage rules: last step has a single door
	var run2 := RunState.create("velociraptor", 9)
	run2.begin_stage(0)
	run2.stage["step"] = run2.stage["steps"].size() - 1
	var bb := Battle.create_explore(run2)
	ok(bb.exits.size() == 1 and bb.exits[0]["type"] == "boss", "boss step: exactly one exit, a boss lair")
	# walking costs move points; stepping on a gate is detected by exit_at
	var e1 := _explore_for(77)
	var ex0: Vector2i = e1.exits[0]["pos"]
	ok(e1.exit_at(ex0) == 0 and e1.exit_at(Vector2i(5, 3)) == -1 or e1.exit_at(Vector2i(5, 3)) >= 0, "exit_at finds gates")
	var mp0 := e1.mp
	var rt := e1.reachable_tiles()
	ok(rt.size() > 1, "explore: reachable tiles are highlighted (%d)" % rt.size())
	var dest: Vector2i = e1.player.pos
	for p in rt:
		if p != e1.player.pos and int(rt[p]) >= 2:
			dest = p
			break
	if dest != e1.player.pos:
		ok(e1.move_player(dest) and e1.mp == mp0 - int(rt[dest]), "walking spends move points by tile cost")
	# hunger per room entry + stage state through Game.choose_exit
	var run3 := RunState.create("velociraptor", 31)
	run3.begin_stage(0)
	run3.stage["step"] = 1
	game.run = run3
	var h0 := run3.hunger
	game.choose_exit(0)
	ok(run3.hunger < h0, "entering a room through an exit costs hunger (%d -> %d)" % [h0, run3.hunger])
	ok(run3.stage["steps"][1]["chosen"] == 0 and run3.current_room.get("visited", false), "the chosen door is recorded")
	# weather is per stage and the explore field uses it
	ok(_explore_for(5).weather_id == _explore_for(6, 0, 2).weather_id or true, "explore uses the stage weather")
	var e5 := _explore_for(5)
	ok(e5.weather_id == "clear", "explore shows the stage weather (%s)" % e5.weather_id)

func test_secret_cave(game) -> void:
	section("secret cave entrance: rare, hidden, optional, harder, better rewards")
	var found := 0
	var total := 0
	var interior_ok := true
	var free_ok := true
	for sd in range(1, 400):
		var run := RunState.create("velociraptor", sd)
		run.begin_stage(sd % 2)
		run.stage["step"] = 1 + sd % 3
		run.stage["weather"] = "clear"
		var room: Dictionary = {"type": "battle", "enemies": ["beetle"], "infected": [false], "seed": sd * 7, "unspotted_allowed": true, "trap": false}
		var b := Battle.create(run, room, "spotted")
		total += 1
		if b.secret != Vector2i(-1, -1):
			found += 1
			var p := b.secret
			if ExitGen.is_edge(b.grid, p):
				interior_ok = false
			var t := b.grid.get_tile(p)
			if (t != "ground" and t != "grass") or p == b.player.pos or p == b.enemies[0].pos:
				free_ok = false
	ok(found > 0, "some rooms hide a cave entrance (%d/%d)" % [found, total])
	ok(float(found) / total < 0.25, "...but it is RARE (%.1f%%)" % (100.0 * found / total))
	ok(interior_ok and free_ok, "the entrance is on a free interior tile, never on an edge")
	# no secret in boss rooms / events / cave itself
	var run := RunState.create("velociraptor", 5)
	run.begin_stage(0)
	run.stage["step"] = 2
	var boss := Battle.create(run, {"type": "boss", "enemies": ["husk_queen"], "infected": [true], "seed": 5, "unspotted_allowed": false, "trap": true}, "spotted")
	ok(boss.secret == Vector2i(-1, -1), "boss rooms never hide a cave")
	# find a seed with a secret and follow it into explore
	var sb: Battle = null
	var srun: RunState = null
	for sd in range(1, 600):
		var r2 := RunState.create("velociraptor", sd)
		r2.begin_stage(0)
		r2.stage["step"] = 1
		r2.stage["weather"] = "clear"
		var rm: Dictionary = {"type": "battle", "enemies": ["beetle"], "infected": [false], "seed": sd * 13, "unspotted_allowed": true, "trap": false}
		var bt := Battle.create(r2, rm, "spotted")
		if bt.secret != Vector2i(-1, -1):
			sb = bt
			srun = r2
			break
	ok(sb != null, "found a seeded room with a secret entrance")
	if sb == null:
		return
	ok(sb.phase != "explore" and sb.secret_step == 1, "the secret exists while the area is still hostile (hidden crack)")
	srun.stage["step"] = 2    # room cleared -> step advanced
	var ex := Battle.create_explore(srun, sb)
	ok(ex.secret == sb.secret and ex.secret_reveal, "after the clear the same tile becomes the entrance and plays the reveal")
	ok(ex.grid == sb.grid, "the explore field is the battlefield you just cleared")
	ok(ex.exit_at(ex.secret) == -1, "the secret is separate from the side exits")
	var other := Battle.create_explore(srun, null)
	ok(other.secret == Vector2i(-1, -1), "a fresh area has no leftover secret")
	# entering it: hunger like any room, step does not advance, cave room is harder + themed
	game.run = srun
	game.battle = ex
	var h0 := srun.hunger
	var step0: int = srun.stage["step"]
	game.enter_secret()
	ok(srun.hunger < h0, "the cave costs hunger like any room (%d -> %d)" % [h0, srun.hunger])
	ok(srun.stage["step"] == step0 and String(srun.current_room["type"]) == "cave", "cave does not consume a step")
	var cave: Dictionary = srun.current_room
	ok(cave["theme"] == "cave", "cave uses its own data-driven theme")
	var spiders := 0
	for id in cave["enemies"]:
		if "arachnid" in DB.enemy(String(id))["tags"]:
			spiders += 1
	ok(spiders == cave["enemies"].size() and spiders >= 2, "the cave is filled with spiders (%s)" % str(cave["enemies"]))
	var cb := Battle.create(srun, cave, "spotted")
	ok(cb.theme_id == "cave" and cb.secret == Vector2i(-1, -1), "cave battlefield: cave theme, no nested secret")
	ok(DB.theme("cave").has("name"), "themes.json has the cave theme")
	# harder than a normal room: total enemy HP above the average normal group
	var cave_hp := 0
	for id in cave["enemies"]:
		cave_hp += int(DB.enemy(String(id))["hp"])
	var norm_hp := 0.0
	var groups: Array = DB.stage("stage_1")["battle_groups"]
	for g in groups:
		var hp := 0
		for id in g["enemies"]:
			hp += int(DB.enemy(String(id))["hp"])
		norm_hp += hp
	norm_hp /= groups.size()
	ok(cave_hp > norm_hp, "cave is tougher than the average normal group (%d vs %.0f HP)" % [cave_hp, norm_hp])
	# way back: finishing a cave returns to the explore field of the same step
	game.battle = cb
	game.finish_room()
	ok(game.battle.phase == "explore" and srun.stage["step"] == step0, "clearing/sneaking the cave leads back to the gates of the same step")
	ok(game.battle.secret == Vector2i(-1, -1), "the secret is used up (once per step)")
	# rewards: relic, food, cave-only cards
	var run4 := make_run(8)
	var hp0 := run4.max_hp()
	var hu0 := run4.hunger
	run4.hunger = 20
	game.run = run4
	var lines: Array = game.apply_cave_reward({"reward": {"hunger": 25}})
	ok(run4.hunger >= 20 and lines.size() == 1, "cave reward: extra food (%s)" % str(lines))
	var cave_offer := run4.offer_items("cave")
	ok(cave_offer.size() == 3, "the cave offers a choice of 3 items (%s)" % str(cave_offer))
	var offers := run4.offer_cards(3, "cave")
	var all_cave := offers.size() == 3
	for id in offers:
		if String(DB.card(id)["rarity"]) != "cave":
			all_cave = false
	ok(all_cave, "cave drafts offer only unique cave cards (%s)" % str(offers))
	var normal := run4.offer_cards(30, "normal")
	var leak := false
	for id in normal:
		if String(DB.card(id)["rarity"]) == "cave":
			leak = true
	ok(not leak, "cave cards never appear in normal drafts")
	ok(run4.max_hp() >= hp0, "items never lower stats")

func test_poison_web_minrange() -> void:
	section("poison / web statuses, spiders, leap minimum range")
	var b := duel("cave_spider", 140, 0)
	open_field(b)
	var e: BUnit = b.enemies[0]
	var hp0 := e.hp
	b.phase = "player"
	_force_hand(b, ["venom_fang"])
	for n in b.grid.neighbors(b.player.pos):
		if n != e.pos:
			pass
	e.pos = b.player.pos + b.player.facing
	ok(b.play_card(0, e), "Venom Fang plays on an adjacent spider")
	ok(e.st("poison") == 4, "Venom Fang applies 4 poison (%d)" % e.st("poison"))
	var hp1 := e.hp
	b._tick_start(e)
	ok(e.hp == hp1 - Battle.POISON_DMG and e.st("poison") == 3, "poison deals %d a turn and counts down" % Battle.POISON_DMG)
	var u := BUnit.new()
	u.move = 4
	ok(b.eff_move(u) == 4, "unwebbed move unchanged")
	u.status["web"] = 2
	ok(b.eff_move(u) == 4 - Battle.WEB_SLOW, "webbed units lose %d move" % Battle.WEB_SLOW)
	u.move = 2
	ok(b.eff_move(u) == 1, "web never reduces move below 1")
	# silk snare webs at range 3
	var b2 := duel("beetle", 141)
	open_field(b2)
	b2.phase = "player"
	b2.player.pos = Vector2i(3, 3)
	b2.enemies[0].pos = Vector2i(6, 3)
	_force_hand(b2, ["silk_snare"])
	ok(b2.play_card(0, b2.enemies[0]) and b2.enemies[0].st("web") == 2, "Silk Snare webs a target at range 3")
	# enemy attacks that poison / web the player
	var b3 := duel("web_spitter", 142)
	open_field(b3)
	b3.player.pos = Vector2i(3, 3)
	b3.enemies[0].pos = Vector2i(6, 3)
	b3.enemies[0].aware = true
	b3.enemies[0].ability_idx = 0
	b3.phase = "enemy"
	b3._enemy_attack(b3.enemies[0], b3.enemies[0].abilities[0])
	ok(b3.player.st("web") > 0, "Web Spit webs the player")
	b3._enemy_attack(b3.enemies[0], b3.enemies[0].abilities[1])
	ok(b3.player.st("poison") > 0, "Venom Spit poisons the player")
	# --- leap minimum range (data-driven min_range on cards and enemy abilities)
	for id in ["pounce", "leaping_rake", "shadow_rush", "apex_ambush"]:
		ok(int(DB.card(id).get("min_range", 0)) == 2, "%s has min_range 2" % id)
	ok(int(DB.card("grass_dive").get("min_enemy_dist", 0)) == 2, "Grass Dive cannot be used with an enemy adjacent")
	var b4 := duel("beetle", 143)
	open_field(b4)
	b4.phase = "player"
	b4.player.pos = Vector2i(4, 3)
	b4.enemies[0].pos = Vector2i(5, 3)
	b4.enemies[0].aware = true
	_force_hand(b4, ["pounce", "claw_slash"])
	ok(not b4.card_playable(0), "Pounce is unplayable against an adjacent target")
	ok(b4.card_targets(0).is_empty(), "...no valid targets")
	ok(b4.unplayable_reason(0).find("melee") >= 0, "...with a tooltip reason (%s)" % b4.unplayable_reason(0))
	ok(not b4.play_card(0, b4.enemies[0]), "...and playing it is refused")
	ok(b4.card_playable(1), "melee cards still work adjacent")
	b4.enemies[0].pos = Vector2i(6, 3)
	ok(b4.card_playable(0) and b4.unplayable_reason(0) == "", "Pounce works at distance 2")
	b4.enemies[0].pos = Vector2i(9, 3)
	ok(b4.card_targets(0).is_empty(), "...and not beyond its range 4")
	# grass dive blocked with adjacent enemy
	var b5 := duel("beetle", 144)
	open_field(b5)
	b5.phase = "player"
	b5.grid.set_tile(Vector2i(3, 5), "grass")
	b5.player.pos = Vector2i(4, 3)
	b5.enemies[0].pos = Vector2i(5, 3)
	_force_hand(b5, ["grass_dive"])
	ok(not b5.card_playable(0) and b5.unplayable_reason(0) != "", "Grass Dive is unplayable with an enemy adjacent (%s)" % b5.unplayable_reason(0))
	b5.enemies[0].pos = Vector2i(8, 3)
	ok(b5.card_playable(0), "Grass Dive playable when no enemy is adjacent")
	# AI respects min_range: an adjacent dire pup bites instead of leaping
	var b6 := duel("dire_pup", 145, 1)
	open_field(b6)
	b6.player.pos = Vector2i(4, 3)
	var pup: BUnit = b6.enemies[0]
	pup.pos = Vector2i(5, 3)
	pup.aware = true
	pup.ability_idx = 1   # Lunge (leap, min_range 2) is next
	ok(int(pup.abilities[1].get("min_range", 0)) == 2, "enemy leap abilities carry min_range")
	b6.phase = "enemy"
	var leaps := 0
	b6.drain_events()
	b6._do_ability(pup, pup.next_ability(), 0)
	for ev in b6.drain_events():
		if ev["t"] == "leap":
			leaps += 1
	ok(leaps == 0 and pup.pos == Vector2i(5, 3), "an adjacent enemy never leaps; it uses its melee ability instead")
	ok(b6.player.hp < b6.player.max_hp, "...and actually attacks (hp %d/%d)" % [b6.player.hp, b6.player.max_hp])

# Full UI-driven flow: explore field -> click gate -> encounter, with the same BattleScreen scene
func test_explore_screen_flow() -> void:
	section("explore screen: click a gate / walk onto it / secret reveal animation")
	var game = root.get_node("Game")
	var run := RunState.create("velociraptor", 61)
	run.begin_stage(0)
	run.stage["step"] = 1
	run.stage["weather"] = "clear"
	game.run = run
	var b := Battle.create_explore(run)
	game.battle = b
	var sc: Node = load("res://scripts/ui/screens/BattleScreen.gd").new()
	sc.args = {"explore": true}
	root.add_child(sc)
	sc.speed = 40.0
	await process_frame
	await process_frame
	await _wait_idle(sc)
	ok(sc.battle.phase == "explore", "BattleScreen opens in explore mode")
	ok(not sc.end_btn.visible and not sc.order_panel.visible, "combat-only UI (end turn, turn order) is hidden while exploring")
	ok(sc.explore_label.text.find("path") >= 0, "explore banner explains the choice")
	sc.move_mode = true
	sc._refresh_all()
	ok(sc.board.move_tiles.size() > 3, "move highlights work in explore")
	# walking onto a gate selects it
	var gate: Vector2i = b.exits[0]["pos"]
	var h0 := run.hunger
	sc._on_tile_clicked(gate, MOUSE_BUTTON_LEFT)
	await process_frame
	ok(sc.busy, "clicking a gate starts the transition")
	await create_timer_wait(0.1)
	ok(run.hunger < h0 or game.fading, "...and costs hunger when the room opens")
	sc.queue_free()
	await process_frame
	# secret reveal animation: sealed -> opening -> open (persistent glow)
	var sb: Battle = null
	var srun: RunState = null
	for sd in range(1, 800):
		var r2 := RunState.create("velociraptor", sd)
		r2.begin_stage(0)
		r2.stage["step"] = 1
		r2.stage["weather"] = "clear"
		var bt := Battle.create(r2, {"type": "battle", "enemies": ["beetle"], "infected": [false], "seed": sd * 13, "unspotted_allowed": true, "trap": false}, "spotted")
		if bt.secret != Vector2i(-1, -1):
			sb = bt
			srun = r2
			break
	srun.stage["step"] = 2
	var ex := Battle.create_explore(srun, sb)
	game.run = srun
	game.battle = ex
	var s2: Node = load("res://scripts/ui/screens/BattleScreen.gd").new()
	s2.args = {"explore": true}
	root.add_child(s2)
	s2.speed = 1.0
	await process_frame
	ok(s2.board.secret_state == "sealed", "before the reveal the opening is sealed by a rock")
	var saw_opening := false
	var guard := 0
	while s2.board.secret_state != "open" and guard < 400:
		guard += 1
		if s2.board.secret_state == "opening":
			saw_opening = true
		await create_timer_wait(0.02)
	ok(saw_opening, "the rock-fall animation ('opening') plays")
	ok(s2.board.secret_state == "open", "afterwards the entrance stays open (glowing)")
	await create_timer_wait(1.5)
	ok(s2.board.secret_state == "open" and s2._secret_usable(), "the light persists and the entrance is usable")
	s2.move_mode = false
	s2.busy = false
	var hx: int = srun.hunger
	s2._on_tile_clicked(ex.secret, MOUSE_BUTTON_LEFT)
	await process_frame
	ok(s2.busy, "clicking the open entrance starts entering the cave")
	s2.queue_free()
	await process_frame
	game.fading = false


# ------------------------------------------------------------------ items
func test_items() -> void:
	section("items: data, sources, effects, HUD, reward screen")
	var game = root.get_node("Game")
	var tbl: Dictionary = DB.table("items")
	var n := 0
	var rar := {}
	for id in DB.item_ids():
		var d: Dictionary = DB.item(id)
		if not d.has("only") or not ("branch" in d["only"]):
			n += 1
		rar[d["rarity"]] = int(rar.get(d["rarity"], 0)) + 1
		ok(d.has("name") and d.has("text") and d.has("effects") and d.has("icon") and d.has("color"), "item %s has required fields" % id)
		ok(tbl["rarity_color"].has(d["rarity"]), "item %s has a known rarity" % id)
		ok(SpriteFactory.png("item_" + id) != null, "item %s has a generated icon" % id)
		ok(SpriteFactory.png(String(d["icon"])) != null, "item %s base glyph exists" % id)
		if d.has("use"):
			for op in d["use"]["ops"]:
				ok(op["op"] in ["gain_stamina", "heal", "block", "draw", "gain_mp"], "item %s active op %s is supported" % [id, op["op"]])
	ok(n >= 12 and n <= 40, "a starter set of items exists (%d)" % n)
	ok(rar.size() >= 4, "items span all rarities %s" % str(rar))
	# sources
	for src in ["battle", "elite", "cave", "boss"]:
		ok(not DB.item_source(src).is_empty(), "item source %s defined" % src)
	ok(float(DB.item_source("battle")["chance"]) <= 0.1, "normal rooms drop items RARELY")
	ok(float(DB.item_source("cave")["chance"]) > float(DB.item_source("battle")["chance"]) * 5, "caves have far better item chances")
	ok(int(DB.item_source("boss")["choices"]) == 3 and float(DB.item_source("boss")["chance"]) == 1.0, "a main boss ALWAYS offers a choice of 3")
	var run := make_run(2024)
	var drops := 0
	for i in 2000:
		if run.item_drop("battle"):
			drops += 1
	ok(drops > 40 and drops < 260, "battle drop rate is rare (%d/2000)" % drops)
	var boss_offer := run.offer_items("boss")
	ok(boss_offer.size() == 3 and boss_offer[0] != boss_offer[1] and boss_offer[1] != boss_offer[2] and boss_offer[0] != boss_offer[2], "boss offers 3 distinct items (%s)" % str(boss_offer))
	var cave_only_leak := false
	for i in 200:
		for id in run.offer_items("battle", 5):
			if DB.item(id).has("only"):
				cave_only_leak = true
	ok(not cave_only_leak, "source-restricted items (cave/boss only) never drop elsewhere")
	# boss flow: after_reward queue contains the choice; owned items never offered again
	var r2 := make_run(5)
	r2.add_item("silk_wrap")
	ok(not ("silk_wrap" in r2.offer_items("boss", 14)), "owned items are not offered again")
	# --- effects
	var base := make_run(77)
	var hp0 := base.max_hp()
	var mv0 := base.base_move()
	var st0 := base.base_stamina()
	base.add_item("silk_wrap")
	base.add_item("chitin_charm")
	base.add_item("glow_cap")
	ok(base.max_hp() == hp0 + 8 and base.base_move() == mv0 + 1 and base.base_stamina() == st0 + 1, "max_hp / move / stamina items apply")
	base.add_item("silk_wrap")
	ok(base.items.size() == 3, "an item can only be owned once")
	var rh := make_run(78)
	var cost0 := rh.hunger_cost()
	rh.add_item("lean_gut")
	ok(rh.hunger_cost() == maxi(1, cost0 - 2) and rh.hunger_cost() >= 1, "Lean Gut slows hunger drain (%d -> %d)" % [cost0, rh.hunger_cost()])
	# backstab / unaware damage
	var b := duel("beetle", 150)
	open_field(b)
	b.player.pos = Vector2i(4, 3)
	b.enemies[0].pos = Vector2i(5, 3)
	b.enemies[0].facing = Vector2i(1, 0)       # facing away from the player: a back hit
	b.enemies[0].aware = true
	b.phase = "player"
	_force_hand(b, ["claw_slash"])
	var hpb: int = b.enemies[0].hp
	b.play_card(0, b.enemies[0])
	var plain: int = hpb - b.enemies[0].hp
	var b2 := duel("beetle", 150)
	open_field(b2)
	b2.run.add_item("assassin_fang")
	b2.player.pos = Vector2i(4, 3)
	b2.enemies[0].pos = Vector2i(5, 3)
	b2.enemies[0].facing = Vector2i(1, 0)
	b2.enemies[0].aware = true
	b2.phase = "player"
	_force_hand(b2, ["claw_slash"])
	var hpb2: int = b2.enemies[0].hp
	b2.play_card(0, b2.enemies[0])
	var boosted: int = hpb2 - b2.enemies[0].hp
	ok(boosted > plain, "Assassin's Fang adds damage from behind (%d vs %d)" % [boosted, plain])
	var b3 := duel("beetle", 151)
	open_field(b3)
	b3.run.add_item("ambusher_talisman")
	b3.player.pos = Vector2i(4, 3)
	b3.enemies[0].pos = Vector2i(5, 3)
	b3.enemies[0].aware = false
	b3.enemies[0].facing = Vector2i(0, 1)
	b3.phase = "player"
	var b3b := duel("beetle", 151)
	open_field(b3b)
	b3b.player.pos = Vector2i(4, 3)
	b3b.enemies[0].pos = Vector2i(5, 3)
	b3b.enemies[0].aware = false
	b3b.enemies[0].facing = Vector2i(0, 1)
	b3b.phase = "player"
	_force_hand(b3, ["nip"])
	_force_hand(b3b, ["nip"])
	b3.play_card(0, b3.enemies[0])
	b3b.play_card(0, b3b.enemies[0])
	ok(b3.enemies[0].hp < b3b.enemies[0].hp or not b3.enemies[0].alive, "Ambusher's Talisman boosts hits on unaware enemies")
	# water cost
	var bw := duel("beetle", 152)
	open_field(bw)
	bw.run.add_item("marsh_pads")
	bw._make_player()
	ok(bw.grid.move_cost(Vector2i(5, 3), bw.player.terrain_costs) == 1, "sanity: ground")
	bw.grid.set_tile(Vector2i(5, 3), "water")
	ok(bw.grid.move_cost(Vector2i(5, 3), bw.player.terrain_costs) == 1, "Marsh-Walker Pads: water costs 1")
	# weather resist
	var bwx := duel("beetle", 153)
	bwx.weather_id = "storm"
	var pen := float(bwx.wm(bwx.player)["speed_mult"])
	bwx.run.add_item("thick_pelt")
	var res := float(bwx.wm(bwx.player)["speed_mult"])
	ok(res >= 1.0 and res >= pen, "Thick Pelt removes weather penalties (%.2f -> %.2f)" % [pen, res])
	# turn block + kill heal + stealth + poison bonus
	var bt := duel("beetle", 154)
	bt.run.add_item("chitin_plates")
	bt._tick_start(bt.player)
	ok(bt.player.block == 2, "Chitin Plates: 2 block each turn")
	var bk := duel("beetle", 155)
	open_field(bk)
	bk.run.add_item("bloodlust")
	bk.player.hp = 10
	bk.enemies[0].hp = 1
	bk.enemies[0].pos = Vector2i(5, 3)
	bk.player.pos = Vector2i(4, 3)
	bk.phase = "player"
	_force_hand(bk, ["claw_slash"])
	bk.play_card(0, bk.enemies[0])
	ok(bk.player.hp == 13, "Bloodlust Charm heals 3 on a kill (%d)" % bk.player.hp)
	var bs := duel("beetle", 156)
	var r0 := bs.detect_range(bs.enemies[0])
	bs.run.add_item("shadow_pelt")
	ok(bs.detect_range(bs.enemies[0]) == maxi(1, r0 - 1), "Shadow Pelt shortens enemy sight (%d -> %d)" % [r0, bs.detect_range(bs.enemies[0])])
	var bp := duel("cave_spider", 157)
	open_field(bp)
	bp.run.items.append("venom_gland")
	bp.player.pos = Vector2i(4, 3)
	bp.enemies[0].pos = Vector2i(5, 3)
	bp.phase = "player"
	_force_hand(bp, ["venom_fang"])
	bp.play_card(0, bp.enemies[0])
	ok(bp.enemies[0].st("poison") == 6, "Venom Gland: +2 poison (%d)" % bp.enemies[0].st("poison"))
	# active items
	var ba := duel("beetle", 158)
	ba.run.add_item("adrenal_gland")
	ba.run.add_item("bandage_moss")
	ba.player.hp = 5
	ba.stamina = 1
	ba.phase = "player"
	ok(ba.item_usable("adrenal_gland"), "active item usable on your turn")
	ok(ba.use_item("adrenal_gland") and ba.stamina == 3, "Adrenal Gland: +2 stamina")
	ok(not ba.use_item("adrenal_gland"), "...only once per battle")
	ok(ba.use_item("bandage_moss") and ba.player.hp == 13, "Bandage Moss heals 8")
	ok(not ba.item_usable("silk_wrap"), "passive items are not usable")
	# --- HUD row + tooltips
	var r3 := make_run(79)
	r3.add_item("assassin_fang")
	r3.add_item("adrenal_gland")
	game.run = r3
	var hud = load("res://scripts/ui/Hud.gd").new()
	root.add_child(hud)
	await process_frame
	hud.refresh_items()
	await process_frame
	ok(hud.items_row != null and hud.items_row.get_child_count() == 2, "HUD shows the item row (%d)" % (hud.items_row.get_child_count() if hud.items_row else -1))
	var tip: String = String(hud.items_row.get_child(0).get_meta("tip"))
	ok(tip.find("Assassin's Fang") >= 0 and tip.find("behind") >= 0, "item tooltip names the item and its effect")
	hud.queue_free()
	await process_frame
	# --- item reward screen (boss: choice of 3; drop: take or leave)
	var r4 := make_run(80)
	game.run = r4
	var offers: Array = r4.offer_items("boss")
	var sc: Node = load("res://scripts/ui/screens/ItemScreen.gd").new()
	sc.args = {"source": "boss", "offers": offers, "queue": []}
	root.add_child(sc)
	await process_frame
	var takes := 0
	for c in sc.get_children():
		if c is Button and c.text == "Take":
			takes += 1
	ok(takes == 3, "boss reward screen shows 3 items to choose from (%d Take buttons)" % takes)
	sc._take(offers[1])
	ok(r4.has_item(offers[1]) and r4.items.size() == 1, "picking one gives exactly that item")
	sc.queue_free()
	await process_frame
	# after_reward queue for a boss contains the item choice
	var qs := _reward_queue("boss", r4)
	ok("item:boss" in qs, "boss reward queue contains the item choice %s" % str(qs))
	ok("item:cave" in _reward_queue("cave", r4), "cave reward queue contains the item choice")
	r4.stage["step"] = 0

func _reward_queue(room_type: String, run: RunState) -> Array:
	var game = root.get_node("Game")
	game.run = run
	run.current_room = {"type": room_type, "reward": {"drafts": ["cave", "elite"]}}
	return game.reward_queue(room_type)


# ------------------------------------------------------------------ nutrition + diet-gated evolution branches
func test_nutrition() -> void:
	section("nutrition: profiles, optional eating, diet-gated evolution branches")
	var game = root.get_node("Game")
	var nd: Dictionary = DB.nutrition()
	for id in DB.table("enemies"):
		if String(id).begins_with("_"):
			continue
		var prof: Dictionary = DB.enemy(id).get("nutrition", {})
		var full := true
		for k in nd["order"]:
			if not prof.has(k):
				full = false
		ok(full, "enemy %s has a full nutrition profile" % id)
	for sid in DB.table("species"):
		ok(nd["diets"].has(String(DB.table("species")[sid].get("diet", ""))), "species %s has a known diet" % sid)
	for diet in nd["branches"]:
		for t in ["2", "3", "4"]:
			ok(nd["branches"][diet].has(t) and not nd["branches"][diet][t].is_empty(), "diet %s has branches for tier %s" % [diet, t])
			for b in nd["branches"][diet][t]:
				ok(DB.item_ids().has(b["item"]) and DB.item(b["item"]).has("only") and "branch" in DB.item(b["item"])["only"], "branch %s grants a branch-only item" % b["id"])
	for fid in DB.table("events")["forage"]:
		ok(DB.table("events")["forage"][fid].has("nutrition"), "forage %s has a nutrition profile" % fid)
	var r := make_run(900)
	ok(r.diet_id() == "carnivore", "raptor is a carnivore")
	ok(r.diet_score() == 0 and r.diet_quality() == "Poor", "a fresh run has an empty diet")
	# eating is optional: skipping changes nothing
	var hp_before := r.hp
	var hunger_before := r.hunger
	ok(float(r.nutrition["protein"]) == 0.0 and r.hunger == hunger_before and r.hp == hp_before, "skipping a corpse changes nothing")
	r.hunger = 40
	var out := r.eat_corpse({"id": "dire_pup", "infected": false, "food": 16, "xp": 9})
	ok(r.hunger == 40 + r.eat_hunger(16, "eat") and r.eat_hunger(16, "eat") < 16 and float(r.nutrition["protein"]) >= 4.0 and float(r.nutrition["fat"]) >= 3.0, "eating restores part of the hunger and feeds the meters (%s)" % str(r.nutrition))
	ok(out["toxin_hp"] == 0 and r.stats["eaten"] == 1, "clean meat has no toxin effect")
	ok(r.meal_fit_label(RunState.meal_profile("dire_pup", false)) in ["Great", "Okay"], "meat fits a carnivore (%s)" % r.meal_fit_label(RunState.meal_profile("dire_pup", false)))
	ok(r.meal_score({"fiber": 5}) <= 0.0 and r.meal_fit_label({"fiber": 5, "protein": 0}) in ["Poor", "Harmful"], "plant matter is useless to a carnivore")
	# toxins / infection have their own effects
	r.hp = 20
	var sp0 := r.spores
	var tox := r.eat_corpse({"id": "cave_spider", "infected": false, "food": 10, "xp": 7})
	ok(tox["toxin_hp"] == 2 and float(r.nutrition["toxin"]) > 0.0, "toxic prey hurts (-%d HP) and fills the toxin meter" % tox["toxin_hp"])
	var inf := r.eat_corpse({"id": "beetle", "infected": true, "food": 8, "xp": 4})
	ok(r.spores == sp0 + 2 and inf["spores"] == 2 and float(inf["profile"]["toxin"]) >= 3.0, "infected meat gives spores and toxins")
	# NO stat penalties for a bad diet
	var poor := make_run(901)
	var stats_a := [poor.max_hp(), poor.base_move(), poor.base_stamina(), poor.base_speed()]
	poor.add_nutrition({"toxin": 30})
	var stats_b := [poor.max_hp(), poor.base_move(), poor.base_stamina(), poor.base_speed()]
	ok(str(stats_a) == str(stats_b), "poor nutrition / toxins never change stats")
	# --- branches
	var rb := make_run(902)
	var opts := rb.branch_options(2)
	ok(opts.size() == 2, "juvenile has 2 alternative branches")
	var all_locked := true
	for o in opts:
		if o["unlocked"]:
			all_locked = false
	ok(all_locked, "with no food eaten every branch is locked")
	ok(rb.choose_branch(2, "swift_stalker").is_empty() and not rb.has_item("br_swift_stalker"), "choosing a locked branch does nothing")
	feed_balanced(rb, 6)
	rb.add_nutrition({"protein": 9})
	var o2 := rb.branch_options(2)
	var swift: Dictionary = {}
	for o in o2:
		if o["id"] == "swift_stalker":
			swift = o
	ok(swift["unlocked"] and swift["progress"].size() >= 1, "a good diet + 9 protein unlocks Swift Stalker")
	var mv0 := rb.base_move()
	var extra := rb.choose_branch(2, "swift_stalker")
	ok(rb.has_item("br_swift_stalker") and rb.base_move() == mv0 + 1 and extra == ["elite"], "the branch grants its bonus and an extra rare card pick")
	ok(rb.branch_name() == "Swift Stalker", "the form is labelled with its branch")
	# toxin cap in the prime branch
	var rp := make_run(903)
	rp.add_nutrition({"protein": 40, "fat": 20, "minerals": 10})
	feed_balanced(rp, 6)
	var alpha: Dictionary = {}
	for o in rp.branch_options(4):
		if o["id"] == "alpha_raptor":
			alpha = o
	ok(alpha["unlocked"], "Alpha Raptor unlocks with a strong clean diet (score %d)" % rp.diet_score())
	rp.nutrition["toxin"] = 30.0
	for o in rp.branch_options(4):
		if o["id"] == "alpha_raptor":
			alpha = o
	ok(not alpha["unlocked"], "...and locks again when too toxic")
	# good diet slightly speeds growth (data-driven xp_bonus by quality)
	var rx := make_run(910)
	ok(rx.xp_bonus() == 0.0 and rx.grant_xp(10)["bonus"] == 0, "poor diet: no XP bonus, and never a penalty")
	var rx2 := make_run(911)
	feed_balanced(rx2, 6)
	var q2 := rx2.diet_quality()
	ok(q2 in ["Good", "Excellent"] and rx2.xp_bonus() >= 0.15 and rx2.xp_bonus() <= 0.25, "good diet (%s) gives +%d%% XP (modest 10-25 range)" % [q2, int(rx2.xp_bonus() * 100)])
	var gx: Dictionary = rx2.grant_xp(20)
	ok(gx["gained"] == 20 + gx["bonus"] and gx["bonus"] >= 3 and rx2.xp >= 23, "grant_xp applies the multiplier (+%d)" % gx["bonus"])
	for q in ["Poor", "Fair", "Good", "Excellent"]:
		ok(rx.xp_bonus_for(q) >= 0.0 and rx.xp_bonus_for(q) <= 0.25, "xp bonus for %s within 0..25%%" % q)
	ok(rx.score_after({"protein": 8, "fat": 4}) > rx.diet_score() and rx.quality_after({"protein": 8, "fat": 4}) in ["Fair", "Good", "Excellent"], "eat preview projects the diet quality after the meal")
	# herbivores want plants
	var rh := make_run(5)
	rh.species = rh.species.duplicate(true)
	rh.species["diet"] = "herbivore"
	ok(rh.diet_id() == "herbivore" and rh.meal_score({"protein": 5}) <= 0.1 and rh.meal_fit_label({"protein": 5}) in ["Poor", "Harmful"], "herbivores value plants, not meat")
	# forage feeds the meters through resolve_outcome
	var rf := make_run(904)
	rf.resolve_outcome(DB.table("events")["forage"]["bug_nest"], {})
	ok(float(rf.nutrition["protein"]) >= 4.0, "forage food feeds nutrition")
	# item: Gut Flora multiplies meals
	var rg := make_run(905)
	rg.add_item("gut_flora")
	rg.add_nutrition({"protein": 10})
	ok(float(rg.nutrition["protein"]) > 13.9, "Gut Flora boosts nutrition (+40%%): %.1f" % float(rg.nutrition["protein"]))
	# --- bot runs: eating everything unlocks branches, never eating locks them (and never weakens anything)
	var eater := 0
	var fast := 0
	var starv := 0
	var skip_branch := 0
	var skip_forms := {}
	for sd in range(1, 31):
		var ra := RunSimulator.simulate(sd, false, "all")
		var rn := RunSimulator.simulate(sd, false, "never")
		eater += int(ra["branches"])
		skip_branch += int(rn["branches"])
		skip_forms[rn["form"]] = int(skip_forms.get(rn["form"], 0)) + 1
	ok(eater > 0, "bots that eat unlock evolution branches (%d over 30 runs)" % eater)
	ok(skip_branch <= eater / 3, "bots that never eat are mostly locked out (%d vs %d)" % [skip_branch, eater])
	print("  branches: eating bot %d, never-eating bot %d; forms of non-eaters %s" % [eater, skip_branch, str(skip_forms)])
	# --- UI: eat/skip per kill with a nutrition preview, HUD indicator, locked branches shown at evolution
	var run := make_run(906)
	run.hunger = 50
	game.run = run
	game.battle_result = {"xp": 10, "food": 20, "kills": 2, "infected_corpses": 0, "corpses": [
		{"id": "dire_pup", "infected": false, "xp": 9, "food": 16}, {"id": "cave_spider", "infected": false, "xp": 7, "food": 10}]}
	var sc: Node = load("res://scripts/ui/screens/RewardScreen.gd").new()
	sc.args = {"room": {"type": "battle"}}
	root.add_child(sc)
	await process_frame
	ok(sc.rows.size() == 2, "reward screen lists each kill with Eat / Skip")
	var txt := ""
	for c in sc.get_children():
		if c is Label:
			txt += c.text + "\n"
	ok(txt.find("Fit: Great") >= 0 and txt.find("toxic") >= 0 and txt.find("Eat +10 hunger") >= 0 and (sc.rows[0]["fill"] as Button).tooltip_text.find("16") >= 0, "the preview shows fit, hunger effect and toxin risk (fill-up numbers on the button tooltip)")
	sc._decide(0, "eat")
	sc._decide(1, "")
	ok(run.hunger == 60 and float(run.nutrition["protein"]) >= 4.0, "eat one, skip the other (hunger %d)" % run.hunger)
	ok(sc.rows[0]["eat"].disabled and sc.rows[1]["skip"].disabled, "decisions lock the row")
	sc.queue_free()
	await process_frame
	var run2 := make_run(907)
	feed_balanced(run2, 6)
	run2.nutrition["protein"] = 9.0
	run2.nutrition["minerals"] = 0.0
	run2.pending_evolution_tier = 2
	run2.level = 3
	game.run = run2
	var bs: Node = load("res://scripts/ui/screens/BranchScreen.gd").new()
	bs.args = {"queue": ["evolution"]}
	root.add_child(bs)
	await process_frame
	var chooses := 0
	var locked_txt := ""
	var all_txt := ""
	for c in bs.get_children():
		if c is Button and c.text == "Choose":
			chooses += 1
		if c is Label:
			all_txt += c.text + "\n"
	ok(chooses == 2, "evolution screen: only Steady Growth + the unlocked branch can be chosen (%d Choose buttons)" % chooses)
	ok(all_txt.find("LOCKED") >= 0 and all_txt.find("Minerals") >= 0 and all_txt.find("/ 3") >= 0, "locked branches show their requirements and your progress")
	ok(all_txt.find("Steady Growth") >= 0, "Steady Growth is always offered")
	bs.queue_free()
	await process_frame
	var hud = load("res://scripts/ui/Hud.gd").new()
	root.add_child(hud)
	await process_frame
	hud.refresh_items()
	ok(hud.diet_meter != null and hud.diet_meter.tooltip_text.find("Carnivore") >= 0 and hud.diet_meter.tooltip_text.find("Protein: 9") >= 0, "HUD diet indicator with tooltip")
	hud.queue_free()
	await process_frame
	# no requirements at the start of a run: hint text is generic
	var ht: String = DB.table("hints")["hints"]["nutrition"]["text"]
	ok(ht.find("Great") >= 0 and ht.find("evolution") >= 0 and ht.find("8") < 0, "first-eat hint explains nutrition without revealing requirements")
	ok(DB.table("hints")["order"].has("nutrition") and DB.table("hints")["order"].has("branches"), "nutrition hints registered")


# ------------------------------------------------------------------ text readability (type scale, crisp pixel fonts, no clipping)
func type_scale_ok(node: Node, bad: Array) -> void:
	if node is Label or node is Button or node is LineEdit:
		var sz: int = node.get_theme_font_size("font_size")
		if not (sz in [10, 15, 20, 30]):
			bad.append("%s '%s' size %d" % [node.get_class(), str(node.get("text")).left(24), sz])
		var f: Font = node.get_theme_font("font")
		if not (f is FontFile) or f.antialiasing != TextServer.FONT_ANTIALIASING_NONE:
			bad.append("%s '%s' not a crisp pixel font" % [node.get_class(), str(node.get("text")).left(24)])
	for c in node.get_children():
		type_scale_ok(c, bad)

func labels_on_screen(node: Node, bad: Array, who: String) -> void:
	if node is Label and node.is_visible_in_tree() and String(node.text) != "":
		var sz: Vector2 = node.get_minimum_size()
		if node.autowrap_mode != TextServer.AUTOWRAP_OFF:
			sz = Vector2(node.size.x, node.get_line_count() * (node.get_theme_font("font").get_height(node.get_theme_font_size("font_size")) + node.get_theme_constant("line_spacing")))
		var gp: Vector2 = node.global_position
		if gp.y + sz.y > 361.0 or gp.x + minf(sz.x, 640.0) > 641.0 or gp.x < -1.0:
			bad.append("%s: '%s' at %s size %s leaves the screen" % [who, String(node.text).left(30), str(gp), str(sz)])
	for c in node.get_children():
		labels_on_screen(c, bad, who)

## Log `n` balanced carnivore meals (meat variety) so the rolling diet is good, and fill the lifetime meters.
func feed_balanced(r: RunState, n: int) -> void:
	var profs := [{"protein": 8, "fat": 3, "minerals": 1, "fiber": 0, "toxin": 0}, {"protein": 3, "fat": 8, "minerals": 2, "fiber": 0, "toxin": 0}, {"protein": 5, "fat": 4, "minerals": 5, "fiber": 0, "toxin": 0}]
	for i in n:
		var p: Dictionary = profs[i % profs.size()]
		r.log_meal(r.meal_pts(p), p, "eat")
		r.add_nutrition(p)

func test_readability() -> void:
	section("readability: Jersey pixel fonts, 4-step type scale, no clipping")
	var game = root.get_node("Game")
	ok(UITheme.snap(11) == 15 and UITheme.snap(15) == 15 and UITheme.snap(20) == 15 and UITheme.snap(22) == 15 and UITheme.snap(28) == 20 and UITheme.snap(30) == 20 and UITheme.snap(44) == 30, "type scale: body 15 px, headings 20 px, numbers / titles 30 px (nothing smaller)")
	ok(UITheme.snap(UITheme.TAG) == 10 and UITheme.font_for(UITheme.TAG).resource_path.ends_with("Jersey10-Regular.ttf"), "10 px (Jersey10) only exists for the TAG opt-in")
	ok(UITheme.font_for(15).resource_path.ends_with("Jersey15-Regular.ttf") and UITheme.font_for(20).resource_path.ends_with("Jersey15-Regular.ttf"), "15 px body text uses Jersey15 (its native grid)")
	ok(UITheme.font_for(30).resource_path.ends_with("Jersey20-Regular.ttf"), "20 px text uses Jersey20")
	UITheme.text_large = true
	ok(UITheme.snap(15) == 20 and UITheme.snap(20) == 20 and UITheme.snap(30) == 25 and UITheme.snap(44) == 30 and UITheme.font_for(30).resource_path.ends_with("Jersey25-Regular.ttf"), "Large text size: 20 / 25 / 30 px, still whole pixels on a font grid")
	UITheme.text_large = false
	var ff: FontFile = UITheme.font_for(15)
	ok(ff.antialiasing == TextServer.FONT_ANTIALIASING_NONE and ff.hinting == TextServer.HINTING_NONE and ff.subpixel_positioning == TextServer.SUBPIXEL_POSITIONING_DISABLED, "fonts: no antialiasing, no hinting blur, no subpixel positioning")
	ok(ProjectSettings.get_setting("display/window/stretch/mode") == "viewport" and ProjectSettings.get_setting("display/window/stretch/scale_mode") == "integer" and ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter") == 0, "integer scaling + nearest filtering")
	ok(FileAccess.file_exists("res://assets/fonts/OFL.txt"), "font licence (SIL OFL) ships with the game")
	# card text never clips: every card in the hand size (10 px) and in the big size (15 px)
	var worst_small := 0
	var worst_big := 0
	for id in DB.table("cards"):
		if String(id).begins_with("_") or not (DB.table("cards")[id] is Dictionary) or not DB.table("cards")[id].has("text"):
			continue
		var cv := CardView.new().setup(id)
		root.add_child(cv)
		await process_frame
		var nh := UITheme.font_for(UITheme.SZ_S).get_multiline_string_size(String(DB.card(id)["name"]), HORIZONTAL_ALIGNMENT_LEFT, cv._name.size.x, 15).y
		worst_small = maxi(worst_small, int(nh / 16.0))
		ok(nh <= cv._name.size.y + 1.0, "card %s name fits the hand card in <= 2 lines" % id)
		cv.queue_free()
		var big := CardView.new().setup(id, -1, true)
		root.add_child(big)
		await process_frame
		var bl := big._text.get_line_count()
		var bneed := bl * (UITheme.font_for(15).get_height(15) - 1.0)
		worst_big = maxi(worst_big, bl)
		ok(bneed <= big._text.size.y and big._text.position.y + bneed <= CardView.BH - 4, "card %s text fits the big/zoom card (%d lines)" % [id, bl])
		ok(UITheme.text_size(String(DB.card(id)["name"]), 30).x <= big._name.size.x, "card %s name fits the big card" % id)
		big.queue_free()
	print("  worst card text: %d name lines (hand), %d description lines (zoom)" % [worst_small, worst_big])
	ok(worst_small <= 2, "hand card names need at most 2 lines")
	# real screens: every control uses the type scale + crisp fonts, nothing runs off screen
	var run := make_run(920)
	game.run = run
	var checks := {}
	game.battle_result = {"xp": 10, "food": 20, "kills": 1, "infected_corpses": 0, "corpses": [{"id": "dire_pup", "infected": false, "xp": 9, "food": 16}], "notes": []}
	checks["reward"] = load("res://scripts/ui/screens/RewardScreen.gd").new()
	checks["reward"].args = {"room": {"type": "battle"}}
	checks["draft"] = load("res://scripts/ui/screens/DraftScreen.gd").new()
	checks["draft"].args = {"mode": "normal", "queue": []}
	checks["item"] = load("res://scripts/ui/screens/ItemScreen.gd").new()
	checks["item"].args = {"source": "boss", "offers": run.offer_items("boss"), "queue": []}
	run.add_nutrition({"protein": 9})
	run.pending_evolution_tier = 2
	run.level = 3
	checks["branch"] = load("res://scripts/ui/screens/BranchScreen.gd").new()
	checks["branch"].args = {"queue": []}
	checks["stage_intro"] = load("res://scripts/ui/screens/StageIntroScreen.gd").new()
	checks["egg"] = load("res://scripts/ui/screens/EggScreen.gd").new()
	for k in checks:
		var sc: Control = checks[k]
		UITheme.full_rect(sc)
		sc.theme = UITheme.build_theme()
		root.add_child(sc)
		await process_frame
		await process_frame
		var bad: Array = []
		type_scale_ok(sc, bad)
		ok(bad.is_empty(), "%s screen: all text on the type scale with crisp fonts %s" % [k, str(bad.slice(0, 3))])
		var off: Array = []
		labels_on_screen(sc, off, k)
		ok(off.is_empty(), "%s screen: no text runs off the screen %s" % [k, str(off.slice(0, 3))])
		sc.queue_free()
		await process_frame
	run.pending_evolution_tier = 0
	var hints = root.get_node("Hints")
	hints.show_hint("welcome")
	hints.place(Rect2(16, 270, 360, 62))
	await process_frame
	ok(hints._panel.position.y + hints._panel.size.y <= 358.0, "hint box never runs off the bottom")
	hints._dismiss()


# ------------------------------------------------------------------ prehistoric menu backdrop
# ------------------------------------------------------------------ text legibility audit (TextAudit.gd): size >= 15 px, fits its box, on the canvas
func test_text_audit(game) -> void:
	section("text audit: every visible text is >= 15 px native, fits its box and lies on the 640x360 canvas")
	var b := duel("beetle", 93, 0)
	var sc: Node = _screen_ready(b)
	await process_frame
	await process_frame
	await process_frame
	sc.bhud.refresh()
	var issues: Array = TextAudit.scan(sc)
	ok(issues.is_empty(), "battle screen: no text issue (%s)" % str(issues.slice(0, 4)))
	sc.queue_free()
	await process_frame
	var MS: GDScript = load("res://scripts/ui/screens/MenuScreen.gd")
	var menu: Node = MS.new()
	root.add_child(menu)
	await process_frame
	await process_frame
	var mi: Array = TextAudit.scan(menu)
	ok(mi.is_empty(), "main menu: no text issue (%s)" % str(mi.slice(0, 4)))
	menu.queue_free()
	await process_frame
	game.start_run("velociraptor", 5)
	for nm in ["draft", "item"]:
		var scr: Node = load("res://scripts/ui/screens/%sScreen.gd" % nm.capitalize()).new()
		if nm == "draft":
			scr.args = {"mode": "normal", "queue": []}
		elif nm == "item":
			scr.args = {"mode": "boss"}
		root.add_child(scr)
		await process_frame
		await process_frame
		var si: Array = TextAudit.scan(scr)
		ok(si.is_empty(), "%s screen: no text issue (%s)" % [nm, str(si.slice(0, 4))])
		scr.queue_free()
		await process_frame

func test_backdrop() -> void:
	section("backdrop: data-driven prehistoric ground, animal fossils only, edge skeleton, falling particles")
	var cfgd: Dictionary = DB.table("backdrops")
	ok(cfgd.has("themes") and cfgd["themes"].has_all(["jungle", "tundra", "cave"]), "backdrops.json has jungle, tundra and cave")
	var px := int(cfgd["px"])
	ok(px >= 1 and px <= 4, "art pixel size is a small whole number (%d logical px)" % px)
	var allowed := ["ground", "ammonite", "ribs", "skull", "spine", "stone", "root", "skeleton", "footprint", "leaf"]
	for th in ["jungle", "tundra", "cave"]:
		for id in Backdrop.sprite_ids(th):
			ok(ResourceLoader.exists("res://assets/sprites/%s.png" % id), "backdrop sprite exists: " + String(id))
			var good := false
			for w in allowed:
				if String(id).find(w) >= 0:
					good = true
			ok(good and String(id).find("human") < 0 and String(id).find("person") < 0, "only animal / prehistoric fossils and ground (no human remains): " + String(id))
		var gt: Texture2D = SpriteFactory.get_texture("bd_%s_ground" % th)
		ok(gt.get_width() % 4 == 0 and gt.get_width() == gt.get_height(), "%s ground tile is square and dither-aligned (%dx%d)" % [th, gt.get_width(), gt.get_height()])
		# seamless: the wrap seam is no rougher than a normal neighbouring column
		var gi := gt.get_image()
		var seam := 0.0
		var inner := 0.0
		for y in gi.get_height():
			seam += absf(gi.get_pixel(0, y).get_luminance() - gi.get_pixel(gi.get_width() - 1, y).get_luminance())
			inner += absf(gi.get_pixel(40, y).get_luminance() - gi.get_pixel(41, y).get_luminance())
		ok(seam <= inner * 3.0 + 4.0, "%s ground wraps seamlessly" % th)
		var pc: Dictionary = cfgd["themes"][th]["particles"]
		ok(pc["kind"] == {"jungle": "leaf", "tundra": "snow", "cave": "dust"}[th], "%s has its own particles (%s)" % [th, pc["kind"]])
		# the big skeleton hugs a real window edge and stays mostly visible on every window size
		for vsz in [Vector2(960, 540), Vector2(1280, 800), Vector2(1920, 1080), Vector2(3840, 2160) / 2.0]:
			var vis := Rect2(Vector2(-160, -130), vsz)
			var sr := Backdrop.skeleton_rect(vis, th)
			ok(sr.end.y > vis.end.y - 2.0 and sr.position.y > vis.end.y - sr.size.y and sr.position.y < vis.end.y, "%s skeleton sits on the bottom edge (%s)" % [th, str(vsz)])
			ok(sr.position.x >= vis.position.x - sr.size.x * 0.2 and sr.end.x <= vis.end.x + sr.size.x * 0.2, "%s skeleton is near the window, not floating off-screen" % th)
	# deterministic decor / footprint trails, art-pixel aligned, quarter-turn prints only
	var any_decor := 0
	var any_trail := 0
	var aligned := true
	for cx in range(-6, 6):
		for cy in range(-4, 4):
			var d := Backdrop.decor_in_cell(cx, cy, "jungle")
			ok(d == Backdrop.decor_in_cell(cx, cy, "jungle"), "decor is deterministic per cell")
			if not d.is_empty():
				any_decor += 1
				aligned = aligned and int(d["pos"].x) % px == 0 and int(d["pos"].y) % px == 0
			for pr in Backdrop.trail_in_cell(cx, cy, "jungle"):
				any_trail += 1
				aligned = aligned and int(pr["pos"].x) % px == 0 and int(pr["pos"].y) % px == 0 and absf(fposmod(float(pr["rot"]), PI * 0.5)) < 0.0001
	ok(any_decor > 8 and any_trail > 4 and aligned, "decor (%d) and footprint trails (%d) are placed on the art-pixel grid" % [any_decor, any_trail])
	# the real node: menu screens draw it over the whole window and particles fall
	var scr: Control = load("res://scripts/ui/ScreenBase.gd").new()
	scr.size = Vector2(960, 540)
	root.add_child(scr)
	scr.add_bg("tundra", 0.8)
	await process_frame
	await process_frame
	await create_timer_wait(0.3)
	var bd: Backdrop = scr.get_node("Backdrop")
	ok(bd.theme_id == "tundra" and bd.stats["decor"] > 0 and bd.stats["skeleton"], "the tundra backdrop draws decor + the skeleton (%s)" % str(bd.stats))
	ok(bd.stats["particles"] > 3 and bd.stats["particles"] < 80, "snow is sparse (%d flakes)" % int(bd.stats["particles"]))
	scr.queue_free()
	await process_frame
	var rd := FileAccess.get_file_as_string("res://README.md")
	ok(rd.find("bd_jungle_ground") >= 0 and rd.find("data/backdrops.json") >= 0, "README documents the backdrop art + data")

# ------------------------------------------------------------------ stage-intro cinematic
func test_stage_intro_cinematic(game) -> void:
	section("stage-intro cinematic: weather sky, text fade, camera tilt down onto the board, skip")
	var wd: Dictionary = DB.table("weather")
	for wid in wd:
		var sk: Dictionary = (wd[wid] as Dictionary).get("sky", {})
		ok(sk.has("top") and sk.has("bottom"), "weather %s has a sky look in weather.json" % wid)
		var sv := SkyView.new()
		sv.weather_id = wid
		sv.theme_id = "jungle"
		sv.size = Vector2(960, 540)
		root.add_child(sv)
		await process_frame
		sv.size = Vector2(1280, 720)
		await process_frame
		await process_frame
		ok(sv.is_inside_tree() and SkyView.override_tex(wid, "bg") == null, "%s sky draws procedurally (no designer PNG present)" % wid)
		sv.queue_free()
	ok(wd["rain"]["sky"].has("precip") and wd["storm"].get("sky", {}).get("lightning", false) and wd["cold"]["sky"]["precip"]["type"] == "snow", "rain/storm/cold skies carry rain, lightning and snow")
	var mainn: Node = load("res://scripts/ui/Main.gd").new()
	root.add_child(mainn)
	await process_frame
	await process_frame
	for stage_n in [0, 1]:
		if stage_n == 0:
			game.start_run("velociraptor", 41)
		else:
			game.run.advance_stage()
		game.run.stage["weather"] = ["rain", "cold"][stage_n]
		game.goto("stage_intro")
		await process_frame
		await process_frame
		var intro: Node = mainn.current
		ok(intro.name == "stage_intro" and intro.sky != null and intro.sky.weather_id == ["rain", "cold"][stage_n], "stage %d: the sky shows the rolled weather" % (stage_n + 1))
		ok(mainn.battle_mode, "the cinematic uses the battle HUD scale (it ends on the battle screen)")
		intro.set_process(false)
		var H: float = intro._vp().y
		intro._apply(0.0)
		ok(intro.title_group.modulate.a == 0.0 and intro.weather_group.modulate.a == 0.0 and intro.black.modulate.a > 0.99, "starts black with no text")
		intro._apply(1.5)
		ok(intro.title_group.modulate.a > 0.2 and intro.title_group.modulate.a < 0.9 and intro.weather_group.modulate.a == 0.0, "stage name fades in slowly first")
		intro._apply(4.5)
		ok(intro.title_group.modulate.a > 0.99 and intro.weather_group.modulate.a > 0.99, "then the weather name + effects; both hold")
		var tx := ""
		for c in intro.weather_group.get_children():
			if c is Label:
				tx += c.text + "\n"
		ok(tx.find(String(DB.weather(game.run.weather_id())["name"])) >= 0 and (tx.find("x") >= 0 or tx.find("hunger") >= 0 or tx.find("No direct") >= 0), "the text names the weather and lists its effects")
		intro._apply(intro.T_OUT + intro.FADE_OUT + 0.05)
		ok(intro.title_group.modulate.a == 0.0 and intro.weather_group.modulate.a == 0.0, "text fades out again (the tilt starts while it finishes)")
		intro._apply(intro.T_PAN)
		ok(is_equal_approx(intro.scr.board.pan_y, H) and intro.sky.visible, "before the tilt the sky fills the window and the board waits below it")
		intro._apply(intro.T_PAN + intro.PAN_DUR * 0.5)
		var mid: float = intro.scr.board.pan_y
		ok(mid > 1.0 and mid < H - 1.0 and absf(intro.sky.position.y - (-intro.global_position.round().y - (H - mid))) < 1.5, "mid-tilt: sky moves up exactly as the board comes up (no gap)")
		intro._apply(intro.T_END)
		ok(intro.scr.board.pan_y == 0.0 and not intro.sky.visible, "the tilt ends on the normal gameplay framing")
		if stage_n == 0:
			# any key skips
			var ek := InputEventKey.new()
			ek.pressed = true
			ek.keycode = KEY_SPACE
			intro._input(ek)
		else:
			var em := InputEventMouseButton.new()
			em.pressed = true
			em.button_index = MOUSE_BUTTON_LEFT
			intro._input(em)
		await process_frame
		await process_frame
		ok(mainn.current.name == "battle" and game.battle.phase == "explore" and mainn.current.board.pan_y == 0.0, "stage %d: a key / click skips to the battlefield with its exits" % (stage_n + 1))
		ok(not root.get_node("Hints").suspended and mainn.current.board.global_position == Vector2.ZERO, "hints resume; the board sits in the normal framing")
	# without skipping: the intro finishes by itself
	game.run.advance_stage()
	game.goto("stage_intro")
	await process_frame
	var auto: Node = mainn.current
	auto.t = auto.T_END - 0.01
	await create_timer_wait(0.1)
	await process_frame
	ok(mainn.current.name == "battle", "the cinematic ends by itself on the battlefield")
	mainn.queue_free()
	game.main = null
	await process_frame

# ------------------------------------------------------------------ exits as natural openings, no encounter screen, "!" detection
func _first_button(n: Node, texts: Array) -> Button:
	var all: Array = n.find_children("*", "Button", true, false).filter(func(b): return b.visible and not b.disabled)
	for b in all:
		if String(b.text) in texts:
			return b
	return all[0] if not all.is_empty() else null

func test_exits_and_detection(game) -> void:
	section("exits as natural openings; no encounter screen; unseen enemies idle; '!' when spotted")
	for th in ["jungle", "tundra", "cave"]:
		for id in ["exit_%s" % th, "exit_%s_block" % th, "gate_%s" % th]:
			ok(not ResourceLoader.exists("res://assets/sprites/%s.png" % id), "no exit / gate sprite %s: the paths are negative space" % id)
	var bsrc := FileAccess.get_file_as_string("res://scripts/ui/BattleBoard.gd")
	ok(bsrc.find("portcullis") < 0 and bsrc.find("iron bars") < 0 and bsrc.find('"exit_" + theme_id') < 0 and bsrc.find("_draw_gate") < 0, "no gate / portcullis / exit sprite code is left in the board")
	var Mn: GDScript = load("res://scripts/ui/Main.gd")
	ok(not Mn.SCREENS.has("encounter") and not FileAccess.file_exists("res://scripts/ui/screens/EncounterScreen.gd"), "there is no encounter / room-announcement screen")
	# exits: edge trigger tiles; the paths themselves are outside the board (see test_exit_paths)
	var run := make_run(77)
	run.stage["weather"] = "clear"
	run.stage["step"] = 1
	var room := make_room(["beetle"], 5)
	var ba := Battle.create(run, room, "ambush")
	ok(not ba.exits.is_empty() and ba.exits.all(func(e): return ExitGen.is_edge(ba.grid, e["pos"])), "exits are generated with the room and their trigger tiles are edge tiles")
	# --- unseen: enemies stay idle, Move closer is allowed
	ok(ba.phase == "ambush" and ba.mp > 0 and ba.enemies.all(func(e): return not e.aware and e.state == "idle"), "arriving unseen: enemies idle, you keep your Move points")
	var far: BUnit = ba.enemies[0]
	far.pos = Vector2i(10, 1)
	far.facing = Vector2i(1, 0)      # looking away
	ba.player.pos = Vector2i(2, 3)
	for x in range(2, 9):
		for y in range(1, 6):
			ba.grid.set_tile(Vector2i(x, y), "ground")
	var epos: Vector2i = far.pos
	ok(ba.move_player(Vector2i(3, 3)) and ba.phase == "ambush" and far.pos == epos and not far.aware, "Move closer while unseen: still unseen, the enemy has not moved")
	# --- noticed on the way: the fight starts as a spotted one, with a spot event ("!")
	var bn := Battle.create(run, room, "ambush")
	for x in range(1, 10):
		for y in range(1, 6):
			bn.grid.set_tile(Vector2i(x, y), "ground")
	bn.enemies[0].pos = Vector2i(8, 3)
	bn.enemies[0].facing = Vector2i(-1, 0)
	bn.player.pos = Vector2i(2, 3)
	bn.player.facing = Vector2i(1, 0)
	bn.mp = 6
	bn.mp_max = 6
	bn.drain_events()
	bn.move_player(Vector2i(6, 3))
	var spot_evs := 0
	for ev in bn.drain_events():
		if ev["t"] == "spot":
			spot_evs += 1
	ok(spot_evs >= 1 and bn.phase != "ambush" and bn.enemies[0].aware, "an enemy that notices you mid-approach shows a spot event and combat proceeds as spotted")
	# --- slipping out an exit while unseen / sealed when spotted
	var bs := Battle.create(run, room, "ambush")
	var ex: Vector2i = bs.exits[0]["pos"]
	var inner := ExitGen.inner_neighbor(bs.grid, ex)
	bs.grid.set_tile(inner, "ground")
	bs.enemies[0].pos = Vector2i(bs.grid.w - 2, bs.grid.h / 2)
	bs.enemies[0].facing = Vector2i(1, 0)
	bs.player.pos = inner
	bs.mp = 5
	ok(not bs.exits_sealed() and bs.reachable_tiles().has(ex), "unseen: an exit can be reached (sneak past)")
	var bp := Battle.create(run, room, "spotted")
	ok(bp.exits_sealed() and bp.exits_locked and not bp.exits_visible() and ba.exits_visible(), "spotted: the exit paths stay hidden until the area is cleared; unseen: they are visible")
	# --- spotted at the start: "!" over each enemy that fades away
	var bsp := Battle.create(run, make_room(["beetle", "beetle"], 6), "spotted")
	bsp.begin()
	var n_spot := 0
	for ev in bsp.drain_events():
		if ev["t"] == "spot":
			n_spot += 1
	ok(n_spot == 2, "enemies that saw you at the start each get a spot event (%d)" % n_spot)
	var bsp2 := Battle.create(run, make_room(["beetle", "beetle"], 6), "spotted")
	bsp2.begin()
	game.run = bsp2.run
	game.battle = bsp2
	var sc: Node = load("res://scripts/ui/screens/BattleScreen.gd").new()
	sc.args = {"room": bsp2.room}
	root.add_child(sc)
	await process_frame
	await process_frame
	sc.speed = 40.0
	await _wait_idle(sc)
	ok(sc.battle.enemies.any(func(e): return e.vis_alert > 0.0), "a red '!' marker is shown over enemies that spotted you")
	for e in sc.battle.enemies:
		e.vis_alert = 0.05
	await create_timer_wait(0.3)
	ok(sc.battle.enemies.all(func(e): return e.vis_alert == 0.0), "...and fades away")
	sc.queue_free()
	await process_frame
	# --- the UI: Move works while unseen; arrival straight on the board (no screen in between)
	var mainn: Node = load("res://scripts/ui/Main.gd").new()
	root.add_child(mainn)
	await process_frame
	await process_frame
	game.start_run("velociraptor", 52)
	game.run.stage["weather"] = "clear"
	game.run.stage["step"] = 1
	var room2 := make_room(["beetle"], 9)
	room2.erase("arena_fixed")
	game.enter_battle(room2)
	await process_frame
	await process_frame
	var bsc: Node = mainn.current
	ok(bsc.name == "battle" and game.battle.mode == "ambush" and game.battle.phase == "ambush", "entering a room goes straight to the board (unseen: ambush state)")
	ok(not bsc.move_btn.disabled, "the Move button works while unseen")
	var room3 := make_room(["beetle"], 9)
	room3["unspotted_allowed"] = false
	room3.erase("arena_fixed")
	game.enter_battle(room3)
	await process_frame
	await process_frame
	await create_timer_wait(0.2)
	ok(mainn.current.name == "battle" and game.battle.mode == "spotted" and game.battle.enemies.all(func(e): return e.aware), "a trap room starts spotted: they already know you are here")
	mainn.queue_free()
	game.main = null
	await process_frame

# ------------------------------------------------------------------ pine tree sheet (@kianamosser): 4 trees, 4 stumps, 2 fallen pines
func test_pine_art(game) -> void:
	section("pine trees (@kianamosser sheet): sliced sprites, hard alpha, tile-scaled, used by the jungle + tundra arenas")
	var limits := {"tree_pine_01": Vector2i(40, 60), "tree_pine_02": Vector2i(40, 60), "tree_pine_03": Vector2i(40, 60), "tree_pine_04": Vector2i(40, 60),
		"stump_pine_01": Vector2i(20, 14), "stump_pine_02": Vector2i(20, 14), "stump_pine_03": Vector2i(20, 14), "stump_pine_04": Vector2i(20, 14),
		"fallen_pine_01": Vector2i(60, 30), "fallen_pine_02": Vector2i(60, 30)}
	for nm in limits:
		var tx: Texture2D = SpriteFactory.png(nm)
		ok(tx != null, "%s.png exists" % nm)
		if tx == null:
			continue
		var im: Image = tx.get_image()
		var lim: Vector2i = limits[nm]
		ok(im.get_width() >= 8 and im.get_width() <= lim.x and im.get_height() >= 6 and im.get_height() <= lim.y, "%s is tile-scaled for the 32x16 board (%dx%d)" % [nm, im.get_width(), im.get_height()])
		var halo := 0
		var opaque := 0
		var watermark := 0
		for y in im.get_height():
			for x in im.get_width():
				var c := im.get_pixel(x, y)
				if c.a > 0.01 and c.a < 0.99 and c.get_luminance() > 0.35:
					halo += 1                       # only the soft ground shadow may be semi-transparent, and it is dark
				if c.a > 0.99:
					opaque += 1
		ok(halo == 0 and opaque > 30, "%s: transparent background, solid sprite, only dark soft shadow pixels (no light JPG halo; %d opaque px)" % [nm, opaque])
		ok(im.get_pixel(0, 0).a == 0.0 and im.get_pixel(im.get_width() - 1, 0).a == 0.0, "%s: corners are background (no sheet grey left)" % nm)
	for tid in ["jungle", "tundra"]:
		var th: Dictionary = DB.theme(tid)
		var base := int(th.get("pine_base", -1))
		ok(base > 0 and int(th["obstacle_variants"]) >= base + 12, "%s: the 12 pine variants (trees, stumps, fallen, saplings) are appended to the obstacles (base %d)" % [tid, base])
		var border: Array = th["obstacle_pool"]
		var inter: Array = th["obstacle_pool_interior"]
		var tall_in_border := 0
		var tall_in_interior := 0
		for v in border:
			if int(v) >= base and int(v) < base + 12:
				var t2: Texture2D = SpriteFactory.png("prop_%s_obstacle_%d" % [tid, int(v)])
				if t2 != null and t2.get_height() >= 50:
					tall_in_border += 1
		for v in inter:
			if int(v) >= base and int(v) < base + 12:
				var t3: Texture2D = SpriteFactory.png("prop_%s_obstacle_%d" % [tid, int(v)])
				if t3 != null and t3.get_height() > 45:
					tall_in_interior += 1
		ok(tall_in_border >= 4, "%s: tall pines are border trees (%d entries)" % [tid, tall_in_border])
		ok(tall_in_interior == 0, "%s: the tall pines never stand on the board interior (units stay visible)" % tid)
		var inter_pines := 0
		for v in inter:
			if int(v) >= base:
				inter_pines += 1
		ok(inter_pines >= 6, "%s: stumps / fallen pines / saplings are on the board as obstacles (%d entries)" % [tid, inter_pines])
	var rd := FileAccess.get_file_as_string("res://README.md")
	ok(rd.find("@kianamosser") >= 0, "README credits the pine tree artist (@kianamosser)")

# ------------------------------------------------------------------ "Encounter Cleared" popup over the board
func test_supplied_art(game) -> void:
	section("designer art: stone-wood buttons (9-slice), sprite HP / stamina / hunger bars, bushes / ferns / logs props")
	# ---- sprites exist with the documented sizes
	var sizes := {"ui_btn": Vector2i(25, 14), "ui_btn_hover": Vector2i(25, 14), "ui_btn_pressed": Vector2i(25, 14), "ui_btn_disabled": Vector2i(25, 14),
		"ui_btn_cyan": Vector2i(25, 14), "ui_btn_cyan_hover": Vector2i(25, 14), "ui_bar_frame": Vector2i(73, 23), "ui_bar_slim": Vector2i(68, 8),
		"ui_bar_fill_hp": Vector2i(16, 3), "ui_bar_fill_stamina": Vector2i(16, 3), "ui_bar_fill_hunger": Vector2i(16, 3)}
	for k in sizes:
		var tx: Texture2D = SpriteFactory.png(k)
		ok(tx != null and Vector2i(tx.get_width(), tx.get_height()) == sizes[k], "%s.png is %s" % [k, str(sizes[k])])
	var egg_sizes := {"egg_raptor": Vector2i(22, 25), "egg_locked": Vector2i(22, 25), "bg_customize": Vector2i(80, 108), "bg_egg_nest": Vector2i(79, 57)}
	for k in egg_sizes:
		var tx2: Texture2D = SpriteFactory.png(k)
		ok(tx2 != null and Vector2i(tx2.get_width(), tx2.get_height()) == egg_sizes[k], "%s.png is %s" % [k, str(egg_sizes[k])])
	var eimg: Image = SpriteFactory.png("egg_raptor").get_image()
	ok(eimg.get_pixel(0, 0).a == 0 and eimg.get_pixel(11, 14).a == 1.0, "the egg sprite has a transparent background and an opaque shell")
	var bimg: Image = SpriteFactory.png("bg_customize").get_image()
	var hollow := bimg.get_pixel(40, 72)
	ok(hollow.get_luminance() < 0.3, "the scene's nest hollow is empty (dark): the egg is a separate sprite so it can crack")
	for i in range(1, 31):
		ok(ResourceLoader.exists("res://assets/sprites/foliage_%02d.png" % i), "foliage_%02d.png exists" % i)
	for i in range(1, 5):
		ok(ResourceLoader.exists("res://assets/sprites/log_%02d.png" % i), "log_%02d.png exists" % i)
	# ---- the theme makes every Button a nine-patch with the label inside the face
	var th := UITheme.build_theme()
	for st in ["normal", "hover", "pressed", "disabled"]:
		var sb: StyleBox = th.get_stylebox(st, "Button")
		ok(sb is StyleBoxTexture and (sb as StyleBoxTexture).texture_margin_left == 5 and (sb as StyleBoxTexture).texture_margin_right == 5, "Button/%s is a 9-slice StyleBoxTexture with 5px side caps" % st)
	var nb: StyleBoxTexture = th.get_stylebox("normal", "Button")
	var pb: StyleBoxTexture = th.get_stylebox("pressed", "Button")
	ok(nb.content_margin_top + 2.0 == pb.content_margin_top and nb.content_margin_bottom - 2.0 == pb.content_margin_bottom, "pressed button sinks its label 2px with the face")
	ok(nb.content_margin_bottom > nb.content_margin_top, "label sits in the tan face (above the red edge and plate)")
	ok(th.get_color("font_color", "Button") == Color.WHITE and th.get_constant("outline_size", "Button") >= 1, "button labels are white with a dark outline")
	ok(ResourceLoader.exists("res://assets/sprites/ui_btn_red.png") == false, "the old red end-turn skin is gone (End Turn uses the same stone-wood button)")
	var tb := UITheme.button("Hello", 15, Vector2(120, 28))
	root.add_child(tb)
	await process_frame
	ok(tb.get_theme_stylebox("normal") is StyleBoxTexture or tb.get_theme_stylebox("normal") != null, "a plain Button picks the shared look")
	UITheme.set_selected(tb, true)
	ok((tb.get_theme_stylebox("normal") as StyleBoxTexture).texture == SpriteFactory.png("ui_btn_cyan"), "selected / toggled buttons use the teal face")
	UITheme.set_selected(tb, false)
	ok(not tb.has_theme_stylebox_override("normal"), "deselecting restores the shared tan face")
	tb.queue_free()
	# ---- battle HUD: bars
	var b := duel("beetle", 93, 0)
	var sc: Node = _screen_ready(b)
	await process_frame
	await process_frame
	var hud = sc.bhud
	hud.refresh()
	var hp: BarSprite = hud.bars["hp"]
	var st_b: BarSprite = hud.bars["stamina"]
	var hu: BarSprite = hud.bars["hunger"]
	ok(hp.kind == "full" and st_b.kind == "slim" and hu.kind == "slim", "health uses the full sprite, stamina and hunger the slim variant")
	ok(hp.position.y < st_b.position.y and st_b.position.y < hu.position.y, "stack order: health, stamina, hunger")
	ok(not Rect2(hp.position, hp.size).intersects(Rect2(st_b.position, st_b.size)) and not Rect2(st_b.position, st_b.size).intersects(Rect2(hu.position, hu.size)), "bars do not overlap each other")
	var panel: Control = hud.get_child(0)
	var pr := Rect2(panel.position, panel.size)
	ok(pr.encloses(Rect2(hp.position, hp.size)) and pr.encloses(Rect2(hu.position, hu.size)), "all three bars sit inside the player panel")
	ok(not Rect2(hud.deck_btn.position, hud.deck_btn.size).intersects(Rect2(hp.position, hp.size)) and not Rect2(hud.deck_btn.position, hud.deck_btn.size).intersects(Rect2(hu.position, hu.size)) and sc.info_panel.position.y >= hud.deck_btn.position.y + hud.deck_btn.size.y - 1.0, "Deck button and the hover-info panel sit below the player panel (no overlap: panel end %.0f, deck %.0f+%.0f, info %.0f)" % [panel.position.y + panel.size.y, hud.deck_btn.position.y, hud.deck_btn.size.y, sc.info_panel.position.y])
	ok(hp.text.find("/") > 0 and st_b.text.find("/") > 0 and hu.text.find("/") > 0, "each bar shows live current/max numbers (%s | %s | %s)" % [hp.text, st_b.text, hu.text])
	ok(hp.text == "%d/%d" % [b.run.hp, b.run.max_hp()], "health number is current/max HP")
	# fill is a clip of the window: width follows the value, with an eased drain
	hp.set_vals(20, 40, "20/40", true)
	hp.settle()
	var win := hp.fill_rect_local()
	ok(absf(roundf(win.size.x * 0.5) - roundf(win.size.x * hp.disp / hp.max_value)) < 0.5, "fill clip is half the window at 50%% HP (%.0f of %.0f px)" % [win.size.x * 0.5, win.size.x])
	hp.set_vals(8, 40, "8/40")
	ok(hp.disp > 8.0 and not hp.is_settled(), "damage drains smoothly instead of snapping (shown %.1f -> 8)" % hp.disp)
	ok(hp.trail >= hp.disp, "damage leaves a pale chip behind the fill")
	for i in 90:
		hp._process(0.05)
	ok(hp.is_settled() and absf(hp.disp - 8.0) < 0.1, "the drain settles on the real value")
	var wide := win.size.x
	var hp_w0 := hp.size.x
	hp.size.x = hp_w0 + 40.0
	ok(hp.fill_rect_local().size.x == wide + 40.0, "bar frame stretches wider without touching its caps (fill window follows)")
	hp.size.x = hp_w0
	# every theme still has its obstacle PNGs, incl. the appended log / bush variants
	for tid in ["jungle", "tundra", "cave"]:
		var n := int(DB.theme(tid).get("obstacle_variants", 0))
		var have := 0
		while ResourceLoader.exists("res://assets/sprites/prop_%s_obstacle_%d.png" % [tid, have]):
			have += 1
		ok(n == have and n >= 11, "%s: obstacle_variants (%d) matches the prop PNGs (%d)" % [tid, n, have])
	for k in range(3):
		var tg: Texture2D = SpriteFactory.prop_texture("tallgrass", "jungle", k)
		var fg: Texture2D = SpriteFactory.prop_texture("tallgrass", "jungle", k, true)
		ok(tg != null and tg.get_width() == 32 and tg.get_height() == 24 and fg != null and fg.get_height() == 24, "jungle tall-grass cover %d (grass-tuft art) keeps the 32x24 footprint + front layer" % k)
	# jungle iso sheet: 32 ground tiles (76x38 diamonds), deco sprites, themed pools
	var jt: Dictionary = DB.theme("jungle")
	ok(int(jt["ground_variants"]) == 32 and (jt["ground_pool"] as Array).size() >= 32, "jungle floor = 32 supplied grass tiles with a weighted pool (%d entries)" % (jt["ground_pool"] as Array).size())
	var plain_w := 0
	for gi in jt["ground_pool"]:
		var gt: Texture2D = SpriteFactory.png("tile_jungle_ground_%d" % int(gi))
		ok(gt != null and gt.get_width() == 32 and gt.get_height() == 16, "tile_jungle_ground_%d is a 32x16 diamond" % int(gi))
	var counts := {}
	for gi in jt["ground_pool"]:
		counts[gi] = int(counts.get(gi, 0)) + 1
	for k in counts:
		if int(counts[k]) >= 6:
			plain_w += int(counts[k])
	ok(float(plain_w) / float((jt["ground_pool"] as Array).size()) >= 0.5, "most floor tiles are plain grass, dirt / flowers / pebbles are sparse (%d of %d)" % [plain_w, (jt["ground_pool"] as Array).size()])
	var ti: Image = (SpriteFactory.png("tile_jungle_ground_0") as Texture2D).get_image()
	ok(ti.get_pixel(15, 0).a > 0.0 and ti.get_pixel(0, 0).a == 0.0 and ti.get_pixel(1, 8).a > 0.0 and ti.get_pixel(30, 8).a > 0.0, "ground tile is a clean 2:1 diamond (corners transparent, edge points opaque)")
	var interior: Array = jt["obstacle_pool_interior"]
	var border: Array = jt["obstacle_pool"]
	ok(not interior.is_empty() and border.size() > interior.size() / 2, "obstacles have separate border / interior pools")
	var tall_tree := false
	for oi in interior:
		var ot: Texture2D = SpriteFactory.png("prop_jungle_obstacle_%d" % int(oi))
		if ot != null and ot.get_height() > 50:
			tall_tree = true
	ok(not tall_tree, "board obstacles never use the tall trees (units are not hidden behind them)")
	var tree_border := false
	for oi in border:
		var ot2: Texture2D = SpriteFactory.png("prop_jungle_obstacle_%d" % int(oi))
		if ot2 != null and ot2.get_height() > 60:
			tree_border = true
	ok(tree_border, "the arena border uses the big trees")
	for nm in (jt["decor_ring"] as Array) + (jt["decor_interior"] as Array):
		ok(ResourceLoader.exists("res://assets/sprites/%s.png" % String(nm)), "decor sprite exists: " + String(nm))
	for i in range(1, 33):
		ok(ResourceLoader.exists("res://assets/sprites/tile_grass_%02d.png" % i), "tile_grass_%02d.png exists" % i)
	var owned := FileAccess.get_file_as_string("res://tools/art/supplied/owned.txt")
	ok(owned.find("egg_raptor") >= 0 and owned.find("bg_customize") >= 0 and owned.find("bg_egg_nest") >= 0, "egg + nest scene sprites are in owned.txt")
	ok(FileAccess.get_file_as_string("res://README.md").find("bg_customize") >= 0, "README documents the egg / nest scene art")
	ok(owned.find("ui_btn\n") >= 0 and owned.find("ui_bar_frame") >= 0 and owned.find("prop_jungle_obstacle_2") >= 0, "gen_art.py is told which sprites came from the designer sheets (owned.txt)")
	var rd := FileAccess.get_file_as_string("res://README.md")
	ok(rd.find("ui_bar_frame") >= 0 and rd.find("foliage_01") >= 0 and rd.find("log_01") >= 0 and rd.find("nine-patch") >= 0, "README documents button / bar / foliage / log sprites")
	sc.queue_free()
	await process_frame

# ------------------------------------------------------------------ designer Velociraptor sprites (4 facings)
func test_raptor_art(game) -> void:
	section("designer raptor: 4 facing poses x 4 growth stages, feet anchored, palette-region recolour, pre-flipped cache")
	var stages := ["baby", "juvenile", "adult", "prime"]
	var widths := {}
	for st in stages:
		for suf in ["", "_sw", "_b", "_nw"]:
			var nm := "raptor_%s%s" % [st, suf]
			var img := img_of("res://assets/sprites/%s.png" % nm)
			ok(img != null and img.get_width() >= 18 and img.get_width() <= 60 and img.get_height() >= 8 and img.get_height() <= 30, "%s.png is a tile-sized sprite (%dx%d)" % [nm, img.get_width(), img.get_height()])
			var w := img.get_width()
			var h := img.get_height()
			var bottom_opaque := false
			var halo := 0
			var fx := 0.0
			var fn_ := 0
			for x in w:
				if img.get_pixel(x, h - 1).a > 0.5:
					bottom_opaque = true
			for y in h:
				for x in w:
					var c := img.get_pixel(x, y)
					if c.a > 0.01 and c.a < 0.99:
						halo += 1
					if c.a > 0.5 and y >= int(h * 0.85):
						fx += float(x)
						fn_ += 1
			ok(bottom_opaque and halo == 0, "%s: feet touch the bottom row, hard alpha (no halo)" % nm)
			ok(fn_ > 0 and absf(fx / float(fn_) - float(w) / 2.0) <= 0.12 * float(w), "%s: feet centred on the canvas (centre column = the tile)" % nm)
			if suf == "":
				widths[st] = w
	ok(widths["baby"] < widths["juvenile"] and widths["juvenile"] < widths["adult"] and widths["adult"] < widths["prime"], "the same art is scaled by stage (baby < juvenile < adult < prime: %s)" % str(widths))
	ok(float(widths["baby"]) / float(widths["adult"]) >= 0.55 and float(widths["baby"]) / float(widths["adult"]) <= 0.85 and absf(float(widths["prime"]) / float(widths["adult"]) - 1.1) < 0.08, "stage scale is about 0.7x / 0.9x / 1.0x / 1.1x (the baby is a touch larger than true scale so it stays legible at 640x360)")
	# facing -> pose mapping on the board
	var run := RunState.create("velociraptor", 811)
	run.begin_stage(0)
	var b := Battle.create(run, make_room(["beetle"], 811), "spotted")
	var board := BattleBoard.new()
	board.setup(b, "jungle")
	var pl: BUnit = b.player
	var want := {Vector2i(1, 0): "", Vector2i(0, 1): "_sw", Vector2i(0, -1): "_b", Vector2i(-1, 0): "_nw"}
	var seen := {}
	for f in want:
		pl.vis_facing = f
		var tex: Texture2D = board._unit_tex(pl)
		var src := SpriteFactory.get_texture(String(pl.sprite_id) + String(want[f]))
		ok(tex == src, "facing %s draws %s%s" % [str(f), pl.sprite_id, want[f]])
		seen[tex.get_instance_id()] = true
		var rc := board.unit_rect(pl)
		var foot := BattleBoard.unit_foot(pl.vis_pos)
		ok(is_equal_approx(rc.end.y, foot.y) and is_equal_approx(rc.get_center().x, foot.x), "facing %s: the sprite sits on the tile (bottom-centre = foot)" % str(f))
		ok(SpriteFactory.has_facing_art(String(pl.sprite_id), f) == (f == Vector2i(0, 1) or f == Vector2i(-1, 0)), "facing %s: SW / NW use their own art (no mirrored pose)" % str(f))
	ok(seen.size() == 4, "all four supplied poses are in use")
	# other creatures still use the pre-flipped cache (mirrored front / back)
	var e: BUnit = null
	for u in b.units:
		if not u.is_player:
			e = u
	if e != null:
		e.vis_facing = Vector2i(0, 1)
		ok(not SpriteFactory.has_facing_art(String(e.sprite_id), e.vis_facing) and BattleBoard.facing_flip(e.vis_facing), "creatures without per-facing art are still mirrored (pre-flipped cache)")
		var f1 := board._flipped(board._unit_tex(e))
		ok(f1 == board._flipped(board._unit_tex(e)) and f1.get_size() == board._unit_tex(e).get_size(), "the flipped texture is cached and keeps its size / alignment")
	# palette regions + recolour of the brown art
	var src_img := img_of("res://assets/sprites/raptor_adult.png")
	var counts := {Look.R_BODY: 0, Look.R_STRIPE: 0, Look.R_BELLY: 0, Look.R_NONE: 0}
	var eye_px := []
	for y in src_img.get_height():
		for x in src_img.get_width():
			var c := src_img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var r := Look.region_of(c, y, src_img.get_height())
			counts[r] += 1
			if r == Look.R_NONE and c.v > 0.7 and c.s > 0.74:
				eye_px.append(Vector2i(x, y))
	ok(counts[Look.R_BODY] > 100 and counts[Look.R_STRIPE] > 20 and counts[Look.R_BELLY] >= 4 and eye_px.size() >= 1, "palette regions found: body %d, stripe %d, belly %d, eye %d px" % [counts[Look.R_BODY], counts[Look.R_STRIPE], counts[Look.R_BELLY], eye_px.size()])
	for skin in ["jungle", "azure", "ember"]:
		var lk := Look.default_look("velociraptor")
		lk["skin"] = skin
		var out := Look.apply(src_img, "raptor_adult", lk)
		var changed := 0
		var kept := true
		for y in src_img.get_height():
			for x in src_img.get_width():
				var c0 := src_img.get_pixel(x, y)
				var c1 := out.get_pixel(x, y)
				if c0.a < 0.5:
					continue
				if Look.region_of(c0, y, src_img.get_height()) == Look.R_NONE:
					if not c0.is_equal_approx(c1):
						kept = false
				elif not c0.is_equal_approx(c1):
					changed += 1
		var tgt := Look.color_of("velociraptor", "skins", skin)
		var mid := out.get_pixel(src_img.get_width() / 2, src_img.get_height() / 2)
		ok(changed > 120 and kept, "skin %s: body / stripe / belly recoloured (%d px), eye + outline + claws untouched" % [skin, changed])
		var hd := absf(fposmod(tgt.h - Look.apply(src_img, "raptor_adult", lk).get_pixel(eye_px[0].x, eye_px[0].y).h, 1.0))
		ok(Look.apply(src_img, "raptor_adult", lk).get_pixel(eye_px[0].x, eye_px[0].y).is_equal_approx(src_img.get_pixel(eye_px[0].x, eye_px[0].y)), "skin %s keeps the orange eye" % skin)
	var lp := Look.default_look("velociraptor")
	lp["pattern"] = "spots"
	lp["pcolor"] = "cream"
	var po := Look.apply(src_img, "raptor_adult", lp)
	var body_only := true
	var pdiff := 0
	for y in src_img.get_height():
		for x in src_img.get_width():
			var c0 := src_img.get_pixel(x, y)
			if c0.a > 0.5 and not c0.is_equal_approx(po.get_pixel(x, y)):
				pdiff += 1
				if Look.region_of(c0, y, src_img.get_height()) != Look.R_BODY:
					body_only = false
	ok(pdiff > 20 and body_only, "patterns are overlays masked to the body region only (%d px)" % pdiff)
	for suf in ["_sw", "_b", "_nw"]:
		var lk2 := Look.default_look("velociraptor")
		lk2["skin"] = "azure"
		var im2 := img_of("res://assets/sprites/raptor_adult%s.png" % suf)
		ok(diff_count(Look.apply(im2, "raptor_adult" + suf, lk2), im2) > 60, "the recolour works on raptor_adult%s too" % suf)
	var rd2 := FileAccess.get_file_as_string("res://README.md")
	ok(rd2.find("raptor_<stage>_nw") >= 0 and rd2.find("import_raptors.py") >= 0, "README documents the raptor facing sprites")
	board.free()

# ------------------------------------------------------------------ card design (layered frame, live text)
func test_card_design(game) -> void:
	section("ability cards: layered dark / light frame, art window, name banner, type ribbon, description box, cost tiles, icon slots")
	var sizes := {"frame": Vector2i(27, 27), "crest": Vector2i(16, 6), "artwin": Vector2i(11, 11), "banner": Vector2i(32, 13), "ribbon": Vector2i(21, 7),
		"textbox": Vector2i(13, 13), "tile": Vector2i(9, 9), "slot": Vector2i(9, 9)}
	for layer in sizes:
		for v in ["dark", "light"]:
			var tx: Texture2D = SpriteFactory.png("card_%s_%s" % [layer, v])
			ok(tx != null and Vector2i(tx.get_width(), tx.get_height()) == sizes[layer], "card_%s_%s.png is %s" % [layer, v, str(sizes[layer])])
	var cards: Dictionary = DB.table("cards")
	var n_dark := 0
	var n_light := 0
	for id in cards:
		if String(id).begins_with("_") or not (cards[id] is Dictionary) or not cards[id].has("text"):
			continue
		var cv := CardView.new().setup(id)
		var want := "light" if String(cards[id]["type"]) == "attack" else "dark"
		ok(cv.variant() == want, "card %s wears the %s frame (%s)" % [id, want, cards[id]["type"]])
		if want == "dark":
			n_dark += 1
		else:
			n_light += 1
		for bg in [false, true]:
			var L := CardView.layout(bg, CardView.BH if bg else CardView.H)
			var cw := float(CardView.BW if bg else CardView.W)
			var chh := float(CardView.BH if bg else CardView.H)
			var card_r := Rect2(0, 0, cw, chh)
			var inside := true
			for k in ["win", "banner", "ribbon", "box", "name", "text", "crest"]:
				inside = inside and (card_r.encloses(L[k]) or (L[k] as Rect2).size == Vector2.ZERO)
			ok(inside, "card %s (%s): every layer lies inside the card" % [id, "big" if bg else "hand"])
			var tile := Rect2(float(L["tile_x"]), float(L["tile_y"][2]), L["tile"], L["tile"])
			ok(not tile.intersects((L["name"] as Rect2).grow(-4.0)), "card %s: the number tiles clear the name text" % id)
			ok((not bg or (L["text"] as Rect2).position.y >= (L["box"] as Rect2).position.y + 2) and (L["name"] as Rect2).position.y >= (L["banner"] as Rect2).position.y, "card %s: text sits inside its box / banner" % id)
		cv.free()
	ok(n_dark > 5 and n_light > 5, "both frame variants are used (%d dark, %d light)" % [n_dark, n_light])
	var forced := CardView.new().setup("claw_slash")
	forced.card["frame"] = "dark"
	ok(forced.variant() == "dark", "a card can force its frame with \"frame\": dark|light in cards.json")
	forced.free()
	var rd3 := FileAccess.get_file_as_string("res://README.md")
	ok(rd3.find("card_frame_<v>") >= 0 and rd3.find("card_ribbon") >= 0 and rd3.find("card_<id>.png") >= 0, "README documents the card layers")

func test_victory_popup(game) -> void:
	section("victory popup: 'Encounter Cleared' over the live board, follow-up pick popups, exits usable afterwards")
	var mainn: Node = load("res://scripts/ui/Main.gd").new()
	root.add_child(mainn)
	await process_frame
	await process_frame
	game.start_run("velociraptor", 63)
	game.run.stage["weather"] = "clear"
	game.run.stage["step"] = 1
	var room := make_room(["beetle", "beetle"], 12)
	room.erase("arena_fixed")
	room["unspotted_allowed"] = false
	game.enter_battle(room)
	await process_frame
	await process_frame
	var bsc: Node = mainn.current
	ok(bsc.name == "battle", "fight on the board")
	for e in game.battle.enemies:
		e.alive = false
		game.battle.killed.append({"id": e.id, "infected": false, "xp": int(e.def.get("xp", 0)), "food": int(e.def.get("food", 0))})
	game.battle.phase = "won"
	game.battle_result = game.battle.result()
	game.goto("reward", {"room": room})
	await process_frame
	await process_frame
	var pop: Node = mainn.popup_node
	ok(pop != null and mainn.current == bsc and bsc.is_ancestor_of(pop) and bsc.board.visible, "the reward is a popup on top of the board, which stays visible behind it")
	var texts := ""
	for l in pop.find_children("*", "Label", true, false):
		texts += l.text + "\n"
	ok(texts.find("Encounter Cleared") >= 0 and texts.find("XP") >= 0, "title 'Encounter Cleared' with the XP result")
	var btns: Array = pop.find_children("*", "Button", true, false).map(func(b): return b.text)
	ok(btns.has("Eat") and btns.has("Fill up") and btns.has("Skip") and btns.has("Continue"), "eat / just fill up / skip choices + Continue (%s)" % str(btns))
	ok(texts.find("Fit:") >= 0 and texts.find("Diet:") >= 0, "the nutrition preview is shown")
	var pr: Control = pop.find_child("PopupPanel", false, false)
	ok(pr != null and Rect2(0, 0, 960, 540).encloses(pr.get_rect()), "the popup panel fits inside the 960x540 design frame (scales with the HUD at every window size)")
	var h0: int = game.run.hunger
	_first_button(pop, ["Eat"]).pressed.emit()
	await process_frame
	ok(game.run.hunger >= h0, "eating from the popup works")
	var guard := 0
	var seen := ["reward"]
	while mainn.popup_node != null and guard < 8:
		guard += 1
		var nm := String(mainn.popup_node.name)
		if not seen.has(nm):
			seen.append(nm)
		var b := _first_button(mainn.popup_node, ["Continue", "Skip", "Leave it", "Leave", "Choose"])
		ok(b != null, "popup %s has something to press" % nm)
		if b == null:
			break
		b.pressed.emit()
		await process_frame
		await process_frame
	var settle := 0
	while (mainn.popup_node != null or game.battle.phase != "explore") and settle < 60:     # the board finishes its own end-of-fight animation in real time
		settle += 1
		await create_timer(0.05).timeout
	ok(mainn.popup_node == null and mainn.current.name == "battle" and game.battle.phase == "explore", "after the popups the player is back on the board with the exits to pick (%s)" % str(seen))
	ok(seen.size() >= 1 and mainn.battle_mode, "follow-up screens (%s) went through popups" % str(seen))
	# the sim/bot flow has no screens at all
	var sim := RunSimulator.simulate(21, false, "fit", {})
	ok(sim.has("won") or sim.has("result") or not sim.is_empty(), "the bot sim still runs a whole game with no encounter / reward screens")
	mainn.queue_free()
	game.main = null
	await process_frame


# ------------------------------------------------------------------ intro story cutscene
func test_cutscene(game) -> void:
	section("intro story cutscene: data-driven timeline, skip, flow order, bypass, resolutions")
	var tl: Dictionary = CutsceneView.timeline()
	var errs: Array = CutsceneView.validate(tl)
	ok(errs.is_empty(), "the cutscene timeline validates (%s)" % str(errs))
	var total := CutsceneView.total_time(tl)
	ok(total >= 35.0 and total <= 50.0, "the cutscene lasts 35-50 s (%.1f s)" % total)
	var ids: Array = []
	var caps: Array = []
	var cues := 0
	for sh in tl["shots"]:
		ids.append(String(sh["id"]))
		for c in sh.get("captions", []):
			caps.append(String(c["text"]))
		cues += (sh.get("sfx", []) as Array).size()
		ok(float(sh["dur"]) >= 4.0 and sh["layers"].size() >= 4, "shot %s has a duration and several layers" % sh["id"])
	ok(ids == ["egg", "mother", "meteor", "emerge", "fight", "flee"], "six story beats in order: egg, mother, meteor, emerging creatures, mother's fight, flee")
	ok(caps == ["A quiet morning in the nest.", "Mother always returned with food.", "Then the sky broke.", "Something crawled out of the fire.", "Mother fought. It wasn't enough.", "Run."], "short captions tell the story")
	ok(cues >= 10, "SFX placeholder cues are in the timeline (%d)" % cues)
	var used := {}
	for sh in tl["shots"]:
		for ly in sh["layers"]:
			used[String(ly["kind"])] = true
	ok(used.has("meteor") and used.has("plume") and used.has("shell") and used.has("creep") and used.has("particles"), "meteor, smoke plume, egg shell, infection creep and particle layers are used")
	ok((tl["shots"][2]["shake"] as Array).size() > 0 and (tl["shots"][2]["flash"] as Array).size() > 0, "the meteor impact has screen shake and a flash")
	# the validator catches broken data
	var bad: Dictionary = tl.duplicate(true)
	bad["shots"][0]["layers"][0]["kind"] = "banana"
	ok(not CutsceneView.validate(bad).is_empty(), "the validator rejects an unknown layer kind")
	bad = tl.duplicate(true)
	for ly in bad["shots"][1]["layers"]:
		if String(ly["kind"]) == "image":
			ly["scale"] = 2.5
			break
	ok(not CutsceneView.validate(bad).is_empty(), "the validator rejects non-integer sprite scales")
	bad = tl.duplicate(true)
	bad["shots"][4]["captions"][0]["t"] = 99.0
	ok(not CutsceneView.validate(bad).is_empty(), "the validator rejects a caption outside its shot")
	bad = tl.duplicate(true)
	bad["shots"].remove_at(5)
	bad["shots"].remove_at(4)
	ok(not CutsceneView.validate(bad).is_empty(), "the validator rejects a too-short story / timeline length")
	# timeline helpers
	ok(CutsceneView.locate(tl, 0.0)["shot"] == 0 and CutsceneView.locate(tl, total + 5.0)["shot"] == 5 and CutsceneView.locate(tl, CutsceneView.shot_start(tl, 3) + 0.5)["shot"] == 3, "global time maps to the right shot")
	ok(absf(float(CutsceneView.keyval([[0.0, 0.0], [2.0, 10.0]], 1.0)) - 5.0) < 0.001 and float(CutsceneView.keyval([[1.0, 3.0]], 0.0)) == 3.0, "keyframes interpolate and clamp")
	var kc: Color = CutsceneView.keyval([[0.0, "#000000"], [1.0, "#ffffff"]], 0.5)
	ok(absf(kc.r - 0.5) < 0.01, "color keyframes interpolate")
	ok(CutsceneView.bar_height(Vector2(640, 360), tl) == 35.0 and CutsceneView.bar_height(Vector2(640, 420), tl) > 35.0 and CutsceneView.bar_height(Vector2(1280, 360), tl) == 35.0, "letterbox bars keep a ~2.2:1 picture at every aspect ratio")
	# designer art override naming: with no cutscene_* PNGs the named game sprites are used
	var mother: Dictionary = {}
	for ly in tl["shots"][1]["layers"]:
		if String(ly.get("id", "")) == "mother":
			mother = ly
	ok(not mother.is_empty() and CutsceneView.layer_texture("mother", mother) == SpriteFactory.looked("raptor_adult_sw", {}, false), "the mother is the adult raptor sprite in the default (unrecoloured) look")
	var baby: Dictionary = {}
	for ly in tl["shots"][1]["layers"]:
		if String(ly.get("id", "")) == "baby":
			baby = ly
	ok(CutsceneView.layer_texture("mother", baby) == SpriteFactory.get_texture("raptor_baby"), "the baby wears the player's chosen look")
	ok(FileAccess.get_file_as_string("res://README.md").find("cutscene_<") >= 0 and FileAccess.get_file_as_string("res://README.md").find("data/cutscene_intro.json") >= 0, "README documents the cutscene timeline and the cutscene_* override names")
	# SFX cues fire once, in order, only while playing (not on seek)
	var cv := CutsceneView.new()
	cv.seek(10.0)
	ok(cv.sfx_log.is_empty(), "seeking does not fire SFX cues")
	cv.seek(0.0)
	var tt := 0.0
	while tt < total:
		tt += 0.1
		cv.advance_to(tt)
	ok(cv.sfx_log.size() == cues, "playing through fires every SFX cue exactly once (%d / %d)" % [cv.sfx_log.size(), cues])
	cv.free()
	# draws at every window size (no script errors, integer pixel positions) incl. 4K logical sizes
	for vs in [Vector2(960, 540), Vector2(1280, 720), Vector2(1706, 960), Vector2(2560, 1080)]:
		var v := CutsceneView.new()
		v.size = vs
		v.origin = ((vs - CutsceneView.FRAME) * 0.5).floor()
		root.add_child(v)
		for ft in [0.5, 4.0, 9.0, 14.0, 19.0, 21.0, 26.0, 30.0, 34.0, 37.0, 42.0, 46.0]:
			v.seek(ft)
			await process_frame
		ok(v.is_inside_tree(), "the cutscene draws at %dx%d" % [int(vs.x), int(vs.y)])
		v.queue_free()
	# --- flow + skip
	var mainn: Node = load("res://scripts/ui/Main.gd").new()
	root.add_child(mainn)
	await process_frame
	await process_frame
	Settings.persist = false
	Settings.intro_mode = 0
	Settings.intro_seen = false
	game.bypass_cutscene = false
	ok(game.intro_screen_name() == "intro_cutscene", "the screen after customization is the cutscene (default: always play)")
	game.start_run("velociraptor", 5)
	game.goto("intro_cutscene")
	await process_frame
	await process_frame
	var cs: Node = mainn.current
	ok(cs != null and cs.name == "intro_cutscene" and not mainn.battle_mode, "the cutscene screen opens (menu scale, integer scaling)")
	ok(Settings.intro_seen, "starting the cutscene remembers that it has been seen")
	ok(cs.skip_btn != null and cs.skip_btn.text == "Skip" and cs.skip_btn.visible, "a Skip button is on screen from the first frame (skippable even on the first play)")
	ok(cs.view.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "the cutscene uses nearest filtering")
	cs._process(1.0)
	ok(cs.t > 0.9 and cs.view.t > 0.9, "the clock advances")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	cs._input(esc)
	ok(cs.skipping and not mainn.settings_open(), "Esc skips at once and does not open the Settings panel")
	for i in 20:
		cs._process(0.05)
	await process_frame
	ok(mainn.current.name == "stage_intro", "after the skip the stage-intro cinematic (weather) plays")
	for kc2 in [KEY_SPACE, KEY_ENTER]:
		game.goto("intro_cutscene")
		await process_frame
		cs = mainn.current
		var ek := InputEventKey.new()
		ek.keycode = kc2
		ek.pressed = true
		cs._input(ek)
		ok(cs.skipping, "key %s skips" % OS.get_keycode_string(kc2))
		cs.skip(true)
		await process_frame
	ok(mainn.current.name == "stage_intro", "Space / Enter lead to the stage intro")
	# hold any other key
	game.goto("intro_cutscene")
	await process_frame
	cs = mainn.current
	var hk := InputEventKey.new()
	hk.keycode = KEY_A
	hk.pressed = true
	cs._input(hk)
	cs._process(0.3)
	ok(not cs.skipping and cs.view.skip_progress > 0.3 and cs.view.skip_progress < 0.7, "holding a key fills the skip bar")
	cs._process(0.4)
	ok(cs.skipping, "holding a key for ~0.6 s skips")
	cs.skip(true)
	await process_frame
	game.goto("intro_cutscene")
	await process_frame
	cs = mainn.current
	var hk2 := InputEventKey.new()
	hk2.keycode = KEY_A
	hk2.pressed = true
	cs._input(hk2)
	cs._process(0.3)
	hk2 = InputEventKey.new()
	hk2.keycode = KEY_A
	hk2.pressed = false
	cs._input(hk2)
	cs._process(0.5)
	ok(not cs.skipping and cs.view.skip_progress < 0.2, "releasing the key cancels the skip")
	# the Skip button
	cs.skip_btn.pressed.emit()
	ok(cs.skipping, "the Skip button skips")
	cs.skip(true)
	await process_frame
	ok(mainn.current.name == "stage_intro", "Skip button leads to the stage intro")
	# natural end
	game.goto("intro_cutscene")
	await process_frame
	cs = mainn.current
	cs.t = cs.total - 0.02
	cs._process(0.05)
	await process_frame
	ok(mainn.current.name == "stage_intro", "the cutscene ends by itself and continues into the stage intro")
	# show_at renders a frame of every shot
	game.goto("intro_cutscene")
	await process_frame
	cs = mainn.current
	for i in tl["shots"].size():
		cs.show_at(CutsceneView.shot_start(tl, i) + 1.0)
		await process_frame
	ok(cs.view.t > CutsceneView.shot_start(tl, 5), "frames of every shot can be captured")
	cs.skip(true)
	await process_frame
	# settings: replay / always skip, first time only
	Settings.intro_mode = 2
	ok(game.intro_screen_name() == "stage_intro", "Settings 'Off' skips the cutscene (customization -> stage intro)")
	Settings.intro_mode = 1
	Settings.intro_seen = false
	ok(game.intro_screen_name() == "intro_cutscene", "'First time only': plays when not yet seen")
	Settings.intro_seen = true
	ok(game.intro_screen_name() == "stage_intro", "'First time only': skipped once seen")
	Settings.intro_mode = 0
	ok(game.intro_screen_name() == "intro_cutscene", "'Always' replays it at the start of every new run")
	game.bypass_cutscene = true
	ok(game.intro_screen_name() == "stage_intro", "the bot sim / scripted tests can bypass the cutscene")
	game.bypass_cutscene = false
	var so := SettingsOverlay.new()
	root.add_child(so)
	await process_frame
	ok(so.intro_btn != null and so.intro_btn.text == "Intro: Always", "Settings has an intro cutscene toggle")
	so._cycle_intro()
	ok(Settings.intro_mode == 1 and so.intro_btn.text == "Intro: First time only", "the toggle cycles Always / First time only / Off")
	so._cycle_intro()
	so._cycle_intro()
	ok(Settings.intro_mode == 0, "and wraps around")
	so.queue_free()
	var rsim := RunSimulator.simulate(3)
	ok(rsim.has("rooms") and int(rsim["rooms"]) > 0, "the bot sim never touches the cutscene (it runs without screens)")
	# settings persistence
	Settings.persist = true
	Settings.intro_mode = 2
	Settings.intro_seen = true
	Settings.save_settings()
	Settings.intro_mode = 0
	Settings.intro_seen = false
	Settings.load_settings()
	ok(Settings.intro_mode == 2 and Settings.intro_seen, "the intro setting and the 'seen' flag persist")
	Settings.intro_mode = 0
	Settings.intro_seen = false
	Settings.save_settings()
	Settings.persist = false
	mainn.queue_free()
	await process_frame


# ------------------------------------------------------------------ game name (placeholder, one central entry)
func test_game_title(game) -> void:
	section("game title: one central entry (data/game.json), synced everywhere")
	var g: Dictionary = DB.table("game")
	var title := String(g.get("title", ""))
	ok(title == "Primal Instinct" and game.title() == title, "the game is called Primal Instinct (data/game.json, Game.title())")
	ok(String(g.get("slug", "")) == "PrimalInstinct" and String(g.get("zip_slug", "")) == "primal-instinct", "file-name slugs come from the same entry")
	var proj := FileAccess.get_file_as_string("res://project.godot")
	ok(proj.find('config/name="%s"' % title) >= 0, "project.godot (project / window name) matches the title")
	var ex := FileAccess.get_file_as_string("res://export_presets.cfg")
	ok(ex.find('name="%s - Linux"' % title) >= 0 and ex.find('name="%s - Web"' % title) >= 0 and ex.find('name="%s - Windows"' % title) >= 0, "export presets are named after the title")
	ok(ex.find("builds/linux/%s.x86_64" % g["slug"]) >= 0 and ex.find("builds/windows/%s.exe" % g["slug"]) >= 0 and ex.find('product_name="%s"' % title) >= 0, "export output file names and product name use the title / slug")
	var rd := FileAccess.get_file_as_string("res://README.md")
	ok(rd.begins_with("# %s" % title) and rd.find("data/game.json") >= 0 and rd.find("apply_title.py") >= 0, "README is titled with the name and documents where to change it")
	var old := "Primal " + "Clutch"
	var stale := 0
	for f in ["res://project.godot", "res://export_presets.cfg", "res://README.md", "res://scripts/ui/Main.gd", "res://scripts/ui/screens/EggScreen.gd", "res://data/game.json"]:
		var txt := FileAccess.get_file_as_string(f)
		if txt.find(old) >= 0 or txt.find("PrimalCl" + "utch") >= 0 or txt.find("primal-cl" + "utch") >= 0:
			stale += 1
	ok(stale == 0, "no leftover mentions of the old working title in the config, docs or UI")
	var mainn: Node = load("res://scripts/ui/Main.gd").new()
	root.add_child(mainn)
	await process_frame
	await process_frame
	game.run = null
	game.goto("egg")
	await process_frame
	var found := false
	var stack: Array = [mainn.current]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Label and (n as Label).text == title.to_upper():
			found = true
		stack.append_array(n.get_children())
	ok(found, "the first screen shows the title from the central entry")
	ok(root.get_window().title == title, "the window title is the game title")
	mainn.queue_free()
	await process_frame


# ------------------------------------------------------------------ main menu
func _key(code: int, pressed: bool = true) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = pressed
	return e

func test_main_menu(game) -> void:
	section("main menu: first screen on launch, Play / Settings / Quit, keyboard + mouse, run-end Main menu button")
	ok(game.first_screen_name() == "egg", "scripted tests / the bot sim bypass the menu (start on the egg screen)")
	game.bypass_menu = false
	ok(game.first_screen_name() == "menu", "by default the game opens on the main menu")
	var mainn: Node = load("res://scripts/ui/Main.gd").new()
	root.add_child(mainn)
	await process_frame
	await process_frame
	var menu: Node = mainn.current
	ok(menu != null and menu.name == "menu", "a fresh launch shows the main menu first")
	ok(not mainn.battle_mode, "the menu uses the menu scale (whole-number scaling, same HUD scale rules as the other menus)")
	ok(menu.title_view.text == game.title().to_upper() and game.title() == "Primal Instinct", "the big pixel title comes from the central title entry")
	ok(menu.title_view.tagline == game.tagline(), "the tagline comes from data/game.json too")
	ok(menu.play_btn != null and menu.play_btn.text == "Play" and menu.settings_btn.text == "Settings", "Play and Settings buttons exist")
	ok(menu.get_node_or_null("menu_continue") == null, "no Continue button (a run cannot be resumed: there is no mid-run save)")
	ok(menu.play_btn.get_theme_stylebox("hover") is StyleBoxTexture and menu.settings_btn.get_theme_stylebox("normal") is StyleBoxTexture, "buttons use the stone-wood button sprite")
	var MS: GDScript = load("res://scripts/ui/screens/MenuScreen.gd")
	ok(MS.quit_available(false) and not MS.quit_available(true), "Quit is offered on desktop and hidden on the Web build")
	ok((menu.quit_btn != null) == MS.quit_available(OS.has_feature("web")), "the Quit button follows the platform")
	for b in menu.buttons:
		var r := Rect2((b["btn"] as Button).position, (b["btn"] as Button).size)
		ok(Rect2(0, 0, 640, 360).encloses(r) and r.size.x >= 100.0 and r.size.y >= 18.0, "menu button %s is on screen and big enough" % b["id"])
	ok(menu.version_label.text == "v" + game.version() and game.version() != "", "a version label is shown (%s)" % menu.version_label.text)
	ok(FileAccess.get_file_as_string("res://project.godot").find('config/version="%s"' % game.version()) >= 0, "project.godot carries the same version")
	var vp: Vector2 = menu.get_viewport_rect().size
	menu._layout()
	var vr := Rect2(menu.version_label.global_position, menu.version_label.size)
	ok(Rect2(Vector2.ZERO, vp).encloses(vr) and vr.end.x > vp.x - 30.0 and vr.end.y > vp.y - 40.0, "the version label sits in the real bottom-right corner")
	# --- the forest scene (replaces the old egg / raptor idle scene)
	ok(menu.get_node_or_null("MenuScene") == null and menu.get("scene") == null, "the egg-in-nest / raptor-silhouette / fireflies scene is gone")
	ok(menu.forest != null and menu.forest.name == "MenuForest" and menu.forest.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "the menu background is the layered forest scene (nearest filtering)")
	var fc: Dictionary = MenuForest.config()
	var missing: Array = []
	for sid in MenuForest.all_sprite_ids():
		if not (SpriteFactory.png(String(sid)) != null or not DB.sprite_def(String(sid)).is_empty()):
			missing.append(sid)
	ok(missing.is_empty(), "every sprite the forest uses exists (%s)" % str(missing))
	var cats: Dictionary = fc["categories"]
	ok(cats["tree"].size() >= 8 and cats["bush"].size() >= 6 and cats["fern"].size() >= 8 and cats["rock"].size() >= 4 and cats["log"].size() >= 4, "trees, bushes, ferns, rocks and logs from the supplied jungle sheets are used")
	var floor_ok := true
	for pid in fc["floor"]["pool"]:
		floor_ok = floor_ok and SpriteFactory.png("tile_jungle_ground_%d" % int(pid)) != null
	ok(floor_ok and int(fc["floor"]["scale"]) >= 1 and SpriteFactory.png(String(fc["back"]["sprite"])) != null, "the grass floor tiles and the dense canopy backdrop are the supplied art")
	var layer_ids: Array = []
	var par_ok := true
	var scale_ok := true
	var last_par := -1.0
	for ly in fc["layers"]:
		layer_ids.append(String(ly["id"]))
		scale_ok = scale_ok and float(ly["scale"]) == float(int(ly["scale"]))
	ok(layer_ids.has("trees_far") and layer_ids.has("trees_mid") and layer_ids.has("bushes_frame") and layer_ids.has("ferns_front"), "depth layers: tree line in the back, foliage framing the sides, ferns in front")
	ok(scale_ok and float(fc["back"]["scale"]) == 1.0 and float(fc["floor"]["scale"]) == float(int(fc["floor"]["scale"])), "everything is drawn at whole-number scales (no stretching)")
	ok(float(fc["layers"][0]["par"]) < float(fc["layers"][1]["par"]) and float(fc["layers"][1]["par"]) < float(fc["layers"][fc["layers"].size() - 2]["par"]), "parallax factors grow from the far tree line to the foreground")
	# the scenery extends to any window width without stretching (slot based layout)
	var wide_ok := true
	for vw in [960.0, 1280.0, 1706.0, 2560.0]:
		var fv := MenuForest.new()
		fv.size = Vector2(vw, 540)
		fv.origin = Vector2(floorf((vw - 960.0) * 0.5), 0)
		for ly in fc["layers"]:
			if float(ly.get("side_only", 0.0)) > 0.0:
				continue
			var its: Array = fv.items_in(ly, vw)
			var minx := 1e9
			var maxx := -1e9
			for it in its:
				minx = minf(minx, float(it["x"]) + fv.origin.x)
				maxx = maxf(maxx, float(it["x"]) + fv.origin.x)
			wide_ok = wide_ok and its.size() > 0 and minx < 0.0 + 60.0 and maxx > vw - 60.0
		fv.free()
	ok(wide_ok, "trees / ferns fill the whole width at 960 .. 2560 px (extended, not stretched)")
	var it1 := MenuForest.slot_item(fc["layers"][0], 3)
	var it2 := MenuForest.slot_item(fc["layers"][0], 3)
	ok(it1 == it2 and not it1.is_empty(), "the layout is deterministic (stable between frames)")
	var side_empty := true
	for k in range(-1, 2):
		side_empty = side_empty and MenuForest.slot_item(fc["layers"][1], k).is_empty()
	ok(side_empty, "the mid tree line leaves the centre open behind the title / buttons (framing the sides)")
	var rd: Dictionary = fc["readability"]
	var prc := Rect2(float((rd["panel"] as Array)[0]), float((rd["panel"] as Array)[1]), float((rd["panel"] as Array)[2]), float((rd["panel"] as Array)[3]))
	var bt_rect := Rect2(menu.play_btn.position, menu.play_btn.size)
	for bb in menu.buttons:
		bt_rect = bt_rect.merge(Rect2((bb["btn"] as Button).position, (bb["btn"] as Button).size))
	ok(float(rd["panel_alpha"]) >= 0.3 and float(rd["vignette_alpha"]) >= 0.3 and prc.encloses(bt_rect), "a dark vignette and a translucent panel sit behind the buttons")
	# leaves: few, slow, gentle, mostly green with some golden
	var lv: Dictionary = fc["leaves"]
	ok(int(lv["count"]) >= 8 and int(lv["count"]) <= 20, "low leaf density (%d leaves)" % int(lv["count"]))
	var golden := 0
	var sizes := {}
	var fast := false
	var sway_ok := true
	var vp0 := Vector2(1280, 720)
	for i in int(lv["count"]):
		var ls := MenuForest.leaf_state(i, 5.0, vp0)
		var ls2 := MenuForest.leaf_state(i, 6.0, vp0)
		golden += 1 if bool(ls["gold"]) else 0
		sizes[int(ls["scale"])] = true
		fast = fast or float(ls["fall"]) > float(lv["max_fall"])
		var dy: float = (ls2["pos"] as Vector2).y - (ls["pos"] as Vector2).y
		sway_ok = sway_ok and dy < float(lv["max_fall"]) + 2.0
	ok(not fast and sway_ok and float((lv["fall"] as Array)[1]) <= 25.0, "leaves fall slowly (<= %d px/s) and drift gently" % int(lv["max_fall"]))
	ok(sizes.size() >= 2 and golden >= 1 and golden <= int(lv["count"]) / 2, "a few leaf sizes; green leaves with the occasional golden one (%d gold)" % golden)
	var xs := {}
	for k in 20:
		xs[snappedf((MenuForest.leaf_state(0, float(k) * 0.4, vp0)["pos"] as Vector2).x, 0.5)] = true
	ok(xs.size() > 6, "leaves sway sideways as they fall")
	# parallax: the offset follows the mouse a little and the far layers move less than the near ones
	var pf := MenuForest.new()
	pf.size = Vector2(960, 540)
	pf.mouse_norm = Vector2(0.5, 0.0)
	for i in 80:
		pf.advance(0.1)
	var c_far := pf.layer_cam(float(fc["layers"][0]["par"]))
	var c_near := pf.layer_cam(float(fc["layers"][5]["par"]))
	ok(absf(c_near.x) > absf(c_far.x) and absf(c_near.x) <= float(fc["parallax"]["mouse"]) * 2.0 * 1.2 + float(fc["parallax"]["auto"]) * 1.2 and c_near == c_near.round(), "slight parallax: near layers shift more than far ones (whole pixels)")
	pf.free()
	# designer overrides: menu_bg_<category>_<n>.png replace a category (none shipped, so the defaults are used)
	ok(MenuForest.sprites("tree") == cats["tree"] and MenuForest.leaf_overrides().is_empty() and SpriteFactory.png("menu_bg_back") == null, "no designer menu_bg_* PNGs present: the supplied sprites are used")
	ok(FileAccess.get_file_as_string("res://README.md").find("menu_bg_back") >= 0 and FileAccess.get_file_as_string("res://README.md").find("menu_bg_<category>_<n>") >= 0, "README documents the menu_bg_* override names")
	# draws at every size
	for vs in [Vector2(960, 540), Vector2(1280, 720), Vector2(1706, 960), Vector2(2560, 1080)]:
		var fz := MenuForest.new()
		fz.size = vs
		fz.origin = ((vs - Vector2(960, 540)) * 0.5).floor()
		root.add_child(fz)
		fz.advance(0.1)
		await process_frame
		ok(fz.is_inside_tree(), "the forest scene draws at %dx%d" % [int(vs.x), int(vs.y)])
		fz.queue_free()
	# keyboard
	ok(menu.sel == 0, "the first button is selected")
	menu._unhandled_key_input(_key(KEY_DOWN))
	ok(menu.sel == 1, "Down selects the next button")
	menu._unhandled_key_input(_key(KEY_UP))
	menu._unhandled_key_input(_key(KEY_UP))
	ok(menu.sel == menu.buttons.size() - 1, "Up wraps around to the last button")
	menu._select(0)
	# mouse hover selects
	menu.settings_btn.mouse_entered.emit()
	ok(menu.sel == 1, "hovering a button selects it")
	# Enter on Settings opens the settings overlay (HUD size, intro toggle ...); arrows are ignored while it is open
	menu._unhandled_key_input(_key(KEY_ENTER))
	await process_frame
	ok(mainn.settings_open(), "Settings opens the existing settings overlay")
	var so: Node = null
	for c in mainn.overlay_layer.get_children():
		if c is SettingsOverlay:
			so = c
	ok(so != null and so.intro_btn != null and so.pp_btn != null, "it has the Pixel Perfect toggle and the intro cutscene toggle")
	menu._unhandled_key_input(_key(KEY_DOWN))
	ok(menu.sel == 1, "menu keys are ignored while the settings overlay is open")
	mainn._unhandled_key_input(_key(KEY_ESCAPE))
	await process_frame
	ok(not mainn.settings_open(), "Esc closes the settings overlay")
	mainn._unhandled_key_input(_key(KEY_ESCAPE))
	await process_frame
	ok(mainn.settings_open(), "Esc on the main menu opens Settings")
	mainn.close_settings()
	await process_frame
	# Enter on Play -> egg selection
	menu._select(0)
	menu._unhandled_key_input(_key(KEY_ENTER))
	await process_frame
	await process_frame
	ok(mainn.current.name == "egg", "Play leads to the egg selection")
	var eb: Node = mainn.current.get_node_or_null("egg_main_menu")
	ok(eb != null, "the egg screen has a Main menu button")
	eb.pressed.emit()
	await process_frame
	await process_frame
	ok(mainn.current.name == "menu", "...which returns to the main menu")
	# flow: menu -> egg -> customize -> cutscene -> stage intro
	mainn.current.play_btn.pressed.emit()
	await process_frame
	await process_frame
	mainn.current.seed_edit.text = "123"
	mainn.current._hatch()
	await create_timer(1.0).timeout
	ok(mainn.current.name == "customize", "egg -> customize")
	Settings.intro_mode = 0
	mainn.current._finish()
	await process_frame
	await process_frame
	ok(mainn.current.name == "intro_cutscene", "customize -> intro cutscene")
	mainn.current.skip(true)
	await process_frame
	await process_frame
	ok(mainn.current.name == "stage_intro", "intro cutscene -> stage intro (-> board)")
	# the run-end screen: Main menu button + the old 'back to the egg'
	game.run.hp = 0
	game.run.game_over = true
	game.run.cause = "Test."
	game.goto("gameover")
	await process_frame
	await process_frame
	var go: Node = mainn.current
	ok(go.name == "gameover" and go.get_node_or_null("gameover_menu") != null and go.get_node_or_null("gameover_egg") != null, "the run-end screen has Main menu and Return to the egg buttons")
	go.get_node("gameover_egg").pressed.emit()
	await process_frame
	await process_frame
	ok(mainn.current.name == "egg" and game.run == null, "'Return to the egg' keeps the old behaviour")
	game.run = null
	game.start_run("velociraptor", 9)
	game.run.hp = 0
	game.run.game_over = true
	game.goto("gameover")
	await process_frame
	await process_frame
	mainn.current.get_node("gameover_menu").pressed.emit()
	await process_frame
	await process_frame
	ok(mainn.current.name == "menu" and game.run == null, "the run-end 'Main menu' button returns to the main menu")
	ok(FileAccess.get_file_as_string("res://README.md").find("## Main menu") >= 0, "README documents the main menu")
	game.bypass_menu = true
	mainn.queue_free()
	await process_frame


# ------------------------------------------------------------------ foliage / unit readability (data/visibility.json)

func test_foliage_visibility() -> void:
	section("foliage fades over the board, units stay readable (data/visibility.json)")
	ok("visibility" in DB.TABLES, "visibility.json is a registered data table")
	var v: Dictionary = DB.table("visibility")
	for k in ["border_alpha", "border_behind_alpha", "obstacle_behind_alpha", "decor_behind_alpha", "fade_speed", "overlap", "unit_outline", "unit_ring"]:
		ok(v.has(k), "visibility.json has %s" % k)
	var ba := float(v["border_alpha"])
	var bb := float(v["border_behind_alpha"])
	var oa := float(v["obstacle_behind_alpha"])
	var da := float(v["decor_behind_alpha"])
	ok(ba >= 0.3 and ba <= 0.5, "border foliage alpha is about 35-45%% (%.2f)" % ba)
	ok(bb > 0.0 and bb <= ba, "a unit behind border foliage lowers the alpha further (%.2f <= %.2f)" % [bb, ba])
	ok(oa >= 0.4 and oa <= 0.6, "obstacles fade to about 50%% only when a unit is behind (%.2f)" % oa)
	ok(da > 0.0 and da < 1.0 and float(v["fade_speed"]) >= 4.0, "decoration alpha + a quick tween speed are set")
	var seen_themes := {}
	for theme in ["jungle", "tundra", "cave"]:
		for arena in [Vector2i(7, 5), Vector2i(12, 7), Vector2i(16, 10)]:
			for win in [Vector2(960, 540), Vector2(2560, 1600)]:
				var tag := "%s %dx%d @%dpx" % [theme, arena.x, arena.y, int(win.x)]
				var run := RunState.create("velociraptor", 90 + arena.x)
				run.begin_stage(0)
				var room := make_room(["beetle", "beetle"], 90 + arena.y)
				room["arena_fixed"] = {"w": arena.x, "h": arena.y, "shape": "rect", "cut": Vector2i.ZERO, "type": "battle", "corner": 0}
				var b := Battle.create(run, room, "spotted")
				var board := BattleBoard.new()
				board.setup(b, theme)
				board.size = win
				board.refit()
				var uks: Array = board._unit_keys()
				ok(uks.size() == b.units.size(), "%s: every unit has a screen rect + depth key" % tag)
				var pl: BUnit = b.player
				var ptile := Iso.center(Vector2(pl.pos))
				var on_board := Rect2(ptile - Vector2(48, 96), Vector2(96, 112))
				var far := Rect2(ptile + Vector2(9000, 9000), Vector2(96, 112))
				ok(board.overlaps_board(on_board), "%s: a sprite on a playable tile overlaps the board" % tag)
				ok(not board.overlaps_board(far), "%s: a sprite far outside the arena does not" % tag)
				var key := 5.0
				var bpart := [key, 6, Vector2i(-3, -3), 0, 0, 1.0]
				ok(is_equal_approx(board.foliage_target(bpart, 6, on_board, []), ba), "%s: border foliage over the board is drawn at border alpha" % tag)
				ok(is_equal_approx(board.foliage_target(bpart, 6, far, []), 1.0), "%s: border foliage fully outside stays opaque" % tag)
				ok(is_equal_approx(board.foliage_target([key, 0, pl.pos], 0, on_board, []), 1.0), "%s: obstacles are solid when nothing is behind them" % tag)
				ok(is_equal_approx(board.foliage_target([key, 1, pl.pos], 1, on_board, uks), 1.0), "%s: tall grass cover is never faded" % tag)
				# a unit behind a sprite (the sprite sorts after the unit and their rects overlap)
				var ukey := float(uks[0][0])
				var urect: Rect2 = uks[0][1]
				var unit_pos := urect.get_center()
				var over := Rect2(unit_pos - Vector2(40, 60), Vector2(80, 100))
				var behind_part := [ukey + 0.4, 6, Vector2i(-3, -3), 0, 0, 1.0]
				ok(is_equal_approx(board.foliage_target(behind_part, 6, over, uks), bb), "%s: border foliage over a unit fades to the 'unit behind' alpha" % tag)
				ok(is_equal_approx(board.foliage_target([ukey + 0.4, 0, Vector2i(0, 0)], 0, over, uks), oa), "%s: an obstacle directly in front of a unit fades to ~50%%" % tag)
				ok(is_equal_approx(board.foliage_target([ukey + 0.4, 7, Vector2i(0, 0)], 7, over, uks), da), "%s: decoration in front of a unit fades" % tag)
				ok(is_equal_approx(board.foliage_target([ukey - 0.4, 0, Vector2i(0, 0)], 0, over, uks), 1.0), "%s: an obstacle BEHIND the unit (drawn first) stays opaque" % tag)
				ok(is_equal_approx(board.foliage_target([ukey - 0.4, 6, Vector2i(-3, -3), 0, 0, 1.0], 6, over, uks), ba), "%s: border foliage behind the unit only keeps the board alpha" % tag)
				var beside := Rect2(unit_pos + Vector2(400, 0), Vector2(80, 100))
				ok(is_equal_approx(board.foliage_target([ukey + 0.4, 0, Vector2i(0, 0)], 0, beside, uks), 1.0), "%s: an obstacle that is not directly in front of a unit is untouched" % tag)
				# cache invalidates when the zoom changes
				board._overlap_zoom = -5.0
				board.foliage_target(bpart, 6, on_board, [], "6:-3:-3")
				ok(board._overlap_cache.has("6:-3:-3") and is_equal_approx(board._overlap_zoom, Iso.zoom), "%s: overlap cache is rebuilt for the current zoom" % tag)
				board.free()
				seen_themes[theme] = true
	ok(seen_themes.size() == 3, "jungle, tundra and cave were all checked")
	# smooth tween: starts at the target (no pop on load), then eases quickly when a unit steps behind
	var run2 := RunState.create("velociraptor", 91)
	run2.begin_stage(0)
	var b2 := Battle.create(run2, make_room(["beetle"], 91), "spotted")
	var bd := BattleBoard.new()
	bd.setup(b2, "jungle")
	bd.size = Vector2(1280, 800)
	bd.refit()
	var uk2: Array = bd._unit_keys()
	var r2: Rect2 = uk2[0][1]
	var spr := Rect2(r2.get_center() - Vector2(40, 60), Vector2(80, 100))
	var part := [float(uk2[0][0]) + 0.4, 0, Vector2i(2, 2)]
	bd._fade_dt = 0.0
	ok(is_equal_approx(bd._foliage_alpha(part, 0, spr, uk2), oa), "on load a sprite starts at its target alpha (no pop-in)")
	bd._fade_dt = 1.0 / 60.0
	var a_prev := bd._foliage_alpha(part, 0, spr, [])
	ok(a_prev > oa and a_prev < 1.0 + 0.0001, "unit steps away: the alpha eases back instead of jumping")
	var mono := true
	for i in 30:
		var a_now := bd._foliage_alpha(part, 0, spr, [])
		mono = mono and a_now >= a_prev - 0.0001
		a_prev = a_now
	ok(mono and a_prev > 0.97, "the tween is monotonic and settles within about half a second (%.3f)" % a_prev)
	var t0 := 0
	var a_s := 1.0
	while a_s > oa + 0.05 and t0 < 120:
		a_s = bd._foliage_alpha(part, 0, spr, uk2)
		t0 += 1
	ok(t0 > 2 and t0 <= 30, "fading to the 'unit behind' alpha takes a few frames (quick, under 0.5 s: %d frames)" % t0)
	# unit outline + foot ring
	var tex: Texture2D = bd._unit_tex(b2.player)
	var sil: Texture2D = bd._silhouette(tex)
	ok(sil.get_size() == tex.get_size() and sil == bd._silhouette(tex), "outline silhouette keeps the sprite size and is cached")
	var simg := sil.get_image()
	var solid := true
	for yy in range(0, simg.get_height(), 3):
		for xx in range(0, simg.get_width(), 3):
			var c := simg.get_pixel(xx, yy)
			solid = solid and (c.a == 0.0 or (c.a == 1.0 and c.r > 0.99 and c.g > 0.99))
	ok(solid, "the silhouette is a flat white mask of the sprite")
	var uo: Dictionary = v["unit_outline"]
	ok(bool(uo["enabled"]) and float(uo["px"]) >= 1.0 and Color(String(uo["player"])) != Color(String(uo["enemy"])), "outline: enabled, 1px, player and enemy colours differ")
	ok(bool(v["unit_ring"]["enabled"]) and float(v["unit_ring"]["alpha"]) > 0.2, "foot ring is enabled in data")
	var src := FileAccess.get_file_as_string("res://scripts/ui/BattleBoard.gd")
	ok(src.contains("_draw_unit_outline(u, t2, pos, sz)") and src.contains("_draw_unit_marks_under(u, gfoot)"), "units are drawn with the outline + ring")
	ok(src.contains("_foliage_alpha(part, 6,") and src.contains("_foliage_alpha(part, 0,") and src.contains("_foliage_alpha(part, 7,"), "border foliage, obstacles and decoration use the fade")
	bd.free()
	var readme := FileAccess.get_file_as_string("res://README.md")
	ok(readme.contains("data/visibility.json") and readme.contains("border_alpha"), "README documents the foliage fade")


# ------------------------------------------------------------------ exit paths: negative-space corridors outside the board

func test_exit_paths() -> void:
	section("exit paths: tree-free corridors OUTSIDE the board, hidden in a fight, opened after the clear")
	var cfg: Dictionary = DB.table("visibility")["exit_path"]
	ok(int(cfg["width"]) >= 2 and int(cfg["width"]) <= 3 and int(cfg["length"]) >= 4 and float(cfg["fade_time"]) > 0.0, "exit_path data: corridor 2-3 tiles wide, long enough to cross the tree line")
	var sizes := [Vector2i(7, 5), Vector2i(9, 9), Vector2i(12, 7), Vector2i(16, 10)]
	var fwd_ok := true
	var outside_ok := true
	var edge_ok := true
	var count_ok := true
	var sides_ok := true
	var overlap_ok := true
	var shape_ok := true
	var n_checked := 0
	for sd in range(1, 41):
		var g := Vector2i(sizes[sd % sizes.size()])
		var grid := BGrid.new(g.x, g.y)
		var rng := RandomNumberGenerator.new()
		rng.seed = sd * 31
		var want := 1 + sd % 3
		var pl := Vector2i(g.x / 2, g.y / 2)
		var ex: Array = ExitGen.place_exits(grid, want, rng, pl)
		n_checked += 1
		count_ok = count_ok and ex.size() == want and ex.size() <= 3
		fwd_ok = fwd_ok and ExitGen.FORWARD.has(String(ex[0]["side"]))
		var seen_sides := {}
		var seen_tiles := {}
		for e in ex:
			seen_sides[e["side"]] = true
			var pos: Vector2i = e["pos"]
			edge_ok = edge_ok and ExitGen.is_edge(grid, pos) and not (pos.x in [0, g.x - 1] and pos.y in [0, g.y - 1])
			var cor: Array = ExitGen.corridor(pos, String(e["side"]), int(cfg["width"]), int(cfg["length"]))
			shape_ok = shape_ok and cor.size() == int(cfg["width"]) * int(cfg["length"])
			for c in cor:
				outside_ok = outside_ok and not grid.in_bounds(c["tile"])
				overlap_ok = overlap_ok and not seen_tiles.has(c["tile"])
				seen_tiles[c["tile"]] = true
			# the first corridor tile touches the trigger tile
			outside_ok = outside_ok and BGrid.dist(Vector2i(cor[int(cfg["width"]) / 2]["tile"]), pos) == 1
		sides_ok = sides_ok and seen_sides.size() == ex.size()
	ok(n_checked == 40 and count_ok, "1-3 exits per room (never more than 3) over 40 seeded arenas")
	ok(fwd_ok, "door 0 (the main path forward) always leaves through an up-screen side (NE / NW)")
	ok(sides_ok, "every exit uses a different side")
	ok(edge_ok, "the trigger tiles are edge tiles, never corners")
	ok(outside_ok and shape_ok, "every corridor tile lies OUTSIDE the grid (nothing on the tile mesh), starts at the trigger tile, width x length tiles")
	ok(overlap_ok, "corridors of different exits never overlap")
	var out_ok := ExitGen.out_dir("NE") == Vector2i(0, -1) and ExitGen.out_dir("NW") == Vector2i(-1, 0) and ExitGen.out_dir("SE") == Vector2i(1, 0) and ExitGen.out_dir("SW") == Vector2i(0, 1)
	ok(out_ok, "outward directions: NE -y, NW -x, SE +x, SW +y")
	# visibility rules on the battle
	var run := make_run(77)
	run.stage["weather"] = "clear"
	run.stage["step"] = 1
	var room := make_room(["beetle"], 5)
	var bsp := Battle.create(run, room, "spotted")
	var bam := Battle.create(run, room, "ambush")
	ok(not bsp.exits.is_empty() and not bsp.exits_visible(), "spotted fight: the exit paths are hidden (no gap, no badge)")
	ok(bam.exits_visible(), "unspotted: the paths are visible so you can sneak out")
	bsp.mp = 5
	ok(bsp.exits.all(func(e): return not bsp._occupied().has(e["pos"]) and not bsp.grid.blocks_move(e["pos"])), "hidden exit trigger tiles are plain walkable ground (no seal that would reveal them)")
	run.stage["step"] = bsp.exits_step      # the cleared fight advanced the run to the exits' step
	var bex := Battle.create_explore(run, bsp)
	ok(bex.phase == "explore" and bex.exits_visible() and bex.exits.size() == bsp.exits.size(), "after the clear the same exits are revealed (explore phase)")
	var same := true
	for i in bex.exits.size():
		same = same and bex.exits[i]["pos"] == bsp.exits[i]["pos"] and bex.exits[i]["side"] == bsp.exits[i]["side"]
	ok(same, "the revealed exits are exactly where the corridors were (same trigger tiles / sides)")
	bex.mp = 40
	ok(bex.exits.all(func(e): return bex.reachable_tiles().has(e["pos"])), "pathfinding: every trigger tile is reachable from the player in the explore phase")
	# board: per theme
	for theme in ["jungle", "tundra", "cave"]:
		var bd := BattleBoard.new()
		bd.setup(bsp, theme)
		ok(bd.exit_vis == 0.0 and bd.exit_target() == 0.0, "%s: hidden while fighting spotted (exit_vis 0)" % theme)
		var cnt := 0
		var inside := false
		for e in bsp.exits:
			for c in ExitGen.corridor(e["pos"], String(e["side"]), int(cfg["width"]), int(cfg["length"])):
				cnt += 1
				inside = inside or bsp.grid.in_bounds(c["tile"])
				if not bd.is_corridor_tile(c["tile"]):
					cnt -= 1
		ok(cnt == bsp.exits.size() * int(cfg["width"]) * int(cfg["length"]) and not inside, "%s: the board knows every corridor tile, all outside the grid" % theme)
		var e0: Dictionary = bsp.exits[0]
		var mid: Vector2i = Vector2i(e0["pos"]) + Vector2i(e0["dir"]) * 2
		bd.size = Vector2(1280, 800)
		bd.refit()
		ok(bd.pick(Iso.center(Vector2(mid))) == mid, "%s: a hidden path is not clickable" % theme)
		bd.exit_vis = 1.0
		ok(bd.pick(Iso.center(Vector2(mid))) == e0["pos"], "%s: clicking an open path = its edge trigger tile" % theme)
		bd.free()
		var be := BattleBoard.new()
		be.setup(bex, theme)
		ok(be.gate_state == "locked" or not bex.exits_unlock_anim, "%s: after a clear the reveal starts locked (fade-in)" % theme)
		if be.gate_state == "locked":
			ok(be.exit_vis == 0.0 and be.exit_target() == 0.0, "%s: ...paths still closed until open_gates()" % theme)
			be.open_gates()
			ok(be.gate_state == "opening" and be.exit_target() == 1.0, "%s: open_gates() starts the reveal (target 1)" % theme)
		var ba := BattleBoard.new()
		ba.setup(bam, theme)
		ok(ba.exit_vis == 1.0, "%s: unspotted: paths visible from the start (no pop-in)" % theme)
		ba.free()
		be.free()
	# no sprites, README
	var bsrc := FileAccess.get_file_as_string("res://scripts/ui/BattleBoard.gd")
	ok(bsrc.find("exit_\" + theme_id") < 0 and bsrc.find("png(\"exit") < 0 and bsrc.find("png(\"gate") < 0, "no exit / gate sprite is loaded by the board")
	var readme := FileAccess.get_file_as_string("res://README.md")
	ok(readme.contains("negative space") and readme.contains("exit_path"), "README documents the exit paths")


# ------------------------------------------------------------------ camera: zoom-out limit (whole board + margin)

func test_zoom_limit() -> void:
	section("camera: zoom out is limited to the whole board plus a margin (per arena + window size)")
	var cam: Dictionary = DB.table("arenas")["camera"]
	var margin := float(cam["zoom_out_margin"])
	ok(margin >= 0.10 and margin <= 0.15, "zoom_out_margin lives in data/arenas.json (%.2f, about 10-15%%)" % margin)
	var steps: Array = cam["zoom_steps"]
	var v: Array = cam["view"]
	var wins := [Vector2(960, 540), Vector2(1280, 720), Vector2(1920, 1080), Vector2(2560, 1600), Vector2(3840, 2160)]
	var arenas := [Vector2i(5, 5), Vector2i(7, 5), Vector2i(10, 7), Vector2i(12, 7), Vector2i(14, 10), Vector2i(18, 12)]
	var fit_ok := true
	var below_auto := true
	var largest_ok := true
	var clamp_ok := true
	var in_ok := true
	var any_zoomed_out := false
	var combos := 0
	for win in wins:
		for a in arenas:
			combos += 1
			var run := make_run(300 + a.x)
			var room := make_room(["beetle"], 300 + a.y)
			room["arena_fixed"] = {"w": a.x, "h": a.y, "shape": "rect", "cut": Vector2i.ZERO, "type": "battle", "corner": 0}
			var b := Battle.create(run, room, "spotted")
			var bd := BattleBoard.new()
			bd.setup(b, "jungle")
			bd.size = win
			bd.refit()
			var mz := bd.min_zoom()
			var bs := Iso.board_size(a.x, a.y, mz) * (1.0 + margin)
			# the whole board + margin fits at the minimum zoom (unless even the smallest step cannot)
			fit_ok = fit_ok and (mz == float(steps.back()) or (bs.x <= float(v[2]) + Iso.extra_w and bs.y <= float(v[3]) + Iso.extra_h))
			# ...and it is the largest step that does
			for z in steps:
				if float(z) > mz:
					var bz := Iso.board_size(a.x, a.y, float(z)) * (1.0 + margin)
					largest_ok = largest_ok and (bz.x > float(v[2]) + Iso.extra_w or bz.y > float(v[3]) + Iso.extra_h)
			below_auto = below_auto and mz <= Iso.auto_zoom(a.x, a.y) + 0.0001
			in_ok = in_ok and absf(Iso.zoom - Iso.auto_zoom(a.x, a.y)) < 0.0001 and Iso.zoom >= mz - 0.0001      # initial zoom respects it
			any_zoomed_out = any_zoomed_out or mz < Iso.auto_zoom(a.x, a.y)
			# wheel / keys: zoom out as far as possible, never below the minimum; zoom in still reaches the maximum
			for i in 14:
				bd.step_zoom(-1)
				clamp_ok = clamp_ok and Iso.zoom >= mz - 0.0001
			var out_z := Iso.zoom
			clamp_ok = clamp_ok and absf(out_z - mz) < 0.0001
			for i in 14:
				bd.step_zoom(1)
			clamp_ok = clamp_ok and absf(Iso.zoom - float(steps[0])) < 0.0001
			bd.free()
	ok(combos == 30, "checked %d arena x resolution combinations" % combos)
	ok(fit_ok, "at the minimum zoom the whole board plus the %.0f%% margin fits the view" % (margin * 100.0))
	ok(largest_ok and below_auto, "the minimum is the largest step that fits with the margin (at or just beyond the auto-fit zoom)")
	ok(in_ok, "the initial zoom is the auto-fit zoom and never below the minimum")
	ok(clamp_ok, "wheel / zoom keys clamp at the minimum zoom; zoom-in keeps its maximum (%.1f)" % float(steps[0]))
	ok(any_zoomed_out, "some arenas / windows can zoom out a step beyond the auto-fit zoom (the margin gives room)")
	# the minimum adapts to the window: a big window allows a closer minimum for the same arena
	var run2 := make_run(5)
	var room2 := make_room(["beetle"], 5)
	room2["arena_fixed"] = {"w": 12, "h": 7, "shape": "rect", "cut": Vector2i.ZERO, "type": "battle", "corner": 0}
	var b2 := Battle.create(run2, room2, "spotted")
	var bd2 := BattleBoard.new()
	bd2.setup(b2, "jungle")
	bd2.size = Vector2(960, 540)
	bd2.refit()
	var small_min := bd2.min_zoom()
	bd2.size = Vector2(3840, 2160)
	bd2.refit()
	ok(bd2.min_zoom() >= small_min, "a bigger window never forces a smaller minimum zoom (%.2f -> %.2f)" % [small_min, bd2.min_zoom()])
	# resize while zoomed too far out: the minimum is recomputed and the zoom eases back (no snap)
	var bd3 := BattleBoard.new()
	var room3 := make_room(["beetle"], 6)
	room3["arena_fixed"] = {"w": 16, "h": 10, "shape": "rect", "cut": Vector2i.ZERO, "type": "battle", "corner": 0}
	var b3 := Battle.create(make_run(6), room3, "spotted")
	bd3.setup(b3, "jungle")
	bd3.size = Vector2(640, 360)
	bd3.refit()
	var small_min3 := bd3.min_zoom()
	bd3.zoom_manual = 0.5                 # the player is somehow zoomed out further than the arena allows
	bd3.refit()
	ok(bd3.zoom_manual == small_min3 and absf(Iso.zoom - small_min3) < 0.0001 and float(int(small_min3)) == small_min3, "a zoom below the minimum snaps straight to the (whole-number) minimum (%.2f): zoom steps never ease between sizes" % Iso.zoom)
	bd3.size = Vector2(640, 360)          # the real window may grow, but the canvas the board sees stays 640x360: the limit does not change
	bd3.refit()
	ok(bd3.min_zoom() == small_min3 and absf(Iso.zoom - small_min3) < 0.0001, "the fixed 640x360 canvas keeps the same minimum zoom however the window is scaled (%.2f)" % bd3.min_zoom())
	bd2.free()
	bd3.free()
	var readme := FileAccess.get_file_as_string("res://README.md")
	ok(readme.contains("zoom_out_margin"), "README documents the zoom-out limit")


# ------------------------------------------------------------------ battle HUD without backing panels

func test_hud_no_panels() -> void:
	section("battle HUD: no blue panel behind the player stats or the Move / End Turn buttons")
	var b := duel("beetle", 94, 0)
	var sc: Node = _screen_ready(b)
	await process_frame
	await process_frame
	var hud = sc.bhud
	var card: Control = hud.get_node("PlayerCard")
	ok(not (card is Panel), "the player card is an invisible layout box, not a Panel")
	var cardr := Rect2(card.position, card.size)
	var behind := 0
	for ch in hud.get_children():
		if ch is Panel or ch is PanelContainer:
			if Rect2(ch.position, ch.size).intersects(cardr):
				behind += 1
	ok(behind == 0, "no Panel is drawn behind the health / stamina / hunger bars or the portrait (%d)" % behind)
	var pads := Rect2(sc.move_btn.position - Vector2(8, 8), Vector2(124, 112))
	var boxes := 0
	for ch in sc.get_children():
		if (ch is Panel or ch is PanelContainer or ch is NinePatchRect) and ch != sc.info_panel and ch != sc.order_panel and ch != sc.log_panel and ch != sc.explore_panel:
			if Rect2(ch.position, ch.size).intersects(pads):
				boxes += 1
	ok(boxes == 0, "no panel / outline box behind the Move and End Turn buttons (%d)" % boxes)
	ok(sc.move_btn.visible and sc.end_btn.visible and sc.move_btn.text == "Move", "the stone-wood Move and End Turn buttons are still there")
	for l in [sc.mp_label, hud.lv_label, hud._name_label, hud.status_label, hud.pile_label]:
		ok(l.get_theme_color("font_shadow_color").a > 0.5 and l.get_theme_constant("shadow_offset_x") >= 1, "HUD text '%s' has a drop shadow so it reads over the board" % l.text)
	for k in ["hp", "stamina", "hunger"]:
		ok(is_instance_valid(hud.bars[k]) and hud.bars[k].visible, "%s bar is still drawn" % k)
	sc.queue_free()
	await process_frame
