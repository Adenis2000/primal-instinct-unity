class_name ShotUtil
extends RefCounted
## Screenshots at real window sizes. The game renders on a 640x360 canvas (stretch mode "viewport"), so the viewport texture is always 640x360:
## this scales it up with nearest filtering by the window's integer scale (Pixel Perfect) and centres it on a black window-sized canvas, i.e.
## exactly what the player sees (letterbox / pillarbox bars included).

static func compose(img: Image, win: Vector2i, pixel_perfect: bool = true) -> Image:
	var mn: GDScript = load("res://scripts/ui/Main.gd")
	var r: Dictionary = mn.scale_for(Vector2(win), pixel_perfect)
	var sc := float(r["s"])
	var cw := int(round(img.get_width() * sc))
	var ch := int(round(img.get_height() * sc))
	var scaled := img.duplicate()
	scaled.convert(Image.FORMAT_RGBA8)
	scaled.resize(cw, ch, Image.INTERPOLATE_NEAREST)
	var out := Image.create(win.x, win.y, false, Image.FORMAT_RGBA8)
	out.fill(Color("#05080d"))
	out.blit_rect(scaled, Rect2i(0, 0, cw, ch), Vector2i((win.x - cw) / 2, (win.y - ch) / 2))
	return out

## Saves what the window shows (viewport texture composed on the window canvas). Returns the saved size.
static func save(vp: Viewport, path: String, win: Vector2i) -> Vector2i:
	var img := vp.get_texture().get_image()
	var out := compose(img, win, Settings.pixel_perfect)
	out.save_png(path)
	if OS.get_cmdline_user_args().has("--audit"):
		var issues := TextAudit.scan(vp.get_tree().root)
		print("AUDIT ", path.get_file().get_basename(), ": ", issues.size())
		for i in issues:
			print("AUDIT   ", i)
	return Vector2i(out.get_width(), out.get_height())
