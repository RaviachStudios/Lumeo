extends Node
# Filmstrip harness for the ROYAL CASINO's events. Renders one casino event as a
# grid of beats through the REAL gameplay path — the real device, the real camera
# fit, the real chips, the real table — so the choreography can be read rather than
# guessed at.
#
# The event's clock is advanced BY HAND at a fixed 60 Hz between captures rather
# than left to run in real time, so every beat lands on exactly the second it is
# labelled with and a slow frame cannot move the picture.
#
# Run WITHOUT --headless:
#
#   Godot_..._console.exe --path . tools/casino_event_shot.tscn -- <event> [board]
#
#     event  community | roulette | cascade | flip | deal | lights | flush | all
#     board  easy | medium | hard          (default hard)
#
# Writes res://shot_cev_<event>_<board>.png — a 3x4 grid of the twelve beats,
# labelled with the time each was taken at. Delete them when done.

const CHIPS := preload("res://chip_buttons.gd")
const SHOT_W := 1280
const SHOT_H := 720
const CELL_W := 426
const CELL_H := 240
const COLS := 3
const ROWS := 4

const KINDS := {
	"community": 0, "roulette": 1, "cascade": 2, "flip": 3, "deal": 4,
	"lights": 5, "flush": 6,
}

var _dev: MemoryGameUI
var _vp: SubViewport
var _dev_vp: SubViewport
var _world: Node3D
var _ev: Node
var _board_name := "hard"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var which := String(args[0]) if args.size() > 0 else "flush"
	_board_name = String(args[1]) if args.size() > 1 else "hard"

	for _i in 10:
		await get_tree().process_frame
	CoinsManager.selected_theme = CHIPS.THEME_ID

	_vp = SubViewport.new()
	_vp.size = Vector2i(SHOT_W, SHOT_H)
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	var bg := ColorRect.new()
	bg.color = BackgroundScenes.backdrop_color(CHIPS.THEME_ID).linear_to_srgb()
	bg.size = Vector2(SHOT_W, SHOT_H)
	_vp.add_child(bg)

	match _board_name:
		"easy": _dev = EasyGameUI.new()
		"medium": _dev = MemoryGameUI.new()
		_: _dev = HardGameUI.new()
	_dev.input_enabled = false
	_dev.size = Vector2(SHOT_W, SHOT_H)
	_vp.add_child(_dev)
	await get_tree().process_frame
	_dev.configure(_dev._count, [])
	_dev.set_level(24)
	for c in _dev.get_children():
		if c is SubViewportContainer:
			_dev_vp = (c as SubViewportContainer).get_child(0) as SubViewport
	_world = _dev._bg_scene
	_ev = _world.get_node_or_null("EventsRoot")
	if _ev == null or not bool(_ev.get("_lane_ok")):
		print("no lane on %s — nothing to shoot" % _board_name)
		get_tree().quit(1)
		return
	for _i in 20:
		await get_tree().process_frame

	var list: Array = KINDS.keys() if which == "all" else [which]
	for nm: String in list:
		await _strip(nm)
	get_tree().quit()


func _strip(nm: String) -> void:
	if not KINDS.has(nm):
		print("unknown event '%s'" % nm)
		return
	var kind: int = KINDS[nm]
	# Started through the real entry points, so the gating and the tiering are the
	# ones that ship. The round is chosen to land on tier 2 (the most crowded case,
	# which is the one worth looking at) and the kind is forced afterwards.
	var secs := 0.0
	if kind == 6:
		secs = float(_ev.call("start_flush", 8))
	else:
		# Draw until the wanted event comes up. Cheaper than reaching in, and it
		# proves the picker can reach it.
		#
		# Keyed off `active()` and NOT off the returned freeze: the small events
		# deliberately return 0.0 (they do not stop the game — see
		# CasinoEvents.start_event), so a loop that tested the return value drew
		# nothing at all and reported "could not draw" for all six.
		var got := false
		for round_no in range(24, 24 + 3 * 40, 3):
			_ev.call("start_event", round_no)
			if bool(_ev.call("active")):
				if int(_ev.get("_kind")) == kind:
					got = true
					break
				_ev.call("stop")
		if not got:
			print("could not draw '%s'" % nm)
			return
	var total: float = float(_ev.get("_len"))
	# `secs` is what the event asked the GAME for, which for everything but the Royal
	# Flush is deliberately zero — see CasinoEvents.start_event.
	print("--- %s on %s: %.2f s long, asks the game to freeze %.2f ---"
		% [nm, _board_name, total, secs])

	var grid := Image.create(CELL_W * COLS, CELL_H * ROWS, false, Image.FORMAT_RGBA8)
	grid.fill(Color(0.04, 0.04, 0.05))
	var beats := COLS * ROWS
	var clock := 0.0
	for i in beats:
		var want: float = total * float(i) / float(beats - 1)
		# Advance in real 60 Hz steps so the event sees the frame times it would in
		# play — the sparks are integrated, so stepping straight to `want` would
		# give a different picture from the one the player gets.
		while clock < want - 0.0001:
			var dt: float = minf(1.0 / 60.0, want - clock)
			_ev.call("tick", dt)
			clock += dt
		_dev_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		for _f in 2:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := _vp.get_texture().get_image()
		img.resize(CELL_W, CELL_H, Image.INTERPOLATE_LANCZOS)
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		grid.blit_rect(img, Rect2i(0, 0, CELL_W, CELL_H),
			Vector2i((i % COLS) * CELL_W, int(i / COLS) * CELL_H))
		print("   beat %2d  t=%.2f  cards %d  chips %d  sparks %d  ball %s" % [
			i, want, _count("Cards"), _count("Chips"), _count("Sparks"),
			_ball_note()])
	var path := "res://shot_cev_%s_%s.png" % [nm, _board_name]
	grid.save_png(path)
	print("   -> %s" % path)
	# ...and one FULL-RESOLUTION frame, because the grid is a choreography check and
	# cannot answer the question the card faces actually raise: can the player read
	# the rank. Taken at the beat the event is most itself.
	await _hero(nm, total)
	_ev.call("stop")
	for _f in 2:
		await get_tree().process_frame


# The moment each event is worth looking at closely, as a fraction of its length.
const HERO_AT := {
	"community": 0.55, "roulette": 0.62, "cascade": 0.55, "flip": 0.55,
	"deal": 0.45, "lights": 0.45, "flush": 0.68,
}


func _hero(nm: String, total: float) -> void:
	_ev.call("stop")
	for _f in 2:
		await get_tree().process_frame
	if nm == "flush":
		_ev.call("start_flush", 16)
	else:
		for round_no in range(24, 24 + 3 * 40, 3):
			_ev.call("start_event", round_no)
			if bool(_ev.call("active")):
				if int(_ev.get("_kind")) == int(KINDS[nm]):
					break
				_ev.call("stop")
	var want: float = total * float(HERO_AT.get(nm, 0.5))
	var clock := 0.0
	while clock < want - 0.0001:
		var dt: float = minf(1.0 / 60.0, want - clock)
		_ev.call("tick", dt)
		clock += dt
	_dev_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for _f in 2:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "res://shot_cev_%s_%s_hero.png" % [nm, _board_name]
	_vp.get_texture().get_image().save_png(path)
	print("   -> %s  (t=%.2f)" % [path, want])


func _count(nm: String) -> int:
	var mmi := _ev.get_node_or_null(nm) as MultiMeshInstance3D
	return 0 if mmi == null else mmi.multimesh.instance_count


# The ball's size ON SCREEN, because "is it visible" is a pixel question and every
# guess at it so far has been wrong.
func _ball_note() -> String:
	var b := _ev.get_node_or_null("Ball") as MeshInstance3D
	if b == null or not b.visible:
		return "no"
	var cam: Camera3D = null
	for c in _dev_vp.get_children():
		if c is Camera3D:
			cam = c
	if cam == null:
		return "yes"
	var p := b.global_position
	var r: float = (b.mesh as SphereMesh).radius * b.scale.x
	var a := cam.unproject_position(p - cam.global_transform.basis.x * r)
	var c2 := cam.unproject_position(p + cam.global_transform.basis.x * r)
	return "yes @(%d,%d) %.1f px" % [int((a.x + c2.x) * 0.5),
		int((a.y + c2.y) * 0.5), a.distance_to(c2)]
