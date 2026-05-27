extends Control

var game_manager: Node

const BG_TOP := Color(0.04, 0.04, 0.18)
const BG_BOT := Color(0.08, 0.03, 0.25)

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()

func _draw() -> void:
	var sz := get_viewport_rect().size
	for y in range(0, int(sz.y), 4):
		var t := float(y) / sz.y
		draw_line(Vector2(0, y), Vector2(sz.x, y), BG_TOP.lerp(BG_BOT, t), 4.0)

func _build_ui() -> void:
	var sz := get_viewport_rect().size
	var cx := sz.x * 0.5

	var title := Label.new()
	title.text = "Choose Difficulty"
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	title.position = Vector2(cx - 280, sz.y * 0.1)
	title.size = Vector2(560, 72)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	var diffs := [
		{"label": "EASY",     "col": Color(0.15, 0.75, 0.3),  "diff": "easy"},
		{"label": "MODERATE", "col": Color(0.95, 0.65, 0.1),  "diff": "moderate"},
		{"label": "HARD",     "col": Color(0.9, 0.15, 0.15),  "diff": "hard"},
	]

	for i in diffs.size():
		var d: Dictionary = diffs[i]
		var y := sz.y * (0.27 + i * 0.22)
		_add_diff_btn(d["label"] as String, Vector2(cx - 260, y), d["col"] as Color, d["diff"] as String)

	var back := Button.new()
	back.text = "← Back"
	back.position = Vector2(30, 20)
	back.size = Vector2(120, 44)
	back.add_theme_font_size_override("font_size", 18)
	_style_btn(back, Color(0.2, 0.2, 0.4))
	back.pressed.connect(func() -> void: game_manager.show_home())
	add_child(back)

func _add_diff_btn(label: String, pos: Vector2, col: Color, diff: String) -> void:
	var container := Panel.new()
	container.position = pos
	container.size = Vector2(520, 80)
	var sn := StyleBoxFlat.new()
	sn.bg_color = col * Color(1,1,1,0.15)
	sn.border_color = col
	sn.border_width_left = 3; sn.border_width_right = 3
	sn.border_width_top = 3; sn.border_width_bottom = 3
	sn.corner_radius_top_left = 12; sn.corner_radius_top_right = 12
	sn.corner_radius_bottom_left = 12; sn.corner_radius_bottom_right = 12
	container.add_theme_stylebox_override("panel", sn)
	add_child(container)

	var btn := Button.new()
	btn.text = label
	btn.position = Vector2(0, 0)
	btn.size = Vector2(520, 80)
	btn.add_theme_font_size_override("font_size", 32)
	btn.add_theme_color_override("font_color", col)
	_style_btn(btn, Color(0,0,0,0))
	var sh := StyleBoxFlat.new()
	sh.bg_color = col * Color(1,1,1,0.25)
	sh.corner_radius_top_left = 12; sh.corner_radius_top_right = 12
	sh.corner_radius_bottom_left = 12; sh.corner_radius_bottom_right = 12
	btn.add_theme_stylebox_override("hover", sh)
	btn.pressed.connect(func() -> void:
		GameState.set_difficulty(diff)
		game_manager.show_game()
	)
	container.add_child(btn)

func _style_btn(btn: Button, col: Color) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.corner_radius_top_left = 12; s.corner_radius_top_right = 12
	s.corner_radius_bottom_left = 12; s.corner_radius_bottom_right = 12
	btn.add_theme_stylebox_override("normal", s)
	var sp := s.duplicate() as StyleBoxFlat
	sp.bg_color = col.darkened(0.1)
	btn.add_theme_stylebox_override("pressed", sp)
