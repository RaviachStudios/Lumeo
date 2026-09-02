extends Node
# Measures Godot's AgX transfer curve against Blender's AgX - Punchy, on the same
# ramp of linear emissive values (and the same four saturated hues), so the
# difference between the two transforms is a table of numbers instead of an
# impression. The Blender half is rendered by the throwaway script in the session
# notes; this reads its PNG back and prints them side by side.
const VALS := [0.002, 0.002245, 0.00252, 0.002828, 0.003175, 0.003564, 0.004, 0.00449, 0.00504, 0.005657, 0.00635, 0.007127, 0.008, 0.00898, 0.010079, 0.011314, 0.012699, 0.014254, 0.016, 0.017959, 0.020159, 0.022627, 0.025398, 0.028509, 0.032, 0.035919, 0.040317, 0.045255, 0.050797, 0.057018, 0.064, 0.071838, 0.080635, 0.09051, 0.101594, 0.114035, 0.128, 0.143675, 0.16127, 0.181019, 0.203187, 0.22807, 0.256, 0.28735, 0.32254, 0.362039, 0.406375, 0.45614, 0.512, 0.574701, 0.64508, 0.724077, 0.812749, 0.91228, 1.024, 1.149401, 1.290159, 1.448155, 1.625499, 1.824561, 2.048, 2.298802, 2.580318, 2.896309, 3.250997, 3.649121, 4.096, 4.597605, 5.160637, 5.792619, 6.501995, 7.298242, 8.192, 9.195209, 10.321273, 11.585238, 13.003989, 14.596485, 16.384, 18.390418, 20.642546, 23.170475, 26.007979, 29.192969, 32.768, 36.780836]
const HUES := []
const CELL := 16

func _ready() -> void:
	for i in 10: await get_tree().process_frame
	var rows: Array = [Vector3.ONE]
	rows.append_array(HUES)

	var vp := SubViewport.new()
	vp.size = Vector2i(VALS.size() * CELL, rows.size() * CELL)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = float(rows.size())
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.position = Vector3(VALS.size() * 0.5, rows.size() * 0.5, 10.0)
	vp.add_child(cam)
	var sh := Shader.new()
	# `unshaded` writes ALBEDO straight to the HDR buffer and ignores EMISSION, so
	# the value under test goes in as ALBEDO. It is still tonemapped, which is the
	# only thing being measured here.
	sh.code = "shader_type spatial;\nrender_mode unshaded;\nuniform vec3 c;\nvoid fragment(){ ALBEDO = c; }"
	for r in rows.size():
		for i in VALS.size():
			var q := MeshInstance3D.new()
			var pm := PlaneMesh.new()
			pm.size = Vector2(1, 1)
			pm.orientation = PlaneMesh.FACE_Z
			q.mesh = pm
			q.position = Vector3(i + 0.5, r + 0.5, 0)
			var m := ShaderMaterial.new()
			m.shader = sh
			var h: Vector3 = rows[r]
			var v: float = VALS[i]
			m.set_shader_parameter("c", h * v)
			q.material_override = m
			vp.add_child(q)
	add_child(vp)
	for i in 10: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var got := vp.get_texture().get_image()

	var ref := Image.load_from_file(ProjectSettings.globalize_path("user://agx_blender.png"))
	print("###TABLE###")
	for r in rows.size():
		for i in VALS.size():
			# Both images are written top-down while the quads were placed bottom-up
			# in 3D, so row r of the layout is row (n-1-r) of both pictures.
			var y := (rows.size() - 1 - r) * CELL + CELL / 2
			var g := got.get_pixel(i * CELL + CELL / 2, y)
			var b := ref.get_pixel(i * CELL + CELL / 2, y) if ref != null else Color(0, 0, 0)
			print("%.6f %.6f %.6f" % [VALS[i], b.r, g.r])
	get_tree().quit()
