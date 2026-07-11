extends Control

# Loaded via `const RouletteBall = preload(...)` in simon_wheel.gd (same pattern as
# electric_pulse.gd / volcano_cone.gd) — no `class_name`, to avoid colliding with
# that const's name.
#
# The Jackpot (casino) skin's status indicator: instead of the stock blue glowing
# dot beneath the level numeral, this draws a small polished ivory roulette ball —
# soft radial shading, a glossy top-left specular, a warm reflected rim off the gold
# ring and a soft contact shadow — as a pure 2D canvas effect painted on top of the
# wheel. It sits at a fixed rest position (bottom of the inner gold roulette ring,
# where the blue dot used to be) and is otherwise perfectly still.
#
# Every 3rd completed round SimonWheel.roulette_spin() calls spin(): the ball glows
# softly (~0.2s), then eases smoothly one full CLOCKWISE lap around the inner gold
# ring — accelerating then slowing (cubic ease-in-out) — trailing a faint golden
# streak and a few gold sparkles, with a slight bloom for the duration only, and
# lands back EXACTLY on its rest spot. A soft rolling sound (ending in a click as it
# drops home) is played in sync. Total ~1.4s. It never blocks input or touches the
# 3D wheel — the lap is cosmetic and self-contained.

const R := 7.0                 # ball radius in px (~ the old 12px dot)

const GLOW_DUR := 0.20         # soft pre-glow before the ball moves
const LAP_DUR := 1.00          # one full lap around the ring (eased)
const SETTLE_DUR := 0.22       # landing pulse + trail/sparkle fade after the lap
const TOTAL := GLOW_DUR + LAP_DUR + SETTLE_DUR

const TRAIL_LIFE := 0.16       # seconds a trail sample lingers behind the ball

# ---- Mega Jackpot celebration (every 8th level): a continuous multi-lap roll, ~3s ----
# The ball spins up smoothly from rest, cruises at a constant elegant speed for the
# bulk of the celebration, then eases to a stop landing EXACTLY back on its rest
# spot. Total time and the cruise speed are chosen so the trapezoidal velocity
# profile integrates to a whole number of turns (see _cele_ang) — no teleport, no
# jitter, and it comes home dead-centre beneath the numeral.
const CELE_DUR := 3.0          # matches BackgroundManager.casino_jackpot()'s 3s tween
const CELE_SPINUP := 0.40      # ease from rest up to cruise speed
const CELE_SETTLE := 0.60      # ease from cruise speed back down to rest (smooth stop)
const CELE_LAPS := 2.0         # whole turns over the whole celebration (elegant ~1.25s/lap)
# Cruise angular speed: the spin-up and settle ramps are smoothstep, each of which
# integrates to exactly half its rectangle, so the total swept angle is
# OMEGA * (DUR - SPINUP/2 - SETTLE/2). Solving that == CELE_LAPS full turns:
const CELE_OMEGA := CELE_LAPS * TAU / (CELE_DUR - 0.5 * CELE_SPINUP - 0.5 * CELE_SETTLE)

# Ivory finish. Dark = the shaded/terminator side, mid = the lit body, bright = the
# highlit cap; the specular is white and the reflected rim is warm gold (the ring).
const IVORY_DARK := Color(0.56, 0.53, 0.46)
const IVORY_MID := Color(0.91, 0.88, 0.80)
const IVORY_BRIGHT := Color(1.0, 0.99, 0.95)
const GOLD := Color(1.0, 0.82, 0.34)

# Light direction (screen space, y-down): up and slightly left, so the gloss sits on
# the upper-left and the shadow falls lower-right — a fixed studio key light the ball
# rolls under, which reads as a moving glossy reflection during the lap.
const LIGHT := Vector2(-0.42, -0.52)

var _orbit := Vector2.ZERO     # centre of the lap (the inner gold ring's centre)
var _rest := Vector2.ZERO      # resting position of the ball (bottom of the ring)
var _radius := 40.0            # lap radius (rest is _orbit + (0, _radius))

var _spinning := false
var _mode := "lap"             # "lap" = single every-3 lap; "celebrate" = Stage-5 roll
var _t := 0.0
var _rolled := false           # rolling sound fired at lap start
var _landed := false           # landing pulse fired at lap end
var _land := 0.0               # landing pulse intensity (1 -> 0 over SETTLE_DUR)
var _prev_pos := Vector2.ZERO
var _spawn_acc := 0.0
var _trail: Array = []         # [{pos, age}] recent ball positions
var _sparkles: Array = []      # [{pos, vel, t, life, size, seed}]

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 90                 # above the wheel render + numeral
	set_process(false)           # idle until a spin is requested

# Pin the ball's geometry in this Control's local pixel space. `center` is the inner
# gold ring's centre (the numeral/hub centre), `radius` the lap radius, `rest` the
# resting spot (bottom of the ring). Called on every layout so a resize keeps it put.
func set_geometry(center: Vector2, radius: float, rest: Vector2) -> void:
	_orbit = center
	_radius = radius
	_rest = rest
	if not _spinning:
		queue_redraw()

# Kick off one lap. No-op if already spinning so laps never stack.
func spin() -> void:
	if _spinning:
		return
	_mode = "lap"
	_spinning = true
	_t = 0.0
	_rolled = false
	_landed = false
	_land = 0.0
	_spawn_acc = 0.0
	_trail.clear()
	_sparkles.clear()
	_prev_pos = _rest
	set_process(true)
	queue_redraw()

# Stage-5 Mega Jackpot celebration: the ball rolls continuously around the ring for
# ~5s (multiple laps at a constant elegant speed), then smoothly slows and settles
# back onto its exact rest spot. Force-starts over any in-flight lap so the two
# never fight. Cosmetic and self-contained — it never blocks input or the 3D wheel.
func celebrate() -> void:
	_mode = "celebrate"
	_spinning = true
	_t = 0.0
	_rolled = true         # the roll sound is started here, not gated on GLOW_DUR
	_landed = true         # no discrete landing pulse — the ease-to-rest reads as settling
	_land = 0.0
	_spawn_acc = 0.0
	_trail.clear()
	_sparkles.clear()
	_prev_pos = _rest
	AudioManager.play_roulette_roll(CELE_DUR)
	set_process(true)
	queue_redraw()

func _process(dt: float) -> void:
	_t += dt
	var total := CELE_DUR if _mode == "celebrate" else TOTAL

	var pos := _ball_pos()
	var tangent := pos - _prev_pos
	if tangent.length() > 0.001:
		tangent = tangent.normalized()
	_prev_pos = pos

	# `moving` gates the trail + sparkles; `speed01` (0..1) scales sparkle density with
	# how fast the ball is travelling, so effects swell mid-motion and thin at the ends.
	var moving := false
	var speed01 := 0.0
	if _mode == "celebrate":
		moving = _t < CELE_DUR
		speed01 = _cele_env(_t)
	else:
		# Play the soft rolling sound the instant the ball starts moving; the WAV lasts
		# one lap and ends with a click, so the click lands as the ball drops back home.
		if not _rolled and _t >= GLOW_DUR:
			_rolled = true
			AudioManager.play_roulette_roll(LAP_DUR)
		# Landing pulse the instant the lap completes.
		if not _landed and _t >= GLOW_DUR + LAP_DUR:
			_landed = true
			_land = 1.0
		moving = _t > GLOW_DUR and _t < GLOW_DUR + LAP_DUR
		if moving:
			speed01 = sin(PI * (_t - GLOW_DUR) / LAP_DUR)

	if _land > 0.0:
		_land = maxf(0.0, _land - dt / SETTLE_DUR)

	# Golden motion trail: sample the ball's path while it moves, age & prune the rest.
	if moving:
		_trail.append({"pos": pos, "age": 0.0})
	for s in _trail:
		s["age"] += dt
	while _trail.size() > 0 and _trail[0]["age"] > TRAIL_LIFE:
		_trail.remove_at(0)

	# Gold sparkles behind the ball — denser the faster it's rolling, none at rest.
	if moving:
		_spawn_acc += dt * (26.0 * speed01 + 4.0)
		while _spawn_acc >= 1.0:
			_spawn_acc -= 1.0
			_spawn_sparkle(pos, tangent)
	for s in _sparkles:
		s["t"] += dt
		s["pos"] += s["vel"] * dt
		s["vel"] *= maxf(0.0, 1.0 - dt * 3.0)
	var alive: Array = []
	for s in _sparkles:
		if s["t"] < s["life"]:
			alive.append(s)
	_sparkles = alive

	if _t >= total:
		_spinning = false
		_land = 0.0
		_trail.clear()
		_sparkles.clear()
		set_process(false)
		queue_redraw()
		return
	queue_redraw()

# Celebration velocity envelope (0..1): smoothly ramps rest->cruise over the spin-up,
# holds at 1 through the cruise, then ramps cruise->rest over the settle. Drives both
# sparkle density and the bloom, so effects fade in and out with the motion itself.
func _cele_env(t: float) -> float:
	if t < CELE_SPINUP:
		return smoothstep(0.0, CELE_SPINUP, t)
	if t > CELE_DUR - CELE_SETTLE:
		return smoothstep(CELE_DUR, CELE_DUR - CELE_SETTLE, t)
	return 1.0

# Accumulated celebration angle (radians) at time t, in closed form so the ball lands
# on an EXACT whole number of turns (== rest) with zero velocity. Velocity follows a
# trapezoid: smoothstep ramp up (spin-up), flat CELE_OMEGA (cruise), smoothstep ramp
# down (settle). Each smoothstep integrates to half its rectangle, giving an exact
# total of CELE_LAPS turns; velocities match at both junctions, so there's no jerk.
func _cele_ang(t: float) -> float:
	t = clampf(t, 0.0, CELE_DUR)
	var cruise_end := CELE_DUR - CELE_SETTLE
	if t <= CELE_SPINUP:
		var x := t / CELE_SPINUP
		return CELE_OMEGA * CELE_SPINUP * (x * x * x - 0.5 * x * x * x * x)
	var ang_su := 0.5 * CELE_OMEGA * CELE_SPINUP
	if t <= cruise_end:
		return ang_su + CELE_OMEGA * (t - CELE_SPINUP)
	var ang_cr := ang_su + CELE_OMEGA * (cruise_end - CELE_SPINUP)
	var w := 1.0 - (t - cruise_end) / CELE_SETTLE       # 1 -> 0 across the settle
	return ang_cr + CELE_OMEGA * CELE_SETTLE * (0.5 - w * w * w + 0.5 * w * w * w * w)

func _spawn_sparkle(pos: Vector2, tangent: Vector2) -> void:
	# Drift slightly backward (opposite the ball's motion) plus a little scatter, so
	# they appear to peel off behind the ball and linger near the path.
	var v := -tangent * randf_range(8.0, 22.0) + Vector2(randf_range(-10.0, 10.0), randf_range(-10.0, 10.0))
	_sparkles.append({
		"pos": pos, "vel": v, "t": 0.0,
		"life": randf_range(0.25, 0.42), "size": randf_range(1.6, 3.2),
		"seed": randf() * TAU,
	})

# Cubic ease-in-out over the lap: the ball smoothly speeds up then slows down, so the
# motion feels elegant rather than a constant-speed sweep. Zero speed at both ends
# means it eases away from — and settles back onto — its rest spot without a jerk.
func _ease_io(p: float) -> float:
	if p < 0.5:
		return 4.0 * p * p * p
	var q := -2.0 * p + 2.0
	return 1.0 - q * q * q * 0.5

# The ball's current centre. At rest (and during the pre-glow / after landing) it's
# exactly _rest; during the lap it rides the circle CLOCKWISE from the bottom:
# bottom -> left -> top -> right -> bottom. offset(e=0)=offset(e=1)=(0,+radius)=rest,
# so it returns to the EXACT starting position.
func _ball_pos() -> Vector2:
	# Stage-5 celebration: ride the continuous angle. At t=0 and t=CELE_DUR the angle
	# is a whole multiple of TAU, so offset(-sin, cos) = (0, +radius) = exactly _rest.
	if _mode == "celebrate":
		if _t >= CELE_DUR:
			return _rest
		var ca := _cele_ang(_t)
		return _orbit + Vector2(-sin(ca), cos(ca)) * _radius
	if _t <= GLOW_DUR:
		return _rest
	var lp := (_t - GLOW_DUR) / LAP_DUR
	if lp >= 1.0:
		return _rest
	var e := _ease_io(clampf(lp, 0.0, 1.0))
	var ang := TAU * e
	return _orbit + Vector2(-sin(ang), cos(ang)) * _radius

# Glow/bloom strength: ramps up over the pre-glow, holds through the lap, fades over
# the settle. Drives the soft halo behind the ball — present during the animation only.
func _glow_amount() -> float:
	# Celebration: bloom swells in over the spin-up, holds through the cruise, and
	# fades out over the settle (matching the motion envelope) so it's cleanly removed.
	if _mode == "celebrate":
		return _cele_env(_t)
	if _t < GLOW_DUR:
		return smoothstep(0.0, 1.0, _t / GLOW_DUR)
	if _t < GLOW_DUR + LAP_DUR:
		return 1.0
	return clampf(1.0 - (_t - GLOW_DUR - LAP_DUR) / SETTLE_DUR, 0.0, 1.0)

func _draw() -> void:
	var pos := _rest
	var glow := 0.0
	if _spinning:
		pos = _ball_pos()
		glow = _glow_amount()
		_draw_trail()
		_draw_sparkles()
	_draw_ball(pos, glow)
	if _land > 0.001:
		_draw_landing(pos)

# Soft radial glow built from a few stacked circles (same trick as the electric core):
# larger + fainter to smaller + denser, so it reads as a smooth halo.
func _glow(c: Vector2, r: float, col: Color) -> void:
	draw_circle(c, r, Color(col.r, col.g, col.b, col.a * 0.35))
	draw_circle(c, r * 0.66, Color(col.r, col.g, col.b, col.a * 0.55))
	draw_circle(c, r * 0.36, Color(col.r, col.g, col.b, col.a * 0.9))

# The polished ivory ball: contact shadow, optional bloom, a shaded sphere (offset
# lit discs), a warm reflected rim off the gold ring and a crisp glossy specular.
func _draw_ball(c: Vector2, glow: float) -> void:
	# Soft contact shadow, flattened into an ellipse just below the ball.
	draw_set_transform(c + Vector2(0.0, R * 0.9), 0.0, Vector2(1.15, 0.5))
	_glow(Vector2.ZERO, R * 1.5, Color(0.0, 0.0, 0.02, 0.32))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Slight bloom — during the animation only, tasteful and warm.
	if glow > 0.01:
		_glow(c, R * 3.4, Color(GOLD.r, GOLD.g, GOLD.b, 0.16 * glow))
		_glow(c, R * 2.0, Color(1.0, 0.90, 0.5, 0.14 * glow))

	# Shaded sphere: full dark base leaves a crescent terminator; lit discs offset
	# toward the light build a smooth gradient up to the highlit cap.
	draw_circle(c, R, IVORY_DARK)
	draw_circle(c + LIGHT * (R * 0.28), R * 0.86, IVORY_MID)
	draw_circle(c + LIGHT * (R * 0.50), R * 0.55, IVORY_BRIGHT)
	# Warm bounce on the shadow side — light kicked back up off the gold ring/felt.
	draw_circle(c - LIGHT * (R * 0.58), R * 0.30, Color(0.82, 0.62, 0.32, 0.22))

	# Glossy specular: a soft bloom of white with a tight hot dot on top.
	var spec := c + LIGHT * (R * 0.5)
	draw_circle(spec, R * 0.32, Color(1.0, 1.0, 1.0, 0.5))
	draw_circle(spec, R * 0.15, Color(1.0, 1.0, 1.0, 0.95))
	# Crisp reflected rim along the lower-right edge (the gold ring catching the ball).
	var rim_a := 0.45 + 0.35 * glow
	draw_arc(c, R * 0.92, deg_to_rad(18.0), deg_to_rad(112.0), 16, Color(1.0, 0.9, 0.62, rim_a), 1.2, true)

func _draw_trail() -> void:
	for s in _trail:
		var af: float = clampf(s["age"] / TRAIL_LIFE, 0.0, 1.0)
		var a := 1.0 - af
		var rr := R * (0.28 + 0.55 * a)
		var p: Vector2 = s["pos"]
		draw_circle(p, rr, Color(GOLD.r, GOLD.g, GOLD.b, 0.26 * a))
		draw_circle(p, rr * 0.5, Color(1.0, 0.92, 0.6, 0.30 * a))

func _draw_sparkles() -> void:
	for s in _sparkles:
		var life: float = s["life"]
		var a := 1.0 - clampf(s["t"] / life, 0.0, 1.0)
		if a <= 0.01:
			continue
		var tw := 0.6 + 0.4 * sin(s["t"] * 40.0 + float(s["seed"]))
		var sz: float = float(s["size"]) * (0.7 + 0.5 * tw)
		var p: Vector2 = s["pos"]
		var gold := Color(GOLD.r, GOLD.g, GOLD.b, a * 0.9)
		draw_line(p - Vector2(sz, 0.0), p + Vector2(sz, 0.0), gold, 1.0, true)
		draw_line(p - Vector2(0.0, sz), p + Vector2(0.0, sz), gold, 1.0, true)
		draw_circle(p, sz * 0.35, Color(1.0, 1.0, 0.92, a))

# A brief expanding gold ring + a warm bloom as the ball drops back into its pocket.
func _draw_landing(c: Vector2) -> void:
	var e := 1.0 - _land
	_glow(c, R * (1.6 + e * 1.4), Color(GOLD.r, GOLD.g, GOLD.b, 0.12 * _land))
	draw_arc(c, R * (1.0 + e * 1.8), 0.0, TAU, 24, Color(1.0, 0.85, 0.42, 0.5 * _land), 1.4, true)
