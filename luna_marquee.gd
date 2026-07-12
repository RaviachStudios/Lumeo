extends Control

# Loaded via `const LunaMarquee = preload(...)` in simon_wheel.gd (same pattern as
# electric_pulse.gd / roulette_ball.gd) — no `class_name`, to avoid colliding with
# that const's name.
#
# The Luna Park skin's signature: a ring of warm incandescent carnival marquee bulbs
# hung just outside the wheel's outer rim. The bulb screen positions are computed in
# SimonWheel (projected through the same tilted camera that renders the 3D wheel), so
# the ring is a perfectly-fitted ellipse around the machine. This node just paints and
# animates them as a pure 2D canvas overlay on top of the wheel — it never touches the
# 3D wheel and never blocks input.
#
# Idle: every bulb softly glows and breathes with a gently staggered phase, so the
# ring always feels alive but stays calm and luxurious (never a harsh blink).
#
# SimonWheel.luna_light_chase() (every 3rd round) runs light_chase(): a single bright
# crest sweeps ~2 clockwise laps around the ring over ~2s while every bulb lifts a
# little, with a few gold sparkles peeling off the crest. Gameplay is never interrupted.
#
# SimonWheel.luna_celebrate() (every 5th round) runs celebrate(): every bulb powers to
# full while an energetic fast crest races several laps for ~4s, throwing off sparkles,
# then everything eases smoothly back to the idle glow.

const R := 5.2                       # bulb core radius in px

const CHASE_DUR := 2.0               # Light Chase length (matches the every-3 event)
const CHASE_LAPS := 2.0              # clockwise laps the crest travels during a chase
const CELE_DUR := 4.0                # Carnival Celebration length (every-5 event)
const CELE_LAPS := 5.0               # faster, more energetic crest during the celebration

# Warm handcrafted incandescent tones — never over-saturated.
const WARM := Color(1.0, 0.80, 0.42)
const CORE := Color(1.0, 0.93, 0.68)
const HOT := Color(1.0, 0.99, 0.90)
const GOLD := Color(1.0, 0.86, 0.42)

var _bulbs: PackedVector2Array = PackedVector2Array()   # bulb centres, this Control's px space

var _time := 0.0                     # free-running clock for the idle breathing
var _mode := "idle"                  # "idle" | "chase" | "celebrate"
var _evt := 0.0                      # elapsed time inside the active chase/celebration
var _sparkles: Array = []            # [{pos, vel, t, life, size, seed}]
var _spawn_acc := 0.0

# Frozen = show a single settled still and never advance the clock/redraw. Set by
# SimonWheel for the SHOP preview wheels (SIMON tab + SPECIAL SKINS cards): a preview
# wheel's marquee must not keep breathing every frame — that's a per-frame CPU/redraw
# cost on a screen full of previews AND read as a bug (the ring "kept going" in the
# SIMON tab). The live gameplay wheel is never frozen, so its ring still breathes.
var _frozen := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The marquee must draw ABOVE the wheel's SubViewportContainer, but it must NOT
	# escape an ancestor's clip_contents — the shop's SPECIAL SKINS / SIMON preview
	# cards clip their wheel, and a CanvasItem with a non-zero z_index is lifted out of
	# that clip in Godot, so its bulbs float over the whole shop instead of staying
	# inside the card. SimonWheel adds this overlay AFTER the SubViewportContainer (see
	# _build_center_overlay), so plain tree order already paints it on top of the wheel
	# render — no z_index needed. Keeping z_index at 0 is what lets the card clip contain
	# the ring so it can never remain floating on screen after the preview is gone.
	z_index = 0
	visibility_changed.connect(_on_visibility)
	set_process(false)               # only runs while the ring is actually shown

# Hand the overlay its bulb positions (already projected to this Control's local pixel
# space by SimonWheel). Called on every layout so a resize keeps the ring fitted. An
# empty array (off the Luna Park skin) parks the node idle and invisible.
func set_bulbs(pts: PackedVector2Array) -> void:
	_bulbs = pts
	if visible and _bulbs.size() > 0 and not _frozen:
		set_process(true)
	else:
		set_process(false)
	queue_redraw()

func _on_visibility() -> void:
	set_process(visible and _bulbs.size() > 0 and not _frozen)

# Freeze the ring to a single settled still (previews) or let it breathe again (live
# gameplay). Frozen holds whatever phase `_time` is at, so the bulbs read as lit but
# never animate or redraw — ~zero ongoing cost. See `_frozen`.
func set_frozen(on: bool) -> void:
	if _frozen == on:
		return
	_frozen = on
	if on:
		set_process(false)
	else:
		set_process(visible and _bulbs.size() > 0)
	queue_redraw()

# Light Chase — a single bright crest sweeps ~2 clockwise laps while every bulb lifts.
# No-op if there are no bulbs. Force-starts over an in-flight chase; yields to a
# running celebration (the bigger event owns the ring until it finishes).
func light_chase() -> void:
	if _bulbs.size() == 0 or _mode == "celebrate":
		return
	_mode = "chase"
	_evt = 0.0
	_spawn_acc = 0.0
	set_process(true)
	queue_redraw()

# Carnival Celebration — every bulb powers to full while an energetic crest races
# several laps for ~4s, then eases back to the idle glow. Force-starts over any chase.
func celebrate() -> void:
	if _bulbs.size() == 0:
		return
	_mode = "celebrate"
	_evt = 0.0
	_spawn_acc = 0.0
	set_process(true)
	queue_redraw()

func _process(dt: float) -> void:
	_time += dt
	if _mode != "idle":
		_evt += dt
		var dur := CELE_DUR if _mode == "celebrate" else CHASE_DUR
		# Sparkles peel off the travelling crest; density swells mid-event, thins at the ends.
		var env := _event_env()
		_spawn_acc += dt * (18.0 * env + 2.0) * (1.6 if _mode == "celebrate" else 1.0)
		while _spawn_acc >= 1.0:
			_spawn_acc -= 1.0
			_spawn_sparkle()
		if _evt >= dur:
			_mode = "idle"
			_evt = 0.0
	# Age + drift the sparkles, prune the dead ones.
	if _sparkles.size() > 0:
		for s in _sparkles:
			s["t"] += dt
			s["pos"] += s["vel"] * dt
			s["vel"] *= maxf(0.0, 1.0 - dt * 2.6)
		var alive: Array = []
		for s in _sparkles:
			if s["t"] < s["life"]:
				alive.append(s)
		_sparkles = alive
	# Idle with no bulbs shown and no sparkles left → nothing to animate, stop redrawing.
	if _mode == "idle" and _sparkles.size() == 0 and not visible:
		set_process(false)
	queue_redraw()

# Event envelope (0..1): fades in over the first 15% and out over the last 20% of the
# active chase/celebration, so both the crest and the sparkles arrive and leave gently.
func _event_env() -> float:
	if _mode == "idle":
		return 0.0
	var dur := CELE_DUR if _mode == "celebrate" else CHASE_DUR
	var p := clampf(_evt / dur, 0.0, 1.0)
	return smoothstep(0.0, 0.15, p) * smoothstep(1.0, 0.80, p)

# Brightness of bulb `i` (0..~1.4) right now: a gentle staggered idle breath, plus the
# travelling chase crest and — during a celebration — a full-ring power-on lift.
func _bulb_bright(i: int, n: int) -> float:
	var fi := float(i) / float(n)
	var breath := 0.52 + 0.22 * sin(_time * 1.5 + float(i) * 0.8)
	if _mode == "idle":
		return breath
	var env := _event_env()
	var dur := CELE_DUR if _mode == "celebrate" else CHASE_DUR
	var laps := CELE_LAPS if _mode == "celebrate" else CHASE_LAPS
	var head := (_evt / dur) * laps          # crest travels clockwise (increasing index)
	var dd := fposmod(fi - head, 1.0)
	var ring_dist := minf(dd, 1.0 - dd)      # wrap distance to the crest, 0..0.5
	var crest := smoothstep(0.12, 0.0, ring_dist)
	if _mode == "celebrate":
		var full := 0.75 + 0.25 * sin(_time * 6.0 + float(i))   # whole ring lit + shimmer
		return breath + env * (full + crest * 0.7)
	return breath + env * crest * 0.9

func _spawn_sparkle() -> void:
	if _bulbs.size() == 0:
		return
	# Spawn near a bulb that's currently on the crest so sparkles trail the running light.
	var n := _bulbs.size()
	var dur := CELE_DUR if _mode == "celebrate" else CHASE_DUR
	var laps := CELE_LAPS if _mode == "celebrate" else CHASE_LAPS
	var head := (_evt / dur) * laps
	var i := int(round(fposmod(head, 1.0) * float(n))) % n
	var p: Vector2 = _bulbs[i] + Vector2(randf_range(-4.0, 4.0), randf_range(-4.0, 4.0))
	var v := Vector2(randf_range(-16.0, 16.0), randf_range(-22.0, -4.0))
	_sparkles.append({
		"pos": p, "vel": v, "t": 0.0,
		"life": randf_range(0.28, 0.5), "size": randf_range(1.6, 3.2),
		"seed": randf() * TAU,
	})

func _draw() -> void:
	var n := _bulbs.size()
	if n == 0:
		return
	for i in n:
		_draw_bulb(_bulbs[i], _bulb_bright(i, n))
	_draw_sparkles()

# One warm marquee bulb: a soft outer halo (wider + brighter the hotter it burns), a
# warm glowing body and a hot core, all seated on a dim brass socket so an unlit bulb
# still reads as a physical fixture rather than vanishing.
func _draw_bulb(c: Vector2, bright: float) -> void:
	bright = clampf(bright, 0.0, 1.4)
	# brass socket / bulb base — always faintly visible
	draw_circle(c, R * 1.15, Color(0.28, 0.18, 0.08, 0.55))
	# outer halo
	draw_circle(c, R * (2.4 + 1.4 * bright), Color(WARM.r, WARM.g, WARM.b, 0.10 * bright))
	draw_circle(c, R * (1.5 + 0.6 * bright), Color(WARM.r, WARM.g, WARM.b, 0.18 * bright))
	# glowing body
	draw_circle(c, R * 0.72, Color(CORE.r, CORE.g, CORE.b, 0.45 + 0.45 * bright))
	# hot filament core
	draw_circle(c, R * 0.36, Color(HOT.r, HOT.g, HOT.b, 0.35 + 0.65 * clampf(bright, 0.0, 1.0)))

func _draw_sparkles() -> void:
	for s in _sparkles:
		var life: float = s["life"]
		var a := 1.0 - clampf(s["t"] / life, 0.0, 1.0)
		if a <= 0.01:
			continue
		var tw := 0.6 + 0.4 * sin(s["t"] * 38.0 + float(s["seed"]))
		var sz: float = float(s["size"]) * (0.7 + 0.5 * tw)
		var p: Vector2 = s["pos"]
		var gold := Color(GOLD.r, GOLD.g, GOLD.b, a * 0.9)
		draw_line(p - Vector2(sz, 0.0), p + Vector2(sz, 0.0), gold, 1.0, true)
		draw_line(p - Vector2(0.0, sz), p + Vector2(0.0, sz), gold, 1.0, true)
		draw_circle(p, sz * 0.32, Color(1.0, 1.0, 0.92, a))
