extends Node
# The MAGICAL LAKE pads' COMPUTER-SEQUENCE HIGHLIGHT, measured rather than eyeballed.
#
# The complaint this exists to settle: when the computer plays a pad back, the
# rolled rim flashes and the recessed dish inside it stays dark, so the highlight
# reads as a glowing RING with a hole in it instead of as one lit lily pad.
#
# It is a ratio, and a ratio is a number: this lights each of the six pads in turn
# at a set of candidate face-highlight lifts and prints the mean colour of the DISH
# against the mean colour of the RIM for each one. `LilyButtons.HIGHLIGHT_FACE` is
# the lift that brings the two together without pushing the dish into the clip that
# turns a saturated pad white (see MemoryGameUI.HIGHLIGHT_BOOST's note on why the
# face is the channel that washes out).
#
# Run WITHOUT --headless — it reads back a rendered image:
#   Godot_..._console.exe --path . tools/lily_glow.tscn -- [easy|medium|hard]
#
# Writes res://shot_lily_glow_<lift>.png, one per candidate. Delete them when done.

const LILY := preload("res://lily_buttons.gd")
const SHOT_W := 1280
const SHOT_H := 720

# Candidate lifts on the dish's highlight rung, as multipliers on the stock one.
# 1.0 is what shipped and is the defect.
const LIFTS := [2.35, 3.0, 3.8, 4.6]

# Where the two samples are taken, in the pad's own units (its outline is r = 1.0).
# The dish is a bowl whose middle sits at y 0.249 and the rim rolls up to 0.339 at
# r = 0.88 — so these are the two surfaces the complaint is about, at the heights
# they actually occupy, rather than two guesses at a screen radius.
const DISH_R := 0.0
const DISH_Y := 0.249
const RIM_R := 0.88
const RIM_Y := 0.324

var _dev: MemoryGameUI
var _vp: SubViewport
var _dev_vp: SubViewport
var _cam: Camera3D
var _board: Node3D

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var which := String(args[0]) if args.size() > 0 else "hard"

	for _i in 10:
		await get_tree().process_frame
	CoinsManager.selected_theme = LILY.THEME_ID

	_vp = SubViewport.new()
	_vp.size = Vector2i(SHOT_W, SHOT_H)
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_2d = Viewport.MSAA_DISABLED
	add_child(_vp)
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
	await _settle(40)

	var shipped: float = float(_dev._surf_levels[0][MemoryGameUI.STATE_HIGHLIGHT])
	print("board %s   shipped face highlight %.3f   ring %.3f"
		% [which, shipped, float(_dev._ring_levels[0][MemoryGameUI.STATE_HIGHLIGHT])])

	for lift: float in LIFTS:
		for i in _dev._count:
			_dev._surf_levels[i][MemoryGameUI.STATE_HIGHLIGHT] = shipped * lift
		# Light every pad at once: the question is about ONE pad's own surfaces, and
		# lighting them together is the only way to get all six in one frame.
		for i in _dev._count:
			_dev.set_lit(i, true)
		await _settle(30)
		await _save(lift)
		print("--- face lift x%.2f  (dish highlight %.2f of idle) ---" % [lift, shipped * lift])
		_report()
		for i in _dev._count:
			_dev.set_lit(i, false)
		await _settle(24)
	get_tree().quit()

func _settle(n: int) -> void:
	_dev.set_process(true)
	if _dev_vp:
		_dev_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for _i in n:
		await get_tree().process_frame

# Dish against rim, per colour. `gap` is what the eye reads as the hole: the dish's
# luminance as a fraction of the rim's, where 1.00 is one evenly lit pad.
func _report() -> void:
	var img := _vp.get_texture().get_image()
	for idx in _dev._count:
		var key: String = _dev._keys[idx]
		var holder := _board.find_child("Button_%s" % key, true, false) as Node3D
		if holder == null:
			continue
		var c := holder.position
		var dish := _mean(img, _cam.unproject_position(c + Vector3(DISH_R, DISH_Y, 0.0)), 9.0)
		var rl := _mean(img, _cam.unproject_position(c + Vector3(-RIM_R, RIM_Y, 0.0)), 5.0)
		var rr := _mean(img, _cam.unproject_position(c + Vector3(RIM_R, RIM_Y, 0.0)), 5.0)
		var rim := (rl + rr) * 0.5
		print("  %-8s dish (%3d,%3d,%3d) L %5.1f sat %.2f   rim (%3d,%3d,%3d) L %5.1f   dish/rim %.2f"
			% [key, dish.r * 255, dish.g * 255, dish.b * 255, _lum(dish), _sat(dish),
				rim.r * 255, rim.g * 255, rim.b * 255, _lum(rim),
				_lum(dish) / maxf(_lum(rim), 0.001)])

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

func _save(lift: float) -> void:
	if _dev_vp:
		_dev_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for _i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "res://shot_lily_glow_%03d.png" % int(round(lift * 100.0))
	_vp.get_texture().get_image().save_png(path)
	print("shot  %s" % path)
