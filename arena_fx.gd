extends Node2D

# ArenaFX — the cinematic "grand colosseum" flourish behind the hub UI. It layers,
# from back to front:
#   • a bobbing CROWD silhouette bowl curving across the upper stands,
#   • draped medieval BANNERS that gently wave,
#   • flickering wall TORCHES with rising gold EMBERS,
#   • a low drift of ground SMOKE / dust,
#   • the centrepiece: a stone PLATFORM crowned with a big winged CHAMPIONSHIP
#     SHIELD bearing one of the board's BUTTONS, plus small winged BUTTONS that flap
#     across the screen now and then.
#   • once every 10–15s the crowd cheers and the wall torches flare, all settling
#     back within a second.
#
# Everything is cheap by construction and self-contained (it drives no shared
# shader): the crowd/platform are a handful of _draw() primitives redrawn per frame,
# banners are small waving Polygon2Ds, and all particles are a few low-amount
# CPUParticles2D reused across events. The node is added between the background and
# the interactive widgets, so all of it stays BEHIND the cards and buttons. The
# platform is placed low-centre so it reads through the empty state and sits
# harmlessly behind the carousel card when contests exist.

const SimonFlyer := preload("res://simon_flyer.gd")

const GOLD  := Color(1.0, 0.82, 0.30)
# The championship emblem is one of the board's BUTTONS, and it lights up in the
# board's own order — Crimson, Amber, Jade, Cyan, Violet — so the crest is playing a
# slow round of Simon on the dais. Colours come from SimonFlyer so the crest and the
# flyers are unmistakably the same prop at two sizes.
const EMBLEM_COLS: Array = SimonFlyer.BUTTON_COLS
const EMBLEM_HOLD := 2.2       # seconds one colour holds before the next lights
const TORCH := Color(1.0, 0.55, 0.18)
const EMBER := Color(1.0, 0.70, 0.30)
const SMOKE := Color(0.62, 0.60, 0.74)
# The crowd is now a ring of detailed cartoon spectators (heads, bodies, arms,
# hands) drawn around the stage and cheering. These palettes give each person a
# distinct skin tone, hair colour and festive shirt so the stands read as a
# real, varied audience rather than a silhouette bowl.
const SKIN_TONES := [
	Color(0.99, 0.82, 0.66), Color(0.96, 0.76, 0.58), Color(0.86, 0.66, 0.48),
	Color(0.72, 0.52, 0.36), Color(0.54, 0.38, 0.26), Color(0.42, 0.29, 0.20)]
const HAIR_COLS := [
	Color(0.10, 0.08, 0.08), Color(0.22, 0.14, 0.09), Color(0.42, 0.26, 0.13),
	Color(0.80, 0.63, 0.30), Color(0.66, 0.22, 0.16), Color(0.62, 0.62, 0.68),
	Color(0.16, 0.12, 0.14)]
const SHIRT_COLS := [
	Color(0.90, 0.26, 0.32), Color(0.24, 0.55, 0.92), Color(0.28, 0.74, 0.46),
	Color(0.96, 0.74, 0.24), Color(0.72, 0.36, 0.86), Color(0.96, 0.52, 0.22),
	Color(0.18, 0.74, 0.78), Color(0.94, 0.42, 0.62)]
const PANTS_COLS := [
	Color(0.20, 0.22, 0.32), Color(0.30, 0.24, 0.19), Color(0.15, 0.17, 0.27),
	Color(0.34, 0.30, 0.36), Color(0.22, 0.28, 0.24)]
const BANNER_PUR := Color(0.30, 0.12, 0.40)
const BANNER_CRIM := Color(0.46, 0.11, 0.20)

# Layout constants mirror arena_screen's card so the platform sits under it.
const CARD_TOP := 190.0
const CARD_H := 296.0

# The podium footprint is doubled again here (on top of its already-enlarged
# size) purely by growing its rx/ry — the y-offsets are untouched, so the
# front rim doesn't drift and the shield's resting point below needs no
# re-grounding this time; it keeps its exact screen position.
# The shield is planted at the BACK of the podium (a negative, "far side"
# offset in this faux-perspective) so the crown/door entrances stand in front
# of it on the dais rather than beside a centred trophy.
const SHIELD_Y := -70.0
# The championship shield is drawn a touch smaller than the (now larger) stage
# so it reads as a trophy resting ON the dais floor rather than floating above
# it — its footprint is SHIELD_SCALE * the enlarged stage_scale.
const SHIELD_SCALE := 1.42
# Local (unscaled, pre- _duel_scale) offsets for the crown / door slots either
# side of the shield — pushed out to the front-left / front-right edge of the
# doubled podium, standing on the same ground line (same row) on both sides.
const SIDE_X := 184.0
const SIDE_Y := 60.0

# The podium's centre and uniform scale in screen space, in sync with
# _build_platform()'s maths, exposed statically so the host screen can plant
# the crown/door controls directly on the dais without needing an FX instance.
# The stage is enlarged by STAGE_MULT and dropped lower on the page so it reads
# as a big floor the players stand on (rather than a pedestal floating mid-screen).
const STAGE_MULT := 1.4
const STAGE_DROP := 56.0

static func stage_center(sz: Vector2) -> Vector2:
	return Vector2(sz.x * 0.5, CARD_TOP + CARD_H * 0.82 + STAGE_DROP)

static func stage_scale(sz: Vector2) -> float:
	return clampf(sz.x / 520.0, 0.82, 1.25) * STAGE_MULT

# Screen-space point where the crown (side = -1) or door (side = +1) should
# stand on the podium — the host uses this as the ground-anchor for its
# action_card()/layout_action_card() pair.
static func side_slot_pos(sz: Vector2, side: float) -> Vector2:
	return stage_center(sz) + Vector2(side * SIDE_X, SIDE_Y) * stage_scale(sz)

var _sz := Vector2.ZERO
var _t := 0.0
# The crowd / platform / spotlights are the heavy redraws; gate them to ~30fps
# (this is ambient background behind the UI, so half-rate is invisible) instead
# of repainting every one of the ~50 spectators and the layered dais each frame.
var _redraw_acc := 0.0
const REDRAW_DT := 1.0 / 30.0

# ---- ambient ----
# The crowd is drawn in two layers: `_crowd_bodies` holds a baked body Sprite2D per
# spectator (drawn once, then just repositioned for the bob) with the ground shadows
# painted under them; `_crowd_arms` paints only the waving arms on top each tick.
var _crowd_bodies: Node2D
var _crowd_arms: Node2D
var _people: Array[Dictionary] = []          # cheering spectators around the stage
var _banners: Array[Dictionary] = []      # {node, cx, halfw, len, phase, cols}
var _torch_lamps: Array[Sprite2D] = []
var _torch_phase: PackedFloat32Array = PackedFloat32Array()
var _embers: CPUParticles2D
var _smoke: CPUParticles2D

# ---- centrepiece (platform) ----
# The dais is fully static (stone courses, gold rings, rivets) — it's drawn ONCE
# into its own node so the per-frame path only repaints the animated shield on
# `_duel`. This removes ~130 primitives (incl. 120 rivet circles) from every
# redraw, which is the single biggest saving for low-end phones.
var _dais: Node2D
var _duel: Node2D
var _platform_c := Vector2.ZERO
var _duel_scale := 1.0
var _spot: Node2D

# ---- winged wheels that flap across the arena ----
var _flyers: Array = []

# ---- event envelopes ----
var _cheer := 0.0          # 0..1 crowd cheer + torch flare (decays ~1s)
var _big_timer := 12.0     # countdown to the next crowd cheer + torch flare

func setup(size: Vector2) -> void:
	_sz = size
	_build()
	set_process(true)

func relayout(size: Vector2) -> void:
	# The hub calls this from its _layout(), which fires once right after setup() with
	# the SAME viewport size — rebuilding then would re-run the whole crowd bake for
	# nothing. Only rebuild when the size actually changed (a rotation / resize).
	if size == _sz:
		return
	_sz = size
	_build()

# Freeze all animation + particles. Used while a blur-scrim modal is open: the FX
# sits behind a heavy full-screen blur there, so it's effectively invisible and
# there's no reason to keep paying for its redraws / particle sim on a phone.
func pause() -> void:
	if not is_processing():
		return
	set_process(false)
	if _embers:
		_embers.emitting = false
	if _smoke:
		_smoke.emitting = false
	for f in _flyers:
		if is_instance_valid(f):
			(f as Node).set_process(false)

func resume() -> void:
	if is_processing():
		return
	set_process(true)
	if _embers:
		_embers.emitting = true
	if _smoke:
		_smoke.emitting = true
	for f in _flyers:
		if is_instance_valid(f):
			(f as Node).set_process(true)

# ---------------- build ----------------

func _build() -> void:
	for c in get_children():
		c.queue_free()
	_torch_lamps.clear()
	_banners.clear()
	_flyers.clear()
	_people.clear()

	_build_crowd()
	_build_smoke()
	_build_banners()
	_build_torches()
	_build_spotlights()
	_build_platform()
	_build_embers()
	_build_flyers()

	_big_timer = randf_range(10.0, 15.0)

# --- crowd: individual cartoon spectators packed around the BACK of the stage ---
# Each person is generated once (stable position / palette / cheer style). PERF: the
# body (legs, torso, neck, head, hair) never changes shape — only the whole figure's
# vertical BOB and the arms move — so the body is baked ONCE into a small sprite and
# thereafter only repositioned; per frame we redraw just the two arms. That's ~7
# primitives per fan instead of ~31, the biggest per-frame saving for phones. They're
# packed in a band wrapping the back rim and both flanks of the dais; the front
# (viewer) half is left empty. Flank spectators turn to face the centre.
const _PERSON_FW := 48                  # baked body sprite size (design px)
const _PERSON_FH := 84
const _PERSON_FEET := Vector2(24.0, 76.0)   # feet anchor inside the baked sprite

func _build_crowd() -> void:
	# bodies (+ ground shadows) underneath, arms layer on top
	_crowd_bodies = Node2D.new()
	_crowd_bodies.draw.connect(_draw_crowd_shadows)
	add_child(_crowd_bodies)
	_people.clear()

	var c := stage_center(_sz)
	var sc := stage_scale(_sz)
	var seed := 0

	# Outer stone-rim ellipse (mirrors _draw_platform's base course); the crowd is
	# planted right against this rim so everyone stands hard up against the dais.
	var rim_rx := 322.0 * sc
	var rim_ry := 76.0 * sc
	var mid_y := c.y + 12.0 * sc

	# Angles sweep from the lower-left flank, up and over the back, down to the
	# lower-right flank; the front wedge (~32°..148°) is skipped so the near half
	# of the stage stays clear. Four staggered rows give the crowd real depth: the
	# front row is full detailed figures; the three back rows are packed with cheap
	# simplified spectators (a bobbing torso + head, a fraction of the draw calls)
	# so the stands read as a big roaring crowd without the per-frame cost of
	# drawing every distant fan in full.
	const ROWS := 1                                          # only the front row that hugs the stage; far rows removed
	var a0 := deg_to_rad(148.0)                              # lower-left flank
	var a1 := deg_to_rad(392.0)                              # lower-right flank (=32°)
	var base_n := int(clampf(_sz.x / 100.0, 9.0, 14.0))
	for row in ROWS:
		var far := float(row)                               # 0 = front row
		var simple := row >= 1                              # only the front row is a full figure; the rest are cheap fans
		# detailed rows thin out with depth; distant simplified rows pack denser
		var n := (base_n - row * 3) if not simple else (base_n + (row - 1) * 3)
		var rmul := 1.0 + far * 0.035                        # each row only a hair further out
		var lift := far * 5.0 * sc                           # …barely lifted, so all rows hug the dais
		var scl := lerpf(1.12, 0.60, far / float(maxi(ROWS - 1, 1)))
		var stagger := (0.5 / float(n)) * far                # offset each row into the gaps
		for i in n:
			var f := (float(i) + 0.5) / float(n) + stagger
			var ang := lerpf(a0, a1, f)
			var x := c.x + cos(ang) * (rim_rx + 6.0 * sc) * rmul
			var y := mid_y + sin(ang) * (rim_ry + 5.0 * sc) * rmul - lift
			y += (_rnd(seed * 29 + 9) - 0.5) * 5.0 * sc       # break the straight line
			# The two extreme flank spectators (far left / far right) otherwise dip
			# into the low front edge of the rim and read as standing BELOW the stage.
			# Tuck just those endpoints inward toward centre and lift them a little so
			# they sit on the dais with the rest of the row.
			var t_end := clampf((0.16 - minf(f, 1.0 - f)) / 0.16, 0.0, 1.0)
			x = c.x + (x - c.x) * (1.0 - 0.34 * t_end)
			y -= 60.0 * sc * t_end
			# flank spectators turn toward the centre; the back rows look straight out
			var face := clampf(-cos(ang) * 1.7, -1.0, 1.0)
			_add_person(Vector2(x, y), scl, seed, face, simple)
			seed += 1

	# Draw back-to-front (higher on screen first) so nearer fans overlap cleanly.
	_people.sort_custom(func(a, b): return a["pos"].y < b["pos"].y)

	# Bake each spectator's body into a sprite (added in sorted order so nearer fans
	# sit in front), then add the arms layer above all bodies.
	for p in _people:
		var spr := Sprite2D.new()
		spr.texture = _bake_person(p)
		spr.centered = false
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_crowd_bodies.add_child(spr)
		p["sprite"] = spr
	_crowd_arms = Node2D.new()
	_crowd_arms.draw.connect(_draw_crowd_arms)
	add_child(_crowd_arms)

	_update_crowd()
	_crowd_bodies.queue_redraw()

# Deterministic 0..1 hash so a person's look never re-randomises between rebuilds.
static func _rnd(seed: int) -> float:
	return absf(fmod(sin(float(seed) * 12.9898 + 3.17) * 43758.5453, 1.0))

# The bake-relevant appearance of spectator `seed` at facing `face` and scale `scl` —
# exactly the fields _bake_person reads (and nothing positional). Factored out so the
# live crowd build and the loading-screen pre-warm derive byte-identical looks, and thus
# identical bake cache keys. See warm_crowd / _crowd_looks.
static func _person_look(scl: float, seed: int, face: float) -> Dictionary:
	return {
		"s": scl * 1.05,
		"face": face,
		"skin": SKIN_TONES[int(_rnd(seed * 11 + 3) * SKIN_TONES.size()) % SKIN_TONES.size()],
		"hair": HAIR_COLS[int(_rnd(seed * 13 + 5) * HAIR_COLS.size()) % HAIR_COLS.size()],
		"shirt": SHIRT_COLS[int(_rnd(seed * 17 + 6) * SHIRT_COLS.size()) % SHIRT_COLS.size()],
		"pants": PANTS_COLS[int(_rnd(seed * 19 + 7) * PANTS_COLS.size()) % PANTS_COLS.size()],
		"flip": _rnd(seed * 23 + 8) < 0.5,
	}

func _add_person(pos: Vector2, scl: float, seed: int, face: float = 0.0, simple: bool = false) -> void:
	var d := _person_look(scl, seed, face)
	d["pos"] = pos
	d["simple"] = simple
	d["anim"] = int(_rnd(seed * 7 + 1) * 5.0) % 5
	d["phase"] = _rnd(seed * 3 + 2) * TAU
	d["speed"] = lerpf(0.85, 1.25, _rnd(seed * 5 + 4))
	_people.append(d)

# Ground shadows sit under the bodies — static (they don't bob), so painted once.
func _draw_crowd_shadows() -> void:
	for p in _people:
		var o: Vector2 = p["pos"]
		var s: float = p["s"]
		_crowd_bodies.draw_circle(o + Vector2(0, 1.0 * s), 8.0 * s, Color(0.02, 0.02, 0.05, 0.28))

# Per-tick crowd update: recompute each fan's bob + arm targets, slide the body
# sprite to the bobbed position, and flag the arms layer for a repaint.
func _update_crowd() -> void:
	for p in _people:
		var pose := _person_pose(p)
		p["_pose"] = pose
		var spr: Sprite2D = p.get("sprite")
		if spr:
			spr.position = pose["b"] - _PERSON_FEET
	if _crowd_arms:
		_crowd_arms.queue_redraw()

# The animated pose for one spectator: vertical bob + the four arm targets (elbow /
# hand, left / right) for its cheer style. Returns them plus `b`, the bobbed feet
# origin in screen space. `anim` picks one of five cheer styles.
func _person_pose(p: Dictionary) -> Dictionary:
	var s: float = p["s"]
	var anim: int = p["anim"]
	var ph: float = p["phase"]
	var spd: float = p["speed"]
	var boost := 1.0 + _cheer * 0.7                        # everyone cheers harder on a roar
	var t := _t * spd + ph
	var shoulder_y := -30.0 * s

	var lel := Vector2.ZERO; var lha := Vector2.ZERO
	var rel := Vector2.ZERO; var rha := Vector2.ZERO
	var bob := 0.0
	match anim:
		0:  # both arms overhead, waving side to side
			var sway := sin(t * 3.0) * 3.0 * s * boost
			lel = Vector2(-9.0 * s, shoulder_y - 6.0 * s); lha = Vector2(-6.0 * s + sway, shoulder_y - 14.0 * s)
			rel = Vector2(9.0 * s, shoulder_y - 6.0 * s);  rha = Vector2(6.0 * s + sway, shoulder_y - 14.0 * s)
			bob = sin(t * 2.0) * 1.6 * s
		1:  # clapping — hands meet and part in front of the chest
			var c := sin(t * 7.0) * 0.5 + 0.5
			var gap := lerpf(1.5 * s, 7.0 * s * boost, c)
			var cy := shoulder_y + 5.0 * s
			lel = Vector2(-8.0 * s, shoulder_y + 3.0 * s); lha = Vector2(-gap, cy)
			rel = Vector2(8.0 * s, shoulder_y + 3.0 * s);  rha = Vector2(gap, cy)
			bob = sin(t * 3.5) * 1.0 * s
		2:  # one fist pumping up and down
			var pump := (sin(t * 4.0) * 0.5 + 0.5) * boost
			rel = Vector2(7.5 * s, shoulder_y - 3.0 * s); rha = Vector2(6.0 * s, lerpf(shoulder_y - 5.0 * s, shoulder_y - 15.0 * s, pump))
			lel = Vector2(-7.0 * s, shoulder_y + 7.0 * s); lha = Vector2(-8.0 * s, shoulder_y + 13.0 * s)
			bob = pump * 2.2 * s
		3:  # jumping with both arms in a V
			var jb := absf(sin(t * 2.4))
			bob = jb * 7.5 * s * boost
			lel = Vector2(-10.0 * s, shoulder_y - 6.0 * s); lha = Vector2(-13.0 * s, shoulder_y - 12.0 * s)
			rel = Vector2(10.0 * s, shoulder_y - 6.0 * s);  rha = Vector2(13.0 * s, shoulder_y - 12.0 * s)
		_:  # alternating arms (one up, one down, swapping)
			var a := sin(t * 3.2) * 0.5 + 0.5
			lha = Vector2(-7.0 * s, lerpf(shoulder_y + 13.0 * s, shoulder_y - 13.0 * s, a))
			lel = Vector2(-8.0 * s, lerpf(shoulder_y + 6.0 * s, shoulder_y - 6.0 * s, a))
			rha = Vector2(7.0 * s, lerpf(shoulder_y + 13.0 * s, shoulder_y - 13.0 * s, 1.0 - a))
			rel = Vector2(8.0 * s, lerpf(shoulder_y + 6.0 * s, shoulder_y - 6.0 * s, 1.0 - a))
			bob = sin(t * 3.0) * 1.5 * s

	return {"b": p["pos"] - Vector2(0, bob), "lel": lel, "lha": lha, "rel": rel, "rha": rha}

# Draw only the waving arms (sleeve + skin forearm + hand) for every spectator, over
# the baked bodies. Reads the pose cached by _update_crowd this tick.
func _draw_crowd_arms() -> void:
	for p in _people:
		var pose: Dictionary = p.get("_pose", {})
		if pose.is_empty():
			continue
		var s: float = p["s"]
		var shirt: Color = p["shirt"]
		var skin: Color = p["skin"]
		var b: Vector2 = pose["b"]
		var shoulder_y := -30.0 * s
		var l_sh := b + Vector2(-6.0 * s, shoulder_y + 1.0 * s)
		var r_sh := b + Vector2(6.0 * s, shoulder_y + 1.0 * s)
		_limb(_crowd_arms, l_sh, b + pose["lel"], 4.4 * s, shirt)
		_limb(_crowd_arms, r_sh, b + pose["rel"], 4.4 * s, shirt)
		_limb(_crowd_arms, b + pose["lel"], b + pose["lha"], 3.4 * s, skin)
		_limb(_crowd_arms, b + pose["rel"], b + pose["rha"], 3.4 * s, skin)
		_crowd_arms.draw_circle(b + pose["lha"], 2.9 * s, skin)   # hands
		_crowd_arms.draw_circle(b + pose["rha"], 2.9 * s, skin)

# A rounded limb segment: a thick line with circular caps at both ends.
func _limb(canvas: CanvasItem, a: Vector2, c: Vector2, w: float, col: Color) -> void:
	canvas.draw_line(a, c, col, w)
	canvas.draw_circle(a, w * 0.5, col)
	canvas.draw_circle(c, w * 0.5, col)

# ---- one-time body bake (legs / torso / neck / head / hair) into a sprite ----

# Rasterise a spectator's static body (everything except the arms + ground shadow) into
# a small RGBA image, composited back-to-front with a 1px soft edge. The result is shown
# as a Sprite2D anchored at _PERSON_FEET, so a bob is just a cheap vertical move. Built
# in the same local frame as the old _draw_person (origin = feet, y up = negative).
# Baked spectator bodies keyed by their appearance signature, shared across every
# ArenaFX instance for the whole session. The body art is fully determined by the
# figure's scale, facing and palette — never by its screen position — and that scale is
# constant (single crowd row), so the same handful of textures recur on every hub open
# and on the redundant relayout rebuild. Rasterising each is ~4k pixels × 11 shapes of
# GDScript, so re-baking them was the bulk of the ~0.5-1s stall when opening the Arena;
# caching means only the FIRST time a given look is needed pays for it.
static var _person_cache: Dictionary = {}

# Pre-bake every spectator body the hub's crowd will need for a viewport of `size`,
# populating the shared texture cache. Called from the loading screen so the FIRST
# Arena open reuses these instead of rasterising the whole crowd on the main thread the
# instant the hub appears (the ~0.5-1s open stall). Pure CPU work, safe off-tree — no
# nodes are created. A no-op once the cache already holds these looks; a viewport
# rotation between here and the open just re-bakes on demand (self-healing).
static func warm_crowd(size: Vector2) -> void:
	for look in _crowd_looks(size):
		_bake_person(look)

# The set of distinct spectator LOOKS for a `size`-wide viewport, matching the single
# front row _build_crowd lays out (ROWS == 1 → constant 1.12 scale, no stagger). Only
# the appearance (scale / facing / palette) is reproduced here; positions live in the
# live build. Kept in lockstep with _build_crowd's per-fan derivation so both bake the
# same cache keys — if that loop changes shape, warming simply misses and the open
# re-bakes as it does today (no correctness impact).
static func _crowd_looks(size: Vector2) -> Array:
	var looks: Array = []
	var a0 := deg_to_rad(148.0)
	var a1 := deg_to_rad(392.0)
	var base_n := int(clampf(size.x / 100.0, 9.0, 14.0))
	for i in base_n:
		var f := (float(i) + 0.5) / float(base_n)
		var ang := lerpf(a0, a1, f)
		var face := clampf(-cos(ang) * 1.7, -1.0, 1.0)
		looks.append(_person_look(1.12, i, face))
	return looks

static func _bake_person(p: Dictionary) -> ImageTexture:
	var s: float = p["s"]
	var skin: Color = p["skin"]
	var hair: Color = p["hair"]
	var shirt: Color = p["shirt"]
	var pants: Color = p["pants"]
	var fdir := -1.0 if p["flip"] else 1.0
	var face: float = p.get("face", 0.0)

	var key := "%.3f|%d|%.3f|%s|%s|%s|%s" % [s, 1 if p["flip"] else 0, face, skin, hair, shirt, pants]
	var cached: Variant = _person_cache.get(key)
	if cached is ImageTexture:
		return cached

	var hip_y := -15.0 * s
	var shoulder_y := -30.0 * s
	var head_cy := -39.0 * s
	var head_r := 6.2 * s
	var l_hip := Vector2(-3.2 * s, hip_y); var r_hip := Vector2(3.2 * s, hip_y)
	var l_foot := Vector2(-3.4 * s, 0.0); var r_foot := Vector2(3.4 * s, 0.0)
	var hip_c := Vector2(0, hip_y); var sho_c := Vector2(0, shoulder_y)
	var head := Vector2(0, head_cy)
	var shade_side := (-signf(face)) if absf(face) > 0.05 else fdir

	# Shape list, back-to-front (same order the old code drew them). Each is a circle
	# {"r"} or a capsule {"a","b","r"}, with a colour.
	var shapes: Array = [
		{"a": l_hip, "b": l_foot, "r": 2.3 * s, "col": pants},      # legs
		{"a": r_hip, "b": r_foot, "r": 2.3 * s, "col": pants},
		{"c": l_foot + Vector2(-0.6 * s, 0), "r": 2.4 * s, "col": Color(0.10, 0.09, 0.12)},   # shoes
		{"c": r_foot + Vector2(-0.6 * s, 0), "r": 2.4 * s, "col": Color(0.10, 0.09, 0.12)},
		{"a": hip_c, "b": sho_c, "r": 6.75 * s, "col": shirt},      # torso
		{"a": hip_c + Vector2(fdir * 2.0 * s, 0), "b": sho_c + Vector2(fdir * 2.0 * s, 0),
			"r": 1.5 * s, "col": shirt.lightened(0.18)},            # front panel highlight
		{"a": sho_c + Vector2(0, -1.0 * s), "b": head + Vector2(0, head_r * 0.7),
			"r": 2.2 * s, "col": skin},                             # neck
		{"c": head, "r": head_r, "col": skin},                      # head
		{"c": head + Vector2(shade_side * head_r * 0.5, head_r * 0.2), "r": head_r * 0.62,
			"col": skin.darkened(0.10)},                            # shading crescent
		{"c": head + Vector2(0, -head_r * 0.16), "r": head_r * 1.08, "col": hair},   # hair cap
		{"c": head + Vector2(0, head_r * 0.55), "r": head_r * 1.0, "col": skin},     # reveal face
	]

	# Precompute an expanded AABB per shape (its extent + the 1px soft edge) so the
	# per-pixel loop can cheaply skip the shapes a pixel is nowhere near — a pixel touches
	# only one or two of the eleven shapes, so this rejects most of the distance math that
	# dominated the bake.
	var lows := PackedVector2Array()
	var highs := PackedVector2Array()
	for sh in shapes:
		var rr: float = float(sh["r"]) + 1.0
		var lo: Vector2
		var hi: Vector2
		if sh.has("c"):
			var cc: Vector2 = sh["c"]
			lo = cc - Vector2(rr, rr); hi = cc + Vector2(rr, rr)
		else:
			var sa: Vector2 = sh["a"]; var sb: Vector2 = sh["b"]
			lo = Vector2(minf(sa.x, sb.x), minf(sa.y, sb.y)) - Vector2(rr, rr)
			hi = Vector2(maxf(sa.x, sb.x), maxf(sa.y, sb.y)) + Vector2(rr, rr)
		lows.append(lo); highs.append(hi)

	var img := Image.create(_PERSON_FW, _PERSON_FH, false, Image.FORMAT_RGBA8)
	for py in _PERSON_FH:
		for px in _PERSON_FW:
			# local point (drawing frame): feet at _PERSON_FEET, y up = negative
			var lp := Vector2(float(px) + 0.5, float(py) + 0.5) - _PERSON_FEET
			var out := Color(0, 0, 0, 0)
			for si in shapes.size():
				if lp.x < lows[si].x or lp.x > highs[si].x or lp.y < lows[si].y or lp.y > highs[si].y:
					continue
				var sh: Dictionary = shapes[si]
				var d: float
				if sh.has("c"):
					d = lp.distance_to(sh["c"])
				else:
					d = _dist_to_seg(lp, sh["a"], sh["b"])
				var cov := clampf(0.5 + (sh["r"] - d), 0.0, 1.0)   # 1px soft edge
				if cov > 0.0:
					var col: Color = sh["col"]
					out = _over(out, Color(col.r, col.g, col.b, col.a * cov))
			img.set_pixelv(Vector2i(px, py), out)
	var tex := ImageTexture.create_from_image(img)
	_person_cache[key] = tex
	return tex

# Shortest distance from point p to segment a→b.
static func _dist_to_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.dot(ab), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)

# Straight "over" alpha compositing (src over dst).
static func _over(dst: Color, src: Color) -> Color:
	var a := src.a + dst.a * (1.0 - src.a)
	if a <= 0.0001:
		return Color(0, 0, 0, 0)
	var inv := dst.a * (1.0 - src.a)
	return Color(
		(src.r * src.a + dst.r * inv) / a,
		(src.g * src.a + dst.g * inv) / a,
		(src.b * src.a + dst.b * inv) / a, a)

# --- draped, gently waving banners hung from the upper walls ---
func _build_banners() -> void:
	var xs := PackedFloat32Array([0.12, 0.32, 0.68, 0.88])
	var top_y := _sz.y * 0.02
	var length := clampf(_sz.y * 0.20, 96.0, 168.0)
	var halfw := clampf(_sz.x * 0.028, 20.0, 34.0)
	for k in xs.size():
		var node := Polygon2D.new()
		node.position = Vector2(xs[k] * _sz.x, top_y)
		var col: Color = BANNER_PUR if (k % 2 == 0) else BANNER_CRIM
		node.color = col
		add_child(node)
		# a slim gold hanging bar at the top of each banner
		var bar := Polygon2D.new()
		bar.position = node.position
		bar.color = Color(GOLD.r, GOLD.g, GOLD.b, 0.85)
		bar.polygon = PackedVector2Array([
			Vector2(-halfw - 3, -4), Vector2(halfw + 3, -4),
			Vector2(halfw + 3, 2), Vector2(-halfw - 3, 2)])
		add_child(bar)
		_banners.append({
			"node": node, "bar": bar, "halfw": halfw, "len": length,
			"phase": float(k) * 1.3, "cols": 6})
	_update_banners()

func _update_banners() -> void:
	for b in _banners:
		var node: Polygon2D = b["node"]
		var halfw: float = b["halfw"]
		var length: float = b["len"]
		var segs: int = b["cols"]
		var phase: float = b["phase"]
		var lefts: Array[Vector2] = []
		var rights: Array[Vector2] = []
		var cols: PackedColorArray = PackedColorArray()
		for i in range(segs + 1):
			var f := float(i) / float(segs)                  # 0 top … 1 bottom
			var y := length * f
			var sway := sin(_t * 1.1 + phase + f * 2.2) * (2.0 + 6.0 * f)
			var hw := halfw * (1.0 - 0.16 * f)               # slight taper
			lefts.append(Vector2(sway - hw, y))
			rights.append(Vector2(sway + hw, y))
		# darken toward the bottom (fabric falloff)
		var poly := PackedVector2Array()
		for i in range(segs + 1):
			poly.append(lefts[i])
		for i in range(segs, -1, -1):
			poly.append(rights[i])
		node.polygon = poly
		# vertex_colors multiply the node's base color, so keep them grayscale: a
		# simple top→bottom darkening of the fabric (no double-applied hue).
		for i in range(segs + 1):
			var shade := lerpf(1.0, 0.55, float(i) / float(segs))
			cols.append(Color(shade, shade, shade, 0.92))
		for i in range(segs, -1, -1):
			var shade := lerpf(1.0, 0.55, float(i) / float(segs))
			cols.append(Color(shade, shade, shade, 0.92))
		node.vertex_colors = cols
		# keep the gold bar riding with the banner
		var bar: Polygon2D = b["bar"]
		bar.position = node.position

# --- flickering wall torches (warm glow that flares during arena events) ---
func _build_torches() -> void:
	var xs := PackedFloat32Array([0.07, 0.28, 0.72, 0.93])
	var ys := PackedFloat32Array([0.16, 0.11, 0.11, 0.16])
	_torch_phase = PackedFloat32Array()
	_torch_phase.resize(xs.size())
	for k in xs.size():
		var lamp := Sprite2D.new()
		lamp.texture = SimonFlyer.radial()
		lamp.position = Vector2(xs[k] * _sz.x, ys[k] * _sz.y)
		lamp.scale = Vector2.ONE * (58.0 / 128.0)
		lamp.modulate = Color(TORCH.r, TORCH.g, TORCH.b, 0.6)
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		lamp.material = m
		add_child(lamp)
		_torch_lamps.append(lamp)
		_torch_phase[k] = float(k) * 1.7

# --- rising gold embers across the arena ---
func _build_embers() -> void:
	_embers = CPUParticles2D.new()
	_embers.texture = SimonFlyer.radial()
	_embers.amount = 14
	_embers.lifetime = 5.0
	_embers.preprocess = 5.0
	_embers.position = Vector2(_sz.x * 0.5, _sz.y + 8.0)
	_embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_embers.emission_rect_extents = Vector2(_sz.x * 0.5, 6.0)
	_embers.direction = Vector2(0, -1)
	_embers.spread = 18.0
	_embers.gravity = Vector2(0, -8.0)
	_embers.initial_velocity_min = 16.0
	_embers.initial_velocity_max = 34.0
	_embers.scale_amount_min = 0.06
	_embers.scale_amount_max = 0.14
	_embers.color = EMBER
	_embers.color_ramp = _fade_ramp(Color(1.0, 0.78, 0.36))
	var em := CanvasItemMaterial.new()
	em.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_embers.material = em
	add_child(_embers)

# --- low ground smoke / dust that drifts slowly sideways ---
func _build_smoke() -> void:
	_smoke = CPUParticles2D.new()
	_smoke.texture = SimonFlyer.radial()
	_smoke.amount = 10
	_smoke.lifetime = 7.0
	_smoke.preprocess = 7.0
	_smoke.position = Vector2(_sz.x * 0.5, _sz.y - 10.0)
	_smoke.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_smoke.emission_rect_extents = Vector2(_sz.x * 0.5, 10.0)
	_smoke.direction = Vector2(1, -0.35)
	_smoke.spread = 30.0
	_smoke.gravity = Vector2(6.0, -3.0)
	_smoke.initial_velocity_min = 5.0
	_smoke.initial_velocity_max = 16.0
	_smoke.scale_amount_min = 1.4
	_smoke.scale_amount_max = 2.8
	_smoke.color = Color(SMOKE.r, SMOKE.g, SMOKE.b, 0.10)
	_smoke.color_ramp = _fade_ramp(Color(SMOKE.r, SMOKE.g, SMOKE.b, 0.14))
	add_child(_smoke)

# --- the centrepiece: the inlaid wheel platform, redrawn each frame ---
func _build_platform() -> void:
	_platform_c = stage_center(_sz)
	_duel_scale = stage_scale(_sz)

	# Static stone dais — painted once (Node2D draws itself on entering the tree
	# and again only when _build() rebuilds it on a resize).
	_dais = Node2D.new()
	_dais.position = _platform_c
	_dais.scale = Vector2.ONE * _duel_scale
	_dais.draw.connect(_draw_dais)
	add_child(_dais)

	# Animated championship shield — the only part of the podium that repaints.
	_duel = Node2D.new()
	_duel.position = _platform_c
	_duel.scale = Vector2.ONE * _duel_scale
	_duel.draw.connect(_draw_champion_shield)
	add_child(_duel)

# --- soft spotlights raking down from above onto the crown / shield / door ---
func _build_spotlights() -> void:
	_spot = Node2D.new()
	_spot.position = stage_center(_sz)
	_spot.scale = Vector2.ONE * stage_scale(_sz)
	_spot.draw.connect(_draw_spotlights)
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_spot.material = m
	add_child(_spot)

# --- little winged BUTTONS that flap across the arena now and then ---
func _build_flyers() -> void:
	# Two crossers on staggered timers so the arena always has a bit of life above
	# the platform without ever feeling busy (each waits 15–28s between passes).
	# Each wears a different cap colour, picked from the board's five, so the pair
	# never reads as the same prop crossing twice.
	var cols: Array = SimonFlyer.BUTTON_COLS.duplicate()
	cols.shuffle()
	for i in 2:
		var f := SimonFlyer.new()
		add_child(f)
		f.setup(_sz, {"mode": "cross", "scale": 0.58,
			"art": "button", "button_color": cols[i % cols.size()]})
		_flyers.append(f)

func _fade_ramp(peak: Color) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	g.colors = PackedColorArray([
		Color(peak.r, peak.g, peak.b, 0.0), peak,
		Color(peak.r, peak.g, peak.b, 0.0)])
	return g

# ---------------- platform drawing ----------------

# Three soft cones of light raking down from above onto the crown, the shield
# and the door — drawn additively, behind everything else, so the podium
# reads as a lit stage rather than three separate props.
func _draw_spotlights() -> void:
	var flicker := 0.85 + 0.15 * sin(_t * 0.6)
	for target in [Vector2(-SIDE_X, SIDE_Y), Vector2(0.0, SHIELD_Y), Vector2(SIDE_X, SIDE_Y)]:
		_draw_spot_cone(target, flicker)

func _draw_spot_cone(target: Vector2, flicker: float) -> void:
	var src := Vector2(target.x, target.y - 220.0)
	var col := Color(1.0, 0.93, 0.74)
	for i in range(3):
		var a := (0.11 - float(i) * 0.032) * flicker
		var top_w := 12.0 + float(i) * 3.0
		var bot_w := 40.0 + float(i) * 12.0
		var poly := PackedVector2Array([
			src + Vector2(-top_w * 0.5, 0.0), src + Vector2(top_w * 0.5, 0.0),
			target + Vector2(bot_w * 0.5, 0.0), target + Vector2(-bot_w * 0.5, 0.0)])
		_spot.draw_colored_polygon(poly, Color(col.r, col.g, col.b, a))
	# a soft pool of light where the beam lands on the podium
	_spot.draw_circle(target, 28.0, Color(col.r, col.g, col.b, 0.13 * flicker))

func _draw_dais() -> void:
	# a squashed stone dais with a soft cast shadow and a beveled, rivet-studded
	# rim — the whole podium footprint doubled again (rx/ry only) so it reads
	# as a genuinely big stage rather than a pedestal under the shield. Fully
	# static, so it's painted once onto `_dais` (never in the per-frame path).
	_draw_ellipse(Vector2(0, 27), 364, 92, Color(0.02, 0.02, 0.05, 0.5), 48)   # cast shadow
	_draw_ellipse(Vector2(0, 15), 346, 84, Color(0.13, 0.11, 0.18, 0.96), 48)  # dark base course
	# a thin gold banding line around the outer stone course for a richer edge
	_draw_ellipse(Vector2(0, 13), 336, 80, Color(GOLD.r, GOLD.g, GOLD.b, 0.30), 48)
	_draw_ellipse(Vector2(0, 11), 326, 76, Color(0.21, 0.18, 0.28, 0.98), 48)  # upper course
	_draw_ellipse(Vector2(0, 7), 300, 68, Color(0.29, 0.25, 0.38, 1.0), 48)    # polished top face
	# a broad soft sheen across the top face (light raking from above)
	_draw_ellipse(Vector2(0, 0), 244, 46, Color(1.0, 0.98, 0.94, 0.05), 40)
	_draw_ellipse(Vector2(0, -2), 176, 30, Color(1.0, 0.99, 0.96, 0.05), 40)
	# an inlaid gold ring decorating the top surface (gold band = outer gold
	# ellipse minus an inner stone ellipse punched back out of it)
	_draw_ellipse(Vector2(0, 8), 262, 58, Color(GOLD.r, GOLD.g, GOLD.b, 0.55), 48)
	_draw_ellipse(Vector2(0, 8), 252, 55, Color(0.31, 0.27, 0.40, 1.0), 48)
	_draw_ellipse(Vector2(0, 8), 236, 51, Color(GOLD.r, GOLD.g, GOLD.b, 0.16), 48)
	_draw_ellipse(Vector2(0, 8), 228, 48, Color(0.30, 0.26, 0.39, 1.0), 48)
	# gold rivets studded around the stone rim, each seated in a small dark socket
	for k in 40:
		var ra := float(k) / 40.0 * TAU
		var rp := Vector2(cos(ra) * 312.0, 11.0 + sin(ra) * 64.0)
		_dais.draw_circle(rp + Vector2(0, 1.2), 3.2, Color(0.04, 0.03, 0.07, 0.6))
		_dais.draw_circle(rp, 2.6, Color(GOLD.r, GOLD.g, GOLD.b, 0.75))
		_dais.draw_circle(rp + Vector2(-0.8, -0.8), 0.9, Color(1.0, 0.97, 0.85, 0.8))

# The centrepiece trophy: a gold-rimmed heraldic shield bearing one of the board's
# buttons, flanked by outstretched golden wings and topped with a small crown — a
# "championship shield" that stands on the dais where the duelling knights used to be.
func _draw_champion_shield() -> void:
	var puls := 0.5 + 0.5 * sin(_t * 2.0)
	var flap := sin(_t * 2.4)                              # gentle wing beat
	var breathe := (1.0 + 0.035 * sin(_t * 1.1)) * SHIELD_SCALE  # slow idle "breathing" scale
	var sc := Vector2(0.0, SHIELD_Y)                        # shield centre, grounded on the 2x podium
	var top_y := -25.0 * breathe
	var bot_y := 21.0 * breathe
	var w := 21.0 * breathe

	# soft golden aura behind the whole emblem — breathes together with the shield
	_duel.draw_circle(sc + Vector2(0, -2), (34.0 + puls * 4.0) * breathe, Color(GOLD.r, GOLD.g, GOLD.b, 0.05 + puls * 0.05))

	# wings spread behind the shield (drawn first so the shield overlaps their roots)
	for s in [-1.0, 1.0]:
		_draw_wing(sc + Vector2(s * 13.0 * breathe, top_y + 8.0 * breathe), s, flap, breathe)

	# shield: cast shadow, dark body, inner bevel, then a bright gold rim
	var path := _shield_path(sc + Vector2(0, 1.5), w, top_y, bot_y)
	_duel.draw_colored_polygon(path, Color(0.02, 0.02, 0.05, 0.4))            # shadow
	_duel.draw_colored_polygon(_shield_path(sc, w, top_y, bot_y), Color(0.16, 0.10, 0.26, 1.0))
	_duel.draw_colored_polygon(_shield_path(sc, w - 2.4, top_y + 2.2, bot_y - 3.0),
		Color(0.24, 0.16, 0.38, 1.0))                                        # inner face
	var rim := _shield_path(sc, w, top_y, bot_y)
	rim.append(rim[0])
	_duel.draw_polyline(rim, GOLD, 2.0, true)                                # gold border

	# the button, seated on the shield face
	_draw_button_emblem(sc + Vector2(0, -3.0 * breathe), 12.0 * breathe, puls)

	# a small three-point crown resting on the shield's top edge
	_draw_crown(sc + Vector2(0, top_y - 1.0), 12.0 * breathe)

# A leaf-shaped feather from `base` to `tip`, widest at its middle.
func _feather(base: Vector2, tip: Vector2, wdt: float, col: Color) -> void:
	var d := tip - base
	var l := d.length()
	if l < 0.01:
		return
	var dir := d / l
	var nrm := Vector2(-dir.y, dir.x)
	var mid := base + dir * (l * 0.5)
	_duel.draw_colored_polygon(
		PackedVector2Array([base, mid + nrm * wdt, tip, mid - nrm * wdt]), col)

# One golden wing: a fan of feathers rooted at `base`, `s` = +1 right / -1 left.
func _draw_wing(base: Vector2, s: float, flap: float, breathe: float = 1.0) -> void:
	var n := 5
	for i in n:
		var f := float(i) / float(n - 1)                 # 0 = top feather, 1 = bottom
		# theta: angle above horizontal (top feathers point up, bottom ones fan out flat)
		var theta := deg_to_rad(lerpf(62.0, -8.0, f)) + flap * 0.18 * (1.0 - f)
		var length := lerpf(30.0, 17.0, f) * breathe
		var tip := base + Vector2(s * cos(theta) * length, -sin(theta) * length)
		var shade := GOLD.lerp(Color(0.72, 0.50, 0.12), f)   # tips a touch darker/older
		_feather(base, tip, 3.0 + (1.0 - f) * 1.4, shade)
		# a thin bright quill highlight along each feather
		_duel.draw_line(base, tip, Color(1.0, 0.94, 0.7, 0.5), 0.8)

# Heraldic shield outline: flat top with two shoulders tapering to a rounded point.
func _shield_path(c: Vector2, w: float, top_y: float, bot_y: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var sh := top_y + (bot_y - top_y) * 0.34              # shoulder height
	pts.append(c + Vector2(-w, top_y))
	pts.append(c + Vector2(w, top_y))
	# right lower edge: quadratic curve from the shoulder in to the bottom point
	var rp0 := Vector2(w, sh); var rctrl := Vector2(w, bot_y); var rp1 := Vector2(0, bot_y)
	for i in range(1, 9):
		var tt := i / 8.0
		pts.append(c + rp0.lerp(rctrl, tt).lerp(rctrl.lerp(rp1, tt), tt))
	# left lower edge: mirror, curving back up to the left shoulder
	var lp0 := Vector2(0, bot_y); var lctrl := Vector2(-w, bot_y); var lp1 := Vector2(-w, sh)
	for i in range(1, 9):
		var tt := i / 8.0
		pts.append(c + lp0.lerp(lctrl, tt).lerp(lctrl.lerp(lp1, tt), tt))
	return pts

# The championship button: gold bezel, the dark bore gap under its lip, then a domed
# cap that lights through the board's five colours in turn. Each change lands as a
# flash that decays over the first third of its hold — the cap reads as a button being
# PRESSED rather than a colour wheel spinning — and the last fifth cross-fades into the
# next colour so nothing ever snaps.
func _emblem_cap() -> Dictionary:
	var span := _t / EMBLEM_HOLD
	var i := int(span)
	var f := fposmod(span, 1.0)                       # 0→1 through this colour's hold
	var col: Color = EMBLEM_COLS[i % EMBLEM_COLS.size()]
	var nxt: Color = EMBLEM_COLS[(i + 1) % EMBLEM_COLS.size()]
	return {
		"col": col.lerp(nxt, clampf((f - 0.8) / 0.2, 0.0, 1.0)),
		"lit": clampf(1.0 - f * 3.0, 0.0, 1.0),       # press flash, gone by a third in
	}

func _draw_button_emblem(c: Vector2, r: float, puls: float) -> void:
	var cap: Dictionary = _emblem_cap()
	var col: Color = cap["col"]
	var lit: float = cap["lit"]
	# gold aura on the shield face, plus the colour the lit cap throws past the bezel
	_duel.draw_circle(c, r + 3.0 + puls * 1.5, Color(GOLD.r, GOLD.g, GOLD.b, 0.09 + puls * 0.07))
	_duel.draw_circle(c, r + 1.5 + lit * 2.5, Color(col.r, col.g, col.b, 0.08 + lit * 0.18))
	# The button itself, in the order the model stacks it: a gold outer edge, the dark
	# bezel wall, the bright light channel, then the flat cap. Plain stacked circles —
	# the bands stay crisp at the size the crest actually draws at.
	_duel.draw_circle(c, r, GOLD.darkened(0.15))
	_duel.draw_circle(c, r * 0.93, Color(0.10, 0.10, 0.13))
	_duel.draw_circle(c, r * 0.80, col.lerp(Color(1, 1, 1), 0.72 + lit * 0.20))
	var cr := r * 0.72
	_duel.draw_circle(c, cr, col.darkened(0.12).lerp(col.lightened(0.24), lit))
	# a wide, shallow lift toward the top of the cap where the key light lands. It has
	# to stay wide: a small bright circle inside a darker one turns the flat cap into a
	# ball, which is exactly what the modelled button is not.
	_duel.draw_circle(c + Vector2(0.0, -cr * 0.10), cr * 0.86, col.lightened(0.04 + lit * 0.26))
	_duel.draw_circle(c + Vector2(-cr * 0.34, -cr * 0.36), cr * 0.22,
		Color(1, 1, 1, 0.12 + lit * 0.12))

# A small three-point crown sitting on the shield's crest, `w` = its half-width.
func _draw_crown(c: Vector2, w: float) -> void:
	var base_y := 0.0
	var peak := -8.0
	var body := PackedVector2Array([
		c + Vector2(-w, base_y), c + Vector2(w, base_y),
		c + Vector2(w * 0.62, peak), c + Vector2(w * 0.30, base_y - 2.0),
		c + Vector2(0.0, peak - 1.0), c + Vector2(-w * 0.30, base_y - 2.0),
		c + Vector2(-w * 0.62, peak)])
	_duel.draw_colored_polygon(body, GOLD)
	_duel.draw_line(c + Vector2(-w, base_y - 1.0), c + Vector2(w, base_y - 1.0),
		GOLD.lightened(0.25), 1.6)                               # jewelled band
	# a gem ball capping each crown point
	for px in [-w * 0.62, 0.0, w * 0.62]:
		_duel.draw_circle(c + Vector2(px, peak - 1.0), 1.6, Color(0.95, 0.30, 0.34))

# Draw a filled ellipse via a polygon fan (Godot has no primitive ellipse fill).
# Only the static dais uses this, so it paints onto `_dais`.
func _draw_ellipse(c: Vector2, rx: float, ry: float, col: Color, steps: int) -> void:
	var pts := PackedVector2Array()
	for i in steps:
		var a := float(i) / float(steps) * TAU
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	_dais.draw_colored_polygon(pts, col)

# ---------------- process (animation + events) ----------------

func _process(dt: float) -> void:
	_t += dt

	# cheer envelope (crowd rim-light + torch flare, decays ~1s)
	if _cheer > 0.0:
		_cheer = maxf(0.0, _cheer - dt / 1.0)

	# every so often the crowd cheers and the wall torches flare, then settle back
	_big_timer -= dt
	if _big_timer <= 0.0:
		_big_timer = randf_range(10.0, 15.0)
		_cheer = 1.0

	# The crowd / shield / spotlights / banners all repaint on one throttled ~30fps
	# gate. This is ambient art sitting behind the UI, so half-rate is invisible but
	# roughly halves the per-frame CPU + draw-call load on phones. The stone dais is
	# static and painted once (see _build_platform), so it's not repainted here.
	_redraw_acc += dt
	if _redraw_acc >= REDRAW_DT:
		_redraw_acc = 0.0
		_update_banners()
		_update_crowd()
		if _duel:
			_duel.queue_redraw()
		if _spot:
			_spot.queue_redraw()

	# torch flicker (+ flare during a cheer)
	for i in _torch_lamps.size():
		var flick := 0.58 + 0.16 * sin(_t * 7.0 + _torch_phase[i]) + 0.08 * sin(_t * 13.0 + _torch_phase[i] * 2.0)
		var lamp := _torch_lamps[i]
		lamp.modulate.a = flick + _cheer * 0.5
		lamp.scale = Vector2.ONE * (58.0 / 128.0) * (1.0 + _cheer * 0.25 + 0.03 * sin(_t * 9.0 + _torch_phase[i]))
