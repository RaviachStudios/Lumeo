extends Control

# Does a lit/pressed segment ever reach the SubViewport's render target while the
# REAL heavy theme is painting behind it and the frame rate has collapsed?
#
# Every rendered frame is sampled (frame_post_draw) and bucketed per WHEEL
# SEGMENT, so "panel N got brighter on screen" is measured, not inferred.

const COLORS := [
	Color(0.74, 0.13, 0.13), Color(0.13, 0.56, 0.24), Color(0.13, 0.30, 0.74),
	Color(0.82, 0.64, 0.10), Color(0.82, 0.40, 0.10),
]
const N := 5
const VP := 560

var _wheel: SimonWheel
var _stall_ms := 0.0
var _buckets: Array = []
var _peak := PackedFloat32Array()
var _base := PackedFloat32Array()
var _frames := 0
var _dt_sum := 0.0

func _ready() -> void:
	_wheel = SimonWheel.new()
	add_child(_wheel)
	_wheel.size = Vector2(VP, VP)
	_wheel.position = (Vector2(1280, 720) - _wheel.size) * 0.5
	_wheel.configure(N, COLORS)
	_wheel.set_level(1)
	_peak.resize(N)
	_base.resize(N)
	RenderingServer.frame_post_draw.connect(_sample)
	set_process(true)
	_run()

func _process(_dt: float) -> void:
	if _stall_ms > 0.0:
		var end := Time.get_ticks_usec() + int(_stall_ms * 1000.0)
		while Time.get_ticks_usec() < end:
			pass

func _build_buckets() -> void:
	_buckets.clear()
	for i in N:
		_buckets.append(PackedVector2Array())
	for y in range(4, VP - 4, 5):
		for x in range(4, VP - 4, 5):
			var seg: int = _wheel.segment_at_point(Vector2(x, y))
			if seg >= 0 and seg < N:
				_buckets[seg].append(Vector2(x, y))

func _read() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(N)
	var img := _wheel._vp.get_texture().get_image()
	for i in N:
		var pts: PackedVector2Array = _buckets[i]
		var sum := 0.0
		for p in pts:
			var c := img.get_pixel(int(p.x), int(p.y))
			sum += (c.r + c.g + c.b) * c.a / 3.0
		out[i] = sum / maxf(float(pts.size()), 1.0)
	return out

func _sample() -> void:
	if _buckets.is_empty():
		return
	var cur := _read()
	for i in N:
		if cur[i] > _peak[i]:
			_peak[i] = cur[i]
	_frames += 1
	_dt_sum += get_process_delta_time()

func _frames_wait(n: int) -> void:
	for i in n:
		await RenderingServer.frame_post_draw

func _arm() -> void:
	for i in N:
		_peak[i] = 0.0
	_frames = 0
	_dt_sum = 0.0

func _measure(label: String, idx: int, body: Callable) -> void:
	_arm()
	await body.call()
	await _frames_wait(3)
	var lift := _peak[idx] - _base[idx]
	var rel := lift / maxf(_base[idx], 0.0001)
	var verdict := "LIT " if rel > 0.15 else "DARK"
	print("  %s  %-22s seg%d base=%.4f peak=%.4f  %+.0f%%   frames=%d avg_dt=%.3f" %
		[verdict, label, idx, _base[idx], _peak[idx], rel * 100.0, _frames,
		 _dt_sum / maxf(float(_frames), 1.0)])

func _flash(idx: int, duration: float) -> void:
	_wheel.set_lit(idx, true)
	await get_tree().create_timer(duration).timeout
	_wheel.set_lit(idx, false)

func _press_feedback(idx: int) -> void:
	_wheel.set_press(idx, 1.0)
	_wheel.set_lit(idx, true)
	get_tree().create_timer(0.18).timeout.connect(func() -> void:
		_wheel.set_lit(idx, false)
		_wheel.set_press(idx, 0.0))

# Put the manager into the exact state gameplay puts it in for `theme`.
func _equip(theme: String, skin: String) -> void:
	CoinsManager.selected_theme = theme
	if skin.is_empty():
		CoinsManager.simon_mode = CoinsManager.SIMON_MODE_MANUAL   # ignore any equipped skin bg
	else:
		CoinsManager.simon_mode = CoinsManager.SIMON_MODE_SKIN
		CoinsManager.selected_skin = skin
	_wheel.apply_skin(null, null, null, skin)
	BackgroundManager.set_active(false)
	BackgroundManager.set_active(true)
	BackgroundManager._apply_theme()
	# node themes paint the full shader until their plate lands — wait it out
	for i in 240:
		await RenderingServer.frame_post_draw
		if BackgroundManager._render_mode != "FULL" or not BackgroundManager._NODE_PLATE.has(theme):
			break

func _sweep(theme: String, skin: String = "") -> void:
	await _equip(theme, skin)
	print("")
	print("=== theme '%s' skin '%s'  bg_key=%s render_mode=%s animated_wheel=%s ===" %
		[theme, skin, BackgroundManager._resolved_bg_key(), BackgroundManager._render_mode,
		 _wheel._animated_skin()])
	for target_fps in [60.0, 12.0, 7.0, 5.0]:
		_stall_ms = 0.0 if target_fps >= 60.0 else 1000.0 / target_fps
		await _frames_wait(15)
		_base = _read()
		print("--- target %.0f fps (dt=%.3fs) ---" % [target_fps, get_process_delta_time()])
		await _measure("sequence flash 0.40s", 0, func() -> void: await _flash(0, 0.40))
		await _measure("sequence flash 0.18s", 1, func() -> void: await _flash(1, 0.18))
		await _measure("press feedback", 2, func() -> void:
			_press_feedback(2)
			await get_tree().create_timer(0.35).timeout)
		await _measure("2nd of a double-tap", 3, func() -> void:
			_press_feedback(3)
			await get_tree().create_timer(0.10).timeout
			_arm()
			_press_feedback(3)
			await get_tree().create_timer(0.35).timeout)

func _run() -> void:
	await _frames_wait(30)
	_build_buckets()
	await _sweep("midnight")
	await _sweep("castle")
	await _sweep("inferno")
	await _sweep(CoinsManager.DEFAULT_THEME, "inferno")
	print("DONE")
	get_tree().quit()
