extends Node

# ─────────────────────────────────────────────────────────────────────────────
# DailyTasks — a small set of goals that refresh every UTC day ("play 3 games",
# "reach round 7 on Hard", "play an Arena race", …). Progress accrues silently
# while the player plays; the coins are only handed over when they CLAIM a
# finished task from the tasks popup (one at a time, or all at once). The home
# screen badges the tasks pill with a red count while anything is claimable.
#
# STORAGE: one map field, `daily_tasks`, on /users/{uid} — the same doc the
# wallet and the badge bitfield already live on:
#
#   daily_tasks: {
#     date:     "YYYY-MM-DD",                # UTC day this state belongs to
#     counters: { games: 3, best_hard: 5 },  # raw progress, task-agnostic
#     claimed:  { play_1: true },            # ids already paid out
#   }
#
# Tasks read their progress from a shared COUNTER rather than a per-task number,
# so the catalog can be re-tuned — or new tasks added — with no migration: a new
# task simply starts reading a counter that is already being kept. Maps, never
# arrays: the Android Firestore SDK rejects raw arrays (see
# CoinsManager._owned_themes_map_for_save for the full story).
#
# READ: piggy-backs on CoinsManager's single authenticated read of /users/{uid}
# (raw_user_doc), exactly like BadgeManager — a second get_document would race it
# on the plugin's shared task signal.
#
# WRITE: progress writes are COALESCED into one deferred merge write and never
# fire before `loaded`, so they can't race the login read. A CLAIM instead rides
# CoinsManager.credit_task_reward, which puts the coin delta AND the new claimed
# set in the SAME merge write — so a failed save can never leave a task "claimed
# but unpaid" (the same trick maybe_reward_alltime uses for band rewards).
# ─────────────────────────────────────────────────────────────────────────────

# Progress kinds:
#   COUNT  accumulates            (games played)        → "2 TO GO"
#   BEST   keeps the day's max    (highest round)       → "REACH 7"
#   RANK   keeps the day's MIN    (best leaderboard #)  → "TOP 50"
# RANK is the odd one out: lower is better and 0 means "no standing yet", so it
# gets its own completion test and its own progress bar (see bar_fraction).
const COUNT := "count"
const BEST := "best"
const RANK := "rank"

# Accents, echoing the palettes already in use elsewhere (BadgeManager.CAT_COLORS
# for volume/arena, profile_screen.DIFFS for the difficulty tints).
const C_PLAY := Color(0.38, 0.64, 0.98)     # play-volume tasks
const C_ROUND := Color(0.28, 0.80, 0.82)    # cumulative rounds / breadth
const C_SKILL := Color(0.64, 0.46, 0.96)    # best-score tasks
const C_EASY := Color(0.30, 0.82, 0.46)
const C_MOD := Color(1.00, 0.72, 0.25)
const C_HARD := Color(1.00, 0.46, 0.22)
const C_ARENA := Color(0.96, 0.36, 0.42)
const C_BOARD := Color(1.00, 0.78, 0.26)    # daily-leaderboard standings
const C_GIFT := Color(0.98, 0.86, 0.35)     # the daily ritual + coin earnings

# The catalog, in CATALOG order — which is also the fallback display order (the
# popup floats finished tasks to the top, see ordered_tasks). `counter` names the
# progress bucket; `art` picks the emblem BadgeIcons draws for the medallion.
#
# REWARD SCALE: deliberately small — a task is a nudge, not an income. The cheapest
# ask pays 5 and the hardest 15, so a normal session collects ~50-70 coins and a
# full sweep of all 21 (ten games, round 20, round 12 on Hard, three Arena races…)
# pays 205. Compare the daily claim's 30-100. Retune freely: nothing but this table
# knows the numbers.
const TASKS: Array[Dictionary] = [
	# ── Play volume ─────────────────────────────────────────────────────────
	{"id": "play_1",    "counter": "games",       "kind": COUNT, "target": 1,   "reward": 5,
		"name": "Warm-Up",          "desc": "Play one game",                    "art": "controller", "accent": C_PLAY},
	{"id": "play_3",    "counter": "games",       "kind": COUNT, "target": 3,   "reward": 8,
		"name": "Triple Play",      "desc": "Play three games",                 "art": "controller", "accent": C_PLAY},
	{"id": "play_5",    "counter": "games",       "kind": COUNT, "target": 5,   "reward": 12,
		"name": "Marathon",         "desc": "Play five games",                  "art": "rocket",     "accent": C_PLAY},
	{"id": "play_10",   "counter": "games",       "kind": COUNT, "target": 10,  "reward": 15,
		"name": "Unstoppable",      "desc": "Play ten games",                   "art": "flame",      "accent": C_PLAY},

	# ── Breadth: rounds cleared and difficulties touched ────────────────────
	{"id": "rounds_25", "counter": "rounds",      "kind": COUNT, "target": 25,  "reward": 8,
		"name": "Round Up",         "desc": "Clear 25 rounds in total",         "art": "chart",      "accent": C_ROUND},
	{"id": "rounds_60", "counter": "rounds",      "kind": COUNT, "target": 60,  "reward": 12,
		"name": "Long Haul",        "desc": "Clear 60 rounds in total",         "art": "chart",      "accent": C_ROUND},
	{"id": "all_diffs", "counter": "diffs",       "kind": COUNT, "target": 3,   "reward": 12,
		"name": "Triple Threat",    "desc": "Play Easy, Moderate and Hard",     "art": "triangle",   "accent": C_ROUND},

	# ── Best round of the day, any difficulty ───────────────────────────────
	{"id": "reach_5",   "counter": "best_any",    "kind": BEST,  "target": 5,   "reward": 5,
		"name": "Getting Going",    "desc": "Reach round 5",                    "art": "num", "num": 5,  "accent": C_SKILL},
	{"id": "reach_10",  "counter": "best_any",    "kind": BEST,  "target": 10,  "reward": 8,
		"name": "Double Digits",    "desc": "Reach round 10",                   "art": "num", "num": 10, "accent": C_SKILL},
	{"id": "reach_15",  "counter": "best_any",    "kind": BEST,  "target": 15,  "reward": 12,
		"name": "Sharp Today",      "desc": "Reach round 15",                   "art": "num", "num": 15, "accent": C_SKILL},
	{"id": "reach_20",  "counter": "best_any",    "kind": BEST,  "target": 20,  "reward": 15,
		"name": "Peak Form",        "desc": "Reach round 20",                   "art": "brain",      "accent": C_SKILL},

	# ── Per difficulty ──────────────────────────────────────────────────────
	{"id": "easy_12",   "counter": "best_easy",   "kind": BEST,  "target": 12,  "reward": 6,
		"name": "Easy Does It",     "desc": "Reach round 12 on Easy",           "art": "leaf",       "accent": C_EASY},
	{"id": "mod_8",     "counter": "best_moderate","kind": BEST, "target": 8,   "reward": 8,
		"name": "Middle Ground",    "desc": "Reach round 8 on Moderate",        "art": "spark",      "accent": C_MOD},
	{"id": "mod_14",    "counter": "best_moderate","kind": BEST, "target": 14,  "reward": 12,
		"name": "Moderate Master",  "desc": "Reach round 14 on Moderate",       "art": "spark",      "accent": C_MOD},
	{"id": "hard_7",    "counter": "best_hard",   "kind": BEST,  "target": 7,   "reward": 10,
		"name": "Hard Mode",        "desc": "Reach round 7 on Hard",            "art": "bolt",       "accent": C_HARD},
	{"id": "hard_12",   "counter": "best_hard",   "kind": BEST,  "target": 12,  "reward": 12,
		"name": "Iron Memory",      "desc": "Reach round 12 on Hard",           "art": "bolt",       "accent": C_HARD},

	# ── Arena ───────────────────────────────────────────────────────────────
	{"id": "arena_1",     "counter": "arena",        "kind": COUNT, "target": 1, "reward": 8,
		"name": "Into The Arena",   "desc": "Race once in the Arena",           "art": "swords",     "accent": C_ARENA},
	{"id": "arena_3",     "counter": "arena",        "kind": COUNT, "target": 3, "reward": 12,
		"name": "Arena Regular",    "desc": "Race three times in the Arena",    "art": "sword",      "accent": C_ARENA},
	{"id": "arena_podium","counter": "arena_podium", "kind": COUNT, "target": 1, "reward": 10,
		"name": "On The Podium",    "desc": "Finish top 3 in an Arena race",    "art": "medal",      "accent": C_ARENA},
	{"id": "arena_win",   "counter": "arena_wins",   "kind": COUNT, "target": 1, "reward": 15,
		"name": "Take The Crown",   "desc": "Finish 1st in an Arena race",      "art": "crown",      "accent": C_ARENA},
	{"id": "arena_crowd", "counter": "arena_crowd",  "kind": COUNT, "target": 1, "reward": 12,
		"name": "Full House",       "desc": "Race against 10 or more players",  "art": "flag",       "accent": C_ARENA},

	# ── Today's leaderboard standing (any difficulty) ────────────────────────
	{"id": "lb_top50",  "counter": "lb_rank",     "kind": RANK,  "target": 50,  "reward": 8,
		"name": "On The Board",     "desc": "Reach the daily Top 50",           "art": "chart",      "accent": C_BOARD},
	{"id": "lb_top25",  "counter": "lb_rank",     "kind": RANK,  "target": 25,  "reward": 10,
		"name": "Climbing",         "desc": "Reach the daily Top 25",           "art": "star",       "accent": C_BOARD},
	{"id": "lb_top10",  "counter": "lb_rank",     "kind": RANK,  "target": 10,  "reward": 12,
		"name": "Daily Ten",        "desc": "Reach the daily Top 10",           "art": "medal",      "accent": C_BOARD},
	{"id": "lb_top3",   "counter": "lb_rank",     "kind": RANK,  "target": 3,   "reward": 15,
		"name": "Daily Podium",     "desc": "Reach the daily Top 3",            "art": "trophy",     "accent": C_BOARD},

	# ── The daily ritual + what the day earned ──────────────────────────────
	{"id": "claim",     "counter": "daily_claim", "kind": COUNT, "target": 1,   "reward": 5,
		"name": "Daily Reward",     "desc": "Claim your daily reward",          "art": "gift",       "accent": C_GIFT},
	{"id": "coins_50",  "counter": "coins",       "kind": COUNT, "target": 50,  "reward": 8,
		"name": "Payday",           "desc": "Earn 50 coins from games",         "art": "coin",       "accent": C_GIFT},
	{"id": "coins_150", "counter": "coins",       "kind": COUNT, "target": 150, "reward": 12,
		"name": "Big Earner",       "desc": "Earn 150 coins from games",        "art": "chest",      "accent": C_GIFT},
]

# The difficulties the "Triple Threat" task counts.
const DIFFS := ["easy", "moderate", "hard"]

# Progress, a claim, or a day-rollover moved. Everything that paints tasks
# (the home pill, the popup) listens to this.
signal changed

var _by_id: Dictionary = {}          # id -> task dict
var _date := ""                      # UTC day the state below belongs to
var _counters: Dictionary = {}       # counter name -> int
var _claimed: Dictionary = {}        # task id -> true
var _loaded := false
var _is_editor := OS.get_name() != "Android"
# Progress writes are coalesced + deferred (see the WRITE note above).
var _dirty := false
var _flush_queued := false

func _ready() -> void:
	for t in TASKS:
		_by_id[String(t["id"])] = t
	CoinsManager.loaded.connect(_on_user_loaded)
	FirebaseManager.signed_out.connect(_on_signed_out)
	# A daily standing is reported by whoever loads a daily board — the boot
	# warm-up, the leaderboards screen, a pull-to-refresh. We just listen; the
	# leaderboards never have to know tasks exist.
	LeaderboardManager.daily_rank_seen.connect(_on_daily_rank_seen)
	# Only sync if CoinsManager has GENUINELY loaded (doc present) — never off mere
	# is_signed_in, whose read may still be in flight (same rule as BadgeManager).
	if CoinsManager.raw_user_doc.size() > 0:
		_on_user_loaded()

# ─── public queries ─────────────────────────────────────────────────────────

func is_ready() -> bool:
	return _loaded

func task(id: String) -> Dictionary:
	return _by_id.get(id, {})

func total_count() -> int:
	return TASKS.size()

# The catalog in DISPLAY order: everything finished floats to the top (rewards
# waiting to be collected first, then the ones already banked), and the rest keeps
# catalog order below. Callers snapshot this ONCE when they build — re-sorting a
# live list would shuffle rows out from under the finger that just tapped one.
func ordered_tasks() -> Array[Dictionary]:
	var ready: Array[Dictionary] = []
	var banked: Array[Dictionary] = []
	var pending: Array[Dictionary] = []
	for t in TASKS:
		var id := String(t["id"])
		if not is_complete(id):
			pending.append(t)
		elif is_claimed(id):
			banked.append(t)
		else:
			ready.append(t)
	var out: Array[Dictionary] = []
	out.append_array(ready)
	out.append_array(banked)
	out.append_array(pending)
	return out

# Raw progress toward a task, clamped to its target (so a round-25 run doesn't
# report 25/10 on a "reach round 10" task). RANK tasks are not clamped — their
# value is a leaderboard position, not an amount.
func progress(id: String) -> int:
	var t: Dictionary = _by_id.get(id, {})
	if t.is_empty():
		return 0
	var have := _counter(String(t["counter"]))
	if String(t["kind"]) == RANK:
		return have
	return mini(have, int(t["target"]))

func is_complete(id: String) -> bool:
	var t: Dictionary = _by_id.get(id, {})
	if t.is_empty():
		return false
	var have := _counter(String(t["counter"]))
	if String(t["kind"]) == RANK:
		return have > 0 and have <= int(t["target"])   # lower is better; 0 = unranked
	return have >= int(t["target"])

# ─── display copy (kept here so the catalog owns what a task MEANS) ─────────

# 0..1 for the row's progress bar. A RANK task has no natural fraction, so it
# uses target/rank — full at the target, half at twice it, tapering off below.
func bar_fraction(id: String) -> float:
	var t: Dictionary = _by_id.get(id, {})
	if t.is_empty():
		return 0.0
	var have := _counter(String(t["counter"]))
	var target := maxi(1, int(t["target"]))
	if String(t["kind"]) == RANK:
		if have <= 0:
			return 0.0
		return clampf(float(target) / float(have), 0.0, 1.0)
	return clampf(float(have) / float(target), 0.0, 1.0)

# The small readout above the bar: "3 / 5" for amounts, "#12" for a standing.
func progress_text(id: String) -> String:
	var t: Dictionary = _by_id.get(id, {})
	if t.is_empty():
		return ""
	if String(t["kind"]) == RANK:
		var r := _counter(String(t["counter"]))
		return ("#%d" % r) if r > 0 else "—"
	return "%d / %d" % [progress(id), int(t["target"])]

# What the muted action pill says while a task is still out of reach.
func action_text(id: String) -> String:
	var t: Dictionary = _by_id.get(id, {})
	if t.is_empty():
		return ""
	var target := int(t["target"])
	match String(t["kind"]):
		RANK:
			return "TOP %d" % target
		BEST:
			return "REACH %d" % target
		_:
			return "%d TO GO" % maxi(1, target - progress(id))

func is_claimed(id: String) -> bool:
	return bool(_claimed.get(id, false))

func can_claim(id: String) -> bool:
	return _loaded and is_complete(id) and not is_claimed(id)

func claimable_count() -> int:
	var n := 0
	for t in TASKS:
		if can_claim(String(t["id"])):
			n += 1
	return n

# Coins sitting unclaimed right now — the "+N" on the Claim All button.
func claimable_total() -> int:
	var sum := 0
	for t in TASKS:
		if can_claim(String(t["id"])):
			sum += int(t["reward"])
	return sum

func completed_count() -> int:
	var n := 0
	for t in TASKS:
		if is_complete(String(t["id"])):
			n += 1
	return n

func all_claimed() -> bool:
	for t in TASKS:
		if not is_claimed(String(t["id"])):
			return false
	return true

# Seconds until the UTC midnight that wipes the board (drives the popup's
# "RESETS IN 7h 12m" line).
func seconds_until_reset() -> int:
	var now := int(Time.get_unix_time_from_system())
	return 86400 - int(posmod(now, 86400))

# Re-check the calendar. Called when a tasks surface opens so a client left
# running across midnight doesn't keep showing yesterday's board.
func refresh() -> void:
	if _roll_if_new_day():
		_mark_dirty()
		changed.emit()

# ─── claiming ───────────────────────────────────────────────────────────────

# Pay out one finished task. Returns the coins granted (0 if it wasn't claimable
# or the wallet refused the write).
func claim(id: String) -> int:
	_roll_if_new_day()
	if not can_claim(id):
		return 0
	return _pay([id])

# Pay out every finished-but-unclaimed task in ONE write. Returns the total.
func claim_all() -> int:
	_roll_if_new_day()
	var ids: Array[String] = []
	for t in TASKS:
		var id := String(t["id"])
		if can_claim(id):
			ids.append(id)
	if ids.is_empty():
		return 0
	return _pay(ids)

# Mark `ids` claimed and credit their coins. The claimed-set rides the wallet's
# merge write so the payout and the record of it can't come apart; if the wallet
# refuses (signed out / not loaded) we roll the marks back and pay nothing.
func _pay(ids: Array[String]) -> int:
	var total := 0
	for id in ids:
		_claimed[id] = true
		total += int((_by_id[id] as Dictionary)["reward"])
	var state := _state_for_save()
	if not CoinsManager.credit_task_reward(total, {"daily_tasks": state}):
		for id in ids:
			_claimed.erase(id)
		return 0
	# Keep CoinsManager's cached doc coherent, and drop any pending progress write
	# — the state we just sent already carries the counters.
	CoinsManager.raw_user_doc["daily_tasks"] = state
	_dirty = false
	changed.emit()
	return total

# ─── progress hooks (called from the game systems, one thin line each) ──────

func note_game_played(difficulty: String) -> void:
	_bump("games", 1)
	_mark_diff_played(difficulty)

# First game of the day on this difficulty. "Triple Threat" counts the SET, so a
# per-difficulty flag is what keeps the tally idempotent across replays.
func _mark_diff_played(difficulty: String) -> void:
	if not DIFFS.has(difficulty) or _defer("diff", difficulty, 1):
		return
	_roll_if_new_day()
	var seen := "played_" + difficulty
	if _counter(seen) != 0:
		return
	_counters[seen] = 1
	_counters["diffs"] = _counter("diffs") + 1
	_mark_dirty()
	changed.emit()

func note_arena_played() -> void:
	_bump("arena", 1)

# Final standing in a race that actually happened. `players` is the size of the
# field, so "race against 10 or more" can only be earned in a real crowd.
func note_contest_result(rank: int, players: int) -> void:
	if players >= 10:
		_bump("arena_crowd", 1)
	if rank <= 0:
		return
	if rank <= 3:
		_bump("arena_podium", 1)
	if rank == 1:
		_bump("arena_wins", 1)

# Today's position on a daily board (any difficulty). Best-of-the-day wins, and
# the same standing seen twice changes nothing, so this is safe to call on every
# board load.
func note_daily_rank(rank: int) -> void:
	_lower("lb_rank", rank)

func _on_daily_rank_seen(_difficulty: String, rank: int) -> void:
	note_daily_rank(rank)

func note_score(difficulty: String, rounds: int) -> void:
	_bump("rounds", rounds)                 # lifetime-of-the-day rounds cleared
	_raise("best_any", rounds)
	if DIFFS.has(difficulty):
		_raise("best_" + difficulty, rounds)

# Coins banked from a finished run (CoinsManager.session_earned). Only gameplay
# earnings count here — claims and task rewards are not "earned from games".
func note_coins_earned(amount: int) -> void:
	_bump("coins", amount)

func note_daily_claimed() -> void:
	_raise("daily_claim", 1)

# ─── counters ───────────────────────────────────────────────────────────────

func _counter(name: String) -> int:
	return int(_counters.get(name, 0))

# Accumulating counter (games played, races run).
func _bump(name: String, by: int) -> void:
	if by <= 0 or _defer("bump", name, by):
		return
	_roll_if_new_day()
	_counters[name] = _counter(name) + by
	_mark_dirty()
	changed.emit()

# High-water counter (best round of the day). Only writes when it actually moves,
# so a string of weak runs costs nothing.
func _raise(name: String, value: int) -> void:
	if value <= 0 or _defer("raise", name, value):
		return
	_roll_if_new_day()
	if value <= _counter(name):
		return
	_counters[name] = value
	_mark_dirty()
	changed.emit()

# Low-water counter (best leaderboard position of the day, where 1 is best and 0
# means "no standing yet" — so an empty counter always loses to a real rank).
func _lower(name: String, value: int) -> void:
	if value <= 0 or _defer("lower", name, value):
		return
	_roll_if_new_day()
	var cur := _counter(name)
	if cur > 0 and value >= cur:
		return
	_counters[name] = value
	_mark_dirty()
	changed.emit()

# Notes can land before the board itself has loaded — the leaderboard warm-up
# races CoinsManager's wallet read at boot, and whichever wins, _decode would
# overwrite anything already counted. So a note taken while a load is in flight is
# parked and replayed after the decode. Only for signed-in players: a guest has no
# board to load, so their notes are simply dropped (not queued forever).
const _MAX_PENDING := 64
var _pending: Array = []          # [op, counter, value] taken before `loaded`

func _defer(op: String, name: String, value: int) -> bool:
	if _loaded:
		return false
	if FirebaseManager.is_signed_in() and _pending.size() < _MAX_PENDING:
		_pending.append([op, name, value])
	return true

func _replay_pending() -> void:
	var queued := _pending
	_pending = []
	for e in queued:
		match String(e[0]):
			"bump":  _bump(String(e[1]), int(e[2]))
			"raise": _raise(String(e[1]), int(e[2]))
			"lower": _lower(String(e[1]), int(e[2]))
			"diff":  _mark_diff_played(String(e[1]))

# Wipe the board when the UTC day has turned. Returns true if it did.
func _roll_if_new_day() -> bool:
	var today := _today()
	if _date == today:
		return false
	_date = today
	_counters = {}
	_claimed = {}
	return true

# ─── persistence ────────────────────────────────────────────────────────────

func _on_user_loaded() -> void:
	_loaded = true
	_decode(CoinsManager.raw_user_doc.get("daily_tasks", {}))
	# A stored board from an earlier day is dropped here, not carried over; the
	# reset write can wait for the first real progress (nothing is owed either way).
	_roll_if_new_day()
	_replay_pending()          # anything counted while the read was in flight
	changed.emit()

func _on_signed_out() -> void:
	_loaded = false
	_date = ""
	_counters = {}
	_claimed = {}
	_pending = []
	_dirty = false
	changed.emit()

func _decode(raw: Variant) -> void:
	_date = ""
	_counters = {}
	_claimed = {}
	if not (raw is Dictionary):
		return
	var d := raw as Dictionary
	_date = String(d.get("date", ""))
	var c: Variant = d.get("counters", {})
	if c is Dictionary:
		for k in (c as Dictionary).keys():
			_counters[String(k)] = int((c as Dictionary)[k])
	var cl: Variant = d.get("claimed", {})
	if cl is Dictionary:
		for k in (cl as Dictionary).keys():
			# Ignore ids that are no longer in the catalog, so a retired task can't
			# keep a dead key alive in the doc forever.
			if _by_id.has(String(k)):
				_claimed[String(k)] = true

func _state_for_save() -> Dictionary:
	return {"date": _date, "counters": _counters.duplicate(), "claimed": _claimed.duplicate()}

# Mark the board changed and schedule ONE deferred write, coalescing a burst of
# hooks (a game-over fires note_game_played + note_score back to back) into a
# single set_document. Never writes before `loaded` — see the WRITE note at the
# top for why that would be dangerous.
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
	var state := _state_for_save()
	CoinsManager.raw_user_doc["daily_tasks"] = state
	if _is_editor:
		return
	# merge=true → writes only `daily_tasks`, never clobbers the wallet fields.
	Firebase.firestore.set_document("users", uid, {"daily_tasks": state}, true)

# UTC calendar day, matching CoinsManager._today() so the tasks board and the
# daily claim turn over at the same instant for every player on earth.
func _today() -> String:
	var d := Time.get_date_dict_from_system(true)
	return "%04d-%02d-%02d" % [int(d["year"]), int(d["month"]), int(d["day"])]
