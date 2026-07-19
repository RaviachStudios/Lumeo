class_name ArenaIcons
extends RefCounted

# Custom-drawn vector icons for the arena's contest popups, replacing the emoji
# glyphs 🎲 / 🌐 / 🔒 (shuffle-name die, Public globe, Private padlock) so they
# render identically on every device and match the app's hand-drawn look. Each
# draw_* paints centered inside `size` on the given CanvasItem.

static func paint(c: CanvasItem, kind: String, size: Vector2, col: Color) -> void:
	match kind:
		"dice":  draw_dice(c, size, col)
		"globe": draw_globe(c, size, col)
		"lock":  draw_lock(c, size, col)

# ---------------- shared helpers ----------------

# Filled rounded rectangle (Godot's draw_rect has no corner radius): a plus-shaped
# pair of rects plus four corner discs.
static func _rounded_rect(c: CanvasItem, rect: Rect2, r: float, col: Color) -> void:
	r = min(r, min(rect.size.x, rect.size.y) * 0.5)
	var p := rect.position
	var s := rect.size
	c.draw_rect(Rect2(p.x + r, p.y, s.x - 2.0 * r, s.y), col)
	c.draw_rect(Rect2(p.x, p.y + r, s.x, s.y - 2.0 * r), col)
	c.draw_circle(Vector2(p.x + r, p.y + r), r, col)
	c.draw_circle(Vector2(p.x + s.x - r, p.y + r), r, col)
	c.draw_circle(Vector2(p.x + r, p.y + s.y - r), r, col)
	c.draw_circle(Vector2(p.x + s.x - r, p.y + s.y - r), r, col)

# A closed ellipse outline, used for the globe's meridians and rim.
static func _ellipse(c: CanvasItem, ctr: Vector2, rx: float, ry: float, col: Color, w: float) -> void:
	var pts := PackedVector2Array()
	var n := 48
	for i in range(n + 1):
		var a := TAU * float(i) / float(n)
		pts.append(ctr + Vector2(cos(a) * rx, sin(a) * ry))
	c.draw_polyline(pts, col, w, true)

# ---------------- 🎲 die (shuffle name) ----------------

static func draw_dice(c: CanvasItem, size: Vector2, col: Color) -> void:
	var ctr := size * 0.5
	var d: float = min(size.x, size.y) * 0.72       # die side
	var r: float = d * 0.22                          # corner radius
	var rect := Rect2(ctr.x - d * 0.5, ctr.y - d * 0.5, d, d)
	# contact shadow
	_rounded_rect(c, Rect2(rect.position + Vector2(0.0, d * 0.07), rect.size), r, Color(0.0, 0.0, 0.0, 0.30))
	# body
	_rounded_rect(c, rect, r, col)
	# top sheen: a lighter band across the upper half
	_rounded_rect(c, Rect2(rect.position + Vector2(d * 0.12, d * 0.10), Vector2(d * 0.76, d * 0.30)),
		d * 0.14, Color(1.0, 1.0, 1.0, 0.14))
	# pips — the "5" face
	var pip: float = d * 0.115
	var dark := Color(0.12, 0.09, 0.05, 0.94)
	var o: float = d * 0.26
	for off in [Vector2(-o, -o), Vector2(o, -o), Vector2.ZERO, Vector2(-o, o), Vector2(o, o)]:
		c.draw_circle(ctr + off, pip, dark)

# ---------------- 🌐 globe (Public) ----------------

static func draw_globe(c: CanvasItem, size: Vector2, _col: Color) -> void:
	# Self-coloured so it always reads as a little world globe (an accent tint would
	# muddy the ocean/land contrast), independent of the caller's icon colour.
	var ctr := size * 0.5
	var R: float = min(size.x, size.y) * 0.42
	var ocean := Color(0.34, 0.66, 0.80)
	var grid := Color(0.09, 0.27, 0.40, 0.85)
	var land := Color(0.42, 0.72, 0.46)
	# sphere
	c.draw_circle(ctr, R, ocean)
	# a couple of land blobs
	c.draw_circle(ctr + Vector2(-R * 0.34, -R * 0.24), R * 0.30, land)
	c.draw_circle(ctr + Vector2(R * 0.30, R * 0.10), R * 0.26, land)
	c.draw_circle(ctr + Vector2(R * 0.02, R * 0.46), R * 0.16, land)
	# latitude chords (width follows the sphere silhouette)
	for fy in [-0.5, 0.0, 0.5]:
		var y: float = fy * R
		var hw: float = sqrt(max(R * R - y * y, 0.0))
		c.draw_line(ctr + Vector2(-hw, y), ctr + Vector2(hw, y), grid, 2.0, true)
	# meridians: centre line + one vertical ellipse (gives the two side longitudes)
	c.draw_line(ctr + Vector2(0.0, -R), ctr + Vector2(0.0, R), grid, 2.0, true)
	_ellipse(c, ctr, R * 0.55, R, grid, 2.0)
	# rim
	_ellipse(c, ctr, R, R, grid, 2.0)

# ---------------- 🔒 padlock (Private) ----------------

static func draw_lock(c: CanvasItem, size: Vector2, col: Color) -> void:
	var ctr := size * 0.5
	var w: float = min(size.x, size.y)
	# body
	var bw: float = w * 0.60
	var bh: float = w * 0.46
	var brect := Rect2(ctr.x - bw * 0.5, ctr.y + w * 0.04 - bh * 0.5, bw, bh)
	# shackle: an upside-down U (semicircle + two straight legs) sitting on the body
	var sr: float = bw * 0.30
	var scy: float = brect.position.y - sr * 0.10
	var shcol := col.darkened(0.18)
	var sw: float = w * 0.11
	c.draw_arc(Vector2(ctr.x, scy), sr, PI, TAU, 24, shcol, sw, true)
	var leg_bot: float = brect.position.y + 2.0
	c.draw_line(Vector2(ctr.x - sr, scy), Vector2(ctr.x - sr, leg_bot), shcol, sw)
	c.draw_line(Vector2(ctr.x + sr, scy), Vector2(ctr.x + sr, leg_bot), shcol, sw)
	# contact shadow + body
	_rounded_rect(c, Rect2(brect.position + Vector2(0.0, w * 0.05), brect.size), w * 0.12, Color(0.0, 0.0, 0.0, 0.28))
	_rounded_rect(c, brect, w * 0.12, col)
	# top sheen
	_rounded_rect(c, Rect2(brect.position + Vector2(bw * 0.14, bh * 0.14), Vector2(bw * 0.72, bh * 0.22)),
		bh * 0.10, Color(1.0, 1.0, 1.0, 0.15))
	# keyhole
	var dark := Color(0.12, 0.09, 0.05, 0.94)
	var ky: float = brect.position.y + bh * 0.42
	c.draw_circle(Vector2(ctr.x, ky), w * 0.07, dark)
	c.draw_rect(Rect2(ctr.x - w * 0.028, ky, w * 0.056, bh * 0.34), dark)
