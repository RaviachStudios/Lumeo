extends Node
# END-TO-END PROOF ON THE REAL GAME that the ROYAL CASINO's events behave the way
# the design says they do — which for this skin is the OPPOSITE claim to Ice
# Kingdom's and the Magical Lake's, and is therefore worth proving on the real
# game.gd rather than on a duration returned by a background:
#
#   * every third completed round starts a casino event, and THE GAME IS NOT
#     FROZEN — the sequence plays back, presses register, the round advances, all
#     while cards are sliding across the back of the table;
#   * EXCEPT rounds 3 and 6 of every eight, where the croupier deals into the hand
#     in the MIDDLE of the table and the round is frozen for the length of the
#     throw — the exception that lets those cards cross the ring at all;
#   * level 8 IS frozen, for the whole Royal Flush, and taps during it do nothing;
#   * and the "ROYAL FLUSH!" banner is game.gd's own, drawn over the whole screen,
#     so nothing that photographs the board's own viewport can see it — this is the
#     only harness here that can.
#
#   Godot_..._console.exe --path . tools/casino_play_test.tscn -- [board] [banner]
#
# `-- hard banner` skips the nine rounds and photographs the banner alone: playing to
# level 8 takes minutes per board, and "does the phrase clear the buttons on a board
# with three of them" does not need a game played to answer it.
#
# Needs a real GPU. Writes res://shot_casfz_*.png. Delete them when done.

const Game := preload("res://game.gd")
const CHIPS := preload("res://chip_buttons.gd")
const ROUNDS := 9

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
var _table: Node3D
var _ev: Node
var _fails := 0

func _ok(pass_: bool, what: String, detail: String = "") -> void:
	if not pass_:
		_fails += 1
	print("  [%s] %s%s" % ["PASS" if pass_ else "FAIL", what,
		("  -- " + detail) if detail != "" else ""])

func _ready() -> void:
	for _i in 10:
		await get_tree().process_frame          # let CoinsManager load the wallet
	CoinsManager.selected_theme = CHIPS.THEME_ID
	var args := OS.get_cmdline_user_args()
	var which := String(args[0]) if args.size() > 0 else "hard"
	# GameState's middle difficulty is called "moderate", and an unknown string falls
	# through its match to the three-button board WITHOUT complaining — so "medium"
	# would silently test Easy twice.
	if which == "medium":
		which = "moderate"
	GameState.set_difficulty(which)
	print("difficulty: %s" % GameState.difficulty)
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
	_table = _dev._bg_scene
	_ev = null if _table == null else _table.get_node_or_null("EventsRoot")
	_ok(_dev.button_skin_id() == CHIPS.THEME_ID, "wearing the poker chips",
		_dev.button_skin_id())
	_ok(_table != null and _table.has_method("start_table_event"),
		"standing on the poker table")
	_ok(_ev != null and bool(_ev.get("_lane_ok")), "the lane solved on this board")
	if _table == null or _ev == null:
		get_tree().quit(1)
		return

	if args.has("banner"):
		await _banner()
		print("\n==== %s ====" % ("ALL CHECKS PASSED" if _fails == 0
			else "%d CHECK(S) FAILED" % _fails))
		get_tree().quit(_fails)
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
		# The last tap of the round has landed. There is no await in game.gd between
		# the completion and the background's milestone hook, so whatever is true now
		# is what that hook did.
		if round_no == 8:
			await _watch_frozen()
		elif round_no % CasinoEvents.HAND_CYCLE == CasinoEvents.HAND_AT_LOW \
				or round_no % CasinoEvents.HAND_CYCLE == CasinoEvents.HAND_AT_KING:
			await _watch_deal(round_no)
		elif round_no % 3 == 0:
			await _watch_free(round_no)
		else:
			_ok(not bool(_ev.call("active")),
				"round %d: no event on a non-multiple of three" % round_no)
			_ok(_game._state != "event", "round %d: and no freeze" % round_no)
		_ok(_stub.game_over_rounds < 0, "round %d: still alive" % round_no)

	print("\n==== %s ====" % ("ALL CHECKS PASSED" if _fails == 0
		else "%d CHECK(S) FAILED" % _fails))
	get_tree().quit(_fails)


# THE CLAIM THIS HARNESS EXISTS FOR. Every third round starts an event and the game
# carries straight on: no freeze, and the next round's sequence plays back while the
# cards are still on the table.
func _watch_free(round_no: int) -> void:
	_ok(bool(_ev.call("active")),
		"round %d: an event started" % round_no)
	_ok(_game._state != "event",
		"round %d: AND THE GAME IS NOT FROZEN" % round_no, _game._state)
	var lvl: int = _game.level
	var t0 := Time.get_ticks_msec()
	var shot_done := false
	# Give it the length of the event, then check the game moved on underneath it.
	while Time.get_ticks_msec() - t0 < 2600:
		if not shot_done and Time.get_ticks_msec() - t0 > 900:
			shot_done = true
			await _save("free%d" % round_no)
		await get_tree().process_frame
	_ok(_game.level > lvl or _game._state == "playback" or _game._state == "input",
		"round %d: the game advanced while the event ran" % round_no,
		"level %d -> %d, state %s" % [lvl, _game.level, _game._state])


# ROUNDS 3 AND 6 — the croupier dealing into the hand, which is the OTHER thing on
# this table that stops the round, and the reason the "every third round does not
# freeze" claim above is not the whole story any more.
#
# The distinction is worth spelling out because it is the whole design: the six lane
# events play ACROSS THE BACK of the table, above the buttons, so the next round is
# free to start underneath them; the hand is dealt INTO THE MIDDLE, over the play
# area, and a card thrown over a chip the player is trying to press would be exactly
# the bug this skin refuses to have. So these two rounds freeze — briefly — and the
# freeze is what buys the flight the right to cross the ring at all.
func _watch_deal(round_no: int) -> void:
	_ok(bool(_ev.call("active")), "round %d: the deal started" % round_no)
	_ok(int(_ev.get("_kind")) == CasinoEvents.EV_HAND,
		"round %d: ...and it is the HAND, not a lane event" % round_no,
		"kind %d" % int(_ev.get("_kind")))
	_ok(_game._state == "event",
		"round %d: the round is frozen for it" % round_no, _game._state)
	# THE CARDS EXIST AT THE START, IN THE AIR. This is the regression guard for the
	# bug that made the whole deal invisible: they used to be created and then wiped
	# by `_begin` on the same frame, so the milestone put three cards on the felt
	# without ever showing one move.
	var cards: Array = _ev.get("_cards")
	_ok(cards.size() > 0, "round %d: ...with cards in flight" % round_no,
		"%d" % cards.size())
	var lvl: int = _game.level
	# The round that just COMPLETED is still holding its own presses — player_seq is
	# cleared by _next_round, which is exactly what the freeze is stopping — so the
	# baseline is what is there now and not zero. (`> 0` here reported a press on the
	# first frame of every deal.)
	var pressed: int = _game.player_seq.size()
	var seq: int = _game.sequence.size()
	var taps := 0
	var moved := ""
	var t0 := Time.get_ticks_msec()
	while _game._state == "event" and Time.get_ticks_msec() - t0 < 9000:
		await _tap(taps % _dev._count)
		taps += 1
		if _game.level != lvl:
			moved = "the level advanced"
		elif _game.sequence.size() != seq:
			moved = "the sequence grew"
		elif _game.player_seq.size() != pressed:
			moved = "a press registered"
	var secs := float(Time.get_ticks_msec() - t0) / 1000.0
	_ok(moved == "", "round %d: %d taps during it changed nothing" % [round_no, taps],
		moved)
	# ...for AS LONG AS THE DEAL ASKED FOR, and not a beat longer. Held against the
	# event's own promised duration rather than a number typed here: a three-card
	# deal is three complete animations end to end (the arm is back at rest before
	# it reaches for the next card), so this moves whenever the clip is retimed and
	# a fixed ceiling would only ever be a stale one.
	var owed: float = CasinoEvents.T_HAND_LOW 		if round_no % CasinoEvents.HAND_CYCLE == CasinoEvents.HAND_AT_LOW 		else CasinoEvents.T_HAND_KING
	_ok(secs > owed * 0.6 and secs < owed + 0.45,
		"round %d: the freeze lasted the deal and no longer" % round_no,
		"%.2f s, the deal asked for %.2f" % [secs, owed])
	_ok(not bool(_ev.call("active")),
		"round %d: nothing of the deal outlived it" % round_no)
	# ...and what it left behind is the row the player is collecting.
	var want := 3 if round_no % CasinoEvents.HAND_CYCLE == CasinoEvents.HAND_AT_LOW \
		else 4
	_ok(_ev.get("_hand").size() == want,
		"round %d: the hand is %d cards" % [round_no, want],
		"%d" % _ev.get("_hand").size())


# ...and level 8, which is the one that DOES stop the game.
func _watch_frozen() -> void:
	_ok(_game._state == "event",
		"level 8: the round is frozen the instant it completes", _game._state)
	var lvl: int = _game.level
	var seq: int = _game.sequence.size()
	var pressed: int = _game.player_seq.size()
	var t0 := Time.get_ticks_msec()
	var taps := 0
	var moved := ""
	var ran := false
	var shot_done := false
	while _game._state == "event" and Time.get_ticks_msec() - t0 < 14000:
		if bool(_ev.call("active")):
			ran = true
		# The banner pops with the Ace at about 2.7 s.
		if not shot_done and Time.get_ticks_msec() - t0 > 2900:
			shot_done = true
			await _save("royalflush")
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
	var secs := float(Time.get_ticks_msec() - t0) / 1000.0
	var want: float = CasinoEvents.T_FLUSH + CasinoEvents.HOLD
	_ok(ran, "level 8: the Royal Flush ran inside the freeze")
	_ok(moved == "", "level 8: %d taps during it changed nothing" % taps, moved)
	_ok(absf(secs - want) < 0.9, "level 8: the freeze lasted the whole hand",
		"%.2f s, asked for %.2f" % [secs, want])
	_ok(not bool(_ev.call("active")),
		"level 8: and nothing of the hand outlived it")


# The banner alone, over a resting table. The freeze is not exercised here — the
# rounds above are what prove that — so this is only the composition: whether twelve
# characters at this size clear the chips on a board with three of them.
func _banner() -> void:
	print("\n-- the banner, at rest --")
	_table.call("start_royal_flush", 8)
	_game._show_royal_flush_text()
	await get_tree().create_timer(2.95).timeout
	await _save("banner")
	await get_tree().create_timer(0.7).timeout
	await _save("banner_hold")
	await get_tree().create_timer(1.4).timeout
	var left := 0
	for c in _game.get_children():
		if c is Control and not (c is SubViewportContainer):
			for d in (c as Control).get_children():
				if d is Label and String((d as Label).text).contains("ROYAL"):
					left += 1
	_ok(left == 0, "the banner frees itself when it is done", str(left))


func _save(tag: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(
		"res://shot_casfz_%s.png" % tag)
	print("  shot  res://shot_casfz_%s.png" % tag)


func _screen_of(idx: int) -> Vector2:
	var key: String = _dev._keys[idx]
	var holder := _board.find_child("Button_%s" % key, true, false) as Node3D
	return _cam.unproject_position(holder.position + Vector3(0.0, 0.5, 0.0)) \
		+ _dev.position

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
