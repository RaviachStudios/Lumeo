extends Node
# END-TO-END PROOF THAT ICE KINGDOM'S TWO MILESTONE EVENTS ACTUALLY PAUSE THE GAME,
# and the only harness here that renders the BANNERS — they are game.gd's, drawn
# over the whole screen, so nothing that photographs the board's own viewport
# (tools/ice_event.tscn) can see them.
#
# It is the lake's freeze test with a different skin equipped and different rounds
# watched, and it is deliberately the same shape: the brief for both events ends
# with "the game must remain paused / non-interactive for the ENTIRE duration", and
# that is a claim about the REAL game.gd on the REAL board, not about a duration
# returned by a background.
#
# So it plays the real game, taps its way correctly through nine rounds, and on the
# three that fire an event it HAMMERS THE BOARD WITH TAPS for the whole duration
# and asserts that nothing happens at all — no press registers, the sequence does
# not grow, the level does not advance, no button lights, the race clock is not
# armed, and the next round does not begin until the background says it is done.
#
#   Godot_..._console.exe --path . tools/ice_freeze_test.tscn   (needs a real GPU)
#
# Rounds 3, 6 and 9 are the crystal burst; round 8 is the aurora celebration.
# Writes res://shot_icefz_*.png. Delete them when done.

const Game := preload("res://game.gd")
const ICE := preload("res://ice_buttons.gd")
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
var _ice: Node3D
var _fails := 0

func _ok(pass_: bool, what: String, detail: String = "") -> void:
	if not pass_:
		_fails += 1
	print("  [%s] %s%s" % ["PASS" if pass_ else "FAIL", what,
		("  -- " + detail) if detail != "" else ""])

func _ready() -> void:
	for _i in 10:
		await get_tree().process_frame          # let CoinsManager load the wallet
	CoinsManager.selected_theme = ICE.THEME_ID
	var which := "hard"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		which = String(args[0])
	# GameState's middle difficulty is called "moderate", and an unknown string
	# falls through its match to the three-button board WITHOUT complaining — so
	# `-- medium` silently tested Easy twice. Accepted here as an alias because
	# every other Ice Kingdom harness spells it "medium".
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
	_ice = _dev._bg_scene
	_ok(_dev.button_skin_id() == ICE.THEME_ID, "wearing the snowflakes",
		_dev.button_skin_id())
	_ok(_ice != null and _ice.has_method("start_streak_event"),
		"standing on Ice Kingdom")
	if _ice == null:
		get_tree().quit(1)
		return

	# `-- <board> banners` skips the nine rounds and photographs the two banners
	# alone. Playing to level 8 takes about four minutes of real time per board, and
	# the question "does the phrase fit over THREE buttons instead of six" does not
	# need a game played to answer it.
	if args.size() > 1 and String(args[1]) == "banners":
		await _banners()
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
		# The last tap of the round has landed. On 3, 6, 8 and 9 the game must be
		# frozen RIGHT NOW — there is no await between the completion and the freeze,
		# which is the point: nothing can slip in front of it.
		if round_no == 8:
			await _watch("level 8 (the aurora)", IceWorld.PT_TOTAL, "veins")
		elif round_no % 3 == 0:
			await _watch("level %d (the burst)" % round_no, IceWorld.EV_TOTAL,
				"streak%d" % round_no)
		else:
			_ok(_game._state != "event", "round %d: no event, no freeze" % round_no)
		_ok(_stub.game_over_rounds < 0, "round %d: still alive" % round_no)

	print("\n==== %s ====" % ("ALL CHECKS PASSED" if _fails == 0
		else "%d CHECK(S) FAILED" % _fails))
	get_tree().quit(_fails)


# Both banners at their fullest, over a resting board. The freeze is not exercised
# here — the rounds above are what proves that — so this is only the composition:
# whether the phrase clears the buttons on a board with a different number of them.
func _banners() -> void:
	print("\n-- the banners, at rest --")
	_game._show_frozen_streak_text(6)
	await get_tree().create_timer(0.55).timeout
	await _save("banner_streak")
	await get_tree().create_timer(1.2).timeout
	_game._show_ice_veins_text()
	await get_tree().create_timer(2.7).timeout
	await _save("banner_veins")
	await get_tree().create_timer(2.5).timeout
	var left := 0
	for c in _game.get_children():
		if c is Control and (c as Control).get_child_count() > 0 \
				and not (c is SubViewportContainer):
			for d in c.get_children():
				if d is Label and String((d as Label).text).contains("VEINS"):
					left += 1
	_ok(left == 0, "both banners free themselves when they are done", str(left))


# The whole of the assertion. `want` is the freeze the background asked for; `shot`
# is what to name the frame grabbed from the middle of it, which is where the
# banner is at full size.
func _watch(label: String, want: float, shot: String) -> void:
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
	var shot_at := int(want * 1000.0 * 0.55)
	var shot_done := false
	while _game._state == "event" and Time.get_ticks_msec() - t0 < 14000:
		if bool(_ice.call("event_active")):
			ran = true
		if not shot_done and Time.get_ticks_msec() - t0 > shot_at:
			shot_done = true
			await _save(shot)
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
		# ...after the player's own last press has finished lighting up. That flash
		# is _press_feedback's 0.18 s decay and it belongs to the tap that STARTED
		# the event; anything lit after it could only be a sequence being played.
		if Time.get_ticks_msec() - t0 > 400:
			for i in _dev._count:
				if _dev._lit[i]:
					lit = true
	var secs := float(Time.get_ticks_msec() - t0) / 1000.0
	_ok(ran, "%s: the background's own event ran inside the freeze" % label)
	_ok(moved == "", "%s: %d taps during it changed nothing" % [label, taps], moved)
	_ok(not lit, "%s: and no button lit once the press feedback cleared" % label)
	_ok(absf(secs - want) < 0.9, "%s: the freeze lasted the whole event" % label,
		"%.2f s, asked for %.2f" % [secs, want])
	_ok(not bool(_ice.call("event_active")),
		"%s: and nothing of the event outlived it" % label)
	_ok(_game.level == lvl and _game.sequence.size() == seq,
		"%s: the round it resumes into is the one it left" % label)


func _save(tag: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(
		"res://shot_icefz_%s.png" % tag)
	print("  shot  res://shot_icefz_%s.png" % tag)


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
