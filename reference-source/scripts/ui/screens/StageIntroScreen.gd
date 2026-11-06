extends ScreenBase
## Stage-intro cinematic (start of the run and between stages):
##  1. animated sky shot themed to the rolled weather (SkyView, data/weather.json "sky"),
##  2. the stage name + weather name and its effects fade in slowly,  3. hold, then fade out,
##  4. the camera tilts down from the sky onto the battlefield (the real BattleScreen, built underneath) and the sequence ends in
##     exactly the normal gameplay framing - the finished BattleScreen is simply adopted by Main.
## Any key or click skips straight to the end. Timings are constants below (seconds).

const T_BLACK := 0.7            # fade in from black
const T_TITLE_IN := 0.9         # stage name starts to fade in
const T_WEATHER_IN := 2.0       # weather name + effects start to fade in
const FADE_IN := 1.7
const T_OUT := 5.8              # hold ends, text fades out
const FADE_OUT := 1.0
const T_PAN := 6.4              # camera tilt down
const PAN_DUR := 2.6
const T_END := T_PAN + PAN_DUR

var t := 0.0
var finished := false
var sky: SkyView = null
var world: Control = null
var scr: Control = null         # the BattleScreen shown at the end
var title_group: Control = null
var weather_group: Control = null
var skip_label: Label = null
var black: ColorRect = null
var veil: Control = null
var _hud_nodes: Array = []
var pan_p := 0.0                # 0 = sky shot, 1 = gameplay framing

func _ready() -> void:
	var r: RunState = Game.run
	var def := r.stage_def()
	var wid := r.weather_id()
	var theme_id := String(def.get("theme", "jungle"))
	if Game.main != null:
		Game.main.set_battle_mode(true)
	Hints.suspended = true
	# --- the battlefield the camera ends on (built now, hidden under the sky)
	world = Control.new()
	UITheme.full_rect(world)
	world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(world)
	if Game.main != null:
		Game.prepare_explore()
		scr = load("res://scripts/ui/screens/BattleScreen.gd").new()
		scr.set("args", {"explore": true})
		UITheme.full_rect(scr)
		scr.name = "battle"
		world.add_child(scr)
	# --- sky
	sky = SkyView.new()
	sky.name = "Sky"
	sky.weather_id = wid
	sky.theme_id = theme_id
	add_child(sky)
	# --- text
	veil = Control.new()
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)
	title_group = Control.new()
	title_group.name = "TitleText"
	title_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title_group)
	weather_group = Control.new()
	weather_group.name = "WeatherText"
	weather_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(weather_group)
	_build_text(r, def, wid)
	black = ColorRect.new()
	black.color = Color(0.02, 0.02, 0.05, 1.0)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)
	if scr != null and scr.has_method("get_children"):
		var board = scr.get("board")
		for c in scr.get_children():
			if c != board and not (c is ColorRect):
				_hud_nodes.append(c)
	_apply(0.0)

func _exit_tree() -> void:
	Hints.suspended = false

func _outline(l: Label) -> Label:
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 3)
	return l

func _line(parent: Control, text: String, y: float, size: int, color: Color, h: float = 0.0) -> Label:
	var l := _outline(UITheme.label(text, size, color, HORIZONTAL_ALIGNMENT_CENTER))
	l.position = Vector2(80, y)
	l.size = Vector2(480, h if h > 0.0 else UITheme.snap(size) + 3)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func _build_text(r: RunState, def: Dictionary, wid: String) -> void:
	var wd: Dictionary = DB.weather(wid)
	var wc := Color(String(wd["color"]))
	_line(title_group, "STAGE %d" % (r.stage_idx + 1), 56, 20, UITheme.C_DIM)
	_line(title_group, String(def["name"]), 72, 40, UITheme.C_GOLD)
	_line(title_group, String(def["subtitle"]), 108, 20, UITheme.C_TEXT)
	var name_l := _line(weather_group, String(wd["name"]), 150, 30, wc)
	var wdt := UITheme.font_for(30).get_string_size(String(wd["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.snap(30)).x
	var ic := UITheme.icon(String(wd["icon"]), 33)
	ic.position = Vector2(roundf(320.0 - wdt * 0.5 - 40.0), 148)
	weather_group.add_child(ic)
	name_l.name = "WeatherName"
	_line(weather_group, String(wd["desc"]), 176, 15, UITheme.C_TEXT, 28)
	var y := 214.0
	for row in effect_rows(r):
		_line(weather_group, ("+ " if row[1] else "- ") + String(row[0]), y, 15, UITheme.C_GREEN if row[1] else Color("#ff8a80"))
		y += 14.0
	skip_label = _outline(UITheme.label("Press any key to skip", 15, UITheme.C_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	skip_label.position = Vector2(0, 342)
	skip_label.size = Vector2(640, 12)
	skip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(skip_label)

## [[text, is_good], ...] - what the rolled weather does to the player.
static func effect_rows(r: RunState) -> Array:
	var rows: Array = []
	var m := r.weather_mods()
	_row(rows, "Enemy sight range", float(m["perception_mult"]), true)
	_row(rows, "Your speed", float(m["speed_mult"]), false)
	_row(rows, "Your damage", float(m["damage_mult"]), false)
	if int(m["hunger_extra"]) != 0:
		rows.append(["+%d hunger per room" % int(m["hunger_extra"]), false])
	if rows.is_empty():
		rows.append(["No direct effect on you (check enemy types in battle)", true])
	return rows

static func _row(rows: Array, label: String, mult: float, lower_is_good: bool) -> void:
	if absf(mult - 1.0) < 0.01:
		return
	var good := (mult < 1.0) if lower_is_good else (mult > 1.0)
	rows.append(["%s x%.2f" % [label, mult], good])

static func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

func _vp() -> Vector2:
	return get_viewport_rect().size

## Sets every moving part for time `tt` (also used by tests / frame captures).
func _apply(tt: float) -> void:
	var vp := _vp()
	var gp := global_position.round()
	sky.position = -gp
	sky.size = vp
	var pan_raw := (tt - T_PAN) / PAN_DUR
	pan_p = _ease(pan_raw)
	var H := vp.y
	var pan_px := roundf(pan_p * H)
	sky.position = Vector2(-gp.x, -gp.y - pan_px)
	sky.visible = pan_p < 1.0
	if scr != null:
		var board = scr.get("board")
		if board != null:
			board.set("pan_y", H - pan_px)
		var ha := _ease((pan_p - 0.55) / 0.45)
		for c in _hud_nodes:
			if is_instance_valid(c):
				c.modulate.a = ha
	var out := 1.0 - clampf((tt - T_OUT) / FADE_OUT, 0.0, 1.0)
	title_group.modulate.a = clampf((tt - T_TITLE_IN) / FADE_IN, 0.0, 1.0) * out
	weather_group.modulate.a = clampf((tt - T_WEATHER_IN) / FADE_IN, 0.0, 1.0) * out
	skip_label.modulate.a = clampf((tt - 2.5) / 1.0, 0.0, 1.0) * 0.8 * (1.0 - pan_p)
	black.position = -gp
	black.size = vp
	black.modulate.a = 1.0 - clampf(tt / T_BLACK, 0.0, 1.0)
	# soft dark band behind the text so it reads on any sky
	veil.queue_redraw()
	var band := (title_group.modulate.a + weather_group.modulate.a) * 0.5
	if veil.get_child_count() == 0:
		for i in 3:
			var rc := ColorRect.new()
			rc.mouse_filter = Control.MOUSE_FILTER_IGNORE
			veil.add_child(rc)
	for i in 3:
		var rc: ColorRect = veil.get_child(i)
		var grow := 40.0 - i * 16.0
		rc.position = Vector2(-gp.x, 50.0 - grow)
		rc.size = Vector2(vp.x, 200.0 + grow * 2.0)
		rc.color = Color(0.0, 0.0, 0.03, 0.09 * band)

func _process(dt: float) -> void:
	if finished:
		return
	t += dt
	_apply(t)
	if t >= T_END:
		_finish()

func _input(e: InputEvent) -> void:
	if finished:
		return
	var go := false
	if e is InputEventKey and e.pressed and not e.echo and e.keycode != KEY_F11:
		go = true
	elif e is InputEventMouseButton and e.pressed:
		go = true
	elif e is InputEventScreenTouch and e.pressed:
		go = true
	if go:
		get_viewport().set_input_as_handled()
		skip()

## Jump straight to the end of the cinematic: the battlefield in its normal framing.
func skip() -> void:
	if finished:
		return
	t = T_END
	_apply(T_END)
	_finish()

func _finish() -> void:
	if finished:
		return
	finished = true
	if scr == null or Game.main == null:
		Game.start_explore()
		return
	var board = scr.get("board")
	if board != null:
		board.set("pan_y", 0.0)
	for c in _hud_nodes:
		if is_instance_valid(c):
			c.modulate.a = 1.0
	Game.main.adopt_screen(scr, "battle")
	Hints.resume()
