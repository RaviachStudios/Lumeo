extends Node
# What ground the fitted gameplay camera actually sees, per difficulty, against
# the Blender composition contract (bottom edge y=-3.34, top edge y=+6.43, in
# Blender coordinates; Godot z = -y).
const Easy := preload("res://easy_game_ui.gd")
const Medium := preload("res://memory_game_ui.gd")
const Hard := preload("res://hard_game_ui.gd")

func _ready() -> void:
	for i in 40: await get_tree().process_frame
	CoinsManager.simon_mode = CoinsManager.SIMON_MODE_MANUAL
	CoinsManager.selected_theme = "bg_neongrid"
	print("board    cam_pos                 bottom_y  top_y   (blender)  ref: -3.34 / +6.43")
	for board in ["easy", "moderate", "hard"]:
		var dev: Control = (Easy.new() if board == "easy"
			else (Hard.new() if board == "hard" else Medium.new()))
		dev.input_enabled = false
		dev.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(dev)
		dev.configure(dev._count, [])
		for i in 40: await get_tree().process_frame
		var cam: Camera3D = dev._cam
		var vp := Vector2(dev._vp.size)
		var bot := _ground(cam, Vector2(vp.x * 0.5, vp.y - 1.0))
		var top := _ground(cam, Vector2(vp.x * 0.5, 1.0))
		print("%-9s %-22s  %+7.2f  %+7.2f   vp=%s" % [board,
			str(cam.global_position.round()), -bot, -top, vp])
		dev.queue_free()
		await get_tree().process_frame
	get_tree().quit()

# Where the ray through `px` meets y = 0, returned as Godot z.
func _ground(cam: Camera3D, px: Vector2) -> float:
	var o := cam.project_ray_origin(px)
	var d := cam.project_ray_normal(px)
	if absf(d.y) < 0.0001: return 999.0
	return (o + d * (-o.y / d.y)).z
