extends Node

# Two parallel leaderboard families, one collection per difficulty:
#   global_{diff}/{uid}   -> { name, score }                            (all-time)
#   daily_{diff}/{date}__{uid} -> { uid, name, score, date, expires_unix }
#
# Reads use Firestore's REST endpoints (the plugin's read callbacks don't fire
# reliably on Android). Writes use the plugin so the native auth context is
# applied automatically.
#
# REST query strategy: instead of listing the whole collection and sorting on
# the client (which broke silently once a board crossed ~300 rows because the
# `list` endpoint orders by document name, NOT by score), we hit Firestore's
# structured-query and aggregation endpoints. This gets the real top-N at any
# size, plus the small "neighborhood" of rows around the signed-in player when
# they're outside the top-N.
#
# Composite indexes (Firestore console / `firebase deploy --only firestore:indexes`):
# the daily collections need an index per query shape because each query
# combines an equality on `date` with an inequality / orderBy on `score`. For
# each of daily_easy / daily_moderate / daily_hard:
#   - (date ASC, score DESC)  — top-N + neighborhood-below
#   - (date ASC, score ASC)   — neighborhood-above + rank count aggregation
# Firestore returns the create-link in its error payload the first time each
# query runs; that's the standard workflow for first-time setup.

# How many top rows the screen shows (the rest scrolls in the neighborhood, or
# is invisible). 20 was chosen so the podium (3) + remaining list (17 rows) fits
# the screen without scrolling at 720h, leaving the neighborhood snippet room.
const GLOBAL_TOP_N := 20
# Rows to fetch above + below the player when they're outside the top-N. With
# 3 above + the player + 3 below, the snippet reads as a clear "where you sit"
# panel without dominating the screen.
const NEIGHBOR_COUNT := 3
const DIFFS: Array[String] = ["easy", "moderate", "hard"]

# REST base for the Firestore project. The runQuery/runAggregationQuery
# endpoints hang off the same root.
const _FB_BASE := "https://firestore.googleapis.com/v1/projects/simon-6bc39/databases/(default)/documents"
# The bare resource path (no host/version) used inside :commit / :batchGet bodies,
# where documents are named by their full resource path.
const _FB_PROJECT_DOCS := "projects/simon-6bc39/databases/(default)/documents"

# ---- score histogram (scale-invariant rank) --------------------------------
# The rank of a player OUTSIDE the top-N used to need a count() aggregation over
# every row above them — O(players-above-me) reads, which grows without bound as
# the board grows. Instead we keep a materialized score histogram: for each score
# value, HOW MANY players hold that as their best. Rank is then pure arithmetic —
# read the (fixed-size) histogram and sum the counts of every score above mine —
# so a rank lookup costs a FIXED number of reads no matter how large the board is.
#
# Storage: board_hist/{board}_{k}  ->  { counts: { "<score>": <int> } }
# where {board} is e.g. "global_easy" and k is 0..HIST_SHARDS-1.
#
# Why shards: every score submit writes the histogram, and a single Firestore
# document sustains only ~1 write/sec. Each client writes to a RANDOM shard, so
# writes spread across HIST_SHARDS docs; the true count for a score is the SUM of
# that score's field across all shards. Reads batch-get all shards in one request.
# HIST_SHARDS is a small constant, so rank stays a fixed read cost. Raising it
# later is backward-compatible: new shards simply start empty at 0 (bump the client
# const first — reads must always cover every shard a writer might use — then, for
# daily, the matching HIST_SHARDS in functions/index.js). LOWERING it is NOT free:
# counts in dropped shards go unread, so re-run the histogram rebuild afterwards.
#
# Maintenance differs per family:
#  * ALL-TIME (global_{diff}): maintained by the CLIENT via Firestore's atomic
#    `increment` field-transform over REST :commit (the Android plugin can't do
#    atomic increments). On a new best the client does +1 at the new score and -1
#    at the old, in ONE commit to ONE random shard. (Kept client-side because the
#    shipped app already does this — moving it to the trigger would double-count
#    until old apps age out.)
#  * DAILY (daily_{diff}): maintained SERVER-SIDE by the syncDaily_* Cloud Function
#    trigger, which fires on every daily row write (any client version). The board
#    is PER-DAY — "daily_{diff}_{date}" — since a daily rank is only among that
#    day's players; the midnight closeDailyBoards job deletes each closed day's
#    histogram shards. This client only READS the daily histogram (never writes it).
#
# Trust: the histogram doc is world-writable (there's no native-auth token on the
# REST path), so a bad client can skew rank NUMBERS — but not the podium, which
# still derives from the auth-guarded per-uid rows. Same client-trusted posture as
# the boards themselves. Drift (a crash between the -1/+1, or a deleted account) is
# self-healing: rebuild_histograms() recomputes every shard from the rows.
# 3 shards sustain ~3 concurrent new-highs/sec — plenty until the game is much
# bigger — and keep a rank lookup at 3 reads. Raise later if a day genuinely sees
# thousands of simultaneous high scores (see the "Raising it" note above).
const HIST_SHARDS := 3
const _HIST_COLL := "board_hist"
# The all-time boards the CLIENT rebuild path re-tallies. Daily histograms are
# per-day and rebuilt server-side (functions/index.js rebuildHistogramsNow).
const _HIST_BOARDS: Array[String] = ["global_easy", "global_moderate", "global_hard"]

# Daily rows are keyed by `{date}__{uid}` (not `{uid}`), so a later replay never
# overwrites a prior day's row. Closed-day boards are now consumed SERVER-SIDE:
# the midnight Cloud Function (functions/index.js -> closeDailyBoards) reads
# yesterday's top 50, credits placement rewards, then deletes yesterday's rows —
# so the old "retain N days until the player returns to collect" reason is gone
# (rewards are pushed to /users, not pulled from these rows). The retention window
# + client sweep below remain only as a harmless backstop if the server job ever
# lags. The screen's `date == today` filter keeps history off the live board.
const _DAILY_RETENTION_DAYS := 14
# Buffer added past the retention window before writing the expiry, so a sweep
# never races a player active right at the day flip. 6h is plenty of slack.
const _DAILY_EXPIRES_BUFFER_SECS := 6 * 3600

var _is_editor := OS.get_name() != "Android"
# In-memory sims so the entire flow is testable in the editor without a device.
# Shape mirrors Firestore: collection -> uid -> doc.
var _sim_global := {"easy": {}, "moderate": {}, "hard": {}}
var _sim_daily := {"easy": {}, "moderate": {}, "hard": {}}

# Last-known all-time global rank per difficulty for the signed-in player,
# persisted to disk so the profile card can show a rank INSTANTLY on open
# instead of blocking on a network round-trip. Refreshed as a side effect of
# every real board load (leaderboards screen + profile), and keyed by uid so a
# different account never sees a stale rank from the previous one.
const _RANK_CACHE_PATH := "user://rank_cache.cfg"
var _rank_cache: Dictionary = {}   # diff -> int rank (>0)

# Boot-warmed board cache. Both families are fetched right after sign-in (well
# before the player can reach the leaderboards screen), so the screen can paint
# instantly from here with NO loading overlay and then quietly revalidate. Keys
# match the screen's range keys ("all_time" / "daily"). Now that every board read
# is fixed-cost, this warm-up is cheap and bounded regardless of DB size.
const RANGE_ALL_KEY := "all_time"
const RANGE_DAILY_KEY := "daily"
var _warm: Dictionary = {}                       # range_key -> load_all result
var _warm_ready := {RANGE_ALL_KEY: false, RANGE_DAILY_KEY: false}
var _warming := false

func _uid() -> String:  return FirebaseManager.uid
func _name() -> String: return FirebaseManager.display_name

func _ready() -> void:
	FirebaseManager.display_name_changed.connect(_on_display_name_changed)
	FirebaseManager.signed_in.connect(_on_signed_in)
	FirebaseManager.signed_out.connect(_on_signed_out)
	# Editor sign-in is synchronous, so we may already be signed in by now (the
	# signed_in signal fired before we connected). Cover that case: load the rank
	# cache and kick the board warm-up so the leaderboards screen opens instantly.
	if not _uid().is_empty():
		_load_rank_cache()
		warm_boards()

# The last cached all-time rank for `difficulty` (0 if unknown / not signed in).
func cached_rank(difficulty: String) -> int:
	return int(_rank_cache.get(difficulty, 0))

func _on_signed_in(_uid_in: String, _name_in: String) -> void:
	_rank_cache.clear()
	_load_rank_cache()
	# Preload both leaderboard families now so the screen never shows a loader.
	warm_boards()

func _on_signed_out() -> void:
	_rank_cache.clear()
	_warm.clear()
	_warm_ready[RANGE_ALL_KEY] = false
	_warm_ready[RANGE_DAILY_KEY] = false

# Record a freshly-computed rank for the signed-in player and persist it.
func _cache_rank(difficulty: String, rank: int) -> void:
	if rank <= 0 or _uid().is_empty():
		return
	if int(_rank_cache.get(difficulty, 0)) == rank:
		return
	_rank_cache[difficulty] = rank
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "uid", _uid())
	for d: String in _rank_cache:
		cfg.set_value("ranks", d, int(_rank_cache[d]))
	cfg.save(_RANK_CACHE_PATH)

func _load_rank_cache() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_RANK_CACHE_PATH) != OK:
		return
	# Only trust the cache if it belongs to the account that's signed in now.
	if String(cfg.get_value("meta", "uid", "")) != _uid():
		return
	for d in DIFFS:
		var r := int(cfg.get_value("ranks", d, 0))
		if r > 0:
			_rank_cache[d] = r

func reset_session() -> void:
	pass

# Erases every row this account has across all six boards (global/daily x
# easy/moderate/hard), for the account-deletion flow. Rows are keyed by uid,
# so this is a direct delete per collection — no query needed.
func delete_all_my_rows() -> void:
	var my_uid := _uid()
	if my_uid.is_empty():
		return
	if _is_editor:
		for diff in DIFFS:
			# All-time sim rows are keyed by uid; daily sim rows by `{date}__{uid}`,
			# so erase every daily key whose stored uid is mine.
			var g: Dictionary = _sim_global.get(diff, {})
			g.erase(my_uid)
			_sim_global[diff] = g
			var dd: Dictionary = _sim_daily.get(diff, {})
			for key in dd.keys():
				if String((dd[key] as Dictionary).get("uid", key)) == my_uid:
					dd.erase(key)
			_sim_daily[diff] = dd
		return
	for diff in DIFFS:
		# All-time: one row per uid. Read its score first so we can pull this
		# player's count back out of the materialized histogram after deleting.
		var board := "global_" + diff
		var mine := await _rest_get(board, my_uid)
		var my_old := int(mine.get("data", {}).get("score", 0))
		Firebase.firestore.delete_document(board, my_uid)
		await Firebase.firestore.delete_task_completed
		if my_old > 0:
			await _hist_apply(board, {my_old: -1})
		# Legacy daily row from before date-partitioning (keyed by `{uid}`, no
		# `uid` field so the query below can't see it). Harmless no-op if absent.
		var daily_coll := "daily_" + diff
		Firebase.firestore.delete_document(daily_coll, my_uid)
		await Firebase.firestore.delete_task_completed
		# Daily: potentially one row per retained day. Query by the `uid` field
		# (single-field auto-index — no composite needed) and delete each.
		var daily_rows := await _rest_run_query({
			"from": [{"collectionId": daily_coll}],
			"where": {"fieldFilter": {
				"field": {"fieldPath": "uid"},
				"op": "EQUAL",
				"value": {"stringValue": my_uid},
			}},
		})
		for item in daily_rows.get("items", []):
			Firebase.firestore.delete_document(daily_coll, String(item.get("id", "")))
			await Firebase.firestore.delete_task_completed

# A rename only touches existing leaderboard rows — we MUST NOT create empty
# rows for a user just because they picked a name. So for each row we read first
# and only write if it already exists. All-time rows are keyed by uid; for daily
# we update TODAY's row (`{today}__{uid}`) only — past days are historical
# snapshots and their name is cosmetic, so we leave them untouched.
func _on_display_name_changed(new_name: String) -> void:
	var uid := _uid()
	if uid.is_empty() or new_name.is_empty():
		return
	var today := _today_utc()
	if _is_editor:
		for diff in DIFFS:
			var g: Dictionary = _sim_global.get(diff, {})
			if g.has(uid):
				var e: Dictionary = g[uid]
				e["name"] = new_name
				g[uid] = e
				_sim_global[diff] = g
			var dd: Dictionary = _sim_daily.get(diff, {})
			var did := _daily_doc_id(today, uid)
			if dd.has(did):
				var de: Dictionary = dd[did]
				de["name"] = new_name
				dd[did] = de
				_sim_daily[diff] = dd
		return
	for diff in DIFFS:
		for entry in [["global_" + diff, uid], ["daily_" + diff, _daily_doc_id(today, uid)]]:
			var coll: String = entry[0]
			var doc_id: String = entry[1]
			var existing := await _rest_get(coll, doc_id)
			if not bool(existing.get("exists", false)):
				continue
			Firebase.firestore.set_document(coll, doc_id, {"name": new_name}, true)
			await Firebase.firestore.write_task_completed

# ---- REST helpers ----

func _http_get(url: String) -> Array:
	var http := HTTPRequest.new()
	http.timeout = 6.0
	add_child(http)
	# All collections read here have `allow read: if true` in firestore.rules,
	# so no Authorization header is needed.
	if http.request(url) != OK:
		http.queue_free()
		return [0, 0, [], PackedByteArray()]
	var r: Array = await http.request_completed
	http.queue_free()
	return r

# POST helper used by runQuery / runAggregationQuery. Sends application/json
# and returns [result, response_code, headers, body] like _http_get does.
func _http_post(url: String, body: Dictionary) -> Array:
	var http := HTTPRequest.new()
	http.timeout = 6.0
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var json := JSON.stringify(body)
	if http.request(url, headers, HTTPClient.METHOD_POST, json) != OK:
		http.queue_free()
		return [0, 0, [], PackedByteArray()]
	var r: Array = await http.request_completed
	http.queue_free()
	return r

func _rest_get(collection: String, doc_id: String) -> Dictionary:
	var r := await _http_get(_FB_BASE + "/" + collection + "/" + doc_id)
	if r[1] != 200: return {"exists": false}
	var j := JSON.new()
	j.parse((r[3] as PackedByteArray).get_string_from_utf8())
	if not j.data is Dictionary: return {"exists": false}
	return {"exists": true, "data": _fields(j.data.get("fields", {}))}

# Like _rest_get, but distinguishes a definitive 404 (document absent) from a
# network/server failure. Returns {status: "ok"|"missing"|"error", data}. The
# reward path needs this: treating a transient failure as "no row" would stamp a
# day as resolved and skip a reward the player actually earned.
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

# The player uid a returned row belongs to. Daily rows carry an explicit `uid`
# field (their doc id is `{date}__{uid}`, so the id itself is NOT the uid);
# all-time rows are keyed by uid directly and have no `uid` field, so the doc id
# is the fallback. Using this everywhere keeps "is this me?" correct on both.
func _doc_uid(doc: Dictionary) -> String:
	var d: Dictionary = doc.get("data", {})
	return String(d.get("uid", doc.get("id", "")))

# Firestore doc id for a player's daily row on a given UTC date.
func _daily_doc_id(date_str: String, uid: String) -> String:
	return date_str + "__" + uid

# Runs a Firestore structured query. `query` is the body's `structuredQuery`
# object (Firestore REST shape). Returns {ok, items} where each item is
# {id, data}. ok is false only when every retry failed to reach the server.
func _rest_run_query(query: Dictionary) -> Dictionary:
	var body := {"structuredQuery": query}
	for attempt in 3:
		var r := await _http_post(_FB_BASE + ":runQuery", body)
		if r[1] == 200:
			var j := JSON.new()
			j.parse((r[3] as PackedByteArray).get_string_from_utf8())
			# runQuery returns an array of {document?, readTime?} envelopes. The
			# first envelope can be a metadata-only "readTime" record with no
			# `document` key when the query matched zero rows — those are
			# skipped here. Defensive: handle a non-array payload too.
			var out := []
			if j.data is Array:
				for env in j.data:
					if not (env is Dictionary):
						continue
					var doc: Variant = env.get("document", null)
					if not (doc is Dictionary):
						continue
					var parts: PackedStringArray = (doc.get("name", "") as String).split("/")
					out.append({"id": parts[-1], "data": _fields(doc.get("fields", {}))})
			return {"ok": true, "items": out}
		if attempt < 2:
			await get_tree().create_timer(1.0).timeout
	return {"ok": false, "items": []}

# Runs a Firestore aggregation query (count, sum, avg). For our use case it's
# always a single count() with an alias. Returns {ok, value} — value is 0 on a
# soft empty result, but ok=false on hard failure.
func _rest_run_aggregation(query: Dictionary, alias: String) -> Dictionary:
	var body := {
		"structuredAggregationQuery": {
			"aggregations": [{"alias": alias, "count": {}}],
			"structuredQuery": query,
		},
	}
	for attempt in 3:
		var r := await _http_post(_FB_BASE + ":runAggregationQuery", body)
		if r[1] == 200:
			var j := JSON.new()
			j.parse((r[3] as PackedByteArray).get_string_from_utf8())
			# Response shape: [{ result: { aggregateFields: { <alias>: { integerValue: "N" }}}}]
			if j.data is Array and (j.data as Array).size() > 0:
				var env: Variant = (j.data as Array)[0]
				if env is Dictionary:
					var result: Variant = env.get("result", {})
					if result is Dictionary:
						var fields: Variant = result.get("aggregateFields", {})
						if fields is Dictionary:
							var v: Variant = (fields as Dictionary).get(alias, {})
							if v is Dictionary:
								return {"ok": true, "value": int((v as Dictionary).get("integerValue", 0))}
			return {"ok": true, "value": 0}
		if attempt < 2:
			await get_tree().create_timer(1.0).timeout
	return {"ok": false, "value": 0}

func _val(v: Variant) -> Variant:
	if not v is Dictionary: return null
	if v.has("stringValue"):    return v["stringValue"]
	if v.has("integerValue"):   return int(v["integerValue"])
	if v.has("doubleValue"):    return float(v["doubleValue"])
	if v.has("booleanValue"):   return bool(v["booleanValue"])
	if v.has("timestampValue"): return v["timestampValue"]    # ISO string; we don't parse
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
		if v != null: out[k] = v
	return out

# ---- score histogram helpers ----

# Full resource name of one histogram shard, e.g.
# projects/.../documents/board_hist/global_easy_3
func _hist_shard_name(board: String, k: int) -> String:
	return _FB_PROJECT_DOCS + "/" + _HIST_COLL + "/" + board + "_" + str(k)

# Firestore field path for a score bucket. A numeric map key must be backtick-
# quoted in a field path, so score 37 becomes  counts.`37`.
func _hist_field_path(score: int) -> String:
	return "counts.`" + str(score) + "`"

# Apply a set of {score: delta} changes to the board's histogram, atomically, in a
# SINGLE commit to ONE random shard. Server-side `increment` transforms mean
# concurrent writers never clobber; a missing shard/field is created and treated as
# 0. Best-effort and fire-and-forget from the caller's view — a lost increment only
# nudges rank slightly and is healed by rebuild_histograms().
func _hist_apply(board: String, deltas: Dictionary) -> void:
	if _is_editor or deltas.is_empty():
		return
	var k := randi() % HIST_SHARDS
	var transforms: Array = []
	for score in deltas:
		var d := int(deltas[score])
		if d == 0:
			continue
		transforms.append({
			"fieldPath": _hist_field_path(int(score)),
			"increment": {"integerValue": str(d)},
		})
	if transforms.is_empty():
		return
	# update with an EMPTY updateMask writes none of update's own fields (so sibling
	# counts are preserved) while still creating the doc if absent; the transforms
	# then apply. This is exactly what a merge-set of FieldValue.increment compiles
	# to.
	var body := {
		"writes": [{
			"update": {"name": _hist_shard_name(board, k)},
			"updateMask": {"fieldPaths": []},
			"updateTransforms": transforms,
		}],
	}
	await _rest_commit(body)

# The signed-in player's EXACT all-time rank on `board` (1-based) from the
# histogram: 1 + (players whose best score is strictly greater than mine). Reads
# every shard in one batchGet, so the cost is fixed (HIST_SHARDS reads) regardless
# of board size. Returns -1 on a hard read failure so the caller can fall back.
func _hist_rank(board: String, my_score: int) -> int:
	var names: Array = []
	for k in HIST_SHARDS:
		names.append(_hist_shard_name(board, k))
	var shards := await _rest_batch_get(names)
	if not bool(shards.get("ok", false)):
		return -1
	var docs: Array = shards.get("docs", [])
	# No shard exists yet → the histogram hasn't been seeded (pre-backfill rollout,
	# or a brand-new board). Signal a fallback rather than reporting a bogus rank 1
	# for everyone. (After rebuild_histograms(), every shard exists — shard 0 with
	# the tally, the rest as empty {counts:{}} — so this only fires when unseeded.)
	if docs.is_empty():
		return -1
	var above := 0
	for fields in docs:
		var counts: Dictionary = (fields as Dictionary).get("counts", {})
		for key in counts:
			if int(key) > my_score:
				above += int(counts[key])
	return above + 1

# POSTs a Firestore :commit and returns the HTTP status (200 = written). Writes
# are NOT retried here: `increment` is not idempotent, so a retry on an ambiguous
# response could double-count. Callers treat non-200 as best-effort failure.
func _rest_commit(body: Dictionary) -> int:
	var r := await _http_post(_FB_BASE + ":commit", body)
	return int(r[1])

# Batch-reads several documents by full resource name in one request. Returns
# {ok, docs} where docs is the list of decoded field dicts for the ones that
# exist (missing shards are simply skipped). ok=false only on hard failure.
func _rest_batch_get(names: Array) -> Dictionary:
	var body := {"documents": names}
	for attempt in 3:
		var r := await _http_post(_FB_BASE + ":batchGet", body)
		if r[1] == 200:
			var j := JSON.new()
			j.parse((r[3] as PackedByteArray).get_string_from_utf8())
			var out: Array = []
			if j.data is Array:
				for env in j.data:
					if env is Dictionary and (env as Dictionary).has("found"):
						var found: Dictionary = env["found"]
						out.append(_fields(found.get("fields", {})))
			return {"ok": true, "docs": out}
		if attempt < 2:
			await get_tree().create_timer(1.0).timeout
	return {"ok": false, "docs": []}

# ---- histogram backfill / rebuild (run once at rollout, and to heal drift) ----

# Recompute EVERY all-time histogram from the authoritative per-uid rows and
# overwrite the shards. Safe to re-run any time: the rows are the source of truth,
# so this both seeds a fresh deployment and repairs any accumulated drift. Reads
# every row of each board once (a one-off O(rows) admin cost, NOT paid per player
# open). Returns a per-board summary { board: {rows, distinct_scores} }.
# Run it from a device/editor build, e.g. via a debug button:
#   await LeaderboardManager.rebuild_histograms()
func rebuild_histograms() -> Dictionary:
	var summary := {}
	for board in _HIST_BOARDS:
		var res := await _rebuild_one(board)
		var counts: Dictionary = res.get("counts", {})
		var total := 0
		for s in counts:
			total += int(counts[s])
		summary[board] = {
			"rows": total,
			"distinct_scores": counts.size(),
			"write_code": int(res.get("write_code", 0)),  # HTTP status of the commit (200 = ok)
			"write_ok": bool(res.get("write_ok", false)),  # AND the read-back matched
		}
	return summary

func _rebuild_one(board: String) -> Dictionary:
	# 1) Tally {score: count} over every row (paged full scan).
	var counts := {}
	var rows := await _rest_list_all(board)
	for row in rows:
		var sc := int((row as Dictionary).get("score", 0))
		if sc <= 0:
			continue
		counts[sc] = int(counts.get(sc, 0)) + 1
	# 2) Overwrite shard 0 with the full tally and CLEAR the rest, so re-running
	# never double-counts. Reads sum across shards, so one loaded shard is correct.
	var code := await _hist_overwrite_shard(board, 0, counts)
	for k in range(1, HIST_SHARDS):
		await _hist_overwrite_shard(board, k, {})
	# 3) Prove the write actually landed (answers "did the unauthenticated :commit
	# succeed?"): read shard 0 back and confirm its total matches the tally.
	# Firestore single-doc reads are strongly consistent, so this sees the write.
	var want_total := 0
	for s in counts:
		want_total += int(counts[s])
	var back := await _rest_get(_HIST_COLL, board + "_0")
	var back_counts: Dictionary = back.get("data", {}).get("counts", {})
	var back_total := 0
	for s in back_counts:
		back_total += int(back_counts[s])
	var write_ok := code == 200 and back_total == want_total
	return {"counts": counts, "write_code": code, "write_ok": write_ok}

# Replace one shard's document with exactly { counts: <map> } (no updateMask =
# full-document replace). Returns the commit's HTTP status (200 = written).
# Used only by the rebuild path.
func _hist_overwrite_shard(board: String, k: int, counts: Dictionary) -> int:
	var fields := {}
	for score in counts:
		fields[str(int(score))] = {"integerValue": str(int(counts[score]))}
	var body := {
		"writes": [{
			"update": {
				"name": _hist_shard_name(board, k),
				"fields": {"counts": {"mapValue": {"fields": fields}}},
			},
		}],
	}
	return await _rest_commit(body)

# Pages through an entire collection via the REST list endpoint, returning every
# document's decoded fields. Only used by the one-off rebuild, so the full scan is
# acceptable here (and nowhere on the per-open read path).
func _rest_list_all(collection: String) -> Array:
	var out: Array = []
	var page_token := ""
	for _guard in 10000:                       # hard stop against a runaway loop
		var url := _FB_BASE + "/" + collection + "?pageSize=300"
		if not page_token.is_empty():
			url += "&pageToken=" + page_token.uri_encode()
		var r := await _http_get(url)
		if r[1] != 200:
			break
		var j := JSON.new()
		j.parse((r[3] as PackedByteArray).get_string_from_utf8())
		if not j.data is Dictionary:
			break
		for doc in j.data.get("documents", []):
			out.append(_fields((doc as Dictionary).get("fields", {})))
		page_token = String(j.data.get("nextPageToken", ""))
		if page_token.is_empty():
			break
	return out

# ---- date helpers (UTC; one canonical day per real-world day) ----

func _today_utc() -> String:
	var d := Time.get_date_dict_from_system(true)
	return "%04d-%02d-%02d" % [int(d["year"]), int(d["month"]), int(d["day"])]

# Unix timestamp at the next 00:00 UTC after `now_unix`. Used as the basis for
# the expiry stamped on daily rows.
func _next_midnight_utc(now_unix: int) -> int:
	# Each UTC day is exactly 86400s with no DST, so the next midnight is the
	# start of the next day index.
	var day_index := int(floor(float(now_unix) / 86400.0))
	return (day_index + 1) * 86400

# Firestore wire format for an ISO-8601 UTC timestamp field.
func _ts_value(unix_seconds: int) -> Dictionary:
	return {"timestampValue": Time.get_datetime_string_from_unix_time(unix_seconds) + "Z"}

# ---- materialized top-N boards (board_top, server-written) -----------------
# The top-N list is 100% of the fixed board read cost (3 diffs x 20 rows per
# family). A scheduled Cloud Function (functions/index.js) recomputes each
# family's three top-N lists every few minutes and writes them into ONE doc per
# family:
#   board_top/global -> { boards:{ easy:[{uid,name,score}...], moderate:[...],
#                                   hard:[...] }, updated_unix }
#   board_top/daily  -> { date:"YYYY-MM-DD", boards:{...}, updated_unix }
# So a whole family's top lists cost ONE read here instead of 3x20. board_top is
# READ-ONLY for clients in firestore.rules — only the trusted function (Admin
# SDK, which bypasses rules) writes it — so the visible lists can't be forged.
#
# Graceful degradation: if the doc is missing/unreadable (function not deployed
# yet, or a brand-new board) each board transparently falls back to its own
# live top-N query, so behaviour is identical to before the materialization.
const _BOARD_TOP_COLL := "board_top"

# "global" for the all-time family, "daily" for the daily family.
func _family_doc_for(prefix: String) -> String:
	return "daily" if prefix.begins_with("daily") else "global"

# Reads a family's materialized top-N doc and returns { diff: Array<{uid,name,
# score}> }, or {} when it's unavailable / stale (caller then falls back to live
# top-N queries). For daily we require the doc's `date` to match today's — a doc
# left over from before the day flipped is stale and must not paint yesterday's
# board.
func _fetch_family_tops(prefix: String, extra_eq: Dictionary) -> Dictionary:
	if _is_editor:
		return {}
	var res := await _rest_get(_BOARD_TOP_COLL, _family_doc_for(prefix))
	if not bool(res.get("exists", false)):
		return {}
	var data: Dictionary = res.get("data", {})
	if extra_eq.has("date") and String(data.get("date", "")) != String(extra_eq["date"]):
		return {}
	var boards: Variant = data.get("boards", {})
	if not (boards is Dictionary):
		return {}
	return boards as Dictionary

# ---- public API: all-time ----

# Reads the signed-in user's stored all-time score for one difficulty. Returns
# 0 when the user has no row yet, isn't signed in, or the read fails — callers
# (GameState) treat "no row" and "score 0" identically.
func get_my_score(difficulty: String) -> int:
	if _uid().is_empty():
		return 0
	if _is_editor:
		var g: Dictionary = _sim_global.get(difficulty, {})
		return int(g.get(_uid(), {}).get("score", 0))
	var existing := await _rest_get("global_" + difficulty, _uid())
	return int(existing.get("data", {}).get("score", 0))

# Submit a new all-time score. Only writes if it strictly beats the player's
# existing row.
func submit_score(difficulty: String, score: int) -> void:
	if _uid().is_empty(): return
	if _is_editor:
		var g: Dictionary = _sim_global.get(difficulty, {})
		if score > int(g.get(_uid(), {}).get("score", 0)):
			g[_uid()] = {"name": _name(), "score": score}
			_sim_global[difficulty] = g
		return
	var coll := "global_" + difficulty
	var existing := await _rest_get(coll, _uid())
	var old_score := int(existing.get("data", {}).get("score", 0))
	if score <= old_score:
		return
	Firebase.firestore.set_document(coll, _uid(),
		{"name": _name(), "score": score}, true)
	await Firebase.firestore.write_task_completed
	# Keep the materialized histogram in step: this player's best moved from
	# old_score -> score. Move their single count with it (a first-ever row has
	# old_score 0, which was never counted, so only the +1 applies).
	var deltas := {score: 1}
	if old_score > 0:
		deltas[old_score] = int(deltas.get(old_score, 0)) - 1
	await _hist_apply(coll, deltas)

# Submit a new daily score. Rows are keyed per-day (`{today}__{uid}`), so this
# only ever compares against TODAY's own row — no cross-day overwrite handling is
# needed anymore (yesterday is a different document). Writes only if the score
# strictly beats today's existing row.
func submit_score_daily(difficulty: String, score: int) -> void:
	var uid := _uid()
	if uid.is_empty(): return
	if score <= 0: return
	var today := _today_utc()
	var now_u := int(Time.get_unix_time_from_system())
	# Survive the full retention window so a closed day's board is still readable
	# for reward collection right up to the last day of that window.
	var expires_u := _next_midnight_utc(now_u) + _DAILY_RETENTION_DAYS * 86400 + _DAILY_EXPIRES_BUFFER_SECS
	var doc_id := _daily_doc_id(today, uid)
	if _is_editor:
		var g: Dictionary = _sim_daily.get(difficulty, {})
		var existing: Dictionary = g.get(doc_id, {})
		if score <= int(existing.get("score", 0)):
			return
		g[doc_id] = {
			"uid": uid, "name": _name(), "score": score, "date": today,
			"expires_at": _ts_value(expires_u)["timestampValue"],
			"expires_unix": expires_u,
		}
		_sim_daily[difficulty] = g
		return
	var coll := "daily_" + difficulty
	var existing := await _rest_get(coll, doc_id)
	if score <= int(existing.get("data", {}).get("score", 0)):
		return
	# `expires_unix` is the field expiry ACTUALLY keys on. The earlier plan here
	# was to let a Firestore TTL policy read the ISO string in `expires_at`, on
	# the assumption TTL would coerce it — it does not. TTL only ever acts on a
	# field of type Timestamp, and this plugin cannot write one: set_document()
	# hands the dict to the AAR, which marshals a GDScript String to a Java
	# String, so `expires_at` lands as a Firestore string and TTL skips the doc
	# in silence. Every daily row ever written outlived its expiry as a result.
	#
	# An int has no such ambiguity, and firestore.rules can compare it against
	# request.time — so any signed-in client may delete a row once it's past
	# `expires_unix`, and sweep_expired_daily() below does exactly that. The ISO
	# `expires_at` string is still written purely so already-released builds
	# (which validate against it) keep working; nothing reads it.
	Firebase.firestore.set_document(coll, doc_id, {
		"uid": uid, "name": _name(), "score": score, "date": today,
		"expires_at": Time.get_datetime_string_from_unix_time(expires_u) + "Z",
		"expires_unix": expires_u,
	}, true)
	await Firebase.firestore.write_task_completed

# The signed-in player's FINAL rank on a past daily board (1-based), used by the
# reward-collection flow. Returns:
#   >0  the rank
#    0  the player has no row for that day (didn't play) or scored 0
#   -1  the read/aggregation failed (network/server) — caller must NOT treat
#       this as "no reward" and must retry later.
func my_daily_rank_for(difficulty: String, date_str: String) -> int:
	var uid := _uid()
	if uid.is_empty():
		return 0
	if _is_editor:
		return _my_daily_rank_for_sim(difficulty, date_str)
	var coll := "daily_" + difficulty
	var mine := await _rest_get_status(coll, _daily_doc_id(date_str, uid))
	match String(mine.get("status", "error")):
		"missing":
			return 0
		"ok":
			pass
		_:
			return -1
	var d: Dictionary = mine.get("data", {})
	# Defensive: the doc id already pins the date, but confirm the field agrees.
	if String(d.get("date", "")) != date_str:
		return 0
	var my_score := int(d.get("score", 0))
	if my_score <= 0:
		return 0
	var agg := await _rest_run_aggregation(
		_build_score_compare_query(coll, {"date": date_str}, ">", my_score, ""),
		"above_count")
	if not bool(agg.get("ok", false)):
		return -1
	return int(agg.get("value", 0)) + 1

# Editor-sim equivalent of my_daily_rank_for: count sim rows for that date with a
# strictly higher score. Never fails (no network), so it never returns -1.
func _my_daily_rank_for_sim(difficulty: String, date_str: String) -> int:
	var uid := _uid()
	var src: Dictionary = _sim_daily.get(difficulty, {})
	var mine: Dictionary = src.get(_daily_doc_id(date_str, uid), {})
	if String(mine.get("date", "")) != date_str:
		return 0
	var my_score := int(mine.get("score", 0))
	if my_score <= 0:
		return 0
	var above := 0
	for key in src:
		var e: Dictionary = src[key]
		if String(e.get("date", "")) == date_str and int(e.get("score", 0)) > my_score:
			above += 1
	return above + 1

# Loads one all-time board: top 20 + my row + my neighborhood (if I'm outside
# the top 20). Returns the same shape as the daily loader so the screen treats
# them interchangeably.
func load_global(difficulty: String) -> Dictionary:
	var tops := await _fetch_family_tops("global_", {})
	var res := await _load_board("global_" + difficulty, {}, tops.get(difficulty, null))
	if bool(res.get("ok", false)):
		_cache_rank(difficulty, int(res.get("my_rank", 0)))
	return res

# Loads one daily board (filtered to today's date) with the same shape as
# load_global.
func load_daily(difficulty: String) -> Dictionary:
	var today := _today_utc()
	var tops := await _fetch_family_tops("daily_", {"date": today})
	return await _load_board("daily_" + difficulty, {"date": today}, tops.get(difficulty, null))

# Emitted by a worker each time one board finishes, so _load_all can wait for the
# whole batch without awaiting the boards one-at-a-time.
signal _board_loaded

# Loads all three all-time boards at once. Shape: { easy: {...}, moderate: {...},
# hard: {...}, ok: bool }.
func load_all_globals() -> Dictionary:
	return await _load_all("global_", {})

# Loads all three daily boards at once.
func load_all_dailies() -> Dictionary:
	return await _load_all("daily_", {"date": _today_utc()})

# ---- boot warm-up (kills the leaderboards loading screen) ----

# Fetch BOTH families concurrently into the warm cache. Re-runnable: a fresh call
# refetches (used on sign-in). Non-blocking for callers — start it and forget it;
# the screen consumes whatever's ready via take_warm(). Safe to call before the
# player opens the screen.
func warm_boards() -> void:
	if _warming:
		return
	_warming = true
	_warm_ready[RANGE_ALL_KEY] = false
	_warm_ready[RANGE_DAILY_KEY] = false
	var pending := {"left": 2}
	_warm_family(RANGE_ALL_KEY, pending)
	_warm_family(RANGE_DAILY_KEY, pending)
	while pending["left"] > 0:
		await _warm_family_done
	_warming = false
	# Fire-and-forget once the boards the player is waiting on are in hand —
	# garbage collection is never worth delaying the UI for.
	sweep_expired_daily()

# Its own completion signal (NOT _board_loaded, which the inner _load_all loops
# already fan out on — sharing it across the nested concurrent loops would risk a
# missed wake-up).
signal _warm_family_done

# Worker: loads one family into the warm cache. Called WITHOUT await so both
# families load at once.
func _warm_family(range_key: String, pending: Dictionary) -> void:
	var res: Dictionary
	if range_key == RANGE_DAILY_KEY:
		res = await load_all_dailies()
	else:
		res = await load_all_globals()
	if bool(res.get("ok", false)):
		_warm[range_key] = res
		_warm_ready[range_key] = true
	pending["left"] -= 1
	_warm_family_done.emit()

# ---- expiry sweep (client-side GC; Firestore TTL never worked — see rules) ----

# How many expired rows one pass reaps per board. Deletes are one round-trip
# each, so this bounds what a single session contributes in the background. The
# cap doesn't have to keep up with a day's writes on its own: every client that
# opens the app runs a pass, oldest-first, so the backlog drains collectively.
const _SWEEP_LIMIT := 12

# Deletes daily rows whose `expires_unix` has passed. Any signed-in client may
# do this (firestore.rules isExpired), which is the whole point — rows belonging
# to players who never come back would otherwise live forever, since the row's
# own owner is the only other party allowed to remove it.
#
# Rows written by builds that predate `expires_unix` are invisible to this query
# (a Firestore inequality filter skips docs missing the field) and are NOT swept
# here; those are a fixed, non-growing set cleared by a one-off admin purge.
func sweep_expired_daily() -> void:
	if _is_editor or _uid().is_empty():
		return
	var now_u := int(Time.get_unix_time_from_system())
	for diff in DIFFS:
		var coll := "daily_" + diff
		var res := await _rest_run_query({
			"from": [{"collectionId": coll}],
			"where": {"fieldFilter": {
				"field": {"fieldPath": "expires_unix"},
				"op": "LESS_THAN",
				"value": {"integerValue": str(now_u)},
			}},
			# Oldest first, so concurrent sweepers converge on the same head of the
			# backlog and a doc that somehow resists deletion can't hide newer ones.
			"orderBy": [{"field": {"fieldPath": "expires_unix"}, "direction": "ASCENDING"}],
			"limit": _SWEEP_LIMIT,
		})
		if not bool(res.get("ok", false)):
			continue
		for item: Dictionary in res.get("items", []):
			var doc_id := String(item.get("id", ""))
			if doc_id.is_empty():
				continue
			# A racing sweeper may have deleted it already; that just fails the
			# rule check and we move on.
			Firebase.firestore.delete_document(coll, doc_id)
			await Firebase.firestore.delete_task_completed

# The warm-cached families if BOTH are ready, else {}. Shape:
# { all_time: <load_all result>, daily: <load_all result> }. The screen seeds its
# own per-range caches from this to paint instantly without a loading overlay.
func take_warm() -> Dictionary:
	if warm_ready():
		return {RANGE_ALL_KEY: _warm[RANGE_ALL_KEY], RANGE_DAILY_KEY: _warm[RANGE_DAILY_KEY]}
	return {}

# True once BOTH families are in the warm cache, i.e. the leaderboards screen can
# open with no loading overlay. The boot loading screen polls this.
func warm_ready() -> bool:
	return _warm_ready[RANGE_ALL_KEY] and _warm_ready[RANGE_DAILY_KEY]

# True while a warm_boards() pass is in flight (its fetches reset the ready flags,
# so callers must not kick a second pass on top of a live one).
func is_warming() -> bool:
	return _warming

# Loads all three boards of one family CONCURRENTLY. Each _load_board coroutine
# fires its first HTTP request before it suspends, so kicking them all off (without
# awaiting in between) puts every request in flight at once; we then wait for the
# batch via the _board_loaded signal. Cuts the screen-open wait from ~6 serial
# round-trips to ~1.
func _load_all(prefix: String, extra_eq: Dictionary) -> Dictionary:
	# One read of the family's materialized top-N doc supplies all three boards'
	# top lists; each board then only pays for its own my-row/neighborhood, and
	# only when the player sits outside the top. A missing doc leaves tops == {}
	# so each board falls back to its own live top-N query (old behaviour).
	var tops := await _fetch_family_tops(prefix, extra_eq)
	var out := {}
	var pending := {"left": DIFFS.size()}
	for diff in DIFFS:
		_load_board_into(prefix + diff, extra_eq, diff, out, pending, tops.get(diff, null))
	while pending["left"] > 0:
		await _board_loaded
	var ok := true
	for diff in DIFFS:
		if not out[diff].get("ok", false): ok = false
	out["ok"] = ok
	return out

# Worker: loads one board into `out[key]`, then decrements the batch counter and
# signals completion. Called WITHOUT await so the boards run in parallel.
func _load_board_into(collection: String, extra_eq: Dictionary, key: String,
		out: Dictionary, pending: Dictionary, top_rows: Variant = null) -> void:
	var res := await _load_board(collection, extra_eq, top_rows)
	out[key] = res
	# Warm the rank cache off the all-time boards the leaderboards screen loads,
	# so a later profile open shows the rank without waiting on the network.
	if collection.begins_with("global_") and bool(res.get("ok", false)):
		_cache_rank(key, int(res.get("my_rank", 0)))
	pending["left"] -= 1
	_board_loaded.emit()

# Returns:
#   { rows: Array<{uid, name, score, is_me}>,
#     my_row: { uid, name, score } | {},
#     my_rank: int,                    # 0 = not signed in or no row yet
#     neighborhood: Array<{uid, name, score, is_me, rank}>,  # only if my_rank > TOP_N
#     ok: bool }
#
# `extra_eq` is an optional {field: stringValue} equality filter applied to
# every query, used for the daily collections to scope to today's date.
func _load_board(collection: String, extra_eq: Dictionary, top_rows: Variant = null) -> Dictionary:
	if _is_editor:
		return _load_board_sim(collection, extra_eq)

	var my_uid := _uid()
	# For daily boards a row's doc id is `{date}__{uid}`, so my own row lives at
	# that composite id, not at `{uid}`. All-time boards read at `{uid}`.
	var my_doc_id := my_uid
	if extra_eq.has("date"):
		my_doc_id = _daily_doc_id(String(extra_eq["date"]), my_uid)

	# 1) Top N rows. Prefer the pre-fetched materialized list (from board_top —
	# one read for the whole family); when it's absent fall back to a per-board
	# server-ordered top-N query, the real top regardless of board size.
	var rows: Array = []
	if top_rows == null:
		var top := await _rest_run_query(_build_top_query(collection, extra_eq, GLOBAL_TOP_N))
		if not bool(top.get("ok", false)):
			return {"ok": false, "rows": [], "my_row": {}, "my_rank": 0, "neighborhood": []}
		for doc in top.get("items", []):
			var d: Dictionary = doc.get("data", {})
			rows.append({"uid": _doc_uid(doc), "name": d.get("name", "Player"),
				"score": int(d.get("score", 0))})
	else:
		for r in (top_rows as Array):
			var rr: Dictionary = r
			rows.append({"uid": String(rr.get("uid", "")), "name": rr.get("name", "Player"),
				"score": int(rr.get("score", 0))})

	# Tag each top row with whether it belongs to the signed-in player.
	var found_me_in_top := false
	for r in rows:
		var is_me: bool = String(r["uid"]) == my_uid
		r["is_me"] = is_me
		if is_me:
			found_me_in_top = true

	# 2) My row (if signed in). We always look it up so the screen can show
	# "your best today: N" even when the player has zero leaderboard standing.
	var my_row: Dictionary = {}
	var my_rank := 0
	if not my_uid.is_empty():
		if found_me_in_top:
			for i in rows.size():
				if rows[i]["is_me"]:
					my_rank = i + 1
					my_row = {"uid": my_uid, "name": rows[i]["name"], "score": rows[i]["score"]}
					break
		else:
			var existing := await _rest_get(collection, my_doc_id)
			if bool(existing.get("exists", false)):
				var d: Dictionary = existing.get("data", {})
				# For daily, an extra_eq on `date` lets us reject yesterday's
				# stale row (nobody has swept it yet) without showing it.
				var keep := true
				for k in extra_eq:
					if String(d.get(k, "")) != String(extra_eq[k]):
						keep = false
						break
				if keep:
					my_row = {"uid": my_uid, "name": d.get("name", "Player"),
						"score": int(d.get("score", 0))}

	# 3) Neighborhood — only if I have a row AND I'm not already in the top N.
	var neighborhood: Array = []
	if not my_row.is_empty() and not found_me_in_top:
		var my_score := int(my_row.get("score", 0))
		my_rank = await _rank_above(collection, extra_eq, my_score)
		# Above-query is clipped so we never return players who are already in
		# the top-N list (otherwise rank 21–25 would all duplicate the top 20).
		# For a rank-22 player, only 1 above row exists below the top 20; for a
		# rank-100 player, the full NEIGHBOR_COUNT is fine.
		var above_limit: int = mini(NEIGHBOR_COUNT, maxi(0, my_rank - GLOBAL_TOP_N - 1))
		var above_items: Array = []
		if above_limit > 0:
			var above := await _rest_run_query(
				_build_score_compare_query(collection, extra_eq, ">", my_score, "ASCENDING", above_limit))
			above_items = above.get("items", [])
		# 3 immediately below (score < mine, sorted DESC for the same reason).
		var below := await _rest_run_query(
			_build_score_compare_query(collection, extra_eq, "<", my_score, "DESCENDING", NEIGHBOR_COUNT))
		neighborhood = _assemble_neighborhood(my_row, my_rank, above_items, below.get("items", []), my_uid)

	# Trim top to the requested count (server already limited, but be defensive).
	return {
		"ok": true,
		"rows": rows.slice(0, GLOBAL_TOP_N),
		"my_row": my_row,
		"my_rank": my_rank,
		"neighborhood": neighborhood,
	}

# The signed-in player's 1-based rank on `collection` given their score. All-time
# boards resolve this from the score histogram — a FIXED read cost that does not
# grow with the board — falling back to the count() aggregation only if the
# histogram read hard-fails. Daily boards use the aggregation directly (one day's
# field is naturally bounded, so it never scales).
func _rank_above(collection: String, extra_eq: Dictionary, my_score: int) -> int:
	# Both families carry a fixed-cost histogram. All-time board is "global_{diff}";
	# the daily one is PER-DAY, board "daily_{diff}_{date}" (server-maintained by the
	# syncDaily_* trigger). A hard read failure / unseeded histogram (-1) falls back
	# to the exact count() aggregation, so ranks are always correct, just costlier.
	var hist_board := ""
	if collection.begins_with("global_"):
		hist_board = collection
	elif collection.begins_with("daily_") and extra_eq.has("date"):
		hist_board = collection + "_" + String(extra_eq["date"])
	if not hist_board.is_empty():
		var r := await _hist_rank(hist_board, my_score)
		if r > 0:
			return r
	var agg := await _rest_run_aggregation(
		_build_score_compare_query(collection, extra_eq, ">", my_score, ""),
		"above_count")
	return int(agg.get("value", 0)) + 1

# Build a structuredQuery body for "top N by score" with optional equality
# filters layered on top (used for daily's `date == today`).
func _build_top_query(collection: String, extra_eq: Dictionary, limit: int) -> Dictionary:
	var q := {
		"from": [{"collectionId": collection}],
		"orderBy": [{"field": {"fieldPath": "score"}, "direction": "DESCENDING"}],
		"limit": limit,
	}
	if not extra_eq.is_empty():
		q["where"] = _compose_where(extra_eq, "", 0, "")
	return q

# Build a structuredQuery body for "rows where score (op) my_score, ordered by
# score (direction)" with the same optional equality filters. `op` is one of
# Firestore's comparison ops ("GREATER_THAN", "LESS_THAN"). Pass an empty
# direction to skip the orderBy clause (used for the aggregation query — no
# orderBy is required when we only count).
func _build_score_compare_query(collection: String, extra_eq: Dictionary,
		op_symbol: String, my_score: int, direction: String, limit: int = 0) -> Dictionary:
	var firestore_op := "GREATER_THAN" if op_symbol == ">" else "LESS_THAN"
	var q := {
		"from": [{"collectionId": collection}],
		"where": _compose_where(extra_eq, "score", my_score, firestore_op),
	}
	if not direction.is_empty():
		q["orderBy"] = [{"field": {"fieldPath": "score"}, "direction": direction}]
	if limit > 0:
		q["limit"] = limit
	return q

# Build a structuredQuery `where` block combining N equality filters and an
# optional inequality on score. Returns the Firestore REST shape:
# either a single fieldFilter, or a compositeFilter(AND, [...]).
func _compose_where(extra_eq: Dictionary, ineq_field: String, ineq_value: int, ineq_op: String) -> Dictionary:
	var filters: Array = []
	for field in extra_eq:
		filters.append({
			"fieldFilter": {
				"field": {"fieldPath": String(field)},
				"op": "EQUAL",
				"value": {"stringValue": String(extra_eq[field])},
			}
		})
	if not ineq_field.is_empty():
		filters.append({
			"fieldFilter": {
				"field": {"fieldPath": ineq_field},
				"op": ineq_op,
				"value": {"integerValue": str(ineq_value)},
			}
		})
	if filters.size() == 1:
		return filters[0]
	return {"compositeFilter": {"op": "AND", "filters": filters}}

# Stitch the 3-above / 3-below queries + my row into a contiguous neighborhood
# sequence with ranks attached. Server returned: above (ASC by score) is in
# order [closest to me ... furthest above me], below (DESC by score) is in
# order [closest to me ... furthest below me]. We reverse `above` so the
# rendered list reads top -> bottom by rank.
func _assemble_neighborhood(my_row: Dictionary, my_rank: int, above_items: Array,
		below_items: Array, my_uid: String) -> Array:
	var out: Array = []
	var above_ranks_top_to_bottom: Array = []
	for i in above_items.size():
		# i = 0 -> closest above, i = above_items.size() - 1 -> furthest above.
		# So my_rank - 1 is the closest above's rank, my_rank - 2 is next, etc.
		above_ranks_top_to_bottom.append(my_rank - 1 - i)
	# Render top -> bottom: furthest above first.
	for i in range(above_items.size() - 1, -1, -1):
		var doc: Dictionary = above_items[i]
		var d: Dictionary = doc.get("data", {})
		var uid := _doc_uid(doc)
		out.append({
			"uid": uid, "name": d.get("name", "Player"),
			"score": int(d.get("score", 0)),
			"is_me": uid == my_uid,
			"rank": above_ranks_top_to_bottom[i],
		})
	out.append({
		"uid": my_uid, "name": my_row.get("name", "Player"),
		"score": int(my_row.get("score", 0)),
		"is_me": true, "rank": my_rank,
	})
	for i in below_items.size():
		var doc: Dictionary = below_items[i]
		var d: Dictionary = doc.get("data", {})
		var uid := _doc_uid(doc)
		out.append({
			"uid": uid, "name": d.get("name", "Player"),
			"score": int(d.get("score", 0)),
			"is_me": uid == my_uid,
			"rank": my_rank + 1 + i,
		})
	return out

# Editor simulation: same shape as the live path, computed in-memory over
# _sim_global / _sim_daily so the screen + neighborhood UI can be tested off
# device. extra_eq is interpreted as `date == today` for daily collections.
func _load_board_sim(collection: String, extra_eq: Dictionary) -> Dictionary:
	var diff := collection.trim_prefix("global_").trim_prefix("daily_")
	var table := _sim_daily if collection.begins_with("daily_") else _sim_global
	var src: Dictionary = table.get(diff, {})
	var rows_full: Array = []
	for key in src:
		var e: Dictionary = src[key]
		# Daily sim rows are keyed `{date}__{uid}` and carry an explicit `uid`;
		# all-time sim rows are keyed by uid directly (no `uid` field), so the key
		# is the fallback — mirrors _doc_uid on the live path.
		var uid := String(e.get("uid", key))
		# date filter for daily collections.
		var keep := true
		for k in extra_eq:
			if String(e.get(k, "")) != String(extra_eq[k]):
				keep = false
				break
		if not keep:
			continue
		rows_full.append({"uid": uid, "name": e.get("name", "Player"),
			"score": int(e.get("score", 0))})
	rows_full.sort_custom(func(a, b): return a["score"] > b["score"])

	var my_uid := _uid()
	var my_rank := 0
	for i in rows_full.size():
		if rows_full[i]["uid"] == my_uid:
			my_rank = i + 1
			break

	var top: Array = []
	for i in mini(GLOBAL_TOP_N, rows_full.size()):
		var r: Dictionary = rows_full[i].duplicate()
		r["is_me"] = r["uid"] == my_uid
		top.append(r)

	var my_row: Dictionary = {}
	if my_rank > 0:
		my_row = {"uid": my_uid,
			"name": rows_full[my_rank - 1]["name"],
			"score": rows_full[my_rank - 1]["score"]}

	var neighborhood: Array = []
	if my_rank > GLOBAL_TOP_N:
		# Clamp the lower bound to GLOBAL_TOP_N so rank 21–25's "above" rows
		# never overlap the top-N list rendered above the divider. Below stays
		# at NEIGHBOR_COUNT (or whatever's available in the table).
		var lo := maxi(GLOBAL_TOP_N, my_rank - 1 - NEIGHBOR_COUNT)
		var hi := mini(rows_full.size(), my_rank + NEIGHBOR_COUNT)
		for i in range(lo, hi):
			var r: Dictionary = rows_full[i].duplicate()
			r["is_me"] = r["uid"] == my_uid
			r["rank"] = i + 1
			neighborhood.append(r)

	return {
		"ok": true,
		"rows": top,
		"my_row": my_row,
		"my_rank": my_rank,
		"neighborhood": neighborhood,
	}
