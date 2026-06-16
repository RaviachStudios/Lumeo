extends Control
class_name SimonWheel

# A 3D Simon wheel rendered through a SubViewport and shown as a 2D widget.
# Geometry is generated procedurally from the segment count, so it adapts to
# 4 / 5 / 6 buttons (easy / moderate / hard) with no per-count art.
#
# Public API:
#   configure(count, colors)      -> (re)build the wheel
#   set_lit(idx, on)              -> light a segment (drives emission glow)
#   set_press(idx, amount)        -> 0..1 press-down feedback
#   segment_at_point(local_pos)   -> segment index under a tap, or -1
#
# Renderer note: project runs the Mobile (Vulkan) renderer. The look is driven
# entirely by geometry (rounded-bevel buttons), StandardMaterial3D (glossy ABS,
# no textures), and soft lighting - NOT by surface texture/noise. Emissive
# materials + a touch of bloom drive the light-up.

# ---- tunables (wheel is built in local units, ring outer radius = 1.0) ----
const OUTER_R := 1.0
const INNER_R := 0.34        # buttons reach closer to center (bigger buttons)
const SEG_H := 0.20          # segment thickness (depth) - thick, heavy buttons
const BASE_R := 1.16         # graphite base plate radius (thin frame outside buttons)
const BASE_H := 0.20
const HUB_R := 0.30          # smaller center circle (~ -25%)
const HUB_H := 0.22
const GAP_DEG := 5.0         # angular gap between segments
const ARC_STEPS := 16        # arc tessellation per segment (smooth bevel/dome)
const RADIAL_STEPS := 10     # radial tessellation of the top (smooth bevel/dome)
const DOME := 0.045          # gentle central convexity (pillowed top)
const BEVEL := 0.085         # rounded-bevel drop around the whole segment edge
const BEVEL_ZONE := 0.3      # fraction of each half-extent occupied by the bevel

const EMIT_ON := 1.3         # emission when lit: lit from within, not overexposed
const EMIT_OFF := 0.22       # idle self-illumination — bumped from 0.14 so the
							 # button colors read vivid even before being lit.
							 # Still well under the 1.1 bloom threshold.
const GLOW_LERP := 14.0      # how fast glow rises/falls
const PRESS_DROP := 0.06     # how far a pressed segment sinks (local units)
const HALO_SIZE := 1.5       # small glow that bleeds just past the segment edges
const HALO_ALPHA := 0.5      # outer-glow strength when lit (calibrating - tune down)
# Each colored button is inset inside its slot, leaving a dark frame
# border around it, and raised so it sits proud of the frame.
const BTN_ANG_MARGIN := 2.0  # degrees trimmed from each angular side
const BTN_RAD_MARGIN := 0.06 # radial inset
const BTN_RAISE := 0.09      # how far the button sits above the frame plate
# Side walls kept fairly bright so buttons never read as near-black; inner/cap
# walls only a little darker for a soft seam (gentle AO, not heavy shadow).
const SIDE_DARK := 0.15      # outer side-wall brightness vs the top
const SIDE_DARK_IN := 0.58   # inner/recessed walls a touch darker

# Camera framing (slight tilt for a 3D feel while keeping hit-testing simple).
# Pulled in so the wheel fills most of the widget (large, prominent).
const CAM_POS := Vector3(0.0, 4.0, 1.5)
const CAM_FOV := 34.0

var _colors: Array = []
var _count: int = 0
var _start_angle := -PI * 0.5   # segment 0 centered toward top of screen

var _vpc: SubViewportContainer
var _vp: SubViewport
var _cam: Camera3D
var _wheel_root: Node3D
var _segments: Array[MeshInstance3D] = []
var _seg_mats: Array[StandardMaterial3D] = []
var _seg_base: Array[Color] = []   # enriched (richer/brighter) per-segment base color
var _emit_cur: Array[float] = []
var _emit_tgt: Array[float] = []
var _press: Array[float] = []
var _halos: Array[MeshInstance3D] = []
var _halo_mats: Array[StandardMaterial3D] = []
var _glow_tex: Texture2D
var _level_num: Label
var _num_labels: Array[Label] = []   # stacked layers (glow / main / highlight)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_shell()
	resized.connect(_sync_viewport_size)

func _build_shell() -> void:
	_vpc = SubViewportContainer.new()
	_vpc.stretch = true
	_vpc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vpc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vpc)

	_vp = SubViewport.new()
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vpc.add_child(_vp)

	# --- environment ---
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR   # transparent for compositing
	# A studio-ish sky drives image-based reflections so metal reads as metal.
	# It is NOT drawn (background stays transparent) - only used for IBL.
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.55, 0.62, 0.85)
	sky_mat.sky_horizon_color = Color(0.16, 0.18, 0.28)
	sky_mat.ground_horizon_color = Color(0.12, 0.12, 0.16)
	sky_mat.ground_bottom_color = Color(0.02, 0.02, 0.04)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.45         # broad studio fill — bumped from 1.15
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 2   # tune 1.0–1.5
											# so the wheel reads brighter without
											# touching any clearcoat/specular path
	# Side glow: only the lit segment crosses the HDR threshold, so it blooms a
	# little colored light onto the surrounding frame. The bloom radius is kept
	# SMALL (fine glow levels only) so it reads as light bleed, not a neon aura.
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_strength = 0.9
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.set_glow_level(1, 1.0)               # finest -> tight glow close to the edge
	env.set_glow_level(2, 0.9)
	env.set_glow_level(3, 0.4)
	env.set_glow_level(4, 0.0)               # zero the wide levels -> small radius
	env.set_glow_level(5, 0.0)
	env.set_glow_level(6, 0.0)
	env.set_glow_level(7, 0.0)
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)

	# --- camera ---
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = CAM_FOV
	_cam.position = CAM_POS
	_vp.add_child(_cam)
	_cam.look_at(Vector3.ZERO, Vector3.UP)  # must be in-tree before look_at

	# --- lights ---
	# One large, soft light source from nearly overhead. A directional light reads
	# as an infinitely large source, so its specular is broad and soft (no small
	# sharp hotspot) and it lays a clean highlight across the glossy tops.
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-72, -18, 0)   # high overhead, slight lean
	key.light_energy = 1.25
	key.light_color = Color(1.0, 0.98, 0.95)
	key.light_specular = 0.85                      # broad, controlled highlight
	key.shadow_enabled = true                      # soft contact shadows in the seams
	key.shadow_blur = 3.0                          # softer = premium, no hard edge
	key.shadow_opacity = 0.5                       # light shadows, no heavy darkening
	_vp.add_child(key)

	# Cool, dim fill from the opposite low side: lifts the recessed/lower faces just
	# enough to read their form without flattening the contrast.
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-28, 150, 0)
	fill.light_energy = 0.45                       # lifts the shadowed inner faces
	fill.light_specular = 0.0                      # no second hotspot
	fill.light_color = Color(0.7, 0.78, 1.0)
	_vp.add_child(fill)

	_wheel_root = Node3D.new()
	_vp.add_child(_wheel_root)

	_build_center_overlay()
	_sync_viewport_size()

# Center readout styled like an illuminated hardware display: a large pure-white
# numeral (auto-shrinking as the level grows) with a soft blue outer glow, a
# circular glow behind it and a soft drop shadow, plus a small status light a
# fixed gap below - all Godot-native (no fonts). Centered on the hub.
const NUM_MAX_SIZE := 80     # font size for short numbers
const NUM_MIN_SIZE := 26     # never shrink past this
const NUM_MAX_W := 104.0     # numeral shrinks to stay within this width (the hub)
const CENTER_LIFT := 20      # px to raise the readout (hub center sits above widget
							 # center due to the camera tilt)
const DOT_GAP := 57          # px from the numeral center down to the status light

func _build_center_overlay() -> void:
	# Numeral holder, centered on the hub. This Control is sized to the widget, so
	# anchoring children to its center pins the numeral to the inner-circle center.
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(190, 120)
	holder.size = Vector2(190, 120)
	holder.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	holder.offset_top -= CENTER_LIFT
	holder.offset_bottom -= CENTER_LIFT
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)

	# (1) circular blue-white glow behind the numeral: invisible body, soft halo.
	var glow := Panel.new()
	glow.custom_minimum_size = Vector2(100, 100)
	glow.size = Vector2(100, 100)
	glow.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gs := StyleBoxFlat.new()
	gs.bg_color = Color(0.5, 0.68, 1.0, 0.0)
	gs.set_corner_radius_all(50)
	gs.shadow_color = Color(0.45, 0.66, 1.0, 0.15)   # low-opacity, soft falloff
	gs.shadow_size = 30
	glow.add_theme_stylebox_override("panel", gs)
	holder.add_child(glow)

	_num_labels.clear()
	# (2) soft blue OUTER GLOW, glyph-shaped: transparent fill, blurred blue shadow.
	var nglow := _num_label(NUM_MAX_SIZE, Color(0.5, 0.7, 1.0, 0.0))
	nglow.add_theme_color_override("font_shadow_color", Color(0.45, 0.68, 1.0, 0.5))
	nglow.add_theme_constant_override("shadow_offset_x", 0)
	nglow.add_theme_constant_override("shadow_offset_y", 0)
	nglow.add_theme_constant_override("shadow_outline_size", 10)
	holder.add_child(nglow)
	_num_labels.append(nglow)

	# (3) main numeral: pure white, thin same-color weight outline (~semi-bold),
	# and a soft dark drop shadow underneath.
	_level_num = _num_label(NUM_MAX_SIZE, Color.WHITE)
	_level_num.add_theme_color_override("font_outline_color", Color(1, 1, 1, 1))
	_level_num.add_theme_constant_override("outline_size", 2)   # weight, not a stroke
	_level_num.add_theme_color_override("font_shadow_color", Color(0.0, 0.02, 0.06, 0.5))
	_level_num.add_theme_constant_override("shadow_offset_x", 0)
	_level_num.add_theme_constant_override("shadow_offset_y", 4)
	_level_num.add_theme_constant_override("shadow_outline_size", 5)
	holder.add_child(_level_num)
	_num_labels.append(_level_num)

	# (4) faint top highlight: white copy nudged up 2px at low alpha, so the top
	# edge of the numeral catches a little extra light (illuminated-display feel).
	var hi := _num_label(NUM_MAX_SIZE, Color(1, 1, 1, 0.35))
	hi.offset_top -= 2
	hi.offset_bottom -= 2
	holder.add_child(hi)
	_num_labels.append(hi)

	# Small glowing status light, centered horizontally a fixed gap below the
	# numeral (just inside the lower hub).
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(12, 12)
	dot.size = Vector2(12, 12)
	dot.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	dot.offset_top += DOT_GAP - CENTER_LIFT          # stays DOT_GAP below the numeral
	dot.offset_bottom += DOT_GAP - CENTER_LIFT
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ds := StyleBoxFlat.new()
	ds.bg_color = Color(0.55, 0.76, 1.0)
	ds.set_corner_radius_all(6)
	ds.shadow_color = Color(0.35, 0.62, 1.0, 0.7)
	ds.shadow_size = 10
	dot.add_theme_stylebox_override("panel", ds)
	add_child(dot)

	set_level(1)

# One numeral layer: fills the holder and centers its glyph, so all layers align.
func _num_label(fsize: int, col: Color) -> Label:
	var l := Label.new()
	l.text = "1"
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# Largest size (<= NUM_MAX_SIZE) at which the number still fits NUM_MAX_W wide.
func _fit_num_size(txt: String) -> int:
	var w := ThemeDB.fallback_font.get_string_size(
		txt, HORIZONTAL_ALIGNMENT_LEFT, -1, NUM_MAX_SIZE).x
	if w <= NUM_MAX_W:
		return NUM_MAX_SIZE
	return maxi(NUM_MIN_SIZE, int(floor(NUM_MAX_SIZE * NUM_MAX_W / w)))

func set_level(n: int) -> void:
	var txt := str(n)
	var fs := _fit_num_size(txt)
	for l in _num_labels:
		l.text = txt
		l.add_theme_font_size_override("font_size", fs)

func _sync_viewport_size() -> void:
	if _vpc:
		_vpc.position = Vector2.ZERO
		_vpc.size = size
	if _vp:
		_vp.size = Vector2i(maxi(2, int(size.x)), maxi(2, int(size.y)))

# ---------------- build ----------------

func configure(count: int, colors: Array) -> void:
	_count = count
	_colors = colors.duplicate()
	if _wheel_root == null:
		_build_shell()
	_rebuild()

func _rebuild() -> void:
	for c in _wheel_root.get_children():
		c.queue_free()
	_segments.clear()
	_seg_mats.clear()
	_seg_base.clear()
	_emit_cur.clear()
	_emit_tgt.clear()
	_press.clear()

	_halos.clear()
	_halo_mats.clear()
	if _glow_tex == null:
		_glow_tex = _make_glow_tex()

	# --- premium graphite base plate + concentric machined rings ---
	# Graphite (never pure black), satin metal so it catches soft reflections.
	# Semi-metallic graphite: enough diffuse to read as a lit gray metal surface
	# (pure metal would only show dim reflections and look black).
	var base := _disc(BASE_R, BASE_H, Color(0.15, 0.155, 0.17), 0.45)
	(base.material_override as StandardMaterial3D).metallic = 0.4
	_wheel_root.add_child(base)

	# recessed dark groove just outside the buttons - reads as ambient occlusion
	var groove := MeshInstance3D.new()
	groove.mesh = _ring_mesh(OUTER_R, OUTER_R + 0.035, 0.16, 0.0)
	groove.position.y = 0.04
	groove.material_override = _metal_mat(Color(0.05, 0.05, 0.06), 0.3, 0.6)
	_wheel_root.add_child(groove)

	# raised beveled inner ring (machined lip)
	var ring_a := MeshInstance3D.new()
	ring_a.mesh = _ring_mesh(OUTER_R + 0.035, OUTER_R + 0.10, 0.22, 0.05)
	ring_a.position.y = 0.05
	ring_a.material_override = _metal_mat(Color(0.19, 0.195, 0.22), 0.45, 0.32)
	_wheel_root.add_child(ring_a)

	# outer rounded rim ring (catches the soft top highlight); thin overall frame
	var ring_b := MeshInstance3D.new()
	ring_b.mesh = _ring_mesh(OUTER_R + 0.095, OUTER_R + 0.16, 0.2, 0.07)
	ring_b.position.y = 0.03
	ring_b.material_override = _metal_mat(Color(0.23, 0.235, 0.26), 0.5, 0.26)
	_wheel_root.add_child(ring_b)

	# smaller glossy graphite center hub
	var hub := _disc(HUB_R, HUB_H, Color(0.11, 0.11, 0.14), 0.3)
	(hub.material_override as StandardMaterial3D).metallic = 0.5
	hub.position.y = 0.06
	_wheel_root.add_child(hub)

	var step := TAU / _count
	var gap := deg_to_rad(GAP_DEG)
	for i in _count:
		var a0 := _start_angle + i * step + gap * 0.5
		var a1 := _start_angle + (i + 1) * step - gap * 0.5
		var raw: Color = _colors[i % _colors.size()] if not _colors.is_empty() else Color.GRAY
		var col := _enrich(raw)   # richer + ~25% brighter so colors read clearly
		# dark metallic frame plate filling this slot (the button's own frame)
		var frame := MeshInstance3D.new()
		frame.mesh = _sector_mesh(a0, a1, INNER_R, OUTER_R, SEG_H)
		frame.position.y = BASE_H * 0.5
		frame.material_override = _metal_mat(Color(0.08, 0.08, 0.095), 0.3, 0.45)
		_wheel_root.add_child(frame)
		# inset, raised, glossy colored button sitting inside the frame: thick body,
		# a gently pillowed top and a soft rounded bevel wrapping the whole edge.
		var ba0 := a0 + deg_to_rad(BTN_ANG_MARGIN)
		var ba1 := a1 - deg_to_rad(BTN_ANG_MARGIN)
		var mesh := _sector_mesh(ba0, ba1, INNER_R + BTN_RAD_MARGIN, OUTER_R - BTN_RAD_MARGIN,
			SEG_H * 2.0, DOME, SIDE_DARK, BEVEL)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position.y = BASE_H * 0.5 + BTN_RAISE
		var mat := _seg_material(col, true)
		mi.material_override = mat
		_wheel_root.add_child(mi)
		_segments.append(mi)
		_seg_mats.append(mat)
		_seg_base.append(col)
		_emit_cur.append(EMIT_OFF)
		_emit_tgt.append(EMIT_OFF)
		_press.append(0.0)
		# soft additive glow halo over this segment (blooms outward when lit)
		var am := (a0 + a1) * 0.5
		var rm := (INNER_R + OUTER_R) * 0.5
		var halo := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(HALO_SIZE, HALO_SIZE)
		halo.mesh = q
		halo.rotation_degrees = Vector3(-90, 0, 0)   # lie flat, facing up
		# Sit above the frame (~0.20) but below the button's edge top (~0.305): the
		# button hides the bright core, only the soft outer falloff spills onto the
		# surrounding frame = light bleed.
		halo.position = Vector3(cos(am) * rm, 0.26, sin(am) * rm)
		var gmat := _halo_material(col)
		halo.material_override = gmat
		_wheel_root.add_child(halo)
		_halos.append(halo)
		_halo_mats.append(gmat)

# Glossy injection-molded ABS plastic. No textures, no triplanar, no rim - the
# form is carried entirely by geometry and lighting. A clearcoat gives the thin
# clear-gloss top layer real buttons have; vertex colors only darken the side
# walls (baked-in AO), never adding visible pattern.
func _seg_material(col: Color, use_vcol: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.vertex_color_use_as_albedo = use_vcol  # darkens side/recessed faces only
	m.metallic = 0.0                         # dielectric ABS plastic, not metal
	m.roughness = 0.3                        # clean satin gloss (broad highlight)
	m.specular = 0.65
	m.clearcoat_enabled = true               # thin clear gloss coat
	m.clearcoat = 0.3
	m.clearcoat_roughness = 0.1
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = EMIT_OFF
	return m

# Richer, brighter version of a base color (more saturation + value, with a
# brightness floor) so inactive buttons read clearly and look premium instead of
# dark/desaturated.
func _enrich(c: Color) -> Color:
	var s := clampf(c.s * 1.1, 0.0, 1.0)
	var v := clampf(maxf(c.v * 1.35, 0.55), 0.0, 1.0)
	return Color.from_hsv(c.h, s, v, c.a)

# The lit-state albedo: a moderately brighter, slightly more saturated version of
# the (already enriched) base - never lerped toward white, so it stays the color.
func _lit_color(c: Color) -> Color:
	var s := clampf(c.s * 1.05, 0.0, 1.0)
	var v := clampf(c.v * 1.18, 0.0, 1.0)
	return Color.from_hsv(c.h, s, v, c.a)

func _metal_mat(col: Color, metal: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metal
	m.roughness = rough
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _disc(radius: float, height: float, col: Color, rough: float) -> MeshInstance3D:
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 48
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = 0.2
	m.roughness = rough
	mi.material_override = m
	return mi

# Full-circle rounded rim (domed across the radius only -> no seam).
func _ring_mesh(ri: float, ro: float, h: float, dome_h: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := h * 0.5
	var bot := -h * 0.5
	var steps := 96
	for j in steps:
		var a0: float = TAU * float(j) / steps
		var a1: float = TAU * float(j + 1) / steps
		for jr in RADIAL_STEPS:
			var t0 := float(jr) / RADIAL_STEPS
			var t1 := float(jr + 1) / RADIAL_STEPS
			var r0: float = lerp(ri, ro, t0)
			var r1: float = lerp(ri, ro, t1)
			var y0: float = top + dome_h * sin(PI * t0)
			var y1: float = top + dome_h * sin(PI * t1)
			var p00 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
			var p10 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
			var p11 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
			var p01 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
			var n := (p10 - p00).cross(p01 - p00).normalized()
			if n.y < 0.0:
				n = -n
			_quad(st, p00, p10, p11, p01, n)
		var nrm := (Vector3(cos(a0), 0, sin(a0)) + Vector3(cos(a1), 0, sin(a1))).normalized()
		# outer wall
		_quad(st,
			Vector3(cos(a0) * ro, bot, sin(a0) * ro), Vector3(cos(a1) * ro, bot, sin(a1) * ro),
			Vector3(cos(a1) * ro, top, sin(a1) * ro), Vector3(cos(a0) * ro, top, sin(a0) * ro), nrm)
		# inner wall
		_quad(st,
			Vector3(cos(a0) * ri, top, sin(a0) * ri), Vector3(cos(a1) * ri, top, sin(a1) * ri),
			Vector3(cos(a1) * ri, bot, sin(a1) * ri), Vector3(cos(a0) * ri, bot, sin(a0) * ri), -nrm)
	return st.commit()

# Soft radial gradient (white center -> transparent edge) for glow billboards.
func _make_glow_tex() -> Texture2D:
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := Vector2(s, s) * 0.5
	for y in s:
		for x in s:
			var d := Vector2(x, y).distance_to(c) / (s * 0.5)
			var a := pow(clampf(1.0 - d, 0.0, 1.0), 1.5)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)

func _halo_material(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = _glow_tex
	m.albedo_color = Color(col.r, col.g, col.b, 0.0)   # invisible until lit
	return m

# Annular sector shaped like a real molded button: a gently pillowed top that
# rolls off into a soft rounded bevel around the entire edge, then drops to a
# short vertical wall and end caps. The bevel ends at y = wall_top, so the top
# surface meets the walls smoothly (no hard crease).
func _sector_mesh(a0: float, a1: float, ri: float, ro: float, h: float,
		dome: float = DOME, side_dark: float = 1.0, bevel: float = 0.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := h * 0.5
	var bot := -h * 0.5
	var wall_top := top - bevel                          # bevel ends here, wall begins
	var side := Color(side_dark, side_dark, side_dark)   # outer side-wall tint
	# inner + cap walls are more occluded -> darker (baked-in ambient occlusion)
	var k_in := side_dark * 0.72
	var side_in := Color(k_in, k_in, k_in)
	# pillowed + beveled top face (radial x arc grid). Vertices move in Y only;
	# the dense grid + smoothly varying normals read as a rounded bevel.
	for jr in RADIAL_STEPS:
		var r0: float = lerp(ri, ro, float(jr) / RADIAL_STEPS)
		var r1: float = lerp(ri, ro, float(jr + 1) / RADIAL_STEPS)
		for ja in ARC_STEPS:
			var aa0: float = lerp(a0, a1, float(ja) / ARC_STEPS)
			var aa1: float = lerp(a0, a1, float(ja + 1) / ARC_STEPS)
			var p00 := _dome_pt(aa0, r0, a0, a1, ri, ro, top, dome, bevel)
			var p10 := _dome_pt(aa1, r0, a0, a1, ri, ro, top, dome, bevel)
			var p11 := _dome_pt(aa1, r1, a0, a1, ri, ro, top, dome, bevel)
			var p01 := _dome_pt(aa0, r1, a0, a1, ri, ro, top, dome, bevel)
			var n := (p10 - p00).cross(p01 - p00).normalized()
			if n.y < 0.0:
				n = -n
			_quad(st, p00, p10, p11, p01, n)
	# walls + caps - the bevel drops onto these short vertical faces
	for j in ARC_STEPS:
		var b0: float = lerp(a0, a1, float(j) / ARC_STEPS)
		var b1: float = lerp(a0, a1, float(j + 1) / ARC_STEPS)
		var nrm := (Vector3(cos(b0), 0, sin(b0)) + Vector3(cos(b1), 0, sin(b1))).normalized()
		# outer wall
		_quad(st, _p(b0, ro, bot), _p(b1, ro, bot), _p(b1, ro, wall_top), _p(b0, ro, wall_top), nrm, side)
		# inner wall (recessed, near the hub -> darker)
		_quad(st, _p(b0, ri, wall_top), _p(b1, ri, wall_top), _p(b1, ri, bot), _p(b0, ri, bot), -nrm, side_in)
	# end caps (sit in the gaps between buttons -> recessed, darker)
	var tan0 := Vector3(-sin(a0), 0, cos(a0))
	_quad(st, _p(a0, ri, bot), _p(a0, ro, bot), _p(a0, ro, wall_top), _p(a0, ri, wall_top), -tan0, side_in)
	var tan1 := Vector3(-sin(a1), 0, cos(a1))
	_quad(st, _p(a1, ri, wall_top), _p(a1, ro, wall_top), _p(a1, ro, bot), _p(a1, ri, bot), tan1, side_in)
	return st.commit()

func _p(angle: float, r: float, y: float) -> Vector3:
	return Vector3(cos(angle) * r, y, sin(angle) * r)

# Rounded-shoulder falloff: 1.0 across the plateau, easing to 0.0 at an edge with
# a vertical tangent (quarter-circle), so the bevel meets the wall smoothly. `d`
# is the normalized distance to the nearest edge along one axis (0 = at edge).
func _shoulder(d: float) -> float:
	if d >= BEVEL_ZONE:
		return 1.0
	var u := d / BEVEL_ZONE                  # 0 at edge -> 1 at plateau
	return sqrt(maxf(0.0, 1.0 - (1.0 - u) * (1.0 - u)))

# A point on the button top. `f` is a rounded square-plateau mask (0 at every
# edge/corner, 1 over the middle): edges drop by `bevel` (rounded shoulder),
# while a gentle `dome` pillow lifts the plateau center. Walls stay flush at
# y = top - bevel because f = 0 there.
func _dome_pt(angle: float, r: float, a0: float, a1: float,
		ri: float, ro: float, top: float, dome: float = DOME,
		bevel: float = 0.0) -> Vector3:
	var tr := (r - ri) / (ro - ri)
	var ta := (angle - a0) / (a1 - a0)
	var f := _shoulder(minf(tr, 1.0 - tr)) * _shoulder(minf(ta, 1.0 - ta))
	var pillow := sin(PI * tr) * sin(PI * ta)
	var y := top - bevel * (1.0 - f) + dome * pillow
	return Vector3(cos(angle) * r, y, sin(angle) * r)

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3,
		col: Color = Color.WHITE) -> void:
	for v in [a, b, c]:
		st.set_color(col); st.set_normal(n); st.add_vertex(v)
	for v in [a, c, d]:
		st.set_color(col); st.set_normal(n); st.add_vertex(v)

# ---------------- runtime ----------------

func set_lit(idx: int, on: bool) -> void:
	if idx < 0 or idx >= _emit_tgt.size():
		return
	_emit_tgt[idx] = EMIT_ON if on else EMIT_OFF

func set_press(idx: int, amount: float) -> void:
	if idx < 0 or idx >= _press.size():
		return
	_press[idx] = clampf(amount, 0.0, 1.0)

func _process(dt: float) -> void:
	for i in _seg_mats.size():
		var k := clampf(dt * GLOW_LERP, 0.0, 1.0)
		_emit_cur[i] = lerp(_emit_cur[i], _emit_tgt[i], k)
		var mat := _seg_mats[i]
		mat.emission_energy_multiplier = _emit_cur[i]
		var base: Color = _seg_base[i] if i < _seg_base.size() else Color.GRAY
		# lit_amount is measured ABOVE the idle floor, so idle = 0 (no halo / no
		# extra brightening) while the emission floor still keeps colors visible.
		var lit_amount := clampf((_emit_cur[i] - EMIT_OFF) / (EMIT_ON - EMIT_OFF), 0.0, 1.0)
		# Lit = illuminated from within: brighten + slightly saturate the whole
		# surface (not toward white), so it glows richly without washing out. The
		# emission energy above does the internal-glow part; gloss/specular survive.
		mat.albedo_color = base.lerp(_lit_color(base), lit_amount)
		# fade the glow halo in/out
		if i < _halo_mats.size():
			var hc := _halo_mats[i].albedo_color
			hc.a = lit_amount * HALO_ALPHA
			_halo_mats[i].albedo_color = hc
		# press sink
		_segments[i].position.y = BASE_H * 0.5 + BTN_RAISE - _press[i] * PRESS_DROP

# ---------------- hit testing ----------------

# Maps a tap (in this Control's local coords) to a segment index, or -1.
# Works regardless of camera tilt by intersecting the camera ray with the
# wheel's top plane and reading polar coords in wheel space.
func segment_at_point(local_pos: Vector2) -> int:
	if _cam == null or _count == 0:
		return -1
	var vp_scale := Vector2(_vp.size) / size
	var vpp := local_pos * vp_scale
	var origin := _cam.project_ray_origin(vpp)
	var dir := _cam.project_ray_normal(vpp)
	var plane_y := BASE_H * 0.5 + SEG_H * 0.5
	if absf(dir.y) < 0.0001:
		return -1
	var dist := (plane_y - origin.y) / dir.y
	if dist <= 0.0:
		return -1
	var hit := origin + dir * dist
	var r := sqrt(hit.x * hit.x + hit.z * hit.z)
	if r < INNER_R or r > OUTER_R:
		return -1
	var ang := atan2(hit.z, hit.x) - _start_angle
	ang = fposmod(ang, TAU)
	return int(ang / (TAU / _count)) % _count
