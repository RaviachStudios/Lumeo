extends Node
# Screenshot harness for ROYAL CASINO: the poker table with the six chip buttons
# lying on it, through the REAL gameplay path — the real device class, the real
# camera fit, the real skin resolution — on whichever board is asked for.
#
# This is the check neither Blender nor a static read of the code can make. The
# table's whole palette is solved against the board's own Environment (AgX at
# tonemap_exposure 0.40, see CasinoWorld.tone), the chips are lit by a rig that only
# exists while they are worn, and the rail/arc are solved against the live camera —
# all of which only prove out in a render.
#
# Run WITHOUT --headless (the dummy driver has no framebuffer to read back):
#
#   Godot_..._console.exe --path . tools/casino_shot.tscn -- [easy|medium|hard] [stock]
#
# Writes res://shot_casino_*.png. Delete them when done.

const CHIPS := preload("res://chip_buttons.gd")
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
	CoinsManager.selected_theme = "default" if stock else CHIPS.THEME_ID

	_vp = SubViewport.new()
	_vp.size = Vector2i(SHOT_W, SHOT_H)
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_2d = Viewport.MSAA_DISABLED
	add_child(_vp)
	# The same flat fill the 2D layer puts behind the board in gameplay, so nothing
	# in the shot is standing on a colour the player never sees.
	var bg := ColorRect.new()
	bg.color = BackgroundScenes.backdrop_color(CHIPS.THEME_ID).linear_to_srgb()
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
	_report_table()

	await _settle(40)
	await _save("idle")
	_report()

	var last: int = _dev._count - 1
	_dev.set_lit(last, true)
	await _settle(30)
	await _save("highlight")
	_report_one(last, "highlight")
	_dev.set_lit(last, false)
	await _settle(30)

	# Mid-press: the clip is frozen at the bottom of its (scaled) travel, or the
	# settle frames the shot needs would also advance it back up and the "pressed"
	# frame would really be the released one.
	_dev.set_press(0, 1.0)
	await _settle(4)
	if _ap:
		_ap.seek(0.115, true)
		_ap.speed_scale = 0.0
	await _settle(14)
	_report_press()
	await _save("press")
	if _ap:
		_ap.speed_scale = 1.0
	_dev.set_press(0, 0.0)
	await _settle(30)
	get_tree().quit()


func _settle(n: int) -> void:
	_dev.set_process(true)
	if _dev_vp:
		_dev_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for _i in n:
		await get_tree().process_frame


# What the table SOLVED for this camera. The lamp, the arc and the rail are all
# answered on screen, so their numbers are the first thing to look at when the
# picture is wrong.
func _report_table() -> void:
	var w: Node3D = _dev._bg_scene
	if w == null:
		print("no table")
		return
	var fm: ShaderMaterial = w.get("_fmat")
	var vps := Vector2(_dev_vp.size)
	var top := vps.y
	for c: Vector2 in _dev._centres:
		top = minf(top, _cam.unproject_position(Vector3(c.x, CasinoWorld.CHIP_TOP, c.y)).y)
	print("--- the table, solved ---")
	print("  reach            %.2f" % float(w.get("_reach")))
	print("  top chip at      y %.0f of %d" % [top, int(vps.y)])
	print("  lamp             %s   soft %.2f" % [fm.get_shader_parameter("lamp"),
		fm.get_shader_parameter("lamp_soft")])
	var arc := float(fm.get_shader_parameter("arc_r"))
	print("  betting arc      r %.2f -> screen y %s" % [arc,
		"(off)" if arc <= 0.1 else "%.0f" % _cam.unproject_position(Vector3(0, 0, -arc)).y])
	var on := float(fm.get_shader_parameter("rail_on"))
	var rr := float(fm.get_shader_parameter("rail_r"))
	print("  rail             %s   r %.2f -> screen y %s" % ["ON" if on > 0.5 else "off", rr,
		"-" if on <= 0.5 else "%.0f" % _cam.unproject_position(Vector3(0, 0, -rr)).y])
	print("  fall             %s" % fm.get_shader_parameter("fall"))
	var dress := w.find_child("Dressing", false, false)
	if dress != null:
		for c in dress.get_children():
			if c is MultiMeshInstance3D:
				print("  %-11s x%d" % [c.name, (c as MultiMeshInstance3D).multimesh.instance_count])
	var ev := w.get_node_or_null("EventsRoot")
	if ev != null:
		print("  lane             %s  z %.2f  x %.2f..%.2f  card %.2f" % [
			"OK" if bool(ev.get("_lane_ok")) else "REFUSED",
			float(ev.get("_lane_z")), float(ev.get("_x_lo")), float(ev.get("_x_hi")),
			float(ev.get("_card_len"))])
		if bool(ev.get("_lane_ok")):
			print("  lane on screen   y %.0f (chips start at %.0f)"
				% [_cam.unproject_position(Vector3(0, 0, float(ev.get("_lane_z")))).y, top])


# What the six chips and the felt around them actually measure, so a colour
# complaint has numbers behind it instead of an impression. SATURATION is reported
# next to brightness on purpose: a chip that is bright and grey has lost the one
# thing a colour-matching game needs from it.
func _report() -> void:
	var img := _vp.get_texture().get_image()
	print("--- chip tops (y 0.32) and the felt 2.2 out from each ---")
	for key: String in _dev._keys:
		var holder := _board.find_child("Button_%s" % key, true, false) as Node3D
		if holder == null:
			continue
		var s := _cam.unproject_position(holder.position + Vector3(0.0, 0.33, 0.0))
		var f := _cam.unproject_position(holder.position * 1.55)
		var pc := _mean(img, s, 22.0)
		var fc := _px(img, f)
		print("  %-8s chip (%3d,%3d,%3d) sat %.2f lum %.2f   felt (%3d,%3d,%3d)"
			% [key, pc.r * 255, pc.g * 255, pc.b * 255, pc.s, pc.get_luminance(),
				fc.r * 255, fc.g * 255, fc.b * 255])
	print("  felt centre  %s" % str(_px(img, _cam.unproject_position(Vector3.ZERO)) * 255.0))


func _report_one(idx: int, what: String) -> void:
	var img := _vp.get_texture().get_image()
	var key: String = _dev._keys[idx]
	var holder := _board.find_child("Button_%s" % key, true, false) as Node3D
	var pc := _mean(img, _cam.unproject_position(holder.position + Vector3(0.0, 0.33, 0.0)), 22.0)
	print("  %s: %-8s (%3d,%3d,%3d) sat %.2f lum %.2f"
		% [what, key, pc.r * 255, pc.g * 255, pc.b * 255, pc.s, pc.get_luminance()])


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


# How far the pressed chip actually goes into the felt. The chip is 0.324 tall and
# stands on y = 0, so this is the whole of what PRESS_SCALE decides.
func _report_press() -> void:
	var key: String = _dev._keys[0]
	var surf := _board.find_child("Button_%s_Surface" % key, true, false) as MeshInstance3D
	if surf == null:
		return
	var drop: float = surf.position.y
	print("--- press: %s ---" % key)
	print("  travel            %.4f  (%.0f mm)" % [drop, -drop * 1000.0])
	print("  chip top          %.4f  (%.0f%% of its height still proud)"
		% [CasinoWorld.CHIP_TOP + drop,
			100.0 * (CasinoWorld.CHIP_TOP + drop) / CasinoWorld.CHIP_TOP])


func _px(img: Image, p: Vector2) -> Color:
	return img.get_pixel(clampi(int(p.x), 0, SHOT_W - 1), clampi(int(p.y), 0, SHOT_H - 1))


func _save(what: String) -> void:
	if _dev_vp:
		_dev_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for _i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "res://shot_casino_%s_%s.png" % [_tag, what]
	_vp.get_texture().get_image().save_png(path)
	print("shot  %s" % path)
