extends Control

# First-launch loading screen. Shown by GameManager before the home screen on
# every app open, so the wallet doc (coins, owned/equipped theme, daily-claim
# state, shop inventory) finishes loading from Firestore BEFORE the player lands
# on home — no more values popping in late. Solid #051438 backdrop with a simple
# "Loading…" caption whose trailing dots cycle.
#
# Deliberately fully static — a single painted frame with NO animation of any kind
# (no spinner, and not even cycling dots). On the GL-compatibility renderer, shaders
# and scenes compile synchronously on their first draw, and each compile is a hard
# render-thread stall that delivers no frame. Anything meant to move — including a
# caption whose trailing dots change — freezes and visibly jerks during those stalls,
# so nothing here is meant to move: just a fixed "Loading…" caption on the brand navy.
# Every loading screen in the app shares this same still frame (shop, leaderboards).
#
# When the data is ready (or a safety timeout elapses) it calls
# game_manager.show_home(), which frees this screen.

var game_manager: Node

# #051438 brand navy.
const BG_COLOR := Color(0.0196, 0.0784, 0.2196)

# Minimum time the screen stays up (so it never flashes), and a hard cap so a
# stalled / silently-failing Firestore read can't trap the player here forever.
const MIN_SEC := 1.1
const MAX_SEC := 9.0

var _bg: ColorRect
var _caption: Label
var _done := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # swallow taps while loading
	_build_background()
	_build_caption()
	_layout()
	get_viewport().size_changed.connect(_layout)
	_run_boot()

# ---------------- build ----------------

func _build_background() -> void:
	# Under a CanvasLayer anchors give no size, so the solid fill is sized in
	# _layout(). Opaque, so any theme BackgroundManager paints beneath stays hidden
	# until the player actually reaches home.
	_bg = ColorRect.new()
	_bg.color = BG_COLOR
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

func _build_caption() -> void:
	_caption = Label.new()
	_caption.text = "Loading…"
	_caption.add_theme_font_size_override("font_size", 24)
	_caption.add_theme_color_override("font_color", Color(0.78, 0.84, 1.0, 0.92))
	_caption.add_theme_color_override("font_shadow_color", Color(0.30, 0.45, 1.0, 0.35))
	_caption.add_theme_constant_override("shadow_offset_x", 0)
	_caption.add_theme_constant_override("shadow_offset_y", 0)
	_caption.add_theme_constant_override("shadow_outline_size", 6)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_caption)

# ---------------- layout ----------------

func _layout() -> void:
	var sz := get_viewport_rect().size
	var cx := sz.x * 0.5
	var cy := sz.y * 0.5
	if _bg:
		_bg.position = Vector2.ZERO
		_bg.size = sz
	if _caption:
		_caption.size = Vector2(320, 32)
		_caption.position = Vector2(cx - 160, cy - 16)

# ---------------- boot ----------------

func _run_boot() -> void:
	var start := Time.get_ticks_msec()
	# Signed-in players have a wallet doc to fetch; guests have nothing to load,
	# so for them this is purely the minimum-display delay.
	if FirebaseManager.is_signed_in():
		while not CoinsManager.is_loaded() and _elapsed(start) < MAX_SEC:
			await get_tree().process_frame
	# Warm Google Play Billing here, while we're already showing a spinner, so
	# the coin-pack popup opens with prices in place instead of flashing
	# "LOADING…" buttons. On devices without the billing plugin (editor,
	# emulator without Play Services) prices_ready stays false — the MAX_SEC
	# cap below stops us from blocking forever.
	if PurchaseManager.ensure_initialised():
		while not PurchaseManager.prices_ready() and _elapsed(start) < MAX_SEC:
			await get_tree().process_frame
	var remaining := MIN_SEC - _elapsed(start)
	if remaining > 0.0:
		await get_tree().create_timer(remaining).timeout
	if _done or not is_inside_tree():
		return
	_done = true
	if game_manager:
		game_manager.show_home()

func _elapsed(start_ms: int) -> float:
	return float(Time.get_ticks_msec() - start_ms) / 1000.0
