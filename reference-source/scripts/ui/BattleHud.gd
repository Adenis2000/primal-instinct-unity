class_name BattleHud
extends Hud
## Battle HUD (matches the mock-up): top-left portrait + HP / Hunger / Stamina panel, top-right weather + stage.

var battle: Battle
var bars: Dictionary = {}
var status_label: Label
var lv_label: Label
var pile_label: Label
var _name_label: Label

const ITEMS_AT := Vector2(3, 33)      # top-left strip under the turn order: items, then the diet meter
const DIET_AT := Vector2(4, 53)

## Layout on the 640x360 canvas (no backing panels over the board): top-left turn order (BattleScreen) + items, top-centre weather / stage strip,
## top-right character card (portrait, name, HP / stamina / hunger bars, draw / discard counts, Deck button), bottom-right Move / End Turn, bottom-centre hand.
func _a(n: Control, mode: String) -> Control:
	return UITheme.anchor(n, mode, _off)

func _ready() -> void:
	items_origin = ITEMS_AT
	diet_origin = DIET_AT
	position = Vector2.ZERO
	size = Vector2(640, 360)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# --- top-right: player card
	# no backing panel / frame: "PlayerCard" is an invisible layout box (bars + portrait sit directly over the board, labels get a shadow)
	var card := Control.new()
	card.name = "PlayerCard"
	card.position = Vector2(438, 2)
	card.size = Vector2(200, 96)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_a(add_p(card), "RT")
	portrait = UITheme.icon("portrait_baby", 43)
	portrait.position = Vector2(594, 3)
	portrait.size = Vector2(43, 43)
	_a(add_p(portrait), "RT")
	lv_label = UITheme.label("Lv. 1", 15, UITheme.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	UITheme.shadow(lv_label)
	lv_label.position = Vector2(590, 47)
	lv_label.size = Vector2(47, 16)
	_a(add_p(lv_label), "RT")
	_name_label = UITheme.label("Velociraptor", 15, Color.WHITE)
	UITheme.shadow(_name_label)
	_name_label.position = Vector2(484, 1)
	_a(add_p(_name_label), "RT")
	status_label = UITheme.label("", 15, UITheme.C_GREEN, HORIZONTAL_ALIGNMENT_RIGHT)
	UITheme.shadow(status_label)
	status_label.position = Vector2(554, 1)
	status_label.size = Vector2(52, 16)
	_a(add_p(status_label), "RT")
	# health (full sprite with the wing + number tab) on top, then stamina, then hunger (slim variants, recoloured fill)
	var defs := [["hp", "full", "hp", "", Vector2(484, 17), Vector2(106, 23)],
		["stamina", "slim", "stamina", "icon_stamina", Vector2(484, 44), Vector2(106, 16)],
		["hunger", "slim", "hunger", "icon_meat", Vector2(484, 62), Vector2(106, 16)]]
	for d in defs:
		var b := BarSprite.new()
		b.kind = d[1]
		b.fill_id = d[2]
		b.icon_id = d[3]
		b.position = d[4]
		b.size = d[5]
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		_a(add_p(b), "RT")
		bars[d[0]] = b
	# --- top-centre: weather + stage strip
	_a(add_p(UITheme.panel(Rect2(208, 2, 228, 20))), "T")
	weather_icon = UITheme.icon("icon_clear", 11)
	weather_icon.position = Vector2(213, 6)
	weather_icon.size = Vector2(11, 11)
	weather_icon.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	weather_icon.stretch_mode = TextureRect.STRETCH_KEEP
	_a(add_p(weather_icon), "T")
	weather_label = UITheme.label("", 15, UITheme.C_TEXT)
	weather_label.position = Vector2(228, 3)
	_a(add_p(weather_label), "T")
	stage_label = UITheme.label("", 15, UITheme.C_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	stage_label.position = Vector2(318, 3)
	stage_label.size = Vector2(114, 16)
	_a(add_p(stage_label), "T")
	var wh := Control.new()
	wh.position = Vector2(208, 2)
	wh.size = Vector2(228, 20)
	wh.name = "WeatherHover"
	_a(add_p(wh), "T")
	# --- gear button (Settings) next to the weather strip
	_a(add_p(UITheme.gear_button(Rect2(440, 2, 20, 20), _open_settings)), "T")
	# --- under the player card: draw/discard counts + Deck button
	deck_btn = UITheme.button("Deck", 15, Vector2(46, 20))
	deck_btn.position = Vector2(590, 66)
	deck_btn.size = Vector2(46, 20)
	deck_btn.pressed.connect(_open_deck)
	_a(add_p(deck_btn), "RT")
	pile_label = UITheme.label("", 15, UITheme.C_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	UITheme.shadow(pile_label)
	pile_label.position = Vector2(438, 80)
	pile_label.size = Vector2(150, 16)
	_a(add_p(pile_label), "RT")
	refresh()

func add_p(c: Control) -> Control:
	add_child(c)
	return c

## Hug the real screen corners (see _a): re-applied whenever the window/frame offset changes.
func anchor_to(off: Vector2) -> void:
	_off = off
	for ch in get_children():
		if ch is Control and ch.has_meta("amode"):
			UITheme.reanchor(ch, off)
	items_origin = ITEMS_AT - off
	diet_origin = DIET_AT - off
	if items_row != null:
		items_row.position = items_origin
	if diet_meter != null:
		diet_meter.position = diet_origin

var _off: Vector2 = Vector2.ZERO

func refresh() -> void:
	var r: RunState = Game.run
	if r == null or bars.is_empty():
		return
	portrait.texture = SpriteFactory.png("portrait_" + String(r.form()["id"])) if SpriteFactory.png("portrait_" + String(r.form()["id"])) != null else SpriteFactory.get_texture(r.form_sprite_id())
	_name_label.text = String(r.species["name"])
	lv_label.text = "Lv. %d" % r.level
	var hp := r.hp if hp_override < 0 else hp_override
	var b: BarSprite = bars["hp"]
	b.set_vals(hp, r.max_hp(), "%d/%d" % [hp, r.max_hp()])
	b.tooltip_text = "Health" if r.spores <= 0 else "Health (infected: %d spores)" % r.spores
	var hb: BarSprite = bars["hunger"]
	hb.set_vals(r.hunger, r.hunger_max(), "%d/%d" % [r.hunger, r.hunger_max()])
	var hs := r.hunger_state()
	hb.tint = Color.WHITE if hs == "ok" else (Color(1.0, 0.78, 0.66) if hs == "low" else Color(1.0, 0.55, 0.55))
	hb.tooltip_text = "Hunger: drops %d per room. %s" % [r.hunger_cost(), {"ok": "Well fed.", "low": "LOW: -1 stamina, speed x0.8.", "starving": "STARVING: HP loss each room!"}[hs]]
	var sb: BarSprite = bars["stamina"]
	if battle != null:
		sb.set_vals(battle.stamina, maxf(1.0, battle.stamina_max), "%d/%d" % [battle.stamina, battle.stamina_max])
		if battle.is_hidden():
			status_label.text = "UNSPOTTED"
			status_label.add_theme_color_override("font_color", UITheme.C_GREEN)
		else:
			status_label.text = "SPOTTED"
			status_label.add_theme_color_override("font_color", UITheme.C_RED)
		pile_label.text = "Draw %d Disc %d Exh %d" % [battle.draw_pile.size(), battle.discard_pile.size(), battle.exhausted.size()]
	sb.tooltip_text = "Stamina: each card costs stamina. Refills fully every turn."
	refresh_items()
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

func _open_settings() -> void:
	if Game.main != null:
		Game.main.open_settings()
