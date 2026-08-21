extends Control

# Per-frame GPU cost of every theme, on the shader each theme actually uses IN
# GAMEPLAY (baked plate -> blit, node themes -> their cheap dyn shader, the rest
# -> the full scene shader). Absolute numbers are desktop numbers; the RATIOS are
# what carries over to a phone.

const FRAMES := 90          # timed frames per theme
const WARM := 25            # frames discarded first (shader compile + pipeline warm)

var _rect: ColorRect
var _mat: ShaderMaterial
var _plate: ImageTexture
var _consts: Dictionary

func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_consts = BackgroundManager.get_script().get_script_constant_map()
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)
	_mat = ShaderMaterial.new()
	_rect.material = _mat
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.2, 0.25))
	_plate = ImageTexture.create_from_image(img)
	_run()

func _bench(code: String) -> float:
	var sh := Shader.new()
	sh.code = code
	_mat.shader = sh
	var sz := get_viewport().get_visible_rect().size
	_mat.set_shader_parameter("aspect", sz.x / maxf(1.0, sz.y))
	_mat.set_shader_parameter("static_tex", _plate)
	_mat.set_shader_parameter("plate_tex", _plate)
	_mat.set_shader_parameter("noise_tex", BackgroundManager._noise_lut)
	_rect.color = Color(1, 1, 1, 1)
	for i in WARM:
		await RenderingServer.frame_post_draw
	var t0 := Time.get_ticks_usec()
	for i in FRAMES:
		await RenderingServer.frame_post_draw
	return float(Time.get_ticks_usec() - t0) / float(FRAMES) / 1000.0

func _run() -> void:
	await BackgroundManager._ensure_noise_lut()          # Skybound/Inferno read it
	var shaders: Dictionary = _consts["_SHADERS"]
	var node_dyn: Dictionary = _consts["_NODE_DYN"]
	var static_bake: Dictionary = _consts["_STATIC_BAKE"]
	var blit: String = _consts["_BLIT_SHADER"]
	var gradients: Dictionary = _consts["_GRADIENTS"]

	# Empty-scene floor, so each theme's own cost is what sits above it.
	var floor_ms := await _bench("shader_type canvas_item;\nvoid fragment(){ COLOR = vec4(0.1,0.1,0.1,1.0); }")
	print("baseline (flat fill): %.3f ms/frame  [%s]" %
		[floor_ms, "%.0f fps" % (1000.0 / maxf(floor_ms, 0.001))])
	print("")

	var rows: Array = []
	var keys: Array = shaders.keys()
	keys.sort()
	for key: String in keys:
		var path := ""
		var code := ""
		if static_bake.has(key):
			path = "BAKED"
			code = blit
		elif node_dyn.has(key):
			path = "NODES"
			code = node_dyn[key]
		else:
			path = "FULL "
			code = shaders[key]
		var ms := await _bench(code)
		rows.append([ms - floor_ms, key, path])
	# One gradient theme as a "cheap theme" reference point.
	var g0: String = gradients.keys()[0]
	rows.append([(await _bench(BackgroundManager._gradient_shader(gradients[g0]))) - floor_ms,
		g0 + " (gradient)", "GRAD "])

	rows.sort_custom(func(a, b): return a[0] > b[0])
	print("theme cost above baseline, gameplay render path:")
	for r in rows:
		print("  %6.3f ms  %s  %s" % [r[0], r[2], r[1]])
	print("DONE")
	get_tree().quit()
