extends Node
## Visual check of arenas / themes / window sizes (not part of the test-suite). Run with a display:
##   godot --path . --rendering-driver opengl3 -- --gallery --out=/tmp/gal [--sizes=1280x720,2560x1600] [--cases=jungle_battle,boss,cave,tundra]
## Saves one PNG per (case, size) at the window's native pixels.

var main: Control

func wait(t: float) -> void:
	await get_tree().create_timer(t).timeout

func cut_done_marker() -> void:
	pass

func run(main_: Control, args: PackedStringArray) -> void:
	main = main_
	var out := "/tmp/gal"
	var sizes := ["1280x720", "1920x1080", "2560x1600", "3840x2160"]
	var cases := ["jungle_battle", "elite", "boss", "cave", "tundra", "ambush_small"]
	var seed_in := 7
	var pp := true                     # --pp=0 turns Pixel Perfect off
	for a in args:
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--sizes="):
			sizes = a.substr(8).split(",")
		elif a.begins_with("--cases="):
			cases = a.substr(8).split(",")
		elif a.begins_with("--seed="):
			seed_in = int(a.substr(7))
		elif a.begins_with("--pp="):
			pp = a.substr(5) != "0"
	DirAccess.make_dir_recursive_absolute(out)
	Settings.persist = false
	Settings.pixel_perfect = pp
	main.apply_settings()
	Game.persist_enabled = false
	Game.load_save()
	for cs in cases:
		for oc in main.overlay_layer.get_children():
			oc.queue_free()          # no overlay (Settings / Deck) leaks from the previous case into this shot
		await get_tree().process_frame
		var run_: RunState = Game.start_run("velociraptor", seed_in)
		if String(cs) in ["egg", "draft", "item", "intro", "customize", "customize_default", "settings", "cutscene", "menu", "deck", "gameover", "branch", "event", "puzzle", "bd_tundra", "bd_cave", "bd_jungle"] or String(cs).begins_with("seq_"):
			match String(cs):
				"egg":
					Game.run = null
					Game.goto("egg")
				"bd_tundra", "bd_cave", "bd_jungle":
					run_.stage["theme"] = String(cs).substr(3)
					run_.deck.append_array(["rake", "open_vein", "gore"])
					Game.goto("draft", {"mode": "elite", "queue": []})
				"seq_clear", "seq_fog", "seq_rain", "seq_storm", "seq_heat", "seq_cold":
					# stage-intro cinematic frames: --cases=seq_rain  (frames at fixed times; sizes[0] is used)
					run_.stage["weather"] = String(cs).substr(4)
					var p0 := String(sizes[0]).split("x")
					get_window().size = Vector2i(int(p0[0]), int(p0[1]))
					Game.goto("stage_intro")
					await wait(0.5)
					var intro: Control = main.current
					intro.set_process(false)
					intro.sky.animate = false
					var fi := 0
					for tt in [0.5, 3.4, 5.6, 6.9, 7.7, 8.4]:
						intro._apply(tt)
						intro.sky.time = tt * 1.0
						await wait(0.25)
						await RenderingServer.frame_post_draw
						ShotUtil.save(get_viewport(), "%s/%s_%s_f%d.png" % [out, cs, sizes[0], fi], get_window().size)
						print("GALLERY frame ", cs, " t=", tt)
						fi += 1
					intro.skip()
				"menu":
					Game.run = null
					Game.goto("menu")
				"cutscene":
					# intro story cutscene, one frame per beat at every size:  --cases=cutscene --sizes=1280x720,3840x2160
					Settings.intro_mode = 0
					for sz in sizes:
						var p3 := String(sz).split("x")
						get_window().size = Vector2i(int(p3[0]), int(p3[1]))
						Game.goto("intro_cutscene")
						await wait(0.8)
						var cut: Control = main.current
						var fj := 0
						for tt in [0.8, 4.4, 6.6, 11.0, 14.2, 18.7, 19.6, 20.6, 22.8, 26.5, 30.0, 34.5, 36.9, 38.8, 43.0]:
							cut.show_at(float(tt))
							await wait(0.2)
							await RenderingServer.frame_post_draw
							ShotUtil.save(get_viewport(), "%s/cutscene_%s_f%02d.png" % [out, sz, fj], get_window().size)
							fj += 1
						print("GALLERY cutscene frames at ", sz, " viewport=", get_viewport().get_visible_rect().size)
					cut_done_marker()
				"deck":
					run_.deck.append_array(["rake", "open_vein", "gore", "pounce", "crouch"])
					Game.goto("draft", {"mode": "elite", "queue": []})
					await wait(0.4)
					main.open_deck_overlay()
				"gameover":
					Game.goto("gameover")
				"branch":
					run_.pending_evolution_tier = 2
					Game.goto("branch", {"queue": []})
				"event", "puzzle":
					var rm := {}
					for st in run_.stage["steps"]:
						for dr in st["doors"]:
							if dr["type"] == String(cs) and rm.is_empty():
								rm = dr
					if rm.is_empty():
						rm = run_.choose_door(0)
					Game.goto(String(cs), {"room": rm})
				"draft":
					run_.deck.append_array(["rake", "open_vein", "gore"])
					Game.goto("draft", {"mode": "elite", "queue": []})
				"intro":
					Game.goto("stage_intro")
				"settings":
					Game.run = null
					Game.goto("egg")
					await wait(0.8)
					main.open_settings()
				"customize", "customize_default":
					Game.goto("customize", {"species": "velociraptor", "seed": 7})
					await wait(3.0)
					if String(cs) == "customize":
						for kv in [["skin", "azure"], ["pattern", "stripes"], ["pcolor", "gold"], ["gender", "female"]]:
							main.current.pick(kv[0], kv[1])
				"item":
					Game.goto("item", {"source": "boss", "offers": run_.offer_items("boss"), "queue": []})
			await wait(0.8)
			Hints.clear()
			for sz in sizes:
				var p2 := String(sz).split("x")
				get_window().size = Vector2i(int(p2[0]), int(p2[1]))
				await wait(0.6)
				Hints.clear()
				await RenderingServer.frame_post_draw
				ShotUtil.save(get_viewport(), "%s/%s_%s.png" % [out, cs, sz], get_window().size)
				print("GALLERY ", "%s/%s_%s.png" % [out, cs, sz], " viewport=", get_viewport().get_visible_rect().size, " window=", get_window().size)
			continue
		var room := _room_for(run_, String(cs))
		var mode := "ambush" if String(cs).begins_with("ambush") else "spotted"
		run_.enter_room(room)
		Game.battle = Battle.create(run_, room, mode)
		Game.battle.begin()
		Game.goto("battle", {"room": room})
		await wait(0.8)
		var s: Control = main.current
		if "speed" in s:
			s.speed = 20.0
		if String(cs).begins_with("victory"):
			for e in Game.battle.enemies:
				e.alive = false
				Game.battle.killed.append({"id": e.id, "infected": false, "xp": int(e.def.get("xp", 0)), "food": int(e.def.get("food", 0))})
			Game.battle.phase = "won"
			Game.battle_result = Game.battle.result()
			Game.goto("reward", {"room": room})
			await wait(0.8)
			if String(cs) == "victory_draft":
				Game.goto("draft", {"mode": "elite", "queue": []})
				await wait(0.5)
			elif String(cs) == "victory_item":
				Game.goto("item", {"source": "boss", "offers": run_.offer_items("boss"), "queue": []})
				await wait(0.5)
			elif String(cs) == "victory_branch":
				run_.add_nutrition({"protein": 9})
				run_.pending_evolution_tier = 2
				run_.level = 3
				Game.goto("branch", {"queue": []})
				await wait(0.5)
		Hints.clear()
		for sz in sizes:
			var p := String(sz).split("x")
			get_window().size = Vector2i(int(p[0]), int(p[1]))
			await wait(0.6)
			Hints.clear()
			await RenderingServer.frame_post_draw
			var path := "%s/%s_%s.png" % [out, cs, sz]
			ShotUtil.save(get_viewport(), path, get_window().size)
			var sp: Dictionary = Game.battle.arena_spec
			print("GALLERY ", path, " viewport=", get_viewport().get_visible_rect().size, " arena=", sp.get("w"), "x", sp.get("h"), " shape=", sp.get("shape"), " zoom=", Iso.zoom, " window=", get_window().size, " scale=", get_window().content_scale_factor, " mode=", get_window().content_scale_mode, " aspect=", get_window().content_scale_aspect, " sm=", get_window().content_scale_stretch)
	get_tree().quit(0)

func _room_for(r: RunState, cs: String) -> Dictionary:
	match cs:
		"boss":
			r.stage["step"] = r.stage["steps"].size() - 1
			return r.choose_door(0)
		"elite":
			for i in r.stage["steps"].size():
				for d in r.stage["steps"][i]["doors"]:
					if d["type"] == "elite":
						r.stage["step"] = i
						return d
		"cave":
			return StageGen.make_cave_room(r)
		"tundra":
			r.advance_stage()
			r.stage["step"] = 1
			for d in r.stage["steps"][1]["doors"]:
				if d["type"] in ["battle", "elite"]:
					return d
			return r.choose_door(0)
	r.stage["step"] = 1
	for d in r.stage["steps"][1]["doors"]:
		if d["type"] == "battle":
			return d
	return r.choose_door(0)
