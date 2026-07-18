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
const DailyRankRewardPopup := preload("res://daily_rank_reward_popup.gd")
const ProfilePopup := preload("res://profile_screen.gd")
const CoinsPurchasePopup := preload("res://coins_purchase_popup.gd")
const HomeTutorial := preload("res://home_tutorial.gd")
const ShopScreen := preload("res://shop_screen.gd")

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

# Premium-card chrome (shared by the Shop / Leaderboard / Arena cards).
const CARD_SIZE := Vector2(248.0, 300.0)
const ARENA_SIZE := Vector2(506.0, 124.0)
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
var _arena_card: Dictionary = {}   # bottom-center: opens the Arena (multiplayer contests)

# --- knight-duel animation state (drives the two fencers on the Arena card) ---
# The two knights fight in a loop of randomised "beats". Each beat winds up, strikes
# (a sword clash or a dodged whiff), briefly freezes on impact, then recovers, with
# continuous idle motion (breathing, weight-shifts, shield fidget) layered on top.
# The heavy colosseum backdrop stays fully static; only the small knight overlay
# redraws each frame, so the animation is cheap.
const _KN_TF_POS := Vector2(13.0, -23.6)   # matches _draw_arena_simon's canvas transform
const _KN_TF_SCL := Vector2(1.28, 1.13)
const _KN_L_FEET := Vector2(91.0, 86.0)    # neutral stance, pre-transform (ctr 107,74)
const _KN_R_FEET := Vector2(123.0, 86.0)
var _duel_rng := RandomNumberGenerator.new()
var _duel_t := 0.0
var _beat_start := 0.0
var _beat_end := 0.0
var _atk_idx := 0                          # 0 = left leads this beat, 1 = right
var _beat_dodge := false                   # this beat is a dodge/whiff rather than a clash
var _beat_clash := Vector2(107.0, 54.0)    # where the blades meet on a clash beat
var _clash_seed := 0.0                      # rotates the spark shards
var _flashed := false                       # spark already fired for this beat
var _clash_flash := 0.0                     # 0..1 spark intensity, decays after impact
var _clash_at := Vector2(107.0, 54.0)
var _pose_l := {"feet": Vector2(91.0, 86.0), "blade": Vector2(107.0, 54.0), "lean": 0.0, "guard": 0.15}
var _pose_r := {"feet": Vector2(123.0, 86.0), "blade": Vector2(107.0, 54.0), "lean": 0.0, "guard": 0.15}
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
# First-run tour state. `_tutorial_active` guards against a second tour being
# spawned; `_awaiting_coins_for_tutorial` guards the one-shot wait for the wallet
# doc to load (signed-in users) so we don't connect the `loaded` signal twice.
var _tutorial_active := false
var _awaiting_coins_for_tutorial := false
# One-shot guard so the opportunistic shop-preview warm-up (see _schedule_shop_prewarm)
# only fires once per home-screen lifetime.
var _shop_prewarm_started := false

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
		# Show a summary popup when yesterday's leaderboard reward lands. Connect
		# BEFORE kicking off the grant so we never miss the (possibly synchronous
		# in editor) emission.
		CoinsManager.daily_rank_reward_granted.connect(_on_daily_rank_reward)
		# Opening the home screen is the heartbeat of the login-streak system AND
		# the moment we collect the previous day's leaderboard-standing reward.
		# If the wallet hasn't finished loading yet, defer both until it has.
		if CoinsManager.is_loaded():
			CoinsManager.register_login()
			CoinsManager.grant_daily_rewards_if_due()
		else:
			CoinsManager.loaded.connect(CoinsManager.register_login, CONNECT_ONE_SHOT)
			CoinsManager.loaded.connect(CoinsManager.grant_daily_rewards_if_due, CONNECT_ONE_SHOT)

	_layout()
	get_viewport().size_changed.connect(_layout)
	_start_animations()
	AudioManager.play_bg_music()
	_schedule_shop_prewarm()

	# On the first home open of this launch, a signed-out player is asked whether
	# to sign in or continue as a guest. The flag lives on the (persistent)
	# GameManager so returning home later in the same session won't re-prompt.
	if not FirebaseManager.is_signed_in() and not game_manager.welcome_prompt_shown:
		game_manager.welcome_prompt_shown = true
		_show_welcome_popup()
	else:
		# No welcome gate in the way — offer the first-run tour if it hasn't been
		# seen yet (guests: local flag; signed-in: their wallet-doc flag).
		_maybe_start_tutorial()

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
	_ranks_card = _build_card("LEADERBOARD", _draw_ranks_card, "View Leaderboard", _draw_chart, _on_leaderboards, false)
	# Podium rank numerals, overlaid on the leaderboard illustration.
	_card_numeral(_ranks_card, "1", 22, Color(0.34, 0.24, 0.05), Vector2(98, 159), 40)
	_card_numeral(_ranks_card, "2", 18, Color(0.30, 0.31, 0.36), Vector2(29, 175), 36)
	_card_numeral(_ranks_card, "3", 18, Color(0.36, 0.24, 0.10), Vector2(167, 189), 36)
	_build_arena_card()

# A premium navigation card: rounded translucent-purple panel with a title, a
# procedural illustration, and a bottom call-to-action pill (icon + label). The
# whole card is tappable (transparent Button overlay) and scales gently on hover.
func _build_card(title: String, draw_cb: Callable, cta: String, icon_cb: Callable, action: Callable, show_title := true) -> Dictionary:
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

	if show_title:
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

# The bottom "ARENA" banner card: a fully drawn stadium illustration on the left,
# a title + subtitle, and a call-to-action pill — same premium purple/blue chrome
# as the Shop / Leaderboard cards. Whole card is tappable → the multiplayer Arena.
func _build_arena_card() -> void:
	var wrap := Control.new()
	wrap.size = ARENA_SIZE
	wrap.custom_minimum_size = ARENA_SIZE
	wrap.pivot_offset = ARENA_SIZE * 0.5
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wrap)

	var floater := Control.new()
	floater.size = ARENA_SIZE
	floater.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(floater)

	var panel := _card_panel(ARENA_SIZE, CARD_PURPLE, CARD_BORDER, CARD_GLOW)
	floater.add_child(panel)

	# A wide, deluxe colosseum illustration filling the left of the card.
	var art := Control.new()
	art.size = Vector2(300, ARENA_SIZE.y)
	art.position = Vector2(6, 0)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.draw.connect(_draw_arena_simon.bind(art))
	panel.add_child(art)

	# The two duelling knights live on their own thin overlay above the (static)
	# colosseum art, so only this tiny node redraws each frame. Same box + canvas
	# transform as `art` so the fencers line up on the arena floor.
	var knights := Control.new()
	knights.size = Vector2(300, ARENA_SIZE.y)
	knights.position = Vector2(6, 0)
	knights.mouse_filter = Control.MOUSE_FILTER_IGNORE
	knights.draw.connect(_draw_arena_knights.bind(knights))
	panel.add_child(knights)

	# "ARENA" title — a custom-drawn, brushed-steel wordmark (metallic bevel + soft
	# shadow, no neon) set to the right of the colosseum, lifted to leave room for a
	# subtitle bubble beneath it (the whole card is tappable; no CTA pill).
	var col_w := ARENA_SIZE.x - 306 - 20
	var title := Control.new()
	title.position = Vector2(306, 6)
	title.size = Vector2(col_w, 62)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.draw.connect(_draw_arena_title.bind(title))
	panel.add_child(title)

	# A rounded "bubble" subtitle under the title — mirrors the pill chrome of the
	# Shop / Leaderboard CTA buttons so the Arena card reads as the same family.
	var sub := Panel.new()
	var sub_w := 178.0
	var sub_h := 30.0
	sub.size = Vector2(sub_w, sub_h)
	sub.position = Vector2(306 + (col_w - sub_w) * 0.5, 78)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sst := StyleBoxFlat.new()
	# A slightly muted purple with a gentle shadow — inviting, not shouting.
	sst.bg_color = Color(0.48, 0.35, 0.86, 0.94)
	sst.set_corner_radius_all(int(sub_h * 0.5))
	sst.shadow_color = Color(0.42, 0.28, 0.90, 0.38)
	sst.shadow_size = 4
	sub.add_theme_stylebox_override("panel", sst)
	var sl := Label.new()
	# Atmospheric tagline — deliberately small, low-contrast and light so it finishes
	# the pill without competing with the title or the central PLAY button.
	sl.text = "Fight for Glory"
	sl.add_theme_font_size_override("font_size", 13)
	sl.add_theme_color_override("font_color", Color(0.90, 0.90, 0.98, 0.74))
	sl.add_theme_constant_override("line_spacing", 0)
	sl.size = Vector2(sub_w, sub_h)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub.add_child(sl)
	panel.add_child(sub)

	var btn := _overlay_button(ARENA_SIZE)
	btn.mouse_entered.connect(_on_card_hover.bind(wrap, true))
	btn.mouse_exited.connect(_on_card_hover.bind(wrap, false))
	btn.button_down.connect(_on_card_press.bind(wrap, true))
	btn.button_up.connect(_on_card_press.bind(wrap, false))
	btn.pressed.connect(_on_arena)
	floater.add_child(btn)

	_arena_card = {"wrap": wrap, "art": art, "floater": floater, "knights": knights}
	_duel_rng.randomize()

# The Arena mascot: a medieval colosseum. Massive tiered stone grandstands ring a
# central arena floor rendered as Simon himself (the four-colour wheel), where two
# armoured knights duel with swords. Torches, banners, a wooden railing and a dark,
# warm-lit mood set the epic medieval scene. Fully static. `c` is a ~214 x 124 box.
func _draw_arena_simon(c: Control) -> void:
	# The scene below is authored around the original 214x124 box; a scaled canvas
	# transform blows it up crisply to fill the wider, deluxe art box.
	# Squashed a touch vertically (sy 1.13 vs sx 1.28) so the bowl sits fully inside
	# the card instead of clipping its top/bottom; offset keeps the centre at y≈60.
	c.draw_set_transform(Vector2(13.0, -23.6), 0.0, Vector2(1.28, 1.13))
	var ctr := Vector2(107, 74)

	# Warm torch-lit haze — keeps the arena dark with an amber core.
	_glow(c, ctr + Vector2(0, -2), 78.0, Color(0.95, 0.50, 0.16), 5)

	# Dark, warm stone (lit from within by the torches).
	var st_edge := Color(0.10, 0.08, 0.06)
	var st_dk := Color(0.21, 0.16, 0.11)
	var st_md := Color(0.37, 0.29, 0.19)
	var st_lt := Color(0.56, 0.44, 0.28)

	# Soft cast shadow under the whole bowl.
	c.draw_colored_polygon(_ellipse_pts(ctr + Vector2(0, 4), 97.0, 46.0), Color(0, 0, 0, 0.22))

	# --- massive tiered grandstands: concentric seating bowls stepping down + in,
	# each with a thin warm-lit lip so the levels read as stacked stone steps ---
	var tiers := [Vector3(96, 46, 0.0), Vector3(88, 42, 0.28), Vector3(79, 37.5, 0.5),
		Vector3(69, 33, 0.72), Vector3(59, 28, 0.95)]
	for tv in tiers:
		var t: Vector3 = tv
		c.draw_colored_polygon(_ellipse_pts(ctr, t.x, t.y), st_dk.lerp(st_md, t.z))
		var lip := PackedVector2Array()
		for k in 22:
			var a: float = PI + PI * float(k) / 21.0
			lip.append(ctr + Vector2(cos(a) * (t.x - 1.0), sin(a) * (t.y - 1.0)))
		c.draw_polyline(lip, Color(st_lt.r, st_lt.g, st_lt.b, 0.5), 1.3, true)

	# --- gilded cornice crowning the outer wall (the deluxe touch) ---
	var gold := Color(0.98, 0.82, 0.34)
	var crown := _ellipse_pts(ctr, 96.5, 46.0, 56)
	crown.append(crown[0])
	c.draw_polyline(crown, Color(gold.r, gold.g, gold.b, 0.7), 2.0, true)
	c.draw_polyline(_ellipse_pts(ctr, 96.5, 46.0, 56), Color(1.0, 0.94, 0.72, 0.35), 0.8, true)

	# --- a subtle crowd murmuring in the upper stands (sparse warm-dark dots) ---
	for ring in 2:
		var rx: float = 90.0 - ring * 8.0
		var ry: float = 43.0 - ring * 4.0
		var n := 34 - ring * 6
		for i in n:
			var a := TAU * float(i) / float(n)
			var warm := 0.5 + 0.5 * sin(float(i) * 2.7 + ring * 1.3)
			c.draw_circle(ctr + Vector2(cos(a) * rx, sin(a) * ry), 1.2,
				Color(0.30 + 0.22 * warm, 0.20 + 0.08 * warm, 0.14, 0.65))

	# --- the arcade: dark arch openings set into the outer wall ---
	var na := 30
	for i in na:
		var a := TAU * float(i) / float(na)
		var p := ctr + Vector2(cos(a) * 88.0, sin(a) * 42.0)
		c.draw_rect(Rect2(p.x - 1.8, p.y - 1.2, 3.6, 3.9), st_edge)
		c.draw_circle(Vector2(p.x, p.y - 1.2), 1.8, st_edge)

	# --- a deluxe balustrade fence ringing the very top of the outer wall ---
	_draw_arena_fence(c, ctr, 95.0, 45.5)

	# --- medieval banners draped over the upper wall ---
	var bcols := [Color(0.72, 0.16, 0.18), Color(0.20, 0.34, 0.64),
		Color(0.74, 0.56, 0.16), Color(0.30, 0.52, 0.28)]
	var bang := [PI * 1.20, PI * 1.40, PI * 1.60, PI * 1.80]
	for i in bang.size():
		_draw_arena_banner(c, ctr + Vector2(cos(bang[i]) * 83.0, sin(bang[i]) * 39.0), bcols[i])

	# --- torches ringing the back of the arena, casting warm pools of light ---
	for a in [PI * 1.12, PI * 1.34, PI * 1.66, PI * 1.88]:
		_draw_arena_torch(c, ctr + Vector2(cos(a) * 73.0, sin(a) * 35.0))

	# --- the arena floor: a sand ledge fenced by a wooden railing ---
	c.draw_colored_polygon(_ellipse_pts(ctr, 56.0, 27.0), st_md.darkened(0.15))
	c.draw_colored_polygon(_ellipse_pts(ctr, 52.0, 24.5), Color(0.30, 0.22, 0.14))
	var rail := _ellipse_pts(ctr, 54.0, 25.5)
	rail.append(rail[0])
	c.draw_polyline(rail, Color(0.36, 0.23, 0.12), 1.8, true)
	for i in 16:
		var a := TAU * float(i) / 16.0
		var p := ctr + Vector2(cos(a) * 54.0, sin(a) * 25.5)
		c.draw_line(p, p + Vector2(0, -3.0), Color(0.42, 0.28, 0.15), 1.4)

	# --- Simon himself as the arena floor: the four-colour wheel (top gold, right
	# red, bottom green, left blue), the sand showing through the gaps as a cross ---
	var f_rx := 50.0
	var f_ry := 24.0
	var simon := [Color(0.97, 0.78, 0.22), Color(0.88, 0.22, 0.24),
		Color(0.20, 0.70, 0.34), Color(0.24, 0.50, 0.95)]
	var gap := deg_to_rad(6.0)
	for q in 4:
		var a0 := -PI * 0.75 + q * PI * 0.5 + gap * 0.5
		var a1 := -PI * 0.75 + (q + 1) * PI * 0.5 - gap * 0.5
		var wedge := PackedVector2Array([ctr])
		for k in 11:
			var a: float = lerp(a0, a1, float(k) / 10.0)
			wedge.append(ctr + Vector2(cos(a) * f_rx, sin(a) * f_ry))
		c.draw_colored_polygon(wedge, simon[q])
	# Glossy sheen across the top of the colour wheel — makes Simon read as polished.
	c.draw_colored_polygon(_ellipse_pts(ctr + Vector2(0, -7), 34.0, 11.0), Color(1, 1, 1, 0.10))
	# Thin gold ring binding the wheel, then the dark hub.
	var wheel_ring := _ellipse_pts(ctr, f_rx, f_ry, 44)
	wheel_ring.append(wheel_ring[0])
	c.draw_polyline(wheel_ring, Color(0.98, 0.82, 0.34, 0.6), 1.4, true)
	c.draw_colored_polygon(_ellipse_pts(ctr, 8.0, 4.0), Color(0.12, 0.12, 0.18))   # hub
	c.draw_polyline(_ellipse_pts(ctr, 8.0, 4.0, 20), Color(0.98, 0.82, 0.34, 0.7), 1.0, true)  # gilded hub rim

	# The two duelling knights are drawn on a separate animated overlay
	# (_draw_arena_knights), so nothing below the wheel needs to redraw per frame.

# A deluxe balustrade fence ringing the colosseum: a stone rail of gilded posts
# linked by twin rails, each post crowned with a golden finial. `rx`,`ry` are the
# outer-wall radii it rides on. Fully static.
func _draw_arena_fence(c: Control, ctr: Vector2, rx: float, ry: float) -> void:
	var wood := Color(0.36, 0.26, 0.16)
	var wood_dk := Color(0.18, 0.12, 0.08)
	var gold := Color(0.98, 0.82, 0.34)
	var gold_hi := Color(1.0, 0.95, 0.74)
	var ph := 6.5                                    # post height (screen-up)
	# Lower rail hugging the wall, then a top rail lifted by the post height.
	var lower := _ellipse_pts(ctr, rx, ry, 60)
	lower.append(lower[0])
	var upper := PackedVector2Array()
	for p in lower:
		upper.append(p + Vector2(0, -ph))
	c.draw_polyline(lower, wood_dk, 2.4, true)
	c.draw_polyline(upper, wood, 2.2, true)
	c.draw_polyline(upper, Color(gold.r, gold.g, gold.b, 0.55), 1.0, true)   # gilded cap-rail
	# Balusters: a shaded post with a bright edge, crowned by a gilded finial.
	var n := 30
	for i in n:
		var a := TAU * float(i) / float(n)
		var b := ctr + Vector2(cos(a) * rx, sin(a) * ry)
		var top := b + Vector2(0, -ph)
		c.draw_line(b, top, wood, 2.2)
		c.draw_line(b + Vector2(0.7, 0), top + Vector2(0.7, 0), wood_dk, 0.8)
		c.draw_line(b + Vector2(-0.7, 0), top + Vector2(-0.7, 0), Color(0.62, 0.48, 0.30), 0.7)
		c.draw_circle(top, 1.7, gold)
		c.draw_circle(top + Vector2(-0.5, -0.5), 0.7, gold_hi)

# One wall torch: a warm glow, a short bracket and a two-tone flame.
func _draw_arena_torch(c: Control, base: Vector2) -> void:
	_glow(c, base + Vector2(0, -4), 13.0, Color(1.0, 0.58, 0.20), 4)
	c.draw_rect(Rect2(base.x - 1.1, base.y - 2.0, 2.2, 8.0), Color(0.26, 0.17, 0.09))
	c.draw_colored_polygon(PackedVector2Array([
		base + Vector2(0, -12), base + Vector2(2.8, -5), base + Vector2(0, -2),
		base + Vector2(-2.8, -5)]), Color(1.0, 0.52, 0.16))
	c.draw_colored_polygon(PackedVector2Array([
		base + Vector2(0, -9), base + Vector2(1.5, -5), base + Vector2(0, -3),
		base + Vector2(-1.5, -5)]), Color(1.0, 0.86, 0.42))

# A small hanging medieval banner: a rod, a swallow-tail flag (shaded right half)
# and a light emblem dot.
func _draw_arena_banner(c: Control, top: Vector2, col: Color) -> void:
	var w := 7.0
	var h := 12.0
	c.draw_colored_polygon(PackedVector2Array([
		top + Vector2(-w * 0.5, 0), top + Vector2(w * 0.5, 0), top + Vector2(w * 0.5, h),
		top + Vector2(0, h - 3.5), top + Vector2(-w * 0.5, h)]), col)
	c.draw_colored_polygon(PackedVector2Array([
		top + Vector2(0, 0), top + Vector2(w * 0.5, 0),
		top + Vector2(w * 0.5, h), top + Vector2(0, h - 3.5)]), col.darkened(0.22))
	c.draw_rect(Rect2(top.x - w * 0.5 - 1.0, top.y - 1.6, w + 2.0, 1.8), Color(0.30, 0.21, 0.11))
	c.draw_circle(top + Vector2(0, h * 0.42), 1.5, Color(1, 1, 0.85, 0.85))

# One armoured knight standing at `feet`, facing `face` (+1 right, -1 left), his
# sword swinging toward `blade_tip`. `lean` is a world-x offset applied to the upper
# body (positive toward the foe when lunging, negative when dodging back); `guard`
# in 0..1 raises the shield across the chest to block. Dark steel so he reads
# against the colour wheel; the plume carries his team colour.
func _draw_arena_knight(c: Control, feet: Vector2, face: float, plume: Color, blade_tip: Vector2, lean: float, guard: float) -> void:
	var steel := Color(0.40, 0.43, 0.52)
	var steel_dk := Color(0.20, 0.22, 0.29)
	var steel_hi := Color(0.68, 0.72, 0.82)
	var cx := feet.x
	var ux := cx + lean            # leaning upper-body x
	var hipx := cx + lean * 0.4    # hips follow the lean a little
	var hip := feet.y - 9.0
	var sh := feet.y - 20.0
	# Legs stay planted at the feet and rise to the (leaning) hips.
	c.draw_line(Vector2(cx - 2.6, feet.y), Vector2(hipx - 2.6, hip), steel_dk, 2.6)
	c.draw_line(Vector2(cx + 2.6, feet.y), Vector2(hipx + 2.6, hip), steel_dk, 2.6)
	# Shield on the outer arm; it rises and swings across the chest as `guard` grows.
	var sxx := ux - face * 6.5 + face * guard * 3.8
	var syy := sh - guard * 4.0
	var ss := 1.0 + guard * 0.15
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(sxx - 3.2 * ss, syy + 1), Vector2(sxx + 3.2 * ss, syy + 1), Vector2(sxx + 3.2 * ss, syy + 8 * ss),
		Vector2(sxx, syy + 11.5 * ss), Vector2(sxx - 3.2 * ss, syy + 8 * ss)]), steel_dk)
	c.draw_line(Vector2(sxx, syy + 2), Vector2(sxx, syy + 9 * ss), plume, 1.2)
	# Torso (armoured trapezoid) + a vertical sheen.
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(ux - 4.5, sh), Vector2(ux + 4.5, sh),
		Vector2(hipx + 3.6, hip), Vector2(hipx - 3.6, hip)]), steel)
	c.draw_line(Vector2(ux - face * 2.2, sh + 1.5), Vector2(hipx - face * 2.2, hip - 1.0), steel_hi, 1.0)
	# Helmet with a shaded face side, a dark visor slit and a swept-back plume.
	var hy := sh - 4.0
	c.draw_circle(Vector2(ux, hy), 4.3, steel)
	c.draw_circle(Vector2(ux + face * 1.3, hy + 0.4), 3.6, steel_dk)
	c.draw_rect(Rect2(ux - 3.4, hy - 0.8, 6.8, 1.7), Color(0.04, 0.04, 0.07))
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(ux - face * 1.0, hy - 4.5), Vector2(ux - face * 3.5, hy - 9.5),
		Vector2(ux - face * 5.5, hy - 8.0), Vector2(ux - face * 2.0, hy - 3.0)]), plume)
	# Sword: gauntlet at the inner shoulder, blade swinging to the tip, crossguard.
	var hand := Vector2(ux + face * 5.0, sh + 2.0)
	c.draw_line(hand, blade_tip, steel_hi, 2.0)
	c.draw_line(hand, blade_tip, Color(1, 1, 1, 0.5), 0.8)
	var bv := blade_tip - hand
	if bv.length() < 0.01:
		bv = Vector2(0, -1)
	var gd := bv.normalized().orthogonal() * 3.0
	c.draw_line(hand - gd, hand + gd, Color(0.55, 0.42, 0.16), 2.2)
	c.draw_circle(hand, 1.4, steel_dk)

# The animated knight overlay: the two fencers plus the spark that flares when their
# blades meet. Same canvas transform as the (static) arena art so they sit on the
# floor. Poses are advanced in _advance_duel(); this only renders the current frame.
func _draw_arena_knights(c: Control) -> void:
	c.draw_set_transform(_KN_TF_POS, 0.0, _KN_TF_SCL)
	_draw_arena_knight(c, _pose_l["feet"], 1.0, Color(0.28, 0.44, 0.72),
		_pose_l["blade"], _pose_l["lean"], _pose_l["guard"])
	_draw_arena_knight(c, _pose_r["feet"], -1.0, Color(0.80, 0.26, 0.28),
		_pose_r["blade"], _pose_r["lean"], _pose_r["guard"])
	# Spark burst at the point of impact, fading over ~0.2s after the clash.
	if _clash_flash > 0.02:
		var a := _clash_flash
		var p := _clash_at
		for i in 3:
			var rr := (3.0 + 7.0 * a) * (1.0 - i * 0.25)
			c.draw_circle(p, rr, Color(1.0, 0.9, 0.5, 0.18 * a))
		_star4(c, p, 2.0 + 4.0 * a, Color(1.0, 0.98, 0.80, a))
		c.draw_circle(p, 1.6 * a, Color(1, 1, 1, 0.95 * a))
		for k in 5:
			var ang := TAU * float(k) / 5.0 + _clash_seed
			var d0 := 3.0 + 10.0 * (1.0 - a)
			var dir := Vector2(cos(ang), sin(ang))
			c.draw_line(p + dir * d0, p + dir * (d0 + 3.0 + 4.0 * a), Color(1.0, 0.9, 0.5, 0.9 * a), 1.0)

# The "ARENA" wordmark: a brushed-steel, beveled extrusion (bright top rim → dark
# lower face) over a soft drop shadow and a whisper of cool glow — medieval and
# metallic, never neon. Fully static (drawn once).
func _draw_arena_title(c: Control) -> void:
	var font := get_theme_default_font()
	var fs := 40
	var txt := "ARENA"
	var ts := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var asc := font.get_ascent(fs)
	var desc := font.get_descent(fs)
	var base := Vector2((c.size.x - ts.x) * 0.5, (c.size.y - (asc + desc)) * 0.5 + asc)
	# Soft drop shadow for depth.
	for off in [Vector2(0, 3), Vector2(1.2, 3), Vector2(-1.2, 3)]:
		c.draw_string(font, base + off, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.02, 0.02, 0.06, 0.28))
	# A very subtle cool glow behind the letters (not a neon halo).
	c.draw_string(font, base + Vector2(0, 0.5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.55, 0.62, 0.85, 0.10))
	# Beveled steel extrusion: stacked copies from dark/low to bright/high fake a
	# vertical brushed-metal gradient with a lit top edge and a shadowed base.
	var steps := [
		[Vector2(0, 2.0), Color(0.20, 0.22, 0.30)],
		[Vector2(0, 1.3), Color(0.31, 0.34, 0.43)],
		[Vector2(0, 0.6), Color(0.46, 0.49, 0.59)],
		[Vector2(0, 0.0), Color(0.63, 0.67, 0.77)],
		[Vector2(-0.4, -0.7), Color(0.81, 0.85, 0.93)],
		[Vector2(-0.5, -1.3), Color(0.96, 0.98, 1.0)],
	]
	for s in steps:
		c.draw_string(font, base + (s[0] as Vector2), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, s[1] as Color)

# ---------------- knight-duel director (runs while the menu is visible) ----------------

func _process(_dt: float) -> void:
	if _arena_card.is_empty() or not is_visible_in_tree():
		return
	_advance_duel(_dt)
	(_arena_card["knights"] as Control).queue_redraw()

# Roll a fresh combat "beat": a randomised duration, lead attacker, clash point and
# whether it is a clash or a dodged whiff — so the duel never settles into a pattern.
func _roll_beat() -> void:
	_beat_start = _beat_end
	_beat_end = _beat_start + _duel_rng.randf_range(2.0, 3.2)
	_beat_dodge = _duel_rng.randf() < 0.30
	_atk_idx = 0 if _duel_rng.randf() < 0.5 else 1
	_beat_clash = Vector2(107.0 + _duel_rng.randf_range(-8.0, 8.0), 54.0 + _duel_rng.randf_range(-5.0, 9.0))
	_clash_seed = _duel_rng.randf() * TAU
	_flashed = false

# Piecewise-linear keyframe lookup with smoothstep easing between segments.
func _kf(u: float, keys: Array) -> float:
	if u <= float(keys[0][0]):
		return float(keys[0][1])
	for i in range(1, keys.size()):
		if u <= float(keys[i][0]):
			var seg: float = max(0.0001, float(keys[i][0]) - float(keys[i - 1][0]))
			var t: float = (u - float(keys[i - 1][0])) / seg
			t = t * t * (3.0 - 2.0 * t)
			return lerpf(float(keys[i - 1][1]), float(keys[i][1]), t)
	return float(keys[keys.size() - 1][1])

# Advance the duel by `dt` and write both knights' current poses into _pose_l/_pose_r.
func _advance_duel(dt: float) -> void:
	_duel_t += dt
	while _duel_t >= _beat_end:
		_roll_beat()
	var dur: float = max(0.001, _beat_end - _beat_start)
	var u := (_duel_t - _beat_start) / dur

	# The strike envelope: rest → wind back → lunge → hold (impact freeze) → recover.
	var drive := _kf(u, [[0.0, 0.12], [0.34, -0.14], [0.50, 1.0], [0.60, 1.0], [1.0, 0.12]])
	# Fire the clash spark once, at the strike, on clash (non-dodge) beats.
	if not _beat_dodge and not _flashed and u >= 0.50:
		_flashed = true
		_clash_flash = 1.0
		_clash_at = _beat_clash
	_clash_flash = max(0.0, _clash_flash - dt * 4.5)

	# Continuous idle motion, always present so neither knight is ever fully still.
	var breath := sin(_duel_t * 1.7)
	var sway := sin(_duel_t * 0.45)          # slow circling drift of the pair

	for idx in 2:
		var face := 1.0 if idx == 0 else -1.0
		var feet0: Vector2 = _KN_L_FEET if idx == 0 else _KN_R_FEET
		var pose: Dictionary = _pose_l if idx == 0 else _pose_r
		var is_atk := idx == _atk_idx
		# The lead attacker commits fully; a partner on a clash beat commits a touch less.
		var d := drive * (1.0 if is_atk else 0.86)
		var lunge: float = max(0.0, d)

		var lean := 0.0
		var guard: float = 0.15 + 0.10 * max(0.0, sin(_duel_t * 1.1 + idx * 2.1))  # subtle shield fidget
		var blade: Vector2
		# Footwork: step in on the lunge / small step back on the wind-up, plus the
		# slow circling drift and a tiny weight-shift so the stance is never rigid.
		var fx := feet0.x + face * d * 5.0 + sway * 2.0 + sin(_duel_t * 1.3 + idx) * 0.5
		var fy := feet0.y + breath * 0.5 + absf(sin(_duel_t * 0.9 + idx * 1.7)) * 0.4

		if _beat_dodge and not is_atk:
			# Defender: lean away, raise the shield to block, sword held in guard.
			var dd := _kf(u, [[0.0, 0.0], [0.45, 0.0], [0.52, 1.0], [0.62, 1.0], [1.0, 0.0]])
			lean = -face * dd * 3.5
			guard = 0.25 + 0.75 * dd
			fx = feet0.x - face * dd * 2.5 + sway * 2.0
			blade = feet0 + Vector2(face * 3.0, -25.0 - 2.0 * dd)
		else:
			# Attacker (or both, on a clash beat): swing the blade to its target and
			# lean into the strike.
			lean = face * lunge * 2.2
			var rest_tip := feet0 + Vector2(face * 3.0, -25.0)
			if _beat_dodge and is_atk:
				# Whiff: the blade sweeps low, across where the foe was.
				blade = rest_tip.lerp(feet0 + Vector2(face * 14.0, -6.0), lunge)
			else:
				blade = rest_tip.lerp(_beat_clash, lunge)
			if d < 0.0:
				blade.y += d * 5.0   # wind-up raises the blade a little higher

		pose["feet"] = Vector2(fx, fy)
		pose["blade"] = blade
		pose["lean"] = lean
		pose["guard"] = clampf(guard, 0.0, 1.0)

# A small crossed-swords glyph for the Arena CTA pill (24x24 box).
func _draw_sword_icon(c: Control) -> void:
	for s in [-1.0, 1.0]:
		var a := Vector2(12 - s * 7, 20)          # hilt (bottom)
		var b := Vector2(12 + s * 7, 4)           # tip (top)
		c.draw_line(a, b, Color(0.85, 0.88, 1.0), 2.6)             # blade
		var guard_c := a.lerp(b, 0.18)
		var perp := Vector2(-(b - a).y, (b - a).x).normalized()
		c.draw_line(guard_c - perp * 4.0, guard_c + perp * 4.0, Color(1.0, 0.82, 0.3), 2.4)  # crossguard

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

func _ellipse_pts(center: Vector2, rx: float, ry: float, n: int = 48) -> PackedVector2Array:
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

# Deluxe championship cup: a tiered marble-gold base and stem, a metallic 3D bowl
# with a bright specular sweep and rounded side shading, an elliptical raised rim,
# rounded tube handles, a jewelled plaque and a few star glints. Light comes from
# the upper-left; the bowl stays near-symmetric so the podium still reads clean.
func _draw_trophy(c: Control, bc: Vector2) -> void:
	var g_hi := Color(1.0, 0.98, 0.80)   # specular highlight
	var g_lt := Color(1.0, 0.87, 0.44)
	var g_md := Color(0.90, 0.66, 0.20)
	var g_dk := Color(0.60, 0.42, 0.12)
	var g_edge := Color(0.40, 0.27, 0.07)

	# Soft cast-shadow puddle under the whole trophy.
	c.draw_colored_polygon(_ellipse_pts(Vector2(bc.x, bc.y + 3.0), 42.0, 8.0),
		Color(0, 0, 0, 0.20))

	# --- tiered base + stem ---
	_draw_bevel_slab(c, Rect2(bc.x - 30, bc.y - 12, 60, 12), g_md, g_lt, g_dk)   # plinth
	_draw_bevel_slab(c, Rect2(bc.x - 20, bc.y - 23, 40, 12), g_lt, g_hi, g_dk)   # tier
	var stem_top := bc.y - 40.0
	c.draw_polygon(PackedVector2Array([
		Vector2(bc.x - 9, stem_top), Vector2(bc.x + 9, stem_top),
		Vector2(bc.x + 6, bc.y - 23), Vector2(bc.x - 6, bc.y - 23)]),
		PackedColorArray([g_lt, g_dk, g_md, g_hi]))
	c.draw_line(Vector2(bc.x - 2, stem_top + 2), Vector2(bc.x - 2, bc.y - 24), g_hi, 2.0)

	# --- bowl: horizontal rows tapering from a wide rim down to the stem ---
	var cup_top := bc.y - 82.0
	var cup_bot := bc.y - 40.0
	var bh := cup_bot - cup_top
	var rw := 34.0   # rim half-width
	var bw := 9.0    # base half-width
	var rows := 22
	for i in rows:
		var t0 := float(i) / float(rows)
		var t1 := float(i + 1) / float(rows)
		var y0 := cup_top + bh * t0
		var y1 := cup_top + bh * t1
		var w0 := bw + (rw - bw) * pow(1.0 - t0, 0.72)
		var w1 := bw + (rw - bw) * pow(1.0 - t1, 0.72)
		var c0 := g_lt.lerp(g_dk, smoothstep(0.0, 1.0, t0))
		var c1 := g_lt.lerp(g_dk, smoothstep(0.0, 1.0, t1))
		c.draw_polygon(PackedVector2Array([
			Vector2(bc.x - w0, y0), Vector2(bc.x + w0, y0),
			Vector2(bc.x + w1, y1), Vector2(bc.x - w1, y1)]),
			PackedColorArray([c0, c0, c1, c1]))

	# Rounded-cylinder edge shading — a dark crescent down each side, deeper on the
	# right (shadow side) than the lit left.
	_bowl_edge(c, bc.x, cup_top, bh, rw, bw, -1.0, Color(g_edge.r, g_edge.g, g_edge.b, 0.40))
	_bowl_edge(c, bc.x, cup_top, bh, rw, bw, 1.0, Color(g_edge.r, g_edge.g, g_edge.b, 0.66))

	# Specular sweep: a soft bright vertical lens just left of center, plus a crisp glint.
	for k in 6:
		var sy := cup_top + 7.0 + k * 5.0
		var sw := lerpf(6.0, 2.5, float(k) / 5.0)
		c.draw_colored_polygon(_ellipse_pts(Vector2(bc.x - 8, sy), sw, 4.5, 16),
			Color(g_hi.r, g_hi.g, g_hi.b, 0.15))
	c.draw_circle(Vector2(bc.x - 14, cup_top + 12), 3.0, Color(1, 1, 1, 0.85))

	# --- rim: raised elliptical lip over a dark hollow interior ---
	c.draw_colored_polygon(_ellipse_pts(Vector2(bc.x, cup_top + 1.0), 34, 9), g_dk)
	c.draw_colored_polygon(_ellipse_pts(Vector2(bc.x, cup_top - 1.0), 33, 8), g_lt)
	c.draw_colored_polygon(_ellipse_pts(Vector2(bc.x, cup_top - 1.0), 25, 5.5),
		g_edge.darkened(0.25))

	# --- rounded tube handles (ear-shaped, rooted to the tapering bowl) ---
	_draw_handle(c, bc.x, cup_top, bh, rw, bw, -1.0, g_dk, g_lt)
	_draw_handle(c, bc.x, cup_top, bh, rw, bw, 1.0, g_dk, g_lt)

	# --- deluxe star glints ---
	_star4(c, Vector2(bc.x + 27, cup_top + 1), 6.0, Color(1, 1, 1, 0.90))
	_star4(c, Vector2(bc.x - 24, cup_top + 36), 4.0, Color(1, 1, 0.95, 0.70))
	_star4(c, Vector2(bc.x + 20, cup_top + 42), 3.0, Color(1, 1, 1, 0.55))

# A 3D bevelled slab: flat face with a lit top/left edge and a shadowed bottom/right.
func _draw_bevel_slab(c: Control, r: Rect2, face: Color, hi: Color, dk: Color) -> void:
	c.draw_rect(r, face)
	c.draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 3), hi)
	c.draw_rect(Rect2(r.position.x, r.position.y, 2, r.size.y), hi)
	c.draw_rect(Rect2(r.position.x, r.position.y + r.size.y - 3, r.size.x, 3), dk)
	c.draw_rect(Rect2(r.position.x + r.size.x - 2, r.position.y, 2, r.size.y), dk)

# A thin shadow crescent hugging one side of the bowl, fading transparent inward.
func _bowl_edge(c: Control, cx: float, top: float, bh: float, rw: float, bw: float,
		side: float, col: Color) -> void:
	var band := 9.0
	var n := 11
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var clear := Color(col.r, col.g, col.b, 0.0)
	for i in n + 1:                                   # outer edge, top -> bottom
		var t := float(i) / float(n)
		var w := bw + (rw - bw) * pow(1.0 - t, 0.72)
		pts.append(Vector2(cx + side * w, top + bh * t))
		cols.append(col)
	for i in range(n, -1, -1):                        # inner edge, bottom -> top
		var t := float(i) / float(n)
		var w := bw + (rw - bw) * pow(1.0 - t, 0.72)
		pts.append(Vector2(cx + side * maxf(w - band, 0.0), top + bh * t))
		cols.append(clear)
	c.draw_polygon(pts, cols)

# A rounded gold handle shaped like an ear: it springs off the bowl just below the
# rim, bulges outward, then curves back to meet the bowl lower down. Both roots are
# read off the exact same taper the bowl uses (same rw/bw/exponent), so the ends
# always sit on the metal instead of floating past a narrower part of the cup.
func _draw_handle(c: Control, cx: float, cup_top: float, bh: float,
		rw: float, bw: float, side: float, dk: Color, lt: Color) -> void:
	var top_t := 0.12   # upper root: high on the bowl, near the wide rim
	var bot_t := 0.82   # lower root: down where the bowl has narrowed
	# Bowl half-width at each root (matches the cup loop's taper), pulled in ~2px so
	# the tube embeds into the metal rather than kissing the outer edge.
	var top_w := bw + (rw - bw) * pow(1.0 - top_t, 0.72) - 2.0
	var bot_w := bw + (rw - bw) * pow(1.0 - bot_t, 0.72) - 2.0
	var p_top := Vector2(cx + side * top_w, cup_top + bh * top_t)
	var p_bot := Vector2(cx + side * bot_w, cup_top + bh * bot_t)
	var bulge := 20.0   # how far the ear swells out from the chord
	var n := 18
	var pts := PackedVector2Array()
	for i in n + 1:
		var s := float(i) / float(n)
		var base := p_top.lerp(p_bot, s)
		base.x += side * sin(s * PI) * bulge     # swell outward, zero at both roots
		pts.append(base)
	c.draw_polyline(pts, dk, 7.0, true)
	# Bright sheen along the upper side of the tube (light from upper-left).
	var hi := PackedVector2Array()
	for p in pts:
		hi.append(p + Vector2(-0.8, -1.4))
	c.draw_polyline(hi, lt, 2.5, true)

# A four-point sparkle: two slim diamonds crossed over a bright core.
func _star4(c: Control, ctr: Vector2, r: float, col: Color) -> void:
	var w := r * 0.26
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(ctr.x, ctr.y - r), Vector2(ctr.x + w, ctr.y),
		Vector2(ctr.x, ctr.y + r), Vector2(ctr.x - w, ctr.y)]), col)
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(ctr.x - r, ctr.y), Vector2(ctr.x, ctr.y - w),
		Vector2(ctr.x + r, ctr.y), Vector2(ctr.x, ctr.y + w)]), col)
	c.draw_circle(ctr, r * 0.22, col)

# Shop illustration: storefront, drawn into the card; offset to centre in the art.
func _draw_shop_card(c: Control) -> void:
	c.draw_set_transform(Vector2(-16, -2), 0.0, Vector2.ONE)
	_draw_shop(c)

# Deluxe 3D storefront: a boxed building with a receding right wall + roof, a
# glossy sign carrying a shopping-bag mark, a scalloped awning with a lit top
# face, two glowing display windows full of merch, a warm glass doorway and a
# bevelled step. Light comes from the upper-left.
func _draw_shop(c: Control) -> void:
	var fx0 := 52.0     # front-left
	var fx1 := 196.0    # front-right
	var top := 74.0
	var bot := 224.0
	var dx := 24.0      # perspective depth
	var dy := 18.0
	_glow(c, Vector2(130, 150), 130.0, Color(1.0, 0.82, 0.45), 6)

	# Ground shadow.
	c.draw_colored_polygon(_ellipse_pts(Vector2(130, bot + 6), 96, 12), Color(0, 0, 0, 0.22))

	# --- building box ---
	var wall := Color(0.94, 0.91, 0.85)
	c.draw_colored_polygon(PackedVector2Array([          # receding right wall
		Vector2(fx1, top), Vector2(fx1 + dx, top - dy),
		Vector2(fx1 + dx, bot - dy), Vector2(fx1, bot)]), wall.darkened(0.28))
	c.draw_colored_polygon(PackedVector2Array([          # lit roof top face
		Vector2(fx0, top), Vector2(fx1, top),
		Vector2(fx1 + dx, top - dy), Vector2(fx0 + dx, top - dy)]), wall.lightened(0.10))
	c.draw_rect(Rect2(fx0, top, fx1 - fx0, bot - top), wall)
	c.draw_polygon(PackedVector2Array([                  # gentle left-lit front shade
		Vector2(fx0, top), Vector2(fx1, top), Vector2(fx1, bot), Vector2(fx0, bot)]),
		PackedColorArray([Color(1, 1, 1, 0.10), Color(0, 0, 0, 0.10),
			Color(0, 0, 0, 0.10), Color(1, 1, 1, 0.10)]))

	# --- sign band ---
	var sign_h := 26.0
	c.draw_rect(Rect2(fx0, top, fx1 - fx0, sign_h), Color(0.18, 0.22, 0.40))
	c.draw_rect(Rect2(fx0, top, fx1 - fx0, 3), Color(0.34, 0.40, 0.64))       # lit top edge
	c.draw_colored_polygon(PackedVector2Array([          # sign side on the receding wall
		Vector2(fx1, top), Vector2(fx1 + dx, top - dy),
		Vector2(fx1 + dx, top - dy + sign_h), Vector2(fx1, top + sign_h)]),
		Color(0.12, 0.15, 0.30))
	_draw_bag_glyph(c, Vector2((fx0 + fx1) * 0.5, top + sign_h * 0.5))

	# --- awning ---
	_draw_awning3d(c, fx0 - 2.0, fx1 + 2.0, top + sign_h)

	# --- windows + door ---
	var base_y := 150.0
	_draw_shop_window(c, Rect2(fx0 + 8, base_y, 40, 46))
	_draw_shop_window(c, Rect2(fx1 - 48, base_y, 40, 46))
	_draw_shop_door(c, Rect2((fx0 + fx1) * 0.5 - 18, base_y - 2, 36, bot - base_y + 2))

	# --- bevelled step ---
	_draw_bevel_slab(c, Rect2(fx0 - 6, bot - 8, (fx1 - fx0) + 12, 10),
		Color(0.80, 0.78, 0.74), Color(0.93, 0.91, 0.87), Color(0.55, 0.53, 0.50))

# 3D striped awning: a lit top slab receding back, a scalloped front and shadow.
func _draw_awning3d(c: Control, ax0: float, ax1: float, ay: float) -> void:
	var h := 24.0
	var depth := 10.0
	var stripes := 7
	var w := (ax1 - ax0) / float(stripes)
	var cream := Color(0.97, 0.94, 0.90)
	var red := Color(0.86, 0.28, 0.32)
	c.draw_colored_polygon(PackedVector2Array([          # lit top face
		Vector2(ax0, ay), Vector2(ax1, ay),
		Vector2(ax1 - 6, ay - depth), Vector2(ax0 + 6, ay - depth)]), Color(0.90, 0.44, 0.46))
	for i in stripes:
		var sx := ax0 + i * w
		var col := red if i % 2 == 0 else cream
		c.draw_rect(Rect2(sx, ay, w, h), col)
		c.draw_circle(Vector2(sx + w * 0.5, ay + h), w * 0.5, col)               # scallop
		c.draw_arc(Vector2(sx + w * 0.5, ay + h), w * 0.5, 0, PI, 10, col.darkened(0.18), 2.0, true)
	c.draw_rect(Rect2(ax0, ay + h - 2, ax1 - ax0, 2), Color(0, 0, 0, 0.15))      # underside
	c.draw_rect(Rect2(ax0, ay - 3, ax1 - ax0, 4), Color(0.55, 0.16, 0.20))       # valance trim

# Glowing display window: recessed frame, glass with a cool-to-warm gradient,
# a shelf of little merch and a diagonal gloss streak.
func _draw_shop_window(c: Control, r: Rect2) -> void:
	c.draw_rect(r.grow(3), Color(0.30, 0.22, 0.18))       # recessed frame
	c.draw_polygon(PackedVector2Array([                   # glass gradient
		r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([Color(0.55, 0.70, 0.85), Color(0.48, 0.62, 0.80),
			Color(1.0, 0.80, 0.45), Color(1.0, 0.76, 0.42)]))
	var sy := r.position.y + r.size.y - 12.0               # merch on a shelf
	c.draw_rect(Rect2(r.position.x + 4, sy, 8, 8), Color(0.90, 0.35, 0.40))
	c.draw_rect(Rect2(r.position.x + 16, sy - 2, 8, 10), Color(0.40, 0.70, 0.95))
	c.draw_rect(Rect2(r.position.x + 28, sy, 8, 8), Color(0.55, 0.85, 0.55))
	c.draw_rect(Rect2(r.position.x, sy + 8, r.size.x, 3), Color(0.30, 0.22, 0.18))
	c.draw_line(r.position + Vector2(6, 4), r.position + Vector2(r.size.x * 0.5, r.size.y * 0.55),
		Color(1, 1, 1, 0.35), 3.0)                         # gloss streak
	c.draw_line(r.position + Vector2(16, 4), r.position + Vector2(r.size.x * 0.72, r.size.y * 0.6),
		Color(1, 1, 1, 0.20), 2.0)
	c.draw_rect(r, Color(0.30, 0.22, 0.18), false, 2.0)

# Warm glass doorway: bevelled frame, gradient door, a lit upper pane and a knob.
func _draw_shop_door(c: Control, r: Rect2) -> void:
	c.draw_rect(r.grow(3), Color(0.28, 0.20, 0.16))       # frame
	c.draw_polygon(PackedVector2Array([                   # door body gradient
		r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([Color(0.42, 0.30, 0.24), Color(0.34, 0.24, 0.20),
			Color(0.30, 0.21, 0.17), Color(0.40, 0.28, 0.22)]))
	var pane := Rect2(r.position.x + 6, r.position.y + 6, r.size.x - 12, 26)
	c.draw_rect(pane, Color(1.0, 0.82, 0.48, 0.9))
	c.draw_line(pane.position + Vector2(3, 3), pane.position + Vector2(pane.size.x * 0.5, pane.size.y * 0.8),
		Color(1, 1, 1, 0.35), 2.0)
	c.draw_rect(pane, Color(0.28, 0.20, 0.16), false, 2.0)
	c.draw_circle(Vector2(r.end.x - 8, (r.position.y + r.end.y) * 0.5 + 6), 2.6, Color(0.95, 0.86, 0.5))

# Small cream shopping-bag mark for the sign band.
func _draw_bag_glyph(c: Control, ctr: Vector2) -> void:
	var col := Color(0.95, 0.90, 0.80)
	var bw := 16.0
	var bh := 14.0
	c.draw_rect(Rect2(ctr.x - bw * 0.5, ctr.y - bh * 0.4, bw, bh), col)       # bag body
	c.draw_arc(ctr - Vector2(0, bh * 0.4), 5.0, PI, TAU, 12, col, 2.0, true)  # handle loop
	c.draw_line(Vector2(ctr.x - bw * 0.5, ctr.y - bh * 0.4),
		Vector2(ctr.x - bw * 0.5 + 3, ctr.y + bh * 0.5), col.darkened(0.15), 1.0)

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
	# Center the whole glyph (bow + lid + body) on the disc, not just the body —
	# the bow adds ~4px of mass above the lid, so offset box_top down by half of it.
	var box_top := ctr.y - (box_h - lid_h - 4.0) * 0.5
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
	_place_card(_arena_card, Vector2(cx - ARENA_SIZE.x * 0.5, sz.y - ARENA_SIZE.y - sz.y * 0.03))

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
	var bob_cards := [_shop_card, _ranks_card, _arena_card]
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

	# Whole-card tap opens the player Profile. Added FIRST so it sits BEHIND the
	# sign-in/out action and the settings gear — those stay tappable on top; the
	# rest of the card (avatar/name) opens the profile.
	var open_btn := Button.new()
	open_btn.flat = true
	open_btn.focus_mode = Control.FOCUS_NONE
	open_btn.size = Vector2(W, H)
	for s in ["normal", "hover", "pressed", "focus"]:
		open_btn.add_theme_stylebox_override(s, StyleBoxEmpty.new())
	open_btn.pressed.connect(_open_profile_popup)
	_profile_card.add_child(open_btn)

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

	# 3D-shaded minted coin (gradient face, visible edge, specular). Drawn in
	# code so it stays crisp at any DPI; the "$" is overlaid on top.
	var disc := Control.new()
	disc.size = Vector2(d, d)
	disc.position = Vector2(disc_x, disc_y)
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.draw.connect(func() -> void:
		PackIcons.draw_coin_3d(disc, Vector2(d, d) * 0.5, d * 0.5))
	_coin_pill.add_child(disc)
	var glyph := Label.new()
	glyph.text = "$"
	glyph.add_theme_font_size_override("font_size", 24)
	# Dark stamped glyph with a pale lower-right shadow → reads as raised metal.
	glyph.add_theme_color_override("font_color", Color(0.34, 0.19, 0.02))
	glyph.add_theme_color_override("font_shadow_color", Color(1.0, 0.94, 0.66, 0.7))
	glyph.add_theme_constant_override("shadow_offset_x", 1)
	glyph.add_theme_constant_override("shadow_offset_y", 2)
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
	# Raised 3D disc: a warm bevel (bright gold rim, dark base) sitting on a drop shadow so
	# it reads as a button popping OFF the pill, not a flat circle.
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.30, 0.17, 0.05)                     # rich brown inner
	s.set_corner_radius_all(int(d * 0.5))
	s.border_color = Color(1.0, 0.80, 0.28)                  # gold outer ring
	s.set_border_width_all(3)
	s.shadow_color = Color(0.0, 0.0, 0.0, 0.55)              # cast shadow = raised
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 4)
	_coin_plus_btn.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = Color(0.38, 0.22, 0.07)                    # brighter on hover (lifts more)
	sh.shadow_size = 8
	sh.shadow_offset = Vector2(0, 5)
	_coin_plus_btn.add_theme_stylebox_override("hover", sh)
	var sp := s.duplicate() as StyleBoxFlat
	sp.bg_color = Color(0.16, 0.08, 0.02)                    # darker + shadow shrinks = pressed IN
	sp.shadow_size = 2
	sp.shadow_offset = Vector2(0, 1)
	_coin_plus_btn.add_theme_stylebox_override("pressed", sp)
	_coin_plus_btn.add_theme_color_override("font_color", Color(1.0, 0.82, 0.30))  # gold plus
	_coin_plus_btn.add_theme_color_override("font_hover_color", Color(1.0, 0.88, 0.45))
	_coin_plus_btn.pressed.connect(_open_coins_popup)
	add_child(_coin_plus_btn)

	# Glossy top sheen — a soft warm-white highlight on the upper half so the disc reads as
	# a rounded dome catching light from above (the key "3D" cue). Purely decorative.
	var sheen := Panel.new()
	var shw := d * 0.60
	var shh := d * 0.34
	sheen.size = Vector2(shw, shh)
	sheen.position = Vector2((d - shw) * 0.5, d * 0.13)
	sheen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sheen_st := StyleBoxFlat.new()
	sheen_st.bg_color = Color(1.0, 0.96, 0.78, 0.30)
	sheen_st.set_corner_radius_all(int(shh * 0.5))
	sheen.add_theme_stylebox_override("panel", sheen_st)
	_coin_plus_btn.add_child(sheen)
	# The sheen dims while the button is held so the disc reads as pressing in (paired with
	# the pressed style's shrunk shadow, which does the "sink").
	_coin_plus_btn.button_down.connect(func() -> void: sheen.modulate.a = 0.4)
	_coin_plus_btn.button_up.connect(func() -> void: sheen.modulate.a = 1.0)

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

# Yesterday's leaderboard-standing reward just landed — show the summary popup.
func _on_daily_rank_reward(total: int, results: Array) -> void:
	if not is_inside_tree():
		return
	var popup := DailyRankRewardPopup.new()
	popup.total = total
	popup.results = results
	add_child(popup)

# Player profile opens as a modal popup over the home screen (not a screen swap),
# so home stays painted behind the dim backdrop.
func _open_profile_popup() -> void:
	var popup := ProfilePopup.new()
	popup.game_manager = game_manager
	add_child(popup)

# ---------------- settings popup ----------------

# Minimal settings modal opened by the profile-card gear: a music on/off toggle,
# a tutorial replay, a support section (contact + privacy policy), a close
# button and a footer with the app version. Dismissed by tapping outside or
# Close.
const CONTACT_EMAIL := "RaviachStudios@gmail.com"
const PRIVACY_POLICY_URL := "https://raviachstudios.github.io/Raviach-policy/"

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

	var show_delete := FirebaseManager.is_signed_in()
	const PW := 440.0
	const BASE_PH := 466.0
	const DELETE_SECTION_H := 94.0
	var ph := BASE_PH + (DELETE_SECTION_H if show_delete else 0.0)
	var panel := _card_panel(Vector2(PW, ph), Color(0.05, 0.06, 0.16, 0.98),
		Color(0.40, 0.50, 1.0, 0.55), Color(0.0, 0.0, 0.0, 0.55))
	panel.position = (sz - Vector2(PW, ph)) * 0.5
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
	title.position = Vector2(20, 22)
	title.size = Vector2(PW - 40, 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(title)

	_popup_section_label(panel, "PREFERENCES", 80, PW)
	var music_on := AudioManager.is_music_on()
	_settings_music_btn = _make_popup_button(panel, "Music:  %s" % ("On" if music_on else "Off"),
		Vector2(40, 100), Vector2(PW - 80, 50), Color(0.16, 0.18, 0.34), _toggle_music)
	_make_popup_button(panel, "Replay Tutorial", Vector2(40, 158), Vector2(PW - 80, 50),
		Color(0.16, 0.18, 0.34), _replay_tutorial.bind(overlay))

	_popup_divider(panel, 224, PW)
	_popup_section_label(panel, "SUPPORT", 234, PW)
	_make_popup_button(panel, "Contact Us", Vector2(40, 254), Vector2(PW - 80, 50),
		Color(0.16, 0.18, 0.34), _contact_us)
	_make_popup_button(panel, "Privacy Policy", Vector2(40, 312), Vector2(PW - 80, 50),
		Color(0.16, 0.18, 0.34), _open_privacy_policy)

	# Signed-in-only danger zone. Guests have no server-side account to delete.
	var after_y := 374.0
	if show_delete:
		_popup_divider(panel, after_y, PW)
		_popup_section_label(panel, "ACCOUNT", after_y + 12, PW)
		_make_popup_button(panel, "Delete Account", Vector2(40, after_y + 32), Vector2(PW - 80, 50),
			Color(0.62, 0.16, 0.20), _confirm_delete_account.bind(overlay))
		after_y += DELETE_SECTION_H

	_make_popup_button(panel, "Close", Vector2(40, after_y), Vector2(PW - 80, 50),
		Color(0.15, 0.6, 0.95), overlay.queue_free)

	var footer := Label.new()
	footer.text = "Simon v%s   ·   %s" % [ProjectSettings.get_setting("application/config/version", ""), CONTACT_EMAIL]
	footer.add_theme_font_size_override("font_size", 13)
	footer.add_theme_color_override("font_color", Color(0.50, 0.53, 0.74, 0.65))
	footer.position = Vector2(20, after_y + 60)
	footer.size = Vector2(PW - 40, 20)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(footer)

	# Gentle entrance: fade + scale-pop on the panel.
	panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2(0.92, 0.92)
	overlay.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(overlay, "modulate:a", 1.0, 0.20).set_trans(Tween.TRANS_SINE)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# Small uppercase caption used to group buttons within a popup (e.g. "SUPPORT").
func _popup_section_label(panel: Control, text: String, y: float, pw: float) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.52, 0.55, 0.82, 0.75))
	lbl.position = Vector2(40, y)
	lbl.size = Vector2(pw - 80, 16)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(lbl)

# Hairline separator between grouped sections of a popup.
func _popup_divider(panel: Control, y: float, pw: float) -> void:
	var line := ColorRect.new()
	line.color = Color(1.0, 1.0, 1.0, 0.08)
	line.position = Vector2(40, y)
	line.size = Vector2(pw - 80, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(line)

func _toggle_music() -> void:
	if AudioManager.is_music_on():
		AudioManager.stop_bg_music()
	else:
		AudioManager.play_bg_music()
	if _settings_music_btn and is_instance_valid(_settings_music_btn):
		_settings_music_btn.text = "Music:  %s" % ("On" if AudioManager.is_music_on() else "Off")

# Closes the settings popup and forces the first-run tour to play again,
# bypassing the "already seen" flags that normally gate it.
func _replay_tutorial(overlay: Control) -> void:
	overlay.queue_free()
	if _tutorial_active or has_node("HomeTutorial"):
		return
	_start_tutorial()

func _contact_us() -> void:
	OS.shell_open("mailto:%s?subject=Simon%%20Feedback" % CONTACT_EMAIL)

func _open_privacy_policy() -> void:
	OS.shell_open(PRIVACY_POLICY_URL)

# Second confirmation modal opened from the settings popup's "Delete Account".
# No backdrop-tap-to-dismiss on this one, deliberately — an irreversible action
# should only close via an explicit Cancel or Delete Forever tap.
func _confirm_delete_account(_settings_overlay: Control) -> void:
	var sz := get_viewport_rect().size
	var overlay := Control.new()
	overlay.name = "DeleteAccountPopup"
	overlay.position = Vector2.ZERO
	overlay.size = sz
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.01, 0.04, 0.72)
	dim.position = Vector2.ZERO
	dim.size = sz
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(dim)

	const PW := 440.0
	const PH := 336.0
	var panel := _card_panel(Vector2(PW, PH), Color(0.05, 0.06, 0.16, 0.98),
		Color(0.75, 0.24, 0.28, 0.6), Color(0.0, 0.0, 0.0, 0.55))
	panel.position = (sz - Vector2(PW, PH)) * 0.5
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(panel)

	var title := Label.new()
	title.text = "Delete Account?"
	title.add_theme_font_size_override("font_size", 27)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.position = Vector2(24, 26)
	title.size = Vector2(PW - 48, 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(title)

	var body := Label.new()
	body.text = "This permanently erases your coins, scores, cosmetics and Arena history — it can't be undone.\n\nYour one-time Remove Ads purchase isn't affected; it's restored automatically if you sign back in."
	body.add_theme_font_size_override("font_size", 15)
	body.add_theme_color_override("font_color", Color(0.80, 0.83, 0.95, 0.92))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.position = Vector2(24, 72)
	body.size = Vector2(PW - 48, 160)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(body)

	var half := (PW - 48.0 - 14.0) * 0.5
	_make_popup_button(panel, "Cancel", Vector2(24, PH - 66), Vector2(half, 50),
		Color(0.16, 0.18, 0.34), overlay.queue_free)
	_make_popup_button(panel, "Delete Forever", Vector2(24 + half + 14, PH - 66), Vector2(half, 50),
		Color(0.68, 0.16, 0.20), _do_delete_account.bind(overlay, title, body))

	panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2(0.92, 0.92)
	overlay.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(overlay, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_SINE)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# Runs the actual deletion once "Delete Forever" is confirmed. On success,
# FirebaseManager.delete_account() ends by treating this exactly like a sign
# -out, which home_screen's own `signed_out` handler already reacts to by
# rebuilding the whole home screen — that discards this overlay along with
# everything else, so there's nothing left to close here. On failure, the
# dialog flips to an error state so the player can retry or back out.
func _do_delete_account(overlay: Control, title: Label, body: Label) -> void:
	for c in title.get_parent().get_children():
		if c is Button:
			c.disabled = true
	title.text = "Deleting…"
	body.text = "Please wait — this only takes a moment."
	var result: Dictionary = await FirebaseManager.delete_account()
	if not is_instance_valid(overlay):
		return
	if bool(result.get("ok", false)):
		return
	title.text = "Something Went Wrong"
	body.text = "We couldn't delete your account. Check your connection and try again — if it keeps failing, sign out, sign back in, then retry, or use Contact Us."
	for c in title.get_parent().get_children():
		if c is Button:
			c.disabled = false

# ---------------- sign-in popup (welcome + feature gates) ----------------

# First-launch welcome popup: shown once per launch (gated on welcome_prompt_shown
# in _ready) when signed out. The player must pick sign in or guest before they
# can interact with the menu.
func _show_welcome_popup() -> void:
	# If the player picks "Play as Guest", start the first-run tour once the
	# popup closes. (Picking "Sign In" routes through name-pick → a fresh home,
	# whose _ready offers the tour based on the wallet-doc flag instead.)
	_show_sign_in_popup(
		"Welcome to Simon",
		"Sign in to save your coins, climb the leaderboards and claim daily rewards — or jump straight in as a guest.",
		"Play as Guest",
		_maybe_start_tutorial)

# Feature-gate popup: shown when a guest taps Shop or Leaderboards. Same
# visual, but the secondary action is "Maybe Later" — the user is already
# playing as a guest, so "Play as Guest" would be redundant copy.
func _show_sign_in_required_popup(title_text: String, subtitle_text: String) -> void:
	_show_sign_in_popup(title_text, subtitle_text, "Maybe Later")

# Shared builder for both popup variants. Caller passes the title / subtitle
# copy and the label for the secondary (dismiss) button.
func _show_sign_in_popup(title_text: String, subtitle_text: String, secondary_label: String,
		on_dismiss: Callable = Callable()) -> void:
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

	# The secondary (dismiss) button frees the popup and then runs an optional
	# follow-up (e.g. the welcome variant kicks off the first-run tour).
	var dismiss := func() -> void:
		overlay.queue_free()
		if on_dismiss.is_valid():
			on_dismiss.call()
	_make_popup_button(panel, secondary_label, Vector2(40, 264), Vector2(bw, 56),
		Color(0.16, 0.18, 0.34), dismiss)

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

# Opportunistic shop warm-up. Once the home screen has been sitting idle for a beat,
# quietly pre-compile the theme-preview shaders that fill the shop's opening view — the
# exact set the shop's loading veil otherwise blocks on (its first three grid rows, see
# shop_screen._begin_load's priority_count). Each warm-up is one tiny throwaway 16x16
# render per frame (BackgroundManager.prewarm_previews), so it's invisible here; by the
# time the player taps Shop those shaders are already compiled and the veil lifts almost
# immediately instead of holding for the first-open compile burst. Skipped work for
# players who never open the shop is exactly one no-op call. Idempotent: prewarm_previews
# ignores ids already warm or queued, and the _shop_prewarm_started guard stops repeats.
func _schedule_shop_prewarm() -> void:
	if _shop_prewarm_started:
		return
	_shop_prewarm_started = true
	# Gate behind GL stability so this never bakes into a torn context right after a
	# resume (see the app-pause/resume GL guard on GameManager), then let home settle
	# so the warm-up never competes with the entry animations or a first-run tour.
	if game_manager:
		await game_manager.await_gl_stable()
	if not is_inside_tree():
		return
	await get_tree().create_timer(2.5).timeout
	if not is_inside_tree():
		return
	var items: Array = []
	for cat in ShopScreen.CATEGORIES:
		if cat.get("key", "") == "themes":
			items = cat.get("items", [])
			break
	# Match the shop's veil-blocking set: its first three grid rows.
	var priority: int = ShopScreen.GRID_COLS * 3
	BackgroundManager.prewarm_previews(items.slice(0, priority))

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

func _on_arena() -> void:
	# Arena needs an identity (a name others can see + a uid to own contests).
	if FirebaseManager.is_signed_in() and FirebaseManager.has_display_name():
		game_manager.show_arena()
	else:
		_show_sign_in_required_popup(
			"Sign In for the Arena",
			"Sign in and pick a name to create and join contests with friends.")

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
	# The Google sign-in dialog is a separate Android activity that tears down and
	# recreates our GL context. Rebuilding the whole screen here (shader compiles,
	# texture uploads, offscreen SubViewport bakes) on the resume frame can hit an
	# invalid render target and segfault the GL thread on Adreno. Wait for the
	# context to be proven stable before swapping screens.
	await game_manager.await_gl_stable()
	if not is_inside_tree():
		return  # navigated away (or freed) while we were waiting out the resume
	if FirebaseManager.has_display_name():
		game_manager.show_home()  # rebuild to show name + leaderboards access
	else:
		game_manager.show_name_picker()

func _on_sign_in_failed(_error: String) -> void:
	_signing_in = false

func _on_signed_out() -> void:
	game_manager.show_home()

# ---------------- first-run tutorial ----------------

# Local persistence for the guest "has seen the tour" flag. Signed-in users use
# the Firestore flag (CoinsManager.tutorial_seen) instead; we still set this
# local flag for them too, so the tour never repeats on this device even before
# the wallet doc has loaded on a later launch.
const PREFS_PATH := "user://prefs.cfg"

func _local_tutorial_seen() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(PREFS_PATH) != OK:
		return false
	return bool(cfg.get_value("tutorial", "seen", false))

func _set_local_tutorial_seen() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PREFS_PATH)                     # keep any other prefs already stored
	cfg.set_value("tutorial", "seen", true)
	cfg.save(PREFS_PATH)

# Decide whether to run the tour, then run it. Safe to call more than once: it
# no-ops if a tour is already up, if the sign-in gate is still showing, or once
# the flag says it's been seen. The local flag wins outright — a guest who saw
# the tour and then signs in (a fresh account with no server-side flag yet)
# must not be shown it again — and it's synced up to the wallet doc once one
# becomes available. Otherwise, for signed-in users, we wait (once) for the
# wallet doc so it can read the server-side flag.
func _maybe_start_tutorial() -> void:
	if _tutorial_active or has_node("HomeTutorial"):
		return
	# The welcome / sign-in gate closes with queue_free (deferred), so the node
	# can still be present this same frame — ignore it if it's on its way out.
	var gate := get_node_or_null("SignInPopup")
	if gate and not gate.is_queued_for_deletion():
		return
	if _local_tutorial_seen():
		if FirebaseManager.is_signed_in() and CoinsManager.is_loaded() and not CoinsManager.tutorial_seen:
			CoinsManager.mark_tutorial_seen()
		return
	if FirebaseManager.is_signed_in():
		if not CoinsManager.is_loaded():
			if not _awaiting_coins_for_tutorial:
				_awaiting_coins_for_tutorial = true
				CoinsManager.loaded.connect(_maybe_start_tutorial, CONNECT_ONE_SHOT)
			return
		_awaiting_coins_for_tutorial = false
		if CoinsManager.tutorial_seen:
			_set_local_tutorial_seen()
			return
	_start_tutorial()

# Build the step list from whatever widgets this screen is actually showing
# (a guest has no coin pill / daily claim, so those steps are skipped), then
# spawn the overlay.
func _start_tutorial() -> void:
	_tutorial_active = true
	var steps: Array = []
	steps.append({
		"rect": Rect2(),
		"title": "Welcome to Simon!",
		"body": "Quick tour, then you're off. Tap Next — skip anytime."})
	if _coin_pill or _daily_btn or not _shop_card.is_empty():
		var body_text := "Spend coins in the Shop to customize Simon."
		if _coin_pill or _daily_btn:
			body_text = "Earn coins by playing and from your daily reward, then spend them in the Shop."
		var rect := Rect2()
		if not _shop_card.is_empty():
			rect = (_shop_card["wrap"] as Control).get_global_rect()
		elif _coin_pill:
			rect = _coin_pill.get_global_rect()
		steps.append({"rect": rect, "title": "Coins & Shop", "body": body_text})
	if not _start_lm.is_empty():
		# Spotlight the visible orb, not the full 300×300 tap target.
		var c: Vector2 = (_start_lm["wrap"] as Control).get_global_rect().get_center()
		steps.append({
			"rect": Rect2(c - Vector2(120, 120), Vector2(240, 240)),
			"title": "Play Simon",
			"body": "Medium and Hard add more buttons and move faster — pick your challenge and tap START."})
	if not _ranks_card.is_empty():
		steps.append({
			"rect": (_ranks_card["wrap"] as Control).get_global_rect(),
			"title": "Leaderboards",
			"body": "See how your best scores stack up against players worldwide."})
	if not _arena_card.is_empty():
		steps.append({
			"rect": (_arena_card["wrap"] as Control).get_global_rect(),
			"title": "The Arena",
			"body": "Create or join contests and go head-to-head with your friends."})

	var tut := HomeTutorial.new()
	tut.name = "HomeTutorial"
	tut.finished.connect(_on_tutorial_finished)
	add_child(tut)
	tut.setup(steps)

func _on_tutorial_finished() -> void:
	_tutorial_active = false
	# Persist "seen" on both halves the app reads: the local file always, plus the
	# wallet doc when signed in (so it follows the account across devices).
	_set_local_tutorial_seen()
	if FirebaseManager.is_signed_in():
		CoinsManager.mark_tutorial_seen()
