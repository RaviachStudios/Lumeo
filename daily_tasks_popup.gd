extends Control

# ─────────────────────────────────────────────────────────────────────────────
# Daily Tasks — a MODAL POPUP over the home screen, opened from the tasks pill in
# the top-left HUD. One scrolling column of task rows; each row carries the badge
# medallion, the goal, a progress bar, its coin reward and its own CLAIM button,
# with a CLAIM ALL button in the footer.
#
# Three row states, which the whole row expresses at once (medallion, border,
# bar, chip, button):
#   • LOCKED    — greyed, padlocked medallion, bar shows how far there is to go
#   • CLAIMABLE — accent border with a pulsing halo, lit medallion, gold CLAIM
#   • CLAIMED   — green, checked chip, the button reads "CLAIMED"
#
# Visual language follows the badge gallery / daily-claim dialogs: a glassy panel
# with a header band, drawn-in light (top sheen + pooled bottom shadow), soft
# ambient shadows and hairline dividers — all procedural, no PNGs, no scene.
# ─────────────────────────────────────────────────────────────────────────────

const GOLD := Color(1.0, 0.82, 0.30)
const GOLD_HI := Color(1.0, 0.93, 0.58)
const ACCENT := Color(0.52, 0.58, 1.0)      # structural accent (band line, dividers)
const GREEN := Color(0.44, 0.92, 0.56)      # claimed state
const TEAL := Color(0.30, 0.85, 0.84)       # the tasks identity colour (matches the HUD pill)

const PAD := 22.0
const CONTENT_TOP := 74.0
const ROW_H := 96.0
const ROW_GAP := 10.0
# Rows sit inset inside the scroll viewport so a lit row's coloured shadow has
# room to bloom without the ScrollContainer clipping it flat against its edge.
const ROW_INSET := 12.0
const FOOTER_H := 96.0
const ICON_D := 66.0
const TEXT_X := 98.0
const CHIP_W := 104.0
const BTN_W := 150.0
const BTN_H := 48.0

var _dw := 880.0
var _dh := 620.0

var _backdrop: ColorRect
var _dialog: Panel
var _done_lbl: Label
var _reset_lbl: Label
var _footer_btn: Button
var _rows: Array[Dictionary] = []     # per row: { task, wrap, panel, icon, title, desc,
									  #            prog, bar_fill, chip, chip_lbl,
									  #            chip_dot, btn, pulse }
var _row_w := 800.0
var _bar_w := 400.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP            # eats clicks behind
	# A client left open across UTC midnight must not paint yesterday's board.
	DailyTasks.refresh()
	var vp := get_viewport_rect().size
	_dw = clampf(vp.x - 150.0, 700.0, 900.0)
	_dh = clampf(vp.y - 56.0, 500.0, 640.0)
	# Scroll viewport width, less the scrollbar gutter and the two row insets.
	_row_w = _dw - PAD * 2.0 - 14.0 - ROW_INSET * 2.0
	_bar_w = maxf(160.0, _row_w - 400.0)

	_build_backdrop()
	_build_dialog()
	_build_rows()
	_build_footer()
	_refresh_all()

	DailyTasks.changed.connect(_refresh_all)
	get_viewport().size_changed.connect(_recenter)
	_recenter()

	# The reset countdown only needs a coarse tick — it is displayed to the minute.
	var clock := create_tween().set_loops()
	clock.tween_interval(20.0)
	clock.tween_callback(_update_reset_label)

	# Pop-in so the open feels intentional (same gesture as the other dialogs).
	_dialog.pivot_offset = _dialog.size * 0.5
	_dialog.scale = Vector2.ONE * 0.88
	_dialog.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_dialog, "scale", Vector2.ONE, 0.20) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_dialog, "modulate:a", 1.0, 0.18)
	tw.tween_property(_backdrop, "modulate:a", 1.0, 0.18).from(0.0)

# ─── shell ───────────────────────────────────────────────────────────────────

func _build_backdrop() -> void:
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.01, 0.02, 0.06, 0.66)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.gui_input.connect(_on_backdrop_click)
	# Faint ambient light pooled behind the dialog so the scrim isn't dead flat.
	_backdrop.draw.connect(func() -> void:
		var ctr := _backdrop.size * 0.5
		var rad := _backdrop.size.length() * 0.5
		for i in 6:
			var t := float(i) / 5.0
			_backdrop.draw_circle(ctr, rad * (0.32 + 0.5 * t),
				Color(TEAL.r, TEAL.g, TEAL.b, 0.018 * (1.0 - t))))
	add_child(_backdrop)

func _build_dialog() -> void:
	_dialog = Panel.new()
	_dialog.size = Vector2(_dw, _dh)
	_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	var ds := StyleBoxFlat.new()
	ds.bg_color = Color(0.045, 0.055, 0.155, 0.99)
	ds.set_corner_radius_all(26)
	ds.border_color = Color(TEAL.r, TEAL.g, TEAL.b, 0.55)
	ds.set_border_width_all(2)
	ds.shadow_color = Color(TEAL.r, TEAL.g, TEAL.b, 0.28)
	ds.shadow_size = 30
	_polish(ds)
	_dialog.add_theme_stylebox_override("panel", ds)
	add_child(_dialog)
	_add_depth(_dialog, _dialog.size, 26, 0.05, 0.22)

	# ── header band ──────────────────────────────────────────────────────────
	var band := Panel.new()
	band.position = Vector2(2, 2)
	band.size = Vector2(_dw - 4, 62)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.075, 0.105, 0.215, 0.94)
	bs.corner_radius_top_left = 24
	bs.corner_radius_top_right = 24
	_polish(bs)
	band.add_theme_stylebox_override("panel", bs)
	band.draw.connect(func() -> void:
		_vgrad(band, Rect2(2, 1.5, _dw - 8, 28),
			Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.0))
		_vgrad(band, Rect2(16, 59, _dw - 36, 3),
			Color(TEAL.r, TEAL.g, TEAL.b, 0.0), Color(TEAL.r, TEAL.g, TEAL.b, 0.34)))
	_dialog.add_child(band)

	var title := Label.new()
	title.text = "DAILY TASKS"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.86, 0.98, 1.0))
	title.add_theme_color_override("font_shadow_color", Color(TEAL.r, TEAL.g, TEAL.b, 0.55))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 2)
	title.add_theme_constant_override("shadow_outline_size", 6)
	title.position = Vector2(0, 13)
	title.size = Vector2(_dw, 38)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog.add_child(title)

	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.size = Vector2(40, 40)
	close.position = Vector2(_dw - 52, 12)
	close.add_theme_font_size_override("font_size", 24)
	close.add_theme_color_override("font_color", Color(0.78, 0.88, 1.0, 0.75))
	close.add_theme_color_override("font_hover_color", Color(1.0, 0.45, 0.45))
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(_close)
	_dialog.add_child(close)

	# ── sub-header: "N / 7 COMPLETE" on the left, the reset clock on the right ──
	_done_lbl = Label.new()
	_done_lbl.add_theme_font_size_override("font_size", 15)
	_done_lbl.add_theme_color_override("font_color", Color(0.62, 0.90, 0.92))
	_done_lbl.position = Vector2(PAD + 4, CONTENT_TOP - 2)
	_done_lbl.size = Vector2(260, 22)
	_done_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog.add_child(_done_lbl)

	_reset_lbl = Label.new()
	_reset_lbl.add_theme_font_size_override("font_size", 15)
	_reset_lbl.add_theme_color_override("font_color", Color(0.60, 0.64, 0.84))
	_reset_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_reset_lbl.position = Vector2(_dw - PAD - 264, CONTENT_TOP - 2)
	_reset_lbl.size = Vector2(260, 22)
	_reset_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog.add_child(_reset_lbl)
	_update_reset_label()

	var div := _soft_divider(_dw - PAD * 2.0, TEAL)
	div.position = Vector2(PAD, CONTENT_TOP + 22)
	_dialog.add_child(div)

# ─── rows ────────────────────────────────────────────────────────────────────

func _build_rows() -> void:
	var top := CONTENT_TOP + 32.0
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.position = Vector2(PAD, top)
	scroll.size = Vector2(_dw - PAD * 2.0, _dh - top - FOOTER_H)
	_dialog.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(_row_w + ROW_INSET * 2.0, 0)
	vbox.add_theme_constant_override("separation", int(ROW_GAP))
	scroll.add_child(vbox)

	# Snapshot the order once: finished tasks on top, the rest in catalog order.
	for t in DailyTasks.ordered_tasks():
		vbox.add_child(_make_row(t))

# One task row. Everything inside is MOUSE_FILTER_IGNORE except the claim button,
# so a touch drag anywhere on the row still reaches the ScrollContainer (a row of
# STOP controls is exactly what blocks list scrolling on Android).
func _make_row(t: Dictionary) -> Control:
	var accent: Color = t["accent"]
	# The wrapper is what the VBox lays out (and stretches to its own width); the
	# panel inside it is the row proper, inset so its lit shadow can bloom.
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(_row_w + ROW_INSET * 2.0, ROW_H)
	wrap.size = Vector2(_row_w + ROW_INSET * 2.0, ROW_H)
	wrap.mouse_filter = Control.MOUSE_FILTER_PASS

	var panel := Panel.new()
	panel.position = Vector2(ROW_INSET, 0)
	panel.size = Vector2(_row_w, ROW_H)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(panel)
	_add_depth(panel, panel.size, 18, 0.05, 0.18)

	# Medallion — the same procedural art the badge gallery uses, so a locked task
	# reads (padlock + slate silhouette) exactly like a locked badge.
	var id := String(t["id"])
	var art := String(t.get("art", "star"))
	var num := int(t.get("num", 0))
	var icon := Control.new()
	icon.position = Vector2(16, (ROW_H - ICON_D) * 0.5)
	icon.custom_minimum_size = Vector2(ICON_D, ICON_D)
	icon.size = Vector2(ICON_D, ICON_D)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.draw.connect(func() -> void:
		BadgeIcons.draw_badge(icon, icon.size, art, accent, DailyTasks.is_complete(id), num))
	panel.add_child(icon)

	var title := Label.new()
	title.text = String(t["name"])
	title.add_theme_font_size_override("font_size", 21)
	title.position = Vector2(TEXT_X, 11)
	title.size = Vector2(_bar_w, 27)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(title)

	var desc := Label.new()
	desc.text = String(t["desc"])
	desc.add_theme_font_size_override("font_size", 14)
	desc.position = Vector2(TEXT_X, 40)
	desc.size = Vector2(_bar_w - 96.0, 20)
	desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(desc)

	# Progress readout, right-aligned to the end of the bar below it.
	var prog := Label.new()
	prog.add_theme_font_size_override("font_size", 15)
	prog.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	prog.position = Vector2(TEXT_X + _bar_w - 96.0, 40)
	prog.size = Vector2(96, 20)
	prog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(prog)

	var bar_bg := Panel.new()
	bar_bg.position = Vector2(TEXT_X, 68)
	bar_bg.size = Vector2(_bar_w, 10)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bbs := StyleBoxFlat.new()
	bbs.bg_color = Color(0.02, 0.03, 0.09, 0.92)
	bbs.set_corner_radius_all(5)
	bbs.border_color = Color(1, 1, 1, 0.07)
	bbs.set_border_width_all(1)
	_polish(bbs)
	bar_bg.add_theme_stylebox_override("panel", bbs)
	panel.add_child(bar_bg)

	var bar_fill := Panel.new()
	bar_fill.position = Vector2.ZERO
	bar_fill.size = Vector2(0, 10)
	bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_bg.add_child(bar_fill)

	# Reward chip (coin + amount).
	var chip := Panel.new()
	chip.position = Vector2(_row_w - BTN_W - 18.0 - 14.0 - CHIP_W, (ROW_H - 40.0) * 0.5)
	chip.size = Vector2(CHIP_W, 40)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(chip)

	var chip_dot := Control.new()
	chip_dot.position = Vector2(10, 8)
	chip_dot.size = Vector2(24, 24)
	chip_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip_dot.draw.connect(func() -> void: _draw_coin(chip_dot, Vector2(12, 12), 11.0))
	chip.add_child(chip_dot)

	var chip_lbl := Label.new()
	chip_lbl.text = "+%d" % int(t["reward"])
	chip_lbl.add_theme_font_size_override("font_size", 19)
	chip_lbl.position = Vector2(38, 0)
	chip_lbl.size = Vector2(CHIP_W - 44.0, 40)
	chip_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(chip_lbl)

	# The one interactive control on the row. PASS, not the Button default STOP: a
	# STOP button eats the ScreenDrag, so a flick that starts on it (enabled or
	# greyed — it covers a sixth of the row) leaves the list stuck. With PASS the
	# tap still lands and the drag carries on up to the ScrollContainer, which
	# cancels the half-made press once the finger passes its drag deadzone.
	var btn := Button.new()
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	btn.size = Vector2(BTN_W, BTN_H)
	btn.position = Vector2(_row_w - BTN_W - 18.0, (ROW_H - BTN_H) * 0.5)
	btn.pivot_offset = Vector2(BTN_W, BTN_H) * 0.5
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 19)
	btn.pressed.connect(_on_claim.bind(id))
	panel.add_child(btn)

	var row := {
		"task": t, "panel": panel, "icon": icon, "title": title,
		"desc": desc, "prog": prog, "bar_fill": bar_fill, "chip": chip,
		"chip_lbl": chip_lbl, "chip_dot": chip_dot, "btn": btn, "wrap": wrap,
		"pulse": null,
	}
	_rows.append(row)
	return wrap

# ─── state painting ──────────────────────────────────────────────────────────

func _refresh_all() -> void:
	for r in _rows:
		_refresh_row(r)
	var done := DailyTasks.completed_count()
	var total := DailyTasks.total_count()
	_done_lbl.text = "%d / %d COMPLETE" % [done, total]
	_refresh_footer()

func _refresh_row(r: Dictionary) -> void:
	var t: Dictionary = r["task"]
	var id := String(t["id"])
	var accent: Color = t["accent"]
	var complete := DailyTasks.is_complete(id)
	var claimed := DailyTasks.is_claimed(id)
	var claimable := DailyTasks.can_claim(id)

	var panel: Panel = r["panel"]
	var st := StyleBoxFlat.new()
	st.set_corner_radius_all(18)
	_polish(st)
	if claimable:
		# A lit row: accent-tinted glass, a full-strength rim, and a coloured halo
		# instead of the neutral drop shadow the dormant rows wear.
		st.bg_color = Color(0.09, 0.11, 0.24, 0.97).lerp(Color(accent.r, accent.g, accent.b, 0.97), 0.12)
		st.border_color = Color(accent.r, accent.g, accent.b, 0.90)
		st.set_border_width_all(2)
		st.shadow_color = Color(accent.r, accent.g, accent.b, 0.42)
		st.shadow_size = 10
		st.shadow_offset = Vector2(0, 2)
	elif claimed:
		st.bg_color = Color(0.055, 0.13, 0.10, 0.94)
		st.border_color = Color(GREEN.r, GREEN.g, GREEN.b, 0.45)
		st.set_border_width_all(1)
		_elevate(st, 0.24, 6, 3.0)
	else:
		st.bg_color = Color(0.055, 0.068, 0.165, 0.92)
		st.border_color = Color(0.30, 0.35, 0.55, 0.38)
		st.set_border_width_all(1)
		_elevate(st, 0.26, 6, 3.0)
	panel.add_theme_stylebox_override("panel", st)
	(r["icon"] as Control).queue_redraw()

	var title: Label = r["title"]
	var desc: Label = r["desc"]
	if claimable:
		title.add_theme_color_override("font_color", Color.WHITE)
		desc.add_theme_color_override("font_color", Color(0.80, 0.85, 0.98, 0.92))
	elif claimed:
		title.add_theme_color_override("font_color", Color(0.78, 0.94, 0.84))
		desc.add_theme_color_override("font_color", Color(0.62, 0.82, 0.70, 0.85))
	else:
		title.add_theme_color_override("font_color", Color(0.74, 0.78, 0.90))
		desc.add_theme_color_override("font_color", Color(0.56, 0.60, 0.76))

	# Progress bar + readout. A finished task shows a full bar in its own accent
	# (green once claimed); an unfinished one shows the fraction it has reached.
	var prog: Label = r["prog"]
	prog.text = DailyTasks.progress_text(id)
	prog.add_theme_color_override("font_color",
		Color(GREEN.r, GREEN.g, GREEN.b, 0.9) if complete else Color(0.66, 0.71, 0.88))
	var fill: Panel = r["bar_fill"]
	var frac := DailyTasks.bar_fraction(id)
	# Any progress at all keeps a visible sliver, so "barely started" still reads
	# as started rather than as nothing.
	fill.size = Vector2(maxf(_bar_w * frac, 6.0) if frac > 0.0 else 0.0, 10)
	var fc := GREEN if claimed else (accent if complete else accent.darkened(0.18))
	var fs := StyleBoxFlat.new()
	fs.bg_color = fc
	fs.set_corner_radius_all(5)
	fs.shadow_color = Color(fc.r, fc.g, fc.b, 0.45 if complete else 0.22)
	fs.shadow_size = 6
	_polish(fs)
	fill.add_theme_stylebox_override("panel", fs)
	fill.visible = frac > 0.0

	# Reward chip.
	var chip: Panel = r["chip"]
	var chip_lbl: Label = r["chip_lbl"]
	var cs := StyleBoxFlat.new()
	cs.set_corner_radius_all(20)
	cs.set_border_width_all(1)
	_polish(cs)
	if claimed:
		cs.bg_color = Color(0.06, 0.16, 0.11, 0.92)
		cs.border_color = Color(GREEN.r, GREEN.g, GREEN.b, 0.55)
		chip_lbl.add_theme_color_override("font_color", Color(0.74, 0.94, 0.82))
	elif complete:
		cs.bg_color = Color(0.20, 0.15, 0.04, 0.95)
		cs.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.75)
		chip_lbl.add_theme_color_override("font_color", GOLD_HI)
	else:
		cs.bg_color = Color(0.035, 0.045, 0.12, 0.90)
		cs.border_color = Color(0.36, 0.40, 0.58, 0.42)
		chip_lbl.add_theme_color_override("font_color", Color(0.72, 0.76, 0.90, 0.75))
	chip.add_theme_stylebox_override("panel", cs)
	(r["chip_dot"] as Control).modulate = Color(1, 1, 1, 1.0 if complete else 0.45)

	# Action button: the live CLAIM, or a muted state pill telling the player what
	# is still missing / that it is already in the bank.
	var btn: Button = r["btn"]
	# Only a live CLAIM breathes; the muted states sit still.
	var pulse: Tween = r["pulse"]
	if pulse != null and pulse.is_valid():
		pulse.kill()
	r["pulse"] = null
	btn.scale = Vector2.ONE
	if claimable:
		btn.disabled = false
		btn.text = "CLAIM"
		_style_gold_button(btn)
		var tw := create_tween().set_loops()
		tw.tween_property(btn, "scale", Vector2.ONE * 1.045, 0.62) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(btn, "scale", Vector2.ONE, 0.62) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		r["pulse"] = tw
	elif claimed:
		btn.disabled = true
		btn.text = "CLAIMED ✓"
		_style_flat_button(btn, Color(0.07, 0.17, 0.12, 0.85),
			Color(GREEN.r, GREEN.g, GREEN.b, 0.45), Color(0.70, 0.93, 0.78))
	else:
		btn.disabled = true
		btn.text = DailyTasks.action_text(id)
		_style_flat_button(btn, Color(0.04, 0.05, 0.13, 0.85),
			Color(0.34, 0.38, 0.56, 0.40), Color(0.66, 0.70, 0.86, 0.85))

func _refresh_footer() -> void:
	var pending := DailyTasks.claimable_count()
	if pending > 0:
		_footer_btn.disabled = false
		_footer_btn.text = "CLAIM ALL   +%d" % DailyTasks.claimable_total()
		_style_gold_button(_footer_btn)
	elif DailyTasks.all_claimed():
		_footer_btn.disabled = true
		_footer_btn.text = "ALL CLAIMED ✓"
		_style_flat_button(_footer_btn, Color(0.06, 0.16, 0.11, 0.85),
			Color(GREEN.r, GREEN.g, GREEN.b, 0.45), Color(0.72, 0.94, 0.80))
	else:
		_footer_btn.disabled = true
		_footer_btn.text = "KEEP PLAYING"
		_style_flat_button(_footer_btn, Color(0.04, 0.05, 0.13, 0.85),
			Color(0.34, 0.38, 0.56, 0.40), Color(0.66, 0.70, 0.86, 0.85))

func _update_reset_label() -> void:
	if not is_instance_valid(_reset_lbl):
		return
	var s := DailyTasks.seconds_until_reset()
	var h := s / 3600
	var m := (s % 3600) / 60
	_reset_lbl.text = ("RESETS IN %dh %02dm" % [h, m]) if h > 0 \
		else ("RESETS IN %dm" % maxi(1, m))

# ─── footer ──────────────────────────────────────────────────────────────────

func _build_footer() -> void:
	var div := _soft_divider(_dw - PAD * 2.0, ACCENT)
	div.position = Vector2(PAD, _dh - FOOTER_H + 8.0)
	_dialog.add_child(div)

	_footer_btn = Button.new()
	_footer_btn.size = Vector2(360, 60)
	_footer_btn.position = Vector2((_dw - 360.0) * 0.5, _dh - FOOTER_H + 24.0)
	_footer_btn.focus_mode = Control.FOCUS_NONE
	_footer_btn.add_theme_font_size_override("font_size", 22)
	_footer_btn.pressed.connect(_on_claim_all)
	_dialog.add_child(_footer_btn)

# ─── claiming ────────────────────────────────────────────────────────────────

func _on_claim(id: String) -> void:
	var row := _row_for(id)
	if DailyTasks.claim(id) <= 0:
		return
	AudioManager.play_replay_sound()      # short two-note lift; the fanfare is for Claim All
	if not row.is_empty():
		_celebrate(row)
	_refresh_all()

func _on_claim_all() -> void:
	# Snapshot the claimable rows first — claiming flips them out of that state.
	var winners: Array[Dictionary] = []
	for r in _rows:
		if DailyTasks.can_claim(String((r["task"] as Dictionary)["id"])):
			winners.append(r)
	if DailyTasks.claim_all() <= 0:
		return
	AudioManager.play_win_sound()
	for i in winners.size():
		# Stagger the bursts so a full sweep reads as a cascade, not one flash.
		var r: Dictionary = winners[i]
		var timer := get_tree().create_timer(i * 0.11)
		timer.timeout.connect(func() -> void:
			if is_instance_valid(r["panel"] as Node):
				_celebrate(r))
	_refresh_all()

# Pop the row and throw a coin burst from its medallion.
func _celebrate(r: Dictionary) -> void:
	var panel: Panel = r["panel"]
	if not is_instance_valid(panel):
		return
	panel.pivot_offset = panel.size * 0.5
	var pop := create_tween()
	pop.tween_property(panel, "scale", Vector2(1.03, 1.10), 0.12) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	pop.tween_property(panel, "scale", Vector2.ONE, 0.24) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var icon: Control = r["icon"]
	_burst_at(icon.global_position - _dialog.global_position + icon.size * 0.5)

# A radial coin/spark burst from a point in dialog space — the claim payoff.
func _burst_at(center: Vector2) -> void:
	var count := 14
	for i in count:
		var shard := Polygon2D.new()
		var rr: float = 3.0 + randf() * 3.0
		if i % 2 == 0:
			shard.polygon = _circle_polygon(rr, 10)
			shard.color = Color(1.0, 0.80, 0.25, 1.0)
		else:
			shard.polygon = PackedVector2Array([
				Vector2(0, -rr * 1.6), Vector2(rr * 0.5, 0), Vector2(0, rr * 1.6), Vector2(-rr * 0.5, 0)])
			shard.color = Color(1.0, 0.95, 0.6, 1.0)
		shard.position = center
		_dialog.add_child(shard)
		var ang: float = TAU * float(i) / count + randf() * 0.4
		var dist: float = 54.0 + randf() * 48.0
		var dest: Vector2 = center + Vector2(cos(ang), sin(ang)) * dist + Vector2(0, 24.0)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(shard, "position", dest, 0.5 + randf() * 0.2) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(shard, "rotation", randf_range(-TAU, TAU), 0.65)
		tw.tween_property(shard, "modulate:a", 0.0, 0.65).set_delay(0.12)
		tw.chain().tween_callback(shard.queue_free)

func _row_for(id: String) -> Dictionary:
	for r in _rows:
		if String((r["task"] as Dictionary)["id"]) == id:
			return r
	return {}

# ─── button styling ──────────────────────────────────────────────────────────

# Gold gradient-lit action button, matching the daily-claim dialog's CLAIM.
func _style_gold_button(btn: Button) -> void:
	var base := Color(1.00, 0.66, 0.10)
	var fg := Color(0.20, 0.11, 0.0)
	var s := StyleBoxFlat.new()
	s.bg_color = base
	s.set_corner_radius_all(16)
	s.border_color = GOLD_HI
	s.set_border_width_all(1)
	_polish(s)
	s.shadow_color = Color(base.r, base.g, base.b, 0.45)
	s.shadow_size = 14
	s.shadow_offset = Vector2(0, 3)
	btn.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = base.lightened(0.14)
	btn.add_theme_stylebox_override("hover", sh)
	var sp := s.duplicate() as StyleBoxFlat
	sp.bg_color = base.darkened(0.18)
	sp.shadow_size = 6
	btn.add_theme_stylebox_override("pressed", sp)
	btn.add_theme_color_override("font_color", fg)
	btn.add_theme_color_override("font_hover_color", fg)
	btn.add_theme_color_override("font_pressed_color", fg)
	_sheen(btn)

# Muted pill used for the "not yet" / "already claimed" states. Styled on every
# slot (normal + disabled) so the look doesn't depend on the disabled flag.
func _style_flat_button(btn: Button, bg: Color, border: Color, fg: Color) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(16)
	s.border_color = border
	s.set_border_width_all(1)
	_polish(s)
	for slot in ["normal", "hover", "pressed", "disabled"]:
		btn.add_theme_stylebox_override(slot, s)
	btn.add_theme_color_override("font_color", fg)
	btn.add_theme_color_override("font_hover_color", fg)
	btn.add_theme_color_override("font_disabled_color", fg)

# One-time top sheen across a button's face (skipped if it already has one).
func _sheen(btn: Button) -> void:
	if btn.has_meta("sheened"):
		return
	btn.set_meta("sheened", true)
	var ov := Control.new()
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.draw.connect(func() -> void:
		_vgrad(ov, Rect2(10, 3, btn.size.x - 20, btn.size.y * 0.5),
			Color(1, 1, 1, 0.20), Color(1, 1, 1, 0.0)))
	btn.add_child(ov)

# ─── procedural art ──────────────────────────────────────────────────────────

# A minted coin disc with a rim and a specular highlight (the chip's leading dot).
func _draw_coin(c: CanvasItem, ctr: Vector2, r: float) -> void:
	c.draw_circle(ctr + Vector2(0, 1.5), r, Color(0.0, 0.0, 0.0, 0.28))
	c.draw_circle(ctr, r, Color(0.72, 0.52, 0.10))
	c.draw_circle(ctr, r * 0.91, Color(0.95, 0.78, 0.20))
	c.draw_circle(ctr, r * 0.73, Color(1.0, 0.88, 0.36))
	c.draw_circle(ctr + Vector2(-r * 0.24, -r * 0.26), r * 0.27, Color(1.0, 0.96, 0.72, 0.7))

func _circle_polygon(r: float, n: int) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in n:
		var a: float = TAU * float(i) / n
		p.append(Vector2(cos(a), sin(a)) * r)
	return p

# ─── close / layout ──────────────────────────────────────────────────────────

func _on_backdrop_click(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
		_close()
	elif ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed:
		_close()

func _close() -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_dialog, "scale", Vector2.ONE * 0.88, 0.15) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(_dialog, "modulate:a", 0.0, 0.15)
	tw.tween_property(_backdrop, "modulate:a", 0.0, 0.15)
	tw.chain().tween_callback(queue_free)

func _recenter() -> void:
	var sz := get_viewport_rect().size
	if _backdrop:
		_backdrop.position = Vector2.ZERO
		_backdrop.size = sz
	if _dialog:
		_dialog.position = (sz - _dialog.size) * 0.5
		_dialog.pivot_offset = _dialog.size * 0.5

# ─── premium-polish helpers (shared vocabulary with the other dialogs) ───────

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
