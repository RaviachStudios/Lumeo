extends Control

# Premium "Choose Difficulty" screen, matching the home menu: deep navy->purple
# shader background (nebula + tiny particles + glow + vignette), a slowly
# rotating orbit with five glowing orbs, a glowing header with side-lined
# subtitle, three interactive dark-glass difficulty cards with accent neon
# rims / icons, and a bottom "Beat your best" card. Nodes + shaders +
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

# Unlock-confirm popup (only present while a locked card is being purchased).
var _popup: Control
var _popup_dialog: Panel
var _popup_backdrop: ColorRect

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
	# If the wallet doc lands after this screen is built, drop the lock on any
	# difficulty the player already owns.
	CoinsManager.levels_changed.connect(_on_levels_changed)
	_start_animations()
	_intro()

func _on_levels_changed() -> void:
	for d in DIFFS:
		var diff: String = d["diff"]
		if CoinsManager.is_level_unlocked(diff):
			_unlock_card_visual(diff)

# ---------------- background ----------------

func _build_background() -> void:
	# Skip when a shop theme is equipped — BackgroundManager renders that
	# globally beneath us.
	if BackgroundManager.is_themed():
		return
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
	var diff: String = d["diff"]
	var locked := not CoinsManager.is_level_unlocked(diff)
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

	# circular icon container. A bought difficulty glows in its accent color; a
	# locked one is muted with no glow, so the eye isn't drawn to an option the
	# player can't pick yet (the styling is swapped back on purchase).
	var dia := 52.0
	var icon := Panel.new()
	icon.size = Vector2(dia, dia)
	icon.position = Vector2(CARD_W - 22 - dia if rtl else 22, (CARD_H - dia) * 0.5)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.add_theme_stylebox_override("panel", _icon_stylebox(accent, dia, locked))
	btn.add_child(icon)
	var sym := _make_icon(d["icon"], dia * 0.36, accent.lightened(0.45))
	sym.position = Vector2(dia * 0.5, dia * 0.5)
	if locked:
		sym.modulate = Color(0.58, 0.61, 0.70)   # desaturate the glyph while locked
	icon.add_child(sym)
	btn.set_meta("icon_panel", icon)
	btn.set_meta("icon_sym", sym)
	btn.set_meta("icon_dia", dia)

	# Title sits next to the icon (leading edge); sides flip in RTL so the icon
	# stays on the visual leading side.
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
	btn.set_meta("title", title)
	btn.set_meta("diff", diff)

	# Locked difficulty: dim the title, stamp a price badge (coin cost) on the
	# trailing edge, and pin a padlock to the top-right corner (overhanging the
	# card a touch so it reads as a "locked" seal). Both are removed on purchase.
	if locked:
		title.add_theme_color_override("font_color", Color(0.62, 0.66, 0.78))
		title.add_theme_color_override("font_outline_color", Color(0.62, 0.66, 0.78))
		var badge := _make_price_badge(CoinsManager.level_price(diff))
		var bw: float = badge.size.x
		badge.position = Vector2(22 if rtl else CARD_W - 22 - bw, (CARD_H - badge.size.y) * 0.5)
		btn.add_child(badge)
		btn.set_meta("lock_badge", badge)
		var seal := _make_lock_seal()
		var sd: float = seal.size.x
		# Top corner, exceeding slightly past the card edge on the trailing side.
		seal.position = Vector2(-sd * 0.40 if rtl else CARD_W - sd * 0.60, -sd * 0.40)
		btn.add_child(seal)
		btn.set_meta("lock_seal", seal)

	btn.pressed.connect(_on_card_pressed.bind(d))
	return wrap

# Trailing-edge badge for a locked card: a gold coin disc and the price. The
# padlock that used to live here now sits in the card's top-right corner (see
# _make_lock_seal). Returned as a fixed-size Control so the caller can position it.
func _make_price_badge(price: int) -> Control:
	var badge := Control.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := 40.0

	# Gold coin disc with "$"
	var dia := 26.0
	var disc := Panel.new()
	disc.size = Vector2(dia, dia)
	disc.position = Vector2(0.0, (h - dia) * 0.5)
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ds := StyleBoxFlat.new()
	ds.bg_color = Color(1.0, 0.78, 0.16)
	ds.set_corner_radius_all(int(dia * 0.5))
	ds.border_color = Color(1.0, 0.92, 0.55)
	ds.set_border_width_all(2)
	disc.add_theme_stylebox_override("panel", ds)
	badge.add_child(disc)
	var glyph := Label.new()
	glyph.text = "$"
	glyph.add_theme_font_size_override("font_size", 18)
	glyph.add_theme_color_override("font_color", Color(0.45, 0.30, 0.05))
	glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.add_child(glyph)

	# Price number
	var price_lbl := Label.new()
	price_lbl.text = str(price)
	price_lbl.add_theme_font_size_override("font_size", 24)
	price_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45))
	price_lbl.position = Vector2(dia + 6.0, 0)
	price_lbl.size = Vector2(64, h)
	price_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	price_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(price_lbl)

	badge.size = Vector2(dia + 6.0 + 64.0, h)
	return badge

# Accent-lit circular icon backing for a difficulty card. Locked cards get a flat
# muted disc with no glow; unlocked cards glow in their accent color.
func _icon_stylebox(accent: Color, dia: float, locked: bool) -> StyleBoxFlat:
	var ic := StyleBoxFlat.new()
	ic.set_corner_radius_all(int(dia * 0.5))
	ic.set_border_width_all(2)
	if locked:
		ic.bg_color = Color(0.16, 0.18, 0.24, 0.45)
		ic.border_color = Color(0.42, 0.45, 0.55)
		ic.shadow_size = 0                                   # no glow while locked
	else:
		var icbg := accent.darkened(0.2)
		icbg.a = 0.28
		ic.bg_color = icbg
		ic.border_color = accent.lightened(0.2)
		ic.shadow_color = Color(accent.r, accent.g, accent.b, 0.5)
		ic.shadow_size = 14
	return ic

# Round padlock "seal" pinned to a locked card's top-right corner. Dark glass
# disc with a padlock glyph; sized so the caller can overhang the card edge.
func _make_lock_seal() -> Control:
	var d := 38.0
	var seal := Panel.new()
	seal.size = Vector2(d, d)
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.10, 0.12, 0.20, 0.96)
	s.set_corner_radius_all(int(d * 0.5))
	s.border_color = Color(0.60, 0.63, 0.75)
	s.set_border_width_all(2)
	s.shadow_color = Color(0, 0, 0, 0.55)
	s.shadow_size = 7
	seal.add_theme_stylebox_override("panel", s)
	var lk := _lock_icon(7.5, Color(0.90, 0.92, 1.0))
	lk.position = Vector2(d * 0.5, d * 0.5 - 1.0)
	seal.add_child(lk)
	return seal

# Minimal padlock: a rounded body rect + a semicircular shackle. `s` is roughly
# the body half-width. Centered on the node's origin.
func _lock_icon(s: float, col: Color) -> Node2D:
	var n := Node2D.new()
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(-s, 0), Vector2(s, 0),
		Vector2(s, s * 1.3), Vector2(-s, s * 1.3)])
	body.color = col
	n.add_child(body)
	var shackle := Line2D.new()
	shackle.width = maxf(2.0, s * 0.32)
	shackle.default_color = col
	var pts := PackedVector2Array()
	var r := s * 0.62
	for i in 13:
		var a: float = PI + float(i) / 12.0 * PI
		pts.append(Vector2(cos(a) * r, -s * 0.05 + sin(a) * r))
	shackle.points = pts
	n.add_child(shackle)
	return n

# Tapping a card either starts the game (unlocked) or opens the buy-confirm
# popup (locked). The popup, not the card, completes a purchase.
func _on_card_pressed(d: Dictionary) -> void:
	if _selecting or _popup:
		return
	if not CoinsManager.is_level_unlocked(String(d["diff"])):
		_show_unlock_popup(d)
		return
	_on_select(d)

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

# ---------------- unlock (buy) popup ----------------

const POPUP_W := 440.0
const POPUP_H := 250.0

func _show_unlock_popup(d: Dictionary) -> void:
	if _popup:
		return
	var diff: String = d["diff"]
	var accent: Color = d["accent"]
	var price := CoinsManager.level_price(diff)
	var sz := get_viewport_rect().size

	_popup = Control.new()
	_popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	_popup.size = sz
	add_child(_popup)

	_popup_backdrop = ColorRect.new()
	_popup_backdrop.color = Color(0, 0, 0, 0.0)
	_popup_backdrop.size = sz
	_popup_backdrop.gui_input.connect(func(ev: InputEvent) -> void:
		if (ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed) \
				or (ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed):
			_close_popup())
	_popup.add_child(_popup_backdrop)

	_popup_dialog = Panel.new()
	_popup_dialog.size = Vector2(POPUP_W, POPUP_H)
	_popup_dialog.position = (sz - Vector2(POPUP_W, POPUP_H)) * 0.5
	_popup_dialog.pivot_offset = Vector2(POPUP_W, POPUP_H) * 0.5
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.08, 0.10, 0.22, 0.98)
	ps.set_corner_radius_all(26)
	ps.border_color = Color(accent.r, accent.g, accent.b, 0.7)
	ps.set_border_width_all(2)
	ps.shadow_color = Color(0, 0, 0, 0.5)
	ps.shadow_size = 22
	_popup_dialog.add_theme_stylebox_override("panel", ps)
	_popup.add_child(_popup_dialog)

	# Heading
	var head := Label.new()
	head.text = "Unlock %s?" % String(d["title"])
	head.add_theme_font_size_override("font_size", 30)
	head.add_theme_color_override("font_color", accent.lightened(0.25))
	head.position = Vector2(0, 28)
	head.size = Vector2(POPUP_W, 40)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_popup_dialog.add_child(head)

	# Price row: coin disc + "for N coins"
	var row := Control.new()
	row.size = Vector2(POPUP_W, 40)
	row.position = Vector2(0, 84)
	_popup_dialog.add_child(row)
	var dia := 30.0
	var price_text := "for %d coins" % price
	var text_lbl := Label.new()
	text_lbl.text = price_text
	text_lbl.add_theme_font_size_override("font_size", 24)
	text_lbl.add_theme_color_override("font_color", Color(0.90, 0.92, 1.0))
	# Approx-center the disc+text group.
	var est_text_w := 11.0 * price_text.length()
	var group_w := dia + 10.0 + est_text_w
	var gx := (POPUP_W - group_w) * 0.5
	var disc := Panel.new()
	disc.size = Vector2(dia, dia)
	disc.position = Vector2(gx, (40 - dia) * 0.5)
	var ds := StyleBoxFlat.new()
	ds.bg_color = Color(1.0, 0.78, 0.16)
	ds.set_corner_radius_all(int(dia * 0.5))
	ds.border_color = Color(1.0, 0.92, 0.55)
	ds.set_border_width_all(2)
	disc.add_theme_stylebox_override("panel", ds)
	row.add_child(disc)
	var dglyph := Label.new()
	dglyph.text = "$"
	dglyph.add_theme_font_size_override("font_size", 20)
	dglyph.add_theme_color_override("font_color", Color(0.45, 0.30, 0.05))
	dglyph.set_anchors_preset(Control.PRESET_FULL_RECT)
	dglyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dglyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	disc.add_child(dglyph)
	text_lbl.position = Vector2(gx + dia + 10.0, 0)
	text_lbl.size = Vector2(est_text_w + 20.0, 40)
	text_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(text_lbl)

	# Feedback line (e.g. "Not enough coins") — hidden until needed.
	var feedback := Label.new()
	feedback.name = "Feedback"
	feedback.text = ""
	feedback.add_theme_font_size_override("font_size", 18)
	feedback.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
	feedback.position = Vector2(0, 130)
	feedback.size = Vector2(POPUP_W, 24)
	feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_popup_dialog.add_child(feedback)

	# Confirm (✓) and cancel (✗) round buttons.
	var by := POPUP_H - 28.0 - 72.0
	var yes := _make_choice_button("check", Color(0.24, 0.74, 0.40))
	yes.position = Vector2(POPUP_W * 0.5 - 72.0 - 18.0, by)
	yes.pressed.connect(_on_confirm_purchase.bind(d, feedback))
	_popup_dialog.add_child(yes)
	var no := _make_choice_button("cross", Color(0.82, 0.30, 0.34))
	no.position = Vector2(POPUP_W * 0.5 + 18.0, by)
	no.pressed.connect(_close_popup)
	_popup_dialog.add_child(no)

	# Pop-in animation.
	_popup_dialog.scale = Vector2.ONE * 0.85
	_popup_dialog.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_popup_backdrop, "color", Color(0, 0, 0, 0.55), 0.16)
	tw.tween_property(_popup_dialog, "scale", Vector2.ONE, 0.20) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_popup_dialog, "modulate:a", 1.0, 0.16)

# 72x72 circular button containing a drawn check or cross, so the glyphs always
# render regardless of font coverage.
func _make_choice_button(kind: String, accent: Color) -> Button:
	var btn := Button.new()
	btn.size = Vector2(72, 72)
	btn.focus_mode = Control.FOCUS_NONE
	var s := StyleBoxFlat.new()
	s.bg_color = accent
	s.set_corner_radius_all(36)
	s.border_color = accent.lightened(0.3)
	s.set_border_width_all(2)
	s.shadow_color = Color(accent.r, accent.g, accent.b, 0.45)
	s.shadow_size = 12
	btn.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = accent.lightened(0.12)
	btn.add_theme_stylebox_override("hover", sh)
	var sp := s.duplicate() as StyleBoxFlat
	sp.bg_color = accent.darkened(0.15)
	btn.add_theme_stylebox_override("pressed", sp)

	var mark := Line2D.new()
	mark.width = 7.0
	mark.default_color = Color.WHITE
	mark.joint_mode = Line2D.LINE_JOINT_ROUND
	mark.begin_cap_mode = Line2D.LINE_CAP_ROUND
	mark.end_cap_mode = Line2D.LINE_CAP_ROUND
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if kind == "check":
		mark.points = PackedVector2Array([
			Vector2(22, 38), Vector2(32, 48), Vector2(52, 24)])
		btn.add_child(mark)
	else:
		mark.points = PackedVector2Array([Vector2(24, 24), Vector2(48, 48)])
		btn.add_child(mark)
		var mark2 := Line2D.new()
		mark2.width = 7.0
		mark2.default_color = Color.WHITE
		mark2.begin_cap_mode = Line2D.LINE_CAP_ROUND
		mark2.end_cap_mode = Line2D.LINE_CAP_ROUND
		mark2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark2.points = PackedVector2Array([Vector2(48, 24), Vector2(24, 48)])
		btn.add_child(mark2)
	return btn

func _on_confirm_purchase(d: Dictionary, feedback: Label) -> void:
	var diff: String = d["diff"]
	if CoinsManager.purchase_level(diff):
		AudioManager.play_button_tone(int(d["orb"]), 0.2)
		_unlock_card_visual(diff)
		_close_popup()
	else:
		# Almost always: can't afford. Surface it and shake the dialog.
		feedback.text = "Not enough coins"
		if is_instance_valid(_popup_dialog):
			var base_x := _popup_dialog.position.x
			var sh := create_tween()
			for off: float in [-10.0, 9.0, -7.0, 5.0, 0.0]:
				sh.tween_property(_popup_dialog, "position:x", base_x + off, 0.05)

# Strip the lock badge + restore the title color on a card that was just bought.
func _unlock_card_visual(diff: String) -> void:
	for wrap in _cards:
		var btn := wrap.get_child(0) as Button
		if btn == null or String(btn.get_meta("diff", "")) != diff:
			continue
		if btn.has_meta("lock_badge"):
			var badge: Control = btn.get_meta("lock_badge")
			if is_instance_valid(badge):
				badge.queue_free()
			btn.remove_meta("lock_badge")
		if btn.has_meta("lock_seal"):
			var seal: Control = btn.get_meta("lock_seal")
			if is_instance_valid(seal):
				seal.queue_free()
			btn.remove_meta("lock_seal")
		var accent := _accent_for(diff)
		# Light the icon back up now that it's owned.
		if btn.has_meta("icon_panel"):
			var icon: Panel = btn.get_meta("icon_panel")
			var dia: float = btn.get_meta("icon_dia")
			if is_instance_valid(icon):
				icon.add_theme_stylebox_override("panel", _icon_stylebox(accent, dia, false))
		if btn.has_meta("icon_sym"):
			var sym: Node2D = btn.get_meta("icon_sym")
			if is_instance_valid(sym):
				sym.modulate = Color.WHITE
		var title: Label = btn.get_meta("title")
		if title:
			title.add_theme_color_override("font_color", accent.lightened(0.2))
			title.add_theme_color_override("font_outline_color", accent.lightened(0.2))
		return

func _accent_for(diff: String) -> Color:
	for d in DIFFS:
		if String(d["diff"]) == diff:
			var c: Color = d["accent"]
			return c
	return Color.WHITE

func _close_popup() -> void:
	if not _popup:
		return
	var popup := _popup
	_popup = null
	_popup_dialog = null
	_popup_backdrop = null
	var tw := create_tween()
	tw.tween_property(popup, "modulate:a", 0.0, 0.14)
	tw.tween_callback(popup.queue_free)

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

	# Keep an open buy-popup centered if the viewport changes under it.
	if _popup:
		_popup.size = sz
		if _popup_backdrop:
			_popup_backdrop.size = sz
		if _popup_dialog:
			_popup_dialog.position = (sz - Vector2(POPUP_W, POPUP_H)) * 0.5

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
