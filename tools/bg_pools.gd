extends Node
# How much of the remaining Godot-vs-Blender gap is the board's own ground pools —
# the coloured light the buttons cast on the table, which is existing tuned
# behaviour and not part of the background import. Renders each background twice,
# with the pool plate shown and hidden.
const Hard := preload("res://hard_game_ui.gd")
func _ready() -> void:
	for i in 40: await get_tree().process_frame
	CoinsManager.simon_mode = CoinsManager.SIMON_MODE_MANUAL
	CoinsManager.selected_skin = ""
	for id in BackgroundScenes.ORDER:
		CoinsManager.selected_theme = String(id)
		var means := []
		for pools in [true, false]:
			var dev := Hard.new(); dev.input_enabled = false
			dev.set_anchors_preset(Control.PRESET_FULL_RECT)
			add_child(dev); dev.configure(6, [])
			for i in 70: await get_tree().process_frame
			if not pools:
				var g := dev._vp.find_child("GroundGlow", true, false)
				if g: g.visible = false
			dev._kick_render()
			await RenderingServer.frame_post_draw
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			means.append(_bg_mean(get_viewport().get_texture().get_image()))
			dev.queue_free()
			await get_tree().process_frame
		var a: Vector3 = means[0]
		var b: Vector3 = means[1]
		print("%-14s with %5.1f %5.1f %5.1f   without %5.1f %5.1f %5.1f   pools contribute %+5.1f %+5.1f %+5.1f" % [
			id, a.x, a.y, a.z, b.x, b.y, b.z, a.x - b.x, a.y - b.y, a.z - b.z])
	get_tree().quit()

# The same cells bg_compare calls background (buttons excluded), same 8x5 grid.
func _bg_mean(img: Image) -> Vector3:
	const BTN := [Vector2i(2,1),Vector2i(3,1),Vector2i(4,1),Vector2i(5,1),
		Vector2i(1,2),Vector2i(2,2),Vector2i(3,2),Vector2i(4,2),Vector2i(5,2),Vector2i(6,2),
		Vector2i(2,3),Vector2i(3,3),Vector2i(4,3),Vector2i(5,3)]
	var acc := Vector3.ZERO
	var n := 0
	for r in 5:
		for c in 8:
			if BTN.has(Vector2i(c, r)): continue
			var x0 := int(float(c) / 8.0 * img.get_width())
			var x1 := int(float(c + 1) / 8.0 * img.get_width())
			var y0 := int(float(r) / 5.0 * img.get_height())
			var y1 := int(float(r + 1) / 5.0 * img.get_height())
			var y := y0
			while y < y1:
				var x := x0
				while x < x1:
					var p := img.get_pixel(x, y)
					acc += Vector3(p.r, p.g, p.b); n += 1
					x += 6
				y += 6
	return acc / maxf(float(n), 1.0) * 255.0
