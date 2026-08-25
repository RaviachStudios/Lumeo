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

	# Soft coloured glow for earned badges — a wider, softer halo than before so the
	# medallion reads as lit from within rather than outlined.
	if earned:
		for i in 9:
			var t := float(i) / 8.0
			c.draw_circle(center, R * (0.94 + 0.26 * t), Color(acc.r, acc.g, acc.b, 0.055 * (1.0 - t)))

	# Contact shadow — grounds the medallion against the panel so it feels raised.
	c.draw_circle(center + Vector2(0, R * 0.07), R * 1.0, Color(0.0, 0.0, 0.0, 0.30))

	# ── Metallic medal frame ──
	# A clean circular rim — no teeth or notches. A crisp dark outer edge, then a
	# radial brushed-metal band (outer darker → inner brighter) reading as machined
	# steel/titanium, finished with a thicker outer rim and a thinner inner rim.
	c.draw_circle(center, R, Color(0.03, 0.04, 0.09, 1.0))
	c.draw_circle(center, R * 0.965, acc.darkened(0.42))
	# Radial metal gradient across the whole ring band (down to the inner disc).
	var band_lo := acc.darkened(0.20) if earned else acc.lightened(0.00)
	var band_hi := acc.lightened(0.34) if earned else acc.lightened(0.16)
	for i in 9:
		var t := float(i) / 8.0
		c.draw_circle(center, lerpf(R * 0.960, R * 0.840, t), band_lo.lerp(band_hi, t))
	# Two engraved concentric grooves in place of gear teeth: a fine recessed dark
	# line with a hairline highlight just inside it, like a milled ring catching light.
	c.draw_arc(center, R * 0.912, 0, TAU, 72, Color(0.0, 0.0, 0.0, 0.22), 1.5)
	var g_lite := acc.lightened(0.52) if earned else acc.lightened(0.26)
	c.draw_arc(center, R * 0.898, 0, TAU, 72, Color(g_lite.r, g_lite.g, g_lite.b, 0.30), 1.0)
	# Soft directional bevel: a broad light arc top-left (lit from above-left) and a
	# gentle shadow arc bottom-right, giving the rim rounded depth without hard edges.
	var rw := R * 0.075
	var hi := acc.lightened(0.66) if earned else acc.lightened(0.36)
	c.draw_arc(center, R * 0.925, PI * 0.98, PI * 1.60, 32, Color(hi.r, hi.g, hi.b, 0.85), rw, true)
	c.draw_arc(center, R * 0.925, -PI * 0.04, PI * 0.54, 32, Color(0.0, 0.0, 0.0, 0.28), rw, true)
	# Small specular glints spaced around the rim, brightest near the light source.
	var glints: Array[float] = [PI * 1.28, PI * 1.02, PI * 0.22]
	var glint_a := [0.55, 0.34, 0.22] if earned else [0.30, 0.18, 0.12]
	for gi in glints.size():
		var ga: float = glints[gi]
		var gd := Vector2(cos(ga), sin(ga))
		c.draw_circle(center + gd * (R * 0.925), R * 0.042, Color(1, 1, 1, glint_a[gi]))
	# Thin inner rim framing the disc well, a shade darker to seat the icon.
	c.draw_circle(center, R * 0.845, acc.darkened(0.34) if earned else acc.lightened(0.03))

	# ── Inner disc ──
	# A recessed well: dark rim ring, gradient face, a soft top sheen and a gentle
	# shadow pooled beneath where the emblem sits, giving the icon real depth.
	var disc := Color(0.09, 0.10, 0.16).lerp(acc, 0.15 if earned else 0.05)
	c.draw_circle(center, R * 0.83, disc.darkened(0.35))
	c.draw_circle(center, R * 0.80, disc)
	# Radial face shading (brighter toward top).
	c.draw_circle(center + Vector2(0, -R * 0.10), R * 0.72, disc.lightened(0.06))
	c.draw_circle(center + Vector2(0, R * 0.28), R * 0.50, Color(0.0, 0.0, 0.0, 0.18))
	c.draw_circle(center + Vector2(0, -R * 0.32), R * 0.50, Color(1, 1, 1, 0.075 if earned else 0.035))

	# Emblem.
	var er: float = R * 0.52
	_emblem(c, art, center, er, ink, acc, earned, num)

	# Locked: mute the (often intrinsically-coloured) emblem toward a silhouette and
	# add a recessed inner shadow so it reads as a sunken, not-yet-earned slot; then
	# stamp a padlock chip lower-right. Kept readable, just lower contrast.
	if not earned:
		c.draw_circle(center, R * 0.80, Color(0.10, 0.11, 0.17, 0.58))
		c.draw_arc(center, R * 0.70, PI * 0.94, PI * 1.62, 22, Color(0.0, 0.0, 0.0, 0.28), R * 0.10, true)
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
		"btn":         _em_btn(c, ce, r, acc)
		"btn_seq":     _em_btn_seq(c, ce, r, acc)
		"btn_ring":    _em_btn_ring(c, ce, r, acc)
		"btn_check":   _em_btn_check(c, ce, r, acc)
		"btn_bolt":    _em_btn_bolt(c, ce, r, acc)
		"btn_crown":   _em_btn_crown(c, ce, r, acc)
		"btn_star":    _em_btn_star(c, ce, r, acc)
		"btn_frame":   _em_btn_frame(c, ce, r, acc)
		"key":         _key(c, ce, r, ink)
		"shield":      _shield(c, ce, r, ink, acc)
		"gift":        _gift(c, ce, r, ink, acc)
		"calendar":    _calendar(c, ce, r, ink, acc)
		"flame":       _flame(c, ce, r, acc)
		"controller":  _controller(c, ce, r, ink)
		"rocket":      _rocket(c, ce, r, ink, acc)
		_:             _fill_star(c, ce, r, ink, 5)

# ─── the BUTTON family ───────────────────────────────────────────────────────
#
# Every achievement that is about PLAYING is drawn out of one part: a LUMEO button,
# seen head-on. A dark metal bezel, the lit channel ringing it, a domed coloured cap
# with a gloss in the upper left. It is the same object the game is played on, and
# drawing every one of these emblems from the single `_btn` primitive is what makes
# the gallery read as one designed collection rather than as a pile of clip-art.
#
# This replaced the four-colour wheel emblem (and the bare numeral rings), which
# were the last Simon-shaped things in the badge art.
#
# `lit` is 0..1 — how brightly the button is switched on. An unlit button is not
# black: it is the cap in its own colour, just without the halo, the hot channel or
# the crown highlight. That difference is what a "sequence" emblem is made of.

# The board's own cap colours, in the order the emblems below step through them.
const BTN_CAPS := [
	Color(0.30, 0.82, 0.92),   # cyan
	Color(0.62, 0.44, 1.00),   # violet
	Color(0.98, 0.34, 0.72),   # magenta
	Color(1.00, 0.74, 0.24),   # amber
	Color(0.18, 0.84, 0.56),   # jade
	Color(0.32, 0.52, 1.00),   # blue
]

# The key light every emblem in the set is lit from, so the whole page agrees.
const BTN_LIGHT := Vector2(-0.55, -0.62)

# One button. `r` is the bezel's outer radius.
static func _btn(c: CanvasItem, ce: Vector2, r: float, cap: Color, lit: float) -> void:
	# the light it throws when it is on — drawn first, so it sits behind the metal
	if lit > 0.01:
		for i in 4:
			var t := float(i) / 3.0
			c.draw_circle(ce, r * (1.02 + 0.38 * t),
				Color(cap.r, cap.g, cap.b, 0.19 * lit * (1.0 - t)))
	# the seat it stands in
	c.draw_circle(ce + Vector2(0.0, r * 0.10), r * 1.02, Color(0.0, 0.0, 0.0, 0.38))
	# the bezel: near-black metal with a lit shoulder up-left and a turned shadow
	# down-right, which is the whole reason it reads as a machined ring
	c.draw_circle(ce, r, Color(0.11, 0.12, 0.17))
	c.draw_arc(ce, r * 0.90, PI * 0.94, PI * 1.64, 22, Color(0.56, 0.60, 0.74, 0.90), r * 0.17, true)
	c.draw_arc(ce, r * 0.90, -PI * 0.06, PI * 0.56, 22, Color(0.02, 0.02, 0.05, 0.60), r * 0.17, true)
	# the channel: the lit gap between the bezel and the cap
	c.draw_circle(ce, r * 0.80, Color(0.04, 0.04, 0.08))
	var chan := cap.lerp(Color(1, 1, 1), 0.30 + 0.50 * lit)
	c.draw_arc(ce, r * 0.755, 0, TAU, 40, Color(chan.r, chan.g, chan.b, 0.50 + 0.50 * lit), r * 0.085)
	# the cap: a dome, ramped from a lit crown to a deep shoulder
	_btn_cap(c, ce, r * 0.70, cap, lit)

# The cap on its own — a vertical ramp built as a coloured polygon so it is a real
# gradient, plus the broad sheen a moulded plastic dome always has up-left.
static func _btn_cap(c: CanvasItem, ce: Vector2, r: float, cap: Color, lit: float) -> void:
	var top := cap.lightened(0.22 + 0.40 * lit)
	var bot := cap.darkened(0.46 - 0.24 * lit)
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var n := 40
	for i in n:
		var a := TAU * float(i) / float(n)
		var p := Vector2(cos(a), sin(a)) * r
		pts.append(ce + p)
		cols.append(top.lerp(bot, smoothstep(0.0, 1.0, (p.y + r) / (2.0 * r))))
	c.draw_polygon(pts, cols)
	c.draw_circle(ce + Vector2(-r * 0.30, -r * 0.34), r * 0.34, Color(1, 1, 1, 0.20 + 0.16 * lit))
	c.draw_arc(ce, r * 0.94, 0, TAU, 32, Color(0.0, 0.0, 0.0, 0.22), r * 0.12)

# ONE button, switched on. The simplest member of the set and the one everything
# else is a variation of.
static func _em_btn(c: CanvasItem, ce: Vector2, r: float, acc: Color) -> void:
	_btn(c, ce, r * 0.86, _cap_for(acc, 0), 1.0)

# A three-button SEQUENCE, reading left to right: lit, lit, waiting. The whole game
# in one emblem — an order, and a next step.
static func _em_btn_seq(c: CanvasItem, ce: Vector2, r: float, acc: Color) -> void:
	var br := r * 0.40
	var lits := [1.0, 0.72, 0.0]
	for i in 3:
		var x := (float(i) - 1.0) * r * 0.72
		var y := -r * 0.10 + absf(float(i) - 1.0) * r * 0.06
		_btn(c, ce + Vector2(x, y), br, _cap_for(acc, i), lits[i])
	# the order marks under the row: two filled, one hollow
	for i in 3:
		var p := ce + Vector2((float(i) - 1.0) * r * 0.72, r * 0.74)
		if i < 2:
			c.draw_circle(p, r * 0.075, Color(1, 1, 1, 0.80))
		else:
			c.draw_arc(p, r * 0.075, 0, TAU, 14, Color(1, 1, 1, 0.42), r * 0.032)

# SIX buttons in a ring with three of them lit: a pattern held in memory. The ring
# is deliberately six INDIVIDUAL buttons with air between them — never a divided disc.
static func _em_btn_ring(c: CanvasItem, ce: Vector2, r: float, acc: Color) -> void:
	var br := r * 0.31
	var ring := r * 0.66
	var on := [true, false, true, false, false, true]
	for i in 6:
		var a := -PI * 0.5 + TAU * float(i) / 6.0
		_btn(c, ce + Vector2(cos(a), sin(a)) * ring, br, _cap_for(acc, i), 1.0 if on[i] else 0.0)

# A button with a CHECK struck over it: a sequence returned correctly.
static func _em_btn_check(c: CanvasItem, ce: Vector2, r: float, acc: Color) -> void:
	_btn(c, ce, r * 0.90, _cap_for(acc, 3), 0.85)
	var w := r * 0.17
	var a := ce + Vector2(-r * 0.34, r * 0.00)
	var b := ce + Vector2(-r * 0.08, r * 0.30)
	var d := ce + Vector2(r * 0.40, -r * 0.34)
	for pass_i in 2:                                  # a dark under-stroke, then white
		var col := Color(0.02, 0.03, 0.08, 0.55) if pass_i == 0 else Color(1, 1, 1, 1)
		var k: float = 1.34 if pass_i == 0 else 1.0
		c.draw_line(a, b, col, w * k)
		c.draw_line(b, d, col, w * k)
		c.draw_circle(a, w * k * 0.5, col)
		c.draw_circle(b, w * k * 0.5, col)
		c.draw_circle(d, w * k * 0.5, col)

# A BOLT struck across a button: speed, and the hard difficulties.
static func _em_btn_bolt(c: CanvasItem, ce: Vector2, r: float, acc: Color) -> void:
	_btn(c, ce, r * 0.82, _cap_for(acc, 3), 0.9)
	var s := r * 0.86
	var tri := PackedVector2Array([
		ce + Vector2(0.16, -1.06) * s, ce + Vector2(-0.44, 0.10) * s,
		ce + Vector2(0.02, 0.10) * s, ce + Vector2(-0.14, 1.06) * s,
		ce + Vector2(0.48, -0.08) * s, ce + Vector2(0.02, -0.08) * s])
	var halo := PackedVector2Array()
	for p in tri:
		halo.append(ce + (p - ce) * 1.16)
	c.draw_colored_polygon(halo, Color(0.02, 0.03, 0.08, 0.50))
	c.draw_colored_polygon(tri, Color(1.0, 0.94, 0.62))
	c.draw_colored_polygon(PackedVector2Array([tri[0], tri[1], tri[2]]), Color(1, 1, 1, 0.75))

# A CROWN riding on top of a button.
static func _em_btn_crown(c: CanvasItem, ce: Vector2, r: float, acc: Color) -> void:
	_btn(c, ce + Vector2(0.0, r * 0.22), r * 0.74, _cap_for(acc, 1), 1.0)
	_crown(c, ce + Vector2(0.0, -r * 0.66), r * 0.52, Color(1, 1, 1))

# A STAR bursting behind a button.
static func _em_btn_star(c: CanvasItem, ce: Vector2, r: float, acc: Color) -> void:
	var gold := Color(1.0, 0.86, 0.34)
	_poly(c, _star_pts(ce, r * 1.04, r * 0.44, 5), Color(gold.r, gold.g, gold.b, 0.55))
	_poly(c, _star_pts(ce, r * 0.92, r * 0.38, 5), gold)
	_btn(c, ce, r * 0.58, _cap_for(acc, 0), 1.0)

# A button wearing a cosmetic FRAME: the stock bezel with a second, decorative ring
# fitted over it, which is exactly what a Button Frame is.
static func _em_btn_frame(c: CanvasItem, ce: Vector2, r: float, acc: Color) -> void:
	# the cosmetic ring, in the badge's own accent, seated proud of the button
	for i in 4:
		var t := float(i) / 3.0
		c.draw_arc(ce, r * (1.00 + 0.10 * t), 0, TAU, 40,
			Color(acc.r, acc.g, acc.b, 0.18 * (1.0 - t)), r * 0.16)
	c.draw_arc(ce, r * 0.98, 0, TAU, 44, Color(0.10, 0.11, 0.16), r * 0.26)
	c.draw_arc(ce, r * 0.98, 0, TAU, 44, acc.lightened(0.46), r * 0.15)
	c.draw_arc(ce, r * 1.04, 0, TAU, 44, Color(0.05, 0.05, 0.09, 0.70), r * 0.05)
	c.draw_arc(ce, r * 0.98, PI * 0.96, PI * 1.62, 22, Color(1, 1, 1, 0.72), r * 0.07)
	_btn(c, ce, r * 0.80, _cap_for(acc, 1), 0.55)

# The cap colour emblem `i` uses. Anchored to the badge's own accent when the accent
# is a real colour, so a locked (slate) badge greys out with everything else.
static func _cap_for(acc: Color, i: int) -> Color:
	if acc.s < 0.32:                                  # locked/slate: no colour to keep
		return acc.lightened(0.10 + 0.06 * float(i % 3))
	return BTN_CAPS[i % BTN_CAPS.size()]

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
	# The milestone number moulded into the CAP of a lit button — the same part every
	# other gameplay emblem is built from, so a "reach round 20" badge belongs to the
	# same set as the sequence and pattern ones. It used to be a bare target ring.
	_btn(c, ce, r * 0.98, _cap_for(acc, 0), 0.80)
	var cap_r := r * 0.98 * 0.70
	var f := ThemeDB.fallback_font
	var fs := int(cap_r * (1.52 if num < 10 else (1.16 if num < 100 else 0.90)))
	var s := str(num)
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
	var at := ce - Vector2(w.x * 0.5, -w.y * 0.32)
	# a soft drop under the numeral: a lit cap is bright enough that plain white ink
	# on it loses its edges
	c.draw_string(f, at + Vector2(0.0, r * 0.05), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		Color(0.02, 0.03, 0.10, 0.50))
	c.draw_string(f, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1))

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
