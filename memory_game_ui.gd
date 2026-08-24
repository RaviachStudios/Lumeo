extends Control
class_name MemoryGameUI

# The MODERATE ("Medium") gameplay device: the five-button physical game board
# authored in Blender and exported as res://models/MemoryGame_UI_Medium.glb.
#
# The GLB is the source of truth for geometry, layout, materials and the press
# animations. Nothing here remodels, merges, re-parents or rebuilds any of it. The
# script places a camera and a lighting rig in front of the imported scene so it
# reads like the Blender reference (MediumV3/MemoryGame_UI_Medium_idle.png), and
# drives the per-button emission that the game needs at runtime.
#
# Three presentation choices ARE made here rather than in the asset, all of them
# transforms and material values, never geometry:
#   * the five button parents are pushed outward by SPACING_SCALE,
#   * the Jade button is darkened to separate it from Cyan,
#   * the round number is a Godot-side stage plate, because the V3 board has no
#     centre module to put it in.
#
# Public API is a drop-in superset of SimonWheel's, so game.gd drives it with the
# exact same calls (see game.gd's _wheel):
#   configure(count, colors)      -> build the device (colors are ignored; the
#                                    GLB carries its own authored palette)
#   apply_skin(outer, inner, number, skin_id)
#                                 -> only the level-number font package applies
#   set_lit(idx, on)              -> HIGHLIGHT emission (sequence playback)
#   set_press(idx, amount)        -> Press_* clip + PRESSED emission
#   segment_at_point(local_pos)   -> button index under a tap, or -1
#   set_level(n)                  -> stage-number readout
#   erupt() / electric_pulse() / roulette_spin() / luna_light_chase() /
#   luna_celebrate() / roulette_celebrate()
#                                 -> no-ops (skin flourishes belong to the wheel)
#
# Colour-named conveniences for anything that would rather not think in indices:
#   play_color("crimson") / press_color("jade") / set_color_enabled("cyan", false)
#   set_round_number(n)
#   signals button_pressed(idx) and color_pressed(name)
#
# Renderer note: same approach as SimonWheel — a transparent SubViewport with its
# own World3D. The viewport only redraws while something is moving (see
# _update_render_activity), which is what keeps the mobile GL driver from leaking
# on long sessions.

const MODEL: PackedScene = preload("res://models/MemoryGame_UI_Medium.glb")

# Button index -> the GLB's colour key. The index order matches game.gd's
# BUTTON_COLORS (Red, Green, Blue, Yellow, Orange) so the existing per-index tones
# from AudioManager.play_button_tone keep their pairing: crimson reads as the red
# slot, jade as green, cyan as blue, amber as yellow and violet as the fifth.
# The names are exactly the ones the Blender file uses for its nodes
# (Button_Jade, Button_Jade_Surface, Button_Jade_Frame) and its clips (Press_Jade).
const COLOR_KEYS := ["Crimson", "Jade", "Cyan", "Amber", "Violet"]
const NUM_BUTTONS := 5
# The button at the back of the board, which the stage plate sits behind.
const FAR_KEY := "Cyan"

# ---------------------------------------------------------------------------
# Board layout
# ---------------------------------------------------------------------------
# The board is authored FLAT: the five buttons sit on the y = 0 plane at a radius
# of 1.83 with their axes along +Y, Cyan at the back (-Z) and Crimson / Jade at
# the front. Nothing here rotates it — the tilt the composition needs comes from
# the camera looking down at the plane, which is exactly how the Blender reference
# was framed. Tilting the board as well would only duplicate that, and tilting the
# buttons individually would break the "one physical surface" read entirely.
#
# As authored, neighbouring frames are 2.15 apart centre-to-centre for a frame
# DIAMETER of 2.0 — a 0.15 gap, which reads as five discs crowding each other.
# Pushing the button PARENTS out by 15% (radius 1.83 -> 2.10) opens that to 0.47
# without touching a single vertex: the buttons keep their authored size, shape,
# proportions and orientation, and only their distance from the middle changes.
const SPACING_SCALE := 1.15

# ---------------------------------------------------------------------------
# Jade
# ---------------------------------------------------------------------------
# As authored, Jade renders (50,148,123) against Cyan's (70,167,167) — two teals a
# few counts apart, which is a colour-identification game's worst failure. This is
# the requested deep-emerald target.
#
# Its hue is very nearly the authored one (the authored green:blue ratio is
# 1:0.507, the target's is 1:0.501), so the correction is a DARKENING, not a hue
# rotation: the target sits at 0.43x the authored green in linear light. That one
# factor is derived at build time and applied to the surface's emission and to the
# under-glow, so the whole button dims together and keeps the material
# relationships the asset was authored with. The bright rim ring is deliberately
# left alone — every button's ring is near-white, and dimming only Jade's would
# make it the odd one out.
const JADE_KEY := "Jade"
const JADE_TARGET := Color("087a58")
# How far the Jade emission and under-glow are pulled down. In pure colour terms
# the target sits at 0.43x the authored green, but that ratio is a linear-light
# answer and this scene tonemaps through AgX, which renders it a shade under the
# mark. 0.62 was measured off the render instead: it puts the Jade top on
# (8,122,88) against Cyan's (73,168,164) — the same hue family, unmistakably
# darker and deeper, and still plainly green rather than black or teal.
const JADE_DIM := 0.62

# ---------------------------------------------------------------------------
# Camera
# ---------------------------------------------------------------------------
# A perspective camera raised above the board, fitted to the Blender reference
# rather than guessed: solving the five measured button centroids in the 1920x1080
# render for camera pose and lens lands on elevation 33.9 deg, a 53.3 deg
# horizontal field and a target just above the board plane, to 9 px RMS.
#
# That angle is the whole "physical tabletop" read — high enough to show the frame
# thickness, the raised surface and the gap between them, low enough that the back
# button sits clearly higher in frame than the front two, and nowhere near
# top-down.
#
# KEEP_WIDTH, not KEEP_HEIGHT: the board is much wider than it is deep on screen,
# so width is the binding constraint. On a taller viewport this keeps every button
# in frame instead of cropping the outer two.
const CAM_FOV := 53.32                       # horizontal, with KEEP_WIDTH
const CAM_ELEV_DEG := 33.86
const CAM_TARGET := Vector3(0.0, 0.56, 0.12)
const CAM_DIST_START := 7.11                 # the reference's own distance
const CAM_DIST_MIN := 4.0
const CAM_DIST_MAX := 26.0
# How much of the frame the board is fitted into, and where its centre lands.
# The composition fills the viewport; the small vertical bias lifts it off the
# bottom edge so game.gd's status pill has the front gap to itself.
const FIT_FILL_X := 0.94
const FIT_FILL_Y := 0.89
const FIT_CENTRE_Y := 0.485

# ---------------------------------------------------------------------------
# Emission states
# ---------------------------------------------------------------------------
# Multipliers on whatever the GLB authored, in LINEAR light: idle 1.0 is the
# material exactly as exported, so a resting board is the Blender asset untouched.
#
# The V3 export carries no glTF `extras`, unlike the previous board which shipped
# its four levels as Blender custom properties. _read_states still honours them if
# a later export adds them back (as `emission_idle` / `ring_idle` and friends,
# normalised against idle); until then these are the levels.
const FALLBACK_SURFACE := {"idle": 1.0, "highlight": 2.60, "pressed": 1.70, "disabled": 0.10}
const FALLBACK_RING := {"idle": 1.0, "highlight": 2.40, "pressed": 1.90, "disabled": 0.15}

const STATE_IDLE := "idle"
const STATE_HIGHLIGHT := "highlight"
const STATE_PRESSED := "pressed"
const STATE_DISABLED := "disabled"

# How fast a button eases between emission states. Fast enough that a press reads
# as instant, slow enough that the flare has a visible falloff instead of popping.
const EMIT_LERP := 18.0

# A single exposure trim on every emissive, in LINEAR light — never a colour,
# never a per-button value. 1.0 = exactly as Blender authored it.
const EMISSION_MATCH := 1.0

# ---------------------------------------------------------------------------
# Ground glow
# ---------------------------------------------------------------------------
# The reference's soft colour pools on the table around each button are bloom from
# the Blender render. Godot's glow pass cannot stand in for them here — under the
# Compatibility (GL) renderer it applies a flat additive term with no falloff at
# any distance, and it writes no alpha, so over this device's transparent
# SubViewport it would be discarded at composite time regardless.
#
# So the pools are drawn explicitly: ONE unshaded plane lying ON the board, just
# above y = 0, whose shader sums a radial falloff around each button centre. A
# single extra draw call, no full-screen post-process, correct alpha, and each
# button's pool is independently controllable. Because it lies in the board plane
# it is depth-tested like everything else, so the frames occlude it and it reads
# as light on a surface rather than a sprite pasted over the render.
# Fitted to the reference's own pool, sampled outward from a button into empty
# board (its hue channel, of 255):
#     r    1.25  1.50  1.75
#     ref    35    31    25
#     here   36    30    26
const GLOW_PEAK := 0.210      # amount at the peak radius, at idle
const GLOW_R_IN := 0.86       # ramps up from here (inside is under the frame)
const GLOW_R_PEAK := 1.10     # brightest just outside the frame rim
const GLOW_FALLOFF := 0.63    # e-folding rate outward, per board unit
const GLOW_R_KNEE := 2.20     # the tail starts being cut here...
const GLOW_R_CUT := 3.20      # ...and is gone here (the reference keeps its
                              # backdrop near-black away from the buttons; without
                              # this the five tails meet and read as a colour wash
                              # over the whole frame)
const GLOW_PLANE_Y := 0.012   # just off the board plane, under every frame
const GLOW_PLANE_SIZE := 18.0
# Draw order for the transparent layers: pools on the board, then the stage
# plate, then its numeral on top of the plate.
const GLOW_PRIORITY := -2
const STAGE_PLATE_PRIORITY := -1
const STAGE_TEXT_PRIORITY := 1

const GLOW_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// Button centres on the board plane, and each one's pool colour premultiplied by
// its current intensity. Five entries, in the device's own button order.
uniform vec2 centers[5];
uniform vec3 tints[5];
uniform float r_in;
uniform float r_peak;
uniform float falloff;
uniform float r_knee;
uniform float r_cut;

varying vec2 board;

void vertex() {
	// The plane is centred on the board origin and unrotated, so its local XZ is
	// board XZ.
	board = VERTEX.xz;
}

void fragment() {
	vec3 acc = vec3(0.0);
	for (int i = 0; i < 5; i++) {
		float r = distance(board, centers[i]);
		float s = r < r_peak
			? smoothstep(r_in, r_peak, r)
			: exp(-falloff * (r - r_peak)) * (1.0 - smoothstep(r_knee, r_cut, r));
		acc += tints[i] * s;
	}
	// Normal (not additive) blending, so the pool writes alpha and survives
	// compositing over a transparent viewport. Splitting the accumulated light
	// into a full-strength hue plus a coverage alpha makes the result identical to
	// an additive blend everywhere the backdrop is dark, which it is.
	float a = clamp(max(max(acc.r, acc.g), acc.b), 0.0, 1.0);
	ALBEDO = a > 0.0001 ? acc / a : vec3(0.0);
	ALPHA = a;
}
"""

# ---------------------------------------------------------------------------
# Stage plate (the round number)
# ---------------------------------------------------------------------------
# The V3 board has no centre module, so the round number is added here. It is NOT
# put in the empty middle: it lies flat ON the board plane behind the back button,
# so it shares the board's perspective, foreshortening and lighting and reads as
# part of the same physical object rather than as a label floating over it.
#
# It is a compact pill — a dark inset plate with a thin cool hairline edge — sized
# and dimmed to stay clearly secondary to the five colours.
const STAGE_POS := Vector3(0.0, 0.014, -5.10)
const STAGE_SIZE := Vector2(2.60, 1.18)      # full width/depth of the pill
const STAGE_CORNER := 0.59                   # = half the depth, so it is a capsule
const STAGE_EDGE := 0.055                    # hairline thickness
const STAGE_FILL := Color(0.20, 0.215, 0.25, 0.90)
# HDR: AgX at this exposure rolls 1.0 down to a mid grey, so a hairline that
# should read as bright metal has to be driven past white.
const STAGE_EDGE_COLOR := Color(1.15, 1.30, 1.55)
const STAGE_DIGIT_H := 0.78                  # cap height of the numeral
const STAGE_MAX_W := 1.95
const STAGE_FONT_SIZE := 96
const STAGE_CAP_RATIO := 0.733               # cap height as a fraction of font_size
const STAGE_BASELINE_BIAS := 0.024           # centres the digit ink, not the line box
const STAGE_TEXT_COLOR := Color(0.86, 0.90, 0.96)
const STAGE_TEXT_ENERGY := 2.60
const STAGE_FONT_PATH := "res://fonts/arial.ttf"
const STAGE_EMBOLDEN := 0.36

const STAGE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec2 half_size;
uniform float corner;
uniform float edge;
uniform vec4 fill_color : source_color;
uniform vec4 edge_color : source_color;

varying vec2 plate;

void vertex() {
	plate = VERTEX.xz;
}

void fragment() {
	// Rounded-rectangle distance: negative inside, zero on the outline.
	vec2 d = abs(plate) - (half_size - vec2(corner));
	float sd = length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0) - corner;
	float aa = max(fwidth(sd), 0.0015);
	float inside = 1.0 - smoothstep(-aa, aa, sd);
	// A hairline band hugging the outline from the inside.
	float band = 1.0 - smoothstep(edge - aa, edge + aa, abs(sd + edge * 0.5));
	band *= inside;
	vec3 col = mix(fill_color.rgb, edge_color.rgb, band);
	float a = max(fill_color.a * inside, edge_color.a * band);
	ALBEDO = col;
	ALPHA = a;
}
"""

# Emitted when a button is tapped, if this device is handling its own input
# (see input_enabled). game.gd drives input itself, so it turns that off — these
# exist for anything that wants the panel to be self-contained.
signal button_pressed(idx: int)
signal color_pressed(color_name: String)

# When true the device raycasts taps itself and emits the signals above. game.gd
# sets this false: it must gate presses on its own game state (only during the
# player's turn, never behind the quit dialog), so it queries segment_at_point
# instead and there must not be a second, ungated handler.
var input_enabled := true

var _vpc: SubViewportContainer
var _vp: SubViewport
var _cam: Camera3D
var _board: Node3D               # the instantiated GLB scene
var _ap: AnimationPlayer         # the GLB's own AnimationPlayer (Press_* clips)

# Per-button state, all indexed by button index (0..4).
var _face_mats: Array[StandardMaterial3D] = []   # the coloured top surface
var _ring_mats: Array[StandardMaterial3D] = []   # the bright rim on that surface
var _glow_mats: Array[StandardMaterial3D] = []   # the under-glow inside the frame
var _face_base: Array[Color] = []                # authored emission, LINEAR light
var _ring_base: Array[Color] = []
var _glow_base: Array[Color] = []
var _pool_tint: Array[Vector3] = []              # ground-pool hue, LINEAR
var _surf_levels: Array[Dictionary] = []
var _ring_levels: Array[Dictionary] = []
var _emit_cur: Array[float] = []
var _emit_tgt: Array[float] = []
var _ring_cur: Array[float] = []
var _ring_tgt: Array[float] = []
var _lit: Array[bool] = []
var _pressing: Array[bool] = []
var _enabled: Array[bool] = []
var _areas: Dictionary = {}                      # Area3D instance id -> button index
var _centres: Array[Vector2] = []                # button centres on the board plane

# Guard so a press that arrives as BOTH set_press() and set_lit() in the same
# frame (game.gd's _press_feedback does exactly that) only restarts the clip once.
var _anim_idx := -1
var _anim_frame := -1
# Separate guard for self-handled taps: emulate_touch_from_mouse turns one click
# into both a MouseButton and a ScreenTouch event.
var _tap_frame := -1

var _readout: Label3D
var _num_pack: Variant = null
var _glow_mat: ShaderMaterial
var _fit_points: PackedVector3Array = PackedVector3Array()
# The viewport size the framing was last fitted for. The SubViewport takes its
# size from the stretching container a frame or more AFTER this Control is sized,
# so fitting once during _ready would fit against a 2x2 placeholder and leave the
# board cropped. _process re-fits the moment the real size lands.
var _fitted_size := Vector2i.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _vpc == null:
		_build_shell()
	resized.connect(_on_resized)

# ---------------- build ----------------

func _build_shell() -> void:
	_vpc = SubViewportContainer.new()
	_vpc.stretch = true
	_vpc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vpc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# PREMULTIPLIED alpha, not the default straight-alpha blend. A transparent
	# SubViewport hands back a texture whose colour is ALREADY multiplied by its
	# coverage; compositing that with the normal blend multiplies by alpha a second
	# time, which annihilates anything faint. Every pixel the board itself draws is
	# fully opaque so it never noticed — but the ground pools and the stage plate
	# are deliberately faint, and under straight alpha they were squared away to
	# nothing.
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	_vpc.material = cm
	add_child(_vpc)

	_vp = SubViewport.new()
	# Transparent, so the board composites over whatever the game (or an equipped
	# shop theme) has drawn behind it.
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	# MSAA on a render-target SubViewport is a heavy allocation on mobile GL
	# drivers. The board's silhouettes are all big discs, which is the case that
	# needs it least.
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	# Start idle; _process/_kick_render drive the redraw cadence from there.
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vpc.add_child(_vp)

	_build_environment()
	_build_camera()
	_build_lights()

	_board = MODEL.instantiate() as Node3D
	_vp.add_child(_board)
	_ap = _board.find_child("AnimationPlayer", true, false) as AnimationPlayer

	_space_buttons()
	_recolour_jade()
	_build_buttons()
	_build_ground_glow()
	_build_stage_plate()
	_collect_fit_points()
	_fit_camera()

# Push the five button PARENTS outward from the middle. Only the parent nodes'
# translations change: the meshes under them keep their authored transforms, so
# every button keeps its size, its proportions and its orientation relative to the
# board, and the pentagon keeps its exact equal-angle arrangement.
func _space_buttons() -> void:
	for key: String in COLOR_KEYS:
		var holder := _board.find_child("Button_%s" % key, true, false) as Node3D
		if holder == null:
			continue
		var p := holder.position
		holder.position = Vector3(p.x * SPACING_SCALE, p.y, p.z * SPACING_SCALE)

# Darken Jade to the deep-emerald target so it cannot be confused with Cyan.
# See the JADE_* note: this is a brightness change along the authored hue, applied
# as one factor to the surface and the under-glow so the whole button moves
# together. The rim ring and the frame are untouched.
func _recolour_jade() -> void:
	var surf := _board.find_child("Button_%s_Surface" % JADE_KEY, true, false) as MeshInstance3D
	var frame := _board.find_child("Button_%s_Frame" % JADE_KEY, true, false) as MeshInstance3D
	if surf == null or frame == null:
		return
	var src := surf.mesh.surface_get_material(0) as StandardMaterial3D
	if src == null:
		return
	var target := JADE_TARGET.srgb_to_linear()
	var dim := JADE_DIM

	var face := _own_material(surf, 0)
	if face != null:
		face.albedo_color = target.linear_to_srgb()
		face.emission = (_imported_emission(face) * dim).linear_to_srgb()
		face.emission_energy_multiplier = 1.0
	var glow := _own_material(frame, 1)
	if glow != null:
		glow.emission = (_imported_emission(glow) * dim).linear_to_srgb()
		glow.emission_energy_multiplier = 1.0

# A dark studio. The frames are METALLIC 0.9, so they take almost no diffuse at
# all: the sky and the lights' SPECULAR are the only knobs that touch them, and a
# bright or blue sky would lift the near-black chassis to grey. The coloured tops
# are ~80% self-lit, so ambient only supplies the remainder.
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR   # transparent for compositing

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

	# AGX, matching the view transform the reference was rendered through.
	# This is not a taste call, it is measurable: the Violet button has exactly zero
	# green in its albedo AND its emission, yet the reference renders its top at
	# (99,97,192). Only a strongly desaturating filmic transform lifts a channel
	# that is not there at all — which is what AgX does, and which is Blender 4.x's
	# default. Rendered LINEAR the same materials come out as raw neon (cyan at
	# (0,252,242) against the reference's (70,167,167)), and the whole palette reads
	# as saturated UI rather than as lit plastic.
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	# Swept against the reference's four measurable tops rather than guessed. At
	# exposure 1.0 the whole palette runs 40-80 counts hot (cyan (147,212,209)
	# against (70,167,167)); 0.40 lands crimson and cyan within about 8 and keeps
	# amber and violet a touch more saturated than Blender's AgX, which is the
	# right side to err on for a game that is entirely about telling colours apart.
	env.tonemap_exposure = 0.40
	# Off deliberately: see the GLOW_* note. It has no falloff under this renderer,
	# it writes no alpha over a transparent viewport, and it costs a full-screen
	# pass to do nothing useful.
	env.glow_enabled = false

	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)

func _build_camera() -> void:
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.keep_aspect = Camera3D.KEEP_WIDTH
	_cam.fov = CAM_FOV
	_cam.near = 0.15
	_cam.far = 80.0
	_vp.add_child(_cam)
	_place_camera(CAM_DIST_START, Vector3.ZERO)

# Put the camera `dist` back along the fitted elevation, looking at the board, and
# optionally slide the whole rig sideways/up to re-centre the composition. The
# slide moves camera AND target together, so it translates the framing without
# changing the viewing angle — the board keeps exactly the tilt it was fitted for.
func _place_camera(dist: float, slide: Vector3) -> void:
	var e := deg_to_rad(CAM_ELEV_DEG)
	var target := CAM_TARGET + slide
	var pos := target + Vector3(0.0, sin(e), cos(e)) * dist
	# look_at_from_position works off-tree too.
	_cam.look_at_from_position(pos, target, Vector3.UP)

func _build_lights() -> void:
	# Front-upper-left key. Diffuse is small — the tops carry their own colour as
	# emission — but the specular lobe is what puts the studio highlight on every
	# metal frame and the gloss streak across each dome, which is where the sense of
	# physical depth comes from.
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42.0, -34.0, 0.0)
	key.light_energy = 0.14
	key.light_specular = 1.5
	key.light_color = Color(1.0, 0.99, 0.97)
	key.shadow_enabled = false
	_vp.add_child(key)

	# A cool grazing fill from behind the board. It barely touches anything facing
	# the camera, but it picks out the far rim of each frame, which is the
	# separation that keeps the buttons from merging into the dark backdrop.
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-16.0, 158.0, 0.0)
	fill.light_energy = 0.05
	fill.light_specular = 1.2
	fill.light_color = Color(0.80, 0.86, 1.0)
	fill.shadow_enabled = false
	_vp.add_child(fill)

# Per button: give the coloured face, its rim ring and the under-glow their OWN
# material copies so each button's emission can be driven independently, and hang
# an invisible Area3D off the STATIONARY parent so taps hit that button alone.
func _build_buttons() -> void:
	for arr: Array in [_face_mats, _ring_mats, _glow_mats, _face_base, _ring_base,
			_glow_base, _pool_tint, _surf_levels, _ring_levels, _emit_cur, _emit_tgt,
			_ring_cur, _ring_tgt, _lit, _pressing, _enabled, _centres]:
		arr.clear()
	_areas.clear()

	for idx in NUM_BUTTONS:
		var key: String = COLOR_KEYS[idx]
		var holder := _board.find_child("Button_%s" % key, true, false) as Node3D
		var surf := _board.find_child("Button_%s_Surface" % key, true, false) as MeshInstance3D
		var frame := _board.find_child("Button_%s_Frame" % key, true, false) as MeshInstance3D

		# How the GLB packs them: the surface mesh carries the coloured top on
		# surface 0 and its bright rim on surface 1; the frame mesh carries the metal
		# on surface 0 and the under-glow on surface 1. That split is what lets the
		# glow be driven apart from the colour without touching any geometry.
		var face := _own_material(surf, 0)
		var ring := _own_material(surf, 1)
		var glow := _own_material(frame, 1)
		_face_mats.append(face)
		_ring_mats.append(ring)
		_glow_mats.append(glow)
		_face_base.append(_imported_emission(face))
		_ring_base.append(_imported_emission(ring))
		_glow_base.append(_imported_emission(glow))
		_pool_tint.append(_pool_hue(face))

		var levels := _read_states(surf)
		_surf_levels.append(levels[0])
		_ring_levels.append(levels[1])

		_emit_cur.append(1.0)
		_emit_tgt.append(1.0)
		_ring_cur.append(1.0)
		_ring_tgt.append(1.0)
		_lit.append(false)
		_pressing.append(false)
		_enabled.append(true)
		_centres.append(Vector2(holder.position.x, holder.position.z) if holder else Vector2.ZERO)

		_add_button_area(holder, idx)
		_apply_emission(idx)

# Duplicate one surface's material into a per-instance override so changing its
# emission can't bleed into anything else sharing that resource. The duplicate
# starts life identical to the imported material.
func _own_material(mi: MeshInstance3D, surface: int) -> StandardMaterial3D:
	if mi == null or mi.mesh == null or surface >= mi.mesh.get_surface_count():
		return null
	var existing := mi.get_surface_override_material(surface) as StandardMaterial3D
	if existing != null:
		return existing
	var src := mi.mesh.surface_get_material(surface) as StandardMaterial3D
	if src == null:
		return null
	var dup := src.duplicate() as StandardMaterial3D
	mi.set_surface_override_material(surface, dup)
	return dup

# The linear light an imported material emits, resolved once.
#
# This is NOT the same as reading `emission` off the material: Godot stores the
# emission colour in sRGB and folds `emission_energy_multiplier` in BEFORE the
# conversion to linear, so the pair only means what Blender authored once it has
# been resolved through the same conversion the renderer will use.
func _imported_emission(m: StandardMaterial3D) -> Color:
	if m == null or not m.emission_enabled:
		return Color(0, 0, 0)
	return m.emission.srgb_to_linear() * m.emission_energy_multiplier

# The hue a button's ground pool takes: its own top colour, normalised to full
# strength so the pool is a saturated wash rather than a dim copy.
func _pool_hue(face: StandardMaterial3D) -> Vector3:
	if face == null:
		return Vector3.ONE
	var c := face.albedo_color.srgb_to_linear()
	var m := maxf(c.r, maxf(c.g, c.b))
	if m <= 0.0001:
		return Vector3.ONE
	return Vector3(c.r / m, c.g / m, c.b / m)

# The four emission levels, as multipliers on the authored value. The V3 export
# carries no glTF `extras`; if a later one does, the scene importer preserves them
# as a node meta dictionary called "extras" and they are honoured here, normalised
# against whatever that export calls idle.
func _read_states(surf: MeshInstance3D) -> Array[Dictionary]:
	var extras: Dictionary = {}
	if surf != null and surf.has_meta("extras"):
		var m: Variant = surf.get_meta("extras")
		if m is Dictionary:
			extras = m
	var s: Dictionary = {}
	var r: Dictionary = {}
	var s_idle := float(extras.get("emission_idle", 0.0))
	var r_idle := float(extras.get("ring_idle", 0.0))
	for st: String in [STATE_IDLE, STATE_HIGHLIGHT, STATE_PRESSED, STATE_DISABLED]:
		s[st] = (float(extras["emission_%s" % st]) / s_idle) if (s_idle > 0.0 and extras.has("emission_%s" % st)) else FALLBACK_SURFACE[st]
		r[st] = (float(extras["ring_%s" % st]) / r_idle) if (r_idle > 0.0 and extras.has("ring_%s" % st)) else FALLBACK_RING[st]
	return [s, r]

# One invisible Area3D per button, parented to the button's STATIONARY parent
# node — never to the surface, which travels 11.5cm on every press. A collider
# that rode the animation would drag the hit target with it.
#
# The shape is a plain disc-shaped cylinder standing on the board, which is the
# button's own axis, sized a little past the visible frame so taps are forgiving.
# The buttons sit 2.47 apart centre-to-centre after spacing, so at this radius
# five discs still cannot overlap.
func _add_button_area(holder: Node3D, idx: int) -> void:
	if holder == null:
		return
	var shape := CylinderShape3D.new()
	shape.radius = 1.12
	# Only as tall as the button itself (the frame starts at 0 and the raised
	# surface tops out at 0.525). A taller cylinder sticks up into the path of the
	# grazing rays that reach the board BEHIND it, and a tap on the stage plate
	# would register as a press of the back button.
	shape.height = 0.62
	var area := Area3D.new()
	area.name = "Hit_%s" % COLOR_KEYS[idx]
	area.monitoring = false        # we only ever query it with a ray
	area.monitorable = false
	area.input_ray_pickable = true
	var cs := CollisionShape3D.new()
	cs.shape = shape
	# A CylinderShape3D already stands along Y, which is the button's axis.
	cs.position = Vector3(0.0, 0.30, 0.0)
	area.add_child(cs)
	holder.add_child(area)
	_areas[area.get_instance_id()] = idx

# The ground pools: one plane lying on the board, shader-summed per button.
func _build_ground_glow() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(GLOW_PLANE_SIZE, GLOW_PLANE_SIZE)
	var sh := Shader.new()
	sh.code = GLOW_SHADER
	_glow_mat = ShaderMaterial.new()
	_glow_mat.shader = sh
	_glow_mat.render_priority = GLOW_PRIORITY
	var centres := PackedVector2Array()
	for c: Vector2 in _centres:
		centres.append(c)
	_glow_mat.set_shader_parameter("centers", centres)
	_glow_mat.set_shader_parameter("r_in", GLOW_R_IN)
	_glow_mat.set_shader_parameter("r_peak", GLOW_R_PEAK)
	_glow_mat.set_shader_parameter("falloff", GLOW_FALLOFF)
	_glow_mat.set_shader_parameter("r_knee", GLOW_R_KNEE)
	_glow_mat.set_shader_parameter("r_cut", GLOW_R_CUT)

	var mi := MeshInstance3D.new()
	mi.name = "GroundGlow"
	mi.mesh = plane
	mi.material_override = _glow_mat
	mi.position = Vector3(0.0, GLOW_PLANE_Y, 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vp.add_child(mi)
	_push_glow()

# Push each button's current pool colour (its own hue, scaled by how far its glow
# has risen above idle) into the shader.
func _push_glow() -> void:
	if _glow_mat == null:
		return
	var tints := PackedVector3Array()
	for idx in NUM_BUTTONS:
		tints.append(_pool_tint[idx] * (GLOW_PEAK * _ring_cur[idx]))
	_glow_mat.set_shader_parameter("tints", tints)

# The stage plate: a pill lying on the board behind the back button, carrying the
# round number. Nothing about the five buttons is touched, and nothing is placed
# in the empty middle.
func _build_stage_plate() -> void:
	var plane := PlaneMesh.new()
	plane.size = STAGE_SIZE * 1.4        # room for the rounded corners' antialiasing
	var sh := Shader.new()
	sh.code = STAGE_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	# Explicit ordering for the three transparent layers. Distance sorting alone
	# put the plate on top of its own numeral — the fill is 90% opaque, so the
	# number came back out at (37,45,48), barely above the fill itself.
	mat.render_priority = STAGE_PLATE_PRIORITY
	mat.set_shader_parameter("half_size", STAGE_SIZE * 0.5)
	mat.set_shader_parameter("corner", STAGE_CORNER)
	mat.set_shader_parameter("edge", STAGE_EDGE)
	mat.set_shader_parameter("fill_color", STAGE_FILL)
	mat.set_shader_parameter("edge_color", STAGE_EDGE_COLOR)

	var plate := MeshInstance3D.new()
	plate.name = "StagePlate"
	plate.mesh = plane
	plate.material_override = mat
	plate.position = STAGE_POS
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vp.add_child(plate)

	var l := Label3D.new()
	l.name = "RoundNumber"
	l.text = "1"
	l.font_size = STAGE_FONT_SIZE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# A lit readout emits its own light; shading it would sink it into the board's
	# shadow and it would stop reading as part of the plate.
	l.shaded = false
	l.double_sided = false
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	l.no_depth_test = false
	l.render_priority = STAGE_TEXT_PRIORITY
	l.modulate = STAGE_TEXT_COLOR * STAGE_TEXT_ENERGY
	l.font = _stage_font()
	# Lie the glyphs down onto the board: -90 deg about X puts the text plane's
	# normal along +Y and its top toward -Z (the far edge, which is up on screen),
	# so it reads the right way round under this camera.
	l.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	l.position = STAGE_POS + Vector3(0.0, 0.004, 0.0)
	_vp.add_child(l)
	_readout = l
	_fit_readout()

# Size and seat the readout so the digits keep a constant cap height, shrinking
# only when a long number would overrun the plate.
func _fit_readout() -> void:
	if _readout == null:
		return
	var f: Font = _readout.font if _readout.font != null else ThemeDB.fallback_font
	var cap_px := float(STAGE_FONT_SIZE) * STAGE_CAP_RATIO
	var ps := STAGE_DIGIT_H / maxf(1.0, cap_px)
	var w: float = f.get_string_size(
		_readout.text, HORIZONTAL_ALIGNMENT_LEFT, -1, STAGE_FONT_SIZE).x * ps
	if w > STAGE_MAX_W:
		ps *= STAGE_MAX_W / w
	_readout.pixel_size = ps
	# Label3D centres the line box, but digits have no descender, so their ink sits
	# above that centre. Push it back down by the measured bias. On the flat plate
	# "down" on screen is +Z.
	_readout.position.z = STAGE_POS.z + STAGE_BASELINE_BIAS * float(STAGE_FONT_SIZE) * ps

func _stage_font(base: Font = null) -> Font:
	var src: Font = base
	if src == null and ResourceLoader.exists(STAGE_FONT_PATH):
		var f := load(STAGE_FONT_PATH)
		if f is Font:
			src = f
	if src == null:
		return null
	var fv := FontVariation.new()
	fv.base_font = src
	fv.variation_embolden = STAGE_EMBOLDEN
	return fv

# ---------------- camera fitting ----------------

# Every point the framing must not crop: each button's frame rim and the top edge
# of its raised surface, plus the stage plate's corners. Gathered once, since none
# of it moves (the press animation only sinks a surface).
func _collect_fit_points() -> void:
	_fit_points = PackedVector3Array()
	for idx in NUM_BUTTONS:
		var c: Vector2 = _centres[idx]
		for i in 16:
			var a := TAU * float(i) / 16.0
			var ca := cos(a)
			var sa := sin(a)
			_fit_points.append(Vector3(c.x + ca * 1.0, 0.0, c.y + sa * 1.0))
			_fit_points.append(Vector3(c.x + ca * 0.745, 0.525, c.y + sa * 0.745))
	var hs := STAGE_SIZE * 0.5
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_fit_points.append(STAGE_POS + Vector3(hs.x * sx, 0.0, hs.y * sz))

# Frame the board: pull the camera back until everything fits the viewport with a
# margin, then slide the rig so the composition sits centred. Both steps iterate,
# because a perspective camera is not a pure scale — two passes are enough to
# settle to well under a pixel.
func _fit_camera() -> void:
	if _cam == null or _vp == null or _fit_points.is_empty():
		return
	var vp := Vector2(_vp.size)
	if vp.x < 8.0 or vp.y < 8.0:
		return
	_fitted_size = _vp.size
	var dist := CAM_DIST_START
	var slide := Vector3.ZERO
	for _pass in 3:
		_place_camera(dist, slide)
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		for p: Vector3 in _fit_points:
			var s := _cam.unproject_position(p)
			mn = mn.min(s)
			mx = mx.max(s)
		var span := mx - mn
		if span.x <= 0.0 or span.y <= 0.0:
			return
		var k := maxf(span.x / (vp.x * FIT_FILL_X), span.y / (vp.y * FIT_FILL_Y))
		dist = clampf(dist * k, CAM_DIST_MIN, CAM_DIST_MAX)
		# Re-centre. Pixels -> world at the target's depth, then slide the rig along
		# its own right/up axes so the framing translates without tilting.
		_place_camera(dist, slide)
		mn = Vector2(INF, INF)
		mx = Vector2(-INF, -INF)
		for p: Vector3 in _fit_points:
			var s := _cam.unproject_position(p)
			mn = mn.min(s)
			mx = mx.max(s)
		var centre := (mn + mx) * 0.5
		var want := Vector2(vp.x * 0.5, vp.y * FIT_CENTRE_Y)
		var per_world := (vp.y * 0.5) / (tan(deg_to_rad(_cam_fov_y()) * 0.5) * dist)
		var delta := (want - centre) / maxf(per_world, 0.0001)
		var b := _cam.global_transform.basis
		slide += b.x * -delta.x + b.y * delta.y
	_place_camera(dist, slide)

# The effective VERTICAL fov. The camera is KEEP_WIDTH, so `fov` is horizontal and
# the vertical one follows the viewport's aspect.
func _cam_fov_y() -> float:
	var vp := Vector2(_vp.size)
	var aspect: float = (vp.x / vp.y) if vp.y > 0.0 else 1.7778
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(_cam.fov) * 0.5) / maxf(aspect, 0.01)))

# ---------------- emission state machine ----------------

# Which of the four states a button should currently be showing. Disabled wins
# outright; otherwise a highlight (sequence playback) reads brighter than a press,
# so it takes precedence while both are active — which is what a player press
# does, since game.gd asks for both at once.
func _state_of(idx: int) -> String:
	if not _enabled[idx]:
		return STATE_DISABLED
	if _lit[idx]:
		return STATE_HIGHLIGHT
	if _pressing[idx]:
		return STATE_PRESSED
	return STATE_IDLE

func _retarget(idx: int) -> void:
	var st := _state_of(idx)
	_emit_tgt[idx] = _surf_levels[idx][st]
	_ring_tgt[idx] = _ring_levels[idx][st]
	_kick_render()

# Push the current state onto the materials.
#
# The level is applied to the emission COLOUR in linear light with the energy
# multiplier pinned at 1.0 — NOT by scaling that multiplier, which is the obvious
# way and is wrong. Godot multiplies the energy into the stored sRGB colour and
# converts afterwards, so the multiplier scales the authored value through a ~2.4
# gamma: asking for a 2.6x rise by setting the multiplier to 2.6 emits about 8x
# and flares a saturated colour to washed-out white.
func _apply_emission(idx: int) -> void:
	var lvl: float = _emit_cur[idx] * EMISSION_MATCH
	var glow: float = _ring_cur[idx] * EMISSION_MATCH
	var face: StandardMaterial3D = _face_mats[idx]
	if face != null:
		face.emission = (_face_base[idx] * lvl).linear_to_srgb()
		face.emission_energy_multiplier = 1.0
	var ring: StandardMaterial3D = _ring_mats[idx]
	if ring != null:
		ring.emission = (_ring_base[idx] * glow).linear_to_srgb()
		ring.emission_energy_multiplier = 1.0
	var under: StandardMaterial3D = _glow_mats[idx]
	if under != null:
		under.emission = (_glow_base[idx] * glow).linear_to_srgb()
		under.emission_energy_multiplier = 1.0

# ---------------- press animation ----------------

# Play exactly one Press_* clip. Each clip carries all five buttons — the pressed
# one sinking, the other four pinned at their rest pose — so only the named button
# ever moves, and a clip cannot leave a previous button stuck down. The frames are
# in no clip at all, so they never move: the surface sinks INTO its stationary
# frame, which is the whole point of the animation.
func _trigger_press(idx: int) -> void:
	if _ap == null or idx < 0 or idx >= NUM_BUTTONS:
		return
	var frame := Engine.get_process_frames()
	if _anim_idx == idx and _anim_frame == frame:
		return   # same press arriving twice in one frame (set_press + set_lit)
	_anim_idx = idx
	_anim_frame = frame
	var clip := "Press_%s" % COLOR_KEYS[idx]
	if not _ap.has_animation(clip):
		return
	if _ap.current_animation == clip and _ap.is_playing():
		_ap.seek(0.0, true)
	else:
		# A short blend keeps a retrigger from snapping the previous button back up.
		_ap.play(clip, 0.05)
	_kick_render()

# ---------------- public API (SimonWheel compatible) ----------------

# `count` and `colors` come from game.gd's difficulty setup. This is a fixed
# five-button board with its own authored palette, so both are accepted and
# ignored — the signature exists so game.gd can drive either device.
func configure(_count: int, _colors: Array) -> void:
	if _vpc == null:
		_build_shell()
	_kick_render()

# Only the level-number font package applies to this device; the modelled board
# colours and the special skins belong to SimonWheel. The frames are deliberately
# left alone — they are the cosmetic slot, and swapping them is
# set_frame_material's job.
func apply_skin(_outer: Variant, _inner: Variant, number: Variant, _skin_id: String = "") -> void:
	_num_pack = number
	_apply_num_pack()

# Sequence playback: light the button, don't sink it. game.gd's _flash calls this
# with `true` for flash_time and then `false`.
func set_lit(idx: int, on: bool) -> void:
	if idx < 0 or idx >= NUM_BUTTONS or _lit.is_empty():
		return
	_lit[idx] = on
	_retarget(idx)

# Press feedback. game.gd sinks a button with set_press(idx, 1.0) and releases it
# 0.18s later with 0.0. The GLB's clip sinks AND raises on its own, so the release
# only has to clear the brightening.
func set_press(idx: int, amount: float) -> void:
	if idx < 0 or idx >= NUM_BUTTONS or _pressing.is_empty():
		return
	var down := amount > 0.0
	_pressing[idx] = down
	if down:
		_trigger_press(idx)
	_retarget(idx)

func set_level(n: int) -> void:
	set_round_number(n)

# Maps a tap (in this Control's local coords) to a button index, or -1.
# Casts the camera ray through the SubViewport's own physics space and reads which
# button's Area3D it struck, so each button is hit-tested independently and the
# gaps between them are correctly dead.
func segment_at_point(local_pos: Vector2) -> int:
	if _cam == null or _vp == null or size.x <= 0.0 or size.y <= 0.0:
		return -1
	var vp := Vector2(_vp.size)
	if vp.x <= 0.0 or vp.y <= 0.0:
		vp = size
	var vpp := local_pos * (vp / size)
	var origin := _cam.project_ray_origin(vpp)
	var dir := _cam.project_ray_normal(vpp)
	# find_world_3d(), not world_3d — the latter is the (unset) override slot and
	# reads back null even though the SubViewport owns a world.
	var world := _vp.find_world_3d()
	if world == null:
		return -1
	var space := world.direct_space_state
	if space == null:
		return -1
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 200.0)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return -1
	var collider: Object = hit.get("collider")
	if collider == null:
		return -1
	return int(_areas.get(collider.get_instance_id(), -1))

# --- skin flourishes: SimonWheel-only, accepted as no-ops so game.gd's
# every-3rd/5th/8th-round calls stay untouched on this difficulty. ---
func erupt() -> void: pass
func electric_pulse() -> void: pass
func roulette_spin() -> void: pass
func roulette_celebrate() -> void: pass
func luna_light_chase() -> void: pass
func luna_celebrate() -> void: pass
func set_overlay_compact(_numeral_scale: float, _show_dot: bool) -> void: pass
func set_static_preview(_on: bool) -> void: pass
func set_preview_paused(_paused: bool) -> void: pass

# ---------------- public API (colour-named) ----------------

func index_of(color_name: String) -> int:
	return COLOR_KEYS.find(color_name.capitalize())

# Sequence playback for one colour: brighten the top, push the glow up, hold for
# `duration`, then ease back to idle. Timing lives here and nowhere else.
func play_color(color_name: String, duration: float = 0.45) -> void:
	var idx := index_of(color_name)
	if idx < 0:
		return
	set_lit(idx, true)
	if duration > 0.0:
		var t := get_tree().create_timer(duration)
		t.timeout.connect(func() -> void: set_lit(idx, false))

# A full press: the authored clip plus the pressed brightening, released on its
# own. This is what the device does to itself on a tap.
func press_color(color_name: String, hold: float = 0.18) -> void:
	var idx := index_of(color_name)
	if idx < 0:
		return
	set_press(idx, 1.0)
	if hold > 0.0:
		var t := get_tree().create_timer(hold)
		t.timeout.connect(func() -> void: set_press(idx, 0.0))

func set_color_enabled(color_name: String, on: bool) -> void:
	set_button_enabled(index_of(color_name), on)

func set_button_enabled(idx: int, on: bool) -> void:
	if idx < 0 or idx >= NUM_BUTTONS or _enabled.is_empty():
		return
	_enabled[idx] = on
	_retarget(idx)

func set_all_enabled(on: bool) -> void:
	for i in NUM_BUTTONS:
		set_button_enabled(i, on)

# The round number on the stage plate. Nothing about the five buttons changes.
func set_round_number(value: int) -> void:
	if _readout == null:
		return
	_readout.text = str(value)
	_fit_readout()
	_kick_render()

# The frames are the reserved cosmetic slot, one material per button so they can
# be re-skinned independently later. This swaps one without touching that button's
# top, rim or under-glow.
func set_frame_material(color_name: String, mat: Material) -> void:
	var mi := frame_mesh(color_name)
	if mi != null:
		mi.set_surface_override_material(0, mat)
		_kick_render()

func frame_mesh(color_name: String) -> MeshInstance3D:
	var idx := index_of(color_name)
	if idx < 0 or _board == null:
		return null
	return _board.find_child("Button_%s_Frame" % COLOR_KEYS[idx], true, false) as MeshInstance3D

func surface_mesh(color_name: String) -> MeshInstance3D:
	var idx := index_of(color_name)
	if idx < 0 or _board == null:
		return null
	return _board.find_child("Button_%s_Surface" % COLOR_KEYS[idx], true, false) as MeshInstance3D

# ---------------- input ----------------

# Self-contained tap handling, for anything that drops this device in without its
# own hit-testing. game.gd turns it off (see input_enabled) because presses there
# are only legal during the player's turn.
func _input(event: InputEvent) -> void:
	if not input_enabled or _vp == null:
		return
	var tap := Vector2(-1.0, -1.0)
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			tap = mb.position
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			tap = st.position
	if tap.x < 0.0:
		return
	# emulate_touch_from_mouse fires both a MouseButton and a ScreenTouch for one
	# click — guard against handling the same tap twice.
	var frame := Engine.get_process_frames()
	if frame == _tap_frame:
		return
	_tap_frame = frame
	var idx := segment_at_point(tap - global_position)
	if idx < 0 or not _enabled[idx]:
		return
	press_color(COLOR_KEYS[idx])
	button_pressed.emit(idx)
	color_pressed.emit(COLOR_KEYS[idx].to_lower())
	get_viewport().set_input_as_handled()

# ---------------- layout / per-frame ----------------

# The container is anchored to this Control's full rect and drives the
# SubViewport's size, so a resize only has to re-fit the framing.
func _on_resized() -> void:
	_fit_camera()
	_kick_render()

func _process(dt: float) -> void:
	if _vp != null and _vp.size != _fitted_size:
		_fit_camera()
	var animating := _ap != null and _ap.is_playing()
	var glow_dirty := false
	var k := clampf(dt * EMIT_LERP, 0.0, 1.0)
	for i in _emit_cur.size():
		var was_s: float = _emit_cur[i]
		var was_r: float = _ring_cur[i]
		_emit_cur[i] = lerpf(_emit_cur[i], _emit_tgt[i], k)
		if absf(_emit_cur[i] - _emit_tgt[i]) <= 0.002:
			_emit_cur[i] = _emit_tgt[i]
		_ring_cur[i] = lerpf(_ring_cur[i], _ring_tgt[i], k)
		if absf(_ring_cur[i] - _ring_tgt[i]) <= 0.002:
			_ring_cur[i] = _ring_tgt[i]
		# Push whenever the value MOVED, not whenever it is still short of the
		# target. Those are not the same test: a long frame makes k clamp to 1 and
		# the whole transition lands in one step, and the arrival step of a normal
		# transition also lands exactly on target — under a "still travelling" test
		# both would change the state without ever writing it to the material, and
		# the button would simply never light.
		if _emit_cur[i] != was_s or _ring_cur[i] != was_r:
			_apply_emission(i)
			glow_dirty = true
		if _emit_cur[i] != _emit_tgt[i] or _ring_cur[i] != _ring_tgt[i]:
			animating = true
	if glow_dirty:
		_push_glow()
	_update_render_activity(animating)

# Redraw only while something moves. Once the press clip has ended and the flash
# has settled we render one final frame (UPDATE_ONCE self-disables) and stop —
# continuously re-rendering static 3D content is what leaked the mobile GL
# driver's heap on long sessions (see SimonWheel's note).
func _update_render_activity(animating: bool) -> void:
	if _vp == null:
		return
	if animating:
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	elif _vp.render_target_update_mode == SubViewport.UPDATE_ALWAYS:
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE

# Force one redraw after something changed outside the per-frame loop (build,
# resize, a state change that starts on an idle frame).
func _kick_render() -> void:
	if _vp == null:
		return
	if _vp.render_target_update_mode != SubViewport.UPDATE_ALWAYS:
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE

# Apply the equipped level-number font package (shop "SIMON" tab). Only the
# typeface and tint carry over — the numeral is part of a modelled plate here, so
# it keeps the plate's own brightness rather than the hub-sized glow/outline
# treatment SimonWheel gives it.
func _apply_num_pack() -> void:
	if _readout == null:
		return
	var pack: Dictionary = _num_pack if (_num_pack is Dictionary) else {}

	var font: Font = null
	var fp := String(pack.get("font", ""))
	if fp != "" and ResourceLoader.exists(fp):
		var f := load(fp)
		if f is Font:
			font = f
	_readout.font = _stage_font(font)

	var tint: Color = pack.get("color", STAGE_TEXT_COLOR)
	_readout.modulate = Color(tint.r, tint.g, tint.b) * STAGE_TEXT_ENERGY
	_fit_readout()
