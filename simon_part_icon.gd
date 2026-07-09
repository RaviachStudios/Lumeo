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
var tint: Variant = null         # Color, style Dictionary, or null (ring/hub parts)
var font_pack: Variant = null    # Dictionary or null (level_number)

# tint can now be a pattern/motif style: {"pattern": int, "a": Color, "b": Color}
# (see CoinsManager.simon_part_style). Rim pattern codes 1-10, hub motif codes
# 21-35 — the same ints SimonWheel's _STYLE_SHADER branches on, drawn here in 2D.

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
		if tint is Dictionary:
			_draw_rim_pattern(c, rim_mid, rim_w, RIM_OUT * scale, tint)
		else:
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
		if tint is Dictionary:
			_draw_hub_motif(c, hub_r, tint)
		else:
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

# ---------------- patterned OUTER RING (2D preview of a rim pattern) ----------------

static func _fr(x: float) -> float:
	return x - floor(x)

# Per-angle rim colour for the continuous patterns; the dotted/spotted styles
# (3 dots, 7 leopard, 9 stars) return their base ink and get discrete overlays.
func _rim_slice_color(pid: int, a: Color, b: Color, ang: float) -> Color:
	var u := ang / TAU
	match pid:
		1:  return b if _fr(u * 11.0) < 0.5 else a            # zebra
		2:  return Color.from_hsv(_fr(u + 1.0), 0.85, 1.0)    # rainbow
		4:  return b if _fr(u * 13.0) < 0.5 else a            # candy cane
		5:  return b if _fr(u * 10.0) < 0.5 else a            # checker (ring stripes)
		6:                                                    # tiger: thin dark bars
			return b if absf(_fr(u * 13.0) - 0.5) * 2.0 > 0.62 else a
		8:  return a.lerp(b, 0.5 + 0.5 * sin(ang * 2.0))      # gradient
		10: return a.lerp(b, 0.5 + 0.5 * sin(ang * 8.0))      # ocean wave
		_:  return a

func _draw_rim_pattern(c: Vector2, rim_mid: float, rim_w: float, rim_out_r: float, pat: Dictionary) -> void:
	var pid := int(pat.get("pattern", 0))
	var a: Color = pat.get("a", Color.GRAY)
	var b: Color = pat.get("b", Color.WHITE)
	# soft outer halo tinted by the primary ink
	draw_arc(c, rim_out_r + rim_w * 0.35, 0.0, TAU, 64, Color(a.r, a.g, a.b, 0.16), rim_w * 1.5, true)
	var n := 90
	for i in n:
		var a0 := float(i) / n * TAU
		var a1 := float(i + 1) / n * TAU + 0.012
		draw_arc(c, rim_mid, a0, a1, 2, _rim_slice_color(pid, a, b, (a0 + a1) * 0.5), rim_w, true)
	# discrete dots / spots / stars sitting on the ring
	if pid == 3 or pid == 7 or pid == 9:
		var count := 22 if pid == 9 else 15
		var dr := rim_w * (0.24 if pid == 3 else (0.30 if pid == 7 else 0.13))
		for i in count:
			var ang := (float(i) + 0.5) / count * TAU
			var p := c + Vector2(cos(ang), sin(ang)) * rim_mid
			draw_circle(p, dr, b)
			if pid == 7:   # leopard: dark ring around each spot
				draw_arc(p, dr * 1.25, 0.0, TAU, 12, Color(b.r, b.g, b.b, 0.7), maxf(1.0, dr * 0.4), true)
	draw_arc(c, rim_out_r, 0.0, TAU, 64, Color(1, 1, 1, 0.4), 1.5, true)

# ---------------- drawn CENTER HUB (2D preview of a hub motif) ----------------

func _draw_hub_motif(c: Vector2, r: float, pat: Dictionary) -> void:
	var pid := int(pat.get("pattern", 0))
	var a: Color = pat.get("a", Color.GRAY)
	var b: Color = pat.get("b", Color.WHITE)
	draw_circle(c, r * 1.28, Color(a.r, a.g, a.b, 0.18))     # halo
	if pid == 28:                                            # rainbow: hued rings
		var rings := 6
		for i in range(rings, 0, -1):
			var rr := r * float(i) / rings
			draw_circle(c, rr, Color.from_hsv(float(i) / rings, 0.8, 1.0))
	else:
		draw_circle(c, r, a)                                # base disc
	match pid:
		21: draw_colored_polygon(_star_pts(c, r * 0.86, r * 0.40, 5, -PI * 0.5), b)  # star
		22: _draw_flower(c, r, b)
		23: _draw_smiley(c, r, b)
		24: _draw_scatter_dots(c, r, b)
		25: _draw_paw(c, r, b)
		26:                                                 # bullseye rings
			draw_arc(c, r * 0.66, 0.0, TAU, 40, b, r * 0.20, true)
			draw_circle(c, r * 0.24, b)
		27: _draw_swirl(c, r, b)
		30: _draw_crescent(c, r, a, b)
		31: _draw_diamond(c, r, a, b)
		32: _draw_clover(c, r, b)
		33: _draw_bolt(c, r, b)
		34: _draw_yinyang(c, r, a, b)
		35: _draw_note(c, r, b)
		_: pass
	draw_arc(c, r, 0.0, TAU, 44, Color(1, 1, 1, 0.5), 1.5, true)

# N-point star: alternating outer / inner radius vertices.
func _star_pts(c: Vector2, r_out: float, r_in: float, n: int, rot: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n * 2:
		var rad := r_out if i % 2 == 0 else r_in
		var ang := rot + float(i) / (n * 2) * TAU
		pts.append(c + Vector2(cos(ang), sin(ang)) * rad)
	return pts

func _draw_flower(c: Vector2, r: float, b: Color) -> void:
	var petals := 6
	for i in petals:
		var ang := float(i) / petals * TAU
		var p := c + Vector2(cos(ang), sin(ang)) * r * 0.5
		draw_circle(p, r * 0.34, b)
	draw_circle(c, r * 0.30, Color(1.0, 0.84, 0.28))         # sunny center

func _draw_smiley(c: Vector2, r: float, b: Color) -> void:
	draw_circle(c + Vector2(-r * 0.34, -r * 0.22), r * 0.14, b)
	draw_circle(c + Vector2(r * 0.34, -r * 0.22), r * 0.14, b)
	draw_arc(c + Vector2(0, -r * 0.05), r * 0.48, deg_to_rad(25.0), deg_to_rad(155.0), 24, b, r * 0.11, true)

func _draw_scatter_dots(c: Vector2, r: float, b: Color) -> void:
	var offs := [Vector2(-0.42, -0.30), Vector2(0.40, -0.36), Vector2(0.0, 0.0),
		Vector2(-0.46, 0.34), Vector2(0.44, 0.30), Vector2(0.02, -0.52), Vector2(0.0, 0.52)]
	for o in offs:
		draw_circle(c + (o as Vector2) * r, r * 0.16, b)

func _draw_paw(c: Vector2, r: float, b: Color) -> void:
	draw_circle(c + Vector2(0, r * 0.22), r * 0.42, b)       # main pad
	for o in [Vector2(-0.42, -0.34), Vector2(-0.15, -0.52), Vector2(0.15, -0.52), Vector2(0.42, -0.34)]:
		draw_circle(c + (o as Vector2) * r, r * 0.17, b)     # toes

func _draw_swirl(c: Vector2, r: float, b: Color) -> void:
	var pts := PackedVector2Array()
	var turns := 2.4
	var steps := 60
	for i in steps + 1:
		var f := float(i) / steps
		var ang := f * turns * TAU
		var rad := r * 0.9 * f
		pts.append(c + Vector2(cos(ang), sin(ang)) * rad)
	draw_polyline(pts, b, maxf(2.0, r * 0.14), true)

# Crescent moon: a pale disc with an offset disc bitten out (drawn in the base `a`),
# plus a small 4-point star glint tucked into the notch.
func _draw_crescent(c: Vector2, r: float, a: Color, b: Color) -> void:
	draw_circle(c + Vector2(-r * 0.12, 0.0), r * 0.72, b)
	draw_circle(c + Vector2(r * 0.30, -r * 0.05), r * 0.66, a)
	draw_colored_polygon(_star_pts(c + Vector2(r * 0.44, -r * 0.46), r * 0.16, r * 0.06, 4, -PI * 0.5), b)

# Faceted gem: a rhombus body with a table girdle line and two facet lines drawn in
# the base colour, so it reads as a cut diamond.
func _draw_diamond(c: Vector2, r: float, a: Color, b: Color) -> void:
	var top := c + Vector2(0, -r * 0.80)
	var bot := c + Vector2(0, r * 0.80)
	var lft := c + Vector2(-r * 0.60, 0)
	var rgt := c + Vector2(r * 0.60, 0)
	draw_colored_polygon(PackedVector2Array([top, rgt, bot, lft]), b)
	var lw := maxf(1.5, r * 0.05)
	var tl := c + Vector2(-r * 0.30, -r * 0.34)
	var tr := c + Vector2(r * 0.30, -r * 0.34)
	draw_line(tl, tr, a, lw)          # table girdle
	draw_line(tl, bot, a, lw)         # facet down to the point
	draw_line(tr, bot, a, lw)

# Lucky clover: four round leaves around the centre plus a little stem.
func _draw_clover(c: Vector2, r: float, b: Color) -> void:
	for i in 4:
		var ang := (float(i) + 0.5) / 4.0 * TAU
		draw_circle(c + Vector2(cos(ang), sin(ang)) * r * 0.34, r * 0.40, b)
	draw_line(c + Vector2(0, r * 0.30), c + Vector2(r * 0.14, r * 0.82), b, maxf(2.0, r * 0.12))

# Lightning: a three-segment zigzag bolt drawn as a thick stroke.
func _draw_bolt(c: Vector2, r: float, b: Color) -> void:
	var pts := PackedVector2Array([
		c + Vector2(r * 0.22, -r * 0.78), c + Vector2(-r * 0.18, -r * 0.05),
		c + Vector2(r * 0.16, -r * 0.05), c + Vector2(-r * 0.22, r * 0.78)])
	draw_polyline(pts, b, maxf(2.5, r * 0.20), true)

# Yin-yang: two teardrops swapped along an S-curve, each holding a dot of the
# opposite ink. `a` is the dark half, `b` the light half.
func _draw_yinyang(c: Vector2, r: float, a: Color, b: Color) -> void:
	# Light half on the right, built from a semicircle polygon.
	var half := PackedVector2Array()
	var steps := 24
	for i in steps + 1:
		var t := -PI * 0.5 + float(i) / steps * PI
		half.append(c + Vector2(cos(t), sin(t)) * r)
	draw_colored_polygon(half, b)
	draw_circle(c + Vector2(0, -r * 0.5), r * 0.5, a)     # upper bulge -> a
	draw_circle(c + Vector2(0, r * 0.5), r * 0.5, b)      # lower bulge -> b
	draw_circle(c + Vector2(0, -r * 0.5), r * 0.14, b)    # b eye in a lobe
	draw_circle(c + Vector2(0, r * 0.5), r * 0.14, a)     # a eye in b lobe

# Melody: an eighth note — round head, upright stem, flag off the top.
func _draw_note(c: Vector2, r: float, b: Color) -> void:
	draw_circle(c + Vector2(-r * 0.18, r * 0.42), r * 0.26, b)
	var lw := maxf(2.0, r * 0.11)
	draw_line(c + Vector2(r * 0.06, r * 0.42), c + Vector2(r * 0.06, -r * 0.62), b, lw)
	draw_line(c + Vector2(r * 0.06, -r * 0.62), c + Vector2(r * 0.34, -r * 0.34), b, lw)
