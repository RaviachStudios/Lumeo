extends Button
# A physical, glossy hard-plastic push button: a deep-red convex dome with a
# top-left light source, a raised embossed white ✕, a floating cast shadow and a
# bottom inner shadow that sells the curved volume. Purely _draw()-based so we get
# smooth directional shading a StyleBoxFlat can't produce. Same square footprint,
# circular face and white ✕ as before — just given real depth. Reacts to the
# button's draw mode (normal / hover / pressed) so pressing physically sinks it.

# Deep, rich reds (much darker than the old bright 0.88/0.20/0.20).
const FACE_CENTER := Color(0.78, 0.12, 0.12)   # lit crown of the dome
const FACE_RIM    := Color(0.40, 0.035, 0.05)  # shaded outer edge of the face
const WALL_COL    := Color(0.26, 0.02, 0.03)   # the button's side / thickness
const X_COL       := Color(0.97, 0.97, 0.98)

func _ready() -> void:
	# We render everything ourselves — strip the button's own chrome + glyph.
	text = ""
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(st, empty)
	# Redraw whenever the visual state changes so the dome animates on press/hover.
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)

func _draw() -> void:
	var mode := get_draw_mode()
	var pressed := mode == DRAW_PRESSED
	var hover := mode == DRAW_HOVER_PRESSED or mode == DRAW_HOVER

	var R := size.x * 0.5
	var c := size * 0.5
	# Pressed → the whole button drops a couple px into its own shadow.
	if pressed:
		c += Vector2(0, 2.0)

	var wall_h := 2.0 if pressed else 5.0          # exposed side height = thickness
	var lit := 0.06 if hover else 0.0              # faint brighten on hover
	var dark := 0.90 if pressed else 1.0           # slightly darker when pushed

	var face_center := (FACE_CENTER.lightened(lit) * Color(dark, dark, dark, 1)).clamp()
	var face_rim := (FACE_RIM * Color(dark, dark, dark, 1)).clamp()

	# 1) Soft floating cast shadow — shorter/tighter when pressed.
	var sh_dy := 3.0 if pressed else 8.0
	var sh_r := R * (1.0 if pressed else 1.06)
	for i in range(9):
		var t := float(i) / 8.0
		draw_circle(c + Vector2(0, sh_dy * (1.0 - t * 0.35)),
			sh_r * (1.0 - t * 0.06), Color(0, 0, 0, 0.055))

	# 2) The button body / side wall, offset down so its bottom crescent reads as
	#    the raised edge (real thickness under the face).
	draw_circle(c + Vector2(0, wall_h), R, (WALL_COL * Color(dark, dark, dark, 1)).clamp())

	# 3) Convex dome face. Concentric rings whose centres drift toward the top-left
	#    light as they shrink → the bright crown lands top-left and the rim stays
	#    darkest at the bottom-right, giving the curved, lit-from-above surface.
	var light := c + Vector2(-R * 0.30, -R * 0.32)
	var steps := 56
	for i in range(steps):
		var t := float(i) / float(steps - 1)          # 0 = outer rim … 1 = crown
		var rr := R * (1.0 - t)
		var col := face_rim.lerp(face_center, ease(t, 0.55))
		draw_circle(c.lerp(light, t * 0.55), rr, col)

	# 4) Bottom inner shadow — a dark arc hugging the lower inner rim to deepen the
	#    dome's curl. (Godot angles: 0 = right, +PI/2 = down.)
	draw_arc(c, R * 0.86, PI * 0.12, PI * 0.88, 32,
		Color(0.10, 0.005, 0.01, 0.45), R * 0.16, true)

	# (No top-left specular shine — the dome shading alone carries the volume.)

	# 7) Embossed white ✕ — bold, centred, with a bevel: dark drop under, white
	#    face, faint top-left catch-light so the glyph itself feels raised.
	var a := R * 0.34
	var p1 := c + Vector2(-a, -a)
	var p2 := c + Vector2(a, a)
	var q1 := c + Vector2(a, -a)
	var q2 := c + Vector2(-a, a)
	var w := R * 0.19
	var x_col := X_COL.darkened(0.06) if pressed else X_COL
	# bevel shadow
	draw_line(p1 + Vector2(0, 1.4), p2 + Vector2(0, 1.4), Color(0, 0, 0, 0.28), w, true)
	draw_line(q1 + Vector2(0, 1.4), q2 + Vector2(0, 1.4), Color(0, 0, 0, 0.28), w, true)
	# main strokes
	draw_line(p1, p2, x_col, w, true)
	draw_line(q1, q2, x_col, w, true)
	# top-left catch-light on the glyph
	draw_line(p1 - Vector2(0, 1.0), p2 - Vector2(0, 1.0), Color(1, 1, 1, 0.30), w * 0.4, true)
	draw_line(q1 - Vector2(0, 1.0), q2 - Vector2(0, 1.0), Color(1, 1, 1, 0.30), w * 0.4, true)
	# round the stroke ends so the ✕ tips aren't chopped flat
	for p in [p1, p2, q1, q2]:
		draw_circle(p, w * 0.5, x_col)
