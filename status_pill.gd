extends Control
class_name StatusPill

# The "Your turn!" / "Watch carefully..." readout on the play screen.
#
# It used to be a Panel with a flat StyleBoxFlat on it — one colour, a hairline
# border and a soft shadow — which is the only control on this screen that was not
# drawn. Against a live 3D board carrying a bespoke skin it read as a debug label
# someone had left on, and it is the one piece of HUD the player looks at every
# single round.
#
# So it is drawn, in the same language as the LEVEL badge (level_tab.gd) it sits
# diagonally opposite: an outer bloom, a cast shadow, a vertical body gradient, a
# glass gloss over the top third, a rim that is bright along the top and dark along
# the bottom, and a 1 px inset catchlight. Nothing here is a texture — it has to sit
# on top of whatever the equipped skin is rendering, so it carries its own depth.
#
# The PALETTE IS THE BADGE'S, deliberately and to the value. Two dark-glass readouts
# in opposite corners of the same frame that are nearly the same blue read as a
# mistake; the same blue reads as a set.

const BODY_TOP := Color(0.075, 0.098, 0.220, 0.94)
const BODY_BOT := Color(0.021, 0.031, 0.086, 0.94)
const GLOSS := Color(0.62, 0.74, 1.0)
const RIM_TOP := Color(0.52, 0.64, 1.0, 0.95)
const RIM_BOT := Color(0.13, 0.18, 0.40, 0.75)
const INNER_TOP := Color(0.72, 0.82, 1.0, 0.22)
const BLOOM := Color(0.30, 0.45, 1.0)
const SHADOW := Color(0.0, 0.005, 0.03, 0.34)

# How far the outer halo reaches, and how many rings it is made of. Three is where
# a halo stops banding and has not yet become a cost.
const BLOOM_REACH := 9.0
const BLOOM_RINGS := 3
const SHADOW_DROP := 4.0

# A slow breath on the bloom, so the pill is alive without ever being a thing that
# moves — this sits under the board and must never pull the eye off it. Half the
# badge's rate: two readouts pulsing at the same frequency beat against each other.
const BREATH_HZ := 0.16
const BREATH_DEPTH := 0.22

var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _process(dt: float) -> void:
	if not visible:
		return
	_t += dt
	queue_redraw()


# A rounded-rect outline as a polygon. `grow` inflates it, which is what the bloom
# rings and the inset catchlight are made of.
func _rr(r: Rect2, rad: float, grow: float = 0.0) -> PackedVector2Array:
	var b := r.grow(grow)
	var k: float = minf(rad + grow, minf(b.size.x, b.size.y) * 0.5)
	var out := PackedVector2Array()
	var seg := 6
	var corners := [
		[Vector2(b.end.x - k, b.position.y + k), -PI * 0.5],
		[Vector2(b.end.x - k, b.end.y - k), 0.0],
		[Vector2(b.position.x + k, b.end.y - k), PI * 0.5],
		[Vector2(b.position.x + k, b.position.y + k), PI],
	]
	for c: Array in corners:
		var o: Vector2 = c[0]
		var a0: float = c[1]
		for i in range(seg + 1):
			var a := a0 + PI * 0.5 * float(i) / float(seg)
			out.append(o + Vector2(cos(a), sin(a)) * k)
	return out


# Per-vertex colours for a vertical gradient across a polygon.
func _grad(poly: PackedVector2Array, y0: float, y1: float,
		top: Color, bot: Color) -> PackedColorArray:
	var cols := PackedColorArray()
	for p: Vector2 in poly:
		cols.append(top.lerp(bot, clampf((p.y - y0) / maxf(y1 - y0, 0.001), 0.0, 1.0)))
	return cols


func _draw() -> void:
	if size.x < 8.0 or size.y < 8.0:
		return
	var body := Rect2(Vector2.ZERO, size)
	var rad := size.y * 0.5
	var breath := 0.5 + 0.5 * sin(_t * TAU * BREATH_HZ)

	# --- the outer bloom. Rings rather than a blur: this is a Control on a canvas
	#     over a 3D viewport, and a real blur here would cost a second pass.
	for i in BLOOM_RINGS:
		var u := float(i + 1) / float(BLOOM_RINGS)
		var ring := _rr(body, rad, BLOOM_REACH * u)
		ring.append(ring[0])
		var a: float = 0.052 * (1.0 - u) * (1.0 - BREATH_DEPTH + BREATH_DEPTH * breath)
		draw_polyline(ring, Color(BLOOM.r, BLOOM.g, BLOOM.b, a), 2.0, true)

	# --- the cast shadow, straight down. It is what lifts the pill off the board
	#     rather than printing it onto the ice.
	var sh := _rr(Rect2(body.position + Vector2(0.0, SHADOW_DROP), body.size), rad)
	draw_colored_polygon(sh, SHADOW)

	# --- the body.
	var poly := _rr(body, rad)
	draw_polygon(poly, _grad(poly, 0.0, size.y, BODY_TOP, BODY_BOT))

	# --- the gloss: the top third of the glass, brightest at its own top edge and
	#     gone by the middle. Clipped to the body so it keeps the rounded ends.
	var gl := Geometry2D.intersect_polygons(poly,
		PackedVector2Array([
			Vector2(-1.0, 0.0), Vector2(size.x + 1.0, 0.0),
			Vector2(size.x + 1.0, size.y * 0.46), Vector2(-1.0, size.y * 0.46)]))
	for g: PackedVector2Array in gl:
		draw_polygon(g, _grad(g, 0.0, size.y * 0.46,
			Color(GLOSS.r, GLOSS.g, GLOSS.b, 0.085),
			Color(GLOSS.r, GLOSS.g, GLOSS.b, 0.0)))

	# --- the rim: bright along the top, dark along the bottom. That one asymmetry
	#     is what makes a flat shape read as a lit solid.
	var rim := _rr(body, rad, -0.5)
	rim.append(rim[0])
	draw_polyline_colors(rim, _grad(rim, 0.0, size.y, RIM_TOP, RIM_BOT), 1.4, true)

	# --- and a 1 px inset catchlight just under the top rim.
	var inner := _rr(body, rad, -2.0)
	inner.append(inner[0])
	draw_polyline_colors(inner,
		_grad(inner, 0.0, size.y * 0.55, INNER_TOP,
			Color(INNER_TOP.r, INNER_TOP.g, INNER_TOP.b, 0.0)), 1.0, true)
