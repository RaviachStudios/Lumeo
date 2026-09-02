extends Node
# Screenshot harness for the ICE KINGDOM snowflake buttons, modelled on
# tools/hgui_shot.gd. Renders the six-button Hard board wearing the ice skin at
# the Blender reference's own resolution over the same near-black plate, so the
# result can be put beside
# "APP IDEAS/Simon/IceButtons/renders/ice_v8_gameplay.png".
#
# This is the check Blender cannot make: Godot's AgX is not Blender's AgX (see the
# ramp in world_scenes.gd), and the board's studio is deliberately almost black,
# so an ice material that reads beautifully in EEVEE can still crush or blow out
# here. Run WITHOUT --headless (the dummy renderer has no framebuffer to read):
#
#   Godot_..._console.exe --path . tools/ice_buttons_shot.tscn

const ICE := preload("res://ice_buttons.gd")
const SHOT_W := 1920
const SHOT_H := 1080
const ORDER := ["Crimson", "Jade", "Cyan", "Amber", "Violet", "Magenta"]

var _dev: HardGameUI
var _vp: SubViewport
var _dev_vp: SubViewport
var _cam: Camera3D
var _board: Node3D
var _ap: AnimationPlayer

func _ready() -> void:
	for _i in 8:
		await get_tree().process_frame     # let CoinsManager load the wallet
	CoinsManager.selected_theme = ICE.THEME_ID

	_vp = SubViewport.new()
	_vp.size = Vector2i(SHOT_W, SHOT_H)
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_2d = Viewport.MSAA_DISABLED
	add_child(_vp)
	var bg := ColorRect.new()
	bg.color = Color8(4, 5, 7)
	bg.size = Vector2(SHOT_W, SHOT_H)
	_vp.add_child(bg)

	_dev = HardGameUI.new()
	_dev.input_enabled = false
	_dev.size = Vector2(SHOT_W, SHOT_H)
	_vp.add_child(_dev)
	await get_tree().process_frame
	_dev.configure(6, [])
	_dev.set_level(12)

	for c in _dev.get_children():
		if c is SubViewportContainer:
			_dev_vp = (c as SubViewportContainer).get_child(0) as SubViewport
	for c in _dev_vp.get_children():
		if c is Camera3D:
			_cam = c
	_board = _dev.find_child("MemoryGame_UI", true, false) as Node3D
	_ap = _dev.find_child("AnimationPlayer", true, false) as AnimationPlayer
	print("ice skin worn: %s" % (_dev.button_skin_id() == ICE.THEME_ID))

	await _settle(30)
	await _save("user://ice_idle.png")
	_report()

	_dev.set_lit(5, true)
	await _settle(40)
	await _save("user://ice_hl_magenta.png")
	_dev.set_lit(5, false)
	await _settle(40)

	_dev.set_press(5, 1.0)
	await _settle(30)
	if _ap:
		_ap.seek(0.09, true)
	await _settle(6)
	await _save("user://ice_press_magenta.png")
	_dev.set_press(5, 0.0)
	await _settle(40)

	# and the stock board, from the same rig, for a like-for-like comparison
	CoinsManager.selected_theme = "default"
	_dev._on_background_changed()
	await _settle(40)
	await _save("user://ice_off_stock.png")
	get_tree().quit()

func _settle(n: int) -> void:
	_dev.set_process(true)
	if _dev_vp:
		_dev_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for _i in n:
		await get_tree().process_frame

func _report() -> void:
	var img := _vp.get_texture().get_image()
	print("--- rendered flake tops (hub centre, y 0.525) ---")
	for key: String in ORDER:
		var holder := _board.find_child("Button_%s" % key, true, false) as Node3D
		var s := _cam.unproject_position(holder.position + Vector3(0.0, 0.525, 0.0))
		var c := img.get_pixel(int(s.x), int(s.y))
		print("  %-8s (%3d,%3d,%3d)" % [key, int(c.r * 255.0), int(c.g * 255.0), int(c.b * 255.0)])

func _save(path: String) -> void:
	_dev.set_process(false)
	if _dev_vp:
		_dev_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for _i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_vp.get_texture().get_image().save_png(path)
	print("shot  %s" % ProjectSettings.globalize_path(path))
