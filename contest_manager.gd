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
#       created_at, started_at, finished_at, expires_unix (expiry),
#       start_deadline,             # public only: created_at + START_WINDOW
#       lobby_shard,                # public only: which lobby/s{N} lists this room
#       lobby_key,                  # legacy browse key (see PUBLIC LOBBY below)
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
# --- PUBLIC LOBBY (the browsable list of open rooms) ------------------------
# The same single-document constraint applies to the LIST of public rooms: a
# client can't listen to "all open rooms", so the list is fanned out into a small
# index that clients CAN listen to — LOBBY_SHARDS documents of LOBBY_SHARD_CAP
# entries each (5 x 20 = LOBBY_MAX, the hard cap on open public rooms):
#
#   lobby/s{N} -> { rooms: { <CID>: { t: title, d: difficulty,
#                                     c: member_count, o: open_at, u: creator_uid } } }
#
# Every viewer listens to all LOBBY_SHARDS docs and merges them client-side (see
# watch_lobby / lobby_rows), so rooms appear, change count and vanish live. Rooms
# are tiny entries, so a whole shard is ~2KB — cheap to push on every change, and
# far cheaper than re-running a 100-doc query per viewer per change.
#
# Liveness is a pure TIME predicate: an entry counts while `now < o + START_WINDOW`.
# Closing a room writes o=0 (a merge can't delete a map key — same reason players
# use "left" tombstones), which makes it dead by that same predicate. So one rule
# covers closed, started AND abandoned rooms, and no client has to be online for a
# dead room to leave the list. Dead keys are swept by the compaction pass in
# _lobby_pick_shard() when a shard actually runs out of slots.
#
# Sharding also spreads writes: Firestore sustains ~1 write/sec on ONE document,
# and joins/leaves/opens/closes across 100 rooms would exceed that on a single doc.
#
# ROLLOUT COMPAT: already-released clients browse by a ranged query on `lobby_key`
# (a uniform random [0,1) sort key, dropped to -1.0 on start). We keep WRITING that
# field so those builds keep working; nothing here reads it.
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

# Live snapshot of the public lobby: the merged, still-open rows across every
# index shard (see lobby_rows). Fires while watch_lobby() is active.
signal lobby_changed(rows: Array)

# ---- caps / limits ----
const MAX_MEMBERS := 45
# Public lobby index: LOBBY_SHARDS docs x LOBBY_SHARD_CAP entries. The cap is real
# — firestore.rules rejects a shard write that would exceed LOBBY_SHARD_CAP.
const LOBBY_SHARDS := 5
const LOBBY_SHARD_CAP := 20
const LOBBY_MAX := LOBBY_SHARDS * LOBBY_SHARD_CAP
# How long a public room stays open for its host to press Start. At the deadline
# the room auto-starts (2+ players) or closes — see contest_detail_screen.
const START_WINDOW := 5 * 60
# Room titles are player-authored; displayed big and clamped everywhere
# (mirrors ArenaUI.TITLE_MAX + titleOk() in firestore.rules).
const TITLE_MAX := 15

const DIFFS: Array[String] = ["easy", "moderate", "hard"]

# Expiry horizon stamped on every room write. A room abandoned without its
# member_count ever reaching 0 is reachable by no other cleanup path, so it is
# reaped once this horizon passes — see sweep_expired_rooms(). This was ORIGINALLY
# a Firestore TTL policy, which silently never ran (see _expires_iso).
const TTL_SECS := 3 * 86400

# How many expired rooms one sweep pass reaps. Deletes are a round-trip each, so
# this bounds what a single lobby-open contributes in the background; every
# client that opens the lobby runs a pass, so the backlog drains collectively.
const SWEEP_LIMIT := 10

const ID_LEN := 6
# Crockford base32 minus I,L,O,U — unambiguous when shared verbally / typed.
const ID_ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
const MAX_SCORE := 9999   # mirror scoreOk() in firestore.rules

const _COLL := "contests"
const _LOBBY_COLL := "lobby"
const _FB_BASE := "https://firestore.googleapis.com/v1/projects/simon-6bc39/databases/(default)/documents"

var _is_editor := OS.get_name() != "Android"

# ---- editor sim store (shape mirrors Firestore) ----
var _sim_rooms: Dictionary = {}       # cid -> room dict
var _sim_shards: Dictionary = {}      # shard index -> rooms map (lobby index)

# Rooms this client currently has a live listener attached to (so document_changed
# only re-emits for docs a screen actually asked to watch).
var _watching: Dictionary = {}        # cid -> true

# ---- public lobby live state ----
var _watching_lobby := false
var _shards: Dictionary = {}          # shard index -> rooms map (last snapshot)
var _lobby_emit_queued := false       # coalesces a burst of shard snapshots into one emit

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

# Legacy expiry stamp. Kept ONLY so already-released builds keep seeing the shape
# they validate against — nothing reads it. It was meant to drive a Firestore TTL
# policy, but TTL only acts on fields of type Timestamp and the Android plugin
# can't produce one (a GDScript String marshals to a Java String), so this always
# landed as a string and TTL never deleted a single room. Expiry now keys on
# `expires_unix` below.
func _expires_iso(base_now: int) -> String:
	return Time.get_datetime_string_from_unix_time(base_now + TTL_SECS) + "Z"

# The real expiry stamp: plain int, UTC seconds. firestore.rules compares it
# against request.time, so once it passes ANY signed-in client may delete the
# room — which is what sweep_expired_rooms() does. Every room write refreshes it,
# so a live room keeps pushing its horizon out and only an abandoned one ages.
func _expires_unix(base_now: int) -> int:
	return base_now + TTL_SECS

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

# Returns {ok, id} or {ok:false, error} with error in {auth, bad_args, lobby_full,
# id_collision}.
# `is_public` rooms are listed in the browse-lobby and must be started within
# START_WINDOW; private ones carry no deadline and can only be joined with the
# shared ID.
func create_contest(difficulty: String, title: String = "",
		is_public: bool = true) -> Dictionary:
	if _uid().is_empty() or not FirebaseManager.has_display_name():
		return {"ok": false, "error": "auth"}
	if not DIFFS.has(difficulty):
		return {"ok": false, "error": "bad_args"}

	# Claim a lobby slot BEFORE creating anything, so a full lobby can't leave an
	# orphan room behind.
	var slot: Dictionary = {}
	if is_public:
		slot = await _lobby_pick_shard()
		if not bool(slot.get("ok", false)):
			return {"ok": false, "error": "lobby_full"}

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
			# Private rooms have no start deadline (0); public ones must start within
			# START_WINDOW of opening.
			"start_deadline": (now + START_WINDOW) if is_public else 0,
			"lobby_shard": int(slot.get("shard", -1)) if is_public else -1,
			"expires_at": _expires_iso(now),
			"expires_unix": _expires_unix(now),
			"players": {_uid(): _new_player(true, now)},
		}
		# Legacy browse key, kept only so already-released builds still see this room
		# in their (ranged-query) lobby. Nothing in this version reads it.
		if is_public:
			room["lobby_key"] = randf()
		await _write_room(cid, room, false)
		if is_public:
			await _lobby_claim(slot, cid, room)
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
	var count := _count_active(players)
	await _write_room(cid, {
		"member_count": count,
		"expires_at": _expires_iso(now),
		"expires_unix": _expires_unix(now),
	}, true)
	await _lobby_bump(room, cid, count)
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
		await _lobby_close(room, cid)
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
		"expires_unix": _expires_unix(_now()),
	}, true)
	if remaining <= 0:
		await _lobby_close(room, cid)
		await _delete_room(cid)
	else:
		await _lobby_bump(room, cid, remaining)

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
	await _lobby_close(room, cid)
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
	var count := _count_active(players)
	await _write_room(cid, {"member_count": count}, true)
	await _lobby_bump(room, cid, count)
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
		# Legacy key: drop below the [0,1) range so older builds stop listing it.
		"lobby_key": -1.0,
		"expires_at": _expires_iso(now),
		"expires_unix": _expires_unix(now),
	}, true)
	# A started race is no longer joinable — take it out of the public lobby.
	await _lobby_close(room, cid)
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
			"status": "finished", "finished_at": now,
			"expires_at": _expires_iso(now), "expires_unix": _expires_unix(now),
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
			"status": "finished", "finished_at": now,
			"expires_at": _expires_iso(now), "expires_unix": _expires_unix(now),
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
		"status": "finished", "finished_at": now,
		"expires_at": _expires_iso(now), "expires_unix": _expires_unix(now),
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
	if document_path.begins_with(_LOBBY_COLL + "/"):
		_apply_shard(document_path, data)
		return
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
#  PUBLIC LOBBY  (live index of open rooms — see the header notes)
# =====================================================================

# Go live on the public lobby. Emits lobby_changed with the current rows as soon
# as the shard snapshots land (Firestore fires a listener immediately with the
# current document, so this needs no separate fetch), and again on every change.
func watch_lobby() -> void:
	if _watching_lobby:
		_queue_lobby_emit()   # a re-entering screen still wants an immediate paint
		return
	_watching_lobby = true
	if _is_editor:
		_queue_lobby_emit()
		return
	for n in LOBBY_SHARDS:
		Firebase.firestore.listen_to_document(_shard_path(n))
	# Opening the lobby is the natural moment to take out the trash: the player is
	# about to sit and watch a list, so a few background deletes cost them nothing.
	# Not awaited — the lobby must paint the instant the shards land.
	sweep_expired_rooms()

# Deletes rooms whose `expires_unix` has passed. Any signed-in client may do this
# (firestore.rules isExpired), which is what makes it work at all: an orphaned
# room's own members are gone by definition, and the previous delete paths all
# required either the creator or a member_count already lowered to 0.
#
# Rooms written by builds that predate `expires_unix` carry no such field, and a
# Firestore inequality filter skips docs missing the field — so they are NOT
# swept here. That's a fixed, non-growing set cleared by a one-off admin purge.
func sweep_expired_rooms() -> void:
	if _is_editor or _uid().is_empty():
		return
	var res := await _rest_run_query({
		"from": [{"collectionId": _COLL}],
		"where": {"fieldFilter": {
			"field": {"fieldPath": "expires_unix"},
			"op": "LESS_THAN",
			"value": {"integerValue": str(_now())},
		}},
		# Oldest first, so concurrent sweepers converge on the same head of the
		# backlog instead of each nibbling a different slice of it.
		"orderBy": [{"field": {"fieldPath": "expires_unix"}, "direction": "ASCENDING"}],
		"limit": SWEEP_LIMIT,
	})
	for item: Dictionary in res:
		var cid := String(item.get("id", ""))
		# Never delete the room this client is sitting in, whatever its stamp says.
		if cid.is_empty() or cid == current_room_id:
			continue
		# A racing sweeper may have taken it already; that just fails the rule
		# check and we move on.
		await _delete_room(cid)

func unwatch_lobby() -> void:
	if not _watching_lobby:
		return
	_watching_lobby = false
	if _is_editor:
		return
	for n in LOBBY_SHARDS:
		Firebase.firestore.stop_listening_to_document(_shard_path(n))

# The merged public lobby: every still-open room across all shards, freshest
# first (a new room has the most time left, and rows age off the END of the list
# instead of churning the top). Rows are display-ready:
#   {id, title, difficulty, member_count, open_at, deadline, is_creator}
func lobby_rows() -> Array:
	var now := _now()
	var src: Dictionary = _sim_shards if _is_editor else _shards
	var out: Array = []
	for idx in src:
		var rooms: Variant = src[idx]
		if not (rooms is Dictionary):
			continue
		for cid in (rooms as Dictionary):
			var e: Variant = (rooms as Dictionary)[cid]
			if not (e is Dictionary):
				continue
			var open_at := int((e as Dictionary).get("o", 0))
			# One predicate for closed (o=0), started (o=0) and abandoned rooms.
			if open_at <= 0 or now >= open_at + START_WINDOW:
				continue
			out.append({
				"id": String(cid),
				"title": String((e as Dictionary).get("t", "Contest")),
				"difficulty": String((e as Dictionary).get("d", "easy")),
				"member_count": int((e as Dictionary).get("c", 1)),
				"open_at": open_at,
				"deadline": open_at + START_WINDOW,
				"is_creator": String((e as Dictionary).get("u", "")) == _uid(),
			})
	out.sort_custom(func(a, b):
		if int(a["open_at"]) != int(b["open_at"]):
			return int(a["open_at"]) > int(b["open_at"])
		return String(a["id"]) < String(b["id"])   # stable order for same-second opens
	)
	return out

func _shard_path(n: int) -> String:
	return "%s/s%d" % [_LOBBY_COLL, n]

# Android live-listener callback for a lobby shard.
func _apply_shard(document_path: String, data: Dictionary) -> void:
	if not _watching_lobby:
		return
	var suffix := document_path.substr((_LOBBY_COLL + "/").length())
	if not suffix.begins_with("s"):
		return
	var idx := int(suffix.substr(1))
	if idx < 0 or idx >= LOBBY_SHARDS:
		return
	var raw: Dictionary = data
	if data.has("fields"):
		raw = _fields(data["fields"])
	var rooms: Variant = raw.get("rooms", {})
	_shards[idx] = rooms if rooms is Dictionary else {}
	_queue_lobby_emit()

# All LOBBY_SHARDS snapshots land back-to-back when a screen goes live; coalesce
# them (and any write-triggered re-emit) into one repaint per frame.
func _queue_lobby_emit() -> void:
	if _lobby_emit_queued:
		return
	_lobby_emit_queued = true
	call_deferred("_emit_lobby")

func _emit_lobby() -> void:
	_lobby_emit_queued = false
	if _watching_lobby:
		emit_signal("lobby_changed", lobby_rows())

# ---- index writes ----

# The index row for a room. Kept to single-letter keys: this map is pushed to
# every lobby viewer on every change.
func _lobby_entry(room: Dictionary) -> Dictionary:
	return {
		"t": String(room.get("title", "Contest")),
		"d": String(room.get("difficulty", "easy")),
		"c": int(room.get("member_count", 1)),
		"o": int(room.get("created_at", _now())),
		"u": String(room.get("creator_uid", "")),
	}

# Writes a room's entry into the slot claimed by _lobby_pick_shard(). When that
# slot needed compaction, the shard is rewritten wholesale (live entries + ours)
# — the only non-merge write in here, and the only thing that reclaims dead keys.
# Two clients compacting the same shard in the same instant can drop one of their
# entries (last write wins): that room simply isn't LISTED — it still exists, its
# ID still works, and its host can reopen. Only reachable on a shard that is both
# full and stale, so it stays rare by construction.
func _lobby_claim(slot: Dictionary, cid: String, room: Dictionary) -> void:
	var shard := int(slot.get("shard", -1))
	if shard < 0:
		return
	if bool(slot.get("compact", false)):
		var live: Dictionary = (slot.get("live", {}) as Dictionary).duplicate(true)
		live[cid] = _lobby_entry(room)
		await _lobby_write(shard, {"rooms": live}, false)
	else:
		await _lobby_write(shard, {"rooms": {cid: _lobby_entry(room)}}, true)

# Republishes a listed room's player count. No-op for private rooms and for rooms
# that have already left the lobby.
func _lobby_bump(room: Dictionary, cid: String, count: int) -> void:
	if not bool(room.get("is_public", false)) or String(room.get("status", "")) != "lobby":
		return
	var shard := int(room.get("lobby_shard", -1))
	if shard < 0 or shard >= LOBBY_SHARDS:
		return
	await _lobby_write(shard, {"rooms": {cid: {"c": count}}}, true)

# Takes a room out of the public lobby (started, cancelled or emptied). o=0 makes
# the entry fail the liveness predicate everywhere; the key itself is reclaimed by
# the next compaction.
func _lobby_close(room: Dictionary, cid: String) -> void:
	if not bool(room.get("is_public", false)):
		return
	var shard := int(room.get("lobby_shard", -1))
	if shard < 0 or shard >= LOBBY_SHARDS:
		return
	await _lobby_write(shard, {"rooms": {cid: {"o": 0}}}, true)

func _lobby_write(shard: int, data: Dictionary, merge: bool) -> void:
	if _is_editor:
		var rooms: Dictionary = data.get("rooms", {})
		if merge:
			var cur: Dictionary = _sim_shards.get(shard, {})
			for cid in rooms:
				var e: Dictionary = cur.get(cid, {})
				for k in (rooms[cid] as Dictionary):
					e[k] = rooms[cid][k]
				cur[cid] = e
			_sim_shards[shard] = cur
		else:
			_sim_shards[shard] = rooms.duplicate(true)
		_queue_lobby_emit()
		return
	Firebase.firestore.set_document(_LOBBY_COLL, "s%d" % shard, data, merge)
	await Firebase.firestore.write_task_completed

# Claims a slot for a new public room: the shard with the most free space.
# Returns {ok:true, shard, compact, live} or {ok:false} when all LOBBY_MAX slots
# are held by live rooms. `compact` means the shard is at its key cap with dead
# entries in it, so the caller must rewrite it rather than merge into it.
func _lobby_pick_shard() -> Dictionary:
	var shards := await _lobby_read_all()
	var now := _now()
	var best := -1
	var best_live: Dictionary = {}
	var best_compact := false
	for n in LOBBY_SHARDS:
		var rooms: Dictionary = shards.get(n, {})
		var live: Dictionary = {}
		for cid in rooms:
			var e: Variant = rooms[cid]
			if not (e is Dictionary):
				continue
			var open_at := int((e as Dictionary).get("o", 0))
			if open_at > 0 and now < open_at + START_WINDOW:
				live[cid] = e
		if live.size() >= LOBBY_SHARD_CAP:
			continue                      # genuinely full of open rooms
		if best >= 0 and live.size() >= best_live.size():
			continue
		best = n
		best_live = live
		# A merge write can only add a key; if the raw map is already at the cap,
		# rules would reject it — so the dead keys have to be swept first.
		best_compact = rooms.size() >= LOBBY_SHARD_CAP
	if best < 0:
		return {"ok": false}
	return {"ok": true, "shard": best, "compact": best_compact, "live": best_live}

# Every shard's rooms map, keyed by shard index. Uses the live snapshots when the
# lobby is already being watched (free); otherwise one REST list of the whole
# (5-document) collection.
func _lobby_read_all() -> Dictionary:
	var out: Dictionary = {}
	for n in LOBBY_SHARDS:
		out[n] = {}
	if _is_editor:
		for n in LOBBY_SHARDS:
			out[n] = (_sim_shards.get(n, {}) as Dictionary).duplicate(true)
		return out
	if _watching_lobby and not _shards.is_empty():
		for n in LOBBY_SHARDS:
			out[n] = _shards.get(n, {})
		return out
	var r := await _http_get(_FB_BASE + "/" + _LOBBY_COLL)
	if r[1] != 200:
		return out                        # treat an unreadable index as empty
	var j := JSON.new()
	j.parse((r[3] as PackedByteArray).get_string_from_utf8())
	if not (j.data is Dictionary):
		return out
	for doc in (j.data as Dictionary).get("documents", []):
		if not (doc is Dictionary):
			continue
		var name := String((doc as Dictionary).get("name", ""))
		var sid := name.substr(name.rfind("/") + 1)
		if not sid.begins_with("s"):
			continue
		var idx := int(sid.substr(1))
		if idx < 0 or idx >= LOBBY_SHARDS:
			continue
		var f := _fields((doc as Dictionary).get("fields", {}))
		var rooms: Variant = f.get("rooms", {})
		out[idx] = rooms if rooms is Dictionary else {}
	return out

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
		# Public rooms only: when the host must have started by, and which lobby
		# shard lists the room (-1 / 0 = not listed, i.e. private or pre-deadline build).
		"start_deadline": int(src.get("start_deadline", 0)),
		"lobby_shard": int(src.get("lobby_shard", -1)),
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

func _rest_get(collection: String, doc_id: String) -> Dictionary:
	var r := await _http_get(_FB_BASE + "/" + collection + "/" + doc_id)
	if r[1] != 200:
		return {"exists": false}
	var j := JSON.new()
	j.parse((r[3] as PackedByteArray).get_string_from_utf8())
	if not j.data is Dictionary:
		return {"exists": false}
	return {"exists": true, "data": _fields(j.data.get("fields", {}))}

# Runs a Firestore structured query and returns [{id, data}, ...] — empty on any
# failure, since the only caller is a best-effort sweep. Reads need no auth
# header (contests is `allow read: if true`); the DELETES that follow go through
# the plugin so rules see request.auth.
func _rest_run_query(query: Dictionary) -> Array:
	var http := HTTPRequest.new()
	http.timeout = 6.0
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var body := JSON.stringify({"structuredQuery": query})
	if http.request(_FB_BASE + ":runQuery", headers, HTTPClient.METHOD_POST, body) != OK:
		http.queue_free()
		return []
	var r: Array = await http.request_completed
	http.queue_free()
	if r[1] != 200:
		return []
	var j := JSON.new()
	j.parse((r[3] as PackedByteArray).get_string_from_utf8())
	if not (j.data is Array):
		return []
	var out: Array = []
	for env in j.data:
		# A zero-match query answers with a single metadata-only envelope that has
		# no `document` key — skip anything that isn't a real result.
		if not (env is Dictionary):
			continue
		var doc: Variant = (env as Dictionary).get("document", null)
		if not (doc is Dictionary):
			continue
		var parts: PackedStringArray = String((doc as Dictionary).get("name", "")).split("/")
		out.append({"id": parts[-1], "data": _fields((doc as Dictionary).get("fields", {}))})
	return out

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
