extends Control

const ArenaUI := preload("res://arena_ui.gd")

# Premium leaderboard screen — same visual language as the home / difficulty /
# how-to-play screens: deep-space shader background, rotating orbit of glowing
# orbs, glass back button, gold trophy header with diamond-decorated underline.
#
# Layout (redesigned): a centered header (trophy + dynamic title + underline),
# then a control row with the TODAY / ALL-TIME range toggle on the left and the
# EASY / MODERATE / HARD difficulty BUTTONS on the right, then the two columns:
#
#   LEFT  — a glass panel "NEARBY YOUR RANK" (its title sits inside the frame):
#           3 players above the signed-in player, the player's own highlighted row,
#           and 3 below — kept a full 7-row window even at an edge (e.g. a 1st-place
#           player shows 6 below). Never a podium; it exists purely to help the
#           player find themselves.
#   RIGHT — the global Top 10. The three highest scores stand on a fully drawn
#           PODIUM: a rectangular stage carrying three medal-tinted blocks (2nd
#           left, 1st center, 3rd right), each crowned with a gold / silver /
#           bronze trophy cup that carries the player's name and score. Below the
#           podium a separate glass panel frames the thin minimal ranks 4–10
#           table. The left glass frame hugs its rows tightly.
#
# A footer line ("Scores are updated in real time") sits centered at the bottom.
# Both ranges load when the screen opens (ALL-TIME shown first) so the toggle
# flips instantly; a full-screen orbiting-orb loading overlay covers the board
# while the first fetch is in flight. Built with Godot nodes + shaders + tweens;
# no PNG/MP3 — all art is procedural.

var game_manager: Node

const ORB_COLORS := [
	Color(1.00, 0.82, 0.29),  # yellow
	Color(0.90, 0.28, 0.30),  # red
	Color(0.55, 0.36, 0.96),  # purple
	Color(0.18, 0.78, 0.39),  # green
	Color(0.23, 0.51, 0.96),  # blue
]

# Data keys (LeaderboardManager still uses "moderate"); display labels can differ.
const DIFFS: Array[String] = ["easy", "moderate", "hard"]
# Labels + icons MUST match the difficulty selection screen so the player
# associates the same chip on both screens with the same mode (EASY ↔ leaf,
# MODERATE ↔ chart, HARD ↔ flame).
const TAB_DEFS := [
	{"diff": "easy", "label": "EASY", "icon": "leaf",
		"accent": Color(0.28, 0.82, 0.45)},
	{"diff": "moderate", "label": "MODERATE", "icon": "chart",
		"accent": Color(1.00, 0.72, 0.25)},
	{"diff": "hard", "label": "HARD", "icon": "flame",
		"accent": Color(0.95, 0.32, 0.40)},
]

const GOLD := Color(1.0, 0.85, 0.2)
const SILVER := Color(0.78, 0.85, 0.98)
const BRONZE := Color(0.88, 0.55, 0.28)

# Premium white-ish stroke ringing the rank numbers in both lists.
const RANK_STROKE := Color(0.92, 0.95, 1.0, 0.85)

# Glass panel accent (subtle purple glow shared by both columns).
const PANEL_ACCENT := Color(0.55, 0.40, 1.00)

# ---- panel geometry (design space; the pair is centered in the viewport) ----
const PANEL_W := 586.0
const PANEL_GAP := 28.0
const PANEL_PAD := 16.0
# Row widths for the two list tables. Kept tight so the name and score read as a
# compact pair instead of sprawling with a big empty gap between them. The rows
# are centered in their (wider) column slot, which the toggle/tabs align to. The
# right table (Top-10) is a touch wider than the left so its larger rows breathe.
const LEFT_ROW_W := 344.0
const RIGHT_ROW_W := 364.0
# The visible glass frame hugs the rows: a row's width plus padding on each side,
# centered inside the column slot.
const LEFT_FRAME_W := LEFT_ROW_W + 2.0 * PANEL_PAD
const RIGHT_FRAME_W := RIGHT_ROW_W + 2.0 * PANEL_PAD

# Left "Nearby your rank" list metrics.
const NEARBY_HEADER_H := 46.0
const NEARBY_ROW_H := 38.0
const NEARBY_ME_H := 54.0
const NEARBY_GAP := 3.0
const NEARBY_SIDE := 3                        # players shown above/below the player

# Right column podium + ranks 4–10 table metrics. The Top-3 is rendered as a
# fully drawn podium: a rectangular stage carrying three medal-tinted blocks
# (2nd on the left, 1st in the center, 3rd on the right), each crowned with a
# gold / silver / bronze trophy cup that has the player's name and score written
# on it. The ranks 4–10 table sits in its glass frame below the podium.
const TOP3_AREA_H := 270.0
const TOP3_COLORS := [GOLD, SILVER, BRONZE]    # 1st gold, 2nd silver, 3rd bronze
const TABLE_ROW_H := 27.0
const TABLE_GAP := 4.0

# Both lists always show a fixed 7 slots, so the glass frames are sized from these
# constants (NOT from the live child list, which on a difficulty toggle still
# holds the just-queue_free'd old rows for one frame and would over-grow). The
# nearby list is 6 normal rows + 1 taller "me" row; the table is 7 equal rows.
const NEARBY_SLOTS := 2 * NEARBY_SIDE + 1
const NEARBY_LIST_H := (NEARBY_SLOTS - 1) * NEARBY_ROW_H + NEARBY_ME_H \
	+ (NEARBY_SLOTS - 1) * NEARBY_GAP
const TABLE_SLOTS := 7
const TABLE_LIST_H := TABLE_SLOTS * TABLE_ROW_H + (TABLE_SLOTS - 1) * TABLE_GAP

# Podium geometry (podium-local space; the podium node is anchored at the
# horizontal center / top of the right column slot). y grows downward. Sized to
# fill the right column width and stand tall while still clearing the ranks 4–10
# table below it at the 720-tall design height.
const POD_BASE_Y := 244.0          # stage top FRONT edge (blocks stand on this)
const POD_STAGE_W := 548.0         # stage width (nearly the full right column)
const POD_STAGE_FH := 22.0         # stage front-face height (depth toward viewer)
const POD_STAGE_DEPTH := 34.0      # top-surface perspective recede (upward)
const POD_STAGE_SKEW := 14.0       # top-surface perspective recede (rightward)
const POD_BLOCK_DEPTH := 16.0      # per-block top-face recede (upward)
const POD_BLOCK_SKEW := 9.0        # per-block top-face recede (rightward)
# Per rank: block width, block height, cup height. 1st is tallest/biggest. Block
# widths are kept just under the difficulty-tab pitch (138) so adjacent blocks
# sit a hair apart rather than overlapping when aligned under the tabs.
const POD_PILLARS := {
	1: {"bw": 140.0, "bh": 60.0, "ch": 150.0},
	2: {"bw": 130.0, "bh": 42.0, "ch": 128.0},
	3: {"bw": 130.0, "bh": 30.0, "ch": 116.0},
}

const BG_SHADER := "
shader_type canvas_item;
uniform float aspect = 0.5;
float star(vec2 uv, vec2 c, float r) { return smoothstep(r, 0.0, distance(uv, c)); }
void fragment() {
	vec2 uv = UV;
	vec3 top = vec3(0.008, 0.020, 0.102);   // #02051A
	vec3 bot = vec3(0.071, 0.000, 0.169);   // #12002B
	vec3 col = mix(top, bot, uv.y);

	vec2 p = (uv - vec2(0.5)) * vec2(aspect, 1.0);

	// nebula blobs (very low opacity)
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
var _orbit: Node2D
var _ring_glow: Line2D
var _ring_line: Line2D
var _orbs: Array[Node2D] = []
var _orb_tex: Texture2D
var _header: Control
var _trophy: Node2D
var _underline: Control
var _back: Button
var _tab_row: HBoxContainer
var _tabs: Array[Dictionary] = []   # { wrap, btn, def, label, underline }

# Two glass columns. Both are plain visual backgrounds (mouse-ignore); their
# content (lists / podium / headers) are separate top-level nodes positioned
# over them in _layout, so nothing has to fight the panels for input.
var _left_panel: Panel
var _right_panel: Panel
var _nearby_header: Control
var _nearby_list: VBoxContainer
var _nearby_empty: Label
var _table_list: VBoxContainer
var _table_empty: Label
var _footer: Control

# Podium: a Node2D holding the drawn stage + three medal blocks + trophy cups,
# rebuilt on each render (cheap — a handful of polygons). Stands where the old
# free-text Top-3 was, in the right column above the ranks 4–10 table.
var _podium: Node2D

# A pair of stage spotlights flanking the podium: each a little "can" projector on
# the floor (left + right of the stage) firing a soft white beam up-and-inward, so
# the light fans BEHIND the trophy cups and their names. Drawn before the podium so
# the beams sit behind it; the heads gently sway + pulse (see _start_animations).
var _spotlights: Node2D
var _spot_heads: Array[Node2D] = []
const SPOT_AIM := 0.40        # base inward tilt of each beam (radians)
const SPOT_SWAY := 0.12       # how far the head swings either side of SPOT_AIM
const SPOT_LEN := 290.0       # beam length (reaches above the tallest cup + name)

var _overlay: Panel
var _overlay_msg: Label
var _overlay_retry: Button
# Full-screen loading state: a fixed "Loading…" caption (same still frame as the
# boot loader) shown over a near-opaque backdrop.
var _ov_spinner: Control
var _ov_caption: Label
var _ov_box: VBoxContainer

# Range toggle (TODAY ⇄ ALL-TIME). Default is ALL-TIME (the headline board most
# players expect to see first). Both ranges are fetched when the screen opens,
# so the toggle flips between them instantly.
const RANGE_DAILY := "daily"
const RANGE_ALL := "all_time"
const RANGE_DEFS := [
	{"key": RANGE_DAILY, "label": "TODAY",    "accent": Color(0.55, 0.82, 1.00)},
	{"key": RANGE_ALL,   "label": "ALL-TIME", "accent": Color(1.00, 0.84, 0.35)},
]
const RANGE_TOGGLE_W := 216.0
const RANGE_TOGGLE_H := 44.0        # matches TAB_H so toggle + difficulty tabs share a baseline
var _range_toggle: Control
var _range_segs: Array[Dictionary] = []   # per seg: { wrap, btn, stylebox, label, accent, key }
# Title text is dynamic: "TODAY'S BEST" / "ALL-TIME BEST", swapped on toggle.
var _title_lbl: Label

var _current_diff := "easy"
var _current_range := RANGE_ALL
# Per-range cache so flipping the toggle is instant once both ranges have been
# fetched at least once. Shape: { diff: { rows, my_row, my_rank, neighborhood, ok } }.
var _caches: Dictionary = {RANGE_DAILY: {}, RANGE_ALL: {}}
var _loaded_ranges: Dictionary = {RANGE_DAILY: false, RANGE_ALL: false}
var _load_token := 0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_orb_tex = _make_radial_texture()
	_build_background()
	_build_orbit()
	_build_panels()
	_build_back()
	_build_header()
	_build_range_toggle()
	_build_tabs()
	_build_spotlights()
	_build_podium()
	_build_lists()
	_build_footer()
	_build_overlay()
	_layout()
	get_viewport().size_changed.connect(_layout)
	_start_animations()
	_intro()
	_load_initial()

# DEV-ONLY: one-off histogram backfill/rebuild trigger. `OS.has_feature("editor")`
# is true ONLY when running from the Godot editor, so this never exists in the
# shipped APK. Running the game in the editor talks to production Firestore over
# REST, so opening Leaderboards there and pressing F9 rebuilds every all-time
# histogram from the authoritative rows. Re-runnable any time to heal drift.
func _input(event: InputEvent) -> void:
	if not OS.has_feature("editor"):
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_F9:
		_dev_rebuild_histograms()

func _dev_rebuild_histograms() -> void:
	print("[hist] rebuilding all-time histograms from rows…")
	var summary: Dictionary = await LeaderboardManager.rebuild_histograms()
	var all_ok := true
	for board in summary:
		var s: Dictionary = summary[board]
		if not bool(s.get("write_ok", false)):
			all_ok = false
		print("[hist]   %s: rows=%d distinct=%d  commit_http=%d  write_ok=%s"
			% [board, int(s.get("rows", 0)), int(s.get("distinct_scores", 0)),
				int(s.get("write_code", 0)), str(s.get("write_ok", false))])
	# The headline answer to "did the unauthenticated :commit writes succeed?"
	if all_ok:
		print("[hist] ✅ WRITES OK — histogram commits landed (verified by read-back).")
	else:
		print("[hist] ❌ WRITES FAILED — check commit_http above. 401/403 = rules/auth ",
			"blocked the unauthenticated commit; 400 = malformed body; 0 = no network.")

func _is_rtl() -> bool:
	return is_layout_rtl()

# ---------------- background ----------------

func _build_background() -> void:
	# Skip when a shop theme is equipped — BackgroundManager handles it globally.
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

# ---------------- orbit + orbs ----------------

func _build_orbit() -> void:
	_orbit = Node2D.new()
	add_child(_orbit)
	_ring_glow = _make_ring(7.0, Color(0.45, 0.42, 1.0, 0.07))
	_orbit.add_child(_ring_glow)
	_ring_line = _make_ring(2.0, Color(0.60, 0.58, 1.0, 0.18))
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

# ---------------- glass panels ----------------

func _build_panels() -> void:
	_left_panel = _make_glass_panel()
	add_child(_left_panel)
	_right_panel = _make_glass_panel()
	add_child(_right_panel)

# A premium glassmorphism container: translucent deep-navy fill, rounded corners,
# a thin purple rim and a soft purple outer glow. Both columns share it so they
# read as a matched pair.
func _make_glass_panel() -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.0, 0.0, 0.0, 0.88)
	s.set_corner_radius_all(28)
	s.border_color = Color(PANEL_ACCENT.r, PANEL_ACCENT.g, PANEL_ACCENT.b, 0.45)
	s.set_border_width_all(1)
	s.shadow_color = Color(PANEL_ACCENT.r, PANEL_ACCENT.g, PANEL_ACCENT.b, 0.22)
	s.shadow_size = 22
	p.add_theme_stylebox_override("panel", s)
	return p

# ---------------- back button ----------------

func _build_back() -> void:
	# Icon-only "<" back cap, matching the Arena screen's back button.
	_back = ArenaUI.make_back_button()
	_back.pressed.connect(func() -> void: game_manager.show_home())
	add_child(_back)

# ---------------- header ----------------

# Compressed header so both panels fit under it at 720h.
const HEADER_W := 720.0
const HEADER_H := 104.0

func _build_header() -> void:
	_header = Control.new()
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.custom_minimum_size = Vector2(HEADER_W, HEADER_H)
	_header.size = Vector2(HEADER_W, HEADER_H)
	add_child(_header)

	_trophy = _make_trophy(20.0, GOLD)
	_trophy.position = Vector2(HEADER_W * 0.5, 16)
	_header.add_child(_trophy)

	_title_lbl = Label.new()
	_title_lbl.text = _title_for_range(_current_range)
	_title_lbl.add_theme_font_size_override("font_size", 38)
	_title_lbl.add_theme_color_override("font_color", Color.WHITE)
	_title_lbl.add_theme_color_override("font_outline_color", Color(1, 1, 1, 1))
	_title_lbl.add_theme_constant_override("outline_size", 2)             # faux-bold
	_title_lbl.add_theme_color_override("font_shadow_color", Color(0.20, 0.40, 1.0, 0.40))
	_title_lbl.add_theme_constant_override("shadow_offset_x", 0)
	_title_lbl.add_theme_constant_override("shadow_offset_y", 4)
	_title_lbl.add_theme_constant_override("shadow_outline_size", 9)
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_lbl.offset_top = 30
	_title_lbl.offset_bottom = -22
	_title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.add_child(_title_lbl)

	# Thin glowing blue underline with a small diamond in the center.
	_underline = Control.new()
	_underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_underline.size = Vector2(420, 14)
	_underline.position = Vector2((HEADER_W - 420) * 0.5, HEADER_H - 18)
	_header.add_child(_underline)
	var ul_line_l := ColorRect.new()
	ul_line_l.color = Color(0.50, 0.58, 1.0, 0.55)
	ul_line_l.size = Vector2(190, 2)
	ul_line_l.position = Vector2(0, 6)
	ul_line_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_underline.add_child(ul_line_l)
	var ul_line_r := ColorRect.new()
	ul_line_r.color = Color(0.50, 0.58, 1.0, 0.55)
	ul_line_r.size = Vector2(190, 2)
	ul_line_r.position = Vector2(230, 6)
	ul_line_r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_underline.add_child(ul_line_r)
	var diamond := _make_diamond(11.0, Color(0.65, 0.72, 1.0))
	diamond.position = Vector2(210, 7)
	_underline.add_child(diamond)

# Stylized trophy: cup body + handles + stem + base, with a soft golden bloom.
func _make_trophy(s: float, col: Color) -> Node2D:
	var n := Node2D.new()
	var halo := Sprite2D.new()
	halo.texture = _orb_tex
	halo.modulate = Color(col.r, col.g, col.b, 0.45)
	halo.scale = Vector2.ONE * (s * 2.6 / 128.0)
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	halo.material = add_mat
	n.add_child(halo)
	var cup := Polygon2D.new()
	cup.polygon = PackedVector2Array([
		Vector2(-s * 0.55, -s * 0.85), Vector2(s * 0.55, -s * 0.85),
		Vector2(s * 0.40,  s * 0.05),  Vector2(-s * 0.40, s * 0.05)
	])
	cup.color = col
	n.add_child(cup)
	var rim := Polygon2D.new()
	rim.polygon = PackedVector2Array([
		Vector2(-s * 0.55, -s * 0.92), Vector2(s * 0.55, -s * 0.92),
		Vector2(s * 0.50,  -s * 0.78), Vector2(-s * 0.50, -s * 0.78)
	])
	rim.color = col.lightened(0.35)
	n.add_child(rim)
	var hl := Line2D.new()
	hl.width = s * 0.10
	hl.default_color = col
	hl.antialiased = true
	hl.points = PackedVector2Array([
		Vector2(-s * 0.55, -s * 0.70), Vector2(-s * 0.95, -s * 0.55),
		Vector2(-s * 0.95, -s * 0.18), Vector2(-s * 0.55, -s * 0.10)
	])
	n.add_child(hl)
	var hr := Line2D.new()
	hr.width = s * 0.10
	hr.default_color = col
	hr.antialiased = true
	hr.points = PackedVector2Array([
		Vector2(s * 0.55, -s * 0.70), Vector2(s * 0.95, -s * 0.55),
		Vector2(s * 0.95, -s * 0.18), Vector2(s * 0.55, -s * 0.10)
	])
	n.add_child(hr)
	var stem := Polygon2D.new()
	stem.polygon = PackedVector2Array([
		Vector2(-s * 0.14, s * 0.05), Vector2(s * 0.14, s * 0.05),
		Vector2( s * 0.10, s * 0.30), Vector2(-s * 0.10, s * 0.30)
	])
	stem.color = col.darkened(0.10)
	n.add_child(stem)
	var base := Polygon2D.new()
	base.polygon = PackedVector2Array([
		Vector2(-s * 0.40, s * 0.30), Vector2(s * 0.40, s * 0.30),
		Vector2( s * 0.50, s * 0.42), Vector2(-s * 0.50, s * 0.42)
	])
	base.color = col.darkened(0.15)
	n.add_child(base)
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

# ---------------- tabs ----------------

const TAB_SEP := 14                # text-tab gap
const TAB_W := 124.0
const TAB_H := 44.0

func _build_tabs() -> void:
	_tab_row = HBoxContainer.new()
	_tab_row.add_theme_constant_override("separation", TAB_SEP)
	add_child(_tab_row)
	_tabs.clear()
	for def in TAB_DEFS:
		_tabs.append(_make_tab(def))
	_refresh_tab_styles()

# A real pill button (same visual language as the TODAY/ALL-TIME range toggle):
# a rounded accent-tinted background with an accent border. The selected button
# fills brighter, gains a glowing accent border + soft shadow and pops slightly;
# the others sit subdued. Two styleboxes are built once and swapped on selection.
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

	var active_sb := StyleBoxFlat.new()
	active_sb.bg_color = Color(accent.r, accent.g, accent.b, 0.18)
	active_sb.set_corner_radius_all(int(TAB_H * 0.5))
	active_sb.border_color = Color(accent.r, accent.g, accent.b, 0.95)
	active_sb.set_border_width_all(2)
	active_sb.shadow_color = Color(accent.r, accent.g, accent.b, 0.45)
	active_sb.shadow_size = 14
	var idle_sb := StyleBoxFlat.new()
	idle_sb.bg_color = Color(0.06, 0.08, 0.20, 0.55)
	idle_sb.set_corner_radius_all(int(TAB_H * 0.5))
	idle_sb.border_color = Color(accent.r, accent.g, accent.b, 0.32)
	idle_sb.set_border_width_all(1)
	for st_name in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(st_name, idle_sb)
	wrap.add_child(btn)

	var lbl := Label.new()
	lbl.text = def["label"]
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", accent)
	lbl.add_theme_color_override("font_shadow_color",
		Color(accent.r, accent.g, accent.b, 0.0))
	lbl.add_theme_constant_override("shadow_offset_x", 0)
	lbl.add_theme_constant_override("shadow_offset_y", 0)
	lbl.add_theme_constant_override("shadow_outline_size", 8)
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(lbl)

	btn.pressed.connect(func() -> void: _on_tab(def["diff"]))
	_tab_row.add_child(wrap)
	return {"wrap": wrap, "btn": btn, "def": def, "label": lbl,
		"active_sb": active_sb, "idle_sb": idle_sb}

func _refresh_tab_styles() -> void:
	for t in _tabs:
		var def: Dictionary = t["def"]
		var accent: Color = def["accent"]
		var active: bool = def["diff"] == _current_diff
		var lbl: Label = t["label"]
		var btn: Button = t["btn"]
		var sb: StyleBoxFlat = t["active_sb"] if active else t["idle_sb"]
		for st_name in ["normal", "hover", "pressed", "focus"]:
			btn.add_theme_stylebox_override(st_name, sb)
		lbl.add_theme_color_override("font_color",
			accent.lightened(0.35) if active else Color(accent.r, accent.g, accent.b, 0.70))
		lbl.add_theme_color_override("font_shadow_color",
			Color(accent.r, accent.g, accent.b, 0.55 if active else 0.0))
		var tw := create_tween()
		tw.tween_property(btn, "scale",
			Vector2.ONE * (1.06 if active else 1.0), 0.18) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_tab(diff: String) -> void:
	if diff == _current_diff:
		return
	_current_diff = diff
	_refresh_tab_styles()
	if _loaded_ranges[_current_range]:
		_render(_caches[_current_range].get(diff, {}))

# ---------------- range toggle (TODAY ⇄ ALL-TIME) ----------------

func _build_range_toggle() -> void:
	_range_toggle = Control.new()
	_range_toggle.custom_minimum_size = Vector2(RANGE_TOGGLE_W, RANGE_TOGGLE_H)
	_range_toggle.size = Vector2(RANGE_TOGGLE_W, RANGE_TOGGLE_H)
	_range_toggle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_range_toggle)

	var bg := Panel.new()
	bg.size = Vector2(RANGE_TOGGLE_W, RANGE_TOGGLE_H)
	bg.position = Vector2.ZERO
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.04, 0.06, 0.18, 0.85)
	bs.set_corner_radius_all(int(RANGE_TOGGLE_H * 0.5))
	bs.border_color = Color(0.55, 0.62, 0.95, 0.35)
	bs.set_border_width_all(1)
	bs.shadow_color = Color(0.20, 0.32, 0.85, 0.22)
	bs.shadow_size = 10
	bg.add_theme_stylebox_override("panel", bs)
	_range_toggle.add_child(bg)

	var sep := ColorRect.new()
	sep.color = Color(0.62, 0.68, 0.95, 0.18)
	sep.size = Vector2(1, RANGE_TOGGLE_H - 22.0)
	sep.position = Vector2(RANGE_TOGGLE_W * 0.5 - 0.5, 11.0)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_range_toggle.add_child(sep)

	var seg_w := RANGE_TOGGLE_W * 0.5
	for i in RANGE_DEFS.size():
		var def: Dictionary = RANGE_DEFS[i]
		_range_segs.append(_make_range_seg(def, Vector2(i * seg_w, 0), Vector2(seg_w, RANGE_TOGGLE_H)))
	_refresh_range_styles()

func _make_range_seg(def: Dictionary, pos: Vector2, size: Vector2) -> Dictionary:
	var accent: Color = def["accent"]

	var btn := Button.new()
	btn.size = size
	btn.position = pos
	btn.pivot_offset = size * 0.5
	btn.focus_mode = Control.FOCUS_NONE
	var s := StyleBoxFlat.new()
	s.bg_color = Color(accent.r, accent.g, accent.b, 0.14)
	s.set_corner_radius_all(int(size.y * 0.5))
	s.border_color = Color(accent.r, accent.g, accent.b, 0.9)
	s.set_border_width_all(2)
	s.shadow_color = Color(accent.r, accent.g, accent.b, 0.45)
	s.shadow_size = 14
	var empty := StyleBoxEmpty.new()
	for st_name in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(st_name, empty)
	btn.add_theme_color_override("font_color", Color(0.78, 0.84, 1.0))
	_range_toggle.add_child(btn)

	var lbl := Label.new()
	lbl.text = def["label"]
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", accent.lightened(0.05))
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(lbl)

	btn.pressed.connect(func() -> void: _on_range(def["key"]))
	return {"btn": btn, "stylebox": s, "label": lbl, "accent": accent, "key": def["key"]}

func _refresh_range_styles() -> void:
	for seg in _range_segs:
		var active: bool = seg["key"] == _current_range
		var accent: Color = seg["accent"]
		var s: StyleBoxFlat = seg["stylebox"]
		var btn: Button = seg["btn"]
		var lbl: Label = seg["label"]
		if active:
			for st_name in ["normal", "hover", "pressed", "focus"]:
				btn.add_theme_stylebox_override(st_name, s)
			lbl.add_theme_color_override("font_color", accent.lightened(0.35))
		else:
			var empty := StyleBoxEmpty.new()
			for st_name in ["normal", "hover", "pressed", "focus"]:
				btn.add_theme_stylebox_override(st_name, empty)
			lbl.add_theme_color_override("font_color", Color(0.62, 0.68, 0.92, 0.85))
		create_tween().tween_property(btn, "scale",
			Vector2.ONE * (1.05 if active else 1.0), 0.18) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_range(key: String) -> void:
	if key == _current_range:
		return
	_current_range = key
	_refresh_range_styles()
	_update_title()
	if _loaded_ranges[_current_range]:
		_render(_caches[_current_range].get(_current_diff, {}))
	else:
		_load_range(_current_range)

func _title_for_range(range_key: String) -> String:
	return "TODAY'S BEST" if range_key == RANGE_DAILY else "ALL-TIME BEST"

func _update_title() -> void:
	if _title_lbl:
		_title_lbl.text = _title_for_range(_current_range)

# ---------------- spotlights (flanking the podium) ----------------

# Two floor spotlights, one each side of the stage, firing white beams up-and-in
# so the light fans behind the cups + names. Shares the podium's local space and
# transform (set in _layout), but is its own node added BEFORE the podium so the
# beams render behind it. The heads sway + pulse in _start_animations.
func _build_spotlights() -> void:
	_spotlights = Node2D.new()
	# Drawn in FRONT of the podium so the projector cans + beams sit on the stage
	# rather than being painted over by it; the beams are additive + low-alpha, so
	# they read as light spilling over the cups instead of washing them out.
	_spotlights.z_index = 1
	add_child(_spotlights)
	_spot_heads.clear()
	var off_x := POD_STAGE_W * 0.5 - 32.0     # standing on the stage, near its front corners
	var base_y := POD_BASE_Y - 40.0
	for dir in [1.0, -1.0]:                    # +1 = left head (aims right), -1 = right
		var head := _make_spotlight(dir)
		head.position = Vector2(-dir * off_x, base_y)
		_spotlights.add_child(head)
		_spot_heads.append(head)

# One spotlight head: built firing straight up, then rotated by `dir * SPOT_AIM` to
# aim inward over the podium. A wide soft wash + a brighter inner core (both white,
# additive, fading to transparent at the top), a lens bloom and a little can fixture.
func _make_spotlight(dir: float) -> Node2D:
	var head := Node2D.new()
	head.add_child(_make_beam(SPOT_LEN, 150.0, 0.07))   # soft outer wash
	head.add_child(_make_beam(SPOT_LEN, 82.0, 0.12))    # bright inner core
	var bloom := Sprite2D.new()
	bloom.texture = _orb_tex
	bloom.modulate = Color(1.0, 1.0, 1.0, 0.55)
	bloom.scale = Vector2.ONE * (52.0 / 128.0)
	var bm := CanvasItemMaterial.new()
	bm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	bloom.material = bm
	head.add_child(bloom)
	head.add_child(_build_projector())
	head.rotation = dir * SPOT_AIM
	return head

# A fading light beam: a tall quad, narrow at the lens (origin) and flaring toward
# the top, white and opaque-ish at the source, transparent at the far end. Additive
# so overlapping beams brighten where they cross.
func _make_beam(length: float, top_half_w: float, base_alpha: float) -> Polygon2D:
	var w0 := 12.0
	var pg := Polygon2D.new()
	pg.polygon = PackedVector2Array([
		Vector2(-w0 * 0.5, 0.0), Vector2(w0 * 0.5, 0.0),
		Vector2(top_half_w, -length), Vector2(-top_half_w, -length),
	])
	pg.color = Color.WHITE
	pg.vertex_colors = PackedColorArray([
		Color(1, 1, 1, base_alpha), Color(1, 1, 1, base_alpha),
		Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0),
	])
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	pg.material = m
	return pg

# A small "can" projector fixture sitting at the beam's origin: a tapered metal
# body with a bright lens ring and a mount foot. Drawn on top of the lens bloom.
func _build_projector() -> Node2D:
	var p := Node2D.new()
	var body := Color(0.12, 0.13, 0.20)
	# Can body (narrow at the lens, flaring slightly to the base).
	p.add_child(_poly(PackedVector2Array([
		Vector2(-13, 0), Vector2(13, 0), Vector2(17, 26), Vector2(-17, 26),
	]), body))
	# Cylinder shading down the right half.
	p.add_child(_poly(PackedVector2Array([
		Vector2(3, 0), Vector2(13, 0), Vector2(17, 26), Vector2(8, 26),
	]), body.darkened(0.35)))
	# Bright lens ring + hot inner lens.
	p.add_child(_poly_at(_ellipse_poly(14.0, 4.6, 22), Vector2(0, 0), Color(0.34, 0.37, 0.5)))
	p.add_child(_poly_at(_ellipse_poly(10.5, 3.1, 22), Vector2(0, 0.6), Color(1.0, 1.0, 0.97, 0.92)))
	# Mount foot.
	p.add_child(_poly(PackedVector2Array([
		Vector2(-9, 26), Vector2(9, 26), Vector2(12, 35), Vector2(-12, 35),
	]), Color(0.07, 0.08, 0.13)))
	return p

# ---------------- podium (right column, where the Top-3 stands) ----------------

func _build_podium() -> void:
	_podium = Node2D.new()
	add_child(_podium)

# Small filled polygon helper for the podium's flat faces.
func _poly(pts: PackedVector2Array, col: Color) -> Polygon2D:
	var pg := Polygon2D.new()
	pg.polygon = pts
	pg.color = col
	return pg

# Same, positioned at `off` (so an ellipse/disc can be placed up the cup).
func _poly_at(pts: PackedVector2Array, off: Vector2, col: Color) -> Polygon2D:
	var pg := _poly(pts, col)
	pg.position = off
	return pg

func _ellipse_poly(rx: float, ry: float, n: int) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in n:
		var a: float = TAU * float(i) / n
		p.append(Vector2(cos(a) * rx, sin(a) * ry))
	return p

# Catmull-Rom interpolation, for smooth cup handles.
func _catmull_point(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((p1 * 2.0) + (p2 - p0) * t
		+ (p0 * 2.0 - p1 * 5.0 + p2 * 4.0 - p3) * t2
		+ (p1 * 3.0 - p0 - p2 * 3.0 + p3) * t3)

func _catmull(points: PackedVector2Array, seg: int) -> PackedVector2Array:
	var n := points.size()
	if n < 2:
		return points
	var out := PackedVector2Array()
	for i in n - 1:
		var p0 := points[maxi(i - 1, 0)]
		var p1 := points[i]
		var p2 := points[i + 1]
		var p3 := points[mini(i + 2, n - 1)]
		for s in seg:
			out.append(_catmull_point(p0, p1, p2, p3, float(s) / seg))
	out.append(points[n - 1])
	return out

# Turns a centerline into a filled ribbon polygon, tapering thin toward both ends.
func _ribbon(center: PackedVector2Array, hw: float) -> PackedVector2Array:
	var n := center.size()
	if n < 2:
		return PackedVector2Array()
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in n:
		var dir: Vector2
		if i == 0:
			dir = center[1] - center[0]
		elif i == n - 1:
			dir = center[n - 1] - center[n - 2]
		else:
			dir = center[i + 1] - center[i - 1]
		if dir.length() < 0.0001:
			dir = Vector2(1, 0)
		dir = dir.normalized()
		var nrm := Vector2(-dir.y, dir.x)
		var t := float(i) / float(n - 1)
		var w := hw * (0.35 + 0.65 * sin(t * PI))   # thin at both ends, full in middle
		right.append(center[i] + nrm * w)
		left.append(center[i] - nrm * w)
	var poly := PackedVector2Array()
	for v in right:
		poly.append(v)
	for i in range(n - 1, -1, -1):
		poly.append(left[i])
	return poly

# The cup bowl as a smooth goblet silhouette with a vertical metal gradient
# (darker at the foot, brighter toward the rim; the left side a touch brighter as
# if lit from the upper-left).
func _build_bowl(u: float, medal: Color) -> Polygon2D:
	var segs := 26
	var y0 := -0.34 * u
	var y1 := -0.93 * u
	var dark := medal.darkened(0.42)
	var lite := medal.lightened(0.42)
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for i in segs + 1:                       # right side, foot → rim
		var t := float(i) / segs
		var r := u * (0.12 + 0.225 * sin(t * PI * 0.5))
		pts.append(Vector2(r, lerp(y0, y1, t)))
		cols.append(dark.lerp(lite, t))
	for i in range(segs, -1, -1):            # left side, rim → foot
		var t := float(i) / segs
		var r := u * (0.12 + 0.225 * sin(t * PI * 0.5))
		pts.append(Vector2(-r, lerp(y0, y1, t)))
		cols.append(dark.lerp(lite, t).lightened(0.10))
	var pg := Polygon2D.new()
	pg.polygon = pts
	pg.color = Color.WHITE
	pg.vertex_colors = cols
	return pg

# The score written across the cup's bowl. Tinted from the cup's own metal — a
# bright fill with a darker metal stroke (an engraved look) — so it blends into
# the cup rather than sitting on top of it. `center` is in the parent's space.
func _score_badge(center: Vector2, font_size: int, score: int, medal: Color) -> Node2D:
	var n := Node2D.new()
	n.position = center
	var l := Label.new()
	l.text = _fmt(score)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", medal.lightened(0.55))
	l.add_theme_color_override("font_outline_color", medal.darkened(0.62))
	l.add_theme_constant_override("outline_size", maxi(3, int(round(font_size * 0.16))))
	l.add_theme_color_override("font_shadow_color",
		Color(medal.darkened(0.7).r, medal.darkened(0.7).g, medal.darkened(0.7).b, 0.5))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.add_theme_constant_override("shadow_outline_size", 1)
	var lw := float(font_size) * 7.0
	var lh := float(font_size + 8)
	l.size = Vector2(lw, lh)
	l.position = Vector2(-lw * 0.5, -lh * 0.5)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.add_child(l)
	return n

# The rectangular stage: a top surface receding up-and-right, a front face and a
# right side face for depth, plus a glowing accent edge along the top front.
func _build_stage() -> Node2D:
	var n := Node2D.new()
	var hw := POD_STAGE_W * 0.5
	var by := POD_BASE_Y
	var d := POD_STAGE_DEPTH
	var sk := POD_STAGE_SKEW
	# Soft accent bloom under the stage.
	var glow := Sprite2D.new()
	glow.texture = _orb_tex
	glow.modulate = Color(PANEL_ACCENT.r, PANEL_ACCENT.g, PANEL_ACCENT.b, 0.16)
	glow.scale = Vector2(POD_STAGE_W * 1.15 / 128.0, 70.0 / 128.0)
	glow.position = Vector2(sk * 0.5, by + 4.0)
	var gm := CanvasItemMaterial.new()
	gm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = gm
	n.add_child(glow)
	# Top surface (perspective parallelogram).
	n.add_child(_poly(PackedVector2Array([
		Vector2(-hw, by), Vector2(hw, by),
		Vector2(hw + sk, by - d), Vector2(-hw + sk, by - d),
	]), Color(0.11, 0.13, 0.28, 0.97)))
	# Front face.
	n.add_child(_poly(PackedVector2Array([
		Vector2(-hw, by), Vector2(hw, by),
		Vector2(hw, by + POD_STAGE_FH), Vector2(-hw, by + POD_STAGE_FH),
	]), Color(0.05, 0.06, 0.16, 0.98)))
	# Right side face.
	n.add_child(_poly(PackedVector2Array([
		Vector2(hw, by), Vector2(hw + sk, by - d),
		Vector2(hw + sk, by - d + POD_STAGE_FH), Vector2(hw, by + POD_STAGE_FH),
	]), Color(0.03, 0.04, 0.11, 0.98)))
	# Glowing accent edge along the top front lip.
	var edge := Line2D.new()
	edge.width = 2.0
	edge.default_color = Color(PANEL_ACCENT.r, PANEL_ACCENT.g, PANEL_ACCENT.b, 0.55)
	edge.antialiased = true
	edge.points = PackedVector2Array([Vector2(-hw, by), Vector2(hw, by)])
	n.add_child(edge)
	return n

# One podium pillar: a medal-tinted 3-D block with a big rank numeral on its
# front, crowned by a trophy cup (when that rank has a player). `cx` is the
# block's center-x in podium-local space.
func _build_pillar(rank: int, cx: float, has: bool,
		player_name: String, score: int) -> Node2D:
	var spec: Dictionary = POD_PILLARS[rank]
	var bw: float = spec["bw"]
	var bh: float = spec["bh"]
	var ch: float = spec["ch"]
	var medal: Color = TOP3_COLORS[rank - 1]
	var n := Node2D.new()
	n.position = Vector2(cx, 0.0)
	var hw := bw * 0.5
	var base_y := POD_BASE_Y - 4.0
	var top_y := base_y - bh
	var d := POD_BLOCK_DEPTH
	var sk := POD_BLOCK_SKEW
	# Front face.
	n.add_child(_poly(PackedVector2Array([
		Vector2(-hw, base_y), Vector2(hw, base_y),
		Vector2(hw, top_y), Vector2(-hw, top_y),
	]), medal.darkened(0.72)))
	# Top face.
	n.add_child(_poly(PackedVector2Array([
		Vector2(-hw, top_y), Vector2(hw, top_y),
		Vector2(hw + sk, top_y - d), Vector2(-hw + sk, top_y - d),
	]), medal.darkened(0.46)))
	# Right side face.
	n.add_child(_poly(PackedVector2Array([
		Vector2(hw, base_y), Vector2(hw, top_y),
		Vector2(hw + sk, top_y - d), Vector2(hw + sk, base_y - d),
	]), medal.darkened(0.82)))
	# Glowing top-edge highlight.
	var edge := Line2D.new()
	edge.width = 2.0
	edge.default_color = Color(medal.r, medal.g, medal.b, 0.7)
	edge.antialiased = true
	edge.points = PackedVector2Array([Vector2(-hw, top_y), Vector2(hw, top_y)])
	n.add_child(edge)
	# Big rank numeral on the front face.
	var num := Label.new()
	num.text = str(rank)
	var nf := int(bh * 0.62)
	num.add_theme_font_size_override("font_size", nf)
	num.add_theme_color_override("font_color", medal.lightened(0.25))
	num.add_theme_color_override("font_shadow_color", Color(medal.r, medal.g, medal.b, 0.55))
	num.add_theme_constant_override("shadow_offset_x", 0)
	num.add_theme_constant_override("shadow_offset_y", 0)
	num.add_theme_constant_override("shadow_outline_size", 7)
	num.size = Vector2(bw, bh)
	num.position = Vector2(-hw, top_y)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.add_child(num)
	# The cup, standing on the block's top surface (or a faint placeholder).
	if has:
		var cup := _build_cup(ch, medal, player_name, score)
		cup.position = Vector2(sk * 0.4, top_y - 4.0)
		n.add_child(cup)
	else:
		var dash := Label.new()
		dash.text = "—"
		dash.add_theme_font_size_override("font_size", 26)
		dash.add_theme_color_override("font_color", Color(medal.r, medal.g, medal.b, 0.4))
		dash.size = Vector2(bw, 40)
		dash.position = Vector2(-hw, top_y - 48)
		dash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dash.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		dash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		n.add_child(dash)
	return n

# A detailed, elegant trophy cup, drawn pointing up (local y grows upward as
# negative) from its pedestal base at the origin. `ch` is the total cup height.
# Smooth shaded bowl, tiered pedestal, baluster stem with a knop, tapered handles
# and a flared rim with an inner opening — all in the medal metal. The score is
# engraved across the bowl, and the player's name floats above with a soft glow.
func _build_cup(ch: float, medal: Color, player_name: String, score: int) -> Node2D:
	var u := ch
	var cup := Node2D.new()
	var dark := medal.darkened(0.45)
	# Soft halo bloom behind the cup.
	var halo := Sprite2D.new()
	halo.texture = _orb_tex
	halo.modulate = Color(medal.r, medal.g, medal.b, 0.28)
	halo.scale = Vector2.ONE * (u * 2.6 / 128.0)
	halo.position = Vector2(0, -u * 0.62)
	var hm := CanvasItemMaterial.new()
	hm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	halo.material = hm
	cup.add_child(halo)
	# Smooth tapered handles (drawn before the bowl so it overlaps their inner
	# ends); reach is kept modest so neighbouring cups don't touch.
	for sgn in [-1.0, 1.0]:
		var ctrl := PackedVector2Array([
			Vector2(sgn * 0.21 * u, -0.58 * u),
			Vector2(sgn * 0.37 * u, -0.63 * u),
			Vector2(sgn * 0.40 * u, -0.74 * u),
			Vector2(sgn * 0.35 * u, -0.85 * u),
			Vector2(sgn * 0.22 * u, -0.885 * u),
		])
		cup.add_child(_poly(_ribbon(_catmull(ctrl, 12), 0.045 * u), medal.darkened(0.08)))
	# Tiered, rounded pedestal for an elegant footing.
	cup.add_child(_poly_at(_ellipse_poly(0.30 * u, 0.072 * u, 30), Vector2(0, -0.03 * u), dark))
	cup.add_child(_poly_at(_ellipse_poly(0.205 * u, 0.05 * u, 28), Vector2(0, -0.115 * u),
		medal.darkened(0.3)))
	cup.add_child(_poly_at(_ellipse_poly(0.13 * u, 0.038 * u, 24), Vector2(0, -0.165 * u),
		medal.darkened(0.18)))
	# Slim baluster stem with a central knop.
	cup.add_child(_poly(PackedVector2Array([
		Vector2(-0.05 * u, -0.165 * u), Vector2(0.05 * u, -0.165 * u),
		Vector2(0.04 * u, -0.22 * u), Vector2(0.05 * u, -0.30 * u),
		Vector2(0.055 * u, -0.36 * u), Vector2(-0.055 * u, -0.36 * u),
		Vector2(-0.05 * u, -0.30 * u), Vector2(-0.04 * u, -0.22 * u),
	]), medal.darkened(0.06)))
	cup.add_child(_poly_at(_ellipse_poly(0.072 * u, 0.058 * u, 22), Vector2(0, -0.25 * u),
		medal.lightened(0.08)))
	# Bowl (smooth, vertically shaded metal).
	cup.add_child(_build_bowl(u, medal))
	# Specular sheen on the upper-left of the bowl.
	var sheen := _poly_at(_ellipse_poly(0.05 * u, 0.19 * u, 18),
		Vector2(-0.135 * u, -0.64 * u), Color(1, 1, 1, 0.18))
	sheen.rotation = -0.2
	cup.add_child(sheen)
	# Flared rim with a darker inner opening (you read down into the cup).
	cup.add_child(_poly_at(_ellipse_poly(0.345 * u, 0.06 * u, 32), Vector2(0, -0.93 * u),
		medal.lightened(0.45)))
	cup.add_child(_poly_at(_ellipse_poly(0.275 * u, 0.042 * u, 32), Vector2(0, -0.923 * u),
		medal.darkened(0.5)))
	# Score engraved across the bowl in the cup's own metal.
	cup.add_child(_score_badge(Vector2(0, -0.62 * u), maxi(16, int(round(0.16 * u))),
		score, medal))
	# Player name floating ABOVE the cup: black fill, a modest medal stroke, and a
	# REAL soft glow from a radial bloom behind it (the font's hard "shadow outline"
	# only thickens the stroke, so we use an additive halo sprite for the glow).
	var nfs := maxi(15, int(round(0.15 * u)))
	var name_h := float(nfs + 8)
	var name_w := 1.5 * u
	# Sit just above the rim's top (the rim ellipse reaches ~-0.99u).
	var name_cy := -0.99 * u - 4.0 - name_h * 0.5
	var nglow := Sprite2D.new()
	nglow.texture = _orb_tex
	nglow.modulate = Color(medal.r, medal.g, medal.b, 0.65)
	nglow.scale = Vector2(name_w * 0.62 / 128.0, name_h * 1.7 / 128.0)
	nglow.position = Vector2(0, name_cy)
	var ngm := CanvasItemMaterial.new()
	ngm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	nglow.material = ngm
	cup.add_child(nglow)
	var name_lbl := Label.new()
	name_lbl.text = player_name
	name_lbl.add_theme_font_size_override("font_size", nfs)
	name_lbl.add_theme_color_override("font_color", Color.BLACK)
	name_lbl.add_theme_color_override("font_outline_color", medal)
	name_lbl.add_theme_constant_override("outline_size", maxi(3, int(round(0.028 * u))))
	name_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	name_lbl.add_theme_constant_override("shadow_offset_x", 0)
	name_lbl.add_theme_constant_override("shadow_offset_y", 1)
	name_lbl.add_theme_constant_override("shadow_outline_size", 2)
	name_lbl.size = Vector2(name_w, name_h)
	name_lbl.position = Vector2(-name_w * 0.5, name_cy - name_h * 0.5)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.clip_text = true
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cup.add_child(name_lbl)
	return cup

# ---------------- avatars ----------------

# Generic procedural avatars (we don't store real ones):
#   "me"      → blue circular badge with a white person silhouette
#   "neutral" → slate circular badge with a person silhouette (podium + table)
#   "shield"  → purple crest badge with a small star (nearby-list opponents)
func _make_avatar(size: float, kind: String) -> Node2D:
	if kind == "shield":
		return _make_shield_avatar(size)
	return _make_person_avatar(size, kind)

func _make_person_avatar(size: float, kind: String) -> Node2D:
	var n := Node2D.new()
	var r := size * 0.5
	var bg: Color = Color(0.30, 0.50, 0.95) if kind == "me" else Color(0.32, 0.36, 0.52)
	var outer := Polygon2D.new()
	outer.polygon = _circle_poly(r, 22)
	outer.color = bg.lightened(0.18)
	n.add_child(outer)
	var inner := Polygon2D.new()
	inner.polygon = _circle_poly(r * 0.86, 22)
	inner.color = bg.darkened(0.12)
	n.add_child(inner)
	var pc: Color = Color(0.94, 0.96, 1.0) if kind == "me" else Color(0.74, 0.78, 0.90)
	var head := Polygon2D.new()
	head.polygon = _circle_poly(r * 0.30, 16)
	head.position = Vector2(0, -r * 0.16)
	head.color = pc
	n.add_child(head)
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(-r * 0.42, r * 0.56), Vector2(-r * 0.30, r * 0.10),
		Vector2( r * 0.30, r * 0.10), Vector2( r * 0.42, r * 0.56),
	])
	body.color = pc
	n.add_child(body)
	return n

func _make_shield_avatar(size: float) -> Node2D:
	var n := Node2D.new()
	var r := size * 0.5
	var base := PackedVector2Array([
		Vector2(-1.00, -0.92), Vector2(1.00, -0.92),
		Vector2( 1.00,  0.18), Vector2(0.00, 1.00), Vector2(-1.00, 0.18),
	])
	var outer := Polygon2D.new()
	var op := PackedVector2Array()
	for v in base: op.append(v * r)
	outer.polygon = op
	outer.color = Color(0.50, 0.36, 0.92)
	n.add_child(outer)
	var inner := Polygon2D.new()
	var ip := PackedVector2Array()
	for v in base: ip.append(v * r * 0.78)
	inner.polygon = ip
	inner.color = Color(0.30, 0.20, 0.60)
	n.add_child(inner)
	var star := _icon_star(r * 0.40, Color(0.86, 0.88, 1.0))
	star.position = Vector2(0, -r * 0.08)
	n.add_child(star)
	return n

# ---------------- left panel: nearby-your-rank list ----------------

# A 1px-tall texture, white, opaque across the middle and fading to transparent at
# the left/right ends — stretched into the fading underline below. Built the same
# way as the orb texture (Image → ImageTexture), which renders reliably here.
func _make_hfade_tex() -> Texture2D:
	var w := 128
	var img := Image.create(w, 1, false, Image.FORMAT_RGBA8)
	for x in w:
		var t := float(x) / float(w - 1)
		var a := 1.0
		if t < 0.16:
			a = t / 0.16
		elif t > 0.84:
			a = (1.0 - t) / 0.16
		img.set_pixel(x, 0, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)

# A thin horizontal underline, solid across the middle and fading out at both
# ends, in `color` over a softer/wider additive `glow_col` halo. Built from
# stretched Sprite2Ds (not Line2D) so it renders reliably. Centered on origin.
func _make_fading_underline(total_w: float, line_w: float,
		color: Color, glow_col: Color, with_glow := true) -> Node2D:
	var n := Node2D.new()
	var tex := _make_hfade_tex()
	if with_glow:
		var glow := Sprite2D.new()
		glow.texture = tex
		glow.modulate = Color(glow_col.r, glow_col.g, glow_col.b, 0.5)
		glow.scale = Vector2(total_w / 128.0, line_w + 7.0)
		var gm := CanvasItemMaterial.new()
		gm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		glow.material = gm
		n.add_child(glow)
	var line := Sprite2D.new()
	line.texture = tex
	line.modulate = color
	line.scale = Vector2(total_w / 128.0, line_w)
	n.add_child(line)
	return n

func _build_lists() -> void:
	# Left header: "NEARBY YOUR RANK" over a thin, edge-fading purple underline.
	_nearby_header = Control.new()
	_nearby_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_nearby_header.size = Vector2(LEFT_ROW_W, NEARBY_HEADER_H)
	add_child(_nearby_header)
	var nh_lbl := Label.new()
	nh_lbl.text = "NEARBY YOUR RANK"
	nh_lbl.add_theme_font_size_override("font_size", 20)
	nh_lbl.add_theme_color_override("font_color", Color(0.80, 0.85, 1.0))
	nh_lbl.add_theme_color_override("font_shadow_color", Color(0.40, 0.45, 1.0, 0.35))
	nh_lbl.add_theme_constant_override("shadow_offset_x", 0)
	nh_lbl.add_theme_constant_override("shadow_offset_y", 0)
	nh_lbl.add_theme_constant_override("shadow_outline_size", 6)
	nh_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	nh_lbl.offset_bottom = -12.0          # sit the title in the top band, underline below
	nh_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nh_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nh_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_nearby_header.add_child(nh_lbl)
	var underline := _make_fading_underline(232.0, 3.0, Color(0.64, 0.50, 1.0), Color(1, 1, 1), false)
	underline.position = Vector2(LEFT_ROW_W * 0.5, NEARBY_HEADER_H - 8.0)
	_nearby_header.add_child(underline)

	_nearby_list = VBoxContainer.new()
	_nearby_list.add_theme_constant_override("separation", int(NEARBY_GAP))
	add_child(_nearby_list)

	_nearby_empty = Label.new()
	_nearby_empty.text = "Play a round to find\nyour place on the board."
	_nearby_empty.add_theme_font_size_override("font_size", 17)
	_nearby_empty.add_theme_color_override("font_color", Color(0.74, 0.80, 1.0))
	_nearby_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_nearby_empty.visible = false
	add_child(_nearby_empty)

	# Right table (ranks 4–10).
	_table_list = VBoxContainer.new()
	_table_list.add_theme_constant_override("separation", int(TABLE_GAP))
	add_child(_table_list)

	_table_empty = Label.new()
	_table_empty.text = "No scores yet — be the first!"
	_table_empty.add_theme_font_size_override("font_size", 18)
	_table_empty.add_theme_color_override("font_color", Color(0.74, 0.80, 1.0))
	_table_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_table_empty.visible = false
	add_child(_table_empty)

# A circular rank chip with a premium white-ish stroke, used at the start of both
# list rows. Sized by diameter `d`.
func _rank_circle(d: float, number: int, font_size: int,
		text_col: Color, stroke: Color) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(d, d)
	p.size = Vector2(d, d)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.08, 0.10, 0.22, 0.55)
	s.set_corner_radius_all(int(d * 0.5))
	s.border_color = stroke
	s.set_border_width_all(2)
	p.add_theme_stylebox_override("panel", s)
	var l := Label.new()
	l.text = str(number)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", text_col)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return p

# One nearby-list row: (rank) [name] ........ [score] — the rank sits in a
# white-stroked circle. The player's own row is taller, purple-glowing and
# stronger-bordered so it instantly draws the eye.
func _make_nearby_row(rank: int, player_name: String, score: int, is_me: bool) -> Control:
	var h := NEARBY_ME_H if is_me else NEARBY_ROW_H
	var row := Panel.new()
	row.custom_minimum_size = Vector2(LEFT_ROW_W, h)
	row.size = Vector2(LEFT_ROW_W, h)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := StyleBoxFlat.new()
	if is_me:
		s.bg_color = Color(0.16, 0.12, 0.34, 0.94)
		s.set_corner_radius_all(16)
		s.border_color = Color(0.66, 0.48, 1.0, 0.95)
		s.set_border_width_all(2)
		s.shadow_color = Color(0.55, 0.40, 1.0, 0.55)
		s.shadow_size = 16
	else:
		s.bg_color = Color(0.06, 0.08, 0.20, 0.45)
		s.set_corner_radius_all(13)
		s.border_color = Color(0.40, 0.45, 0.75, 0.28)
		s.set_border_width_all(1)
	row.add_theme_stylebox_override("panel", s)

	var rank_pad := 10.0 if is_me else 8.0
	var rd := (h - 18.0) if is_me else (h - 12.0)
	var circle := _rank_circle(rd, rank, int(rd * 0.5) + (2 if is_me else 0),
		Color.WHITE if is_me else Color(0.78, 0.84, 1.0), RANK_STROKE)
	circle.position = Vector2(rank_pad, (h - rd) * 0.5)
	row.add_child(circle)

	var name_x := rank_pad + rd + 10.0
	var name_lbl := Label.new()
	name_lbl.text = player_name + ("  (you)" if is_me else "")
	name_lbl.add_theme_font_size_override("font_size", 22 if is_me else 19)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	name_lbl.position = Vector2(name_x, 0)
	name_lbl.size = Vector2(LEFT_ROW_W - name_x - 96, h)
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_lbl)

	var score_lbl := Label.new()
	score_lbl.text = _fmt(score)
	score_lbl.add_theme_font_size_override("font_size", 22 if is_me else 19)
	score_lbl.add_theme_color_override("font_color",
		Color(0.94, 0.97, 1.0) if is_me else Color(0.44, 0.86, 0.52))
	score_lbl.position = Vector2(LEFT_ROW_W - 92, 0)
	score_lbl.size = Vector2(78, h)
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	score_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(score_lbl)

	return row

# One ranks 4–10 table row: a very thin, minimal dark-glass strip with almost no
# glow — [rank] [name] ........ [score]. The table is only here to complete the
# podium, so it stays compact and never competes with the platforms above.
func _make_table_row(rank: int, player_name: String, score: int) -> Control:
	var row := Panel.new()
	row.custom_minimum_size = Vector2(RIGHT_ROW_W, TABLE_ROW_H)
	row.size = Vector2(RIGHT_ROW_W, TABLE_ROW_H)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.07, 0.16, 0.30)
	s.set_corner_radius_all(8)
	s.border_color = Color(0.40, 0.45, 0.72, 0.14)
	s.set_border_width_all(1)
	row.add_theme_stylebox_override("panel", s)

	var rd := TABLE_ROW_H - 6.0
	var circle := _rank_circle(rd, rank, int(rd * 0.55),
		Color(0.82, 0.87, 1.0), RANK_STROKE)
	circle.position = Vector2(9, (TABLE_ROW_H - rd) * 0.5)
	row.add_child(circle)

	var name_x := 9.0 + rd + 9.0
	var name_lbl := Label.new()
	name_lbl.text = player_name
	name_lbl.add_theme_font_size_override("font_size", 17)
	name_lbl.add_theme_color_override("font_color", Color(0.84, 0.88, 0.98))
	name_lbl.position = Vector2(name_x, 0)
	name_lbl.size = Vector2(RIGHT_ROW_W - name_x - 96, TABLE_ROW_H)
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_lbl)

	var score_lbl := Label.new()
	score_lbl.text = _fmt(score)
	score_lbl.add_theme_font_size_override("font_size", 17)
	score_lbl.add_theme_color_override("font_color", Color(0.44, 0.86, 0.52))
	score_lbl.position = Vector2(RIGHT_ROW_W - 92, 0)
	score_lbl.size = Vector2(80, TABLE_ROW_H)
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	score_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(score_lbl)
	return row

# A faint placeholder table row, keeping ranks 4–10 a full 7 slots even when there
# aren't that many players.
func _make_empty_table_row() -> Control:
	var row := Panel.new()
	row.custom_minimum_size = Vector2(RIGHT_ROW_W, TABLE_ROW_H)
	row.size = Vector2(RIGHT_ROW_W, TABLE_ROW_H)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.07, 0.16, 0.14)
	s.set_corner_radius_all(8)
	s.border_color = Color(0.40, 0.45, 0.72, 0.08)
	s.set_border_width_all(1)
	row.add_theme_stylebox_override("panel", s)
	var dash := Label.new()
	dash.text = "—"
	dash.add_theme_font_size_override("font_size", 15)
	dash.add_theme_color_override("font_color", Color(0.55, 0.60, 0.85, 0.30))
	dash.set_anchors_preset(Control.PRESET_FULL_RECT)
	dash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dash.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(dash)
	return row

# ---------------- footer ----------------

func _build_footer() -> void:
	_footer = Control.new()
	_footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_footer.size = Vector2(420, 26)
	add_child(_footer)

	# Small "i" info badge.
	var badge := Panel.new()
	badge.size = Vector2(20, 20)
	badge.position = Vector2(0, 3)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.10, 0.14, 0.30, 0.0)
	bs.set_corner_radius_all(10)
	bs.border_color = Color(0.62, 0.68, 1.0, 0.55)
	bs.set_border_width_all(1)
	badge.add_theme_stylebox_override("panel", bs)
	_footer.add_child(badge)
	var i_lbl := Label.new()
	i_lbl.text = "i"
	i_lbl.add_theme_font_size_override("font_size", 14)
	i_lbl.add_theme_color_override("font_color", Color(0.72, 0.78, 1.0))
	i_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	i_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	i_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	i_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(i_lbl)

	var lbl := Label.new()
	lbl.text = "Scores are updated in real time"
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(0.70, 0.76, 0.95))
	lbl.position = Vector2(28, 0)
	lbl.size = Vector2(392, 26)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_footer.add_child(lbl)

# ---------------- render data ----------------

func _render(d: Dictionary) -> void:
	# Award leaderboard-placement badges from the player's shown rank (global vs daily).
	var my_rank := int(d.get("my_rank", 0))
	if my_rank > 0:
		if _current_range == RANGE_ALL:
			BadgeManager.note_rank(my_rank, false)
		elif _current_range == RANGE_DAILY:
			BadgeManager.note_rank(my_rank, true)
	var rows: Array = d.get("rows", [])
	_render_podium(rows)
	_render_table(rows)
	_render_nearby(d)
	_fit_frames()

# Rebuilds the podium: the stage, then the side pillars (2nd left, 3rd right) and
# finally the center 1st pillar on top, each with a cup when its rank is filled.
func _render_podium(rows: Array) -> void:
	for c in _podium.get_children():
		c.queue_free()
	_podium.add_child(_build_stage())
	# Cups are spaced exactly one difficulty-tab pitch apart (and the podium is
	# centered under the centered tab row), so 2nd sits under EASY, 1st under
	# MODERATE and 3rd under HARD. 1st is drawn last to read as the centerpiece.
	var pitch := TAB_W + TAB_SEP
	var layout := [[2, -pitch], [3, pitch], [1, 0.0]]
	for item in layout:
		var rank: int = item[0]
		var cx: float = item[1]
		var idx := rank - 1
		var has := idx < rows.size()
		var pname := ""
		var score := 0
		if has:
			var r: Dictionary = rows[idx]
			pname = String(r.get("name", "Player"))
			score = int(r.get("score", 0))
		_podium.add_child(_build_pillar(rank, cx, has, pname, score))

func _render_table(rows: Array) -> void:
	for c in _table_list.get_children():
		c.queue_free()
	if rows.is_empty():
		_table_empty.visible = true
		return
	_table_empty.visible = false
	# Always ranks 4..10 (7 slots) — the top 3 live on the podium above. Slots
	# beyond the available scores are shown as faint empty placeholders.
	for i in range(3, 3 + TABLE_SLOTS):
		var rank := i + 1
		var w: Control
		if i < rows.size():
			var r: Dictionary = rows[i]
			w = _make_table_row(rank, String(r.get("name", "Player")), int(r.get("score", 0)))
		else:
			w = _make_empty_table_row()
		_table_list.add_child(w)
		if rank <= 8:
			w.modulate.a = 0.0
			create_tween().tween_property(w, "modulate:a", 1.0, 0.3) \
				.set_delay(0.04 * (rank - 4)).set_trans(Tween.TRANS_SINE)

func _render_nearby(d: Dictionary) -> void:
	for c in _nearby_list.get_children():
		c.queue_free()
	var win := _nearby_window(d)
	if win.is_empty():
		_nearby_empty.visible = true
		return
	_nearby_empty.visible = false
	for entry in win:
		var e: Dictionary = entry
		if bool(e.get("empty", false)):
			_nearby_list.add_child(_make_empty_nearby_row())
		else:
			_nearby_list.add_child(_make_nearby_row(int(e.get("rank", 0)),
				String(e.get("name", "Player")),
				int(e.get("score", 0)),
				bool(e.get("is_me", false))))

# A faint placeholder row that keeps the nearby list a full 7 slots tall even when
# there aren't 7 players around the user.
func _make_empty_nearby_row() -> Control:
	var row := Panel.new()
	row.custom_minimum_size = Vector2(LEFT_ROW_W, NEARBY_ROW_H)
	row.size = Vector2(LEFT_ROW_W, NEARBY_ROW_H)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.08, 0.20, 0.18)
	s.set_corner_radius_all(13)
	s.border_color = Color(0.40, 0.45, 0.75, 0.12)
	s.set_border_width_all(1)
	row.add_theme_stylebox_override("panel", s)
	var dash := Label.new()
	dash.text = "—"
	dash.add_theme_font_size_override("font_size", 18)
	dash.add_theme_color_override("font_color", Color(0.55, 0.60, 0.85, 0.35))
	dash.set_anchors_preset(Control.PRESET_FULL_RECT)
	dash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dash.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(dash)
	return row

# Builds the centered window for the left panel, always padded to a full 7 slots
# (empty placeholders fill any shortfall when there aren't that many players).
# Sources:
#   • neighborhood — already centered on the player (present only when they're
#     outside the top-N), used verbatim;
#   • otherwise a slice of `rows` around my_rank (player inside the top-N).
# Returns [] when the player has no rank yet (signed out / no score), which
# shows the panel's "play a round" empty state.
func _nearby_window(d: Dictionary) -> Array:
	var target := 2 * NEARBY_SIDE + 1
	var out: Array = []
	var neighborhood: Array = d.get("neighborhood", [])
	if not neighborhood.is_empty():
		out = neighborhood.duplicate()
	else:
		var my_rank := int(d.get("my_rank", 0))
		var rows: Array = d.get("rows", [])
		if my_rank <= 0 or rows.is_empty():
			return []
		var n := rows.size()
		var lo := my_rank - NEARBY_SIDE
		var hi := my_rank + NEARBY_SIDE
		# Shift the window so it stays full (2*SIDE+1 rows) when near an edge.
		if lo < 1:
			hi += 1 - lo
			lo = 1
		if hi > n:
			lo -= hi - n
			hi = n
		lo = maxi(1, lo)
		for rank in range(lo, hi + 1):
			var r: Dictionary = rows[rank - 1]
			out.append({
				"rank": rank,
				"name": r.get("name", "Player"),
				"score": int(r.get("score", 0)),
				"is_me": bool(r.get("is_me", false)),
			})
	# Pad with empty slots so the list always shows a full 7 places.
	while out.size() < target:
		out.append({"empty": true})
	return out

# Thousands-separated integer ("18456" → "18,456").
func _fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out

# ---------------- icons ----------------

# Tab-side icons (must mirror the difficulty screen):
#   "leaf"  → EASY      "chart" → MODERATE     "flame" → HARD
func _make_icon(kind: String, s: float, col: Color) -> Node2D:
	match kind:
		"chart": return _icon_chart(s, col)
		"flame":
			return _icon_fire(s)
		"star":  return _icon_star(s, col)
		"crown": return _icon_crown_small(s, col)
		_:       return _icon_poly(_leaf_poly(s), col, -35.0)

func _icon_poly(poly: PackedVector2Array, col: Color, rot_deg: float = 0.0) -> Node2D:
	var n := Node2D.new()
	var pg := Polygon2D.new()
	pg.polygon = poly
	pg.color = col
	pg.rotation_degrees = rot_deg
	n.add_child(pg)
	return n

func _leaf_poly(s: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	var n := 16
	for i in n + 1:
		var t: float = float(i) / n
		p.append(Vector2(sin(t * PI) * s * 0.62, lerp(-s, s, t)))
	for i in n + 1:
		var t: float = float(i) / n
		p.append(Vector2(-sin(t * PI) * s * 0.62, lerp(s, -s, t)))
	return p

# Layered fire icon: outer red silhouette → orange middle → bright yellow core.
func _icon_fire(s: float) -> Node2D:
	var n := Node2D.new()
	var outer := Polygon2D.new()
	outer.polygon = _flame_silhouette(s, 1.00, 0.18)
	outer.color = Color(0.95, 0.30, 0.20)
	n.add_child(outer)
	var mid := Polygon2D.new()
	mid.polygon = _flame_silhouette(s, 0.74, 0.30)
	mid.color = Color(1.00, 0.60, 0.18)
	mid.position = Vector2(0, s * 0.06)
	n.add_child(mid)
	var core := Polygon2D.new()
	core.polygon = _flame_silhouette(s, 0.46, 0.42)
	core.color = Color(1.00, 0.92, 0.40)
	core.position = Vector2(0, s * 0.18)
	n.add_child(core)
	return n

func _flame_silhouette(s: float, scale: float, tip_lean: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	var pts := [
		Vector2( tip_lean * 0.5, -1.45),
		Vector2( 0.18, -1.20),
		Vector2( 0.30, -0.80),
		Vector2( 0.50, -0.50),
		Vector2( 0.62, -0.10),
		Vector2( 0.55,  0.25),
		Vector2( 0.78,  0.05),
		Vector2( 0.85,  0.40),
		Vector2( 0.80,  0.75),
		Vector2( 0.55,  1.00),
		Vector2( 0.00,  1.05),
		Vector2(-0.55,  1.00),
		Vector2(-0.80,  0.75),
		Vector2(-0.85,  0.40),
		Vector2(-0.70,  0.05),
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

func _icon_star(s: float, col: Color) -> Node2D:
	var n := Node2D.new()
	var poly := Polygon2D.new()
	poly.polygon = _star_poly(s)
	poly.color = col
	n.add_child(poly)
	return n

func _star_poly(s: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in 10:
		var ang: float = -PI * 0.5 + i * PI / 5.0
		var r: float = s if i % 2 == 0 else s * 0.42
		p.append(Vector2(cos(ang), sin(ang)) * r)
	return p

func _icon_crown_small(s: float, col: Color) -> Node2D:
	var n := Node2D.new()
	var crown := Polygon2D.new()
	crown.polygon = PackedVector2Array([
		Vector2(-s * 0.95,  s * 0.45),
		Vector2(-s * 0.95, -s * 0.10),
		Vector2(-s * 0.55,  s * 0.15),
		Vector2(-s * 0.20, -s * 0.55),
		Vector2( 0.0,       s * 0.15),
		Vector2( s * 0.20, -s * 0.55),
		Vector2( s * 0.55,  s * 0.15),
		Vector2( s * 0.95, -s * 0.10),
		Vector2( s * 0.95,  s * 0.45)
	])
	crown.color = col
	n.add_child(crown)
	var bar := Polygon2D.new()
	bar.polygon = PackedVector2Array([
		Vector2(-s * 0.95, s * 0.20),
		Vector2( s * 0.95, s * 0.20),
		Vector2( s * 0.95, s * 0.45),
		Vector2(-s * 0.95, s * 0.45)
	])
	bar.color = col.darkened(0.15)
	n.add_child(bar)
	return n

func _circle_poly(r: float, n: int) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in n:
		var a: float = TAU * float(i) / n
		p.append(Vector2(cos(a), sin(a)) * r)
	return p

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
		_orbit.position = Vector2(cx, sz.y * 0.50)
		_rebuild_ring(r)
		for i in _orbs.size():
			var a: float = -PI * 0.5 + i * TAU / _orbs.size()
			_orbs[i].position = Vector2(cos(a), sin(a)) * r

	var top := 8.0
	if _back:
		_back.position = Vector2(24, top + 4)
	if _header:
		_header.position = Vector2(cx - _header.size.x * 0.5, top)

	# Two equal columns, centered as a pair.
	var pair_w := 2.0 * PANEL_W + PANEL_GAP
	var left_x := cx - pair_w * 0.5
	var right_x := left_x + PANEL_W + PANEL_GAP

	# Control row: the TODAY/ALL-TIME toggle is centered over the left table, and
	# the difficulty tabs are centered over the right podium — so each difficulty
	# sits directly above its medal cup (EASY→silver, MODERATE→gold, HARD→bronze).
	var nav_y := top + HEADER_H + 6.0
	if _range_toggle:
		_range_toggle.position = Vector2(left_x + (PANEL_W - RANGE_TOGGLE_W) * 0.5, nav_y)
	if _tab_row:
		var tabs_w := 3.0 * TAB_W + 2.0 * TAB_SEP
		_tab_row.position = Vector2(right_x + (PANEL_W - tabs_w) * 0.5, nav_y)

	# Content starts under the control row; the glass frames themselves are sized to
	# hug their rows in _fit_frames(), not stretched down to the footer.
	var panel_top := nav_y + TAB_H + 14.0
	var footer_y := sz.y - 30.0

	# Both tables are centered in their column slots so the centered toggle / tabs
	# above them line up over their centers.
	var right_list_x := (PANEL_W - RIGHT_ROW_W) * 0.5
	var nearby_x := left_x + (PANEL_W - LEFT_ROW_W) * 0.5

	# Left content: the "NEARBY YOUR RANK" title sits INSIDE the glass frame, with
	# the nearby list directly under it (the frame grows to wrap both in _fit_frames).
	var nearby_header_y := panel_top + PANEL_PAD
	var nearby_list_y := nearby_header_y + NEARBY_HEADER_H + NEARBY_GAP
	if _nearby_header:
		_nearby_header.position = Vector2(nearby_x, nearby_header_y)
	if _nearby_list:
		_nearby_list.position = Vector2(nearby_x, nearby_list_y)
	if _nearby_empty:
		_nearby_empty.position = Vector2(nearby_x, nearby_list_y)
		_nearby_empty.size = Vector2(LEFT_ROW_W, 60)

	# Right column: the drawn podium occupies the top area (anchored at the column's
	# horizontal center); only the ranks 4–10 table gets a glass frame below it.
	if _spotlights:
		_spotlights.position = Vector2(right_x + PANEL_W * 0.5, panel_top)
	if _podium:
		_podium.position = Vector2(right_x + PANEL_W * 0.5, panel_top)
	var table_y := panel_top + TOP3_AREA_H + 12.0
	if _table_list:
		_table_list.position = Vector2(right_x + right_list_x, table_y)
	if _table_empty:
		_table_empty.position = Vector2(right_x + right_list_x, table_y)
		_table_empty.size = Vector2(RIGHT_ROW_W, 30)

	# Footer, centered.
	if _footer:
		_footer.position = Vector2(cx - _footer.size.x * 0.5, footer_y)

	_fit_frames()
	_layout_overlay()

# Sizes each glass frame from the FIXED 7-slot list heights (see NEARBY_LIST_H /
# TABLE_LIST_H) so the frame is identical whether the screen just opened or a
# difficulty was toggled — never measuring the live child list, which briefly
# still contains the old, queue_free'd rows. The "empty" message states fall back
# to a small card so the frame still reads behind the message.
func _fit_frames() -> void:
	if _left_panel and _nearby_list and _nearby_header:
		var h := 72.0 if _nearby_empty.visible else NEARBY_LIST_H
		# Wrap from the title's top down to the bottom of the last list row.
		var top_y := _nearby_header.position.y - PANEL_PAD
		var bottom_y := _nearby_list.position.y + h + PANEL_PAD
		_left_panel.position = Vector2(_nearby_header.position.x - PANEL_PAD, top_y)
		_left_panel.size = Vector2(LEFT_FRAME_W, bottom_y - top_y)
	if _right_panel and _table_list:
		var h2 := 56.0 if _table_empty.visible else TABLE_LIST_H
		_right_panel.position = Vector2(_table_list.position.x - PANEL_PAD,
			_table_list.position.y - PANEL_PAD)
		_right_panel.size = Vector2(RIGHT_FRAME_W, h2 + 2.0 * PANEL_PAD)

func _rebuild_ring(r: float) -> void:
	var pts := PackedVector2Array()
	var n := 72
	for i in n + 1:
		var a: float = TAU * float(i) / n
		pts.append(Vector2(cos(a), sin(a)) * r)
	_ring_glow.points = pts
	_ring_line.points = pts

# ---------------- animations / intro ----------------

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

	# Spotlights: each head swings either side of its aim and breathes in intensity,
	# the two offset in phase so the crossed beams drift across the cups.
	for i in _spot_heads.size():
		var head: Node2D = _spot_heads[i]
		var base_rot: float = head.rotation
		var phase := 1.0 if i % 2 == 0 else -1.0
		var sway := create_tween().set_loops()
		sway.tween_property(head, "rotation", base_rot + phase * SPOT_SWAY, 2.6) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		sway.tween_property(head, "rotation", base_rot - phase * SPOT_SWAY, 2.6) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		var glow := create_tween().set_loops()
		glow.tween_property(head, "modulate:a", 0.72, 1.7 + i * 0.3) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		glow.tween_property(head, "modulate:a", 1.0, 1.7 + i * 0.3) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

# Header fades in first, then the orbit/back/panels, then the nav row slides up.
func _intro() -> void:
	for n in [_header, _orbit, _back, _left_panel, _right_panel, _footer]:
		if n:
			n.modulate.a = 0.0
			create_tween().tween_property(n, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE)
	var row_nodes: Array[Control] = [_range_toggle, _tab_row]
	for n in row_nodes:
		if n:
			n.modulate.a = 0.0
			var base_y: float = n.position.y
			n.position.y = base_y + 14.0
			var tw := create_tween().set_parallel(true)
			tw.tween_property(n, "modulate:a", 1.0, 0.4).set_delay(0.25)
			tw.tween_property(n, "position:y", base_y, 0.4).set_delay(0.25) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for n in [_spotlights, _podium, _nearby_header, _nearby_list, _table_list]:
		if n:
			n.modulate.a = 0.0
			create_tween().tween_property(n, "modulate:a", 1.0, 0.5) \
				.set_delay(0.35).set_trans(Tween.TRANS_SINE)

# ---------------- data load ----------------

# Emitted by _fetch_family when one range's batch finishes, so _load_initial can
# wait for both without fetching them one-after-another.
signal _family_loaded

# Screen-open load: fetch BOTH ranges behind a SINGLE loading screen, and keep
# that screen up until BOTH are cached so either toggle position is instant the
# first time it's tapped. The two families are fetched CONCURRENTLY (and each
# fetches its three difficulty boards in parallel), so the whole set lands in
# roughly one round-trip instead of six serialized ones.
func _load_initial() -> void:
	# Fast path: the boot warm-up (LeaderboardManager.warm_boards, kicked on
	# sign-in) usually has BOTH families ready before the player ever reaches this
	# screen. Seed our caches from it, paint immediately with NO loading overlay,
	# then quietly revalidate in the background (stale-while-revalidate).
	var warm: Dictionary = LeaderboardManager.take_warm()
	if not warm.is_empty():
		_caches[RANGE_ALL] = warm.get(RANGE_ALL, {})
		_caches[RANGE_DAILY] = warm.get(RANGE_DAILY, {})
		_loaded_ranges[RANGE_ALL] = true
		_loaded_ranges[RANGE_DAILY] = true
		_hide_overlay()
		_render(_caches[_current_range].get(_current_diff, {}))
		_revalidate()
		return

	_show_loading()
	_load_token += 1
	var token := _load_token

	var pending := {"left": 2}
	_fetch_family(RANGE_ALL, token, pending)
	_fetch_family(RANGE_DAILY, token, pending)
	while pending["left"] > 0:
		await _family_loaded
	if token != _load_token:
		return

	# Only reveal the board once both ranges are cached; if the current view
	# failed to load, surface the error instead.
	if _loaded_ranges[_current_range]:
		_hide_overlay()
		_render(_caches[_current_range].get(_current_diff, {}))
	else:
		_show_error()

# Background refresh after an instant warm-cache paint: refetch both families and
# re-render the current view only if its data actually changed (so we don't replay
# the intro animations when nothing moved). Never shows the loading overlay.
func _revalidate() -> void:
	_load_token += 1
	var token := _load_token
	var before := JSON.stringify(_caches[_current_range].get(_current_diff, {}))
	var pending := {"left": 2}
	_fetch_family(RANGE_ALL, token, pending)
	_fetch_family(RANGE_DAILY, token, pending)
	while pending["left"] > 0:
		await _family_loaded
	if token != _load_token:
		return
	if not _loaded_ranges[_current_range]:
		return
	var after := JSON.stringify(_caches[_current_range].get(_current_diff, {}))
	if after != before:
		_render(_caches[_current_range].get(_current_diff, {}))

# Worker: fetches one range's three boards, caches them, then signals the batch.
# Called WITHOUT await so ALL-TIME and TODAY load at the same time.
func _fetch_family(range_key: String, token: int, pending: Dictionary) -> void:
	var res: Dictionary
	if range_key == RANGE_DAILY:
		res = await LeaderboardManager.load_all_dailies()
	else:
		res = await LeaderboardManager.load_all_globals()
	if token == _load_token and res.get("ok", false):
		_caches[range_key] = res
		_loaded_ranges[range_key] = true
	pending["left"] -= 1
	_family_loaded.emit()

# Re-entrant: bumps the token so any in-flight load from a previous range/diff
# becomes a no-op when it returns.
func _load_range(range_key: String) -> void:
	_show_loading()
	_load_token += 1
	var token := _load_token
	var result: Dictionary
	if range_key == RANGE_DAILY:
		result = await LeaderboardManager.load_all_dailies()
	else:
		result = await LeaderboardManager.load_all_globals()
	if token != _load_token:
		return
	if not result.get("ok", false):
		_show_error()
		return
	_caches[range_key] = result
	_loaded_ranges[range_key] = true
	if range_key == _current_range:
		_hide_overlay()
		_render(_caches[range_key].get(_current_diff, {}))

# ---------------- overlay ----------------

func _build_overlay() -> void:
	_overlay = Panel.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	# Sit above EVERYTHING, including the spotlights (z_index 1) which would
	# otherwise let the projector cans + beams poke through the loading backdrop.
	_overlay.z_index = 5
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.008, 0.020, 0.075, 0.985)
	_overlay.add_theme_stylebox_override("panel", s)
	add_child(_overlay)

	_ov_spinner = Control.new()
	_ov_spinner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_ov_spinner)

	# Deliberately fully static — a single painted frame with NO animation of any kind
	# (matches every other loading screen in the app). On the GL-compatibility renderer,
	# scenes/shaders compile synchronously on first draw, and each compile is a hard
	# render-thread stall that delivers no frame; anything meant to move — even a caption
	# whose trailing dots change — freezes and jerks during those stalls, so nothing here
	# moves: just a fixed "Loading…" caption.
	_ov_caption = Label.new()
	_ov_caption.text = "Loading…"
	_ov_caption.add_theme_font_size_override("font_size", 24)
	_ov_caption.add_theme_color_override("font_color", Color(0.78, 0.84, 1.0, 0.92))
	_ov_caption.add_theme_color_override("font_shadow_color", Color(0.30, 0.45, 1.0, 0.35))
	_ov_caption.add_theme_constant_override("shadow_offset_x", 0)
	_ov_caption.add_theme_constant_override("shadow_offset_y", 0)
	_ov_caption.add_theme_constant_override("shadow_outline_size", 6)
	_ov_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ov_caption.size = Vector2(360, 32)
	_ov_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ov_spinner.add_child(_ov_caption)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)

	_ov_box = VBoxContainer.new()
	_ov_box.add_theme_constant_override("separation", 16)
	_ov_box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(_ov_box)

	_overlay_msg = Label.new()
	_overlay_msg.add_theme_font_size_override("font_size", 24)
	_overlay_msg.add_theme_color_override("font_color", GOLD)
	_overlay_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_overlay_msg.custom_minimum_size = Vector2(520, 0)
	_ov_box.add_child(_overlay_msg)

	_overlay_retry = Button.new()
	_overlay_retry.text = "Try Again"
	_overlay_retry.custom_minimum_size = Vector2(220, 56)
	_overlay_retry.add_theme_font_size_override("font_size", 22)
	var ns := StyleBoxFlat.new()
	ns.bg_color = Color(0.25, 0.45, 0.65)
	ns.set_corner_radius_all(14)
	_overlay_retry.add_theme_stylebox_override("normal", ns)
	var nh := ns.duplicate() as StyleBoxFlat
	nh.bg_color = Color(0.32, 0.55, 0.78)
	_overlay_retry.add_theme_stylebox_override("hover", nh)
	var np := ns.duplicate() as StyleBoxFlat
	np.bg_color = Color(0.18, 0.34, 0.52)
	_overlay_retry.add_theme_stylebox_override("pressed", np)
	_overlay_retry.add_theme_color_override("font_color", Color.WHITE)
	_overlay_retry.pressed.connect(func() -> void: _load_initial())
	_ov_box.add_child(_overlay_retry)

	_overlay.visible = false

func _layout_overlay() -> void:
	if _overlay == null:
		return
	var sz := get_viewport_rect().size
	_overlay.position = Vector2.ZERO
	_overlay.size = sz
	if _ov_caption:
		_ov_caption.position = Vector2(sz.x * 0.5 - 180, sz.y * 0.5 - 16)

func _show_loading() -> void:
	_layout_overlay()
	_overlay.visible = true
	_ov_spinner.visible = true
	_ov_box.visible = false

func _show_error() -> void:
	_layout_overlay()
	_overlay.visible = true
	_ov_spinner.visible = false
	_ov_box.visible = true
	_overlay_msg.text = "Our servers are currently down.\nPlease try again soon."
	_overlay_retry.visible = true

func _hide_overlay() -> void:
	_overlay.visible = false
