extends Node
# Screenshot harness for ICE KINGDOM: the generated ice environment with the
# snowflake buttons standing on it, through the REAL gameplay path — the real
# device class, the real camera fit, the real skin resolution — on whichever board
# is asked for.
#
# It also MEASURES the one thing this background exists to fix, which is a ratio
# rather than a look: the buttons have to be the brightest and most saturated
# things in the frame, and the middle of the picture has to be the quietest part of
# the background. The imported world this replaced failed both, and it failed them
# by numbers anyone could have printed.
#
# Run WITHOUT --headless (the dummy driver has no framebuffer to read back):
#
#   Godot_..._console.exe --path . tools/ice_shot.tscn -- [easy|medium|hard]
#
# Writes res://shot_ice_*.png. Delete them when done.

const ICE := preload("res://ice_buttons.gd")
const SHOT_W := 1280
const SHOT_H := 720

var _dev: MemoryGameUI
var _vp: SubViewport
var _dev_vp: SubViewport
var _cam: Camera3D
var _board: Node3D
var _tag := "hard"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var which := String(args[0]) if args.size() > 0 else "hard"
	_tag = which

	for _i in 10:
		await get_tree().process_frame     # let CoinsManager load the wallet
	CoinsManager.selected_theme = ICE.THEME_ID

	_vp = SubViewport.new()
	_vp.size = Vector2i(SHOT_W, SHOT_H)
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_2d = Viewport.MSAA_DISABLED
	add_child(_vp)
	# The same flat fill the 2D layer puts behind the board in gameplay, so nothing
	# in the shot is standing on a colour the player never sees.
	var plate := ColorRect.new()
	plate.color = BackgroundScenes.backdrop_color(ICE.THEME_ID).linear_to_srgb()
	plate.size = Vector2(SHOT_W, SHOT_H)
	_vp.add_child(plate)

	match which:
		"easy": _dev = EasyGameUI.new()
		"medium": _dev = MemoryGameUI.new()
		_: _dev = HardGameUI.new()
	_dev.input_enabled = false
	_dev.size = Vector2(SHOT_W, SHOT_H)
	_vp.add_child(_dev)
	await get_tree().process_frame
	_dev.configure(_dev._count, [])
	_dev.set_level(12)

	for c in _dev.get_children():
		if c is SubViewportContainer:
			_dev_vp = (c as SubViewportContainer).get_child(0) as SubViewport
	for c in _dev_vp.get_children():
		if c is Camera3D:
			_cam = c
	_board = _dev.find_child("MemoryGame_UI", true, false) as Node3D
	print("board %s   button skin: '%s'   background: %s"
		% [which, _dev.button_skin_id(), _dev._bg_id])
	var ice := _dev._bg_scene
	if ice != null:
		print("ice reach %.2f   %d draw calls:" % [float(ice.get("_reach")),
			_draw_calls(ice)])
		for n in _pieces(ice):
			var mi := n as GeometryInstance3D
			var count := 1
			if mi is MultiMeshInstance3D:
				count = (mi as MultiMeshInstance3D).multimesh.instance_count
			print("   %-10s x%-3d  layer %d" % [mi.name, count, mi.layers])

	# THE FRAMING, in the numbers FRAME_BIAS is chosen against: where the fit put the
	# board's silhouette, and where the buttons themselves actually end. The gap
	# between the two is the headroom — how far the board may still be pushed DOWN
	# before anything the player looks at is cropped — and guessing it wrong is how a
	# board ends up either sitting on the horizon or floating in an empty lake.
	var top := 1e9
	var bot := -1e9
	for key: String in _dev._keys:
		var h := _board.find_child("Button_%s" % key, true, false) as Node3D
		if h == null:
			continue
		var c := _cam.unproject_position(h.position + Vector3(0.0, 0.30, 0.0))
		var r := _btn_px(h)
		top = minf(top, c.y - r * 0.62)
		bot = maxf(bot, c.y + r * 0.62)
	print("frame  silhouette %.0f..%.0f   buttons %.0f..%.0f   headroom %.0f px"
		% [_dev._board_rect.position.y, _dev._board_rect.end.y, top, bot,
			float(SHOT_H) - bot])
	print("       horizon at %.0f px" % (SHOT_H * IceWorld.HORIZON_FY))

	await _settle(50)
	await _save("idle")
	_band("idle", _dev_vp.get_texture().get_image())
	_report()

	var last: int = _dev._count - 1
	_dev.set_lit(last, true)
	await _settle(30)
	await _save("highlight")
	print("--- with %s lit ---" % _dev._keys[last])
	_report()
	_dev.set_lit(last, false)
	await _settle(30)
	get_tree().quit()


func _pieces(ice: Node3D) -> Array:
	var out: Array = []
	for c in ice.get_children():
		if c is GeometryInstance3D:
			out.append(c)
		for d in c.get_children():
			if d is GeometryInstance3D:
				out.append(d)
	return out


func _draw_calls(ice: Node3D) -> int:
	return _pieces(ice).size()


func _settle(n: int) -> void:
	_dev.set_process(true)
	if _dev_vp:
		_dev_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for _i in n:
		await get_tree().process_frame


# The numbers the design rule is written in. Every one of them is a mean over an
# area, not a pixel: a single texel of a crack or of a flake's rim says nothing
# about what the eye reads.
#
# The background is measured by EXCLUSION rather than at chosen spots, and that is
# not fussiness — the first version of this sampled six fixed fractions of the
# frame, and on Easy "the middle of the ring" landed on the pink flake and reported
# the background at 98 % of a button. Three buttons and six buttons do not put
# their gaps in the same places. So: the frame is reduced to a 320x180 grid of
# means, every cell inside a button's own screen disc is dropped, and what is left
# IS the background, wherever it happens to be on this board.
const GRID_W := 320
const GRID_H := 180
# How much past a button's measured screen radius counts as still being the button.
# Its frost socket and the light it lays immediately around itself are not the
# background, and including them is how a board full of buttons measures as a
# bright background.
const BTN_MARGIN := 1.25

# One button's radius in pixels, as this camera actually draws it.
func _btn_px(holder: Node3D) -> float:
	var mid: Vector3 = holder.position + Vector3(0.0, 0.30, 0.0)
	var edge: Vector3 = mid + Vector3(1.15, 0.0, 0.0)
	if _cam.is_position_behind(mid) or _cam.is_position_behind(edge):
		return 24.0
	return _cam.unproject_position(mid).distance_to(_cam.unproject_position(edge))


# A NEAREST blow-up of the horizon band, because the sky is about 120 px of a 720
# frame and a mountain range cannot be judged at 1:1.
func _band(tag: String, img: Image) -> void:
	_slice(tag + "_sky", img, 0, int(SHOT_H * 0.42))
	# ...and the ICE, which is the largest area of the frame and the one that reads
	# as empty when it is empty.
	_slice(tag + "_ice", img, int(SHOT_H * 0.22), int(SHOT_H * 0.36))


func _slice(tag: String, img: Image, y: int, h: int) -> void:
	var band := Image.create(SHOT_W, h, false, img.get_format())
	band.blit_rect(img, Rect2i(0, y, SHOT_W, h), Vector2i.ZERO)
	band.resize(SHOT_W * 2, h * 2, Image.INTERPOLATE_NEAREST)
	band.save_png("res://shot_ice_%s_%s_band.png" % [_tag, tag])


func _report() -> void:
	# The BOARD's own 3D viewport, not the composited frame. The frame also carries
	# the 2D HUD, and the LEVEL badge's white numerals are the brightest pixels in
	# the picture by a wide margin — the first run of this reported the background
	# peaking at 180 % of a button and was pointing at the "12".
	var img := _dev_vp.get_texture().get_image()
	var flake_l := 0.0
	var flake_s := 0.0
	# The sample radius is a fraction of the BUTTON's own screen radius, not a fixed
	# 24 px. A background may now ask for the board to be framed smaller
	# (BackgroundScenes.frame_bias, which Ice Kingdom uses), and a fixed radius on a
	# smaller button samples its rim and the ice beside it — which reads as the
	# buttons having got darker when all that happened is that they got further away.
	# 0.21 is what the old fixed 24 px WAS as a fraction of a button at the framing
	# every board used before that hook existed, so the numbers stay comparable with
	# every measurement in ice_world.gd's header.
	for key: String in _dev._keys:
		var holder := _board.find_child("Button_%s" % key, true, false) as Node3D
		if holder == null:
			continue
		var s := _cam.unproject_position(holder.position + Vector3(0.0, 0.525, 0.0))
		var c := _mean(img, s, maxf(_btn_px(holder) * 0.21, 8.0))
		flake_l += _lum(c)
		flake_s += _sat(c)
		print("  flake %-8s (%3d,%3d,%3d)  L %5.1f  sat %.2f"
			% [key, c.r * 255, c.g * 255, c.b * 255, _lum(c), _sat(c)])
	flake_l /= float(maxi(_dev._keys.size(), 1))
	flake_s /= float(maxi(_dev._keys.size(), 1))

	# The buttons' screen discs, measured the way the camera actually draws them.
	# _btn_px is the same measurement, per button, and the flake sampler uses it too.
	var discs: Array = []
	for key: String in _dev._keys:
		var holder := _board.find_child("Button_%s" % key, true, false) as Node3D
		if holder == null:
			continue
		var mid := holder.position + Vector3(0.0, 0.30, 0.0)
		var edge := mid + Vector3(1.15, 0.0, 0.0)
		if _cam.is_position_behind(mid) or _cam.is_position_behind(edge):
			continue
		var cs := _cam.unproject_position(mid)
		discs.append([cs, cs.distance_to(_cam.unproject_position(edge)) * BTN_MARGIN])

	var small := img.duplicate()
	small.resize(GRID_W, GRID_H, Image.INTERPOLATE_BILINEAR)
	var sx := float(GRID_W) / float(SHOT_W)
	var acc := 0.0
	var sat := 0.0
	var n := 0
	var worst := -1.0
	var worst_at := Vector2.ZERO
	var worst_c := Color.BLACK
	for gy in GRID_H:
		for gx in GRID_W:
			var p := Vector2((float(gx) + 0.5) / sx, (float(gy) + 0.5) / sx)
			var skip := false
			for d: Array in discs:
				if p.distance_to(d[0]) < float(d[1]):
					skip = true
					break
			if skip:
				continue
			var c: Color = small.get_pixel(gx, gy)
			var l := _lum(c)
			acc += l
			sat += _sat(c)
			n += 1
			if l > worst:
				worst = l
				worst_at = p
				worst_c = c
	var mean := acc / maxf(float(n), 1.0)
	print("  bg    %d cells of %d are background   mean L %.1f  mean sat %.2f"
		% [n, GRID_W * GRID_H, mean, sat / maxf(float(n), 1.0)])
	# The peak's COLOUR as well as its position, because the position alone is not
	# enough to say what is producing it: a crystal tip, a frozen plate, the far ice
	# wall's crest and the sheen on the ice all live in the same part of the frame,
	# and three palette edits were spent on the wrong one before this line existed.
	print("  bg    brightest anywhere in it: L %.1f at (%d, %d)  rgb (%d,%d,%d)"
		% [worst, worst_at.x, worst_at.y,
			worst_c.r * 255.0, worst_c.g * 255.0, worst_c.b * 255.0])
	print("  RULE  flakes mean L %.1f sat %.2f" % [flake_l, flake_s])
	print("        the background\'s MEAN is %.0f%% of a button and its PEAK is %.0f%%"
		% [100.0 * mean / maxf(flake_l, 0.001), 100.0 * worst / maxf(flake_l, 0.001)])


static func _lum(c: Color) -> float:
	return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) * 255.0


static func _sat(c: Color) -> float:
	var hi := maxf(c.r, maxf(c.g, c.b))
	var lo := minf(c.r, minf(c.g, c.b))
	return 0.0 if hi <= 0.0001 else (hi - lo) / hi


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


func _px(img: Image, p: Vector2) -> Color:
	return img.get_pixel(clampi(int(p.x), 0, SHOT_W - 1), clampi(int(p.y), 0, SHOT_H - 1))


func _save(what: String) -> void:
	if _dev_vp:
		_dev_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for _i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "res://shot_ice_%s_%s.png" % [_tag, what]
	_vp.get_texture().get_image().save_png(path)
	print("shot  %s" % path)
