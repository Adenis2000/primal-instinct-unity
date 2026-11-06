class_name ScreenBase
extends Control
## Base class for full-screen UI screens. `args` is set by Main before the node enters the tree.

var args: Dictionary = {}
var hud: Hud = null
## Popup mode (post-fight reward / draft / item / branch panels): the screen is shown as a centred panel over the live battle board
## (Main.show_popup) instead of replacing it. add_bg then draws a light dim + a panel at `popup_rect` instead of the backdrop.
var popup: bool = false
var popup_rect: Rect2 = Rect2(14, 12, 612, 336)

func add_bg(theme_id: String = "jungle", dim: float = 0.7) -> void:
	if popup:
		var shade := ColorRect.new()          # covers the whole window (not only the 640x360 frame); the board stays visible
		shade.name = "PopupShade"
		shade.color = Color(0.0, 0.01, 0.03, 0.45)
		shade.position = Vector2(-2000, -2000)
		shade.size = Vector2(4700, 4700)
		shade.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(shade)
		var pn := UITheme.panel(popup_rect, Color(0.04, 0.06, 0.1, 0.97), UITheme.C_GOLD)
		pn.name = "PopupPanel"
		pn.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(pn)
		return
	var bg := Backdrop.new()
	bg.name = "Backdrop"
	bg.theme_id = theme_id
	bg.dim = dim
	bg.size = Vector2(640, 360)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

func add_hud() -> Hud:
	hud = Hud.new()
	add_child(hud)
	if popup:
		hud.visible = false       # the battle HUD behind the popup already shows this
	return hud

func add_label(text: String, pos: Vector2, size: int = 16, color: Color = UITheme.C_TEXT, width: float = 0.0, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := UITheme.label("", size, color, align)
	l.position = pos
	if width > 0.0:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size = Vector2(width, 0)
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l

func add_centered(text: String, y: float, size: int = 16, color: Color = UITheme.C_TEXT) -> Label:
	var l := UITheme.label(text, size, color, HORIZONTAL_ALIGNMENT_CENTER)
	l.position = Vector2(0, y)
	l.size = Vector2(640, size + 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l

func add_button(text: String, rect: Rect2, cb: Callable, size: int = 16) -> Button:
	var b := UITheme.button(text, size, rect.size)
	b.position = rect.position
	b.size = rect.size
	b.pressed.connect(cb)
	add_child(b)
	return b

func wait(t: float) -> void:
	await get_tree().create_timer(t).timeout
