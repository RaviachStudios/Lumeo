extends Control

# The LEVEL readout every difficulty plays with: a machined dark-glass badge on
# the LEFT edge of the play screen, level with the middle of the button
# formation.
#
# It replaces two older readouts that said the same thing in two different
# places — Medium's plate lying on the board (top of the screen, in the board's
# own perspective) and Easy/Hard's flat "ROUND n" pill in the bottom-left corner.
# One readout, one place, one look on all three boards.
#
# Where it sits is measured, never assumed. `layout_in` is handed the board's
# actual projected silhouette and seats the badge in the gutter left of it: high
# up (its centre at 75% of the screen height, measured from the bottom),
# horizontally centred in whatever room that board leaves — so Easy's narrow triangle gives it more air from the screen edge
# than Hard's wide hexagon does — with a floor of TAB_MARGIN so it never crowds
# the edge. `MemoryGameUI._fit_camera` reserves `reserved_width()` on the left, so
# there is always a gutter to sit in and no button can ever grow into it. The tap
# targets are the button TOPS, which are further in still.
#
# Everything here is drawn, not textured — the tab has to sit on top of a live
# 3D render on every skin, so it carries its own depth: a dark cast shadow, a
# cool outer bloom, a vertical body gradient, a glass gloss over the top third,
# a bright top rim fading to a dark bottom rim, and an accent light-bar under
# the numeral. Nothing is a plain flat panel.
#
# It ignores mouse input, so a tap that lands on it still reaches game.gd and is
# hit-tested against the board underneath.
#
# Referenced as `preload("res://level_tab.gd")` rather than through a class_name,
# the same way ui_kit.gd is, so it never depends on the editor's global-class
# scan having run (the acceptance harnesses run the project headless).

# ---------------------------------------------------------------------------
# Geometry (design pixels; the project stretches canvas_items from 1280x720)
# ---------------------------------------------------------------------------
const TAB_W := 114.0                     # = game.gd's HUD_RIGHT_BTN_W
const TAB_H := 152.0
# Distance from the screen edge: the floor matches the right-hand HUD column's
# own margin, and the ceiling stops the badge drifting into the middle of a board
# that happens to leave a lot of room (Easy at a wide aspect).
const TAB_MARGIN := 20.0                 # = game.gd's HUD_RIGHT_MARGIN
const TAB_MARGIN_MAX := 44.0
# Clearance the fit keeps between the badge's plate and the nearest button. The
# bloom is allowed to graze the outermost dark rim beyond this — it is a soft
# halo over a near-black bezel, and buying it a full BLOOM_W would cost the board
# real width on the tightest aspect.
const TAB_GAP := 10.0
# Where the badge's centre rides, as a fraction of the screen height measured from
# the TOP: 0.25 is 75% of the way up from the bottom. It is screen-relative rather
# than board-relative so the badge holds the same height on all three boards and
# at every aspect, whatever the formation underneath it is doing.
const TAB_CENTRE_Y := 0.25
const TAB_TOP_MIN := 88.0                # below the watch-ad pill / Quit row
# game.gd's status pill row. It was 84.0 — a copy of the pill's old hardcoded
# offset, which moved when the pill's lane was made responsive and the copy did
# not. Derived from the pill's own geometry now, so the badge cannot drift into a
# row that has since moved.
const TAB_BOTTOM_KEEP := 76.0
# Asymmetric corners: big and capsule-like on one side, tighter on the other, so
# the silhouette reads as a tab rather than as one more rounded rectangle.
const R_LEFT := 30.0
const R_RIGHT := 13.0

const PAD := 11.0
const CAP_BASELINE := 25.0               # "LEVEL" sits in the header band
const RULE_Y := 35.0                     # hairline closing the header band
# The numeral sits in a WELL: a rounded window recessed into the plate, dark at
# the top where the bezel shades it and catching a light line along its bottom
# lip. It is what turns the tab from a rounded rectangle with a number on it into
# a machined bezel around a lit display, and it gives the numeral's glow
# something dark to glow against.
const WELL := Rect2(8.0, 41.0, TAB_W - 16.0, 84.0)
const WELL_R := 14.0
const BAR_Y := 134.0                     # accent light-bar under the well
const BAR_W := 58.0
const BAR_H := 3.0

const CAP_TEXT := "LEVEL"
const CAP_SIZE := 13
const CAP_TRACK := 3.4                   # letterspacing, drawn glyph by glyph
const NUM_SIZE := 58                     # shrunk to fit once it reaches 3 digits
# The UI face is a text weight; a readout at this size wants display weight. A
# FontVariation embolden is the way to get it without shipping a second font
# (the same trick the board's old stage numeral used).
const NUM_EMBOLDEN := 0.28

# ---------------------------------------------------------------------------
# Palette
# ---------------------------------------------------------------------------
# The play screen's HUD language is deep indigo glass with a cool blue rim (the
# status pill, the quit dome's shadow). The tab stays inside it and spends its
# one bright note on the accent bar.
const BODY_TOP := Color(0.075, 0.098, 0.220, 0.94)
const BODY_BOT := Color(0.021, 0.031, 0.086, 0.94)
const HEADER_TINT := Color(0.16, 0.21, 0.42, 0.55)   # the band behind "LEVEL"
const GLOSS := Color(0.62, 0.74, 1.0)                # top glass highlight
const GLOSS_A := 0.13
const RIM_TOP := Color(0.52, 0.64, 1.0, 0.95)
const RIM_BOT := Color(0.13, 0.18, 0.40, 0.75)
const INNER_TOP := Color(0.72, 0.82, 1.0, 0.22)      # 1 px inset catchlight
const BLOOM := Color(0.30, 0.45, 1.0)                # outer halo
const BLOOM_W := 22.0                                # how far it reaches out
const SHADOW := Color(0.0, 0.005, 0.03, 0.34)
const WELL_TOP := Color(0.012, 0.020, 0.055, 0.92)    # recessed: dark at the top
const WELL_BOT := Color(0.045, 0.065, 0.150, 0.92)
const WELL_LIP := Color(0.55, 0.70, 1.0, 0.30)       # light along the bottom lip
const WELL_SHEEN := Color(0.70, 0.84, 1.0)           # diagonal glass streak
const CAP_COLOR := Color(0.66, 0.77, 1.0)
const NUM_COLOR := Color(0.95, 0.97, 1.0)
const NUM_GLOW := Color(0.35, 0.62, 1.0)
const ACCENT_A := Color(0.30, 0.92, 1.0)             # bar: cyan ...
const ACCENT_B := Color(0.62, 0.42, 1.0)             # ... to violet

# ---------------------------------------------------------------------------
# Motion
# ---------------------------------------------------------------------------
# A level lands with a punch: the plate over-scales and settles, the new numeral
# rolls up into place behind the old one, and a flare runs through the rim, the
# bloom and the accent bar. It is the only moment of the game the tab has, so it
# takes it — but it is over in half a second and never repeats on its own.
const BUMP_LEN := 0.34
const BUMP_AMT := 0.085
const ROLL_LEN := 0.30
const FLARE_LEN := 0.60
# The idle breath is deliberately slow and shallow; it is redrawn at IDLE_HZ
# rather than every frame, since this control sits over a 3D viewport that is
# itself only re-rendered on demand.
const BREATH_HZ := 0.22
const IDLE_HZ := 20.0

var _level := 1
var _num_font: Font = null               # the equipped level-number face, if any
var _num_tint: Color = NUM_COLOR
var _num: NumRoll

var _t := 0.0                            # free-running clock for the breath
var _redraw_acc := 0.0
var _bump := 0.0                         # 1 -> 0 across BUMP_LEN
var _flare := 0.0                        # 1 -> 0 across FLARE_LEN

# The numeral lives in its own clipped child so the roll can slide the outgoing
# and incoming digits past the window edges without painting over the header.
class NumRoll extends Control:
	var text := "1"
	var prev := ""
	var roll := 1.0                      # 0 = mid-roll, 1 = settled
	var font: Font = null
	var tint := Color(0.95, 0.97, 1.0)
	var glow := Color(0.35, 0.62, 1.0)
	var base_size := 58              # NUM_SIZE; the owner sets it on build

	func _init() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Shrink once the number outgrows the tab, so "148" still reads as one word
	# and never touches the sides.
	func _size_for(s: String, f: Font) -> int:
		var fs := base_size
		var room := size.x - 6.0
		while fs > 22 and f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room:
			fs -= 2
		return fs

	func _draw_num(s: String, f: Font, dy: float, a: float) -> void:
		if s == "" or a <= 0.003:
			return
		var fs := _size_for(s, f)
		var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var base := size.y * 0.5 + (f.get_ascent(fs) - f.get_descent(fs)) * 0.5
		var p := Vector2((size.x - w) * 0.5, base + dy)
		# Bloom first (three fading copies offset around the glyphs), then a dark
		# outline for definition against a bright button, then the numeral.
		for i in 3:
			var r := 3.0 + float(i) * 3.4
			var ga := glow.a * (0.30 - float(i) * 0.085) * a
			if ga > 0.0:
				var c := Color(glow.r, glow.g, glow.b, ga)
				f.draw_string_outline(get_canvas_item(), p, s, HORIZONTAL_ALIGNMENT_LEFT,
					-1, fs, int(r), c)
		f.draw_string_outline(get_canvas_item(), p, s, HORIZONTAL_ALIGNMENT_LEFT,
			-1, fs, 4, Color(0.02, 0.03, 0.09, 0.72 * a))
		f.draw_string(get_canvas_item(), p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(tint.r, tint.g, tint.b, tint.a * a))

	func _draw() -> void:
		var f := font if font != null else ThemeDB.fallback_font
		if f == null:
			return
		var e := 1.0 - pow(1.0 - clampf(roll, 0.0, 1.0), 3.0)   # ease-out cubic
		if prev != "" and e < 1.0:
			_draw_num(prev, f, -size.y * 0.62 * e, 1.0 - e)
		_draw_num(text, f, size.y * 0.62 * (1.0 - e), e)

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	_num = NumRoll.new()
	_num.base_size = NUM_SIZE
	_num.font = _face()
	_num.tint = _num_tint
	_num.glow = NUM_GLOW
	_num.text = str(_level)   # whatever set_level was given before the tree
	add_child(_num)
	_layout()
	set_process(true)

# Seat the badge in the gutter to the LEFT of the board, given the viewport and
# the board's own projected silhouette (an empty rect means the fit has not run
# yet — fall back to the reserved column, which is what the fit will leave).
#
# X: centred in the gutter, so the spacing to the screen edge and the spacing to
# the nearest button come out even, clamped into [TAB_MARGIN, TAB_MARGIN_MAX].
# That is the per-board adaptation — a narrow board leaves a wide gutter and the
# badge moves inward; a wide one leaves the minimum and it hugs the edge.
#
# Y: the badge's CENTRE sits at TAB_CENTRE_Y of the screen height — 75% of the way
# up from the bottom — which is high in the left gutter, above the middle of the
# board rather than level with it. Clamped so it never rides up under the watch-ad
# pill and the Quit dome, and never drops into the status pill's row.
func layout_in(area: Vector2, board: Rect2 = Rect2()) -> void:
	size = Vector2(TAB_W, TAB_H)
	var gutter: float = board.position.x if board.size.x > 0.0 else reserved_width()
	var x := clampf((gutter - TAB_W) * 0.5, TAB_MARGIN, TAB_MARGIN_MAX)
	var y_max := maxf(TAB_TOP_MIN, area.y - TAB_BOTTOM_KEEP - TAB_H)
	var y := clampf(area.y * TAB_CENTRE_Y - TAB_H * 0.5, TAB_TOP_MIN, y_max)
	position = Vector2(x, y)
	pivot_offset = size * 0.5
	_layout()

func _layout() -> void:
	if _num == null:
		return
	# Inset inside the well, so the roll clips against the window rather than the
	# window's own rim.
	_num.position = WELL.position + Vector2(3.0, 3.0)
	_num.size = WELL.size - Vector2(6.0, 6.0)
	_num.queue_redraw()

# The column on the LEFT that the board must not grow into: the badge at its
# closest-to-the-edge, plus the clearance the plate keeps from the nearest button.
# MemoryGameUI._fit_camera reserves exactly this much.
static func reserved_width() -> float:
	return TAB_MARGIN + TAB_W + TAB_GAP

# A level lands: roll the new numeral in behind the old one, punch the plate and
# run the flare. Setting the level it already shows is a no-op, which is what
# keeps the very first round (game.gd starts at 1 and the tab is born showing 1)
# from firing the animation before the player has done anything.
func set_level(n: int) -> void:
	var s := str(n)
	if _num == null:                     # set before the tab entered the tree
		_level = n
		return
	if n == _level and s == _num.text:
		return
	_level = n
	_num.prev = _num.text
	_num.text = s
	_num.roll = 0.0
	_bump = 1.0
	_flare = 1.0
	_num.queue_redraw()
	queue_redraw()

# The equipped level-number package (CoinsManager.SIMON_NUMBER_FONTS): only the
# typeface and the tint carry over. The caption stays the HUD's own face so the
# tab keeps reading as interface whatever the player has equipped.
func apply_number_pack(pack: Variant) -> void:
	var d: Dictionary = pack if (pack is Dictionary) else {}
	_num_font = null
	var fp := String(d.get("font", ""))
	if fp != "" and ResourceLoader.exists(fp):
		var f := load(fp)
		if f is Font:
			_num_font = f
	_num_tint = d.get("color", NUM_COLOR)
	if _num != null:
		_num.font = _face()
		_num.tint = _num_tint
		_num.queue_redraw()

func _face() -> Font:
	var src := _num_font
	if src == null:
		src = get_theme_font("font", "Label")
	if src == null:
		src = ThemeDB.fallback_font
	if src == null:
		return null
	var fv := FontVariation.new()
	fv.base_font = src
	fv.variation_embolden = NUM_EMBOLDEN
	return fv

func _process(dt: float) -> void:
	_t += dt
	var busy := _bump > 0.0 or _flare > 0.0 or (_num != null and _num.roll < 1.0)
	if _bump > 0.0:
		_bump = maxf(0.0, _bump - dt / BUMP_LEN)
		# One damped overshoot, not a bounce loop.
		var u := 1.0 - _bump
		var k := sin(PI * u) * exp(-2.4 * u)
		scale = Vector2.ONE * (1.0 + BUMP_AMT * k)
		if _bump == 0.0:
			scale = Vector2.ONE
	if _flare > 0.0:
		_flare = maxf(0.0, _flare - dt / FLARE_LEN)
	if _num != null and _num.roll < 1.0:
		_num.roll = minf(1.0, _num.roll + dt / ROLL_LEN)
		_num.queue_redraw()
	if busy:
		queue_redraw()
		_redraw_acc = 0.0
		return
	# Idle: the breath only needs a low cadence.
	_redraw_acc += dt
	if _redraw_acc >= 1.0 / IDLE_HZ:
		_redraw_acc = 0.0
		queue_redraw()

# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

# A rounded-rectangle outline as a closed polygon, corners in TL, TR, BR, BL
# order. `grow` expands it outward (used for the bloom and the shadow), which
# also grows the radii so the halo stays concentric.
func _rr(rect: Rect2, r_l: float, r_r: float, grow: float = 0.0,
		seg: int = 6) -> PackedVector2Array:
	var rc := rect.grow(grow)
	var rl := maxf(0.0, r_l + grow)
	var rr := maxf(0.0, r_r + grow)
	var lim := minf(rc.size.x, rc.size.y) * 0.5
	rl = minf(rl, lim)
	rr = minf(rr, lim)
	var pts := PackedVector2Array()
	var corners := [
		[Vector2(rc.position.x + rl, rc.position.y + rl), rl, PI, PI * 1.5],           # TL
		[Vector2(rc.end.x - rr, rc.position.y + rr), rr, PI * 1.5, TAU],               # TR
		[Vector2(rc.end.x - rr, rc.end.y - rr), rr, 0.0, PI * 0.5],                    # BR
		[Vector2(rc.position.x + rl, rc.end.y - rl), rl, PI * 0.5, PI],                # BL
	]
	for c: Array in corners:
		var ctr: Vector2 = c[0]
		var rad: float = c[1]
		var a0: float = c[2]
		var a1: float = c[3]
		for i in range(seg + 1):
			var a: float = lerpf(a0, a1, float(i) / float(seg))
			var v := ctr + Vector2(cos(a), sin(a)) * rad
			# A capsule (radius == half the short side) has its arcs meet exactly,
			# and a repeated vertex is what makes Godot's triangulator reject the
			# polygon outright — so coincident points never go in.
			if pts.is_empty() or pts[pts.size() - 1].distance_squared_to(v) > 0.0004:
				pts.append(v)
	if pts.size() > 2 and pts[0].distance_squared_to(pts[pts.size() - 1]) <= 0.0004:
		pts.remove_at(pts.size() - 1)
	return pts

# A soft edge around the plate: one ring of triangles running from the silhouette
# outward, opaque at the inside edge and transparent at the outside. Both a glow
# and a cast shadow are the same shape, so both are drawn this way.
#
# It is deliberately NOT a stack of expanded fills or outlines. At any spacing
# coarse enough to be cheap, those read as concentric rings — and a halo that
# shows its own construction looks worse than no halo. One triangle array is also
# one draw call, which matters on a control that repaints while it animates.
func _feather(rect: Rect2, r_l: float, r_r: float, width: float, offset: Vector2,
		col: Color, col_b: Variant = null) -> void:
	var inner := _rr(rect, r_l, r_r)
	var outer := _rr(rect, r_l, r_r, width)
	var n := inner.size()
	if n == 0 or outer.size() != n:
		return
	var far: Color = col_b if (col_b is Color) else col
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for i in n:
		var u := clampf((inner[i].x - rect.position.x) / maxf(rect.size.x, 0.001), 0.0, 1.0)
		var c := col.lerp(far, u)
		pts.append(inner[i] + offset)
		cols.append(c)
	for i in n:
		var u2 := clampf((inner[i].x - rect.position.x) / maxf(rect.size.x, 0.001), 0.0, 1.0)
		var c2 := col.lerp(far, u2)
		pts.append(outer[i] + offset)
		cols.append(Color(c2.r, c2.g, c2.b, 0.0))
	var idx := PackedInt32Array()
	for i in n:
		var j := (i + 1) % n
		idx.append_array([i, j, n + i, j, n + j, n + i])
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), idx, pts, cols)

# Per-vertex colours for a vertical gradient across a polygon, so one draw_polygon
# gives a smooth body instead of a flat fill.
func _grad(pts: PackedVector2Array, y0: float, y1: float, c0: Color,
		c1: Color) -> PackedColorArray:
	var cols := PackedColorArray()
	var span := maxf(y1 - y0, 0.001)
	for p: Vector2 in pts:
		cols.append(c0.lerp(c1, clampf((p.y - y0) / span, 0.0, 1.0)))
	return cols

func _draw() -> void:
	var breath := 0.5 + 0.5 * sin(_t * TAU * BREATH_HZ)
	var flare := _flare * _flare              # front-loaded, so the peak is sharp
	var body := Rect2(Vector2.ZERO, size)

	# 1. Cast shadow, offset down: the tab floats above the board, it is not
	#    painted onto it.
	_feather(body, R_LEFT, R_RIGHT, 11.0, Vector2(0.0, 4.0), SHADOW)

	# 2. Cool outer bloom — breathes gently, flares on a level.
	var halo := clampf(0.30 + 0.16 * breath + 1.5 * flare, 0.0, 2.0)
	_feather(body, R_LEFT, R_RIGHT, BLOOM_W, Vector2.ZERO,
		Color(BLOOM.r, BLOOM.g, BLOOM.b, 0.16 * halo))

	# 3. The body: a vertical gradient from indigo glass down to near-black.
	var shell := _rr(body, R_LEFT, R_RIGHT)
	draw_polygon(shell, _grad(shell, 0.0, size.y, BODY_TOP, BODY_BOT))

	# 4. The header band behind "LEVEL", clipped to the shell so it keeps the
	#    top corners, and the hairline that closes it.
	var head := Geometry2D.intersect_polygons(shell,
		_rect_poly(Rect2(0.0, 0.0, size.x, RULE_Y)))
	for poly: PackedVector2Array in head:
		draw_polygon(poly, _grad(poly, 0.0, RULE_Y,
			HEADER_TINT, Color(HEADER_TINT.r, HEADER_TINT.g, HEADER_TINT.b, 0.0)))
	_draw_rule(RULE_Y, flare)

	# 5. The well the numeral sits in, and the glass gloss over the top third of
	#    the plate — brightest at the very top, gone before it reaches the well.
	_draw_well(flare)
	var gloss := Geometry2D.intersect_polygons(shell,
		_rect_poly(Rect2(0.0, 0.0, size.x, size.y * 0.34)))
	for poly: PackedVector2Array in gloss:
		draw_polygon(poly, _grad(poly, 0.0, size.y * 0.34,
			Color(GLOSS.r, GLOSS.g, GLOSS.b, GLOSS_A),
			Color(GLOSS.r, GLOSS.g, GLOSS.b, 0.0)))

	# 6. Rim: a bright top edge falling to a dark bottom one, plus a 1 px inset
	#    catchlight just inside the top — the two together read as a bevel.
	var rim := _rr(body, R_LEFT, R_RIGHT, -0.75)
	rim.append(rim[0])
	var rim_top := RIM_TOP.lerp(Color(1.0, 1.0, 1.0, 1.0), 0.55 * flare)
	draw_polyline_colors(rim, _grad(rim, 0.0, size.y, rim_top, RIM_BOT), 1.6, true)
	var inner := _rr(body, R_LEFT, R_RIGHT, -2.6)
	var inner_cols := _grad(inner, 0.0, size.y * 0.55, INNER_TOP,
		Color(INNER_TOP.r, INNER_TOP.g, INNER_TOP.b, 0.0))
	inner.append(inner[0])
	inner_cols.append(inner_cols[0])
	draw_polyline_colors(inner, inner_cols, 1.0, true)

	# 7. "LEVEL", drawn glyph by glyph so it can be letterspaced. Small caps with
	#    air between them is the one typographic cue that separates a designed
	#    readout from a label.
	_draw_caption(flare)

	# 8. The accent light-bar under the numeral: cyan to violet, sitting in its
	#    own bloom. This is the tab's only saturated colour, and the thing that
	#    flares when a level lands.
	_draw_accent(breath, flare)

	# 9. The level-up wash: a single bright sheet over the whole plate, gone in
	#    under a second.
	if flare > 0.001:
		draw_colored_polygon(shell, Color(0.72, 0.86, 1.0, 0.085 * flare))

# The recessed window: a dark rounded well with the bezel's shadow across its top,
# a catchlight along its bottom lip and one diagonal glass streak. On a level it
# takes a short cyan lift, so the display reads as the thing that lit up.
func _draw_well(flare: float) -> void:
	var w := _rr(WELL, WELL_R, WELL_R)
	var top := WELL_TOP.lerp(Color(0.05, 0.13, 0.28, WELL_TOP.a), 0.55 * flare)
	draw_polygon(w, _grad(w, WELL.position.y, WELL.end.y, top, WELL_BOT))
	# The bezel shades the top of a recess: a short, steep falloff just inside it.
	var shade := Geometry2D.intersect_polygons(w,
		_rect_poly(Rect2(WELL.position.x, WELL.position.y, WELL.size.x, 16.0)))
	for poly: PackedVector2Array in shade:
		draw_polygon(poly, _grad(poly, WELL.position.y, WELL.position.y + 16.0,
			Color(0.0, 0.004, 0.02, 0.55), Color(0.0, 0.004, 0.02, 0.0)))
	# One diagonal streak of glass across the upper-left of the window.
	var sheen := Geometry2D.intersect_polygons(w, PackedVector2Array([
		Vector2(WELL.position.x - 16.0, WELL.end.y + 4.0),
		Vector2(WELL.position.x + WELL.size.x * 0.22, WELL.position.y - 4.0),
		Vector2(WELL.position.x + WELL.size.x * 0.36, WELL.position.y - 4.0),
		Vector2(WELL.position.x - 2.0, WELL.end.y + 4.0),
	]))
	for poly: PackedVector2Array in sheen:
		draw_polygon(poly, _grad(poly, WELL.position.y, WELL.end.y,
			Color(WELL_SHEEN.r, WELL_SHEEN.g, WELL_SHEEN.b, 0.05),
			Color(WELL_SHEEN.r, WELL_SHEEN.g, WELL_SHEEN.b, 0.0)))
	# The lip: bright along the bottom of the recess, dark along the top, which is
	# the opposite of the plate's own rim and is what makes it read as sunk in.
	var lip := _rr(WELL, WELL_R, WELL_R, -0.5)
	lip.append(lip[0])
	var lip_col := WELL_LIP.lerp(Color(0.75, 0.95, 1.0, 0.75), 0.7 * flare)
	draw_polyline_colors(lip, _grad(lip, WELL.position.y + WELL.size.y * 0.35,
		WELL.end.y, Color(0.0, 0.01, 0.04, 0.65), lip_col), 1.2, true)

func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end,
		Vector2(r.position.x, r.end.y)])

# The hairline under the header: bright in the middle, fading out before it
# reaches either side, so it reads as light rather than as a drawn border.
func _draw_rule(y: float, flare: float) -> void:
	var x0 := PAD + 2.0
	var x1 := size.x - PAD - 2.0
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var steps := 12
	var base := Color(0.55, 0.68, 1.0, 0.42 + 0.35 * flare)
	for i in range(steps + 1):
		var u := float(i) / float(steps)
		pts.append(Vector2(lerpf(x0, x1, u), y))
		cols.append(Color(base.r, base.g, base.b, base.a * sin(PI * u)))
	draw_polyline_colors(pts, cols, 1.0, true)

func _draw_caption(flare: float) -> void:
	var f := get_theme_font("font", "Label")
	if f == null:
		f = ThemeDB.fallback_font
	if f == null:
		return
	var w := 0.0
	var adv: Array[float] = []
	for i in CAP_TEXT.length():
		var a := f.get_string_size(CAP_TEXT[i], HORIZONTAL_ALIGNMENT_LEFT, -1, CAP_SIZE).x
		adv.append(a)
		w += a + (CAP_TRACK if i < CAP_TEXT.length() - 1 else 0.0)
	var x := (size.x - w) * 0.5
	var col := CAP_COLOR.lerp(Color(1, 1, 1), 0.7 * flare)
	for i in CAP_TEXT.length():
		var p := Vector2(x, CAP_BASELINE)
		f.draw_char(get_canvas_item(), p + Vector2(0, 1), CAP_TEXT.unicode_at(i),
			CAP_SIZE, Color(0.0, 0.02, 0.08, 0.55))
		f.draw_char(get_canvas_item(), p, CAP_TEXT.unicode_at(i), CAP_SIZE, col)
		x += adv[i] + CAP_TRACK

func _draw_accent(breath: float, flare: float) -> void:
	var w := BAR_W + 26.0 * flare
	var x0 := (size.x - w) * 0.5
	var r := Rect2(x0, BAR_Y, w, BAR_H)
	var a_col := ACCENT_A.lerp(Color(1, 1, 1), 0.6 * flare)
	var b_col := ACCENT_B.lerp(Color(1, 1, 1), 0.6 * flare)
	# The bar sits in its own bloom, which carries the same cyan-to-violet ramp so
	# the light around it is the light coming out of it.
	var rad := r.size.y * 0.5
	var a := (0.34 + 0.10 * breath + 0.9 * flare)
	_feather(r, rad, rad, 7.0 + 9.0 * flare, Vector2.ZERO,
		Color(a_col.r, a_col.g, a_col.b, a), Color(b_col.r, b_col.g, b_col.b, a))
	var core := _rr(r, rad, rad)
	draw_polygon(core, _grad_x(core, r.position.x, r.end.x, a_col, b_col))

func _grad_x(pts: PackedVector2Array, x0: float, x1: float, c0: Color,
		c1: Color) -> PackedColorArray:
	var cols := PackedColorArray()
	var span := maxf(x1 - x0, 0.001)
	for p: Vector2 in pts:
		cols.append(c0.lerp(c1, clampf((p.x - x0) / span, 0.0, 1.0)))
	return cols
