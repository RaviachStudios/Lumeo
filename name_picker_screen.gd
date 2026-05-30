extends Control

var game_manager: Node

const BG_TOP := Color(0.04, 0.04, 0.18)
const BG_BOT := Color(0.08, 0.03, 0.25)
const GOLD := Color(1.0, 0.85, 0.2)

var _name_input: LineEdit
var _error_label: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()

func _draw() -> void:
	var sz := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, sz), BG_TOP)
	for y in range(0, int(sz.y), 4):
		var t := float(y) / sz.y
		draw_line(Vector2(0, y), Vector2(sz.x, y), BG_TOP.lerp(BG_BOT, t), 4.0)

func _build_ui() -> void:
	var sz := get_viewport_rect().size
	var cx := sz.x * 0.5

	var title := Label.new()
	title.text = "Choose Your Name"
	title.add_theme_font_size_override("font_size", 54)
	title.add_theme_color_override("font_color", GOLD)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 3)
	title.position = Vector2(cx - 280, sz.y * 0.12)
	title.size = Vector2(560, 80)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	var sub := Label.new()
	sub.text = "This is how you'll appear on leaderboards"
	sub.add_theme_font_size_override("font_size", 20)
	sub.add_theme_color_override("font_color", Color(0.7, 0.7, 1.0))
	sub.position = Vector2(cx - 260, sz.y * 0.32)
	sub.size = Vector2(520, 36)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sub)

	_name_input = LineEdit.new()
	_name_input.placeholder_text = "Enter your name"
	_name_input.text = FirebaseManager.name_suggestion()
	_name_input.max_length = 20
	_name_input.position = Vector2(cx - 180, sz.y * 0.44)
	_name_input.size = Vector2(360, 58)
	_name_input.add_theme_font_size_override("font_size", 24)
	var input_style := StyleBoxFlat.new()
	input_style.bg_color = Color(0.12, 0.10, 0.28)
	input_style.border_color = Color(0.4, 0.35, 0.8)
	input_style.border_width_bottom = 2
	input_style.border_width_top = 2
	input_style.border_width_left = 2
	input_style.border_width_right = 2
	input_style.corner_radius_top_left = 10
	input_style.corner_radius_top_right = 10
	input_style.corner_radius_bottom_left = 10
	input_style.corner_radius_bottom_right = 10
	_name_input.add_theme_stylebox_override("normal", input_style)
	_name_input.add_theme_color_override("font_color", Color.WHITE)
	_name_input.add_theme_color_override("font_placeholder_color", Color(0.5, 0.5, 0.7))
	add_child(_name_input)

	_error_label = Label.new()
	_error_label.add_theme_font_size_override("font_size", 18)
	_error_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	_error_label.position = Vector2(cx - 220, sz.y * 0.59)
	_error_label.size = Vector2(440, 32)
	_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_error_label)

	_add_btn("CONFIRM", Vector2(cx - 160, sz.y * 0.67), Color(0.15, 0.6, 0.95), _on_confirm)

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

func _on_confirm() -> void:
	var name := _name_input.text.strip_edges()
	if name.length() < 2:
		_error_label.text = "Name must be at least 2 characters."
		return
	FirebaseManager.set_display_name(name)
	game_manager.show_home()
