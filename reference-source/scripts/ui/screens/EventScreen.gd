extends ScreenBase
## Events (multiple-choice with consequences) and foraging (pick a food source).

var room: Dictionary
var ctx: Dictionary = {}
var choice_box: Control
var choices: Array = []

func _ready() -> void:
	room = args["room"]
	var r: RunState = Game.run
	add_bg(String(r.stage.get("theme", "jungle")), 0.8)
	add_hud()
	var title: String
	var body: String
	var color := Color("#e0d060")
	if room["type"] == "forage":
		title = "Foraging Ground"
		body = "Your belly rumbles. A few places look promising for a meal. Which do you try?"
		color = Color(RoomInfo.TYPE_COLOR["forage"])
		var fg: Dictionary = DB.table("events")["forage"]
		for id in room["forage_ids"]:
			choices.append(fg[id])
	else:
		var ev: Dictionary = DB.table("events")["events"][room["event_id"]]
		title = String(ev["name"])
		body = String(ev["text"])
		color = Color(String(ev.get("color", "#e0d060")))
		choices = ev["choices"]
		r.stats["events"] += 1
	add_child(UITheme.panel(Rect2(60, 40, 520, 90), Color(0.06, 0.08, 0.04, 0.92), color))
	add_label(title, Vector2(72, 46), 30, color)
	add_label(body, Vector2(72, 70), 15, UITheme.C_TEXT, 496)
	choice_box = Control.new()
	add_child(choice_box)
	for i in choices.size():
		var c: Dictionary = choices[i]
		var b := UITheme.button("", 20, Vector2(520, 46))
		b.position = Vector2(60, 140 + i * 52)
		b.size = Vector2(520, 46)
		var idx := i
		b.pressed.connect(func(): _choose(idx))
		choice_box.add_child(b)
		var t := UITheme.label(String(c["label"]), 20, Color.WHITE)
		UITheme.outline(t)
		t.position = Vector2(8, 3)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(t)
		var h := UITheme.label(String(c.get("hint", "")), 15, Color("#fff4e0"))
		UITheme.outline(h)
		h.position = Vector2(8, 22)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(h)
	var notes: Array = Game.battle_result.get("notes", [])
	if not notes.is_empty():
		add_label(String(notes[0]), Vector2(60, 340), 15, UITheme.C_DIM)

func _choose(i: int) -> void:
	var r: RunState = Game.run
	choice_box.queue_free()
	var out := r.resolve_outcome(choices[i], ctx)
	if hud:
		hud.refresh()
	var y := 230.0
	add_child(UITheme.panel(Rect2(60, 140, 520, 160), Color(0.06, 0.08, 0.04, 0.92), UITheme.C_BORDER))
	add_label(String(out["text"]), Vector2(72, 148), 15, UITheme.C_TEXT, 496)
	y = 220.0
	for m in out["msgs"]:
		var s := String(m)
		var bad := s.begins_with("-") or s.contains("-") and s.ends_with("HP") or s.begins_with("Infected") or s.begins_with("Lost")
		add_label("- " + s, Vector2(76, y), 15, UITheme.C_RED if bad else UITheme.C_GREEN)
		y += 14.0
	if ctx.has("levels") and not ctx["levels"].is_empty():
		add_label("LEVEL UP!", Vector2(76, y), 15, Color("#6fa8e8"))
	var cont_text := "Continue"
	if ctx.has("battle"):
		cont_text = "Brace yourself..."
	add_button(cont_text, Rect2(264, 308, 112, 24), _continue, 20)

func _continue() -> void:
	if Game.run.game_over:
		Game.finish_room()
		return
	if ctx.has("battle"):
		var spec: Dictionary = ctx["battle"]
		var broom := Game.make_event_battle_room(spec)
		Game.enter_battle(broom)
		return
	Game.finish_room()
