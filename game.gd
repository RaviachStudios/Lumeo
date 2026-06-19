extends Control

var game_manager: Node

const BUTTON_COLORS := [
	Color(0.9, 0.15, 0.15),   # Red
	Color(0.15, 0.8, 0.15),   # Green
	Color(0.15, 0.35, 0.95),  # Blue
	Color(0.95, 0.85, 0.1),   # Yellow
	Color(0.95, 0.5,  0.1),   # Orange
	Color(0.95, 0.3,  0.7),   # Pink
]
const BG_TOP := Color(0.05, 0.05, 0.15)
const BG_BOT := Color(0.02, 0.08, 0.22, 1.0)

var num_buttons: int
var sequence: Array[int] = []
var player_seq: Array[int] = []
var level: int = 0
var replays: int = 3
var flash_time: float
var flash_gap: float
var speed_inc: float

var _wheel: SimonWheel
var _state: String = "idle"  # idle, showing, input, gameover
var _last_input_frame: int = -1

var _status_lbl: Label
var _level_lbl: Label
var _quit_btn: Button
var _watch_ad_btn: Button
# Coins HUD: a top-center pill showing the coins earned THIS session (starts at
# 0). The "+ N" indicator is spawned next to it whenever a level completes; we
# keep a reference so multiple awards in quick succession don't pile up on top
# of each other. The session total is banked into the wallet at game over.
var _coin_panel: Panel
var _coin_lbl: Label
var _coin_icon: Control
var _earn_indicator: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	num_buttons = GameState.num_colors
	flash_time = GameState.flash_time
	flash_gap = GameState.flash_gap
	speed_inc = GameState.speed_increase
	# 3D Simon wheel (rendered via SubViewport). Added before the HUD so it sits
	# behind the labels/buttons; it ignores mouse input - taps are handled here.
	_wheel = SimonWheel.new()
	add_child(_wheel)
	_layout_wheel()
	_wheel.configure(num_buttons, BUTTON_COLORS)
	_apply_simon_skin()
	get_viewport().size_changed.connect(_layout_wheel)
	_build_hud()
	await get_tree().process_frame
	_start_game()

func _process(_dt: float) -> void:
	# Ad loads asynchronously — update button visibility whenever it becomes ready
	if _watch_ad_btn and _state == "input":
		_watch_ad_btn.visible = AdManager.rewarded_ready

func _draw() -> void:
	# When a shop theme is equipped, BackgroundManager fills the viewport;
	# drawing our own gradient would obscure it.
	if BackgroundManager.is_themed():
		return
	var sz := get_viewport_rect().size
	# Background gradient (the wheel composites on top with a transparent backdrop)
	for y in range(0, int(sz.y), 4):
		var t := float(y) / sz.y
		draw_line(Vector2(0,y), Vector2(sz.x,y), BG_TOP.lerp(BG_BOT, t), 4.0)
	# Subtle grid lines
	for x in range(0, int(sz.x), 80):
		draw_line(Vector2(x,0), Vector2(x,sz.y), Color(1,1,1,0.025), 1.0)
	for y in range(0, int(sz.y), 80):
		draw_line(Vector2(0,y), Vector2(sz.x,y), Color(1,1,1,0.025), 1.0)

# Center the 3D wheel as a large square, leaving room for the top/bottom HUD.
func _layout_wheel() -> void:
	if _wheel == null:
		return
	var sz := get_viewport_rect().size
	var s: float = minf(sz.x, sz.y) * 0.92
	_wheel.size = Vector2(s, s)
	_wheel.position = (sz - _wheel.size) * 0.5

# Apply the player's equipped Simon customization (shop "SIMON" tab) to the
# wheel. CoinsManager is already loaded by the time a game starts (the home
# screen waits on CoinsManager.loaded), so the equipped colours are available
# immediately. In skin mode there are no skins yet, so the wheel keeps its stock
# look (all-null) for now.
func _apply_simon_skin() -> void:
	if _wheel == null:
		return
	_wheel.apply_skin(
		_resolved_simon_tint("outer_circle"),
		_resolved_simon_tint("inner_circle"),
		_resolved_simon_tint("level_number"))

# Returns the Color tint for a category, or null to keep the stock look.
func _resolved_simon_tint(category: String) -> Variant:
	if not CoinsManager.is_simon_manual():
		return null
	var id := CoinsManager.equipped_simon_color(category)
	if id == CoinsManager.SIMON_DEFAULT_COLOR:
		return null
	return CoinsManager.simon_color_value(id)

func _input(event: InputEvent) -> void:
	if _state != "input" or get_node("QuitDialog").visible:
		return
	var tap_pos := Vector2(-1, -1)
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			tap_pos = mb.position
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			tap_pos = st.position
	if tap_pos.x < 0:
		return
	# emulate_touch_from_mouse fires both MouseButton and ScreenTouch for one
	# click — guard against double-processing in the same frame
	var frame := Engine.get_process_frames()
	if frame == _last_input_frame:
		return
	_last_input_frame = frame
	var btn := _wheel.segment_at_point(tap_pos - _wheel.position)
	if btn >= 0:
		_player_pressed(btn)
		get_viewport().set_input_as_handled()

func _build_hud() -> void:
	var sz := get_viewport_rect().size

	_level_lbl = Label.new()
	_level_lbl.add_theme_font_size_override("font_size", 20)
	_level_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 1.0))
	_level_lbl.position = Vector2(20, 20)
	_level_lbl.size = Vector2(180, 36)
	add_child(_level_lbl)

	_watch_ad_btn = Button.new()
	_watch_ad_btn.text = "Watch Ad to Replay"
	_watch_ad_btn.position = Vector2(20, 60)
	_watch_ad_btn.size = Vector2(220, 44)
	_watch_ad_btn.add_theme_font_size_override("font_size", 15)
	_flat_btn(_watch_ad_btn, Color(0.75, 0.55, 0.0))
	_watch_ad_btn.pressed.connect(_on_watch_ad)
	_watch_ad_btn.visible = false
	add_child(_watch_ad_btn)

	_quit_btn = Button.new()
	_quit_btn.text = "Quit"
	_quit_btn.position = Vector2(sz.x - 120, 20)
	_quit_btn.size = Vector2(100, 44)
	_quit_btn.add_theme_font_size_override("font_size", 16)
	_flat_btn(_quit_btn, Color(0.45, 0.1, 0.1))
	_quit_btn.pressed.connect(_on_quit)
	add_child(_quit_btn)

	_status_lbl = Label.new()
	_status_lbl.add_theme_font_size_override("font_size", 26)
	_status_lbl.add_theme_color_override("font_color", Color.WHITE)
	_status_lbl.add_theme_color_override("font_shadow_color", Color(0,0,0,0.5))
	_status_lbl.add_theme_constant_override("shadow_offset_x", 2)
	_status_lbl.add_theme_constant_override("shadow_offset_y", 2)
	_status_lbl.position = Vector2(sz.x * 0.5 - 260, sz.y - 70)
	_status_lbl.size = Vector2(520, 50)
	_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_status_lbl)

	if FirebaseManager.is_signed_in():
		_build_coin_hud(sz)
	_build_quit_dialog(sz)

# Top-center pill: a small gold coin glyph + the coins earned this session
# (starts at 0). Only shown when signed in (offline users don't accumulate
# coins). The pill is the anchor for the floating "+ N" earn indicator we spawn
# after each level.
func _build_coin_hud(sz: Vector2) -> void:
	const PW := 150.0
	const PH := 44.0
	_coin_panel = Panel.new()
	_coin_panel.position = Vector2(sz.x * 0.5 - PW * 0.5, 18)
	_coin_panel.size = Vector2(PW, PH)
	_coin_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.06, 0.07, 0.18, 0.85)
	st.set_corner_radius_all(int(PH * 0.5))
	st.border_color = Color(1.0, 0.78, 0.20, 0.7)
	st.set_border_width_all(1)
	st.shadow_color = Color(1.0, 0.78, 0.20, 0.30)
	st.shadow_size = 8
	_coin_panel.add_theme_stylebox_override("panel", st)
	add_child(_coin_panel)

	_coin_icon = _make_coin_icon(22.0)
	_coin_icon.position = Vector2(14, (PH - 22.0) * 0.5)
	_coin_panel.add_child(_coin_icon)

	_coin_lbl = Label.new()
	_coin_lbl.text = "0"
	_coin_lbl.add_theme_font_size_override("font_size", 22)
	_coin_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.42))
	_coin_lbl.position = Vector2(42, 0)
	_coin_lbl.size = Vector2(PW - 56, PH)
	_coin_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_coin_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_coin_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coin_panel.add_child(_coin_lbl)

	# Track coins earned this session (not the wallet total) — the running sum
	# is added to the balance at game over.
	CoinsManager.session_earned_changed.connect(_on_session_changed)

# A small coin: gold disc + bright ring + "$" mark, positioned via top-left.
func _make_coin_icon(d: float) -> Control:
	var c := Control.new()
	c.size = Vector2(d, d)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var disc := Panel.new()
	disc.size = Vector2(d, d)
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ds := StyleBoxFlat.new()
	ds.bg_color = Color(1.0, 0.78, 0.16)
	ds.set_corner_radius_all(int(d * 0.5))
	ds.border_color = Color(1.0, 0.92, 0.55)
	ds.set_border_width_all(2)
	ds.shadow_color = Color(1.0, 0.6, 0.0, 0.55)
	ds.shadow_size = 5
	disc.add_theme_stylebox_override("panel", ds)
	c.add_child(disc)
	var glyph := Label.new()
	glyph.text = "$"
	glyph.add_theme_font_size_override("font_size", int(d * 0.7))
	glyph.add_theme_color_override("font_color", Color(0.45, 0.30, 0.05))
	glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.add_child(glyph)
	return c

func _on_session_changed(session_total: int) -> void:
	if _coin_lbl:
		_coin_lbl.text = str(session_total)

func _build_quit_dialog(sz: Vector2) -> void:
	var overlay := Panel.new()
	overlay.name = "QuitDialog"
	overlay.visible = false
	overlay.position = Vector2(sz.x * 0.5 - 190, sz.y * 0.5 - 100)
	overlay.size = Vector2(380, 200)
	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(0.05, 0.05, 0.2, 0.97)
	sn.corner_radius_top_left = 18; sn.corner_radius_top_right = 18
	sn.corner_radius_bottom_left = 18; sn.corner_radius_bottom_right = 18
	sn.border_color = Color(0.5, 0.15, 0.15)
	sn.border_width_left = 2; sn.border_width_right = 2
	sn.border_width_top = 2; sn.border_width_bottom = 2
	overlay.add_theme_stylebox_override("panel", sn)
	add_child(overlay)

	var lbl := Label.new()
	lbl.text = "Quit to Home?"
	lbl.add_theme_font_size_override("font_size", 30)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.position = Vector2(0, 28)
	lbl.size = Vector2(380, 44)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay.add_child(lbl)

	var sub := Label.new()
	sub.text = "Your progress will be lost."
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	sub.position = Vector2(0, 72)
	sub.size = Vector2(380, 24)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay.add_child(sub)

	var yes := Button.new()
	yes.text = "Yes, Quit"
	yes.position = Vector2(24, 120)
	yes.size = Vector2(155, 52)
	yes.add_theme_font_size_override("font_size", 18)
	_flat_btn(yes, Color(0.55, 0.12, 0.12))
	yes.pressed.connect(func() -> void: game_manager.show_home())
	overlay.add_child(yes)

	var no := Button.new()
	no.text = "Keep Playing"
	no.position = Vector2(201, 120)
	no.size = Vector2(155, 52)
	no.add_theme_font_size_override("font_size", 18)
	_flat_btn(no, Color(0.15, 0.45, 0.2))
	no.pressed.connect(func() -> void: get_node("QuitDialog").visible = false)
	overlay.add_child(no)

func _flat_btn(btn: Button, col: Color) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.corner_radius_top_left = 10; s.corner_radius_top_right = 10
	s.corner_radius_bottom_left = 10; s.corner_radius_bottom_right = 10
	btn.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat; sh.bg_color = col.lightened(0.2)
	btn.add_theme_stylebox_override("hover", sh)
	var sp := s.duplicate() as StyleBoxFlat; sp.bg_color = col.darkened(0.15)
	btn.add_theme_stylebox_override("pressed", sp)
	btn.add_theme_color_override("font_color", Color.WHITE)

func _start_game() -> void:
	sequence = []
	player_seq = []
	level = 0
	replays = 0
	CoinsManager.start_game_session()
	_update_hud()
	_next_round()

func _next_round() -> void:
	level += 1
	player_seq = []
	sequence.append(randi() % num_buttons)
	flash_time = maxf(0.18, GameState.flash_time - (level - 1) * speed_inc)
	flash_gap = maxf(0.08, GameState.flash_gap - (level - 1) * speed_inc * 0.5)
	_update_hud()
	_status_lbl.text = "Watch carefully..."
	_state = "showing"
	await get_tree().create_timer(0.6).timeout
	await _play_sequence()
	_state = "input"
	_status_lbl.text = "Your turn!"

func _play_sequence() -> void:
	for idx: int in sequence:
		await _flash(idx, flash_time)
		await get_tree().create_timer(flash_gap).timeout

func _flash(idx: int, duration: float) -> void:
	_wheel.set_lit(idx, true)
	AudioManager.play_button_tone(idx, duration)
	await get_tree().create_timer(duration).timeout
	_wheel.set_lit(idx, false)

# Brief press feedback on the 3D wheel: sink the segment and light it, then
# release shortly after (set_press/set_lit do not auto-decay).
func _press_feedback(idx: int) -> void:
	_wheel.set_press(idx, 1.0)
	_wheel.set_lit(idx, true)
	get_tree().create_timer(0.18).timeout.connect(func() -> void:
		_wheel.set_lit(idx, false)
		_wheel.set_press(idx, 0.0))

func _player_pressed(idx: int) -> void:
	_press_feedback(idx)
	AudioManager.play_button_tone(idx, 0.3)
	player_seq.append(idx)
	var step := player_seq.size() - 1
	if player_seq[step] != sequence[step]:
		_state = "showing"
		var correct := sequence[step]
		_status_lbl.text = "The correct button was..."
		await get_tree().create_timer(0.35).timeout
		for _i in 3:
			await _flash(correct, 0.28)
			await get_tree().create_timer(0.14).timeout
		_game_over()
		return
	if player_seq.size() == sequence.size():
		_state = "idle"
		_status_lbl.text = "Correct! Get ready..."
		# Award coins for this completed level and float a "+ N" indicator
		# next to the balance pill. Returns 0 if not signed in.
		var earned := CoinsManager.award_for_level(GameState.difficulty, level)
		if earned > 0:
			_show_earn_indicator(earned)
		await get_tree().create_timer(0.8).timeout
		_next_round()

func _on_replay() -> void:
	if _state != "input" or replays <= 0:
		return
	replays -= 1
	_update_hud()
	AudioManager.play_replay_sound()
	_state = "showing"
	_status_lbl.text = "Replaying sequence..."
	player_seq = []
	await _play_sequence()
	_state = "input"
	_status_lbl.text = "Your turn!"

func _on_quit() -> void:
	get_node("QuitDialog").visible = true

func _on_watch_ad() -> void:
	if _state != "input":
		return
	AdManager.show_rewarded(_replay_after_countdown)

func _replay_after_countdown() -> void:
	_state = "showing"
	for n: int in [3, 2, 1]:
		_status_lbl.text = str(n) + "..."
		await get_tree().create_timer(1.0).timeout
	replays += 1
	_state = "input"
	_on_replay()

func _game_over() -> void:
	_state = "gameover"
	# Bank the coins earned this session into the persistent wallet.
	CoinsManager.commit_session()
	AudioManager.play_lose_sound()
	_status_lbl.text = "Game Over!"
	if level > 5:
		AdManager.try_show_interstitial()
	await get_tree().create_timer(1.8).timeout
	game_manager.show_game_over(level - 1)

func _update_hud() -> void:
	_level_lbl.text = "Level: %d" % level
	if _wheel:
		_wheel.set_level(level)
	if _watch_ad_btn:
		_watch_ad_btn.visible = AdManager.rewarded_ready

# Float a gold "+ N" beside the coin pill, drifting up and fading out. Replaces
# any indicator still in flight (rapid awards shouldn't pile up).
func _show_earn_indicator(amount: int) -> void:
	if _coin_panel == null:
		return
	if _earn_indicator and is_instance_valid(_earn_indicator):
		_earn_indicator.queue_free()
	var lbl := Label.new()
	lbl.text = "+ %d" % amount
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45))
	lbl.add_theme_color_override("font_shadow_color", Color(0.5, 0.32, 0.0, 0.7))
	lbl.add_theme_constant_override("shadow_offset_x", 0)
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	lbl.add_theme_constant_override("shadow_outline_size", 6)
	lbl.size = Vector2(90, 36)
	# Anchor immediately to the RIGHT of the coin pill, vertically centered.
	lbl.position = _coin_panel.position + Vector2(_coin_panel.size.x + 6, (_coin_panel.size.y - 36) * 0.5)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)
	_earn_indicator = lbl

	# Quick scale-pop on the coin pill itself, so the change feels punchy.
	_coin_panel.pivot_offset = _coin_panel.size * 0.5
	var pop := create_tween()
	pop.tween_property(_coin_panel, "scale", Vector2.ONE * 1.12, 0.10) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	pop.tween_property(_coin_panel, "scale", Vector2.ONE, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 36.0, 0.85) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.85).set_delay(0.25)
	tw.chain().tween_callback(lbl.queue_free)
