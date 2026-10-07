extends RefCounted

# Procedural classroom art for Class Games: a wood-framed chalkboard (with chalk
# dust, a chalk tray and a few chalk doodles of the six Simon colours) and a shiny
# red apple. Shared by the class screen and the teacher's CREATE CLASS GAME button on
# home. Everything is drawn with CanvasItem primitives — no textures.

const BOARD := Color(0.10, 0.27, 0.20)
const BOARD_DEEP := Color(0.06, 0.17, 0.13)
const WOOD := Color(0.52, 0.32, 0.15)
const WOOD_DARK := Color(0.30, 0.17, 0.07)
const WOOD_LIGHT := Color(0.74, 0.50, 0.26)
const CHALK := Color(0.95, 0.96, 0.90)
const SIMON_COLS := [
	Color(0.95, 0.30, 0.30), Color(0.35, 0.85, 0.40), Color(0.35, 0.55, 1.0),
	Color(1.0, 0.88, 0.30), Color(1.0, 0.60, 0.25), Color(0.95, 0.45, 0.80),
]

static func _rrect(c: CanvasItem, r: Rect2, rad: float, col: Color) -> void:
	var rr := minf(rad, minf(r.size.x, r.size.y) * 0.5)
	c.draw_rect(Rect2(r.position + Vector2(rr, 0), Vector2(r.size.x - rr * 2.0, r.size.y)), col)
	c.draw_rect(Rect2(r.position + Vector2(0, rr), Vector2(r.size.x, r.size.y - rr * 2.0)), col)
	for p in [r.position + Vector2(rr, rr), r.position + Vector2(r.size.x - rr, rr),
			r.position + Vector2(rr, r.size.y - rr), r.position + r.size - Vector2(rr, rr)]:
		c.draw_circle(p, rr, col)

# The whole board inside `rect`. `t` (seconds) drives a slow shimmer on the chalk
# doodles; pass 0 for a static board. `doodles` adds the Simon-dot doodles in the
# corners (off when the board carries a lot of text).
static func draw_chalkboard(c: CanvasItem, rect: Rect2, t: float = 0.0, doodles: bool = true) -> void:
	var frame := maxf(10.0, rect.size.y * 0.06)
	# Soft shadow under the whole board.
	_rrect(c, Rect2(rect.position + Vector2(4, 8), rect.size), 14.0, Color(0, 0, 0, 0.35))
	# Wooden frame with a lit top edge and a darker bottom.
	_rrect(c, rect, 14.0, WOOD_DARK)
	_rrect(c, rect.grow(-2.0), 12.0, WOOD)
	c.draw_rect(Rect2(rect.position + Vector2(10, 3), Vector2(rect.size.x - 20, 3)), WOOD_LIGHT)
	# Wood grain streaks along the frame.
	for i in 6:
		var y := rect.position.y + 4.0 + float(i) * frame / 6.0
		c.draw_line(Vector2(rect.position.x + 12, y), Vector2(rect.end.x - 12, y),
			Color(WOOD_DARK.r, WOOD_DARK.g, WOOD_DARK.b, 0.18), 1.0)
	# The slate.
	var slate := rect.grow(-frame)
	c.draw_rect(slate, BOARD_DEEP)
	c.draw_rect(slate.grow(-3.0), BOARD)
	# Chalk-dust haze: a few broad, faint smudges (deterministic, no RNG).
	for i in 7:
		var fx := fmod(0.13 + i * 0.377, 1.0)
		var fy := fmod(0.29 + i * 0.611, 1.0)
		var p := slate.position + Vector2(slate.size.x * fx, slate.size.y * fy)
		c.draw_circle(p, slate.size.y * (0.10 + 0.05 * float(i % 3)), Color(1, 1, 1, 0.025))
	# Eraser swipe arcs.
	for i in 3:
		var cx := slate.position.x + slate.size.x * (0.25 + 0.25 * i)
		c.draw_arc(Vector2(cx, slate.end.y + slate.size.y * 0.15), slate.size.y * 0.55,
			PI * 1.15, PI * 1.85, 24, Color(1, 1, 1, 0.035), slate.size.y * 0.12)
	if doodles:
		_draw_doodles(c, slate, t)
	# Chalk tray + two sticks of chalk + an eraser.
	var tray := Rect2(Vector2(rect.position.x + rect.size.x * 0.08, rect.end.y - frame * 0.55),
		Vector2(rect.size.x * 0.84, frame * 0.55))
	c.draw_rect(tray, WOOD_DARK)
	c.draw_rect(Rect2(tray.position, Vector2(tray.size.x, 2)), WOOD_LIGHT)
	var sy := tray.position.y - 3.0
	c.draw_line(Vector2(tray.position.x + 30, sy), Vector2(tray.position.x + 58, sy), CHALK, 5.0)
	c.draw_line(Vector2(tray.position.x + 66, sy), Vector2(tray.position.x + 84, sy), SIMON_COLS[3].lightened(0.3), 5.0)
	var er := Rect2(Vector2(tray.end.x - 70, sy - 9), Vector2(44, 12))
	c.draw_rect(er, Color(0.25, 0.28, 0.45))
	c.draw_rect(Rect2(er.position + Vector2(0, er.size.y - 4), Vector2(er.size.x, 4)), Color(0.85, 0.85, 0.80))

# Little chalk Simon wheels in two corners, each segment a chalky Simon colour.
static func _draw_doodles(c: CanvasItem, slate: Rect2, t: float) -> void:
	var r := slate.size.y * 0.11
	for corner in [Vector2(r * 1.5, r * 1.5), Vector2(slate.size.x - r * 1.5, slate.size.y - r * 1.7)]:
		var ctr: Vector2 = slate.position + corner
		for i in 6:
			var a0 := -PI * 0.5 + TAU * float(i) / 6.0 + 0.06
			var a1 := a0 + TAU / 6.0 - 0.12
			var lit := 0.55 + 0.45 * maxf(0.0, sin(t * 2.0 - float(i)))
			var col: Color = SIMON_COLS[i]
			c.draw_arc(ctr, r * 0.72, a0, a1, 10, Color(col.r, col.g, col.b, 0.55 * lit), r * 0.42)
		c.draw_arc(ctr, r * 0.98, 0, TAU, 28, Color(CHALK.r, CHALK.g, CHALK.b, 0.35), 1.5)
		c.draw_circle(ctr, r * 0.26, Color(CHALK.r, CHALK.g, CHALK.b, 0.30))

# A glossy red apple with a leaf, centred at `ctr`, about `s` px tall.
static func draw_apple(c: CanvasItem, ctr: Vector2, s: float) -> void:
	var r := s * 0.42
	var red := Color(0.86, 0.12, 0.14)
	c.draw_circle(ctr + Vector2(0, r * 0.25), r * 1.02, Color(0, 0, 0, 0.25))
	c.draw_circle(ctr + Vector2(-r * 0.42, 0), r * 0.82, red.darkened(0.15))
	c.draw_circle(ctr + Vector2(r * 0.42, 0), r * 0.82, red.darkened(0.15))
	c.draw_circle(ctr + Vector2(-r * 0.38, -r * 0.06), r * 0.76, red)
	c.draw_circle(ctr + Vector2(r * 0.38, -r * 0.06), r * 0.76, red)
	c.draw_circle(ctr + Vector2(-r * 0.55, -r * 0.35), r * 0.20, Color(1, 1, 1, 0.55))
	c.draw_line(ctr + Vector2(0, -r * 0.62), ctr + Vector2(r * 0.12, -r * 1.12), Color(0.36, 0.22, 0.10), maxf(2.0, s * 0.05))
	var leaf := PackedVector2Array([
		ctr + Vector2(r * 0.12, -r * 0.98), ctr + Vector2(r * 0.55, -r * 1.30),
		ctr + Vector2(r * 0.95, -r * 1.12), ctr + Vector2(r * 0.50, -r * 0.88)])
	c.draw_colored_polygon(leaf, Color(0.30, 0.72, 0.30))
