extends Node
# Renders each Themes2 world's SHOP CARD at the real card size, through the real
# path (BackgroundManager.make_preview), and saves it — so what the grid will show
# can be looked at without opening the shop.
#
#   Godot..._console.exe --path . res://tools/world_card.tscn -- [id ...]
const CARD := Vector2(300, 152)

func _ready() -> void:
	for i in 40: await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var ids: Array = args if args.size() > 0 else WorldScenes.ORDER
	var strip := Image.create(int(CARD.x), int(CARD.y) * ids.size(), false, Image.FORMAT_RGBA8)
	for i in ids.size():
		var id := String(ids[i])
		var tex: ImageTexture = await BackgroundManager._render_scene_plate(id, CARD)
		if tex == null:
			print("MISSING ", id)
			continue
		var img := tex.get_image()
		img.convert(Image.FORMAT_RGBA8)
		strip.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()),
			Vector2i(0, int(CARD.y) * i))
		print("card %s %dx%d" % [id, img.get_width(), img.get_height()])
	strip.save_png("user://world_cards.png")
	print("strip %s" % ProjectSettings.globalize_path("user://world_cards.png"))
	get_tree().quit()
