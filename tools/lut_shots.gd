extends Control

# Renders Inferno and Skybound both ways, at the phone's gameplay aspect, so the
# lookup version can be eyeballed against the fbm original.
const PX := Vector2i(1600, 720)
var _c: Dictionary
var _lut: ImageTexture

func _ready() -> void:
	_c = BackgroundManager.get_script().get_script_constant_map()
	_run()

func _original(code: String) -> String:
	var head: String = "shader_type canvas_item;\nuniform float aspect = 1.78;\n" + _c["_NOISE_GLSL"]
	return head + code.substr(code.find("void fragment()")).replace("nfbm(", "fbm(")

# TIME is global and can't be set, so freeze it to a literal per shot — that makes
# each frame reproducible and lets us look at the field far from t=0, where a
# tiling seam or a repeat would have scrolled into view.
func _at(code: String, t: float) -> String:
	return code.replace("TIME", "(%.4f)" % t)

func _shot(code: String, path: String) -> void:
	var vp := SubViewport.new()
	vp.size = PX
	vp.transparent_bg = false
	vp.disable_3d = true
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var r := ColorRect.new()
	r.size = Vector2(PX)
	r.color = Color(1, 1, 1, 1)
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = code
	m.shader = sh
	m.set_shader_parameter("aspect", float(PX.x) / float(PX.y))
	m.set_shader_parameter("noise_tex", _lut)
	r.material = m
	vp.add_child(r)
	add_child(vp)
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(path)
	vp.queue_free()

func _run() -> void:
	await BackgroundManager._ensure_noise_lut()
	_lut = BackgroundManager._noise_lut
	var out := "user://"
	for name in ["INFERNO", "SKYBOUND"]:
		var lut_code: String = _c["_" + name + "_SHADER"]
		for t in [0.0, 37.0, 180.0]:
			await _shot(_at(_original(lut_code), t), "%s%s_t%d_before.png" % [out, name.to_lower(), int(t)])
			await _shot(_at(lut_code, t), "%s%s_t%d_after.png" % [out, name.to_lower(), int(t)])
	print("wrote to ", ProjectSettings.globalize_path(out))
	get_tree().quit()
