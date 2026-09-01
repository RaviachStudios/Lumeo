extends Node
# The real shop screen, THEMES tab, scrolled to the two worlds — so the cards can
# be seen in the grid they actually ship in rather than only as bakes.
#
#   Godot..._console.exe --path . res://tools/world_shop.tscn
#
# Developer harness; not shipped.
const ShopScreen := preload("res://shop_screen.gd")

class StubManager extends Control:
	func show_home() -> void: pass
	func await_gl_stable() -> void: pass

func _ready() -> void:
	FirebaseManager.sign_in()
	FirebaseManager.set_display_name("Tester")
	for i in 30: await get_tree().process_frame
	CoinsManager._apply_doc({"coins": 99999, "owned_themes": {"world_forest": true},
		"selected_theme": "world_forest"})
	var stub := StubManager.new()
	stub.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(stub)
	var shop := ShopScreen.new()
	shop.game_manager = stub
	shop.set_anchors_preset(Control.PRESET_FULL_RECT)
	stub.add_child(shop)
	for i in 240: await get_tree().process_frame
	# Scroll to the end of the THEMES grid, where the worlds are. "-- top" instead
	# shows the head of the grid, where the priced Themes1 floors still are, and
	# "-- scroll:<px>" lands anywhere between the two — the LUMEO block starts in the
	# middle of the grid now that its two free worlds lead it.
	var to := 0 if OS.get_cmdline_user_args().has("top") else 100000
	for x in OS.get_cmdline_user_args():
		if String(x).begins_with("scroll:"):
			to = int(String(x).substr(7))
	for c in _scrolls(shop):
		c.scroll_vertical = to
	# Card previews are baked lazily as they scroll into view, and a LUMEO world's
	# bake renders a whole gameplay board in front of the scene — slow. 120 frames
	# was not enough and every card that had scrolled in showed the LAST texture the
	# grid had, which reads exactly like a preview-cache bug and is not one.
	for i in 600: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var suffix := "_top" if OS.get_cmdline_user_args().has("top") else ""
	for x in OS.get_cmdline_user_args():
		if String(x).begins_with("scroll:"):
			suffix = "_at%d" % to
	get_viewport().get_texture().get_image().save_png("user://world_shop%s.png" % suffix)
	print("shot %s" % ProjectSettings.globalize_path("user://world_shop%s.png" % suffix))
	get_tree().quit()

func _scrolls(n: Node) -> Array:
	var out := []
	if n is ScrollContainer:
		out.append(n)
	for c in n.get_children():
		out += _scrolls(c)
	return out
