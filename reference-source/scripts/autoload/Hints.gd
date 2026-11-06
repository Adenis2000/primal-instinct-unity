extends CanvasLayer
## First-playthrough hint tooltips. Short, dismissible, never shown again after the first run ends.

var _panel: Panel
var _title: Label
var _text: RichTextLabel
var plain_text: String = ""
var _queue: Array = []
var _showing: String = ""

func _ready() -> void:
	layer = 50
	_build()
	_panel.theme = UITheme.build_theme()
	_panel.visible = false

var _ok: Button
var _skip: Button

func _build() -> void:
	_panel = UITheme.panel(Rect2(154, 293, 332, 61), Color(0.08, 0.1, 0.05, 0.97), UITheme.C_GOLD)
	add_child(_panel)
	var tag := UITheme.label("HINT", 15, UITheme.C_GOLD)
	tag.position = Vector2(7, 3)
	_panel.add_child(tag)
	_title = UITheme.label("", 20, UITheme.C_GOLD)
	_title.position = Vector2(38, 1)
	_panel.add_child(_title)
	_text = Keywords.rich("", UITheme.SZ_S, UITheme.C_TEXT)
	_text.position = Vector2(8, 21)
	_text.size = Vector2(316, 24)
	_panel.add_child(_text)
	_ok = UITheme.button("Got it", 15, Vector2(46, 18))
	_ok.pressed.connect(_dismiss)
	_panel.add_child(_ok)
	_skip = UITheme.button("Hide hints", 15, Vector2(70, 18))
	_skip.pressed.connect(_disable)
	_panel.add_child(_skip)
	place(Rect2(16, 262, 360, 62))

## Move the hint box (each screen picks a spot that doesn't cover important UI).
## The box keeps the rect's top-left and width; its height grows to fit the text (never clipped, never off-screen).
var _rect := Rect2(16, 262, 360, 62)

func place(rect: Rect2) -> void:
	_rect = rect
	_relayout()

func _relayout() -> void:
	var w := _rect.size.x
	_text.size = Vector2(w - 16, 0)
	var th := UITheme.font_for(UITheme.SZ_S).get_multiline_string_size(plain_text, HORIZONTAL_ALIGNMENT_LEFT, w - 18, UITheme.snap(UITheme.SZ_S)).y
	var h := 21.0 + th + 5.0
	_panel.size = Vector2(w, h)
	_panel.position = Vector2(_rect.position.x, minf(_rect.position.y, 358.0 - h))
	_text.size = Vector2(w - 16, th + 2)
	_ok.position = Vector2(w - 124.0, 2)
	_skip.position = Vector2(w - 74.0, 2)

func active() -> bool:
	return bool(Game.save.get("hints_enabled", true)) and not bool(Game.save.get("first_run_complete", false))

## Show a hint once (first playthrough only).
func show_hint(id: String) -> void:
	if not active():
		return
	if Game.save["hints_seen"].has(id) or _queue.has(id) or _showing == id:
		return
	if not DB.table("hints")["hints"].has(id):
		return
	_queue.append(id)
	_next()

## While true (stage-intro cinematic) hints are queued but not shown.
var suspended := false

func resume() -> void:
	suspended = false
	_next()

func _next() -> void:
	if suspended or _showing != "" or _queue.is_empty():
		return
	_showing = _queue.pop_front()
	var h: Dictionary = DB.table("hints")["hints"][_showing]
	_title.text = String(h["title"])
	plain_text = String(h["text"])
	_text.clear()
	_text.append_text(Keywords.bbcode(plain_text))
	_relayout()
	_panel.visible = true

func _dismiss() -> void:
	if _showing != "":
		Game.save["hints_seen"][_showing] = true
		Game.write_save()
	_showing = ""
	_panel.visible = false
	_next()

func _disable() -> void:
	Game.save["hints_enabled"] = false
	Game.write_save()
	_queue.clear()
	_showing = ""
	_panel.visible = false

func clear() -> void:
	suspended = false
	place(Rect2(16, 262, 360, 62))
	_queue.clear()
	_showing = ""
	_panel.visible = false

func current() -> String:
	return _showing
