extends Node

# Arena contests. A player creates a contest (a TYPE + a DIFFICULTY), shares its
# short ID, friends join, the creator starts it, everyone plays *inside the
# contest*, and at the end a frozen podium + standings table is shown. Contests
# are cleaned up once finished and abandoned.
#
# --- Storage model (why it looks like this) --------------------------------
# There is NO server (no Cloud Functions). So there is no trusted clock/compute
# to end a timed contest, freeze scores, or delete abandoned docs. Everything is
# done cooperatively by clients, guarded by firestore.rules + Firestore TTL.
#
#   contests/{CID}                    -> meta (public read; owner/member writes)
#   contest_members/{CID__uid}        -> one row per participant (public read;
#                                        each user writes only their own row;
#                                        the creator may delete any row = kick)
#
# "Which contests am I in" is answered by querying contest_members where
# uid == me (NOT by a list on the user doc). A list-on-user-doc would need
# set(merge:true) to *remove* a map key on leave, which Firestore's deep-merge
# cannot do — the query model sidesteps that entirely and keeps writes minimal.
#
# Reads: public collections are read over Firestore's REST endpoints (the
# plugin's collection-read callbacks are unreliable on Android — same reason the
# leaderboard uses REST). Writes/deletes go through the plugin so the native
# FirebaseAuth context is applied and the rules see request.auth.
#
# Editor (non-Android) runs an in-memory sim mirroring the live shapes so the
# whole create -> join -> start -> play -> finalize -> leave -> delete lifecycle
# is testable without a device.

signal my_contests_changed
signal contest_updated(contest_id: String)

# ---- caps (v1; shop upgrades add to the base later) ----
const JOIN_LIMIT_BASE := 2
const CREATE_LIMIT_BASE := 1
const MAX_MEMBERS := 45
# Contest titles are player-authored; displayed big and clamped to this length
# everywhere (mirrors ArenaUI.TITLE_MAX + titleOk() in firestore.rules).
const TITLE_MAX := 15

const TYPES: Array[String] = ["one_game", "one_hour", "one_day", "daily"]
const DIFFS: Array[String] = ["easy", "moderate", "hard"]

# Grace after a timed deadline before we finalize past a member who is still
# mid-game (someone playing at the buzzer gets to finish; a crashed player can't
# wedge the contest forever).
const GRACE_SECS := 300
# TTL horizon written to `expires_at` on every contest + member write. Firestore
# TTL policies on these fields reap orphans if a client never runs cleanup.
const TTL_SECS := 3 * 86400

const ID_LEN := 6
# Crockford base32 minus I,L,O,U — unambiguous when shared verbally / typed.
const ID_ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
const MAX_SCORE := 9999   # mirror scoreOk() in firestore.rules

const _COLL := "contests"
const _MEMBERS := "contest_members"
const _FB_BASE := "https://firestore.googleapis.com/v1/projects/simon-6bc39/databases/(default)/documents"

var _is_editor := OS.get_name() != "Android"

# ---- editor sim stores (shape mirrors Firestore) ----
var _sim_contests: Dictionary = {}    # cid -> meta dict
var _sim_members: Dictionary = {}     # "CID__uid" -> member dict

func _ready() -> void:
	FirebaseManager.display_name_changed.connect(_on_display_name_changed)

func _uid() -> String:  return FirebaseManager.uid
func _name() -> String:
	var n := FirebaseManager.display_name
	return n if not n.is_empty() else "Player"

func _now() -> int: return int(Time.get_unix_time_from_system())

func _member_id(cid: String, uid: String) -> String:
	return cid + "__" + uid

func _expires_iso(base_now: int) -> String:
	return Time.get_datetime_string_from_unix_time(base_now + TTL_SECS) + "Z"

# ---- static display helpers (screens reuse these) ----

static func type_label(t: String) -> String:
	match t:
		"one_game": return "1 Game"
		"one_hour": return "1 Hour"
		"one_day":  return "1 Day"
		"daily":    return "Daily"
	return t

static func type_rule(t: String) -> String:
	match t:
		"one_game": return "Everyone plays one game — highest score wins."
		"one_hour": return "Highest score within 1 hour of the start."
		"one_day":  return "Highest score within 24 hours of the start."
		"daily":    return "Highest score before the day ends (00:00 UTC)."
	return ""

static func diff_label(d: String) -> String:
	return d.capitalize()

# =====================================================================
#  CAPS
# =====================================================================

func join_limit() -> int:  return JOIN_LIMIT_BASE
func create_limit() -> int: return CREATE_LIMIT_BASE

# {join: <#contests I'm in>, create: <#I created>, join_limit, create_limit}.
# Source of truth = my member rows (one query), so it can't drift from reality.
func get_my_counts() -> Dictionary:
	var mine := await _load_my_memberships()
	var created := 0
	for m in mine:
		if bool(m.get("is_creator", false)):
			created += 1
	return {"join": mine.size(), "create": created,
		"join_limit": join_limit(), "create_limit": create_limit()}

# =====================================================================
#  CREATE
# =====================================================================

# Funny fallback contest names (all within TITLE_MAX). Offered as suggestions on the
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
func create_contest(type: String, difficulty: String, title: String = "") -> Dictionary:
	if _uid().is_empty() or not FirebaseManager.has_display_name():
		return {"ok": false, "error": "auth"}
	if not TYPES.has(type) or not DIFFS.has(difficulty):
		return {"ok": false, "error": "bad_args"}
	var counts := await get_my_counts()
	if int(counts["create"]) >= create_limit():
		return {"ok": false, "error": "at_create_limit"}

	var now := _now()
	for _attempt in 6:
		var cid := _gen_id()
		if await _contest_exists(cid):
			continue
		var meta := {
			"id": cid,
			"title": clean_title(title),
			"creator_uid": _uid(),
			"creator_name": _name(),
			"type": type,
			"difficulty": difficulty,
			"status": "lobby",
			"member_count": 1,
			"created_at": now,
			"started_at": 0,
			"deadline_at": 0,
			"finished_at": 0,
			"expires_at": _expires_iso(now),
		}
		await _write_contest(cid, meta, false)
		await _write_member(cid, _new_member_row(cid, true, now))
		emit_signal("my_contests_changed")
		return {"ok": true, "id": cid}
	return {"ok": false, "error": "id_collision"}

func _new_member_row(cid: String, is_creator: bool, now: int) -> Dictionary:
	return {
		"contest_id": cid,
		"uid": _uid(),
		"name": _name(),
		"is_creator": is_creator,
		"joined_at": now,
		"best_score": 0,
		"games_played": 0,
		"last_played_at": 0,
		"state": "joined",
		"done": false,
		"expires_at": _expires_iso(now),
	}

# =====================================================================
#  JOIN
# =====================================================================

# Returns {ok} or {ok:false, error} with error in
# {auth, not_found, ended, full, at_join_limit}.
func join_contest(raw_id: String) -> Dictionary:
	if _uid().is_empty() or not FirebaseManager.has_display_name():
		return {"ok": false, "error": "auth"}
	var cid := raw_id.strip_edges().to_upper()
	if not _valid_id(cid):
		return {"ok": false, "error": "not_found"}

	# Already a member? Treat join as a no-op success so the UI just opens it.
	var mine := await _load_my_memberships()
	for m in mine:
		if String(m.get("contest_id", "")) == cid:
			return {"ok": true, "already": true}
	# Cap check uses the same freshly-loaded list.
	var join_count := mine.size()

	var meta := await _load_meta(cid)
	if meta.is_empty():
		return {"ok": false, "error": "not_found"}
	if String(meta.get("status", "")) == "finished":
		return {"ok": false, "error": "ended"}
	if join_count >= join_limit():
		return {"ok": false, "error": "at_join_limit"}
	var members := await _load_members(cid)
	if members.size() >= MAX_MEMBERS:
		return {"ok": false, "error": "full"}

	var now := _now()
	await _write_member(cid, _new_member_row(cid, false, now))
	# member_count is a display/delete hint; recomputed authoritatively on leave.
	await _write_contest(cid, {
		"member_count": members.size() + 1,
		"expires_at": _expires_iso(now),
	}, true)
	emit_signal("my_contests_changed")
	return {"ok": true}

# =====================================================================
#  START  (creator only)
# =====================================================================

func start_contest(cid: String) -> Dictionary:
	var meta := await _load_meta(cid)
	if meta.is_empty():
		return {"ok": false, "error": "not_found"}
	if String(meta.get("creator_uid", "")) != _uid():
		return {"ok": false, "error": "not_creator"}
	if String(meta.get("status", "")) != "lobby":
		return {"ok": false, "error": "already_started"}

	var now := _now()
	var deadline := _compute_deadline(String(meta.get("type", "")), now)
	await _write_contest(cid, {
		"status": "active",
		"started_at": now,
		"deadline_at": deadline,
		"expires_at": _expires_iso(now),
	}, true)
	emit_signal("contest_updated", cid)
	return {"ok": true}

func _compute_deadline(type: String, now: int) -> int:
	match type:
		"one_hour": return now + 3600
		"one_day":  return now + 86400
		"daily":    return _next_utc_midnight(now)
		_:          return 0    # one_game is event-driven

func _next_utc_midnight(now: int) -> int:
	var day_index := int(floor(float(now) / 86400.0))
	return (day_index + 1) * 86400

# =====================================================================
#  GAMEPLAY HAND-OFF
# =====================================================================

# Sets the contest context on GameState, applies the contest difficulty, and
# marks this member in_progress. The SCREEN navigates to the game afterwards.
# best_before/games_before are passed from the already-loaded detail data so we
# don't spend a read to learn them.
func begin_contest_game(cid: String, type: String, difficulty: String,
		best_before: int, games_before: int) -> void:
	GameState.contest_context = {
		"id": cid, "type": type, "difficulty": difficulty,
		"best_before": best_before, "games_before": games_before,
	}
	GameState.set_difficulty(difficulty)
	var now := _now()
	await _write_member(cid, {
		"contest_id": cid, "uid": _uid(), "state": "in_progress",
		"expires_at": _expires_iso(now),
	}, true)

# Records a finished contest game. `ctx` is the captured GameState.contest_context
# (game_over.gd clears the global one and passes a copy here). Returns the
# (possibly finalized) meta.
func submit_contest_result(ctx: Dictionary, score: int) -> Dictionary:
	var cid := String(ctx.get("id", ""))
	if cid.is_empty() or _uid().is_empty():
		return {}
	var type := String(ctx.get("type", ""))
	var best_before := int(ctx.get("best_before", 0))
	var games_before := int(ctx.get("games_before", 0))
	var s := clampi(score, 0, MAX_SCORE)
	var now := _now()
	var new_best := maxi(best_before, s)
	var is_done := type == "one_game"
	await _write_member(cid, {
		"contest_id": cid, "uid": _uid(), "name": _name(),
		"best_score": new_best, "games_played": games_before + 1,
		"last_played_at": now, "state": "playing_done", "done": is_done,
		"expires_at": _expires_iso(now),
	}, true)

	var meta := await _load_meta(cid)
	# Only one_game resolves on submit (all-played condition). Timed contests
	# resolve when a client's countdown hits 0 — no read spent here.
	if type == "one_game":
		var members := await _load_members(cid)
		# Guard against read-after-write staleness for OUR row: the plugin's
		# write_task_completed is shared, so our await above can resume before our
		# write is visible to the REST read. Force our just-written values in so the
		# "everyone is done" check can't miss the write that triggered it.
		members = _patch_self_row(members, cid, new_best, games_before + 1, now, is_done)
		meta = await _finalize_if_ended(cid, meta, members)
	emit_signal("contest_updated", cid)
	return meta

# Returns `members` with the current user's row set to the given freshly-written
# values (added if the read didn't return it yet).
func _patch_self_row(members: Array, cid: String, best: int, games: int,
		now: int, done: bool) -> Array:
	var out := members.duplicate(true)
	var found := false
	for m in out:
		if String(m.get("uid", "")) == _uid():
			m["best_score"] = best
			m["games_played"] = games
			m["last_played_at"] = now
			m["state"] = "playing_done"
			m["done"] = done
			found = true
			break
	if not found:
		out.append({
			"contest_id": cid, "uid": _uid(), "name": _name(),
			"is_creator": false, "joined_at": now,
			"best_score": best, "games_played": games, "last_played_at": now,
			"state": "playing_done", "done": done,
		})
	return out

# =====================================================================
#  LOAD  (detail screen)
# =====================================================================

# Returns {ok, meta, members, my_member, i_am_member, standings} or
# {ok:false, error:"not_found"}. Runs an opportunistic finalize. Members are
# read at most once.
func load_contest(cid: String) -> Dictionary:
	var meta := await _load_meta(cid)
	if meta.is_empty():
		return {"ok": false, "error": "not_found"}
	# Already finished: the frozen standings are the source of truth (live member
	# rows may already be partly deleted as players exit), so don't read them.
	if String(meta.get("status", "")) == "finished":
		return {
			"ok": true, "meta": meta,
			"standings": _parse_standings(meta),
			"members": [], "my_member": {}, "i_am_member": false,
		}

	var members := await _load_members(cid)
	if String(meta.get("status", "")) == "active":
		meta = await _finalize_if_ended(cid, meta, members)
		if String(meta.get("status", "")) == "finished":
			return {
				"ok": true, "meta": meta,
				"standings": _parse_standings(meta),
				"members": [], "my_member": {}, "i_am_member": false,
			}

	var my_member := {}
	for m in members:
		if String(m.get("uid", "")) == _uid():
			my_member = m
			break
	return {
		"ok": true, "meta": meta, "members": members,
		"my_member": my_member, "i_am_member": not my_member.is_empty(),
		"standings": [],
	}

# =====================================================================
#  MY CONTESTS  (hub list)
# =====================================================================

func load_my_contests() -> Array:
	if _uid().is_empty():
		return []
	var mine := await _load_my_memberships()
	var out: Array = []
	for m in mine:
		var cid := String(m.get("contest_id", ""))
		if cid.is_empty():
			continue
		var meta := await _load_meta(cid)
		if meta.is_empty():
			# Contest gone (deleted/expired) — drop my orphan row.
			await _delete_member(cid, _uid())
			continue
		out.append({
			"id": cid,
			"title": String(meta.get("title", "Contest")),
			"type": String(meta.get("type", "")),
			"difficulty": String(meta.get("difficulty", "easy")),
			"status": String(meta.get("status", "lobby")),
			"is_creator": String(meta.get("creator_uid", "")) == _uid(),
			"member_count": int(meta.get("member_count", 1)),
			"deadline_at": int(meta.get("deadline_at", 0)),
			"my_state": String(m.get("state", "joined")),
			"my_done": bool(m.get("done", false)),
			"my_best": int(m.get("best_score", 0)),
		})
	return out

# =====================================================================
#  KICK / FINALIZE-NOW  (creator)
# =====================================================================

func kick_member(cid: String, target_uid: String) -> Dictionary:
	var meta := await _load_meta(cid)
	if meta.is_empty():
		return {"ok": false, "error": "not_found"}
	if String(meta.get("creator_uid", "")) != _uid():
		return {"ok": false, "error": "not_creator"}
	if target_uid == _uid():
		return {"ok": false, "error": "cant_kick_self"}
	await _delete_member(cid, target_uid)
	var members := await _load_members(cid)
	await _write_contest(cid, {"member_count": members.size()}, true)
	emit_signal("contest_updated", cid)
	return {"ok": true}

# Creator forces a one_game (or any) contest to end now with current scores.
func finalize_now(cid: String) -> Dictionary:
	var meta := await _load_meta(cid)
	if meta.is_empty():
		return {"ok": false, "error": "not_found"}
	if String(meta.get("creator_uid", "")) != _uid():
		return {"ok": false, "error": "not_creator"}
	if String(meta.get("status", "")) != "active":
		return {"ok": false, "error": "not_active"}
	var members := await _load_members(cid)
	meta = await _do_finalize(cid, meta, members)
	emit_signal("contest_updated", cid)
	return {"ok": true, "meta": meta}

# Creator explicitly deletes the whole contest (any status). Tears down every
# member row first (each rule-allowed as the creator), then the contest doc.
# member_count is dropped to 0 before the contest delete so the rule's
# empty-delete path also covers us if the creator lookup is momentarily stale.
func delete_contest(cid: String) -> Dictionary:
	var meta := await _load_meta(cid)
	if meta.is_empty():
		await _delete_member(cid, _uid())
		emit_signal("my_contests_changed")
		return {"ok": true}
	if String(meta.get("creator_uid", "")) != _uid():
		return {"ok": false, "error": "not_creator"}
	var members := await _load_members(cid)
	for m in members:
		await _delete_member(cid, String(m.get("uid", "")))
	await _write_contest(cid, {"member_count": 0}, true)
	await _delete_contest(cid)
	emit_signal("my_contests_changed")
	emit_signal("contest_updated", cid)
	return {"ok": true}

# =====================================================================
#  LEAVE  (+ cleanup / deletion)
# =====================================================================

func leave_contest(cid: String) -> void:
	var meta := await _load_meta(cid)
	if meta.is_empty():
		# Already gone — nothing to leave; drop any orphan row.
		await _delete_member(cid, _uid())
		emit_signal("my_contests_changed")
		return

	var is_creator := String(meta.get("creator_uid", "")) == _uid()
	var status := String(meta.get("status", ""))

	# Creator leaving a live/lobby contest cancels it for everyone.
	if is_creator and status != "finished":
		if status == "lobby":
			# Tear the whole contest down (members self-heal their orphan rows).
			var members_l := await _load_members(cid)
			for m in members_l:
				await _delete_member(cid, String(m.get("uid", "")))
			await _delete_contest(cid)
			emit_signal("my_contests_changed")
			emit_signal("contest_updated", cid)
			return
		else:
			# Active: freeze standings first so far-along members still get a
			# podium, then fall through to a normal member-leave below.
			var members_f := await _load_members(cid)
			meta = await _do_finalize(cid, meta, members_f)

	# Normal member leave.
	await _delete_member(cid, _uid())
	var members := await _load_members(cid)
	# Always publish the new count FIRST (even 0). The contest-delete rule keys on
	# member_count <= 0, so a non-creator last-leaver must lower it before the
	# delete, or the delete would be denied.
	await _write_contest(cid, {
		"member_count": members.size(),
		"expires_at": _expires_iso(_now()),
	}, true)
	if members.is_empty():
		await _delete_contest(cid)
	emit_signal("my_contests_changed")
	emit_signal("contest_updated", cid)

# =====================================================================
#  FINALIZATION
# =====================================================================

# Finalizes only if the end condition is met; otherwise returns meta unchanged.
func maybe_finalize(cid: String) -> Dictionary:
	var meta := await _load_meta(cid)
	if meta.is_empty() or String(meta.get("status", "")) != "active":
		return meta
	var members := await _load_members(cid)
	return await _finalize_if_ended(cid, meta, members)

func _finalize_if_ended(cid: String, meta: Dictionary, members: Array) -> Dictionary:
	if meta.is_empty() or String(meta.get("status", "")) != "active":
		return meta
	var type := String(meta.get("type", ""))
	var ended := false
	if type == "one_game":
		if members.size() > 0:
			ended = true
			for m in members:
				if not bool(m.get("done", false)):
					ended = false
					break
	else:
		var deadline := int(meta.get("deadline_at", 0))
		var now := _now()
		if deadline > 0 and now >= deadline:
			var any_in_progress := false
			for m in members:
				if String(m.get("state", "")) == "in_progress":
					any_in_progress = true
					break
			ended = (not any_in_progress) or (now >= deadline + GRACE_SECS)
	if not ended:
		return meta
	return await _do_finalize(cid, meta, members)

# Writes the frozen result. Idempotent + deterministic, so two clients racing to
# finalize converge on the same standings.
func _do_finalize(cid: String, meta: Dictionary, members: Array) -> Dictionary:
	var ranked := _rank_members(members)
	var standings := {}
	for i in ranked.size():
		var m: Dictionary = ranked[i]
		standings[str(i + 1)] = {
			"uid": String(m.get("uid", "")),
			"name": String(m.get("name", "Player")),
			"score": int(m.get("best_score", 0)),
			"games": int(m.get("games_played", 0)),
		}
	var now := _now()
	var patch := {
		"status": "finished", "finished_at": now,
		"standings": standings, "expires_at": _expires_iso(now),
	}
	await _write_contest(cid, patch, true)
	var out := meta.duplicate(true)
	for k in patch:
		out[k] = patch[k]
	return out

# Sort: highest score first; tie -> whoever reached it earlier; then join order.
# Members who never played (best 0 / last_played 0) sink to the bottom.
func _rank_members(members: Array) -> Array:
	var arr := members.duplicate(true)
	arr.sort_custom(func(a, b):
		var sa := int(a.get("best_score", 0))
		var sb := int(b.get("best_score", 0))
		if sa != sb:
			return sa > sb
		var la := int(a.get("last_played_at", 0))
		var lb := int(b.get("last_played_at", 0))
		var na := la if la > 0 else 0x7FFFFFFF
		var nb := lb if lb > 0 else 0x7FFFFFFF
		if na != nb:
			return na < nb
		return int(a.get("joined_at", 0)) < int(b.get("joined_at", 0))
	)
	return arr

# Frozen standings (meta.standings map) -> ordered Array of
# {uid, name, score, games, rank, is_me}.
func _parse_standings(meta: Dictionary) -> Array:
	var raw: Variant = meta.get("standings", {})
	var out: Array = []
	if not (raw is Dictionary):
		return out
	var keys := (raw as Dictionary).keys()
	keys.sort_custom(func(a, b): return int(a) < int(b))
	for k in keys:
		var e: Dictionary = raw[k]
		out.append({
			"uid": String(e.get("uid", "")),
			"name": String(e.get("name", "Player")),
			"score": int(e.get("score", 0)),
			"games": int(e.get("games", 0)),
			"rank": int(k),
			"is_me": String(e.get("uid", "")) == _uid(),
		})
	return out

# =====================================================================
#  RENAME PROPAGATION
# =====================================================================

# Keep my name fresh on my active member rows (mirrors LeaderboardManager's
# rename propagation). Rare event, so a handful of writes is fine.
func _on_display_name_changed(new_name: String) -> void:
	if _uid().is_empty() or new_name.is_empty():
		return
	var mine := await _load_my_memberships()
	for m in mine:
		var cid := String(m.get("contest_id", ""))
		if cid.is_empty():
			continue
		await _write_member(cid, {
			"contest_id": cid, "uid": _uid(), "name": new_name,
		}, true)

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

func _contest_exists(cid: String) -> bool:
	if _is_editor:
		return _sim_contests.has(cid)
	var r := await _rest_get(_COLL, cid)
	return bool(r.get("exists", false))

func _load_meta(cid: String) -> Dictionary:
	if not _valid_id(cid):
		return {}
	if _is_editor:
		var m: Variant = _sim_contests.get(cid, null)
		return (m as Dictionary).duplicate(true) if m is Dictionary else {}
	var r := await _rest_get(_COLL, cid)
	if not bool(r.get("exists", false)):
		return {}
	return r.get("data", {})

func _load_members(cid: String) -> Array:
	if _is_editor:
		var out: Array = []
		for key in _sim_members:
			var m: Dictionary = _sim_members[key]
			if String(m.get("contest_id", "")) == cid:
				out.append(m.duplicate(true))
		return out
	return await _rest_query_members("contest_id", cid)

func _load_my_memberships() -> Array:
	if _uid().is_empty():
		return []
	if _is_editor:
		var out: Array = []
		for key in _sim_members:
			var m: Dictionary = _sim_members[key]
			if String(m.get("uid", "")) == _uid():
				out.append(m.duplicate(true))
		return out
	return await _rest_query_members("uid", _uid())

func _write_contest(cid: String, data: Dictionary, merge: bool) -> void:
	if _is_editor:
		var cur: Dictionary = _sim_contests.get(cid, {})
		if merge and not cur.is_empty():
			for k in data:
				cur[k] = data[k]
			_sim_contests[cid] = cur
		else:
			_sim_contests[cid] = data.duplicate(true)
		return
	Firebase.firestore.set_document(_COLL, cid, data, merge)
	await Firebase.firestore.write_task_completed

func _write_member(cid: String, data: Dictionary, merge: bool = false) -> void:
	var doc_id := _member_id(cid, String(data.get("uid", _uid())))
	if _is_editor:
		var cur: Dictionary = _sim_members.get(doc_id, {})
		if merge and not cur.is_empty():
			for k in data:
				cur[k] = data[k]
			_sim_members[doc_id] = cur
		else:
			_sim_members[doc_id] = data.duplicate(true)
		return
	Firebase.firestore.set_document(_MEMBERS, doc_id, data, merge)
	await Firebase.firestore.write_task_completed

func _delete_member(cid: String, uid: String) -> void:
	var doc_id := _member_id(cid, uid)
	if _is_editor:
		_sim_members.erase(doc_id)
		return
	Firebase.firestore.delete_document(_MEMBERS, doc_id)
	await Firebase.firestore.delete_task_completed

func _delete_contest(cid: String) -> void:
	if _is_editor:
		_sim_contests.erase(cid)
		return
	Firebase.firestore.delete_document(_COLL, cid)
	await Firebase.firestore.delete_task_completed

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

# runQuery on contest_members with a single equality filter (auto-indexed; no
# composite index needed). Returns Array of decoded member dicts.
func _rest_query_members(field: String, value: String) -> Array:
	var body := {"structuredQuery": {
		"from": [{"collectionId": _MEMBERS}],
		"where": {"fieldFilter": {
			"field": {"fieldPath": field},
			"op": "EQUAL",
			"value": {"stringValue": value},
		}},
		"limit": MAX_MEMBERS,
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
