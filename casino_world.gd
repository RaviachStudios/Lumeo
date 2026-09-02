extends Node3D
class_name CasinoWorld

# ROYAL CASINO — the poker table the six chip buttons (chip_buttons.gd) are lying
# on, and the stage every casino event is played out across.
#
# `world_casino`. The fourth kind of 3D background in this project and the second
# with no imported asset behind it at all: a plane, a shader and a scatter of
# generated props, exactly as the Magical Lake is. BackgroundScenes stays the single
# façade for all of them; adding this one was a CATALOG entry plus forwarding lines.
#
# ---------------------------------------------------------------------------
# What is here and what is next door
# ---------------------------------------------------------------------------
#   casino_world.gd   the table: felt, lamp pool, betting arc, rail, dressing
#   casino_events.gd  everything that HAPPENS on it (see CasinoEvents)
#   chip_buttons.gd   the six poker chips, worn as gameplay buttons
#
# The split is deliberate. This file answers "what does the table look like"; the
# events file answers "what just happened on it", owns its own node, its own clock
# and its own budget, and can be read without the felt shader in the way. The two
# meet at exactly three points: `EventsRoot` is a child of this node, this node
# forwards it the board layout, and this node's `_process` ticks it.
#
# ---------------------------------------------------------------------------
# THE ONE NUMBER THIS BACKGROUND IS BUILT AROUND: y = 0 IS THE FELT
# ---------------------------------------------------------------------------
# The chip asset puts the origin at the centre of its BASE, so a chip standing on
# the board plane is a chip lying on the table — there is nothing to reconcile, no
# waterline to derive and no deck to lift onto. `pool_plane_y` therefore answers 0.0
# (the board's own default) and the coloured ground pools land on the felt for free.
#
# Everything the events place — a card sliding in, a chip cascading, the roulette
# ball's track — is placed at CARD_Y / small offsets above that same zero, which is
# why they all read as being on ONE surface with the buttons.
#
# ---------------------------------------------------------------------------
# THE PALETTE IS AUTHORED ON SCREEN AND SOLVED BACKWARDS
# ---------------------------------------------------------------------------
# The board's Environment tonemaps through AgX at exposure 0.40, which has an
# enormous toe (screen count 4 needs a linear 0.100) and clips from about 4.5.
# Authoring "a casino green in linear" gives black or bleach. So every colour below
# is written as the sRGB the player is meant to SEE and `tone()` converts it, once,
# at build time, through the MEASURED ramp — see LakeWorld's block on this, and
# regenerate with tools/lake_tone.tscn if the board's Environment ever changes.
#
# The corollary that costs a pass if forgotten: A FRACTION OF A SOLVED COLOUR IS NOT
# A DARKER VERSION OF IT. Every shader here mixes between two solved colours rather
# than scaling one, so the shading rides between two points somebody chose instead of
# falling off the bottom of the transform.

# The visual layer a background occupies. Declared again rather than imported so the
# dependency between the modules stays strictly one-way (BackgroundScenes -> here).
const BG_LAYER := 2

# ---------------------------------------------------------------------------
# Catalog
# ---------------------------------------------------------------------------
# The "world_" prefix is the one the Themes2 worlds established. This id is what
# saved wallets contain, so it is frozen once shipped — and it is deliberately NOT
# "casino", which has been spent since launch on the JACKPOT wheel skin
# (CoinsManager.THEMES has no entry for it; simon_wheel.gd and background_manager.gd
# both key off `_skin_id == "casino"`). Two different products, two ids.
const CATALOG := {
	"world_casino": {"name": "Royal Casino"},
}

const ORDER := ["world_casino"]

# The felt plane is two triangles and its cost is per-pixel, so it is sized to run
# past the frame at every aspect on every board with nothing to think about.
const FELT_SIZE := 90.0

# How high a card, a loose chip or anything else the events lay ON the table sits.
# One number, shared with CasinoEvents, so nothing on this table is ever on a
# different plane from anything else.
const CARD_Y := 0.011

# How tall a chip button stands, from the asset (chip_buttons.gd's contract note).
# Used to ask where the TOP of the highest button lands on screen, which is what the
# arc and the rail have to clear.
const CHIP_TOP := 0.324

# ---------------------------------------------------------------------------
# Palette, as sRGB on screen
# ---------------------------------------------------------------------------
# A casino green that is rich rather than garish, lit by one warm overhead lamp and
# falling into the dark of the room. Three solved greens and nothing between them
# is ever scaled.
const FELT_LIT := Color8(52, 132, 90)      # under the lamp, where the buttons are
const FELT_MID := Color8(30, 92, 65)       # the honest colour of the cloth
# Out where the lamp does not reach. Deliberately NOT near-black: this is still
# cloth, and the first pass at (8,30,24) turned the whole outer half of the frame
# into a void with a green puddle in the middle of it. The room past the RAIL is the
# thing that is allowed to be black.
const FELT_DARK := Color8(16, 50, 38)

# The warm bloom the lamp itself lays over the cloth. Mixed IN on top of FELT_LIT
# rather than replacing it, and kept very weak — a casino lamp lights the felt, it
# does not bleach it.
const LAMP_WARM := Color8(126, 152, 96)

# The betting arc: the classic cream pinstripe curving across the felt in front of
# the house, with a thinner companion just outside it.
const ARC_LINE := Color8(206, 190, 148)

# The padded leather rail, and the dark room past it.
const RAIL_DARK := Color8(30, 19, 22)
const RAIL_ROLL := Color8(88, 58, 56)      # the lit top of the roll, facing the lamp
const ROOM := Color8(8, 6, 9)

# The dressing. Chip props are tinted per instance; these are the two ends every
# prop shader mixes between.
const PROP_SHADE := Color8(16, 24, 28)
# Not white. At (214,206,190) the ivory stacks came out as the brightest objects on
# the table — brighter than the buttons, which is the one thing dressing may never be.
const PROP_LIGHT := Color8(176, 168, 154)

# The face-down cards lying in the gutters: a deep house red with an ivory border.
const CARD_BACK := Color8(122, 30, 42)
const CARD_BACK_HI := Color8(168, 58, 68)
const CARD_EDGE := Color8(226, 220, 206)

# Dust in the lamp cone. The one thing in this scene that is atmosphere rather than
# furniture, and the cheapest.
const DUST := Color8(214, 190, 140)

# The key light the DRESSING is shaded by: high, front-left, warm — the lamp.
const SUN_DIR := Vector3(-0.38, 0.82, 0.42)

# ---------------------------------------------------------------------------
# Animation
# ---------------------------------------------------------------------------
# The board's SubViewport deliberately does not redraw while nothing is moving, so
# an animated background is nudged at this rate instead (MemoryGameUI._tick_bg_idle).
# The table itself barely moves — dust drifting through the lamp cone and a slow
# sheen on the nap — so it takes the floors' 15 Hz rather than the lake's 30.
const IDLE_HZ := 15.0

# ...and the app's own rate while an event is on the table. A card crossing the
# frame in half a second at 15 Hz is a slideshow. See `idle_hz_for`.
const EVENT_HZ := 60.0

# ---------------------------------------------------------------------------
# HOW THE BOARD ITSELF IS FRAMED HERE
# ---------------------------------------------------------------------------
# Two deltas on MemoryGameUI's own fit: (how much of the viewport's height the board
# may span, where its centre sits). Every background but Ice Kingdom and this one
# answers (0, 0) — see BackgroundScenes.frame_bias, and MemoryGameUI._fit_camera,
# which CLAMPS whatever comes back because the buttons are the game.
#
# This table needs it for the same reason Ice Kingdom's horizon did. A board fitted
# to fill 0.90 of the height centred at 0.487 puts its top row of buttons at about
# 0.037 of the frame — above anything a picture could put behind them — so the rail
# would either cut across the back chips or have to be pushed so far away that the
# table has no visible edge at all and reads as a green floor.
#
# It is deliberately gentler than Ice's (-0.065, 0.150): the buttons here are the
# same size discs the stock board has, and 0.05 of the height is all the rail and
# the card events need. It buys the band across the top of the frame that EVERY
# casino event is played in.
const FRAME_BIAS := Vector2(-0.050, 0.115)

# ---------------------------------------------------------------------------
# Measured inverse of the board's tone curve
# ---------------------------------------------------------------------------
# Linear radiance for screen counts 0, 4, 8 ... 256, through AgX at
# tonemap_exposure 0.40. The same table lake_world.gd and ice_world.gd carry, and
# for the same reason: it is a property of the BOARD's Environment, not of any one
# background. Regenerate with tools/lake_tone.tscn if that ever changes.
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


# The linear radiance that this Environment turns into `c` on screen. Per channel, by
# lerping the measured ramp — the curve has a toe and a shoulder that are not one
# power law.
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


# What the 2D layer behind the board is cleared to, in LINEAR light (the convention
# BackgroundScenes.backdrop_color already has). The room past the rail, so the flat
# fill behind the viewport is exactly the tone the table dissolves into and no seam
# can appear at the edge of the board's silhouette.
static func backdrop_color(_id: String) -> Color:
	return Color(ROOM.r, ROOM.g, ROOM.b).srgb_to_linear()


# The felt IS the board plane. Nothing to say — see the header.
static func pool_plane_y(_id: String) -> float:
	return 0.0


# The table has an edge, but it is a long way outside the play area and the pools'
# own GLOW_R_CUT ends them well before it.
static func pool_radius(_id: String) -> float:
	return 0.0


# How much of the ground pool this surface takes (BackgroundScenes.pool_gain).
# GLOW_PEAK was fitted against a near-black board; this felt is a mid green — darker
# than the lake's turquoise, brighter than the ice. Six pools at full strength meet
# in the middle and put a pale wash over the cloth exactly where the buttons are.
const POOL_GAIN := 0.66


static func is_animated(_id: String) -> bool:
	return true


# ---------------------------------------------------------------------------
# The scene
# ---------------------------------------------------------------------------
# GDScript cannot resolve a script's own `class_name` from inside that script, and a
# script cannot preload itself either, so the one place this file has to name itself
# does it through the resource cache. `load` on an already-loaded script is a
# dictionary lookup, and it happens once.
static var _script: GDScript = null


static func build(id: String) -> Node3D:
	if not CATALOG.has(id):
		return null
	if _script == null:
		_script = load("res://casino_world.gd") as GDScript
	var root: Variant = _script.new()
	root.name = "RoyalCasino"
	root.construct()
	return root as Node3D


# Tell the table where this board's buttons are, how far the outermost one reaches,
# and the camera and viewport it is all being seen through. Called by MemoryGameUI
# whenever the board's ground layout is (re)established, which is also every resize
# and every difficulty change.
static func set_board_layout(scene: Node3D, centres: PackedVector2Array, reach: float,
		cam: Camera3D, vp_size: Vector2) -> void:
	if scene != null and scene.has_method("set_layout"):
		scene.call("set_layout", centres, reach, cam, vp_size)


# One chip was pressed. The table answers with a small dust puff off the felt at that
# chip and nothing else; the chip's own press clip and its contact shadow do the rest.
static func note_press(scene: Node3D, centre: Vector2) -> void:
	if scene != null and scene.has_method("tap"):
		scene.call("tap", centre)


# The round the player has just FINISHED, offered on every completed round. The table
# answers every THIRD with one randomly chosen casino event (see CasinoEvents) and
# ignores the rest — the decision is here and not in game.gd.
#
# What comes back is a duration and nothing else: the seconds the round must stay
# frozen for what was just started. Same contract as the lake's and Ice Kingdom's,
# and this table answers it in TWO different ways depending on what it started:
#
#   0.0   for the six lane events. They play out above the buttons and the next
#         round is free to start underneath them — a property of the geometry
#         rather than a shortcut; see CasinoEvents.start_event.
#   >0    for the HAND, on the third and sixth of every eight-level cycle. Those
#         cards are thrown by the croupier from behind the table INTO THE MIDDLE
#         of it, across the ring of buttons, and the freeze is what makes that
#         legal — see CasinoEvents.start_hand and the DEAL_WINDUP block above it.
static func note_milestone(scene: Node3D, round_no: int) -> float:
	if scene != null and scene.has_method("start_table_event"):
		return float(scene.call("start_table_event", round_no))
	return 0.0


# The level the player has just COMPLETED, for the milestone the every-third one is
# not big enough for. The table answers every eighth with the ROYAL FLUSH.
static func note_finale(scene: Node3D, level_no: int) -> float:
	if scene != null and scene.has_method("start_royal_flush"):
		return float(scene.call("start_royal_flush", level_no))
	return 0.0


# True while the Royal Flush is still on the table — the ace, the confetti, the
# croupier's dance, any of it. This is what game.gd waits on rather than only on the
# duration `note_finale` returned: the duration is derived from the event's own
# timeline (T_FLUSH + HOLD) and the two agree today, but the one that cannot go
# stale is the event saying so itself. See BackgroundScenes.celebration_busy.
static func celebration_busy(scene: Node3D) -> bool:
	return scene != null and scene.has_method("event_active") \
		and bool(scene.call("event_active"))


# How often the board should nudge its SubViewport to redraw. IDLE_HZ normally; the
# app's own rate while an event is on the table.
static func idle_hz_for(scene: Node3D) -> float:
	if scene != null and scene.has_method("event_active") \
			and bool(scene.call("event_active")):
		return EVENT_HZ
	return IDLE_HZ


# ---------------------------------------------------------------------------
# Preview
# ---------------------------------------------------------------------------
# A shop card renders the table through the Hard board's own pose, the same as every
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
	env.background_color = backdrop_color("world_casino")
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
# The table is FOUR draw calls: the felt, one MultiMesh of chip props, one MultiMesh
# of face-down cards and one batched quad sheet of dust. Nothing is a particle
# system, nothing is a light, nothing has a shadow, nothing has a texture, and
# nothing but a press or an event has a per-frame CPU cost. Every animation in the
# resting table is a function of TIME inside a shader.
#
# CasinoEvents adds its own nodes on top of that, and they are all hidden with
# `instance_count = 0` while nothing is happening — see its own cost note.

# ---------------------------------------------------------------------------
# Where the dressing goes
# ---------------------------------------------------------------------------
# Through the CAMERA, not in metres — the lesson lake_world.gd paid for. A tabletop
# camera looking down at 33.5 deg keystones the ground hard, so "four metres out" is
# comfortably in frame at the SIDE and far outside it toward the camera. Every
# candidate point is projected and kept only if it lands in the frame's gutter, which
# is also what makes ONE table correct on all three boards at every aspect with no
# per-board constant.
const DRESS_CLEAR := 1.20         # multiples of the outermost button's reach
const DRESS_FAR := 3.2            # ...and how far past that it is worth sampling
const EDGE_X := 0.015
const EDGE_TOP := 0.055
const EDGE_BOTTOM := 0.015
const TRIES := 90

const SEED := 0x0ca510

# How many of each prop to attempt. Anything that cannot be placed is dropped rather
# than placed badly, so these are ceilings.
const N_STACKS := 9               # short towers of chips
const N_LOOSE := 12               # single chips lying flat
# NO face-down cards in the dressing any more, and the zero is the point rather
# than a disabled feature: the table now says CHIPS AROUND THE EDGE, CARDS IN THE
# MIDDLE. Five face-down cards scattered out by the rail were the only other cards
# on the felt, and with a royal flush being built in the ring's centre they read as
# competition for it — the eye goes to a card, and the ones that matter are the five
# the player is collecting.
#
# The chips they made room for are added back to the two counts above, so the table
# is no emptier than it was; it is just made of one thing at its edges instead of
# two.
const N_CARDS := 0                # face-down cards — see above
const N_DUST := 18

# A stack is this many chips, picked per stack.
const STACK_LO := 3
const STACK_HI := 7

# How wide a prop may be on screen, as a fraction of the frame's width. A stack that
# reads as furniture out by the rail is a tower across the corner when the same draw
# puts it near the camera.
const SCREEN_FLAT := 0.075
const SCREEN_LOOSE := 0.042       # ...and the tighter cap a single loose chip takes
const SCREEN_TALL := 0.11

# How far toward the camera a STANDING prop may be laid, as a fraction of the band's
# inner radius. See _frame_point.
const STACK_NEAR := 0.30
# How much of the events' lane the dressing keeps clear, in card lengths behind and
# in front of the lane's centre line. Asymmetric because a prop BEHIND a card is
# harmlessly occluded by it and a prop IN FRONT of one is not.
const LANE_KEEP_BACK := 0.55
const LANE_KEEP_FRONT := 1.70
const LOOSE_NEAR := 0.75          # ...and the looser one a flat prop takes

# ---------------------------------------------------------------------------
# The lamp, the arc and the rail
# ---------------------------------------------------------------------------
# All three are SOLVED against the live camera rather than chosen in metres, for the
# same reason the dressing is.
#
# The lamp pool is an ellipse around the board, sized off its reach — that one is
# genuinely a world-space question, because what it has to light is the buttons.
const LAMP_X := 1.40              # multiples of reach
const LAMP_Z := 1.20
const LAMP_SOFT := 0.95           # how far past that it fades, again in reach

# The betting arc and the rail are SCREEN questions: both have to sit ABOVE the
# topmost chip, and how far away that is in metres is different on all three boards
# and at every aspect.
const ARC_CLEAR := 0.045          # of the frame's height, above the top chip
const RAIL_CLEAR := 0.100
# The rail must ALSO leave the frame at the sides rather than curving down through
# it, so its radius is the larger of "far enough back" and "wide enough".
#
# ...and if the larger of those is further than this, THE RAIL IS SWITCHED OFF and
# the felt simply runs out into the dark. That is the whole safety property: there
# is no board, aspect or difficulty on which the table's edge can cut across the
# play area, because the only alternative to clearing it is not drawing it.
const RAIL_MAX := 34.0
const RAIL_W := 1.15              # the width of the padded roll, in board units

# Where the felt starts falling away toward FELT_DARK, as multiples of reach, when
# there is no rail to fall toward.
const FALL_NEAR := 1.35
const FALL_FAR := 4.2

# ---------------------------------------------------------------------------
# The node
# ---------------------------------------------------------------------------
var _felt: MeshInstance3D
var _fmat: ShaderMaterial
var _dealer: CasinoDealer
var _dress: Node3D
var _chips: MultiMeshInstance3D
var _cards: MultiMeshInstance3D
var _dust: MeshInstance3D
var _events: Node3D

var _centres := PackedVector2Array()
var _reach := 0.0
var _vp_size := Vector2.ZERO
var _cam_pose := Transform3D()
var _laid_out := false
# The z band the events' lane occupies, kept clear of dressing. See _scatter.
var _lane_lo := 0.0
var _lane_hi := 0.0
# The screen box the croupier stands in, kept clear of dressing. He is BEHIND every
# prop in the band he stands in — same ground plane, further away — so a chip stack
# that lands on him is drawn behind his head as a shape growing out of it, which is
# what the first render showed: a blue disc twice the size of his head, over his
# shoulder, reading as part of him.
var _dealer_box := Rect2()
# What _lay_table solved that the croupier needs: where the table's edge is and
# which screen row the topmost chip's top edge lands on.
var _rail_r := 0.0
var _top_px := 0.0

# The dust puff a press throws off the felt, as an age per button. Purely local to
# this file; the chip's own press clip and its contact shadow are the press.
var _puff := PackedFloat32Array()

const PUFF_LIFE := 0.55
const MAX_PUFFS := 6


func construct() -> void:
	_build_felt()
	_dress = Node3D.new()
	_dress.name = "Dressing"
	add_child(_dress)
	_chips = _multi("ChipProps", _chip_prop_mesh(), _chip_prop_material())
	_cards = _multi("CardProps", _card_prop_mesh(), _card_prop_material())
	_dust = MeshInstance3D.new()
	_dust.name = "Dust"
	_dust.material_override = _dust_material()
	_dust.layers = BG_LAYER
	_dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The vertices are HOMES, not positions: the drift happens in the vertex shader,
	# after the bounds would have been derived, so they are given rather than found.
	_dust.custom_aabb = AABB(Vector3(-24, -1, -24), Vector3(48, 8, 48))
	_dress.add_child(_dust)

	# THE CROUPIER, before the events, because the events are handed a reference to
	# him and a null one would silently turn every deal back into a card that comes
	# from nowhere. He is placed in _lay_table, which is the only place on this table
	# that knows where the edge is.
	_dealer = CasinoDealer.new()
	_dealer.name = "Croupier"
	add_child(_dealer)
	_dealer.construct()

	_events = CasinoEvents.new()
	_events.name = "EventsRoot"
	add_child(_events)
	_events.call("construct")
	# WHERE THE CARDS COME FROM. Handed over the same way the felt is, and for the
	# same reason: a node path from the events into their parent's other child is a
	# dependency that breaks silently when either file moves.
	_events.call("attach_dealer", _dealer)
	# The two lighting events change the TABLE, so they are given its material
	# directly rather than reaching back up the tree for it — a node path from a
	# child into its parent is a dependency that breaks silently when either file
	# is refactored.
	_events.call("attach_felt", _fmat)

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
	mi.custom_aabb = AABB(Vector3(-40, -2, -40), Vector3(80, 8, 80))
	_dress.add_child(mi)
	return mi


# ---------------- the felt ----------------

func _build_felt() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(FELT_SIZE, FELT_SIZE)
	var sh := Shader.new()
	sh.code = FELT_SHADER
	_fmat = ShaderMaterial.new()
	_fmat.shader = sh
	_fmat.set_shader_parameter("c_lit", tone(FELT_LIT))
	_fmat.set_shader_parameter("c_mid", tone(FELT_MID))
	_fmat.set_shader_parameter("c_dark", tone(FELT_DARK))
	_fmat.set_shader_parameter("c_warm", tone(LAMP_WARM))
	_fmat.set_shader_parameter("c_arc", tone(ARC_LINE))
	_fmat.set_shader_parameter("c_rail", tone(RAIL_DARK))
	_fmat.set_shader_parameter("c_roll", tone(RAIL_ROLL))
	_fmat.set_shader_parameter("c_room", tone(ROOM))
	# Placeholders until the first layout. A table with no camera yet draws as plain
	# felt rather than as a guess at where its furniture goes.
	_fmat.set_shader_parameter("lamp", Vector2(4.5, 3.9))
	_fmat.set_shader_parameter("lamp_soft", 3.1)
	_fmat.set_shader_parameter("arc_r", 0.0)
	_fmat.set_shader_parameter("arc_w", 0.055)
	_fmat.set_shader_parameter("arc_gap", 0.20)
	_fmat.set_shader_parameter("rail_r", 1000.0)
	_fmat.set_shader_parameter("rail_w", RAIL_W)
	_fmat.set_shader_parameter("rail_on", 0.0)
	_fmat.set_shader_parameter("fall", Vector2(6.0, 14.0))
	_fmat.set_shader_parameter("puffs", PackedVector2Array([Vector2.ZERO, Vector2.ZERO,
		Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]))
	_fmat.set_shader_parameter("puff_age", PackedFloat32Array([9.0, 9.0, 9.0, 9.0, 9.0, 9.0]))
	_fmat.set_shader_parameter("puff_count", 0)
	_fmat.set_shader_parameter("puffing", 0.0)
	_fmat.set_shader_parameter("puff_life", PUFF_LIFE)
	_fmat.set_shader_parameter("ev_lift", 0.0)
	_fmat.set_shader_parameter("ev_sweep", -99.0)

	_felt = MeshInstance3D.new()
	_felt.name = "Felt"
	_felt.mesh = pm
	_felt.material_override = _fmat
	_felt.position = Vector3.ZERO
	_felt.layers = BG_LAYER
	_felt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_felt)


# ---------------- layout ----------------

func set_layout(centres: PackedVector2Array, reach: float, cam: Camera3D,
		vp_size: Vector2) -> void:
	_centres = centres
	if _puff.size() != MAX_PUFFS:
		_puff.resize(MAX_PUFFS)
		_puff.fill(PUFF_LIFE * 2.0)
	var pts := PackedVector2Array()
	for i in MAX_PUFFS:
		pts.append(centres[i] if i < centres.size() else Vector2.ZERO)
	_fmat.set_shader_parameter("puffs", pts)
	_fmat.set_shader_parameter("puff_count", mini(centres.size(), MAX_PUFFS))
	if cam == null or vp_size.x < 8.0 or vp_size.y < 8.0:
		return
	# Re-laid whenever the board, the frame OR THE CAMERA moves. The camera is the
	# one that is easy to miss: the board's ground layout is settled several times
	# during a build, and the first of those runs before _fit_camera has solved the
	# distance — so keying only on the reach and the viewport size lays the whole
	# table through a camera that is 30 % too close.
	var pose := cam.global_transform
	if absf(reach - _reach) > 0.05 or _vp_size != vp_size \
			or not pose.is_equal_approx(_cam_pose):
		_vp_size = vp_size
		_cam_pose = pose
		_lay_table(reach, cam, vp_size)
		# THE EVENTS ARE LAID OUT FIRST, and the order matters. Their lane is a band
		# of the table with cards in it, and a chip stack standing in that band is a
		# chip stack in front of the King of Hearts — which is exactly what the first
		# render showed. The dressing needs to know where the lane is before it is
		# scattered, so the lane is solved first and `_scatter` avoids it.
		if _events != null:
			_events.call("set_layout", centres, reach, cam, vp_size)
		# ...AND THE CROUPIER AFTER THEM, because the size of his hands is solved
		# against the size of the cards they deal, and the row those are dealt into
		# is what the events have just finished fitting. A dealer placed inside
		# _lay_table gets last frame's card length, or none at all on the first.
		_place_dealer(cam, vp_size, reach)
		_scatter(reach, cam, vp_size)
		_laid_out = true
	elif _events != null:
		_events.call("set_layout", centres, reach, cam, vp_size)


# Stand the croupier's arms in the band above the table's edge, at the size his own
# cards make him. See CasinoDealer.place.
func _place_dealer(cam: Camera3D, vp: Vector2, reach: float) -> void:
	if _dealer == null:
		return
	var card := 0.0
	if _events != null:
		card = float(_events.get("_hand_len"))
		if card <= 0.0:
			card = float(_events.get("_card_len"))
	_dealer.place(cam, vp, reach, _rail_r, _top_px, card)
	# ...and the idle breath needs the loop running from now on.
	if _dealer.placed():
		set_process(true)


# Solve the lamp, the arc and the rail against this camera.
func _lay_table(reach: float, cam: Camera3D, vp: Vector2) -> void:
	_reach = reach
	_fmat.set_shader_parameter("lamp", Vector2(reach * LAMP_X, reach * LAMP_Z))
	_fmat.set_shader_parameter("lamp_soft", reach * LAMP_SOFT)

	# Where the topmost chip's top edge lands on screen. Screen y grows downward, so
	# the smallest y is the highest button.
	var top_px := vp.y
	for c: Vector2 in _centres:
		var p := Vector3(c.x, CHIP_TOP, c.y)
		if cam.is_position_behind(p):
			continue
		top_px = minf(top_px, cam.unproject_position(p).y)
	if _centres.is_empty():
		top_px = vp.y * 0.30

	# The arc, a little above the chips.
	var arc_r := _radius_at_screen_y(top_px - vp.y * ARC_CLEAR, cam, vp)
	# Below the buttons' own reach it would be drawn THROUGH the play area, which is
	# the one thing it may never do; a table with no visible arc is fine.
	if arc_r < reach * 1.05:
		arc_r = 0.0
	_fmat.set_shader_parameter("arc_r", arc_r)

	# The rail: far enough back to clear the chips AND wide enough to leave the frame
	# at the sides rather than curving down through it.
	var rail_far := _radius_at_screen_y(top_px - vp.y * RAIL_CLEAR, cam, vp)
	var rail_side := _radius_off_screen_x(cam, vp)
	var rail_r := maxf(rail_far, rail_side)
	var rail_on := 1.0 if (rail_far > 0.0 and rail_r <= RAIL_MAX) else 0.0
	_fmat.set_shader_parameter("rail_r", rail_r if rail_on > 0.0 else 1000.0)
	_fmat.set_shader_parameter("rail_on", rail_on)

	# Where the felt starts falling into the dark. Into the rail when there is one,
	# into open darkness when there is not.
	#
	# BOTH ENDS ARE HELD OFF THE BUTTONS. The first version keyed the near end off
	# the rail alone (0.42 of it), which on Hard put it at r 2.04 — INSIDE a ring of
	# buttons reaching 3.47 — so the cloth went dark underneath the play area and the
	# table read as a green pool in a void rather than as a lit table. The near end is
	# now at least a clear margin outside the outermost chip, whichever answer is
	# further out.
	var near := maxf(reach * FALL_NEAR, rail_r * 0.70) if rail_on > 0.0 \
		else reach * FALL_NEAR
	var far := (rail_r * 1.02) if rail_on > 0.0 else reach * FALL_FAR
	_fmat.set_shader_parameter("fall", Vector2(near, maxf(far, near + 0.5)))

	# The two numbers the CROUPIER is fitted against, kept for `_place_dealer` — he
	# is placed after the events rather than here, because the size of his hands is
	# solved against the size of the cards they deal and only the events know that.
	_rail_r = rail_r if rail_on > 0.0 else 0.0
	_top_px = top_px


# The ground radius whose FAR point (0, 0, -r) projects to screen row `py`.
#
# Bisected rather than solved: the closed form needs the camera's elevation, its
# lens and its slide, and the projection is already the authority on all three. 24
# steps take a 60 m bracket to under a millimetre, once per layout.
#
# Returns 0.0 when `py` is above the horizon this camera has, which is the caller's
# signal that there is no room for whatever it was placing.
func _radius_at_screen_y(py: float, cam: Camera3D, vp: Vector2) -> float:
	if py <= vp.y * 0.004:
		return 0.0
	var lo := 0.30
	var hi := 60.0
	if _screen_y_of(hi, cam) > py:
		return 0.0          # even 60 m away is still below the target row
	for _i in 24:
		var mid := (lo + hi) * 0.5
		if _screen_y_of(mid, cam) > py:
			lo = mid
		else:
			hi = mid
	return hi


func _screen_y_of(r: float, cam: Camera3D) -> float:
	var p := Vector3(0.0, 0.0, -r)
	if cam.is_position_behind(p):
		return -1e9
	return cam.unproject_position(p).y


# The smallest ground radius whose SIDE point (r, 0, 0) is off the right edge of the
# frame. This is what stops the rail's circle curving down into the picture beside
# the buttons.
func _radius_off_screen_x(cam: Camera3D, vp: Vector2) -> float:
	var lo := 0.30
	var hi := RAIL_MAX * 1.2
	var edge := vp.x * 1.02
	if _screen_x_of(hi, cam) < edge:
		return hi
	for _i in 24:
		var mid := (lo + hi) * 0.5
		if _screen_x_of(mid, cam) < edge:
			lo = mid
		else:
			hi = mid
	return hi


func _screen_x_of(r: float, cam: Camera3D) -> float:
	var p := Vector3(r, 0.0, 0.0)
	if cam.is_position_behind(p):
		return 1e9
	return cam.unproject_position(p).x


# ---------------- the press puff ----------------

# A chip was pressed. A small dust lift off the nap at that chip and nothing else —
# the ONLY per-frame CPU cost the resting table has, and `_process` turns itself
# back off the moment the last one has died.
func tap(centre: Vector2) -> void:
	var best := -1
	for i in _centres.size():
		if _centres[i].distance_to(centre) < 0.25:
			best = i
			break
	if best < 0 or best >= MAX_PUFFS:
		return
	if _puff.size() != MAX_PUFFS:
		_puff.resize(MAX_PUFFS)
		_puff.fill(PUFF_LIFE * 2.0)
	_puff[best] = 0.0
	set_process(true)
	_push_puffs()


func _process(dt: float) -> void:
	var live := false
	for i in _puff.size():
		if _puff[i] < PUFF_LIFE:
			_puff[i] += dt
			live = true
	if live:
		_push_puffs()
	# The events keep _process alive on their own account, and turn the whole loop
	# back off when they finish.
	if _events != null and bool(_events.call("tick", dt)):
		live = true
	# THE CROUPIER BREATHES, and that is why this loop no longer switches itself
	# off on this background. A pair of hands frozen to the millimetre is the one
	# thing that gives away that they are props; the motion is the asset's own IDLE
	# clip (CasinoDealer.idle seeks it) and it is only stepped while nothing else is
	# running, so it costs one skeleton pose at the rate the board is already
	# redrawing this table at.
	if _dealer != null and _dealer.placed():
		if not (_events != null and bool(_events.call("active"))):
			_dealer.idle(dt)
		live = true
	if not live:
		set_process(false)


func _push_puffs() -> void:
	var ages := PackedFloat32Array()
	var live := false
	for i in MAX_PUFFS:
		var a: float = _puff[i] if i < _puff.size() else PUFF_LIFE * 2.0
		ages.append(a)
		live = live or a < PUFF_LIFE
	_fmat.set_shader_parameter("puff_age", ages)
	_fmat.set_shader_parameter("puffing", 1.0 if live else 0.0)


# ---------------- events, forwarded ----------------

func start_table_event(round_no: int) -> float:
	if _events == null or not _laid_out:
		return 0.0
	# THE HAND FIRST. On the third and sixth of every eight-level cycle the table is
	# building a royal flush in its middle (CasinoEvents' THE HAND), and that
	# outranks the random lane flourish those rounds would otherwise draw — it is
	# the thing the player is actually collecting. Every other multiple of three
	# falls through to the bag exactly as before, so the two interleave: the hand at
	# 3 and 6, a lane event at 9, 12, 15, 18 and 21, the flush at 8.
	var secs: float = _events.call("start_hand", round_no)
	if secs <= 0.0:
		secs = _events.call("start_event", round_no)
	# Keyed off whether an event is RUNNING, not off the freeze it asked for. The
	# small events deliberately ask for none (see CasinoEvents.start_event), and an
	# earlier version that started the clock only when a freeze came back started
	# nothing at all.
	if bool(_events.call("active")):
		set_process(true)
	return secs


func start_royal_flush(level_no: int) -> float:
	if _events == null or not _laid_out:
		return 0.0
	var secs: float = _events.call("start_flush", level_no)
	if secs > 0.0:
		set_process(true)
	return secs


# The hand has to be re-seated whenever the board is (a resize, a difficulty
# change), and CasinoEvents.set_layout does that — this is only here so the table
# can be asked what it is holding without reaching into the events module.
func hand_stage() -> int:
	return int(_events.get("_hand_stage")) if _events != null else 0


# The screen box the hand covers, for the banner that has to keep off it. See
# CasinoEvents.hand_screen_rect.
func hand_rect(cam: Camera3D, vp: Vector2) -> Rect2:
	if _events == null or not _laid_out:
		return Rect2()
	return _events.call("hand_screen_rect", cam, vp)


static func focus_rect(scene: Node3D, cam: Camera3D, vp: Vector2) -> Rect2:
	if scene != null and scene.has_method("hand_rect"):
		return scene.call("hand_rect", cam, vp)
	return Rect2()


func event_active() -> bool:
	return _events != null and bool(_events.call("active"))


# ---------------------------------------------------------------------------
# The felt
# ---------------------------------------------------------------------------
# Flat geometry, shaded entirely analytically. There is nothing to displace: the
# table is flat and is seen at 33.5 deg through a 25 deg lens, so what the eye reads
# as cloth is the NAP — a fine two-scale grain with a directional fibre through it —
# and the nap is a texture-free function of position.
#
# Six terms, in this order, and the order is the design:
#
#   pool     the overhead lamp, an ellipse around the board. This is the single
#            most casino thing about the table and it is what makes the buttons the
#            brightest objects in the frame without touching the buttons.
#   fall     the cloth dropping into shade away from the lamp.
#   nap      the weave. Detail falls off with camera distance or the far half of
#            the table shimmers with aliasing instead of receding.
#   arc      the betting pinstripes, drawn on the FAR side only and fading out to
#            the sides, so they curve behind the board and never cross it.
#   rail     the padded leather edge and its lit roll, gated by `rail_on` — which
#            the CPU sets to zero on any board where the rail cannot clear the
#            buttons. See _lay_table.
#   room     what is past the rail, which is the same colour the 2D layer behind
#            the board is cleared to, so the table has no visible boundary anywhere.
#
# Everything is in radiance: the palette was solved to radiance once at build time
# (see `tone`), and nothing in here converts a colour.
const FELT_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;

const int MAX_PUFFS = 6;

uniform vec3 c_lit;
uniform vec3 c_mid;
uniform vec3 c_dark;
uniform vec3 c_warm;
uniform vec3 c_arc;
uniform vec3 c_rail;
uniform vec3 c_roll;
uniform vec3 c_room;

uniform vec2 lamp;            // ellipse radii of the lamp pool, in board units
uniform float lamp_soft;      // how far past it the pool fades
uniform float arc_r;          // 0 disables the betting arc
uniform float arc_w;
uniform float arc_gap;
uniform float rail_r;
uniform float rail_w;
uniform float rail_on;        // 0 or 1 — see _lay_table
uniform vec2 fall;            // where the cloth starts and finishes falling to c_dark

// The press puff. Costs an exp and a smoothstep per button per pixel for 0.55 s
// after a press, so it sits behind a UNIFORM branch — every fragment in the frame
// takes it the same way, which is what makes it free when it is off.
uniform int puff_count;
uniform vec2 puffs[MAX_PUFFS];
uniform float puff_age[MAX_PUFFS];
uniform float puff_life;
uniform float puffing;

// The two the EVENTS drive (CasinoEvents._pose_lighting), and the only channel
// anything on this table has into the table's own lighting.
uniform float ev_lift;        // 0..1, the room coming up
uniform float ev_sweep;       // angle of the light travelling round the edge; < -9 is off

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// A cheap value-noise pair. Two octaves is all the nap needs — the third was
// measured to change nothing at gameplay size and cost a full extra hash per pixel.
float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = h21(i);
	float b = h21(i + vec2(1.0, 0.0));
	float c = h21(i + vec2(0.0, 1.0));
	float d = h21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec2 p = wpos.xz;
	float r = length(p);

	// --- the lamp pool
	float e = length(p / max(lamp, vec2(0.05)));
	// The ramp starts WELL INSIDE the ellipse. Starting it at e = 1 (the ellipse
	// itself) left the whole play area at one flat value with the falloff entirely
	// outside it, and a lamp with no gradient under the players is not a lamp — it
	// is a fill light, and the table read as a green floor.
	float pool = pow(1.0 - smoothstep(0.30, 1.0 + lamp_soft / max(lamp.x, 0.05), e), 1.4);
	vec3 col = mix(c_mid, c_lit, pool);
	// The warm bloom of the bulb itself, only in the very middle of the pool and
	// only a little of it. Mixed rather than added: a casino lamp lights felt, it
	// does not bleach it.
	// Written as 1 - smoothstep(lo, hi) rather than smoothstep(hi, lo): GLSL leaves
	// smoothstep UNDEFINED when edge0 >= edge1, and some drivers oblige.
	col = mix(col, c_warm, 0.16 * (1.0 - smoothstep(0.0, 0.55, e)));

	// --- falling into the dark of the room
	col = mix(col, c_dark, smoothstep(fall.x, fall.y, r));

	// --- the nap
	// The board's centre is about ten units from this camera, so a detail fade that
	// began at five had already taken half the nap off the felt the player is
	// actually looking at. It exists to stop the FAR field aliasing, and that starts
	// well past the rail.
	float det = 1.0 - smoothstep(9.0, 22.0, distance(CAMERA_POSITION_WORLD, wpos));
	float grain = vnoise(p * 26.0) * 0.65 + vnoise(p * 71.0) * 0.35;
	// A directional fibre through the grain: felt is woven, and a purely isotropic
	// noise reads as concrete. Very shallow — this is a sheen, not a pattern.
	float fibre = 0.5 + 0.5 * sin(dot(p, vec2(0.87, 0.49)) * 118.0);
	float nap = (grain - 0.5) * 0.9 + (fibre - 0.5) * 0.22;
	col = mix(col, mix(c_dark, c_lit, 0.70), clamp(nap, 0.0, 1.0) * 0.115 * det);
	col = mix(col, c_dark, clamp(-nap, 0.0, 1.0) * 0.100 * det);

	// --- the betting arc, far side only
	if (arc_r > 0.1) {
		float far_side = -p.y / max(r, 0.0001);
		float side = smoothstep(-0.10, 0.62, far_side);
		float d1 = abs(r - arc_r);
		float d2 = abs(r - arc_r - arc_gap);
		float line = (1.0 - smoothstep(0.0, arc_w, d1))
			+ 0.55 * (1.0 - smoothstep(0.0, arc_w * 0.62, d2));
		col = mix(col, c_arc, clamp(line, 0.0, 1.0) * side * 0.80);
	}

	// --- the rail
	if (rail_on > 0.5) {
		float rr = (r - rail_r) / max(rail_w, 0.05);
		float on = smoothstep(0.0, 0.14, rr);
		col = mix(col, c_rail, on);
		// The lit top of the roll, facing the lamp: a band just inside the rail's
		// middle. This is the only thing that says the edge is padded and round
		// rather than a painted line.
		float roll = 1.0 - smoothstep(0.0, 0.34, abs(rr - 0.26));
		col = mix(col, c_roll, roll * on * 0.55);
		col = mix(col, c_room, smoothstep(0.98, 1.30, rr));
	}

	// --- the jackpot / royal-flush lighting
	//
	// The lift is applied to the LAMP POOL and not to the whole table, which is what
	// makes it read as the house turning the lights up on the players rather than as
	// an exposure change: the ellipse the six chips are standing in brightens, and
	// the dark of the room around it does not.
	if (ev_lift > 0.002) {
		col = mix(col, mix(col, c_warm, 0.62), ev_lift * 0.40 * (0.35 + 0.65 * pool));
	}
	// ...and a warm band travelling once round the OUTER felt, which at this camera
	// is the border of the picture. Kept outside `fall.x` so it can never run across
	// the play area.
	if (ev_sweep > -9.0) {
		float ang = atan(p.x, -p.y);
		float dd = abs(mod(ang - ev_sweep + 3.14159265, 6.28318530) - 3.14159265);
		// From `fall.x` and not a fraction of it: that is where the cloth starts
		// falling away, which is by construction already outside the outermost chip.
		float outer = smoothstep(fall.x, fall.y, r);
		col = mix(col, c_arc, exp(-dd * dd * 3.0) * outer * 0.42);
	}

	// --- the press puff
	if (puffing > 0.5) {
		float lift = 0.0;
		for (int i = 0; i < MAX_PUFFS; i++) {
			if (i >= puff_count) { break; }
			float a = puff_age[i];
			if (a >= puff_life) { continue; }
			float u = a / puff_life;
			float ring = 1.05 + u * 0.85;
			float d = abs(distance(p, puffs[i]) - ring);
			lift += (1.0 - smoothstep(0.0, 0.22, d)) * (1.0 - u) * (1.0 - u);
		}
		col = mix(col, mix(col, c_warm, 0.55), clamp(lift, 0.0, 1.0) * 0.30);
	}

	ALBEDO = col;
}
"""


# ---------------------------------------------------------------------------
# Dressing
# ---------------------------------------------------------------------------
# Two MultiMeshes and one batched quad sheet, all generated here, all unshaded with
# their own analytic light, all animating (where they animate at all) in their vertex
# shader off TIME. The whole dressing is three draw calls and no CPU.
#
# The rule the placement obeys is the brief's: frame the play, never compete with it.
# Everything is kept a clear margin outside the outermost button and inside the
# frame's own edges; anything that STANDS must additionally fit under the top of the
# picture, and anything FLAT is capped by how wide it lands on screen.
#
# WHY EVERY PROP SHADER IS A mix() BETWEEN TWO SOLVED COLOURS: because a FRACTION of
# a solved colour is not a darker version of it. `tone` gives the radiance that
# produces a chosen screen colour, and AgX at exposure 0.40 has a toe deep enough
# that a prop authored at screen (34,58,70) and multiplied by a lambert floor of 0.30
# renders BLACK. So every prop shades by mixing between a solved SHADOW and a solved
# LIGHT, both ends are colours somebody chose, and the palette can be read off the
# constants above. (Learned on the lake; it cost a whole pass there.)

# Lay every prop out for a board whose outermost button reaches `reach`. Only
# instance transforms are written — no mesh is rebuilt and no material touched — so a
# resize or a difficulty change costs two array fills and one small mesh.
# The band's inner radius is `reach * DRESS_CLEAR`, and the near-band cut-off is
# expressed against it so one number serves all three boards.
static func reach_of(lo: float) -> float:
	return lo / DRESS_CLEAR


func _scatter(reach: float, cam: Camera3D, vp: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var lo := reach * DRESS_CLEAR
	var hi := reach * DRESS_CLEAR + DRESS_FAR
	# The strip of table the events play in, kept clear of furniture. Zero when the
	# lane could not be solved, in which case there are no events either.
	# The HANDS only. An arm crosses most of the top of the frame and refusing every
	# prop behind one would empty the table's whole back edge — a chip stack behind
	# a forearm is occluded and reads correctly. One behind a PALM does not.
	_dealer_box = _dealer.hands_screen_rect(cam, vp) if _dealer != null else Rect2()
	_lane_lo = 0.0
	_lane_hi = 0.0
	if _events != null and bool(_events.get("_lane_ok")):
		var lz: float = _events.get("_lane_z")
		var cl: float = _events.get("_card_len")
		_lane_lo = lz - cl * LANE_KEEP_BACK
		_lane_hi = lz + cl * LANE_KEEP_FRONT
	_fill_chips(_chips.multimesh, rng, lo, hi, cam, vp)
	_fill_cards(_cards.multimesh, rng, lo, hi, cam, vp)
	_dust.mesh = _dust_mesh(N_DUST, rng, lo, hi + 1.5, cam, vp)


# --- chip props ----------------------------------------------------------
# One low cylinder with a bevelled edge, instanced. A stack is N of them at 0.14
# apart with a little rotational jitter, which is what a real stack looks like and
# what makes it read as separate chips at a glance; a loose chip is one instance.
#
# Deliberately COARSER than the gameplay chip and not the same asset: this is a prop
# 3-6 metres out at a shallow angle, where a 14,080-triangle button would spend its
# whole budget on detail under a pixel across. 22 sides is where the silhouette
# stops reading as a polygon at the sizes the fit allows.
const PROP_SIDES := 22
const PROP_R := 0.30
const PROP_H := 0.075
const PROP_BEVEL := 0.035          # of the radius, rolled off top and bottom
const STACK_STEP := 0.078


static func _chip_prop_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var n := PROP_SIDES
	var rb := PROP_R * (1.0 - PROP_BEVEL)
	# Four rings: bottom face edge, bottom bevel, top bevel, top face edge. UV.y
	# carries how far up the chip a vertex is, which is what the shader shades by.
	var rings := [
		{"r": rb, "y": 0.0, "u": 0.0},
		{"r": PROP_R, "y": PROP_H * 0.30, "u": 0.30},
		{"r": PROP_R, "y": PROP_H * 0.70, "u": 0.70},
		{"r": rb, "y": PROP_H, "u": 1.0},
	]
	for ring: Dictionary in rings:
		for i in n:
			var a := TAU * float(i) / float(n)
			var rr: float = ring["r"]
			verts.append(Vector3(cos(a) * rr, ring["y"], sin(a) * rr))
			norms.append(Vector3(cos(a), 0.35 if ring["u"] > 0.5 else -0.35, sin(a)).normalized())
			uvs.append(Vector2(float(i) / float(n), ring["u"]))
	for ring in 3:
		for i in n:
			var j := (i + 1) % n
			var a0 := ring * n + i
			var a1 := ring * n + j
			var b0 := (ring + 1) * n + i
			var b1 := (ring + 1) * n + j
			idx.append_array([a0, b0, b1, a0, b1, a1])
	# The top face, as a fan. The bottom is never seen — the chip is lying on the
	# table — so it is not built at all.
	var centre := verts.size()
	verts.append(Vector3(0.0, PROP_H, 0.0))
	norms.append(Vector3.UP)
	uvs.append(Vector2(0.5, 1.6))       # >1 marks the face, so the shader can flatten it
	for i in n:
		var j := (i + 1) % n
		idx.append_array([3 * n + i, centre, 3 * n + j])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _chip_prop_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
// CULL_DISABLED, not cull_back. The barrel is a polar strip whose winding comes out
// inward, so back-face culling removes the NEAR half of every prop and a stack of
// chips renders as a hollow crescent. The mesh is 22 sides and a few hundred
// triangles per stack; drawing both faces costs less than a topology fix would.
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;
uniform vec3 c_shade;
uniform vec3 c_light;
uniform vec3 sun;
varying vec3 wnorm;
varying vec3 tint;
varying float face;
void vertex() {
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	tint = INSTANCE_CUSTOM.rgb;
	face = UV.y > 1.2 ? 1.0 : 0.0;
	// The eight inserts round a real chip's edge, as a band on the barrel. Free:
	// it is the angular UV the mesh already carries.
	tint *= mix(1.0, 0.62, step(0.5, fract(UV.x * 8.0)) * (1.0 - face)
		* step(0.15, UV.y) * step(UV.y, 0.85));
}
void fragment() {
	// A flat top catches the lamp; a barrel facing away from it falls into shade.
	float lam = clamp(dot(normalize(wnorm), normalize(sun)) * 0.5 + 0.5, 0.0, 1.0);
	lam = mix(lam, 0.92, face);
	vec3 base = mix(c_shade, c_light, lam);
	ALBEDO = base * tint;
}
"""
	m.shader = sh
	m.set_shader_parameter("c_shade", tone(PROP_SHADE))
	m.set_shader_parameter("c_light", tone(PROP_LIGHT))
	m.set_shader_parameter("sun", SUN_DIR.normalized())
	return m


# The colours a prop chip may be. Casino denominations rather than the gameplay
# palette, on purpose: the six BUTTONS are the only objects on this table allowed to
# be the game's colours, and dressing that borrows them competes for the same read.
const PROP_TINTS := [
	Color(0.88, 0.86, 0.82),   # ivory / house
	Color(0.86, 0.24, 0.26),   # red
	Color(0.20, 0.30, 0.72),   # blue
	Color(0.16, 0.16, 0.18),   # black
	Color(0.88, 0.74, 0.30),   # gold
]


func _fill_chips(mm: MultiMesh, rng: RandomNumberGenerator, lo: float, hi: float,
		cam: Camera3D, vp: Vector2) -> void:
	var xf: Array[Transform3D] = []
	var cd: Array[Color] = []
	# Stacks STAND, so they are kept out of the near band. See _frame_point.
	var near_z := reach_of(lo) * STACK_NEAR
	for _s in N_STACKS:
		var p := _frame_point(rng, lo, hi, cam, vp, near_z)
		if p == Vector3.INF:
			continue
		var count := rng.randi_range(STACK_LO, STACK_HI)
		# The stack is FITTED, not tested. As a pass/fail test at a fixed height it
		# rejects everything on the board with the closest camera, silently, and the
		# failure looks like a bug in the scatter rather than in the test. See
		# LakeWorld's _fit_height for the general finding.
		var want := PROP_H + STACK_STEP * float(count - 1)
		var tall := _fit_height(p, want, cam, vp)
		if tall <= PROP_H * 0.9:
			continue
		var s := clampf(tall / maxf(want, 0.001), 0.35, 1.0)
		s = minf(s, _fit_flat(p, PROP_R, cam, vp) / PROP_R)
		if s <= 0.3:
			continue
		var tint: Color = PROP_TINTS[rng.randi() % PROP_TINTS.size()]
		for k in count:
			var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s))
			# A real stack leans a hair and its chips are never quite concentric.
			var jit := Vector3(rng.randfn(0.0, 0.010), 0.0, rng.randfn(0.0, 0.010))
			xf.append(Transform3D(b, p + jit + Vector3(0.0, STACK_STEP * s * float(k), 0.0)))
			cd.append(tint)
	for _l in N_LOOSE:
		# Loose chips lie flat and may come further forward than a stack, but not all
		# the way: at no limit at all one landed in the bottom corner of the frame at
		# nearly the size of a gameplay button.
		var p := _frame_point(rng, lo, hi + 0.8, cam, vp, reach_of(lo) * LOOSE_NEAR)
		if p == Vector3.INF:
			continue
		# Capped tighter than a card is: a single chip lying flat has no detail to
		# justify the room, and one drawn near the camera at the card's cap is the
		# biggest object in the frame.
		var s := _fit_flat(p, PROP_R, cam, vp, SCREEN_LOOSE) / PROP_R
		if s <= 0.3:
			continue
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s))
		xf.append(Transform3D(b, p))
		cd.append(PROP_TINTS[rng.randi() % PROP_TINTS.size()])
	_fill(mm, xf, cd)


# --- face-down cards -----------------------------------------------------
# Flat rounded rectangles lying on the felt, deep house red with an ivory border and
# a lattice through the middle. Nothing here is ever face UP: the five cards the
# player is meant to read all belong to the events, and dressing that shows a rank
# would compete with them.
# A real playing card is most of twice a chip's diameter across its long axis, and
# the first pass at 0.44 x 0.62 read as a postage stamp beside a chip 2.0 across.
const CARD_W := 0.78
const CARD_L := 1.12
const CARD_CORNER := 0.075
const CARD_SEGS := 4               # quarter-circle segments per corner


static func _card_prop_mesh() -> ArrayMesh:
	return card_mesh(CARD_W, CARD_L, CARD_CORNER, CARD_SEGS)


# A rounded-rect card lying in the xz plane, centred on its own origin, UV 0..1
# across it. Shared with CasinoEvents, which builds every card it deals from this.
static func card_mesh(w: float, l: float, corner: float, segs: int) -> ArrayMesh:
	var hw := w * 0.5
	var hl := l * 0.5
	var c := minf(corner, minf(hw, hl) * 0.95)
	var ring := PackedVector2Array()
	var corners := [Vector2(hw - c, hl - c), Vector2(-hw + c, hl - c),
		Vector2(-hw + c, -hl + c), Vector2(hw - c, -hl + c)]
	for k in 4:
		var a0 := TAU * 0.25 * float(k)
		for s in segs + 1:
			var a: float = a0 + TAU * 0.25 * float(s) / float(segs)
			ring.append(corners[k] + Vector2(cos(a), sin(a)) * c)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	verts.append(Vector3.ZERO)
	norms.append(Vector3.UP)
	uvs.append(Vector2(0.5, 0.5))
	for v: Vector2 in ring:
		verts.append(Vector3(v.x, 0.0, v.y))
		norms.append(Vector3.UP)
		uvs.append(Vector2(v.x / w + 0.5, v.y / l + 0.5))
	var n := ring.size()
	for i in n:
		idx.append_array([0, 1 + i, 1 + ((i + 1) % n)])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _card_prop_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;
uniform vec3 c_back;
uniform vec3 c_hi;
uniform vec3 c_edge;
void fragment() {
	vec2 q = abs(UV - 0.5) * 2.0;
	float border = max(q.x, q.y);
	// ivory rim, then a thin red gap, then the printed field
	vec3 col = c_back;
	float lat = 0.5 + 0.5 * sin((UV.x + UV.y) * 62.0) * sin((UV.x - UV.y) * 62.0);
	col = mix(col, c_hi, lat * 0.45 * (1.0 - smoothstep(0.60, 0.74, border)));
	col = mix(col, c_edge, smoothstep(0.80, 0.90, border));
	col = mix(col, c_back, smoothstep(0.93, 0.985, border));
	ALBEDO = col;
}
"""
	m.shader = sh
	m.set_shader_parameter("c_back", tone(CARD_BACK))
	m.set_shader_parameter("c_hi", tone(CARD_BACK_HI))
	m.set_shader_parameter("c_edge", tone(CARD_EDGE))
	return m


func _fill_cards(mm: MultiMesh, rng: RandomNumberGenerator, lo: float, hi: float,
		cam: Camera3D, vp: Vector2) -> void:
	var xf: Array[Transform3D] = []
	var cd: Array[Color] = []
	for _c in N_CARDS:
		var p := _frame_point(rng, lo, hi, cam, vp)
		if p == Vector3.INF:
			continue
		var s := _fit_flat(p, CARD_L * 0.5, cam, vp) / (CARD_L * 0.5)
		if s <= 0.35:
			continue
		s = minf(s, 1.0)
		p.y = CARD_Y
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s))
		xf.append(Transform3D(b, p))
		cd.append(Color.WHITE)
		# Cards on a table come in pairs and small heaps far more often than singly.
		if rng.randf() < 0.55:
			var b2 := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s))
			var off := Vector3(rng.randfn(0.0, 0.09), 0.0016, rng.randfn(0.0, 0.09))
			xf.append(Transform3D(b2, p + off))
			cd.append(Color.WHITE)
	_fill(mm, xf, cd)


# --- dust ----------------------------------------------------------------
# Motes hanging in the lamp cone. The one thing in the resting table that is
# atmosphere rather than furniture, and by a distance the cheapest: one batched quad
# sheet, billboarded in view space, drifting off TIME.
func _dust_mesh(count: int, rng: RandomNumberGenerator, lo: float, hi: float,
		cam: Camera3D, vp: Vector2) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	for _i in count:
		var home := _frame_point(rng, lo * 0.55, hi, cam, vp)
		if home == Vector3.INF:
			continue
		# Low. At 0.35 - 2.10 the motes sat well above the table in the dark half of
		# the frame and read as STARS rather than as dust in a lamp cone.
		home.y = rng.randf_range(0.18, 0.95)
		var sz := rng.randf_range(0.011, 0.021)
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


static func _dust_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled,
	depth_draw_never, blend_add;
uniform vec3 tint;
varying vec2 quv;
varying float bright;
void vertex() {
	float s = UV2.x * 6.2831853;
	float t = TIME * 0.13;
	vec3 c = VERTEX;
	// Three periods with no common factor, so a mote wanders instead of orbiting.
	c.x += 0.42 * sin(t * 0.73 + s);
	c.z += 0.34 * cos(t * 0.51 + s * 1.7);
	c.y += 0.30 * sin(t * 0.41 + s * 2.3);
	vec4 vp = MODELVIEW_MATRIX * vec4(c, 1.0);
	// Billboard by offsetting in VIEW space, after the transform: one sheet, no
	// per-instance basis to rebuild, and it faces the camera at any board angle.
	vp.xy += UV * UV2.y;
	POSITION = PROJECTION_MATRIX * vp;
	quv = UV;
	bright = mix(0.35, 1.0, 0.5 + 0.5 * sin(t * 1.9 + s * 4.1));
}
void fragment() {
	float d = clamp(1.0 - length(quv), 0.0, 1.0);
	ALBEDO = tint * bright;
	ALPHA = d * d * d;
}
"""
	m.shader = sh
	m.set_shader_parameter("tint", tone(DUST))
	m.render_priority = 3
	return m


# ---------------------------------------------------------------------------
# Placement
# ---------------------------------------------------------------------------
# A point on the felt between `lo` and `hi` out from the middle of the board that
# lands in the frame's own gutter. Returns Vector3.INF when nothing in TRIES lands,
# and the caller then DROPS that prop rather than placing it badly.
# `near_z` rejects anything closer to the camera than that (+z is toward it), and
# everything that STANDS UP uses it. The near band is the most magnified part of a
# tabletop frame and the only part in FRONT of the buttons, so a stack of chips there
# is both the biggest object on screen and between the player and the game. The two
# bottom corners are better left as open felt leading into the table.
func _frame_point(rng: RandomNumberGenerator, lo: float, hi: float,
		cam: Camera3D, vp: Vector2, near_z: float = 1e9) -> Vector3:
	var x0 := vp.x * EDGE_X
	var x1 := vp.x * (1.0 - EDGE_X)
	var y0 := vp.y * EDGE_TOP
	var y1 := vp.y * (1.0 - EDGE_BOTTOM)
	for _try in TRIES:
		var a := rng.randf() * TAU
		# Linear in radius, not in sqrt: sampling uniformly by AREA pushes most of
		# the draw to the outer edge of the band, which on a keystoned ground plane
		# is the far strip — and every prop ends up in the top corners.
		var r := lerpf(lo, hi, rng.randf())
		var p := Vector3(cos(a) * r, 0.0, sin(a) * r)
		if p.z > near_z:
			continue
		# Out of the events' lane. This camera has no roll, so a band of world z is a
		# horizontal band of the SCREEN — which is what "do not stand in front of the
		# cards" actually means.
		if _lane_hi > _lane_lo and p.z > _lane_lo and p.z < _lane_hi:
			continue
		# is_position_behind FIRST: unproject_position on a point behind the camera
		# hands back a mirrored screen position that passes every bounds test below.
		if cam.is_position_behind(p):
			continue
		var s := cam.unproject_position(p)
		if s.x < x0 or s.x > x1 or s.y < y0 or s.y > y1:
			continue
		# ...and not on top of the croupier's hands. A screen test and not a world
		# one, because what is wrong with a prop there is not where it is standing —
		# it is a long way behind them — but that it is drawn inside a palm.
		if _dealer_box.has_area() and _dealer_box.has_point(s):
			continue
		return p
	return Vector3.INF


# How wide something lying FLAT at `p` may be, capped by how much of the frame's
# width it would cover.
func _fit_flat(p: Vector3, want: float, cam: Camera3D, vp: Vector2,
		cap: float = SCREEN_FLAT) -> float:
	var edge := p + Vector3(want, 0.0, 0.0)
	if cam.is_position_behind(p) or cam.is_position_behind(edge):
		return 0.0
	var px := cam.unproject_position(p).distance_to(cam.unproject_position(edge))
	if px <= 0.5:
		return want
	return want * minf(1.0, (vp.x * cap) / px)


# How tall something STANDING at `p` may be: it has to fit under the top of the frame
# and stay under SCREEN_TALL of its height on screen. FITTED rather than tested — see
# _fill_chips.
func _fit_height(p: Vector3, want: float, cam: Camera3D, vp: Vector2) -> float:
	var top := p + Vector3(0.0, want, 0.0)
	if cam.is_position_behind(p) or cam.is_position_behind(top):
		return 0.0
	var s := cam.unproject_position(p)
	var rise := s.y - cam.unproject_position(top).y
	if rise <= 0.5:
		return want
	var room := minf(s.y - vp.y * EDGE_TOP, vp.y * SCREEN_TALL)
	if room <= 0.0:
		return 0.0
	return want * clampf(room / rise, 0.0, 1.0)


static func _fill(mm: MultiMesh, xf: Array[Transform3D], cd: Array[Color]) -> void:
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_custom_data(i, cd[i])
