class_name DietMeter
extends Control
## HUD indicator of the run's nutrition: five tiny meters (P F M Fb T) and the diet quality. Tooltip has the details.
## Preferred nutrients for the species' diet are drawn bright; toxins in purple.

func _ready() -> void:
	custom_minimum_size = Vector2(236, 16)
	size = Vector2(236, 16)
	mouse_filter = Control.MOUSE_FILTER_PASS

func refresh() -> void:
	var r: RunState = Game.run
	if r == null:
		return
	var nd: Dictionary = DB.nutrition()
	var lines: Array = ["Diet: %s - quality %s (rolling score %d)" % [r.diet()["name"], r.diet_quality(), r.diet_score()], String(r.diet()["desc"])]
	for k in nd["order"]:
		lines.append("%s: %d%s" % [nd["nutrients"][k]["name"], int(round(float(r.nutrition[k]))), "  (preferred)" if k in r.diet()["prefers"] else ""])
	lines.append("Growth bonus: +%d%% XP from every fight (Fair +10, Good +15, Excellent +25)" % int(round(r.xp_bonus() * 100.0)))
	lines.append("Quality is a rolling average of your last %d meals: only selective eating keeps it high. Junk (Fill up) and Harmful meals drag it down." % int(DB.nutrition()["rolling"]["window"]))
	lines.append("A good diet unlocks stronger evolution paths. A poor one only locks them - it never weakens you.")
	tooltip_text = "\n".join(lines)
	queue_redraw()

func _draw() -> void:
	var r: RunState = Game.run
	if r == null:
		return
	var nd: Dictionary = DB.nutrition()
	var cap := float(nd["meter_cap"])
	var x := 0.0
	for k in nd["order"]:
		var col := Color.html(String(nd["nutrients"][k]["color"]))
		var pref: bool = k in r.diet()["prefers"] or k == "toxin"
		if not pref:
			col = col.darkened(0.55)
		var short := String(nd["nutrients"][k]["short"])
		UITheme.draw_text_in(self, Rect2(x, 0, 20, 16), short, UITheme.SZ_S, Color(1, 1, 1, 0.98 if pref else 0.6), HORIZONTAL_ALIGNMENT_LEFT)
		var lw := UITheme.text_size(short, UITheme.SZ_S).x
		var bx := x + lw + 1.0
		draw_rect(Rect2(bx, 5, 14, 6), Color(0.02, 0.03, 0.06))
		draw_rect(Rect2(bx + 1, 6, roundf(12.0 * clampf(float(r.nutrition[k]) / cap * 2.0, 0.0, 1.0)), 4), col)
		draw_rect(Rect2(bx, 5, 14, 6), Color("#2a3e56"), false, 1.0)
		x = bx + 17.0
	var xb := int(round(r.xp_bonus() * 100.0))
	var q := r.diet_quality()
	UITheme.draw_text_in(self, Rect2(x + 1, 0, size.x - x - 1, 16), "%s%s" % [q, ("  +%d%% XP" % xb) if xb > 0 else ""], UITheme.SZ_S, Color("#a8e060") if xb > 0 else Color("#8fa4b8"), HORIZONTAL_ALIGNMENT_LEFT)
