extends SceneTree
## Renders a few cards (hand + big) with keyword highlighting to /tmp/cards.png. xvfb-run godot --script res://tests/cardshot.gd
func _initialize() -> void:
	await process_frame
	DB.load_all()
	var host := Control.new()
	host.theme = UITheme.build_theme()
	root.add_child(host)
	var ids := ["claw_slash", "hamstring", "circle_strike", "hunters_calm", "gore", "apex_ambush"]
	var x := 4.0
	for id in ids:
		var cv := CardView.new().setup(id)
		cv.position = Vector2(x, 4)
		host.add_child(cv)
		x += CardView.W + 4
	x = 4.0
	for id in ["claw_slash", "hamstring", "well_fed", "second_wind"]:
		var cv := CardView.new().setup(id, -1, true)
		cv.position = Vector2(x, 170)
		host.add_child(cv)
		x += CardView.BW + 6
	root.size = Vector2i(960, 460)
	await process_frame
	await process_frame
	await create_timer(0.3).timeout
	root.get_texture().get_image().save_png("/tmp/cards.png")
	for id in ["backstab", "hamstring", "circle_strike", "hunters_calm"]:
		var cv := CardView.new().setup(id)
		host.add_child(cv)
		await process_frame
		await process_frame
		print(id, " lines=", cv._text.get_line_count(), " content_h=", cv._text.get_content_height())
	quit()
