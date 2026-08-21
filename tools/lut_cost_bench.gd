extends Control

# The lookup version is cheaper than this desktop GPU can resolve in a single
# full-screen pass, so stack N passes to lift both versions clear of the floor and
# get a real ratio. Each pass is one full-screen draw of the theme.
const PASSES := 8
const FRAMES := 90
const WARM := 25

var _rects: Array[ColorRect] = []
var _c: Dictionary
var _lut: ImageTexture

func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_c = BackgroundManager.get_script().get_script_constant_map()
	for i in PASSES:
		var r := ColorRect.new()
		r.set_anchors_preset(Control.PRESET_FULL_RECT)
		r.color = Color(1, 1, 1, 1)
		r.material = ShaderMaterial.new()
		add_child(r)
		_rects.append(r)
	_run()

func _original(code: String) -> String:
	var head: String = "shader_type canvas_item;\nuniform float aspect = 1.78;\n" + _c["_NOISE_GLSL"]
	return head + code.substr(code.find("void fragment()")).replace("nfbm(", "fbm(")

func _bench(code: String) -> float:
	var sh := Shader.new()
	sh.code = code
	for r in _rects:
		var m: ShaderMaterial = r.material
		m.shader = sh
		m.set_shader_parameter("aspect", 1.78)
		m.set_shader_parameter("noise_tex", _lut)
	for i in WARM:
		await RenderingServer.frame_post_draw
	var t0 := Time.get_ticks_usec()
	for i in FRAMES:
		await RenderingServer.frame_post_draw
	return float(Time.get_ticks_usec() - t0) / float(FRAMES) / 1000.0 / float(PASSES)

func _run() -> void:
	await BackgroundManager._ensure_noise_lut()
	_lut = BackgroundManager._noise_lut
	var floor_ms := await _bench("shader_type canvas_item;\nvoid fragment(){ COLOR = vec4(0.1,0.1,0.1,0.5); }")
	print("floor (flat fill): %.4f ms per full-screen pass" % floor_ms)
	for name in ["INFERNO", "SKYBOUND"]:
		var lut_code: String = _c["_" + name + "_SHADER"]
		var a := await _bench(_original(lut_code)) - floor_ms
		var b := await _bench(lut_code) - floor_ms
		print("%-9s fbm %.4f ms  ->  lookup %.4f ms   %.1fx cheaper" % [name, a, b, a / maxf(b, 0.00001)])
	print("DONE")
	get_tree().quit()
