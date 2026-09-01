extends Node
# Does StandardMaterial3D carry an emission COLOUR above 1.0, and does
# EMISSION_OP_MULTIPLY fold ALBEDO (vertex colour included) into it?
# Both are load-bearing for lily_buttons.gd; neither is documented.
func _ready() -> void:
	for _i in 6: await get_tree().process_frame
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 16)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 0.40
	env.glow_enabled = false
	var we := WorldEnvironment.new(); we.environment = env
	vp.add_child(we)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.0
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.position = Vector3(2.0, 0.5, 10.0)
	vp.add_child(cam)

	# Four cells: emission colour 0.5 / 1.0 / 2.0 / 3.0 linear, ADD op, albedo black.
	# Then the same four with MULTIPLY and albedo 0.5.
	var cases := [
		["ADD  0.5", 0.5, BaseMaterial3D.EMISSION_OP_ADD, Color(0, 0, 0)],
		["ADD  1.0", 1.0, BaseMaterial3D.EMISSION_OP_ADD, Color(0, 0, 0)],
		["ADD  2.0", 2.0, BaseMaterial3D.EMISSION_OP_ADD, Color(0, 0, 0)],
		["ADD  3.0", 3.0, BaseMaterial3D.EMISSION_OP_ADD, Color(0, 0, 0)],
		["MUL  1.0 x a0.5", 1.0, BaseMaterial3D.EMISSION_OP_MULTIPLY, Color(0.5, 0.5, 0.5).linear_to_srgb()],
		["MUL  2.0 x a0.5", 2.0, BaseMaterial3D.EMISSION_OP_MULTIPLY, Color(0.5, 0.5, 0.5).linear_to_srgb()],
		["MUL  3.0 x a0.5", 3.0, BaseMaterial3D.EMISSION_OP_MULTIPLY, Color(0.5, 0.5, 0.5).linear_to_srgb()],
		["MUL  6.0 x a0.5", 6.0, BaseMaterial3D.EMISSION_OP_MULTIPLY, Color(0.5, 0.5, 0.5).linear_to_srgb()],
	]
	for i in cases.size():
		var q := MeshInstance3D.new()
		var pm := PlaneMesh.new(); pm.size = Vector2(1, 1); pm.orientation = PlaneMesh.FACE_Z
		q.mesh = pm
		q.position = Vector3(i * 0.5 + 0.25, 0.5, 0.0)
		q.scale = Vector3(0.5, 1.0, 1.0)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		m.disable_ambient_light = true
		m.albedo_color = cases[i][3]
		m.emission_enabled = true
		m.emission_operator = cases[i][2]
		m.emission = Color(cases[i][1], cases[i][1], cases[i][1]).linear_to_srgb()
		m.emission_energy_multiplier = 1.0
		q.material_override = m
		vp.add_child(q)
	add_child(vp)
	for _i in 8: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	print("--- emission probe (AgX @ 0.40; ramp: lin 0.5 -> 80, 1.0 -> 158, 2.0 -> 226, 3.0 -> 245) ---")
	for i in cases.size():
		var c := img.get_pixel(i * 8 + 4, 8)
		print("  %-18s -> %3d" % [cases[i][0], int(c.r * 255.0)])
	get_tree().quit()
