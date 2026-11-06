class_name AutoPlayer
extends RefCounted
## Simple heuristic bot used by the headless tests (and handy for balance sims).

static func play(b: Battle, rng: RandomNumberGenerator, ambush_pref: float = 0.8, max_turns: int = 60, smart: bool = false) -> Dictionary:
	var guard := 0
	var timeout := false
	while guard < 3000:
		guard += 1
		b.drain_events()
		if b.phase == "ambush":
			var t := b.ambush_targets()
			if not t.is_empty() and rng.randf() < ambush_pref:
				b.ambush_strike(pick_ambush_target(b, t) if smart else t[rng.randi() % t.size()])
			else:
				b.skip_ambush()
		elif b.phase == "player":
			if b.turn_no > max_turns:
				timeout = true
				break
			if OS.get_environment("BOTDBG") != "" and b.turn_no > 50:
				var hpl := []
				for e in b.alive_enemies():
					hpl.append("%s %d/%d@%s %s w=%s st=%s" % [e.id, e.hp, e.max_hp, str(e.pos), e.state, str(not e.windup.is_empty()), str(e.status)])
				print("T", b.turn_no, " me ", b.player.hp, "/", b.player.max_hp, " @", b.player.pos, " st=", b.player.status, " stam=", b.stamina, " hand=", b.hand, " | ", hpl)
			_turn(b, rng, smart)
			b.end_player_turn()
		else:
			break
	b.drain_events()
	return {"phase": b.phase, "turns": b.turn_no, "timeout": timeout}

static func _turn(b: Battle, rng: RandomNumberGenerator, smart: bool = false) -> void:
	for step in 25:
		if b.phase != "player":
			return
		var a := next_action(b, rng, smart) if not smart else smart_action(b, rng)
		match a["type"]:
			"card":
				b.play_card(a["i"], a["target"])
			"move":
				if not b.move_player(a["pos"]):
					return
			_:
				return

## One decision for the current player turn: {"type": "card"|"move"|"end", ...}.
## Also used by the screenshot tour to drive the real UI.
static func next_action(b: Battle, rng: RandomNumberGenerator, smart: bool = false) -> Dictionary:
	var best_i := -1
	var best_score := -1.0
	var best_target = null
	for i in b.hand.size():
		if not b.card_playable(i):
			continue
		var c := b.card_at(i)
		var score := 0.0
		var target = null
		match String(c["type"]):
			"attack":
				score = 10.0 + rng.randf() * 3.0
				var ts := b.card_targets(i)
				if ts.is_empty():
					continue
				ts.sort_custom(func(x, y): return x.hp < y.hp)
				target = ts[0]
			"skill":
				score = 4.0 + rng.randf()
				if String(c["target"]) == "tile":
					var ts2 := b.card_targets(i)
					if ts2.is_empty() or b.is_hidden():
						continue
					target = ts2[rng.randi() % ts2.size()]
				elif b.player.hp < b.player.max_hp * 0.5:
					score += 2.0
			"power":
				score = 7.0
		if score > best_score:
			best_score = score
			best_i = i
			best_target = target
	if best_i >= 0:
		return {"type": "card", "i": best_i, "target": best_target}
	if b.mp > 0 and not b.alive_enemies().is_empty():
		var reach := b.reachable_tiles()
		var best_p: Vector2i = b.player.pos
		var best_d := _min_dist(b, b.player.pos)
		for p in reach:
			var d := _min_dist(b, p)
			if d < best_d:
				best_d = d
				best_p = p
		if best_p != b.player.pos:
			return {"type": "move", "pos": best_p}
	return {"type": "end"}

static func _min_dist(b: Battle, p: Vector2i) -> int:
	var m := 99
	for e in b.alive_enemies():
		m = mini(m, BGrid.dist(p, e.pos))
	return m


# ====================================================================== COMPETENT BOT
## "Smart" bot = a competent human proxy: dodges telegraphed attacks, positions for flanks/grass, keeps cheap cards for
## kills, retreats when hurt, uses synergy cards (mark, bleed payoffs...), picks cards/items/doors with a plan.
## It is intentionally NOT perfect: no lookahead search, no deck counting.

static func pick_ambush_target(b: Battle, ts: Array) -> BUnit:
	var best: BUnit = ts[0]
	var best_s := -999.0
	for e in ts:
		var s: float = float(e.def.get("xp", 1)) * 0.5 - float(e.hp) * 0.2
		if "ranged" in e.tags or e.def.get("behavior", "") == "kiter":
			s += 4.0
		if e.def.get("behavior", "") == "pack":
			s += 2.0
		if e.is_boss():
			s -= 5.0
		if s > best_s:
			best_s = s
			best = e
	return best

static func in_danger(b: Battle, p: Vector2i) -> bool:
	for e in b.alive_enemies():
		if not e.windup.is_empty() and e.windup_tiles.has(p):
			return true
	return false

## Rough expected damage of card `i` on `tgt` from where the player will stand.
static func est_damage(b: Battle, i: int, tgt: BUnit) -> float:
	var c := b.card_at(i)
	var total := 0.0
	var pv := b.preview_attack(i, tgt) if String(c["target"]) == "enemy" else {"mult": 1.0, "dir": "front"}
	for e in c["effects"]:
		match String(e["op"]):
			"damage":
				var base := float(e.get("amount", 0))
				if not tgt.aware:
					base += float(e.get("unaware_bonus", 0)) + 2.0
				base += float(e.get("per_bleed", 0)) * tgt.st("bleed")
				if String(pv["dir"]) != "front":
					base += float(e.get("flank_bonus", 0))
				if tgt.st("bleed") > 0:
					base += float(e.get("bleed_bonus", 0))
				base += float(e.get("per_momentum", 0)) * minf(float(b.moved_tiles), float(e.get("momentum_max", 6)))
				base += float(e.get("per_diet", 0)) * b.run.diet_tier()
				if tgt.st("mark") > 0:
					base += 3.0
				base *= float(pv["mult"])
				if String(pv["dir"]) == "front" and tgt.armor > 0 and tgt.st("expose") == 0:
					base -= tgt.armor
				total += maxf(0.0, base)
			"damage_adjacent":
				total += float(e.get("amount", 0))
	return total

static func _wants_skill(b: Battle, c: Dictionary, rng: RandomNumberGenerator) -> float:
	var hp_frac := float(b.player.hp) / float(b.player.max_hp)
	var threatened := false
	var near := 0
	for e in b.alive_enemies():
		if e.aware and BGrid.dist(e.pos, b.player.pos) <= e.move + 1:
			threatened = true
		if BGrid.dist(e.pos, b.player.pos) <= 1:
			near += 1
	var sc := 0.0
	for op in c["effects"]:
		match String(op["op"]):
			"block":
				sc += (5.0 if threatened else 0.5) + (2.0 if hp_frac < 0.6 else 0.0)
			"heal":
				sc += 6.0 if hp_frac < 0.6 else 0.0
			"heal_per_bleeding":
				sc += 4.0 if hp_frac < 0.8 else 0.0
			"draw", "draw_if_bleeding", "draw_diet":
				sc += 3.5 if b.hand.size() < 5 else 1.0
			"gain_stamina":
				sc += 2.0
			"gain_mp":
				sc += 3.0 if b.alive_enemies().size() > 0 else 0.0
			"mark":
				sc += 5.0
			"hide":
				sc += 6.0 if (b.grid.is_grass(b.player.pos) and not b.is_hidden() and near == 0) else -9.0
			"daze", "fear":
				sc += 4.0 if near > 0 else 0.0
			"evade":
				sc += 3.0 if threatened else 0.0
			"hunger":
				sc += 4.0 if b.run.hunger < 55 else 0.5
			"stalker", "calm":
				sc += 3.0 if b.is_hidden() else 0.5
			"speed_buff", "extra_turn":
				sc += 4.0
			"retreat":
				sc += 5.0 if (hp_frac < 0.5 and near > 0) else -3.0
			"dash":
				sc += 0.0
	return sc

static func smart_action(b: Battle, rng: RandomNumberGenerator) -> Dictionary:
	var p := b.player
	var hp_frac := float(p.hp) / float(p.max_hp)
	# 1) telegraphed attack aimed at our tile: leave it first
	if in_danger(b, p.pos) and b.mp > 0:
		var best_p := p.pos
		var best_s := -999.0
		for t in b.reachable_tiles():
			if in_danger(b, t):
				continue
			var s := -float(_min_dist(b, t)) * 0.5 + (2.0 if b.grid.is_grass(t) else 0.0) - float(int(b.reachable_tiles()[t]))
			if s > best_s:
				best_s = s
				best_p = t
		if best_p != p.pos:
			return {"type": "move", "pos": best_p}
	# 2) emergency: use an active item
	for id in b.run.items:
		if b.item_usable(id) and hp_frac < 0.45:
			b.use_item(id)
	# 3) score every playable card
	var best_i := -1
	var best_score := 0.0
	var best_target = null
	for i in b.hand.size():
		if not b.card_playable(i):
			continue
		var c := b.card_at(i)
		var cost := maxi(1, int(c["cost"]))
		var score := 0.0
		var target = null
		match String(c["type"]):
			"attack":
				var ts := b.card_targets(i)
				if String(c["target"]) == "enemy" and ts.is_empty():
					continue
				if String(c["target"]) == "self":
					var d := est_damage(b, i, b.alive_enemies()[0]) * float(b.alive_enemies().filter(func(e): return BGrid.dist(e.pos, p.pos) <= 1).size())
					score = d / float(cost) + 1.0
				else:
					var bs := -999.0
					for e in ts:
						var dmg := est_damage(b, i, e)
						var s := dmg
						if dmg >= e.hp:
							s += 8.0 + float(e.def.get("xp", 1)) * 0.3
						if "ranged" in e.tags or e.def.get("behavior", "") == "kiter":
							s += 2.0
						s += (float(e.max_hp - e.hp) / float(e.max_hp)) * 3.0
						if not e.windup.is_empty():
							s += 2.0
						if s > bs:
							bs = s
							target = e
					score = bs / (0.6 + 0.4 * float(cost)) + 1.0
					# fragile when about to die: prefer defence unless this kills
					if hp_frac < 0.3 and est_damage(b, i, target) < target.hp:
						score -= 3.0
			"skill":
				score = _wants_skill(b, c, rng)
				if String(c["target"]) == "tile":
					var ts2 := b.card_targets(i)
					if ts2.is_empty():
						continue
					# tile skills (Grass Dive...): only to reach grass or escape when hurt
					var bt: Vector2i = ts2[0]
					var bsc := -999.0
					for t in ts2:
						var s2 := (4.0 if b.grid.is_grass(t) else 0.0) + float(_min_dist(b, t)) * (0.5 if hp_frac < 0.5 else -0.2)
						if in_danger(b, t):
							s2 -= 9.0
						if s2 > bsc:
							bsc = s2
							bt = t
					target = bt
					score = bsc if bsc > 2.0 else -1.0
				elif String(c["target"]) == "enemy":
					var ts3 := b.card_targets(i)
					if ts3.is_empty():
						continue
					ts3.sort_custom(func(x, y): return x.hp > y.hp)
					target = ts3[0]
				score /= (0.7 + 0.3 * float(cost))
			"power":
				score = 7.5 - float(b.turn_no) * 0.2
		if score > best_score:
			best_score = score
			best_i = i
			best_target = target
	if best_i >= 0 and best_score > 0.5:
		return {"type": "card", "i": best_i, "target": best_target}
	# 4) reposition
	if b.mp > 0 and not b.alive_enemies().is_empty():
		var reach := b.reachable_tiles()
		var foes := b.alive_enemies()
		var have_attack := false
		for i in b.hand.size():
			if String(b.card_at(i)["type"]) == "attack" and b.card_cost(i) <= b.stamina:
				have_attack = true
		var hurt := hp_frac < 0.35 and not b.is_hidden() and b.turn_no < 25
		var best_t: Vector2i = p.pos
		var best_v := _tile_value(b, p.pos, foes, hurt, have_attack, 0)
		for t in reach:
			var v := _tile_value(b, t, foes, hurt, have_attack, int(reach[t]))
			if v > best_v + 0.01:
				best_v = v
				best_t = t
		if best_t == p.pos and have_attack and not hurt:
			# walled in (water / rocks): fall back to real path distance towards the nearest foe
			var foe: BUnit = foes[0]
			for e in foes:
				if BGrid.dist(e.pos, p.pos) < BGrid.dist(foe.pos, p.pos):
					foe = e
			var field: Dictionary = b.grid.reach(foe.pos, 99, {})["cost"]
			var cur_c: int = int(field.get(p.pos, 99))
			for t in reach:
				if int(field.get(t, 99)) < cur_c - 0 and int(field.get(t, 99)) < int(field.get(best_t, 99)):
					best_t = t
		if best_t != p.pos:
			return {"type": "move", "pos": best_t}
	return {"type": "end"}

static func _tile_value(b: Battle, t: Vector2i, foes: Array, hurt: bool, have_attack: bool, cost: int) -> float:
	var v := 0.0
	if in_danger(b, t):
		v -= 30.0
	var nearest := 99
	var adj := 0
	var threat := 0.0
	for e in foes:
		var d := BGrid.dist(t, e.pos)
		nearest = mini(nearest, d)
		if d <= 1:
			adj += 1
		if e.aware and d <= e.move + int(e.abilities.size() > 0 and int(e.abilities[0].get("range", 1)) > 1) * 3 + 1:
			threat += 1.0
		# flank value: standing behind/beside an enemy we are about to attack
		if d <= 2 and have_attack:
			match b.facing_dir(t, e):
				"back":
					v += 3.0
				"side":
					v += 1.5
	if hurt:
		v += float(nearest) * 1.5 - float(adj) * 4.0
		if b.grid.is_grass(t):
			v += 4.0
	else:
		if have_attack:
			# stand where we can hit next turn but not be swarmed
			v -= float(maxi(0, nearest - 1)) * 1.2
			v -= float(maxi(0, adj - 1)) * 3.0
		else:
			v += float(nearest) * 0.8
	if have_attack and not hurt and (b.turn_no > 12 or foes.all(func(e): return not e.aware)):
		v -= float(nearest) * (1.5 if b.turn_no > 12 else 0.8)   # never stall: close in on unaware foes
	if b.grid.is_grass(t):
		v += 1.2
	v -= float(cost) * 0.15
	v -= threat * 0.3
	return v

static func pick_door(run: RunState, doors: Array, rng: RandomNumberGenerator) -> int:
	var hp_frac := float(run.hp) / float(run.max_hp())
	var best := 0
	var best_s := -999.0
	for i in doors.size():
		var t := String(doors[i].get("type", "battle"))
		var s := rng.randf() * 0.5
		match t:
			"battle":
				s += 3.0 if hp_frac > 0.5 else 0.5
			"elite":
				s += 4.0 if (hp_frac > 0.75 and run.level >= 3) else -4.0
			"boss":
				s += 5.0
			"forage":
				s += 4.0 if run.hunger < 55 else 1.5
				s += 2.0 if hp_frac < 0.6 else 0.0
			"event":
				s += 2.0
			"puzzle":
				s += 2.0
		if run.hunger < 30 and t == "battle":
			s += 2.0   # corpses are food
		if s > best_s:
			best_s = s
			best = i
	return best

const _RAR := {"common": 1.0, "uncommon": 2.0, "rare": 3.0}

## Archetype leaning of the current build: tag -> count (cards 1, items 2).
static func build_tags(run: RunState) -> Dictionary:
	var d := {}
	for id in run.deck:
		for t in DB.card(String(id)).get("tags", []):
			d[t] = int(d.get(t, 0)) + 1
	for id in run.items:
		for t in DB.item(String(id)).get("tags", []):
			d[t] = int(d.get(t, 0)) + 2
	return d

static func card_value(c: Dictionary) -> float:
	var v := 0.0
	var cost := float(c["cost"])
	for e in c["effects"]:
		match String(e["op"]):
			"damage":
				v += float(e.get("amount", 0)) * 1.0 + float(e.get("flank_bonus", 0)) * 0.5 + float(e.get("per_bleed", 0)) * 1.5 + float(e.get("unaware_bonus", 0)) * 0.4
			"damage_adjacent":
				v += float(e.get("amount", 0)) * 1.5
			"bleed", "poison":
				v += float(e.get("amount", 0)) * 1.6
			"block":
				v += float(e.get("amount", 0)) * 0.7
			"draw", "draw_if_bleeding", "draw_diet":
				v += 3.0
			"mark", "daze", "fear", "stun":
				v += 3.5
			"gain_mp", "gain_stamina", "extra_turn":
				v += 3.0
			"heal":
				v += float(e.get("amount", 0)) * 0.6
			"stalker", "calm", "patient", "quicken", "well_fed":
				v += 4.0
			_:
				v += 1.0
	if String(c["type"]) == "power":
		v += 1.5
	return v / (0.7 + 0.5 * cost)

static func pick_card(run: RunState, offer: Array, opts: Dictionary, rng: RandomNumberGenerator) -> String:
	if not bool(opts.get("smart", false)) and String(opts.get("archetype", "")) == "":
		return String(offer[rng.randi() % offer.size()])
	var tags := build_tags(run)
	var arch := String(opts.get("archetype", ""))
	var lean := ""
	var lean_n := 0
	for t in tags:
		if int(tags[t]) > lean_n:
			lean_n = int(tags[t])
			lean = String(t)
	var best := String(offer[0])
	var best_s := -999.0
	for id in offer:
		var c: Dictionary = DB.card(String(id))
		var s := card_value(c)
		var ctags: Array = c.get("tags", [])
		for t in ctags:
			s += minf(float(tags.get(t, 0)), 6.0) * 0.45
			if arch != "" and t == arch:
				s += 4.0
		# do not hoard duplicates of weak cards
		var dup := 0
		for d in run.deck:
			if d == id:
				dup += 1
		s -= float(dup) * 1.5
		s -= 0.0 if run.deck.size() < 14 else float(run.deck.size() - 13) * 0.4
		s += rng.randf() * 0.5
		if s > best_s:
			best_s = s
			best = String(id)
	return best

static func pick_item(run: RunState, offer: Array, opts: Dictionary, rng: RandomNumberGenerator) -> String:
	if not bool(opts.get("smart", false)) and String(opts.get("archetype", "")) == "":
		return String(offer[0])
	var tags := build_tags(run)
	var arch := String(opts.get("archetype", ""))
	var best := String(offer[0])
	var best_s := -999.0
	for id in offer:
		var d: Dictionary = DB.item(String(id))
		var s: float = float(_RAR.get(String(d.get("rarity", "common")), 1.0)) * 2.0
		for t in d.get("tags", []):
			s += minf(float(tags.get(t, 0)), 6.0) * 0.5
			if arch != "" and t == arch:
				s += 4.0
		s += rng.randf() * 0.5
		if s > best_s:
			best_s = s
			best = String(id)
	return best
