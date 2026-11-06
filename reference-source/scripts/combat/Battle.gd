class_name Battle
extends RefCounted
## Turn-based tactical card battle on a tile grid. Pure logic: the UI replays `events`.
##
## Design choices (see README):
##  * Turn order: turn meter. Each unit's meter fills by its speed; at METER it acts. A unit twice as
##    fast as another acts twice as often (extra turns happen naturally, cards can grant more).
##  * A player turn: stamina refills to max, movement points (MP) refill, hand is redrawn.
##  * Movement is FREE but limited by MP (tile move cost: water=2). Cards can add MP or move you.
##  * Stealth: each enemy is aware/unaware. Player is "hidden" when no enemy is aware.
const METER := 100.0
const NOISE_RADIUS := 3
const DIRS4 := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]   # SE, SW, NW, NE on screen
const SEARCH_SCAN_TURNS := 2   # turns an enemy spends looking around once it reaches the last seen spot
const TRACK_MULT := 1.5        # hunting enemies see (track) you out to 1.5x their normal sight range
const SCENT_RANGE := 8         # "scent" enemies never lose you inside this many tiles
const ROAM_RADIUS := 3         # idle enemies wander within this many tiles of their home
const ROAM_STEP := 2           # ...walking at most this many movement points per turn
const AMBUSH_RANGE := 24  # free first strike: you pounce from hiding on any enemy on the board

var run: RunState
var grid: BGrid
var rng := RandomNumberGenerator.new()
var evade_rng := RandomNumberGenerator.new()   # own seeded stream for tile evasion rolls (keeps layouts / AI rolls unchanged)
var last_dodged: bool = false
var arena_spec: Dictionary = {}                 # {w, h, shape, cut, corner, type} from ArenaGen (seeded per room)
var weather_id: String = ""
var room: Dictionary = {}
var mode: String = "spotted"          # spotted | ambush
var player: BUnit
var units: Array = []
var enemies: Array = []
var phase: String = "setup"           # ambush | player | enemy | won | lost
var turn_no: int = 0
var current: BUnit = null
var draw_pile: Array = []
var hand: Array = []
var discard_pile: Array = []
var exhausted: Array = []
var stamina: int = 0
var stamina_max: int = 0
var mp: int = 0
var mp_max: int = 0
var events: Array = []
var killed: Array = []                # [{id, infected, xp, food}]
var stalker: int = 0
var calm: bool = false
var calm_used: bool = false
var started_unspotted: bool = false
# ---- combat-depth state (reset every battle)
var moved_tiles: int = 0          # MOMENTUM: tiles you moved/leaped this turn (powers Rending Charge, Boots, Second Wind...)
var quicken: bool = false         # power: 0-cost cards grant +1 movement
var patient: bool = false         # power: hidden at turn start -> +1 stamina, +1 card
var well_fed_on: bool = false     # power: Good+ diet at turn start -> +1 stamina
var free_draw_used: bool = false  # Tempo Charm: first 0-cost card each turn draws
var evade_temp: int = 0           # % evasion from Blur until your next turn
const MARK_BONUS := 3             # damage added to your next hit on a Marked enemy (consumed)
const DAZE_DAMAGE := 0.5          # Dazed units deal half damage and move half as far
var _uid: int = 0

# ------------------------------------------------------------------ creation

static func create(run_: RunState, room_: Dictionary, mode_: String = "spotted") -> Battle:
	var b := Battle.new()
	b.run = run_
	b.room = room_
	b.mode = mode_
	b._setup()
	return b

func _setup() -> void:
	var sdef: Dictionary = run.stage_def()
	var terrain: Dictionary = sdef.get("terrain", {})
	if room.has("terrain"):
		terrain = room["terrain"]
	var theme: String = String(room.get("theme", run.stage.get("theme", "jungle")))
	theme_id = theme
	var rseed: int = int(room.get("seed", 1))
	arena_spec = ArenaGen.pick(rseed, room, mode, run.stage_idx)
	grid = BGrid.generate(RunState.mix(rseed, 31), terrain, theme, arena_spec)
	rng.seed = RunState.mix(rseed, 77)
	evade_rng.seed = RunState.mix(rseed, 505)
	weather_id = run.weather_id()
	started_unspotted = (mode == "ambush")

	# player
	_make_player()
	var starts := grid.free_tiles({}, 0, 1)
	if starts.is_empty():
		starts = grid.free_tiles({}, 0, grid.w / 2)
	player.pos = starts[rng.randi() % starts.size()]
	units.append(player)

	_place_fight_exits()
	_roll_secret(sdef)

	# enemies
	var occupied := {player.pos: player}
	if secret != Vector2i(-1, -1):
		occupied[secret] = null
	for ex in exits:
		occupied[ex["pos"]] = null
	var ids: Array = room.get("enemies", []).duplicate()
	var flags: Array = room.get("infected", []).duplicate()
	# difficulty: sometimes one more of the room's own kind joins (own seeded stream, never in tutorial rooms)
	if run != null and not ids.is_empty() and ids.size() < 4:
		var xr := RandomNumberGenerator.new()
		xr.seed = RunState.mix(rseed, 909)
		if xr.randf() < Difficulty.extra_chance(run, room):
			ids.append(ids[xr.randi() % ids.size()])
			flags.append(false)
	# only spawn where the player can actually walk to (sealed gates / rocks must not wall an enemy into a nook)
	var walkable: Dictionary = grid.reach(player.pos, 99, occupied)["cost"]
	for i in ids.size():
		var u := _make_enemy(String(ids[i]))
		var cands := grid.free_tiles(occupied, grid.w / 2, grid.w - 1).filter(func(p): return walkable.has(p))
		var far := cands.filter(func(p): return BGrid.dist(p, player.pos) >= 5)
		if far.is_empty():
			far = cands
		if far.is_empty():
			far = grid.free_tiles(occupied, 2, grid.w - 1, true).filter(func(p): return walkable.has(p))
		if far.is_empty():
			far = grid.free_tiles(occupied, 2, grid.w - 1, true)
		u.pos = far[rng.randi() % far.size()]
		u.home = u.pos
		occupied[u.pos] = u
		u.aware = (mode != "ambush")
		if i < flags.size() and bool(flags[i]) and not bool(u.def.get("infected", false)):
			infect_unit(u, true)
		units.append(u)
		enemies.append(u)
	# initial facing: enemies face a random direction (toward you if they already know you are here);
	# you start facing the nearest enemy. Persisted from then on (see README: Facing).
	for e in enemies:
		e.facing = DIRS4[rng.randi() % 4]
		if e.aware:
			e.facing = dir_toward(e.pos, player.pos, e.facing)
	if not enemies.is_empty():
		var nearest: BUnit = enemies[0]
		for e in enemies:
			if BGrid.dist(e.pos, player.pos) < BGrid.dist(nearest.pos, player.pos):
				nearest = e
		player.facing = dir_toward(player.pos, nearest.pos, player.facing)
	for u in units:
		u.vis_pos = Vector2(u.pos)
		u.vis_facing = u.facing
		u.vis_hp = u.hp

	# deck
	draw_pile = run.deck.duplicate()
	_shuffle(draw_pile)
	log_line("Weather: %s." % String(DB.weather(weather_id)["name"]) if weather_id != "" else "Battle begins.")
	if mode == "ambush":
		phase = "ambush"
		mp = eff_move(player)       # you may Move closer while unseen (enemies stay idle until they notice you / you strike)
		mp_max = mp
		log_line("They have not noticed you. Move closer and strike first - or slip away through an exit.")
	else:
		phase = "enemy"

## SECRET cave entrance: in some fought rooms (seeded, data/stages.json "secret".chance) a cracked tile hides a way into a
## spider cave. It is only a faint tile detail until the area is cleared (then a rock rolls away and it glows).
## Uses its own rng stream so existing seeded layouts do not shift.
## EXITS ARE PATHS OUTSIDE THE BOARD: 1-3 exits per room, each a corridor of negative space (no trees) through the surrounding tree
## line, leaving from an arena EDGE tile (the trigger tile: walk onto it to take the path; door 0 faces forward / up-screen).
## While enemies know about you the corridor is filled with trees like the rest of the border (exits_visible() == false); it opens
## when the area is cleared / sneaked past, and is already visible while nobody has noticed you (you may slip out).
static var pending_unlock: bool = false   # set when a room was sneaked past: the next explore field plays the gates-opening animation
var exits_locked: bool = false
var exits_unlock_anim: bool = false         # explore just started after a clear: play the gates-opening animation
var exits_step: int = -1                    # run step these exits lead into (the explore step)

func _place_fight_exits() -> void:
	exits = []
	exits_locked = false
	var t := String(room.get("type", ""))
	if t == "cave" or t == "explore" or t == "event" or bool(room.get("event_battle", false)):
		return
	var steps: Array = run.stage["steps"]
	var nxt := int(run.stage["step"]) + 1
	if nxt >= steps.size():
		return    # the stage ends with this room: no gates
	var doors: Array = steps[nxt]["doors"]
	var xr := RandomNumberGenerator.new()
	xr.seed = RunState.mix(int(room.get("seed", 1)), 1313)
	var places := ExitGen.place_exits(grid, doors.size(), xr, player.pos)
	for i in places.size():
		exits.append({"pos": places[i]["pos"], "side": places[i]["side"], "dir": places[i]["dir"], "door": i, "type": String(doors[i]["type"])})
	exits_locked = not exits.is_empty()
	exits_step = nxt

func _roll_secret(sdef: Dictionary) -> void:
	secret = Vector2i(-1, -1)
	secret_step = int(run.stage.get("step", 0))
	var sec: Dictionary = sdef.get("secret", {})
	var t := String(room.get("type", ""))
	if sec.is_empty() or (t != "battle" and t != "elite") or room.get("event_battle", false):
		return
	if secret_step >= run.stage["steps"].size() - 1:
		return
	var srng := RandomNumberGenerator.new()
	srng.seed = RunState.mix(int(room.get("seed", 1)), 909)
	if srng.randf() < float(sec.get("chance", 0.0)):
		secret = ExitGen.place_secret(grid, srng, player.pos, exits.map(func(e): return e["pos"]))

func _make_player() -> void:
	player = BUnit.new()
	player.uid = _next_uid()
	player.id = run.species_id
	player.display_name = String(run.species["name"])
	player.is_player = true
	player.tags = run.tags()
	player.max_hp = run.max_hp()
	player.hp = run.hp
	player.base_speed = run.base_speed()
	player.move = run.base_move()
	player.sprite_id = run.form_sprite_id()
	player.sprite_px = int(run.form()["sprite_px"])
	player.aware = true
	player.def = {"facing": run.species.get("facing", {}), "terrain_cost": run.species.get("terrain_cost", {})}
	player.terrain_costs = Battle.resolve_terrain_costs(player.tags, player.def)
	var wc := run.item_bonus("water_cost")
	if wc > 0:
		player.terrain_costs["water"] = maxi(1, int(player.terrain_costs.get("water", int(DB.table("tiles")["water"]["move_cost"]))) - wc)
	if run.spores > 0:
		player.status["spores"] = run.spores

## EXPLORE phase (after a room is cleared / on arrival at a stage): the battlefield has no enemies; the exits of the
## current step appear as gates on its edges and you walk (or click) to the one you want. `prev` reuses its grid.
const EXPLORE_MP := 12
var exits: Array = []                       # [{pos, side, door, type}] one per door of the current step (max 3)
var secret: Vector2i = Vector2i(-1, -1)     # hidden cave entrance (inside the area), or (-1,-1)
var secret_step: int = -1                   # run step this field's secret belongs to
var secret_reveal: bool = false             # explore just started after a clear: play the "rock falls away" reveal
var stage_idx: int = 0
var theme_id: String = "jungle"

static func create_explore(run_: RunState, prev: Battle = null) -> Battle:
	var b := Battle.new()
	b.run = run_
	b.mode = "explore"
	b.stage_idx = run_.stage_idx
	b._setup_explore(prev)
	return b

func _setup_explore(prev: Battle) -> void:
	var sdef: Dictionary = run.stage_def()
	var step := int(run.stage["step"])
	var eseed := RunState.mix(RunState.mix(run.seed_val, 5000 + run.stage_idx), step + 1)
	room = {"type": "explore", "seed": eseed, "step": step}
	theme_id = String(run.stage.get("theme", "jungle"))      # the cleared field keeps the stage's look (tundra stays tundra)
	rng.seed = RunState.mix(eseed, 77)
	weather_id = run.weather_id()
	var keep := prev != null and prev.grid != null and prev.stage_idx == run.stage_idx and String(prev.room.get("type", "")) != "cave"
	if keep:
		grid = prev.grid
		arena_spec = prev.arena_spec
	else:
		arena_spec = ArenaGen.pick(eseed, room, "spotted", run.stage_idx)
		grid = BGrid.generate(RunState.mix(eseed, 31), sdef.get("terrain", {}), String(run.stage.get("theme", "jungle")), arena_spec)
	_make_player()
	if keep and prev.player != null and grid.in_bounds(prev.player.pos) and not grid.blocks_move(prev.player.pos):
		player.pos = prev.player.pos
		player.facing = prev.player.facing
	else:
		var starts := grid.free_tiles({}, grid.w / 4, grid.w * 2 / 3)
		if starts.is_empty():
			starts = grid.free_tiles({}, 0, grid.w - 1)
		player.pos = starts[rng.randi() % starts.size()]
	units.append(player)
	player.vis_pos = Vector2(player.pos)
	player.vis_facing = player.facing
	player.vis_hp = player.hp
	var doors := run.current_step_doors()
	exits_step = step
	var reuse := keep and prev != null and not prev.exits.is_empty() and prev.exits_step == step and prev.exits.size() == doors.size()
	exits_unlock_anim = (prev != null and prev.exits_locked) or pending_unlock
	pending_unlock = false
	if reuse:
		exits = prev.exits.duplicate(true)     # the very gates that were visible (sealed) during the fight
	else:
		var places := ExitGen.place_exits(grid, doors.size(), rng, player.pos)
		for i in places.size():
			exits.append({"pos": places[i]["pos"], "side": places[i]["side"], "dir": places[i]["dir"], "door": i, "type": String(doors[i]["type"])})
	# the secret hole belongs to the field you just cleared (placed there by _roll_secret), once per step
	secret = Vector2i(-1, -1)
	secret_step = step
	if keep and prev.secret != Vector2i(-1, -1) and int(run.stage.get("secret_used_step", -1)) != step:
		var ok_step := (prev.secret_step == step) if prev.mode == "explore" else (prev.secret_step == step - 1)
		if ok_step and not grid.blocks_move(prev.secret) and prev.secret != player.pos:
			secret = prev.secret
			secret_reveal = (prev.mode != "explore") or prev.secret_reveal
	mp_max = EXPLORE_MP
	mp = mp_max
	phase = "explore"

func exit_at(p: Vector2i) -> int:
	for i in exits.size():
		if exits[i]["pos"] == p:
			return i
	return -1

## Terrain cost overrides for a unit: trait tags (data/tiles.json "traits", e.g. aquatic / semi_aquatic) merged with the
## def's own "terrain_cost" {tile_id: cost}, which wins.
static func resolve_terrain_costs(tags: Array, def: Dictionary) -> Dictionary:
	var out := {}
	var traits: Dictionary = DB.table("tiles").get("traits", {})
	for t in tags:
		if traits.has(t):
			for k in traits[t]:
				out[k] = mini(int(out[k]), int(traits[t][k])) if out.has(k) else int(traits[t][k])
	var own: Dictionary = def.get("terrain_cost", {})
	for k in own:
		out[k] = int(own[k])
	return out

func _next_uid() -> int:
	_uid += 1
	return _uid

func _make_enemy(id: String) -> BUnit:
	var d: Dictionary = DB.enemy(id)
	var u := BUnit.new()
	u.uid = _next_uid()
	u.id = id
	u.def = d
	u.display_name = String(d["name"])
	u.tags = d.get("tags", [])
	u.max_hp = int(d["hp"])
	u.hp = u.max_hp
	u.base_speed = float(d["speed"])
	u.move = int(d["move"])
	u.perception = float(d["perception"])
	u.abilities = d["abilities"].duplicate(true)
	u.sprite_id = String(d["sprite"])
	u.sprite_px = 16
	var sd := DB.sprite_def(u.sprite_id)
	if not sd.is_empty():
		u.sprite_px = int(sd["size"])
	u.infected = bool(d.get("infected", false))
	u.immune_to_infection = bool(d.get("immune", false))
	u.spreader = bool(d.get("spreader", false))
	u.spread_cd = 2
	u.terrain_costs = Battle.resolve_terrain_costs(u.tags, d)
	u.armor = int(d.get("armor", 0))
	if run != null and not d.has("fixed_stats") and not String(id).begins_with("_"):
		u.max_hp = maxi(1, int(round(float(u.max_hp) * Difficulty.hp_mult(run, room))))
		u.hp = u.max_hp
		u.bonus_damage = Difficulty.dmg_add(run, room)
	return u

func infect_unit(u: BUnit, silent: bool = false) -> void:
	if u.infected or u.immune_to_infection or u.is_player:
		return
	var cfg: Dictionary = DB.enemy("_infection")
	u.infected = true
	var new_max := int(round(u.max_hp * float(cfg["hp_mult"])))
	u.hp += new_max - u.max_hp
	u.max_hp = new_max
	u.bonus_damage += int(cfg["damage_bonus"])
	u.abilities.append(cfg["extra_ability"].duplicate(true))
	u.display_name = "Infected " + u.display_name
	u.spread_cd = int(cfg["spread_every"])
	if not silent:
		ev({"t": "infect", "unit": u.uid, "hp_after": u.hp})
		ev({"t": "popup", "unit": u.uid, "text": "INFECTED", "color": "#8dff6a"})
		log_line("%s is overtaken by the parasite!" % u.display_name)

func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t

# ------------------------------------------------------------------ events/log

func ev(d: Dictionary) -> void:
	events.append(d)

func drain_events() -> Array:
	var e := events
	events = []
	return e

func log_line(text: String) -> void:
	ev({"t": "log", "text": text})

func unit_by_uid(uid: int) -> BUnit:
	for u in units:
		if u.uid == uid:
			return u
	return null

func alive_enemies() -> Array:
	return enemies.filter(func(u): return u.alive)

func _occupied(except: BUnit = null) -> Dictionary:
	var o := {}
	for u in units:
		if u.alive and u != except:
			o[u.pos] = u
	return o

## Gates are sealed while the area is not cleared - except while nobody has noticed you (ambush phase): then you may slip out
## through one ("sneak past": no fight, no spoils).
func exits_sealed() -> bool:
	return exits_locked and phase != "ambush"

## Are the exit paths open (corridor cleared of trees, usable)? Hidden while enemies have noticed you; open in the explore phase and
## while nobody has noticed you (ambush phase: slip away). The trigger tile is a plain walkable edge tile either way.
func exits_visible() -> bool:
	return not exits.is_empty() and not exits_sealed()

func wm(u: BUnit) -> Dictionary:
	var m := WeatherSys.mods_for(weather_id, u.tags)
	if u.is_player and run != null and run.item_bonus("weather_resist") > 0:
		# Thick Pelt: weather can still help you, but never hurts
		m["speed_mult"] = maxf(1.0, float(m["speed_mult"]))
		m["damage_mult"] = maxf(1.0, float(m["damage_mult"]))
		m["stamina_delta"] = maxi(0, int(m["stamina_delta"]))
		m["hunger_extra"] = mini(0, int(m["hunger_extra"]))
		m["perception_mult"] = minf(1.0, float(m["perception_mult"]))
	return m

func eff_speed(u: BUnit) -> float:
	var s := (u.base_speed + u.speed_bonus) * float(wm(u)["speed_mult"])
	if u.is_player:
		var hs := run.hunger_state()
		var cfg: Dictionary = DB.growth()["hunger"]
		if hs == "low":
			s *= float(cfg["low_speed_mult"])
		elif hs == "starving":
			s *= float(cfg["starve_speed_mult"])
	return maxf(1.0, s)

func is_hidden() -> bool:
	for e in enemies:
		if e.alive and e.aware:
			return false
	return true

# ------------------------------------------------------------------ turn order

func _next_actor() -> BUnit:
	var best: BUnit = null
	var best_t := INF
	for u in units:
		if not u.alive:
			continue
		var t := maxf(0.0, (METER - u.meter) / eff_speed(u))
		if best == null or t < best_t - 0.0001 or (absf(t - best_t) <= 0.0001 and (u.is_player and not best.is_player)):
			best = u
			best_t = t
	for u in units:
		if u.alive:
			u.meter += best_t * eff_speed(u)
	best.meter -= METER
	return best

## Predict upcoming actors (does not change state).
func preview_order(n: int) -> Array:
	var meters := {}
	for u in units:
		if u.alive:
			meters[u] = u.meter
	var out: Array = []
	for i in n:
		var best: BUnit = null
		var best_t := INF
		for u in meters:
			var t := maxf(0.0, (METER - meters[u]) / eff_speed(u))
			if best == null or t < best_t - 0.0001 or (absf(t - best_t) <= 0.0001 and (u.is_player and not best.is_player)):
				best = u
				best_t = t
		if best == null:
			break
		for u in meters:
			meters[u] += best_t * eff_speed(u)
		meters[best] -= METER
		out.append(best)
	return out

## Begin the fight: unless an ambush phase is pending, run turns until the player may act.
func begin() -> void:
	if phase == "ambush":
		return
	if not _alerted_at_start:
		_alerted_at_start = true
		for e in enemies:
			if e.alive and e.aware:
				ev({"t": "spot", "unit": e.uid})      # they saw you coming: a "!" appears over each
	_run_turns()

var _alerted_at_start := false

func ambush_targets() -> Array:
	var out := []
	if phase != "ambush":
		return out
	for e in alive_enemies():
		if BGrid.dist(player.pos, e.pos) <= AMBUSH_RANGE and _landing_tile(e, AMBUSH_RANGE) != Vector2i(-1, -1):
			out.append(e)
	return out

func ambush_strike(target: BUnit) -> bool:
	if phase != "ambush" or not alive_enemies().has(target):
		return false
	var base := 4 + 2 * (run.tier() - 1)   # doubled by the unaware bonus: 8 / 12 / 16 / 20
	var land := _landing_tile(target, AMBUSH_RANGE)
	if land == Vector2i(-1, -1):
		return false
	_leap(player, land, false, "pounce")   # the strike resolves before anyone can react
	log_line("Ambush! You pounce on %s." % target.display_name)
	_face_pos(player, target.pos)
	var ibonus := run.item_bonus("unaware_damage") + run.item_bonus("ambush_bonus") + (run.item_bonus("back_damage") if facing_dir(player.pos, target) == "back" else 0)
	var dmg := _calc_damage(player, target, base * 2 + (stalker) + ibonus, facing_mult(player.pos, target))
	var fdir := facing_dir(player.pos, target)
	if fdir != "front":
		ev({"t": "popup", "unit": target.uid, "text": "%s hit x%s" % [String(DB.facing_cfg()["labels"][fdir]), str(snappedf(facing_mult(player.pos, target), 0.01))], "color": "#7dff8a" if fdir == "back" else "#ffd24a"})
	run.stats["ambushes"] += 1
	_hit(target, dmg, player, {"silent_if_kill": true})
	if player.alive and not _check_end():
		_detect_all()
	_finish_ambush()
	return true

func skip_ambush() -> void:
	if phase == "ambush":
		_finish_ambush()

func _finish_ambush() -> void:
	phase = "enemy"
	if not _check_end():
		_run_turns()

func _run_turns() -> void:
	var guard := 0
	while guard < 600:
		guard += 1
		if _check_end():
			return
		var a := _next_actor()
		current = a
		a.turns_taken += 1
		ev({"t": "turn", "unit": a.uid})
		_tick_start(a)
		if not a.alive:
			continue
		if a.is_player:
			_begin_player_turn()
			phase = "player"
			return
		if a.st("stun") > 0:
			_cancel_windup(a, false)
			ev({"t": "popup", "unit": a.uid, "text": "STUNNED", "color": "#ffe060"})
		else:
			_enemy_act(a)
		_tick_end(a)
	push_error("Battle turn loop guard tripped")

const POISON_DMG := 2      # per turn; the poison status counts the turns left
const WEB_SLOW := 2        # move points lost while webbed

## Movement allowance of a unit this turn (webbed units lose WEB_SLOW, never below 1).
func eff_move(u: BUnit) -> int:
	var m := u.move
	if u.st("web") > 0:
		m = maxi(1, m - WEB_SLOW)
	if u.st("daze") > 0:
		m = maxi(1, m / 2)
	return m

func _tick_start(u: BUnit) -> void:
	u.block = run.item_bonus("turn_block") if u.is_player else 0
	u.turns_left = 1 if u.slow_turn() else 99
	var bl := u.st("bleed")
	if bl > 0:
		u.status["bleed"] = bl - 1
		_raw_damage(u, bl, "bleed")
		if not u.alive:
			return
	var po := u.st("poison")
	if po > 0:
		u.status["poison"] = po - 1
		_raw_damage(u, POISON_DMG, "poison")
		if not u.alive:
			return
	var sp := u.st("spores")
	if sp > 0:
		u.status["spores"] = sp - 1
		_raw_damage(u, 1, "spores")
		if not u.alive:
			return
	# infection spreads between enemies
	if not u.is_player and u.infected and u.alive:
		u.spread_cd -= 1
		if u.spread_cd <= 0:
			var cfg: Dictionary = DB.enemy("_infection")
			var best: BUnit = null
			for o in alive_enemies():
				if o != u and not o.infected and not o.immune_to_infection and BGrid.dist(o.pos, u.pos) <= int(cfg["spread_range"]):
					if best == null or BGrid.dist(o.pos, u.pos) < BGrid.dist(best.pos, u.pos):
						best = o
			u.spread_cd = int(cfg["spread_every"])
			if best != null:
				infect_unit(best)

func _tick_end(u: BUnit) -> void:
	for k in ["weak", "expose", "stun", "web", "daze", "fear", "mark"]:
		if u.st(k) > 0:
			u.status[k] = u.st(k) - 1

func _raw_damage(u: BUnit, amount: int, why: String) -> void:
	u.hp -= amount
	ev({"t": "damage", "unit": u.uid, "amount": amount, "blocked": 0, "hp_after": maxi(u.hp, 0), "why": why})
	if u.hp <= 0:
		_kill(u)

# ------------------------------------------------------------------ player turn

func _begin_player_turn() -> void:
	turn_no += 1
	var hs := run.hunger_state()
	var cfg: Dictionary = DB.growth()["hunger"]
	stamina_max = run.base_stamina() + int(wm(player)["stamina_delta"])
	if hs != "ok":
		stamina_max -= int(cfg["low_stamina_penalty"])
	stamina_max = maxi(1, stamina_max)
	stamina = stamina_max
	mp = eff_move(player)
	mp_max = mp
	calm_used = false
	moved_tiles = 0
	free_draw_used = false
	evade_temp = 0
	var extra_cards := 0
	if patient and is_hidden():
		stamina += 1
		extra_cards = 1
		ev({"t": "popup", "unit": player.uid, "text": "Patient: +1 stamina, +1 card", "color": "#8fd070"})
	if well_fed_on and run.diet_tier() >= 2:
		stamina += 1
		ev({"t": "popup", "unit": player.uid, "text": "Well-Fed: +1 stamina", "color": "#e0a050"})
	if grid.get_tile(player.pos) == "water" and player.st("spores") > 0:
		player.status["spores"] = 0
		ev({"t": "popup", "unit": player.uid, "text": "Spores washed off", "color": "#8fc8f0"})
	_draw(run.hand_size() + extra_cards)
	ev({"t": "player_turn"})

func _draw(n: int) -> void:
	for i in n:
		if draw_pile.is_empty():
			if discard_pile.is_empty():
				return
			draw_pile = discard_pile
			discard_pile = []
			_shuffle(draw_pile)
		hand.append(draw_pile.pop_back())

func end_player_turn() -> void:
	if phase != "player":
		return
	discard_pile.append_array(hand)
	hand = []
	_tick_end(player)
	phase = "enemy"
	ev({"t": "player_turn_end"})
	_run_turns()

# ---- card helpers

func card_at(i: int) -> Dictionary:
	return DB.card(String(hand[i]))

func card_cost(i: int) -> int:
	return int(card_at(i)["cost"])

func _has_op(card: Dictionary, op: String) -> bool:
	for e in card["effects"]:
		if e["op"] == op:
			return true
	return false

func card_targets(i: int) -> Array:
	"""Valid targets: BUnits for 'enemy', Vector2i for 'tile', [] for self/all (always valid)."""
	var c := card_at(i)
	var out := []
	match String(c["target"]):
		"enemy":
			var r := int(c.get("range", 1))
			var minr := int(c.get("min_range", 0))
			var is_pounce := _has_op(c, "pounce")
			for e in alive_enemies():
				var d := BGrid.dist(player.pos, e.pos)
				if d > r or d < minr:
					continue
				if is_pounce:
					if _landing_tile(e, r) != Vector2i(-1, -1):
						out.append(e)
				elif r == 1 or grid.los(player.pos, e.pos):
					out.append(e)
		"tile":
			if int(c.get("min_enemy_dist", 0)) > 0 and _enemy_within(int(c["min_enemy_dist"]) - 1):
				return out
			var r := int(c.get("range", 3))
			var res := grid.reach(player.pos, r, _occupied(player), player.terrain_costs)
			var filt := String(c.get("tile_filter", ""))
			for p in res["cost"]:
				if filt == "" or grid.get_tile(p) == filt:
					out.append(p)
	return out

## True if a living enemy is within `d` tiles of the player.
func _enemy_within(d: int) -> bool:
	for e in alive_enemies():
		if BGrid.dist(player.pos, e.pos) <= d:
			return true
	return false

## Why a card cannot be played right now ("" = it can). Used for the greyed-out card tooltip.
func unplayable_reason(i: int) -> String:
	if phase != "player" or i < 0 or i >= hand.size():
		return ""
	var c := card_at(i)
	if card_cost(i) > stamina:
		return "Not enough stamina."
	var t := String(c["target"])
	if (t == "enemy" or t == "tile") and card_targets(i).is_empty():
		var minr := int(c.get("min_range", 0))
		if minr > 0 and _enemy_within(minr - 1):
			return "Too close: needs a target at least %d tiles away (no leaping at melee range)." % minr
		if int(c.get("min_enemy_dist", 0)) > 0 and _enemy_within(int(c["min_enemy_dist"]) - 1):
			return "An enemy is adjacent: you cannot dive away from melee range."
		return "No valid target in range."
	if _has_op(c, "damage_adjacent") and not _enemy_within(1):
		return "No enemy is adjacent."
	return ""

## Active items (items.json "use"): once per battle each.
var items_used: Dictionary = {}

func item_usable(id: String) -> bool:
	return phase == "player" and run.has_item(id) and DB.item(id).has("use") and not items_used.has(id)

func use_item(id: String) -> bool:
	if not item_usable(id):
		return false
	items_used[id] = true
	var ctx := {"target": null, "was_hidden": is_hidden(), "hit": false, "card": {}}
	for op in DB.item(id)["use"]["ops"]:
		_apply_op(op, ctx)
	ev({"t": "popup", "unit": player.uid, "text": "%s: %s" % [DB.item(id)["name"], DB.item(id)["use"]["text"]], "color": "#f0c050"})
	return true

func card_playable(i: int) -> bool:
	if phase != "player" or i < 0 or i >= hand.size():
		return false
	if card_cost(i) > stamina:
		return false
	var t := String(card_at(i)["target"])
	if t == "enemy" or t == "tile":
		return not card_targets(i).is_empty()
	if _has_op(card_at(i), "damage_adjacent") and not _enemy_within(1):
		return false
	return true

func play_card(i: int, target = null) -> bool:
	if not card_playable(i):
		return false
	var c := card_at(i)
	var t := String(c["target"])
	if t == "enemy":
		if not (target is BUnit) or not card_targets(i).has(target):
			return false
	elif t == "tile":
		if not (target is Vector2i) or not card_targets(i).has(target):
			return false
	stamina -= int(c["cost"])
	var id: String = hand[i]
	var hand_index_played := i
	hand.remove_at(i)
	var ctx := {"target": target, "was_hidden": is_hidden(), "hit": false, "card": c}
	ev({"t": "card_played", "id": id, "i": hand_index_played})
	if int(c["cost"]) == 0:
		if quicken:
			mp += 1
			mp_max += 1
			ev({"t": "popup", "unit": player.uid, "text": "Quicken +1 move", "color": "#7fd8f0"})
		if not free_draw_used and run.item_bonus("free_draw") > 0:
			free_draw_used = true
			_draw(run.item_bonus("free_draw"))
			ev({"t": "popup", "unit": player.uid, "text": "Tempo: +1 card", "color": "#7fd8f0"})
	for e in c["effects"]:
		_apply_op(e, ctx)
		if _check_end():
			break
	if c["type"] == "attack" and ctx["hit"] and ctx["was_hidden"] and calm and not calm_used:
		calm_used = true
		stamina += 1
		ev({"t": "popup", "unit": player.uid, "text": "+1 stamina (calm)", "color": "#f0b030"})
	if c["type"] == "power" or bool(c.get("exhaust", false)):
		exhausted.append(id)
	else:
		discard_pile.append(id)
	if not _check_end() and not _has_op(c, "hide"):
		_detect_all()   # noticed after pouncing/moving? (not when you just vanished)
	return true

func _apply_op(op: Dictionary, ctx: Dictionary) -> void:
	var tgt = ctx["target"]
	var amt := int(op.get("amount", 0))
	if bool(ctx.get("dodged", false)) and String(op["op"]) in ["bleed", "poison", "web", "weak", "expose", "stun", "daze", "mark", "double_bleed"]:
		return   # the attack missed: its riders do not land
	match String(op["op"]):
		"damage":
			if not (tgt is BUnit) or not tgt.alive:
				return
			var base := amt
			if not tgt.aware:
				base += int(op.get("unaware_bonus", 0))
			base += int(op.get("per_bleed", 0)) * tgt.st("bleed")
			if ctx["was_hidden"]:
				base += stalker
			_face_pos(player, tgt.pos)
			var fdir := facing_dir(player.pos, tgt)
			base += _synergy_damage(op, tgt, fdir)
			var fm := facing_mult(player.pos, tgt, op.get("facing", {}))
			if fdir == "back":
				base += run.item_bonus("back_damage")
			if not tgt.aware:
				base += run.item_bonus("unaware_damage")
			ctx["fdir"] = fdir
			var dmg := _calc_damage(player, tgt, base, fm)
			if fdir != "front" and fm != 1.0:
				ev({"t": "popup", "unit": tgt.uid, "text": "%s x%s" % [String(DB.facing_cfg()["labels"][fdir]), str(snappedf(fm, 0.01))], "color": "#7dff8a" if fdir == "back" else "#ffd24a"})
			var was_unaware: bool = not tgt.aware
			var killed_it := _hit(tgt, dmg, player, {"silent_if_kill": was_unaware})
			ctx["dodged"] = last_dodged
			ctx["hit"] = not last_dodged
			if not last_dodged and bool(op.get("consume_bleed", false)) and tgt.alive:
				tgt.status["bleed"] = 0
				ev({"t": "popup", "unit": tgt.uid, "text": "Bleed consumed", "color": "#e04050"})
			if killed_it and op.has("on_kill"):
				for k in op["on_kill"]:
					_apply_op(k, ctx)
		"bleed":
			for u in _op_targets(ctx):
				if u.alive:
					var ba := amt
					if op.has("back_bonus") and String(ctx.get("fdir", "")) == "back":
						ba += int(op["back_bonus"])
					ba += run.item_bonus("bleed_bonus")
					u.add_status("bleed", ba)
					ev({"t": "popup", "unit": u.uid, "text": "Bleed +%d" % ba, "color": "#e04050"})
		"poison":
			for u in _op_targets(ctx):
				if u.alive:
					var pa := amt + run.item_bonus("poison_bonus")
					if op.has("back_mult") and String(ctx.get("fdir", "")) == "back":
						pa *= int(op["back_mult"])
					u.add_status("poison", pa)
					ev({"t": "popup", "unit": u.uid, "text": "Poison +%d" % pa, "color": "#9aff5a"})
		"web":
			for u in _op_targets(ctx):
				if u.alive:
					u.add_status("web", int(op.get("turns", 1)))
					ev({"t": "popup", "unit": u.uid, "text": "Webbed", "color": "#e8e8ff"})
		"weak":
			for u in _op_targets(ctx):
				if u.alive:
					if bool(op.get("back_only", false)) and String(ctx.get("fdir", "")) != "back":
						continue
					u.add_status("weak", int(op.get("turns", 1)))
					ev({"t": "popup", "unit": u.uid, "text": "Weakened", "color": "#a0a0c0"})
		"expose":
			for u in _op_targets(ctx):
				if u.alive:
					u.add_status("expose", int(op.get("turns", 1)))
					ev({"t": "popup", "unit": u.uid, "text": "Exposed", "color": "#f0b030"})
		"stun":
			for u in _op_targets(ctx):
				if u.alive:
					u.add_status("stun", int(op.get("turns", 1)))
		"block":
			player.block += amt
			ev({"t": "block", "unit": player.uid, "amount": amt})
		"gain_mp":
			mp += amt
			mp_max += amt
			ev({"t": "popup", "unit": player.uid, "text": "+%d move" % amt, "color": "#7fd8f0"})
		"gain_stamina":
			if op.has("cond") and moved_tiles < int(op["cond"].get("momentum_min", 0)):
				return
			stamina += amt
			ev({"t": "popup", "unit": player.uid, "text": "+%d stamina" % amt, "color": "#f0b030"})
		"draw":
			_draw(amt)
		"heal":
			player.hp = mini(player.max_hp, player.hp + amt)
			ev({"t": "heal", "unit": player.uid, "amount": amt, "hp_after": player.hp})
		"hunger":
			run.change_hunger(amt)
			ev({"t": "popup", "unit": player.uid, "text": "+%d hunger" % amt, "color": "#e8a060"})
		"self_damage":
			_raw_damage(player, amt, "self")
		"speed_buff":
			player.speed_bonus += amt
			ev({"t": "popup", "unit": player.uid, "text": "+%d speed" % amt, "color": "#7fd8f0"})
		"stalker":
			stalker += amt
			ev({"t": "popup", "unit": player.uid, "text": "Stalker", "color": "#6fc24e"})
		"calm":
			calm = true
			ev({"t": "popup", "unit": player.uid, "text": "Calm", "color": "#6fc24e"})
		"extra_turn":
			player.meter += METER
			ev({"t": "popup", "unit": player.uid, "text": "EXTRA TURN", "color": "#ffe060"})
		"pounce":
			if tgt is BUnit and BGrid.dist(player.pos, tgt.pos) > 1:
				var land := _landing_tile(tgt, int(ctx["card"].get("range", 4)))
				if land != Vector2i(-1, -1):
					_leap(player, land, false, "pounce")
			if tgt is BUnit:
				_face_pos(player, tgt.pos)
		"dash":
			if tgt is Vector2i and tgt != player.pos:
				var res := grid.reach(player.pos, int(ctx["card"].get("range", 4)), _occupied(player), player.terrain_costs)
				var path := BGrid.path_from(res["prev"], player.pos, tgt)
				_move_along(player, path)
		"retreat":
			_retreat(player, int(op.get("tiles", 2)) + run.item_bonus("retreat_bonus"))
		"mark":
			for u in _op_targets(ctx):
				if u.alive:
					u.add_status("mark", int(op.get("turns", 2)))
					ev({"t": "popup", "unit": u.uid, "text": "Marked", "color": "#ffb060"})
		"daze":
			for u in _op_targets(ctx):
				if u.alive:
					u.add_status("daze", int(op.get("turns", 1)))
					ev({"t": "popup", "unit": u.uid, "text": "Dazed", "color": "#c8a0ff"})
		"fear":
			for u in _op_targets(ctx):
				if u.alive:
					if u.is_boss():
						ev({"t": "popup", "unit": u.uid, "text": "Resists fear", "color": "#a0a0a0"})
					else:
						u.add_status("fear", int(op.get("turns", 1)))
						_cancel_windup(u, false)
						ev({"t": "popup", "unit": u.uid, "text": "Feared", "color": "#d890ff"})
		"double_bleed":
			for u in _op_targets(ctx):
				if u.alive and u.st("bleed") > 0:
					u.status["bleed"] = u.st("bleed") * 2
					ev({"t": "popup", "unit": u.uid, "text": "Bleed x2 (%d)" % u.st("bleed"), "color": "#e04050"})
		"patient":
			patient = true
			ev({"t": "popup", "unit": player.uid, "text": "Patient Hunter", "color": "#8fd070"})
		"quicken":
			quicken = true
			ev({"t": "popup", "unit": player.uid, "text": "Quicken", "color": "#7fd8f0"})
		"well_fed":
			well_fed_on = true
			ev({"t": "popup", "unit": player.uid, "text": "Well-Fed", "color": "#e0a050"})
		"evade":
			evade_temp += amt
			ev({"t": "popup", "unit": player.uid, "text": "+%d%% evasion" % amt, "color": "#7fd8f0"})
		"heal_per_bleeding":
			var nb := 0
			for e in alive_enemies():
				if e.st("bleed") > 0:
					nb += 1
			if nb > 0:
				player.hp = mini(player.max_hp, player.hp + amt * nb)
				ev({"t": "heal", "unit": player.uid, "amount": amt * nb, "hp_after": player.hp})
		"draw_if_bleeding":
			for e in alive_enemies():
				if e.st("bleed") > 0:
					_draw(amt)
					break
		"draw_if_grass":
			if grid.is_grass(player.pos):
				_draw(amt)
				ev({"t": "popup", "unit": player.uid, "text": "Cover: +%d card" % amt, "color": "#8fd070"})
		"draw_diet":
			var dn := amt * run.diet_tier()
			if dn > 0:
				_draw(dn)
				ev({"t": "popup", "unit": player.uid, "text": "Diet: +%d cards" % dn, "color": "#e0a050"})
		"damage_adjacent":
			for e in alive_enemies():
				if BGrid.dist(player.pos, e.pos) <= 1:
					var fd := facing_dir(player.pos, e)
					var d2 := _calc_damage(player, e, amt + _synergy_damage({}, e, fd), 1.0)
					_hit(e, d2, player, {"aoe": true})
					ctx["hit"] = true
					if _check_end():
						return
		"hide":
			_try_hide()

func _op_targets(ctx: Dictionary) -> Array:
	if ctx["card"]["target"] == "all_enemies":
		return alive_enemies()
	var t = ctx["target"]
	if t is BUnit:
		return [t]
	return []

# ------------------------------------------------------------------ facing

## Dominant grid axis of the vector a->b (ties prefer the current facing's axis, then x). `keep` is returned if a==b.
static func dir_toward(a: Vector2i, b: Vector2i, keep: Vector2i = Vector2i(1, 0)) -> Vector2i:
	var d := b - a
	if d == Vector2i.ZERO:
		return keep
	if absi(d.x) > absi(d.y):
		return Vector2i(signi(d.x), 0)
	if absi(d.y) > absi(d.x):
		return Vector2i(0, signi(d.y))
	# exact diagonal: keep the axis we already face if it is one of the two options, else x
	if keep.x != 0 and signi(d.x) == keep.x:
		return Vector2i(keep.x, 0)
	if keep.y != 0 and signi(d.y) == keep.y:
		return Vector2i(0, keep.y)
	return Vector2i(signi(d.x), 0)

static func quarter_turns(a: Vector2i, b: Vector2i) -> int:
	var ia: int = DIRS4.find(a)
	var ib: int = DIRS4.find(b)
	var d := posmod(ib - ia, 4)
	return mini(d, 4 - d)

## "front" | "side" | "back": where `from` stands relative to `tgt`'s facing.
static func relative_dir(from: Vector2i, tgt_pos: Vector2i, tgt_facing: Vector2i) -> String:
	var v := from - tgt_pos
	if v == Vector2i.ZERO:
		return "front"
	var a := v.x * tgt_facing.x + v.y * tgt_facing.y
	var p := absi(v.x * tgt_facing.y - v.y * tgt_facing.x)
	if a > p:
		return "front"
	if -a > p:
		return "back"
	return "side"

func facing_dir(from: Vector2i, tgt: BUnit) -> String:
	return relative_dir(from, tgt.pos, tgt.facing)

## Damage multiplier for an attack launched from `from` at `tgt`. `over` is an optional per-card/per-ability
## {front, side, back} table replacing the global default. Targets add their own ftrait (enemy def "facing").
func facing_mult(from: Vector2i, tgt: BUnit, over: Dictionary = {}) -> float:
	var d := facing_dir(from, tgt)
	var defaults: Dictionary = DB.facing_cfg()["defaults"]
	var ftrait: Dictionary = tgt.facing_trait()
	if tgt.is_player:
		# the player's species table replaces the global default
		return float(over.get(d, ftrait.get(d, defaults[d])))
	return float(over.get(d, defaults[d])) * float(ftrait.get(d, 1.0))

## How well `e` can see something standing at `p` given where e is looking (1 = full range, 0 = blind spot).
func vision_mult(e: BUnit, p: Vector2i) -> float:
	var d := relative_dir(p, e.pos, e.facing)
	var table: Dictionary = DB.facing_cfg()["vision"]
	var own: Dictionary = e.facing_trait().get("vision", {})
	return float(own.get(d, table[d]))

## Set `u`'s facing (respecting slow turners). Returns true if the facing changed.
func _set_facing(u: BUnit, dir: Vector2i) -> bool:
	if dir == u.facing or dir == Vector2i.ZERO:
		return false
	var need := quarter_turns(u.facing, dir)
	var target := dir
	if need > u.turns_left:
		if u.turns_left <= 0:
			return false
		# rotate only as far as the budget allows, toward the wanted direction
		var ia: int = DIRS4.find(u.facing)
		var ib: int = DIRS4.find(dir)
		var step := 1 if posmod(ib - ia, 4) <= 2 else -1
		target = DIRS4[posmod(ia + step * u.turns_left, 4)]
		need = u.turns_left
	u.turns_left -= need
	u.facing = target
	ev({"t": "face", "unit": u.uid, "dir": target})
	return true

func _face_pos(u: BUnit, p: Vector2i) -> void:
	_set_facing(u, dir_toward(u.pos, p, u.facing))

## FREE turn: face the grid axis nearest to tile `p` (any phase where the player may act). Returns the new facing.
func face_player_toward(p: Vector2i) -> Vector2i:
	if phase != "player" and phase != "ambush" and phase != "explore":
		return player.facing
	player.turns_left = 99
	_face_pos(player, p)
	return player.facing

func face_player(dir: Vector2i) -> bool:
	if phase != "player" and phase != "ambush":
		return false
	player.turns_left = 99
	return _set_facing(player, dir)

## Preview used by the UI: what an attack on `tgt` with card `i` would do. {dir, mult, from}
func preview_attack(i: int, tgt: BUnit) -> Dictionary:
	var c := card_at(i)
	var from := player.pos
	if _has_op(c, "pounce") and BGrid.dist(player.pos, tgt.pos) > 1:
		var land := _landing_tile(tgt, int(c.get("range", 4)))
		if land != Vector2i(-1, -1):
			from = land
	var over := {}
	for e in c["effects"]:
		if e["op"] == "damage" and e.has("facing"):
			over = e["facing"]
			break
	return {"dir": facing_dir(from, tgt), "mult": facing_mult(from, tgt, over), "from": from}

func preview_ambush(tgt: BUnit) -> Dictionary:
	var land := _landing_tile(tgt, AMBUSH_RANGE)
	var from := land if land != Vector2i(-1, -1) else player.pos
	return {"dir": facing_dir(from, tgt), "mult": facing_mult(from, tgt), "from": from}

# ------------------------------------------------------------------ damage & death

func _calc_damage(src: BUnit, tgt: BUnit, base: int, fmult: float = 1.0) -> int:
	var amt := float(base + src.bonus_damage) * fmult
	amt *= float(wm(src)["damage_mult"])
	if src.st("weak") > 0:
		amt *= 0.75
	if src.st("daze") > 0:
		amt *= DAZE_DAMAGE
	if tgt.st("expose") > 0:
		amt *= 1.5
	return maxi(0, int(round(amt)))

## Returns true if the target died.
func _hit(tgt: BUnit, dmg: int, src: BUnit, opts: Dictionary = {}) -> bool:
	last_dodged = false
	# single-target attacks only: area attacks (opts.aoe) cannot be dodged, and unaware targets never see it coming
	if src != null and tgt.alive and not bool(opts.get("aoe", false)) and (tgt.is_player or tgt.aware):
		var evade := grid.evasion(tgt.pos)
		if tgt.is_player:
			if grid.is_grass(tgt.pos):
				evade += float(run.item_bonus("grass_evasion")) / 100.0
			evade += float(evade_temp) / 100.0
		evade = minf(evade, 0.75)
		if evade > 0.0 and evade_rng.randf() < evade:
			last_dodged = true
			ev({"t": "dodge", "unit": tgt.uid, "src": src.uid})
			log_line("%s dodges in the tall grass!" % ("You" if tgt.is_player else tgt.display_name))
			return false
	if src != null and tgt.alive and not tgt.is_player and tgt.armor > 0 and tgt.st("expose") == 0 and dmg > 0 and facing_dir(src.pos, tgt) == "front":
		dmg = maxi(int(ceil(float(dmg) / 2.0)), dmg - tgt.armor)   # armour never cancels more than half a hit
		ev({"t": "popup", "unit": tgt.uid, "text": "Armor -%d" % tgt.armor, "color": "#b0b8c8"})
	var absorbed := mini(tgt.block, dmg)
	tgt.block -= absorbed
	var real := dmg - absorbed
	tgt.hp -= real
	ev({"t": "hit", "src": src.uid if src != null else -1, "unit": tgt.uid, "amount": real, "blocked": absorbed, "hp_after": maxi(tgt.hp, 0), "why": "attack"})
	if tgt.hp <= 0:
		var silent: bool = bool(opts.get("silent_if_kill", false)) and src != null and src.is_player
		_kill(tgt)
		if silent:
			ev({"t": "popup", "unit": src.uid, "text": "Silent kill", "color": "#6fc24e"})
		else:
			_noise(tgt.pos, src)
		return true
	if not tgt.is_player:
		_check_phases(tgt)
	if src != null and src.is_player and not tgt.is_player:
		if not tgt.aware:
			tgt.aware = true
			tgt.last_seen = player.pos
			ev({"t": "spot", "unit": tgt.uid})
		_noise(tgt.pos, src)
	return false

func _noise(at: Vector2i, src: BUnit) -> void:
	if src == null or not src.is_player:
		return
	for e in alive_enemies():
		if not e.aware and BGrid.dist(e.pos, at) <= NOISE_RADIUS:
			e.aware = true
			e.last_seen = player.pos
			ev({"t": "spot", "unit": e.uid})
			log_line("%s heard the commotion." % e.display_name)

func _kill(u: BUnit) -> void:
	u.alive = false
	u.hp = 0
	ev({"t": "death", "unit": u.uid})
	if not u.is_player and run != null and run.item_bonus("kill_heal") > 0 and player.alive:
		var kh := run.item_bonus("kill_heal")
		player.hp = mini(player.max_hp, player.hp + kh)
		ev({"t": "heal", "unit": player.uid, "amount": kh, "hp_after": player.hp})
	if not u.is_player:
		killed.append({"id": u.id, "infected": u.infected, "xp": int(u.def.get("xp", 0)), "food": int(u.def.get("food", 0))})
		log_line("%s is defeated." % u.display_name)
	else:
		log_line("You fall...")

func _check_end() -> bool:
	if phase == "won" or phase == "lost":
		return true
	if not player.alive:
		phase = "lost"
		ev({"t": "end", "result": "lost"})
		return true
	if alive_enemies().is_empty():
		phase = "won"
		ev({"t": "end", "result": "won"})
		return true
	return false

## Result summary used by the reward flow.
func result() -> Dictionary:
	var xp := 0
	var food := 0
	var inf := 0
	for k in killed:
		xp += int(k["xp"])
		food += int(k["food"]) / (2 if k["infected"] else 1)
		if k["infected"]:
			inf += 1
	return {"won": phase == "won", "xp": xp, "food": food, "infected_corpses": inf, "kills": killed.size(), "corpses": killed.duplicate(true)}

## Persist player state back into the run.
func commit_to_run() -> void:
	run.hp = clampi(player.hp, 0, run.max_hp())
	run.spores = player.st("spores")
	run.stats["kills"] += killed.size()
	if not player.alive:
		run.game_over = true
		run.cause = "Slain in battle."

# ------------------------------------------------------------------ movement

func reachable_tiles() -> Dictionary:
	if phase != "player" and phase != "explore" and phase != "ambush":
		return {}
	return grid.reach(player.pos, mp, _occupied(player), player.terrain_costs)["cost"]

func move_player(dest: Vector2i) -> bool:
	if phase != "player" and phase != "explore" and phase != "ambush":
		return false
	var res := grid.reach(player.pos, mp, _occupied(player), player.terrain_costs)
	if not res["cost"].has(dest) or dest == player.pos:
		return false
	var path := BGrid.path_from(res["prev"], player.pos, dest)
	mp -= int(res["cost"][dest])
	_move_along(player, path)
	if phase == "ambush" and alive_enemies().any(func(e): return e.aware):
		_finish_ambush()        # noticed on the way in: the fight starts as a normal (spotted) one
	return true

func _move_along(u: BUnit, path: Array) -> void:
	if path.is_empty():
		return
	ev({"t": "move", "unit": u.uid, "path": path.duplicate()})
	if u.is_player:
		moved_tiles += path.size()
	var prev: Vector2i = u.pos
	for p in path:
		_set_facing(u, dir_toward(prev, p, u.facing))
		prev = p
	u.pos = path.back()
	if u.is_player:
		_detect_all()

func _leap(u: BUnit, dest: Vector2i, detect: bool = true, style: String = "leap") -> void:
	if dest == u.pos:
		return
	ev({"t": "leap", "unit": u.uid, "from": u.pos, "to": dest, "style": style})
	if u.is_player:
		moved_tiles += BGrid.dist(u.pos, dest)
	_set_facing(u, dir_toward(u.pos, dest, u.facing))
	u.pos = dest
	if u.is_player and detect:
		_detect_all()

## Adjacent free tile to `target` closest to the leaper, within `max_range` of the player. (-1,-1) if none.
func _landing_tile(target: BUnit, max_range: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_score := 9999
	var occ := _occupied()
	for n in grid.neighbors(target.pos):
		if grid.blocks_move(n):
			continue
		if occ.has(n) and not is_same(occ[n], player):
			continue
		var d := BGrid.dist(player.pos, n)
		if d > max_range:
			continue
		var score := d * 10 - (3 if grid.is_grass(n) else 0) + (2 if grid.get_tile(n) == "water" else 0)
		match facing_dir(n, target):
			"back":
				score -= 12     # land behind the target when we can: backstab synergy
			"side":
				score -= 5
		if score < best_score:
			best_score = score
			best = n
	return best

func _retreat(u: BUnit, tiles: int) -> void:
	var res := grid.reach(u.pos, tiles, _occupied(u), u.terrain_costs)
	var foes: Array = enemies.filter(func(e): return e.alive and e.aware)
	if foes.is_empty():
		foes = alive_enemies()
	var best: Vector2i = u.pos
	var best_score := _retreat_score(u.pos, foes, 0)
	for p in res["cost"]:
		var s := _retreat_score(p, foes, int(res["cost"][p]))
		if s > best_score:
			best_score = s
			best = p
	if best != u.pos:
		_move_along(u, BGrid.path_from(res["prev"], u.pos, best))

func _retreat_score(p: Vector2i, foes: Array, cost: int) -> int:
	var md := 99
	for f in foes:
		md = mini(md, BGrid.dist(p, f.pos))
	return md * 10 + (6 if grid.is_grass(p) else 0) - cost

func _try_hide() -> void:
	if not grid.is_grass(player.pos):
		ev({"t": "popup", "unit": player.uid, "text": "Nowhere to hide", "color": "#a0a0a0"})
		return
	var lost := false
	for e in alive_enemies():
		if e.aware and BGrid.dist(e.pos, player.pos) >= 2:
			_lose_track(e)
			lost = true
	if lost:
		ev({"t": "popup", "unit": player.uid, "text": "HIDDEN", "color": "#6fc24e"})
		log_line("You melt into the tall grass.")
	elif not is_hidden():
		ev({"t": "popup", "unit": player.uid, "text": "Too close!", "color": "#a0a0a0"})

# ------------------------------------------------------------------ detection

func can_detect(e: BUnit) -> bool:
	return can_detect_at(e, player.pos)

## Could `e` (looking where it faces) notice the player standing on tile `p`? Enemies see far in front, less to the
## sides and not at all behind them (a rear approach is undetected, even adjacent). Tall grass etc. still apply.
func can_detect_at(e: BUnit, p: Vector2i) -> bool:
	var vm := vision_mult(e, p)
	if vm <= 0.0:
		return false
	var d := BGrid.dist(e.pos, p)
	if d <= 1:
		return true
	var r := maxi(1, int(floor(e.perception * float(wm(e)["perception_mult"]) * grid.detect_mod(p) * vm + 0.0001)))
	return d <= r and grid.los(e.pos, p)

func detect_range(e: BUnit) -> int:
	var r := e.perception * float(wm(e)["perception_mult"]) * grid.detect_mod(player.pos)
	return maxi(1, int(floor(r + 0.0001)) - run.item_bonus("stealth"))

func _detect_all() -> void:
	for e in alive_enemies():
		if e.state != "spotted":
			if can_detect(e):
				_spot(e, e.state != "searching")   # a searching enemy that finds you does not call for help
		elif tracks_player(e):
			e.last_seen = player.pos                 # hunting enemies keep updating where they last saw you

func _spot(e: BUnit, alert_others: bool = true) -> void:
	if e.state == "idle" and int(e.def.get("surprise", 0)) > 0:
		e.surprise_ready = true
	e.aware = true
	e.last_seen = player.pos
	e.roam_target = Vector2i(-1, -1)
	ev({"t": "spot", "unit": e.uid})
	log_line("%s spots you!" % e.display_name)
	if not alert_others:
		return
	for o in alive_enemies():
		if o.state == "idle" and BGrid.dist(o.pos, e.pos) <= NOISE_RADIUS:
			o.aware = true
			o.last_seen = player.pos
			ev({"t": "spot", "unit": o.uid})

## Can a HUNTING enemy still follow you? It turns freely toward you, so only distance, cover, weather and line of
## sight matter (range x TRACK_MULT). Adjacent always; "scent" enemies track within SCENT_RANGE regardless of cover.
func tracks_player(e: BUnit) -> bool:
	var d := BGrid.dist(e.pos, player.pos)
	if d <= 1:
		return true
	if e.is_boss():
		return true      # bosses never lose you
	if bool(e.def.get("elite", false)) and d <= 10:
		return true      # elites hunt relentlessly
	if "scent" in e.tags and d <= SCENT_RANGE:
		return true
	var r := maxi(1, int(floor(e.perception * float(wm(e)["perception_mult"]) * grid.detect_mod(player.pos) * TRACK_MULT + 0.0001)))
	return d <= r and grid.los(e.pos, player.pos)

## The enemy stops hunting: it remembers where it last saw you and goes to search there, alone (no one else is alerted).
func _lose_track(e: BUnit) -> void:
	e.state = "searching"
	e.search_phase = "go"
	e.scan_left = SEARCH_SCAN_TURNS
	if e.last_seen == Vector2i(-1, -1):
		e.last_seen = player.pos
	ev({"t": "lose_track", "unit": e.uid, "last_seen": e.last_seen})
	log_line("%s loses sight of you." % e.display_name)

# ------------------------------------------------------------------ enemy AI

func _enemy_act(e: BUnit) -> void:
	match e.state:
		"idle":
			_idle(e)
			if e.alive and can_detect(e):
				_spot(e)
			return
		"searching":
			_search(e)
			return
	if e.st("fear") > 0 and not e.is_boss():
		_cancel_windup(e, false)
		ev({"t": "popup", "unit": e.uid, "text": "Flees in fear", "color": "#d890ff"})
		_flee(e, eff_move(e))
		return
	var rh := float(e.def.get("retreat_hp", 0.0))
	if rh > 0.0 and not e.retreated and float(e.hp) <= float(e.max_hp) * rh and e.state == "spotted":
		e.retreated = true
		e.bonus_damage += 1
		_cancel_windup(e, false)
		ev({"t": "popup", "unit": e.uid, "text": "Retreats!", "color": "#ffd080"})
		log_line("%s breaks off and retreats!" % e.display_name)
		_flee(e, eff_move(e) + 1)
		return
	# spotted: keep hunting only while you can still be followed; otherwise go and search where you were last seen
	if not tracks_player(e):
		_lose_track(e)
		_search(e)
		return
	e.last_seen = player.pos
	_face_pos(e, player.pos)   # aware enemies turn toward you first (slow turners can only swing 90 degrees)
	var ab := e.next_ability()
	if ab.is_empty():
		return
	_do_ability(e, ab, 0)

## True path distances (walking cost) from `target` outward; used to steer enemies around obstacles.
func _dist_map(target: Vector2i, costs: Dictionary = {}) -> Dictionary:
	return grid.reach(target, 99, {}, costs)["cost"]

## Walk `e` up to `budget` movement points along the cheapest path toward `target`. Returns true if it moved.
func _step_toward(e: BUnit, target: Vector2i, budget: int, avoid_water: bool = false) -> bool:
	var dm := _dist_map(target, e.terrain_costs)
	var res := grid.reach(e.pos, budget, _occupied(e), e.terrain_costs)
	var best: Vector2i = e.pos
	var best_d: int = int(dm.get(e.pos, 999))
	var best_c := 0
	for p in res["cost"]:
		if avoid_water and grid.get_tile(p) == "water":
			continue
		var d: int = int(dm.get(p, 999))
		var c: int = int(res["cost"][p])
		if d < best_d or (d == best_d and best != e.pos and c < best_c):
			best = p
			best_d = d
			best_c = c
	if best == e.pos:
		return false
	_move_along(e, BGrid.path_from(res["prev"], e.pos, best))
	return true

## SEARCHING: walk to the last seen tile (within the movement allowance), then look around for SEARCH_SCAN_TURNS turns
## (turning through the facing/vision cone each turn); give up and go back to idle roaming if you are not found.
func _search(e: BUnit) -> void:
	if can_detect(e):
		_spot(e, false)
		return
	if e.search_phase == "go":
		if e.pos != e.last_seen:
			var moved := _step_toward(e, e.last_seen, eff_move(e))
			if e.alive and can_detect(e):
				_spot(e, false)
				return
			if moved:
				if e.pos == e.last_seen:
					e.search_phase = "scan"   # arrived: start looking around next turn
				return
		e.search_phase = "scan"   # standing on the spot already, or no way to get closer
	# scan: swing the gaze one quarter turn per turn, alternating direction so the whole area gets covered
	var i: int = DIRS4.find(e.facing)
	var step := 1 if (SEARCH_SCAN_TURNS - e.scan_left) % 2 == 0 else -2
	_set_facing(e, DIRS4[posmod(i + step, 4)])
	e.scan_left -= 1
	if can_detect(e):
		_spot(e, false)
		return
	if e.scan_left <= 0:
		e.state = "idle"
		e.roam_target = Vector2i(-1, -1)
		ev({"t": "give_up", "unit": e.uid})
		ev({"t": "popup", "unit": e.uid, "text": "Hm.", "color": "#c8c8c8"})
		log_line("%s gives up the search." % e.display_name)

## IDLE: wander around `home` (walks a couple of tiles toward a random waypoint, pauses and glances around in between).
func _idle(e: BUnit) -> void:
	if e.home == Vector2i(-1, -1):
		e.home = e.pos
	var roll := rng.randf()
	if roll >= 0.55:
		if roll < 0.80:   # glance around: slow sweeps leave windows to slip behind them
			var i: int = DIRS4.find(e.facing)
			_set_facing(e, DIRS4[posmod(i + (1 if rng.randf() < 0.5 else -1), 4)])
		return
	var far_from_home := BGrid.dist(e.pos, e.home) > ROAM_RADIUS
	if far_from_home:
		e.roam_target = e.home    # returning to the post after a search
	elif e.roam_target == Vector2i(-1, -1) or e.roam_target == e.pos or rng.randf() < 0.2:
		var opts := []
		var occ := _occupied(e)
		for dx in range(-ROAM_RADIUS, ROAM_RADIUS + 1):
			for dy in range(-ROAM_RADIUS, ROAM_RADIUS + 1):
				var p := e.home + Vector2i(dx, dy)
				if BGrid.dist(p, e.home) <= ROAM_RADIUS and grid.in_bounds(p) and not grid.blocks_move(p) and not occ.has(p) and grid.get_tile(p) != "water" and p != e.pos:
					opts.append(p)
		e.roam_target = opts[rng.randi() % opts.size()] if not opts.is_empty() else e.pos
	if e.roam_target != e.pos:
		if not _step_toward(e, e.roam_target, ROAM_STEP, true):
			e.roam_target = Vector2i(-1, -1)

func _in_range(e: BUnit, ab: Dictionary, from: Vector2i) -> bool:
	var d := BGrid.dist(from, player.pos)
	match String(ab["kind"]):
		"aoe":
			return d <= int(ab.get("radius", 1))
		"attack", "infect":
			var r := int(ab.get("range", 1))
			if d > r or d < int(ab.get("min_range", 0)):
				return false
			return r <= 1 or bool(ab.get("leap", false)) or grid.los(from, player.pos)
	return true

func _do_ability(e: BUnit, ab: Dictionary, depth: int) -> void:
	var kind := String(ab["kind"])
	if not e.windup.is_empty():
		_fire_windup(e)
		return
	match kind:
		"block":
			e.block += int(ab["amount"])
			ev({"t": "block", "unit": e.uid, "amount": int(ab["amount"])})
			log_line("%s uses %s." % [e.display_name, ab["name"]])
			e.ability_idx += 1
			_approach(e, {"kind": "attack", "range": 1})
			return
		"summon":
			var limit := int(ab.get("limit", 3))
			var existing := 0
			for o in alive_enemies():
				if o.id == String(ab["summon"]):
					existing += 1
			if existing >= limit:
				e.ability_idx += 1
				if depth < 3:
					_do_ability(e, e.next_ability(), depth + 1)
				return
			log_line("%s broods..." % e.display_name)
			for i in int(ab.get("count", 1)):
				_spawn_near(e, String(ab["summon"]))
			e.ability_idx += 1
			return
		"infect":
			# sometimes seed the parasite into a nearby ally instead of the player
			var ally: BUnit = null
			for o in alive_enemies():
				if o != e and not o.infected and not o.immune_to_infection and BGrid.dist(o.pos, e.pos) <= int(ab.get("range", 3)):
					ally = o
					break
			if ally != null and rng.randf() < 0.45:
				log_line("%s spits spores at %s." % [e.display_name, ally.display_name])
				ev({"t": "attack", "unit": e.uid, "target": ally.uid, "ranged": BGrid.dist(e.pos, ally.pos) > 1})
				if BGrid.dist(e.pos, ally.pos) > 1:
					ev({"t": "projectile", "unit": e.uid, "target": ally.uid, "kind": "spore", "from": e.pos, "to": ally.pos})
				infect_unit(ally)
				e.ability_idx += 1
				return
	# movement + attack abilities. Leaps have a minimum distance: adjacent to you, use the next ability instead.
	if int(ab.get("min_range", 0)) > BGrid.dist(e.pos, player.pos) and depth < e.abilities.size():
		e.ability_idx += 1
		_do_ability(e, e.next_ability(), depth + 1)
		return
	# KITERS (ranged units) back off when you close in, then shoot
	var kiter := String(e.def.get("behavior", "")) == "kiter"
	if kiter and depth == 0 and BGrid.dist(e.pos, player.pos) <= 1 and kind == "attack" and int(ab.get("range", 1)) > 1:
		ev({"t": "popup", "unit": e.uid, "text": "Backs off", "color": "#c0c0ff"})
		_flee(e, eff_move(e))
	# TELEGRAPHED heavy attacks: charge this turn (danger tiles shown), strike the marked tiles next turn
	if bool(ab.get("windup", false)):
		_start_windup(e, ab)
		return
	if not _in_range(e, ab, e.pos):
		_approach(e, ab)
	if not _in_range(e, ab, e.pos) or not player.alive:
		return
	if bool(ab.get("leap", false)) and BGrid.dist(e.pos, player.pos) > 1:
		var land := _landing_for(e)
		if land == Vector2i(-1, -1):
			return
		_leap(e, land)
	e.ability_idx += 1
	_enemy_attack(e, ab)
	if e.alive and ab.has("hit_and_run") and player.alive:
		_flee(e, int(ab["hit_and_run"]))
	elif e.alive and kiter and player.alive and int(ab.get("range", 1)) > 1:
		_flee(e, 1)

func _landing_for(e: BUnit) -> Vector2i:
	var occ := _occupied(e)
	var best := Vector2i(-1, -1)
	var bd := 999
	for n in grid.neighbors(player.pos):
		if grid.blocks_move(n) or occ.has(n):
			continue
		var d := BGrid.dist(e.pos, n)
		if d < bd:
			bd = d
			best = n
	return best

## Tiles within `radius` of `c` (walkable arena tiles only).
func _aoe_tiles(c: Vector2i, radius: int) -> Array:
	var out := []
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var p := c + Vector2i(dx, dy)
			if grid.in_bounds(p) and not grid.is_void(p) and BGrid.dist(c, p) <= radius:
				out.append(p)
	return out

func _start_windup(e: BUnit, ab: Dictionary) -> void:
	if not _in_range(e, ab, e.pos):
		_approach(e, ab)
	if not _in_range(e, ab, e.pos) or not player.alive:
		return
	_face_pos(e, player.pos)
	e.windup = ab
	e.windup_tiles = _aoe_tiles(e.pos, int(ab.get("radius", 1))) if String(ab["kind"]) == "aoe" else [player.pos]
	ev({"t": "windup", "unit": e.uid, "tiles": e.windup_tiles.duplicate()})
	ev({"t": "popup", "unit": e.uid, "text": "%s!" % String(ab["name"]), "color": "#ff9040"})
	log_line("%s winds up %s: step out of the red tiles!" % [e.display_name, ab["name"]])

func _fire_windup(e: BUnit) -> void:
	var ab := e.windup
	var tiles := e.windup_tiles
	e.windup = {}
	e.windup_tiles = []
	e.ability_idx += 1
	ev({"t": "windup_end", "unit": e.uid})
	if player.alive and tiles.has(player.pos):
		_enemy_attack(e, ab, float(ab.get("windup_mult", 1.5)))
	else:
		ev({"t": "attack", "unit": e.uid, "target": player.uid, "ranged": false})
		ev({"t": "popup", "unit": player.uid, "text": "Sidestepped!", "color": "#7dff8a"})
		log_line("You avoid %s." % ab["name"])

func _cancel_windup(e: BUnit, quiet: bool = true) -> void:
	if e.windup.is_empty():
		return
	e.windup = {}
	e.windup_tiles = []
	ev({"t": "windup_end", "unit": e.uid})
	if not quiet:
		ev({"t": "popup", "unit": e.uid, "text": "Interrupted!", "color": "#ffe060"})

## Boss/elite phases (enemies.json "phases": [{hp_pct, text, bonus_damage, move, speed, summon, count, popup}]), once each.
func _check_phases(u: BUnit) -> void:
	var ph: Array = u.def.get("phases", [])
	for i in ph.size():
		if u.phase_done.has(i) or not u.alive:
			continue
		var p: Dictionary = ph[i]
		if float(u.hp) > float(u.max_hp) * float(p["hp_pct"]):
			continue
		u.phase_done.append(i)
		u.bonus_damage += int(p.get("bonus_damage", 0))
		u.move += int(p.get("move", 0))
		u.speed_bonus += float(p.get("speed", 0))
		ev({"t": "popup", "unit": u.uid, "text": String(p.get("popup", "PHASE 2")), "color": "#ff5040"})
		ev({"t": "phase", "unit": u.uid})
		log_line(String(p.get("text", "%s changes tactics!" % u.display_name)))
		if p.has("summon"):
			for k in int(p.get("count", 1)):
				_spawn_near(u, String(p["summon"]))

## Extra damage from synergies for one of your hits on `tgt` (mark, flank, bleed, momentum, diet, items).
func _synergy_damage(op: Dictionary, tgt: BUnit, fdir: String) -> int:
	var b := 0
	var bleeding := tgt.st("bleed") > 0
	if op.has("flank_bonus") and fdir != "front":
		b += int(op["flank_bonus"])
	if op.has("bleed_bonus") and bleeding:
		b += int(op["bleed_bonus"])
	if op.has("per_momentum"):
		b += int(op["per_momentum"]) * mini(moved_tiles, int(op.get("momentum_max", 6)))
	if op.has("per_diet"):
		b += int(op["per_diet"]) * run.diet_tier()
	if tgt.st("mark") > 0:
		b += MARK_BONUS + run.item_bonus("mark_bonus")
		tgt.status["mark"] = 0
		ev({"t": "popup", "unit": tgt.uid, "text": "Mark +%d" % (MARK_BONUS + run.item_bonus("mark_bonus")), "color": "#ffb060"})
	if bleeding:
		b += run.item_bonus("bleed_vuln")
	if fdir != "front":
		b += run.item_bonus("side_damage")
	b += mini(3, moved_tiles / 2) * run.item_bonus("momentum_dmg")
	b += run.diet_tier() * run.item_bonus("diet_damage")
	return b

## What `e` is going to do on its next turn (Slay-the-Spire style intent). {kind, label, dmg, tiles, status}
func intent_of(e: BUnit) -> Dictionary:
	if not e.alive:
		return {}
	if e.st("stun") > 0:
		return {"kind": "stun", "label": "Stunned"}
	if e.st("fear") > 0 and not e.is_boss():
		return {"kind": "flee", "label": "Fleeing"}
	if e.state == "idle":
		return {"kind": "idle", "label": "Unaware"}
	if e.state == "searching":
		return {"kind": "search", "label": "Searching"}
	if not e.windup.is_empty():
		var wa: Dictionary = e.windup
		var wd := int(round(float(_calc_damage(e, player, int(wa.get("damage", 0)), 1.0)) * float(wa.get("windup_mult", 1.5))))
		return {"kind": "windup", "label": String(wa["name"]), "dmg": wd, "tiles": e.windup_tiles}
	var rh := float(e.def.get("retreat_hp", 0.0))
	if rh > 0.0 and not e.retreated and float(e.hp) <= float(e.max_hp) * rh:
		return {"kind": "flee", "label": "Retreating"}
	var ab := {}
	var dist := BGrid.dist(e.pos, player.pos)
	for k in e.abilities.size():
		var a: Dictionary = e.abilities[(e.ability_idx + k) % e.abilities.size()]
		if int(a.get("min_range", 0)) > dist:
			continue
		ab = a
		break
	if ab.is_empty():
		return {}
	var kind := String(ab["kind"])
	var out := {"kind": kind, "label": String(ab["name"]), "dmg": 0, "status": []}
	match kind:
		"attack", "aoe", "infect":
			var base := int(ab.get("damage", 0))
			out["dmg"] = _calc_damage(e, player, base, 1.0) if base > 0 else 0
			if bool(ab.get("windup", false)):
				out["kind"] = "charge"
			elif kind == "attack" and int(ab.get("range", 1)) > 1 and not bool(ab.get("leap", false)):
				out["kind"] = "ranged"
			elif bool(ab.get("leap", false)):
				out["kind"] = "leap"
	for k in ["bleed", "poison", "web", "spores", "weak"]:
		if ab.has(k):
			out["status"].append(k)
	return out

func _enemy_attack(e: BUnit, ab: Dictionary, mult: float = 1.0) -> void:
	_face_pos(e, player.pos)
	var ranged := BGrid.dist(e.pos, player.pos) > 1 and not bool(ab.get("leap", false)) and String(ab["kind"]) in ["attack", "infect"]
	ev({"t": "attack", "unit": e.uid, "target": player.uid, "ranged": ranged})
	if ranged:
		ev({"t": "projectile", "unit": e.uid, "target": player.uid, "kind": String(ab.get("projectile", "spore" if String(ab["kind"]) == "infect" else "spit")), "from": e.pos, "to": player.pos})
	log_line("%s uses %s." % [e.display_name, ab["name"]])
	var kind := String(ab["kind"])
	var base := int(ab.get("damage", 0))
	if base > 0 and bool(e.def.get("pack", false)):
		var mates := 0
		for o in alive_enemies():
			if o != e and o.id == e.id and BGrid.dist(o.pos, player.pos) <= 1:
				mates += 1
		mates = mini(mates, 2)
		if mates > 0:
			base += mates
			ev({"t": "popup", "unit": e.uid, "text": "Pack +%d" % mates, "color": "#ffb060"})
	if base > 0 and e.surprise_ready:
		e.surprise_ready = false
		base += int(e.def.get("surprise", 0))
		ev({"t": "popup", "unit": e.uid, "text": "Ambush! +%d" % int(e.def.get("surprise", 0)), "color": "#ff7050"})
	if base > 0 or kind == "attack" or kind == "aoe":
		var fm := facing_mult(e.pos, player, ab.get("facing", {}))
		var fdir := facing_dir(e.pos, player)
		var dmg := int(round(float(_calc_damage(e, player, base, fm)) * mult))
		if fdir != "front" and fm != 1.0:
			ev({"t": "popup", "unit": player.uid, "text": "%s hit x%s" % [String(DB.facing_cfg()["labels"][fdir]), str(snappedf(fm, 0.01))], "color": "#ff9a6a"})
		_hit(player, dmg, e, {"aoe": kind == "aoe"})
		if last_dodged:
			return
	if not player.alive:
		return
	if ab.has("bleed"):
		player.add_status("bleed", int(ab["bleed"]))
		ev({"t": "popup", "unit": player.uid, "text": "Bleed +%d" % int(ab["bleed"]), "color": "#e04050"})
	if ab.has("poison"):
		player.add_status("poison", int(ab["poison"]))
		ev({"t": "popup", "unit": player.uid, "text": "Poison +%d" % int(ab["poison"]), "color": "#9aff5a"})
	if ab.has("web"):
		player.add_status("web", int(ab["web"]))
		ev({"t": "popup", "unit": player.uid, "text": "Webbed", "color": "#e8e8ff"})
	if ab.has("spores"):
		player.add_status("spores", int(ab["spores"]))
		ev({"t": "popup", "unit": player.uid, "text": "Spores +%d" % int(ab["spores"]), "color": "#8dff6a"})
	if ab.has("weak"):
		player.add_status("weak", int(ab["weak"]))

func _approach(e: BUnit, ab: Dictionary) -> void:
	var res := grid.reach(e.pos, eff_move(e), _occupied(e), e.terrain_costs)
	var best: Vector2i = e.pos
	var best_key := _approach_key(e, ab, e.pos, 0)
	for p in res["cost"]:
		var k := _approach_key(e, ab, p, int(res["cost"][p]))
		if k < best_key:
			best_key = k
			best = p
	if best != e.pos:
		_move_along(e, BGrid.path_from(res["prev"], e.pos, best))

func _approach_key(e: BUnit, ab: Dictionary, p: Vector2i, cost: int) -> int:
	var d := BGrid.dist(p, player.pos)
	var in_r := _in_range(e, ab, p)
	var bonus_grass := 0 if grid.is_grass(p) else 1
	if in_r:
		# prefer the farthest tile that is still in range (ranged units keep distance), then cheap tiles
		# melee: flank - prefer to strike from the player's side/back (we may need to walk around)
		var flank := 0
		if int(ab.get("range", 1)) <= 1:
			match facing_dir(p, player):
				"back":
					flank = -6
				"side":
					flank = -3
		return -1000 + cost * 2 + bonus_grass + flank + (0 if int(ab.get("range", 1)) <= 1 else -d)
	return d * 10 + cost

func _flee(e: BUnit, tiles: int) -> void:
	var res := grid.reach(e.pos, tiles, _occupied(e), e.terrain_costs)
	var best: Vector2i = e.pos
	var best_d := BGrid.dist(e.pos, player.pos)
	for p in res["cost"]:
		var d := BGrid.dist(p, player.pos)
		if d > best_d:
			best_d = d
			best = p
	if best != e.pos:
		_move_along(e, BGrid.path_from(res["prev"], e.pos, best))

func _spawn_near(e: BUnit, id: String) -> void:
	var occ := _occupied()
	var spots := []
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var p := e.pos + Vector2i(dx, dy)
			if grid.in_bounds(p) and not grid.blocks_move(p) and not occ.has(p) and p != player.pos:
				spots.append(p)
	if spots.is_empty():
		return
	var u := _make_enemy(id)
	u.pos = spots[rng.randi() % spots.size()]
	u.home = u.pos
	u.aware = true
	u.last_seen = player.pos
	u.vis_pos = Vector2(u.pos)
	u.vis_hp = u.hp
	u.meter = 40.0
	units.append(u)
	enemies.append(u)
	ev({"t": "spawn", "unit": u.uid})
	log_line("%s emerges!" % u.display_name)

# ------------------------------------------------------------------ pre-fight stealth

## Probability that sneaking past an unaware room succeeds (shown to the player).
static func sneak_chance(run_: RunState, room_: Dictionary) -> float:
	var enemies_: Array = room_.get("enemies", [])
	var w := run_.weather_id()
	var chance := 0.75 + float(WeatherSys.mods_for(w, run_.tags())["sneak_bonus"])
	var mult_sum := 0.0
	for id in enemies_:
		var d: Dictionary = DB.enemy(String(id))
		mult_sum += float(WeatherSys.mods_for(w, d.get("tags", []))["perception_mult"])
	if not enemies_.is_empty():
		var avg := mult_sum / enemies_.size()
		chance -= 0.5 * (avg - 1.0)
		chance -= 0.07 * (enemies_.size() - 1)
	return clampf(chance, 0.1, 0.95)
