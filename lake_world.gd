extends Node3D
class_name LakeWorld

# MAGICAL LAKE — the gameplay background the lily-pad buttons float on.
#
# It is a third KIND of 3D background and the first one with no asset behind it at
# all: no .blend, no .glb, no image. The eight Themes1 floors are imported geometry
# (background_scenes.gd), the two Themes2 worlds are imported geometry with imported
# animation (world_scenes.gd), and this is a plane, a shader and a scatter of
# generated props. BackgroundScenes stays the single façade for all three; nothing
# outside it has to know which kind an id is.
#
# ---------------------------------------------------------------------------
# Why it is 3D when the eight LUMEO worlds are 2D
# ---------------------------------------------------------------------------
# lume_worlds.gd measured the reason a gameplay background usually has to be a
# canvas shader: the camera looks down ~33.5 deg through a ~25 deg lens, so the top
# of the frame is still ~18 deg BELOW the horizon and a prop standing at z = -4 has
# 0.45 m before its head leaves the picture. A world that needs a SKY cannot be
# built out here.
#
# A lake does not need one. The brief is a surface with no horizon that fills the
# whole frame, which is exactly the shape of frame that geometry measurement
# describes — and everything the lake has to do needs the buttons and the water to
# share one camera, one depth buffer and one tonemap:
#
#   * a pad must OCCLUDE the water behind it, and the water must run right up to
#     the pad's own outline;
#   * a press sinks the pad 11.5 cm THROUGH the surface (the Press_<Key> clip, not
#     touched), which only reads if the surface is at a real height in the same space;
#   * the ripple a press throws starts at that pad's world position;
#   * the coloured pool the board already lays on the ground (MemoryGameUI's
#     GLOW_*) has to land ON the water, which is what makes a lit pad tint the
#     water around it without a line of new colour plumbing.
#
# So it lives where the other 3D backgrounds live: inside MemoryGameUI's SubViewport
# as a sibling of the board, on BG_LAYER.
#
# ---------------------------------------------------------------------------
# Everything is unshaded
# ---------------------------------------------------------------------------
# Not a shortcut — it is the only way to be predictable here. The board's
# Environment is a dark studio with a bright ProceduralSky as its reflection source
# (there for the metallic bezels) and AgX at tonemap_exposure 0.40, and those are
# not ours to move: the exposure was swept against the BUTTONS' own reference
# render. A lit material in that room mirrors the sky and comes out grey (the trap
# background_scenes.gd documents as `ambient_light_disabled` being mandatory), and
# no light we add may touch a button.
#
# So every surface here computes its own shading — a lambert term against one
# authored sun direction, a fresnel term, a rim term — and writes the result
# straight out. No lights are built at all, which also means there is nothing to
# cull to a layer and nothing that can reach the board.
#
# ---------------------------------------------------------------------------
# The palette is authored on SCREEN, not in linear light
# ---------------------------------------------------------------------------
# AgX at exposure 0.40 is emphatically not a gamma curve: screen count 4 needs
# linear 0.100, count 128 needs 0.72, count 232 needs 2.61, and from ~4.5 up
# everything is white. Authoring a turquoise "in linear" and hoping is how a lake
# comes out either black or bleached.
#
# So the palette below is written as the sRGB the player is meant to SEE, and
# `tone()` converts each one to the radiance that produces it, once, at build time,
# using TONE_RAMP — which is measured, not modelled (tools/lake_tone.tscn renders
# a log2 ramp through the board's own Environment and prints the table back). The
# shader then only ever mixes radiances, which is what a renderer does anyway.

# The visual layer a background occupies. Declared again rather than imported so the
# dependency between the modules stays strictly one-way (BackgroundScenes -> here)
# and GDScript never has to resolve a cycle between two `class_name` scripts.
const BG_LAYER := 2

# ---------------------------------------------------------------------------
# Catalog
# ---------------------------------------------------------------------------
# The "world_" prefix is the one the Themes2 worlds established and is kept for the
# same reason: it clears BOTH namespaces already spent — "ocean" and "rainbow" are
# shader themes, "bg_crystal" is Crystal Cave, "lume_ocean" is a LUMEO world. This
# id is what saved wallets contain, so it is frozen once shipped.
const CATALOG := {
	"world_lake": {"name": "Magical Lake"},
}

const ORDER := ["world_lake"]

# ---------------------------------------------------------------------------
# The waterline
# ---------------------------------------------------------------------------
# The single most important number in the whole skin, and it is derived from the
# asset rather than chosen. The pad's underside is a bowl: y 0.000 at the middle,
# 0.090 at r 0.5, 0.118 at r 0.7, and the rim curls up to 0.267 at r 1.0. So a
# waterline at 0.095 crosses the pad's own underside at about r 0.55 — the middle
# of the pad sits IN the water and its curled edge rides above it, which is what a
# lily pad does.
#
# It also decides what a press looks like, for free. The Press_<Key> clip sinks the
# button surface 11.5 cm; from here that puts the pad's middle 2 cm under and leaves
# the rim 12 cm proud, so pressing a pad pushes it into the lake and it comes back
# up. Nothing about the clip, the board or the animation was touched to get that.
const WATER_Y := 0.095

# The plane is two triangles and its cost is per-pixel, so it is sized to run past
# the frame at every aspect on every board with nothing to think about. The far half
# is uniform haze long before it ends (see HAZE_*).
const WATER_SIZE := 90.0

# ---------------------------------------------------------------------------
# Palette, as sRGB on screen
# ---------------------------------------------------------------------------
# Rich turquoise near the board, deepening to a blue-green away from it, dissolving
# into the same tone the 2D layer is cleared to so the surface has no edge anywhere
# (the lesson lume_worlds.gd paid for twice: a surface that ends needs an edge, and
# an edge inside the frame is a line across the picture — so there isn't one).
const SHALLOW := Color8(46, 168, 158)
const DEEP := Color8(16, 84, 104)
const HAZE := Color8(11, 47, 66)
# What the sky puts back into the water at grazing angles, which at this camera is
# most of the far field. Cool and pale, and the reason the lake reads as wet.
const SKY := Color8(150, 214, 226)
# The warm half of the lighting: sun glints on the wave crests and the highlight
# that runs along a crest before it turns over.
const SUN := Color8(255, 244, 206)
# A magical lake is allowed one colour that water does not have. This is a very
# faint violet lift in the mid-distance, well under the buttons in strength.
const MAGIC := Color8(120, 96, 200)

# Where the depth ramp runs, in board units away from the camera (-z is away).
const DEPTH_NEAR := -1.0
const DEPTH_FAR := 11.0
# ...and where the whole thing has dissolved into HAZE. Well past the top of the
# frame on every board and aspect, so the dissolve is a gradient the player never
# sees the end of.
const HAZE_NEAR := 7.0
const HAZE_FAR := 24.0
# The same deepening applied sideways, which is what frames the play area: the
# middle of the lake stays bright and the gutters fall away.
const SIDE_NEAR := 3.4
const SIDE_FAR := 15.0

# The key light the DRESSING is shaded by: front-upper-left, so a reed or a stone
# is lit on the side the camera is on and reads as a solid object.
const SUN_DIR := Vector3(-0.42, 0.58, 0.70)

# And the direction the WATER takes its glint from, which is a different question
# with a measurable answer. A specular highlight appears where the half-vector
# between light and eye lines up with the surface normal, and this surface is
# horizontal — so the light has to be very nearly the MIRROR of the camera about
# the vertical, which at this 33.5 deg pose means low and on the FAR side of the
# lake.
#
# Not a preference. Lit from SUN_DIR the half-vector sits ~55 deg off the water's
# normal, `pow(dot, n)` is zero for any exponent worth using, and the lake renders
# as a flat wash with no highlight anywhere on it — which is exactly what the first
# build did. Mirrored, the half-vector is within 10 deg of vertical, the wave slopes
# cut it into a glitter path, and the water reads as water.
const GLINT_DIR := Vector3(-0.20, 0.56, -0.80)

# ---------------------------------------------------------------------------
# Animation
# ---------------------------------------------------------------------------
# The board's SubViewport deliberately does not redraw while nothing is moving, so
# an animated background is nudged at this rate instead (MemoryGameUI._tick_bg_idle).
# Water is the one thing that can never be still, so it takes the same 30 Hz the
# Themes2 worlds do rather than the floors' 15.
const IDLE_HZ := 30.0

# How long a press ripple lives. Only while one is running does anything here have a
# per-frame CPU cost at all — see Lake._process, which switches itself off.
const PRESS_LIFE := 1.7

# ---------------------------------------------------------------------------
# Measured inverse of the board's tone curve
# ---------------------------------------------------------------------------
# Linear radiance for screen counts 0, 4, 8 ... 256, through AgX at
# tonemap_exposure 0.40. Regenerate with tools/lake_tone.tscn if the board's
# Environment ever changes (it should not — see that harness's header).
const TONE_RAMP: Array = [
	0.00000, 0.10043, 0.12500, 0.14464, 0.16736, 0.18900, 0.20832, 0.22960,
	0.25306, 0.27387, 0.29460, 0.31690, 0.33718, 0.35744, 0.37801, 0.39685,
	0.41663, 0.43740, 0.45920, 0.47958, 0.50000, 0.52129, 0.54277, 0.56294,
	0.58386, 0.60555, 0.62741, 0.64809, 0.66945, 0.69152, 0.71431, 0.73785,
	0.76217, 0.78729, 0.81324, 0.84004, 0.86773, 0.89633, 0.92587, 0.95639,
	0.98791, 1.02047, 1.05625, 1.09549, 1.13620, 1.17841, 1.22219, 1.26760,
	1.31813, 1.37425, 1.43276, 1.49376, 1.56821, 1.64638, 1.72844, 1.83234,
	1.94247, 2.07431, 2.23132, 2.40021, 2.61347, 2.95141, 3.33305, 3.85670,
	4.46263,
]


# The linear radiance that this Environment turns into `c` on screen. Per channel,
# by lerping the measured ramp — the curve has a toe and a shoulder that are not one
# power law, and a cubic through it (which is what the first version of the probe
# fitted) lands eight or nine counts out through the mid-tones.
static func tone(c: Color) -> Vector3:
	return Vector3(_tone1(c.r), _tone1(c.g), _tone1(c.b))


static func _tone1(v: float) -> float:
	var x := clampf(v, 0.0, 1.0) * 255.0 / 4.0
	var i := int(floor(x))
	if i >= TONE_RAMP.size() - 1:
		return float(TONE_RAMP[TONE_RAMP.size() - 1])
	return lerpf(float(TONE_RAMP[i]), float(TONE_RAMP[i + 1]), x - float(i))


# ---------------------------------------------------------------------------
# Façade
# ---------------------------------------------------------------------------

static func has_scene(id: String) -> bool:
	return CATALOG.has(id)


static func display_name(id: String) -> String:
	return String(CATALOG.get(id, {}).get("name", id))


# What the 2D layer behind the board is cleared to. Returned in LINEAR light, which
# is the convention BackgroundScenes.backdrop_color already has (its callers apply
# linear_to_srgb to get a ColorRect's colour) — so the flat fill behind the viewport
# is exactly the tone the water dissolves into and no seam can appear at the edge of
# the board's silhouette.
static func backdrop_color(_id: String) -> Color:
	return Color(HAZE.r, HAZE.g, HAZE.b).srgb_to_linear()


# The lake is a surface, not an island: nothing stands on it near the buttons, it
# runs past the frame in every direction, and it is fitted by neither seating nor
# scaling. It answers the three geometry questions the same way a Themes1 floor
# does, except that its play surface is the WATERLINE rather than y = 0 — which is
# what puts the board's coloured pools on the water instead of under it.
static func pool_plane_y(id: String) -> float:
	return WATER_Y if CATALOG.has(id) else 0.0


# No edge, so no clip: the pools' own GLOW_R_CUT is what ends them.
static func pool_radius(_id: String) -> float:
	return 0.0


# ...but a good deal less of one. See BackgroundScenes.pool_gain: the pools were
# fitted against a near-black board and this surface is bright turquoise, so at full
# strength six of them meet in the middle and wash the lake out. At this gain they
# read as each pad's colour spreading a little way across the water, which is what
# they were always for.
const POOL_GAIN := 0.40


static func is_animated(_id: String) -> bool:
	return true


# ---------------------------------------------------------------------------
# The scene
# ---------------------------------------------------------------------------

# GDScript cannot resolve a script's own `class_name` from inside that script, and
# a script cannot preload itself either, so the one place this file has to name
# itself does it through the resource cache. `load` on an already-loaded script is
# a dictionary lookup, and it happens once.
static var _script: GDScript = null


static func build(id: String) -> Node3D:
	if not CATALOG.has(id):
		return null
	if _script == null:
		_script = load("res://lake_world.gd") as GDScript
	var root: Variant = _script.new()
	root.name = "MagicalLake"
	root.construct()
	return root as Node3D


# Tell the lake where this board's buttons are and how far the outermost one
# reaches, so the water can put its contact shadows and its standing ripples around
# the real pads and the dressing can be laid outside them. Called by MemoryGameUI
# whenever the board's ground layout is (re)established, which is also every resize
# and every difficulty change.
static func set_board_layout(scene: Node3D, centres: PackedVector2Array, reach: float,
		cam: Camera3D, vp_size: Vector2) -> void:
	if scene != null and scene.has_method("set_layout"):
		scene.call("set_layout", centres, reach, cam, vp_size)


# One pad was pressed. Starts the splash at that pad and nowhere else.
static func note_press(scene: Node3D, centre: Vector2) -> void:
	if scene != null and scene.has_method("splash"):
		scene.call("splash", centre)


# The round the player has just FINISHED.
#
# This is the one piece of match state a background is ever told, and widening the
# hook to carry it was a deliberate decision rather than an oversight — the note on
# BackgroundScenes.set_board_layout used to be able to say a background learns
# nothing about the game, and now says a background learns one integer.
#
# It buys the every-five-rounds frog (see THE FROG), and the number is used for two
# things only: refusing a repeat if the completion fires twice for one round, and
# seeding the variation so occurrence N always looks like occurrence N. It is not
# stored, not scored and not shown. Every other background ignores it.
#
# WHAT COMES BACK is the only thing that flows the other way, and it is a DURATION
# and nothing else: how many seconds the round must stay frozen for the event that
# was just started, or 0.0 if none was. The background still learns nothing about
# the game and still cannot reach into it — it answers "how long", and game.gd
# decides what to do about it. That one number is what turned the frog from a thing
# that plays OVER the next round into an interruption the round waits out.
static func note_milestone(scene: Node3D, round_no: int) -> float:
	if scene != null and scene.has_method("start_frog_event"):
		return float(scene.call("start_frog_event", round_no))
	return 0.0


# The level the player has just COMPLETED, offered to the background so it can mark
# a milestone the every-five-rounds one is not big enough for. Same contract as
# note_milestone in every respect, including the returned freeze in seconds; the
# lake answers it at level 8 with the five-frog party (see THE PARTY) and every
# other background ignores it.
static func note_finale(scene: Node3D, level_no: int) -> float:
	if scene != null and scene.has_method("start_party_event"):
		return float(scene.call("start_party_event", level_no))
	return 0.0


# ---------------------------------------------------------------------------
# Preview
# ---------------------------------------------------------------------------
# A shop card renders the lake through the Hard board's own pose, the same as every
# other 3D background, so the card shows the framing the player gets.
const PREVIEW_FOV := 43.44
const PREVIEW_ELEV_DEG := 33.51
const PREVIEW_TARGET := Vector3(0.0, 0.35, 0.54)
const PREVIEW_DIST := 10.04


static func make_preview_camera(_aspect: float) -> Camera3D:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.fov = PREVIEW_FOV
	cam.near = 0.15
	cam.far = 200.0
	var e := deg_to_rad(PREVIEW_ELEV_DEG)
	cam.look_at_from_position(
		PREVIEW_TARGET + Vector3(0.0, sin(e), cos(e)) * PREVIEW_DIST,
		PREVIEW_TARGET, Vector3.UP)
	return cam


# The palette is solved against the BOARD's Environment, so a preview has to be
# rendered through the same one or every colour here lands somewhere else.
static func make_preview_environment() -> WorldEnvironment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = backdrop_color("world_lake")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 0.40
	env.glow_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	return we


# ---------------------------------------------------------------------------
# Cost
# ---------------------------------------------------------------------------
# The whole lake is EIGHT draw calls: the water, four MultiMeshes (reeds, pads,
# flowers, stones) and two batched quad sheets (fireflies, sparkles), plus the
# board's own ground-pool sheet which was already there. Nothing is a particle
# system, nothing is a light, nothing has a shadow and nothing but a press has a
# per-frame CPU cost — every animation in here is a function of TIME inside a
# shader, which is the pattern the eight Themes1 floors established and the reason
# they cost a low-rate redraw of a scene that was going to be drawn anyway.

const MAX_PADS := 6

# ---------------------------------------------------------------------------
# Where the dressing goes
# ---------------------------------------------------------------------------
# Through the CAMERA, not in metres. The first build laid props on a world annulus
# scaled off the board's reach, which sounded board-agnostic and was not: measured
# on Hard, the first reed landed at screen x 1961 and the first stone at (-444,
# 842) — every one of them outside a 1280x720 frame. A tabletop camera looking down
# at 33.5 deg maps the ground to a strongly keystoned trapezium, so "4.5 m out" is
# comfortably inside the frame to the SIDE and far outside it toward the camera.
#
# So a candidate point is PROJECTED, and kept only if it lands where it is wanted:
# inside the frame with a margin, outside the board's own footprint, and — for
# anything that stands up — with its TOP still in frame too, which is the 0.45 m
# ceiling lume_worlds.gd measured, expressed as a test rather than as a number.
#
# That is what makes ONE environment correct on all three boards at every aspect.
# Easy's three buttons reach ~2.6 and its camera comes in; Hard's six reach ~3.5 and
# its camera pulls back; the fit re-runs on every resize. None of it needs a
# per-board constant, because the frame is asked directly.

# How far outside the outermost button's reach a prop must be, as a multiple of it.
# The play area is kept clear in WORLD units rather than screen ones, because that
# is what "not behind the buttons" actually means.
const DRESS_CLEAR := 1.22
# And how far past that it is worth sampling at all, before the projection decides.
const DRESS_FAR := 3.5

# The frame margin, as a fraction of width and height. Props are kept off the very
# edge so none is a sliver, and out of the top band, where the ground is compressed
# so hard that a prop there is a smear.
const EDGE_X := 0.015
const EDGE_TOP := 0.10
const EDGE_BOTTOM := 0.015

const SEED := 0x11ac0


# ---------------------------------------------------------------------------
# The node
# ---------------------------------------------------------------------------
# This class IS the lake: the façade above and the scene below are one script,
# because everything the node does per frame is written in terms of the palette,
# the shader and the constants above it. (It was an inner class for one draft;
# GDScript cannot resolve an outer `class_name` from inside a nested class, and
# splitting the two into separate files would have made a preload cycle out of a
# dependency that only runs one way.)

var _water: MeshInstance3D
var _wmat: ShaderMaterial
var _dress: Node3D
var _reeds: MultiMeshInstance3D
var _pads: MultiMeshInstance3D
var _flowers: MultiMeshInstance3D
var _stones: MultiMeshInstance3D
var _flies: MeshInstance3D
var _sparks: MeshInstance3D
var _centres := PackedVector2Array()
var _ages := PackedFloat32Array()
var _reach := 0.0
var _vp_size := Vector2.ZERO
var _cam_pose := Transform3D()

func construct() -> void:
	_build_water()
	_dress = Node3D.new()
	_dress.name = "Dressing"
	add_child(_dress)
	_reeds = _multi("Reeds", _reed_mesh(), _reed_material())
	_pads = _multi("Pads", _pad_mesh(), _pad_material())
	_flowers = _multi("Flowers", _flower_mesh(), _flower_material())
	_stones = _multi("Stones", _stone_mesh(), _stone_material())
	_flies = _motes("Fireflies", true)
	_sparks = _motes("Sparkles", false)
	_dress.add_child(_flies)
	_dress.add_child(_sparks)
	# The dressing stays empty until a camera arrives: it cannot be placed without
	# one, and an empty MultiMesh for the frame or two before the first fit is
	# invisible rather than wrong.
	set_process(false)

func _multi(nm: String, mesh: Mesh, mat: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	var mi := MultiMeshInstance3D.new()
	mi.name = nm
	mi.multimesh = mm
	mi.material_override = mat
	mi.layers = BG_LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The dressing sits well outside the buttons but the camera is shallow, so a
	# generous box keeps a swaying reed from popping at the edge of the frame.
	mi.custom_aabb = AABB(Vector3(-40, -2, -40), Vector3(80, 8, 80))
	_dress.add_child(mi)
	return mi

# ---------------- water ----------------

func _build_water() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(WATER_SIZE, WATER_SIZE)
	var sh := Shader.new()
	sh.code = WATER_SHADER
	_wmat = ShaderMaterial.new()
	_wmat.shader = sh
	_wmat.set_shader_parameter("c_shallow", tone(SHALLOW))
	_wmat.set_shader_parameter("c_deep", tone(DEEP))
	_wmat.set_shader_parameter("c_haze", tone(HAZE))
	_wmat.set_shader_parameter("c_sky", tone(SKY))
	_wmat.set_shader_parameter("c_sun", tone(SUN))
	_wmat.set_shader_parameter("c_magic", tone(MAGIC))
	_wmat.set_shader_parameter("glint_dir", GLINT_DIR.normalized())
	_wmat.set_shader_parameter("depth_span", Vector2(DEPTH_NEAR, DEPTH_FAR))
	_wmat.set_shader_parameter("haze_span", Vector2(HAZE_NEAR, HAZE_FAR))
	_wmat.set_shader_parameter("side_span", Vector2(SIDE_NEAR, SIDE_FAR))
	_wmat.set_shader_parameter("press_life", PRESS_LIFE)
	_wmat.set_shader_parameter("pad_r", 1.0)
	_wmat.set_shader_parameter("pad_count", 0)
	_wmat.set_shader_parameter("splashing", 0.0)

	_water = MeshInstance3D.new()
	_water.name = "Water"
	_water.mesh = pm
	_water.material_override = _wmat
	_water.position = Vector3(0.0, WATER_Y, 0.0)
	_water.layers = BG_LAYER
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_water)

# ---------------- layout ----------------

func set_layout(centres: PackedVector2Array, reach: float, cam: Camera3D,
		vp_size: Vector2) -> void:
	_centres = centres
	if _ages.size() != centres.size():
		_ages.resize(centres.size())
		_ages.fill(PRESS_LIFE * 2.0)
	var pads := PackedVector2Array()
	var ages := PackedFloat32Array()
	for i in MAX_PADS:
		pads.append(centres[i] if i < centres.size() else Vector2.ZERO)
		ages.append(_ages[i] if i < _ages.size() else PRESS_LIFE * 2.0)
	_wmat.set_shader_parameter("pads", pads)
	_wmat.set_shader_parameter("ages", ages)
	_wmat.set_shader_parameter("pad_count", mini(centres.size(), MAX_PADS))
	# Re-laid whenever the board, the frame OR THE CAMERA moves. The camera is the
	# one that is easy to miss and was: the board's ground layout is settled several
	# times during a build, and the first of those runs before _fit_camera has
	# solved the distance — so keying only on the reach and the viewport size left
	# the whole dressing placed through a camera 30 % too close, with props landing
	# outside the final frame. Comparing the pose costs one Transform3D and fixes it
	# for every path at once (build, resize, difficulty change).
	if cam == null or vp_size.x < 8.0 or vp_size.y < 8.0:
		return
	var pose := cam.global_transform
	if absf(reach - _reach) > 0.05 or _vp_size != vp_size \
			or not pose.is_equal_approx(_cam_pose):
		_vp_size = vp_size
		_cam_pose = pose
		_scatter(reach, cam, vp_size)

# A press. The splash is started at the pad that moved and nowhere else, and it
# is the ONLY thing in this scene with a per-frame CPU cost — `_process` turns
# itself back off the moment the last ripple has died.
func splash(centre: Vector2) -> void:
	var best := -1
	for i in _centres.size():
		if _centres[i].distance_to(centre) < 0.25:
			best = i
			break
	if best < 0 or best >= MAX_PADS:
		return
	_ages[best] = 0.0
	set_process(true)
	_push_ages()

func _process(dt: float) -> void:
	var live := false
	for i in _ages.size():
		if _ages[i] < PRESS_LIFE:
			_ages[i] += dt
			live = true
	_push_ages()
	# The two events keep _process alive on their own account. They are the second
	# and third things in this scene with a per-frame CPU cost, and like the ripples
	# each turns the whole loop back off when it finishes — see THE FROG and THE
	# PARTY below. They are mutually exclusive: each refuses to start while the
	# other is running, and the round is frozen for the whole of either.
	if _ev_on:
		_tick_event(dt)
		live = true
	if _pt_on:
		_tick_party(dt)
		live = true
	if not live:
		set_process(false)

func _push_ages() -> void:
	var ages := PackedFloat32Array()
	var live := false
	for i in MAX_PADS:
		var a: float = _ages[i] if i < _ages.size() else PRESS_LIFE * 2.0
		ages.append(a)
		live = live or a < PRESS_LIFE
	_wmat.set_shader_parameter("ages", ages)
	_wmat.set_shader_parameter("splashing", 1.0 if live else 0.0)

# ---------------- dressing ----------------

# Lay every prop out for a board whose outermost button reaches `reach`. Only
# instance transforms are written — no mesh is rebuilt and no material is
# touched — so a resize or a difficulty change costs four array fills.
func _scatter(reach: float, cam: Camera3D, vp: Vector2) -> void:
	_reach = reach
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var lo := reach * DRESS_CLEAR
	var hi := reach * DRESS_CLEAR + DRESS_FAR
	fill_reeds(_reeds.multimesh, rng, lo, hi, cam, vp)
	fill_pads(_pads.multimesh, rng, lo, hi, cam, vp)
	fill_flowers(_flowers.multimesh, rng, lo, hi, cam, vp)
	fill_stones(_stones.multimesh, rng, lo, hi, cam, vp)
	# The swarms are laid through the frame as well. They were the one thing left
	# on a world annulus, and at 4-13 m out most of a swarm sat off screen: a
	# firefly nobody can see is not atmosphere, it is a draw call.
	_flies.mesh = mote_mesh(30, true, lo, hi + 2.0, cam, vp)
	_sparks.mesh = mote_mesh(26, false, lo, hi + 2.0, cam, vp)
	# The frog's path is solved on exactly the same signal, and for exactly the same
	# reason: where a point four metres out lands on screen is a question only this
	# camera can answer, and it answers it differently on all three boards.
	_place_path(reach, cam, vp)
	# ...and so are the party's five berths, for the same reason again.
	_place_party(cam, vp)


# ---------------------------------------------------------------------------
# The water
# ---------------------------------------------------------------------------
# Flat geometry, shaded entirely from an analytic wave FIELD. Displacing a
# subdivided plane buys nothing at this camera — the surface is seen at 33.5 deg
# through a 25 deg lens, so a 3 cm swell moves a silhouette by well under a pixel —
# and costs a mesh. What the eye actually reads as water is the NORMAL, and the
# normal here is the exact gradient of the height field rather than a sampled
# approximation of one, which is why three waves are enough to look like many.
#
# Three terms, in this order, and the order is the design:
#
#   swell    three directional sine waves, ~0.06 m peak to peak, moving at three
#            speeds in three directions so the interference never repeats visibly.
#   pads     a standing ring just outside each lily pad (the water a floating thing
#            keeps around it) and, for PRESS_LIFE seconds after a press, one ring
#            travelling outward from the pad that moved.
#   shade    the contact shadow. Applied to the colour LAST, after every highlight,
#            or the specular would re-light the very shadow that is the only thing
#            saying the pad is resting IN the surface rather than hovering over it.
#
# Everything is in radiance, because the palette was solved to radiance once at
# build time (see `tone`). Nothing in here converts a colour.
const WATER_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;

const int MAX_PADS = 6;

uniform vec3 c_shallow;
uniform vec3 c_deep;
uniform vec3 c_haze;
uniform vec3 c_sky;
uniform vec3 c_sun;
uniform vec3 c_magic;
uniform vec3 glint_dir;
uniform vec2 depth_span;      // where the near-to-deep ramp runs, in metres away
uniform vec2 haze_span;       // and where the surface has dissolved entirely
uniform vec2 side_span;       // the same deepening applied sideways
uniform int pad_count;
uniform vec2 pads[MAX_PADS];
uniform float ages[MAX_PADS]; // seconds since that pad was pressed
uniform float pad_r;
uniform float press_life;
// 1 while any pad's splash is still alive. The splash costs an exp, a sin and a
// cos per pad per pixel, and it is running for 1.7 s out of every press — so it is
// behind a UNIFORM branch, which every fragment in the frame takes the same way and
// which therefore costs nothing when it is off. It is the one piece of this shader
// that is not always needed.
uniform float splashing;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float t = TIME;

	// --- the open-water swell, and its analytic gradient
	float h = 0.0;
	vec2 g = vec2(0.0);

	// Detail falls off with distance. A 0.55 m ripple is a few pixels across up at
	// the top of the frame, and left at full strength the far half of the lake
	// shimmers with aliasing instead of receding. The base swell is untouched.
	float det = 1.0 - smoothstep(5.5, 15.0, distance(CAMERA_POSITION_WORLD, wpos));

	// Wavelengths of 1.6 / 0.7 / 0.35 m. A 3 m swell was the first try and it
	// reads as weather rather than as a calm pond: at gameplay scale one pad is
	// 2 m across, so anything longer than about two pads is a slow heave under the
	// buttons instead of ripples between them.
	vec2 d1 = vec2(0.870, 0.493);
	float ph1 = dot(d1, p) * 4.00 + t * 1.10;
	h += 0.030 * sin(ph1);
	g += (0.030 * 4.00) * d1 * cos(ph1);

	vec2 d2 = vec2(-0.410, 0.912);
	float ph2 = dot(d2, p) * 9.00 - t * 1.70;
	h += (0.013 * det) * sin(ph2);
	g += (0.013 * 9.00 * det) * d2 * cos(ph2);

	vec2 d3 = vec2(0.630, -0.777);
	float ph3 = dot(d3, p) * 18.00 + t * 2.60;
	h += (0.005 * det) * sin(ph3);
	g += (0.005 * 18.00 * det) * d3 * cos(ph3);

	// The ridge value the crest highlight is drawn from, kept as the waves' own
	// signed sum rather than the height: `h` peaks only where all three waves agree,
	// which is a scatter of soft BLOBS, and the first build's foam looked like
	// clouds on the water. Weighted toward the primary wave, this is a ridge running
	// along the swell and broken up by the two shorter ones — which is a ripple.
	float ridge = 0.48 * sin(ph1) + 0.34 * sin(ph2) + 0.18 * sin(ph3);

	// --- what each pad does to the water it is sitting in
	float shade = 0.0;
	float foam = 0.0;
	for (int i = 0; i < pad_count; i++) {
		vec2 v = p - pads[i];
		float r = length(v);
		vec2 dir = v / max(r, 0.0001);

		// The ring a floating thing keeps around itself. Windowed to a band just
		// outside the pad so it never touches the open water and never reaches the
		// neighbour.
		float band = exp(-pow((r - pad_r * 1.42) / (pad_r * 0.90), 2.0));
		float rp = r * 7.4 - t * 2.05;
		h += (0.0118 * band) * sin(rp);
		g += (0.0118 * band * 7.4) * dir * cos(rp);

		// The splash. One ring leaving the pad at 2.6 m/s, dying quadratically over
		// press_life, so the last of it is gone rather than cut off.
		if (splashing > 0.5) {
			float live = clamp(1.0 - ages[i] / press_life, 0.0, 1.0);
			live *= live;
			float dd = r - (pad_r * 0.75 + ages[i] * 2.6);
			float env = exp(-dd * dd * 5.0) * live;
			float sp = dd * 6.2;
			h += (0.070 * env) * cos(sp);
			g -= (0.070 * env * 6.2) * dir * sin(sp);
			// The ring is also BRIGHT, not only bent. A pure normal perturbation is
			// invisible against water whose highlight is already broken up; the white
			// water on the ring's crest is what actually reads as a splash.
			foam += env * 1.9;
		}

		// The contact shadow: the pad's own footprint on the water, soft-edged and
		// a little wider than the pad so it reads as light wrapping under it.
		shade += 0.62 * (1.0 - smoothstep(pad_r * 0.50, pad_r * 1.55, r));
	}
	shade = clamp(shade, 0.0, 0.72);

	vec3 n = normalize(vec3(-g.x, 1.0, -g.y));
	vec3 vdir = normalize(CAMERA_POSITION_WORLD - wpos);
	vec3 ldir = normalize(glint_dir);

	// --- depth. Away from the camera AND out to the sides, so the middle of the
	//     lake stays bright under the buttons and the gutters fall away, which is
	//     what frames the play area without putting anything in it.
	float away = -wpos.z;
	float dep = clamp((away - depth_span.x) / max(depth_span.y - depth_span.x, 0.001), 0.0, 1.0);
	float sid = smoothstep(side_span.x, side_span.y, length(p));
	float deepness = clamp(max(dep * dep, sid), 0.0, 1.0);

	vec3 col = mix(c_shallow, c_deep, deepness);
	// The one colour real water does not have, kept in the mid-distance and well
	// under the buttons in strength.
	col += c_magic * (0.16 * dep * (1.0 - deepness));

	// --- reflection. At this camera the far field is all grazing, so a plain
	//     fresnel against the wave normals IS the sky sitting on the water.
	// Exponent 2.5, not the textbook 5: this camera never gets anywhere near
	// grazing (it looks down at 33.5 deg, so 1 - dot is about 0.45 over the whole
	// frame) and a fifth power of that is four thousandths — a term that cannot be
	// seen at any mix weight.
	float fres = pow(1.0 - clamp(dot(n, vdir), 0.0, 1.0), 2.5);
	col = mix(col, c_sky, clamp(fres * 0.45, 0.0, 0.14));

	// --- the sun: a tight glint on the crests plus a broad sheen under it
	vec3 hv = normalize(ldir + vdir);
	float nh = clamp(dot(n, hv), 0.0, 1.0);
	// Exponent 45, not the hundreds a water shader usually wants: the whole wave
	// field tilts the normal by at most ~19 deg, and a tighter lobe simply never
	// fires. At 45 the flats glint and the slopes go dark, which IS glitter.
	// 0.12, not the 0.50 the first sweep used. c_sun is a RADIANCE solved from
	// screen white (4.46, 2.95, 1.90 — see `tone`), so half of it laid over water
	// that is already sitting near 1.0 does not brighten the highlight, it removes
	// the lake.
	col += c_sun * (pow(nh, 45.0) * 0.09 + pow(nh, 8.0) * 0.010);

	// --- the stylised half: a bright line along a crest about to turn over. This
	//     is what reads as MOVING water at a glance, where the specular alone
	//     reads as a still shiny floor.
	float crest = smoothstep(0.78, 0.96, ridge) * (0.55 + 0.45 * det);
	// Weighted toward the SKY rather than the sun: the crest is the sky seen in a
	// tilted facet, and a warm highlight of the same strength pulls the whole lake
	// grey (the red channel of this turquoise sits at 0.32 and c_sun's is 4.46, so
	// a little of it goes a very long way).
	col += (c_sun * 0.012 + c_sky * 0.060) * crest;
	col += (c_sun * 0.055 + c_sky * 0.16) * clamp(foam, 0.0, 1.0);

	col *= 1.0 - shade;
	// The far dissolve goes on after everything, so no highlight survives into it
	// and the surface simply stops existing rather than having an edge.
	col = mix(col, c_haze, smoothstep(haze_span.x, haze_span.y, away));

	ALBEDO = col;
}
"""


# ---------------------------------------------------------------------------
# Dressing
# ---------------------------------------------------------------------------
# Four MultiMeshes and two batched quad sheets. Every one of them is generated here
# rather than imported, every one is unshaded with its own analytic light, and every
# one animates in its vertex shader off TIME — so the entire environment costs six
# draw calls and no CPU at all.
#
# ---------------------------------------------------------------------------
# Why every prop shader is a mix() between two solved colours
# ---------------------------------------------------------------------------
# Because a FRACTION of a solved colour is not a darker version of it. `tone` gives
# the radiance that produces a chosen screen colour, and AgX at exposure 0.40 has an
# enormous toe: screen count 4 needs 0.100 and count 24 needs 0.208. So a stone
# authored at screen (34,58,70) and multiplied by a lambert floor of 0.30 does not
# render as a dark stone — it renders as a BLACK one, because 0.079 is below the
# curve's first step. Measured: the near stones came out as holes in the water.
#
# So every prop shades by mixing between a solved SHADOW colour and a solved LIGHT
# colour. Both ends are then screen colours somebody chose, the shading rides
# between two known points instead of falling off the bottom of the transform, and
# the palette can be read off the constants.
#
# The one rule the placement obeys is the brief's: frame the play, never compete
# with it. Everything is kept a clear margin outside the outermost button and
# inside the frame's own edges (see "Where the dressing goes"); anything that
# STANDS must additionally fit under the top of the picture, and anything FLAT is
# allowed all the way round, because a small pad lying on the water can neither
# hide a button nor leave the frame.

# --- reeds ---------------------------------------------------------------

const REED_SEGS := 7
const REED_BASE_W := 0.052
const REED_BOW := 0.16


# One blade, 1 m tall, bowing forward as it rises. COLOR.r carries the height
# fraction, which is both the colour ramp and the sway weight.
static func _reed_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for s in REED_SEGS + 1:
		var v := float(s) / float(REED_SEGS)
		var w: float = REED_BASE_W * pow(1.0 - v, 0.75) + 0.003
		var x: float = REED_BOW * v * v
		for side in 2:
			var o := (-1.0 if side == 0 else 1.0) * w
			verts.append(Vector3(x, v, o))
			norms.append(Vector3(1.0, 0.0, 0.0))
			cols.append(Color(v, 0.0, 0.0, 1.0))
	for s in REED_SEGS:
		var a := s * 2
		idx.append_array([a, a + 1, a + 3, a, a + 3, a + 2])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


static func _reed_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;
uniform vec3 c_base;
uniform vec3 c_tip;
uniform vec3 ldir;
uniform float sway;
uniform float rate;
varying float vv;
varying vec3 wn;
varying float shade;
void vertex() {
	vv = COLOR.r;
	float ph = INSTANCE_CUSTOM.x * 6.2831853;
	// Weighted by height SQUARED: a reed is anchored in the mud and the tip is what
	// the air moves, so a linear weight makes the whole blade slide sideways.
	float w = vv * vv;
	VERTEX.x += sway * w * sin(TIME * rate + ph);
	VERTEX.z += sway * w * 0.6 * cos(TIME * rate * 0.83 + ph * 1.7);
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	shade = INSTANCE_CUSTOM.y;
}
void fragment() {
	// Two-sided, so the lambert is FOLDED about the normal rather than clipped: a
	// blade seen from behind is lit, not black.
	float lam = 0.5 + 0.5 * dot(wn, ldir);
	ALBEDO = mix(c_base, c_tip, clamp(0.45 * vv + 0.55 * lam, 0.0, 1.0)) * shade;
}
"""
	m.shader = sh
	m.set_shader_parameter("c_base", tone(Color8(26, 74, 58)))
	m.set_shader_parameter("c_tip", tone(Color8(122, 202, 132)))
	m.set_shader_parameter("ldir", SUN_DIR.normalized())
	m.set_shader_parameter("sway", 0.075)
	m.set_shader_parameter("rate", 0.85)
	return m


# Reeds come in CLUMPS. Scattered one by one they read as a fence; in fives, with
# one shared root and their own heights and phases, they read as a plant.
# The tallest a blade in a clump WANTS to be; _fit_height cuts it down to whatever
# the frame has room for at that spot, and REED_MIN is the height below which a
# clump is not worth placing at all.
const REED_TALL := 0.95
const REED_MIN := 0.28
# Kept to the side gutters. A reed in the far band is both the tallest thing in the
# most compressed part of the picture and directly behind the buttons.
const REED_ARC := 0.85


static func fill_reeds(mm: MultiMesh, rng: RandomNumberGenerator, lo: float, hi: float,
		cam: Camera3D, vp: Vector2) -> void:
	var xf: Array[Transform3D] = []
	var cd: Array[Color] = []
	for _c in 10:
		var root := _frame_point(rng, lo, hi, cam, vp, REED_ARC, lo * 0.25)
		if root == Vector3.INF:
			continue
		var tall := _fit_height(root, REED_TALL, cam, vp)
		if tall < REED_MIN:
			continue
		root.y = WATER_Y - 0.05          # rooted just under the surface
		for _b in rng.randi_range(4, 7):
			var o := Vector3(rng.randfn(0.0, 0.16), 0.0, rng.randfn(0.0, 0.16))
			var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), root + o)
			t.basis = t.basis.scaled(Vector3.ONE * (tall * rng.randf_range(0.62, 1.0)))
			xf.append(t)
			cd.append(Color(rng.randf(), rng.randf_range(0.78, 1.20), 0.0, 0.0))
	_fill(mm, xf, cd)


# --- floating pads -------------------------------------------------------

const PAD_SEGS := 44
const PAD_NOTCH := 0.30           # radians of the notch every lily pad has


# A decorative pad: unit radius, one notch, dished up toward the rim the way the
# gameplay pads are. COLOR.r is the radius fraction.
static func _pad_mesh() -> ArrayMesh:
	var verts := PackedVector3Array([Vector3.ZERO])
	var norms := PackedVector3Array([Vector3.UP])
	var cols := PackedColorArray([Color(0, 0, 0, 1)])
	var idx := PackedInt32Array()
	var span := TAU - PAD_NOTCH
	for i in PAD_SEGS + 1:
		var a := -PI + PAD_NOTCH * 0.5 + span * float(i) / float(PAD_SEGS)
		var r := 1.0 + 0.035 * sin(a * 9.0)
		verts.append(Vector3(cos(a) * r, 0.018 + 0.055 * r * r * r, sin(a) * r))
		norms.append(Vector3.UP)
		cols.append(Color(1.0, 0.0, 0.0, 1.0))
	for i in PAD_SEGS:
		idx.append_array([0, i + 1, i + 2])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


static func _pad_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;
uniform vec3 c_hub;
uniform vec3 c_rim;
uniform float bob;
uniform float rate;
varying float vr;
varying float shade;
void vertex() {
	vr = COLOR.r;
	float ph = INSTANCE_CUSTOM.x * 6.2831853;
	// Rides the same swell the water shader draws: it has to go UP and TILT, or a
	// pad that only bobs reads as a decal blinking in place.
	VERTEX.y += bob * sin(TIME * rate + ph);
	VERTEX.x += 0.045 * vr * sin(TIME * rate * 0.77 + ph * 1.3);
	shade = INSTANCE_CUSTOM.y;
}
void fragment() {
	ALBEDO = mix(c_hub, c_rim, vr) * shade;
}
"""
	m.shader = sh
	m.set_shader_parameter("c_hub", tone(Color8(30, 92, 68)))
	m.set_shader_parameter("c_rim", tone(Color8(98, 188, 124)))
	m.set_shader_parameter("bob", 0.022)
	m.set_shader_parameter("rate", 1.05)
	return m


static func fill_pads(mm: MultiMesh, rng: RandomNumberGenerator, lo: float, hi: float,
		cam: Camera3D, vp: Vector2) -> void:
	var xf: Array[Transform3D] = []
	var cd: Array[Color] = []
	for _i in 22:
		# Flat, so `height` is 0 and it is allowed all the way round — including the
		# far band, where a scatter of small pads is most of what says this is a
		# lake rather than a pool.
		var p := _frame_point(rng, lo, hi * 1.3, cam, vp)
		if p == Vector3.INF:
			continue
		p.y = WATER_Y + 0.006
		var s := minf(rng.randf_range(0.26, 0.62), _fit_flat(p, 0.62, cam, vp))
		if s < 0.12:
			continue
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p)
		t.basis = t.basis.scaled(Vector3(s, s, s))
		xf.append(t)
		cd.append(Color(rng.randf(), rng.randf_range(0.80, 1.15), 0.0, 0.0))
	_fill(mm, xf, cd)


# --- flowers -------------------------------------------------------------

# Two rings of petals over a small golden heart. COLOR.g flags the heart, COLOR.r
# is the length fraction along a petal.
#
# Each petal is FIVE vertices, not three. A petal drawn as one triangle from the
# middle is a spike, and eight spikes round a hub is a star — which is exactly what
# the first build put in the corners of the frame, reading as a sparkle effect
# rather than as a flower. Widening at the shoulder and closing to a rounded tip is
# the whole difference.
static func _flower_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()

	for ring in 2:
		var n := 8
		var lift := 0.09 if ring == 0 else 0.24
		var reach := 1.0 if ring == 0 else 0.60
		var off := 0.0 if ring == 0 else PI / float(n)
		for i in n:
			var a := off + TAU * float(i) / float(n)
			var d := Vector3(cos(a), 0.0, sin(a))
			var s := Vector3(-sin(a), 0.0, cos(a))
			var b := verts.size()
			var base := Vector3(0.0, lift * 0.30, 0.0)
			var mid := d * (reach * 0.55) + Vector3(0.0, lift * 0.85, 0.0)
			verts.append(base + s * (0.10 * reach))
			verts.append(base - s * (0.10 * reach))
			verts.append(mid - s * (0.21 * reach))
			verts.append(mid + s * (0.21 * reach))
			verts.append(d * reach + Vector3(0.0, lift, 0.0))
			for _k in 5:
				norms.append(Vector3.UP)
			cols.append(Color(0.0, 0.0, 0, 1))
			cols.append(Color(0.0, 0.0, 0, 1))
			cols.append(Color(0.55, 0.0, 0, 1))
			cols.append(Color(0.55, 0.0, 0, 1))
			cols.append(Color(1.0, 0.0, 0, 1))
			idx.append_array([b, b + 1, b + 2, b + 1, b + 3, b + 2, b + 2, b + 3, b + 4])

	var c0 := verts.size()
	verts.append(Vector3(0.0, 0.20, 0.0))
	norms.append(Vector3.UP)
	cols.append(Color(0.0, 1.0, 0, 1))
	for i in 9:
		var a := TAU * float(i) / 8.0
		verts.append(Vector3(cos(a) * 0.20, 0.15, sin(a) * 0.20))
		norms.append(Vector3.UP)
		cols.append(Color(1.0, 1.0, 0, 1))
	for i in 8:
		idx.append_array([c0, c0 + i + 1, c0 + i + 2])

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


static func _flower_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;
uniform vec3 c_petal_in;
uniform vec3 c_petal_out;
uniform vec3 c_heart;
uniform float bob;
uniform float rate;
varying float vt;
varying float heart;
varying float shade;
void vertex() {
	vt = COLOR.r;
	heart = COLOR.g;
	float ph = INSTANCE_CUSTOM.x * 6.2831853;
	VERTEX.y += bob * sin(TIME * rate + ph);
	VERTEX.x += 0.030 * vt * sin(TIME * rate * 0.71 + ph * 1.9);
	shade = INSTANCE_CUSTOM.y;
}
void fragment() {
	// The heart is the one warm thing at the edge of the frame, and it is what
	// keeps a white flower from reading as a hole in the water.
	vec3 c = heart > 0.5 ? c_heart : mix(c_petal_in, c_petal_out, vt);
	ALBEDO = c * shade;
}
"""
	m.shader = sh
	m.set_shader_parameter("c_petal_in", tone(Color8(250, 226, 236)))
	m.set_shader_parameter("c_petal_out", tone(Color8(216, 132, 174)))
	m.set_shader_parameter("c_heart", tone(Color8(255, 206, 110)))
	m.set_shader_parameter("bob", 0.016)
	m.set_shader_parameter("rate", 0.9)
	return m


static func fill_flowers(mm: MultiMesh, rng: RandomNumberGenerator, lo: float, hi: float,
		cam: Camera3D, vp: Vector2) -> void:
	var xf: Array[Transform3D] = []
	var cd: Array[Color] = []
	for _i in 8:
		var p := _frame_point(rng, lo, hi, cam, vp, 0.0, lo * 0.25)
		if p == Vector3.INF:
			continue
		p.y = WATER_Y + 0.010
		var s := minf(rng.randf_range(0.22, 0.34), _fit_height(p, 0.34, cam, vp))
		if s < 0.14:
			continue
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p)
		t.basis = t.basis.scaled(Vector3(s, s, s))
		xf.append(t)
		cd.append(Color(rng.randf(), rng.randf_range(0.85, 1.10), 0.0, 0.0))
	_fill(mm, xf, cd)


# --- stones --------------------------------------------------------------

static func _stone_mesh() -> Mesh:
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = 9
	s.rings = 5
	return s


static func _stone_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;
uniform vec3 c_shadow;
uniform vec3 c_dry;
uniform vec3 c_wet;
uniform vec3 c_moss;
uniform vec3 ldir;
uniform float water_y;
varying vec3 wn;
varying float wy;
varying float shade;
void vertex() {
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
	shade = INSTANCE_CUSTOM.y;
}
void fragment() {
	float lam = clamp(dot(wn, ldir), 0.0, 1.0);
	// A stone in a lake is three things: dry on top, wet at the line, and mossy
	// wherever the light lands flat. The waterline is the whole reason it reads as
	// half submerged rather than as a pebble resting on a floor.
	vec3 c = mix(c_shadow, c_dry, lam);
	float wet = 1.0 - smoothstep(water_y, water_y + 0.14, wy);
	c = mix(c, c_wet, wet * 0.85);
	c = mix(c, c_moss, clamp(wn.y, 0.0, 1.0) * 0.40 * (1.0 - wet));
	ALBEDO = c * shade;
}
"""
	m.shader = sh
	m.set_shader_parameter("c_shadow", tone(Color8(68, 86, 94)))
	m.set_shader_parameter("c_dry", tone(Color8(146, 156, 160)))
	m.set_shader_parameter("c_wet", tone(Color8(46, 78, 88)))
	m.set_shader_parameter("c_moss", tone(Color8(72, 130, 90)))
	m.set_shader_parameter("ldir", SUN_DIR.normalized())
	m.set_shader_parameter("water_y", WATER_Y)
	return m


static func fill_stones(mm: MultiMesh, rng: RandomNumberGenerator, lo: float, hi: float,
		cam: Camera3D, vp: Vector2) -> void:
	var xf: Array[Transform3D] = []
	var cd: Array[Color] = []
	for _i in 9:
		var p := _frame_point(rng, lo, hi, cam, vp, 1.05, lo * 0.25)
		if p == Vector3.INF:
			continue
		var s := minf(rng.randf_range(0.16, 0.40), _fit_height(p, 0.40, cam, vp))
		if s < 0.10:
			continue
		# Sunk to somewhere between a third and two thirds, so no two break the
		# surface at the same height and none of them look placed.
		p.y = WATER_Y - s * rng.randf_range(0.35, 0.68)
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p)
		t.basis = t.basis.scaled(Vector3(s * rng.randf_range(0.9, 1.5), s,
			s * rng.randf_range(0.9, 1.5)))
		xf.append(t)
		cd.append(Color(rng.randf(), rng.randf_range(0.82, 1.12), 0.0, 0.0))
	_fill(mm, xf, cd)


# --- fireflies and sparkles ---------------------------------------------

# One batched sheet of camera-facing quads: a whole swarm in ONE draw call and no
# particle system. Each quad's four vertices all carry the SAME world position (its
# home) and differ only in UV, which the vertex shader uses as the corner offset
# after the billboard — so drift, bob and flicker are one function of TIME and a
# per-mote seed, evaluated on the GPU.
static func _motes(nm: String, firefly: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.material_override = _mote_material(firefly)
	mi.layers = BG_LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The vertices are HOMES, not positions: the drift happens in the vertex shader,
	# after the bounds would have been derived, so they are given rather than found.
	mi.custom_aabb = AABB(Vector3(-24, -1, -24), Vector3(48, 8, 48))
	return mi


static func mote_mesh(count: int, firefly: bool, lo: float, hi: float,
		cam: Camera3D, vp: Vector2) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + (7 if firefly else 13)
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	var size_lo := 0.040 if firefly else 0.018
	var size_hi := 0.062 if firefly else 0.030
	var y_lo := 0.28 if firefly else 0.02
	var y_hi := 1.15 if firefly else 0.32
	for _i in count:
		var home := _frame_point(rng, lo, hi, cam, vp)
		if home == Vector3.INF:
			continue
		home.y = WATER_Y + rng.randf_range(y_lo, y_hi)
		var sz := rng.randf_range(size_lo, size_hi)
		var seed01 := rng.randf()
		var b := verts.size()
		for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			verts.append(home)
			uvs.append(c)
			uv2.append(Vector2(seed01, sz))
		idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	if not verts.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _mote_material(firefly: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled,
	depth_draw_never, blend_add;
uniform vec3 tint;
uniform float rate;
uniform float amp;
uniform float rise;
uniform float flick;
varying vec2 quv;
varying float bright;
void vertex() {
	float s = UV2.x * 6.2831853;
	float t = TIME * rate;
	// Three periods with no common factor, so a mote wanders instead of orbiting.
	vec3 c = VERTEX;
	c.x += amp * sin(t * 0.73 + s);
	c.z += amp * 0.80 * cos(t * 0.51 + s * 1.7);
	c.y += rise * sin(t * 0.41 + s * 2.3);
	vec4 vp = MODELVIEW_MATRIX * vec4(c, 1.0);
	// Billboard by offsetting in VIEW space, after the transform: one sheet, no
	// per-instance basis to rebuild, and it faces the camera at any board angle.
	vp.xy += UV * UV2.y;
	POSITION = PROJECTION_MATRIX * vp;
	quv = UV;
	bright = mix(1.0 - flick, 1.0, 0.5 + 0.5 * sin(t * 2.1 + s * 4.1));
}
void fragment() {
	float d = clamp(1.0 - length(quv), 0.0, 1.0);
	ALBEDO = tint * bright;
	ALPHA = d * d * d;
}
"""
	m.shader = sh
	m.set_shader_parameter("tint", tone(Color8(255, 232, 150)) if firefly
		else tone(Color8(186, 244, 255)))
	m.set_shader_parameter("rate", 0.30 if firefly else 0.16)
	m.set_shader_parameter("amp", 0.55 if firefly else 0.20)
	m.set_shader_parameter("rise", 0.26 if firefly else 0.06)
	m.set_shader_parameter("flick", 0.75 if firefly else 0.30)
	m.render_priority = 3
	return m


# --- placement -----------------------------------------------------------

# A point on the water between `lo` and `hi` out from the middle of the board that
# lands in the frame's own gutter.
#
# Returns Vector3.INF when nothing in TRIES lands, and the caller then drops that
# prop rather than placing it badly.
const TRIES := 90

# `arc`, in radians, restricts the angle to within that much of the +x or -x axis —
# the SIDE gutters, where the ground is nearest the camera and a prop that stands up
# has the most room under the top of the frame. 0 means anywhere.
# `near_z` rejects anything closer to the camera than that (+z is toward it).
# Everything that STANDS uses it. The near band is the most magnified part of a
# tabletop frame and the only part in FRONT of the buttons, so a stone there is
# both the biggest object on screen and between the player and the game; the two
# bottom corners are better left as open water leading into the board.
static func _frame_point(rng: RandomNumberGenerator, lo: float, hi: float,
		cam: Camera3D, vp: Vector2, arc: float = 0.0, near_z: float = 1e9) -> Vector3:
	var x0 := vp.x * EDGE_X
	var x1 := vp.x * (1.0 - EDGE_X)
	var y0 := vp.y * EDGE_TOP
	var y1 := vp.y * (1.0 - EDGE_BOTTOM)
	for _try in TRIES:
		var a := rng.randf() * TAU
		if arc > 0.0:
			a = (rng.randf() * 2.0 - 1.0) * arc + (0.0 if rng.randf() < 0.5 else PI)
		# Linear in radius, not in sqrt: sampling uniformly by AREA pushes most of
		# the draw to the outer edge of the band, which on a keystoned ground plane
		# is the far strip — and the first pass put every prop in the top corners.
		var r := lerpf(lo, hi, rng.randf())
		var p := Vector3(cos(a) * r, WATER_Y, sin(a) * r)
		if p.z > near_z:
			continue
		# is_position_behind FIRST: unproject_position on a point behind the camera
		# hands back a mirrored screen position that passes every bounds test below.
		if cam.is_position_behind(p):
			continue
		var s := cam.unproject_position(p)
		if s.x < x0 or s.x > x1 or s.y < y0 or s.y > y1:
			continue
		return p
	return Vector3.INF


# How tall something standing at `p` may actually be, given that it wants to be
# `want` metres and has to fit under the top of the frame AND stay under
# SCREEN_TALL of its height on screen.
#
# Height is FITTED rather than tested, and that is the whole difference between a
# lake with reeds and a lake without: as a pass/fail test at a fixed 1.2 m it
# rejected every candidate on Hard, and at 0.85 it still rejected every one on
# Medium, whose camera comes in closer. A rejection sampler fails by producing
# nothing, silently, on exactly the board nobody re-rendered. Fitted, the answer
# to "there is less room here" is a shorter reed, which is also what a shallower
# margin of a pond actually looks like.
#
# Linear in the rise: over the 30-90 cm these props stand, the projection of a
# vertical segment is within a pixel of linear at this lens.
const SCREEN_TALL := 0.15         # of the frame's height, at most


# The same cap for something lying FLAT: how wide it may be on screen, as a
# fraction of the frame's width. A decorative pad has no height to cut down, and a
# radius that reads as a leaf out at the far bank is a slab across the corner when
# the same draw puts it near the camera.
const SCREEN_FLAT := 0.060


static func _fit_flat(p: Vector3, want: float, cam: Camera3D, vp: Vector2,
		cap: float = SCREEN_FLAT) -> float:
	var edge := p + Vector3(want, 0.0, 0.0)
	if cam.is_position_behind(p) or cam.is_position_behind(edge):
		return 0.0
	var px := cam.unproject_position(p).distance_to(cam.unproject_position(edge))
	if px <= 0.5:
		return want
	return want * minf(1.0, (vp.x * cap) / px)


static func _fit_height(p: Vector3, want: float, cam: Camera3D, vp: Vector2) -> float:
	var top := p + Vector3(0.0, want, 0.0)
	if cam.is_position_behind(p) or cam.is_position_behind(top):
		return 0.0
	var s := cam.unproject_position(p)
	var rise := s.y - cam.unproject_position(top).y
	if rise <= 0.5:
		return 0.0
	var room := minf(s.y - vp.y * EDGE_TOP, vp.y * SCREEN_TALL)
	if room <= 0.0:
		return 0.0
	return want * clampf(room / rise, 0.0, 1.0)


static func _fill(mm: MultiMesh, xf: Array[Transform3D], cd: Array[Color]) -> void:
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_custom_data(i, cd[i])


# ===========================================================================
# THE FROG
# ===========================================================================
# Every fifth completed round, a lily pad pushes up out of the lake in the MIDDLE
# of the frame, a frog hops in from the RIGHT of the screen, lands on it, pauses
# for a beat, and goes straight out of the LEFT of the frame in ONE more jump.
# Then the pad sinks and the lake is a lake again.
#
#   off-screen right  ->  the centre pad  ->  off-screen left
#
# and nothing in between: no second pad, no touch-down on the water, no bounce and
# no in-place reaction. The first version had all four — the frog stopped twice,
# read the room and hopped on the spot — and at ~6.2 s it was a small scene playing
# over the next round rather than a thing that crosses the lake. This one is ~4.0 s
# and is one crossing with one landing in it.
#
# ---------------------------------------------------------------------------
# What it is allowed to touch
# ---------------------------------------------------------------------------
# Nothing. It is a visual event and it is built to be impossible for it to be
# anything else: it owns four nodes under this one, it is advanced by this scene's
# own `_process`, and it never calls into the board, the game, the input path or
# the score. game.gd fires it and does NOT await it (see the every-5-rounds block
# there), so the next round starts on the board's own timing whether the frog has
# finished or not.
#
# It cannot cover the play area either, and that is geometry rather than care —
# but not the geometry the first attempt used. See THE LANE below: the path is the
# straight line across the board that is FURTHEST from every button centre, so the
# frog crosses the water through a gap in the ring and is never over a button.
#
# ---------------------------------------------------------------------------
# The path is solved through the CAMERA, like everything else out here
# ---------------------------------------------------------------------------
# The trap the dressing already paid for (see _frame_point): a tabletop camera
# keystones the ground so hard that a distance in metres is not a position on
# screen. "Four metres to the right" is comfortably in frame at the side and far
# outside it toward the camera, and the answer differs on all three boards and at
# every aspect.
#
# So the path takes its DEPTH from the board (THE LANE, below) and its LATERAL
# extent from the CAMERA: the four x positions are solved so that they land on
# chosen fractions of the frame's width. `_x_at_screen` bisects for them. That is
# what makes "enters from the right edge, stops just right of centre, lands left of
# centre, leaves past the left edge" true on Easy, Medium and Hard, at any aspect,
# with no per-board number anywhere.
#
# ---------------------------------------------------------------------------
# THE LANE, and the obvious answer that was wrong
# ---------------------------------------------------------------------------
# "Behind the gameplay area" sounds like it means BEHIND THE BOARD, and the first
# build put the whole path at z = -(reach + 1.15) for that reason. Rendered, the
# lily pad was a four-pixel sliver hanging off the top edge of the frame and the
# frog never appeared at all.
#
# The board fills 82% of the frame's width and 90% of its height (mgui_verify says
# so), and this camera keystones the ground hard: the water one metre past the
# outermost button projects to y = 12 on a 720-tall frame. There is no room behind
# the board. There never was — "behind" on a tabletop camera means "in the last few
# pixels at the top", which is not a place to put anything.
#
# What there IS room in is the board's own middle. The buttons stand on a RING, and
# the inside of that ring is open water on all three boards — the largest single
# clear area in the frame. So the lane is the horizontal line across the board that
# maximises its distance from every button centre, searched from the back of the
# board forward and taking the FURTHEST BACK of any tie, so the frog still goes as
# far behind the play as the geometry actually allows. On Hard that lands on z = 0
# with 1.24 m of clearance to the nearest button on either side; on Easy and Medium
# it lands wherever those rings leave the most room, which is not the same place and
# is not a number anyone has to maintain.
#
# The clearance is measured to the button CENTRES and it bounds the whole line, not
# just the stops: every point on a line at constant z is at least |c.z - z| from
# every centre. So no part of the crossing can be over a button, at any x, on any
# board — which is a stronger promise than picking three safe-looking spots.
#
# The jump apex is FITTED and not chosen, for the same reason a reed's height is:
# at this camera the top of the frame is only ~18 deg below the horizon, so a prop
# four metres out has well under half a metre of headroom, and an arc authored at a
# fixed height sends the frog out of the top of the picture on the board nobody
# re-rendered. `_fit_height` cuts the arc down to the room there is.
#
# ---------------------------------------------------------------------------
# Cost
# ---------------------------------------------------------------------------
# Four draw calls while it runs and none when it does not (every node is hidden
# between events, and the meshes are built once on the first event and kept). No
# particle system, no physics, no lights, no shadows, no textures, no tweens — the
# arcs are closed-form functions of one clock, so a skin change that frees this node
# mid-jump leaves nothing behind to stop.

# How far forward of the board's back edge the lane search is allowed to run. It
# stops at the middle rather than going on to the front of the board, because the
# near band is the most magnified part of a tabletop frame and the only part BETWEEN
# the player and the game (the same reason the dressing keeps out of it — see
# _frame_point's `near_z`). A frog hopping across the front of the buttons is a
# frog in the way.
const LANE_FORWARD := 0.15
const LANE_STEPS := 72

# And how far down the frame the lane's water must land, as a fraction of its
# height. The clearance search on its own is a BOARD answer, and on two of the three
# boards it picks a lane behind the buttons — which is where the ring genuinely has
# the most room, and which the camera then puts in the top 80 pixels of the picture
# with the pad half off the top edge. Measured on Medium: the roomiest lane by
# clearance alone landed at y = 74 of 720, 1.4 px above the highest button.
#
# So the search is constrained rather than re-weighted: lanes that land above this
# are not candidates at all, and the roomiest of what is left wins. The number is
# the frog's own arc plus its body, with a little over — anything higher and
# _fit_height starts cutting the jump down to a shuffle.
const LANE_TOP := 0.245

# Where the three stations sit across the frame, as fractions of its width. Entry
# and exit are outside it on purpose: the frog is already moving when it appears,
# and it is still moving when it goes, so neither end of the crossing has a frog
# standing still on the water waiting to be looked at.
#
# There is exactly ONE stop, and it is the middle of the frame. That is the whole
# composition — the pad comes up in the centre, the frog crosses to it and leaves —
# and it is also the roomiest place on the lane on all three boards, because the
# inside of a ring of buttons is where a ring has its space. The second stop the
# first version had (a touch-down on open water left of centre) is gone with the
# bounce it existed for.
#
# The stop still has a WINDOW, and the window is a fallback rather than a search.
# Being on the lane already guarantees the frog is never OVER a button — but only
# by `best_gap` minus a button's own radius, which on Hard is 24 cm, and a frog
# that lands 24 cm from a lily pad's edge lands with a lily pad behind it and is
# half hidden. So the place it actually STOPS is checked for room, and moved along
# the lane only if it does not have it.
#
# Checked rather than optimised, and that distinction cost a pass in the first
# version: searching the window for the roomiest x pulled the stops away from where
# the composition wanted them. The composition is the requirement; clearance is a
# constraint on it. The window is narrow here for the same reason — "the centre" is
# a much tighter brief than "just right of centre" was.
const PATH_IN_X := 1.18           # off the right edge
const PATH_PAD_X := 0.500         # the lily pad, in the middle of the frame
const PATH_PAD_LO := 0.40         # ...and how far it may slide to find room
const PATH_PAD_HI := 0.62
# Further out than the entry, and further than the old exit's -0.16: this jump is
# the last thing that happens, so the frog has to be COMPLETELY gone by the time it
# ends rather than a body's width past the edge. At 1280 wide that is 384 px of
# clear air past the frame.
const PATH_OUT_X := -0.30         # off the left edge

# How much open water a stop wants around it, ON SCREEN, as a fraction of the
# frame's width — the clear gap between the event pad's outline and the nearest
# gameplay pad's, in pixels, not in metres.
#
# In metres was the first version and it is the same mistake the dressing made once
# already (see _frame_point): a tabletop camera keystones the ground, and the three
# boards draw their pads at very different sizes, so "1.85 m from a button centre"
# is a comfortable gap on Hard and a pad sitting half behind the front leaf on Easy.
# Measured there: the stop cleared every centre by more than 2 m and the frog still
# landed with the magenta pad in front of it.
const STOP_ROOM := 0.055
# The height the gameplay pads' own tops sit at, for measuring their screen radius.
const PAD_TOP := 0.30

# The event pad. Bigger than the decorative ones (which are capped at SCREEN_FLAT)
# because a frog has to sit on it and be seen to sit on it, and it is one prop for
# four seconds rather than twenty-two for the whole match.
const EV_PAD_SCALE := 0.66
const EV_PAD_SUNK := 0.30         # how far under the water it waits

# How high a jump reaches, before the frame-fit cuts it down.
const EV_APEX := 0.62

# Where the EXIT jump's arc peaks, as a fraction of its flight. The entry's peaks
# in the middle, where a thrown thing's does.
#
# This one does not, because a symmetric arc puts its apex halfway between the
# centre pad and a point off the left edge — which is the top-left CORNER of the
# frame, where the LEVEL badge is drawn over the viewport and where the lake's own
# lilies and reeds are thickest. Rendered, the best-read moment of the whole event
# — the frog at the top of its last jump — happened behind the badge, and the
# filmstrip showed an empty lake at the beat named "the top of that arc".
#
# Peaking at a third of the flight puts the apex around a quarter of the way across
# the frame instead, in open water, and leaves the rest of the arc as a long
# descent out of the picture. It is also what a push off a floating leaf looks
# like: a hard vertical shove first, and then travel.
#
# It does not put the WHOLE jump in the clear, and it cannot: the badge covers
# 160 px of the ~200 px band any arc over this lane uses, so a frog crossing the
# last 145 px of the frame at any readable height is behind it. What this buys is
# that everything worth seeing — the push-off, the stretch, the apex — happens
# before that, and what the badge covers is the tail of a descent that is on its
# way out of the picture anyway.
const EV_EXIT_PEAK := 0.32

# The frog, as a multiplier on the model below (which is authored at ~0.29 m nose
# to tail). Picked at gameplay size against the BUTTONS rather than from the number:
# the first pass shipped it at 0.62, which is a physically sensible frog next to a
# 2 m lily pad and rendered as a 25-pixel speck nobody would notice. It is scaled up
# until it reads as an animal, and stopped well before it reads as a seventh button
# — about 45 px tall against a gameplay pad's 330 px across.
const FROG_SCALE := 1.55

# ---------------------------------------------------------------------------
# The clock
# ---------------------------------------------------------------------------
# Durations, in seconds. The whole event is ~4.0 s and it still runs OVER the next
# round starting — it is deliberately not a cutscene, and nothing waits for it.
#
# The four beats and where they land, measured from the trigger:
#
#   0.00 - 0.60   the pad breaks the surface and settles          EV_PAD_RISE
#   0.50 - 1.60   the frog crosses from off-screen right and      EV_JUMP_IN
#                 lands on it (it leaves WHILE the pad is still
#                 rising, which is what keeps the first second
#                 from being an empty lake)
#   1.60 - 1.92   the landing squash, and a crouch out of it      EV_PAUSE
#   1.92 - 3.37   ONE jump, off the pad and out of the frame      EV_JUMP_OUT
#   3.17 - 3.79   the pad goes back under (it starts while the    EV_SINK
#                 frog is still in the air, so the lake is not
#                 left holding a pad after the event is over)
#   3.79 - 4.04   the last ripple fading, nothing on screen       EV_TAIL
#
# The overlaps are the reason it reads as ~4 s of ACTION rather than as six things
# queued up: only two of the six spans have the lake to themselves.
const EV_PAD_RISE := 0.60         # pad breaks the surface and bounces settled
const EV_LEAD_IN := 0.50          # ...and the frog is already on its way in
const EV_JUMP_IN := 1.10          # off-screen right -> the pad
# The whole pause, and the ONE thing the brief is most explicit about: the frog
# lands, it reacts, and it goes. It is long enough to read as a beat and much too
# short to become an interaction — no second bounce, no hop in place, no look at
# the camera. The landing squash takes the first 60 % of it and the crouch that
# launches the exit takes the last 40 %, so there is no still frame in it either.
const EV_PAUSE := 0.32
const EV_JUMP_OUT := 1.45         # the pad -> off-screen left, in one arc
const EV_SINK := 0.62             # the pad going back under
const EV_TAIL := 0.25             # last ripple fading, nothing on screen
# How far before the frog is gone the pad starts sinking.
const EV_SINK_LEAD := 0.20
# The margin between the last frame of the event and the frame gameplay resumes on.
# Two clocks decide those two things — this scene's `_process` and a SceneTreeTimer
# in game.gd — and without a margin they land on the same frame in an order nobody
# controls. 0.12 s is one dropped frame's worth at 8 fps and it is invisible.
const EV_HOLD := 0.12

# How long a ripple ring lives, and a droplet.
const RIPPLE_LIFE := 1.15
const DROP_LIFE := 0.55
const MAX_RIPPLES := 5
const MAX_DROPS := 10

# ---------------------------------------------------------------------------
# Palette
# ---------------------------------------------------------------------------
# Authored on screen and solved through tone() like the rest of the lake. The
# greens are picked AGAINST the decorative pads (hub 30,92,68 / rim 98,188,124) so
# the frog reads as part of this lake and not as a sticker on it, and the belly is
# the one warm-pale thing on it, which is what keeps a small green shape on green
# water from disappearing.
const FROG_BACK := Color8(104, 196, 110)
const FROG_BELLY := Color8(226, 242, 198)
const FROG_SPINE := Color8(48, 132, 82)
const FROG_SHADE := Color8(26, 82, 74)
const FROG_EYE := Color8(250, 250, 238)
const FROG_PUPIL := Color8(22, 38, 44)
# The ripple crest and the droplets: the same pale sky the water mirrors, so a ring
# on the surface is the surface catching light rather than a white circle drawn on it.
const RIPPLE_C := Color8(240, 253, 255)
const RIPPLE_TROUGH := Color8(16, 66, 80)
const DROP_C := Color8(196, 238, 246)

var _ev_root: Node3D
var _frog: MeshInstance3D
var _ev_pad: MultiMeshInstance3D
var _rings: MultiMeshInstance3D
var _drops: MultiMeshInstance3D

var _ev_on := false
var _ev_t := 0.0
var _ev_prev := 0.0               # _ev_t at the top of the previous frame; see _cross
var _ev_last := -1                # the round the last event was fired for
var _ev_seed := 0
# Solved from the camera every time the layout settles; the event reads them live,
# so a resize or a difficulty change mid-jump re-aims the frog instead of stranding it.
var _ev_ready := false
var _p_in := Vector3.ZERO
var _p_pad := Vector3.ZERO
var _p_out := Vector3.ZERO
# The apex, in two parts. `_ev_apex_fit` is how high a jump MAY go here, solved
# against the frame by _place_path; `_ev_apex` is this occurrence's share of it.
# They are separate because the fit is a property of the board and the camera and
# the variation is a property of the round, and folding the second into the first
# is how the fit gets quietly overwritten at trigger time.
var _ev_apex_fit := EV_APEX
var _ev_apex := EV_APEX
# The timeline, resolved at trigger so the variation can move it. Five marks now
# rather than nine: the frog leaves, it lands, it goes, it is gone, and the pad is
# back under.
var _k_in := 0.0                  # the frog pushes off, off-screen right
var _k_land := 0.0                # ...and lands on the pad
var _k_go := 0.0                  # the final jump starts (the ribbit is here)
var _k_gone := 0.0                # the frog is fully outside the frame
var _k_sink := 0.0                # the pad starts going back under
var _k_end := 0.0
# ripple i: (x, z, age, amp);  drop i: (x, y, z) plus velocity and age
var _ring_pos: Array[Vector3] = []
var _ring_age: PackedFloat32Array = PackedFloat32Array()
var _ring_amp: PackedFloat32Array = PackedFloat32Array()
var _drop_p: Array[Vector3] = []
var _drop_v: Array[Vector3] = []
var _drop_age: PackedFloat32Array = PackedFloat32Array()


# ---------------------------------------------------------------------------
# Trigger
# ---------------------------------------------------------------------------
# `round_no` is the round that was just COMPLETED. It is the only piece of match
# state this scene is ever told, it is used for exactly two things — refusing a
# repeat and seeding the variation — and it is not stored beyond that.
func start_frog_event(round_no: int) -> float:
	# Three guards, and each one is a real case rather than defensive noise:
	#   * `_ev_on` — the completion signal arriving while the last frog is still
	#     crossing. It cannot happen from gameplay any more (the round is frozen
	#     for the whole event), but a harness firing two in a row can, and a second
	#     trigger must not restart a frog half way across the lake.
	#   * `_ev_last` — the completion signal firing twice for one round, which is
	#     the duplicate the brief asks to be immune to.
	#   * `_ev_ready` — no camera has arrived yet, so there is no path to solve and
	#     no way to place the frog anywhere but wrong.
	# A refused trigger returns 0.0, which is what tells game.gd not to freeze.
	#
	# ...and a fourth, which used to live in game.gd: EVERY FIFTH round, and the
	# lake is what knows that. The completion hook is offered on every round now
	# (see BackgroundScenes.note_milestone) so that a background may pick its own
	# number — Ice Kingdom picks three — and the number this event was always
	# written to is five.
	if round_no % 5 != 0:
		return 0.0
	if _ev_on or _pt_on or round_no == _ev_last or not _ev_ready:
		return 0.0
	_ev_last = round_no
	if _ev_root == null:
		_build_event()

	# Variation, seeded off the round, so occurrence N is always occurrence N (a
	# resize mid-event cannot re-roll it) and no two in a row are the same.
	#
	# What varies is now much smaller than it was, and deliberately so: the shape of
	# this event is four beats at four times, and the old +-30 % on a hold moved the
	# whole tail of it by most of a second. So the two things that vary are the two
	# that cannot change the reading — how high the arcs go, and a few hundredths on
	# the pause — and the pad's own resting angle (_ev_seed, in _pad_xform).
	var rng := RandomNumberGenerator.new()
	rng.seed = int(round_no) * 7919 + 13
	_ev_seed = int(round_no)
	_ev_apex = _ev_apex_fit * rng.randf_range(0.90, 1.12)

	_k_in = EV_LEAD_IN
	_k_land = _k_in + EV_JUMP_IN
	_k_go = _k_land + EV_PAUSE * rng.randf_range(0.92, 1.14)
	_k_gone = _k_go + EV_JUMP_OUT
	_k_sink = _k_gone - EV_SINK_LEAD
	_k_end = _k_sink + EV_SINK + EV_TAIL

	_ev_t = 0.0
	_ev_prev = 0.0
	_ev_on = true
	_ev_root.visible = true
	_ev_pad.visible = true
	_frog.visible = false
	# The party's five pairs share this root; nothing of theirs may be left standing.
	_pt_pads.visible = false
	_pt_frogs.visible = false
	_ring_age.fill(RIPPLE_LIFE * 2.0)
	_drop_age.fill(DROP_LIFE * 2.0)
	_splash(_p_pad, 0.85, 4, rng)
	AudioManager.play_lake_emerge()
	set_process(true)
	# The freeze, and it is `_k_end` and not `_k_gone`: the frog is completely off
	# the left of the frame at `_k_gone`, but the pad it left is still standing on
	# the water and its last ring is still spreading. EV_HOLD is the margin that
	# makes the ORDER certain rather than simultaneous — this scene's own tick and
	# game.gd's timer are two clocks, and the one that must land second is the one
	# that lets the player press a button again.
	return _k_end + EV_HOLD


# Everything back to rest. The lake is normally FREED when the player leaves the
# skin, which takes the frog with it — but a board that swaps a background without
# rebuilding, and every harness that runs two events in a row, needs this.
func stop_frog_event() -> void:
	_ev_on = false
	_ev_t = 0.0
	_ev_prev = 0.0
	if _ev_root != null:
		# The root goes dark only if the OTHER event is not using it — the two share
		# it, and they share the ripples and droplets under it as well.
		_ev_root.visible = _pt_on
		_ev_pad.visible = false
		_frog.visible = false
		if not _pt_on:
			# visible_instance_count, NOT instance_count: zeroing the count frees the
			# buffers, and the next event then writes past the end of a zero-length
			# multimesh. The pool is allocated once in _build_event and stays.
			_rings.multimesh.visible_instance_count = 0
			_drops.multimesh.visible_instance_count = 0
	if not _pt_on:
		_ring_age.fill(RIPPLE_LIFE * 2.0)
		_drop_age.fill(DROP_LIFE * 2.0)


# Is an event running? The acceptance harness asserts on this rather than reaching
# for a private flag.
func frog_event_active() -> bool:
	return _ev_on


# ---------------------------------------------------------------------------
# The path
# ---------------------------------------------------------------------------
# Called from _scatter, so it is re-solved on exactly the same signal the dressing
# is: the board, the frame or the CAMERA POSE moving. See set_layout's note on why
# the pose is the one that matters.
func _place_path(reach: float, cam: Camera3D, vp: Vector2) -> void:
	var z := _lane_z(reach, cam, vp)
	_p_in = Vector3(_x_at_screen(PATH_IN_X, z, cam, vp), WATER_Y, z)
	_p_pad = _lane_stop(z, PATH_PAD_X, PATH_PAD_LO, PATH_PAD_HI, cam, vp)
	_p_out = Vector3(_x_at_screen(PATH_OUT_X, z, cam, vp), WATER_Y, z)
	# The arc is fitted to the room above the pad, which is the highest point of the
	# path on screen and therefore the one that decides. Floor it so a very tight
	# frame gives a small hop rather than a slide.
	_ev_apex_fit = maxf(_fit_height(_p_pad, EV_APEX, cam, vp), EV_APEX * 0.42)
	if not _ev_on:
		_ev_apex = _ev_apex_fit
	_ev_ready = true
	if _ev_root != null:
		_ev_pad.multimesh.set_instance_transform(0, _pad_xform(_pad_y(_ev_t)))


# The depth of the lane: the z that is furthest from every button centre, searched
# from the back of the board to just past its middle. See THE LANE.
#
# `>` rather than `>=` on the comparison is doing real work — it keeps the FIRST
# maximum found, and the search runs back to front, so a board whose ring leaves two
# equally good lanes gets the one further from the player.
func _lane_z(reach: float, cam: Camera3D, vp: Vector2) -> float:
	if _centres.is_empty():
		return -reach * 0.5
	var best := LANE_FORWARD
	var best_gap := -1.0
	for i in LANE_STEPS:
		var z := lerpf(-reach * 0.98, LANE_FORWARD, float(i) / float(LANE_STEPS - 1))
		# Measured at x = 0, which is the highest the lane goes on screen: a
		# keystoned ground plane lifts nothing and drops everything as it goes out
		# to the sides, so the middle is the case to clear.
		var p := Vector3(0.0, WATER_Y, z)
		if cam.is_position_behind(p) or cam.unproject_position(p).y < vp.y * LANE_TOP:
			continue
		var gap := 1e9
		for c: Vector2 in _centres:
			gap = minf(gap, absf(c.y - z))
		if gap > best_gap:
			best_gap = gap
			best = z
	return best


# A stop on the lane: `want` of the frame's width if there is room there, and
# otherwise the nearest x inside [lo, hi] that has.
#
# The score CLAMPS the room at STOP_ROOM and then subtracts the distance from where
# the composition wanted the stop, IN PIXELS. So every candidate with enough room
# scores alike on the first term and the second one picks the one nearest home —
# the frog stops where it was meant to unless it cannot, and moves the least it can
# when it must. Thirty-one candidates, once per layout change.
#
# Both terms have to be in pixels or the second one does not exist. The first
# version weighed a room in PIXELS against a distance in METRES, and a metre of
# slide cost the same as four pixels of room — so "moves the least it can" was
# never true, the search simply maximised room, and on a board where nothing in the
# window has enough (see below) it went straight to the end of the window. With the
# distance measured the same way the room is, half a pixel of home for a pixel of
# room, the stop only leaves the middle of the frame when the middle is genuinely
# unusable.
#
# Measured across the window (tools/frog_shot.tscn prints the profile), the three
# boards divide into two cases:
#
#   Hard, Medium   91..111 px clear at every candidate, 104 at dead centre. A ring
#                  of buttons has its space in the middle, which is exactly where
#                  the composition wants the pad, so the search never moves it.
#   Easy           -13 px at centre and no better than +1 ANYWHERE in the window.
#                  Three pads, and the front one is centred on the frame: at the
#                  only lane depths LANE_TOP allows, that one pad's outline covers
#                  the whole middle band. There is nothing to slide to.
#
# So on Easy the frog lands with its feet behind the front pad, and that is the
# right answer rather than a defect: the alternative is a pad surfacing off to one
# side of a three-button board, which loses the composition and gains about a
# centimetre of ankle. It reads as depth, because it IS depth — the event is
# happening behind the board.
const STOP_STEPS := 31
# What a pixel of home is worth against a pixel of room. Below 1.0 because room is
# a hard requirement and position is a preference: at 0.5 the stop will trade 2 px
# of travel for 1 px of clearance, and no further.
const STOP_HOME_WEIGHT := 0.5

func _lane_stop(z: float, want: float, lo: float, hi: float,
		cam: Camera3D, vp: Vector2) -> Vector3:
	var x0 := _x_at_screen(want, z, cam, vp)
	var x_lo := _x_at_screen(lo, z, cam, vp)
	var x_hi := _x_at_screen(hi, z, cam, vp)
	var s0 := cam.unproject_position(Vector3(x0, PAD_TOP, z)).x
	var need := vp.x * STOP_ROOM
	var best := x0
	var best_score := -1e9
	for i in STOP_STEPS:
		var x := lerpf(x_lo, x_hi, float(i) / float(STOP_STEPS - 1))
		var sx := cam.unproject_position(Vector3(x, PAD_TOP, z)).x
		var score := minf(_stop_room(x, z, cam), need) \
			- absf(sx - s0) * STOP_HOME_WEIGHT
		if score > best_score:
			best_score = score
			best = x
	return Vector3(best, WATER_Y, z)


# How many pixels of open water there are between a stop at (x, z) and the nearest
# gameplay pad's outline on screen. Negative means the two overlap.
#
# Each pad's screen size is measured by projecting points one board unit out from
# its centre at the height its own top sits at, which is what the camera actually
# does to it — the three boards space their buttons differently and are framed at
# different distances, so no fixed pixel radius is right for more than one of them.
#
# TWO axes, not one, and that is not a refinement: a disc lying on the ground under
# a camera looking down at 33.5 deg projects to an ELLIPSE about half as tall as it
# is wide. Measuring only the x axis and treating the result as a radius therefore
# claimed every pad was twice as tall on screen as it is, and the search read clear
# water above and below a pad as being inside it. Measured on Easy, whose front pad
# is centred on the frame: the true gap at the stop was ~5 px and this function
# reported -122, so no candidate in the window looked usable and the composition
# had nothing to work with. The radius used is the ellipse's own radius in the
# direction of the stop, which is exact on the axes and within a few per cent
# between them.
func _stop_room(x: float, z: float, cam: Camera3D) -> float:
	var s := cam.unproject_position(Vector3(x, PAD_TOP, z))
	var room := 1e9
	for c: Vector2 in _centres:
		var mid := Vector3(c.x, PAD_TOP, c.y)
		var e_x := Vector3(c.x + 1.0, PAD_TOP, c.y)
		var e_z := Vector3(c.x, PAD_TOP, c.y + 1.0)
		if cam.is_position_behind(mid) or cam.is_position_behind(e_x) \
				or cam.is_position_behind(e_z):
			continue
		var cs := cam.unproject_position(mid)
		var a := maxf(cs.distance_to(cam.unproject_position(e_x)), 0.001)
		var b := maxf(cs.distance_to(cam.unproject_position(e_z)), 0.001)
		var d := cs.distance_to(s)
		if d <= 0.001:
			return -maxf(a, b)
		var dir := (s - cs) / d
		room = minf(room, d - 1.0 / sqrt(pow(dir.x / a, 2.0) + pow(dir.y / b, 2.0)))
	return room


# The world x that lands on `frac` of the frame's width, at depth `z` on the water.
#
# Bisected rather than solved: the projection is a division, so inverting it in
# closed form means special-casing the aspect, the KEEP_WIDTH fit and the near
# plane, and this runs only when the layout settles. Screen x is monotonic in world
# x because this camera has no roll — its right vector IS +x — which is what makes
# a bisection valid at all.
static func _x_at_screen(frac: float, z: float, cam: Camera3D, vp: Vector2) -> float:
	var target := vp.x * frac
	var lo := -70.0
	var hi := 70.0
	for _i in 34:
		var mid := (lo + hi) * 0.5
		var p := Vector3(mid, WATER_Y, z)
		if cam.is_position_behind(p):
			return mid
		if cam.unproject_position(p).x < target:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


# ---------------------------------------------------------------------------
# Per-frame
# ---------------------------------------------------------------------------
func _tick_event(dt: float) -> void:
	_ev_prev = _ev_t
	_ev_t += dt
	if _ev_t >= _k_end:
		stop_frog_event()
		return
	_ev_pad.multimesh.set_instance_transform(0, _pad_xform(_pad_y(_ev_t)))
	_step_frog()
	# Fired from HERE and not from _step_frog, which returns early once the frog has
	# left the frame — the last splash of the event is the pad going back under, and
	# it happens after that.
	_frog_beats(_ev_t)
	_step_ripples(dt)
	_step_drops(dt)


# --- the pad -------------------------------------------------------------

# How high the event pad sits at time `t`. Up with a small overshoot, a long hold,
# then back down — and it is only ever a height, so the pad cannot drift.
func _pad_y(t: float) -> float:
	var top := WATER_Y + 0.006
	if t < EV_PAD_RISE:
		var u := clampf(t / EV_PAD_RISE, 0.0, 1.0)
		# Out-cubic to the surface, then one small bounce, which is what a floating
		# thing does when it stops rising and the water does not.
		var e := 1.0 - pow(1.0 - u, 3.0)
		var bounce := 0.045 * sin(u * PI * 2.0) * (1.0 - u)
		return lerpf(top - EV_PAD_SUNK, top, e) + bounce
	if t < _k_sink:
		return top
	# pow(d, 0.7), not d*d, and the difference is entirely about the first two
	# centimetres. The pad is a DISH — its rim stands 7 cm proud of its middle — so
	# while the surface is between the two, all that shows is the rim, which on a
	# scalloped outline is nine dark dashes in a circle. An ease that starts slowly
	# holds the pad exactly there; this one gets it under and gone.
	var d := clampf((t - _k_sink) / EV_SINK, 0.0, 1.0)
	return lerpf(top, top - EV_PAD_SUNK, pow(d, 0.7))


func _pad_xform(y: float) -> Transform3D:
	# ...and it draws in as it goes, by a sixth. Half of the same problem: a leaf
	# being pulled under gets smaller as well as lower, and shrinking closes the
	# residual ring instead of leaving it to fade in place.
	var sink := clampf((_ev_t - _k_sink) / EV_SINK, 0.0, 1.0) if _k_sink > 0.0 else 0.0
	var s := EV_PAD_SCALE * (1.0 - 0.17 * sink)
	var t := Transform3D(Basis(Vector3.UP, float(_ev_seed) * 0.7), Vector3(_p_pad.x, y, _p_pad.z))
	t.basis = t.basis.scaled(Vector3(s, s, s))
	return t


# --- the frog ------------------------------------------------------------

# One frame of the frog: where it is, which way it faces, and how squashed it is.
# Every phase is a closed-form function of `_ev_t`, so there is no integrated state
# to drift, nothing to reset and nothing to stop.
func _step_frog() -> void:
	var t := _ev_t
	if t < _k_in or t >= _k_gone:
		_frog.visible = false
		return
	_frog.visible = true

	var pos := _p_pad
	var lift := 0.0
	var pitch := 0.0
	var squash := Vector3.ONE
	# Facing: the frog travels right-to-left the whole way and never turns, so its
	# nose is on -x from the first frame to the last. There is no yaw and no roll
	# any more — both belonged to the in-place reaction that this event no longer
	# has, and a frog that turns to look at something is a frog that has stopped.

	if t < _k_land:
		# 1. IN. Off the right of the frame, onto the pad.
		var u := (t - _k_in) / (_k_land - _k_in)
		pos = _p_in.lerp(_p_pad, u)
		lift = _arc(u) * _ev_apex
		pitch = _pitch(u)
		squash = _air_squash(u)
	elif t < _k_go:
		# 2. PAUSE. The landing squash, and then the crouch that launches the exit
		# — one continuous move, not a stop between two of them. Both are pure
		# squash on a frog standing still on the pad, so nothing here can drift.
		var u := (t - _k_land) / maxf(_k_go - _k_land, 0.001)
		if u < 0.60:
			squash = _land_squash(u / 0.60)
		else:
			# Amplitude is what sells a jump, so the crouch is deep and short.
			var c := sin((u - 0.60) / 0.40 * PI)
			squash = Vector3(1.0 + 0.17 * c, 1.0 - 0.26 * c, 1.0 + 0.17 * c)
	else:
		# 3. OUT. ONE arc, off the pad and out of the left of the frame, and the
		# last thing that happens.
		#
		# Its arc PEAKS EARLY (see EV_EXIT_PEAK) — that is the only difference
		# between this jump and the entry, and it is a framing decision, not a
		# physical one.
		var u := (t - _k_go) / (_k_gone - _k_go)
		var v := _skew(u, EV_EXIT_PEAK)
		pos = _p_pad.lerp(_p_out, u)
		lift = _arc(v) * _ev_apex
		pitch = _pitch(v)
		squash = _air_squash(v)

	# What the frog is standing on. On the pad while it is on the pad, and IN the
	# water once it has left it — a third of its height under, which is what the
	# exit arc lands its far end in even though the frog is off the frame long
	# before it gets there. The jump lerps its ground with it, or the frog would
	# step down 20 cm the instant it left the leaf.
	var deck := _pad_y(_ev_t) + 0.012
	var wet := WATER_Y - 0.075
	var ground := deck
	if t >= _k_go:
		ground = lerpf(deck, wet, clampf((t - _k_go) / EV_JUMP_OUT, 0.0, 1.0))
	var b := Basis(Vector3.UP, PI) * Basis(Vector3(0.0, 0.0, 1.0), pitch)
	b = b.scaled(Vector3(squash.x, squash.y, squash.z) * FROG_SCALE)
	_frog.transform = Transform3D(b, Vector3(pos.x, ground + lift, pos.z))


# The one-shot moments: a splash where a jump lands, a sound where one starts.
# Driven off the clock crossing a boundary rather than off a phase, so a dropped
# frame cannot skip one and a repeated frame cannot fire one twice.
#
# There are four, and each one is a different sound: they all go to the SAME single
# ambience player (AudioManager._amb_player), so two beats at one instant would be
# one beat with the other truncated. That is why the ribbit is alone on the push-off
# and does not share it with the hop's whoosh.
func _frog_beats(t: float) -> void:
	# Which beat, if any, this frame stepped over. Resolved BEFORE anything is
	# allocated: this runs on every frame of the event and only four of those frames
	# do anything, so building a RandomNumberGenerator up front would be ~120 throw-
	# away objects per crossing for four uses of one.
	var at := Vector3.ZERO
	var amp := 0.0
	var drops := 0
	var sound := ""
	if _cross(t, _k_in):
		sound = "hop"
	elif _cross(t, _k_land):
		at = _p_pad; amp = 0.60; drops = 3; sound = "tap_soft"
	elif _cross(t, _k_go):
		# THE RIBBIT, and the contact the push-off leaves on the water. The brief
		# puts the frog's own voice exactly here — on the last jump, as it goes —
		# rather than on the landing, so it reads as the frog signing off.
		#
		# The ripple is small and it is thrown at the PAD: the frog is pushing off a
		# floating leaf, so what the water gets is the leaf being shoved down, not a
		# body hitting it. No droplets, for the same reason.
		at = _p_pad; amp = 0.42; drops = 0; sound = "ribbit"
	elif _cross(t, _k_sink + EV_SINK * 0.55):
		at = _p_pad; amp = 0.50; drops = 0; sound = "tap_soft"
	else:
		return

	if amp > 0.0:
		var rng := RandomNumberGenerator.new()
		rng.seed = _ev_seed * 31 + int(t * 1000.0)
		_splash(at, amp, drops, rng)
	match sound:
		"hop": AudioManager.play_frog_hop()
		"ribbit": AudioManager.play_frog_ribbit()
		"tap_soft": AudioManager.play_water_tap(0.42)


# Did this frame step over `mark`? `_ev_t` has already been advanced, so the test is
# on the interval that just closed — which is what makes a beat fire exactly once at
# any frame rate, and makes a dropped frame move a splash rather than lose it.
func _cross(t: float, mark: float) -> bool:
	return t >= mark and _ev_prev < mark


# --- the jump shape ------------------------------------------------------

# The height of an arc at `u`, peaking at 1.0 in the middle. A parabola, not a sine:
# a sine leaves the ground too gently and reads as floating.
static func _arc(u: float) -> float:
	var c := clampf(u, 0.0, 1.0)
	return 4.0 * c * (1.0 - c)


# Move an arc's apex to `peak` without changing either of its ends: the two halves
# of the flight are stretched to different lengths and each is still half a
# parabola. Feed the result to _arc, _pitch and _air_squash — all three are written
# about the same 0..1 arc parameter, so remapping it once moves the apex, the nose
# and the stretch together and nothing gets out of step with anything else.
#
# The apex is the only place the two halves meet, and both are flat there (that is
# what an apex is), so the join has no kink in it however far it is moved.
static func _skew(u: float, peak: float) -> float:
	var c := clampf(u, 0.0, 1.0)
	var k := clampf(peak, 0.05, 0.95)
	return 0.5 * c / k if c < k else 0.5 + 0.5 * (c - k) / (1.0 - k)


# Nose up on the way out, level at the top, nose down on the way in — the
# derivative of the arc, scaled. This is most of what makes it read as a jump
# rather than as a slide with a bump in it.
static func _pitch(u: float) -> float:
	return -0.42 * (1.0 - 2.0 * clampf(u, 0.0, 1.0))


# Stretch along the direction of travel while climbing, neutral at the apex, and
# gathered again before landing. Volume is roughly kept, which is what stops
# squash and stretch reading as the model changing size.
static func _air_squash(u: float) -> Vector3:
	var c := clampf(u, 0.0, 1.0)
	var s := 1.0 - 4.0 * c * (1.0 - c)          # 1 at the ends, 0 at the apex
	return Vector3(1.0 + 0.20 * s, 1.0 + 0.16 * s, 1.0 - 0.14 * s)


# The squash on contact, and the recovery. One overshoot, because two reads as a
# bouncing ball and this is a frog absorbing a landing.
static func _land_squash(u: float) -> Vector3:
	var c := clampf(u, 0.0, 1.0)
	var k := (1.0 - c) * cos(c * PI * 1.55)
	return Vector3(1.0 + 0.26 * k, 1.0 - 0.30 * k, 1.0 + 0.26 * k)


# ===========================================================================
# THE PARTY — the level-8 celebration
# ===========================================================================
# Completing LEVEL 8 on this skin is the lake's big moment. FIVE lily pads push up
# out of the water in five different places, each with A FROG ALREADY SITTING ON
# IT, the frogs cheer where they sit while a "YOU ROCK!" banner pops over the
# board, and then every pair goes back down together and the lake closes over them.
# Five seconds, start to finish, and THE ROUND IS FROZEN FOR ALL OF IT.
#
# ---------------------------------------------------------------------------
# One unit, not two things that meet
# ---------------------------------------------------------------------------
# The single most important thing about this event is what it is NOT: there is no
# frog that jumps onto a pad, flies toward one, lands on one or walks up and sits
# down. A frog and its pad are ONE ANIMATED UNIT from the first frame to the last,
# and the code says so rather than being careful — both transforms are written in
# the same loop iteration, off the same pad height, and the frog's only independent
# motion is a few centimetres of seated bounce that is a function of the same clock.
# There is no path, no arc and no landing anywhere in this section; the three
# helpers that make a jump (_arc, _pitch, _air_squash) are not called from it.
#
# ---------------------------------------------------------------------------
# The berths are solved through the CAMERA, and they are not a pattern
# ---------------------------------------------------------------------------
# Same finding as everything else out here: a position in metres is not a position
# on screen under a tabletop camera, and the three boards leave their gaps in
# completely different places. So the five berths are chosen ON SCREEN — a coarse
# grid of screen points is unprojected onto the water, and a berth is accepted only
# if it has open water around it (measured with _stop_room, the same pixel measure
# the frog's landing uses) and is far enough from every berth already taken.
#
# Candidates are visited in a SHUFFLED order rather than best-first, and that is
# the whole reason the five do not read as a pattern: best-first packs them into
# whichever region of the frame happens to score highest, which on a ring of six
# buttons is a neat arc. A shuffled walk under a minimum-separation rule is a
# Poisson-disc sample — irregular by construction, spread by construction, and the
# same five places every time because the shuffle is seeded.
#
# If five will not fit, the requirement is relaxed and the walk is repeated (four
# rounds). That is the same lesson _fit_height learned: a rejection sampler that
# cannot meet its bar fails by silently producing NOTHING, on the one difficulty
# nobody re-rendered.
#
# The top-left corner is excluded outright — the LEVEL badge is drawn over the
# viewport there, and a frog nobody can see is not a celebration.
#
# ---------------------------------------------------------------------------
# Cost
# ---------------------------------------------------------------------------
# Two more draw calls than the lake already has, both MultiMeshes of five, and both
# hidden between events. Ten transforms a frame while it runs, no tweens, no
# particle system: the whole event is a closed-form function of one clock, so a
# skin change that frees this node mid-party leaves nothing behind to stop.

const PT_COUNT := 5

# The pads. A little smaller than the frog event's single one (0.66) because there
# are five of them and they are not the subject — the frogs on them are.
const PT_PAD_SCALE := 0.62
const PT_PAD_MIN := 0.24
# How far under the water a pair waits, and it is deeper than the solo event's 0.30
# for a reason that is arithmetic rather than taste: a frog rides down WITH its pad
# here, and the frog is about 0.24 m tall at this scale. Anything less than about
# 0.28 leaves a pair of eyes floating on the surface after the pad is gone.
const PT_SUNK := 0.52
# How wide a party pad may be ON SCREEN, as a fraction of the frame's width. Its
# own constant rather than the dressing's SCREEN_FLAT (0.060) because these five
# are the subject of the shot for five seconds and the twenty-two scattered ones
# are not — but still a long way under a gameplay pad, which is about 0.26 of the
# width on Hard.
const PT_SCREEN := 0.080

# ---------------------------------------------------------------------------
# The clock
# ---------------------------------------------------------------------------
# Five seconds, and the round is frozen for every one of them, so unlike the frog
# this one is budgeted as a scene rather than as something glimpsed:
#
#   0.00 - 0.78   five pads surface, each with its frog aboard      PT_RISE
#                 (staggered by up to PT_STAGGER so they do not
#                 come up as one sheet)
#   0.60 - 1.00   the settle bounce dies away
#   1.00 - 3.45   THE CELEBRATION — "YOU ROCK!" pops over the       PT_CHEER0/1
#                 board, the woohoo plays, the frogs bounce
#                 where they sit
#   3.50 - 4.74   every pair sinks back, together                   PT_SINK
#   4.74 - 5.00   the last ring fading, nothing on screen
const PT_TOTAL := 5.00
const PT_RISE := 0.62
const PT_STAGGER := 0.16
const PT_CHEER0 := 1.00
const PT_CHEER1 := 3.45
const PT_SINK_AT := 3.50
const PT_SINK := 1.15

# The seated cheer. `PT_HOP` is the whole argument: at 5.5 cm a frog scaled to 1.55
# lifts by about a fifth of its own height, which reads as bouncing on the spot.
# Twice that and it reads as trying to leave, which is the one thing this event may
# not look like.
const PT_HOP_HZ := 2.35
const PT_HOP := 0.055
const PT_WIGGLE := 0.13           # radians of yaw, the "look how pleased I am" wag

# ---------------------------------------------------------------------------
# Where the berths may be, on SCREEN
# ---------------------------------------------------------------------------
const PT_EDGE_X := 0.055          # of the frame's width, in from each side
const PT_TOP := 0.155             # ...and down from the top, where the ground is
const PT_BOTTOM := 0.90           #    so compressed that a pad there is a sliver
const PT_GRID_X := 15
const PT_GRID_Y := 11
# How much open water a berth wants around it and how far apart two berths must be,
# both as fractions of the frame's WIDTH and both measured in pixels for the reason
# _lane_stop had to learn: metres and pixels are not comparable under this camera.
const PT_ROOM := 0.028
const PT_SEP := 0.170
const PT_RELAX := 4               # rounds of loosening before five is given up on
# ...and a rule that is about COMPOSITION rather than about clearance: at most two
# berths may share a horizontal band of the frame.
#
# It is here because minimum separation alone does not produce what "five different
# visually interesting locations, not a grid" means. On a ring of six buttons the
# only open water is the bottom strip and the two side gutters, and a pure
# Poisson-disc walk therefore filled the bottom strip first: the first render of
# this put FOUR of the five along one line at y = 637, all correctly separated and
# all obviously a row. Banding is what makes the five read as scattered.
const PT_BAND := 0.10             # of the frame's height
const PT_PER_BAND := 2
# The top-left box the HUD owns (the LEVEL badge), as fractions of the frame. No
# berth may land inside it.
const PT_HUD_X := 0.34
const PT_HUD_Y := 0.40

var _pt_pads: MultiMeshInstance3D
var _pt_frogs: MultiMeshInstance3D
var _pt_on := false
var _pt_t := 0.0
var _pt_prev := 0.0
var _pt_last := -1                # the level the last party was fired for
var _pt_ready := false
# Solved from the camera every time the layout settles, exactly like the frog's
# path: five water positions, the scale each one is allowed there, the yaw that
# points its frog at the player, and two per-pair offsets that keep the five from
# moving as one.
var _pt_p: Array[Vector3] = []
var _pt_scale := PackedFloat32Array()
var _pt_yaw := PackedFloat32Array()
var _pt_lag := PackedFloat32Array()
var _pt_phase := PackedFloat32Array()


# ---------------------------------------------------------------------------
# Trigger
# ---------------------------------------------------------------------------
# `level_no` is the level that was just COMPLETED. Same contract as the frog's
# trigger in every respect: it is refused rather than queued, it is not stored
# beyond the duplicate guard, and what comes back is the number of seconds the
# round must stay frozen — 0.0 when nothing started.
func start_party_event(level_no: int) -> float:
	# Four guards, and the first two are the "exactly once" the brief asks for: the
	# same level cannot fire twice, and neither event will start on top of the other.
	# Level EIGHT and no other, which game.gd used to decide and the lake now does,
	# for the reason start_frog_event's fourth guard gives.
	if level_no != 8:
		return 0.0
	if _pt_on or _ev_on or level_no == _pt_last or not _pt_ready:
		return 0.0
	_pt_last = level_no
	if _ev_root == null:
		_build_event()

	_pt_t = 0.0
	_pt_prev = 0.0
	_pt_on = true
	_ev_root.visible = true
	# The frog event's own two nodes are hidden rather than merely idle: they share
	# a root, and a stale single pad standing in the middle of a five-pad party is
	# exactly the kind of leftover that only shows up in a screenshot.
	_ev_pad.visible = false
	_frog.visible = false
	_pt_pads.visible = true
	_pt_frogs.visible = true
	var pmm := _pt_pads.multimesh
	for i in _pt_p.size():
		# x is the pad shader's bob phase (its own bob is off here — see _build_event
		# — but the rim's lateral wobble still reads it), y is `shade`. A shade of
		# ZERO is a black pad.
		pmm.set_instance_custom_data(i, Color(_pt_phase[i] / TAU, 1.30, 0.0, 0.0))
	_ring_age.fill(RIPPLE_LIFE * 2.0)
	_drop_age.fill(DROP_LIFE * 2.0)
	AudioManager.play_lake_emerge()
	set_process(true)
	# Write frame zero now. The first _process is a whole frame away, and without
	# this the five pairs spend it at whatever transform the last party left.
	_pose_party(0.0)
	return PT_TOTAL + EV_HOLD


# Everything back to rest. Like stop_frog_event, this exists for the paths where
# the lake is NOT freed: a board that swaps a background without rebuilding, and
# every harness that runs two events in a row.
func stop_party_event() -> void:
	_pt_on = false
	_pt_t = 0.0
	_pt_prev = 0.0
	if _ev_root != null:
		_pt_pads.visible = false
		_pt_frogs.visible = false
		_pt_pads.multimesh.visible_instance_count = 0
		_pt_frogs.multimesh.visible_instance_count = 0
		# The root goes dark only if the other event is not using it.
		_ev_root.visible = _ev_on
		if not _ev_on:
			_rings.multimesh.visible_instance_count = 0
			_drops.multimesh.visible_instance_count = 0
	if not _ev_on:
		_ring_age.fill(RIPPLE_LIFE * 2.0)
		_drop_age.fill(DROP_LIFE * 2.0)


# Is the party running? The acceptance harness asserts on this rather than reaching
# for a private flag.
func party_event_active() -> bool:
	return _pt_on


# ---------------------------------------------------------------------------
# The berths
# ---------------------------------------------------------------------------
# Called from _scatter, so it is re-solved on exactly the same signal the dressing
# and the frog's path are: the board, the frame or the camera pose moving.
func _place_party(cam: Camera3D, vp: Vector2) -> void:
	# Every candidate, as a point on the water under a point on the screen.
	var cand: Array[Vector3] = []
	for iy in PT_GRID_Y:
		var fy := lerpf(PT_TOP, PT_BOTTOM, float(iy) / float(PT_GRID_Y - 1))
		for ix in PT_GRID_X:
			var fx := lerpf(PT_EDGE_X, 1.0 - PT_EDGE_X, float(ix) / float(PT_GRID_X - 1))
			if fx < PT_HUD_X and fy < PT_HUD_Y:
				continue
			var p := _water_at_screen(Vector2(fx * vp.x, fy * vp.y), cam)
			if p != Vector3.INF:
				cand.append(p)

	# Shuffled, seeded. See the note above: best-first is what makes five props
	# look like a formation.
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 977
	var order := PackedInt32Array()
	for i in cand.size():
		order.append(i)
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := order[i]
		order[i] = order[j]
		order[j] = swap

	var picked: Array[Vector3] = []
	for relax in PT_RELAX:
		var ease := 1.0 - 0.26 * float(relax)
		var need := vp.x * PT_ROOM * ease
		var sep := vp.x * PT_SEP * ease
		var band := vp.y * PT_BAND
		# The band rule is a composition preference, so it is the FIRST thing given
		# up when five will not otherwise fit — clearance is a requirement and a
		# scattered arrangement is not.
		var per_band := PT_PER_BAND if relax < 2 else PT_COUNT
		picked.clear()
		for k in order:
			var p: Vector3 = cand[k]
			if _stop_room(p.x, p.z, cam) < need:
				continue
			var s := cam.unproject_position(Vector3(p.x, PAD_TOP, p.z))
			var clear := true
			var in_band := 0
			for q: Vector3 in picked:
				var qs := cam.unproject_position(Vector3(q.x, PAD_TOP, q.z))
				if qs.distance_to(s) < sep:
					clear = false
					break
				if absf(qs.y - s.y) < band:
					in_band += 1
			if clear and in_band < per_band:
				picked.append(p)
				if picked.size() == PT_COUNT:
					break
		if picked.size() == PT_COUNT:
			break

	_pt_p = picked
	var n := picked.size()
	_pt_scale.resize(n)
	_pt_yaw.resize(n)
	_pt_lag.resize(n)
	_pt_phase.resize(n)
	for i in n:
		var p: Vector3 = picked[i]
		# FITTED, not chosen: a pad that reads as a leaf out at the back of the frame
		# is a slab across the corner when the same size is used near the camera.
		_pt_scale[i] = maxf(minf(PT_PAD_SCALE,
			_fit_flat(p, PT_PAD_SCALE, cam, vp, PT_SCREEN)), PT_PAD_MIN)
		# FACING THE PLAYER. The frog's local +x is its nose, and Basis(UP, a) sends
		# +x to (cos a, 0, -sin a), so the yaw that points the nose at the camera is
		# atan2(-dz, dx) of the horizontal offset to it. Solved per berth rather than
		# once, because five pads spread across the frame do not face the same way.
		var d := cam.global_position - p
		_pt_yaw[i] = atan2(-d.z, d.x) if absf(d.x) + absf(d.z) > 0.0001 else 0.0
		_pt_lag[i] = lerpf(0.02, PT_STAGGER, rng.randf())
		_pt_phase[i] = rng.randf() * TAU
	_pt_ready = n == PT_COUNT
	if _ev_root != null and _pt_on:
		_pose_party(_pt_t)


# The point on the water directly under a point on the screen. A ray/plane
# intersection, which is exact — unlike the frog's lateral stations, which bisect
# because they are solving for one axis at a fixed depth rather than for a point.
static func _water_at_screen(px: Vector2, cam: Camera3D) -> Vector3:
	var o := cam.project_ray_origin(px)
	var d := cam.project_ray_normal(px)
	if absf(d.y) < 0.0001:
		return Vector3.INF
	var t := (WATER_Y - o.y) / d.y
	if t <= 0.0 or t > 200.0:
		return Vector3.INF
	return o + d * t


# ---------------------------------------------------------------------------
# Per-frame
# ---------------------------------------------------------------------------
func _tick_party(dt: float) -> void:
	_pt_prev = _pt_t
	_pt_t += dt
	if _pt_t >= PT_TOTAL:
		stop_party_event()
		return
	_pose_party(_pt_t)
	_party_beats(_pt_t)
	_step_ripples(dt)
	_step_drops(dt)


# One frame of all five pairs. Both transforms of a pair are written HERE, in the
# same iteration, off the same pad height — which is what "one animated unit" means
# in code rather than in a comment.
func _pose_party(t: float) -> void:
	var n := _pt_p.size()
	var pmm := _pt_pads.multimesh
	var fmm := _pt_frogs.multimesh
	pmm.visible_instance_count = n
	fmm.visible_instance_count = n
	var top := WATER_Y + 0.006
	for i in n:
		var p: Vector3 = _pt_p[i]
		var s: float = _pt_scale[i]
		# The frog is scaled BY ITS PAD, so a berth the frame made small carries a
		# small frog and the pair stays in proportion wherever it surfaced.
		var ratio: float = s / PT_PAD_SCALE
		var sink := _party_sink(t, i)
		var y := _party_pad_y(t, i)
		# A gentle float, done on the CPU for both halves off ONE expression rather
		# than in the pad's own vertex shader — that shader's bob is switched off for
		# these pads (see _build_event), because a frog that does not bob with the
		# leaf it is sitting on is a frog stuck to the air above it.
		var up := clampf((y - (top - PT_SUNK)) / PT_SUNK, 0.0, 1.0)
		var bob := 0.020 * ratio * up * sin(t * 1.05 + _pt_phase[i])
		y += bob

		var sc := s * (1.0 - 0.14 * sink)
		var pad := Transform3D(Basis(Vector3.UP, _pt_yaw[i] + float(i) * 1.31),
			Vector3(p.x, y, p.z))
		pad.basis = pad.basis.scaled(Vector3(sc, sc, sc))
		pmm.set_instance_transform(i, pad)

		# The seated cheer, and it is the ONLY thing the frog does on its own. Off
		# the pad's own height, so it rides the rise, the float and the sink without
		# any of those being repeated here.
		var lift := 0.0
		var squash := Vector3.ONE
		var wag := 0.0
		if t >= PT_CHEER0 and t < PT_CHEER1:
			var ph := (t - PT_CHEER0) * PT_HOP_HZ * TAU + _pt_phase[i]
			var b := maxf(sin(ph), 0.0)          # in the air
			var c := pow(1.0 - b, 2.4)           # ...and gathered on the leaf
			lift = PT_HOP * ratio * pow(b, 1.35)
			squash = Vector3(1.0 - 0.10 * b + 0.10 * c,
				1.0 + 0.20 * b - 0.15 * c,
				1.0 - 0.10 * b + 0.10 * c)
			wag = PT_WIGGLE * sin(ph * 0.5 + _pt_phase[i])
		var fb := Basis(Vector3.UP, _pt_yaw[i] + wag)
		fb = fb.scaled(Vector3(squash.x, squash.y, squash.z) * FROG_SCALE * ratio)
		fmm.set_instance_transform(i, Transform3D(fb,
			Vector3(p.x, y + 0.012 * ratio + lift, p.z)))


# How far through its sink a pair is, 0 before it starts and 1 when it is gone. The
# lag is carried into the sink at about half strength, so the five do not surface
# in one order and disappear in another.
func _party_sink(t: float, i: int) -> float:
	return clampf((t - (PT_SINK_AT + _pt_lag[i] * 0.55)) / PT_SINK, 0.0, 1.0)


# The height of pair `i` at `t`, and it is only ever a height — the pad cannot
# drift, and neither can the frog, because the frog reads this.
func _party_pad_y(t: float, i: int) -> float:
	var top := WATER_Y + 0.006
	var lag: float = _pt_lag[i]
	if t < lag:
		return top - PT_SUNK
	var d := _party_sink(t, i)
	if d > 0.0:
		# The same pow(d, 0.7) the solo pad sinks with, and for the same reason: an
		# ease that starts slowly parks the dish exactly at the waterline, where all
		# that shows is a ring of scalloped rim.
		return lerpf(top, top - PT_SUNK, pow(d, 0.7))
	var u := clampf((t - lag) / PT_RISE, 0.0, 1.0)
	# pow(u, 1.45) — ACCELERATING, which is the opposite of the solo pad's
	# out-cubic, and the difference is entirely about the frog riding on top.
	#
	# The frog stands about 0.24 m proud of the leaf, so its head crosses the
	# surface while the pad is still 0.24 m under it. Under an ease that does most
	# of its travel first, that happens a quarter of the way into the rise and the
	# player watches a disembodied head float for two thirds of a second. Under this
	# one it happens at about 0.66 of it, so the head breaks the surface and the leaf
	# is up underneath it a fifth of a second later — which is a frog surfacing on a
	# lily pad rather than a frog surfacing and then being given one.
	var e := pow(u, 1.45)
	var bounce := 0.055 * sin(u * PI * 2.0) * (1.0 - u)
	return lerpf(top - PT_SUNK, top, e) + bounce


# The one-shot moments, driven off the clock crossing a mark exactly as the frog's
# are, so a dropped frame moves one rather than losing it.
#
# There is ONE sound in the whole event and it is at the top of the celebration.
# Everything else is water. That is the ambience player's constraint (it is one
# player, so two sounds at one instant is one sound truncated) turned into the
# design: five frogs cheering is one cheer, not five.
func _party_beats(t: float) -> void:
	for i in _pt_p.size():
		if _pt_cross(t, _pt_lag[i] + PT_RISE * 0.34):
			var rng := RandomNumberGenerator.new()
			rng.seed = SEED + i * 131
			_splash(_pt_p[i], 0.52 * (_pt_scale[i] / PT_PAD_SCALE), 2, rng)
		elif _pt_cross(t, PT_SINK_AT + _pt_lag[i] * 0.55 + PT_SINK * 0.35):
			var rng2 := RandomNumberGenerator.new()
			rng2.seed = SEED + i * 977 + 7
			# No droplets on the way down: the water is closing over a leaf, not
			# being hit by one.
			_splash(_pt_p[i], 0.40 * (_pt_scale[i] / PT_PAD_SCALE), 0, rng2)
	if _pt_cross(t, PT_CHEER0):
		AudioManager.play_frog_woohoo()


func _pt_cross(t: float, mark: float) -> bool:
	return t >= mark and _pt_prev < mark


# --- ripples and droplets ------------------------------------------------

# One splash: a ring on the surface and `n` droplets thrown out of it.
func _splash(at: Vector3, amp: float, n: int, rng: RandomNumberGenerator) -> void:
	var slot := 0
	var oldest := -1.0
	for i in MAX_RIPPLES:
		if _ring_age[i] > oldest:
			oldest = _ring_age[i]
			slot = i
	_ring_pos[slot] = Vector3(at.x, WATER_Y + 0.004, at.z)
	_ring_age[slot] = 0.0
	_ring_amp[slot] = amp
	for _k in n:
		var d := -1
		var old := -1.0
		for i in MAX_DROPS:
			if _drop_age[i] > old:
				old = _drop_age[i]
				d = i
		if d < 0:
			break
		var a := rng.randf() * TAU
		var sp := rng.randf_range(0.35, 0.75) * amp
		_drop_p[d] = Vector3(at.x, WATER_Y + 0.02, at.z)
		_drop_v[d] = Vector3(cos(a) * sp, rng.randf_range(0.85, 1.45) * amp, sin(a) * sp)
		_drop_age[d] = 0.0


func _step_ripples(dt: float) -> void:
	var mm := _rings.multimesh
	var n := 0
	for i in MAX_RIPPLES:
		if _ring_age[i] >= RIPPLE_LIFE:
			continue
		_ring_age[i] += dt
		var u := clampf(_ring_age[i] / RIPPLE_LIFE, 0.0, 1.0)
		# Out fast and then easing, which is what a ring on water does. The travel is
		# scaled by the splash's own strength, so a pad settling and a frog landing
		# throw visibly different rings.
		var r: float = 0.12 + 0.86 * _ring_amp[i] * (1.0 - pow(1.0 - u, 2.2))
		var t := Transform3D(Basis().scaled(Vector3(r, 1.0, r)), _ring_pos[i])
		mm.set_instance_transform(n, t)
		mm.set_instance_custom_data(n, Color(u, _ring_amp[i], 0.0, 0.0))
		n += 1
	mm.visible_instance_count = n


# Ballistic, on the CPU, for at most ten 3 cm spheres — which is cheaper than any
# particle system's setup cost and stops dead the moment the event does.
const DROP_G := 3.2

func _step_drops(dt: float) -> void:
	var mm := _drops.multimesh
	var n := 0
	for i in MAX_DROPS:
		if _drop_age[i] >= DROP_LIFE:
			continue
		_drop_age[i] += dt
		_drop_v[i].y -= DROP_G * dt
		_drop_p[i] += _drop_v[i] * dt
		if _drop_p[i].y < WATER_Y:
			_drop_age[i] = DROP_LIFE
			continue
		var u := clampf(_drop_age[i] / DROP_LIFE, 0.0, 1.0)
		# Shrunk away rather than faded: an opaque droplet needs no transparency
		# pass, and a drop getting smaller as it falls is what a real one looks like
		# at this size anyway.
		var s := 0.030 * (1.0 - u * u)
		var t := Transform3D(Basis().scaled(Vector3(s, s, s)), _drop_p[i])
		mm.set_instance_transform(n, t)
		n += 1
	mm.visible_instance_count = n


# ---------------------------------------------------------------------------
# Construction — once, on the first event of a session on this board
# ---------------------------------------------------------------------------
func _build_event() -> void:
	_ev_root = Node3D.new()
	_ev_root.name = "FrogEvent"
	_ev_root.visible = false
	add_child(_ev_root)

	# The pad is the DECORATIVE pad's own mesh and material, instanced once. Reusing
	# them rather than authoring a second lily pad is the whole reason the thing that
	# rises out of the water is unmistakably one of this lake's own leaves — and the
	# material reads INSTANCE_CUSTOM for its bob and its shade, which is why this is
	# a one-instance MultiMesh and not a MeshInstance3D (a plain instance would hand
	# the shader a custom data of zero, and `shade` 0 is a black pad).
	_ev_pad = MultiMeshInstance3D.new()
	_ev_pad.name = "EventPad"
	var pmm := MultiMesh.new()
	pmm.transform_format = MultiMesh.TRANSFORM_3D
	pmm.use_custom_data = true
	pmm.mesh = _pad_mesh()
	pmm.instance_count = 1
	pmm.set_instance_transform(0, _pad_xform(WATER_Y - EV_PAD_SUNK))
	# x is the bob phase, y is `shade` — the contact-shadow term every prop material
	# out here reads off its instance. A shade of ZERO is a black pad, which is what
	# a plain MeshInstance3D would have handed the shader; 1.15 puts this one a touch
	# brighter than the scattered pads, which is right for the one the event is about
	# and is the difference between a leaf and a hole in the water.
	pmm.set_instance_custom_data(0, Color(0.37, 1.15, 0.0, 0.0))
	_ev_pad.multimesh = pmm
	_ev_pad.material_override = _pad_material()
	_ev_pad.layers = BG_LAYER
	_ev_pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ev_pad.custom_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))
	_ev_root.add_child(_ev_pad)

	_frog = MeshInstance3D.new()
	_frog.name = "Frog"
	_frog.mesh = _frog_mesh()
	_frog.material_override = _frog_material()
	_frog.layers = BG_LAYER
	_frog.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_frog.visible = false
	_ev_root.add_child(_frog)

	_rings = MultiMeshInstance3D.new()
	_rings.name = "Ripples"
	var rmm := MultiMesh.new()
	rmm.transform_format = MultiMesh.TRANSFORM_3D
	rmm.use_custom_data = true
	rmm.mesh = _ring_mesh()
	rmm.instance_count = MAX_RIPPLES
	rmm.visible_instance_count = 0
	_rings.multimesh = rmm
	_rings.material_override = _ring_material()
	_rings.layers = BG_LAYER
	_rings.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rings.custom_aabb = AABB(Vector3(-30, -2, -30), Vector3(60, 4, 60))
	_ev_root.add_child(_rings)

	_drops = MultiMeshInstance3D.new()
	_drops.name = "Droplets"
	var dmm := MultiMesh.new()
	dmm.transform_format = MultiMesh.TRANSFORM_3D
	dmm.mesh = _drop_mesh()
	dmm.instance_count = MAX_DROPS
	dmm.visible_instance_count = 0
	_drops.multimesh = dmm
	_drops.material_override = _drop_material()
	_drops.layers = BG_LAYER
	_drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_drops.custom_aabb = AABB(Vector3(-30, -2, -30), Vector3(60, 4, 60))
	_ev_root.add_child(_drops)

	# --- the party's two, hidden until level 8 (see THE PARTY).
	#
	# They are MultiMeshes of five rather than five nodes each, which is what keeps
	# the whole celebration at two draw calls; the pads need custom data (the pad
	# shader reads `shade` off it and a shade of zero is a black pad) and the frogs
	# do not (their shader reads the mesh's own vertex colours, and turning colours
	# on for a MultiMesh would overwrite them).
	_pt_pads = MultiMeshInstance3D.new()
	_pt_pads.name = "PartyPads"
	var ptm := MultiMesh.new()
	ptm.transform_format = MultiMesh.TRANSFORM_3D
	ptm.use_custom_data = true
	ptm.mesh = _pad_mesh()
	ptm.instance_count = PT_COUNT
	ptm.visible_instance_count = 0
	_pt_pads.multimesh = ptm
	# Its OWN material, and the only thing changed on it is that the shader's bob is
	# switched off: these pads are floated on the CPU instead, together with the
	# frogs sitting on them, because a leaf that bobs in a vertex shader takes its
	# passenger nowhere.
	var pmat := _pad_material()
	pmat.set_shader_parameter("bob", 0.0)
	_pt_pads.material_override = pmat
	_pt_pads.layers = BG_LAYER
	_pt_pads.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pt_pads.custom_aabb = AABB(Vector3(-30, -2, -30), Vector3(60, 4, 60))
	_pt_pads.visible = false
	_ev_root.add_child(_pt_pads)

	_pt_frogs = MultiMeshInstance3D.new()
	_pt_frogs.name = "PartyFrogs"
	var ftm := MultiMesh.new()
	ftm.transform_format = MultiMesh.TRANSFORM_3D
	ftm.mesh = _frog_mesh()
	ftm.instance_count = PT_COUNT
	ftm.visible_instance_count = 0
	_pt_frogs.multimesh = ftm
	_pt_frogs.material_override = _frog_material()
	_pt_frogs.layers = BG_LAYER
	_pt_frogs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pt_frogs.custom_aabb = AABB(Vector3(-30, -2, -30), Vector3(60, 4, 60))
	_pt_frogs.visible = false
	_ev_root.add_child(_pt_frogs)

	_ring_pos.resize(MAX_RIPPLES)
	_ring_age.resize(MAX_RIPPLES)
	_ring_amp.resize(MAX_RIPPLES)
	_ring_age.fill(RIPPLE_LIFE * 2.0)
	_ring_amp.fill(1.0)
	_drop_p.resize(MAX_DROPS)
	_drop_v.resize(MAX_DROPS)
	_drop_age.resize(MAX_DROPS)
	_drop_age.fill(DROP_LIFE * 2.0)


# ---------------------------------------------------------------------------
# The frog, as geometry
# ---------------------------------------------------------------------------
# Ten blobs welded into one mesh: a body, a head, two eyes, two pupils, two folded
# haunches and two front feet. That is the whole model, and it is the right shape of
# model for where it is used — the frog is about fifty pixels tall at gameplay size,
# so what has to be right is the SILHOUETTE (a wide low body, a raised head, eyes
# proudly on top of it, haunches bunched behind) and nothing below that resolves.
#
# It is built out of Godot's own SphereMesh rather than a hand-rolled UV sphere, and
# that is a deliberate choice about risk rather than laziness: the winding, the
# normals and the poles of a generated sphere are the two-line bug that renders a
# model inside out, and there is nothing to gain here by owning them. Each blob's
# arrays are pulled out, scaled and translated into place, and the NORMALS are
# transformed by the inverse-scale — a non-uniform scale does not preserve them, and
# a frog whose belly is lit like its back is exactly the flat look this whole pass
# exists to remove.
#
# Local frame: +x is forward (the nose), +y up, origin under the frog's feet so the
# animation can put it on a surface by setting y and nothing else.
#
# The vertex colours carry three things the shader needs and no texture is worth:
#   COLOR.r  belly, 0 on the back and 1 underneath
#   COLOR.g  part, 0 skin / 0.5 eye white / 1 pupil
#   COLOR.b  the dorsal stripe, which is what gives a small green shape on green
#            water a readable top
const FROG_BODY_TOP := 0.150

static func _frog_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()

	# body: wide, low and tapering back, which is the frog read at any size
	_frog_blob(verts, norms, cols, idx, Vector3(-0.010, 0.082, 0.0),
		Vector3(0.132, 0.078, 0.108), 12, 7, 0.0)
	# head: a second dome grown out of the front of it, not a separate ball on a neck
	_frog_blob(verts, norms, cols, idx, Vector3(0.084, 0.112, 0.0),
		Vector3(0.082, 0.066, 0.084), 12, 7, 0.0)
	# eyes, proud of the head — the single most important shape on the whole animal
	for side in [-1.0, 1.0]:
		_frog_blob(verts, norms, cols, idx, Vector3(0.104, 0.176, side * 0.047),
			Vector3(0.040, 0.040, 0.040), 9, 6, 0.5)
		_frog_blob(verts, norms, cols, idx, Vector3(0.128, 0.180, side * 0.052),
			Vector3(0.022, 0.024, 0.022), 7, 5, 1.0)
	# haunches, bunched behind — the frog is always either about to jump or landing
	for side in [-1.0, 1.0]:
		_frog_blob(verts, norms, cols, idx, Vector3(-0.058, 0.062, side * 0.094),
			Vector3(0.082, 0.058, 0.042), 9, 6, 0.0)
		_frog_blob(verts, norms, cols, idx, Vector3(0.006, 0.020, side * 0.108),
			Vector3(0.062, 0.020, 0.030), 8, 5, 0.0)
	# front feet, small and planted
	for side in [-1.0, 1.0]:
		_frog_blob(verts, norms, cols, idx, Vector3(0.086, 0.026, side * 0.070),
			Vector3(0.034, 0.028, 0.026), 8, 5, 0.0)
		_frog_blob(verts, norms, cols, idx, Vector3(0.120, 0.014, side * 0.072),
			Vector3(0.040, 0.014, 0.026), 8, 5, 0.0)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


# One ellipsoid, appended in place. `part` goes straight into COLOR.g.
static func _frog_blob(verts: PackedVector3Array, norms: PackedVector3Array,
		cols: PackedColorArray, idx: PackedInt32Array,
		at: Vector3, r: Vector3, seg: int, rings: int, part: float) -> void:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = seg
	sm.rings = rings
	var a: Array = sm.surface_get_arrays(0)
	var sv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var sn: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var si: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var base := verts.size()
	for i in sv.size():
		var p := at + Vector3(sv[i].x * r.x, sv[i].y * r.y, sv[i].z * r.z)
		verts.append(p)
		# Inverse-scale on the normal: a non-uniform scale sends the surface one way
		# and its normal the other.
		norms.append(Vector3(sn[i].x / r.x, sn[i].y / r.y, sn[i].z / r.z).normalized())
		if part > 0.0:
			cols.append(Color(0.0, part, 0.0, 1.0))
		else:
			var belly := clampf(1.0 - p.y / (FROG_BODY_TOP * 0.72), 0.0, 1.0)
			# The stripe: narrow, along the spine, and only on the upper half, so it
			# never wraps round onto the flank and turns into a band.
			var stripe := smoothstep(0.052, 0.014, absf(p.z)) \
				* smoothstep(0.070, 0.130, p.y)
			cols.append(Color(belly * belly, 0.0, stripe, 1.0))
	for i in si.size():
		idx.append(base + si[i])


static func _frog_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;
uniform vec3 c_back;
uniform vec3 c_belly;
uniform vec3 c_spine;
uniform vec3 c_shade;
uniform vec3 c_eye;
uniform vec3 c_pupil;
uniform vec3 ldir;
varying vec3 wn;
varying float belly;
varying float part;
varying float stripe;
void vertex() {
	// World-space normal, because the frog is rotated and non-uniformly SCALED
	// every frame by the squash: shading it in local space would swing the light
	// around it as it turns, and a stretched frog would light like a flat one.
	wn = normalize((MODEL_NORMAL_MATRIX * NORMAL));
	belly = COLOR.r;
	part = COLOR.g;
	stripe = COLOR.b;
}
void fragment() {
	float lam = clamp(dot(wn, ldir), 0.0, 1.0);
	vec3 skin = mix(c_back, c_belly, belly);
	skin = mix(skin, c_spine, stripe * 0.60);
	// A floor under the lambert, not a black shadow: the shaded side of a small
	// animal on bright water is still coloured, and crushing it is how a stylised
	// model starts reading as a silhouette.
	vec3 c = mix(c_shade, skin, 0.34 + 0.66 * lam);
	if (part > 0.75) {
		c = c_pupil;
	} else if (part > 0.25) {
		// The eye keeps a little of the light so it reads as a wet dome rather
		// than as a white dot.
		c = c_eye * (0.74 + 0.26 * lam);
	}
	ALBEDO = c;
}
"""
	m.shader = sh
	m.set_shader_parameter("c_back", tone(FROG_BACK))
	m.set_shader_parameter("c_belly", tone(FROG_BELLY))
	m.set_shader_parameter("c_spine", tone(FROG_SPINE))
	m.set_shader_parameter("c_shade", tone(FROG_SHADE))
	m.set_shader_parameter("c_eye", tone(FROG_EYE))
	m.set_shader_parameter("c_pupil", tone(FROG_PUPIL))
	m.set_shader_parameter("ldir", SUN_DIR.normalized())
	return m


# ---------------------------------------------------------------------------
# The ripple ring and the droplets
# ---------------------------------------------------------------------------
# A flat annulus, expanded and faded by the instance's own age. COLOR.r is the
# radial fraction, so the shader can put the brightness in the MIDDLE of the band
# and take it to nothing at both edges — a ring with a hard edge reads as a decal,
# and this one has to read as the surface itself catching the light.
const RING_SEGS := 40
# Where the band starts, as a fraction of the ring's outer radius. The rest of its
# shape — where it is dark, where it is bright, where it fades out — is solved in
# the shader from the vertex's own radius, and NOT carried in a vertex colour.
#
# That is a correction, not a preference. The first two builds put the alpha profile
# in COLOR.g and the crest/trough signal in COLOR.r, the way every other prop out
# here carries its parameters. Probed with a debug shader that wrote the varyings
# straight to ALBEDO, the ring drew in the right place at the right size with both
# channels ARRIVING BUT SMALL — enough to light a debug channel and nowhere near
# enough for `prof * fade` to be a visible alpha. Adding the NORMAL array the
# surface was missing changed nothing.
#
# Rather than keep guessing at how a colour attribute is being packed on a mesh
# built for a MultiMesh, the profile is now geometry: `length(VERTEX.xz)` is exactly
# as available, exactly as cheap, and cannot be quietly requantised on the way in.
const RING_IN := 0.72

static func _ring_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	# Five loops across the band: the shading is analytic, so these only have to be
	# close enough together that a linearly-interpolated radius does not visibly
	# straighten the profile.
	var loops := 5
	for loop in loops:
		var r := lerpf(RING_IN, 1.0, float(loop) / float(loops - 1))
		for i in RING_SEGS:
			var a := TAU * float(i) / float(RING_SEGS)
			verts.append(Vector3(cos(a) * r, 0.0, sin(a) * r))
			norms.append(Vector3.UP)
	for loop in loops - 1:
		for i in RING_SEGS:
			var j := (i + 1) % RING_SEGS
			var a0 := loop * RING_SEGS + i
			var a1 := loop * RING_SEGS + j
			var b0 := (loop + 1) * RING_SEGS + i
			var b1 := (loop + 1) * RING_SEGS + j
			idx.append_array([a0, b0, b1, a0, b1, a1])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


# MIXED, not added, and that is the thing about this material worth knowing.
#
# The obvious build is an additive white ring, and it is nearly invisible here. This
# water is a bright turquoise sitting well up AgX's shoulder — screen count 232 needs
# a radiance of 2.61 and everything past ~4.5 is white — so adding half a unit of
# light to it moves the picture by about twenty counts and reads as a smudge.
#
# A real ripple is not extra light anyway: it is a trough and a crest, one darker
# than the water and one brighter. Mixing lets the trough go DOWN, which additive
# blending cannot do at any strength, and the two of them side by side read as a
# ring at a fraction of the brightness either one alone would need. The dark half
# and the bright half get equal width for the same reason.
static func _ring_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, fog_disabled;
uniform vec3 c_crest;
uniform vec3 c_trough;
uniform float r_in;
varying float band;
varying float fade;
void vertex() {
	// 0 at the inner edge of the band, 1 at the outer one, straight off the ring's
	// own geometry — see RING_IN.
	band = clamp((length(VERTEX.xz) - r_in) / (1.0 - r_in), 0.0, 1.0);
	// age in x, amplitude in y. The CPU decides how far the ring has travelled
	// (it scales the instance); only how strongly it still shows is solved here.
	float age = INSTANCE_CUSTOM.x;
	fade = (1.0 - age) * (1.0 - age) * INSTANCE_CUSTOM.y;
}
void fragment() {
	ALBEDO = mix(c_trough, c_crest, smoothstep(0.30, 0.78, band));
	// A hump: nothing at either edge of the band, everything through the middle,
	// so the ring has no border anywhere.
	ALPHA = sin(band * 3.1415927) * fade * 0.62;
}
"""
	m.shader = sh
	m.set_shader_parameter("c_crest", tone(RIPPLE_C))
	m.set_shader_parameter("c_trough", tone(RIPPLE_TROUGH))
	m.set_shader_parameter("r_in", RING_IN)
	return m


static func _drop_mesh() -> Mesh:
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = 6
	s.rings = 4
	return s


static func _drop_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;
uniform vec3 c_drop;
uniform vec3 ldir;
varying vec3 wn;
void vertex() { wn = normalize((MODEL_NORMAL_MATRIX * NORMAL)); }
void fragment() {
	ALBEDO = c_drop * (0.68 + 0.32 * clamp(dot(wn, ldir), 0.0, 1.0));
}
"""
	m.shader = sh
	m.set_shader_parameter("c_drop", tone(DROP_C))
	m.set_shader_parameter("ldir", SUN_DIR.normalized())
	return m
