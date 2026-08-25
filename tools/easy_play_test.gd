extends Node
# End-to-end play test for EASY on the three-button board: drives the REAL game.gd
# through synthetic taps at each button's on-screen position, so the whole path is
# exercised — tap -> EasyGameUI.segment_at_point -> game.gd._player_pressed ->
# round progression -> loss. Nothing here reaches into the game's state to make a
# move; it only reads `sequence` to know where to tap, exactly as a player's eyes do.
#   Godot_..._console.exe --path . tools/easy_play_test.tscn      (needs a real GPU)
#
# This is tools/hard_play_test.gd with the difficulty and the button count
# swapped; everything it drives is the shared code path, which is the point.

const Game := preload("res://game.gd")
const ROUNDS := 8

class StubManager extends Control:
	var game_over_rounds := -1
	func show_game_over(rounds: int) -> void: game_over_rounds = rounds
	func show_contest_detail(_cid: String) -> void: pass
	func show_home() -> void: pass

var _game: Control
var _stub: StubManager
var _dev: EasyGameUI
var _cam: Camera3D
var _board: Node3D
var _fails := 0

func _ok(pass_: bool, what: String, detail: String = "") -> void:
	if not pass_:
		_fails += 1
	print("  [%s] %s%s" % ["PASS" if pass_ else "FAIL", what, ("  -- " + detail) if detail != "" else ""])

func _ready() -> void:
	GameState.set_difficulty("easy")
	_ok(GameState.num_colors == 3, "easy is a three-colour game", str(GameState.num_colors))
	_stub = StubManager.new()
	_stub.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_stub)
	_game = Game.new()
	_game.game_manager = _stub
	_stub.add_child(_game)
	await get_tree().create_timer(0.5).timeout

	_dev = _game._wheel as EasyGameUI
	_ok(_dev != null, "easy plays on the three-button board")
	_ok(not (_game._wheel is SimonWheel), "and NOT on the old four-colour wheel")
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

	print("\n-- playing %d rounds correctly --" % ROUNDS)
	for round_no in range(1, ROUNDS + 1):
		if not await _wait_for_input():
			_ok(false, "round %d reached the player's turn" % round_no)
			break
		_ok(_game.level == round_no, "round %d: level counter" % round_no, "level=%d" % _game.level)
		_ok(_game.sequence.size() == round_no, "round %d: sequence grew by one" % round_no,
			str(_game.sequence))
		_ok(_dev._pill_number.text == str(round_no), "round %d: the pill shows it" % round_no,
			_dev._pill_number.text)
		var seq: Array = _game.sequence.duplicate()
		for step: int in seq:
			await _tap(step)
			await get_tree().create_timer(0.12).timeout
		_ok(_game.player_seq.size() == 0 or _game.player_seq.size() == seq.size(),
			"round %d: every tap was accepted" % round_no,
			"%d of %d" % [_game.player_seq.size(), seq.size()])
		_ok(_stub.game_over_rounds < 0, "round %d: still alive" % round_no)

	print("\n-- every colour is reachable --")
	if await _wait_for_input():
		# Tap all three in turn; only the first matters to the game, but each tap
		# must resolve to the button it landed on.
		for i in 3:
			var got := _dev.segment_at_point(_screen_of(i) - _dev.position)
			_ok(got == i, "a tap on %s resolves to index %d" % [_dev._keys[i], i], "got %d" % got)

	print("\n-- a wrong press ends the game --")
	var seq: Array = _game.sequence.duplicate()
	var wrong: int = (int(seq[0]) + 1) % 3
	var level_at_death: int = _game.level
	await _tap(wrong)
	var waited := 0.0
	while _stub.game_over_rounds < 0 and waited < 6.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	_ok(_stub.game_over_rounds >= 0, "the game ended")
	_ok(_stub.game_over_rounds == level_at_death - 1,
		"scored the rounds actually completed", "reported %d, died on round %d" % [
			_stub.game_over_rounds, level_at_death])

	print("\n==== ", "ALL CHECKS PASSED" if _fails == 0 else "%d CHECK(S) FAILED" % _fails, " ====")
	get_tree().quit(_fails)

# Where button `idx` sits on screen, in the game's viewport coordinates.
func _screen_of(idx: int) -> Vector2:
	var key: String = _dev._keys[idx]
	var holder := _board.find_child("Button_%s" % key, true, false) as Node3D
	return _cam.unproject_position(holder.position + Vector3(0.0, 0.5, 0.0)) + _dev.position

# A real tap: the same InputEventMouseButton the OS would deliver, pushed through
# game.gd's own _input handler.
func _tap(idx: int) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = _screen_of(idx)
	_game._input(ev)
	await get_tree().process_frame

func _wait_for_input() -> bool:
	var waited := 0.0
	while _game._state != "input" and waited < 25.0:
		await get_tree().create_timer(0.05).timeout
		waited += 0.05
	return _game._state == "input"
