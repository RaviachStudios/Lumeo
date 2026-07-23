extends RefCounted

# Shared procedural icon art (no PNGs — crisp at any DPI). Vector glyphs drawn as
# Node2D children, centered on their origin, sized by `s` (roughly the glyph's
# half-height). Used by the difficulty screen and the Arena's contest wizard so
# the same idea always wears the same shape: a leaf is Easy everywhere, a flame is
# Hard everywhere.
# Referenced via `preload("res://game_icons.gd")`, so it never depends on the
# editor's global-class scan.

static func make(kind: String, s: float, col: Color) -> Node2D:
	match kind:
		"chart":    return icon_chart(s, col)
		"flame":    return icon_fire(s)          # ignores `col` — fire is always fire
		"clock":    return icon_clock(s, col)
		"calendar": return icon_calendar(s, col)
		"trophy":   return icon_trophy(s, col)
		"globe":    return icon_globe(s, col)
		"lock":     return icon_lock(s * 0.62, col)
		_:          return icon_poly(leaf_poly(s), col, -35.0)

static func icon_poly(poly: PackedVector2Array, col: Color, rot_deg: float = 0.0) -> Node2D:
	var n := Node2D.new()
	var pg := Polygon2D.new()
	pg.polygon = poly
	pg.color = col
	pg.rotation_degrees = rot_deg
	n.add_child(pg)
	return n

static func leaf_poly(s: float) -> PackedVector2Array:
	# vertical almond/leaf (points top & bottom, bulging sides)
	var p := PackedVector2Array()
	var n := 16
	for i in n + 1:
		var t: float = float(i) / n
		p.append(Vector2(sin(t * PI) * s * 0.62, lerp(-s, s, t)))
	for i in n + 1:
		var t: float = float(i) / n
		p.append(Vector2(-sin(t * PI) * s * 0.62, lerp(s, -s, t)))
	return p

# Layered fire icon: three nested flame silhouettes (large outer red → orange
# middle → bright yellow core). Each silhouette is drawn from a unit polygon
# scaled by a factor, so the inner layers sit inside the outer one and produce
# the orange-to-yellow gradient you see in real fire.
static func icon_fire(s: float) -> Node2D:
	var n := Node2D.new()
	var outer := Polygon2D.new()
	outer.polygon = flame_silhouette(s, 1.00, 0.18)
	outer.color = Color(0.95, 0.30, 0.20)              # deep red base
	n.add_child(outer)
	var mid := Polygon2D.new()
	mid.polygon = flame_silhouette(s, 0.74, 0.30)
	mid.color = Color(1.00, 0.60, 0.18)                # orange middle
	mid.position = Vector2(0, s * 0.06)                # sits a touch lower
	n.add_child(mid)
	var core := Polygon2D.new()
	core.polygon = flame_silhouette(s, 0.46, 0.42)
	core.color = Color(1.00, 0.92, 0.40)               # hot yellow core
	core.position = Vector2(0, s * 0.18)
	n.add_child(core)
	return n

# Tall, lick-shaped flame silhouette pointing UP (canvas Y grows downward, so
# the tip uses a negative Y). `scale` shrinks the whole shape; `tip_lean` tilts
# the tip slightly to the side for a natural "flickering" feel — inner layers
# use a stronger lean so they don't perfectly mirror the outer outline.
static func flame_silhouette(s: float, scale: float, tip_lean: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	# 20-sample silhouette traced clockwise from the tip, back down to the base,
	# around the rounded bottom, and back up the left side. The numbers come from
	# tracing a stylized flame on a unit grid.
	var pts := [
		Vector2( tip_lean * 0.5, -1.45),   # main tip (slightly leaning)
		Vector2( 0.18, -1.20),
		Vector2( 0.30, -0.80),
		Vector2( 0.50, -0.50),
		Vector2( 0.62, -0.10),
		Vector2( 0.55,  0.25),
		Vector2( 0.78,  0.05),             # small upper-right lick
		Vector2( 0.85,  0.40),
		Vector2( 0.80,  0.75),             # base flare right
		Vector2( 0.55,  1.00),             # rounded base, right
		Vector2( 0.00,  1.05),             # base bottom
		Vector2(-0.55,  1.00),             # rounded base, left
		Vector2(-0.80,  0.75),             # base flare left
		Vector2(-0.85,  0.40),
		Vector2(-0.70,  0.05),             # small upper-left curl
		Vector2(-0.50,  0.20),
		Vector2(-0.55, -0.15),
		Vector2(-0.40, -0.55),
		Vector2(-0.25, -0.90),
		Vector2(-0.10, -1.15),
	]
	for v in pts:
		p.append(Vector2(v.x, v.y) * s * scale)
	return p

static func icon_chart(s: float, col: Color) -> Node2D:
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

# Minimal padlock: a rounded body rect + a semicircular shackle. `s` is roughly
# the body half-width. Centered on the node's origin.
static func icon_lock(s: float, col: Color) -> Node2D:
	var n := Node2D.new()
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(-s, 0), Vector2(s, 0),
		Vector2(s, s * 1.3), Vector2(-s, s * 1.3)])
	body.color = col
	n.add_child(body)
	var shackle := Line2D.new()
	shackle.width = maxf(2.0, s * 0.32)
	shackle.default_color = col
	var pts := PackedVector2Array()
	var r := s * 0.62
	for i in 13:
		var a: float = PI + float(i) / 12.0 * PI
		pts.append(Vector2(cos(a) * r, -s * 0.05 + sin(a) * r))
	shackle.points = pts
	n.add_child(shackle)
	return n

# ---- contest-format glyphs ----

# A trophy on a plinth — "one game, winner takes it".
static func icon_trophy(s: float, col: Color) -> Node2D:
	var n := Node2D.new()
	var cup := Polygon2D.new()
	cup.polygon = PackedVector2Array([
		Vector2(-0.62, -0.95), Vector2(0.62, -0.95),
		Vector2(0.52, -0.20), Vector2(0.20, 0.16), Vector2(-0.20, 0.16),
		Vector2(-0.52, -0.20)])
	_scale_poly(cup, s)
	cup.color = col
	n.add_child(cup)
	# handles: open arcs sweeping out of the cup's shoulders
	for side in [-1.0, 1.0]:
		var h := Line2D.new()
		h.width = maxf(2.0, s * 0.14)
		h.default_color = col
		h.begin_cap_mode = Line2D.LINE_CAP_ROUND
		h.end_cap_mode = Line2D.LINE_CAP_ROUND
		var pts := PackedVector2Array()
		for i in 9:
			var a: float = lerp(-1.3, 1.3, float(i) / 8.0)
			pts.append(Vector2(side * (0.62 + cos(a) * 0.34), -0.62 + sin(a) * 0.36) * s)
		h.points = pts
		n.add_child(h)
	var stem := Polygon2D.new()
	stem.polygon = PackedVector2Array([
		Vector2(-0.13, 0.16), Vector2(0.13, 0.16),
		Vector2(0.13, 0.62), Vector2(-0.13, 0.62)])
	_scale_poly(stem, s)
	stem.color = col
	n.add_child(stem)
	var base := Polygon2D.new()
	base.polygon = PackedVector2Array([
		Vector2(-0.55, 0.62), Vector2(0.55, 0.62),
		Vector2(0.62, 0.95), Vector2(-0.62, 0.95)])
	_scale_poly(base, s)
	base.color = col
	n.add_child(base)
	return n

# A clock face — hour + minute hands and a rim.
static func icon_clock(s: float, col: Color) -> Node2D:
	var n := Node2D.new()
	var rim := Line2D.new()
	rim.width = maxf(2.0, s * 0.16)
	rim.default_color = col
	rim.closed = true
	var pts := PackedVector2Array()
	for i in 28:
		var a: float = TAU * float(i) / 28.0
		pts.append(Vector2(cos(a), sin(a)) * s * 0.92)
	rim.points = pts
	n.add_child(rim)
	for hand: Vector2 in [Vector2(0.0, -0.60), Vector2(0.44, 0.16)]:
		var l := Line2D.new()
		l.width = maxf(2.0, s * 0.15)
		l.default_color = col
		l.begin_cap_mode = Line2D.LINE_CAP_ROUND
		l.end_cap_mode = Line2D.LINE_CAP_ROUND
		l.points = PackedVector2Array([Vector2.ZERO, hand * s])
		n.add_child(l)
	return n

# A day: a sun disc with rays (24h — "before the sun comes round again").
static func icon_calendar(s: float, col: Color) -> Node2D:
	var n := Node2D.new()
	var disc := Polygon2D.new()
	var dp := PackedVector2Array()
	for i in 20:
		var a: float = TAU * float(i) / 20.0
		dp.append(Vector2(cos(a), sin(a)) * s * 0.50)
	disc.polygon = dp
	disc.color = col
	n.add_child(disc)
	for i in 8:
		var a: float = TAU * float(i) / 8.0
		var ray := Line2D.new()
		ray.width = maxf(2.0, s * 0.15)
		ray.default_color = col
		ray.begin_cap_mode = Line2D.LINE_CAP_ROUND
		ray.end_cap_mode = Line2D.LINE_CAP_ROUND
		var dir := Vector2(cos(a), sin(a))
		ray.points = PackedVector2Array([dir * s * 0.68, dir * s * 0.98])
		n.add_child(ray)
	return n

# A globe — a disc crossed by a meridian + two latitudes ("anyone can find it").
static func icon_globe(s: float, col: Color) -> Node2D:
	var n := Node2D.new()
	var rim := Line2D.new()
	rim.width = maxf(2.0, s * 0.15)
	rim.default_color = col
	rim.closed = true
	var pts := PackedVector2Array()
	for i in 28:
		var a: float = TAU * float(i) / 28.0
		pts.append(Vector2(cos(a), sin(a)) * s * 0.92)
	rim.points = pts
	n.add_child(rim)
	# meridian: an ellipse squeezed on X so it reads as a sphere's edge-on circle
	var mer := Line2D.new()
	mer.width = maxf(2.0, s * 0.12)
	mer.default_color = col
	mer.closed = true
	var mp := PackedVector2Array()
	for i in 24:
		var a: float = TAU * float(i) / 24.0
		mp.append(Vector2(cos(a) * 0.42, sin(a)) * s * 0.92)
	mer.points = mp
	n.add_child(mer)
	for y: float in [-0.42, 0.42]:
		var lat := Line2D.new()
		lat.width = maxf(2.0, s * 0.12)
		lat.default_color = col
		var half := sqrt(maxf(0.0, 0.92 * 0.92 - y * y))
		lat.points = PackedVector2Array([Vector2(-half, y) * s, Vector2(half, y) * s])
		n.add_child(lat)
	return n

static func _scale_poly(pg: Polygon2D, s: float) -> void:
	var out := PackedVector2Array()
	for v: Vector2 in pg.polygon:
		out.append(v * s)
	pg.polygon = out
