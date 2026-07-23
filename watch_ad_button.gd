extends Button
# A physical, glossy hard-plastic push-button in a wide pill / "balloon" shape:
# a deep amber convex dome lit from the top-left, with real thickness, a floating
# contact shadow and bold white text. Entirely _draw()-based so we get smooth
# directional shading (no border / frame / rim / glow chrome a StyleBox would add).
# Depth comes only from gradients + shading. Reacts to the button's draw mode so
# pressing physically sinks and flattens it.
#
# `glow` (0..1) is the idle attention nudge: an ENVELOPE, not the animation. While
# it's up the button runs its own loop (see _process) and plays three things at
# once, so the eye can't miss it:
#   · a full aura wrapping the whole silhouette — ends included, not just a band
#     above and below — hottest at the rim and falling off amber → deep orange,
#   · a bright bolt of light that sweeps side to side across the face, leaning
#     like a real specular streak and clipped to the pill so nothing overhangs,
#   · a heartbeat: the button swells and settles on a lub-dub rhythm, with the
#     aura breathing on the same beat.
# game.gd tweens `glow` up, holds it, and tweens it back down.

# Deep golden / dark-amber body — rich and tactile, not bright yellow. Lighting
# is soft polished-plastic reflection, not a wet-glass white shine.
const FACE_TOP    := Color(0.72, 0.47, 0.07)   # lit upper crown
const FACE_BOTTOM := Color(0.34, 0.19, 0.015)  # shaded lower face
const WALL_COL    := Color(0.24, 0.125, 0.01)  # the button body / thickness
const REFLECT_COL := Color(1.0, 0.86, 0.55)    # subtle ambient plastic sheen
const GLOW_COL    := Color(0.98, 0.66, 0.16)   # aura core — matches the amber body
const GLOW_OUTER  := Color(1.0, 0.38, 0.06)    # aura fades out into a deep orange
const GLOW_RIM    := Color(1.0, 0.90, 0.62)    # hot lip hugging the silhouette
const BOLT_COL    := Color(1.0, 0.97, 0.86)    # the sweeping shine
const TEXT_COL    := Color(0.99, 0.98, 0.96)

const FS := 17
const PAD := 30.0

# --- attention loop ---
const AURA_REACH := 34.0    # how far the aura pushes past the silhouette, at rest
const AURA_LAYERS := 20
const BEAT_PERIOD := 0.95   # one lub-dub cycle
const BEAT_SCALE := 0.055   # peak swell (fraction of size)
const SWEEP_PERIOD := 1.5   # one crossing of the face
const SWEEP_BANDS := 16     # scanline bands the bolt is clipped into
const SWEEP_SLANT := 0.42   # lean, as a fraction of height

var glow: float = 0.0:
	set(v):
		glow = v
		var on := glow > 0.001
		set_process(on)
		if not on:
			_phase = 0.0
			scale = Vector2.ONE
		queue_redraw()

var _phase := 0.0           # seconds since the nudge began; drives beat + sweep

func _ready() -> void:
	# We render the dome AND the label ourselves — strip the button's own chrome.
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(st, empty)
	# Fit the pill to the text with generous horizontal padding.
	var font := get_theme_font("font")
	if font:
		var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x
		size = Vector2(round(tw + PAD * 2.0), 48)
	# The heartbeat swells the button about its own centre.
	pivot_offset = size * 0.5
	set_process(false)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)

# Only runs while the nudge is up (the setter arms/disarms it).
func _process(delta: float) -> void:
	_phase += delta
	scale = Vector2.ONE * (1.0 + glow * BEAT_SCALE * _beat())
	queue_redraw()

# Lub-dub: a strong beat, a softer echo a fifth of a second later, then rest.
func _beat() -> float:
	var p := fposmod(_phase, BEAT_PERIOD)
	return clampf(maxf(_thump(p / 0.17), 0.55 * _thump((p - 0.25) / 0.17)), 0.0, 1.0)

func _thump(x: float) -> float:
	if x <= 0.0 or x >= 1.0:
		return 0.0
	return sin(x * PI)

# Fill a horizontal stadium as ONE convex polygon — no overlapping primitives, so
# it composites correctly at low alpha. _fill_pill() below can't be used for the
# aura: its end-caps are full circles centred on the middle band's edges, so each
# cap double-blends its inner half over the band. Opaque fills hide that, but
# stacked translucent ones show it as two hard vertical seams with a brighter
# core — which is exactly why the old halo read as a band above and below the
# button instead of an aura around it.
const PILL_SEGS := 12   # per cap; plenty at this size

func _fill_pill_soft(pos: Vector2, sz: Vector2, col: Color) -> void:
	if sz.x <= 0.0 or sz.y <= 0.0:
		return
	var rad: float = min(sz.x, sz.y) * 0.5
	var cy := pos.y + sz.y * 0.5
	var rc := Vector2(pos.x + sz.x - rad, cy)
	var lc := Vector2(pos.x + rad, cy)
	var pts := PackedVector2Array()
	for i in PILL_SEGS + 1:                       # right cap, top → bottom
		var a := -PI * 0.5 + PI * float(i) / float(PILL_SEGS)
		pts.append(rc + Vector2(cos(a), sin(a)) * rad)
	for i in PILL_SEGS + 1:                       # left cap, bottom → top
		var a := PI * 0.5 + PI * float(i) / float(PILL_SEGS)
		pts.append(lc + Vector2(cos(a), sin(a)) * rad)
	draw_colored_polygon(pts, col)

# Fill a horizontal stadium (pill) covering rect(pos, sz): a middle band plus two
# rounded end-caps. Caps are antialiased for a clean silhouette. Opaque fills only
# (see _fill_pill_soft).
func _fill_pill(pos: Vector2, sz: Vector2, col: Color, aa := false) -> void:
	if sz.x <= 0 or sz.y <= 0:
		return
	var rad: float = min(sz.x, sz.y) * 0.5
	draw_rect(Rect2(pos.x + rad, pos.y, max(0.0, sz.x - 2.0 * rad), sz.y), col)
	draw_circle(Vector2(pos.x + rad, pos.y + rad), rad, col, true, -1.0, aa)
	draw_circle(Vector2(pos.x + sz.x - rad, pos.y + rad), rad, col, true, -1.0, aa)

# A leaning band of light travelling across the pill. Cut into horizontal bands so
# it can be clipped to the stadium silhouette — a plain skewed quad would overhang
# the rounded caps. Each band is one polygon whose vertex colours ramp
# transparent → bright → transparent, so the streak has soft edges for free.
func _draw_bolt(pos: Vector2, sz: Vector2) -> void:
	var p := fposmod(_phase, SWEEP_PERIOD) / SWEEP_PERIOD
	var a := glow * sin(p * PI) * 0.62            # fades in/out at both edges
	if a <= 0.002:
		return
	var slant := sz.y * SWEEP_SLANT
	var cx := pos.x - sz.y * 1.5 + p * (sz.x + sz.y * 3.0 + slant)
	# Two passes: a wide soft flare, then a narrow white-hot core inside it.
	_bolt_pass(pos, sz, cx, slant, sz.y * 0.80, a * 0.45)
	_bolt_pass(pos, sz, cx, slant, sz.y * 0.30, a)

func _bolt_pass(pos: Vector2, sz: Vector2, cx: float, slant: float,
		band: float, a: float) -> void:
	var rad: float = min(sz.x, sz.y) * 0.5
	var mid_y := pos.y + sz.y * 0.5
	var bh := sz.y / float(SWEEP_BANDS)
	var edge := Color(BOLT_COL.r, BOLT_COL.g, BOLT_COL.b, 0.0)
	var core := Color(BOLT_COL.r, BOLT_COL.g, BOLT_COL.b, a)
	for i in SWEEP_BANDS:
		var y0 := pos.y + float(i) * bh
		var y1 := y0 + bh
		# Take the NARROWEST width in the band so the streak can't poke out.
		var dy: float = maxf(absf(y0 - mid_y), absf(y1 - mid_y))
		var half: float = sqrt(maxf(rad * rad - dy * dy, 0.0))
		var x0 := pos.x + rad - half
		var x1 := pos.x + sz.x - rad + half
		# Lean: the band's centre slides with height, like a real specular sweep.
		var m := cx - ((y0 + y1) * 0.5 - mid_y) / sz.y * slant
		var l: float = maxf(m - band, x0)
		var r: float = minf(m + band, x1)
		if r - l <= 0.5:
			continue
		var c: float = clampf(m, l, r)
		draw_polygon(
			PackedVector2Array([
				Vector2(l, y0), Vector2(c, y0), Vector2(r, y0),
				Vector2(r, y1), Vector2(c, y1), Vector2(l, y1)]),
			PackedColorArray([edge, core, edge, edge, core, edge]))

func _draw() -> void:
	var mode := get_draw_mode()
	var pressed := mode == DRAW_PRESSED
	var hover := mode == DRAW_HOVER_PRESSED or mode == DRAW_HOVER

	var w := size.x
	var h := size.y
	var drop := 2.0 if pressed else 0.0          # whole button sinks when pressed
	var base_pos := Vector2(0, drop)
	var center := Vector2(w * 0.5, h * 0.5 + drop)

	var wall_h := 2.0 if pressed else 5.0        # exposed bottom edge = thickness
	var lit := 0.05 if hover else 0.0
	var dark := 0.90 if pressed else 1.0
	var dmul := Color(dark, dark, dark, 1)

	var face_top := (FACE_TOP.lightened(lit) * dmul).clamp()
	var face_bottom := (FACE_BOTTOM * dmul).clamp()

	# 0) Idle attention aura — concentric stadiums grown UNIFORMLY, so the halo wraps
	#    the ends as tightly as the top and bottom (a rectangular halo would leave the
	#    caps bare). Painted biggest-first so the alpha piles up toward the rim into a
	#    smooth falloff, and it swells on the heartbeat along with the body.
	if glow > 0.001:
		var beat := _beat()
		var reach := AURA_REACH * (0.80 + 0.42 * beat)
		var amp := glow * (0.72 + 0.50 * beat)
		for i in range(AURA_LAYERS):
			var t := 1.0 - float(i) / float(AURA_LAYERS - 1)   # 1 = outermost … 0 = rim
			var grow := 1.5 + t * reach
			var a := amp * 0.085 * pow(1.0 - t, 2.0)
			var col := GLOW_COL.lerp(GLOW_OUTER, t)
			_fill_pill_soft(base_pos - Vector2(grow, grow),
				Vector2(w + grow * 2.0, h + grow * 2.0),
				Color(col.r, col.g, col.b, a))
		# A hot lip right against the silhouette so the edge reads as lit, not fogged.
		for i in range(3):
			var g := 3.0 - float(i)
			_fill_pill_soft(base_pos - Vector2(g, g), Vector2(w + g * 2.0, h + g * 2.0),
				Color(GLOW_RIM.r, GLOW_RIM.g, GLOW_RIM.b, amp * 0.13))

	# 1) Soft contact shadow — shorter/tighter when pressed.
	var sh_dy := 3.0 if pressed else 7.0
	for i in range(7):
		var t := float(i) / 6.0
		var grow := t * (2.0 if pressed else 5.0)
		_fill_pill_soft(base_pos + Vector2(-grow, sh_dy - grow * 0.3),
			Vector2(w + grow * 2.0, h + grow * 2.0),
			Color(0, 0, 0, 0.05))

	# 2) Button body / side wall, offset down so its bottom crescent reads as the
	#    raised edge (real thickness under the face).
	_fill_pill(base_pos + Vector2(0, wall_h), Vector2(w, h),
		(WALL_COL * dmul).clamp(), true)

	# 3) Convex dome face. Inset stadiums from the shaded rim up to the lit crown;
	#    each layer drifts toward the top-left light, so the crown sits high-left and
	#    the surface darkens smoothly toward the bottom-right. No hard white shine —
	#    the gradient itself carries the volume.
	var layers := 44
	var flat := 0.7 if pressed else 1.0          # pressed dome is a touch flatter
	for i in range(layers):
		var t := float(i) / float(layers - 1)     # 0 = rim … 1 = crown
		var inset := t * (h * 0.5)
		var rp := base_pos + Vector2(inset * 0.5, inset) \
			+ Vector2(-h * 0.05, -h * 0.10) * t * flat
		var rs := Vector2(w - inset, h - inset * 2.0)
		var col := face_bottom.lerp(face_top, ease(t, 0.62))
		_fill_pill(rp, rs, col, false)

	# 4) Ambient plastic reflections — broad, low-alpha sheens (top band + a fainter
	#    lower bounce). Subtle and matte, not glossy glass.
	var refl := 0.05 if pressed else 0.075
	_fill_pill_soft(base_pos + Vector2(w * 0.10, h * 0.14),
		Vector2(w * 0.80, h * 0.30),
		Color(REFLECT_COL.r, REFLECT_COL.g, REFLECT_COL.b, refl))
	_fill_pill_soft(base_pos + Vector2(w * 0.22, h * 0.60),
		Vector2(w * 0.56, h * 0.20),
		Color(REFLECT_COL.r, REFLECT_COL.g, REFLECT_COL.b, refl * 0.5))

	# 4b) The bolt: a bright shine crossing the face side to side. Drawn over the
	#     plastic sheen but under the label, so the text stays crisp as it passes.
	if glow > 0.001:
		_draw_bolt(base_pos + Vector2(2.0, 2.0), Vector2(w - 4.0, h - 4.0))

	# 5) Bold white label — crisp, centred, with a soft drop shadow for readability
	#    and a second pass to thicken (bold) without a heavy font.
	var font := get_theme_font("font")
	if font:
		var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x
		var tx := center.x - tw * 0.5
		var ty := center.y + (font.get_ascent(FS) - font.get_descent(FS)) * 0.5
		var tcol := TEXT_COL.darkened(0.06) if pressed else TEXT_COL
		draw_string(font, Vector2(tx, ty + 1.4), text, HORIZONTAL_ALIGNMENT_LEFT,
			-1, FS, Color(0.12, 0.05, 0.0, 0.55))
		draw_string(font, Vector2(tx, ty), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FS, tcol)
		draw_string(font, Vector2(tx + 0.6, ty), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FS, tcol)
