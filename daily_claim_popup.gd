extends Control

# Modal popup for the daily-claim streak. Days 1-14 are shown as a 2x7 grid
# (the cell matching `next_claim_day()` is highlighted, earlier days marked
# claimed). On day 15+ the grid is replaced by a single big "endless streak"
# celebration card — one giant day-number, a glowing coin medallion, and a
# +100 reward — because there is no useful ladder past the cap.
# Either way, the bottom action button claims today's reward via CoinsManager
# and the popup self-closes after a brief flash.
#
# This screen overlays the home screen (added as a child of HomeScreen). It
# is fully self-built — no exported scene, no PNGs.

const ROWS := 2
const COLS := 7
const CELL := Vector2(80, 100)
const CELL_GAP := 10.0
const DIALOG_W := 740.0
const DIALOG_H := 480.0
# Day at which the grid is replaced by the endless-streak view. Must match
# CoinsManager's reward curve breakpoint (day 14 = last grid cell, 15+ flat).
const ENDLESS_DAY := 15

var _backdrop: ColorRect
var _dialog: Panel
var _action_btn: Button
var _cells: Array[Dictionary] = []   # per cell: { panel, day, reward_lbl }
var _is_endless := false
# Endless-view widgets we animate on _ready, kept as members so we can drive
# the looping sparkle / coin-bob tweens without re-querying the tree.
var _endless_day_lbl: Label = null
var _endless_coin: Node2D = null
var _endless_sparkles: Array[Node2D] = []

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP            # eats clicks behind
	_is_endless = CoinsManager.next_claim_day() >= ENDLESS_DAY
	_build()
	_layout()
	get_viewport().size_changed.connect(_layout)
	if _is_endless:
		_start_endless_animations()
	# Pop-in tween on the dialog so the open feels intentional.
	_dialog.pivot_offset = _dialog.size * 0.5
	_dialog.scale = Vector2.ONE * 0.85
	_dialog.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_dialog, "scale", Vector2.ONE, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_dialog, "modulate:a", 1.0, 0.18)
	tw.tween_property(_backdrop, "modulate:a", 1.0, 0.18).from(0.0)

func _build() -> void:
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0, 0, 0, 0.6)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.gui_input.connect(_on_backdrop_click)
	add_child(_backdrop)

	_dialog = Panel.new()
	_dialog.size = Vector2(DIALOG_W, DIALOG_H)
	_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	var ds := StyleBoxFlat.new()
	ds.bg_color = Color(0.04, 0.06, 0.18, 0.98)
	ds.set_corner_radius_all(22)
	ds.border_color = Color(1.0, 0.78, 0.22, 0.85)
	ds.set_border_width_all(2)
	ds.shadow_color = Color(1.0, 0.78, 0.22, 0.35)
	ds.shadow_size = 22
	_dialog.add_theme_stylebox_override("panel", ds)
	add_child(_dialog)

	var title := Label.new()
	title.text = "DAILY REWARD"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45))
	title.add_theme_color_override("font_shadow_color", Color(0.6, 0.40, 0.0, 0.6))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 3)
	title.add_theme_constant_override("shadow_outline_size", 7)
	title.position = Vector2(0, 18)
	title.size = Vector2(DIALOG_W, 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dialog.add_child(title)

	var sub := Label.new()
	sub.text = "Sign in each day to grow your streak" if not _is_endless \
		else "Your streak is unstoppable"
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", Color(0.78, 0.82, 1.0, 0.85))
	sub.position = Vector2(0, 64)
	sub.size = Vector2(DIALOG_W, 24)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dialog.add_child(sub)

	if _is_endless:
		_build_endless_card()
	else:
		# Grid of 14 day cells: row 1 is days 1–7, row 2 is days 8–14.
		var grid := GridContainer.new()
		grid.columns = COLS
		grid.add_theme_constant_override("h_separation", int(CELL_GAP))
		grid.add_theme_constant_override("v_separation", int(CELL_GAP))
		var grid_w := COLS * CELL.x + (COLS - 1) * CELL_GAP
		var grid_h := ROWS * CELL.y + (ROWS - 1) * CELL_GAP
		grid.position = Vector2((DIALOG_W - grid_w) * 0.5, 110)
		grid.size = Vector2(grid_w, grid_h)
		_dialog.add_child(grid)
		for day in range(1, COLS * ROWS + 1):
			_cells.append(_make_cell(day, grid))

	_action_btn = Button.new()
	_action_btn.size = Vector2(280, 64)
	_action_btn.position = Vector2((DIALOG_W - 280) * 0.5, DIALOG_H - 64 - 28)
	_action_btn.focus_mode = Control.FOCUS_NONE
	_action_btn.add_theme_font_size_override("font_size", 24)
	_action_btn.pressed.connect(_on_action)
	_dialog.add_child(_action_btn)

	# Light "Close" hint in the corner.
	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.size = Vector2(36, 36)
	close.position = Vector2(DIALOG_W - 44, 12)
	close.add_theme_font_size_override("font_size", 22)
	close.add_theme_color_override("font_color", Color(0.8, 0.82, 1.0, 0.7))
	close.add_theme_color_override("font_hover_color", Color(1.0, 0.45, 0.45))
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(_close)
	_dialog.add_child(close)

	_refresh_states()

# ---------------- endless-streak view (day 15+) ----------------

# Single big celebratory card replacing the 14-day grid. Centers a huge
# "DAY N" label, a gold coin medallion with the flat +N reward beside it,
# and an "ENDLESS STREAK" badge — flanked by twinkling sparkles. The action
# button at the bottom is shared with the grid path.
func _build_endless_card() -> void:
	var day := CoinsManager.next_claim_day()
	var reward := CoinsManager.daily_reward_for_day(day)
	var area_top := 96.0

	# Ambient sparkles around the central content. Positions chosen to flank
	# the big number / medallion without crowding them — a simple celebration.
	# Action button starts at y=388 (DIALOG_H - 64 - 28); keep sparkles above it.
	var sparkle_positions := [
		Vector2(96, 132),  Vector2(644, 138),
		Vector2(118, 250), Vector2(622, 254),
		Vector2(196, 354), Vector2(544, 354),
	]
	for p in sparkle_positions:
		var s := _make_sparkle(8.0)
		s.position = p
		_dialog.add_child(s)
		_endless_sparkles.append(s)

	# The giant day number — the focal point.
	_endless_day_lbl = Label.new()
	_endless_day_lbl.text = "DAY %d" % day
	_endless_day_lbl.add_theme_font_size_override("font_size", 92)
	_endless_day_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45))
	# Outline gives the digits a touch more weight; glow comes from shadow_outline_size.
	_endless_day_lbl.add_theme_color_override("font_outline_color", Color(1.0, 0.92, 0.45))
	_endless_day_lbl.add_theme_constant_override("outline_size", 2)
	_endless_day_lbl.add_theme_color_override("font_shadow_color", Color(1.0, 0.55, 0.10, 0.7))
	_endless_day_lbl.add_theme_constant_override("shadow_offset_x", 0)
	_endless_day_lbl.add_theme_constant_override("shadow_offset_y", 0)
	_endless_day_lbl.add_theme_constant_override("shadow_outline_size", 22)
	_endless_day_lbl.position = Vector2(0, area_top + 4)
	_endless_day_lbl.size = Vector2(DIALOG_W, 110)
	_endless_day_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_endless_day_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_endless_day_lbl.pivot_offset = Vector2(DIALOG_W * 0.5, 55)
	_dialog.add_child(_endless_day_lbl)

	# Coin medallion + reward, horizontally grouped & centered.
	var coin_d := 64.0
	var row := Control.new()
	var row_w := 280.0
	row.size = Vector2(row_w, 80)
	row.position = Vector2((DIALOG_W - row_w) * 0.5, area_top + 130)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog.add_child(row)

	_endless_coin = _make_coin_medallion(coin_d)
	# Node2D position is its center — sit it at the row's vertical midline.
	_endless_coin.position = Vector2(40, 40)
	row.add_child(_endless_coin)

	var reward_lbl := Label.new()
	reward_lbl.text = "+%d" % reward
	reward_lbl.add_theme_font_size_override("font_size", 56)
	reward_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45))
	reward_lbl.add_theme_color_override("font_shadow_color", Color(0.6, 0.40, 0.0, 0.7))
	reward_lbl.add_theme_constant_override("shadow_offset_x", 0)
	reward_lbl.add_theme_constant_override("shadow_offset_y", 3)
	reward_lbl.add_theme_constant_override("shadow_outline_size", 9)
	reward_lbl.position = Vector2(90, 0)
	reward_lbl.size = Vector2(row_w - 90, 80)
	reward_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	reward_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	reward_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(reward_lbl)

	# Badge subtitle.
	var badge := Label.new()
	badge.text = "✦  ENDLESS  STREAK  ✦"
	badge.add_theme_font_size_override("font_size", 20)
	badge.add_theme_color_override("font_color", Color(0.85, 0.78, 1.0))
	badge.add_theme_color_override("font_shadow_color", Color(0.55, 0.45, 1.0, 0.55))
	badge.add_theme_constant_override("shadow_offset_x", 0)
	badge.add_theme_constant_override("shadow_offset_y", 0)
	badge.add_theme_constant_override("shadow_outline_size", 8)
	badge.position = Vector2(0, area_top + 220)
	badge.size = Vector2(DIALOG_W, 24)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dialog.add_child(badge)

# Gold coin disc + ring + "$" glyph, drawn as Polygon2D + Label so it can
# rotate / scale as a single Node2D. Same look as shop_screen's medallion.
func _make_coin_medallion(d: float) -> Node2D:
	var n := Node2D.new()
	var rim := Polygon2D.new()
	rim.polygon = _circle_polygon(d * 0.5 + 4.0, 32)
	rim.color = Color(1.0, 0.92, 0.55, 0.95)
	n.add_child(rim)
	var disc := Polygon2D.new()
	disc.polygon = _circle_polygon(d * 0.5, 32)
	disc.color = Color(1.0, 0.78, 0.20)
	n.add_child(disc)
	var glyph := Label.new()
	glyph.text = "$"
	glyph.add_theme_font_size_override("font_size", int(d * 0.7))
	glyph.add_theme_color_override("font_color", Color(0.45, 0.30, 0.05))
	glyph.position = Vector2(-d * 0.5, -d * 0.5)
	glyph.size = Vector2(d, d)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.add_child(glyph)
	return n

# Four-pointed star shape. Centered on its position; scale tweens look great.
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

# Looping idle animations — only used in endless mode. The medallion rotates
# slowly and bobs in scale; sparkles twinkle independently of each other.
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
		var s := _endless_sparkles[i]
		var d := 0.7 + (i % 3) * 0.25
		var tw := create_tween().set_loops()
		# Stagger phase by setting the starting value so they don't twinkle in lockstep.
		s.scale = Vector2.ONE * (0.6 + 0.4 * float(i) / maxi(1, _endless_sparkles.size()))
		tw.tween_property(s, "scale", Vector2.ONE * 1.3, d) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(s, "scale", Vector2.ONE * 0.55, d) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		var spin := create_tween().set_loops()
		spin.tween_property(s, "rotation", TAU, 6.0 + i) \
			.from(0.0).set_trans(Tween.TRANS_LINEAR)

func _make_cell(day: int, parent: Node) -> Dictionary:
	var cell := Panel.new()
	cell.custom_minimum_size = CELL
	cell.size = CELL
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(cell)

	var day_lbl := Label.new()
	day_lbl.text = "DAY %d" % day
	day_lbl.add_theme_font_size_override("font_size", 12)
	day_lbl.position = Vector2(0, 10)
	day_lbl.size = Vector2(CELL.x, 18)
	day_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cell.add_child(day_lbl)

	# Small coin glyph centered as a visual anchor.
	var disc := Panel.new()
	var d := 28.0
	disc.size = Vector2(d, d)
	disc.position = Vector2((CELL.x - d) * 0.5, 32)
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ds := StyleBoxFlat.new()
	ds.bg_color = Color(1.0, 0.78, 0.16)
	ds.set_corner_radius_all(int(d * 0.5))
	ds.border_color = Color(1.0, 0.92, 0.55)
	ds.set_border_width_all(2)
	disc.add_theme_stylebox_override("panel", ds)
	cell.add_child(disc)
	var glyph := Label.new()
	glyph.text = "$"
	glyph.add_theme_font_size_override("font_size", 18)
	glyph.add_theme_color_override("font_color", Color(0.45, 0.30, 0.05))
	glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	disc.add_child(glyph)

	var reward_lbl := Label.new()
	reward_lbl.text = "+%d" % CoinsManager.daily_reward_for_day(day)
	reward_lbl.add_theme_font_size_override("font_size", 18)
	reward_lbl.add_theme_color_override("font_color", Color.WHITE)
	reward_lbl.position = Vector2(0, CELL.y - 26)
	reward_lbl.size = Vector2(CELL.x, 22)
	reward_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cell.add_child(reward_lbl)

	return {"panel": cell, "day": day, "day_lbl": day_lbl, "reward_lbl": reward_lbl}

# Style each cell based on whether the player has already claimed it, is about
# to claim it (highlight), or it's still in the future (faded). Also updates
# the bottom action button. In endless mode the cells array is empty (no grid
# was built), so the loop is a no-op and only the action button is updated.
func _refresh_states() -> void:
	var next_day := CoinsManager.next_claim_day()
	var can_claim := CoinsManager.can_claim_today()
	for c in _cells:
		var day: int = c["day"]
		var panel: Panel = c["panel"]
		var st := StyleBoxFlat.new()
		st.set_corner_radius_all(12)
		if day == next_day and not can_claim:
			# Today's reward already collected — keep this cell highlighted so
			# the player can still see which day they last claimed when reopening
			# the popup, instead of it blending in with future / faded cells.
			st.bg_color = Color(0.10, 0.22, 0.14, 0.95)
			st.border_color = Color(0.50, 1.0, 0.60, 0.95)
			st.set_border_width_all(2)
			st.shadow_color = Color(0.50, 1.0, 0.60, 0.45)
			st.shadow_size = 12
		elif day < next_day:
			# Already part of this streak — visited.
			st.bg_color = Color(0.10, 0.20, 0.12, 0.85)
			st.border_color = Color(0.30, 0.85, 0.40, 0.55)
			st.set_border_width_all(1)
		elif day == next_day and can_claim:
			# Today's reward — highlighted with gold rim + glow.
			st.bg_color = Color(0.18, 0.16, 0.08, 0.95)
			st.border_color = Color(1.0, 0.85, 0.30, 1.0)
			st.set_border_width_all(2)
			st.shadow_color = Color(1.0, 0.85, 0.30, 0.55)
			st.shadow_size = 12
		else:
			# Future days — faded.
			st.bg_color = Color(0.06, 0.08, 0.18, 0.85)
			st.border_color = Color(0.30, 0.35, 0.55, 0.45)
			st.set_border_width_all(1)
		panel.add_theme_stylebox_override("panel", st)

	# Action button reflects claim state.
	if can_claim:
		_action_btn.text = "CLAIM   +%d" % CoinsManager.daily_reward_for_day(next_day)
		_set_action_style(_action_btn, Color(1.00, 0.66, 0.10), Color(0.18, 0.10, 0.0))
		_action_btn.disabled = false
	else:
		_action_btn.text = "COME BACK TOMORROW"
		_set_action_style(_action_btn, Color(0.30, 0.30, 0.40), Color(0.85, 0.85, 0.95, 0.7))
		_action_btn.disabled = true

func _set_action_style(btn: Button, bg: Color, fg: Color) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(16)
	btn.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = bg.lightened(0.15)
	btn.add_theme_stylebox_override("hover", sh)
	var sp := s.duplicate() as StyleBoxFlat
	sp.bg_color = bg.darkened(0.2)
	btn.add_theme_stylebox_override("pressed", sp)
	var sd := s.duplicate() as StyleBoxFlat
	sd.bg_color = bg.darkened(0.05)
	btn.add_theme_stylebox_override("disabled", sd)
	btn.add_theme_color_override("font_color", fg)
	btn.add_theme_color_override("font_disabled_color", fg)

func _on_action() -> void:
	var reward := CoinsManager.claim_daily()
	if reward <= 0:
		return
	# Briefly flash the just-claimed cell (or the endless medallion when the
	# grid isn't shown), then auto-close so the player sees the coin register.
	_refresh_states()
	if _is_endless and _endless_coin:
		var pop := create_tween()
		pop.tween_property(_endless_coin, "scale", Vector2.ONE * 1.30, 0.14) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		pop.tween_property(_endless_coin, "scale", Vector2.ONE, 0.24) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	elif CoinsManager.streak_days >= 1 and CoinsManager.streak_days <= _cells.size():
		var c: Dictionary = _cells[CoinsManager.streak_days - 1]
		var panel: Panel = c["panel"]
		panel.pivot_offset = panel.size * 0.5
		var pop := create_tween()
		pop.tween_property(panel, "scale", Vector2.ONE * 1.15, 0.12) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		pop.tween_property(panel, "scale", Vector2.ONE, 0.20) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Auto-dismiss after a beat so the player sees their reward register.
	get_tree().create_timer(0.75).timeout.connect(_close)

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
