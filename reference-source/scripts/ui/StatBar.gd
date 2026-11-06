class_name StatBar
extends Control
## Simple pixel bar with icon and "value/max" text.

var value: float = 0.0
var max_value: float = 1.0
var fill_color: Color = UITheme.C_RED
var icon_id: String = ""
var text_override: String = ""
var flash_low: bool = false

func setup(icon_: String, color: Color, size_: Vector2) -> StatBar:
	icon_id = icon_
	fill_color = color
	custom_minimum_size = size_
	size = size_
	mouse_filter = Control.MOUSE_FILTER_PASS
	return self

func set_values(v: float, m: float, txt: String = "") -> void:
	value = v
	max_value = maxf(1.0, m)
	text_override = txt
	queue_redraw()

func _draw() -> void:
	var h := size.y
	var x0 := 0.0
	if icon_id != "":
		draw_texture(SpriteFactory.get_texture(icon_id), Vector2(0, floorf((h - 11) / 2.0)))
		x0 = 13.0
	var r := Rect2(x0, 2, size.x - x0, h - 4)
	draw_rect(r, Color("#0c1008"))
	var frac := clampf(value / max_value, 0.0, 1.0)
	var fr := Rect2(r.position + Vector2(1, 1), Vector2(roundf((r.size.x - 2) * frac), r.size.y - 2))
	draw_rect(fr, fill_color)
	draw_rect(Rect2(fr.position, Vector2(fr.size.x, 1)), fill_color.lightened(0.3))
	draw_rect(r, UITheme.C_BORDER, false, 1.0)
	var t := text_override if text_override != "" else "%d/%d" % [int(value), int(max_value)]
	UITheme.draw_text_in(self, r, t, UITheme.SZ_S)
