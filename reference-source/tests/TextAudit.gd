class_name TextAudit
extends RefCounted
## Programmatic legibility audit of everything visible in a tree: every text element must (1) use a real pixel size of at least MIN_PX
## (Jersey10 `tiny` tags excepted), (2) fit its box (no clipped / trimmed / overflowing text), (3) lie on the 640x360 canvas and inside a
## Panel parent. Returns human-readable issue strings (empty = fine). Used by tests/run_tests.gd and printed by tests/Gallery.gd.

const MIN_PX := 15

static func scan(root: Node, canvas: Vector2 = Vector2(640, 360), min_px: int = MIN_PX) -> Array:
	var out: Array = []
	_walk(root, out, canvas, min_px)
	return out

static func _walk(n: Node, out: Array, canvas: Vector2, min_px: int) -> void:
	if n is CanvasItem and not (n as CanvasItem).visible:
		return
	if n.has_meta("audit_skip"):
		return
	if n is Control:
		_check(n as Control, out, canvas, min_px)
	for c in n.get_children():
		_walk(c, out, canvas, min_px)

static func _name(c: Control) -> String:
	return "%s(%s)" % [c.name, c.get_class()]

static func _check(c: Control, out: Array, canvas: Vector2, min_px: int) -> void:
	var text := ""
	var px := 0
	var f: Font = null
	if c is Label:
		text = (c as Label).text
		px = c.get_theme_font_size("font_size")
		f = c.get_theme_font("font")
	elif c is Button:
		text = (c as Button).text
		px = c.get_theme_font_size("font_size")
		f = c.get_theme_font("font")
	elif c is RichTextLabel:
		var rt := c as RichTextLabel
		text = rt.get_parsed_text()
		px = rt.get_theme_font_size("normal_font_size")
		f = rt.get_theme_font("normal_font")
	elif c is LineEdit:
		text = (c as LineEdit).text
		px = c.get_theme_font_size("font_size")
		f = c.get_theme_font("font")
	else:
		return
	if text.strip_edges() == "":
		return
	var tag := String(c.get_meta("tiny", "")) != "" or c.has_meta("tiny")
	if px < min_px and not tag:
		out.append("small %dpx: %s '%s'" % [px, _name(c), text.substr(0, 24)])
	var r := Rect2(c.global_position, c.size)
	if c is Label:
		var l := c as Label
		var lh := f.get_height(px)
		var ls := float(l.get_theme_constant("line_spacing"))
		if l.autowrap_mode == TextServer.AUTOWRAP_OFF:
			var w := f.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
			if w > c.size.x + 1.5 and c.size.x > 0.0:
				out.append("wide (%d > %d): %s '%s'" % [w, c.size.x, _name(c), text.substr(0, 24)])
			if l.clip_text == false and float(l.get_line_count()) * lh + float(maxi(0, l.get_line_count() - 1)) * ls > c.size.y + 2.0 and c.size.y > 0.0:
				out.append("tall: %s '%s'" % [_name(c), text.substr(0, 24)])
		else:
			if float(l.get_line_count()) * lh + float(maxi(0, l.get_line_count() - 1)) * ls > c.size.y + 2.0:
				out.append("tall (%d lines x %d > %d): %s '%s'" % [l.get_line_count(), lh, c.size.y, _name(c), text.substr(0, 24)])
	elif c is Button:
		var w2 := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var icon_w := 0.0
		if (c as Button).icon != null:
			icon_w = float((c as Button).icon.get_width()) + 3.0
		if w2 + icon_w + 4.0 > c.size.x:
			out.append("button text wide (%d+%d > %d): %s '%s'" % [w2, icon_w, c.size.x, _name(c), text.substr(0, 24)])
		if f.get_height(px) > c.size.y:
			out.append("button text tall: %s '%s'" % [_name(c), text.substr(0, 24)])
	elif c is RichTextLabel:
		var rt2 := c as RichTextLabel
		if rt2.get_content_height() > c.size.y + 2.0:
			out.append("rich text tall (%d > %d): %s '%s'" % [rt2.get_content_height(), c.size.y, _name(c), text.substr(0, 24)])
	# on the canvas (scroll containers / off-screen slide-ins excluded by their own visibility)
	if r.size.x > 0.0 and r.size.y > 0.0:
		var vis := Rect2(Vector2.ZERO, canvas).grow(2.0)
		if not vis.encloses(r) and not c.has_meta("audit_offscreen_ok"):
			# only complain when the TEXT would be cut (a wide invisible container reaching past the edge is fine)
			out.append("off canvas %s: %s '%s'" % [str(r), _name(c), text.substr(0, 24)])
	var p := c.get_parent()
	if p is Panel and (p as Panel).size.x > 0.0 and c.position.x >= -1.0:
		if c.position.x + c.size.x > (p as Panel).size.x + 1.5 or c.position.y + c.size.y > (p as Panel).size.y + 1.5:
			out.append("outside its panel: %s '%s'" % [_name(c), text.substr(0, 24)])
