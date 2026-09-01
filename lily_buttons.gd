extends RefCounted
class_name LilyButtons

# The MAGICAL LAKE gameplay buttons — a lily pad floating on the water, which is
# what replaces the stock disc-in-a-black-bezel while `world_lake` is the equipped
# 3D background.
#
# The pads themselves are authored in Blender (APP IDEAS/Simon/Skins/Leaf/Leaf.blend,
# rebuildable from lilypad_builder.py beside it) and ship as one .glb per colour in
# res://models/buttons/. NOTHING here remodels one: the pad arrives with its dish,
# its veins, its curled rim and its per-vertex shading intact and is used as it was
# authored.
#
# ---------------------------------------------------------------------------
# The same mesh swap the snowflakes are, and the two ways this asset differs
# ---------------------------------------------------------------------------
# Like ice_buttons.gd this is a MESH SWAP on the board's OWN MeshInstance3D nodes
# (see MemoryGameUI._apply_button_skin). The nodes stay, so the `Press_<Key>`
# clips, the emission state machine, the Area3D hit-testing, `_space_buttons`, the
# camera fit, the ground pools and the render cadence all keep working untouched,
# and nothing in game.gd or the level system is aware it happened.
#
# But the .glb was NOT built to the stock two-mesh contract the snowflakes were, and
# pretending otherwise would have meant re-exporting a finished asset. It carries
# ONE mesh, ONE surface, spanning the whole of a button's height:
#
#   stock   Button_<Key>_Surface   y 0.245 -> 0.525   slot 0 face,  slot 1 rim ring
#           Button_<Key>_Frame     y 0.000 -> 0.141   slot 0 metal, slot 1 under-glow
#   pad     LilyPad_Button_Mesh    y 0.000 -> 0.339   one slot
#
# So the contract is met HERE, in two steps, and both are geometry the pad wants
# anyway:
#
# 1. THE PAD IS SPLIT IN TWO at RIM_SPLIT, into the dish and the curled outer rim.
#    Not a decoration: the four emission rungs are driven through two channels on
#    purpose (see MemoryGameUI's HIGHLIGHT_BOOST note — the face may only be pushed
#    1.42x before its strongest channel clips and the hue slides toward white, the
#    ring takes 1.95x and reads as MORE colour). A single-surface pad would have to
#    take the whole flash on its face and would go pale exactly when the player is
#    reading it. Split, the flash is a bright ring running round the pad's raised
#    edge, which is both the readable signal and what a lily pad's edge does when
#    light catches it.
#
# 2. THE FRAME NODE BECOMES THE WATERLINE. A pad has no bezel and must not grow
#    one, but the node is still there, still stationary while the surface sinks,
#    and still the board's slot-1 under-glow channel. So it carries the two things
#    that only make sense at the waterline and only make sense if they DON'T move
#    with the press: a meniscus ring hugging the pad's own outline (surface 0) and
#    the coloured halo the pad lays on the water (surface 1). Both are built here,
#    both are flat, and both sit at LakeWorld.WATER_Y — so when a press sinks the
#    pad 11.5 cm they stay on the surface and the pad dips THROUGH them, which is
#    the whole "it is floating in the water, not on top of it" read.
#
# The meniscus follows the pad's MEASURED outline rather than a circle. The pad is
# not round (r 0.88 .. 1.01 with a notch), and a circular ring left a visibly
# uneven gap of open water on the narrow sides — about nine pixels at gameplay
# scale, which is enough to read as a sticker.
#
# ---------------------------------------------------------------------------
# The two things the glTF import gets wrong, and why they are fixed here
# ---------------------------------------------------------------------------
# 1. COLOR_0 IS DISCARDED. The pad's entire painted shading — the veins, the hub
#    dome, the rim band, the darker underside — lives in a POINT colour attribute
#    called "Col", wired in Blender as MULTIPLY(flat colour, Col) into Base Color
#    at factor 1.0. That is EXACTLY glTF's COLOR_0 semantics, so the export is
#    lossless and carries the attribute correctly.
#
#    Godot's glTF importer then leaves `vertex_color_use_as_albedo` FALSE, so none
#    of it is used and the pad renders as one flat slab of `baseColorFactor`.
#    Measured on the imported material (tools/pad_diag.tscn). Turning it on here is
#    the whole fix; nothing about the asset changes.
#
# 2. The pad is not lit enough to be a 3D object. See the LIGHTS block below —
#    that one is not an import bug, it is the board's studio being wrong for this
#    asset, and it is the larger half of the problem.
#
# ---------------------------------------------------------------------------
# Why the emission is re-authored and the albedo is not
# ---------------------------------------------------------------------------
# The board is a dark studio: its two DirectionalLights carry 0.14 and 0.05 of
# energy and exist to put a specular highlight on six small metallic bezels (see
# MemoryGameUI._build_lights). A stock button is ~80 % self-lit, and so is an ice
# snowflake. A pad imported as authored is a diffuse leaf with an emissiveFactor of
# about 0.13, and under that studio it renders (24,3,11) — black.
#
# So each pad gets an emission derived from ITS OWN albedo, never from a colour of
# our choosing: the palette stays the asset's and the six pads keep the
# relationships Blender gave them (bar the one correction NORM_POWER makes).
#
# The obvious way to do that is EMISSION_OP_MULTIPLY, which folds ALBEDO — and with
# it the COLOR_0 attribute the builder painted the veins, the hub and the rim band
# into — straight into the emission. **It does not work.** Measured with
# tools/emis_probe.tscn: under Godot 4.7's GL Compatibility renderer a material with
# EMISSION_OP_MULTIPLY emits NOTHING AT ALL, at any level, with any albedo. Silently
# — no warning, no error, just a black material.
#
# So the emission is a flat per-pad colour on EMISSION_OP_ADD, and the vein shading
# is carried by the LIT term underneath it: the pad's albedo really is
# vertex-coloured, the studio really does light it, and against a flat glow that
# modulation still reads at roughly a quarter of the pad's value, which is what
# keeps the veins and the hub dome visible. It is worth knowing that the shading
# comes from two different terms if either is ever re-tuned.
#
# The same probe found the second half of it: **the emission colour is used RAW.**
# Compatibility applies no sRGB-to-linear conversion to it, so whatever number is in
# `emission` is the radiance emitted (0.5 -> screen 123, 1.0 -> 161, 2.0 -> 194,
# against a measured ramp that puts a true linear 0.5 at 80). That is invisible to
# the rest of the board, whose emission pipeline round-trips its own values and is
# self-consistent either way — but a NEW material authored to a measured target has
# to write the target itself, which is what the constants below are.
#
# Cosmetic bezels are suppressed while pads are worn, for the same reason ice
# suppresses them (MemoryGameUI._refresh_frame): the eighteen frames are a lathe
# built for the stock disc, and wearing one covers the frame mesh's surface 0,
# which here is the meniscus.

# The 3D-background id this look belongs to. Ownership, price, purchase and equip
# are CoinsManager.THEMES and `selected_theme` — see LakeWorld.CATALOG.
const THEME_ID := "world_lake"

# This look needs the board's viewport anti-aliased. The board runs without MSAA by
# default because the stock button is a big disc; these are not (see
# MemoryGameUI._antialias_for, which measures what it costs and what it fixes).
const WANTS_AA := true

# ---------------------------------------------------------------------------
# Press travel
# ---------------------------------------------------------------------------
# How much of the board's own press stroke a pad takes. The GLB's Press_<Key> clip
# sinks a button 115 mm, which is right for a moulded plastic dome travelling into
# its housing and much too far for a leaf resting on water.
#
# Measured against the waterline rather than chosen by eye. The pad's dish sits
# 154 mm proud of LakeWorld.WATER_Y at rest; the full stroke leaves it 39 mm — it
# loses three quarters of its visible height and the middle all but goes under,
# which reads as the pad sinking rather than being pressed.
#
#   scale   travel    dish centre above water    of its resting height
#   1.00    -0.115          39 mm                      25 %   sinks: the dish's
#                                                             middle band passes
#                                                             under the surface and
#                                                             the pad goes murky
#   0.45    -0.052         102 mm                      66 %   chosen
#   0.35    -0.040         114 mm                      74 %   too subtle to read as
#                                                             a press at gameplay size
#
# 0.45 was picked at real gameplay size, between the two: at 0.35 the pad barely
# moved against its neighbours and the press stopped registering; at 0.45 it sits
# visibly lower than the ring around it, stays fully coloured, and its rim is still
# 192 mm proud. The dish's lowest point stays 43 mm above the waterline, so no part
# of the pad is ever occluded by the water.
#
# The board's own timing, easing and the small overshoot on the way back are all
# untouched — only the amplitude is scaled, so the press stays exactly as quick and
# as responsive as every other button's.
const PRESS_SCALE := 0.45

# Opt out of the board's Jade->deep-emerald correction (MemoryGameUI._recolour_jade),
# which replaces one button's albedo outright with JADE_TARGET. See the note there
# for why this asset is not a candidate for it.
const RECOLOUR_JADE := false

const LAKE := preload("res://lake_world.gd")

const PATH := "res://models/buttons/LilyPad_%s.glb"

# Board colour key -> the pad colour authored for it. The board's keys are the
# GLB's node names and are not ours to rename; the pads were authored to the six
# colours the design asked for, so this is where the two vocabularies meet.
#
# "Amber" and "Yellow" both take the yellow pad: Medium and Hard key their third
# button Amber (an orange-gold) and EASY keys its own third button Yellow, and a
# leaf has no reason to draw that distinction the way a moulded plastic dome did.
const PAD_FOR := {
	"Crimson": "Red",
	"Jade":    "Green",
	"Cyan":    "Cyan",
	"Amber":   "Yellow",
	"Violet":  "Purple",
	"Magenta": "Pink",
	"Yellow":  "Yellow",
}

# ---------------------------------------------------------------------------
# The split
# ---------------------------------------------------------------------------
# Where the dish stops and the curled rim starts, in board units. Measured off the
# asset rather than picked: the pad's underside climbs from y 0.118 at r 0.70 to
# y 0.267 at r 1.00, so 0.76 is inside the curl everywhere including the narrow
# sides, and outside the veined dish everywhere.
const RIM_SPLIT := 0.76

# How bright each half sits at IDLE, as a multiplier on that pad's own albedo. The
# rim carries more because it is the flash channel, and because a real pad's raised
# edge catches light its flat middle does not.
#
# The emission is now a FLASH channel, not a substitute for lighting.
#
# The first build set these so the pad reached a readable brightness on emission
# alone, because the board's studio left it at (24,3,11). That works as arithmetic
# and fails as a picture: a flat self-lit surface has no shading, so the pad came
# out a plain coloured blob with its veins, its dish and its rolled rim all
# invisible — which is exactly what a lit render of the same mesh shows is there
# (see LIGHTS). Emission cannot make a shape read; only light can.
#
# So the pads are LIT now, and these carry only a faint leaf-glow at idle. The
# state machine still multiplies them by 3.69x on the face and 4.68x on the rim
# for a highlight, and that step is what the player reads during playback.
const DISH_EMISSION := 0.30
const RIM_EMISSION := 0.46

# ---------------------------------------------------------------------------
# The computer's highlight, and why this pad needs its own number
# ---------------------------------------------------------------------------
# An extra multiplier on the DISH's highlight rung only — the flash the player
# reads while the computer is playing the sequence back. Idle, pressed and
# disabled are untouched, so the pad's resting look is exactly as it was.
#
# The board's own two rungs (MemoryGameUI.HIGHLIGHT_BOOST 1.42 on the face,
# HIGHLIGHT_GLOW_BOOST 1.95 on the ring) are a STOCK BUTTON's ratio, and a stock
# button is a moulded dome with a ring around it: both surfaces face the light the
# same way, so 3.69x and 4.68x read as one lit object. This pad does not. Its dish
# is a BOWL recessed inside its own rolled rim — the rim is the only part of it
# turned toward the key light — so at the board's ratio the rim flashed, the dish
# stayed where it was, and the highlight read as a glowing ring with a hole in it.
# That is the "the centre of the lily pad stays dark" defect.
#
# The number is large because the rung is not a radiance. The board writes emission
# through an sRGB round trip and this renderer uses the stored colour raw (see the
# header, and the note on MemoryGameUI._apply_emission), so a rung of k lands as
# roughly k^(1/2.2) times the light: 3.0 here is about 1.65x on the dish, which is
# why nothing clips.
#
# Measured at gameplay size on Hard with tools/lily_glow.tscn, as the dish's mean
# luminance over the rim's — 1.00 being one evenly lit pad, and the saturation of
# the worst colour (Cyan, the palest) as the cost:
#
#   lift   dish/rim, six colours        Cyan sat
#   1.00   0.69 .. 0.83   shipped: the hole, worst on Jade and Violet   0.66
#   1.95   0.79 .. 0.92   better, still visibly darker in the middle    0.61
#   3.00   0.90 .. 1.01   chosen                                        0.55
#   3.80   0.97 .. 1.08   the dish starts to OUTSHINE the rim, which    0.52
#                         turns the pad inside out
#   4.60   1.02 .. 1.14   and washes the palest two toward white        0.49
#
# 3.00 is the last value at which the rim is still the brightest part of the pad —
# which is what a lit leaf looks like and what keeps the silhouette readable —
# while nothing inside it reads as a hollow. All six colours land inside a tenth of
# each other, so no pad in the set flashes differently from its neighbours.
const HIGHLIGHT_FACE := 3.00

# The six pads' authored albedos span 2.5x — Red's brightest channel is 0.354 and
# Yellow's is 0.882 — and a colour-identification game cannot have one button four
# screen stops darker than another just because the leaf it was painted on is.
#
# Normalising it away entirely would flatten the palette the asset was authored
# with, so the emission is divided by the SQUARE ROOT of the pad's brightest
# channel instead: the spread closes from 2.5x to 1.6x, red stays the deepest pad
# and yellow the brightest, and nothing is inverted.
const NORM_POWER := 0.5

# ---------------------------------------------------------------------------
# The waterline pieces
# ---------------------------------------------------------------------------
# Both are flat annuli generated around the pad's own measured outline, in board
# units OUT from it. The meniscus is the bright lip of surface tension where the
# pad meets the water; the halo is the light the pad lays on the water, and is what
# the board's slot-1 emission channel drives.
const MENISCUS_OUT := 0.13        # how far past the outline the lip reaches
const MENISCUS_IN := 0.07         # and how far back over the pad it starts
const MENISCUS_COLOR := Color(0.62, 0.90, 0.92)
const MENISCUS_ALPHA := 0.16

const HALO_IN := 0.62             # fraction of the outline the halo starts at
const HALO_OUT := 0.46            # how far past the outline it reaches
const HALO_EMISSION := 0.20       # at idle, as a multiplier on the pad's albedo

# How high above the water each sheet lies. Small, and ordered, because they are
# transparent sheets nearly coplanar with an opaque one: the meniscus must land on
# top of the halo, and both under the board's own ground pool (which sits at
# LakeWorld.WATER_Y + MemoryGameUI.GLOW_PLANE_Y).
const HALO_LIFT := 0.004
const MENISCUS_LIFT := 0.008

# Angular resolution of the outline and of both rings. The pad's silhouette is
# smooth apart from its notch; 128 samples put the error under a pixel at gameplay
# scale and cost 3 x 128 vertices per ring.
const OUTLINE_STEPS := 128

# key -> {"surface": Mesh, "frame": Mesh}.
static var _cache: Dictionary = {}
# The pad outline, in board units by angle. One design in six colours, so this is
# measured once and shared.
static var _outline: PackedFloat32Array = PackedFloat32Array()


# Is the Magical Lake look the one currently equipped?
static func active() -> bool:
	return active_for(CoinsManager.selected_theme)


# Does a board standing on `theme_id` wear the pads? Boards ask about the background
# they are ACTUALLY standing on rather than about the wallet, because a shop card is
# the same board with a background the player has not equipped (and may not own) —
# see MemoryGameUI._wanted_background. That is what puts the pads in the Magical
# Lake card's own preview, and equally what keeps them out of every other card's.
static func active_for(theme_id: String) -> bool:
	return theme_id == THEME_ID


# The two meshes for one colour, or {} if the asset is missing — in which case the
# caller keeps the stock button rather than showing half a board.
static func build(key: String) -> Dictionary:
	if _cache.has(key):
		return _cache[key]
	if not PAD_FOR.has(key):
		return {}
	var path: String = PATH % PAD_FOR[key]
	if not ResourceLoader.exists(path):
		push_warning("LilyButtons: missing %s" % path)
		return {}
	var ps: PackedScene = load(path)
	if ps == null:
		push_warning("LilyButtons: cannot load %s" % path)
		return {}
	var root := ps.instantiate()
	var mi := _first_mesh(root)
	if mi == null or mi.mesh == null or mi.mesh.get_surface_count() < 1:
		push_warning("LilyButtons: %s has no mesh" % path)
		root.free()
		return {}
	var src: Mesh = mi.mesh
	var base := src.surface_get_material(0) as StandardMaterial3D
	if base == null:
		push_warning("LilyButtons: %s surface 0 has no StandardMaterial3D" % path)
		root.free()
		return {}

	if _outline.is_empty():
		_outline = _measure_outline(src)

	var out := {
		"surface": _split_pad(src, base),
		"frame": _waterline(base),
	}
	_cache[key] = out
	# Drop the throwaway instance; the Meshes we kept survive it, the PackedScene
	# does not.
	root.free()
	return out


# Release everything but the colours named. Called with the live board's own keys,
# so a difficulty change does not leave the previous board's meshes resident.
static func trim_cache(keep: Array) -> void:
	for key: String in _cache.keys():
		if not keep.has(key):
			_cache.erase(key)


static func _first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for c in node.get_children():
		var found := _first_mesh(c)
		if found != null:
			return found
	return null


# ---------------------------------------------------------------------------
# The pad, split into dish and rim
# ---------------------------------------------------------------------------
# One ArrayMesh, two surfaces, sharing the asset's own vertex arrays untouched —
# only the INDEX list is partitioned, by each triangle's centroid radius. So no
# vertex is moved, no normal is recomputed and no seam can open between the halves:
# they meet on shared vertices and the split is invisible until the emission
# channels are driven apart, which is when it is supposed to appear.
static func _split_pad(src: Mesh, base: StandardMaterial3D) -> ArrayMesh:
	var arrays: Array = src.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]

	var dish := PackedInt32Array()
	var rim := PackedInt32Array()
	var split_sq := RIM_SPLIT * RIM_SPLIT
	var i := 0
	while i < idx.size():
		var a := idx[i]
		var b := idx[i + 1]
		var c := idx[i + 2]
		var m: Vector3 = (verts[a] + verts[b] + verts[c]) / 3.0
		# Appended in place, both branches spelled out: a PackedInt32Array is a VALUE
		# in GDScript, so binding one to a local and appending to that would build the
		# triangle list into a copy and throw it away.
		if (m.x * m.x + m.z * m.z) >= split_sq:
			rim.append(a); rim.append(b); rim.append(c)
		else:
			dish.append(a); dish.append(b); dish.append(c)
		i += 3

	var mesh := ArrayMesh.new()
	_add_surface(mesh, arrays, dish, _pad_material(base, DISH_EMISSION))
	_add_surface(mesh, arrays, rim, _pad_material(base, RIM_EMISSION))
	return mesh


static func _add_surface(mesh: ArrayMesh, arrays: Array, idx: PackedInt32Array,
		mat: StandardMaterial3D) -> void:
	if idx.is_empty():
		# Never leave a surface out: MemoryGameUI reads slot 0 and slot 1 by number,
		# and a mesh with one surface would silently lose a channel.
		idx = PackedInt32Array([0, 0, 0])
	var a := arrays.duplicate()
	a[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	mesh.surface_set_material(mesh.get_surface_count() - 1, mat)


# One half of a pad. Everything the asset authored is kept; what is added is the
# self-lit term the board's dark studio cannot supply, expressed as a multiple of
# this pad's OWN albedo so the six colours keep exactly the relationship Blender
# gave them.
static func _pad_material(base: StandardMaterial3D, level: float) -> StandardMaterial3D:
	var m := base.duplicate() as StandardMaterial3D
	level /= _norm(base)
	# THE IMPORT FIX. Without this the "Col" attribute the whole surface design is
	# painted into is loaded, uploaded and then ignored.
	m.vertex_color_use_as_albedo = true
	m.emission_enabled = true
	m.emission_operator = BaseMaterial3D.EMISSION_OP_ADD
	# The pad's own albedo, normalised and scaled, written as the radiance to emit.
	# Not linear_to_srgb'd: see the header — Compatibility uses this colour raw.
	var c := base.albedo_color.srgb_to_linear()
	m.emission = Color(c.r * level, c.g * level, c.b * level)
	# Pinned at 1.0. The multiplier scales in sRGB and so does NOT scale the light
	# linearly (a 2.96x multiplier emits ~8.5x); everything goes in the colour.
	m.emission_energy_multiplier = 1.0
	# Mandatory on anything standing in this viewport: the board's Environment
	# carries a bright ProceduralSky as its reflection source (it is there for the
	# metallic bezels), and a leaf that mirrors it comes out grey. Same trap the 3D
	# backgrounds hit — see background_scenes.gd.
	m.disable_ambient_light = true
	return m


# ---------------------------------------------------------------------------
# Lights
# ---------------------------------------------------------------------------
# The pads bring their own lighting, and this is the largest half of making them
# read as 3D at all.
#
# The board's studio is two DirectionalLights at 0.14 and 0.05 energy whose job is
# to put a specular highlight on six small metallic bezels; a stock button is ~80%
# self-lit and needs almost nothing else. A lily pad is a diffuse leaf whose whole
# design is SHAPE — a dish, a rolled rim, a raised vein fan — and shape is only
# visible as a gradient across a lit surface. In that studio it has none, and no
# amount of emission puts it back.
#
# Measured rather than assumed: the source .blend has NO LIGHTS IN IT AT ALL (a
# 0.05 grey world and nothing else), so Blender's own render of this mesh is the
# same flat blob Godot's was. Dropping an ordinary three-point rig into that file
# turned the identical mesh into the asset it was designed as. This is that rig.
#
# Culled to BOARD_LAYER, so it lights the buttons and cannot touch the lake, and
# built ONLY while the pads are worn (see MemoryGameUI._apply_button_skin), so no
# other background or board is altered by a single count.
# SPECULAR IS KEPT LOW ON ALL THREE, and that is the difference between a lit pad
# and a grey one. A specular lobe is WHITE: it adds the same amount to all three
# channels, so on a saturated albedo it does not brighten the colour, it removes it.
# Measured on the first rig (specular 0.55/0.25/0.90): the Crimson pad rendered
# (141,129,139) — saturation 0.08, a neutral grey button in a game whose entire
# subject is telling six colours apart. The pads are matte leaves; they want the
# light's DIFFUSE and only a hint of its sheen.
const LIGHTS := [
	# key: front-upper-left and warm — the vein fan and the dish gradient are its work
	{"dir": Vector3(-2.2, 2.6, 2.4), "energy": 2.10, "color": Color(1.00, 0.96, 0.90), "spec": 0.14},
	# fill: from the right and cool, so the shaded half keeps its colour
	# Only faintly cool. A strongly blue fill is the second way to grey a saturated
	# pad out: on Crimson, whose albedo is 8x more red than green, a (0.72,0.86,1.0)
	# fill puts in exactly the two channels the button does not have.
	{"dir": Vector3(2.6, 1.2, 1.6), "energy": 0.58, "color": Color(0.90, 0.94, 1.00), "spec": 0.06},
	# rim: from behind, low — this is what separates the rolled edge from the water
	{"dir": Vector3(0.4, 1.6, -2.6), "energy": 0.80, "color": Color(0.92, 0.97, 1.00), "spec": 0.26},
]


# The rig, as loose nodes for the caller to parent and free. `cull` is the layer
# mask they may light, which is always the board's own.
static func lights(cull: int) -> Array:
	var out: Array = []
	for spec: Dictionary in LIGHTS:
		var l := DirectionalLight3D.new()
		var from: Vector3 = spec["dir"]
		l.look_at_from_position(from, Vector3(0.0, 0.10, 0.0), Vector3.UP)
		l.light_energy = float(spec["energy"])
		l.light_color = spec["color"]
		l.light_specular = float(spec["spec"])
		l.shadow_enabled = false          # six small props on a mobile GL driver
		l.light_cull_mask = cull
		out.append(l)
	return out


# How much this pad's own brightness is taken out of its emission. See NORM_POWER.
static func _norm(base: StandardMaterial3D) -> float:
	var c := base.albedo_color.srgb_to_linear()
	var peak := maxf(c.r, maxf(c.g, c.b))
	return pow(maxf(peak, 0.02), NORM_POWER)


# ---------------------------------------------------------------------------
# The waterline
# ---------------------------------------------------------------------------
# The pad's silhouette, sampled as a radius per angle. Taken from the mesh rather
# than from the builder's parameters so it stays true if the asset is ever
# re-exported, and shared across all six colours, which are one design.
static func _measure_outline(src: Mesh) -> PackedFloat32Array:
	var verts: PackedVector3Array = src.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var r := PackedFloat32Array()
	r.resize(OUTLINE_STEPS)
	for v: Vector3 in verts:
		var d := Vector2(v.x, v.z).length()
		if d <= 0.0001:
			continue
		var a := atan2(v.z, v.x)
		var b := int(floor((a + PI) / TAU * float(OUTLINE_STEPS))) % OUTLINE_STEPS
		if d > r[b]:
			r[b] = d
	# The notch leaves one or two bins with nothing in them at all; carry the last
	# real radius across rather than collapsing the ring to the origin there.
	var last := 0.0
	for i in OUTLINE_STEPS:
		if r[i] > 0.0:
			last = r[i]
	for i in OUTLINE_STEPS:
		if r[i] <= 0.0:
			r[i] = last
		else:
			last = r[i]
	return r


# The two flat sheets that live at the waterline, as one two-surface mesh for the
# board's stationary Frame node. Surface 0 is the meniscus, surface 1 the halo —
# the same slot meanings the stock frame has, which is what lets the emission state
# machine drive the halo without knowing any of this.
static func _waterline(base: StandardMaterial3D) -> ArrayMesh:
	var mesh := ArrayMesh.new()

	var men := _annulus(1.0, MENISCUS_IN, MENISCUS_OUT, 0.0, LAKE.WATER_Y + MENISCUS_LIFT)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, men)
	mesh.surface_set_material(0, _meniscus_material())

	var halo := _annulus(HALO_IN, 0.0, HALO_OUT, 0.45, LAKE.WATER_Y + HALO_LIFT)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, halo)
	mesh.surface_set_material(1, _halo_material(base))
	return mesh


# A flat ring following the pad's outline. The inner loop sits at
# `base_r * in_scale - in_off` and the outer one `out` metres past the outline, so
# one generator serves a lip that hugs the edge (scale 1, a small inset) and a halo
# that starts well inside the pad (scale 0.55) and spreads onto the water.
#
# Three concentric loops, so the alpha can ramp up at the inner edge and back down
# at the outer one and the sheet has no visible border anywhere. `mid` is where the
# peak sits between the two, as a fraction of `out` past the outline: on the outline
# for the lip, a little outside it for the halo, which is where a pad's light
# actually pools on the water.
#
# The alpha profile is carried in the vertex COLOUR. Both materials read it through
# vertex_color_use_as_albedo, which multiplies alpha as well as colour.
static func _annulus(in_scale: float, in_off: float, out: float, mid: float, y: float) -> Array:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var n := OUTLINE_STEPS
	var profile := [0.0, 1.0, 0.0]
	for ring in 3:
		for i in n:
			var a := -PI + TAU * (float(i) + 0.5) / float(n)
			var base_r: float = _outline[i]
			var r := base_r
			match ring:
				0: r = maxf(base_r * in_scale - in_off, 0.02)
				1: r = base_r + mid * out
				2: r = base_r + out
			verts.append(Vector3(cos(a) * r, y, sin(a) * r))
			norms.append(Vector3.UP)
			cols.append(Color(1.0, 1.0, 1.0, profile[ring]))
	for ring in 2:
		for i in n:
			var j := (i + 1) % n
			var a0 := ring * n + i
			var a1 := ring * n + j
			var b0 := (ring + 1) * n + i
			var b1 := (ring + 1) * n + j
			idx.append_array([a0, b0, b1, a0, b1, a1])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	return arrays


# The bright lip of surface tension. Unshaded on purpose — it is a highlight on
# water, not a lit object, and the board's studio would leave it black.
static func _meniscus_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(MENISCUS_COLOR.r, MENISCUS_COLOR.g, MENISCUS_COLOR.b, MENISCUS_ALPHA)
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.disable_receive_shadows = true
	m.render_priority = 1
	return m


# The light the pad lays on the water. This is the board's slot-1 under-glow
# channel: MemoryGameUI takes its emission as `_glow_base` and drives it through
# idle / highlight / pressed / disabled, so the halo brightens with the flash and
# the pool the button throws, without a line of code here knowing that.
static func _halo_material(base: StandardMaterial3D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var c := base.albedo_color.srgb_to_linear()
	m.albedo_color = Color(0, 0, 0, 1)
	m.vertex_color_use_as_albedo = true
	m.emission_enabled = true
	m.emission = Color(c.r, c.g, c.b) * (HALO_EMISSION / _norm(base))
	m.emission_energy_multiplier = 1.0
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	m.disable_ambient_light = true
	m.render_priority = 0
	return m
