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
# merge can't delete a map key; the UI filters tombstones out.
#
# --- WHY A CLOSED ROOM IS A WRITE, NEVER A DELETE ---------------------------
# The Android plugin's document listener only emits when the snapshot EXISTS
# (Firestore.kt: `if (snapshot != null && snapshot.exists())`) — so a DELETED
# document is never delivered to a single watcher. Every "the room ended" signal
# therefore has to be a WRITE that leaves the doc in place; deleting the room while
# people are still sitting in it froze them on a live-looking lobby forever (the
# host's Cancel Room did exactly that).
#
# So a room that ends while others may still be watching it is CLOSED, not deleted:
# `cancelled: true` plus status "finished" (see _close_room). Status is deliberately
# kept inside the released ['lobby','playing','finished'] set so already-shipped
# clients — which route any UNKNOWN status straight into the game — degrade to the
# final-standings face instead of launching a phantom match. The doc itself is reaped
# later by the expiry sweep, when nobody is watching any more.
#
# Deletes still happen where no watcher can be left behind (last member out, expiry
# sweep) — and _watchdog covers even those, because an already-released host still
# deletes the room on cancel. See WATCHDOG_SECS.
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
# dead room to leave the list. Dead keys are reclaimed two ways: eagerly by
# compact_lobby_shards() every time the lobby opens (rewrites any shard carrying
# dead keys down to its live entries), and as a fallback by the compaction pass in
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
# Straggler timeout for the RACE phase. A room only flips to "finished" once every
# active player is "done" — so one player who joined and never raced, or force-closed
# mid-game, would otherwise freeze the room (and everyone waiting on the results
# board) until the TTL sweep. Instead the room force-finalizes once nobody NEW has
# finished for this long (the clock resets on every finish — see play_grace_deadline),
# so a steady stream of finishers, or a strong player still on a long run while others
# trickle in, keeps it open; only a genuine gap (a no-show / force-closed player)
# trips it. Any participant's client does the finalize; a no-show ranks at its score,
# 0. See finalize_overdue() and _render_results in the detail screen.
const FINISH_GRACE := 3 * 60
# Room titles are player-authored; displayed big and clamped everywhere
# (mirrors ArenaUI.TITLE_MAX + titleOk() in firestore.rules).
const TITLE_MAX := 15

const DIFFS: Array[String] = ["easy", "moderate", "hard"]

# Expiry horizon stamped on every room write. A room abandoned without its
# member_count ever reaching 0 is reachable by no other cleanup path, so it is
# reaped once this horizon passes — see sweep_expired_rooms(). This was ORIGINALLY
# a Firestore TTL policy, which silently never ran (see _expires_iso).
#
# Because EVERY room write refreshes this, the horizon is really "reap N seconds
# after the last write". At 20 min that catches an abandoned room quickly — but it
# would also catch a live room that simply goes quiet (a private lobby waiting for a
# friend; a room mid-game, whose only writes are at launch and finish). So any screen
# sitting on a room heartbeats it under this window via touch_room() (see
# KEEPALIVE in contest_detail_screen): a room stays alive exactly as long as someone
# has it open, and dies within TTL_SECS once everyone closes it.
const TTL_SECS := 20 * 60

# Expiry horizon stamped when a race STARTS, instead of TTL_SECS. Nobody heartbeats a
# room while the race is on — every player is in the game, not on the room screen, and
# the keepalive is host-only — so a race longer than TTL_SECS with no finishers yet used
# to expire out from under everyone still playing, and the sweep would delete it
# mid-run. One write at start (and one per finish) covers the whole race window without
# adding a single heartbeat. Generous on purpose: a strong player on Easy can run a very
# long time, and an over-long room costs nothing but a doc waiting to be swept.
const RACE_TTL_SECS := 60 * 60

# How many expired rooms one sweep pass reaps. Deletes are a round-trip each, so
# this bounds what a single lobby-open contributes in the background; every
# client that opens the lobby runs a pass, so the backlog drains collectively.
const SWEEP_LIMIT := 10

# How long a CLOSED room (host cancelled — see _close_room) lingers before it becomes
# sweepable. It only has to outlive the push that tells everyone it closed; a couple of
# minutes also means a player who opens the room from a stale hub card right afterwards
# still reads "the host closed this room" instead of the blanker "no longer exists".
const CLOSED_LINGER := 2 * 60

# --- watchdog (the backstop for invisible deletes) --------------------------
# The plugin never reports a DELETED document (see the header note), so a watched room
# that disappears — reaped by the expiry sweep, emptied by the last member out, or
# cancelled by an ALREADY-RELEASED host, which still deletes the doc — would leave this
# client frozen on a stale screen forever. So while a room is watched and still live, we
# confirm it exists over REST whenever no push has landed for WATCHDOG_SECS, and emit the
# "gone" state ourselves. Costs one read per idle window per open room screen, and
# nothing at all while pushes are flowing (any push resets the clock).
const WATCHDOG_SECS := 45
const WATCHDOG_TICK := 15

const ID_LEN := 6
# Digits only — the shareable room code is 6 numbers, no letters.
const ID_ALPHABET := "0123456789"
const MAX_SCORE := 9999   # mirror scoreOk() in firestore.rules

const _COLL := "contests"
const _LOBBY_COLL := "lobby"
# Stage-2 materialized read surfaces, written ONLY by the syncContest Cloud Function
# (see functions/index.js) and read-only to clients (firestore.rules). Clients WATCH
# contest_state/{cid} instead of the raw room — so a burst of joins/scores no longer
# wakes every member on every write — and READ the single lobby_index/open doc on
# Refresh instead of live-watching the 5 lobby shards.
const _STATE_COLL := "contest_state"
const _LOBBY_INDEX_PATH := "lobby_index/open"
# The per-user doc (owned by CoinsManager). We persist `current_room` here so the
# "one room at a time" rule survives an app restart / device change.
const _COLL_USERS := "users"
const _FB_BASE := "https://firestore.googleapis.com/v1/projects/simon-6bc39/databases/(default)/documents"

var _is_editor := OS.get_name() != "Android"

# ---- editor sim store (shape mirrors Firestore) ----
var _sim_rooms: Dictionary = {}       # cid -> room dict
var _sim_shards: Dictionary = {}      # shard index -> rooms map (lobby index)

# Rooms this client currently has a live listener attached to (so document_changed
# only re-emits for docs a screen actually asked to watch).
var _watching: Dictionary = {}        # cid -> true
# Watchdog bookkeeping per watched room: {t: unix of the last emit, st: the status we
# last emitted, gone: we've already reported it missing}. See WATCHDOG_SECS.
var _watch_seen: Dictionary = {}      # cid -> {t:int, st:String, gone:bool}
var _watchdog: Timer
var _watchdog_busy := false           # one presence read in flight at a time

# ---- public lobby live state ----
var _watching_lobby := false
var _shards: Dictionary = {}          # shard index -> rooms map (last snapshot)
var _lobby_emit_queued := false       # coalesces a burst of shard snapshots into one emit

# The room this client is currently participating in (set on create/join, cleared
# on leave). Lets a screen re-enter and guards accidental double-joins.
var current_room_id: String = ""
# Display cache for that room, so the Arena hub can paint the "return to your room"
# card INSTANTLY off a synchronous read (no CREATE/JOIN flash) instead of waiting on
# active_room()'s validating network read. Persisted alongside current_room and
# restored at startup; kept coherent by active_room() when it validates.
var current_room_title: String = ""
var current_room_is_host: bool = false

# Contest ids this client has already finished its single race in (this session).
# The room is single-attempt: once we've submitted our result we must NEVER route
# back into the game for that room. The detail screen is rebuilt fresh on every
# navigation (so a per-screen guard resets) and its routing decision reads the
# player's "done" state from a room fetch — but Firestore REST reads are eventually
# consistent, so the fetch right after finishing can still report us as not-done and
# re-launch the match, exiting straight into a new game in an infinite loop. This
# authoritative local record closes that race: has_played(cid) stays true regardless
# of read staleness. Keyed by cid; cleared on sign-out.
var _played_contests: Dictionary = {}

func _ready() -> void:
	if not _is_editor:
		Firebase.firestore.document_changed.connect(_on_document_changed)
	# Restore the persisted room pointer off CoinsManager's single authenticated read
	# of /users/{uid} (same piggy-back the badges use), so a signed-in player who
	# force-quit is still recognised as being in their room. Guarded on both orderings:
	# connect for the read that's still to land, and sync now if it already has.
	CoinsManager.loaded.connect(_on_user_loaded)
	FirebaseManager.signed_out.connect(_clear_room_cache)
	if CoinsManager.raw_user_doc.size() > 0:
		_on_user_loaded()

func _on_user_loaded() -> void:
	current_room_id = String(CoinsManager.raw_user_doc.get("current_room", ""))
	current_room_title = String(CoinsManager.raw_user_doc.get("current_room_title", ""))
	current_room_is_host = bool(CoinsManager.raw_user_doc.get("current_room_host", false))

func _clear_room_cache() -> void:
	current_room_id = ""
	current_room_title = ""
	current_room_is_host = false
	_played_contests.clear()

# True once this client has submitted its single race result for `cid` (see
# _played_contests). The detail screen consults this so a stale post-finish room
# read can't re-launch the match.
func has_played(cid: String) -> bool:
	return _played_contests.has(cid)

# Synchronous view of the persisted room pointer, for painting the hub before (or
# without) a network read. has_cached_room() may be optimistic — active_room() is the
# validating source of truth and will self-heal a stale pointer.
func has_cached_room() -> bool: return not current_room_id.is_empty()
func cached_room_id() -> String: return current_room_id
func cached_room_title() -> String: return current_room_title
func cached_room_is_host() -> bool: return current_room_is_host

func _uid() -> String:  return FirebaseManager.uid
func _name() -> String:
	var n := FirebaseManager.display_name
	return n if not n.is_empty() else "Player"

func _now() -> int: return int(Time.get_unix_time_from_system())

# The live room this client is still seated in (as host OR guest), shaped, or {} if
# none. This is what enforces "one room at a time": create_contest and join_contest
# refuse while it's non-empty, and the Arena hub turns its CREATE card into a
# "return to your room" card off it. A player can't host — or even sit in — two
# rooms at once.
#
# `current_room_id` is set on create/join and cleared on leave, and is persisted to
# /users/{uid}.current_room (see _set_current_room). This also self-heals a stale
# pointer: one to a room that was deleted, or one we were kicked/left from elsewhere,
# is cleared (and the clear persisted) and treated as "no active room". A finished
# race no longer holds a slot, so it doesn't count either.
func active_room() -> Dictionary:
	if current_room_id.is_empty():
		return {}
	var room := await _load_room(current_room_id)
	if room.is_empty():
		await _set_current_room("")                # pointer to a deleted room
		return {}
	var mine: Dictionary = (room.get("players", {}) as Dictionary).get(_uid(), {})
	if mine.is_empty() or String(mine.get("state", "")) == "left":
		await _set_current_room("")                # we're no longer a member
		return {}
	if String(room.get("status", "")) == "finished":
		await _set_current_room("")                # a finished race frees the slot
		return {}
	# Keep the instant-display cache coherent with the live room (e.g. a pointer
	# restored from an older build that persisted no title/host). In-memory only — the
	# next create/join persists it; no need to spend a write on a read path.
	current_room_title = String(room.get("title", ""))
	current_room_is_host = String(room.get("creator_uid", "")) == _uid()
	return room

# Keep the instant-display room cache honest against a room state we've just observed
# (a live-listener push or a one-shot load). The Arena hub paints its "return to your
# room" card synchronously off current_room_id BEFORE it can validate over the network;
# if the room we point at has gone terminal for us — finished, deleted, or we were
# kicked / left — clearing the pointer the instant we see that means the hub never
# paints the stale card, so there's no card→CREATE/JOIN flash on the way back from a
# race that just ended (or a room the host cancelled). This is the in-session partner
# to active_room()'s self-heal and the loading-screen validation: whichever observes
# the terminal state first clears the pointer. Fire-and-forget — _set_current_room
# clears the in-memory pointer SYNCHRONOUSLY (all a same-frame hub paint reads) and
# persists the empty pointer in the background. The `!= current_room_id` guard makes
# it idempotent: once cleared, repeat pushes for the same room no longer match.
func _reconcile_room_cache(cid: String, room: Dictionary) -> void:
	if cid.is_empty() or cid != current_room_id:
		return
	if _room_terminal_for_me(room):
		_set_current_room("")

# A room no longer holds a seat for us: it's gone/deleted ({}), the race is finished,
# or our own player row is missing or tombstoned (kicked, or left from elsewhere). A
# room that's still in the lobby or playing with us an active member is NOT terminal —
# we can still return to it, so the hub's card stays.
func _room_terminal_for_me(room: Dictionary) -> bool:
	if room.is_empty():
		return true
	if String(room.get("status", "")) == "finished":
		return true
	var mine: Dictionary = (room.get("players", {}) as Dictionary).get(_uid(), {})
	return mine.is_empty() or String(mine.get("state", "")) == "left"

# Reconcile the cache off the freshest room state, then fan the change out to watchers.
# Every room_changed emission goes through here so the pointer self-heals wherever the
# terminal transition is first seen (finish, host-cancel, kick, delete).
func _emit_room(cid: String, room: Dictionary) -> void:
	_reconcile_room_cache(cid, room)
	if _watching.has(cid):
		_watch_seen[cid] = {
			"t": _now(),
			"st": String(room.get("status", "")),
			"gone": room.is_empty(),
		}
	emit_signal("room_changed", cid, room)

# Sets the room pointer AND persists it to /users/{uid}.current_room (merge write, so
# it never clobbers the wallet/cosmetics on that same doc). This is what makes the
# "one room at a time" rule survive a restart: on next launch _on_user_loaded reads
# it back off CoinsManager's authenticated read. No-op (in-memory only) in the editor
# sim and when signed out.
func _set_current_room(cid: String, title: String = "", is_host: bool = false) -> void:
	current_room_id = cid
	# The display cache only means anything while we hold a room; clearing the pointer
	# clears it too.
	current_room_title = title if not cid.is_empty() else ""
	current_room_is_host = is_host if not cid.is_empty() else false
	if _is_editor:
		return
	var uid := _uid()
	if uid.is_empty():
		return
	# Keep CoinsManager's cached doc coherent so a same-session reader sees the change.
	CoinsManager.raw_user_doc["current_room"] = cid
	CoinsManager.raw_user_doc["current_room_title"] = current_room_title
	CoinsManager.raw_user_doc["current_room_host"] = current_room_is_host
	Firebase.firestore.set_document(_COLL_USERS, uid, {
		"current_room": cid,
		"current_room_title": current_room_title,
		"current_room_host": current_room_is_host,
	}, true)
	await Firebase.firestore.write_task_completed

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

	# One room at a time: a player already seated in a live room can't open another
	# (this is what stops a host pressing Back in the lobby and spinning up a second
	# room). The Arena hub reflects this as a "return to your room" card, so the
	# player is routed back instead of ever reaching here.
	var busy := await active_room()
	if not busy.is_empty():
		return {"ok": false, "error": "in_room", "id": String(busy.get("id", ""))}

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
		await _set_current_room(cid, String(room["title"]), true)
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

	# One room at a time: block joining a DIFFERENT room while still seated in one.
	# Re-opening the room we're already in is fine and falls through to the no-op
	# success below.
	var busy := await active_room()
	if not busy.is_empty() and String(busy.get("id", "")) != cid:
		return {"ok": false, "error": "in_room", "id": String(busy.get("id", ""))}

	var room := await _load_room(cid)
	if room.is_empty():
		return {"ok": false, "error": "not_found"}
	# A room the host closed sticks around (see _close_room) instead of vanishing, so
	# it's worth telling those two cases apart: "already racing" vs "closed for good".
	if String(room.get("status", "")) == "finished":
		return {"ok": false, "error": "closed"}
	if String(room.get("status", "")) != "lobby":
		return {"ok": false, "error": "ended"}

	var players: Dictionary = room.get("players", {})
	# Already an active member? Treat join as a no-op success so the UI just opens it.
	var mine: Dictionary = players.get(_uid(), {})
	if not mine.is_empty() and String(mine.get("state", "")) != "left":
		await _set_current_room(cid, String(room.get("title", "")),
			String(room.get("creator_uid", "")) == _uid())
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
	# (No _lobby_bump: live lobby counts are given up — browsers refresh the list.)
	await _set_current_room(cid, String(room.get("title", "")),
		String(room.get("creator_uid", "")) == _uid())
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
# Returns true when the leave was actually recorded. A caller that navigates away on a
# FAILED leave would strand the player: their row still holds a seat in a room the hub
# no longer points at (and their unfinished row blocks everyone else's all-done check).
func leave_contest(cid: String) -> bool:
	var room := await _load_room(cid)
	if room.is_empty():
		# Nothing to leave — but a pointer at a room that's gone is exactly the stale
		# pointer active_room() would clear anyway, so drop it.
		if current_room_id == cid:
			await _set_current_room("")
		return true
	var is_creator := String(room.get("creator_uid", "")) == _uid()
	var status := String(room.get("status", ""))

	# Creator abandoning a lobby cancels the room entirely — same terminal write as
	# Cancel Room, so everyone still sitting in the lobby is actually told.
	if is_creator and status == "lobby":
		var closed := await _close_room(cid, room)
		if closed and current_room_id == cid:
			await _set_current_room("")
		return closed

	# Tombstone my own row, then republish the active count.
	if not await _write_player(cid, _uid(), {"state": "left"}):
		return false
	# Only now is the seat really given up; clearing the pointer before this point meant
	# a rejected/failed write left the client believing it had left a room it hadn't.
	if current_room_id == cid:
		await _set_current_room("")
	var players: Dictionary = room.get("players", {})
	if players.has(_uid()):
		players[_uid()]["state"] = "left"
	var remaining := _count_active(players)
	await _write_room(cid, {
		"member_count": remaining,
		"expires_at": _expires_iso(_now()),
		"expires_unix": _expires_unix(_now()),
	}, true)
	# Last one out CLOSES the room rather than deleting it. Deleting needed the
	# "member_count <= 0" delete rule, which any member could reach by simply writing
	# that count — a one-write way to destroy a live 45-player race. With the room
	# closed instead, it leaves the browse list the same way every other ended room
	# does and the server sweep reaps the doc once it expires.
	if remaining <= 0:
		await _close_room(cid, room)
	return true

# Best-effort cleanup on account deletion: leave whatever room we're currently in.
# The single-doc model has no per-uid query, so we can only reach the active room;
# any earlier orphan rows are reaped by Firestore TTL.
func leave_all() -> void:
	if not current_room_id.is_empty():
		await leave_contest(current_room_id)

# Creator closes the whole room (any status). See _close_room: this is a WRITE, not a
# delete, because a delete is invisible to everyone still sitting in the room.
func cancel_room(cid: String) -> Dictionary:
	var room := await _load_room(cid)
	if room.is_empty():
		if current_room_id == cid:
			await _set_current_room("")
		return {"ok": true}
	if String(room.get("creator_uid", "")) != _uid():
		return {"ok": false, "error": "not_creator"}
	# A room that already reached its end is NOT re-closable. Now that closing is a
	# write everyone sees (it used to be a delete nobody saw), writing it over a room
	# that finished on its own would replace a legitimate final podium with "the host
	# closed this room" on every watcher's screen — for a race that genuinely ran to its
	# end. Reachable via a confirm dialog opened on the results board that the host taps
	# through after the race finalized underneath it. Nothing left to close: succeed.
	if String(room.get("status", "")) == "finished":
		if current_room_id == cid:
			await _set_current_room("")
		return {"ok": true}
	if not await _close_room(cid, room):
		return {"ok": false, "error": "write_failed"}
	if current_room_id == cid:
		await _set_current_room("")
	return {"ok": true}

# Ends a room that other people may still be watching. The doc STAYS — a deleted
# document never reaches a listener (see the header note), so the only way to tell the
# room it's over is to leave a state behind that says so:
#
#   cancelled: true    the real signal; screens render "the host closed this room"
#   status: "finished" so ALREADY-RELEASED clients (which know only lobby/playing/
#                      finished, and treat anything else as "playing" — i.e. launch the
#                      match) land on the final-standings face instead
#   member_count: 0    frees the room for the plain empty-room delete rule
#   expires_unix       CLOSED_LINGER out, so the sweep reaps the doc once the push has
#                      long since landed and nobody is watching any more
#
# The lobby entry is closed the same way it always was, so the room stops being listed
# for browsers immediately.
func _close_room(cid: String, room: Dictionary) -> bool:
	var now := _now()
	if not await _write_room(cid, {
		"status": "finished",
		"cancelled": true,
		"member_count": 0,
		"finished_at": now,
		"expires_at": _expires_iso(now),
		"expires_unix": now + CLOSED_LINGER,
	}, true):
		return false
	await _lobby_close(room, cid)
	return true

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
		# The race horizon, not the lobby one: from here until the results are in,
		# nobody is on a screen that heartbeats this room (see RACE_TTL_SECS).
		"expires_unix": now + RACE_TTL_SECS,
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
	# No per-player "playing" write: the room is already globally "playing", and a
	# racer is simply "in the room, not done/left", so this write was redundant. The
	# results board classifies anyone not "done" (and not "left") as still racing.
	# Dropping it removes one write per player AND its listener fan-out as players launch.
	GameState.contest_context = {"id": cid, "difficulty": difficulty, "seed": seed}
	GameState.set_difficulty(difficulty)

# Records this player's finished match (single attempt). `score` = rounds cleared.
# If every active player is now done, flips the room to "finished". Returns the
# (possibly finalized) shaped room.
func submit_result(cid: String, score: int) -> Dictionary:
	if cid.is_empty() or _uid().is_empty():
		return {}
	# Record locally BEFORE the network write: from this point the detail screen must
	# treat us as done even if the room read that follows is a stale (pre-write) copy.
	_played_contests[cid] = true
	var s := clampi(score, 0, MAX_SCORE)
	var now := _now()

	# Read BEFORE writing (this is the same single read the all-done check always
	# needed — just moved ahead of the write, so it costs nothing extra). It buys the
	# membership check: a score merge writes `state:"done"` over our row, so a player
	# the host kicked mid-race would otherwise UN-tombstone themselves and reappear on
	# the board. Reading first is the only point at which we can still see that we're
	# out. A room that's simply gone falls through — there is nothing to write into
	# (rules deny a merge that would re-create it) and we're already recorded locally.
	var room := await _load_room(cid)
	var players: Dictionary = room.get("players", {})
	# Only skip the write when we actually READ a room that says we're out. An empty
	# read is ambiguous — the room is gone, OR the request just failed — and a score is
	# far too expensive to drop on a maybe, so we still write: a merge into a room that
	# really is gone is denied by the rules anyway, which costs nothing.
	var mine: Dictionary = players.get(_uid(), {})
	if not room.is_empty() and not mine.is_empty() \
			and String(mine.get("state", "")) == "left":
		return room                      # kicked / left: our race no longer counts
	# Fold an expiry refresh into the score write, on the RACE horizon: every finish
	# buys the room another window, so stragglers can't be reaped mid-race.
	await _write_room(cid, {
		"players": {_uid(): {
			"name": _name(), "state": "done", "score": s, "finished_at": now,
		}},
		"expires_at": _expires_iso(now), "expires_unix": now + RACE_TTL_SECS,
	}, true)

	if room.is_empty() or String(room.get("status", "")) != "playing":
		return room
	# The roster we read predates our own write, so fold our result in before the
	# all-done check (the same correction the post-write read used to need for REST's
	# eventual consistency — either way this row is authoritative locally).
	if not players.has(_uid()):
		players[_uid()] = _new_player(false, now)
	players[_uid()]["state"] = "done"
	players[_uid()]["score"] = s
	players[_uid()]["finished_at"] = now

	room["players"] = players
	if _all_done(players):
		await _mark_finished(cid, room)
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

# Flip a room we've established is over to "finished" and push the result out to
# watchers ourselves. Emitting matters: the watcher that triggered the finalize is
# sitting on the results board waiting for exactly this transition, and waiting on the
# mirror to echo it back costs a Cloud Function round trip we don't need — and, when
# that echo is late or lost, up to a full watchdog window (see WATCHDOG_SECS). Returns
# whether the room is now finished. `room` is updated in place.
func _mark_finished(cid: String, room: Dictionary) -> bool:
	var now := _now()
	# Never claim a finish we couldn't write — that would podium a race that, for
	# everyone else, is still running.
	if not await _write_room(cid, {
		"status": "finished", "finished_at": now,
		"expires_at": _expires_iso(now), "expires_unix": _expires_unix(now),
	}, true):
		return false
	room["status"] = "finished"
	room["finished_at"] = now
	_emit_room(cid, room)
	return true

# Any participant may finalize once every active player is done (idempotent — a
# stale read on the last finisher, or a client that only observed all-done from the
# results board, still converges the room to "finished").
func finalize_if_done(cid: String) -> void:
	var room := await _load_room(cid)
	if room.is_empty():
		return
	if String(room.get("status", "")) == "finished":
		# It's already over and we're only hearing it now, straight from the room doc.
		# This read is then the freshest news we have — the mirror's "finished" push
		# either never reached us or was overtaken by a stale one — so fan it out
		# instead of dropping it on the floor and leaving the board waiting.
		_emit_room(cid, room)
		return
	if String(room.get("status", "")) != "playing":
		return
	if _all_done(room.get("players", {})):
		await _mark_finished(cid, room)

# The unix second at which a still-"playing" room may be force-finalized despite
# stragglers: FINISH_GRACE after the MOST RECENT finisher (so the clock resets every
# time someone finishes — a strong player still racing while others post scores keeps
# the room open; it only fires on a real gap in finishes). Returns 0 when nobody has
# finished yet — with no one on the results board waiting, we don't rush the racers
# (a fully-abandoned pre-finish room is caught by the TTL sweep instead). The detail
# screen reads this to show the countdown and to trigger finalize_overdue().
func play_grace_deadline(room: Dictionary) -> int:
	var latest := 0
	var players: Dictionary = room.get("players", {})
	for uid in players:
		var p: Dictionary = players[uid]
		if String(p.get("state", "")) != "done":
			continue
		var f := int(p.get("finished_at", 0))
		if f > latest:
			latest = f
	return (latest + FINISH_GRACE) if latest > 0 else 0

# Straggler timeout: once the grace window after the first finisher has elapsed, any
# participant's client may force the room to "finished" with the scores on hand, so a
# no-show / force-closed player can't freeze it for everyone who did finish. Idempotent
# and self-gating — it re-reads the room and only writes when genuinely overdue and
# still "playing", so several viewers firing it at once converge harmlessly.
func finalize_overdue(cid: String) -> void:
	var room := await _load_room(cid)
	if room.is_empty():
		return
	if String(room.get("status", "")) == "finished":
		_emit_room(cid, room)          # already over — see finalize_if_done
		return
	if String(room.get("status", "")) != "playing":
		return
	var deadline := play_grace_deadline(room)
	if deadline <= 0 or _now() < deadline:
		return
	await _mark_finished(cid, room)

# Keepalive: push a live room's expiry horizon out so the 20-minute sweep doesn't
# reap it while someone still has it open (see TTL_SECS). The detail screen calls this
# on a timer for its lobby / playing faces. The CALLER must gate on a room it's
# actively showing (non-empty, not finished) — a merge write recreates a missing doc,
# so we must never heartbeat a room that was just deleted.
func touch_room(cid: String) -> void:
	if cid.is_empty():
		return
	var now := _now()
	await _write_room(cid, {
		"expires_at": _expires_iso(now),
		"expires_unix": _expires_unix(now),
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
	if not await _mark_finished(cid, room):
		return {"ok": false, "error": "write_failed"}
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
	return (await load_room_status(cid)).get("room", {})

# load_room, but reporting WHY the room came back empty:
#   {status: "ok"|"missing"|"error", room: Dictionary}
# "missing" is a real 404 — the room is gone. "error" is a network/server failure
# and says nothing about whether the room exists; a caller must retry rather than
# conclude anything. The distinction matters twice over, because an empty room is
# also TERMINAL for the hub pointer: reconciling on a failed read doesn't just
# paint the wrong screen, it deletes the card the player would use to get back.
# So the reconcile below happens only when we actually know the answer.
func load_room_status(cid: String) -> Dictionary:
	var res := await _load_room_status(cid)
	if String(res.get("status", "error")) != "error":
		# A one-shot paint of a room that's already terminal for us (e.g. opening a stale
		# hub card into a since-finished room) self-heals the pointer too.
		_reconcile_room_cache(cid, res.get("room", {}))
	return res

# How many times load_room_retrying re-reads before giving up, and the gap between
# attempts. Deliberately small: each attempt can burn the full 6s HTTP timeout, so
# every extra try is another 6 seconds a genuinely offline player spends staring at
# "Loading…". Two covers a transient blip; past that the manual "Try Again" face is
# the better answer than a longer silent wait.
const ROOM_READ_RETRIES := 2
const ROOM_READ_RETRY_GAP := 1.5

# load_room_status with retries on "error" only — a 404 is an answer and returns
# immediately. Use this anywhere a failed read would otherwise be rendered as
# "this room no longer exists".
func load_room_retrying(cid: String) -> Dictionary:
	var res := {}
	for attempt in ROOM_READ_RETRIES:
		res = await load_room_status(cid)
		if String(res.get("status", "error")) != "error":
			return res
		if attempt < ROOM_READ_RETRIES - 1:
			await get_tree().create_timer(ROOM_READ_RETRY_GAP).timeout
	return res

# Attach a live listener for `cid`. Fires room_changed(cid, room) with the current
# state immediately and on every subsequent change (an empty room = deleted).
func watch_room(cid: String) -> void:
	if cid.is_empty():
		return
	_watching[cid] = true
	_watch_seen[cid] = {"t": _now(), "st": "", "gone": false}
	if _is_editor:
		call_deferred("_sim_emit", cid)
	else:
		# Watch the coalesced materialized mirror, not the raw room (see _STATE_COLL).
		Firebase.firestore.listen_to_document(_STATE_COLL + "/" + cid)
		_start_watchdog()

func unwatch_room(cid: String) -> void:
	if not _watching.has(cid):
		return
	_watching.erase(cid)
	_watch_seen.erase(cid)
	if not _is_editor:
		Firebase.firestore.stop_listening_to_document(_STATE_COLL + "/" + cid)
		if _watching.is_empty() and _watchdog:
			_watchdog.stop()

# ---- watchdog: notice a room that vanished (see WATCHDOG_SECS) ----

func _start_watchdog() -> void:
	if _watchdog == null:
		_watchdog = Timer.new()
		_watchdog.wait_time = WATCHDOG_TICK
		_watchdog.timeout.connect(_on_watchdog)
		add_child(_watchdog)
	if _watchdog.is_stopped():
		_watchdog.start()

# A listener push always resets the clock, so this only ever reads for a room that has
# gone quiet. Rooms already reported gone, and rooms whose last state was terminal, are
# skipped — there's nothing left to learn about them.
func _on_watchdog() -> void:
	if _watchdog_busy or _watching.is_empty():
		return
	var now := _now()
	for cid in _watching.keys():
		var seen: Dictionary = _watch_seen.get(cid, {})
		if bool(seen.get("gone", false)) or String(seen.get("st", "")) == "finished":
			continue
		if now - int(seen.get("t", now)) < WATCHDOG_SECS:
			continue
		_watchdog_busy = true
		var res := await _load_room_status(cid)
		_watchdog_busy = false
		if not _watching.has(cid):
			continue
		var read_status := String(res.get("status", "error"))
		# A read that FAILED tells us nothing. Declaring the room gone on it is the
		# worst possible misread: it tears down the results board and clears the hub
		# pointer, so the player is put out of a room that never went anywhere. This
		# is not a rare case either — NOTIFICATION_APPLICATION_RESUMED ages every
		# watched room out, so dismissing a full-screen ad schedules this read for
		# the exact moment the network is least likely to answer. Leave the clock
		# untouched and let the next window ask again.
		if read_status == "error":
			continue
		var room: Dictionary = res.get("room", {})
		if room.is_empty():
			_emit_room(cid, {})       # deleted out from under us — nobody would have told us
			continue
		# Still there: don't re-emit an unchanged room (that would rebuild the screen
		# every window and restart its animations), but DO push a status we somehow
		# missed — that's a dropped listener, and the room moving on without us.
		var seen2: Dictionary = _watch_seen.get(cid, {})
		if String(room.get("status", "")) != String(seen2.get("st", "")):
			_emit_room(cid, room)
		else:
			seen2["t"] = _now()
			_watch_seen[cid] = seen2

# Coming back from the background is the likeliest moment to have missed something (the
# listener was torn down while we were away, and anything deleted meanwhile is invisible
# either way), so age every watched room out and let the next tick re-confirm it.
func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_RESUMED:
		return
	if _watch_seen.is_empty():
		return
	for cid in _watch_seen:
		var seen: Dictionary = _watch_seen[cid]
		seen["t"] = 0
		_watch_seen[cid] = seen
	# And re-confirm NOW rather than on the next tick. Anything that backgrounds the
	# app (a rewarded ad, an app switch) can cover the very window in which the room
	# finishes, so waiting out up to WATCHDOG_TICK on top of that is the difference
	# between "the podium is up when I come back" and staring at the waiting board.
	call_deferred("_on_watchdog")

# Android live-listener callback. `data` is the changed document (decoded by the
# plugin, or REST-style with a "fields" wrapper). An empty / identity-less payload
# means the doc was deleted.
func _on_document_changed(document_path: String, data: Dictionary) -> void:
	if document_path.begins_with(_STATE_COLL + "/"):
		_on_state_changed(document_path, data)
		return
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
		_emit_room(cid, {})   # deleted / gone
		return
	_emit_room(cid, _shape_room(raw, cid))

# Live-listener callback for the materialized contest_state/{cid} the client watches
# in place of the raw room. Payload is { summary:{...}, updated_unix }. An empty /
# summary-less payload is AMBIGUOUS — either the room isn't materialized yet (just
# created, the function hasn't run) or it was deleted — so we resolve it with one
# authoritative read of contests/{cid} rather than guess "gone" and flash the room away.
func _on_state_changed(document_path: String, data: Dictionary) -> void:
	var cid := document_path.substr((_STATE_COLL + "/").length())
	if not _watching.has(cid):
		return
	var raw: Dictionary = data
	if data.has("fields"):
		raw = _fields(data["fields"])
	var summary: Variant = raw.get("summary", null)
	if not (summary is Dictionary) or (summary as Dictionary).is_empty():
		call_deferred("_confirm_room_presence", cid)
		return
	_emit_room(cid, _shape_room(summary, cid))

# Resolve an empty contest_state push against the source of truth: the room still
# exists (not yet materialized) → emit its current raw state; it's really gone → {}.
func _confirm_room_presence(cid: String) -> void:
	if not _watching.has(cid):
		return
	var room := await _load_room(cid)
	if not _watching.has(cid):
		return
	_emit_room(cid, room)

# Editor-sim emit for a watched room.
func _sim_emit(cid: String) -> void:
	if not _watching.has(cid):
		return
	var r: Variant = _sim_rooms.get(cid, null)
	_emit_room(cid, _shape_room(r, cid) if r is Dictionary else {})

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
	compact_lobby_shards()

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

# Reclaims dead entries from the lobby index shards. Closing a room only marks its
# entry o=0 (a merge can't delete a map key — see _lobby_close); the key is
# otherwise reclaimed only when a shard fills to its cap and needs a slot
# (_lobby_pick_shard compaction). At low traffic a shard never reaches the cap, so
# closed/started/finished rooms pile up as dead keys — invisible in the browse list
# (lobby_rows filters them) but real clutter in the docs. This rewrites any shard
# that carries dead keys down to just its still-open entries, using the SAME
# liveness predicate as lobby_rows/_lobby_pick_shard, so nothing a viewer can still
# see is ever dropped. Bounded to LOBBY_SHARDS writes, and only writes a shard that
# actually has junk. Runs alongside sweep_expired_rooms() when the lobby opens.
#
# Same last-write-wins caveat as _lobby_claim's compaction: a room created into a
# shard in the instant between our read and our non-merge rewrite can be dropped
# from the LIST (the room doc itself survives and its host can reopen it). Rare by
# construction — only a create landing in the exact shard mid-rewrite — and
# self-healing.
func compact_lobby_shards() -> void:
	if _is_editor or _uid().is_empty():
		return
	var shards := await _lobby_read_all()
	var now := _now()
	for n in LOBBY_SHARDS:
		var rooms: Dictionary = shards.get(n, {})
		if rooms.is_empty():
			continue
		var live: Dictionary = {}
		for cid in rooms:
			var e: Variant = rooms[cid]
			if not (e is Dictionary):
				continue
			var open_at := int((e as Dictionary).get("o", 0))
			if open_at > 0 and now < open_at + START_WINDOW:
				live[cid] = e
		# Only rewrite when there's actually something to reclaim — a shard with no
		# dead keys must not cost a write (and must not widen the race window above).
		if live.size() == rooms.size():
			continue
		await _lobby_write(n, {"rooms": live}, false)

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

# Stage-2 lobby read: ONE authoritative read of the CF-maintained lobby_index/open
# doc (the whole open-public-room list), shaped into display rows. This is what the
# hub's Refresh button calls — one read for the list, versus the old live 5-shard
# listeners that took a push per room event. Rows match lobby_rows()'s shape.
func refresh_lobby() -> Array:
	var rooms := await _load_lobby_index()
	return _lobby_rows_from(rooms)

func _load_lobby_index() -> Dictionary:
	if _is_editor:
		# No Cloud Function in the editor sim; merge the sim shards to mirror the
		# single index the function would maintain.
		var merged: Dictionary = {}
		for n in _sim_shards:
			for cid in (_sim_shards[n] as Dictionary):
				merged[cid] = _sim_shards[n][cid]
		return merged
	var r := await _http_get(_FB_BASE + "/" + _LOBBY_INDEX_PATH)
	if r[1] != 200:
		return {}
	var j := JSON.new()
	j.parse((r[3] as PackedByteArray).get_string_from_utf8())
	if not (j.data is Dictionary):
		return {}
	var f := _fields((j.data as Dictionary).get("fields", {}))
	var rooms: Variant = f.get("rooms", {})
	return rooms if rooms is Dictionary else {}

# Filter + sort a rooms map (cid -> {t,d,c,o,u}) into display rows, using the SAME
# liveness predicate as the shards (now < o + START_WINDOW), freshest first.
func _lobby_rows_from(rooms: Dictionary) -> Array:
	var now := _now()
	var out: Array = []
	for cid in rooms:
		var e: Variant = rooms[cid]
		if not (e is Dictionary):
			continue
		var open_at := int((e as Dictionary).get("o", 0))
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
		return String(a["id"]) < String(b["id"]))
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

# Accepts the LEGACY Crockford-base32 alphabet as well as the digits we now generate.
# Already-released builds hand out codes with letters in them, and their rooms show up
# in the browse list for everyone — validating only against ID_ALPHABET made every one
# of those rooms unjoinable ("no room found") until those builds age out. New codes are
# still digits-only; this only widens what we'll ACCEPT.
const ID_ALPHABET_LEGACY := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

func _valid_id(cid: String) -> bool:
	if cid.length() != ID_LEN:
		return false
	for c in cid:
		if ID_ALPHABET_LEGACY.find(c) < 0:
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
	return (await _load_room_status(cid)).get("room", {})

# The read behind _load_room, keeping the 404-vs-failure distinction its callers
# throw away. See load_room_status for why anything user-facing needs it.
func _load_room_status(cid: String) -> Dictionary:
	if not _valid_id(cid):
		return {"status": "missing", "room": {}}
	if _is_editor:
		var r: Variant = _sim_rooms.get(cid, null)
		if r is Dictionary:
			return {"status": "ok", "room": _shape_room(r, cid)}
		return {"status": "missing", "room": {}}
	var res := await _rest_get_status(_COLL, cid)
	var status := String(res.get("status", "error"))
	if status != "ok":
		return {"status": status, "room": {}}
	return {"status": "ok", "room": _shape_room(res.get("data", {}), cid)}

# Merge-write on the room doc. In the sim, `merge` deep-merges (including a nested
# `players` map) so a partial write never drops sibling fields/players.
# Returns whether the write landed. The plugin answers every write on ONE shared
# signal, so a result can't be correlated to its request with certainty — which is why
# this only ever reports failure on an EXPLICIT `status:false`, never on a shape it
# doesn't recognise. Good enough for the paths that must not pretend to have succeeded
# (giving up a seat, closing a room), and harmless everywhere else.
func _write_room(cid: String, data: Dictionary, merge: bool) -> bool:
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
		return true
	Firebase.firestore.set_document(_COLL, cid, data, merge)
	var res: Variant = await Firebase.firestore.write_task_completed
	return not (res is Dictionary and (res as Dictionary).get("status", true) == false)

# Merge-write a single player's record (only touches players.<uid>).
func _write_player(cid: String, uid: String, rec: Dictionary) -> bool:
	return await _write_room(cid, {"players": {uid: rec}}, true)

func _delete_room(cid: String) -> void:
	if _is_editor:
		_sim_rooms.erase(cid)
		if _watching.has(cid):
			_emit_room(cid, {})
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
		# Set by _close_room: the room didn't run to a finish, the host ended it. Rides
		# alongside status "finished" (see _close_room for why the status isn't its own
		# value), and is what screens key the "host closed this room" face on.
		"cancelled": bool(src.get("cancelled", false)),
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
	var res := await _rest_get_status(collection, doc_id)
	var ok := String(res.get("status", "error")) == "ok"
	return {"exists": ok, "data": res.get("data", {})}

# Like _rest_get, but separates a definitive 404 (the doc is genuinely gone) from a
# network/server failure. Collapsing the two is how a room that is perfectly alive
# gets rendered as "This room no longer exists": the read is issued with a 6s
# timeout, and the one moment it is most likely to fail is exactly when a
# full-screen ad has just backgrounded the app. Callers that decide whether a room
# still exists MUST use this and treat "error" as "unknown, try again", never as
# "gone". Returns {status: "ok"|"missing"|"error", data}.
func _rest_get_status(collection: String, doc_id: String) -> Dictionary:
	var r := await _http_get(_FB_BASE + "/" + collection + "/" + doc_id)
	var code := int(r[1])
	if code == 200:
		var j := JSON.new()
		j.parse((r[3] as PackedByteArray).get_string_from_utf8())
		if j.data is Dictionary:
			return {"status": "ok", "data": _fields(j.data.get("fields", {}))}
		return {"status": "error", "data": {}}
	if code == 404:
		return {"status": "missing", "data": {}}
	return {"status": "error", "data": {}}

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
