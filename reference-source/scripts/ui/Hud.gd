class_name Hud
extends Control
## Top bar: form/level, HP, hunger, XP, weather, stage progress, deck.

var hp_bar: StatBar
var hunger_bar: StatBar
var xp_bar: StatBar
var form_label: Label
var weather_icon: TextureRect
var weather_label: Label
var stage_label: Label
var portrait: TextureRect
var deck_btn: Button
var hp_override: int = -1
var items_row: Control
var items_origin: Vector2 = Vector2(4, 37)
var diet_meter: Control
var diet_origin: Vector2 = Vector2(4, 342)       # bottom-left on the menu-style screens (the top-right collided with centred titles)
var item_use_cb: Callable = Callable()     # battle: called with the item id when an ACTIVE item icon is clicked

func _ready() -> void:
	position = Vector2.ZERO
	size = Vector2(640, 34)
	add_child(UITheme.panel(Rect2(0, 0, 640, 34), Color("#10160b"), Color("#33471f")))
	portrait = UITheme.icon("raptor_baby", 30)
	portrait.position = Vector2(3, 2)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(portrait)
	form_label = UITheme.label("", 15, UITheme.C_GOLD)
	form_label.position = Vector2(36, 1)
	add_child(form_label)
	hp_bar = StatBar.new().setup("icon_heart", UITheme.C_RED, Vector2(88, 22))
	hp_bar.position = Vector2(102, 6)
	add_child(hp_bar)
	hunger_bar = StatBar.new().setup("icon_meat", Color("#d88a3a"), Vector2(88, 22))
	hunger_bar.position = Vector2(194, 6)
	add_child(hunger_bar)
	xp_bar = StatBar.new().setup("", Color("#6fa8e8"), Vector2(84, 22))
	xp_bar.position = Vector2(286, 6)
	add_child(xp_bar)
	weather_icon = UITheme.icon("icon_clear", 11)
	weather_icon.position = Vector2(376, 11)
	add_child(weather_icon)
	weather_label = UITheme.label("", 15, UITheme.C_TEXT)
	weather_label.position = Vector2(390, 9)
	add_child(weather_label)
	var wh := Control.new()
	wh.position = Vector2(372, 3)
	wh.size = Vector2(80, 28)
	wh.name = "WeatherHover"
	add_child(wh)
	stage_label = UITheme.label("", 15, UITheme.C_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	stage_label.position = Vector2(450, 9)
	stage_label.size = Vector2(138, 16)
	add_child(stage_label)
	deck_btn = UITheme.button("Deck", 15, Vector2(46, 24))
	deck_btn.position = Vector2(592, 5)
	deck_btn.size = Vector2(46, 24)
	deck_btn.pressed.connect(_open_deck)
	add_child(deck_btn)
	refresh()

## Item inventory row (icons with tooltips; rarity-coloured frames).
func refresh_items() -> void:
	var r: RunState = Game.run
	if r == null:
		return
	if diet_meter == null:
		diet_meter = DietMeter.new()
		add_child(diet_meter)
	diet_meter.position = diet_origin
	diet_meter.refresh()
	if items_row == null:
		items_row = Control.new()
		items_row.position = items_origin
		items_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(items_row)
	items_row.position = items_origin
	for c in items_row.get_children():
		c.queue_free()
	var x := 0.0
	for id in r.items:
		var holder := Control.new()
		holder.position = Vector2(x, 0)
		holder.size = Vector2(17, 17)
		var tip := ItemUI.tooltip(String(id))
		holder.name = "item_" + String(id)
		var active: bool = DB.item(String(id)).has("use")
		var b = get("battle")
		var ready_now: bool = active and b != null and b.item_usable(String(id))
		if active:
			tip += "\n" + ("Click to use (once per battle)." if ready_now else ("Used this battle." if b != null and b.items_used.has(String(id)) else "Usable during your turn in a fight."))
			holder.gui_input.connect(func(e: InputEvent):
				if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and item_use_cb.is_valid():
					item_use_cb.call(String(id)))
		holder.set_meta("tip", tip)
		Keywords.attach_tip(holder, String(DB.item(String(id))["name"]) + "  [" + String(DB.item(String(id))["rarity"]).capitalize() + "]", tip.substr(tip.find("\n") + 1), "#" + ItemUI.rarity_color(String(id)).to_html(false))
		var frame := ColorRect.new()
		frame.color = ItemUI.rarity_color(String(id))
		frame.size = Vector2(17, 17)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(frame)
		var inner := ColorRect.new()
		inner.color = Color(0.05, 0.07, 0.12)
		inner.position = Vector2(1, 1)
		inner.size = Vector2(15, 15)
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(inner)
		var ic := TextureRect.new()
		ic.texture = ItemUI.texture(String(id))
		ic.position = Vector2(2, 2)
		ic.size = Vector2(13, 13)
		ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if active and not ready_now:
			ic.modulate = Color(1, 1, 1, 0.45)
		holder.add_child(ic)
		if ready_now:
			var dot := ColorRect.new()
			dot.color = Color("#f0c050")
			dot.position = Vector2(13, 1)
			dot.size = Vector2(3, 3)
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			holder.add_child(dot)
		items_row.add_child(holder)
		x += 19.0

func _open_deck() -> void:
	if Game.run != null and Game.main != null:
		Game.main.open_deck_overlay()

func refresh() -> void:
	var r: RunState = Game.run
	if r == null:
		return
	portrait.texture = SpriteFactory.get_texture(r.form_sprite_id())
	form_label.text = "%s\nLv %d" % [String(r.form()["name"]), r.level]
	form_label.position = Vector2(36, 1)
	var hp := r.hp if hp_override < 0 else hp_override
	hp_bar.set_values(hp, r.max_hp())
	hunger_bar.set_values(r.hunger, r.hunger_max())
	var hs := r.hunger_state()
	hunger_bar.fill_color = Color("#d88a3a") if hs == "ok" else (Color("#e0602a") if hs == "low" else Color("#c02020"))
	hunger_bar.tooltip_text = "Hunger: drops %d per room. %s" % [r.hunger_cost(), {"ok": "Well fed.", "low": "LOW: -1 stamina, speed x0.8.", "starving": "STARVING: HP loss each room!"}[hs]]
	hp_bar.tooltip_text = "Health"
	var nxt := r.xp_to_next()
	if nxt > 0:
		var xb := int(round(r.xp_bonus() * 100.0))
		xp_bar.set_values(r.xp, nxt, "XP %d/%d%s" % [r.xp, nxt, ("  +%d%%" % xb) if xb > 0 else ""])
	else:
		xp_bar.set_values(1, 1, "MAX")
	xp_bar.tooltip_text = "Experience. Next forms at level 3, 5 and 7.\nDiet quality %s: %s" % [r.diet_quality(), ("+%d%% XP from every fight (good eating speeds up growth)" % int(round(r.xp_bonus() * 100.0))) if r.xp_bonus() > 0.0 else "no growth bonus yet - eat what suits your species"]
	if not r.stage.is_empty():
		var w := r.weather_id()
		if w != "":
			var wd: Dictionary = DB.weather(w)
			weather_icon.texture = SpriteFactory.get_texture(String(wd["icon"]))
			weather_label.text = String(wd["name"])
			var tip := "%s\n%s" % [wd["name"], wd["desc"]]
			var lines := WeatherSys.describe_for(w, r.tags())
			if not lines.is_empty():
				tip += "\nOn you: " + ", ".join(lines)
			get_node("WeatherHover").tooltip_text = tip
		stage_label.text = "Stage %d  Room %d/%d" % [r.stage_idx + 1, mini(int(r.stage["step"]) + 1, r.stage["steps"].size()), r.stage["steps"].size()]
	if r.spores > 0:
		hp_bar.tooltip_text = "Health (infected: %d spores)" % r.spores
	refresh_items()
