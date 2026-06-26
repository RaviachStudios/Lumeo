extends Control

# Premium leaderboard screen — same visual language as the home / difficulty /
# how-to-play screens: deep-space shader background, rotating orbit of glowing
# orbs, glass back button, gold trophy header with diamond-decorated underline.
# Two-column body: a wide scrolling rank TABLE on the LEFT (full standings,
# ranks 1+, with the top 3 medal-tinted) and a top-3 PODIUM on the RIGHT (cards
# on cylindrical pedestals with crown / star-medal / skull-medal toppers). The
# TODAY / ALL-TIME segmented toggle and the three difficulty tabs (EASY /
# MODERATE / HARD — labels and icons mirror the difficulty selection screen)
# stack above the table. Both ranges load when the screen opens (ALL-TIME shown
# first), so the toggle flips instantly. When the signed-in player is outside the
# top 20 the list also shows a "your neighborhood" snippet with a "⋯" gap divider
# above their row. Names only — no avatars (we don't store any). A full-screen
# orbiting-orb loading overlay covers the board while the first fetch is in
# flight. Built with Godot nodes + shaders + tweens; no PNG/MP3.

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

# Podium accent per rank: drives glow beam, card rim, pedestal numeral color,
# topper tint. Order matches rank (index 0 → rank 1).
const RANK_ACCENTS := [
	Color(1.00, 0.82, 0.25),  # 1st — gold
	Color(0.55, 0.78, 1.00),  # 2nd — silver/blue
	Color(0.95, 0.55, 0.25),  # 3rd — bronze
]

# Row metrics for the rank table (now the left column; lists ranks 1+).
const ROW_H := 56.0
const ROW_GAP := 8.0
const LIST_W := 600.0

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
var _tabs: Array[Dictionary] = []   # { wrap, btn, stylebox, def, icon_panel, label }

# Podium: a single Control that hosts 3 PodiumSlot Controls (one per rank).
# Each slot is built once and just hidden/repopulated when data changes — this
# avoids per-render Polygon2D rebuilds for the laurel/numeral, which are
# expensive to allocate on every tab swap.
var _podium: Control
var _podium_slots: Array[Dictionary] = []   # per slot: { root, card, score_lbl, name_lbl, beam, beam_mat }

var _scroll: ScrollContainer
var _list: VBoxContainer
var _empty_lbl: Label
var _overlay: Panel
var _overlay_msg: Label
var _overlay_retry: Button
# Full-screen loading state: an orbiting-orb spinner + caption (same language as
# the boot loader) shown over a near-opaque backdrop, so a slow fetch reads as a
# real loading screen instead of a thin label floating above an empty table.
var _ov_spinner: Control
var _ov_orbit: Node2D
var _ov_orbs: Array[Node2D] = []
var _ov_caption: Label
var _ov_box: VBoxContainer
var _ov_dots_idx := 0

# Range toggle (TODAY ⇄ ALL-TIME). Sits above the table and is the screen's
# second axis of slicing; default is ALL-TIME (the headline board players most
# expect to see first). Both ranges are fetched when the screen opens, so the
# toggle flips between them instantly.
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
	_build_back()
	_build_header()
	_build_range_toggle()
	_build_tabs()
	_build_podium()
	_build_list()
	_build_overlay()
	_layout()
	get_viewport().size_changed.connect(_layout)
	_start_animations()
	_intro()
	_load_initial()

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

# ---------------- back button ----------------

func _build_back() -> void:
	_back = Button.new()
	_back.text = "← Back"
	_back.size = Vector2(132, 46)
	_back.focus_mode = Control.FOCUS_NONE
	_back.add_theme_font_size_override("font_size", 18)
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.07, 0.10, 0.26, 0.7)        # translucent navy glass
	s.set_corner_radius_all(23)
	s.border_color = Color(0.35, 0.5, 1.0, 0.5)      # thin blue border
	s.set_border_width_all(1)
	s.shadow_color = Color(0.25, 0.4, 1.0, 0.25)     # soft blue glow
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

# Header is compressed vs. the older screen so the podium + list both fit at 720h.
const HEADER_W := 720.0
const HEADER_H := 150.0

func _build_header() -> void:
	_header = Control.new()
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.custom_minimum_size = Vector2(HEADER_W, HEADER_H)
	_header.size = Vector2(HEADER_W, HEADER_H)
	add_child(_header)

	_trophy = _make_trophy(32.0, GOLD)
	_trophy.position = Vector2(HEADER_W * 0.5, 22)
	_header.add_child(_trophy)

	_title_lbl = Label.new()
	_title_lbl.text = _title_for_range(_current_range)
	_title_lbl.add_theme_font_size_override("font_size", 46)
	_title_lbl.add_theme_color_override("font_color", Color.WHITE)
	_title_lbl.add_theme_color_override("font_outline_color", Color(1, 1, 1, 1))
	_title_lbl.add_theme_constant_override("outline_size", 2)             # faux-bold
	_title_lbl.add_theme_color_override("font_shadow_color", Color(0.20, 0.40, 1.0, 0.40))
	_title_lbl.add_theme_constant_override("shadow_offset_x", 0)
	_title_lbl.add_theme_constant_override("shadow_offset_y", 4)
	_title_lbl.add_theme_constant_override("shadow_outline_size", 9)
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_lbl.offset_top = 50
	_title_lbl.offset_bottom = -40
	_title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.add_child(_title_lbl)

	# Thin glowing blue underline with a small diamond in the center — matches
	# the subtitle decorations on the home / how-to-play screens.
	_underline = Control.new()
	_underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_underline.size = Vector2(420, 14)
	_underline.position = Vector2((HEADER_W - 420) * 0.5, HEADER_H - 24)
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

const TAB_SEP := 28                # pill-to-pill gap
const TAB_W := 168.0
const TAB_H := 44.0

func _build_tabs() -> void:
	_tab_row = HBoxContainer.new()
	_tab_row.add_theme_constant_override("separation", TAB_SEP)
	add_child(_tab_row)
	_tabs.clear()
	for def in TAB_DEFS:
		_tabs.append(_make_tab(def))
	_refresh_tab_styles()

# Rounded pill tab: dark glass background + thin neon border in the accent
# color + small accent-colored icon on the leading side + uppercase label.
func _make_tab(def: Dictionary) -> Dictionary:
	var accent: Color = def["accent"]
	var rtl := _is_rtl()
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
	# Share ONE stylebox across every Button state so the active-tab glow updates
	# immediately on click (per-state duplicates leave the button stuck in
	# hover/pressed style right after a tap).
	btn.add_theme_stylebox_override("normal", s)
	btn.add_theme_stylebox_override("hover", s)
	btn.add_theme_stylebox_override("pressed", s)
	btn.add_theme_stylebox_override("focus", s)
	btn.add_theme_color_override("font_color", Color(0.74, 0.80, 1.0))
	wrap.add_child(btn)

	var icon := Panel.new()
	var dia := 26.0
	icon.size = Vector2(dia, dia)
	icon.position = Vector2(TAB_W - 12 - dia if rtl else 12, (TAB_H - dia) * 0.5)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := StyleBoxFlat.new()
	var icbg := accent.darkened(0.2); icbg.a = 0.30
	ic.bg_color = icbg
	ic.set_corner_radius_all(int(dia * 0.5))
	ic.border_color = accent.lightened(0.2)
	ic.set_border_width_all(1)
	icon.add_theme_stylebox_override("panel", ic)
	btn.add_child(icon)
	var sym := _make_icon(def["icon"], dia * 0.38, accent.lightened(0.45))
	sym.position = Vector2(dia * 0.5, dia * 0.5)
	icon.add_child(sym)

	var lbl := Label.new()
	lbl.text = def["label"]
	lbl.add_theme_font_size_override("font_size", 17)
	lbl.add_theme_color_override("font_color", accent.lightened(0.15))
	lbl.position = Vector2(8 if rtl else 12 + dia + 6, 0)
	lbl.size = Vector2(TAB_W - (12 + dia + 6) - 12, TAB_H)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(lbl)

	btn.pressed.connect(func() -> void: _on_tab(def["diff"]))
	_tab_row.add_child(wrap)
	return {"wrap": wrap, "btn": btn, "stylebox": s, "def": def, "label": lbl, "icon_panel": icon}

func _refresh_tab_styles() -> void:
	for t in _tabs:
		var def: Dictionary = t["def"]
		var accent: Color = def["accent"]
		var active: bool = def["diff"] == _current_diff
		var s: StyleBoxFlat = t["stylebox"]
		s.border_color = Color(accent.r, accent.g, accent.b, 1.0 if active else 0.55)
		s.set_border_width_all(2 if active else 1)
		s.shadow_color = Color(accent.r, accent.g, accent.b, 0.45 if active else 0.20)
		s.shadow_size = 14 if active else 8
		var lbl: Label = t["label"]
		lbl.add_theme_color_override("font_color",
			accent.lightened(0.35) if active else accent.lightened(0.05))
		var tw := create_tween()
		tw.tween_property(t["btn"], "scale",
			Vector2.ONE * (1.05 if active else 1.0), 0.18) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_tab(diff: String) -> void:
	if diff == _current_diff:
		return
	_current_diff = diff
	_refresh_tab_styles()
	if _loaded_ranges[_current_range]:
		_render(_caches[_current_range].get(diff, {}))

# ---------------- range toggle (TODAY ⇄ ALL-TIME) ----------------

# Two-segment pill that selects which leaderboard family the screen renders.
# Visually distinct from the difficulty tabs (no icon, accent shared by both
# segments only when active) so it reads as a scope toggle rather than another
# difficulty — though it lives on the same row so the player understands the
# two axes belong together.
func _build_range_toggle() -> void:
	_range_toggle = Control.new()
	_range_toggle.custom_minimum_size = Vector2(RANGE_TOGGLE_W, RANGE_TOGGLE_H)
	_range_toggle.size = Vector2(RANGE_TOGGLE_W, RANGE_TOGGLE_H)
	_range_toggle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_range_toggle)

	# Single shared background panel behind both segments — gives the toggle a
	# unified pill silhouette so the two halves read as one control. Each
	# segment is a transparent Button overlaid on top + its own thin "active"
	# StyleBoxFlat that only shows when selected.
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

	# Hairline separator down the middle so the two halves read distinctly even
	# when neither is hovered. Slightly inset top/bottom for a refined look.
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

# One half of the pill. The "active" stylebox is what visually selects the
# segment — an accent rim + halo on top of the shared background.
func _make_range_seg(def: Dictionary, pos: Vector2, size: Vector2) -> Dictionary:
	var accent: Color = def["accent"]

	var btn := Button.new()
	btn.size = size
	btn.position = pos
	btn.pivot_offset = size * 0.5
	btn.focus_mode = Control.FOCUS_NONE
	# Active stylebox — only swapped onto the button when this segment is the
	# current range. Inactive segments use a fully transparent style so the
	# shared background panel shows through. The active fill is intentionally
	# soft (low alpha) so the underlying glass tone still reads.
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
	# Already-loaded range: just re-render from cache, no spinner. First time
	# the user flips to a range we fetch and show the loading overlay.
	if _loaded_ranges[_current_range]:
		_render(_caches[_current_range].get(_current_diff, {}))
	else:
		_load_range(_current_range)

func _title_for_range(range_key: String) -> String:
	return "TODAY'S BEST" if range_key == RANGE_DAILY else "ALL-TIME BEST"

func _update_title() -> void:
	if _title_lbl:
		_title_lbl.text = _title_for_range(_current_range)

# ---------------- podium ----------------

# Per-slot geometry. Index 0 = rank 1 (center, tallest). Sides (1,2) are smaller.
# Tuned to give the rank 4+ list at least ~4 rows of breathing room at 720h.
const PODIUM_H := 188.0
const PODIUM_GAP := 12.0              # horizontal gap between slots
const PODIUM_CARD_W := [156.0, 136.0, 136.0]    # [rank1, rank2, rank3]
const PODIUM_CARD_H := [108.0, 92.0, 92.0]
const PODIUM_PED_H  := [70.0, 52.0, 52.0]
const PODIUM_PED_W  := [174.0, 154.0, 154.0]
const PODIUM_TOPPER := [36.0, 28.0, 28.0]       # diameter for medals; same scale used for the crown
# Visual order on screen, left → right: rank 2, rank 1, rank 3 (center tallest).
const PODIUM_DISPLAY_ORDER := [1, 0, 2]

func _build_podium() -> void:
	_podium = Control.new()
	_podium.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_podium)
	_podium_slots.clear()
	for rank_idx in 3:
		_podium_slots.append(_build_podium_slot(rank_idx))

# A slot is built ONCE at startup. Re-rendering just updates the score/name
# labels and shows/hides the placeholder — laurel/numeral Polygon2Ds aren't
# rebuilt because they're surprisingly expensive to allocate (many vertices,
# antialiased lines), and tab swaps need to feel instant.
func _build_podium_slot(rank_idx: int) -> Dictionary:
	var card_w: float = PODIUM_CARD_W[rank_idx]
	var card_h: float = PODIUM_CARD_H[rank_idx]
	var ped_w: float  = PODIUM_PED_W[rank_idx]
	var ped_h: float  = PODIUM_PED_H[rank_idx]
	var topper_sz: float = PODIUM_TOPPER[rank_idx]
	var accent: Color = RANK_ACCENTS[rank_idx]

	# Slot root: total width = max(card_w, ped_w) + slack for glow falloff; total
	# height covers topper + card + pedestal. Children are positioned with the
	# pedestal-bottom at y=PODIUM_H (shared baseline across slots).
	var w: float = maxf(card_w, ped_w) + 60.0   # +60 to keep glow inside slot bounds
	var slot := Control.new()
	slot.size = Vector2(w, PODIUM_H)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_podium.add_child(slot)

	var cx_local := w * 0.5
	var baseline := PODIUM_H            # bottom of pedestal
	var ped_top := baseline - ped_h
	var card_bottom := ped_top + 8.0    # card slightly overlaps the pedestal
	var card_top := card_bottom - card_h

	# --- light beam (behind the card, rising from the pedestal) ---
	# Trapezoid widens upward into the card area and fades; vertex_colors gives a
	# soft vertical falloff, ADD blend lets it tint whatever's beneath without
	# darkening the background.
	var beam := Polygon2D.new()
	var beam_top_y: float = card_top - 16.0
	var beam_bot_y: float = ped_top + 6.0
	var beam_top_half: float = card_w * 0.48
	var beam_bot_half: float = ped_w * 0.30
	beam.polygon = PackedVector2Array([
		Vector2(cx_local - beam_top_half, beam_top_y),
		Vector2(cx_local + beam_top_half, beam_top_y),
		Vector2(cx_local + beam_bot_half, beam_bot_y),
		Vector2(cx_local - beam_bot_half, beam_bot_y),
	])
	# top fades, bottom intense (the pedestal is the "light source").
	var c_top := Color(accent.r, accent.g, accent.b, 0.0)
	var c_bot := Color(accent.r, accent.g, accent.b, 0.55)
	beam.vertex_colors = PackedColorArray([c_top, c_top, c_bot, c_bot])
	var beam_mat := CanvasItemMaterial.new()
	beam_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	beam.material = beam_mat
	slot.add_child(beam)

	# --- card panel (glassy, dark navy with colored rim glow) ---
	var card := Panel.new()
	card.size = Vector2(card_w, card_h)
	card.position = Vector2(cx_local - card_w * 0.5, card_top)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.06, 0.08, 0.20, 0.88)
	cs.set_corner_radius_all(16)
	cs.border_color = Color(accent.r, accent.g, accent.b, 0.85)
	cs.set_border_width_all(2)
	cs.shadow_color = Color(accent.r, accent.g, accent.b, 0.55)
	cs.shadow_size = 18                                       # the rim glow
	card.add_theme_stylebox_override("panel", cs)
	slot.add_child(card)

	# Ringed score circle (top half of the card). The Panel is a perfect circle
	# via corner_radius=50%; the border is the visible ring.
	var ring_d: float = card_h * 0.50
	var ring := Panel.new()
	ring.size = Vector2(ring_d, ring_d)
	ring.position = Vector2((card_w - ring_d) * 0.5, 10.0)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rs := StyleBoxFlat.new()
	rs.bg_color = Color(0.03, 0.04, 0.10, 0.85)
	rs.set_corner_radius_all(int(ring_d * 0.5))
	rs.border_color = accent.lightened(0.15)
	rs.set_border_width_all(2)
	rs.shadow_color = Color(accent.r, accent.g, accent.b, 0.45)
	rs.shadow_size = 10
	ring.add_theme_stylebox_override("panel", rs)
	card.add_child(ring)

	var score_lbl := Label.new()
	score_lbl.text = "—"
	score_lbl.add_theme_font_size_override("font_size", 22 if rank_idx == 0 else 18)
	score_lbl.add_theme_color_override("font_color", Color.WHITE)
	score_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	score_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.add_child(score_lbl)

	# Player name fills the remaining bottom half of the card.
	var name_lbl := Label.new()
	name_lbl.text = ""
	name_lbl.add_theme_font_size_override("font_size", 19 if rank_idx == 0 else 16)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	name_lbl.position = Vector2(8, ring_d + 10.0)
	name_lbl.size = Vector2(card_w - 16, card_h - ring_d - 14.0)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(name_lbl)

	# --- topper (crown / star-medal / skull-medal), centered above the card ---
	var topper := _make_topper(rank_idx, topper_sz)
	topper.position = Vector2(cx_local, card_top - topper_sz * 0.45)
	slot.add_child(topper)

	# --- pedestal (cylinder with laurel wreath + rank numeral) ---
	var pedestal := _make_pedestal(rank_idx, ped_w, ped_h)
	pedestal.position = Vector2(cx_local - ped_w * 0.5, ped_top)
	slot.add_child(pedestal)

	return {
		"root": slot, "card": card, "ring": ring,
		"score_lbl": score_lbl, "name_lbl": name_lbl,
		"beam": beam, "beam_mat": beam_mat,
		"topper": topper,
	}

# Cylindrical pedestal: a dark rounded rectangle with a brighter top "rim" ellipse
# to fake the 3D cap, a big rank numeral in metal color, and laurel branches on
# either side of the numeral.
func _make_pedestal(rank_idx: int, w: float, h: float) -> Control:
	var pedestal := Control.new()
	pedestal.size = Vector2(w, h)
	pedestal.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var body := Panel.new()
	body.size = Vector2(w, h)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.05, 0.06, 0.15, 0.98)
	ps.set_corner_radius_all(20)
	ps.border_color = Color(0.20, 0.22, 0.36)
	ps.set_border_width_all(1)
	ps.shadow_color = Color(0, 0, 0, 0.5)
	ps.shadow_size = 6
	body.add_theme_stylebox_override("panel", ps)
	pedestal.add_child(body)

	# Top "cap" — a slightly lighter strip that suggests the lit top of a
	# cylinder catching the light beam from above.
	var cap := Panel.new()
	cap.size = Vector2(w - 8, 10)
	cap.position = Vector2(4, 0)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var caps := StyleBoxFlat.new()
	caps.bg_color = Color(0.10, 0.12, 0.24)
	caps.set_corner_radius_all(6)
	cap.add_theme_stylebox_override("panel", caps)
	pedestal.add_child(cap)

	# Laurel wreath: one branch on each side of the numeral, mirrored.
	var laurel_col: Color = RANK_ACCENTS[rank_idx].lightened(0.10)
	var laurel_s: float = h * 0.30
	var laurel_l := _make_laurel(laurel_s, laurel_col, false)
	laurel_l.position = Vector2(w * 0.5 - laurel_s * 1.6, h * 0.55)
	pedestal.add_child(laurel_l)
	var laurel_r := _make_laurel(laurel_s, laurel_col, true)
	laurel_r.position = Vector2(w * 0.5 + laurel_s * 1.6, h * 0.55)
	pedestal.add_child(laurel_r)

	# Rank numeral, centered.
	var num := Label.new()
	num.text = str(rank_idx + 1)
	num.add_theme_font_size_override("font_size", int(h * 0.62))
	num.add_theme_color_override("font_color", RANK_ACCENTS[rank_idx].lightened(0.20))
	num.add_theme_color_override("font_outline_color",
		RANK_ACCENTS[rank_idx].darkened(0.30))
	num.add_theme_constant_override("outline_size", 2)
	num.set_anchors_preset(Control.PRESET_FULL_RECT)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pedestal.add_child(num)

	return pedestal

# Rank 1 → gold crown; ranks 2/3 → circular medals containing star/skull icons.
func _make_topper(rank_idx: int, size: float) -> Node2D:
	match rank_idx:
		0: return _make_crown_topper(size, RANK_ACCENTS[0])
		1: return _make_medal_topper(size, RANK_ACCENTS[1], "star")
		_: return _make_medal_topper(size, RANK_ACCENTS[2], "skull")

func _make_crown_topper(s: float, col: Color) -> Node2D:
	var n := Node2D.new()
	# Soft golden bloom behind the crown.
	var halo := Sprite2D.new()
	halo.texture = _orb_tex
	halo.modulate = Color(col.r, col.g, col.b, 0.55)
	halo.scale = Vector2.ONE * (s * 3.0 / 128.0)
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	halo.material = add_mat
	n.add_child(halo)
	var crown := Polygon2D.new()
	crown.polygon = PackedVector2Array([
		Vector2(-s * 0.9,  s * 0.4),
		Vector2(-s * 0.9, -s * 0.05),
		Vector2(-s * 0.5,  s * 0.15),
		Vector2(-s * 0.2, -s * 0.45),
		Vector2( 0.0,      s * 0.15),
		Vector2( s * 0.2, -s * 0.45),
		Vector2( s * 0.5,  s * 0.15),
		Vector2( s * 0.9, -s * 0.05),
		Vector2( s * 0.9,  s * 0.4)
	])
	crown.color = col
	n.add_child(crown)
	# Three little jewel highlights on the points.
	for x_off in [-0.55, 0.0, 0.55]:
		var jewel := Polygon2D.new()
		jewel.polygon = _circle_poly(s * 0.10, 12)
		jewel.position = Vector2(x_off * s, -s * 0.28)
		jewel.color = col.lightened(0.45)
		n.add_child(jewel)
	return n

# A circular medal disc (dark inner + colored rim) with an icon in the middle.
# "kind" picks the icon: "star" → 5-point star, "skull" → skull silhouette.
func _make_medal_topper(s: float, accent: Color, kind: String) -> Node2D:
	var n := Node2D.new()
	var halo := Sprite2D.new()
	halo.texture = _orb_tex
	halo.modulate = Color(accent.r, accent.g, accent.b, 0.50)
	halo.scale = Vector2.ONE * (s * 2.6 / 128.0)
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	halo.material = add_mat
	n.add_child(halo)
	var disc := Polygon2D.new()
	disc.polygon = _circle_poly(s * 0.72, 28)
	disc.color = accent
	n.add_child(disc)
	var inner := Polygon2D.new()
	inner.polygon = _circle_poly(s * 0.58, 28)
	inner.color = accent.darkened(0.45)
	n.add_child(inner)
	var sym: Node2D
	if kind == "skull":
		sym = _icon_skull(s * 0.42, accent.lightened(0.30))
	else:
		sym = _icon_star(s * 0.40, accent.lightened(0.30))
	n.add_child(sym)
	# Little ribbon "ears" peeking out from behind the disc (just two short bars).
	for side in [-1.0, 1.0]:
		var ribbon := Polygon2D.new()
		ribbon.polygon = PackedVector2Array([
			Vector2(side * s * 0.40, -s * 0.65),
			Vector2(side * s * 0.78, -s * 0.45),
			Vector2(side * s * 0.62, -s * 0.30),
			Vector2(side * s * 0.30, -s * 0.50)
		])
		ribbon.color = accent.darkened(0.20)
		n.add_child(ribbon)
	return n

# ---------------- list (ranks 4+) ----------------

func _build_list() -> void:
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", int(ROW_GAP))
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)

	# Shown when the podium is empty (no scores yet).
	_empty_lbl = Label.new()
	_empty_lbl.text = "No scores yet — be the first!"
	_empty_lbl.add_theme_font_size_override("font_size", 20)
	_empty_lbl.add_theme_color_override("font_color", Color(0.74, 0.80, 1.0))
	_empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_lbl.visible = false
	_list.add_child(_empty_lbl)

# Compact pill row: rank circle | name (left) | score (right, green).
func _make_list_row(rank: int, name: String, score: int, is_me: bool) -> Control:
	var row_w := LIST_W
	var row := Panel.new()
	row.custom_minimum_size = Vector2(row_w, ROW_H)
	row.size = Vector2(row_w, ROW_H)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.08, 0.20, 0.78) if not is_me \
		else Color(0.12, 0.10, 0.26, 0.92)
	s.set_corner_radius_all(int(ROW_H * 0.5))
	s.border_color = Color(0.35, 0.4, 0.7, 0.45) if not is_me \
		else Color(GOLD.r, GOLD.g, GOLD.b, 0.85)
	s.set_border_width_all(1 if not is_me else 2)
	if is_me:
		s.shadow_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.35)
		s.shadow_size = 10
	row.add_theme_stylebox_override("panel", s)

	# Rank inside a thin circle on the left.
	var circle_d := ROW_H - 18.0
	var circle := Panel.new()
	circle.size = Vector2(circle_d, circle_d)
	circle.position = Vector2(14, (ROW_H - circle_d) * 0.5)
	circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Medal tint for the podium ranks so the top 3 rows echo the podium beside them.
	var medal := Color(0.55, 0.50, 0.95, 0.75)
	match rank:
		1: medal = GOLD
		2: medal = SILVER
		3: medal = BRONZE
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(medal.r, medal.g, medal.b, 0.10) if rank <= 3 \
		else Color(0.04, 0.05, 0.14, 0.0)
	cs.set_corner_radius_all(int(circle_d * 0.5))
	cs.border_color = Color(medal.r, medal.g, medal.b, 0.95 if rank <= 3 else 0.75)
	cs.set_border_width_all(2)
	circle.add_theme_stylebox_override("panel", cs)
	row.add_child(circle)

	var rank_lbl := Label.new()
	rank_lbl.text = str(rank)
	rank_lbl.add_theme_font_size_override("font_size", 18)
	rank_lbl.add_theme_color_override("font_color",
		medal.lightened(0.25) if rank <= 3 else Color(0.88, 0.92, 1.0))
	rank_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	rank_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	circle.add_child(rank_lbl)

	# Name fills the middle.
	var name_lbl := Label.new()
	name_lbl.text = name + ("  (you)" if is_me else "")
	name_lbl.add_theme_font_size_override("font_size", 22)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	name_lbl.position = Vector2(14 + circle_d + 16, 0)
	name_lbl.size = Vector2(row_w - (14 + circle_d + 16) - 120, ROW_H)
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_lbl)

	# Score on the right, green per the mockup.
	var score_lbl := Label.new()
	score_lbl.text = str(score)
	score_lbl.add_theme_font_size_override("font_size", 22)
	score_lbl.add_theme_color_override("font_color", Color(0.36, 0.95, 0.55))
	score_lbl.position = Vector2(row_w - 120, 0)
	score_lbl.size = Vector2(106, ROW_H)
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	score_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(score_lbl)
	return row

# ---------------- render data ----------------

func _render(d: Dictionary) -> void:
	var rows: Array = d.get("rows", [])
	_render_podium(rows)
	_render_list(rows, d.get("neighborhood", []), int(d.get("my_rank", 0)))

func _render_podium(rows: Array) -> void:
	for rank_idx in 3:
		var slot: Dictionary = _podium_slots[rank_idx]
		if rank_idx < rows.size():
			var r: Dictionary = rows[rank_idx]
			slot["score_lbl"].text = str(int(r.get("score", 0)))
			slot["name_lbl"].text = String(r.get("name", "Player")).to_upper()
			slot["root"].modulate.a = 1.0
			slot["beam"].visible = true
			slot["topper"].visible = true
		else:
			# Placeholder: card stays visible (so the podium silhouette reads),
			# but score/name are blanked and the glow beam + topper are hidden.
			slot["score_lbl"].text = "—"
			slot["name_lbl"].text = ""
			slot["root"].modulate.a = 0.55
			slot["beam"].visible = false
			slot["topper"].visible = false

func _render_list(rows: Array, neighborhood: Array, my_rank: int) -> void:
	# Keep _empty_lbl, drop the previous row Panels + any prior divider.
	for c in _list.get_children():
		if c == _empty_lbl: continue
		c.queue_free()

	if rows.is_empty() and neighborhood.is_empty():
		_empty_lbl.visible = true
		return
	_empty_lbl.visible = false

	# The table is the full standings now (ranks 1..20); the podium to its right
	# celebrates the same top 3, with their table rows medal-tinted to tie the two
	# columns together. With <20 entries the list is just shorter.
	for i in range(0, rows.size()):
		var r: Dictionary = rows[i]
		var rank := i + 1
		var w := _make_list_row(rank,
			String(r.get("name", "Player")),
			int(r.get("score", 0)),
			bool(r.get("is_me", false)))
		_list.add_child(w)
		# Staggered fade-in for the first batch only — feels snappier than
		# animating every row when long lists scroll.
		if rank <= 8:
			w.modulate.a = 0.0
			create_tween().tween_property(w, "modulate:a", 1.0, 0.3) \
				.set_delay(0.04 * (rank - 3)).set_trans(Tween.TRANS_SINE)

	# Neighborhood snippet — only present when the signed-in player is outside
	# the top 20. Manager builds an 11-row max sequence centred on the player
	# with explicit "rank" fields, so we just render them with a "⋯" divider
	# in front to call out the gap.
	if not neighborhood.is_empty() and rows.size() > 0:
		var last_top_rank := rows.size()
		# Top neighborhood row's rank > last_top_rank + 1 means there's a true
		# gap; if it's exactly last_top_rank + 1 we'd be lying with a "⋯". In
		# practice my_rank > GLOBAL_TOP_N gates this, so last_top_rank + 1 <
		# top.rank is always true — but be defensive.
		var top_n_rank := int((neighborhood[0] as Dictionary).get("rank", last_top_rank + 2))
		if top_n_rank > last_top_rank + 1:
			_list.add_child(_make_gap_divider(last_top_rank, top_n_rank, my_rank))
		for r in neighborhood:
			var entry: Dictionary = r
			var nr := _make_list_row(int(entry.get("rank", 0)),
				String(entry.get("name", "Player")),
				int(entry.get("score", 0)),
				bool(entry.get("is_me", false)))
			_list.add_child(nr)

# A compact "rank gap" indicator placed between the top-20 list and the
# player's neighborhood snippet. Two thin lines on either side of a centred
# "⋯" and a small "RANK N" hint, so the player understands their snippet
# isn't fabricated — there really are N players hidden between.
func _make_gap_divider(last_top_rank: int, next_rank: int, my_rank: int) -> Control:
	const DIVIDER_H := 36.0
	var hidden := next_rank - last_top_rank - 1
	var row := Control.new()
	row.custom_minimum_size = Vector2(LIST_W, DIVIDER_H)
	row.size = Vector2(LIST_W, DIVIDER_H)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Two ColorRects framing a centred dots + label. They're absolute-positioned
	# so the label can drift slightly with hidden-count digits without breaking.
	var dots := Label.new()
	dots.text = "⋯"
	dots.add_theme_font_size_override("font_size", 26)
	dots.add_theme_color_override("font_color", Color(0.65, 0.72, 1.0, 0.65))
	dots.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dots.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dots.size = Vector2(60, DIVIDER_H)
	dots.position = Vector2((LIST_W - 60.0) * 0.5, 0)
	dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(dots)

	# Small "N players hidden" hint above the dots. Reads as a non-shouty
	# explanation rather than a label that demands attention.
	var hint := Label.new()
	if hidden == 1:
		hint.text = "1 player between"
	else:
		hint.text = "%d players between" % hidden
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.74, 0.80, 1.0, 0.55))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	hint.size = Vector2(LIST_W, 14)
	hint.position = Vector2(0, -2)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(hint)

	# Faint side-lines so the divider feels like a graphical break, not just text.
	var line_w := (LIST_W - 120.0) * 0.5
	var l1 := ColorRect.new()
	l1.color = Color(0.42, 0.48, 0.82, 0.30)
	l1.size = Vector2(line_w, 1)
	l1.position = Vector2(0, DIVIDER_H * 0.62)
	l1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l1)
	var l2 := ColorRect.new()
	l2.color = Color(0.42, 0.48, 0.82, 0.30)
	l2.size = Vector2(line_w, 1)
	l2.position = Vector2(LIST_W - line_w, DIVIDER_H * 0.62)
	l2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l2)

	# Suppress unused-warning when the caller doesn't read these (we keep the
	# args for future expansion — e.g. clickable "jump to my rank" affordance).
	var _unused := my_rank
	return row

# ---------------- icons ----------------

# Tab-side icons (must mirror the difficulty screen):
#   "leaf"  → EASY      "chart" → MODERATE     "flame" → HARD
# The podium uses _icon_star / _icon_crown_small / _icon_skull internally for
# medal/topper decorations — those aren't tab icons.
func _make_icon(kind: String, s: float, col: Color) -> Node2D:
	match kind:
		"chart": return _icon_chart(s, col)
		"flame":
			# Fire keeps its own red→orange→yellow palette regardless of the
			# accent passed in, so HARD always reads as fire.
			return _icon_fire(s)
		"star":  return _icon_star(s, col)
		"crown": return _icon_crown_small(s, col)
		"skull": return _icon_skull(s, col)
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
# Mirrors difficulty_screen._icon_fire so HARD reads identically on both screens.
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
	# Tiny base bar so it reads as a crown, not just spikes.
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

# Stylized skull: rounded "head" silhouette with two dark eye sockets and a
# small jaw notch. Always drawn in `col` (the icon tint) — we don't try to
# detail the teeth because at icon size they smear into a single blob.
func _icon_skull(s: float, col: Color) -> Node2D:
	var n := Node2D.new()
	var head := Polygon2D.new()
	head.polygon = PackedVector2Array([
		Vector2(-s * 0.75, -s * 0.45),
		Vector2(-s * 0.90, -s * 0.05),
		Vector2(-s * 0.80,  s * 0.35),
		Vector2(-s * 0.55,  s * 0.55),
		Vector2(-s * 0.35,  s * 0.40),
		Vector2(-s * 0.18,  s * 0.65),
		Vector2( 0.0,       s * 0.50),
		Vector2( s * 0.18,  s * 0.65),
		Vector2( s * 0.35,  s * 0.40),
		Vector2( s * 0.55,  s * 0.55),
		Vector2( s * 0.80,  s * 0.35),
		Vector2( s * 0.90, -s * 0.05),
		Vector2( s * 0.75, -s * 0.45),
		Vector2( s * 0.40, -s * 0.80),
		Vector2(-s * 0.40, -s * 0.80),
	])
	head.color = col
	n.add_child(head)
	# Dark eye sockets — punch out roughly circular dark blobs.
	for x_off in [-0.36, 0.36]:
		var eye := Polygon2D.new()
		eye.polygon = _circle_poly(s * 0.20, 14)
		eye.position = Vector2(x_off * s, -s * 0.10)
		eye.color = Color(0.03, 0.02, 0.08)
		n.add_child(eye)
	# Nose triangle.
	var nose := Polygon2D.new()
	nose.polygon = PackedVector2Array([
		Vector2(-s * 0.06, s * 0.10),
		Vector2( s * 0.06, s * 0.10),
		Vector2( 0.0,      s * 0.30),
	])
	nose.color = Color(0.03, 0.02, 0.08)
	n.add_child(nose)
	return n

func _circle_poly(r: float, n: int) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in n:
		var a: float = TAU * float(i) / n
		p.append(Vector2(cos(a), sin(a)) * r)
	return p

# Three-leaf laurel branch (rotated wedges). `mirror_x` flips it for the right side.
func _make_laurel(s: float, col: Color, mirror_x: bool) -> Node2D:
	var n := Node2D.new()
	var dir := -1.0 if mirror_x else 1.0
	for i in 3:
		var leaf := Polygon2D.new()
		var pts := PackedVector2Array()
		var off := Vector2(dir * (s * 0.30 + i * s * 0.18), -s * 0.40 + i * s * 0.30)
		var rot := dir * deg_to_rad(35.0 + i * 12.0)
		var n_pts := 12
		for j in n_pts + 1:
			var t: float = float(j) / n_pts
			var lp := Vector2(sin(t * PI) * s * 0.26, lerp(-s * 0.45, s * 0.45, t))
			pts.append(off + lp.rotated(rot))
		leaf.polygon = pts
		leaf.color = col
		n.add_child(leaf)
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
		# The orbit circles around the podium area to feel like the "stage".
		var r := sz.x * 0.42
		_orbit.position = Vector2(cx, sz.y * 0.48)
		_rebuild_ring(r)
		for i in _orbs.size():
			var a: float = -PI * 0.5 + i * TAU / _orbs.size()
			_orbs[i].position = Vector2(cos(a), sin(a)) * r

	var top := 14.0
	if _back:
		_back.position = Vector2(24, top + 4)
	if _header:
		_header.position = Vector2(cx - _header.size.x * 0.5, top)

	# Two columns: a wide scrolling rank table on the left and the top-3 podium on
	# the right. The TODAY/ALL-TIME toggle and the EASY/MOD/HARD difficulty tabs
	# stack above the table (toggle row first, then tabs row), both left-aligned to
	# the table so the controls read as belonging to it.
	var margin := 56.0
	var col_gap := 36.0
	var table_x := margin
	var nav_y := top + HEADER_H - 6.0
	if _range_toggle:
		_range_toggle.position = Vector2(table_x, nav_y)
	var tabs_y := nav_y + RANGE_TOGGLE_H + 12.0
	if _tab_row:
		_tab_row.position = Vector2(table_x, tabs_y)

	# Table fills the vertical space under the tabs down to the bottom margin.
	var table_y := tabs_y + TAB_H + 18.0
	var table_bottom := sz.y - 24.0
	if _scroll:
		_scroll.position = Vector2(table_x, table_y)
		_scroll.size = Vector2(LIST_W, maxf(60.0, table_bottom - table_y))
	if _list:
		_list.custom_minimum_size = Vector2(LIST_W, 0)

	# Podium sits in the space to the right of the table, centered both within
	# that space and vertically against the table's height.
	var podium_region_x := table_x + LIST_W + col_gap
	var podium_cx := podium_region_x + (sz.x - podium_region_x - margin) * 0.5
	var podium_y := table_y + ((table_bottom - table_y) - PODIUM_H) * 0.5
	if _podium:
		_layout_podium(podium_cx, maxf(table_y, podium_y))

	_layout_overlay()

# Centers the podium horizontally at cx with a fixed display order (left → right:
# rank 2, rank 1, rank 3). Slots stack onto a shared baseline (PODIUM_H), so the
# taller center column rises ABOVE the sides automatically.
func _layout_podium(cx: float, y: float) -> void:
	# Total width = sum of ped widths + gaps. Iterates in display order.
	var widths: Array[float] = []
	for rank_idx in PODIUM_DISPLAY_ORDER:
		widths.append(PODIUM_PED_W[rank_idx])
	var total_w := 0.0
	for w in widths:
		total_w += w
	total_w += PODIUM_GAP * (widths.size() - 1)

	var x := cx - total_w * 0.5
	for i in PODIUM_DISPLAY_ORDER.size():
		var rank_idx: int = PODIUM_DISPLAY_ORDER[i]
		var ped_w: float  = PODIUM_PED_W[rank_idx]
		var slot: Control = _podium_slots[rank_idx]["root"]
		# slot.size.x = max(card_w, ped_w) + 60 (glow slack). Aligning the
		# pedestal center to (x + ped_w/2) so all three pedestals share a
		# horizontal grid, even if their cards are different widths.
		var slot_cx := x + ped_w * 0.5
		slot.position = Vector2(slot_cx - slot.size.x * 0.5, y)
		x += ped_w + PODIUM_GAP
	_podium.position = Vector2.ZERO
	_podium.size = get_viewport_rect().size

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

# Header fades in first, then the orbit/back, then the nav row slides up.
func _intro() -> void:
	for n in [_header, _orbit, _back]:
		if n:
			n.modulate.a = 0.0
			create_tween().tween_property(n, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE)
	# Toggle + tabs share the row, so they share the intro motion — both ride
	# the same delay/duration so the row reads as one element settling in.
	# Annotate the iterator as Control so the type inference for `base_y` lands
	# on float (the array literal mixes Control + HBoxContainer types).
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
	if _podium:
		_podium.modulate.a = 0.0
		create_tween().tween_property(_podium, "modulate:a", 1.0, 0.5) \
			.set_delay(0.35).set_trans(Tween.TRANS_SINE)

# ---------------- data load ----------------

# Screen-open load: fetch BOTH ranges so flipping the toggle is instant. ALL-TIME
# is the default view, so we fetch + render it first (behind the loading screen),
# then preload TODAY silently in the background. If the player flips to TODAY
# before it lands they briefly see the spinner, then it fills in.
func _load_initial() -> void:
	_show_loading()
	_load_token += 1
	var token := _load_token

	var all_res := await LeaderboardManager.load_all_globals()
	if token != _load_token:
		return
	if not all_res.get("ok", false):
		_show_error()
		return
	_caches[RANGE_ALL] = all_res
	_loaded_ranges[RANGE_ALL] = true
	if _current_range == RANGE_ALL:
		_hide_overlay()
		_render(_caches[RANGE_ALL].get(_current_diff, {}))

	# Background-load TODAY. A toggle flip mid-flight bumps _load_token, so this
	# bails harmlessly and the flip's own _load_range takes over.
	var daily_res := await LeaderboardManager.load_all_dailies()
	if token != _load_token:
		return
	if daily_res.get("ok", false):
		_caches[RANGE_DAILY] = daily_res
		_loaded_ranges[RANGE_DAILY] = true
		# Player already flipped to TODAY while it was loading — render now.
		if _current_range == RANGE_DAILY:
			_hide_overlay()
			_render(_caches[RANGE_DAILY].get(_current_diff, {}))

# Re-entrant: bumps the token so any in-flight load from a previous range/diff
# becomes a no-op when it returns. Always fetches the CURRENT range; the other
# range stays in its cache (or empty until the user flips to it).
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
	# Only render if the player is still looking at the range we just loaded
	# (they may have flipped the toggle while it was in flight; that case
	# already triggered a separate _load_range for the new range).
	if range_key == _current_range:
		_hide_overlay()
		_render(_caches[range_key].get(_current_diff, {}))

# ---------------- overlay ----------------

func _build_overlay() -> void:
	_overlay = Panel.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var s := StyleBoxFlat.new()
	# Near-opaque deep navy — fully hides the empty board so this reads as a
	# loading screen, not a spinner sitting on top of blank table rows.
	s.bg_color = Color(0.008, 0.020, 0.075, 0.985)
	_overlay.add_theme_stylebox_override("panel", s)
	add_child(_overlay)

	# --- loading spinner (orbiting orbs + caption) ---
	_ov_spinner = Control.new()
	_ov_spinner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_ov_spinner)

	_ov_orbit = Node2D.new()
	_ov_spinner.add_child(_ov_orbit)
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
		orb.scale = Vector2.ONE * 0.62          # smaller than the page orbs
		var a: float = -PI * 0.5 + i * TAU / ORB_COLORS.size()
		orb.position = Vector2(cos(a), sin(a)) * r
		_ov_orbit.add_child(orb)
		_ov_orbs.append(orb)

	_ov_caption = Label.new()
	_ov_caption.text = "Loading leaderboards"
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

	# --- error box (message + retry) ---
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
	_overlay_retry.pressed.connect(func() -> void: _load_range(_current_range))
	_ov_box.add_child(_overlay_retry)

	# Perpetual spinner motion (rotation + per-orb pulse + caption dots). Cheap to
	# leave running; the whole overlay just hides when not loading.
	var rot := create_tween().set_loops()
	rot.tween_property(_ov_orbit, "rotation", TAU, 2.6).from(0.0).set_trans(Tween.TRANS_LINEAR)
	for i in _ov_orbs.size():
		var dur := 0.7 + i * 0.05
		var base := _ov_orbs[i].scale
		var pulse := create_tween().set_loops()
		pulse.tween_property(_ov_orbs[i], "scale", base * 1.14, dur) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		pulse.tween_property(_ov_orbs[i], "scale", base, dur) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var dots := create_tween().set_loops()
	dots.tween_interval(0.35)
	dots.tween_callback(_ov_tick_dots)

	_overlay.visible = false

func _ov_tick_dots() -> void:
	if _ov_caption == null or not _ov_caption.visible:
		return
	_ov_dots_idx = (_ov_dots_idx + 1) % 4
	_ov_caption.text = "Loading leaderboards" + ".".repeat(_ov_dots_idx)

func _layout_overlay() -> void:
	if _overlay == null:
		return
	var sz := get_viewport_rect().size
	_overlay.position = Vector2.ZERO
	_overlay.size = sz
	if _ov_orbit:
		_ov_orbit.position = Vector2(sz.x * 0.5, sz.y * 0.45)
	if _ov_caption:
		_ov_caption.position = Vector2(sz.x * 0.5 - 180, sz.y * 0.45 + 86)

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
