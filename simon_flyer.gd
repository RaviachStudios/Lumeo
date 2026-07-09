extends Node2D

# SimonFlyer — a small golden winged Simon that flaps and flies. Its three flap
# poses are BAKED ONCE to shared ImageTextures (static cache), so every screen that
# shows a flyer reuses the same textures: no per-frame rasterisation, nothing to
# make it laggy. Flight is just a Sprite2D moving + swapping frames + a soft bloom.
#
# One node = one flyer. Pick a mode in setup():
#   "cross"  — crosses the screen edge-to-edge on a gentle wave, infrequently.
#   "wander" — enters from a random edge, drifts to a random spot, hovers a beat,
#              then flies back out; infrequently. (active contest)
#   "rise"   — rises bottom→top on a horizontal wave, looping. `anchor_x`/`side`
#              place & mirror it; two risers started together read as a synced pair.

const SIMON_COLS := [
	Color(0.97, 0.78, 0.22), Color(0.88, 0.22, 0.24),
	Color(0.20, 0.70, 0.34), Color(0.24, 0.50, 0.95)]
const GOLD := Color(1.0, 0.82, 0.30)
const FLAP_SEQ := [0, 1, 2, 1]

static var _frames_cache: Array[Texture2D] = []
static var _radial_cache: Texture2D

var _mode := "cross"
var _sz := Vector2.ZERO
var _scale := 0.6
var _anchor_x := 0.0
var _side := 1.0
var _rise_amp := 34.0
var _rise_waves := 2.0
var _rise_dur := 3.8
var _rise_wait := 0.0         # idle gap between rises (keeps them infrequent)
var _top_pad := 0.0           # extra px to clear above y=0 (host content is inset)

# rise pause state — every so often a riser stalls mid-climb for a beat
var _rise_y := 0.0
var _rise_next_pause := 2.0    # prog point of the next stall (>1 → none left)
var _rise_pause_t := 0.0       # remaining stall time
var _rise_vel := 0.0           # current climb speed (prog/sec); eased toward target
var _osc := 0.0                # continuous sway phase (never resets → no jumps)

var _sprite: Sprite2D
var _bloom: Sprite2D
var _flap_t := 0.0

# flight state
var _phase := "idle"          # idle | fly | in | wait | out
var _timer := 0.0
var _prog := 0.0
var _dur := 4.0
var _p0 := Vector2.ZERO
var _p1 := Vector2.ZERO
var _amp := 40.0
var _freq := 2.0

func setup(size: Vector2, cfg: Dictionary = {}) -> void:
	_sz = size
	_mode = String(cfg.get("mode", "cross"))
	_scale = float(cfg.get("scale", 0.6))
	_anchor_x = float(cfg.get("anchor_x", size.x * 0.5))
	_side = float(cfg.get("side", 1.0))
	_rise_amp = float(cfg.get("amp", 34.0))
	_rise_waves = float(cfg.get("waves", 2.0))
	_rise_dur = float(cfg.get("dur", 3.8))
	_top_pad = float(cfg.get("top_pad", 0.0))

	_bloom = Sprite2D.new()
	_bloom.texture = _radial()
	_bloom.modulate = Color(GOLD.r, GOLD.g, GOLD.b, 0.5)
	var bm := CanvasItemMaterial.new()
	bm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_bloom.material = bm
	_bloom.visible = false
	add_child(_bloom)

	_sprite = Sprite2D.new()
	_sprite.texture = _frames()[0]
	_sprite.scale = Vector2.ONE * _scale
	_bloom.scale = Vector2.ONE * _scale * 1.4
	_sprite.visible = false
	add_child(_sprite)

	match _mode:
		"rise":
			# Rises are infrequent: start idle with a short random gap, then loop with
			# long idle waits between passes (see _proc_rise).
			_phase = "idle"
			_rise_wait = randf_range(float(cfg.get("delay", 1.0)), float(cfg.get("delay", 1.0)) + 4.0)
			_sprite.visible = false
			_bloom.visible = false
		"wander":
			_timer = randf_range(2.0, 6.0)
		_:
			_timer = randf_range(3.0, 7.0)
	set_process(true)

func relayout(size: Vector2) -> void:
	_sz = size

func _process(dt: float) -> void:
	match _mode:
		"rise": _proc_rise(dt)
		"wander": _proc_wander(dt)
		_: _proc_cross(dt)

# ---- cross (arena) ----
func _proc_cross(dt: float) -> void:
	if _phase != "fly":
		_timer -= dt
		if _timer <= 0.0:
			_launch_cross()
		return
	_prog += dt / _dur
	if _prog >= 1.0:
		_hide()
		_timer = randf_range(15.0, 28.0)
		return
	var pos := _p0.lerp(_p1, _prog)
	pos.y += sin(_prog * PI * _freq * 2.0) * _amp
	_place(pos, cos(_prog * PI * _freq * 2.0) * 0.14, _edge_alpha(_prog, 0.12))
	_advance_flap(dt, 9.0)

func _launch_cross() -> void:
	_phase = "fly"
	_prog = 0.0
	_dur = randf_range(3.6, 5.4)
	_amp = randf_range(22.0, 56.0)
	_freq = randf_range(1.4, 2.6)
	var dir := 1.0 if randf() < 0.5 else -1.0
	var y0 := randf_range(_sz.y * 0.18, _sz.y * 0.62)
	var y1: float = clampf(y0 + randf_range(-90.0, 90.0), _sz.y * 0.12, _sz.y * 0.7)
	_p0 = Vector2(-70.0 if dir > 0.0 else _sz.x + 70.0, y0)
	_p1 = Vector2(_sz.x + 70.0 if dir > 0.0 else -70.0, y1)
	_sprite.flip_h = dir < 0.0
	# Seat it at the off-screen start (alpha 0) before revealing — no stale-position flash.
	_place(_p0, 0.0, _edge_alpha(0.0, 0.12))
	_show()

# ---- wander (active) ----
func _proc_wander(dt: float) -> void:
	match _phase:
		"idle":
			_timer -= dt
			if _timer <= 0.0:
				_launch_wander()
		"in":
			_prog += dt / _dur
			if _prog >= 1.0:
				_phase = "wait"
				_timer = randf_range(0.9, 1.6)
			var p := _ease(_p0, _p1, _prog)
			_place(p, 0.0, 1.0)          # no fade — enters from off-screen
			_advance_flap(dt, 8.0)
		"wait":
			_timer -= dt
			_flap_t += dt * 4.0
			var bob := Vector2(0, sin(_flap_t) * 3.0)
			_place(_p1 + bob, sin(_flap_t) * 0.06, 1.0)
			_advance_flap(dt, 4.0)
			if _timer <= 0.0:
				_launch_wander_exit()
		"out":
			_prog += dt / _dur
			if _prog >= 1.0:
				_hide()
				_phase = "idle"
				_timer = randf_range(12.0, 22.0)
				return
			var q := _ease(_p0, _p1, _prog)
			_place(q, 0.0, 1.0)          # no fade — exits off-screen
			_advance_flap(dt, 8.0)

func _launch_wander() -> void:
	_phase = "in"
	_prog = 0.0
	_dur = randf_range(1.8, 2.6)
	_p0 = _random_edge_point()
	_p1 = Vector2(randf_range(_sz.x * 0.25, _sz.x * 0.75), randf_range(_sz.y * 0.25, _sz.y * 0.62))
	_sprite.flip_h = _p1.x < _p0.x
	# Seat it at the off-screen entry point before revealing — no stale-position flash.
	_place(_p0, 0.0, 1.0)
	_show()

func _launch_wander_exit() -> void:
	_phase = "out"
	_prog = 0.0
	_dur = randf_range(1.8, 2.6)
	_p0 = _sprite.position
	_p1 = _random_edge_point()
	_sprite.flip_h = _p1.x < _p0.x

# ---- rise (lobby, edge lanes) ----
# Rises up its lane bottom→top and flies fully off the top edge, then idles a long
# beat before the next pass. The climb speed eases in and out (never snaps), so it
# glides up from the bottom and slows to a halt at each stall. Horizontal sway is one
# continuous oscillator that runs the whole time — gentle while cruising, a livelier
# shiver while stalled — so the motion stays smooth with no jumps between the two.
func _proc_rise(dt: float) -> void:
	if _phase == "idle":
		_rise_wait -= dt
		if _rise_wait <= 0.0:
			_start_rise()
		return
	# Climb speed eases toward a target: cruise while flying, 0 while stalled. Because
	# it eases, the flyer visibly decelerates before a stop and accelerates after one.
	var cruise := 1.0 / _rise_dur
	var target := cruise
	if _rise_pause_t > 0.0:
		_rise_pause_t -= dt
		target = 0.0
		if _rise_pause_t <= 0.0:
			# Hold done — maybe schedule one more stall higher up (past 1.0 → none).
			_rise_next_pause = _prog + randf_range(0.34, 0.6)
	elif _prog >= _rise_next_pause:
		# Reached a scheduled stall: begin the hold.
		_rise_pause_t = randf_range(0.6, 1.3)
		_rise_next_pause = 2.0
		target = 0.0
	_rise_vel = move_toward(_rise_vel, target, cruise * 3.0 * dt)
	_prog += _rise_vel * dt
	if _prog >= 1.0:
		# Flown fully off the top: hide and wait a long, random beat before rising again.
		_phase = "idle"
		_sprite.visible = false
		_bloom.visible = false
		_rise_wait = randf_range(9.0, 18.0)
		return
	# Vertical travel from just below the bottom edge to fully above the top.
	_rise_y = lerpf(_sz.y + 70.0, -(90.0 + _top_pad), _prog)
	# `slow` is 0 at full cruise, 1 when stopped. Sway grows a little and quickens as
	# it slows, so a stall reads as a soft shiver — all continuous, no snap.
	var slow := 1.0 - clampf(_rise_vel / cruise, 0.0, 1.0)
	_osc += dt * (1.7 + 2.6 * slow)
	var x := _anchor_x + sin(_osc) * _rise_amp * (0.35 + 0.65 * slow)
	_place(Vector2(x, _rise_y), cos(_osc) * (0.04 + 0.05 * slow), 1.0)
	_advance_flap(dt, 6.5)

func _start_rise() -> void:
	_phase = "fly"
	_prog = 0.0
	_rise_vel = 0.0                             # eases up from a standstill → glides in
	_osc = randf() * TAU                        # random sway phase so the pair differ
	_rise_next_pause = randf_range(0.25, 0.7)   # first stall somewhere in the climb
	# Place at the prog=0 start (just below the bottom edge) BEFORE revealing, so the
	# first visible frame is already off-screen at the bottom — otherwise the sprite
	# shows for one frame at its stale position (a corner flash / jump on the first rise).
	_rise_y = _sz.y + 70.0
	_place(Vector2(_anchor_x + sin(_osc) * _rise_amp, _rise_y), cos(_osc) * 0.09, 1.0)
	_show()

# ---- helpers ----
func _random_edge_point() -> Vector2:
	# The top edge adds _top_pad so a flyer leaving upward clears the host's inset
	# content (the screen's real top sits _top_pad above y=0).
	match randi() % 4:
		0: return Vector2(randf_range(0, _sz.x), -(70.0 + _top_pad))
		1: return Vector2(randf_range(0, _sz.x), _sz.y + 70.0)
		2: return Vector2(-70.0, randf_range(0, _sz.y))
		_: return Vector2(_sz.x + 70.0, randf_range(0, _sz.y))

func _ease(a: Vector2, b: Vector2, t: float) -> Vector2:
	var e: float = t * t * (3.0 - 2.0 * t)      # smoothstep
	return a.lerp(b, e)

func _edge_alpha(t: float, w: float) -> float:
	return clampf(minf(t, 1.0 - t) / w, 0.0, 1.0)

func _place(pos: Vector2, rot: float, alpha: float) -> void:
	_sprite.position = pos
	_sprite.rotation = rot
	_sprite.modulate.a = alpha
	_bloom.position = pos
	_bloom.modulate.a = 0.5 * alpha

func _advance_flap(dt: float, speed: float) -> void:
	_flap_t += dt * speed
	_sprite.texture = _frames()[FLAP_SEQ[int(_flap_t) % FLAP_SEQ.size()]]

func _show() -> void:
	_sprite.visible = true
	_bloom.visible = true

func _hide() -> void:
	_phase = "idle"
	_sprite.visible = false
	_bloom.visible = false

# ===================== baked art (shared static cache) =====================

static func frames() -> Array[Texture2D]:
	return _frames()

static func radial() -> Texture2D:
	return _radial()

static func _frames() -> Array[Texture2D]:
	if _frames_cache.is_empty():
		for flap in [-0.85, 0.0, 0.85]:
			_frames_cache.append(_bake_simon(flap))
	return _frames_cache

static func _radial() -> Texture2D:
	if _radial_cache == null:
		var s := 128
		var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
		var c := Vector2(s, s) * 0.5
		for y in s:
			for x in s:
				var d := Vector2(x, y).distance_to(c) / (s * 0.5)
				img.set_pixel(x, y, Color(1, 1, 1, pow(clampf(1.0 - d, 0.0, 1.0), 2.0)))
		_radial_cache = ImageTexture.create_from_image(img)
	return _radial_cache

# One golden winged Simon frame. Wings painted first (behind), then the four-colour
# Simon disc over them, into a single RGBA image → one Sprite2D texture.
static func _bake_simon(flap: float) -> Texture2D:
	var px := 104
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var c := Vector2(px, px) * 0.5
	var body_r := 20.0
	var gap := deg_to_rad(15.0)
	var wing_l := 34.0
	var wing_w := 12.0
	for y in px:
		for x in px:
			var p := Vector2(x, y) + Vector2(0.5, 0.5) - c
			var out := Color(0, 0, 0, 0)
			for s in [-1.0, 1.0]:
				var sh := Vector2(s * 11.0, -2.0)
				var wdir := Vector2(s, -0.18 - 0.60 * flap).normalized()
				var wc := sh + wdir * (wing_l * 0.5)
				var loc := p - wc
				var u := loc.dot(wdir)
				var v := loc.dot(Vector2(-wdir.y, wdir.x))
				var e := (u / (wing_l * 0.5)) * (u / (wing_l * 0.5)) + (v / (wing_w * 0.5)) * (v / (wing_w * 0.5))
				var wa := clampf((1.0 - e) / 0.14, 0.0, 1.0)
				if wa > 0.0:
					var tip := clampf((u / (wing_l * 0.5)) * 0.5 + 0.5, 0.0, 1.0)
					var wcol := GOLD.lerp(Color(0.75, 0.52, 0.12), tip)
					out = _over(out, Color(wcol.r, wcol.g, wcol.b, wa))
			var r := p.length()
			if r <= body_r + 1.0:
				var ba := clampf((body_r - r) / 1.5, 0.0, 1.0)
				var disc := Color(0.20, 0.16, 0.09)
				if r >= 9.0 and r <= 17.0:
					var ang := atan2(p.y, p.x)
					var seg := int(floor((ang + PI * 0.75) / (PI * 0.5)))
					var a0 := -PI * 0.75 + seg * PI * 0.5 + gap * 0.5
					var a1 := -PI * 0.75 + (seg + 1) * PI * 0.5 - gap * 0.5
					var na := wrapf(ang, -PI, PI)
					if na >= a0 and na <= a1:
						disc = SIMON_COLS[((seg % 4) + 4) % 4]
				if r >= body_r - 2.5:
					disc = GOLD.lightened(0.1)
				if p.distance_to(Vector2(-5, -5)) < 4.0:
					disc = disc.lerp(Color(1, 1, 1), 0.35)
				out = _over(out, Color(disc.r, disc.g, disc.b, ba))
			img.set_pixel(x, y, out)
	return ImageTexture.create_from_image(img)

static func _over(dst: Color, src: Color) -> Color:
	var a := src.a + dst.a * (1.0 - src.a)
	if a <= 0.0:
		return Color(0, 0, 0, 0)
	var rgb := (Vector3(src.r, src.g, src.b) * src.a + Vector3(dst.r, dst.g, dst.b) * dst.a * (1.0 - src.a)) / a
	return Color(rgb.x, rgb.y, rgb.z, a)
