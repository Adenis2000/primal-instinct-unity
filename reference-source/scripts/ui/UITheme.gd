class_name UITheme
extends RefCounted
## Shared look & feel helpers. All UI is built in code with these.

const C_TEXT := Color("#e8f0f8")
const C_DIM := Color("#8fa4b8")
const C_GOLD := Color("#f0c050")
const C_PANEL := Color("#14202e")
const C_PANEL2 := Color("#1c2c40")
const C_BORDER := Color("#4a6a8c")
const C_RED := Color("#e04050")
const C_GREEN := Color("#6fc24e")
const C_BLUE := Color("#6fa8e8")

# ---------------------------------------------------------------- type scale (assets/fonts: Jersey 10 / 15 / 20 / 25, SIL OFL)
# The game renders on a 640x360 native canvas (integer-scaled), and Jersey is a pixel font drawn on a 10 / 15 / 20 / 25 px grid.
# Callers still ask for the four DESIGN classes (S 15, M 20, L 30, XL 40, anything in between is snapped);
# snap() turns a class into the real pixel size, each an exact multiple of its font's grid, so every glyph stays razor sharp.
# READABILITY RULE: no text below 15 px native (Jersey 10 is kept only for the tiny non-essential tags that pass `tiny`, see PX_TAG):
#   Normal:  S -> 15 (Jersey15)  card text, tooltips, log, captions, hints      M -> 15 (Jersey15)  body, labels, buttons
#            L -> 20 (Jersey20)  headings, numbers                              XL -> 30 (Jersey15 at 200%)  titles
#   Large:   S -> 20 (Jersey20)  M -> 20 (Jersey20)  L -> 25 (Jersey25)  XL -> 30  (Settings -> Text size; layouts are tested in both)
const SZ_S := 15
const SZ_M := 20
const SZ_L := 30
const SZ_XL := 40
const PX_TAG := 10      # Jersey10: tiny, non-essential tags only (never body text); pass size TAG to opt in
const TAG := 1
const PX_S := 15
const PX_M := 15
const PX_L := 20
const PX_XL := 30
static var text_large := false      # Settings -> Text size (Normal / Large), set by Settings.apply

static var _fonts: Dictionary = {}

## Design size (any number) -> real pixel size: 10 / 15 / 20 / 30.
static func snap(size: int) -> int:
	if size == TAG:
		return PX_TAG
	if text_large:
		if size <= 24:
			return 20
		if size <= 34:
			return 25
		return PX_XL
	if size <= 24:
		return PX_M
	if size <= 34:
		return PX_L
	return PX_XL

static func _load_font(path: String) -> Font:
	var res = load(path)
	if res is FontFile:
		res.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		res.hinting = TextServer.HINTING_NONE
		res.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		res.generate_mipmaps = false
		res.force_autohinter = false
		return res
	return ThemeDB.fallback_font

## The font for a REAL pixel size (10 / 15 / 20 / 30).
static func font_px(px: int) -> Font:
	var key := "j10" if px == PX_TAG else ("j20" if px == 20 else ("j25" if px == 25 else "j15"))
	if not _fonts.has(key):
		var path: String = {"j10": "res://assets/fonts/Jersey10-Regular.ttf", "j15": "res://assets/fonts/Jersey15-Regular.ttf", "j20": "res://assets/fonts/Jersey20-Regular.ttf", "j25": "res://assets/fonts/Jersey25-Regular.ttf"}[key]
		_fonts[key] = _load_font(path)
	return _fonts[key]

## The font for a design size (S / M / L / XL or anything in between).
static func font_for(size: int) -> Font:
	return font_px(snap(size))

static func font() -> Font:
	return font_for(SZ_S)

## Give any Control the matching font + snapped size (use instead of add_theme_font_size_override).
static func apply(c: Control, size: int) -> void:
	var px := snap(size)
	c.add_theme_font_override("font", font_px(px))
	c.add_theme_font_size_override("font_size", px)
	# a node that is not in the tree yet does not refresh its theme cache, so its minimum size would still be the default font's and clamp
	# any `size = ...` set before add_child: refresh it now
	c.notification(Control.NOTIFICATION_THEME_CHANGED)

## Width/height of a string at a (snapped) size.
static func text_size(text: String, size: int) -> Vector2:
	var px := snap(size)
	return font_px(px).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px)

## Draw text vertically centred in `rect` (horizontal: LEFT / CENTER / RIGHT), pixel-snapped.
static func draw_text_in(ci: CanvasItem, rect: Rect2, text: String, size: int, color: Color = Color.WHITE, align: int = HORIZONTAL_ALIGNMENT_CENTER, outline: bool = true) -> void:
	var px := snap(size)
	var f := font_px(px)
	var ts := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px)
	var x := rect.position.x
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x += (rect.size.x - ts.x) / 2.0
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x += rect.size.x - ts.x
	var y := rect.position.y + (rect.size.y - f.get_height(px)) / 2.0 + f.get_ascent(px)
	draw_text(ci, Vector2(x, y), text, px, color, HORIZONTAL_ALIGNMENT_LEFT, -1.0, outline)

## Crisp text for _draw(): dark outline/shadow underneath so it reads over any art. `pos` is the baseline-left point.
static func draw_text(ci: CanvasItem, pos: Vector2, text: String, size: int, color: Color = Color.WHITE, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0, outline: bool = true) -> void:
	var px := snap(size)
	var f := font_px(px)
	pos = pos.round()
	if outline:
		ci.draw_string_outline(f, pos, text, align, width, px, 1, Color(0.02, 0.03, 0.06, 0.95))
	ci.draw_string(f, pos, text, align, width, px, color)

## Pixel-art 9-slice box from assets/sprites/<tex>.png (generated by tools/gen_art.py; drop in your own to restyle).
static func sbox(tex_name: String, margin: int = 5, pad: int = 4) -> StyleBox:
	var tex := SpriteFactory.png(tex_name)
	if tex == null:
		return box(C_PANEL, C_BORDER, 1, 0, pad)
	var s := StyleBoxTexture.new()
	s.texture = tex
	s.texture_margin_left = margin
	s.texture_margin_right = margin
	s.texture_margin_top = margin
	s.texture_margin_bottom = margin
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad - 1
	s.content_margin_bottom = pad - 1
	s.draw_center = true
	return s

## Button face (assets/sprites/ui_btn*.png, 25x14 px, see README "Button sprites"): 9-slice margins per file (left, top, right, bottom).
## Content margins keep the label inside the tan face (above the red lower edge and the lavender plate).
const BTN_MARGINS := {
	"ui_btn": [5, 2, 5, 7], "ui_btn_hover": [5, 2, 5, 7], "ui_btn_disabled": [5, 2, 5, 7],
	"ui_btn_cyan": [5, 2, 5, 7], "ui_btn_cyan_hover": [5, 2, 5, 7], "ui_btn_pressed": [5, 3, 5, 5],
}
const BTN_PAD := {"ui_btn_pressed": [4, 3, 4, 3]}   # label sinks 1px with the face
const BTN_PAD_DEFAULT := [4, 1, 4, 5]

static func btn_box(tex_name: String) -> StyleBox:
	var tex := SpriteFactory.png(tex_name)
	if tex == null:
		return box(C_PANEL2, C_BORDER, 1, 0, 5)
	var m: Array = BTN_MARGINS.get(tex_name, [5, 2, 5, 7])
	var pd: Array = BTN_PAD.get(tex_name, BTN_PAD_DEFAULT)
	var s := StyleBoxTexture.new()
	s.texture = tex
	s.texture_margin_left = m[0]
	s.texture_margin_top = m[1]
	s.texture_margin_right = m[2]
	s.texture_margin_bottom = m[3]
	s.content_margin_left = pd[0]
	s.content_margin_top = pd[1]
	s.content_margin_right = pd[2]
	s.content_margin_bottom = pd[3]
	s.draw_center = true
	s.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	s.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	return s

## Toggle / selected look for a Button (move mode on, chosen option): the teal face; off = back to the theme's tan face.
static func set_selected(b: Button, on: bool) -> void:
	if on:
		b.add_theme_stylebox_override("normal", btn_box("ui_btn_cyan"))
		b.add_theme_stylebox_override("hover", btn_box("ui_btn_cyan_hover"))
		b.add_theme_stylebox_override("pressed", btn_box("ui_btn_cyan_hover"))
	else:
		for st in ["normal", "hover", "pressed"]:
			b.remove_theme_stylebox_override(st)

static func box(bg: Color, border: Color = C_BORDER, bw: int = 1, radius: int = 0, pad: int = 4) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad - 1
	s.content_margin_bottom = pad - 1
	s.anti_aliasing = false
	return s

static func build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font_for(SZ_S)
	t.default_font_size = snap(SZ_S)
	t.set_color("font_color", "Label", C_TEXT)
	t.set_stylebox("normal", "Button", btn_box("ui_btn"))
	t.set_stylebox("hover", "Button", btn_box("ui_btn_hover"))
	t.set_stylebox("pressed", "Button", btn_box("ui_btn_pressed"))
	t.set_stylebox("disabled", "Button", btn_box("ui_btn_disabled"))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	# white label with a dark-brown outline (like the supplied sprite), centred in the face
	t.set_color("font_color", "Button", Color.WHITE)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color("#f3e8d8"))
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color("#a8a4a0"))
	t.set_color("font_outline_color", "Button", Color("#2a1608"))
	t.set_constant("outline_size", "Button", 1)
	t.set_stylebox("panel", "PanelContainer", sbox("ui_panel", 5, 6))
	t.set_stylebox("panel", "Panel", sbox("ui_panel", 5, 6))
	t.set_stylebox("normal", "LineEdit", sbox("ui_panel_dim", 4, 4))
	t.set_color("font_color", "LineEdit", C_TEXT)
	t.set_color("font_placeholder_color", "LineEdit", C_DIM)
	t.set_stylebox("panel", "TooltipPanel", sbox("ui_panel_gold", 5, 4))
	t.set_font_size("font_size", "TooltipLabel", snap(SZ_S))
	t.set_font("font", "TooltipLabel", font_for(SZ_S))
	# light text on dark panels + a 1px drop shadow everywhere (reads over art as well)
	for cls in ["Label", "TooltipLabel"]:
		t.set_color("font_shadow_color", cls, Color(0, 0, 0, 0.75))
		t.set_constant("shadow_offset_x", cls, 1)
		t.set_constant("shadow_offset_y", cls, 1)
	t.set_constant("line_spacing", "Label", 1)
	t.set_font("font", "Button", font_for(SZ_M))
	t.set_font_size("font_size", "Button", snap(SZ_M))
	t.set_font("font", "LineEdit", font_for(SZ_M))
	t.set_font_size("font_size", "LineEdit", snap(SZ_M))
	return t

static func label(text: String, size: int = 16, color: Color = C_TEXT, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	apply(l, size)            # font first: a Label caches its minimum size, and a later `size = ...` is clamped to it
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l

## Dark-brown outline so a Label reads on the tan button face (use for labels placed on top of a Button).
static func outline(l: Label) -> void:
	l.add_theme_color_override("font_outline_color", Color("#2a1608"))
	l.add_theme_constant_override("outline_size", 1)

## Soft drop shadow + hairline dark outline so text / icons read straight over the board (HUD elements that have no backing panel).
static func shadow(l: Label) -> void:
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("outline_size", 1)

static func button(text: String, size: int = 16, min_size: Vector2 = Vector2.ZERO) -> Button:
	var b := Button.new()
	apply(b, size)
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	return b

static func icon(id: String, px: int = 16) -> TextureRect:
	var r := TextureRect.new()
	r.texture = SpriteFactory.get_texture(id)
	r.custom_minimum_size = Vector2(px, px)
	r.size = Vector2(px, px)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

## kind: "ui_panel" (navy), "ui_panel_gold" (selected/important), "ui_panel_dim", "ui_panel_green", "ui_panel_red".
## The legacy colour arguments pick a matching variant: a gold border gives the gold panel.
static func panel(rect: Rect2, bg: Color = C_PANEL, border: Color = C_BORDER, kind: String = "") -> Panel:
	var p := Panel.new()
	p.position = rect.position
	p.size = rect.size
	if kind == "":
		kind = "ui_panel_gold" if border == C_GOLD else "ui_panel"
	p.add_theme_stylebox_override("panel", sbox(kind, 5, 4))
	return p

static func full_rect(c: Control) -> void:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = 0
	c.offset_top = 0
	c.offset_right = 0
	c.offset_bottom = 0


## Legacy big-window helper (the 640x360 canvas never grows, `off` is always zero); `off` is the margin on each side.
## Anchor modes (any of L R T B): L moves a node by -off.x, R by +off.x, T by -off.y, B by +off.y, so it hugs the REAL screen corner/edge.
## The design position is remembered in meta "abase" so re-anchoring on every resize never drifts.
static func anchor(n: Control, mode: String, off: Vector2) -> Control:
	if not n.has_meta("abase"):
		n.set_meta("abase", n.position)
	n.set_meta("amode", mode)
	var base: Vector2 = n.get_meta("abase")
	var sh := Vector2.ZERO
	if "L" in mode:
		sh.x = -off.x
	if "R" in mode:
		sh.x = off.x
	if "T" in mode:
		sh.y = -off.y
	if "B" in mode:
		sh.y = off.y
	n.position = base + sh
	return n

static func reanchor(n: Control, off: Vector2) -> void:
	if n.has_meta("amode"):
		anchor(n, String(n.get_meta("amode")), off)

## Small gear button that opens the Settings panel (Esc does too).
static func gear_button(rect: Rect2, cb: Callable) -> Button:
	var b := Button.new()
	b.position = rect.position
	b.size = rect.size
	b.focus_mode = Control.FOCUS_NONE
	b.icon = SpriteFactory.get_texture("icon_gear")
	b.expand_icon = false
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.tooltip_text = "Settings (Esc)"
	b.name = "gear_btn"
	b.pressed.connect(cb)
	return b
