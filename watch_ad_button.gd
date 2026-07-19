extends Button
# A physical, glossy hard-plastic push-button in a wide pill / "balloon" shape:
# a deep amber convex dome lit from the top-left, with real thickness, a floating
# contact shadow and bold white text. Entirely _draw()-based so we get smooth
# directional shading (no border / frame / rim / glow chrome a StyleBox would add).
# Depth comes only from gradients + shading. Reacts to the button's draw mode so
# pressing physically sinks and flattens it.
#
# `glow` (0..1) drives a soft amber halo radiating AROUND the pill for the idle
# attention animation — the button body itself never moves or scales; only the
# halo breathes. game.gd tweens this property.

# Deep golden / dark-amber body — rich and tactile, not bright yellow. Lighting
# is soft polished-plastic reflection, not a wet-glass white shine.
const FACE_TOP    := Color(0.72, 0.47, 0.07)   # lit upper crown
const FACE_BOTTOM := Color(0.34, 0.19, 0.015)  # shaded lower face
const WALL_COL    := Color(0.24, 0.125, 0.01)  # the button body / thickness
const REFLECT_COL := Color(1.0, 0.86, 0.55)    # subtle ambient plastic sheen
const GLOW_COL    := Color(0.98, 0.66, 0.16)    # halo matches the amber body
const TEXT_COL    := Color(0.99, 0.98, 0.96)

const FS := 17
const PAD := 30.0

var glow: float = 0.0:
	set(v):
		glow = v
		queue_redraw()

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
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)

# Fill a horizontal stadium (pill) covering rect(pos, sz): a middle band plus two
# rounded end-caps. Caps are antialiased for a clean silhouette.
func _fill_pill(pos: Vector2, sz: Vector2, col: Color, aa := false) -> void:
	if sz.x <= 0 or sz.y <= 0:
		return
	var rad: float = min(sz.x, sz.y) * 0.5
	draw_rect(Rect2(pos.x + rad, pos.y, max(0.0, sz.x - 2.0 * rad), sz.y), col)
	draw_circle(Vector2(pos.x + rad, pos.y + rad), rad, col, true, -1.0, aa)
	draw_circle(Vector2(pos.x + sz.x - rad, pos.y + rad), rad, col, true, -1.0, aa)

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

	# 0) Idle attention glow — a soft amber halo radiating around the pill. Several
	#    translucent, progressively larger pills build a smooth radial falloff. The
	#    body never moves; only this breathes (driven by `glow`).
	if glow > 0.001:
		for i in range(14):
			var t := float(i) / 13.0
			var grow := 2.0 + t * 26.0
			var a := glow * 0.11 * pow(1.0 - t, 1.7)
			_fill_pill(base_pos - Vector2(grow, grow),
				Vector2(w + grow * 2.0, h + grow * 2.0),
				Color(GLOW_COL.r, GLOW_COL.g, GLOW_COL.b, a), true)

	# 1) Soft contact shadow — shorter/tighter when pressed.
	var sh_dy := 3.0 if pressed else 7.0
	for i in range(7):
		var t := float(i) / 6.0
		var grow := t * (2.0 if pressed else 5.0)
		_fill_pill(base_pos + Vector2(-grow, sh_dy - grow * 0.3),
			Vector2(w + grow * 2.0, h + grow * 2.0),
			Color(0, 0, 0, 0.05), true)

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
	_fill_pill(base_pos + Vector2(w * 0.10, h * 0.14),
		Vector2(w * 0.80, h * 0.30),
		Color(REFLECT_COL.r, REFLECT_COL.g, REFLECT_COL.b, refl), true)
	_fill_pill(base_pos + Vector2(w * 0.22, h * 0.60),
		Vector2(w * 0.56, h * 0.20),
		Color(REFLECT_COL.r, REFLECT_COL.g, REFLECT_COL.b, refl * 0.5), true)

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
