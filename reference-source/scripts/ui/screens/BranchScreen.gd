extends ScreenBase
## Evolution branches. Standard growth is always available; stronger branches need a good diet for YOUR species.
## Requirements are only revealed here (at evolution time): locked branches show what they needed and how close you were.

var queue: Array = []
var tier: int = 2

func _ready() -> void:
	queue = args.get("queue", [])
	var r: RunState = Game.run
	tier = maxi(r.pending_evolution_tier, r.tier())
	add_bg(String(r.stage.get("theme", "jungle")), 0.86)
	add_hud()
	add_centered("EVOLUTION: %s" % String(DB.table("growth")["forms"][tier - 1]["name"]), 34, 30, UITheme.C_GOLD)
	add_centered("You are what you ate. Diet: %s - quality %s (score %d)" % [String(r.diet()["name"]), r.diet_quality(), r.diet_score()], 58, 15, UITheme.C_DIM)
	var opts := r.branch_options(tier)
	var n := opts.size() + 1
	var gap := 8.0
	var cw := minf(184.0, floorf((624.0 - float(n - 1) * gap) / float(n)))
	var total := n * cw + (n - 1) * gap
	var x0 := roundf((640.0 - total) / 2.0)
	_panel(x0, cw, "Steady Growth", "The normal evolution. Always available. No bonus, no penalty.", [], true, "", Color("#9aa8b8"))
	for i in opts.size():
		var o: Dictionary = opts[i]
		var x := x0 + (i + 1) * (cw + gap)
		_panel(x, cw, String(o["name"]), String(o["text"]), o["progress"], bool(o["unlocked"]), String(o["id"]), Color("#f0c050") if o["unlocked"] else Color("#5a6070"))
	Hints.show_hint("branches")

const PY := 76.0
const PH := 252.0

func _panel(x: float, cw: float, title: String, text: String, prog: Array, unlocked: bool, id: String, col: Color) -> void:
	add_child(UITheme.panel(Rect2(x, PY, cw, PH), Color(0.05, 0.07, 0.12, 0.96) if unlocked else Color(0.04, 0.045, 0.06, 0.96), col))
	var dim := Color("#9aa0b0")
	add_label(title, Vector2(x + 7, PY + 7), 20, Color.WHITE if unlocked else dim, cw - 14)
	var y := PY + 28.0
	if not unlocked:
		add_label("LOCKED", Vector2(x + 7, y), 15, Color("#e08080"), cw - 14)
		y += 14.0
	var tl := Keywords.rich(text, 15, UITheme.C_TEXT if unlocked else dim)
	tl.position = Vector2(x + 7, y)
	var th := UITheme.font_for(15).get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, cw - 16, UITheme.snap(15)).y
	tl.size = Vector2(cw - 14, th + 3)
	add_child(tl)
	y += th + 8.0
	if not prog.is_empty():
		add_label("Needs:" if not unlocked else "Requirements met:", Vector2(x + 7, y), 15, UITheme.C_DIM, cw - 14)
		y += 14.0
		for p in prog:
			var okp: bool = p["ok"]
			var have := int(round(p["have"]))
			var need := int(p["need"])
			var txt := "%s %s %s" % [p["label"], ("%d / %d" % [have, need]) if p["label"] != "Toxins at most" else ("%d (max %d)" % [have, need]), "OK" if okp else "X"]
			add_label(txt, Vector2(x + 9, y), 15, UITheme.C_GREEN if okp else Color("#ff8a80"), cw - 16)
			y += 13.0
	if unlocked:
		add_button("Choose", Rect2(x + 16, PY + PH - 30, cw - 32, 22), func(): _choose(id), 20)
	else:
		add_label("Eat more of what suits you next time.", Vector2(x + 7, PY + PH - 28), 15, dim, cw - 14)

func _choose(id: String) -> void:
	var extra: Array = Game.run.choose_branch(tier, id)
	var q := queue.duplicate()
	var at := q.find("evolution")
	if at >= 0:
		for i in extra.size():
			q.insert(at + 1 + i, extra[i])
	else:
		q.append_array(extra)
	Game.run_drafts(q)
