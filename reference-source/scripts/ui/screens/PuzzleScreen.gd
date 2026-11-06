extends ScreenBase
## Memory puzzle: the singing stones.

const COLS := [Color("#d84a4a"), Color("#4a8ae0"), Color("#5ac85a"), Color("#e8c84a")]
const NOTES := ["ROAR", "HOWL", "CHIRP", "HISS"]

var room: Dictionary
var puzzle: SequencePuzzle
var pdef: Dictionary
var stones: Array = []
var status: Label
var accepting: bool = false
var done: bool = false

func _ready() -> void:
	room = args["room"]
	var r: RunState = Game.run
	pdef = DB.table("puzzles")[String(room["puzzle_id"])]
	puzzle = SequencePuzzle.from_room(room)
	add_bg(String(r.stage.get("theme", "jungle")), 0.8)
	add_hud()
	add_centered(String(pdef["name"]), 40, 30, Color(RoomInfo.TYPE_COLOR["puzzle"]))
	add_label(String(pdef["intro"]), Vector2(60, 66), 15, UITheme.C_TEXT, 520, HORIZONTAL_ALIGNMENT_CENTER)
	var n := puzzle.buttons
	var w := 86.0
	var gap := 16.0
	var x0 := (640.0 - (n * w + (n - 1) * gap)) / 2.0
	for i in n:
		var b := Button.new()
		b.position = Vector2(roundf(x0 + i * (w + gap)), 112)
		b.size = Vector2(w, w)
		b.focus_mode = Control.FOCUS_NONE
		b.text = NOTES[i]
		UITheme.apply(b, 20)
		_style(b, 0.45)
		var idx := i
		b.pressed.connect(func(): _press(idx))
		add_child(b)
		stones.append(b)
	status = add_centered("Watch carefully...", 218, 30, UITheme.C_GOLD)
	add_centered("Mistakes allowed: %d" % puzzle.mistakes_left, 246, 15, UITheme.C_DIM)
	await wait(0.8)
	_play_sequence()

func _style(b: Button, bright: float) -> void:
	var c: Color = COLS[stones.size() if b.get_parent() == null else stones.find(b)]
	var col := c * Color(bright, bright, bright, 1.0)
	for st in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(st, UITheme.box(col, Color("#101010") if bright < 0.9 else Color.WHITE, 2, 0, 5))

func _flash(i: int, t: float = 0.45) -> void:
	_style(stones[i], 1.0)
	await wait(t)
	_style(stones[i], 0.45)

func _play_sequence() -> void:
	accepting = false
	status.text = "Watch carefully..."
	for s in puzzle.sequence:
		await _flash(int(s), 0.5)
		await wait(0.18)
	status.text = "Your turn! Repeat the pattern."
	accepting = true

func _press(i: int) -> void:
	if not accepting or done:
		return
	_flash(i, 0.2)
	var res := puzzle.press(i)
	match res:
		"ok":
			pass
		"done":
			_finish(true)
		"wrong":
			accepting = false
			var r: RunState = Game.run
			r.apply_effects(pdef["mistake_effects"])
			hud.refresh()
			status.text = "WRONG! The stones shock you. (%d mistakes left)" % puzzle.mistakes_left
			if r.game_over:
				_finish(false)
				return
			await wait(1.2)
			_play_sequence()
		"fail":
			Game.run.apply_effects(pdef["mistake_effects"])
			hud.refresh()
			_finish(false)

func _finish(ok: bool) -> void:
	if done:
		return
	done = true
	accepting = false
	var r: RunState = Game.run
	r.stats["puzzles"] += 1
	if ok:
		var ctx := {}
		var msgs := r.apply_effects(pdef["reward"], ctx)
		status.text = "The stones sing! " + ", ".join(msgs)
		status.add_theme_color_override("font_color", UITheme.C_GREEN)
	else:
		status.text = "The stones fall silent. Nothing gained."
		status.add_theme_color_override("font_color", UITheme.C_RED)
	hud.refresh()
	add_button("Continue", Rect2(264, 280, 112, 24), func(): Game.finish_room(), 20)
