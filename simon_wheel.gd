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
# Renderer note: project uses gl_compatibility, where Environment glow is
# unreliable. The glow here comes from emissive materials + lighting, which
# works on every renderer. Environment glow is enabled too as a bonus when
# the device supports it.

# ---- tunables (wheel is built in local units, ring outer radius = 1.0) ----
const OUTER_R := 1.0
const INNER_R := 0.42
const SEG_H := 0.16          # segment thickness (depth)
const BASE_R := 1.14         # dark body disc radius
const BASE_H := 0.20
const HUB_R := 0.40
const HUB_H := 0.24
const GAP_DEG := 6.0         # angular gap between segments
const ARC_STEPS := 10        # arc tessellation per segment
const RADIAL_STEPS := 6      # radial tessellation of the domed top
const DOME := 0.05           # how much the button top bulges (pillow look)

const EMIT_ON := 4.0         # emission energy when lit
const EMIT_OFF := 0.0
const GLOW_LERP := 14.0      # how fast glow rises/falls
const PRESS_DROP := 0.06     # how far a pressed segment sinks (local units)
const HALO_SIZE := 2.0       # size of the soft glow billboard over a segment
const HALO_ALPHA := 0.4      # peak glow strength when fully lit (real bloom adds more)
# Each colored button is inset inside its slot, leaving a dark metal frame
# border around it, and raised so it sits proud of the frame.
const BTN_ANG_MARGIN := 1.6  # degrees trimmed from each angular side
const BTN_RAD_MARGIN := 0.05 # radial inset
const BTN_RAISE := 0.05      # how far the button sits above the frame plate
const SIDE_DARK := 0.42      # side-wall brightness vs the top face (3D feel)
# White top-edge highlight, per edge (currently tuned on the orange button).
const FOCUS_COLOR := Color(0.95, 0.5, 0.1)  # orange
const GLOW_OUTER := 0.85     # long outer edge - strong
const GLOW_INNER := 0.1      # short inner edge (toward center) - very low
const GLOW_SIDE := 0.45      # the two radial side edges - medium

# Camera framing (slight tilt for a 3D feel while keeping hit-testing simple).
# Distance chosen so the full wheel (radius ~1.14) fits with margin for glow.
const CAM_POS := Vector3(0.0, 4.6, 1.7)
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
var _emit_cur: Array[float] = []
var _emit_tgt: Array[float] = []
var _press: Array[float] = []
var _halos: Array[MeshInstance3D] = []
var _halo_mats: Array[StandardMaterial3D] = []
var _glow_tex: Texture2D

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
	env.ambient_light_energy = 0.35
	# real bloom, but with a high threshold so ONLY truly-lit segments bloom -
	# the regular button colors must not glow in idle.
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 1.4
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
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
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-58, -32, 0)
	key.light_energy = 1.1
	key.light_color = Color(1.0, 0.97, 0.92)
	_vp.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-40, 145, 0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.6, 0.7, 1.0)
	_vp.add_child(fill)

	# tight overhead light for a hot specular highlight on the glossy tops
	var spec := OmniLight3D.new()
	spec.position = Vector3(0.25, 2.4, 0.15)
	spec.omni_range = 7.0
	spec.light_energy = 0.9
	spec.light_specular = 1.0
	spec.light_color = Color(1.0, 1.0, 1.0)
	_vp.add_child(spec)

	_wheel_root = Node3D.new()
	_vp.add_child(_wheel_root)

	_sync_viewport_size()

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
	_emit_cur.clear()
	_emit_tgt.clear()
	_press.clear()

	_halos.clear()
	_halo_mats.clear()
	if _glow_tex == null:
		_glow_tex = _make_glow_tex()

	# dark plate the buttons sit in (kept small so it doesn't read as a dome)
	var base := _disc(1.02, BASE_H, Color(0.03, 0.03, 0.04), 0.4)
	(base.material_override as StandardMaterial3D).metallic = 0.6
	_wheel_root.add_child(base)

	# raised inner lip where the frame meets the buttons
	var lip := MeshInstance3D.new()
	lip.mesh = _ring_mesh(1.0, 1.06, 0.22, 0.05)
	lip.position.y = 0.05
	lip.material_override = _metal_mat(Color(0.16, 0.16, 0.2), 1.0, 0.12)
	_wheel_root.add_child(lip)

	# main outer frame ring: wide, flat-ish, polished dark metal (low roughness
	# = sharp reflections so it catches a bright highlight arc on top)
	var bezel := MeshInstance3D.new()
	bezel.mesh = _ring_mesh(1.05, 1.34, 0.26, 0.10)
	bezel.position.y = 0.04
	bezel.material_override = _metal_mat(Color(0.13, 0.13, 0.16), 1.0, 0.12)
	_wheel_root.add_child(bezel)

	# brighter polished outer edge for a defined machined rim
	var rim := MeshInstance3D.new()
	rim.mesh = _ring_mesh(1.30, 1.40, 0.18, 0.05)
	rim.position.y = 0.0
	rim.material_override = _metal_mat(Color(0.2, 0.2, 0.24), 1.0, 0.1)
	_wheel_root.add_child(rim)

	# center hub
	var hub := _disc(HUB_R, HUB_H, Color(0.04, 0.04, 0.07), 0.25)
	(hub.material_override as StandardMaterial3D).metallic = 0.9
	hub.position.y = 0.06
	_wheel_root.add_child(hub)

	var step := TAU / _count
	var gap := deg_to_rad(GAP_DEG)
	for i in _count:
		var a0 := _start_angle + i * step + gap * 0.5
		var a1 := _start_angle + (i + 1) * step - gap * 0.5
		var col: Color = _colors[i % _colors.size()] if not _colors.is_empty() else Color.GRAY
		# dark metallic frame plate filling this slot (the button's own frame)
		var frame := MeshInstance3D.new()
		frame.mesh = _sector_mesh(a0, a1, INNER_R, OUTER_R, SEG_H)
		frame.position.y = BASE_H * 0.5
		frame.material_override = _metal_mat(Color(0.05, 0.05, 0.065), 0.85, 0.3)
		_wheel_root.add_child(frame)
		# inset, raised, glossy colored button sitting inside the frame:
		# extra dome + height and darker side faces for a real beveled-button feel.
		var is_focus := col.is_equal_approx(FOCUS_COLOR)
		var ba0 := a0 + deg_to_rad(BTN_ANG_MARGIN)
		var ba1 := a1 - deg_to_rad(BTN_ANG_MARGIN)
		var ri_b := INNER_R + BTN_RAD_MARGIN
		var ro_b := OUTER_R - BTN_RAD_MARGIN
		var mesh := _sector_mesh(ba0, ba1, ri_b, ro_b, SEG_H * 1.6, DOME * 2.4, SIDE_DARK)
		var mat := _seg_material(col, true)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position.y = BASE_H * 0.5 + BTN_RAISE
		mi.material_override = mat
		if is_focus:
			# orange: glowing white highlight ribbons along the top edges
			mi.add_child(_edge_highlight(ba0, ba1, ri_b, ro_b, SEG_H * 1.6 * 0.5, DOME * 2.4))
		_wheel_root.add_child(mi)
		_segments.append(mi)
		_seg_mats.append(mat)
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
		halo.position = Vector3(cos(am) * rm, 0.34, sin(am) * rm)
		var gmat := _halo_material(col)
		halo.material_override = gmat
		_wheel_root.add_child(halo)
		_halos.append(halo)
		_halo_mats.append(gmat)

func _seg_material(col: Color, use_vcol: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.vertex_color_use_as_albedo = use_vcol  # lets the mesh darken side faces
	m.metallic = 0.55                        # metallic-tinted colored surface
	m.roughness = 0.2
	m.specular = 0.6
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.rim_enabled = true                     # soft edge sheen
	m.rim = 0.4
	m.rim_tint = 0.3
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = EMIT_OFF
	return m

# Unshaded additive material for the glowing white edge ribbons. Per-vertex
# alpha (white rgb) controls glow strength, so it emits regardless of lighting.
func _edge_glow_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color.WHITE
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

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
			var a := pow(clampf(1.0 - d, 0.0, 1.0), 2.2)
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

# Annular sector with a domed (pillow) top, vertical walls and end caps.
# The dome is 0 at every edge, so the top stays continuous with the walls.
func _sector_mesh(a0: float, a1: float, ri: float, ro: float, h: float,
		dome: float = DOME, side_dark: float = 1.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := h * 0.5
	var bot := -h * 0.5
	var side := Color(side_dark, side_dark, side_dark)   # darker side-wall tint
	# domed top face (radial x arc grid) - keeps full (white) vertex color
	for jr in RADIAL_STEPS:
		var r0: float = lerp(ri, ro, float(jr) / RADIAL_STEPS)
		var r1: float = lerp(ri, ro, float(jr + 1) / RADIAL_STEPS)
		for ja in ARC_STEPS:
			var aa0: float = lerp(a0, a1, float(ja) / ARC_STEPS)
			var aa1: float = lerp(a0, a1, float(ja + 1) / ARC_STEPS)
			var p00 := _dome_pt(aa0, r0, a0, a1, ri, ro, top, dome)
			var p10 := _dome_pt(aa1, r0, a0, a1, ri, ro, top, dome)
			var p11 := _dome_pt(aa1, r1, a0, a1, ri, ro, top, dome)
			var p01 := _dome_pt(aa0, r1, a0, a1, ri, ro, top, dome)
			var n := (p10 - p00).cross(p01 - p00).normalized()
			if n.y < 0.0:
				n = -n
			_quad(st, p00, p10, p11, p01, n)
	# walls + caps - tinted darker for a 3D bevel feel
	for j in ARC_STEPS:
		var b0: float = lerp(a0, a1, float(j) / ARC_STEPS)
		var b1: float = lerp(a0, a1, float(j + 1) / ARC_STEPS)
		var nrm := (Vector3(cos(b0), 0, sin(b0)) + Vector3(cos(b1), 0, sin(b1))).normalized()
		# outer wall
		_quad(st, _p(b0, ro, bot), _p(b1, ro, bot), _p(b1, ro, top), _p(b0, ro, top), nrm, side)
		# inner wall
		_quad(st, _p(b0, ri, top), _p(b1, ri, top), _p(b1, ri, bot), _p(b0, ri, bot), -nrm, side)
	# end caps
	var tan0 := Vector3(-sin(a0), 0, cos(a0))
	_quad(st, _p(a0, ri, bot), _p(a0, ro, bot), _p(a0, ro, top), _p(a0, ri, top), -tan0, side)
	var tan1 := Vector3(-sin(a1), 0, cos(a1))
	_quad(st, _p(a1, ri, top), _p(a1, ro, top), _p(a1, ro, bot), _p(a1, ri, bot), tan1, side)
	return st.commit()

# Glowing white highlight ribbons hugging the four top edges of a button.
# Each ribbon is brightest right at the edge (alpha = per-edge intensity) and
# fades to transparent inward. Built in the button's local space, lifted just
# above the domed top. Returns a MeshInstance3D to parent to the button.
func _edge_highlight(a0: float, a1: float, ri: float, ro: float,
		top: float, dome: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := Vector3.UP
	var rim_w := 0.07                 # ribbon width (radial)
	var rim_a := deg_to_rad(4.5)      # ribbon width (angular, for side edges)
	var lift := 0.006
	var co := Color(1, 1, 1, GLOW_OUTER)
	var ci := Color(1, 1, 1, GLOW_INNER)
	var cs := Color(1, 1, 1, GLOW_SIDE)
	var clear := Color(1, 1, 1, 0.0)
	# outer arc edge (strong)
	for j in ARC_STEPS:
		var b0: float = lerp(a0, a1, float(j) / ARC_STEPS)
		var b1: float = lerp(a0, a1, float(j + 1) / ARC_STEPS)
		_quad_c(st, _rim_pt(b0, ro, a0, a1, ri, ro, top, dome, lift),
			_rim_pt(b1, ro, a0, a1, ri, ro, top, dome, lift),
			_rim_pt(b1, ro - rim_w, a0, a1, ri, ro, top, dome, lift),
			_rim_pt(b0, ro - rim_w, a0, a1, ri, ro, top, dome, lift), n, co, co, clear, clear)
	# inner arc edge (faint)
	for j in ARC_STEPS:
		var b0: float = lerp(a0, a1, float(j) / ARC_STEPS)
		var b1: float = lerp(a0, a1, float(j + 1) / ARC_STEPS)
		_quad_c(st, _rim_pt(b0, ri, a0, a1, ri, ro, top, dome, lift),
			_rim_pt(b1, ri, a0, a1, ri, ro, top, dome, lift),
			_rim_pt(b1, ri + rim_w, a0, a1, ri, ro, top, dome, lift),
			_rim_pt(b0, ri + rim_w, a0, a1, ri, ro, top, dome, lift), n, ci, ci, clear, clear)
	# two radial side edges (medium)
	for j in RADIAL_STEPS:
		var r0: float = lerp(ri, ro, float(j) / RADIAL_STEPS)
		var r1: float = lerp(ri, ro, float(j + 1) / RADIAL_STEPS)
		_quad_c(st, _rim_pt(a0, r0, a0, a1, ri, ro, top, dome, lift),
			_rim_pt(a0, r1, a0, a1, ri, ro, top, dome, lift),
			_rim_pt(a0 + rim_a, r1, a0, a1, ri, ro, top, dome, lift),
			_rim_pt(a0 + rim_a, r0, a0, a1, ri, ro, top, dome, lift), n, cs, cs, clear, clear)
		_quad_c(st, _rim_pt(a1, r0, a0, a1, ri, ro, top, dome, lift),
			_rim_pt(a1, r1, a0, a1, ri, ro, top, dome, lift),
			_rim_pt(a1 - rim_a, r1, a0, a1, ri, ro, top, dome, lift),
			_rim_pt(a1 - rim_a, r0, a0, a1, ri, ro, top, dome, lift), n, cs, cs, clear, clear)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _edge_glow_mat()
	return mi

func _rim_pt(angle: float, r: float, a0: float, a1: float, ri: float, ro: float,
		top: float, dome: float, lift: float) -> Vector3:
	var p := _dome_pt(angle, r, a0, a1, ri, ro, top, dome)
	p.y += lift
	return p

# Quad with a distinct color at each of the four corners.
func _quad_c(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3,
		ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	st.set_color(ca); st.set_normal(n); st.add_vertex(a)
	st.set_color(cb); st.set_normal(n); st.add_vertex(b)
	st.set_color(cc); st.set_normal(n); st.add_vertex(c)
	st.set_color(ca); st.set_normal(n); st.add_vertex(a)
	st.set_color(cc); st.set_normal(n); st.add_vertex(c)
	st.set_color(cd); st.set_normal(n); st.add_vertex(d)

func _p(angle: float, r: float, y: float) -> Vector3:
	return Vector3(cos(angle) * r, y, sin(angle) * r)

# A point on the domed top. bump peaks at the segment center and is 0 on all
# four edges, so walls/caps stay flush at y = top.
func _dome_pt(angle: float, r: float, a0: float, a1: float,
		ri: float, ro: float, top: float, dome: float = DOME) -> Vector3:
	var tr := (r - ri) / (ro - ri)
	var ta := (angle - a0) / (a1 - a0)
	var bump := sin(PI * tr) * sin(PI * ta)
	return Vector3(cos(angle) * r, top + dome * bump, sin(angle) * r)

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
		var base: Color = _colors[i % _colors.size()] if not _colors.is_empty() else Color.GRAY
		var lit_amount := clampf(_emit_cur[i] / EMIT_ON, 0.0, 1.0)
		# brighten albedo a touch while lit
		mat.albedo_color = base.lerp(base.lightened(0.35), lit_amount)
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
