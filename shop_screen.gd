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
const TAB_W := 168.0
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

	if _grid:
		var grid_w := GRID_COLS * CARD_W + (GRID_COLS - 1) * CARD_GAP_X
		_grid.position = Vector2(cx - grid_w * 0.5, top + HEADER_H + 8.0 + TAB_H + 28.0)

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
