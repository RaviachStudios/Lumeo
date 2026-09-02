extends RefCounted
class_name WorldScenes

# The two LUME WORLDS from Themes2.blend: full cinematic environments — a floating
# island arena, a mid-ground, a deep abyss and a living particle layer — that the
# gameplay buttons stand in the middle of.
#
# Four more (Rainbow Sky, Inferno Abyss, Crystal Cavern, Galaxy Realm) were built
# from the same .blend and then cut before release. Nothing here is per-world
# special-cased, so re-adding one is a CATALOG entry, an ORDER slot, a
# CoinsManager.THEMES row, a shop CATEGORIES slot, the .glb and a regenerated
# world_scenes_data.gd (see tools/gen_world_data.py's ORDER).
#
# ---------------------------------------------------------------------------
# One background system, two kinds of asset
# ---------------------------------------------------------------------------
# These are NOT a second background system. They are ordinary entries in the
# existing 3D-background catalog: BackgroundScenes is the single façade every
# caller already uses (has_scene / build / is_animated / seat_* / display_name /
# make_preview_*), and it forwards a world id here. Ownership, price, purchase,
# equip and persistence are CoinsManager.THEMES and `selected_theme`, exactly as
# for the eight Themes1 floors and the shader themes before them.
#
# What differs from Themes1 is only what the asset can carry:
#
#   Themes1  no animation at all in the .blend; every mesh carried a `lume_anim`
#            STRING describing intent, and background_scenes.gd rebuilt each one as
#            a shader running on TIME.
#   Themes2  300 frames of real object TRS keyframes per world, exported into the
#            .glb. They are played by the GLB's own AnimationPlayer, unmodified.
#            Nothing here re-authors motion.
#
# ---------------------------------------------------------------------------
# What the .glb could not carry
# ---------------------------------------------------------------------------
# Two things, both restored from world_scenes_data.gd (generated straight out of
# the .blend — see tools/gen_world_data.py):
#
# 1. VERTEX COLOUR DRIVES EMISSION. Every material in these worlds is
#    MULTIPLY(a flat colour, the "Col" vertex attribute) on Base Color, and — on
#    every glowing surface — on Emission Color as well. glTF's COLOR_0 only
#    multiplies BASE colour, so the exporter wrote each emissive factor as a flat
#    constant. Imported as-is, every sky, nebula, mist card, light shaft and glow
#    halo renders as one uniform slab of colour instead of the graded shape the
#    artist painted into it. `vc_emis` puts the multiply back.
#
# 2. THE AREA LIGHTS. glTF has point / spot / directional and nothing else, so the
#    big soft panels that shape all six renders exported as empty nodes. So did the
#    six shared LUME presentation panels, which each theme re-tints and re-scales
#    (activate_theme) and which contribute roughly a third of the light on the
#    deck. Both are rebuilt from the data table.
#
# The .glb IS trusted for everything it can carry: geometry, the COLOR_0 attribute
# itself, node names, transforms and all 300 frames of animation. Nothing is
# remodelled here.
#
# ---------------------------------------------------------------------------
# Where they live
# ---------------------------------------------------------------------------
# Inside MemoryGameUI's SubViewport, as a sibling of the board, on visual layer
# BackgroundScenes.BG_LAYER — the same seat the Themes1 floors take, for the same
# reason: the buttons and the world have to share one camera, one depth buffer and
# one tonemap, or a button cannot occlude what is behind it and its ground pool
# cannot land on the deck. Every light built here is culled to that layer, so no
# world can shift a button's colour.

# ---------------------------------------------------------------------------
# Where the match landed
# ---------------------------------------------------------------------------
# Measured with tools/world_tune.gd: each world rendered at the reference's own
# 1920x1080 through the reference camera and compared against renders/lume_*.png,
# on a 8x5 grid with the cells the buttons occupy excluded. Mean sRGB, Godot over
# Blender, at the constants below:
#
#     Living Forest   1.19 / 1.37 / 0.75
#     Ice Kingdom     1.16 / 1.07 / 1.26
#
# The constants themselves were fitted against all SIX worlds that existed then
# (geometric mean 0.94 / 1.02 / 1.06); four have since been cut and are not coming
# back, so the two rows above are the whole record now. Forest moved by ~0.05 when
# its mushrooms were rebuilt — a taller, rounder glowing prop puts more cyan in
# frame — and its reference render was re-made from the same .blend, so the pair is
# still measuring the same scene.
#
# What is left is per-world HUE, not level, and no global constant can move it: it
# is the residue of a tonemapper whose saturation behaviour differs from Blender's
# (see AGX_FIT — the curve is matched, the desaturation is not) and of the panel
# specular that is not rebuilt at all (see _omni).

const Data := preload("res://world_scenes_data.gd")

# The visual layer a background occupies — the same number BackgroundScenes.BG_LAYER
# names, and the reason no light built here can ever touch a button. It is declared
# again rather than imported so the dependency between the two modules stays
# strictly one-way (BackgroundScenes -> WorldScenes) and GDScript never has to
# resolve a cycle between two `class_name` scripts. tools/world_verify.gd asserts
# the two agree.
const BG_LAYER := 2

# ---------------------------------------------------------------------------
# Catalog
# ---------------------------------------------------------------------------
# `id` is the shop/persistence id. The "world_" prefix keeps them clear of both the
# shader themes ("inferno", "rainbow", "deepspace" are all taken) and the Themes1
# floors ("bg_crystal" is Crystal Cave). These ids are what saved wallets contain,
# so they are frozen once shipped.
#
# `world` is the key the data tables are cut by, and the name the .blend uses.
# `world_ice` USED TO BE HERE, and is not any more. Ice Kingdom is still a shipping
# background under the same id, still sold on the same shelf, and still brings the
# same snowflake buttons — but the ground under it is now generated in Godot
# (ice_world.gd) instead of imported from Themes2.blend. Why: the imported world was
# a closed composition with columns of bright blue crystal down both sides of the
# frame, white crack lines running under the buttons, and a vignette that put the
# darkest part of the picture where the six snowflakes are, and it took more of the
# frame's contrast than the thing the player has to read.
#
# LUME_World_Ice.glb is still on disk, still imported, and world_scenes_data.gd
# still carries its full table — this file could build it again by restoring the
# three lines below, and the reference render is still Themes2/renders/lume_ice.png.
# Nothing else was removed, and Ice's rows in the data tables are what a second
# world proves the generated ones against.
#
#	"world_ice":     {"name": "Ice Kingdom",    "world": "Ice",
#		"glb": "res://models/worlds/LUME_World_Ice.glb"},
const CATALOG := {
	"world_forest":  {"name": "Living Forest",  "world": "Forest",
		"glb": "res://models/worlds/LUME_World_Forest.glb"},
}

# Shop display order. It is NOT a price ladder like the Themes1 floors' (these are
# free); it runs from the world with the least happening in frame to the most, which
# is the order a player reads them in as "more". Keep in step with
# CoinsManager.THEMES and the shop's CATEGORIES["items"].
#
# One entry, since Ice Kingdom moved to ice_world.gd. BackgroundScenes.all_order()
# concatenates this with the generated backgrounds' own ORDERs, so the shelves are
# unchanged by where a background is built.
const ORDER := ["world_forest"]

# ---------------------------------------------------------------------------
# Exposure
# ---------------------------------------------------------------------------
# Both engines tonemap through AgX, so the only thing between the two images is how
# much light reaches it. Blender renders each world at its own view-transform
# exposure (Data.EXPOSURE: -0.20 for both of these), i.e. a linear scale of
# 2^exposure. The board's Godot Environment renders at
# tonemap_exposure 0.40, a number that is not ours to touch — it was swept against
# the BUTTONS' own reference render and is what puts crimson and cyan on their
# measured pixels.
#
# So each world's own radiance is pre-scaled by the ratio instead, and the same
# linear value arrives at AgX in both engines.
const BOARD_TONEMAP_EXPOSURE := 0.40

# Blender's own linear scale for this world: 2^(view exposure). Everything the
# shader is handed — albedo, emission, light irradiance — is in this DISPLAY-REFERRED
# domain, because that is the domain `agx_match` is defined in. Converting into the
# board's exposure is the last thing that happens, after the match.
static func blender_exposure(world: String) -> float:
	return pow(2.0, float(Data.EXPOSURE.get(world, -0.20)))

# ---------------------------------------------------------------------------
# Godot's AgX is not Blender's AgX
# ---------------------------------------------------------------------------
# This is the single biggest thing between the two images, and it is not a small
# difference. Measured (tools/agx_probe.gd renders the same ramp of linear values
# through both transforms and prints them side by side):
#
#     linear      Blender AgX - Punchy      Godot TONE_MAPPER_AGX
#      0.02              10                          0
#      0.08              52                          9
#      0.18              88                         38
#      0.50             144                        128
#      1.00             176                        203
#      2.00             203                        243
#      4.00             222                        255  (clipped)
#     24.00             255                        255
#
# Godot's curve has perhaps a third of the latitude: it crushes everything under
# ~0.06 to black and clips to white from ~3.5 up, where Blender's still resolves
# 0.01 and is still climbing at 24. On this material that is not subtle — it is why
# an untreated import renders the rainbow, the cloud bank and every crystal core as
# flat white shapes, and the deck's shadow side as black.
#
# The board's Environment cannot be re-tonemapped to fix it: its AgX at
# tonemap_exposure 0.40 was swept against the BUTTONS' own reference render and is
# what puts crimson and cyan on their measured pixels, and it is shared with the
# twenty existing themes.
#
# So the background PRE-COMPENSATES instead. For a Blender display-referred value u,
# `agx_match` returns the value u' that Godot's AgX turns into the same picture:
#
#     GodotAgX(u' * 0.40) == BlenderAgX(u)
#
# It is a cubic through log2(u), least-squares fitted to 64 measured points spanning
# u = 0.012 .. 26 and accurate to 4.5 % (well under one display count over almost all
# of it). Below the fit range Blender's own 8-bit reference floors out, so the
# curve's smooth extrapolation is better behaved than the measurement; above it
# everything is clipped white in both engines anyway.
#
# It is applied to the EMISSIVE term only. That is where all the blow-outs are —
# these worlds are lit as much by their own emission as by their lamps — and it is
# the only term a spatial shader can reach, because Godot adds the light
# contribution after fragment() returns and there is no hook that sees the sum. What
# the lit term needs instead is a level shift, which is what LIGHT_SCALE is.
const AGX_FIT := Vector4(-0.404809, 0.393487, -0.008515, 0.003836)
# The log2 range the fit is trusted over; outside it the cubic is clamped rather
# than extrapolated, because a cubic leaving its data does so quickly.
const AGX_LOG_MIN := -9.0
const AGX_LOG_MAX := 5.2

# Blender's "Punchy" look is a contrast AND a saturation lift. The contrast half is
# inside the measured curve above (the ramp was rendered through AgX - Punchy); the
# saturation half a neutral ramp cannot see, so it stays a separate gain, applied
# before the match. Same value the Themes1 floors use, for the same transform.
const PUNCHY_SATURATION := 1.18

# ---------------------------------------------------------------------------
# Ambient
# ---------------------------------------------------------------------------
# EEVEE lights these scenes with the world background as well as with the lamps,
# and every material here is `ambient_light_disabled` (it has to be — the board's
# Environment carries a bright ProceduralSky as its reflection source for the
# metallic button bezels, and without that flag every deck mirrors it and comes out
# flat mid-grey). So the world's own contribution is put back as one analytic term:
# a flat irradiance on the surface's own albedo, weighted by how much sky the
# normal can see.
#
# The colour is the .blend's own world ramp (a vertical gradient, 0.6 strength)
# averaged over the hemisphere; the gain is swept against the six reference renders
# (tools/world_compare.gd).
const AMBIENT_COLOR := Vector3(0.090, 0.190, 0.360)
# Swept, with LIGHT_SCALE, against all six reference renders (tools/world_tune.gd).
# Kept as static vars rather than consts ONLY so that sweep can move them in one
# process; nothing at runtime writes them.
static var AMBIENT_GAIN := 0.60
# How much of it survives at a downward-facing normal — an underside sees the abyss,
# not the sky, but not nothing either.
const AMBIENT_FLOOR := 0.25

# ---------------------------------------------------------------------------
# Lights
# ---------------------------------------------------------------------------
# Every light is rebuilt rather than imported, so all of them arrive the same way
# and are culled the same way. The two glTF-native kinds (the vent/crystal points,
# the three suns) come in with photometric intensities in the thousands and no cull
# mask; the panels do not come in at all.
#
# The conversion is physical rather than fitted, so a 340 W sheen 10 m out and a
# 14 W mushroom light 4 m out both land without a per-world number:
#
#   Blender AREA   a Lambertian emitter of power P has on-axis intensity P/PI, so
#                  the irradiance it lays on the middle of the scene is P/(PI*d^2).
#   Blender POINT  isotropic: intensity P/(4*PI), irradiance P/(4*PI*d^2).
#   Blender SUN    `energy` IS the irradiance, in W/m^2.
#
# Godot's Lambert diffuse is `albedo * NdotL * energy` where Blender's is
# `albedo/PI * E * NdotL` — hence the extra division by PI on every one of them.
# LIGHT_SCALE is measured rather than derived: 1.8, swept against all six reference
# renders together with TONE_IRRADIANCE (tools/world_tune.gd). Most of what it
# absorbs is nameable — every rebuilt light has its specular turned off (see _omni),
# and in the reference the panels' specular is a real part of the image, a wide
# low-roughness sheen across the deck and the rim. Rolling that into the diffuse
# term is why the physical derivation lands low.

#
# The omnis are set to a true inverse-square falloff (`omni_attenuation = 2.0`),
# which is what Blender does, so `light_energy` is the light's INTENSITY and the
# conversion needs no reference distance to be normalised at. Godot's own falloff is
#
#     att(d) = (1 - (d/range)^4)^2 * d^-decay
#
# — a smooth window on an inverse power, NOT the (1 - d/range)^decay it looks like
# from the inspector — so the range only has to be far enough out that the window
# is still ~1 across the whole scene.
static var LIGHT_SCALE := 1.8
const _INV_PI := 1.0 / PI

# A panel this big is a SHEET of light, not a lamp: what it does to the scene is a
# broad even wash with a wide specular, which is a directional light's behaviour and
# not an omni's. Below it, the panel is a local accent strip that really does fall
# off, and is rebuilt as a short string of omnis along its own long axis so a 13 m
# strip does not read as one hotspot in the middle.
const _DIR_AREA := 3.0            # m^2
const _MAX_SPLIT := 3
# Far enough out that Godot's range window stays ~1 across the whole island: at
# 20 m it is still 0.995, so the falloff the scene sees is pure inverse square.
const _LIGHT_RANGE := 90.0

# The board's SubViewport is nudged at this rate while a world is equipped, which is
# what advances the animation (the viewport deliberately does not redraw while
# nothing moves — see MemoryGameUI._update_render_activity). The clips are authored
# at 30 fps and a good deal of what moves in them is stepped rather than smooth
# (sparkle pops, wing flaps), so sampling at exactly the authored rate reproduces
# them and anything slower beats against them.
const IDLE_HZ := 30.0

# ---------------------------------------------------------------------------
# Backdrop
# ---------------------------------------------------------------------------
# Each world closes itself off with its own painted sky card (ICE_Sky,
# FOREST_Sky) sized to fill the reference frame. The gameplay boards do not
# use the reference lens, so at a wider one the card can stop short — and behind it
# is the clear colour of a transparent SubViewport, i.e. the 2D theme layer, which
# would show as a bright band across the top of a night scene.
#
# One inverted box around everything, painted the deepest tone of that world's own
# sky, is what the camera would have seen in Blender and costs one flat fill.
const BACKDROP_SIZE := 320.0
const BACKDROP := {
	"Ice":     Color(0.0090, 0.0180, 0.0420),
	"Forest":  Color(0.0080, 0.0160, 0.0130),
}

static func has_scene(id: String) -> bool:
	return CATALOG.has(id)

static func display_name(id: String) -> String:
	return String(CATALOG.get(id, {}).get("name", id))

static func world_of(id: String) -> String:
	return String(CATALOG.get(id, {}).get("world", ""))

# The flat colour behind this world, already exposure-matched — see _backdrop.
static func backdrop_color_of(id: String) -> Color:
	return _backdrop_color(world_of(id))

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

# Instantiate a world as a Node3D ready to be added to the board's viewport, with
# its animation already running. Returns null for an unknown id, so a caller can
# treat "not a world" and "a world I don't have" the same way.
static func build(id: String) -> Node3D:
	if not CATALOG.has(id):
		return null
	var def: Dictionary = CATALOG[id]
	var packed: PackedScene = load(String(def["glb"])) as PackedScene
	if packed == null:
		push_warning("WorldScenes: missing glb for %s" % id)
		return null
	var world := String(def["world"])

	var root := Node3D.new()
	root.name = "World_" + id
	root.add_child(_backdrop(world))

	var scene := packed.instantiate() as Node3D
	root.add_child(scene)

	_strip_imported_lights(scene)
	_dress_meshes(scene, world)
	_add_lights(root, world)
	if STILL.has(id):
		_freeze_animation(scene)
	else:
		_start_animation(scene)
	return root

# Worlds that are deliberately NOT played. The .glb is untouched — it still carries
# all 300 frames — but for an id listed here the AnimationPlayer is dropped at build
# time, so every node keeps the rest pose the .blend keyed at frame 1 and nothing
# writes a transform again.
#
# It is EMPTY now that Ice Kingdom is built in Godot rather than imported (the
# generated one animates its own snow), and it is kept because it is the mechanism
# rather than the case: dropping the player rather than pausing it is what makes the
# whole path inert for a world that ships still. `is_animated` below goes false, so
# the board stops nudging a redraw at IDLE_HZ for it and `set_playing` finds nothing
# to resume, and neither has to know about this table.
const STILL := {}

# Whether this world's clip runs. Kept as a function rather than a constant so the
# caller does not have to know about STILL.
static func is_animated(id: String) -> bool:
	return not STILL.has(id)

# ---------------------------------------------------------------------------
# Fitting the composition to a board's camera
# ---------------------------------------------------------------------------
# All six were composed against ONE camera — LUME_Gameplay_Camera, at a 43.60 deg
# lens on a 16:9 frame — and the composition is CLOSED around it. The island fills
# the bottom of the frame; the deep background (mountains, castle, portal, volcano
# range, rainbow) lives entirely in the band between the top of the island's
# silhouette and the top of the frame, because the camera pitches 33.5 deg down and
# never sees the horizon. That band is 13.5 % of the reference frame.
#
# The game does not use that camera. Each board fits its own to put its BUTTONS in a
# particular part of the frame, and all three sit lower and see less far:
#
#     reference  z 5.85, 43.60 deg      Hard  z 5.38, 43.44 deg
#     Moderate   z 3.60, 53.32 deg      Easy  z 3.83, 44.00 deg
#
# Dropped in at its authored scale, the island's rim then runs off the top of every
# board and the entire band goes with it — the world reduces to a deck.
#
# Neither the camera nor the buttons may move, so the WORLD is fitted instead: one
# uniform scale about the origin, solved so that the island's highest silhouette
# point lands back on the v the reference put it at. Scaling about the origin leaves
# the deck's top plane at y = 0 exactly where it was, so the buttons stay standing on
# it and nothing about the board changes.
#
# Two things bound it, and both are measured rather than chosen:
#   * it never grows a world (a board that already sees far enough gets the authored
#     scale), and
#   * it may never shrink the deck to where the outermost button overhangs its edge —
#     Data.DECK[...].radius against the reach MemoryGameUI measures off the live board.
# The fit re-runs on every resize, so it holds at any aspect on any device.

# The narrowest lip the composition is ever authored to have between the outermost
# button and the edge of the deck, and therefore the floor on how far a world may be
# shrunk. It is not a chosen number: it is the lip the HARD board has at the
# authored scale — deck radius 4.21 against a reach of 3.47 — which is the tightest
# of the three, because Hard's six buttons are pushed out by MemoryGameUI's
# SPACING_SCALE and sit 15 % wider than the Ref_LUME_Buttons_Hard rig the deck was
# sized around.
#
# So Hard is pinned at the authored scale (it has no room, and taking any would
# start growing the rim's crystals and roots into the button ring — measured, at
# 0.90 they reach the Violet and Cyan frames), and Moderate and Easy, whose boards
# are narrower, may shrink until they are as tight as Hard is.
const DECK_MARGIN := 0.74

# ---------------------------------------------------------------------------
# Where the play surface actually is
# ---------------------------------------------------------------------------
# A Themes1 floor IS the plane y = 0, so anything the board wants to lay on the
# ground it can lay at y = 0 and be done. A world is not: it is an ISLAND, its deck
# stands 55 .. 71 mm above the origin (Data.DECK[...]["top"]) and it ENDS — past
# `far` there is a rim wall and then a kilometre of abyss.
#
# Both facts bite the board's ground pools (MemoryGameUI.GLOW_*), the coloured light
# each button throws on the table. That is one flat unshaded sheet 12 mm up, which is
# exactly right on a floor and wrong twice on a world: the sheet is BURIED under the
# deck for its whole width, so no button lays any light on the ground at all, and the
# only place it surfaces is past the island edge, where it hangs over the void and the
# camera's shallow angle compresses the whole remainder of it into a bright band along
# the far rim. The symptom is a flash that misses the surface it is standing on and
# washes the scenery behind it instead.
#
# So a world answers two questions no floor has to: how high its surface is, and where
# it stops. Both are in world units and both are scaled by fit_scale at the callsite,
# because the board scales the whole scene about the origin.

# Clearance between the deck's own top and anything laid on it. Larger than the
# floors' 12 mm because a deck carries dressing that a floor does not — Forest's moss
# and Ice's surface cracks lie up to 8 mm proud of the platform itself, and a pool
# that passes UNDER them reads as a hole punched in the light.
const POOL_DECK_BIAS := 0.022

# How high to lay something on this world's play surface, before fit_scale. 0.0 for
# anything that is not a world, which is the caller's signal to keep its own default.
static func pool_plane_y(id: String) -> float:
	if not CATALOG.has(id):
		return 0.0
	return float(Data.DECK[world_of(id)]["top"]) + POOL_DECK_BIAS

# The radius past which nothing may be laid on this world, before fit_scale. The
# deck's TIGHTEST boundary, which is `far` — the tapered edge away from the camera,
# and the one the pools actually spill over. Being a little conservative on the near
# and side edges (which reach `radius`, ~0.46 further) costs nothing: the pool's own
# GLOW_R_CUT has already thinned it to almost nothing by then.
static func pool_radius(id: String) -> float:
	if not CATALOG.has(id):
		return 0.0
	var deck: Dictionary = Data.DECK[world_of(id)]
	return minf(float(deck["far"]), float(deck["radius"]))

# Solve the uniform scale for `id` under `cam` in a `vp_size` viewport, with the
# outermost button `board_reach` out from the middle.
static func fit_scale(id: String, cam: Camera3D, vp_size: Vector2, board_reach: float) -> float:
	var world := world_of(id)
	var deck: Dictionary = Data.DECK.get(world, {})
	if deck.is_empty() or cam == null or vp_size.y < 8.0:
		return 1.0
	var floor_s := 0.0
	var radius := float(deck["radius"])
	if radius > 0.0:
		floor_s = clampf((board_reach + DECK_MARGIN) / radius, 0.05, 1.0)
	var target := float(deck["skyline_v"]) * vp_size.y
	var p: Vector3 = deck["skyline"]
	if _skyline_v(cam, p, 1.0) >= target:
		# The board already frames the island at or below the reference silhouette:
		# it sees at least as far, so there is nothing to correct.
		return 1.0
	# v is monotonic in s over this range (the point only moves down the frame as the
	# world shrinks toward the camera's aim), so a plain bisection converges to well
	# under a pixel in a dozen steps and costs a dozen unprojects on a resize.
	var lo := floor_s
	var hi := 1.0
	for _i in 14:
		var mid := (lo + hi) * 0.5
		if _skyline_v(cam, p, mid) < target:
			hi = mid
		else:
			lo = mid
	return clampf(hi, floor_s, 1.0)

static func _skyline_v(cam: Camera3D, p: Vector3, s: float) -> float:
	return cam.unproject_position(p * s).y

# ---------------------------------------------------------------------------
# Animation
# ---------------------------------------------------------------------------
# The GLB carries one clip per world, named "Scene": 300 keys per channel at 30 fps,
# t = 0.0333 .. 10.0. Frame 301 is keyed identical to frame 1, which is the standard
# game-loop convention — so the clip's LENGTH is 10.0 s and the wrap from the last
# key back to the first spans exactly one frame. Godot's LOOP_LINEAR interpolates
# across that wrap, so the loop is seamless with the imported length untouched;
# nothing is retimed, resampled or rebuilt.
#
# The Animation resources are sub-resources of the imported PackedScene and are
# shared by every instance of it, so the loop flag is set once and costs nothing on
# later builds.
const CLIP := "Scene"

# Two channels that used to be in that clip are gone, and it is worth knowing why the
# .glb no longer matches what the .blend shipped on 2026-08-26. FOREST_GlowMushrooms
# keyed OBJECT scale 0.95 -> 1.05 and FOREST_GlowPlants (the crystal shards) keyed it
# 0.90 -> 1.10.
#
# OBJECT SCALE IN THESE WORLDS IS ABOUT THE WORLD ORIGIN, and both of those meshes are
# a scatter of many small pieces 3 .. 4.4 m out from it — so neither curve is a pulse,
# it is a TRANSLATION that grows with radius: +-0.2 m of ground travel per mushroom,
# +-0.44 m per crystal. What the player saw was the whole bed swimming. Both actions
# were removed at the source and the world re-exported (36 -> 34 channels, everything
# else identical in shape: same 48 nodes, same 300 frames, same 0.0333 .. 10.0 s).
# The same pass rebuilt the mushrooms themselves from flat discs into capped
# toadstools; see the revision note in Themes2/README.md.

static func _start_animation(scene: Node3D) -> void:
	var ap := _player(scene)
	if ap == null:
		push_warning("WorldScenes: no AnimationPlayer in %s" % scene.name)
		return
	var anim := ap.get_animation(CLIP)
	if anim == null:
		push_warning("WorldScenes: no '%s' clip in %s" % [CLIP, scene.name])
		return
	anim.loop_mode = Animation.LOOP_LINEAR
	# Physics-step playback would tie the motion to a fixed tick the board does not
	# otherwise use; idle keeps it on the same clock the redraw nudge runs on.
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	# Start each world somewhere other than frame 1, so a shop card and a freshly
	# opened board show the field of drifting things populated rather than all
	# lined up at the top of its cycle. Deterministic per world, not random, so a
	# preview bake is reproducible.
	ap.play(CLIP)
	ap.seek(fposmod(float(hash(scene.name) % 997) * 0.01, anim.length), true)

# Drop the clip entirely (see STILL). The nodes are left exactly where the import
# put them, which is the .blend's frame-1 pose.
static func _freeze_animation(scene: Node3D) -> void:
	var ap := _player(scene)
	if ap == null:
		return
	ap.get_parent().remove_child(ap)
	ap.queue_free()

static func _player(scene: Node) -> AnimationPlayer:
	for c in scene.get_children():
		if c is AnimationPlayer:
			return c
	return scene.find_child("AnimationPlayer", true, false) as AnimationPlayer

# Stop or resume a built world's clip. The board calls this when it stops being
# visible: the viewport already stops redrawing, but an AnimationPlayer keeps
# writing transforms every idle frame whether anyone is looking or not.
static func set_playing(root: Node3D, on: bool) -> void:
	if root == null or not is_instance_valid(root):
		return
	var ap := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap == null:
		return
	if on:
		if not ap.is_playing():
			ap.play(CLIP)
	elif ap.is_playing():
		ap.pause()

static func _strip_imported_lights(node: Node) -> void:
	for c in node.get_children():
		if c is Light3D:
			node.remove_child(c)
			c.queue_free()
		else:
			_strip_imported_lights(c)

# An inverted box enclosing the whole world, painted its own deepest sky tone.
# Unshaded, depth-write off, never shadowed: it is the "there is nothing further
# away than this" surface, and it can never occlude anything in front of it.
static func _backdrop(world: String) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = Vector3(BACKDROP_SIZE, BACKDROP_SIZE, BACKDROP_SIZE)
	var mi := MeshInstance3D.new()
	mi.name = "Backdrop"
	mi.mesh = box
	mi.layers = BG_LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = BACKDROP_SIZE
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_FRONT              # we are inside it
	m.albedo_color = _backdrop_color(world).linear_to_srgb()
	m.disable_receive_shadows = true
	mi.material_override = m
	return mi

static func _backdrop_color(world: String) -> Color:
	# Through the same match the sky cards take, so the fill behind them sits at the
	# same level: on a lens wide enough to see past a card's edge, the two have to be
	# the same colour or the seam shows as a band.
	var c: Color = BACKDROP.get(world, Color(0.006, 0.008, 0.014))
	var k := blender_exposure(world)
	var m := agx_match1(maxf(c.r, maxf(c.g, c.b)) * k)
	var d := maxf(maxf(c.r, maxf(c.g, c.b)) * k, 1e-5)
	var g := (m / d) / BOARD_TONEMAP_EXPOSURE
	return Color(c.r * k * g, c.g * k * g, c.b * k * g)

# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------

static func _dress_meshes(scene: Node3D, world: String) -> void:
	for spec: Dictionary in Data.OBJECTS.get(world, []):
		var mesh_name := String(spec["name"])
		var mi := scene.find_child(mesh_name, true, false) as MeshInstance3D
		if mi == null:
			push_warning("WorldScenes: no mesh node named %s" % mesh_name)
			continue
		mi.layers = BG_LAYER
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var slots: Array = spec.get("slots", [])
		for s in mini(slots.size(), mi.mesh.get_surface_count()):
			var md: Dictionary = Data.MATERIALS.get(String(slots[s]), {})
			if md.is_empty():
				continue
			mi.set_surface_override_material(s, _material(md, world))

# ---------------------------------------------------------------------------
# Where each material sits on the curve
# ---------------------------------------------------------------------------
# Godot adds a mesh's light contribution AFTER fragment() has returned, so a spatial
# shader can never see the lit result and can never put a tone curve on it. Without
# one, Godot's AgX crushes every shadow in these worlds: Inferno's basalt crust was
# albedo 0.078 and renders pure black where the reference has a visible dark plum.
#
# What the shader CAN know before anything is drawn is roughly how bright a given
# material ends up, because these worlds are lit by a fixed rig aimed at a fixed
# island and the irradiance on it is the same everywhere to within a stop. So the
# curve is LINEARISED at that point: the material's own albedo against one reference
# irradiance says where on the curve it sits, and the correction there is folded
# into its ALBEDO as a constant, with the conversion out of Blender's display
# exposure into the board's folded in with it.
#
# The variable that matters here is the ALBEDO — dark rock against pale stone is a
# factor of ten, where the rig's irradiance across a world varies by well under
# two — so the reference irradiance is one swept number for all six rather than a
# per-world sum. 4.5 is where the six land together (tools/world_tune.gd): the
# geometric-mean ratio across them is 1.24/1.32/1.40 at 1.0, 0.97/1.05/1.10 at 3.0
# and 0.86/0.95/0.98 at 6.0. It also keeps the two knobs independent: LIGHT_SCALE still moves
# the actual light level, which a per-world estimate would silently cancel out.
#
# It is a linearisation, not the curve. A surface facing away from every light is
# corrected as if it faced them, so shadow sides come out slightly flat — which is
# the right direction to be wrong in, against the alternative of losing them
# entirely.
static var TONE_IRRADIANCE := 4.5

static func _tone_factor(albedo: Color) -> float:
	var v := albedo.r * 0.2126 + albedo.g * 0.7152 + albedo.b * 0.0722
	v *= TONE_IRRADIANCE
	if v <= 1e-5:
		return 1.0 / BOARD_TONEMAP_EXPOSURE
	return (agx_match1(v) / v) / BOARD_TONEMAP_EXPOSURE

# The GDScript twin of the shader's agx_match1 — same cubic, same clamp.
static func agx_match1(u: float) -> float:
	var x := clampf(log(maxf(u, 1e-5)) / log(2.0), AGX_LOG_MIN, AGX_LOG_MAX)
	var y: float = AGX_FIT.x + x * (AGX_FIT.y + x * (AGX_FIT.z + x * AGX_FIT.w))
	return pow(2.0, y)

# One ShaderMaterial per (material, world) — cached, because a world reuses the
# same handful across dozens of meshes and the shop bakes six cards in a row.
static var _mat_cache: Dictionary = {}

static func _material(md: Dictionary, world: String) -> ShaderMaterial:
	var blend: bool = bool(md.get("blend", false))
	var key := "%s/%s" % [str(md), world]
	if _mat_cache.has(key):
		return _mat_cache[key]

	var mat := ShaderMaterial.new()
	mat.shader = _shader(blend)
	var base: Color = md["base"]
	mat.set_shader_parameter("base", Vector3(base.r, base.g, base.b))
	mat.set_shader_parameter("vc_base", 1.0 if bool(md.get("vc_base", false)) else 0.0)
	mat.set_shader_parameter("vc_emis", 1.0 if bool(md.get("vc_emis", false)) else 0.0)
	mat.set_shader_parameter("vc_alpha", 1.0 if bool(md.get("vc_alpha", false)) else 0.0)
	mat.set_shader_parameter("alpha", float(md.get("alpha", 1.0)) * float(md.get("base_a", 1.0)))
	mat.set_shader_parameter("metallic", float(md.get("metallic", 0.0)))
	mat.set_shader_parameter("roughness", float(md.get("roughness", 0.5)))
	mat.set_shader_parameter("specular", _specular(md))
	# The emissive term is resolved to LINEAR light here and written straight into
	# the shader, instead of going through a StandardMaterial3D's
	# emission_energy_multiplier — which the Compatibility renderer applies in sRGB,
	# so a strength of 3 emits about 8x rather than 3x. Doing the multiply in the
	# shader side-steps that entirely.
	# The emissive term is handed to the shader in BLENDER display-referred linear —
	# the material's own value at that world's view exposure — because that is the
	# domain agx_match is defined in. The shader converts to Godot's after the match.
	var e: Color = md["emis"]
	var g := float(md.get("emis_strength", 0.0)) * blender_exposure(world)
	mat.set_shader_parameter("emis", Vector3(e.r * g, e.g * g, e.b * g))
	mat.set_shader_parameter("sat", PUNCHY_SATURATION)
	mat.set_shader_parameter("amb", AMBIENT_COLOR * AMBIENT_GAIN)
	mat.set_shader_parameter("tone", _tone_factor(base))
	if blend:
		# Nothing in the transparent layer casts a shadow or should be sorted
		# against the opaque set; depth ordering between the haze cards themselves
		# is by distance, and they sit at very different depths.
		mat.render_priority = -1
	_mat_cache[key] = mat
	return mat

# Blender's "Specular IOR Level" and Godot's SPECULAR are not the same number and
# feeding one to the other is a 2.5x error in reflectance on the ice deck.
#
#   Blender  F0 comes from the IOR, ((n-1)/(n+1))^2, scaled by the level against its
#            own 0.5 default.
#   Godot    F0 = 0.16 * SPECULAR^2.
#
# So the level is resolved to an F0 and the F0 back to Godot's parameter. A material
# at Blender's defaults (IOR 1.45, level 0.5) comes out at 0.459, i.e. all but
# Godot's own default — which is the check that the mapping is right.
static func _specular(md: Dictionary) -> float:
	var ior := float(md.get("ior", 1.45))
	var level := float(md.get("specular", 0.5))
	var n := (ior - 1.0) / maxf(ior + 1.0, 0.001)
	var f0 := n * n * (level / 0.5)
	return clampf(sqrt(maxf(f0, 0.0) / 0.16), 0.0, 1.0)

static func clear_cache() -> void:
	_mat_cache.clear()

# ---------------------------------------------------------------------------
# Shader
# ---------------------------------------------------------------------------
# Two programs for the whole set — opaque and blended. Every per-material
# difference is a uniform, including whether the vertex colour multiplies base,
# emission and alpha, so the Compatibility renderer compiles two shaders on a first
# open instead of one per material. The extra `mix` per channel is free next to a
# compile stutter on a mobile GL driver.
static var _shader_cache: Dictionary = {}

static func _shader(blend: bool) -> Shader:
	var key := int(blend)
	if _shader_cache.has(key):
		return _shader_cache[key]
	var sh := Shader.new()
	sh.code = _shader_code(blend)
	_shader_cache[key] = sh
	return sh

# One cubic through log2. `1e-5` keeps log2 off zero for an unlit fragment; the
# clamp keeps the cubic inside the data it was fitted to.
#
# It is driven by the BRIGHTEST CHANNEL and applied as a scale on the colour, not
# run per channel, and not driven by luminance either. All three were measured:
#
#   per channel   destroys saturation. The curve lifts 0.02 by 4x and 2.0 by 0.5x,
#                 so Inferno's hot orange lava (3.5, 1.1, 0.2) comes out of it a
#                 pale peach — which is exactly what it did.
#   luminance     over-brightens saturated darks. A deep blue (0.02, 0.10, 0.30) has
#                 a luminance of 0.098 and gets that value's 2.5x lift applied to
#                 its blue channel too, which took Ice and Crystal to twice the
#                 reference's mean.
#   max channel   anchors the dominant channel exactly where the per-channel curve
#                 would put it — which is where the neutral measurement says it
#                 belongs — and carries the other two with it, so hue and saturation
#                 are untouched. Both failure modes go away at once.
const _AGX_GLSL := "
float agx_match1(float u) {
	float x = clamp(log2(max(u, 1e-5)), %.2f, %.2f);
	float y = %.6f + x * (%.6f + x * (%.6f + x * %.6f));
	return exp2(y);
}
vec3 agx_match(vec3 c) {
	float m = max(c.r, max(c.g, c.b));
	if (m <= 1e-5) { return vec3(0.0); }
	return c * (agx_match1(m) / m);
}
"

static func _shader_code(blend: bool) -> String:
	# `ambient_light_disabled` is mandatory, not stylistic: the board's Environment
	# carries a bright grey-blue ProceduralSky as its reflection source, deliberately,
	# because the button frames are metallic 0.9 and that sky's specular is the only
	# thing that puts a studio highlight on them. Blender's world here is a dim
	# gradient. Left on, every deck mirrors the studio sky and comes out flat
	# mid-grey with the design invisible under it; `amb` below puts back the world
	# lighting that SHOULD be there.
	var modes := "cull_disabled, ambient_light_disabled"
	if blend:
		modes = "cull_disabled, ambient_light_disabled, depth_draw_never, shadows_disabled"
	var s := "shader_type spatial;\nrender_mode %s;\n\n" % modes
	s += "uniform vec3 base;\nuniform vec3 emis;\nuniform vec3 amb;\nuniform float tone;\n"
	s += "uniform float vc_base;\nuniform float vc_emis;\nuniform float vc_alpha;\n"
	s += "uniform float alpha;\nuniform float metallic;\nuniform float roughness;\n"
	s += "uniform float specular;\nuniform float sat;\n"
	s += _AGX_GLSL % [AGX_LOG_MIN, AGX_LOG_MAX,
		AGX_FIT.x, AGX_FIT.y, AGX_FIT.z, AGX_FIT.w]
	s += "\nvarying vec3 nrm_world;\n"
	s += "void vertex() {\n"
	# NORMAL is model space in vertex() and view space by the time fragment() sees
	# it; resolving world space here keeps which-is-which unambiguous, because
	# getting it backwards silently zeroes the sky term instead of failing.
	s += "\tnrm_world = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);\n"
	s += "}\n\n"
	s += "void fragment() {\n"
	# COLOR is (1,1,1,1) on a mesh with no colour attribute, which is exactly what
	# a material asking for one on such a mesh should get — the same conclusion
	# Blender's own exporter reached when it wrote the flat factor into the .glb.
	s += "\tvec3 vc = mix(vec3(1.0), COLOR.rgb, vc_base);\n"
	s += "\tvec3 alb = base * vc;\n"
	# `tone` is the match curve evaluated at THIS material's own operating point (see
	# _tone_factor). The lit result cannot be corrected after the fact — Godot adds
	# the light contribution once fragment() has returned, and no hook sees the sum —
	# so the correction is folded into the albedo instead, at the brightness this
	# material is actually lit to.
	s += "\tALBEDO = alb * tone;\n"
	s += "\tMETALLIC = metallic;\n\tROUGHNESS = roughness;\n\tSPECULAR = specular;\n"
	# The world background EEVEE lights these with, standing in for the ambient this
	# material had to disable. Written to EMISSION rather than through a light
	# because that is what it is — incoming sky, not a lamp: unshadowed, no falloff,
	# tinted by the surface's own reflectance.
	s += "\tfloat up = clamp(nrm_world.y, 0.0, 1.0);\n"
	# One more contributor to the LIT total, not a separate picture, so it is added
	# linearly alongside the lights rather than run through the match on its own.
	s += "\tEMISSION = amb * alb * tone * mix(%.3f, 1.0, up);\n" % AMBIENT_FLOOR
	s += "\tvec3 g = emis * mix(vec3(1.0), COLOR.rgb, vc_emis);\n"
	# Punchy's saturation half, which the measured curve cannot carry.
	s += "\tfloat lum = dot(g, vec3(0.2126, 0.7152, 0.0722));\n"
	s += "\tg = max(mix(vec3(lum), g, sat), vec3(0.0));\n"
	# ...then into the value Godot's own AgX turns into Blender's picture, and out
	# of Blender's display exposure into the board's.
	s += "\tEMISSION += agx_match(g) * %.6f;\n" % (1.0 / BOARD_TONEMAP_EXPOSURE)
	if blend:
		s += "\tALPHA = alpha * mix(1.0, COLOR.a, vc_alpha);\n"
	s += "}\n"
	return s

# ---------------------------------------------------------------------------
# Lights
# ---------------------------------------------------------------------------

static func _add_lights(root: Node3D, world: String) -> void:
	var k := blender_exposure(world)
	for L: Dictionary in Data.LIGHTS.get(world, []):
		_add_light(root, L, k)

static func _add_light(root: Node3D, L: Dictionary, k: float) -> void:
	var kind := String(L["type"])
	var col: Color = L["color"]
	var watts := float(L["energy"]) * k * LIGHT_SCALE
	var origin: Vector3 = L["origin"]
	var basis: Basis = L["basis"]
	var lname := String(L["name"])

	if kind == "SUN":
		_directional(root, lname, basis, col, watts * _INV_PI)
		return

	if kind == "POINT":
		_omni(root, lname, origin, col, watts * 0.25 * _INV_PI * _INV_PI,
			float(L.get("radius", 0.0)))
		return

	var sx := float(L["size"])
	var sy := float(L.get("size_y", 0.0))
	if sx * sy >= _DIR_AREA:
		# A directional has no position, so the panel's irradiance has to be
		# evaluated somewhere: the middle of the composition, which is where the deck
		# and the buttons are and what the panel was aimed at.
		var d := maxf(origin.length(), 0.5)
		_directional(root, lname, basis, col, watts * _INV_PI / (PI * d * d))
		return

	# A strip: local, does fall off, and must not read as one hotspot in the middle
	# of a 13 m panel, so the power is spread along the strip's own long axis.
	var long_axis: Vector3 = basis.x if sx >= sy else basis.y
	var length := maxf(sx, sy)
	var n := clampi(int(round(length / 3.5)), 1, _MAX_SPLIT)
	var intensity := watts * _INV_PI * _INV_PI / float(n)
	for i in n:
		var t := 0.0 if n == 1 else (float(i) / float(n - 1) - 0.5)
		var p := origin + long_axis.normalized() * (t * length * 0.5)
		_omni(root, "%s_%d" % [lname, i], p, col, intensity, 0.0)

static func _directional(root: Node3D, name: String, basis: Basis, col: Color, energy: float) -> void:
	var d := DirectionalLight3D.new()
	d.name = name
	# A Blender area light and a Godot directional both emit along their own -Z, so
	# the panel's orientation carries across untouched. Position is dropped, which
	# is the point: a directional has none.
	d.basis = basis
	d.light_color = col.linear_to_srgb()
	d.light_energy = energy
	d.light_cull_mask = BG_LAYER
	# See _omni: no rebuilt light contributes specular. A Blender area panel's
	# highlight is its own SHAPE reflected in the surface — ICE_Light_Sheen is
	# 13 m x 0.25 m seen from 10 m, an angular half-width of about 30 degrees — and
	# the only way to say that to a Godot light is a roughness this material does
	# not have. Rendered as a point source instead, the same panel puts a blown
	# white ellipse on a deck at roughness 0.145 where the reference has a soft
	# gradient. At that angular size the panel's specular and its ambient are the
	# same thing anyway, and the shader's own sky term carries it.
	d.light_specular = 0.0
	# No shadow anywhere in the set. The reference has almost none to reproduce —
	# these scenes are lit by wide soft panels and by their own emission — and a
	# shadow map per light would be up to eleven of them per world on a mobile GL
	# driver.
	d.shadow_enabled = false
	root.add_child(d)

static func _omni(root: Node3D, name: String, pos: Vector3, col: Color,
		intensity: float, radius: float) -> void:
	var o := OmniLight3D.new()
	o.name = name
	o.position = pos
	o.omni_range = _LIGHT_RANGE
	o.omni_attenuation = 2.0             # true inverse square, as Blender has it
	o.light_color = col.linear_to_srgb()
	o.light_energy = intensity
	o.light_cull_mask = BG_LAYER
	o.shadow_enabled = false
	# NO specular from any of these. Every one stands in for something Blender
	# integrates over an AREA — a crystal core, a lava vent, a 13 m strip cut into
	# three — and a Godot point light's specular on a surface at roughness 0.06 to
	# 0.15 (which is what an ice deck, a crystal and a lava crust all are here) is a
	# near-singularity: it renders as a blown white ellipse metres across where the
	# reference has a soft gradient. Their diffuse contribution is what the
	# composition is actually made of.
	o.light_specular = 0.0
	if radius > 0.0:
		o.light_size = radius
	root.add_child(o)

# ---------------------------------------------------------------------------
# Shop preview
# ---------------------------------------------------------------------------
# The camera all six were composed against, from the .blend itself: the real
# LUME_Gameplay_Camera, unmoved. A card frames a world the way its author did.
# How far LUME_Gameplay_Camera looks down. Its Blender matrix is a pure X rotation
# whose forward is (0, 0.8339, -0.5519), i.e. asin(0.5519) = 33.51 deg below level.
const PREVIEW_PITCH_DEG := 33.51

static func make_preview_camera(_aspect: float) -> Camera3D:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.keep_aspect = Camera3D.KEEP_WIDTH        # Blender's own sensor fit at 16:9
	cam.fov = Data.REF_CAM_FOV
	cam.near = 0.15
	cam.far = 400.0
	# Position and pitch straight off the .blend camera: it sits on the world's
	# centre line and looks down PITCH_DEG, so a plain rotation is the whole pose.
	cam.position = Data.REF_CAM_ORIGIN
	cam.rotation = Vector3(-deg_to_rad(PREVIEW_PITCH_DEG), 0.0, 0.0)
	return cam

# A card shows the world with the real board standing on it, so what a player buys
# is what a player gets. The bake is exposed exactly like gameplay — same AgX, same
# materials, same lights, same camera — because unlike the Themes1 floors there IS
# a board in the frame carrying the composition's mid-tones.
static func make_preview_environment(world: String) -> WorldEnvironment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = _backdrop_color(world).linear_to_srgb()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = BOARD_TONEMAP_EXPOSURE
	env.glow_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	return we
