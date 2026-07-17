extends Node

# Arena rooms. A player CREATES a room (a name + difficulty + public/private),
# shares its short ID (or lists it publicly), friends JOIN, everyone sits in a
# LIVE lobby, the creator presses PLAY, and then ALL players race the SAME Simon
# sequence at once (one attempt each). As players finish they land on a live
# "who's still playing / who finished" screen; once everyone is done the frozen
# final leaderboard is shown.
#
# --- Storage model (why it looks like this) --------------------------------
# There is NO server (no Cloud Functions), and the Android Firebase plugin can
# only listen to a SINGLE document (not a query). So the entire room lives in ONE
# document and every client attaches a document listener to it:
#
#   contests/{CID} -> {
#       id, title, creator_uid, creator_name, difficulty, is_public,
#       status: "lobby" | "playing" | "finished",
#       seed,                       # shared RNG seed for the race (0 until start)
#       member_count,               # derived (non-"left" players); browse/rules hint
#       created_at, started_at, finished_at, expires_at (TTL),
#       lobby_key,                  # public+lobby only; ranged browse query key
#       players: { <uid>: { name, is_creator, joined_at,
#                           state: "lobby"|"playing"|"done"|"left",
#                           score, finished_at } }
#   }
#
# Each client writes ONLY its own player key via set_document(merge:true) — a
# Firestore deep-merge preserves sibling keys, so concurrent joins/score writes
# never clobber each other. "Leaving" tombstones the key (state="left") because a
# merge can't delete a map key; the UI filters tombstones out. The whole doc is
# deleted when the creator cancels in lobby, or the last real player leaves.
#
# Reads (initial fetch + lobby browse) use Firestore's REST endpoints (the
# plugin's collection callbacks are unreliable on Android — same as the
# leaderboard). Writes/deletes and the live listener go through the plugin so the
# native FirebaseAuth context is applied and rules see request.auth.
#
# Editor (non-Android) runs an in-memory sim mirroring the live shape so the whole
# create -> join -> start -> play -> finish lifecycle is testable without a device;
# watch_room() re-emits the sim room after every local write.
#
# Trust model: scores/standings are client-trusted (same posture as the
# leaderboards). Rules bound structure only — a shared room doc can't be defended
# key-by-key.

# Live snapshot of a watched room. `room` is a shaped dict (see _shape_room); an
# empty {} means the room is gone (deleted / not found).
signal room_changed(cid: String, room: Dictionary)

# ---- caps / limits ----
const MAX_MEMBERS := 45
# How many public lobby rooms the browse screen pulls per (single) fetch.
const LOBBY_FETCH := 10
# Room titles are player-authored; displayed big and clamped everywhere
# (mirrors ArenaUI.TITLE_MAX + titleOk() in firestore.rules).
const TITLE_MAX := 15

const DIFFS: Array[String] = ["easy", "moderate", "hard"]

# TTL horizon written to `expires_at` on every write. Firestore TTL reaps orphans
# if a client never runs cleanup.
const TTL_SECS := 3 * 86400

const ID_LEN := 6
# Crockford base32 minus I,L,O,U — unambiguous when shared verbally / typed.
const ID_ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
const MAX_SCORE := 9999   # mirror scoreOk() in firestore.rules

const _COLL := "contests"
const _FB_BASE := "https://firestore.googleapis.com/v1/projects/simon-6bc39/databases/(default)/documents"

var _is_editor := OS.get_name() != "Android"

# ---- editor sim store (shape mirrors Firestore) ----
var _sim_rooms: Dictionary = {}       # cid -> room dict

# Rooms this client currently has a live listener attached to (so document_changed
# only re-emits for docs a screen actually asked to watch).
var _watching: Dictionary = {}        # cid -> true

# The room this client is currently participating in (set on create/join, cleared
# on leave). Lets a screen re-enter and guards accidental double-joins.
var current_room_id: String = ""

func _ready() -> void:
	if not _is_editor:
		Firebase.firestore.document_changed.connect(_on_document_changed)

func _uid() -> String:  return FirebaseManager.uid
func _name() -> String:
	var n := FirebaseManager.display_name
	return n if not n.is_empty() else "Player"

func _now() -> int: return int(Time.get_unix_time_from_system())

func _expires_iso(base_now: int) -> String:
	return Time.get_datetime_string_from_unix_time(base_now + TTL_SECS) + "Z"

# ---- static display helpers (screens reuse these) ----

static func diff_label(d: String) -> String:
	return d.capitalize()

# =====================================================================
#  CREATE
# =====================================================================

# Funny fallback room names (all within TITLE_MAX). Offered as suggestions on the
# create screen and used when a player leaves the name blank.
const FUNNY_NAMES: Array[String] = [
	"Thumb Wars", "Combo Chaos", "Brain Freeze", "Simon Smackdown",
	"Tap Titans", "Recall Rumble", "Pattern Panic", "Mind Meltdown",
	"Button Mashers", "Sequence Slam", "The Gauntlet", "Neuron Nuke",
	"Flashback Fight", "Echo Chamber", "Total Recall", "Memory Lane",
	"Blinkin' Havoc", "Colour Clash", "Rapid Recall", "Simon Says No",
]

static func random_title() -> String:
	return FUNNY_NAMES[randi() % FUNNY_NAMES.size()]

# Sanitizes a player-authored title to the shared limit; blank -> a random funny name.
static func clean_title(raw: String) -> String:
	var s := raw.strip_edges()
	if s.is_empty():
		return random_title()
	if s.length() > TITLE_MAX:
		s = s.substr(0, TITLE_MAX)
	return s

# Returns {ok, id} or {ok:false, error}.
# `is_public` rooms are discoverable in the browse-lobby (see load_lobby_contests);
# private ones can only be joined with the shared ID.
func create_contest(difficulty: String, title: String = "",
		is_public: bool = true) -> Dictionary:
	if _uid().is_empty() or not FirebaseManager.has_display_name():
		return {"ok": false, "error": "auth"}
	if not DIFFS.has(difficulty):
		return {"ok": false, "error": "bad_args"}

	var now := _now()
	for _attempt in 6:
		var cid := _gen_id()
		if await _room_exists(cid):
			continue
		var room := {
			"id": cid,
			"title": clean_title(title),
			"creator_uid": _uid(),
			"creator_name": _name(),
			"difficulty": difficulty,
			"status": "lobby",
			"is_public": is_public,
			"seed": 0,
			"member_count": 1,
			"created_at": now,
			"started_at": 0,
			"finished_at": 0,
			"expires_at": _expires_iso(now),
			"players": {_uid(): _new_player(true, now)},
		}
		# A public, still-in-lobby room carries a uniform random `lobby_key` in
		# [0,1). The browse-lobby fetches a random slice with a single ranged query
		# on this one field (see load_lobby_contests). Private rooms omit it, so they
		# never surface; on start we drop it below range so started rooms leave the lobby.
		if is_public:
			room["lobby_key"] = randf()
		await _write_room(cid, room, false)
		current_room_id = cid
		BadgeManager.note_contest_hosted()   # "Host With Most" badge
		return {"ok": true, "id": cid}
	return {"ok": false, "error": "id_collision"}

func _new_player(is_creator: bool, now: int) -> Dictionary:
	return {
		"name": _name(),
		"is_creator": is_creator,
		"joined_at": now,
		"state": "lobby",
		"score": 0,
		"finished_at": 0,
	}

# =====================================================================
#  JOIN
# =====================================================================

# Returns {ok} or {ok:false, error} with error in {auth, not_found, ended, full}.
func join_contest(raw_id: String) -> Dictionary:
	if _uid().is_empty() or not FirebaseManager.has_display_name():
		return {"ok": false, "error": "auth"}
	var cid := raw_id.strip_edges().to_upper()
	if not _valid_id(cid):
		return {"ok": false, "error": "not_found"}

	var room := await _load_room(cid)
	if room.is_empty():
		return {"ok": false, "error": "not_found"}
	if String(room.get("status", "")) != "lobby":
		return {"ok": false, "error": "ended"}

	var players: Dictionary = room.get("players", {})
	# Already an active member? Treat join as a no-op success so the UI just opens it.
	var mine: Dictionary = players.get(_uid(), {})
	if not mine.is_empty() and String(mine.get("state", "")) != "left":
		current_room_id = cid
		return {"ok": true, "already": true}
	if _count_active(players) >= MAX_MEMBERS:
		return {"ok": false, "error": "full"}

	var now := _now()
	await _write_player(cid, _uid(), _new_player(false, now))
	# Recompute the count from the roster we already read, counting myself once.
	players[_uid()] = _new_player(false, now)
	await _write_room(cid, {
		"member_count": _count_active(players),
		"expires_at": _expires_iso(now),
	}, true)
	current_room_id = cid
	BadgeManager.note_contest_joined()   # "Challenger" / "Regular" badges
	return {"ok": true}

# Count of participants whose row isn't a "left" tombstone.
func _count_active(players: Dictionary) -> int:
	var n := 0
	for uid in players:
		var p: Dictionary = players[uid]
		if String(p.get("state", "")) != "left":
			n += 1
	return n

# =====================================================================
#  LEAVE / CANCEL
# =====================================================================

# A normal participant leaves (also used when the creator leaves a lobby, which
# tears the whole room down for everyone).
func leave_contest(cid: String) -> void:
	var room := await _load_room(cid)
	if current_room_id == cid:
		current_room_id = ""
	if room.is_empty():
		return
	var is_creator := String(room.get("creator_uid", "")) == _uid()
	var status := String(room.get("status", ""))

	# Creator abandoning a lobby cancels the room entirely.
	if is_creator and status == "lobby":
		await _delete_room(cid)
		return

	# Tombstone my own row, then republish the active count. The delete rule keys on
	# member_count <= 0, so a last-leaver must lower it before the doc can be removed.
	await _write_player(cid, _uid(), {"state": "left"})
	var players: Dictionary = room.get("players", {})
	if players.has(_uid()):
		players[_uid()]["state"] = "left"
	var remaining := _count_active(players)
	await _write_room(cid, {
		"member_count": remaining,
		"expires_at": _expires_iso(_now()),
	}, true)
	if remaining <= 0:
		await _delete_room(cid)

# Best-effort cleanup on account deletion: leave whatever room we're currently in.
# The single-doc model has no per-uid query, so we can only reach the active room;
# any earlier orphan rows are reaped by Firestore TTL.
func leave_all() -> void:
	if not current_room_id.is_empty():
		await leave_contest(current_room_id)

# Creator explicitly deletes the whole room (any status).
func cancel_room(cid: String) -> Dictionary:
	var room := await _load_room(cid)
	if current_room_id == cid:
		current_room_id = ""
	if room.is_empty():
		return {"ok": true}
	if String(room.get("creator_uid", "")) != _uid():
		return {"ok": false, "error": "not_creator"}
	# Drop member_count to 0 first so the empty-delete rule path also covers us.
	await _write_room(cid, {"member_count": 0}, true)
	await _delete_room(cid)
	return {"ok": true}

# Creator removes a member (tombstones their row).
func kick_member(cid: String, target_uid: String) -> Dictionary:
	var room := await _load_room(cid)
	if room.is_empty():
		return {"ok": false, "error": "not_found"}
	if String(room.get("creator_uid", "")) != _uid():
		return {"ok": false, "error": "not_creator"}
	if target_uid == _uid():
		return {"ok": false, "error": "cant_kick_self"}
	await _write_player(cid, target_uid, {"state": "left"})
	var players: Dictionary = room.get("players", {})
	if players.has(target_uid):
		players[target_uid]["state"] = "left"
	await _write_room(cid, {"member_count": _count_active(players)}, true)
	return {"ok": true}

# =====================================================================
#  START  (creator only)
# =====================================================================

# Flips the room to "playing" and stamps a shared RNG seed so every client
# generates the identical Simon sequence. Returns {ok, seed} or {ok:false,error}.
func start_room(cid: String) -> Dictionary:
	var room := await _load_room(cid)
	if room.is_empty():
		return {"ok": false, "error": "not_found"}
	if String(room.get("creator_uid", "")) != _uid():
		return {"ok": false, "error": "not_creator"}
	if String(room.get("status", "")) != "lobby":
		return {"ok": false, "error": "already_started"}

	var now := _now()
	var seed := randi()
	if seed == 0:
		seed = 1   # 0 is our "not started yet" sentinel
	await _write_room(cid, {
		"status": "playing",
		"started_at": now,
		"seed": seed,
		# Drop below the [0,1) key range so a started room disappears from browse.
		"lobby_key": -1.0,
		"expires_at": _expires_iso(now),
	}, true)
	return {"ok": true, "seed": seed}

# =====================================================================
#  GAMEPLAY HAND-OFF
# =====================================================================

# Sets the contest context on GameState, applies the difficulty, and marks this
# player in-progress. The SCREEN navigates to the game afterwards.
func begin_contest_game(cid: String, difficulty: String, seed: int) -> void:
	GameState.contest_context = {"id": cid, "difficulty": difficulty, "seed": seed}
	GameState.set_difficulty(difficulty)
	await _write_player(cid, _uid(), {"state": "playing"})

# Records this player's finished match (single attempt). `score` = rounds cleared.
# If every active player is now done, flips the room to "finished". Returns the
# (possibly finalized) shaped room.
func submit_result(cid: String, score: int) -> Dictionary:
	if cid.is_empty() or _uid().is_empty():
		return {}
	var s := clampi(score, 0, MAX_SCORE)
	var now := _now()
	await _write_player(cid, _uid(), {
		"name": _name(), "state": "done", "score": s, "finished_at": now,
	})

	var room := await _load_room(cid)
	if room.is_empty() or String(room.get("status", "")) != "playing":
		return room
	var players: Dictionary = room.get("players", {})
	# Guard read-after-write staleness for OUR row (REST reads are eventually
	# consistent): force our just-written done values in before the all-done check.
	if not players.has(_uid()):
		players[_uid()] = _new_player(false, now)
	players[_uid()]["state"] = "done"
	players[_uid()]["score"] = s
	players[_uid()]["finished_at"] = now

	if _all_done(players):
		await _write_room(cid, {
			"status": "finished", "finished_at": now, "expires_at": _expires_iso(now),
		}, true)
		room["status"] = "finished"
		room["finished_at"] = now
	room["players"] = players
	return room

# True when there's at least one active player and every active player is "done".
func _all_done(players: Dictionary) -> bool:
	var any := false
	for uid in players:
		var st := String((players[uid] as Dictionary).get("state", ""))
		if st == "left":
			continue
		any = true
		if st != "done":
			return false
	return any

# Any participant may finalize once every active player is done (idempotent — a
# stale read on the last finisher, or a client that only observed all-done from the
# results board, still converges the room to "finished").
func finalize_if_done(cid: String) -> void:
	var room := await _load_room(cid)
	if room.is_empty() or String(room.get("status", "")) != "playing":
		return
	if _all_done(room.get("players", {})):
		var now := _now()
		await _write_room(cid, {
			"status": "finished", "finished_at": now, "expires_at": _expires_iso(now),
		}, true)

# Creator forces the room to end now with current scores.
func finish_now(cid: String) -> Dictionary:
	var room := await _load_room(cid)
	if room.is_empty():
		return {"ok": false, "error": "not_found"}
	if String(room.get("creator_uid", "")) != _uid():
		return {"ok": false, "error": "not_creator"}
	if String(room.get("status", "")) != "playing":
		return {"ok": false, "error": "not_active"}
	var now := _now()
	await _write_room(cid, {
		"status": "finished", "finished_at": now, "expires_at": _expires_iso(now),
	}, true)
	room["status"] = "finished"
	room["finished_at"] = now
	return {"ok": true, "room": room}

# =====================================================================
#  STANDINGS
# =====================================================================

# Ordered Array of {uid, name, score, rank, is_me} from a room's players map.
# Sort: highest score first; tie -> whoever finished earlier; then join order.
# "left" tombstones and players who never finished sink appropriately.
func standings_from_room(room: Dictionary) -> Array:
	var players: Dictionary = room.get("players", {})
	var arr: Array = []
	for uid in players:
		var p: Dictionary = players[uid]
		if String(p.get("state", "")) == "left":
			continue
		arr.append({
			"uid": uid,
			"name": String(p.get("name", "Player")),
			"score": int(p.get("score", 0)),
			"finished_at": int(p.get("finished_at", 0)),
			"joined_at": int(p.get("joined_at", 0)),
		})
	arr.sort_custom(func(a, b):
		if a["score"] != b["score"]:
			return a["score"] > b["score"]
		var fa := int(a["finished_at"]) if int(a["finished_at"]) > 0 else 0x7FFFFFFF
		var fb := int(b["finished_at"]) if int(b["finished_at"]) > 0 else 0x7FFFFFFF
		if fa != fb:
			return fa < fb
		return int(a["joined_at"]) < int(b["joined_at"])
	)
	var out: Array = []
	for i in arr.size():
		var e: Dictionary = arr[i]
		out.append({
			"uid": e["uid"], "name": e["name"], "score": e["score"],
			"rank": i + 1, "is_me": String(e["uid"]) == _uid(),
		})
	return out

# =====================================================================
#  LOAD / LIVE WATCH
# =====================================================================

# One-shot fetch of a room's current state (shaped, or {} if gone). Screens use it
# for an immediate paint; watch_room() then keeps it live.
func load_room(cid: String) -> Dictionary:
	return await _load_room(cid)

# Attach a live listener for `cid`. Fires room_changed(cid, room) with the current
# state immediately and on every subsequent change (an empty room = deleted).
func watch_room(cid: String) -> void:
	if cid.is_empty():
		return
	_watching[cid] = true
	if _is_editor:
		call_deferred("_sim_emit", cid)
	else:
		Firebase.firestore.listen_to_document(_COLL + "/" + cid)

func unwatch_room(cid: String) -> void:
	if not _watching.has(cid):
		return
	_watching.erase(cid)
	if not _is_editor:
		Firebase.firestore.stop_listening_to_document(_COLL + "/" + cid)

# Android live-listener callback. `data` is the changed document (decoded by the
# plugin, or REST-style with a "fields" wrapper). An empty / identity-less payload
# means the doc was deleted.
func _on_document_changed(document_path: String, data: Dictionary) -> void:
	var prefix := _COLL + "/"
	var cid := document_path
	if document_path.begins_with(prefix):
		cid = document_path.substr(prefix.length())
	if not _watching.has(cid):
		return
	var raw: Dictionary = data
	if data.has("fields"):
		raw = _fields(data["fields"])
	if raw.is_empty() or not raw.has("creator_uid"):
		emit_signal("room_changed", cid, {})   # deleted / gone
		return
	emit_signal("room_changed", cid, _shape_room(raw, cid))

# Editor-sim emit for a watched room.
func _sim_emit(cid: String) -> void:
	if not _watching.has(cid):
		return
	var r: Variant = _sim_rooms.get(cid, null)
	emit_signal("room_changed", cid, _shape_room(r, cid) if r is Dictionary else {})

# Called after every sim write so watchers see the change live.
func _sim_touch(cid: String) -> void:
	if _watching.has(cid):
		_sim_emit(cid)

# =====================================================================
#  BROWSE LOBBY  (public, still-in-lobby rooms)
# =====================================================================

# Up to LOBBY_FETCH public rooms that are open (status == lobby), chosen
# (pseudo-)randomly with a SINGLE cheap ranged read on `lobby_key`. Each row is
# returned already-decoded so the screen shows title / difficulty / member_count
# without another read.
func load_lobby_contests() -> Array:
	var pivot := randf()
	var rows: Array
	if _is_editor:
		rows = _sim_lobby(pivot)
	else:
		rows = await _rest_query_lobby(pivot)
	var out: Array = []
	for raw in rows:
		if not (raw is Dictionary):
			continue
		if String(raw.get("status", "")) != "lobby":
			continue
		if not bool(raw.get("is_public", false)):
			continue
		out.append({
			"id": String(raw.get("id", "")),
			"title": String(raw.get("title", "Contest")),
			"difficulty": String(raw.get("difficulty", "easy")),
			"member_count": int(raw.get("member_count", 1)),
			"is_creator": String(raw.get("creator_uid", "")) == _uid(),
		})
	return out

func _sim_lobby(pivot: float) -> Array:
	var out: Array = []
	for cid in _sim_rooms:
		var m: Dictionary = _sim_rooms[cid]
		if not m.has("lobby_key"):
			continue
		if float(m.get("lobby_key", -1.0)) >= pivot:
			out.append(m.duplicate(true))
	out.sort_custom(func(a, b): return float(a.get("lobby_key", 0.0)) < float(b.get("lobby_key", 0.0)))
	return out.slice(0, LOBBY_FETCH)

# =====================================================================
#  ID helpers
# =====================================================================

func _gen_id() -> String:
	var s := ""
	for _i in ID_LEN:
		s += ID_ALPHABET[randi() % ID_ALPHABET.length()]
	return s

func _valid_id(cid: String) -> bool:
	if cid.length() != ID_LEN:
		return false
	for c in cid:
		if ID_ALPHABET.find(c) < 0:
			return false
	return true

# =====================================================================
#  STORAGE ADAPTER  (editor sim  <->  live Firestore)
# =====================================================================

func _room_exists(cid: String) -> bool:
	if _is_editor:
		return _sim_rooms.has(cid)
	var r := await _rest_get(_COLL, cid)
	return bool(r.get("exists", false))

func _load_room(cid: String) -> Dictionary:
	if not _valid_id(cid):
		return {}
	if _is_editor:
		var r: Variant = _sim_rooms.get(cid, null)
		return _shape_room(r, cid) if r is Dictionary else {}
	var res := await _rest_get(_COLL, cid)
	if not bool(res.get("exists", false)):
		return {}
	return _shape_room(res.get("data", {}), cid)

# Merge-write on the room doc. In the sim, `merge` deep-merges (including a nested
# `players` map) so a partial write never drops sibling fields/players.
func _write_room(cid: String, data: Dictionary, merge: bool) -> void:
	if _is_editor:
		if merge and _sim_rooms.has(cid):
			var room: Dictionary = _sim_rooms[cid]
			for k in data:
				if k == "players" and room.has("players") and data["players"] is Dictionary:
					for uid in data["players"]:
						var cur: Dictionary = room["players"].get(uid, {})
						for kk in data["players"][uid]:
							cur[kk] = data["players"][uid][kk]
						room["players"][uid] = cur
				else:
					room[k] = data[k]
			_sim_rooms[cid] = room
		else:
			_sim_rooms[cid] = data.duplicate(true)
		_sim_touch(cid)
		return
	Firebase.firestore.set_document(_COLL, cid, data, merge)
	await Firebase.firestore.write_task_completed

# Merge-write a single player's record (only touches players.<uid>).
func _write_player(cid: String, uid: String, rec: Dictionary) -> void:
	await _write_room(cid, {"players": {uid: rec}}, true)

func _delete_room(cid: String) -> void:
	if _is_editor:
		_sim_rooms.erase(cid)
		if _watching.has(cid):
			emit_signal("room_changed", cid, {})
		return
	Firebase.firestore.delete_document(_COLL, cid)
	await Firebase.firestore.delete_task_completed

# Normalize a raw room (sim dict or REST-decoded) into a guaranteed-key shape so
# screens never have to guard missing/mistyped fields. Returns {} for null.
func _shape_room(raw: Variant, cid: String) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var src: Dictionary = raw
	var players_raw: Variant = src.get("players", {})
	var players: Dictionary = {}
	if players_raw is Dictionary:
		for uid in players_raw:
			var p: Variant = players_raw[uid]
			if not (p is Dictionary):
				continue
			players[uid] = {
				"name": String(p.get("name", "Player")),
				"is_creator": bool(p.get("is_creator", false)),
				"joined_at": int(p.get("joined_at", 0)),
				"state": String(p.get("state", "lobby")),
				"score": int(p.get("score", 0)),
				"finished_at": int(p.get("finished_at", 0)),
			}
	return {
		"id": cid,
		"title": String(src.get("title", "Contest")),
		"creator_uid": String(src.get("creator_uid", "")),
		"creator_name": String(src.get("creator_name", "")),
		"difficulty": String(src.get("difficulty", "easy")),
		"is_public": bool(src.get("is_public", false)),
		"status": String(src.get("status", "lobby")),
		"seed": int(src.get("seed", 0)),
		"member_count": int(src.get("member_count", players.size())),
		"created_at": int(src.get("created_at", 0)),
		"started_at": int(src.get("started_at", 0)),
		"finished_at": int(src.get("finished_at", 0)),
		"players": players,
	}

# =====================================================================
#  REST (public reads)  — copied pattern from LeaderboardManager
# =====================================================================

func _http_get(url: String) -> Array:
	var http := HTTPRequest.new()
	http.timeout = 6.0
	add_child(http)
	if http.request(url) != OK:
		http.queue_free()
		return [0, 0, [], PackedByteArray()]
	var r: Array = await http.request_completed
	http.queue_free()
	return r

func _http_post(url: String, body: Dictionary) -> Array:
	var http := HTTPRequest.new()
	http.timeout = 6.0
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body)) != OK:
		http.queue_free()
		return [0, 0, [], PackedByteArray()]
	var r: Array = await http.request_completed
	http.queue_free()
	return r

func _rest_get(collection: String, doc_id: String) -> Dictionary:
	var r := await _http_get(_FB_BASE + "/" + collection + "/" + doc_id)
	if r[1] != 200:
		return {"exists": false}
	var j := JSON.new()
	j.parse((r[3] as PackedByteArray).get_string_from_utf8())
	if not j.data is Dictionary:
		return {"exists": false}
	return {"exists": true, "data": _fields(j.data.get("fields", {}))}

# runQuery on contests: a single ranged query for public lobby rooms. Filters on
# `lobby_key >= pivot` and orders by it (one auto-indexed field, no composite index
# — private/started rooms carry no in-range key, so they're excluded). Returns
# Array of decoded room dicts (id folded in from the doc name is already a field).
func _rest_query_lobby(pivot: float) -> Array:
	var body := {"structuredQuery": {
		"from": [{"collectionId": _COLL}],
		"where": {"fieldFilter": {
			"field": {"fieldPath": "lobby_key"},
			"op": "GREATER_THAN_OR_EQUAL",
			"value": {"doubleValue": pivot},
		}},
		"orderBy": [{"field": {"fieldPath": "lobby_key"}, "direction": "ASCENDING"}],
		"limit": LOBBY_FETCH,
	}}
	for attempt in 3:
		var r := await _http_post(_FB_BASE + ":runQuery", body)
		if r[1] == 200:
			var j := JSON.new()
			j.parse((r[3] as PackedByteArray).get_string_from_utf8())
			var out: Array = []
			if j.data is Array:
				for env in j.data:
					if not (env is Dictionary):
						continue
					var doc: Variant = env.get("document", null)
					if not (doc is Dictionary):
						continue
					out.append(_fields(doc.get("fields", {})))
			return out
		if attempt < 2:
			await get_tree().create_timer(1.0).timeout
	return []

func _val(v: Variant) -> Variant:
	if not v is Dictionary: return null
	if v.has("stringValue"):    return v["stringValue"]
	if v.has("integerValue"):   return int(v["integerValue"])
	if v.has("doubleValue"):    return float(v["doubleValue"])
	if v.has("booleanValue"):   return bool(v["booleanValue"])
	if v.has("timestampValue"): return v["timestampValue"]
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
		var v = _val(f[k])
		if v != null:
			out[k] = v
	return out
