extends Node
# The real shop screen on the SPECIAL SKINS tab, so the ROYAL CASINO card can be seen
# in the grid it actually ships in — beside Ice Kingdom and Magical Lake, which is the
# point: the tab has THREE theme-backed skins now and they have to read as a shelf
# rather than as three unrelated products that happen to share a row.
#
# Pass "-- owned" to see it after the claim (EQUIP), "-- equipped" to see it while
# worn (EQUIPPED); with neither, the wallet is empty and the card must read FREE.
#
#   Godot..._console.exe --path . res://tools/casino_shop.tscn [-- owned|equipped]
#
# Developer harness; not shipped.
const ShopScreen := preload("res://shop_screen.gd")

class StubManager extends Control:
	func show_home() -> void: pass
	func await_gl_stable() -> void: pass

func _ready() -> void:
	FirebaseManager.sign_in()
	FirebaseManager.set_display_name("Tester")
	for _i in 30: await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var doc := {"coins": 99999}
	if args.has("owned") or args.has("equipped"):
		doc["owned_themes"] = {"world_casino": true}
	if args.has("equipped"):
		doc["selected_theme"] = "world_casino"
	CoinsManager._apply_doc(doc)
	var stub := StubManager.new()
	stub.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(stub)
	var shop := ShopScreen.new()
	shop.game_manager = stub
	shop.set_anchors_preset(Control.PRESET_FULL_RECT)
	stub.add_child(shop)
	for _i in 300: await get_tree().process_frame
	shop._on_tab("skins")
	# Each card's preview is a baked still that renders a whole gameplay board in its
	# own viewport before it lands, and there are three of them now — so this wait is
	# not padding.
	for _i in 500: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var suffix := ""
	if args.has("owned"): suffix = "_owned"
	if args.has("equipped"): suffix = "_equipped"
	get_viewport().get_texture().get_image().save_png("res://shot_casino_shop%s.png" % suffix)
	print("shot res://shot_casino_shop%s.png" % suffix)
	get_tree().quit()
