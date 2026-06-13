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
	get_viewport().size_changed.connect(_layout_wheel)
	_build_hud()
	await get_tree().process_frame
	_start_game()

func _process(_dt: float) -> void:
	# Ad loads asynchronously — update button visibility whenever it becomes ready
	if _watch_ad_btn and _state == "input":
		_watch_ad_btn.visible = AdManager.rewarded_ready

func _draw() -> void:
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

	_build_quit_dialog(sz)

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
