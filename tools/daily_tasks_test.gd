extends Node

# Headless exercise of the daily-task board against CoinsManager's editor sim
# (the sim mirrors the Firestore shape, so this covers the real logic — only the
# transport differs), plus a smoke-build of the popup so a layout/typing mistake
# in it surfaces here instead of on a device. Run:
#
#   godot --headless --path . tools/daily_tasks_test.tscn
#
# Not shipped with the game; it's a developer harness.

const DailyTasksPopup := preload("res://daily_tasks_popup.gd")

var _fails := 0

func _ready() -> void:
	FirebaseManager.sign_in()
	FirebaseManager.set_display_name("Tester")
	# CoinsManager loads the (empty) sim wallet on the signed_in signal; DailyTasks
	# picks the board up off that same load.
	await _settle()
	await _run()
	await _run_ui()
	await _run_touch_scroll()
	print("\n%s" % ("ALL CHECKS PASSED" if _fails == 0 else "%d CHECK(S) FAILED" % _fails))
	get_tree().quit(1 if _fails > 0 else 0)

func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("  ok    %s" % label)
	else:
		_fails += 1
		print("  FAIL  %s   %s" % [label, detail])

func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func _run() -> void:
	print("\n-- progress --")
	_check("board ready after wallet load", DailyTasks.is_ready())
	_check("nothing claimable on a fresh day", DailyTasks.claimable_count() == 0)
	_check("play_1 starts at 0/1", DailyTasks.progress("play_1") == 0)

	DailyTasks.note_game_played("easy")
	DailyTasks.note_score("easy", 6)
	_check("play_1 completes on the first game", DailyTasks.is_complete("play_1"))
	_check("play_3 shows partial progress", DailyTasks.progress("play_3") == 1)
	_check("reach_10 tracks the day's best", DailyTasks.progress("reach_10") == 6)
	_check("reach_10 not complete at round 6", not DailyTasks.is_complete("reach_10"))

	DailyTasks.note_score("easy", 3)
	_check("a weaker run can't lower the best", DailyTasks.progress("reach_10") == 6)
	DailyTasks.note_score("hard", 12)
	_check("best clamps to the target", DailyTasks.progress("reach_10") == 10)
	_check("hard task reads the hard-only best", DailyTasks.is_complete("hard_7"))

	print("\n-- counters --")
	_check("rounds accumulate across runs", DailyTasks.progress("rounds_25") == 21, "6+3+12")
	_check("per-difficulty bests are separate",
		DailyTasks.progress("easy_12") == 6 and DailyTasks.progress("hard_12") == 12)
	_check("moderate untouched", DailyTasks.progress("mod_8") == 0)
	_check("one difficulty played so far", DailyTasks.progress("all_diffs") == 1)
	DailyTasks.note_game_played("easy")
	_check("replaying a difficulty doesn't re-count it", DailyTasks.progress("all_diffs") == 1)
	DailyTasks.note_game_played("hard")
	_check("a new difficulty counts once", DailyTasks.progress("all_diffs") == 2)
	DailyTasks.note_coins_earned(30)
	DailyTasks.note_coins_earned(25)
	_check("coin earnings accumulate", DailyTasks.progress("coins_50") == 50, "clamped at the target")

	print("\n-- arena --")
	DailyTasks.note_arena_played()
	DailyTasks.note_contest_result(4, 6)
	_check("a 4th place is not a podium", not DailyTasks.is_complete("arena_podium"))
	_check("a small field isn't a full house", not DailyTasks.is_complete("arena_crowd"))
	DailyTasks.note_arena_played()
	DailyTasks.note_contest_result(2, 12)
	_check("2nd place takes the podium task", DailyTasks.is_complete("arena_podium"))
	_check("12 racers fills the house", DailyTasks.is_complete("arena_crowd"))
	_check("2nd place is not a win", not DailyTasks.is_complete("arena_win"))
	DailyTasks.note_contest_result(1, 4)
	_check("1st place takes the crown", DailyTasks.is_complete("arena_win"))

	print("\n-- daily leaderboard --")
	_check("no standing yet reads as unranked", DailyTasks.progress_text("lb_top50") == "—")
	_check("an unranked board bar is empty", DailyTasks.bar_fraction("lb_top50") == 0.0)
	DailyTasks.note_daily_rank(80)
	_check("rank 80 misses the Top 50", not DailyTasks.is_complete("lb_top50"))
	_check("but it does show progress", DailyTasks.bar_fraction("lb_top50") > 0.0)
	_check("the readout is the position", DailyTasks.progress_text("lb_top50") == "#80")
	DailyTasks.note_daily_rank(22)
	_check("rank 22 takes Top 50 and Top 25",
		DailyTasks.is_complete("lb_top50") and DailyTasks.is_complete("lb_top25"))
	_check("rank 22 misses Top 10", not DailyTasks.is_complete("lb_top10"))
	DailyTasks.note_daily_rank(64)
	_check("a worse standing can't undo a better one", DailyTasks.progress_text("lb_top25") == "#22")
	_check("action copy names the bar", DailyTasks.action_text("lb_top10") == "TOP 10")
	# End to end: a real daily-board load is what reports a standing in the app, so
	# check the signal path rather than just the note it ends in.
	LeaderboardManager.submit_score_daily("easy", 42)
	var board: Dictionary = await LeaderboardManager.load_daily("easy")
	_check("the board reports a standing", int(board.get("my_rank", 0)) == 1)
	_check("loading a daily board feeds the task board",
		DailyTasks.progress_text("lb_top3") == "#1" and DailyTasks.is_complete("lb_top3"))

	print("\n-- ordering --")
	var order := DailyTasks.ordered_tasks()
	_check("every task is listed once", order.size() == DailyTasks.total_count())
	var last_state := -1
	var monotonic := true
	for t in order:
		var id := String(t["id"])
		# 0 = claimable, 1 = already claimed, 2 = unfinished.
		var state := 2 if not DailyTasks.is_complete(id) else (1 if DailyTasks.is_claimed(id) else 0)
		if state < last_state:
			monotonic = false
		last_state = state
	_check("finished tasks sort above unfinished ones", monotonic)

	print("\n-- claiming --")
	var before := CoinsManager.balance
	var reward := int(DailyTasks.task("play_1")["reward"])
	_check("play_1 is claimable", DailyTasks.can_claim("play_1"))
	_check("claim pays the reward", DailyTasks.claim("play_1") == reward)
	_check("coins landed in the wallet", CoinsManager.balance == before + reward)
	_check("claim counts as earned", CoinsManager.earned_coins >= reward)
	_check("a second claim pays nothing", DailyTasks.claim("play_1") == 0)
	_check("claimed tasks leave the ready count", not DailyTasks.can_claim("play_1"))

	var pending := DailyTasks.claimable_total()
	var ready_now := DailyTasks.claimable_count()
	_check("claim-all sweeps what's left", DailyTasks.claim_all() == pending, str(pending))
	_check("nothing left to claim", DailyTasks.claimable_count() == 0, str(ready_now))
	_check("wallet holds every reward", CoinsManager.balance == before + reward + pending)

	print("\n-- persistence --")
	await _settle()
	var saved: Variant = CoinsManager.raw_user_doc.get("daily_tasks", {})
	_check("board is mirrored on the wallet doc", saved is Dictionary and not (saved as Dictionary).is_empty())
	var counters: Dictionary = (saved as Dictionary).get("counters", {})
	var claimed: Dictionary = (saved as Dictionary).get("claimed", {})
	_check("counters persisted", int(counters.get("games", 0)) == 3, str(counters))
	_check("claims persisted", bool(claimed.get("play_1", false)), str(claimed))
	_check("state is a map of maps (no arrays)", counters is Dictionary and claimed is Dictionary)

	print("\n-- sign out --")
	FirebaseManager.sign_out_user()
	await _settle()
	_check("board clears with the account", not DailyTasks.is_ready())
	_check("no stale progress after sign-out", DailyTasks.progress("play_1") == 0)
	# A signed-out note has no board to land on and must not be queued for the next
	# account either (only an in-flight load parks notes — see _defer).
	DailyTasks.note_game_played("easy")
	_check("a signed-out note is dropped", DailyTasks.progress("play_1") == 0)
	FirebaseManager.sign_in()
	FirebaseManager.set_display_name("Tester")
	await _settle()
	_check("board reloads on sign-in", DailyTasks.is_ready())
	_check("claims survive a re-login", DailyTasks.is_claimed("play_1"))
	_check("counters come back exactly as saved", DailyTasks.progress("play_5") == 3)

# Build the popup for real and let it live a few frames — catches null refs,
# bad casts and draw-callback errors that a pure-logic test can't see.
func _run_ui() -> void:
	print("\n-- popup --")
	# Leave the board carrying claimed, claimable AND locked tasks at once, so the
	# popup opens on the mix a real player would see.
	DailyTasks.note_game_played("hard")
	DailyTasks.note_game_played("hard")
	DailyTasks.note_score("hard", 8)
	DailyTasks.note_daily_claimed()
	var host := Control.new()
	host.size = Vector2(1280, 720)
	add_child(host)
	var popup := DailyTasksPopup.new()
	host.add_child(popup)
	await _settle()
	await _settle()
	_check("popup built and stayed alive", is_instance_valid(popup) and popup.is_inside_tree())
	_check("claimable rewards are waiting", DailyTasks.claimable_count() > 0)
	await _shoot("daily_tasks_popup")
	# Progress arriving while the popup is open must not reshuffle it.
	DailyTasks.note_game_played("moderate")
	await _settle()
	_check("popup survives a live progress update", is_instance_valid(popup))
	popup._on_claim_all()
	await _settle()
	_check("popup survives claim-all", is_instance_valid(popup))
	await _shoot("daily_tasks_popup_claimed")
	# The lower half of the list (Hard / Arena / Daily Reward) is worth a look too.
	for c in popup._dialog.get_children():
		if c is ScrollContainer:
			(c as ScrollContainer).scroll_vertical = 9999
	await _settle()
	await _shoot("daily_tasks_popup_bottom")
	popup._close()
	await _settle()

	# Re-open on the now-rich board: the sort runs again, so the Arena and daily
	# leaderboard tasks earned above come to the top.
	var popup2 := DailyTasksPopup.new()
	host.add_child(popup2)
	await _settle()
	_check("popup re-opens on a fully worked board", is_instance_valid(popup2))
	await _shoot("daily_tasks_popup_reopen")
	for c in popup2._dialog.get_children():
		if c is ScrollContainer:
			(c as ScrollContainer).scroll_vertical = 1500
	await _settle()
	await _shoot("daily_tasks_popup_arena")
	popup2._close()
	await _settle()

# The list has to flick on Android no matter where the finger lands — including on
# a row's CLAIM button. A Control with MOUSE_FILTER_STOP swallows the ScreenDrag
# before the ScrollContainer ever sees it, so this drags from three places and
# asserts all three scroll. The project runs with emulate_touch_from_mouse, so the
# synthesized ScreenTouch/ScreenDrag here takes the exact path a real finger does.
func _run_touch_scroll() -> void:
	print("\n-- touch scroll --")
	# The dummy display server never dispatches GUI touch, so a headless run would
	# report every drag below as stuck. Run windowed to actually exercise these.
	if DisplayServer.get_name() == "headless":
		print("  skip  touch checks need a windowed run (godot --path . tools/daily_tasks_test.tscn)")
		return
	Input.use_accumulated_input = false
	var host := Control.new()
	host.size = get_viewport().get_visible_rect().size
	add_child(host)
	var popup := DailyTasksPopup.new()
	host.add_child(popup)
	await _settle()
	await _settle()

	var scroll: ScrollContainer = null
	for c in popup._dialog.get_children():
		if c is ScrollContainer:
			scroll = c as ScrollContainer
	if scroll == null:
		_check("popup has a scrolling list", false)
		return
	_check("the list is long enough to scroll", scroll.get_v_scroll_bar().max_value > scroll.size.y)
	_check("the build reports a touchscreen", DisplayServer.is_touchscreen_available(),
		"emulate_touch_from_mouse is what makes this reachable on desktop")

	# _run_ui swept the board with claim-all; finish one more task so a live CLAIM
	# is on screen alongside the claimed/locked ones.
	DailyTasks.note_score("moderate", 9)
	await _settle()

	# A claimable row (live CLAIM) and a locked one (greyed pill) — the player hit
	# both states.
	var live: Button = null
	var dead: Button = null
	for r in popup._rows:
		var btn: Button = r["btn"]
		if btn.disabled:
			if dead == null:
				dead = btn
		elif live == null:
			live = btn
	_check("board shows a live and a dead claim button", live != null and dead != null)

	await _rest(scroll)
	var body := scroll.global_position + Vector2(60, scroll.size.y * 0.5)
	_check("drag on the row body scrolls", await _drag(scroll, body) > 0)
	if live != null:
		_check("drag on a live CLAIM scrolls", await _drag_on(scroll, live) > 0)
	if dead != null:
		_check("drag on a disabled claim button scrolls", await _drag_on(scroll, dead) > 0)

	# The other half of the bargain: a tap that doesn't travel must still claim.
	if live != null:
		var id := ""
		for r in popup._rows:
			if r["btn"] == live:
				id = String((r["task"] as Dictionary)["id"])
		await _tap(scroll, live)
		_check("a tap on CLAIM still claims", DailyTasks.is_claimed(id), id)

	popup._close()
	await _settle()

# Press and release on a control without moving — a claim tap.
func _tap(scroll: ScrollContainer, ctl: Control) -> void:
	await _rest(scroll)
	var into_view := ctl.global_position.y - scroll.global_position.y \
		+ float(scroll.scroll_vertical) - scroll.size.y * 0.5
	scroll.scroll_vertical = int(maxf(0.0, into_view))
	await _settle()
	var at := ctl.global_position + ctl.size * 0.5
	for pressed in [true, false]:
		var ev := InputEventScreenTouch.new()
		ev.index = 0
		ev.position = at
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await _settle()

# Flick starting on a control. The row is brought into view first (and the press
# point read only after it has settled there — read any earlier and it would be
# taken from wherever the previous flick left the row).
func _drag_on(scroll: ScrollContainer, ctl: Control) -> int:
	await _rest(scroll)
	var into_view := ctl.global_position.y - scroll.global_position.y \
		+ float(scroll.scroll_vertical) - scroll.size.y * 0.5
	scroll.scroll_vertical = int(maxf(0.0, into_view))
	await _settle()
	var at := ctl.global_position + ctl.size * 0.5
	if not Rect2(scroll.global_position, scroll.size).has_point(at):
		print("     (skipped: %s is outside the list at %s)" % [ctl.text, at])
		return -1
	# Flick back toward the top when the list is already scrolled — that direction
	# always has room, whereas a row near the bottom has nowhere further to go.
	return await _drag(scroll, at, 1 if scroll.scroll_vertical > 240 else -1)

# Park the list back at the top and let the release inertia die out, so the next
# drag starts from a known offset.
func _rest(scroll: ScrollContainer) -> void:
	for i in 60:
		scroll.scroll_vertical = 0
		await get_tree().process_frame
		if scroll.scroll_vertical == 0:
			break

# One flick from `at` (dir -1 drags the finger up, +1 down), reported as the
# distance the list travelled while the finger was still down — before any
# release inertia, so it is purely what the drag itself moved.
func _drag(scroll: ScrollContainer, at: Vector2, dir := -1) -> int:
	var start := scroll.scroll_vertical
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.position = at
	press.pressed = true
	Input.parse_input_event(press)
	await _settle()

	var pos := at
	for i in 10:
		var step := Vector2(0, 24.0 * dir)
		pos += step
		var drag := InputEventScreenDrag.new()
		drag.index = 0
		drag.position = pos
		drag.relative = step
		drag.velocity = Vector2(0, 900.0 * dir)
		Input.parse_input_event(drag)
		await _settle()
	var reached: int = absi(scroll.scroll_vertical - start)

	var release := InputEventScreenTouch.new()
	release.index = 0
	release.position = pos
	release.pressed = false
	Input.parse_input_event(release)
	await _settle()
	return reached

# Save the current frame to user://<name>.png. A no-op headless (the dummy
# renderer has no framebuffer to read back) — run without --headless to get one.
func _shoot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "user://%s.png" % name
	img.save_png(path)
	print("  shot  %s" % ProjectSettings.globalize_path(path))
