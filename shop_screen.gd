extends Control

const CoinsPurchasePopup := preload("res://coins_purchase_popup.gd")
const PurchaseConfirmPopup := preload("res://purchase_confirm_popup.gd")
const ArenaUI := preload("res://arena_ui.gd")

# Shop screen — same visual language as the leaderboards / difficulty / home
# screens (deep-space shader background, slowly rotating orbit of glowing orbs,
# glass back button, glowing header with diamond-underlined subtitle, segmented
# category tabs). Three categories, each built from data in one place:
#   THEMES         — the background catalog (CoinsManager.THEMES), a scrolling grid.
#                    Only the modelled 3D backgrounds are on sale; the older shader
#                    themes are detached (see CATEGORIES["items"]).
#   BUTTON FRAMES  — the modelled boards' button-bezel cosmetics (ButtonFrames), a
#                    scrolling 3-wide grid, each card previewing a real GLB button
#                    wearing it.
#   SPECIAL SKINS  — complete pre-made wheel skins (CoinsManager.SIMON_SKINS).
#                    Currently detached: no skin is flagged `released`, so the tab
#                    shows the "Coming soon" card instead of a grid (see SKIN_DEFS).
# Every card in every category shows a preview, the price, and the same state-aware
# action button (BUY → EQUIP → EQUIPPED).
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
		# THIS LIST IS THE SHOP'S SOURCE OF DISPLAY ORDER *AND* OF WHAT IS ON SALE.
		# Only the eight modelled 3D backgrounds (BackgroundScenes) are listed. They are
		# ordinary theme cards in every respect the shop cares about — the only
		# difference is that their preview comes from a baked 3D render instead of a
		# live shader, which BackgroundManager.make_preview resolves on its own.
		#
		# Every older shader theme (midnight … deepspace) is DETACHED, not deleted:
		# its CoinsManager.THEMES entry and its BackgroundManager renderer are intact,
		# so a player who already owns and equips one keeps it working and re-listing
		# one is a single id added back here. Nothing else needs to change.
		#
		# "default" stays listed on purpose. It is the only way back for a player who
		# has a now-detached theme equipped — without a Default card they would be
		# stuck on it. Its card is always "owned" and free, so the buy/equip flow
		# handles it without special casing.
		"items": ["default",
			"bg_darkmetal", "bg_hexfloor", "bg_neongrid", "bg_circuit",
			"bg_deepspace", "bg_volcanic", "bg_crystal", "bg_arcade"],
	},
	# Button-frame cosmetics for the modelled boards. No flat `items` list — its cards
	# come from ButtonFrames.ORDER and are built specially in _render_category /
	# _build_frames_panel.
	{
		"key": "frames", "label": "BUTTON FRAMES", "icon": "diamond",
		"accent": Color(0.58, 0.46, 1.00),
	},
	# Complete pre-made wheel skins, as their own category. Empty for now (a
	# placeholder panel); ships later. See _build_skins_panel.
	{
		"key": "skins", "label": "SPECIAL SKINS", "icon": "diamond",
		"accent": Color(0.92, 0.45, 0.78),
	},
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
# seamless the moment it appears. Fixed "Loading…" caption plus a milestone-driven
# progress bar (same treatment as the boot loading screen). Lifted by _begin_load once
# everything is ready.
var _ov: Panel
var _ov_caption: Label
var _ov_bar: ProgressBar
var _ov_progress := 0.0
var _loaded := false

# Loading-bar geometry + milestones. Values mark the END of each _begin_load stage, so
# the bar steps only when real work actually finishes — see _set_load_progress.
const OV_BAR_W := 260.0
const OV_BAR_H := 10.0
const LP_START := 0.05      # overlay painted, construction about to begin
const LP_GRID := 0.30       # THEMES grid rendered
const LP_PANELS := 0.50     # BUTTON FRAMES + SKINS panels prebuilt
const LP_COMPILE := 1.0     # every priority preview shader compiled

# --- BUTTON FRAMES tab ---
var _frames_root: Control                # frame-cosmetic panel (built lazily) — a ScrollContainer
var _frames_grid: GridContainer          # the card grid inside _frames_root
var _frames_by_id: Dictionary = {}       # frame_id -> {root, btn, price_box, price_label, accent, preview}
var _skins_root: Control                 # SPECIAL SKINS panel (built lazily) — the ScrollContainer
										 # card grid, or a plain Control placeholder when detached
										 # (_skins_coming_soon). Cast to ScrollContainer for scroll ops.
var _skins_grid: GridContainer           # the card grid inside _skins_root
var _skins_by_id: Dictionary = {}        # skin_id -> {root, btn, btn_label, price_label, accent, preview, y}

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
	# Keep cards + coin pill in sync if the player buys / equips while open. All three
	# signals funnel into a single coalesced refresh (see _queue_refresh): a buy fires
	# balance_changed + themes_changed (+ simon_changed when a skin drops) in the same
	# frame, and each used to re-run the SAME handlers — restyling every card and
	# rebuilding the hidden skin preview wheels' materials several times per equip.
	# _flush_refresh runs once per frame and only touches the panel that's actually
	# visible; hidden panels refresh when their tab is next shown (see _render_category).
	CoinsManager.balance_changed.connect(_on_balance_changed)
	CoinsManager.themes_changed.connect(_queue_refresh)
	CoinsManager.simon_changed.connect(_queue_refresh)
	CoinsManager.frames_changed.connect(_queue_refresh)
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
	_set_load_progress(LP_START)
	# Let the loading overlay actually paint BEFORE we block the main thread building the
	# store. Everything below (the theme-card grid + the FRAMES/SKINS panels) is constructed
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
	# Pre-compile the preview shaders one per frame, so no tile hitches on a first-draw
	# shader compile. Previews stay fully LIVE/animated — what keeps scrolling smooth is
	# that the shop only lets the tiles actually IN the visible scroll band keep drawing
	# (see _update_preview_visibility), so at most a handful of shaders run at once.
	#
	# We hold the veil only for the FIRST screenful of theme shaders (+ the skin card
	# backgrounds) — compiling all ~20 up front is what made first-open feel long. The
	# rest are queued in the background right after the veil lifts (see below); by the
	# time the player scrolls past the first rows they're compiled, and any that aren't
	# yet warm cost a single one-frame hitch instead of blocking the whole open.
	var priority_count := GRID_COLS * 3          # first three rows cover the opening view
	BackgroundManager.prewarm_previews(theme_items.slice(0, priority_count))
	# Skip the skin-preview prewarm entirely while the SPECIAL SKINS tab is detached —
	# the placeholder renders no wheels, so there's nothing to warm.
	if not _skins_coming_soon():
		var skin_ids: Array[String] = []
		for d in _live_skin_defs():
			skin_ids.append(String(d["id"]))
		BackgroundManager.prewarm_skin_previews(skin_ids)
	# Render the THEMES grid and build the FRAMES + SKINS panels while the overlay still
	# hides the construction. These are the two heaviest bursts in the shop, so both run
	# in INCREMENTAL mode — yielding frames as they build — so the loading overlay's orbit
	# tween keeps ticking instead of freezing the moment the shop opens.
	await _render_category(_current_cat, true)
	if not is_inside_tree():
		return
	_set_load_progress(LP_GRID)
	await _prebuild_panels()
	if not is_inside_tree():
		return
	_set_load_progress(LP_PANELS)
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
	# The compile queue drains one shader per frame, so its depth is real progress —
	# measure against the high-water mark and walk the bar from LP_PANELS to LP_COMPILE
	# as it empties. This is the longest stretch of a first shop open; on a repeat open
	# everything is already warm, the loop never runs, and the bar simply completes.
	var peak_pending := maxi(1, BackgroundManager.prewarm_pending())
	while BackgroundManager.is_prewarming() and is_inside_tree():
		peak_pending = maxi(peak_pending, BackgroundManager.prewarm_pending())
		var done_frac := 1.0 - float(BackgroundManager.prewarm_pending()) / float(peak_pending)
		_set_load_progress(LP_PANELS + (LP_COMPILE - LP_PANELS) * done_frac)
		await get_tree().process_frame
	if not is_inside_tree():
		return
	# Top the bar off and let one frame present it, so the veil doesn't lift off a bar
	# visibly stuck short of full.
	_set_load_progress(LP_COMPILE)
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_loaded = true
	_hide_loading()
	_update_preview_visibility()
	# The shop is now interactive. Compile the remaining theme preview shaders in the
	# background (one per frame) so scrolling further down stays hitch-free. Already-warm
	# and already-queued ids are skipped inside prewarm_previews, so passing the full
	# list just enqueues whatever the priority pass didn't cover.
	BackgroundManager.prewarm_previews(theme_items)

# Builds the non-default category panels ahead of time so switching to them is
# instant. Each builder add_child()s its root; the inactive panels are hidden immediately, but the
# SKINS panel is left VISIBLE (under the veil) so its 3D preview wheels actually render
# — _begin_load hides + idles it once that render has happened. Yields a frame between
# the two panels so the loading overlay's animation keeps ticking during the build.
# Safe to call once — guarded by the null checks.
func _prebuild_panels() -> void:
	if not is_inside_tree():
		return
	if _frames_root == null:
		_build_frames_panel()
		_frames_root.visible = false
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

# Leaving the shop. The BUTTON FRAMES tab is the one place that needs all sixteen
# cosmetics resident at once — sixteen meshes and their texture sets — and there is
# no reason to carry that into a game. Hand everything back except what the player
# is actually wearing; the board re-asks for that one and gets it from the cache.
func _exit_tree() -> void:
	ButtonFrames.trim_cache([CoinsManager.selected_frame])
	ButtonFramePreview.release_template()

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
	# Icon-only "<" back cap, matching the Arena screen's back button.
	_back = ArenaUI.make_back_button()
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

# Bigger version of the in-game HUD coin. Uses the exact same 3D-shaded minted
# coin (PackIcons.draw_coin_3d) as the game HUD and home-screen pill so the
# currency reads identically everywhere, wrapped in a soft golden halo for the
# header. The "$" is stamped on top.
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
	# Minted coin drawn centered on this Node2D's origin (r ≈ old rim radius so
	# the on-screen size is unchanged from the previous flat disc).
	var r := d * 0.9
	var disc := Node2D.new()
	disc.draw.connect(func() -> void:
		PackIcons.draw_coin_3d(disc, Vector2.ZERO, r))
	n.add_child(disc)
	var glyph := Label.new()
	glyph.text = "$"
	glyph.add_theme_font_size_override("font_size", int(d * 1.2))
	# Dark stamped glyph with a pale lower-right shadow → reads as raised metal.
	glyph.add_theme_color_override("font_color", Color(0.34, 0.19, 0.02))
	glyph.add_theme_color_override("font_shadow_color", Color(1.0, 0.94, 0.66, 0.7))
	glyph.add_theme_constant_override("shadow_offset_x", 1)
	glyph.add_theme_constant_override("shadow_offset_y", 2)
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
	_coin_plus_btn.pivot_offset = Vector2(d, d) * 0.5
	_coin_plus_btn.add_theme_font_size_override("font_size", 34)
	_coin_plus_btn.focus_mode = Control.FOCUS_NONE
	# Raised 3D disc matching the home-screen "+": warm bevel (bright gold rim,
	# dark base) on a drop shadow so it reads as a button popping OFF the pill.
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
	# Y position is shared with the pill (centered vertically); X is set in _layout.
	_coin_plus_btn.position = Vector2(0, (pill_h - d) * 0.5)
	add_child(_coin_plus_btn)

	# Glossy top sheen — a soft warm-white highlight on the upper half so the
	# disc reads as a rounded dome catching light from above. Purely decorative.
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
	# The sheen dims while the button is held so the disc reads as pressing in.
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

func _on_balance_changed(new_balance: int) -> void:
	# The coin pill updates immediately (instant feedback); card affordability rides
	# the coalesced refresh with the other signals fired by the same purchase.
	if _coin_lbl:
		_coin_lbl.text = str(new_balance)
	_queue_refresh()

# --- coalesced card refresh ---
# balance_changed / themes_changed / simon_changed all arrive together on a buy or
# equip; funnel them into a SINGLE refresh next idle frame so the work runs once,
# not three times. _flush_refresh only restyles the panel that's currently visible —
# hidden panels are refreshed when their tab is next shown by _render_category.
var _refresh_queued := false

func _queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_flush_refresh")

func _flush_refresh() -> void:
	_refresh_queued = false
	# Equipping inside the shop can flip is_themed() (a paid theme / skin background),
	# so keep the shop's own background in sync regardless of the active tab.
	_sync_local_background()
	match _current_cat:
		"themes":
			_refresh_cards()
		"frames":
			_refresh_frame_cards()
		"skins":
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
	# THEMES uses the card grid; BUTTON FRAMES and SPECIAL SKINS each have a bespoke panel.
	# Hide them all, then show the one for this category.
	_grid_scroll.visible = false
	if _frames_root:
		_frames_root.visible = false
	if _skins_root:
		_skins_root.visible = false
	# Any SPECIAL SKINS preview wheels idle while their tab is hidden; the skins branch
	# below resumes them when that tab is the one being shown.
	_set_skins_preview_paused(true)

	if key == "frames":
		if _frames_root == null:
			_build_frames_panel()
		_frames_root.visible = true
		(_frames_root as ScrollContainer).scroll_vertical = 0
		_refresh_frame_cards()
		_layout()
		return
	if key == "skins":
		if _skins_root == null:
			_build_skins_panel()
		_skins_root.visible = true
		# The detached placeholder is a plain Control (no scroll_vertical); the real
		# panel is a ScrollContainer that we reset to the top on show.
		if not _skins_coming_soon():
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
	# the list only scrolls from the gaps between cards. The buy/equip button is
	# also PASS (see below) so a drag starting on the button itself still scrolls.
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
	# PASS so a press-and-drag that starts on the button still reaches the
	# ScrollContainer; a plain tap still registers as a click.
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
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

# Every shop card (theme / skin / colour) shares the same four button states —
# EQUIPPED, owned EQUIP, affordable BUY, locked BUY — differing only by accent and
# corner radius. Building the five StyleBoxFlats fresh on each card each refresh meant
# ~5 allocations × 21 theme cards on every equip; instead we build them ONCE per
# (accent, radius, state) and share the resources across all cards in that state.
var _btn_style_cache: Dictionary = {}

# Returns the cached visual for a card button state:
#   { normal, hover, pressed, disabled : StyleBoxFlat, fg : Color,
#     text : String, disabled_btn : bool }
# `state` is one of "equipped" | "owned" | "afford" | "locked".
func _card_button_style(accent: Color, radius: int, state: String) -> Dictionary:
	var key := "%s|%d|%s" % [accent.to_html(true), radius, state]
	if _btn_style_cache.has(key):
		return _btn_style_cache[key]
	var equipped := state == "equipped"
	var bg_col: Color
	var fg_col := Color.WHITE
	var text := ""
	match state:
		"equipped":
			bg_col = Color(0.18, 0.45, 0.28)
			text = "EQUIPPED"
		"owned":
			bg_col = Color(0.20, 0.55, 0.95)
			text = "EQUIP"
		"afford":
			bg_col = Color(1.00, 0.66, 0.10)
			fg_col = Color(0.18, 0.10, 0.0)
		_:  # "locked"
			bg_col = Color(0.30, 0.30, 0.40)
			fg_col = Color(0.85, 0.85, 0.95, 0.7)
	var s := StyleBoxFlat.new()
	s.bg_color = bg_col
	s.set_corner_radius_all(radius)
	s.border_color = accent.lightened(0.2) if equipped else bg_col.lightened(0.15)
	s.set_border_width_all(2 if equipped else 0)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = bg_col.lightened(0.12)
	var sp := s.duplicate() as StyleBoxFlat
	sp.bg_color = bg_col.darkened(0.20)
	var sd := s.duplicate() as StyleBoxFlat
	sd.bg_color = bg_col.darkened(0.05)
	var out := {
		"normal": s, "hover": sh, "pressed": sp, "disabled": sd,
		"fg": fg_col, "text": text, "disabled_btn": equipped or state == "locked",
	}
	_btn_style_cache[key] = out
	return out

# Resolve which of the four states a card is in, given its ownership flags.
func _card_state(owned: bool, equipped: bool, affordable: bool) -> String:
	if equipped:
		return "equipped"
	if owned:
		return "owned"
	return "afford" if affordable else "locked"

# Apply a resolved state's cached styling to a card's button + price block.
func _style_card_button(btn: Button, price_box: Control, price_label: Label,
		accent: Color, radius: int, state: String, owned: bool) -> void:
	var st := _card_button_style(accent, radius, state)
	# Unowned cards show the price block in the button; owned ones show EQUIP/EQUIPPED.
	price_box.visible = not owned
	price_label.add_theme_color_override("font_color", st["fg"])
	btn.text = st["text"]
	btn.disabled = st["disabled_btn"]
	btn.add_theme_stylebox_override("normal", st["normal"])
	btn.add_theme_stylebox_override("hover", st["hover"])
	btn.add_theme_stylebox_override("pressed", st["pressed"])
	btn.add_theme_stylebox_override("disabled", st["disabled"])
	btn.add_theme_color_override("font_color", st["fg"])
	btn.add_theme_color_override("font_disabled_color", st["fg"])

func _apply_card_state(theme_id: String, c: Dictionary) -> void:
	var owned := CoinsManager.owns(theme_id)
	# In SKIN mode the skin's own world overrides every theme, so no theme reads as
	# equipped — it shows EQUIP instead (tapping it drops the skin and re-applies
	# the theme as the background).
	var equipped := CoinsManager.is_simon_manual() and CoinsManager.selected_theme == theme_id
	var affordable := CoinsManager.can_afford(theme_id)
	_style_card_button(c["btn"], c["price_box"], c["price_label"], c["accent"], 14,
		_card_state(owned, equipped, affordable), owned)

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

# ---------------- BUTTON FRAMES panel ----------------
#
# The frame cosmetics for the modelled boards' buttons — Medium's five and Hard's
# six. One equipped frame is worn by every button on whichever board is in play, so
# this is a single flat list of cards — no per-colour slot, no per-difficulty
# inventory and no sub-popup. DEFAULT leads so reverting to the stock black bezel is
# always one tap away; it is permanently owned and free, which lets it ride the same
# BUY -> EQUIP -> EQUIPPED flow as the rest with no special casing.
#
# Sixteen cards (DEFAULT + the fifteen Blender cosmetics) no longer fit one row, so
# this is a scrolling 3-wide grid built the same way the THEMES tab's is — same card
# footprint, same gaps, same reserved scrollbar width — rather than a second kind of
# list to maintain. Three across (not four) so each card is given the same breathing
# room as a THEMES card at the same viewport width.
const FRAME_CARD_W := 288.0
const FRAME_CARD_H := 320.0
const FRAME_CARD_GAP := 22.0
const FRAME_PREVIEW_H := 152.0
const FRAME_GRID_COLS := 3
const FRAMES_PANEL_W := FRAME_GRID_COLS * FRAME_CARD_W \
	+ (FRAME_GRID_COLS - 1) * FRAME_CARD_GAP

# Segment colours for the SPECIAL SKINS preview wheels — a fixed slice of game.gd's
# BUTTON_COLORS (a preview only demonstrates the skin's rim/hub/numeral treatment, so
# the segment colours themselves are arbitrary but should look like a real round).
const PREVIEW_COLORS := [
	Color(0.9, 0.15, 0.15), Color(0.15, 0.8, 0.15), Color(0.15, 0.35, 0.95),
	Color(0.95, 0.85, 0.1), Color(0.95, 0.5, 0.1),
]

func _build_frames_panel() -> void:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = false
	_frames_root = scroll
	add_child(_frames_root)

	_frames_grid = GridContainer.new()
	_frames_grid.columns = FRAME_GRID_COLS
	_frames_grid.add_theme_constant_override("h_separation", int(FRAME_CARD_GAP))
	_frames_grid.add_theme_constant_override("v_separation", int(FRAME_CARD_GAP))
	scroll.add_child(_frames_grid)

	_frames_by_id.clear()
	for i in ButtonFrames.ORDER.size():
		var frame_id: String = ButtonFrames.ORDER[i]
		var card := _make_frame_card(frame_id)
		_frames_grid.add_child(card["root"])
		_frames_by_id[frame_id] = card
	_refresh_frame_cards()

func _make_frame_card(frame_id: String) -> Dictionary:
	var accent := ButtonFrames.frame_accent(frame_id)
	var glow := ButtonFrames.frame_glow(frame_id)

	var root := Panel.new()
	root.custom_minimum_size = Vector2(FRAME_CARD_W, FRAME_CARD_H)
	root.size = Vector2(FRAME_CARD_W, FRAME_CARD_H)
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	# Each card's border + drop shadow wear their own cosmetic's colours, so the four
	# read as four different things before you have even looked at the previews.
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.06, 0.08, 0.20, 0.94)
	cs.set_corner_radius_all(22)
	cs.border_color = Color(accent.r, accent.g, accent.b, 0.85)
	cs.set_border_width_all(2)
	cs.shadow_color = Color(glow.r, glow.g, glow.b, 0.40)
	cs.shadow_size = 16
	root.add_theme_stylebox_override("panel", cs)

	# The preview: one real GLB button wearing this frame, in a rounded inset.
	var clip := Panel.new()
	clip.size = Vector2(FRAME_CARD_W - 32, FRAME_PREVIEW_H)
	clip.position = Vector2(16, 16)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var clip_st := StyleBoxFlat.new()
	clip_st.bg_color = Color(0.030, 0.035, 0.075)
	clip_st.set_corner_radius_all(14)
	clip_st.border_color = Color(accent.r, accent.g, accent.b, 0.20)
	clip_st.set_border_width_all(1)
	clip.add_theme_stylebox_override("panel", clip_st)
	root.add_child(clip)

	var preview := ButtonFramePreview.new()
	preview.size = clip.size
	preview.position = Vector2.ZERO
	clip.add_child(preview)
	preview.set_frame(frame_id)

	var name_lbl := Label.new()
	name_lbl.text = ButtonFrames.frame_name(frame_id).to_upper()
	name_lbl.add_theme_font_size_override("font_size", 21)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	name_lbl.add_theme_color_override("font_shadow_color", Color(glow.r, glow.g, glow.b, 0.55))
	name_lbl.add_theme_constant_override("shadow_offset_x", 0)
	name_lbl.add_theme_constant_override("shadow_offset_y", 2)
	name_lbl.add_theme_constant_override("shadow_outline_size", 8)
	name_lbl.position = Vector2(16, 16 + FRAME_PREVIEW_H + 12)
	name_lbl.size = Vector2(FRAME_CARD_W - 32, 28)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(name_lbl)

	var blurb := Label.new()
	blurb.text = ButtonFrames.frame_blurb(frame_id)
	blurb.add_theme_font_size_override("font_size", 14)
	blurb.add_theme_color_override("font_color", Color(0.80, 0.82, 0.95, 0.78))
	blurb.position = Vector2(16, name_lbl.position.y + 30)
	blurb.size = Vector2(FRAME_CARD_W - 32, 20)
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blurb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(blurb)

	var btn := Button.new()
	btn.size = Vector2(FRAME_CARD_W - 32, 48)
	btn.position = Vector2(16, FRAME_CARD_H - 48 - 14)
	btn.add_theme_font_size_override("font_size", 19)
	btn.focus_mode = Control.FOCUS_NONE
	# PASS, like the theme cards: a drag that starts on the button still scrolls the
	# grid instead of being swallowed by it.
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(btn)
	# The price block sits inside the button, same as every other shop card. These
	# are all priced at 0, so an unowned card literally reads "coin 0".
	var price := _make_price_content(CoinsManager.frame_price(frame_id), 12.0, 20, 48.0)
	btn.add_child(price["box"])
	btn.pressed.connect(func() -> void: _on_frame_action(frame_id))
	return {
		"root": root, "btn": btn, "price_box": price["box"],
		"price_label": price["label"], "accent": accent, "preview": preview,
	}

func _refresh_frame_cards() -> void:
	for frame_id in _frames_by_id:
		_apply_frame_card_state(frame_id, _frames_by_id[frame_id])

func _apply_frame_card_state(frame_id: String, c: Dictionary) -> void:
	var owned := CoinsManager.owns_frame(frame_id)
	var equipped := CoinsManager.selected_frame == frame_id
	_style_card_button(c["btn"], c["price_box"], c["price_label"], c["accent"], 14,
		_card_state(owned, equipped, CoinsManager.can_afford_frame(frame_id)), owned)

func _on_frame_action(frame_id: String) -> void:
	if CoinsManager.owns_frame(frame_id):
		CoinsManager.select_frame(frame_id)
		return
	# The same confirm-then-buy gate the themes use, so the shop has one flow. At 0
	# coins the dialog is simply confirming a free unlock — it still shows the price.
	_confirm_purchase(
		ButtonFrames.frame_name(frame_id),
		CoinsManager.frame_price(frame_id),
		func() -> void:
			if CoinsManager.purchase_frame(frame_id):
				# Auto-equip what was just unlocked, so the five buttons change the
				# moment the player leaves the shop.
				CoinsManager.select_frame(frame_id)
	)


# SPECIAL SKINS panel — one tall card per complete skin (currently only Inferno).
# Each card hosts a live SimonWheel preview with the skin's bespoke palette and
# overlay (e.g. the inferno flames) actually rendering, so what you see in the
# shop is exactly what you get on the gameplay screen.
const SKIN_ACCENT := Color(0.92, 0.45, 0.78)   # generic fallback for any skin without a bespoke pair
# Per-skin frame palette: [primary (border), secondary (glow)]. Each card's frame wears
# its own skin's colours instead of one shared pink, so the border reads as part of the
# world it previews. Requested pairs: Volcano red→orange, Arcade blue→purple, Jackpot
# white→black, Luna Park white→red. See _skin_frame / _make_skin_card.
const SKIN_FRAME_COLORS := {
	"inferno":  [Color(1.00, 0.32, 0.08), Color(1.00, 0.64, 0.18)],   # molten red-orange
	"arcade":   [Color(0.36, 0.48, 1.00), Color(0.70, 0.30, 1.00)],   # electric blue-purple
	"casino":   [Color(0.96, 0.96, 0.98), Color(0.06, 0.06, 0.09)],   # ivory white / black
	"lunapark": [Color(1.00, 0.96, 0.94), Color(1.00, 0.26, 0.30)],   # carnival white / red
}
const SKIN_CARD_W := 360.0
const SKIN_CARD_H := 470.0
const SKIN_PREVIEW := 260.0
const SKIN_PREVIEW_LOGICAL := 380.0   # render the live wheel at this logical size
									   # then scale down (same trick as the skin
									   # tab's preview — keeps the inner numeral/hub
									   # proportions correct at preview scale).
const SKIN_CARD_GAP := 32.0
# The SPECIAL SKINS cards live in a scrolling grid (same as the THEMES tab) so more
# skins than fit on screen wrap onto extra rows instead of running off the side.
const SKIN_GRID_COLS := 3
const SKIN_GRID_SCROLLBAR_W := 14.0
# Padding inside the skins scroll so each card's coloured frame glow (drop shadow, incl.
# the rounded corners) isn't clipped by the scroll bounds. Slightly larger than the card
# shadow_size (20). See _build_skins_panel / _layout.
const SKIN_FRAME_PAD := 26

# Most of the skin set isn't ready to ship, so the SPECIAL SKINS tab shows only the
# skins flagged `released` below. When NONE are released the whole tab is DETACHED —
# instead of the card grid it shows a "Coming soon" placeholder (see
# _skins_coming_soon / _build_skins_coming_soon). Nothing is deleted — the full skin
# card / preview pipeline stays intact and each skin returns the moment its entry is
# flagged released (which also re-enables that skin's preview prewarm in _begin_load).
# Released skins: NONE — every entry below is detached, so the tab is the placeholder.

# Display order + pretty labels for the skins shown in the SPECIAL SKINS tab.
# Adding a new skin = an entry here + a catalog entry in CoinsManager.SIMON_SKINS
# + the corresponding skin path in SimonWheel. A `blurb` field is optional; when
# absent the card renders just the title (used for VOLCANO). Only entries with
# `released: true` appear in the shop — the rest stay hidden until they're ready.
# Ordered by price, ascending.
const SKIN_DEFS := [
	# All three are DETACHED for now (no `released` flag): the art, the SimonWheel skin
	# paths and the CoinsManager catalog entries are untouched, so re-listing one is a
	# single `"released": true` here. With none released the tab shows the coming-soon card.
	{"id": "casino", "label": "JACKPOT", "blurb": "Place your bets."},
	{"id": "arcade", "label": "ARCADE", "blurb": "Insert coin."},
	{"id": "lunapark", "label": "LUNA PARK", "blurb": "Step right up."},
	{"id": "racing", "label": "REDLINE", "blurb": "Floor it."},
	{"id": "pirate", "label": "BUCCANEER", "blurb": "Batten the hatches."},
	{"id": "submarine", "label": "NAUTILUS", "blurb": "Dive deep."},
	{"id": "phantom", "label": "PHANTOM", "blurb": "Something's watching."},
	{"id": "inferno", "label": "VOLCANO"},  # detached: too laggy for now (art/pipeline kept intact)
]

# The subset of SKIN_DEFS that are live in the shop right now (flagged `released`).
# All skin building/prewarm iterates this, so unreleased skins never render a card.
func _live_skin_defs() -> Array:
	var out: Array = []
	for d in SKIN_DEFS:
		if d.get("released", false):
			out.append(d)
	return out

# The SPECIAL SKINS tab is detached (shows the "Coming soon" placeholder instead
# of the card grid) exactly when no skins are released yet.
func _skins_coming_soon() -> bool:
	return _live_skin_defs().is_empty()

# `incremental` (initial load, behind the veil) yields a frame between skin cards so the
# loading overlay keeps animating instead of freezing while all 7 live 3D preview wheels —
# the single heaviest build in the shop — are constructed in one synchronous burst.
func _build_skins_panel(incremental := false) -> void:
	# No released skins yet — show the placeholder instead of the card grid.
	if _skins_coming_soon():
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
	# Inset the grid from the scroll edges with a MarginContainer, so each card's coloured
	# frame GLOW (a StyleBoxFlat drop shadow that extends beyond the card, incl. its rounded
	# corners) has room to render instead of being clipped hard against the scroll bounds —
	# most visibly at the top. The top margin also nudges the first row down a little.
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_top", SKIN_FRAME_PAD)
	pad.add_theme_constant_override("margin_bottom", SKIN_FRAME_PAD)
	pad.add_theme_constant_override("margin_left", SKIN_FRAME_PAD)
	pad.add_theme_constant_override("margin_right", SKIN_FRAME_PAD)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skins_root.add_child(pad)
	_skins_grid = GridContainer.new()
	_skins_grid.columns = SKIN_GRID_COLS
	# Keep the fixed-width grid centred inside the (wider) padded scroll rather than
	# stretched/left-aligned, so the cards stay centred with the glow room on both sides.
	_skins_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_skins_grid.add_theme_constant_override("h_separation", int(SKIN_CARD_GAP))
	_skins_grid.add_theme_constant_override("v_separation", int(SKIN_CARD_GAP))
	pad.add_child(_skins_grid)
	_skins_by_id.clear()
	var live_defs := _live_skin_defs()
	for i in live_defs.size():
		var def: Dictionary = live_defs[i]
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
		# SPECIAL SKINS previews are STATIC thumbnails: render one settled frame, then
		# freeze. Several live 3D wheels (each with shadows + bloom, and Volcano's coal
		# animating forever) redrawing at once was the skins-tab lag. The still is
		# captured behind the loading veil and held with ~zero ongoing cost.
		wheel.set_static_preview(true)
		_skins_by_id[def["id"]] = card
		if incremental:
			await get_tree().process_frame
			if not is_inside_tree():
				return
	_refresh_skin_cards()

# Placeholder shown while the SPECIAL SKINS tab is detached (_skins_coming_soon).
# A single centred glass card in the shop's visual language: no live wheels, no
# purchase flow — just a "Coming soon" note. _skins_root is a plain Control here
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
	title.text = "Coming soon…"
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
	sub.text = "New special skins are on the way."
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
	# Per-skin two-tone frame: a bold PRIMARY border in the skin's colour with a soft
	# SECONDARY outer glow, so each card's frame reads as part of the world it previews.
	var frame: Array = _skin_frame(skin_id)
	var primary: Color = frame[0]
	var secondary: Color = frame[1]
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.06, 0.08, 0.20, 0.94)
	cs.set_corner_radius_all(24)
	cs.border_color = Color(primary.r, primary.g, primary.b, 0.90)
	cs.set_border_width_all(3)
	cs.shadow_color = Color(secondary.r, secondary.g, secondary.b, 0.45)
	cs.shadow_size = 20
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
	# Faint inner rim tinted with the skin's primary so the inset echoes the outer frame.
	clip_st.border_color = Color(primary.r, primary.g, primary.b, 0.22)
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
	# wheel (same trick as the frame previews use).
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
	# preview works precisely because it configures its wheel in-tree.

	# A skin that brings its own button frame says so, on the preview rather than in
	# the copy: one small chip in the skin's own colour, tucked into the corner of the
	# inset. The card already carries a title, a blurb and a price — anything larger
	# than this and the grid starts to read as a spec sheet.
	if not ButtonFrames.frame_for_skin(skin_id).is_empty():
		clip.add_child(_skin_frame_chip(primary, clip.size))

	# Name + blurb, below the preview.
	var name_lbl := Label.new()
	name_lbl.text = String(def["label"])
	name_lbl.add_theme_font_size_override("font_size", 26)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	name_lbl.add_theme_color_override("font_shadow_color", Color(secondary.r, secondary.g, secondary.b, 0.55))
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
	# PASS so a press-and-drag that starts on the button still reaches the
	# ScrollContainer; a plain tap still registers as a click.
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(btn)
	var price := _make_price_content(CoinsManager.skin_price(skin_id), 13.0, 22, 52.0)
	btn.add_child(price["box"])
	btn.pressed.connect(func() -> void: _on_skin_action(skin_id))
	return {
		"root": root, "btn": btn, "price_box": price["box"],
		"price_label": price["label"], "accent": primary, "preview": wheel,
	}

# The "this skin dresses your buttons too" chip. Sits inside the preview inset,
# bottom-right, so it reads as a label ON the thing it describes.
func _skin_frame_chip(accent: Color, area: Vector2) -> Panel:
	var chip := Panel.new()
	var w := 152.0
	var h := 24.0
	chip.size = Vector2(w, h)
	chip.position = Vector2(area.x - w - 10.0, area.y - h - 10.0)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.04, 0.05, 0.12, 0.82)
	st.set_corner_radius_all(int(h * 0.5))
	st.border_color = Color(accent.r, accent.g, accent.b, 0.75)
	st.set_border_width_all(1)
	chip.add_theme_stylebox_override("panel", st)
	var l := Label.new()
	l.text = "EXCLUSIVE FRAME"
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", accent.lightened(0.35))
	l.size = Vector2(w, h)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(l)
	return chip

# The [primary border, secondary glow] frame colours for a skin's shop card, or the
# shared pink fallback for any skin without a bespoke pair. See SKIN_FRAME_COLORS.
func _skin_frame(skin_id: String) -> Array:
	return SKIN_FRAME_COLORS.get(skin_id, [SKIN_ACCENT, SKIN_ACCENT])

func _refresh_skin_cards() -> void:
	for skin_id in _skins_by_id:
		_apply_skin_card_state(skin_id, _skins_by_id[skin_id])

# Mirror of _apply_card_state for skin cards. The "equipped" state additionally
# requires simon_mode == SKIN — equipping a manual per-part colour switches the
# mode back to MANUAL, at which point even the formerly-selected skin reads as
# merely OWNED, not equipped.
func _apply_skin_card_state(skin_id: String, c: Dictionary) -> void:
	var owned := CoinsManager.owns_skin(skin_id)
	var equipped := (not CoinsManager.is_simon_manual()) and CoinsManager.selected_skin == skin_id
	var affordable := CoinsManager.can_afford_skin(skin_id)
	_style_card_button(c["btn"], c["price_box"], c["price_label"], c["accent"], 14,
		_card_state(owned, equipped, affordable), owned)

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
	if _skins_coming_soon():
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

# ---------------- loading overlay ----------------

func _build_loading_overlay() -> void:
	_ov = Panel.new()
	_ov.mouse_filter = Control.MOUSE_FILTER_STOP   # swallow taps while loading
	_ov.z_index = 100                              # above cards, tabs, and the orbit orbs
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.008, 0.020, 0.075, 0.985)
	_ov.add_theme_stylebox_override("panel", s)
	add_child(_ov)

	# Nothing here is animated in the tween/spinner sense. On the GL-compatibility
	# renderer, first shop-open compiles ~20 preview shaders + the skin wheels, and each
	# compile is a hard render-thread stall that delivers no frame; anything meant to move
	# smoothly — even a caption whose trailing dots change — freezes and jerks through
	# those stalls. So the caption is fixed and the bar below steps on MILESTONES only,
	# which makes a stall read as honest progress rather than a broken animation.
	_ov_caption = Label.new()
	_ov_caption.text = "Loading…"
	_ov_caption.add_theme_font_size_override("font_size", 24)
	_ov_caption.add_theme_color_override("font_color", Color(0.78, 0.84, 1.0, 0.92))
	_ov_caption.add_theme_color_override("font_shadow_color", Color(0.30, 0.45, 1.0, 0.35))
	_ov_caption.add_theme_constant_override("shadow_offset_x", 0)
	_ov_caption.add_theme_constant_override("shadow_offset_y", 0)
	_ov_caption.add_theme_constant_override("shadow_outline_size", 6)
	_ov_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ov_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ov.add_child(_ov_caption)

	# Flat-stylebox ProgressBar: repaints only when `value` changes, so it costs
	# nothing while a stage grinds. Same palette as the boot loading screen's bar.
	_ov_bar = ProgressBar.new()
	_ov_bar.min_value = 0.0
	_ov_bar.max_value = 100.0
	_ov_bar.value = 0.0
	_ov_bar.show_percentage = false
	_ov_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.09, 0.16, 0.36, 0.95)
	track.border_color = Color(0.30, 0.45, 1.0, 0.30)
	track.set_border_width_all(1)
	track.set_corner_radius_all(int(OV_BAR_H * 0.5))
	_ov_bar.add_theme_stylebox_override("background", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.42, 0.60, 1.0, 1.0)
	fill.set_corner_radius_all(int(OV_BAR_H * 0.5))
	_ov_bar.add_theme_stylebox_override("fill", fill)
	_ov.add_child(_ov_bar)

	_ov.visible = false
	_layout_loading()

func _layout_loading() -> void:
	if _ov == null:
		return
	var sz := get_viewport_rect().size
	_ov.position = Vector2.ZERO
	_ov.size = sz
	if _ov_caption:
		_ov_caption.size = Vector2(320, 32)
		_ov_caption.position = Vector2(sz.x * 0.5 - 160, sz.y * 0.5 - 28)
	if _ov_bar:
		_ov_bar.size = Vector2(OV_BAR_W, OV_BAR_H)
		_ov_bar.position = Vector2(sz.x * 0.5 - OV_BAR_W * 0.5, sz.y * 0.5 + 14)

# Monotonic, so a stage that resolves early (nothing left to compile, skins tab
# detached) can only push the bar forward, never snap it back.
func _set_load_progress(v: float) -> void:
	_ov_progress = maxf(_ov_progress, clampf(v, 0.0, 1.0))
	if _ov_bar:
		_ov_bar.value = _ov_progress * 100.0

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
	if _frames_root:
		# Reserve the scrollbar's width so the cards themselves stay visually centred,
		# exactly as the THEMES grid does.
		var fscroll_w := FRAMES_PANEL_W + GRID_SCROLLBAR_W
		_frames_root.position = Vector2(cx - fscroll_w * 0.5, content_y)
		_frames_root.size = Vector2(fscroll_w,
			maxf(0.0, sz.y - content_y - GRID_BOTTOM_MARGIN))
	if _skins_root:
		var sgrid_w := SKIN_GRID_COLS * SKIN_CARD_W + (SKIN_GRID_COLS - 1) * SKIN_CARD_GAP
		# Reserve scrollbar width + the frame-glow padding (both sides) so the cards stay
		# visually centred and their side glow has room.
		var sscroll_w := sgrid_w + SKIN_GRID_SCROLLBAR_W + 2.0 * SKIN_FRAME_PAD
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
