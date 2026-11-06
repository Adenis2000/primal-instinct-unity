extends ScreenBase
## Title / character selection. You choose an egg; it hatches into a baby at the start of the run.

class EggSlot extends Control:
	const SLOT := Vector2(96, 108)
	signal picked(id: String)
	var species_id: String = ""
	var selected: bool = false
	var playable: bool = false
	var tex: TextureRect
	func setup(id: String) -> EggSlot:
		species_id = id
		var sp := DB.species(id)
		playable = bool(sp["playable"])
		custom_minimum_size = Vector2(SLOT.x, SLOT.y)
		size = SLOT
		var nest := TextureRect.new()              # the twig/fern nest (bg_egg_nest) the egg sits in
		nest.name = "nest"
		nest.texture = SpriteFactory.get_texture("bg_egg_nest")
		nest.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		nest.position = Vector2(float(int(SLOT.x) - int(nest.texture.get_width())) * 0.5, 22)
		nest.size = nest.texture.get_size()
		nest.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not playable:
			nest.modulate = Color(0.55, 0.62, 0.62)
		add_child(nest)
		tex = TextureRect.new()
		tex.name = "egg"
		tex.texture = SpriteFactory.get_texture(String(sp["sprites"]["egg"]))
		tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var esz := tex.texture.get_size() * 2.0         # integer 2x so the pixels stay square
		tex.size = esz
		tex.position = Vector2((SLOT.x - esz.x) * 0.5, 56.0 - esz.y)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_SCALE
		tex.pivot_offset = Vector2(esz.x * 0.5, esz.y - 2.0)
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not playable:
			tex.modulate = Color(0.7, 0.7, 0.8)
		add_child(tex)
		var n := UITheme.label(String(sp["name"]) if playable else "???", 20, UITheme.C_TEXT if playable else UITheme.C_DIM, HORIZONTAL_ALIGNMENT_CENTER)
		n.position = Vector2(0, 78)
		n.size = Vector2(SLOT.x, 16)
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(n)
		var s := UITheme.label(String(sp["playstyle"]) if playable else "locked", 15, UITheme.C_GOLD if playable else UITheme.C_DIM, HORIZONTAL_ALIGNMENT_CENTER)
		s.position = Vector2(0, 94)
		s.size = Vector2(SLOT.x, 12)
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(s)
		return self
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, SLOT), Color(0.05, 0.08, 0.03, 0.75))
		draw_rect(Rect2(Vector2.ZERO, SLOT), UITheme.C_GOLD if selected else Color("#3f5a28"), false, 2.0 if selected else 1.0)
	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			picked.emit(species_id)

var slots: Dictionary = {}
var selected_id: String = "velociraptor"
var info_title: Label
var info_body: Label
var seed_edit: LineEdit
var hatch_btn: Button
var flash: ColorRect
var hatching: bool = false

func _ready() -> void:
	add_bg("jungle", 0.78)
	add_centered(Game.title().to_upper(), 6, 40, UITheme.C_GOLD)
	add_centered(Game.tagline(), 40, 15, UITheme.C_DIM)
	add_centered("Choose your egg", 52, 20, UITheme.C_GOLD)
	var ids := DB.table("species").keys()
	var x0 := (640 - (ids.size() * 96 + (ids.size() - 1) * 12)) / 2
	for i in ids.size():
		var s := EggSlot.new().setup(ids[i])
		s.position = Vector2(x0 + i * 108, 66)
		s.picked.connect(_pick)
		add_child(s)
		slots[ids[i]] = s
	add_child(UITheme.panel(Rect2(16, 182, 400, 162)))
	info_title = add_label("", Vector2(26, 190), 20, UITheme.C_GOLD)
	info_body = add_label("", Vector2(26, 208), 15, UITheme.C_TEXT, 380)
	add_child(UITheme.panel(Rect2(424, 182, 200, 162)))
	add_label("Run seed (optional)", Vector2(434, 188), 15, UITheme.C_DIM)
	seed_edit = LineEdit.new()
	seed_edit.placeholder_text = "random"
	seed_edit.position = Vector2(434, 202)
	seed_edit.size = Vector2(180, 20)
	UITheme.apply(seed_edit, 15)
	add_child(seed_edit)
	var last := int(Game.save.get("last_seed", 0))
	add_label("Last seed: %s" % (str(last) if last > 0 else "-"), Vector2(434, 226), 15, UITheme.C_DIM)
	hatch_btn = add_button("HATCH!", Rect2(434, 242, 180, 28), _hatch, 30)
	hatch_btn.tooltip_text = "Pick this egg, then customize your hatchling."
	var runs := int(Game.save.get("runs", 0))
	var hint_state := "hints: on" if Hints.active() else "hints: off (first run done)"
	add_label("Runs: %d   Wins: %d   %s" % [runs, int(Game.save.get("wins", 0)), hint_state], Vector2(434, 276), 15, UITheme.C_DIM, 180)
	var dl_ids: Array = Difficulty.level_ids()
	var st := {"cur": String(Game.save.get("difficulty", String(DB.table("difficulty")["default"])))}   # dict: lambdas capture by value
	var dbtn := add_button("", Rect2(528, 322, 86, 16), func(): pass, 15)
	dbtn.name = "difficulty_btn"
	var _upd := func():
		var lv: Dictionary = DB.table("difficulty")["levels"][st["cur"]]
		dbtn.text = String(lv["name"])
		dbtn.tooltip_text = "Difficulty: %s - %s" % [lv["name"], lv["desc"]]
	_upd.call()
	for c in dbtn.pressed.get_connections():
		dbtn.pressed.disconnect(c["callable"])
	dbtn.pressed.connect(func():
		st["cur"] = String(dl_ids[(dl_ids.find(st["cur"]) + 1) % dl_ids.size()])
		Game.save["difficulty"] = st["cur"]
		Game.write_save()
		_upd.call())
	add_button("Replay hints", Rect2(434, 322, 90, 16), func():
		Game.save["first_run_complete"] = false
		Game.save["hints_seen"] = {}
		Game.save["hints_enabled"] = true
		Game.write_save()
		Game.goto("egg"), 15)
	add_button("Main menu", Rect2(6, 5, 64, 16), func(): Game.goto("menu"), 15).name = "egg_main_menu"
	add_child(UITheme.gear_button(Rect2(612, 5, 22, 18), _open_settings))
	flash = ColorRect.new()
	flash.color = Color(1, 1, 1, 0)
	UITheme.full_rect(flash)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)
	_pick("velociraptor")

func _pick(id: String) -> void:
	if hatching:
		return
	selected_id = id
	for k in slots:
		slots[k].selected = (k == id)
		slots[k].queue_redraw()
	var sp := DB.species(id)
	if bool(sp["playable"]):
		var b: Dictionary = sp["base"]
		info_title.text = "%s  (%s)" % [sp["name"], sp["era"]]
		var deck_parts := []
		for cid in sp["starter_deck"]:
			deck_parts.append("%dx %s" % [sp["starter_deck"][cid], DB.card(cid)["name"]])
		info_body.text = "%s\n\nHatchling stats: %d HP, speed %d, move %d, stamina %d.\nStarter deck: %s." % [sp["blurb"], b["max_hp"], b["speed"], b["move"], b["stamina"], ", ".join(deck_parts)]
		hatch_btn.disabled = false
	else:
		info_title.text = "??? (locked)"
		info_body.text = "%s\n\nThis egg is not ready to hatch yet. Only the Velociraptor is playable in this prototype." % sp["blurb"]
		hatch_btn.disabled = true

## Pressing HATCH! wobbles the chosen egg, then opens the customization screen (egg cracks in the centre, eye peeks out).
## The run itself starts when the look is confirmed (CustomizeScreen).
func _hatch() -> void:
	if hatching or not bool(DB.species(selected_id)["playable"]):
		return
	hatching = true
	hatch_btn.disabled = true
	var slot: EggSlot = slots[selected_id]
	var tw := create_tween()
	for i in 4:
		tw.tween_property(slot.tex, "rotation", 0.18 if i % 2 == 0 else -0.18, 0.07)
	tw.tween_property(slot.tex, "rotation", 0.0, 0.05)
	tw.tween_property(flash, "color:a", 0.6, 0.15)
	await tw.finished
	Game.goto("customize", {"species": selected_id, "seed": RunState.seed_from_text(seed_edit.text)})

func _open_settings() -> void:
	if Game.main != null:
		Game.main.open_settings()
