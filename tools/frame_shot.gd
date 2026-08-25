extends Node
# Screenshot harness for the button-frame cosmetics (companion to mgui_shot). Renders the Medium
# board wearing every catalog entry — the sixteen shop frames AND the three skin-bound
# ones — plus the shop's BUTTON FRAMES tab.
# Run WITHOUT --headless:  godot --path . tools/frame_shot.tscn

const SHOT_W := 1280
const SHOT_H := 720

var _vp: SubViewport
var _dev: MemoryGameUI
var _dev_vp: SubViewport

func _ready() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(SHOT_W, SHOT_H)
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_2d = Viewport.MSAA_DISABLED
	add_child(_vp)

	var bg := ColorRect.new()
	bg.color = Color8(8, 16, 40)
	bg.size = Vector2(SHOT_W, SHOT_H)
	_vp.add_child(bg)

	_dev = MemoryGameUI.new()
	_dev.input_enabled = false
	_dev.size = Vector2(SHOT_W, SHOT_H)
	_vp.add_child(_dev)
	await get_tree().process_frame
	_dev.configure(5, [])
	_dev.set_round_number(7)
	for c in _dev.get_children():
		if c is SubViewportContainer:
			_dev_vp = (c as SubViewportContainer).get_child(0) as SubViewport

	var every: Array = ButtonFrames.ORDER.duplicate()
	for sid: String in ButtonFrames.SKIN_FRAMES.keys():
		every.append(String(ButtonFrames.SKIN_FRAMES[sid]))
	for fid: String in every:
		_dev.apply_button_frame(fid)
		await _settle(24)
		await _save("user://frame_%s.png" % fid)

	# One shot with a button lit + one pressed, on the tiger frame, to prove the
	# cosmetic doesn't disturb the surface emission or the press clip.
	_dev.apply_button_frame("tiger_glow")
	_dev.set_lit(2, true)
	_dev.set_press(0, 1.0)
	await _settle(30)
	await _save("user://frame_tiger_active.png")

	_dev.queue_free()
	await get_tree().process_frame
	await _shop()
	get_tree().quit()

func _shop() -> void:
	var shop: Control = load("res://shop_screen.gd").new()
	shop.game_manager = null
	shop.size = Vector2(SHOT_W, SHOT_H)
	_vp.add_child(shop)
	for _i in 240:
		await get_tree().process_frame
	await _save("user://shop_themes.png")
	shop.call("_on_tab", "skins")
	for _i in 60:
		await get_tree().process_frame
	await _save("user://shop_skins.png")
	shop.call("_on_tab", "frames")
	for _i in 120:
		await get_tree().process_frame
	await _save("user://shop_frames.png")
	# ...and the second row, which only exists now that there are sixteen cards.
	(shop.get("_frames_root") as ScrollContainer).scroll_vertical = 342
	for _i in 30:
		await get_tree().process_frame
	await _save("user://shop_frames_row2.png")
	# The confirm dialog for a free unlock — the price must read 0.
	shop.call("_on_frame_action", "tiger_glow")
	for _i in 60:
		await get_tree().process_frame
	await _save("user://shop_frame_confirm.png")

func _settle(n: int) -> void:
	_dev.set_process(true)
	if _dev_vp:
		_dev_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for _i in n:
		await get_tree().process_frame

func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	img.save_png(path)
	print("saved ", ProjectSettings.globalize_path(path))
