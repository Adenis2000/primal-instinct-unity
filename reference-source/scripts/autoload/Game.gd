extends Node
## Autoload: owns the current run, the persistent save and screen routing.

const SAVE_PATH := "user://save.json"

var run: RunState = null
var save: Dictionary = {}
var main: Node = null            # Main.gd (screen host), set by Main
var battle: Battle = null        # active battle (kept across screens for the reward flow)
var battle_result: Dictionary = {}
var field: Battle = null          # the last battlefield (explore view) so the cave can lead back to it
var persist_enabled: bool = true # tests turn this off

func _ready() -> void:
	DB.load_all()
	load_save()

func default_save() -> Dictionary:
	return {"first_run_complete": false, "hints_seen": {}, "hints_enabled": true, "last_seed": 0, "runs": 0, "wins": 0, "best_stage": 0}

func load_save() -> void:
	save = default_save()
	if not persist_enabled:
		return
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			for k in d:
				save[k] = d[k]

func write_save() -> void:
	if not persist_enabled:
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(save, "\t"))

func reset_save() -> void:
	save = default_save()
	write_save()

# ------------------------------------------------------------------ run lifecycle

func start_run(species_id: String, seed_in: int = 0, look: Dictionary = {}) -> RunState:
	run = RunState.create(species_id, seed_in)
	run.look = Look.sanitize(look, species_id)       # cosmetic only (see Look.gd): never touches stats or the run RNG
	SpriteFactory.set_look(run.look)
	var dl := String(save.get("difficulty", String(DB.table("difficulty")["default"])))
	run.difficulty = dl if DB.table("difficulty")["levels"].has(dl) else String(DB.table("difficulty")["default"])
	run.begin_stage(0)
	battle = null
	save["last_seed"] = run.seed_val
	write_save()
	return run

## Called once when a run ends (death or victory). Hints stop after the first completed run.
func end_run() -> void:
	if run == null:
		return
	save["runs"] = int(save.get("runs", 0)) + 1
	save["first_run_complete"] = true
	if run.victory:
		save["wins"] = int(save.get("wins", 0)) + 1
	save["best_stage"] = maxi(int(save.get("best_stage", 0)), run.stage_idx + 1)
	write_save()

func main_screen_names() -> Array:
	return load("res://scripts/ui/Main.gd").SCREENS.keys()

## The game's (placeholder) name lives in data/game.json: change it there and run tools/apply_title.py.
static func title() -> String:
	return String(DB.table("game").get("title", "Primal Instinct"))

static func version() -> String:
	return String(DB.table("game").get("version", "0.1.0"))

## First screen after launch: the main menu (the bot sim / scripted tests set `bypass_menu` and start on the egg screen instead).
var bypass_menu: bool = false

func first_screen_name() -> String:
	return "egg" if bypass_menu else "menu"

static func tagline() -> String:
	return String(DB.table("game").get("tagline", ""))

## Set by the bot sim / scripted tests: the intro story cutscene never plays.
var bypass_cutscene: bool = false

## Screen that follows the egg customization: the story cutscene (when the player wants it), else the stage-intro cinematic.
func intro_screen_name() -> String:
	if bypass_cutscene or not Settings.should_play_intro():
		return "stage_intro"
	return "intro_cutscene"

func goto(screen: String, args: Dictionary = {}) -> void:
	if screen == "encounter":      # legacy name: there is no pre-fight screen any more, you arrive on the board
		enter_battle(args["room"])
		return
	if main != null:
		if screen in ["reward", "draft", "item", "branch"] and main.popup_context():
			main.show_popup(screen, args)
		else:
			main.show_screen(screen, args)

# ------------------------------------------------------------------ flow

## Room finished (rewards done). Decides where to go next.
func finish_room() -> void:
	if run.game_over:
		goto("gameover")
		return
	if run.pending_evolution_tier > 0:
		run_drafts(["branch", "evolution"])
		return
	if String(run.current_room.get("type", "")) == "cave":
		start_explore()   # the secret cave does not use up a step: back to the gates of the room you came from
		return
	var r := run.complete_room()
	if r == "stage_clear":
		if run.advance_stage():
			goto("stage_intro")
		else:
			goto("gameover")
	else:
		start_explore()

## Show the battlefield with the exits (gates) of the current step; the player walks to / clicks the one to take.
## Reuses the previous battlefield (same stage) so the exits appear where you just fought.
func start_explore() -> void:
	prepare_explore()
	goto("battle", {"explore": true})

## Builds (and stores) the explore battlefield without showing it (the stage-intro cinematic pans down onto it).
func prepare_explore() -> void:
	var prev: Battle = battle if battle != null and battle.run == run else null
	if prev != null and String(prev.room.get("type", "")) == "cave":
		prev = field if field != null and field.run == run else null
	battle = Battle.create_explore(run, prev)
	field = battle

var fading: bool = false

## Exit chosen on the battlefield: short fade, then the room opens.
func take_exit(i: int) -> void:
	if fading:
		return
	fading = true
	if main != null:
		await main.fade_out()
	fading = false
	choose_exit(i)

func take_secret() -> void:
	if fading:
		return
	fading = true
	if main != null:
		await main.fade_out()
	fading = false
	enter_secret()

## Take exit `i` of the current step: hunger cost, then the room opens (short fade handled by Main).
func choose_exit(i: int) -> void:
	var room := run.choose_door(i)
	var notes := run.enter_room(room)
	battle_result = {"notes": notes}
	_open_room(room)

func _open_room(room: Dictionary) -> void:
	if run.game_over:
		goto("gameover")
		return
	match String(room["type"]):
		"battle", "elite", "boss", "cave":
			enter_battle(room)
		"event", "forage":
			goto("event", {"room": room})
		"puzzle":
			goto("puzzle", {"room": room})

## There is no pre-fight screen: you arrive on the board. Enemies that have not noticed you stay idle (you may Move closer and
## ambush them for a free first hit, or slip out an exit); enemies that already spotted you show a "!" and the fight starts.
func enter_battle(room: Dictionary) -> void:
	var mode := "ambush" if bool(room.get("unspotted_allowed", false)) else "spotted"
	battle = Battle.create(run, room, mode)
	var notes: Array = battle_result.get("notes", [])
	if not notes.is_empty():
		battle.log_line(String(notes[0]))
	battle.begin()
	goto("battle", {"room": room})

## Reached an exit while unseen: the room counts as sneaked past (no spoils).
func sneak_out() -> void:
	if fading:
		return
	fading = true
	run.stats["sneaks"] += 1
	Battle.pending_unlock = true
	if battle != null:
		battle.commit_to_run()
	if main != null:
		await main.fade_out()
	fading = false
	finish_room()

## The secret cave entrance inside the area: a spider den. Costs the usual room hunger but does NOT consume the step.
func enter_secret() -> void:
	var room := StageGen.make_cave_room(run)
	run.stage["secret_used_step"] = int(run.stage["step"])
	run.stats["caves"] = int(run.stats.get("caves", 0)) + 1
	var notes := run.enter_room(room)
	battle_result = {"notes": notes}
	_open_room(room)

## Cave clear bonus (data: stages.json secret.reward): extra food (+ the item choice, see after_reward). Returns lines.
func apply_cave_reward(room: Dictionary) -> Array:
	var rw: Dictionary = room.get("reward", {})
	var lines: Array = []
	var food := int(rw.get("hunger", 0))
	if food > 0:
		run.change_hunger(food)
		lines.append("The spiders' larder: +%d hunger" % food)
	return lines

## Start a draft chain: each entry is a draft mode. Empty queue finishes the room.
func run_drafts(queue: Array) -> void:
	if queue.is_empty():
		finish_room()
		return
	var q := queue.duplicate()
	var mode: String = q.pop_front()
	if mode == "branch":
		var tier := maxi(run.pending_evolution_tier, run.tier())
		if run.branch_options(tier).is_empty():
			run_drafts(q)
		else:
			goto("branch", {"queue": q})
		return
	if mode.begins_with("item:"):
		var offers := run.offer_items(mode.substr(5))
		if offers.is_empty():
			run_drafts(q)
			return
		goto("item", {"source": mode.substr(5), "offers": offers, "queue": q})
		return
	goto("draft", {"mode": mode, "queue": q})

## After a battle was won and rewards were collected.
func after_reward(room_type: String) -> void:
	run_drafts(reward_queue(room_type))

## The chain of screens after a won room: evolution, card drafts, item rewards (drop / choice of 3).
func reward_queue(room_type: String) -> Array:
	var q: Array = []
	if run.pending_evolution_tier > 0:
		q.append_array(["branch", "evolution"])
	match room_type:
		"battle":
			q.append("normal")
			if run.item_drop("battle"):
				q.append("item:battle")
		"elite":
			q.append("elite")
			if run.item_drop("elite"):
				q.append("item:elite")
		"boss":
			q.append("elite")
			q.append("item:boss")      # a main boss always drops a choice of 3
		"cave":
			for m in run.current_room.get("reward", {}).get("drafts", ["cave"]):
				q.append(String(m))
			q.append("item:cave")
	return q

## Build the transient room used by event-triggered fights.
func make_event_battle_room(spec: Dictionary) -> Dictionary:
	var enemies: Array = spec["enemies"]
	var infected: Array = []
	for e in enemies:
		infected.append(bool(DB.enemy(String(e)).get("infected", false)))
	return {"type": "battle", "enemies": enemies, "infected": infected, "seed": run.rng.randi(), "unspotted_allowed": bool(spec.get("unspotted", false)), "trap": not bool(spec.get("unspotted", false)), "event_battle": true, "teach": ""}
