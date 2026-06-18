extends Node

# Single Firestore collection per difficulty:
#   global_{diff}/{uid} -> { name, score }

const GLOBAL_TOP_N := 50
const DIFFS: Array[String] = ["easy", "moderate", "hard"]

# Reads go through the Firestore REST API because the plugin's read callbacks
# don't fire reliably on Android. Writes still use the plugin.
const _FB_BASE := "https://firestore.googleapis.com/v1/projects/simon-6bc39/databases/(default)/documents"

var _is_editor := OS.get_name() != "Android"
var _sim_global := {"easy": {}, "moderate": {}, "hard": {}}

func _uid() -> String:  return FirebaseManager.uid
func _name() -> String: return FirebaseManager.display_name

func _ready() -> void:
	FirebaseManager.display_name_changed.connect(_on_display_name_changed)

func reset_session() -> void:
	pass

# A rename only needs to touch existing leaderboard rows — we MUST NOT create
# empty rows (no score) for a user just because they picked a name. So for
# each difficulty we read first, and only write if the row already exists.
func _on_display_name_changed(new_name: String) -> void:
	var uid := _uid()
	if uid.is_empty() or new_name.is_empty():
		return
	if _is_editor:
		for diff in DIFFS:
			var g: Dictionary = _sim_global.get(diff, {})
			if g.has(uid):
				var e: Dictionary = g[uid]
				e["name"] = new_name
				g[uid] = e
				_sim_global[diff] = g
		return
	for diff in DIFFS:
		var coll := "global_" + diff
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

func _rest_get(collection: String, doc_id: String) -> Dictionary:
	var r := await _http_get(_FB_BASE + "/" + collection + "/" + doc_id)
	if r[1] != 200: return {"exists": false}
	var j := JSON.new()
	j.parse((r[3] as PackedByteArray).get_string_from_utf8())
	if not j.data is Dictionary: return {"exists": false}
	return {"exists": true, "data": _fields(j.data.get("fields", {}))}

# Returns { ok, items }. ok is false only when every attempt failed to reach
# the server (HTTP != 200). An empty list with ok == true means "no scores yet".
func _rest_list(collection: String, page_size: int = 300) -> Dictionary:
	for attempt in 3:
		var r := await _http_get(_FB_BASE + "/" + collection + "?pageSize=%d" % page_size)
		if r[1] == 200:
			var j := JSON.new()
			j.parse((r[3] as PackedByteArray).get_string_from_utf8())
			if not j.data is Dictionary: return {"ok": true, "items": []}
			var out := []
			for doc in j.data.get("documents", []):
				var parts: PackedStringArray = (doc.get("name", "") as String).split("/")
				out.append({"id": parts[-1], "data": _fields(doc.get("fields", {}))})
			return {"ok": true, "items": out}
		if attempt < 2:
			await get_tree().create_timer(1.0).timeout
	return {"ok": false, "items": []}

func _val(v: Variant) -> Variant:
	if not v is Dictionary: return null
	if v.has("stringValue"):  return v["stringValue"]
	if v.has("integerValue"): return int(v["integerValue"])
	if v.has("doubleValue"):  return float(v["doubleValue"])
	if v.has("booleanValue"): return bool(v["booleanValue"])
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

# ---- public API ----

# Reads the signed-in user's stored score for one difficulty. Returns 0 when
# the user has no row yet, isn't signed in, or the read fails — callers treat
# "no leaderboard row" and "score 0" identically, so a quiet 0 is the right
# default. Used by GameState to hydrate the in-memory high-score cache.
func get_my_score(difficulty: String) -> int:
	if _uid().is_empty():
		return 0
	if _is_editor:
		var g: Dictionary = _sim_global.get(difficulty, {})
		return int(g.get(_uid(), {}).get("score", 0))
	var existing := await _rest_get("global_" + difficulty, _uid())
	return int(existing.get("data", {}).get("score", 0))

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

# Loads one difficulty and returns { rows, my_rank, total }.
func load_global(difficulty: String) -> Dictionary:
	var rows := []
	var ok := true
	if _is_editor:
		var g: Dictionary = _sim_global.get(difficulty, {})
		for uid in g:
			var e: Dictionary = g[uid]
			rows.append({"uid": uid, "name": e.get("name", "Player"),
				"score": int(e.get("score", 0))})
	else:
		var res := await _rest_list("global_" + difficulty, 300)
		ok = res.get("ok", false)
		for doc in res.get("items", []):
			var d: Dictionary = doc.get("data", {})
			rows.append({"uid": doc.get("id", ""), "name": d.get("name", "Player"),
				"score": int(d.get("score", 0))})
	rows.sort_custom(func(a, b): return a["score"] > b["score"])
	var my_rank := 0
	for i in rows.size():
		rows[i]["is_me"] = rows[i]["uid"] == _uid()
		if rows[i]["is_me"]: my_rank = i + 1
	return {"rows": rows.slice(0, GLOBAL_TOP_N), "my_rank": my_rank,
		"total": rows.size(), "ok": ok}

# Loads all three difficulties at once. Returns { easy: {...}, moderate: {...}, hard: {...} }.
func load_all_globals() -> Dictionary:
	var out := {}
	var ok := true
	for diff in DIFFS:
		var d := await load_global(diff)
		if not d.get("ok", false): ok = false
		out[diff] = d
	out["ok"] = ok
	return out
