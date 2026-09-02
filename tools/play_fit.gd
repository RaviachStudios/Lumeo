extends Node
# THE PLAY SCREEN'S FRAMING, measured — every difficulty, every skin, every level,
# every aspect ratio this game can be handed.
#
# It exists because the fit had no answer to one question: does the board actually
# FIT? `MemoryGameUI._fit_camera` places the buttons' silhouette at a chosen height
# with a chosen span, and the two are independent numbers — nothing ever checked
# that a span placed at that height lands inside the viewport. On Ice Kingdom
# (BackgroundScenes.frame_bias) it does not: 0.835 of the height centred at 0.637
# runs to 1.054, so the bottom row of buttons is cropped by the screen edge.
#
# So this measures the three things the player can actually be denied:
#
#   CROP     any part of a button outside the viewport — it cannot be seen, and the
#            part of it that is off-screen cannot be tapped either;
#   COVER    the "Your turn!" pill drawn over a button, which is the same denial by
#            a different route — the HUD is on the 2D layer above the board;
#   STRAY    a HUD control that has left the viewport, which is what happens to the
#            close dome on a resize, because game.gd only re-lays the board.
#
# Everything is measured through the REAL game — the real game.gd, its real HUD,
# the real board classes, the real skin resolution — inside a SubViewport of the
# size under test, because a fit that is correct at 1280x720 and wrong at 1170x2532
# is not a fit.
#
#   Godot_..._console.exe --path . tools/play_fit.tscn            # the full sweep
#   Godot_..._console.exe --path . tools/play_fit.tscn -- quick   # one size
#
# Run WITHOUT --headless: it projects through a live camera.

const Game := preload("res://game.gd")

# The sizes. A desktop 16:9, a tall phone, a very tall phone, a tablet, a landscape
# phone and a small window — the point of the list is that the band the buttons
# live in is a FRACTION of the height in some of them and a pixel lane in others,
# and a fit that only ever ran at 16:9 has never met the difference.
const SIZES: Array = [
	[Vector2i(1280, 720), "16:9 desktop"],
	[Vector2i(720, 1280), "9:16 phone"],
	[Vector2i(1080, 2160), "9:18 tall phone"],
	[Vector2i(1170, 2532), "iPhone 13"],
	[Vector2i(1536, 2048), "3:4 tablet"],
	[Vector2i(960, 540), "small window"],
]
const DIFFS: Array = ["easy", "moderate", "hard"]
# A plain background with no framing preference at all, and BOTH of the ones that
# have one — Ice Kingdom, whose horizon is the tightest top constraint in the
# game, and Royal Casino, whose rail is the other. The band has to satisfy a
# background that asks for nothing and two that ask for opposite amounts.
const SKINS: Array = ["bg_arcade", "world_ice", "world_casino"]
const LEVELS: Array = [1, 12, 27]

var _pass := 0
var _fail := 0
var _notes: Array[String] = []


class StubManager extends Control:
	func show_game_over(_rounds: int) -> void: pass
	func show_contest_detail(_cid: String) -> void: pass
	func show_home() -> void: pass


func _ok(cond: bool, what: String, detail: String = "") -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		_notes.append("  FAIL  %s   [%s]" % [what, detail])


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var quick := args.size() > 0 and String(args[0]) == "quick"
	var sizes: Array = [SIZES[0]] if quick else SIZES
	for _i in 30:
		await get_tree().process_frame
	CoinsManager.simon_mode = CoinsManager.SIMON_MODE_MANUAL
	CoinsManager.selected_skin = ""
	print("=== the play screen's framing ===")
	for skin: String in SKINS:
		for diff: String in DIFFS:
			for entry: Array in sizes:
				await _case(skin, diff, entry[0], String(entry[1]))
	print("")
	for n in _notes:
		print(n)
	print("\n%s  (%d passed, %d failed)"
		% ["PASS" if _fail == 0 else "FAIL", _pass, _fail])
	get_tree().quit(0 if _fail == 0 else 1)


func _case(skin: String, diff: String, vps: Vector2i, label: String) -> void:
	CoinsManager.selected_theme = skin
	GameState.difficulty = diff
	# GameState's middle difficulty is spelled "moderate"; an unknown string falls
	# through its match to the THREE-button board silently, so a sweep written with
	# "medium" tests Easy twice and reports it as a pass.
	GameState.num_colors = 3 if diff == "easy" else (6 if diff == "hard" else 5)
	BackgroundManager.set_active(true)
	var vp := SubViewport.new()
	vp.size = vps
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var stub := StubManager.new()
	stub.set_anchors_preset(Control.PRESET_FULL_RECT)
	stub.size = Vector2(vps)
	vp.add_child(stub)
	var game := Game.new()
	game.game_manager = stub
	stub.add_child(game)
	game.set_anchors_preset(Control.PRESET_FULL_RECT)
	game.size = Vector2(vps)
	for _i in 26:
		await get_tree().process_frame
	for lv: int in LEVELS:
		if game._wheel != null:
			game._wheel.set_level(lv)
		game._set_status("Your turn!")
		for _i in 3:
			await get_tree().process_frame
		_measure(game, Vector2(vps), "%s %s %s L%d" % [skin, diff, label, lv])
	vp.queue_free()
	await get_tree().process_frame


# The buttons' own extent on screen, from the SAME points the fit is solved
# against (MemoryGameUI._collect_fit_points): each button's frame rim and the top
# edge of its raised surface. Anything outside this is not a button.
func _button_rects(dev: Node) -> Array:
	var out: Array = []
	var cam: Camera3D = dev.get("_cam")
	var centres: PackedVector2Array = dev.get("_centres")
	var count: int = dev.get("_count")
	if cam == null:
		return out
	for idx in count:
		var c: Vector2 = centres[idx]
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		for i in 24:
			var a := TAU * float(i) / 24.0
			for p: Vector3 in [
					Vector3(c.x + cos(a) * 1.0, 0.0, c.y + sin(a) * 1.0),
					Vector3(c.x + cos(a) * 0.745, 0.525, c.y + sin(a) * 0.745)]:
				if cam.is_position_behind(p):
					continue
				var s := cam.unproject_position(p)
				mn = mn.min(s)
				mx = mx.max(s)
		if mn.x <= mx.x:
			out.append(Rect2(mn, mx - mn))
	return out


func _measure(game: Node, vp: Vector2, tag: String) -> void:
	var dev: Node = game.get("_wheel")
	if dev == null:
		_ok(false, "%s: the board was built" % tag)
		return
	var rects := _button_rects(dev)
	_ok(rects.size() > 0, "%s: buttons projected" % tag, str(rects.size()))
	if rects.is_empty():
		return
	# --- CROP. Every button, whole, inside the viewport.
	var worst_bot := -INF
	var worst_top := INF
	var worst_l := INF
	var worst_r := -INF
	for r: Rect2 in rects:
		worst_top = minf(worst_top, r.position.y)
		worst_bot = maxf(worst_bot, r.end.y)
		worst_l = minf(worst_l, r.position.x)
		worst_r = maxf(worst_r, r.end.x)
	_ok(worst_bot <= vp.y, "%s: no button is cropped at the BOTTOM" % tag,
		"lowest %.0f px vs viewport %.0f" % [worst_bot, vp.y])
	_ok(worst_top >= 0.0, "%s: no button is cropped at the TOP" % tag,
		"highest %.0f px" % worst_top)
	_ok(worst_l >= 0.0 and worst_r <= vp.x, "%s: no button is cropped at a SIDE" % tag,
		"x %.0f..%.0f vs %.0f" % [worst_l, worst_r, vp.x])

	# --- COVER. The status pill is drawn over the board, so a pill that overlaps a
	#     button takes that button off the player exactly as an edge would.
	var pill: Control = game.get("_status_panel")
	if pill != null and pill.visible:
		var pr := Rect2(pill.position, pill.size)
		var hit := 0
		for r: Rect2 in rects:
			if pr.intersects(r):
				hit += 1
		_ok(hit == 0, "%s: 'Your turn!' covers no button" % tag,
			"%d of %d, pill y %.0f..%.0f" % [hit, rects.size(), pr.position.y, pr.end.y])
		_ok(pr.end.y <= vp.y and pr.position.x >= 0.0 and pr.end.x <= vp.x,
			"%s: 'Your turn!' is inside the viewport" % tag,
			"y %.0f..%.0f, x %.0f..%.0f" % [pr.position.y, pr.end.y,
				pr.position.x, pr.end.x])

	# --- STRAY. The close dome and the LEVEL badge, inside the viewport.
	var quit_btn: Control = game.get("_quit_btn")
	if quit_btn != null:
		var qr := Rect2(quit_btn.position, quit_btn.size)
		_ok(qr.position.x >= 0.0 and qr.position.y >= 0.0
				and qr.end.x <= vp.x and qr.end.y <= vp.y,
			"%s: the close button is inside the viewport" % tag,
			"x %.0f..%.0f y %.0f..%.0f vs %.0fx%.0f"
				% [qr.position.x, qr.end.x, qr.position.y, qr.end.y, vp.x, vp.y])
		var over := 0
		for r: Rect2 in rects:
			if qr.intersects(r):
				over += 1
		_ok(over == 0, "%s: the close button covers no button" % tag, str(over))
	var tab: Control = dev.get("_tab")
	if tab != null and tab.visible:
		var tr := Rect2(tab.position, tab.size)
		_ok(tr.position.x >= 0.0 and tr.position.y >= 0.0
				and tr.end.x <= vp.x and tr.end.y <= vp.y,
			"%s: the LEVEL badge is inside the viewport" % tag,
			"x %.0f..%.0f y %.0f..%.0f" % [tr.position.x, tr.end.x,
				tr.position.y, tr.end.y])
		var lo := 0
		for r: Rect2 in rects:
			if tr.intersects(r):
				lo += 1
		_ok(lo == 0, "%s: the LEVEL badge covers no button" % tag, str(lo))
