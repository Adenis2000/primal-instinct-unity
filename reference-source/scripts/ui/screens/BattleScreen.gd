extends ScreenBase
## Battle UI: replays Battle events with animations and turns clicks into Battle actions.
## Controls: click a card then a highlighted target; "Move" button (or M) toggles move mode - in move mode a click on a
## highlighted tile walks there; otherwise a click on a tile just TURNS you to face it (free, unlimited). Facing persists.

var battle: Battle
var room: Dictionary
var board: BattleBoard
var bhud: BattleHud
var hand_root: Control
var order_root: Control
var info_label: Label
var info_panel: Control
var log_label: Label
var mp_label: Label
var move_btn: Button
var end_btn: Button
var banner: Label
var selected: int = -1
var move_mode: bool = false
var busy: bool = true
var log_lines: Array = []
var hover_tile: Vector2i = Vector2i(-1, -1)
var speed: float = 1.0
var _ending: bool = false
var seen_types: Dictionary = {}     # event types replayed so far (tests/diagnostics)
var order_panel: Control
var log_panel: Control
var explore_panel: Control
var explore_label: Label
var _off: Vector2 = Vector2(-1, -1)      # margin between the frame and the screen edge (always zero on the fixed 640x360 canvas)
var _anchored: Array = []

func _anch(n: Control, mode: String) -> Control:
	_anchored.append(n)
	return UITheme.anchor(n, mode, Vector2.ZERO if _off.x < 0.0 else _off)

func _process(_dt: float) -> void:
	var o := global_position.round()
	if o != _off:
		_off = o
		for n in _anchored:
			if is_instance_valid(n):
				UITheme.reanchor(n, _off)
		if bhud != null:
			bhud.anchor_to(_off)
		if battle != null and is_instance_valid(hand_root):
			hand_root.position = Vector2(0, _off.y)
			if _built_hand_off != _off:
				_rebuild_hand()

func _ready() -> void:
	battle = Game.battle
	room = args.get("room", {})
	var r: RunState = Game.run
	var theme_id := battle.theme_id if battle != null and battle.theme_id != "" else String(r.stage.get("theme", "jungle"))
	var bg := ColorRect.new()
	bg.color = SpriteFactory.theme_bg(theme_id)
	UITheme.full_rect(bg)
	add_child(bg)
	board = BattleBoard.new()
	board.setup(battle, theme_id)
	board.tile_clicked.connect(_on_tile_clicked)
	board.tile_hovered.connect(_on_tile_hovered)
	add_child(board)
	bhud = BattleHud.new()
	bhud.battle = battle
	hud = bhud
	bhud.item_use_cb = _use_item
	add_child(bhud)
	banner = UITheme.label("", 20, UITheme.C_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	banner.position = Vector2(180, 24)
	banner.size = Vector2(280, 20)
	banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner.add_theme_color_override("font_outline_color", Color.BLACK)
	banner.add_theme_constant_override("outline_size", 2)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(banner)
	_anch(banner, "T")
	# turn order (top)
	order_panel = Control.new()          # invisible layout box: the unit icons sit straight on the board (no backing square)
	order_panel.position = Vector2(2, 2)
	order_panel.size = Vector2(204, 29)
	order_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(order_panel)
	_anch(order_panel, "LT")
	order_root = Control.new()
	order_root.position = Vector2(4, 3)
	add_child(order_root)
	_anch(order_root, "LT")
	# hover info (right)
	info_panel = UITheme.panel(Rect2(438, 100, 199, 58), Color(0, 0, 0, 0.9), UITheme.C_BORDER, "ui_panel_dim")
	add_child(info_panel)
	_anch(info_panel, "RT")
	info_label = add_label("", Vector2(443, 103), 15, UITheme.C_TEXT, 190)
	_anch(info_label, "RT")
	# log (bottom-left)
	log_panel = UITheme.panel(Rect2(2, 246, 112, 112), Color(0, 0, 0, 0.88), UITheme.C_BORDER, "ui_panel_dim")
	add_child(log_panel)
	_anch(log_panel, "LB")
	log_label = add_label("", Vector2(6, 249), 15, Color("#b4c4d4"), 104)
	_anch(log_label, "LB")
	# hand (bottom center)
	hand_root = Control.new()
	add_child(hand_root)
	# move panel (bottom-right)
	# (no backing panel: the stone-wood buttons sit straight over the board, labels get a shadow)
	move_btn = Button.new()
	move_btn.position = Vector2(540, 258)
	move_btn.size = Vector2(96, 22)
	move_btn.focus_mode = Control.FOCUS_NONE
	move_btn.text = "Move"
	move_btn.icon = SpriteFactory.get_texture("icon_move")
	UITheme.apply(move_btn, 15)
	move_btn.pressed.connect(_toggle_move)
	add_child(move_btn)
	_anch(move_btn, "RB")
	var foot := TextureRect.new()
	foot.texture = SpriteFactory.get_texture("icon_foot")
	foot.position = Vector2(541, 308)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(foot)
	_anch(foot, "RB")
	mp_label = add_label("", Vector2(556, 306), 15, UITheme.C_TEXT)
	UITheme.shadow(mp_label)
	_anch(mp_label, "RB")
	end_btn = add_button("END TURN", Rect2(540, 282, 96, 22), _on_end_pressed, 15)
	_anch(end_btn, "RB")
	var turn_hint := add_label("Click tile = turn", Vector2(540, 326), 15, Color("#c9bfa8"), 98, HORIZONTAL_ALIGNMENT_CENTER)
	UITheme.shadow(turn_hint)
	_anch(turn_hint, "RB")
	Hints.place(Rect2(130, 76, 300, 60))
	if battle.phase == "explore":
		_build_explore_ui()
	_start()

## EXPLORE (room cleared): the same battlefield, no enemies; exits are gates on its edges.
func _build_explore_ui() -> void:
	order_panel.hide()
	order_root.hide()
	log_panel.hide()
	log_label.hide()
	end_btn.hide()
	explore_panel = UITheme.panel(Rect2(70, 296, 500, 62), Color(0.03, 0.05, 0.1, 0.94), UITheme.C_BORDER, "ui_panel_dim")
	add_child(explore_panel)
	_anch(explore_panel, "B")
	_anch(add_label("CHOOSE YOUR PATH", Vector2(78, 299), 20, UITheme.C_GOLD), "B")
	explore_label = add_label("Click a path (a gap in the trees) or walk to the edge next to it. Each path shows its reward; the room beyond is a surprise. Entering a room costs hunger.", Vector2(78, 316), 15, UITheme.C_TEXT, 484)
	_anch(explore_label, "B")

func _start() -> void:
	await _play(battle.drain_events())
	if battle.phase == "explore" and board.gate_state == "locked":
		# the area is clear (or sneaked past): the paths open (corridor trees fade out)
		await _w(0.35)
		board.open_gates()
		await _w(board.GATE_OPEN_TIME + 0.15)
	if battle.phase == "explore" and board.secret_state == "sealed":
		# the area is clear: a rock rolls away from the hidden opening and it starts to glow
		await _w(0.45)
		board.open_secret()
		await _w(board.SECRET_OPEN_TIME + 0.1)
	busy = false
	_refresh_all()
	_check_end()
	_start_hints()

func _start_hints() -> void:
	if battle.phase == "ambush" and battle.exits_visible():
		Hints.show_hint("locked_exits")
	if battle.phase == "explore":
		Hints.show_hint("exits")
		Hints.show_hint("movement")
		if battle.secret != Vector2i(-1, -1):
			Hints.show_hint("secret")
		return
	Hints.show_hint("movement")
	Hints.show_hint("facing")
	if battle.grid.count_tiles("grass") > 0:
		Hints.show_hint("evasion")
	Hints.show_hint("stamina")
	Hints.show_hint("keywords")
	Hints.show_hint("intent")
	Hints.show_hint("turn_order")
	if battle.started_unspotted:
		Hints.show_hint("stealth")
	if battle.phase == "player" and battle.grid.is_grass(battle.player.pos) and not battle.is_hidden():
		Hints.show_hint("hide")

# ------------------------------------------------------------------ input

func _unhandled_key_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed:
		return
	if Game.main != null and Game.main.settings_open():
		return
	if e.keycode == KEY_ESCAPE:
		# Esc first cancels a selected card / move mode; with nothing to cancel it falls through to Main (opens Settings)
		if selected >= 0 or move_mode:
			selected = -1
			move_mode = false
			if not busy:
				_refresh_all()
			get_viewport().set_input_as_handled()
		return
	if busy:
		return
	if e.keycode == KEY_M:
		_toggle_move()
	elif e.keycode == KEY_SPACE or e.keycode == KEY_E:
		_on_end_pressed()
	elif e.keycode >= KEY_1 and e.keycode <= KEY_9:
		var i: int = e.keycode - KEY_1
		if battle.phase == "player" and i < battle.hand.size():
			_select_card(i)

func _toggle_move() -> void:
	if busy or (battle.phase != "player" and battle.phase != "explore" and battle.phase != "ambush"):
		return
	if not move_mode and not _can_move():
		_popup_player("No moves left", Color("#c8c8c8"))
		return
	move_mode = not move_mode
	selected = -1
	_refresh_all()

## True while the player still has move points AND somewhere to go (costs per tile / blockers considered).
func _can_move() -> bool:
	if (battle.phase != "player" and battle.phase != "explore" and battle.phase != "ambush") or battle.mp <= 0:
		return false
	for p in battle.reachable_tiles():
		if p != battle.player.pos:
			return true
	return false

func _use_item(id: String) -> void:
	if busy or not battle.item_usable(id):
		return
	await _do(func(): battle.use_item(id))

func _on_end_pressed() -> void:
	if busy:
		return
	if battle.phase == "ambush":
		selected = -1
		await _do(func(): battle.skip_ambush())
	elif battle.phase == "player":
		selected = -1
		move_mode = false
		await _do(func(): battle.end_player_turn())

func _on_card_clicked(view: CardView) -> void:
	if busy or battle.phase != "player":
		return
	_select_card(view.index)

func _select_card(i: int) -> void:
	if not battle.card_playable(i):
		var why := battle.unplayable_reason(i)
		_popup_player(why if why != "" else "Can't play that", Color("#a0a0a0"))
		return
	var c := battle.card_at(i)
	var t := String(c["target"])
	move_mode = false
	if t == "self" or t == "all_enemies" or t == "none":
		selected = -1
		await _do(func(): battle.play_card(i))
		return
	selected = -1 if selected == i else i
	_refresh_all()

func _on_tile_hovered(p: Vector2i) -> void:
	hover_tile = p
	_update_info()
	_update_overlays()

func _on_tile_clicked(p: Vector2i, button: int) -> void:
	if busy:
		return
	if button == MOUSE_BUTTON_RIGHT:
		selected = -1
		move_mode = false
		_refresh_all()
		return
	if button != MOUSE_BUTTON_LEFT:
		return
	if battle.phase == "explore":
		await _explore_click(p)
		return
	if battle.phase == "ambush":
		for e in battle.ambush_targets():
			if e.pos == p:
				await _do(func(): battle.ambush_strike(e))
				return
		# unseen: Move closer (or out through an exit = sneak past), or turn on the spot (free)
		if battle.exit_at(p) >= 0 and battle.reachable_tiles().has(p):
			if battle.move_player(p):
				await _do(func(): pass)
				if battle.phase == "ambush" and battle.exit_at(battle.player.pos) >= 0:
					_sneak_out()
			return
		if move_mode:
			if battle.move_player(p):
				await _do(func(): pass)
				if battle.phase == "ambush" and battle.exit_at(battle.player.pos) >= 0:
					_sneak_out()
			return
		await _do(func(): battle.face_player_toward(p))
		return
	if battle.phase != "player":
		return
	if selected >= 0:
		var c := battle.card_at(selected)
		var t := String(c["target"])
		var idx := selected
		if t == "enemy":
			for e in battle.card_targets(idx):
				if e.pos == p:
					selected = -1
					await _do(func(): battle.play_card(idx, e))
					return
		elif t == "tile":
			if battle.card_targets(idx).has(p):
				selected = -1
				await _do(func(): battle.play_card(idx, p))
				return
		selected = -1
		_refresh_all()
		return
	if move_mode:
		if battle.move_player(p):
			await _do(func(): pass)
		return
	# normal mode: a click only turns you to face that tile (free)
	await _do(func(): battle.face_player_toward(p))

## Explore: clicking a gate (or the glowing cave mouth) takes it; otherwise Move mode walks (and stepping onto a gate takes it).
func _explore_click(p: Vector2i) -> void:
	var xi := battle.exit_at(p)
	if xi >= 0:
		_take_exit(xi)
		return
	if _secret_usable() and p == battle.secret:
		_take_secret()
		return
	if move_mode:
		if battle.move_player(p):
			await _do(func(): pass)
			var here := battle.exit_at(battle.player.pos)
			if here >= 0:
				_take_exit(here)
			elif _secret_usable() and battle.player.pos == battle.secret:
				_take_secret()
		return
	await _do(func(): battle.face_player_toward(p))

func _secret_usable() -> bool:
	return battle.secret != Vector2i(-1, -1) and board.secret_state == "open"

func _take_exit(i: int) -> void:
	busy = true
	move_mode = false
	board.move_tiles = {}
	explore_label.text = "Entering..."
	await Game.take_exit(i)

## Reached an exit while nobody noticed you: slip away (no fight, no spoils).
func _sneak_out() -> void:
	busy = true
	move_mode = false
	board.move_tiles = {}
	banner.text = "You slip away unseen..."
	await Game.sneak_out()

func _take_secret() -> void:
	busy = true
	move_mode = false
	board.move_tiles = {}
	explore_label.text = "You squeeze into the cave..."
	await Game.take_secret()

## Run a battle action, then play back the events it produced.
func _do(action: Callable) -> void:
	busy = true
	action.call()
	var evs := battle.drain_events()
	await _play(evs)
	busy = false
	_refresh_all()
	_check_end()

func _check_end() -> void:
	if _ending:
		return
	if battle.phase == "won":
		_ending = true
		var res := battle.result()
		battle.commit_to_run()
		Game.battle_result = res
		await wait(0.7 / speed)
		Game.goto("reward", {"room": room})
	elif battle.phase == "lost":
		_ending = true
		battle.commit_to_run()
		Game.run.cause = "Slain by %s." % _killer_name()
		await wait(1.2 / speed)
		Game.goto("gameover")

func _killer_name() -> String:
	return String(battle.current.display_name) if battle.current != null and not battle.current.is_player else "your wounds"

# ------------------------------------------------------------------ refresh

func _refresh_all() -> void:
	if not is_inside_tree():
		return
	# move mode ends by itself once there is nothing left to walk to (Moves Left 0 / no affordable tile)
	if move_mode and not busy and not _can_move():
		move_mode = false
		if battle.phase == "player" or battle.phase == "explore" or battle.phase == "ambush":
			_popup_player("Out of moves", Color("#c8c8c8"))
	_rebuild_hand()
	var in_player := battle.phase == "player" or battle.phase == "explore" or battle.phase == "ambush"
	mp_label.text = "Moves: %d/%d" % [battle.mp, battle.mp_max] if in_player else "Moves: -"
	move_btn.disabled = busy or not in_player
	move_btn.text = "Move  (on)" if move_mode else "Move"
	UITheme.set_selected(move_btn, move_mode)
	match battle.phase:
		"ambush":
			end_btn.text = "SKIP AMBUSH"
			banner.text = "UNSEEN! Click a marked enemy for a free strike, Move closer, or slip out an exit."
		"player":
			end_btn.text = "END TURN"
			banner.text = ""
		_:
			end_btn.text = "..."
			banner.text = ""
	end_btn.disabled = busy or not (battle.phase == "player" or battle.phase == "ambush")
	board.current_uid = battle.current.uid if battle.current != null else -1
	board.show_move = move_mode and in_player
	hud.hp_override = battle.player.vis_hp
	hud.refresh()
	_update_order()
	_update_overlays()
	_update_info()
	_flush_log()

var _built_hand_off: Vector2 = Vector2(-6, -6)

func _rebuild_hand() -> void:
	if zoom != null and is_instance_valid(zoom):
		zoom.queue_free()
		zoom = null
	for c in hand_root.get_children():
		c.queue_free()
	var n := battle.hand.size()
	var step := float(CardView.W) + 2.0
	_built_hand_off = _off
	var ox := maxf(0.0, _off.x)
	var avail := 412.0 - float(CardView.W) + 2.0 * ox
	if n > 1:
		step = minf(step, avail / float(n - 1))
	var total := step * (n - 1) + CardView.W if n > 0 else 0.0
	var x0 := 116.0 - ox + maxf(0.0, (avail + CardView.W - total) / 2.0)
	for i in n:
		var cv := CardView.new().setup(String(battle.hand[i]), i)
		cv.position = Vector2(roundf(x0 + i * step), 360 - CardView.H - (5 if i == selected else 0))   # hand_root itself is shifted to the real bottom edge
		cv.set_state(battle.phase == "player" and battle.card_playable(i), i == selected)
		cv.clicked.connect(_on_card_clicked)
		cv.hovered.connect(_on_card_hover)
		hand_root.add_child(cv)

var zoom: CardView = null

## Hovering a hand card shows a big, fully readable copy above it (text 15 px, 2x art), with the reason if it can't be played.
func _on_card_hover(view: CardView, on: bool) -> void:
	if zoom != null and is_instance_valid(zoom):
		zoom.queue_free()
		zoom = null
	if not is_instance_valid(view):
		return
	if on:
		var why := battle.unplayable_reason(view.index) if battle.phase == "player" else ""
		zoom = CardView.new().setup(view.card_id, -1, true, why)
		zoom.mouse_filter = Control.MOUSE_FILTER_IGNORE
		zoom.z_index = 30
		zoom.set_state(why == "", false)
		var ofs := Vector2(maxf(0.0, _off.x), maxf(0.0, _off.y))
		zoom.position = Vector2(roundf(clampf(view.position.x + CardView.W / 2.0 - zoom.w / 2.0, 2.0 - ofs.x, 638.0 + ofs.x - zoom.w)), roundf(360.0 + ofs.y - CardView.H - 3.0 - zoom.h))
		add_child(zoom)
		var kp := Keywords.side_panel(String(DB.card(view.card_id)["text"]))
		if kp != null:
			zoom.add_child(kp)
			kp.position = Vector2(zoom.w + 3, 0) if zoom.position.x + zoom.w + 4 + 120 < 638.0 + maxf(0.0, _off.x) else Vector2(-112, 0)
		view.z_index = 5
	else:
		view.z_index = 0

func _update_order() -> void:
	for c in order_root.get_children():
		c.queue_free()
	var seq: Array = []
	if battle.current != null and battle.current.alive and battle.phase == "player":
		seq.append(battle.current)
	seq.append_array(battle.preview_order(7 if seq.is_empty() else 6))
	var x := 0
	for i in seq.size():
		var u: BUnit = seq[i]
		var holder := Control.new()
		holder.position = Vector2(x, 0)
		holder.size = Vector2(26, 26)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		order_root.add_child(holder)
		# the unit's own sprite (outline carries it over the board): no backing square, no shadow; a thin team-colour line sits under it
		var ic := TextureRect.new()
		ic.texture = SpriteFactory.png("portrait_" + String(Game.run.form()["id"])) if u.is_player and Game.run != null and SpriteFactory.png("portrait_" + String(Game.run.form()["id"])) != null else SpriteFactory.creature(u.sprite_id, false, u.infected and not u.is_player and not bool(u.def.get("infected", false)))
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.position = Vector2(0, 0)
		ic.custom_minimum_size = Vector2(26, 23)
		ic.size = Vector2(26, 23)
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(ic)
		var team := ColorRect.new()
		team.color = Color("#5ad0c0") if u.is_player else (Color("#a060e0") if u.infected else Color("#e05058"))
		team.position = Vector2(1, 23)
		team.size = Vector2(24, 2)
		team.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(team)
		if i == 0 and battle.phase == "player":
			var fr := ColorRect.new()          # the unit whose turn it is: a gold marker over the team line
			fr.name = "now_marker"
			fr.color = UITheme.C_GOLD
			fr.position = Vector2(0, 22)
			fr.size = Vector2(26, 4)
			fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			holder.add_child(fr)
		x += 29

func _update_overlays() -> void:
	board.move_tiles = {}
	board.target_tiles = {}
	board.detect_tiles = {}
	board.preview = {}
	if busy:
		return
	if battle.phase == "ambush":
		for e in battle.ambush_targets():
			board.target_tiles[e.pos] = Color(1.0, 0.3, 0.3)
			var pv := battle.preview_ambush(e)
			board.preview[e.pos] = {"dir": pv["dir"], "mult": pv["mult"]}
	if battle.phase == "player" or battle.phase == "explore" or battle.phase == "ambush":
		if battle.phase != "ambush" and selected >= 0 and selected < battle.hand.size():
			for t in battle.card_targets(selected):
				if t is BUnit:
					board.target_tiles[t.pos] = Color(1.0, 0.3, 0.3)
					var pv := battle.preview_attack(selected, t)
					board.preview[t.pos] = {"dir": pv["dir"], "mult": pv["mult"]}
				else:
					board.target_tiles[t] = Color(0.4, 1.0, 0.4)
		elif move_mode:
			var rt := battle.reachable_tiles()
			for p in rt:
				if p != battle.player.pos:
					board.move_tiles[p] = rt[p]
	# vision cone of a hovered unaware enemy (takes its facing into account)
	var u := _unit_at(hover_tile)
	if u != null and not u.is_player and u.alive and not u.aware:
		for y in battle.grid.h:
			for x in battle.grid.w:
				var p := Vector2i(x, y)
				if battle.grid.blocks_move(p):
					continue
				if battle.can_detect_at(u, p):
					board.detect_tiles[p] = true
	# hovering an enemy with no card selected: show where you'd stand relative to it
	if u != null and not u.is_player and u.alive and selected < 0 and battle.phase == "player":
		var pv2 := {"dir": battle.facing_dir(battle.player.pos, u), "mult": battle.facing_mult(battle.player.pos, u)}
		board.preview[u.pos] = pv2

func _unit_at(p: Vector2i) -> BUnit:
	if p.x < 0:
		return null
	for u in battle.units:
		if u.alive and u.pos == p:
			return u
	return null

func _dir_name(f: Vector2i) -> String:
	match f:
		Vector2i(1, 0):
			return "SE"
		Vector2i(0, 1):
			return "SW"
		Vector2i(-1, 0):
			return "NW"
	return "NE"

func _update_info() -> void:
	if battle.phase == "ambush" and hover_tile.x >= 0 and battle.exits_visible():
		var ax := battle.exit_at(hover_tile)
		if ax >= 0:
			info_label.text = "PATH OUT (%s edge)\nNobody has noticed you: walk onto this edge tile to slip away unseen (no fight, no spoils)." % String(battle.exits[ax]["side"])
			_fit_info()
			return
	if battle.phase == "explore" and hover_tile.x >= 0:
		var xi := battle.exit_at(hover_tile)
		if xi >= 0:
			var h := RoomInfo.reward_hint(String(battle.exits[xi]["type"]))
			info_label.text = "PATH (%s side%s)\nReward: %s\nWhat waits beyond is a surprise. Click the path, or walk onto this edge tile." % [String(battle.exits[xi]["side"]), ", forward" if int(battle.exits[xi]["door"]) == 0 else "", h["label"]]
			_fit_info()
			return
		if _secret_usable() and hover_tile == battle.secret:
			info_label.text = "SECRET CAVE\nA spider den: harder than a normal room, but rarer cards, extra food and an item. Costs hunger like any room. Optional."
			return
	var u := _unit_at(hover_tile)
	if u == null:
		u = battle.player
	var lines: Array = []
	var nm := u.display_name
	lines.append("%s%s" % [nm, "  (INFECTED)" if u.infected else ""])
	lines.append("HP %d/%d  Spd %.1f  Mv %d  Faces %s" % [u.hp, u.max_hp, battle.eff_speed(u), u.move, _dir_name(u.facing)])
	if not u.is_player:
		match u.state:
			"spotted":
				lines.append("Status: ALERT - hunting you")
			"searching":
				lines.append("Status: SEARCHING (%s) - checking where it last saw you" % ("walking there" if u.search_phase == "go" else "looking around, %d turn(s) left" % u.scan_left))
			_:
				lines.append("Status: idle, roaming (sees %d ahead)" % battle.detect_range(u))
		var ft := u.facing_trait()
		if not ft.is_empty():
			lines.append("Front x%s  Side x%s  Back x%s%s" % [str(ft.get("front", 1.0)), str(ft.get("side", 1.0)), str(ft.get("back", 1.0)), "  (slow turner)" if u.slow_turn() else ""])
		var ab := u.next_ability()
		if not ab.is_empty():
			var dmg := ""
			if ab.has("damage"):
				dmg = " dmg %d" % int(round((int(ab["damage"]) + u.bonus_damage) * float(battle.wm(u)["damage_mult"])))
			lines.append("Next: %s%s" % [ab["name"], dmg])
	var wl := WeatherSys.describe_for(battle.weather_id, u.tags)
	if not wl.is_empty():
		lines.append("Weather: " + ", ".join(wl))
	if hover_tile.x >= 0 and battle.grid.in_bounds(hover_tile):
		var td := battle.grid.tdef(hover_tile)
		var mc := battle.grid.move_cost(hover_tile, battle.player.terrain_costs)
		var evn := int(round(battle.grid.evasion(hover_tile) * 100.0))
		lines.append("Tile: %s%s%s" % [td["name"], "  (move cost %d)" % mc if not battle.grid.blocks_move(hover_tile) else "  (blocked)", ("  %d%% evasion" % evn) if evn > 0 else ""])
	info_label.text = "\n".join(lines)
	_fit_info()

func _fit_info() -> void:
	var fh := UITheme.font_for(UITheme.SZ_S).get_height(UITheme.snap(UITheme.SZ_S))
	var th := UITheme.font_for(UITheme.SZ_S).get_multiline_string_size(info_label.text, HORIZONTAL_ALIGNMENT_LEFT, 190, UITheme.snap(UITheme.SZ_S)).y
	th += (th / fh)    # theme line_spacing 1 px per line
	info_panel.size.y = maxf(36.0, th + 11.0)

func _flush_log() -> void:
	var f := UITheme.font_for(UITheme.SZ_S)
	var px := UITheme.snap(UITheme.SZ_S)
	var keep: Array = []
	for i in range(log_lines.size() - 1, -1, -1):        # newest lines that fit the panel (6 lines of 15 px), never a clipped line
		var cand: Array = [log_lines[i]] + keep
		if f.get_multiline_string_size("\n".join(cand), HORIZONTAL_ALIGNMENT_LEFT, 104, px).y > 96.0:
			break
		keep = cand
	log_label.text = "\n".join(keep)
	log_label.size = Vector2(104, 96)

# ------------------------------------------------------------------ event playback

func _w(t: float) -> void:
	if t > 0.0:
		await get_tree().create_timer(t / speed).timeout

func _play(evs: Array) -> void:
	for e in evs:
		await _handle(e)
	for u in battle.units:
		u.vis_pos = Vector2(u.pos)
		u.vis_hp = u.hp
		u.vis_dead = not u.alive
		u.vis_alpha = 1.0 if u.alive else 0.0
		u.vis_aware = u.aware
		u.vis_infected = u.infected
		u.vis_facing = u.facing
		u.vis_state = u.state
		u.vis_off = Vector2.ZERO
		u.vis_lift = 0.0
		u.vis_squash = 0.0 if u.alive else u.vis_squash
	_flush_log()

func _handle(e: Dictionary) -> void:
	var u: BUnit = battle.unit_by_uid(int(e.get("unit", -1)))
	seen_types[String(e["t"])] = int(seen_types.get(String(e["t"]), 0)) + 1
	match String(e["t"]):
		"log":
			log_lines.append(String(e["text"]))
			_flush_log()
		"turn":
			board.current_uid = int(e["unit"])
			if u != null and not u.is_player:
				await _w(0.1)
		"move":
			var path: Array = e["path"]
			var step := minf(0.12, 0.7 / maxf(1.0, path.size()))
			var prevp := Vector2i(u.vis_pos.round())
			for p in path:
				u.vis_facing = Battle.dir_toward(prevp, p, u.vis_facing)
				prevp = p
				await _hop_to(u, Vector2(p), step / speed, 2.0)
				board.add_fx("dust", BattleBoard.unit_foot(u.vis_pos), Color(0.85, 0.85, 0.8) if board.theme_id == "tundra" else Color(0.7, 0.62, 0.45), 0.3, {"seed": u.uid * 3 + p.x})
		"face":
			if u != null:
				u.vis_facing = e["dir"]
		"leap":
			u.vis_facing = Battle.dir_toward(Vector2i(u.vis_pos.round()), e["to"], u.vis_facing)
			var pounce := String(e.get("style", "leap")) == "pounce"
			var dist := u.vis_pos.distance_to(Vector2(e["to"]))
			board.add_fx("dust", BattleBoard.unit_foot(u.vis_pos), Color(0.75, 0.7, 0.55), 0.3, {"seed": 1})
			var dur := (0.16 if pounce else 0.22) / speed
			var tw := create_tween().set_parallel(true)
			tw.tween_property(u, "vis_pos", Vector2(e["to"]), dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT if pounce else Tween.EASE_IN_OUT)
			tw.tween_method(func(v: float): u.vis_lift = sin(v * PI) * (6.0 + dist * 1.3), 0.0, 1.0, dur)
			await tw.finished
			u.vis_pos = Vector2(e["to"])
			u.vis_lift = 0.0
			board.add_fx("dust", BattleBoard.unit_foot(u.vis_pos), Color(0.75, 0.7, 0.55), 0.35, {"seed": 4})
			if pounce:
				board.add_fx("shock", BattleBoard.unit_foot(u.vis_pos), Color(1.0, 0.9, 0.6), 0.35)
				board.shake = maxf(board.shake, 0.35)
				await _w(0.05)
		"windup":
			if u != null:
				u.vis_windup = e["tiles"]
				board.add_fx("ring", BattleBoard.unit_foot(u.vis_pos), Color("#ff6040"), 0.5)
				board.shake = maxf(board.shake, 0.15)
				Hints.show_hint("telegraph")
				await _w(0.25)
		"windup_end":
			if u != null:
				u.vis_windup = []
		"phase":
			if u != null:
				board.add_fx("shock", BattleBoard.unit_foot(u.vis_pos), Color(1.0, 0.3, 0.2), 0.6)
				board.shake = maxf(board.shake, 0.6)
				await _w(0.35)
		"dodge":
			if u != null:
				_popup(u, "Dodge", Color("#9ae8ff"))
				var away := Vector2(-2, -1) if u.vis_pos.x <= 4 else Vector2(2, -1)
				var dtw := create_tween()
				dtw.tween_property(u, "vis_off", away, 0.07 / speed)
				dtw.tween_property(u, "vis_off", Vector2.ZERO, 0.12 / speed)
				await dtw.finished
		"attack":
			var t: BUnit = battle.unit_by_uid(int(e["target"]))
			if bool(e.get("ranged", false)):
				await _recoil(u, t)
			else:
				await _lunge(u, t)
		"projectile":
			var t: BUnit = battle.unit_by_uid(int(e["target"]))
			await _projectile(u, t, String(e.get("kind", "spit")))
		"give_up":
			if u != null:
				u.vis_state = "idle"
				await _w(0.1)
		"card_played":
			await _card_feedback(String(e.get("id", "")), int(e.get("i", -1)))
		"hit":
			var src: BUnit = battle.unit_by_uid(int(e.get("src", -1)))
			if src != null and src.is_player and u != null and src != u:
				await _lunge(src, u)
			await _apply_hit(u, e)
		"damage":
			await _apply_hit(u, e)
		"heal":
			u.vis_hp = int(e["hp_after"])
			board.add_fx("ring", BattleBoard.unit_foot(u.vis_pos), Color("#6fe06f"), 0.45)
			_popup(u, "+%d" % int(e["amount"]), UITheme.C_GREEN)
			hud.hp_override = battle.player.vis_hp
			hud.refresh()
			await _w(0.12)
		"block":
			board.add_fx("ring", BattleBoard.unit_foot(u.vis_pos), Color("#6fb4ff"), 0.4)
			_popup(u, "+%d block" % int(e["amount"]), UITheme.C_BLUE)
			await _w(0.1)
		"popup":
			if u != null:
				_popup(u, String(e["text"]), Color(String(e.get("color", "#ffffff"))))
				await _w(0.12)
		"spot":
			if u != null:
				u.vis_aware = true
				u.vis_state = "spotted"
				u.vis_alert = 3.5
				Hints.show_hint("stealth")
				await _w(0.15)
		"lose_track":
			if u != null:
				u.vis_aware = false
				u.vis_state = "searching"
				Hints.show_hint("search")
				_popup(u, "?", Color("#ffe060"))
				await _w(0.1)
		"death":
			if u != null:
				board.add_fx("puff", BattleBoard.unit_foot(u.vis_pos) + Vector2(0, -2), Color(0.8, 0.8, 0.75), 0.45)
				var tw := create_tween().set_parallel(true)
				tw.tween_property(u, "vis_squash", 1.0, 0.32 / speed).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
				tw.tween_property(u, "vis_alpha", 0.0, 0.3 / speed).set_delay(0.12 / speed)
				await tw.finished
				u.vis_dead = true
		"spawn":
			if u != null:
				u.vis_pos = Vector2(u.pos)
				u.vis_alpha = 0.0
				u.vis_aware = true
				u.vis_dead = false
				var tw := create_tween()
				tw.tween_property(u, "vis_alpha", 1.0, 0.3 / speed)
				await tw.finished
		"infect":
			if u != null:
				u.vis_infected = true
				u.vis_hp = int(e["hp_after"])
				u.vis_flash = 1.0
				u.vis_pulse = 1.0
				u.vis_pulse_col = Color("#b060ff")
				board.add_fx("ring", BattleBoard.unit_foot(u.vis_pos), Color("#b060ff"), 0.5)
				board.add_fx("ring", BattleBoard.unit_foot(u.vis_pos), Color("#d8a0ff"), 0.7)
				await _w(0.25)

func _hop_to(u: BUnit, dest: Vector2, dur: float, h: float) -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(u, "vis_pos", dest, dur)
	tw.tween_method(func(v: float): u.vis_lift = sin(v * PI) * h, 0.0, 1.0, dur)
	await tw.finished
	u.vis_pos = dest          # land exactly on the tile
	u.vis_lift = 0.0

## Screen-space unit vector from src toward target (so lunges follow the iso diagonals).
func _screen_dir(src: BUnit, target: BUnit) -> Vector2:
	var d := Iso.center(Vector2(target.pos)) - Iso.center(src.vis_pos)
	return d.normalized() if d.length() > 0.01 else Vector2(0, 1)

func _lunge(src: BUnit, target: BUnit) -> void:
	if src == null or target == null:
		return
	var d := _screen_dir(src, target) * 5.0
	var tw := create_tween()
	tw.tween_property(src, "vis_off", d * 0.35 * -1.0, 0.05 / speed)       # wind-up
	tw.tween_property(src, "vis_off", d, 0.06 / speed).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(src, "vis_off", Vector2.ZERO, 0.09 / speed)
	await tw.finished
	src.vis_off = Vector2.ZERO

func _recoil(src: BUnit, target: BUnit) -> void:
	if src == null or target == null:
		return
	var d := _screen_dir(src, target) * -2.0
	var tw := create_tween()
	tw.tween_property(src, "vis_off", d, 0.06 / speed)
	tw.tween_property(src, "vis_off", Vector2.ZERO, 0.08 / speed)
	await tw.finished
	src.vis_off = Vector2.ZERO

func _projectile(src: BUnit, target: BUnit, kind: String) -> void:
	if src == null or target == null:
		return
	var from := board.body_pos(src)
	var to := board.body_pos(target)
	var col := Color("#9ae04a") if kind == "spit" else (Color("#8dff6a") if kind == "spore" else Color("#ffd060"))
	var dist := Vector2(src.pos).distance_to(Vector2(target.pos))
	var dur := clampf(0.12 + dist * 0.045, 0.18, 0.42)     # seconds at normal speed
	board.add_fx("proj", from, col, dur / speed, {"to": to, "arc": 4.0 + dist * 1.3})
	await _w(dur)
	board.add_fx("burst", to, col, 0.3)

func _shake_unit(u: BUnit, amp: float) -> void:
	var tw := create_tween()
	for i in 4:
		tw.tween_property(u, "vis_off", Vector2(amp if i % 2 == 0 else -amp, 0.0) * (1.0 - i * 0.2), 0.03 / speed)
	tw.tween_property(u, "vis_off", Vector2.ZERO, 0.03 / speed)

func _apply_hit(u: BUnit, e: Dictionary) -> void:
	if u == null:
		return
	u.vis_hp = int(e["hp_after"])
	u.vis_flash = 1.0
	var amt := int(e["amount"])
	var blocked := int(e.get("blocked", 0))
	var why := String(e.get("why", "attack"))
	var body := board.body_pos(u)
	if amt > 0:
		_popup(u, "-%d" % amt, Color("#ff6060") if not u.is_player else Color("#ff9090"))
	elif blocked > 0:
		_popup(u, "Blocked", UITheme.C_BLUE)
	match why:
		"bleed":
			u.vis_pulse = 1.0
			u.vis_pulse_col = Color("#ff3040")
			board.add_fx("ring", BattleBoard.unit_foot(u.vis_pos), Color("#ff3040"), 0.45)
		"poison":
			u.vis_pulse = 1.0
			u.vis_pulse_col = Color("#7aff40")
			board.add_fx("ring", BattleBoard.unit_foot(u.vis_pos), Color("#7aff40"), 0.45)
		"spores":
			u.vis_pulse = 1.0
			u.vis_pulse_col = Color("#8dff6a")
			board.add_fx("ring", BattleBoard.unit_foot(u.vis_pos), Color("#8dff6a"), 0.45)
		_:
			board.add_fx("burst", body, Color("#ffe9a0") if blocked == 0 else Color("#8fc8ff"), 0.28)
			if amt > 0:
				board.add_fx("slash", body, Color("#ffffff"), 0.22)
				_shake_unit(u, 1.0 + minf(2.0, amt / 8.0))
			if amt >= 8:
				board.shake = maxf(board.shake, 0.35)
	if u.is_player:
		board.shake = maxf(board.shake, 0.6 if why == "attack" else 0.2)
		hud.hp_override = u.vis_hp
		hud.refresh()
	await _w(0.16)

## Card-play feedback: the played card pops up and fades, and a coloured ring pulses under the player.
func _card_feedback(id: String, idx: int) -> void:
	if id == "":
		return
	var view: CardView = null
	for c in hand_root.get_children():
		if c is CardView and c.index == idx:
			view = c
	var card := DB.card(id)
	var col := Color("#ff6a5a") if String(card["type"]) == "attack" else (Color("#5aa8ff") if String(card["type"]) == "skill" else Color("#b878ff"))
	if view != null:
		var ghost := CardView.new().setup(id, idx)
		ghost.position = view.position
		ghost.z_index = 30
		ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ghost.pivot_offset = Vector2(CardView.W / 2.0, CardView.H / 2.0)
		add_child(ghost)
		view.visible = false
		var tw := ghost.create_tween().set_parallel(true)
		tw.tween_property(ghost, "position:y", ghost.position.y - 28.0, 0.26 / speed).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(ghost, "modulate:a", 0.0, 0.2 / speed).set_delay(0.08 / speed)
		tw.chain().tween_callback(ghost.queue_free)
	board.add_fx("ring", BattleBoard.unit_foot(battle.player.vis_pos), col, 0.4)
	await _w(0.14)

func _popup(u: BUnit, text: String, color: Color) -> void:
	if u == null:
		return
	var l := UITheme.label(text, 20, color, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.06))
	l.add_theme_constant_override("outline_size", 2)
	l.size = Vector2(62, 12)
	l.position = (BattleBoard.unit_foot(u.vis_pos) + Vector2(-31, -20)).round()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.z_index = 20
	board.add_child(l)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 13, 0.9 / speed)
	tw.tween_property(l, "modulate:a", 0.0, 0.9 / speed).set_delay(0.4 / speed)
	tw.chain().tween_callback(l.queue_free)

func _popup_player(text: String, color: Color) -> void:
	_popup(battle.player, text, color)
