extends SceneTree
## Debug: one fight with the smart bot, printing the log. godot --headless --script res://tests/dbg.gd -- enemy=husk_queen level=5 stage=0 seed=1
func _initialize() -> void:
	await process_frame
	root.get_node("Game").persist_enabled = false
	DB.load_all()
	var a := {"enemy": "husk_queen", "level": "5", "stage": "0", "seed": "1", "smart": "1", "mode": "spotted", "step": "5"}
	for s in OS.get_cmdline_user_args():
		var kv := s.split("=")
		if kv.size() == 2:
			a[kv[0]] = kv[1]
	var run := RunState.create("velociraptor", int(a["seed"]))
	run.begin_stage(int(a["stage"]))
	run.level = int(a["level"])
	run.hp = run.max_hp()
	for i in 8:
		run.deck.append(["claw_slash", "skitter", "pounce", "nip"][i % 4])
	var room := {"type": "boss" if "queen" in a["enemy"] or "mammoth" in a["enemy"] else "elite", "step": int(a["step"]), "seed": int(a["seed"]) * 13, "enemies": a["enemy"].split(","), "infected": [false], "stage": "stage_1"}
	var b := Battle.create(run, room, a["mode"])
	b.begin()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var turns := 0
	while b.phase != "won" and b.phase != "lost" and turns < 40:
		b.drain_events()
		if b.phase == "ambush":
			b.skip_ambush()
			continue
		if b.phase != "player":
			break
		turns += 1
		var hpl := []
		for e in b.alive_enemies():
			hpl.append("%s %d/%d@%s %s" % [e.id, e.hp, e.max_hp, str(e.pos), e.state])
		print("T", b.turn_no, " me ", b.player.hp, "/", b.player.max_hp, " @", b.player.pos, " hand=", b.hand, " | ", hpl)
		for k in 25:
			var act := AutoPlayer.smart_action(b, rng)
			if act["type"] == "card":
				print("   card ", b.hand[act["i"]], " -> ", act["target"].id if act["target"] is BUnit else act["target"])
				b.play_card(act["i"], act["target"])
			elif act["type"] == "move":
				print("   move ", act["pos"])
				b.move_player(act["pos"])
			else:
				break
			if b.phase != "player":
				break
		b.end_player_turn()
		for l in b.log.slice(-6) if "log" in b else []:
			print("     ", l)
	print("RESULT ", b.phase, " turns=", turns)
	quit()
