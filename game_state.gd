extends Node

# Set by ContestManager.begin_contest_game when a game is launched from inside an
# Arena contest; empty {} for normal play. Shape: {id, type, difficulty,
# best_before, games_before}. game.gd reads it to switch to "Forfeit" framing;
# game_over.gd captures + clears it, submits the contest result, and routes back
# to the contest. Cleared on any return to home / difficulty so a stale context
# can never make a normal game count toward a contest.
var contest_context: Dictionary = {}

var difficulty: String = "easy"
var num_colors: int = 4
var flash_time: float = 0.7
var flash_gap: float = 0.25
var speed_increase: float = 0.008

# In-memory mirror of the player's per-difficulty high scores. For signed-in
# users this mirrors the Firestore leaderboard row (the source of truth);
# for guests it mirrors the local file at GUEST_SAVE_PATH (the guest-only
# fallback, since unsigned users have no leaderboard row to read).
var high_scores: Dictionary = {"easy": 0, "moderate": 0, "hard": 0}

# Tracks whether we've already pulled the signed-in user's leaderboard rows
# into the cache, so a sign-out/sign-in toggle re-fetches them.
var _hydrated: bool = false

# Guest-only persistence. Signed-in users never touch this file — their truth
# lives on Firestore. The file stays around across sign-in/sign-out cycles so
# a guest who signs in, plays, then signs out, still finds their pre-sign-in
# bests intact.
const GUEST_SAVE_PATH := "user://highscores.cfg"

func _ready() -> void:
	FirebaseManager.signed_in.connect(_on_signed_in)
	FirebaseManager.signed_out.connect(_on_signed_out)
	# GameState autoloads before FirebaseManager, so the editor-sim cached
	# profile isn't applied yet — defer one frame so is_signed_in() is honest.
	call_deferred("_init_from_storage")

func set_difficulty(diff: String) -> void:
	difficulty = diff
	match diff:
		"easy":
			num_colors = 4
			flash_time = 0.7
			flash_gap = 0.25
			speed_increase = 0.008
		"moderate":
			num_colors = 5
			flash_time = 0.55
			flash_gap = 0.18
			speed_increase = 0.022
		"hard":
			num_colors = 6
			flash_time = 0.42
			flash_gap = 0.13
			speed_increase = 0.038

func get_high_score() -> int:
	return high_scores.get(difficulty, 0) as int

# Returns true if this is a new high score for the current difficulty.
# Updates the in-memory cache immediately. For guests we also persist to the
# fallback file; for signed-in users the caller is responsible for pushing the
# score to LeaderboardManager (game_over.gd does this so it can read the
# player's rank back in the same flow).
func submit_score(rounds: int) -> bool:
	var prev: int = high_scores.get(difficulty, 0) as int
	if rounds > prev:
		high_scores[difficulty] = rounds
		if not FirebaseManager.is_signed_in():
			_save_guest_scores()
		return true
	return false

func _init_from_storage() -> void:
	if FirebaseManager.is_signed_in():
		_hydrate_from_leaderboard()
	else:
		_load_guest_scores()

func _on_signed_in(_uid: String, _display_name: String) -> void:
	# A new sign-in belongs to a different player — drop any guest highs
	# from the in-memory cache before pulling fresh values from Firestore.
	# The guest file is left untouched so a later sign-out can restore it.
	high_scores = {"easy": 0, "moderate": 0, "hard": 0}
	_hydrated = false
	_hydrate_from_leaderboard()

func _on_signed_out() -> void:
	# Sign-out drops back to guest mode: reload the pre-existing guest file
	# (if any) so the player isn't shown a reset 0 best.
	high_scores = {"easy": 0, "moderate": 0, "hard": 0}
	_hydrated = false
	_load_guest_scores()

func _hydrate_from_leaderboard() -> void:
	if _hydrated:
		return
	_hydrated = true
	for diff in ["easy", "moderate", "hard"]:
		var s: int = await LeaderboardManager.get_my_score(diff)
		high_scores[diff] = s

func _save_guest_scores() -> void:
	var cfg := ConfigFile.new()
	for key: String in high_scores:
		cfg.set_value("scores", key, high_scores[key])
	cfg.save(GUEST_SAVE_PATH)

func _load_guest_scores() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(GUEST_SAVE_PATH) != OK:
		return
	for key: String in high_scores:
		high_scores[key] = cfg.get_value("scores", key, 0)
