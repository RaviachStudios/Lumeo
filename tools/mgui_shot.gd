extends Node
# Screenshot harness for memory_game_ui.gd. Renders the device at the Blender
# reference's exact resolution (1440x1440), with the same near-black plate behind
# it, so the result can be compared pixel-for-pixel against
# APP IDEAS/Simon/MediumNew/MemoryGame_UI_idle.png. Run WITHOUT --headless (the
# dummy renderer has no framebuffer to read back):
#
#   godot --path . tools/mgui_shot.tscn
#
# Saves idle, red-highlighted and red-pressed. Not shipped with the game.

const SHOT_W := 1920
const SHOT_H := 1080

var _dev: MemoryGameUI
var _vp: SubViewport
var _dev_vp: SubViewport
var _ap: AnimationPlayer

func _ready() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(SHOT_W, SHOT_H)
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_2d = Viewport.MSAA_DISABLED
	add_child(_vp)

	# Stand-in for the screen behind the device: the reference's near-black plate.
	var bg := ColorRect.new()
	bg.color = Color8(4, 5, 7)
	bg.size = Vector2(SHOT_W, SHOT_H)
	_vp.add_child(bg)

	_dev = MemoryGameUI.new()
	_dev.input_enabled = false
	_dev.size = Vector2(SHOT_W, SHOT_H)
	_vp.add_child(_dev)
	await get_tree().process_frame
	_dev.configure(5, [])
	_dev.set_round_number(12)

	for c in _dev.get_children():
		if c is SubViewportContainer:
			_dev_vp = (c as SubViewportContainer).get_child(0) as SubViewport
	_ap = _dev.find_child("AnimationPlayer", true, false) as AnimationPlayer

	await _settle(30)
	await _save("user://mgui_idle.png")
	_report()

	# Cyan (the back button) highlighted, as the sequence plays it.
	_dev.set_lit(2, true)
	await _settle(40)
	await _save("user://mgui_hl_cyan.png")
	_dev.set_lit(2, false)

	# Cyan at the bottom of its press stroke (the clip holds 0.067..0.133s).
	await _settle(40)
	_dev.set_press(2, 1.0)
	await _settle(30)
	if _ap:
		_ap.seek(0.09, true)
	await _settle(6)
	await _save("user://mgui_press_cyan.png")

	get_tree().quit()

# Run `n` frames with the device live, then freeze it so the captured frame is
# the settled one. PentagonDevice's note applies here too: the device drives its
# own SubViewport back to idle every frame, so it has to stop processing before
# UPDATE_ALWAYS will stick.
func _settle(n: int) -> void:
	_dev.set_process(true)
	if _dev_vp:
		_dev_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for _i in n:
		await get_tree().process_frame

# Sample the render at points whose board coordinates we know, and print them
# against the Blender reference's own values.
const REF := {
	"Crimson": Vector3(106, 13, 56),
	"Cyan": Vector3(70, 167, 167),
	"Amber": Vector3(178, 137, 77),
	"Violet": Vector3(99, 97, 192),
	"Jade": Vector3(-1, -1, -1),
}

func _report() -> void:
	var img := _vp.get_texture().get_image()
	var cam: Camera3D = null
	for c in _dev_vp.get_children():
		if c is Camera3D:
			cam = c
	var board := _dev.find_child("MemoryGame_UI", true, false) as Node3D
	print("--- rendered tops (reference in brackets) ---")
	for key: String in ["Crimson", "Jade", "Cyan", "Amber", "Violet"]:
		var holder := board.find_child("Button_%s" % key, true, false) as Node3D
		var p := holder.position + Vector3(0.0, 0.525, 0.0)
		var s := cam.unproject_position(p)
		var c := img.get_pixel(int(s.x), int(s.y))
		var r: Vector3 = REF[key]
		print("  %-8s screen=(%4d,%4d)  rgb=(%3d,%3d,%3d)   ref=(%d,%d,%d)" % [
			key, int(s.x), int(s.y),
			int(c.r * 255.0), int(c.g * 255.0), int(c.b * 255.0), r.x, r.y, r.z])
	# framing extents
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for key: String in ["Crimson", "Jade", "Cyan", "Amber", "Violet"]:
		var holder := board.find_child("Button_%s" % key, true, false) as Node3D
		for i in 24:
			var a := TAU * float(i) / 24.0
			var s := cam.unproject_position(holder.position + Vector3(cos(a), 0.0, sin(a)))
			mn = mn.min(s)
			mx = mx.max(s)
	print("  buttons occupy x[%d..%d] of %d, y[%d..%d] of %d" % [
		mn.x, mx.x, img.get_width(), mn.y, mx.y, img.get_height()])
	var tab: Control = _dev._tab
	if tab:
		print("  level tab rect=%s  showing %s" % [Rect2(tab.position, tab.size), tab._num.text])
	# Ground pools, sampled outward from Crimson into the empty front-left where
	# no other button contributes. Reference profile (its own hue channel, of 255):
	#   r 1.25 -> 35   1.50 -> 31   1.75 -> 25   2.00 -> 21   2.50 -> 16
	var cr := board.find_child("Button_Crimson", true, false) as Node3D
	var dir := Vector3(-0.7, 0.0, 0.8).normalized()
	var row := ""
	for r: float in [1.25, 1.50, 1.75, 2.00, 2.50]:
		var s := cam.unproject_position(cr.position + Vector3(0.0, 0.02, 0.0) + dir * r)
		var c := img.get_pixel(clampi(int(s.x), 0, img.get_width() - 1),
			clampi(int(s.y), 0, img.get_height() - 1))
		row += "r%.2f=(%d,%d,%d) " % [r, int(c.r * 255.0), int(c.g * 255.0), int(c.b * 255.0)]
	print("  crimson pool ", row, " [ref R: 35 31 25 21 16]")
	if lbl:
		var s := cam.unproject_position(lbl.position + Vector3(0, 0.01, 0))
		var best := Color(0, 0, 0)
		for dy in range(-26, 27):
			for dx in range(-60, 61):
				var q := img.get_pixel(int(s.x) + dx, int(s.y) + dy)
				if q.r + q.g + q.b > best.r + best.g + best.b:
					best = q
		print("  round-number ink brightest = (%d,%d,%d)" % [
			int(best.r * 255.0), int(best.g * 255.0), int(best.b * 255.0)])

func _save(path: String) -> void:
	_dev.set_process(false)
	if _dev_vp:
		_dev_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for _i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	img.save_png(path)
	print("shot  %s" % ProjectSettings.globalize_path(path))
