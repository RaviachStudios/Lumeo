extends Node2D
# ThemeProps — the cheap PARTICLE layer drawn over a baked static plate. The dense
# per-pixel dot loops (sparkles, fireflies, stars) were the shader perf killers;
# here they are real CPUParticles2D (GL/Mali-safe), drawn only where each dot is.
# The distinct "hero" props (fairies, birds, galaxies, ships, ...) stay in a light
# shader over the plate (see background_manager), which keeps their animation
# pixel-smooth and correctly sized. One instance per node theme.

const DOT_PX := 32

var _sz := Vector2.ZERO
var _key := ""
var _bg: Node                       # BackgroundManager, for driving kitty eye uniforms

# --- kitty gesture state ---
var _gesture := ""                  # "" | "blink" (both eyes) | "wink" (one eye)
var _gt := 0.0                      # elapsed time in the current gesture
var _blink_timer := 0.0             # countdown to the next idle blink

# --- volcano (skin:inferno) eruption state ---
# One activity value per corner volcano, pushed to the dyn shader's `erupt` vec4
# each frame. It idles low (breathing crater glow) and jumps on level complete,
# then decays back to idle so the eruption plays out over a few seconds.
var _vt := 0.0                                          # volcano idle clock
var _erupt := [0.0, 0.0, 0.0, 0.0]                      # current activity per volcano
var _erupt_pending := [0.0, 0.0, 0.0, 0.0]             # staged burst peak
var _erupt_delay := [0.0, 0.0, 0.0, 0.0]               # per-volcano stagger before firing

func setup(key: String, size: Vector2, bgmgr: Node) -> void:
	_sz = size
	_key = key
	_bg = bgmgr
	var dot := _make_dot()
	match key:
		"fairies":
			# pink sparkle dust drifting up + a few warm fireflies
			_add_particles(dot, 30, 6.0, Color(1.0, 0.70, 0.90), 0.10, 0.22, 3.0, 12.0, 30.0, 0.42, 0.42, true)
			_add_particles(dot, 6, 8.0, Color(1.0, 0.85, 0.55), 0.22, 0.40, 2.0, 8.0, 80.0, 0.45, 0.40, true)
		"deepspace":
			_add_particles(dot, 50, 3.0, Color(1, 1, 1), 0.04, 0.10, 0.0, 0.0, 0.0, 0.50, 0.50, true)
		"cosmos":
			_add_particles(dot, 30, 3.0, Color(1, 1, 1), 0.04, 0.10, 0.0, 0.0, 0.0, 0.50, 0.50, true)
		"neon":
			_add_particles(dot, 14, 3.0, Color(0.92, 0.92, 0.98), 0.04, 0.09, 0.0, 0.0, 0.0, 0.20, 0.20, true)
		"aurora":
			_add_particles(dot, 40, 3.0, Color(0.92, 0.96, 1.0), 0.04, 0.09, 0.0, 0.0, 0.0, 0.275, 0.275, true)
		"kitty":
			# hearts drifting up across the whole screen, fading in/out (alpha-blended)
			_add_particles(_make_heart(), 18, 5.0, Color(1.0, 0.45, 0.65), 0.40, 0.90, 6.0, 16.0, 20.0, 0.50, 0.50, false)
			_blink_timer = randf_range(2.0, 4.0)
		"reef":
			# rising bubble rings
			_add_particles(_make_ring(), 10, 5.0, Color(0.55, 0.85, 0.92), 0.35, 0.60, 8.0, 18.0, 14.0, 0.55, 0.45, true)
		"skin:inferno":
			# rising embers (additive) + slowly falling ash flakes (darkening)
			_add_particles(dot, 30, 5.0, Color(1.0, 0.50, 0.12), 0.05, 0.14, 6.0, 20.0, 24.0, 0.55, 0.45, true)
			_add_particles(dot, 14, 7.0, Color(0.09, 0.07, 0.09), 0.06, 0.12, 3.0, 9.0, 40.0, 0.50, 0.50, false, 1.0)
		_:
			pass
	# kitty runs a gesture controller; the volcano drives its eruption uniforms
	set_process(key == "kitty" or key == "skin:inferno")

# ===========================================================================
# KITTY gestures — driven every frame while the kitty theme is active. Idle:
# randomly blink both eyes with a smile. On level complete: wink one eye + pop a
# speech cloud with a random message. Eye state is pushed to the kitty shader via
# BackgroundManager.set_kitty_eyes(); the cloud is a real node with a Label.
# ===========================================================================
func _process(dt: float) -> void:
	if _key == "skin:inferno":
		_process_volcano(dt)
		return
	if _key != "kitty":
		return
	_gt += dt
	var el := 1.0
	var er := 1.0
	var sm := 0.0
	if _gesture == "blink":
		var b := sin(PI * clampf(_gt / 0.30, 0.0, 1.0))     # 0 -> 1 -> 0 (close then open)
		el = 1.0 - b
		er = 1.0 - b
		sm = b
		if _gt >= 0.30:
			_gesture = ""
	elif _gesture == "wink":
		var b := sin(PI * clampf(_gt / 0.55, 0.0, 1.0))
		er = 1.0 - b                                        # only the right eye winks
		sm = 0.5 * b
		if _gt >= 0.55:
			_gesture = ""
	if is_instance_valid(_bg):
		_bg.call("set_kitty_eyes", el, er, sm)
	# schedule the next idle blink when nothing is playing
	if _gesture == "":
		_blink_timer -= dt
		if _blink_timer <= 0.0:
			_gesture = "blink"
			_gt = 0.0
			_blink_timer = randf_range(3.5, 6.5)

# Called by BackgroundManager.notify_level_complete(): the cat winks one eye, and
# the volcano erupts — mid on every level, heavier on milestones, big past 20.
func on_level_complete(level: int) -> void:
	if _key == "kitty":
		_gesture = "wink"
		_gt = 0.0
		return
	if _key == "skin:inferno":
		var peak := 1.4                                     # mid erupt on every level
		if level >= 20:
			peak = 3.0                                      # big erupt every level from 20 on
		elif level == 5 or level == 10 or (level > 10 and (level - 10) % 3 == 0):
			peak = 2.2                                      # heavy erupt (5, 10, then every 3)
		for i in 4:
			_erupt_pending[i] = peak * (0.85 + 0.30 * randf())   # slight per-crater variation
			_erupt_delay[i] = 0.02 + i * 0.12 + randf() * 0.05   # staggered pops, left -> right
		return

# Volcano controller: each frame, fire any staged eruption whose stagger has
# elapsed, then decay every volcano's activity back toward a low breathing idle,
# and push all four to the dyn shader's `erupt` uniform.
func _process_volcano(dt: float) -> void:
	_vt += dt
	for i in 4:
		if _erupt_delay[i] > 0.0:
			_erupt_delay[i] -= dt
			if _erupt_delay[i] <= 0.0:
				_erupt[i] = maxf(_erupt[i], _erupt_pending[i])   # fire the staged burst
		var idle := 0.10 + 0.05 * sin(_vt * 0.8 + i * 1.7)       # breathing ambient glow/smoke
		_erupt[i] = move_toward(_erupt[i], idle, dt * 0.55)      # eruptions ease back to idle
	if is_instance_valid(_bg):
		_bg.call("set_volcano_erupt", _erupt[0], _erupt[1], _erupt[2], _erupt[3])

# A soft round white dot, tinted per-system.
func _make_dot() -> ImageTexture:
	var img := Image.create(DOT_PX, DOT_PX, false, Image.FORMAT_RGBA8)
	var c := Vector2(DOT_PX, DOT_PX) * 0.5
	var r := float(DOT_PX) * 0.5
	for y in DOT_PX:
		for x in DOT_PX:
			var d := (Vector2(x, y) + Vector2(0.5, 0.5)).distance_to(c) / r
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)

func _add_mat() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m

# Alpha fades 0 -> full -> 0 across a particle's life, so each dot twinkles on.
func _twinkle_ramp() -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	return g

# A soft heart (kitty), point-down. Implicit-curve fill with a soft edge.
func _make_heart() -> ImageTexture:
	var px := 48
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	for y in px:
		for x in px:
			var u := (float(x) + 0.5) / px * 2.6 - 1.3
			var v := 1.3 - (float(y) + 0.5) / px * 2.6        # +v is up
			var h := u * u + v * v - 1.0
			var val := h * h * h - u * u * v * v * v          # < 0 inside the heart
			img.set_pixel(x, y, Color(1, 1, 1, clampf(0.5 - val * 5.0, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)

# A hollow ring (reef bubbles): alpha peaks at ~0.78 of the radius.
func _make_ring() -> ImageTexture:
	var px := 32
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var c := Vector2(px, px) * 0.5
	var r := float(px) * 0.5
	for y in px:
		for x in px:
			var dd := (Vector2(x, y) + Vector2(0.5, 0.5)).distance_to(c) / r
			var ring := 1.0 - absf(dd - 0.78) / 0.20
			img.set_pixel(x, y, Color(1, 1, 1, clampf(ring, 0.0, 1.0) * 0.9))
	return ImageTexture.create_from_image(img)

# Emit `amount` dots/sprites over a screen band centred at cy (fraction of height)
# with half-height hy, drifting up at vmin..vmax (0 = twinkle in place). `additive`
# picks add vs. normal blend.
func _add_particles(tex: Texture2D, amount: int, life: float, col: Color, smin: float, smax: float,
		vmin: float, vmax: float, spread: float, cy: float, hy: float, additive: bool, dir_y: float = -1.0) -> void:
	var p := CPUParticles2D.new()
	p.texture = tex
	if additive:
		p.material = _add_mat()
	p.amount = amount
	p.lifetime = life
	p.preprocess = life                                     # pre-fill so no ramp-up
	p.position = Vector2(_sz.x * 0.5, _sz.y * cy)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(_sz.x * 0.5, _sz.y * hy)
	p.direction = Vector2(0, dir_y)
	p.spread = spread
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.scale_amount_min = smin
	p.scale_amount_max = smax
	p.color = col
	p.color_ramp = _twinkle_ramp()
	add_child(p)
