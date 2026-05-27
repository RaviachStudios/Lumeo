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
	title.text = "How To Play"
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	title.position = Vector2(cx - 240, sz.y * 0.06)
	title.size = Vector2(480, 70)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	var steps := [
		["👁  Watch", "Simon will light up a sequence of colored buttons.\nPay close attention to the order!"],
		["👆  Repeat", "Tap the buttons in the exact same order.\nOne wrong press and it's game over."],
		["📈  Level Up", "Each round adds one more step to the sequence.\nSee how far your memory takes you!"],
		["🔁  Replay", "Stuck? Use a Replay token to watch the\nsequence again. You get 3 per game."],
	]

	for i in steps.size():
		var col := i % 2 == 0
		var x := cx - 420 if col else cx + 20
		var y := sz.y * (0.22 + (i / 2) * 0.32)
		_add_step(steps[i][0], steps[i][1], Vector2(x, y))

	var back := Button.new()
	back.text = "← Back to Home"
	back.position = Vector2(cx - 130, sz.y * 0.88)
	back.size = Vector2(260, 52)
	back.add_theme_font_size_override("font_size", 20)
	_style_flat(back, Color(0.15, 0.6, 0.95))
	back.pressed.connect(func() -> void: game_manager.show_home())
	add_child(back)

func _add_step(heading: String, body: String, pos: Vector2) -> void:
	var panel := Panel.new()
	panel.position = pos
	panel.size = Vector2(380, 130)
	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(1,1,1,0.07)
	sn.corner_radius_top_left = 14; sn.corner_radius_top_right = 14
	sn.corner_radius_bottom_left = 14; sn.corner_radius_bottom_right = 14
	panel.add_theme_stylebox_override("panel", sn)
	add_child(panel)

	var h := Label.new()
	h.text = heading
	h.add_theme_font_size_override("font_size", 22)
	h.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	h.position = Vector2(14, 12)
	h.size = Vector2(352, 30)
	panel.add_child(h)

	var b := Label.new()
	b.text = body
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", Color(0.85, 0.85, 0.95))
	b.position = Vector2(14, 48)
	b.size = Vector2(352, 70)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(b)

func _style_flat(btn: Button, col: Color) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.corner_radius_top_left = 12; s.corner_radius_top_right = 12
	s.corner_radius_bottom_left = 12; s.corner_radius_bottom_right = 12
	btn.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = col.lightened(0.15)
	btn.add_theme_stylebox_override("hover", sh)
	var sp := s.duplicate() as StyleBoxFlat
	sp.bg_color = col.darkened(0.15)
	btn.add_theme_stylebox_override("pressed", sp)
	btn.add_theme_color_override("font_color", Color.WHITE)
