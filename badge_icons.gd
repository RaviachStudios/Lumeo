extends RefCounted
class_name BadgeIcons

# Procedural badge art, drawn in code (house style — same approach as pack_icons.gd).
# One medallion frame for every badge (a beveled category-tinted medal) plus a
# per-badge emblem. Earned badges glow in full colour; locked badges are rendered
# as a dim slate silhouette with a small padlock, so the gallery reads at a glance.
#
# Call from a CanvasItem's _draw():
#   BadgeIcons.draw_badge(self, size, art, accent, earned, num)

const SLATE := Color(0.34, 0.37, 0.47)
const SLATE_INK := Color(0.60, 0.63, 0.73)

static func draw_badge(c: CanvasItem, size: Vector2, art: String, accent: Color, earned: bool, num: int = 0) -> void:
	var center := size * 0.5
	var R: float = min(size.x, size.y) * 0.5 - 2.0
	var acc := accent if earned else SLATE
	var ink := Color(0.98, 0.98, 1.0) if earned else SLATE_INK

	# Soft outer glow for earned badges (concentric fading rings).
	if earned:
		for i in 6:
			var t := float(i) / 5.0
			c.draw_circle(center, R * (0.96 + 0.16 * t), Color(acc.r, acc.g, acc.b, 0.05 * (1.0 - t)))

	# Beveled metal rim.
	c.draw_circle(center, R, Color(0.04, 0.05, 0.10, 1.0))
	c.draw_circle(center, R * 0.965, acc.darkened(0.42))
	c.draw_circle(center, R * 0.90, acc.lightened(0.18) if earned else acc.lightened(0.05))
	# Coin-edge notches around the rim.
	var notch_col := acc.darkened(0.55)
	for k in 44:
		var a := TAU * float(k) / 44.0
		var d := Vector2(cos(a), sin(a))
		c.draw_line(center + d * (R * 0.905), center + d * (R * 0.965), notch_col, 1.5)

	# Inner disc (dark, faintly accent-tinted) + top sheen.
	var disc := Color(0.09, 0.10, 0.16).lerp(acc, 0.14)
	c.draw_circle(center, R * 0.82, disc.darkened(0.10))
	c.draw_circle(center, R * 0.82, disc)
	c.draw_circle(center + Vector2(0, -R * 0.34), R * 0.52, Color(1, 1, 1, 0.06 if earned else 0.03))

	# Emblem.
	var er: float = R * 0.52
	_emblem(c, art, center, er, ink, acc, earned, num)

	# Locked: mute the (often intrinsically-coloured) emblem toward a silhouette,
	# then stamp a padlock chip lower-right.
	if not earned:
		c.draw_circle(center, R * 0.82, Color(0.10, 0.11, 0.17, 0.62))
		_lock(c, center + Vector2(R * 0.52, R * 0.52), R * 0.26)

# ─── emblem dispatch ─────────────────────────────────────────────────────────

static func _emblem(c: CanvasItem, art: String, ce: Vector2, r: float, ink: Color, acc: Color, earned: bool, num: int) -> void:
	match art:
		"num":         _num(c, ce, r, ink, acc, num)
		"star":        _fill_star(c, ce, r, ink, 5)
		"sprout":      _sprout(c, ce, r, ink)
		"handshake":   _handshake(c, ce, r, ink)
		"tag":         _tag(c, ce, r, ink, acc)
		"book":        _book(c, ce, r, ink)
		"coin":        _coin(c, ce, r, ink, acc)
		"coins":       _coins(c, ce, r, ink, acc)
		"chest":       _chest(c, ce, r, ink, acc)
		"brain":       _brain(c, ce, r, ink)
		"leaf":        _leaf(c, ce, r, ink)
		"spark":       _fill_star(c, ce, r, ink, 4)
		"bolt":        _bolt(c, ce, r, ink)
		"triangle":    _triangle(c, ce, r, ink)
		"chart":       _chart(c, ce, r, ink, acc)
		"medal":       _medal(c, ce, r, ink, acc)
		"trophy":      _trophy(c, ce, r, ink)
		"crown":       _crown(c, ce, r, ink)
		"sun":         _sun(c, ce, r, ink)
		"moon":        _moon(c, ce, r, ink)
		"sword":       _sword(c, ce, r, ink)
		"swords":      _swords(c, ce, r, ink)
		"flag":        _flag(c, ce, r, ink, acc)
		"palette":     _palette(c, ce, r, ink)
		"gem":         _gem(c, ce, r, ink, acc)
		"diamond":     _gem(c, ce, r, ink, acc)
		"wheel":       _wheel(c, ce, r, ink, acc)
		"key":         _key(c, ce, r, ink)
		"shield":      _shield(c, ce, r, ink, acc)
		"gift":        _gift(c, ce, r, ink, acc)
		"calendar":    _calendar(c, ce, r, ink, acc)
		"flame":       _flame(c, ce, r, acc)
		"controller":  _controller(c, ce, r, ink)
		"rocket":      _rocket(c, ce, r, ink, acc)
		_:             _fill_star(c, ce, r, ink, 5)

# ─── primitives ──────────────────────────────────────────────────────────────

static func _poly(c: CanvasItem, pts: PackedVector2Array, col: Color) -> void:
	c.draw_colored_polygon(pts, col)

static func _star_pts(ce: Vector2, ro: float, ri: float, points: int, rot: float = -PI / 2.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in points * 2:
		var rr: float = ro if i % 2 == 0 else ri
		var a: float = rot + PI * float(i) / float(points)
		pts.append(ce + Vector2(cos(a), sin(a)) * rr)
	return pts

static func _fill_star(c: CanvasItem, ce: Vector2, r: float, ink: Color, points: int) -> void:
	_poly(c, _star_pts(ce, r, r * 0.44, points), ink)
	c.draw_circle(ce, r * 0.16, ink.lightened(0.3))

static func _num(c: CanvasItem, ce: Vector2, r: float, ink: Color, acc: Color, num: int) -> void:
	# Target ring with the milestone number inside.
	c.draw_arc(ce, r, 0, TAU, 40, acc.lightened(0.2), r * 0.16)
	c.draw_arc(ce, r * 0.66, 0, TAU, 32, ink, r * 0.10)
	var f := ThemeDB.fallback_font
	var fs := int(r * (1.15 if num < 10 else (0.9 if num < 100 else 0.72)))
	var s := str(num)
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
	c.draw_string(f, ce - Vector2(w.x * 0.5, -w.y * 0.32), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)

static func _coin(c: CanvasItem, ce: Vector2, r: float, ink: Color, acc: Color) -> void:
	c.draw_circle(ce, r, Color(0.95, 0.78, 0.20))
	c.draw_circle(ce, r * 0.78, Color(1.0, 0.87, 0.34))
	var f := ThemeDB.fallback_font
	var fs := int(r * 1.2)
	var w := f.get_string_size("$", HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
	c.draw_string(f, ce - Vector2(w.x * 0.5, -w.y * 0.32), "$", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.55, 0.40, 0.05))

static func _coins(c: CanvasItem, ce: Vector2, r: float, ink: Color, acc: Color) -> void:
	_coin(c, ce + Vector2(-r * 0.42, r * 0.35), r * 0.62, ink, acc)
	_coin(c, ce + Vector2(r * 0.42, r * 0.35), r * 0.62, ink, acc)
	_coin(c, ce + Vector2(0, -r * 0.25), r * 0.72, ink, acc)

static func _chest(c: CanvasItem, ce: Vector2, r: float, ink: Color, acc: Color) -> void:
	var w := r * 1.5
	var h := r * 1.05
	# lid
	c.draw_colored_polygon(PackedVector2Array([
		ce + Vector2(-w * 0.5, -h * 0.15), ce + Vector2(w * 0.5, -h * 0.15),
		ce + Vector2(w * 0.42, -h * 0.55), ce + Vector2(-w * 0.42, -h * 0.55)]),
		Color(0.55, 0.34, 0.16))
	# body
	c.draw_rect(Rect2(ce + Vector2(-w * 0.5, -h * 0.15), Vector2(w, h * 0.7)), Color(0.42, 0.26, 0.12))
	c.draw_rect(Rect2(ce + Vector2(-w * 0.5, -h * 0.02), Vector2(w, h * 0.14)), Color(0.95, 0.78, 0.20))
	c.draw_circle(ce + Vector2(0, h * 0.08), r * 0.16, Color(0.98, 0.86, 0.32))

static func _sprout(c: CanvasItem, ce: Vector2, r: float, ink: Color) -> void:
	var soil := ce + Vector2(0, r * 0.7)
	c.draw_line(soil, ce + Vector2(0, -r * 0.2), Color(0.45, 0.75, 0.35), r * 0.14)
	_poly(c, PackedVector2Array([ce + Vector2(0, -r * 0.05),
		ce + Vector2(-r * 0.7, -r * 0.35), ce + Vector2(-r * 0.05, -r * 0.6)]), Color(0.40, 0.80, 0.40))
	_poly(c, PackedVector2Array([ce + Vector2(0, -r * 0.05),
		ce + Vector2(r * 0.7, -r * 0.35), ce + Vector2(r * 0.05, -r * 0.6)]), Color(0.50, 0.86, 0.46))
	c.draw_arc(soil, r * 0.75, 0.15 * PI, 0.85 * PI, 20, Color(0.45, 0.30, 0.18), r * 0.12)

static func _leaf(c: CanvasItem, ce: Vector2, r: float, ink: Color) -> void:
	_poly(c, PackedVector2Array([ce + Vector2(0, -r), ce + Vector2(r * 0.7, 0),
		ce + Vector2(0, r), ce + Vector2(-r * 0.7, 0)]), Color(0.40, 0.82, 0.42))
	c.draw_line(ce + Vector2(0, -r * 0.8), ce + Vector2(0, r * 0.8), Color(0.20, 0.55, 0.25), r * 0.1)

static func _handshake(c: CanvasItem, ce: Vector2, r: float, ink: Color) -> void:
	c.draw_line(ce + Vector2(-r, -r * 0.2), ce + Vector2(0, r * 0.1), ink, r * 0.32)
	c.draw_line(ce + Vector2(r, -r * 0.2), ce + Vector2(0, r * 0.1), ink.darkened(0.15), r * 0.32)
	c.draw_circle(ce + Vector2(0, r * 0.05), r * 0.26, ink.lightened(0.2))

static func _tag(c: CanvasItem, ce: Vector2, r: float, ink: Color, acc: Color) -> void:
	_poly(c, PackedVector2Array([ce + Vector2(-r * 0.2, -r), ce + Vector2(r, -r * 0.2),
		ce + Vector2(-r * 0.2, r), ce + Vector2(-r, r * 0.2), ce + Vector2(-r, -r * 0.2)]), acc.lightened(0.25))
	c.draw_circle(ce + Vector2(-r * 0.45, 0), r * 0.16, Color(0.06, 0.07, 0.12))

static func _book(c: CanvasItem, ce: Vector2, r: float, ink: Color) -> void:
	c.draw_rect(Rect2(ce + Vector2(-r * 0.9, -r * 0.7), Vector2(r * 1.8, r * 1.4)), ink)
	c.draw_line(ce + Vector2(0, -r * 0.7), ce + Vector2(0, r * 0.7), Color(0.06, 0.07, 0.12), r * 0.1)
	for i in 3:
		var y := -r * 0.35 + i * r * 0.35
		c.draw_line(ce + Vector2(-r * 0.7, y), ce + Vector2(-r * 0.15, y), Color(0.4, 0.45, 0.6), r * 0.06)
		c.draw_line(ce + Vector2(r * 0.15, y), ce + Vector2(r * 0.7, y), Color(0.4, 0.45, 0.6), r * 0.06)

static func _brain(c: CanvasItem, ce: Vector2, r: float, ink: Color) -> void:
	c.draw_circle(ce + Vector2(-r * 0.35, 0), r * 0.6, ink)
	c.draw_circle(ce + Vector2(r * 0.35, 0), r * 0.6, ink)
	c.draw_circle(ce + Vector2(0, -r * 0.3), r * 0.5, ink)
	c.draw_line(ce + Vector2(0, -r * 0.7), ce + Vector2(0, r * 0.5), Color(0.06, 0.07, 0.12), r * 0.08)
	c.draw_arc(ce + Vector2(-r * 0.35, 0), r * 0.3, 0, PI, 12, Color(0.06, 0.07, 0.12), r * 0.06)

static func _bolt(c: CanvasItem, ce: Vector2, r: float, ink: Color) -> void:
	_poly(c, PackedVector2Array([ce + Vector2(r * 0.15, -r), ce + Vector2(-r * 0.5, r * 0.15),
		ce + Vector2(0, r * 0.15), ce + Vector2(-r * 0.15, r), ce + Vector2(r * 0.5, -r * 0.15),
		ce + Vector2(0, -r * 0.15)]), Color(1.0, 0.86, 0.28))

static func _triangle(c: CanvasItem, ce: Vector2, r: float, ink: Color) -> void:
	var p0 := ce + Vector2(0, -r)
	var p1 := ce + Vector2(r * 0.87, r * 0.55)
	var p2 := ce + Vector2(-r * 0.87, r * 0.55)
	c.draw_colored_polygon(PackedVector2Array([p0, p1, p2]), Color(ink.r, ink.g, ink.b, 0.22))
	c.draw_polyline(PackedVector2Array([p0, p1, p2, p0]), ink, r * 0.17)
	for p: Vector2 in [p0, p1, p2]:
		c.draw_circle(p, r * 0.12, ink.lightened(0.2))

static func _chart(c: CanvasItem, ce: Vector2, r: float, ink: Color, acc: Color) -> void:
	var base := ce + Vector2(0, r * 0.7)
	var hs := [0.5, 0.85, 1.2, 1.55]
	for i in 4:
		var x := -r * 0.75 + i * r * 0.5
		var h: float = r * float(hs[i])
		c.draw_rect(Rect2(Vector2(base.x + x - r * 0.16, base.y - h), Vector2(r * 0.32, h)),
			acc.lightened(0.1) if i == 3 else ink)

static func _medal(c: CanvasItem, ce: Vector2, r: float, ink: Color, acc: Color) -> void:
	c.draw_colored_polygon(PackedVector2Array([ce + Vector2(-r * 0.4, -r), ce + Vector2(-r * 0.1, -r * 0.1),
		ce + Vector2(-r * 0.55, -r * 0.1)]), Color(0.85, 0.25, 0.30))
	c.draw_colored_polygon(PackedVector2Array([ce + Vector2(r * 0.4, -r), ce + Vector2(r * 0.1, -r * 0.1),
		ce + Vector2(r * 0.55, -r * 0.1)]), Color(0.30, 0.45, 0.90))
	c.draw_circle(ce + Vector2(0, r * 0.3), r * 0.62, acc.darkened(0.2))
	c.draw_circle(ce + Vector2(0, r * 0.3), r * 0.44, acc.lightened(0.25))
	_fill_star(c, ce + Vector2(0, r * 0.3), r * 0.3, Color(0.06, 0.07, 0.12), 5)

static func _trophy(c: CanvasItem, ce: Vector2, r: float, ink: Color) -> void:
	var gold := Color(1.0, 0.82, 0.28)
	c.draw_arc(ce + Vector2(0, -r * 0.15), r * 0.7, 0.05 * PI, 0.95 * PI, 20, gold, r * 0.16)
	c.draw_colored_polygon(PackedVector2Array([ce + Vector2(-r * 0.6, -r * 0.75), ce + Vector2(r * 0.6, -r * 0.75),
		ce + Vector2(r * 0.42, r * 0.05), ce + Vector2(-r * 0.42, r * 0.05)]), gold)
	c.draw_rect(Rect2(ce + Vector2(-r * 0.12, r * 0.05), Vector2(r * 0.24, r * 0.4)), gold.darkened(0.15))
	c.draw_rect(Rect2(ce + Vector2(-r * 0.5, r * 0.45), Vector2(r, r * 0.22)), gold.darkened(0.25))

static func _crown(c: CanvasItem, ce: Vector2, r: float, ink: Color) -> void:
	var gold := Color(1.0, 0.82, 0.28)
	c.draw_colored_polygon(PackedVector2Array([
		ce + Vector2(-r, r * 0.5), ce + Vector2(-r, -r * 0.5), ce + Vector2(-r * 0.5, r * 0.05),
		ce + Vector2(0, -r * 0.7), ce + Vector2(r * 0.5, r * 0.05), ce + Vector2(r, -r * 0.5),
		ce + Vector2(r, r * 0.5)]), gold)
	c.draw_rect(Rect2(ce + Vector2(-r, r * 0.5), Vector2(r * 2, r * 0.3)), gold.darkened(0.2))
	for dx in [-0.6, 0.0, 0.6]:
		c.draw_circle(ce + Vector2(r * dx, -r * 0.55), r * 0.13, Color(0.95, 0.35, 0.45))

static func _sun(c: CanvasItem, ce: Vector2, r: float, ink: Color) -> void:
	var gold := Color(1.0, 0.84, 0.32)
	for k in 8:
		var a := TAU * float(k) / 8.0
		var d := Vector2(cos(a), sin(a))
		c.draw_line(ce + d * r * 0.6, ce + d * r, gold, r * 0.14)
	c.draw_circle(ce, r * 0.55, gold)

static func _moon(c: CanvasItem, ce: Vector2, r: float, ink: Color) -> void:
	c.draw_circle(ce, r * 0.9, Color(0.92, 0.93, 0.78))
	c.draw_circle(ce + Vector2(r * 0.4, -r * 0.25), r * 0.8, Color(0.09, 0.10, 0.16).lerp(Color(0.2, 0.2, 0.3), 0.5))

static func _sword(c: CanvasItem, ce: Vector2, r: float, ink: Color) -> void:
	c.draw_line(ce + Vector2(r * 0.7, -r * 0.9), ce + Vector2(-r * 0.5, r * 0.6), Color(0.8, 0.84, 0.92), r * 0.18)
	c.draw_line(ce + Vector2(-r * 0.35, r * 0.25), ce + Vector2(-r * 0.75, r * 0.65), Color(0.55, 0.40, 0.2), r * 0.2)
	c.draw_line(ce + Vector2(-r * 0.7, r * 0.2), ce + Vector2(-r * 0.2, r * 0.7), Color(0.9, 0.75, 0.3), r * 0.14)

static func _swords(c: CanvasItem, ce: Vector2, r: float, ink: Color) -> void:
	c.draw_line(ce + Vector2(-r * 0.8, -r * 0.8), ce + Vector2(r * 0.7, r * 0.7), Color(0.8, 0.84, 0.92), r * 0.16)
	c.draw_line(ce + Vector2(r * 0.8, -r * 0.8), ce + Vector2(-r * 0.7, r * 0.7), Color(0.75, 0.79, 0.88), r * 0.16)

static func _flag(c: CanvasItem, ce: Vector2, r: float, ink: Color, acc: Color) -> void:
	c.draw_line(ce + Vector2(-r * 0.55, -r), ce + Vector2(-r * 0.55, r), ink, r * 0.14)
	c.draw_colored_polygon(PackedVector2Array([ce + Vector2(-r * 0.5, -r * 0.9), ce + Vector2(r * 0.8, -r * 0.55),
		ce + Vector2(-r * 0.5, -r * 0.2)]), acc.lightened(0.15))

static func _palette(c: CanvasItem, ce: Vector2, r: float, ink: Color) -> void:
	c.draw_circle(ce, r, Color(0.85, 0.80, 0.70))
	c.draw_circle(ce + Vector2(r * 0.45, r * 0.3), r * 0.3, Color(0.09, 0.10, 0.16))
	var cols := [Color(0.9, 0.3, 0.3), Color(0.3, 0.7, 0.4), Color(0.3, 0.5, 0.9), Color(0.95, 0.8, 0.3)]
	var angs := [-2.4, -1.6, -0.8, 0.0]
	for i in 4:
		var a: float = angs[i]
		c.draw_circle(ce + Vector2(cos(a), sin(a)) * r * 0.55, r * 0.17, cols[i])

static func _gem(c: CanvasItem, ce: Vector2, r: float, ink: Color, acc: Color) -> void:
	var top := -r * 0.4
	c.draw_colored_polygon(PackedVector2Array([ce + Vector2(-r * 0.7, top), ce + Vector2(r * 0.7, top),
		ce + Vector2(0, r * 0.95)]), acc.lightened(0.25))
	c.draw_colored_polygon(PackedVector2Array([ce + Vector2(-r * 0.7, top), ce + Vector2(-r * 0.25, top),
		ce + Vector2(0, r * 0.95)]), acc.lightened(0.45))
	c.draw_colored_polygon(PackedVector2Array([ce + Vector2(-r * 0.7, top), ce + Vector2(r * 0.7, top),
		ce + Vector2(r * 0.42, -r * 0.75), ce + Vector2(-r * 0.42, -r * 0.75)]), acc.lightened(0.1))

static func _wheel(c: CanvasItem, ce: Vector2, r: float, ink: Color, acc: Color) -> void:
	var segs := [Color(0.85, 0.2, 0.2), Color(0.2, 0.65, 0.3), Color(0.2, 0.35, 0.85), Color(0.95, 0.75, 0.2), Color(0.9, 0.45, 0.15)]
	for i in 5:
		var a0 := TAU * float(i) / 5.0 - PI / 2
		var a1 := TAU * float(i + 1) / 5.0 - PI / 2
		var pts := PackedVector2Array([ce])
		var steps := 6
		for s in steps + 1:
			var a: float = lerp(a0, a1, float(s) / float(steps))
			pts.append(ce + Vector2(cos(a), sin(a)) * r)
		c.draw_colored_polygon(pts, segs[i])
	c.draw_circle(ce, r * 0.32, Color(0.10, 0.10, 0.14))
	c.draw_circle(ce, r * 0.22, ink)

static func _key(c: CanvasItem, ce: Vector2, r: float, ink: Color) -> void:
	var gold := Color(1.0, 0.82, 0.30)
	c.draw_arc(ce + Vector2(-r * 0.4, -r * 0.4), r * 0.4, 0, TAU, 20, gold, r * 0.16)
	c.draw_line(ce + Vector2(-r * 0.2, -r * 0.2), ce + Vector2(r * 0.6, r * 0.6), gold, r * 0.16)
	c.draw_line(ce + Vector2(r * 0.6, r * 0.6), ce + Vector2(r * 0.85, r * 0.35), gold, r * 0.14)
	c.draw_line(ce + Vector2(r * 0.4, r * 0.4), ce + Vector2(r * 0.6, r * 0.2), gold, r * 0.14)

static func _shield(c: CanvasItem, ce: Vector2, r: float, ink: Color, acc: Color) -> void:
	c.draw_colored_polygon(PackedVector2Array([ce + Vector2(0, -r), ce + Vector2(r * 0.85, -r * 0.6),
		ce + Vector2(r * 0.7, r * 0.4), ce + Vector2(0, r), ce + Vector2(-r * 0.7, r * 0.4),
		ce + Vector2(-r * 0.85, -r * 0.6)]), acc.lightened(0.1))
	c.draw_colored_polygon(PackedVector2Array([ce + Vector2(-r * 0.15, -r * 0.1), ce + Vector2(r * 0.05, -r * 0.1),
		ce + Vector2(r * 0.05, r * 0.1), ce + Vector2(r * 0.35, r * 0.1), ce + Vector2(0, r * 0.5),
		ce + Vector2(-r * 0.35, 0)]), Color(0.98, 0.98, 1.0))

static func _gift(c: CanvasItem, ce: Vector2, r: float, ink: Color, acc: Color) -> void:
	c.draw_rect(Rect2(ce + Vector2(-r * 0.8, -r * 0.2), Vector2(r * 1.6, r * 1.0)), acc.lightened(0.1))
	c.draw_rect(Rect2(ce + Vector2(-r * 0.85, -r * 0.55), Vector2(r * 1.7, r * 0.4)), acc.lightened(0.25))
	c.draw_rect(Rect2(ce + Vector2(-r * 0.12, -r * 0.55), Vector2(r * 0.24, r * 1.35)), Color(0.98, 0.85, 0.35))
	c.draw_circle(ce + Vector2(-r * 0.28, -r * 0.6), r * 0.22, Color(0.98, 0.85, 0.35))
	c.draw_circle(ce + Vector2(r * 0.28, -r * 0.6), r * 0.22, Color(0.98, 0.85, 0.35))

static func _calendar(c: CanvasItem, ce: Vector2, r: float, ink: Color, acc: Color) -> void:
	c.draw_rect(Rect2(ce + Vector2(-r * 0.85, -r * 0.7), Vector2(r * 1.7, r * 1.5)), Color(0.95, 0.96, 1.0))
	c.draw_rect(Rect2(ce + Vector2(-r * 0.85, -r * 0.7), Vector2(r * 1.7, r * 0.45)), acc.darkened(0.1))
	for gy in 2:
		for gx in 3:
			c.draw_rect(Rect2(ce + Vector2(-r * 0.6 + gx * r * 0.5, -r * 0.05 + gy * r * 0.4),
				Vector2(r * 0.3, r * 0.25)), acc.lerp(Color(0.6, 0.6, 0.7), 0.5))

static func _flame(c: CanvasItem, ce: Vector2, r: float, acc: Color) -> void:
	c.draw_colored_polygon(PackedVector2Array([ce + Vector2(0, -r), ce + Vector2(r * 0.7, r * 0.2),
		ce + Vector2(r * 0.4, r * 0.8), ce + Vector2(-r * 0.4, r * 0.8), ce + Vector2(-r * 0.7, r * 0.2)]),
		Color(1.0, 0.45, 0.12))
	c.draw_colored_polygon(PackedVector2Array([ce + Vector2(0, -r * 0.35), ce + Vector2(r * 0.4, r * 0.35),
		ce + Vector2(0, r * 0.7), ce + Vector2(-r * 0.4, r * 0.35)]), Color(1.0, 0.82, 0.28))

static func _controller(c: CanvasItem, ce: Vector2, r: float, ink: Color) -> void:
	c.draw_rect(Rect2(ce + Vector2(-r * 0.9, -r * 0.35), Vector2(r * 1.8, r * 0.75)), ink)
	c.draw_circle(ce + Vector2(-r, 0), r * 0.38, ink)
	c.draw_circle(ce + Vector2(r, 0), r * 0.38, ink)
	c.draw_line(ce + Vector2(-r * 0.6, -r * 0.05), ce + Vector2(-r * 0.2, -r * 0.05), Color(0.09, 0.10, 0.16), r * 0.1)
	c.draw_line(ce + Vector2(-r * 0.4, -r * 0.25), ce + Vector2(-r * 0.4, r * 0.15), Color(0.09, 0.10, 0.16), r * 0.1)
	c.draw_circle(ce + Vector2(r * 0.4, -r * 0.1), r * 0.1, Color(0.9, 0.35, 0.4))
	c.draw_circle(ce + Vector2(r * 0.6, r * 0.1), r * 0.1, Color(0.4, 0.7, 0.95))

static func _rocket(c: CanvasItem, ce: Vector2, r: float, ink: Color, acc: Color) -> void:
	c.draw_colored_polygon(PackedVector2Array([ce + Vector2(0, -r), ce + Vector2(r * 0.42, -r * 0.1),
		ce + Vector2(r * 0.42, r * 0.55), ce + Vector2(-r * 0.42, r * 0.55), ce + Vector2(-r * 0.42, -r * 0.1)]),
		Color(0.95, 0.96, 1.0))
	c.draw_circle(ce + Vector2(0, -r * 0.2), r * 0.2, acc.lightened(0.1))
	c.draw_colored_polygon(PackedVector2Array([ce + Vector2(-r * 0.42, r * 0.1), ce + Vector2(-r * 0.8, r * 0.55),
		ce + Vector2(-r * 0.42, r * 0.55)]), Color(0.9, 0.35, 0.3))
	c.draw_colored_polygon(PackedVector2Array([ce + Vector2(r * 0.42, r * 0.1), ce + Vector2(r * 0.8, r * 0.55),
		ce + Vector2(r * 0.42, r * 0.55)]), Color(0.9, 0.35, 0.3))
	c.draw_colored_polygon(PackedVector2Array([ce + Vector2(-r * 0.22, r * 0.55), ce + Vector2(r * 0.22, r * 0.55),
		ce + Vector2(0, r)]), Color(1.0, 0.7, 0.2))

static func _lock(c: CanvasItem, ce: Vector2, r: float) -> void:
	c.draw_circle(ce, r * 1.15, Color(0.05, 0.06, 0.11))
	c.draw_circle(ce, r * 0.92, Color(0.24, 0.27, 0.36))
	c.draw_arc(ce + Vector2(0, -r * 0.15), r * 0.4, PI, TAU, 12, Color(0.75, 0.78, 0.86), r * 0.16)
	c.draw_rect(Rect2(ce + Vector2(-r * 0.45, -r * 0.15), Vector2(r * 0.9, r * 0.7)), Color(0.80, 0.83, 0.90))
