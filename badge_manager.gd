extends Node

# ─────────────────────────────────────────────────────────────────────────────
# BadgeManager — the achievements/badges system.
#
# STORAGE (space-efficient): every badge the player can earn owns a permanent
# bit index. The whole earned set is one 256-bit field (a 32-byte PackedByteArray)
# base64-encoded to a ~44-char string and stored as the single `badges` field on
# /users/{uid}. 250 badges = 250 bits = 32 bytes on the wire, regardless of how
# many are earned. Bit indices are FROZEN once shipped — never renumber an id, only
# append new ones (we reserve 256 bits so growth needs no migration).
#
# READ: /users/{uid} requires an AUTHENTICATED read (see firestore.rules), and the
# Firebase plugin's auth token isn't exposed to REST — so we do NOT read the doc
# ourselves (a second plugin get_document would also race CoinsManager on the shared
# get_task_completed signal). Instead we piggy-back on CoinsManager, which already
# reads the whole user doc once on sign-in and stashes it as `raw_user_doc`. We pull
# our `badges` field from there when CoinsManager emits `loaded`.
#
# WRITE: fire-and-forget merge write of just {badges: <blob>} — merge=true means it
# never clobbers coins/cosmetics written by CoinsManager (same pattern as
# CoinsManager._save_partial). Awards are rare, so the extra write is cheap.
#
# EARN GESTURE: earning a badge emits `badge_earned(id)`; badge_toast.gd (spawned
# once here) shows a muted card sliding in from the LEFT so it never covers the
# centred Simon wheel nor competes with the Simon tones during a game.
# ─────────────────────────────────────────────────────────────────────────────

const BITS := 256
const BYTES := BITS / 8   # 32

# cat -> accent colour used by badge_icons.gd for the medal backing + toast.
const CAT_COLORS := {
	"onboarding":  Color(0.28, 0.80, 0.82),
	"score":       Color(0.64, 0.46, 0.96),
	"leaderboard": Color(1.00, 0.78, 0.26),
	"arena":       Color(0.96, 0.36, 0.42),
	"shop":        Color(0.96, 0.55, 0.86),
	"economy":     Color(0.98, 0.82, 0.24),
	"streak":      Color(1.00, 0.55, 0.20),
	"volume":      Color(0.38, 0.64, 0.98),
	"fun":         Color(0.74, 0.42, 0.96),
}

# The catalog. `bit` is PERMANENT. `art` selects the emblem in badge_icons.gd.
# Keep ids stable; append new badges with the next free bit.
const BADGES: Array[Dictionary] = [
	# ── Onboarding ──────────────────────────────────────────────────────────
	{"id": "first_game",  "bit": 0,  "cat": "onboarding", "art": "sprout",   "name": "First Steps",      "desc": "Play your very first game."},
	{"id": "signed_in",   "bit": 1,  "cat": "onboarding", "art": "handshake","name": "Welcome Aboard",   "desc": "Sign in to your account."},
	{"id": "named",       "bit": 2,  "cat": "onboarding", "art": "tag",      "name": "Who Am I",         "desc": "Choose your player name."},
	{"id": "tutorial",    "bit": 3,  "cat": "onboarding", "art": "book",     "name": "Quick Study",      "desc": "Finish the How To Play guide."},
	{"id": "first_coins", "bit": 4,  "cat": "onboarding", "art": "coin",     "name": "First Coin",       "desc": "Earn your very first coins."},

	# ── Score / memory (any difficulty) ─────────────────────────────────────
	{"id": "score_5",   "bit": 5,  "cat": "score", "art": "num", "num": 5,  "name": "Warming Up",     "desc": "Reach round 5."},
	{"id": "score_10",  "bit": 6,  "cat": "score", "art": "num", "num": 10, "name": "Sharp Eyes",     "desc": "Reach round 10."},
	{"id": "score_15",  "bit": 7,  "cat": "score", "art": "num", "num": 15, "name": "In The Zone",    "desc": "Reach round 15."},
	{"id": "score_20",  "bit": 8,  "cat": "score", "art": "num", "num": 20, "name": "Steel Trap",     "desc": "Reach round 20."},
	{"id": "score_25",  "bit": 9,  "cat": "score", "art": "num", "num": 25, "name": "Mastermind",     "desc": "Reach round 25."},
	{"id": "score_30",  "bit": 10, "cat": "score", "art": "num", "num": 30, "name": "Photographic",   "desc": "Reach round 30."},
	{"id": "score_40",  "bit": 11, "cat": "score", "art": "num", "num": 40, "name": "Superhuman",     "desc": "Reach round 40."},
	{"id": "score_50",  "bit": 12, "cat": "score", "art": "brain",          "name": "The Impossible", "desc": "Reach round 50."},

	# ── Difficulty-specific ─────────────────────────────────────────────────
	{"id": "easy_20",     "bit": 13, "cat": "score", "art": "leaf",   "name": "Easy Rider",      "desc": "Reach round 20 on Easy."},
	{"id": "mod_15",      "bit": 14, "cat": "score", "art": "spark",  "name": "Middle Ground",   "desc": "Reach round 15 on Moderate."},
	{"id": "mod_25",      "bit": 15, "cat": "score", "art": "spark",  "name": "Moderate Master", "desc": "Reach round 25 on Moderate."},
	{"id": "hard_10",     "bit": 16, "cat": "score", "art": "bolt",   "name": "Hardcore",        "desc": "Reach round 10 on Hard."},
	{"id": "hard_20",     "bit": 17, "cat": "score", "art": "bolt",   "name": "Iron Memory",     "desc": "Reach round 20 on Hard."},
	{"id": "all_diffs",   "bit": 18, "cat": "score", "art": "triangle","name": "Triple Threat",  "desc": "Play Easy, Moderate and Hard."},

	# ── Global / daily leaderboard ──────────────────────────────────────────
	{"id": "lb_top100",   "bit": 19, "cat": "leaderboard", "art": "chart",  "name": "On The Board",     "desc": "Break into the global Top 100."},
	{"id": "lb_top50",    "bit": 20, "cat": "leaderboard", "art": "chart",  "name": "Rising Star",      "desc": "Reach the global Top 50."},
	{"id": "lb_top10",    "bit": 21, "cat": "leaderboard", "art": "medal",  "name": "Elite Ten",        "desc": "Reach the global Top 10."},
	{"id": "lb_top3",     "bit": 22, "cat": "leaderboard", "art": "trophy", "name": "Podium Finish",    "desc": "Reach the global Top 3."},
	{"id": "lb_first",    "bit": 23, "cat": "leaderboard", "art": "crown",  "name": "World Champion",   "desc": "Claim the #1 global spot."},
	{"id": "daily_top10", "bit": 24, "cat": "leaderboard", "art": "sun",    "name": "Daily Grind",      "desc": "Reach the daily Top 10."},
	{"id": "daily_first", "bit": 25, "cat": "leaderboard", "art": "star",   "name": "Player Of The Day","desc": "Top the daily leaderboard."},

	# ── Arena / contests ────────────────────────────────────────────────────
	{"id": "arena_join",   "bit": 26, "cat": "arena", "art": "sword",   "name": "Challenger",      "desc": "Join your first Arena contest."},
	{"id": "arena_host",   "bit": 27, "cat": "arena", "art": "flag",    "name": "Host With Most",  "desc": "Create a contest."},
	{"id": "arena_win",    "bit": 28, "cat": "arena", "art": "trophy",  "name": "Arena Victor",    "desc": "Win a contest."},
	{"id": "arena_win5",   "bit": 29, "cat": "arena", "art": "crown",   "name": "Gladiator",       "desc": "Win 5 contests."},
	{"id": "arena_podium", "bit": 30, "cat": "arena", "art": "medal",   "name": "Contender",       "desc": "Finish top 3 in a contest."},
	{"id": "arena_play10", "bit": 31, "cat": "arena", "art": "swords",  "name": "Regular",         "desc": "Play in 10 contests."},

	# ── Shop / cosmetics ────────────────────────────────────────────────────
	{"id": "first_theme",  "bit": 32, "cat": "shop", "art": "palette", "name": "Fresh Look",     "desc": "Buy your first theme."},
	{"id": "themes_5",     "bit": 33, "cat": "shop", "art": "palette", "name": "Collector",      "desc": "Own 5 themes."},
	{"id": "themes_all",   "bit": 34, "cat": "shop", "art": "gem",     "name": "Completionist",  "desc": "Own every theme."},
	{"id": "first_skin",   "bit": 35, "cat": "shop", "art": "wheel",   "name": "Skinned",        "desc": "Buy a Special Skin."},
	{"id": "skins_all",    "bit": 36, "cat": "shop", "art": "diamond", "name": "Skin Deep",      "desc": "Own every Special Skin."},
	{"id": "unlock_diff",  "bit": 37, "cat": "shop", "art": "key",     "name": "Level Up",       "desc": "Unlock a harder difficulty."},

	# ── Economy / coins ─────────────────────────────────────────────────────
	{"id": "coins_1k",     "bit": 38, "cat": "economy", "art": "coin",    "name": "Pocket Change", "desc": "Hold 1,000 coins."},
	{"id": "coins_10k",    "bit": 39, "cat": "economy", "art": "coins",   "name": "Money Bags",    "desc": "Hold 10,000 coins."},
	{"id": "coins_50k",    "bit": 40, "cat": "economy", "art": "chest",   "name": "High Roller",   "desc": "Hold 50,000 coins."},
	{"id": "earned_10k",   "bit": 41, "cat": "economy", "art": "coins",   "name": "Grinder",       "desc": "Earn 10,000 coins in total."},
	{"id": "earned_100k",  "bit": 42, "cat": "economy", "art": "chest",   "name": "Tycoon",        "desc": "Earn 100,000 coins in total."},
	{"id": "remove_ads",   "bit": 43, "cat": "economy", "art": "shield",  "name": "Ad-Free",       "desc": "Unlock Remove Ads."},

	# ── Streak / daily ──────────────────────────────────────────────────────
	{"id": "claim_first",  "bit": 44, "cat": "streak", "art": "gift",     "name": "Daily Bonus",   "desc": "Claim your first daily reward."},
	{"id": "streak_3",     "bit": 45, "cat": "streak", "art": "calendar", "name": "Habit Forming", "desc": "Reach a 3-day streak."},
	{"id": "streak_7",     "bit": 46, "cat": "streak", "art": "calendar", "name": "Week Warrior",  "desc": "Reach a 7-day streak."},
	{"id": "streak_14",    "bit": 47, "cat": "streak", "art": "flame",    "name": "Fortnight",     "desc": "Reach a 14-day streak."},
	{"id": "streak_30",    "bit": 48, "cat": "streak", "art": "flame",    "name": "Unstoppable",   "desc": "Reach a 30-day streak."},

	# ── Play volume (lifetime, tracked locally) ─────────────────────────────
	{"id": "games_10",     "bit": 49, "cat": "volume", "art": "controller", "name": "Getting Started", "desc": "Play 10 games."},
	{"id": "games_50",     "bit": 50, "cat": "volume", "art": "controller", "name": "Dedicated",       "desc": "Play 50 games."},
	{"id": "games_100",    "bit": 51, "cat": "volume", "art": "rocket",     "name": "Centurion",       "desc": "Play 100 games."},
	{"id": "games_500",    "bit": 52, "cat": "volume", "art": "rocket",     "name": "Marathoner",      "desc": "Play 500 games."},

	# ── Fun / secret ────────────────────────────────────────────────────────
	{"id": "night_owl",    "bit": 53, "cat": "fun", "art": "moon",  "name": "Night Owl",       "desc": "Play between midnight and 4 AM."},
	{"id": "early_bird",   "bit": 54, "cat": "fun", "art": "sun",   "name": "Early Bird",      "desc": "Play between 4 and 6 AM."},
	{"id": "badge_master", "bit": 55, "cat": "fun", "art": "star",  "name": "Simon Says Master","desc": "Earn 40 badges."},
]

signal badge_earned(id: String)
signal badges_changed

# 32-byte earned bitfield.
var _bits := PackedByteArray()
var _by_id: Dictionary = {}     # id -> badge dict
var _by_bit: Dictionary = {}    # bit -> badge dict
var _loaded := false
var _is_editor := OS.get_name() != "Android"
# Writes are COALESCED + DEFERRED: many awards in one frame produce a single
# set_document on the next idle frame, and nothing writes before `loaded` (so a
# write can never race CoinsManager's login read on the shared plugin signal).
var _dirty := false
var _flush_queued := false

# Local progress counters that gate multi-event badges. Earned BITS are the source
# of truth (server-persisted); these counters are just local progress helpers, so a
# device-local ConfigFile is fine (matches how the game treats guest state).
const STATS_PATH := "user://badge_stats.cfg"
var _games_played := 0
var _contests_played := 0
var _contests_won := 0
var _diffs_played := {}          # difficulty -> true

func _ready() -> void:
	_bits.resize(BYTES)
	for b in BADGES:
		_by_id[b["id"]] = b
		_by_bit[int(b["bit"])] = b
	_load_stats()
	# Piggy-back on CoinsManager's single authenticated read of /users/{uid}.
	CoinsManager.loaded.connect(_on_user_loaded)
	FirebaseManager.signed_out.connect(_on_signed_out)
	# NOTE: we deliberately do NOT award on FirebaseManager.signed_in — that fires
	# WHILE CoinsManager's get_document read of /users/{uid} is still in flight, and a
	# concurrent plugin write would jam the shared task signal (skill rules 20-22),
	# corrupting the wallet read (coins appear reset, purchases fail). All awards wait
	# for `loaded` (read complete). The "signed_in" badge is granted in _on_user_loaded.
	FirebaseManager.display_name_changed.connect(func(n: String) -> void:
		if not n.is_empty(): note_named())
	# Re-evaluate inventory-driven badges whenever the wallet/cosmetics change.
	CoinsManager.balance_changed.connect(func(_v: int) -> void: _eval_economy())
	CoinsManager.themes_changed.connect(_eval_inventory)
	CoinsManager.simon_changed.connect(_eval_inventory)
	CoinsManager.levels_changed.connect(_eval_inventory)
	CoinsManager.remove_ads_changed.connect(func() -> void: _eval_inventory())
	# Only sync if CoinsManager has GENUINELY loaded already (doc present). Never sync
	# off mere is_signed_in — the read may still be in flight (see note above).
	if CoinsManager.raw_user_doc.size() > 0:
		_on_user_loaded()
	# Spawn the earn-gesture overlay (deferred so the scene root exists).
	call_deferred("_ensure_toast")

# ─── public queries ─────────────────────────────────────────────────────────

func has_badge(id: String) -> bool:
	var b: Variant = _by_id.get(id, null)
	if b == null:
		return false
	return _is_bit(int((b as Dictionary)["bit"]))

func earned_count() -> int:
	var n := 0
	for i in BITS:
		if _is_bit(i):
			n += 1
	return n

func total_count() -> int:
	return BADGES.size()

func badge(id: String) -> Dictionary:
	return _by_id.get(id, {})

func cat_color(cat: String) -> Color:
	return CAT_COLORS.get(cat, Color(0.6, 0.6, 0.7))

# ─── awarding ───────────────────────────────────────────────────────────────

# Grant a badge by id. No-op if unknown or already earned. Persists + notifies.
func award(id: String) -> void:
	var b: Variant = _by_id.get(id, null)
	if b == null:
		return
	var bit := int((b as Dictionary)["bit"])
	if _is_bit(bit):
		return
	_set_bit(bit)
	_mark_dirty()
	badge_earned.emit(id)
	badges_changed.emit()
	# Meta badge: earning any badge may push us over the 40-badge line.
	if id != "badge_master" and earned_count() >= 40:
		award("badge_master")

# ─── evaluation hooks (called from game systems; each stays a thin one-liner
#     on the caller side — all thresholds live here) ──────────────────────────

func note_signed_in() -> void:
	award("signed_in")

func note_named() -> void:
	award("named")

func note_tutorial_done() -> void:
	award("tutorial")

func note_daily_claimed(streak_days: int) -> void:
	award("claim_first")
	if streak_days >= 3:  award("streak_3")
	if streak_days >= 7:  award("streak_7")
	if streak_days >= 14: award("streak_14")
	if streak_days >= 30: award("streak_30")

func note_game_played(difficulty: String) -> void:
	award("first_game")
	_games_played += 1
	if not _diffs_played.has(difficulty):
		_diffs_played[difficulty] = true
	_save_stats()
	if _games_played >= 10:  award("games_10")
	if _games_played >= 50:  award("games_50")
	if _games_played >= 100: award("games_100")
	if _games_played >= 500: award("games_500")
	if _diffs_played.has("easy") and _diffs_played.has("moderate") and _diffs_played.has("hard"):
		award("all_diffs")
	# Time-of-day secrets (local clock).
	var h := int(Time.get_time_dict_from_system(false).get("hour", 12))
	if h >= 0 and h < 4:
		award("night_owl")
	elif h >= 4 and h < 6:
		award("early_bird")

func note_score(difficulty: String, rounds: int) -> void:
	if rounds >= 5:  award("score_5")
	if rounds >= 10: award("score_10")
	if rounds >= 15: award("score_15")
	if rounds >= 20: award("score_20")
	if rounds >= 25: award("score_25")
	if rounds >= 30: award("score_30")
	if rounds >= 40: award("score_40")
	if rounds >= 50: award("score_50")
	match difficulty:
		"easy":
			if rounds >= 20: award("easy_20")
		"moderate":
			if rounds >= 15: award("mod_15")
			if rounds >= 25: award("mod_25")
		"hard":
			if rounds >= 10: award("hard_10")
			if rounds >= 20: award("hard_20")

# rank: 1-based global position (0 = unranked). daily: this was the daily board.
func note_rank(rank: int, daily: bool) -> void:
	if rank <= 0:
		return
	if daily:
		if rank <= 10: award("daily_top10")
		if rank == 1:  award("daily_first")
		return
	if rank <= 100: award("lb_top100")
	if rank <= 50:  award("lb_top50")
	if rank <= 10:  award("lb_top10")
	if rank <= 3:   award("lb_top3")
	if rank == 1:   award("lb_first")

func note_contest_joined() -> void:
	award("arena_join")
	_contests_played += 1
	_save_stats()
	if _contests_played >= 10:
		award("arena_play10")

func note_contest_hosted() -> void:
	award("arena_host")

# rank: 1-based finishing position in the contest (0 = unknown).
func note_contest_result(rank: int) -> void:
	if rank == 1:
		award("arena_win")
		_contests_won += 1
		_save_stats()
		if _contests_won >= 5:
			award("arena_win5")
	if rank >= 1 and rank <= 3:
		award("arena_podium")

# ─── inventory / economy re-evaluation ──────────────────────────────────────

func _eval_inventory() -> void:
	# Themes.
	var owned_themes: int = 0
	for t in CoinsManager.owned_themes:
		if String(t) != CoinsManager.DEFAULT_THEME:
			owned_themes += 1
	if owned_themes >= 1: award("first_theme")
	if owned_themes >= 5: award("themes_5")
	if _owns_all_themes(): award("themes_all")
	# Skins.
	var owned_skins := 0
	var total_skins := 0
	for sid in CoinsManager.SIMON_SKINS.keys():
		total_skins += 1
		if CoinsManager.owns_skin(String(sid)):
			owned_skins += 1
	if owned_skins >= 1: award("first_skin")
	if total_skins > 0 and owned_skins >= total_skins: award("skins_all")
	# Difficulty unlocks (moderate/hard purchased).
	if CoinsManager.owned_levels.size() >= 1:
		award("unlock_diff")
	# Remove ads.
	if CoinsManager.has_remove_ads:
		award("remove_ads")
	_eval_economy()

func _eval_economy() -> void:
	var bal: int = CoinsManager.balance
	if bal >= 1000:  award("coins_1k")
	if bal >= 10000: award("coins_10k")
	if bal >= 50000: award("coins_50k")
	if bal > 0:      award("first_coins")
	var earned: int = CoinsManager.earned_coins
	if earned >= 10000:  award("earned_10k")
	if earned >= 100000: award("earned_100k")

func _owns_all_themes() -> bool:
	for k in CoinsManager.THEMES.keys():
		if String(k) == CoinsManager.DEFAULT_THEME:
			continue
		if not CoinsManager.owned_themes.has(String(k)):
			return false
	return true

# ─── persistence ────────────────────────────────────────────────────────────

func _on_user_loaded() -> void:
	_loaded = true
	var blob := String(CoinsManager.raw_user_doc.get("badges", ""))
	_decode(blob)
	# Now that the wallet read is complete it's safe to award. Grant the sign-in
	# badge here (NOT on the signed_in signal — that races the read) and reconcile
	# inventory/economy badges the player may already qualify for. Any resulting
	# writes are coalesced into one deferred set_document (see _mark_dirty), which
	# runs on a later idle frame — never concurrent with the read.
	if FirebaseManager.is_signed_in() and FirebaseManager.has_display_name():
		award("signed_in")
	_eval_inventory()
	badges_changed.emit()

func _on_signed_out() -> void:
	_loaded = false
	_bits = PackedByteArray()
	_bits.resize(BYTES)
	badges_changed.emit()

func _decode(blob: String) -> void:
	_bits = PackedByteArray()
	_bits.resize(BYTES)
	if blob.is_empty():
		return
	var raw := Marshalls.base64_to_raw(blob)
	for i in mini(raw.size(), BYTES):
		_bits[i] = raw[i]

func _encode() -> String:
	return Marshalls.raw_to_base64(_bits)

# Mark the bitfield changed and schedule ONE deferred write. Coalesces a burst of
# awards (e.g. the login reconciliation) into a single set_document, and never
# writes until `loaded` (so it can't race the login read on the shared signal).
func _mark_dirty() -> void:
	_dirty = true
	if _loaded and not _flush_queued:
		_flush_queued = true
		_flush_saves.call_deferred()

func _flush_saves() -> void:
	_flush_queued = false
	if not _dirty:
		return
	_dirty = false
	if not FirebaseManager.is_signed_in():
		return
	var uid := FirebaseManager.uid
	if uid.is_empty():
		return
	# Keep CoinsManager's cached doc coherent so a same-session re-eval sees it.
	CoinsManager.raw_user_doc["badges"] = _encode()
	if _is_editor:
		return
	# merge=true → writes only `badges`, never clobbers coins/cosmetics.
	Firebase.firestore.set_document("users", uid, {"badges": _encode()}, true)

# ─── bit helpers ────────────────────────────────────────────────────────────

func _is_bit(bit: int) -> bool:
	if bit < 0 or bit >= BITS:
		return false
	return (_bits[bit >> 3] & (1 << (bit & 7))) != 0

func _set_bit(bit: int) -> void:
	if bit < 0 or bit >= BITS:
		return
	_bits[bit >> 3] = _bits[bit >> 3] | (1 << (bit & 7))

# ─── local stats file ───────────────────────────────────────────────────────

func _load_stats() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(STATS_PATH) != OK:
		return
	_games_played = int(cfg.get_value("stats", "games_played", 0))
	_contests_played = int(cfg.get_value("stats", "contests_played", 0))
	_contests_won = int(cfg.get_value("stats", "contests_won", 0))
	var diffs: Variant = cfg.get_value("stats", "diffs", [])
	if diffs is Array:
		for d in diffs:
			_diffs_played[String(d)] = true

func _save_stats() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("stats", "games_played", _games_played)
	cfg.set_value("stats", "contests_played", _contests_played)
	cfg.set_value("stats", "contests_won", _contests_won)
	cfg.set_value("stats", "diffs", _diffs_played.keys())
	cfg.save(STATS_PATH)

# ─── earn-gesture overlay ───────────────────────────────────────────────────

const BadgeToast := preload("res://badge_toast.gd")
var _toast: Node

func _ensure_toast() -> void:
	if _toast != null and is_instance_valid(_toast):
		return
	_toast = BadgeToast.new()
	get_tree().root.add_child(_toast)
