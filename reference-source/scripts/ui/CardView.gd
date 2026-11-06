class_name CardView
extends Control
## Visual card. Click to select/play.

signal clicked(view: CardView)
signal hovered(view: CardView, on: bool)

const W := 80           # hand / deck size (640x360 canvas): art, 2-line name (Jersey15), cost / rarity / type tiles. NO description: it is too small to read,
const H := 80           # so the full text lives on the big card that opens on hover (see BattleScreen._on_card_hover)
const BW := 180         # "big" card (hover zoom, draft, rewards): art at 2x, name 20 px (Jersey20), description 15 px (Jersey15, <= 5 lines for every card, see tests)
const BH := 208

var card_id: String = ""
var card: Dictionary = {}
var index: int = -1
var playable: bool = true
var selected: bool = false
var big: bool = false
var w: int = W
var h: int = H
var reason: String = ""     # why it cannot be played (shown on the big card)
var synergy: Array = []     # archetype tags this card shares with your current build (draft highlight)
var _hover: bool = false
var _text: RichTextLabel
var _name: Label

## Card layers (assets/sprites/card_<layer>_<dark|light>.png, see tools/art/art_card.py and the README "Ability cards"):
## frame, art window, crest (rarity gem), name banner, type ribbon, description box, 3 number tiles, 2 icon slots.
## Attacks wear the light "desert" frame, skills / powers the dark "night" frame (override per card with "frame": "dark"|"light").
const FRAME_MARGIN := [5, 5, 5, 5]
## glyph pixel size: 1 px per cell on the 9 px hand tile (7x7 glyph), 1 px on the big one too (the big tile is 12 px)
const GLYPHS := {
	"attack": ["#.....#", ".#...#.", "..#.#..", "...#...", "..#.#..", ".#...#.", "#.....#"],
	"skill": [".#####.", "#######", "#######", "#######", ".#####.", "..###..", "...#..."],
	"power": ["...#...", "..###..", ".#####.", "#######", ".#####.", "..###..", "...#..."],
}
const RARITY_COL := {"starter": "#c8d0d8", "common": "#c8d0d8", "uncommon": "#6fd24e", "rare": "#5aa0f0", "legendary": "#f0b030", "cave": "#b080ff"}
const TYPE_COL := {"attack": "#d04a3a", "skill": "#3a82d0", "power": "#a050d0"}

## Pixel layout of every layer (card-local px) for the hand card (1x art) or the big card (2x art).
static func layout(big_: bool, h_: int) -> Dictionary:
	if big_:
		return {"win": Rect2(27, 6, 126, 76), "crest": Rect2(74, 1, 32, 12), "banner": Rect2(3, 78, 174, 26), "ribbon": Rect2(9, 104, 162, 15),
			"box": Rect2(3, 118, 174, h_ - 118), "tile": 12, "ctile": 18, "tile_x": 3, "tile_y": [6, 28, 43], "slot_x": 160, "slot_y": [8, 26], "slot": 14,
			"name": Rect2(14, 80, 152, 22), "text": Rect2(9, 121, 162, h_ - 124), "art_src": Rect2(0, 0, 61, 36), "gem": 12, "inset": 2}
	return {"win": Rect2(15, 4, 62, 32), "crest": Rect2(32, 0, 16, 5), "banner": Rect2(3, 37, 74, 33), "ribbon": Rect2(5, 70, 70, 6),
		"box": Rect2(0, 0, 0, 0), "tile": 9, "ctile": 12, "tile_x": 3, "tile_y": [3, 17, 27], "slot_x": 0, "slot_y": [0, 0], "slot": 0,
		"name": Rect2(6, 38, 68, 31), "text": Rect2(0, 0, 0, 0), "art_src": Rect2(1, 4, 58, 28), "gem": 6, "inset": 2}

func variant() -> String:
	var v := String(card.get("frame", ""))
	if v in ["dark", "light"]:
		return v
	return "light" if String(card.get("type", "attack")) == "attack" else "dark"

func setup(id: String, idx: int = -1, big_: bool = false, reason_: String = "") -> CardView:
	card_id = id
	card = DB.card(id)
	index = idx
	big = big_
	reason = reason_
	w = BW if big else W
	h = BH if big else H
	if big and reason != "":
		h += 18
	custom_minimum_size = Vector2(w, h)
	size = Vector2(w, h)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var L := layout(big, h)
	var light := variant() == "light"
	var nr: Rect2 = L["name"]
	_name = UITheme.label(String(card["name"]), UITheme.SZ_L if big else UITheme.SZ_S, Color("#fff4dc"), HORIZONTAL_ALIGNMENT_CENTER)
	_name.position = nr.position
	_name.size = nr.size
	_name.autowrap_mode = TextServer.AUTOWRAP_OFF if big else TextServer.AUTOWRAP_WORD_SMART
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS if big else TextServer.OVERRUN_NO_TRIMMING
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name.add_theme_constant_override("line_spacing", -2)
	UITheme.shadow(_name)
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name)
	if big:
		var tr: Rect2 = L["text"]
		_text = Keywords.rich(String(card["text"]), UITheme.SZ_S, Color("#5a3826") if light else Color("#e4eef0"), HORIZONTAL_ALIGNMENT_LEFT, 0.5 if light else 0.0)
		_text.position = tr.position
		_text.size = tr.size
		_text.add_theme_constant_override("line_separation", -1)
		add_child(_text)
	if reason != "":
		var rl := UITheme.label("Can't play: " + reason, UITheme.SZ_S, Color("#ffd0c8") if not light else Color("#a02818"), HORIZONTAL_ALIGNMENT_CENTER)
		rl.position = Vector2(5, h - 17)
		rl.size = Vector2(w - 10, 16)
		rl.clip_text = true
		rl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(rl)
	return self

func _type_color() -> Color:
	return Color(String(TYPE_COL.get(String(card["type"]), "#a050d0")))

func _layer(name: String) -> String:
	return "card_%s_%s" % [name, variant()]

func _nine(name: String, rect: Rect2, m: Array, tint: Color) -> void:
	var tex := SpriteFactory.png(_layer(name))
	if tex == null:
		return
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = m[0]
	sb.texture_margin_top = m[1]
	sb.texture_margin_right = m[2]
	sb.texture_margin_bottom = m[3]
	sb.modulate_color = tint
	draw_style_box(sb, rect)

func _glyph(kind: String, at: Rect2, col: Color, sc: int) -> void:
	var rows: Array = GLYPHS.get(kind, GLYPHS["power"])
	var o := at.position + ((at.size - Vector2(7 * sc, 7 * sc)) * 0.5).floor()
	for y in 7:
		for x in 7:
			if String(rows[y])[x] == "#":
				draw_rect(Rect2(o + Vector2(x * sc, y * sc), Vector2(sc, sc)), col)

func _draw() -> void:
	var dim := 1.0 if playable else 0.62
	var tint := Color(dim, dim, dim, 1)
	var L := layout(big, h)
	var sc := 2 if big else 1
	var light := variant() == "light"
	# 1. card body + frame
	_nine("frame", Rect2(0, 0, w, h), FRAME_MARGIN, tint)
	# 2. illustration (assets/sprites/card_<id>.png, 92x54) in the art window: 1x (hand, 37 rows) or 2x (big, cropped to 84 cols)
	var win: Rect2 = L["win"]
	var inner := win.grow(-float(L["inset"]))
	draw_rect(inner, Color("#14162a") if not light else Color("#8fcfc0"))
	var art := SpriteFactory.png("card_" + card_id)
	if art != null:
		draw_texture_rect_region(art, inner, L["art_src"], tint)
	else:
		draw_texture(SpriteFactory.get_texture(String(card.get("icon", "icon_claw"))), (inner.get_center() - Vector2(5, 5)).round(), tint)
	_nine("artwin", win, [2, 2, 2, 2], tint)
	# 3. crest tab with the rarity gem
	var cr: Rect2 = L["crest"]
	var ct := SpriteFactory.png(_layer("crest"))
	if ct != null:
		draw_texture_rect(ct, cr, false, tint)
	var rar := String(card.get("rarity", "common"))
	var gc := Color(String(RARITY_COL.get(rar, "#c8d0d8")))
	var gw := int(L["gem"])
	var gp := cr.position + (Vector2(10, 4) if big else Vector2(5, 2))
	draw_rect(Rect2(gp, Vector2(gw, gw / 2)), gc * tint)
	draw_rect(Rect2(gp, Vector2(gw, sc)), gc.lightened(0.5) * tint)
	# 4. name banner (the name label sits on it), 5. type ribbon, 6. description box
	_nine("banner", L["banner"], [11, 5, 11, 5], tint)
	var rb: Rect2 = L["ribbon"]
	_nine("ribbon", rb, [7, 2, 7, 2], tint)
	var tc := _type_color()
	var ty := String(card["type"])
	if big:
		var rcol := Color("#fff0cf") if light else tc.lightened(0.55)
		UITheme.draw_text_in(self, rb, ty.to_upper(), UITheme.SZ_S, rcol * tint, HORIZONTAL_ALIGNMENT_CENTER, true)
	else:
		var bar := Rect2(rb.position.x + rb.size.x * 0.5 - 9, rb.position.y + 2, 18, 1)
		draw_rect(bar, tc.lightened(0.35) * tint)
	if (L["box"] as Rect2).size.x > 0.0:
		_nine("textbox", L["box"], [4, 4, 4, 4], tint)
	# 7. number tiles: stamina cost (bigger tile, live number), rarity gem, card type glyph
	var ts := int(L["tile"])
	var cts := int(L["ctile"])
	var tx := float(L["tile_x"])
	var tys: Array = L["tile_y"]
	var tiles: Array = [Rect2(tx, float(tys[0]), cts, cts), Rect2(tx + float(cts - ts) / 2.0, float(tys[1]), ts, ts), Rect2(tx + float(cts - ts) / 2.0, float(tys[2]), ts, ts)]
	for i in 3:
		_nine("tile", tiles[i], [2, 2, 2, 2], tint)
	var cs := str(int(card["cost"]))
	UITheme.draw_text_in(self, tiles[0], cs, UITheme.SZ_L if big else UITheme.SZ_S, (Color("#fff4dc") if light else Color("#f4f6e4")) * tint, HORIZONTAL_ALIGNMENT_CENTER, true)
	var gem2: Rect2 = (tiles[1] as Rect2).grow(float(-2 if not big else -3))
	draw_rect(gem2, Color(0, 0, 0, 0.55))
	draw_rect(gem2.grow(-1.0), gc * tint)
	_glyph(ty, tiles[2], tc.lightened(0.15 if light else 0.4) * tint, 1)
	# 8. archetype tags in the two icon slots (big card only; data/archetypes.json colours; gold edge when it is a synergy)
	var tags: Array = card.get("tags", [])
	var sl := int(L["slot"])
	if sl > 0:
		for i in 2:
			var sr := Rect2(float(L["slot_x"]), float((L["slot_y"] as Array)[i]), sl, sl)
			_nine("slot", sr, [2, 2, 2, 2], tint)
			if i < tags.size():
				var tcol := Arch.color_of(String(tags[i]))
				var pip := sr.grow(-3.0)
				draw_rect(pip, tcol * tint)
				draw_rect(Rect2(pip.position, Vector2(pip.size.x, 1)), tcol.lightened(0.5) * tint)
				if synergy.has(tags[i]):
					draw_rect(sr, Color("#ffe890"), false, 1.0)
	elif not tags.is_empty() and not synergy.is_empty() and synergy.has(tags[0]):
		draw_rect(Rect2(w - 9.0, 6, 5, 5), Color("#ffe890"))
	if selected:
		draw_rect(Rect2(1, 1, w - 2, h - 2), Color("#ffd24a"), false, 2.0)
	elif _hover and playable:
		draw_rect(Rect2(1, 1, w - 2, h - 2), Color(0.7, 1.0, 0.7, 0.8), false, 1.0)
	if not synergy.is_empty():
		var gp2 := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 220.0)
		draw_rect(Rect2(1, 1, w - 2, h - 2), Color(1.0, 0.85, 0.3, gp2), false, 2.0)
	if not playable:
		draw_rect(Rect2(3, 3, w - 6, h - 6), Color(0, 0, 0, 0.22))

func _process(_d: float) -> void:
	if not synergy.is_empty():
		queue_redraw()

func set_state(playable_: bool, selected_: bool) -> void:
	playable = playable_
	selected = selected_
	queue_redraw()

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self)

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER:
		_hover = true
		hovered.emit(self, true)
		queue_redraw()
	elif what == NOTIFICATION_MOUSE_EXIT:
		_hover = false
		hovered.emit(self, false)
		queue_redraw()
