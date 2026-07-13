extends Node2D

# ArenaFX — the cinematic "grand colosseum" flourish behind the hub UI. It layers,
# from back to front:
#   • a bobbing CROWD silhouette bowl curving across the upper stands,
#   • draped medieval BANNERS that gently wave,
#   • flickering wall TORCHES with rising gold EMBERS,
#   • a low drift of ground SMOKE / dust,
#   • the centrepiece: a stone PLATFORM crowned with a big winged-Simon CHAMPIONSHIP
#     SHIELD, plus small golden winged SIMONS that flap across the screen now and then.
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
# Four Simon-disc colours (gold / red / green / blue) for the championship emblem.
const SIMON_COLS := [
	Color(0.97, 0.78, 0.22), Color(0.88, 0.22, 0.24),
	Color(0.20, 0.70, 0.34), Color(0.24, 0.50, 0.95)]
const TORCH := Color(1.0, 0.55, 0.18)
const EMBER := Color(1.0, 0.70, 0.30)
const SMOKE := Color(0.62, 0.60, 0.74)
# Crowd + banners lean into the game's purple/gold identity.
const CROWD_COL  := Color(0.10, 0.08, 0.18)
const BANNER_PUR := Color(0.30, 0.12, 0.40)
const BANNER_CRIM := Color(0.46, 0.11, 0.20)

# Layout constants mirror arena_screen's card so the platform sits under it.
const CARD_TOP := 150.0
const CARD_H := 296.0

var _sz := Vector2.ZERO
var _t := 0.0

# ---- ambient ----
var _crowd: Node2D
var _crowd_cols: PackedFloat32Array = PackedFloat32Array()   # per-column bob phase
var _banners: Array[Dictionary] = []      # {node, cx, halfw, len, phase, cols}
var _torch_lamps: Array[Sprite2D] = []
var _torch_phase: PackedFloat32Array = PackedFloat32Array()
var _embers: CPUParticles2D
var _smoke: CPUParticles2D

# ---- centrepiece (platform) ----
var _duel: Node2D
var _platform_c := Vector2.ZERO
var _duel_scale := 1.0

# ---- winged Simons that flap across the arena ----
var _flyers: Array = []

# ---- event envelopes ----
var _cheer := 0.0          # 0..1 crowd cheer + torch flare (decays ~1s)
var _big_timer := 12.0     # countdown to the next crowd cheer + torch flare

func setup(size: Vector2) -> void:
	_sz = size
	_build()
	set_process(true)

func relayout(size: Vector2) -> void:
	_sz = size
	_build()

# ---------------- build ----------------

func _build() -> void:
	for c in get_children():
		c.queue_free()
	_torch_lamps.clear()
	_banners.clear()
	_flyers.clear()

	_build_crowd()
	_build_smoke()
	_build_banners()
	_build_torches()
	_build_platform()
	_build_embers()
	_build_flyers()

	_big_timer = randf_range(10.0, 15.0)

# --- crowd: a curved bowl of bobbing silhouette heads across the upper stands ---
func _build_crowd() -> void:
	_crowd = Node2D.new()
	_crowd.draw.connect(_draw_crowd)
	add_child(_crowd)
	# Stable per-column phase so heads bob out of sync but never re-randomise.
	var cols := int(clampf(_sz.x / 24.0, 18.0, 60.0))
	_crowd_cols = PackedFloat32Array()
	_crowd_cols.resize(cols)
	for i in cols:
		_crowd_cols[i] = fmod(sin(float(i) * 12.9898) * 43758.5453, 1.0) * TAU
	_crowd.queue_redraw()

func _draw_crowd() -> void:
	var cols := _crowd_cols.size()
	if cols == 0:
		return
	var rows := 4
	var top_y := _sz.y * 0.035
	var row_gap := 15.0
	var bowl := _sz.y * 0.10                 # how far the outer columns curve down
	var rim := Color(0.55, 0.40, 0.62, 0.5)  # faint warm rim light on the crowd
	var cheer_lift := _cheer * 6.0
	for r in rows:
		var seat_t := float(r) / float(rows - 1)   # 0 front row … 1 back row
		var head_r := lerpf(4.2, 2.6, seat_t)
		var base_a := lerpf(0.85, 0.45, seat_t)
		var col := Color(CROWD_COL.r, CROWD_COL.g, CROWD_COL.b, base_a)
		for i in cols:
			var fx := (float(i) + 0.5) / float(cols)          # 0..1 across width
			var cxn := (fx - 0.5) * 2.0                        # -1..1
			var x := fx * _sz.x
			var y := top_y + r * row_gap + cxn * cxn * bowl
			var bob := sin(_t * 1.7 + _crowd_cols[i] + r * 0.6) * (1.6 + cheer_lift)
			var p := Vector2(x, y - bob)
			_crowd.draw_circle(p, head_r, col)                 # head
			_crowd.draw_circle(p + Vector2(0, head_r * 1.2), head_r * 1.25,
				Color(col.r, col.g, col.b, col.a * 0.7))       # shoulders
			# a faint warm rim when the crowd is cheering
			if _cheer > 0.01:
				_crowd.draw_arc(p, head_r + 0.6, PI, TAU, 6,
					Color(rim.r, rim.g, rim.b, rim.a * _cheer), 1.2, true)

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

# --- the centrepiece: the inlaid Simon-wheel platform, redrawn each frame ---
func _build_platform() -> void:
	_platform_c = Vector2(_sz.x * 0.5, CARD_TOP + CARD_H * 0.60)
	_duel_scale = clampf(_sz.x / 520.0, 0.82, 1.25)

	_duel = Node2D.new()
	_duel.position = _platform_c
	_duel.scale = Vector2.ONE * _duel_scale
	_duel.draw.connect(_draw_platform)
	add_child(_duel)

# --- little golden winged Simons that flap across the arena now and then ---
func _build_flyers() -> void:
	# Two crossers on staggered timers so the arena always has a bit of life above
	# the platform without ever feeling busy (each waits 15–28s between passes).
	for i in 2:
		var f := SimonFlyer.new()
		add_child(f)
		f.setup(_sz, {"mode": "cross", "scale": 0.58})
		_flyers.append(f)

func _fade_ramp(peak: Color) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	g.colors = PackedColorArray([
		Color(peak.r, peak.g, peak.b, 0.0), peak,
		Color(peak.r, peak.g, peak.b, 0.0)])
	return g

# ---------------- platform drawing ----------------

func _draw_platform() -> void:
	# a squashed stone dais with a soft cast shadow and a beveled, rivet-studded rim
	_draw_ellipse(Vector2(0, 13), 86, 22, Color(0.02, 0.02, 0.05, 0.5), 28)
	_draw_ellipse(Vector2(0, 7), 82, 20, Color(0.13, 0.11, 0.18, 0.96), 28)
	_draw_ellipse(Vector2(0, 5), 77, 18, Color(0.21, 0.18, 0.28, 0.98), 28)
	_draw_ellipse(Vector2(0, 3), 71, 16, Color(0.27, 0.23, 0.35, 1.0), 28)
	# gold rivets studded around the stone rim
	for k in 14:
		var ra := float(k) / 14.0 * TAU
		_duel.draw_circle(Vector2(cos(ra) * 74.0, 5.0 + sin(ra) * 15.0), 1.5,
			Color(GOLD.r, GOLD.g, GOLD.b, 0.45))
	# --- the champion emblem: a big winged Simon mounted on a heraldic shield ---
	_draw_champion_shield()

# The centrepiece trophy: a gold-rimmed heraldic shield bearing the four-colour Simon
# disc, flanked by outstretched golden wings and topped with a small crown — a
# "championship shield" that stands on the dais where the duelling knights used to be.
func _draw_champion_shield() -> void:
	var puls := 0.5 + 0.5 * sin(_t * 2.0)
	var flap := sin(_t * 2.4)                              # gentle wing beat
	var sc := Vector2(0.0, -13.0)                          # shield centre
	var top_y := -25.0
	var bot_y := 21.0
	var w := 21.0

	# soft golden aura behind the whole emblem
	_duel.draw_circle(sc + Vector2(0, -2), 34.0 + puls * 4.0, Color(GOLD.r, GOLD.g, GOLD.b, 0.05))

	# wings spread behind the shield (drawn first so the shield overlaps their roots)
	for s in [-1.0, 1.0]:
		_draw_wing(sc + Vector2(s * 13.0, top_y + 8.0), s, flap)

	# shield: cast shadow, dark body, inner bevel, then a bright gold rim
	var path := _shield_path(sc + Vector2(0, 1.5), w, top_y, bot_y)
	_duel.draw_colored_polygon(path, Color(0.02, 0.02, 0.05, 0.4))            # shadow
	_duel.draw_colored_polygon(_shield_path(sc, w, top_y, bot_y), Color(0.16, 0.10, 0.26, 1.0))
	_duel.draw_colored_polygon(_shield_path(sc, w - 2.4, top_y + 2.2, bot_y - 3.0),
		Color(0.24, 0.16, 0.38, 1.0))                                        # inner face
	var rim := _shield_path(sc, w, top_y, bot_y)
	rim.append(rim[0])
	_duel.draw_polyline(rim, GOLD, 2.0, true)                                # gold border

	# the Simon disc, seated on the shield face
	_draw_simon_disc(sc + Vector2(0, -3.0), 12.0, puls)

	# a small three-point crown resting on the shield's top edge
	_draw_crown(sc + Vector2(0, top_y - 1.0), 12.0)

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
func _draw_wing(base: Vector2, s: float, flap: float) -> void:
	var n := 5
	for i in n:
		var f := float(i) / float(n - 1)                 # 0 = top feather, 1 = bottom
		# theta: angle above horizontal (top feathers point up, bottom ones fan out flat)
		var theta := deg_to_rad(lerpf(62.0, -8.0, f)) + flap * 0.18 * (1.0 - f)
		var length := lerpf(30.0, 17.0, f)
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

# The four-colour Simon disc: gold rim, four quadrant arcs, a dark hub and gloss.
func _draw_simon_disc(c: Vector2, r: float, puls: float) -> void:
	_duel.draw_circle(c, r + 1.5, Color(GOLD.r, GOLD.g, GOLD.b, 0.10 + puls * 0.10))  # glow
	_duel.draw_circle(c, r, GOLD.darkened(0.12))                 # gold rim
	_duel.draw_circle(c, r * 0.88, Color(0.05, 0.04, 0.09))      # dark gap ring
	var r_out := r * 0.84
	var r_in := r * 0.40
	var gap := deg_to_rad(11.0)
	for q in 4:
		var a0 := -PI * 0.75 + q * PI * 0.5 + gap * 0.5
		var a1 := -PI * 0.75 + (q + 1) * PI * 0.5 - gap * 0.5
		var poly := PackedVector2Array()
		for i in 9:
			var a := lerpf(a0, a1, i / 8.0)
			poly.append(c + Vector2(cos(a), sin(a)) * r_out)
		for i in 9:
			var a := lerpf(a1, a0, i / 8.0)
			poly.append(c + Vector2(cos(a), sin(a)) * r_in)
		_duel.draw_colored_polygon(poly, SIMON_COLS[q])
	_duel.draw_circle(c, r_in * 0.95, Color(0.10, 0.08, 0.15))   # hub
	_duel.draw_circle(c, r_in * 0.5, GOLD.lightened(0.1))        # gold centre
	_duel.draw_circle(c + Vector2(-r * 0.28, -r * 0.28), r * 0.16, Color(1, 1, 1, 0.20))  # gloss

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
func _draw_ellipse(c: Vector2, rx: float, ry: float, col: Color, steps: int) -> void:
	var pts := PackedVector2Array()
	for i in steps:
		var a := float(i) / float(steps) * TAU
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	_duel.draw_colored_polygon(pts, col)

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

	# banners wave; crowd bobs; the platform wheel shimmers — all redraw cheaply
	_update_banners()
	if _crowd:
		_crowd.queue_redraw()
	if _duel:
		_duel.queue_redraw()

	# torch flicker (+ flare during a cheer)
	for i in _torch_lamps.size():
		var flick := 0.58 + 0.16 * sin(_t * 7.0 + _torch_phase[i]) + 0.08 * sin(_t * 13.0 + _torch_phase[i] * 2.0)
		var lamp := _torch_lamps[i]
		lamp.modulate.a = flick + _cheer * 0.5
		lamp.scale = Vector2.ONE * (58.0 / 128.0) * (1.0 + _cheer * 0.25 + 0.03 * sin(_t * 9.0 + _torch_phase[i]))
