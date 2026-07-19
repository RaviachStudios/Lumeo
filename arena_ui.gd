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
const JOIN_BLUE := Color(0.33, 0.52, 0.97)       # royal blue (Join Room card)
const JOIN_CYAN := Color(0.42, 0.86, 0.98)       # cyan glow accent (Join Room card)

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

# Icon-only back control: a round torch-lit stone cap holding just the HEAD of a
# left-pointing arrow (two strokes meeting at a point) — no shaft, no "Back" label.
static func make_back_button() -> Button:
	var b := Button.new()
	b.text = ""
	b.custom_minimum_size = Vector2(46, 46)
	b.size = Vector2(46, 46)
	b.focus_mode = Control.FOCUS_NONE
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.16, 0.10, 0.06, 0.78)
	s.set_corner_radius_all(23)
	s.shadow_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.25)
	s.shadow_size = 10
	b.add_theme_stylebox_override("normal", s)
	# No hover reaction: hovering keeps the resting look (otherwise the default theme's
	# hover stylebox shows through).
	b.add_theme_stylebox_override("hover", s)
	b.add_theme_stylebox_override("focus", s)
	var sp := s.duplicate() as StyleBoxFlat
	sp.bg_color = Color(0.11, 0.07, 0.04, 0.92)
	b.add_theme_stylebox_override("pressed", sp)

	var chevron := Control.new()
	chevron.set_anchors_preset(Control.PRESET_FULL_RECT)
	chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var arm := 9.0
	chevron.draw.connect(func() -> void:
		var c := chevron.size * 0.5
		var apex := c + Vector2(-arm * 0.7, 0.0)
		chevron.draw_line(c + Vector2(arm * 0.55, -arm), apex, TEXT, 3.2, true)
		chevron.draw_line(apex, c + Vector2(arm * 0.55, arm), TEXT, 3.2, true))
	b.add_child(chevron)
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
	# ~17% larger, heavier faux-bold weight, and a soft drop shadow — premium,
	# game-like typography (Clash Royale / Marvel Snap read).
	b.add_theme_font_size_override("font_size", 23)
	b.add_theme_color_override("font_outline_color", Color(0.06, 0.04, 0.02, 0.85))
	b.add_theme_constant_override("outline_size", 3)          # thicker → bolder weight
	b.add_theme_color_override("font_shadow_color", Color(0.04, 0.02, 0.01, 0.55))
	b.add_theme_constant_override("shadow_offset_x", 0)
	b.add_theme_constant_override("shadow_offset_y", 2)
	b.add_theme_constant_override("shadow_outline_size", 3)   # soft, diffuse shadow
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
	var sp := s.duplicate() as StyleBoxFlat
	sp.bg_color = s.bg_color.darkened(0.14)
	b.add_theme_stylebox_override("pressed", sp)
	var sd := s.duplicate() as StyleBoxFlat
	sd.bg_color = Color(0.10, 0.09, 0.12, 0.5)
	sd.border_color = Color(accent.r, accent.g, accent.b, 0.25)
	sd.shadow_size = 0
	b.add_theme_stylebox_override("disabled", sd)
	# Warm ivory rather than a plain/cool white; the primary reads a touch brighter
	# to carry the visual hierarchy.
	b.add_theme_color_override("font_color", Color(1.0, 0.97, 0.90) if primary else Color(0.97, 0.93, 0.85))
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

# ---- hub action choices (Join / Create) ----
# No oversized illustration anymore — each choice is a lightweight engraved
# WOODEN SIGNBOARD: a gold-framed plank, warm wood grain, corner rivets, a small
# heraldic crest pinned to the top (a crown for CREATE, a shield for JOIN) and a
# little gold flourish under the label. The board carries a soft gold glow that
# gently breathes and brightens on hover, and the whole sign lifts slightly when
# pointed at. Built by action_card(), placed by layout_action_card().

# Cheap rounded-rect fill built from primitives (a cross of two rects plus four
# corner circles) — avoids allocating a StyleBox every redraw.
static func _draw_rounded_rect_fill(c: Control, rect: Rect2, radius: float, col: Color) -> void:
	var r := minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	if r <= 0.0:
		c.draw_rect(rect, col)
		return
	c.draw_rect(Rect2(rect.position.x, rect.position.y + r, rect.size.x, rect.size.y - r * 2.0), col)
	c.draw_rect(Rect2(rect.position.x + r, rect.position.y, rect.size.x - r * 2.0, rect.size.y), col)
	c.draw_circle(rect.position + Vector2(r, r), r, col)
	c.draw_circle(rect.position + Vector2(rect.size.x - r, r), r, col)
	c.draw_circle(rect.position + Vector2(r, rect.size.y - r), r, col)
	c.draw_circle(rect.position + Vector2(rect.size.x - r, rect.size.y - r), r, col)

# A tiny four-point sparkle (two crossed diamonds + a hot core), used to twinkle
# gold flecks around the CREATE board's edges.
static func _draw_star4(c: Control, ctr: Vector2, s: float, col: Color) -> void:
	if s <= 0.3:
		return
	c.draw_colored_polygon(PackedVector2Array([
		ctr + Vector2(0.0, -s), ctr + Vector2(s * 0.30, 0.0),
		ctr + Vector2(0.0, s), ctr + Vector2(-s * 0.30, 0.0)]), col)
	c.draw_colored_polygon(PackedVector2Array([
		ctr + Vector2(-s, 0.0), ctr + Vector2(0.0, s * 0.30),
		ctr + Vector2(s, 0.0), ctr + Vector2(0.0, -s * 0.30)]), col)
	c.draw_circle(ctr, s * 0.22, Color(1.0, 1.0, 1.0, col.a * 0.85))

# Twinkling flecks orbiting just outside the board rim (CREATE = warm gold,
# JOIN = cool magical blue). Each fleck breathes on its own phase.
static func _draw_sparkles(c: Control, w: float, h: float, t: float, col: Color, count: int) -> void:
	for i in range(count):
		var fi := float(i)
		var tw := 0.5 + 0.5 * sin(t * 1.7 + fi * 1.9)
		var ang := fi / float(count) * TAU + sin(t * 0.25 + fi) * 0.25
		var px := w * 0.5 + cos(ang) * (w * 0.53)
		var py := h * 0.5 + sin(ang) * (h * 0.92)
		_draw_star4(c, Vector2(px, py), h * 0.07 * tw, Color(col.r, col.g, col.b, tw * 0.9))

# A few tiny sparkles that pop around the four corners on hover — quick twinkles
# just outside each corner, phased so they shimmer rather than blink in unison.
static func _draw_corner_sparkles(c: Control, w: float, h: float, t: float, col: Color) -> void:
	var corners := [Vector2(0.0, 0.0), Vector2(w, 0.0), Vector2(0.0, h), Vector2(w, h)]
	var i := 0
	for cn: Vector2 in corners:
		var ph := float(i) * 1.7
		var tw := 0.5 + 0.5 * sin(t * 4.5 + ph)
		var off := Vector2(-6.0 if cn.x > w * 0.5 else 6.0, -6.0 if cn.y > h * 0.5 else 6.0)
		_draw_star4(c, cn + off, h * 0.10 * tw, Color(col.r, col.g, col.b, tw * 0.95))
		# a smaller satellite twinkle on the opposite phase
		_draw_star4(c, cn + off * 1.9, h * 0.06 * (1.0 - tw), Color(1.0, 1.0, 1.0, (1.0 - tw) * 0.7))
		i += 1

# A quick diagonal light band swept across the frame on hover. `prog` runs 0→1;
# outside that range nothing is drawn. Alpha rises and falls so it reads as a
# glint, not a wipe.
static func _draw_shine_sweep(c: Control, rect: Rect2, prog: float, col: Color) -> void:
	if prog <= 0.0 or prog >= 1.0:
		return
	var bw := rect.size.x * 0.20
	var skew := rect.size.y * 0.45
	var x := rect.position.x - bw - skew + prog * (rect.size.x + bw * 2.0 + skew)
	var y0 := rect.position.y
	var y1 := rect.position.y + rect.size.y
	var a := sin(prog * PI) * 0.42
	var edge := Color(col.r, col.g, col.b, 0.0)
	var core := Color(col.r, col.g, col.b, a)
	c.draw_polygon(
		PackedVector2Array([
			Vector2(x, y0), Vector2(x + bw, y0),
			Vector2(x + bw - skew, y1), Vector2(x - skew, y1)]),
		PackedColorArray([edge, core, core, edge]))

# One short hanging cloth banner draped over a side of the board — a royal-blue
# pennant with a swallowtail hem, a gold trim and a stud at the top.
static func _draw_side_banner(c: Control, cx: float, top_y: float, bw: float, blen: float,
		top_col: Color, bot_col: Color, gold: Color, gold_l: Color, gold_d: Color) -> void:
	var half := bw * 0.5
	var notch := blen * 0.24
	var pts := PackedVector2Array([
		Vector2(cx - half, top_y), Vector2(cx + half, top_y),
		Vector2(cx + half, top_y + blen - notch), Vector2(cx, top_y + blen),
		Vector2(cx - half, top_y + blen - notch)])
	# cloth with a top-to-bottom shade
	c.draw_polygon(pts, PackedColorArray([top_col, top_col, bot_col, bot_col, bot_col]))
	# soft fold shading down the middle + a left-side sheen
	c.draw_line(Vector2(cx, top_y + 2.0), Vector2(cx, top_y + blen - notch * 0.6),
		Color(0.0, 0.0, 0.0, 0.18), maxf(1.0, bw * 0.06))
	c.draw_line(Vector2(cx - half * 0.5, top_y + 2.0), Vector2(cx - half * 0.5, top_y + blen - notch),
		Color(top_col.r, top_col.g, top_col.b, 0.5) + Color(0.25, 0.25, 0.25, 0.0), maxf(1.0, bw * 0.08))
	# gold trim + swallowtail outline
	var outline := pts
	outline.append(pts[0])
	c.draw_polyline(outline, Color(gold.r, gold.g, gold.b, 0.9), maxf(1.2, bw * 0.07), true)
	# embroidered stitch trim: fine gold dashes running just inside each cloth edge
	var stitch := Color(gold_l.r, gold_l.g, gold_l.b, 0.62)
	var lx := cx - half + bw * 0.17
	var rx := cx + half - bw * 0.17
	var sy := top_y + bw * 0.20
	while sy < top_y + blen - notch:
		c.draw_line(Vector2(lx, sy), Vector2(lx, sy + bw * 0.10), stitch, 1.0)
		c.draw_line(Vector2(rx, sy), Vector2(rx, sy + bw * 0.10), stitch, 1.0)
		sy += bw * 0.22
	# a gentle second cloth fold to the right of centre (soft shadow + a lit crease)
	c.draw_line(Vector2(cx + half * 0.44, top_y + 2.0), Vector2(cx + half * 0.44, top_y + blen - notch),
		Color(0.0, 0.0, 0.0, 0.11), maxf(1.0, bw * 0.05))
	c.draw_line(Vector2(cx + half * 0.26, top_y + 2.0), Vector2(cx + half * 0.26, top_y + blen - notch * 0.8),
		Color(top_col.r + 0.16, top_col.g + 0.16, top_col.b + 0.18, 0.40), maxf(1.0, bw * 0.05))
	# top rail + stud
	c.draw_line(Vector2(cx - half - 2.0, top_y), Vector2(cx + half + 2.0, top_y), gold_d, maxf(1.4, bw * 0.09))
	c.draw_circle(Vector2(cx, top_y), bw * 0.16, gold_d)
	c.draw_circle(Vector2(cx, top_y), bw * 0.12, gold)
	c.draw_circle(Vector2(cx - bw * 0.03, top_y - bw * 0.03), bw * 0.05, gold_l)

# Two banners, one draped over each side of the board just below the top frame.
static func _draw_banners(c: Control, w: float, h: float, fr: float) -> void:
	var top_col := Color(0.34, 0.52, 0.96)
	var bot_col := Color(0.15, 0.26, 0.62)
	var gold := Color(1.0, 0.82, 0.40)
	var gold_l := Color(1.0, 0.93, 0.64)
	var gold_d := Color(0.52, 0.34, 0.10)
	var bw := h * 0.30
	var blen := h * 0.66
	var top_y := h * 0.16
	_draw_side_banner(c, fr * 0.62, top_y, bw, blen, top_col, bot_col, gold, gold_l, gold_d)
	_draw_side_banner(c, w - fr * 0.62, top_y, bw, blen, top_col, bot_col, gold, gold_l, gold_d)

# A small heraldic crown pinned above the CREATE board — three points, a banded
# base and jewelled tips. `s` is roughly the half-width.
static func _draw_mini_crown(c: Control, ctr: Vector2, s: float, gold: Color, gold_l: Color, gold_d: Color) -> void:
	var p := PackedVector2Array([
		ctr + Vector2(-s, s * 0.5), ctr + Vector2(-s, -s * 0.05),
		ctr + Vector2(-s * 0.5, -s * 0.62), ctr + Vector2(-s * 0.18, -s * 0.12),
		ctr + Vector2(0.0, -s * 0.9), ctr + Vector2(s * 0.18, -s * 0.12),
		ctr + Vector2(s * 0.5, -s * 0.62), ctr + Vector2(s, -s * 0.05),
		ctr + Vector2(s, s * 0.5)])
	c.draw_colored_polygon(p, gold)
	var o := p
	o.append(p[0])
	c.draw_polyline(o, gold_d, maxf(1.2, s * 0.12), true)
	c.draw_line(ctr + Vector2(-s, s * 0.26), ctr + Vector2(s, s * 0.26), Color(gold_l.r, gold_l.g, gold_l.b, 0.7), maxf(1.0, s * 0.1))
	c.draw_circle(ctr + Vector2(0.0, -s * 0.9), s * 0.14, gold_l)
	c.draw_circle(ctr + Vector2(-s * 0.5, -s * 0.62), s * 0.12, gold_l)
	c.draw_circle(ctr + Vector2(s * 0.5, -s * 0.62), s * 0.12, gold_l)

# A small heraldic shield pinned above the JOIN board — a royal-blue field with a
# silver rim, a thin gold inline and a bold white "+" join glyph. `s` ~ half-width.
static func _draw_mini_shield(c: Control, ctr: Vector2, s: float, accent: Color, gold: Color, gold_l: Color, gold_d: Color) -> void:
	var sil := Color(0.80, 0.85, 0.93)
	var sil_l := Color(0.97, 0.99, 1.0)
	var body := accent.lerp(Color(0.10, 0.16, 0.44), 0.30)
	var p := PackedVector2Array([
		ctr + Vector2(-s, -s * 0.72), ctr + Vector2(s, -s * 0.72),
		ctr + Vector2(s, s * 0.16), ctr + Vector2(0.0, s * 0.95),
		ctr + Vector2(-s, s * 0.16)])
	c.draw_colored_polygon(p, body)
	var sh := PackedVector2Array([
		ctr + Vector2(-s, -s * 0.72), ctr + Vector2(0.0, -s * 0.72),
		ctr + Vector2(0.0, s * 0.95), ctr + Vector2(-s, s * 0.16)])
	c.draw_colored_polygon(sh, Color(1.0, 1.0, 1.0, 0.12))
	var o := p
	o.append(p[0])
	c.draw_polyline(o, sil, maxf(1.4, s * 0.15), true)          # heavy silver rim
	c.draw_polyline(o, gold, maxf(0.8, s * 0.06), true)         # gold accent inline
	# bold white "+" join glyph
	var arm := s * 0.5
	var thick := maxf(1.6, s * 0.22)
	c.draw_line(ctr + Vector2(0.0, -arm), ctr + Vector2(0.0, arm), sil_l, thick)
	c.draw_line(ctr + Vector2(-arm, s * 0.04), ctr + Vector2(arm, s * 0.04), sil_l, thick)

# A clean, tight bloom hugging the frame (was a wide, blurry halo). Five thin
# concentric rings, brightest against the edge and falling off fast, so the glow
# reads as a premium rim-light rather than a soft cloud. `y_bias` nudges the
# bloom down so JOIN's glow pools slightly underneath the plate.
static func _draw_glow_bloom(c: Control, w: float, h: float, rad: float, glow_col: Color,
		strength: float, breathe: float, y_bias: float) -> void:
	var ga := (0.062 + 0.042 * breathe) * strength
	for i in range(6):
		var pad := 1.5 + float(i) * 1.9                      # 1.5..11 — hugs the frame tightly
		var f := 1.0 - float(i) / 6.0
		var a := ga * f * f                                  # squared falloff → crisp bloom, no blurry cloud
		_draw_rounded_rect_fill(c, Rect2(-pad, -pad + y_bias * pad, w + pad * 2.0, h + pad * 2.0),
			rad + pad, Color(glow_col.r, glow_col.g, glow_col.b, a))

# A soft contact shadow pooled just beneath the whole board so it reads as lifted
# off the stage. A couple of dark rounded slabs offset downward (drawn under the
# frame — only the sliver below the board shows).
static func _draw_drop_shadow(c: Control, w: float, h: float, rad: float, lift: float) -> void:
	for i in range(3):
		var inset := 3.0 + float(i) * 3.0
		var dy := 3.0 + lift + float(i) * 2.5
		var a := 0.20 * (1.0 - float(i) / 3.0)
		_draw_rounded_rect_fill(c, Rect2(inset, dy, w - inset * 2.0, h), rad, Color(0.0, 0.0, 0.0, a))

# A single soft diagonal reflection streak across a metal frame face — a static
# "studio light" catch that makes the gold/silver read as polished metal.
static func _draw_frame_reflection(c: Control, w: float, h: float, col: Color, a: float) -> void:
	var bw := w * 0.16
	var x := w * 0.20
	var skew := h * 0.5
	var edge := Color(col.r, col.g, col.b, 0.0)
	var core := Color(col.r, col.g, col.b, a)
	c.draw_polygon(
		PackedVector2Array([
			Vector2(x, 0.0), Vector2(x + bw, 0.0),
			Vector2(x + bw - skew, h), Vector2(x - skew, h)]),
		PackedColorArray([edge, core, core, edge]))

# A clean anti-aliased rounded-rect OUTLINE (four edges + four corner arcs) — used
# for the fine "second frame" groove channelled into the metal face.
static func _draw_rounded_rect_stroke(c: Control, rect: Rect2, radius: float, col: Color, width: float) -> void:
	var r := clampf(radius, 0.0, minf(rect.size.x, rect.size.y) * 0.5)
	var x0 := rect.position.x
	var y0 := rect.position.y
	var x1 := rect.position.x + rect.size.x
	var y1 := rect.position.y + rect.size.y
	c.draw_line(Vector2(x0 + r, y0), Vector2(x1 - r, y0), col, width, true)
	c.draw_line(Vector2(x1, y0 + r), Vector2(x1, y1 - r), col, width, true)
	c.draw_line(Vector2(x1 - r, y1), Vector2(x0 + r, y1), col, width, true)
	c.draw_line(Vector2(x0, y1 - r), Vector2(x0, y0 + r), col, width, true)
	c.draw_arc(Vector2(x1 - r, y0 + r), r, -PI * 0.5, 0.0, 10, col, width, true)
	c.draw_arc(Vector2(x1 - r, y1 - r), r, 0.0, PI * 0.5, 10, col, width, true)
	c.draw_arc(Vector2(x0 + r, y1 - r), r, PI * 0.5, PI, 10, col, width, true)
	c.draw_arc(Vector2(x0 + r, y0 + r), r, PI, PI * 1.5, 10, col, width, true)

# A fine decorative "second frame" cut into the metal face: a thin dark groove with
# a bright lip just inside it, so a slimmer frame reads nested within the main one.
static func _draw_inner_frame(c: Control, w: float, h: float, rad: float, inset: float,
		lip: Color, groove: Color) -> void:
	var rect := Rect2(inset, inset, w - inset * 2.0, h - inset * 2.0 - 3.0)
	var r := maxf(2.0, rad - inset)
	_draw_rounded_rect_stroke(c, rect, r, Color(groove.r, groove.g, groove.b, 0.8), 1.6)
	_draw_rounded_rect_stroke(c, Rect2(rect.position.x + 1.4, rect.position.y + 1.4,
		rect.size.x - 2.8, rect.size.y - 2.8), r - 1.4, Color(lip.r, lip.g, lip.b, 0.6), 1.0)

# Bright bevel down the left inner edge + a dark bevel down the right, so the frame
# reads as chamfered on all four sides (the boards draw the top/bottom bevels).
static func _draw_side_bevels(c: Control, w: float, h: float, rad: float, light: Color, dark: Color) -> void:
	c.draw_line(Vector2(1.6, rad), Vector2(1.6, h - rad - 3.0), Color(light.r, light.g, light.b, 0.7), 1.6, true)
	c.draw_line(Vector2(w - 1.8, rad), Vector2(w - 1.8, h - rad - 3.0), Color(dark.r, dark.g, dark.b, 0.6), 1.6, true)

# A small mounting boss seated on the frame's top-centre, behind the crest, so the
# crown/shield reads as a decorative crest built INTO the frame rather than floating
# above it. Flanked by two tiny rivets.
static func _draw_crest_mount(c: Control, w: float, s: float, gold: Color, gold_l: Color, gold_d: Color) -> void:
	var cx := w * 0.5
	var mw := s * 1.8
	var mh := s * 0.46
	var top := -s * 0.05
	_draw_rounded_rect_fill(c, Rect2(cx - mw * 0.5, top + 1.6, mw, mh), mh * 0.5, Color(0.0, 0.0, 0.0, 0.30))
	_draw_rounded_rect_fill(c, Rect2(cx - mw * 0.5, top, mw, mh), mh * 0.5, gold_d)
	_draw_rounded_rect_fill(c, Rect2(cx - mw * 0.5 + 1.6, top + 1.0, mw - 3.2, mh - 2.0), mh * 0.45, gold)
	_draw_rounded_rect_fill(c, Rect2(cx - mw * 0.5 + 2.6, top + 1.4, mw - 5.2, mh * 0.42), mh * 0.4,
		Color(gold_l.r, gold_l.g, gold_l.b, 0.6))
	for sx in [-1.0, 1.0]:
		var rc := Vector2(cx + sx * mw * 0.40, top + mh * 0.52)
		c.draw_circle(rc, s * 0.11, gold_d)
		c.draw_circle(rc, s * 0.075, gold_l)
		c.draw_circle(rc + Vector2(-s * 0.02, -s * 0.02), s * 0.03, Color(1.0, 1.0, 0.96, 0.9))

# CREATE — a warm oak signboard in a thick raised gold frame.
static func _draw_wood_board(c: Control, w: float, h: float, rad: float, accent: Color,
		glow_col: Color, strength: float, t: float, breathe: float) -> void:
	var wood := Color(0.35, 0.22, 0.13)
	var wood_d := Color(0.19, 0.11, 0.06)
	var wood_l := Color(0.48, 0.32, 0.19)
	var gold := Color(1.0, 0.82, 0.40)
	var gold_l := Color(1.0, 0.93, 0.64)
	var gold_d := Color(0.52, 0.34, 0.10)

	_draw_drop_shadow(c, w, h, rad, 0.0)                                       # elevated contact shadow
	_draw_glow_bloom(c, w, h, rad, glow_col, strength, breathe, 0.0)

	# raised gold frame with real depth: a thicker dark base, the gold face, a
	# bright top bevel and a dark bottom bevel so the edges read as beveled metal.
	_draw_rounded_rect_fill(c, Rect2(0.0, 3.0, w, h), rad, gold_d)              # frame drop shadow (deeper)
	_draw_rounded_rect_fill(c, Rect2(0.0, 0.0, w, h - 3.0), rad, gold)         # frame face
	_draw_rounded_rect_fill(c, Rect2(1.5, 1.0, w - 3.0, h * 0.34), rad * 0.8,
		Color(gold_l.r, gold_l.g, gold_l.b, 0.55))                             # soft overhead top highlight
	_draw_rounded_rect_fill(c, Rect2(1.5, h * 0.56, w - 3.0, h * 0.44 - 3.0), rad * 0.7,
		Color(gold_d.r, gold_d.g, gold_d.b, 0.24))                             # lower metal shade → richer vertical gradient
	c.draw_line(Vector2(rad, 1.2), Vector2(w - rad, 1.2), Color(gold_l.r, gold_l.g, gold_l.b, 0.95), 1.8)  # bright top bevel (thin upper highlight)
	c.draw_line(Vector2(rad, h - 4.0), Vector2(w - rad, h - 4.0), Color(gold_d.r, gold_d.g, gold_d.b, 0.7), 1.6)  # dark bottom bevel
	_draw_side_bevels(c, w, h, rad, gold_l, gold_d)                           # left/right chamfer → beveled on all edges
	_draw_frame_reflection(c, w, h - 3.0, gold_l, 0.22)                        # gentle metallic reflection
	_draw_frame_reflection(c, w * 0.62, h - 3.0, gold_l, 0.10)                 # second, softer catch-light

	# carved wood face
	var fr := maxf(4.0, h * 0.135)
	var iw := w - fr * 2.0
	var faceh := h - fr * 2.0
	_draw_inner_frame(c, w, h, rad, fr * 0.52, gold_l, gold_d)                 # fine second frame nested in the gold face
	# ambient occlusion where the frame meets the sunken panel (dark ring around the face)
	_draw_rounded_rect_fill(c, Rect2(fr - 2.5, fr - 2.5, iw + 5.0, faceh + 5.0), rad * 0.6, Color(0.0, 0.0, 0.0, 0.34))
	_draw_rounded_rect_fill(c, Rect2(fr, fr, iw, faceh), rad * 0.6, wood_d)
	_draw_rounded_rect_fill(c, Rect2(fr, fr, iw, faceh - 2.0), rad * 0.6, wood)
	for pt: float in [0.22, 0.44, 0.66, 0.88]:                                  # vertical plank seams
		var px := fr + iw * pt
		c.draw_line(Vector2(px, fr + 4.0), Vector2(px, h - fr - 5.0), Color(wood_d.r, wood_d.g, wood_d.b, 0.85), 1.6)
		c.draw_line(Vector2(px + 1.0, fr + 4.0), Vector2(px + 1.0, h - fr - 5.0), Color(wood_l.r, wood_l.g, wood_l.b, 0.55), 1.0)
	for pt: float in [0.10, 0.33, 0.55, 0.77, 0.96]:                            # fine grain figuring between the seams
		var px := fr + iw * pt
		c.draw_line(Vector2(px, fr + 5.0), Vector2(px, h - fr - 6.0), Color(wood_d.r, wood_d.g, wood_d.b, 0.28), 1.0)
	_draw_rounded_rect_fill(c, Rect2(fr + 3.0, fr + 2.0, iw - 6.0, faceh * 0.42), rad * 0.4,
		Color(wood_l.r, wood_l.g, wood_l.b, 0.30))                             # top sheen (overhead light)
	# inner shadow around the inside border: dark along top/left, a light bevel along bottom/right
	c.draw_line(Vector2(fr + 5.0, fr + 3.0), Vector2(w - fr - 5.0, fr + 3.0), Color(0.0, 0.0, 0.0, 0.34), 2.2)
	c.draw_line(Vector2(fr + 3.0, fr + 5.0), Vector2(fr + 3.0, h - fr - 5.0), Color(0.0, 0.0, 0.0, 0.26), 2.2)
	c.draw_line(Vector2(fr + 5.0, h - fr - 4.0), Vector2(w - fr - 5.0, h - fr - 4.0), Color(wood_l.r, wood_l.g, wood_l.b, 0.30), 1.4)
	c.draw_line(Vector2(w - fr - 4.0, fr + 5.0), Vector2(w - fr - 4.0, h - fr - 5.0), Color(wood_l.r, wood_l.g, wood_l.b, 0.22), 1.4)

	# inner engraved line, tinted by the choice accent
	var eng := accent.lerp(gold, 0.35)
	var ei := fr + 4.0
	_draw_rounded_rect_fill(c, Rect2(ei, ei, w - ei * 2.0, h - ei * 2.0), rad * 0.45, Color(eng.r, eng.g, eng.b, 0.55))
	_draw_rounded_rect_fill(c, Rect2(ei + 2.0, ei + 2.0, w - ei * 2.0 - 4.0, h - ei * 2.0 - 4.0), rad * 0.4, wood)

	# corner rivets — domed studs seated in an engraved socket, with a bright specular
	var sr := fr * 0.40
	var inset := fr * 0.95
	for cs in [Vector2(inset, inset), Vector2(w - inset, inset), Vector2(inset, h - inset), Vector2(w - inset, h - inset)]:
		c.draw_circle(cs, sr * 1.32, Color(gold_d.r, gold_d.g, gold_d.b, 0.9))    # recessed socket rim
		c.draw_arc(cs, sr * 1.28, 0.35, PI * 0.85, 14, Color(gold_l.r, gold_l.g, gold_l.b, 0.5), 1.3, true)  # socket catch-light
		c.draw_circle(cs + Vector2(0.6, 0.9), sr, Color(0.0, 0.0, 0.0, 0.35))    # rivet contact shadow
		c.draw_circle(cs, sr, gold_d)
		c.draw_circle(cs, sr * 0.82, gold)
		c.draw_circle(cs + Vector2(-sr * 0.3, -sr * 0.3), sr * 0.34, gold_l)
		c.draw_circle(cs + Vector2(-sr * 0.34, -sr * 0.34), sr * 0.15, Color(1.0, 1.0, 0.96, 0.95))  # specular

	# little gold flourish under the label (short rules + a centre diamond)
	var fy := h - fr - 5.0
	var fw := iw * 0.34
	c.draw_line(Vector2(w * 0.5 - fw, fy), Vector2(w * 0.5 - fw * 0.2, fy), Color(gold.r, gold.g, gold.b, 0.7), 1.6)
	c.draw_line(Vector2(w * 0.5 + fw * 0.2, fy), Vector2(w * 0.5 + fw, fy), Color(gold.r, gold.g, gold.b, 0.7), 1.6)
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(w * 0.5, fy - 3.0), Vector2(w * 0.5 + 3.0, fy),
		Vector2(w * 0.5, fy + 3.0), Vector2(w * 0.5 - 3.0, fy)]), gold_l)
	c.draw_circle(Vector2(w * 0.5 - 1.0, fy - 1.2), 1.2, Color(1.0, 1.0, 0.96, 0.9))  # specular
	for sx in [-1.0, 1.0]:                                                       # ornamental separator dots
		c.draw_circle(Vector2(w * 0.5 + sx * fw * 0.24, fy), 1.7, gold_d)
		c.draw_circle(Vector2(w * 0.5 + sx * fw * 0.24, fy), 1.1, Color(gold_l.r, gold_l.g, gold_l.b, 0.9))

	_draw_banners(c, w, h, fr)
	_draw_sparkles(c, w, h, t, Color(1.0, 0.88, 0.5), 7)

# JOIN — a royal-blue brushed-steel plate in a heavy silver frame with gold accents.
static func _draw_metal_board(c: Control, w: float, h: float, rad: float, accent: Color,
		glow_col: Color, strength: float, t: float, breathe: float) -> void:
	var steel := Color(0.19, 0.31, 0.60)
	var steel_d := Color(0.09, 0.16, 0.38)
	var steel_l := Color(0.42, 0.58, 0.92)
	var sil := Color(0.78, 0.83, 0.91)
	var sil_l := Color(0.96, 0.98, 1.0)
	var sil_d := Color(0.40, 0.46, 0.56)
	var gold := Color(1.0, 0.82, 0.40)
	var gold_l := Color(1.0, 0.93, 0.64)
	var gold_d := Color(0.55, 0.42, 0.14)

	_draw_drop_shadow(c, w, h, rad, 0.0)                                        # elevated contact shadow
	# soft blue glow pooling underneath the plate
	_draw_glow_bloom(c, w, h, rad, glow_col, strength, breathe, 0.9)

	# heavy silver frame with real depth: deeper dark base, silver face, bright top
	# bevel + dark bottom bevel, and a polished-metal reflection streak.
	_draw_rounded_rect_fill(c, Rect2(0.0, 3.0, w, h), rad, sil_d)               # frame drop shadow (deeper)
	_draw_rounded_rect_fill(c, Rect2(0.0, 0.0, w, h - 3.0), rad, sil)           # silver frame face
	_draw_rounded_rect_fill(c, Rect2(1.5, 1.0, w - 3.0, h * 0.34), rad * 0.8,
		Color(sil_l.r, sil_l.g, sil_l.b, 0.65))                                 # soft overhead top highlight
	_draw_rounded_rect_fill(c, Rect2(1.5, h * 0.56, w - 3.0, h * 0.44 - 3.0), rad * 0.7,
		Color(sil_d.r, sil_d.g, sil_d.b, 0.26))                                 # lower metal shade → richer vertical gradient
	c.draw_line(Vector2(rad, 1.2), Vector2(w - rad, 1.2), Color(sil_l.r, sil_l.g, sil_l.b, 1.0), 1.8)   # bright top bevel (thin upper highlight)
	c.draw_line(Vector2(rad, h - 4.0), Vector2(w - rad, h - 4.0), Color(sil_d.r, sil_d.g, sil_d.b, 0.75), 1.6)  # dark bottom bevel
	_draw_side_bevels(c, w, h, rad, sil_l, sil_d)                               # left/right chamfer → beveled on all edges
	_draw_frame_reflection(c, w, h - 3.0, sil_l, 0.28)                          # polished-metal reflection
	_draw_frame_reflection(c, w * 0.62, h - 3.0, sil_l, 0.12)                   # second, softer catch-light
	# thin gold accent band inset into the frame
	var af := maxf(3.0, h * 0.055)
	_draw_rounded_rect_fill(c, Rect2(af, af, w - af * 2.0, h - af * 2.0), rad * 0.75, gold_d)
	_draw_rounded_rect_fill(c, Rect2(af + 1.6, af + 1.6, w - af * 2.0 - 3.2, h - af * 2.0 - 3.2), rad * 0.7, gold)
	_draw_frame_reflection(c, w, h - 3.0, gold_l, 0.20)                         # gold band catch-light

	# brushed-steel plate face
	var fr := maxf(5.0, h * 0.15)
	var iw := w - fr * 2.0
	var ih := h - fr * 2.0
	_draw_inner_frame(c, w, h, rad, fr * 0.6, sil_l, sil_d)                     # fine second frame nested in the silver face
	# ambient occlusion where the frame meets the sunken plate
	_draw_rounded_rect_fill(c, Rect2(fr - 2.5, fr - 2.5, iw + 5.0, ih + 5.0), rad * 0.55, Color(0.0, 0.0, 0.0, 0.36))
	_draw_rounded_rect_fill(c, Rect2(fr, fr, iw, ih), rad * 0.55, steel_d)
	_draw_rounded_rect_fill(c, Rect2(fr, fr, iw, ih - 2.0), rad * 0.55, steel)
	# fine horizontal brushing streaks
	var yy := fr + 3.0
	var row := 0
	while yy < h - fr - 3.0:
		var v := sin(float(row) * 12.9898) * 43758.5453
		v = v - floor(v)
		var la := 0.07 + 0.08 * v
		var col := steel_l if (row % 2 == 0) else steel_d
		c.draw_line(Vector2(fr + 4.0, yy), Vector2(w - fr - 4.0, yy), Color(col.r, col.g, col.b, la), 1.0)
		yy += 2.6
		row += 1
	# top sheen across the plate
	_draw_rounded_rect_fill(c, Rect2(fr + 3.0, fr + 2.0, iw - 6.0, ih * 0.40), rad * 0.4,
		Color(steel_l.r, steel_l.g, steel_l.b, 0.30))
	# metallic gold rim-light around the plate edge
	var ei := fr + 3.0
	_draw_rounded_rect_fill(c, Rect2(ei, ei, w - ei * 2.0, h - ei * 2.0), rad * 0.5, Color(gold_l.r, gold_l.g, gold_l.b, 0.5))
	_draw_rounded_rect_fill(c, Rect2(ei + 1.6, ei + 1.6, w - ei * 2.0 - 3.2, h - ei * 2.0 - 3.2), rad * 0.45, steel)
	# inner shadow around the inside border: dark along top/left, a light bevel along bottom/right
	c.draw_line(Vector2(fr + 5.0, fr + 3.0), Vector2(w - fr - 5.0, fr + 3.0), Color(0.0, 0.0, 0.0, 0.32), 2.2)
	c.draw_line(Vector2(fr + 3.0, fr + 5.0), Vector2(fr + 3.0, h - fr - 5.0), Color(0.0, 0.0, 0.0, 0.24), 2.2)
	c.draw_line(Vector2(fr + 5.0, h - fr - 4.0), Vector2(w - fr - 5.0, h - fr - 4.0), Color(sil_l.r, sil_l.g, sil_l.b, 0.28), 1.4)
	c.draw_line(Vector2(w - fr - 4.0, fr + 5.0), Vector2(w - fr - 4.0, h - fr - 5.0), Color(sil_l.r, sil_l.g, sil_l.b, 0.20), 1.4)

	# corner rivets (silver) — domed studs seated in an engraved socket, bright specular
	var sr := fr * 0.40
	var inset := fr * 0.95
	for cs in [Vector2(inset, inset), Vector2(w - inset, inset), Vector2(inset, h - inset), Vector2(w - inset, h - inset)]:
		c.draw_circle(cs, sr * 1.32, Color(sil_d.r, sil_d.g, sil_d.b, 0.9))      # recessed socket rim
		c.draw_arc(cs, sr * 1.28, 0.35, PI * 0.85, 14, Color(sil_l.r, sil_l.g, sil_l.b, 0.55), 1.3, true)  # socket catch-light
		c.draw_circle(cs + Vector2(0.6, 0.9), sr, Color(0.0, 0.0, 0.0, 0.35))    # rivet contact shadow
		c.draw_circle(cs, sr, sil_d)
		c.draw_circle(cs, sr * 0.82, sil)
		c.draw_circle(cs + Vector2(-sr * 0.3, -sr * 0.3), sr * 0.34, sil_l)
		c.draw_circle(cs + Vector2(-sr * 0.34, -sr * 0.34), sr * 0.15, Color(1.0, 1.0, 1.0, 0.98))  # specular

	# gold flourish under the label
	var fy := h - fr - 5.0
	var fw := iw * 0.34
	c.draw_line(Vector2(w * 0.5 - fw, fy), Vector2(w * 0.5 - fw * 0.2, fy), Color(gold.r, gold.g, gold.b, 0.7), 1.6)
	c.draw_line(Vector2(w * 0.5 + fw * 0.2, fy), Vector2(w * 0.5 + fw, fy), Color(gold.r, gold.g, gold.b, 0.7), 1.6)
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(w * 0.5, fy - 3.0), Vector2(w * 0.5 + 3.0, fy),
		Vector2(w * 0.5, fy + 3.0), Vector2(w * 0.5 - 3.0, fy)]), gold_l)
	c.draw_circle(Vector2(w * 0.5 - 1.0, fy - 1.2), 1.2, Color(1.0, 1.0, 0.96, 0.9))  # specular
	for sx in [-1.0, 1.0]:                                                       # ornamental separator dots
		c.draw_circle(Vector2(w * 0.5 + sx * fw * 0.24, fy), 1.7, gold_d)
		c.draw_circle(Vector2(w * 0.5 + sx * fw * 0.24, fy), 1.1, Color(gold_l.r, gold_l.g, gold_l.b, 0.9))

	_draw_banners(c, w, h, fr)
	# subtle magical blue shimmer around the rim
	_draw_sparkles(c, w, h, t, Color(0.62, 0.86, 1.0), 6)

# The engraved signboard itself (crest pokes above y=0, glow blooms out past the
# edges — the plaque control is drawn with clip_contents off). CREATE renders as
# oak-in-gold, JOIN as steel-in-silver; both share the crest, banners and a
# hover shine sweep.
static func _draw_signboard(c: Control, kind: String, accent: Color, glow_col: Color, glow_strength: float) -> void:
	var w := c.size.x
	var h := c.size.y
	var t := Time.get_ticks_msec() / 1000.0
	var breathe := 0.5 + 0.5 * sin(t * 1.4)
	var rad := h * 0.30
	var gold := Color(1.0, 0.82, 0.40)
	var gold_l := Color(1.0, 0.93, 0.64)
	var gold_d := Color(0.52, 0.34, 0.10)

	if kind == "crown":
		_draw_wood_board(c, w, h, rad, accent, glow_col, glow_strength, t, breathe)
	else:
		_draw_metal_board(c, w, h, rad, accent, glow_col, glow_strength, t, breathe)

	# heraldic crest — seated into a small mounting boss on the frame's top edge, ~20%
	# smaller and dropped so its base sinks into the frame: reads as a decorative crest
	# built into the button rather than a separate icon floating above it.
	var cs2 := h * 0.204                                       # ~15% smaller crest — reads as an integrated crest, not a floating icon
	var crest_ctr := Vector2(w * 0.5, cs2 * 0.46)             # dropped so its base sinks further into the top frame
	_draw_crest_mount(c, w, cs2, gold, gold_l, gold_d)
	if kind == "crown":
		_draw_mini_crown(c, crest_ctr, cs2, gold, gold_l, gold_d)
	else:
		_draw_mini_shield(c, crest_ctr, cs2, accent, gold, gold_l, gold_d)

# A ghost copy of the title used as an emboss layer (drawn behind the main face,
# offset up for a highlight or down for a shadow). `ol` / `oc` set an optional
# outline so the shadow layer can carry a broad dark halo for readability.
static func _emboss_layer(text: String, fs: int, col: Color, ol: int, oc: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	if ol > 0:
		l.add_theme_color_override("font_outline_color", oc)
		l.add_theme_constant_override("outline_size", ol)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# Builds a hub action choice as an engraved wooden signboard (unsized/unpositioned
# — call layout_action_card() to place it). `icon_kind` picks the crest: "crown"
# for CREATE, "door" (shield crest) for JOIN. `accent` tints the engrave/crest,
# `glow` sets the soft glow colour (amber for Create, cyan for Join). `primary`
# and `subtitle_text` are accepted for call-site compatibility but unused now.
static func action_card(title_text: String, subtitle_text: String, icon_kind: String,
		accent: Color, primary: bool = false, glow: Color = Color(-1.0, -1.0, -1.0, -1.0),
		icon_scale: float = 1.0) -> Button:
	var glow_col := accent if glow.r < 0.0 else glow
	var scale := maxf(0.6, icon_scale)
	var pw := 132.0 * scale
	var ph := 46.0 * scale
	var crest := ph * 0.42

	var b := Button.new()
	b.text = ""
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.clip_contents = false
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, empty)

	# The signboard plaque (crest pokes above it; glow blooms past its edges).
	var plaque := Control.new()
	plaque.size = Vector2(pw, ph)
	plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plaque.set_meta("glow_strength", 1.0)
	plaque.draw.connect(func() -> void:
		_draw_signboard(plaque, icon_kind, accent, glow_col, plaque.get_meta("glow_strength")))
	b.add_child(plaque)

	# Engraved gold title across the board.
	var title := Label.new()
	title.text = title_text.to_upper()
	# Shrink the engraved font until the whole title fits inside the board so long
	# labels like "CREATE A ROOM" don't spill past the frame.
	var fit_fs := int(round(14.5 * scale))
	var avail_w := pw * 0.76
	var title_font := title.get_theme_font("font")
	if title_font == null:
		title_font = ThemeDB.fallback_font
	while fit_fs > 8 and title_font.get_string_size(title.text, HORIZONTAL_ALIGNMENT_CENTER, -1.0, fit_fs).x > avail_w:
		fit_fs -= 1
	title.add_theme_font_size_override("font_size", fit_fs)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))          # polished engraved gold
	title.add_theme_color_override("font_outline_color", Color(0.22, 0.12, 0.03, 0.9))
	title.add_theme_constant_override("outline_size", 2)                        # thinner → readability from material, not a heavy border
	title.add_theme_color_override("font_shadow_color", Color(glow_col.r, glow_col.g, glow_col.b, 0.6))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 1)
	title.add_theme_constant_override("shadow_outline_size", 8)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Emboss: a dark inner-shadow copy sunk below the letters and a thin gold
	# top-highlight copy raised above them (both behind the main face), so the
	# engraved title catches the same overhead light as the frame.
	var title_sh := _emboss_layer(title.text, fit_fs, Color(0.11, 0.06, 0.01, 0.92), 3, Color(0.08, 0.04, 0.01, 0.92))
	var title_hi := _emboss_layer(title.text, fit_fs, Color(1.0, 0.99, 0.88, 0.98), 0, Color(0, 0, 0, 0))
	plaque.add_child(title_sh)   # behind
	plaque.add_child(title_hi)   # behind, above the shadow
	plaque.add_child(title)      # main face on top

	# Repaints the plaque for glow breathing, twinkling sparkles and the shine sweep.
	var tmr := Timer.new()
	tmr.wait_time = 0.04
	tmr.autostart = true
	tmr.timeout.connect(plaque.queue_redraw)
	plaque.add_child(tmr)

	b.set_meta("plaque_ctrl", plaque)
	b.set_meta("title_lbl", title)
	b.set_meta("title_sh", title_sh)
	b.set_meta("title_hi", title_hi)
	b.set_meta("plaque_size", Vector2(pw, ph))
	b.set_meta("crest", crest)
	b.set_meta("base_pos", Vector2.ZERO)

	var set_glow := func(v: float) -> void:
		plaque.set_meta("glow_strength", v)

	# Press feedback: the glow flares on tap-down and the label brightens, then
	# both settle back to the resting state on release.
	b.button_down.connect(func() -> void:
		b.scale = Vector2.ONE
		plaque.set_meta("glow_strength", 2.7)
		title.create_tween().tween_property(title, "modulate", Color(1.25, 1.2, 1.08), 0.12))
	b.button_up.connect(func() -> void:
		b.create_tween().tween_method(set_glow, 2.7, 1.0, 0.2)
		title.create_tween().tween_property(title, "modulate", Color.WHITE, 0.16))
	return b

# Sizes/positions a signboard built by action_card(). `ground` is the dais point
# the crown/door used to stand on; the board's visual centre is planted ~150px
# above it (the same zone the old icons occupied), and scale grows from the
# bottom so hover reads as the sign rising off the stage.
static func layout_action_card(b: Button, ground: Vector2, size: Vector2) -> void:
	var ps: Vector2 = b.get_meta("plaque_size")
	var crest: float = b.get_meta("crest")
	var cy := ground.y - 150.0
	var pos := Vector2(ground.x - size.x * 0.5, cy - size.y * 0.5)
	b.set_meta("base_pos", pos)
	b.position = pos
	b.size = size
	b.pivot_offset = Vector2(size.x * 0.5, size.y * 0.5 + ps.y * 0.5)
	var plaque: Control = b.get_meta("plaque_ctrl")
	var title: Label = b.get_meta("title_lbl")
	plaque.position = Vector2(size.x * 0.5 - ps.x * 0.5, size.y * 0.5 - ps.y * 0.5 + crest * 0.4)
	plaque.size = ps
	var frv := maxf(4.0, ps.y * 0.13)
	var tpos := Vector2(0.0, frv * 0.5)
	var tsize := Vector2(ps.x, ps.y - frv * 1.6)
	title.position = tpos
	title.size = tsize
	# Emboss ghosts: highlight raised above the face, shadow sunk below it.
	var title_sh: Label = b.get_meta("title_sh")
	var title_hi: Label = b.get_meta("title_hi")
	title_hi.position = tpos + Vector2(0.0, -1.5)
	title_hi.size = tsize
	title_sh.position = tpos + Vector2(0.0, 1.8)
	title_sh.size = tsize

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

# The hub's premium wordmark: a big carved-gold "ARENA" with emboss layers (bright
# top-highlight + sunken bronze shadow) and gold ornament rules flanking the word —
# a Clash-Royale/Marvel-Snap style banner. Returns a Control; the caller sizes it to
# (screen_w, ~64) and positions it; everything centres and lays out inside.
static func hub_title(text: String) -> Control:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.clip_contents = false
	var up := text.to_upper()
	var fs := 48

	# Gold ornament rules + gems flanking the word, drawn from the measured text width.
	var deco := Control.new()
	deco.set_anchors_preset(Control.PRESET_FULL_RECT)
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deco.draw.connect(func() -> void:
		var f := ThemeDB.fallback_font
		var tw := f.get_string_size(up, HORIZONTAL_ALIGNMENT_CENTER, -1.0, fs).x
		var cx := deco.size.x * 0.5
		var cy := deco.size.y * 0.5
		var gap := 22.0
		var rule_len := 46.0
		var gold := Color(1.0, 0.82, 0.36)
		var gold_hi := Color(1.0, 0.95, 0.72)
		for dir: float in [-1.0, 1.0]:
			var inner: float = cx + dir * (tw * 0.5 + gap)
			var outer: float = inner + dir * rule_len
			# tapered rule
			deco.draw_line(Vector2(inner, cy), Vector2(outer, cy), Color(gold.r, gold.g, gold.b, 0.85), 2.4, true)
			deco.draw_line(Vector2(inner, cy - 0.6), Vector2(outer, cy - 0.6), Color(gold_hi.r, gold_hi.g, gold_hi.b, 0.5), 1.0, true)
			# a small diamond gem at the outer end
			var g := Vector2(outer + dir * 8.0, cy)
			var r := 5.0
			var pts := PackedVector2Array([g + Vector2(0, -r), g + Vector2(r, 0), g + Vector2(0, r), g + Vector2(-r, 0)])
			deco.draw_colored_polygon(pts, gold)
			deco.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), gold_hi, 1.0, true)
			deco.draw_circle(g + Vector2(-1.2, -1.4), 1.3, Color(1, 1, 1, 0.85)))
	root.add_child(deco)

	# Sunken shadow copy (dropped, with a broad dark halo for depth).
	var sh := _emboss_layer(up, fs, Color(0.14, 0.07, 0.01, 0.95), 5, Color(0.08, 0.04, 0.0, 0.9))
	sh.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sh.set_anchors_preset(Control.PRESET_FULL_RECT)
	sh.position = Vector2(0, 3)
	root.add_child(sh)

	# Bright top highlight (raised), so the letters catch the overhead light.
	var hi := _emboss_layer(up, fs, Color(1.0, 0.98, 0.80, 0.95), 0, Color(0, 0, 0, 0))
	hi.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hi.set_anchors_preset(Control.PRESET_FULL_RECT)
	hi.position = Vector2(0, -2)
	root.add_child(hi)

	# Main carved-gold face with a warm amber glow.
	var l := Label.new()
	l.text = up
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", Color(1.0, 0.84, 0.42))
	l.add_theme_color_override("font_outline_color", Color(0.24, 0.13, 0.02, 0.95))
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_color_override("font_shadow_color", Color(1.0, 0.55, 0.15, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", 14)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(l)
	return root

# A premium hub subtitle: warm ivory, letter-spaced-feeling small caps with a soft
# shadow — sits under the wordmark as a tasteful tagline.
static func hub_subtitle(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", Color(0.96, 0.86, 0.66))
	l.add_theme_color_override("font_outline_color", Color(0.10, 0.06, 0.02, 0.7))
	l.add_theme_constant_override("outline_size", 2)
	l.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.35))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
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
