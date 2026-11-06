extends Control
## Screen host. Builds the theme, routes screens, handles CLI flags (--tour for screenshots).

const SCREENS := {
	"menu": preload("res://scripts/ui/screens/MenuScreen.gd"),
	"egg": preload("res://scripts/ui/screens/EggScreen.gd"),
	"customize": preload("res://scripts/ui/screens/CustomizeScreen.gd"),
	"intro_cutscene": preload("res://scripts/ui/screens/CutsceneScreen.gd"),
	"stage_intro": preload("res://scripts/ui/screens/StageIntroScreen.gd"),
	"battle": preload("res://scripts/ui/screens/BattleScreen.gd"),
	"reward": preload("res://scripts/ui/screens/RewardScreen.gd"),
	"branch": preload("res://scripts/ui/screens/BranchScreen.gd"),
	"item": preload("res://scripts/ui/screens/ItemScreen.gd"),
	"draft": preload("res://scripts/ui/screens/DraftScreen.gd"),
	"event": preload("res://scripts/ui/screens/EventScreen.gd"),
	"puzzle": preload("res://scripts/ui/screens/PuzzleScreen.gd"),
	"gameover": preload("res://scripts/ui/screens/GameOverScreen.gd"),
}

const UI_SIZE := Vector2(640, 360)    # the native pixel canvas (Sea-of-Stars format); the window shows it integer-scaled (Settings: Pixel Perfect)
var frame: Control                     # 640x360 native frame (screens live here)
var holder: Control
var current: Control = null
var overlay_layer: Control
var fade_rect: ColorRect
var battle_mode := false              # battle screen / stage intro (kept for the flow; the canvas is the same 640x360 everywhere)

func _ready() -> void:
	Settings.load_settings()
	theme = UITheme.build_theme()
	Game.main = self
	get_window().title = Game.title()
	UITheme.full_rect(self)
	frame = Control.new()
	frame.size = UI_SIZE
	frame.custom_minimum_size = UI_SIZE
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	holder = Control.new()
	UITheme.full_rect(holder)
	frame.add_child(holder)
	overlay_layer = Control.new()
	UITheme.full_rect(overlay_layer)
	overlay_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(overlay_layer)
	fade_rect = ColorRect.new()
	fade_rect.color = Color(0.02, 0.02, 0.05, 1.0)
	UITheme.full_rect(fade_rect)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.modulate = Color(1, 1, 1, 0)
	add_child(fade_rect)
	get_window().size_changed.connect(_relayout)
	_relayout()
	var args := OS.get_cmdline_user_args()
	if not ("--tour" in args or "--selftest" in args or "--gallery" in args) and DisplayServer.get_name() != "headless":
		_fit_window()
		if Settings.fullscreen:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	if "--selftest" in args:
		_selftest()
		return
	show_screen(Game.first_screen_name())
	if "--gallery" in args:
		var gal = load("res://tests/Gallery.gd").new()
		add_child(gal)
		gal.run(self, args)
		return
	if "--tour" in args:
		var tour = load("res://tests/Tour.gd").new()
		add_child(tour)
		tour.run(self, args)

## The window always shows the 640x360 canvas (stretch mode viewport: it is rendered at 640x360 and scaled up with nearest filtering).
## Pixel Perfect on: whole-number scale + black bars (letterbox / pillarbox) so pixels stay square; off: fractional scale that fills the window.
func _relayout() -> void:
	apply_display()
	frame.position = Vector2.ZERO
	Hints.offset = frame.position
	queue_redraw()

func apply_display() -> void:
	var w := get_window()
	w.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	w.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER if Settings.pixel_perfect else Window.CONTENT_SCALE_STRETCH_FRACTIONAL
	if w.content_scale_size != Vector2i(UI_SIZE):
		w.content_scale_size = Vector2i(UI_SIZE)

## Pure: how a window of `win` pixels shows the 640x360 canvas. Returns {s: scale (int when pixel perfect), content: Vector2 size on screen,
## bars: Vector2 black margin on each side (x = pillarbox, y = letterbox)}.
static func scale_for(win: Vector2, pixel_perfect: bool = true) -> Dictionary:
	var fit := minf(win.x / UI_SIZE.x, win.y / UI_SIZE.y)
	var s := maxf(1.0, floorf(fit)) if pixel_perfect else maxf(0.01, fit)
	var content := UI_SIZE * s
	return {"s": s, "content": content, "bars": ((win - content) * 0.5).floor()}

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size), Color("#05080d"))

## Start windowed at a sensible size: the largest whole multiple of 960x540 that fits in 90% of the display (so it never
## overflows the screen and pixels stay crisp). F11 toggles fullscreen.
func _fit_window() -> void:
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		return
	var sc := DisplayServer.screen_get_size()
	var usable := DisplayServer.screen_get_usable_rect().size
	if usable.x > 0:
		sc = usable
	var m := maxi(2, int(floor(minf(float(sc.x) * 0.92 / UI_SIZE.x, float(sc.y) * 0.88 / UI_SIZE.y))))
	var ws := Vector2i(int(UI_SIZE.x) * m, int(UI_SIZE.y) * m)
	DisplayServer.window_set_min_size(Vector2i(int(UI_SIZE.x), int(UI_SIZE.y)))
	DisplayServer.window_set_size(ws)
	var sp := DisplayServer.screen_get_position()
	DisplayServer.window_set_position(sp + (sc - ws) / 2)

func toggle_fullscreen() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		_fit_window()
		Settings.set_fullscreen(false)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		Settings.set_fullscreen(true)

## Settings panel (gear button / Esc). HUD size etc. apply live.
func open_settings() -> void:
	if settings_open():
		return
	var so := SettingsOverlay.new()
	so.close_requested.connect(close_settings)
	so.apply_requested.connect(apply_settings)
	so.fullscreen_requested.connect(toggle_fullscreen)
	overlay_layer.add_child(so)

func close_settings() -> void:
	for c in overlay_layer.get_children():
		if c is SettingsOverlay:
			c.queue_free()
			overlay_layer.remove_child(c)

func settings_open() -> bool:
	for c in overlay_layer.get_children():
		if c is SettingsOverlay and not c.is_queued_for_deletion():
			return true
	return false

## Re-applies the HUD size (and everything derived from the window size) right now.
func apply_settings() -> void:
	_relayout()
	call_deferred("_relayout")

func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F11:
		toggle_fullscreen()
		if settings_open():
			for c in overlay_layer.get_children():
				if c is SettingsOverlay:
					c.refresh()
		get_viewport().set_input_as_handled()
	elif e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		if settings_open():
			close_settings()
		else:
			open_settings()
		get_viewport().set_input_as_handled()

## The battle HUD scale is used by the battle screen and by the stage-intro cinematic (which pans down onto the battle screen).
func set_battle_mode(on: bool) -> void:
	battle_mode = on

var popup_node: Control = null

## Show a post-fight screen (reward / draft / item / branch) as a popup panel over the current battle board.
func show_popup(name: String, args: Dictionary = {}) -> void:
	clear_popup()
	Hints.clear()
	var s: Control = SCREENS[name].new()
	s.set("args", args)
	s.set("popup", true)
	UITheme.full_rect(s)
	s.name = name
	current.add_child(s)
	popup_node = s

func clear_popup() -> void:
	if popup_node != null and is_instance_valid(popup_node):
		popup_node.get_parent().remove_child(popup_node)
		popup_node.queue_free()
	popup_node = null

## True when a won battle's board is on screen, i.e. the next reward-type screen should be a popup over it.
func popup_context() -> bool:
	return current != null and current.name == "battle" and current.get("battle") != null and current.battle.phase == "won"

## Make an already built screen (the battlefield the cinematic ended on) the current one - no rebuild, no fade, no flicker.
func adopt_screen(node: Control, name: String) -> void:
	var old := current
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	if old != null:
		holder.remove_child(old)
		old.queue_free()
	set_battle_mode(name == "battle")
	node.name = name
	holder.add_child(node)
	current = node

func show_screen(name: String, args: Dictionary = {}) -> void:
	popup_node = null
	if current != null:
		holder.remove_child(current)   # leave the tree now so the new screen can take the same node name
		current.queue_free()
		current = null
	Hints.clear()
	set_battle_mode(name == "battle" or name == "stage_intro")
	var s: Control = SCREENS[name].new()
	s.set("args", args)
	UITheme.full_rect(s)
	s.name = name
	holder.add_child(s)
	current = s
	s.modulate = Color(1, 1, 1, 0)
	var tw := create_tween()
	tw.tween_property(s, "modulate:a", 1.0, 0.18)
	if fade_rect != null and fade_rect.modulate.a > 0.0:
		tw.parallel().tween_property(fade_rect, "modulate:a", 0.0, 0.3)

## Short fade to black used when walking through an exit (the next screen fades back in, see show_screen).
func fade_out(t: float = 0.25) -> void:
	var tw := create_tween()
	tw.tween_property(fade_rect, "modulate:a", 1.0, t)
	await tw.finished

func open_deck_overlay() -> void:
	for c in overlay_layer.get_children():
		c.queue_free()
	var o := DeckOverlay.new()
	overlay_layer.add_child(o)

## `--selftest`: simulate full runs with the bot using the exported data/logic, then quit.
## Lets us verify an exported build without a display:  ./PrimalInstinct.x86_64 --headless -- --selftest
func _selftest() -> void:
	var wins := 0
	var rooms := 0
	var n := 25
	for s in range(1, n + 1):
		var r := RunSimulator.simulate(s)
		rooms += int(r["rooms"])
		if r["victory"]:
			wins += 1
	print("SELFTEST ok: %d runs, %d victories, avg %.1f rooms, data tables loaded: %d" % [n, wins, float(rooms) / n, DB.TABLES.size()])
	get_tree().quit(0)
