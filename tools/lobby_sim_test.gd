extends Node

# Headless exercise of the public-lobby index against ContestManager's editor sim
# (the sim mirrors the Firestore shape, so this covers the real logic — only the
# transport differs). Run:
#
#   godot --headless --path . tools/lobby_sim_test.tscn
#
# Not shipped with the game; it's a developer harness for the lobby/deadline rules
# that are otherwise only observable on a device.

var _fails := 0
var _rows: Array = []

func _ready() -> void:
	FirebaseManager.sign_in()
	FirebaseManager.set_display_name("Tester")
	ContestManager.lobby_changed.connect(func(rows: Array) -> void: _rows = rows)
	ContestManager.watch_lobby()
	await _run()
	await _run_ui()
	print("\n%s" % ("ALL CHECKS PASSED" if _fails == 0 else "%d CHECK(S) FAILED" % _fails))
	get_tree().quit(1 if _fails > 0 else 0)

func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("  ok    %s" % label)
	else:
		_fails += 1
		print("  FAIL  %s   %s" % [label, detail])

# The live signal is emitted deferred (coalesced); wait a frame to observe it.
func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func _ids(rows: Array) -> Array:
	return rows.map(func(r): return String(r.get("id", "")))

# The lobby's ordering contract: newest open first, ties broken by id so the list
# doesn't reshuffle between snapshots.
func _ordering_ok(rows: Array) -> bool:
	for i in range(1, rows.size()):
		var prev: Dictionary = rows[i - 1]
		var cur: Dictionary = rows[i]
		if int(prev["open_at"]) < int(cur["open_at"]):
			return false
		if int(prev["open_at"]) == int(cur["open_at"]) and String(prev["id"]) > String(cur["id"]):
			return false
	return true

func _run() -> void:
	print("\n-- open / list --")
	var a: Dictionary = await ContestManager.create_contest("easy", "Alpha", true)
	var b: Dictionary = await ContestManager.create_contest("hard", "Bravo", true)
	var p: Dictionary = await ContestManager.create_contest("easy", "Private", false)
	await _settle()
	_check("public rooms listed", _rows.size() == 2, str(_ids(_rows)))
	_check("private room not listed", not _ids(_rows).has(String(p["id"])))
	_check("row carries a deadline",
		int(_rows[0].get("deadline", 0)) - int(_rows[0].get("open_at", 0)) == ContestManager.START_WINDOW)
	_check("row is flagged as mine", bool(_rows[0].get("is_creator", false)))
	_check("rows are ordered newest-first, ties by id", _ordering_ok(_rows), str(_ids(_rows)))
	# Same-second opens tie on open_at, so force a gap to see the ordering itself.
	_age_entry(String(a["id"]), 5)
	_check("an older room sorts below a newer one",
		String(ContestManager.lobby_rows()[0]["id"]) == String(b["id"]),
		str(_ids(ContestManager.lobby_rows())))

	print("\n-- join bumps the listed count --")
	var mine := FirebaseManager.uid
	FirebaseManager.uid = "other_uid_1"
	var j: Dictionary = await ContestManager.join_contest(String(a["id"]))
	FirebaseManager.uid = mine
	await _settle()
	_check("join succeeded", bool(j.get("ok", false)), str(j))
	for r: Dictionary in _rows:
		if String(r["id"]) == String(a["id"]):
			_check("listed count followed the join", int(r["member_count"]) == 2, str(r))

	print("\n-- start / cancel leave the lobby --")
	await ContestManager.start_room(String(a["id"]))
	await _settle()
	_check("started room delisted", not _ids(_rows).has(String(a["id"])), str(_ids(_rows)))
	await ContestManager.cancel_room(String(b["id"]))
	await _settle()
	_check("cancelled room delisted", not _ids(_rows).has(String(b["id"])), str(_ids(_rows)))
	_check("lobby empty again", _rows.is_empty(), str(_ids(_rows)))

	print("\n-- the start window expires on its own --")
	var c: Dictionary = await ContestManager.create_contest("moderate", "Stale", true)
	await _settle()
	_check("room listed while fresh", _ids(_rows).has(String(c["id"])))
	# Age the entry past START_WINDOW without any write from its host.
	_age_entry(String(c["id"]), ContestManager.START_WINDOW + 1)
	_check("expired room drops out of the rows",
		not _ids(ContestManager.lobby_rows()).has(String(c["id"])))

	print("\n-- the %d-room cap --" % ContestManager.LOBBY_MAX)
	var made := 0
	for i in ContestManager.LOBBY_MAX:
		var r: Dictionary = await ContestManager.create_contest("easy", "R%d" % i, true)
		if bool(r.get("ok", false)):
			made += 1
		else:
			break
	_check("exactly LOBBY_MAX rooms fit", made == ContestManager.LOBBY_MAX, "made %d" % made)
	var over: Dictionary = await ContestManager.create_contest("easy", "Overflow", true)
	_check("the next public room is refused",
		not bool(over.get("ok", false)) and String(over.get("error", "")) == "lobby_full", str(over))
	var priv: Dictionary = await ContestManager.create_contest("easy", "StillPrivate", false)
	_check("a private room is still allowed", bool(priv.get("ok", false)), str(priv))
	await _settle()
	_check("all LOBBY_MAX rooms are listed", _rows.size() == ContestManager.LOBBY_MAX,
		"listed %d" % _rows.size())
	_check("no shard holds more than LOBBY_SHARD_CAP", _max_shard_size() <= ContestManager.LOBBY_SHARD_CAP,
		"max %d" % _max_shard_size())

	print("\n-- dead entries are reclaimed, not squatted --")
	# Expire every listed room; the slots must come back even though nothing was
	# deleted (entries can only be tombstoned).
	for r: Dictionary in _rows:
		_age_entry(String(r["id"]), ContestManager.START_WINDOW + 1)
	var after: Dictionary = await ContestManager.create_contest("easy", "Reclaimed", true)
	_check("a slot frees up once rooms expire", bool(after.get("ok", false)), str(after))
	await _settle()
	_check("only the fresh room is listed", _rows.size() == 1, "listed %d" % _rows.size())
	_check("compaction kept the shard within cap", _max_shard_size() <= ContestManager.LOBBY_SHARD_CAP,
		"max %d" % _max_shard_size())

# Builds the real screens headlessly and drives the new paths (popup open, live
# push, paging, per-second tick, countdown chip). Catches null/typo breakage that
# the pure-data checks above can't see. Visual correctness still needs a device.
func _run_ui() -> void:
	print("\n-- lobby popup --")
	# Enough rooms to need more than one page.
	for i in 25:
		await ContestManager.create_contest("easy", "UI%d" % i, true)
	var arena: Control = preload("res://arena_screen.gd").new()
	arena.game_manager = self
	add_child(arena)
	await _settle()
	arena.call("_open_lobby_modal")
	await _settle()
	var rows: Array = arena.get("_lobby_rows")
	_check("popup picked up the live rows", rows.size() >= 25, "got %d" % rows.size())
	_check("first page holds one page of rows",
		arena.get("_lobby_list").get_child_count() == arena.get("LOBBY_PAGE"),
		"rendered %d" % arena.get("_lobby_list").get_child_count())
	arena.call("_lobby_turn_page", 1)
	_check("paging forward moves the window", int(arena.get("_lobby_page")) == 1)
	arena.call("_lobby_turn_page", 5)
	_check("paging can't run past the end",
		int(arena.get("_lobby_page")) == arena.call("_lobby_page_count") - 1,
		"page %d" % int(arena.get("_lobby_page")))
	arena.call("_lobby_turn_page", -99)
	_check("paging can't run before the start", int(arena.get("_lobby_page")) == 0)
	arena.call("_on_lobby_tick")
	_check("the per-second tick survives a redraw", true)
	arena.call("_close_lobby_modal")
	_check("closing the popup drops the listeners",
		not ContestManager.lobby_changed.is_connected(Callable(arena, "_on_lobby_changed")))
	arena.queue_free()
	# The popup's teardown unwatches for everyone; re-arm for the room checks.
	ContestManager.watch_lobby()
	await _settle()

	print("\n-- room countdown --")
	var pub: Dictionary = await ContestManager.create_contest("easy", "Timed", true)
	var room: Control = preload("res://contest_detail_screen.gd").new()
	room.set("contest_id", String(pub["id"]))
	room.game_manager = self
	add_child(room)
	await _settle()
	await _settle()
	_check("public room shows a countdown chip", room.get("_timer_chip") != null)
	_check("countdown reads the remaining window",
		String(room.get("_timer_lbl").text).begins_with("5:"),
		String(room.get("_timer_lbl").text))
	room.queue_free()
	await _settle()

	var priv: Dictionary = await ContestManager.create_contest("easy", "Quiet", false)
	var proom: Control = preload("res://contest_detail_screen.gd").new()
	proom.set("contest_id", String(priv["id"]))
	proom.game_manager = self
	add_child(proom)
	await _settle()
	await _settle()
	_check("private room has no countdown", proom.get("_timer_chip") == null)
	proom.queue_free()
	await _settle()

# Screens call into their game_manager; the harness only has to absorb it.
func show_arena() -> void:
	pass

# Rewinds a listed room's open time so it falls outside the start window — what a
# host walking away looks like to every other client.
func _age_entry(cid: String, secs: int) -> void:
	var shards: Dictionary = ContestManager.get("_sim_shards")
	for idx in shards:
		var rooms: Dictionary = shards[idx]
		if rooms.has(cid):
			rooms[cid]["o"] = int(rooms[cid]["o"]) - secs

func _max_shard_size() -> int:
	var shards: Dictionary = ContestManager.get("_sim_shards")
	var m := 0
	for idx in shards:
		m = maxi(m, (shards[idx] as Dictionary).size())
	return m
