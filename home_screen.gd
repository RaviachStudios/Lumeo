extends Control

var game_manager: Node

const BG_TOP := Color(0.04, 0.04, 0.18)
const BG_BOT := Color(0.08, 0.03, 0.25)
const GOLD := Color(1.0, 0.85, 0.2)
const BUTTON_COLORS := [Color(0.9,0.15,0.15), Color(0.15,0.8,0.15), Color(0.15,0.35,0.95), Color(0.95,0.85,0.1), Color(0.95,0.5,0.1), Color(0.95,0.3,0.7)]

var _deco_angles: Array[float] = []
var _deco_speeds: Array[float] = []

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 6:
		_deco_angles.append(i * TAU / 6.0)
		_deco_speeds.append(0.12 + i * 0.03)
	_build_ui()
	AudioManager.play_bg_music()

func _process(dt: float) -> void:
	for i in _deco_angles.size():
		_deco_angles[i] += _deco_speeds[i] * dt
	queue_redraw()

func _draw() -> void:
	var sz := get_viewport_rect().size
	# Gradient background
	draw_rect(Rect2(Vector2.ZERO, sz), BG_TOP)
	for y in range(0, int(sz.y), 4):
		var t := float(y) / sz.y
		var c := BG_TOP.lerp(BG_BOT, t)
		draw_line(Vector2(0, y), Vector2(sz.x, y), c, 4.0)
	# Decorative orbiting circles
	var cx := sz.x * 0.5
	var cy := sz.y * 0.5
	var orb_r := minf(cx, cy) * 0.72
	for i in 6:
		var a := _deco_angles[i]
		var pos := Vector2(cx + cos(a) * orb_r, cy + sin(a) * orb_r)
		var col: Color = BUTTON_COLORS[i]
		draw_circle(pos, 28.0, col * Color(1,1,1,0.18))
		draw_circle(pos, 18.0, col * Color(1,1,1,0.35))
	# Subtle ring outline
	draw_arc(Vector2(cx, cy), orb_r, 0, TAU, 64, Color(1,1,1,0.06), 2.0)

func _build_ui() -> void:
	var sz := get_viewport_rect().size
	var cx := sz.x * 0.5

	# Title
	var title := Label.new()
	title.text = "SIMON"
	title.add_theme_font_size_override("font_size", 96)
	title.add_theme_color_override("font_color", GOLD)
	title.add_theme_color_override("font_shadow_color", Color(0,0,0,0.6))
	title.add_theme_constant_override("shadow_offset_x", 4)
	title.add_theme_constant_override("shadow_offset_y", 4)
	title.position = Vector2(cx - 180, sz.y * 0.12)
	title.size = Vector2(360, 120)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	var sub := Label.new()
	sub.text = "Memory Challenge"
	sub.add_theme_font_size_override("font_size", 22)
	sub.add_theme_color_override("font_color", Color(0.7, 0.7, 1.0))
	sub.position = Vector2(cx - 160, sz.y * 0.28)
	sub.size = Vector2(320, 40)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sub)

	_add_btn("START GAME", Vector2(cx - 160, sz.y * 0.45), Color(0.15,0.6,0.95), _on_start)
	_add_btn("HOW TO PLAY", Vector2(cx - 160, sz.y * 0.62), Color(0.25,0.25,0.55), _on_how)

func _add_btn(txt: String, pos: Vector2, col: Color, cb: Callable) -> void:
	var btn := Button.new()
	btn.text = txt
	btn.position = pos
	btn.size = Vector2(320, 64)
	btn.add_theme_font_size_override("font_size", 24)
	var sn := StyleBoxFlat.new()
	sn.bg_color = col
	sn.corner_radius_top_left = 14
	sn.corner_radius_top_right = 14
	sn.corner_radius_bottom_left = 14
	sn.corner_radius_bottom_right = 14
	btn.add_theme_stylebox_override("normal", sn)
	var sh := sn.duplicate() as StyleBoxFlat
	sh.bg_color = col.lightened(0.2)
	btn.add_theme_stylebox_override("hover", sh)
	var sp := sn.duplicate() as StyleBoxFlat
	sp.bg_color = col.darkened(0.2)
	btn.add_theme_stylebox_override("pressed", sp)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.pressed.connect(cb)
	add_child(btn)

func _on_start() -> void:
	AudioManager.stop_bg_music()
	game_manager.show_difficulty()

func _on_how() -> void:
	game_manager.show_how_to_play()
