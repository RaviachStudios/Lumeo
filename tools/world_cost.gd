extends Node
# What a world actually costs on the board, measured rather than assumed: average
# and worst frame time over a few hundred frames with the board redrawing every
# frame (UPDATE_ALWAYS), which is the most expensive state gameplay ever puts it
# in — during a sequence flash. Between flashes the board runs at
# WorldScenes.IDLE_HZ instead, i.e. half of this at 60 fps.
#
#   Godot..._console.exe --path . res://tools/world_cost.tscn -- [id ...]
#
# "none" is the same board with no 3D background at all — the baseline every
# number here should be read against. Run WITHOUT --headless.
const Hard := preload("res://hard_game_ui.gd")
const FRAMES := 240

func _ready() -> void:
	# Without this every number is 16.6 ms and the measurement is of vsync.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	for i in 40: await get_tree().process_frame
	CoinsManager.simon_mode = CoinsManager.SIMON_MODE_MANUAL
	CoinsManager.selected_skin = ""
	var args := OS.get_cmdline_user_args()
	var ids: Array = args if args.size() > 0 else (["none", "bg_neongrid"] as Array) + WorldScenes.ORDER
	print("background      lights  avg ms   p95 ms   worst ms")
	for idv in ids:
		var id := String(idv)
		CoinsManager.selected_theme = "default" if id == "none" else id
		var dev := Hard.new()
		dev.input_enabled = false
		dev.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(dev)
		dev.configure(6, [])
		for i in 60: await get_tree().process_frame
		dev._vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var lights := _count_lights(dev._bg_scene) if dev._bg_scene != null else 0
		var t := []
		for i in FRAMES:
			var t0 := Time.get_ticks_usec()
			await RenderingServer.frame_post_draw
			t.append(float(Time.get_ticks_usec() - t0) / 1000.0)
		t.sort()
		var sum := 0.0
		for v in t: sum += v
		print("%-14s %6d  %6.2f   %6.2f   %6.2f" % [id, lights, sum / float(t.size()),
			t[int(t.size() * 0.95)], t[t.size() - 1]])
		dev.queue_free()
		await get_tree().process_frame
	get_tree().quit()

func _count_lights(n: Node) -> int:
	var c := 1 if n is Light3D else 0
	for ch in n.get_children():
		c += _count_lights(ch)
	return c
