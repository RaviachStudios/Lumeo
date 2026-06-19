extends Control

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
		# handles it without special casing.
		"items": ["default", "skybound", "inferno"],
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
	{"cat": "outer_circle", "label": "OUTER CIRCLE"},
	{"cat": "inner_circle", "label": "INNER CIRCLE"},
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
var _tab_row: HBoxContainer
var _tabs: Array[Dictionary] = []
var _grid: GridContainer
var _cards_by_id: Dictionary = {}        # theme_id -> { root, btn, btn_label, price_label, badge }
var _current_cat: String = "themes"

# --- SIMON tab ---
const SIMON_ACCENT := Color(0.58, 0.46, 1.00)
var _simon_root: Control                 # SIMON colour panel (built lazily)
var _simon_preview: SimonWheel           # live wheel reflecting the equipped colours
var _simon_tiles_box: Control            # holds the three colour tiles
var _simon_tiles: Dictionary = {}        # category -> {swatch, value_lbl}
var _skins_root: Control                 # SPECIAL SKINS placeholder panel (built lazily)
# Colour popup (opened from a tile):
var _color_popup: Control
var _popup_category: String = ""
var _popup_cards: Dictionary = {}        # color_id -> {btn, price_row, accent}

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
	CoinsManager.simon_changed.connect(_refresh_simon_panel)
	CoinsManager.simon_changed.connect(_refresh_color_cards)
	# Equipping from inside the shop flips BackgroundManager.is_themed() under
	# us — without this, the shop's own deep-space bg stays in place over the
	# new global theme (or vanishes to grey when the player re-equips default),
	# and the change only becomes visible after navigating back to home.
	CoinsManager.themes_changed.connect(_sync_local_background)
	_render_category(_current_cat)

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

func _on_balance_changed(new_balance: int) -> void:
	if _coin_lbl:
		_coin_lbl.text = str(new_balance)
	# Card affordability changes with balance too.
	_refresh_cards()
	_refresh_color_cards()

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
	_grid = GridContainer.new()
	_grid.columns = GRID_COLS
	_grid.add_theme_constant_override("h_separation", int(CARD_GAP_X))
	_grid.add_theme_constant_override("v_separation", int(CARD_GAP_Y))
	add_child(_grid)

func _render_category(key: String) -> void:
	# THEMES uses the card grid; SIMON and SPECIAL SKINS each have a bespoke panel.
	# Hide them all, then show the one for this category.
	_grid.visible = false
	if _simon_root:
		_simon_root.visible = false
	if _skins_root:
		_skins_root.visible = false

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
		_layout()
		return

	_grid.visible = true
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
	for theme_id in cat.get("items", []):
		var card := _make_card(theme_id, cat["accent"])
		_grid.add_child(card["root"])
		_cards_by_id[theme_id] = card
	_refresh_cards()

func _make_card(theme_id: String, accent: Color) -> Dictionary:
	var meta: Dictionary = CoinsManager.THEMES.get(theme_id, {})
	var pretty_name: String = meta.get("name", theme_id.capitalize())

	var root := Panel.new()
	root.custom_minimum_size = Vector2(CARD_W, CARD_H)
	root.size = Vector2(CARD_W, CARD_H)
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
	#   ↓   price (coin + number) — hidden if owned  (28 tall)
	#   ↓   action button                            (48 tall, bottom-anchored)
	var below_preview := 16 + PREVIEW_H + 12.0

	var name_lbl := Label.new()
	name_lbl.text = pretty_name.to_upper()
	name_lbl.add_theme_font_size_override("font_size", 22)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	name_lbl.position = Vector2(16, below_preview)
	name_lbl.size = Vector2(CARD_W - 32, 28)
	root.add_child(name_lbl)

	# Price row: small gold coin + number, hidden once the player owns the theme.
	var price_row := Control.new()
	price_row.position = Vector2(16, below_preview + 32.0)
	price_row.size = Vector2(CARD_W - 32, 28)
	price_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(price_row)

	var price_coin := _make_big_coin(12.0)
	price_coin.position = Vector2(11, 14)
	price_row.add_child(price_coin)
	var price_lbl := Label.new()
	price_lbl.text = str(CoinsManager.theme_price(theme_id))
	price_lbl.add_theme_font_size_override("font_size", 20)
	price_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45))
	price_lbl.position = Vector2(26, 0)
	price_lbl.size = Vector2(price_row.size.x - 26, 28)
	price_row.add_child(price_lbl)

	var btn := Button.new()
	btn.size = Vector2(CARD_W - 32, 48)
	btn.position = Vector2(16, CARD_H - 48 - 16)
	btn.add_theme_font_size_override("font_size", 19)
	btn.focus_mode = Control.FOCUS_NONE
	root.add_child(btn)

	btn.pressed.connect(func() -> void: _on_action(theme_id))
	return {
		"root": root, "btn": btn, "price_row": price_row,
		"price_label": price_lbl, "accent": accent,
	}

# Apply BUY / EQUIP / EQUIPPED visual state to all cards in the current grid.
func _refresh_cards() -> void:
	for theme_id in _cards_by_id:
		var c: Dictionary = _cards_by_id[theme_id]
		_apply_card_state(theme_id, c)

func _apply_card_state(theme_id: String, c: Dictionary) -> void:
	var btn: Button = c["btn"]
	var accent: Color = c["accent"]
	var price_row: Control = c["price_row"]
	var owned := CoinsManager.owns(theme_id)
	var equipped := CoinsManager.selected_theme == theme_id
	var affordable := CoinsManager.can_afford(theme_id)

	price_row.visible = not owned
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
		label_text = "BUY"
		bg_col = Color(1.00, 0.66, 0.10)
		fg_col = Color(0.18, 0.10, 0.0)
	else:
		label_text = "BUY  (need %d)" % (CoinsManager.theme_price(theme_id) - CoinsManager.balance)
		bg_col = Color(0.30, 0.30, 0.40)
		fg_col = Color(0.85, 0.85, 0.95, 0.7)
		btn.disabled = true

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
	# Not yet owned. Try to purchase; signal-driven refresh handles the UI.
	if not CoinsManager.purchase_theme(theme_id):
		return
	# Auto-equip a freshly purchased theme so the player sees their reward
	# immediately the next time they leave the shop.
	CoinsManager.select_theme(theme_id)

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
	_simon_preview.set_level(3)

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

# SPECIAL SKINS category — a placeholder until complete skins ship.
func _build_skins_panel() -> void:
	_skins_root = Control.new()
	_skins_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skins_root.custom_minimum_size = Vector2(SIMON_PANEL_W, 200)
	_skins_root.size = Vector2(SIMON_PANEL_W, 200)
	add_child(_skins_root)
	var soon := Label.new()
	soon.text = "Complete skins coming soon"
	soon.add_theme_font_size_override("font_size", 24)
	soon.add_theme_color_override("font_color", Color(0.78, 0.72, 0.90, 0.9))
	soon.position = Vector2(0, 70)
	soon.size = Vector2(SIMON_PANEL_W, 44)
	soon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	soon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skins_root.add_child(soon)

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

	# Round colour swatch showing the equipped colour for this part.
	var swatch := Panel.new()
	swatch.size = Vector2(SIMON_SWATCH, SIMON_SWATCH)
	swatch.position = Vector2((SIMON_TILE_W - SIMON_SWATCH) * 0.5, 18)
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(swatch)

	var name_lbl := Label.new()
	name_lbl.text = label
	name_lbl.add_theme_font_size_override("font_size", 17)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	name_lbl.position = Vector2(8, 18 + SIMON_SWATCH + 12)
	name_lbl.size = Vector2(SIMON_TILE_W - 16, 26)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(name_lbl)

	var value_lbl := Label.new()
	value_lbl.add_theme_font_size_override("font_size", 15)
	value_lbl.add_theme_color_override("font_color", Color(0.74, 0.78, 1.0, 0.9))
	value_lbl.position = Vector2(8, 18 + SIMON_SWATCH + 38)
	value_lbl.size = Vector2(SIMON_TILE_W - 16, 24)
	value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(value_lbl)

	root.pressed.connect(func() -> void: _open_color_popup(category))
	_simon_tiles[category] = {"swatch": swatch, "value_lbl": value_lbl}
	return root

func _style_swatch(swatch: Panel, color_id: String) -> void:
	var st := StyleBoxFlat.new()
	st.bg_color = CoinsManager.simon_color_value(color_id)
	st.set_corner_radius_all(int(SIMON_SWATCH * 0.5))
	st.border_color = Color(1, 1, 1, 0.35)
	st.set_border_width_all(2)
	# Default reads as the "stock" look — give it a muted ring so it's clearly
	# the no-tint option rather than a real colour.
	if color_id == CoinsManager.SIMON_DEFAULT_COLOR:
		st.border_color = Color(1, 1, 1, 0.15)
	swatch.add_theme_stylebox_override("panel", st)

func _refresh_simon_panel() -> void:
	if _simon_root == null:
		return
	# tile swatches + equipped colour names.
	for cat in _simon_tiles:
		var t: Dictionary = _simon_tiles[cat]
		var id: String = CoinsManager.equipped_simon_color(cat)
		_style_swatch(t["swatch"], id)
		t["value_lbl"].text = String(CoinsManager.SIMON_COLORS.get(id, {}).get("name", id.capitalize()))
	# Live preview mirrors what the wheel actually wears right now.
	_refresh_simon_preview()

# Re-tint the preview wheel to match the equipped colours.
func _refresh_simon_preview() -> void:
	if _simon_preview == null:
		return
	_simon_preview.apply_skin(
		_simon_tint("outer_circle"),
		_simon_tint("inner_circle"),
		_simon_tint("level_number"))

# The Color tint a part wears right now, or null for the stock look — mirrors
# game.gd._resolved_simon_tint so the preview matches the real in-game wheel.
func _simon_tint(category: String) -> Variant:
	if not CoinsManager.is_simon_manual():
		return null
	var id := CoinsManager.equipped_simon_color(category)
	if id == CoinsManager.SIMON_DEFAULT_COLOR:
		return null
	return CoinsManager.simon_color_value(id)

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
	for color_id in CoinsManager.SIMON_COLORS.keys():
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
	var meta: Dictionary = CoinsManager.SIMON_COLORS.get(color_id, {})
	var pretty: String = meta.get("name", color_id.capitalize())

	var root := Panel.new()
	root.custom_minimum_size = Vector2(SWATCH_CARD_W, SWATCH_CARD_H)
	root.size = Vector2(SWATCH_CARD_W, SWATCH_CARD_H)
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.07, 0.09, 0.22, 0.92)
	cs.set_corner_radius_all(16)
	cs.border_color = Color(1, 1, 1, 0.10)
	cs.set_border_width_all(1)
	root.add_theme_stylebox_override("panel", cs)

	# Colour swatch.
	var sw := 64.0
	var swatch := Panel.new()
	swatch.size = Vector2(sw, sw)
	swatch.position = Vector2((SWATCH_CARD_W - sw) * 0.5, 12)
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ss := StyleBoxFlat.new()
	ss.bg_color = CoinsManager.simon_color_value(color_id)
	ss.set_corner_radius_all(int(sw * 0.5))
	ss.border_color = Color(1, 1, 1, 0.30 if color_id != CoinsManager.SIMON_DEFAULT_COLOR else 0.12)
	ss.set_border_width_all(2)
	swatch.add_theme_stylebox_override("panel", ss)
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

	# Price row (coin + number), hidden once owned.
	var price_row := Control.new()
	price_row.position = Vector2(0, 12 + sw + 28)
	price_row.size = Vector2(SWATCH_CARD_W, 22)
	price_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(price_row)
	var price_coin := _make_big_coin(9.0)
	price_coin.position = Vector2(SWATCH_CARD_W * 0.5 - 22, 11)
	price_row.add_child(price_coin)
	var price_lbl := Label.new()
	price_lbl.text = str(CoinsManager.simon_color_price(color_id))
	price_lbl.add_theme_font_size_override("font_size", 16)
	price_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45))
	price_lbl.position = Vector2(SWATCH_CARD_W * 0.5 - 8, 0)
	price_lbl.size = Vector2(60, 22)
	price_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price_row.add_child(price_lbl)

	var btn := Button.new()
	btn.size = Vector2(SWATCH_CARD_W - 20, 36)
	btn.position = Vector2(10, SWATCH_CARD_H - 36 - 10)
	btn.add_theme_font_size_override("font_size", 16)
	btn.focus_mode = Control.FOCUS_NONE
	root.add_child(btn)
	btn.pressed.connect(func() -> void: _on_color_action(category, color_id))

	return {"root": root, "btn": btn, "price_row": price_row, "accent": SIMON_ACCENT}

func _refresh_color_cards() -> void:
	if _popup_category.is_empty():
		return
	for color_id in _popup_cards:
		_apply_color_card_state(_popup_category, color_id, _popup_cards[color_id])

func _apply_color_card_state(category: String, color_id: String, c: Dictionary) -> void:
	var btn: Button = c["btn"]
	var accent: Color = c["accent"]
	var price_row: Control = c["price_row"]
	var owned := CoinsManager.owns_simon_color(category, color_id)
	var equipped := CoinsManager.equipped_simon_color(category) == color_id
	var affordable := CoinsManager.can_afford_simon(color_id)

	price_row.visible = not owned
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
		label_text = "BUY"
		bg_col = Color(1.00, 0.66, 0.10)
		fg_col = Color(0.18, 0.10, 0.0)
	else:
		label_text = "need %d" % (CoinsManager.simon_color_price(color_id) - CoinsManager.balance)
		bg_col = Color(0.30, 0.30, 0.40)
		fg_col = Color(0.85, 0.85, 0.95, 0.7)
		btn.disabled = true

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
	if not CoinsManager.purchase_simon_color(category, color_id):
		return
	# Auto-equip a freshly bought colour so the choice takes effect at once.
	CoinsManager.equip_simon_color(category, color_id)

func _close_color_popup() -> void:
	if _color_popup and is_instance_valid(_color_popup):
		_color_popup.queue_free()
	_color_popup = null
	_popup_category = ""
	_popup_cards.clear()

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

	if _tab_row:
		var row_w := CATEGORIES.size() * TAB_W + maxi(0, CATEGORIES.size() - 1) * TAB_SEP
		_tab_row.position = Vector2(cx - row_w * 0.5, top + HEADER_H + 8.0)

	var content_y := top + HEADER_H + 8.0 + TAB_H + 28.0
	if _grid:
		var grid_w := GRID_COLS * CARD_W + (GRID_COLS - 1) * CARD_GAP_X
		_grid.position = Vector2(cx - grid_w * 0.5, content_y)
	if _simon_root:
		_simon_root.position = Vector2(cx - SIMON_PANEL_W * 0.5, content_y)
	if _skins_root:
		_skins_root.position = Vector2(cx - SIMON_PANEL_W * 0.5, content_y)

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
