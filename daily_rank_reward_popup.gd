extends Control

# ─────────────────────────────────────────────────────────────────────────────
# Yesterday's Rankings — the modal shown on login when the previous day's
# daily-leaderboard standing reward is surfaced (see
# CoinsManager.consume_pending_daily_rewards).
#
# The coins are ALREADY banked server-side (the midnight Cloud Function credited
# them) by the time this opens, so this popup is purely the celebratory receipt
# and its button just closes. It is the one moment the game gets to tell a player
# they placed, so it is built as a small award ceremony rather than a list:
#
#   • a hero medallion struck for the BEST placement of the day, lit by a slow
#     ray fan and ringed with sparkles
#   • one placement card per result — rank medal, difficulty, standing caption,
#     and the coins it earned — dealt in with a staggered slide
#   • a gold total strip with a shine that sweeps across once it lands
#
# Self-built (no scene, no PNGs), overlaid on the home screen, following the
# modal conventions and chrome of profile_screen.gd / coins_purchase_popup.gd.
#
# Inputs (set by the caller before add_child):
#   total   : int    summed coins granted
#   results : Array  of { diff: String, rank: int, reward: int }
# ─────────────────────────────────────────────────────────────────────────────

var total: int = 0
var results: Array = []

const GOLD := Color(1.00, 0.82, 0.28)
const GOLD_DEEP := Color(0.62, 0.36, 0.02)
const SILVER := Color(0.80, 0.86, 0.98)
const BRONZE := Color(0.90, 0.58, 0.30)
const COOL := Color(0.52, 0.62, 1.00)

const DIALOG_W := 660.0
const PAD := 24.0
const HEADER_H := 62.0
const HERO_H := 150.0
const ROW_H := 74.0
const ROW_GAP := 10.0
const TOTAL_H := 72.0
const BTN_H := 62.0

# Difficulty accents match the profile popup's, so a player reads the same colour
# for "hard" everywhere in the game.
const _DIFF := {
	"easy":     {"title": "EASY",     "accent": Color(0.28, 0.82, 0.45)},
	"moderate": {"title": "MODERATE", "accent": Color(1.00, 0.72, 0.25)},
	"hard":     {"title": "HARD",     "accent": Color(0.95, 0.32, 0.40)},
}
# Rank order used when several days are merged into one receipt.
const _DIFF_ORDER := ["easy", "moderate", "hard"]

var _backdrop: ColorRect
var _dialog: Panel
var _rows: Array[Control] = []      # placement cards, for the staggered entrance
var _total_strip: Panel
var _shine: Control
# The rows actually drawn: either `results` verbatim, or one aggregated row per
# difficulty when the player has been away long enough to stack up receipts.
var _shown: Array = []
var _grouped := false
var _days := 0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_prepare_rows()
	_build()
	_layout()
	get_viewport().size_changed.connect(_layout)
	_animate_in()

# ─── data shaping ────────────────────────────────────────────────────────────

# Normally this is one day's worth: at most three rows, one per difficulty. But
# the receipt merges every day the player was away, so a week offline can arrive
# as fifteen entries — more than the dialog could ever show without running off
# a 720-tall screen. Past a threshold we collapse to one row per difficulty
# carrying that difficulty's BEST rank and its SUMMED coins, which keeps the
# dialog a fixed size and still tells the player the two things that matter.
func _prepare_rows() -> void:
	var clean: Array = []
	for r in results:
		if r is Dictionary and int((r as Dictionary).get("reward", 0)) > 0:
			clean.append(r)
	if clean.size() <= 3:
		_shown = clean
		return
	var best: Dictionary = {}          # diff -> {diff, rank, reward, count}
	for r in clean:
		var diff := String((r as Dictionary).get("diff", ""))
		var rank := int((r as Dictionary).get("rank", 0))
		var reward := int((r as Dictionary).get("reward", 0))
		var cur: Dictionary = best.get(diff, {"diff": diff, "rank": rank, "reward": 0, "count": 0})
		cur["reward"] = int(cur["reward"]) + reward
		cur["count"] = int(cur["count"]) + 1
		if rank > 0 and (int(cur["rank"]) <= 0 or rank < int(cur["rank"])):
			cur["rank"] = rank
		best[diff] = cur
	_grouped = true
	for key in _DIFF_ORDER:
		if best.has(key):
			_shown.append(best[key])
			_days = maxi(_days, int((best[key] as Dictionary)["count"]))
	for key in best.keys():                                  # any unknown difficulty id
		if not _DIFF_ORDER.has(key):
			_shown.append(best[key])

func _dialog_h() -> float:
	var rows := maxi(1, _shown.size())
	var rows_h := rows * ROW_H + (rows - 1) * ROW_GAP
	return HEADER_H + HERO_H + 30.0 + rows_h + 16.0 + TOTAL_H + 18.0 + BTN_H + PAD

# The best (numerically lowest) placement of the receipt — what the hero medal
# is struck for.
func _best_rank() -> int:
	var best := 0
	for r in _shown:
		var rank := int((r as Dictionary).get("rank", 0))
		if rank > 0 and (best == 0 or rank < best):
			best = rank
	return best

# ─── shell ───────────────────────────────────────────────────────────────────

func _build() -> void:
	var dh := _dialog_h()

	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.01, 0.02, 0.06, 0.68)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.gui_input.connect(_on_backdrop_click)
	# Warm light pooled behind the dialog, so the scrim reads as a lit stage
	# rather than a flat dim — the profile popup does the same in cool blue.
	_backdrop.draw.connect(func() -> void:
		var ctr := _backdrop.size * 0.5
		var rad := _backdrop.size.length() * 0.5
		for i in 6:
			var t := float(i) / 5.0
			_backdrop.draw_circle(ctr, rad * (0.30 + 0.5 * t),
				Color(GOLD.r, GOLD.g, GOLD.b, 0.022 * (1.0 - t))))
	add_child(_backdrop)

	_dialog = Panel.new()
	_dialog.size = Vector2(DIALOG_W, dh)
	_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	var ds := StyleBoxFlat.new()
	ds.bg_color = Color(0.045, 0.055, 0.155, 0.99)
	ds.set_corner_radius_all(26)
	ds.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.70)
	ds.set_border_width_all(2)
	ds.shadow_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.32)
	ds.shadow_size = 30
	_polish(ds)
	_dialog.add_theme_stylebox_override("panel", ds)
	add_child(_dialog)

	# Hero first, header second: the ray fan is wider than the medallion and the
	# opaque header band is what stops it bleeding up behind the title.
	_build_hero()
	_build_header()

	var y := HEADER_H + HERO_H + 30.0
	for r in _shown:
		var card := _build_row(r)
		card.position = Vector2(PAD, y)
		_dialog.add_child(card)
		_rows.append(card)
		y += ROW_H + ROW_GAP

	_build_total(y - ROW_GAP + 16.0)
	_build_collect(dh - PAD - BTN_H)

func _build_header() -> void:
	# Header band across the top (rounded top corners only) for structure.
	var band := Panel.new()
	band.position = Vector2(2, 2)
	band.size = Vector2(DIALOG_W - 4, HEADER_H)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.10, 0.085, 0.20, 0.94)
	bs.corner_radius_top_left = 24
	bs.corner_radius_top_right = 24
	_polish(bs)
	band.add_theme_stylebox_override("panel", bs)
	# Glassy top sheen + a gold line pooling along the lower edge, so the band
	# reads as backlit and separates cleanly from the body.
	band.draw.connect(func() -> void:
		_vgrad(band, Rect2(2, 1.5, DIALOG_W - 8, 26), Color(1, 1, 1, 0.055), Color(1, 1, 1, 0.0))
		_vgrad(band, Rect2(14, HEADER_H - 2, DIALOG_W - 32, 2),
			Color(GOLD.r, GOLD.g, GOLD.b, 0.0), Color(GOLD.r, GOLD.g, GOLD.b, 0.32)))
	_dialog.add_child(band)

	var title := Label.new()
	title.text = "YOUR DAILY RANKINGS" if _grouped else "YESTERDAY'S RANKINGS"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1.0, 0.94, 0.62))
	title.add_theme_color_override("font_shadow_color", Color(0.70, 0.42, 0.0, 0.65))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 3)
	title.add_theme_constant_override("shadow_outline_size", 8)
	title.position = Vector2(0, 13)
	title.size = Vector2(DIALOG_W, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog.add_child(title)

	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.size = Vector2(40, 40)
	close.position = Vector2(DIALOG_W - 52, 12)
	close.add_theme_font_size_override("font_size", 24)
	close.add_theme_color_override("font_color", Color(0.85, 0.86, 1.0, 0.72))
	close.add_theme_color_override("font_hover_color", Color(1.0, 0.45, 0.45))
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(_close)
	_dialog.add_child(close)

# ─── hero medallion ──────────────────────────────────────────────────────────

# A struck medal for the day's best placement, standing in a fan of light with a
# ring of sparkles. The rays are a separate Control that is SLOWLY ROTATED by a
# tween rather than redrawn per frame — on the weakest phones an animated
# _draw() over this area costs real milliseconds, a transform costs nothing.
func _build_hero() -> void:
	var rank := _best_rank()
	var tier := _tier(rank)
	var col: Color = tier["col"]
	var ctr := Vector2(DIALOG_W * 0.5, HEADER_H + 62.0)

	var rays := Control.new()
	rays.size = Vector2(HERO_H * 1.75, HERO_H * 1.75)
	rays.position = ctr - rays.size * 0.5
	rays.pivot_offset = rays.size * 0.5
	rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rays.draw.connect(_draw_rays.bind(rays, col))
	_dialog.add_child(rays)
	var spin := create_tween().set_loops()
	spin.tween_property(rays, "rotation", TAU, 42.0).from(0.0).set_trans(Tween.TRANS_LINEAR)

	var medal := Control.new()
	medal.size = Vector2(112, 112)
	medal.position = ctr - medal.size * 0.5
	medal.pivot_offset = medal.size * 0.5
	medal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	medal.draw.connect(_draw_medal.bind(medal, col, rank, true))
	_dialog.add_child(medal)
	# A slow breath keeps the hero alive without drawing attention to itself.
	var breathe := create_tween().set_loops()
	breathe.tween_property(medal, "scale", Vector2.ONE * 1.035, 1.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	breathe.tween_property(medal, "scale", Vector2.ONE, 1.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	for i in 5:
		_add_sparkle(ctr, col, i)

	var caption := Label.new()
	caption.text = String(tier["headline"])
	caption.add_theme_font_size_override("font_size", 17)
	caption.add_theme_color_override("font_color", Color(col.r, col.g, col.b, 0.95))
	caption.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	caption.add_theme_constant_override("shadow_offset_y", 2)
	caption.add_theme_constant_override("shadow_outline_size", 5)
	caption.position = Vector2(0, HEADER_H + 120.0)
	caption.size = Vector2(DIALOG_W, 22)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog.add_child(caption)

	var sub := Label.new()
	if _grouped:
		sub.text = "Your best across %d days on the daily boards" % _days
	else:
		sub.text = "Where you finished on yesterday's daily boards"
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", Color(0.78, 0.82, 1.0, 0.72))
	sub.position = Vector2(0, HEADER_H + 144.0)
	sub.size = Vector2(DIALOG_W, 18)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog.add_child(sub)

# One twinkling point on a ring around the hero, each on its own offset cycle so
# they never pulse in unison.
func _add_sparkle(ctr: Vector2, col: Color, i: int) -> void:
	var ang := -PI * 0.5 + TAU * (float(i) / 5.0) + 0.4
	var rad := 78.0
	var s := Control.new()
	s.size = Vector2(18, 18)
	s.position = ctr + Vector2(cos(ang), sin(ang) * 0.78) * rad - s.size * 0.5
	s.pivot_offset = s.size * 0.5
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.draw.connect(func() -> void: _draw_sparkle(s, Vector2(9, 9), 9.0, col))
	_dialog.add_child(s)
	s.modulate.a = 0.0
	var tw := create_tween().set_loops()
	tw.tween_interval(0.35 * float(i))
	tw.tween_property(s, "modulate:a", 0.9, 0.45).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(s, "scale", Vector2.ONE, 0.45).from(Vector2.ONE * 0.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(s, "modulate:a", 0.0, 0.6).set_trans(Tween.TRANS_SINE)
	tw.tween_interval(1.5 - 0.2 * float(i))

# ─── placement card ──────────────────────────────────────────────────────────

func _build_row(r: Dictionary) -> Control:
	var diff := String(r.get("diff", ""))
	var rank := int(r.get("rank", 0))
	var reward := int(r.get("reward", 0))
	var d: Dictionary = _DIFF.get(diff, {"title": diff.to_upper(), "accent": Color(0.75, 0.79, 0.95)})
	var accent: Color = d["accent"]
	var tier := _tier(rank)
	var medal_col: Color = tier["col"]
	var w := DIALOG_W - PAD * 2.0

	var card := Panel.new()
	card.size = Vector2(w, ROW_H)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.075, 0.09, 0.21, 0.94)
	cs.set_corner_radius_all(18)
	cs.border_color = Color(accent.r, accent.g, accent.b, 0.34)
	cs.set_border_width_all(1)
	# A thicker lit edge on the left carries the difficulty colour into the card.
	cs.border_width_left = 4
	_polish(cs)
	_elevate(cs, 0.30, 8, 3.0)
	card.add_theme_stylebox_override("panel", cs)

	# Depth pass: top sheen + pooled bottom shadow, and a faint wash of the
	# difficulty colour bleeding in from the lit edge.
	var depth := Control.new()
	depth.size = card.size
	depth.mouse_filter = Control.MOUSE_FILTER_IGNORE
	depth.draw.connect(func() -> void:
		_vgrad(depth, Rect2(11, 1.5, w - 22, 26), Color(1, 1, 1, 0.055), Color(1, 1, 1, 0.0))
		_vgrad(depth, Rect2(11, ROW_H - 22, w - 22, 20),
			Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.16))
		_hgrad(depth, Rect2(4, 6, 96, ROW_H - 12),
			Color(accent.r, accent.g, accent.b, 0.13), Color(accent.r, accent.g, accent.b, 0.0)))
	card.add_child(depth)

	# Rank medal — the same struck disc as the hero, small and without its ribbon.
	var medal := Control.new()
	medal.size = Vector2(52, 52)
	medal.position = Vector2(16, (ROW_H - 52) * 0.5)
	medal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	medal.draw.connect(_draw_medal.bind(medal, medal_col, rank, false))
	card.add_child(medal)

	var name_lbl := Label.new()
	name_lbl.text = String(d["title"])
	name_lbl.add_theme_font_size_override("font_size", 21)
	name_lbl.add_theme_color_override("font_color", accent)
	name_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	name_lbl.add_theme_constant_override("shadow_offset_y", 2)
	name_lbl.add_theme_constant_override("shadow_outline_size", 4)
	name_lbl.position = Vector2(82, 12)
	name_lbl.size = Vector2(240, 26)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(name_lbl)

	var standing := Label.new()
	if rank > 0:
		standing.text = "%s · %s" % [_ordinal(rank), String(tier["caption"])]
	else:
		standing.text = String(tier["caption"])
	standing.add_theme_font_size_override("font_size", 13)
	standing.add_theme_color_override("font_color", Color(0.78, 0.82, 1.0, 0.72))
	standing.position = Vector2(82, 38)
	standing.size = Vector2(300, 18)
	standing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(standing)

	# Reward: a struck coin with the amount beside it, right-aligned.
	var coin := Control.new()
	coin.size = Vector2(34, 34)
	coin.position = Vector2(w - 156, (ROW_H - 34) * 0.5)
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin.draw.connect(func() -> void: PackIcons.draw_coin_3d(coin, Vector2(17, 16), 13.5))
	card.add_child(coin)

	var rw := Label.new()
	rw.text = "+%s" % _comma(reward)
	rw.add_theme_font_size_override("font_size", 25)
	rw.add_theme_color_override("font_color", Color(1.0, 0.92, 0.52))
	rw.add_theme_color_override("font_shadow_color", Color(0.6, 0.36, 0.0, 0.7))
	rw.add_theme_constant_override("shadow_offset_y", 2)
	rw.add_theme_constant_override("shadow_outline_size", 6)
	rw.position = Vector2(w - 118, (ROW_H - 30) * 0.5)
	rw.size = Vector2(102, 30)
	rw.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rw.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(rw)
	return card

# ─── total strip ─────────────────────────────────────────────────────────────

func _build_total(y: float) -> void:
	var w := DIALOG_W - PAD * 2.0
	_total_strip = Panel.new()
	_total_strip.size = Vector2(w, TOTAL_H)
	_total_strip.position = Vector2(PAD, y)
	_total_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ts := StyleBoxFlat.new()
	ts.bg_color = Color(0.27, 0.17, 0.03, 0.97)
	ts.set_corner_radius_all(18)
	ts.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.75)
	ts.set_border_width_all(2)
	ts.shadow_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.28)
	ts.shadow_size = 14
	_polish(ts)
	_total_strip.add_theme_stylebox_override("panel", ts)
	_dialog.add_child(_total_strip)

	var depth := Control.new()
	depth.size = _total_strip.size
	depth.mouse_filter = Control.MOUSE_FILTER_IGNORE
	depth.draw.connect(func() -> void:
		_vgrad(depth, Rect2(11, 1.5, w - 22, 32), Color(1, 1, 1, 0.10), Color(1, 1, 1, 0.0))
		_vgrad(depth, Rect2(11, TOTAL_H - 26, w - 22, 24), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.22))
		# Warm light gathering under the amount, so the gold end of the strip glows.
		_hgrad(depth, Rect2(w * 0.42, 5, w * 0.58 - 12, TOTAL_H - 10),
			Color(GOLD.r, GOLD.g, GOLD.b, 0.0), Color(GOLD.r, GOLD.g, GOLD.b, 0.10)))
	_total_strip.add_child(depth)

	var lbl := Label.new()
	lbl.text = "BANKED TO YOUR WALLET"
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.62, 0.80))
	lbl.position = Vector2(22, (TOTAL_H - 20) * 0.5)
	lbl.size = Vector2(320, 20)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_total_strip.add_child(lbl)

	var coin := Control.new()
	coin.size = Vector2(40, 40)
	coin.position = Vector2(w - 214, (TOTAL_H - 40) * 0.5)
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin.draw.connect(func() -> void: PackIcons.draw_coin_3d(coin, Vector2(20, 19), 16.0))
	_total_strip.add_child(coin)

	var amount := Label.new()
	amount.text = "+%s" % _comma(total)
	amount.add_theme_font_size_override("font_size", 38)
	amount.add_theme_color_override("font_color", Color(1.0, 0.94, 0.58))
	amount.add_theme_color_override("font_shadow_color", Color(0.55, 0.30, 0.0, 0.8))
	amount.add_theme_constant_override("shadow_offset_y", 3)
	amount.add_theme_constant_override("shadow_outline_size", 9)
	amount.position = Vector2(w - 172, (TOTAL_H - 46) * 0.5)
	amount.size = Vector2(150, 46)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	amount.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_total_strip.add_child(amount)

	# A soft specular bar that sweeps the strip once, right after it lands — the
	# "it's real gold" beat. Clipped to the strip so it never spills.
	_total_strip.clip_contents = true
	_shine = Control.new()
	_shine.size = Vector2(120, TOTAL_H)
	_shine.position = Vector2(-140, 0)
	_shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shine.draw.connect(func() -> void:
		# Skewed so it reads as a light bar raking across, not a vertical wipe.
		var pts := PackedVector2Array([
			Vector2(34, 0), Vector2(86, 0), Vector2(52, TOTAL_H), Vector2(0, TOTAL_H)])
		_shine.draw_polygon(pts, PackedColorArray([
			Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.22),
			Color(1, 1, 1, 0.22), Color(1, 1, 1, 0.0)])))
	_total_strip.add_child(_shine)

# ─── collect button ──────────────────────────────────────────────────────────

func _build_collect(y: float) -> void:
	var bw := 280.0
	var btn := Button.new()
	btn.text = "COLLECT"
	btn.size = Vector2(bw, BTN_H)
	btn.position = Vector2((DIALOG_W - bw) * 0.5, y)
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 25)
	btn.add_theme_color_override("font_color", Color(0.24, 0.13, 0.0))
	btn.add_theme_color_override("font_outline_color", Color(1.0, 0.94, 0.70, 0.5))
	btn.add_theme_constant_override("outline_size", 1)

	var s := StyleBoxFlat.new()
	s.bg_color = Color(1.00, 0.70, 0.14)
	s.set_corner_radius_all(20)
	s.border_color = Color(1.0, 0.92, 0.60, 0.85)
	s.border_width_left = 1
	s.border_width_right = 1
	s.border_width_top = 2
	s.border_width_bottom = 1
	s.shadow_color = Color(GOLD_DEEP.r, GOLD_DEEP.g, GOLD_DEEP.b, 0.65)
	s.shadow_size = 12
	s.shadow_offset = Vector2(0, 5)
	s.content_margin_top = 2
	s.content_margin_bottom = 6
	_polish(s)
	btn.add_theme_stylebox_override("normal", s)
	# Hover lifts the pill; press collapses the shadow and drops the face in.
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = Color(1.00, 0.78, 0.24)
	sh.shadow_size = 16
	sh.shadow_offset = Vector2(0, 8)
	btn.add_theme_stylebox_override("hover", sh)
	var sp := s.duplicate() as StyleBoxFlat
	sp.bg_color = Color(0.86, 0.56, 0.06)
	sp.shadow_size = 4
	sp.shadow_offset = Vector2(0, 1)
	sp.content_margin_top = 6
	sp.content_margin_bottom = 2
	btn.add_theme_stylebox_override("pressed", sp)

	var sheen := _add_sheen(btn, 20)
	btn.button_down.connect(func() -> void: sheen.modulate.a = 0.35)
	btn.button_up.connect(func() -> void: sheen.modulate.a = 1.0)
	btn.pressed.connect(_close)
	_dialog.add_child(btn)

# ─── entrance ────────────────────────────────────────────────────────────────

# The dialog pops in on the house beat, then the placement cards are dealt in one
# after another and the total strip lands last with its shine — so the receipt
# reads as a small ceremony instead of appearing all at once.
func _animate_in() -> void:
	_dialog.pivot_offset = _dialog.size * 0.5
	_dialog.scale = Vector2.ONE * 0.88
	_dialog.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_dialog, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_dialog, "modulate:a", 1.0, 0.20)
	tw.tween_property(_backdrop, "modulate:a", 1.0, 0.20).from(0.0)

	for i in _rows.size():
		var card := _rows[i]
		var home := card.position
		card.position = home + Vector2(28, 0)
		card.modulate.a = 0.0
		var t := create_tween()
		t.tween_interval(0.16 + 0.09 * float(i))
		t.tween_property(card, "position", home, 0.26) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(card, "modulate:a", 1.0, 0.22)

	if _total_strip != null:
		var land := 0.16 + 0.09 * float(_rows.size())
		_total_strip.modulate.a = 0.0
		_total_strip.pivot_offset = _total_strip.size * 0.5
		_total_strip.scale = Vector2(0.94, 0.94)
		var t2 := create_tween()
		t2.tween_interval(land)
		t2.tween_property(_total_strip, "modulate:a", 1.0, 0.20)
		t2.parallel().tween_property(_total_strip, "scale", Vector2.ONE, 0.30) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if _shine != null:
			var t3 := create_tween()
			t3.tween_interval(land + 0.26)
			t3.tween_property(_shine, "position:x", _total_strip.size.x + 40.0, 0.62) \
				.from(-140.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

# ─── medal / ray / sparkle art ───────────────────────────────────────────────

# A struck medal disc: cast shadow, milled rim, a gradient face lit from the
# top-left, an inner bezel, the placement numeral, and (for the hero) a pair of
# ribbon tails behind it. Same construction as the coin in pack_icons — concentric
# discs whose centre drifts toward the light — so it sits in the same world.
func _draw_medal(c: Control, col: Color, rank: int, hero: bool) -> void:
	var r := minf(c.size.x, c.size.y) * (0.40 if hero else 0.48)
	var ctr := c.size * 0.5
	if hero:
		ctr.y -= c.size.y * 0.04
		_draw_ribbon(c, ctr, r, col)

	var dark := col.darkened(0.55)
	var mid := col.darkened(0.18)
	var light := col.lightened(0.42)

	var cast := 0.10 if hero else 0.32          # the hero sits IN light; don't ring it
	c.draw_circle(ctr + Vector2(r * 0.10, r * 0.20), r * 1.06, Color(0, 0, 0, cast))
	c.draw_circle(ctr + Vector2(0, r * 0.10), r, dark)          # rim thickness below
	# Face: rim → mid → colour → catchlight, centre drifting to the top-left light.
	var steps := 11
	for i in steps:
		var t := float(i) / float(steps - 1)
		var rr := r * (1.0 - 0.80 * t)
		var off := Vector2(-r * 0.15, -r * 0.19) * t
		var face := dark.lerp(mid, minf(1.0, t * 2.2)) if t < 0.45 else mid.lerp(light, (t - 0.45) / 0.55)
		c.draw_circle(ctr + off, rr, face)
	# Milled edge + a bright top-left arc / dark lower-right arc so it reads round.
	var ridge := maxf(1.0, r * 0.07)
	c.draw_arc(ctr, r * 0.88, PI * 0.72, PI * 1.92, 26, Color(1, 1, 1, 0.42), ridge, true)
	c.draw_arc(ctr, r * 0.88, PI * 1.92, TAU + PI * 0.72, 26, Color(0, 0, 0, 0.24), ridge, true)
	# Inner bezel the numeral sits inside.
	c.draw_arc(ctr, r * 0.62, 0.0, TAU, 30, Color(0, 0, 0, 0.22), maxf(1.0, r * 0.05), true)
	c.draw_circle(ctr - Vector2(r * 0.30, r * 0.32), r * 0.14, Color(1, 1, 1, 0.50))

	# Placement numeral, drawn with the theme font so it matches the rest of the UI.
	var txt := str(rank) if rank > 0 else "—"
	var font := get_theme_default_font()
	if font != null:
		var fs := int(r * (0.86 if txt.length() < 2 else 0.66))
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var base := ctr + Vector2(-w * 0.5, fs * 0.36)
		c.draw_string(font, base + Vector2(0, 2), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(0, 0, 0, 0.45))
		c.draw_string(font, base, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col.darkened(0.70))

# Two ribbon tails hanging behind the hero medal.
func _draw_ribbon(c: Control, ctr: Vector2, r: float, col: Color) -> void:
	var deep := col.darkened(0.42)
	var edge := col.darkened(0.62)
	for side in [-1.0, 1.0]:
		var top := ctr + Vector2(side * r * 0.42, r * 0.30)
		var pts := PackedVector2Array([
			top + Vector2(-side * r * 0.20, 0),
			top + Vector2(side * r * 0.26, 0),
			top + Vector2(side * r * 0.62, r * 1.02),
			top + Vector2(side * r * 0.30, r * 0.80),
			top + Vector2(side * r * 0.06, r * 1.06)])
		c.draw_colored_polygon(pts, deep if side < 0.0 else edge)

# The light behind the hero: a warm bloom with a fan of spokes raking through it.
# Both are drawn PALE rather than in the medal's own colour — saturated gold at a
# low alpha over the navy body lands on a muddy brown that reads as dirt, so the
# fan looked like black spikes. Lifting the value (toward white) is what makes it
# read as light. Drawn once and rotated by tween (see _build_hero), so it costs
# nothing per frame.
func _draw_rays(host: Control, col: Color) -> void:
	var ctr := host.size * 0.5
	var reach := host.size.x * 0.5
	var pale := col.lerp(Color(1, 1, 1), 0.55)
	# Warm pool, densest at the centre and gone by the edge.
	for i in 10:
		var t := float(i) / 9.0
		host.draw_circle(ctr, reach * (0.12 + 0.88 * t),
			Color(pale.r, pale.g, pale.b, 0.07 * (1.0 - t) * (1.0 - t)))
	# Spokes, alternating long and short, each tapering to nothing at its tip.
	var n := 12
	for i in n:
		var a := TAU * float(i) / float(n)
		var far := reach * (0.96 if i % 2 == 0 else 0.70)
		var near := reach * 0.28
		var half_in := 0.075 if i % 2 == 0 else 0.048
		var half_out := half_in * 0.40
		var pts := PackedVector2Array([
			ctr + Vector2(cos(a - half_in), sin(a - half_in)) * near,
			ctr + Vector2(cos(a + half_in), sin(a + half_in)) * near,
			ctr + Vector2(cos(a + half_out), sin(a + half_out)) * far,
			ctr + Vector2(cos(a - half_out), sin(a - half_out)) * far])
		var hot := Color(pale.r, pale.g, pale.b, 0.30)
		var gone := Color(pale.r, pale.g, pale.b, 0.0)
		host.draw_polygon(pts, PackedColorArray([hot, hot, gone, gone]))

# A four-point star twinkle.
func _draw_sparkle(c: CanvasItem, ctr: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array([
		ctr + Vector2(0, -r), ctr + Vector2(r * 0.22, -r * 0.22),
		ctr + Vector2(r, 0), ctr + Vector2(r * 0.22, r * 0.22),
		ctr + Vector2(0, r), ctr + Vector2(-r * 0.22, r * 0.22),
		ctr + Vector2(-r, 0), ctr + Vector2(-r * 0.22, -r * 0.22)])
	c.draw_colored_polygon(pts, Color(1, 1, 1, 0.85))
	c.draw_circle(ctr, r * 0.30, Color(col.r, col.g, col.b, 0.55))

# ─── copy helpers ────────────────────────────────────────────────────────────

# Medal metal + wording for a placement. Bands mirror
# CoinsManager.daily_reward_for_rank (1 / 2 / 3 / 10 / 25 / 50), so what the
# player reads always matches what the server actually paid.
func _tier(rank: int) -> Dictionary:
	if rank == 1:
		return {"col": GOLD,   "caption": "Champion",   "headline": "DAILY CHAMPION"}
	if rank == 2:
		return {"col": SILVER, "caption": "Runner-up",  "headline": "RUNNER-UP"}
	if rank == 3:
		return {"col": BRONZE, "caption": "Third place", "headline": "THIRD PLACE"}
	if rank > 0 and rank <= 10:
		return {"col": COOL,   "caption": "Top 10",     "headline": "TOP 10 FINISH"}
	if rank > 0 and rank <= 25:
		return {"col": COOL,   "caption": "Top 25",     "headline": "TOP 25 FINISH"}
	if rank > 0:
		return {"col": COOL,   "caption": "Top 50",     "headline": "TOP 50 FINISH"}
	return {"col": COOL, "caption": "Ranked", "headline": "YOU PLACED"}

func _ordinal(n: int) -> String:
	if n <= 0:
		return "—"
	# 11/12/13 are the classic exceptions ("11th", not "11st").
	var suffix := "th"
	if not (n % 100 >= 11 and n % 100 <= 13):
		match n % 10:
			1: suffix = "st"
			2: suffix = "nd"
			3: suffix = "rd"
	return "%d%s" % [n, suffix]

func _comma(n: int) -> String:
	var s := str(n)
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += ","
		out += s[i]
	return out

# ─── shared chrome helpers (house style, see profile_screen.gd) ──────────────

func _polish(sb: StyleBoxFlat) -> void:
	sb.anti_aliasing = true
	sb.anti_aliasing_size = 1.0
	sb.corner_detail = 12
	sb.border_blend = true

func _elevate(sb: StyleBoxFlat, strength := 0.34, size := 10, offset := 4.0) -> void:
	sb.shadow_color = Color(0.0, 0.0, 0.0, strength)
	sb.shadow_size = size
	sb.shadow_offset = Vector2(0, offset)

# A vertical gradient quad (draw_polygon carries per-vertex colours — the one way
# to get a true gradient out of Godot's immediate draw API).
func _vgrad(c: CanvasItem, r: Rect2, top: Color, bot: Color) -> void:
	var pts := PackedVector2Array([
		r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	c.draw_polygon(pts, PackedColorArray([top, top, bot, bot]))

func _hgrad(c: CanvasItem, r: Rect2, left: Color, right: Color) -> void:
	var pts := PackedVector2Array([
		r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	c.draw_polygon(pts, PackedColorArray([left, right, right, left]))

# Glossy top-half highlight, so a rounded control reads as a domed, light-catching
# surface. Returns the Panel so the caller can dim it while held.
func _add_sheen(host: Control, corner: int) -> Panel:
	var sheen := Panel.new()
	sheen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheen.set_anchors_preset(Control.PRESET_TOP_WIDE)
	sheen.anchor_bottom = 0.5
	sheen.offset_left = 5
	sheen.offset_right = -5
	sheen.offset_top = 3
	sheen.offset_bottom = 0
	var ss := StyleBoxFlat.new()
	ss.bg_color = Color(1.0, 0.98, 0.88, 0.18)
	ss.set_corner_radius_all(maxi(6, corner - 6))
	ss.corner_radius_bottom_left = maxi(4, corner - 14)
	ss.corner_radius_bottom_right = maxi(4, corner - 14)
	sheen.add_theme_stylebox_override("panel", ss)
	sheen.z_index = 1
	host.add_child(sheen)
	return sheen

# ─── modal plumbing ──────────────────────────────────────────────────────────

func _on_backdrop_click(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
		_close()
	elif ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed:
		_close()

func _close() -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_dialog, "scale", _dialog.scale * 0.88, 0.15) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(_dialog, "modulate:a", 0.0, 0.15)
	tw.tween_property(_backdrop, "modulate:a", 0.0, 0.15)
	tw.chain().tween_callback(queue_free)

func _layout() -> void:
	var sz := get_viewport_rect().size
	if _backdrop:
		_backdrop.position = Vector2.ZERO
		_backdrop.size = sz
		_backdrop.queue_redraw()
	if _dialog:
		# On a short viewport (a very wide phone) scale the whole dialog down
		# rather than letting it run off the top and bottom edges.
		var fit := minf(1.0, (sz.y - 24.0) / maxf(1.0, _dialog.size.y))
		_dialog.pivot_offset = _dialog.size * 0.5
		_dialog.scale = Vector2.ONE * fit
		# Scaling happens about the pivot, so the visual centre stays put and
		# plain centring is still correct at any fit.
		_dialog.position = (sz - _dialog.size) * 0.5
