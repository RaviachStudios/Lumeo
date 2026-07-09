extends Control

const CoinsPurchasePopup := preload("res://coins_purchase_popup.gd")
const PurchaseConfirmPopup := preload("res://purchase_confirm_popup.gd")

# Shop screen — same visual language as the leaderboards / difficulty / home
# screens (deep-space shader background, slowly rotating orbit of glowing orbs,
# glass back button, glowing header with diamond-underlined subtitle, segmented
# category tabs). The category list starts with just "THEMES" (backgrounds),
# but the tab row is built generically so adding more categories later is just
# data. Inside THEMES, two items: SKYBOUND (blue + clouds, 2000) and INFERNO
# (black + colorful fire, 5000). Each card shows a live preview of the theme
# shader, the price, and a state-aware action button (BUY → EQUIP → EQUIPPED).
#
# Built entirely from Godot nodes + shaders + tweens — no PNG/MP3 assets.

var game_manager: Node

const ORB_COLORS := [
	Color(1.00, 0.82, 0.29),
	Color(0.90, 0.28, 0.30),
	Color(0.55, 0.36, 0.96),
	Color(0.18, 0.78, 0.39),
	Color(0.23, 0.51, 0.96),
]

const GOLD := Color(1.0, 0.85, 0.2)

# Each category entry mirrors the leaderboards TAB_DEFS shape. The `items`
# field lists theme_ids in display order; the shop screen resolves each id
# through CoinsManager.THEMES + BackgroundManager.make_preview.
const CATEGORIES := [
	{
		"key": "themes", "label": "THEMES", "icon": "diamond",
		"accent": Color(1.00, 0.78, 0.22),
		# "default" is included so players can revert after equipping a paid
		# theme; its card is always "owned" and free, so the buy/equip flow
		# handles it without special casing. Ordered by tier: low-value gradients
		# (80), then mid-value illustrated scenes (250-800), then high-value
		# animated scenes (1000-3200).
		"items": ["default",
			"midnight", "indigo", "sunset", "crimson", "slate", "skybound",
			"rainbow", "forest", "desert", "speedway", "reef", "kitty",
			"cosmos", "neon",
			"inferno", "clouds", "aurora", "fairies", "deepspace", "castle"],
	},
	# Wheel colour customization. No flat `items` list — its content (live wheel
	# preview + the three per-part colour tiles) is built specially in
	# _render_category / _build_simon_panel.
	{
		"key": "simon", "label": "SIMON", "icon": "diamond",
		"accent": Color(0.58, 0.46, 1.00),
	},
	# Complete pre-made wheel skins, as their own category. Empty for now (a
	# placeholder panel); ships later. See _build_skins_panel.
	{
		"key": "skins", "label": "SPECIAL SKINS", "icon": "diamond",
		"accent": Color(0.92, 0.45, 0.78),
	},
]

# Display order + pretty labels for the three customizable wheel parts.
const SIMON_TILES := [
	{"cat": "outer_circle", "label": "OUTER RING"},
	{"cat": "inner_circle", "label": "CENTER HUB"},
	{"cat": "level_number", "label": "LEVEL NUMBER"},
]

# Reused shader from leaderboards_screen so the entire app feels like one place.
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
	col *= mix(0.62, 1.0, smoothstep(1.1, 0.25, length(p)));
	COLOR = vec4(col, 1.0);
}
"

const HEADER_W := 720.0
const HEADER_H := 150.0

const TAB_SEP := 28
const TAB_W := 188.0          # wide enough for the longest label ("SPECIAL SKINS")
const TAB_H := 44.0

# Card grid sizing — three columns at the default 1280-wide viewport. Width is
# generous enough that the preview tile shows a recognizable slice of the
# theme; the card itself stays dark-glass styled. Future categories with more
# items will simply wrap onto extra rows.
const CARD_W := 300.0
const CARD_H := 320.0
const CARD_GAP_X := 28.0
const CARD_GAP_Y := 28.0
const PREVIEW_H := 152.0
const GRID_COLS := 3
# Width reserved for the vertical scrollbar so the card grid stays centred while
# the THEMES list scrolls (more themes than fit on screen wrap onto extra rows).
const GRID_SCROLLBAR_W := 14.0
# Gap kept below the grid so the last row never butts against the screen edge.
const GRID_BOTTOM_MARGIN := 24.0

var _bg: ColorRect
var _bg_mat: ShaderMaterial
var _orbit: Node2D
var _ring_glow: Line2D
var _ring_line: Line2D
var _orbs: Array[Node2D] = []
var _orb_tex: Texture2D
var _back: Button
var _header: Control
var _underline: Control
var _coin_pill: Panel
var _coin_lbl: Label
var _coin_plus_btn: Button       # opens the coin-pack purchase popup
var _tab_row: HBoxContainer
var _tabs: Array[Dictionary] = []
var _grid_scroll: ScrollContainer        # wraps _grid so the THEMES list can scroll
var _grid: GridContainer
var _cards_by_id: Dictionary = {}        # theme_id -> { root, btn, btn_label, price_label, badge }
var _current_cat: String = "themes"

# --- loading overlay ---
# Covers the shop while its previews bake + its panels build, so the store is fully
# seamless the moment it appears (same orbiting-orb language as the leaderboards /
# boot loading screens). Lifted by _begin_load once everything is ready.
var _ov: Panel
var _ov_orbit: Node2D
var _ov_orbs: Array[Node2D] = []
var _ov_caption: Label
var _ov_dots_idx := 0
var _loaded := false

# --- SIMON tab ---
const SIMON_ACCENT := Color(0.58, 0.46, 1.00)
var _simon_root: Control                 # SIMON colour panel (built lazily)
var _simon_preview: SimonWheel           # live wheel reflecting the equipped colours
var _simon_tiles_box: Control            # holds the three colour tiles
var _simon_tiles: Dictionary = {}        # category -> {swatch}
var _skins_root: Control                 # SPECIAL SKINS panel (built lazily) — the ScrollContainer
										 # card grid, or a plain Control placeholder when detached
										 # (SKINS_COMING_SOON). Cast to ScrollContainer for scroll ops.
var _skins_grid: GridContainer           # the card grid inside _skins_root
var _skins_by_id: Dictionary = {}        # skin_id -> {root, btn, btn_label, price_label, accent, preview, y}
# Colour popup (opened from a tile):
var _color_popup: Control
var _popup_category: String = ""
var _popup_cards: Dictionary = {}        # color_id -> {btn, price_box, price_label, accent}

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_orb_tex = _make_radial_texture()
	_build_background()
	_build_orbit()
	_build_back()
	_build_header()
	_build_coin_pill()
	_build_tabs()
	_build_grid()
	_layout()
	get_viewport().size_changed.connect(_layout)
	_start_animations()
	# Keep cards + coin pill in sync if the player buys / equips while open.
	CoinsManager.balance_changed.connect(_on_balance_changed)
	CoinsManager.themes_changed.connect(_refresh_cards)
	# Buying / equipping / toggling on the SIMON tab refreshes its tiles and any
	# open colour popup, the same way themes_changed refreshes the theme cards.
	# The same signal is fired on SPECIAL SKINS purchase/equip, so the skin cards
	# follow along too (their EQUIPPED state also flips when the SIMON tab equips
	# a per-part colour, since that switches simon_mode back to MANUAL).
	CoinsManager.simon_changed.connect(_refresh_simon_panel)
	CoinsManager.simon_changed.connect(_refresh_color_cards)
	CoinsManager.simon_changed.connect(_refresh_skin_cards)
	# Equipping from inside the shop flips BackgroundManager.is_themed() under
	# us — without this, the shop's own deep-space bg stays in place over the
	# new global theme (or vanishes to grey when the player re-equips default),
	# and the change only becomes visible after navigating back to home.
	CoinsManager.themes_changed.connect(_sync_local_background)
	# Everything the shop shows is already resident in CoinsManager (loaded on the
	# boot loading screen) — there is nothing to fetch here. The lag came from the
	# VISUALS: the THEMES grid drew ~20 full-screen animated shaders at once, and the
	# other panels' live wheels were built on first tab tap. So we hold a loading
	# overlay and prepare it all up front (bake previews + build panels) before the
	# store appears. See _begin_load.
	_build_loading_overlay()
	_begin_load()

# Shop open sequence, run behind the loading overlay so navigation is seamless the
# moment the veil lifts. No network work — all data is already in CoinsManager.
func _begin_load() -> void:
	_show_loading()
	# Let the loading overlay actually paint BEFORE we block the main thread building the
	# store. Everything below (the 21-card grid + the SIMON/SKINS panels) is constructed
	# synchronously, so without this yield the veil only appears after that freeze — the
	# shop button would feel unresponsive. Two frames guarantees the overlay has rendered,
	# so the loading screen shows the instant the shop opens.
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var theme_items: Array = []
	for c in CATEGORIES:
		if c["key"] == "themes":
			theme_items = c.get("items", [])
			break
	# Pre-compile every THEMES preview shader + each SKINS card's background, one per
	# frame, so no tile hitches on a first-draw shader compile. Previews stay fully
	# LIVE/animated — what keeps scrolling smooth is that the shop only lets the tiles
	# actually IN the visible scroll band keep drawing (see _update_preview_visibility),
	# so at most a handful of shaders run at once instead of all ~20.
	BackgroundManager.prewarm_previews(theme_items)
	# Skip the skin-preview prewarm entirely while the SPECIAL SKINS tab is detached —
	# the placeholder renders no wheels, so there's nothing to warm.
	if not SKINS_COMING_SOON:
		var skin_ids: Array[String] = []
		for d in SKIN_DEFS:
			skin_ids.append(String(d["id"]))
		BackgroundManager.prewarm_skin_previews(skin_ids)
	# Render the THEMES grid and build the SIMON + SKINS panels while the overlay still
	# hides the construction. These are the two heaviest bursts in the shop, so both run
	# in INCREMENTAL mode — yielding frames as they build — so the loading overlay's orbit
	# tween keeps ticking instead of freezing the moment the shop opens.
	await _render_category(_current_cat, true)
	if not is_inside_tree():
		return
	await _prebuild_panels()
	if not is_inside_tree():
		return
	# Give the SPECIAL SKINS preview wheels a couple of frames to render once behind the veil
	# (paying the first-draw shader upload during loading — see _prebuild_panels), then idle
	# the hidden wheels since we open on THEMES. The first switch to that tab then just kicks
	# a redraw of the already-built wheels instead of building/first-drawing them.
	# This MUST happen before the prewarm wait below: an animated skin's wheel renders
	# UPDATE_ALWAYS while unpaused, so leaving all 7 live 3D viewports drawing every frame
	# for the whole shader-compile wait is what made the loading orbit animation stutter.
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree():
		return
	if _current_cat != "skins":
		_set_skins_preview_paused(true)
	# Hold the veil until every preview shader has finished compiling. With the skin
	# wheels now idled, these frames are cheap, so the orbit animation stays smooth
	# however long the compile queue takes to drain.
	while BackgroundManager.is_prewarming() and is_inside_tree():
		await get_tree().process_frame
	if not is_inside_tree():
		return
	_loaded = true
	_hide_loading()
	_update_preview_visibility()

# Builds the non-default category panels ahead of time so switching to them is
# instant. Each builder add_child()s its root; SIMON is hidden immediately, but the
# SKINS panel is left VISIBLE (under the veil) so its 3D preview wheels actually render
# — _begin_load hides + idles it once that render has happened. Yields a frame between
# the two panels so the loading overlay's animation keeps ticking during the build.
# Safe to call once — guarded by the null checks.
func _prebuild_panels() -> void:
	if not is_inside_tree():
		return
	if _simon_root == null:
		_build_simon_panel()
		_simon_root.visible = false
	await get_tree().process_frame
	if not is_inside_tree():
		return
	if _skins_root == null:
		await _build_skins_panel(true)
		if not is_inside_tree():
			return
		_skins_root.visible = false
	# Keep the panel hidden but leave its preview wheels UNPAUSED for now, so each renders its
	# 3D scene once behind the veil (a SubViewport renders on its own render target regardless
	# of whether its container is visible). That pays the first-draw shader upload during
	# loading instead of on the first tab switch. _begin_load idles them after that window.
	_set_skins_preview_paused(false)
	_layout()

# ---------------- background ----------------

func _build_background() -> void:
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

func _sync_local_background() -> void:
	var themed := BackgroundManager.is_themed()
	if themed and _bg:
		_bg.queue_free()
		_bg = null
		_bg_mat = null
	elif not themed and not _bg:
		_build_background()
		# Built after the rest of the UI in this case — push it under everything.
		move_child(_bg, 0)
		_layout()

# ---------------- orbit ----------------

func _build_orbit() -> void:
	_orbit = Node2D.new()
	add_child(_orbit)
	_ring_glow = _make_ring(7.0, Color(0.45, 0.42, 1.0, 0.07))
	_orbit.add_child(_ring_glow)
	_ring_line = _make_ring(2.0, Color(0.60, 0.58, 1.0, 0.18))
	_orbit.add_child(_ring_line)
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

# ---------------- back button ----------------

func _build_back() -> void:
	_back = Button.new()
	_back.text = "← Back"
	_back.size = Vector2(132, 46)
	_back.focus_mode = Control.FOCUS_NONE
	_back.add_theme_font_size_override("font_size", 18)
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.07, 0.10, 0.26, 0.7)
	s.set_corner_radius_all(23)
	s.border_color = Color(0.35, 0.5, 1.0, 0.5)
	s.set_border_width_all(1)
	s.shadow_color = Color(0.25, 0.4, 1.0, 0.25)
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

# ---------------- header ----------------

func _build_header() -> void:
	_header = Control.new()
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.custom_minimum_size = Vector2(HEADER_W, HEADER_H)
	_header.size = Vector2(HEADER_W, HEADER_H)
	add_child(_header)

	# Big gold coin glyph as the shop's mascot, centered above the title.
	var coin := _make_big_coin(34.0)
	coin.position = Vector2(HEADER_W * 0.5, 24)
	_header.add_child(coin)

	var title := Label.new()
	title.text = "THE SHOP"
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_color_override("font_outline_color", Color(1, 1, 1, 1))
	title.add_theme_constant_override("outline_size", 2)
	title.add_theme_color_override("font_shadow_color", Color(1.00, 0.78, 0.22, 0.45))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 4)
	title.add_theme_constant_override("shadow_outline_size", 9)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.offset_top = 56
	title.offset_bottom = -36
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.add_child(title)

	_underline = Control.new()
	_underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_underline.size = Vector2(420, 14)
	_underline.position = Vector2((HEADER_W - 420) * 0.5, HEADER_H - 24)
	_header.add_child(_underline)
	var ul_line_l := ColorRect.new()
	ul_line_l.color = Color(1.00, 0.78, 0.22, 0.55)
	ul_line_l.size = Vector2(190, 2)
	ul_line_l.position = Vector2(0, 6)
	ul_line_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_underline.add_child(ul_line_l)
	var ul_line_r := ColorRect.new()
	ul_line_r.color = Color(1.00, 0.78, 0.22, 0.55)
	ul_line_r.size = Vector2(190, 2)
	ul_line_r.position = Vector2(230, 6)
	ul_line_r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_underline.add_child(ul_line_r)
	var diamond := _make_diamond(11.0, Color(1.0, 0.92, 0.55))
	diamond.position = Vector2(210, 7)
	_underline.add_child(diamond)

# Bigger version of the in-game HUD coin: gold disc + bright ring + "$" glyph,
# with a soft golden halo for the header.
func _make_big_coin(d: float) -> Node2D:
	var n := Node2D.new()
	var halo := Sprite2D.new()
	halo.texture = _orb_tex
	halo.modulate = Color(1.0, 0.78, 0.22, 0.55)
	halo.scale = Vector2.ONE * (d * 3.0 / 128.0)
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	halo.material = add_mat
	n.add_child(halo)
	# Outer light rim first (drawn beneath), then the gold disc on top — the
	# difference between the two radii reads as the metallic rim.
	var rim := Polygon2D.new()
	rim.polygon = _circle_poly(d * 0.92, 28)
	rim.color = Color(1.0, 0.92, 0.55, 0.85)
	n.add_child(rim)
	var disc := Polygon2D.new()
	disc.polygon = _circle_poly(d * 0.78, 28)
	disc.color = Color(1.0, 0.78, 0.20)
	n.add_child(disc)
	var glyph := Label.new()
	glyph.text = "$"
	glyph.add_theme_font_size_override("font_size", int(d * 1.15))
	glyph.add_theme_color_override("font_color", Color(0.45, 0.30, 0.05))
	glyph.position = Vector2(-d, -d)
	glyph.size = Vector2(d * 2.0, d * 2.0)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	n.add_child(glyph)
	return n

func _make_diamond(s: float, col: Color) -> Node2D:
	var n := Node2D.new()
	var halo := Sprite2D.new()
	halo.texture = _orb_tex
	halo.modulate = Color(col.r, col.g, col.b, 0.5)
	halo.scale = Vector2.ONE * (s * 3.0 / 128.0)
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	halo.material = add_mat
	n.add_child(halo)
	var d := Polygon2D.new()
	d.polygon = PackedVector2Array([
		Vector2(0, -s * 0.55), Vector2(s * 0.55, 0),
		Vector2(0,  s * 0.55), Vector2(-s * 0.55, 0)
	])
	d.color = col
	n.add_child(d)
	return n

func _circle_poly(r: float, n: int) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in n:
		var a: float = TAU * float(i) / n
		p.append(Vector2(cos(a), sin(a)) * r)
	return p

# ---------------- coin balance pill ----------------

# Large gold pill on the upper-right: live balance, instantly updates on buy /
# claim / award. Per spec: "show it in the shop larger" than the home screen.
func _build_coin_pill() -> void:
	const PW := 220.0
	const PH := 62.0
	_coin_pill = Panel.new()
	_coin_pill.size = Vector2(PW, PH)
	_coin_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.06, 0.07, 0.18, 0.88)
	st.set_corner_radius_all(int(PH * 0.5))
	st.border_color = Color(1.0, 0.78, 0.22, 0.85)
	st.set_border_width_all(2)
	st.shadow_color = Color(1.0, 0.78, 0.22, 0.40)
	st.shadow_size = 14
	_coin_pill.add_theme_stylebox_override("panel", st)
	add_child(_coin_pill)

	var coin := _make_big_coin(20.0)
	coin.position = Vector2(28, PH * 0.5)
	_coin_pill.add_child(coin)

	_coin_lbl = Label.new()
	_coin_lbl.text = str(CoinsManager.balance)
	_coin_lbl.add_theme_font_size_override("font_size", 32)
	_coin_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45))
	_coin_lbl.position = Vector2(56, 0)
	_coin_lbl.size = Vector2(PW - 70, PH)
	_coin_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_coin_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_coin_pill.add_child(_coin_lbl)

	_build_coin_plus_button(PH)

# Gold circular "+" button that opens the coin-pack purchase popup. Larger
# than the home-screen variant because the shop's coin pill is itself larger;
# positioned to the LEFT of the pill in _layout (the pill anchors top-right).
func _build_coin_plus_button(pill_h: float) -> void:
	var d := 48.0
	_coin_plus_btn = Button.new()
	_coin_plus_btn.text = "+"
	_coin_plus_btn.size = Vector2(d, d)
	_coin_plus_btn.add_theme_font_size_override("font_size", 34)
	_coin_plus_btn.focus_mode = Control.FOCUS_NONE
	var s := StyleBoxFlat.new()
	s.bg_color = Color(1.0, 0.78, 0.20)
	s.set_corner_radius_all(int(d * 0.5))
	s.border_color = Color(1.0, 0.92, 0.55)
	s.set_border_width_all(2)
	s.shadow_color = Color(1.0, 0.78, 0.22, 0.55)
	s.shadow_size = 12
	_coin_plus_btn.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = Color(1.0, 0.88, 0.35)
	_coin_plus_btn.add_theme_stylebox_override("hover", sh)
	var sp := s.duplicate() as StyleBoxFlat
	sp.bg_color = Color(0.85, 0.62, 0.10)
	_coin_plus_btn.add_theme_stylebox_override("pressed", sp)
	_coin_plus_btn.add_theme_color_override("font_color", Color(0.30, 0.18, 0.0))
	_coin_plus_btn.add_theme_color_override("font_hover_color", Color(0.18, 0.10, 0.0))
	_coin_plus_btn.pressed.connect(_open_coins_popup)
	# Y position is shared with the pill (centered vertically); X is set in _layout.
	_coin_plus_btn.position = Vector2(0, (pill_h - d) * 0.5)
	add_child(_coin_plus_btn)

func _open_coins_popup() -> void:
	var popup := CoinsPurchasePopup.new()
	add_child(popup)

func _on_balance_changed(new_balance: int) -> void:
	if _coin_lbl:
		_coin_lbl.text = str(new_balance)
	# Card affordability changes with balance too.
	_refresh_cards()
	_refresh_color_cards()
	_refresh_skin_cards()

# ---------------- category tabs ----------------

func _build_tabs() -> void:
	_tab_row = HBoxContainer.new()
	_tab_row.add_theme_constant_override("separation", TAB_SEP)
	add_child(_tab_row)
	for c in CATEGORIES:
		_tabs.append(_make_tab(c))
	_refresh_tab_styles()

func _make_tab(def: Dictionary) -> Dictionary:
	var accent: Color = def["accent"]
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(TAB_W, TAB_H)
	wrap.size = Vector2(TAB_W, TAB_H)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var btn := Button.new()
	btn.size = Vector2(TAB_W, TAB_H)
	btn.pivot_offset = Vector2(TAB_W, TAB_H) * 0.5
	btn.focus_mode = Control.FOCUS_NONE
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.07, 0.10, 0.26, 0.75)
	s.set_corner_radius_all(int(TAB_H * 0.5))
	s.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	s.set_border_width_all(1)
	s.shadow_color = Color(accent.r, accent.g, accent.b, 0.20)
	s.shadow_size = 8
	for st_name in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(st_name, s)
	btn.add_theme_color_override("font_color", Color(0.74, 0.80, 1.0))
	wrap.add_child(btn)

	# Tiny diamond icon, same convention as leaderboards' EASY/MOD/HARD tabs.
	var icon := Panel.new()
	var dia := 26.0
	icon.size = Vector2(dia, dia)
	icon.position = Vector2(12, (TAB_H - dia) * 0.5)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := StyleBoxFlat.new()
	var icbg := accent.darkened(0.2); icbg.a = 0.30
	ic.bg_color = icbg
	ic.set_corner_radius_all(int(dia * 0.5))
	ic.border_color = accent.lightened(0.2)
	ic.set_border_width_all(1)
	icon.add_theme_stylebox_override("panel", ic)
	btn.add_child(icon)
	var sym := _make_diamond(dia * 0.42, accent.lightened(0.45))
	sym.position = Vector2(dia * 0.5, dia * 0.5)
	icon.add_child(sym)

	var lbl := Label.new()
	lbl.text = def["label"]
	lbl.add_theme_font_size_override("font_size", 17)
	lbl.add_theme_color_override("font_color", accent.lightened(0.15))
	lbl.position = Vector2(12 + dia + 6, 0)
	lbl.size = Vector2(TAB_W - (12 + dia + 6) - 12, TAB_H)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(lbl)

	btn.pressed.connect(func() -> void: _on_tab(def["key"]))
	_tab_row.add_child(wrap)
	return {"wrap": wrap, "btn": btn, "stylebox": s, "def": def, "label": lbl}

func _refresh_tab_styles() -> void:
	for t in _tabs:
		var def: Dictionary = t["def"]
		var accent: Color = def["accent"]
		var active: bool = def["key"] == _current_cat
		var s: StyleBoxFlat = t["stylebox"]
		s.border_color = Color(accent.r, accent.g, accent.b, 1.0 if active else 0.55)
		s.set_border_width_all(2 if active else 1)
		s.shadow_color = Color(accent.r, accent.g, accent.b, 0.45 if active else 0.20)
		s.shadow_size = 14 if active else 8
		var lbl: Label = t["label"]
		lbl.add_theme_color_override("font_color",
			accent.lightened(0.35) if active else accent.lightened(0.05))
		create_tween().tween_property(t["btn"], "scale",
			Vector2.ONE * (1.05 if active else 1.0), 0.18) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_tab(key: String) -> void:
	if key == _current_cat:
		return
	_current_cat = key
	_refresh_tab_styles()
	_render_category(_current_cat)

# ---------------- item grid ----------------

func _build_grid() -> void:
	# The grid lives inside a ScrollContainer so categories with more cards than
	# fit on screen (THEMES) scroll vertically instead of overflowing the viewport.
	_grid_scroll = ScrollContainer.new()
	_grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_grid_scroll)
	# As the grid scrolls, keep only the tiles in view drawing their live shader.
	_grid_scroll.get_v_scroll_bar().value_changed.connect(
		func(_v: float) -> void: _update_preview_visibility())
	_grid = GridContainer.new()
	_grid.columns = GRID_COLS
	_grid.add_theme_constant_override("h_separation", int(CARD_GAP_X))
	_grid.add_theme_constant_override("v_separation", int(CARD_GAP_Y))
	_grid_scroll.add_child(_grid)

# `incremental` (used only during the initial load, behind the veil) yields a frame every
# few theme cards so the loading overlay's animation keeps ticking instead of freezing while
# all ~21 cards + their preview shaders build in one synchronous burst. Tab switches call it
# without the flag so the grid still swaps in a single frame.
func _render_category(key: String, incremental := false) -> void:
	# THEMES uses the card grid; SIMON and SPECIAL SKINS each have a bespoke panel.
	# Hide them all, then show the one for this category.
	_grid_scroll.visible = false
	if _simon_root:
		_simon_root.visible = false
	if _skins_root:
		_skins_root.visible = false
	# Any SPECIAL SKINS preview wheels idle while their tab is hidden; the skins branch
	# below resumes them when that tab is the one being shown.
	_set_skins_preview_paused(true)

	if key == "simon":
		if _simon_root == null:
			_build_simon_panel()
		_simon_root.visible = true
		_refresh_simon_panel()
		_layout()
		return
	if key == "skins":
		if _skins_root == null:
			_build_skins_panel()
		_skins_root.visible = true
		# The detached placeholder is a plain Control (no scroll_vertical); the real
		# panel is a ScrollContainer that we reset to the top on show.
		if not SKINS_COMING_SOON:
			(_skins_root as ScrollContainer).scroll_vertical = 0
		_refresh_skin_cards()
		_layout()
		# Resume only the wheels actually in the scroll band — not a blanket wake of all 7.
		# The skins are static and were already applied at build time, so there's no need to
		# re-apply them here; that per-switch rebuild of every wheel's materials (plus waking
		# all 7 viewports at once) was the tab-switch lag.
		_update_skin_preview_visibility()
		return

	_grid_scroll.visible = true
	_grid_scroll.scroll_vertical = 0
	for c in _grid.get_children():
		c.queue_free()
	_cards_by_id.clear()
	var cat: Dictionary = {}
	for c in CATEGORIES:
		if c["key"] == key:
			cat = c
			break
	if cat.is_empty():
		return
	var idx := 0
	for theme_id in cat.get("items", []):
		var card := _make_card(theme_id, cat["accent"])
		# Grid-local top of this card's row, so _update_preview_visibility can tell
		# which tiles are within the scroll band without waiting for a layout pass.
		card["y"] = float(int(idx / GRID_COLS)) * (CARD_H + CARD_GAP_Y)
		_grid.add_child(card["root"])
		_cards_by_id[theme_id] = card
		idx += 1
		# During the incremental load, keep each preview hidden as it's added so we never
		# animate all ~21 shaders at once behind the veil, and breathe every few cards so
		# the overlay animation keeps running. _update_preview_visibility re-enables the
		# on-screen band at the end.
		if incremental:
			var pv: Control = card.get("preview")
			if pv:
				pv.visible = false
			if idx % 4 == 0:
				await get_tree().process_frame
				if not is_inside_tree():
					return
	_refresh_cards()
	_update_preview_visibility()

# A centred "coin + price" block to drop inside a buy button, so the button
# itself shows the cost (no separate price row, no "need X" copy). Returns the
# container plus its number label so callers can recolour the price per button
# state (dark on the gold affordable button, dim on the greyed-out one).
func _make_price_content(price: int, coin_d: float, font_size: int, btn_h: float) -> Dictionary:
	var box := HBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var coin_wrap := Control.new()
	coin_wrap.custom_minimum_size = Vector2(coin_d * 2.0, btn_h)
	coin_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var coin := _make_big_coin(coin_d)
	coin.position = Vector2(coin_d, btn_h * 0.5)
	coin_wrap.add_child(coin)
	box.add_child(coin_wrap)
	var lbl := Label.new()
	lbl.text = str(price)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(lbl)
	return {"box": box, "label": lbl}

func _make_card(theme_id: String, accent: Color) -> Dictionary:
	var meta: Dictionary = CoinsManager.THEMES.get(theme_id, {})
	var pretty_name: String = meta.get("name", theme_id.capitalize())

	var root := Panel.new()
	root.custom_minimum_size = Vector2(CARD_W, CARD_H)
	root.size = Vector2(CARD_W, CARD_H)
	# PASS (not the Panel default STOP) so a touch starting on the card body still
	# reaches the ScrollContainer as a drag — otherwise the panel swallows it and
	# the list only scrolls from the gaps between cards. The buy/equip button keeps
	# its default STOP so taps on it still register.
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.06, 0.08, 0.20, 0.92)
	cs.set_corner_radius_all(20)
	cs.border_color = Color(accent.r, accent.g, accent.b, 0.7)
	cs.set_border_width_all(2)
	cs.shadow_color = Color(accent.r, accent.g, accent.b, 0.30)
	cs.shadow_size = 14
	root.add_theme_stylebox_override("panel", cs)

	# Preview: live shader render of the theme, inset with rounded corners via
	# a clip Panel (Godot can't directly round a ColorRect, but ColorRect inside
	# a clip_contents Panel gets the same effect).
	var clip := Panel.new()
	clip.size = Vector2(CARD_W - 32, PREVIEW_H)
	clip.position = Vector2(16, 16)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var clip_st := StyleBoxFlat.new()
	clip_st.bg_color = Color(0.04, 0.05, 0.14)
	clip_st.set_corner_radius_all(14)
	clip_st.border_color = Color(1, 1, 1, 0.08)
	clip_st.set_border_width_all(1)
	clip.add_theme_stylebox_override("panel", clip_st)
	root.add_child(clip)
	var preview := BackgroundManager.make_preview(theme_id, clip.size)
	preview.position = Vector2.ZERO
	clip.add_child(preview)

	# Layout below the preview, from top down:
	#   16  preview                                  (PREVIEW_H tall)
	#   ↓   name                                     (28 tall)
	#   ↓   action button                            (48 tall, bottom-anchored).
	#       When unowned the button shows the price (coin + number); owned/equipped
	#       it shows EQUIP / EQUIPPED instead.
	var below_preview := 16 + PREVIEW_H + 12.0

	var name_lbl := Label.new()
	name_lbl.text = pretty_name.to_upper()
	name_lbl.add_theme_font_size_override("font_size", 22)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	name_lbl.position = Vector2(16, below_preview)
	name_lbl.size = Vector2(CARD_W - 32, 28)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(name_lbl)

	var btn := Button.new()
	btn.size = Vector2(CARD_W - 32, 48)
	btn.position = Vector2(16, CARD_H - 48 - 16)
	btn.add_theme_font_size_override("font_size", 19)
	btn.focus_mode = Control.FOCUS_NONE
	root.add_child(btn)

	# Price block lives inside the button; toggled off once the theme is owned.
	var price := _make_price_content(CoinsManager.theme_price(theme_id), 12.0, 20, 48.0)
	btn.add_child(price["box"])

	btn.pressed.connect(func() -> void: _on_action(theme_id))
	return {
		"root": root, "btn": btn, "price_box": price["box"],
		"price_label": price["label"], "accent": accent, "preview": preview,
	}

# Apply BUY / EQUIP / EQUIPPED visual state to all cards in the current grid.
func _refresh_cards() -> void:
	for theme_id in _cards_by_id:
		var c: Dictionary = _cards_by_id[theme_id]
		_apply_card_state(theme_id, c)

# Keep only the preview tiles within (or just outside) the visible scroll band drawing
# their live shader; hide the rest. Previews stay fully animated — we simply don't pay
# to render the ones you can't see, so the grid never draws all ~20 animated shaders at
# once (that simultaneous cost was the scroll/tab lag). Recomputed on scroll + re-render.
func _update_preview_visibility() -> void:
	if _grid_scroll == null or not _grid_scroll.visible:
		return
	var sv := float(_grid_scroll.scroll_vertical)
	var vh := _grid_scroll.size.y
	var margin := CARD_H * 0.6      # begin animating a bit before a tile scrolls in
	for theme_id in _cards_by_id:
		var c: Dictionary = _cards_by_id[theme_id]
		var preview: Control = c.get("preview")
		if preview == null:
			continue
		var y: float = c.get("y", 0.0)
		var on := (y + CARD_H > sv - margin) and (y < sv + vh + margin)
		if preview.visible != on:
			preview.visible = on

func _apply_card_state(theme_id: String, c: Dictionary) -> void:
	var btn: Button = c["btn"]
	var accent: Color = c["accent"]
	var price_box: Control = c["price_box"]
	var price_label: Label = c["price_label"]
	var owned := CoinsManager.owns(theme_id)
	# In SKIN mode the skin's own world overrides every theme, so no theme reads as
	# equipped — it shows EQUIP instead (tapping it drops the skin and re-applies
	# the theme as the background).
	var equipped := CoinsManager.is_simon_manual() and CoinsManager.selected_theme == theme_id
	var affordable := CoinsManager.can_afford(theme_id)

	# Unowned cards show the price block in the button; owned ones show EQUIP/EQUIPPED.
	price_box.visible = not owned
	btn.disabled = false

	var label_text := ""
	var bg_col: Color
	var fg_col := Color.WHITE
	if equipped:
		label_text = "EQUIPPED"
		bg_col = Color(0.18, 0.45, 0.28)
		btn.disabled = true
	elif owned:
		label_text = "EQUIP"
		bg_col = Color(0.20, 0.55, 0.95)
	elif affordable:
		bg_col = Color(1.00, 0.66, 0.10)
		fg_col = Color(0.18, 0.10, 0.0)
	else:
		bg_col = Color(0.30, 0.30, 0.40)
		fg_col = Color(0.85, 0.85, 0.95, 0.7)
		btn.disabled = true

	price_label.add_theme_color_override("font_color", fg_col)
	btn.text = label_text
	var s := StyleBoxFlat.new()
	s.bg_color = bg_col
	s.set_corner_radius_all(14)
	s.border_color = accent.lightened(0.2) if equipped else bg_col.lightened(0.15)
	s.set_border_width_all(2 if equipped else 0)
	btn.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = bg_col.lightened(0.12)
	btn.add_theme_stylebox_override("hover", sh)
	var sp := s.duplicate() as StyleBoxFlat
	sp.bg_color = bg_col.darkened(0.20)
	btn.add_theme_stylebox_override("pressed", sp)
	var sd := s.duplicate() as StyleBoxFlat
	sd.bg_color = bg_col.darkened(0.05)
	btn.add_theme_stylebox_override("disabled", sd)
	btn.add_theme_color_override("font_color", fg_col)
	btn.add_theme_color_override("font_disabled_color", fg_col)

func _on_action(theme_id: String) -> void:
	if CoinsManager.owns(theme_id):
		CoinsManager.select_theme(theme_id)
		return
	# Not yet owned. Confirm before spending — the BUY button is right under
	# the player's thumb on the card and tapping it used to charge instantly.
	if not CoinsManager.can_afford(theme_id):
		return
	var meta: Dictionary = CoinsManager.THEMES.get(theme_id, {})
	_confirm_purchase(
		String(meta.get("name", theme_id.capitalize())),
		CoinsManager.theme_price(theme_id),
		func() -> void:
			if CoinsManager.purchase_theme(theme_id):
				# Auto-equip a freshly purchased theme so the player sees their
				# reward immediately the next time they leave the shop.
				CoinsManager.select_theme(theme_id)
	)

# Shared confirm-then-spend gate for shop purchases. `on_confirmed` runs only
# if the player taps BUY; backdrop / cancel / X just close the dialog.
func _confirm_purchase(item_name: String, price: int, on_confirmed: Callable) -> void:
	var popup := PurchaseConfirmPopup.new()
	popup.item_name = item_name
	popup.price = price
	popup.confirmed.connect(on_confirmed)
	add_child(popup)

# ---------------- SIMON panel ----------------

const SIMON_PANEL_W := 700.0
const SIMON_TILE_W := 210.0
const SIMON_TILE_H := 196.0
const SIMON_TILE_GAP := 34.0
const SIMON_SWATCH := 96.0
const PREVIEW_WHEEL := 168.0          # displayed size of the live wheel preview
# SimonWheel's centre overlay (numeral + status dot) is sized in fixed pixels tuned
# for the large in-game wheel, so we render the preview at this larger logical size
# and scale it down — keeping the numeral/hub proportions correct at preview scale.
const PREVIEW_WHEEL_LOGICAL := 340.0

# Segment colours for the preview wheel — a fixed slice of game.gd's BUTTON_COLORS
# (the preview only demonstrates the equipped rim/hub/numeral tints, so the button
# colours themselves are arbitrary but should look like a real round).
const PREVIEW_COLORS := [
	Color(0.9, 0.15, 0.15), Color(0.15, 0.8, 0.15), Color(0.15, 0.35, 0.95),
	Color(0.95, 0.85, 0.1), Color(0.95, 0.5, 0.1),
]

func _build_simon_panel() -> void:
	_simon_root = Control.new()
	_simon_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_simon_root.custom_minimum_size = Vector2(SIMON_PANEL_W, 400)
	_simon_root.size = Vector2(SIMON_PANEL_W, 400)
	add_child(_simon_root)

	# Live wheel preview — equipping a colour is itself what the wheel wears, and
	# this preview shows that look in real time. Updated by _refresh_simon_preview.
	_simon_preview = SimonWheel.new()
	_simon_preview.size = Vector2(PREVIEW_WHEEL_LOGICAL, PREVIEW_WHEEL_LOGICAL)
	var pscale := PREVIEW_WHEEL / PREVIEW_WHEEL_LOGICAL
	_simon_preview.scale = Vector2(pscale, pscale)   # scales toward the top-left pivot
	_simon_preview.position = Vector2((SIMON_PANEL_W - PREVIEW_WHEEL) * 0.5, 0)
	_simon_root.add_child(_simon_preview)
	_simon_preview.configure(5, PREVIEW_COLORS)
	_simon_preview.set_level(1)
	# The numeral overlay is fixed-pixel (tuned for the large in-game wheel), so on
	# this small preview it reads too big and the status dot is meaningless here —
	# shrink the numeral to match the in-game proportion and drop the dot.
	_simon_preview.set_overlay_compact(0.52, false)

	# The three per-part colour tiles, directly below the preview.
	var content_y := PREVIEW_WHEEL + 30.0
	_simon_tiles_box = Control.new()
	_simon_tiles_box.position = Vector2(0, content_y)
	_simon_tiles_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_simon_root.add_child(_simon_tiles_box)
	var tiles_total := SIMON_TILES.size() * SIMON_TILE_W + (SIMON_TILES.size() - 1) * SIMON_TILE_GAP
	var tx := (SIMON_PANEL_W - tiles_total) * 0.5
	for i in SIMON_TILES.size():
		var def: Dictionary = SIMON_TILES[i]
		var tile := _make_simon_tile(def["cat"], def["label"], Vector2(tx + i * (SIMON_TILE_W + SIMON_TILE_GAP), 0))
		_simon_tiles_box.add_child(tile)

# SPECIAL SKINS panel — one tall card per complete skin (currently only Inferno).
# Each card hosts a live SimonWheel preview with the skin's bespoke palette and
# overlay (e.g. the inferno flames) actually rendering, so what you see in the
# shop is exactly what you get on the gameplay screen.
const SKIN_ACCENT := Color(0.92, 0.45, 0.78)
const SKIN_CARD_W := 360.0
const SKIN_CARD_H := 470.0
const SKIN_PREVIEW := 260.0
const SKIN_PREVIEW_LOGICAL := 380.0   # render the live wheel at this logical size
									   # then scale down (same trick as the SIMON
									   # tab's preview — keeps the inner numeral/hub
									   # proportions correct at preview scale).
const SKIN_CARD_GAP := 32.0
# The SPECIAL SKINS cards live in a scrolling grid (same as the THEMES tab) so more
# skins than fit on screen wrap onto extra rows instead of running off the side.
const SKIN_GRID_COLS := 3
const SKIN_GRID_SCROLLBAR_W := 14.0

# The current skin set isn't ready to ship, so the SPECIAL SKINS tab is DETACHED
# for this release: instead of the card grid it shows a "To be continued" placeholder.
# Nothing below is deleted — the whole skin card / preview pipeline stays intact and
# the tab comes back the moment this flips to false (also re-enables the skin-preview
# prewarm in _begin_load). See _build_skins_panel / _build_skins_coming_soon.
const SKINS_COMING_SOON := true

# Display order + pretty labels for the skins shown in the SPECIAL SKINS tab.
# Adding a new skin = an entry here + a catalog entry in CoinsManager.SIMON_SKINS
# + the corresponding skin path in SimonWheel. A `blurb` field is optional; when
# absent the card renders just the title (used for VOLCANO).
const SKIN_DEFS := [
	{"id": "inferno", "label": "VOLCANO"},
	{"id": "racing", "label": "REDLINE", "blurb": "Floor it."},
	{"id": "submarine", "label": "NAUTILUS", "blurb": "Dive deep."},
	{"id": "arcade", "label": "ARCADE", "blurb": "Insert coin."},
	{"id": "pirate", "label": "BUCCANEER", "blurb": "Batten the hatches."},
	{"id": "casino", "label": "JACKPOT", "blurb": "Place your bets."},
	{"id": "phantom", "label": "PHANTOM", "blurb": "Something's watching."},
]

# `incremental` (initial load, behind the veil) yields a frame between skin cards so the
# loading overlay keeps animating instead of freezing while all 7 live 3D preview wheels —
# the single heaviest build in the shop — are constructed in one synchronous burst.
func _build_skins_panel(incremental := false) -> void:
	# Detached for this release — show the placeholder instead of the card grid.
	if SKINS_COMING_SOON:
		_build_skins_coming_soon()
		return
	# A vertically scrolling card grid — same structure as the THEMES tab — so the
	# skins wrap onto extra rows and scroll instead of overflowing horizontally.
	# (_skins_root is typed Control so it can also hold the detached placeholder, so
	# use a locally-typed ScrollContainer for the scroll-specific setup here.)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_skins_root = scroll
	add_child(_skins_root)
	# As the list scrolls, idle the live preview wheels that scroll out of view.
	scroll.get_v_scroll_bar().value_changed.connect(
		func(_v: float) -> void: _update_skin_preview_visibility())
	_skins_grid = GridContainer.new()
	_skins_grid.columns = SKIN_GRID_COLS
	_skins_grid.add_theme_constant_override("h_separation", int(SKIN_CARD_GAP))
	_skins_grid.add_theme_constant_override("v_separation", int(SKIN_CARD_GAP))
	_skins_root.add_child(_skins_grid)
	_skins_by_id.clear()
	for i in SKIN_DEFS.size():
		var def: Dictionary = SKIN_DEFS[i]
		var card := _make_skin_card(def)
		# Grid-local top of this card's row, so _update_skin_preview_visibility can
		# tell which cards are within the scroll band (mirrors the THEMES grid).
		card["y"] = float(int(i / SKIN_GRID_COLS)) * (SKIN_CARD_H + SKIN_CARD_GAP)
		_skins_grid.add_child(card["root"])
		# Configure the preview wheel now that its card is IN THE TREE — off-tree
		# configuration mis-sized the SubViewport and mis-aimed the camera.
		var wheel: SimonWheel = card["preview"]
		wheel.configure(5, PREVIEW_COLORS)
		wheel.set_level(1)
		wheel.set_overlay_compact(0.52, false)
		wheel.apply_skin(null, null, null, String(def["id"]))
		_skins_by_id[def["id"]] = card
		if incremental:
			await get_tree().process_frame
			if not is_inside_tree():
				return
	_refresh_skin_cards()

# Placeholder shown while the SPECIAL SKINS tab is detached (SKINS_COMING_SOON).
# A single centred glass card in the shop's visual language: no live wheels, no
# purchase flow — just a "To be continued" note. _skins_root is a plain Control here
# (not the usual ScrollContainer), and _skins_by_id stays empty so every skin helper
# (_refresh_skin_cards / _set_skins_preview_paused / _update_skin_preview_visibility)
# no-ops naturally. The card is centre-anchored so it re-centres as _layout resizes
# the panel.
func _build_skins_coming_soon() -> void:
	_skins_root = Control.new()
	_skins_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_skins_root)

	var cw := 480.0
	var ch := 260.0
	var card := Panel.new()
	# Centre-anchor within _skins_root so it stays put through resizes / rotation.
	card.anchor_left = 0.5
	card.anchor_top = 0.5
	card.anchor_right = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = -cw * 0.5
	card.offset_top = -ch * 0.5
	card.offset_right = cw * 0.5
	card.offset_bottom = ch * 0.5
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.06, 0.08, 0.20, 0.92)
	cs.set_corner_radius_all(24)
	cs.border_color = Color(SKIN_ACCENT.r, SKIN_ACCENT.g, SKIN_ACCENT.b, 0.7)
	cs.set_border_width_all(2)
	cs.shadow_color = Color(SKIN_ACCENT.r, SKIN_ACCENT.g, SKIN_ACCENT.b, 0.35)
	cs.shadow_size = 18
	card.add_theme_stylebox_override("panel", cs)
	_skins_root.add_child(card)

	# Diamond accent, matching the tab / header convention.
	var diamond := _make_diamond(16.0, SKIN_ACCENT.lightened(0.35))
	diamond.position = Vector2(cw * 0.5, 44)
	card.add_child(diamond)

	var eyebrow := Label.new()
	eyebrow.text = "SPECIAL SKINS"
	eyebrow.add_theme_font_size_override("font_size", 18)
	eyebrow.add_theme_color_override("font_color", SKIN_ACCENT.lightened(0.2))
	eyebrow.position = Vector2(24, 74)
	eyebrow.size = Vector2(cw - 48, 26)
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eyebrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(eyebrow)

	var title := Label.new()
	title.text = "To be continued…"
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_color_override("font_shadow_color", Color(SKIN_ACCENT.r, SKIN_ACCENT.g, SKIN_ACCENT.b, 0.5))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 3)
	title.add_theme_constant_override("shadow_outline_size", 9)
	title.position = Vector2(24, 108)
	title.size = Vector2(cw - 48, 54)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(title)

	var sub := Label.new()
	sub.text = "New wheel skins are on the way."
	sub.add_theme_font_size_override("font_size", 17)
	sub.add_theme_color_override("font_color", Color(0.80, 0.82, 0.95, 0.80))
	sub.position = Vector2(24, 178)
	sub.size = Vector2(cw - 48, 26)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(sub)

func _make_skin_card(def: Dictionary) -> Dictionary:
	var skin_id: String = def["id"]

	var root := Panel.new()
	root.custom_minimum_size = Vector2(SKIN_CARD_W, SKIN_CARD_H)
	root.size = Vector2(SKIN_CARD_W, SKIN_CARD_H)
	# PASS (not STOP) so a drag starting on the card body still reaches the
	# ScrollContainer as a scroll; the buy/equip button keeps its default STOP.
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.06, 0.08, 0.20, 0.94)
	cs.set_corner_radius_all(24)
	cs.border_color = Color(SKIN_ACCENT.r, SKIN_ACCENT.g, SKIN_ACCENT.b, 0.75)
	cs.set_border_width_all(2)
	cs.shadow_color = Color(SKIN_ACCENT.r, SKIN_ACCENT.g, SKIN_ACCENT.b, 0.35)
	cs.shadow_size = 18
	root.add_theme_stylebox_override("panel", cs)

	# Live wheel preview hosted in a rounded inset, so the flame overlay can spill
	# right out to the card's interior padding for a really immersive look.
	var clip := Panel.new()
	clip.size = Vector2(SKIN_CARD_W - 36, SKIN_PREVIEW + 24)
	clip.position = Vector2(18, 18)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var clip_st := StyleBoxFlat.new()
	# Deep void backdrop, used only as a fallback for skins with no background;
	# the skin's own world (below) paints over it for skins that ship one.
	clip_st.bg_color = Color(0.018, 0.008, 0.025)
	clip_st.set_corner_radius_all(16)
	clip_st.border_color = Color(1, 1, 1, 0.07)
	clip_st.set_border_width_all(1)
	clip.add_theme_stylebox_override("panel", clip_st)
	root.add_child(clip)

	# The skin's bespoke background (e.g. the Volcano world), rendered behind the
	# wheel so the card previews the full look you'll equip — not just the wheel.
	var skin_bg := BackgroundManager.make_skin_preview(skin_id, clip.size)
	skin_bg.position = Vector2.ZERO
	clip.add_child(skin_bg)

	# Live SimonWheel preview with this skin applied. Logical size > displayed
	# size + uniform scale = preview reads at the same proportions as the in-game
	# wheel (same trick as the SIMON tab uses).
	var wheel := SimonWheel.new()
	wheel.size = Vector2(SKIN_PREVIEW_LOGICAL, SKIN_PREVIEW_LOGICAL)
	var pscale := SKIN_PREVIEW / SKIN_PREVIEW_LOGICAL
	wheel.scale = Vector2(pscale, pscale)
	wheel.position = Vector2((clip.size.x - SKIN_PREVIEW) * 0.5, (clip.size.y - SKIN_PREVIEW) * 0.5)
	clip.add_child(wheel)
	# NOTE: the wheel is configured LATER (see _build_skins_panel) — only AFTER this
	# card is added to the tree. Building/configuring it off-tree left the SubViewport
	# mis-sized (2× → only the top-left quarter showed) and mis-aimed (blank), because
	# SubViewportContainer sizing + Camera3D.look_at both need an in-tree node. The
	# SIMON tab preview works precisely because it configures its wheel in-tree.

	# Name + blurb, below the preview.
	var name_lbl := Label.new()
	name_lbl.text = String(def["label"])
	name_lbl.add_theme_font_size_override("font_size", 26)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	name_lbl.add_theme_color_override("font_shadow_color", Color(1.0, 0.40, 0.10, 0.55))
	name_lbl.add_theme_constant_override("shadow_offset_x", 0)
	name_lbl.add_theme_constant_override("shadow_offset_y", 2)
	name_lbl.add_theme_constant_override("shadow_outline_size", 8)
	name_lbl.position = Vector2(18, 18 + SKIN_PREVIEW + 24 + 8)
	name_lbl.size = Vector2(SKIN_CARD_W - 36, 32)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(name_lbl)

	# Optional one-line description under the title. Omitted for skins that
	# don't define a `blurb` (e.g. VOLCANO ships with title-only).
	var blurb_text := String(def.get("blurb", ""))
	if not blurb_text.is_empty():
		var blurb := Label.new()
		blurb.text = blurb_text
		blurb.add_theme_font_size_override("font_size", 15)
		blurb.add_theme_color_override("font_color", Color(0.80, 0.82, 0.95, 0.78))
		blurb.position = Vector2(18, name_lbl.position.y + 38)
		blurb.size = Vector2(SKIN_CARD_W - 36, 22)
		blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		blurb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(blurb)

	# Action button at the bottom: BUY (shows coin + price), EQUIP, or EQUIPPED.
	var btn := Button.new()
	btn.size = Vector2(SKIN_CARD_W - 36, 52)
	btn.position = Vector2(18, SKIN_CARD_H - 52 - 18)
	btn.add_theme_font_size_override("font_size", 20)
	btn.focus_mode = Control.FOCUS_NONE
	root.add_child(btn)
	var price := _make_price_content(CoinsManager.skin_price(skin_id), 13.0, 22, 52.0)
	btn.add_child(price["box"])
	btn.pressed.connect(func() -> void: _on_skin_action(skin_id))
	return {
		"root": root, "btn": btn, "price_box": price["box"],
		"price_label": price["label"], "accent": SKIN_ACCENT, "preview": wheel,
	}

func _refresh_skin_cards() -> void:
	for skin_id in _skins_by_id:
		_apply_skin_card_state(skin_id, _skins_by_id[skin_id])

# Mirror of _apply_card_state for skin cards. The "equipped" state additionally
# requires simon_mode == SKIN — equipping a manual per-part colour switches the
# mode back to MANUAL, at which point even the formerly-selected skin reads as
# merely OWNED, not equipped.
func _apply_skin_card_state(skin_id: String, c: Dictionary) -> void:
	var btn: Button = c["btn"]
	var accent: Color = c["accent"]
	var price_box: Control = c["price_box"]
	var price_label: Label = c["price_label"]
	var owned := CoinsManager.owns_skin(skin_id)
	var equipped := (not CoinsManager.is_simon_manual()) and CoinsManager.selected_skin == skin_id
	var affordable := CoinsManager.can_afford_skin(skin_id)

	price_box.visible = not owned
	btn.disabled = false

	var label_text := ""
	var bg_col: Color
	var fg_col := Color.WHITE
	if equipped:
		label_text = "EQUIPPED"
		bg_col = Color(0.18, 0.45, 0.28)
		btn.disabled = true
	elif owned:
		label_text = "EQUIP"
		bg_col = Color(0.20, 0.55, 0.95)
	elif affordable:
		bg_col = Color(1.00, 0.66, 0.10)
		fg_col = Color(0.18, 0.10, 0.0)
	else:
		bg_col = Color(0.30, 0.30, 0.40)
		fg_col = Color(0.85, 0.85, 0.95, 0.7)
		btn.disabled = true

	price_label.add_theme_color_override("font_color", fg_col)
	btn.text = label_text
	var s := StyleBoxFlat.new()
	s.bg_color = bg_col
	s.set_corner_radius_all(14)
	s.border_color = accent.lightened(0.2) if equipped else bg_col.lightened(0.15)
	s.set_border_width_all(2 if equipped else 0)
	btn.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = bg_col.lightened(0.12)
	btn.add_theme_stylebox_override("hover", sh)
	var sp := s.duplicate() as StyleBoxFlat
	sp.bg_color = bg_col.darkened(0.20)
	btn.add_theme_stylebox_override("pressed", sp)
	var sd := s.duplicate() as StyleBoxFlat
	sd.bg_color = bg_col.darkened(0.05)
	btn.add_theme_stylebox_override("disabled", sd)
	btn.add_theme_color_override("font_color", fg_col)
	btn.add_theme_color_override("font_disabled_color", fg_col)

# Re-applies each card's skin to its preview wheel. Cheap; safe to call any time
# the skin's appearance might have changed (e.g. catalog re-tuned during dev).
# Idle (or resume) the SPECIAL SKINS cards' live preview wheels. Called with true when
# their tab is hidden so an animated skin (e.g. Volcano's flames) stops rendering
# off-screen and taxing the other tabs, and false when the tab is shown. No-op before
# the panel is built.
func _set_skins_preview_paused(paused: bool) -> void:
	for skin_id in _skins_by_id:
		var c: Dictionary = _skins_by_id[skin_id]
		var w: SimonWheel = c.get("preview")
		if w != null and w.has_method("set_preview_paused"):
			w.set_preview_paused(paused)

# Keep only the skin cards within (or just outside) the visible scroll band running
# their live preview wheel; idle the rest. Mirrors _update_preview_visibility for the
# THEMES grid so scrolling the SKINS grid never drives every wheel at once. No-op when
# the tab is hidden (the panel-level pause already idled them all).
func _update_skin_preview_visibility() -> void:
	if _skins_root == null or not _skins_root.visible:
		return
	# Detached placeholder: a plain Control with no live wheels to gate.
	if SKINS_COMING_SOON:
		return
	var sv := float((_skins_root as ScrollContainer).scroll_vertical)
	var vh := _skins_root.size.y
	var margin := SKIN_CARD_H * 0.5
	for skin_id in _skins_by_id:
		var c: Dictionary = _skins_by_id[skin_id]
		var w: SimonWheel = c.get("preview")
		if w == null or not w.has_method("set_preview_paused"):
			continue
		var y: float = c.get("y", 0.0)
		var on := (y + SKIN_CARD_H > sv - margin) and (y < sv + vh + margin)
		w.set_preview_paused(not on)

func _on_skin_action(skin_id: String) -> void:
	if CoinsManager.owns_skin(skin_id):
		CoinsManager.equip_skin(skin_id)
		return
	if not CoinsManager.purchase_skin(skin_id):
		return
	# Auto-equip a freshly bought skin so the choice takes effect at once.
	CoinsManager.equip_skin(skin_id)

func _make_simon_tile(category: String, label: String, pos: Vector2) -> Button:
	var root := Button.new()
	root.position = pos
	root.size = Vector2(SIMON_TILE_W, SIMON_TILE_H)
	root.focus_mode = Control.FOCUS_NONE
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.06, 0.08, 0.20, 0.92)
	cs.set_corner_radius_all(18)
	cs.border_color = Color(SIMON_ACCENT.r, SIMON_ACCENT.g, SIMON_ACCENT.b, 0.7)
	cs.set_border_width_all(2)
	cs.shadow_color = Color(SIMON_ACCENT.r, SIMON_ACCENT.g, SIMON_ACCENT.b, 0.30)
	cs.shadow_size = 12
	root.add_theme_stylebox_override("normal", cs)
	var ch := cs.duplicate() as StyleBoxFlat
	ch.bg_color = Color(0.09, 0.11, 0.26, 0.95)
	root.add_theme_stylebox_override("hover", ch)
	var cp := cs.duplicate() as StyleBoxFlat
	cp.bg_color = Color(0.05, 0.06, 0.16, 0.95)
	root.add_theme_stylebox_override("pressed", cp)

	# Schematic of the wheel with THIS part highlighted, so the tile clearly
	# shows which piece of the Simon it customises (not just a colour blob).
	var swatch := SimonPartIcon.new()
	swatch.size = Vector2(SIMON_SWATCH, SIMON_SWATCH)
	swatch.position = Vector2((SIMON_TILE_W - SIMON_SWATCH) * 0.5, 18)
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(swatch)

	# Only the category name — the equipped colour/style name is intentionally not
	# shown here (the icon itself conveys the look).
	var name_lbl := Label.new()
	name_lbl.text = label
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	name_lbl.position = Vector2(8, 18 + SIMON_SWATCH + 20)
	name_lbl.size = Vector2(SIMON_TILE_W - 16, 28)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(name_lbl)

	root.pressed.connect(func() -> void: _open_color_popup(category))
	_simon_tiles[category] = {"swatch": swatch}
	return root

func _style_swatch(swatch: SimonPartIcon, category: String, color_id: String) -> void:
	# Level number is a font package; ring/hub are flat colours. Default reads as
	# the "stock" look (graphite/white) — pass null so the icon draws its fallback.
	if category == "level_number":
		swatch.setup(category, null, CoinsManager.simon_number_font(color_id))
		return
	swatch.setup(category, CoinsManager.simon_part_style(category, color_id))

func _refresh_simon_panel() -> void:
	if _simon_root == null:
		return
	# tile swatches (the equipped look is shown by the icon itself). In SKIN mode
	# the per-part slots read as "nothing equipped", so the tiles show the stock
	# look rather than whatever manual colour is still stored underneath.
	var manual := CoinsManager.is_simon_manual()
	for cat in _simon_tiles:
		var t: Dictionary = _simon_tiles[cat]
		var id: String = CoinsManager.equipped_simon_color(cat) if manual else CoinsManager.simon_default_id(cat)
		_style_swatch(t["swatch"], cat, id)
	# Live preview mirrors what the wheel actually wears right now.
	_refresh_simon_preview()

# Re-tint the preview wheel to match what is actually equipped. In skin mode a
# complete skin overrides the per-part colours, so the preview should show that
# skin (otherwise switching between tabs makes the wheel "lose" its fire/etc.).
func _refresh_simon_preview() -> void:
	if _simon_preview == null:
		return
	var skin_id := CoinsManager.selected_skin if not CoinsManager.is_simon_manual() else ""
	_simon_preview.apply_skin(
		_simon_tint("outer_circle"),
		_simon_tint("inner_circle"),
		_simon_number_pack(),
		skin_id)

# The equipped level-number font package for the live preview, or null for stock.
func _simon_number_pack() -> Variant:
	if not CoinsManager.is_simon_manual():
		return null
	var id := CoinsManager.equipped_simon_color("level_number")
	if id == CoinsManager.SIMON_DEFAULT_FONT:
		return null
	return CoinsManager.simon_number_font(id)

# The look a part wears right now (Color / pattern-motif Dictionary / null) —
# mirrors game.gd._resolved_simon_tint so the preview matches the in-game wheel.
func _simon_tint(category: String) -> Variant:
	if not CoinsManager.is_simon_manual():
		return null
	return CoinsManager.simon_part_style(category, CoinsManager.equipped_simon_color(category))

# ---------------- colour popup ----------------

const POPUP_W := 640.0
const POPUP_H := 520.0
const SWATCH_CARD_W := 168.0
const SWATCH_CARD_H := 168.0
const SWATCH_GAP := 22.0
const SWATCH_COLS := 3

func _open_color_popup(category: String) -> void:
	_close_color_popup()
	_popup_category = category
	_popup_cards.clear()
	var sz := get_viewport_rect().size

	var overlay := Control.new()
	overlay.name = "ColorPopup"
	overlay.position = Vector2.ZERO
	overlay.size = sz
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	_color_popup = overlay

	# Dim backdrop — tapping it closes the popup.
	var dim := Button.new()
	dim.flat = true
	dim.position = Vector2.ZERO
	dim.size = sz
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus"]:
		dim.add_theme_stylebox_override(st, empty)
	var dim_rect := ColorRect.new()
	dim_rect.color = Color(0.0, 0.01, 0.04, 0.66)
	dim_rect.position = Vector2.ZERO
	dim_rect.size = sz
	dim_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(dim_rect)
	dim.pressed.connect(_close_color_popup)
	overlay.add_child(dim)

	var panel := Panel.new()
	panel.position = (sz - Vector2(POPUP_W, POPUP_H)) * 0.5
	panel.size = Vector2(POPUP_W, POPUP_H)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.05, 0.06, 0.16, 0.99)
	st.set_corner_radius_all(22)
	st.border_color = Color(SIMON_ACCENT.r, SIMON_ACCENT.g, SIMON_ACCENT.b, 0.7)
	st.set_border_width_all(2)
	st.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	st.shadow_size = 22
	panel.add_theme_stylebox_override("panel", st)
	overlay.add_child(panel)

	var pretty := "PART"
	for d in SIMON_TILES:
		if d["cat"] == category:
			pretty = d["label"]
			break
	var title := Label.new()
	title.text = pretty
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.position = Vector2(24, 18)
	title.size = Vector2(POPUP_W - 48, 38)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(title)

	var close := Button.new()
	close.text = "✕"
	close.size = Vector2(40, 40)
	close.position = Vector2(POPUP_W - 50, 12)
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 20)
	var clo := StyleBoxFlat.new()
	clo.bg_color = Color(0.10, 0.12, 0.26, 0.9)
	clo.set_corner_radius_all(20)
	close.add_theme_stylebox_override("normal", clo)
	close.add_theme_color_override("font_color", Color(0.85, 0.88, 1.0))
	close.pressed.connect(_close_color_popup)
	panel.add_child(close)

	# Scroll the cards so extra rows never spill past the popup. The region runs
	# from below the title to just above the bottom edge; its width leaves room
	# for the scrollbar so the grid itself stays centred.
	const SCROLLBAR_W := 14.0
	var grid_w := SWATCH_COLS * SWATCH_CARD_W + (SWATCH_COLS - 1) * SWATCH_GAP
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size = Vector2(grid_w + SCROLLBAR_W, POPUP_H - 68 - 20)
	scroll.position = Vector2((POPUP_W - (grid_w + SCROLLBAR_W)) * 0.5, 68)
	panel.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = SWATCH_COLS
	grid.add_theme_constant_override("h_separation", int(SWATCH_GAP))
	grid.add_theme_constant_override("v_separation", int(SWATCH_GAP))
	scroll.add_child(grid)
	for color_id in CoinsManager.simon_catalog(category).keys():
		var card := _make_color_card(category, color_id)
		grid.add_child(card["root"])
		_popup_cards[color_id] = card
	_refresh_color_cards()

	# Gentle entrance.
	panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2(0.93, 0.93)
	overlay.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(overlay, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_SINE)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _make_color_card(category: String, color_id: String) -> Dictionary:
	var meta: Dictionary = CoinsManager.simon_catalog(category).get(color_id, {})
	var pretty: String = meta.get("name", color_id.capitalize())

	var root := Panel.new()
	root.custom_minimum_size = Vector2(SWATCH_CARD_W, SWATCH_CARD_H)
	root.size = Vector2(SWATCH_CARD_W, SWATCH_CARD_H)
	# PASS (not the Panel default STOP) so a drag that starts on a card body still
	# reaches the enclosing ScrollContainer — otherwise the popup only scrolls when
	# the drag begins in the gaps between cards. The BUY/EQUIP button stays STOP so
	# taps on it still register as a press, not a scroll.
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.07, 0.09, 0.22, 0.92)
	cs.set_corner_radius_all(16)
	cs.border_color = Color(1, 1, 1, 0.10)
	cs.set_border_width_all(1)
	root.add_theme_stylebox_override("panel", cs)

	# Part sketch tinted by this candidate colour, so the user previews the actual
	# wheel piece in that colour rather than picking from anonymous blobs.
	var sw := 64.0
	var swatch := SimonPartIcon.new()
	swatch.size = Vector2(sw, sw)
	swatch.position = Vector2((SWATCH_CARD_W - sw) * 0.5, 12)
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if category == "level_number":
		swatch.setup(category, null, CoinsManager.simon_number_font(color_id))
	else:
		swatch.setup(category, CoinsManager.simon_part_style(category, color_id))
	root.add_child(swatch)

	var name_lbl := Label.new()
	name_lbl.text = pretty
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	name_lbl.position = Vector2(6, 12 + sw + 4)
	name_lbl.size = Vector2(SWATCH_CARD_W - 12, 22)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(name_lbl)

	var btn := Button.new()
	btn.size = Vector2(SWATCH_CARD_W - 20, 36)
	btn.position = Vector2(10, SWATCH_CARD_H - 36 - 10)
	btn.add_theme_font_size_override("font_size", 16)
	btn.focus_mode = Control.FOCUS_NONE
	root.add_child(btn)

	# Price block inside the button (coin + number); hidden once the colour is owned.
	var price := _make_price_content(
		CoinsManager.simon_item_price(category, color_id), 9.0, 16, 36.0)
	btn.add_child(price["box"])

	btn.pressed.connect(func() -> void: _on_color_action(category, color_id))

	return {
		"root": root, "btn": btn, "price_box": price["box"],
		"price_label": price["label"], "accent": SIMON_ACCENT,
	}

func _refresh_color_cards() -> void:
	if _popup_category.is_empty():
		return
	for color_id in _popup_cards:
		_apply_color_card_state(_popup_category, color_id, _popup_cards[color_id])

func _apply_color_card_state(category: String, color_id: String, c: Dictionary) -> void:
	var btn: Button = c["btn"]
	var accent: Color = c["accent"]
	var price_box: Control = c["price_box"]
	var price_label: Label = c["price_label"]
	var owned := CoinsManager.owns_simon_color(category, color_id)
	# Only the MANUAL mode actually wears these per-part colours; in SKIN mode the
	# complete skin overrides them, so nothing should advertise itself as equipped.
	var equipped := CoinsManager.is_simon_manual() \
		and CoinsManager.equipped_simon_color(category) == color_id
	var affordable := CoinsManager.can_afford_simon_item(category, color_id)

	price_box.visible = not owned
	btn.disabled = false

	var label_text := ""
	var bg_col: Color
	var fg_col := Color.WHITE
	if equipped:
		label_text = "EQUIPPED"
		bg_col = Color(0.18, 0.45, 0.28)
		btn.disabled = true
	elif owned:
		label_text = "EQUIP"
		bg_col = Color(0.20, 0.55, 0.95)
	elif affordable:
		bg_col = Color(1.00, 0.66, 0.10)
		fg_col = Color(0.18, 0.10, 0.0)
	else:
		bg_col = Color(0.30, 0.30, 0.40)
		fg_col = Color(0.85, 0.85, 0.95, 0.7)
		btn.disabled = true

	price_label.add_theme_color_override("font_color", fg_col)
	btn.text = label_text
	var s := StyleBoxFlat.new()
	s.bg_color = bg_col
	s.set_corner_radius_all(12)
	s.border_color = accent.lightened(0.2) if equipped else bg_col.lightened(0.15)
	s.set_border_width_all(2 if equipped else 0)
	btn.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = bg_col.lightened(0.12)
	btn.add_theme_stylebox_override("hover", sh)
	var sp := s.duplicate() as StyleBoxFlat
	sp.bg_color = bg_col.darkened(0.20)
	btn.add_theme_stylebox_override("pressed", sp)
	var sd := s.duplicate() as StyleBoxFlat
	sd.bg_color = bg_col.darkened(0.05)
	btn.add_theme_stylebox_override("disabled", sd)
	btn.add_theme_color_override("font_color", fg_col)
	btn.add_theme_color_override("font_disabled_color", fg_col)

func _on_color_action(category: String, color_id: String) -> void:
	if CoinsManager.owns_simon_color(category, color_id):
		CoinsManager.equip_simon_color(category, color_id)
		return
	if not CoinsManager.can_afford_simon_item(category, color_id):
		return
	var meta: Dictionary = CoinsManager.simon_catalog(category).get(color_id, {})
	_confirm_purchase(
		String(meta.get("name", color_id.capitalize())),
		CoinsManager.simon_item_price(category, color_id),
		func() -> void:
			if CoinsManager.purchase_simon_color(category, color_id):
				# Auto-equip a freshly bought colour so the choice takes effect at once.
				CoinsManager.equip_simon_color(category, color_id)
	)

func _close_color_popup() -> void:
	if _color_popup and is_instance_valid(_color_popup):
		_color_popup.queue_free()
	_color_popup = null
	_popup_category = ""
	_popup_cards.clear()

# ---------------- loading overlay ----------------

func _build_loading_overlay() -> void:
	_ov = Panel.new()
	_ov.mouse_filter = Control.MOUSE_FILTER_STOP   # swallow taps while loading
	_ov.z_index = 100                              # above cards, tabs, and the orbit orbs
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.008, 0.020, 0.075, 0.985)
	_ov.add_theme_stylebox_override("panel", s)
	add_child(_ov)

	_ov_orbit = Node2D.new()
	_ov.add_child(_ov_orbit)
	var ring := _make_ring(2.0, Color(0.45, 0.55, 1.0, 0.18))
	var pts := PackedVector2Array()
	var n := 64
	var r := 52.0
	for i in n + 1:
		var a: float = TAU * float(i) / n
		pts.append(Vector2(cos(a), sin(a)) * r)
	ring.points = pts
	_ov_orbit.add_child(ring)
	_ov_orbs.clear()
	for i in ORB_COLORS.size():
		var orb := _make_orb(ORB_COLORS[i])
		orb.scale = Vector2.ONE * 0.55
		var a: float = -PI * 0.5 + i * TAU / ORB_COLORS.size()
		orb.position = Vector2(cos(a), sin(a)) * r
		_ov_orbit.add_child(orb)
		_ov_orbs.append(orb)

	_ov_caption = Label.new()
	_ov_caption.text = "Loading shop"
	_ov_caption.add_theme_font_size_override("font_size", 24)
	_ov_caption.add_theme_color_override("font_color", Color(0.78, 0.84, 1.0, 0.92))
	_ov_caption.add_theme_color_override("font_shadow_color", Color(0.30, 0.45, 1.0, 0.35))
	_ov_caption.add_theme_constant_override("shadow_offset_x", 0)
	_ov_caption.add_theme_constant_override("shadow_offset_y", 0)
	_ov_caption.add_theme_constant_override("shadow_outline_size", 6)
	_ov_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ov_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ov.add_child(_ov_caption)

	var rot := create_tween().set_loops()
	rot.tween_property(_ov_orbit, "rotation", TAU, 2.6).from(0.0).set_trans(Tween.TRANS_LINEAR)
	for i in _ov_orbs.size():
		var dur := 0.7 + i * 0.05
		var base: Vector2 = _ov_orbs[i].scale
		var pulse := create_tween().set_loops()
		pulse.tween_property(_ov_orbs[i], "scale", base * 1.14, dur) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		pulse.tween_property(_ov_orbs[i], "scale", base, dur) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var dots := create_tween().set_loops()
	dots.tween_interval(0.35)
	dots.tween_callback(_ov_tick_dots)

	_ov.visible = false
	_layout_loading()

func _ov_tick_dots() -> void:
	if _ov_caption == null or _ov == null or not _ov.visible:
		return
	_ov_dots_idx = (_ov_dots_idx + 1) % 4
	_ov_caption.text = "Loading shop" + ".".repeat(_ov_dots_idx)

func _layout_loading() -> void:
	if _ov == null:
		return
	var sz := get_viewport_rect().size
	_ov.position = Vector2.ZERO
	_ov.size = sz
	if _ov_orbit:
		_ov_orbit.position = Vector2(sz.x * 0.5, sz.y * 0.46)
	if _ov_caption:
		_ov_caption.size = Vector2(320, 32)
		_ov_caption.position = Vector2(sz.x * 0.5 - 160, sz.y * 0.46 + 92)

func _show_loading() -> void:
	_layout_loading()
	if _ov:
		_ov.visible = true

func _hide_loading() -> void:
	if _ov:
		_ov.visible = false

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
		_orbit.position = Vector2(cx, sz.y * 0.52)
		_rebuild_ring(r)
		for i in _orbs.size():
			var a: float = -PI * 0.5 + i * TAU / _orbs.size()
			_orbs[i].position = Vector2(cos(a), sin(a)) * r

	var top := 14.0
	if _back:
		_back.position = Vector2(24, top + 4)
	if _header:
		_header.position = Vector2(cx - _header.size.x * 0.5, top)
	if _coin_pill:
		_coin_pill.position = Vector2(sz.x - _coin_pill.size.x - 24, top + 4)
		if _coin_plus_btn:
			# Sit immediately left of the pill, vertically centred against it.
			_coin_plus_btn.position = Vector2(
				_coin_pill.position.x - _coin_plus_btn.size.x - 10,
				_coin_pill.position.y + (_coin_pill.size.y - _coin_plus_btn.size.y) * 0.5)

	if _tab_row:
		var row_w := CATEGORIES.size() * TAB_W + maxi(0, CATEGORIES.size() - 1) * TAB_SEP
		_tab_row.position = Vector2(cx - row_w * 0.5, top + HEADER_H + 8.0)

	var content_y := top + HEADER_H + 8.0 + TAB_H + 28.0
	if _grid_scroll:
		var grid_w := GRID_COLS * CARD_W + (GRID_COLS - 1) * CARD_GAP_X
		# Reserve scrollbar width so the cards themselves stay visually centred.
		var scroll_w := grid_w + GRID_SCROLLBAR_W
		_grid_scroll.position = Vector2(cx - scroll_w * 0.5, content_y)
		_grid_scroll.size = Vector2(scroll_w,
			maxf(0.0, sz.y - content_y - GRID_BOTTOM_MARGIN))
		_update_preview_visibility()
	if _simon_root:
		_simon_root.position = Vector2(cx - SIMON_PANEL_W * 0.5, content_y)
	if _skins_root:
		var sgrid_w := SKIN_GRID_COLS * SKIN_CARD_W + (SKIN_GRID_COLS - 1) * SKIN_CARD_GAP
		# Reserve scrollbar width so the cards themselves stay visually centred.
		var sscroll_w := sgrid_w + SKIN_GRID_SCROLLBAR_W
		_skins_root.position = Vector2(cx - sscroll_w * 0.5, content_y)
		_skins_root.size = Vector2(sscroll_w,
			maxf(0.0, sz.y - content_y - GRID_BOTTOM_MARGIN))
		_update_skin_preview_visibility()

	_layout_loading()

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
