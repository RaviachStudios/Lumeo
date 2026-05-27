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
const BG_BOT := Color(0.02, 0.08, 0.22)
const INNER_R := 90.0
const OUTER_R := 230.0

var num_buttons: int
var sequence: Array[int] = []
var player_seq: Array[int] = []
var level: int = 0
var replays: int = 3
var flash_time: float
var flash_gap: float
var speed_inc: float

var _lit: Array[bool] = []
var _press_anim: Array[float] = []  # 0..1, animates press
var _ring_center: Vector2
var _state: String = "idle"  # idle, showing, input, paused, gameover
var _paused_state: String = ""
var _last_input_frame: int = -1

var _status_lbl: Label
var _level_lbl: Label
var _pause_btn: Button
var _watch_ad_btn: Button

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	num_buttons = GameState.num_colors
	flash_time = GameState.flash_time
	flash_gap = GameState.flash_gap
	speed_inc = GameState.speed_increase
	for _i in num_buttons:
		_lit.append(false)
		_press_anim.append(0.0)
	_build_hud()
	await get_tree().process_frame
	_start_game()

func _process(dt: float) -> void:
	var dirty := false
	for i in num_buttons:
		if _press_anim[i] > 0.0:
			_press_anim[i] = maxf(0.0, _press_anim[i] - dt * 6.0)
			dirty = true
	if dirty:
		queue_redraw()
	# Ad loads asynchronously — update button visibility whenever it becomes ready
	if _watch_ad_btn and _state == "input":
		_watch_ad_btn.visible = AdManager.rewarded_ready

func _draw() -> void:
	var sz := get_viewport_rect().size
	_ring_center = sz / 2.0
	# Background gradient
	for y in range(0, int(sz.y), 4):
		var t := float(y) / sz.y
		draw_line(Vector2(0,y), Vector2(sz.x,y), BG_TOP.lerp(BG_BOT, t), 4.0)
	# Subtle grid lines
	for x in range(0, int(sz.x), 80):
		draw_line(Vector2(x,0), Vector2(x,sz.y), Color(1,1,1,0.025), 1.0)
	for y in range(0, int(sz.y), 80):
		draw_line(Vector2(0,y), Vector2(sz.x,y), Color(1,1,1,0.025), 1.0)
	# Ring shadow
	draw_circle(_ring_center, OUTER_R + 10, Color(0,0,0,0.22))
	# Buttons
	for i in num_buttons:
		_draw_button(i)
	# Center disc
	draw_circle(_ring_center, INNER_R - 6, Color(0.08, 0.08, 0.2))
	var level_txt := "LEVEL\n%d" % level
	_draw_centered_text(_ring_center, level_txt, 22, Color(1.0, 0.85, 0.2))

func _draw_button(idx: int) -> void:
	var angle_step := TAU / num_buttons
	var gap := deg_to_rad(4.5)
	var a0 := idx * angle_step + gap - PI * 0.5
	var a1 := (idx + 1) * angle_step - gap - PI * 0.5
	var press := _press_anim[idx]
	var shrink := press * 6.0
	var inner := INNER_R + shrink
	var outer := OUTER_R - shrink
	var col: Color = BUTTON_COLORS[idx]
	var is_lit := _lit[idx]

	# Layered bloom glow when lit (outermost → inward)
	if is_lit:
		draw_colored_polygon(
			_arc_poly(a0 - deg_to_rad(3.5), a1 + deg_to_rad(3.5), inner - 26, outer + 26, _ring_center),
			col * Color(1, 1, 1, 0.09))
		draw_colored_polygon(
			_arc_poly(a0 - deg_to_rad(2.0), a1 + deg_to_rad(2.0), inner - 14, outer + 14, _ring_center),
			col * Color(1, 1, 1, 0.20))
		draw_colored_polygon(
			_arc_poly(a0 - deg_to_rad(0.8), a1 + deg_to_rad(0.8), inner - 5, outer + 5, _ring_center),
			col * Color(1, 1, 1, 0.30))

	# Two-pass soft drop shadow
	draw_colored_polygon(
		_arc_poly(a0, a1, inner - 2, outer + 5, _ring_center + Vector2(2, 4)),
		Color(0, 0, 0, 0.18))
	draw_colored_polygon(
		_arc_poly(a0, a1, inner - 1, outer + 3, _ring_center + Vector2(1, 2)),
		Color(0, 0, 0, 0.22))

	# Main face — clean flat surface
	var face_col: Color
	if is_lit:
		face_col = col.lightened(0.44)
	elif press > 0.0:
		face_col = col.darkened(press * 0.20)
	else:
		face_col = col
	draw_colored_polygon(
		_arc_poly(a0, a1, inner, outer, _ring_center),
		face_col)

	# Subtle inner-edge highlight — single thin bright arc
	var hi := 0.50 if is_lit else 0.22 * (1.0 - press * 0.9)
	draw_polyline(
		_arc_line(a0 + deg_to_rad(1.5), a1 - deg_to_rad(1.5), inner + 4, _ring_center),
		Color(1, 1, 1, hi), 2.0)

func _arc_poly(a0: float, a1: float, inner_r: float, outer_r: float,
		center: Vector2, steps: int = 20) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for j in range(steps + 1):
		var t: float = float(j) / steps
		var a: float = lerp(a0, a1, t)
		pts.append(center + Vector2(cos(a), sin(a)) * outer_r)
	for j in range(steps + 1):
		var t: float = float(j) / steps
		var a: float = lerp(a1, a0, t)
		pts.append(center + Vector2(cos(a), sin(a)) * inner_r)
	return pts

func _arc_line(a0: float, a1: float, r: float, center: Vector2,
		steps: int = 20) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for j in range(steps + 1):
		var t: float = float(j) / steps
		var a: float = lerp(a0, a1, t)
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	return pts

func _draw_centered_text(pos: Vector2, txt: String, size_px: int, col: Color) -> void:
	var font := ThemeDB.fallback_font
	var lines := txt.split("\n")
	var total_h := lines.size() * size_px * 1.3
	var y := pos.y - total_h * 0.5
	for line in lines:
		var w := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
		draw_string(font, Vector2(pos.x - w * 0.5, y + size_px), line, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, col)
		y += size_px * 1.3

func _get_button_at(pos: Vector2) -> int:
	var rel := pos - _ring_center
	var dist := rel.length()
	if dist < INNER_R or dist > OUTER_R:
		return -1
	var angle := atan2(rel.y, rel.x) + PI * 0.5
	if angle < 0.0:
		angle += TAU
	return int(angle / (TAU / num_buttons)) % num_buttons

func _input(event: InputEvent) -> void:
	if _state != "input":
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
	var btn := _get_button_at(tap_pos)
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
	_watch_ad_btn.text = "📺 Replay"
	_watch_ad_btn.position = Vector2(20, 60)
	_watch_ad_btn.size = Vector2(160, 44)
	_watch_ad_btn.add_theme_font_size_override("font_size", 17)
	_flat_btn(_watch_ad_btn, Color(0.75, 0.55, 0.0))
	_watch_ad_btn.pressed.connect(_on_watch_ad)
	_watch_ad_btn.visible = false
	add_child(_watch_ad_btn)

	_pause_btn = Button.new()
	_pause_btn.text = "⏸ Pause"
	_pause_btn.position = Vector2(sz.x - 150, 20)
	_pause_btn.size = Vector2(130, 44)
	_pause_btn.add_theme_font_size_override("font_size", 16)
	_flat_btn(_pause_btn, Color(0.3, 0.3, 0.5))
	_pause_btn.pressed.connect(_on_pause)
	add_child(_pause_btn)

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

	# Pause overlay (hidden by default)
	_build_pause_overlay(sz)

func _build_pause_overlay(sz: Vector2) -> void:
	var overlay := Panel.new()
	overlay.name = "PauseOverlay"
	overlay.visible = false
	overlay.position = Vector2(sz.x * 0.5 - 180, sz.y * 0.5 - 120)
	overlay.size = Vector2(360, 240)
	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(0.05, 0.05, 0.2, 0.95)
	sn.corner_radius_top_left = 18; sn.corner_radius_top_right = 18
	sn.corner_radius_bottom_left = 18; sn.corner_radius_bottom_right = 18
	sn.border_color = Color(0.4, 0.4, 0.8); sn.border_width_left = 2
	sn.border_width_right = 2; sn.border_width_top = 2; sn.border_width_bottom = 2
	overlay.add_theme_stylebox_override("panel", sn)
	add_child(overlay)

	var lbl := Label.new()
	lbl.text = "PAUSED"
	lbl.add_theme_font_size_override("font_size", 40)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	lbl.position = Vector2(60, 30)
	lbl.size = Vector2(240, 56)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay.add_child(lbl)

	var resume := Button.new()
	resume.text = "▶ Resume"
	resume.position = Vector2(60, 110)
	resume.size = Vector2(240, 50)
	resume.add_theme_font_size_override("font_size", 20)
	_flat_btn(resume, Color(0.15, 0.6, 0.3))
	resume.pressed.connect(_on_resume)
	overlay.add_child(resume)

	var home := Button.new()
	home.text = "🏠 Home"
	home.position = Vector2(60, 172)
	home.size = Vector2(240, 50)
	home.add_theme_font_size_override("font_size", 20)
	_flat_btn(home, Color(0.3, 0.3, 0.55))
	home.pressed.connect(func() -> void: game_manager.show_home())
	overlay.add_child(home)

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
	_lit[idx] = true
	queue_redraw()
	AudioManager.play_button_tone(idx, duration)
	await get_tree().create_timer(duration).timeout
	_lit[idx] = false
	queue_redraw()

func _player_pressed(idx: int) -> void:
	_press_anim[idx] = 1.0
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

func _on_pause() -> void:
	if _state == "paused":
		return
	_paused_state = _state
	_state = "paused"
	_pause_btn.text = ""
	get_node("PauseOverlay").visible = true

func _on_resume() -> void:
	get_node("PauseOverlay").visible = false
	_pause_btn.text = "⏸ Pause"
	_state = _paused_state
	if _state == "showing":
		# Re-play sequence from start
		_state = "input"
		_status_lbl.text = "Your turn!"

func _on_watch_ad() -> void:
	if _state != "input":
		return
	AdManager.show_rewarded(func() -> void:
		replays += 1
		_on_replay())

func _game_over() -> void:
	_state = "gameover"
	AudioManager.play_lose_sound()
	_status_lbl.text = "Game Over!"
	AdManager.try_show_interstitial()
	await get_tree().create_timer(1.8).timeout
	game_manager.show_game_over(level - 1)

func _update_hud() -> void:
	_level_lbl.text = "Level: %d" % level
	if _watch_ad_btn:
		_watch_ad_btn.visible = AdManager.rewarded_ready
