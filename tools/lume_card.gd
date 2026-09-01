extends Node
# Contact sheet of the eight LUMEO worlds' SHOP CARDS: the exact texture
# BackgroundManager bakes for a THEMES-tab tile, laid out as the grid shows them.
#
#   Godot..._console.exe --path . res://tools/lume_card.tscn

const LumeWorlds := preload("res://lume_worlds.gd")
const CARD := Vector2(300, 152)
const COLS := 3
const PAD := 14

func _ready() -> void:
	for i in 30:
		await get_tree().process_frame
	var rows := int(ceil(float(LumeWorlds.ORDER.size()) / float(COLS)))
	var sheet := Image.create(int(COLS * (CARD.x + PAD) + PAD),
		int(rows * (CARD.y + PAD) + PAD), false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.05, 0.04, 0.09))
	for i in LumeWorlds.ORDER.size():
		var id := String(LumeWorlds.ORDER[i])
		var tex: ImageTexture = await BackgroundManager._render_scene_plate(id, CARD)
		if tex == null:
			print("MISSING  %s" % id)
			continue
		var img := tex.get_image()
		img.convert(Image.FORMAT_RGBA8)
		var at := Vector2i(PAD + (i % COLS) * int(CARD.x + PAD), PAD + int(i / COLS) * int(CARD.y + PAD))
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), at)
		print("card  %-16s %s" % [id, str(img.get_size())])
	sheet.save_png("user://lume_cards.png")
	print("sheet  %s" % ProjectSettings.globalize_path("user://lume_cards.png"))
	get_tree().quit()
