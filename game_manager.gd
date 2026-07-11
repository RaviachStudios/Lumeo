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
const ArenaScreen := preload("res://arena_screen.gd")
const ContestCreateScreen := preload("res://contest_create_screen.gd")
const ContestDetailScreen := preload("res://contest_detail_screen.gd")
const ContestLobbyScreen := preload("res://contest_lobby_screen.gd")

var _current: Control = null
var _canvas: CanvasLayer
# Set once the home screen has shown the "sign in or play as guest" welcome
# prompt. Lives here (the persistent root) so it survives home-screen rebuilds
# and the prompt only appears on the first home open of an app launch.
var welcome_prompt_shown := false

# --- pause/resume GL-context stability ---
# On Android our surface can be torn down and its EGL/GL context recreated
# whenever another activity covers us (most notably the Google Sign-In dialog).
# Doing heavy GL work on the resume frame — compiling shaders, uploading
# textures, baking offscreen SubViewports (see BackgroundManager / simon_wheel)
# — can dereference an invalid render target and segfault the GL thread on
# Adreno. We track background state here and expose await_gl_stable() so callers
# can defer such work until the context is proven good again.
signal app_resumed
var _app_paused := false
# Set on pause, cleared once we've confirmed the restored context can render.
var _resume_pending := false
# Completed frames to let render with a valid context before heavy GL work is
# considered safe. frame_post_draw only fires after a successful GPU frame, so
# each one is proof the context is alive.
const _RESUME_SETTLE_FRAMES := 2

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas = $ScreenCanvas
	await get_tree().process_frame
	# Boot through the loading screen so the wallet/theme/shop data is ready before
	# home appears. It calls show_home() itself once loading completes.
	show_loading()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			if _current is HomeScreen:
				get_tree().quit()
			else:
				show_home()
		NOTIFICATION_APPLICATION_PAUSED:
			_app_paused = true
			_resume_pending = true
		NOTIFICATION_APPLICATION_RESUMED:
			_app_paused = false
			app_resumed.emit()

# Awaits until the app is foregrounded AND a few frames have rendered against a
# valid GL context, so callers can safely (re)build screens or bake textures
# after a pause/resume. A cheap no-op when we were never backgrounded.
func await_gl_stable() -> void:
	while _app_paused:
		await app_resumed
	if _resume_pending:
		for _i in _RESUME_SETTLE_FRAMES:
			await RenderingServer.frame_post_draw
		_resume_pending = false

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

func show_arena() -> void:
	_swap(ArenaScreen.new())

func show_contest_create() -> void:
	_swap(ContestCreateScreen.new())

func show_contest_lobby() -> void:
	_swap(ContestLobbyScreen.new())

func show_contest_detail(contest_id: String) -> void:
	var s := ContestDetailScreen.new()
	s.contest_id = contest_id
	_swap(s)

func show_loading() -> void:
	_swap(LoadingScreen.new())

func show_home() -> void:
	# Any return home ends a contest game context (an abandoned contest game must
	# never leak into a later normal game).
	GameState.contest_context = {}
	_swap(HomeScreen.new())

func show_difficulty() -> void:
	# Normal-play entry point: guarantee no stale contest context.
	GameState.contest_context = {}
	_swap(DifficultyScreen.new())

func show_how_to_play() -> void:
	_swap(HowToPlayScreen.new())

func show_game() -> void:
	_swap(GameScreen.new())

func show_game_over(rounds: int) -> void:
	var s := GameOverScreen.new()
	s.rounds = rounds
	_swap(s)
