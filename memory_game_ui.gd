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
#   * the round number is a Godot-side HUD tab, because the V3 board has no
#     centre module to put it in (see level_tab.gd — every board uses it).
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
#   set_level(n)                  -> the LEVEL tab's readout
#   apply_button_frame(frame_id)  -> wear a frame cosmetic on every bezel
#                                    (resolved through _refresh_frame, so an active
#                                     Special Skin's own frame outranks the equipped one)
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
#
# ---------------------------------------------------------------------------
# One device, three boards
# ---------------------------------------------------------------------------
# Everything below is board-agnostic: which GLB, which colour keys, how far the
# buttons are pushed apart, where the camera sits and where the round number goes
# are read from the "board spec" vars further down, whose DEFAULTS are the Medium
# board and are what this class is on its own. HARD subclasses it
# (hard_game_ui.gd) for the six-button hexagon and EASY subclasses it
# (easy_game_ui.gd) for the three-button triangle; each overrides only that
# handful of values. The spacing, the emission state machine, the press clips, the
# hit-testing, the camera fitting, the LEVEL tab and the frame cosmetics are the
# same code, unchanged, for all three.

const MODEL: PackedScene = preload("res://models/MemoryGame_UI_Medium.glb")
# The right-edge LEVEL readout, shared by all three boards. Preloaded rather than
# referenced by class_name so it never depends on the editor's global-class scan.
const LEVEL_TAB := preload("res://level_tab.gd")

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
#
# This is the MEDIUM default and it is a board-spec value (`_spacing`): Hard's
# hexagon is authored at the same crowded 2.15 and takes the same push, but Easy's
# triangle is already authored 2.45 apart — the gap the other two only reach after
# being pushed — so it overrides this to 1.0 and is used exactly as authored.
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
# The authored radius of a button's frame disc, identical on all three boards
# (they are the same button, vertex for vertex — see easy_game_ui.gd's note). Used
# to work out how far the outermost button reaches, which is what limits how far a
# 3D background may be seated (see _seat_background).
const FRAME_RADIUS := 1.0

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
#
# The band shrank from 0.89/0.485 when the round number stopped being a plate
# lying on the board: the plate's corners were fit points, and dropping them let
# the five buttons grow into the room it had been holding — far enough that the
# two front buttons dipped into the status pill's row. These numbers put the
# nearest button ~14 px clear of that pill, which is the clearance Easy and Hard
# are already tuned to. They are very nearly Hard's own band (0.83/0.45), which
# is the sanity check: same tabletop, same HUD above and below it, same answer.
# The buttons still come out ~14% BIGGER than they were with the plate — the old
# band was wider but the plate was eating the top of it. Measured, not guessed:
# tools/tab_clear.tscn reports the clearance per board per aspect.
const FIT_FILL_X := 0.94
const FIT_FILL_Y := 0.83
const FIT_CENTRE_Y := 0.448

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
# Draw order for the transparent layers: the ground pools sit under everything
# else in the 3D scene.
const GLOW_PRIORITY := -2

const GLOW_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// Button centres on the board plane, and each one's pool colour premultiplied by
// its current intensity. One entry per button, in the device's own button order
// (the array length is patched in at build time from the board spec's count).
uniform vec2 centers[%d];
uniform vec3 tints[%d];
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
	for (int i = 0; i < %d; i++) {
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
# The LEVEL readout
# ---------------------------------------------------------------------------
# None of the three boards models one: there is no centre module on any of them,
# and the empty middle stays empty on all three (the old wheel's centre hub is not
# coming back in any form). The readout is 2D HUD instead — `level_tab.gd`'s
# deluxe tab, seated against the RIGHT edge under game.gd's Quit dome, identical
# on Easy, Medium and Hard.
#
# Two earlier readouts are gone with it: Medium's plate lying on the board behind
# its back button (which cost the camera fit ~15% of every button's on-screen size
# and only a pentagon had an edge to hang it off) and Easy/Hard's flat "ROUND n"
# pill in the bottom-left corner. One readout, one corner, one look.
#
# The board fit reserves the tab's column so no button can ever grow into it —
# see `_fit_camera`, which only pays for that reserve on aspects where width
# binds.

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

# ---------------------------------------------------------------------------
# Board spec
# ---------------------------------------------------------------------------
# The whole of "which board is this". Every value here defaults to the Medium
# board, so this class on its own is exactly what it always was; hard_game_ui.gd
# overrides them in its _init() and inherits the rest of the file untouched.
# Nothing below this block ever reads the MODEL / COLOR_KEYS / CAM_*
# constants directly — they are the DEFAULTS, and these vars are the truth.
var _model: PackedScene = MODEL
var _keys: Array = COLOR_KEYS
var _count: int = NUM_BUTTONS
var _spacing: float = SPACING_SCALE
var _jade_dim: float = JADE_DIM
var _cam_fov: float = CAM_FOV
var _cam_elev: float = CAM_ELEV_DEG
var _cam_target: Vector3 = CAM_TARGET
var _cam_dist_start: float = CAM_DIST_START
var _fit_fill_x: float = FIT_FILL_X
var _fit_fill_y: float = FIT_FILL_Y
var _fit_centre_y: float = FIT_CENTRE_Y

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

var _tab: Control                  # the left-edge LEVEL readout (LEVEL_TAB)
var _board_rect := Rect2()         # the board's silhouette on screen, from the fit
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
	# Equipping a frame in the shop re-skins a live board immediately — the device
	# owns this rather than game.gd because the cosmetic is purely presentational
	# and has nothing to do with the round in progress.
	CoinsManager.frames_changed.connect(_on_frames_changed)
	# Equipping a 3D background in the shop re-dresses a live board the same way a
	# frame does. Both signals fire on equip; themes_changed is the one that carries
	# a background change, and simon_changed because equipping a complete skin drops
	# whatever theme was on.
	CoinsManager.themes_changed.connect(_on_background_changed)
	CoinsManager.simon_changed.connect(_on_background_changed)

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
	_build_background()

	_board = _model.instantiate() as Node3D
	_vp.add_child(_board)
	_ap = _board.find_child("AnimationPlayer", true, false) as AnimationPlayer

	_space_buttons()
	_recolour_jade()
	_build_buttons()
	_refresh_frame()
	_build_ground_glow()
	_build_level_tab()
	_collect_fit_points()
	_fit_camera()

# Push the button PARENTS outward from the middle. Only the parent nodes'
# translations change: the meshes under them keep their authored transforms, so
# every button keeps its size, its proportions and its orientation relative to the
# board, and the polygon keeps its exact equal-angle arrangement. A board authored
# at the right spacing already (`_spacing == 1.0`, which is Easy) is left alone.
func _space_buttons() -> void:
	if is_equal_approx(_spacing, 1.0):
		return
	for key: String in _keys:
		var holder := _board.find_child("Button_%s" % key, true, false) as Node3D
		if holder == null:
			continue
		var p := holder.position
		holder.position = Vector3(p.x * _spacing, p.y, p.z * _spacing)

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
	var dim := _jade_dim

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
	_cam.fov = _cam_fov
	_cam.near = 0.15
	_cam.far = 80.0
	_vp.add_child(_cam)
	_place_camera(_cam_dist_start, Vector3.ZERO)

# Put the camera `dist` back along the fitted elevation, looking at the board, and
# optionally slide the whole rig sideways/up to re-centre the composition. The
# slide moves camera AND target together, so it translates the framing without
# changing the viewing angle — the board keeps exactly the tilt it was fitted for.
func _place_camera(dist: float, slide: Vector3) -> void:
	var e := deg_to_rad(_cam_elev)
	var target := _cam_target + slide
	var pos := target + Vector3(0.0, sin(e), cos(e)) * dist
	# look_at_from_position works off-tree too.
	_cam.look_at_from_position(pos, target, Vector3.UP)

# The visual layer the board itself occupies. Both lights below are culled to it,
# so they light the buttons and nothing else.
#
# That matters only once a 3D background is behind them (BackgroundScenes puts its
# meshes on layer 2). These two are a studio rig, not a physical one: their diffuse
# is almost nothing and their SPECULAR is turned up past 1 precisely to plant a
# highlight on six small metallic bezels. Pointed at a 20x15 metre floor of
# metallic 0.3 / roughness 0.33 the same rig lays a broad grey sheen across the
# whole frame — measured at (71,80,95) in the top-right corner of Neon Grid against
# the Blender reference's (3,14,29), which is the single largest difference the
# import had. Blender lights the floor with the background's OWN 47-light rig, and
# so now does this.
#
# Nothing about the buttons changes: they are on BOARD_LAYER and this is the only
# layer these lights were ever reaching.
const BOARD_LAYER := 1

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
	key.light_cull_mask = BOARD_LAYER
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
	fill.light_cull_mask = BOARD_LAYER
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

	for idx in _count:
		var key: String = _keys[idx]
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
# Both boards space their buttons 2.47 apart centre-to-centre (Medium's pentagon
# and Hard's hexagon are authored at 2.15 and scaled alike), so at this radius the
# discs still cannot overlap on either.
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
	area.name = "Hit_%s" % _keys[idx]
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
	# The uniform array lengths and the loop bound have to be literals in GLSL, so
	# the button count is substituted into the source rather than passed in.
	sh.code = GLOW_SHADER % [_count, _count, _count]
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
	for idx in _count:
		tints.append(_pool_tint[idx] * (GLOW_PEAK * _ring_cur[idx]))
	_glow_mat.set_shader_parameter("tints", tints)

# ---------------- the LEVEL tab ----------------

# The round readout: a sibling of the SubViewportContainer, so it draws over the
# board. It ignores mouse input, so a tap that lands on it still reaches game.gd
# and is hit-tested against the board underneath. _fit_camera positions it, since
# where it sits depends on where the board's left edge landed.
func _build_level_tab() -> void:
	_tab = LEVEL_TAB.new()
	add_child(_tab)
	_tab.layout_in(size, _board_rect)
	_tab.apply_number_pack(_num_pack)

# ---------------- camera fitting ----------------

# Every point the framing must not crop: each button's frame rim and the top edge
# of its raised surface. Gathered once, since none of it moves (the press
# animation only sinks a surface).
func _collect_fit_points() -> void:
	_fit_points = PackedVector3Array()
	for idx in _count:
		var c: Vector2 = _centres[idx]
		for i in 16:
			var a := TAU * float(i) / 16.0
			var ca := cos(a)
			var sa := sin(a)
			_fit_points.append(Vector3(c.x + ca * 1.0, 0.0, c.y + sa * 1.0))
			_fit_points.append(Vector3(c.x + ca * 0.745, 0.525, c.y + sa * 0.745))

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
	# The LEVEL tab holds a fixed column against the LEFT edge, and no button may
	# ever grow into it. It enters the fit as two LIMITS rather than as a margin:
	# the width the board may span, and how far LEFT its centre may sit. Neither
	# limit changes the board's SIZE on 16:9 and wider — height binds there, so the
	# scale, the elevation, the lens and the button spacing are exactly what they
	# were; the board only slides sideways to sit beside the column instead of on
	# top of it. A narrow (tall) aspect, where width binds, also shrinks — same as
	# it always did, since the column simply moved sides.
	# _fit_fill_x is a margin as much as a width: the board is meant to keep
	# (1 - fill) / 2 of the viewport clear on each side. The reserved column
	# replaces that margin on the left; the right keeps it, so a tall viewport —
	# where width binds and the column actually costs something — cannot push the
	# far edge of the board flush against the screen.
	var far_margin := vp.x * (1.0 - _fit_fill_x) * 0.5
	var avail_x := minf(vp.x * _fit_fill_x,
		maxf(vp.x - LEVEL_TAB.reserved_width() - far_margin, 64.0))
	var dist := _cam_dist_start
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
		var k := maxf(span.x / avail_x, span.y / (vp.y * _fit_fill_y))
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
		# Centred, unless that would put the board's left edge under the tab, in
		# which case it sits as far left as it can without doing so — and never so
		# far right that it crops on the other side.
		var half := span.x * 0.5
		var lo := LEVEL_TAB.reserved_width() + half
		var cx := clampf(vp.x * 0.5, lo, maxf(lo, vp.x - far_margin - half))
		var want := Vector2(cx, vp.y * _fit_centre_y)
		var per_world := (vp.y * 0.5) / (tan(deg_to_rad(_cam_fov_y()) * 0.5) * dist)
		var delta := (want - centre) / maxf(per_world, 0.0001)
		var b := _cam.global_transform.basis
		slide += b.x * -delta.x + b.y * delta.y
	_place_camera(dist, slide)
	_board_rect = _screen_rect()
	_seat_background()
	if _tab != null:
		_tab.layout_in(Vector2(_vp.size), _board_rect)

# Where the board's silhouette actually lands on screen, in viewport pixels. The
# tab seats itself against this rather than against a guessed margin, so each
# board's own width decides how much air the badge gets.
func _screen_rect() -> Rect2:
	if _cam == null:
		return Rect2()
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for p: Vector3 in _fit_points:
		var s := _cam.unproject_position(p)
		mn = mn.min(s)
		mx = mx.max(s)
	if mn.x > mx.x:
		return Rect2()
	return Rect2(mn, mx - mn)

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

# Play exactly one Press_* clip. Each clip only ever animates its own button's
# surface, so only the named button moves and a clip cannot leave a previous button
# stuck down. The frames are
# in no clip at all, so they never move: the surface sinks INTO its stationary
# frame, which is the whole point of the animation.
func _trigger_press(idx: int) -> void:
	if _ap == null or idx < 0 or idx >= _count:
		return
	var frame := Engine.get_process_frames()
	if _anim_idx == idx and _anim_frame == frame:
		return   # same press arriving twice in one frame (set_press + set_lit)
	_anim_idx = idx
	_anim_frame = frame
	var clip := "Press_%s" % _keys[idx]
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
# board with its own authored palette and its own button count, so both are
# accepted and ignored — the signature exists so game.gd can drive either device.
func configure(_count: int, _colors: Array) -> void:
	if _vpc == null:
		_build_shell()
	_kick_render()

# Only the level-number font package applies to this device; the modelled board
# colours belong to SimonWheel. What a Special Skin DOES reach here is the bezel:
# Arcade, Jackpot and Luna Park each bring a frame of their own, which outranks the
# equipped cosmetic for as long as that skin is the active look (see
# ButtonFrames.effective_frame). Everything else about the board is untouched.
func apply_skin(_outer: Variant, _inner: Variant, number: Variant, skin_id: String = "") -> void:
	_num_pack = number
	_apply_num_pack()
	if _skin_id != skin_id:
		_skin_id = skin_id
		_refresh_frame()

# Wear whatever the current skin + equipped-cosmetic pair resolves to. Every path
# that can change either of them comes through here rather than calling
# apply_button_frame with a raw id, so the priority is decided in exactly one place.
func _refresh_frame() -> void:
	apply_button_frame(ButtonFrames.effective_frame(CoinsManager.selected_frame, _skin_id))

# Sequence playback: light the button, don't sink it. game.gd's _flash calls this
# with `true` for flash_time and then `false`.
func set_lit(idx: int, on: bool) -> void:
	if idx < 0 or idx >= _count or _lit.is_empty():
		return
	_lit[idx] = on
	_retarget(idx)

# Press feedback. game.gd sinks a button with set_press(idx, 1.0) and releases it
# 0.18s later with 0.0. The GLB's clip sinks AND raises on its own, so the release
# only has to clear the brightening.
func set_press(idx: int, amount: float) -> void:
	if idx < 0 or idx >= _count or _pressing.is_empty():
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
	return _keys.find(color_name.capitalize())

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
	if idx < 0 or idx >= _count or _enabled.is_empty():
		return
	_enabled[idx] = on
	_retarget(idx)

func set_all_enabled(on: bool) -> void:
	for i in _count:
		set_button_enabled(i, on)

# The round number, on the right-edge LEVEL tab. Nothing about the buttons or the
# 3D scene changes, so this never has to kick the viewport.
func set_round_number(value: int) -> void:
	if _tab != null:
		_tab.set_level(value)

func frame_mesh(color_name: String) -> MeshInstance3D:
	var idx := index_of(color_name)
	if idx < 0 or _board == null:
		return null
	return _board.find_child("Button_%s_Frame" % _keys[idx], true, false) as MeshInstance3D

func surface_mesh(color_name: String) -> MeshInstance3D:
	var idx := index_of(color_name)
	if idx < 0 or _board == null:
		return null
	return _board.find_child("Button_%s_Surface" % _keys[idx], true, false) as MeshInstance3D

# ---------------- button-frame cosmetics ----------------
#
# The shop's equipped frame cosmetic, worn by ALL of this board's buttons at once —
# the player picks one frame, not one per colour, and the same global selection
# dresses the Medium board's five and the Hard board's six. There is no per-board
# and no per-difficulty inventory anywhere.
#
# A cosmetic is a real Blender MESH (see ButtonFrames), so wearing one means
# swapping which solid is drawn, not which material is on it:
#
#   * a shared `Cosmetic_Frame` MeshInstance3D goes under `Button_<Colour>` at the
#     identity transform. Both GLBs author the stock bezel at identity under that
#     same parent and the library authors every cosmetic at the origin with
#     transforms applied, so the two land on top of each other exactly — on five
#     buttons or on six, with no measuring and no scaling.
#   * the stock bezel's surface 0 (the metal) is covered with an invisible
#     material. Its surface 1 is this button's UNDER-GLOW, which the emission state
#     machine drives every frame and which sits at r <= 0.698 — inside the
#     cosmetic's r >= 0.766 opening, so it goes on showing through the new bezel.
#     Hiding the whole MeshInstance3D would have taken the glow with it.
#
# Untouched by all of it: the coloured top and its rim (surfaces 0 and 1 of the
# SURFACE mesh), the under-glow, the ground pools, the hit-testing, the camera and
# the press clips — which animate the surface mesh's transform only, so a cosmetic
# is stationary through a press by construction rather than by being told to be.
#
# "default" (and any id not in the catalog) frees the cosmetic node and clears the
# override, handing the button straight back to the GLB's own Mat_<Colour>_Frame —
# the stock black bezel, byte for byte, with nothing left behind.
#
# One Mesh and one set of three ShaderMaterials are shared by every button on the
# board, so an equip allocates N nodes and nothing else.
func apply_button_frame(frame_id: String) -> void:
	if _board == null:
		return
	var wear := ButtonFrames.is_cosmetic(frame_id)
	for key: String in _keys:
		var stock := _board.find_child("Button_%s_Frame" % key, true, false) as MeshInstance3D
		if stock == null:
			continue
		var holder := stock.get_parent()
		var worn := holder.get_node_or_null(ButtonFrames.INSTANCE_NAME) as MeshInstance3D
		if not wear:
			stock.set_surface_override_material(0, null)
			if worn != null:
				holder.remove_child(worn)
				worn.queue_free()
			continue
		if worn == null:
			worn = ButtonFrames.make_frame_instance(frame_id)
			if worn == null:
				# The library failed to load. Leave the stock bezel showing rather
				# than a button with no frame at all.
				stock.set_surface_override_material(0, null)
				continue
			holder.add_child(worn)
		else:
			var entry := ButtonFrames.build(frame_id)
			if not entry.is_empty():
				worn.mesh = entry["mesh"]
				var mats: Array = entry["mats"]
				for i in mats.size():
					worn.set_surface_override_material(i, mats[i])
		stock.set_surface_override_material(0, ButtonFrames.hidden_material())
	# Everything the player is not wearing goes back to the loader. During play this
	# leaves exactly one cosmetic's mesh and textures resident.
	ButtonFrames.trim_cache([frame_id])
	_frame_idle = ButtonFrames.animates(frame_id)
	_frame_idle_accum = 0.0
	_kick_render()

# The cosmetic currently worn by one button, or null. Exposed for the acceptance
# tests, which check placement and press-stationarity against the real board.
func cosmetic_frame(color_name: String) -> MeshInstance3D:
	var mi := frame_mesh(color_name)
	if mi == null:
		return null
	return mi.get_parent().get_node_or_null(ButtonFrames.INSTANCE_NAME) as MeshInstance3D

func _on_frames_changed() -> void:
	_refresh_frame()

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
	press_color(_keys[idx])
	button_pressed.emit(idx)
	color_pressed.emit(String(_keys[idx]).to_lower())
	get_viewport().set_input_as_handled()

# ---------------- layout / per-frame ----------------

# The container is anchored to this Control's full rect and drives the
# SubViewport's size, so a resize only has to re-fit the framing.
func _on_resized() -> void:
	# _fit_camera re-seats the tab itself: the badge is placed against the board's
	# new silhouette, so it can only be positioned once the fit has settled.
	_fit_camera()
	_kick_render()

func _process(dt: float) -> void:
	if _vp != null and _vp.size != _fitted_size:
		_fit_camera()
	_tick_frame_idle(dt)
	_tick_bg_idle(dt)
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

# The equipped cosmetic's idle breathing runs on TIME inside its shader, so it only
# advances when this SubViewport actually draws — and this board deliberately does
# not draw while nothing is moving. Rather than pin it to UPDATE_ALWAYS (which is
# what leaked the mobile GL driver's heap; see _update_render_activity), an idle
# board wearing an animated frame is nudged to redraw at FRAME_IDLE_HZ.
#
# 12 Hz is chosen against what the effect actually is: a 6-second cosine and a UV
# offset that advances one pattern period per loop. At 12 Hz the breath is sampled
# 72 times per cycle and the drift moves ~0.7% of a period per step, neither of
# which is resolvable. It costs a fifth of the redraws a continuous animation would
# and it stops entirely the moment a press or a flash takes over — those set
# UPDATE_ALWAYS on their own and the accumulator simply stops mattering.
const FRAME_IDLE_HZ := 12.0

# The active Special Skin ("" = none), pushed in by apply_skin. It is held because
# it is half of what decides which frame the board wears — the other half being the
# equipped cosmetic — and either can change without the other.
var _skin_id := ""
var _frame_idle := false            # is an ANIMATED cosmetic equipped?
var _frame_idle_accum := 0.0

# ---------------------------------------------------------------------------
# The 3D gameplay background
# ---------------------------------------------------------------------------
# The nine LUME backgrounds (BackgroundScenes) are floors, not wallpaper: they were
# authored in Blender against this exact camera, with the buttons standing on them.
# So they are built into THIS viewport, as a sibling of the board, and share its
# camera, its depth buffer and its tonemap. A button occludes the grid line behind
# it, its ground pool lands on the floor, and the whole composition is one render.
#
# Everything else about the board is untouched by this. The background's meshes sit
# on their own visual layer and its lights are culled to that layer, so no button's
# colour, emission or frame can be moved by whatever is equipped behind it.
#
# The paid 2D themes are unaffected too: BackgroundManager paints those on a
# CanvasLayer beneath this viewport, and this viewport is transparent everywhere a
# 3D background is not drawn — so exactly one of the two is ever visible.
var _bg_scene: Node3D
var _bg_id := ""
var _bg_idle := false               # is an ANIMATED background equipped?
var _bg_idle_accum := 0.0

func _build_background() -> void:
	var want := _wanted_background()
	if want == _bg_id:
		return
	_bg_id = want
	if _bg_scene != null:
		_bg_scene.queue_free()
		_bg_scene = null
	_bg_idle = false
	if want.is_empty():
		return
	_bg_scene = BackgroundScenes.build(want)
	if _bg_scene == null:
		_bg_id = ""
		return
	_vp.add_child(_bg_scene)
	_bg_idle = BackgroundScenes.is_animated(want)
	_seat_background()

# Which 3D background should be showing, or "" for none. A complete Special Skin
# outranks everything while it is on — the same rule BackgroundManager applies to
# the 2D themes — so a skin's bespoke world is never half-covered by a floor.
func _wanted_background() -> String:
	if not CoinsManager.is_simon_manual():
		return ""
	var t: String = CoinsManager.selected_theme
	return t if BackgroundScenes.has_scene(t) else ""

# Slide the 3D background along the ground so the composition its author framed
# lands where they framed it under THIS board's camera (see BackgroundScenes'
# REF_TOP_Y note). Runs from _fit_camera, so it re-seats on every resize and every
# difficulty on its own.
func _seat_background() -> void:
	# _build_shell builds the background BEFORE the board (so the floor is behind
	# it in the tree and draws first), which means the very first call has no
	# buttons to measure a reach from. _fit_camera runs a few lines later, once the
	# board exists, and seats it properly.
	if _bg_scene == null or _cam == null or _vp == null or _board == null:
		return
	var vp := Vector2(_vp.size)
	if vp.x < 8.0 or vp.y < 8.0:
		return
	# Where the ray through the middle of the TOP edge meets the board plane.
	var px := Vector2(vp.x * 0.5, 1.0)
	var o := _cam.project_ray_origin(px)
	var d := _cam.project_ray_normal(px)
	if d.y > -0.0001:
		return                        # looking at or above the horizon: nothing to seat
	# Godot z is the negation of Blender y.
	var top_y := -(o + d * (-o.y / d.y)).z
	_bg_scene.position.z = minf(
		BackgroundScenes.seat_wanted(_bg_id, top_y),
		BackgroundScenes.seat_allowed(_bg_id, _board_reach()))

# How far the outermost button reaches from the middle of the board: the furthest
# button parent plus the frame radius. Measured off the live board rather than
# taken from a constant, so a re-spaced or re-authored board stays correct.
func _board_reach() -> float:
	var r := 0.0
	for key: String in _keys:
		var holder := _board.find_child("Button_%s" % key, true, false) as Node3D
		if holder != null:
			r = maxf(r, Vector2(holder.position.x, holder.position.z).length())
	return r + FRAME_RADIUS

func _on_background_changed() -> void:
	if _vp == null:
		return
	_build_background()
	_kick_render()

# Same treatment an animated button frame gets: the animation runs on TIME inside
# the background's shaders, so it only advances when this SubViewport actually
# draws, and this board deliberately does not draw while nothing is moving. Nudge
# it at BG_IDLE_HZ rather than pinning UPDATE_ALWAYS (which is what leaked the
# mobile GL driver's heap — see _update_render_activity).
func _tick_bg_idle(dt: float) -> void:
	if not _bg_idle or _vp == null:
		return
	if _vp.render_target_update_mode == SubViewport.UPDATE_ALWAYS:
		return                       # something else is already driving the redraw
	_bg_idle_accum += dt
	if _bg_idle_accum < 1.0 / BackgroundScenes.BG_IDLE_HZ:
		return
	_bg_idle_accum = 0.0
	_kick_render()

func _tick_frame_idle(dt: float) -> void:
	if not _frame_idle or _vp == null:
		return
	if _vp.render_target_update_mode == SubViewport.UPDATE_ALWAYS:
		return                       # something else is already driving the redraw
	_frame_idle_accum += dt
	if _frame_idle_accum < 1.0 / FRAME_IDLE_HZ:
		return
	_frame_idle_accum = 0.0
	_kick_render()

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

# Apply the equipped level-number font package (CoinsManager.SIMON_NUMBER_FONTS,
# whose storefront is retired). Only the typeface and the tint carry over — the
# tab keeps its own caption face, glow and outline so it still reads as interface
# whatever the player has equipped.
func _apply_num_pack() -> void:
	if _tab != null:
		_tab.apply_number_pack(_num_pack)
