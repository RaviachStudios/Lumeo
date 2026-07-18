extends Control

# First-launch loading screen. Shown by GameManager before the home screen on
# every app open, so the wallet doc (coins, owned/equipped theme, daily-claim
# state, shop inventory) finishes loading from Firestore BEFORE the player lands
# on home — no more values popping in late. Solid #051438 backdrop with a fixed
# "Loading…" caption and a progress bar beneath it.
#
# Nothing here is animated in the tween/spinner sense. On the GL-compatibility
# renderer, shaders and scenes compile synchronously on their first draw, and each
# compile is a hard render-thread stall that delivers no frame — anything meant to
# move smoothly (a spinner, cycling caption dots, an eased bar) freezes and visibly
# jerks through those stalls. So the bar is driven by MILESTONES, not by time or a
# tween: it steps forward only when a real boot stage actually finishes. A stall
# therefore parks the bar mid-stage, which reads as honest progress rather than as
# a broken animation. The bar never moves backwards.
# The other loading screens in the app (shop, leaderboards) keep the plain still
# frame — they have no staged work to report.
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

# Bar geometry (centred under the caption).
const BAR_W := 260.0
const BAR_H := 10.0

# Milestone values. Each boot stage claims a slice; guests and devices without the
# billing plugin skip straight past their stage, so the bar jumps rather than
# creeping — that's intended, it mirrors work that genuinely wasn't needed.
const P_START := 0.06     # screen is up
const P_WALLET := 0.45    # wallet doc (coins / theme / daily / inventory) in hand
const P_BILLING := 0.70   # Play Billing prices resolved (or unavailable)
const P_BOARDS := 0.90    # leaderboard warm-up settled
const P_DONE := 1.0       # minimum-display hold elapsed, handing off to home

# How many discrete steps the last slice is walked across during the hold. Low on
# purpose: coarse steps read as staged progress, a fine-grained walk reads as a
# tween and shows every render stall.
const HOLD_STEPS := 5

var _bg: ColorRect
var _caption: Label
var _bar: ProgressBar
var _progress := 0.0
var _done := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # swallow taps while loading
	_build_background()
	_build_caption()
	_build_bar()
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

func _build_bar() -> void:
	# A plain ProgressBar with flat styleboxes: it repaints only when `value`
	# changes, so it costs nothing while a stage is grinding away.
	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 100.0
	_bar.value = 0.0
	_bar.show_percentage = false
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.09, 0.16, 0.36, 0.95)
	track.border_color = Color(0.30, 0.45, 1.0, 0.30)
	track.set_border_width_all(1)
	track.set_corner_radius_all(int(BAR_H * 0.5))
	_bar.add_theme_stylebox_override("background", track)

	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.42, 0.60, 1.0, 1.0)
	fill.set_corner_radius_all(int(BAR_H * 0.5))
	_bar.add_theme_stylebox_override("fill", fill)

	add_child(_bar)

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
		_caption.position = Vector2(cx - 160, cy - 28)
	if _bar:
		_bar.size = Vector2(BAR_W, BAR_H)
		_bar.position = Vector2(cx - BAR_W * 0.5, cy + 14)

# ---------------- progress ----------------

# Monotonic: a stage that resolves out of order (billing unavailable, boards already
# warm) can only ever push the bar forward, never snap it back.
func _set_progress(v: float) -> void:
	_progress = maxf(_progress, clampf(v, 0.0, 1.0))
	if _bar:
		_bar.value = _progress * 100.0

# ---------------- boot ----------------

func _run_boot() -> void:
	var start := Time.get_ticks_msec()
	_set_progress(P_START)
	# Signed-in players have a wallet doc to fetch; guests have nothing to load,
	# so for them this is purely the minimum-display delay.
	if FirebaseManager.is_signed_in():
		# Kick the leaderboard boards fetch FIRST so it flies in parallel with the
		# wallet and billing waits below — it costs us no extra wall-clock time
		# unless it's the slowest of the three. LeaderboardManager normally starts
		# this itself on sign-in; this covers the case where it hasn't (autoload
		# order) and is a no-op while a pass is already in flight.
		if not LeaderboardManager.warm_ready() and not LeaderboardManager.is_warming():
			LeaderboardManager.warm_boards()
		while not CoinsManager.is_loaded() and _elapsed(start) < MAX_SEC:
			await get_tree().process_frame
	_set_progress(P_WALLET)
	# Warm Google Play Billing here, while the loading screen is already up, so
	# the coin-pack popup opens with prices in place instead of flashing
	# "LOADING…" buttons. On devices without the billing plugin (editor,
	# emulator without Play Services) prices_ready stays false — the MAX_SEC
	# cap below stops us from blocking forever.
	if PurchaseManager.ensure_initialised():
		while not PurchaseManager.prices_ready() and _elapsed(start) < MAX_SEC:
			await get_tree().process_frame
	_set_progress(P_BILLING)
	# Finally wait out whatever's left of the board fetch kicked above, so the FIRST
	# visit to the leaderboards screen paints from the warm cache instead of showing
	# its own loading overlay. We drop out the moment the pass stops running, so a
	# failed fetch costs nothing extra (the screen just loads on open, as before);
	# MAX_SEC caps a stalled one.
	if FirebaseManager.is_signed_in():
		while LeaderboardManager.is_warming() and not LeaderboardManager.warm_ready() \
				and _elapsed(start) < MAX_SEC:
			await get_tree().process_frame
	_set_progress(P_BOARDS)
	# Whatever is left of the minimum-display hold. On a fast boot (and always for
	# guests, who have no wallet / boards to wait on) every stage above resolves at
	# once, so without this the bar would snap to P_BOARDS and sit dead for the whole
	# hold. Walk the last slice across the hold in a few COARSE steps — not a tween:
	# a render stall just makes one step land late instead of stuttering a smooth fill.
	var remaining := MIN_SEC - _elapsed(start)
	if remaining > 0.0:
		var steps := HOLD_STEPS
		var slice := remaining / float(steps)
		for i in steps:
			await get_tree().create_timer(slice).timeout
			if _done or not is_inside_tree():
				return
			_set_progress(P_BOARDS + (P_DONE - P_BOARDS) * (float(i + 1) / float(steps)))
	if _done or not is_inside_tree():
		return
	_done = true
	# Top the bar off and let one frame present it, so the hand-off doesn't cut
	# away from a bar visibly stuck short of full.
	_set_progress(P_DONE)
	await get_tree().process_frame
	if not is_inside_tree():
		return
	if game_manager:
		game_manager.show_home()

func _elapsed(start_ms: int) -> float:
	return float(Time.get_ticks_msec() - start_ms) / 1000.0
