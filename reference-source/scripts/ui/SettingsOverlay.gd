class_name SettingsOverlay
extends Control
## Modal settings panel (gear button / Esc): Pixel Perfect (integer scale + bars), fullscreen (F11), intro cutscene, master volume.
## Saved to user://settings.cfg. Laid out for the 640x360 native canvas.

signal close_requested
signal apply_requested
signal fullscreen_requested

var pp_btn: Button
var size_note: Label
var fs_btn: Button
var intro_btn: Button
var vol_slider: HSlider
var vol_label: Label

func _ready() -> void:
	name = "SettingsOverlay"
	UITheme.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.position = Vector2(-1000, -1000)
	dim.size = Vector2(2700, 2400)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	add_child(UITheme.panel(Rect2(110, 36, 420, 288)))
	_label("SETTINGS", Vector2(110, 44), 30, UITheme.C_GOLD, 420, HORIZONTAL_ALIGNMENT_CENTER)
	_label("Pixel Perfect", Vector2(130, 76), 15, UITheme.C_GOLD)
	pp_btn = UITheme.button("", 20, Vector2(200, 24))
	pp_btn.position = Vector2(130, 92)
	pp_btn.size = Vector2(200, 24)
	pp_btn.name = "pixel_perfect_btn"
	pp_btn.tooltip_text = "On: the 640x360 pixel canvas is scaled by a whole number (2x at 720p, 3x at 1080p, 4x at 1440p, 6x at 4K) with black bars. Off: fills the window with a fractional scale."
	pp_btn.pressed.connect(_toggle_pp)
	add_child(pp_btn)
	size_note = _label("", Vector2(130, 120), 15, UITheme.C_DIM, 380)
	_label("Display", Vector2(130, 160), 15, UITheme.C_GOLD)
	fs_btn = UITheme.button("", 20, Vector2(170, 24))
	fs_btn.position = Vector2(130, 176)
	fs_btn.size = Vector2(170, 24)
	fs_btn.name = "fullscreen_btn"
	fs_btn.pressed.connect(_toggle_fs)
	add_child(fs_btn)
	_label("Intro story cutscene", Vector2(318, 160), 15, UITheme.C_GOLD)
	intro_btn = UITheme.button("", 18, Vector2(182, 24))
	intro_btn.position = Vector2(318, 176)
	intro_btn.size = Vector2(182, 24)
	intro_btn.name = "intro_mode_btn"
	intro_btn.tooltip_text = "Whether a new run opens with the short story cutscene (always skippable)."
	intro_btn.pressed.connect(_cycle_intro)
	add_child(intro_btn)
	_label("Master volume", Vector2(130, 212), 15, UITheme.C_GOLD)
	vol_slider = HSlider.new()
	vol_slider.name = "volume_slider"
	vol_slider.min_value = 0
	vol_slider.max_value = 100
	vol_slider.step = 5
	vol_slider.value = Settings.volume
	vol_slider.position = Vector2(130, 232)
	vol_slider.size = Vector2(300, 16)
	vol_slider.value_changed.connect(_set_volume)
	add_child(vol_slider)
	vol_label = _label("", Vector2(442, 228), 20, UITheme.C_TEXT)
	var close := UITheme.button("Close (Esc)", 20, Vector2(110, 24))
	close.position = Vector2(265, 280)
	close.size = Vector2(110, 24)
	close.name = "settings_close"
	close.pressed.connect(func(): close_requested.emit())
	add_child(close)
	get_window().size_changed.connect(refresh)
	refresh()

func _label(text: String, pos: Vector2, size_px: int, col: Color, width: float = 0.0, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := UITheme.label(text, size_px, col, align)
	l.position = pos
	if width > 0.0:
		l.size = Vector2(width, 0)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l

func _toggle_pp() -> void:
	Settings.set_pixel_perfect(not Settings.pixel_perfect)
	apply_requested.emit()
	refresh()

func _toggle_fs() -> void:
	fullscreen_requested.emit()
	refresh()

func _cycle_intro() -> void:
	Settings.set_intro_mode((Settings.intro_mode + 1) % 3)
	refresh()

func _set_volume(v: float) -> void:
	Settings.set_volume(int(v))
	refresh()

## Re-style the controls and describe what the current choice means for this window.
func refresh() -> void:
	UITheme.set_selected(pp_btn, Settings.pixel_perfect)
	pp_btn.text = "Pixel Perfect: %s" % ("On" if Settings.pixel_perfect else "Off")
	var win := Vector2(get_window().size)
	var mn: GDScript = load("res://scripts/ui/Main.gd")
	var r: Dictionary = mn.scale_for(win, Settings.pixel_perfect)
	if Settings.pixel_perfect:
		size_note.text = "Now: %dx pixel scale%s." % [int(r["s"]), (", black bars %dx%d px" % [int(r["bars"].x), int(r["bars"].y)]) if r["bars"] != Vector2.ZERO else ""]
	else:
		size_note.text = "Now: %.2fx fractional scale (fills the window, pixels may shimmer)." % float(r["s"])
	fs_btn.text = "Fullscreen: %s  (F11)" % ("On" if Settings.fullscreen else "Off")
	intro_btn.text = "Intro: %s" % Settings.INTRO_NAMES[Settings.intro_mode]
	vol_label.text = "%d%%" % Settings.volume
