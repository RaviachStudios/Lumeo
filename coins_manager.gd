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
signal remove_ads_changed
signal loaded
# Running total of coins earned in the current game session (resets to 0 on
# start_game_session). The in-game HUD tracks this instead of the wallet total.
signal session_earned_changed(session_total: int)
# Emitted when the daily-standing reward for one or more just-closed days is
# granted on login. `results` is Array<{diff, rank, reward}> for the popup;
# `total` is the summed coins. Only emitted when total > 0.
signal daily_rank_reward_granted(total: int, results: Array)

const _COLL := "users"

# ---- leaderboard reward tables ----------------------------------------------
# See LEADERBOARD_REWARDS_PLAN.md. Two independent systems:
#   * All-time: paid once per rank BAND per difficulty, the first time you reach
#     it (band improvement only). Keyed by band index (1 = best).
#   * Daily: paid on first login after a day closes, for your final standing.

# Band index -> coins, for the all-time board. Band index comes from
# _alltime_band_index(rank); 0 means "outside top 50" (no reward).
const ALLTIME_BAND_REWARDS := {1: 1000, 2: 750, 3: 500, 4: 350, 5: 250, 6: 150}

# How many days back a login will look for an uncollected daily reward. Must not
# exceed LeaderboardManager._DAILY_RETENTION_DAYS (rows older than that are gone).
const DAILY_RANK_WINDOW_DAYS := 14

# Theme catalog. "default" is the stock look (no purchased background) and is
# always owned. Adding new shop items is just an entry here + a renderer in
# BackgroundManager.
const DEFAULT_THEME := "default"
# Ordered by price, ascending (mirrors the THEMES tab's display order — see
# CATEGORIES["items"] in shop_screen.gd, which is the actual source of shop order).
const THEMES := {
	"default":  {"name": "Default",  "price": 0,    "category": "themes"},
	"midnight": {"name": "Midnight", "price": 80,   "category": "themes"},
	"indigo":   {"name": "Indigo",   "price": 80,   "category": "themes"},
	"sunset":   {"name": "Sunset",   "price": 80,   "category": "themes"},
	"crimson":  {"name": "Crimson",  "price": 80,   "category": "themes"},
	"slate":    {"name": "Slate",    "price": 80,   "category": "themes"},
	"skybound": {"name": "Skybound", "price": 80,   "category": "themes"},
	"forest":   {"name": "Enchanted Forest",  "price": 350, "category": "themes"},
	"desert":   {"name": "Wild West",         "price": 350, "category": "themes"},
	"clouds":   {"name": "Dreamy Clouds",     "price": 400, "category": "themes"},
	"speedway": {"name": "Speedway",          "price": 450, "category": "themes"},
	"kitty":    {"name": "Neko Pop",          "price": 550, "category": "themes"},
	"rainbow":  {"name": "Rainbow",           "price": 600, "category": "themes"},
	"neon":     {"name": "Neon City",         "price": 800, "category": "themes"},
	"castle":   {"name": "Dragon's Keep",     "price": 900, "category": "themes"},
	"inferno":  {"name": "Inferno",           "price": 1000, "category": "themes"},
	"fairies":  {"name": "Enchanted Fairies", "price": 1000, "category": "themes"},
	"aurora":   {"name": "Northern Lights",   "price": 1050, "category": "themes"},
	"reef":     {"name": "Coral Reef",        "price": 1200, "category": "themes"},
	"deepspace":{"name": "Deep Space",        "price": 1600, "category": "themes"},
}

# Difficulty unlocks. Every difficulty is free to play — this is the set of
# difficulties still behind a coin price, and is_level_unlocked treats anything
# absent from it as playable, so an empty dict means "all unlocked". Moderate
# and Hard used to cost 10/20; the machinery (price badge, buy popup,
# purchase_level) stays so a difficulty can be re-priced by adding one line
# here. Purchases persist on /users/{uid} as a map (owned_levels:
# {moderate: true}) — same storage shape as owned_themes.
const LEVEL_PRICES := {}

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
	"silver":   {"name": "Silver",   "price": 110, "color": Color(0.80, 0.82, 0.87)},
	"gold":     {"name": "Gold",     "price": 130, "color": Color(0.95, 0.78, 0.26)},
}

# Patterned OUTER-RING styles (no flat colour — the rim wears a repeating pattern).
# `pattern` is a small int shared verbatim by SimonWheel's _STYLE_SHADER (3D wheel)
# and SimonPartIcon (2D shop swatch); `color`/`color2` are the two pattern inks.
# Rim pattern codes: 1 zebra · 2 rainbow · 3 dots · 4 candy · 5 checker ·
#                    6 tiger · 7 leopard · 8 gradient · 9 stars · 10 wave
const SIMON_OUTER_PATTERNS := {
	"pinkdots": {"name": "Pink Dots",   "price": 150, "pattern": 3,  "color": Color(0.96, 0.45, 0.72), "color2": Color(1.0, 1.0, 1.0)},
	"zebra":    {"name": "Zebra",       "price": 180, "pattern": 1,  "color": Color(0.08, 0.08, 0.10), "color2": Color(0.96, 0.96, 0.98)},
	"candy":    {"name": "Candy Cane",  "price": 200, "pattern": 4,  "color": Color(0.90, 0.16, 0.22), "color2": Color(1.0, 0.98, 0.98)},
	"tiger":    {"name": "Tiger",       "price": 220, "pattern": 6,  "color": Color(0.98, 0.55, 0.10), "color2": Color(0.08, 0.06, 0.05)},
	"sunset":   {"name": "Sunset",      "price": 240, "pattern": 8,  "color": Color(1.0, 0.48, 0.32),  "color2": Color(0.95, 0.30, 0.66)},
	"leopard":  {"name": "Leopard",     "price": 250, "pattern": 7,  "color": Color(0.87, 0.66, 0.34), "color2": Color(0.32, 0.18, 0.07)},
	"ocean":    {"name": "Ocean Wave",  "price": 260, "pattern": 10, "color": Color(0.10, 0.52, 0.80), "color2": Color(0.58, 0.90, 0.96)},
	"prism":    {"name": "Rainbow",     "price": 300, "pattern": 2,  "color": Color(1, 0, 0),          "color2": Color(1, 1, 1)},
	"starry":   {"name": "Starry Night","price": 300, "pattern": 9,  "color": Color(0.09, 0.12, 0.34), "color2": Color(1.0, 0.95, 0.72)},
}

# Drawn CENTER-HUB styles — a motif rendered on the hub disc. Same `pattern`/
# `color`/`color2` contract as SIMON_OUTER_PATTERNS, with codes in the 20s/30s.
# Hub motif codes: 21 star · 22 flower · 23 smiley · 24 dots · 25 paw ·
#                  26 target · 27 swirl · 28 rainbow · 30 crescent · 31 diamond ·
#                  32 clover · 33 bolt · 34 yin-yang · 35 music note
const SIMON_INNER_MOTIFS := {
	"bubbles":  {"name": "Bubbles",     "price": 150, "pattern": 24, "color": Color(0.56, 0.40, 0.92), "color2": Color(1.0, 1.0, 1.0)},
	"target":   {"name": "Bullseye",    "price": 160, "pattern": 26, "color": Color(0.90, 0.24, 0.28), "color2": Color(1.0, 1.0, 1.0)},
	"star":     {"name": "Gold Star",   "price": 180, "pattern": 21, "color": Color(0.20, 0.24, 0.46), "color2": Color(1.0, 0.84, 0.30)},
	"smiley":   {"name": "Smiley",      "price": 200, "pattern": 23, "color": Color(1.0, 0.82, 0.24),  "color2": Color(0.14, 0.10, 0.04)},
	"paw":      {"name": "Paw Print",   "price": 200, "pattern": 25, "color": Color(0.98, 0.70, 0.80), "color2": Color(0.55, 0.28, 0.36)},
	"bolt":     {"name": "Lightning",   "price": 200, "pattern": 33, "color": Color(0.16, 0.14, 0.30), "color2": Color(1.0, 0.86, 0.24)},
	"swirl":    {"name": "Swirl",       "price": 220, "pattern": 27, "color": Color(0.16, 0.78, 0.74), "color2": Color(1.0, 1.0, 1.0)},
	"crescent": {"name": "Crescent Moon","price": 220, "pattern": 30, "color": Color(0.10, 0.12, 0.30), "color2": Color(1.0, 0.93, 0.70)},
	"melody":   {"name": "Melody",      "price": 230, "pattern": 35, "color": Color(0.55, 0.30, 0.85), "color2": Color(1.0, 1.0, 1.0)},
	"clover":   {"name": "Lucky Clover","price": 240, "pattern": 32, "color": Color(0.95, 0.97, 0.90), "color2": Color(0.22, 0.68, 0.32)},
	"daisy":    {"name": "Daisy",       "price": 250, "pattern": 22, "color": Color(0.74, 0.64, 0.96), "color2": Color(1.0, 1.0, 1.0)},
	"yinyang":  {"name": "Harmony",     "price": 260, "pattern": 34, "color": Color(0.10, 0.10, 0.12), "color2": Color(0.97, 0.97, 0.98)},
	"diamond":  {"name": "Diamond",     "price": 280, "pattern": 31, "color": Color(0.10, 0.32, 0.45), "color2": Color(0.62, 0.92, 0.99)},
	"rainbow":  {"name": "Rainbow",     "price": 300, "pattern": 28, "color": Color(1, 0, 0),          "color2": Color(1, 1, 1)},
}

# Complete pre-made wheel skins, each a single bundled look (rings, hub, numeral,
# plus any procedural overlay like flames). Equipping one switches simon_mode to
# SKIN and overrides the manual per-part colours; equipping a per-part colour
# switches simon_mode back to MANUAL. Stock-look behaviour is unchanged when no
# skin has ever been equipped.
# Ordered by price, ascending (mirrors SKIN_DEFS in shop_screen.gd, the actual
# source of shop display order).
const SIMON_SKINS := {
	"casino":     {"name": "Jackpot",   "price": 4500},
	"arcade":     {"name": "Arcade",    "price": 5000},
	"lunapark":   {"name": "Luna Park", "price": 5500},
	"racing":     {"name": "Redline",   "price": 7000},
	"pirate":     {"name": "Buccaneer", "price": 7200},
	"submarine":  {"name": "Nautilus",  "price": 7500},
	"phantom":    {"name": "Phantom",   "price": 7800},
	# Stored id stays "inferno" (selected_skin / owned_skins in Firestore, and the
	# _skin_id checks in SimonWheel) so existing ownership keeps working; only the
	# display name changed when the skin was upgraded into the Volcano look.
	"inferno":    {"name": "Volcano",   "price": 8000},
}

# The "level_number" category is NOT a flat colour — it's a font *package* (a whole
# look: typeface + glow + colour + outline). These are its catalog entries; the id
# stored in equipped_simon["level_number"] / owned_simon refers to one of these.
# Fields consumed by SimonWheel._apply_num_pack and SimonPartIcon._draw_number:
#   font         res:// path to a .ttf, or "" = engine default font
#   color        main numeral colour
#   glow / glow_size    soft outer-glow colour + blur radius
#   outline / outline_size   thin weight/stroke colour + size
const SIMON_DEFAULT_FONT := "classic"
const SIMON_NUMBER_FONTS := {
	# The outline is intentionally a CONTRASTING colour to the fill (not a same-hue
	# weight) so the numeral stays readable even on a hub of the same colour.
	"classic": {"name": "Classic", "price": 0,   "font": "",
		"color": Color(1, 1, 1), "glow": Color(0.45, 0.68, 1.0, 0.5), "glow_size": 10,
		"outline": Color(0.05, 0.07, 0.16, 0.95), "outline_size": 4},
	"neon":    {"name": "Neon",    "price": 120, "font": "",
		"color": Color(0.45, 1.0, 0.95), "glow": Color(0.10, 0.95, 0.90, 0.8), "glow_size": 15,
		"outline": Color(0.0, 0.05, 0.07, 1.0), "outline_size": 4},
	"sky":     {"name": "Sky",     "price": 120, "font": "",
		"color": Color(0.62, 0.86, 1.0), "glow": Color(0.35, 0.70, 1.0, 0.65), "glow_size": 13,
		"outline": Color(0.05, 0.16, 0.38, 1.0), "outline_size": 4},
	"lavender": {"name": "Lavender", "price": 140, "font": "",
		"color": Color(0.80, 0.70, 1.0), "glow": Color(0.60, 0.45, 1.0, 0.65), "glow_size": 13,
		"outline": Color(0.20, 0.12, 0.40, 1.0), "outline_size": 4},
	"mint":    {"name": "Mint",    "price": 140, "font": "",
		"color": Color(0.65, 1.0, 0.85), "glow": Color(0.30, 0.95, 0.75, 0.65), "glow_size": 13,
		"outline": Color(0.04, 0.28, 0.22, 1.0), "outline_size": 4},
	"inferno": {"name": "Inferno", "price": 150, "font": "",
		"color": Color(1.0, 0.66, 0.22), "glow": Color(1.0, 0.28, 0.06, 0.75), "glow_size": 15,
		"outline": Color(0.10, 0.02, 0.0, 1.0), "outline_size": 5},
	# Softer, girlier looks — the rounded handwritten face (orange_juice) in candy
	# tones, plus a couple of bright playful colourways on the stock face.
	"bubblegum": {"name": "Bubblegum", "price": 160, "font": "res://fonts/orange_juice.ttf",
		"color": Color(1.0, 0.62, 0.82), "glow": Color(1.0, 0.45, 0.72, 0.7), "glow_size": 14,
		"outline": Color(0.55, 0.12, 0.30, 1.0), "outline_size": 5},
	"script":  {"name": "Script",  "price": 180, "font": "res://fonts/orange_juice.ttf",
		"color": Color(1.0, 0.96, 0.86), "glow": Color(0.90, 0.75, 0.50, 0.45), "glow_size": 9,
		"outline": Color(0.12, 0.07, 0.03, 1.0), "outline_size": 4},
	"candy":   {"name": "Candy",   "price": 200, "font": "res://fonts/orange_juice.ttf",
		"color": Color(1.0, 0.90, 0.98), "glow": Color(0.85, 0.35, 0.95, 0.7), "glow_size": 14,
		"outline": Color(0.45, 0.10, 0.55, 1.0), "outline_size": 5},
	"gold":    {"name": "Gold",    "price": 250, "font": "res://fonts/arial.ttf",
		"color": Color(1.0, 0.84, 0.32), "glow": Color(1.0, 0.70, 0.16, 0.6), "glow_size": 11,
		"outline": Color(0, 0, 0, 1), "outline_size": 5},
}

# The catalog backing a category: font packages for "level_number", and per-part
# style sets for the ring/hub — each is the shared flat colours PLUS that part's
# own patterns (outer) or motifs (inner). Built once, lazily (see _build_style_catalogs).
var _outer_catalog: Dictionary = {}
var _inner_catalog: Dictionary = {}

func simon_catalog(category: String) -> Dictionary:
	if category == "level_number":
		return SIMON_NUMBER_FONTS
	if _outer_catalog.is_empty():
		_build_style_catalogs()
	return _inner_catalog if category == "inner_circle" else _outer_catalog

# Merge the shared flat colours with each part's extra styles. Order matters for
# the shop grid: flat colours first (cheapest, familiar), then the fancy styles.
func _build_style_catalogs() -> void:
	_outer_catalog = SIMON_COLORS.duplicate(true)
	for k in SIMON_OUTER_PATTERNS:
		_outer_catalog[k] = SIMON_OUTER_PATTERNS[k]
	_inner_catalog = SIMON_COLORS.duplicate(true)
	for k in SIMON_INNER_MOTIFS:
		_inner_catalog[k] = SIMON_INNER_MOTIFS[k]

# The look a ring/hub part wears for a catalog id, resolved for both the 3D wheel
# (SimonWheel.apply_skin) and the 2D shop swatch (SimonPartIcon):
#   null       -> stock graphite (the "default" id)
#   Color      -> a flat tint (legacy colour styles)
#   Dictionary -> a pattern/motif: {"pattern": int, "a": Color, "b": Color}
func simon_part_style(category: String, id: String) -> Variant:
	if id == SIMON_DEFAULT_COLOR:
		return null
	var meta: Dictionary = simon_catalog(category).get(id, {})
	if meta.has("pattern"):
		return {
			"pattern": int(meta["pattern"]),
			"a": meta.get("color", Color.GRAY),
			"b": meta.get("color2", Color.WHITE),
		}
	return meta.get("color", Color.GRAY)

# The free/stock default id for a category (font "classic" vs colour "default").
func simon_default_id(category: String) -> String:
	return SIMON_DEFAULT_FONT if category == "level_number" else SIMON_DEFAULT_COLOR

# Price of any catalog item, looked up in the category's own catalog.
func simon_item_price(category: String, id: String) -> int:
	return int(simon_catalog(category).get(id, {}).get("price", 0))

func can_afford_simon_item(category: String, id: String) -> bool:
	return balance >= simon_item_price(category, id)

# The full font package for a level-number style id (falls back to Classic).
func simon_number_font(id: String) -> Dictionary:
	return SIMON_NUMBER_FONTS.get(id, SIMON_NUMBER_FONTS[SIMON_DEFAULT_FONT])

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
# The most recently loaded /users/{uid} document, verbatim. Exposed so other
# managers (e.g. BadgeManager) can read extra fields off the SAME authenticated
# read without issuing a second one that would race the shared plugin signal.
var raw_user_doc: Dictionary = {}
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
# Leaderboard rewards (see LEADERBOARD_REWARDS_PLAN.md):
var alltime_reward_bands: Dictionary = {} # diff -> best (lowest) band idx already
										  # rewarded on the all-time board. Absent
										  # / 0 = never rewarded for that diff.
var last_daily_reward_date: String = ""   # "YYYY-MM-DD" UTC of the most recent day
										  # whose daily-standing reward has been
										  # resolved. "" = never (fresh cycle).
# Audit trail (added later so old wallets keep working — both default to empty
# and accumulate forward from the first new event).
var earned_coins: int = 0                 # lifetime coins earned by gameplay/claims,
										  # NOT counting real-money purchases. Allows
										  # auditing balance = earned + purchased - spent.
var purchase_history: Dictionary = {}     # sku -> { iso_timestamp: true }. Stored as
										  # a map-of-map (not a list) because the Android
										  # Firestore SDK rejects raw arrays — same
										  # reasoning as _owned_themes_map_for_save.
# Non-consumable entitlement: once bought, ads are off forever. The flag is
# the durable source of truth — PurchaseManager re-acknowledges with Play on
# every fresh install, but it's CoinsManager that the rest of the app reads.
var has_remove_ads: bool = false
# Whether this account has already seen the first-run home-screen tour. The
# server-side half of the "seen" flag (the local half lives in user://prefs.cfg,
# owned by the home screen) so a signed-in player who saw the tour on one device
# won't be shown it again on another.
var tutorial_seen: bool = false

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
	earned_coins += session_earned
	balance_changed.emit(balance)
	_save_partial({"coins": balance, "earned_coins": earned_coins})

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
	earned_coins += reward
	last_claim_date = _today()
	balance_changed.emit(balance)
	daily_claim_changed.emit()
	_save_partial({
		"coins": balance,
		"earned_coins": earned_coins,
		"last_claim_date": last_claim_date,
	})
	return reward

# --- leaderboard rewards ------------------------------------------------------

# The all-time reward band for a rank (1 = best, 0 = outside top 50 / no reward).
static func _alltime_band_index(rank: int) -> int:
	if rank <= 0:  return 0
	if rank == 1:  return 1
	if rank == 2:  return 2
	if rank == 3:  return 3
	if rank <= 10: return 4
	if rank <= 24: return 5
	if rank <= 50: return 6
	return 0

# Coins for a FINAL daily standing (0 outside top 50).
static func daily_reward_for_rank(rank: int) -> int:
	if rank <= 0:  return 0
	if rank == 1:  return 500
	if rank == 2:  return 300
	if rank == 3:  return 150
	if rank <= 10: return 100
	if rank <= 25: return 50
	if rank <= 50: return 25
	return 0

# Grant the all-time milestone reward for reaching `rank` on `diff`, IF that rank
# lands in a strictly better band than the best we've already rewarded for this
# difficulty. Returns the coins granted (0 if no new band). Called at game over
# on a new personal best (the only time an all-time rank can improve), after the
# rank has been read back from the board.
#
# The band update and the coin delta ride the SAME merge write, so a failed save
# never leaves "rewarded but unpaid": the server keeps the old band AND old
# balance, and a later new-high re-attempts cleanly.
func maybe_reward_alltime(diff: String, rank: int) -> int:
	if not is_loaded():
		return 0
	var idx := _alltime_band_index(rank)
	if idx == 0:
		return 0
	var best := int(alltime_reward_bands.get(diff, 0))
	if best != 0 and idx >= best:
		return 0                                   # same or worse band → nothing
	var reward := int(ALLTIME_BAND_REWARDS.get(idx, 0))
	if reward <= 0:
		return 0
	alltime_reward_bands[diff] = idx
	balance += reward
	earned_coins += reward
	balance_changed.emit(balance)
	_save_partial({
		"coins": balance,
		"earned_coins": earned_coins,
		"alltime_reward_bands": alltime_reward_bands,
	})
	return reward

# The daily-standing reward is now computed and CREDITED server-side by the
# midnight Cloud Function (functions/index.js -> closeDailyBoards): it increments
# the wallet's coins/earned_coins and writes a receipt into pending_daily_rewards
# on /users/{uid}, keyed by the closed day's date. The client no longer reads the
# leaderboards or credits coins for this — it just surfaces the receipt popup for
# any day(s) not yet shown and clears them. The coins are already reflected in
# `balance` (loaded from the doc on sign-in), so this ONLY shows the celebratory
# receipt; it never changes the balance.
#
# pending_daily_rewards shape (server-written):
#   { "YYYY-MM-DD": { total:int, results:[{diff,rank,reward}], date:String }, ... }
func consume_pending_daily_rewards() -> void:
	if not is_loaded():
		return
	var pending: Variant = raw_user_doc.get("pending_daily_rewards", {})
	if not (pending is Dictionary) or (pending as Dictionary).is_empty():
		return
	# Merge every not-yet-shown day into one receipt (normally exactly one; more
	# only if the player was away several days). Chronological by date key.
	var dates: Array = (pending as Dictionary).keys()
	dates.sort()
	var grand_total := 0
	var all_results: Array = []
	for date_str in dates:
		var entry: Variant = (pending as Dictionary)[date_str]
		if entry is Dictionary:
			grand_total += int((entry as Dictionary).get("total", 0))
			var rs: Variant = (entry as Dictionary).get("results", [])
			if rs is Array:
				for r in rs:
					all_results.append(r)
	# Clear the receipt so it never shows twice. We consumed every current key, so
	# write an empty map. (A key the server might add in the very same instant would
	# be lost here, but the coins are already banked — only the popup would be
	# missed, an acceptable once-a-day-at-most race.)
	raw_user_doc["pending_daily_rewards"] = {}
	_save_partial({"pending_daily_rewards": {}})
	if grand_total > 0:
		daily_rank_reward_granted.emit(grand_total, all_results)

# --- daily-task rewards -------------------------------------------------------

# Credit the coins for one or more claimed daily tasks. `extra_fields` carries the
# claimant's own state (DailyTasks' `daily_tasks` map) and rides the SAME merge
# write as the coin delta, so a failed save can never leave a task "claimed but
# unpaid" — the server keeps both the old claimed-set AND the old balance, and the
# player can simply claim again. Same reasoning as maybe_reward_alltime.
#
# Returns true if the coins were credited.
func credit_task_reward(amount: int, extra_fields: Dictionary = {}) -> bool:
	if amount <= 0 or not is_loaded():
		return false
	balance += amount
	earned_coins += amount
	balance_changed.emit(balance)
	var fields := {"coins": balance, "earned_coins": earned_coins}
	for k in extra_fields:
		fields[k] = extra_fields[k]
	_save_partial(fields)
	return true

# --- real-money coin purchases ---

# Credit coins purchased via Google Play Billing. Called by PurchaseManager
# after a successful, deduplicated purchase. WHY a dedicated entry-point and
# not a generic add_coins: when this moves server-side per
# COINS_PURCHASE_PLAN.md the Cloud Function will own the increment and the
# client will just _load_user() — having the call site already isolated to
# one method makes that swap a one-file change.
#
# The optional `sku` parameter lets us append a purchase-history entry under
# /users/{uid}/purchase_history.{sku}.{iso_ts} = true alongside the balance
# update, so the wallet doc itself carries an auditable list of past purchases.
# Purchased coins are intentionally NOT added to `earned_coins`; that field
# tracks gameplay/claim earnings only, so balance can later be audited as
# earned + purchased − spent.
func credit_purchased_coins(amount: int, sku: String = "") -> void:
	if amount <= 0:
		return
	if not FirebaseManager.is_signed_in():
		return
	balance += amount
	var fields := {"coins": balance}
	if not sku.is_empty():
		var iso := _now_iso(int(Time.get_unix_time_from_system()))
		var per_sku: Dictionary = purchase_history.get(sku, {})
		per_sku[iso] = true
		purchase_history[sku] = per_sku
		# Firestore merge writes replace the value at a top-level field key (no
		# nested merge), so we send the entire map back. It's small (a few SKUs
		# × a handful of timestamps), and _apply_doc reloaded it on sign-in so
		# we have the full history in memory before mutating.
		fields["purchase_history"] = purchase_history
	balance_changed.emit(balance)
	_save_partial(fields)

# Mark the remove-ads entitlement as owned. Idempotent: a no-op if the flag
# is already set (PurchaseManager calls this on every replay of the original
# Play purchase). `sku` is recorded in purchase_history on the first grant so
# the wallet has a paper trail for support.
func set_remove_ads_owned(sku: String = "") -> void:
	if not FirebaseManager.is_signed_in():
		return
	if has_remove_ads:
		return
	has_remove_ads = true
	var fields := {"has_remove_ads": true}
	if not sku.is_empty():
		var iso := _now_iso(int(Time.get_unix_time_from_system()))
		var per_sku: Dictionary = purchase_history.get(sku, {})
		per_sku[iso] = true
		purchase_history[sku] = per_sku
		fields["purchase_history"] = purchase_history
	remove_ads_changed.emit()
	_save_partial(fields)

# Record that this account has seen the first-run home tour. Idempotent; a no-op
# for guests (their "seen" flag is the local file, not the wallet doc).
func mark_tutorial_seen() -> void:
	if not FirebaseManager.is_signed_in():
		return
	if tutorial_seen:
		return
	tutorial_seen = true
	_save_partial({"tutorial_seen": true})

# Permanently erases the wallet doc (coins, streak, owned cosmetics, purchase
# history, remove-ads flag) for the account-deletion flow. Note this does NOT
# revoke the non-consumable "remove ads" Play purchase itself — Play still
# owns that record, so PurchaseManager's startup query silently re-grants it
# on the next sign-in. Consumable coin purchases have no such replay: once
# this doc is gone, any coins bought with real money are gone for good, same
# as any other in-game currency tied to a deleted save.
func delete_wallet_doc() -> void:
	var doc_uid := FirebaseManager.uid
	if doc_uid.is_empty():
		return
	if _is_editor:
		_sim_db.erase(doc_uid)
		return
	Firebase.firestore.delete_document(_COLL, doc_uid)
	await Firebase.firestore.delete_task_completed

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

# Equip an owned theme. Returns true if anything actually changed.
#
# Equipping a theme is a manual choice, so it also drops any complete skin: a skin
# wins everything while on (overriding both the background AND the per-part wheel
# colours), and equipping a theme returns to the manual look. The saved theme +
# per-part colours are kept in storage untouched while a skin is on, so flipping
# simon_mode back to manual simply makes them active again ("reequip all the manual
# stuff"). This is why it's not a plain `selected_theme == theme_id` early-out — we
# must still drop the skin even when re-equipping the already-selected theme.
func select_theme(theme_id: String) -> bool:
	if not owns(theme_id): return false
	var fields := {}
	var mode_changed := false
	if simon_mode != SIMON_MODE_MANUAL:
		simon_mode = SIMON_MODE_MANUAL
		mode_changed = true
		fields["simon_mode"] = simon_mode
	var theme_changed := selected_theme != theme_id
	if theme_changed:
		selected_theme = theme_id
		fields["selected_theme"] = selected_theme
	if not mode_changed and not theme_changed:
		return false
	themes_changed.emit()
	if mode_changed:
		simon_changed.emit()    # the skin came off → wheel, skin cards + simon tiles refresh
	_save_partial(fields)
	return true

# --- simon-customization API ---

func _default_equipped_simon() -> Dictionary:
	var d := {}
	for cat in SIMON_CATEGORIES:
		d[cat] = simon_default_id(cat)
	return d

func _default_owned_simon() -> Dictionary:
	var d := {}
	for cat in SIMON_CATEGORIES:
		d[cat] = [simon_default_id(cat)] as Array[String]
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
	if not simon_catalog(category).has(color_id): return false
	if owns_simon_color(category, color_id): return false
	var price := simon_item_price(category, color_id)
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
	# implicitly drops any complete skin and puts the wheel back into manual mode.
	# A skin wins everything while on (overriding the per-part colours AND the
	# theme), but the manual config is kept in storage untouched — so flipping back
	# to manual restores the rest of the saved per-part colours, with only the part
	# just tapped changing here.
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

# --- complete skin API (the SPECIAL SKINS shop tab) ---

func skin_price(skin_id: String) -> int:
	return int(SIMON_SKINS.get(skin_id, {}).get("price", 0))

func owns_skin(skin_id: String) -> bool:
	return owned_skins.has(skin_id)

func can_afford_skin(skin_id: String) -> bool:
	return balance >= skin_price(skin_id)

# Buy a complete skin. Returns true on success (deducts coins, adds to owned_skins).
func purchase_skin(skin_id: String) -> bool:
	if not FirebaseManager.is_signed_in(): return false
	if not SIMON_SKINS.has(skin_id): return false
	if owns_skin(skin_id): return false
	var price := skin_price(skin_id)
	if balance < price: return false
	balance -= price
	owned_skins.append(skin_id)
	balance_changed.emit(balance)
	simon_changed.emit()
	_save_partial({"coins": balance, "owned_skins": _owned_skins_map_for_save()})
	return true

# Equip an owned complete skin. Equipping a skin implicitly puts the wheel into
# SKIN mode (mirrors equip_simon_color flipping into MANUAL). Returns true if
# anything actually changed.
func equip_skin(skin_id: String) -> bool:
	if not owns_skin(skin_id): return false
	var changed := false
	if simon_mode != SIMON_MODE_SKIN:
		simon_mode = SIMON_MODE_SKIN
		changed = true
	if selected_skin != skin_id:
		selected_skin = skin_id
		changed = true
	if not changed:
		return false
	simon_changed.emit()
	_save_partial({"simon_mode": simon_mode, "selected_skin": selected_skin})
	return true

# Same map-not-array reasoning as _owned_themes_map_for_save.
func _owned_skins_map_for_save() -> Dictionary:
	var out := {}
	for s in owned_skins:
		out[s] = true
	return out

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
	alltime_reward_bands = {}
	last_daily_reward_date = ""
	earned_coins = 0
	purchase_history = {}
	has_remove_ads = false
	tutorial_seen = false
	session_earned = 0
	_loaded_for_uid = ""
	balance_changed.emit(balance)
	themes_changed.emit()
	simon_changed.emit()
	levels_changed.emit()
	daily_claim_changed.emit()
	remove_ads_changed.emit()

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
	remove_ads_changed.emit()

func _apply_doc(doc: Dictionary) -> void:
	raw_user_doc = doc.duplicate(true)
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
	# Leaderboard-reward trackers. Missing on old wallets — defaults ({} / "")
	# are correct: no bands rewarded yet, and an empty date starts a fresh daily
	# cycle (no retroactive pay) on the next login.
	alltime_reward_bands = {}
	var raw_bands: Variant = doc.get("alltime_reward_bands", {})
	if raw_bands is Dictionary:
		for k in raw_bands.keys():
			alltime_reward_bands[String(k)] = int(raw_bands[k])
	last_daily_reward_date = String(doc.get("last_daily_reward_date", ""))
	# Audit fields. Missing on old wallets — defaults are correct (0 / {}) and
	# the value just accumulates forward from the next event.
	earned_coins = int(doc.get("earned_coins", 0))
	purchase_history = {}
	var raw_ph: Variant = doc.get("purchase_history", {})
	if raw_ph is Dictionary:
		for sku in raw_ph.keys():
			var entries: Variant = raw_ph[sku]
			if entries is Dictionary:
				var copy := {}
				for ts in entries.keys():
					copy[String(ts)] = true
				purchase_history[String(sku)] = copy
	has_remove_ads = bool(doc.get("has_remove_ads", false))
	tutorial_seen = bool(doc.get("tutorial_seen", false))
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
		var catalog := simon_catalog(cat)
		var def_id := simon_default_id(cat)
		var owned: Array[String] = owned_simon[cat]
		var raw: Variant = doc.get(_owned_simon_field(cat), {})
		if raw is Dictionary:
			for k in raw.keys():
				var s := String(k)
				if catalog.has(s) and not owned.has(s):
					owned.append(s)
		elif raw is Array:
			for t in raw:
				var s := String(t)
				if catalog.has(s) and not owned.has(s):
					owned.append(s)
		var eq := String(doc.get(_equipped_simon_field(cat), def_id))
		equipped_simon[cat] = eq if owned.has(eq) else def_id
	owned_skins = []
	var raw_sk: Variant = doc.get("owned_skins", {})
	if raw_sk is Dictionary:
		for k in raw_sk.keys():
			var s := String(k)
			if SIMON_SKINS.has(s) and not owned_skins.has(s):
				owned_skins.append(s)
	elif raw_sk is Array:
		for t in raw_sk:
			var s := String(t)
			if SIMON_SKINS.has(s) and not owned_skins.has(s):
				owned_skins.append(s)
	selected_skin = String(doc.get("selected_skin", ""))
	if not selected_skin.is_empty() and not owned_skins.has(selected_skin):
		selected_skin = ""
	# Defensive: if the doc claims skin mode but no skin is actually owned/selected,
	# fall back to manual so the wheel never tries to render a non-existent skin.
	if simon_mode == SIMON_MODE_SKIN and selected_skin.is_empty():
		simon_mode = SIMON_MODE_MANUAL

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

# UTC "day index" = number of whole days since the unix epoch. A single integer
# per calendar day that's trivial to add/subtract and round-trips with a
# "YYYY-MM-DD" string via the two helpers below. Used by the daily-reward scan.
func _today_day_index() -> int:
	return int(floor(float(Time.get_unix_time_from_system()) / 86400.0))

func _day_index_from_date(date_str: String) -> int:
	# Godot parses a bare "YYYY-MM-DD" as that date at 00:00 UTC.
	var u := int(Time.get_unix_time_from_datetime_string(date_str))
	return int(floor(float(u) / 86400.0))

func _date_str_from_day_index(day_index: int) -> String:
	var d := Time.get_date_dict_from_unix_time(day_index * 86400)
	return "%04d-%02d-%02d" % [int(d["year"]), int(d["month"]), int(d["day"])]
