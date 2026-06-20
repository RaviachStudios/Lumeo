extends Control
class_name SimonPartIcon

# A small 2D icon for the shop's SIMON tab that makes each customisable part of
# the wheel obvious:
#   • "outer_circle" / "inner_circle" -> a schematic wheel (rim + segmented button
#     ring + hub, NO numeral) drawn in _draw, with THIS part strongly highlighted
#     in the chosen colour and everything else a faint grey sketch.
#   • "level_number" -> JUST the level numeral "1" in the chosen font package.
#     This is rendered with stacked Label children (glow + main), NOT immediate-mode
#     draw_string: a freshly-loaded dynamic font rasterizes its glyph lazily, and
#     drawing it in _draw the same frame paints a filled box (the glyph atlas isn't
#     uploaded yet). Labels integrate with the font system and render reliably.
#
#   category  : "outer_circle" | "inner_circle" | "level_number"
#   tint      : Color of the chosen colour for the ring/hub parts, or null = stock
#   font_pack : Dictionary describing the level-number font style (see CoinsManager
#               .SIMON_NUMBER_FONTS), or null = stock white numeral

var category: String = "outer_circle"
var tint: Variant = null         # Color or null (ring/hub parts)
var font_pack: Variant = null    # Dictionary or null (level_number)

var _num_glow: Label             # soft outer-glow layer (level_number)
var _num_main: Label             # main numeral layer (level_number)

# Geometry as fractions of the wheel's outer rim radius (mirrors simon_wheel.gd's
# relative proportions, flattened to a top-down sketch).
const RIM_OUT := 1.16
const RIM_IN := 1.00
const BTN_OUT := 0.96
const BTN_IN := 0.40
const HUB_R := 0.36
const SEG_COUNT := 5
const SEG_GAP_DEG := 9.0

# Faint "sketch" palette for the parts that are NOT this tile's category — present
# for context so the wheel is recognisable, but clearly de-emphasised.
const SKETCH_RIM := Color(0.36, 0.40, 0.55, 0.40)
const SKETCH_SEG := Color(0.30, 0.34, 0.50, 0.40)
const SKETCH_HUB := Color(0.22, 0.25, 0.36, 0.55)

func setup(part: String, part_tint: Variant, pack: Variant = null) -> void:
	category = part
	tint = part_tint
	font_pack = pack
	if part == "level_number":
		_ensure_number_labels()
		_config_number_labels()
	_set_number_visible(part == "level_number")
	queue_redraw()

# ---------------- level-number numeral (Label children) ----------------

func _ensure_number_labels() -> void:
	if _num_main != null:
		return
	_num_glow = _make_num_label()
	add_child(_num_glow)
	_num_main = _make_num_label()
	add_child(_num_main)

func _make_num_label() -> Label:
	var l := Label.new()
	l.text = "1"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _set_number_visible(v: bool) -> void:
	if _num_glow != null:
		_num_glow.visible = v
	if _num_main != null:
		_num_main.visible = v

func _config_number_labels() -> void:
	var pack: Dictionary = font_pack if (font_pack is Dictionary) else {}
	var font: Font = null
	var fp := String(pack.get("font", ""))
	if fp != "" and ResourceLoader.exists(fp):
		var f := load(fp)
		if f is Font:
			font = f
	var fs := int(minf(size.x, size.y) * 0.62)
	for l in [_num_glow, _num_main]:
		if font != null:
			l.add_theme_font_override("font", font)
		else:
			l.remove_theme_font_override("font")
		l.add_theme_font_size_override("font_size", fs)

	# Glow layer: invisible glyph fill, a soft coloured shadow (centred = halo).
	_num_glow.add_theme_color_override("font_color", Color(0, 0, 0, 0))
	_num_glow.add_theme_color_override("font_shadow_color", pack.get("glow", Color(0.45, 0.68, 1.0, 0.5)))
	_num_glow.add_theme_constant_override("shadow_offset_x", 0)
	_num_glow.add_theme_constant_override("shadow_offset_y", 0)
	_num_glow.add_theme_constant_override("shadow_outline_size", int(pack.get("glow_size", 10)))

	# Main numeral: fill + a CONTRASTING outline so it reads on a same-colour hub.
	_num_main.add_theme_color_override("font_color", pack.get("color", Color.WHITE))
	_num_main.add_theme_color_override("font_outline_color", pack.get("outline", Color(0, 0, 0, 1)))
	_num_main.add_theme_constant_override("outline_size", int(pack.get("outline_size", 4)))

# ---------------- ring / hub schematic (_draw) ----------------

func _draw() -> void:
	if category == "level_number":
		return   # numeral is drawn by the Label children
	var s: float = minf(size.x, size.y)
	var c := size * 0.5
	var scale: float = (s * 0.46) / RIM_OUT
	var rim_active := category == "outer_circle"
	var hub_active := category == "inner_circle"

	# --- segmented button ring (always faint context) ---
	# Thick stroked arcs (a band of the ring's radial thickness): draw_arc with a
	# width renders a correct annular wedge, unlike a concave fill polygon.
	var seg_mid: float = (BTN_OUT + BTN_IN) * 0.5 * scale
	var seg_w: float = (BTN_OUT - BTN_IN) * scale
	var gap := deg_to_rad(SEG_GAP_DEG)
	var step := TAU / SEG_COUNT
	for i in SEG_COUNT:
		var a0: float = -PI * 0.5 + i * step + gap * 0.5
		var a1: float = -PI * 0.5 + (i + 1) * step - gap * 0.5
		draw_arc(c, seg_mid, a0, a1, 10, SKETCH_SEG, seg_w, true)

	# --- outer rim ring ---
	var rim_mid: float = (RIM_OUT + RIM_IN) * 0.5 * scale
	var rim_w: float = (RIM_OUT - RIM_IN) * scale
	if rim_active:
		var col := _display_color(Color(0.64, 0.66, 0.74))
		draw_arc(c, RIM_OUT * scale + rim_w * 0.35, 0.0, TAU, 64, Color(col.r, col.g, col.b, 0.18), rim_w * 1.5, true)
		draw_arc(c, rim_mid, 0.0, TAU, 64, col, rim_w, true)
		draw_arc(c, RIM_OUT * scale, 0.0, TAU, 64, Color(1, 1, 1, 0.45), 1.5, true)
	else:
		draw_arc(c, RIM_OUT * scale, 0.0, TAU, 64, SKETCH_RIM, maxf(1.5, rim_w * 0.26), true)
		draw_arc(c, RIM_IN * scale, 0.0, TAU, 64, SKETCH_RIM, maxf(1.5, rim_w * 0.26), true)

	# --- centre hub ---
	var hub_r: float = HUB_R * scale
	if hub_active:
		var hcol := _display_color(Color(0.40, 0.40, 0.48))
		draw_circle(c, hub_r * 1.28, Color(hcol.r, hcol.g, hcol.b, 0.18))   # halo
		draw_circle(c, hub_r, hcol)
		draw_arc(c, hub_r, 0.0, TAU, 44, Color(1, 1, 1, 0.5), 1.5, true)
	else:
		draw_circle(c, hub_r, SKETCH_HUB)
		draw_arc(c, hub_r, 0.0, TAU, 40, Color(1, 1, 1, 0.08), 1.5, true)

# The colour this part wears: the chosen tint (lifted into a clearly visible range
# the way the wheel enriches its colours), or the supplied stock graphite/white
# fallback when no real colour is equipped.
func _display_color(stock: Color) -> Color:
	if tint is Color:
		var t: Color = tint
		var v: float = clampf(maxf(t.v * 1.2, 0.6), 0.0, 1.0)
		return Color.from_hsv(t.h, t.s, v, 1.0)
	return stock
