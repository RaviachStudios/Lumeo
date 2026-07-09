extends Control

# ─────────────────────────────────────────────────────────────────────────────
# Player Profile — a MODAL POPUP overlaid on the home screen (opened from the
# top-right profile card). Mirrors the daily-claim popup's modal conventions:
# a dim backdrop (tap to dismiss), a centred dialog that pops in with a tween,
# and a ✕ close button. Fully self-built — no exported scene, no PNGs.
#
# The dialog is a landscape "player card" split into two columns:
#   • LEFT  — identity panel: name + status, coins / badges chips, and the three
#             per-difficulty personal-best rows (best score + global rank). No
#             avatar icon (dropped per product decision).
#   • RIGHT — a scrolling badge gallery grouped by category (earned in colour,
#             locked as muted silhouettes); tap any badge for its detail card.
# All state comes from managers already resident in memory (GameState.high_scores,
# CoinsManager.balance, BadgeManager). Ranks show instantly from LeaderboardManager's
# local cache and then refresh async (guarded with a token, per the Firestore-hang
# mitigation).
# ─────────────────────────────────────────────────────────────────────────────

const BadgeIconControl := preload("res://badge_icon_control.gd")

# Assigned by the opener but not required — the popup closes itself.
var game_manager: Node

const GOLD := Color(1.0, 0.82, 0.28)
const PURPLE := Color(0.64, 0.46, 0.96)
const ACCENT := Color(0.52, 0.58, 1.0)

const DIFFS := [
	{"key": "easy",     "title": "EASY",     "accent": Color(0.28, 0.82, 0.45)},
	{"key": "moderate", "title": "MODERATE", "accent": Color(1.00, 0.72, 0.25)},
	{"key": "hard",     "title": "HARD",     "accent": Color(0.95, 0.32, 0.40)},
]
# Display order + friendly section titles for the gallery.
const CATS := [
	["onboarding",  "Getting Started"],
	["score",       "Memory & Skill"],
	["leaderboard", "Leaderboards"],
	["arena",       "The Arena"],
	["shop",        "Shop & Style"],
	["economy",     "Fortune"],
	["streak",      "Daily Streak"],
	["volume",      "Milestones"],
	["fun",         "Secrets"],
]

# Dialog geometry (computed in _ready from the viewport).
var _dw := 1140.0
var _dh := 660.0
const PAD := 26.0
const CONTENT_TOP := 72.0
const LW := 372.0          # left identity-panel width
const COL_GAP := 22.0

var _backdrop: ColorRect
var _dialog: Panel

var _rank_labels: Dictionary = {}   # diff -> Label
var _rank_token := 0
var _detail: Control

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP            # eats clicks behind
	var vp := get_viewport_rect().size
	_dw = clampf(vp.x - 140.0, 720.0, 1160.0)
	_dh = clampf(vp.y - 56.0, 520.0, 664.0)

	_build_backdrop()
	_build_dialog()
	_build_left_panel()
	_build_right_panel()
	_fetch_ranks()

	get_viewport().size_changed.connect(_recenter)
	_recenter()

	# Pop-in so the open feels intentional.
	_dialog.pivot_offset = _dialog.size * 0.5
	_dialog.scale = Vector2.ONE * 0.88
	_dialog.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_dialog, "scale", Vector2.ONE, 0.20) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_dialog, "modulate:a", 1.0, 0.18)
	tw.tween_property(_backdrop, "modulate:a", 1.0, 0.18).from(0.0)

# ─── shell (backdrop + dialog) ───────────────────────────────────────────────

func _build_backdrop() -> void:
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.01, 0.02, 0.06, 0.66)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.gui_input.connect(_on_backdrop_click)
	add_child(_backdrop)

func _build_dialog() -> void:
	_dialog = Panel.new()
	_dialog.size = Vector2(_dw, _dh)
	_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	var ds := StyleBoxFlat.new()
	ds.bg_color = Color(0.045, 0.055, 0.155, 0.99)
	ds.set_corner_radius_all(26)
	ds.border_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.65)
	ds.set_border_width_all(2)
	ds.shadow_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.35)
	ds.shadow_size = 30
	_dialog.add_theme_stylebox_override("panel", ds)
	add_child(_dialog)

	# Header band across the top (rounded top corners only) for structure.
	var band := Panel.new()
	band.position = Vector2(2, 2)
	band.size = Vector2(_dw - 4, 60)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.085, 0.10, 0.24, 0.92)
	bs.corner_radius_top_left = 24
	bs.corner_radius_top_right = 24
	_dialog.add_child(band)

	var title := Label.new()
	title.text = "PLAYER PROFILE"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.80, 0.85, 1.0))
	title.add_theme_color_override("font_shadow_color", Color(0.3, 0.4, 0.9, 0.6))
	title.add_theme_constant_override("shadow_offset_y", 2)
	title.add_theme_constant_override("shadow_outline_size", 5)
	title.position = Vector2(0, 12)
	title.size = Vector2(_dw, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog.add_child(title)

	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.size = Vector2(40, 40)
	close.position = Vector2(_dw - 52, 12)
	close.add_theme_font_size_override("font_size", 24)
	close.add_theme_color_override("font_color", Color(0.78, 0.82, 1.0, 0.75))
	close.add_theme_color_override("font_hover_color", Color(1.0, 0.45, 0.45))
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(_close)
	_dialog.add_child(close)

# ─── left identity panel ─────────────────────────────────────────────────────

func _build_left_panel() -> void:
	var content_h := _dh - CONTENT_TOP - PAD
	var panel := Panel.new()
	panel.position = Vector2(PAD, CONTENT_TOP)
	panel.size = Vector2(LW, content_h)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.07, 0.085, 0.20, 0.92)
	ps.set_corner_radius_all(20)
	ps.border_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.28)
	ps.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", ps)
	_dialog.add_child(panel)

	var signed := FirebaseManager.is_signed_in() and FirebaseManager.has_display_name()
	var uname := FirebaseManager.display_name if signed else "Guest"

	# Per product decision the profile carries no avatar icon — the panel leads
	# straight into the player's name, standing chips, and personal bests.
	var earned := BadgeManager.earned_count()
	var total := maxi(1, BadgeManager.total_count())

	var name_lbl := Label.new()
	name_lbl.text = uname
	name_lbl.add_theme_font_size_override("font_size", 30)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	name_lbl.position = Vector2(12, 44)
	name_lbl.size = Vector2(LW - 24, 40)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(name_lbl)

	var status := Label.new()
	status.text = "Signed in" if signed else "Playing as guest"
	status.add_theme_font_size_override("font_size", 15)
	status.add_theme_color_override("font_color", Color(0.58, 0.62, 0.82))
	status.position = Vector2(12, 86)
	status.size = Vector2(LW - 24, 22)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(status)

	# Coins + badges chips, centred as a group.
	var coins_chip := _chip(_fmt(CoinsManager.balance), GOLD, true)
	var badge_chip := _chip("%d / %d" % [earned, total], PURPLE, false)
	var group_w := coins_chip.size.x + 12.0 + badge_chip.size.x
	var sx := (LW - group_w) * 0.5
	coins_chip.position = Vector2(sx, 122)
	badge_chip.position = Vector2(sx + coins_chip.size.x + 12.0, 122)
	panel.add_child(coins_chip)
	panel.add_child(badge_chip)

	# Divider.
	var div := ColorRect.new()
	div.color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.18)
	div.position = Vector2(28, 186)
	div.size = Vector2(LW - 56, 1)
	div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(div)

	var sect := Label.new()
	sect.text = "PERSONAL  BESTS"
	sect.add_theme_font_size_override("font_size", 14)
	sect.add_theme_color_override("font_color", Color(0.62, 0.68, 0.92))
	sect.position = Vector2(28, 202)
	sect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(sect)

	# Three per-difficulty rows.
	var row_w := LW - 40.0
	var row_h := 72.0
	var gap := 10.0
	var y0 := 232.0
	for i in DIFFS.size():
		var row := _stat_row(DIFFS[i], Vector2(row_w, row_h))
		row.position = Vector2(20, y0 + i * (row_h + gap))
		panel.add_child(row)

func _stat_row(d: Dictionary, sz: Vector2) -> Control:
	var accent: Color = d["accent"]
	var diff: String = d["key"]
	var row := Panel.new()
	row.size = sz
	row.custom_minimum_size = sz
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.055, 0.07, 0.17, 0.95)
	sb.set_corner_radius_all(14)
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.45)
	sb.set_border_width_all(1)
	row.add_theme_stylebox_override("panel", sb)

	# Left accent bar.
	var bar := Panel.new()
	bar.position = Vector2(0, 0)
	bar.size = Vector2(5, sz.y)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bs := StyleBoxFlat.new()
	bs.bg_color = accent
	bs.corner_radius_top_left = 14
	bs.corner_radius_bottom_left = 14
	bar.add_theme_stylebox_override("panel", bs)
	row.add_child(bar)

	var title := Label.new()
	title.text = String(d["title"])
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", accent)
	title.position = Vector2(20, 10)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(title)

	var best: int = int(GameState.high_scores.get(diff, 0))
	var score := Label.new()
	score.text = str(best)
	score.add_theme_font_size_override("font_size", 32)
	score.add_theme_color_override("font_color", Color.WHITE)
	score.position = Vector2(18, 30)
	score.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(score)

	# Rank, right-aligned; filled in async by _fetch_ranks.
	var rank := Label.new()
	rank.text = "#—"
	rank.add_theme_font_size_override("font_size", 26)
	rank.add_theme_color_override("font_color", GOLD)
	rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rank.position = Vector2(sz.x - 150, 14)
	rank.size = Vector2(134, 32)
	rank.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(rank)

	var rcap := Label.new()
	rcap.text = "GLOBAL RANK"
	rcap.add_theme_font_size_override("font_size", 12)
	rcap.add_theme_color_override("font_color", Color(0.55, 0.60, 0.76))
	rcap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rcap.position = Vector2(sz.x - 150, 48)
	rcap.size = Vector2(134, 18)
	rcap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(rcap)
	_rank_labels[diff] = rank
	return row

# Rounded chip with a leading coloured dot (a coin when `coin`) + text.
func _chip(text: String, accent: Color, coin: bool) -> Control:
	var f := ThemeDB.fallback_font
	var fs := 20
	var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var w := tw + 58.0
	var p := Panel.new()
	p.size = Vector2(w, 40)
	p.custom_minimum_size = p.size
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.13, 0.92)
	sb.set_corner_radius_all(20)
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.65)
	sb.set_border_width_all(1)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot := _dot(accent, coin)
	dot.position = Vector2(12, 8)
	p.add_child(dot)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", fs)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.position = Vector2(40, 0)
	lbl.size = Vector2(w - 46, 40)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(lbl)
	return p

func _dot(accent: Color, coin: bool) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(24, 24)
	c.size = Vector2(24, 24)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void:
		if coin:
			c.draw_circle(Vector2(12, 12), 11, Color(0.95, 0.78, 0.20))
			c.draw_circle(Vector2(12, 12), 8, Color(1.0, 0.88, 0.36))
		else:
			c.draw_circle(Vector2(12, 12), 10, accent))
	return c

# ─── right badge gallery ─────────────────────────────────────────────────────

func _build_right_panel() -> void:
	var right_x := PAD + LW + COL_GAP
	var right_w := _dw - right_x - PAD
	var content_bottom := _dh - PAD

	var header := Label.new()
	header.text = "BADGES"
	header.add_theme_font_size_override("font_size", 24)
	header.add_theme_color_override("font_color", Color.WHITE)
	header.position = Vector2(right_x, CONTENT_TOP)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog.add_child(header)

	var count := Label.new()
	count.text = "%d / %d earned" % [BadgeManager.earned_count(), BadgeManager.total_count()]
	count.add_theme_font_size_override("font_size", 16)
	count.add_theme_color_override("font_color", PURPLE)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.position = Vector2(right_x + right_w - 220, CONTENT_TOP + 6)
	count.size = Vector2(220, 24)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog.add_child(count)

	var scroll_top := CONTENT_TOP + 40.0
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.position = Vector2(right_x, scroll_top)
	scroll.size = Vector2(right_w, content_bottom - scroll_top)
	_dialog.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(right_w - 16, 0)
	vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(vbox)

	# Bucket badges by category once.
	var by_cat: Dictionary = {}
	for b in BadgeManager.BADGES:
		var cat := String(b["cat"])
		if not by_cat.has(cat):
			by_cat[cat] = []
		by_cat[cat].append(b)

	for entry in CATS:
		var cat: String = entry[0]
		if not by_cat.has(cat):
			continue
		vbox.add_child(_section_header(String(entry[1]), BadgeManager.cat_color(cat)))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 8)
		for b in by_cat[cat]:
			flow.add_child(_badge_cell(b))
		vbox.add_child(flow)

func _section_header(text: String, accent: Color) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var bar := Panel.new()
	bar.custom_minimum_size = Vector2(6, 22)
	var bs := StyleBoxFlat.new()
	bs.bg_color = accent
	bs.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("panel", bs)
	h.add_child(bar)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	h.add_child(lbl)
	return h

func _badge_cell(b: Dictionary) -> Control:
	var earned := BadgeManager.has_badge(String(b["id"]))
	# A plain Button here (MOUSE_FILTER_STOP) swallows touch drags, so a swipe that
	# happens to start on a badge never reaches the ScrollContainer and the gallery
	# can't be scrolled. Instead the cell is a PASS control that lets the drag flow
	# up to the ScrollContainer, and we detect a genuine *tap* (press + release with
	# little movement) ourselves to open the detail card — same trade the shop cards
	# make (see shop_screen._make_theme_card).
	var cell := Control.new()
	cell.custom_minimum_size = Vector2(96, 116)
	cell.mouse_filter = Control.MOUSE_FILTER_PASS
	var press := {"pos": Vector2.ZERO, "down": false}
	cell.gui_input.connect(func(ev: InputEvent) -> void:
		var start := Vector2(-1, -1)
		var release := Vector2(-1, -1)
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed: start = mb.position
				else: release = mb.position
		elif ev is InputEventScreenTouch:
			var st := ev as InputEventScreenTouch
			if st.pressed: start = st.position
			else: release = st.position
		if start.x >= 0.0:
			press["pos"] = start
			press["down"] = true
		elif release.x >= 0.0 and bool(press["down"]):
			press["down"] = false
			# A tap, not the tail of a scroll drag.
			if release.distance_to(press["pos"] as Vector2) < 14.0:
				_show_detail(b, earned))

	var icon := BadgeIconControl.new()
	icon.custom_minimum_size = Vector2(78, 78)
	icon.size = Vector2(78, 78)
	icon.position = Vector2(9, 4)
	icon.set_badge(b, earned)
	cell.add_child(icon)

	var name_lbl := Label.new()
	name_lbl.text = String(b["name"])
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color",
		Color(0.9, 0.92, 1.0) if earned else Color(0.5, 0.53, 0.64))
	name_lbl.position = Vector2(0, 84)
	name_lbl.size = Vector2(96, 30)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(name_lbl)
	return cell

# ─── badge detail overlay ────────────────────────────────────────────────────

func _show_detail(b: Dictionary, earned: bool) -> void:
	if _detail and is_instance_valid(_detail):
		_detail.queue_free()
	var vp := get_viewport_rect().size
	var accent: Color = BadgeManager.cat_color(String(b["cat"]))

	var overlay := Panel.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var os := StyleBoxFlat.new()
	os.bg_color = Color(0.02, 0.03, 0.08, 0.72)
	overlay.add_theme_stylebox_override("panel", os)
	var dismiss := func() -> void:
		if is_instance_valid(overlay):
			overlay.queue_free()
			_detail = null
	# Tap the dim area to dismiss.
	var closer := Button.new()
	closer.flat = true
	closer.set_anchors_preset(Control.PRESET_FULL_RECT)
	closer.focus_mode = Control.FOCUS_NONE
	closer.pressed.connect(dismiss)
	overlay.add_child(closer)

	var card := Panel.new()
	card.size = Vector2(420, 360)
	card.position = (vp - card.size) * 0.5
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.08, 0.10, 0.20, 0.99)
	cs.set_corner_radius_all(24)
	cs.border_color = accent if earned else Color(0.35, 0.38, 0.48)
	cs.set_border_width_all(2)
	cs.shadow_color = Color(accent.r, accent.g, accent.b, 0.4 if earned else 0.0)
	cs.shadow_size = 24
	card.add_theme_stylebox_override("panel", cs)
	overlay.add_child(card)

	# Explicit ✕ so there's always an obvious way out (tapping the dim area works
	# too, but a visible close affordance is clearer, especially on a phone).
	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.size = Vector2(40, 40)
	close.position = Vector2(card.size.x - 48, 8)
	close.add_theme_font_size_override("font_size", 24)
	close.add_theme_color_override("font_color", Color(0.82, 0.85, 1.0, 0.8))
	close.add_theme_color_override("font_hover_color", Color(1.0, 0.45, 0.45))
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(dismiss)
	card.add_child(close)

	var icon := BadgeIconControl.new()
	icon.custom_minimum_size = Vector2(150, 150)
	icon.size = Vector2(150, 150)
	icon.position = Vector2((card.size.x - 150) * 0.5, 28)
	icon.set_badge(b, earned)
	card.add_child(icon)

	var name_lbl := Label.new()
	name_lbl.text = String(b["name"])
	name_lbl.add_theme_font_size_override("font_size", 28)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.position = Vector2(20, 190)
	name_lbl.size = Vector2(card.size.x - 40, 36)
	card.add_child(name_lbl)

	var desc := Label.new()
	desc.text = String(b["desc"])
	desc.add_theme_font_size_override("font_size", 17)
	desc.add_theme_color_override("font_color", Color(0.72, 0.76, 0.9))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.position = Vector2(30, 232)
	desc.size = Vector2(card.size.x - 60, 60)
	card.add_child(desc)

	var status := Label.new()
	status.text = "✓ EARNED" if earned else "🔒 LOCKED"
	status.add_theme_font_size_override("font_size", 18)
	status.add_theme_color_override("font_color",
		Color(0.4, 0.9, 0.55) if earned else Color(0.55, 0.58, 0.7))
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.position = Vector2(20, 306)
	status.size = Vector2(card.size.x - 40, 30)
	card.add_child(status)

	add_child(overlay)
	_detail = overlay

# ─── async leaderboard ranks ─────────────────────────────────────────────────

func _fetch_ranks() -> void:
	_rank_token += 1
	var token := _rank_token
	if not (FirebaseManager.is_signed_in() and FirebaseManager.has_display_name()):
		for diff: String in _rank_labels:
			(_rank_labels[diff] as Label).text = "—"
		return
	# Show the last-known rank from the local cache immediately so the card never
	# opens on a "loading" placeholder — the async refresh below then corrects it
	# if standings have moved since it was cached.
	for diff: String in _rank_labels:
		var cached := int(LeaderboardManager.cached_rank(diff))
		if cached > 0:
			(_rank_labels[diff] as Label).text = "#%d" % cached
	for d in DIFFS:
		var diff: String = d["key"]
		var data: Dictionary = await LeaderboardManager.load_global(diff)
		if token != _rank_token or not is_inside_tree():
			return
		var lbl: Label = _rank_labels.get(diff, null)
		if lbl == null:
			continue
		var rank := int(data.get("my_rank", 0))
		lbl.text = ("#%d" % rank) if rank > 0 else "—"

# ─── close / layout ──────────────────────────────────────────────────────────

func _on_backdrop_click(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
		_close()
	elif ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed:
		_close()

func _close() -> void:
	_rank_token += 1
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

func _exit_tree() -> void:
	_rank_token += 1

# ─── helpers ─────────────────────────────────────────────────────────────────

func _fmt(n: int) -> String:
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out
