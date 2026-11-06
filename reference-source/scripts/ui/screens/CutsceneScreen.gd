extends ScreenBase
## Intro story cutscene: plays after the egg customization, before the weather / Stage-1 intro. ~48 s, no voice, pixel art with
## letterbox bars, fades, camera pans, shakes and short captions. The shots come from data/cutscene_intro.json (CutsceneView draws them).
##
## Skippable at any moment (even on the first play):
##   - Esc / Space / Enter                      -> skip at once,
##   - hold ANY other key or the mouse button   -> a bar fills (skip_hold seconds), then it skips,
##   - the "Skip" button (stone-wood style) in the bottom-right corner.
## Skipping (or the end) goes to the stage-intro cinematic. Settings -> "Intro story cutscene" = Always / First time only / Off.

var view: CutsceneView = null
var t: float = 0.0
var total: float = 0.0
var finished: bool = false
var skipping: bool = false
var skip_btn: Button = null
var hold: float = 0.0
var hold_time: float = 0.6
var _held_keys: Dictionary = {}
var _mouse_down: bool = false
var _skip_t: float = 0.0

func _ready() -> void:
	Hints.suspended = true
	view = CutsceneView.new()
	view.name = "CutsceneView"
	add_child(view)
	total = CutsceneView.total_time(view.tl)
	hold_time = float(view.tl.get("skip_hold", 0.6))
	skip_btn = UITheme.button("Skip", 15, Vector2(48, 16))
	skip_btn.name = "skip_btn"
	skip_btn.size = Vector2(48, 16)
	skip_btn.tooltip_text = "Skip the intro story (Esc / Space / Enter, or hold any key)"
	skip_btn.pressed.connect(func(): skip())
	add_child(skip_btn)
	Settings.mark_intro_seen()
	_layout()
	view.seek(0.0)

func _exit_tree() -> void:
	Hints.suspended = false

## The control is sized to the real viewport (not just the 640x360 frame); the frame origin is where this screen sits.
func _layout() -> void:
	var vp := get_viewport_rect().size
	var gp := global_position.round()
	view.position = -gp
	view.size = vp
	view.origin = gp
	var bh := CutsceneView.bar_height(vp, view.tl)
	skip_btn.position = Vector2(vp.x - 56.0, vp.y - bh * 0.5 - 8.0) - gp

func _process(dt: float) -> void:
	if finished:
		return
	_layout()
	if skipping:
		_skip_t += dt
		view.extra_black = clampf(_skip_t / 0.25, 0.0, 1.0)
		view.queue_redraw()
		if _skip_t >= 0.25:
			_finish()
		return
	t = minf(t + dt, total)
	var holding := not _held_keys.is_empty() or _mouse_down
	hold = clampf(hold + (dt if holding else -dt * 2.0), 0.0, hold_time)
	view.skip_progress = hold / hold_time if hold > 0.0 else 0.0
	view.show_prompt = clampf(1.0 - t / 6.0, 0.35, 1.0) if not holding else 1.0
	view.advance_to(t)
	if hold >= hold_time:
		skip()
	elif t >= total:
		_finish()

func _input(e: InputEvent) -> void:
	if finished or skipping:
		return
	if e is InputEventKey:
		if e.pressed and not e.echo:
			if e.keycode in [KEY_ESCAPE, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
				get_viewport().set_input_as_handled()      # Esc must not open the Settings panel over the cutscene
				skip()
			elif e.keycode != KEY_F11:
				_held_keys[e.keycode] = true
				get_viewport().set_input_as_handled()
		elif not e.pressed:
			_held_keys.erase(e.keycode)
	elif e is InputEventMouseButton:
		if e.pressed:
			if skip_btn != null and skip_btn.get_global_rect().has_point(e.position):
				return                                     # the Skip button handles its own click
			_mouse_down = true
			get_viewport().set_input_as_handled()
		else:
			_mouse_down = false
	elif e is InputEventScreenTouch:
		_mouse_down = e.pressed

## Skip to the stage intro (quick fade to black). `instant` finishes in the same frame (tests / scripted flows).
func skip(instant: bool = false) -> void:
	if finished:
		return
	if instant:
		_finish()
		return
	skipping = true
	_skip_t = 0.0

func _finish() -> void:
	if finished:
		return
	finished = true
	if Game.main != null and Game.run != null:
		Game.goto("stage_intro")
	elif Game.main != null:
		Game.main.show_screen("egg")

## Frame capture helper (tour / tests): freeze the clock at global time `tt` and draw that frame.
func show_at(tt: float) -> void:
	set_process(false)
	t = tt
	_layout()
	view.skip_progress = 0.0
	view.seek(tt)
