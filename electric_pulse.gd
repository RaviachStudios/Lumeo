extends Control

# Loaded via `const ElectricPulse = preload(...)` in simon_wheel.gd (same pattern as
# volcano_cone.gd) — no `class_name`, to avoid colliding with that const's name.
#
# Premium "electric charge" overlay, drawn ON TOP of the wheel every 3rd
# completed round. SimonWheel.electric_pulse() spawns one of these, hands it the
# screen-space hub centre plus one endpoint per white divider (already projected
# through the wheel's tilted camera, so every bolt starts EXACTLY at the centre and
# ends EXACTLY on the outer rim), then it animates itself for ~0.8s and frees itself.
# It never touches the 3D wheel geometry — it's a pure 2D canvas effect.
#
# Timeline over DURATION (~0.8s), phase u = elapsed / DURATION:
#   u < CHARGE_FRAC : a small energy sphere glows and rapidly charges in the centre.
#   u = CHARGE_FRAC : DISCHARGE — the four bolts snap out; on_discharge fires (panel
#                     glow pulse + camera shake + zap sound, all owned by the wheel).
#   u > CHARGE_FRAC : bolts stay alive (flicker, wander, fork) while edge sparks burst
#                     and expand; everything eases smoothly back to nothing by u = 1.

const DURATION := 0.8
const CHARGE_FRAC := 0.34      # fraction of DURATION spent charging before discharge
const SPARK_DUR := 0.34        # seconds an edge spark-burst lives after discharge
const CORE_R := 26.0           # fully-charged energy-sphere core radius (px)

const COL_BLUE := Color(0.25, 0.55, 1.0)
const COL_CYAN := Color(0.45, 0.95, 1.0)
const COL_PURPLE := Color(0.62, 0.42, 1.0)

var _t := 0.0
var _discharged := false
var _center := Vector2.ZERO
var _ends: Array[Vector2] = []
var _seeds: Array[float] = []
var _on_discharge: Callable

func setup(center: Vector2, ends: Array, on_discharge: Callable) -> void:
	_center = center
	_ends.clear()
	_seeds.clear()
	for e in ends:
		_ends.append(e)
		_seeds.append(randf() * 100.0)
	_on_discharge = on_discharge

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_level = false
	z_index = 100                       # sit above the wheel render + numeral

func _process(dt: float) -> void:
	_t += dt
	if not _discharged and _t >= DURATION * CHARGE_FRAC:
		_discharged = true
		if _on_discharge.is_valid():
			_on_discharge.call()
	if _t >= DURATION:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	if _ends.is_empty():
		return
	var u := clampf(_t / DURATION, 0.0, 1.0)
	var tail := 1.0 - smoothstep(0.86, 1.0, u)          # gentle global fade-out at the end
	var charge := clampf(u / CHARGE_FRAC, 0.0, 1.0)

	# Energy sphere: brightens as it charges, then flares and fades after discharge.
	var core_i: float
	if u < CHARGE_FRAC:
		core_i = charge
	else:
		core_i = 1.0 - clampf((u - CHARGE_FRAC) / 0.30, 0.0, 1.0)
	_draw_core(charge, core_i * tail)

	if u < CHARGE_FRAC:
		return

	# Discharge: four living bolts down the dividers + expanding edge sparks.
	var bl := (u - CHARGE_FRAC) / (1.0 - CHARGE_FRAC)    # 0..1 over the bolts' life
	var bolt_i := pow(1.0 - bl, 0.5) * tail
	for k in _ends.size():
		_draw_bolt(_center, _ends[k], _seeds[k], bolt_i)
	var sl := clampf((u - CHARGE_FRAC) / (SPARK_DUR / DURATION), 0.0, 1.0)
	if sl < 1.0:
		for k in _ends.size():
			_draw_sparks(_ends[k], sl, _seeds[k])

# The central energy sphere: soft electric halo, a spray of charging arcs flicking
# off it, and a bright white-hot core on top.
func _draw_core(charge: float, intensity: float) -> void:
	if intensity <= 0.01:
		return
	var r := lerpf(3.0, CORE_R, ease(charge, 0.4))
	draw_circle(_center, r * 2.2, Color(COL_BLUE.r, COL_BLUE.g, COL_BLUE.b, 0.10 * intensity))
	draw_circle(_center, r * 1.5, Color(COL_CYAN.r, COL_CYAN.g, COL_CYAN.b, 0.16 * intensity))
	# charging arcs flicking outward off the sphere (regenerated each frame = crackle)
	var ticks := 7
	for i in ticks:
		var ang := randf() * TAU
		var reach := r * (1.2 + randf() * 1.7)
		var p := _center + Vector2(cos(ang), sin(ang)) * reach
		draw_line(_center, p, Color(COL_CYAN.r, COL_CYAN.g, COL_CYAN.b, 0.35 * intensity * charge), 1.5, true)
	draw_circle(_center, r, Color(0.7, 0.9, 1.0, 0.5 * intensity))
	draw_circle(_center, r * 0.5, Color(1, 1, 1, 0.9 * intensity))

# One jagged bolt drawn as three stacked passes (wide soft glow, mid, bright core)
# plus a couple of short forked branches.
func _draw_bolt(a: Vector2, b: Vector2, seed: float, intensity: float) -> void:
	if intensity <= 0.02:
		return
	var amp := a.distance_to(b) * 0.06
	var pts := _jagged(a, b, seed, amp)
	var glow_col := COL_BLUE.lerp(COL_PURPLE, fmod(seed, 1.0))
	draw_polyline(pts, Color(glow_col.r, glow_col.g, glow_col.b, 0.18 * intensity), 9.0 * intensity + 3.0, true)
	draw_polyline(pts, Color(COL_CYAN.r, COL_CYAN.g, COL_CYAN.b, 0.55 * intensity), 4.0, true)
	draw_polyline(pts, Color(0.85, 0.95, 1.0, 0.95 * intensity), 1.6, true)
	_draw_branches(pts, seed, intensity)

# Short lightning forks springing off the main path at random nodes. Endpoints are
# re-rolled every frame so the branches crackle and dance (the "alive" feel).
func _draw_branches(pts: PackedVector2Array, seed: float, intensity: float) -> void:
	var n := pts.size()
	if n < 4:
		return
	var span := pts[0].distance_to(pts[n - 1])
	for j in 2:
		var idx := clampi(2 + int(randf() * (n - 4)), 1, n - 2)
		var base := pts[idx]
		var dir := (pts[idx + 1] - pts[idx - 1]).normalized().rotated(randf_range(-1.2, 1.2))
		var length := span * randf_range(0.06, 0.16)
		var bp := _jagged(base, base + dir * length, seed * 3.0 + float(j) * 7.0, length * 0.2)
		draw_polyline(bp, Color(COL_CYAN.r, COL_CYAN.g, COL_CYAN.b, 0.5 * intensity), 3.0, true)
		draw_polyline(bp, Color(0.9, 0.95, 1.0, 0.8 * intensity), 1.2, true)

# A jagged polyline from a to b. Perpendicular offsets combine a smoothly TIME-driven
# wander (reads as animated movement) with a per-frame random sparkle (flicker), and
# taper to zero at both ends so the bolt starts EXACTLY at a and ends EXACTLY at b.
func _jagged(a: Vector2, b: Vector2, seed: float, amp: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var segs := 12
	var dir := b - a
	var perp := Vector2(-dir.y, dir.x).normalized()
	for i in segs + 1:
		var f := float(i) / segs
		var base := a.lerp(b, f)
		var taper := sin(f * PI)
		var wander := sin(_t * 22.0 + seed * 1.7 + f * 9.0) + 0.6 * sin(_t * 41.0 + seed * 3.1 + f * 17.0)
		var sparkle := randf() * 2.0 - 1.0
		var off := (wander * 0.55 + sparkle * 0.45) * amp * taper
		pts.append(base + perp * off)
	return pts

# Expanding spark burst where a bolt meets the rim: radial spark lines that fly out
# and fade, plus a small hot flash at the impact point.
func _draw_sparks(p: Vector2, life: float, seed: float) -> void:
	var fade := 1.0 - life
	var reach := lerpf(3.0, 30.0, ease(life, 0.3))
	var count := 9
	for i in count:
		var ang := TAU * float(i) / count + seed + life * 2.0
		var tip := p + Vector2(cos(ang), sin(ang)) * reach * (0.6 + randf() * 0.6)
		var col := COL_CYAN if i % 2 == 0 else COL_PURPLE
		draw_line(p, tip, Color(col.r, col.g, col.b, 0.7 * fade), 2.0, true)
	draw_circle(p, lerp(7.0, 1.0, life), Color(1, 1, 1, 0.8 * fade))
