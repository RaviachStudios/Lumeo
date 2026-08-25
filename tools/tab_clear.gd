extends Node
# Acceptance probe for the LEVEL badge's placement, at the aspects the game
# ships on. For each board it prints where the badge landed, how far it is from
# the screen edge and from the nearest button, and whether it (or any button)
# collides with game.gd's HUD. Run WITHOUT --headless.
#
# This is the check to re-run after ANY change to the badge's geometry or to a
# board's framing band — the two are coupled through
# LevelTab.reserved_width() / MemoryGameUI._fit_camera.
#
# One overlap is deliberate and is NOT a collision: the near button's black frame
# passes behind the bottom-centre status pill. The boards are fitted into the
# pill's band on purpose (it is the only vertical room left on a 16:9 screen), so
# the rule the probe enforces is the one that matters — no coloured button FACE
# may go behind the pill. `face->pill` is that clearance in pixels.
#
# Note on aspects: the project stretches canvas_items from 1280x720 with
# aspect=expand, so the logical viewport is never narrower than 1280 — a 4:3
# device is 1280x960, not 960x720. Those are the three cases below.

const Game := preload("res://game.gd")

class StubManager extends Control:
	func show_game_over(_rounds: int) -> void: pass
	func show_contest_detail(_cid: String) -> void: pass
	func show_home() -> void: pass

func _ready() -> void:
	for aspect: Vector2 in [Vector2(1280, 720), Vector2(1600, 720), Vector2(1280, 960)]:
		for diff: String in ["easy", "moderate", "hard"]:
			await _probe(diff, aspect)
	get_tree().quit()

# Distance from a point to a rect (0 inside).
func _dist(p: Vector2, r: Rect2) -> float:
	var dx := maxf(maxf(r.position.x - p.x, p.x - r.end.x), 0.0)
	var dy := maxf(maxf(r.position.y - p.y, p.y - r.end.y), 0.0)
	return sqrt(dx * dx + dy * dy)

func _probe(diff: String, vp: Vector2) -> void:
	GameState.difficulty = diff
	GameState.num_colors = 3 if diff == "easy" else (6 if diff == "hard" else 5)
	var stub := StubManager.new()
	stub.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(stub)
	var game := Game.new()
	game.game_manager = stub
	stub.add_child(game)
	await get_tree().process_frame
	game.size = vp
	game._wheel.size = vp
	game._wheel._vp.size = Vector2i(vp)
	game._wheel._on_resized()
	await get_tree().process_frame

	var cam: Camera3D = game._wheel._cam
	var tab: Control = game._wheel._tab
	var tab_r := Rect2(tab.position, tab.size)
	# game.gd's own HUD, in fractions of its 1280x720 design viewport.
	var hud := {
		"watch-ad": Rect2(0.0156, 0.0278, 0.2813, 0.0666),
		"quit": Rect2(0.9438, 0.0278, 0.0406, 0.0722),
		"status": Rect2(0.3438, 0.8833, 0.3125, 0.0723),
	}
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	var in_tab := 0
	var d_tab := INF
	var hud_hits := ""
	var d_pill := INF
	# _collect_fit_points appends the pair (frame rim on the table, raised coloured
	# surface) per sample, in that order — so the odd entries are the FACES. The two
	# are held to different rules against the status pill: see below.
	var pill := Rect2(hud["status"].position * vp, hud["status"].size * vp)
	for i in game._wheel._fit_points.size():
		var s := cam.unproject_position(game._wheel._fit_points[i])
		var is_face: bool = (i % 2) == 1
		mn = mn.min(s)
		mx = mx.max(s)
		if tab_r.has_point(s):
			in_tab += 1
		d_tab = minf(d_tab, _dist(s, tab_r))
		if is_face:
			d_pill = minf(d_pill, _dist(s, pill))
		for name: String in hud:
			var r: Rect2 = hud[name]
			# The status pill is allowed to sit in FRONT of the near button's black
			# frame — that is the one overlap the framing bands spend on purpose, and
			# it is what buys the boards their size and their low seat on the screen.
			# Nothing coloured may go behind it, and neither rim nor face may touch
			# any other HUD control.
			if name == "status" and not is_face:
				continue
			if Rect2(r.position * vp, r.size * vp).has_point(s) and not hud_hits.contains(name):
				hud_hits += name + " "
	for name: String in hud:
		var r: Rect2 = hud[name]
		if Rect2(r.position * vp, r.size * vp).intersects(tab_r):
			hud_hits += "tab/" + name + " "
	print("%-9s %4dx%-4d  board x[%6.1f %6.1f] y[%5.1f %5.1f]   badge %s  edge=%4.1f  nearest button=%5.1f  buttons in badge=%d  face->pill=%5.1f  HUD collisions: %s" % [
		diff, vp.x, vp.y, mn.x, mx.x, mn.y, mx.y, str(tab_r), tab_r.position.x,
		d_tab, in_tab, d_pill, "none" if hud_hits == "" else hud_hits])
	stub.queue_free()
	await get_tree().process_frame
