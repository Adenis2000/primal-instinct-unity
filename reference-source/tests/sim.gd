extends SceneTree
## Balance sim. godot --headless --script res://tests/sim.gd -- seeds=60 smart=1 archetype=bleed eat=fit difficulty=normal start=0
func _initialize() -> void:
	await process_frame
	var game = root.get_node("Game")
	game.persist_enabled = false
	DB.load_all()
	var a := {"seeds": "60", "smart": "1", "archetype": "", "eat": "fit", "difficulty": "", "start": "0"}
	for s in OS.get_cmdline_user_args():
		var kv := s.split("=")
		if kv.size() == 2:
			a[kv[0]] = kv[1]
	var n := int(a["seeds"])
	var wins := 0
	var rooms := 0
	var stage2 := 0
	var causes := {}
	var dq := {}
	var forms := {}
	var deaths := {}
	var s1_deaths := 0
	var branches := 0
	var room_hist := {}
	for i in n:
		var o := {"smart": a["smart"] == "1"}
		if a["archetype"] != "":
			o["archetype"] = a["archetype"]
		if a["difficulty"] != "":
			o["difficulty"] = a["difficulty"]
		var r := RunSimulator.simulate(int(a["start"]) + i + 1, false, a["eat"], o)
		if r["victory"]:
			wins += 1
		rooms += int(r["rooms"])
		branches += int(r["branches"])
		if int(r["max_stage"]) >= 2:
			stage2 += 1
		if r.has("timeout_room"):
			print("  timeout in ", r["timeout_room"], " seed ", i + 1)
		if not r["victory"]:
			room_hist[int(r["rooms"])] = int(room_hist.get(int(r["rooms"]), 0)) + 1
			if int(r["max_stage"]) < 2:
				s1_deaths += 1
		if r.has("died_in"):
			deaths[r["died_in"]] = int(deaths.get(r["died_in"], 0)) + 1
		var c := String(r["cause"]) if not r["victory"] else "victory"
		causes[c] = int(causes.get(c, 0)) + 1
		dq[r["diet_quality"]] = int(dq.get(r["diet_quality"], 0)) + 1
		forms[r["form"]] = int(forms.get(r["form"], 0)) + 1
	var dl := []
	for k in deaths:
		dl.append([deaths[k], k])
	dl.sort_custom(func(x, y): return x[0] > y[0])
	print("DEATHS ", dl.slice(0, 12))
	var keys := room_hist.keys()
	keys.sort()
	var hs := []
	for k in keys:
		hs.append("%d:%d" % [k, room_hist[k]])
	print("PER-STAGE: stage 1 cleared by %d%% (died in stage 1: %d%%); stage 2 reached by %d%%, of those %d%% win; deaths by rooms played [rooms:count] %s" % [
		int(100.0 * (n - s1_deaths) / n), int(100.0 * s1_deaths / n), int(100.0 * stage2 / n), int(100.0 * wins / maxi(1, stage2)), " ".join(hs)])
	print("BRANCHES per run: ", snappedf(float(branches) / n, 0.01))
	print("SIM ", a, " wins=", wins, "/", n, " (", snappedf(100.0 * wins / n, 0.1), "%) avg_rooms=", snappedf(float(rooms) / n, 0.1), " reached_stage2=", stage2, " causes=", causes, " diet=", dq, " forms=", forms)
	quit()
