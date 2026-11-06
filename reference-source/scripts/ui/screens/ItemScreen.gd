extends ScreenBase
## Item reward: a rare drop after a cleared area (take it or leave it), or a choice of 3 (boss hoard, secret cave).

var source: String = "battle"
var offers: Array = []
var queue: Array = []

func _ready() -> void:
	source = String(args.get("source", "battle"))
	offers = args.get("offers", [])
	queue = args.get("queue", [])
	var r: RunState = Game.run
	add_bg(String(r.stage.get("theme", "jungle")), 0.85)
	add_hud()
	var cfg := DB.item_source(source)
	add_centered(String(cfg.get("title", "An item!")), 36, 30, UITheme.C_GOLD)
	add_centered("Choose 1 of %d. It lasts for the rest of the run." % offers.size() if offers.size() > 1 else "You found something. Keep it?", 60, 15, UITheme.C_DIM)
	var cw := 184.0
	var gap := 14.0
	var py := 82.0
	var ph := 196.0
	var total := offers.size() * cw + (offers.size() - 1) * gap
	var x0 := roundf((640.0 - total) / 2.0)
	for i in offers.size():
		var id: String = offers[i]
		var d: Dictionary = DB.item(id)
		var col := ItemUI.rarity_color(id)
		var x := x0 + i * (cw + gap)
		add_child(UITheme.panel(Rect2(x, py, cw, ph), Color(0.05, 0.07, 0.12, 0.96), col))
		var ic := TextureRect.new()
		ic.texture = ItemUI.texture(id)
		var isz := ic.texture.get_size() * 3.0              # integer 3x: square pixels
		ic.position = Vector2(roundf(x + cw / 2.0 - isz.x / 2.0), py + 10.0)
		ic.size = isz
		ic.stretch_mode = TextureRect.STRETCH_SCALE
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(ic)
		add_label(String(d["name"]), Vector2(x + 6, py + 54), 20, Color.WHITE, cw - 12, HORIZONTAL_ALIGNMENT_CENTER)
		add_label(String(d["rarity"]).to_upper() + ("  -  ACTIVE" if d.has("use") else "  -  PASSIVE"), Vector2(x + 6, py + 74), 15, col, cw - 12, HORIZONTAL_ALIGNMENT_CENTER)
		var itags: Array = d.get("tags", [])
		if not itags.is_empty():
			var syn := Arch.matching(itags, r.deck, r.items)
			var tl := add_label(("SYNERGY: " if not syn.is_empty() else "Build: ") + Arch.tags_text(itags), Vector2(x + 6, py + ph - 48), 15, UITheme.C_GOLD if not syn.is_empty() else UITheme.C_DIM, cw - 12, HORIZONTAL_ALIGNMENT_CENTER)
			tl.name = "tags_%d" % i
			if not syn.is_empty():
				var glow := Panel.new()
				glow.position = Vector2(x - 1, py - 1)
				glow.size = Vector2(cw + 2, ph + 2)
				glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
				var gsb := StyleBoxFlat.new()
				gsb.draw_center = false
				gsb.border_color = UITheme.C_GOLD
				gsb.set_border_width_all(2)
				glow.add_theme_stylebox_override("panel", gsb)
				add_child(glow)
		var tx := Keywords.rich(String(d["text"]), 15, UITheme.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
		tx.position = Vector2(x + 8, py + 92)
		tx.size = Vector2(cw - 16, 52)
		add_child(tx)
		add_button("Take", Rect2(x + 24, py + ph - 30, cw - 48, 22), func(): _take(id), 20)
	if offers.size() == 1:
		add_button("Leave it", Rect2(264, py + ph + 12, 112, 22), func(): _done(), 20)
	Hints.show_hint("items")

func _take(id: String) -> void:
	Game.run.add_item(id)
	_done()

func _done() -> void:
	Game.run_drafts(queue)
