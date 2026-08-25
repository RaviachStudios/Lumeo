extends Node
# Screenshot + measurement harness for hard_game_ui.gd, modelled on tools/mgui_shot.gd.
# Renders the six-button board at the Blender reference's exact resolution over the
# same near-black plate, so the result can be compared against
# "APP IDEAS/Simon/HardV3/MemoryGame_UI_Hard_idle.png" and ..._press_magenta.png.
# Run WITHOUT --headless (the dummy renderer has no framebuffer to read back):
#
#   Godot_..._console.exe --path . tools/hgui_shot.tscn
#
# Saves idle, one highlighted, one pressed, and one wearing a shop frame.

const SHOT_W := 1920
const SHOT_H := 1080

# The reference render's own button tops, measured off
# HardV3/MemoryGame_UI_Hard_idle.png at each button's centre.
const REF := {
	"Crimson": Vector3(100, 4, 51),
	"Jade": Vector3(34, 147, 119),
	"Cyan": Vector3(97, 169, 171),
	"Amber": Vector3(178, 134, 69),
	"Violet": Vector3(88, 83, 188),
	"Magenta": Vector3(179, 60, 137),
}
const ORDER := ["Crimson", "Jade", "Cyan", "Amber", "Violet", "Magenta"]

var _dev: HardGameUI
var _vp: SubViewport
var _dev_vp: SubViewport
var _cam: Camera3D
var _board: Node3D
var _ap: AnimationPlayer

func _ready() -> void:
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

	await _settle(30)
	await _save("user://hgui_idle.png")
	_report()

	_dev.set_lit(5, true)                 # magenta, as the sequence plays it
	await _settle(40)
	await _save("user://hgui_hl_magenta.png")
	_dev.set_lit(5, false)
	await _settle(40)

	# Magenta at the bottom of its press stroke (the clip holds 0.067..0.133s),
	# which is the pose the reference's press render captures.
	_dev.set_press(5, 1.0)
	await _settle(30)
	if _ap:
		_ap.seek(0.09, true)
	await _settle(6)
	await _save("user://hgui_press_magenta.png")
	_press_report()
	_dev.set_press(5, 0.0)
	await _settle(40)

	_dev.apply_button_frame("tiger_glow")
	await _settle(30)
	await _save("user://hgui_frame_tiger.png")

	get_tree().quit()

func _settle(n: int) -> void:
	_dev.set_process(true)
	if _dev_vp:
		_dev_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for _i in n:
		await get_tree().process_frame

func _report() -> void:
	var img := _vp.get_texture().get_image()
	print("--- rendered tops (Blender reference in brackets) ---")
	for key: String in ORDER:
		var holder := _board.find_child("Button_%s" % key, true, false) as Node3D
		var s := _cam.unproject_position(holder.position + Vector3(0.0, 0.525, 0.0))
		var c := img.get_pixel(int(s.x), int(s.y))
		var r: Vector3 = REF[key]
		var got := Vector3(int(c.r * 255.0), int(c.g * 255.0), int(c.b * 255.0))
		print("  %-8s screen=(%4d,%4d)  rgb=(%3d,%3d,%3d)   ref=(%d,%d,%d)   dE=%.0f" % [
			key, int(s.x), int(s.y), got.x, got.y, got.z, r.x, r.y, r.z, (got - r).length()])
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for key: String in ORDER:
		var holder := _board.find_child("Button_%s" % key, true, false) as Node3D
		for i in 24:
			var a := TAU * float(i) / 24.0
			var s := _cam.unproject_position(holder.position + Vector3(cos(a), 0.0, sin(a)))
			mn = mn.min(s)
			mx = mx.max(s)
	print("  buttons occupy x[%d..%d] of %d, y[%d..%d] of %d" % [
		mn.x, mx.x, img.get_width(), mn.y, mx.y, img.get_height()])

# How far the pressed surface actually travels on screen, and how much brighter
# it got — the two things the press render is meant to show.
func _press_report() -> void:
	var img := _vp.get_texture().get_image()
	var surf := _dev.surface_mesh("Magenta")
	var frame := _dev.frame_mesh("Magenta")
	print("--- magenta pressed ---")
	print("  surface y = %.4f (rest 0.0), frame y = %.4f (must be 0)" % [
		surf.position.y, frame.position.y])
	var holder := _board.find_child("Button_Magenta", true, false) as Node3D
	var s := _cam.unproject_position(holder.position + Vector3(0.0, 0.525, 0.0))
	var c := img.get_pixel(int(s.x), int(s.y))
	print("  top now (%d,%d,%d)  (idle was %s)" % [
		int(c.r * 255.0), int(c.g * 255.0), int(c.b * 255.0), str(REF["Magenta"])])

func _save(path: String) -> void:
	_dev.set_process(false)
	if _dev_vp:
		_dev_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for _i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_vp.get_texture().get_image().save_png(path)
	print("shot  %s" % ProjectSettings.globalize_path(path))
