extends Node
# Contact sheet for the button-frame cosmetics: all eighteen frames worn on a
# neutral stand-in button, in ONE render, under the BOARD'S OWN studio (same
# Environment, same two lights, same AgX exposure as MemoryGameUI) and through
# ButtonFrames' own materials.
#
# It exists to be compared side by side with the asset's Blender showcase
# (RingCustomize/Button_Frame_Cosmetics_Showcase.png), which is rendered in a
# five-light presentation room. Where this sheet is darker than that one, it is
# the studio, not the asset — see the painted-environment note in button_frames.gd.
#
# Run WITHOUT --headless:  godot --path . tools/frame_sheet.tscn

const W := 1920
const H := 1080
const COLS := 6
const ROWS := 3
const CELL := 2.55        # world units between cells

func _ready() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	_studio(vp)

	var ids: Array = ButtonFrames.ORDER.filter(func(i: String) -> bool:
		return ButtonFrames.is_cosmetic(i))
	for sid: String in ["arcade", "casino", "lunapark"]:
		ids.append(ButtonFrames.frame_for_skin(sid))

	for i in ids.size():
		var col := i % COLS
		var row := i / COLS
		var at := Vector3((float(col) - (COLS - 1) * 0.5) * CELL,
			0.0, (float(row) - (ROWS - 1) * 0.5) * CELL * 1.45)
		_cell(vp, String(ids[i]), at)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = (float(COLS) * CELL + 0.7) * float(H) / float(W)
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.near = 0.05
	cam.far = 100.0
	var e := deg_to_rad(33.9)                   # the board's own elevation
	cam.look_at_from_position(Vector3(0.0, sin(e), cos(e)) * 20.0, Vector3.ZERO, Vector3.UP)
	vp.add_child(cam)

	for _i in 30:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.save_png("user://frame_sheet.png")
	print("sheet  %s" % ProjectSettings.globalize_path("user://frame_sheet.png"))
	# Numbers, not impressions: per cell, how bright the ring actually gets and
	# whether anything is clipping. The asset's own showcase reports 0 fully-clipped
	# pixels and a max channel of 0.996, so that is the bar.
	for i in ids.size():
		var col := i % COLS
		var row := i / COLS
		var cw := W / COLS
		var ch := H / ROWS
		var r := Rect2i(col * cw, row * ch, cw, ch)
		var clipped := 0
		var mx := 0.0
		var lit := 0
		var sum := Vector3.ZERO
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var c := img.get_pixel(x, y)
				var m: float = maxf(c.r, maxf(c.g, c.b))
				if m >= 0.997:
					clipped += 1
				mx = maxf(mx, m)
				if m > 0.30:
					lit += 1
					sum += Vector3(c.r, c.g, c.b)
		var mean := (sum / maxf(float(lit), 1.0)) * 255.0
		print("  %-16s max=%.3f clipped=%-5d lit=%-6d mean_lit=(%3.0f,%3.0f,%3.0f)" % [
			ids[i], mx, clipped, lit, mean.x, mean.y, mean.z])
	get_tree().quit()

# One cell: a neutral stand-in button (the showcase's own idea) wearing the frame.
func _cell(vp: SubViewport, id: String, at: Vector3) -> void:
	var holder := Node3D.new()
	holder.position = at
	vp.add_child(holder)

	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.745
	cyl.bottom_radius = 0.745
	cyl.height = 0.28
	cyl.radial_segments = 64
	body.mesh = cyl
	var m := StandardMaterial3D.new()
	# The showcase's neutral stand-in. It carries its own light for the same reason
	# the board's buttons do — so the ring is judged against something, not a void.
	m.albedo_color = Color(0.62, 0.62, 0.64)
	m.metallic = 0.0
	m.roughness = 0.42
	m.emission_enabled = true
	m.emission = Color(0.62, 0.62, 0.64)
	m.emission_energy_multiplier = 0.55
	body.mesh.surface_set_material(0, m)
	body.position = Vector3(0.0, 0.385, 0.0)
	holder.add_child(body)

	var frame := ButtonFrames.make_frame_instance(id)
	if frame != null:
		holder.add_child(frame)

func _studio(vp: SubViewport) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.055, 0.075, 0.115)
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.56, 0.60, 0.70)
	sky_mat.sky_horizon_color = Color(0.26, 0.28, 0.33)
	sky_mat.ground_horizon_color = Color(0.14, 0.15, 0.18)
	sky_mat.ground_bottom_color = Color(0.04, 0.04, 0.05)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 1.0, 1.0)
	env.ambient_light_energy = 0.13
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 0.40
	env.glow_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42.0, -34.0, 0.0)
	key.light_energy = 0.14
	key.light_specular = 1.5
	key.light_color = Color(1.0, 0.99, 0.97)
	vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-16.0, 158.0, 0.0)
	fill.light_energy = 0.05
	fill.light_specular = 1.2
	fill.light_color = Color(0.80, 0.86, 1.0)
	vp.add_child(fill)
