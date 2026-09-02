extends RefCounted
class_name BackgroundScenes

# The LUME gameplay backgrounds: 3D scenes that live in the board's own
# SubViewport, under the buttons, seen through the same fitted gameplay camera.
#
# This class is the single façade for ALL of them. It owns the eight Themes1
# FLOORS itself (below) and forwards the two Themes2 WORLDS to world_scenes.gd,
# which is a different kind of asset — whole environments with their own authored
# animation — but the same kind of product, sold and equipped through the same
# path. No caller ever has to know which is which; see "The Themes2 worlds" below.
#
# ---------------------------------------------------------------------------
# Why these are not BackgroundManager themes
# ---------------------------------------------------------------------------
# Every existing theme is a full-screen canvas_item shader on a CanvasLayer at
# layer -1, behind all UI. These nine are geometry: a floor authored in Blender
# against the real gameplay camera, with the buttons standing ON it. Painted as a
# flat 2D layer they would lose the one thing they are for — the buttons and the
# floor sharing a perspective, a horizon and a depth buffer, so a button occludes
# the grid line behind it and its ground pool lands on the same surface.
#
# So they are built into MemoryGameUI's SubViewport as a sibling of the board (see
# `memory_game_ui.gd::_build_background`). BackgroundManager still owns the shop
# side — ownership, equipping, previews — and simply paints nothing on the 2D
# layer while one of these is equipped, because the 3D floor fills the frame.
#
# ---------------------------------------------------------------------------
# What the .glb could not carry, and where it came from instead
# ---------------------------------------------------------------------------
# The whole lighting design of these scenes is a per-vertex colour attribute named
# "Glow", wired to Emission Color on a plain Principled BSDF. glTF has no way to
# say "vertex colour drives emission" — it only multiplies COLOR_0 into BASE
# colour, and Blender's exporter only writes COLOR_0 at all when a vertex-colour
# node feeds Base Color. So the export relinks Glow -> Base Color for the duration
# of the write, which means every emissive material in the .glb reports
# baseColorFactor (1,1,1,1) and emissiveFactor (1,1,1): both placeholders.
#
# Importing that as-is gives white plastic with a vertex-coloured tint — which is
# what "just import the GLB" looks like, and is nothing like the reference.
#
# The real values are only in Themes1.blend, so they are read out of it and
# generated into `background_scenes_data.gd` (MATERIALS / LIGHTS / OBJECTS).
# Each mesh then gets a ShaderMaterial that puts everything back where Blender has
# it:
#
#     ALBEDO   = the material's real Base Color          (dark: 0.004 .. 0.075)
#     EMISSION = COLOR.rgb * Emission Strength * anim    (the Glow attribute)
#     ALPHA    = COLOR.a                                 (ribbons only)
#
# Writing EMISSION in a custom shader also side-steps the Compatibility
# renderer's emission_energy trap (it scales in sRGB, so a strength of 3 emits
# ~8x, not 3x — see the note in memory_game_ui.gd's frame handling).
#
# To regenerate the data after a Blender change:
#     python3 tools/gen_bg_data.py <lume_bg_truth.json> background_scenes_data.gd
# where the json is dumped from the live .blend (the dump script is in the same
# file's header).
#
# ---------------------------------------------------------------------------
# Animation
# ---------------------------------------------------------------------------
# The .blend deliberately holds no animation at all — no actions, no keyframes,
# no shader-time nodes, frame range 1-1. Every mesh instead carries a `lume_anim`
# custom property describing the INTENT ("trace_pulse | bright head travelling
# outward from the hub, 2.6s, staggered"), and rebuilding that in the engine is
# the importer's job.
#
# All of it is done in the shader off TIME. Nothing ticks on the CPU, no
# AnimationPlayer runs, no node transform changes per frame. The board's
# SubViewport is nudged to redraw at BG_IDLE_HZ while an animated background is
# equipped (the same mechanism an animated button frame already uses), so the
# whole cost of the animation is a low-rate redraw of a scene that was going to be
# drawn anyway.

const Data := preload("res://background_scenes_data.gd")

# ---------------------------------------------------------------------------
# Catalog
# ---------------------------------------------------------------------------
# `id` is the shop/persistence id and must never collide with an existing theme in
# CoinsManager.THEMES — which already has "deepspace", "aurora" and "neon", hence
# the "bg_" prefix on every one of these. `coll` is the Blender collection the
# data tables are keyed by.
const CATALOG := {
	"bg_neongrid":  {"name": "Neon Grid",     "coll": "BG_NeonGrid",
		"glb": "res://models/backgrounds/BG_NeonGrid.glb"},
	"bg_deepspace": {"name": "Deep Void",     "coll": "BG_DeepSpace",
		"glb": "res://models/backgrounds/BG_DeepSpace.glb"},
	"bg_circuit":   {"name": "Circuit Board", "coll": "BG_Circuit",
		"glb": "res://models/backgrounds/BG_Circuit.glb"},
	"bg_hexfloor":  {"name": "Hexagon Floor", "coll": "BG_HexFloor",
		"glb": "res://models/backgrounds/BG_HexFloor.glb"},
	"bg_darkmetal": {"name": "Dark Metal",    "coll": "BG_DarkMetal",
		"glb": "res://models/backgrounds/BG_DarkMetal.glb"},
	"bg_crystal":   {"name": "Crystal Cave",  "coll": "BG_CrystalCave",
		"glb": "res://models/backgrounds/BG_CrystalCave.glb"},
	"bg_volcanic":  {"name": "Volcanic",      "coll": "BG_Volcanic",
		"glb": "res://models/backgrounds/BG_Volcanic.glb"},
	"bg_arcade":    {"name": "Arcade Room",   "coll": "BG_ArcadeRoom",
		"glb": "res://models/backgrounds/BG_ArcadeRoom.glb"},
}

# Shop display order. Cheapest first, matching every other category's convention —
# keep this in step with the prices in CoinsManager.THEMES (100 .. 800).
const ORDER := ["bg_darkmetal", "bg_hexfloor", "bg_neongrid", "bg_circuit",
	"bg_deepspace", "bg_volcanic", "bg_crystal", "bg_arcade"]

# ---------------------------------------------------------------------------
# Exposure
# ---------------------------------------------------------------------------
# Both renderers tonemap through AgX, so the only thing between the two images is
# how much light reaches it. Blender renders these at Filmic exposure -0.30, i.e.
# a linear scale of 2^-0.30 = 0.8123. The board's Godot Environment renders at
# tonemap_exposure 0.40 — a number that is not ours to touch, because it was swept
# against the BUTTONS' own reference render and is what makes crimson and cyan land
# on their measured pixels.
#
# So the background's own radiance is pre-scaled by the ratio instead. One
# constant, applied to emission and to light energy, and the same linear value
# arrives at AgX in both engines.
const EXPOSURE_MATCH := 0.8123 / 0.40        # = 2.031

# Blender's view transform is "AgX - Punchy", which is base AgX plus a contrast and
# saturation lift; Godot only has base AgX. Punchy's effect on this material — very
# dark grounds carrying small, strongly coloured emissive marks — is almost entirely
# a saturation gain, so it is applied to the emissive term rather than left as a
# whole-image pass we would have to pay a full-screen shader for.
const PUNCHY_SATURATION := 1.18

# The visual layer the background occupies. Everything the board itself draws stays
# on layer 1, so the theme lights below can be culled to this layer alone and can
# never shift a button's colour — which would break the one thing the game is
# about. The board's own key and fill are culled the other way for the same reason
# (see memory_game_ui.gd's BOARD_LAYER): they are a specular-heavy studio rig meant
# for six small bezels, and across a 20x15 m floor they lay down a grey sheen the
# reference does not have.
const BG_LAYER := 2

# Nudge rate for the board's SubViewport while an animated background is equipped.
# Every motion here is measured in whole seconds per cycle — the fastest is the
# 2.6s circuit pulse — so 15 Hz samples the quickest of them 39 times per cycle,
# which is far past the point of being resolvable, and costs a quarter of the
# redraws a continuous animation would. Matches MemoryGameUI's FRAME_IDLE_HZ
# treatment of an animated button frame.
const BG_IDLE_HZ := 15.0

# ---------------------------------------------------------------------------
# Backdrop
# ---------------------------------------------------------------------------
# Blender's world is a vertical ramp on the view direction's Z, clamped at 0 — and
# the gameplay camera points DOWN, so every direction it can see is below the
# horizon and lands on the ramp's floor value. The world is, from this camera,
# a flat near-black.
#
# It still has to be drawn. The Blender composition was framed for a 43.4 deg lens
# where the floor fills the frame, but Medium plays on a 53.3 deg one, whose top
# edge reaches ~1.4 units further out than the floor's far edge — so on Medium
# there is a band of nothing above the floor unless something fills it. A single
# inverted box around the scene does that for one draw call, and is what the
# camera would have seen in Blender.
const BACKDROP_COLOR := Color(0.0035, 0.0042, 0.006)
const BACKDROP_SIZE := 90.0

# ---------------------------------------------------------------------------
# Seating the composition
# ---------------------------------------------------------------------------
# Every one of these was composed against ONE camera: the Blender file's, at a
# 43.6 deg lens looking down 33.5 deg, whose frame runs from y = -3.34 at the
# bottom edge to y = +6.43 at the top. Everything that STANDS in the set — arcade
# cabinets, crystal spires, aurora ribbons — is clamped against that top edge so
# nothing is ever cut by it.
#
# The game does not use that camera. It uses each board's own fitted one, aimed to
# put the BUTTONS in a particular band of the frame, and it therefore sees less
# far. Measured on 1280x720 (tools/bg_frame.gd), the top edge lands at:
#
#     Easy      y = +4.11        Moderate  y = +4.97        Hard  y = +5.15
#
# So Arcade Room's cabinet row (which reaches y = 5.73) loses its bases on all
# three, and Crystal Cave's far spires (5.46) lose their tops on Easy and Moderate.
# Not a material or lighting error — a framing one.
#
# The correction is to SEAT the background rather than drop it at the origin:
# translate it along the ground toward the camera until its furniture is back
# inside the frame. Two things bound how far, and both are measured rather than
# chosen:
#
#   * How far it NEEDS to move — Data.FURNITURE_FAR_Y, how far out the scene's
#     standing geometry actually reaches. Five of the nine have none at all: they
#     are floors, their far edge running off the top of the frame is what a floor
#     does, and seating them would only drag the horizon band into view and make
#     them WORSE. Those get nothing.
#
#   * How far it MAY move — sliding the scene forward slides its cleared middle
#     with it, so the outermost button drifts outward through the scene.
#     Data.TALL_RADIUS is where each scene's first solid standing geometry begins,
#     and the seat is clamped so the outermost button never reaches it. Hard on
#     Arcade Room gets 0.32 of the 0.58 it wants — the difference between a cabinet
#     row standing behind the buttons and one growing out of them.
#
# The buttons do not move, the camera does not move, and the fit re-runs on every
# resize, so this holds at any aspect. See MemoryGameUI._seat_background.

# A margin on top of the clearance, so a button's frame never quite touches.
const SEAT_MARGIN := 0.15

# How far this background must come forward for its own furniture to clear a frame
# whose top edge lands at Blender y `top_y`. Zero for a scene with nothing standing
# in it.
static func seat_wanted(bg_id: String, top_y: float) -> float:
	# Neither a world nor the lake is ever seated: one is a closed composition
	# fitted to this camera, the other is an unbounded surface with nothing standing
	# on it to clear. Both fall through the CATALOG test below and answer 0, and the
	# same is true of seat_allowed — this note is here so that reads as intended
	# rather than as an oversight.
	# A world is never seated. The Themes1 scenes are floors with furniture standing
	# on them, and sliding one forward only brings its own props back inside the
	# frame. A world is a CLOSED composition: its deep background lives in a narrow
	# band below the deck's far edge, placed against this camera's own occlusion ray,
	# and sliding it along the ground would drag that band out of alignment with the
	# very frame it was fitted to. See world_scenes.gd.
	if WorldScenes.has_scene(bg_id):
		return 0.0
	if not CATALOG.has(bg_id):
		return 0.0
	var far: float = Data.FURNITURE_FAR_Y.get(String(CATALOG[bg_id]["coll"]), INF)
	if far == INF:
		return 0.0
	return maxf(far - top_y, 0.0)

# HOW THE BOARD ITSELF SHOULD BE FRAMED while this background is showing, as two
# deltas on MemoryGameUI's own fit: (how much of the viewport's height the board may
# span, where its centre sits). Zero for every background but one.
#
# It is the only thing in this file that moves the BOARD rather than the scenery,
# and it exists because Ice Kingdom made a horizon (see IceWorld.HORIZON_FY). A
# board fitted to fill 0.90 of the height centred at 0.487 has its top row of
# buttons at 0.037 — above any horizon a picture could have — so the snowflakes
# stood ON the skyline with the mountains cutting across them. Nothing in the
# BACKGROUND can fix that: the buttons are 0.90 of the frame and the sky has to go
# somewhere.
#
# So the background says where it needs the board, the board decides whether it can
# oblige (see MemoryGameUI._fit_camera, which clamps), and every other background
# answers (0, 0) and is framed exactly as it was.
# How much of the TOP of the frame a background needs the buttons to stay out of,
# as a fraction of the viewport's height. Zero for every background that is only a
# picture behind the board.
#
# It is a separate hook from frame_bias, and the split is the point. `frame_bias` is
# a PREFERENCE — "I would like the board this big, about here" — expressed as two
# free numbers, and two free numbers cannot state a constraint: Ice Kingdom's asked
# for a span of 0.835 centred at 0.637, which is a board running to 1.054 of the
# height, and the fit obediently drew it forty pixels off the bottom of the screen.
# This is the CONSTRAINT half, and MemoryGameUI._fit_camera solves the preference
# inside it (see THE BAND) rather than instead of it.
#
# What each background is protecting:
#
#   Ice Kingdom  its HORIZON. The ice discards itself on a screen line and the sky
#                stands behind it; a button whose rim crosses that line is a button
#                silhouetted against mountains, which tools/ice_verify.tscn checks
#                for by name ("no button stands on the skyline").
#   Royal Casino its RAIL, the betting arc and the band every casino event is
#                played in — see CasinoEvents' note on THE LANE, which refuses to
#                run an event at all on a pose where that band does not exist.
#
# Both add a small margin on top of their own line, because what must clear it is a
# button's RIM, and the fit measures rims.
const BOARD_TOP_MARGIN := 0.022

# `base_fill` and `base_centre` are the board's OWN unbiased framing, handed in
# rather than read back: this file is the façade every background script funnels
# through and MemoryGameUI already depends on it, so reaching the other way turns
# the pair into a parse cycle and nothing in the project compiles.
static func board_top_inset(bg_id: String, base_fill: float,
		base_centre: float) -> float:
	if IceWorld.has_scene(bg_id):
		return IceWorld.HORIZON_FY + BOARD_TOP_MARGIN
	# The casino has no single line to name — its rail, arc and event lane are built
	# from the pose rather than from a screen fraction — so its constraint is read
	# back out of the preference it already wrote: the TOP EDGE its own FRAME_BIAS
	# was aiming at. That edge is the thing the bias existed to buy, and it is the
	# half of it that was never in question; only the bottom overflowed.
	var b := frame_bias(bg_id)
	if b == Vector2.ZERO:
		return 0.0
	var fill: float = clampf(base_fill + b.x, 0.55, 0.98)
	var centre: float = clampf(base_centre + b.y, 0.30, 0.80)
	return maxf(centre - fill * 0.5, 0.0)


static func frame_bias(bg_id: String) -> Vector2:
	if IceWorld.has_scene(bg_id):
		return IceWorld.FRAME_BIAS
	# Royal Casino is the second, and it asks for less. It has a table EDGE rather
	# than a horizon, and the band it needs above the top row of chips is where the
	# rail, the betting arc and every casino event are played. See
	# CasinoWorld.FRAME_BIAS, and CasinoEvents' note on THE LANE — which refuses to
	# run any event at all on a pose where that band does not exist.
	if CasinoWorld.has_scene(bg_id):
		return CasinoWorld.FRAME_BIAS
	return Vector2.ZERO


# How far it may come forward before the outermost button — `board_reach` out from
# the middle, which MemoryGameUI measures off the live board — reaches the scene's
# first standing geometry.
static func seat_allowed(bg_id: String, board_reach: float) -> float:
	if WorldScenes.has_scene(bg_id):
		return 0.0
	if not CATALOG.has(bg_id):
		return 0.0
	var tall: float = Data.TALL_RADIUS.get(String(CATALOG[bg_id]["coll"]), INF)
	if tall == INF:
		return INF
	return maxf(tall - board_reach - SEAT_MARGIN, 0.0)

# ---------------------------------------------------------------------------
# Stand-in environment
# ---------------------------------------------------------------------------
# The one thing about these scenes that Godot's Compatibility renderer genuinely
# cannot do. Blender lights them with big area panels, and an area light's defining
# property is a WIDE specular reflection: Dark Metal's floor is metallic 1.0, which
# means it has no diffuse response whatsoever and its concentric machine turning is
# visible only as the reflection of those panels. Compatibility has no area light,
# no per-object reflection probe, and a directional light's specular on that floor
# is a single narrow band. Rebuilt with lights alone the floor renders black and the
# machining — the entire identity of that background — disappears.
#
# So the panels are also folded into a small analytic environment, evaluated per
# fragment: one colour for what the surface sees looking up, modulated by how
# rough it is and tinted by its own albedo, which for a metal IS its reflectance.
# That is what an IBL would give it, minus the cost of having one.
#
# It is derived, not invented: the colour is the background's own panel lights
# summed as colour x watts, so a scene with ten times the panel power gets ten
# times the environment, and one lit by violet strips gets a violet one. Neon
# Grid's floor (albedo 0.004, 33 W of panels) lands ~35x below Dark Metal's
# (albedo 0.025, 177 W) with no per-scene tuning at all.
const ENV_GAIN := 0.0330

# How much of the environment survives at grazing normals. The ring grooves and
# plate edges are the only geometry whose normals are NOT straight up, so the
# contrast between these two is exactly what makes machining read as machining.
const ENV_FLOOR := 0.30

# ---------------------------------------------------------------------------
# The Themes2 worlds
# ---------------------------------------------------------------------------
# Six more 3D backgrounds, imported later and from a different .blend, whose assets
# carry things these nine do not: real keyframed animation, and materials whose
# values survived the glTF round trip. Building one is enough of its own job to
# live in world_scenes.gd — but it is NOT a second background system, and no caller
# should ever have to ask which kind an id is.
#
# So this class stays the single façade. `has_scene`, `build`, `is_animated`, the
# seating pair, the preview pieces and the backdrop colour all answer for both
# catalogs, and MemoryGameUI / BackgroundManager / the shop / the harnesses are
# unchanged apart from the new ids appearing in their lists.

# Every 3D background id, Themes1 floors first, in shop order. `ORDER` on its own
# stays the Themes1 ladder, because that is what its price/ordering comment and the
# existing harness defaults mean by it.
static func all_order() -> Array:
	return (ORDER as Array) + (WorldScenes.ORDER as Array) + (IceWorld.ORDER as Array) \
		+ (LakeWorld.ORDER as Array) + (CasinoWorld.ORDER as Array)

static func has_scene(id: String) -> bool:
	return CATALOG.has(id) or WorldScenes.has_scene(id) or IceWorld.has_scene(id) \
		or LakeWorld.has_scene(id) or CasinoWorld.has_scene(id)

static func display_name(id: String) -> String:
	if WorldScenes.has_scene(id):
		return WorldScenes.display_name(id)
	if IceWorld.has_scene(id):
		return IceWorld.display_name(id)
	if LakeWorld.has_scene(id):
		return LakeWorld.display_name(id)
	if CasinoWorld.has_scene(id):
		return CasinoWorld.display_name(id)
	return String(CATALOG.get(id, {}).get("name", id))

# The flat colour behind a background: what a shop card is cleared to before the
# bake lands, and what the board's viewport sits on. Each world carries its own
# (they are not all night scenes — Rainbow Sky is a daylight one).
static func backdrop_color(id: String) -> Color:
	if WorldScenes.has_scene(id):
		return WorldScenes.backdrop_color_of(id)
	if IceWorld.has_scene(id):
		return IceWorld.backdrop_color(id)
	if LakeWorld.has_scene(id):
		return LakeWorld.backdrop_color(id)
	if CasinoWorld.has_scene(id):
		return CasinoWorld.backdrop_color(id)
	return BACKDROP_COLOR

# How often the board must be nudged to redraw while this background is equipped.
# The Themes1 floors animate in their shaders at whole-second periods and are happy
# at BG_IDLE_HZ; a world plays a 30 fps clip and wants sampling at its own rate.
#
# `scene` is optional and is only read by a background that redraws at two rates:
# Ice Kingdom's milestone events need the app's own frame rate for a few seconds
# and its resting rate (15 Hz) for everything else, and the id alone cannot say
# which of those is true right now.
static func idle_hz(id: String, scene: Node3D = null) -> float:
	if LakeWorld.has_scene(id):
		return LakeWorld.IDLE_HZ
	if IceWorld.has_scene(id):
		return IceWorld.idle_hz_for(scene)
	# Same two-rate answer Ice Kingdom gives, and for the same reason: a card
	# crossing the frame in half a second at the table's resting 15 Hz is a
	# slideshow. See CasinoWorld.idle_hz_for.
	if CasinoWorld.has_scene(id):
		return CasinoWorld.idle_hz_for(scene)
	return WorldScenes.IDLE_HZ if WorldScenes.has_scene(id) else BG_IDLE_HZ

# The uniform scale that puts a background's composition back inside THIS board's
# frame. The Themes1 floors are corrected by sliding instead (seat_wanted /
# seat_allowed above) and always answer 1.0; the Themes2 worlds are closed
# compositions that cannot be slid, and are fitted by scale — see
# WorldScenes.fit_scale.
static func fit_scale(id: String, cam: Camera3D, vp_size: Vector2, board_reach: float) -> float:
	if WorldScenes.has_scene(id):
		return WorldScenes.fit_scale(id, cam, vp_size, board_reach)
	# The lake is neither slid nor scaled. It is a SURFACE that runs past the frame
	# in every direction and dissolves into its own distance haze, so there is no
	# composition to recover and nothing to fit: what adapts to the three boards is
	# where its dressing is laid, which is set_board_layout's job.
	return 1.0

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

# Instantiate a background as a Node3D ready to be added to the board's viewport.
# Returns null for an unknown id, so every caller can treat "no 3D background" and
# "a background I don't have" the same way.
static func build(id: String) -> Node3D:
	if WorldScenes.has_scene(id):
		return WorldScenes.build(id)
	if IceWorld.has_scene(id):
		return IceWorld.build(id)
	if LakeWorld.has_scene(id):
		return LakeWorld.build(id)
	if CasinoWorld.has_scene(id):
		return CasinoWorld.build(id)
	if not CATALOG.has(id):
		return null
	var def: Dictionary = CATALOG[id]
	var packed: PackedScene = load(String(def["glb"])) as PackedScene
	if packed == null:
		push_warning("BackgroundScenes: missing glb for %s" % id)
		return null

	var root := Node3D.new()
	root.name = "Background_" + id
	root.add_child(_backdrop())

	var scene := packed.instantiate() as Node3D
	root.add_child(scene)

	var coll := String(def["coll"])
	var objects: Array = Data.OBJECTS.get(coll, [])
	var env := _env_color(Data.LIGHTS.get(coll, []))
	var sweep := _sweep_period(Data.LIGHTS.get(coll, []))
	# The glTF importer brings in the two backgrounds that DO carry punctual lights
	# (CrystalCave's 7 crystal points, Volcanic's 7 vents) as Light3D nodes with
	# glTF's own photometric intensities and no cull mask. They are rebuilt from the
	# data table alongside the 33 area lights that could not be exported at all, so
	# every light in every background arrives the same way and is culled the same
	# way. Drop the imported ones rather than special-case two scenes.
	_strip_imported_lights(scene)
	_dress_meshes(scene, objects, env, sweep)
	_add_lights(root, Data.LIGHTS.get(coll, []))
	return root

# Whether anything in this background moves. Static ones (there are none today, but
# the machinery must not assume that) leave the board's redraw cadence alone.
static func is_animated(id: String) -> bool:
	if WorldScenes.has_scene(id):
		return WorldScenes.is_animated(id)
	if IceWorld.has_scene(id):
		return IceWorld.is_animated(id)
	if LakeWorld.has_scene(id):
		return LakeWorld.is_animated(id)
	if CasinoWorld.has_scene(id):
		return CasinoWorld.is_animated(id)
	if not CATALOG.has(id):
		return false
	for o: Dictionary in Data.OBJECTS.get(String(CATALOG[id]["coll"]), []):
		if _anim_kind(String(o.get("anim", ""))) != ANIM_STATIC:
			return true
	return false

# ---------------------------------------------------------------------------
# Laying something on the play surface
# ---------------------------------------------------------------------------
# The board draws the buttons' coloured ground pools on one flat sheet lying on the
# ground (MemoryGameUI.GLOW_*). "The ground" is not the same place for every
# background, and these two are how the board asks.
#
# A Themes1 FLOOR is the plane y = 0 and has no edge worth speaking of, so both
# answer 0 — "nothing to say, keep your own default". A Themes2 WORLD is an island
# whose deck stands above the origin and stops at a rim, and answers with both; see
# the block above WorldScenes.pool_plane_y for what goes wrong when it is not asked.
# A canvas theme has no 3D background at all and never reaches here.
#
# Both are in the background's own units, BEFORE fit_scale — the caller has the scale
# it applied and multiplies.

# How high this background's play surface is, or 0.0 for "use your own default".
static func pool_plane_y(id: String) -> float:
	if IceWorld.has_scene(id):
		return IceWorld.pool_plane_y(id)
	if LakeWorld.has_scene(id):
		return LakeWorld.pool_plane_y(id)
	if CasinoWorld.has_scene(id):
		return CasinoWorld.pool_plane_y(id)
	return WorldScenes.pool_plane_y(id) if WorldScenes.has_scene(id) else 0.0

# The radius past which nothing may be laid on it, or 0.0 for "no edge".
static func pool_radius(id: String) -> float:
	if IceWorld.has_scene(id):
		return IceWorld.pool_radius(id)
	if LakeWorld.has_scene(id):
		return LakeWorld.pool_radius(id)
	if CasinoWorld.has_scene(id):
		return CasinoWorld.pool_radius(id)
	return WorldScenes.pool_radius(id) if WorldScenes.has_scene(id) else 0.0

# How much of the pool this surface takes, as a multiple of MemoryGameUI.GLOW_PEAK.
#
# The third question in the same family as the two above, and asked for the same
# reason: GLOW_PEAK was fitted against a NEAR-BLACK board, where a pool is light
# appearing out of nothing. Every background before the lake was dark enough for
# that to hold. The lake is a bright turquoise surface, and the pool sheet blends
# MIX rather than ADD — so six pools overlapping in the middle of the board reach
# an alpha of 0.6 and REPLACE most of the water with a pale wash. Measured: the
# whole play area came out fogged, with the colour of the pools and none of the
# water's.
#
# It is a property of the SURFACE, not of the pools, which is why it lives here and
# not in a per-theme override on the board.
static func pool_gain(id: String) -> float:
	if IceWorld.has_scene(id):
		return IceWorld.POOL_GAIN
	if CasinoWorld.has_scene(id):
		return CasinoWorld.POOL_GAIN
	return LakeWorld.POOL_GAIN if LakeWorld.has_scene(id) else 1.0

# ---------------------------------------------------------------------------
# Telling a background about the board standing on it
# ---------------------------------------------------------------------------
# Two hooks, both no-ops for every background but the lake, and both carrying
# information the board already has rather than anything new.
#
# Nothing before the lake needed them because nothing before the lake REACTED to
# the buttons: a floor is a floor whether five discs or six are standing on it. A
# water surface is not — it has to know where the pads are to keep a ripple around
# each one, to put a contact shadow under each one, and to throw a splash from the
# one that was just pressed. See lake_world.gd's WATER_SHADER.
#
# This is deliberately the ONLY thing the board tells a background, and it is
# geometry, not state: no score, no round, no colour, no game. The lake cannot
# learn anything about the match from it.

# Where this board's buttons stand, how far the outermost one reaches, and the
# camera and viewport the whole thing is being seen through — the last two because
# a tabletop camera keystones the ground hard enough that "in the gutter" is only
# answerable on screen (see LakeWorld's placement note). Called on build, on every
# resize and on every difficulty change.
static func set_board_layout(scene: Node3D, id: String, centres: PackedVector2Array,
		reach: float, cam: Camera3D, vp_size: Vector2) -> void:
	if scene != null and IceWorld.has_scene(id):
		IceWorld.set_board_layout(scene, centres, reach, cam, vp_size)
	if scene != null and LakeWorld.has_scene(id):
		LakeWorld.set_board_layout(scene, centres, reach, cam, vp_size)
	if scene != null and CasinoWorld.has_scene(id):
		CasinoWorld.set_board_layout(scene, centres, reach, cam, vp_size)

# One button at `centre` was just pressed.
static func note_press(scene: Node3D, id: String, centre: Vector2) -> void:
	if scene != null and LakeWorld.has_scene(id):
		LakeWorld.note_press(scene, centre)
	if scene != null and CasinoWorld.has_scene(id):
		CasinoWorld.note_press(scene, centre)

# The player has just COMPLETED round `round_no`.
#
# The third hook, and the one that breaks the rule the two above set: this is match
# state, not geometry. It is here because the Magical Lake earns it — every fifth
# completed round a frog crosses the water behind the board (LakeWorld's THE FROG
# section) — and it is kept to a single integer for that reason. A background may
# know which round has just ended; it may not know the score, the colour, the
# sequence or whether the player is winning.
#
# A no-op for every background but the lake, exactly like the other two.
#
# ONE THING FLOWS BACK, and it is a duration: how many seconds the round must stay
# frozen for whatever this started, or 0.0 for nothing. It used to return nothing
# and game.gd used to ignore it, which is how the frog ended up crossing the lake
# over the top of the next round's sequence. The background still cannot reach into
# the game — it says how long it needs and the game decides what to do about it.
#
# IT IS NOW OFFERED ON EVERY COMPLETED ROUND, and that is the contract this note
# always described rather than a widening of it. game.gd used to gate the call on
# `level % 5 == 0` — the lake's number — which meant a second background could not
# want a different one without editing the game. The BACKGROUND decides now: the
# lake answers every fifth round with the frog, Ice Kingdom answers every third
# with a burst of crystals, and everything else answers 0.0 to all of them.
static func note_milestone(scene: Node3D, id: String, round_no: int) -> float:
	if scene == null:
		return 0.0
	if LakeWorld.has_scene(id):
		return LakeWorld.note_milestone(scene, round_no)
	if IceWorld.has_scene(id):
		return IceWorld.note_milestone(scene, round_no)
	if CasinoWorld.has_scene(id):
		return CasinoWorld.note_milestone(scene, round_no)
	return 0.0

# The player has just COMPLETED level `level_no`, offered so a background can mark
# a milestone the every-five-rounds one is not big enough for. Same contract and
# the same returned freeze as note_milestone; the lake answers it at level 8 with
# the five-frog party and every other background ignores it.
static func note_finale(scene: Node3D, id: String, level_no: int) -> float:
	if scene == null:
		return 0.0
	if LakeWorld.has_scene(id):
		return LakeWorld.note_finale(scene, level_no)
	if IceWorld.has_scene(id):
		return IceWorld.note_finale(scene, level_no)
	if CasinoWorld.has_scene(id):
		return CasinoWorld.note_finale(scene, level_no)
	return 0.0

# ---------------------------------------------------------------------------
# Shop preview
# ---------------------------------------------------------------------------
# A card shows one baked frame of the real 3D scene rather than a live one, and it
# is rendered through the same camera and the same tonemap gameplay uses, so what
# the player buys is what the player gets. BackgroundManager owns the caching and
# the blit (see _render_scene_plate); these two build the pieces it needs.

# The Hard board's camera pose — the one the Blender previews were composed
# against, and the widest of the three, so a card frames the scene the way its
# author did. `aspect` is the card's, and the field is horizontal (KEEP_WIDTH),
# matching MemoryGameUI.
const PREVIEW_FOV := 43.44
const PREVIEW_ELEV_DEG := 33.51
const PREVIEW_TARGET := Vector3(0.0, 0.35, 0.54)
const PREVIEW_DIST := 10.04

static func make_preview_camera(aspect: float, id: String = "") -> Camera3D:
	if WorldScenes.has_scene(id):
		return WorldScenes.make_preview_camera(aspect)
	if IceWorld.has_scene(id):
		return IceWorld.make_preview_camera(aspect)
	if LakeWorld.has_scene(id):
		return LakeWorld.make_preview_camera(aspect)
	if CasinoWorld.has_scene(id):
		return CasinoWorld.make_preview_camera(aspect)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.fov = PREVIEW_FOV
	cam.near = 0.15
	cam.far = 200.0
	var e := deg_to_rad(PREVIEW_ELEV_DEG)
	var pos := PREVIEW_TARGET + Vector3(0.0, sin(e), cos(e)) * PREVIEW_DIST
	cam.look_at_from_position(pos, PREVIEW_TARGET, Vector3.UP)
	# Unused, but a Camera3D with no viewport aspect set can frame oddly before its
	# first resize; keeping it explicit makes the bake deterministic.
	cam.set_meta("aspect", aspect)
	return cam

# In gameplay these floors are also lit by the buttons standing on them — six
# coloured pools that are a large part of what the player actually sees. A card has
# no buttons, so it is the background alone and lands about a stop darker. Dark
# Metal, whose whole subject is faint machining on near-black gunmetal, comes out
# unreadable at a 300x152 thumbnail; the rest lose contrast.
#
# So a card is exposed a little hotter than gameplay. It is the only place these
# two numbers are allowed to differ, and it is a thumbnail-legibility decision, not
# a colour one: same AgX, same materials, same lights, same camera.
const PREVIEW_EXPOSURE := 0.58

# The board's own Environment, minus the transparency. Ambient and the sky are
# irrelevant here: every background material is ambient_light_disabled and carries
# its own environment term.
static func make_preview_environment(id: String = "") -> WorldEnvironment:
	if WorldScenes.has_scene(id):
		return WorldScenes.make_preview_environment(WorldScenes.world_of(id))
	# The lake's whole palette was solved against the BOARD's Environment (see
	# LakeWorld.tone), so its card is rendered through that one and not through the
	# hotter PREVIEW_EXPOSURE below: every colour in it would land somewhere else.
	if IceWorld.has_scene(id):
		return IceWorld.make_preview_environment()
	if LakeWorld.has_scene(id):
		return LakeWorld.make_preview_environment()
	if CasinoWorld.has_scene(id):
		return CasinoWorld.make_preview_environment()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BACKDROP_COLOR.linear_to_srgb()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = PREVIEW_EXPOSURE
	env.glow_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	return we

static func _strip_imported_lights(node: Node) -> void:
	for c in node.get_children():
		if c is Light3D:
			node.remove_child(c)
			c.queue_free()
		else:
			_strip_imported_lights(c)

# An inverted box enclosing the whole scene, painted the world's floor colour.
# Unshaded and depth-write-off, so it costs one flat fill and can never occlude
# anything: it is the "there is nothing further away than this" surface.
static func _backdrop() -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = Vector3(BACKDROP_SIZE, BACKDROP_SIZE, BACKDROP_SIZE)
	var mi := MeshInstance3D.new()
	mi.name = "Backdrop"
	mi.mesh = box
	mi.layers = BG_LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Never culled away when the camera sits inside it and its centre is off-screen.
	mi.extra_cull_margin = BACKDROP_SIZE
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_FRONT            # we are inside it
	m.albedo_color = BACKDROP_COLOR.linear_to_srgb()
	m.disable_receive_shadows = true
	mi.material_override = m
	return mi

# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------

# The stand-in environment's colour for one background: its own area panels summed
# as colour x watts. Point lights are excluded — they are local accents (crystal
# cores, lava vents), not the wide soft sources this is standing in for.
static func _env_color(lights: Array) -> Vector3:
	var acc := Vector3.ZERO
	for L: Dictionary in lights:
		if String(L["type"]) != "AREA":
			continue
		var c: Color = L["color"]
		acc += Vector3(c.r, c.g, c.b) * float(L["energy"])
	return acc * ENV_GAIN * EXPOSURE_MATCH

# ---------------------------------------------------------------------------
# The light sweep
# ---------------------------------------------------------------------------
# Two backgrounds carry a `lume_anim` on a LIGHT rather than on a mesh: Dark
# Metal's "slow orbit of the specular highlight, 18s" and Arcade Room's "20s pass
# across the floor". Dark Metal in particular has no animated mesh at all — its two
# accent strips lie under the floor plane — so without this it does not move.
#
# What a sweeping panel does to a floor is move a broad bright band across it, so
# that is what this is: a wide travelling gaussian on the stand-in environment,
# running on TIME like everything else. No node rotates, nothing ticks on the CPU.
# On Dark Metal it drags a highlight across the machine turning, which is the whole
# point of machine turning.
const SWEEP_AMP := 0.45         # how much brighter the band is than the rest
const SWEEP_WIDTH := 7.0        # band half-width in metres
const SWEEP_SPAN := 15.0        # how far across the floor it travels each way
# What fraction of the visible floor the band covers on average — a gaussian of
# half-width SWEEP_WIDTH over a floor about 28 m across. Used to normalise the
# sweep so it redistributes light instead of adding it.
const SWEEP_COVERAGE := 0.45

# The sweep period for a background, or 0.0 if it has no sweeping light.
static func _sweep_period(lights: Array) -> float:
	for L: Dictionary in lights:
		if not String(L["name"]).contains("Light_Sweep"):
			continue
		# The period is written into the light's own lume_anim string, but only the
		# mesh extras survive into the data table, so it is read from the catalog of
		# animation strings the same way a mesh's is.
		return SWEEP_PERIOD.get(String(L["name"]), 18.0)
	return 0.0

# Periods as written on the lights in the .blend.
const SWEEP_PERIOD := {
	"BG_DarkMetal_Light_Sweep": 18.0,     # "slow orbit of the specular highlight, 18s"
	"BG_ArcadeRoom_Light_Sweep": 20.0,    # "20s pass across the floor"
}

static func _dress_meshes(scene: Node3D, objects: Array, env: Vector3, sweep: float) -> void:
	# The importer renames nodes (BG_Volcanic_Crust keeps its name, but meshes
	# arrive as "BG_Volcanic_Crust.002" etc.), so match on the node name the
	# exporter wrote, which is the Blender object name.
	for spec: Dictionary in objects:
		var name := String(spec["name"])
		var mi := scene.find_child(name, true, false) as MeshInstance3D
		if mi == null:
			push_warning("BackgroundScenes: no mesh node named %s" % name)
			continue
		var kind := _anim_kind(String(spec.get("anim", "")))
		var params := _anim_params(String(spec.get("anim", "")), name)
		mi.layers = BG_LAYER
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if _needs_element_phase(kind):
			_encode_element_phase(mi)
		var slots: Array = spec.get("slots", [])
		for s in slots.size():
			var mat_name := String(slots[s])
			var md: Dictionary = Data.MATERIALS.get(mat_name, {})
			if md.is_empty():
				continue
			# `crack_edge_breathe (slot 1 only)`: the basalt tops must not breathe
			# with the crack walls, or the whole crust pumps instead of the light
			# inside the cracks.
			var slot_kind := kind
			if params.get("slot", -1) >= 0 and s != int(params["slot"]):
				slot_kind = ANIM_STATIC
			mi.set_surface_override_material(s, _make_material(md, slot_kind, params, env, sweep))

static func _make_material(md: Dictionary, kind: int, params: Dictionary, env: Vector3, sweep: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	var glow: bool = bool(md.get("glow", false))
	var blend: bool = bool(md.get("blend", false))
	mat.shader = _shader(kind, glow, blend)
	var albedo: Color = md["albedo"]
	mat.set_shader_parameter("albedo", Vector3(albedo.r, albedo.g, albedo.b))
	mat.set_shader_parameter("metallic", float(md.get("metallic", 0.0)))
	mat.set_shader_parameter("roughness", float(md.get("roughness", 0.5)))
	mat.set_shader_parameter("env", env)
	mat.set_shader_parameter("sweep_period", sweep)
	if glow:
		mat.set_shader_parameter("emis", float(md.get("emis", 1.0)) * EXPOSURE_MATCH)
		mat.set_shader_parameter("sat", PUNCHY_SATURATION)
	for k in params:
		if k == "slot":
			continue
		mat.set_shader_parameter(k, params[k])
	if blend:
		# The ribbons are the only blended surfaces in the whole set and they are
		# additive light, not glass: they must not sort against each other (five
		# overlapping curtains have no correct order) and must not write depth.
		mat.render_priority = -1
	return mat

# ---------------------------------------------------------------------------
# Animation kinds
# ---------------------------------------------------------------------------
# Every `lume_anim` string in the nine backgrounds maps onto one of these. The
# string also carries its timing ("| 6s, 3s offset"), which _anim_params parses, so
# the periods and phases in the engine are the ones the artist wrote rather than
# numbers invented here.
enum {
	ANIM_STATIC,
	ANIM_BREATHE,     # emission scales on a slow sine
	ANIM_WAVE,        # a bright band travelling outward from the middle
	ANIM_BLINK,       # per-element on/off, pseudo-random
	ANIM_FLICKER,     # per-element fast noise (arcade screens, neon signs)
	ANIM_DRIFT,       # per-element translation with a wrap and a fade
	ANIM_TWINKLE,     # per-element brightness noise (stars)
	ANIM_RIBBON,      # lateral wave + alpha breathe (aurora curtains)
	ANIM_SCROLL,      # energy travelling ALONG the geometry, not outward
}

static func _anim_kind(s: String) -> int:
	if s.is_empty() or s.begins_with("static"):
		return ANIM_STATIC
	if s.begins_with("emission_scroll"):
		return ANIM_SCROLL
	if s.begins_with("trace_pulse") or s.begins_with("hex_wave") or s.begins_with("radial_pulse"):
		return ANIM_WAVE
	if s.begins_with("blink"):
		return ANIM_BLINK
	if s.begins_with("screen_flicker") or s.begins_with("neon_pulse"):
		return ANIM_FLICKER
	if s.begins_with("drift_translate"):
		return ANIM_DRIFT
	if s.begins_with("uv_parallax_drift"):
		return ANIM_TWINKLE
	if s.begins_with("wave_offset"):
		return ANIM_RIBBON
	# "emission_breathe", "emission_pulse", "crack_edge_breathe",
	# "emission_breathe follows ribbons", "emission_breathe + slow flow"
	return ANIM_BREATHE

# Kinds whose look depends on each ELEMENT (star, LED, ember, sign) having its own
# phase. Those meshes get a per-island random written into COLOR.a at build time —
# see _encode_element_phase.
static func _needs_element_phase(kind: int) -> bool:
	return kind == ANIM_BLINK or kind == ANIM_FLICKER \
		or kind == ANIM_DRIFT or kind == ANIM_TWINKLE

# Pull the timing out of the artist's own description. "| 6s, 3s offset" ->
# period 6, phase 3; "| 0.85x-1.15x, 6s" -> depth 0.15; "| 5s, 40% depth" ->
# depth 0.40. Anything not stated falls back to a value chosen for the kind.
static func _anim_params(s: String, node_name: String) -> Dictionary:
	var p := {}
	if s.is_empty():
		return p
	var kind := _anim_kind(s)
	var tail := s.substr(s.find("|") + 1) if s.contains("|") else ""

	var period := _first_seconds(tail)
	if period <= 0.0:
		period = 6.0
	p["period"] = period

	var depth := 0.18
	var pct := _find_percent(tail)
	if pct > 0.0:
		depth = pct
	var span := _find_range(tail)          # "0.85x-1.15x"
	if span > 0.0:
		depth = span
	if kind == ANIM_BREATHE and s.contains("very subtle"):
		depth = 0.08
	p["depth"] = depth

	# A second time in the string is an offset, not a period ("6s, 3s offset").
	var offset := _second_seconds(tail)
	# The five aurora ribbons are separate objects sharing one material and are
	# staggered by index — "phase = index * 2".
	if kind == ANIM_RIBBON:
		var idx := node_name.substr(node_name.length() - 2).to_int()
		offset = float(maxi(idx - 1, 0)) * 2.0
	p["phase"] = offset

	if kind == ANIM_WAVE:
		# Travelling outward from the middle of the board. 3.4 units between crests
		# puts one visible band inside the play area at a time on all three boards.
		p["wavelength"] = 3.4
	if kind == ANIM_SCROLL:
		p["wavelength"] = 5.0
	if kind == ANIM_DRIFT:
		# The direction the artist named. Everything rises except the cosmic dust,
		# which is called out as "+X 0.02 u/s, wrap".
		if s.contains("+X"):
			p["drift"] = Vector3(0.02, 0.0, 0.0)
			p["span"] = 12.0
		else:
			p["drift"] = Vector3(0.0, 0.055, 0.0)
			p["span"] = 3.2
	if s.contains("slot 1 only"):
		p["slot"] = 1
	return p

# First "<n>s" in the string, as seconds. "2-5s per sign" -> 3.5 (the midpoint of a
# stated range, which is what "2-5s per sign" means for a whole population).
static func _first_seconds(s: String) -> float:
	var re := RegEx.new()
	re.compile("([0-9]+(?:\\.[0-9]+)?)\\s*(?:-\\s*([0-9]+(?:\\.[0-9]+)?)\\s*)?s\\b")
	var m := re.search(s)
	if m == null:
		return 0.0
	var a := m.get_string(1).to_float()
	if not m.get_string(2).is_empty():
		return (a + m.get_string(2).to_float()) * 0.5
	return a

static func _second_seconds(s: String) -> float:
	var re := RegEx.new()
	re.compile("([0-9]+(?:\\.[0-9]+)?)\\s*s\\b")
	var all := re.search_all(s)
	return all[1].get_string(1).to_float() if all.size() > 1 else 0.0

# "40% depth" -> 0.40
static func _find_percent(s: String) -> float:
	var re := RegEx.new()
	re.compile("([0-9]+(?:\\.[0-9]+)?)\\s*%")
	var m := re.search(s)
	return m.get_string(1).to_float() * 0.01 if m != null else 0.0

# "0.85x-1.15x" and "0.7->1.4" -> the half-span, which is what the shader wants.
static func _find_range(s: String) -> float:
	var re := RegEx.new()
	re.compile("([0-9]+\\.[0-9]+)\\s*x?\\s*(?:-|->)\\s*([0-9]+\\.[0-9]+)")
	var m := re.search(s)
	if m == null:
		return 0.0
	var a := m.get_string(1).to_float()
	var b := m.get_string(2).to_float()
	return absf(b - a) * 0.5

# ---------------------------------------------------------------------------
# Per-element phase
# ---------------------------------------------------------------------------
# A "per-star twinkle" needs every star to be on its own clock, and all 290 of them
# are one mesh. Hashing the vertex position inside the shader would tear an element
# across its own triangles; a `flat` varying would split it at every face.
#
# So the phase is resolved at build time, where the connectivity is actually known:
# union-find the triangles into islands (one star, one LED, one ember), give each
# island a random 0..1, and write it into COLOR.a — a channel that is 1.0 on every
# one of these meshes and is only ever read as alpha by the aurora ribbons, which
# do not take this path. The shader then has an exact, tear-free per-element value
# for free.
static func _encode_element_phase(mi: MeshInstance3D) -> void:
	var src := mi.mesh
	if src == null:
		return
	var out := ArrayMesh.new()
	for s in src.get_surface_count():
		var arr := src.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		if verts.is_empty() or cols.size() != verts.size():
			out.add_surface_from_arrays(src.surface_get_primitive_type(s), arr)
			continue
		var parent := PackedInt32Array()
		parent.resize(verts.size())
		for i in verts.size():
			parent[i] = i
		# Union every pair of indices that share a triangle.
		var i := 0
		while i + 2 < idx.size():
			_union(parent, idx[i], idx[i + 1])
			_union(parent, idx[i + 1], idx[i + 2])
			i += 3
		var phase := {}
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(mi.name)
		for v in verts.size():
			var r := _find(parent, v)
			if not phase.has(r):
				phase[r] = rng.randf()
			cols[v] = Color(cols[v].r, cols[v].g, cols[v].b, float(phase[r]))
		arr[Mesh.ARRAY_COLOR] = cols
		out.add_surface_from_arrays(src.surface_get_primitive_type(s), arr)
	mi.mesh = out

static func _find(parent: PackedInt32Array, a: int) -> int:
	while parent[a] != a:
		parent[a] = parent[parent[a]]
		a = parent[a]
	return a

static func _union(parent: PackedInt32Array, a: int, b: int) -> void:
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra != rb:
		parent[rb] = ra

# ---------------------------------------------------------------------------
# Shaders
# ---------------------------------------------------------------------------
# One shader per (animation kind, has-glow, is-blended). There are nine kinds and
# almost every emissive material uses a different one, so this is a handful of
# small programs, cached across every background that asks for the same
# combination — the shop's nine preview bakes compile each at most once.
static var _shader_cache: Dictionary = {}

static func _shader(kind: int, glow: bool, blend: bool) -> Shader:
	var key := "%d/%d/%d" % [kind, int(glow), int(blend)]
	if _shader_cache.has(key):
		return _shader_cache[key]
	var sh := Shader.new()
	sh.code = _shader_code(kind, glow, blend)
	_shader_cache[key] = sh
	return sh

# The shared skeleton. `anim` is the single scalar every kind computes and the
# emission is multiplied by — which is the whole animation system: the SHAPE of
# every glow is already in the mesh, and the engine only modulates its intensity.
static func _shader_code(kind: int, glow: bool, blend: bool) -> String:
	# `ambient_light_disabled` is not a stylistic choice, it is the single thing
	# that makes these read at all. The board's Environment carries a bright
	# grey-blue ProceduralSky as its reflection source — deliberately, because the
	# button frames are METALLIC 0.9 and that sky's specular is the only thing that
	# puts a studio highlight on them. Blender's world here is the opposite: a ramp
	# that clamps to near-black everywhere this camera can see.
	#
	# Left on, every background floor (metallic 0.3-1.0, roughness 0.18-0.42) mirrors
	# that studio sky and comes out flat mid-grey, with the neon design invisible
	# underneath it. Disabling ambient AND radiance per-material restores Blender's
	# black world for the background alone and leaves the buttons' sky exactly where
	# it was.
	var modes := "cull_disabled, ambient_light_disabled"
	if blend:
		modes = "cull_disabled, blend_add, depth_draw_never, shadows_disabled, unshaded"
	var s := "shader_type spatial;\nrender_mode %s;\n\n" % modes
	s += "uniform vec3 albedo;\nuniform float metallic;\nuniform float roughness;\n"
	if not blend:
		s += "uniform vec3 env;\nuniform float sweep_period;\n"
	if glow:
		s += "uniform float emis;\nuniform float sat;\n"
	s += _uniforms(kind)
	s += _HASH_GLSL if _needs_element_phase(kind) or kind == ANIM_BLINK else ""

	# --- vertex ---
	s += "\nvarying vec3 obj_pos;\nvarying float elem;\nvarying vec3 nrm_world;\n"
	s += "void vertex() {\n"
	s += "\tobj_pos = VERTEX;\n"
	s += "\telem = COLOR.a;\n"
	# NORMAL is model space in vertex(), so one matrix gets it to world. Doing this
	# here rather than in fragment keeps it unambiguous — NORMAL is VIEW space by
	# the time fragment() sees it, and getting that backwards silently zeroes the
	# up-facing term instead of failing.
	s += "\tnrm_world = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);\n"
	s += _vertex_body(kind)
	s += "}\n"

	# --- fragment ---
	s += "\nvoid fragment() {\n"
	s += "\tALBEDO = albedo;\n\tMETALLIC = metallic;\n\tROUGHNESS = roughness;\n"
	if not blend:
		# The stand-in for the area panels' reflection (see ENV_GAIN). Written to
		# EMISSION rather than through a light because it IS a reflection, not
		# incident light: it must not be shadowed, must not fall off with distance,
		# and must be tinted by the surface's own reflectance — which for a metal is
		# its albedo, and for a dielectric is a flat few percent.
		s += "\tfloat up = clamp(nrm_world.y, 0.0, 1.0);\n"
		s += "\tvec3 refl = mix(vec3(0.045), albedo, metallic);\n"
		# The roughness term is a power, not a straight subtraction, because it is
		# doing the work of a specular lobe WIDTH: a polished ring reflects a bright
		# panel, a rougher one next to it scatters the same panel into a dimmer,
		# broader sheen. Dark Metal's machine turning alternates 0.18 and 0.36
		# roughness between neighbouring annuli, and this is what makes the two read
		# as different metal instead of one flat surface.
		s += "\tEMISSION = env * refl * mix(%.3f, 1.0, up) * pow(1.0 - roughness, 1.6);\n" % ENV_FLOOR
		# The travelling band. sweep_period 0 means this background has no sweeping
		# light, and the branch costs one compare on a uniform — the same for every
		# fragment, so it is free on any GPU worth the name.
		s += "\tif (sweep_period > 0.0) {\n"
		s += "\t\tfloat sx = sin(TIME * 6.2831853 / sweep_period) * %.2f;\n" % SWEEP_SPAN
		s += "\t\tfloat band = exp(-pow((obj_pos.x - sx) / %.2f, 2.0));\n" % SWEEP_WIDTH
		# Normalised by the band's own mean coverage, because a sweeping light MOVES
		# energy across the floor rather than adding it: the band is brighter and
		# everything outside it is correspondingly dimmer, and the frame's average
		# stays where the reference has it.
		s += "\t\tEMISSION *= (1.0 + %.3f * band) / %.4f;\n" % [SWEEP_AMP, 1.0 + SWEEP_AMP * SWEEP_COVERAGE]
		s += "\t}\n"
	if glow:
		s += "\tfloat anim = 1.0;\n"
		s += _fragment_anim(kind)
		s += "\tvec3 g = COLOR.rgb;\n"
		# The saturation lift standing in for Blender's "AgX - Punchy" look.
		s += "\tfloat lum = dot(g, vec3(0.2126, 0.7152, 0.0722));\n"
		s += "\tg = max(mix(vec3(lum), g, sat), vec3(0.0));\n"
		s += "\tEMISSION += g * emis * anim;\n"
	if blend:
		s += "\tALPHA = COLOR.a * alpha_gain;\n"
	elif kind == ANIM_DRIFT or kind == ANIM_TWINKLE:
		# These meshes' alpha channel now carries the element phase, so it must not
		# reach ALPHA. They are opaque anyway.
		s += "\tALPHA = 1.0;\n"
	s += "}\n"
	return s

const _HASH_GLSL := "
float h11(float p) {
	// sin-free hash. sin() is among the slowest ops on a mobile GPU and this runs
	// per fragment; the pattern differs from a sin-based hash, the character does not.
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}
"

static func _uniforms(kind: int) -> String:
	match kind:
		ANIM_BREATHE, ANIM_TWINKLE, ANIM_BLINK, ANIM_FLICKER:
			return "uniform float period;\nuniform float depth;\nuniform float phase;\n"
		ANIM_WAVE, ANIM_SCROLL:
			return "uniform float period;\nuniform float depth;\nuniform float phase;\nuniform float wavelength;\n"
		ANIM_DRIFT:
			return "uniform float period;\nuniform float depth;\nuniform float phase;\nuniform vec3 drift;\nuniform float span;\n"
		ANIM_RIBBON:
			return "uniform float period;\nuniform float depth;\nuniform float phase;\nuniform float alpha_gain = 1.0;\n"
		_:
			return "uniform float alpha_gain = 1.0;\n"

static func _vertex_body(kind: int) -> String:
	match kind:
		ANIM_DRIFT:
			# Each element rises (or drifts) on its own offset within the span and
			# wraps, so the field never empties and never marches in step.
			return "\tfloat t = TIME * length(drift) + elem * span;\n" + \
				"\tfloat travel = mod(t, span);\n" + \
				"\tVERTEX += normalize(drift) * travel;\n"
		ANIM_RIBBON:
			# The curtain's lateral wave. Amplitude grows with height so the base
			# stays anchored on the ground and the top swims, which is how a real
			# aurora reads.
			return "\tfloat w = TIME * 6.2831853 / period + phase;\n" + \
				"\tVERTEX.x += sin(w + VERTEX.y * 0.55) * 0.42 * clamp(VERTEX.y * 0.5, 0.0, 1.0);\n"
		_:
			return ""

static func _fragment_anim(kind: int) -> String:
	match kind:
		ANIM_BREATHE:
			return "\tanim = 1.0 + depth * sin((TIME + phase) * 6.2831853 / period);\n"
		ANIM_WAVE:
			# A bright head travelling outward from the middle of the board. The
			# trough never goes below 1.0 - depth, so nothing ever goes dark and the
			# static design underneath is always readable.
			return "\tfloat r = length(obj_pos.xz);\n" + \
				"\tfloat w = r / wavelength - (TIME + phase) / period;\n" + \
				"\tanim = 1.0 + depth * 1.2 * pow(max(sin(w * 6.2831853) * 0.5 + 0.5, 0.0), 9.0);\n"
		ANIM_SCROLL:
			# Energy travelling ALONG the grid rather than outward from a hub: the
			# phase runs on the sum of the two axes, so it slides down the lines.
			return "\tfloat w = (obj_pos.x + obj_pos.z) / wavelength - (TIME + phase) / period;\n" + \
				"\tanim = 1.0 + depth * 1.2 * pow(max(sin(w * 6.2831853) * 0.5 + 0.5, 0.0), 6.0);\n"
		ANIM_BLINK:
			# Each element holds for its own share of the period, then blinks. The
			# blink is a fast rise and a slower fall, which is what an LED looks like.
			return "\tfloat cyc = (TIME + elem * period) / period;\n" + \
				"\tfloat f = fract(cyc);\n" + \
				"\tfloat gate = step(0.55, h11(floor(cyc) + elem * 71.3));\n" + \
				"\tanim = 1.0 - depth * gate * smoothstep(0.0, 0.06, f) * smoothstep(0.42, 0.10, f);\n"
		ANIM_FLICKER:
			# A screen or a sign: mostly steady, with a shallow wobble and the
			# occasional short dropout the artist asked for.
			return "\tfloat t = TIME / period + elem * 13.7;\n" + \
				"\tfloat n = h11(floor(t * 4.0) + elem * 37.1);\n" + \
				"\tfloat wob = 1.0 + depth * (n - 0.5);\n" + \
				"\tfloat drop = step(0.965, h11(floor(t * 9.0) + elem * 91.7));\n" + \
				"\tanim = wob * (1.0 - 0.55 * drop);\n"
		ANIM_TWINKLE:
			return "\tfloat t = TIME / period + elem * 29.3;\n" + \
				"\tanim = 1.0 + depth * 1.6 * sin(t * 6.2831853) * (0.4 + 0.6 * h11(elem * 53.7));\n"
		ANIM_DRIFT:
			# Fade in off the floor and out at the top of the span, so a wrapping
			# element never pops.
			return "\tfloat t = TIME * length(drift) + elem * span;\n" + \
				"\tfloat u = mod(t, span) / span;\n" + \
				"\tanim = smoothstep(0.0, 0.18, u) * smoothstep(1.0, 0.72, u);\n"
		ANIM_RIBBON:
			return "\tanim = 1.0 + depth * sin((TIME + phase) * 6.2831853 / period);\n"
		_:
			return ""

# ---------------------------------------------------------------------------
# Lights
# ---------------------------------------------------------------------------
# 33 of the 47 theme lights are Blender AREA lights and Godot has none, so each is
# rebuilt as whichever Godot light actually reproduces what that panel DOES. The
# two cases behave completely differently and using one type for both is what makes
# an import of this kind look wrong:
#
#   Big soft panel (area >= _DIR_AREA) -> DirectionalLight3D along the panel's own
#     -Z. What these contribute is a broad, even specular sweep across a whole
#     floor — Dark Metal's concentric machine turning is only visible BECAUSE a
#     7x1.4 m panel lays a wide highlight over it, and its floor is metallic 1.0,
#     so specular is the only channel it has at all. A point light gives that
#     surface one small dot and the machining disappears.
#
#   Accent strip (everything else) -> a short string of omnis along its long axis.
#     These are the coloured neon washes at the sides. They ARE local, they do fall
#     off, and their whole job is to tint one region — but a single omni in the
#     middle of a 6 m strip reads as a hotspot, so the power is spread along the
#     strip's own length instead.
#
# Every one is culled to BG_LAYER so it lights the floor and never the buttons.
# In Blender one rig lights the whole set, but the buttons' Godot palette was
# measured against their own reference and a 15 W violet panel washing across them
# would move colours the game asks the player to tell apart.
const _LIGHT_ENERGY := 0.025      # omni light_energy per Blender watt
const _DIR_ENERGY := 0.0060       # directional light_energy per Blender watt
const _DIR_AREA := 9.0            # m^2 above which a panel is rebuilt as directional
const _LIGHT_RANGE := 26.0
const _LIGHT_ATTEN := 1.35        # softens Godot's linear falloff towards inverse-square
const _MAX_SPLIT := 3

static func _add_lights(root: Node3D, lights: Array) -> void:
	for L: Dictionary in lights:
		_add_light(root, L)

static func _add_light(root: Node3D, L: Dictionary) -> void:
	var col: Color = L["color"]
	var origin: Vector3 = L["origin"]
	var basis: Basis = L["basis"]
	var watts := float(L["energy"])

	if String(L["type"]) != "AREA":
		_omni(root, String(L["name"]), origin, col,
			watts * _LIGHT_ENERGY * EXPOSURE_MATCH, float(L.get("radius", 0.0)))
		return

	var sx := float(L["size"])
	var sy := float(L.get("size_y", 0.0))
	if sx * sy >= _DIR_AREA:
		_directional(root, String(L["name"]), basis, col, watts * _DIR_ENERGY * EXPOSURE_MATCH)
		return

	# How many omnis, and how far apart. One per ~3.5 units of the panel's longer
	# side, capped: past three the extra lights stop changing the image and start
	# costing draw time on a mobile GL device.
	var long_axis: Vector3 = basis.x if sx >= sy else basis.y
	var length := maxf(sx, sy)
	var n := clampi(int(round(length / 3.5)), 1, _MAX_SPLIT)
	var energy := watts * _LIGHT_ENERGY * EXPOSURE_MATCH
	for i in n:
		var t := 0.0 if n == 1 else (float(i) / float(n - 1) - 0.5)
		var p := origin + long_axis.normalized() * (t * length * 0.5)
		_omni(root, "%s_%d" % [String(L["name"]), i], p, col, energy / float(n), 0.0)

static func _directional(root: Node3D, name: String, basis: Basis, col: Color, energy: float) -> void:
	var d := DirectionalLight3D.new()
	d.name = name
	# A Blender area light emits along its own -Z, and so does a Godot directional,
	# so the panel's orientation carries across untouched. Position is dropped,
	# which is the whole point: a directional has none.
	d.basis = basis
	d.light_color = col.linear_to_srgb()
	d.light_energy = energy
	d.light_cull_mask = BG_LAYER
	d.shadow_enabled = false
	root.add_child(d)

static func _omni(root: Node3D, name: String, pos: Vector3, col: Color, energy: float, radius: float) -> void:
	var o := OmniLight3D.new()
	o.name = name
	o.position = pos
	o.light_color = col.linear_to_srgb()
	o.light_energy = energy
	o.omni_range = _LIGHT_RANGE
	o.omni_attenuation = _LIGHT_ATTEN
	o.light_cull_mask = BG_LAYER
	# No shadow anywhere in the set. Nothing in these scenes casts one in the
	# reference either — the floors are lit by their own emission, and a shadow map
	# per light would be 47 of them across the catalog on a mobile GL driver.
	o.shadow_enabled = false
	if radius > 0.0:
		o.light_size = radius
	root.add_child(o)
