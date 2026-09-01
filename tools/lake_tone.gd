extends Node
# What linear radiance does the BOARD's own Environment turn into a given screen
# colour?
#
# The lake (lake_world.gd) is authored entirely in Godot rather than matched to a
# Blender render, so it has no reference image to sweep a gain against. What it has
# instead is a target: "this turquoise, on screen". Between the two sits the board's
# Environment — AgX at tonemap_exposure 0.40 — which is emphatically not a gamma
# curve: it crushes everything under ~0.15 linear to black and clips from ~9 up
# (see the ramp world_scenes.gd measured at exposure 1.0).
#
# So this measures the transfer once, at the exposure the board actually runs at,
# and fits its INVERSE as a cubic in log2 — the same shape world_scenes.gd's
# AGX_FIT uses, for the same reason (a cubic through log space is smooth, cheap in
# GLSL and behaves at the ends).
#
# Run WITHOUT --headless (the dummy driver never draws, so the readback hangs —
# see the headless-harness note in tools/lume_verify.gd):
#
#   Godot_..._console.exe --path . tools/lake_tone.tscn
#
# Paste the printed FIT line into lake_world.gd's TONE_FIT.

const EXPOSURE := 0.40          # MemoryGameUI._build_environment
const CELL := 8
# The screen range the fit is asked to be accurate over: counts 20 .. 245 of 255.
const FIT_LO := 20.0 / 255.0
const FIT_HI := 245.0 / 255.0

func _ready() -> void:
	for _i in 8:
		await get_tree().process_frame

	# log2-uniform ramp over the whole usable range of the transform.
	var vals: Array[float] = []
	for i in 96:
		vals.append(pow(2.0, -7.0 + 10.0 * float(i) / 95.0))

	var vp := SubViewport.new()
	vp.size = Vector2i(vals.size() * CELL, CELL)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = EXPOSURE
	env.glow_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.0
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.position = Vector3(vals.size() * 0.5, 0.5, 10.0)
	vp.add_child(cam)

	var sh := Shader.new()
	sh.code = "shader_type spatial;\nrender_mode unshaded;\nuniform vec3 c;\nvoid fragment(){ ALBEDO = c; }"
	for i in vals.size():
		var q := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(1, 1)
		pm.orientation = PlaneMesh.FACE_Z
		q.mesh = pm
		q.position = Vector3(i + 0.5, 0.5, 0.0)
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("c", Vector3.ONE * vals[i])
		q.material_override = m
		vp.add_child(q)

	add_child(vp)
	for _i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()

	# Measured pairs: (screen value in 0..1 sRGB, linear radiance in).
	var xs: Array[float] = []      # log2 of the SCREEN value
	var ys: Array[float] = []      # log2 of the LINEAR value that produced it
	print("--- Godot AgX @ exposure %.2f ---" % EXPOSURE)
	print("   linear     screen(0-255)")
	for i in vals.size():
		var c := img.get_pixel(i * CELL + CELL / 2, CELL / 2)
		print("  %9.5f      %5.1f" % [vals[i], c.r * 255.0])
		# Only the monotonic interior is usable: the crushed floor and the clipped
		# ceiling both map many linears onto one screen value and cannot be inverted.
		# The window is tighter than that at BOTH ends, and for the same reason in
		# each case: the screen value is 8-bit, so near the toe one count of
		# quantisation is a large fraction of the linear value behind it, and near
		# the shoulder a whole octave of linear light shares a count. Fitting over
		# the interval an artist actually authors in keeps the residual honest.
		if c.r >= FIT_LO and c.r <= FIT_HI:
			xs.append(log(c.r) / log(2.0))
			ys.append(log(vals[i]) / log(2.0))

	if xs.size() < 8:
		print("not enough usable samples (%d)" % xs.size())
		get_tree().quit()
		return

	# The curve is measured, monotonic and smooth, so the honest inverse is the
	# ramp itself read backwards rather than a polynomial through it. A cubic in
	# log2 (which is what world_scenes.gd's AGX_FIT is, and what the first version
	# of this probe printed) lands 8-9 counts out through the mid-tones: AgX's toe
	# and shoulder are not one smooth power law and a cubic has to average them.
	#
	# So: invert by interpolating the measured pairs at every 4th screen count, in
	# log2 of the linear value (which is where the samples are uniform), and print
	# that as a table lake_world.gd can lerp.
	var out := PackedStringArray()
	var lo_c := int(ceil(img.get_pixel(CELL / 2, CELL / 2).r * 255.0))
	for c8 in range(0, 260, 4):
		var target := minf(float(c8), 255.0) / 255.0
		var lin := 0.0
		if c8 <= lo_c:
			lin = 0.0
		else:
			for i in range(1, vals.size()):
				var a0 := img.get_pixel((i - 1) * CELL + CELL / 2, CELL / 2).r
				var a1 := img.get_pixel(i * CELL + CELL / 2, CELL / 2).r
				if a1 >= target and a0 < target and a1 > a0:
					var f := (target - a0) / (a1 - a0)
					lin = pow(2.0, lerp(log(vals[i - 1]) / log(2.0), log(vals[i]) / log(2.0), f))
					break
			if lin == 0.0:
				lin = vals[vals.size() - 1]     # past the shoulder: clipped white
		out.append("%.5f" % lin)
	print("")
	print("TONE_RAMP (linear radiance for screen counts 0, 4, 8 ... 256)")
	for r in range(0, out.size(), 8):
		print("\t" + ", ".join(Array(out.slice(r, r + 8))) + ",")
	get_tree().quit()
