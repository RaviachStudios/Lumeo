extends Button
# A premium, glossy 3D pill for confirmation dialogs. A raised rounded slab with a
# darker base edge under it (real thickness), a soft cast shadow, a top gloss sheen
# and a light inner rim — pressing physically sinks the face onto its base. Carries
# an embossed icon (a check ✓ or a cross ✕) beside its label. Fully _draw()-based so
# the shading and depth read richer than a StyleBoxFlat can.

var base_color: Color = Color(0.2, 0.5, 0.25)
var icon_kind: String = "check"   # "check" or "cross"
var label_text: String = ""
var font_size: int = 18

func setup(col: Color, kind: String, txt: String) -> void:
	base_color = col
	icon_kind = kind
	label_text = txt
	text = ""
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(st, empty)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)
	queue_redraw()

func _rrect(rect: Rect2, col: Color, radius: float, shadow: float = 0.0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.anti_aliasing = true
	if shadow > 0.0:
		sb.shadow_size = int(shadow)
		sb.shadow_color = Color(0, 0, 0, 0.38)
		sb.shadow_offset = Vector2(0, 5)
	sb.draw(get_canvas_item(), rect)

func _draw() -> void:
	var mode := get_draw_mode()
	var pressed := mode == DRAW_PRESSED
	var hover := mode == DRAW_HOVER or mode == DRAW_HOVER_PRESSED

	var w := size.x
	var h := size.y
	var radius := h * 0.32
	var bevel := 6.0                                   # raised thickness of the slab
	var col := base_color.lightened(0.07) if hover else base_color

	# How far the face drops toward its base. Pressed → nearly flush (sunken).
	var face_top := (bevel - 2.0) if pressed else 0.0
	var face_h := h - bevel

	# 1) Base / raised side edge (darker), full height — its lower crescent shows as
	#    the button's thickness. Carries the soft cast shadow.
	_rrect(Rect2(0, 0, w, h), base_color.darkened(0.5), radius, 6.0)

	# 2) Main convex face, sitting above the base.
	var face_rect := Rect2(0, face_top, w, face_h)
	_rrect(face_rect, col, radius)

	# 3) Vertical gradient — a few darkening bands from top to bottom sell the curve.
	for i in range(4):
		var t := float(i) / 3.0
		var band := Rect2(0, face_top + face_h * (0.35 + t * 0.16), w, face_h * 0.22)
		_rrect(band, Color(0, 0, 0, 0.05), radius * 0.7)

	# 4) Glossy sheen across the top half — brighter thin cap, softer body.
	_rrect(Rect2(4, face_top + 3, w - 8, face_h * 0.44), Color(1, 1, 1, 0.13), radius * 0.7)
	_rrect(Rect2(5, face_top + 3, w - 10, face_h * 0.16), Color(1, 1, 1, 0.16), radius * 0.6)

	# 5) Icon + label, embossed and centred as a group.
	var font := get_theme_default_font()
	var icon_sz := face_h * 0.40
	var gap := 12.0
	var text_sz := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var group_w := icon_sz + gap + text_sz.x
	var start_x := (w - group_w) * 0.5
	var cy := face_top + face_h * 0.5

	_draw_icon(Vector2(start_x + icon_sz * 0.5, cy), icon_sz * 0.5)

	var baseline := cy + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	var tx := start_x + icon_sz + gap
	# soft drop shadow under the text, then the white face.
	draw_string(font, Vector2(tx, baseline + 1.5), label_text, HORIZONTAL_ALIGNMENT_LEFT,
		-1, font_size, Color(0, 0, 0, 0.35))
	draw_string(font, Vector2(tx, baseline), label_text, HORIZONTAL_ALIGNMENT_LEFT,
		-1, font_size, Color.WHITE)

func _draw_icon(c: Vector2, r: float) -> void:
	var wln := r * 0.42
	var shadow := Color(0, 0, 0, 0.35)
	if icon_kind == "check":
		var a := c + Vector2(-r * 0.85, r * 0.05)
		var b := c + Vector2(-r * 0.20, r * 0.72)
		var d := c + Vector2(r * 0.95, -r * 0.75)
		draw_polyline([a + Vector2(0, 1.6), b + Vector2(0, 1.6), d + Vector2(0, 1.6)], shadow, wln, true)
		draw_polyline([a, b, d], Color.WHITE, wln, true)
		for p in [a, b, d]:
			draw_circle(p, wln * 0.5, Color.WHITE)
	else:
		var s := r * 0.78
		var p1 := c + Vector2(-s, -s)
		var p2 := c + Vector2(s, s)
		var q1 := c + Vector2(s, -s)
		var q2 := c + Vector2(-s, s)
		draw_line(p1 + Vector2(0, 1.6), p2 + Vector2(0, 1.6), shadow, wln, true)
		draw_line(q1 + Vector2(0, 1.6), q2 + Vector2(0, 1.6), shadow, wln, true)
		draw_line(p1, p2, Color.WHITE, wln, true)
		draw_line(q1, q2, Color.WHITE, wln, true)
		for p in [p1, p2, q1, q2]:
			draw_circle(p, wln * 0.5, Color.WHITE)
