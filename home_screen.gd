extends Control

# Premium main menu — a "magical space" home screen built entirely from Godot
# nodes + shaders + _draw() + tweens (no static images):
#   - a deep purple→blue gradient sky with twinkling stars (BG_SHADER)
#   - one large, thin glowing orbital ring of soft colored orbs behind everything
#   - the LUMEO logo (white, soft-shadowed; the "O" is a physical gold BUTTON)
#     over a "MEMORY CHALLENGE" subtitle
#   - TOP-LEFT: a gold coin pill + a Daily Hub button (red notification dot)
#     that drops a panel holding the daily claim and the daily-task progress
#   - TOP-RIGHT: three separate glass controls — a profile capsule (avatar +
#     name), an auth button (sign out / sign in) and a settings disc
#   - CENTER: a floating grassy island carrying the big 3D START button
#   - LEFT / RIGHT: premium Shop and Leaderboard cards (illustration + CTA button)
#   - BOTTOM-CENTER: a small "How to Play" card
# Everything is laid out symmetrically and re-flowed in _layout() on resize.

const DailyClaimPopup := preload("res://daily_claim_popup.gd")
const DailyTasksPopup := preload("res://daily_tasks_popup.gd")
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
# The logo's "O" is a real button, not a glyph: a static gold body (`_o_frame`)
# with a raised gold cap (`_o_cap`) sunk into it, the cap carrying the white
# illuminated trim (`_o_trim`) that draws the letter's counter. `_o_aura` is the
# warm halo it sits in — its child `_o_glow` breathes, the parent flashes on press,
# so the two tweens never touch the same property.
var _o_frame: Node2D
var _o_cap: Node2D
var _o_trim: Node2D
var _o_bloom: Node2D
var _o_aura: Node2D
var _o_glow: Sprite2D
var _o_raise := 0.0                # how far the cap stands proud of the collar, px
var _o_cap_rest := 0.0             # the cap's resting y inside its box

# The START button, in the same three pieces: a static dark-metal frame drawn by the
# landmark's own drawer, the luminous accent ring that cycles through the game's
# colours (`_play_accent` = the hot trim, `_play_glow` = its coloured bloom), and the
# violet cap that carries the arrow and is the only part that moves when pressed.
var _play_accent: Node2D
var _play_glow: Node2D
var _play_cap: Node2D
var _play_flash := 0.0             # 0 at rest .. 1 at the bottom of a press
var _play_cap_rest := 0.0
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
const _KN_TF_POS := Vector2(13.0, -23.6)   # matches _draw_arena_colosseum's canvas transform
const _KN_TF_SCL := Vector2(1.28, 1.13)
const _KN_L_FEET := Vector2(91.0, 86.0)    # neutral stance, pre-transform (ctr 107,74)
const _KN_R_FEET := Vector2(123.0, 86.0)
# One additive node per pad button, holding that button's "lit" state. Only their
# `modulate:a` is animated (see _arena_pulse), so the colosseum art stays static.
var _pad_lights: Array[Node2D] = []
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
var _account_hud: Control
# Red "you earned something new" dot on the account bubble, twin of the daily
# pills' badges. Cleared by visiting the profile (where the gallery lives, and
# where each new badge wears a dot of its own until it's looked at).
var _ach_badge: Panel
var _signing_in := false
# Top-left coin pill (signed-in only). Mirrors the in-game HUD style but lives
# at a fixed corner here. Daily-claim button sits just under it.
var _coin_pill: Panel
var _coin_lbl: Label
var _coin_plus_btn: Button       # opens the coin-pack purchase popup
var _coin_loading_tween: Tween   # animates "." -> ".." -> "..." while CoinsManager loads
var _coin_loading_idx: int = 0
# Daily Hub — the nav pill right of the coin pill, plus the dropdown it expands.
# The pill carries a red dot whenever anything daily is outstanding; the panel
# holds the two rituals (login claim + task board) as one row each.
var _hub_btn: Button
var _hub_badge: Panel            # red "something is waiting" dot on the pill
var _hub_caret: Control          # the little "v" that flips when the panel opens
var _hub_clip: Control           # animated reveal window (clips the panel)
var _hub_panel: Panel
var _hub_catcher: Control        # full-screen outside-tap dismisser
var _hub_tween: Tween
var _hub_tick: Timer             # 1s countdown refresh, runs only while open
var _hub_open := false
var _claim_status: Label         # "Ready to claim" / "Next reward in 7h 12m"
var _claim_btn: Button           # bright purple Claim (available)
var _claim_done: Panel           # green ✓ Claimed chip (already collected)
var _tasks_count_lbl: Label      # "2/5 Completed"
var _tasks_bar_fill: Panel
var _tasks_ready_dot: Panel      # red dot on View Tasks when rewards are ready
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
	_build_account_hud()
	_build_credits()
	if FirebaseManager.is_signed_in():
		_build_coin_pill()
		_build_daily_hub()
		# Show a summary popup when yesterday's leaderboard reward lands. Connect
		# BEFORE kicking off the grant so we never miss the (possibly synchronous
		# in editor) emission.
		CoinsManager.daily_rank_reward_granted.connect(_on_daily_rank_reward)
		# Opening the home screen is the heartbeat of the login-streak system AND
		# the moment we surface the previous day's leaderboard-standing reward
		# (already credited server-side; this just shows/clears the receipt).
		# If the wallet hasn't finished loading yet, defer both until it has.
		if CoinsManager.is_loaded():
			CoinsManager.register_login()
			CoinsManager.consume_pending_daily_rewards()
		else:
			CoinsManager.loaded.connect(CoinsManager.register_login, CONNECT_ONE_SHOT)
			CoinsManager.loaded.connect(CoinsManager.consume_pending_daily_rewards, CONNECT_ONE_SHOT)

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

	# "L U M E [O]" - the O is not a letter but a gold BUTTON shaped like one: the
	# same seat/cap/lit-trim hardware the board's buttons are built from (see
	# _make_o_button). It ends the word, so it is the piece the eye lands on last.
	var w_left := font.get_string_size("L U M E", HORIZONTAL_ALIGNMENT_LEFT, -1, f).x
	var w_space := font.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, f).x
	var dr := 90.0                                   # O-button diameter (~ cap height)
	var g := w_space * 0.60                          # gap before the button
	var th := 112.0                                  # title band height
	var group_w := w_left + g + dr
	var x0 := (lw - group_w) * 0.5

	_logo_box.add_child(_logo_letter("L U M E", f, Vector2(x0, 0), Vector2(w_left, th)))
	# Drop the O slightly below the cap-height center so it visually sits alongside
	# the lowercase center of the surrounding capitals (the letter "O" in this font
	# reads optically lower than the cap-tops).
	var o_ctr := Vector2(x0 + w_left + g + dr * 0.5, th * 0.6 + f * 0.04)
	_logo_box.add_child(_make_o_button(dr, o_ctr))

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

# ---------------- the logo "O": a gold button ----------------

# The gold the logo's O is cut from. The START button next to it is dark metal, but
# both are milled to the SAME profile (HW_* below), which is what makes them read as
# two pieces of one machine rather than as two unrelated ornaments.
const LUX_DEEP := Color(0.34, 0.19, 0.02)          # the shadow side / extruded wall
const LUX_BASE := Color(0.86, 0.61, 0.13)          # the metal itself
const LUX_HI := Color(1.00, 0.91, 0.55)            # where the key light lands
const LUX_RIM := Color(1.00, 0.60, 0.20)           # warm bounce on the far edge
const LUX_LIGHT := Vector2(-0.55, -0.84)           # key light, upper left

# ---------------------------------------------------------------------------
# The hardware profile
# ---------------------------------------------------------------------------
# Both buttons on this screen are turned from the same three parts, in the order an
# illuminated arcade button is actually built: an ILLUMINATED BEZEL immediately
# around the cap, a DARK SEAT it is screwed into, and the raised CAP itself. Read
# from the rim inward as fractions of the bezel's outer radius:
#
#   1.00 .. 0.955  the outer CHAMFER — dark metal, the frame's own lip
#   0.955 .. 0.845 the LIT LAND — the frame's face, and the only coloured part
#   0.845 .. 0.800 the inner CHAMFER, rolling down off the land
#   0.800 .. 0.745 the SEAT: the darkest ring on the object, which is what separates
#                  the luminous frame from the cap instead of a slab of grey metal
#   0.745 ..       the CAP: the raised violet surface, which owns the middle
#
# There used to be a wide gunmetal CROWN between the trim and the cap — 30% of the
# radius of bare grey metal — and it was the single thing that made the button read
# as a mechanical disk rather than a button. It is gone: the lit bezel now runs
# straight into a thin dark seat, and the cap took the space back (0.745 of the
# radius against the old 0.70, so the violet surface is 13% wider and the frame
# around it is thin).
#
# Drawn from above with the key light at upper-left, so each band is shaded by how
# squarely it faces that light and by how proud of the bevel it sits.
const HW_LIP := 0.955           # bezel rim -> the lit land
const HW_LAND := 0.845          # lit land -> inner chamfer
const HW_CHAMFER := 0.800       # inner chamfer -> the seat
const HW_SEAT := 0.745          # the seat -> the cap
const HW_SEGS := 64

# The O is turned from the same parts as START, in gold, and read from the rim in:
#
#   1.00 .. 0.930  the SEAT — a thin near-black collar, the gap the cap is sunk into
#   0.930 ..       the CAP — the raised POLISHED gold surface, which owns the object
#   0.659 .. 0.522 the white illuminated TRIM, seated in a groove milled in the cap
#   0.430 ..       the BORE — the dark counter, the hole that makes it the letter O
#
# There used to be a wide gold BEZEL outside all of this — a knurled wall from 1.00
# to 0.915 and a brushed crown down to 0.845, i.e. a fifth of the radius of frame
# wrapped around the button. At logo size that outer ring was the biggest shape in
# the object, so the O read as a decorative gold band with something in the middle
# rather than as a letter. It is gone. The cap took the whole radius back (0.930
# against the old 0.780, so the gold surface is 19% wider), the seat shrank to the
# thin dark collar that is all a seated cap actually needs, and the depth now comes
# from the button BODY's own barrel wall rather than from a frame around it.
#
# The trim and the bore were widened in the same proportion, so the white ring keeps
# exactly its old share of the gold and the counter still reads as a hole punched
# through a solid — which together are what spell the letter.
const O_SEAT := 0.930           # the seat -> (the cap is sunk into it)
const O_CAP := 0.930            # outer radius of the raised cap
const O_TRIM := 0.590           # centre-line of the white trim tube
const O_TRIM_W := 0.137         # its width, as a fraction of the radius
const O_BORE := 0.430           # the counter: the hole through the button
# The collar is the same alloy as the cap in a much duller finish. That tonal step —
# dark bronze seat, polished cap — is what makes the raised surface read as its own
# part instead of as a dome milled out of one lump of gold.
const O_BEZEL := Color(0.46, 0.30, 0.06)

# The LUMEO "O": a premium gold BUTTON whose cap happens to be a ring, so the letter
# reads as a letter and the object reads as hardware.
#
#   _o_frame   static body — the extruded barrel that gives the object its thickness
#              and the thin dark collar the cap is seated in
#   _o_cap     the raised gold surface: an annular cap with a bevelled crown, its own
#              wall of thickness underneath, and a specular streak on the lit shoulder
#   _o_trim    the white illuminated trim ringing the counter — a lit tube seated in a
#              groove milled into the cap's inner edge, NOT a stroke on top of it
#
# Only the cap + trim move on a press; the body never does. Everything is drawn once
# into static Node2Ds — the idle breathing and the press ride on node transforms and
# modulate, so nothing here ever repaints.
func _make_o_button(d: float, center: Vector2) -> Control:
	var box := Control.new()
	box.size = Vector2(d, d * 1.16)                  # room under it for the barrel
	box.position = center - Vector2(d, d) * 0.5
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var r := d * 0.5
	_o_raise = d * 0.065                             # how far the cap stands proud

	# the warm light the gold sits in. Two nodes so the idle breath (on the glow) and
	# the press flare (on the aura) never fight over one property.
	_o_aura = Node2D.new()
	_o_aura.position = Vector2(r, r)
	box.add_child(_o_aura)
	_o_glow = Sprite2D.new()
	_o_glow.texture = _orb_tex
	_o_glow.scale = Vector2.ONE * (d * 2.1 / 128.0)
	_o_glow.modulate = Color(1.0, 0.72, 0.26, 0.20)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_o_glow.material = add
	_o_aura.add_child(_o_glow)

	_o_frame = Node2D.new()
	_o_frame.position = Vector2(r, r)
	_o_frame.draw.connect(_draw_o_frame.bind(_o_frame, r))
	box.add_child(_o_frame)

	_o_cap = Node2D.new()
	_o_cap_rest = r - _o_raise
	_o_cap.position = Vector2(r, _o_cap_rest)
	_o_cap.draw.connect(_draw_o_cap.bind(_o_cap, r))
	box.add_child(_o_cap)

	# The trim rides on the cap (so it travels with it) but is its own node. Its tube
	# is drawn OPAQUE — white over gold has to stay white, and additive white on gold
	# only ever comes out yellow — with the bloom split into an additive child so a
	# press can flare the light without bleaching the metal.
	_o_trim = Node2D.new()
	_o_trim.draw.connect(_draw_o_trim.bind(_o_trim, r))
	_o_cap.add_child(_o_trim)
	_o_bloom = Node2D.new()
	_o_bloom.material = add
	_o_bloom.draw.connect(_draw_o_bloom.bind(_o_bloom, r))
	_o_trim.add_child(_o_bloom)

	# input: a transparent disc over the button. It has no destination — the O is a
	# piece of hardware you can push, and pushing it is the whole reward.
	var btn := Button.new()
	btn.size = Vector2(d, d)
	btn.focus_mode = Control.FOCUS_NONE
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(st, empty)
	btn.button_down.connect(_on_o_press)
	btn.button_up.connect(_on_o_release)
	box.add_child(btn)
	return box

# The static half of the O: the button BODY — everything that does not move when it
# is pressed. With the outer bezel gone this is just two things: the barrel that
# gives the object its thickness, and the thin dark collar the cap is seated in.
func _draw_o_frame(c: Node2D, r: float) -> void:
	var lit := LUX_LIGHT.normalized()
	var depth := r * 0.20                            # how far the body stands off the page

	# the barrel: the body's footprint stamped downward, darkest at the bottom and
	# warming as it climbs, so the wall reads as gold turning under into shadow. This
	# is now the ONLY thing carrying the button's depth, so it is worth its own
	# rolled highlight at the top of the lit side.
	var steps := 14
	for i in range(steps, 0, -1):
		var f := float(i) / float(steps)
		c.draw_circle(Vector2(0.0, depth * f), r,
			Color(0.10, 0.05, 0.01).lerp(Color(0.50, 0.32, 0.06), 1.0 - f))
	# contact shadow where the barrel meets the page
	c.draw_colored_polygon(_ellipse_pts(Vector2(0.0, depth * 1.05), r * 0.90, r * 0.16),
		Color(0.03, 0.01, 0.06, 0.38))
	# the bright turn at the very rim, where the wall rolls over into the cap collar
	c.draw_arc(Vector2.ZERO, r * 0.985, deg_to_rad(-176.0), deg_to_rad(-92.0), 18,
		Color(1.00, 0.86, 0.48, 0.42), r * 0.026, true)

	# the SEAT the cap drops into — a thin near-black collar, deliberately the darkest
	# ring on the object, so the raised surface reads as a separate piece seated in
	# the body rather than as a dome milled out of one block
	_ring_band(c, r, O_SEAT, 1.00, lit, 0.14, 0.02, LUX_DEEP.darkened(0.35))
	for i in 4:                                      # the cap's shadow cast into it
		var f := float(i) / 3.0
		c.draw_arc(Vector2(0.0, _o_raise * 0.6), r * (O_CAP + 0.006 + f * 0.014), 0.0, TAU,
			HW_SEGS, Color(0.04, 0.01, 0.00, 0.42 - f * 0.11), r * 0.026, true)

	# clean antialiased silhouette over the flat-shaded quads
	c.draw_arc(Vector2.ZERO, r, 0.0, TAU, HW_SEGS, Color(0.18, 0.09, 0.01, 0.80), 2.0, true)

# The moving half: the raised gold ring-shaped cap that carries the white trim.
func _draw_o_cap(c: Node2D, r: float) -> void:
	var lit := LUX_LIGHT.normalized()
	var outer := r * O_CAP                           # seated inside the body's collar
	var inner := r * O_BORE                          # the counter — the hole in the O
	var trim := r * O_TRIM                           # where the white trim is seated
	var half := r * O_TRIM_W * 0.5                   # half the trim's width
	var band := outer - (trim + half)                # the gold OUTSIDE the trim

	# the cap's own thickness: the same annulus stamped down into the seat, which is
	# what makes the surface read as standing proud rather than painted on
	var steps := 9
	for i in range(steps, 0, -1):
		var f := float(i) / float(steps)
		c.draw_arc(Vector2(0.0, _o_raise * f), (outer + inner) * 0.5, 0.0, TAU, HW_SEGS,
			Color(0.20, 0.10, 0.01).lerp(Color(0.60, 0.38, 0.07), 1.0 - f), outer - inner, true)

	# the gold surface: crown high in the middle of the band, both edges rolled away
	var mid := (outer + trim + half) * 0.5
	_gold_band(c, Vector2.ZERO, mid, band, lit)
	# ...and the narrow shoulder that steps down from the trim groove into the bore
	_ring_band(c, r, inner / r, (trim - half) / r, lit, 0.40, 0.06, LUX_BASE)

	# specular streak where the key light grazes the crown, warm rim light opposite
	c.draw_arc(Vector2.ZERO, mid + band * 0.10, deg_to_rad(-158.0), deg_to_rad(-106.0),
		14, Color(1.0, 0.99, 0.92, 0.75), band * 0.34, true)
	c.draw_arc(Vector2.ZERO, mid - band * 0.26, deg_to_rad(22.0), deg_to_rad(66.0),
		12, Color(1.0, 0.86, 0.56, 0.38), band * 0.22, true)

	# the cap's outer edge: a bright rolled bevel on the lit side over a dark
	# silhouette, so the surface has a visible EDGE standing above the seat
	c.draw_arc(Vector2.ZERO, outer, 0.0, TAU, HW_SEGS, Color(0.20, 0.10, 0.01, 0.80), 2.2, true)
	c.draw_arc(Vector2.ZERO, outer - 1.4, deg_to_rad(-178.0), deg_to_rad(-88.0), 20,
		Color(1.00, 0.92, 0.62, 0.60), 2.0, true)

	# the bore, seen down the middle of the cap: a short dark wall so the counter is a
	# hole through a solid object, not a disc of background
	for i in 7:
		var f := float(i) / 6.0
		c.draw_circle(Vector2(0.0, _o_raise * 1.0 * f), inner * (1.0 - f * 0.05),
			Color(0.18, 0.09, 0.01).lerp(Color(0.03, 0.015, 0.04), f))
	c.draw_arc(Vector2.ZERO, inner, 0.0, TAU, HW_SEGS, Color(0.12, 0.06, 0.01, 0.80), 1.6, true)

	# one four-point glint on the lit shoulder — the "deluxe" cue
	var sa := deg_to_rad(-134.0)
	_sparkle(c, Vector2(cos(sa), sin(sa)) * (mid + band * 0.14), r * 0.30)

# The white trim: a lit tube seated in a groove milled around the counter. Opaque,
# because the point of it is that it is WHITE against gold — and built as groove ->
# tube -> hot core -> grazing highlight, so it has a body instead of an outline.
func _draw_o_trim(c: Node2D, r: float) -> void:
	var trim := r * O_TRIM
	var w := r * O_TRIM_W
	# the groove the tube lies in: a dark ring on the gold, which is what stops the
	# white from reading as a stroke laid on top of the metal
	c.draw_arc(Vector2.ZERO, trim, 0.0, TAU, HW_SEGS, Color(0.18, 0.09, 0.01, 0.90), w * 1.42, true)
	# the tube: a full-width body in near-white, then a hot core down its middle. It
	# is drawn at the full authored width (0.115 of the radius, ~5px at logo size)
	# because a hairline here does not read as the letter O — it reads as a scratch.
	c.draw_arc(Vector2.ZERO, trim, 0.0, TAU, HW_SEGS, Color(0.88, 0.91, 1.00, 1.0), w, true)
	c.draw_arc(Vector2.ZERO, trim, 0.0, TAU, HW_SEGS, Color(1, 1, 1, 1.0), w * 0.52, true)
	# the tube is round: a bright graze on its lit side, a cooler one opposite
	c.draw_arc(Vector2.ZERO, trim - w * 0.24, deg_to_rad(-172.0), deg_to_rad(-96.0), 18,
		Color(1, 1, 1, 0.95), w * 0.42, true)
	c.draw_arc(Vector2.ZERO, trim + w * 0.30, deg_to_rad(22.0), deg_to_rad(80.0), 14,
		Color(0.74, 0.79, 0.94, 0.60), w * 0.30, true)
	# the two shadow lines where the tube meets the walls of its groove
	c.draw_arc(Vector2.ZERO, trim + w * 0.60, 0.0, TAU, HW_SEGS, Color(0.16, 0.08, 0.01, 0.55), w * 0.20, true)
	c.draw_arc(Vector2.ZERO, trim - w * 0.60, 0.0, TAU, HW_SEGS, Color(0.16, 0.08, 0.01, 0.55), w * 0.20, true)

# The light the trim throws onto the gold either side of it. Additive and tight — a
# lit part glows a little onto its own housing, it does not floodlight the button.
func _draw_o_bloom(c: Node2D, r: float) -> void:
	var trim := r * O_TRIM
	var w := r * O_TRIM_W
	for i in 3:
		var f := float(i) / 2.0
		c.draw_arc(Vector2.ZERO, trim, 0.0, TAU, HW_SEGS,
			Color(0.86, 0.90, 1.00, 0.13 - f * 0.035), w * (1.5 + f * 1.3), true)

# One flat-shaded band of the hardware profile: the annulus from `r0` to `r1` (both
# fractions of the bezel radius `r`), shaded around the ring by the key light and
# across the band by a linear crown ramp from `c0` at the outer edge to `c1` at the
# inner one. Quads share their edge vertices exactly, so neighbouring bands meet
# without a seam.
func _ring_band(c: CanvasItem, r: float, r0: float, r1: float, lit: Vector2,
		c0: float, c1: float, base: Color) -> void:
	for i in HW_SEGS:
		var a0 := TAU * float(i) / float(HW_SEGS)
		var a1 := TAU * float(i + 1) / float(HW_SEGS)
		var d0 := Vector2(cos(a0), sin(a0))
		var d1 := Vector2(cos(a1), sin(a1))
		var l0 := d0.dot(lit)
		var l1 := d1.dot(lit)
		c.draw_polygon(
			PackedVector2Array([d0 * (r * r1), d1 * (r * r1), d1 * (r * r0), d0 * (r * r0)]),
			PackedColorArray([_metal(l0, c0, base), _metal(l1, c0, base),
				_metal(l1, c1, base), _metal(l0, c1, base)]))

# The metal at one point on a band, for any base tone. `lam` is how squarely it faces
# the key light (-1..1), `crown` how proud of the bevel it sits (0 at a rolled edge,
# 1 at the crown). Shares its shaping with _lux, which is the gold-only special case.
func _metal(lam: float, crown: float, base: Color) -> Color:
	var dark := base.darkened(0.72)
	var col := dark.lerp(base, 0.30 + 0.70 * (lam * 0.5 + 0.5))
	col = col.lerp(base.lightened(0.62), pow(maxf(lam, 0.0), 2.0) * crown)
	return col.lerp(dark, (1.0 - crown) * 0.40)

# ---------------- the O's idle + press ----------------

# Idle: nothing but a slow swell in the halo it sits in. No rotation, no bob — the
# object is a machined part, and machined parts hold still.
func _o_breathe() -> void:
	if _o_glow == null:
		return
	var br := create_tween().set_loops()
	br.tween_property(_o_glow, "modulate:a", 0.34, 2.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	br.tween_property(_o_glow, "modulate:a", 0.18, 2.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

# Press: the gold surface sinks into its collar, the trim brightens with it and the
# gold's own light briefly swells. The body does not move.
func _on_o_press() -> void:
	if _o_cap == null:
		return
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_o_cap, "position:y", _o_cap.position.y + _o_raise * 0.72, 0.07) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_o_bloom, "modulate", Color(2.3, 2.2, 2.05, 1.0), 0.07)
	tw.tween_property(_o_trim, "modulate", Color(1.22, 1.22, 1.26, 1.0), 0.07)
	tw.tween_property(_o_aura, "modulate", Color(1.62, 1.46, 1.26, 1.0), 0.07)

func _on_o_release() -> void:
	if _o_cap == null:
		return
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_o_cap, "position:y", _o_cap_rest, 0.24) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_o_bloom, "modulate", Color.WHITE, 0.30)
	tw.tween_property(_o_trim, "modulate", Color.WHITE, 0.30)
	tw.tween_property(_o_aura, "modulate", Color.WHITE, 0.34)

# One band of the logo gold, shaded in two directions at once: around the ring by
# where the key light falls, and across the band by a rounded bevel profile (both
# edges roll away, the crown catches the light).
#
# It is built as a quad strip with per-vertex colours rather than a stack of
# draw_arc() calls: neighbouring quads share their edge vertices and colours exactly,
# so the metal comes out smooth. Painting it as separate arc segments leaves a seam
# at every joint and the ring reads as a milled gear instead of a solid.
const LUX_SEGS := 64
const LUX_PROFILE := [-0.50, -0.18, 0.16, 0.50]     # band-relative radii of the rings
const LUX_CROWN := [0.30, 1.00, 0.90, 0.26]         # how much light each ring takes

func _gold_band(c: CanvasItem, ctr: Vector2, radius: float, thick: float, lit: Vector2) -> void:
	for i in LUX_SEGS:
		var a0 := TAU * float(i) / float(LUX_SEGS)
		var a1 := TAU * float(i + 1) / float(LUX_SEGS)
		var d0 := Vector2(cos(a0), sin(a0))
		var d1 := Vector2(cos(a1), sin(a1))
		var l0 := d0.dot(lit)                        # -1 far side .. 1 facing the light
		var l1 := d1.dot(lit)
		for k in LUX_PROFILE.size() - 1:
			var ra: float = radius + thick * LUX_PROFILE[k]
			var rb: float = radius + thick * LUX_PROFILE[k + 1]
			var wa: float = LUX_CROWN[k]
			var wb: float = LUX_CROWN[k + 1]
			c.draw_polygon(
				PackedVector2Array([ctr + d0 * ra, ctr + d1 * ra, ctr + d1 * rb, ctr + d0 * rb]),
				PackedColorArray([_lux(l0, wa), _lux(l1, wa), _lux(l1, wb), _lux(l0, wb)]))

# The gold at one point on a band. `lam` is how squarely that point faces the key
# light (-1..1); `crown` is how proud of the bevel it sits (0 at a rolled edge, 1 at
# the crown). The far side never goes flat-dark — it picks up a warm bounce, which is
# the difference between gold and brown.
func _lux(lam: float, crown: float) -> Color:
	var col := LUX_DEEP.lerp(LUX_BASE, 0.34 + 0.66 * (lam * 0.5 + 0.5))
	col = col.lerp(LUX_HI, pow(maxf(lam, 0.0), 2.0) * crown)
	col = col.lerp(LUX_RIM, pow(maxf(-lam, 0.0), 3.0) * 0.55)
	return col.lerp(LUX_DEEP, (1.0 - crown) * 0.42)

# A four-point star glint: two tapered spikes crossed, plus a hot core.
func _sparkle(c: CanvasItem, ctr: Vector2, size: float) -> void:
	var w := size * 0.16
	for rot in [0.0, PI * 0.5]:
		var dir := Vector2(cos(rot), sin(rot))
		var nrm := Vector2(-dir.y, dir.x)
		var long: float = size * (0.5 if rot == 0.0 else 0.34)
		c.draw_colored_polygon(PackedVector2Array([
			ctr - dir * long, ctr + nrm * w, ctr + dir * long, ctr - nrm * w]),
			Color(1, 1, 1, 0.85))
	c.draw_circle(ctr, w * 1.15, Color(1, 1, 1, 0.95))

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
	art.draw.connect(_draw_arena_colosseum.bind(art))
	panel.add_child(art)

	# The pad's six buttons light one at a time. Each one's light is its own additive
	# node rather than a repaint of the pad, and they share the art's canvas transform
	# so they land exactly on the buttons underneath. Added before the knights, so the
	# fencers stay in front of the light rather than behind it.
	var addm := CanvasItemMaterial.new()
	addm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var lights := Node2D.new()
	lights.position = art.position + _KN_TF_POS
	lights.scale = _KN_TF_SCL
	panel.add_child(lights)
	_pad_lights.clear()
	for i in PAD_COLS.size():
		var lit := Node2D.new()
		lit.material = addm
		lit.modulate = Color(1, 1, 1, 0)
		lit.draw.connect(_draw_arena_btn_light.bind(lit, i))
		lights.add_child(lit)
		_pad_lights.append(lit)

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
	btn.button_down.connect(_on_card_press.bind(wrap, true))
	btn.button_up.connect(_on_card_press.bind(wrap, false))
	btn.pressed.connect(_on_arena)
	floater.add_child(btn)

	_arena_card = {"wrap": wrap, "art": art, "floater": floater, "knights": knights}
	_duel_rng.randomize()

# The Arena mascot: a medieval colosseum. Massive tiered stone grandstands ring a
# central arena floor carrying the BUTTON PAD (see _draw_arena_pad), where two
# armoured knights duel with swords. Torches, banners, a wooden railing and a dark,
# warm-lit mood set the epic medieval scene. Fully static. `c` is a ~214 x 124 box.
func _draw_arena_colosseum(c: Control) -> void:
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

	# --- what the two knights are actually fighting over: the BUTTON PAD ---
	_draw_arena_pad(c)

	# The two duelling knights are drawn on a separate animated overlay
	# (_draw_arena_knights), so nothing below the pad needs to redraw per frame; the
	# pad's own idle light is a set of additive nodes above it (_draw_arena_btn_light).

# ---------------- the Arena's button pad ----------------
#
# What stands on the arena floor is a miniature LUMEO board: six INDIVIDUAL physical
# buttons standing on a dark hexagonal deck. It replaced a four-colour Simon wheel,
# and the whole point of the swap is that nothing here is a slice of a disc — every
# button is its own object, with its own bezel, its own seat and its own shadow, and
# the deck underneath is neutral dark metal so the colour only ever lives in the caps.
#
# Everything is authored in the same ~214x124 space as the colosseum around it and
# drawn once into the static art layer. The idle "one button lights up" pulse lives in
# separate additive nodes on top (_draw_arena_btn_light), so the pad never repaints.
const PAD_CTR := Vector2(107.0, 74.0)         # authored-space centre of the arena floor
const PAD_RX := 43.0                          # deck radius, across the flats-to-points
const PAD_RY := 20.5                          # ...squashed by the floor's own perspective
const PAD_LIFT := 5.0                         # how tall the deck stands off the sand
const PAD_RING := Vector2(29.0, 13.8)         # the ring the six buttons stand on
const PAD_BTN := Vector2(9.0, 4.3)            # one button's frame, in the same perspective
const PAD_BTN_H := 4.4                        # how tall a button stands off the deck

# The six caps, in ring order from the top. Cyan / magenta / amber / blue / jade /
# violet: the game's own palette, ordered so no two neighbours are the same family.
const PAD_COLS := [
	Color(0.22, 0.86, 0.96),   # cyan
	Color(0.96, 0.30, 0.72),   # magenta
	Color(1.00, 0.72, 0.20),   # amber
	Color(0.28, 0.48, 0.99),   # deep blue
	Color(0.16, 0.84, 0.56),   # jade
	Color(0.60, 0.42, 1.00),   # violet
]
# The order the idle pulse walks them in. Deliberately NOT 0,1,2,3,4,5: a ring lighting
# in sequence reads as a spinner, and this has to read as a remembered pattern.
const PAD_SEQ := [0, 3, 1, 5, 2, 4]

# Where button `i` stands, in authored space. Index 0 is the far one at the top.
func _pad_btn_pos(i: int) -> Vector2:
	var a := -PI * 0.5 + TAU * float(i) / float(PAD_COLS.size())
	return PAD_CTR + Vector2(cos(a) * PAD_RING.x, sin(a) * PAD_RING.y)

# The deck's outline: a hexagon in the floor's perspective, rotated 30 degrees off the
# buttons so a corner sits between every neighbouring pair rather than behind one.
func _pad_hex(ctr: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var a := TAU * float(i) / 6.0
		pts.append(ctr + Vector2(cos(a) * rx, sin(a) * ry))
	return pts

func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array(pts)
	out.append(pts[0])
	return out

# The deck, then the six buttons standing on it, back to front.
func _draw_arena_pad(c: CanvasItem) -> void:
	var ctr := PAD_CTR

	# the shadow the whole deck drops onto the sand
	c.draw_colored_polygon(_ellipse_pts(ctr + Vector2(0.0, PAD_LIFT + 2.0),
		PAD_RX * 1.04, PAD_RY * 1.10, 28), Color(0.0, 0.0, 0.0, 0.34))

	# the deck's side wall: the hexagon stamped downward, dark at the foot and
	# climbing into gunmetal, so the deck reads as a slab with thickness
	for i in range(9, 0, -1):
		var f := float(i) / 9.0
		c.draw_colored_polygon(_pad_hex(ctr + Vector2(0.0, PAD_LIFT * f), PAD_RX, PAD_RY),
			Color(0.035, 0.035, 0.055).lerp(Color(0.15, 0.15, 0.21), 1.0 - f))

	# the deck's top face: dark brushed metal, lit a touch toward the middle. Built as
	# a fan of six triangles so the falloff is a real gradient rather than a flat wash.
	var rim := _pad_hex(ctr, PAD_RX, PAD_RY)
	var face_mid := Color(0.235, 0.235, 0.315)
	var face_edge := Color(0.115, 0.115, 0.165)
	for i in 6:
		c.draw_polygon(PackedVector2Array([ctr, rim[i], rim[(i + 1) % 6]]),
			PackedColorArray([face_mid, face_edge, face_edge]))

	# restrained machining: six shallow radial grooves running out to the corners,
	# each a dark cut with a lit lip on its upper side
	for i in 6:
		var a := TAU * float(i) / 6.0
		var d := Vector2(cos(a) * PAD_RX, sin(a) * PAD_RY)
		c.draw_line(ctr + d * 0.34, ctr + d * 0.94, Color(0.06, 0.06, 0.10, 0.85), 1.2)
		c.draw_line(ctr + d * 0.34 + Vector2(0.0, -0.7), ctr + d * 0.94 + Vector2(0.0, -0.7),
			Color(0.42, 0.44, 0.56, 0.30), 0.6)

	# the illuminated edge: one thin cool filament following the deck's top rim, with a
	# fainter, wider copy under it standing in for its bloom
	c.draw_polyline(_closed(rim), Color(0.30, 0.86, 1.00, 0.16), 3.0, true)
	c.draw_polyline(_closed(rim), Color(0.62, 0.94, 1.00, 0.70), 1.1, true)
	# ...and six tiny service lights, one at each corner
	for p in rim:
		c.draw_circle(p, 1.5, Color(0.40, 0.88, 1.00, 0.22))
		c.draw_circle(p, 0.7, Color(0.86, 0.98, 1.00, 0.85))

	# the centre medallion: a small sunk disc with a lit rim. It is the only thing in
	# the middle of the deck, which is what keeps the six buttons the subject.
	c.draw_colored_polygon(_ellipse_pts(ctr, 5.4, 2.6, 20), Color(0.07, 0.07, 0.11))
	c.draw_polyline(_closed(_ellipse_pts(ctr, 5.4, 2.6, 20)), Color(0.52, 0.60, 0.78, 0.55), 0.8, true)
	c.draw_circle(ctr + Vector2(0.0, -0.3), 1.1, Color(0.72, 0.86, 1.00, 0.50))

	# the buttons, painted back to front so the near ones overlap the far ones
	var order := [0, 1, 5, 2, 4, 3]
	for i in order:
		_draw_arena_button(c, _pad_btn_pos(i), PAD_COLS[i])

# One physical button on the deck: contact shadow, a metal frame with a visible side
# wall, the dark seat milled into it, and a raised coloured cap sitting in the seat.
# The same four parts, in the same order, as the buttons the game is actually played
# on — just small enough to fit on a card.
func _draw_arena_button(c: CanvasItem, p: Vector2, col: Color) -> void:
	var rx := PAD_BTN.x
	var ry := PAD_BTN.y

	# the shadow it drops on the deck, offset with the scene's key light
	c.draw_colored_polygon(_ellipse_pts(p + Vector2(1.1, PAD_BTN_H * 0.55), rx * 1.10, ry * 1.10, 22),
		Color(0.0, 0.0, 0.0, 0.40))

	# the frame's side wall, stamped down onto the deck
	for i in range(6, 0, -1):
		var f := float(i) / 6.0
		c.draw_colored_polygon(_ellipse_pts(p + Vector2(0.0, PAD_BTN_H * f), rx, ry, 22),
			Color(0.045, 0.045, 0.065).lerp(Color(0.22, 0.22, 0.30), 1.0 - f))

	# the frame's top face + its polished lip
	c.draw_colored_polygon(_ellipse_pts(p, rx, ry, 22), Color(0.30, 0.30, 0.39))
	c.draw_polyline(_closed(_ellipse_pts(p, rx, ry, 22)), Color(0.62, 0.65, 0.80, 0.85), 0.9, true)
	c.draw_polyline(_ellipse_pts(p, rx * 0.99, ry * 0.99, 22).slice(11, 20),
		Color(0.88, 0.92, 1.00, 0.55), 0.7, true)

	# the seat: the dark gap the cap is sunk into. Thin, but it is the whole reason the
	# cap reads as a separate part rather than as a coloured spot painted on the frame.
	c.draw_colored_polygon(_ellipse_pts(p, rx * 0.76, ry * 0.76, 22), Color(0.05, 0.05, 0.075))

	# the cap: raised out of the seat, with its own wall of thickness under it
	var lift := 1.7
	var crx := rx * 0.66
	var cry := ry * 0.66
	for i in range(4, 0, -1):
		var f := float(i) / 4.0
		c.draw_colored_polygon(_ellipse_pts(p + Vector2(0.0, lift * f), crx, cry, 22),
			col.darkened(0.74).lerp(col.darkened(0.46), 1.0 - f))

	# the cap's face: a vertical ramp from a lit crown to a deep shoulder
	var top := p - Vector2(0.0, lift)
	var face := _ellipse_pts(top, crx, cry, 22)
	var fcol := PackedColorArray()
	for pt in face:
		var t: float = clampf((pt.y - (top.y - cry)) / maxf(2.0 * cry, 0.001), 0.0, 1.0)
		fcol.append(col.lightened(0.34).lerp(col.darkened(0.42), smoothstep(0.0, 1.0, t)))
	c.draw_polygon(face, fcol)
	# the gloss on its crown, and a faint bounce of its own colour on the far shoulder
	c.draw_colored_polygon(_ellipse_pts(top + Vector2(-0.4, -cry * 0.36), crx * 0.56, cry * 0.42, 16),
		Color(1, 1, 1, 0.30))
	c.draw_polyline(_closed(_ellipse_pts(top, crx, cry, 22)), col.lightened(0.55).lerp(Color(0, 0, 0, 1), 0.15), 0.6, true)

# The light one button throws when the pad's idle pulse reaches it. Drawn additively in
# the cap's own colour and animated with `modulate:a` alone — the pad itself is static
# art and never repaints for this.
func _draw_arena_btn_light(c: CanvasItem, i: int) -> void:
	var p := _pad_btn_pos(i)
	var col: Color = PAD_COLS[i]
	var crx := PAD_BTN.x * 0.66
	var cry := PAD_BTN.y * 0.66
	var top := p - Vector2(0.0, 1.7)
	# the halo standing in the air over the button
	for k in 5:
		var f := float(k) / 4.0
		c.draw_colored_polygon(_ellipse_pts(top, crx * (1.5 + f * 2.4), cry * (1.5 + f * 2.4), 20),
			Color(col.r, col.g, col.b, 0.10 - f * 0.018))
	# the cap itself running hot, and a white-hot core on its crown
	c.draw_colored_polygon(_ellipse_pts(top, crx, cry, 22), Color(col.r, col.g, col.b, 0.85))
	c.draw_colored_polygon(_ellipse_pts(top + Vector2(0.0, -cry * 0.22), crx * 0.62, cry * 0.55, 16),
		Color(1, 1, 1, 0.45))
	# a spill of the same colour onto the deck the button stands on
	c.draw_colored_polygon(_ellipse_pts(p + Vector2(0.0, PAD_BTN_H * 0.5), PAD_BTN.x * 1.7, PAD_BTN.y * 1.7, 22),
		Color(col.r, col.g, col.b, 0.10))

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

func _on_card_press(wrap: Control, down: bool) -> void:
	var tw := create_tween()
	tw.tween_property(wrap, "scale", Vector2.ONE * (0.97 if down else 1.0), 0.10) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

# ---------------- START orb ----------------

const START_SIZE := Vector2(300.0, 300.0)

# Where the button sits inside its 300x300 art box, and how big it is. Kept high in
# the box so the barrel and its contact shadow clear the START label underneath.
const PLAY_CTR := Vector2(150.0, 138.0)
const PLAY_RAD := 113.0                              # bezel outer radius
# The button was authored at radius 96 and is now the menu's hero, ~18% wider. Every
# radius in the drawing is a fraction of PLAY_RAD and scales for free; the handful of
# values that are honest PIXELS (barrel depth, cap lift, the arrow, hairline widths)
# are multiplied by this instead, so the assembly grows as one object rather than a
# big ring with a small arrow rattling around inside it.
const PLAY_K := PLAY_RAD / 96.0
# Top of the START label's box, inside the same 300x300 art. The word is the button's
# caption, not a second element under it, so it is pinned to the hardware: the barrel
# and its contact shadow bottom out at PLAY_CTR.y + PLAY_RAD + depth * 1.4 ≈ 266, and
# the cap-height of a 36px "START" starts ~17px into a 48-tall centred box. 265 leaves
# roughly ten clean pixels between the two — close enough that the word reads as
# attached to the button, far enough that it never touches the shadow.
const START_LABEL_Y := 265.0

# The accent's colour wheel. ONE colour owns the ring at a time; a leg is a slow
# sweep of hue from the colour it holds to the next, so the ring never becomes a
# rainbow and never divides into segments — it just changes what it is lit with.
# Hues (degrees) in the order the game reads them:
#   RED -> YELLOW -> ORANGE -> BLUE -> PURPLE -> GREEN -> RED
const PLAY_HUE := [0.0, 55.0, 30.0, 220.0, 265.0, 140.0]
# The signed hue travel of each leg. Mostly the short way round, EXCEPT orange->blue,
# which is swept forward through green/cyan: the short way back would drag the ring
# through red and purple, i.e. through two colours the cycle is about to show anyway.
# They sum to exactly 0, which is what makes the loop seamless.
const PLAY_HUE_STEP := [55.0, -25.0, 190.0, 45.0, -125.0, -140.0]
const PLAY_CYCLE := 11.0                             # seconds for the whole wheel
const PLAY_BREATH := 3.2                             # seconds per idle glow swell

func _build_start() -> void:
	_start_lm = _landmark(START_SIZE, _draw_play_frame, _on_start)
	var art: Control = _start_lm["art"]

	# the coloured bloom the frame's light channel throws, then the hot trim lying in
	# the channel itself, then the violet cap on top. Both luminous layers are drawn
	# in white and additively blended, so tinting them is a modulate away — the colour
	# cycle never repaints anything.
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	_play_glow = Node2D.new()
	_play_glow.material = add
	_play_glow.draw.connect(_draw_play_glow.bind(_play_glow))
	art.add_child(_play_glow)

	_play_accent = Node2D.new()
	_play_accent.material = add
	_play_accent.draw.connect(_draw_play_accent.bind(_play_accent))
	art.add_child(_play_accent)

	_play_cap = Node2D.new()
	_play_cap_rest = 0.0
	_play_cap.draw.connect(_draw_play_cap.bind(_play_cap))
	art.add_child(_play_cap)

	_lm_label(_start_lm, "START", 36, Color.WHITE, ICON_BLUE.lightened(0.25),
		Vector2(0, START_LABEL_Y), Vector2(START_SIZE.x, 48))

# The colour the accent is lit with `t` legs into the wheel (t in 0..6, wrapping).
# smoothstep() across each leg makes the ring settle on every colour before easing
# into the next, so it reads as "red ... blending ... yellow" rather than as a
# constant-speed hue spin.
func _play_accent_color(t: float) -> Color:
	var leg := int(floor(t)) % PLAY_HUE.size()
	var e: float = smoothstep(0.0, 1.0, t - floor(t))
	var h: float = PLAY_HUE[leg] + PLAY_HUE_STEP[leg] * e
	return Color.from_hsv(wrapf(h, 0.0, 360.0) / 360.0, 0.84, 1.0)

# Drives the accent every frame: its colour from the wheel, its brightness from a
# slow idle swell plus whatever the press is adding. Only modulate is touched, so
# this costs two colour multiplies a frame and no redraw.
func _play_accent_tick(t: float) -> void:
	var col := _play_accent_color(t)
	var breath: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * TAU / PLAY_BREATH)
	# The land runs hot, but only barely mixed toward white (0.12, not the old 0.34):
	# the accent is blended additively, so every point of white here is a point of
	# saturation lost, and at this size a washed ring reads as "some pale light"
	# rather than as RED, then YELLOW, then BLUE. The brightness that sells it comes
	# from the alpha the band is drawn with, not from bleaching the hue.
	var hot := col.lerp(Color.WHITE, 0.12) * (1.28 + 0.55 * _play_flash)
	hot.a = 1.0
	_play_accent.modulate = hot
	var k: float = (0.94 + 0.16 * breath) * (1.0 + 1.20 * _play_flash)
	_play_glow.modulate = Color(col.r * k, col.g * k, col.b * k, 1.0)

# Build one clickable landmark: a transparent Button (input) wrapping an `art`
# Control which holds the procedural `drawer` plus whatever extra layers the caller
# adds on top. The press is handled per-part rather than by scaling `art` (see
# _on_lm_press). Returns the pieces so callers can attach labels and the layout can
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

# ---------------- the START button ----------------
#
# The same machine as the logo's O, one size up and in dark metal: a barrel standing
# off its own contact shadow, milled to the HW_* profile (light channel, crown, slope,
# bore) and carrying a raised violet cap. It is drawn in four layers so the parts that
# animate are separate nodes from the parts that never do:
#
#   _draw_play_frame   the dark metal — barrel, channel groove, crown, slope, socket
#   _draw_play_glow    the coloured bloom the channel throws (additive, tinted)
#   _draw_play_accent  the hot trim lying in the channel (additive, tinted)
#   _draw_play_cap     the violet dome + arrow — the only piece that moves on a press
#
# Nothing here repaints: the colour wheel and the idle swell ride on modulate, the
# press on the cap's transform.

# The frame's own material. Near-black anodised metal, not gunmetal: it is only the
# supporting structure the light sits in, and every tone it carries competes with
# the colour the land is lit with. Dark enough that an additive colour laid over it
# comes out saturated instead of washed toward white.
const PLAY_METAL := Color(0.17, 0.17, 0.24)          # the frame's dark base tone
const PLAY_SEAT := Color(0.045, 0.042, 0.085)        # the seat — the darkest ring

func _draw_play_frame(c: Control) -> void:
	var ctr := PLAY_CTR
	var rad := PLAY_RAD
	var depth := 13.0 * PLAY_K                       # how tall the barrel stands
	var lit := LUX_LIGHT.normalized()

	# contact shadow on the ground it stands on
	c.draw_colored_polygon(
		_ellipse_pts(ctr + Vector2(0.0, depth + rad * 0.78), rad * 0.90, rad * 0.17),
		Color(0.02, 0.01, 0.08, 0.40))

	# The barrel: the bezel's footprint stamped downward. Shallower and darker than
	# it was — it is the frame's side wall, and its job is to say "this ring has
	# thickness", not to add another disc of grey to the silhouette.
	var steps := 14
	for i in range(steps, 0, -1):
		var f := float(i) / float(steps)
		c.draw_circle(ctr + Vector2(0.0, depth * f),
			rad, Color(0.025, 0.025, 0.05).lerp(Color(0.13, 0.13, 0.19), 1.0 - f))

	c.draw_set_transform(ctr, 0.0, Vector2.ONE)
	# The frame, in dark metal. The colour is NOT painted here — it is the additive
	# accent layer above, so the wheel can re-tint it without repainting anything.
	# outer chamfer, rolling up from the barrel to the land
	_ring_band(c, rad, HW_LIP, 1.00, lit, 0.24, 0.86, PLAY_METAL)
	# the land: the face the light lies on, kept flat and dark
	_ring_band(c, rad, HW_LAND, HW_LIP, lit, 0.86, 0.80, PLAY_METAL.darkened(0.30))
	# inner chamfer, rolling down off the land into the seat
	_ring_band(c, rad, HW_CHAMFER, HW_LAND, lit, 0.80, 0.10, PLAY_METAL.darkened(0.42))
	# the seat: the darkest ring on the object. This thin band is the whole
	# separation between the luminous frame and the violet cap.
	_ring_band(c, rad, HW_SEAT, HW_CHAMFER, lit, 0.14, 0.02, PLAY_SEAT)

	# the bore under the cap, and the shadow the cap casts down into its seat
	var bore := rad * HW_SEAT
	for i in 6:
		var f := float(i) / 5.0
		c.draw_circle(Vector2(0.0, -5.0 * PLAY_K * (1.0 - f)), bore * (1.0 - f * 0.03),
			Color(0.03, 0.03, 0.055).lerp(Color(0.09, 0.09, 0.14), f * 0.6))
	for i in 3:
		var f := float(i) / 2.0
		c.draw_arc(Vector2(0.0, 3.0 * PLAY_K), rad * (HW_SEAT + 0.006 + f * 0.016), 0.0, TAU, 72,
			Color(0.01, 0.01, 0.03, 0.34 - f * 0.10), rad * 0.030, true)

	# antialiased silhouettes over the flat-shaded quads
	c.draw_arc(Vector2.ZERO, rad, 0.0, TAU, 96, Color(0.03, 0.03, 0.06, 0.85), 2.4 * PLAY_K, true)
	c.draw_arc(Vector2.ZERO, bore, 0.0, TAU, 96, Color(0.02, 0.02, 0.04, 0.85), 2.0 * PLAY_K, true)
	# one cool graze on the outer chamfer's lit shoulder: the cue that the frame is
	# machined metal even where the colour has not reached it
	c.draw_arc(Vector2.ZERO, rad * 0.978, deg_to_rad(-166.0), deg_to_rad(-104.0), 18,
		Color(0.86, 0.90, 1.00, 0.30), rad * 0.032, true)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# The bloom the lit land throws into the air around the button and down into its own
# seat. Drawn white; the cycle tints it. It is what makes the colour visible from
# across the menu rather than only on the ring itself — but it stays a halo, never a
# floodlight, or the whole button washes out.
func _draw_play_glow(c: Node2D) -> void:
	var rad := PLAY_RAD
	c.draw_set_transform(PLAY_CTR, 0.0, Vector2.ONE)
	# outward, into the air
	for i in 6:
		var f := float(i) / 5.0
		c.draw_arc(Vector2.ZERO, rad * (0.99 + f * 0.075), 0.0, TAU, 72,
			Color(1, 1, 1, 0.105 - f * 0.017), rad * (0.045 + f * 0.055), true)
	# inward: a spill across the inner chamfer and into the seat, so the seat reads as
	# a shadowed groove lit from its outer wall rather than as a painted black ring
	for i in 3:
		var f := float(i) / 2.0
		c.draw_arc(Vector2.ZERO, rad * (0.828 - f * 0.030), 0.0, TAU, 72,
			Color(1, 1, 1, 0.115 - f * 0.035), rad * (0.026 + f * 0.024), true)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# The colour itself: the frame's whole LAND lit from within, plus a thin hot edge
# running along its outer lip. This is the primary accent on the screen and the only
# part of the button that ever changes colour.
#
# Everything here is drawn in WHITE with per-vertex ALPHA and blended ADDITIVELY over
# the dark frame, so `modulate` alone re-lights it: the pixel ends up
# `dark_metal + colour * alpha`, which stays a saturated colour instead of drifting
# toward white the way a colour mixed toward white would. That is also why the land
# is never taken to full alpha — a fully lit land at every hue would clip to white on
# yellow and cyan and the colour would be gone at exactly the brightest moment.
#
# The band is shaded twice: across it by a bevel profile (both edges roll away, the
# outer shoulder is proudest), and around it by the key light — but only gently, so
# ONE colour still owns the whole ring rather than the ring reading as a gradient.
const PLAY_LAND_PROFILE := [0.845, 0.876, 0.918, 0.952, 0.985]
const PLAY_LAND_ALPHA := [0.16, 0.62, 0.86, 0.74, 0.20]

func _draw_play_accent(c: Node2D) -> void:
	var rad := PLAY_RAD
	var lit := LUX_LIGHT.normalized()
	c.draw_set_transform(PLAY_CTR, 0.0, Vector2.ONE)

	for i in HW_SEGS:
		var a0 := TAU * float(i) / float(HW_SEGS)
		var a1 := TAU * float(i + 1) / float(HW_SEGS)
		var d0 := Vector2(cos(a0), sin(a0))
		var d1 := Vector2(cos(a1), sin(a1))
		# 0.80 .. 1.00 of the authored alpha: the far side of the ring is still
		# unmistakably lit, it just isn't the side the key light is on.
		var k0: float = 0.80 + 0.20 * (d0.dot(lit) * 0.5 + 0.5)
		var k1: float = 0.80 + 0.20 * (d1.dot(lit) * 0.5 + 0.5)
		for j in PLAY_LAND_PROFILE.size() - 1:
			var ra: float = rad * PLAY_LAND_PROFILE[j]
			var rb: float = rad * PLAY_LAND_PROFILE[j + 1]
			var aa: float = PLAY_LAND_ALPHA[j]
			var ab: float = PLAY_LAND_ALPHA[j + 1]
			c.draw_polygon(
				PackedVector2Array([d0 * ra, d1 * ra, d1 * rb, d0 * rb]),
				PackedColorArray([Color(1, 1, 1, aa * k0), Color(1, 1, 1, aa * k1),
					Color(1, 1, 1, ab * k1), Color(1, 1, 1, ab * k0)]))

	# the thin luminous edge: a hot filament along the land's outer shoulder, which is
	# what gives the frame a defined lit EDGE instead of a soft coloured wash
	c.draw_arc(Vector2.ZERO, rad * 0.941, 0.0, TAU, 96, Color(1, 1, 1, 0.42), rad * 0.020, true)
	# ...and a second, finer one on the inner lip, so the frame is bounded on both
	# sides and reads as a bezel seated around the cap
	c.draw_arc(Vector2.ZERO, rad * 0.859, 0.0, TAU, 96, Color(1, 1, 1, 0.26), rad * 0.012, true)
	# the land is a rolled surface, not a flat washer: a specular sweep where the key
	# light grazes it
	c.draw_arc(Vector2.ZERO, rad * 0.918, deg_to_rad(-168.0), deg_to_rad(-98.0), 22,
		Color(1, 1, 1, 0.30), rad * 0.056, true)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# The cap: a raised, glossy dome in LUMEO's own violet, carrying the play arrow. It
# keeps its colour through the whole wheel — the cycle happens outside it.
const PLAY_CAP_TOP := Color(0.62, 0.50, 1.00)        # lit crown of the dome
const PLAY_CAP_BOT := Color(0.14, 0.09, 0.44)        # deep indigo where it rolls away

func _draw_play_cap(c: Node2D) -> void:
	var ctr := PLAY_CTR
	var cap_r := PLAY_RAD * HW_SEAT - 2.5 * PLAY_K
	var raise := 7.0 * PLAY_K                        # how far it stands out of the bore

	c.draw_set_transform(ctr + Vector2(0.0, -raise), 0.0, Vector2.ONE)
	# the cap's own wall of thickness, stamped down into the socket
	for i in range(6, 0, -1):
		var f := float(i) / 6.0
		c.draw_circle(Vector2(0.0, raise * f + 2.0 * PLAY_K), cap_r,
			Color(0.05, 0.04, 0.13).lerp(Color(0.19, 0.13, 0.44), 1.0 - f))

	# the dome: a vertical ramp from a lit violet crown to deep indigo
	var body := PackedVector2Array()
	var bcol := PackedColorArray()
	var n := 64
	for i in n:
		var a := TAU * float(i) / float(n)
		var p := Vector2(cos(a), sin(a)) * cap_r
		body.append(p)
		var t: float = clampf((p.y + cap_r) / (2.0 * cap_r), 0.0, 1.0)
		bcol.append(PLAY_CAP_TOP.lerp(PLAY_CAP_BOT, smoothstep(0.0, 1.0, t)))
	c.draw_polygon(body, bcol)

	# the dome's edge rolls away from the light: a dark inner ring reads as curvature,
	# and a faint violet emission ring keeps the cap from going dead at the rim
	c.draw_arc(Vector2.ZERO, cap_r - 3.5 * PLAY_K, 0.0, TAU, 64, Color(0.04, 0.02, 0.16, 0.26), 6.0 * PLAY_K, true)
	c.draw_arc(Vector2.ZERO, cap_r - 1.6 * PLAY_K, 0.0, TAU, 64, Color(0.58, 0.46, 1.00, 0.34), 2.4 * PLAY_K, true)

	# gloss: one broad sheen across the top of the dome, one tight hot spot in it
	c.draw_colored_polygon(
		_ellipse_pts(Vector2(-4.0 * PLAY_K, -cap_r * 0.44), cap_r * 0.74, cap_r * 0.34),
		Color(1, 1, 1, 0.16))
	c.draw_circle(Vector2(-cap_r * 0.36, -cap_r * 0.44), cap_r * 0.19, Color(1, 1, 1, 0.22))

	_draw_play_arrow(c, Vector2(10.0 * PLAY_K, 0.0))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# The play symbol: a rounded triangle built as a piece of lit acrylic set into the cap
# — a cast shadow under it, a violet bounce beneath its lower edge, the white body,
# and a brighter wedge along its lit side. Not a glyph; it has thickness.
func _draw_play_arrow(c: CanvasItem, at: Vector2) -> void:
	var k := PLAY_K
	var tri := PackedVector2Array([
		at + Vector2(-29.0, -40.0) * k, at + Vector2(-29.0, 40.0) * k, at + Vector2(41.0, 0.0) * k])
	# the soft light the acrylic throws onto the dome around it: three swelling
	# copies of the silhouette, each fainter, so the arrow sits IN the cap's light
	# instead of being pasted onto it
	for i in 3:
		var f := float(i) / 2.0
		var halo := PackedVector2Array()
		for pt in tri:
			halo.append(at + (pt - at) * (1.30 - f * 0.11))
		_rounded_tri(c, halo, 9.0 * k, Color(0.86, 0.84, 1.00, 0.05 + f * 0.035))
	var drop := PackedVector2Array()
	for pt in tri:
		drop.append(pt + Vector2(0.0, 4.0) * k)
	_rounded_tri(c, drop, 7.0 * k, Color(0.03, 0.02, 0.16, 0.34))
	var lift := PackedVector2Array()
	for pt in tri:
		lift.append(pt + Vector2(-1.0, -2.0) * k)
	_rounded_tri(c, lift, 7.0 * k, Color(0.72, 0.66, 1.00, 0.55))    # violet bounce off the cap
	_rounded_tri(c, tri, 7.0 * k, Color(1, 1, 1, 0.99))
	# The bevel on the lit edge, pulled in so it sits inside the silhouette. It is the
	# ONLY shading on the body: a second, darker wedge on the turned side was tried
	# and it read as dirt on a white arrow rather than as a chamfer — at this size the
	# depth has to come from the drop shadow, the violet bounce and this one highlight.
	var bev := PackedVector2Array([
		at + Vector2(-21.0, -25.0) * k, at + Vector2(-21.0, 6.0) * k, at + Vector2(17.0, -9.0) * k])
	_rounded_tri(c, bev, 5.0 * k, Color(1, 1, 1, 1.0))

# A triangle with rounded corners. Godot's polyline has no round joints, so it is
# built as the inset triangle plus a round-capped stroke of width 2r along its edges:
# each corner is pulled in along its own bisector by r/sin(half-angle), which is the
# exact offset that lands the arc tangent to both edges. Dropping circles on the
# original corners instead leaves three visible blobs on the acute tip.
func _rounded_tri(c: CanvasItem, pts: PackedVector2Array, r: float, col: Color) -> void:
	var inset := PackedVector2Array()
	for i in 3:
		var p := pts[i]
		var a := (pts[(i + 2) % 3] - p).normalized()
		var b := (pts[(i + 1) % 3] - p).normalized()
		var bis := (a + b).normalized()
		var half := acos(clampf(a.dot(bis), -1.0, 1.0))
		inset.append(p + bis * (r / maxf(sin(half), 0.20)))
	c.draw_colored_polygon(inset, col)
	for i in 3:
		c.draw_line(inset[i], inset[(i + 1) % 3], col, r * 2.0)
	for pt in inset:
		c.draw_circle(pt, r, col)

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

	# Handles go down first, with their roots buried inside the bowl's silhouette;
	# the cup is then painted over them, so each ear emerges from behind the metal
	# instead of butting against it.
	_draw_handle(c, bc.x, cup_top, bh, rw, bw, -1.0, g_edge, g_md, g_hi)
	_draw_handle(c, bc.x, cup_top, bh, rw, bw, 1.0, g_edge, g_md.darkened(0.12), g_lt)

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

# A cast gold handle shaped like an ear: it grows out of the bowl just under the
# rim, sweeps outward and around, then merges back into the bowl about two-thirds
# of the way down. Both roots are read off the exact same taper the bowl uses (same
# rw/bw/exponent) and pushed a few px *into* the metal, and the tube is built as a
# variable-width polygon — fat where it meets the cup, slim around the outer arc —
# so the ends read as welded on rather than as a wire laid beside the trophy.
func _draw_handle(c: Control, cx: float, cup_top: float, bh: float,
		rw: float, bw: float, side: float, dk: Color, md: Color, lt: Color) -> void:
	var top_t := 0.06   # upper root: right under the rim
	var bot_t := 0.66   # lower root: still on a reasonably wide part of the bowl
	# Roots sit ~9px inside the bowl wall so the cup, drawn afterwards, hides them.
	var top_w := bw + (rw - bw) * pow(1.0 - top_t, 0.72) - 9.0
	var bot_w := bw + (rw - bw) * pow(1.0 - bot_t, 0.72) - 9.0
	var p0 := Vector2(cx + side * top_w, cup_top + bh * top_t)
	var p3 := Vector2(cx + side * bot_w, cup_top + bh * bot_t)
	# Control points: leave the bowl heading out and slightly up, return into the
	# lower root from outside and below, so the silhouette is a teardrop ear.
	var p1 := p0 + Vector2(side * 36.0, -8.0)
	var p2 := p3 + Vector2(side * 40.0, 10.0)

	var n := 26
	var mid := PackedVector2Array()
	for i in n + 1:
		mid.append(_bezier3(p0, p1, p2, p3, float(i) / float(n)))

	# Sweep the tube: offset the spine by a half-width that swells at both roots.
	# Each normal is flipped to agree with the previous one, so the two rails never
	# swap sides and pinch the polygon into a notch part-way round the arc.
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var norms := PackedVector2Array()
	var prev := Vector2.ZERO
	for i in mid.size():
		var s := float(i) / float(n)
		var hw := 3.0 + 2.6 * (1.0 - sin(s * PI))
		var tang: Vector2 = (mid[mini(i + 1, n)] - mid[maxi(i - 1, 0)]).normalized()
		var nor := Vector2(-tang.y, tang.x)
		if i > 0 and nor.dot(prev) < 0.0:
			nor = -nor
		prev = nor
		norms.append(nor)
		outer.append(mid[i] + nor * hw)
		inner.append(mid[i] - nor * hw)
	var poly := outer
	for i in range(inner.size() - 1, -1, -1):
		poly.append(inner[i])
	c.draw_colored_polygon(poly, md)
	c.draw_polyline(poly, dk, 1.0, true)          # crisp cast edge

	# Sheen along one flank of the tube, brightest where that flank turns to face the
	# upper-left key light and fading to nothing at the roots and on the shaded side.
	var light := Vector2(-0.6, -0.8)
	var sheen := PackedVector2Array()
	var sheen_cols := PackedColorArray()
	for i in mid.size():
		var s2 := float(i) / float(n)
		var nor2: Vector2 = norms[i]
		if nor2.dot(light) < 0.0:
			nor2 = -nor2
		sheen.append(mid[i] + nor2 * 2.0)
		var a := clampf(nor2.dot(light), 0.0, 1.0) * sin(s2 * PI)
		sheen_cols.append(Color(lt.r, lt.g, lt.b, a * 0.95))
	c.draw_polyline_colors(sheen, sheen_cols, 1.8, true)

# One point on a cubic Bezier.
func _bezier3(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, s: float) -> Vector2:
	var u := 1.0 - s
	return u * u * u * p0 + 3.0 * u * u * s * p1 + 3.0 * u * s * s * p2 + s * s * s * p3

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

# Cog scaled to whatever square it's drawn into. A thick band plus stubby teeth
# of the SAME stroke width, with the hub left hollow — at 26px that silhouette
# reads as a gear, where thin spokes around a ring just read as a target.
func _draw_gear(c: Control) -> void:
	var col := Color(0.86, 0.88, 0.99)
	var s := c.size.x
	var ctr := Vector2(s, s) * 0.5
	var w := s * 0.13
	for i in 8:
		var a := TAU * float(i) / 8.0
		var d := Vector2(cos(a), sin(a))
		c.draw_line(ctr + d * s * 0.30, ctr + d * s * 0.45, col, w)
	c.draw_arc(ctr, s * 0.30, 0.0, TAU, 32, col, w, true)

# Pressing START pushes the CAP into its bezel — the frame, its channel and its light
# stay exactly where they are. Scaling the whole widget would read as a UI element
# being tapped; sinking one part of it reads as a switch being thrown. `_play_flash`
# is picked up by the next _play_accent_tick, which brightens the current colour
# without changing it.
func _on_lm_press(_art: Control) -> void:
	if _play_cap == null:
		return
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_play_cap, "position:y", _play_cap_rest + 5.0 * PLAY_K, 0.07) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "_play_flash", 1.0, 0.07)

func _on_lm_release(_art: Control) -> void:
	if _play_cap == null:
		return
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_play_cap, "position:y", _play_cap_rest, 0.26) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "_play_flash", 0.0, 0.34)

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

	# Account row hugs the right edge, on the same baseline as the top-left coin
	# pill so the two HUD corners sit level.
	if _account_hud:
		_account_hud.position = Vector2(sz.x - _account_hud.size.x - ACC_RIGHT, HUD_TOP)

	# credits tuck into the bottom-right corner, right-aligned. A wider right margin
	# pulls the line left so the "@drorbardavid" tail clears a phone's rounded corner
	# / safe-area edge instead of getting clipped.
	if _credits:
		_credits.size = Vector2(sz.x - 56.0, 18.0)   # right edge sits 40px from the screen edge
		_credits.position = Vector2(16.0, sz.y - 22.0)

	# The Daily Hub's dismiss catcher. Anchors are useless here (this screen lives
	# under a CanvasLayer and therefore has no size of its own), so the full-screen
	# sheet has to be measured against the viewport like everything else above —
	# without this it is a 0x0 control and taps outside the dropdown hit nothing.
	if _hub_catcher:
		_hub_catcher.position = Vector2.ZERO
		_hub_catcher.size = sz

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

	# The START button does not pulse in size — it is a machined object. What moves is
	# the light in its channel: one slow, seamless trip around the colour wheel, with
	# an idle swell folded into the same per-frame tick (see _play_accent_tick). LINEAR
	# so the wheel turns at a constant rate; the dwell on each colour comes from the
	# smoothstep inside a leg, not from the tween.
	if _play_accent:
		create_tween().set_loops() \
			.tween_method(_play_accent_tick, 0.0, float(PLAY_HUE.size()), PLAY_CYCLE) \
			.set_trans(Tween.TRANS_LINEAR)

	# ...and the logo's O breathes in its own gold.
	_o_breathe()

	# ...and the Arena pad remembers a pattern, one button at a time.
	_arena_pulse()

# The pad's idle: one button warms up, holds, fades, and after a beat of dark the next
# one in the pattern does the same. ~2.4s a button, so a whole pass takes about fifteen
# seconds — slow enough to read as ambience rather than as a sequence being played at
# you. Nothing redraws: this is six `modulate:a` tweens on a chain.
func _arena_pulse() -> void:
	if _pad_lights.is_empty():
		return
	var tw := create_tween().set_loops()
	for idx in PAD_SEQ:
		var lit: Node2D = _pad_lights[idx]
		tw.tween_property(lit, "modulate:a", 1.0, 0.55) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_interval(0.28)
		tw.tween_property(lit, "modulate:a", 0.0, 0.75) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_interval(0.85)

# ---------------- account HUD (top-right) ----------------

# The top-right corner, signed in:
#
#        [ name ]•   ( ⚙ )
#     opens Profile ↑   settings (+ sign out)
#          new-achievement dot
#
# The account capsule is the one solid, saturated object up here: a moulded deep
# blue bubble with the player's gold name centred on it and nothing else, so their
# identity reads as a physical badge rather than another pane of the HUD glass.
# The red dot on its shoulder is the only thing that ever joins the name there —
# it appears the moment an achievement is earned and clears once the profile (which
# is where the badge gallery lives, each new badge dotted in turn) is closed. Settings keeps
# the glass treatment — it's a tool, not an identity — and now owns sign-out,
# which is a rare, deliberate action that has no business one mis-tap away from
# the profile button. Guests get a labelled "Sign In" capsule beside the bubble.
const ACC_H := 56.0                     # == COIN_PILL_H, the top-left twin
const ACC_DISC := 48.0                  # round action buttons
const ACC_GAP := 10.0                   # breathing room BETWEEN the controls
const ACC_PILL_W := 196.0               # account capsule (signed in)
const ACC_GUEST_W := 152.0              # ...and with the shorter "Guest" on it
const ACC_SIGNIN_W := 116.0             # labelled "Sign In" capsule (guests)
const ACC_RIGHT := 18.0                 # margin from the screen's right edge

# Rim/aura accents per control.
const ACC_RIM := Color(0.55, 0.62, 1.0)         # the shared blue-violet HUD rim
const ACC_AURA := Color(0.55, 0.36, 1.0)        # purple outer glow (as coin pill)
const ACC_INVITE := Color(0.32, 0.76, 1.0)      # sign-in

# The account bubble's own palette — a deep navy dome, not HUD glass. TOP → FACE
# → BELLY is the vertical ramp painted across the capsule; DEEP is the socket it
# sits in, showing only as the strip of thickness under its bottom edge. Kept dark
# on purpose: the gold name is the bright thing on this object, and a mid-blue face
# fought it for attention.
const ACC_BLUE_DEEP := Color(0.00, 0.02, 0.09)  # the socket / underside
const ACC_BLUE_TOP := Color(0.09, 0.21, 0.50)   # lit crown
const ACC_BLUE_FACE := Color(0.03, 0.11, 0.34)  # the body colour, mid-height
const ACC_BLUE_BELLY := Color(0.01, 0.05, 0.20) # shaded lower curve
const ACC_BLUE_RIM := Color(0.22, 0.42, 0.80)   # bright edge catching the light
const ACC_BEVEL := 4.0                          # how much underside shows below

func _build_account_hud() -> void:
	_account_hud = Control.new()
	_account_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_account_hud)

	var signed := FirebaseManager.is_signed_in() and FirebaseManager.has_display_name()
	var x := 0.0

	# --- (1) account bubble: the player's name, and nothing else to mis-tap ---
	var pill_w := ACC_PILL_W if signed else ACC_GUEST_W
	var pill := _bubble_button(Vector2(pill_w, ACC_H))
	pill.position = Vector2(x, 0)
	pill.pressed.connect(_open_profile_popup)
	_account_hud.add_child(pill)

	# Text is printed on the lit face (so it rides the press), which means it
	# centres against ACC_H - ACC_BEVEL and is inset by the face's own offset.
	var face: Control = pill.get_node("Face")
	var face_h := face.size.y

	# The name, alone and centred on the capsule. It carried a "View profile"
	# caption before; the name IS the affordance here — every other object in this
	# corner is a labelled control, so a capsule wearing the player's own name reads
	# as theirs to tap without being told.
	var nl := Label.new()
	nl.text = FirebaseManager.display_name if signed else "Guest"
	nl.add_theme_font_size_override("font_size", 21)
	nl.add_theme_color_override("font_color", GOLD)
	# On blue, gold needs a dark contact shadow to stay legible rather than the
	# warm bloom it wore on the near-black glass.
	nl.add_theme_color_override("font_shadow_color", Color(0.01, 0.04, 0.16, 0.80))
	nl.add_theme_constant_override("shadow_offset_x", 0)
	nl.add_theme_constant_override("shadow_offset_y", 1)
	nl.add_theme_constant_override("shadow_outline_size", 4)
	nl.position = Vector2(14, 0)
	nl.size = Vector2(face.size.x - 28.0, face_h)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_child(nl)

	# Red "new achievement" dot on the bubble's top-right, the same gesture the
	# daily-claim gift disc uses. It's a sibling of the bubble, not a child, so
	# the press animation doesn't drag it around. Opening the profile (which is
	# what the bubble does) shows the gallery and clears it.
	_ach_badge = Panel.new()
	_ach_badge.size = Vector2(14, 14)
	_ach_badge.position = Vector2(x + pill_w - 15.0, -3.0)
	_ach_badge.pivot_offset = Vector2(7, 7)
	_ach_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var abs_ := StyleBoxFlat.new()
	abs_.bg_color = Color(0.95, 0.18, 0.18)
	abs_.set_corner_radius_all(7)
	abs_.border_color = Color(1.0, 0.80, 0.80, 0.85)
	abs_.set_border_width_all(1)
	abs_.shadow_color = Color(0.95, 0.18, 0.18, 0.7)
	abs_.shadow_size = 8
	_ach_badge.add_theme_stylebox_override("panel", abs_)
	_account_hud.add_child(_ach_badge)

	var apulse := create_tween().set_loops()
	apulse.tween_property(_ach_badge, "scale", Vector2.ONE * 1.25, 0.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	apulse.tween_property(_ach_badge, "scale", Vector2.ONE, 0.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	_refresh_ach_badge()
	BadgeManager.unseen_changed.connect(_refresh_ach_badge)

	x += pill_w + ACC_GAP

	# --- (2) guests get an inviting labelled capsule of their own: a lone
	# "enter" glyph tucked into the account pill would be a guess, and there's
	# no account to attach it to yet. ---
	if not signed:
		var in_btn := _glass_button(Vector2(ACC_SIGNIN_W, ACC_DISC), ACC_INVITE, Color(0.20, 0.62, 1.0))
		in_btn.position = Vector2(x, (ACC_H - ACC_DISC) * 0.5)
		in_btn.pressed.connect(_on_sign_in)
		_account_hud.add_child(in_btn)
		x += ACC_SIGNIN_W + ACC_GAP
		# Glyph + label are placed by hand (not via Button.text/icon) so the pair
		# keeps a fixed optical rhythm inside the capsule at any font metric.
		var ii := Control.new()
		ii.size = Vector2(22, 22)
		ii.position = Vector2(13, (ACC_DISC - 22) * 0.5)
		ii.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ii.draw.connect(_draw_exit_icon.bind(ii, Color(0.62, 0.88, 1.0), false))
		in_btn.add_child(ii)
		var il := Label.new()
		il.text = "Sign In"
		il.add_theme_font_size_override("font_size", 17)
		il.add_theme_color_override("font_color", Color(0.84, 0.94, 1.0))
		il.add_theme_color_override("font_shadow_color", Color(0.25, 0.65, 1.0, 0.45))
		il.add_theme_constant_override("shadow_offset_x", 0)
		il.add_theme_constant_override("shadow_offset_y", 0)
		il.add_theme_constant_override("shadow_outline_size", 6)
		il.position = Vector2(41, 0)
		il.size = Vector2(ACC_SIGNIN_W - 41 - 10, ACC_DISC)
		il.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		il.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		il.mouse_filter = Control.MOUSE_FILTER_IGNORE
		in_btn.add_child(il)
		# Slow breathing aura: the one thing in the corner asking to be tapped.
		var br := create_tween().set_loops()
		br.tween_property(in_btn, "modulate", Color(1.15, 1.15, 1.15), 1.3) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		br.tween_property(in_btn, "modulate", Color.WHITE, 1.3) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# --- (3) settings disc ---
	var gear_btn := _glass_button(Vector2(ACC_DISC, ACC_DISC), ACC_RIM, ACC_AURA)
	gear_btn.position = Vector2(x, (ACC_H - ACC_DISC) * 0.5)
	gear_btn.tooltip_text = "Settings"
	gear_btn.pressed.connect(_show_settings_popup)
	_account_hud.add_child(gear_btn)
	x += ACC_DISC

	var gi := _icon_holder(gear_btn, 28.0)
	gi.draw.connect(_draw_gear.bind(gi))
	# The gear turns a notch as it's pressed — cheap, and it makes the tap feel
	# mechanical rather than like a flat image lighting up.
	gear_btn.button_down.connect(func() -> void:
		create_tween().tween_property(gi, "rotation", PI * 0.25, 0.18) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	gear_btn.button_up.connect(func() -> void:
		create_tween().tween_property(gi, "rotation", 0.0, 0.35) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))

	_account_hud.size = Vector2(x, ACC_H)

	# Staggered drop-in so the corner assembles itself instead of popping.
	for i in _account_hud.get_child_count():
		var ch: Control = _account_hud.get_child(i)
		var rest := ch.position
		ch.position = rest - Vector2(0, 14)
		ch.modulate.a = 0.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(ch, "position", rest, 0.42).set_delay(0.08 * i) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(ch, "modulate:a", 1.0, 0.28).set_delay(0.08 * i)

func _refresh_ach_badge() -> void:
	if _ach_badge and is_instance_valid(_ach_badge):
		_ach_badge.visible = BadgeManager.has_unseen()

# The account bubble: a moulded blue capsule rather than another pane of glass.
# A deep socket panel carries the outer aura, and the bubble itself is DRAWN one
# scanline at a time (see _draw_bubble) so its surface is a continuous gradient —
# a stacked "gloss panel" always betrays itself with a hard inner edge at this
# size, which reads as a second object rather than as curvature. The bubble sits
# ACC_BEVEL px above the socket's bottom; that exposed strip is the thickness.
# Pressing drops it into the socket, so the capsule squashes rather than tints.
func _bubble_button(size: Vector2) -> Button:
	var btn := Button.new()
	btn.size = size
	btn.focus_mode = Control.FOCUS_NONE
	btn.pivot_offset = size * 0.5
	# The button is a bare hit zone; every pixel of it is painted by the children.
	for st in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())

	var body := Panel.new()
	body.size = size
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bs := StyleBoxFlat.new()
	bs.bg_color = ACC_BLUE_DEEP
	bs.set_corner_radius_all(int(size.y * 0.5))
	bs.shadow_color = Color(0.05, 0.18, 0.62, 0.36)
	bs.shadow_size = 13
	bs.shadow_offset = Vector2(0, 3)
	body.add_theme_stylebox_override("panel", bs)
	btn.add_child(body)

	# Named so the caller can hang the name/caption off the FACE — text has to
	# travel with the surface it's printed on when the bubble is pressed.
	var face := Control.new()
	face.name = "Face"
	face.size = Vector2(size.x - 3.0, size.y - ACC_BEVEL)
	face.position = Vector2(1.5, 0)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.draw.connect(_draw_bubble.bind(face))
	btn.add_child(face)

	btn.button_down.connect(func() -> void:
		create_tween().tween_property(face, "position:y", ACC_BEVEL - 1.0, 0.08) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT))
	btn.button_up.connect(func() -> void:
		create_tween().tween_property(face, "position:y", 0.0, 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	return btn

# Paints the capsule as horizontal scanlines: each row gets the stadium's own
# half-width (so the silhouette is exactly round) and a colour sampled from a
# top-lit vertical ramp, with a specular falloff over the upper third. Drawn
# once per invalidation, not per frame — it's a static surface.
func _draw_bubble(c: Control) -> void:
	var w := c.size.x
	var h := c.size.y
	var r := h * 0.5
	# One extra row of bright rim underneath, then the ramp inset by a pixel, so
	# the edge catches light without a separate stroke pass.
	c.draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0))
	for pass_i in 2:
		var inset := 0.0 if pass_i == 0 else 1.0
		var ph := h - inset * 2.0
		var pr := ph * 0.5
		for row in int(ceil(ph)):
			var y := float(row) + 0.5
			# Half-width lost to the rounded cap at this height.
			var dx := 0.0
			if y < pr:
				dx = pr - sqrt(maxf(0.0, pr * pr - (pr - y) * (pr - y)))
			elif y > ph - pr:
				var dy := y - (ph - pr)
				dx = pr - sqrt(maxf(0.0, pr * pr - dy * dy))
			var col := ACC_BLUE_RIM
			if pass_i == 1:
				var t := y / ph
				# Two-segment ramp: lit crown, then a long fall into the shaded
				# belly, which is what makes the surface read as curved.
				col = ACC_BLUE_TOP.lerp(ACC_BLUE_FACE, minf(1.0, t / 0.45)) if t < 0.45 \
					else ACC_BLUE_FACE.lerp(ACC_BLUE_BELLY, (t - 0.45) / 0.55)
				# Specular: strongest just under the crown, gone by a third down.
				var s := maxf(0.0, 1.0 - t / 0.34)
				col = col.lerp(Color(1, 1, 1), 0.20 * s * s)
			c.draw_rect(Rect2(dx + inset, float(row) + inset, w - inset * 2.0 - dx * 2.0, 1.0), col)

# A tappable capsule of navy glass with a neon rim and a coloured aura — the
# shared body of every control in the account row. Hover brightens and lifts the
# aura; press sinks it (aura shrinks, face darkens) and nudges the whole button
# down a hair, which is what sells the physicality on a touch screen.
func _glass_button(size: Vector2, rim: Color, aura: Color) -> Button:
	var btn := Button.new()
	btn.size = size
	btn.focus_mode = Control.FOCUS_NONE
	btn.pivot_offset = size * 0.5
	var r := int(minf(size.x, size.y) * 0.5)

	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(0.03, 0.04, 0.12, 0.90)
	sn.set_corner_radius_all(r)
	sn.border_color = Color(rim.r, rim.g, rim.b, 0.55)
	sn.set_border_width_all(1)
	sn.shadow_color = Color(aura.r, aura.g, aura.b, 0.36)
	sn.shadow_size = 12
	sn.shadow_offset = Vector2(0, 2)
	btn.add_theme_stylebox_override("normal", sn)

	var sh := sn.duplicate() as StyleBoxFlat
	sh.bg_color = Color(0.07, 0.09, 0.20, 0.94)
	sh.border_color = Color(rim.r, rim.g, rim.b, 0.85)
	sh.shadow_size = 17
	btn.add_theme_stylebox_override("hover", sh)

	var sp := sn.duplicate() as StyleBoxFlat
	sp.bg_color = Color(0.02, 0.02, 0.08, 0.96)
	sp.border_color = Color(rim.r, rim.g, rim.b, 0.95)
	sp.shadow_size = 4
	sp.shadow_offset = Vector2(0, 1)
	btn.add_theme_stylebox_override("pressed", sp)

	btn.button_down.connect(func() -> void:
		create_tween().tween_property(btn, "scale", Vector2(0.955, 0.955), 0.09) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT))
	btn.button_up.connect(func() -> void:
		create_tween().tween_property(btn, "scale", Vector2.ONE, 0.24) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	return btn

# Centred, rotate-able square that an icon painter draws into.
func _icon_holder(parent: Control, d: float) -> Control:
	var c := Control.new()
	c.size = Vector2(d, d)
	c.position = (parent.size - Vector2(d, d)) * 0.5
	c.pivot_offset = Vector2(d, d) * 0.5
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
	return c

# Door-and-arrow glyph. The arrow always travels left→right (the direction of
# "going"); `out` puts the door behind it and the arrow leaving the frame (sign
# out), otherwise the door is ahead of it and the arrow heads in (sign in).
func _draw_exit_icon(c: Control, col: Color, out: bool) -> void:
	var s := c.size.x
	var w := maxf(2.0, s * 0.10)
	var top := s * 0.08
	var bot := s * 0.92
	# Door: a three-sided frame, its open side facing the arrow's path.
	if out:
		c.draw_polyline(PackedVector2Array([
			Vector2(s * 0.40, top), Vector2(s * 0.08, top),
			Vector2(s * 0.08, bot), Vector2(s * 0.40, bot)]), col, w, true)
	else:
		c.draw_polyline(PackedVector2Array([
			Vector2(s * 0.60, top), Vector2(s * 0.92, top),
			Vector2(s * 0.92, bot), Vector2(s * 0.60, bot)]), col, w, true)
	# Arrow, clear of the frame either way.
	var y := s * 0.5
	var tip := Vector2(s * 0.94 if out else s * 0.52, y)
	c.draw_line(Vector2(s * 0.50 if out else s * 0.06, y), tip, col, w)
	c.draw_polyline(PackedVector2Array([
		tip - Vector2(s * 0.20, s * 0.18), tip, tip - Vector2(s * 0.20, -s * 0.18)]),
		col, w, true)

# Sign-out asks first — and says plainly that nothing is lost, which is the
# actual worry. The settings popup that opened this stays up behind the
# confirmation (matching Delete Account) so cancelling lands the player back
# where they were; an actual sign-out rebuilds the home screen and takes it with
# it, so there's nothing to tear down here.
func _confirm_sign_out(_settings_overlay: Control = null) -> void:
	var sz := get_viewport_rect().size
	var overlay := Control.new()
	overlay.name = "SignOutPopup"
	overlay.position = Vector2.ZERO
	overlay.size = sz
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.01, 0.04, 0.62)
	dim.position = Vector2.ZERO
	dim.size = sz
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(dim)

	var close_bg := _overlay_button(sz)
	close_bg.pressed.connect(overlay.queue_free)
	overlay.add_child(close_bg)

	const PW := 430.0
	const PH := 250.0
	var panel := _card_panel(Vector2(PW, PH), Color(0.05, 0.06, 0.16, 0.98),
		Color(0.40, 0.50, 1.0, 0.55), Color(0.0, 0.0, 0.0, 0.55))
	panel.position = (sz - Vector2(PW, PH)) * 0.5
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(panel)

	var title := Label.new()
	title.text = "Sign Out?"
	title.add_theme_font_size_override("font_size", 27)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.position = Vector2(24, 26)
	title.size = Vector2(PW - 48, 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(title)

	var body := Label.new()
	body.text = "You'll go back to playing as a guest. Your coins, scores and cosmetics stay on your account — sign back in any time to pick up where you left off."
	body.add_theme_font_size_override("font_size", 15)
	body.add_theme_color_override("font_color", Color(0.80, 0.83, 0.95, 0.92))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.position = Vector2(24, 74)
	body.size = Vector2(PW - 48, 90)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(body)

	var half := (PW - 48.0 - 14.0) * 0.5
	_make_popup_button(panel, "Cancel", Vector2(24, PH - 66), Vector2(half, 50),
		Color(0.16, 0.18, 0.34), overlay.queue_free)
	_make_popup_button(panel, "Sign Out", Vector2(24 + half + 14, PH - 66), Vector2(half, 50),
		Color(0.62, 0.16, 0.20), func() -> void:
			overlay.queue_free()
			_on_sign_out())

	panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2(0.92, 0.92)
	overlay.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(overlay, "modulate:a", 1.0, 0.20).set_trans(Tween.TRANS_SINE)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

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

# ---------------- Daily Hub (top nav) ----------------
#
# The second pill of the top-left navigation bar: [coin pill][Daily Hub v].
# Tapping it expands a panel directly underneath holding the two daily rituals
# as one row each — the login claim, and the task board's progress. Both used to
# be their own HUD pill; folding them into one dropdown gives the corner a single
# entry point (and a single red dot) instead of three competing chips.
#
# Geometry note: the panel is left-aligned with the coin pill and RIGHT-aligned
# with the hub pill, so it reads as the whole nav cluster unfolding rather than a
# slab floating under one button. Its right edge stops short of the SIMON logo's
# "S" and its height stops short of the Shop card — the dropdown never covers
# either, nor the central START orb.
const HUB_PILL_W := 160.0
const HUB_PILL_H := COIN_PILL_H
const HUB_PANEL_W := 406.0
const HUB_PANEL_H := 160.0
const HUB_PANEL_GAP := 10.0             # pill bottom -> panel top
# Slack around the panel so the reveal window doesn't crop its purple aura.
const HUB_GLOW_M := 26.0
const HUB_OPEN_T := 0.28
const HUB_CLOSE_T := 0.22
const HUB_PURPLE := Color(0.66, 0.36, 1.0)      # the shared "daily" purple
const HUB_PURPLE_HI := Color(0.90, 0.70, 1.0)   # its lit rim
const HUB_TEAL := Color(0.30, 0.85, 0.84)       # tasks accent (kept from the old pill)
const HUB_GREEN := Color(0.22, 0.82, 0.48)      # claimed / done
const HUB_PAD := 18.0                   # panel inner margin
const HUB_ACT_W := 116.0                # width of both right-hand action buttons

func _build_daily_hub() -> void:
	var x := HUD_LEFT + COIN_PILL_W + HUD_GAP
	var y := HUD_TOP

	_hub_btn = Button.new()
	_hub_btn.position = Vector2(x, y)
	_hub_btn.size = Vector2(HUB_PILL_W, HUB_PILL_H)
	_hub_btn.focus_mode = Control.FOCUS_NONE
	# Same navy glass body / purple rim / purple aura as the coin pill beside it,
	# so the two read as one bar rather than two unrelated widgets.
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.03, 0.04, 0.12, 0.90)
	s.set_corner_radius_all(int(HUB_PILL_H * 0.5))
	s.border_color = Color(0.78, 0.62, 1.0, 0.55)
	s.set_border_width_all(1)
	s.shadow_color = Color(0.55, 0.36, 1.0, 0.40)
	s.shadow_size = 14
	s.shadow_offset = Vector2(0, 2)
	_hub_btn.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = Color(0.08, 0.08, 0.20, 0.95)
	sh.border_color = Color(0.86, 0.72, 1.0, 0.80)
	sh.shadow_size = 18
	_hub_btn.add_theme_stylebox_override("hover", sh)
	var sp := s.duplicate() as StyleBoxFlat
	sp.bg_color = Color(0.02, 0.02, 0.10, 1.0)
	sp.shadow_size = 6
	_hub_btn.add_theme_stylebox_override("pressed", sp)
	_hub_btn.text = ""                                  # art is overlaid below
	_hub_btn.pressed.connect(_toggle_hub)
	add_child(_hub_btn)

	# Purple gift disc on the left — the same mark the old Daily Claim pill wore,
	# so the button still says "rewards live here" at a glance.
	var d := 36.0
	var disc := _hub_disc(d, HUB_PURPLE, HUB_PURPLE_HI)
	disc.position = Vector2(9.0, (HUB_PILL_H - d) * 0.5)
	_hub_btn.add_child(disc)
	var gift := Control.new()
	gift.size = Vector2(d, d)
	gift.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gift.draw.connect(_draw_gift_icon.bind(gift))
	disc.add_child(gift)

	var lbl := Label.new()
	lbl.text = "Daily Hub"
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_color_override("font_outline_color", Color.WHITE)
	lbl.add_theme_constant_override("outline_size", 1)
	lbl.add_theme_color_override("font_shadow_color", Color(0.62, 0.36, 1.0, 0.40))
	lbl.add_theme_constant_override("shadow_outline_size", 4)
	lbl.position = Vector2(9.0 + d + 6.0, 0)
	lbl.size = Vector2(HUB_PILL_W - (9.0 + d + 6.0) - 26.0, HUB_PILL_H)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hub_btn.add_child(lbl)

	# Down-caret on the far right; it flips to point up while the panel is open,
	# which is the one cue that tells the player this pill is a dropdown.
	_hub_caret = Control.new()
	_hub_caret.size = Vector2(22, 22)
	_hub_caret.position = Vector2(HUB_PILL_W - 28.0, (HUB_PILL_H - 22.0) * 0.5)
	_hub_caret.pivot_offset = Vector2(11, 11)
	_hub_caret.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hub_caret.draw.connect(_draw_hub_caret.bind(_hub_caret))
	_hub_btn.add_child(_hub_caret)

	# Red "something daily is outstanding" dot, top-right of the pill.
	_hub_badge = Panel.new()
	_hub_badge.size = Vector2(14, 14)
	_hub_badge.position = Vector2(HUB_PILL_W - 18.0, 2.0)
	_hub_badge.pivot_offset = Vector2(7, 7)
	_hub_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.95, 0.18, 0.18)
	bs.set_corner_radius_all(7)
	bs.border_color = Color(1.0, 0.80, 0.80, 0.85)
	bs.set_border_width_all(1)
	bs.shadow_color = Color(0.95, 0.18, 0.18, 0.7)
	bs.shadow_size = 8
	_hub_badge.add_theme_stylebox_override("panel", bs)
	_hub_btn.add_child(_hub_badge)

	var pulse := create_tween().set_loops()
	pulse.tween_property(_hub_badge, "scale", Vector2.ONE * 1.25, 0.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(_hub_badge, "scale", Vector2.ONE, 0.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	_build_hub_panel()

	_hub_tick = Timer.new()
	_hub_tick.wait_time = 1.0
	_hub_tick.timeout.connect(_refresh_claim_status)
	add_child(_hub_tick)

	_refresh_hub()
	CoinsManager.daily_claim_changed.connect(_refresh_hub)
	CoinsManager.loaded.connect(_refresh_hub)
	DailyTasks.changed.connect(_refresh_hub)

# The dropdown itself. Built once, hidden, and revealed by growing `_hub_clip`
# (a clipping window) rather than by scaling the panel — scaling would squash the
# text and the corner radii, while a clip reads as the panel unrolling out of the
# nav bar. The window is inflated by HUB_GLOW_M on every side so the panel's
# purple aura isn't sliced off at the edges.
func _build_hub_panel() -> void:
	var px := HUD_LEFT
	var py := HUD_TOP + HUB_PILL_H + HUB_PANEL_GAP

	# Sits UNDER the panel in the tree, so taps inside the panel reach its own
	# controls first and only strays out here dismiss the dropdown. Sized to the
	# viewport by _layout (anchors give nothing under a CanvasLayer) and raised
	# above the rest of the screen by _open_hub, so the first tap anywhere else
	# just closes the dropdown instead of pressing whatever is under the finger.
	_hub_catcher = Control.new()
	_hub_catcher.position = Vector2.ZERO
	_hub_catcher.size = get_viewport_rect().size
	_hub_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	_hub_catcher.visible = false
	_hub_catcher.gui_input.connect(_on_hub_catcher_input)
	add_child(_hub_catcher)

	_hub_clip = Control.new()
	_hub_clip.position = Vector2(px - HUB_GLOW_M, py - HUB_GLOW_M)
	_hub_clip.size = Vector2(HUB_PANEL_W + HUB_GLOW_M * 2.0, 0.0)
	_hub_clip.clip_contents = true
	_hub_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hub_clip.visible = false
	_hub_clip.modulate.a = 0.0
	add_child(_hub_clip)

	_hub_panel = Panel.new()
	_hub_panel.position = Vector2(HUB_GLOW_M, HUB_GLOW_M)
	_hub_panel.size = Vector2(HUB_PANEL_W, HUB_PANEL_H)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.045, 0.05, 0.15, 0.97)
	ps.set_corner_radius_all(22)
	ps.border_color = Color(0.62, 0.48, 1.0, 0.55)
	ps.set_border_width_all(1)
	ps.shadow_color = Color(0.45, 0.24, 0.95, 0.45)
	ps.shadow_size = 18
	ps.shadow_offset = Vector2(0, 6)
	_hub_panel.add_theme_stylebox_override("panel", ps)
	_hub_clip.add_child(_hub_panel)

	# A soft violet wash across the top edge so the panel feels lit from the pill
	# above it instead of being a flat slab.
	var sheen := Panel.new()
	sheen.size = Vector2(HUB_PANEL_W - 2.0, 46.0)
	sheen.position = Vector2(1.0, 1.0)
	sheen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ss := StyleBoxFlat.new()
	ss.bg_color = Color(0.55, 0.36, 1.0, 0.10)
	ss.corner_radius_top_left = 21
	ss.corner_radius_top_right = 21
	sheen.add_theme_stylebox_override("panel", ss)
	_hub_panel.add_child(sheen)

	_build_hub_claim_row()
	_build_hub_divider()
	_build_hub_tasks_row()

const HUB_ROW_A := 16.0                 # claim row top, in panel space
const HUB_ROW_B := 89.0                 # tasks row top
const HUB_DISC := 38.0
const HUB_TEXT_X := HUB_PAD + HUB_DISC + 12.0

# 🎁 Daily Claim — gift disc, status line, and a bright purple Claim button that
# collects the reward in place. The row's left half is its own flat hit zone and
# opens the full streak popup, so the seven-day grid stays one tap away.
func _build_hub_claim_row() -> void:
	var open_zone := _hub_row_hit(HUB_ROW_A, _open_daily_popup)
	_hub_panel.add_child(open_zone)

	var disc := _hub_disc(HUB_DISC, HUB_PURPLE, HUB_PURPLE_HI)
	disc.position = Vector2(HUB_PAD, HUB_ROW_A + 2.0)
	_hub_panel.add_child(disc)
	var gift := Control.new()
	gift.size = Vector2(HUB_DISC, HUB_DISC)
	gift.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gift.draw.connect(_draw_gift_icon.bind(gift))
	disc.add_child(gift)

	_hub_panel.add_child(_hub_title("Daily Claim", HUB_ROW_A))
	_claim_status = _hub_sub("", HUB_ROW_A + 23.0)
	_hub_panel.add_child(_claim_status)

	var bx := HUB_PANEL_W - HUB_PAD - HUB_ACT_W
	_claim_btn = Button.new()
	_claim_btn.text = "Claim"
	_claim_btn.size = Vector2(HUB_ACT_W, 38.0)
	_claim_btn.position = Vector2(bx, HUB_ROW_A + 2.0)
	_claim_btn.pivot_offset = Vector2(HUB_ACT_W, 38.0) * 0.5
	_claim_btn.focus_mode = Control.FOCUS_NONE
	_claim_btn.add_theme_font_size_override("font_size", 17)
	_claim_btn.add_theme_color_override("font_color", Color.WHITE)
	_claim_btn.add_theme_color_override("font_hover_color", Color.WHITE)
	var cs := StyleBoxFlat.new()
	cs.bg_color = HUB_PURPLE
	cs.set_corner_radius_all(19)
	cs.border_color = HUB_PURPLE_HI
	cs.set_border_width_all(2)
	cs.shadow_color = Color(0.62, 0.32, 1.0, 0.75)
	cs.shadow_size = 12
	_claim_btn.add_theme_stylebox_override("normal", cs)
	var ch := cs.duplicate() as StyleBoxFlat
	ch.bg_color = Color(0.74, 0.46, 1.0)
	ch.shadow_size = 16
	_claim_btn.add_theme_stylebox_override("hover", ch)
	var cp := cs.duplicate() as StyleBoxFlat
	cp.bg_color = Color(0.50, 0.24, 0.86)
	cp.shadow_size = 4
	_claim_btn.add_theme_stylebox_override("pressed", cp)
	_claim_btn.pressed.connect(_on_hub_claim)
	_hub_panel.add_child(_claim_btn)

	# Breathing glow so the one actionable thing in the panel is unmistakable.
	var br := create_tween().set_loops()
	br.tween_property(_claim_btn, "scale", Vector2.ONE * 1.045, 0.8) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	br.tween_property(_claim_btn, "scale", Vector2.ONE, 0.8) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# ...and its already-collected twin, occupying the exact same rect.
	_claim_done = Panel.new()
	_claim_done.size = Vector2(HUB_ACT_W, 38.0)
	_claim_done.position = Vector2(bx, HUB_ROW_A + 2.0)
	_claim_done.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ds := StyleBoxFlat.new()
	ds.bg_color = Color(HUB_GREEN.r, HUB_GREEN.g, HUB_GREEN.b, 0.16)
	ds.set_corner_radius_all(19)
	ds.border_color = Color(HUB_GREEN.r, HUB_GREEN.g, HUB_GREEN.b, 0.60)
	ds.set_border_width_all(1)
	_claim_done.add_theme_stylebox_override("panel", ds)
	_hub_panel.add_child(_claim_done)
	var tick := Control.new()
	tick.size = Vector2(20, 20)
	tick.position = Vector2(16, 9)
	tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tick.draw.connect(_draw_hub_check.bind(tick))
	_claim_done.add_child(tick)
	var dl := Label.new()
	dl.text = "Claimed"
	dl.add_theme_font_size_override("font_size", 15)
	dl.add_theme_color_override("font_color", Color(0.62, 0.95, 0.74))
	dl.position = Vector2(40, 0)
	dl.size = Vector2(HUB_ACT_W - 46.0, 38.0)
	dl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_claim_done.add_child(dl)

func _build_hub_divider() -> void:
	var line := ColorRect.new()
	line.color = Color(0.62, 0.56, 1.0, 0.16)
	line.size = Vector2(HUB_PANEL_W - HUB_PAD * 2.0, 1.0)
	line.position = Vector2(HUB_PAD, 74.0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hub_panel.add_child(line)

# 🎯 Daily Tasks — clipboard disc, "N/M Completed", a progress bar under the
# text, and a View Tasks button (red-dotted when rewards are sitting unclaimed).
func _build_hub_tasks_row() -> void:
	var open_zone := _hub_row_hit(HUB_ROW_B, _open_tasks_popup)
	_hub_panel.add_child(open_zone)

	var disc := _hub_disc(HUB_DISC, HUB_TEAL, Color(0.72, 0.98, 0.98))
	disc.position = Vector2(HUB_PAD, HUB_ROW_B + 2.0)
	_hub_panel.add_child(disc)
	var glyph := Control.new()
	glyph.size = Vector2(HUB_DISC, HUB_DISC)            # _draw_tasks_icon scales itself
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph.draw.connect(_draw_tasks_icon.bind(glyph))
	disc.add_child(glyph)

	_hub_panel.add_child(_hub_title("Daily Tasks", HUB_ROW_B))
	_tasks_count_lbl = _hub_sub("", HUB_ROW_B + 23.0)
	_hub_panel.add_child(_tasks_count_lbl)

	# Progress bar, tucked under the label and stopping short of the button.
	var bar_x := HUB_TEXT_X
	var bar_w := HUB_PANEL_W - HUB_PAD - HUB_ACT_W - 16.0 - bar_x
	var track := Panel.new()
	track.size = Vector2(bar_w, 8.0)
	track.position = Vector2(bar_x, HUB_ROW_B + 45.0)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ts := StyleBoxFlat.new()
	ts.bg_color = Color(1, 1, 1, 0.09)
	ts.set_corner_radius_all(4)
	ts.border_color = Color(0.62, 0.56, 1.0, 0.20)
	ts.set_border_width_all(1)
	track.add_theme_stylebox_override("panel", ts)
	_hub_panel.add_child(track)

	_tasks_bar_fill = Panel.new()
	_tasks_bar_fill.size = Vector2(0, 8.0)
	_tasks_bar_fill.position = Vector2.ZERO
	_tasks_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fs := StyleBoxFlat.new()
	fs.bg_color = HUB_PURPLE
	fs.set_corner_radius_all(4)
	fs.shadow_color = Color(0.62, 0.32, 1.0, 0.55)
	fs.shadow_size = 6
	_tasks_bar_fill.add_theme_stylebox_override("panel", fs)
	track.add_child(_tasks_bar_fill)

	var bx := HUB_PANEL_W - HUB_PAD - HUB_ACT_W
	var view := Button.new()
	view.text = "View Tasks"
	view.size = Vector2(HUB_ACT_W, 38.0)
	view.position = Vector2(bx, HUB_ROW_B + 6.0)
	view.focus_mode = Control.FOCUS_NONE
	view.add_theme_font_size_override("font_size", 15)
	view.add_theme_color_override("font_color", Color(0.92, 0.90, 1.0))
	view.add_theme_color_override("font_hover_color", Color.WHITE)
	var vs := StyleBoxFlat.new()
	vs.bg_color = Color(0.16, 0.13, 0.34, 0.95)
	vs.set_corner_radius_all(19)
	vs.border_color = Color(0.72, 0.58, 1.0, 0.65)
	vs.set_border_width_all(1)
	view.add_theme_stylebox_override("normal", vs)
	var vh := vs.duplicate() as StyleBoxFlat
	vh.bg_color = Color(0.24, 0.19, 0.46, 0.98)
	vh.border_color = Color(0.86, 0.72, 1.0, 0.90)
	view.add_theme_stylebox_override("hover", vh)
	var vp := vs.duplicate() as StyleBoxFlat
	vp.bg_color = Color(0.11, 0.08, 0.26, 1.0)
	view.add_theme_stylebox_override("pressed", vp)
	view.pressed.connect(_open_tasks_popup)
	_hub_panel.add_child(view)

	_tasks_ready_dot = Panel.new()
	_tasks_ready_dot.size = Vector2(12, 12)
	_tasks_ready_dot.position = Vector2(HUB_ACT_W - 12.0, -2.0)
	_tasks_ready_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rs := StyleBoxFlat.new()
	rs.bg_color = Color(0.95, 0.18, 0.18)
	rs.set_corner_radius_all(6)
	rs.shadow_color = Color(0.95, 0.18, 0.18, 0.7)
	rs.shadow_size = 7
	_tasks_ready_dot.add_theme_stylebox_override("panel", rs)
	view.add_child(_tasks_ready_dot)

# ---- panel building blocks ----

# The transparent hit zone under a row's disc + text: opens that row's full
# screen. Only the left column, so it never steals the action button's taps.
func _hub_row_hit(top: float, on_press: Callable) -> Button:
	var b := Button.new()
	b.position = Vector2(HUB_PAD - 6.0, top - 4.0)
	b.size = Vector2(HUB_PANEL_W - HUB_PAD - HUB_ACT_W - 16.0 - (HUB_PAD - 6.0), 50.0)
	b.focus_mode = Control.FOCUS_NONE
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(0, 0, 0, 0)
	flat.set_corner_radius_all(14)
	b.add_theme_stylebox_override("normal", flat)
	b.add_theme_stylebox_override("focus", flat)
	var fh := flat.duplicate() as StyleBoxFlat
	fh.bg_color = Color(1, 1, 1, 0.05)
	b.add_theme_stylebox_override("hover", fh)
	var fp := flat.duplicate() as StyleBoxFlat
	fp.bg_color = Color(1, 1, 1, 0.09)
	b.add_theme_stylebox_override("pressed", fp)
	b.pressed.connect(on_press)
	return b

# Glossy coloured disc with a highlight blob — the shared icon plate of the HUD.
func _hub_disc(d: float, base: Color, rim: Color) -> Panel:
	var disc := Panel.new()
	disc.size = Vector2(d, d)
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ds := StyleBoxFlat.new()
	ds.bg_color = base
	ds.set_corner_radius_all(int(d * 0.5))
	ds.border_color = rim
	ds.set_border_width_all(2)
	disc.add_theme_stylebox_override("panel", ds)
	var hl := Panel.new()
	var hd := d * 0.34
	hl.size = Vector2(hd, hd)
	hl.position = Vector2(d * 0.17, d * 0.13)
	hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hs := StyleBoxFlat.new()
	hs.bg_color = Color(1.0, 0.98, 1.0, 0.42)
	hs.set_corner_radius_all(int(hd * 0.5))
	hl.add_theme_stylebox_override("panel", hs)
	disc.add_child(hl)
	return disc

func _hub_title(text: String, top: float) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color.WHITE)
	l.add_theme_constant_override("outline_size", 1)
	l.position = Vector2(HUB_TEXT_X, top)
	l.size = Vector2(HUB_PANEL_W - HUB_PAD - HUB_ACT_W - 16.0 - HUB_TEXT_X, 22.0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _hub_sub(text: String, top: float) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.72, 0.75, 0.95, 0.90))
	l.position = Vector2(HUB_TEXT_X, top)
	l.size = Vector2(HUB_PANEL_W - HUB_PAD - HUB_ACT_W - 16.0 - HUB_TEXT_X, 18.0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# A soft "v" for the pill; flipped by rotating the whole control when open.
func _draw_hub_caret(c: Control) -> void:
	var ctr := c.size * 0.5
	var w := c.size.x * 0.30
	var h := c.size.y * 0.17
	c.draw_polyline(PackedVector2Array([
			ctr + Vector2(-w, -h), ctr + Vector2(0, h), ctr + Vector2(w, -h)]),
		Color(0.88, 0.82, 1.0), 3.0, true)

func _draw_hub_check(c: Control) -> void:
	var s := c.size.x
	c.draw_polyline(PackedVector2Array([
			Vector2(s * 0.14, s * 0.52), Vector2(s * 0.40, s * 0.78), Vector2(s * 0.88, s * 0.20)]),
		Color(0.42, 0.95, 0.62), 3.0, true)

# ---- open / close ----

func _toggle_hub() -> void:
	if _hub_open:
		_close_hub()
	else:
		_open_hub()

func _open_hub() -> void:
	if _hub_open or not _hub_clip:
		return
	_hub_open = true
	# A client left running across UTC midnight would otherwise show yesterday's
	# board; re-check the calendar before painting the rows.
	DailyTasks.refresh()
	_refresh_hub()
	_hub_catcher.visible = true
	_hub_clip.visible = true
	# Cards, the START orb and the account row are built after the catcher, so on
	# their own they would sit on top of it and swallow the dismiss tap. Lift the
	# pair to the front for as long as the dropdown is open (catcher first, so the
	# panel still wins its own taps).
	move_child(_hub_catcher, get_child_count() - 1)
	move_child(_hub_clip, get_child_count() - 1)
	_hub_panel.position.y = HUB_GLOW_M - 8.0
	if _hub_tween and _hub_tween.is_valid():
		_hub_tween.kill()
	_hub_tween = create_tween().set_parallel(true)
	_hub_tween.tween_property(_hub_clip, "size:y", HUB_PANEL_H + HUB_GLOW_M * 2.0, HUB_OPEN_T) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_hub_tween.tween_property(_hub_clip, "modulate:a", 1.0, 0.16)
	_hub_tween.tween_property(_hub_panel, "position:y", HUB_GLOW_M, HUB_OPEN_T) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_hub_tween.tween_property(_hub_caret, "rotation", PI, HUB_OPEN_T) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_animate_task_bar()
	_hub_tick.start()

func _close_hub() -> void:
	if not _hub_open or not _hub_clip:
		return
	_hub_open = false
	_hub_catcher.visible = false
	_hub_tick.stop()
	if _hub_tween and _hub_tween.is_valid():
		_hub_tween.kill()
	_hub_tween = create_tween().set_parallel(true)
	_hub_tween.tween_property(_hub_clip, "size:y", 0.0, HUB_CLOSE_T) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_hub_tween.tween_property(_hub_clip, "modulate:a", 0.0, HUB_CLOSE_T * 0.8)
	_hub_tween.tween_property(_hub_caret, "rotation", 0.0, HUB_CLOSE_T) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_hub_tween.chain().tween_callback(func() -> void:
		if not _hub_open and is_instance_valid(_hub_clip):
			_hub_clip.visible = false)

func _on_hub_catcher_input(ev: InputEvent) -> void:
	var tapped := (ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed) \
		or (ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed)
	if tapped:
		_close_hub()

# ---- state ----

func _refresh_hub() -> void:
	if not _hub_btn or not is_instance_valid(_hub_btn):
		return
	_refresh_claim_status()

	var done := DailyTasks.completed_count()
	var total := DailyTasks.total_count()
	_tasks_count_lbl.text = "%d/%d Completed" % [done, total]
	if _hub_open:
		_animate_task_bar()
	else:
		var track := _tasks_bar_fill.get_parent() as Control
		_tasks_bar_fill.size.x = track.size.x * _task_fraction()
	_tasks_ready_dot.visible = DailyTasks.claimable_count() > 0

	# The pill's dot is a CALL TO ACTION, not a progress read-out: it lights only
	# while there is something the player can collect right now — the login reward
	# or a finished task's coins. Tasks merely left to play are already told by the
	# "2/5 Completed" line and the bar; counting them here left the dot burning all
	# day, so collecting everything on offer never actually cleared it.
	_hub_badge.visible = CoinsManager.can_claim_today() or DailyTasks.claimable_count() > 0

func _refresh_claim_status() -> void:
	if not _claim_status or not is_instance_valid(_claim_status):
		return
	var can := CoinsManager.can_claim_today()
	_claim_btn.visible = can
	_claim_done.visible = not can
	if can:
		var reward := CoinsManager.daily_reward_for_day(CoinsManager.next_claim_day())
		_claim_status.text = "Ready to collect · +%s" % _comma_int(reward)
		_claim_status.add_theme_color_override("font_color", Color(0.98, 0.84, 0.38))
	else:
		_claim_status.text = "Next reward in %s" % _hub_reset_text()
		_claim_status.add_theme_color_override("font_color", Color(0.72, 0.75, 0.95, 0.90))

# Both dailies roll at the same UTC midnight, so the task board's own countdown
# is exactly the wait for the next claim.
func _hub_reset_text() -> String:
	var s := DailyTasks.seconds_until_reset()
	var h := s / 3600
	var m := (s % 3600) / 60
	if h > 0:
		return "%dh %02dm" % [h, m]
	if m > 0:
		return "%dm %02ds" % [m, s % 60]
	return "%ds" % s

func _task_fraction() -> float:
	var total := DailyTasks.total_count()
	if total <= 0:
		return 0.0
	return clampf(float(DailyTasks.completed_count()) / float(total), 0.0, 1.0)

func _animate_task_bar() -> void:
	if not _tasks_bar_fill or not is_instance_valid(_tasks_bar_fill):
		return
	var track := _tasks_bar_fill.get_parent() as Control
	create_tween().tween_property(_tasks_bar_fill, "size:x", track.size.x * _task_fraction(), 0.45) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

# ---- actions ----

# Collect in place. The three beats below are the same ones daily_claim_popup
# runs on its own Claim button — the wallet grant, the streak badges and the
# "Daily Reward" task have to move together wherever the claim is made.
func _on_hub_claim() -> void:
	var reward := CoinsManager.claim_daily()
	if reward <= 0:
		_refresh_hub()
		return
	BadgeManager.note_daily_claimed(CoinsManager.streak_days)
	DailyTasks.note_daily_claimed()
	_hub_claim_flourish(reward)
	_refresh_hub()
	# Tidy the panel away once the receipt has read — the same beat the full claim
	# popup uses, and it clears the corner for the badge toast a streak milestone
	# fires into exactly this spot.
	var tidy := create_tween()
	tidy.tween_interval(1.1)
	tidy.tween_callback(_close_hub)

# A gold "+N" lifts out of the button and fades — enough of a receipt that the
# coin pill's jump upward doesn't come out of nowhere.
func _hub_claim_flourish(reward: int) -> void:
	var fly := Label.new()
	fly.text = "+%s" % _comma_int(reward)
	fly.add_theme_font_size_override("font_size", 22)
	fly.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	fly.add_theme_color_override("font_shadow_color", Color(1.0, 0.70, 0.20, 0.55))
	fly.add_theme_constant_override("shadow_outline_size", 6)
	fly.size = Vector2(HUB_ACT_W, 30.0)
	fly.position = Vector2(HUB_PANEL_W - HUB_PAD - HUB_ACT_W, HUB_ROW_A + 4.0)
	fly.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fly.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hub_panel.add_child(fly)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(fly, "position:y", HUB_ROW_A - 26.0, 0.85) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(fly, "modulate:a", 0.0, 0.85).set_delay(0.25)
	tw.chain().tween_callback(fly.queue_free)

func _open_daily_popup() -> void:
	_close_hub()
	var popup := DailyClaimPopup.new()
	add_child(popup)

func _open_tasks_popup() -> void:
	_close_hub()
	var popup := DailyTasksPopup.new()
	add_child(popup)

# Small clipboard glyph drawn inside the daily-tasks disc: a cream board with a
# dark clip, three ruled lines, and the first two ticked off in green.
func _draw_tasks_icon(c: Control) -> void:
	var s := c.size.x / 34.0                       # glyph authored against a 34px disc
	var board := Rect2(9.0 * s, 8.0 * s, 16.0 * s, 19.0 * s)
	c.draw_rect(Rect2(board.position + Vector2(0, 1.5 * s), board.size), Color(0, 0, 0, 0.25))
	c.draw_rect(board, Color(0.97, 0.98, 1.0))
	c.draw_rect(Rect2(board.position, Vector2(board.size.x, 3.0 * s)), Color(0.85, 0.90, 0.98))
	c.draw_rect(Rect2(13.0 * s, 5.0 * s, 8.0 * s, 4.6 * s), Color(0.16, 0.22, 0.38))
	for i in 3:
		var ly: float = (13.5 + i * 5.0) * s
		var ink := Color(0.58, 0.63, 0.75) if i == 2 else Color(0.30, 0.36, 0.50)
		c.draw_line(Vector2(15.5 * s, ly), Vector2(22.5 * s, ly), ink, maxf(1.0, 1.4 * s))
		if i < 2:
			c.draw_polyline(PackedVector2Array([
					Vector2(11.0 * s, ly - 0.2 * s),
					Vector2(12.4 * s, ly + 1.7 * s),
					Vector2(14.4 * s, ly - 2.6 * s)]),
				Color(0.12, 0.70, 0.40), maxf(1.2, 1.7 * s), true)

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

	# Sign-out and delete both live here now — the two account-level actions, kept
	# together behind the gear rather than loose in the HUD. Guests have neither.
	var show_account := FirebaseManager.is_signed_in()
	const PW := 440.0
	const BASE_PH := 524.0
	const ACCOUNT_SECTION_H := 152.0
	var ph := BASE_PH + (ACCOUNT_SECTION_H if show_account else 0.0)
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
	# Re-opens the ad consent prompt. Required, not optional: a consent the player
	# can't withdraw isn't a valid consent.
	_make_popup_button(panel, "Ad Preferences", Vector2(40, 370), Vector2(PW - 80, 50),
		Color(0.16, 0.18, 0.34), ConsentManager.open_settings)

	# Signed-in-only account zone. Guests have no account to leave or delete.
	# Sign Out reads as a neutral action and Delete Account as the destructive
	# one, so they don't share a colour despite sharing a section.
	var after_y := 432.0
	if show_account:
		_popup_divider(panel, after_y, PW)
		_popup_section_label(panel, "ACCOUNT", after_y + 12, PW)
		_make_popup_button(panel, "Sign Out", Vector2(40, after_y + 32), Vector2(PW - 80, 50),
			Color(0.16, 0.18, 0.34), _confirm_sign_out.bind(overlay))
		_make_popup_button(panel, "Delete Account", Vector2(40, after_y + 90), Vector2(PW - 80, 50),
			Color(0.62, 0.16, 0.20), _confirm_delete_account.bind(overlay))
		after_y += ACCOUNT_SECTION_H

	_make_popup_button(panel, "Close", Vector2(40, after_y), Vector2(PW - 80, 50),
		Color(0.15, 0.6, 0.95), overlay.queue_free)

	var footer := Label.new()
	footer.text = "LUMEO v%s   ·   %s" % [ProjectSettings.get_setting("application/config/version", ""), CONTACT_EMAIL]
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
	OS.shell_open("mailto:%s?subject=LUMEO%%20Feedback" % CONTACT_EMAIL)

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
	# The Remove Ads line is only for the players who actually bought it before the
	# product was delisted — for everyone else it advertises something that no
	# longer exists (see PurchaseManager.REMOVE_ADS_SKU).
	body.text = "This permanently erases your coins, scores, cosmetics and Arena history — it can't be undone."
	if CoinsManager.has_remove_ads:
		body.text += "\n\nYour one-time Remove Ads purchase isn't affected; it's restored automatically if you sign back in."
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
		"Welcome to LUMEO",
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
		"title": "Welcome to LUMEO!",
		"body": "Quick tour, then you're off. Tap Next — skip anytime."})
	if _coin_pill or _hub_btn or not _shop_card.is_empty():
		var body_text := "Spend coins in the Shop to customize your board."
		if _coin_pill or _hub_btn:
			body_text = "Earn coins by playing and from your daily reward, then spend them in the Shop."
		var rect := Rect2()
		if not _shop_card.is_empty():
			rect = (_shop_card["wrap"] as Control).get_global_rect()
		elif _coin_pill:
			rect = _coin_pill.get_global_rect()
		steps.append({"rect": rect, "title": "Coins & Shop", "body": body_text})
	if _hub_btn:
		steps.append({
			"rect": _hub_btn.get_global_rect(),
			"title": "Daily Hub",
			"body": "Your daily reward and a fresh set of small goals live here — tap it to collect both."})
	if not _start_lm.is_empty():
		# Spotlight the visible orb, not the full 300×300 tap target.
		var c: Vector2 = (_start_lm["wrap"] as Control).get_global_rect().get_center()
		steps.append({
			"rect": Rect2(c - Vector2(120, 120), Vector2(240, 240)),
			"title": "Play LUMEO",
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
