extends Node3D
class_name CasinoEvents

# THE ROYAL CASINO'S EVENT SYSTEM — everything that HAPPENS on the poker table.
#
# The table itself is casino_world.gd; the six gameplay chips are chip_buttons.gd.
# This node hangs under the table, owns every temporary object on it, and is the
# only thing in the skin with a clock.
#
# ===========================================================================
# WHAT IT IS ALLOWED TO TOUCH
# ===========================================================================
# NOTHING. It is a visual system and it is built so that it cannot be anything else:
#
#   * it owns five nodes under this one and creates no others;
#   * it is advanced only by CasinoWorld's `_process`, which is itself only running
#     while something is alive;
#   * it never calls into the board, the game, the input path, the sequence or the
#     score, and it has no reference to any of them;
#   * it never MOVES a button, never touches a button's material, and every object
#     it places is solved to land in the frame's gutter or on the lane ABOVE the
#     buttons (see THE LANE) — so it cannot cover the play area even for a frame;
#   * the ONE thing that flows back to the game is a NUMBER OF SECONDS. game.gd
#     freezes the round for exactly that long and thaws it again. The event does not
#     know that happened and cannot ask.
#
# If an event is somehow still running when the next round begins, `stop()` drops
# every object instantly and the table is a table again — no tween to cancel, no
# await to unwind, because there are none: everything here is posed from ONE clock
# in closed form.
#
# ===========================================================================
# THE LANE
# ===========================================================================
# Every event is played out along one horizontal line across the table, and that
# line is solved ON SCREEN against the live camera rather than chosen in metres.
#
# It sits just above the topmost chip and below the betting arc — the band across
# the top of the frame that CasinoWorld.FRAME_BIAS exists to buy. Its ends are the
# world x at which the frame's left and right edges fall AT THAT DEPTH, so a card
# entering from `_x_in` is genuinely off screen on every board at every aspect, and
# one parked at `_x_lo .. _x_hi` is genuinely inside the picture.
#
# It is one lane and not six because six lanes is six ways to end up over a button.
# The variety in these events comes from the objects and the choreography, which is
# where variety is cheap; the geometry is solved once, tested once, and shared.
#
# If the lane cannot be solved — a viewport too small, a camera pose with no room
# above the buttons — `_lane_ok` stays false and EVERY event refuses to start. A
# skin with no events is a disappointment; a card across the middle of the board is
# a bug.
#
# ===========================================================================
# COST
# ===========================================================================
# FIVE draw calls, all of them at `instance_count = 0` or `visible = false` whenever
# nothing is happening, which is almost all of the time:
#
#   Cards     MultiMesh, <= 12   every card in every event, incl. the Royal Flush
#   Chips     MultiMesh, <= 16   the cascade
#   Sparks    MultiMesh, <= 72   every particle in every event, one shared system
#   Shadows   MultiMesh, <= 28   one per live card and chip, generated automatically
#   Ball      MeshInstance3D     the roulette ball
#
# No particle system, no light, no shadow map, no texture, no post-process. The card
# faces — border, corner index, rank glyph and heart pips — are drawn analytically in
# the fragment shader from an instance id, so twelve different cards are one draw
# call and no atlas.
#
# The per-frame CPU is a pose pass over at most 12 + 16 + 72 + 28 transforms, and it
# runs for two to four seconds once every three rounds.

const BG_LAYER := 2

# ---------------------------------------------------------------------------
# The events
# ---------------------------------------------------------------------------
enum {
	EV_COMMUNITY,     # 2-3 cards slide on, sit, and slide away
	EV_ROULETTE,      # the ball laps a small track, lands on a number, pops
	EV_CASCADE,       # chips slide and spin across the felt, some stacking
	EV_FLIP,          # one big card slides in and flips over
	EV_DEAL,          # a glowing deck deals three cards, slap slap slap
	EV_LIGHTS,        # the table lighting comes up, gold in the air
}

const EVENT_COUNT := 6

# The Royal Flush's kind. Outside the enum (the random draw is `% EVENT_COUNT`) but
# a NON-NEGATIVE number all the same, because `_kind >= 0` is what "something is
# running" means everywhere in this file — `active()`, `tick()` and CasinoWorld's
# `_process` all key off it. It was -2 for one draft and the finale silently never
# ran: every clock in the file treated it as idle.
const EV_FLUSH := 6

# How often the table does something, in completed rounds. The BACKGROUND decides
# this, not game.gd — see CasinoWorld.note_milestone.
const EVERY := 3

# ...and the level the ROYAL FLUSH answers.
const FINALE_EVERY := 8

# ---------------------------------------------------------------------------
# Spectacle tiers
# ---------------------------------------------------------------------------
# The events run from the first milestone to the last, and get bigger as the player
# gets further — but the ceiling is low on purpose. What grows is the number of
# objects and the amount of gold in the air; what does NOT grow is how much of the
# frame is used, how long anything lasts, or how bright the table gets. A casino
# that becomes harder to read at round 30 has stopped being a reward.
#
#   tier 0   rounds 3 - 9     two cards, few sparks, no table lift
#   tier 1   rounds 12 - 21   three cards, more sparks, a hint of lift
#   tier 2   round 24 on      three cards with gold edges, full sparks, full lift
static func tier_for(round_no: int) -> int:
	return clampi(int(round_no / 12), 0, 2)

# ---------------------------------------------------------------------------
# The lane
# ---------------------------------------------------------------------------
# How far above the topmost chip the lane sits, as a fraction of the frame's height.
# Below CasinoWorld.ARC_CLEAR (0.045), so the lane is between the chips and the
# betting arc rather than on top of either.
const LANE_CLEAR := 0.022

# The lane's ends, as fractions of the frame's width. Objects live between these;
# they enter and leave from `LANE_OFF` past them.
const LANE_LO := 0.16
const LANE_HI := 0.84
const LANE_OFF := 0.34

# The biggest a card may be, as a fraction of the frame's HEIGHT (a card on the lane
# is seen nearly edge-on, so its long axis reads vertically compressed and width is
# the wrong cap). Five of them side by side must still fit the lane.
# BOTH THIS AND CARD_LEN WERE FAR TOO SMALL IN THE FIRST BUILD (0.115 and 0.92), and
# it was only visible in a render: at that size a card on the lane is about 68 x 48
# pixels at 1280 x 720 — enough to read as "a card", nowhere near enough to read as
# "the King of Hearts". The whole point of the level-8 celebration is that the player
# can see it says 10 J Q K A.
#
# The lane is not what limited it. Five cards at 1.55 still fit inside `_x_lo` ..
# `_x_hi` with room to spare on all three boards; this cap was doing all the work.
const CARD_SCREEN := 0.20

# How far BEHIND its objects' near edge the lane's centre line sits, as a multiple
# of a card's length. The worst case on this table is the flip event's card: half a
# diagonal of a 1 x 0.70 rectangle is 0.61 of its length, and that event scales it by
# 1.30 — so 0.80. Every other object on the lane (a chip, the ball, a dealt card at
# its landing yaw) is smaller than that, and each is additionally capped against this
# number where it is laid out.
const LANE_BACK := 0.82
const CARD_LEN := 1.55            # the size a card wants to be, in board units
const CARD_ASPECT := 0.70         # width / length, a real playing card's proportion

# How high a card floats at the top of its slide, before it settles onto the felt.
const CARD_HOP := 0.16

# ---------------------------------------------------------------------------
# Palette
# ---------------------------------------------------------------------------
# Solved through CasinoWorld.tone at build time, exactly like the table's — see the
# note in that file. Screen colours in, radiance out, and nothing here ever scales a
# solved colour.
const CARD_FACE := Color8(244, 240, 230)     # the printed field
const CARD_FACE_LO := Color8(206, 200, 188)  # its shaded half, for the bevel
const CARD_INK := Color8(26, 24, 28)         # the border and the rank when black
const CARD_RED := Color8(206, 34, 48)        # hearts
const CARD_GOLD := Color8(226, 188, 104)     # the inner border, and every gold edge
const BALL_CORE := Color8(255, 252, 240)
const BALL_GLOW := Color8(255, 226, 150)
const SPARK_GOLD := Color8(255, 214, 122)
const SPARK_WHITE := Color8(255, 248, 226)
const SHADOW_C := Color8(4, 14, 11)

# The chips the cascade uses. Casino denominations, never the gameplay palette —
# the six BUTTONS are the only objects on this table allowed to be the game's
# colours, and an event that borrows them competes for the same read.
const CASCADE_LIGHT := Color8(214, 205, 188)

const CASCADE_TINTS := [
	Color(0.94, 0.93, 0.90), Color(0.86, 0.24, 0.26), Color(0.20, 0.30, 0.72),
	Color(0.16, 0.16, 0.18), Color(0.88, 0.74, 0.30),
]

# ---------------------------------------------------------------------------
# Caps. Every one of these is a hard array bound as well as a budget.
# ---------------------------------------------------------------------------
const MAX_CARDS := 12
const MAX_CHIPS := 16
const MAX_SPARKS := 72
const MAX_SHADOWS := MAX_CARDS + MAX_CHIPS

# How high the contact shadows lie. Under the table's own dressing and under the
# board's ground pools (MemoryGameUI.GLOW_PLANE_Y is 0.012), so an event's shadow
# can never draw over a button's light.
const SHADOW_Y := 0.006

# ---------------------------------------------------------------------------
# Ranks
# ---------------------------------------------------------------------------
# The five the Royal Flush needs, and the only five drawn anywhere. Each is an index
# the card shader turns into glyphs; nothing here is a font, a texture or a string,
# so a missing glyph in a shipped font cannot put a row of boxes on the table.
const RANK_10 := 0
const RANK_J := 1
const RANK_Q := 2
const RANK_K := 3
const RANK_A := 4

# The four a decorative flip may land on. "JOKER" is deliberately absent: it needs a
# figure rather than a letter, and a card that reads "J" while a real Jack of Hearts
# is one event away is worse than one fewer face.
const FLIP_RANKS := [RANK_A, RANK_K, RANK_Q, RANK_J]

# ---------------------------------------------------------------------------
# Timelines
# ---------------------------------------------------------------------------
# Every event is a handful of marks on ONE clock, and every object is posed in
# closed form from it. There is not a single Tween in this file, and that is the
# property that makes `stop()` safe: freeing or resetting this node mid-event leaves
# nothing running anywhere.
#
# The freeze the game takes is the event's length plus HOLD — the event's clock and
# game.gd's SceneTreeTimer are two different clocks, and the one that must land
# second is the one that re-enables input.
const HOLD := 0.12

const T_COMMUNITY := 3.05
const T_ROULETTE := 3.00
const T_CASCADE := 2.55
const T_FLIP := 2.95
const T_DEAL := 2.80
const T_LIGHTS := 2.60
const T_FLUSH := 4.35

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var _cards_mm: MultiMeshInstance3D
var _chips_mm: MultiMeshInstance3D
var _sparks_mm: MultiMeshInstance3D
var _shadow_mm: MultiMeshInstance3D
var _ball: MeshInstance3D
var _ball_mat: ShaderMaterial
var _felt: ShaderMaterial          # the table's own material, for the lighting events

var _kind := -1
var _prev := -1
var _bag: Array = []
var _t := 0.0
var _prev_t := 0.0                 # _t at the top of the previous frame; see _cross
var _len := 0.0
var _tier := 0
var _last_round := -1
var _last_level := -1
var _flush := false

# Solved lane geometry
var _lane_ok := false
var _lane_z := 0.0
var _x_lo := 0.0
var _x_hi := 0.0
var _x_in := 0.0
var _x_out := 0.0
var _card_len := CARD_LEN
var _lane_back := 0.0
var _reach := 0.0

var _rng := RandomNumberGenerator.new()

# The live objects. Each is a plain Dictionary posed by a closed-form function of
# `_t`; there is no per-object state that survives a frame except the sparks', which
# are integrated.
var _cards: Array[Dictionary] = []
var _chips: Array[Dictionary] = []
var _sp_p: Array[Vector3] = []
var _sp_v: Array[Vector3] = []
var _sp_age := PackedFloat32Array()
var _sp_life := PackedFloat32Array()
var _sp_size := PackedFloat32Array()
var _sp_col: Array[Color] = []

# The roulette event's own few numbers.
var _ball_a := 0.0
var _ball_r := 0.0
var _ball_c := Vector3.ZERO
var _ball_stop := 0.0


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
func construct() -> void:
	_rng.seed = 0x0ca5e0

	_cards_mm = _multi("Cards", CasinoWorld.card_mesh(
		CARD_LEN * CARD_ASPECT, CARD_LEN, CARD_LEN * 0.085, 4), _card_material())
	_chips_mm = _multi("Chips", CasinoWorld._chip_prop_mesh(), _chip_material())
	_sparks_mm = _multi("Sparks", _billboard_quad(), _spark_material())
	_shadow_mm = _multi("Shadows", _flat_quad(), _shadow_material())

	_ball = MeshInstance3D.new()
	_ball.name = "Ball"
	var sm := SphereMesh.new()
	# Big enough to BE a roulette ball at gameplay size. At 0.085 it rendered as a
	# single white pixel beside a chip 2.0 across and the whole event read as a
	# glitch; the ball is the subject, and a real one next to a stack of chips is
	# about this size anyway.
	sm.radius = 0.20
	sm.height = 0.40
	sm.radial_segments = 12
	sm.rings = 6
	_ball.mesh = sm
	_ball_mat = _ball_material()
	_ball.material_override = _ball_mat
	_ball.layers = BG_LAYER
	_ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ball.visible = false
	add_child(_ball)

	_clear_all()


# The table's own material, so the two lighting events can lift it. Handed over by
# CasinoWorld rather than looked up, because a node path from here into the parent
# is a dependency that breaks silently when either file is refactored.
func attach_felt(mat: ShaderMaterial) -> void:
	_felt = mat
	_push_felt(0.0, -99.0)


func _multi(nm: String, mesh: Mesh, mat: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	# BOTH channels. Eight floats per instance is what lets one draw call carry
	# twelve different card faces: COLOR is tint + alpha, CUSTOM is rank / face /
	# glow / gold. Four would have forced an atlas or a second material.
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.name = nm
	mi.multimesh = mm
	mi.material_override = mat
	mi.layers = BG_LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-30, -2, -30), Vector3(60, 8, 60))
	add_child(mi)
	return mi


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------
# Solve the lane against the live camera. Called on build, on every resize and on
# every difficulty change — the same signal the table's dressing is laid on, and for
# the same reason: where a point four metres out lands on screen is a question only
# this camera can answer, and it answers it differently on all three boards.
func set_layout(centres: PackedVector2Array, reach: float, cam: Camera3D,
		vp: Vector2) -> void:
	_lane_ok = false
	_reach = reach
	_centres = centres
	if cam == null or vp.x < 8.0 or vp.y < 8.0:
		return

	# Where the topmost chip's top edge lands. Screen y grows downward, so the
	# smallest y is the highest button.
	var top_px := vp.y * 0.34
	if not centres.is_empty():
		top_px = vp.y
		for c: Vector2 in centres:
			var p := Vector3(c.x, CasinoWorld.CHIP_TOP, c.y)
			if cam.is_position_behind(p):
				continue
			top_px = minf(top_px, cam.unproject_position(p).y)

	# THE CLEARANCE IS FOR THE OBJECT'S NEAR EDGE, NOT FOR THE LANE'S CENTRE, and
	# getting that wrong is the one way this system could put something over a
	# button. This camera has no roll and looks down the -z axis, so a world line of
	# constant z projects to a HORIZONTAL screen line — which means "the lane is
	# above the top chip" holds at every x, for a point. A card is not a point: it is
	# ~0.9 long, it may be turned up to a radian, and the flip event scales it by
	# 1.3, so its nearest corner can be most of a card-length in front of the lane.
	#
	# So `edge_z` is where that NEAREST CORNER is allowed to be, and the lane itself
	# is pushed a full worst-case half-diagonal further back.
	var want_py := top_px - vp.y * LANE_CLEAR
	if want_py <= vp.y * 0.012:
		return                      # no band above the buttons: no events, by design
	var edge_z := _z_at_screen_y(want_py, cam)
	if edge_z >= 0.0:
		return

	# Sized at the NEAR edge, which is the most magnified part of the band and
	# therefore the conservative place to ask. FITTED rather than tested: as a
	# pass/fail check at a fixed size it rejects everything on the board with the
	# closest camera, silently, and the failure reads as an event that never fires.
	# (The lake paid for this lesson with its reeds.)
	_card_len = _fit_len(CARD_LEN, edge_z, cam, vp)
	if _card_len <= 0.0:
		return
	_lane_back = _card_len * LANE_BACK
	_lane_z = edge_z - _lane_back

	_x_lo = _x_at_screen_frac(LANE_LO, _lane_z, cam, vp)
	_x_hi = _x_at_screen_frac(LANE_HI, _lane_z, cam, vp)
	_x_in = _x_at_screen_frac(1.0 + LANE_OFF, _lane_z, cam, vp)
	_x_out = _x_at_screen_frac(-LANE_OFF, _lane_z, cam, vp)
	if _x_hi - _x_lo < 0.4 or _x_in <= _x_hi or _x_out >= _x_lo:
		return

	# Five of them must still fit between the lane's ends with a gap. This can only
	# SHRINK the card, so the lane stays at least as far back as it needs to be.
	_card_len = minf(_card_len, (_x_hi - _x_lo) / (5.0 * CARD_ASPECT * 1.28))
	# An ABSOLUTE floor, not a fraction of what the card wanted to be: what makes a
	# card unusable is being too small to READ, and that is a size on the table.
	if _card_len < 0.55:
		return
	_lane_back = minf(_lane_back, _card_len * LANE_BACK)

	# ...and one last WORLD check, because the projection is not the only thing that
	# can be wrong. A camera pose in which "above the chips on screen" is still inside
	# the ring of them is one to refuse rather than to trust.
	if -_lane_z < reach * 0.90:
		return

	_lane_ok = true


# The world z on the felt whose projection falls on screen row `py`. Bisected: the
# closed form needs the camera's elevation, its lens and its slide, and the
# projection is already the authority on all three.
# The lane's centre is set back by a CARD's worst-case half-diagonal (see LANE_BACK),
# which is right for a card and wrong for everything smaller: a chip or a roulette
# ball parked there sits at the very top of the frame, half into the rail. This is
# the same lane, moved forward by the room the object does not need — so it stays
# above the chips (the lane's FRONT edge is what was solved to clear them) and is
# drawn where it can be seen.
func _front_z(radius: float) -> float:
	return _lane_z + maxf(0.0, _lane_back - radius)


func _z_at_screen_y(py: float, cam: Camera3D) -> float:
	var near := -0.20
	var far := -70.0
	if _py_of(far, cam) > py:
		return 1.0                  # even 70 m back is still below that row
	for _i in 24:
		var mid := (near + far) * 0.5
		if _py_of(mid, cam) > py:
			near = mid
		else:
			far = mid
	return far


func _py_of(z: float, cam: Camera3D) -> float:
	var p := Vector3(0.0, 0.0, z)
	if cam.is_position_behind(p):
		return -1e9
	return cam.unproject_position(p).y


# The world x, at depth z on the felt, that projects to `frac` of the frame's width.
# The projection is linear in x at a fixed depth, so two probes and a solve — no
# bisection needed and none used.
func _x_at_screen_frac(frac: float, z: float, cam: Camera3D, vp: Vector2) -> float:
	var a := Vector3(0.0, 0.0, z)
	var b := Vector3(1.0, 0.0, z)
	if cam.is_position_behind(a) or cam.is_position_behind(b):
		return 0.0
	var sa := cam.unproject_position(a).x
	var sb := cam.unproject_position(b).x
	if absf(sb - sa) < 0.0001:
		return 0.0
	return (vp.x * frac - sa) / (sb - sa)


# How long something lying flat at depth z may be before it covers more than
# CARD_SCREEN of the frame's height.
func _fit_len(want: float, z: float, cam: Camera3D, vp: Vector2) -> float:
	var a := Vector3(0.0, 0.0, z)
	var b := Vector3(0.0, 0.0, z + want)
	if cam.is_position_behind(a) or cam.is_position_behind(b):
		return 0.0
	var px := absf(cam.unproject_position(b).y - cam.unproject_position(a).y)
	if px <= 0.5:
		return want
	return want * minf(1.0, (vp.y * CARD_SCREEN) / px)


# ---------------------------------------------------------------------------
# Starting an event
# ---------------------------------------------------------------------------
# The player has just completed round `round_no`. Every third one, ONE randomly
# chosen event runs; every other round is answered 0.0 and nothing happens.
#
# Returns THE SECONDS THE ROUND MUST STAY FROZEN, and that is the only thing that
# ever flows back to the game.
#
# ---------------------------------------------------------------------------
# THE SMALL EVENTS ASK FOR NO FREEZE AT ALL, AND THAT IS THE DESIGN
# ---------------------------------------------------------------------------
# This function starts a two-to-three second event and then returns 0.0. It is the
# one place this skin deliberately parts company with the Magical Lake and Ice
# Kingdom, both of which freeze the round for the whole of every milestone.
#
# They have to. The lake's frog crosses the MIDDLE of the frame and its level-8 party
# surfaces five pads among the buttons; Ice Kingdom grows a ring of crystals through
# the play area. An event over the top of the next round's sequence would be an event
# the player has to read past.
#
# This one does not, because of where it is: every object is on THE LANE, which is
# solved to sit above the topmost chip on screen and is asserted to by
# tools/casino_verify.tscn on all three boards. Cards can slide across the back of
# the table while the six chips flash their sequence underneath, and neither is in
# the other's way. So the table stays alive while the game carries on, which is what
# a casino table actually does — and the player is never made to wait for a flourish.
#
# The ROYAL FLUSH is the exception and DOES freeze (see start_flush): it is the
# celebration, it carries a banner, and the round has nothing to do while it runs.
func start_event(round_no: int) -> float:
	if not _lane_ok or _kind >= 0 or round_no <= 0 or round_no % EVERY != 0:
		return 0.0
	# Refuse a repeat if the completion somehow fires twice for one round.
	if round_no == _last_round:
		return 0.0
	_last_round = round_no
	_tier = tier_for(round_no)

	# The seed is the ROUND, so occurrence N always looks like occurrence N. That is
	# worth more than fresh randomness: it makes an event reproducible in a harness,
	# and it stops the same event looking different on a replay of the same round.
	_rng.seed = 0x0ca5e0 + round_no * 977

	# A SHUFFLED BAG, not a random draw. "Random, but never twice running" was the
	# first version and it is not enough: measured over fourteen milestones it left
	# one of the six unseen, which is a player who plays for four minutes and never
	# finds out the table has a roulette ball in it. A bag of all six, drawn without
	# replacement and reshuffled when it empties, guarantees every event inside any
	# six occurrences AND still never repeats across the join.
	if _bag.is_empty():
		_bag = _fill_bag()
	var pick := int(_bag.pop_back())
	_prev = pick
	_begin(pick, _duration(pick))
	# ...and no freeze. See the block above.
	return 0.0


# Six events in a random order, with the one that comes out FIRST guaranteed not to
# be the one that just played — which is the only place a bag can repeat.
func _fill_bag() -> Array:
	var bag: Array = []
	for i in EVENT_COUNT:
		bag.append(i)
	for i in range(bag.size() - 1, 0, -1):
		var j := _rng.randi() % (i + 1)
		var t: Variant = bag[i]
		bag[i] = bag[j]
		bag[j] = t
	if _prev >= 0 and int(bag[bag.size() - 1]) == _prev:
		var t2: Variant = bag[0]
		bag[0] = bag[bag.size() - 1]
		bag[bag.size() - 1] = t2
	return bag


# The player has just completed level `level_no`. Every eighth is the ROYAL FLUSH.
func start_flush(level_no: int) -> float:
	if not _lane_ok or level_no <= 0 or level_no % FINALE_EVERY != 0:
		return 0.0
	if level_no == _last_level:
		return 0.0
	_last_level = level_no
	# The finale outranks a running event rather than queueing behind it: this is
	# fired in the same instant as the every-third one on rounds 24, 48, ... and the
	# small one has had no frame to draw yet.
	if _kind >= 0:
		stop()
	_tier = 2
	_rng.seed = 0x0ca5f1 + level_no * 613
	_begin(EV_FLUSH, T_FLUSH)
	return _len + HOLD


static func _duration(kind: int) -> float:
	match kind:
		EV_COMMUNITY: return T_COMMUNITY
		EV_ROULETTE: return T_ROULETTE
		EV_CASCADE: return T_CASCADE
		EV_FLIP: return T_FLIP
		EV_DEAL: return T_DEAL
		EV_LIGHTS: return T_LIGHTS
	return 0.0


func _begin(kind: int, secs: float) -> void:
	_clear_all()
	_kind = kind
	_flush = kind == EV_FLUSH
	_t = 0.0
	_prev_t = -1.0
	_len = secs
	match kind:
		EV_COMMUNITY: _lay_community()
		EV_ROULETTE: _lay_roulette()
		EV_CASCADE: _lay_cascade()
		EV_FLIP: _lay_flip()
		EV_DEAL: _lay_deal()
		EV_LIGHTS: _lay_lights()
		EV_FLUSH: _lay_flush()
	_pose(0.0)


# Drop everything, now. Called when a finale outranks a running event, and by the
# board when the casino stops being the equipped background.
func stop() -> void:
	_kind = -1
	_flush = false
	_t = 0.0
	_clear_all()


func active() -> bool:
	return _kind >= 0


func _clear_all() -> void:
	_cards.clear()
	_chips.clear()
	_sp_p.clear()
	_sp_v.clear()
	_sp_col.clear()
	_sp_age.resize(0)
	_sp_life.resize(0)
	_sp_size.resize(0)
	if _cards_mm != null:
		_cards_mm.multimesh.instance_count = 0
	if _chips_mm != null:
		_chips_mm.multimesh.instance_count = 0
	if _sparks_mm != null:
		_sparks_mm.multimesh.instance_count = 0
	if _shadow_mm != null:
		_shadow_mm.multimesh.instance_count = 0
	if _ball != null:
		_ball.visible = false
	_push_felt(0.0, -99.0)


# ---------------------------------------------------------------------------
# The clock
# ---------------------------------------------------------------------------
# Returns true while anything is still alive, which is what keeps CasinoWorld's
# `_process` running and what turns it off again.
func tick(dt: float) -> bool:
	if _kind < 0:
		return false
	_prev_t = _t
	_t += dt
	_step_sparks(dt)
	if _t >= _len:
		# The sparks are allowed to outlive the timeline by their own life, so a
		# burst at the end falls rather than vanishing. Nothing else is.
		_cards.clear()
		_chips.clear()
		if _ball != null:
			_ball.visible = false
		_push_felt(0.0, -99.0)
		_pose(_len)
		if _sp_age.is_empty():
			_kind = -1
			_clear_all()
			return false
		return true
	_pose(_t)
	_beat(_t)
	return true


# True on the frame that crosses `mark`. The event's beats — the one or two sounds
# each one is allowed — fire off this rather than off a timer, so a dropped frame
# moves a beat instead of losing it.
func _cross(t: float, mark: float) -> bool:
	return _prev_t < mark and t >= mark


# ===========================================================================
# THE SIX EVENTS
# ===========================================================================
# Each `_lay_*` writes a list of objects and their marks, once, at t = 0. Nothing
# below runs per frame; `_pose` does, and it is one closed-form function of `_t` for
# every object in the list. That is what makes an event cancellable at any instant
# and what keeps the per-frame cost a fixed pose pass.

# The board's button centres, kept only so the two lighting events can put a glint
# beside each chip WITHOUT touching a button. See _lay_lights.
var _centres := PackedVector2Array()

# Continuous emitters use an accumulator rather than "one per frame": the frame rate
# here moves between 15 and 60 Hz (see CasinoWorld.idle_hz_for), and a per-frame
# emitter makes an event four times as dense on the boards that redraw fastest.
var _emit_acc := 0.0


# --- EVENT 1: COMMUNITY CARDS --------------------------------------------
# Two cards, three from tier 1. They slide on one after another from the right,
# each turning slightly as it lands and settling with a small bounce, sit for a
# beat, and slide away to the left.
func _lay_community() -> void:
	var n := 2 if _tier == 0 else 3
	var ranks := _shuffled_ranks()
	var step := _card_len * CARD_ASPECT * 1.24
	var x0 := -step * (float(n) - 1.0) * 0.5
	for i in n:
		var x: float = x0 + step * float(i)
		_cards.append(_card({
			"rank": ranks[i % ranks.size()],
			"up": true,
			"from": Vector3(_x_in + step * float(i) * 0.5, 0.0, _lane_z),
			"to": Vector3(x, 0.0, _lane_z),
			# A card thrown across felt arrives at an angle and straightens as it
			# stops. The residual is deliberately not zero: five cards all at
			# exactly 0 read as a printed strip rather than as dealt objects.
			"yaw0": 0.62,
			"yaw1": _rng.randf_range(-0.075, 0.075),
			"in_at": 0.10 + 0.20 * float(i),
			"in_len": 0.44,
			"out_at": _len - 0.78,
			"out_len": 0.64,
			"out_to": Vector3(_x_out - step * float(i) * 0.4, 0.0, _lane_z),
			"gold": 0.35 if _tier >= 2 else 0.0,
		}))


# --- EVENT 2: THE ROULETTE BALL ------------------------------------------
# Not a wheel. A ball appears over the lane, laps a small circle faster and faster,
# decelerates hard onto one point of the track, holds for a fraction of a second and
# POPS in a sparkle.
#
# A wheel was the first idea and is the wrong one at this scale: a roulette wheel big
# enough to read is a second board, and a second board on the table is exactly the
# clutter the brief rules out. What the player actually recognises is the BALL — the
# rattle, the lap, the drop — so that is all there is.
func _lay_roulette() -> void:
	# The track is squashed to 0.55 in z (see _pose_ball), so its z reach is
	# `_ball_r * 0.55` — capped against the lane's own clearance so the ball can
	# never come forward past where a card may be.
	_ball_r = clampf((_x_hi - _x_lo) * 0.155, 0.30, minf(0.95, _lane_back / 0.55))
	_ball_c = Vector3((_x_lo + _x_hi) * 0.5, 0.10, _front_z(_ball_r * 0.55))
	# The pocket it lands in: a fixed angle for this occurrence, so the same round
	# always lands on the same number.
	_ball_stop = _rng.randf() * TAU


# --- EVENT 3: THE CHIP CASCADE -------------------------------------------
# Five chips, up to nine at tier 2, slide and spin in from the right, run out along
# the lane, and two of them arrive at the same place and STACK. Then they all go.
#
# The stack is the point of the event. Chips crossing felt in a line is a conveyor;
# two of them ending up on top of each other is the thing a table full of chips
# actually does, and it is one extra y offset.
func _lay_cascade() -> void:
	var n := mini(5 + _tier * 2, MAX_CHIPS)
	var span := _x_hi - _x_lo
	# The pair that stacks. Two adjacent chips are given the same landing x and the
	# second a height, so it comes to rest ON the first.
	var pair := _rng.randi_range(1, maxi(n - 2, 1))
	var stack_x := _x_lo + span * _rng.randf_range(0.30, 0.70)
	# A chip prop is PROP_R across at scale 1 and the cascade draws it at up to
	# 1.35 x 1.18 of the board's own scale, so its own radius eats most of the lane's
	# clearance on a small board. What is left is all the z jitter it may have.
	var world := _card_len / CARD_LEN
	var chip_r := CasinoWorld.PROP_R * CASCADE_SCALE * 1.18 * world
	var jz := clampf(_lane_back - chip_r, 0.0, 0.16)
	# How high the chip that rides up onto its neighbour ends up. In the SAME units
	# the chip is drawn in — the props are scaled by 1.35 and by the board's own
	# world factor, so an unscaled STACK_STEP would leave the top chip floating on a
	# small board and buried on a large one.
	var lift_y := CasinoWorld.STACK_STEP * CASCADE_SCALE * world * 0.92
	var cz := _front_z(chip_r)
	for i in n:
		var lands_on_stack := i == pair or i == pair + 1
		var x: float = stack_x if lands_on_stack else \
			_x_lo + span * (0.06 + 0.88 * float(i) / float(maxi(n - 1, 1)))
		var lift: float = lift_y if i == pair + 1 else 0.0
		_chips.append({
			"from": Vector3(_x_in + 0.55 * float(i), lift, cz
				+ _rng.randf_range(-jz, jz)),
			"to": Vector3(x, lift, cz + _rng.randf_range(-jz * 0.75, jz * 0.75)),
			"in_at": 0.05 + 0.058 * float(i),
			"in_len": _rng.randf_range(0.50, 0.74),
			# Spin, in turns over the slide. A chip pushed across felt rolls on its
			# face; the number is high enough to read as a spin and low enough that
			# the eight edge inserts do not strobe.
			"spin": _rng.randf_range(2.2, 3.6) * (1.0 if _rng.randf() < 0.5 else -1.0),
			"out_at": _len - 0.66,
			"out_len": 0.58,
			"out_to": Vector3(_x_out - 0.5 * float(i), lift, cz),
			"tint": CASCADE_TINTS[_rng.randi() % CASCADE_TINTS.size()],
			"scale": _rng.randf_range(0.92, 1.18),
			"stacks": lands_on_stack,
		})


# --- EVENT 4: THE CARD FLIP ----------------------------------------------
# One big card slides to the middle of the lane face down, LIFTS as it turns over —
# a card is not flipped flat on the table, it is picked up on one edge — lands with
# a bounce showing a face, holds, and slides away.
func _lay_flip() -> void:
	var ranks := _shuffled_ranks()
	_cards.append(_card({
		"rank": ranks[0],
		"up": false,
		"size": 1.30,
		"from": Vector3(_x_in, 0.0, _lane_z),
		"to": Vector3((_x_lo + _x_hi) * 0.5, 0.0, _lane_z),
		"yaw0": 0.95,
		"yaw1": 0.0,
		"in_at": 0.05,
		"in_len": 0.52,
		"flip_at": 0.78,
		"flip_len": 0.40,
		"flip_lift": 0.22,
		"bounce_at": 1.18,
		"glow_at": 1.18,
		"glow_len": 0.9,
		"out_at": _len - 0.72,
		"out_len": 0.66,
		"out_to": Vector3(_x_out, 0.0, _lane_z),
		"gold": 0.55 if _tier >= 1 else 0.25,
	}))


# --- EVENT 5: THE GOLDEN DEAL --------------------------------------------
# A glowing deck appears at the right end of the lane and deals three cards fast —
# SLAP, SLAP, SLAP — each landing with a bounce and a spray of gold. The deck fades,
# the three sit for a beat, and they go.
#
# The stagger is 115 ms and that is not a taste call: AudioManager's deal sound is
# three slaps baked into ONE buffer at 0 / 115 / 230 ms (it has to be one buffer —
# the ambience channel is a single player, so three calls would be one slap). The
# landings are laid on those marks so the picture and the sound are the same event.
# How much bigger than the table's DRESSING a cascade chip is drawn. The dressing's
# scale is right for something four metres out in the gutter; a chip that is the
# subject of an event has to hold its own beside a card 1.55 long.
const CASCADE_SCALE := 1.6

const DEAL_STAGGER := 0.115
const DEAL_SLIDE := 0.30
const DEAL_FIRST := 0.35


func _lay_deal() -> void:
	var ranks := _shuffled_ranks()
	var deck := Vector3(_x_hi + _card_len * CARD_ASPECT * 0.55, 0.0, _lane_z)
	# The deck: four face-down cards stacked, glowing gold. Not a modelled box — a
	# short stack of the same card mesh reads as a deck from this angle and costs
	# four instances of a MultiMesh that is already there.
	for k in 4:
		_cards.append(_card({
			"rank": RANK_A,
			"up": false,
			"from": deck + Vector3(0.0, 0.0026 * float(k), 0.0),
			"to": deck + Vector3(0.0, 0.0026 * float(k), 0.0),
			"yaw0": 0.06 * float(k),
			"yaw1": 0.06 * float(k),
			"in_at": 0.0,
			"in_len": 0.22,
			"hop": 0.0,             # it appears where it is; it does not fly in
			"pop_in": true,
			"out_at": 1.05,
			"out_len": 0.40,
			"fade_out": true,
			"gold": 1.0,
			"glow_at": 0.0,
			"glow_len": 1.45,
		}))
	var step := _card_len * CARD_ASPECT * 1.24
	var x0 := (_x_lo + _x_hi) * 0.5 - step
	for i in 3:
		_cards.append(_card({
			"rank": ranks[i],
			"up": true,
			"from": deck,
			"to": Vector3(x0 + step * float(2 - i), 0.0, _lane_z),
			"yaw0": 0.55,
			"yaw1": _rng.randf_range(-0.06, 0.06),
			"in_at": DEAL_FIRST + DEAL_STAGGER * float(i),
			"in_len": DEAL_SLIDE,
			"hop": CARD_HOP * 1.35,
			"bounce_at": DEAL_FIRST + DEAL_SLIDE + DEAL_STAGGER * float(i),
			"sparkle_at": DEAL_FIRST + DEAL_SLIDE + DEAL_STAGGER * float(i),
			"out_at": _len - 0.72,
			"out_len": 0.66,
			"out_to": Vector3(_x_out - step * float(i) * 0.35, 0.0, _lane_z),
			"gold": 0.85,
		}))


# --- EVENT 6: THE JACKPOT LIGHTS -----------------------------------------
# The only event with no objects in it. The table lighting comes up, a warm glow
# travels once around the outer edge of the felt, gold hangs in the air, and it all
# goes back down.
#
# "The poker chips receive a subtle highlight" is done by LIGHTING THEM, not by
# touching them: the lift is applied to the lamp pool, which is the ellipse the six
# chips are standing in, and a few grains of gold rise from just outside each chip's
# rim. Nothing in this file may write a button's material — those belong to the
# board's emission state machine, and a skin that borrows one has taken the flash
# the player is reading.
const LIGHTS_UP := 0.55
const LIGHTS_DOWN := 0.60
const LIGHTS_SWEEP0 := 0.18
const LIGHTS_SWEEP1 := 2.25


func _lay_lights() -> void:
	pass          # everything it does is in _pose and _emit


# --- THE ROYAL FLUSH -----------------------------------------------------
# The level-8 celebration, and the only thing on this table that is longer than
# three seconds.
#
#   0.05 - 0.87   five cards slide on from the right, face down, in order
#   1.00 - 1.84   the first four turn over one at a time: 10, J, Q, K
#   1.90 - 2.42   the fifth does NOT. It glows, it shakes, and gold gathers on it
#   2.42 - 2.62   it SLAMS open: A
#   2.62          the burst — gold everywhere, every card bounces, the table lifts
#   3.70 - 4.30   the five slide away and the table is a table again
#
# The camera never moves and the board is never covered: every card is on the lane,
# which is above the top row of chips by construction.
const RF_IN := 0.05
const RF_IN_STAGGER := 0.11
const RF_IN_LEN := 0.38
const RF_FLIP0 := 1.00
const RF_FLIP_STAGGER := 0.20
const RF_FLIP_LEN := 0.24
const RF_SHAKE := 1.90
const RF_SHAKE_LEN := 0.52
const RF_SLAM := 2.42
const RF_SLAM_LEN := 0.20
const RF_BURST := 2.62
const RF_OUT := 3.70
const RF_OUT_LEN := 0.60

# The hand, in the order it is laid down and read.
const ROYAL := [RANK_10, RANK_J, RANK_Q, RANK_K, RANK_A]


func _lay_flush() -> void:
	var step := _card_len * CARD_ASPECT * 1.22
	var x0 := (_x_lo + _x_hi) * 0.5 - step * 2.0
	for i in 5:
		var last := i == 4
		var d := {
			"rank": ROYAL[i],
			"up": false,
			"from": Vector3(_x_in + step * float(i) * 0.45, 0.0, _lane_z),
			"to": Vector3(x0 + step * float(i), 0.0, _lane_z),
			"yaw0": 0.52,
			"yaw1": 0.0,
			"in_at": RF_IN + RF_IN_STAGGER * float(i),
			"in_len": RF_IN_LEN,
			"hop": CARD_HOP,
			"out_at": RF_OUT,
			"out_len": RF_OUT_LEN,
			"out_to": Vector3(_x_out - step * float(i) * 0.3, 0.0, _lane_z),
			"gold": 1.0,
			"bounce_at": RF_BURST,
		}
		if last:
			# The fifth card is the whole event: it waits while the other four are
			# read, gathers light, shakes, and then turns over harder and faster
			# than any of them.
			d["flip_at"] = RF_SLAM
			d["flip_len"] = RF_SLAM_LEN
			d["flip_lift"] = 0.30
			d["slam"] = true
			d["shake_at"] = RF_SHAKE
			d["shake_len"] = RF_SHAKE_LEN
			d["glow_at"] = RF_SHAKE
			d["glow_len"] = RF_OUT - RF_SHAKE
		else:
			d["flip_at"] = RF_FLIP0 + RF_FLIP_STAGGER * float(i)
			d["flip_len"] = RF_FLIP_LEN
			d["flip_lift"] = 0.12
			d["glow_at"] = RF_BURST
			d["glow_len"] = 0.9
		_cards.append(_card(d))


# Fill in every field a card may have, so `_pose` never has to ask whether one is
# present. A Dictionary with holes in it is how a pose function grows a branch per
# field; this is one `merge` instead.
func _card(d: Dictionary) -> Dictionary:
	var base := {
		"rank": RANK_A, "up": true, "size": 1.0,
		"from": Vector3.ZERO, "to": Vector3.ZERO, "out_to": Vector3.ZERO,
		"yaw0": 0.0, "yaw1": 0.0,
		"in_at": 0.0, "in_len": 0.4, "hop": CARD_HOP,
		"flip_at": -1.0, "flip_len": 0.3, "flip_lift": 0.0, "slam": false,
		"shake_at": -1.0, "shake_len": 0.0,
		"glow_at": -1.0, "glow_len": 0.0,
		"bounce_at": -1.0, "sparkle_at": -1.0,
		"out_at": 1e9, "out_len": 0.5, "fade_out": false, "pop_in": false,
		"gold": 0.0,
	}
	base.merge(d, true)
	return base


func _shuffled_ranks() -> Array:
	var r: Array = FLIP_RANKS.duplicate()
	for i in range(r.size() - 1, 0, -1):
		var j := _rng.randi() % (i + 1)
		var tmp: Variant = r[i]
		r[i] = r[j]
		r[j] = tmp
	return r


# ===========================================================================
# POSING
# ===========================================================================
# One pass, every frame an event is running, over at most 12 cards + 16 chips + 72
# sparks + their shadows. Every object's pose is a CLOSED FORM in `t`: nothing here
# integrates, nothing accumulates, and nothing has to be unwound to stop an event.
# (The sparks are the single exception and are integrated, because a ballistic arc
# with drag has no closed form worth writing.)

# How high a card is before its contact shadow has fully spread. Purely a look
# number: the shadow tightens and darkens as an object comes down, which is the only
# cue that says how far above the felt it is at a camera this shallow.
const SHADOW_H := 0.34


func _pose(t: float) -> void:
	# Emission first, so a spark thrown on this beat is drawn on this frame rather
	# than on the next one. `_push_sparks` at the bottom is what uploads them.
	_emit(t)
	var world := _card_len / CARD_LEN            # this board's scale for everything
	var cxf: Array[Transform3D] = []
	var ccol: Array[Color] = []
	var ccd: Array[Color] = []
	var sxf: Array[Transform3D] = []
	var scol: Array[Color] = []

	for c: Dictionary in _cards:
		var in_at: float = c["in_at"]
		if t < in_at:
			continue
		var in_len: float = maxf(c["in_len"], 0.0001)
		var u := clampf((t - in_at) / in_len, 0.0, 1.0)
		var e := _out_cubic(u)
		var pos: Vector3 = (c["from"] as Vector3).lerp(c["to"] as Vector3, e)
		var y: float = float(c["hop"]) * sin(PI * u) * world
		var alpha := 1.0
		var sc := world * float(c["size"])

		# The deck's cards do not slide in, they appear — a back-eased scale pop.
		if bool(c["pop_in"]):
			sc *= _out_back(u)
			alpha = smoothstep(0.0, 0.35, u)

		# Landing: a short damped bounce. This is the whole difference between a
		# card that was placed and a card that was thrown.
		var since := t - (in_at + in_len)
		if since >= 0.0 and since < 0.26:
			y += 0.055 * world * exp(-since * 14.0) * absf(sin(since * 26.0))

		# The flip.
		var a0: float = 0.0 if bool(c["up"]) else PI
		var ang := a0
		var flip_at: float = c["flip_at"]
		if flip_at >= 0.0 and t >= flip_at:
			var f := clampf((t - flip_at) / maxf(float(c["flip_len"]), 0.0001), 0.0, 1.0)
			var ef := _slam(f) if bool(c["slam"]) else _in_out(f)
			ang = lerpf(a0, PI - a0, ef)
			# A card is turned over by being picked up on one edge, not spun flat.
			y += float(c["flip_lift"]) * sin(PI * f) * world

		# The anticipation on the fifth Royal Flush card: a tightening tremor that
		# GROWS, which is what makes it read as pressure building rather than as a
		# loose object.
		var shake_at: float = c["shake_at"]
		if shake_at >= 0.0 and t >= shake_at and t < shake_at + float(c["shake_len"]):
			var k := (t - shake_at) / maxf(float(c["shake_len"]), 0.0001)
			var amp := 0.016 * world * (0.20 + 0.80 * k * k)
			pos.x += sin(t * 58.0) * amp
			pos.z += sin(t * 71.0) * amp * 0.7
			sc *= 1.0 + 0.035 * k * absf(sin(t * 21.0))

		# The burst bounce, shared by every card in the Royal Flush.
		var bounce_at: float = c["bounce_at"]
		if bounce_at >= 0.0:
			var s2 := t - bounce_at
			if s2 >= 0.0 and s2 < 0.36:
				y += 0.075 * world * exp(-s2 * 11.0) * absf(sin(s2 * 20.0))

		# Glow.
		var glow := 0.0
		var glow_at: float = c["glow_at"]
		if glow_at >= 0.0 and t >= glow_at:
			var g := clampf((t - glow_at) / maxf(float(c["glow_len"]), 0.0001), 0.0, 1.0)
			glow = sin(PI * pow(g, 0.6))

		# Leaving.
		var out_at: float = c["out_at"]
		if t >= out_at:
			var v := clampf((t - out_at) / maxf(float(c["out_len"]), 0.0001), 0.0, 1.0)
			if bool(c["fade_out"]):
				alpha *= 1.0 - smoothstep(0.0, 1.0, v)
				sc *= 1.0 - 0.18 * v
			else:
				pos = pos.lerp(c["out_to"] as Vector3, _in_cubic(v))
				alpha *= 1.0 - smoothstep(0.62, 1.0, v)
		if alpha <= 0.004:
			continue

		var yaw: float = lerpf(float(c["yaw0"]), float(c["yaw1"]), e)
		var b := Basis(Vector3.UP, yaw) * Basis(Vector3(0.0, 0.0, 1.0), ang)
		b = b.scaled(Vector3(sc, sc, sc))
		var p := Vector3(pos.x, CasinoWorld.CARD_Y + y, pos.z)
		cxf.append(Transform3D(b, p))
		ccol.append(Color(1.0, 1.0, 1.0, alpha))
		# rank / face / glow / gold, in that order. The rank is divided down because
		# MultiMesh custom data is a colour and is happiest inside 0..1; the shader
		# multiplies it back and rounds.
		ccd.append(Color(float(c["rank"]) / 8.0, 1.0 if cos(ang) > 0.0 else 0.0,
			glow, float(c["gold"])))
		_shadow(sxf, scol, p, sc * 0.80, alpha)

	var pxf: Array[Transform3D] = []
	var pcol: Array[Color] = []
	var pcd: Array[Color] = []
	for c: Dictionary in _chips:
		var in_at: float = c["in_at"]
		if t < in_at:
			continue
		var in_len: float = maxf(c["in_len"], 0.0001)
		var u := clampf((t - in_at) / in_len, 0.0, 1.0)
		var e := _out_cubic(u)
		var pos: Vector3 = (c["from"] as Vector3).lerp(c["to"] as Vector3, e)
		var alpha := 1.0
		var out_at: float = c["out_at"]
		if t >= out_at:
			var v := clampf((t - out_at) / maxf(float(c["out_len"]), 0.0001), 0.0, 1.0)
			pos = pos.lerp(c["out_to"] as Vector3, _in_cubic(v))
			alpha = 1.0 - smoothstep(0.62, 1.0, v)
		if alpha <= 0.004:
			continue
		# A chip that lands on another one drops the last centimetre rather than
		# arriving at its height — otherwise the stack assembles itself in mid-air.
		var y: float = pos.y
		if bool(c["stacks"]):
			y *= _out_cubic(clampf((u - 0.72) / 0.28, 0.0, 1.0))
		var sc := (_card_len / CARD_LEN) * float(c["scale"]) * CASCADE_SCALE
		var b := Basis(Vector3.UP, float(c["spin"]) * TAU * e).scaled(Vector3(sc, sc, sc))
		var p := Vector3(pos.x, y, pos.z)
		pxf.append(Transform3D(b, p))
		var tint: Color = c["tint"]
		pcol.append(Color(tint.r, tint.g, tint.b, alpha))
		pcd.append(Color(0.0, 0.0, 0.0, 0.0))
		_shadow(sxf, scol, p, sc * 0.42, alpha)

	# The roulette ball.
	if _kind == EV_ROULETTE:
		_pose_ball(t)

	_fill(_cards_mm.multimesh, cxf, ccol, ccd, MAX_CARDS)
	_fill(_chips_mm.multimesh, pxf, pcol, pcd, MAX_CHIPS)
	_fill_shadows(sxf, scol)
	_push_sparks()
	_pose_lighting(t)


# One contact shadow, laid flat under whatever is above it. Generated rather than
# authored, so every object in every event has one and none can be forgotten.
func _shadow(xf: Array[Transform3D], col: Array[Color], p: Vector3, size: float,
		alpha: float) -> void:
	if xf.size() >= MAX_SHADOWS:
		return
	var h := clampf(p.y / SHADOW_H, 0.0, 1.0)
	var spread := size * (1.0 + 0.75 * h)
	xf.append(Transform3D(Basis().scaled(Vector3(spread, 1.0, spread)),
		Vector3(p.x, SHADOW_Y, p.z)))
	col.append(Color(1.0, 1.0, 1.0, alpha * (0.62 - 0.42 * h)))


func _fill_shadows(xf: Array[Transform3D], col: Array[Color]) -> void:
	var mm := _shadow_mm.multimesh
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_color(i, col[i])


static func _fill(mm: MultiMesh, xf: Array[Transform3D], col: Array[Color],
		cd: Array[Color], cap: int) -> void:
	var n := mini(xf.size(), cap)
	mm.instance_count = n
	for i in n:
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_color(i, col[i])
		mm.set_instance_custom_data(i, cd[i])


# ---------------------------------------------------------------------------
# The roulette ball
# ---------------------------------------------------------------------------
# Three phases on one clock: the ball is driven faster and faster, released and
# decelerated hard onto one point of the track, and popped.
#
# The "motion blur" is a TRAIL of sparks laid at the ball's own position, one every
# few milliseconds — which is what motion blur is, and which costs nothing extra
# because the spark system was going to be there for the pop anyway.
const BALL_IN := 0.26
const BALL_SPIN_END := 2.02
const BALL_SETTLE := 2.30
const BALL_POP := 2.52
const BALL_LAPS := 4.6            # how many times round, over the whole spin


func _pose_ball(t: float) -> void:
	if t >= BALL_POP or t < 0.0:
		_ball.visible = false
		return
	_ball.visible = true
	# Angle: an ease that starts slow, runs fast, and stops hard. `pow(u, 0.42)` on
	# the way out is the deceleration — a ball leaving the rim loses most of its
	# speed in the last quarter turn, and a linear stop reads as a motor switching
	# off.
	var u := clampf(t / BALL_SPIN_END, 0.0, 1.0)
	var turn := smoothstep(0.0, 1.0, pow(u, 0.62)) * BALL_LAPS * TAU
	var a := _ball_stop + turn
	var r := _ball_r
	var lift := 0.0
	if t < BALL_IN:
		# Dropping in.
		var v := t / BALL_IN
		lift = (1.0 - _out_cubic(v)) * 0.55
		r *= 0.72 + 0.28 * _out_cubic(v)
	elif t > BALL_SPIN_END:
		# Off the rim and into the pocket: it falls inward and wobbles to a stop.
		var v := clampf((t - BALL_SPIN_END) / (BALL_SETTLE - BALL_SPIN_END), 0.0, 1.0)
		r *= 1.0 - 0.34 * _out_cubic(v)
		a += sin(v * PI * 3.0) * (1.0 - v) * 0.16
		lift = (1.0 - v) * 0.03
	var p := _ball_c + Vector3(cos(a) * r, lift, sin(a) * r * 0.55)
	# The track is an ELLIPSE in world space, squashed in z, because the camera is
	# shallow: a true circle on the felt projects to a very flat oval that reads as
	# a line rather than as a lap. This is a composition correction and it is the
	# same one every ground disc in this project needs.
	var s := 1.0
	if t < BALL_IN:
		s = _out_back(t / BALL_IN)
	elif t > BALL_SETTLE:
		# A held beat, and then it goes.
		s = 1.0 + 0.12 * sin((t - BALL_SETTLE) * 18.0) * (1.0 - (t - BALL_SETTLE) / 0.22)
	s *= _card_len / CARD_LEN
	_ball.transform = Transform3D(Basis().scaled(Vector3(s, s, s)), p)
	_ball_a = a
	_ball_mat.set_shader_parameter("hot",
		1.0 if t < BALL_SPIN_END else 1.0 - clampf((t - BALL_SPIN_END) / 0.5, 0.0, 1.0))


# ---------------------------------------------------------------------------
# Lighting
# ---------------------------------------------------------------------------
# The two events that change the TABLE rather than putting something on it. Both
# work through two uniforms on the felt's own material and touch nothing else.
func _pose_lighting(t: float) -> void:
	if _felt == null:
		return
	var lift := 0.0
	var sweep := -99.0
	if _kind == EV_LIGHTS:
		lift = smoothstep(0.0, LIGHTS_UP, t) \
			* (1.0 - smoothstep(_len - LIGHTS_DOWN, _len, t))
		if t > LIGHTS_SWEEP0 and t < LIGHTS_SWEEP1:
			sweep = -PI + TAU * (t - LIGHTS_SWEEP0) / (LIGHTS_SWEEP1 - LIGHTS_SWEEP0)
	elif _flush:
		# A short, hard lift on the burst and a single sweep out of it. Deliberately
		# briefer than the jackpot event's: this one is punctuation, not weather.
		lift = smoothstep(RF_BURST - 0.10, RF_BURST + 0.16, t) \
			* (1.0 - smoothstep(RF_BURST + 0.9, RF_OUT + 0.2, t))
		if t > RF_BURST and t < RF_BURST + 1.30:
			sweep = -PI + TAU * (t - RF_BURST) / 1.30
	_push_felt(lift, sweep)


func _push_felt(lift: float, sweep: float) -> void:
	if _felt == null:
		return
	_felt.set_shader_parameter("ev_lift", lift)
	_felt.set_shader_parameter("ev_sweep", sweep)


# ---------------------------------------------------------------------------
# Sparks
# ---------------------------------------------------------------------------
# ONE particle system, shared by every event that needs particles: the ball's trail
# and its pop, the golden deal's landings, the jackpot lights' rising gold, and the
# Royal Flush's gather and burst. Seventy-two of them, integrated on the CPU because
# a ballistic arc with drag has no closed form worth writing, and drawn as one
# additive MultiMesh billboarded in view space.
const SPARK_G := 1.9              # gravity, in board units


func _spark(p: Vector3, v: Vector3, life: float, size: float, col: Color) -> void:
	if _sp_age.size() >= MAX_SPARKS:
		return
	_sp_p.append(p)
	_sp_v.append(v)
	_sp_age.append(0.0)
	_sp_life.append(life)
	_sp_size.append(size)
	_sp_col.append(col)


func _burst(at: Vector3, n: int, speed: float, life: float, size: float,
		col: Color) -> void:
	for _i in n:
		var a := _rng.randf() * TAU
		var up := _rng.randf_range(0.45, 1.0)
		var s := speed * _rng.randf_range(0.55, 1.25)
		_spark(at, Vector3(cos(a) * s * 0.8, up * s, sin(a) * s * 0.5),
			life * _rng.randf_range(0.7, 1.2), size * _rng.randf_range(0.7, 1.35), col)


func _step_sparks(dt: float) -> void:
	var i := _sp_age.size() - 1
	while i >= 0:
		_sp_age[i] += dt
		if _sp_age[i] >= _sp_life[i]:
			_sp_p.remove_at(i)
			_sp_v.remove_at(i)
			_sp_col.remove_at(i)
			_sp_age.remove_at(i)
			_sp_life.remove_at(i)
			_sp_size.remove_at(i)
		else:
			var v: Vector3 = _sp_v[i]
			v.y -= SPARK_G * dt
			v *= 1.0 - minf(dt * 1.6, 0.6)
			_sp_v[i] = v
			_sp_p[i] = (_sp_p[i] as Vector3) + v * dt
		i -= 1


func _push_sparks() -> void:
	var mm := _sparks_mm.multimesh
	var n := _sp_age.size()
	mm.instance_count = n
	var world := _card_len / CARD_LEN
	for i in n:
		var u := _sp_age[i] / maxf(_sp_life[i], 0.0001)
		mm.set_instance_transform(i, Transform3D(Basis(), _sp_p[i]))
		var c: Color = _sp_col[i]
		# Fade in over the first tenth so a spark is never born at full brightness,
		# and out over the last half.
		mm.set_instance_color(i, Color(c.r, c.g, c.b,
			smoothstep(0.0, 0.10, u) * (1.0 - smoothstep(0.45, 1.0, u))))
		mm.set_instance_custom_data(i,
			Color(_sp_size[i] * world * (1.0 - 0.45 * u), 0.0, 0.0, 0.0))


# Continuous emission, per event. Rate-based rather than per-frame: this scene
# redraws at 15 Hz at rest and 60 Hz during an event (CasinoWorld.idle_hz_for), and
# a per-frame emitter would make the same event four times as dense on the board
# that happens to be redrawing fastest.
func _emit(t: float) -> void:
	var world := _card_len / CARD_LEN
	var gold := Color(SPARK_GOLD.r, SPARK_GOLD.g, SPARK_GOLD.b)
	var white := Color(SPARK_WHITE.r, SPARK_WHITE.g, SPARK_WHITE.b)

	if _kind == EV_ROULETTE:
		# The trail. One spark every few milliseconds AT THE BALL, which is what a
		# motion blur is, and it stops the moment the ball does.
		if t < BALL_SPIN_END and t > BALL_IN:
			# The trail IS the motion blur, and it has to be big enough to blur with:
			# at 0.055 the ball left a dotted line rather than a streak.
			_rate(t, 90.0, func() -> void:
				_spark(_ball.position, Vector3(0.0, 0.10, 0.0), 0.26,
					0.105 * world, white))
		if _cross(t, BALL_POP):
			_burst(_ball.position, 14 + _tier * 5, 1.5, 0.75, 0.115 * world, gold)
			_burst(_ball.position, 6, 0.9, 0.55, 0.085 * world, white)

	if _kind == EV_LIGHTS:
		if t > 0.15 and t < _len - LIGHTS_DOWN:
			var rate := 14.0 + 9.0 * float(_tier)
			_rate(t, rate, func() -> void:
				# Around the buttons — the "the chips receive a highlight" half of
				# this event — and out in the gutters, in the same draw. Every
				# candidate is checked against `_clear_of_chips`, so gold rises
				# BESIDE a chip and never in front of one.
				var at := Vector3.INF
				for _try in 6:
					var a := _rng.randf() * TAU
					var p := Vector3.ZERO
					if not _centres.is_empty() and _rng.randf() < 0.70:
						var c: Vector2 = _centres[_rng.randi() % _centres.size()]
						var rr := _rng.randf_range(1.45, 1.90)
						p = Vector3(c.x + cos(a) * rr, 0.06, c.y + sin(a) * rr)
					else:
						var rr := _reach * _rng.randf_range(1.30, 1.95)
						p = Vector3(cos(a) * rr, 0.05, sin(a) * rr)
					if _clear_of_chips(p, DRIFT):
						at = p
						break
				if at == Vector3.INF:
					return
				_spark(at, Vector3(_rng.randfn(0.0, 0.10), _rng.randf_range(0.55, 1.10),
					_rng.randfn(0.0, 0.08)), _rng.randf_range(0.9, 1.5),
					0.095 * world, gold))

	if _kind == EV_CASCADE:
		for c: Dictionary in _chips:
			var land: float = float(c["in_at"]) + float(c["in_len"])
			if bool(c["stacks"]) and _cross(t, land):
				_burst((c["to"] as Vector3) + Vector3(0.0, 0.05, 0.0), 5, 0.5, 0.4,
					0.035 * world, white)

	if _kind == EV_DEAL or _flush:
		for c: Dictionary in _cards:
			var sp: float = c["sparkle_at"]
			if sp >= 0.0 and _cross(t, sp):
				_burst((c["to"] as Vector3) + Vector3(0.0, 0.03, 0.0),
					6 + _tier * 3, 0.85, 0.55, 0.050 * world, gold)

	if _flush:
		# The gather: gold converging ON the fifth card while it shakes. Emitted OUT
		# at it from a ring and given an inward velocity, because particles arriving
		# read as pressure building and particles leaving read as something already
		# over.
		if t > RF_SHAKE and t < RF_SLAM and _cards.size() > 4:
			var target: Vector3 = (_cards[4]["to"] as Vector3) + Vector3(0.0, 0.05, 0.0)
			_rate(t, 26.0 + 14.0 * float(_tier), func() -> void:
				var a := _rng.randf() * TAU
				var rr := _rng.randf_range(0.5, 1.1) * world
				var from := target + Vector3(cos(a) * rr, _rng.randf_range(0.15, 0.5),
					sin(a) * rr * 0.6)
				_spark(from, (target - from) * 1.35, 0.42, 0.048 * world, gold))
		if _cross(t, RF_BURST) and _cards.size() > 4:
			var at: Vector3 = (_cards[4]["to"] as Vector3) + Vector3(0.0, 0.06, 0.0)
			_burst(at, 30, 2.3, 0.95, 0.085 * world, gold)
			_burst(at, 12, 1.4, 0.70, 0.062 * world, white)
			# ...and a smaller one over every other card, so the whole hand fires
			# rather than one corner of it.
			for i in 4:
				_burst((_cards[i]["to"] as Vector3) + Vector3(0.0, 0.05, 0.0),
					5, 1.2, 0.65, 0.055 * world, gold)


# How far from a button's centre anything this system places IN the play area — which
# means the jackpot lights' rising gold, and nothing else — has to stay. It is the
# board's own hit-area radius (MemoryGameUI._add_button_area's cylinder), so a grain
# of gold is outside the disc the player is aiming at as well as outside the chip.
#
# Everything ELSE is kept out of the play area by geometry instead: it is on the
# lane, which is above the top row of chips by construction. This rule exists for the
# one event that is deliberately all over the table.
const CHIP_CLEAR := 1.12

# ...and the extra margin an EMISSION point has to keep on top of it, because a spark
# does not stay where it was born. Its horizontal velocity is drawn from a normal
# with sigma 0.10 and decays at 1.6/s, so the whole drift integrates to about 0.06 m
# at one sigma and 0.19 at three. 0.28 covers that and the quad's own half-width.
#
# Found by the acceptance harness rather than by reasoning: emitting AT exactly
# CHIP_CLEAR passed every frame it was checked on except the ones near the end of a
# spark's life, which is the kind of miss that never shows up in a still.
const DRIFT := 0.28


func _clear_of_chips(p: Vector3, extra: float = 0.0) -> bool:
	for c: Vector2 in _centres:
		if Vector2(p.x, p.z).distance_to(c) < CHIP_CLEAR + extra:
			return false
	return true


# Fire `fn` at `hz`, driven by the elapsed time rather than by frames.
func _rate(t: float, hz: float, fn: Callable) -> void:
	var dt := t - maxf(_prev_t, 0.0)
	if dt <= 0.0:
		return
	_emit_acc += dt * hz
	var n := int(_emit_acc)
	# Capped per frame: a long hitch must not dump forty sparks in one instant.
	n = mini(n, 6)
	_emit_acc -= float(n)
	for _i in n:
		fn.call()


# ---------------------------------------------------------------------------
# Sound
# ---------------------------------------------------------------------------
# At most TWO beats per event, never two at one instant, and always at least a third
# of a second apart. The ambience channel is ONE AudioStreamPlayer (see
# AudioManager's casino block): assigning a stream cuts off whatever was running, so
# "one tap per card" would be one tap and two silences.
func _beat(t: float) -> void:
	match _kind:
		EV_COMMUNITY:
			if _cross(t, 0.10):
				AudioManager.play_card_slide()
			# The LAST landing, so the sound closes the deal rather than opening it.
			var last := 0.10 + 0.20 * float(_cards.size() - 1) + 0.44
			if _cross(t, last):
				AudioManager.play_card_tap()
		EV_ROULETTE:
			if _cross(t, BALL_IN):
				AudioManager.play_roulette_spin(BALL_SETTLE - BALL_IN)
			if _cross(t, BALL_POP):
				AudioManager.play_chip_clink()
		EV_CASCADE:
			if _cross(t, 0.05 + 0.50):
				AudioManager.play_chip_clink()
			if _cross(t, 1.35):
				AudioManager.play_chip_clink()
		EV_FLIP:
			if _cross(t, 0.05):
				AudioManager.play_card_slide()
			if _cross(t, 1.18):
				AudioManager.play_card_tap()
		EV_DEAL:
			# One stream, three slaps, landing on the three landings.
			if _cross(t, DEAL_FIRST + DEAL_SLIDE):
				AudioManager.play_card_deal_three()
		EV_LIGHTS:
			if _cross(t, 0.10):
				AudioManager.play_casino_swell()
		EV_FLUSH:
			if _cross(t, RF_IN):
				AudioManager.play_card_slide()
			# The fanfare is 1.55 s: 0.62 of rising shimmer, then the chord. Fired
			# here so the chord strikes at 2.57 and the fifth card slams open at
			# 2.62 — the sound leads the picture by fifty milliseconds, which is
			# where a hit reads as simultaneous rather than late.
			if _cross(t, RF_SHAKE + 0.05):
				AudioManager.play_royal_fanfare()


# ---------------------------------------------------------------------------
# Easing
# ---------------------------------------------------------------------------
static func _out_cubic(u: float) -> float:
	var v := 1.0 - clampf(u, 0.0, 1.0)
	return 1.0 - v * v * v


static func _in_cubic(u: float) -> float:
	var v := clampf(u, 0.0, 1.0)
	return v * v * v


static func _in_out(u: float) -> float:
	var v := clampf(u, 0.0, 1.0)
	return v * v * (3.0 - 2.0 * v)


static func _out_back(u: float) -> float:
	var v := clampf(u, 0.0, 1.0) - 1.0
	return 1.0 + v * v * (2.70158 * v + 1.70158)


# The SLAM. Slow for the first third — the card is still being held — then almost
# all of the turn in the middle third, then a small overshoot that settles. A plain
# ease-in-out flip reads as a card being placed; this one reads as a card being
# thrown down.
static func _slam(u: float) -> float:
	var v := clampf(u, 0.0, 1.0)
	if v < 0.30:
		return _in_cubic(v / 0.30) * 0.14
	var w := (v - 0.30) / 0.70
	return 0.14 + 0.86 * _out_back(w)


# ===========================================================================
# MESHES AND MATERIALS
# ===========================================================================

# A quad whose four vertices are all at the ORIGIN, with the corner carried in UV.
# The billboard is done in VIEW space in the vertex shader, so one sheet faces the
# camera at any board angle with no per-instance basis to rebuild.
static func _billboard_quad() -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		verts.append(Vector3.ZERO)
		uvs.append(c)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# A unit quad lying FLAT in the xz plane, for the contact shadows.
static func _flat_quad() -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		verts.append(Vector3(c.x, 0.0, c.y))
		norms.append(Vector3.UP)
		uvs.append(c * 0.5 + Vector2(0.5, 0.5))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# ---------------------------------------------------------------------------
# The card face
# ---------------------------------------------------------------------------
# ORIGINAL ARTWORK, DRAWN ANALYTICALLY. Every card in every event is the same mesh
# and the same material; what makes one a King of Hearts and the next a Ten is four
# floats of instance data. So twelve different faces are ONE draw call, there is no
# atlas, no texture memory and no import step.
#
# WHY THERE IS NOT A SINGLE CHARACTER OF TEXT IN IT. A heart drawn with the "♥"
# glyph is a bet on the shipped font having one, and a missing glyph is a box on the
# card — the same trap game.gd's celebration banners avoid by building their sparkle
# ring out of rotated ColorRects rather than out of a star character. Here the hearts
# are an SDF and the five ranks are three or four line segments each, so the artwork
# is identical on every device and at every size, and it stays crisp when a card is
# scaled up for the flip.
#
# The ranks are exactly the five a Royal Flush needs — 10, J, Q, K, A — and the suit
# is always hearts, which is what makes the level-8 hand legible as a hand rather
# than as five pretty cards.
static func _card_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 c_face;
uniform vec3 c_face_lo;
uniform vec3 c_red;
uniform vec3 c_gold;
uniform vec3 c_back;
uniform vec3 c_back_hi;
uniform vec3 c_edge;
uniform float aspect;          // width / length

varying vec4 inst;             // rank/8, face 0|1, glow, gold

void vertex() {
	inst = INSTANCE_CUSTOM;
}

float dot2(vec2 v) { return dot(v, v); }

float sd_seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

// Approximate distance to an ellipse's outline. Exact enough for a stroke this
// thick, and a fraction of the cost of the real solve.
float sd_ell(vec2 p, vec2 rad) {
	return (length(p / rad) - 1.0) * min(rad.x, rad.y);
}

// iq's heart: point at the origin, lobes reaching y = 1, x within +/- 1.
float sd_heart(vec2 p) {
	p.x = abs(p.x);
	if (p.y + p.x > 1.0) {
		return sqrt(dot2(p - vec2(0.25, 0.75))) - 0.35355339;
	}
	return sqrt(min(dot2(p - vec2(0.0, 1.0)),
		dot2(p - 0.5 * max(p.x + p.y, 0.0)))) * sign(p.x - p.y);
}

// A heart centred at `c`, `s` tall, in card space.
float heart_cov(vec2 q, vec2 c, float s, float aa) {
	vec2 hp = (q - c) / s + vec2(0.0, 0.5);
	return smoothstep(aa, -aa, sd_heart(hp) * s);
}

// The five ranks, in a glyph box roughly 0.9 wide by 1.4 tall.
float glyph_d(vec2 p, int id) {
	float d = 1e9;
	if (id == 0) {                       // 10
		vec2 a = (p - vec2(-0.32, 0.0)) / vec2(0.60, 1.0);
		d = min(d, sd_seg(a, vec2(0.0, -0.62), vec2(0.0, 0.62)) * 0.60);
		d = min(d, sd_seg(a, vec2(-0.46, 0.30), vec2(0.0, 0.62)) * 0.60);
		vec2 b = p - vec2(0.30, 0.0);
		d = min(d, abs(sd_ell(b, vec2(0.26, 0.62))));
	} else if (id == 1) {                // J
		d = min(d, sd_seg(p, vec2(0.22, 0.62), vec2(0.22, -0.22)));
		d = min(d, sd_seg(p, vec2(0.22, -0.22), vec2(0.00, -0.58)));
		d = min(d, sd_seg(p, vec2(0.00, -0.58), vec2(-0.28, -0.38)));
	} else if (id == 2) {                // Q
		d = min(d, abs(sd_ell(p - vec2(0.0, 0.04), vec2(0.34, 0.50))));
		d = min(d, sd_seg(p, vec2(0.10, -0.22), vec2(0.40, -0.62)));
	} else if (id == 3) {                // K
		d = min(d, sd_seg(p, vec2(-0.26, 0.62), vec2(-0.26, -0.62)));
		d = min(d, sd_seg(p, vec2(-0.26, 0.02), vec2(0.30, 0.62)));
		d = min(d, sd_seg(p, vec2(-0.26, 0.02), vec2(0.34, -0.62)));
	} else {                             // A
		d = min(d, sd_seg(p, vec2(-0.34, -0.62), vec2(0.00, 0.62)));
		d = min(d, sd_seg(p, vec2(0.34, -0.62), vec2(0.00, 0.62)));
		d = min(d, sd_seg(p, vec2(-0.17, -0.12), vec2(0.17, -0.12)));
	}
	return d;
}

float glyph_cov(vec2 q, vec2 c, float h, int id, float aa) {
	float k = h / 1.32;
	float d = glyph_d((q - c) / k, id) * k - h * 0.078;
	return smoothstep(aa, -aa, d);
}

// One corner index: the rank with a small heart under it. Called twice, the second
// time with the card space negated, which is the 180-degree copy every playing card
// carries in the opposite corner.
float index_cov(vec2 q, int id, float aa) {
	float c = glyph_cov(q, vec2(-0.222, 0.330), 0.200, id, aa);
	c = max(c, heart_cov(q, vec2(-0.222, 0.175), 0.078, aa));
	return c;
}

void fragment() {
	int id = int(floor(inst.x * 8.0 + 0.5));
	float face = inst.y;
	float glow = inst.z;
	float gold = inst.w;

	// Card space: 1.0 along the card's LENGTH, `aspect` across its width.
	vec2 q = vec2((UV.x - 0.5) * aspect, UV.y - 0.5);
	float border = max(abs(q.x) / (aspect * 0.5), abs(q.y) / 0.5);
	float aa = max(fwidth(q.x), fwidth(q.y)) * 1.2 + 0.0006;

	vec3 col;
	if (face > 0.5) {
		// The printed side. The base is a MIX between two solved creams rather
		// than a scaled one, so the card has a shading gradient across it without
		// falling off the bottom of the tone curve (see CasinoWorld's palette note).
		col = mix(c_face_lo, c_face, clamp(0.42 + 0.85 * (q.y + 0.5), 0.0, 1.0));
		// The gold inner border.
		float line = 1.0 - smoothstep(0.0, 0.030, abs(border - 0.885));
		col = mix(col, c_gold, line * (0.40 + 0.60 * gold));
		// The suit and the rank, both red: this table plays hearts.
		float marks = max(index_cov(q, id, aa), index_cov(-q, id, aa));
		marks = max(marks, heart_cov(q, vec2(0.0, -0.015), 0.260, aa));
		col = mix(col, c_red, marks);
	} else {
		col = c_back;
		float lat = 0.5 + 0.5 * sin((UV.x + UV.y) * 58.0) * sin((UV.x - UV.y) * 58.0);
		col = mix(col, c_back_hi, lat * 0.45 * (1.0 - smoothstep(0.58, 0.74, border)));
		col = mix(col, c_edge, smoothstep(0.82, 0.91, border));
		col = mix(col, c_back, smoothstep(0.94, 0.99, border));
	}

	// The glow: a lift over the whole card and a strong gold rim, so a card that is
	// about to be turned over reads as lit from underneath rather than as recoloured.
	float rim = smoothstep(0.72, 0.99, border);
	col = mix(col, c_gold, clamp(glow, 0.0, 1.0) * (0.16 + 0.55 * rim));

	ALBEDO = col;
	ALPHA = COLOR.a;
}
"""
	m.shader = sh
	m.set_shader_parameter("c_face", CasinoWorld.tone(CARD_FACE))
	m.set_shader_parameter("c_face_lo", CasinoWorld.tone(CARD_FACE_LO))
	m.set_shader_parameter("c_red", CasinoWorld.tone(CARD_RED))
	m.set_shader_parameter("c_gold", CasinoWorld.tone(CARD_GOLD))
	m.set_shader_parameter("c_back", CasinoWorld.tone(CasinoWorld.CARD_BACK))
	m.set_shader_parameter("c_back_hi", CasinoWorld.tone(CasinoWorld.CARD_BACK_HI))
	m.set_shader_parameter("c_edge", CasinoWorld.tone(CasinoWorld.CARD_EDGE))
	m.set_shader_parameter("aspect", CARD_ASPECT)
	m.render_priority = 2
	return m


# The cascade's chips. The table's own prop mesh, tinted and faded per instance.
static func _chip_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
// CULL_DISABLED for the same reason CasinoWorld's copy is: the prop mesh's barrel
// winds inward, so back-face culling removes the near half and a chip renders as a
// hollow crescent. Two materials, one mesh, one mistake — fix both or neither.
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;
uniform vec3 c_shade;
uniform vec3 c_light;
uniform vec3 sun;
varying vec3 wnorm;
varying float face;
varying float band;
void vertex() {
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	face = UV.y > 1.2 ? 1.0 : 0.0;
	// The eight edge inserts, from the angular UV the mesh already carries.
	band = mix(1.0, 0.62, step(0.5, fract(UV.x * 8.0)) * (1.0 - face)
		* step(0.15, UV.y) * step(UV.y, 0.85));
}
void fragment() {
	float lam = clamp(dot(normalize(wnorm), normalize(sun)) * 0.5 + 0.5, 0.0, 1.0);
	lam = mix(lam, 0.94, face);
	ALBEDO = mix(c_shade, c_light, lam) * COLOR.rgb * band;
	ALPHA = COLOR.a;
}
"""
	m.shader = sh
	m.set_shader_parameter("c_shade", CasinoWorld.tone(CasinoWorld.PROP_SHADE))
	# A stop brighter than the table's own dressing, and only here. The dressing is
	# deliberately dim so it can never out-read the buttons; a cascade chip is the
	# SUBJECT of its event for two and a half seconds and has to be seen.
	m.set_shader_parameter("c_light", CasinoWorld.tone(CASCADE_LIGHT))
	m.set_shader_parameter("sun", CasinoWorld.SUN_DIR.normalized())
	m.render_priority = 2
	return m


# Every particle in every event. Additive, billboarded in view space, size carried
# in the instance's custom data so one sheet draws sparks of a dozen sizes.
static func _spark_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled,
	depth_draw_never, blend_add;
varying vec2 quv;
void vertex() {
	vec4 vp = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	vp.xy += UV * INSTANCE_CUSTOM.x;
	POSITION = PROJECTION_MATRIX * vp;
	quv = UV;
}
void fragment() {
	float d = clamp(1.0 - length(quv), 0.0, 1.0);
	// Cubed, so a spark is a point with a halo rather than a disc. A linear falloff
	// at these sizes reads as a bubble.
	ALBEDO = COLOR.rgb;
	ALPHA = d * d * d * COLOR.a;
}
"""
	m.shader = sh
	m.render_priority = 4
	return m


# The contact shadows. MIX and not ADD, because a shadow has to SUBTRACT light from
# the felt — an additive dark sheet is a no-op, which is a mistake that looks like
# the shadows simply not being there.
static func _shadow_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled,
	depth_draw_never;
uniform vec3 c_shadow;
varying vec2 quv;
void vertex() { quv = UV * 2.0 - 1.0; }
void fragment() {
	float d = clamp(1.0 - length(quv), 0.0, 1.0);
	ALBEDO = c_shadow;
	ALPHA = d * d * COLOR.a;
}
"""
	m.shader = sh
	m.set_shader_parameter("c_shadow", CasinoWorld.tone(SHADOW_C))
	m.render_priority = -1
	return m


# The roulette ball. A bright core with a hot rim, so it reads as a lit sphere at
# eight pixels across; `hot` is dropped as it decelerates, which is what makes the
# stop feel like the energy leaving it rather than like a pause.
static func _ball_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;
uniform vec3 c_core;
uniform vec3 c_glow;
uniform float hot = 1.0;
void fragment() {
	// Lit from straight above and hottest at the top, which is where the table lamp
	// is — and then a RIM term, because at eight pixels across what reads as "a
	// glowing ball" is the edge being brighter than the middle, not the reverse.
	float f = clamp(dot(normalize(NORMAL), vec3(0.0, 1.0, 0.0)) * 0.5 + 0.5, 0.0, 1.0);
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.0);
	vec3 col = mix(c_glow, c_core, f * (0.55 + 0.45 * hot));
	ALBEDO = mix(col, c_core, rim * (0.35 + 0.45 * hot));
}
"""
	m.shader = sh
	m.set_shader_parameter("c_core", CasinoWorld.tone(BALL_CORE))
	m.set_shader_parameter("c_glow", CasinoWorld.tone(BALL_GLOW))
	m.set_shader_parameter("hot", 1.0)
	m.render_priority = 3
	return m
