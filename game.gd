extends Control

var game_manager: Node

const BUTTON_COLORS := [
	Color(0.9, 0.15, 0.15),   # Red
	Color(0.15, 0.8, 0.15),   # Green
	Color(0.15, 0.35, 0.95),  # Blue
	Color(0.95, 0.85, 0.1),   # Yellow
	Color(0.95, 0.5,  0.1),   # Orange
	Color(0.95, 0.3,  0.7),   # Pink
]
const BG_TOP := Color(0.05, 0.05, 0.15)
const BG_BOT := Color(0.02, 0.08, 0.22, 1.0)

# Shared width for the top-right Quit button and the coins pill directly beneath
# it, so their right edges align AND they read as the same-width column.
const HUD_RIGHT_BTN_W := 114.0
const HUD_RIGHT_MARGIN := 20.0

# ---------------------------------------------------------------------------
# THE HUD'S LANES
# ---------------------------------------------------------------------------
# The play screen is a 3D board with a flat HUD drawn on top of it, and until this
# existed the two were laid out in ignorance of each other. That cost two defects
# that tools/play_fit.tscn now measures directly, both of them on every level and
# every difficulty:
#
#   * the "Your turn!" pill was drawn OVER one or two buttons on every skin. A
#     button under an opaque pill is as unavailable as one off the screen — this is
#     a game whose entire input is tapping buttons;
#   * and on Ice Kingdom the bottom row ran forty pixels past the bottom edge,
#     because the board's framing preference (BackgroundScenes.frame_bias) was two
#     free numbers that nobody checked against the size of the viewport.
#
# So the pill's lane is declared here, published to the board (set_hud_insets) and
# the board is framed INSIDE what is left. The numbers are the pill's own geometry
# rather than a guessed margin, so moving the pill moves the board.
const STATUS_H := 48.0            # the pill's height
const STATUS_BOTTOM := 16.0       # ...its gap to the bottom edge
const STATUS_CLEAR := 12.0        # ...and the air between it and the nearest button

# The top-right column (close dome, coins) and the top-left (watch-ad) both start
# here, and the board is kept out of neither: it is held off both SIDES by
# _fit_camera's own width reserve, and the corners are where that reserve puts the
# room. tools/play_fit.tscn asserts the corners stay clear per button, per board,
# per aspect — which is the check that makes it safe not to spend a top lane.
const HUD_TOP_MARGIN := 20.0
const STATUS_FONT := 26

# The height this HUD is AUTHORED at. Below it the HUD scales down with the frame;
# at or above it nothing scales, so every shipping device sees the HUD exactly as
# drawn (project.godot stretches canvas_items/expand from a 1280x720 base, which
# keeps the viewport height at 720 or more on any real screen — width is what
# varies).
#
# It exists because the HUD is in absolute pixels and the board is a fraction of
# the frame, so on any viewport SHORTER than the design height the HUD grows
# relative to the board it is drawn over. tools/play_fit.tscn caught exactly that
# at 960x540: the close dome, unchanged at 52 px, is 9.6 % of that frame against
# 7.2 % of a 720 one, and it reached far enough into the board to cover a button.
const HUD_BASE_H := 720.0
# The close dome's diameter at the design height. Named here rather than left a
# local in _build_hud because _layout_hud has to re-derive it on every resize.
const QUIT_D := 52.0


# 1.0 at the design height and above; proportional below it.
func _hud_scale() -> float:
	return clampf(get_viewport_rect().size.y / HUD_BASE_H, 0.70, 1.0)

var num_buttons: int
var sequence: Array[int] = []
var player_seq: Array[int] = []
var level: int = 0
var replays: int = 3
var flash_time: float
var flash_gap: float
var speed_inc: float

# The play device. Every difficulty now plays on a modelled physical board: easy
# on the three-button EasyGameUI triangle, moderate on the five-button MemoryGameUI
# pentagon, hard on the six-button HardGameUI hexagon — the latter two being
# MemoryGameUI subclasses, so all three are the same class with a different board
# spec. The procedural four-colour SimonWheel is no longer a play device on any
# difficulty (it still backs the shop's preview wheels).
#
# Still deliberately untyped: everything below only ever calls the shared API
# (configure / apply_skin / set_lit / set_press / segment_at_point / set_level /
# the skin flourishes), and the name is kept so the ~40 call sites below did not
# have to churn.
var _wheel
var _state: String = "idle"  # idle, showing, input, gameover
var _last_input_frame: int = -1
# True when this game was launched from inside an Arena contest (GameState holds
# the contest context). Changes Quit -> Forfeit framing and makes the game-over
# flow route back to the contest + record the result.
var _is_contest: bool = false

var _status_lbl: Label
var _status_panel: Control
var _quit_btn: Button
var _watch_ad_btn: Button
# Coins HUD: a top-center pill showing the coins earned THIS session (starts at
# 0). The "+ N" indicator is spawned next to it whenever a level completes; we
# keep a reference so multiple awards in quick succession don't pile up on top
# of each other. The session total is banked into the wallet at game over.
var _coin_panel: Panel
var _coin_lbl: Label
var _coin_icon: Control
var _earn_indicator: Label

# The Watch-Ad button used to run an idle "attention nudge" — an aura, a sweeping
# bolt of light and a heartbeat swell — whenever the player paused mid-round. It
# was removed deliberately: it is an animation whose only purpose is to pull the
# eye onto an ad entry point during play, which is what the publisher policies
# call encouraging clicks. The button now sits completely passive and is offered
# on its own merits.

# Arena race extras (only active when _is_contest).
const PRESS_LIMIT := 10.0          # seconds allowed to make each next press
var _rng := RandomNumberGenerator.new()   # room-seeded so all racers share the sequence
var _press_active := false          # is the per-press timer currently counting?
var _press_deadline := 0.0          # ticks-seconds by which the next press must land
var _countdown_lbl: Label           # big side 3-2-1 shown in the final seconds

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_is_contest = GameState.contest_context.has("id")
	# Seed the sequence RNG from the room so every racer sees the identical pattern.
	if _is_contest:
		_rng.seed = int(GameState.contest_context.get("seed", 0))
	num_buttons = GameState.num_colors
	flash_time = GameState.flash_time
	flash_gap = GameState.flash_gap
	speed_inc = GameState.speed_increase
	# The 3D play device (rendered via SubViewport). Added before the HUD so it
	# sits behind the labels/buttons; it ignores mouse input - taps are handled
	# here. One modelled board per difficulty: three buttons on easy, five on
	# moderate, six on hard.
	var board: MemoryGameUI
	match GameState.difficulty:
		"hard":
			board = HardGameUI.new()
		"moderate":
			board = MemoryGameUI.new()
		_:
			board = EasyGameUI.new()
	# The board can hit-test and react to its own taps, but a press is only
	# legal during the player's turn and never behind the quit dialog. That
	# policy lives in _input below, so its own handler stays off and there is
	# no second, ungated path into _player_pressed.
	board.input_enabled = false
	_wheel = board
	add_child(_wheel)
	_layout_wheel()
	_wheel.configure(num_buttons, BUTTON_COLORS)
	_apply_simon_skin()
	get_viewport().size_changed.connect(_relayout)
	_build_hud()
	# The rewarded "watch ads for replay" ad is the ONLY source of replays (they
	# start at 0), so it's offered during arena races too — where the 10s per-press
	# window is running the whole time the ad is on screen. Both clocks here are
	# wall-clock, so the ad silently eats the window and the player was knocked out
	# the instant it closed. Credit the lost time back instead.
	AdManager.ad_closed.connect(_on_ad_closed)
	await get_tree().process_frame
	_start_game()

# An ad just came down after `seconds_shown` on screen. Nothing about the game
# advanced while it was up, so neither should the deadlines that measure it.
func _on_ad_closed(seconds_shown: float) -> void:
	if seconds_shown <= 0.0:
		return
	if _press_active:
		_press_deadline += seconds_shown

func _process(_dt: float) -> void:
	# Nothing on this screen should advance behind a full-screen ad. Most Android
	# builds pause the loop anyway, but that is the plugin's behaviour rather than a
	# guarantee, and the one thing that must NOT happen while the player can't see
	# the wheel is the press window timing out under the ad.
	if AdManager.is_showing_ad():
		return

	# Ad loads asynchronously — update button visibility whenever it becomes ready
	if _watch_ad_btn and _state == "input":
		_watch_ad_btn.visible = AdManager.rewarded_ready

	# Arena race: per-press 10s window with a 3-2-1 side countdown; miss it -> over.
	if _is_contest and _press_active and _state == "input":
		var remaining := _press_deadline - _now_secs()
		if remaining <= 0.0:
			_on_press_timeout()
		elif remaining <= 3.0:
			if _countdown_lbl:
				_countdown_lbl.visible = true
				_countdown_lbl.text = str(int(ceil(remaining)))
		elif _countdown_lbl:
			_countdown_lbl.visible = false

func _now_secs() -> float:
	return Time.get_ticks_msec() / 1000.0

func _draw() -> void:
	# When a shop theme is equipped, BackgroundManager fills the viewport;
	# drawing our own gradient would obscure it.
	if BackgroundManager.is_themed():
		return
	var sz := get_viewport_rect().size
	# Background gradient (the wheel composites on top with a transparent backdrop)
	for y in range(0, int(sz.y), 4):
		var t := float(y) / sz.y
		draw_line(Vector2(0,y), Vector2(sz.x,y), BG_TOP.lerp(BG_BOT, t), 4.0)
	# Subtle grid lines
	for x in range(0, int(sz.x), 80):
		draw_line(Vector2(x,0), Vector2(x,sz.y), Color(1,1,1,0.025), 1.0)
	for y in range(0, int(sz.y), 80):
		draw_line(Vector2(0,y), Vector2(sz.x,y), Color(1,1,1,0.025), 1.0)

# Give the modelled board the whole viewport; it frames itself inside it.
# Re-lay EVERYTHING the viewport's size decides, in the one order that works: the
# HUD's lanes are computed first, published to the board second, and the board
# fitted third — a board framed against a HUD that has not moved yet is framed
# against the last viewport.
#
# It runs on every resize, and before this it did not exist: `size_changed` was
# wired straight to _layout_wheel, so the board re-fitted and the close dome, the
# status pill, the coin pill and the quit dialog all stayed where the FIRST layout
# had put them. Shrink the window and the close button is outside it.
func _relayout() -> void:
	_layout_hud()
	_layout_wheel()


# Where every flat control on the play screen goes, as a function of the viewport
# and the device's safe area. Called from _build_hud and from every resize; nothing
# here may be positioned anywhere else.
func _layout_hud() -> void:
	var sz := get_viewport_rect().size
	var safe := _safe_insets()
	var k := _hud_scale()
	var left := HUD_TOP_MARGIN * k + safe.x
	var right := HUD_RIGHT_MARGIN * k + safe.z
	var top := HUD_TOP_MARGIN * k + safe.y
	if _watch_ad_btn != null:
		_watch_ad_btn.position = Vector2(left, top)
	if _quit_btn != null:
		_quit_btn.size = Vector2(QUIT_D, QUIT_D) * k
		_quit_btn.position = Vector2(sz.x - _quit_btn.size.x - right, top)
		_quit_btn.queue_redraw()
	if _coin_panel != null:
		_coin_panel.position = Vector2(sz.x - _coin_panel.size.x - right,
			top + 58.0 * k)
	if _countdown_lbl != null:
		_layout_countdown(sz)
	var dlg := get_node_or_null("QuitDialog") as Control
	if dlg != null:
		dlg.position = Vector2(roundf(sz.x * 0.5 - dlg.size.x * 0.5),
			roundf(sz.y * 0.5 - dlg.size.y * 0.5))
	_layout_status(sz)
	# ...and the board is framed inside what the HUD left. The pill's lane is its
	# own height plus its two margins — measured, not guessed, so that a change to
	# the pill moves the buttons rather than quietly starting to cover them.
	if _wheel != null:
		_wheel.set_hud_insets(0.0,
			(STATUS_BOTTOM + STATUS_H + STATUS_CLEAR) * k + safe.w)


# The status pill, sized to its text and seated in its lane. Split out of
# _set_status so that a resize re-seats it without needing the text to change.
func _layout_status(sz: Vector2) -> void:
	if _status_panel == null or _status_lbl == null:
		return
	var safe := _safe_insets()
	var k := _hud_scale()
	var fs := int(roundf(STATUS_FONT * k))
	_status_lbl.add_theme_font_size_override("font_size", fs)
	var font := _status_lbl.get_theme_font("font")
	var tw: float = font.get_string_size(_status_lbl.text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var ph := STATUS_H * k
	var pw: float = clampf(maxf(180.0 * k, tw + 60.0 * k),
		180.0 * k, maxf(200.0, sz.x - 80.0))
	_status_panel.size = Vector2(roundf(pw), roundf(ph))
	_status_panel.position = Vector2(roundf(sz.x * 0.5 - pw * 0.5),
		roundf(sz.y - (STATUS_BOTTOM + STATUS_H) * k - safe.w))
	_status_lbl.position = Vector2.ZERO
	_status_lbl.size = _status_panel.size


# The device's safe area — a notch, a cutout, a gesture bar — as insets in VIEWPORT
# pixels (left, top, right, bottom).
#
# The conversion matters: the safe area comes back in real window pixels and this
# project stretches (canvas_items / expand, 1280x720 base), so a 90 px cutout on a
# 2400-wide phone is 48 px of viewport, not 90. Mobile only — on desktop
# get_display_safe_area returns the whole SCREEN, which against a smaller window
# yields nonsense insets rather than zero.
func _safe_insets() -> Vector4:
	if not OS.has_feature("mobile"):
		return Vector4.ZERO
	var win := DisplayServer.window_get_size()
	if win.x <= 0 or win.y <= 0:
		return Vector4.ZERO
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.x <= 0 or safe.size.y <= 0:
		return Vector4.ZERO
	var vp := get_viewport_rect().size
	var sx := vp.x / float(win.x)
	var sy := vp.y / float(win.y)
	return Vector4(
		maxf(float(safe.position.x), 0.0) * sx,
		maxf(float(safe.position.y), 0.0) * sy,
		maxf(float(win.x - safe.end.x), 0.0) * sx,
		maxf(float(win.y - safe.end.y), 0.0) * sy)


func _layout_wheel() -> void:
	if _wheel == null:
		return
	var sz := get_viewport_rect().size
	# A modelled board is a wide tabletop seen in perspective, not a disc, so it
	# gets the WHOLE viewport instead of the centred square the old wheel took — a
	# square would waste the sides and shrink the buttons for nothing. Each board
	# fits its own framing to whatever rect it is given (MemoryGameUI._fit_camera),
	# and all three leave the bottom centre clear for the status pill (the pentagon
	# through its open front, the hexagon and the triangle through their fitted
	# vertical bands).
	_wheel.size = sz
	_wheel.position = Vector2.ZERO
	_layout_countdown(sz)

# Position the big 3-2-1 side countdown on the right edge, vertically centred.
func _layout_countdown(sz: Vector2) -> void:
	if _countdown_lbl == null:
		return
	_countdown_lbl.size = Vector2(140, 140)
	_countdown_lbl.position = Vector2(sz.x - 160.0, sz.y * 0.5 - 70.0)

# Apply the player's equipped board customization (the retired per-part colours, or
# the SPECIAL SKINS tab) to the play device. CoinsManager is already loaded by the time a game
# starts (the home screen waits on CoinsManager.loaded), so the equipped look
# is available immediately. In skin mode the active skin overrides every per-part
# colour with its own bespoke palette + overlay (e.g. inferno's ring of flames).
func _apply_simon_skin() -> void:
	if _wheel == null:
		return
	var skin_id := CoinsManager.selected_skin if not CoinsManager.is_simon_manual() else ""
	_wheel.apply_skin(
		_resolved_simon_tint("outer_circle"),
		_resolved_simon_tint("inner_circle"),
		_resolved_simon_number(),
		skin_id)

# Returns the look for a category (Color, pattern/motif Dictionary, or null to
# keep the stock graphite look). See CoinsManager.simon_part_style.
func _resolved_simon_tint(category: String) -> Variant:
	if not CoinsManager.is_simon_manual():
		return null
	return CoinsManager.simon_part_style(category, CoinsManager.equipped_simon_color(category))

# The equipped level-number font package, or null for the stock white numeral
# (mirrors _resolved_simon_tint but resolves the font catalog instead of a colour).
func _resolved_simon_number() -> Variant:
	if not CoinsManager.is_simon_manual():
		return null
	var id := CoinsManager.equipped_simon_color("level_number")
	if id == CoinsManager.SIMON_DEFAULT_FONT:
		return null
	return CoinsManager.simon_number_font(id)

func _input(event: InputEvent) -> void:
	if _state != "input" or get_node("QuitDialog").visible:
		return
	var tap_pos := Vector2(-1, -1)
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			tap_pos = mb.position
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			tap_pos = st.position
	if tap_pos.x < 0:
		return
	# emulate_touch_from_mouse fires both MouseButton and ScreenTouch for one
	# click — guard against double-processing in the same frame
	var frame := Engine.get_process_frames()
	if frame == _last_input_frame:
		return
	_last_input_frame = frame
	var btn: int = _wheel.segment_at_point(tap_pos - _wheel.position)
	if btn >= 0:
		_player_pressed(btn)
		get_viewport().set_input_as_handled()

func _build_hud() -> void:
	var sz := get_viewport_rect().size

	# "Watch a video to replay" — a physical glossy amber push-button pill. The
	# label states the required action in full BEFORE the ad, which the rewarded-ad
	# policy requires and "Watch ads for replay" only half did. The dome + label are
	# drawn by watch_ad_button.gd; it also sizes itself to the text with generous
	# padding in _ready.
	#
	# It lives in the top-LEFT corner, the point furthest from the play device: every
	# board is fitted into a band that leaves the top corners clear at any viewport
	# aspect (the acceptance harnesses check exactly that, per button, per board).
	# Taps during a round land on a button and nowhere near here, which is the whole
	# point — an ad control must not sit inside the area a player is repeatedly
	# hitting.
	_watch_ad_btn = (load("res://watch_ad_button.gd") as GDScript).new()
	_watch_ad_btn.text = "Watch a video to replay"
	_watch_ad_btn.position = Vector2(20, 20)
	_watch_ad_btn.focus_mode = Control.FOCUS_NONE
	_watch_ad_btn.pressed.connect(_on_watch_ad)
	_watch_ad_btn.visible = false
	add_child(_watch_ad_btn)

	# Quit — a physical glossy red push-button dome with a white ✕, top-right.
	_quit_btn = (load("res://close_button.gd") as GDScript).new()
	_quit_btn.position = Vector2(sz.x - QUIT_D - HUD_RIGHT_MARGIN, 20)
	_quit_btn.size = Vector2(QUIT_D, QUIT_D)
	_quit_btn.focus_mode = Control.FOCUS_NONE
	_quit_btn.pressed.connect(_on_quit)
	add_child(_quit_btn)

	# Status line below the wheel, set inside an elegant dark-glass pill so the
	# prompt reads as a deliberate readout instead of floating text.
	_build_status_bar(sz)

	# (Coins earned are still tracked + banked at game over via CoinsManager; the
	# on-screen coins pill was removed from the play screen.)
	_build_quit_dialog(sz)
	# Everything above is CONSTRUCTED at a nominal size; this is what actually
	# places it, and it is the same call every resize makes.
	_layout_hud()

	# Arena race: a big glowing 3-2-1 that appears on the side in the last 3s of a
	# press window. Hidden by default; _process toggles + updates it.
	if _is_contest:
		_countdown_lbl = Label.new()
		_countdown_lbl.add_theme_font_size_override("font_size", 96)
		_countdown_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		_countdown_lbl.add_theme_color_override("font_outline_color", Color(0.3, 0.08, 0.0))
		_countdown_lbl.add_theme_constant_override("outline_size", 10)
		_countdown_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_countdown_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_countdown_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_countdown_lbl.visible = false
		add_child(_countdown_lbl)
		_layout_countdown(sz)

# A raised, glossy 3D button. The face is `base`; a thick darker bottom border acts
# as the button's "side", a bright top border is the highlight, and a drop shadow
# grounds it. On press the side shrinks and the face darkens so it visibly sinks.
# `corner` sets the corner radius (pass half the height for a circle/pill).
func _solid3d_btn(btn: Button, base: Color, fg: Color, corner: int) -> void:
	var side := base.darkened(0.55)       # dark lower edge = the button's depth
	var s := StyleBoxFlat.new()
	s.bg_color = base
	s.set_corner_radius_all(corner)
	s.border_color = side
	s.border_width_top = 2                # thin bright cap so the top edge catches light
	s.border_width_left = 2
	s.border_width_right = 2
	s.border_width_bottom = 9             # tall raised "wall" under the face → chunky 3D
	s.shadow_color = Color(0, 0, 0, 0.55) # soft cast shadow grounds the button
	s.shadow_size = 12
	s.shadow_offset = Vector2(0, 8)       # lifts the button well off the screen
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_bottom = 3           # optical-centre the label above the thick wall
	btn.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = base.lightened(0.12)    # brighter face on hover
	sh.shadow_size = 16
	sh.shadow_offset = Vector2(0, 10)     # floats a touch higher
	btn.add_theme_stylebox_override("hover", sh)
	# Pressed: the wall collapses and the whole button drops down into its shadow.
	var sp := s.duplicate() as StyleBoxFlat
	sp.bg_color = base.darkened(0.18)
	sp.border_width_bottom = 2
	sp.shadow_size = 3
	sp.shadow_offset = Vector2(0, 2)
	sp.content_margin_top = 7             # shove the label down as the face sinks ~7px
	sp.content_margin_bottom = 0
	btn.add_theme_stylebox_override("pressed", sp)
	var sd := s.duplicate() as StyleBoxFlat
	sd.bg_color = base.darkened(0.35)
	sd.border_color = side.darkened(0.2)
	sd.shadow_color = Color(0, 0, 0, 0.3)
	btn.add_theme_stylebox_override("disabled", sd)
	btn.add_theme_color_override("font_color", fg)
	btn.add_theme_color_override("font_hover_color", fg)
	btn.add_theme_color_override("font_pressed_color", fg)

# Status prompt below the wheel, housed in a soft dark-glass pill that auto-fits
# the text width (kept centred). Built once; _set_status() updates the text.
func _build_status_bar(sz: Vector2) -> void:
	# DRAWN, not styled. It was a Panel with a flat StyleBoxFlat — one colour, a
	# hairline border, a soft shadow — which is the only control on this screen that
	# was not drawn, and against a live 3D board wearing a bespoke skin it read as a
	# debug label. status_pill.gd gives it the LEVEL badge's own language and the
	# badge's own palette, so the two dark-glass readouts in opposite corners of the
	# frame read as a set instead of as two different ideas.
	_status_panel = (load("res://status_pill.gd") as GDScript).new()
	_status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status_panel)

	_status_lbl = Label.new()
	_status_lbl.add_theme_font_size_override("font_size", STATUS_FONT)
	_status_lbl.add_theme_color_override("font_color", Color(0.93, 0.95, 1.0))
	_status_lbl.add_theme_color_override("font_shadow_color", Color(0, 0.02, 0.08, 0.6))
	_status_lbl.add_theme_constant_override("shadow_offset_x", 0)
	_status_lbl.add_theme_constant_override("shadow_offset_y", 2)
	_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_panel.add_child(_status_lbl)
	_set_status("")

# Update the status text and resize/recentre its pill to fit.
func _set_status(txt: String) -> void:
	if _status_lbl == null:
		return
	_status_lbl.text = txt
	_status_panel.visible = txt != ""
	# The pill's GEOMETRY is _layout_status's, not this function's, and the split is
	# what makes the lane honest: the board is framed against the lane, the lane is
	# the pill's rect, and a pill re-seated only when its text happens to change is
	# a pill that is in the wrong place after every resize.
	_layout_status(get_viewport_rect().size)

# Top-center pill: a small gold coin glyph + the coins earned this session
# (starts at 0). Only shown when signed in (offline users don't accumulate
# coins). The pill is the anchor for the floating "+ N" earn indicator we spawn
# after each level.
func _build_coin_hud(sz: Vector2) -> void:
	# Same width as the Quit button above it (right edges aligned, matching column).
	const PW := HUD_RIGHT_BTN_W
	const PH := 44.0
	_coin_panel = Panel.new()
	# Top-right, directly under the Quit button (right edges aligned).
	_coin_panel.position = Vector2(sz.x - PW - HUD_RIGHT_MARGIN, 78)
	_coin_panel.size = Vector2(PW, PH)
	_coin_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.06, 0.07, 0.18, 0.85)
	st.set_corner_radius_all(int(PH * 0.5))
	st.border_color = Color(1.0, 0.78, 0.20, 0.7)
	st.set_border_width_all(1)
	st.shadow_color = Color(1.0, 0.78, 0.20, 0.30)
	st.shadow_size = 8
	_coin_panel.add_theme_stylebox_override("panel", st)
	add_child(_coin_panel)

	_coin_icon = _make_coin_icon(22.0)
	_coin_icon.position = Vector2(14, (PH - 22.0) * 0.5)
	_coin_panel.add_child(_coin_icon)

	_coin_lbl = Label.new()
	_coin_lbl.text = "0"
	_coin_lbl.add_theme_font_size_override("font_size", 22)
	_coin_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.42))
	_coin_lbl.position = Vector2(42, 0)
	_coin_lbl.size = Vector2(PW - 56, PH)
	_coin_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_coin_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_coin_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coin_panel.add_child(_coin_lbl)

	# Track coins earned this session (not the wallet total) — the running sum
	# is added to the balance at game over.
	CoinsManager.session_earned_changed.connect(_on_session_changed)

# A small coin: gold disc + bright ring + "$" mark, positioned via top-left.
func _make_coin_icon(d: float) -> Control:
	var c := Control.new()
	c.size = Vector2(d, d)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 3D-shaded minted coin (gradient face, visible edge, specular), drawn in
	# code and matched to the home-screen pill. The "$" is overlaid on top.
	var disc := Control.new()
	disc.size = Vector2(d, d)
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.draw.connect(func() -> void:
		PackIcons.draw_coin_3d(disc, Vector2(d, d) * 0.5, d * 0.5))
	c.add_child(disc)
	var glyph := Label.new()
	glyph.text = "$"
	glyph.add_theme_font_size_override("font_size", int(d * 0.7))
	# Dark stamped glyph with a pale lower-right shadow → reads as raised metal.
	glyph.add_theme_color_override("font_color", Color(0.34, 0.19, 0.02))
	glyph.add_theme_color_override("font_shadow_color", Color(1.0, 0.94, 0.66, 0.7))
	glyph.add_theme_constant_override("shadow_offset_x", 1)
	glyph.add_theme_constant_override("shadow_offset_y", 1)
	glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.add_child(glyph)
	return c

func _on_session_changed(session_total: int) -> void:
	if _coin_lbl:
		_coin_lbl.text = str(session_total)

func _build_quit_dialog(sz: Vector2) -> void:
	var overlay := Panel.new()
	overlay.name = "QuitDialog"
	overlay.visible = false
	overlay.position = Vector2(sz.x * 0.5 - 190, sz.y * 0.5 - 100)
	overlay.size = Vector2(380, 200)
	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(0.07, 0.08, 0.16, 0.98)
	sn.corner_radius_top_left = 20; sn.corner_radius_top_right = 20
	sn.corner_radius_bottom_left = 20; sn.corner_radius_bottom_right = 20
	sn.border_color = Color(0.32, 0.36, 0.6, 0.9)
	sn.border_width_left = 2; sn.border_width_right = 2
	sn.border_width_top = 2; sn.border_width_bottom = 2
	sn.shadow_color = Color(0, 0, 0, 0.55)
	sn.shadow_size = 24
	sn.shadow_offset = Vector2(0, 10)
	overlay.add_theme_stylebox_override("panel", sn)
	add_child(overlay)

	var lbl := Label.new()
	lbl.text = "Forfeit game?" if _is_contest else "Quit to Home?"
	lbl.add_theme_font_size_override("font_size", 30)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.position = Vector2(0, 28)
	lbl.size = Vector2(380, 44)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay.add_child(lbl)

	var sub := Label.new()
	sub.text = "Your current score will count." if _is_contest else "Your progress will be lost."
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	sub.position = Vector2(0, 72)
	sub.size = Vector2(380, 24)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay.add_child(sub)

	var dlg_btn: GDScript = load("res://dialog_button.gd")

	var yes := dlg_btn.new() as Button
	yes.position = Vector2(24, 120)
	yes.size = Vector2(155, 52)
	yes.focus_mode = Control.FOCUS_NONE
	yes.call("setup", Color(0.62, 0.11, 0.12), "cross",
		"Yes, Forfeit" if _is_contest else "Yes, Quit")
	yes.pressed.connect(_on_quit_confirmed)
	overlay.add_child(yes)

	var no := dlg_btn.new() as Button
	no.position = Vector2(201, 120)
	no.size = Vector2(155, 52)
	no.focus_mode = Control.FOCUS_NONE
	no.call("setup", Color(0.14, 0.52, 0.24), "check", "Keep Playing")
	no.pressed.connect(func() -> void: get_node("QuitDialog").visible = false)
	overlay.add_child(no)

func _start_game() -> void:
	sequence = []
	player_seq = []
	level = 0
	replays = 0
	CoinsManager.start_game_session()
	_update_hud()
	_next_round()

# Next colour in the sequence. Arena races draw from a room-seeded RNG so every
# player sees the identical pattern; solo play stays fully random.
func _next_color() -> int:
	if _is_contest:
		return _rng.randi() % num_buttons
	return randi() % num_buttons

func _next_round() -> void:
	level += 1
	player_seq = []
	sequence.append(_next_color())
	flash_time = maxf(0.18, GameState.flash_time - (level - 1) * speed_inc)
	flash_gap = maxf(0.08, GameState.flash_gap - (level - 1) * speed_inc * 0.5)
	_update_hud()
	# Level-8 signature moments (each fires once, on the two special skins that have one).
	# The round FREEZES on the banner — it's awaited before the sequence starts, so
	# gameplay is paused for the ~3s show, then the round continues.
	#   • Volcano: the sky cracks into a thunderstorm behind a "YOU ARE ON FIRE!" banner.
	#   • Arcade: the hall goes dark, every cabinet screen catches fire, and a big
	#     "LUMEO KING" banner lights up.
	if level == 8 and _is_volcano_skin():
		BackgroundManager.volcano_thunderstorm()   # storm runs concurrently with the banner
		await _show_fire_text()
	elif level == 8 and _is_arcade_skin():
		BackgroundManager.arcade_king()            # dark room + fire screens, concurrent
		await _show_king_text()
	_set_status("Watch carefully...")
	_state = "showing"
	await get_tree().create_timer(0.6).timeout
	await _play_sequence()
	_state = "input"
	_set_status("Your turn!")
	_arm_press_timer()

# True when the equipped wheel look is the Volcano ("inferno") special skin — the
# same resolution _apply_simon_skin uses (a manual per-part look never counts).
func _is_volcano_skin() -> bool:
	return not CoinsManager.is_simon_manual() and CoinsManager.selected_skin == "inferno"

# True when the equipped look is the Jackpot ("casino") special skin — the same
# resolution used for the Stage-5 Mega Jackpot celebration. Its bespoke casino
# world is the live background, so the celebration's shader effects land on it.
func _is_casino_skin() -> bool:
	return not CoinsManager.is_simon_manual() and CoinsManager.selected_skin == "casino"

# True when the equipped look is the Luna Park ("lunapark") special skin — the same
# resolution used for the every-5-rounds "NICE RIDE!" carnival moment. Its bespoke
# park world is the live background, so the celebration's shader effects land on it.
func _is_lunapark_skin() -> bool:
	return not CoinsManager.is_simon_manual() and CoinsManager.selected_skin == "lunapark"

# True when the equipped look is the Arcade ("arcade") special skin — used for the
# level-8 "LUMEO KING" blackout (its cabinet hall is the live background, so the shader
# effect lands on it). A manual per-part look never counts.
func _is_arcade_skin() -> bool:
	return not CoinsManager.is_simon_manual() and CoinsManager.selected_skin == "arcade"

# Flash a big "YOU'RE ON FIRE!" banner across the screen, hold it, then fade it out
# — ~3.3s total. Awaited by _next_round so the sequence only resumes once it fades.
# Built from stacked layers (soft outer glow behind a molten-gradient-feel main
# layer) and bursts in with a scale pop so it lands like a real hype moment.
func _show_fire_text() -> void:
	# Full-screen holder we can scale-pop around the screen centre.
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.modulate.a = 0.0
	var screen := get_viewport_rect().size
	# Size the holder to the viewport EXPLICITLY (not via an anchor preset): the centred
	# labels below fill this rect, so an unresolved/zero holder size can't collapse the
	# text into the top-left corner. Pivot at centre so the scale-pop grows from middle.
	holder.position = Vector2.ZERO
	holder.size = screen
	holder.pivot_offset = screen * 0.5
	add_child(holder)

	# Font size scales with the screen so it reads huge on phones and desktop alike,
	# but stays within the width (with margins) so the line never clips.
	# "YOU ARE ON FIRE!" is a long line, so keep it a bit smaller than a short banner
	# would be, and cap it so it never runs off the sides on wide screens.
	var fs := int(clampf(screen.x * 0.115, 56.0, 124.0))
	var txt := "YOU ARE ON FIRE!"

	# Layer 1 — soft orange glow bloom behind the letters (thick outline, no fill punch).
	var glow := _fire_label(txt, fs)
	glow.add_theme_color_override("font_color", Color(1.0, 0.45, 0.12, 0.85))
	glow.add_theme_color_override("font_outline_color", Color(1.0, 0.35, 0.05, 0.7))
	glow.add_theme_constant_override("outline_size", 40)
	holder.add_child(glow)

	# Layer 2 — the crisp molten face: bright yellow-hot core, deep charred outline,
	# and a warm drop-shadow bloom so the letters feel lit from within.
	var main := _fire_label(txt, fs)
	main.add_theme_color_override("font_color", Color(1.0, 0.80, 0.28))       # yellow-hot
	main.add_theme_color_override("font_outline_color", Color(0.30, 0.02, 0.0))
	main.add_theme_constant_override("outline_size", 16)
	main.add_theme_color_override("font_shadow_color", Color(1.0, 0.30, 0.04, 0.6))
	main.add_theme_constant_override("shadow_offset_x", 0)
	main.add_theme_constant_override("shadow_offset_y", 6)
	main.add_theme_constant_override("shadow_outline_size", 12)
	holder.add_child(main)

	# Pop in with an overshoot + fade (together), hold with a gentle heat-shimmer
	# breath, then fade out. ~0.45 + 1.0 + 1.0 + 0.9 ≈ 3.35s total.
	holder.scale = Vector2(0.72, 0.72)
	var tw := create_tween()
	tw.tween_property(holder, "modulate:a", 1.0, 0.35)
	tw.parallel().tween_property(holder, "scale", Vector2.ONE, 0.45) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(holder, "scale", Vector2(1.04, 1.04), 1.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(holder, "scale", Vector2.ONE, 1.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(holder, "modulate:a", 0.0, 0.9)
	await tw.finished
	holder.queue_free()

# One centred full-screen text layer for the fire banner (shared setup for the
# stacked glow + main layers so they line up exactly).
func _fire_label(txt: String, fs: int) -> Label:
	var lbl := Label.new()
	lbl.text = txt
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", fs)
	return lbl

# Big "YOU ROCK!" banner for the Magical Lake's level-8 party — a bright lime-white
# face over a soft aqua bloom, in the lake's own greens so it belongs to the water
# it pops over rather than being a UI card laid on top of it.
#
# NOT awaited, and that is the point rather than an oversight: the round is already
# frozen by _freeze_for_event for the whole ~5 s party, and it is the PARTY's clock
# that releases it. So this is free to be shorter than the event — it waits out the
# pads surfacing, pops at about 0.9 s, breathes, and is completely gone by 3.3 s,
# which leaves the last stretch of the celebration to the frogs and the sink to the
# water. A banner still on screen while the pads go under is a banner that turns the
# ending into a fade rather than a farewell.
#
# It is deliberately narrower than the other four banners (0.13 of the width against
# their 0.16-0.17): five frogs are the subject here, and a full-width word across
# the middle of the frame covers three of them.
func _show_you_rock_text() -> void:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.modulate.a = 0.0
	var screen := get_viewport_rect().size
	# Size the holder to the viewport EXPLICITLY (not via an anchor preset): the
	# centred labels below fill this rect, so an unresolved size can't collapse the
	# text into the top-left corner. Pivot at centre so the scale-pop grows from it.
	holder.position = Vector2.ZERO
	holder.size = screen
	holder.pivot_offset = screen * 0.5
	add_child(holder)

	var fs := int(clampf(screen.x * 0.13, 62.0, 150.0))
	var txt := "YOU ROCK!"

	# A ring of small diamonds around the word. They are rotated ColorRects rather
	# than a glyph on purpose — a star character is a bet on the shipped font having
	# one, and a missing glyph is a row of boxes across the celebration.
	var mid := screen * 0.5
	for i in 9:
		var a := TAU * float(i) / 9.0 + 0.31
		var s := 11.0 + 9.0 * float((i * 5) % 3)
		var pip := ColorRect.new()
		pip.color = Color(0.82, 1.0, 0.92) if i % 2 == 0 else Color(0.62, 0.94, 1.0)
		pip.size = Vector2(s, s)
		pip.pivot_offset = Vector2(s, s) * 0.5
		pip.rotation = PI * 0.25
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var home := mid + Vector2(cos(a) * screen.x * 0.30, sin(a) * screen.y * 0.19)
		pip.position = home - pip.size * 0.5
		pip.scale = Vector2.ZERO
		holder.add_child(pip)
		# Out from the word and away, each on its own beat, so the ring twinkles
		# instead of pulsing as one object.
		var pt := holder.create_tween()
		pt.tween_interval(0.95 + 0.055 * float(i))
		pt.tween_property(pip, "scale", Vector2.ONE, 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pt.parallel().tween_property(pip, "position",
			pip.position + (home - mid).normalized() * 34.0, 1.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		pt.tween_property(pip, "scale", Vector2.ZERO, 0.85) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	# Layer 1 — soft aqua bloom behind the letters (thick, low-punch outline).
	var glow := _fire_label(txt, fs)
	glow.add_theme_color_override("font_color", Color(0.42, 1.0, 0.82, 0.85))
	glow.add_theme_color_override("font_outline_color", Color(0.30, 0.92, 0.86, 0.7))
	glow.add_theme_constant_override("outline_size", 40)
	holder.add_child(glow)

	# Layer 2 — crisp lime-white face with a deep lake-green outline and a cool drop
	# shadow, so the letters read as lit from the water.
	var main := _fire_label(txt, fs)
	main.add_theme_color_override("font_color", Color(0.94, 1.0, 0.86))
	main.add_theme_color_override("font_outline_color", Color(0.04, 0.20, 0.18))
	main.add_theme_constant_override("outline_size", 18)
	main.add_theme_color_override("font_shadow_color", Color(0.20, 0.80, 0.70, 0.6))
	main.add_theme_constant_override("shadow_offset_x", 0)
	main.add_theme_constant_override("shadow_offset_y", 6)
	main.add_theme_constant_override("shadow_outline_size", 12)
	holder.add_child(main)

	# Wait out the pads surfacing (0.85) → pop in with an overshoot (0.35) → breathe
	# (1.2) → fade fully out (0.9). Gone at 3.30 s of a 5.00 s party.
	holder.scale = Vector2(0.68, 0.68)
	var tw := create_tween()
	tw.tween_interval(0.85)
	tw.tween_property(holder, "modulate:a", 1.0, 0.30)
	tw.parallel().tween_property(holder, "scale", Vector2.ONE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(holder, "scale", Vector2(1.05, 1.05), 1.2) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(holder, "modulate:a", 0.0, 0.9) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tw.finished
	holder.queue_free()

# ---------------------------------------------------------------------------
# Ice Kingdom's two milestone banners
# ---------------------------------------------------------------------------
# The background id these belong to. The two celebrations themselves are the
# BACKGROUND's — it decides whether a level number means anything to it and how long
# the round must freeze — and these are the words that go over them, which are the
# game's, because nothing inside a SubViewport can draw over the HUD.
const ICE_BG := "world_ice"

# ...and the Royal Casino's, for the level-8 ROYAL FLUSH. There is deliberately NO
# every-third-round banner to go with it, unlike Ice Kingdom's FROZEN STREAK: the
# casino's small events ARE the show — cards dealt, a roulette ball, a chip cascade —
# and a line of text over the table every third round would compete with the thing it
# was announcing. The table speaks for itself until level 8.
const CASINO_BG := "world_casino"

# What the every-third-level banner says, cycled by which milestone it is: level 3
# is the first, 6 the second, and it comes round again at 15. Four phrases rather
# than one because this fires every three levels for a whole run — the fourth time
# a player reads the same two words in ninety seconds it has stopped being a reward.
const ICE_STREAK_WORDS := [
	"FROZEN STREAK!", "ICE COLD!", "KEEP GOING!", "UNSTOPPABLE!",
]

# The shimmer that runs across the big banner's letters: a soft band in SCREEN space
# multiplying a white copy of the text, so the highlight travels across the whole
# phrase rather than across each glyph.
#
# It has to be a shader and not a moving rectangle for one reason — a rectangle over
# the text is also a rectangle over the ice behind it. Multiplying the LABEL's own
# alpha is what keeps the band inside the letters.
const ICE_SHIMMER_SHADER := """
shader_type canvas_item;
uniform float pos = -0.4;
uniform float width = 0.16;
void fragment() {
	float d = (SCREEN_UV.x - pos) / width;
	COLOR.a *= exp(-d * d);
}
"""

func _ice_shimmer_mat() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = ICE_SHIMMER_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("pos", -0.4)
	return m


# The EXTRUSION under both banners, and the thing that makes them read as carved
# rather than as typed: `depth` copies of the word, each one pixel lower and darker
# than the last, laid down before the face. Six of them at 1280 wide.
#
# It is stacked Labels and not an outline because an outline goes round a letter and
# an extrusion goes UNDER it — the difference is the whole of the 3D impression, and
# at a banner's size an outline thick enough to fake one closes up the counters of
# the a and the o.
func _ice_extrude(holder: Control, txt: String, fs: int, depth: int,
		base: Color) -> void:
	for i in range(depth, 0, -1):
		var lay := _fire_label(txt, fs)
		var k := float(i) / float(depth)
		lay.add_theme_color_override("font_color", base.darkened(0.35 * k))
		lay.add_theme_color_override("font_outline_color", base.darkened(0.55))
		lay.add_theme_constant_override("outline_size", 10)
		lay.position = Vector2(0.0, float(i) * 2.2)
		holder.add_child(lay)


# EVENT 1's banner — "FROZEN STREAK!" and its three siblings, over the ~1.35 s ring
# of crystals. Fast: in over a fifth of a second with a small overshoot, a beat, and
# gone by 1.15 s, which is inside the freeze the background asked for.
#
# It sits ABOVE the middle of the frame (0.32 of the height) and not on it. The six
# snowflakes are the subject of every frame in this game including this one, and a
# word across their middle for a second is a second of not being able to read them.
func _show_frozen_streak_text(level_no: int) -> void:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.modulate.a = 0.0
	var screen := get_viewport_rect().size
	holder.position = Vector2(0.0, -screen.y * 0.155)
	holder.size = screen
	holder.pivot_offset = screen * 0.5
	add_child(holder)

	var idx: int = (int(level_no / 3) - 1) % ICE_STREAK_WORDS.size()
	var txt: String = String(ICE_STREAK_WORDS[maxi(idx, 0)])
	var fs := int(clampf(screen.x * 0.072, 34.0, 88.0))

	# Layer 1 — a wide, soft cyan bloom, which is the frost light the crystals in the
	# gutters are throwing at the same moment.
	var glow := _fire_label(txt, fs)
	glow.add_theme_color_override("font_color", Color(0.46, 0.86, 1.0, 0.70))
	glow.add_theme_color_override("font_outline_color", Color(0.30, 0.72, 0.95, 0.55))
	glow.add_theme_constant_override("outline_size", 30)
	holder.add_child(glow)

	# Layer 2 — the extrusion, in a deep polar blue.
	_ice_extrude(holder, txt, fs, 5, Color(0.10, 0.32, 0.52))

	# Layer 3 — the face: near-white with a cold blue cast, a deep ice outline and a
	# tight cyan shadow directly under it.
	var main := _fire_label(txt, fs)
	main.add_theme_color_override("font_color", Color(0.90, 0.98, 1.0))
	main.add_theme_color_override("font_outline_color", Color(0.05, 0.16, 0.30))
	main.add_theme_constant_override("outline_size", 12)
	main.add_theme_color_override("font_shadow_color", Color(0.36, 0.80, 1.0, 0.55))
	main.add_theme_constant_override("shadow_offset_x", 0)
	main.add_theme_constant_override("shadow_offset_y", 4)
	main.add_theme_constant_override("shadow_outline_size", 9)
	holder.add_child(main)

	holder.scale = Vector2(0.60, 0.60)
	var tw := create_tween()
	tw.tween_property(holder, "modulate:a", 1.0, 0.16)
	tw.parallel().tween_property(holder, "scale", Vector2.ONE, 0.26) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(holder, "scale", Vector2(1.04, 1.04), 0.42) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(holder, "modulate:a", 0.0, 0.34) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tw.finished
	holder.queue_free()


# EVENT 2's banner — "ICE IN MY VEINS!", over the ~4.85 s aurora celebration.
#
# NOT awaited, exactly like the lake's: the round is already frozen for the whole
# event and it is the EVENT's clock that releases it, so this is free to be shorter.
# It waits out the aurora coming up and the sleigh reaching the middle of the sky
# (1.15 s), pops, holds while the sleigh leaves, and is completely gone by 4.0 s of
# 4.85 — which leaves the light sweep and the last of the snow to close the event on
# their own. A banner still up while the sky comes down turns an ending into a fade.
func _show_ice_veins_text() -> void:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.modulate.a = 0.0
	var screen := get_viewport_rect().size
	# Lifted a little off the middle, and no further. Sixteen characters at a size
	# that reads as a celebration is most of the frame's width, so the only place
	# for it is the BAND BETWEEN THE ROWS of buttons — high enough to clear the near
	# ones, low enough not to sit on the far ones. Lifting it to the top of the
	# frame would put it over the sky the aurora and the sleigh are using.
	holder.position = Vector2(0.0, -screen.y * 0.060)
	holder.size = screen
	holder.pivot_offset = screen * 0.5
	add_child(holder)

	var fs := int(clampf(screen.x * 0.090, 46.0, 116.0))
	var txt := "ICE IN MY VEINS!"

	# A ring of ice chips around the phrase, on the lake party's pattern: rotated
	# ColorRects rather than a glyph, because a star character is a bet on the
	# shipped font having one and a missing glyph is a row of boxes across the
	# celebration.
	var mid := screen * 0.5 + holder.position
	for i in 10:
		var a := TAU * float(i) / 10.0 + 0.19
		var sz := 9.0 + 8.0 * float((i * 7) % 3)
		var pip := ColorRect.new()
		pip.color = Color(0.86, 0.97, 1.0) if i % 2 == 0 else Color(0.52, 0.86, 1.0)
		pip.size = Vector2(sz, sz)
		pip.pivot_offset = Vector2(sz, sz) * 0.5
		pip.rotation = PI * 0.25
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# A TALL ring, not a wide one: at 0.17 of the height the chips landed inside
		# the phrase rather than around it, which reads as debris on the letters.
		var home := screen * 0.5 + Vector2(cos(a) * screen.x * 0.35,
			sin(a) * screen.y * 0.27)
		pip.position = home - pip.size * 0.5
		pip.scale = Vector2.ZERO
		holder.add_child(pip)
		var pt := holder.create_tween()
		pt.tween_interval(1.30 + 0.05 * float(i))
		pt.tween_property(pip, "scale", Vector2.ONE, 0.20) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pt.parallel().tween_property(pip, "position",
			pip.position + (home - mid).normalized() * 30.0, 1.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		pt.tween_property(pip, "scale", Vector2.ZERO, 0.8) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	# Layer 1 — the wide aurora bloom, in the same violet-into-cyan the sky is doing
	# behind it, so the phrase belongs to the moment rather than sitting on it.
	var halo := _fire_label(txt, fs)
	halo.add_theme_color_override("font_color", Color(0.52, 0.55, 1.0, 0.55))
	halo.add_theme_color_override("font_outline_color", Color(0.40, 0.60, 1.0, 0.55))
	halo.add_theme_constant_override("outline_size", 46)
	holder.add_child(halo)

	# Layer 2 — a tighter cyan glow inside it.
	var glow := _fire_label(txt, fs)
	glow.add_theme_color_override("font_color", Color(0.40, 0.90, 1.0, 0.0))
	glow.add_theme_color_override("font_shadow_color", Color(0.34, 0.86, 1.0, 0.65))
	glow.add_theme_constant_override("shadow_offset_x", 0)
	glow.add_theme_constant_override("shadow_offset_y", 0)
	glow.add_theme_constant_override("shadow_outline_size", 24)
	holder.add_child(glow)

	# Layer 3 — the extrusion. Deeper than the streak banner's, because this one is
	# nearly twice the size and an extrusion that does not scale with the letters
	# reads as a printing error.
	_ice_extrude(holder, txt, fs, 7, Color(0.07, 0.26, 0.46))

	# Layer 4 — the face: thick, rounded, near-white with a cold cast, over a deep
	# ice outline and a cyan shadow that acts as the bottom of the extrusion.
	var main := _fire_label(txt, fs)
	main.add_theme_color_override("font_color", Color(0.93, 0.99, 1.0))
	main.add_theme_color_override("font_outline_color", Color(0.04, 0.14, 0.28))
	main.add_theme_constant_override("outline_size", 16)
	main.add_theme_color_override("font_shadow_color", Color(0.30, 0.78, 1.0, 0.6))
	main.add_theme_constant_override("shadow_offset_x", 0)
	main.add_theme_constant_override("shadow_offset_y", 7)
	main.add_theme_constant_override("shadow_outline_size", 12)
	holder.add_child(main)

	# Layer 5 — the shimmer. A white copy of the phrase whose alpha is a soft band in
	# screen space; sweeping the band across is the highlight running along the ice.
	var shine := _fire_label(txt, fs)
	shine.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.9))
	var smat := _ice_shimmer_mat()
	shine.material = smat
	holder.add_child(shine)

	# 1.15 wait → pop (0.34) → breathe (1.35) → out (0.85). Gone at 3.9 s of 4.85.
	holder.scale = Vector2(0.66, 0.66)
	var tw := create_tween()
	tw.tween_interval(1.15)
	tw.tween_property(holder, "modulate:a", 1.0, 0.28)
	tw.parallel().tween_property(holder, "scale", Vector2.ONE, 0.34) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(holder, "scale", Vector2(1.045, 1.045), 1.35) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(holder, "modulate:a", 0.0, 0.85) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	# The shimmer runs twice, on its own tween: once as the phrase lands and once
	# while it is holding. Both start off the left edge and finish off the right, so
	# the band is never seen to appear.
	var sw := create_tween()
	sw.tween_interval(1.45)
	sw.tween_method(func(v: float) -> void: smat.set_shader_parameter("pos", v),
		-0.25, 1.25, 0.85).set_trans(Tween.TRANS_SINE)
	sw.tween_interval(0.55)
	sw.tween_method(func(v: float) -> void: smat.set_shader_parameter("pos", v),
		-0.25, 1.25, 0.95).set_trans(Tween.TRANS_SINE)
	await tw.finished
	holder.queue_free()


# ---------------------------------------------------------------------------
# The Royal Casino's level-8 banner
# ---------------------------------------------------------------------------
# "ROYAL FLUSH!" over CasinoEvents' five-card celebration. The celebration itself is
# the BACKGROUND's — it deals the hand, holds the fifth card back, slams it open on
# the Ace and decides how long the round must freeze — and this is the words that go
# over it, which are the game's, because nothing inside a SubViewport can draw over
# the HUD.
#
# NOT awaited, and that is the point rather than an oversight: the round is already
# frozen by _freeze_for_event for the whole ~4.35 s hand, and it is the EVENT's clock
# that releases it. So this is free to be shorter, and it is — it waits out the deal
# and the four reveals, arrives exactly as the Ace turns over (2.50 s), holds through
# the gold burst, and is completely gone by 4.34 s, which leaves the cards' exit to
# close the celebration on its own. A banner still up while the hand slides away
# turns an ending into a fade.
#
# ONE LINE, not "ROYAL..." then "FLUSH!". The brief offers both; this UI has four
# other celebration banners and all of them are a single line, so a two-beat reveal
# here would read as a different game's typography rather than as a bigger moment in
# this one. The IMPACT is carried instead by the scale overshoot, the extrusion and
# the shine, which is where a casino sign gets its weight anyway.
#
# It sits a little ABOVE the middle of the frame: the five cards are on the lane
# across the top and the six chips are in the lower middle, so this is the band
# between them.
func _show_royal_flush_text() -> void:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.modulate.a = 0.0
	var screen := get_viewport_rect().size
	holder.position = Vector2(0.0, -screen.y * 0.075)
	holder.size = screen
	holder.pivot_offset = screen * 0.5
	add_child(holder)

	var fs := int(clampf(screen.x * 0.108, 52.0, 132.0))
	var txt := "ROYAL FLUSH!"

	# A ring of small gold pips around the phrase — rotated ColorRects rather than a
	# glyph, because a star or a suit character is a bet on the shipped font having
	# one and a missing glyph is a row of boxes across the celebration. (Same reason
	# CasinoEvents draws its hearts as an SDF instead of using the heart character.)
	var mid := screen * 0.5 + holder.position
	for i in 11:
		var a := TAU * float(i) / 11.0 + 0.27
		var sz := 9.0 + 8.0 * float((i * 5) % 3)
		var pip := ColorRect.new()
		pip.color = Color(1.0, 0.86, 0.44) if i % 2 == 0 else Color(1.0, 0.96, 0.80)
		pip.size = Vector2(sz, sz)
		pip.pivot_offset = Vector2(sz, sz) * 0.5
		pip.rotation = PI * 0.25
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# A TALL ring rather than a wide one: at a small vertical radius the pips land
		# inside the phrase instead of around it, which reads as debris on the letters.
		var home := screen * 0.5 + Vector2(cos(a) * screen.x * 0.33,
			sin(a) * screen.y * 0.26)
		pip.position = home - pip.size * 0.5
		pip.scale = Vector2.ZERO
		holder.add_child(pip)
		# Out from the phrase and away, each on its own beat, so the ring twinkles
		# instead of pulsing as one object.
		var pt := holder.create_tween()
		pt.tween_interval(2.62 + 0.045 * float(i))
		pt.tween_property(pip, "scale", Vector2.ONE, 0.20) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pt.parallel().tween_property(pip, "position",
			pip.position + (home - mid).normalized() * 32.0, 1.3) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		pt.tween_property(pip, "scale", Vector2.ZERO, 0.7) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	# Layer 1 — the wide gold halo, which is the same light the table's own burst is
	# throwing at that instant, so the phrase belongs to the moment rather than
	# sitting on top of it.
	var halo := _fire_label(txt, fs)
	halo.add_theme_color_override("font_color", Color(1.0, 0.78, 0.26, 0.62))
	halo.add_theme_color_override("font_outline_color", Color(1.0, 0.66, 0.16, 0.55))
	halo.add_theme_constant_override("outline_size", 46)
	holder.add_child(halo)

	# Layer 2 — a tighter amber glow inside it.
	var glow := _fire_label(txt, fs)
	glow.add_theme_color_override("font_color", Color(1.0, 0.84, 0.40, 0.0))
	glow.add_theme_color_override("font_shadow_color", Color(1.0, 0.72, 0.22, 0.70))
	glow.add_theme_constant_override("shadow_offset_x", 0)
	glow.add_theme_constant_override("shadow_offset_y", 0)
	glow.add_theme_constant_override("shadow_outline_size", 24)
	holder.add_child(glow)

	# Layer 3 — the extrusion, in a deep bronze. This is what makes the phrase read as
	# CAST rather than as typed, and it is stacked copies rather than a thick outline
	# because an outline goes ROUND a letter and an extrusion goes UNDER it — at this
	# size an outline heavy enough to fake one closes up the counters of the O and
	# the R. (_ice_extrude is not ice-specific; it takes the base colour.)
	_ice_extrude(holder, txt, fs, 7, Color(0.30, 0.16, 0.04))

	# Layer 4 — the face: bright table gold over a near-black outline, with a warm
	# shadow under it acting as the bottom of the extrusion.
	var main := _fire_label(txt, fs)
	main.add_theme_color_override("font_color", Color(1.0, 0.87, 0.44))
	main.add_theme_color_override("font_outline_color", Color(0.14, 0.05, 0.02))
	main.add_theme_constant_override("outline_size", 16)
	main.add_theme_color_override("font_shadow_color", Color(1.0, 0.60, 0.14, 0.60))
	main.add_theme_constant_override("shadow_offset_x", 0)
	main.add_theme_constant_override("shadow_offset_y", 7)
	main.add_theme_constant_override("shadow_outline_size", 12)
	holder.add_child(main)

	# Layer 5 — the shine. A white copy of the phrase whose alpha is a soft band in
	# SCREEN space; sweeping the band across is the highlight travelling along the
	# letters. It has to be a shader and not a moving rectangle for one reason — a
	# rectangle over the text is also a rectangle over the table behind it, and
	# multiplying the LABEL's own alpha is what keeps the band inside the letters.
	var shine := _fire_label(txt, fs)
	shine.add_theme_color_override("font_color", Color(1.0, 1.0, 0.94, 0.92))
	var smat := _ice_shimmer_mat()
	shine.material = smat
	holder.add_child(shine)

	# 2.50 wait — the deal and the four reveals — then the impact lands with the Ace:
	# in over a quarter of a second from 0.55 with a BACK overshoot, a breath, and
	# gone by 4.34 s of a 4.35 s celebration.
	holder.scale = Vector2(0.55, 0.55)
	var tw := create_tween()
	tw.tween_interval(2.50)
	tw.tween_property(holder, "modulate:a", 1.0, 0.24)
	tw.parallel().tween_property(holder, "scale", Vector2.ONE, 0.34) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(holder, "scale", Vector2(1.035, 1.035), 1.05) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(holder, "modulate:a", 0.0, 0.45) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	# The shine runs twice on its own tween: once as the phrase lands and once while
	# it is holding. Both start off the left edge and finish off the right, so the
	# band is never seen to appear or to stop.
	var sw := create_tween()
	sw.tween_interval(2.72)
	sw.tween_method(func(v: float) -> void: smat.set_shader_parameter("pos", v),
		-0.25, 1.25, 0.70).set_trans(Tween.TRANS_SINE)
	sw.tween_interval(0.35)
	sw.tween_method(func(v: float) -> void: smat.set_shader_parameter("pos", v),
		-0.25, 1.25, 0.80).set_trans(Tween.TRANS_SINE)
	await tw.finished
	holder.queue_free()


# Big "LUMEO KING" banner for the Arcade skin's level-8 blackout — regal gold letters
# ringed by an electric neon glow (cyan→magenta), so it reads like a lit marquee sign
# over the darkened hall. Pops in, holds with a gentle breath, fades out — ~3.3s total.
# Awaited by _next_round so the round stays frozen until it clears.
func _show_king_text() -> void:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.modulate.a = 0.0
	var screen := get_viewport_rect().size
	holder.position = Vector2.ZERO
	holder.size = screen
	holder.pivot_offset = screen * 0.5
	add_child(holder)

	var fs := int(clampf(screen.x * 0.155, 70.0, 164.0))
	var txt := "LUMEO KING"

	# Layer 1 — wide neon halo (electric blue), a thick soft outline with no fill punch.
	var glow := _fire_label(txt, fs)
	glow.add_theme_color_override("font_color", Color(0.40, 0.85, 1.0, 0.85))
	glow.add_theme_color_override("font_outline_color", Color(0.30, 0.55, 1.0, 0.7))
	glow.add_theme_constant_override("outline_size", 44)
	holder.add_child(glow)

	# Layer 2 — magenta inner glow, a touch tighter, so the halo reads as arcade neon.
	var glow2 := _fire_label(txt, fs)
	glow2.add_theme_color_override("font_color", Color(1.0, 0.30, 0.85, 0.0))
	glow2.add_theme_color_override("font_shadow_color", Color(1.0, 0.25, 0.80, 0.6))
	glow2.add_theme_constant_override("shadow_offset_x", 0)
	glow2.add_theme_constant_override("shadow_offset_y", 0)
	glow2.add_theme_constant_override("shadow_outline_size", 22)
	holder.add_child(glow2)

	# Layer 3 — the crisp regal-gold face: bright gold core, deep outline, warm shadow.
	var main := _fire_label(txt, fs)
	main.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35))          # regal gold
	main.add_theme_color_override("font_outline_color", Color(0.16, 0.06, 0.0))
	main.add_theme_constant_override("outline_size", 16)
	main.add_theme_color_override("font_shadow_color", Color(1.0, 0.62, 0.10, 0.55))
	main.add_theme_constant_override("shadow_offset_x", 0)
	main.add_theme_constant_override("shadow_offset_y", 6)
	main.add_theme_constant_override("shadow_outline_size", 12)
	holder.add_child(main)

	# Pop in with an overshoot + fade, hold with a gentle breath, then fade out. ~3.3s.
	holder.scale = Vector2(0.72, 0.72)
	var tw := create_tween()
	tw.tween_property(holder, "modulate:a", 1.0, 0.35)
	tw.parallel().tween_property(holder, "scale", Vector2.ONE, 0.45) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(holder, "scale", Vector2(1.04, 1.04), 1.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(holder, "scale", Vector2.ONE, 1.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(holder, "modulate:a", 0.0, 0.9)
	await tw.finished
	holder.queue_free()

# Big bold gold "JACKPOT!" banner that pops over the wheel during the Mega Jackpot
# party, holds, then fades out and is freed exactly as the ~3s show ends. Built from a
# soft gold glow layer behind a crisp bright-gold face (thick dark outline = bold and
# clear). Centred on screen and never awaited, so it runs alongside the light show.
func _show_jackpot_text() -> void:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.modulate.a = 0.0
	var screen := get_viewport_rect().size
	# Size the holder to the viewport EXPLICITLY (not via an anchor preset): the centred
	# labels below fill this rect, so an unresolved/zero holder size can't collapse the
	# text into the top-left corner. Pivot at centre so the scale-pop grows from middle.
	holder.position = Vector2.ZERO
	holder.size = screen
	holder.pivot_offset = screen * 0.5
	add_child(holder)

	var fs := int(clampf(screen.x * 0.17, 76.0, 176.0))
	var txt := "JACKPOT!"

	# Layer 1 — soft gold bloom behind the letters (thick, low-punch outline).
	var glow := _fire_label(txt, fs)
	glow.add_theme_color_override("font_color", Color(1.0, 0.82, 0.34, 0.85))
	glow.add_theme_color_override("font_outline_color", Color(1.0, 0.72, 0.22, 0.7))
	glow.add_theme_constant_override("outline_size", 40)
	holder.add_child(glow)

	# Layer 2 — crisp bright-gold face with a deep outline (reads bold + clear) and a
	# warm drop shadow so the letters feel lit.
	var main := _fire_label(txt, fs)
	main.add_theme_color_override("font_color", Color(1.0, 0.90, 0.45))
	main.add_theme_color_override("font_outline_color", Color(0.24, 0.10, 0.0))
	main.add_theme_constant_override("outline_size", 18)
	main.add_theme_color_override("font_shadow_color", Color(1.0, 0.60, 0.12, 0.6))
	main.add_theme_constant_override("shadow_offset_x", 0)
	main.add_theme_constant_override("shadow_offset_y", 6)
	main.add_theme_constant_override("shadow_outline_size", 12)
	holder.add_child(main)

	# Pop in (0.45s incl. parallel scale) → breathe hold (1.15s) → fade fully out (1.4s) = 3.0s.
	holder.scale = Vector2(0.72, 0.72)
	var tw := create_tween()
	tw.tween_property(holder, "modulate:a", 1.0, 0.35)
	tw.parallel().tween_property(holder, "scale", Vector2.ONE, 0.45) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(holder, "scale", Vector2(1.05, 1.05), 1.15) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(holder, "modulate:a", 0.0, 1.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tw.finished
	holder.queue_free()

# Big carnival "NICE RIDE!" banner that pops over the wheel during the Luna Park every-5
# celebration, holds, then fades fully out and is freed exactly as the ~3s show ends
# (synced with the background's `cele` clock — sky dims, rides blaze). Built from a soft
# pink bloom behind a bright warm-gold face. Centred on screen; never awaited, so it runs
# alongside the light show without touching gameplay timing.
func _show_nice_ride_text() -> void:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.modulate.a = 0.0
	var screen := get_viewport_rect().size
	# Size the holder to the viewport EXPLICITLY (not via an anchor preset): the centred
	# labels below fill this rect, so an unresolved/zero holder size can't collapse the
	# text into the top-left corner. Pivot at centre so the scale-pop grows from middle.
	holder.position = Vector2.ZERO
	holder.size = screen
	holder.pivot_offset = screen * 0.5
	add_child(holder)

	var fs := int(clampf(screen.x * 0.16, 72.0, 168.0))
	var txt := "NICE RIDE!"

	# Layer 1 — soft carnival-pink bloom behind the letters (thick, low-punch outline).
	var glow := _fire_label(txt, fs)
	glow.add_theme_color_override("font_color", Color(1.0, 0.42, 0.72, 0.85))
	glow.add_theme_color_override("font_outline_color", Color(1.0, 0.35, 0.62, 0.7))
	glow.add_theme_constant_override("outline_size", 40)
	holder.add_child(glow)

	# Layer 2 — crisp bright warm-gold face with a deep outline (bold + clear) and a warm
	# drop shadow so the letters feel lit like the rides.
	var main := _fire_label(txt, fs)
	main.add_theme_color_override("font_color", Color(1.0, 0.92, 0.52))
	main.add_theme_color_override("font_outline_color", Color(0.28, 0.06, 0.12))
	main.add_theme_constant_override("outline_size", 18)
	main.add_theme_color_override("font_shadow_color", Color(1.0, 0.55, 0.30, 0.6))
	main.add_theme_constant_override("shadow_offset_x", 0)
	main.add_theme_constant_override("shadow_offset_y", 6)
	main.add_theme_constant_override("shadow_outline_size", 12)
	holder.add_child(main)

	# Pop in (0.45s incl. parallel scale) → breathe hold (1.0s) → fade fully out (1.5s) ≈ 3.0s,
	# so the banner is completely gone right as the park eases back to its idle night.
	holder.scale = Vector2(0.72, 0.72)
	var tw := create_tween()
	tw.tween_property(holder, "modulate:a", 1.0, 0.3)
	tw.parallel().tween_property(holder, "scale", Vector2.ONE, 0.45) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(holder, "scale", Vector2(1.05, 1.05), 1.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(holder, "modulate:a", 0.0, 1.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tw.finished
	holder.queue_free()

func _play_sequence() -> void:
	for idx: int in sequence:
		await _flash(idx, flash_time)
		await get_tree().create_timer(flash_gap).timeout

func _flash(idx: int, duration: float) -> void:
	_wheel.set_lit(idx, true)
	AudioManager.play_button_tone(idx, duration)
	await get_tree().create_timer(duration).timeout
	_wheel.set_lit(idx, false)

# Brief press feedback on the 3D wheel: sink the segment and light it, then
# release shortly after (set_press/set_lit do not auto-decay).
func _press_feedback(idx: int) -> void:
	_wheel.set_press(idx, 1.0)
	_wheel.set_lit(idx, true)
	get_tree().create_timer(0.18).timeout.connect(func() -> void:
		_wheel.set_lit(idx, false)
		_wheel.set_press(idx, 0.0))

func _player_pressed(idx: int) -> void:
	_press_feedback(idx)
	AudioManager.play_button_tone(idx, 0.3)
	player_seq.append(idx)
	var step := player_seq.size() - 1
	if player_seq[step] != sequence[step]:
		_disarm_press_timer()
		_state = "showing"
		var correct := sequence[step]
		_set_status("The correct button was...")
		await get_tree().create_timer(0.35).timeout
		for _i in 3:
			await _flash(correct, 0.28)
			await get_tree().create_timer(0.14).timeout
		_game_over()
		return
	if player_seq.size() != sequence.size():
		# Correct, but more presses to go — reset the per-press window.
		_arm_press_timer()
	if player_seq.size() == sequence.size():
		_disarm_press_timer()
		_state = "idle"
		_set_status("Correct! Get ready...")
		# Award coins for this completed level and float a "+ N" indicator
		# next to the balance pill. Returns 0 if not signed in.
		var earned := CoinsManager.award_for_level(GameState.difficulty, level)
		if earned > 0:
			_show_earn_indicator(earned)
		BackgroundManager.notify_level_complete(level)      # kitty theme winks + cheers
		# THE 3D BACKGROUND'S OWN MILESTONE, offered on EVERY completed round.
		#
		# It used to be asked only inside `level % 5 == 0`, which was the Magical
		# Lake's number living in the game rather than in the lake. The BACKGROUND
		# decides now (see BackgroundScenes.note_milestone): the lake still crosses a
		# frog every fifth round, Ice Kingdom grows and shatters a ring of crystals
		# every third, and every other background answers 0.0 to all of them. A
		# fourth background wanting a fourth number does not touch this file.
		#
		# What comes back is the SECONDS THE ROUND MUST STAY FROZEN, and the freeze
		# is taken the instant it is offered — there is no await between the round
		# completing and this, which is the whole point of taking it here.
		var bg_secs: float = _wheel.background_milestone(level)
		if bg_secs > 0.0:
			_freeze_for_event()
			# Ice Kingdom's every-third-level burst gets a banner over it, raised now
			# so it scales in while the crystals are still growing. Fired and NOT
			# awaited: the banner is shorter than the event, and it is the EVENT's
			# clock that releases the freeze.
			if _wheel.background_id() == ICE_BG:
				_show_frozen_streak_text(level)
		# Every 3 rounds the Volcano skin's central hub volcano erupts and feeds a surge
		# of fresh lava into the background river. Both calls are no-ops off the skin.
		if level % 3 == 0:
			_wheel.electric_pulse()   # premium electric charge flourish (non-casino/lunapark skins)
			_wheel.roulette_spin()    # Jackpot skin: ivory ball laps the gold ring
			_wheel.luna_light_chase() # Luna Park skin: marquee bulbs chase around the wheel
			_wheel.erupt()
			BackgroundManager.surge_river()
			BackgroundManager.luna_light_chase()   # Luna Park: environment bulbs briefly synchronise
		# Every 5 rounds the Arcade skin's cabinets all flash a giant glowing "OMG" for 4s.
		# No-op off the Arcade skin. Independent of the every-3 pulse; on round 15/30 both
		# fire together. Purely cosmetic — never awaited, so gameplay timing is untouched.
		if level % 5 == 0:
			BackgroundManager.arcade_omg()
			# Luna Park skin: the "NICE RIDE!" moment — the marquee ring powers on, the sky
			# dims while the Ferris wheel + coaster blaze, fireworks/confetti fire, and a big
			# "NICE RIDE!" banner pops over the wheel and fades fully out over ~3s. The light
			# show is fired concurrently, then the round FREEZES on the banner (awaited) so the
			# next level only starts once the text is completely gone. All calls no-op off the skin.
			_wheel.luna_celebrate()
			BackgroundManager.luna_celebrate()
			if _is_lunapark_skin():
				await _show_nice_ride_text()   # FREEZE until the "NICE RIDE!" banner fully fades out
		# ...and the background's freeze is released HERE and nowhere earlier. Not when
		# the lake's frog lands on the pad or reaches the left edge, and not when the
		# last of Ice Kingdom's crystals lets go: only once the event is completely
		# outside the viewport and the background has cleaned it up.
		#
		# After the Luna Park await rather than before it. The two can never both be
		# running — they are on different backgrounds — but a freeze that ends while
		# any banner is still up is a freeze that ended early, and this order cannot
		# get that wrong.
		if bg_secs > 0.0:
			await get_tree().create_timer(bg_secs).timeout
			_thaw_after_event()
		# THE BIGGER OF THE TWO BACKGROUND HOOKS, offered every eighth completed level,
		# for the milestone the every-round one is not enough for. Same contract, same
		# returned freeze, and the same rule about who decides: the Magical Lake answers
		# level 8 and only level 8 with the five-frog "YOU ROCK!" party, and Ice Kingdom
		# answers every eighth with the aurora, the reindeer and "ICE IN MY VEINS!".
		# Each refuses a repeat on its own account, so this cannot fire twice for one
		# level.
		if level % 8 == 0:
			var party_secs: float = _wheel.background_celebration(level)
			if party_secs > 0.0:
				_freeze_for_event()
				# Fired, NOT awaited: each banner's own tween is shorter than the
				# celebration it sits over, and it is the CELEBRATION's clock that decides
				# when the round resumes. The freeze covers both.
				var finale_bg: String = _wheel.background_id()
				if finale_bg == ICE_BG:
					_show_ice_veins_text()
				elif finale_bg == CASINO_BG:
					_show_royal_flush_text()
				else:
					_show_you_rock_text()
				await get_tree().create_timer(party_secs).timeout
				_thaw_after_event()
		# Jackpot skin only: every 8th completed level (8, 16, 24, …) fires a Mega
		# Jackpot celebration — the hall washes through a rainbow, the gold JACKPOT
		# sign powers on, the roulette ball rolls, and a big "JACKPOT!" banner pops
		# over the wheel and fades out over ~3s. The round FREEZES here until the banner
		# has fully faded: the light show + rolling ball are fired concurrently, then we
		# await the on-screen text so the next level only starts once it's gone.
		# `casino_jackpot()` is a no-op on any other background.
		if level % 8 == 0 and _is_casino_skin():
			_wheel.roulette_celebrate()   # ball rolls continuously for the whole ~3s show
			BackgroundManager.casino_jackpot()   # rainbow wash + gold sign (concurrent tween)
			await _show_jackpot_text()    # FREEZE until the "JACKPOT!" banner fully fades out
		await get_tree().create_timer(0.8).timeout
		_next_round()

func _on_replay() -> void:
	if _state != "input" or replays <= 0:
		return
	replays -= 1
	_update_hud()
	AudioManager.play_replay_sound()
	_state = "showing"
	_set_status("Replaying sequence...")
	player_seq = []
	await _play_sequence()
	_state = "input"
	_set_status("Your turn!")
	_arm_press_timer()

func _on_quit() -> void:
	get_node("QuitDialog").visible = true

# The Android back gesture, offered to us by GameManager before it falls back to
# "go home". A RACE takes it: going home clears GameState.contest_context, so the run
# would be voided with no score submitted to the room — and, since nothing recorded
# that we played, the hub card would let us re-enter and race the same room again.
# Back therefore raises the same forfeit prompt as the on-screen quit button (and
# closes it if it's already up). A normal solo game keeps the old behaviour.
func handle_back() -> bool:
	if not _is_contest:
		return false
	var dlg := get_node_or_null("QuitDialog")
	if dlg == null:
		return true                      # mid-teardown: swallow it rather than void the run
	if _state == "gameover":
		return true                      # the result is already being submitted
	dlg.visible = not dlg.visible
	return true

# "Yes" in the quit dialog. Normal play → home. Race play → forfeit, which runs
# the game-over flow so the current score is submitted to the room and we route
# back to the live room (see _game_over's _is_contest branch).
func _on_quit_confirmed() -> void:
	get_node("QuitDialog").visible = false
	if _is_contest:
		if _state != "gameover":
			_game_over()
	else:
		game_manager.show_home()

func _on_watch_ad() -> void:
	if _state != "input":
		return
	AdManager.show_rewarded(_replay_after_countdown)

func _replay_after_countdown() -> void:
	_state = "showing"
	for n: int in [3, 2, 1]:
		_set_status(str(n) + "...")
		await get_tree().create_timer(1.0).timeout
	replays += 1
	_state = "input"
	_on_replay()

# Arm the per-press countdown (Arena races only). Resets the 10s window to now.
func _arm_press_timer() -> void:
	if not _is_contest:
		return
	_press_active = true
	_press_deadline = _now_secs() + PRESS_LIMIT
	if _countdown_lbl:
		_countdown_lbl.visible = false

func _disarm_press_timer() -> void:
	_press_active = false
	if _countdown_lbl:
		_countdown_lbl.visible = false

# ---------------------------------------------------------------------------
# The celebration freeze
# ---------------------------------------------------------------------------
# A background milestone that is meant to be an INTERRUPTION rather than something
# happening behind the next round (the Magical Lake's frog, and its level-8 party).
#
# There is no second gameplay clock here and no new pause system: this screen
# already has exactly one thing that decides whether anything may happen, and it is
# `_state`. Every entry point in the file is gated on it —
#
#   _input                 a tap only reaches _player_pressed while it is "input"
#   _process               the Arena per-press countdown only ticks in "input"
#   _on_replay             refuses outside "input"
#   _on_watch_ad           refuses outside "input"
#   _on_press_timeout      refuses outside "input"
#
# — so a state that is not "input" is already, and provably, a state in which the
# player cannot press a button, the sequence cannot advance and the 10 s race clock
# cannot expire. What the freeze adds is that the round does not MOVE ON either,
# and that is the `await` at the call site: the next round is started by the line
# after it, so while it is waiting no round begins, no level is reached and no
# sequence is played.
#
# "event" rather than "idle" because a name that is never "input" cannot be
# mistaken for one, and because the press timer is explicitly disarmed on the way
# in: an Arena race could otherwise carry a live deadline into a five-second
# celebration and knock the player out during it.
const EVENT_STATE := "event"
var _frozen_state := ""

func _freeze_for_event() -> void:
	if _state == EVENT_STATE:
		return
	_frozen_state = _state
	_disarm_press_timer()
	_state = EVENT_STATE

# Put back exactly what was there. If something ended the game while the event was
# running — the Android back gesture into the forfeit prompt is the one real path —
# `_state` is no longer "event" and this does nothing, so a finished run cannot be
# resurrected into the round it was in.
func _thaw_after_event() -> void:
	if _state != EVENT_STATE:
		return
	_state = _frozen_state if _frozen_state != "" else "idle"
	_frozen_state = ""

# The 10s window elapsed before the player pressed — flash the button they missed,
# then end the game (counts exactly like a wrong press at this step).
func _on_press_timeout() -> void:
	_disarm_press_timer()
	if _state != "input":
		return
	_state = "showing"
	var step := player_seq.size()
	var correct := sequence[step] if step < sequence.size() else -1
	_set_status("Time's up!")
	await get_tree().create_timer(0.35).timeout
	if correct >= 0:
		for _i in 3:
			await _flash(correct, 0.28)
			await get_tree().create_timer(0.14).timeout
	_game_over()

func _game_over() -> void:
	_state = "gameover"
	_disarm_press_timer()
	# Bank the coins earned this session into the persistent wallet. session_earned
	# survives the commit, so the task board can count what the run paid out — and
	# so the game-over screen can offer to multiply it (see game_over.gd).
	CoinsManager.commit_session()
	DailyTasks.note_coins_earned(CoinsManager.session_earned)
	# Advance the interstitial's per-N-games counter. Counted here rather than at
	# the ad itself so quitting to home mid-run doesn't move the player toward the
	# next ad — only games actually played do.
	AdManager.note_game_finished()
	AudioManager.play_lose_sound()
	_set_status("Game Over!")
	# Arena race: record this attempt (rounds cleared = level - 1) on the room and
	# hand back to the live room, which shows the results/waiting board then the
	# final leaderboard once everyone's done. No replay — single attempt.
	if _is_contest:
		var ctx := GameState.contest_context.duplicate()
		GameState.contest_context = {}   # clear so a later normal game can't inherit it
		var cid := String(ctx.get("id", ""))
		var rounds := level - 1
		# Race games count toward engagement/score badges AND the solo leaderboards.
		# A race is still a real run at the room's difficulty, so its score
		# updates the player's personal best and the daily / all-time boards exactly
		# like a solo game — in addition to being recorded on the room itself.
		BadgeManager.note_game_played(GameState.difficulty)
		BadgeManager.note_score(GameState.difficulty, rounds)
		# …and toward today's task board, where a race also ticks the Arena task.
		DailyTasks.note_game_played(GameState.difficulty)
		DailyTasks.note_score(GameState.difficulty, rounds)
		DailyTasks.note_arena_played()
		# submit_score updates the in-memory best (and the guest file for signed-out
		# players); the return flags a new personal best, which gates the all-time
		# board write just as it does on the solo game-over screen.
		var is_new_high := GameState.submit_score(rounds)
		if FirebaseManager.is_signed_in() and FirebaseManager.has_display_name():
			# Daily best can move on any run (a non-PB run can still be today's best),
			# so submit unconditionally; the manager only writes if it beats today's row.
			LeaderboardManager.submit_score_daily(GameState.difficulty, rounds)
			if is_new_high:
				LeaderboardManager.submit_score(GameState.difficulty, rounds)
		await get_tree().create_timer(1.2).timeout
		await ContestManager.submit_result(cid, level - 1)
		if not is_inside_tree():
			return
		game_manager.show_contest_detail(cid)
		return
	await get_tree().create_timer(1.8).timeout
	if not is_inside_tree():
		return
	# The game-over interstitial, between the round ending and the results screen
	# appearing. Here rather than on the game-over screen itself so the ad lands in
	# the gap the player already reads as "the run is over", and the results are
	# the first thing they see when it closes — not something an ad interrupts.
	#
	# Always awaited: show_interstitial() emits interstitial_finished even when
	# policy or fill mean nothing is shown (the common case — see the caps in
	# ad_manager_levelplay.gd), so this costs a frame when there is no ad.
	AdManager.show_interstitial()
	await AdManager.interstitial_finished
	if not is_inside_tree():
		return
	game_manager.show_game_over(level - 1)

func _update_hud() -> void:
	if _wheel:
		# Clamped at 1: _start_game calls this with level 0 before it starts the
		# first round, and the LEVEL tab animates every change it is given — there
		# is no round zero to roll away from.
		_wheel.set_level(maxi(level, 1))
	if _watch_ad_btn:
		_watch_ad_btn.visible = AdManager.rewarded_ready

# Float a gold "+ N" beside the coin pill, drifting up and fading out. Replaces
# any indicator still in flight (rapid awards shouldn't pile up).
func _show_earn_indicator(amount: int) -> void:
	if _coin_panel == null:
		return
	if _earn_indicator and is_instance_valid(_earn_indicator):
		_earn_indicator.queue_free()
	var lbl := Label.new()
	lbl.text = "+ %d" % amount
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45))
	lbl.add_theme_color_override("font_shadow_color", Color(0.5, 0.32, 0.0, 0.7))
	lbl.add_theme_constant_override("shadow_offset_x", 0)
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	lbl.add_theme_constant_override("shadow_outline_size", 6)
	lbl.size = Vector2(90, 36)
	# Anchor immediately to the LEFT of the coin pill (it now sits at the top-right
	# corner, so a right-side float would run off screen), vertically centered.
	lbl.position = _coin_panel.position + Vector2(-90 - 6, (_coin_panel.size.y - 36) * 0.5)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)
	_earn_indicator = lbl

	# Quick scale-pop on the coin pill itself, so the change feels punchy.
	_coin_panel.pivot_offset = _coin_panel.size * 0.5
	var pop := create_tween()
	pop.tween_property(_coin_panel, "scale", Vector2.ONE * 1.12, 0.10) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	pop.tween_property(_coin_panel, "scale", Vector2.ONE, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 36.0, 0.85) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.85).set_delay(0.25)
	tw.chain().tween_callback(lbl.queue_free)
