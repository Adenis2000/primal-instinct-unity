extends Node
## Scripted UI tour: drives the REAL screens (clicks via the same handlers the mouse uses),
## saves screenshots and fails loudly if anything breaks. Run with a display (xvfb):
##   godot --path . --rendering-driver opengl3 -- --tour [--out=/path/to/dir]
## tools/run_tour.sh wraps this.

var main: Control
var out_dir := "/workspace/dino-deckbuilder/screenshots"
var rng := RandomNumberGenerator.new()
var shots := 0
var problems: Array = []
var demos_only := false      # --demos: only the foliage + exit-path screenshots (fast iteration)

func run(main_: Control, args: PackedStringArray) -> void:
	main = main_
	for a in args:
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a == "--demos":
			demos_only = true
	DirAccess.make_dir_recursive_absolute(out_dir)
	rng.seed = 4
	Game.persist_enabled = false
	Game.load_save()
	Settings.persist = false          # the tour never touches the player's settings; it always plays the story cutscene
	Settings.intro_mode = 0
	_tour()

func wait(t: float) -> void:
	await get_tree().create_timer(t).timeout

func shot(name: String, delay: float = 0.35) -> void:
	await wait(delay)
	await RenderingServer.frame_post_draw
	var img := ShotUtil.compose(get_viewport().get_texture().get_image(), get_window().size)
	var path := "%s/%02d_%s.png" % [out_dir, shots, name]
	img.save_png(path)
	shots += 1
	print("TOUR screenshot: ", path)

## Screenshot at the window's native pixels (no 2x upscale), e.g. for the 4K menu shot.
func shot_native(name: String, delay: float = 0.35) -> void:
	await wait(delay)
	await RenderingServer.frame_post_draw
	var img := ShotUtil.compose(get_viewport().get_texture().get_image(), get_window().size)
	var path := "%s/%02d_%s.png" % [out_dir, shots, name]
	img.save_png(path)
	shots += 1
	print("TOUR screenshot: ", path, " ", img.get_size())

func expect(cond: bool, msg: String) -> void:
	if cond:
		print("TOUR ok: ", msg)
	else:
		problems.append(msg)
		print("TOUR FAIL: ", msg)

func screen() -> Control:
	return cur()

func hint_dismiss() -> void:
	if Hints.current() != "":
		Hints._dismiss()

func fast(s: Control) -> void:
	if "speed" in s:
		s.speed = 12.0

var align_checks := 0
var align_bad := 0

## Every unit must be drawn exactly on its logical tile whenever the screen is idle.
func check_align(s: Control) -> void:
	var b: Battle = Game.battle
	for u in b.units:
		if not u.alive:
			continue
		align_checks += 1
		var c: Vector2 = Iso.center(Vector2(u.pos))
		if u.vis_pos != Vector2(u.pos) or Iso.tile_at(c) != u.pos or s.board.pick(c) != u.pos or u.vis_off != Vector2.ZERO or u.vis_lift != 0.0:
			align_bad += 1
			print("TOUR misaligned: ", u.id, " pos=", u.pos, " vis=", u.vis_pos)

func play_battle(max_steps: int = 400) -> void:
	var s: Control = screen()
	if s.name != "battle":
		return
	fast(s)
	var b: Battle = Game.battle
	var steps := 0
	while steps < max_steps and s != null and is_instance_valid(s) and cur() == s:
		steps += 1
		await wait(0.03)
		if cur() != s or not is_instance_valid(s):
			break
		if s.busy:
			continue
		check_align(s)
		if b.phase == "ambush":
			var t := b.ambush_targets()
			if t.is_empty():
				s._on_end_pressed()
			else:
				s._on_tile_clicked(t[0].pos, MOUSE_BUTTON_LEFT)
			continue
		if b.phase != "player":
			continue
		var a := AutoPlayer.next_action(b, rng)
		match a["type"]:
			"card":
				var i: int = a["i"]
				var c := b.card_at(i)
				if c["target"] == "enemy":
					s._select_card(i)
					await wait(0.02)
					s._on_tile_clicked(a["target"].pos, MOUSE_BUTTON_LEFT)
				elif c["target"] == "tile":
					s._select_card(i)
					await wait(0.02)
					s._on_tile_clicked(a["target"], MOUSE_BUTTON_LEFT)
				else:
					s._select_card(i)
			"move":
				s.move_mode = true
				s._on_tile_clicked(a["pos"], MOUSE_BUTTON_LEFT)
			_:
				s._on_end_pressed()


## Resolve the reward screen the way a player would: eat the first corpse, skip the rest, press Continue.
## The screen the player is looking at: the popup over the board (reward / draft / item / branch) if there is one.
func cur() -> Control:
	return main.popup_node if main.popup_node != null and is_instance_valid(main.popup_node) else main.current

func finish_reward(room_type: String = "battle") -> void:
	var sc: Control = cur()
	if sc.name != "reward":
		return
	for i in sc.rows.size():
		sc._decide(i, "eat" if i == 0 else "")
	await wait(0.2)
	Game.after_reward(room_type)
	await wait(0.6)

var seen_screens := {}

## Take one screenshot the first time each screen/variant shows up.
func once(key: String, delay: float = 0.4) -> void:
	if seen_screens.has(key):
		return
	seen_screens[key] = true
	await shot(key, delay)

## Drive ANY screen like a player until `stop` returns true (or the step budget is spent).
func drive(stop: Callable, budget: int = 60) -> void:
	for step in budget:
		await wait(0.5)
		hint_dismiss()
		hint_dismiss()
		if stop.call():
			return
		var sc: Control = cur()
		var n: String = sc.name
		match n:
			"intro_cutscene":
				sc.skip(true)
			"stage_intro":
				await once("auto_stage_intro", 0.2)
				sc.skip()
			"battle":
				var b: Battle = Game.battle
				if b.phase == "explore":
					await once("auto_explore_gates", 0.2)
					if stop.call():
						return
					sc._take_exit(0)
					await wait(1.0)
				else:
					await play_battle()
					await wait(1.0)
			"reward":
				await once("auto_reward", 0.3)
				await finish_reward(String(sc.room.get("type", "battle")))
			"draft":
				await once("auto_draft_" + String(sc.mode), 0.2)
				sc._pick(sc.offers[0])
			"item":
				await once("auto_item_pick", 0.2)
				sc._take(sc.offers[0])
			"branch":
				await once("auto_branch", 0.2)
				var pick := ""
				for o in Game.run.branch_options(maxi(Game.run.pending_evolution_tier, Game.run.tier())):
					if o["unlocked"] and String(o["id"]) != "":
						pick = String(o["id"])
						break
				sc._choose(pick)
			"event":
				await once("auto_event", 0.2)
				sc._choose(0)
				await wait(0.4)
				if cur() == sc:
					await once("auto_event_outcome", 0.2)
					sc._continue()
			"puzzle":
				await once("auto_puzzle", 0.2)
				var tries := 0
				while not sc.accepting and tries < 100:
					tries += 1
					await wait(0.1)
				for q in sc.puzzle.sequence:
					sc._press(int(q))
					await wait(0.25)
				await wait(0.5)
				sc._continue()
			"gameover":
				return
			_:
				await wait(0.3)

func _tour() -> void:
	await wait(0.5)
	if demos_only:
		await _foliage_demo()
		await _exit_paths_demo()
		print("TOUR complete: %d screenshots, %d problems" % [shots, problems.size()])
		for p in problems:
			print("TOUR PROBLEM: ", p)
		get_tree().quit(1 if problems.size() > 0 else 0)
		return
	# 0. main menu (first screen on launch)
	expect(cur().name == "menu", "the game starts on the main menu")
	var win0: Vector2i = get_window().size
	for msz in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1600), Vector2i(3840, 2160)]:
		get_window().size = msz
		await wait(0.7)
		expect(get_viewport().get_visible_rect().size == Vector2(640, 360), "the menu is drawn on the 640x360 canvas at %dx%d" % [msz.x, msz.y])
		expect(cur().forest.size.x >= 640.0 and cur().forest.drawn["sprites"] > 20 and cur().forest.drawn["tiles"] > 20, "the forest scene draws at %dx%d" % [msz.x, msz.y])
		await shot_native("main_menu_%dx%d" % [msz.x, msz.y], 0.3)
	get_window().size = win0
	await wait(0.6)
	var dn := InputEventKey.new()
	dn.keycode = KEY_DOWN
	dn.pressed = true
	cur()._unhandled_key_input(dn)
	expect(cur().sel == 1, "Down moves the selection to Settings")
	await shot("main_menu_settings_selected", 0.3)
	cur()._settings()
	await shot("main_menu_settings_open", 0.4)
	main.close_settings()
	await wait(0.2)
	cur()._select(0)
	cur()._play()
	await wait(0.5)
	# 1. egg screen
	expect(cur().name == "egg", "Play leads to the egg screen")
	await shot("egg_select")
	cur()._pick("tyrannosaurus")
	await shot("egg_locked_slot", 0.15)
	cur()._pick("velociraptor")
	# hatch via the real button handler (seeded for reproducibility)
	cur().seed_edit.text = "20261016"
	cur()._hatch()
	await wait(0.9)
	expect(cur().name == "customize", "HATCH! opens the egg-cracking customization screen")
	await shot("customize_egg_cracking", 0.6)
	await shot("customize_egg_opening", 0.7)
	await shot("customize_peek_default", 2.4)
	cur().pick("skin", "jungle")
	await shot("customize_jungle_skin", 0.3)
	cur().pick("skin", "azure")
	cur().pick("pattern", "stripes")
	cur().pick("pcolor", "gold")
	cur().pick("gender", "female")
	await shot("customize_azure_stripes_female", 0.4)
	cur().pick("skin", "ember")
	cur().pick("pattern", "spots")
	cur().pick("pcolor", "cream")
	cur().pick("gender", "male")
	await shot("customize_ember_spots_male", 0.3)
	cur()._confirm()
	await wait(1.8)
	expect(cur().name == "intro_cutscene", "confirming hatches the baby and starts the run with the story cutscene")
	expect(Game.run.look["skin"] == "ember" and Game.run.look["pattern"] == "spots", "the chosen look is stored on the run")
	expect(Game.run.seed_val == 20261016, "seed stored in run")
	await _cutscene_tour()
	expect(cur().name == "stage_intro", "skipping the cutscene continues into the stage intro (weather)")
	# the cinematic, frozen at fixed times: sky, text in, text out, camera tilting down, arriving on the board
	var intro: Control = cur()
	intro.set_process(false)
	intro.sky.animate = false
	for fr in [["stage_intro_1_sky", 0.9], ["stage_intro_2_text", 4.5], ["stage_intro_3_text_out", 6.4], ["stage_intro_4_tilt", 7.5], ["stage_intro_5_tilt_end", 8.4]]:
		intro._apply(float(fr[1]))
		intro.sky.time = float(fr[1])
		await shot(String(fr[0]), 0.35)
	var ek := InputEventKey.new()
	ek.pressed = true
	ek.keycode = KEY_SPACE
	intro._input(ek)      # any key skips
	await wait(0.5)
	expect(cur().name == "battle" and Game.battle.phase == "explore", "stage intro leads to the battlefield (explore) with gates")
	await shot("explore_first_gates", 0.8)
	hint_dismiss()
	hint_dismiss()
	hint_dismiss()
	# hover the first gate: tooltip with the reward hint
	cur()._on_tile_hovered(Game.battle.exits[0]["pos"])
	await shot("explore_hover_gate", 0.3)
	# 2. first room: tutorial beetle, unspotted -- walk into gate 0 via the real click handler
	cur()._on_tile_clicked(Game.battle.exits[0]["pos"], MOUSE_BUTTON_LEFT)
	await wait(1.6)
	expect(cur().name == "battle" and Game.battle.phase == "ambush", "first door opens straight onto the board, unseen (no encounter screen)")
	await shot("arrive_unseen", 0.6)
	expect(cur().name == "battle", "ambush starts a battle")
	await shot("battle_ambush_phase", 0.5)
	hint_dismiss()
	hint_dismiss()
	hint_dismiss()
	hint_dismiss()
	# the four supplied raptor poses on the board (SE, SW, NE, NW)
	var pu: BUnit = Game.battle.player
	var f0: Vector2i = pu.facing
	for fd in [["se", Vector2i(1, 0)], ["sw", Vector2i(0, 1)], ["ne", Vector2i(0, -1)], ["nw", Vector2i(-1, 0)]]:
		pu.facing = fd[1]
		pu.vis_facing = fd[1]
		await shot("raptor_facing_" + String(fd[0]), 0.25)
	pu.facing = f0
	pu.vis_facing = f0
	# ambush strike
	var bs: Control = cur()
	fast(bs)
	var tgt: BUnit = Game.battle.ambush_targets()[0]
	bs._on_tile_hovered(tgt.pos)
	await shot("battle_hover_detection", 0.3)
	bs._on_tile_clicked(tgt.pos, MOUSE_BUTTON_LEFT)
	await wait(1.2)
	await shot("battle_after_ambush", 0.2)
	if Game.battle.phase == "player":
		# select a card to show targeting overlay
		for i in Game.battle.hand.size():
			if Game.battle.card_playable(i) and Game.battle.card_at(i)["target"] == "enemy":
				bs._select_card(i)
				break
		await shot("battle_card_targeting", 0.3)
		bs._on_tile_clicked(Vector2i(0, 0), MOUSE_BUTTON_RIGHT)
	await play_battle()
	await wait(1.2)
	expect(cur().name == "reward" or cur().name == "gameover", "battle ends in reward")
	if cur().name == "reward":
		await shot("reward_victory", 0.6)
		cur()._decide(0, "eat")
		await shot("reward_eaten", 0.3)
		for i in range(1, cur().rows.size()):
			cur()._decide(i, "")
		Game.after_reward("battle")
		await wait(0.6)
		expect(cur().name == "draft", "draft follows victory")
		await shot("draft_cards", 0.5)
		hint_dismiss()
		cur()._pick(cur().offers[0])
		await wait(0.6)
		expect(cur().name == "battle" or cur().name == "draft", "draft returns to the battlefield")
		if cur().name == "battle":
			await shot("explore_after_clear", 0.8)
	# 2b. facing / move-mode demo on a spotted fight
	await _facing_demo()
	# 2c. animation + search-AI frames (real speed, frames saved to screenshots/anim/)
	await _anim_demo()
	# 2d. depth systems: keyword tooltips, telegraphs + intents, draft/item synergy highlights
	await _depth_demo()
	# 3. other room types on this stage's map (reach via real door flow when possible)
	await _show_rooms()
	# 3b. systems: secret cave, items, nutrition, branches
	await _systems_demo()
	# 4. spotted battle with weather + hunger + infection (elite)
	await _elite_and_evolution()
	# 5. stage 2 and boss
	await _stage2_and_boss()
	# 6. game over
	Game.run.hp = 0
	Game.run.game_over = true
	Game.run.cause = "Slain by a Smilodon."
	Game.goto("gameover")
	await shot("game_over", 0.6)
	expect(cur().get_node_or_null("gameover_menu") != null and cur().get_node_or_null("gameover_egg") != null, "the run-end screen offers the egg and the main menu")
	# deck overlay
	main.open_deck_overlay()
	await shot("deck_overlay", 0.3)
	for oc in main.overlay_layer.get_children():
		oc.queue_free()
	await wait(0.2)
	# 7. new runs on a settled screen: foliage / unit readability, then exit paths (hidden in the fight, revealed after the clear)
	Hints.clear()
	await wait(0.8)
	await _foliage_demo()
	await _exit_paths_demo()
	expect(align_checks > 50 and align_bad == 0, "units always drawn on their tile (%d checks, %d offsets)" % [align_checks, align_bad])
	print("TOUR complete: %d screenshots, %d problems" % [shots, problems.size()])
	for p in problems:
		print("TOUR PROBLEM: ", p)
	get_tree().quit(1 if problems.size() > 0 else 0)

## Foliage over the board is semi-transparent and units stay readable: screenshots right after the arena loads (2560x1600 + 1280x720).
func _foliage_demo() -> void:
	var win1: Vector2i = get_window().size
	DirAccess.make_dir_recursive_absolute(out_dir + "/foliage")
	for theme in ["jungle", "tundra", "cave"]:
		var r: RunState = Game.start_run("velociraptor", 4242)
		var room: Dictionary
		if theme == "cave":
			room = StageGen.make_cave_room(r)
		else:
			if theme == "tundra":
				r.advance_stage()
			room = _first_battle_room(r)
		r.enter_room(room)
		Game.battle = Battle.create(r, room, "spotted")
		Game.battle.begin()
		Game.goto("battle", {"room": room})
		await wait(0.8)
		var bs: Control = cur()
		fast(bs)
		for sz in [Vector2i(2560, 1600), Vector2i(1280, 720)]:
			get_window().size = sz
			await wait(0.7)
			Hints.clear()
			await wait(0.4)
			await RenderingServer.frame_post_draw
			var img := ShotUtil.compose(get_viewport().get_texture().get_image(), get_window().size)
			var path := "%s/foliage/after_%s_%dx%d.png" % [out_dir, theme, sz.x, sz.y]
			img.save_png(path)
			shots += 1
			print("TOUR screenshot: ", path, " ", img.get_size())
		var fade: Dictionary = bs.board._fade
		var faded := 0
		var bad := 0
		var ba := float(DB.table("visibility")["border_alpha"])
		for k in fade:
			if String(k).begins_with("6:"):
				if float(fade[k]) < 0.999:
					faded += 1
				if float(fade[k]) > ba + 0.01 and float(fade[k]) < 0.999:
					bad += 1
		expect(faded > 0 and bad == 0, "%s arena: %d border trees / foliage over the board are semi-transparent (none half-way)" % [theme, faded])
		var uk: Array = bs.board._unit_keys()
		expect(uk.size() == Game.battle.units.size(), "%s arena: every unit has an on-screen rect for the visibility test" % theme)
	get_window().size = win1
	await wait(0.5)

## Exit paths before / after the clear in jungle, tundra and cave: screenshots/exits/<theme>_{hidden,revealed}_<size>.png
func _exit_paths_demo() -> void:
	var win1: Vector2i = get_window().size
	DirAccess.make_dir_recursive_absolute(out_dir + "/exits")
	for theme in ["jungle", "tundra", "cave"]:
		var r: RunState = Game.start_run("velociraptor", 4242)
		# (the secret cave room has no exits of its own: the cave look is a normal fight on the cave theme)
		var room: Dictionary
		if theme == "tundra":
			r.advance_stage()
		room = _first_battle_room(r)
		r.stage["theme"] = theme
		r.enter_room(room)
		Game.battle = Battle.create(r, room, "spotted")
		Game.battle.theme_id = theme
		Game.battle.begin()
		Game.goto("battle", {"room": room})
		await wait(1.6)
		var bs: Control = cur()
		fast(bs)
		Hints.clear()
		for i in 6:
			hint_dismiss()
		expect(Game.battle.exits.size() >= 1 and Game.battle.exits.size() <= 3 and not Game.battle.exits_visible() and bs.board.exit_vis == 0.0, "%s: exits are hidden during the fight (%d paths)" % [theme, Game.battle.exits.size()])
		for sz in [Vector2i(2560, 1600), Vector2i(1280, 720)]:
			get_window().size = sz
			await wait(0.7)
			Hints.clear()
			await _save_shot("%s/exits/%s_hidden_%dx%d.png" % [out_dir, theme, sz.x, sz.y])
		# the area is cleared -> explore field: the corridors open
		for e in Game.battle.enemies:
			e.alive = false
		r.stage["step"] = Game.battle.exits_step
		Game.start_explore()
		await wait(1.0)
		bs = cur()
		Hints.clear()
		for i in 6:
			hint_dismiss()
		get_window().size = Vector2i(1280, 720)
		await wait(2.2)
		expect(cur().name == "battle" and Game.battle.phase == "explore" and cur().board.exit_vis >= 0.99, "%s: after the clear the exit paths are open" % theme)
		expect(Iso.zoom >= cur().board.min_zoom() - 0.001, "%s: the camera zoom respects the zoom-out limit (%.2f >= %.2f)" % [theme, Iso.zoom, cur().board.min_zoom()])
		for sz in [Vector2i(2560, 1600), Vector2i(1280, 720)]:
			get_window().size = sz
			await wait(0.8)
			Hints.clear()
			for i in 6:
				hint_dismiss()
			await _save_shot("%s/exits/%s_revealed_%dx%d.png" % [out_dir, theme, sz.x, sz.y])
	get_window().size = win1
	await wait(0.5)

## A normal fight door somewhere on the stage map (sets the run's step to it).
func _first_battle_room(r: RunState) -> Dictionary:
	var steps: Array = r.stage["steps"]
	for i in range(1, steps.size() - 1):
		for d in steps[i]["doors"]:
			if d["type"] == "battle":
				r.stage["step"] = i
				return d
	r.stage["step"] = 1
	return r.choose_door(0)

func _save_shot(path: String) -> void:
	await wait(0.3)
	await RenderingServer.frame_post_draw
	var img := ShotUtil.compose(get_viewport().get_texture().get_image(), get_window().size)
	img.save_png(path)
	shots += 1
	print("TOUR screenshot: ", path, " ", img.get_size())

func _facing_demo() -> void:
	var r: RunState = Game.run
	var src := _find_room("battle")
	if src.is_empty():
		src = _find_room("elite")
	var room := src.duplicate(true)
	room["unspotted_allowed"] = false
	r.hp = r.max_hp()
	r.enter_room(room)
	Game.enter_battle(room)
	await wait(1.4)
	for i in 6:
		hint_dismiss()
	var bs: Control = cur()
	fast(bs)
	var b: Battle = Game.battle
	while bs.busy or b.phase != "player":
		await wait(0.1)
	check_align(bs)
	await shot("battle_spotted_start", 0.4)
	var foe: BUnit = b.alive_enemies()[0]
	bs._on_tile_hovered(foe.pos)
	await shot("battle_hover_enemy_facing", 0.3)
	# hover a hand card: big readable copy (text 20 px) above it; an unplayable card shows why
	var cards_v: Array = bs.hand_root.get_children().filter(func(c): return c is CardView)
	if cards_v.size() > 0:
		bs._on_card_hover(cards_v[0], true)
		await shot("battle_card_hover_zoom", 0.3)
		bs._on_card_hover(cards_v[0], false)
		for cv in cards_v:
			if not b.card_playable(cv.index):
				bs._on_card_hover(cv, true)
				await shot("battle_card_hover_unplayable", 0.3)
				bs._on_card_hover(cv, false)
				break
	# click a tile in normal mode: only turns
	var before := b.player.pos
	var f0 := b.player.facing
	var turn_to := b.player.pos + Vector2i(0, 1) if b.player.facing != Vector2i(0, 1) else b.player.pos + Vector2i(-1, 0)
	bs._on_tile_clicked(turn_to, MOUSE_BUTTON_LEFT)
	await wait(0.2)
	expect(b.player.pos == before, "tour: click in normal mode does not move")
	expect(b.player.facing != f0, "tour: click in normal mode turns the player")
	check_align(bs)
	await shot("battle_turned_free", 0.3)
	for i in b.hand.size():
		if b.card_playable(i) and b.card_at(i)["target"] == "enemy":
			bs._select_card(i)
			break
	await shot("battle_card_targeting", 0.3)
	bs._on_tile_clicked(Vector2i(0, 0), MOUSE_BUTTON_RIGHT)
	bs._toggle_move()
	await shot("battle_move_mode", 0.3)
	# walk one tile in move mode, then verify alignment after the animation
	var reach: Dictionary = b.reachable_tiles()
	var dest := Vector2i(-1, -1)
	for q in reach.keys():
		if q != b.player.pos and (dest.x < 0 or int(reach[q]) > int(reach[dest])):
			dest = q
	if dest.x >= 0:
		bs._on_tile_clicked(dest, MOUSE_BUTTON_LEFT)
		while bs.busy:
			await wait(0.05)
		expect(b.player.pos == dest, "tour: move mode click walks to the tile")
		check_align(bs)
		await shot("battle_after_move", 0.3)
	bs._toggle_move()
	bs._toggle_move()
	await play_battle()
	await wait(1.2)
	if cur().name == "reward":
		await finish_reward("battle")
		if cur().name == "draft":
			hint_dismiss()
			cur()._pick(cur().offers[0])
			await wait(0.6)

## Save a numbered frame into screenshots/anim/<name>_<k>.png (cropped to the board area, 2x) without waiting for idle.
func anim_frame(name: String, k: int) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(out_dir + "/anim")
	img = img.get_region(Rect2i(60, 12, 520, 280))
	img.resize(img.get_width() * 3, img.get_height() * 3, Image.INTERPOLATE_NEAREST)
	img.save_png("%s/anim/%s_%02d.png" % [out_dir, name, k])

func _start_battle(enemies: Array, mode: String, seed_in: int) -> Control:
	var r: RunState = Game.run
	r.hp = r.max_hp()
	var room := {"type": "battle", "enemies": enemies, "infected": enemies.map(func(_e): return false), "seed": seed_in, "unspotted_allowed": true, "trap": false}
	r.enter_room(room)
	Game.battle = Battle.create(r, room, mode)
	Game.battle.begin()
	Game.goto("battle", {"room": room})
	await wait(1.0)
	for i in 6:
		hint_dismiss()
	var bs: Control = cur()
	while bs.busy:
		await wait(0.1)
	return bs

func _anim_demo() -> void:
	var r: RunState = Game.run
	r.stage["weather"] = "clear"
	# A. ambush pounce frames
	var bs: Control = await _start_battle(["spitter", "beetle"], "ambush", 2468)
	var b: Battle = Game.battle
	expect(b.phase == "ambush", "tour: ambush battle for the pounce animation")
	var tgt: BUnit = b.ambush_targets()[0]
	bs._on_tile_clicked(tgt.pos, MOUSE_BUTTON_LEFT)    # runs in the background; we sample frames while it plays
	for k in 14:
		await wait(0.045)
		await anim_frame("pounce", k)
	while bs.busy:
		await wait(0.05)
	check_align(bs)
	# B. walking frames (move mode)
	if b.phase == "player":
		var reach: Dictionary = b.reachable_tiles()
		var dest := Vector2i(-1, -1)
		for q in reach.keys():
			if q != b.player.pos and (dest.x < 0 or int(reach[q]) > int(reach[dest])):
				dest = q
		bs._toggle_move()
		bs._on_tile_clicked(dest, MOUSE_BUTTON_LEFT)
		for k in 12:
			await wait(0.05)
			await anim_frame("walk", k)
		while bs.busy:
			await wait(0.05)
		expect(b.player.pos == dest, "tour: walked to the clicked tile")
		check_align(bs)
		bs._toggle_move()
	# C. enemy turn: ranged projectile + hit
	var spit_seen := false
	bs._on_end_pressed()
	var k2 := 0
	var tries := 0
	while bs.busy and tries < 200:
		tries += 1
		await wait(0.04)
		if bs.board.fx.size() > 0 and k2 < 14:
			await anim_frame("enemy_turn", k2)
			k2 += 1
		spit_seen = spit_seen or bs.seen_types.has("projectile")
	expect(spit_seen, "tour: the ranged enemy fired a projectile")
	check_align(bs)
	await shot("battle_after_enemy_turn", 0.3)
	# D. lose sight -> '?' searching
	var sp: BUnit = null
	for e in b.alive_enemies():
		sp = e
	if sp != null and b.phase == "player":
		sp.perception = 1.0
		sp.tags = ["reptile"]
		sp.aware = true
		sp.last_seen = b.player.pos
		sp.pos = sp.pos if BGrid.dist(sp.pos, b.player.pos) > 3 else sp.pos
		sp.vis_state = "spotted"
		var guard := 0
		while sp.state != "searching" and b.phase == "player" and guard < 6:
			guard += 1
			bs._on_end_pressed()
			while bs.busy:
				await wait(0.05)
			sp.aware = true if sp.state == "idle" else sp.aware
		expect(sp.state == "searching" or b.phase != "player", "tour: enemy that lost sight is searching")
		if b.phase == "player":
			await shot("battle_enemy_searching", 0.5)
			check_align(bs)
	await play_battle()
	await wait(1.2)
	if cur().name == "reward":
		await finish_reward("battle")
		if cur().name == "draft":
			hint_dismiss()
			cur()._pick(cur().offers[0])
			await wait(0.6)

func _depth_demo() -> void:
	var r: RunState = Game.run
	r.stage["weather"] = "clear"
	# A. telegraphed heavy attack + intent chips + keyword tooltip on the zoomed card
	var bs: Control = await _start_battle(["glyptodon"], "spotted", 777)
	var b: Battle = Game.battle
	while b.phase != "player":
		await wait(0.1)
	var e: BUnit = b.alive_enemies()[0]
	var bash := {}
	for a in e.abilities:
		if bool(a.get("windup", false)):
			bash = a
	e.pos = b.player.pos + Vector2i(1, 0)
	e.facing = Vector2i(-1, 0)
	await bs._do(func(): b._start_windup(e, bash))
	expect(not e.windup.is_empty() and b.intent_of(e)["kind"] == "windup", "tour: glyptodon telegraphs Bash (red tiles + intent)")
	for i in 4:
		await wait(0.3)
		hint_dismiss()
	await shot("battle_telegraph_intent", 0.4)
	# keyword tooltip: hover a keyword in the zoomed card for ~1 s
	b.hand = ["rake", "gore", "backstab", "mark_prey", "dazing_blow"]
	bs._refresh_all()
	await wait(0.3)
	var cards_v: Array = bs.hand_root.get_children().filter(func(c): return c is CardView)
	for i in 3:
		hint_dismiss()
		await wait(0.2)
	if cards_v.size() > 0:
		bs._on_card_hover(cards_v[0], true)
		await wait(0.2)
		if bs.zoom != null:
			bs.get_viewport().warp_mouse(bs.zoom.global_position + Vector2(60, 120))
			bs.zoom._text.meta_hover_started.emit("bleed")
			await wait(Keywords.HOVER_DELAY + 0.3)
			expect(get_tree().root.get_node_or_null("KwTipLayer") != null, "tour: hovering a keyword for ~1 s shows the glossary tooltip")
			await shot("keyword_tooltip_zoom", 0.2)
			bs.zoom._text.meta_hover_ended.emit("bleed")
		bs._on_card_hover(cards_v[0], false)
	Keywords.hide_tip()
	# B. draft with synergy highlights (deck leans Bleed / Flank / Ambush / Speed)
	var saved_deck: Array = r.deck.duplicate()
	r.deck.append_array(["rake", "open_vein", "gore", "backstab", "flanking_strike", "mark_prey", "rending_charge", "dazing_blow"])
	Game.goto("draft", {"mode": "elite", "queue": []})
	await wait(0.6)
	hint_dismiss()
	hint_dismiss()
	await shot("draft_synergy_highlight", 0.4)
	# keyword tooltip on a draft card
	var dv: Array = cur().get_children().filter(func(c): return c is CardView)
	if dv.size() > 0:
		dv[0]._text.meta_hover_started.emit(Keywords.find(String(dv[0].card["text"]))[0] if not Keywords.find(String(dv[0].card["text"])).is_empty() else "bleed")
		await wait(Keywords.HOVER_DELAY + 0.3)
		await shot("keyword_tooltip_draft", 0.2)
		dv[0]._text.meta_hover_ended.emit("bleed")
	Keywords.hide_tip()
	r.deck = saved_deck
	# C. item choice with archetype tags and keyword text
	r.add_item("blood_sigil")
	r.add_item("rending_claws")
	var offers := r.offer_items("boss")
	Game.goto("item", {"source": "boss", "offers": offers, "queue": []})
	await wait(0.5)
	hint_dismiss()
	await shot("item_choice_tags", 0.3)

func _find_room(type: String) -> Dictionary:
	for st in Game.run.stage["steps"]:
		for d in st["doors"]:
			if d["type"] == type:
				return d
	return {}

func _show_rooms() -> void:
	var r: RunState = Game.run
	# event
	var ev := _find_room("event")
	r.enter_room(ev)
	Game.goto("event", {"room": ev})
	await shot("event_choices", 0.5)
	cur()._choose(0)
	await shot("event_outcome", 0.3)
	# forage
	var fo := _find_room("forage")
	Game.goto("event", {"room": fo})
	await shot("forage_choices", 0.5)
	cur()._choose(0)
	await shot("forage_outcome", 0.3)
	# puzzle: solve through the UI
	var pz := _find_room("puzzle")
	Game.goto("puzzle", {"room": pz})
	await wait(0.3)
	await shot("puzzle_watch", 0.4)
	var sc: Control = cur()
	await wait(3.6)
	var tries := 0
	while not sc.accepting and tries < 100:
		tries += 1
		await wait(0.1)
	expect(sc.accepting, "puzzle reaches input phase")
	await shot("puzzle_input", 0.1)
	for s in pz["sequence"]:
		sc._press(int(s))
		await wait(0.3)
	expect(sc.done and sc.puzzle.success, "puzzle solved through UI")
	await shot("puzzle_solved", 0.3)
	# map after progress
	r.stage["step"] = 3
	Game.start_explore()
	await shot("explore_mid_stage", 0.9)


## Secret cave (crack -> rock-fall -> glow -> cave), item reward + inventory, nutrition eat choice, evolution branches.
func _systems_demo() -> void:
	var r: RunState = Game.run
	r.stage["weather"] = "clear"
	r.stage["step"] = 1
	r.hp = r.max_hp()
	r.hunger = 70
	r.add_item("venom_gland")
	r.add_item("gut_flora")
	r.stage_def()["secret"]["chance"] = 1.0
	var room := _find_room("battle").duplicate(true)
	room["unspotted_allowed"] = false
	room["enemies"] = ["beetle", "beetle"]
	room["infected"] = [false, false]
	r.enter_room(room)
	Game.battle = Battle.create(r, room, "spotted")
	Game.battle.begin()
	Game.goto("battle", {"room": room})
	await wait(1.0)
	for i in 6:
		hint_dismiss()
	var bs: Control = cur()
	fast(bs)
	while bs.busy:
		await wait(0.1)
	expect(Game.battle.secret != Vector2i(-1, -1), "tour: a secret cave tile was rolled")
	await shot("battle_secret_crack", 0.4)
	print("TOUR dbg before play: phase=", Game.battle.phase, " busy=", bs.busy, " alive=", Game.battle.alive_enemies().size())
	await play_battle()
	print("TOUR dbg after play: screen=", cur().name, " phase=", Game.battle.phase, " alive=", Game.battle.alive_enemies().size())
	await wait(1.4)
	if cur().name == "reward":
		await shot("reward_eat_choice", 0.5)
		await finish_reward("battle")
	await drive(func(): return cur().name == "battle" and Game.battle.phase == "explore", 8)
	await wait(2.2)
	await shot("explore_secret_open", 0.3)
	var sec := Game.battle.secret
	if sec != Vector2i(-1, -1) and cur().name == "battle":
		cur()._on_tile_hovered(sec)
		await shot("explore_secret_hover", 0.2)
		cur()._take_secret()
		await wait(1.4)
		await drive(func(): return cur().name == "battle" and Game.battle.mode != "explore" and String(Game.battle.room.get("type", "")) == "cave", 4)
		await once("cave_battle_start", 0.5)
		await play_battle()
		await wait(1.4)
		await drive(func(): return cur().name == "battle" and Game.battle.phase == "explore", 12)
		await shot("explore_after_cave", 0.8)
	# item choice of three (boss style), HUD inventory with a tooltip
	var offers := r.offer_items("boss")
	Game.goto("item", {"source": "boss", "offers": offers, "queue": []})
	await shot("item_boss_choice", 0.5)
	cur()._take(offers[0])
	await wait(0.5)
	# evolution branches: one unlocked, the rest locked with their requirements
	r.add_nutrition({"protein": 9})
	r.pending_evolution_tier = 2
	Game.goto("branch", {"queue": []})
	await shot("branch_choice_locked", 0.5)
	r.pending_evolution_tier = 0
	Game.start_explore()
	await wait(0.8)
	await shot("explore_with_items", 0.3)

func _elite_and_evolution() -> void:
	var r: RunState = Game.run
	r.stage["weather"] = "fog"
	r.hp = r.max_hp()
	var room := _find_room("elite").duplicate(true)
	room["infected"] = [true]
	room["unspotted_allowed"] = false
	room["trap"] = true
	r.enter_room(room)
	Game.enter_battle(room)
	await shot("arrive_elite_infected_spotted", 1.0)
	await wait(1.0)
	hint_dismiss()
	await shot("battle_elite_start", 0.4)
	await play_battle()
	await wait(1.2)
	if cur().name == "reward":
		# force evolution for the screenshot
		r.level = 2
		r.xp = 23
		var res: Dictionary = Game.battle_result
		res["xp"] = 30
		Game.goto("reward", {"room": room})
		await shot("reward_evolution", 0.6)
		await finish_reward("elite")
		await drive(func(): return cur().name == "battle" and Game.battle.phase == "explore", 14)

## One frozen frame per beat of every cutscene shot (names: cutscene_<shot>_<n>), then the skip button.
func _cutscene_tour() -> void:
	var cs: Control = cur()
	var tl: Dictionary = cs.view.tl
	var frames := {"egg": [0.7, 2.6, 4.4, 6.6], "mother": [1.4, 4.4, 5.9, 7.6], "meteor": [0.9, 2.5, 3.3, 5.6],
		"emerge": [1.2, 3.6, 5.5, 7.8], "fight": [1.8, 3.6, 4.5, 6.5, 8.0], "flee": [0.9, 2.8, 4.2, 6.1]}
	expect(String(cs.skip_btn.text) == "Skip" and cs.skip_btn.visible, "the cutscene has a Skip button")
	for i in tl["shots"].size():
		var sh: Dictionary = tl["shots"][i]
		var t0 := CutsceneView.shot_start(tl, i)
		var n := 1
		for lt in frames.get(String(sh["id"]), [1.0]):
			cs.show_at(t0 + float(lt))
			await shot("cutscene_%d_%s_%d" % [i + 1, String(sh["id"]), n], 0.25)
			n += 1
	cs.skip(true)
	await wait(0.5)

func _stage2_and_boss() -> void:
	var r: RunState = Game.run
	r.game_over = false
	r.hp = r.max_hp()
	r.level = 5
	r.xp = 70
	r.advance_stage()
	Game.goto("stage_intro")
	await wait(0.4)
	cur().set_process(false)
	cur().sky.animate = false
	cur()._apply(4.5)
	await shot("stage2_intro", 0.4)
	cur().skip()
	await wait(0.4)
	await shot("stage2_explore", 0.9)
	# boss with drones
	var boss := _find_room("boss")
	r.enter_room(boss)
	Game.enter_battle(boss)
	await shot("arrive_boss_spotted", 1.0)
	await wait(1.0)
	await shot("battle_boss_start", 0.4)
	# play a few turns then screenshot
	var s: Control = cur()
	fast(s)
	var b: Battle = Game.battle
	var turns := 0
	while b.phase == "player" and turns < 3:
		turns += 1
		var guard := 0
		while b.phase == "player" and guard < 30:
			guard += 1
			await wait(0.03)
			if s.busy:
				continue
			var a := AutoPlayer.next_action(b, rng)
			if a["type"] == "end":
				break
			if a["type"] == "card":
				var c := b.card_at(a["i"])
				s._select_card(a["i"])
				if c["target"] in ["enemy", "tile"]:
					await wait(0.02)
					s._on_tile_clicked(a["target"].pos if a["target"] is BUnit else a["target"], MOUSE_BUTTON_LEFT)
			else:
				s.move_mode = true
				s._on_tile_clicked(a["pos"], MOUSE_BUTTON_LEFT)
		while s.busy:
			await wait(0.05)
		s._on_end_pressed()
		await wait(0.2)
		while s.busy:
			await wait(0.05)
	await shot("battle_boss_midfight", 0.4)
