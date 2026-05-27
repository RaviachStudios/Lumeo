extends Control

var game_manager: Node
var rounds: int = 0

const BG_TOP := Color(0.04, 0.04, 0.18)
const BG_BOT := Color(0.08, 0.03, 0.25)
const GOLD := Color(1.0, 0.85, 0.2)

var _confetti: Array[Dictionary] = []
var _time: float = 0.0
var _is_new_high: bool = false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_is_new_high = GameState.submit_score(rounds)
	_spawn_confetti()
	_build_ui()
	AudioManager.play_win_sound()

func _spawn_confetti() -> void:
	var colors := [Color(0.9,0.15,0.15), Color(0.15,0.8,0.15), Color(0.15,0.35,0.95),
				   Color(0.95,0.85,0.1), Color(0.95,0.5,0.1), Color(0.95,0.3,0.7), Color.WHITE]
	var sz := get_viewport_rect().size
	var count := 90 if _is_new_high else 60
	for _i in count:
		_confetti.append({
			"pos": Vector2(randf() * sz.x, randf_range(-120.0, 0.0)),
			"vel": Vector2(randf_range(-50.0, 50.0), randf_range(60.0, 200.0)),
			"col": colors[randi() % colors.size()],
			"size": randf_range(5.0, 14.0),
			"rot": randf() * TAU,
			"rot_speed": randf_range(-3.0, 3.0),
		})

func _process(dt: float) -> void:
	_time += dt
	var sz := get_viewport_rect().size
	for c: Dictionary in _confetti:
		c["pos"] = (c["pos"] as Vector2) + (c["vel"] as Vector2) * dt
		c["rot"] = (c["rot"] as float) + (c["rot_speed"] as float) * dt
		if (c["pos"] as Vector2).y > sz.y + 20:
			c["pos"] = Vector2(randf() * sz.x, -20.0)
	queue_redraw()

func _draw() -> void:
	var sz := get_viewport_rect().size
	for y in range(0, int(sz.y), 4):
		var t := float(y) / sz.y
		draw_line(Vector2(0,y), Vector2(sz.x,y), BG_TOP.lerp(BG_BOT, t), 4.0)
	for c: Dictionary in _confetti:
		var pos: Vector2 = c["pos"]
		var s: float = c["size"]
		var col: Color = c["col"]
		var fade := minf(1.0, _time * 2.0)
		draw_rect(Rect2(pos - Vector2(s,s)*0.5, Vector2(s,s)), col * Color(1,1,1,0.8 * fade))

func _build_ui() -> void:
	var sz := get_viewport_rect().size
	var cx := sz.x * 0.5
	var best: int = GameState.get_high_score()

	# Emoji + heading
	var emoji := Label.new()
	emoji.text = "🏆" if _is_new_high else "🎉"
	emoji.add_theme_font_size_override("font_size", 72)
	emoji.position = Vector2(cx - 60, sz.y * 0.05)
	emoji.size = Vector2(120, 90)
	emoji.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(emoji)

	var heading := Label.new()
	heading.text = "NEW HIGH SCORE!" if _is_new_high else "Well Played!"
	heading.add_theme_font_size_override("font_size", 52)
	heading.add_theme_color_override("font_color", Color(1.0, 0.6, 0.1) if _is_new_high else GOLD)
	heading.add_theme_color_override("font_shadow_color", Color(0,0,0,0.5))
	heading.add_theme_constant_override("shadow_offset_x", 3)
	heading.add_theme_constant_override("shadow_offset_y", 3)
	heading.position = Vector2(cx - 300, sz.y * 0.22)
	heading.size = Vector2(600, 70)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(heading)

	# Round count
	var sub := Label.new()
	sub.text = "You completed %d round%s!" % [rounds, "s" if rounds != 1 else ""]
	sub.add_theme_font_size_override("font_size", 26)
	sub.add_theme_color_override("font_color", Color(0.85, 0.85, 1.0))
	sub.position = Vector2(cx - 340, sz.y * 0.38)
	sub.size = Vector2(680, 40)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sub)

	# High score panel
	const PW := 340.0
	const PH := 108.0
	var panel := Panel.new()
	panel.position = Vector2(cx - PW * 0.5, sz.y * 0.50)
	panel.size = Vector2(PW, PH)
	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(0.38, 0.22, 0.0, 0.45) if _is_new_high else Color(0.08, 0.08, 0.22, 0.7)
	sn.border_color = GOLD if _is_new_high else Color(0.3, 0.3, 0.6)
	sn.border_width_left = 3 if _is_new_high else 2
	sn.border_width_right = 3 if _is_new_high else 2
	sn.border_width_top = 3 if _is_new_high else 2
	sn.border_width_bottom = 3 if _is_new_high else 2
	sn.corner_radius_top_left = 18; sn.corner_radius_top_right = 18
	sn.corner_radius_bottom_left = 18; sn.corner_radius_bottom_right = 18
	panel.add_theme_stylebox_override("panel", sn)
	add_child(panel)

	var header := Label.new()
	header.text = "★  PERSONAL BEST  ★"
	header.add_theme_font_size_override("font_size", 13)
	header.add_theme_color_override("font_color", GOLD if _is_new_high else Color(0.5, 0.5, 0.75))
	header.position = Vector2(0, 10)
	header.size = Vector2(PW, 20)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(header)

	var score_num := Label.new()
	score_num.text = str(best)
	score_num.add_theme_font_size_override("font_size", 46)
	score_num.add_theme_color_override("font_color", GOLD if _is_new_high else Color.WHITE)
	if _is_new_high:
		score_num.add_theme_color_override("font_shadow_color", Color(1.0, 0.5, 0.0, 0.55))
		score_num.add_theme_constant_override("shadow_offset_x", 2)
		score_num.add_theme_constant_override("shadow_offset_y", 2)
	score_num.position = Vector2(0, 28)
	score_num.size = Vector2(PW, 56)
	score_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(score_num)

	var rounds_lbl := Label.new()
	rounds_lbl.text = "round%s" % ("s" if best != 1 else "")
	rounds_lbl.add_theme_font_size_override("font_size", 14)
	rounds_lbl.add_theme_color_override("font_color", GOLD.darkened(0.2) if _is_new_high else Color(0.55, 0.55, 0.8))
	rounds_lbl.position = Vector2(0, 82)
	rounds_lbl.size = Vector2(PW, 20)
	rounds_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(rounds_lbl)

	_add_btn("🏠  Home", Vector2(cx - 250, sz.y * 0.76), Color(0.15, 0.6, 0.95),
		func() -> void: game_manager.show_home())
	_add_btn("▶  Play Again", Vector2(cx + 10, sz.y * 0.76), Color(0.2, 0.65, 0.3),
		func() -> void: game_manager.show_difficulty())

func _add_btn(txt: String, pos: Vector2, col: Color, cb: Callable) -> void:
	var btn := Button.new()
	btn.text = txt
	btn.position = pos
	btn.size = Vector2(220, 60)
	btn.add_theme_font_size_override("font_size", 22)
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.corner_radius_top_left = 14; s.corner_radius_top_right = 14
	s.corner_radius_bottom_left = 14; s.corner_radius_bottom_right = 14
	btn.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = col.lightened(0.2)
	btn.add_theme_stylebox_override("hover", sh)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.pressed.connect(cb)
	add_child(btn)
