extends Node
# The board's SubViewport sets msaa_3d = MSAA_DISABLED, justified in comment by
# "the board's silhouettes are all big discs, which is the case that needs it
# least". A snowflake with 48 thin arms and a lily pad with a scalloped rim and
# raised veins are not big discs. This renders both assets at their real gameplay
# pixel size with MSAA off and on, so the difference is a picture and a number.
#
#   Godot_..._console.exe --path . tools/pad_aa.tscn
const ASSETS := {
	"pad": "res://models/buttons/LilyPad_Purple.glb",
	"flake": "res://models/buttons/Ice_Snowflake_Violet.glb",
}
const N := 340        # about what one button spans on a 1280-wide gameplay frame

func _ready() -> void:
	for _i in 6: await get_tree().process_frame
	for tag: String in ASSETS:
		var off := await _shot(ASSETS[tag], "%s_aa_off" % tag, Viewport.MSAA_DISABLED)
		var on := await _shot(ASSETS[tag], "%s_aa_4x" % tag, Viewport.MSAA_4X)
		# How much of the frame actually differs, and by how much: an aliasing
		# difference is a thin, high-contrast set of pixels along every silhouette.
		var moved := 0
		var worst := 0.0
		for y in N:
			for x in N:
				var d: float = (Vector3(off.get_pixel(x, y).r, off.get_pixel(x, y).g, off.get_pixel(x, y).b)
					- Vector3(on.get_pixel(x, y).r, on.get_pixel(x, y).g, on.get_pixel(x, y).b)).length()
				if d > 0.02:
					moved += 1
				worst = maxf(worst, d)
		print("  %-6s  %d px differ (%.1f%% of frame), worst delta %.3f"
			% [tag, moved, 100.0 * float(moved) / float(N * N), worst])
	get_tree().quit()

func _shot(src: String, tag: String, msaa: int) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(N, N)
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.msaa_3d = msaa as Viewport.MSAA
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.05, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 0.60
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42.0, -34.0, 0.0)
	key.light_energy = 1.6
	vp.add_child(key)

	var cam := Camera3D.new()
	cam.fov = 43.44
	var e := deg_to_rad(33.51)
	cam.look_at_from_position(Vector3(0, 0.17, 0) + Vector3(0.0, sin(e), cos(e)) * 3.0,
		Vector3(0, 0.17, 0), Vector3.UP)
	vp.add_child(cam)

	var root := (load(src) as PackedScene).instantiate()
	_colour(root)
	vp.add_child(root)
	add_child(vp)
	for _i in 6: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.save_png("res://aa_%s.png" % tag)
	vp.queue_free()
	await get_tree().process_frame
	return img

# Both assets bake their shading into COLOR_0, which the glTF importer does not
# switch on. Without this the comparison is between two flat slabs.
func _colour(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var m := (mi.mesh.surface_get_material(s) as StandardMaterial3D)
			if m == null:
				continue
			var d := m.duplicate() as StandardMaterial3D
			d.vertex_color_use_as_albedo = true
			mi.set_surface_override_material(s, d)
	for c in n.get_children():
		_colour(c)
