extends ScreenBase
## Pick one of three cards. Modes: normal | elite | evolution.

var mode: String = "normal"
var queue: Array = []
var offers: Array = []

func _ready() -> void:
	mode = String(args.get("mode", "normal"))
	queue = args.get("queue", [])
	var r: RunState = Game.run
	add_bg(String(r.stage.get("theme", "jungle")), 0.85)
	add_hud()
	var title := "Choose a card"
	var sub := "Add one card to your deck."
	match mode:
		"elite":
			title = "Spoils of a mighty foe"
			sub = "Better cards are on offer."
		"cave":
			title = "The spiders' hoard"
			sub = "Unique cave cards. Choose one."
		"evolution":
			title = "EVOLUTION: %s" % r.form()["name"]
			sub = "Your new form unlocks stronger skills. Choose one."
	add_centered(title, 36, 30, UITheme.C_GOLD)
	add_centered(sub, 58, 15, UITheme.C_DIM)
	offers = r.offer_cards(3, mode)
	var cw := float(CardView.BW)
	var gap := 16.0
	var total := offers.size() * cw + (offers.size() - 1) * gap
	var x0 := (640.0 - total) / 2.0
	for i in offers.size():
		var cv := CardView.new().setup(String(offers[i]), -1, true)
		cv.synergy = Arch.matching(DB.card(String(offers[i])).get("tags", []), r.deck, r.items)
		cv.position = Vector2(roundf(x0 + i * (cw + gap)), 76)
		var id: String = offers[i]
		cv.clicked.connect(func(_v): _pick(id))
		add_child(cv)
		var tier := int(DB.card(id)["tier"])
		var forms := ["Hatchling", "Juvenile", "Adult", "Prime"]
		var syn_txt := ""
		if not cv.synergy.is_empty():
			syn_txt = "SYNERGY: " + Arch.tags_text(cv.synergy)
		var tag_lbl := add_label(syn_txt if syn_txt != "" else "%s skill" % forms[tier - 1], Vector2(x0 + i * (cw + gap) - 8, 76 + CardView.BH + 2), 15, UITheme.C_GOLD if syn_txt != "" else UITheme.C_DIM, cw + 16, HORIZONTAL_ALIGNMENT_CENTER)
		tag_lbl.name = "tag_%d" % i
	if mode != "evolution":
		add_button("Skip", Rect2(532, 322, 100, 26), func(): _done(), 20)
	Hints.place(Rect2(8, 312, 500, 46))
	Hints.show_hint("draft")
	Hints.show_hint("synergy")

func _pick(id: String) -> void:
	Game.run.add_card(id)
	Game.run.stats["cards_drafted"] += 1
	_done()

func _done() -> void:
	if mode == "evolution":
		Game.run.pending_evolution_tier = 0
	Game.run_drafts(queue)
