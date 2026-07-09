extends RefCounted

# Referenced by the Arena screens via `preload("res://arena_ui.gd")` (not a
# global class_name), so it never depends on the editor's global-class scan.

# Shared chrome for the Arena screens (hub / create / detail). Theme: THE
# COLOSSEUM — a grand amphitheatre under a starlit night. Sandstone + torch amber
# + gold over a deep indigo sky. Three background "modes" reskin the same stone
# world per screen:
#   "hub"    — tiered seating rings receding to the rim, torches, a sandy floor.
#   "lobby"  — an enclosing torch-lit staging tunnel (dark archway frame, warm).
#   "active" — the roaring floor: brighter stands + a strong combat-floor glow.
# Detail on the top/bottom bands only; the centre is kept clear for the widgets
# (Simon's wheel/carousel sits there). Pure helpers — no state.

# ---- palette (warm stone / torchlight / gold) ----
const ACCENT := Color(0.95, 0.66, 0.28)          # torch gold (buttons, rims)
const TEXT := Color(0.98, 0.94, 0.86)            # warm parchment white
const MUTED := Color(0.80, 0.72, 0.58)           # dim sandstone
const GOLD := Color(1.0, 0.85, 0.2)              # medals / champions
const SAND := Color(0.86, 0.68, 0.38)            # plaques / stone faces
const TORCH := Color(1.0, 0.55, 0.18)            # flame

const BG_SHADER := "
shader_type canvas_item;
uniform float aspect = 1.7;
uniform float warm = 0.0;      // extra amber wash (lobby)
uniform float enclose = 0.0;   // dark archway framing (lobby)
uniform float floor_glow = 1.0;// combat-floor intensity (active pushes this up)
uniform float stands = 1.0;    // seating-ring intensity
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec2 uv = UV;
	// vertical gradient: deep night sky -> blue stone -> deep-blue floor. Kept in the
	// game's cool indigo family (the golden torches / spotlights below stay warm).
	vec3 night = vec3(0.020, 0.028, 0.090);
	vec3 stone = vec3(0.070, 0.085, 0.200);
	vec3 sand  = vec3(0.090, 0.110, 0.250);
	vec3 col = mix(night, stone, smoothstep(0.0, 0.55, uv.y));
	col = mix(col, sand, smoothstep(0.58, 1.0, uv.y));

	vec2 p = (uv - vec2(0.5, 0.5)) * vec2(aspect, 1.0);

	// tiered seating rings: concentric arcs from a vanishing point above screen,
	// only painted into the top band so the centre stays clean.
	vec2 vp = vec2(0.5 * aspect, -0.12);
	float d = distance(vec2(uv.x * aspect, uv.y), vp);
	float rings = smoothstep(0.55, 1.0, 0.5 + 0.5 * sin(d * 44.0));
	float topband = smoothstep(0.58, 0.0, uv.y);
	col += vec3(0.10, 0.13, 0.26) * rings * topband * 0.7 * stands;
	col += vec3(0.05, 0.07, 0.16) * topband * 0.28;

	// torches: warm flickering glows along the rim (top band)
	float f1 = 0.72 + 0.28 * sin(TIME * 7.0);
	float f2 = 0.72 + 0.28 * sin(TIME * 9.0 + 1.7);
	col += vec3(1.0, 0.52, 0.16) * smoothstep(0.17, 0.0, distance(uv, vec2(0.12, 0.20))) * 0.55 * f1;
	col += vec3(1.0, 0.52, 0.16) * smoothstep(0.17, 0.0, distance(uv, vec2(0.88, 0.19))) * 0.55 * f2;
	col += vec3(1.0, 0.56, 0.20) * smoothstep(0.13, 0.0, distance(uv, vec2(0.30, 0.11))) * 0.35 * f2;
	col += vec3(1.0, 0.56, 0.20) * smoothstep(0.13, 0.0, distance(uv, vec2(0.70, 0.12))) * 0.35 * f1;

	// combat-floor glow (bottom band) — cool blue wash, warmed by a hint of gold
	float botband = smoothstep(0.62, 1.0, uv.y);
	col += vec3(0.16, 0.24, 0.48) * botband * 0.38 * floor_glow;
	col += vec3(0.22, 0.15, 0.06) * botband * 0.12 * floor_glow;

	// stars in the strip above the rim
	vec2 g = floor(uv * vec2(88.0 * aspect, 88.0));
	float h = hash(g);
	col += vec3(0.90, 0.92, 1.0) * smoothstep(0.992, 1.0, h) * smoothstep(0.34, 0.0, uv.y) * 0.8;

	// lobby: enclose the scene in a dark stone archway + a warm interior wash
	float arch = smoothstep(0.42, 0.58, distance(p * vec2(1.0, 1.22), vec2(0.0, -0.04)));
	col = mix(col, col * 0.22, arch * enclose);
	col += vec3(0.20, 0.11, 0.04) * (1.0 - arch) * enclose * 0.5;
	col += vec3(0.16, 0.08, 0.02) * warm;

	// keep the centre readable, edges vignetted
	col *= mix(0.84, 1.0, smoothstep(0.0, 0.6, length(p)));
	col *= mix(0.58, 1.0, smoothstep(1.2, 0.3, length(p)));
	COLOR = vec4(col, 1.0);
}
"

# The contest LOBBY has its own world — the CHAMPIONS' ANTECHAMBER: a cool regal
# hall (teal→violet), gold-trimmed banner drapes down the sides, an overhead halo
# of light on the roster, gold motes above and a polished marble floor below. Kept
# deliberately distinct from the warm amphitheatre so the lobby reads as its own room.
const LOBBY_SHADER := "
shader_type canvas_item;
uniform float aspect = 1.7;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec2 uv = UV;
	vec3 top = vec3(0.05, 0.10, 0.17);
	vec3 mid = vec3(0.14, 0.09, 0.25);
	vec3 flr = vec3(0.05, 0.05, 0.12);
	vec3 col = mix(top, mid, smoothstep(0.0, 0.55, uv.y));
	col = mix(col, flr, smoothstep(0.60, 1.0, uv.y));

	vec2 p = (uv - vec2(0.5, 0.5)) * vec2(aspect, 1.0);

	// overhead halo of light (upper band; centre stays readable)
	float halo = smoothstep(0.60, 0.0, distance(vec2(uv.x, uv.y * 1.25), vec2(0.5, 0.10)));
	col += vec3(0.30, 0.34, 0.58) * halo * 0.55;

	// gold-trimmed banner drapes down the left and right edges
	float band = max(smoothstep(0.11, 0.06, uv.x), smoothstep(0.89, 0.94, uv.x));
	col = mix(col, vec3(0.24, 0.10, 0.16), band * 0.6);
	col += vec3(0.05, 0.02, 0.03) * band * (0.5 + 0.5 * sin(uv.y * 60.0));   // pleats
	col += vec3(1.0, 0.82, 0.35) * smoothstep(0.006, 0.0, abs(uv.x - 0.10)) * 0.55;
	col += vec3(1.0, 0.82, 0.35) * smoothstep(0.006, 0.0, abs(uv.x - 0.90)) * 0.55;

	// slow gold motes in the upper band — each softly fades in then straight back
	// out (a gentle twinkle), and only re-picks a spot while fully invisible, so a
	// mote never pops from one place to another.
	float gs = 40.0;
	vec2 gc = uv * vec2(gs * aspect, gs);
	vec2 cell = floor(gc);
	float spd = 0.18 + 0.10 * hash(cell + 7.31);            // slow, per-cell pace
	float mt = TIME * spd + hash(cell) * 20.0;              // desynced cell clock
	float active = step(0.86, hash(cell + floor(mt) * 1.31)); // sparse; re-rolled per cycle at env==0
	float env = 0.5 - 0.5 * cos(fract(mt) * 6.2831);        // 0 -> 1 -> 0: fade in, fade out
	vec2 f = fract(gc) - 0.5;
	float mdot = smoothstep(0.45, 0.0, length(f));          // soft round dot, no square edges
	col += vec3(1.0, 0.85, 0.42) * active * env * mdot * smoothstep(0.5, 0.0, uv.y) * 0.9;

	// polished marble floor: soft sheen + a wash of the halo colour reflected up
	float floorb = smoothstep(0.72, 1.0, uv.y);
	col += vec3(0.16, 0.15, 0.26) * floorb * (0.4 + 0.35 * sin(uv.x * 34.0));
	col += vec3(0.30, 0.30, 0.52) * halo * floorb * 0.35;

	col *= mix(0.55, 1.0, smoothstep(1.2, 0.2, length(p)));                  // vignette
	COLOR = vec4(col, 1.0);
}
"

# The lobby's distinct background (see LOBBY_SHADER). Sized via size_bg() like the rest.
static func make_lobby_bg() -> ColorRect:
	var bg := ColorRect.new()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.color = Color(0.05, 0.05, 0.12)
	var sh := Shader.new()
	sh.code = LOBBY_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	bg.material = mat
	return bg

# A full-screen shader background for the given mode. The host sizes it (CanvasLayer
# children get no anchored size) via size_bg() in its _layout.
static func make_bg(mode: String = "hub") -> ColorRect:
	var bg := ColorRect.new()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.color = Color(0.03, 0.03, 0.09)
	var sh := Shader.new()
	sh.code = BG_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	match mode:
		"lobby":
			mat.set_shader_parameter("warm", 1.0)
			mat.set_shader_parameter("enclose", 1.0)
			mat.set_shader_parameter("floor_glow", 0.7)
			mat.set_shader_parameter("stands", 0.5)
		"active":
			mat.set_shader_parameter("warm", 0.25)
			mat.set_shader_parameter("enclose", 0.0)
			mat.set_shader_parameter("floor_glow", 1.5)
			mat.set_shader_parameter("stands", 1.25)
		_:
			mat.set_shader_parameter("warm", 0.0)
			mat.set_shader_parameter("enclose", 0.0)
			mat.set_shader_parameter("floor_glow", 1.0)
			mat.set_shader_parameter("stands", 1.0)
	bg.material = mat
	return bg

# Retune an existing bg to a different mode (the detail screen swaps between
# lobby / active / finished without rebuilding the ColorRect).
static func set_bg_mode(bg: ColorRect, mode: String) -> void:
	if bg == null:
		return
	var mat := bg.material as ShaderMaterial
	if mat == null:
		return
	match mode:
		"lobby":
			mat.set_shader_parameter("warm", 1.0)
			mat.set_shader_parameter("enclose", 1.0)
			mat.set_shader_parameter("floor_glow", 0.7)
			mat.set_shader_parameter("stands", 0.5)
		"active":
			mat.set_shader_parameter("warm", 0.25)
			mat.set_shader_parameter("enclose", 0.0)
			mat.set_shader_parameter("floor_glow", 1.5)
			mat.set_shader_parameter("stands", 1.25)
		_:
			mat.set_shader_parameter("warm", 0.1)
			mat.set_shader_parameter("enclose", 0.0)
			mat.set_shader_parameter("floor_glow", 1.0)
			mat.set_shader_parameter("stands", 1.0)

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
	s.bg_color = Color(0.16, 0.10, 0.06, 0.78)
	s.set_corner_radius_all(23)
	s.border_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.55)
	s.set_border_width_all(1)
	s.shadow_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.25)
	s.shadow_size = 10
	b.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = Color(0.24, 0.15, 0.08, 0.9)
	b.add_theme_stylebox_override("hover", sh)
	var sp := s.duplicate() as StyleBoxFlat
	sp.bg_color = Color(0.11, 0.07, 0.04, 0.92)
	b.add_theme_stylebox_override("pressed", sp)
	b.add_theme_color_override("font_color", TEXT)
	return b

# A translucent stone/glass panel, gold-rimmed.
static func glass_panel(accent: Color = ACCENT) -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.04, 0.03, 0.02, 0.58)
	s.set_corner_radius_all(20)
	s.border_color = Color(accent.r, accent.g, accent.b, 0.45)
	s.set_border_width_all(1)
	s.shadow_color = Color(accent.r, accent.g, accent.b, 0.18)
	s.shadow_size = 16
	p.add_theme_stylebox_override("panel", s)
	return p

# A carved-sandstone panel (used for plaques / the contest carousel card).
static func stone_panel(accent: Color = ACCENT) -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.16, 0.12, 0.09, 0.92)
	s.set_corner_radius_all(18)
	s.border_color = Color(accent.r, accent.g, accent.b, 0.85)
	s.set_border_width_all(2)
	s.shadow_color = Color(accent.r, accent.g, accent.b, 0.35)
	s.shadow_size = 18
	p.add_theme_stylebox_override("panel", s)
	return p

# A glowing, glossy pill button. `primary` brightens the fill/rim and adds a
# stronger glow. A translucent top "sheen" child gives it a fancier, glassy read.
static func pill_button(text: String, accent: Color, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.10, 0.7))
	b.add_theme_constant_override("outline_size", 1)          # crisp faux-bold label
	var body := Color(accent.r, accent.g, accent.b, 0.34 if primary else 0.16)
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.10, 0.09, 0.16, 0.90).lerp(body, 0.62)
	s.set_corner_radius_all(28)
	s.corner_detail = 8
	s.border_color = accent.lightened(0.15) if primary else Color(accent.r, accent.g, accent.b, 0.6)
	s.set_border_width_all(2 if primary else 1)
	s.shadow_color = Color(accent.r, accent.g, accent.b, 0.5 if primary else 0.24)
	s.shadow_size = 18 if primary else 10
	s.content_margin_left = 16
	s.content_margin_right = 16
	b.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = s.bg_color.lightened(0.12)
	sh.shadow_size = s.shadow_size + 4
	b.add_theme_stylebox_override("hover", sh)
	var sp := s.duplicate() as StyleBoxFlat
	sp.bg_color = s.bg_color.darkened(0.14)
	b.add_theme_stylebox_override("pressed", sp)
	var sd := s.duplicate() as StyleBoxFlat
	sd.bg_color = Color(0.10, 0.09, 0.12, 0.5)
	sd.border_color = Color(accent.r, accent.g, accent.b, 0.25)
	sd.shadow_size = 0
	b.add_theme_stylebox_override("disabled", sd)
	b.add_theme_color_override("font_color", accent.lightened(0.55) if primary else TEXT)
	b.add_theme_color_override("font_disabled_color", MUTED.darkened(0.2))

	# Glossy top sheen — a soft translucent highlight over the upper half.
	var sheen := Panel.new()
	sheen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheen.set_anchors_preset(Control.PRESET_TOP_WIDE)
	sheen.anchor_bottom = 0.52
	sheen.offset_left = 5
	sheen.offset_right = -5
	sheen.offset_top = 4
	sheen.offset_bottom = 0
	var ss := StyleBoxFlat.new()
	ss.bg_color = Color(1.0, 1.0, 1.0, 0.10 if primary else 0.06)
	ss.set_corner_radius_all(22)
	sheen.add_theme_stylebox_override("panel", ss)
	sheen.z_index = 1
	b.add_child(sheen)
	return b

# A small status pill (label with a tinted rounded background). Returns a Panel
# holding a centered Label; the host positions it.
static func status_pill(text: String, accent: Color, w: float, h: float) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(w, h)
	p.size = Vector2(w, h)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := StyleBoxFlat.new()
	s.bg_color = Color(accent.r, accent.g, accent.b, 0.20)
	s.set_corner_radius_all(int(h * 0.5))
	s.border_color = Color(accent.r, accent.g, accent.b, 0.85)
	s.set_border_width_all(1)
	p.add_theme_stylebox_override("panel", s)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", int(h * 0.42))
	l.add_theme_color_override("font_color", accent.lightened(0.4))
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return p

static func status_accent(status: String) -> Color:
	match status:
		"lobby":    return SAND
		"active":   return TORCH
		"finished": return GOLD
	return MUTED

static func status_text(status: String) -> String:
	match status:
		"lobby":    return "OPEN LOBBY"
		"active":   return "LIVE NOW"
		"finished": return "FINISHED"
	return status.to_upper()

# A centered screen title with a soft glow.
static func title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 40)
	l.add_theme_color_override("font_color", Color(1.0, 0.96, 0.86))
	l.add_theme_color_override("font_shadow_color", Color(0.9, 0.5, 0.15, 0.5))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.add_theme_constant_override("shadow_outline_size", 10)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# A big carved-gold contest title (the champion's headline). Clamped by the caller
# to the 15-char display limit.
static func big_title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 52)
	l.add_theme_color_override("font_color", GOLD.lightened(0.15))
	l.add_theme_color_override("font_outline_color", Color(0.28, 0.16, 0.03))
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_shadow_color", Color(1.0, 0.6, 0.2, 0.45))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.add_theme_constant_override("shadow_outline_size", 12)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# Clamp a contest title to the shared display limit (used everywhere it's shown).
const TITLE_MAX := 15
static func clamp_title(t: String, fallback: String = "Contest") -> String:
	var s := t.strip_edges()
	if s.is_empty():
		return fallback
	if s.length() > TITLE_MAX:
		s = s.substr(0, TITLE_MAX)
	return s

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
