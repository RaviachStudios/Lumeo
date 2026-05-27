extends Node

var difficulty: String = "easy"
var num_colors: int = 4
var flash_time: float = 0.7
var flash_gap: float = 0.25
var speed_increase: float = 0.008

var high_scores: Dictionary = {"easy": 0, "moderate": 0, "hard": 0}

const SAVE_PATH := "user://highscores.cfg"

func _ready() -> void:
	_load_scores()

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

# Returns true if this is a new high score
func submit_score(rounds: int) -> bool:
	var prev: int = high_scores.get(difficulty, 0) as int
	if rounds > prev:
		high_scores[difficulty] = rounds
		_save_scores()
		return true
	return false

func _save_scores() -> void:
	var cfg := ConfigFile.new()
	for key: String in high_scores:
		cfg.set_value("scores", key, high_scores[key])
	cfg.save(SAVE_PATH)

func _load_scores() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for key: String in high_scores:
		high_scores[key] = cfg.get_value("scores", key, 0)
