extends Control

# Premium main menu: shader-driven navy->indigo background (vignette + radial
# glow + soft blobs, gently breathing), a slowly rotating orbit ring carrying
# five pulsing colored orbs, a glowing SIMON logo, and three dark navy-glass pill
# buttons with hover / press / float micro-animations. Everything is built from
# Godot nodes + shaders + tweens (no static images).

var game_manager: Node

const GOLD := Color(1.0, 0.85, 0.2)

# Orbit orb colors - a soft reference to the Simon colors (premium, not neon).
const ORB_COLORS := [
	Color(1.00, 0.82, 0.29),  # yellow
	Color(0.90, 0.28, 0.30),  # red
	Color(0.55, 0.36, 0.96),  # purple
	Color(0.18, 0.78, 0.39),  # green
	Color(0.23, 0.51, 0.96),  # blue
]

const BTN_W := 360.0
const BTN_H := 74.0
const BTN_GAP := 22.0
const ICON_BLUE := Color(0.23, 0.51, 0.96)
const ICON_GREEN := Color(0.18, 0.78, 0.39)
const ICON_PURPLE := Color(0.55, 0.36, 0.96)

const BG_SHADER := "
shader_type canvas_item;
uniform float aspect = 0.5;
void fragment() {
	vec2 uv = UV;
	// deep, near-black space gradient (no pure black) - dark like the reference.
	// Built with mix() only (no ternary, which can fail to compile).
	vec3 top = vec3(0.012, 0.020, 0.070);
	vec3 mid = vec3(0.018, 0.035, 0.110);
	vec3 bot = vec3(0.045, 0.030, 0.105);
	vec3 col = mix(top, mid, clamp(uv.y / 0.5, 0.0, 1.0));
	col = mix(col, bot, clamp((uv.y - 0.5) / 0.5, 0.0, 1.0));

	// soft BLUE glow hugging the left edge, soft RED glow hugging the right edge
	col += vec3(0.10, 0.22, 0.58) * smoothstep(0.5, 0.0, distance(uv, vec2(0.0, 0.45))) * 0.30;
	col += vec3(0.55, 0.12, 0.22) * smoothstep(0.5, 0.0, distance(uv, vec2(1.0, 0.50))) * 0.22;

	vec2 p = (uv - vec2(0.5)) * vec2(aspect, 1.0);
	// very subtle radial glow behind the logo (upper-center), slowly breathing
	float breathe = 0.85 + 0.15 * sin(TIME * 0.6);
	col += vec3(0.10, 0.16, 0.42) * smoothstep(0.5, 0.0, length(p - vec2(0.0, -0.18))) * 0.20 * breathe;

	// gentle vignette to keep the center deep
	col *= mix(0.6, 1.0, smoothstep(1.1, 0.25, length(p)));
	COLOR = vec4(col, 1.0);
}
"

# Dark navy-glass button face (gradient + top highlight + blue rim + inner glow +
# soft drop shadow), drawn on a ColorRect padded out so the shadow has room.
const BTN_PAD := 20.0
const BTN_SHADER := "
shader_type canvas_item;
uniform vec2 rect_size = vec2(400.0, 114.0);
uniform float pad = 20.0;
uniform float radius = 34.0;
uniform vec3 top_col = vec3(0.118, 0.153, 0.369);
uniform vec3 bot_col = vec3(0.078, 0.102, 0.259);
float sdf_round_box(vec2 pp, vec2 b, float r) {
	vec2 q = abs(pp) - b + vec2(r);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}
void fragment() {
	vec2 px = UV * rect_size;
	vec2 p = px - rect_size * 0.5;
	vec2 hb = (rect_size - vec2(pad * 2.0)) * 0.5;   // visual half-size
	float d = sdf_round_box(p, hb, radius);
	float body = smoothstep(1.0, -1.0, d);           // 1 inside, AA edge

	// soft drop shadow below the panel
	float sd = sdf_round_box(p - vec2(0.0, 7.0), hb, radius);
	float shadow = smoothstep(pad, 0.0, sd) * 0.45;

	float ty = clamp((px.y - pad) / (rect_size.y - pad * 2.0), 0.0, 1.0);
	vec3 base = mix(top_col, bot_col, ty);                       // subtle gradient
	base += vec3(0.55, 0.65, 0.95) * smoothstep(0.16, 0.0, ty) * 0.10;  // top highlight
	base += vec3(0.35, 0.55, 1.0) * smoothstep(-7.0, -0.5, d) * 0.16;   // blue rim light
	base += vec3(0.20, 0.35, 0.80) * smoothstep(95.0, 0.0, length(p)) * 0.05;  // inner glow

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
var _logo_box: Control
var _btn_wrappers: Array[Control] = []
var _btn_face_mat: ShaderMaterial
var _signing_in := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	FirebaseManager.signed_in.connect(_on_signed_in)
	FirebaseManager.sign_in_failed.connect(_on_sign_in_failed)
	FirebaseManager.signed_out.connect(_on_signed_out)

	_orb_tex = _make_radial_texture()
	_build_background()
	_build_orbit()
	_build_logo()
	_build_buttons()
	_build_account_corner()

	_layout()
	get_viewport().size_changed.connect(_layout)
	_start_animations()
	AudioManager.play_bg_music()

# ---------------- background ----------------

func _build_background() -> void:
	# NOTE: screens live under a CanvasLayer (not a Control), so anchors give this
	# screen no size - the background must be sized to the viewport in _layout().
	_bg = ColorRect.new()
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.color = Color(0.02, 0.03, 0.09)   # dark fallback if the shader ever fails (never gray)
	var sh := Shader.new()
	sh.code = BG_SHADER
	_bg_mat = ShaderMaterial.new()
	_bg_mat.shader = sh
	_bg.material = _bg_mat
	add_child(_bg)

# ---------------- orbit + orbs ----------------

func _build_orbit() -> void:
	# A single parent (OrbitContainer): the ring and all orbs are children, so
	# rotating it spins the whole system together. The orbs are radially
	# symmetric, so they keep facing the viewer as the container turns.
	_orbit = Node2D.new()
	add_child(_orbit)

	_ring_glow = _make_ring(7.0, Color(0.45, 0.42, 1.0, 0.08))  # soft blue-purple bloom
	_orbit.add_child(_ring_glow)
	_ring_line = _make_ring(2.0, Color(0.62, 0.60, 1.0, 0.25))  # thin blue+purple line
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

# An orb = a soft additive halo + a brighter core, both from one radial texture.
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

# White radial gradient (bright center -> transparent edge) for orbs.
func _make_radial_texture() -> Texture2D:
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := Vector2(s, s) * 0.5
	for y in s:
		for x in s:
			var d := Vector2(x, y).distance_to(c) / (s * 0.5)
			var a := pow(clampf(1.0 - d, 0.0, 1.0), 2.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)

# ---------------- logo ----------------

func _build_logo() -> void:
	var lw := 720.0
	var lh := 172.0
	_logo_box = Control.new()
	_logo_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo_box.custom_minimum_size = Vector2(lw, lh)
	_logo_box.size = Vector2(lw, lh)
	add_child(_logo_box)

	var font := ThemeDB.fallback_font
	var f := 96

	# "S I M [O] N" - the O is a 4-colour Simon ring, not a letter.
	var w_left := font.get_string_size("S I M", HORIZONTAL_ALIGNMENT_LEFT, -1, f).x
	var w_right := font.get_string_size("N", HORIZONTAL_ALIGNMENT_LEFT, -1, f).x
	var w_space := font.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, f).x
	var dr := 72.0                                   # O-ring diameter (~ cap height)
	var g := w_space * 0.7                           # gap on each side of the ring
	var th := 112.0                                  # title band height
	var group_w := w_left + g + dr + g + w_right
	var x0 := (lw - group_w) * 0.5

	_logo_box.add_child(_logo_letter("S I M", f, Vector2(x0, 0), Vector2(w_left, th)))
	var ring := _make_o_ring(dr)
	# Drop the ring slightly below the cap-height center so it visually sits
	# alongside the lowercase center of the surrounding capitals (the letter "O"
	# in this font reads optically lower than the cap-tops).
	ring.position = Vector2(x0 + w_left + g + dr * 0.5, th * 0.6 + f * 0.04)
	_logo_box.add_child(ring)
	_logo_box.add_child(_logo_letter("N", f, Vector2(x0 + w_left + g + dr + g, 0), Vector2(w_right, th)))

	# subtitle + glowing side lines, each ending in a small glowing dot
	var sf := 20
	var sub_txt := "M E M O R Y   C H A L L E N G E"
	var w_sub := font.get_string_size(sub_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sf).x
	var sub_y := th + 12.0
	var sub_x := (lw - w_sub) * 0.5

	var sub := Label.new()
	sub.text = sub_txt
	sub.add_theme_font_size_override("font_size", sf)
	sub.add_theme_color_override("font_color", Color(0.76, 0.74, 1.0, 0.95))  # lavender
	sub.add_theme_color_override("font_shadow_color", Color(0.45, 0.40, 1.0, 0.35))
	sub.add_theme_constant_override("shadow_offset_x", 0)
	sub.add_theme_constant_override("shadow_offset_y", 0)
	sub.add_theme_constant_override("shadow_outline_size", 5)   # subtle glow
	sub.position = Vector2(sub_x, sub_y)
	sub.size = Vector2(w_sub, 28)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo_box.add_child(sub)

	var line_col := Color(0.50, 0.50, 1.0, 0.5)
	var dot_col := Color(0.58, 0.56, 1.0)
	var llen := 56.0
	var lgap := 18.0
	var ly := sub_y + 14.0                           # vertical centre of the subtitle
	_add_line(Vector2(sub_x - lgap - llen, ly - 1.0), Vector2(llen, 2.0), line_col)
	_logo_box.add_child(_glow_dot(9.0, dot_col, Vector2(sub_x - lgap - llen, ly)))
	_add_line(Vector2(sub_x + w_sub + lgap, ly - 1.0), Vector2(llen, 2.0), line_col)
	_logo_box.add_child(_glow_dot(9.0, dot_col, Vector2(sub_x + w_sub + lgap + llen, ly)))

# A bold, white, soft-shadowed logo letter (faux-bold via same-colour outline).
func _logo_letter(txt: String, fsize: int, pos: Vector2, size: Vector2) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(1, 1, 1, 1))
	l.add_theme_constant_override("outline_size", 2)             # weight, not a stroke
	l.add_theme_color_override("font_shadow_color", Color(0.0, 0.02, 0.10, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 6)
	l.add_theme_constant_override("shadow_outline_size", 10)     # soft shadow + glow
	l.position = pos
	l.size = size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# The Simon "O": four colored quarter-arcs (yellow/red/green/blue) around an
# empty dark center, drawn as round-capped Line2D arcs. Centered on its origin.
func _make_o_ring(diameter: float) -> Node2D:
	var ring := Node2D.new()
	var rr := diameter * 0.5
	var thick := diameter * 0.2
	var cols := [
		Color(0.97, 0.78, 0.22),  # top    - yellow
		Color(0.88, 0.22, 0.24),  # right  - red
		Color(0.20, 0.70, 0.34),  # bottom - green
		Color(0.24, 0.50, 0.95),  # left   - blue
	]
	var gap := deg_to_rad(12.0)
	var base := -PI * 0.75                            # start of the top segment
	for i in 4:
		var a0: float = base + i * PI * 0.5 + gap * 0.5
		var a1: float = base + (i + 1) * PI * 0.5 - gap * 0.5
		var arc := Line2D.new()
		arc.width = thick
		arc.default_color = cols[i]
		arc.antialiased = true
		arc.begin_cap_mode = Line2D.LINE_CAP_ROUND
		arc.end_cap_mode = Line2D.LINE_CAP_ROUND
		var pts := PackedVector2Array()
		var n := 14
		var pr := rr - thick * 0.5
		for j in n + 1:
			var a: float = lerp(a0, a1, float(j) / n)
			pts.append(Vector2(cos(a), sin(a)) * pr)
		arc.points = pts
		ring.add_child(arc)
	return ring

func _add_line(pos: Vector2, size: Vector2, col: Color) -> void:
	var r := ColorRect.new()
	r.position = pos
	r.size = size
	r.color = col
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo_box.add_child(r)

# Small glowing dot centered on `center`.
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

# ---------------- buttons ----------------

func _build_buttons() -> void:
	# Shared dark-glass face material (all pills are identical size/colors).
	var sh := Shader.new()
	sh.code = BTN_SHADER
	_btn_face_mat = ShaderMaterial.new()
	_btn_face_mat.shader = sh
	_btn_face_mat.set_shader_parameter("rect_size", Vector2(BTN_W + BTN_PAD * 2.0, BTN_H + BTN_PAD * 2.0))
	_btn_face_mat.set_shader_parameter("pad", BTN_PAD)
	_btn_face_mat.set_shader_parameter("radius", 34.0)
	_btn_face_mat.set_shader_parameter("top_col", Vector3(0.118, 0.153, 0.369))  # #1E275E
	_btn_face_mat.set_shader_parameter("bot_col", Vector3(0.078, 0.102, 0.259))  # #141A42

	_btn_wrappers.clear()
	_btn_wrappers.append(_make_menu_button("START GAME", ICON_BLUE, _on_start))
	_btn_wrappers.append(_make_menu_button("LEADERBOARDS", ICON_GREEN, _on_leaderboards))
	_btn_wrappers.append(_make_menu_button("HOW TO PLAY", ICON_PURPLE, _on_how))

# A dark navy-glass pill (shader face: gradient + top highlight + blue rim + inner
# glow + soft shadow), a glowing colored icon on the left, light label center-left,
# and a chevron on the right.
# Wrapped in a Control so layout (wrapper.position) and animation (button.scale /
# position) never fight each other.
func _make_menu_button(txt: String, icon_col: Color, cb: Callable) -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(BTN_W, BTN_H)
	wrap.size = Vector2(BTN_W, BTN_H)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wrap)

	var btn := Button.new()
	btn.size = Vector2(BTN_W, BTN_H)
	btn.pivot_offset = Vector2(BTN_W, BTN_H) * 0.5      # scale about the center
	btn.focus_mode = Control.FOCUS_NONE
	# invisible styleboxes - the dark-glass look comes entirely from the shader face
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(st, empty)
	wrap.add_child(btn)

	# dark navy-glass face (shader). Padded out so the shadow has room; the visual
	# pill is inset by BTN_PAD and stays centered under scaling.
	var face := ColorRect.new()
	face.material = _btn_face_mat
	face.position = Vector2(-BTN_PAD, -BTN_PAD)
	face.size = Vector2(BTN_W + BTN_PAD * 2.0, BTN_H + BTN_PAD * 2.0)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(face)

	# colored circular icon - brighter than the button, glowing from within.
	# In RTL the icon mirrors to the trailing edge so it sits opposite the arrow.
	var rtl_layout := _is_rtl()
	var icon := Panel.new()
	var d := 44.0
	icon.size = Vector2(d, d)
	icon.position = Vector2(BTN_W - 18 - d if rtl_layout else 18, (BTN_H - d) * 0.5)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := StyleBoxFlat.new()
	ic.bg_color = icon_col.lightened(0.12)
	ic.set_corner_radius_all(int(d * 0.5))
	ic.border_color = icon_col.lightened(0.45)        # bright inner-lit rim
	ic.set_border_width_all(2)
	ic.shadow_color = Color(icon_col.r, icon_col.g, icon_col.b, 0.6)
	ic.shadow_size = 13                               # soft colored bloom
	icon.add_theme_stylebox_override("panel", ic)
	btn.add_child(icon)

	var lbl := Label.new()
	lbl.text = txt
	lbl.add_theme_font_size_override("font_size", 23)
	lbl.add_theme_color_override("font_color", Color(0.93, 0.96, 1.0))
	lbl.position = Vector2(40 if rtl_layout else 18 + d + 16, 0)
	lbl.size = Vector2(BTN_W - (18 + d + 16) - 40, BTN_H)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if rtl_layout else HORIZONTAL_ALIGNMENT_LEFT
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(lbl)

	var arrow := Label.new()
	# Always points right: the button's visible "leading icon → label → arrow"
	# flow does not mirror on RTL devices (Godot's auto-mirror cancels the manual
	# position flip), so a "‹" here would be the only RTL-flipped element and
	# would read as pointing the wrong way against an otherwise LTR-laid row.
	arrow.text = "›"
	arrow.add_theme_font_size_override("font_size", 32)
	arrow.add_theme_color_override("font_color", Color(0.55, 0.66, 0.92))
	arrow.position = Vector2(10 if rtl_layout else BTN_W - 40, 0)
	arrow.size = Vector2(30, BTN_H)
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(arrow)

	btn.mouse_entered.connect(_on_btn_hover.bind(btn, true))
	btn.mouse_exited.connect(_on_btn_hover.bind(btn, false))
	btn.button_down.connect(_on_btn_down.bind(btn))
	btn.button_up.connect(_on_btn_up.bind(btn))
	btn.pressed.connect(cb)
	return wrap

# True when the UI is laid out right-to-left (Hebrew, Arabic, …). Used to mirror
# chevrons/icons so "next" still reads in the natural reading direction.
# is_layout_rtl() resolves the inherited/locale settings to the final orientation,
# while get_layout_direction() can still return the symbolic LOCALE value.
func _is_rtl() -> bool:
	return is_layout_rtl()

func _on_btn_hover(btn: Button, entered: bool) -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(btn, "scale", Vector2.ONE * (1.03 if entered else 1.0), 0.16) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(btn, "modulate", Color(1.10, 1.10, 1.10) if entered else Color.WHITE, 0.16)

func _on_btn_down(btn: Button) -> void:
	create_tween().tween_property(btn, "scale", Vector2.ONE * 0.98, 0.10) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _on_btn_up(btn: Button) -> void:
	create_tween().tween_property(btn, "scale", Vector2.ONE, 0.20) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)   # quick bounce back

# ---------------- layout ----------------

func _layout() -> void:
	var sz := get_viewport_rect().size
	var cx := sz.x * 0.5
	var cy := sz.y * 0.5
	if _bg:
		_bg.position = Vector2.ZERO
		_bg.size = sz                       # CanvasLayer gives no size; fill explicitly
	if _bg_mat:
		_bg_mat.set_shader_parameter("aspect", sz.x / maxf(1.0, sz.y))

	# orbit: centered, radius ~40% of screen width
	var r := sz.x * 0.40
	if _orbit:
		_orbit.position = Vector2(cx, cy)
		_rebuild_ring(r)
		for i in _orbs.size():
			var a: float = -PI * 0.5 + i * TAU / _orbs.size()
			_orbs[i].position = Vector2(cos(a), sin(a)) * r

	# logo: focal point, upper-center
	if _logo_box:
		_logo_box.position = Vector2(cx - _logo_box.size.x * 0.5, sz.y * 0.16)

	# buttons: stacked, centered, lower portion
	var total := _btn_wrappers.size() * BTN_H + (_btn_wrappers.size() - 1) * BTN_GAP
	var start_y := sz.y * 0.60 - total * 0.5
	for i in _btn_wrappers.size():
		_btn_wrappers[i].position = Vector2(cx - BTN_W * 0.5, start_y + i * (BTN_H + BTN_GAP))

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
	# orbit: one full revolution every 25s, perfectly linear (no easing)
	var rot := create_tween().set_loops()
	rot.tween_property(_orbit, "rotation", TAU, 25.0).from(0.0).set_trans(Tween.TRANS_LINEAR)

	# orbs: subtle ~5% pulse, ~2s, slightly different timing each
	for i in _orbs.size():
		var dur := 0.9 + i * 0.06
		var pulse := create_tween().set_loops()
		pulse.tween_property(_orbs[i], "scale", Vector2.ONE * 1.05, dur) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		pulse.tween_property(_orbs[i], "scale", Vector2.ONE, dur) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# buttons: gentle vertical float of 1-2px, each slightly out of phase
	for i in _btn_wrappers.size():
		var btn := _btn_wrappers[i].get_child(0)
		var dur := 2.4 + i * 0.4
		var fl := create_tween().set_loops()
		fl.tween_property(btn, "position:y", -2.0, dur) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		fl.tween_property(btn, "position:y", 0.0, dur) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

# ---------------- account corner ----------------

func _build_account_corner() -> void:
	var sz := get_viewport_rect().size
	const W := 200.0
	var x := sz.x - W - 16.0
	if FirebaseManager.is_signed_in() and FirebaseManager.has_display_name():
		var name_lbl := Label.new()
		name_lbl.text = FirebaseManager.display_name
		name_lbl.add_theme_font_size_override("font_size", 22)
		name_lbl.add_theme_color_override("font_color", GOLD)
		name_lbl.position = Vector2(x, 14)
		name_lbl.size = Vector2(W, 32)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		add_child(name_lbl)

		var sign_out := Button.new()
		sign_out.text = "sign out"
		sign_out.flat = true
		sign_out.add_theme_font_size_override("font_size", 14)
		sign_out.add_theme_color_override("font_color", Color(0.55, 0.55, 0.72))
		sign_out.add_theme_color_override("font_hover_color", Color(1.0, 0.45, 0.45))
		sign_out.add_theme_color_override("font_pressed_color", Color(0.85, 0.25, 0.25))
		sign_out.position = Vector2(x, 44)
		sign_out.size = Vector2(W, 28)
		sign_out.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		sign_out.pressed.connect(_on_sign_out)
		add_child(sign_out)
	else:
		_add_corner_btn("Sign in", Vector2(sz.x - 136, 16), Vector2(120, 44),
			Color(0.15, 0.6, 0.95), _on_sign_in)

func _add_corner_btn(txt: String, pos: Vector2, size: Vector2, col: Color, cb: Callable) -> void:
	var btn := Button.new()
	btn.text = txt
	btn.position = pos
	btn.size = size
	btn.add_theme_font_size_override("font_size", 18)
	_style(btn, col)
	btn.pressed.connect(cb)
	add_child(btn)

func _style(btn: Button, col: Color) -> void:
	var sn := StyleBoxFlat.new()
	sn.bg_color = col
	sn.set_corner_radius_all(14)
	btn.add_theme_stylebox_override("normal", sn)
	var sh := sn.duplicate() as StyleBoxFlat
	sh.bg_color = col.lightened(0.2)
	btn.add_theme_stylebox_override("hover", sh)
	var sp := sn.duplicate() as StyleBoxFlat
	sp.bg_color = col.darkened(0.2)
	btn.add_theme_stylebox_override("pressed", sp)
	btn.add_theme_color_override("font_color", Color.WHITE)

# ---------------- actions ----------------
func _on_start() -> void:
	AudioManager.stop_bg_music()
	game_manager.show_difficulty()

func _on_how() -> void:
	game_manager.show_how_to_play()

func _on_leaderboards() -> void:
	if FirebaseManager.is_signed_in() and FirebaseManager.has_display_name():
		game_manager.show_leaderboards()
	else:
		_on_sign_in()  # not signed in -> behaves like the sign-in button

func _on_sign_in() -> void:
	if _signing_in:
		return
	_signing_in = true
	FirebaseManager.sign_in()

func _on_sign_out() -> void:
	FirebaseManager.sign_out_user()

func _on_signed_in(_uid: String, _display_name: String) -> void:
	_signing_in = false
	if FirebaseManager.has_display_name():
		game_manager.show_home()  # rebuild to show name + leaderboards access
	else:
		game_manager.show_name_picker()

func _on_sign_in_failed(_error: String) -> void:
	_signing_in = false

func _on_signed_out() -> void:
	game_manager.show_home()
