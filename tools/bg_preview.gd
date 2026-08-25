extends Node
# The shop card previews for the modelled backgrounds: BackgroundManager.make_preview
# at the real card size, laid out in a grid and saved, so the baked 3D stills can be
# checked the way a player sees them.
func _ready() -> void:
	for i in 40: await get_tree().process_frame
	var cols := 3
	var card := Vector2(300, 152)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.04, 0.03, 0.09)
	root.add_child(bg)
	var i := 0
	for id in BackgroundScenes.ORDER:
		var pv := BackgroundManager.make_preview(String(id), card)
		pv.position = Vector2(20 + (i % cols) * (card.x + 20),
			20 + int(i / cols) * (card.y + 40))
		root.add_child(pv)
		var lbl := Label.new()
		lbl.text = "%s  %d" % [CoinsManager.THEMES[id]["name"], CoinsManager.theme_price(id)]
		lbl.position = pv.position + Vector2(0, card.y + 4)
		root.add_child(lbl)
		i += 1
	for f in 120: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://bg_previews.png")
	print("shot previews")
	get_tree().quit()
