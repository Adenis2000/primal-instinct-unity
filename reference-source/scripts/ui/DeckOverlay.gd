class_name DeckOverlay
extends Control
## Modal list of the cards in your deck.

func _ready() -> void:
	UITheme.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	UITheme.full_rect(dim)
	add_child(dim)
	add_child(UITheme.panel(Rect2(20, 20, 600, 320)))
	var run: RunState = Game.run
	var counts := {}
	for id in run.deck:
		counts[id] = int(counts.get(id, 0)) + 1
	add_child(UITheme.label("Your deck (%d cards)" % run.deck.size(), 20, UITheme.C_GOLD).duplicate())
	get_child(get_child_count() - 1).position = Vector2(31, 25)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(31, 48)
	scroll.size = Vector2(579, 264)
	add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	scroll.add_child(grid)
	var ids := counts.keys()
	ids.sort_custom(func(a, b): return [int(DB.card(a)["tier"]), a] < [int(DB.card(b)["tier"]), b])
	for id in ids:
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(CardView.W + 3, CardView.H + 3)
		var cv := CardView.new().setup(id)
		cv.position = Vector2(2, 2)
		holder.add_child(cv)
		var cnt := UITheme.label("x%d" % counts[id], 20, UITheme.C_GOLD)
		cnt.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.06))
		cnt.add_theme_constant_override("outline_size", 2)
		cnt.position = Vector2(CardView.W - 22, 14)
		cnt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(cnt)
		grid.add_child(holder)
	var close := UITheme.button("Close", 20, Vector2(60, 18))
	close.position = Vector2(550, 318)
	close.size = Vector2(60, 18)
	close.pressed.connect(queue_free)
	add_child(close)
