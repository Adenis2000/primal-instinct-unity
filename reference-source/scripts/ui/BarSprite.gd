class_name BarSprite
extends Control
## HUD stat bar drawn from the designer sprites (assets/sprites/ui_bar_*.png, see README "Bar sprites"):
##   kind "full": ui_bar_frame (73x23: wing ornament, bar, number tab) - used for HEALTH. The number is rendered live in the tab.
##   kind "slim": ui_bar_slim (68x8, same frame without wing/tab) with an icon on the left and the number on the right - STAMINA / HUNGER.
## The fill is ui_bar_fill_<fill_id>.png (16x3, tiled) CLIPPED to the fill window of the frame, so it shrinks with the value.
## The shown value eases to the real one (smooth drain); damage leaves a pale "chip" that follows a moment later.

const FRAME_MARGIN := [39, 0, 33, 0]          # full frame: 9-slice (left, top, right, bottom); the 1px column at x=39 stretches
const FULL_FILL := Rect2(9, 7, 0, 3)          # fill window: x inset 9 from the left, y 7, height 3 (width = W - 9 - 5)
const FULL_FILL_RIGHT := 5
const FULL_TAB := Rect2(7, 11, 34, 12)        # number tab (the live number is centred on it; the 15 px digits overhang the plate, outline keeps them readable)
const SLIM_MARGIN := [34, 0, 33, 0]
const SLIM_FILL := Rect2(4, 2, 0, 3)
const SLIM_FILL_RIGHT := 5
const ICON := 11
const ROW_PAD := 3                            # slim rows are 16 px tall (15 px number text): the 8 px frame is centred in them
const TEXT_W := 38

var kind: String = "full"
var fill_id: String = "hp"                    # hp | stamina | hunger
var icon_id: String = ""
var value: float = 0.0                        # target
var max_value: float = 1.0
var text: String = ""
var tint: Color = Color.WHITE                 # modulate for the fill (hunger low / starving)
var disp: float = 0.0                         # eased value that is actually drawn
var trail: float = 0.0                        # pale damage chip
var _chip_wait: float = 0.0
var _first := true

func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(true)

## Set target values. `instant` (and the very first call) skips the easing.
func set_vals(v: float, m: float, txt: String, instant: bool = false) -> void:
	var old := value
	value = v
	max_value = maxf(1.0, m)
	text = txt
	if _first or instant:
		disp = v
		trail = v
		_first = false
	elif v < old:
		_chip_wait = 0.35
	elif v > old:
		trail = maxf(trail, v)
	queue_redraw()

## Jump straight to the target (tests / screenshots).
func settle() -> void:
	disp = value
	trail = value
	queue_redraw()

func is_settled() -> bool:
	return absf(disp - value) < 0.01 and absf(trail - value) < 0.01

func _process(dt: float) -> void:
	if is_settled():
		return
	disp = value if absf(disp - value) < 0.02 else lerpf(disp, value, minf(1.0, dt * 9.0))
	if trail > disp:
		if _chip_wait > 0.0:
			_chip_wait -= dt
		else:
			trail = maxf(disp, trail - dt * max_value * 0.5) if absf(trail - disp) > 0.02 else disp
	else:
		trail = disp
	queue_redraw()

func fill_rect_local() -> Rect2:
	if kind == "full":
		return Rect2(FULL_FILL.position, Vector2(size.x - FULL_FILL.position.x - FULL_FILL_RIGHT, FULL_FILL.size.y))
	var bx := float(ICON + 1)
	var bw := size.x - bx - TEXT_W
	return Rect2(Vector2(bx + SLIM_FILL.position.x, 1.0 + float(ROW_PAD) + SLIM_FILL.position.y), Vector2(bw - SLIM_FILL.position.x - SLIM_FILL_RIGHT, SLIM_FILL.size.y))

func _frame_box(name: String, m: Array) -> StyleBoxTexture:
	var tex := SpriteFactory.png(name)
	if tex == null:
		return null
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = m[0]
	sb.texture_margin_top = m[1]
	sb.texture_margin_right = m[2]
	sb.texture_margin_bottom = m[3]
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	return sb

func _draw() -> void:
	var fr := fill_rect_local()
	var frac := clampf(disp / maxf(1.0, max_value), 0.0, 1.0)
	var fw := roundf(fr.size.x * frac)
	if disp > 0.0 and frac > 0.0:
		fw = maxf(fw, 1.0)
	var ftex := SpriteFactory.png("ui_bar_fill_" + fill_id)
	var frame_name := "ui_bar_frame" if kind == "full" else "ui_bar_slim"
	var fb := _frame_box(frame_name, FRAME_MARGIN if kind == "full" else SLIM_MARGIN)
	# 1. dark backing of the window, 2. pale chip, 3. fill (clipped to the window), 4. frame on top
	draw_rect(fr, Color("#2a1e2c"))
	var cw := roundf(fr.size.x * clampf(trail / maxf(1.0, max_value), 0.0, 1.0))
	if cw > fw:
		draw_rect(Rect2(fr.position.x + fw, fr.position.y, cw - fw, fr.size.y), Color("#f0e0c8"))
	if fw > 0.0:
		var r := Rect2(fr.position, Vector2(fw, fr.size.y))
		if ftex != null:
			draw_texture_rect(ftex, r, true, tint)
		else:
			draw_rect(r, Color("#d04050") * tint)
		if fw > 3.0:
			draw_rect(Rect2(r.end.x - 1.0, r.position.y, 1.0, r.size.y), Color(1, 1, 1, 0.35))
	if kind == "full":
		if fb != null:
			fb.draw(get_canvas_item(), Rect2(0, 0, size.x, 23))
		UITheme.draw_text_in(self, FULL_TAB, text, UITheme.SZ_S, Color("#f6ead0"), HORIZONTAL_ALIGNMENT_CENTER, true)
	else:
		if icon_id != "":
			var it := SpriteFactory.get_texture(icon_id)
			if it != null:
				draw_texture(it, Vector2(0, float(ROW_PAD)))
		if fb != null:
			fb.draw(get_canvas_item(), Rect2(ICON + 1, 1 + ROW_PAD, size.x - ICON - 1 - TEXT_W, 8))
		UITheme.draw_text_in(self, Rect2(size.x - TEXT_W + 3, 0, TEXT_W - 3, size.y), text, UITheme.SZ_S, Color("#f6ead0"), HORIZONTAL_ALIGNMENT_LEFT, true)
