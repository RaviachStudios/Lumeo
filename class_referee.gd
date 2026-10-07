extends RefCounted

# The referee of a Class Game. Runs on the TEACHER's device (and, in the editor sim,
# on behalf of a pretend teacher). Pure logic: it never touches the network. It is fed
# the class doc and the five report shards, and when something must change it RETURNS
# the merge-write to make; ClassManager performs it and hands the result back through
# apply(). That keeps every decision in one testable place and lets the same code run
# against the editor sim.
#
# Why the teacher's device and not a Cloud Function: see CLASS_GAMES_PLAN.md. In short,
# one deterministic writer, no trigger latency or ordering problems, and the referee's
# whole state can be rebuilt from Firestore (class doc + 5 shards) after a restart.
#
# Round lifecycle (all times in SERVER milliseconds):
#   publish round r      -> doc {round: r, round_at_ms}
#   every student either reports {st:"in", r} (completed) or {st:"out"/"left"}
#   resolve round r when every student still in has answered OR deadline_ms(r) passes:
#     - completed  -> stays in
#     - anything else (failed, left, never answered) -> out[uid] = r
#   then: <= 1 student left or r == MAX_ROUNDS -> finish; else publish r + 1.

const ClassRules := preload("res://class_rules.gd")

var pid := ""
var doc: Dictionary = {}          # shaped class doc (ClassManager.shape_class)
var rows: Dictionary = {}         # uid -> shaped report row (+ "k": shard index)
# Rows are only trustworthy for resolving a round once every shard has been read at
# least once since (re)attaching — a referee that judged a round off a half-loaded set
# of shards would count out everyone in the missing ones.
var synced := false
var _shards_seen: Dictionary = {} # k -> true

func setup(class_id: String, class_doc: Dictionary) -> void:
	pid = class_id
	doc = class_doc.duplicate(true)
	rows.clear()
	_shards_seen.clear()
	synced = false

# Replace everything we know about shard `k` with a fresh snapshot of it.
func set_shard(k: int, players: Dictionary) -> void:
	for uid in rows.keys():
		if int((rows[uid] as Dictionary).get("k", -1)) == k:
			rows.erase(uid)
	for uid in players:
		var row: Dictionary = (players[uid] as Dictionary).duplicate()
		row["k"] = k
		rows[uid] = row
	_shards_seen[k] = true
	if _shards_seen.size() >= ClassRules.SHARDS:
		synced = true

# A class-doc snapshot (listener push or re-read). Our own writes are applied locally
# the moment we make them (apply), so a push can only ever be our own echo or older —
# never adopt one that would move the game backwards.
func on_doc(d: Dictionary) -> void:
	if d.is_empty():
		return
	if _status_rank(String(d.get("status", ""))) < _status_rank(String(doc.get("status", ""))):
		return
	if String(d.get("status", "")) == String(doc.get("status", "")) \
			and int(d.get("round", 0)) < int(doc.get("round", 0)):
		return
	doc = d.duplicate(true)

# Fold a write we just made into our local copy (maps merge key-by-key, like
# Firestore's merge does).
func apply(write: Dictionary) -> void:
	for k in write:
		var v: Variant = write[k]
		if v is Dictionary and doc.get(k, null) is Dictionary:
			var cur: Dictionary = doc[k]
			for kk in v:
				cur[kk] = v[kk]
			doc[k] = cur
		else:
			doc[k] = v

static func _status_rank(s: String) -> int:
	match s:
		"lobby": return 0
		"playing": return 1
		"finished", "cancelled": return 2
	return -1

func status() -> String:
	return String(doc.get("status", ""))

func is_kicked(uid: String) -> bool:
	return (doc.get("kicked", {}) as Dictionary).has(uid)

# ---------------------------------------------------------------------------
# Lobby
# ---------------------------------------------------------------------------

# Students currently waiting in the lobby, in join order: [{uid, n, j}].
func lobby_students() -> Array:
	var out: Array = []
	for uid in rows:
		var row: Dictionary = rows[uid]
		if String(row.get("st", "")) != "lobby" or is_kicked(uid):
			continue
		if uid == String(doc.get("teacher_uid", "")):
			continue
		out.append({"uid": uid, "n": String(row.get("n", "Student")), "j": int(row.get("j", 0))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["j"]) != int(b["j"]):
			return int(a["j"]) < int(b["j"])
		return String(a["uid"]) < String(b["uid"]))
	return out

# The write (if any) the lobby needs right now: keep `full` honest, and push the
# expiry out when a long lobby is about to be swept. {} = nothing to do.
func lobby_upkeep(now_unix: int) -> Dictionary:
	if status() != "lobby":
		return {}
	var w := {}
	var full := lobby_students().size() >= ClassRules.MAX_STUDENTS
	if full != bool(doc.get("full", false)):
		w["full"] = full
	if int(doc.get("expires_unix", 0)) - now_unix < ClassRules.LOBBY_REFRESH_BELOW:
		w["expires_unix"] = now_unix + ClassRules.LOBBY_TTL
	return w

# The START write, or {"error": ...}. Takes the first MAX_STUDENTS waiting students
# (by join time) as the frozen roster; anyone else who slipped in sees "class full".
func start(now_ms: int, now_unix: int, seed: int) -> Dictionary:
	if status() != "lobby":
		return {"error": "not_lobby"}
	var waiting := lobby_students()
	if waiting.size() < ClassRules.MIN_STUDENTS:
		return {"error": "too_few"}
	var roster := {}
	for i in mini(waiting.size(), ClassRules.MAX_STUDENTS):
		var e: Dictionary = waiting[i]
		var row: Dictionary = rows.get(e["uid"], {})
		roster[e["uid"]] = {"n": String(e["n"]), "d": String(row.get("d", ""))}
	return {
		"status": "playing",
		"started_at": now_unix,
		"seed": seed,
		"roster": roster,
		"round": 1,
		"round_at_ms": now_ms,
		"alive": roster.size(),
		"expires_unix": now_unix + ClassRules.PLAY_TTL,
	}

# ---------------------------------------------------------------------------
# Playing
# ---------------------------------------------------------------------------

func roster() -> Dictionary:
	return doc.get("roster", {})

func out_map() -> Dictionary:
	return doc.get("out", {})

# Roster students not (yet) counted out.
func alive_uids() -> Array:
	var out: Array = []
	var o := out_map()
	for uid in roster():
		if not o.has(uid):
			out.append(uid)
	return out

# Where a still-in student stands on round r: "done" (completed it), "failed" (told us
# they're out / left), or "pending" (nothing yet).
func answer(uid: String, r: int) -> String:
	var row: Dictionary = rows.get(uid, {})
	if row.is_empty():
		return "pending"
	var st := String(row.get("st", ""))
	if st == "out" or st == "left":
		return "failed"
	if int(row.get("r", 0)) >= r:
		return "done"
	return "pending"

func current_deadline_ms() -> int:
	return ClassRules.deadline_ms(int(doc.get("round_at_ms", 0)), int(doc.get("round", 1)))

# Snapshot for the teacher's live board.
func progress() -> Dictionary:
	var r := int(doc.get("round", 0))
	var done := 0
	var failed := 0
	var alive := alive_uids()
	for uid in alive:
		match answer(uid, r):
			"done": done += 1
			"failed": failed += 1
	return {
		"round": r,
		"alive": alive.size(),
		"done": done,
		"failed": failed,
		"pending": alive.size() - done - failed,
		"out": out_map().size(),
		"deadline_ms": current_deadline_ms(),
	}

# The write that ends round r now, or {} if it isn't over yet. Called on every tick
# and whenever a shard changes.
func tick(now_ms: int, now_unix: int) -> Dictionary:
	if status() != "playing" or not synced:
		return {}
	var r := int(doc.get("round", 0))
	if r <= 0:
		return {}
	var alive := alive_uids()
	var all_answered := true
	for uid in alive:
		if answer(uid, r) == "pending":
			all_answered = false
			break
	if not all_answered and now_ms < current_deadline_ms():
		return {}
	return _resolve_round(r, alive, now_ms, now_unix)

func _resolve_round(r: int, alive: Array, now_ms: int, now_unix: int) -> Dictionary:
	var new_out := {}
	var survivors: Array = []
	for uid in alive:
		if answer(uid, r) == "done":
			survivors.append(uid)
		else:
			new_out[uid] = r
	if survivors.size() <= 1 or r >= ClassRules.MAX_ROUNDS:
		var merged_out := out_map().duplicate()
		for uid in new_out:
			merged_out[uid] = new_out[uid]
		var w := _finish_write(merged_out, r, now_unix)
		if not new_out.is_empty():
			w["out"] = new_out
		w["alive"] = survivors.size()
		return w
	var nw := {
		"round": r + 1,
		"round_at_ms": now_ms,
		"alive": survivors.size(),
		"expires_unix": now_unix + ClassRules.PLAY_TTL,
	}
	# NEVER send an empty map: in a Firestore merge write an empty map value REPLACES
	# the whole field (there are no leaf keys to merge), which wiped every earlier
	# round's outs the first time a round passed with nobody going out.
	if not new_out.is_empty():
		nw["out"] = new_out
	return nw

# The teacher pressed End Game. Whoever already completed the current round keeps
# it; whoever was still mid-round is credited with the rounds before it (no one is
# counted out for a round the teacher cut short).
func end_now(now_unix: int) -> Dictionary:
	if status() != "playing":
		return {}
	var r := int(doc.get("round", 0))
	var w := _finish_write(out_map(), r, now_unix)
	w["ended_early"] = true
	return w

# Remove a student. In the lobby they simply vanish from the list; mid-game they are
# also counted out on the current round.
func kick(uid: String, now_unix: int) -> Dictionary:
	var w := {"kicked": {uid: true}}
	if status() == "playing" and roster().has(uid) and not out_map().has(uid):
		w["out"] = {uid: int(doc.get("round", 1))}
		w["alive"] = maxi(0, alive_uids().size() - 1)
		# Removing the second-to-last student leaves a winner — end it now rather than
		# make one student play on alone.
		if alive_uids().size() - 1 <= 1:
			var merged := out_map().duplicate()
			merged[uid] = int(doc.get("round", 1))
			var f := _finish_write(merged, int(doc.get("round", 1)), now_unix, {uid: true})
			f["kicked"] = w["kicked"]
			f["out"] = w["out"]
			f["alive"] = w["alive"]
			return f
	if status() == "lobby":
		w["expires_unix"] = maxi(int(doc.get("expires_unix", 0)), now_unix + 60)
	return w

func cancel(now_unix: int) -> Dictionary:
	return {
		"status": "cancelled",
		"finished_at": now_unix,
		"expires_unix": now_unix + ClassRules.DONE_TTL,
	}

# Build the final results from the report rows and the out map.
#   rounds completed: out at round R -> R - 1; still in -> min(row.r, current round)
#   score/time: the row's running totals — EXCEPT a student counted out at R whose
#   (late) report says they completed R: the totals then include a round they were
#   not credited with, so its points/time (ls/lt) are taken back off.
# `also_kicked` = students being removed by the very write this result rides on (not
# yet in doc.kicked), so they're left out of the standings too.
func _finish_write(final_out: Dictionary, cur_round: int, now_unix: int,
		also_kicked: Dictionary = {}) -> Dictionary:
	var list: Array = []
	var ros := roster()
	for uid in ros:
		if is_kicked(uid) or also_kicked.has(uid):
			continue
		var row: Dictionary = rows.get(uid, {})
		var rr := int(row.get("r", 0))
		var s := int(row.get("s", 0))
		var t := int(row.get("t", 0))
		var rounds := mini(rr, cur_round)
		if final_out.has(uid):
			var at := int(final_out[uid])
			rounds = maxi(0, at - 1)
			if rr >= at:
				s = maxi(0, s - int(row.get("ls", 0)))
				t = maxi(0, t - int(row.get("lt", 0)))
		list.append({"uid": uid, "n": String((ros[uid] as Dictionary).get("n", "Student")),
			"r": rounds, "s": s, "t": t})
	var ranked := ClassRules.rank(list)
	var results := {}
	for e: Dictionary in ranked:
		results[e["uid"]] = {"n": e["n"], "r": e["r"], "s": e["s"], "t": e["t"], "p": e["p"]}
	return {
		"status": "finished",
		"finished_at": now_unix,
		"results": results,
		"expires_unix": now_unix + ClassRules.DONE_TTL,
	}
