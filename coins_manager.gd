extends Node

# Single source of truth for the user's wallet:
#   - coin balance
#   - owned + currently equipped theme (shop background)
#   - display name (mirrored from FirebaseManager so we can propagate renames
#     to the leaderboards even when offline reads aren't available)
#   - login streak: streak_days + first_login_at (timestamp of the streak's
#     day-1 open). The streak is driven by home-screen opens, not by claims.
# All of it lives in one Firestore doc: /users/{uid}. Loaded on sign-in,
# every mutation writes a merge patch back. Editor (non-Android) runs in a
# simulated in-memory store keyed by uid — same pattern as LeaderboardManager.
#
# Per product decision: coins only accumulate for signed-in users. The whole
# wallet is empty / read-only when signed out.

signal balance_changed(new_balance: int)
signal themes_changed
signal daily_claim_changed
signal loaded

const _COLL := "users"

# Theme catalog. "default" is the stock look (no purchased background) and is
# always owned. Adding new shop items is just an entry here + a renderer in
# BackgroundManager.
const DEFAULT_THEME := "default"
const THEMES := {
	"default":  {"name": "Default",  "price": 0,    "category": "themes"},
	"skybound": {"name": "Skybound", "price": 2000, "category": "themes"},
	"inferno":  {"name": "Inferno",  "price": 5000, "category": "themes"},
}

# Daily-claim curve: day 1 = 30, +5 per consecutive day, capped at day 14 = 95.
# Day 15+ jumps to a flat 100 (where the popup also switches to its
# "endless streak" celebratory view — see daily_claim_popup.gd).
const DAILY_REWARD_BASE := 30
const DAILY_REWARD_STEP := 5
const DAILY_REWARD_CAP_DAY := 14
const DAILY_REWARD_ENDLESS := 100

# Per-difficulty per-level award curve. Returns the coins awarded for COMPLETING
# `level` (1-indexed). Hard L5 vs L6 resolved per product clarification: the
# earlier range owns the overlap, so 4–5 → +2, 6 alone → +3.
static func coins_for_level(diff: String, level: int) -> int:
	if level <= 0:
		return 0
	match diff:
		"easy":
			if level <= 5:  return 1
			if level <= 9:  return 2
			if level <= 13: return 3
			if level <= 15: return 4
			return level - 10                    # L16=6, L17=7, …
		"moderate":
			if level <= 3:  return 1
			if level <= 7:  return 2
			if level <= 9:  return 3
			if level <= 12: return 4
			return level - 8                     # L13=5, L14=6, …
		"hard":
			if level <= 3:  return 1
			if level <= 5:  return 2
			if level == 6:  return 3
			if level <= 9:  return 4
			return level - 5                     # L10=5, L11=6, …
		_:
			return 0

# Coin reward for the n-th day of the streak (1-based). Days 1-14 follow the
# growth curve; day 15 onwards is a flat ENDLESS reward forever.
static func daily_reward_for_day(day: int) -> int:
	if day >= DAILY_REWARD_CAP_DAY + 1:
		return DAILY_REWARD_ENDLESS
	var d := clampi(day, 1, DAILY_REWARD_CAP_DAY)
	return DAILY_REWARD_BASE + (d - 1) * DAILY_REWARD_STEP

var _is_editor := OS.get_name() != "Android"
var _sim_db: Dictionary = {}             # editor sim: uid -> doc
var _loaded_for_uid := ""

# --- state (server truth) ---
var balance: int = 0
var owned_themes: Array[String] = [DEFAULT_THEME]
var selected_theme: String = DEFAULT_THEME
var last_claim_date: String = ""         # "YYYY-MM-DD" UTC; "" = never claimed
var streak_days: int = 0                 # consecutive days the user has opened the
                                          # app (1 on the first day, resets to 1 if
                                          # the user misses a calendar day)
var first_login_at: String = ""           # ISO-8601 UTC ("YYYY-MM-DDTHH:MM:SS") of
                                          # the streak's day-1 open. Reset together
                                          # with streak_days whenever a day is missed.
var player_name: String = ""              # mirror of FirebaseManager.display_name.
                                          # Kept on /users so a rename can be pushed
                                          # to leaderboards even when offline.

# --- in-game session ---
var session_earned: int = 0              # cleared in start_game_session()

func _ready() -> void:
	FirebaseManager.signed_in.connect(_on_signed_in)
	FirebaseManager.signed_out.connect(_on_signed_out)
	FirebaseManager.display_name_changed.connect(_on_display_name_changed)
	# Editor sign-in is synchronous (FirebaseManager loads the cached profile),
	# so by the time we autoload here the user may already be signed in.
	if FirebaseManager.is_signed_in():
		call_deferred("_load_user")

func is_loaded() -> bool:
	return not FirebaseManager.uid.is_empty() and _loaded_for_uid == FirebaseManager.uid

# --- game-session API (called by game.gd) ---

func start_game_session() -> void:
	session_earned = 0

# Award coins for completing a level on this difficulty. Returns the amount
# awarded so the caller can drive a "+ N" animation. 0 if not signed in or
# the curve says nothing.
func award_for_level(diff: String, level: int) -> int:
	var amount := coins_for_level(diff, level)
	if amount <= 0 or not FirebaseManager.is_signed_in():
		return 0
	balance += amount
	session_earned += amount
	balance_changed.emit(balance)
	_save_partial({"coins": balance})
	return amount

# --- login-streak + daily-claim API ---

# Call this every time the home screen opens. Idempotent within a single
# calendar day. Advances streak_days by 1 on a new day, resets the streak to
# 1 (and stamps a fresh first_login_at) if any day was missed.
#
# WHY this lives in CoinsManager: streak_days drives both the daily-claim
# reward curve and the popup's "endless streak" view, so the manager that
# already owns the rest of the wallet is the natural home for the timer.
func register_login() -> void:
	if not is_loaded():
		return
	var now_u := int(Time.get_unix_time_from_system())
	# Brand-new user (or wallet doc missing the field): start at day 1.
	if streak_days <= 0 or first_login_at.is_empty():
		first_login_at = _now_iso(now_u)
		streak_days = 1
		_save_partial({"first_login_at": first_login_at, "streak_days": streak_days})
		daily_claim_changed.emit()
		return
	var first_u := int(Time.get_unix_time_from_datetime_string(first_login_at))
	# Bad / unparseable stored value — treat as fresh start to avoid sticking.
	if first_u <= 0:
		first_login_at = _now_iso(now_u)
		streak_days = 1
		_save_partial({"first_login_at": first_login_at, "streak_days": streak_days})
		daily_claim_changed.emit()
		return
	var expected := _utc_days_between(first_u, now_u) + 1
	if expected == streak_days:
		return                                       # same calendar day → no-op
	if expected == streak_days + 1:
		# Next consecutive day — extend the streak, leave first_login_at alone.
		streak_days = expected
		_save_partial({"streak_days": streak_days})
		daily_claim_changed.emit()
		return
	# expected > streak_days + 1 → at least one calendar day was skipped.
	first_login_at = _now_iso(now_u)
	streak_days = 1
	_save_partial({"first_login_at": first_login_at, "streak_days": streak_days})
	daily_claim_changed.emit()

func can_claim_today() -> bool:
	return FirebaseManager.is_signed_in() and last_claim_date != _today()

# What day-number a claim done RIGHT NOW would be (1-based). Mirrors the
# current open-streak — the claim no longer drives the streak itself.
func next_claim_day() -> int:
	return maxi(1, streak_days)

# Returns the amount granted (0 if already claimed today / not signed in).
func claim_daily() -> int:
	if not can_claim_today():
		return 0
	var day := next_claim_day()
	var reward := daily_reward_for_day(day)
	balance += reward
	last_claim_date = _today()
	balance_changed.emit(balance)
	daily_claim_changed.emit()
	_save_partial({
		"coins": balance,
		"last_claim_date": last_claim_date,
	})
	return reward

# --- theme API ---

func owns(theme_id: String) -> bool:
	return owned_themes.has(theme_id)

func theme_price(theme_id: String) -> int:
	return int(THEMES.get(theme_id, {}).get("price", 0))

func can_afford(theme_id: String) -> bool:
	return balance >= theme_price(theme_id)

# Buy a theme. Returns true on success (deducts coins, adds to owned_themes).
func purchase_theme(theme_id: String) -> bool:
	if not FirebaseManager.is_signed_in(): return false
	if not THEMES.has(theme_id): return false
	if owns(theme_id): return false
	var price := theme_price(theme_id)
	if balance < price: return false
	balance -= price
	owned_themes.append(theme_id)
	balance_changed.emit(balance)
	themes_changed.emit()
	_save_partial({"coins": balance, "owned_themes": _owned_themes_map_for_save()})
	return true

# Equip an owned theme. Returns true if the selection actually changed.
func select_theme(theme_id: String) -> bool:
	if not owns(theme_id): return false
	if selected_theme == theme_id: return false
	selected_theme = theme_id
	themes_changed.emit()
	_save_partial({"selected_theme": selected_theme})
	return true

# --- internal: load / save ---

func _on_signed_in(_uid: String, _name: String) -> void:
	_load_user()

func _on_signed_out() -> void:
	balance = 0
	owned_themes = [DEFAULT_THEME]
	selected_theme = DEFAULT_THEME
	last_claim_date = ""
	streak_days = 0
	first_login_at = ""
	player_name = ""
	session_earned = 0
	_loaded_for_uid = ""
	balance_changed.emit(balance)
	themes_changed.emit()
	daily_claim_changed.emit()

# FirebaseManager owns the canonical display name; we mirror it onto /users
# so leaderboards (and any future read-only consumer) can find it cheaply.
func _on_display_name_changed(new_name: String) -> void:
	if not is_loaded():
		return
	if new_name == player_name:
		return
	player_name = new_name
	_save_partial({"name": player_name})

func _load_user() -> void:
	var uid := FirebaseManager.uid
	if uid.is_empty():
		return
	if _is_editor:
		_apply_doc(_sim_db.get(uid, {}))
		_loaded_for_uid = uid
		_emit_all()
		return
	# Reads go through the plugin (NOT REST) because the plugin's auth_success
	# dict does not include an ID token, so REST GETs hit Firestore unauthenticated
	# and the `allow read: if isUser(uid)` rule rejects them. The plugin's
	# get_document inherits the native FirebaseAuth context the same way writes do.
	Firebase.firestore.get_document(_COLL, uid)
	var doc := {}
	# get_task_completed is a shared signal; filter by docID so a future caller
	# can't steal our reply (today only this function reads, but be safe).
	while true:
		var result: Dictionary = await Firebase.firestore.get_task_completed
		if String(result.get("docID", "")) != uid:
			continue
		if bool(result.get("status", false)):
			var d: Variant = result.get("data", {})
			if d is Dictionary:
				doc = d
		break
	_apply_doc(doc)
	_loaded_for_uid = uid
	_emit_all()

func _emit_all() -> void:
	loaded.emit()
	balance_changed.emit(balance)
	themes_changed.emit()
	daily_claim_changed.emit()

func _apply_doc(doc: Dictionary) -> void:
	balance = int(doc.get("coins", 0))
	# "default" is always owned even if the doc somehow omits it.
	owned_themes = [DEFAULT_THEME]
	# owned_themes is stored as a map ({theme_id: true}) — see
	# _owned_themes_map_for_save for why. The Array branch is kept only so a
	# read from a hand-edited Firestore doc still works; nothing in the app
	# writes that shape anymore.
	var raw: Variant = doc.get("owned_themes", {})
	if raw is Dictionary:
		for k in raw.keys():
			var s := String(k)
			if not owned_themes.has(s):
				owned_themes.append(s)
	elif raw is Array:
		for t in raw:
			var s := String(t)
			if not owned_themes.has(s):
				owned_themes.append(s)
	selected_theme = String(doc.get("selected_theme", DEFAULT_THEME))
	if not owned_themes.has(selected_theme):
		selected_theme = DEFAULT_THEME
	last_claim_date = String(doc.get("last_claim_date", ""))
	streak_days = int(doc.get("streak_days", 0))
	first_login_at = String(doc.get("first_login_at", ""))
	player_name = String(doc.get("name", ""))
	# If FirebaseManager already knows a newer name (e.g. user just picked it
	# and the doc on the server hasn't caught up), push the local pick back
	# up so /users stays the canonical mirror.
	var auth_name := FirebaseManager.display_name
	if not auth_name.is_empty() and auth_name != player_name:
		player_name = auth_name
		_save_partial({"name": player_name})

# Owned themes are persisted as a Firestore *map* ({theme_id: true}), not a
# list. WHY: the Firebase Android Firestore SDK (25.1.4) rejects raw Java
# arrays at write time ("Arrays are not supported; use a List instead"),
# and the GodotFirebaseAndroid plugin marshals GDScript Array → Java Object[]
# without converting to java.util.List. Any merge write that included a list
# field silently failed end-to-end — taking the coin delta down with it —
# which is why purchases looked fine in-session but were gone on reopen. A
# Dictionary marshals via Java HashMap, which Firestore accepts. We still
# omit "default" so the stored map stays minimal; _apply_doc re-adds it.
func _owned_themes_map_for_save() -> Dictionary:
	var out := {}
	for t in owned_themes:
		if t != DEFAULT_THEME:
			out[t] = true
	return out

func _save_partial(fields: Dictionary) -> void:
	var uid := FirebaseManager.uid
	if uid.is_empty():
		return
	if _is_editor:
		var d: Dictionary = _sim_db.get(uid, {})
		for k in fields:
			d[k] = fields[k]
		_sim_db[uid] = d
		return
	# merge=true writes only the listed fields, so concurrent updates from
	# different code paths don't clobber each other.
	Firebase.firestore.set_document(_COLL, uid, fields, true)

# --- date helpers (UTC YYYY-MM-DD; one canonical day per real-world day,
#     regardless of the player's local timezone) ---

func _today() -> String:
	var d := Time.get_date_dict_from_system(true)
	return "%04d-%02d-%02d" % [int(d["year"]), int(d["month"]), int(d["day"])]

func _yesterday() -> String:
	var u := int(Time.get_unix_time_from_system()) - 86400
	var d := Time.get_date_dict_from_unix_time(u)
	return "%04d-%02d-%02d" % [int(d["year"]), int(d["month"]), int(d["day"])]

# ISO-8601 UTC string Godot's Time API round-trips with — no timezone suffix
# because get_unix_time_from_datetime_string already treats bare strings as UTC.
func _now_iso(unix_seconds: int) -> String:
	return Time.get_datetime_string_from_unix_time(unix_seconds)

# Number of UTC calendar-day boundaries between two unix timestamps. Using
# floor(t / 86400) collapses each timestamp to its UTC day index, which is
# DST-immune and matches _today() / _yesterday().
func _utc_days_between(a_unix: int, b_unix: int) -> int:
	return int(floor(float(b_unix) / 86400.0)) - int(floor(float(a_unix) / 86400.0))
