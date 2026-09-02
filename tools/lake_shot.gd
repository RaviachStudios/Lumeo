extends Node
# Screenshot harness for MAGICAL LAKE: the lake environment with the lily-pad
# buttons standing on it, through the REAL gameplay path — the real device class,
# the real camera fit, the real skin resolution — on whichever board is asked for.
#
# This is the check neither Blender nor a static read of the code can make. The
# lake's whole palette is solved against the board's own Environment (AgX at
# tonemap_exposure 0.40, see LakeWorld.tone), the pads are lit almost entirely by
# an emission derived from their own albedo, and the waterline is a number chosen
# off the asset's underside — all three only prove out in a render.
#
# Run WITHOUT --headless (the dummy driver has no framebuffer to read back —
# see tools/lake_verify.gd's note):
#
#   Godot_..._console.exe --path . tools/lake_shot.tscn -- [easy|medium|hard] [stock]
#
# Writes res://shot_lake_*.png. Delete them when done.

const LILY := preload("res://lily_buttons.gd")
const SHOT_W := 1280
const SHOT_H := 720

var _dev: MemoryGameUI
var _vp: SubViewport
var _dev_vp: SubViewport
var _cam: Camera3D
var _board: Node3D
var _ap: AnimationPlayer
var _tag := "hard"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var which := String(args[0]) if args.size() > 0 else "hard"
	var stock := args.has("stock")
	_tag = which + ("_stock" if stock else "")

	for _i in 10:
		await get_tree().process_frame     # let CoinsManager load the wallet
	CoinsManager.selected_theme = "default" if stock else LILY.THEME_ID

	_vp = SubViewport.new()
	_vp.size = Vector2i(SHOT_W, SHOT_H)
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_2d = Viewport.MSAA_DISABLED
	add_child(_vp)
	# The same flat fill the 2D layer puts behind the board in gameplay, so nothing
	# in the shot is standing on a colour the player never sees.
	var bg := ColorRect.new()
	bg.color = BackgroundScenes.backdrop_color(LILY.THEME_ID).linear_to_srgb()
	bg.size = Vector2(SHOT_W, SHOT_H)
	_vp.add_child(bg)

	match which:
		"easy": _dev = EasyGameUI.new()
		"medium": _dev = MemoryGameUI.new()
		_: _dev = HardGameUI.new()
	_dev.input_enabled = false
	_dev.size = Vector2(SHOT_W, SHOT_H)
	_vp.add_child(_dev)
	await get_tree().process_frame
	_dev.configure(_dev._count, [])
	_dev.set_level(7)

	for c in _dev.get_children():
		if c is SubViewportContainer:
			_dev_vp = (c as SubViewportContainer).get_child(0) as SubViewport
	for c in _dev_vp.get_children():
		if c is Camera3D:
			_cam = c
	_board = _dev.find_child("MemoryGame_UI", true, false) as Node3D
	_ap = _dev.find_child("AnimationPlayer", true, false) as AnimationPlayer
	print("board %s   button skin: '%s'   keys %s" % [which, _dev.button_skin_id(), str(_dev._keys)])
	var lake := _dev._bg_scene
	if lake != null:
		print("lake reach %.2f   dressing:" % lake.get("_reach"))
		for c in lake.find_child("Dressing", false, false).get_children():
			if c is MultiMeshInstance3D:
				var mm: MultiMesh = (c as MultiMeshInstance3D).multimesh
				var p0 := mm.get_instance_transform(0).origin if mm.instance_count > 0 else Vector3.ZERO
				var s0 := _cam.unproject_position(p0)
				print("   %-9s x%-3d  first at (%.1f, %.2f, %.1f) -> screen (%d, %d)"
					% [c.name, mm.instance_count, p0.x, p0.y, p0.z, s0.x, s0.y])
			else:
				print("   %-9s (batched sheet)" % c.name)

	await _settle(40)
	await _save("idle")
	_report()

	var last: int = _dev._count - 1
	_dev.set_lit(last, true)
	await _settle(30)
	await _save("highlight")
	_dev.set_lit(last, false)
	await _settle(30)

	# Mid-splash: the press clip is 0.09 s in (the pad at the bottom of its travel)
	# and the ripple has had a quarter of a second to leave it.
	_dev.set_press(0, 1.0)
	await _settle(4)
	if _ap:
		# Freeze the clip AT the bottom. Without this the settle frames the shot
		# needs for the water to catch up also advance the player through the rest
		# of the stroke, and the "pressed" frame is really the released one.
		_ap.seek(0.115, true)
		_ap.speed_scale = 0.0
	await _settle(14)
	_report_press()
	await _save("press")
	if _ap:
		_ap.speed_scale = 1.0
	_dev.set_press(0, 0.0)
	await _settle(30)
	await _save("settle")
	get_tree().quit()

func _settle(n: int) -> void:
	_dev.set_process(true)
	if _dev_vp:
		_dev_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for _i in n:
		await get_tree().process_frame

# What the six pads and the water they sit in actually measure, so a colour
# complaint has numbers behind it instead of an impression.
func _report() -> void:
	var img := _vp.get_texture().get_image()
	print("--- pad tops (dish centre, y 0.25) and the water 2.2 out from each ---")
	for key: String in _dev._keys:
		var holder := _board.find_child("Button_%s" % key, true, false) as Node3D
		if holder == null:
			continue
		var s := _cam.unproject_position(holder.position + Vector3(0.0, 0.25, 0.0))
		var w := _cam.unproject_position(holder.position * 1.55 + Vector3(0.0, LakeWorld.WATER_Y, 0.0))
		# Saturation, not only brightness. A pad that is bright and grey has lost the
		# one thing a colour-matching game needs from it, and the number is the only
		# way to see that coming (see the HIGHLIGHT_BOOST note in memory_game_ui.gd).
		var pc := _mean(img, s, 26.0)
		print("  %-8s pad (%3d,%3d,%3d) sat %.2f   water (%3d,%3d,%3d)"
			% [key, pc.r * 255, pc.g * 255, pc.b * 255, pc.s,
				_px(img, w).r * 255, _px(img, w).g * 255, _px(img, w).b * 255])

# The mean colour inside `r` pixels of `p` — the button as the eye reads it, not
# whatever the vein hub's specular happens to be doing at one texel.
func _mean(img: Image, p: Vector2, r: float) -> Color:
	var acc := Color(0, 0, 0)
	var n := 0
	for dy in range(int(-r), int(r) + 1):
		for dx in range(int(-r), int(r) + 1):
			if Vector2(dx, dy).length() > r:
				continue
			acc += _px(img, p + Vector2(dx, dy))
			n += 1
	return acc / maxf(1.0, float(n))

# How deep the pressed pad actually goes, in board units against the waterline.
# The pad's underside is y 0 at its middle and its top there is y 0.249, so what
# decides whether it "sinks" is how much of that 0.249 is left above LakeWorld's
# WATER_Y once the clip has taken its travel out.
func _report_press() -> void:
	var key: String = _dev._keys[0]
	var surf := _board.find_child("Button_%s_Surface" % key, true, false) as MeshInstance3D
	if surf == null:
		return
	var drop: float = surf.position.y
	var water := LakeWorld.WATER_Y
	print("--- press: %s ---" % key)
	print("  travel            %.4f" % drop)
	print("  dish centre top   %.4f  (%.0f mm above water)" % [0.249 + drop, (0.249 + drop - water) * 1000.0])
	print("  rim top           %.4f  (%.0f mm above water)" % [0.339 + drop, (0.339 + drop - water) * 1000.0])
	print("  underside centre  %.4f  (%.0f mm below water)" % [0.0 + drop, (water - drop) * 1000.0])

func _px(img: Image, p: Vector2) -> Color:
	return img.get_pixel(clampi(int(p.x), 0, SHOT_W - 1), clampi(int(p.y), 0, SHOT_H - 1))

func _save(what: String) -> void:
	if _dev_vp:
		_dev_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for _i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "res://shot_lake_%s_%s.png" % [_tag, what]
	_vp.get_texture().get_image().save_png(path)
	print("shot  %s" % path)
