class_name Keywords
extends RefCounted
## Keyword glossary (data/keywords.json): bold + coloured keywords in any text, hover tooltips, and tests helpers.
##   Keywords.rich(text, size, color) -> RichTextLabel   (hover a keyword ~0.9s: tooltip)
##   Keywords.bbcode(text)            -> String with [meta]/[b]/[color] markup
##   Keywords.find(text)              -> keyword ids used in text
##   Keywords.attach_tip(control, title, body)  hover any control for a tooltip with bolded body + keyword definitions

const HOVER_DELAY := 0.9

static var _re: RegEx = null
static var _alias: Dictionary = {}     # surface form -> keyword id
static var _bold: Font = null

static func table() -> Dictionary:
	return DB.table("keywords")["keywords"]

static func op_map() -> Dictionary:
	return DB.table("keywords")["ops"]

static func _build() -> void:
	if _re != null:
		return
	_alias.clear()
	var forms: Array = []
	var kws := table()
	for id in kws:
		var d: Dictionary = kws[id]
		var all: Array = [String(d["name"])]
		all.append_array(d.get("aliases", []))
		for f in all:
			if not _alias.has(String(f)):
				_alias[String(f)] = String(id)
				forms.append(String(f))
	forms.sort_custom(func(a, b): return String(a).length() > String(b).length())
	var esc: Array = []
	for f in forms:
		var r := RegEx.new()
		esc.append(String(f).replace("'", "'").replace("(", "\\(").replace(")", "\\)").replace("+", "\\+").replace(".", "\\."))
	_re = RegEx.new()
	_re.compile("(?<![A-Za-z'])(" + "|".join(esc) + ")(?![A-Za-z])")

## [{text, id}] segments of `text` (id == "" for plain text).
static func segments(text: String) -> Array:
	_build()
	var out: Array = []
	var pos := 0
	for m in _re.search_all(text):
		var s := m.get_start()
		if s > pos:
			out.append({"text": text.substr(pos, s - pos), "id": ""})
		out.append({"text": m.get_string(), "id": String(_alias[m.get_string()])})
		pos = m.get_end()
	if pos < text.length():
		out.append({"text": text.substr(pos), "id": ""})
	return out

static func find(text: String) -> Array:
	var ids: Array = []
	for s in segments(text):
		if String(s["id"]) != "" and not ids.has(s["id"]):
			ids.append(s["id"])
	return ids

static func color_of(id: String) -> String:
	return String(table()[id]["color"])

static func bbcode(text: String, plain_color: String = "", darken: float = 0.0) -> String:
	var out := ""
	for s in segments(text):
		var t := String(s["text"]).replace("[", "[lb]")
		if String(s["id"]) == "":
			out += t if plain_color == "" else "[color=%s]%s[/color]" % [plain_color, t]
		else:
			out += "[url=%s][color=%s][b]%s[/b][/color][/url]" % [s["id"], (color_of(String(s["id"])) if darken <= 0.0 else "#" + Color(color_of(String(s["id"]))).darkened(darken).to_html(false)), t]
	return out

static func bold_font(size: int) -> Font:
	var f := UITheme.font_for(size)
	var v := FontVariation.new()
	v.base_font = f
	v.variation_embolden = 0.65
	v.spacing_glyph = 1
	return v

## A RichTextLabel with the pixel fonts, bold coloured keywords and hover tooltips.
static func rich(text: String, size: int, color: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT, darken: float = 0.0) -> RichTextLabel:
	var px := UITheme.snap(size)
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = false
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	r.meta_underlined = false
	r.add_theme_font_override("normal_font", UITheme.font_for(size))
	r.add_theme_font_override("bold_font", bold_font(size))
	r.add_theme_font_size_override("normal_font_size", px)
	r.add_theme_font_size_override("bold_font_size", px)
	r.add_theme_color_override("default_color", color)
	r.add_theme_constant_override("line_separation", 0)
	r.add_theme_constant_override("outline_size", 0)
	r.horizontal_alignment = align
	r.text = ""
	r.append_text(bbcode(text, "", darken))
	var tip := _TipHover.new()
	tip.owner_label = r
	r.add_child(tip)
	r.meta_hover_started.connect(tip.on_enter)
	r.meta_hover_ended.connect(tip.on_exit)
	return r

## Tooltip popup (shared, one at a time). Created lazily under the root so it floats above any screen.
static var _tip_panel: PanelContainer = null

static func show_tip(host: Node, title: String, body: String, color: String = "#f0c050") -> void:
	hide_tip()
	var layer := CanvasLayer.new()
	layer.layer = 90
	layer.name = "KwTipLayer"
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.07, 0.12, 0.97)
	sb.border_color = Color(color)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := Label.new()
	t.text = title
	UITheme.apply(t, UITheme.SZ_M)
	t.add_theme_color_override("font_color", Color(color))
	vb.add_child(t)
	var b := RichTextLabel.new()
	b.bbcode_enabled = true
	b.fit_content = true
	b.scroll_active = false
	b.custom_minimum_size = Vector2(250, 0)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_theme_font_override("normal_font", UITheme.font_for(UITheme.SZ_S))
	b.add_theme_font_override("bold_font", bold_font(UITheme.SZ_S))
	b.add_theme_font_size_override("normal_font_size", UITheme.snap(UITheme.SZ_S))
	b.add_theme_font_size_override("bold_font_size", UITheme.snap(UITheme.SZ_S))
	b.add_theme_color_override("default_color", UITheme.C_TEXT)
	b.append_text(bbcode(body))
	vb.add_child(b)
	panel.add_child(vb)
	layer.add_child(panel)
	host.get_tree().root.add_child(layer)
	_tip_panel = panel
	panel.reset_size()
	var vp := host.get_viewport().get_visible_rect().size
	var mp := host.get_viewport().get_mouse_position()
	panel.position = Vector2(clampf(mp.x + 14.0, 4.0, vp.x - 270.0), clampf(mp.y + 18.0, 4.0, vp.y - 120.0))
	# keep it fully on screen after it has its final size
	panel.resized.connect(func():
		panel.position = Vector2(clampf(panel.position.x, 4.0, maxf(4.0, vp.x - panel.size.x - 4.0)), clampf(panel.position.y if panel.position.y + panel.size.y < vp.y - 4.0 else mp.y - panel.size.y - 10.0, 4.0, maxf(4.0, vp.y - panel.size.y - 4.0))))

static func hide_tip() -> void:
	if _tip_panel != null and is_instance_valid(_tip_panel):
		var l := _tip_panel.get_parent()
		if l != null:
			l.queue_free()
	_tip_panel = null

static func show_keyword(host: Node, id: String) -> void:
	var d: Dictionary = table()[id]
	show_tip(host, String(d["name"]), String(d["text"]), String(d["color"]))

## Hover any Control for ~0.9s: tooltip with a title, a body (keywords bolded) and the definitions of the keywords it uses.
static func attach_tip(c: Control, title: String, body: String, color: String = "#f0c050", with_defs: bool = true) -> void:
	c.tooltip_text = ""
	if c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		c.mouse_filter = Control.MOUSE_FILTER_PASS
	var h := _TipHover.new()
	h.owner_label = c
	h.title = title
	h.body = body
	h.color = color
	h.defs = with_defs
	c.add_child(h)
	c.mouse_entered.connect(h.start_whole)
	c.mouse_exited.connect(h.on_exit)

## Definitions block for the keywords used in `text` (BBCode), used by item tooltips and the hand zoom panel.
static func defs_text(text: String) -> String:
	var lines: Array = []
	for id in find(text):
		var d: Dictionary = table()[id]
		lines.append("[color=%s][b]%s[/b][/color]: %s" % [d["color"], d["name"], d["text"]])
	return "\n".join(lines)

## A static side panel listing the keywords used in `text` (shown next to the zoomed card in battle).
static func side_panel(text: String, width: float = 230.0) -> Control:
	var ids := find(text)
	if ids.is_empty():
		return null
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.07, 0.12, 0.97)
	sb.border_color = Color("#4a6a8c")
	sb.set_border_width_all(2)
	sb.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b := RichTextLabel.new()
	b.bbcode_enabled = true
	b.fit_content = true
	b.scroll_active = false
	b.custom_minimum_size = Vector2(width, 0)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_theme_font_override("normal_font", UITheme.font_for(UITheme.SZ_S))
	b.add_theme_font_override("bold_font", bold_font(UITheme.SZ_S))
	b.add_theme_font_size_override("normal_font_size", UITheme.snap(UITheme.SZ_S))
	b.add_theme_font_size_override("bold_font_size", UITheme.snap(UITheme.SZ_S))
	b.add_theme_color_override("default_color", UITheme.C_TEXT)
	b.add_theme_constant_override("line_separation", 0)
	b.append_text(defs_text(text).replace("\n", "\n\n"))
	panel.add_child(b)
	return panel

class _TipHover extends Node:
	var owner_label: Control
	var title: String = ""
	var body: String = ""
	var color: String = "#f0c050"
	var defs: bool = true
	var _kw: String = ""
	var _timer: SceneTreeTimer = null
	var _gen: int = 0

	func on_enter(meta) -> void:
		_kw = String(meta)
		_arm()

	func start_whole() -> void:
		_kw = ""
		_arm()

	func _arm() -> void:
		_gen += 1
		var g := _gen
		Keywords.hide_tip()
		var t := owner_label.get_tree().create_timer(Keywords.HOVER_DELAY)
		t.timeout.connect(func():
			if g != _gen or not is_instance_valid(owner_label) or not owner_label.is_visible_in_tree():
				return
			if _kw != "":
				Keywords.show_keyword(owner_label, _kw)
			else:
				var text := body
				if defs:
					var d := Keywords.defs_text(body)
					if d != "":
						text += "\n\n" + d
				Keywords.show_tip(owner_label, title, text, color))

	func on_exit(_meta = null) -> void:
		_gen += 1
		Keywords.hide_tip()

	func _exit_tree() -> void:
		_gen += 1
		Keywords.hide_tip()
