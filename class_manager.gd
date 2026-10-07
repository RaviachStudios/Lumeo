extends Node

# Class Games (teacher mode). A teacher (users/{uid}.role == "teacher", set by hand
# in the Firebase console) opens a class, students join with its 6-digit PID, and
# everyone plays the same hard-mode sequence round by round. See CLASS_GAMES_PLAN.md
# for the design and the reasoning behind it; this header is the operational summary.
#
# --- Storage (built for the fewest reads/writes) ----------------------------------
#
#   classes/{PID}              written ONLY by the teacher, ~20 writes a game;
#                              every student listens to it.
#   class_reports/{PID}_{k}    k = 0..4; each student merge-writes ONLY their own row
#                              (rules enforce it); only the teacher listens.
#
# Students never hear each other's writes — the teacher's device is the referee
# (class_referee.gd) and turns ~45 reports into ONE "next round" write. A full
# 45-student, 15-round game is ~750 writes / ~1,600 reads.
#
#   classes/{PID} = {
#     v, teacher_uid, teacher_name, status: lobby|playing|finished|cancelled,
#     created_at, started_at, finished_at, expires_unix, full,
#     seed, roster: {uid: {n, d}}, round, round_at_ms, alive,
#     out: {uid: round}, kicked: {uid: true}, results: {uid: {n, r, s, t, p}},
#     ended_early
#   }
#   class_reports/{PID}_{k} = { players: { uid: {n, d, j, st, r, s, t, ls, lt, f} } }
#     st: lobby|in|out|left   r: rounds completed   s/t: running score / time (ms)
#     ls/lt: the LAST round's points / time   f: the round they failed (0 = none)
#
# --- Time ------------------------------------------------------------------------
# Device clocks don't agree and the plugin can't write server timestamps, so every
# device estimates its offset to server time from the HTTP Date header of a REST read
# it already makes (see _note_server_date). The teacher stamps rounds in server ms;
# a student uses that ONLY to tell how late a round reached them. Gameplay clocks are
# always local (see ClassRules for the shared deadline formula).
#
# --- Plugin constraints (same as ContestManager) -----------------------------------
# * Listeners are single-document only, and never fire for a DELETED doc — so a class
#   that ends is a WRITE (status cancelled/finished) and the server sweep deletes it
#   later; a watchdog read covers the case where the doc vanished under us.
# * Reads go over REST (unauthenticated; both collections are world-readable, they
#   hold names and scores only), writes through the plugin so rules see request.auth.
#
# The pointer to the class we're in lives in a LOCAL file (not on /users), so joining
# costs no extra write; it is what routes a restarted app straight back into its class.

const ClassRules := preload("res://class_rules.gd")
const ClassReferee := preload("res://class_referee.gd")

# Fired whenever anything a class screen shows may have changed.
signal changed
# A new round this student should play now (game.gd / the class screen take it with
# take_pending_round()).
signal round_started(r: int)
# A short message for a toast.
signal notice(text: String)

const _COLL := "classes"
const _REPORTS := "class_reports"
const _FB_BASE := "https://firestore.googleapis.com/v1/projects/simon-6bc39/databases/(default)/documents"
const _PTR_PATH := "user://class_pointer.cfg"
const _DEVICE_PATH := "user://class_device.cfg"

const TICK_SECS := 0.25            # teacher referee + editor sim cadence
const WATCH_TICK := 5.0            # student watchdog cadence (local checks only)
const LOBBY_CHECK_SECS := 60       # watchdog read cadence once a lobby is past expiry
const TEACHER_LATE_SECS := 4       # past the round's deadline before "waiting for teacher"
const LATE_CHECK_SECS := 30        # watchdog read cadence while waiting for the teacher

var _is_editor := OS.get_name() != "Android"
# Editor only: whether this editor session plays the teacher. Flip it in the remote
# inspector (or here) to try the student side against a simulated teacher.
var editor_teacher := true

# ---- the class we're attached to ----
var class_id := ""
var is_host := false
var doc: Dictionary = {}           # shaped (shape_class)
var gone := false                  # the class doc no longer exists
var load_failed := false           # couldn't reach Firestore to load it (retryable)
var _listening: Array[String] = []
var _last_push_unix := 0

# ---- student ----
var _my_row: Dictionary = {}       # my report row as last written (running totals)
var _self_out_round := 0           # I reported myself out on this round (0 = no)
var _self_out_reason := ""         # failed | late | left
var _started_round := 0            # last round handed to the game
# Set when we (re)attach to a game already in progress — i.e. the app was closed and
# reopened mid-game. A round that was already running then can't be played; say so
# plainly instead of blaming the connection.
var _resumed_mid_game := false
var _pending_round := 0
var _pending_recv_ms := 0          # ticks when that round's update reached us
var _coins_open := false           # a coin session is running for this class
var coins_earned := 0              # what this class paid out (shown on the podium)
var teacher_late := false          # the round is overdue: "waiting for teacher"
var _wd_next_read := 0
var _wd_busy := false

# ---- teacher ----
var referee: ClassReferee
var _resyncing := false
var _confirming := false
var _confirm_retry_ms := 0
# The teacher's last check against the server failed: the game is paused (no round is
# judged) until it succeeds. Shown on the live board.
var teacher_offline := false

# ---- server time ----
var _offset := 0.0
var _offset_err := 1e9
var _device := ""

var _tick: Timer
var _watch: Timer

func _ready() -> void:
	_device = _load_device_token()
	if not _is_editor:
		Firebase.firestore.document_changed.connect(_on_document_changed)
	FirebaseManager.signed_out.connect(_on_signed_out)
	_tick = Timer.new()
	_tick.wait_time = TICK_SECS
	_tick.timeout.connect(_on_tick)
	add_child(_tick)
	_watch = Timer.new()
	_watch.wait_time = WATCH_TICK
	_watch.timeout.connect(_on_watch)
	add_child(_watch)
	if _is_editor:
		_offset_err = 0.0

func _uid() -> String: return FirebaseManager.uid
func _name() -> String:
	return ClassRules.clean_name(FirebaseManager.display_name)
func _unix() -> float: return Time.get_unix_time_from_system()

func server_ms() -> int:
	return int((_unix() + _offset) * 1000.0)

func server_unix() -> int:
	return int(_unix() + _offset)

func offset_known() -> bool:
	return _offset_err < 3.0

# ---------------------------------------------------------------------------
# Who may do what
# ---------------------------------------------------------------------------

func is_teacher() -> bool:
	if not FirebaseManager.is_signed_in():
		return false
	if _is_editor:
		return editor_teacher
	return String(CoinsManager.raw_user_doc.get("role", "")) == "teacher"

# ---------------------------------------------------------------------------
# Local pointer ("I'm in class X") — survives an app restart, costs no writes
# ---------------------------------------------------------------------------

func has_pointer() -> bool:
	return not pointer_id().is_empty()

func pointer_id() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(_PTR_PATH) != OK:
		return ""
	if String(cfg.get_value("class", "uid", "")) != _uid() or _uid().is_empty():
		return ""
	return String(cfg.get_value("class", "id", ""))

func pointer_is_host() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(_PTR_PATH) != OK:
		return false
	return bool(cfg.get_value("class", "host", false))

func _set_pointer(pid: String, host: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("class", "id", pid)
	cfg.set_value("class", "host", host)
	cfg.set_value("class", "uid", _uid())
	cfg.save(_PTR_PATH)

func _clear_pointer() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("class", "id", "")
	cfg.save(_PTR_PATH)

# One read: is the class we point at still worth returning to? Clears the pointer when
# it isn't (gone, over for good, or we're no longer part of it). Returns the shaped doc
# or {}. Used by the loading screen, the home/arena entrances and the "one game at a
# time" check.
func validate_pointer() -> Dictionary:
	var pid := pointer_id()
	if pid.is_empty():
		return {}
	var res := await _read_class(pid)
	var st := String(res.get("status", "error"))
	if st == "error":
		# Unknown — keep the pointer; the caller treats it as "maybe still in a class".
		return {"_unknown": true, "id": pid}
	if st == "missing":
		_clear_pointer()
		return {}
	var d: Dictionary = res["doc"]
	var host := String(d.get("teacher_uid", "")) == _uid()
	if not host and (d.get("kicked", {}) as Dictionary).has(_uid()):
		_clear_pointer()
		return {}
	if String(d.get("status", "")) == "cancelled":
		_clear_pointer()
		return {}
	return d

# True when this player is busy in a class (for ContestManager's one-game-at-a-time
# rule). Costs one read only when a pointer exists.
func busy() -> bool:
	if not has_pointer():
		return false
	var d := await validate_pointer()
	if d.is_empty():
		return false
	return String(d.get("status", "")) != "finished"

# ---------------------------------------------------------------------------
# Create (teacher)
# ---------------------------------------------------------------------------

# {ok, id} or {ok:false, error} with error in {auth, not_teacher, in_room, in_class,
# id_collision, write_failed}.
func create_class() -> Dictionary:
	if _uid().is_empty() or not FirebaseManager.has_display_name():
		return {"ok": false, "error": "auth"}
	if not is_teacher():
		return {"ok": false, "error": "not_teacher"}
	var mine := await validate_pointer()
	if not mine.is_empty() and String(mine.get("status", "")) != "finished":
		return {"ok": false, "error": "in_class", "id": String(mine.get("id", pointer_id()))}
	if ContestManager.has_cached_room():
		var room := await ContestManager.active_room()
		if not room.is_empty():
			return {"ok": false, "error": "in_room"}
	for _attempt in 6:
		var pid := _gen_pid()
		var res := await _read_class(pid)
		var st := String(res.get("status", "error"))
		if st == "ok":
			continue                       # taken
		if st == "error":
			return {"ok": false, "error": "network"}
		var now := server_unix()
		var data := {
			"v": ClassRules.VERSION,
			"teacher_uid": _uid(),
			"teacher_name": _name(),
			"status": "lobby",
			"created_at": now,
			"started_at": 0,
			"finished_at": 0,
			"expires_unix": now + ClassRules.LOBBY_TTL,
			"full": false,
			"seed": 0,
			"round": 0,
			"round_at_ms": 0,
			"alive": 0,
		}
		if not await _write_doc(_COLL, pid, data, false, true):
			return {"ok": false, "error": "write_failed"}
		_set_pointer(pid, true)
		await attach(pid, shape_class(data, pid))
		if _is_editor:
			_sim_spawn_bots(pid)
		return {"ok": true, "id": pid}
	return {"ok": false, "error": "id_collision"}

# ---------------------------------------------------------------------------
# Join (student)
# ---------------------------------------------------------------------------

# {ok, host?} or {ok:false, error} — error in {auth, bad_pid, not_found, network,
# update_app, teacher_update, started, ended, kicked, full, in_room, in_class}.
func join_class(raw: String) -> Dictionary:
	if _uid().is_empty() or not FirebaseManager.has_display_name():
		return {"ok": false, "error": "auth"}
	var pid := raw.strip_edges()
	if not ClassRules.valid_pid(pid):
		return {"ok": false, "error": "bad_pid"}
	# One game at a time.
	var mine_pid := pointer_id()
	if not mine_pid.is_empty() and mine_pid != pid:
		var mine := await validate_pointer()
		if not mine.is_empty() and String(mine.get("status", "")) != "finished":
			return {"ok": false, "error": "in_class"}
	if ContestManager.has_cached_room():
		var room := await ContestManager.active_room()
		if not room.is_empty():
			return {"ok": false, "error": "in_room"}

	if _is_editor and not _sim_docs.has(_COLL + "/" + pid):
		_sim_make_teacher_class(pid)
	var res := await _read_class(pid)
	var st := String(res.get("status", "error"))
	if st == "error":
		return {"ok": false, "error": "network"}
	if st == "missing":
		return {"ok": false, "error": "not_found"}
	var d: Dictionary = res["doc"]
	if String(d.get("teacher_uid", "")) == _uid():
		_set_pointer(pid, true)
		await attach(pid, d)
		return {"ok": true, "host": true}
	var v := int(d.get("v", 0))
	if v > ClassRules.VERSION:
		return {"ok": false, "error": "update_app"}
	if v < ClassRules.VERSION:
		return {"ok": false, "error": "teacher_update"}
	if (d.get("kicked", {}) as Dictionary).has(_uid()):
		return {"ok": false, "error": "kicked"}
	var status := String(d.get("status", ""))
	if status == "finished" or status == "cancelled":
		return {"ok": false, "error": "ended"}
	if status == "playing":
		# Already part of this game (an app restart mid-game): go back in.
		if (d.get("roster", {}) as Dictionary).has(_uid()):
			_set_pointer(pid, false)
			await attach(pid, d)
			return {"ok": true}
		return {"ok": false, "error": "started"}
	if bool(d.get("full", false)) and mine_pid != pid:
		return {"ok": false, "error": "full"}
	var now := server_unix()
	var row := {
		"n": _name(), "d": _device, "j": now, "st": "lobby",
		"r": 0, "s": 0, "t": 0, "ls": 0, "lt": 0, "f": 0,
	}
	if not await _write_row(pid, row, true):
		return {"ok": false, "error": "write_failed"}
	_my_row = row
	_set_pointer(pid, false)
	await attach(pid, d)
	return {"ok": true}

# ---------------------------------------------------------------------------
# Attach / detach
# ---------------------------------------------------------------------------

# Start following a class. Safe to call again for the class we're already on.
func attach(pid: String, initial: Dictionary = {}) -> void:
	if class_id == pid and not doc.is_empty() and not gone:
		return
	detach()
	class_id = pid
	gone = false
	teacher_late = false
	_started_round = 0
	_pending_round = 0
	_self_out_round = 0
	_self_out_reason = ""
	_resumed_mid_game = false
	load_failed = false
	var d := initial
	if d.is_empty():
		var st := "error"
		for attempt in 3:
			var res := await _read_class(pid)
			st = String(res.get("status", "error"))
			if st != "error":
				d = res.get("doc", {})
				break
			await get_tree().create_timer(2.0).timeout
		if class_id != pid:
			return                         # detached / re-attached meanwhile
		if st == "missing":
			gone = true
			_clear_pointer()
			changed.emit()
			return
		if st == "error":
			load_failed = true
			changed.emit()
			return
	doc = d
	is_host = String(doc.get("teacher_uid", "")) == _uid() and not _uid().is_empty()
	_resumed_mid_game = String(doc.get("status", "")) == "playing"
	_last_push_unix = int(_unix())
	if is_host:
		referee = ClassReferee.new()
		referee.setup(pid, doc)
		await _resync_shards()
		for k in ClassRules.SHARDS:
			_listen(_REPORTS + "/" + ClassRules.shard_id(pid, k))
		_tick.start()
	else:
		if _my_row.is_empty() or String(_my_row.get("_pid", pid)) != pid:
			if not doc.is_empty() and String(doc.get("status", "")) != "lobby":
				await _load_my_row()
		_my_row["_pid"] = pid
		_listen(_COLL + "/" + pid)
		_watch.start()
		if _is_editor:
			_tick.start()
	_on_class_doc(doc, true)

func detach() -> void:
	for p in _listening:
		if not _is_editor:
			Firebase.firestore.stop_listening_to_document(p)
	_listening.clear()
	_tick.stop()
	_watch.stop()
	referee = null
	class_id = ""
	doc = {}
	is_host = false
	teacher_late = false
	load_failed = false

func _listen(path: String) -> void:
	if _listening.has(path):
		return
	_listening.append(path)
	if not _is_editor:
		Firebase.firestore.listen_to_document(path)
	else:
		call_deferred("_sim_deliver", path)

# Account deletion / sign-out cleanup: a teacher cancels their class, a student
# leaves theirs.
func leave_all() -> void:
	if class_id.is_empty() and has_pointer():
		await attach(pointer_id())
	if class_id.is_empty():
		_clear_pointer()
		return
	if is_host:
		cancel_class()
		close_out()
	else:
		leave_class()

# The player is done with this class (left the podium, or it was cancelled/gone).
func close_out() -> void:
	commit_coins()
	_clear_pointer()
	_my_row = {}
	detach()
	changed.emit()

# ---------------------------------------------------------------------------
# Listener plumbing
# ---------------------------------------------------------------------------

func _on_document_changed(path: String, data: Dictionary) -> void:
	if not _listening.has(path):
		return
	var raw: Dictionary = data
	if data.has("fields"):
		raw = _fields(data["fields"])
	_last_push_unix = int(_unix())
	if path.begins_with(_REPORTS + "/"):
		_on_shard(path, raw)
	elif path.begins_with(_COLL + "/"):
		if raw.is_empty() or not raw.has("teacher_uid"):
			return                         # never fires for deletes; ignore empties
		_on_class_doc(shape_class(raw, class_id), false)

func _on_shard(path: String, raw: Dictionary) -> void:
	if referee == null:
		return
	var sid := path.substr((_REPORTS + "/").length())
	var k := int(sid.get_slice("_", 1))
	referee.set_shard(k, _shape_players(raw.get("players", {})))
	_run_referee()
	changed.emit()

# A class-doc snapshot reached us (push, read, or our own initial load).
func _on_class_doc(d: Dictionary, initial: bool) -> void:
	if d.is_empty():
		return
	if not initial and not _newer_or_same(d, doc):
		return
	# Only a doc that MOVED ON (new status / round / outs) clears "waiting for your
	# teacher" and the watchdog's read throttle. A watchdog re-read of the unchanged doc
	# must not: that reset the flag on every read (so the warning never showed) and
	# re-armed the throttle (so every waiting student read every 5 s, not every 30 s).
	var moved := initial or String(d.get("status", "")) != String(doc.get("status", "")) \
		or int(d.get("round", 0)) != int(doc.get("round", 0)) \
		or (d.get("out", {}) as Dictionary).size() != (doc.get("out", {}) as Dictionary).size()
	doc = d
	if moved:
		teacher_late = false
		_wd_next_read = 0
	if is_host:
		if referee:
			referee.on_doc(d)
		changed.emit()
		return
	var phase := student_phase()
	if phase == "playing":
		_maybe_start_round()
	elif phase in ["finished", "cancelled", "kicked", "gone"]:
		if phase == "cancelled" or phase == "kicked":
			_clear_pointer()
	changed.emit()

func _newer_or_same(a: Dictionary, b: Dictionary) -> bool:
	if b.is_empty():
		return true
	var ra := ClassReferee._status_rank(String(a.get("status", "")))
	var rb := ClassReferee._status_rank(String(b.get("status", "")))
	if ra != rb:
		return ra > rb
	if int(a.get("round", 0)) != int(b.get("round", 0)):
		return int(a.get("round", 0)) > int(b.get("round", 0))
	# Same round: a later write can still add outs / kicks.
	return (a.get("out", {}) as Dictionary).size() >= (b.get("out", {}) as Dictionary).size() \
		and (a.get("kicked", {}) as Dictionary).size() >= (b.get("kicked", {}) as Dictionary).size()

# ---------------------------------------------------------------------------
# Student side
# ---------------------------------------------------------------------------

# Where this student stands. One of:
#   none | gone | lobby | playing | out | kicked | not_in_roster | other_device
#   | finished | cancelled
func student_phase() -> String:
	if class_id.is_empty():
		return "none"
	if gone:
		return "gone"
	if doc.is_empty():
		return "none"
	var me := _uid()
	if (doc.get("kicked", {}) as Dictionary).has(me):
		return "kicked"
	match String(doc.get("status", "")):
		"lobby":
			return "lobby"
		"cancelled":
			return "cancelled"
		"finished":
			return "finished"
		"playing":
			var ros: Dictionary = doc.get("roster", {})
			if not ros.has(me):
				return "not_in_roster"
			if String((ros[me] as Dictionary).get("d", "")) != _device \
					and not String((ros[me] as Dictionary).get("d", "")).is_empty():
				return "other_device"
			if (doc.get("out", {}) as Dictionary).has(me) or _self_out_round > 0:
				return "out"
			return "playing"
	return "none"

# The round I went out on (from the doc, or my own report if the doc hasn't caught up).
func my_out_round() -> int:
	var o: Dictionary = doc.get("out", {})
	if o.has(_uid()):
		return int(o[_uid()])
	return _self_out_round

# Why I'm out: failed | late | left | timeout (the referee counted me out because my
# report never arrived) | kicked.
func my_out_reason() -> String:
	if (doc.get("kicked", {}) as Dictionary).has(_uid()):
		return "kicked"
	if not _self_out_reason.is_empty():
		return _self_out_reason
	if (doc.get("out", {}) as Dictionary).has(_uid()):
		return "timeout"
	return ""

func my_score() -> int:
	# A round I completed but was counted out on anyway (my report arrived after the
	# deadline) isn't credited — same rule as the referee's results.
	var s := int(_my_row.get("s", 0))
	var o := my_out_round()
	if o > 0 and int(_my_row.get("r", 0)) >= o:
		s -= int(_my_row.get("ls", 0))
	return maxi(0, s)
func my_rounds() -> int: return int(_my_row.get("r", 0))

func _maybe_start_round() -> void:
	var r := int(doc.get("round", 0))
	if r <= 0 or r <= _started_round:
		return
	# Rounds I've already completed (e.g. after an app restart, my row says so) are
	# not replayed.
	if r <= int(_my_row.get("r", 0)):
		_started_round = r
		return
	_started_round = r
	var lateness := float(server_ms() - int(doc.get("round_at_ms", 0))) / 1000.0
	if offset_known() and lateness > ClassRules.LATE_LIMIT:
		if _resumed_mid_game:
			report_out(r, "closed")
			notice.emit("The app was closed during round %d — you're out" % r)
		else:
			report_out(r, "late")
			notice.emit("Your connection was too slow — you're out in round %d" % r)
		_resumed_mid_game = false
		return
	_resumed_mid_game = false
	_pending_round = r
	_pending_recv_ms = Time.get_ticks_msec()
	round_started.emit(r)
	_route_to_class_if_wandering()

# The round waiting to be played, if any: {r, recv_ms}. Clears it.
func take_pending_round() -> Dictionary:
	if _pending_round <= 0:
		return {}
	var out := {"r": _pending_round, "recv_ms": _pending_recv_ms}
	_pending_round = 0
	return out

func has_pending_round() -> bool:
	return _pending_round > 0

# Put the game into class mode for this class (the screen then opens the game).
func prepare_game() -> void:
	GameState.class_context = {"id": class_id, "seed": int(doc.get("seed", 1))}
	GameState.contest_context = {}
	GameState.set_difficulty("hard")
	if not _coins_open:
		CoinsManager.start_game_session()
		_coins_open = true

# A completed round. One merge write.
func report_round(r: int, pts: int, ms: int) -> void:
	if class_id.is_empty() or _self_out_round > 0:
		return
	var s := int(_my_row.get("s", 0)) + pts
	var t := int(_my_row.get("t", 0)) + ms
	var row := {"n": _name(), "d": _device, "st": "in", "r": r, "s": s, "t": t,
		"ls": pts, "lt": ms, "f": 0}
	_my_row.merge(row, true)
	_write_row(class_id, row, false)

# I'm out (failed / late / left). One merge write. Idempotent.
func report_out(r: int, reason: String) -> void:
	if class_id.is_empty():
		return
	if _self_out_round > 0 and reason != "left":
		return
	_self_out_round = r if _self_out_round <= 0 else _self_out_round
	_self_out_reason = reason if _self_out_reason.is_empty() or reason == "left" else _self_out_reason
	var row := {"n": _name(), "d": _device, "st": "left" if reason == "left" else "out",
		"f": _self_out_round, "r": int(_my_row.get("r", 0)),
		"s": int(_my_row.get("s", 0)), "t": int(_my_row.get("t", 0)),
		"ls": int(_my_row.get("ls", 0)), "lt": int(_my_row.get("lt", 0))}
	_my_row.merge(row, true)
	_write_row(class_id, row, false)
	changed.emit()

# Leave the class for good (student). Lobby: frees the spot. Mid-game: counts as out.
func leave_class() -> void:
	if class_id.is_empty() or is_host:
		close_out()
		return
	var phase := student_phase()
	if phase == "lobby":
		_write_row(class_id, {"n": _name(), "d": _device, "st": "left"}, false)
	elif phase == "playing":
		report_out(maxi(1, int(doc.get("round", 1))), "left")
	close_out()

# Bank this class's coins (once).
func commit_coins() -> void:
	if not _coins_open:
		return
	_coins_open = false
	coins_earned = CoinsManager.session_earned
	CoinsManager.commit_session()

# The ms (server) by which the current round should be over for an on-time player.
func round_expected_end_ms() -> int:
	return ClassRules.expected_end_ms(int(doc.get("round_at_ms", 0)), int(doc.get("round", 1)))

func round_deadline_ms() -> int:
	return ClassRules.deadline_ms(int(doc.get("round_at_ms", 0)), int(doc.get("round", 1)))

# A student wandered off to another screen while their class is about to play: bring
# them back so round 1 isn't lost to the shop.
func _route_to_class_if_wandering() -> void:
	var gm := get_tree().current_scene
	if gm == null or not gm.has_method("show_class") or not gm.has_method("current_screen_kind"):
		return
	var kind := String(gm.call("current_screen_kind"))
	if kind == "game" or kind == "class":
		return
	gm.call("show_class")

# Student watchdog: local checks every WATCH_TICK, a read only when something is
# actually overdue (see TEACHER_LATE_SECS / LOBBY_CHECK_SECS).
func _on_watch() -> void:
	if class_id.is_empty() or is_host or gone or _wd_busy:
		return
	var st := String(doc.get("status", ""))
	var now := server_unix()
	var need_read := false
	if st == "lobby":
		need_read = now > int(doc.get("expires_unix", 0)) + 30
	elif st == "playing":
		var overdue := server_ms() > round_deadline_ms() + TEACHER_LATE_SECS * 1000
		if overdue != teacher_late:
			teacher_late = overdue
			changed.emit()
		need_read = overdue
	else:
		return
	if not need_read or now < _wd_next_read:
		return
	_wd_next_read = now + (LOBBY_CHECK_SECS if st == "lobby" else LATE_CHECK_SECS)
	await _check_now()

# One read of the class doc (watchdog / resume). Picks up a missed push or a delete.
func _check_now() -> void:
	if class_id.is_empty() or _wd_busy:
		return
	_wd_busy = true
	var pid := class_id
	var res := await _read_class(pid)
	_wd_busy = false
	if pid != class_id:
		return
	var st := String(res.get("status", "error"))
	if st == "missing":
		gone = true
		if not is_host:
			_clear_pointer()
		changed.emit()
	elif st == "ok":
		_on_class_doc(res["doc"], false)

func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_RESUMED or class_id.is_empty():
		return
	# Some phones (seen on a OnePlus) cut a backgrounded app's network, and pushes
	# that should have arrived meanwhile never do. Re-attach every listener so each
	# one starts again from a fresh server snapshot (one read per listened doc).
	if not _is_editor:
		for p in _listening:
			Firebase.firestore.stop_listening_to_document(p)
			Firebase.firestore.listen_to_document(p)
	if is_host:
		call_deferred("_resync_after_resume")
	else:
		call_deferred("_check_now")

# Recover my running totals after an app restart (one read of my own shard).
func _load_my_row() -> void:
	var k := ClassRules.shard_of(_uid())
	var res := await _rest_get(_REPORTS, ClassRules.shard_id(class_id, k))
	if String(res.get("status", "")) != "ok":
		return
	var players := _shape_players((res["data"] as Dictionary).get("players", {}))
	if players.has(_uid()):
		_my_row = players[_uid()]
		if String(_my_row.get("st", "")) == "out" or String(_my_row.get("st", "")) == "left":
			_self_out_round = maxi(1, int(_my_row.get("f", 0)))
			_self_out_reason = "left" if String(_my_row.get("st", "")) == "left" else "failed"

# ---------------------------------------------------------------------------
# Teacher side
# ---------------------------------------------------------------------------

# Read all 5 shards over REST and rebuild the referee's rows (a 404 is an empty shard).
# All-or-nothing: if ANY read fails (we're offline) nothing is applied and this returns
# false, so a half-read set of shards can never be judged.
func _resync_shards() -> bool:
	if referee == null:
		return false
	_resyncing = true
	var fresh := {}
	var ok := true
	for k in ClassRules.SHARDS:
		var res := await _rest_get(_REPORTS, ClassRules.shard_id(class_id, k))
		if referee == null:
			_resyncing = false
			return false
		var st := String(res.get("status", "error"))
		if st == "ok":
			fresh[k] = _shape_players((res["data"] as Dictionary).get("players", {}))
		elif st == "missing":
			fresh[k] = {}
		else:
			ok = false
			break
	if ok:
		for k in fresh:
			referee.set_shard(k, fresh[k])
	_resyncing = false
	changed.emit()
	return ok

func _resync_after_resume() -> void:
	await _resync_shards()
	_run_referee()

func _on_tick() -> void:
	if _is_editor:
		_sim_tick()
	if is_host:
		_run_referee()

# Ask the referee whether anything must be written now, and write it.
#
# A round is NEVER judged off the listener alone. The listener only tells us what
# reached THIS device: a teacher whose phone dropped off the network would see no
# reports at all, and at the deadline would count the whole class out (seen in
# testing: 26 students who finished in time, all marked out). So whenever a round is
# due, the referee first re-reads the 5 shards from the server; if that fails we're
# offline and nothing is judged — the game simply pauses (students see "waiting for
# your teacher") until the read succeeds. 5 reads per round.
func _run_referee() -> void:
	if referee == null or _resyncing or _confirming:
		return
	var w := referee.lobby_upkeep(server_unix())
	if not w.is_empty():
		_teacher_write(w)
		return
	if referee.tick(server_ms(), server_unix()).is_empty():
		return                                   # nothing due yet
	if Time.get_ticks_msec() < _confirm_retry_ms:
		return
	_confirming = true
	var ok := await _resync_shards()
	_confirming = false
	if referee == null:
		return
	if not ok:
		_confirm_retry_ms = Time.get_ticks_msec() + 3000
		if not teacher_offline:
			teacher_offline = true
			changed.emit()
		return
	if teacher_offline:
		teacher_offline = false
		changed.emit()
	# Judged on fresh rows, stamped with the time NOW (after we know we're online).
	w = referee.tick(server_ms(), server_unix())
	if not w.is_empty():
		_teacher_write(w)

func _teacher_write(w: Dictionary) -> void:
	if referee == null:
		return
	referee.apply(w)
	doc = referee.doc.duplicate(true)
	_write_doc(_COLL, class_id, w, true, false)
	changed.emit()

func lobby_students() -> Array:
	return referee.lobby_students() if referee else []

func progress() -> Dictionary:
	return referee.progress() if referee else {}

# {ok} or {ok:false, error: too_few | not_lobby}
func start_class() -> Dictionary:
	if referee == null:
		return {"ok": false, "error": "not_host"}
	var seed := (randi() & 0x7FFFFFFF)
	if seed == 0:
		seed = 1
	var w := referee.start(server_ms(), server_unix(), seed)
	if w.has("error"):
		return {"ok": false, "error": w["error"]}
	_teacher_write(w)
	return {"ok": true}

func kick(uid: String) -> void:
	if referee == null:
		return
	_teacher_write(referee.kick(uid, server_unix()))

func end_game() -> void:
	if referee == null:
		return
	var w := referee.end_now(server_unix())
	if not w.is_empty():
		_teacher_write(w)

func cancel_class() -> void:
	if referee == null:
		return
	if referee.status() == "finished" or referee.status() == "cancelled":
		return
	_teacher_write(referee.cancel(server_unix()))

# Shaped live roster for the teacher's board: [{uid, n, state, out_round}] where state
# is done | failed | pending | out.
func board_rows() -> Array:
	if referee == null:
		return []
	var out: Array = []
	var r := int(doc.get("round", 0))
	var o: Dictionary = doc.get("out", {})
	var ros: Dictionary = doc.get("roster", {})
	for uid in ros:
		if referee.is_kicked(uid):
			continue
		var e := {"uid": uid, "n": String((ros[uid] as Dictionary).get("n", "Student"))}
		if o.has(uid):
			e["state"] = "out"
			e["out_round"] = int(o[uid])
		else:
			e["state"] = referee.answer(uid, r)
		out.append(e)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ka := 1 if a["state"] == "out" else 0
		var kb := 1 if b["state"] == "out" else 0
		if ka != kb:
			return ka < kb
		return String(a["n"]) < String(b["n"]))
	return out

# ---------------------------------------------------------------------------
# Results (everyone)
# ---------------------------------------------------------------------------

# Final standings, best first: [{uid, n, r, s, t, p, is_me}].
func standings() -> Array:
	var res: Dictionary = doc.get("results", {})
	var arr: Array = []
	for uid in res:
		var e: Dictionary = res[uid]
		arr.append({"uid": uid, "n": String(e.get("n", "Student")), "r": int(e.get("r", 0)),
			"s": int(e.get("s", 0)), "t": int(e.get("t", 0)), "p": int(e.get("p", 0)),
			"is_me": uid == _uid()})
	arr.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["p"]) != int(b["p"]):
			return int(a["p"]) < int(b["p"])
		return String(a["n"]) < String(b["n"]))
	return arr

# ---------------------------------------------------------------------------
# Shaping
# ---------------------------------------------------------------------------

func shape_class(raw: Dictionary, pid: String) -> Dictionary:
	var ros := {}
	var rr: Variant = raw.get("roster", {})
	if rr is Dictionary:
		for uid in rr:
			var e: Variant = rr[uid]
			if e is Dictionary:
				ros[uid] = {"n": String(e.get("n", "Student")), "d": String(e.get("d", ""))}
	var outm := {}
	var ro: Variant = raw.get("out", {})
	if ro is Dictionary:
		for uid in ro:
			outm[uid] = int(ro[uid])
	var kicked := {}
	var rk: Variant = raw.get("kicked", {})
	if rk is Dictionary:
		for uid in rk:
			kicked[uid] = true
	var results := {}
	var rs: Variant = raw.get("results", {})
	if rs is Dictionary:
		for uid in rs:
			var e2: Variant = rs[uid]
			if e2 is Dictionary:
				results[uid] = {"n": String(e2.get("n", "Student")), "r": int(e2.get("r", 0)),
					"s": int(e2.get("s", 0)), "t": int(e2.get("t", 0)), "p": int(e2.get("p", 0))}
	return {
		"id": pid,
		"v": int(raw.get("v", 0)),
		"teacher_uid": String(raw.get("teacher_uid", "")),
		"teacher_name": String(raw.get("teacher_name", "Teacher")),
		"status": String(raw.get("status", "lobby")),
		"created_at": int(raw.get("created_at", 0)),
		"started_at": int(raw.get("started_at", 0)),
		"finished_at": int(raw.get("finished_at", 0)),
		"expires_unix": int(raw.get("expires_unix", 0)),
		"full": bool(raw.get("full", false)),
		"seed": int(raw.get("seed", 0)),
		"round": int(raw.get("round", 0)),
		"round_at_ms": int(raw.get("round_at_ms", 0)),
		"alive": int(raw.get("alive", 0)),
		"ended_early": bool(raw.get("ended_early", false)),
		"roster": ros,
		"out": outm,
		"kicked": kicked,
		"results": results,
	}

func _shape_players(raw: Variant) -> Dictionary:
	var out := {}
	if not (raw is Dictionary):
		return out
	for uid in raw:
		var p: Variant = raw[uid]
		if not (p is Dictionary):
			continue
		out[uid] = {
			"n": String(p.get("n", "Student")), "d": String(p.get("d", "")),
			"j": int(p.get("j", 0)), "st": String(p.get("st", "lobby")),
			"r": int(p.get("r", 0)), "s": int(p.get("s", 0)), "t": int(p.get("t", 0)),
			"ls": int(p.get("ls", 0)), "lt": int(p.get("lt", 0)), "f": int(p.get("f", 0)),
		}
	return out

# ---------------------------------------------------------------------------
# Storage adapter (plugin / REST  <->  editor sim)
# ---------------------------------------------------------------------------

func _read_class(pid: String) -> Dictionary:
	if not ClassRules.valid_pid(pid):
		return {"status": "missing"}
	var res := await _rest_get(_COLL, pid)
	if String(res.get("status", "")) != "ok":
		return {"status": res.get("status", "error")}
	return {"status": "ok", "doc": shape_class(res["data"], pid)}

func _write_row(pid: String, row: Dictionary, wait: bool) -> bool:
	var k := ClassRules.shard_of(_uid())
	return await _write_doc(_REPORTS, ClassRules.shard_id(pid, k),
		{"players": {_uid(): row}}, true, wait)

# Merge/set write. Fire-and-forget unless `wait`: the SDK queues writes made offline
# and sends them on reconnect, which is exactly what a student who drops for a second
# mid-round needs — the report still lands if it can beat the deadline.
func _write_doc(coll: String, id: String, data: Dictionary, merge: bool, wait: bool) -> bool:
	if _is_editor:
		_sim_write(coll + "/" + id, data, merge)
		return true
	Firebase.firestore.set_document(coll, id, data, merge)
	if not wait:
		return true
	var res: Variant = await Firebase.firestore.write_task_completed
	return not (res is Dictionary and (res as Dictionary).get("status", true) == false)

# {status: ok|missing|error, data}. Also feeds the server-time offset.
func _rest_get(coll: String, id: String) -> Dictionary:
	if _is_editor:
		await get_tree().process_frame
		var d: Variant = _sim_docs.get(coll + "/" + id, null)
		if d is Dictionary:
			return {"status": "ok", "data": (d as Dictionary).duplicate(true)}
		return {"status": "missing", "data": {}}
	var http := HTTPRequest.new()
	http.timeout = 6.0
	add_child(http)
	var t0 := _unix()
	if http.request(_FB_BASE + "/" + coll + "/" + id) != OK:
		http.queue_free()
		return {"status": "error", "data": {}}
	var r: Array = await http.request_completed
	var t1 := _unix()
	http.queue_free()
	var code := int(r[1])
	if code == 200 or code == 404:
		_note_server_date(r[2], t0, t1)
	if code == 404:
		return {"status": "missing", "data": {}}
	if code != 200:
		return {"status": "error", "data": {}}
	var j := JSON.new()
	if j.parse((r[3] as PackedByteArray).get_string_from_utf8()) != OK or not (j.data is Dictionary):
		return {"status": "error", "data": {}}
	return {"status": "ok", "data": _fields((j.data as Dictionary).get("fields", {}))}

# The HTTP Date header has 1 s resolution; the server stamped it somewhere inside
# [t0, t1]. Keep the estimate with the smallest error bound.
func _note_server_date(headers: Variant, t0: float, t1: float) -> void:
	if not (headers is PackedStringArray):
		return
	for h: String in headers:
		if not h.to_lower().begins_with("date:"):
			continue
		var server := _parse_http_date(h.substr(5).strip_edges())
		if server <= 0:
			return
		var err := 0.5 + (t1 - t0) * 0.5
		if err < _offset_err:
			_offset_err = err
			_offset = (float(server) + 0.5) - (t0 + t1) * 0.5
		return

# "Wed, 07 Oct 2026 12:55:01 GMT" -> unix seconds (0 on failure).
static func _parse_http_date(s: String) -> int:
	const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var parts := s.replace(",", "").split(" ", false)
	if parts.size() < 5:
		return 0
	var mon := MONTHS.find(parts[2]) + 1
	var hms := parts[4].split(":")
	if mon <= 0 or hms.size() != 3:
		return 0
	return Time.get_unix_time_from_datetime_dict({
		"year": int(parts[3]), "month": mon, "day": int(parts[1]),
		"hour": int(hms[0]), "minute": int(hms[1]), "second": int(hms[2]),
	})

func _gen_pid() -> String:
	var s := ""
	for _i in ClassRules.PID_LEN:
		s += str(randi() % 10)
	if s.begins_with("0"):
		s = "1" + s.substr(1)              # reads better on a projector
	return s

func _load_device_token() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(_DEVICE_PATH) == OK:
		var t := String(cfg.get_value("device", "token", ""))
		if not t.is_empty():
			return t
	var tok := ""
	const ALPHA := "abcdefghijkmnpqrstuvwxyz23456789"
	for _i in 10:
		tok += ALPHA[randi() % ALPHA.length()]
	cfg.set_value("device", "token", tok)
	cfg.save(_DEVICE_PATH)
	return tok

func _on_signed_out() -> void:
	detach()
	_my_row = {}
	_coins_open = false

func _val(v: Variant) -> Variant:
	if not v is Dictionary: return null
	if v.has("stringValue"):    return v["stringValue"]
	if v.has("integerValue"):   return int(v["integerValue"])
	if v.has("doubleValue"):    return float(v["doubleValue"])
	if v.has("booleanValue"):   return bool(v["booleanValue"])
	if v.has("nullValue"):      return null
	if v.has("arrayValue"):
		var a := []
		for item in v["arrayValue"].get("values", []):
			a.append(_val(item))
		return a
	if v.has("mapValue"):
		return _fields(v["mapValue"].get("fields", {}))
	return null

func _fields(f: Dictionary) -> Dictionary:
	var out := {}
	for k in f:
		var v: Variant = _val(f[k])
		if v != null:
			out[k] = v
	return out

# ===========================================================================
#  EDITOR SIM — the whole class lifecycle without a device or Firestore.
#  Teacher mode: bots join the lobby and play rounds (some fail, some "lose
#  connection" and never answer, one leaves). Student mode (editor_teacher =
#  false): joining any 6-digit PID conjures a class with a pretend teacher whose
#  referee runs here, plus bot classmates. Nothing below runs on Android.
# ===========================================================================

const SIM_BOTS := 14
var _sim_docs: Dictionary = {}       # "coll/id" -> data
var _sim_bots: Array = []            # [{uid, n, join_at, skill, ghost, leaver}]
var _sim_ref: ClassReferee = null    # the pretend teacher (student mode)
var _sim_ref_pid := ""

func _sim_write(path: String, data: Dictionary, merge: bool) -> void:
	if not merge or not _sim_docs.has(path):
		_sim_docs[path] = data.duplicate(true)
	else:
		_sim_merge(_sim_docs[path], data)
	call_deferred("_sim_deliver", path)

static func _sim_merge(dst: Dictionary, src: Dictionary) -> void:
	for k in src:
		# Like Firestore: an EMPTY map in a merge write replaces the field outright.
		if src[k] is Dictionary and not (src[k] as Dictionary).is_empty() and dst.get(k, null) is Dictionary:
			_sim_merge(dst[k], src[k])
		else:
			dst[k] = src[k] if not (src[k] is Dictionary) else (src[k] as Dictionary).duplicate(true)

func _sim_deliver(path: String) -> void:
	if not _listening.has(path) or not _sim_docs.has(path):
		return
	_on_document_changed(path, (_sim_docs[path] as Dictionary).duplicate(true))

func _sim_spawn_bots(pid: String) -> void:
	_sim_bots.clear()
	const NAMES := ["Maya", "Noam", "Lia", "Omer", "Tamar", "Itai", "Noa", "Yoav",
		"Shira", "Ariel", "Eden", "Roni", "Gal", "Amit", "Yael", "Ido"]
	var now := server_unix()
	for i in SIM_BOTS:
		_sim_bots.append({
			"uid": "bot_%02d" % i, "n": NAMES[i % NAMES.size()],
			"join_at": now + 1 + i / 3,
			"skill": randf_range(0.25, 0.9),
			"ghost": i == 3,                   # "loses connection" in round 2
			"leaver": i == 5,                  # walks out of the lobby
			"plan": {},
		})
	_sim_ref_pid = pid

# Student-mode: a class run by a pretend teacher.
func _sim_make_teacher_class(pid: String) -> void:
	var now := server_unix()
	var data := {
		"v": ClassRules.VERSION, "teacher_uid": "sim_teacher", "teacher_name": "Ms. Sim",
		"status": "lobby", "created_at": now, "started_at": 0, "finished_at": 0,
		"expires_unix": now + ClassRules.LOBBY_TTL, "full": false, "seed": 0,
		"round": 0, "round_at_ms": 0, "alive": 0,
	}
	_sim_docs[_COLL + "/" + pid] = data
	_sim_ref = ClassReferee.new()
	_sim_ref.setup(pid, shape_class(data, pid))
	_sim_spawn_bots(pid)

func _sim_shard_players(pid: String, k: int) -> Dictionary:
	var d: Variant = _sim_docs.get(_REPORTS + "/" + ClassRules.shard_id(pid, k), null)
	return (d as Dictionary).get("players", {}) if d is Dictionary else {}

func _sim_tick() -> void:
	var pid := _sim_ref_pid
	if pid.is_empty():
		return
	var cpath := _COLL + "/" + pid
	if not _sim_docs.has(cpath):
		return
	var cdoc := shape_class(_sim_docs[cpath], pid)
	var now := server_unix()
	var now_ms := server_ms()
	for b: Dictionary in _sim_bots:
		var uid := String(b["uid"])
		var k := ClassRules.shard_of(uid)
		var spath := _REPORTS + "/" + ClassRules.shard_id(pid, k)
		var row: Dictionary = _sim_shard_players(pid, k).get(uid, {})
		match String(cdoc["status"]):
			"lobby":
				if row.is_empty() and now >= int(b["join_at"]):
					_sim_write(spath, {"players": {uid: {"n": b["n"], "d": "bot", "j": now,
						"st": "lobby", "r": 0, "s": 0, "t": 0, "ls": 0, "lt": 0, "f": 0}}}, true)
				elif bool(b["leaver"]) and String(row.get("st", "")) == "lobby" \
						and now >= int(b["join_at"]) + 6:
					_sim_write(spath, {"players": {uid: {"st": "left"}}}, true)
			"playing":
				if not (cdoc["roster"] as Dictionary).has(uid) or (cdoc["out"] as Dictionary).has(uid):
					continue
				var r := int(cdoc["round"])
				if int(row.get("r", 0)) >= r or String(row.get("st", "")) in ["out", "left"]:
					continue
				if bool(b["ghost"]) and r >= 2:
					continue                       # silent: the referee must time it out
				var plan: Dictionary = b["plan"]
				if int(plan.get("r", 0)) != r:
					var lim := ClassRules.limit(r)
					var used := lim * clampf(randf_range(0.2, 1.15) * (1.2 - float(b["skill"])), 0.1, 1.2)
					var start_ms := int(cdoc["round_at_ms"]) + int((ClassRules.banner(r) + ClassRules.playback(r)) * 1000.0)
					var fail := randf() > lerpf(0.82, 0.97, float(b["skill"])) or used > lim
					plan = {"r": r, "at": start_ms + int(minf(used, lim) * 1000.0), "fail": fail,
						"ms": int(minf(used, lim) * 1000.0), "pts": ClassRules.points(lim - used, lim)}
					b["plan"] = plan
				if now_ms < int(plan["at"]):
					continue
				if bool(plan["fail"]):
					_sim_write(spath, {"players": {uid: {"st": "out", "f": r}}}, true)
				else:
					_sim_write(spath, {"players": {uid: {"st": "in", "r": r,
						"s": int(row.get("s", 0)) + int(plan["pts"]), "t": int(row.get("t", 0)) + int(plan["ms"]),
						"ls": int(plan["pts"]), "lt": int(plan["ms"])}}}, true)
	# The pretend teacher (student mode): same referee code as a real teacher.
	if _sim_ref != null:
		for k in ClassRules.SHARDS:
			_sim_ref.set_shard(k, _shape_players(_sim_shard_players(pid, k)))
		_sim_ref.on_doc(cdoc)
		var w := {}
		if _sim_ref.status() == "lobby":
			# Auto-start once the human and a few bots are in.
			var waiting := _sim_ref.lobby_students()
			var me_in := false
			for e: Dictionary in waiting:
				if e["uid"] == _uid():
					me_in = true
			if me_in and waiting.size() >= 6:
				w = _sim_ref.start(now_ms, now, randi() % 100000 + 1)
		else:
			w = _sim_ref.tick(now_ms, now)
		if not w.is_empty() and not w.has("error"):
			_sim_ref.apply(w)
			_sim_write(cpath, w, true)
