extends Control

# Premium "How To Play" screen, matching the main menu: deep-space shader
# background, a slowly rotating orbit with pulsing colored orbs, a glowing
# header with decorative side lines, and four dark navy-glass step cards
# (numbered glowing icons + accent title + description) that gently float.
# Built from Godot nodes + shaders + tweens (no static images).

var game_manager: Node

const ORB_COLORS := [
	Color(1.00, 0.82, 0.29),  # yellow
	Color(0.90, 0.28, 0.30),  # red
	Color(0.55, 0.36, 0.96),  # purple
	Color(0.18, 0.78, 0.39),  # green
	Color(0.23, 0.51, 0.96),  # blue
]

const CARD_W := 560.0
const CARD_H := 112.0
const CARD_GAP := 20.0
const CARD_PAD := 20.0

# Four instructional steps: number, accent color, title, description.
const STEPS := [
	{"n": "1", "accent": Color(0.23, 0.51, 0.96), "title": "Watch",
		"desc": "Simon lights up a sequence of colored buttons. Watch the order closely."},
	{"n": "2", "accent": Color(0.18, 0.78, 0.39), "title": "Repeat",
		"desc": "Tap the buttons in the exact same order. One wrong press ends the run."},
	{"n": "3", "accent": Color(0.55, 0.36, 0.96), "title": "Level Up",
		"desc": "Each round adds one more step. See how far your memory takes you."},
	{"n": "4", "accent": Color(1.00, 0.75, 0.22), "title": "Replay",
		"desc": "Stuck? Watch a short ad to replay the sequence and keep going."},
]

const BG_SHADER := "
shader_type canvas_item;
uniform float aspect = 0.5;
void fragment() {
	vec2 uv = UV;
	vec3 top = vec3(0.012, 0.020, 0.070);
	vec3 mid = vec3(0.018, 0.035, 0.110);
	vec3 bot = vec3(0.045, 0.030, 0.105);
	vec3 col = mix(top, mid, clamp(uv.y / 0.5, 0.0, 1.0));
	col = mix(col, bot, clamp((uv.y - 0.5) / 0.5, 0.0, 1.0));

	col += vec3(0.10, 0.22, 0.58) * smoothstep(0.5, 0.0, distance(uv, vec2(0.0, 0.45))) * 0.30;
	col += vec3(0.55, 0.12, 0.22) * smoothstep(0.5, 0.0, distance(uv, vec2(1.0, 0.50))) * 0.22;

	vec2 p = (uv - vec2(0.5)) * vec2(aspect, 1.0);
	float breathe = 0.85 + 0.15 * sin(TIME * 0.6);
	col += vec3(0.10, 0.16, 0.42) * smoothstep(0.55, 0.0, length(p - vec2(0.0, -0.05))) * 0.20 * breathe;

	col *= mix(0.6, 1.0, smoothstep(1.1, 0.25, length(p)));
	COLOR = vec4(col, 1.0);
}
"

# Dark navy-glass card face (gradient + top highlight + blue rim + inner glow +
# soft drop shadow), drawn on a ColorRect padded out so the shadow has room.
const CARD_SHADER := "
shader_type canvas_item;
uniform vec2 rect_size = vec2(600.0, 152.0);
uniform float pad = 20.0;
uniform float radius = 32.0;
uniform vec3 top_col = vec3(0.118, 0.153, 0.369);
uniform vec3 bot_col = vec3(0.078, 0.102, 0.259);
float sdf_round_box(vec2 pp, vec2 b, float r) {
	vec2 q = abs(pp) - b + vec2(r);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}
void fragment() {
	vec2 px = UV * rect_size;
	vec2 p = px - rect_size * 0.5;
	vec2 hb = (rect_size - vec2(pad * 2.0)) * 0.5;
	float d = sdf_round_box(p, hb, radius);
	float body = smoothstep(1.0, -1.0, d);

	float sd = sdf_round_box(p - vec2(0.0, 7.0), hb, radius);
	float shadow = smoothstep(pad, 0.0, sd) * 0.45;

	float ty = clamp((px.y - pad) / (rect_size.y - pad * 2.0), 0.0, 1.0);
	vec3 base = mix(top_col, bot_col, ty);
	base += vec3(0.55, 0.65, 0.95) * smoothstep(0.16, 0.0, ty) * 0.10;     // top highlight
	base += vec3(0.35, 0.55, 1.0) * smoothstep(-7.0, -0.5, d) * 0.16;      // blue rim
	base += vec3(0.20, 0.35, 0.80) * smoothstep(120.0, 0.0, length(p)) * 0.05;  // inner glow

	float a = max(shadow, body);
	vec3 rgb = mix(vec3(0.0, 0.01, 0.04), base, body);
	COLOR = vec4(rgb, a);
}
"

var _bg: ColorRect
var _bg_mat: ShaderMaterial
var _orbit: Node2D
var _ring_glow: Line2D
var _ring_line: Line2D
var _orbs: Array[Node2D] = []
var _orb_tex: Texture2D
var _card_mat: ShaderMaterial
var _header: Control
var _line_l: ColorRect
var _line_r: ColorRect
var _cards: Array[Control] = []
var _back: Button

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_orb_tex = _make_radial_texture()
	_build_background()
	_build_orbit()
	_build_header()
	_build_cards()
	_build_back()
	_layout()
	get_viewport().size_changed.connect(_layout)
	_start_animations()

# ---------------- background ----------------

func _build_background() -> void:
	# Screens live under a CanvasLayer (no size), so size the bg in _layout().
	_bg = ColorRect.new()
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.color = Color(0.02, 0.03, 0.09)
	var sh := Shader.new()
	sh.code = BG_SHADER
	_bg_mat = ShaderMaterial.new()
	_bg_mat.shader = sh
	_bg.material = _bg_mat
	add_child(_bg)

# ---------------- orbit + orbs ----------------

func _build_orbit() -> void:
	_orbit = Node2D.new()
	add_child(_orbit)
	_ring_glow = _make_ring(7.0, Color(0.45, 0.42, 1.0, 0.08))
	_orbit.add_child(_ring_glow)
	_ring_line = _make_ring(2.0, Color(0.62, 0.60, 1.0, 0.25))
	_orbit.add_child(_ring_line)
	_orbs.clear()
	for i in ORB_COLORS.size():
		var orb := _make_orb(ORB_COLORS[i])
		_orbit.add_child(orb)
		_orbs.append(orb)

func _make_ring(w: float, col: Color) -> Line2D:
	var l := Line2D.new()
	l.width = w
	l.default_color = col
	l.antialiased = true
	l.joint_mode = Line2D.LINE_JOINT_ROUND
	return l

func _make_orb(col: Color) -> Node2D:
	var orb := Node2D.new()
	var halo := Sprite2D.new()
	halo.texture = _orb_tex
	halo.modulate = Color(col.r, col.g, col.b, 0.45)
	halo.scale = Vector2.ONE * (72.0 / 128.0)
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	halo.material = add_mat
	orb.add_child(halo)
	var core := Sprite2D.new()
	core.texture = _orb_tex
	core.modulate = col.lightened(0.25)
	core.scale = Vector2.ONE * (26.0 / 128.0)
	orb.add_child(core)
	return orb

func _make_radial_texture() -> Texture2D:
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := Vector2(s, s) * 0.5
	for y in s:
		for x in s:
			var d := Vector2(x, y).distance_to(c) / (s * 0.5)
			img.set_pixel(x, y, Color(1, 1, 1, pow(clampf(1.0 - d, 0.0, 1.0), 2.0)))
	return ImageTexture.create_from_image(img)

# ---------------- header ----------------

func _build_header() -> void:
	_header = Control.new()
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.custom_minimum_size = Vector2(680, 130)
	_header.size = Vector2(680, 130)
	add_child(_header)

	var title := Label.new()
	title.text = "HOW TO PLAY"
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_color_override("font_shadow_color", Color(0.20, 0.40, 1.0, 0.45))  # blue glow
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 4)
	title.add_theme_constant_override("shadow_outline_size", 9)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.add_child(title)

	var sub := Label.new()
	sub.text = "Master the sequence"
	sub.add_theme_font_size_override("font_size", 20)
	sub.add_theme_color_override("font_color", Color(0.74, 0.82, 1.0, 0.8))   # light gray-blue 80%
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.set_anchors_preset(Control.PRESET_FULL_RECT)
	sub.offset_top = 80
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.add_child(sub)

	# two soft blue-purple decorative lines flanking the subtitle
	_line_l = _make_deco_line()
	add_child(_line_l)
	_line_r = _make_deco_line()
	add_child(_line_r)

func _make_deco_line() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0.45, 0.5, 1.0, 0.45)
	r.size = Vector2(64, 2)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

# ---------------- cards ----------------

func _build_cards() -> void:
	var sh := Shader.new()
	sh.code = CARD_SHADER
	_card_mat = ShaderMaterial.new()
	_card_mat.shader = sh
	_card_mat.set_shader_parameter("rect_size", Vector2(CARD_W + CARD_PAD * 2.0, CARD_H + CARD_PAD * 2.0))
	_card_mat.set_shader_parameter("pad", CARD_PAD)
	_card_mat.set_shader_parameter("radius", 32.0)
	_card_mat.set_shader_parameter("top_col", Vector3(0.118, 0.153, 0.369))
	_card_mat.set_shader_parameter("bot_col", Vector3(0.078, 0.102, 0.259))

	_cards.clear()
	for step in STEPS:
		_cards.append(_make_card(step))

# A dark-glass card: shader face + numbered glowing accent icon + accent title +
# light description. Wrapped so layout (wrapper) and float (inner) don't fight.
func _make_card(step: Dictionary) -> Control:
	var accent: Color = step["accent"]
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(CARD_W, CARD_H)
	wrap.size = Vector2(CARD_W, CARD_H)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wrap)

	var card := Control.new()
	card.size = Vector2(CARD_W, CARD_H)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(card)

	var face := ColorRect.new()
	face.material = _card_mat
	face.position = Vector2(-CARD_PAD, -CARD_PAD)
	face.size = Vector2(CARD_W + CARD_PAD * 2.0, CARD_H + CARD_PAD * 2.0)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(face)

	# circular numbered icon, illuminated from within with the accent color
	var icon := Panel.new()
	var d := 60.0
	icon.size = Vector2(d, d)
	icon.position = Vector2(22, (CARD_H - d) * 0.5)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := StyleBoxFlat.new()
	var icbg := accent.darkened(0.15)
	icbg.a = 0.92
	ic.bg_color = icbg
	ic.set_corner_radius_all(int(d * 0.5))
	ic.border_color = accent.lightened(0.35)
	ic.set_border_width_all(2)
	ic.shadow_color = Color(accent.r, accent.g, accent.b, 0.55)
	ic.shadow_size = 14
	icon.add_theme_stylebox_override("panel", ic)
	card.add_child(icon)

	var num := Label.new()
	num.text = step["n"]
	num.add_theme_font_size_override("font_size", 28)
	num.add_theme_color_override("font_color", Color.WHITE)
	num.set_anchors_preset(Control.PRESET_FULL_RECT)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.add_child(num)

	var tx := 22.0 + d + 20.0
	var title := Label.new()
	title.text = step["title"]
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", accent.lightened(0.15))
	title.position = Vector2(tx, 18)
	title.size = Vector2(CARD_W - tx - 24, 32)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(title)

	var desc := Label.new()
	desc.text = step["desc"]
	desc.add_theme_font_size_override("font_size", 16)
	desc.add_theme_color_override("font_color", Color(0.74, 0.82, 1.0, 0.8))
	desc.position = Vector2(tx, 54)
	desc.size = Vector2(CARD_W - tx - 24, CARD_H - 60)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(desc)
	return wrap

func _build_back() -> void:
	_back = Button.new()
	_back.text = "← Back"
	_back.size = Vector2(150, 48)
	_back.focus_mode = Control.FOCUS_NONE
	_back.add_theme_font_size_override("font_size", 18)
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.10, 0.13, 0.30, 0.9)
	s.set_corner_radius_all(24)
	s.border_color = Color(0.35, 0.5, 1.0, 0.4)
	s.set_border_width_all(1)
	_back.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = Color(0.16, 0.2, 0.42, 0.95)
	_back.add_theme_stylebox_override("hover", sh)
	var sp := s.duplicate() as StyleBoxFlat
	sp.bg_color = Color(0.08, 0.10, 0.24, 0.95)
	_back.add_theme_stylebox_override("pressed", sp)
	_back.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	_back.pressed.connect(func() -> void: game_manager.show_home())
	add_child(_back)

# ---------------- layout ----------------

func _layout() -> void:
	var sz := get_viewport_rect().size
	var cx := sz.x * 0.5
	if _bg:
		_bg.position = Vector2.ZERO
		_bg.size = sz
	if _bg_mat:
		_bg_mat.set_shader_parameter("aspect", sz.x / maxf(1.0, sz.y))

	if _orbit:
		var r := sz.x * 0.42
		_orbit.position = Vector2(cx, sz.y * 0.5)
		_rebuild_ring(r)
		for i in _orbs.size():
			var a: float = -PI * 0.5 + i * TAU / _orbs.size()
			_orbs[i].position = Vector2(cos(a), sin(a)) * r

	# header (centered, top)
	var top := sz.y * 0.06
	if _header:
		_header.position = Vector2(cx - _header.size.x * 0.5, top)
	if _line_l and _line_r:
		var ly := top + 90.0
		_line_l.position = Vector2(cx - 200, ly)
		_line_r.position = Vector2(cx + 200 - _line_r.size.x, ly)

	# card stack, centered horizontally, below the header
	var total := STEPS.size() * CARD_H + (STEPS.size() - 1) * CARD_GAP
	var start_y := maxf(top + 150.0, sz.y * 0.52 - total * 0.5)
	for i in _cards.size():
		_cards[i].position = Vector2(cx - CARD_W * 0.5, start_y + i * (CARD_H + CARD_GAP))

	if _back:
		_back.position = Vector2(cx - _back.size.x * 0.5, minf(sz.y - 72.0, start_y + total + 26.0))

func _rebuild_ring(r: float) -> void:
	var pts := PackedVector2Array()
	var n := 72
	for i in n + 1:
		var a: float = TAU * float(i) / n
		pts.append(Vector2(cos(a), sin(a)) * r)
	_ring_glow.points = pts
	_ring_line.points = pts

# ---------------- animations ----------------

func _start_animations() -> void:
	var rot := create_tween().set_loops()
	rot.tween_property(_orbit, "rotation", TAU, 25.0).from(0.0).set_trans(Tween.TRANS_LINEAR)

	for i in _orbs.size():
		var dur := 0.9 + i * 0.06
		var pulse := create_tween().set_loops()
		pulse.tween_property(_orbs[i], "scale", Vector2.ONE * 1.05, dur) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		pulse.tween_property(_orbs[i], "scale", Vector2.ONE, dur) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	for i in _cards.size():
		var card := _cards[i].get_child(0)
		var dur := 2.4 + i * 0.35
		var fl := create_tween().set_loops()
		fl.tween_property(card, "position:y", -2.0, dur) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		fl.tween_property(card, "position:y", 0.0, dur) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
