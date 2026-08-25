extends Control
class_name ButtonFramePreview

# Shop thumbnail for a button-frame cosmetic: ONE real button from the Medium
# board, lit by the same studio the game lights it with, wearing the frame the card
# is selling.
#
# It is the actual GLB button wearing the actual Blender cosmetic mesh — not a
# redraw of either — so what the shop shows is exactly what gets equipped, down to
# the frame's cut accent channel and raised trim lip. It stands in for
# the Hard board's buttons too: that GLB authors the same bezel, vertex for vertex,
# so one preview is honest for both. The rest of the
# board is discarded at build time: instantiate the model, keep the Crimson button's
# subtree, free everything else.
#
# STATIC by construction. The viewport renders one settled frame whenever something
# actually changes (the frame is set, or the container is resized) and is idle the
# rest of the time — sixteen of these cost sixteen renders for the life of the shop,
# not sixteen per frame. The cosmetics' idle breathing runs on TIME inside their
# shader, so a card shows one settled phase of it; paying 16 continuously animating
# 3D viewports to see a +-14% swell would be a poor trade, and the effect is on the
# board itself where it belongs.
#
# The environment and the two lights are MemoryGameUI's own, so the preview cannot
# drift away from the studio the device is actually lit in. Only the camera differs,
# and deliberately — see the framing note below.

const MODEL: PackedScene = preload("res://models/MemoryGame_UI_Medium.glb")

# Which button the preview shows. Crimson is the front-left one on the board, and
# its deep red reads against all fifteen cosmetics without competing with them.
const PREVIEW_KEY := "Crimson"

# Framing. The card is 260x152, and what it has to sell is a ring 0.194 wide sitting
# around a button 1.5 across — so the camera is pulled in tighter than the game's
# and dropped to a lower elevation than the board's 33.86°. That lower angle is the
# whole point: it is what puts the frame's SIDE in view, which is where the cut
# accent channel and the raised trim lip live, and it is what separates Purple Neon
# from Cyan Neon at thumbnail size. The button's own proportions are untouched —
# this is the same mesh, at the same scale, seen from a different seat.
const FOV := 40.0                     # horizontal, with KEEP_WIDTH
const FILL := 0.96                    # fraction of the shorter axis the button fills
const CAM_ELEV_DEG := 25.0
const TARGET := Vector3(0.0, 0.16, 0.0)

var _vpc: SubViewportContainer
var _vp: SubViewport
var _cam: Camera3D
var _button: Node3D
var _frame_mi: MeshInstance3D
var _frame_id := ButtonFrames.DEFAULT_ID
var _fitted_size := Vector2i.ZERO

# The stock button, kept out of the board once and duplicated per card. The shop
# builds sixteen of these tiles at a time; instantiating an 850 KB board scene
# sixteen times to throw away four fifths of it each time is the whole cost of
# opening the tab, and every copy is identical anyway.
static var _template: Node3D

static func _button_template() -> Node3D:
	if _template != null and is_instance_valid(_template):
		return _template
	var board := MODEL.instantiate() as Node3D
	var src := board.find_child("Button_%s" % PREVIEW_KEY, true, false) as Node3D
	if src != null:
		_template = src.duplicate() as Node3D
		_template.position = Vector3.ZERO
	board.free()
	return _template

# The template is deliberately an orphan node, so somebody has to let it go: the
# shop calls this as it closes, in the same breath as ButtonFrames.trim_cache().
static func release_template() -> void:
	if _template != null and is_instance_valid(_template):
		_template.free()
	_template = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _vpc == null:
		_build()

func _build() -> void:
	_vpc = SubViewportContainer.new()
	_vpc.stretch = true
	_vpc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vpc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Premultiplied alpha, for the same reason the device uses it: a transparent
	# SubViewport hands back colour already multiplied by coverage.
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	_vpc.material = cm
	add_child(_vpc)

	_vp = SubViewport.new()
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vpc.add_child(_vp)

	_build_environment()
	_build_lights()

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.keep_aspect = Camera3D.KEEP_WIDTH
	_cam.fov = FOV
	_cam.near = 0.05
	_cam.far = 40.0
	_vp.add_child(_cam)

	# One real button out of the model, with the rest of the board dropped.
	var src := _button_template()
	if src != null:
		_button = src.duplicate() as Node3D
		_vp.add_child(_button)
		_frame_mi = _button.find_child("Button_%s_Frame" % PREVIEW_KEY, true, false) as MeshInstance3D

	_apply_frame()

# The device's own studio: a dark room where the frames (metallic 0.9) are lit
# almost entirely by specular, and AgX at exposure 0.40 does the rest.
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.56, 0.60, 0.70)
	sky_mat.sky_horizon_color = Color(0.26, 0.28, 0.33)
	sky_mat.ground_horizon_color = Color(0.14, 0.15, 0.18)
	sky_mat.ground_bottom_color = Color(0.04, 0.04, 0.05)
	sky_mat.sun_angle_max = 30.0
	sky_mat.sun_curve = 0.15
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 1.0, 1.0)
	env.ambient_light_energy = 0.13
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 0.40
	env.glow_enabled = false

	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)

func _build_lights() -> void:
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42.0, -34.0, 0.0)
	key.light_energy = 0.14
	key.light_specular = 1.5
	key.light_color = Color(1.0, 0.99, 0.97)
	key.shadow_enabled = false
	_vp.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-16.0, 158.0, 0.0)
	fill.light_energy = 0.05
	fill.light_specular = 1.2
	fill.light_color = Color(0.80, 0.86, 1.0)
	fill.shadow_enabled = false
	_vp.add_child(fill)

# ---------------- public API ----------------

# Wear a cosmetic. Cheap and idempotent; re-renders one frame.
func set_frame(frame_id: String) -> void:
	if frame_id == _frame_id and _frame_mi != null:
		return
	_frame_id = frame_id
	_apply_frame()

# Wear the cosmetic the same way the real board does — the actual Blender mesh
# added at the identity transform under the button, with the stock bezel's metal
# made invisible and its under-glow left showing. Nothing here approximates the
# cosmetic; the card is showing the thing that gets equipped.
func _apply_frame() -> void:
	if _frame_mi == null or _button == null:
		return
	var worn := _button.get_node_or_null(ButtonFrames.INSTANCE_NAME) as MeshInstance3D
	if worn != null:
		_button.remove_child(worn)
		worn.queue_free()
	if ButtonFrames.is_cosmetic(_frame_id):
		var mi := ButtonFrames.make_frame_instance(_frame_id)
		if mi != null:
			_button.add_child(mi)
			_frame_mi.set_surface_override_material(0, ButtonFrames.hidden_material())
		else:
			_frame_mi.set_surface_override_material(0, null)
	else:
		_frame_mi.set_surface_override_material(0, null)
	_kick()

# ---------------- framing + redraw ----------------

# The SubViewport takes its size from the stretching container a frame or more AFTER
# this Control is sized, so the fit can't be done once in _build — it would fit a 2x2
# placeholder. Re-fit (and re-render) the moment a real size lands, and whenever it
# changes after that.
func _process(_delta: float) -> void:
	if _vp == null:
		return
	if _vp.size != _fitted_size and _vp.size.x > 2 and _vp.size.y > 2:
		_fitted_size = _vp.size
		_fit_camera()
		_kick()

# Pull the camera back along the device's elevation until the button fits both axes.
func _fit_camera() -> void:
	var half_fov := deg_to_rad(FOV) * 0.5
	var aspect := float(_fitted_size.x) / maxf(1.0, float(_fitted_size.y))
	# Half-extents of the button as it presents at this elevation: full radius across,
	# radius foreshortened by sin(elev) plus the bezel's height going up the frame.
	var e := deg_to_rad(CAM_ELEV_DEG)
	var half_w := 0.98
	var half_h := 0.98 * sin(e) + 0.30
	var dist_w := half_w / (FILL * tan(half_fov))
	var dist_h := half_h / (FILL * tan(half_fov) / aspect)
	var dist := maxf(dist_w, dist_h)
	var pos := TARGET + Vector3(0.0, sin(e), cos(e)) * dist
	_cam.look_at_from_position(pos, TARGET, Vector3.UP)

# Render exactly one frame. UPDATE_ONCE reverts to disabled by itself afterwards.
func _kick() -> void:
	if _vp != null:
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
