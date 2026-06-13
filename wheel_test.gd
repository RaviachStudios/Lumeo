extends Control

# Full-screen preview of the game look: dark gradient background with a radial
# glow + vignette, large centered 3D Simon wheel, minimal top UI (level badge +
# Quit), and a bottom message pill. Run this scene directly (F6).
# (Segment count can be switched with keys 4/5/6 for testing - no on-screen UI.)

# Deeper, slightly desaturated colors read as premium (not neon/cartoon).
const COLORS := [
	Color(0.74, 0.13, 0.13),  # deep red
	Color(0.13, 0.56, 0.24),  # deep green
	Color(0.13, 0.30, 0.74),  # deep blue
	Color(0.82, 0.64, 0.10),  # amber
	Color(0.82, 0.40, 0.10),  # burnt orange
	Color(0.62, 0.18, 0.46),  # deep magenta
]

const BG_SHADER := "
shader_type canvas_item;
uniform float aspect = 1.7;
void fragment() {
	vec3 top = vec3(0.035, 0.043, 0.14);
	vec3 bot = vec3(0.09, 0.055, 0.22);
	vec3 col = mix(top, bot, UV.y);
	vec2 p = UV - vec2(0.5);
	p.x *= aspect;
	float d = length(p);
	col += vec3(0.18, 0.28, 0.6) * smoothstep(0.55, 0.0, d) * 0.30;
	col *= mix(0.84, 1.0, smoothstep(1.05, 0.4, d));
	COLOR = vec4(col, 1.0);
}
"

var _wheel: SimonWheel
var _bg_mat: ShaderMaterial
var _badge: Panel
var _quit: Button
var _pill: Panel
var _count := 5
var _cycle_idx := 0

# Cycle the displayed level through these to check numeral fit/auto-sizing.
const TEST_LEVELS := [1, 7, 10, 42, 99, 100, 250, 1000, 10000]
var _lvl_idx := 0

func _ready() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = BG_SHADER
	_bg_mat = ShaderMaterial.new()
	_bg_mat.shader = sh
	bg.material = _bg_mat
	add_child(bg)

	_wheel = SimonWheel.new()
	add_child(_wheel)

	_badge = _make_pill("Level: 🍃 1", 22)
	add_child(_badge)

	_quit = Button.new()
	_quit.text = "Quit"
	_quit.add_theme_font_size_override("font_size", 20)
	_style_button(_quit, Color(0.75, 0.12, 0.12))
	add_child(_quit)

	_pill = _make_pill("Watch carefully...", 22)
	add_child(_pill)

	_layout()
	get_viewport().size_changed.connect(_layout)
	_wheel.configure(_count, COLORS)
	_wheel.set_level(1)

	var t := Timer.new()
	t.wait_time = 0.7
	t.autostart = true
	t.timeout.connect(_cycle)
	add_child(t)

	# Step the level number through TEST_LEVELS so numeral sizing can be eyeballed.
	var lt := Timer.new()
	lt.wait_time = 1.6
	lt.autostart = true
	lt.timeout.connect(_next_level)
	add_child(lt)

func _next_level() -> void:
	var lvl: int = TEST_LEVELS[_lvl_idx % TEST_LEVELS.size()]
	_lvl_idx += 1
	_wheel.set_level(lvl)
	var lbl := _badge.get_child(0) as Label
	if lbl:
		lbl.text = "Level: 🍃 %d" % lvl

func _layout() -> void:
	var vp := get_viewport_rect().size
	if _bg_mat:
		_bg_mat.set_shader_parameter("aspect", vp.x / maxf(1.0, vp.y))
	var s: float = vp.y * 0.92          # wheel ~ full screen height, centered
	_wheel.size = Vector2(s, s)
	_wheel.position = (vp - _wheel.size) * 0.5
	_badge.position = Vector2(24, 20)
	_quit.size = Vector2(110, 46)
	_quit.position = Vector2(vp.x - _quit.size.x - 24, 20)
	_pill.position = Vector2((vp.x - _pill.size.x) * 0.5, vp.y - 64)

# A dark rounded pill with centered white label; sizes itself to the text.
func _make_pill(text: String, font_size: int) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.14, 0.85)
	sb.set_corner_radius_all(22)
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.set_border_width_all(1)
	sb.content_margin_left = 18; sb.content_margin_right = 18
	sb.content_margin_top = 8; sb.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.add_child(lbl)
	var w := ThemeDB.fallback_font.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 44.0
	p.size = Vector2(w, 44)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

func _style_button(btn: Button, col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(14)
	for s in ["normal", "hover", "pressed"]:
		var b := sb.duplicate() as StyleBoxFlat
		if s == "hover": b.bg_color = col.lightened(0.12)
		elif s == "pressed": b.bg_color = col.darkened(0.15)
		btn.add_theme_stylebox_override(s, b)
	btn.add_theme_color_override("font_color", Color.WHITE)

func _set_count(n: int) -> void:
	_count = n
	_cycle_idx = 0
	_wheel.configure(_count, COLORS)
	_wheel.set_level(1)

func _cycle() -> void:
	var idx := _cycle_idx % _count
	_wheel.set_lit(idx, true)
	get_tree().create_timer(0.4).timeout.connect(func() -> void: _wheel.set_lit(idx, false))
	_cycle_idx += 1

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_4: _set_count(4)
			KEY_5: _set_count(5)
			KEY_6: _set_count(6)

func _gui_input(event: InputEvent) -> void:
	var pos := Vector2(-1, -1)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
	elif event is InputEventScreenTouch and event.pressed:
		pos = event.position
	if pos.x < 0:
		return
	var idx := _wheel.segment_at_point(pos - _wheel.position)
	if idx >= 0:
		_wheel.set_lit(idx, true)
		_wheel.set_press(idx, 1.0)
		get_tree().create_timer(0.25).timeout.connect(func() -> void:
			_wheel.set_lit(idx, false)
			_wheel.set_press(idx, 0.0))
