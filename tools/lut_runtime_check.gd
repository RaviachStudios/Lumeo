extends Control

# End-to-end check of the live path: BackgroundManager bakes the field in _ready,
# _show_live binds it, and the theme paints. Saves what the screen actually shows.

func _ready() -> void:
	_run()

func _run() -> void:
	# Real boot order: the save loads and the field bakes before any theme is equipped.
	await BackgroundManager._ensure_noise_lut()
	for theme in ["inferno", "skybound"]:
		CoinsManager.selected_theme = theme
		CoinsManager.simon_mode = CoinsManager.SIMON_MODE_MANUAL
		BackgroundManager.set_active(false)
		BackgroundManager.set_active(true)
		for i in 20:
			await RenderingServer.frame_post_draw
		var lut: Variant = BackgroundManager._noise_lut
		var bound: Variant = BackgroundManager._mat.get_shader_parameter("noise_tex")
		var img := get_viewport().get_texture().get_image()
		# Is anything actually painted? A black screen means the binding failed.
		var lum := 0.0
		for y in range(0, img.get_height(), 8):
			for x in range(0, img.get_width(), 8):
				var c := img.get_pixel(x, y)
				lum += (c.r + c.g + c.b) / 3.0
		lum /= float((img.get_height() / 8) * (img.get_width() / 8))
		print("%-9s render_mode=%s  lut=%s  bound=%s  mean_screen_luma=%.3f" %
			[theme, BackgroundManager._render_mode,
			 "null" if lut == null else "ok", "null" if bound == null else "ok", lum])
		img.save_png("user://live_%s.png" % theme)
	print("DONE")
	get_tree().quit()
