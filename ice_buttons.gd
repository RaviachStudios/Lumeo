extends RefCounted
class_name IceButtons

# The ICE KINGDOM gameplay buttons — the snowflake carved out of coloured ice that
# replaces the stock disc-in-a-black-bezel while `world_ice` is the equipped 3D
# background.
#
# Authored in Blender (APP IDEAS/Simon/IceButtons/IceButtons.blend, rebuildable
# from the `ice_snowflake_*` text blocks inside it) and shipped as one .glb per
# colour in res://models/buttons/.
#
# ---------------------------------------------------------------------------
# Why this is a MESH SWAP and nothing else
# ---------------------------------------------------------------------------
# Each .glb holds exactly the two meshes a stock button is made of, built to the
# same contract, measured off the shipping boards rather than guessed:
#
#   Button_<Key>_Surface   y 0.245 -> 0.525, r <= 1.000   slot 0 ice, slot 1 frost
#   Button_<Key>_Frame     y 0.000 -> 0.141, r <= 0.780   slot 0 socket, slot 1 glow
#
# Same node names, same origins, same identity transforms, same z range as the
# stock surface, same two-surface split with the same meaning. So wearing them is
# `mi.mesh = ice_mesh` on the board's OWN MeshInstance3D nodes — the nodes stay,
# and with them every single thing the board already does:
#
#   * `Press_<Key>` still plays: the clip animates the NODE's transform, and the
#     node is untouched.
#   * the emission state machine still drives idle/highlight/pressed/disabled:
#     it reads surface 0 and 1 of each mesh, which mean what they always meant.
#   * the Area3D hit shape is a child of the STATIONARY parent and never moves;
#     the flake fits inside it (r 1.00 against the shape's 1.12).
#   * `_space_buttons`, the camera fit, the ground pools and the render cadence
#     all key off the button parents and the frame radius, neither of which moved.
#
# Nothing in game.gd, the level system, the audio or the layout is aware this
# happened. There is no second board, no second scene and no repositioning.
#
# ---------------------------------------------------------------------------
# Why the imported materials are re-authored here
# ---------------------------------------------------------------------------
# The .glb arrives correct and is not the problem, and that was MEASURED on the
# shipped asset before anything was touched (`python3 tools/glb_audit.py
# models/buttons/Ice_Snowflake_*.glb`, identical on all seven):
#
#   6456 triangles, 1020 split vertex positions, widest normal break 137 deg
#   0 degenerate triangles, 0 non-unit normals
#   0 non-manifold edges, 0 inconsistently wound edges
#   every node at an identity transform
#   attributes POSITION, NORMAL, COLOR_0
#
# The split-position count is the one that matters and it is the sharp-edge test:
# a mesh with hard creases has to duplicate a vertex to carry two normals at one,
# so a near-zero count would mean the builder's SHARP_DEG pass never reached the
# export (which is exactly what the lily pad's did — 5 splits in 6706 vertices).
# 1020 of 3232, breaking at up to 137 deg, is every bevel ring and every plan
# corner arriving intact. Nothing about the geometry needs fixing.
#
# What was wrong was the same two things the lily pads hit (see
# lily_buttons.gd and the shading-pipeline note):
#
# 1. COLOR_0 WAS BEING DISCARDED. The builder paints depth into a per-vertex
#    attribute — thick ice through the hub reads deep and saturated, the thin arm
#    tips and every bevel read lighter and a touch cooler — wired in Blender as
#    MULTIPLY(flat colour, "Col"), which is exactly glTF's COLOR_0 semantics. The
#    export carries it; Godot's importer loads it, uploads it and then leaves
#    `vertex_color_use_as_albedo` FALSE, so the whole thickness gradient was
#    thrown away and every arm rendered one flat value.
#
# 2. THE FLAKE WAS SELF-LIT, SO IT HAD NO SHAPE. The exported emission is the
#    flake's own colour at strength 1.39 on the ice, 3.11 on the bevel ring and
#    3.37 on the under-glow — measured in the board's own studio that puts the ice
#    body at radiance ~1.4, four to five times what a lily pad carries. A flat
#    self-lit surface has no gradient across it, so the render was a coloured
#    silhouette with a hard white stroke round it: no bevel roll, no hub dome, no
#    side-wall falloff, no highlight anywhere. The one thing that DID read as 3D
#    was the side wall, and only because it faces a different way.
#
#    That emission was authored for a room with nothing in it. The board's studio
#    is two DirectionalLights at 0.14 and 0.05 energy whose entire job is a
#    specular highlight on six small metallic bezels, and the source .blend has no
#    lights either — so "raise the emission until it is visible" was the only move
#    available, and it is a substitute for lighting rather than lighting.
#
# So the emission becomes a FLASH channel — a faint idle glow derived from each
# flake's OWN albedo, exactly as the pads do it — and the flake is LIT instead,
# by a rig this skin brings with it and that is culled to the board's own layer
# (MemoryGameUI._light_skin). Nothing about the palette moves: every emission
# below is a multiple of the colour the asset was authored with, so the six
# flakes keep the relationships Blender gave them, and the four emission rungs
# the state machine drives are unchanged multipliers on top.
#
# ---------------------------------------------------------------------------
# Clearance
# ---------------------------------------------------------------------------
# The socket's height is DERIVED from the flake's own underside minus the board's
# 0.115 press travel minus 0.035 of air, sampled over the neighbourhood each face
# can reach rather than at its corners. Verified in Blender with an evaluated-mesh
# BVH sweep across the whole travel and 20% past it: zero intersecting faces, and
# 0.0353 of clearance at the bottom of the stroke.

# The 3D-background id this look belongs to. Ownership, price, purchase and equip
# are CoinsManager.THEMES and `selected_theme` — see WorldScenes.CATALOG.
const THEME_ID := "world_ice"

# This look needs the board's viewport anti-aliased. The board runs without MSAA by
# default because the stock button is a big disc; these are not (see
# MemoryGameUI._antialias_for, which measures what it costs and what it fixes).
const WANTS_AA := true

const PATH := "res://models/buttons/Ice_Snowflake_%s.glb"

# Every colour key the three boards use. The first six are Medium's and Hard's;
# EASY names its third button "Yellow" and authors it as a true yellow rather than
# Hard's orange-gold "Amber", so it gets its own variant off the same mesh. All
# seven are one design in seven colours — no board has a different snowflake.
const KEYS := ["Crimson", "Jade", "Cyan", "Amber", "Violet", "Magenta", "Yellow"]

# ---------------------------------------------------------------------------
# Idle emission, per slot
# ---------------------------------------------------------------------------
# A multiplier on the radiance THIS SLOT WAS AUTHORED WITH, not a colour and not a
# level of our own. Every one of the four is a plain scalar, so each material keeps
# its exported hue exactly — the ice body glows its own colour, the bevel band its
# pale frost, the socket the fixed blue-grey it was given and the under-glow the
# flake's colour — and the six buttons keep the relationships Blender gave them.
# The palette does not move; only how much of the picture is self-lit does.
#
# Idle only. The board's state machine multiplies these by 2.60x / 2.40x for a
# highlight and again by HIGHLIGHT_BOOST / HIGHLIGHT_GLOW_BOOST, so the flash is
# unchanged machinery sitting on a quieter resting value.
#
# Measured, not guessed: as exported the ice body sits at radiance ~1.17 in the
# blue and the bevel band at ~1.72, four to five times what a lily pad carries, and
# a surface emitting that much has no gradient left to show its shape with. These
# put the body a shade under the pads' dish and the band a shade over their rim,
# which is where the two assets belong relative to each other — a crystal edge
# catches more light than a leaf's does.
#
# The socket is the one that may NOT be pulled far down. It is a frosted disc in a
# near-black studio and the whole point of the ice housing is that it does not read
# as the black bezel it replaces, so it keeps more than a third of its authored
# glow on top of what the rig now gives it.
const SURFACE_EMISSION := 0.34      # the coloured ice body      (slot 0, driven)
const RING_EMISSION := 0.26         # the bevel/boss frost band  (slot 1, driven)
const SOCKET_EMISSION := 0.18       # the frosted housing        (slot 0, static)
const GLOW_EMISSION := 0.55         # the under-glow + its pool  (slot 1, driven)

# The one ALBEDO the pass touches, and only in level — the hue is untouched.
#
# The socket is a pale frost at roughness 0.52 and it was authored for a room with
# no light in it: everything it shows had to come out of its own emission, so its
# base colour was picked bright. Lit by the rig below it is the single surface on
# the button that takes the most diffuse, and at its authored value it renders as a
# WHITE plastic puck that outshines the snowflake standing on it — the housing
# reading louder than the button is exactly backwards.
#
# Scaled here rather than dimmed with light, because the light is shared with the
# flake and the flake wants it. 0.55 puts the socket back on the pale blue-grey it
# rendered at before the rig existed, and it stays well clear of the black bezel the
# whole ice housing exists to not be: (0.20, 0.24, 0.40) is still plainly frost.
const SOCKET_ALBEDO := 0.55

# key -> {"surface": Mesh, "frame": Mesh}. One entry per colour in play, so Hard
# costs six pairs of Meshes and their materials, and nothing else: the .glb has no
# textures, no images, no animation and no skin in it.
static var _cache: Dictionary = {}


# Is the Ice Kingdom look the one currently equipped?
static func active() -> bool:
	return active_for(CoinsManager.selected_theme)


# Does a board standing on `theme_id` wear the snowflakes? Boards ask this about the
# background they are ACTUALLY standing on rather than about the wallet, because a
# shop card is the same board with a background the player has not equipped (and may
# not own) — see MemoryGameUI._wanted_background. That is what puts the flakes in the
# Ice Kingdom card's own preview, and equally what keeps them out of every other
# card's: a preview standing on some other world, or on nothing at all, is stock.
static func active_for(theme_id: String) -> bool:
	return theme_id == THEME_ID


# The two meshes for one colour, or {} if the asset is missing — in which case the
# caller keeps the stock button rather than showing half a board.
static func build(key: String) -> Dictionary:
	if _cache.has(key):
		return _cache[key]
	if not KEYS.has(key):
		return {}
	var path := PATH % key
	if not ResourceLoader.exists(path):
		push_warning("IceButtons: missing %s" % path)
		return {}
	var ps: PackedScene = load(path)
	if ps == null:
		push_warning("IceButtons: cannot load %s" % path)
		return {}
	var root := ps.instantiate()
	var surf := root.find_child("Button_%s_Surface" % key, true, false) as MeshInstance3D
	var frame := root.find_child("Button_%s_Frame" % key, true, false) as MeshInstance3D
	var out: Dictionary = {}
	if surf != null and surf.mesh != null and frame != null and frame.mesh != null:
		out = {
			"surface": _dress(surf.mesh, [SURFACE_EMISSION, RING_EMISSION], [1.0, 1.0]),
			"frame": _dress(frame.mesh, [SOCKET_EMISSION, GLOW_EMISSION], [SOCKET_ALBEDO, 1.0]),
		}
		_cache[key] = out
	else:
		push_warning("IceButtons: %s has no Button_%s_Surface/_Frame" % [path, key])
	# Drop the throwaway instance; the two Meshes we kept survive it, the
	# PackedScene does not.
	root.free()
	return out


# Release everything but the colours named. Called with the live board's own keys,
# so a difficulty change does not leave the previous board's meshes resident.
static func trim_cache(keep: Array) -> void:
	for key: String in _cache.keys():
		if not keep.has(key):
			_cache.erase(key)


# ---------------------------------------------------------------------------
# The materials
# ---------------------------------------------------------------------------
# One .glb mesh, rebuilt as an ArrayMesh with the SAME arrays and the same surface
# order, wearing re-authored copies of its own materials.
#
# Rebuilt rather than edited in place because a Mesh loaded from a PackedScene is a
# shared resource: writing a material onto it would change every board that ever
# instances the asset, including the shop card sitting behind the one being built.
# Nothing about the geometry is touched — the vertex, normal and colour arrays go
# across untouched and the index list is not even looked at.
#
# What a round trip through surface arrays does drop is any LOD chain the importer
# generated. That costs nothing here: a button is six small meshes at a fixed
# distance from a camera that never moves, so no LOD level was ever going to be
# selected. It would matter for anything that recedes.
static func _dress(src: Mesh, levels: Array, albedos: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for s in src.get_surface_count():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, src.surface_get_arrays(s))
		var base := src.surface_get_material(s) as StandardMaterial3D
		var level: float = levels[s] if s < levels.size() else 0.0
		var albedo: float = albedos[s] if s < albedos.size() else 1.0
		mesh.surface_set_material(s, _material(base, level, albedo))
	return mesh


# One slot of one button. Everything the asset authored is kept — albedo, colour,
# roughness, metallic, the clear coat, the lot — and exactly three things change.
static func _material(base: StandardMaterial3D, level: float,
		albedo: float) -> StandardMaterial3D:
	if base == null:
		return null
	var m := base.duplicate() as StandardMaterial3D
	# Level only, never hue: a scalar on all three channels keeps the ratios, and
	# the only slot that is ever passed anything but 1.0 is the socket.
	if not is_equal_approx(albedo, 1.0):
		var a := m.albedo_color
		m.albedo_color = Color(a.r * albedo, a.g * albedo, a.b * albedo, a.a)

	# 1. THE IMPORT FIX. Without this the "Col" attribute the builder painted the
	#    ice's thickness into is loaded, uploaded and then ignored, and every arm
	#    renders one flat value. Nothing about the asset changes.
	m.vertex_color_use_as_albedo = true

	# 2. THE EMISSION BECOMES A FLASH CHANNEL. The authored radiance, scaled — same
	#    colour, less of it. Resolved through the same round trip the board's own
	#    state machine uses (`_imported_emission` reads srgb_to_linear(emission) x
	#    the multiplier, `_apply_emission` writes linear_to_srgb of it back), so
	#    what lands here is exactly `level` times the radiance this slot rendered at
	#    before, and the state machine's four rungs then drive it untouched.
	m.emission = _radiance(base) * level
	# Pinned at 1.0 — the multiplier scales in sRGB and so does not scale the light
	# linearly. Everything goes in the colour, which is also the form the board
	# reads back and drives.
	m.emission_energy_multiplier = 1.0
	m.emission_enabled = level > 0.0

	# 3. THE SKY IS SHUT OUT. The board's Environment carries a bright ProceduralSky
	#    as its reflection source — it is there for six small metallic bezels — and
	#    polished ice at roughness 0.13 mirrors it straight back as a grey wash that
	#    takes the colour out of the button. Same trap the 3D backgrounds hit, and
	#    the same fix the pads needed.
	m.disable_ambient_light = true
	return m


# What one imported slot actually emits at rest, in the form the material stores it
# and the renderer uses it. Not the same as reading `emission`: Godot keeps the
# emission colour in sRGB and folds `emission_energy_multiplier` in BEFORE the
# conversion, so the pair only means what Blender authored once both have been put
# through the conversion the renderer will use.
static func _radiance(m: StandardMaterial3D) -> Color:
	if m == null or not m.emission_enabled:
		return Color(0, 0, 0)
	return (m.emission.srgb_to_linear() * m.emission_energy_multiplier).linear_to_srgb()


# ---------------------------------------------------------------------------
# Lights
# ---------------------------------------------------------------------------
# The rig the flakes bring with them, and the larger half of making them read as
# carved ice rather than as a coloured sticker.
#
# A snowflake's shape is almost entirely in its EDGES. The cap's top is a flat
# plane, so a light hitting it head-on renders it one value however bright it is;
# what a viewer reads is the rounded bevel running the whole silhouette, the
# crystal boss on the hub, and the side wall dropping to the socket. Those are
# small, steeply-angled surfaces, and they only separate from the flat top when the
# light comes ACROSS them rather than down at them.
#
# Culled to BOARD_LAYER, so the rig lights the buttons and cannot reach the ice cave
# behind them, and built ONLY while the snowflakes are worn
# (MemoryGameUI._light_skin) — no other background or board moves by a single count.
#
# ---------------------------------------------------------------------------
# WHY THESE ARE OMNI LIGHTS AND NOT A THREE-POINT DIRECTIONAL RIG
# ---------------------------------------------------------------------------
# THIS PROJECT'S RENDERER LIGHTS AN OBJECT WITH EXACTLY ONE DirectionalLight3D.
# Measured on the live board (tools/flake_look.tscn) rather than read anywhere:
# with the board's two studio directionals present, adding one, two or three more
# directional lights produced a BYTE-IDENTICAL render, at every energy tried
# including 12.0. Hiding the studio's two made the added rig appear at full
# strength — and then adding its second and third lights changed nothing again.
# Three omni lights in the same places stack normally, each one visibly adding.
#
# It fails silently in the worst possible way: no warning, no error, and a rig that
# looks correct in the scene tree, has the right cull mask, the right rotations and
# `visible = true` on every node, while contributing nothing at all. A skin that
# ships a three-point directional rig here is shipping one light, and if the board
# already has one it is shipping none — which is what the first pass at this did.
#
# So the fill and the rim are OMNI lights, placed far enough out (11-13 units,
# against a board only 4.3 across) and given a range far past the board that their
# falloff across it is a few per cent — a directional light in all but name, and one
# the renderer will actually draw. The board's own studio key keeps the single
# directional slot it has always had; nothing is taken away from it.
#
# ---------------------------------------------------------------------------
# SPECULAR IS THE ONE KNOB THAT MUST STAY MODEST
# ---------------------------------------------------------------------------
# Easy to get backwards on a material called "ice". A specular lobe is WHITE and
# adds the same amount to all three channels, so on a saturated albedo it does not
# brighten the colour, it removes it — and this asset is roughness 0.13 under a
# clear coat, so its specular is a tight and very bright lobe. The flakes are
# allowed more of it than a matte lily pad is, because a glint on a bevel is the
# whole "carved from ice" read, but it is spent on the RIM light — which grazes, so
# its lobe lands on the bevels and the side wall rather than on the flat top.
const RANGE := 48.0            # far past the board, so the falloff across it is flat
const ATTENUATION := 0.30
const LIGHTS := [
	# key: front-upper-left and faintly warm. This is what puts a direction on the
	# flake — the bevel down the left of every arm lights and the one down the right
	# falls away, which is the gradient the flat top cannot supply on its own.
	{"pos": Vector3(-7.5, 8.0, 8.5), "energy": 9.5, "color": Color(1.00, 0.97, 0.92), "spec": 0.16},
	# fill: from the right, cool and weak — it keeps the shaded bevels icy instead of
	# black without closing the gradient the key just opened.
	# Only FAINTLY cool. A strongly blue fill is the second way to grey a saturated
	# flake out: on Crimson, whose albedo is 13x more red than green, a (0.72,0.86,1.0)
	# fill puts in exactly the two channels the button does not have.
	{"pos": Vector3(9.5, 4.5, 6.0), "energy": 2.4, "color": Color(0.90, 0.94, 1.00), "spec": 0.08},
	# rim: from behind and low. This one carries the glints — it grazes the far
	# bevels and the side wall, which is where a crystal edge catches light, and it
	# is what separates the flake's silhouette from the socket underneath it.
	{"pos": Vector3(1.5, 3.6, -10.0), "energy": 5.0, "color": Color(0.86, 0.94, 1.00), "spec": 0.38},
]


# The rig, as loose nodes for the caller to parent and free. `cull` is the layer
# mask they may light, which is always the board's own.
static func lights(cull: int) -> Array:
	var out: Array = []
	for spec: Dictionary in LIGHTS:
		var l := OmniLight3D.new()
		l.position = spec["pos"]
		l.light_energy = float(spec["energy"])
		l.light_color = spec["color"]
		l.light_specular = float(spec["spec"])
		l.omni_range = RANGE
		l.omni_attenuation = ATTENUATION
		l.shadow_enabled = false          # six small props on a mobile GL driver
		l.light_cull_mask = cull
		out.append(l)
	return out
