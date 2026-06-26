extends Control

# Premium main menu — a "magical space" home screen built entirely from Godot
# nodes + shaders + _draw() + tweens (no static images):
#   - a deep purple→blue gradient sky with twinkling stars (BG_SHADER)
#   - one large, thin glowing orbital ring of soft colored orbs behind everything
#   - the SIMON logo (white, soft-shadowed; the "O" is the 4-colour Simon wheel)
#     over a "MEMORY CHALLENGE" subtitle
#   - TOP-LEFT: a gold coin pill + a Daily Claim button (red notification dot)
#   - TOP-RIGHT: a compact profile card (avatar, username, sign-out, settings gear)
#   - CENTER: a floating grassy island carrying the big circular START orb
#   - LEFT / RIGHT: premium Shop and Leaderboard cards (illustration + CTA button)
#   - BOTTOM-CENTER: a small "How to Play" card
# Everything is laid out symmetrically and re-flowed in _layout() on resize.

const DailyClaimPopup := preload("res://daily_claim_popup.gd")
const CoinsPurchasePopup := preload("res://coins_purchase_popup.gd")

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

# Simon accent colors, reused to tint the scattered landmarks.
const ICON_BLUE := Color(0.23, 0.51, 0.96)
const ICON_GREEN := Color(0.18, 0.78, 0.39)
const ICON_PURPLE := Color(0.55, 0.36, 0.96)
const ICON_GOLD := Color(1.00, 0.78, 0.22)

# Premium-card chrome (shared by the Shop / Leaderboard / How-to cards).
const CARD_SIZE := Vector2(248.0, 300.0)
const HOWTO_SIZE := Vector2(396.0, 78.0)
const CARD_PURPLE := Color(0.26, 0.19, 0.50, 0.66)        # semi-transparent purple
const CARD_BORDER := Color(0.62, 0.52, 1.0, 0.45)
const CARD_GLOW := Color(0.40, 0.30, 0.85, 0.45)
const CTA_PURPLE := Color(0.55, 0.40, 0.95, 0.96)

# Procedural twilight sky for the world map: deep indigo at the top easing into a
# warm violet/magenta horizon, a big soft moon-aura behind the logo, a sparse
# twinkling star field that fades out where the island sits, and a vignette.
# Built with mix()/smoothstep() only (no ternary, which can fail to compile on
# the Mobile renderer).
const BG_SHADER := "
shader_type canvas_item;
uniform float aspect = 0.5;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec2 uv = UV;
	vec3 top = vec3(0.04, 0.05, 0.16);
	vec3 mid = vec3(0.16, 0.13, 0.36);
	vec3 low = vec3(0.34, 0.20, 0.42);
	vec3 col = mix(top, mid, smoothstep(0.0, 0.60, uv.y));
	col = mix(col, low, smoothstep(0.60, 1.0, uv.y));

	vec2 p = (uv - vec2(0.5, 0.32)) * vec2(aspect, 1.0);
	// big soft moon-aura behind the logo + island, gently breathing
	float breathe = 0.88 + 0.12 * sin(TIME * 0.5);
	col += vec3(0.40, 0.34, 0.60) * smoothstep(0.65, 0.0, length(p)) * 0.40 * breathe;
	// warm glow rising from the lower horizon
	col += vec3(0.65, 0.32, 0.42) * smoothstep(0.35, 0.0, abs(uv.y - 0.95)) * 0.18;

	// sparse twinkling stars, fading toward the bottom (under the island)
	vec2 g = floor(uv * vec2(120.0 * aspect, 120.0));
	float h = hash(g);
	float tw = 0.6 + 0.4 * sin(TIME * 2.0 + h * 30.0);
	float star = smoothstep(0.991, 1.0, h) * tw;
	col += vec3(0.90, 0.92, 1.0) * star * smoothstep(0.75, 0.10, uv.y);

	col *= mix(0.62, 1.0, smoothstep(1.15, 0.20, length((uv - vec2(0.5)) * vec2(aspect, 1.0))));
	COLOR = vec4(col, 1.0);
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
# The START orb is a clickable landmark widget {wrap, btn, art, drawer} floating in
# the center. The Shop / Leaderboard / How-to navigation are premium cards
# ({wrap} dicts) flanking it.
var _start_lm: Dictionary = {}
var _shop_card: Dictionary = {}
var _ranks_card: Dictionary = {}
var _howto_card: Dictionary = {}
var _profile_card: Panel
var _signing_in := false
# Top-left coin pill (signed-in only). Mirrors the in-game HUD style but lives
# at a fixed corner here. Daily-claim button sits just under it.
var _coin_pill: Panel
var _coin_lbl: Label
var _coin_plus_btn: Button       # opens the coin-pack purchase popup
var _coin_loading_tween: Tween   # animates "." -> ".." -> "..." while CoinsManager loads
var _coin_loading_idx: int = 0
var _daily_btn: Button
var _daily_badge: Panel
var _settings_music_btn: Button
# Tiny, low-key credit line pinned to the very bottom edge.
var _credits: Label

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
	_build_cards()
	_build_start()
	_build_profile_card()
	_build_credits()
	if FirebaseManager.is_signed_in():
		_build_coin_pill()
		_build_daily_claim_button()
		# Opening the home screen is the heartbeat of the login-streak system.
		# If the wallet hasn't finished loading yet, deferred call once it does.
		if CoinsManager.is_loaded():
			CoinsManager.register_login()
		else:
			CoinsManager.loaded.connect(CoinsManager.register_login, CONNECT_ONE_SHOT)

	_layout()
	get_viewport().size_changed.connect(_layout)
	_start_animations()
	AudioManager.play_bg_music()

	# On the first home open of this launch, a signed-out player is asked whether
	# to sign in or continue as a guest. The flag lives on the (persistent)
	# GameManager so returning home later in the same session won't re-prompt.
	if not FirebaseManager.is_signed_in() and not game_manager.welcome_prompt_shown:
		game_manager.welcome_prompt_shown = true
		_show_welcome_popup()

# ---------------- background ----------------

# The home screen always wears its own deep-space sky now: equipped shop themes
# are painted only behind the gameplay screen (BackgroundManager.is_themed() is
# false everywhere else), so there's no global theme to defer to here.
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

# ---------------- premium navigation cards ----------------

# Build the three flanking cards: Shop (left) + Leaderboard (right) + How-to
# (bottom). Shop is shown even when signed out (its action prompts sign-in) so the
# layout stays symmetric.
func _build_cards() -> void:
	_shop_card = _build_card("SHOP", _draw_shop_card, "Go to Shop", _draw_cart, _on_shop)
	_ranks_card = _build_card("LEADERBOARD", _draw_ranks_card, "View Leaderboard", _draw_chart, _on_leaderboards)
	# Podium rank numerals, overlaid on the leaderboard illustration.
	_card_numeral(_ranks_card, "1", 22, Color(0.34, 0.24, 0.05), Vector2(98, 159), 40)
	_card_numeral(_ranks_card, "2", 18, Color(0.30, 0.31, 0.36), Vector2(29, 175), 36)
	_card_numeral(_ranks_card, "3", 18, Color(0.36, 0.24, 0.10), Vector2(167, 189), 36)
	_build_howto_card()

# A premium navigation card: rounded translucent-purple panel with a title, a
# procedural illustration, and a bottom call-to-action pill (icon + label). The
# whole card is tappable (transparent Button overlay) and scales gently on hover.
func _build_card(title: String, draw_cb: Callable, cta: String, icon_cb: Callable, action: Callable) -> Dictionary:
	var wrap := Control.new()
	wrap.size = CARD_SIZE
	wrap.custom_minimum_size = CARD_SIZE
	wrap.pivot_offset = CARD_SIZE * 0.5
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wrap)

	# Inner floater carries the whole card so the idle bob (position:y) is free of
	# the layout (which positions `wrap`) and the hover/press scale (on `wrap`).
	var floater := Control.new()
	floater.size = CARD_SIZE
	floater.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(floater)

	var panel := _card_panel(CARD_SIZE, CARD_PURPLE, CARD_BORDER, CARD_GLOW)
	floater.add_child(panel)

	var t := _card_title(title, Vector2(0, 16), CARD_SIZE.x)
	panel.add_child(t)

	var art := Control.new()
	art.size = CARD_SIZE
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var drawer := Control.new()
	drawer.size = CARD_SIZE
	drawer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drawer.draw.connect(draw_cb.bind(drawer))
	art.add_child(drawer)
	panel.add_child(art)

	var pill := _cta_pill(Vector2(CARD_SIZE.x - 32, 42), cta, icon_cb)
	pill.position = Vector2(16, CARD_SIZE.y - 56)
	panel.add_child(pill)

	var btn := _overlay_button(CARD_SIZE)
	btn.mouse_entered.connect(_on_card_hover.bind(wrap, true))
	btn.mouse_exited.connect(_on_card_hover.bind(wrap, false))
	btn.button_down.connect(_on_card_press.bind(wrap, true))
	btn.button_up.connect(_on_card_press.bind(wrap, false))
	btn.pressed.connect(action)
	floater.add_child(btn)

	return {"wrap": wrap, "art": art, "drawer": drawer, "floater": floater}

# The bottom "HOW TO PLAY" strip: a "?" badge, a title + subtitle, and a round
# arrow affordance on the right. Whole strip is tappable.
func _build_howto_card() -> void:
	var wrap := Control.new()
	wrap.size = HOWTO_SIZE
	wrap.custom_minimum_size = HOWTO_SIZE
	wrap.pivot_offset = HOWTO_SIZE * 0.5
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wrap)

	var panel := _card_panel(HOWTO_SIZE, CARD_PURPLE, CARD_BORDER, CARD_GLOW)
	wrap.add_child(panel)

	# "?" badge
	var badge := _circle_panel(50.0, ICON_PURPLE, Color(0.72, 0.58, 1.0, 0.9))
	badge.position = Vector2(16, 14)
	panel.add_child(badge)
	var q := Label.new()
	q.text = "?"
	q.add_theme_font_size_override("font_size", 30)
	q.add_theme_color_override("font_color", Color.WHITE)
	q.set_anchors_preset(Control.PRESET_FULL_RECT)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	q.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(q)

	var title := Label.new()
	title.text = "HOW TO PLAY"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_color_override("font_shadow_color", Color(0.45, 0.40, 1.0, 0.5))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 0)
	title.add_theme_constant_override("shadow_outline_size", 5)
	title.position = Vector2(80, 12)
	title.size = Vector2(240, 30)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(title)

	var sub := Label.new()
	sub.text = "Learn the rules and start playing"
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Color(0.80, 0.78, 1.0, 0.92))
	sub.position = Vector2(80, 42)
	sub.size = Vector2(270, 22)
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(sub)

	# round arrow affordance on the right
	var arrow := _circle_panel(40.0, CTA_PURPLE, Color(0.45, 0.30, 0.95, 0.55))
	arrow.position = Vector2(HOWTO_SIZE.x - 16 - 40, 19)
	panel.add_child(arrow)
	var ad := Control.new()
	ad.size = Vector2(24, 24)
	ad.position = Vector2(8, 8)
	ad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ad.draw.connect(_draw_arrow.bind(ad))
	arrow.add_child(ad)

	var btn := _overlay_button(HOWTO_SIZE)
	btn.mouse_entered.connect(_on_card_hover.bind(wrap, true))
	btn.mouse_exited.connect(_on_card_hover.bind(wrap, false))
	btn.button_down.connect(_on_card_press.bind(wrap, true))
	btn.button_up.connect(_on_card_press.bind(wrap, false))
	btn.pressed.connect(_on_how)
	wrap.add_child(btn)

	_howto_card = {"wrap": wrap}

# Rounded translucent panel used as the body of every card.
func _card_panel(size: Vector2, bg: Color, border: Color, glow: Color) -> Panel:
	var p := Panel.new()
	p.size = size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.set_corner_radius_all(22)
	st.border_color = border
	st.set_border_width_all(2)
	st.shadow_color = glow
	st.shadow_size = 16
	p.add_theme_stylebox_override("panel", st)
	return p

# A filled circular Panel (used for badges / round buttons).
func _circle_panel(d: float, col: Color, glow: Color) -> Panel:
	var p := Panel.new()
	p.size = Vector2(d, d)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = col
	st.set_corner_radius_all(int(d * 0.5))
	st.shadow_color = glow
	st.shadow_size = 10
	p.add_theme_stylebox_override("panel", st)
	return p

func _card_title(txt: String, pos: Vector2, w: float) -> Label:
	var t := Label.new()
	t.text = txt
	t.add_theme_font_size_override("font_size", 28)
	t.add_theme_color_override("font_color", Color.WHITE)
	t.add_theme_color_override("font_shadow_color", Color(0.45, 0.40, 1.0, 0.5))
	t.add_theme_constant_override("shadow_offset_x", 0)
	t.add_theme_constant_override("shadow_offset_y", 0)
	t.add_theme_constant_override("shadow_outline_size", 6)
	t.position = pos
	t.size = Vector2(w, 36)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

# Bottom call-to-action pill: a solid purple rounded bar with a left icon + label.
func _cta_pill(size: Vector2, txt: String, icon_cb: Callable) -> Panel:
	var pill := Panel.new()
	pill.size = size
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = CTA_PURPLE
	st.set_corner_radius_all(int(size.y * 0.5))
	st.shadow_color = Color(0.45, 0.30, 0.95, 0.5)
	st.shadow_size = 8
	pill.add_theme_stylebox_override("panel", st)

	var ic := Control.new()
	ic.size = Vector2(24, 24)
	ic.position = Vector2(18, (size.y - 24) * 0.5)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.draw.connect(icon_cb.bind(ic))
	pill.add_child(ic)

	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.position = Vector2(48, 0)
	l.size = Vector2(size.x - 56, size.y)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(l)
	return pill

# Centered numeral overlaid on the leaderboard card's podium illustration.
func _card_numeral(card: Dictionary, txt: String, fsize: int, col: Color, pos: Vector2, box: float) -> void:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	l.position = pos
	l.size = Vector2(box, box)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(card["art"] as Control).add_child(l)

# A full-size transparent Button used to make a whole card tappable.
func _overlay_button(size: Vector2) -> Button:
	var btn := Button.new()
	btn.size = size
	btn.focus_mode = Control.FOCUS_NONE
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(s, empty)
	return btn

func _on_card_hover(wrap: Control, entered: bool) -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(wrap, "scale", Vector2.ONE * (1.03 if entered else 1.0), 0.16) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(wrap, "modulate", Color(1.10, 1.10, 1.10) if entered else Color.WHITE, 0.16)

func _on_card_press(wrap: Control, down: bool) -> void:
	var tw := create_tween()
	tw.tween_property(wrap, "scale", Vector2.ONE * (0.97 if down else 1.0), 0.10) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

# ---------------- START orb ----------------

const START_SIZE := Vector2(300.0, 300.0)

func _build_start() -> void:
	_start_lm = _landmark(START_SIZE, _draw_play_orb, _on_start)
	_lm_label(_start_lm, "START", 36, Color.WHITE, ICON_BLUE.lightened(0.25), Vector2(0, 272), Vector2(START_SIZE.x, 48))

# Build one clickable landmark: a transparent Button (input) wrapping an `art`
# Control (scaled on hover/press, breathing while idle) which holds the procedural
# `drawer`. Returns the pieces so callers can attach labels and the layout can
# position the wrapper.
func _landmark(art_size: Vector2, draw_cb: Callable, cb: Callable) -> Dictionary:
	var wrap := Control.new()
	wrap.size = art_size
	wrap.custom_minimum_size = art_size
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wrap)

	var btn := Button.new()
	btn.size = art_size
	btn.focus_mode = Control.FOCUS_NONE
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(s, empty)
	wrap.add_child(btn)

	var art := Control.new()
	art.size = art_size
	art.pivot_offset = art_size * 0.5
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(art)

	var drawer := Control.new()
	drawer.size = art_size
	drawer.pivot_offset = art_size * 0.5
	drawer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drawer.draw.connect(draw_cb.bind(drawer))
	art.add_child(drawer)

	btn.mouse_entered.connect(_on_lm_hover.bind(art, true))
	btn.mouse_exited.connect(_on_lm_hover.bind(art, false))
	btn.button_down.connect(_on_lm_press.bind(art))
	btn.button_up.connect(_on_lm_release.bind(art))
	btn.pressed.connect(cb)
	return {"wrap": wrap, "btn": btn, "art": art, "drawer": drawer}

# A centered, softly glowing text label overlaid on a landmark's art.
func _lm_label(lm: Dictionary, txt: String, fsize: int, col: Color, glow: Color,
		pos: Vector2, size: Vector2) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	if glow.a > 0.0:
		l.add_theme_color_override("font_shadow_color", glow)
		l.add_theme_constant_override("shadow_offset_x", 0)
		l.add_theme_constant_override("shadow_offset_y", 0)
		l.add_theme_constant_override("shadow_outline_size", 7)
	l.position = pos
	l.size = size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lm["art"].add_child(l)
	return l

# ---------------- procedural art ----------------

# Soft layered halo: large faint circle first, smaller brighter ones on top.
func _glow(c: Control, center: Vector2, radius: float, col: Color, layers: int) -> void:
	for i in layers:
		var t := float(i) / float(layers - 1)            # 0 outer .. 1 inner
		var r: float = lerp(radius, radius * 0.2, t)
		var a: float = lerp(0.04, 0.16, t)
		c.draw_circle(center, r, Color(col.r, col.g, col.b, a))

func _ellipse_pts(center: Vector2, rx: float, ry: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts

# Big glossy PLAY orb ringed by the four Simon colors, with a white play triangle.
# Centered in a 300x300 art box (see START_SIZE).
func _draw_play_orb(c: Control) -> void:
	var ctr := Vector2(150.0, 150.0)
	var rad := 104.0
	_glow(c, ctr, rad + 60.0, Color(0.35, 0.60, 1.0), 7)

	# four-color Simon ring
	var ringR := rad + 14.0
	var cols := [Color(0.97, 0.78, 0.22), Color(0.88, 0.22, 0.24),
		Color(0.20, 0.70, 0.34), Color(0.24, 0.50, 0.95)]
	var gap := deg_to_rad(10.0)
	for i in 4:
		var a0 := -PI * 0.75 + i * PI * 0.5 + gap * 0.5
		var a1 := -PI * 0.75 + (i + 1) * PI * 0.5 - gap * 0.5
		c.draw_arc(ctr, ringR, a0, a1, 26, cols[i], 12.0, true)

	# orb body (vertical gradient sphere)
	var body := PackedVector2Array()
	var bcol := PackedColorArray()
	var n := 46
	for i in n:
		var a := TAU * float(i) / float(n)
		var p := ctr + Vector2(cos(a), sin(a)) * rad
		body.append(p)
		var t: float = clampf((p.y - (ctr.y - rad)) / (2.0 * rad), 0.0, 1.0)
		bcol.append(Color(0.40, 0.68, 1.0).lerp(Color(0.08, 0.24, 0.62), t))
	c.draw_polygon(body, bcol)

	# gloss highlight + play triangle (nudged right for optical balance)
	c.draw_circle(ctr + Vector2(-30, -34), 40.0, Color(1, 1, 1, 0.16))
	c.draw_circle(ctr + Vector2(-34, -40), 21.0, Color(1, 1, 1, 0.22))
	var tc := ctr + Vector2(11, 0)
	c.draw_colored_polygon(PackedVector2Array([
		tc + Vector2(-29, -40), tc + Vector2(-29, 40), tc + Vector2(40, 0)]), Color(1, 1, 1, 0.96))

# Leaderboard illustration: a 3-tier podium (silver / bronze / gold) with a gold
# trophy on the winner's block. Drawn into the card; offset to centre in the art.
func _draw_ranks_card(c: Control) -> void:
	c.draw_set_transform(Vector2(-12, -9), 0.0, Vector2.ONE)
	_draw_ranks(c)

func _draw_ranks(c: Control) -> void:
	_glow(c, Vector2(130, 150), 150.0, Color(1.0, 0.82, 0.35), 6)
	var base := 232.0
	_draw_block(c, 28.0, 94.0, 176.0, base, Color(0.78, 0.80, 0.86))   # 2nd - silver
	_draw_block(c, 166.0, 232.0, 190.0, base, Color(0.82, 0.55, 0.30)) # 3rd - bronze
	_draw_block(c, 97.0, 163.0, 150.0, base, Color(0.96, 0.80, 0.32))  # 1st - gold (front)
	_draw_trophy(c, Vector2(130.0, 150.0))

# One pseudo-3D podium block: top face + right side face (receding up-right) + front.
func _draw_block(c: Control, x0: float, x1: float, top: float, base: float, front: Color) -> void:
	var dx := 12.0
	var dy := 12.0
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(x0, top), Vector2(x1, top),
		Vector2(x1 + dx, top - dy), Vector2(x0 + dx, top - dy)]), front.lightened(0.18))
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(x1, top), Vector2(x1 + dx, top - dy),
		Vector2(x1 + dx, base - dy), Vector2(x1, base)]), front.darkened(0.22))
	c.draw_rect(Rect2(x0, top, x1 - x0, base - top), front)
	c.draw_rect(Rect2(x0, base - 10.0, x1 - x0, 10.0), front.darkened(0.15))

# Gold trophy: pedestal, stem, cup bowl (gradient), two handles, rim shine + gem.
func _draw_trophy(c: Control, bc: Vector2) -> void:
	var g_lt := Color(1.0, 0.88, 0.42)
	var g_md := Color(0.88, 0.66, 0.18)
	var g_dk := Color(0.62, 0.44, 0.12)
	c.draw_rect(Rect2(bc.x - 26, bc.y - 10, 52, 10), g_md)        # base tier 1
	c.draw_rect(Rect2(bc.x - 18, bc.y - 20, 36, 12), g_dk)        # base tier 2
	c.draw_rect(Rect2(bc.x - 7, bc.y - 34, 14, 16), g_md)         # stem

	var cup_top := bc.y - 78.0
	var cup_bot := bc.y - 34.0
	var cup := PackedVector2Array([
		Vector2(bc.x - 30, cup_top), Vector2(bc.x + 30, cup_top),
		Vector2(bc.x + 26, cup_top + 18), Vector2(bc.x + 12, cup_bot),
		Vector2(bc.x - 12, cup_bot), Vector2(bc.x - 26, cup_top + 18)])
	var ccol := PackedColorArray()
	for pt in cup:
		var t: float = clampf((pt.y - cup_top) / (cup_bot - cup_top), 0.0, 1.0)
		ccol.append(g_lt.lerp(g_dk, t))
	c.draw_polygon(cup, ccol)

	c.draw_arc(Vector2(bc.x - 26, cup_top + 16), 16.0, PI * 0.5, PI * 1.5, 16, g_md, 6.0, true)
	c.draw_arc(Vector2(bc.x + 26, cup_top + 16), 16.0, -PI * 0.5, PI * 0.5, 16, g_md, 6.0, true)
	c.draw_line(Vector2(bc.x - 26, cup_top + 3), Vector2(bc.x + 26, cup_top + 3), g_lt, 3.0, true)
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(bc.x - 15, cup_top + 6), Vector2(bc.x - 7, cup_top + 6),
		Vector2(bc.x - 10, cup_bot - 6), Vector2(bc.x - 17, cup_bot - 8)]), Color(1, 1, 1, 0.22))
	var gy := cup_top + 22.0                                     # little gem on the cup
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(bc.x, gy - 8), Vector2(bc.x + 6, gy),
		Vector2(bc.x, gy + 8), Vector2(bc.x - 6, gy)]), Color(1, 0.97, 0.7))

# Shop illustration: storefront, drawn into the card; offset to centre in the art.
func _draw_shop_card(c: Control) -> void:
	c.draw_set_transform(Vector2(-16, -2), 0.0, Vector2.ONE)
	_draw_shop(c)

# Storefront: walls, a dark sign header, a striped/scalloped awning, two warm
# display windows and a glowing doorway.
func _draw_shop(c: Control) -> void:
	var x0 := 40.0
	var x1 := 240.0
	_glow(c, Vector2(140, 150), 130.0, Color(1.0, 0.82, 0.45), 6)
	c.draw_rect(Rect2(x0, 76, x1 - x0, 146), Color(0.93, 0.90, 0.84))   # walls
	c.draw_rect(Rect2(x0, 76, x1 - x0, 30), Color(0.20, 0.24, 0.40))    # sign header band
	_draw_awning(c, x0 + 4.0, x1 - 4.0, 106.0)
	# doorway
	c.draw_rect(Rect2(122, 156, 36, 66), Color(0.34, 0.24, 0.20))
	c.draw_rect(Rect2(126, 160, 28, 30), Color(1.0, 0.80, 0.45, 0.85))
	c.draw_circle(Vector2(151, 192), 2.5, Color(0.95, 0.86, 0.5))
	_draw_window(c, Rect2(56, 150, 46, 40))
	_draw_window(c, Rect2(178, 150, 46, 40))
	c.draw_rect(Rect2(x0, 220, x1 - x0, 5), Color(0.0, 0.0, 0.0, 0.18))  # ground shadow

# Striped awning with a scalloped lower edge.
func _draw_awning(c: Control, ax0: float, ax1: float, ay: float) -> void:
	var h := 26.0
	var stripes := 8
	var w := (ax1 - ax0) / float(stripes)
	var a_cream := Color(0.96, 0.93, 0.88)
	var a_red := Color(0.86, 0.30, 0.34)
	for i in stripes:
		var sx := ax0 + i * w
		var col := a_red if i % 2 == 0 else a_cream
		c.draw_rect(Rect2(sx, ay, w, h), col)
		c.draw_circle(Vector2(sx + w * 0.5, ay + h), 9.0, col)        # scallop
	c.draw_rect(Rect2(ax0, ay - 4.0, ax1 - ax0, 5.0), Color(0.55, 0.16, 0.20))  # trim

# Warm glowing window with a cross frame.
func _draw_window(c: Control, r: Rect2) -> void:
	c.draw_rect(r, Color(1.0, 0.82, 0.5, 0.9))
	c.draw_rect(r, Color(0.30, 0.22, 0.18), false, 3.0)
	var mx := r.position.x + r.size.x * 0.5
	var my := r.position.y + r.size.y * 0.5
	c.draw_line(Vector2(mx, r.position.y), Vector2(mx, r.position.y + r.size.y), Color(0.30, 0.22, 0.18), 2.0)
	c.draw_line(Vector2(r.position.x, my), Vector2(r.position.x + r.size.x, my), Color(0.30, 0.22, 0.18), 2.0)

# ---------------- small icons ----------------

func _draw_cart(c: Control) -> void:
	var col := Color.WHITE
	c.draw_line(Vector2(1, 3), Vector2(5, 4), col, 2.0)
	c.draw_polyline(PackedVector2Array([
		Vector2(5, 5), Vector2(23, 5), Vector2(20, 15), Vector2(8, 15), Vector2(5, 4)]), col, 2.0, true)
	c.draw_circle(Vector2(9, 20), 1.9, col)
	c.draw_circle(Vector2(19, 20), 1.9, col)

func _draw_chart(c: Control) -> void:
	var col := Color.WHITE
	c.draw_rect(Rect2(2, 13, 5, 9), col)
	c.draw_rect(Rect2(9, 7, 5, 15), col)
	c.draw_rect(Rect2(16, 3, 5, 19), col)

func _draw_arrow(c: Control) -> void:
	c.draw_polyline(PackedVector2Array([Vector2(8, 5), Vector2(16, 12), Vector2(8, 19)]),
		Color.WHITE, 3.0, true)

# Small gift box glyph drawn inside the daily-claim disc: cream lid + body
# with a vertical ribbon and a bow knot on top. Scales to the 34px disc.
func _draw_gift_icon(c: Control) -> void:
	var ctr := c.size * 0.5
	var box_w := 18.0
	var box_h := 14.0
	var lid_h := 5.0
	var box_top := ctr.y - box_h * 0.5 + 1.0
	var cream := Color(1.0, 0.96, 0.86)
	var ribbon := Color(0.95, 0.85, 0.30)
	# Body + lid
	c.draw_rect(Rect2(ctr.x - box_w * 0.5, box_top, box_w, box_h), cream)
	c.draw_rect(Rect2(ctr.x - box_w * 0.5 - 1.0, box_top - lid_h, box_w + 2.0, lid_h), cream.darkened(0.06))
	# Vertical ribbon
	c.draw_rect(Rect2(ctr.x - 1.5, box_top - lid_h, 3.0, box_h + lid_h), ribbon)
	# Bow knot — two small ellipses
	c.draw_circle(Vector2(ctr.x - 3.5, box_top - lid_h - 1.0), 3.0, ribbon)
	c.draw_circle(Vector2(ctr.x + 3.5, box_top - lid_h - 1.0), 3.0, ribbon)
	c.draw_circle(Vector2(ctr.x, box_top - lid_h - 1.0), 1.6, ribbon.darkened(0.20))

# A right-pointing ">" chevron drawn dead-center in the daily-claim arrow disc.
# Two antialiased strokes meeting at the right vertex. A bare bbox-centered
# chevron looks shoved left because its mass (the two open arm-ends) sits on
# the left while only the single vertex pokes right — its centroid lands at
# x = ctr - reach/3. We nudge the whole mark right by reach/3 so that centroid
# falls on the disc's midline and it reads as centered.
func _draw_daily_chevron(c: Control) -> void:
	var ctr := c.size * 0.5
	var half_h := c.size.y * 0.22       # vertical reach of each arm
	var reach := c.size.x * 0.16        # horizontal half-span
	var nudge := reach / 3.0            # optical-centroid correction
	var col := Color.WHITE
	var w := 3.0
	var tip := Vector2(ctr.x + reach + nudge, ctr.y)
	var top := Vector2(ctr.x - reach + nudge, ctr.y - half_h)
	var bot := Vector2(ctr.x - reach + nudge, ctr.y + half_h)
	c.draw_polyline(PackedVector2Array([top, tip, bot]), col, w, true)

func _draw_gear(c: Control) -> void:
	var col := Color(0.82, 0.84, 0.96)
	var ctr := Vector2(12, 12)
	for i in 8:
		var a := TAU * float(i) / 8.0
		var d := Vector2(cos(a), sin(a))
		c.draw_line(ctr + d * 5.0, ctr + d * 9.0, col, 2.6)
	c.draw_arc(ctr, 6.0, 0.0, TAU, 24, col, 2.4, true)
	c.draw_circle(ctr, 2.2, col)

func _on_lm_hover(art: Control, entered: bool) -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(art, "scale", Vector2.ONE * (1.06 if entered else 1.0), 0.16) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(art, "modulate", Color(1.12, 1.12, 1.12) if entered else Color.WHITE, 0.16)

func _on_lm_press(art: Control) -> void:
	create_tween().tween_property(art, "scale", Vector2.ONE * 0.94, 0.09) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _on_lm_release(art: Control) -> void:
	# Bounce back to rest (touch has no lingering hover, so settle at 1.0).
	var tw := create_tween().set_parallel(true)
	tw.tween_property(art, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(art, "modulate", Color.WHITE, 0.18)

# ---------------- credits ----------------

# A single faint, lightweight line pinned to the bottom edge. Lavender to match the
# subtitle, low alpha + a whisper of glow so it reads as a quiet signature — never
# competing with the START orb or the cards above it.
func _build_credits() -> void:
	_credits = Label.new()
	_credits.text = "Game by Raviach Studios   ·   Music by @drorbardavid"
	_credits.add_theme_font_size_override("font_size", 13)
	_credits.add_theme_color_override("font_color", Color(0.74, 0.72, 1.0, 0.45))
	_credits.add_theme_color_override("font_shadow_color", Color(0.40, 0.36, 1.0, 0.22))
	_credits.add_theme_constant_override("shadow_offset_x", 0)
	_credits.add_theme_constant_override("shadow_offset_y", 0)
	_credits.add_theme_constant_override("shadow_outline_size", 4)
	_credits.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_credits.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_credits.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_credits)

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

	# orbit: centered, radius ~40% of screen width — one large ring behind it all
	var r := sz.x * 0.40
	if _orbit:
		_orbit.position = Vector2(cx, cy)
		_rebuild_ring(r)
		for i in _orbs.size():
			var a: float = -PI * 0.5 + i * TAU / _orbs.size()
			_orbs[i].position = Vector2(cos(a), sin(a)) * r

	# logo: focal point, top-center
	if _logo_box:
		_logo_box.position = Vector2(cx - _logo_box.size.x * 0.5, sz.y * 0.05)

	# the big START orb floats in the center; side cards flank it; the how-to card
	# sits below (placed last so it always wins overlapping taps).
	var side_cy := sz.y * 0.57
	_place_card(_shop_card, Vector2(sz.x * 0.035, side_cy - CARD_SIZE.y * 0.5))
	_place_card(_ranks_card, Vector2(sz.x - sz.x * 0.035 - CARD_SIZE.x, side_cy - CARD_SIZE.y * 0.5))
	_place_card(_howto_card, Vector2(cx - HOWTO_SIZE.x * 0.5, sz.y - HOWTO_SIZE.y - sz.y * 0.03))

	_place_lm(_start_lm, Vector2(cx, sz.y * 0.50))

	if _profile_card:
		_profile_card.position = Vector2(sz.x - _profile_card.size.x - 16.0, 14.0)

	# credits tuck into the bottom-right corner, right-aligned with a small margin
	if _credits:
		_credits.size = Vector2(sz.x - 32.0, 18.0)
		_credits.position = Vector2(16.0, sz.y - 22.0)

# Position a card's wrapper at `pos` (top-left). No-op for an absent card.
func _place_card(card: Dictionary, pos: Vector2) -> void:
	if card.is_empty():
		return
	(card["wrap"] as Control).position = pos

# Center a landmark's wrapper on `center`.
func _place_lm(lm: Dictionary, center: Vector2) -> void:
	if lm.is_empty():
		return
	var wrap: Control = lm["wrap"]
	wrap.position = center - wrap.size * 0.5

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

	# the Shop + Leaderboard cards gently bob in place (slightly out of phase) so the
	# scene feels alive; the bob lives on each card's inner floater.
	var bob_cards := [_shop_card, _ranks_card]
	for i in bob_cards.size():
		var card: Dictionary = bob_cards[i]
		if card.is_empty():
			continue
		var floater: Control = card["floater"]
		var dur := 2.8 + i * 0.6
		var amp := -8.0 - i * 2.0
		var fl := create_tween().set_loops()
		fl.tween_property(floater, "position:y", amp, dur) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		fl.tween_property(floater, "position:y", 0.0, dur) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# the PLAY orb breathes — its inner drawer scales, independent of the hover/press
	# scaling applied to the outer art node, so the two never fight.
	if not _start_lm.is_empty():
		var orb: Control = _start_lm["drawer"]
		var br := create_tween().set_loops()
		br.tween_property(orb, "scale", Vector2.ONE * 1.05, 1.1) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		br.tween_property(orb, "scale", Vector2.ONE, 1.1) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

# ---------------- profile card (top-right) ----------------

# Compact account card: avatar + username + a sign-in/out action + a settings
# gear. Shown for both guests and signed-in players so the corner stays balanced.
func _build_profile_card() -> void:
	const W := 228.0
	const H := 84.0
	_profile_card = _card_panel(Vector2(W, H), Color(0.06, 0.07, 0.18, 0.82),
		Color(0.45, 0.50, 1.0, 0.40), Color(0.30, 0.34, 0.85, 0.45))
	add_child(_profile_card)

	var signed := FirebaseManager.is_signed_in() and FirebaseManager.has_display_name()
	var uname := FirebaseManager.display_name if signed else "Guest"

	var nl := Label.new()
	nl.text = uname
	nl.add_theme_font_size_override("font_size", 20)
	nl.add_theme_color_override("font_color", GOLD)
	nl.position = Vector2(18, 14)
	nl.size = Vector2(W - 18 - 42, 30)
	nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_profile_card.add_child(nl)

	var act := Button.new()
	act.text = "sign out" if signed else "sign in"
	act.flat = true
	act.focus_mode = Control.FOCUS_NONE
	act.add_theme_font_size_override("font_size", 14)
	act.add_theme_color_override("font_color", Color(0.62, 0.64, 0.82) if signed else Color(0.40, 0.78, 1.0))
	act.add_theme_color_override("font_hover_color", Color(1.0, 0.45, 0.45) if signed else Color(0.62, 0.90, 1.0))
	act.add_theme_color_override("font_pressed_color", Color(0.85, 0.25, 0.25) if signed else Color(0.30, 0.62, 0.95))
	act.position = Vector2(14, 46)
	act.size = Vector2(120, 26)
	act.alignment = HORIZONTAL_ALIGNMENT_LEFT
	act.pressed.connect(_on_sign_out if signed else _on_sign_in)
	_profile_card.add_child(act)

	var gear := Button.new()
	gear.size = Vector2(30, 30)
	gear.position = Vector2(W - 38, 12)
	gear.focus_mode = Control.FOCUS_NONE
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus"]:
		gear.add_theme_stylebox_override(s, empty)
	var gd := Control.new()
	gd.size = Vector2(24, 24)
	gd.position = Vector2(3, 3)
	gd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gd.draw.connect(_draw_gear.bind(gd))
	gear.add_child(gd)
	gear.pressed.connect(_show_settings_popup)
	_profile_card.add_child(gear)

# ---------------- coin pill + daily claim (top-left) ----------------

# Glassmorphism currency pill anchored at the top-LEFT. Dark navy pill with a
# thin neon border and a soft outer purple aura; gold coin disc on the left,
# bold comma-formatted balance in the middle, a hairline separator, and a small
# gold circular "+" on the far right that opens the purchase popup. Stays live
# via CoinsManager.balance_changed.
const COIN_PILL_W := 230.0
const COIN_PILL_H := 56.0
const HUD_TOP := 18.0
const HUD_LEFT := 18.0
const HUD_GAP := 16.0

func _build_coin_pill() -> void:
	_coin_pill = Panel.new()
	_coin_pill.position = Vector2(HUD_LEFT, HUD_TOP)
	_coin_pill.size = Vector2(COIN_PILL_W, COIN_PILL_H)
	_coin_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	# Dark navy glass face. The thin neon-blue border + purple outer shadow
	# read as a sci-fi pill rather than a flat chip.
	st.bg_color = Color(0.03, 0.04, 0.12, 0.90)
	st.set_corner_radius_all(int(COIN_PILL_H * 0.5))
	st.border_color = Color(0.55, 0.62, 1.0, 0.55)
	st.set_border_width_all(1)
	# Outer purple aura.
	st.shadow_color = Color(0.55, 0.36, 1.0, 0.40)
	st.shadow_size = 14
	st.shadow_offset = Vector2(0, 2)
	_coin_pill.add_theme_stylebox_override("panel", st)
	add_child(_coin_pill)

	# Glossy gold coin disc — rim + face + highlight. Soft golden glow halo
	# behind it sells the "premium currency" read.
	var d := 40.0
	var disc_x := 8.0
	var disc_y := (COIN_PILL_H - d) * 0.5
	var glow := Panel.new()
	glow.size = Vector2(d + 12, d + 12)
	glow.position = Vector2(disc_x - 6, disc_y - 6)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gs := StyleBoxFlat.new()
	gs.bg_color = Color(1.0, 0.78, 0.22, 0.0)
	gs.set_corner_radius_all(int((d + 12) * 0.5))
	gs.shadow_color = Color(1.0, 0.78, 0.22, 0.55)
	gs.shadow_size = 10
	glow.add_theme_stylebox_override("panel", gs)
	_coin_pill.add_child(glow)

	var disc := Panel.new()
	disc.size = Vector2(d, d)
	disc.position = Vector2(disc_x, disc_y)
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ds := StyleBoxFlat.new()
	ds.bg_color = Color(1.0, 0.80, 0.22)
	ds.set_corner_radius_all(int(d * 0.5))
	ds.border_color = Color(1.0, 0.95, 0.62)
	ds.set_border_width_all(2)
	disc.add_theme_stylebox_override("panel", ds)
	_coin_pill.add_child(disc)
	# Highlight crescent: tiny lighter disc nudged to the top-left for gloss.
	var hl := Panel.new()
	var hd := d * 0.38
	hl.size = Vector2(hd, hd)
	hl.position = Vector2(d * 0.18, d * 0.14)
	hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hs := StyleBoxFlat.new()
	hs.bg_color = Color(1.0, 1.0, 0.85, 0.55)
	hs.set_corner_radius_all(int(hd * 0.5))
	hl.add_theme_stylebox_override("panel", hs)
	disc.add_child(hl)
	var glyph := Label.new()
	glyph.text = "$"
	glyph.add_theme_font_size_override("font_size", 24)
	glyph.add_theme_color_override("font_color", Color(0.40, 0.24, 0.02))
	glyph.add_theme_color_override("font_outline_color", Color(0.40, 0.24, 0.02))
	glyph.add_theme_constant_override("outline_size", 2)
	glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.add_child(glyph)

	# Plus-button geometry, used to compute label width + separator position.
	var plus_d := 36.0
	var plus_x := COIN_PILL_W - plus_d - 8.0
	var sep_x := plus_x - 10.0

	# Hairline vertical separator just before the "+" disc — gives the pill the
	# segmented "balance / action" reading from the reference art.
	var sep := ColorRect.new()
	sep.color = Color(0.65, 0.72, 1.0, 0.25)
	sep.size = Vector2(1, COIN_PILL_H - 22.0)
	sep.position = Vector2(sep_x, 11.0)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coin_pill.add_child(sep)

	# Balance label sits between the gold disc and the separator. Bold-ish via
	# a 1px outline; soft gold shadow so the text feels like it lives in the
	# same world as the coin.
	_coin_lbl = Label.new()
	_coin_lbl.add_theme_font_size_override("font_size", 22)
	_coin_lbl.add_theme_color_override("font_color", Color.WHITE)
	_coin_lbl.add_theme_color_override("font_outline_color", Color.WHITE)
	_coin_lbl.add_theme_constant_override("outline_size", 1)
	_coin_lbl.add_theme_color_override("font_shadow_color", Color(1.0, 0.80, 0.30, 0.35))
	_coin_lbl.add_theme_constant_override("shadow_outline_size", 4)
	var lbl_x := disc_x + d + 8.0
	_coin_lbl.position = Vector2(lbl_x, 0)
	_coin_lbl.size = Vector2(sep_x - lbl_x - 4.0, COIN_PILL_H)
	_coin_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_coin_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_coin_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coin_pill.add_child(_coin_lbl)

	# Until the wallet doc lands from Firestore, show animated dots instead of
	# the placeholder "0" — otherwise the pill flashes "0" for a beat then snaps
	# to the real balance, which reads as "you have nothing" on every open.
	if CoinsManager.is_loaded():
		_coin_lbl.text = _comma_int(CoinsManager.balance)
	else:
		_start_coin_loading_anim()

	CoinsManager.balance_changed.connect(_on_balance_changed)
	# After sign-in CoinsManager may load asynchronously; reflect the final value.
	CoinsManager.loaded.connect(func() -> void: _on_balance_changed(CoinsManager.balance))

	_build_coin_plus_button(plus_d, plus_x)

# Circular gold "+" tucked at the right end of the coin pill — opens the
# real-money purchase popup. Carries its own golden glow ring so it pops off
# the dark glass, and breathes a slow heartbeat to read as actionable.
func _build_coin_plus_button(d: float, x_in_pill: float) -> void:
	var py := HUD_TOP + (COIN_PILL_H - d) * 0.5
	var px := HUD_LEFT + x_in_pill
	_coin_plus_btn = Button.new()
	_coin_plus_btn.text = "+"
	_coin_plus_btn.size = Vector2(d, d)
	_coin_plus_btn.position = Vector2(px, py)
	_coin_plus_btn.pivot_offset = Vector2(d, d) * 0.5
	_coin_plus_btn.add_theme_font_size_override("font_size", 24)
	_coin_plus_btn.focus_mode = Control.FOCUS_NONE
	var s := StyleBoxFlat.new()
	s.bg_color = Color(1.0, 0.78, 0.22)                      # rich gold
	s.set_corner_radius_all(int(d * 0.5))
	s.border_color = Color(1.0, 0.94, 0.60)
	s.set_border_width_all(2)
	s.shadow_color = Color(1.0, 0.78, 0.22, 0.65)            # golden bloom
	s.shadow_size = 12
	_coin_plus_btn.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = Color(1.0, 0.86, 0.36)
	_coin_plus_btn.add_theme_stylebox_override("hover", sh)
	var sp := s.duplicate() as StyleBoxFlat
	sp.bg_color = Color(0.86, 0.62, 0.12)
	_coin_plus_btn.add_theme_stylebox_override("pressed", sp)
	_coin_plus_btn.add_theme_color_override("font_color", Color(0.32, 0.18, 0.0))
	_coin_plus_btn.add_theme_color_override("font_hover_color", Color(0.32, 0.18, 0.0))
	_coin_plus_btn.pressed.connect(_open_coins_popup)
	add_child(_coin_plus_btn)

	# Gentle pulse so the "+" reads as an actionable affordance.
	var pulse := create_tween().set_loops()
	pulse.tween_property(_coin_plus_btn, "scale", Vector2.ONE * 1.06, 0.85) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(_coin_plus_btn, "scale", Vector2.ONE, 0.85) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _open_coins_popup() -> void:
	var popup := CoinsPurchasePopup.new()
	add_child(popup)

func _comma_int(n: int) -> String:
	# 1234567 -> "1,234,567". Used for both the persistent balance HUD and any
	# transient toasts so the formatting stays consistent across the app.
	var s := str(n)
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += ","
		out += s[i]
	return out

func _on_balance_changed(new_balance: int) -> void:
	if _coin_lbl:
		_stop_coin_loading_anim()
		_coin_lbl.text = _comma_int(new_balance)

func _start_coin_loading_anim() -> void:
	if not _coin_lbl:
		return
	_coin_loading_idx = 0
	_coin_lbl.text = "."
	_coin_loading_tween = create_tween().set_loops()
	_coin_loading_tween.tween_interval(0.35)
	_coin_loading_tween.tween_callback(_tick_coin_loading)

func _tick_coin_loading() -> void:
	if not _coin_lbl:
		return
	_coin_loading_idx = (_coin_loading_idx + 1) % 3
	_coin_lbl.text = ".".repeat(_coin_loading_idx + 1)

func _stop_coin_loading_anim() -> void:
	if _coin_loading_tween and _coin_loading_tween.is_valid():
		_coin_loading_tween.kill()
	_coin_loading_tween = null

# Daily-claim chip — sits to the right of the coin pill as a matching glass
# pill: purple gift disc on the left, bold "Daily Claim" label, and a small
# purple arrow disc on the far right that hints at "tap to open". Outer purple
# aura ties it visually to the coin pill's sci-fi treatment. A small red dot
# badges the gift disc when a claim is available.
const DAILY_PILL_W := 230.0

func _build_daily_claim_button() -> void:
	var x := HUD_LEFT + COIN_PILL_W + HUD_GAP
	var y := HUD_TOP
	var ph := COIN_PILL_H

	_daily_btn = Button.new()
	_daily_btn.position = Vector2(x, y)
	_daily_btn.size = Vector2(DAILY_PILL_W, ph)
	_daily_btn.focus_mode = Control.FOCUS_NONE
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.03, 0.04, 0.12, 0.90)
	s.set_corner_radius_all(int(ph * 0.5))
	s.border_color = Color(0.78, 0.62, 1.0, 0.55)
	s.set_border_width_all(1)
	s.shadow_color = Color(0.55, 0.36, 1.0, 0.40)
	s.shadow_size = 14
	s.shadow_offset = Vector2(0, 2)
	_daily_btn.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = Color(0.08, 0.08, 0.20, 0.95)
	_daily_btn.add_theme_stylebox_override("hover", sh)
	var sp := s.duplicate() as StyleBoxFlat
	sp.bg_color = Color(0.02, 0.02, 0.10, 1.0)
	_daily_btn.add_theme_stylebox_override("pressed", sp)
	_daily_btn.text = ""                                # label is overlaid below
	_daily_btn.pressed.connect(_open_daily_popup)
	add_child(_daily_btn)

	# Geometry: purple disc on left, arrow disc on right, centered label between.
	var d := 40.0
	var disc_x := x + 8.0
	var disc_y := y + (ph - d) * 0.5
	var arrow_d := 32.0
	var arrow_x := x + DAILY_PILL_W - arrow_d - 10.0
	var arrow_y := y + (ph - arrow_d) * 0.5

	# Soft purple aura behind the gift disc (drawn as an empty panel with shadow).
	var glow := Panel.new()
	glow.size = Vector2(d + 12, d + 12)
	glow.position = Vector2(disc_x - 6, disc_y - 6)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gs := StyleBoxFlat.new()
	gs.bg_color = Color(0.55, 0.36, 1.0, 0.0)
	gs.set_corner_radius_all(int((d + 12) * 0.5))
	gs.shadow_color = Color(0.62, 0.36, 1.0, 0.55)
	gs.shadow_size = 10
	glow.add_theme_stylebox_override("panel", gs)
	add_child(glow)

	# Purple gift disc — glossy, with a small highlight + the gift glyph inside.
	var disc := Panel.new()
	disc.size = Vector2(d, d)
	disc.position = Vector2(disc_x, disc_y)
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ds := StyleBoxFlat.new()
	ds.bg_color = Color(0.66, 0.36, 1.0)        # vivid purple
	ds.set_corner_radius_all(int(d * 0.5))
	ds.border_color = Color(0.90, 0.70, 1.0)
	ds.set_border_width_all(2)
	disc.add_theme_stylebox_override("panel", ds)
	add_child(disc)
	var hl := Panel.new()
	var hd := d * 0.36
	hl.size = Vector2(hd, hd)
	hl.position = Vector2(d * 0.18, d * 0.14)
	hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hs := StyleBoxFlat.new()
	hs.bg_color = Color(1.0, 0.95, 1.0, 0.45)
	hs.set_corner_radius_all(int(hd * 0.5))
	hl.add_theme_stylebox_override("panel", hs)
	disc.add_child(hl)

	# Tiny procedural gift box inside the disc (lid + body + ribbon).
	var gift := Control.new()
	gift.size = Vector2(d, d)
	gift.position = Vector2.ZERO
	gift.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gift.draw.connect(_draw_gift_icon.bind(gift))
	disc.add_child(gift)

	# Centered "Daily Claim" label between disc and arrow.
	var lbl := Label.new()
	lbl.text = "Daily Claim"
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_color_override("font_outline_color", Color.WHITE)
	lbl.add_theme_constant_override("outline_size", 1)
	lbl.add_theme_color_override("font_shadow_color", Color(0.62, 0.36, 1.0, 0.40))
	lbl.add_theme_constant_override("shadow_outline_size", 4)
	var lbl_x := disc_x + d + 6.0
	lbl.position = Vector2(lbl_x, y)
	lbl.size = Vector2(arrow_x - lbl_x - 6.0, ph)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)

	# Small purple arrow disc on the far right. Drawn as a glossy circle with
	# a chevron glyph; sits over the pill so the whole widget reads as one.
	var arrow := Panel.new()
	arrow.size = Vector2(arrow_d, arrow_d)
	arrow.position = Vector2(arrow_x, arrow_y)
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var asx := StyleBoxFlat.new()
	asx.bg_color = Color(0.55, 0.30, 0.96)
	asx.set_corner_radius_all(int(arrow_d * 0.5))
	asx.border_color = Color(0.86, 0.66, 1.0)
	asx.set_border_width_all(2)
	asx.shadow_color = Color(0.55, 0.30, 0.96, 0.60)
	asx.shadow_size = 10
	arrow.add_theme_stylebox_override("panel", asx)
	add_child(arrow)
	# Procedurally drawn ">" chevron, centered in the disc — avoids relying on a
	# glyph whose baseline/metrics shift the mark off-center per font.
	var chevron := Control.new()
	chevron.size = Vector2(arrow_d, arrow_d)
	chevron.position = Vector2.ZERO
	chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chevron.draw.connect(_draw_daily_chevron.bind(chevron))
	arrow.add_child(chevron)

	# Small pulsing red "claim available" notification dot on the top-right of
	# the gift disc so it pops against the purple.
	_daily_badge = Panel.new()
	_daily_badge.size = Vector2(14, 14)
	_daily_badge.position = Vector2(disc_x + d - 8, disc_y - 4)
	_daily_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.95, 0.18, 0.18)
	bs.set_corner_radius_all(7)
	bs.shadow_color = Color(0.95, 0.18, 0.18, 0.7)
	bs.shadow_size = 8
	_daily_badge.add_theme_stylebox_override("panel", bs)
	add_child(_daily_badge)

	# Gentle infinite pulse so the badge catches the eye.
	var pulse := create_tween().set_loops()
	pulse.tween_property(_daily_badge, "scale", Vector2.ONE * 1.25, 0.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(_daily_badge, "scale", Vector2.ONE, 0.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	_refresh_daily_badge()
	CoinsManager.daily_claim_changed.connect(_refresh_daily_badge)
	CoinsManager.loaded.connect(_refresh_daily_badge)

func _refresh_daily_badge() -> void:
	if _daily_badge:
		_daily_badge.visible = CoinsManager.can_claim_today()

func _open_daily_popup() -> void:
	var popup := DailyClaimPopup.new()
	add_child(popup)

# ---------------- settings popup ----------------

# Minimal settings modal opened by the profile-card gear: a music on/off toggle
# and a close button. Dismissed by tapping outside or Close.
func _show_settings_popup() -> void:
	var sz := get_viewport_rect().size
	var overlay := Control.new()
	overlay.name = "SettingsPopup"
	overlay.position = Vector2.ZERO
	overlay.size = sz
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.01, 0.04, 0.6)
	dim.position = Vector2.ZERO
	dim.size = sz
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(dim)

	# Tapping the dimmed backdrop closes the popup.
	var close_bg := _overlay_button(sz)
	close_bg.pressed.connect(overlay.queue_free)
	overlay.add_child(close_bg)

	const PW := 420.0
	const PH := 260.0
	var panel := _card_panel(Vector2(PW, PH), Color(0.05, 0.06, 0.16, 0.98),
		Color(0.40, 0.50, 1.0, 0.55), Color(0.0, 0.0, 0.0, 0.55))
	panel.position = (sz - Vector2(PW, PH)) * 0.5
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(panel)

	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_color_override("font_shadow_color", Color(0.20, 0.40, 1.0, 0.45))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 3)
	title.add_theme_constant_override("shadow_outline_size", 9)
	title.position = Vector2(20, 28)
	title.size = Vector2(PW - 40, 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(title)

	var music_on := AudioManager.is_music_on()
	_settings_music_btn = _make_popup_button(panel, "Music:  %s" % ("On" if music_on else "Off"),
		Vector2(40, 92), Vector2(PW - 80, 52), Color(0.16, 0.18, 0.34), _toggle_music)
	_make_popup_button(panel, "Close", Vector2(40, 160), Vector2(PW - 80, 52),
		Color(0.15, 0.6, 0.95), overlay.queue_free)

	# Gentle entrance: fade + scale-pop on the panel.
	panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2(0.92, 0.92)
	overlay.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(overlay, "modulate:a", 1.0, 0.20).set_trans(Tween.TRANS_SINE)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _toggle_music() -> void:
	if AudioManager.is_music_on():
		AudioManager.stop_bg_music()
	else:
		AudioManager.play_bg_music()
	if _settings_music_btn and is_instance_valid(_settings_music_btn):
		_settings_music_btn.text = "Music:  %s" % ("On" if AudioManager.is_music_on() else "Off")

# ---------------- sign-in popup (welcome + feature gates) ----------------

# First-launch welcome popup: shown once per launch (gated on welcome_prompt_shown
# in _ready) when signed out. The player must pick sign in or guest before they
# can interact with the menu.
func _show_welcome_popup() -> void:
	_show_sign_in_popup(
		"Welcome to Simon",
		"Sign in to save your coins, climb the leaderboards and claim daily rewards — or jump straight in as a guest.",
		"Play as Guest")

# Feature-gate popup: shown when a guest taps Shop or Leaderboards. Same
# visual, but the secondary action is "Maybe Later" — the user is already
# playing as a guest, so "Play as Guest" would be redundant copy.
func _show_sign_in_required_popup(title_text: String, subtitle_text: String) -> void:
	_show_sign_in_popup(title_text, subtitle_text, "Maybe Later")

# Shared builder for both popup variants. Caller passes the title / subtitle
# copy and the label for the secondary (dismiss) button.
func _show_sign_in_popup(title_text: String, subtitle_text: String, secondary_label: String) -> void:
	var sz := get_viewport_rect().size
	var overlay := Control.new()
	overlay.name = "SignInPopup"
	overlay.position = Vector2.ZERO
	overlay.size = sz
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP   # eat clicks meant for the menu
	add_child(overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.01, 0.04, 0.66)
	dim.position = Vector2.ZERO
	dim.size = sz
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)

	const PW := 480.0
	const PH := 340.0
	var panel := Panel.new()
	panel.position = (sz - Vector2(PW, PH)) * 0.5
	panel.size = Vector2(PW, PH)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.05, 0.06, 0.16, 0.98)
	st.set_corner_radius_all(24)
	st.border_color = Color(0.40, 0.50, 1.0, 0.55)
	st.set_border_width_all(2)
	st.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	st.shadow_size = 22
	panel.add_theme_stylebox_override("panel", st)
	overlay.add_child(panel)

	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_color_override("font_shadow_color", Color(0.20, 0.40, 1.0, 0.45))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 3)
	title.add_theme_constant_override("shadow_outline_size", 9)
	title.position = Vector2(20, 40)
	title.size = Vector2(PW - 40, 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(title)

	var sub := Label.new()
	sub.text = subtitle_text
	sub.add_theme_font_size_override("font_size", 17)
	sub.add_theme_color_override("font_color", Color(0.76, 0.80, 1.0, 0.90))
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.position = Vector2(40, 100)
	sub.size = Vector2(PW - 80, 80)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(sub)

	var bw := PW - 80.0
	var sign_in_btn := _make_popup_button(panel, "Sign In", Vector2(40, 196), Vector2(bw, 56),
		Color(0.15, 0.6, 0.95), _popup_sign_in.bind(overlay))
	sign_in_btn.add_theme_font_size_override("font_size", 22)

	_make_popup_button(panel, secondary_label, Vector2(40, 264), Vector2(bw, 56),
		Color(0.16, 0.18, 0.34), overlay.queue_free)

	# Gentle entrance: fade + scale-pop on the panel.
	panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2(0.92, 0.92)
	overlay.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(overlay, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_SINE)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.30) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# Dismiss the sign-in popup and run the normal sign-in flow.
func _popup_sign_in(overlay: Control) -> void:
	overlay.queue_free()
	_on_sign_in()

func _make_popup_button(parent: Control, txt: String, pos: Vector2, size: Vector2, col: Color, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = txt
	btn.position = pos
	btn.size = size
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 19)
	_style(btn, col)
	btn.pressed.connect(cb)
	parent.add_child(btn)
	return btn

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

func _on_shop() -> void:
	# The shop needs a wallet — guests get the sign-in popup, not a direct
	# auth flow, so they can choose whether to commit.
	if FirebaseManager.is_signed_in():
		game_manager.show_shop()
	else:
		_show_sign_in_required_popup(
			"Sign In to Open the Shop",
			"Sign in to save your coins and purchases across devices — or come back later.")

func _on_leaderboards() -> void:
	if FirebaseManager.is_signed_in() and FirebaseManager.has_display_name():
		game_manager.show_leaderboards()
	else:
		_show_sign_in_required_popup(
			"Sign In for Leaderboards",
			"Sign in to record your high scores and climb the global rankings.")

func _on_sign_in() -> void:
	if _signing_in:
		return
	_signing_in = true
	FirebaseManager.sign_in()
	# Safety net: if the Google sign-in intent silently never launches (e.g. a
	# plugin conflict ate the Activity result), neither success nor failure
	# will fire and the lockout would wedge the button forever. Auto-clear it
	# after a reasonable timeout so a second press can retry.
	get_tree().create_timer(20.0).timeout.connect(_clear_signing_in_guard)

func _clear_signing_in_guard() -> void:
	_signing_in = false

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
