extends Control

# Modal popup for the daily-claim streak. Days 1-14 are shown as a 2x7 calendar
# of coin-medallion cells (the cell matching `next_claim_day()` glows as TODAY,
# earlier days are marked claimed with a green check, later days sit faded). On
# day 15+ the grid is replaced by a single big "endless streak" celebration card
# — one giant day-number, a glowing coin medallion, and the flat +100 reward —
# because there is no useful ladder past the cap.
#
# Either way, the bottom action button claims today's reward via CoinsManager and
# the popup self-closes after a brief celebratory burst.
#
# Visual language matches the player-profile dialog: a glassy panel with a header
# band, drawn-in light (top sheen + pooled bottom shadow), soft ambient shadows,
# hairline dividers, and fully procedural coins / sparkles / flame — no PNGs, no
# exported scene. This screen overlays the home screen (added as its child).

const ROWS := 2
const COLS := 7
const CELL := Vector2(82, 110)
const CELL_GAP := 12.0
const DIALOG_W := 768.0
const DIALOG_H := 524.0
# Day at which the grid is replaced by the endless-streak view. Must match
# CoinsManager's reward curve breakpoint (day 14 = last grid cell, 15+ flat).
const ENDLESS_DAY := 15

# Palette — deep navy glass with warm gold accents, echoing the profile dialog.
const GOLD := Color(1.0, 0.82, 0.30)
const GOLD_HI := Color(1.0, 0.93, 0.58)
const BLUE := Color(0.40, 0.54, 1.0)        # structural accent (dividers / header line)
const GREEN := Color(0.44, 0.92, 0.56)      # claimed state

var _backdrop: ColorRect
var _dialog: Panel
var _grid: Control                          # manual-layout holder so we can float a glow behind a cell
var _streak_chip: Panel
var _action_btn: Button
var _action_lbl: Label
var _cells: Array[Dictionary] = []   # per cell: { panel, day, day_lbl, reward_lbl, coin, check, dimmable }
var _today_cell: Dictionary = {}     # the claimable cell, kept for the pulse loop
var _today_glow: Panel = null        # soft gold halo floated behind the today cell
var _is_endless := false
# Endless-view widgets we animate on _ready, kept as members so we can drive the
# looping sparkle / coin-bob tweens without re-querying the tree.
var _endless_day_lbl: Label = null
var _endless_coin: Node2D = null
var _endless_sparkles: Array[Node2D] = []
var _ambient_sparkles: Array[Node2D] = []

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP            # eats clicks behind
	_is_endless = CoinsManager.next_claim_day() >= ENDLESS_DAY
	_build()
	_layout()
	get_viewport().size_changed.connect(_layout)
	_start_animations()
	# Pop-in tween on the dialog so the open feels intentional.
	_dialog.pivot_offset = _dialog.size * 0.5
	_dialog.scale = Vector2.ONE * 0.85
	_dialog.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_dialog, "scale", Vector2.ONE, 0.20) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_dialog, "modulate:a", 1.0, 0.18)
	tw.tween_property(_backdrop, "modulate:a", 1.0, 0.18).from(0.0)

func _build() -> void:
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.01, 0.02, 0.06, 0.66)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.gui_input.connect(_on_backdrop_click)
	add_child(_backdrop)

	_dialog = Panel.new()
	_dialog.size = Vector2(DIALOG_W, DIALOG_H)
	_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	var ds := StyleBoxFlat.new()
	ds.bg_color = Color(0.045, 0.055, 0.155, 0.99)
	ds.set_corner_radius_all(26)
	ds.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.60)
	ds.set_border_width_all(2)
	_polish(ds)
	_elevate(ds, 0.42, 34, 6.0)
	_dialog.add_theme_stylebox_override("panel", ds)
	add_child(_dialog)
	# Full-panel depth: a top sheen and a pooled bottom shadow no flat box can express.
	_add_depth(_dialog, _dialog.size, 26, 0.05, 0.24)

	# ── header band ──────────────────────────────────────────────────────────
	var band := Panel.new()
	band.position = Vector2(2, 2)
	band.size = Vector2(DIALOG_W - 4, 66)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.10, 0.085, 0.19, 0.94)
	bs.corner_radius_top_left = 24
	bs.corner_radius_top_right = 24
	_polish(bs)
	band.add_theme_stylebox_override("panel", bs)
	# Glassy top sheen + a warm backlit line along the band's lower edge.
	band.draw.connect(func() -> void:
		_vgrad(band, Rect2(2, 1.5, DIALOG_W - 8, 30),
			Color(1, 1, 1, 0.055), Color(1, 1, 1, 0.0))
		_vgrad(band, Rect2(16, 63, DIALOG_W - 36, 3),
			Color(GOLD.r, GOLD.g, GOLD.b, 0.0), Color(GOLD.r, GOLD.g, GOLD.b, 0.32)))
	_dialog.add_child(band)

	var title := Label.new()
	title.text = "DAILY REWARD"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", GOLD_HI)
	title.add_theme_color_override("font_shadow_color", Color(0.55, 0.35, 0.0, 0.55))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 3)
	title.add_theme_constant_override("shadow_outline_size", 8)
	title.position = Vector2(0, 15)
	title.size = Vector2(DIALOG_W, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog.add_child(title)

	# ── streak chip (flame + "N-DAY STREAK") ────────────────────────────────
	_build_streak_chip()

	# ── body: grid calendar or endless card ─────────────────────────────────
	if _is_endless:
		_build_endless_card()
	else:
		_build_grid()

	# ── action button / claimed label ───────────────────────────────────────
	_action_btn = Button.new()
	_action_btn.size = Vector2(320, 66)
	_action_btn.position = Vector2((DIALOG_W - 320) * 0.5, DIALOG_H - 66 - 30)
	_action_btn.focus_mode = Control.FOCUS_NONE
	_action_btn.add_theme_font_size_override("font_size", 25)
	_action_btn.pressed.connect(_on_action)
	_dialog.add_child(_action_btn)

	# Plain text shown in place of the button once the daily reward has already
	# been claimed — "come back tomorrow" is information, not an action.
	_action_lbl = Label.new()
	_action_lbl.size = Vector2(DIALOG_W, 66)
	_action_lbl.position = Vector2(0, DIALOG_H - 66 - 30)
	_action_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_action_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_action_lbl.add_theme_font_size_override("font_size", 22)
	_action_lbl.add_theme_color_override("font_color", Color(0.62, 0.90, 0.70, 0.9))
	_action_lbl.visible = false
	_dialog.add_child(_action_lbl)

	# Corner close button.
	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.size = Vector2(40, 40)
	close.position = Vector2(DIALOG_W - 52, 14)
	close.add_theme_font_size_override("font_size", 22)
	close.add_theme_color_override("font_color", Color(0.82, 0.78, 1.0, 0.72))
	close.add_theme_color_override("font_hover_color", Color(1.0, 0.45, 0.45))
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(_close)
	_dialog.add_child(close)

	# Ambient corner sparkles frame the whole dialog with a little life.
	for p in [Vector2(40, 96), Vector2(DIALOG_W - 40, 100),
			Vector2(52, DIALOG_H - 118), Vector2(DIALOG_W - 52, DIALOG_H - 122)]:
		var s := _make_sparkle(7.0)
		s.position = p
		_dialog.add_child(s)
		_ambient_sparkles.append(s)

	_refresh_states()

# ── streak chip ─────────────────────────────────────────────────────────────

# A rounded pill under the title: a small drawn flame + "N-DAY STREAK". Reads as
# the emotional hook ("don't break it") that the raw grid can't convey on its own.
func _build_streak_chip() -> void:
	_streak_chip = Panel.new()
	_streak_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.12)
	cs.set_corner_radius_all(16)
	cs.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.45)
	cs.set_border_width_all(1)
	_polish(cs)
	_streak_chip.add_theme_stylebox_override("panel", cs)
	_dialog.add_child(_streak_chip)

	var streak: int = maxi(1, CoinsManager.streak_days)
	var flame := _make_flame(15.0)
	flame.position = Vector2(24, 20)
	flame.name = "flame"
	_streak_chip.add_child(flame)

	var lbl := Label.new()
	lbl.name = "lbl"
	lbl.text = ("%d-DAY STREAK" % streak) if not _is_endless else "STREAK UNSTOPPABLE"
	lbl.add_theme_font_size_override("font_size", 17)
	lbl.add_theme_color_override("font_color", GOLD_HI)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_streak_chip.add_child(lbl)

	# Size the pill to its contents; positioned in _layout.
	var text_w := lbl.get_theme_font("font").get_string_size(
		lbl.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		lbl.get_theme_font_size("font_size")).x
	var chip_w := 44.0 + text_w + 22.0
	_streak_chip.size = Vector2(chip_w, 40)
	lbl.position = Vector2(42, 0)
	lbl.size = Vector2(text_w + 10, 40)

# ── grid calendar (days 1-14) ────────────────────────────────────────────────

func _build_grid() -> void:
	var grid_w := COLS * CELL.x + (COLS - 1) * CELL_GAP
	var grid_h := ROWS * CELL.y + (ROWS - 1) * CELL_GAP
	_grid = Control.new()
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid.position = Vector2((DIALOG_W - grid_w) * 0.5, 128)
	_grid.size = Vector2(grid_w, grid_h)
	_dialog.add_child(_grid)

	var next_day := CoinsManager.next_claim_day()
	for day in range(1, COLS * ROWS + 1):
		var col := (day - 1) % COLS
		var row := (day - 1) / COLS
		var c := _make_cell(day)
		var panel: Panel = c["panel"]
		panel.position = Vector2(col * (CELL.x + CELL_GAP), row * (CELL.y + CELL_GAP))
		_grid.add_child(panel)
		_cells.append(c)
		if day == next_day:
			_today_cell = c

	# Float a soft gold halo BEHIND the today cell (index 0 = drawn first).
	if not _today_cell.is_empty() and CoinsManager.can_claim_today():
		var tp: Panel = _today_cell["panel"]
		_today_glow = Panel.new()
		_today_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_today_glow.position = tp.position - Vector2(9, 9)
		_today_glow.size = CELL + Vector2(18, 18)
		var gs := StyleBoxFlat.new()
		gs.bg_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.0)
		gs.set_corner_radius_all(20)
		gs.shadow_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.55)
		gs.shadow_size = 22
		_polish(gs)
		_today_glow.add_theme_stylebox_override("panel", gs)
		_grid.add_child(_today_glow)
		_grid.move_child(_today_glow, 0)

	# A hairline caption under the grid ties the calendar to the button.
	var div := _soft_divider(grid_w * 0.7, BLUE)
	div.position = Vector2((DIALOG_W - grid_w * 0.7) * 0.5, 128 + grid_h + 16)
	_dialog.add_child(div)
	var cap := Label.new()
	cap.text = "Come back every day — miss one and the streak resets"
	cap.add_theme_font_size_override("font_size", 14)
	cap.add_theme_color_override("font_color", Color(0.70, 0.75, 1.0, 0.72))
	cap.position = Vector2(0, 128 + grid_h + 24)
	cap.size = Vector2(DIALOG_W, 20)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog.add_child(cap)

func _make_cell(day: int) -> Dictionary:
	var cell := Panel.new()
	cell.custom_minimum_size = CELL
	cell.size = CELL
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Depth overlay first so the coin + labels drawn after it stay crisp on top.
	_add_depth(cell, CELL, 16, 0.05, 0.16)

	var day_lbl := Label.new()
	day_lbl.text = "DAY %d" % day
	day_lbl.add_theme_font_size_override("font_size", 13)
	day_lbl.add_theme_color_override("font_color", Color(0.80, 0.85, 1.0, 0.85))
	day_lbl.position = Vector2(0, 11)
	day_lbl.size = Vector2(CELL.x, 18)
	day_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	day_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(day_lbl)

	# Real coin medallion (disc + rim + "$"), centered.
	var coin := _make_coin_medallion(38.0)
	coin.position = Vector2(CELL.x * 0.5, 56)
	cell.add_child(coin)

	# Green check badge over the coin, shown for claimed days.
	var check := _make_check(11.0)
	check.position = Vector2(CELL.x * 0.5 + 15, 40)
	check.visible = false
	cell.add_child(check)

	var reward_lbl := Label.new()
	reward_lbl.text = "+%d" % CoinsManager.daily_reward_for_day(day)
	reward_lbl.add_theme_font_size_override("font_size", 19)
	reward_lbl.add_theme_color_override("font_color", Color.WHITE)
	reward_lbl.position = Vector2(0, CELL.y - 27)
	reward_lbl.size = Vector2(CELL.x, 22)
	reward_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reward_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(reward_lbl)

	return {"panel": cell, "day": day, "day_lbl": day_lbl,
		"reward_lbl": reward_lbl, "coin": coin, "check": check}

# Style each cell by state: claimed (green + check), today (gold glow + "TODAY"),
# or future (faded). Also updates the bottom action button. In endless mode the
# cells array is empty, so the loop is a no-op and only the button is updated.
func _refresh_states() -> void:
	var next_day := CoinsManager.next_claim_day()
	var can_claim := CoinsManager.can_claim_today()
	for c in _cells:
		var day: int = c["day"]
		var panel: Panel = c["panel"]
		var day_lbl: Label = c["day_lbl"]
		var reward_lbl: Label = c["reward_lbl"]
		var coin: Node2D = c["coin"]
		var check: Node2D = c["check"]
		var st := StyleBoxFlat.new()
		st.set_corner_radius_all(16)
		_polish(st)
		var claimed := day < next_day or (day == next_day and not can_claim)
		if day == next_day and can_claim:
			# Today's reward — gold rim, warm fill, "TODAY".
			st.bg_color = Color(0.20, 0.16, 0.06, 0.96)
			st.border_color = GOLD
			st.set_border_width_all(2)
			_elevate(st, 0.30, 8, 3.0)
			panel.add_theme_stylebox_override("panel", st)
			day_lbl.text = "TODAY"
			day_lbl.add_theme_color_override("font_color", GOLD_HI)
			day_lbl.add_theme_font_size_override("font_size", 14)
			reward_lbl.add_theme_color_override("font_color", GOLD_HI)
			coin.modulate = Color.WHITE
			check.visible = false
		elif claimed:
			# Already collected in this streak — green, dimmed, checked.
			st.bg_color = Color(0.09, 0.19, 0.12, 0.92)
			st.border_color = Color(GREEN.r, GREEN.g, GREEN.b, 0.55)
			st.set_border_width_all(1)
			panel.add_theme_stylebox_override("panel", st)
			day_lbl.add_theme_color_override("font_color", Color(GREEN.r, GREEN.g, GREEN.b, 0.85))
			reward_lbl.add_theme_color_override("font_color", Color(0.72, 0.90, 0.78, 0.85))
			coin.modulate = Color(0.82, 0.9, 0.82, 0.7)
			check.visible = true
		else:
			# Future days — faded blue-grey.
			st.bg_color = Color(0.065, 0.08, 0.185, 0.88)
			st.border_color = Color(0.32, 0.37, 0.58, 0.42)
			st.set_border_width_all(1)
			panel.add_theme_stylebox_override("panel", st)
			day_lbl.add_theme_color_override("font_color", Color(0.70, 0.75, 1.0, 0.55))
			reward_lbl.add_theme_color_override("font_color", Color(0.80, 0.84, 1.0, 0.6))
			coin.modulate = Color(0.7, 0.72, 0.85, 0.5)
			check.visible = false

	if _today_glow:
		_today_glow.visible = can_claim

	# Action button reflects claim state.
	if can_claim:
		_action_btn.visible = true
		_action_lbl.visible = false
		_action_btn.text = "CLAIM  +%d" % CoinsManager.daily_reward_for_day(next_day)
		_style_action_button()
		_action_btn.disabled = false
	else:
		# Already claimed today — show plain text instead of a (dead) button.
		_action_btn.visible = false
		_action_lbl.visible = true
		_action_lbl.text = "Claimed — come back tomorrow"

# Gold gradient-lit action button with a top sheen and a soft downward glow.
func _style_action_button() -> void:
	var base := Color(1.00, 0.66, 0.10)
	var fg := Color(0.20, 0.11, 0.0)
	var s := StyleBoxFlat.new()
	s.bg_color = base
	s.set_corner_radius_all(18)
	s.border_color = GOLD_HI
	s.set_border_width_all(1)
	_polish(s)
	s.shadow_color = Color(base.r, base.g, base.b, 0.45)
	s.shadow_size = 16
	s.shadow_offset = Vector2(0, 4)
	_action_btn.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = base.lightened(0.14)
	_action_btn.add_theme_stylebox_override("hover", sh)
	var sp := s.duplicate() as StyleBoxFlat
	sp.bg_color = base.darkened(0.18)
	sp.shadow_size = 8
	_action_btn.add_theme_stylebox_override("pressed", sp)
	var sd := s.duplicate() as StyleBoxFlat
	sd.bg_color = base.darkened(0.05)
	_action_btn.add_theme_stylebox_override("disabled", sd)
	_action_btn.add_theme_color_override("font_color", fg)
	_action_btn.add_theme_color_override("font_hover_color", fg)
	_action_btn.add_theme_color_override("font_disabled_color", fg)
	# A one-time top sheen overlay across the button face.
	if not _action_btn.has_meta("sheened"):
		_action_btn.set_meta("sheened", true)
		var ov := Control.new()
		ov.set_anchors_preset(Control.PRESET_FULL_RECT)
		ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ov.draw.connect(func() -> void:
			_vgrad(ov, Rect2(10, 3, _action_btn.size.x - 20, _action_btn.size.y * 0.5),
				Color(1, 1, 1, 0.22), Color(1, 1, 1, 0.0)))
		_action_btn.add_child(ov)

# ── endless-streak view (day 15+) ────────────────────────────────────────────

# Single big celebratory card replacing the 14-day grid. Centers a huge "DAY N"
# label, a gold coin medallion with the flat +N reward beside it, and an
# "ENDLESS STREAK" badge, all seated on a softly-lit hero panel.
func _build_endless_card() -> void:
	var day := CoinsManager.next_claim_day()
	var reward := CoinsManager.daily_reward_for_day(day)
	var area_top := 108.0

	# Hero panel behind the celebration content for depth.
	var hero := Panel.new()
	var hero_w := 520.0
	var hero_h := 250.0
	hero.position = Vector2((DIALOG_W - hero_w) * 0.5, area_top)
	hero.size = Vector2(hero_w, hero_h)
	hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hs := StyleBoxFlat.new()
	hs.bg_color = Color(0.09, 0.085, 0.20, 0.85)
	hs.set_corner_radius_all(22)
	hs.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.35)
	hs.set_border_width_all(1)
	_polish(hs)
	_elevate(hs, 0.30, 14, 5.0)
	hero.add_theme_stylebox_override("panel", hs)
	_dialog.add_child(hero)
	_add_depth(hero, hero.size, 22, 0.05, 0.20)

	# Sparkles flanking the hero content.
	var sparkle_positions := [
		Vector2(150, area_top + 44),  Vector2(618, area_top + 48),
		Vector2(176, area_top + 210), Vector2(596, area_top + 208),
	]
	for p in sparkle_positions:
		var s := _make_sparkle(9.0)
		s.position = p
		_dialog.add_child(s)
		_endless_sparkles.append(s)

	# The giant day number — the focal point.
	_endless_day_lbl = Label.new()
	_endless_day_lbl.text = "DAY %d" % day
	_endless_day_lbl.add_theme_font_size_override("font_size", 88)
	_endless_day_lbl.add_theme_color_override("font_color", GOLD_HI)
	_endless_day_lbl.add_theme_color_override("font_outline_color", GOLD_HI)
	_endless_day_lbl.add_theme_constant_override("outline_size", 2)
	_endless_day_lbl.add_theme_color_override("font_shadow_color", Color(1.0, 0.55, 0.10, 0.7))
	_endless_day_lbl.add_theme_constant_override("shadow_offset_x", 0)
	_endless_day_lbl.add_theme_constant_override("shadow_offset_y", 0)
	_endless_day_lbl.add_theme_constant_override("shadow_outline_size", 22)
	_endless_day_lbl.position = Vector2(0, area_top + 22)
	_endless_day_lbl.size = Vector2(DIALOG_W, 104)
	_endless_day_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_endless_day_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_endless_day_lbl.pivot_offset = Vector2(DIALOG_W * 0.5, 52)
	_endless_day_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog.add_child(_endless_day_lbl)

	# Coin medallion + reward, horizontally grouped & centered.
	var coin_d := 66.0
	var row := Control.new()
	var row_w := 280.0
	row.size = Vector2(row_w, 80)
	row.position = Vector2((DIALOG_W - row_w) * 0.5, area_top + 140)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog.add_child(row)

	_endless_coin = _make_coin_medallion(coin_d)
	_endless_coin.position = Vector2(42, 40)
	row.add_child(_endless_coin)

	var reward_lbl := Label.new()
	reward_lbl.text = "+%d" % reward
	reward_lbl.add_theme_font_size_override("font_size", 56)
	reward_lbl.add_theme_color_override("font_color", GOLD_HI)
	reward_lbl.add_theme_color_override("font_shadow_color", Color(0.6, 0.40, 0.0, 0.7))
	reward_lbl.add_theme_constant_override("shadow_offset_x", 0)
	reward_lbl.add_theme_constant_override("shadow_offset_y", 3)
	reward_lbl.add_theme_constant_override("shadow_outline_size", 9)
	reward_lbl.position = Vector2(94, 0)
	reward_lbl.size = Vector2(row_w - 94, 80)
	reward_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	reward_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	reward_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(reward_lbl)

	# Badge subtitle.
	var badge := Label.new()
	badge.text = "✦   ENDLESS  STREAK   ✦"
	badge.add_theme_font_size_override("font_size", 20)
	badge.add_theme_color_override("font_color", Color(0.88, 0.82, 1.0))
	badge.add_theme_color_override("font_shadow_color", Color(0.55, 0.45, 1.0, 0.55))
	badge.add_theme_constant_override("shadow_offset_x", 0)
	badge.add_theme_constant_override("shadow_offset_y", 0)
	badge.add_theme_constant_override("shadow_outline_size", 8)
	badge.position = Vector2(0, area_top + 224)
	badge.size = Vector2(DIALOG_W, 26)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog.add_child(badge)

# ── procedural art helpers ───────────────────────────────────────────────────

# Gold coin disc + ring + "$" glyph, drawn as Polygon2D + Label so it can rotate
# / scale as a single Node2D. Same look as the shop's medallion.
func _make_coin_medallion(d: float) -> Node2D:
	var n := Node2D.new()
	var glow := Polygon2D.new()
	glow.polygon = _circle_polygon(d * 0.5 + 6.0, 32)
	glow.color = Color(1.0, 0.85, 0.30, 0.18)
	n.add_child(glow)
	var rim := Polygon2D.new()
	rim.polygon = _circle_polygon(d * 0.5 + 3.0, 32)
	rim.color = Color(1.0, 0.92, 0.55, 0.95)
	n.add_child(rim)
	var disc := Polygon2D.new()
	disc.polygon = _circle_polygon(d * 0.5, 32)
	disc.color = Color(1.0, 0.78, 0.20)
	n.add_child(disc)
	# Inner shading ring for a minted look.
	var inner := Polygon2D.new()
	inner.polygon = _circle_polygon(d * 0.36, 28)
	inner.color = Color(1.0, 0.85, 0.34, 0.6)
	n.add_child(inner)
	var glyph := Label.new()
	glyph.text = "$"
	glyph.add_theme_font_size_override("font_size", int(d * 0.66))
	glyph.add_theme_color_override("font_color", Color(0.45, 0.30, 0.05))
	glyph.position = Vector2(-d * 0.5, -d * 0.55)
	glyph.size = Vector2(d, d)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.add_child(glyph)
	return n

# Small green disc with a drawn white checkmark (a claimed-day stamp).
func _make_check(r: float) -> Node2D:
	var n := Node2D.new()
	var rim := Polygon2D.new()
	rim.polygon = _circle_polygon(r + 1.5, 20)
	rim.color = Color(0.06, 0.16, 0.09, 0.95)
	n.add_child(rim)
	var disc := Polygon2D.new()
	disc.polygon = _circle_polygon(r, 20)
	disc.color = GREEN
	n.add_child(disc)
	var tick := Line2D.new()
	tick.points = PackedVector2Array([
		Vector2(-r * 0.45, 0.0), Vector2(-r * 0.1, r * 0.4), Vector2(r * 0.5, -r * 0.45)])
	tick.width = maxf(2.0, r * 0.28)
	tick.default_color = Color(0.05, 0.16, 0.08)
	tick.joint_mode = Line2D.LINE_JOINT_ROUND
	tick.begin_cap_mode = Line2D.LINE_CAP_ROUND
	tick.end_cap_mode = Line2D.LINE_CAP_ROUND
	n.add_child(tick)
	return n

# A little flame (an orange silhouette with a brighter inner core), centered on
# its position — for the streak chip.
func _make_flame(h: float) -> Node2D:
	var n := Node2D.new()
	var outer := Polygon2D.new()
	outer.polygon = _flame_shape(h)
	outer.color = Color(1.0, 0.52, 0.12)
	n.add_child(outer)
	var inner := Polygon2D.new()
	inner.polygon = _flame_shape(h * 0.6)
	inner.position = Vector2(0, h * 0.20)
	inner.color = Color(1.0, 0.86, 0.34)
	n.add_child(inner)
	return n

# Classic flame silhouette: sharp tip at top, rounded belly, centered on origin.
# Built from a normalized right-half outline (scaled by s) then mirrored.
func _flame_shape(h: float) -> PackedVector2Array:
	var s := h * 0.58
	var right := [
		Vector2(0.00, -1.00),   # tip
		Vector2(0.34, -0.22),
		Vector2(0.22, 0.06),
		Vector2(0.50, 0.36),
		Vector2(0.34, 0.78),
		Vector2(0.00, 0.98),    # bottom
	]
	var p := PackedVector2Array()
	for v in right:
		p.append((v as Vector2) * s)
	for i in range(right.size() - 2, 0, -1):
		var v: Vector2 = right[i]
		p.append(Vector2(-v.x, v.y) * s)
	return p

# Four-pointed star shape, centered on its position; scale tweens look great.
func _make_sparkle(r: float) -> Node2D:
	var n := Node2D.new()
	var star := Polygon2D.new()
	var inner := r * 0.32
	star.polygon = PackedVector2Array([
		Vector2(0, -r),       Vector2(inner, -inner),
		Vector2(r, 0),        Vector2(inner, inner),
		Vector2(0, r),        Vector2(-inner, inner),
		Vector2(-r, 0),       Vector2(-inner, -inner),
	])
	star.color = Color(1.0, 0.95, 0.65, 0.9)
	n.add_child(star)
	return n

func _circle_polygon(r: float, n: int) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in n:
		var a: float = TAU * float(i) / n
		p.append(Vector2(cos(a), sin(a)) * r)
	return p

# ── animations ───────────────────────────────────────────────────────────────

func _start_animations() -> void:
	# Ambient sparkles twinkle independently in both modes.
	for i in _ambient_sparkles.size():
		_twinkle(_ambient_sparkles[i], i)
	if _is_endless:
		_start_endless_animations()
	else:
		_start_today_pulse()

# Grid mode: the claimable "today" cell breathes — the coin bobs in scale and the
# halo behind it pulses, drawing the eye to the reward waiting to be taken.
func _start_today_pulse() -> void:
	if _today_cell.is_empty() or not CoinsManager.can_claim_today():
		return
	var coin: Node2D = _today_cell["coin"]
	if coin:
		var bob := create_tween().set_loops()
		bob.tween_property(coin, "scale", Vector2.ONE * 1.12, 0.75) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		bob.tween_property(coin, "scale", Vector2.ONE, 0.75) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if _today_glow:
		var pulse := create_tween().set_loops()
		pulse.tween_property(_today_glow, "modulate:a", 1.0, 0.85) \
			.from(0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		pulse.tween_property(_today_glow, "modulate:a", 0.35, 0.85) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _start_endless_animations() -> void:
	if _endless_coin:
		var rot := create_tween().set_loops()
		rot.tween_property(_endless_coin, "rotation", TAU, 9.0) \
			.from(0.0).set_trans(Tween.TRANS_LINEAR)
		var bob := create_tween().set_loops()
		bob.tween_property(_endless_coin, "scale", Vector2.ONE * 1.08, 0.9) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		bob.tween_property(_endless_coin, "scale", Vector2.ONE, 0.9) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if _endless_day_lbl:
		var glow := create_tween().set_loops()
		glow.tween_property(_endless_day_lbl, "modulate",
			Color(1.0, 1.05, 0.85), 1.4) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		glow.tween_property(_endless_day_lbl, "modulate",
			Color(1.0, 1.0, 1.0), 1.4) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for i in _endless_sparkles.size():
		_twinkle(_endless_sparkles[i], i)

func _twinkle(s: Node2D, i: int) -> void:
	var d := 0.7 + (i % 3) * 0.25
	s.scale = Vector2.ONE * (0.6 + 0.4 * float(i) / 6.0)
	var tw := create_tween().set_loops()
	tw.tween_property(s, "scale", Vector2.ONE * 1.3, d) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(s, "scale", Vector2.ONE * 0.55, d) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var spin := create_tween().set_loops()
	spin.tween_property(s, "rotation", TAU, 6.0 + i) \
		.from(0.0).set_trans(Tween.TRANS_LINEAR)

# A radial coin/spark burst from a point in dialog space — the claim payoff.
func _burst_at(center: Vector2) -> void:
	var count := 16
	for i in count:
		var shard := Polygon2D.new()
		var r: float = 3.0 + randf() * 3.0
		if i % 2 == 0:
			shard.polygon = _circle_polygon(r, 10)
			shard.color = Color(1.0, 0.80, 0.25, 1.0)
		else:
			shard.polygon = PackedVector2Array([
				Vector2(0, -r * 1.6), Vector2(r * 0.5, 0), Vector2(0, r * 1.6), Vector2(-r * 0.5, 0)])
			shard.color = Color(1.0, 0.95, 0.6, 1.0)
		shard.position = center
		_dialog.add_child(shard)
		var ang: float = TAU * float(i) / count + randf() * 0.4
		var dist: float = 70.0 + randf() * 60.0
		var dest: Vector2 = center + Vector2(cos(ang), sin(ang)) * dist + Vector2(0, 30.0)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(shard, "position", dest, 0.55 + randf() * 0.2) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(shard, "rotation", randf_range(-TAU, TAU), 0.7)
		tw.tween_property(shard, "modulate:a", 0.0, 0.7).set_delay(0.15)
		tw.chain().tween_callback(shard.queue_free)

# ── claim ────────────────────────────────────────────────────────────────────

func _on_action() -> void:
	var reward := CoinsManager.claim_daily()
	if reward <= 0:
		return
	BadgeManager.note_daily_claimed(CoinsManager.streak_days)   # daily + streak badges
	# Celebrate: burst + pop on the just-claimed cell (or the endless medallion),
	# refresh the states, then auto-close so the coin registers on the wallet.
	if _is_endless and _endless_coin:
		_burst_at(_endless_coin.global_position - _dialog.global_position)
		var pop := create_tween()
		pop.tween_property(_endless_coin, "scale", Vector2.ONE * 1.35, 0.14) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		pop.tween_property(_endless_coin, "scale", Vector2.ONE, 0.26) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	elif not _today_cell.is_empty():
		var panel: Panel = _today_cell["panel"]
		var burst_c: Vector2 = _grid.position + panel.position + CELL * 0.5
		_burst_at(burst_c)
		panel.pivot_offset = panel.size * 0.5
		var pop := create_tween()
		pop.tween_property(panel, "scale", Vector2.ONE * 1.16, 0.12) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		pop.tween_property(panel, "scale", Vector2.ONE, 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_refresh_states()
	# Auto-dismiss after a beat so the player sees their reward register.
	get_tree().create_timer(0.95).timeout.connect(_close)

func _on_backdrop_click(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
		_close()
	elif ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed:
		_close()

func _close() -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_dialog, "scale", Vector2.ONE * 0.85, 0.15) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(_dialog, "modulate:a", 0.0, 0.15)
	tw.tween_property(_backdrop, "modulate:a", 0.0, 0.15)
	tw.chain().tween_callback(queue_free)

func _layout() -> void:
	var sz := get_viewport_rect().size
	if _backdrop:
		_backdrop.position = Vector2.ZERO
		_backdrop.size = sz
	if _dialog:
		_dialog.position = (sz - _dialog.size) * 0.5
		_dialog.pivot_offset = _dialog.size * 0.5
	if _streak_chip:
		_streak_chip.position = Vector2((DIALOG_W - _streak_chip.size.x) * 0.5, 76)

# ── profile-style polish helpers ─────────────────────────────────────────────

func _polish(sb: StyleBoxFlat) -> void:
	sb.anti_aliasing = true
	sb.anti_aliasing_size = 1.0
	sb.corner_detail = 12
	sb.border_blend = true

func _elevate(sb: StyleBoxFlat, strength := 0.34, size := 10, offset := 4.0) -> void:
	sb.shadow_color = Color(0.0, 0.0, 0.0, strength)
	sb.shadow_size = size
	sb.shadow_offset = Vector2(0, offset)

# A vertical gradient quad (per-vertex colours are the one way to get a true
# gradient out of Godot's immediate draw API).
func _vgrad(c: CanvasItem, r: Rect2, top: Color, bot: Color) -> void:
	var pts := PackedVector2Array([
		r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	c.draw_polygon(pts, PackedColorArray([top, top, bot, bot]))

# Overlay a panel with a top highlight sheen and a pooled bottom inner-shadow.
func _add_depth(panel: Control, sz: Vector2, corner: float, top_hi := 0.06, bot_sh := 0.20) -> void:
	var ov := Control.new()
	ov.position = Vector2.ZERO
	ov.size = sz
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inset := corner * 0.6
	ov.draw.connect(func() -> void:
		var hh := minf(sz.y * 0.5, 54.0)
		_vgrad(ov, Rect2(inset, 1.5, sz.x - 2.0 * inset, hh),
			Color(1, 1, 1, top_hi), Color(1, 1, 1, 0.0))
		var sh := minf(sz.y * 0.5, 46.0)
		_vgrad(ov, Rect2(inset, sz.y - sh - 1.5, sz.x - 2.0 * inset, sh),
			Color(0, 0, 0, 0.0), Color(0, 0, 0, bot_sh)))
	panel.add_child(ov)

# A hairline divider that fades to nothing at both ends.
func _soft_divider(width: float, col: Color) -> Control:
	var d := Control.new()
	d.custom_minimum_size = Vector2(width, 2)
	d.size = Vector2(width, 2)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.draw.connect(func() -> void:
		var mid := Color(col.r, col.g, col.b, 0.34)
		var edge := Color(col.r, col.g, col.b, 0.0)
		var h := width * 0.5
		d.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(h, 0), Vector2(h, 1), Vector2(0, 1)]),
			PackedColorArray([edge, mid, mid, edge]))
		d.draw_polygon(PackedVector2Array([Vector2(h, 0), Vector2(width, 0), Vector2(width, 1), Vector2(h, 1)]),
			PackedColorArray([mid, edge, edge, mid])))
	return d
