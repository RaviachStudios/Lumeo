extends Node
# END-TO-END PROOF THAT THE LAKE'S TWO EVENTS ACTUALLY PAUSE THE GAME.
#
# Everything else about them can be checked by looking (tools/frog_shot.tscn,
# tools/party_shot.tscn) or by inspection (tools/lake_verify.tscn). This one checks
# the half that has no picture and that the first version of the frog got wrong:
# while an event is running, the game must not move.
#
# So it plays the REAL game.gd on the REAL board wearing the lily pads, taps its
# way correctly through eight rounds, and on the two rounds that fire an event it
# HAMMERS THE BOARD WITH TAPS for the whole duration and asserts that nothing at
# all happens — no press registers, the sequence does not grow, the level does not
# advance, and the next round does not start until the lake says the event is over.
#
#   Godot_..._console.exe --path . tools/lake_freeze_test.tscn   (needs a real GPU)
#
# Not headless: it drives a real board with a real camera fit.

const Game := preload("res://game.gd")
const LILY := preload("res://lily_buttons.gd")
const ROUNDS := 8

class StubManager extends Control:
	var game_over_rounds := -1
	func show_game_over(rounds: int) -> void: game_over_rounds = rounds
	func show_contest_detail(_cid: String) -> void: pass
	func show_home() -> void: pass

var _game: Control
var _stub: StubManager
var _dev: MemoryGameUI
var _cam: Camera3D
var _board: Node3D
var _lake: Node3D
var _fails := 0

func _ok(pass_: bool, what: String, detail: String = "") -> void:
	if not pass_:
		_fails += 1
	print("  [%s] %s%s" % ["PASS" if pass_ else "FAIL", what,
		("  -- " + detail) if detail != "" else ""])

func _ready() -> void:
	for _i in 10:
		await get_tree().process_frame          # let CoinsManager load the wallet
	CoinsManager.selected_theme = LILY.THEME_ID
	GameState.set_difficulty("hard")
	_stub = StubManager.new()
	_stub.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_stub)
	_game = Game.new()
	_game.game_manager = _stub
	_stub.add_child(_game)
	await get_tree().create_timer(0.6).timeout

	_dev = _game._wheel as MemoryGameUI
	_ok(_dev != null, "the game built a board")
	if _dev == null:
		get_tree().quit(1)
		return
	var dvp: SubViewport = null
	for c in _dev.get_children():
		if c is SubViewportContainer:
			dvp = (c as SubViewportContainer).get_child(0) as SubViewport
	for c in dvp.get_children():
		if c is Camera3D:
			_cam = c
	_board = _dev.find_child("MemoryGame_UI", true, false) as Node3D
	_lake = _dev._bg_scene
	_ok(_dev.button_skin_id() == LILY.THEME_ID, "wearing the lily pads",
		_dev.button_skin_id())
	_ok(_lake != null and _lake.has_method("start_frog_event"),
		"standing on the Magical Lake")
	if _lake == null:
		get_tree().quit(1)
		return

	for round_no in range(1, ROUNDS + 1):
		if not await _wait_for_input(45.0):
			_ok(false, "round %d reached the player's turn" % round_no, _game._state)
			break
		_ok(_game.level == round_no, "round %d: level counter" % round_no,
			"level=%d" % _game.level)
		var seq: Array = _game.sequence.duplicate()
		for i in seq.size():
			await _tap(int(seq[i]))
			if i < seq.size() - 1:
				await get_tree().create_timer(0.12).timeout
		# The last tap of the round has landed. On rounds 5 and 8 the game must be
		# frozen RIGHT NOW — there is no await between the completion and the freeze,
		# which is the point: nothing can slip in front of it.
		if round_no == 5:
			await _watch("round 5 (the frog)",
				float(_lake.get("_k_end")) + LakeWorld.EV_HOLD)
		elif round_no == 8:
			await _watch("level 8 (the party)", LakeWorld.PT_TOTAL + LakeWorld.EV_HOLD)
		else:
			_ok(_game._state != "event", "round %d: no event, no freeze" % round_no)
		_ok(_stub.game_over_rounds < 0, "round %d: still alive" % round_no)

	print("\n==== %s ====" % ("ALL CHECKS PASSED" if _fails == 0
		else "%d CHECK(S) FAILED" % _fails))
	get_tree().quit(_fails)


# The whole of the assertion. `want` is the freeze the lake asked for.
func _watch(label: String, want: float) -> void:
	_ok(_game._state == "event",
		"%s: the round is frozen the instant it completes" % label, _game._state)
	var lvl: int = _game.level
	var seq: int = _game.sequence.size()
	var pressed: int = _game.player_seq.size()
	var t0 := Time.get_ticks_msec()
	var taps := 0
	var moved := ""
	var ran := false
	var lit := false
	while _game._state == "event" and Time.get_ticks_msec() - t0 < 14000:
		if bool(_lake.call("frog_event_active")) or bool(_lake.call("party_event_active")):
			ran = true
		# Tap a button, hard and often. None of these may reach the game.
		await _tap(taps % _dev._count)
		taps += 1
		if _game.level != lvl:
			moved = "the level advanced"
		elif _game.sequence.size() != seq:
			moved = "the sequence grew"
		elif _game.player_seq.size() != pressed:
			moved = "a press registered"
		elif _game._press_active:
			moved = "the race clock was armed"
		# ...after the player's own last press has finished lighting up. That flash is
		# _press_feedback's 0.18 s decay and it belongs to the tap that STARTED the
		# event; anything lit after it could only be a sequence being played.
		if Time.get_ticks_msec() - t0 > 400:
			for i in _dev._count:
				if _dev._lit[i]:
					lit = true
	var secs := float(Time.get_ticks_msec() - t0) / 1000.0
	_ok(ran, "%s: the lake's own event ran inside the freeze" % label)
	_ok(moved == "", "%s: %d taps during it changed nothing" % [label, taps], moved)
	_ok(not lit, "%s: and no button lit once the press feedback cleared" % label)
	_ok(absf(secs - want) < 0.9, "%s: the freeze lasted the whole event" % label,
		"%.2f s, asked for %.2f" % [secs, want])
	_ok(not bool(_lake.call("frog_event_active"))
			and not bool(_lake.call("party_event_active")),
		"%s: and nothing of the event outlived it" % label)
	_ok(_game.level == lvl and _game.sequence.size() == seq,
		"%s: the round it resumes into is the one it left" % label)


func _screen_of(idx: int) -> Vector2:
	var key: String = _dev._keys[idx]
	var holder := _board.find_child("Button_%s" % key, true, false) as Node3D
	return _cam.unproject_position(holder.position + Vector3(0.0, 0.5, 0.0)) + _dev.position

func _tap(idx: int) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = _screen_of(idx)
	_game._input(ev)
	await get_tree().process_frame

func _wait_for_input(limit: float) -> bool:
	var waited := 0.0
	while _game._state != "input" and waited < limit:
		await get_tree().create_timer(0.05).timeout
		waited += 0.05
	return _game._state == "input"
