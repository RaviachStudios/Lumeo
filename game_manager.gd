extends Node

const HomeScreen := preload("res://home_screen.gd")
const DifficultyScreen := preload("res://difficulty_screen.gd")
const HowToPlayScreen := preload("res://how_to_play.gd")
const GameScreen := preload("res://game.gd")
const GameOverScreen := preload("res://game_over.gd")

var _current: Control = null
var _root_ui: Control

func _ready() -> void:
	_root_ui = Control.new()
	_root_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().root.call_deferred("add_child", _root_ui)
	await get_tree().process_frame
	await get_tree().process_frame
	show_home()

func _notification(what: int) -> void:
	# Android back button — go to home or quit
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _current is HomeScreen:
			get_tree().quit()
		else:
			show_home()

func _swap(screen: Control) -> void:
	if _current:
		_current.queue_free()
	_current = screen
	_current.game_manager = self
	_root_ui.add_child(_current)

func show_home() -> void:
	_swap(HomeScreen.new())

func show_difficulty() -> void:
	_swap(DifficultyScreen.new())

func show_how_to_play() -> void:
	_swap(HowToPlayScreen.new())

func show_game() -> void:
	_swap(GameScreen.new())

func show_game_over(rounds: int) -> void:
	var s := GameOverScreen.new()
	s.rounds = rounds
	_swap(s)
