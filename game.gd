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

var num_buttons: int
var sequence: Array[int] = []
var player_seq: Array[int] = []
var level: int = 0
var replays: int = 3
var flash_time: float
var flash_gap: float
var speed_inc: float

var _wheel: SimonWheel
var _state: String = "idle"  # idle, showing, input, gameover
var _last_input_frame: int = -1
# True when this game was launched from inside an Arena contest (GameState holds
# the contest context). Changes Quit -> Forfeit framing and makes the game-over
# flow route back to the contest + record the result.
var _is_contest: bool = false

var _status_lbl: Label
var _status_panel: Panel
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

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_is_contest = GameState.contest_context.has("id")
	num_buttons = GameState.num_colors
	flash_time = GameState.flash_time
	flash_gap = GameState.flash_gap
	speed_inc = GameState.speed_increase
	# 3D Simon wheel (rendered via SubViewport). Added before the HUD so it sits
	# behind the labels/buttons; it ignores mouse input - taps are handled here.
	_wheel = SimonWheel.new()
	add_child(_wheel)
	_layout_wheel()
	_wheel.configure(num_buttons, BUTTON_COLORS)
	_apply_simon_skin()
	get_viewport().size_changed.connect(_layout_wheel)
	_build_hud()
	await get_tree().process_frame
	_start_game()

func _process(_dt: float) -> void:
	# Ad loads asynchronously — update button visibility whenever it becomes ready
	if _watch_ad_btn and _state == "input":
		_watch_ad_btn.visible = AdManager.rewarded_ready

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

# Center the 3D wheel as a large square, leaving room for the top/bottom HUD.
func _layout_wheel() -> void:
	if _wheel == null:
		return
	var sz := get_viewport_rect().size
	var s: float = minf(sz.x, sz.y) * 0.92
	_wheel.size = Vector2(s, s)
	# Raise the wheel a little now that the coins HUD has moved out of the top
	# centre — fills the space the balance pill used to occupy.
	_wheel.position = Vector2((sz.x - s) * 0.5, (sz.y - s) * 0.5 - sz.y * 0.07)

# Apply the player's equipped Simon customization (shop "SIMON" tab or SPECIAL
# SKINS tab) to the wheel. CoinsManager is already loaded by the time a game
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
	var btn := _wheel.segment_at_point(tap_pos - _wheel.position)
	if btn >= 0:
		_player_pressed(btn)
		get_viewport().set_input_as_handled()

func _build_hud() -> void:
	var sz := get_viewport_rect().size

	# "Watch Ad to Replay" — modern amber glass pill, top-left. (The old "Level:"
	# caption above it is gone; the level now reads from the wheel's centre.)
	_watch_ad_btn = Button.new()
	_watch_ad_btn.text = "▶  Watch Ad to Replay"
	_watch_ad_btn.position = Vector2(20, 20)
	_watch_ad_btn.size = Vector2(244, 48)
	_watch_ad_btn.focus_mode = Control.FOCUS_NONE
	_watch_ad_btn.add_theme_font_size_override("font_size", 16)
	_glass_btn(_watch_ad_btn, Color(0.30, 0.20, 0.02), Color(1.0, 0.74, 0.18), Color(1.0, 0.90, 0.55))
	_watch_ad_btn.pressed.connect(_on_watch_ad)
	_watch_ad_btn.visible = false
	add_child(_watch_ad_btn)

	# Quit — subdued dark-red glass pill, top-right. In a contest it reads as
	# "Forfeit" (leaving still records the current score for the contest).
	_quit_btn = Button.new()
	_quit_btn.text = "✕  Forfeit" if _is_contest else "✕  Quit"
	_quit_btn.position = Vector2(sz.x - HUD_RIGHT_BTN_W - HUD_RIGHT_MARGIN, 20)
	_quit_btn.size = Vector2(HUD_RIGHT_BTN_W, 48)
	_quit_btn.focus_mode = Control.FOCUS_NONE
	_quit_btn.add_theme_font_size_override("font_size", 17)
	_glass_btn(_quit_btn, Color(0.20, 0.05, 0.06), Color(0.85, 0.30, 0.32), Color(1.0, 0.82, 0.82))
	_quit_btn.pressed.connect(_on_quit)
	add_child(_quit_btn)

	# Status line below the wheel, set inside an elegant dark-glass pill so the
	# prompt reads as a deliberate readout instead of floating text.
	_build_status_bar(sz)

	if FirebaseManager.is_signed_in():
		_build_coin_hud(sz)
	_build_quit_dialog(sz)

# Modern rounded-glass button: dark translucent body, a soft accent rim/glow and
# light label. Replaces the old flat fills on the gameplay HUD buttons.
func _glass_btn(btn: Button, body: Color, accent: Color, fg: Color) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(body.r, body.g, body.b, 0.86)
	s.set_corner_radius_all(24)
	s.border_color = Color(accent.r, accent.g, accent.b, 0.85)
	s.set_border_width_all(2)
	s.shadow_color = Color(accent.r, accent.g, accent.b, 0.30)
	s.shadow_size = 10
	s.content_margin_left = 8
	s.content_margin_right = 8
	btn.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = Color(body.r, body.g, body.b, 0.86).lightened(0.12)
	sh.shadow_size = 14
	btn.add_theme_stylebox_override("hover", sh)
	var sp := s.duplicate() as StyleBoxFlat
	sp.bg_color = Color(body.r, body.g, body.b, 0.95).darkened(0.18)
	btn.add_theme_stylebox_override("pressed", sp)
	var sd := s.duplicate() as StyleBoxFlat
	sd.bg_color = Color(body.r, body.g, body.b, 0.55)
	sd.border_color = Color(accent.r, accent.g, accent.b, 0.4)
	btn.add_theme_stylebox_override("disabled", sd)
	btn.add_theme_color_override("font_color", fg)
	btn.add_theme_color_override("font_hover_color", fg.lightened(0.15))
	btn.add_theme_color_override("font_pressed_color", fg)

# Status prompt below the wheel, housed in a soft dark-glass pill that auto-fits
# the text width (kept centred). Built once; _set_status() updates the text.
func _build_status_bar(sz: Vector2) -> void:
	_status_panel = Panel.new()
	_status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.04, 0.05, 0.13, 0.80)
	st.set_corner_radius_all(22)
	st.border_color = Color(0.45, 0.55, 1.0, 0.35)
	st.set_border_width_all(1)
	st.shadow_color = Color(0.15, 0.25, 0.7, 0.30)
	st.shadow_size = 14
	_status_panel.add_theme_stylebox_override("panel", st)
	add_child(_status_panel)

	_status_lbl = Label.new()
	_status_lbl.add_theme_font_size_override("font_size", 26)
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
	var sz := get_viewport_rect().size
	var font := _status_lbl.get_theme_font("font")
	var tw: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	var pw: float = maxf(180.0, tw + 56.0)
	const PH := 52.0
	_status_panel.size = Vector2(pw, PH)
	_status_panel.position = Vector2(sz.x * 0.5 - pw * 0.5, sz.y - 84.0)
	_status_panel.visible = txt != ""
	_status_lbl.position = Vector2.ZERO
	_status_lbl.size = Vector2(pw, PH)

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
	var disc := Panel.new()
	disc.size = Vector2(d, d)
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ds := StyleBoxFlat.new()
	ds.bg_color = Color(1.0, 0.78, 0.16)
	ds.set_corner_radius_all(int(d * 0.5))
	ds.border_color = Color(1.0, 0.92, 0.55)
	ds.set_border_width_all(2)
	ds.shadow_color = Color(1.0, 0.6, 0.0, 0.55)
	ds.shadow_size = 5
	disc.add_theme_stylebox_override("panel", ds)
	c.add_child(disc)
	var glyph := Label.new()
	glyph.text = "$"
	glyph.add_theme_font_size_override("font_size", int(d * 0.7))
	glyph.add_theme_color_override("font_color", Color(0.45, 0.30, 0.05))
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
	sn.bg_color = Color(0.05, 0.05, 0.2, 0.97)
	sn.corner_radius_top_left = 18; sn.corner_radius_top_right = 18
	sn.corner_radius_bottom_left = 18; sn.corner_radius_bottom_right = 18
	sn.border_color = Color(0.5, 0.15, 0.15)
	sn.border_width_left = 2; sn.border_width_right = 2
	sn.border_width_top = 2; sn.border_width_bottom = 2
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

	var yes := Button.new()
	yes.text = "Yes, Forfeit" if _is_contest else "Yes, Quit"
	yes.position = Vector2(24, 120)
	yes.size = Vector2(155, 52)
	yes.add_theme_font_size_override("font_size", 18)
	_flat_btn(yes, Color(0.55, 0.12, 0.12))
	yes.pressed.connect(_on_quit_confirmed)
	overlay.add_child(yes)

	var no := Button.new()
	no.text = "Keep Playing"
	no.position = Vector2(201, 120)
	no.size = Vector2(155, 52)
	no.add_theme_font_size_override("font_size", 18)
	_flat_btn(no, Color(0.15, 0.45, 0.2))
	no.pressed.connect(func() -> void: get_node("QuitDialog").visible = false)
	overlay.add_child(no)

func _flat_btn(btn: Button, col: Color) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.corner_radius_top_left = 10; s.corner_radius_top_right = 10
	s.corner_radius_bottom_left = 10; s.corner_radius_bottom_right = 10
	btn.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat; sh.bg_color = col.lightened(0.2)
	btn.add_theme_stylebox_override("hover", sh)
	var sp := s.duplicate() as StyleBoxFlat; sp.bg_color = col.darkened(0.15)
	btn.add_theme_stylebox_override("pressed", sp)
	btn.add_theme_color_override("font_color", Color.WHITE)

func _start_game() -> void:
	sequence = []
	player_seq = []
	level = 0
	replays = 0
	CoinsManager.start_game_session()
	_update_hud()
	_next_round()

func _next_round() -> void:
	level += 1
	player_seq = []
	sequence.append(randi() % num_buttons)
	flash_time = maxf(0.18, GameState.flash_time - (level - 1) * speed_inc)
	flash_gap = maxf(0.08, GameState.flash_gap - (level - 1) * speed_inc * 0.5)
	_update_hud()
	# Volcano skin only: hitting level 8 flashes a "you are on fire!" banner. The
	# round waits for it to fade before the sequence starts, then Simon continues.
	if level == 8 and _is_volcano_skin():
		await _show_fire_text()
	_set_status("Watch carefully...")
	_state = "showing"
	await get_tree().create_timer(0.6).timeout
	await _play_sequence()
	_state = "input"
	_set_status("Your turn!")

# True when the equipped Simon look is the Volcano ("inferno") special skin — the
# same resolution _apply_simon_skin uses (a manual per-part look never counts).
func _is_volcano_skin() -> bool:
	return not CoinsManager.is_simon_manual() and CoinsManager.selected_skin == "inferno"

# Flash a big "YOU'RE ON FIRE!" banner across the screen, hold it, then fade it out
# — ~3.3s total. Awaited by _next_round so the sequence only resumes once it fades.
# Built from stacked layers (soft outer glow behind a molten-gradient-feel main
# layer) and bursts in with a scale pop so it lands like a real hype moment.
func _show_fire_text() -> void:
	# Full-screen holder we can scale-pop around the screen centre.
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.modulate.a = 0.0
	add_child(holder)
	var screen := get_viewport_rect().size
	holder.pivot_offset = screen * 0.5

	# Font size scales with the screen so it reads huge on phones and desktop alike,
	# but stays within the width (with margins) so the line never clips.
	var fs := int(clampf(screen.x * 0.16, 72.0, 168.0))
	var txt := "YOU'RE ON FIRE!"

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
		_state = "showing"
		var correct := sequence[step]
		_set_status("The correct button was...")
		await get_tree().create_timer(0.35).timeout
		for _i in 3:
			await _flash(correct, 0.28)
			await get_tree().create_timer(0.14).timeout
		_game_over()
		return
	if player_seq.size() == sequence.size():
		_state = "idle"
		_set_status("Correct! Get ready...")
		# Award coins for this completed level and float a "+ N" indicator
		# next to the balance pill. Returns 0 if not signed in.
		var earned := CoinsManager.award_for_level(GameState.difficulty, level)
		if earned > 0:
			_show_earn_indicator(earned)
		BackgroundManager.notify_level_complete(level)      # kitty theme winks + cheers
		# Every 3 rounds the Volcano skin's central hub volcano erupts and feeds a surge
		# of fresh lava into the background river. Both calls are no-ops off the skin.
		if level % 3 == 0:
			_wheel.electric_pulse()   # premium electric charge flourish (non-casino skins)
			_wheel.roulette_spin()    # Jackpot skin: ivory ball laps the gold ring
			_wheel.erupt()
			BackgroundManager.surge_river()
		# Every 5 rounds the Arcade skin's cabinets all flash a giant glowing "OMG" for 4s.
		# No-op off the Arcade skin. Independent of the every-3 pulse; on round 15/30 both
		# fire together. Purely cosmetic — never awaited, so gameplay timing is untouched.
		if level % 5 == 0:
			BackgroundManager.arcade_omg()
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

func _on_quit() -> void:
	get_node("QuitDialog").visible = true

# "Yes" in the quit dialog. Normal play → home. Contest play → forfeit, which
# runs the normal game-over flow so the current score is recorded for the
# contest (game_over.gd sees GameState.contest_context and routes back).
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

func _game_over() -> void:
	_state = "gameover"
	# Bank the coins earned this session into the persistent wallet.
	CoinsManager.commit_session()
	AudioManager.play_lose_sound()
	_set_status("Game Over!")
	# Skip the post-game interstitial for players who bought the remove-ads
	# entitlement. Rewarded ads (the in-game "watch ad to replay" button) are
	# user-initiated and unaffected — the purchase only suppresses ads we'd
	# otherwise force on the player.
	if level > 5 and not CoinsManager.has_remove_ads:
		AdManager.try_show_interstitial()
	await get_tree().create_timer(1.8).timeout
	game_manager.show_game_over(level - 1)

func _update_hud() -> void:
	if _wheel:
		_wheel.set_level(level)
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
