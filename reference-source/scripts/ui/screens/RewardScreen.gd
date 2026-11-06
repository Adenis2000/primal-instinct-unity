extends ScreenBase
## Post-battle popup "Encounter Cleared" over the live board: XP, level-ups, and the EAT / FILL / SKIP choice for each fallen
## creature (with its nutrition profile). Shown by Game.goto("reward") as a centred panel (see ScreenBase.popup); the cards / items /
## evolution picks that follow are popups in the same style.

var res: Dictionary
var room: Dictionary
var xp_res: Dictionary
var rows: Array = []        # [{corpse, label, eat_btn, skip_btn, state}]
var status_labels: Array = []

func _ready() -> void:
	res = Game.battle_result
	room = args.get("room", {})
	var r: RunState = Game.run
	popup_rect = Rect2(24, 12, 592, 336)
	add_bg(String(room.get("theme", r.stage.get("theme", "jungle"))), 0.84)
	xp_res = r.grant_xp(int(res["xp"]))
	add_hud()
	add_centered("Encounter Cleared", 22, 30, UITheme.C_GOLD)
	var bonus := int(xp_res.get("bonus", 0))
	add_centered("%d defeated   +%d XP%s" % [int(res["kills"]), int(xp_res.get("gained", res["xp"])), ("  (diet bonus +%d)" % bonus) if bonus > 0 else ""], 48, 15, UITheme.C_TEXT)
	var y := 64.0
	for lv in xp_res["levels"]:
		add_centered("LEVEL UP!  Level %d" % int(lv), y, 15, Color("#8fc4ff"))
		y += 18.0
	if xp_res["evolved"]:
		add_centered("You are ready to EVOLVE into a %s! (after this screen)" % r.form()["name"], y, 15, UITheme.C_GOLD)
		y += 18.0
	if String(room.get("type", "")) == "cave":
		for line in Game.apply_cave_reward(room):
			add_centered(line, y, 15, Color("#d4c0ff"))
			y += 17.0
	var yend := _build_meals(maxf(y + 4.0, 68.0))
	var cont_y := yend + 6.0
	add_button("Continue", Rect2(500, cont_y, 104, 22), func(): Game.after_reward(String(room.get("type", "battle"))), 20)
	# fit the panel to its content and centre it vertically (the board stays visible around it)
	var ph := clampf(cont_y + 22.0 + 12.0 - popup_rect.position.y, 150.0, popup_rect.size.y)
	var pn: Control = find_child("PopupPanel", false, false)
	if pn != null:
		pn.size.y = ph
		var dy := roundf((360.0 - ph) / 2.0) - popup_rect.position.y
		for c in get_children():
			if c != hud and c.name != "PopupShade":
				c.position.y += dy
	if rows.size() > 0 and Hints.active():
		Game.save["hints_seen"]["nutrition"] = true          # shown as the in-popup tip above

func _meal_text(profile: Dictionary) -> String:
	var parts: Array = []
	for k in DB.nutrition()["order"]:
		if int(profile.get(k, 0)) > 0:
			parts.append("%s %d" % [DB.nutrition()["nutrients"][k]["short"], int(profile[k])])
	return "  ".join(parts)

func _build_meals(y0: float) -> float:
	var r: RunState = Game.run
	var corpses: Array = res.get("corpses", [])
	var hdr := "Eating is optional.  Diet: %s (prefers %s)" % [String(r.diet()["name"]), ", ".join(r.diet()["prefers"])]
	var h := add_label(hdr, Vector2(36, y0), 15, Color("#c4d2e0"), 568, HORIZONTAL_ALIGNMENT_CENTER)
	h.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.06))
	h.add_theme_constant_override("outline_size", 2)
	var y := y0 + 18.0
	if Hints.active():          # first-run tip lives inside the popup (a floating hint box used to cover it)
		var tip := add_label("Eat: its nutrients count toward your diet.  Fill up: more hunger, but a junk meal.", Vector2(36, y), 15, UITheme.C_GOLD, 568, HORIZONTAL_ALIGNMENT_CENTER)
		tip.name = "NutritionTip"
		y += 18.0
	var rh := minf(52.0, (322.0 - y) / maxf(1.0, corpses.size()))
	var three := rh >= 50.0
	for i in corpses.size():
		var c: Dictionary = corpses[i]
		var inf: bool = bool(c.get("infected", false))
		var d := DB.enemy(String(c["id"]))
		var prof := RunState.meal_profile(String(c["id"]), inf)
		var food := int(c["food"]) / (2 if inf else 1)
		add_child(UITheme.panel(Rect2(36, y, 568, rh - 3), Color(0.04, 0.06, 0.1, 0.94), UITheme.C_BORDER, "ui_panel_dim"))
		var tr := TextureRect.new()
		tr.texture = SpriteFactory.get_texture(String(d["sprite"]), inf)
		tr.size = Vector2(28, 28)
		tr.position = Vector2(40, y + (rh - 3 - 28) / 2.0)
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(tr)
		var nm := ("Infected " if inf and not bool(d.get("infected", false)) else "") + String(d["name"])
		add_label(nm, Vector2(72, y + 2), 20, UITheme.C_GREEN if inf else Color.WHITE, 190)
		var fit := r.meal_fit_label(prof)
		var fit_col: Color = {"Great": Color("#6fe86f"), "Okay": Color("#d8e060"), "Poor": Color("#f0a040"), "Harmful": Color("#ff6a60")}.get(fit, Color.WHITE)
		add_label("Fit: " + fit, Vector2(72, y + 18), 15, fit_col, 190)
		var qa := r.quality_after(prof, "eat")
		if three:
			add_label("Diet: %s (%+d%% XP)" % [qa, int(round(r.xp_bonus_for(qa) * 100.0))], Vector2(72, y + 34), 15, Color("#a8c8e8"), 190)
		add_label(_meal_text(prof), Vector2(266, y + 2), 20, Color("#e4eef8"), 140)
		var eat_h := r.eat_hunger(food, "eat")
		var eff := "Eat +%d hunger +%d HP" % [eat_h, r.meal_heal(r.eat_hunger(food, "eat"), prof, "eat")]
		var risk := ""
		var tox := int(prof["toxin"])
		if inf:
			risk = "infected: +2 spores"
		elif tox > 0:
			risk = "toxic: -%d HP if eaten" % (tox * int(DB.nutrition()["toxin_hp"]))
		var qf := r.quality_after(prof, "fill")
		add_label(eff, Vector2(266, y + 18), 15, UITheme.C_TEXT, 140)
		if three and risk != "":
			add_label(risk, Vector2(266, y + 34), 15, Color("#d8a0ff"), 140)
		var st := add_label("", Vector2(410, y + rh / 2.0 - 9), 15, UITheme.C_DIM, 190, HORIZONTAL_ALIGNMENT_CENTER)
		var bh := 24.0
		var by := y + (rh - 3.0 - bh) / 2.0
		var eat := add_button("Eat", Rect2(412, by, 52, bh), func(): _decide(i, "eat"), 20)
		var fill := add_button("Fill up", Rect2(468, by, 60, bh), func(): _decide(i, "fill"), 20)
		var skip := add_button("Skip", Rect2(532, by, 52, bh), func(): _decide(i, ""), 20)
		eat.tooltip_text = "Savour it: its nutrients and fit rating count toward your diet. Only %d of its %d hunger.%s" % [eat_h, food, ("  (" + risk + ")") if risk != "" else ""]
		fill.tooltip_text = "Just fill up: all %d hunger, but no nutrients and it counts as a junk meal (diet -> %s)." % [food, qf]
		skip.tooltip_text = "Leave it. No hunger, no effect on your diet."
		rows.append({"corpse": c, "eat": eat, "fill": fill, "skip": skip, "label": st, "done": false})
		y += rh
	return y

func _decide(i: int, mode: String) -> void:
	var row: Dictionary = rows[i]
	if row["done"]:
		return
	row["done"] = true
	var r: RunState = Game.run
	var lbl: Label = row["label"]
	if mode != "":
		var out := r.eat_corpse(row["corpse"], mode)
		lbl.text = ("Eaten (%s): +%d hunger" % [out["fit"], out["hunger"]]) if mode == "eat" else ("Filled up: +%d hunger, junk meal" % out["hunger"])
		lbl.add_theme_color_override("font_color", UITheme.C_GREEN if mode == "eat" else Color("#c0a888"))
		row["last"] = out
	else:
		lbl.text = "Skipped"
	row["eat"].disabled = true
	row["fill"].disabled = true
	row["eat"].visible = false
	row["fill"].visible = false
	row["skip"].visible = false
	row["skip"].disabled = true
	if hud:
		hud.refresh()
