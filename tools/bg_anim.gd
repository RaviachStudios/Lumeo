extends Node
# Does the animation actually run, and is it subtle enough? Renders each
# background at three moments a few seconds apart and reports how much the image
# moved — mean absolute difference over the whole frame, and the largest single
# pixel change. Zero means nothing is animating; a large number means it is
# distracting.
const Hard := preload("res://hard_game_ui.gd")
const GAP := 2.5

func _ready() -> void:
	for i in 40: await get_tree().process_frame
	CoinsManager.simon_mode = CoinsManager.SIMON_MODE_MANUAL
	CoinsManager.selected_skin = ""
	print("background      animated  mean|d|  max|d|   (sRGB 0-255, over %.1fs)" % (GAP * 2.0))
	for id in BackgroundScenes.ORDER:
		CoinsManager.selected_theme = String(id)
		var dev := Hard.new(); dev.input_enabled = false
		dev.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(dev); dev.configure(6, [])
		for i in 70: await get_tree().process_frame
		var shots := []
		for k in 3:
			if k > 0:
				await get_tree().create_timer(GAP).timeout
			dev._kick_render()
			await RenderingServer.frame_post_draw
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			shots.append(get_viewport().get_texture().get_image())
		var mean := 0.0
		var mx := 0.0
		var n := 0
		var a: Image = shots[0]
		var b: Image = shots[2]
		var y := 0
		while y < a.get_height():
			var x := 0
			while x < a.get_width():
				var p := a.get_pixel(x, y)
				var q := b.get_pixel(x, y)
				var d := (absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b)) / 3.0 * 255.0
				mean += d
				mx = maxf(mx, d)
				n += 1
				x += 3
			y += 3
		print("%-14s %-9s %6.2f  %6.1f" % [id,
			str(BackgroundScenes.is_animated(String(id))), mean / float(n), mx])
		dev.queue_free()
		await get_tree().process_frame
	get_tree().quit()
