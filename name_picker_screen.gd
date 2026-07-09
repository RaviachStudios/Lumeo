extends Control

# Name picker — shown once after sign-in so the player chooses how they appear on
# the leaderboards. Same visual language as the home / leaderboard screens: a deep
# space shader background, a soft orbiting glow, and a centered glassmorphism card
# carrying a glowing star badge, the title, the input field and the confirm button.
#
# The whole card lifts up automatically when the on-screen keyboard opens so the
# input field + button are never hidden behind it (the old fixed layout placed the
# field low enough that the keyboard covered it). All art is procedural — no PNGs.

var game_manager: Node

const GOLD := Color(1.0, 0.85, 0.2)
const ACCENT := Color(0.55, 0.40, 1.00)

const CARD_W := 470.0
const CARD_H := 234.0

const BG_SHADER := "
shader_type canvas_item;
uniform float aspect = 0.5;
float star(vec2 uv, vec2 c, float r) { return smoothstep(r, 0.0, distance(uv, c)); }
void fragment() {
	vec2 uv = UV;
	vec3 top = vec3(0.008, 0.020, 0.102);
	vec3 bot = vec3(0.071, 0.000, 0.169);
	vec3 col = mix(top, bot, uv.y);
	vec2 p = (uv - vec2(0.5)) * vec2(aspect, 1.0);
	float neb = smoothstep(0.5, 0.0, length(p - vec2(-0.34, -0.20)));
	neb += smoothstep(0.55, 0.0, length(p - vec2(0.38, 0.10)));
	col += vec3(0.10, 0.10, 0.30) * neb * 0.10;
	col += vec3(0.10, 0.20, 0.55) * smoothstep(0.5, 0.0, distance(uv, vec2(0.0, 0.4))) * 0.22;
	col += vec3(0.45, 0.12, 0.40) * smoothstep(0.5, 0.0, distance(uv, vec2(1.0, 0.6))) * 0.18;
	float breathe = 0.85 + 0.15 * sin(TIME * 0.6);
	col += vec3(0.12, 0.14, 0.42) * smoothstep(0.55, 0.0, length(p)) * 0.16 * breathe;
	col += vec3(0.7, 0.8, 1.0) * star(uv, vec2(0.16, 0.22), 0.010) * 0.6;
	col += vec3(0.7, 0.8, 1.0) * star(uv, vec2(0.84, 0.18), 0.008) * 0.5;
	col += vec3(0.9, 0.8, 1.0) * star(uv, vec2(0.72, 0.78), 0.009) * 0.5;
	col += vec3(0.7, 0.8, 1.0) * star(uv, vec2(0.24, 0.82), 0.007) * 0.45;
	col += vec3(0.8, 0.85, 1.0) * star(uv, vec2(0.50, 0.10), 0.007) * 0.4;
	col *= mix(0.62, 1.0, smoothstep(1.1, 0.25, length(p)));
	COLOR = vec4(col, 1.0);
}
"

var _bg: ColorRect
var _bg_mat: ShaderMaterial
var _orb_tex: Texture2D
var _card: Control
var _name_input: LineEdit
var _error_label: Label
var _base_card_y := 0.0      # the card's resting Y (no keyboard)
var _card_shift := 0.0       # current smoothed upward shift

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_orb_tex = _make_radial_texture()
	_build_background()
	_build_card()
	_layout()
	get_viewport().size_changed.connect(_layout)

# ---------------- background ----------------

func _build_background() -> void:
	# Skip when a shop theme is equipped — BackgroundManager fills globally.
	if BackgroundManager.is_themed():
		return
	_bg = ColorRect.new()
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.color = Color(0.008, 0.020, 0.10)
	var sh := Shader.new()
	sh.code = BG_SHADER
	_bg_mat = ShaderMaterial.new()
	_bg_mat.shader = sh
	_bg.material = _bg_mat
	add_child(_bg)

func _make_radial_texture() -> Texture2D:
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := Vector2(s, s) * 0.5
	for y in s:
		for x in s:
			var d := Vector2(x, y).distance_to(c) / (s * 0.5)
			img.set_pixel(x, y, Color(1, 1, 1, pow(clampf(1.0 - d, 0.0, 1.0), 2.0)))
	return ImageTexture.create_from_image(img)

# ---------------- glass card ----------------

func _build_card() -> void:
	_card = Control.new()
	_card.custom_minimum_size = Vector2(CARD_W, CARD_H)
	_card.size = Vector2(CARD_W, CARD_H)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card)

	# Glass panel: translucent deep-navy fill, rounded, purple rim + soft glow.
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.0, 0.0, 0.0, 0.86)
	ps.set_corner_radius_all(30)
	ps.border_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.45)
	ps.set_border_width_all(1)
	ps.shadow_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.22)
	ps.shadow_size = 26
	panel.add_theme_stylebox_override("panel", ps)
	_card.add_child(panel)

	# Glowing star badge + title share a tight header so the input field sits high.
	var badge := _make_star(18.0, GOLD)
	badge.position = Vector2(CARD_W * 0.5, 38)
	_card.add_child(badge)

	var title := Label.new()
	title.text = "Choose Your Name"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_color_override("font_outline_color", Color.WHITE)
	title.add_theme_constant_override("outline_size", 1)     # faux-bold
	title.add_theme_color_override("font_shadow_color", Color(0.20, 0.40, 1.0, 0.40))
	title.add_theme_constant_override("shadow_offset_y", 4)
	title.add_theme_constant_override("shadow_outline_size", 9)
	title.position = Vector2(0, 60)
	title.size = Vector2(CARD_W, 46)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(title)

	var sub := Label.new()
	sub.text = "This is how you'll appear on the leaderboards"
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", Color(0.70, 0.74, 1.0))
	sub.position = Vector2(20, 106)
	sub.size = Vector2(CARD_W - 40, 26)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(sub)

	# Field + CONFIRM share one row so the card stays short. The row is centered
	# with matching 10px margins; the button height matches the field.
	var row_y := 138.0
	var row_h := 56.0
	var btn_w := 150.0
	var gap := 14.0
	var input_w := CARD_W - 20.0 - btn_w - gap

	_name_input = LineEdit.new()
	_name_input.placeholder_text = "Enter your name"
	_name_input.text = FirebaseManager.name_suggestion()
	_name_input.max_length = 20
	_name_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_input.position = Vector2(10, row_y)
	_name_input.size = Vector2(input_w, row_h)
	_name_input.add_theme_font_size_override("font_size", 24)
	var input_style := StyleBoxFlat.new()
	input_style.bg_color = Color(0.06, 0.08, 0.20, 0.85)
	input_style.set_corner_radius_all(14)
	input_style.border_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.55)
	input_style.set_border_width_all(2)
	input_style.content_margin_left = 16
	input_style.content_margin_right = 16
	_name_input.add_theme_stylebox_override("normal", input_style)
	var focus_style := input_style.duplicate() as StyleBoxFlat
	focus_style.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.9)
	focus_style.shadow_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.28)
	focus_style.shadow_size = 8
	_name_input.add_theme_stylebox_override("focus", focus_style)
	_name_input.add_theme_color_override("font_color", Color.WHITE)
	_name_input.add_theme_color_override("caret_color", GOLD)
	_name_input.add_theme_color_override("font_placeholder_color", Color(0.5, 0.5, 0.7))
	_name_input.text_submitted.connect(func(_t: String) -> void: _on_confirm())
	_card.add_child(_name_input)

	_add_btn("CONFIRM", Vector2(10 + input_w + gap, row_y),
		Vector2(btn_w, row_h), Color(0.15, 0.6, 0.95), _on_confirm)

	_error_label = Label.new()
	_error_label.add_theme_font_size_override("font_size", 15)
	_error_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
	_error_label.position = Vector2(20, row_y + row_h + 8.0)
	_error_label.size = Vector2(CARD_W - 40, 22)
	_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(_error_label)

# A glowing 4-point star badge (cup-style bloom + diamond cross).
func _make_star(s: float, col: Color) -> Node2D:
	var n := Node2D.new()
	var halo := Sprite2D.new()
	halo.texture = _orb_tex
	halo.modulate = Color(col.r, col.g, col.b, 0.5)
	halo.scale = Vector2.ONE * (s * 3.0 / 128.0)
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	halo.material = add_mat
	n.add_child(halo)
	var star := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 8:
		var a: float = TAU * float(i) / 8.0 - PI * 0.5
		var r: float = s if i % 2 == 0 else s * 0.42
		pts.append(Vector2(cos(a) * r, sin(a) * r))
	star.polygon = pts
	star.color = col
	n.add_child(star)
	return n

func _add_btn(txt: String, pos: Vector2, size: Vector2, col: Color, cb: Callable) -> void:
	var btn := Button.new()
	btn.text = txt
	btn.position = pos
	btn.size = size
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_outline_color", col.darkened(0.45))
	btn.add_theme_constant_override("outline_size", 1)     # faux-bold, reads on the pill
	var sn := StyleBoxFlat.new()
	sn.bg_color = col
	sn.set_corner_radius_all(14)
	sn.shadow_color = Color(col.r, col.g, col.b, 0.45)
	sn.shadow_size = 12
	btn.add_theme_stylebox_override("normal", sn)
	var sh := sn.duplicate() as StyleBoxFlat
	sh.bg_color = col.lightened(0.2)
	btn.add_theme_stylebox_override("hover", sh)
	var sp := sn.duplicate() as StyleBoxFlat
	sp.bg_color = col.darkened(0.2)
	btn.add_theme_stylebox_override("pressed", sp)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.pressed.connect(cb)
	_card.add_child(btn)

# ---------------- layout + keyboard handling ----------------

func _layout() -> void:
	var sz := get_viewport_rect().size
	if _bg:
		_bg.size = sz
		_bg.position = Vector2.ZERO
		if _bg_mat:
			_bg_mat.set_shader_parameter("aspect", sz.x / maxf(sz.y, 1.0))
	# Rest a touch above center so the card feels anchored, not floating low.
	_base_card_y = sz.y * 0.5 - CARD_H * 0.5 - sz.y * 0.04
	_card.position = Vector2((sz.x - CARD_W) * 0.5, _base_card_y - _card_shift)

const TOP_MARGIN := 10.0     # the card top never lifts past this many px from the top

func _process(_delta: float) -> void:
	if _card == null:
		return
	# Lift the card so its bottom edge clears the on-screen keyboard, but never so
	# far that its top runs off the screen — clamp the lift to the available space.
	var target := 0.0
	var kb_h := float(DisplayServer.virtual_keyboard_get_height())
	if kb_h > 0.0 and _name_input.has_focus():
		var vsz := get_viewport_rect().size
		# The keyboard height is reported in real device pixels; the card lives in
		# the stretched design space, so convert it before comparing.
		var win_h := float(get_window().size.y)
		var kb_design := kb_h * (vsz.y / maxf(win_h, 1.0))
		var keyboard_top := vsz.y - kb_design
		var card_bottom := _base_card_y + CARD_H
		var overlap := card_bottom - (keyboard_top - 16.0)
		# Clamp so the card top stays at least TOP_MARGIN below the screen top.
		var max_shift := maxf(_base_card_y - TOP_MARGIN, 0.0)
		target = clampf(overlap, 0.0, max_shift)
	_card_shift = lerpf(_card_shift, target, clampf(_delta * 12.0, 0.0, 1.0))
	_card.position.y = _base_card_y - _card_shift

func _on_confirm() -> void:
	var name := _name_input.text.strip_edges()
	if name.length() < 2:
		_error_label.text = "Name must be at least 2 characters."
		return
	FirebaseManager.set_display_name(name)
	game_manager.show_home()
