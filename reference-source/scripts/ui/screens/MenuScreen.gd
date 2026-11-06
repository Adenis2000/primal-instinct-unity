extends ScreenBase
## Main menu: the first screen on launch (before the egg selection). Title (Game.title(), data/game.json) in big pixel letters,
## stone-wood buttons Play / Settings / Quit (Quit is hidden on the Web build), over a layered forest scene (MenuForest: canopy, tree
## lines, bushes, ferns, rocks / logs, iso grass floor, parallax, slow falling leaves).
## Keyboard: Up/Down (or W/S) move the selection, Enter / Space activate, Esc opens Settings (Esc again closes it); the mouse works too.
## There is no mid-run save in the game, so there is no Continue button.

const BTN_SIZE := Vector2(116, 22)

class TitleView extends Control:
	var text: String = ""
	var tagline: String = ""
	func _draw() -> void:
		var px := 50
		var f := UITheme.font_for(px)
		var ts := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px)
		var x := roundf((size.x - ts.x) * 0.5)
		var y := roundf(f.get_ascent(px) + 4.0)
		# stepped drop shadow (pixel style), dark outline, gold face with a lighter top band
		for i in range(3, 0, -1):
			draw_string(f, Vector2(x + i, y + i), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(0.12, 0.06, 0.02, 1.0))
		draw_string_outline(f, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, 4, Color(0.16, 0.08, 0.03, 1.0))
		draw_string(f, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color("#f0c050"))
		draw_string(f, Vector2(x, y - 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(1.0, 0.93, 0.62, 0.35))
		UITheme.draw_text_in(self, Rect2(0, y + 8, size.x, 12), tagline, 15, Color("#dfe8c4"))

var title_view: TitleView = null
var forest: MenuForest = null
var buttons: Array = []         # [{id, btn}] in display order
var sel: int = 0
var play_btn: Button = null
var settings_btn: Button = null
var quit_btn: Button = null
var version_label: Label = null
var t: float = 0.0

## Quit is not offered in the browser (the page cannot be closed by the game).
static func quit_available(web: bool) -> bool:
	return not web

func _ready() -> void:
	forest = MenuForest.new()
	forest.name = "MenuForest"
	add_child(forest)
	title_view = TitleView.new()
	title_view.name = "Title"
	title_view.text = Game.title().to_upper()
	title_view.tagline = Game.tagline()
	title_view.position = Vector2(0, 26)
	title_view.size = Vector2(640, 80)
	title_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title_view)
	var y := 188.0
	play_btn = _menu_button("Play", "menu_play", y, _play)
	play_btn.tooltip_text = "Start a new run: choose your egg."
	settings_btn = _menu_button("Settings", "menu_settings", y + 30.0, _settings)
	settings_btn.tooltip_text = "Pixel Perfect, fullscreen, volume, intro story cutscene."
	if quit_available(OS.has_feature("web")):
		quit_btn = _menu_button("Quit", "menu_quit", y + 60.0, _quit)
	version_label = UITheme.label("v%s" % Game.version(), 15, UITheme.C_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	version_label.name = "version_label"
	version_label.size = Vector2(60, 16)
	version_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(version_label)
	_select(0)
	_layout()

func _menu_button(text: String, nm: String, y: float, cb: Callable) -> Button:
	var b := add_button(text, Rect2((640.0 - BTN_SIZE.x) * 0.5, y, BTN_SIZE.x, BTN_SIZE.y), cb, 20)
	b.name = nm
	var idx := buttons.size()
	b.mouse_entered.connect(func(): _select(idx))
	buttons.append({"id": nm, "btn": b})
	return b

func _select(i: int) -> void:
	sel = clampi(i, 0, buttons.size() - 1)
	for k in buttons.size():
		UITheme.set_selected(buttons[k]["btn"], k == sel)

## Version label hugs the real bottom-right corner of the window (the frame is centred in bigger viewports).
func _layout() -> void:
	var vp := get_viewport_rect().size
	var gp := global_position.round()
	forest.position = -gp
	forest.size = vp
	forest.origin = gp
	version_label.position = Vector2(vp.x - 66.0, vp.y - 18.0) - gp

func _process(dt: float) -> void:
	t += dt
	_layout()
	var vp := get_viewport_rect().size
	var mp := get_viewport().get_mouse_position()
	forest.mouse_norm = ((mp / vp) - Vector2(0.5, 0.5)).clampf(-0.5, 0.5) if DisplayServer.get_name() != "headless" and vp.x > 0.0 else Vector2.ZERO
	forest.advance(dt)

func _unhandled_key_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.echo:
		return
	if Game.main != null and Game.main.settings_open():
		return
	match e.keycode:
		KEY_DOWN, KEY_S:
			_select((sel + 1) % buttons.size())
			get_viewport().set_input_as_handled()
		KEY_UP, KEY_W:
			_select((sel - 1 + buttons.size()) % buttons.size())
			get_viewport().set_input_as_handled()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			get_viewport().set_input_as_handled()       # first: Play removes this screen from the tree
			(buttons[sel]["btn"] as Button).pressed.emit()

func _play() -> void:
	Game.goto("egg")

func _settings() -> void:
	if Game.main != null:
		Game.main.open_settings()

func _quit() -> void:
	get_tree().quit()
