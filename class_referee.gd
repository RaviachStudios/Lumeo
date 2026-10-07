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
# Nobody is knocked out. Every student plays every round; a round they fail, run out
# of time on, or never answer scores 0 and they play on. Only leaving or being removed
# takes a student out of the game.
#
# Round lifecycle (all times in SERVER milliseconds):
#   publish round r      -> doc {round: r, round_at_ms}
#   each student reports round r: completed {r, w: r, ls, lt} or missed {r} (w < r)
#   resolve round r when every student we're waiting for has answered, or at
#   deadline_ms(r). The points are BANKED in the class doc (bank.{uid}) at that moment,
#   so a report that arrives after the round was resolved is never credited.
#   then: nobody completed round r, or r == max_rounds, or nobody is left -> finish;
#   otherwise publish r + 1.
#
# "Waiting for" = active students who answered the PREVIOUS round (in time or late).
# A student whose phone died answers nothing, so after one silent round the class
# stops waiting for them — they can still score the moment they're back.

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
# `rounds` is the teacher's 10 / 15 choice.
func start(now_ms: int, now_unix: int, seed: int, rounds: int = ClassRules.DEFAULT_ROUNDS) -> Dictionary:
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
		"max_rounds": ClassRules.valid_rounds(rounds),
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

# Students who LEFT or were REMOVED, and the round it happened in. Nobody else is
# ever "out" — a missed round just scores 0.
func out_map() -> Dictionary:
	return doc.get("out", {})

func bank() -> Dictionary:
	return doc.get("bank", {})

func max_rounds() -> int:
	return ClassRules.valid_rounds(int(doc.get("max_rounds", ClassRules.DEFAULT_ROUNDS)))

# Roster students still in the game (not left / removed).
func alive_uids() -> Array:
	var out: Array = []
	var o := out_map()
	for uid in roster():
		if not o.has(uid):
			out.append(uid)
	return out

# How a student stands on round r: "done" (completed it), "missed" (reported a fail /
# timeout), "left", or "pending" (no answer yet).
func answer(uid: String, r: int) -> String:
	var row: Dictionary = rows.get(uid, {})
	if row.is_empty():
		return "pending"
	if String(row.get("st", "")) == "left":
		return "left"
	if int(row.get("r", 0)) >= r:
		return "done" if int(row.get("w", 0)) >= r else "missed"
	return "pending"

# Do we hold round r open for this student? Round 1: everyone. After that, only
# students who answered round r - 1 at all (on time or late) — a silent device isn't
# waited for, but can still score if it answers before the round is resolved.
func waits_for(uid: String, r: int) -> bool:
	if r <= 1:
		return true
	if int((bank().get(uid, {}) as Dictionary).get("a", 0)) >= r - 1:
		return true
	return int((rows.get(uid, {}) as Dictionary).get("r", 0)) >= r - 1

func current_deadline_ms() -> int:
	return ClassRules.deadline_ms(int(doc.get("round_at_ms", 0)), int(doc.get("round", 1)))

# Snapshot for the teacher's live board.
func progress() -> Dictionary:
	var r := int(doc.get("round", 0))
	var done := 0
	var missed := 0
	var pending := 0
	var alive := alive_uids()
	for uid in alive:
		match answer(uid, r):
			"done": done += 1
			"missed": missed += 1
			"pending": pending += 1
	return {
		"round": r,
		"max": max_rounds(),
		"alive": alive.size(),
		"done": done,
		"missed": missed,
		"pending": pending,
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
		if waits_for(uid, r) and answer(uid, r) == "pending":
			all_answered = false
			break
	if not all_answered and now_ms < current_deadline_ms():
		return {}
	return _resolve_round(r, alive, now_ms, now_unix)

# Bank round r for every student still in, then either publish r + 1 or finish.
func _resolve_round(r: int, alive: Array, now_ms: int, now_unix: int) -> Dictionary:
	var new_out := {}
	var new_bank := {}
	var completed := 0
	for uid in alive:
		var row: Dictionary = rows.get(uid, {})
		var b := _bank_entry(uid)
		match answer(uid, r):
			"done":
				b["s"] = int(b["s"]) + clampi(int(row.get("ls", 0)), 0, ClassRules.MAX_POINTS)
				b["t"] = int(b["t"]) + maxi(0, int(row.get("lt", 0)))
				b["c"] = int(b["c"]) + 1
				b["a"] = r
				completed += 1
			"missed":
				b["a"] = r
			"left":
				new_out[uid] = r
		new_bank[uid] = b
	var still_in := alive.size() - new_out.size()
	var w := {}
	if completed == 0 or r >= max_rounds() or still_in <= 0:
		var reason := "max"
		if still_in <= 0:
			reason = "empty"
		elif completed == 0:
			reason = "none_completed"
		w = _finish_write(new_bank, now_unix, reason)
		w["alive"] = still_in
	else:
		w = {
			"round": r + 1,
			"round_at_ms": now_ms,
			"alive": still_in,
			"expires_unix": now_unix + ClassRules.PLAY_TTL,
		}
	# NEVER send an empty map: in a Firestore merge write an empty map value REPLACES
	# the whole field (there are no leaf keys to merge).
	if not new_bank.is_empty():
		w["bank"] = new_bank
	if not new_out.is_empty():
		w["out"] = new_out
	return w

func _bank_entry(uid: String) -> Dictionary:
	var b: Dictionary = (bank().get(uid, {}) as Dictionary).duplicate()
	for k in ["s", "t", "c", "a"]:
		b[k] = int(b.get(k, 0))
	return b

# The teacher pressed End Game. Whoever already completed the current round is
# credited with it; nobody is penalised for the round that was cut short.
func end_now(now_unix: int) -> Dictionary:
	if status() != "playing":
		return {}
	var r := int(doc.get("round", 0))
	var new_bank := {}
	for uid in alive_uids():
		if answer(uid, r) == "done":
			var row: Dictionary = rows.get(uid, {})
			var b := _bank_entry(uid)
			b["s"] = int(b["s"]) + clampi(int(row.get("ls", 0)), 0, ClassRules.MAX_POINTS)
			b["t"] = int(b["t"]) + maxi(0, int(row.get("lt", 0)))
			b["c"] = int(b["c"]) + 1
			b["a"] = r
			new_bank[uid] = b
	var w := _finish_write(new_bank, now_unix, "teacher")
	w["ended_early"] = true
	if not new_bank.is_empty():
		w["bank"] = new_bank
	return w

# Remove a student. In the lobby they simply vanish from the list; mid-game they stop
# playing (their banked points stay on the board unless they were removed).
func kick(uid: String, now_unix: int) -> Dictionary:
	var w := {"kicked": {uid: true}}
	if status() == "playing" and roster().has(uid) and not out_map().has(uid):
		w["out"] = {uid: int(doc.get("round", 1))}
		var left := alive_uids().size() - 1
		w["alive"] = maxi(0, left)
		if left <= 0:
			var f := _finish_write({}, now_unix, "empty", {uid: true})
			f["kicked"] = w["kicked"]
			f["out"] = w["out"]
			f["alive"] = 0
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

# Final results from the bank (+ `fresh` entries this very write is banking). Removed
# students are left out; students who left keep what they banked.
func _finish_write(fresh: Dictionary, now_unix: int, reason: String,
		also_kicked: Dictionary = {}) -> Dictionary:
	var list: Array = []
	var ros := roster()
	for uid in ros:
		if is_kicked(uid) or also_kicked.has(uid):
			continue
		var b: Dictionary = fresh.get(uid, _bank_entry(uid))
		list.append({"uid": uid, "n": String((ros[uid] as Dictionary).get("n", "Student")),
			"s": int(b.get("s", 0)), "c": int(b.get("c", 0)), "t": int(b.get("t", 0))})
	var ranked := ClassRules.rank(list)
	var results := {}
	for e: Dictionary in ranked:
		results[e["uid"]] = {"n": e["n"], "s": e["s"], "c": e["c"], "t": e["t"], "p": e["p"]}
	return {
		"status": "finished",
		"finished_at": now_unix,
		"end_reason": reason,
		"results": results,
		"expires_unix": now_unix + ClassRules.DONE_TTL,
	}
