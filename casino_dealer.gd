extends Node3D
class_name CasinoDealer

# THE DEALER'S HANDS — the ROYAL CASINO's croupier, seen the way a player sitting at
# the table sees one: two arms coming down into the top of the frame, and a pair of
# hands the size real hands are next to the cards they deal.
#
# ===========================================================================
# THE HANDS ARE A BLENDER ASSET NOW, NOT A SCRIPT
# ===========================================================================
# Everything about how the dealer LOOKS and MOVES lives in DealerHands.blend and is
# shipped as `res://models/DealerHands.glb`: one skinned mesh (~3300 triangles, one
# draw call, no textures), a 43-bone armature, and four animation clips authored on
# it — IDLE, DEAL_CARD, DEAL_CARD_QUICK and ROYAL_FLUSH_CELEBRATION. Nothing in this
# file builds geometry or invents a pose any more. What is left is the three jobs
# that are the ENGINE's and cannot be baked into a clip:
#
#   FIT       the asset is authored at a hand length of 1.0 with the felt at y = 0;
#             `place` solves the one scale and the one distance that put the hands
#             above this board's topmost chip and the arms off the top of the frame.
#   DRIVE     the clips are never "played". CasinoEvents hands over a PHASE (or a
#             celebration clock) and this file seeks the clip to the matching time,
#             so the hand and the card it throws can never drift apart — and so a
#             frozen round cannot freeze the dealer, because there is no clock of
#             our own to stop.
#   AIM       one baked deal cannot land on every slot of every board, so the right
#             arm is swung about the shoulder and slid to meet the ACTUAL target the
#             gameplay picked. The authored pose is untouched; only where the arm is
#             rooted moves.
#
# The vertex colours carry the whole look: COLOR.rgb is the tint and COLOR.a is the
# material — 0 skin, 0.5 cloth, 1 metal — which is what lets the same analytic
# shader every other object on this table uses light a Blender mesh.
#
# ===========================================================================
# WHAT IT MAY NOT DO
# ===========================================================================
# THE HANDS MAY NOT COVER A BUTTON. At rest, through the whole idle breath and
# through the whole celebration they are fitted ABOVE the topmost chip's screen row
# — `place` bisects the resting distance against the LOWEST frame of the idle, not
# against the rest pose, so the breath is inside the guarantee rather than outside
# it — and the ONE time they come down over the play area is the deal, which freezes
# the round (CasinoEvents' start_hand / start_flush). Same exemption, on the same
# terms, as the dealt card itself flies under.

const GLB := "res://models/DealerHands.glb"
const BG_LAYER := 2

# ---------------------------------------------------------------------------
# The clips, and the two numbers about each that this file needs
# ---------------------------------------------------------------------------
# RELEASE is where in the clip the fingers open, as a fraction of its length. It is
# frame 21 of 45 in DEAL_CARD and frame 13 of 29 in the quick one; the phase
# CasinoEvents hands over is -1 at the top of the wind-up, 0 at the release and 1 at
# the end of the follow-through, so these two numbers are the whole mapping.
const A_IDLE := "IDLE"
const A_DEAL := "DEAL_CARD"
const A_QUICK := "DEAL_CARD_QUICK"
const A_DANCE := "ROYAL_FLUSH_CELEBRATION"
const DEAL_RELEASE := 26.0 / 44.0
const QUICK_RELEASE := 16.0 / 28.0

# When the arm's aim is allowed to leave the authored pose. It is HELD AT ZERO
# until the card is off the deck: the first third of the clip has to keep meeting
# the left hand, which does not move with the target, and a millimetre of aim there
# is a hand that closes on nothing. It comes in over the carry, is full before the
# fingers open, and is let out again before he settles, so the return is authored.
const AIM_HOLD := 0.36
const AIM_IN := 0.52
const AIM_OUT_A := 0.86
const AIM_OUT_B := 0.99

# ---------------------------------------------------------------------------
# Anatomy — only what the FIT needs. The rest of it is in the .blend.
# ---------------------------------------------------------------------------
# All of these are in HAND LENGTHS, the unit the asset is authored in: wrist crease
# to the tip of the middle finger is exactly 1.0, and the felt is y = 0.
const REST_X := 0.95              # the resting wrists, either side of the middle
const WRIST_UP := 0.78            # ...and their height over the felt
const GRIP_UP := 0.80             # where the card is when the fingers open
const HAND_PER_CARD := 2.10       # a real hand is a little over twice a card
const CHIP_DIAM := 2.0
const HAND_MIN_CHIPS := 0.62
const HAND_MAX_CHIPS := 0.88
const MIN_HAND_SCREEN := 0.070    # ...and a hand smaller than this is not a dealer
const CHIP_MARGIN := 0.028
const SHOULDER_ABOVE := 0.010     # the arms must reach this far off the top edge
# How far the arm may be slid to meet a slot, ACROSS the table and UP off it. The
# two are clamped apart on purpose: leaning a long way forward telescopes a sleeve
# whose shoulder is off the top of the frame, whereas lifting is free — a card that
# leaves the fingers higher is a card that is pitched rather than placed, which is
# what a croupier does with a community card anyway.
const REACH_MAX := 0.45
const LIFT_MAX := 0.30

# The distal phalanx has no child bone to measure, so its tip is taken as this much
# of the joint before it — the real ratio, and the fingertips are what has to clear
# the chips.
# Why the croupier was refused, printed. `place` fails SILENTLY by design — a
# camera with no room for him is a legitimate answer and CasinoEvents has a
# fallback — so when he is unexpectedly absent this is the only thing that says
# which of the two limits he missed and by how much.
const DEBUG := false

const TIP_FINGER := 0.80
const TIP_THUMB := 0.72

# ---------------------------------------------------------------------------
# The look. Unchanged: the hands are lit by the same analytic model as the felt,
# the chips and the cards, because a hand shaded by a different one is a hand from
# a different game.
# ---------------------------------------------------------------------------
const DEALER_SHADE := Color8(30, 33, 41)
const DEALER_LIGHT := Color8(224, 212, 194)
const FELT_BOUNCE := Color8(26, 74, 52)
const RIM := Color8(176, 156, 108)
const RIM_GAIN := 0.34

const SHADOW_C := Color8(4, 14, 11)
const SHADOW_GONE := 1.55
const SHADOW_Y := 0.0075

# Emitted on the frame the celebration clip runs out. The Royal Flush's freeze is
# NOT released on a timer that happens to be five seconds long: game.gd holds the
# board until CasinoWorld.celebration_busy goes false, which is the event system
# saying its own timeline has finished — and this clip is stretched onto exactly
# that timeline (see `dance`), so the two end on the same frame by construction.
# This signal is that instant, for anything that wants it directly.
signal celebration_finished

# One animation clip, with its tracks resolved to bone indices once.
class Clip:
	var anim: Animation
	var length := 0.0
	var pos: PackedInt32Array = PackedInt32Array()
	var rot: PackedInt32Array = PackedInt32Array()
	var release := 0.0            # seconds into the clip, 0 when it has none
	var grip := Transform3D()     # the pinch at the release, in rig space
	var pivot := Vector3.ZERO     # the shoulder it is swung about, in rig space
	var pickup := 0.0             # ...and the instant the card is taken off the deck
	var pickup_grip := Transform3D()   # the card's transform at that instant
	var deck_at := Vector3.ZERO   # where the deck's top card is, on that same frame
	var pickup_gap := 0.0         # how far the pinch misses the deck by; 0 is exact

var _rig: Node3D
var _skel: Skeleton3D
var _mi: MeshInstance3D
var _shadow: MultiMeshInstance3D
var _placed := false

var _clips: Dictionary = {}       # name -> Clip
var _skel_local := Transform3D()  # rig root -> skeleton, constant
var _skel_inv := Transform3D()

var _s := 0.0                     # one hand length, in board units
var _felt := 0.0
var _card := 0.0
var _idle_t := 0.0
var _derived := false             # ...measured once, the first time he is placed
var _fit_clip := ""               # the clip and frame whose hands hang lowest of all
var _fit_t := 0.0
var _fit_pad := 0.0               # ...and the aim's reach, allowed for in the fit

# Bone indices, resolved once by name.
var _b_hands: PackedInt32Array = PackedInt32Array()   # every hand/finger/thumb bone
var _b_tips: PackedInt32Array = PackedInt32Array()    # ...of which these are leaves
var _b_arms: PackedInt32Array = PackedInt32Array()    # the two shoulders and elbows
var _b_upper := -1
var _b_palm_l := -1
var _b_palm_r := -1
var _b_hold := -1
var _b_fwd := -1
var _b_up := -1
var _b_deck := -1
var _b_pick := -1

# The hand-off between one card and the next: see `deal`.
var _prev_phase := 2.0
var _prev_target := Vector3(1e9, 1e9, 1e9)
var _danced := false


# ---------------------------------------------------------------------------
# Loading the asset
# ---------------------------------------------------------------------------
func construct() -> void:
	var packed := load(GLB) as PackedScene
	if packed != null:
		_rig = packed.instantiate() as Node3D
	if _rig != null:
		_rig.name = "Arms"
		add_child(_rig)
		_skel = _find(_rig, "Skeleton3D") as Skeleton3D
		_mi = _find(_rig, "MeshInstance3D") as MeshInstance3D
	if _skel == null or _mi == null:
		# The asset is missing or did not import. Everything below is written to
		# survive that: `placed()` stays false and CasinoEvents falls back to the
		# short run-in the hand used before there was a dealer at all.
		push_warning("CasinoDealer: %s did not load; the croupier will not be drawn."
			% GLB)
		_rig = null
		_build_shadow()
		return

	_mi.material_override = _material()
	_mi.layers = BG_LAYER
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Given, not derived: a skinned mesh's bounds move with its bones and the engine
	# would have to read them back every frame to know where these end up. In the
	# asset's own units — the rig node carries the scale.
	_mi.custom_aabb = AABB(Vector3(-5, -2, -9), Vector3(10, 14, 14))
	_mi.visible = false

	# The rig root -> skeleton transform, accumulated up the chain by hand. The
	# asset nests the skeleton under its own armature node, and `global_transform`
	# is not answerable here: `construct` runs while the dealer is still outside the
	# tree, and asking would return an identity that is right by luck on this asset
	# and wrong on the next re-export.
	var n: Node3D = _skel
	_skel_local = Transform3D()
	while n != null and n != _rig:
		_skel_local = n.transform * _skel_local
		n = n.get_parent() as Node3D
	_skel_inv = _skel_local.affine_inverse()

	_index_bones()
	_load_clips()
	_build_shadow()


static func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var f := _find(c, cls)
		if f != null:
			return f
	return null


func _build_shadow() -> void:
	var sh := MultiMesh.new()
	sh.transform_format = MultiMesh.TRANSFORM_3D
	sh.use_colors = true
	sh.mesh = _flat_quad()
	sh.instance_count = 0
	_shadow = MultiMeshInstance3D.new()
	_shadow.name = "HandShadows"
	_shadow.multimesh = sh
	_shadow.material_override = _shadow_material()
	_shadow.layers = BG_LAYER
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow.custom_aabb = AABB(Vector3(-14, -1, -14), Vector3(28, 2, 28))
	add_child(_shadow)


# Which bone is which, by name, once. The names are the .blend's and the glTF keeps
# them: hand.L/R, f_<finger>.0N.L/R, thumb.0N.L/R, upperarm/forearm, and the AP_
# helpers that are attachment points rather than deformers.
func _index_bones() -> void:
	var hands: Array[int] = []
	var tips: Array[int] = []
	var arms: Array[int] = []
	for i in _skel.get_bone_count():
		var nm := _skel.get_bone_name(i)
		if nm.begins_with("hand.") or nm.begins_with("f_") or nm.begins_with("thumb."):
			hands.append(i)
			if nm.ends_with(".03.L") or nm.ends_with(".03.R"):
				tips.append(i)
		elif nm.begins_with("upperarm.") or nm.begins_with("forearm."):
			arms.append(i)
		match nm:
			"upperarm.R": _b_upper = i
			"hand.L": _b_palm_l = i
			"hand.R": _b_palm_r = i
			"AP_CardHold.R": _b_hold = i
			"AP_CardFwd.R": _b_fwd = i
			"AP_CardUp.R": _b_up = i
			"AP_Deck.L": _b_deck = i
			"AP_Pickup.L": _b_pick = i
	_b_hands = PackedInt32Array(hands)
	_b_tips = PackedInt32Array(tips)
	_b_arms = PackedInt32Array(arms)


func _load_clips() -> void:
	var ap := _find(_rig, "AnimationPlayer") as AnimationPlayer
	if ap == null:
		return
	for want: String in [A_IDLE, A_DEAL, A_QUICK, A_DANCE]:
		var anim: Animation = null
		for nm: String in ap.get_animation_list():
			if nm == want or nm.ends_with("/" + want):
				anim = ap.get_animation(nm)
				break
		if anim == null:
			continue
		var c := Clip.new()
		c.anim = anim
		c.length = anim.length
		c.pos.resize(_skel.get_bone_count())
		c.rot.resize(_skel.get_bone_count())
		c.pos.fill(-1)
		c.rot.fill(-1)
		for t in anim.get_track_count():
			var path := anim.track_get_path(t)
			if path.get_subname_count() < 1:
				continue
			var b := _skel.find_bone(path.get_subname(0))
			if b < 0:
				continue
			match anim.track_get_type(t):
				Animation.TYPE_POSITION_3D: c.pos[b] = t
				Animation.TYPE_ROTATION_3D: c.rot[b] = t
		_clips[want] = c

	_derived = false


# ---------------------------------------------------------------------------
# What has to be MEASURED off the clips, once
# ---------------------------------------------------------------------------
# Not in `construct`, and this is not a style choice: a Skeleton3D only propagates a
# pose while it is INSIDE THE TREE, and the whole table is built before it is added
# to the board's viewport. Seek a clip there and every bone reads back at its rest
# position — so the pickup was found on frame zero, the fit was solved against a
# pose the dealer is never in, and none of it looked wrong from the outside. It is
# done from `place` instead, which cannot run without a live camera.
func _derive() -> void:
	if _derived or _skel == null:
		return
	_derived = true
	# The two things about a deal that have to be read off the CLIP rather than
	# guessed: where the pinch is at the instant the fingers open, and the shoulder
	# the arm is swung about to make it land somewhere else.
	for nm: String in [A_DEAL, A_QUICK]:
		var c: Clip = _clips.get(nm)
		if c == null:
			continue
		c.release = c.length * (DEAL_RELEASE if nm == A_DEAL else QUICK_RELEASE)
		_pose(c, c.release)
		c.grip = _skel_local * _grip_pose()
		c.pivot = (_skel_local * _skel.get_bone_global_pose(_b_upper)).origin
		# WHERE THE CARD IS TAKEN. Derived, never typed: the pickup is the frame
		# whose pinch is nearest the deck's top card. That is a property of the
		# CLIP, so it survives any retime in Blender, and the clip is authored so
		# the pinch MEETS the deck there — `pickup_gap` is the proof, and the
		# harness holds it to zero. Everything about the hand-off hangs off this:
		# the card is the deck's until this instant and the hand's after it.
		if _b_pick >= 0:
			var best := 1e9
			var steps := 120
			for i in steps + 1:
				var tt := c.length * float(i) / float(steps)
				_pose(c, tt)
				var d := _grip_pose().origin.distance_to(
					_skel.get_bone_global_pose(_b_pick).origin)
				if d < best:
					best = d
					c.pickup = tt
			_pose(c, c.pickup)
			c.pickup_grip = _skel_local * _grip_pose()
			c.deck_at = (_skel_local * _skel.get_bone_global_pose(_b_pick)).origin
			c.pickup_gap = best

	# ...and THE FRAME THE WHOLE DEALER IS FITTED AGAINST: the lowest any clip ever
	# puts a hand, over every clip and not just the idle's breath.
	#
	# Fitting the rest pose and then MOVING below it is how a fingertip ends up over
	# a button, and the deal is the animation that would do it: it reaches forward
	# over the table, and forward is DOWN on a camera looking across one. So the
	# deal is measured too, padded by the furthest the aim may ever slide it, and
	# whichever frame of whichever clip comes out lowest is the one `place` puts
	# above the chips. Everything else is then above it by construction.
	var worst := -1e9
	for nm: String in [A_IDLE, A_QUICK, A_DEAL, A_DANCE]:
		var c: Clip = _clips.get(nm)
		if c == null:
			continue
		var pad := REACH_MAX if (nm == A_QUICK or nm == A_DEAL) else 0.0
		var steps := 48
		for i in steps + 1:
			var t := c.length * float(i) / float(steps)
			_pose(c, t)
			for p: Vector3 in _local_hand_points():
				# Screen row rises with z and falls with y at any camera looking
				# down at a table; this picks the frame, `place` does the real
				# projection.
				var m := (p.z + pad) - p.y * 0.55
				if m > worst:
					worst = m
					_fit_clip = nm
					_fit_t = t
					_fit_pad = pad


# ---------------------------------------------------------------------------
# Driving the rig
# ---------------------------------------------------------------------------
# A clip is never played. It is SEEKED, from a phase or a clock the gameplay owns —
# which is what keeps the hand and the card on one timeline, and what makes a frozen
# round safe: there is no timer here to be paused by mistake.
func _pose(c: Clip, t: float) -> void:
	if c == null or _skel == null:
		return
	var u := clampf(t, 0.0, c.length)
	for b in _skel.get_bone_count():
		var pi := c.pos[b]
		if pi >= 0:
			_skel.set_bone_pose_position(b, c.anim.position_track_interpolate(pi, u))
		var ri := c.rot[b]
		if ri >= 0:
			_skel.set_bone_pose_rotation(b, c.anim.rotation_track_interpolate(ri, u))
	# ...AND MADE READABLE IMMEDIATELY. A skeleton batches its global poses and
	# settles them on its own schedule, so a seek followed by a read in the same call
	# hands back the pose BEFORE the seek. Everything here reads straight back —
	# the card's pinch, the fit's lowest pixel, the pickup's derivation — and all of
	# it was quietly measuring one frozen frame.
	_skel.force_update_all_bone_transforms()


# The right arm, swung and slid so the authored deal lands on THIS board's slot.
# `A` is in rig space; the arm's root bone is re-seated by it and everything below
# the shoulder — elbow, wrist, fingers, the card's own attachment point — follows
# for nothing, still in the pose the clip put it in.
func _reseat_arm(a: Transform3D) -> void:
	if _b_upper < 0:
		return
	var par := _skel.get_bone_parent(_b_upper)
	var pg := _skel.get_bone_global_pose(par) if par >= 0 else Transform3D()
	var g := pg * _skel.get_bone_pose(_b_upper)
	var want := (_skel_inv * a * _skel_local) * g
	var loc := pg.affine_inverse() * want
	_skel.set_bone_pose_position(_b_upper, loc.origin)
	_skel.set_bone_pose_rotation(_b_upper, loc.basis.get_rotation_quaternion())


# ---------------------------------------------------------------------------
# Fitting the arms to this camera
# ---------------------------------------------------------------------------
# Two numbers, each with one job: the HAND's size (right next to the card it deals)
# and the resting DISTANCE, which has to satisfy two things at once — the lowest
# pixel of the breathing hands sits above the topmost chip, and the far end of the
# sleeves is off the top edge, so the arms are cut by it and read as continuing out
# of the picture. Both are of the form "no nearer than", so the nearer of the two
# limits is the answer and one bisection does each.
func place(cam: Camera3D, vp: Vector2, reach: float, rail_r: float, top_px: float,
		card_len: float) -> void:
	_placed = false
	_s = 0.0
	_prev_phase = 2.0
	_prev_target = Vector3(1e9, 1e9, 1e9)
	if _mi != null:
		_mi.visible = false
	if _shadow != null:
		_shadow.multimesh.instance_count = 0
	if _skel == null or not _clips.has(A_IDLE):
		return
	if cam == null or vp.y < 8.0 or reach <= 0.0 or card_len <= 0.0:
		return
	_derive()
	_felt = CasinoWorld.CARD_Y
	_card = card_len
	var edge := rail_r if rail_r > 0.0 else reach * 1.45
	_s = clampf(card_len * HAND_PER_CARD, CHIP_DIAM * HAND_MIN_CHIPS,
		CHIP_DIAM * HAND_MAX_CHIPS)

	if DEBUG:
		print("[dealer] s=%.3f edge=%.2f top_px=%.1f vp=%s reach=%.2f card=%.3f"
			% [_s, edge, top_px, vp, reach, card_len])
	_pose(_clips[_fit_clip] if _clips.has(_fit_clip) else _clips[A_IDLE], _fit_t)
	var hands := _local_hand_points()
	if _fit_pad > 0.0:
		for i in hands.size():
			hands[i] = hands[i] + Vector3(0.0, 0.0, _fit_pad)
	var arms := _local_arm_points()
	var floor_px := top_px - vp.y * CHIP_MARGIN
	var want_top := -vp.y * SHOULDER_ABOVE

	var zfar := -(edge * 1.35)
	var znear := -(edge * 0.10)
	var z_hands := _limit(cam, hands, zfar, znear, floor_px, true)
	if DEBUG:
		print("[dealer] zfar=%.2f znear=%.2f z_hands=%s lowest@zfar=%.1f floor=%.1f"
			% [zfar, znear, z_hands, _row_of(cam, hands, zfar, true), floor_px])
	if is_nan(z_hands):
		return                       # nowhere on this table is above the chips
	var z_arms := _limit(cam, arms, zfar, znear, want_top, false)
	if DEBUG:
		print("[dealer] z_arms=%s  arm top@zfar=%.1f want<=%.1f  arm top@znear=%.1f"
			% [z_arms, -_row_of(cam, arms, zfar, false), want_top,
			-_row_of(cam, arms, znear, false)])
	if is_nan(z_arms):
		return                       # this camera cannot cut the arms off the top
	var z: float = minf(z_hands, z_arms)

	_seat(z)
	_placed = true
	_mi.visible = true
	_idle_t = 0.0
	rest()
	# ...and the refusal, on the one thing this file exists for: a hand that is not a
	# close-up. `CasinoEvents._deal_from` falls back to the short run-in the hand used
	# before there was a dealer at all.
	var box := hands_screen_rect(cam, vp)
	if DEBUG:
		print("[dealer] z=%.2f hand box %s (need %.1f px)  full %s"
			% [z, box, vp.y * MIN_HAND_SCREEN, screen_rect(cam, vp)])
	if not box.has_area() or box.size.y < vp.y * MIN_HAND_SCREEN:
		_placed = false
		_mi.visible = false
		_shadow.multimesh.instance_count = 0


# The furthest-forward distance at which every one of `pts` is still on the right
# side of `px`. `below` picks which side that is: the hands must stay ABOVE the chip
# row, the sleeve ends must reach above the top edge. NAN when even the furthest
# pose fails, which is this file's way of saying it will not be drawn here.
func _limit(cam: Camera3D, pts: PackedVector3Array, zfar: float, znear: float,
		px: float, below: bool) -> float:
	if not _ok_at(cam, pts, zfar, px, below):
		return NAN
	if _ok_at(cam, pts, znear, px, below):
		return znear
	for _i in 22:
		var mid := (zfar + znear) * 0.5
		if _ok_at(cam, pts, mid, px, below):
			zfar = mid
		else:
			znear = mid
	return zfar


# The extreme row a set of points reaches at this distance, for DEBUG only.
func _row_of(cam: Camera3D, pts: PackedVector3Array, z: float, below: bool) -> float:
	var worst := -1e9
	for p: Vector3 in pts:
		var w := Vector3(p.x * _s, _felt + p.y * _s, z + p.z * _s)
		if cam.is_position_behind(w):
			continue
		worst = maxf(worst, cam.unproject_position(w).y * (1.0 if below else -1.0))
	return worst


# `below` asks about the LOWEST row these points reach, which is the hands' test:
# every one of them has to stay above the chips. Otherwise it asks about the
# HIGHEST, which is the arms' test: at least one of them has to be off the top of
# the frame. Both get worse as the dealer is moved toward the camera, which is what
# lets one bisection do either.
func _ok_at(cam: Camera3D, pts: PackedVector3Array, z: float, px: float,
		below: bool) -> bool:
	var lo := 1e9
	var hi := -1e9
	for p: Vector3 in pts:
		var w := Vector3(p.x * _s, _felt + p.y * _s, z + p.z * _s)
		if cam.is_position_behind(w):
			continue
		var r := cam.unproject_position(w).y
		lo = minf(lo, r)
		hi = maxf(hi, r)
	if hi < -1e8:
		return false
	return hi < px if below else lo < px


func _seat(z: float) -> void:
	_rig.transform = Transform3D(Basis().scaled(Vector3(_s, _s, _s)),
		Vector3(0.0, _felt, z))


# ---------------------------------------------------------------------------
# Reading the posed rig
# ---------------------------------------------------------------------------
# Every point the fit and the harness care about, in the ASSET's own units — the
# seat is a uniform scale and a slide, so the fit can move the whole dealer without
# re-posing anything.
func _local_hand_points() -> PackedVector3Array:
	var pts := PackedVector3Array()
	for b in _b_hands:
		var g := _skel_local * _skel.get_bone_global_pose(b)
		pts.append(g.origin)
	# ...and the fingertips, which are what actually hangs lowest. A distal phalanx
	# is a leaf and has no child to measure, so it is carried on in the direction it
	# leaves the joint before it.
	for b in _b_tips:
		var par := _skel.get_bone_parent(b)
		if par < 0:
			continue
		var a := (_skel_local * _skel.get_bone_global_pose(par)).origin
		var c := (_skel_local * _skel.get_bone_global_pose(b)).origin
		var d := c - a
		var k := TIP_THUMB if _skel.get_bone_name(b).begins_with("thumb") \
			else TIP_FINGER
		pts.append(c + d * k)
	return pts


func _local_arm_points() -> PackedVector3Array:
	var pts := PackedVector3Array()
	for b in _b_arms:
		pts.append((_skel_local * _skel.get_bone_global_pose(b)).origin)
	return pts


func _world(p: Vector3) -> Vector3:
	return Vector3(p.x * _s, _felt + p.y * _s, _rig.transform.origin.z + p.z * _s)


func _local(p: Vector3) -> Vector3:
	return Vector3(p.x / _s, (p.y - _felt) / _s, (p.z - _rig.transform.origin.z) / _s)


# Everything the hands and arms cover on screen, in the pose they are in NOW — the
# harness holds every frame of every animation against this.
func screen_rect(cam: Camera3D, _vp: Vector2, margin: float = 0.0) -> Rect2:
	return _rect_of(cam, silhouette(), margin)


# ...and just the two HANDS, without the arms. An arm crosses most of the top of the
# frame; refusing every prop behind one would empty the table's whole back edge,
# whereas a chip stack behind a PALM reads as something the dealer is holding.
func hands_screen_rect(cam: Camera3D, _vp: Vector2, margin: float = 0.0) -> Rect2:
	if not _placed:
		return Rect2()
	var pts := PackedVector3Array()
	for p: Vector3 in _local_hand_points():
		pts.append(_world(p))
	return _rect_of(cam, pts, margin)


func _rect_of(cam: Camera3D, pts: PackedVector3Array, margin: float) -> Rect2:
	if not _placed or cam == null:
		return Rect2()
	var r := Rect2()
	var got := false
	for p: Vector3 in pts:
		if cam.is_position_behind(p):
			continue
		var sp := cam.unproject_position(p)
		if got:
			r = r.expand(sp)
		else:
			r = Rect2(sp, Vector2.ZERO)
			got = true
	return r.grow(margin) if got else Rect2()


# Every point the harness holds against the chips: both hands' joints, knuckles and
# fingertips, plus the sleeves that run out of the frame.
func silhouette() -> PackedVector3Array:
	var pts := PackedVector3Array()
	if not _placed:
		return pts
	for p: Vector3 in _local_hand_points():
		pts.append(_world(p))
	for p: Vector3 in _local_arm_points():
		pts.append(_world(p))
	return pts


func placed() -> bool:
	return _placed


func hand_len() -> float:
	return _s


# ---------------------------------------------------------------------------
# WHERE A CARD IS HELD, AND WHERE IT LEAVES
# ---------------------------------------------------------------------------
# The card is gripped between the pad of the thumb and the tips of the index and
# middle fingers — a dealer's pinch — and everything about the deal comes out of this
# one transform: the card is DRAWN there while the hand carries it (CasinoEvents asks
# for `grip` on every frame before the release) and the flight starts from exactly
# the same point at the instant the fingers open. The card cannot float free of the
# hand, because there is only one number.
#
# The pinch is not guessed from the fingers. Blender welds three non-deforming bones
# into the right hand — AP_CardHold, AP_CardFwd and AP_CardUp — and their three
# POSITIONS give the card's frame outright. Positions, not bases: a bone's own axes
# come through glTF under a convention this file would have to assume, and three
# points assume nothing.
func grip() -> Transform3D:
	if not _placed:
		return Transform3D()
	var g := _grip_pose()
	return Transform3D(g.basis, _world((_skel_local * g).origin))


func _grip_pose() -> Transform3D:
	if _b_hold < 0 or _b_fwd < 0 or _b_up < 0:
		return Transform3D()
	var h := _skel.get_bone_global_pose(_b_hold).origin
	var f := _skel.get_bone_global_pose(_b_fwd).origin
	var u := _skel.get_bone_global_pose(_b_up).origin
	# THE BASIS IS THE CARD'S, not the hand's: a card is a flat thing whose LENGTH
	# runs out of the pinch along the fingers and whose FACE lies across it. Getting
	# these two the wrong way round is a card held edge-on to the player, which is a
	# card nobody can see.
	var z := (f - h)
	if z.length_squared() < 1e-9:
		return Transform3D()
	z = z.normalized()
	var y := (u - h)
	y = y - z * y.dot(z)
	if y.length_squared() < 1e-9:
		return Transform3D()
	y = y.normalized()
	return Transform3D(Basis(y.cross(z).normalized(), y, z), h)


# ---------------------------------------------------------------------------
# THE HAND-OFF: the deck's card becomes the hand's card
# ---------------------------------------------------------------------------
# The card is NOT part of this asset and is never duplicated: the game's own card
# object is drawn at `deck_card` while it is still the deck's, eased to `card_start`
# as the hand comes down for it, and asked of `grip` on every frame after that. The
# three agree by construction — `card_start` IS `grip` on the pickup frame, and the
# clip is authored so the pinch meets the deck's top card there to the millimetre —
# so there is no instant anywhere in a deal at which the card jumps.
#
# `pickup_frac` is where in the WIND-UP that instant falls, so CasinoEvents can put
# it on its own clock without knowing anything about frames or clips.
func pickup_frac() -> float:
	var c := _deal_clip()
	if c == null or c.release <= 0.0001:
		return 0.0
	return clampf(c.pickup / c.release, 0.0, 1.0)


# How far the pinch misses the deck's top card by on the pickup frame, in hand
# lengths. It is zero in the shipped asset and the harness holds it there: any other
# answer is a card that changes hands in mid-air.
func pickup_gap() -> float:
	var c := _deal_clip()
	return c.pickup_gap if c != null else 1e9


# The top card, lying in the deck under the left hand.
func deck_card() -> Transform3D:
	var c := _deal_clip()
	if not _placed or c == null:
		return Transform3D()
	return Transform3D(c.pickup_grip.basis, _world(c.deck_at))


# ...and the same card a moment later, pinched in the right hand's fingers. The two
# differ by the width of the deck's own edge, which is the card being drawn OFF it.
func card_start() -> Transform3D:
	var c := _deal_clip()
	if not _placed or c == null:
		return Transform3D()
	return Transform3D(c.pickup_grip.basis, _world(c.pickup_grip.origin))


# Where the deck is, in world space. It is welded to the left hand's bone, so this
# is a lookup rather than a guess, and the right hand's pick-up in the clip was
# authored against the same point.
func deck_point() -> Vector3:
	if not _placed or _b_deck < 0:
		return Vector3.ZERO
	return _world((_skel_local * _skel.get_bone_global_pose(_b_deck)).origin)


# Where a card leaves the fingers, for a card going to `at`. This is the pinch of
# the clip's own release frame with the aim applied, so the hand and the flight
# cannot disagree — they are the same expression.
func release_point(at: Vector3) -> Vector3:
	if not _placed:
		return at
	var c: Clip = _clips.get(A_DEAL)
	if c == null:
		return at
	return _world((_aim(c, at, 1.0) * c.grip).origin)


# BOTH ARE ANSWERED OFF THE LONG CLIP, whichever one the arm is actually running.
# CasinoEvents schedules all three cards of a hand at once, before the arm has been
# handed the first of them, so an answer that depended on which clip was live would
# depend on what the LAST deal happened to leave behind. The two clips' release
# frames are the same pinch to within a twentieth of a hand, so the card starts
# where the fingers are either way.

# ...and which way it is pointing as it goes, so the flight can START at the angle
# the hand let go at. A card that snaps to a new heading on the frame it is released
# is a card that was never in the hand.
func release_aim(at: Vector3) -> Vector3:
	if not _placed:
		return Vector3.FORWARD
	var c: Clip = _clips.get(A_DEAL)
	if c == null:
		return Vector3.FORWARD
	return ((_aim(c, at, 1.0) * c.grip).basis.z as Vector3).normalized()


# ---------------------------------------------------------------------------
# AIMING A BAKED DEAL AT A REAL SLOT
# ---------------------------------------------------------------------------
# One clip cannot land on every slot of every board, and re-solving the arm would
# throw away the pose that makes it look like a dealer. So the pose is kept and the
# arm is RE-ROOTED: swung about its own shoulder until the pinch is over the line to
# the slot, then slid the little that is left. Both are computed in the asset's own
# units, where the hand is 1.0 and the scale has already cancelled.
#
# WHERE THE FINGERS LET GO IS A DISTANCE MEASURED BACK FROM THE SLOT, not a fraction
# of the trip. "Most of the way there" puts the card within its own length of the
# slot — placed rather than dealt, with nothing left to travel — so it is a hand
# length back, or a card and a bit on a board whose row is too close for that.
func _aim(c: Clip, at: Vector3, w: float) -> Transform3D:
	if w <= 0.0001 or _s <= 0.0:
		return Transform3D()
	var l := _local(at)
	var home := Vector3(REST_X, WRIST_UP, 0.0)
	var flat := Vector3(l.x - home.x, 0.0, l.z - home.z)
	var trip := flat.length()
	if trip < 0.001:
		return Transform3D()
	var dir := flat / trip
	var card := _card / _s
	var gap := clampf(minf(0.95, trip * 0.60), minf(card * 1.15, trip * 0.85), 1.25)
	var want := Vector3(l.x, GRIP_UP, l.z) - dir * gap

	var p := c.pivot
	var have := c.grip.origin
	var a0 := Vector2(have.x - p.x, have.z - p.z)
	var a1 := Vector2(want.x - p.x, want.z - p.z)
	var yaw := 0.0
	if a0.length_squared() > 1e-8 and a1.length_squared() > 1e-8:
		yaw = a0.angle_to(a1) * w
	var swing := Transform3D(Basis(Vector3.UP, -yaw), Vector3.ZERO)
	swing.origin = p - swing.basis * p
	var slide := (want - swing * have) * w
	var flat2 := Vector3(slide.x, 0.0, slide.z)
	if flat2.length() > REACH_MAX:
		flat2 = flat2.normalized() * REACH_MAX
	slide = Vector3(flat2.x, clampf(slide.y, -LIFT_MAX, LIFT_MAX), flat2.z)
	return Transform3D(swing.basis, swing.origin + slide)


# How much of that aim is allowed on this frame of the clip. None of it while he is
# over the deck — that half has to keep meeting the LEFT hand, which does not move
# with the target — all of it through the swing and the release, and back to none
# before he settles, so the pose he returns to is the authored one.
static func _aim_weight(u: float) -> float:
	return smoothstep(AIM_HOLD, AIM_IN, u) * (1.0 - smoothstep(AIM_OUT_A, AIM_OUT_B, u))


# ONE DEAL, EVERYWHERE. Every card on every board and every difficulty is dealt by
# the same clip: the cards of a hand are staggered further apart than the animation
# is long (CasinoEvents.HAND_STAGGER), so the arm is never handed a second card
# before it has finished with the first, and there is nothing for a second, shorter
# clip to solve. DEAL_CARD stays in the asset — it is the same performance played
# slower, for an unhurried deal this game does not currently ask for.
func _deal_clip() -> Clip:
	var c: Clip = _clips.get(A_QUICK)
	return c if c != null else _clips.get(A_DEAL)


# ---------------------------------------------------------------------------
# The four things he does
# ---------------------------------------------------------------------------
# Each is a pure function of one number. Nothing here integrates or remembers —
# except the idle, which is nothing but a clock — for the same reason CasinoEvents
# does not: an event may be cancelled on any frame, and a pose that has to be
# unwound is a pose that will one day be left half-unwound.

# Waiting: the first frame of the idle, which is also the pose every clip starts and
# ends on, so nothing ever snaps when one hands over to another.
func rest() -> void:
	if not _placed:
		return
	_prev_phase = 2.0
	_prev_target = Vector3(1e9, 1e9, 1e9)
	_danced = false
	_pose(_clips[A_IDLE], 0.0)
	_push_shadows()


# THE IDLE BREATH. A dealer waiting is not a photograph, and a pair of hands frozen
# to the millimetre for ninety seconds is the one thing that would give away that
# they are props rather than a person's. Four seconds of authored drift, looped —
# and it is the only thing in this file that keeps a clock, because it is the only
# one the gameplay has no clock of its own for.
func idle(dt: float) -> void:
	if not _placed:
		return
	var c: Clip = _clips[A_IDLE]
	_idle_t = fposmod(_idle_t + dt, maxf(c.length, 0.0001))
	_pose(c, _idle_t)
	_push_shadows()


# ONE CARD BEING DEALT, as a phase from -1 (the hand has not moved yet) through 0
# (the card leaves the fingers) to 1 (the hand is back where it started).
#
# The zero is the release and not the start, because the CARD's clock is the one that
# matters: CasinoEvents knows when each card begins to fly and hands that mark
# straight over. A hand that arrives a frame after the card has left is the whole
# reason this file exists. The clip's own release frame is the same instant, so the
# phase maps onto it piecewise and the two halves stretch independently.
func deal(phase: float, at: Vector3) -> void:
	if not _placed:
		return
	var p := clampf(phase, -1.0, 1.0)
	_prev_phase = p
	_prev_target = at

	var c := _deal_clip()
	if c == null:
		return
	var t := (p + 1.0) * c.release if p < 0.0 \
		else c.release + p * (c.length - c.release)
	_pose(c, t)
	_reseat_arm(_aim(c, at, _aim_weight(t / maxf(c.length, 0.0001))))
	_push_shadows()


# THE CELEBRATION. `t` is seconds since it started, `secs` is its whole length, and
# the clip is stretched onto exactly that window — so it cannot outlast the freeze
# and the freeze cannot end while an arm is still in the air. It is 2.5 s authored,
# the round is frozen for 4.84, and the ceiling this may never pass is five.
#
# The dealer IS a pair of hands, so the joke is told with hands: he throws them out
# wide, snaps them back, rolls both wrists over, runs a wave through all ten fingers
# and finishes on two index fingers pointing at the ceiling. Nothing in it is ever
# lower or further forward than the resting pose, which is what keeps the promise
# that the celebration cannot cover the buttons or the hand it is celebrating.
func dance(t: float, secs: float) -> void:
	if not _placed:
		return
	var c: Clip = _clips.get(A_DANCE)
	if c == null:
		rest()
		return
	var u := clampf(t / maxf(secs, 0.0001), 0.0, 1.0)
	_pose(c, u * c.length)
	_push_shadows()
	if u >= 1.0 and not _danced:
		_danced = true
		celebration_finished.emit()



# ---------------------------------------------------------------------------
# Contact shadows
# ---------------------------------------------------------------------------
# One soft blob under each hand, spreading and fading as the hand rises and gone
# entirely above SHADOW_GONE. Elongated ALONG the hand rather than round, because a
# hand's shadow is a hand-shaped smudge and the pose already knows which way it lies.
# At this camera angle the shadow is the only cue that says how far above the table a
# thing is, and a hand with no shadow is a hand pasted onto the picture.
func _push_shadows() -> void:
	if _shadow == null:
		return
	var mm := _shadow.multimesh
	if not _placed:
		mm.instance_count = 0
		return
	var xf: Array[Transform3D] = []
	var col: Array[Color] = []
	for b: int in [_b_palm_l, _b_palm_r]:
		if b < 0:
			continue
		var g := _skel_local * _skel.get_bone_global_pose(b)
		var fwd_l := (g.basis * Vector3(0.0, 1.0, 0.0)).normalized()
		var p := _world(g.origin + fwd_l * 0.42)
		var lift := clampf((p.y - _felt) / maxf(SHADOW_GONE * _s, 0.001), 0.0, 1.0)
		var a := (1.0 - lift) * 0.50
		if a <= 0.004:
			continue
		var fwd := Vector3(fwd_l.x, 0.0, fwd_l.z)
		if fwd.length_squared() < 1e-6:
			fwd = Vector3.FORWARD
		fwd = fwd.normalized()
		var side := Vector3.UP.cross(fwd).normalized()
		var spread := _s * (0.50 + 0.80 * lift)
		xf.append(Transform3D(Basis(side * (spread * 0.78), Vector3.UP,
			fwd * (spread * 1.15)), Vector3(p.x, SHADOW_Y, p.z)))
		col.append(Color(1.0, 1.0, 1.0, a))
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_color(i, col[i])


# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------
# Still analytic and still `unshaded`, because that is how everything else on this
# table is lit and a hand shaded by a different model is a hand from a different
# game. What the Blender asset brings is the DATA the shader has always wanted:
# COLOR.rgb is the tint, painted per vertex in the .blend — warmer over the
# knuckles, deeper on the palm side, ivory on the cuff, near-black on the sleeve,
# gold on the link — and COLOR.a is the material:
#
#   skin    a broad, weak highlight — skin is not plastic and not matte either
#   cloth   almost no specular at all, and a trace of sheen at grazing angles, which
#           is what wool does and what black wool has instead of a highlight
#   metal   one tight bright one, for the cufflink
#
# ...and a GREEN BOUNCE off the table, which is the thing that actually seats the
# hands in the scene: the underside of a hand held over a lit green table is green,
# and no amount of key light will do that job.
static func _material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var s := Shader.new()
	s.code = """
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;
uniform vec3 c_shade;
uniform vec3 c_light;
uniform vec3 c_bounce;
uniform vec3 sun;
uniform vec3 rim_col;
uniform float rim_gain;
varying vec3 wnorm;
varying vec3 wpos;
varying vec3 tint;
varying float mat_id;
void vertex() {
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	tint = COLOR.rgb;
	mat_id = COLOR.a;
}
void fragment() {
	vec3 n = normalize(wnorm);
	vec3 l = normalize(sun);
	vec3 v = normalize(CAMERA_POSITION_WORLD - wpos);
	// The key, WRAPPED: skin and cloth both carry light round the terminator, and a
	// hard lambert on a rounded form is the look that reads as plastic.
	float lam = clamp((dot(n, l) + 0.35) / 1.35, 0.0, 1.0);
	lam = lam * lam * (3.0 - 2.0 * lam);
	vec3 base = tint * mix(c_shade, c_light, lam);
	// The felt, bouncing up. Only the down-facing half of the surface gets it.
	base += tint * c_bounce * clamp(-n.y, 0.0, 1.0) * 0.85;
	float cloth = 1.0 - abs(mat_id - 0.5) * 2.0;
	float metal = clamp(mat_id * 2.0 - 1.0, 0.0, 1.0);
	float skin = clamp(1.0 - mat_id * 2.0, 0.0, 1.0);
	// Skin is not plastic: a low, WIDE highlight rather than a small bright one.
	float shine = skin * 0.105 + metal * 0.90;
	float tight = mix(9.0, 86.0, metal) + cloth * 6.0;
	float spec = pow(clamp(dot(n, normalize(l + v)), 0.0, 1.0), tight);
	float graze = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 3.0);
	vec3 col = base + c_light * (spec * shine * lam)
		+ c_light * (graze * cloth * 0.10);
	col += rim_col * (graze * rim_gain * (0.45 + 0.55 * cloth));
	ALBEDO = col;
}
"""
	m.shader = s
	m.set_shader_parameter("c_shade", CasinoWorld.tone(DEALER_SHADE))
	m.set_shader_parameter("c_light", CasinoWorld.tone(DEALER_LIGHT))
	m.set_shader_parameter("c_bounce", CasinoWorld.tone(FELT_BOUNCE))
	m.set_shader_parameter("sun", CasinoWorld.SUN_DIR.normalized())
	m.set_shader_parameter("rim_col", CasinoWorld.tone(RIM))
	m.set_shader_parameter("rim_gain", RIM_GAIN)
	return m


# The same soft radial blob the cards drop on the felt, for the same reason.
static func _shadow_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var s := Shader.new()
	s.code = """
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
	m.shader = s
	m.set_shader_parameter("c_shadow", CasinoWorld.tone(SHADOW_C))
	m.render_priority = -1
	return m


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
