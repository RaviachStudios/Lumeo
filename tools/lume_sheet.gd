extends Node
# Renders a LUMEO world's free-running shader full-frame, with no board in front
# of it, so the composition can be judged on its own. Much faster than booting
# gameplay for every tweak.
#
#   Godot --path . res://tools/lume_sheet.tscn -- <id> [id ...]
#   Godot --path . res://tools/lume_sheet.tscn -- all
#
# Writes user://sheet_<id>.png at the design resolution. Pass "plate" to render the
# BAKED-PLATE variant instead of the live one, and "wait:<frames>" to sample the
# animation at a later phase (the default 40 frames is about 0.7 s of TIME).

const IDS := ["lume_rainbow", "lume_ocean", "lume_candy", "lume_space",
	"lume_forest", "lume_volcano", "lume_arcade", "lume_kingdom"]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var plate := args.has("plate")
	var ids: Array = []
	var frames := 40
	for x in args:
		if x == "plate":
			continue
		if x.begins_with("wait:"):
			frames = int(x.substr(5))
			continue
		if x == "all":
			ids.append_array(IDS)
		else:
			ids.append(x)
	if ids.is_empty():
		ids = IDS.duplicate()
	var sz := Vector2i(1280, 720)
	for id: String in ids:
		var code: String = ""
		if plate and BackgroundManager._NODE_PLATE.has(id):
			code = BackgroundManager._NODE_PLATE[id]
		elif BackgroundManager._SHADERS.has(id):
			code = BackgroundManager._SHADERS[id]
		if code.is_empty():
			print("MISSING  %s" % id)
			continue
		var vp := SubViewport.new()
		vp.size = sz
		vp.transparent_bg = false
		vp.disable_3d = true
		vp.msaa_2d = Viewport.MSAA_DISABLED
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var rect := ColorRect.new()
		rect.size = Vector2(sz)
		rect.color = Color(1, 1, 1, 1)
		var sh := Shader.new()
		sh.code = code
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mat.set_shader_parameter("aspect", float(sz.x) / float(sz.y))
		rect.material = mat
		vp.add_child(rect)
		add_child(vp)
		# a few frames so TIME is past zero and every prop has moved on-stage
		for i in frames:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var name := "sheet_%s%s.png" % [id, "_plate" if plate else ""]
		vp.get_texture().get_image().save_png("user://" + name)
		print("sheet  %s" % ProjectSettings.globalize_path("user://" + name))
		vp.queue_free()
	get_tree().quit()
