extends Node
# Screenshot + measurement harness for easy_game_ui.gd, modelled on
# tools/hgui_shot.gd. Renders the three-button board at the Blender reference's
# exact resolution over the same near-black plate, so the result can be compared
# against "APP IDEAS/Simon/EasyV3/MemoryGame_UI_Easy_idle.png" and
# ..._press_magenta.png. Run WITHOUT --headless (the dummy renderer has no
# framebuffer to read back):
#
#   Godot_..._console.exe --path . tools/egui_shot.tscn
#
# Saves idle, one highlighted, one pressed, and one wearing a shop frame.

const SHOT_W := 1920
const SHOT_H := 1080

# The reference render's own button tops, the median of a 13x13 patch at each
# button's centre in EasyV3/MemoryGame_UI_Easy_idle.png.
const REF := {
	"Cyan": Vector3(115, 177, 188),
	"Yellow": Vector3(184, 164, 100),
	"Magenta": Vector3(201, 92, 160),
}
const ORDER := ["Cyan", "Yellow", "Magenta"]
# Where the reference puts each button's white rim: the outer ENVELOPE of its rim
# pixels, as [min x, max x, min y, max y] in the 1920x1080 render. This — not the
# centroid — is what the camera was fitted against, because the centroid of a ring
# seen in perspective is NOT where its centre projects (the near half of the ring
# projects larger and drags the mean toward the camera, by 14 px on the back
# buttons here and 23 px on the front one).
const REF_RIM := {
	"Cyan": Vector4(435.0, 803.0, 200.0, 368.0),
	"Yellow": Vector4(1116.0, 1484.0, 200.0, 368.0),
	"Magenta": Vector4(729.0, 1190.0, 496.0, 763.0),
}
# The radius the GLB authors that rim at, and the height it sits at.
const RIM_R := 0.662
const RIM_Y := 0.5148

var _dev: EasyGameUI
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

	_dev = EasyGameUI.new()
	_dev.input_enabled = false
	_dev.size = Vector2(SHOT_W, SHOT_H)
	_vp.add_child(_dev)
	await get_tree().process_frame
	_dev.configure(3, [])
	_dev.set_level(7)

	for c in _dev.get_children():
		if c is SubViewportContainer:
			_dev_vp = (c as SubViewportContainer).get_child(0) as SubViewport
	for c in _dev_vp.get_children():
		if c is Camera3D:
			_cam = c
	_board = _dev.find_child("MemoryGame_UI", true, false) as Node3D
	_ap = _dev.find_child("AnimationPlayer", true, false) as AnimationPlayer

	await _settle(30)
	await _save("user://egui_idle.png")
	_report()

	_dev.set_lit(0, true)                 # cyan, as the sequence plays it
	await _settle(40)
	await _save("user://egui_hl_cyan.png")
	_dev.set_lit(0, false)
	await _settle(40)

	# Magenta at the bottom of its press stroke (the clip holds 0.067..0.133s),
	# which is the pose the reference's press render captures.
	_dev.set_press(2, 1.0)
	await _settle(30)
	if _ap:
		_ap.seek(0.09, true)
	await _settle(6)
	await _save("user://egui_press_magenta.png")
	_press_report()
	_dev.set_press(2, 0.0)
	await _settle(40)

	_dev.apply_button_frame("tiger_glow")
	await _settle(30)
	await _save("user://egui_frame_tiger.png")

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
	# Does the CAMERA reproduce the Blender reference? Not as shipped — the device
	# pulls back and re-centres to leave room for game.gd's HUD, and a perspective
	# camera at a different distance changes the shape of the composition, not just
	# its scale. So the fitted lens and elevation are checked where they were
	# solved: put the camera back at EASY_CAM_DIST_START on EASY_CAM_TARGET, with
	# the board at its authored spacing, and the three rims must land on the pixels
	# they occupy in the reference render.
	print("--- camera pose vs the reference (at the fitted distance) ---")
	var live := _cam.global_transform
	var e := deg_to_rad(EasyGameUI.EASY_CAM_ELEV_DEG)
	var t := EasyGameUI.EASY_CAM_TARGET
	_cam.look_at_from_position(
		t + Vector3(0.0, sin(e), cos(e)) * EasyGameUI.EASY_CAM_DIST_START, t, Vector3.UP)
	var err := 0.0
	for key: String in ORDER:
		var got := _rim_envelope(key)
		var r: Vector4 = REF_RIM[key]
		for i in 4:
			err += pow(got[i] - r[i], 2.0)
		print("  %-8s x[%7.2f..%7.2f] y[%7.2f..%7.2f]" % [key, got.x, got.y, got.z, got.w])
		print("           reference  x[%7.2f..%7.2f] y[%7.2f..%7.2f]" % [r.x, r.y, r.z, r.w])
	print("  RMS %.2f px over the twelve fitted rim extents" % sqrt(err / 12.0))
	_cam.global_transform = live

	print("--- rim envelopes as shipped (re-fitted into the HUD's band) ---")
	for key: String in ORDER:
		var got := _rim_envelope(key)
		print("  %-8s x[%6.1f..%6.1f] y[%6.1f..%6.1f]" % [key, got.x, got.y, got.z, got.w])
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

# The projected outer envelope of one button's white rim: [min x, max x, min y,
# max y] of the authored ring circle, sampled densely enough to find the extremes.
func _rim_envelope(key: String) -> Vector4:
	var c := (_board.find_child("Button_%s" % key, true, false) as Node3D).position
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for i in 360:
		var a := TAU * float(i) / 360.0
		var s := _cam.unproject_position(
			c + Vector3(cos(a) * RIM_R, RIM_Y, sin(a) * RIM_R))
		mn = mn.min(s)
		mx = mx.max(s)
	return Vector4(mn.x, mx.x, mn.y, mx.y)

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
