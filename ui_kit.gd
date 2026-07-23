extends RefCounted

# Shared chrome for the non-Arena screens (shop / difficulty / how-to-play /
# leaderboards), which all live in the game's cool deep-space indigo world. Static
# helpers only — no state. (The Arena screens keep their own warm ArenaUI chrome.)
# Referenced via `preload("res://ui_kit.gd")`, so it never depends on the editor's
# global-class scan.

# A raised, glossy "← Back" button — the premium 3D read shared across the main
# screens: a solid navy body, a top-lit blue bevel (brightest along the top edge),
# a cool cast shadow offset DOWN so the pill floats above the surface, a glossy
# top-half sheen, and hover-lift / press-sink feedback. The caller positions it
# (and may resize) and connects `pressed`.
static func back_button() -> Button:
	var b := Button.new()
	b.text = "← Back"
	b.size = Vector2(132, 46)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.10, 0.7))
	b.add_theme_constant_override("outline_size", 2)          # a touch bolder weight
	b.add_theme_color_override("font_color", Color(0.88, 0.92, 1.0))
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.09, 0.12, 0.28, 0.96)                # solid navy → physical read
	s.set_corner_radius_all(23)
	s.corner_detail = 8
	# top-lit bevel: a bright blue rim, brightest along the top edge
	s.border_color = Color(0.45, 0.60, 1.0, 0.65)
	s.border_width_left = 1
	s.border_width_right = 1
	s.border_width_top = 2
	s.border_width_bottom = 1
	# cool-dark cast shadow, offset DOWN → the pill floats above the surface
	s.shadow_color = Color(0.06, 0.10, 0.32, 0.5)
	s.shadow_size = 9
	s.shadow_offset = Vector2(0, 4)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 3
	s.content_margin_bottom = 5
	b.add_theme_stylebox_override("normal", s)
	# Hover: brighter body + the pill lifts higher (bigger, further-offset shadow).
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = Color(0.14, 0.18, 0.38, 0.97)
	sh.shadow_size = 13
	sh.shadow_offset = Vector2(0, 7)
	b.add_theme_stylebox_override("hover", sh)
	# Pressed: darker body + the shadow collapses and the face drops → sinks IN.
	var sp := s.duplicate() as StyleBoxFlat
	sp.bg_color = Color(0.05, 0.07, 0.20, 0.97)
	sp.shadow_size = 3
	sp.shadow_offset = Vector2(0, 1)
	sp.content_margin_top = 5
	sp.content_margin_bottom = 3
	b.add_theme_stylebox_override("pressed", sp)

	# Glossy top dome — a soft cool-white highlight over the upper half; dims while
	# held so the face reads as pressed in.
	var sheen := _add_sheen(b, 23)
	b.button_down.connect(func() -> void: sheen.modulate.a = 0.4)
	b.button_up.connect(func() -> void: sheen.modulate.a = 1.0)
	return b

# A glossy top-half "sheen" highlight over a rounded control so it reads as a
# domed, light-catching surface. Returns the Panel so callers can dim it on press.
static func _add_sheen(host: Control, corner: int) -> Panel:
	var sheen := Panel.new()
	sheen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheen.set_anchors_preset(Control.PRESET_TOP_WIDE)
	sheen.anchor_bottom = 0.5
	sheen.offset_left = 5
	sheen.offset_right = -5
	sheen.offset_top = 3
	sheen.offset_bottom = 0
	var ss := StyleBoxFlat.new()
	ss.bg_color = Color(0.85, 0.92, 1.0, 0.12)
	ss.set_corner_radius_all(maxi(6, corner - 6))
	# ease the lower corners in so it fades to a soft dome, not a hard band
	ss.corner_radius_bottom_left = maxi(4, corner - 14)
	ss.corner_radius_bottom_right = maxi(4, corner - 14)
	sheen.add_theme_stylebox_override("panel", ss)
	sheen.z_index = 1
	host.add_child(sheen)
	return sheen
