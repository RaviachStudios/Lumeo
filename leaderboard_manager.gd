extends Node

# Two parallel leaderboard families, one collection per difficulty:
#   global_{diff}/{uid}   -> { name, score }                            (all-time)
#   daily_{diff}/{uid}    -> { name, score, date, expires_at }          (today)
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

# Buffer added to today's midnight-UTC before writing it as `expires_at`. TTL is
# best-effort within ~24h, but the screen's `date == today` filter is what
# actually hides yesterday's rows — the buffer only matters for storage cost,
# so 6 hours is plenty of slack to keep TTL from racing with a player who is
# active right at the day flip.
const _DAILY_EXPIRES_BUFFER_SECS := 6 * 3600

var _is_editor := OS.get_name() != "Android"
# In-memory sims so the entire flow is testable in the editor without a device.
# Shape mirrors Firestore: collection -> uid -> doc.
var _sim_global := {"easy": {}, "moderate": {}, "hard": {}}
var _sim_daily := {"easy": {}, "moderate": {}, "hard": {}}

func _uid() -> String:  return FirebaseManager.uid
func _name() -> String: return FirebaseManager.display_name

func _ready() -> void:
	FirebaseManager.display_name_changed.connect(_on_display_name_changed)

func reset_session() -> void:
	pass

# A rename only touches existing leaderboard rows — we MUST NOT create empty
# rows for a user just because they picked a name. So for each (collection,
# uid) we read first and only write if the row already exists. We propagate to
# the daily boards too so a same-day rename stays consistent across tabs.
func _on_display_name_changed(new_name: String) -> void:
	var uid := _uid()
	if uid.is_empty() or new_name.is_empty():
		return
	if _is_editor:
		for diff in DIFFS:
			for table in [_sim_global, _sim_daily]:
				var g: Dictionary = table.get(diff, {})
				if g.has(uid):
					var e: Dictionary = g[uid]
					e["name"] = new_name
					g[uid] = e
					table[diff] = g
		return
	for diff in DIFFS:
		for coll in ["global_" + diff, "daily_" + diff]:
			var existing := await _rest_get(coll, uid)
			if not bool(existing.get("exists", false)):
				continue
			Firebase.firestore.set_document(coll, uid, {"name": new_name}, true)
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

# ---- date helpers (UTC; one canonical day per real-world day) ----

func _today_utc() -> String:
	var d := Time.get_date_dict_from_system(true)
	return "%04d-%02d-%02d" % [int(d["year"]), int(d["month"]), int(d["day"])]

# Unix timestamp at the next 00:00 UTC after `now_unix`. Used as the basis for
# `expires_at` on daily rows.
func _next_midnight_utc(now_unix: int) -> int:
	# Each UTC day is exactly 86400s with no DST, so the next midnight is the
	# start of the next day index.
	var day_index := int(floor(float(now_unix) / 86400.0))
	return (day_index + 1) * 86400

# Firestore wire format for an ISO-8601 UTC timestamp field.
func _ts_value(unix_seconds: int) -> Dictionary:
	return {"timestampValue": Time.get_datetime_string_from_unix_time(unix_seconds) + "Z"}

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
	if score <= int(existing.get("data", {}).get("score", 0)):
		return
	Firebase.firestore.set_document(coll, _uid(),
		{"name": _name(), "score": score}, true)
	await Firebase.firestore.write_task_completed

# Submit a new daily score. Only writes if it strictly beats the player's
# existing row FOR TODAY. If the existing row is from a prior day (TTL hasn't
# swept it yet), we overwrite unconditionally — that resets the row to today's
# new score, so the score field stays a real same-day best instead of an
# accidental "yesterday's best counts against today" cap.
func submit_score_daily(difficulty: String, score: int) -> void:
	if _uid().is_empty(): return
	if score <= 0: return
	var today := _today_utc()
	var now_u := int(Time.get_unix_time_from_system())
	var expires_u := _next_midnight_utc(now_u) + _DAILY_EXPIRES_BUFFER_SECS
	if _is_editor:
		var g: Dictionary = _sim_daily.get(difficulty, {})
		var existing: Dictionary = g.get(_uid(), {})
		var existing_today := String(existing.get("date", "")) == today
		var existing_score := int(existing.get("score", 0)) if existing_today else 0
		if score <= existing_score:
			return
		g[_uid()] = {
			"name": _name(), "score": score, "date": today,
			"expires_at": _ts_value(expires_u)["timestampValue"],
		}
		_sim_daily[difficulty] = g
		return
	var coll := "daily_" + difficulty
	var existing := await _rest_get(coll, _uid())
	var d: Dictionary = existing.get("data", {})
	var existing_today := String(d.get("date", "")) == today
	var existing_score := int(d.get("score", 0)) if existing_today else 0
	if score <= existing_score:
		return
	# The plugin marshals GDScript dicts -> Firestore fields, but it doesn't
	# know about the special {timestampValue: ...} wrapper used in REST shape.
	# It DOES understand a plain ISO-8601 string written into a string field,
	# which is what we use here — the field is named expires_at but stored as a
	# Firestore Timestamp when configured via the TTL policy in the console,
	# which accepts ISO strings as timestamps. The TTL policy is what reads it.
	# If the plugin's string mapping turns out to keep this as `stringValue`
	# (and TTL refuses to delete), we'll move this row to a server-side write.
	Firebase.firestore.set_document(coll, _uid(), {
		"name": _name(), "score": score, "date": today,
		"expires_at": Time.get_datetime_string_from_unix_time(expires_u) + "Z",
	}, true)
	await Firebase.firestore.write_task_completed

# Loads one all-time board: top 20 + my row + my neighborhood (if I'm outside
# the top 20). Returns the same shape as the daily loader so the screen treats
# them interchangeably.
func load_global(difficulty: String) -> Dictionary:
	return await _load_board("global_" + difficulty, {})

# Loads one daily board (filtered to today's date) with the same shape as
# load_global.
func load_daily(difficulty: String) -> Dictionary:
	return await _load_board("daily_" + difficulty, {"date": _today_utc()})

# Loads all three all-time boards at once. Shape: { easy: {...}, moderate: {...},
# hard: {...}, ok: bool }.
func load_all_globals() -> Dictionary:
	var out := {}
	var ok := true
	for diff in DIFFS:
		var d := await load_global(diff)
		if not d.get("ok", false): ok = false
		out[diff] = d
	out["ok"] = ok
	return out

# Loads all three daily boards at once.
func load_all_dailies() -> Dictionary:
	var out := {}
	var ok := true
	for diff in DIFFS:
		var d := await load_daily(diff)
		if not d.get("ok", false): ok = false
		out[diff] = d
	out["ok"] = ok
	return out

# Returns:
#   { rows: Array<{uid, name, score, is_me}>,
#     my_row: { uid, name, score } | {},
#     my_rank: int,                    # 0 = not signed in or no row yet
#     neighborhood: Array<{uid, name, score, is_me, rank}>,  # only if my_rank > TOP_N
#     ok: bool }
#
# `extra_eq` is an optional {field: stringValue} equality filter applied to
# every query, used for the daily collections to scope to today's date.
func _load_board(collection: String, extra_eq: Dictionary) -> Dictionary:
	if _is_editor:
		return _load_board_sim(collection, extra_eq)

	# 1) Top N — server-ordered, real top regardless of total board size.
	var top := await _rest_run_query(_build_top_query(collection, extra_eq, GLOBAL_TOP_N))
	if not bool(top.get("ok", false)):
		return {"ok": false, "rows": [], "my_row": {}, "my_rank": 0, "neighborhood": []}

	var rows: Array = []
	var my_uid := _uid()
	var found_me_in_top := false
	for doc in top.get("items", []):
		var d: Dictionary = doc.get("data", {})
		var uid := String(doc.get("id", ""))
		var is_me := uid == my_uid
		if is_me:
			found_me_in_top = true
		rows.append({"uid": uid, "name": d.get("name", "Player"),
			"score": int(d.get("score", 0)), "is_me": is_me})

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
			var existing := await _rest_get(collection, my_uid)
			if bool(existing.get("exists", false)):
				var d: Dictionary = existing.get("data", {})
				# For daily, an extra_eq on `date` lets us reject yesterday's
				# stale row (TTL hasn't swept it yet) without showing it.
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
		# Exact rank via aggregation: "rows above me" + 1.
		var agg := await _rest_run_aggregation(
			_build_score_compare_query(collection, extra_eq, ">", my_score, ""),
			"above_count")
		my_rank = int(agg.get("value", 0)) + 1
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
		var uid := String(doc.get("id", ""))
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
		var uid := String(doc.get("id", ""))
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
	for uid in src:
		var e: Dictionary = src[uid]
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
