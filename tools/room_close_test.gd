extends Node

# Headless exercise of how a room ENDS, against ContestManager's editor sim. Run:
#
#   godot --headless --path . tools/room_close_test.tscn
#
# The bug this locks down: the Android listener never fires for a DELETED document
# (see the note at the top of contest_manager.gd), so a room that ended by being
# deleted left everyone still sitting in it staring at a live-looking lobby forever.
# Ending a room is therefore a WRITE — `cancelled: true` on top of status "finished"
# — and these checks assert that the watcher actually receives it, that the room
# stops being listed and joinable, and that the seat is released.
#
# Not shipped with the game; a developer harness for behaviour that is otherwise
# only observable with two devices.

var _fails := 0
var _pushes: Array = []      # every room_changed payload for the watched room

func _ready() -> void:
	FirebaseManager.sign_in()
	FirebaseManager.set_display_name("Tester")
	ContestManager.room_changed.connect(func(_cid: String, room: Dictionary) -> void:
		_pushes.append(room))
	await _run()
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
	print("\n-- the host cancels a room someone is watching --")
	var r: Dictionary = await ContestManager.create_contest("easy", "Doomed", true)
	var cid := String(r.get("id", ""))
	_check("room created", not cid.is_empty(), str(r))
	ContestManager.watch_room(cid)
	await _settle()
	_pushes.clear()

	await ContestManager.cancel_room(cid)
	await _settle()

	# THE regression: a watcher must be TOLD. An empty push (the old delete) is not
	# enough on a device — it never arrives at all.
	_check("the watcher got a push", not _pushes.is_empty())
	var last: Dictionary = _pushes[-1] if not _pushes.is_empty() else {}
	_check("the push says the room was closed", bool(last.get("cancelled", false)), str(last))
	_check("status stays inside the released enum (old clients show standings, "
		+ "not a phantom race)", String(last.get("status", "")) == "finished", str(last))

	# The room doc must survive the close — a deleted doc is invisible to a listener,
	# so anyone who was offline for the push still needs to be able to READ the reason.
	var after: Dictionary = await ContestManager.load_room(cid)
	_check("the room is still readable after closing", not after.is_empty())
	_check("...and still reads as closed", bool(after.get("cancelled", false)), str(after))
	# ...but only for as long as it takes the news to land: the close pulls the expiry
	# horizon in from the full TTL to CLOSED_LINGER, so the sweep reaps the doc soon
	# after rather than parking it for 20 minutes.
	var raw: Dictionary = (ContestManager.get("_sim_rooms") as Dictionary).get(cid, {})
	var lingers_for: int = int(raw.get("expires_unix", 0)) - int(Time.get_unix_time_from_system())
	_check("expiry pulled in to CLOSED_LINGER, not the full TTL",
		lingers_for <= ContestManager.CLOSED_LINGER and lingers_for > 0, "%ds" % lingers_for)

	print("\n-- a closed room is out of circulation --")
	_check("no longer listed in the lobby",
		not _lobby_ids().has(cid), str(_lobby_ids()))
	var j: Dictionary = await ContestManager.join_contest(cid)
	_check("can't be joined", not bool(j.get("ok", false)), str(j))
	_check("and says so precisely", String(j.get("error", "")) == "closed", str(j))

	print("\n-- the seat is released --")
	_check("the room pointer was cleared", not ContestManager.has_cached_room(),
		ContestManager.cached_room_id())
	var again: Dictionary = await ContestManager.create_contest("easy", "Next", true)
	_check("the host can open a new room right away", bool(again.get("ok", false)), str(again))
	ContestManager.unwatch_room(cid)

	print("\n-- the host walking out of their own lobby closes it the same way --")
	var cid2 := String(again.get("id", ""))
	ContestManager.watch_room(cid2)
	await _settle()
	_pushes.clear()
	await ContestManager.leave_contest(cid2)
	await _settle()
	var last2: Dictionary = _pushes[-1] if not _pushes.is_empty() else {}
	_check("leaving as host pushes the same closed state",
		bool(last2.get("cancelled", false)), str(last2))
	_check("and delists the room", not _lobby_ids().has(cid2), str(_lobby_ids()))
	ContestManager.unwatch_room(cid2)

	print("\n-- a race that ran to its end can't be re-closed --")
	# Closing is a write everyone SEES, so it must never land on a room that finished on
	# its own: that would replace a legitimate final podium with "the host closed this
	# room" for every watcher. Reachable by tapping through a confirm raised on the
	# results board after the race finalized underneath it.
	var r3: Dictionary = await ContestManager.create_contest("easy", "Real Race", false)
	var cid3 := String(r3.get("id", ""))
	await ContestManager.start_room(cid3)
	await ContestManager.submit_result(cid3, 7)
	var fin: Dictionary = await ContestManager.load_room(cid3)
	_check("the race finished on its own", String(fin.get("status", "")) == "finished", str(fin))
	await ContestManager.cancel_room(cid3)
	var after3: Dictionary = await ContestManager.load_room(cid3)
	_check("cancelling a finished room is a no-op",
		not bool(after3.get("cancelled", false)), str(after3))
	_check("...and the standings survive",
		int((after3.get("players", {}) as Dictionary).get(FirebaseManager.uid, {})
			.get("score", 0)) == 7, str(after3))

	print("\n-- a kicked player's score can't put them back in --")
	# submit_result merge-writes state:"done" over our own row, so a player the host
	# removed mid-race used to UN-tombstone themselves and reappear on the board with a
	# score. The read that guards it happens BEFORE the write.
	var r4: Dictionary = await ContestManager.create_contest("easy", "Kicked", false)
	var cid4 := String(r4.get("id", ""))
	await ContestManager.start_room(cid4)
	ContestManager._write_player(cid4, FirebaseManager.uid, {"state": "left"})
	await ContestManager.submit_result(cid4, 42)
	var k: Dictionary = await ContestManager.load_room(cid4)
	var krow: Dictionary = (k.get("players", {}) as Dictionary).get(FirebaseManager.uid, {})
	_check("the tombstone survives the score write",
		String(krow.get("state", "")) == "left", str(krow))
	_check("...and no score was recorded", int(krow.get("score", 0)) == 0, str(krow))

	print("\n-- the last member out CLOSES the room, it isn't deleted --")
	# Deleting needed the "member_count <= 0" rule arm, which any member could reach by
	# writing that one field — a two-write way to destroy a live race. Closing replaces
	# it, so the doc must still be there afterwards, marked terminal.
	var r5: Dictionary = await ContestManager.create_contest("easy", "Emptied", true)
	var cid5 := String(r5.get("id", ""))
	# Hand the room to a stranger so our own leave takes the ordinary guest path.
	var sim: Dictionary = ContestManager.get("_sim_rooms")
	(sim[cid5] as Dictionary)["creator_uid"] = "someone_else"
	var left5: bool = await ContestManager.leave_contest(cid5)
	_check("the leave was reported as done", left5)
	var after5: Dictionary = await ContestManager.load_room(cid5)
	_check("the emptied room still exists", not after5.is_empty())
	_check("...and reads as closed", bool(after5.get("cancelled", false)), str(after5))
	_check("...and is delisted", not _lobby_ids().has(cid5), str(_lobby_ids()))

	print("\n-- room codes from already-released builds still resolve --")
	# We now GENERATE 6 digits, but shipped builds hand out Crockford-base32 codes and
	# their rooms appear in everyone's browse list; validating only against the new
	# alphabet made every one of those rooms unjoinable.
	sim["A7K3M2"] = {
		"id": "A7K3M2", "title": "Legacy", "creator_uid": "old_client",
		"difficulty": "easy", "status": "lobby", "is_public": true,
		"member_count": 1, "players": {"old_client": {"name": "Old", "state": "lobby"}},
	}
	var legacy: Dictionary = await ContestManager.load_room("A7K3M2")
	_check("a legacy alphanumeric room ID still loads", not legacy.is_empty(), str(legacy))
	_check("a wrong-length code is still rejected",
		(await ContestManager.load_room("A7K3M")).is_empty())

	print("\n-- a finish this client never heard about still reaches the board --")
	# The bug: the race ended in Firestore but the "finished" push never landed here
	# (the materialized mirror is maintained by unordered trigger events, so an older
	# revision can be published last and pin it at "playing"). finalize_if_done READS
	# the room, so it is holding the news — it has to fan it out instead of returning
	# quietly, which is what left players who had already finished on the waiting
	# board for a full watchdog window while everyone else was on the podium.
	var sim6: Dictionary = ContestManager.get("_sim_rooms")
	var r6: Dictionary = await ContestManager.create_contest("easy", "Lost Push", false)
	var cid6 := String(r6.get("id", ""))
	await ContestManager.start_room(cid6)
	var rival6: Dictionary = {"name": "Rival", "state": "lobby", "score": 0}
	((sim6[cid6] as Dictionary)["players"] as Dictionary)["rival"] = rival6
	ContestManager.watch_room(cid6)
	await ContestManager.submit_result(cid6, 5)      # we finish; the rival is still racing
	await _settle()
	_check("one racer left, so the room stays open",
		String((await ContestManager.load_room(cid6)).get("status", "")) == "playing")
	_pushes.clear()
	# The rival finishes and the room is finalized — all of it invisible to us (written
	# straight into the store, no push).
	rival6["state"] = "done"
	rival6["score"] = 9
	rival6["finished_at"] = int(Time.get_unix_time_from_system())
	(sim6[cid6] as Dictionary)["status"] = "finished"
	await ContestManager.finalize_if_done(cid6)
	await _settle()
	var last6: Dictionary = _pushes[-1] if not _pushes.is_empty() else {}
	_check("the missed finish is pushed to the watcher",
		String(last6.get("status", "")) == "finished", str(last6))
	_check("...with the rival's score on it", int((last6.get("players", {}) as Dictionary)
		.get("rival", {}).get("score", 0)) == 9, str(last6))
	ContestManager.unwatch_room(cid6)

	print("\n-- an all-done room nobody finalized is finished from the board --")
	# Same board, other half: everyone is done but no client managed to write the flip
	# (the last finisher's read was stale, or they were killed right after posting).
	# Any participant may close it out, and must see it happen.
	var r7: Dictionary = await ContestManager.create_contest("easy", "Nobody Closed", false)
	var cid7 := String(r7.get("id", ""))
	await ContestManager.start_room(cid7)
	var rival7: Dictionary = {"name": "Rival", "state": "lobby", "score": 0}
	((sim6[cid7] as Dictionary)["players"] as Dictionary)["rival"] = rival7
	ContestManager.watch_room(cid7)
	await ContestManager.submit_result(cid7, 3)
	await _settle()
	_pushes.clear()
	rival7["state"] = "done"                          # done, but nobody wrote the flip
	rival7["score"] = 4
	rival7["finished_at"] = int(Time.get_unix_time_from_system())
	await ContestManager.finalize_if_done(cid7)
	await _settle()
	var last7: Dictionary = _pushes[-1] if not _pushes.is_empty() else {}
	_check("the room is finalized from here", String(last7.get("status", "")) == "finished",
		str(last7))
	_check("...and the write actually landed",
		String((await ContestManager.load_room(cid7)).get("status", "")) == "finished")
	ContestManager.unwatch_room(cid7)

func _lobby_ids() -> Array:
	return ContestManager.lobby_rows().map(func(r): return String(r.get("id", "")))
