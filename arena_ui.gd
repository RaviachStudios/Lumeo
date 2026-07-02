extends RefCounted

# Referenced by the Arena screens via `preload("res://arena_ui.gd")` (not a
# global class_name), so it never depends on the editor's global-class scan.

# Shared chrome for the Arena screens (hub / create / detail) so they match each
# other and the rest of the app (deep-space sky, violet glassmorphism, glowing
# pill buttons). Pure helpers — no state.

const BG_SHADER := "
shader_type canvas_item;
uniform float aspect = 0.5;
float star(vec2 uv, vec2 c, float r) { return smoothstep(r, 0.0, distance(uv, c)); }
void fragment() {
	vec2 uv = UV;
	vec3 top = vec3(0.010, 0.020, 0.090);
	vec3 bot = vec3(0.075, 0.010, 0.150);
	vec3 col = mix(top, bot, uv.y);
	vec2 p = (uv - vec2(0.5)) * vec2(aspect, 1.0);
	col += vec3(0.16, 0.10, 0.40) * smoothstep(0.5, 0.0, distance(uv, vec2(0.0, 0.35))) * 0.28;
	col += vec3(0.40, 0.14, 0.42) * smoothstep(0.5, 0.0, distance(uv, vec2(1.0, 0.6))) * 0.20;
	float breathe = 0.85 + 0.15 * sin(TIME * 0.6);
	col += vec3(0.14, 0.12, 0.44) * smoothstep(0.55, 0.0, length(p)) * 0.16 * breathe;
	col += vec3(0.8, 0.85, 1.0) * star(uv, vec2(0.16, 0.22), 0.010) * 0.55;
	col += vec3(0.8, 0.85, 1.0) * star(uv, vec2(0.84, 0.18), 0.008) * 0.45;
	col += vec3(0.9, 0.8, 1.0) * star(uv, vec2(0.72, 0.80), 0.009) * 0.45;
	col *= mix(0.62, 1.0, smoothstep(1.1, 0.25, length(p)));
	COLOR = vec4(col, 1.0);
}
"

const ACCENT := Color(0.62, 0.42, 1.00)          # arena violet
const TEXT := Color(0.90, 0.92, 1.00)
const MUTED := Color(0.66, 0.71, 0.92)
const GOLD := Color(1.0, 0.85, 0.2)

# A full-screen shader background. The host sizes it (CanvasLayer children get no
# anchored size) via size_bg() in its _layout.
static func make_bg() -> ColorRect:
	var bg := ColorRect.new()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.color = Color(0.02, 0.03, 0.09)
	var sh := Shader.new()
	sh.code = BG_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	bg.material = mat
	return bg

static func size_bg(bg: ColorRect, size: Vector2) -> void:
	if bg == null:
		return
	bg.position = Vector2.ZERO
	bg.size = size
	var mat := bg.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("aspect", size.x / maxf(1.0, size.y))

static func make_back_button() -> Button:
	var b := Button.new()
	b.text = "← Back"
	b.size = Vector2(132, 46)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 18)
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.07, 0.10, 0.26, 0.7)
	s.set_corner_radius_all(23)
	s.border_color = Color(0.45, 0.4, 1.0, 0.5)
	s.set_border_width_all(1)
	s.shadow_color = Color(0.35, 0.3, 1.0, 0.25)
	s.shadow_size = 10
	b.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = Color(0.12, 0.14, 0.36, 0.85)
	b.add_theme_stylebox_override("hover", sh)
	var sp := s.duplicate() as StyleBoxFlat
	sp.bg_color = Color(0.05, 0.06, 0.20, 0.9)
	b.add_theme_stylebox_override("pressed", sp)
	b.add_theme_color_override("font_color", TEXT)
	return b

# A translucent violet glass panel.
static func glass_panel(accent: Color = ACCENT) -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	s.set_corner_radius_all(20)
	s.border_color = Color(accent.r, accent.g, accent.b, 0.4)
	s.set_border_width_all(1)
	s.shadow_color = Color(accent.r, accent.g, accent.b, 0.18)
	s.shadow_size = 16
	p.add_theme_stylebox_override("panel", s)
	return p

# A glowing pill button. `primary` brightens the fill/rim.
static func pill_button(text: String, accent: Color, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 20)
	var body := Color(accent.r, accent.g, accent.b, 0.24 if primary else 0.12)
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.07, 0.18, 0.85).lerp(body, 0.6)
	s.set_corner_radius_all(26)
	s.border_color = Color(accent.r, accent.g, accent.b, 0.95 if primary else 0.5)
	s.set_border_width_all(2 if primary else 1)
	s.shadow_color = Color(accent.r, accent.g, accent.b, 0.45 if primary else 0.22)
	s.shadow_size = 14 if primary else 9
	s.content_margin_left = 14
	s.content_margin_right = 14
	b.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = s.bg_color.lightened(0.10)
	b.add_theme_stylebox_override("hover", sh)
	var sp := s.duplicate() as StyleBoxFlat
	sp.bg_color = s.bg_color.darkened(0.12)
	b.add_theme_stylebox_override("pressed", sp)
	var sd := s.duplicate() as StyleBoxFlat
	sd.bg_color = Color(0.06, 0.07, 0.16, 0.5)
	sd.border_color = Color(accent.r, accent.g, accent.b, 0.25)
	b.add_theme_stylebox_override("disabled", sd)
	b.add_theme_color_override("font_color", accent.lightened(0.4) if primary else TEXT)
	b.add_theme_color_override("font_disabled_color", MUTED.darkened(0.2))
	return b

# A small status pill (label with a tinted rounded background). Returns a Panel
# holding a centered Label; the host positions it.
static func status_pill(text: String, accent: Color, w: float, h: float) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(w, h)
	p.size = Vector2(w, h)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := StyleBoxFlat.new()
	s.bg_color = Color(accent.r, accent.g, accent.b, 0.18)
	s.set_corner_radius_all(int(h * 0.5))
	s.border_color = Color(accent.r, accent.g, accent.b, 0.8)
	s.set_border_width_all(1)
	p.add_theme_stylebox_override("panel", s)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", int(h * 0.44))
	l.add_theme_color_override("font_color", accent.lightened(0.4))
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return p

static func status_accent(status: String) -> Color:
	match status:
		"lobby":    return Color(0.55, 0.70, 1.00)
		"active":   return Color(0.35, 0.85, 0.55)
		"finished": return GOLD
	return MUTED

static func status_text(status: String) -> String:
	match status:
		"lobby":    return "LOBBY"
		"active":   return "LIVE"
		"finished": return "FINISHED"
	return status.to_upper()

# A centered screen title with a soft glow.
static func title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 40)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_shadow_color", Color(0.45, 0.30, 1.0, 0.5))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.add_theme_constant_override("shadow_outline_size", 10)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# Compact human string for a future unix deadline ("2h 14m left", "Ended").
static func time_left(deadline_at: int) -> String:
	if deadline_at <= 0:
		return ""
	var secs := deadline_at - int(Time.get_unix_time_from_system())
	if secs <= 0:
		return "Ended"
	var d := secs / 86400
	var h := (secs % 86400) / 3600
	var m := (secs % 3600) / 60
	if d > 0:
		return "%dd %dh left" % [d, h]
	if h > 0:
		return "%dh %dm left" % [h, m]
	return "%dm left" % [maxi(1, m)]
