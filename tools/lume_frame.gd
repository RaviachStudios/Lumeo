extends Node
# What ground the fitted gameplay camera sees, per difficulty and per aspect, in
# GODOT coordinates (x right, z toward the camera). Used to size the LumeScenes
# ring compositions so nothing they stand up is ever cut by the frame and nothing
# they clear in the middle is ever invaded by a button.
const Easy := preload("res://easy_game_ui.gd")
const Medium := preload("res://memory_game_ui.gd")
const Hard := preload("res://hard_game_ui.gd")

const SIZES := [Vector2i(1280, 720), Vector2i(1024, 768), Vector2i(2400, 1080)]

func _ready() -> void:
	for i in 40: await get_tree().process_frame
	CoinsManager.simon_mode = CoinsManager.SIMON_MODE_MANUAL
	CoinsManager.selected_theme = "bg_neongrid"
	for size in SIZES:
		get_window().size = size
		await get_tree().process_frame
		await get_tree().process_frame
		print("\n=== viewport %s (aspect %.3f) ===" % [str(size), float(size.x) / float(size.y)])
		for board in ["easy", "moderate", "hard"]:
			var dev: Control = (Easy.new() if board == "easy"
				else (Hard.new() if board == "hard" else Medium.new()))
			dev.input_enabled = false
			dev.set_anchors_preset(Control.PRESET_FULL_RECT)
			add_child(dev)
			dev.configure(dev._count, [])
			for i in 30: await get_tree().process_frame
			var cam: Camera3D = dev._cam
			var vp := Vector2(dev._vp.size)
			var tl := _g(cam, Vector2(1, 1))
			var tr := _g(cam, Vector2(vp.x - 1, 1))
			var bl := _g(cam, Vector2(1, vp.y - 1))
			var br := _g(cam, Vector2(vp.x - 1, vp.y - 1))
			var tc := _g(cam, Vector2(vp.x * 0.5, 1))
			var bc := _g(cam, Vector2(vp.x * 0.5, vp.y - 1))
			print("%-9s vp=%s cam=%s reach=%.2f" % [board, str(vp), str(cam.global_position.snapped(Vector3(0.01,0.01,0.01))), dev._board_reach()])
			print("           far  z=%+7.2f   x %+7.2f .. %+7.2f   (top centre z=%+.2f)" % [maxf(tl.y, tr.y) if false else tl.y, tl.x, tr.x, tc.y])
			print("           near z=%+7.2f   x %+7.2f .. %+7.2f   (bot centre z=%+.2f)" % [bl.y, bl.x, br.x, bc.y])
			# Where a point at ground radius R would land on screen, for a few R.
			var line := "           horizon-safe: "
			for r in [6.0, 8.0, 10.0, 14.0]:
				var s := cam.unproject_position(Vector3(0.0, 0.0, -r))
				line += "z=-%.0f -> v=%.2f  " % [r, s.y / vp.y]
			print(line)
			# How high a prop at z=-R may be before its top leaves the frame.
			var line2 := "           top-clip h: "
			for r in [6.0, 8.0, 10.0, 14.0]:
				var h := _max_h(cam, -r)
				line2 += "z=-%.0f -> %.2fm  " % [r, h]
			print(line2)
			dev.queue_free()
			await get_tree().process_frame
	get_tree().quit()

# Ground hit of the ray through px, as (x, z).
func _g(cam: Camera3D, px: Vector2) -> Vector2:
	var o := cam.project_ray_origin(px)
	var d := cam.project_ray_normal(px)
	if absf(d.y) < 0.0001: return Vector2(999, 999)
	var p := o + d * (-o.y / d.y)
	return Vector2(p.x, p.z)

# Tallest a vertical prop standing at (0,0,z) may be before its top crosses the
# top edge of the frame.
func _max_h(cam: Camera3D, z: float) -> float:
	var lo := 0.0
	var hi := 30.0
	for i in 40:
		var mid := (lo + hi) * 0.5
		if cam.unproject_position(Vector3(0.0, mid, z)).y > 0.0:
			lo = mid
		else:
			hi = mid
	return lo
