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
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.5, 0.7)
	env.ambient_light_energy = 0.55
	env.glow_enabled = true            # bonus on renderers that support it
	env.glow_intensity = 0.9
	env.glow_bloom = 0.25
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
	key.light_energy = 1.15
	key.light_color = Color(1.0, 0.97, 0.92)
	_vp.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-40, 145, 0)
	fill.light_energy = 0.45
	fill.light_color = Color(0.6, 0.7, 1.0)
	_vp.add_child(fill)

	# tight overhead light for a hot specular highlight on the glossy tops
	var spec := OmniLight3D.new()
	spec.position = Vector3(0.25, 2.4, 0.15)
	spec.omni_range = 7.0
	spec.light_energy = 1.1
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

	# dark body disc under the buttons
	_wheel_root.add_child(_disc(BASE_R, BASE_H, Color(0.06, 0.06, 0.09), 0.6))
	# center hub
	var hub := _disc(HUB_R, HUB_H, Color(0.04, 0.04, 0.10), 0.5)
	hub.position.y = 0.02
	_wheel_root.add_child(hub)

	var step := TAU / _count
	var gap := deg_to_rad(GAP_DEG)
	for i in _count:
		var a0 := _start_angle + i * step + gap * 0.5
		var a1 := _start_angle + (i + 1) * step - gap * 0.5
		var col: Color = _colors[i % _colors.size()] if not _colors.is_empty() else Color.GRAY
		var mesh := _sector_mesh(a0, a1, INNER_R, OUTER_R, SEG_H)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position.y = BASE_H * 0.5
		var mat := _seg_material(col)
		mi.material_override = mat
		_wheel_root.add_child(mi)
		_segments.append(mi)
		_seg_mats.append(mat)
		_emit_cur.append(EMIT_OFF)
		_emit_tgt.append(EMIT_OFF)
		_press.append(0.0)

func _seg_material(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = 0.12
	m.roughness = 0.24                       # glossier plastic
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.rim_enabled = true                     # soft edge sheen
	m.rim = 0.5
	m.rim_tint = 0.2
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = EMIT_OFF
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

# Annular sector with a domed (pillow) top, vertical walls and end caps.
# The dome is 0 at every edge, so the top stays continuous with the walls.
func _sector_mesh(a0: float, a1: float, ri: float, ro: float, h: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := h * 0.5
	var bot := -h * 0.5
	# domed top face (radial x arc grid)
	for jr in RADIAL_STEPS:
		var r0: float = lerp(ri, ro, float(jr) / RADIAL_STEPS)
		var r1: float = lerp(ri, ro, float(jr + 1) / RADIAL_STEPS)
		for ja in ARC_STEPS:
			var aa0: float = lerp(a0, a1, float(ja) / ARC_STEPS)
			var aa1: float = lerp(a0, a1, float(ja + 1) / ARC_STEPS)
			var p00 := _dome_pt(aa0, r0, a0, a1, ri, ro, top)
			var p10 := _dome_pt(aa1, r0, a0, a1, ri, ro, top)
			var p11 := _dome_pt(aa1, r1, a0, a1, ri, ro, top)
			var p01 := _dome_pt(aa0, r1, a0, a1, ri, ro, top)
			var n := (p10 - p00).cross(p01 - p00).normalized()
			if n.y < 0.0:
				n = -n
			_quad(st, p00, p10, p11, p01, n)
	# walls + caps
	for j in ARC_STEPS:
		var b0: float = lerp(a0, a1, float(j) / ARC_STEPS)
		var b1: float = lerp(a0, a1, float(j + 1) / ARC_STEPS)
		var nrm := (Vector3(cos(b0), 0, sin(b0)) + Vector3(cos(b1), 0, sin(b1))).normalized()
		# outer wall
		_quad(st, _p(b0, ro, bot), _p(b1, ro, bot), _p(b1, ro, top), _p(b0, ro, top), nrm)
		# inner wall
		_quad(st, _p(b0, ri, top), _p(b1, ri, top), _p(b1, ri, bot), _p(b0, ri, bot), -nrm)
	# end caps
	var tan0 := Vector3(-sin(a0), 0, cos(a0))
	_quad(st, _p(a0, ri, bot), _p(a0, ro, bot), _p(a0, ro, top), _p(a0, ri, top), -tan0)
	var tan1 := Vector3(-sin(a1), 0, cos(a1))
	_quad(st, _p(a1, ri, top), _p(a1, ro, top), _p(a1, ro, bot), _p(a1, ri, bot), tan1)
	return st.commit()

func _p(angle: float, r: float, y: float) -> Vector3:
	return Vector3(cos(angle) * r, y, sin(angle) * r)

# A point on the domed top. bump peaks at the segment center and is 0 on all
# four edges, so walls/caps stay flush at y = top.
func _dome_pt(angle: float, r: float, a0: float, a1: float,
		ri: float, ro: float, top: float) -> Vector3:
	var tr := (r - ri) / (ro - ri)
	var ta := (angle - a0) / (a1 - a0)
	var bump := sin(PI * tr) * sin(PI * ta)
	return Vector3(cos(angle) * r, top + DOME * bump, sin(angle) * r)

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	for v in [a, b, c]:
		st.set_normal(n); st.add_vertex(v)
	for v in [a, c, d]:
		st.set_normal(n); st.add_vertex(v)

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
		# brighten albedo a touch while lit
		var base: Color = _colors[i % _colors.size()] if not _colors.is_empty() else Color.GRAY
		var lit_amount := clampf(_emit_cur[i] / EMIT_ON, 0.0, 1.0)
		mat.albedo_color = base.lerp(base.lightened(0.5), lit_amount)
		# press sink
		_segments[i].position.y = BASE_H * 0.5 - _press[i] * PRESS_DROP

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
