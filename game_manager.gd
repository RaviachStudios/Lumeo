extends Control

const LoadingScreen := preload("res://loading_screen.gd")
const HomeScreen := preload("res://home_screen.gd")
const DifficultyScreen := preload("res://difficulty_screen.gd")
const HowToPlayScreen := preload("res://how_to_play.gd")
const GameScreen := preload("res://game.gd")
const GameOverScreen := preload("res://game_over.gd")
const NamePickerScreen := preload("res://name_picker_screen.gd")
const LeaderboardsScreen := preload("res://leaderboards_screen.gd")
const ShopScreen := preload("res://shop_screen.gd")

var _current: Control = null
var _canvas: CanvasLayer
# Set once the home screen has shown the "sign in or play as guest" welcome
# prompt. Lives here (the persistent root) so it survives home-screen rebuilds
# and the prompt only appears on the first home open of an app launch.
var welcome_prompt_shown := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas = $ScreenCanvas
	await get_tree().process_frame
	# Boot through the loading screen so the wallet/theme/shop data is ready before
	# home appears. It calls show_home() itself once loading completes.
	show_loading()

func _notification(what: int) -> void:
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
	# Equipped shop themes are painted only behind the gameplay screen; every other
	# screen wears its own background. Toggle BEFORE the screen builds so its _ready()
	# reads the correct BackgroundManager.is_themed().
	BackgroundManager.set_active(screen is GameScreen)
	_canvas.add_child(_current)

func show_name_picker() -> void:
	_swap(NamePickerScreen.new())

func show_leaderboards() -> void:
	_swap(LeaderboardsScreen.new())

func show_shop() -> void:
	_swap(ShopScreen.new())

func show_loading() -> void:
	_swap(LoadingScreen.new())

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
