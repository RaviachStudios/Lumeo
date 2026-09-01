extends RefCounted
class_name ChipButtons

# The ROYAL CASINO gameplay buttons — a moulded poker chip lying on the felt, which
# is what replaces the stock disc-in-a-black-bezel while `world_casino` is the
# equipped 3D background.
#
# The chips themselves are authored in Blender (APP IDEAS/Simon/Skins/Chips/Chips.blend,
# rebuildable from pokerchip_builder.py beside it) and ship as one .glb per colour in
# res://models/buttons/. NOTHING here remodels one: the chip arrives with its domed
# medallion, its inlay field, its inner ring, its groove, its eight edge inserts and
# its rolled edge intact, and is used exactly as it was authored. Its geometry is not
# touched, not split, not scaled and not re-origined.
#
# ---------------------------------------------------------------------------
# The same mesh swap the snowflakes and the lily pads are
# ---------------------------------------------------------------------------
# Like ice_buttons.gd and lily_buttons.gd this is a MESH SWAP on the board's OWN
# MeshInstance3D nodes (see MemoryGameUI._apply_button_skin). The nodes stay, so the
# `Press_<Key>` clips, the emission state machine, the Area3D hit-testing, the
# spacing, the camera fit, the ground pools and the render cadence all keep working
# untouched, and nothing in game.gd or the level system is aware it happened.
#
# ---------------------------------------------------------------------------
# The contract, and the one place this asset is luckier than the lily pad
# ---------------------------------------------------------------------------
# A stock button is TWO meshes, each with TWO surfaces:
#
#   stock   Button_<Key>_Surface   y 0.245 -> 0.525   slot 0 face,  slot 1 rim ring
#           Button_<Key>_Frame     y 0.000 -> 0.303   slot 0 metal, slot 1 under-glow
#   chip    PokerChip_Button_Mesh  y 0.000 -> 0.324   slot 0 body,  slot 1 accent
#
# The chip was built to the stock FOOTPRINT (radius 0.992 against the frame's 1.000,
# origin at the centre of its base, identity node transform), and — unlike the pad —
# it already ships with the two surfaces the board's emission machine wants, in the
# two slots it wants them in. So there is no split here at all: the surfaces are the
# builder's own, and only their MATERIALS are re-authored.
#
# What still has to be met is the second mesh. A chip has no bezel and must not grow
# one, so the FRAME NODE BECOMES THE CHIP'S CONTACT WITH THE FELT — the two things
# that only make sense on the table and only make sense if they DON'T move with the
# press:
#
#   surface 0   the contact shadow, a soft dark ring hugging the chip's edge
#   surface 1   the coloured light the chip lays on the felt
#
# Both are flat sheets on the table plane, and the frame node is the one the press
# clip never touches — so a pressed chip sinks INTO its own shadow and leaves it
# where it was, which is the whole "this object is resting on that surface" read.
# Surface 1 is also the board's slot-1 under-glow channel, so the halo brightens
# with the flash and with the pool the button throws, without a line here knowing.
#
# ---------------------------------------------------------------------------
# The glTF import trap, met for the third time
# ---------------------------------------------------------------------------
# COLOR_0 IS DISCARDED. The builder paints the chip's moulded shading — the recesses
# reading deep, the rolled edge and the medallion reading light — into a POINT colour
# attribute wired as MULTIPLY(flat colour, Col) into Base Color, which is exactly
# glTF's COLOR_0 semantics. Godot's importer leaves `vertex_color_use_as_albedo`
# FALSE on the body, so all of it is dropped and the chip renders as one flat disc
# of `baseColorFactor`. (Measured: slot 1 comes in with the flag TRUE and slot 0
# with it FALSE, from the same mesh — so this cannot be left to the importer even
# once it has been seen to work on one surface.) Turning it on is the whole fix;
# nothing about the asset changes. See [[glb-import-shading-pipeline]].
#
# ---------------------------------------------------------------------------
# Cosmetic bezels are suppressed while chips are worn
# ---------------------------------------------------------------------------
# Same reason ice and the pads suppress them (MemoryGameUI._refresh_frame): the
# eighteen shop frames are a lathe built for the stock disc, and wearing one covers
# the frame mesh's surface 0 — which here is the contact shadow.

# The 3D-background id this look belongs to. Ownership, price, purchase and equip are
# CoinsManager.THEMES and `selected_theme` — see CasinoWorld.CATALOG.
const THEME_ID := "world_casino"

# This look needs the board's viewport anti-aliased (see MemoryGameUI._antialias_for).
# The chip's silhouette is a clean circle, which is the case MSAA matters least for —
# but it stands on a BRIGHT green felt rather than over near-black, so the stair-step
# along its edge is a full-contrast one, and the eight edge inserts put eight more
# high-contrast boundaries across the rolled edge of every button.
const WANTS_AA := true

# ---------------------------------------------------------------------------
# Press travel
# ---------------------------------------------------------------------------
# How much of the board's own press stroke a chip takes. The GLB's Press_<Key> clip
# sinks a button 115 mm, which is the stroke of a moulded plastic dome dropping into
# its housing, and much too far for a chip lying on a table: the chip is only 324 mm
# tall, so the full stroke would push 35 % of it THROUGH the felt and read as the
# table swallowing it.
#
# The felt does give — that is what makes a chip press feel physical rather than
# like a sprite scaling — so the answer is not zero either.
#
#   scale   travel    of the chip's height   what it reads as
#   1.00    -0.115           35 %            the chip sinking into the table
#   0.34    -0.039           12 %            chosen: pressed into the felt, and
#                                            still clearly the same object
#   0.15    -0.017            5 %            no press at all next to its neighbours
#
# The board's own timing, easing and the small overshoot on the way back are all
# untouched — only the amplitude is scaled, so a chip press stays exactly as quick
# and as responsive as every other button's.
const PRESS_SCALE := 0.34

# Opt out of the board's Jade->deep-emerald correction (MemoryGameUI._recolour_jade),
# which replaces one button's albedo outright with JADE_TARGET. See the note there
# for why this asset is not a candidate for it.
const RECOLOUR_JADE := false

const PATH := "res://models/buttons/PokerChip_%s.glb"

# Board colour key -> the chip colour authored for it. The board's keys are the GLB's
# node names and are not ours to rename; the chips were authored to the same six
# colours the lily pads were, so this is where the two vocabularies meet.
#
# "Amber" and "Yellow" both take the yellow chip: Medium and Hard key their third
# button Amber (an orange-gold) and EASY keys its own third button Yellow. A casino
# chip set has one gold denomination, not two.
const CHIP_FOR := {
	"Crimson": "Red",
	"Jade":    "Green",
	"Cyan":    "Cyan",
	"Amber":   "Yellow",
	"Violet":  "Purple",
	"Magenta": "Pink",
	"Yellow":  "Yellow",
}

# ---------------------------------------------------------------------------
# Emission
# ---------------------------------------------------------------------------
# How bright each surface sits at IDLE, as a multiplier on the CHIP BODY's own
# albedo. These are a FLASH channel and not a substitute for lighting: the chip is a
# dense moulded solid whose entire design is shape (a domed medallion, a recessed
# inlay, a raised ring, a groove, eight inserts cut through a rolled edge), and shape
# is only visible as a gradient across a LIT surface. See LIGHTS below, which is the
# larger half of making this asset read at all.
# ---------------------------------------------------------------------------
# THESE TWO AND THE LIGHT RIG ARE ONE DECISION, AND IT IS MEASURED
# ---------------------------------------------------------------------------
# The first pass set them to 0.22 / 0.34 against a rig four times hotter than this
# one, and the pair FAILED THE ONE TEST THAT MATTERS: at gameplay size, lighting the
# highlight rung moved a chip by ONE COUNT (230,140,183 -> 231,141,185). A button
# whose flash cannot be seen is not a button.
#
# The reason is structural rather than a matter of degree, and it is worth knowing
# before touching either number again:
#
#   * the board writes emission through an sRGB round trip and this renderer uses the
#     stored colour RAW, so a highlight rung of k lands as about k^(1/2.4) of the
#     idle emission — even k = 5 is only 1.9x. Sweeping HIGHLIGHT_FACE from 1.00 to
#     4.60 moved the worst chip's step from +0.013 to +0.069 and no further.
#   * so the SIZE of the flash is set almost entirely by HOW MUCH OF THE IDLE PIXEL
#     IS EMISSION rather than light. At the old rig it was about a fifth, and 1.9x of
#     a fifth is nothing.
#
# tools/chip_glow.tscn sweeps the rig's energy against the emission base and prints
# both against the STOCK BUTTON's own step, which is the number every player of this
# game has already learned to read (idle luminance 0.22..0.60, step +0.178, worst
# highlight saturation 0.25):
#
#   rig    emit    idle lum       worst STEP   worst hi sat
#   1.00    1.0    0.32 .. 0.66     +0.018        0.40      shipped first: invisible
#   1.00    6.0    0.36 .. 0.70     +0.091        0.31
#   1.00   20.0    0.44 .. 0.76     +0.135        0.18      bright, and washed out
#   0.50   20.0    0.37 .. 0.71     +0.179        0.20      the stock step exactly
#   0.25    6.0    0.22 .. 0.52     +0.144        0.41      the stock idle exactly
#   0.25   20.0    0.31 .. 0.67     +0.211        0.21      more flash than stock
#   0.25   50.0    0.46 .. 0.80     +0.150        0.10      the flash eats the colour
#
# That first pass landed on rig 0.28 / emission 11 — and it was WRONG for a reason
# the numbers above cannot show, which is why the render is part of the method:
# with the accent glowing harder than the body (RING_EMISSION was 1.36 for that
# render) the ivory inserts took the chip's own hue, the medallion's dome and the
# groove went flat, and a poker chip became a lit disc. See RING_EMISSION.
#
# So the accent came down, the key light went back up (relief is the key's job), and
# the sweep was re-run around THAT shape:
#
#   rig    emit    idle lum       worst STEP   worst hi sat
#   1.00    1.0    0.24 .. 0.57     +0.109        0.39      relief back, flash short
#   1.00    2.0    0.27 .. 0.64     +0.188        0.28      CHOSEN
#   1.00    3.5    0.31 .. 0.70     +0.191        0.20      no more step, less colour
#   0.70    2.0    0.24 .. 0.61     +0.202        0.29      dimmer, at the cost of relief
#
# SHIPPED: idle luminance 0.27 - 0.64 against the stock button's 0.22 - 0.60, a worst
# step of +0.188 against its +0.178, and 0.28 of saturation left at highlight against
# its 0.25. The chips flash as hard as the buttons this game was built around and
# hold their colour slightly better while doing it.
#
# The `emit 2.0` of that row is 2^(1/2.4) = 1.335 on the authored level, which is
# where the three numbers below come from.
const BODY_EMISSION := 1.07
# ...and THE ACCENT SITS BELOW THE BODY, not above it. It was 1.36 for one render and
# that render is what settled this: at a higher idle glow than the body's, the ivory
# inserts on Purple, Red and Pink took the chip's own hue and stopped being ivory,
# and the whole face flattened into one lit disc with no inserts in it. The board
# already lifts the ring HARDER than the face at highlight (HIGHLIGHT_GLOW_BOOST 1.95
# against the face's 1.42), so the flash does not need a head start at rest — what it
# needs at rest is for the inserts to still read as inserts.
const RING_EMISSION := 0.73

# ...and THE ACCENT'S EMISSION IS DERIVED FROM THE BODY'S ALBEDO, NOT ITS OWN.
#
# This is the one place a chip is not simply used as authored, and it is forced by
# the asset's best idea. A real chip set picks its insert colour per denomination —
# light chips get dark inserts, dark chips get ivory ones — and this one does too
# (pokerchip_builder.LUM_SPLIT): Purple, Red and Pink carry warm ivory inserts,
# Green, Cyan and Yellow carry a deep tint of their own hue. That is correct for the
# ALBEDO and it is what makes the chips look like a set.
#
# It is wrong for EMISSION, because slot 1 is the channel the game FLASHES. Derived
# from each accent's own colour, three chips would flash ivory-white and three would
# flash a dark muddy version of themselves — six buttons whose whole job is to be
# told apart, flashing in two colours that are not theirs. So the accent keeps its
# authored albedo exactly and takes the BUTTON'S colour as its glow, and all six
# chips flash the colour the player is being asked to remember.
#
# It also reads correctly at rest: an ivory insert with a faint purple bloom in it
# is an ivory insert catching the light of the chip around it.

# The light a chip lays on the felt around itself, on the same footing.
# The felt halo is deliberately NOT raised by the full 2.72: it is a wash on a bright
# surface rather than a light on a dark one, and at the chips' own factor six of them
# meet in the middle of the board and fog the cloth.
const HALO_EMISSION := 0.36

# ---------------------------------------------------------------------------
# The computer's highlight
# ---------------------------------------------------------------------------
# An extra multiplier on the BODY's highlight rung only — the flash the player reads
# while the computer is playing the sequence back. Idle, pressed and disabled are
# untouched.
#
# The board's own rungs (MemoryGameUI.HIGHLIGHT_BOOST 1.42 on the face,
# HIGHLIGHT_GLOW_BOOST 1.95 on the ring) are a stock button's ratio, and the pad
# needed 3.00 on top of them because its two surfaces are a bowl inside a rim and
# face the light differently. A CHIP'S TWO SURFACES ARE COPLANAR — the inserts, the
# inner ring and the groove floor are cut into the same flat face the body presents —
# so the stock ratio reads as one lit object here and no correction of that kind is
# needed.
#
# What it does need is a small lift for the GROUND it stands on. Every board before
# this one was near-black behind the buttons; green felt is not, so a flash that was
# a clear step against black is a smaller step against this.
#
# IT IS ALSO NOT THE KNOB THAT MADE THE FLASH VISIBLE, and that is worth recording
# because it is the obvious place to reach first. Sweeping it from 1.00 to 4.60
# (tools/chip_glow.tscn) moved the worst chip's step from +0.013 to +0.069, against a
# stock button's +0.178 — the emission is written through an sRGB round trip, so a
# rung of k is only about k^(1/2.4). What fixed it was the balance between the light
# rig and BODY_EMISSION; see the table there. 1.35 is a modest final trim on top of
# that, and is deliberately far below the lily pad's 3.00, because the failure mode
# here is a white chip rather than a dark middle.
const HIGHLIGHT_FACE := 1.35

# The six chips' authored albedos span 2.58x at the brightest channel in linear
# light — the same order as the lily pads' 2.5x — and a colour-identification game
# cannot have one button two and a half stops darker than another because of the
# plastic it was moulded from. Same correction as the pads: divide by the SQUARE ROOT
# of the brightest channel, which closes the spread to 1.61x, keeps Red the deepest
# chip and Cyan the brightest, and inverts nothing.
const NORM_POWER := 0.5

# ---------------------------------------------------------------------------
# The felt contact
# ---------------------------------------------------------------------------
# Both pieces are flat rings around the chip's own measured radius, in board units
# out from it.
#
# THE SHADOW IS THE PIECE THAT MAKES THE CHIP SIT ON THE TABLE. A chip is a low
# cylinder seen from a shallow angle; without an occlusion contact under it, it
# reads as a coin hovering a few centimetres over the felt, and every casino event
# that slides a card across the same surface then reads as being on a different
# plane from the buttons.
const SHADOW_IN := 0.52           # fraction of the chip's radius the ring starts at
const SHADOW_OUT := 0.30          # how far past the chip's edge it reaches
const SHADOW_MID := 0.02          # where the darkest part sits, past the edge
const SHADOW_COLOR := Color(0.016, 0.055, 0.035)   # the felt's own deep shade
const SHADOW_ALPHA := 0.62

const HALO_IN := 0.66             # fraction of the chip's radius the halo starts at
const HALO_OUT := 0.52            # how far past the edge it reaches
const HALO_MID := 0.34            # ...and where its peak sits, well outside the chip

# How high above the felt each sheet lies. Small, and ORDERED, because they are two
# transparent sheets nearly coplanar with an opaque one — and both must stay under
# the board's own ground pool, which sits at MemoryGameUI.GLOW_PLANE_Y (0.012).
const SHADOW_LIFT := 0.004
const HALO_LIFT := 0.008

# Angular resolution of both rings. The chip's silhouette is a circle broken only by
# eight 0.8 %-deep insert recesses, so this is plenty: 96 samples put the error well
# under a pixel at gameplay scale and cost 3 x 96 vertices per ring.
const RING_STEPS := 96

# key -> {"surface": Mesh, "frame": Mesh}.
static var _cache: Dictionary = {}
# The chip's radius, measured once off the asset and shared: one design, six colours.
static var _radius := 0.0


# Is the Royal Casino look the one currently equipped?
static func active() -> bool:
	return active_for(CoinsManager.selected_theme)


# Does a board standing on `theme_id` wear the chips? Boards ask about the background
# they are ACTUALLY standing on rather than about the wallet, because a shop card is
# the same board with a background the player has not equipped (and may not own) —
# see MemoryGameUI._wanted_background. That is what puts the chips in the Royal
# Casino card's own preview, and equally what keeps them out of every other card's.
static func active_for(theme_id: String) -> bool:
	return theme_id == THEME_ID


# The two meshes for one colour, or {} if the asset is missing — in which case the
# caller keeps the stock button rather than showing half a board.
static func build(key: String) -> Dictionary:
	if _cache.has(key):
		return _cache[key]
	if not CHIP_FOR.has(key):
		return {}
	var path: String = PATH % CHIP_FOR[key]
	if not ResourceLoader.exists(path):
		push_warning("ChipButtons: missing %s" % path)
		return {}
	var ps: PackedScene = load(path)
	if ps == null:
		push_warning("ChipButtons: cannot load %s" % path)
		return {}
	var root := ps.instantiate()
	var mi := _first_mesh(root)
	if mi == null or mi.mesh == null or mi.mesh.get_surface_count() < 2:
		push_warning("ChipButtons: %s does not carry two surfaces" % path)
		root.free()
		return {}
	var src: Mesh = mi.mesh
	var body := src.surface_get_material(0) as StandardMaterial3D
	var accent := src.surface_get_material(1) as StandardMaterial3D
	if body == null or accent == null:
		push_warning("ChipButtons: %s is missing a StandardMaterial3D" % path)
		root.free()
		return {}

	if _radius <= 0.0:
		_radius = _measure_radius(src)

	var out := {
		"surface": _chip(src, body, accent),
		"frame": _contact(body),
	}
	_cache[key] = out
	# Drop the throwaway instance; the Meshes we kept survive it, the PackedScene
	# does not.
	root.free()
	return out


# Release everything but the colours named. Called with the live board's own keys, so
# a difficulty change does not leave the previous board's meshes resident.
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
# The chip
# ---------------------------------------------------------------------------
# One ArrayMesh carrying the asset's own two surfaces, vertex for vertex and index
# for index. Nothing is partitioned, moved or recomputed — the only thing that
# changes is which material each surface wears, and a new ArrayMesh is built rather
# than the imported one re-materialised because that Mesh is a shared sub-resource of
# the PackedScene and every other instance of it would take the change too.
static func _chip(src: Mesh, body: StandardMaterial3D,
		accent: StandardMaterial3D) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, src.surface_get_arrays(0))
	mesh.surface_set_material(0, _chip_material(body, body, BODY_EMISSION))
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, src.surface_get_arrays(1))
	# `body` twice on purpose: the accent keeps its own albedo and takes the BUTTON's
	# colour as its glow. See the note above RING_EMISSION.
	mesh.surface_set_material(1, _chip_material(accent, body, RING_EMISSION))
	return mesh


# One surface of a chip. Everything the asset authored is kept; what is added is the
# self-lit term the board's dark studio cannot supply, expressed as a multiple of the
# CHIP BODY's albedo so the six colours keep the relationship Blender gave them.
static func _chip_material(base: StandardMaterial3D, hue: StandardMaterial3D,
		level: float) -> StandardMaterial3D:
	var m := base.duplicate() as StandardMaterial3D
	level /= _norm(hue)
	# THE IMPORT FIX. Without this the "Col" attribute the whole moulded surface
	# design is painted into is loaded, uploaded and then ignored.
	m.vertex_color_use_as_albedo = true
	m.emission_enabled = true
	# EMISSION_OP_MULTIPLY renders BLACK under this project's GL Compatibility
	# renderer, silently, at every level and with any albedo (measured with
	# tools/emis_probe.tscn — see lily_buttons.gd's header). ADD is the only operator
	# that emits anything here.
	m.emission_operator = BaseMaterial3D.EMISSION_OP_ADD
	# Written as the radiance to emit, NOT linear_to_srgb'd: Compatibility applies no
	# conversion to the emission colour and uses whatever number is stored raw.
	var c := hue.albedo_color.srgb_to_linear()
	m.emission = Color(c.r * level, c.g * level, c.b * level)
	# Pinned at 1.0. The multiplier scales in sRGB and so does NOT scale the light
	# linearly (a 2.96x multiplier emits ~8.5x); everything goes in the colour.
	m.emission_energy_multiplier = 1.0
	# Mandatory on anything standing in this viewport: the board's Environment carries
	# a bright ProceduralSky as its reflection source (it is there for the metallic
	# bezels), and a satin-coated chip that mirrors it comes out grey.
	m.disable_ambient_light = true
	return m


# How much this chip's own brightness is taken out of its emission. See NORM_POWER.
static func _norm(base: StandardMaterial3D) -> float:
	var c := base.albedo_color.srgb_to_linear()
	var peak := maxf(c.r, maxf(c.g, c.b))
	return pow(maxf(peak, 0.02), NORM_POWER)


# The chip's silhouette radius, taken from the mesh rather than from the builder's
# parameters so it stays true if the asset is ever re-exported.
static func _measure_radius(src: Mesh) -> float:
	var verts: PackedVector3Array = src.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var r := 0.0
	for v: Vector3 in verts:
		r = maxf(r, Vector2(v.x, v.z).length())
	# The accent surface carries the outermost band of the rolled edge on some
	# angles (the inserts are cut through it), so both are measured.
	verts = src.surface_get_arrays(1)[Mesh.ARRAY_VERTEX]
	for v: Vector3 in verts:
		r = maxf(r, Vector2(v.x, v.z).length())
	return maxf(r, 0.1)


# ---------------------------------------------------------------------------
# The felt contact
# ---------------------------------------------------------------------------
static func _contact(body: StandardMaterial3D) -> ArrayMesh:
	var mesh := ArrayMesh.new()

	var shade := _ring(SHADOW_IN, SHADOW_OUT, SHADOW_MID, SHADOW_LIFT)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, shade)
	mesh.surface_set_material(0, _shadow_material())

	var halo := _ring(HALO_IN, HALO_OUT, HALO_MID, HALO_LIFT)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, halo)
	mesh.surface_set_material(1, _halo_material(body))
	return mesh


# A flat ring around the chip. Three concentric loops, so the alpha can ramp up at
# the inner edge and back down at the outer one and the sheet has no visible border
# anywhere; `mid` is where the peak sits, as a fraction of `out` past the chip's
# edge. The alpha profile is carried in the vertex COLOUR, which both materials read
# through vertex_color_use_as_albedo (it multiplies alpha as well as colour).
static func _ring(in_scale: float, out: float, mid: float, y: float) -> Array:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var n := RING_STEPS
	var profile := [0.0, 1.0, 0.0]
	var radii := [maxf(_radius * in_scale, 0.02), _radius + mid * out, _radius + out]
	for ring in 3:
		var r: float = radii[ring]
		for i in n:
			var a := -PI + TAU * (float(i) + 0.5) / float(n)
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


# The contact shadow. MIX rather than ADD, because a shadow has to SUBTRACT light
# from the felt — an additive black sheet is a no-op and was the first version of
# this. Unshaded, because it is an occlusion term and not a lit object.
static func _shadow_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(SHADOW_COLOR.r, SHADOW_COLOR.g, SHADOW_COLOR.b, SHADOW_ALPHA)
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	m.disable_ambient_light = true
	# Between the board's ground-pool sheet (GLOW_PRIORITY -2) and the halo, so the
	# three transparent sheets on this plane always sort the same way.
	m.render_priority = -1
	return m


# The light the chip lays on the felt. This is the board's slot-1 under-glow channel:
# MemoryGameUI takes its emission as `_glow_base` and drives it through
# idle / highlight / pressed / disabled, so the halo brightens with the flash and
# with the pool the button throws, without a line of code here knowing that.
static func _halo_material(body: StandardMaterial3D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var c := body.albedo_color.srgb_to_linear()
	m.albedo_color = Color(0, 0, 0, 1)
	m.vertex_color_use_as_albedo = true
	m.emission_enabled = true
	m.emission = Color(c.r, c.g, c.b) * (HALO_EMISSION / _norm(body))
	m.emission_energy_multiplier = 1.0
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	m.disable_ambient_light = true
	m.render_priority = 0
	return m


# ---------------------------------------------------------------------------
# Lights
# ---------------------------------------------------------------------------
# The chips bring their own lighting, and this is the larger half of making them read
# as 3D at all.
#
# The board's studio is two DirectionalLights at 0.14 and 0.05 energy whose entire
# job is a specular highlight on six small metallic bezels; a stock button is ~80 %
# self-lit and needs almost nothing else. A poker chip is a dense moulded solid with
# a matte-satin finish whose whole design is RELIEF — a domed medallion 24 mm proud,
# a recessed inlay, a raised inner ring, a groove, eight inserts cut through a rolled
# edge — and relief is only visible as a gradient across a lit surface. In that
# studio it has none, and no amount of emission puts it back.
#
# THESE ARE OMNI LIGHTS AND NOT A THREE-POINT DIRECTIONAL RIG, and that is measured
# rather than stylistic: this project's renderer lights an object with EXACTLY ONE
# DirectionalLight3D, and the board already has one. Adding directionals produces a
# byte-identical render, silently, at any energy. See ice_buttons.gd's block on this,
# which is the general finding. So the rig is omnis placed far out (11-14 units,
# against a board 4.3 across) with a range far past the board, which makes their
# falloff across it a few per cent — a directional light in all but name, and one the
# renderer will actually draw.
#
# The rig is culled to BOARD_LAYER exactly as the studio is, so it lights the buttons
# and cannot reach the table behind them, and it exists ONLY while the chips are worn
# (MemoryGameUI._light_skin) — no other background or board moves by a single count.
#
# SPECULAR IS THE KNOB THAT MUST STAY MODEST. A specular lobe is WHITE: it adds the
# same amount to all three channels, so on a saturated albedo it does not brighten
# the colour, it removes it. The chip is roughness 0.52 under a light clear coat —
# satin, not gloss — so it is allowed a little more than a matte lily pad and a good
# deal less than a facet of ice, and what it is allowed is spent on the RIM light,
# which grazes the rolled edge where a real chip catches the room.
const RANGE := 48.0            # far past the board, so the falloff across it is flat
const ATTENUATION := 0.30
# THE RIG IS A THIRD OF THE ICE FLAKES', AND THAT IS ABOUT ALBEDO AND HEADROOM.
# A snowflake is a dark, deeply-shadowed carving; a poker chip is a saturated
# moulding whose brightest channel is 0.63 - 0.96 in linear light. At the flakes'
# energies the chips rendered at luminance 0.55 - 0.80 with the saturation squeezed
# out of them (Cyan came out 0.26), and — the reason this had to change rather than
# being a taste call — they sat so far up the tone curve's shoulder that THE
# HIGHLIGHT COULD NOT BE SEEN. The flash is the game.
#
# The rule this settles, and the one to keep if these are ever re-tuned: LIGHT A SKIN
# TO ABOUT THE MIDDLE OF THE CURVE AND LEAVE THE TOP THIRD OF IT FOR THE EMISSION THE
# STATE MACHINE DRIVES. Bright is not the goal; HEADROOM is. See the table above
# BODY_EMISSION for the sweep this came out of.
#
# It is still enough light to be the majority of an idle chip, which is what the rig
# is FOR — the medallion's dome, the inlay's shade and the groove are gradients, and
# a gradient needs light. Measured: at this rig and no emission at all the chips
# still render at luminance 0.16 - 0.42, with all their relief.
const LIGHTS := [
	# key: the overhead table lamp, high and slightly forward-left. This is the one
	# that puts a direction on the chip — the medallion domes, the inlay field falls
	# into shade, and the groove reads as a groove.
	# The key is 1.6x the other two's share of the cut, and deliberately: brightness
	# is what had to come down, but the GRADIENT is what makes the medallion a dome
	# and the groove a groove, and the gradient is this light's alone.
	{"pos": Vector3(-5.0, 12.0, 7.0), "energy": 1.85, "color": Color(1.00, 0.95, 0.86), "spec": 0.15},
	# fill: from the right, cool and weak, so the shaded half keeps its colour.
	# Only FAINTLY cool — a strongly blue fill is the second way to grey a saturated
	# chip out: on Red, whose albedo is nearly 3x more red than green, a
	# (0.72,0.86,1.0) fill puts in exactly the two channels the button does not have.
	{"pos": Vector3(10.0, 5.0, 5.5), "energy": 0.30, "color": Color(0.92, 0.95, 1.00), "spec": 0.07},
	# rim: from behind and low, warm. This one carries the satin sheen along the
	# rolled edge, and is what separates a chip's silhouette from the green felt it is
	# lying on — the boundary the contact shadow makes dark, this makes bright.
	{"pos": Vector3(1.5, 3.2, -11.0), "energy": 0.59, "color": Color(1.00, 0.92, 0.78), "spec": 0.34},
]


# The rig, as loose nodes for the caller to parent and free. `cull` is the layer mask
# they may light, which is always the board's own.
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
