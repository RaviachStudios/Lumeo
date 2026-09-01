extends Node
# Renders each Themes2 world through the EXACT camera it was composed against —
# LUME_Gameplay_Camera, at the reference's own 1920x1080 — with no board in front
# of it, so the Godot image can be compared with renders/lume_<name>.png on
# materials and lighting alone, with framing taken out of the question.
#
#   Godot..._console.exe --path . res://tools/world_ref.tscn -- [id ...]
#
# Writes user://wref_<id>.png. Run WITHOUT --headless.

const W := 1920
const H := 1080

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var ids: Array = []
	for a in args:
		if not String(a).begins_with("hide:") and String(a) != "nolight":
			ids.append(a)
	if ids.is_empty():
		ids = WorldScenes.ORDER
	for i in 20: await get_tree().process_frame
	for idv in ids:
		var id := String(idv)
		var scene := WorldScenes.build(id)
		if scene == null:
			print("MISSING ", id)
			continue
		var vp := SubViewport.new()
		vp.size = Vector2i(W, H)
		vp.transparent_bg = false
		vp.own_world_3d = true
		vp.msaa_3d = Viewport.MSAA_DISABLED
		vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.add_child(WorldScenes.make_preview_environment(WorldScenes.world_of(id)))
		vp.add_child(WorldScenes.make_preview_camera(float(W) / float(H)))
		# Optional diagnostic: "-- <id> hide:<substr>,<substr>" drops matching meshes
		# from the render, which is how a stray bright element gets identified.
		if _flag("nolight"):
			for l in _find_lights(scene.get_parent() if scene.get_parent() else scene):
				l.light_energy = 0.0
		for h in _hide_list():
			for m in _find_all(scene, h):
				m.visible = false
		vp.add_child(scene)
		add_child(vp)
		for i in 20: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var p := "user://wref_%s%s.png" % [id, "_diag" if (_hide_list().size() > 0 or _flag("nolight")) else ""]
		vp.get_texture().get_image().save_png(p)
		print("shot %s" % ProjectSettings.globalize_path(p))
		vp.queue_free()
		await get_tree().process_frame
	get_tree().quit()

func _flag(f: String) -> bool:
	for a in OS.get_cmdline_user_args():
		if String(a) == f:
			return true
	return false

func _find_lights(n: Node) -> Array:
	var out := []
	if n is Light3D:
		out.append(n)
	for c in n.get_children():
		out += _find_lights(c)
	return out

func _hide_list() -> Array:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("hide:"):
			return String(a).substr(5).split(",")
	return []

func _find_all(n: Node, sub: String) -> Array:
	var out := []
	if n is MeshInstance3D and String(n.name).findn(sub) >= 0:
		out.append(n)
	for c in n.get_children():
		out += _find_all(c, sub)
	return out
