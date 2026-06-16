extends Control

# Premium "Choose Difficulty" screen, matching the home menu: deep navy->purple
# shader background (nebula + tiny particles + glow + vignette), a slowly
# rotating orbit with five glowing orbs, a glowing header with side-lined
# subtitle, three interactive dark-glass difficulty cards with accent neon
# rims / icons / arrows, and a bottom "Beat your best" card. Nodes + shaders +
# tweens. Selecting a card sets the difficulty and starts the game.

var game_manager: Node

# Orbit orbs: top yellow, right red, bottom-right green, bottom-left purple, left blue.
const ORBS := [
	{"deg": -90.0, "col": Color(0.97, 0.82, 0.29)},  # yellow
	{"deg":   0.0, "col": Color(0.90, 0.28, 0.30)},  # red
	{"deg":  58.0, "col": Color(0.20, 0.72, 0.34)},  # green
	{"deg": 122.0, "col": Color(0.55, 0.36, 0.96)},  # purple
	{"deg": 180.0, "col": Color(0.24, 0.50, 0.95)},  # blue
]

const DIFFS := [
	{"diff": "easy", "title": "EASY", "accent": Color(0.28, 0.82, 0.45), "orb": 2,
		"icon": "leaf"},
	{"diff": "moderate", "title": "MODERATE", "accent": Color(1.00, 0.72, 0.25), "orb": 0,
		"icon": "chart"},
	{"diff": "hard", "title": "HARD", "accent": Color(0.95, 0.32, 0.40), "orb": 1,
		"icon": "flame"},
]

const CARD_W := 540.0
const CARD_H := 88.0          # thinner buttons (was 124) — no description text
const CARD_GAP := 34.0        # wider gap (was 18) so the three options breathe
const CARD_PAD := 20.0

const BG_SHADER := "
shader_type canvas_item;
uniform float aspect = 0.5;
float star(vec2 uv, vec2 c, float r) { return smoothstep(r, 0.0, distance(uv, c)); }
void fragment() {
	vec2 uv = UV;
	vec3 top = vec3(0.008, 0.020, 0.102);   // #02051A
	vec3 bot = vec3(0.078, 0.000, 0.157);   // #140028
	vec3 col = mix(top, bot, uv.y);

	vec2 p = (uv - vec2(0.5)) * vec2(aspect, 1.0);

	// nebula blobs (blue / purple, very low opacity)
	float neb = smoothstep(0.5, 0.0, length(p - vec2(-0.34, -0.20)));
	neb += smoothstep(0.55, 0.0, length(p - vec2(0.38, 0.10)));
	col += vec3(0.10, 0.10, 0.30) * neb * 0.10;

	// soft side glows + breathing radial glow behind the cards
	col += vec3(0.10, 0.20, 0.55) * smoothstep(0.5, 0.0, distance(uv, vec2(0.0, 0.4))) * 0.22;
	col += vec3(0.45, 0.12, 0.40) * smoothstep(0.5, 0.0, distance(uv, vec2(1.0, 0.6))) * 0.18;
	float breathe = 0.85 + 0.15 * sin(TIME * 0.6);
	col += vec3(0.12, 0.14, 0.42) * smoothstep(0.55, 0.0, length(p)) * 0.16 * breathe;

	// a few tiny static glowing particles
	col += vec3(0.7, 0.8, 1.0) * star(uv, vec2(0.16, 0.22), 0.010) * 0.6;
	col += vec3(0.7, 0.8, 1.0) * star(uv, vec2(0.84, 0.18), 0.008) * 0.5;
	col += vec3(0.9, 0.8, 1.0) * star(uv, vec2(0.72, 0.78), 0.009) * 0.5;
	col += vec3(0.7, 0.8, 1.0) * star(uv, vec2(0.24, 0.82), 0.007) * 0.45;
	col += vec3(0.8, 0.85, 1.0) * star(uv, vec2(0.50, 0.10), 0.007) * 0.4;

	col *= mix(0.62, 1.0, smoothstep(1.1, 0.25, length(p)));   // vignette
	COLOR = vec4(col, 1.0);
}
"

# Dark navy-glass card face with a tunable accent rim (rim_col * rim_boost).
const CARD_SHADER := "
shader_type canvas_item;
uniform vec2 rect_size = vec2(580.0, 164.0);
uniform float pad = 20.0;
uniform float radius = 28.0;
uniform vec3 top_col = vec3(0.118, 0.153, 0.369);
uniform vec3 bot_col = vec3(0.078, 0.102, 0.259);
uniform vec3 rim_col = vec3(0.35, 0.55, 1.0);
uniform float rim_boost = 1.0;
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
	base += vec3(0.55, 0.65, 0.95) * smoothstep(0.16, 0.0, ty) * 0.10;       // top highlight
	base += rim_col * smoothstep(-6.0, -0.5, d) * 0.30 * rim_boost;          // accent neon rim
	base += rim_col * smoothstep(150.0, 0.0, length(p)) * 0.05;              // faint inner glow

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
var _header: Control
var _line_l: ColorRect
var _line_r: ColorRect
var _cards: Array[Control] = []     # difficulty card wrappers
var _back: Button
var _selecting := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_orb_tex = _make_radial_texture()
	_build_background()
	_build_orbit()
	_build_header()
	_build_back()
	_build_cards()
	_layout()
	get_viewport().size_changed.connect(_layout)
	_start_animations()
	_intro()

# ---------------- background ----------------

func _build_background() -> void:
	_bg = ColorRect.new()
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.color = Color(0.02, 0.02, 0.10)
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
	_ring_glow = _make_ring(7.0, Color(0.45, 0.42, 1.0, 0.07))
	_orbit.add_child(_ring_glow)
	_ring_line = _make_ring(2.0, Color(0.60, 0.58, 1.0, 0.18))
	_orbit.add_child(_ring_line)
	_orbs.clear()
	for o in ORBS:
		var orb := _make_orb(o["col"])
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
	_header.custom_minimum_size = Vector2(760, 130)
	_header.size = Vector2(760, 130)
	add_child(_header)

	var title := Label.new()
	title.text = "CHOOSE DIFFICULTY"
	title.add_theme_font_size_override("font_size", 50)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_color_override("font_outline_color", Color(1, 1, 1, 1))
	title.add_theme_constant_override("outline_size", 2)
	title.add_theme_color_override("font_shadow_color", Color(0.20, 0.40, 1.0, 0.45))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 4)
	title.add_theme_constant_override("shadow_outline_size", 9)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.add_child(title)

	var sub := Label.new()
	sub.text = "Pick your challenge"
	sub.add_theme_font_size_override("font_size", 20)
	sub.add_theme_color_override("font_color", Color(0.659, 0.714, 1.0))   # #A8B6FF
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.set_anchors_preset(Control.PRESET_FULL_RECT)
	sub.offset_top = 74
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.add_child(sub)

	_line_l = _make_deco_line()
	add_child(_line_l)
	_line_r = _make_deco_line()
	add_child(_line_r)

func _make_deco_line() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0.50, 0.50, 1.0, 0.45)
	r.size = Vector2(54, 2)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

func _glow_dot(d: float, col: Color, center: Vector2) -> Panel:
	var p := Panel.new()
	p.size = Vector2(d, d)
	p.position = center - Vector2(d, d) * 0.5
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.set_corner_radius_all(int(d * 0.5))
	s.shadow_color = Color(col.r, col.g, col.b, 0.7)
	s.shadow_size = 7
	p.add_theme_stylebox_override("panel", s)
	return p

# ---------------- back button ----------------

func _build_back() -> void:
	_back = Button.new()
	_back.text = "← Back"
	_back.size = Vector2(132, 46)
	_back.focus_mode = Control.FOCUS_NONE
	_back.add_theme_font_size_override("font_size", 18)
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.07, 0.10, 0.26, 0.7)         # translucent navy glass
	s.set_corner_radius_all(23)
	s.border_color = Color(0.35, 0.5, 1.0, 0.5)       # thin blue border
	s.set_border_width_all(1)
	s.shadow_color = Color(0.25, 0.4, 1.0, 0.25)      # soft blue glow
	s.shadow_size = 10
	_back.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = Color(0.12, 0.16, 0.36, 0.85)
	_back.add_theme_stylebox_override("hover", sh)
	var sp := s.duplicate() as StyleBoxFlat
	sp.bg_color = Color(0.05, 0.07, 0.20, 0.9)
	_back.add_theme_stylebox_override("pressed", sp)
	_back.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	_back.pressed.connect(func() -> void: game_manager.show_home())
	add_child(_back)

# ---------------- difficulty cards ----------------

func _build_cards() -> void:
	_cards.clear()
	for d in DIFFS:
		_cards.append(_make_card(d))

func _make_card(d: Dictionary) -> Control:
	var accent: Color = d["accent"]
	var rtl := is_layout_rtl()
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(CARD_W, CARD_H)
	wrap.size = Vector2(CARD_W, CARD_H)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wrap)

	var btn := Button.new()
	btn.size = Vector2(CARD_W, CARD_H)
	btn.pivot_offset = Vector2(CARD_W, CARD_H) * 0.5
	btn.focus_mode = Control.FOCUS_NONE
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(st, empty)
	wrap.add_child(btn)

	# per-card glass face with the accent rim
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = CARD_SHADER
	mat.shader = sh
	mat.set_shader_parameter("rect_size", Vector2(CARD_W + CARD_PAD * 2.0, CARD_H + CARD_PAD * 2.0))
	mat.set_shader_parameter("pad", CARD_PAD)
	mat.set_shader_parameter("radius", 26.0)
	mat.set_shader_parameter("top_col", Vector3(0.118, 0.153, 0.369))
	mat.set_shader_parameter("bot_col", Vector3(0.078, 0.102, 0.259))
	mat.set_shader_parameter("rim_col", Vector3(accent.r, accent.g, accent.b))
	mat.set_shader_parameter("rim_boost", 1.0)
	btn.set_meta("mat", mat)
	var face := ColorRect.new()
	face.material = mat
	face.position = Vector2(-CARD_PAD, -CARD_PAD)
	face.size = Vector2(CARD_W + CARD_PAD * 2.0, CARD_H + CARD_PAD * 2.0)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(face)

	# circular icon container, illuminated in the accent color
	var dia := 52.0
	var icon := Panel.new()
	icon.size = Vector2(dia, dia)
	icon.position = Vector2(CARD_W - 22 - dia if rtl else 22, (CARD_H - dia) * 0.5)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := StyleBoxFlat.new()
	var icbg := accent.darkened(0.2)
	icbg.a = 0.28
	ic.bg_color = icbg
	ic.set_corner_radius_all(int(dia * 0.5))
	ic.border_color = accent.lightened(0.2)
	ic.set_border_width_all(2)
	ic.shadow_color = Color(accent.r, accent.g, accent.b, 0.5)
	ic.shadow_size = 14
	icon.add_theme_stylebox_override("panel", ic)
	btn.add_child(icon)
	var sym := _make_icon(d["icon"], dia * 0.36, accent.lightened(0.45))
	sym.position = Vector2(dia * 0.5, dia * 0.5)
	icon.add_child(sym)

	# Title sits centered between the icon (leading edge) and the arrow (trailing
	# edge); sides flip in RTL so the icon stays opposite the chevron.
	var title := Label.new()
	title.text = d["title"]
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", accent.lightened(0.2))
	title.add_theme_color_override("font_outline_color", accent.lightened(0.2))
	title.add_theme_constant_override("outline_size", 1)
	var title_x := 46.0 if rtl else 22.0 + dia + 18.0
	title.position = Vector2(title_x, 0)
	title.size = Vector2(CARD_W - (22.0 + dia + 18.0) - 46.0, CARD_H)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if rtl else HORIZONTAL_ALIGNMENT_LEFT
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(title)

	# Always points right: the card's visible "leading icon → title → arrow" flow
	# does not mirror on RTL devices (Godot's auto-mirror cancels the manual
	# position flip), so a "‹" here would be the only RTL-flipped element and
	# would read as pointing the wrong way against an otherwise LTR-laid card.
	var arrow := Label.new()
	arrow.text = "›"
	arrow.add_theme_font_size_override("font_size", 34)
	arrow.add_theme_color_override("font_color", accent.lightened(0.2))
	arrow.add_theme_color_override("font_shadow_color", Color(accent.r, accent.g, accent.b, 0.6))
	arrow.add_theme_constant_override("shadow_offset_x", 0)
	arrow.add_theme_constant_override("shadow_offset_y", 0)
	arrow.add_theme_constant_override("shadow_outline_size", 6)
	arrow.position = Vector2(12 if rtl else CARD_W - 46, 0)
	arrow.size = Vector2(34, CARD_H)
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(arrow)

	btn.mouse_entered.connect(_on_hover.bind(btn, true))
	btn.mouse_exited.connect(_on_hover.bind(btn, false))
	btn.pressed.connect(_on_select.bind(d))
	return wrap

func _on_hover(btn: Button, entered: bool) -> void:
	if _selecting:
		return
	var mat: ShaderMaterial = btn.get_meta("mat")
	var tw := create_tween().set_parallel(true)
	tw.tween_property(btn, "scale", Vector2.ONE * (1.03 if entered else 1.0), 0.16) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(btn, "position:y", -3.0 if entered else 0.0, 0.16) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "shader_parameter/rim_boost", 1.6 if entered else 1.0, 0.16)

func _on_select(d: Dictionary) -> void:
	if _selecting:
		return
	_selecting = true
	var idx := DIFFS.find(d)
	var btn: Button = _cards[idx].get_child(0) as Button if idx >= 0 and idx < _cards.size() else null
	if btn:
		var mat: ShaderMaterial = btn.get_meta("mat")
		var tw := create_tween().set_parallel(true)
		tw.tween_property(btn, "scale", Vector2.ONE * 1.04, 0.12).set_trans(Tween.TRANS_SINE)
		tw.tween_property(mat, "shader_parameter/rim_boost", 2.2, 0.12)   # glow +~40%
	_pulse_orb(int(d["orb"]))
	AudioManager.play_button_tone(int(d["orb"]), 0.25)
	await get_tree().create_timer(0.25).timeout
	GameState.set_difficulty(d["diff"])
	game_manager.show_game()

func _pulse_orb(idx: int) -> void:
	if idx < 0 or idx >= _orbs.size():
		return
	var orb := _orbs[idx]
	var tw := create_tween()
	tw.tween_property(orb, "scale", Vector2.ONE * 1.6, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(orb, "scale", Vector2.ONE, 0.13).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

# ---------------- icons (procedural) ----------------

func _make_icon(kind: String, s: float, col: Color) -> Node2D:
	match kind:
		"chart":
			return _icon_chart(s, col)
		"flame":
			# Fire ignores the passed-in accent color so it always reads as fire,
			# regardless of the surrounding card's red rim — see _icon_fire().
			return _icon_fire(s)
		_:
			return _icon_poly(_leaf_poly(s), col, -35.0)

func _icon_poly(poly: PackedVector2Array, col: Color, rot_deg: float = 0.0) -> Node2D:
	var n := Node2D.new()
	var pg := Polygon2D.new()
	pg.polygon = poly
	pg.color = col
	pg.rotation_degrees = rot_deg
	n.add_child(pg)
	return n

func _leaf_poly(s: float) -> PackedVector2Array:
	# vertical almond/leaf (points top & bottom, bulging sides)
	var p := PackedVector2Array()
	var n := 16
	for i in n + 1:
		var t: float = float(i) / n
		p.append(Vector2(sin(t * PI) * s * 0.62, lerp(-s, s, t)))
	for i in n + 1:
		var t: float = float(i) / n
		p.append(Vector2(-sin(t * PI) * s * 0.62, lerp(s, -s, t)))
	return p

# Layered fire icon: three nested flame silhouettes (large outer red → orange
# middle → bright yellow core). Each silhouette is drawn from a unit polygon
# scaled by a factor, so the inner layers sit inside the outer one and produce
# the orange-to-yellow gradient you see in real fire.
func _icon_fire(s: float) -> Node2D:
	var n := Node2D.new()
	var outer := Polygon2D.new()
	outer.polygon = _flame_silhouette(s, 1.00, 0.18)
	outer.color = Color(0.95, 0.30, 0.20)              # deep red base
	n.add_child(outer)
	var mid := Polygon2D.new()
	mid.polygon = _flame_silhouette(s, 0.74, 0.30)
	mid.color = Color(1.00, 0.60, 0.18)                # orange middle
	mid.position = Vector2(0, s * 0.06)                # sits a touch lower
	n.add_child(mid)
	var core := Polygon2D.new()
	core.polygon = _flame_silhouette(s, 0.46, 0.42)
	core.color = Color(1.00, 0.92, 0.40)               # hot yellow core
	core.position = Vector2(0, s * 0.18)
	n.add_child(core)
	return n

# Tall, lick-shaped flame silhouette pointing UP (canvas Y grows downward, so
# the tip uses a negative Y). `scale` shrinks the whole shape; `tip_lean` tilts
# the tip slightly to the side for a natural "flickering" feel — inner layers
# use a stronger lean so they don't perfectly mirror the outer outline.
func _flame_silhouette(s: float, scale: float, tip_lean: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	# 24-sample silhouette traced clockwise from the tip, back down to the base,
	# around the rounded bottom, and back up the left side. The numbers come from
	# tracing a stylized flame on a unit grid.
	var pts := [
		Vector2( tip_lean * 0.5, -1.45),   # main tip (slightly leaning)
		Vector2( 0.18, -1.20),
		Vector2( 0.30, -0.80),
		Vector2( 0.50, -0.50),
		Vector2( 0.62, -0.10),
		Vector2( 0.55,  0.25),
		Vector2( 0.78,  0.05),             # small upper-right lick
		Vector2( 0.85,  0.40),
		Vector2( 0.80,  0.75),             # base flare right
		Vector2( 0.55,  1.00),             # rounded base, right
		Vector2( 0.00,  1.05),             # base bottom
		Vector2(-0.55,  1.00),             # rounded base, left
		Vector2(-0.80,  0.75),             # base flare left
		Vector2(-0.85,  0.40),
		Vector2(-0.70,  0.05),             # small upper-left curl
		Vector2(-0.50,  0.20),
		Vector2(-0.55, -0.15),
		Vector2(-0.40, -0.55),
		Vector2(-0.25, -0.90),
		Vector2(-0.10, -1.15),
	]
	for v in pts:
		p.append(Vector2(v.x, v.y) * s * scale)
	return p

func _icon_chart(s: float, col: Color) -> Node2D:
	var n := Node2D.new()
	var heights := [0.7, 1.0, 1.35]
	var bw := s * 0.34
	var gap := s * 0.16
	var total := 3 * bw + 2 * gap
	for i in 3:
		var h: float = s * heights[i]
		var bar := Polygon2D.new()
		var x := -total * 0.5 + i * (bw + gap)
		bar.polygon = PackedVector2Array([
			Vector2(x, s * 0.6), Vector2(x + bw, s * 0.6),
			Vector2(x + bw, s * 0.6 - h), Vector2(x, s * 0.6 - h)])
		bar.color = col
		n.add_child(bar)
	return n

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
		var r := sz.x * 0.44
		_orbit.position = Vector2(cx, sz.y * 0.52)
		_rebuild_ring(r)
		for i in _orbs.size():
			var a: float = deg_to_rad(ORBS[i]["deg"])
			_orbs[i].position = Vector2(cos(a), sin(a)) * r

	var top := sz.y * 0.05
	if _header:
		_header.position = Vector2(cx - _header.size.x * 0.5, top)
	if _line_l and _line_r:
		var ly := top + 86.0
		_line_l.position = Vector2(cx - 180, ly)
		_line_r.position = Vector2(cx + 180 - _line_r.size.x, ly)

	if _back:
		_back.position = Vector2(24, top + 4)

	# Three thin difficulty pills stacked with generous spacing, centered vertically
	# in the remaining area below the header.
	var total := DIFFS.size() * CARD_H + (DIFFS.size() - 1) * CARD_GAP
	var start_y := maxf(top + 170.0, sz.y * 0.55 - total * 0.5)
	for i in _cards.size():
		_cards[i].position = Vector2(cx - CARD_W * 0.5, start_y + i * (CARD_H + CARD_GAP))

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

# Header + orbit fade in, then cards rise in one after another.
func _intro() -> void:
	for n in [_header, _orbit, _back]:
		if n:
			n.modulate.a = 0.0
			create_tween().tween_property(n, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE)
	for i in _cards.size():
		var card := _cards[i]
		card.modulate.a = 0.0
		var base_y := card.position.y
		card.position.y = base_y + 18.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(card, "modulate:a", 1.0, 0.4).set_delay(0.15 + i * 0.12)
		tw.tween_property(card, "position:y", base_y, 0.4).set_delay(0.15 + i * 0.12) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
