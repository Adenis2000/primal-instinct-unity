class_name BUnit
extends RefCounted
## A combatant on the battle grid (player or enemy).

var uid: int = 0
var id: String = ""
var display_name: String = ""
var is_player: bool = false
var tags: Array = []
var max_hp: int = 1
var hp: int = 1
var base_speed: float = 10.0
var move: int = 3
var perception: float = 3.0
var pos: Vector2i = Vector2i.ZERO
var terrain_costs: Dictionary = {}   # {tile_id: move cost} overrides from traits (aquatic...) / def "terrain_cost"; see data/tiles.json "traits"
var facing: Vector2i = Vector2i(1, 0)   # persists between turns; one of the 4 grid axes
var turns_left: int = 99                 # quarter-turns this unit may still make this turn (slow turners: 1)
var block: int = 0
var meter: float = 0.0           # turn meter (0..METER)
var state: String = "idle"       # enemy awareness: idle (roaming) | spotted (hunting you) | searching (lost you, checking last seen spot)
## `aware` is a view of `state`: true only while spotted. Assigning false drops a spotted enemy back to idle.
var aware: bool:
	get:
		return state == "spotted"
	set(v):
		if v:
			state = "spotted"
		elif state == "spotted":
			state = "idle"
var last_seen: Vector2i = Vector2i(-1, -1)   # where this enemy last saw the player (-1,-1 = never)
var home: Vector2i = Vector2i(-1, -1)        # idle enemies wander around this tile
var roam_target: Vector2i = Vector2i(-1, -1)
var search_phase: String = "go"              # searching: "go" (walk to last_seen) then "scan" (look around)
var scan_left: int = 0
var alive: bool = true
var infected: bool = false
var immune_to_infection: bool = false
var spreader: bool = false
var bonus_damage: int = 0
var speed_bonus: float = 0.0
var status: Dictionary = {}      # bleed, weak, expose, stun, spores
var abilities: Array = []
var ability_idx: int = 0
var def: Dictionary = {}
var sprite_id: String = ""
var sprite_px: int = 16
var spread_cd: int = 1
var turns_taken: int = 0
var summon_cd: int = 0
var windup: Dictionary = {}          # telegraphed heavy attack being charged (ability dict); fires on this unit's next turn
var windup_tiles: Array = []         # tiles the charged attack will hit (shown as red danger tiles)
var surprise_ready: bool = false     # just noticed you from hiding: its first strike gets def.surprise bonus damage
var retreated: bool = false          # already used its "retreat when hurt" (def.retreat_hp)
var phase_done: Array = []           # indices of def.phases already triggered
var armor: int = 0                   # flat damage taken off hits from the front (expose ignores it)
# presentation state (updated by the UI as it replays events)
var vis_pos: Vector2 = Vector2.ZERO
var vis_facing: Vector2i = Vector2i(1, 0)
var vis_hp: int = 1
var vis_dead: bool = false
var vis_flash: float = 0.0
var vis_alpha: float = 1.0
var vis_infected: bool = false
var vis_aware: bool = false
var vis_alert: float = 0.0               # seconds left of the red "!" over a unit that just spotted the player (fades out)
var vis_state: String = "idle"
var vis_off: Vector2 = Vector2.ZERO      # screen-pixel offsets for lunge/shake/recoil (always 0 at rest)
var vis_lift: float = 0.0                # hop / leap height in px (always 0 at rest)
var vis_squash: float = 0.0              # 0..1 death collapse
var vis_windup: Array = []              # danger tiles of the attack this unit is charging (presentation copy of windup_tiles)
var vis_pulse: float = 0.0               # status pulse ring (0..1 running)
var vis_pulse_col: Color = Color.WHITE

func is_boss() -> bool:
	return bool(def.get("boss", false))

func st(name: String) -> int:
	return int(status.get(name, 0))

func add_status(name: String, amount: int) -> void:
	status[name] = st(name) + amount

func next_ability() -> Dictionary:
	if abilities.is_empty():
		return {}
	return abilities[ability_idx % abilities.size()]

func facing_trait() -> Dictionary:
	return def.get("facing", {})

func slow_turn() -> bool:
	return String(facing_trait().get("turn", "")) == "slow"
