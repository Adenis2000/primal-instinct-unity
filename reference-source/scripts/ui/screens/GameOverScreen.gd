extends ScreenBase
## End of run (death or prototype victory). Everything resets: back to the egg (or the main menu).

func _ready() -> void:
	var r: RunState = Game.run
	var won := r.victory
	Game.end_run()
	add_bg("jungle" if won else "tundra", 0.88)
	add_centered("VICTORY!" if won else "YOU DIED", 40, 40, UITheme.C_GOLD if won else UITheme.C_RED)
	if won:
		add_centered("You survived the Frozen Verge and felled the Hollow Mammoth.", 86, 15, UITheme.C_TEXT)
		add_centered("(End of the prototype - more stages to come.)", 100, 15, UITheme.C_DIM)
	else:
		add_centered(r.cause if r.cause != "" else "Your story ends here.", 86, 15, UITheme.C_TEXT)
	var tr := TextureRect.new()
	tr.texture = SpriteFactory.get_texture(r.form_sprite_id())
	var tsz: Vector2 = tr.texture.get_size() * 3.0
	tr.size = tsz
	tr.position = Vector2(roundf(320.0 - tsz.x * 0.5), roundf(150.0 - tsz.y * 0.5))
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	if not won:
		tr.modulate = Color(0.5, 0.5, 0.55)
		tr.flip_v = true
	add_child(tr)
	var s := r.summary()
	var lines := [
		"%s %s  -  level %d" % [s["form"], r.species["name"], s["level"]],
		"Reached stage %d, %d rooms cleared, %d foes defeated" % [s["stage"], s["rooms"], s["kills"]],
		"Deck: %d cards   Ambushes: %d   Sneaked past: %d" % [s["deck"], r.stats["ambushes"], r.stats["sneaks"]],
		"Seed: %d  (type it on the egg screen to replay this dungeon)" % s["seed"],
	]
	var y := 214.0
	for l in lines:
		add_centered(String(l), y, 15, UITheme.C_TEXT)
		y += 16.0
	add_button("Return to the egg", Rect2(132, 296, 180, 28), func():
		Game.run = null
		Game.goto("egg"), 20).name = "gameover_egg"
	add_button("Main menu", Rect2(328, 296, 180, 28), func():
		Game.run = null
		Game.goto("menu"), 20).name = "gameover_menu"
