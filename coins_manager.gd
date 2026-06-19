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
signal simon_changed
signal levels_changed
signal daily_claim_changed
signal loaded
# Running total of coins earned in the current game session (resets to 0 on
# start_game_session). The in-game HUD tracks this instead of the wallet total.
signal session_earned_changed(session_total: int)

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

# Difficulty unlocks. "easy" is always playable; "moderate" and "hard" are
# locked until bought with coins. A purchase is permanent and persists on
# /users/{uid} as a map (owned_levels: {moderate: true, hard: true}) — same
# storage shape as owned_themes (see _owned_levels_map_for_save).
const LEVEL_PRICES := {
	"moderate": 50,
	"hard": 80,
}

# Simon-wheel customization. Three independently-coloured parts of the wheel
# (the metallic rim rings, the centre hub, and the level numeral), each able to
# equip exactly one colour from a shared catalog. "default" keeps the stock
# graphite/white look and is always owned & free; SimonWheel treats it specially
# (no tint applied), so its catalog `color` below is only a swatch placeholder.
#
# simon_mode chooses whether the game applies these manual per-part colours or a
# complete pre-made skin. It is set implicitly — equipping a colour switches to
# manual; equipping a skin (ships later) will switch to skin — so the shop needs
# no separate mode toggle. Skin storage (selected_skin / owned_skins) exists later.
const SIMON_CATEGORIES := ["outer_circle", "inner_circle", "level_number"]
const SIMON_DEFAULT_COLOR := "default"
const SIMON_MODE_MANUAL := "manual"
const SIMON_MODE_SKIN := "skin"
const SIMON_COLORS := {
	"default":  {"name": "Default",  "price": 0,   "color": Color(0.55, 0.57, 0.62)},
	"crimson":  {"name": "Crimson",  "price": 80,  "color": Color(0.86, 0.16, 0.20)},
	"emerald":  {"name": "Emerald",  "price": 80,  "color": Color(0.13, 0.72, 0.40)},
	"azure":    {"name": "Azure",    "price": 80,  "color": Color(0.20, 0.52, 0.95)},
	"amethyst": {"name": "Amethyst", "price": 80,  "color": Color(0.60, 0.34, 0.92)},
	"amber":    {"name": "Amber",    "price": 80,  "color": Color(0.97, 0.62, 0.13)},
	"rose":     {"name": "Rose",     "price": 80,  "color": Color(0.95, 0.36, 0.62)},
	"silver":   {"name": "Silver",   "price": 200, "color": Color(0.80, 0.82, 0.87)},
	"gold":     {"name": "Gold",     "price": 350, "color": Color(0.95, 0.78, 0.26)},
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
var owned_levels: Array[String] = []     # purchased difficulties; "easy" is implicit
# Simon-wheel customization (see SIMON_* constants):
var simon_mode: String = SIMON_MODE_MANUAL          # manual | skin — set implicitly by what you equip
var equipped_simon: Dictionary = _default_equipped_simon()   # category -> color_id
var owned_simon: Dictionary = _default_owned_simon()         # category -> Array[String]
var selected_skin: String = ""           # equipped complete skin ("" = none yet)
var owned_skins: Array[String] = []      # purchased complete skins (none yet)
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
	session_earned_changed.emit(session_earned)

# Award coins for completing a level on this difficulty. Returns the amount
# awarded so the caller can drive a "+ N" animation. 0 if not signed in or
# the curve says nothing.
#
# The coins only accrue into session_earned here; they are NOT added to the
# persistent wallet until commit_session() runs at game over. This is why a
# quit mid-run (progress lost) grants nothing.
func award_for_level(diff: String, level: int) -> int:
	var amount := coins_for_level(diff, level)
	if amount <= 0 or not FirebaseManager.is_signed_in():
		return 0
	session_earned += amount
	session_earned_changed.emit(session_earned)
	return amount

# Bank the current session's earnings into the persistent balance. Called once
# at game over. session_earned is left intact so the game-over screen can still
# display the amount; it resets on the next start_game_session().
func commit_session() -> void:
	if session_earned <= 0 or not FirebaseManager.is_signed_in():
		return
	balance += session_earned
	balance_changed.emit(balance)
	_save_partial({"coins": balance})

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

# --- simon-customization API ---

func _default_equipped_simon() -> Dictionary:
	var d := {}
	for cat in SIMON_CATEGORIES:
		d[cat] = SIMON_DEFAULT_COLOR
	return d

func _default_owned_simon() -> Dictionary:
	var d := {}
	for cat in SIMON_CATEGORIES:
		d[cat] = [SIMON_DEFAULT_COLOR] as Array[String]
	return d

func is_simon_manual() -> bool:
	return simon_mode == SIMON_MODE_MANUAL

func simon_color_price(color_id: String) -> int:
	return int(SIMON_COLORS.get(color_id, {}).get("price", 0))

# Catalog swatch / in-game tint for a colour. Callers must special-case
# SIMON_DEFAULT_COLOR (the wheel keeps its stock look) — this just returns the
# placeholder swatch colour for it.
func simon_color_value(color_id: String) -> Color:
	return SIMON_COLORS.get(color_id, {}).get("color", Color.GRAY)

func can_afford_simon(color_id: String) -> bool:
	return balance >= simon_color_price(color_id)

func owns_simon_color(category: String, color_id: String) -> bool:
	return owned_simon.get(category, [] as Array[String]).has(color_id)

# The colour currently equipped for a category (a SIMON_COLORS id).
func equipped_simon_color(category: String) -> String:
	return String(equipped_simon.get(category, SIMON_DEFAULT_COLOR))

# Buy a colour for a category. Returns true on success (deducts coins, adds to
# owned_<category>). Mirrors purchase_theme.
func purchase_simon_color(category: String, color_id: String) -> bool:
	if not FirebaseManager.is_signed_in(): return false
	if not SIMON_CATEGORIES.has(category): return false
	if not SIMON_COLORS.has(color_id): return false
	if owns_simon_color(category, color_id): return false
	var price := simon_color_price(color_id)
	if balance < price: return false
	balance -= price
	(owned_simon[category] as Array[String]).append(color_id)
	balance_changed.emit(balance)
	simon_changed.emit()
	_save_partial({"coins": balance, _owned_simon_field(category): _owned_simon_map_for_save(category)})
	return true

# Equip an owned colour for a category. Returns true if the selection changed.
func equip_simon_color(category: String, color_id: String) -> bool:
	if not SIMON_CATEGORIES.has(category): return false
	if not owns_simon_color(category, color_id): return false
	# Equipping a per-part colour IS the act of choosing the manual look, so it
	# implicitly puts the wheel into manual mode — there is no separate toggle.
	var changed := false
	if simon_mode != SIMON_MODE_MANUAL:
		simon_mode = SIMON_MODE_MANUAL
		changed = true
	if equipped_simon_color(category) != color_id:
		equipped_simon[category] = color_id
		changed = true
	if not changed:
		return false
	simon_changed.emit()
	_save_partial({
		"simon_mode": simon_mode,
		_equipped_simon_field(category): color_id,
	})
	return true

# Flip the equip: toggle between manual per-part colours and a complete skin.
func set_simon_mode(mode: String) -> bool:
	if mode != SIMON_MODE_MANUAL and mode != SIMON_MODE_SKIN: return false
	if simon_mode == mode: return false
	simon_mode = mode
	simon_changed.emit()
	_save_partial({"simon_mode": simon_mode})
	return true

# Firestore field names, e.g. "owned_outer_circle" / "equipped_inner_circle".
func _owned_simon_field(category: String) -> String:
	return "owned_" + category

func _equipped_simon_field(category: String) -> String:
	return "equipped_" + category

# Owned colours stored as a Firestore *map* ({color_id: true}), not a list —
# same Android-SDK reasoning as _owned_themes_map_for_save. "default" is omitted
# (re-added on load) so the stored map stays minimal.
func _owned_simon_map_for_save(category: String) -> Dictionary:
	var out := {}
	for c in owned_simon.get(category, [] as Array[String]):
		if c != SIMON_DEFAULT_COLOR:
			out[c] = true
	return out

# --- difficulty-unlock API ---

# Easy is always playable; everything in LEVEL_PRICES needs a purchase first.
func is_level_unlocked(diff: String) -> bool:
	if not LEVEL_PRICES.has(diff):
		return true
	return owned_levels.has(diff)

func level_price(diff: String) -> int:
	return int(LEVEL_PRICES.get(diff, 0))

func can_afford_level(diff: String) -> bool:
	return balance >= level_price(diff)

# Buy a locked difficulty. Returns true on success (deducts coins, unlocks it).
func purchase_level(diff: String) -> bool:
	if not FirebaseManager.is_signed_in(): return false
	if not LEVEL_PRICES.has(diff): return false
	if is_level_unlocked(diff): return false
	var price := level_price(diff)
	if balance < price: return false
	balance -= price
	owned_levels.append(diff)
	balance_changed.emit(balance)
	levels_changed.emit()
	_save_partial({"coins": balance, "owned_levels": _owned_levels_map_for_save()})
	return true

# Same map-not-array reasoning as _owned_themes_map_for_save.
func _owned_levels_map_for_save() -> Dictionary:
	var out := {}
	for d in owned_levels:
		out[d] = true
	return out

# --- internal: load / save ---

func _on_signed_in(_uid: String, _name: String) -> void:
	_load_user()

func _on_signed_out() -> void:
	balance = 0
	owned_themes = [DEFAULT_THEME]
	selected_theme = DEFAULT_THEME
	owned_levels = []
	simon_mode = SIMON_MODE_MANUAL
	equipped_simon = _default_equipped_simon()
	owned_simon = _default_owned_simon()
	selected_skin = ""
	owned_skins = []
	last_claim_date = ""
	streak_days = 0
	first_login_at = ""
	player_name = ""
	session_earned = 0
	_loaded_for_uid = ""
	balance_changed.emit(balance)
	themes_changed.emit()
	simon_changed.emit()
	levels_changed.emit()
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
	simon_changed.emit()
	levels_changed.emit()
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
	# Purchased difficulties — stored as a map ({moderate: true}); the Array
	# branch only covers a hand-edited doc, same as owned_themes.
	owned_levels = []
	var raw_lv: Variant = doc.get("owned_levels", {})
	if raw_lv is Dictionary:
		for k in raw_lv.keys():
			var s := String(k)
			if LEVEL_PRICES.has(s) and not owned_levels.has(s):
				owned_levels.append(s)
	elif raw_lv is Array:
		for t in raw_lv:
			var s := String(t)
			if LEVEL_PRICES.has(s) and not owned_levels.has(s):
				owned_levels.append(s)
	_apply_simon_doc(doc)
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

# Load the Simon-customization fields. Each owned set is stored as a map
# ({color_id: true}); the Array branch only covers a hand-edited doc, same
# tolerance as owned_themes / owned_levels. equipped_<category> is clamped to an
# owned id (falling back to "default" so an equipped colour can never be one the
# player doesn't own).
func _apply_simon_doc(doc: Dictionary) -> void:
	simon_mode = String(doc.get("simon_mode", SIMON_MODE_MANUAL))
	if simon_mode != SIMON_MODE_MANUAL and simon_mode != SIMON_MODE_SKIN:
		simon_mode = SIMON_MODE_MANUAL
	owned_simon = _default_owned_simon()
	equipped_simon = _default_equipped_simon()
	for cat in SIMON_CATEGORIES:
		var owned: Array[String] = owned_simon[cat]
		var raw: Variant = doc.get(_owned_simon_field(cat), {})
		if raw is Dictionary:
			for k in raw.keys():
				var s := String(k)
				if SIMON_COLORS.has(s) and not owned.has(s):
					owned.append(s)
		elif raw is Array:
			for t in raw:
				var s := String(t)
				if SIMON_COLORS.has(s) and not owned.has(s):
					owned.append(s)
		var eq := String(doc.get(_equipped_simon_field(cat), SIMON_DEFAULT_COLOR))
		equipped_simon[cat] = eq if owned.has(eq) else SIMON_DEFAULT_COLOR
	selected_skin = String(doc.get("selected_skin", ""))
	owned_skins = []
	var raw_sk: Variant = doc.get("owned_skins", {})
	if raw_sk is Dictionary:
		for k in raw_sk.keys():
			owned_skins.append(String(k))
	elif raw_sk is Array:
		for t in raw_sk:
			owned_skins.append(String(t))

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
