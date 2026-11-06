class_name Settings
extends RefCounted
## Player settings, persisted in a user config file (user://settings.cfg; separate from the run save).
## pixel_perfect (default ON): the 640x360 native canvas is scaled by a WHOLE number (2x at 720p, 3x at 1080p, 4x at 1440p, 6x at 4K) and
## the rest of the window is black bars; OFF = fractional scale that fills the window (aspect kept). See Main.scale_for.

static var path: String = "user://settings.cfg"
static var persist: bool = true
static var pixel_perfect: bool = true
static var fullscreen: bool = false
static var volume: int = 80          # master volume 0..100
## Intro story cutscene (after the egg customization): 0 = play at the start of every run, 1 = first time only, 2 = never.
## It is skippable at any moment either way. `intro_seen` remembers that it has been shown (or skipped) once.
const INTRO_NAMES := ["Always", "First time only", "Off"]
static var intro_mode: int = 0
static var intro_seen: bool = false

static func load_settings() -> void:
	pixel_perfect = true
	fullscreen = false
	volume = 80
	intro_mode = 0
	intro_seen = false
	var cf := ConfigFile.new()
	if cf.load(path) == OK:
		pixel_perfect = bool(cf.get_value("display", "pixel_perfect", true))
		fullscreen = bool(cf.get_value("display", "fullscreen", false))
		volume = clampi(int(cf.get_value("audio", "master", 80)), 0, 100)
		intro_mode = clampi(int(cf.get_value("story", "intro_mode", 0)), 0, 2)
		intro_seen = bool(cf.get_value("story", "intro_seen", false))
	apply_audio()

static func save_settings() -> void:
	if not persist:
		return
	var cf := ConfigFile.new()
	cf.set_value("display", "pixel_perfect", pixel_perfect)
	cf.set_value("display", "fullscreen", fullscreen)
	cf.set_value("audio", "master", volume)
	cf.set_value("story", "intro_mode", intro_mode)
	cf.set_value("story", "intro_seen", intro_seen)
	cf.save(path)

static func set_pixel_perfect(on: bool) -> void:
	pixel_perfect = on
	save_settings()

static func set_fullscreen(on: bool) -> void:
	fullscreen = on
	save_settings()

static func set_volume(v: int) -> void:
	volume = clampi(v, 0, 100)
	apply_audio()
	save_settings()

static func set_intro_mode(v: int) -> void:
	intro_mode = clampi(v, 0, 2)
	save_settings()

static func mark_intro_seen() -> void:
	if intro_seen:
		return
	intro_seen = true
	save_settings()

## Should a new run open with the story cutscene?
static func should_play_intro() -> bool:
	return intro_mode == 0 or (intro_mode == 1 and not intro_seen)

## Master bus volume (0 = muted). The prototype has little audio yet; the setting is real and persisted.
static func apply_audio() -> void:
	var idx := AudioServer.get_bus_index("Master")
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(float(volume) / 100.0) if volume > 0 else -80.0)
		AudioServer.set_bus_mute(idx, volume <= 0)
