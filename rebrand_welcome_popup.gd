extends Control

# ─────────────────────────────────────────────────────────────────────────────
# Welcome to Lumeo — the one-time rebrand receipt, shown on the first home-screen
# open after the rebrand update.
#
# The old wheel stopped being a play device and every shader theme left the shop,
# so a one-off migration (tools/rebrand_migrate.js) refunded that dead inventory,
# added an early-player gift, wiped the old items, and left a receipt on
# /users/{uid} as `rebrand_v1`. THE COINS ARE ALREADY BANKED by the time this
# opens — same contract as daily_rank_reward_popup: this is the celebration, not
# the transaction, and COLLECT only marks the receipt as seen.
#
# Shown once, and only to players who existed before the rebrand:
#   * eligibility — the migration only wrote `rebrand_v1` onto the docs that
#     existed when it ran, so a newer account has no receipt and never sees this.
#   * once-only  — CoinsManager.mark_rebrand_shown() sets `rebrand_v1.shown`, and
#     home_screen only opens this while that key is missing. Server-side state,
#     so a reinstall or a second device can't replay it.
#
# The tone is a party, not an apology: confetti falls across the whole screen for
# as long as the modal is up, in front of the dialog as well as behind it, and
# the copy never mentions what the game used to be called.
#
# Inputs (set by the caller before add_child):
#   receipt : Dictionary  the raw `rebrand_v1` map
# ─────────────────────────────────────────────────────────────────────────────

var receipt: Dictionary = {}

const GOLD := Color(1.00, 0.82, 0.28)
const GOLD_DEEP := Color(0.62, 0.36, 0.02)
const VIOLET := Color(0.56, 0.42, 1.00)

const DIALOG_W := 660.0
const PAD := 24.0
const HEADER_H := 62.0
const HERO_H := 236.0
const ROW_H := 66.0
const ROW_GAP := 9.0
const TOTAL_H := 72.0
const BTN_H := 62.0

# Row art per receipt key. `blurb` is the small line under the label; the accent
# tints the card's lit left edge, matching the colour the shop used for that
# family of items.
const _ROW_ART := {
	"wheel":  {"blurb": "Rims, hubs & numerals",   "accent": Color(0.95, 0.36, 0.48)},
	"skins":  {"blurb": "Complete wheel skins",    "accent": Color(0.98, 0.55, 0.30)},
	"themes": {"blurb": "Retired shop backgrounds","accent": Color(0.31, 0.64, 1.00)},
	"levels": {"blurb": "Moderate & Hard unlocks", "accent": Color(0.28, 0.82, 0.55)},
}

# The five board buttons of the hero glyph: angle around the board ellipse and
# the colour each one lights. Same five hues as the app icon.
const _BOARD_BUTTONS := [
	{"u": -0.10, "v": -0.62, "col": Color(1.00, 0.82, 0.29)},
	{"u": -0.78, "v": -0.05, "col": Color(0.90, 0.28, 0.30)},
	{"u":  0.78, "v": -0.05, "col": Color(0.18, 0.78, 0.55)},
	{"u": -0.46, "v":  0.48, "col": Color(0.55, 0.36, 0.96)},
	{"u":  0.50, "v":  0.48, "col": Color(0.23, 0.51, 0.96)},
]

var _backdrop: ColorRect
var _dialog: Panel
var _rows: Array[Control] = []
var _total_strip: Panel
var _shine: Control
var _confetti_back: Control       # falls behind the dialog
var _confetti_front: Control      # a thinner layer passing in front of it
var _bits: Array[Dictionary] = []
var _closing := false
# Scale that keeps the dialog inside a short viewport (see _layout). The entrance
# tween has to land on THIS, not on 1.0, or a tall receipt — every refund row at
# once — pops back to full size and runs off the top and bottom of the screen.
var _fit := 1.0

# The rows actually drawn: the receipt's refund lines plus the gift, which is
# always last and always present.
var _lines: Array[Dictionary] = []
var _total := 0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_prepare_lines()
	_build()
	_layout()
	get_viewport().size_changed.connect(_layout)
	_animate_in()

# ─── data shaping ────────────────────────────────────────────────────────────

# The migration already filtered out the empty categories, so `items` holds only
# rows worth showing. A player who owned nothing old gets an empty list and this
# popup becomes the gift-only layout with no extra branching anywhere.
func _prepare_lines() -> void:
	var refund := int(receipt.get("refund", 0))
	var gift := int(receipt.get("gift", 0))
	var items: Variant = receipt.get("items", [])
	if items is Array:
		for it in items:
			if not (it is Dictionary):
				continue
			var d := it as Dictionary
			var coins := int(d.get("coins", 0))
			if coins <= 0:
				continue
			var art: Dictionary = _ROW_ART.get(String(d.get("key", "")), {})
			var n := int(d.get("n", 0))
			var blurb := String(art.get("blurb", "Retired items"))
			if n > 0:
				blurb += " · %d item%s" % [n, "" if n == 1 else "s"]
			_lines.append({
				"label": String(d.get("label", "Retired items")),
				"blurb": blurb,
				"coins": coins,
				"accent": art.get("accent", Color(0.75, 0.79, 0.95)),
				"gift": false,
			})
	# A player with nothing to refund gets NO rows: a single "Early player gift
	# +2,000" card sitting directly above a total strip reading the same number is
	# just the amount printed twice. The gold strip carries it alone instead, and
	# the body copy above already says what it is for.
	if gift > 0 and not _lines.is_empty():
		_lines.append({
			"label": "Early player gift",
			"blurb": "You were here before the rebrand",
			"coins": gift,
			"accent": VIOLET,
			"gift": true,
		})
	_total = refund + gift

func _dialog_h() -> float:
	var rows := _lines.size()
	var rows_h := 0.0 if rows == 0 else rows * ROW_H + (rows - 1) * ROW_GAP
	return HEADER_H + HERO_H + 14.0 + rows_h + 16.0 + TOTAL_H + 18.0 + BTN_H + PAD

# ─── shell ───────────────────────────────────────────────────────────────────

func _build() -> void:
	var dh := _dialog_h()

	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.01, 0.02, 0.06, 0.68)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.gui_input.connect(_on_backdrop_click)
	_backdrop.draw.connect(func() -> void:
		var ctr := _backdrop.size * 0.5
		var rad := _backdrop.size.length() * 0.5
		for i in 6:
			var t := float(i) / 5.0
			_backdrop.draw_circle(ctr, rad * (0.30 + 0.5 * t),
				Color(GOLD.r, GOLD.g, GOLD.b, 0.026 * (1.0 - t))))
	add_child(_backdrop)

	# Back layer, then the dialog, then the front layer — child order IS paint
	# order here, which is what puts some of the paper in front of the modal.
	_confetti_back = _make_confetti_layer()
	add_child(_confetti_back)

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

	_confetti_front = _make_confetti_layer()
	add_child(_confetti_front)

	_spawn_confetti()

	# Hero before header: the ray fan is wider than the glyph, and the opaque
	# header band is what stops it bleeding up behind the title.
	_build_hero()
	_build_header()

	var y := HEADER_H + HERO_H + 14.0
	for line in _lines:
		var card := _build_row(line)
		card.position = Vector2(PAD, y)
		_dialog.add_child(card)
		_rows.append(card)
		y += ROW_H + ROW_GAP

	_build_total((y - ROW_GAP if not _lines.is_empty() else y) + 16.0)
	_build_collect(dh - PAD - BTN_H)

func _build_header() -> void:
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
	band.draw.connect(func() -> void:
		_vgrad(band, Rect2(2, 1.5, DIALOG_W - 8, 26), Color(1, 1, 1, 0.055), Color(1, 1, 1, 0.0))
		_vgrad(band, Rect2(14, HEADER_H - 2, DIALOG_W - 32, 2),
			Color(GOLD.r, GOLD.g, GOLD.b, 0.0), Color(GOLD.r, GOLD.g, GOLD.b, 0.32)))
	_dialog.add_child(band)

	var title := Label.new()
	title.text = "WELCOME TO LUMEO!"
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

# ─── hero ────────────────────────────────────────────────────────────────────

# The new board standing in a slowly turning fan of light, under the headline.
# Nothing here refers to what the game used to be — a player who never noticed
# the rename should read this as a party, not an explanation.
func _build_hero() -> void:
	var ctr := Vector2(DIALOG_W * 0.5, HEADER_H + 62.0)

	# The fan is a Control ROTATED by a tween, not redrawn per frame: on the
	# weakest phones an animated _draw() over this area costs real milliseconds
	# while a transform costs nothing.
	var rays := Control.new()
	rays.size = Vector2(196, 196)
	rays.position = ctr - rays.size * 0.5
	rays.pivot_offset = rays.size * 0.5
	rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rays.draw.connect(_draw_rays.bind(rays))
	_dialog.add_child(rays)
	var spin := create_tween().set_loops()
	spin.tween_property(rays, "rotation", TAU, 44.0).from(0.0)

	var glyph := Control.new()
	glyph.size = Vector2(112, 112)
	glyph.position = ctr - glyph.size * 0.5
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph.draw.connect(_draw_board.bind(glyph))
	_dialog.add_child(glyph)

	var head := Label.new()
	head.text = "We've rebranded!"
	head.add_theme_font_size_override("font_size", 32)
	head.add_theme_color_override("font_color", Color(1.0, 0.93, 0.66))
	head.add_theme_color_override("font_shadow_color", Color(0.55, 0.30, 0.0, 0.7))
	head.add_theme_constant_override("shadow_offset_y", 3)
	head.add_theme_constant_override("shadow_outline_size", 8)
	head.position = Vector2(0, HEADER_H + 118.0)
	head.size = Vector2(DIALOG_W, 40)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog.add_child(head)

	var body := Label.new()
	body.text = ("A new name, a new board, a whole new look. Everything you bought for the "
		+ "old look has been refunded in full — and there's a little something extra in there too.") \
		if int(receipt.get("refund", 0)) > 0 else \
		("A new name, a new board, a whole new look — and a gift to celebrate it with, "
		+ "because you were playing before anyone else.")
	body.add_theme_font_size_override("font_size", 16)
	body.add_theme_color_override("font_color", Color(0.80, 0.84, 1.0, 0.82))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.position = Vector2(PAD + 34.0, HEADER_H + 160.0)
	body.size = Vector2(DIALOG_W - (PAD + 34.0) * 2.0, 74)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog.add_child(body)

# ─── rows ────────────────────────────────────────────────────────────────────

func _build_row(line: Dictionary) -> Control:
	var accent: Color = line["accent"]
	var w := DIALOG_W - PAD * 2.0
	var is_gift: bool = bool(line["gift"])

	var card := Panel.new()
	card.size = Vector2(w, ROW_H)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.10, 0.085, 0.24, 0.94) if is_gift else Color(0.075, 0.09, 0.21, 0.94)
	cs.set_corner_radius_all(18)
	cs.border_color = Color(accent.r, accent.g, accent.b, 0.46 if is_gift else 0.34)
	cs.set_border_width_all(1)
	cs.border_width_left = 4
	_polish(cs)
	_elevate(cs, 0.30, 8, 3.0)
	card.add_theme_stylebox_override("panel", cs)

	var depth := Control.new()
	depth.size = card.size
	depth.mouse_filter = Control.MOUSE_FILTER_IGNORE
	depth.draw.connect(func() -> void:
		_vgrad(depth, Rect2(11, 1.5, w - 22, 24), Color(1, 1, 1, 0.055), Color(1, 1, 1, 0.0))
		_vgrad(depth, Rect2(11, ROW_H - 20, w - 22, 18), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.16))
		_hgrad(depth, Rect2(4, 6, 110, ROW_H - 12),
			Color(accent.r, accent.g, accent.b, 0.16 if is_gift else 0.13),
			Color(accent.r, accent.g, accent.b, 0.0)))
	card.add_child(depth)

	var icon := Control.new()
	icon.size = Vector2(44, 44)
	icon.position = Vector2(16, (ROW_H - 44) * 0.5)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_gift:
		icon.draw.connect(_draw_gift.bind(icon, accent))
	else:
		icon.draw.connect(_draw_tag.bind(icon, accent))
	card.add_child(icon)

	var name_lbl := Label.new()
	name_lbl.text = String(line["label"])
	name_lbl.add_theme_font_size_override("font_size", 20)
	name_lbl.add_theme_color_override("font_color", Color(0.94, 0.95, 1.0))
	name_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	name_lbl.add_theme_constant_override("shadow_offset_y", 2)
	name_lbl.add_theme_constant_override("shadow_outline_size", 4)
	name_lbl.position = Vector2(74, 10)
	name_lbl.size = Vector2(w - 220, 26)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(name_lbl)

	var blurb := Label.new()
	blurb.text = String(line["blurb"])
	blurb.add_theme_font_size_override("font_size", 13)
	blurb.add_theme_color_override("font_color", Color(0.78, 0.82, 1.0, 0.70))
	blurb.position = Vector2(74, 36)
	blurb.size = Vector2(w - 220, 18)
	blurb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(blurb)

	var coin := Control.new()
	coin.size = Vector2(32, 32)
	coin.position = Vector2(w - 152, (ROW_H - 32) * 0.5)
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin.draw.connect(func() -> void: PackIcons.draw_coin_3d(coin, Vector2(16, 15), 12.5))
	card.add_child(coin)

	var amount := Label.new()
	amount.text = "+%s" % _comma(int(line["coins"]))
	amount.add_theme_font_size_override("font_size", 24)
	amount.add_theme_color_override("font_color", Color(1.0, 0.92, 0.52))
	amount.add_theme_color_override("font_shadow_color", Color(0.6, 0.36, 0.0, 0.7))
	amount.add_theme_constant_override("shadow_offset_y", 2)
	amount.add_theme_constant_override("shadow_outline_size", 6)
	amount.position = Vector2(w - 116, (ROW_H - 30) * 0.5)
	amount.size = Vector2(100, 30)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	amount.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(amount)
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
		_hgrad(depth, Rect2(w * 0.42, 5, w * 0.58 - 12, TOTAL_H - 10),
			Color(GOLD.r, GOLD.g, GOLD.b, 0.0), Color(GOLD.r, GOLD.g, GOLD.b, 0.10)))
	_total_strip.add_child(depth)

	var lbl := Label.new()
	lbl.text = "ADDED TO YOUR WALLET" if not _lines.is_empty() else "EARLY PLAYER GIFT"
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
	amount.text = "+%s" % _comma(_total)
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

	_total_strip.clip_contents = true
	_shine = Control.new()
	_shine.size = Vector2(120, TOTAL_H)
	_shine.position = Vector2(-140, 0)
	_shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shine.draw.connect(func() -> void:
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

# ─── confetti ────────────────────────────────────────────────────────────────

const _CONFETTI_COLORS := [
	Color(1.00, 0.82, 0.29), Color(0.90, 0.28, 0.30), Color(0.18, 0.82, 0.62),
	Color(0.55, 0.36, 0.96), Color(0.23, 0.51, 0.96), Color(1.00, 0.96, 0.86),
]
# 78 back + 22 front. Each piece is one draw_rect under a per-piece transform,
# which is the cheapest rotated quad Godot's immediate API offers; the array is
# POOLED (a piece that falls off the bottom is respawned in place) so the whole
# effect allocates nothing per frame.
const _CONFETTI_BACK := 78
const _CONFETTI_FRONT := 22

func _make_confetti_layer() -> Control:
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.draw.connect(_draw_confetti.bind(layer))
	return layer

func _spawn_confetti() -> void:
	for i in (_CONFETTI_BACK + _CONFETTI_FRONT):
		_bits.append(_new_bit(i >= _CONFETTI_BACK, true))

# `burst` seeds a piece anywhere up the screen so the modal opens already inside
# a shower instead of waiting for the first pieces to fall into frame.
func _new_bit(front: bool, burst: bool) -> Dictionary:
	var sz := get_viewport_rect().size
	return {
		"front": front,
		"x": randf() * maxf(sz.x, 1.0),
		"y": -randf() * (sz.y * 0.9) if burst else -20.0,
		"vy": (150.0 if front else 95.0) + randf() * 130.0,
		"drift": 16.0 + randf() * 34.0,
		"phase": randf() * TAU,
		"rot": randf() * TAU,
		"spin": (randf() - 0.5) * 6.0,
		"w": (5.0 if front else 3.5) + randf() * 5.0,
		"h": (9.0 if front else 6.0) + randf() * 7.0,
		"ribbon": randf() < 0.26,
		"col": _CONFETTI_COLORS[randi() % _CONFETTI_COLORS.size()],
	}

func _process(delta: float) -> void:
	if _closing:
		return
	var sz := get_viewport_rect().size
	for i in _bits.size():
		var b := _bits[i]
		b["y"] = float(b["y"]) + float(b["vy"]) * delta
		b["phase"] = float(b["phase"]) + delta * 2.4
		b["rot"] = float(b["rot"]) + float(b["spin"]) * delta
		if float(b["y"]) > sz.y + 24.0:
			_bits[i] = _new_bit(bool(b["front"]), false)
		else:
			_bits[i] = b
	if _confetti_back != null:
		_confetti_back.queue_redraw()
	if _confetti_front != null:
		_confetti_front.queue_redraw()

func _draw_confetti(layer: Control) -> void:
	var front := layer == _confetti_front
	for b in _bits:
		if bool(b["front"]) != front:
			continue
		var x := float(b["x"]) + sin(float(b["phase"])) * float(b["drift"])
		var rot := float(b["rot"])
		layer.draw_set_transform(Vector2(x, float(b["y"])), rot, Vector2.ONE)
		var w := float(b["w"])
		var h := float(b["h"])
		if bool(b["ribbon"]):
			layer.draw_rect(Rect2(-1.0, -h, 2.0, h * 2.0), b["col"])
		else:
			# Squashing the height on the spin angle is what sells a flat piece of
			# paper tumbling, without ever leaving 2D.
			var squash := absf(cos(rot * 1.7))
			layer.draw_rect(Rect2(-w * 0.5, -h * 0.5 * squash, w, h * squash + 1.0), b["col"])
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ─── hero art ────────────────────────────────────────────────────────────────

# The light fan behind the board: alternating long/short wedges, drawn once and
# then rotated by the tween in _build_hero.
func _draw_rays(c: Control) -> void:
	var ctr := c.size * 0.5
	var n := 18
	for i in n:
		var a0 := TAU * float(i) / float(n)
		var a1 := a0 + TAU / float(n) * 0.42
		var r := ctr.x * (1.0 if i % 2 == 0 else 0.74)
		c.draw_polygon(
			PackedVector2Array([ctr, ctr + Vector2(cos(a0), sin(a0)) * r,
				ctr + Vector2(cos(a1), sin(a1)) * r]),
			PackedColorArray([
				Color(GOLD.r, GOLD.g, GOLD.b, 0.16),
				Color(GOLD.r, GOLD.g, GOLD.b, 0.0),
				Color(GOLD.r, GOLD.g, GOLD.b, 0.0)]))

# The Lumeo board seen at a tilt: an elliptical deck with five lit buttons.
func _draw_board(c: Control) -> void:
	var ctr := Vector2(c.size.x * 0.5, c.size.y * 0.56)
	var rx := c.size.x * 0.44
	var ry := rx * 0.46

	# Deck: an ellipse approximated as a polygon (draw_circle can't be squashed),
	# with a rim highlight along the top edge.
	var deck := PackedVector2Array()
	var rim := PackedVector2Array()
	for i in 40:
		var a := TAU * float(i) / 40.0
		deck.append(ctr + Vector2(cos(a) * rx, sin(a) * ry))
		rim.append(ctr + Vector2(cos(a) * rx * 1.06, sin(a) * ry * 1.06))
	c.draw_colored_polygon(rim, Color(0.35, 0.28, 0.72, 0.55))
	c.draw_colored_polygon(deck, Color(0.10, 0.12, 0.34, 1.0))

	for b in _BOARD_BUTTONS:
		var p := ctr + Vector2(float(b["u"]) * rx * 0.72, float(b["v"]) * ry * 1.15)
		var col: Color = b["col"]
		c.draw_circle(p + Vector2(0, 2.5), 11.0, Color(0, 0, 0, 0.35))
		c.draw_circle(p, 11.0, Color(col.r, col.g, col.b, 0.30))       # glow
		c.draw_circle(p, 8.4, col)
		c.draw_circle(p - Vector2(2.0, 2.4), 3.2, Color(1, 1, 1, 0.34)) # specular

# A refund row's icon: a price tag, punched and tilted.
func _draw_tag(c: Control, accent: Color) -> void:
	var ctr := c.size * 0.5
	c.draw_set_transform(ctr, -0.32, Vector2.ONE)
	c.draw_rect(Rect2(-13, -10, 22, 20), Color(accent.r, accent.g, accent.b, 0.22), true)
	c.draw_rect(Rect2(-13, -10, 22, 20), Color(accent.r, accent.g, accent.b, 0.85), false, 2.0)
	c.draw_circle(Vector2(-7, -4), 2.6, Color(accent.r, accent.g, accent.b, 0.95))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# The gift row's icon: a wrapped box with a ribbon cross and a bow.
func _draw_gift(c: Control, accent: Color) -> void:
	var ctr := c.size * 0.5
	var box := Rect2(ctr.x - 13, ctr.y - 8, 26, 18)
	c.draw_rect(box, Color(accent.r, accent.g, accent.b, 0.26), true)
	c.draw_rect(box, Color(accent.r, accent.g, accent.b, 0.90), false, 2.0)
	c.draw_line(Vector2(ctr.x, box.position.y), Vector2(ctr.x, box.end.y),
		Color(accent.r, accent.g, accent.b, 0.90), 2.0)
	c.draw_line(Vector2(box.position.x, ctr.y - 1), Vector2(box.end.x, ctr.y - 1),
		Color(accent.r, accent.g, accent.b, 0.90), 2.0)
	c.draw_circle(Vector2(ctr.x - 4, box.position.y - 3), 3.4, Color(accent.r, accent.g, accent.b, 0.95))
	c.draw_circle(Vector2(ctr.x + 4, box.position.y - 3), 3.4, Color(accent.r, accent.g, accent.b, 0.95))

# ─── entrance ────────────────────────────────────────────────────────────────

func _animate_in() -> void:
	_dialog.pivot_offset = _dialog.size * 0.5
	_dialog.scale = Vector2.ONE * _fit * 0.88
	_dialog.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_dialog, "scale", Vector2.ONE * _fit, 0.22) \
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

# ─── helpers (house style, see daily_rank_reward_popup.gd) ───────────────────

func _comma(n: int) -> String:
	var s := str(n)
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += ","
		out += s[i]
	return out

func _polish(sb: StyleBoxFlat) -> void:
	sb.anti_aliasing = true
	sb.anti_aliasing_size = 1.0
	sb.corner_detail = 12
	sb.border_blend = true

func _elevate(sb: StyleBoxFlat, strength := 0.34, size := 10, offset := 4.0) -> void:
	sb.shadow_color = Color(0.0, 0.0, 0.0, strength)
	sb.shadow_size = size
	sb.shadow_offset = Vector2(0, offset)

func _vgrad(c: CanvasItem, r: Rect2, top: Color, bot: Color) -> void:
	var pts := PackedVector2Array([
		r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	c.draw_polygon(pts, PackedColorArray([top, top, bot, bot]))

func _hgrad(c: CanvasItem, r: Rect2, left: Color, right: Color) -> void:
	var pts := PackedVector2Array([
		r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	c.draw_polygon(pts, PackedColorArray([left, right, right, left]))

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

# Closing IS the acknowledgement, by any route — button, ✕ or backdrop tap. The
# coins were banked by the migration, so the only thing this write protects is
# the player seeing the same party twice.
func _close() -> void:
	if _closing:
		return
	_closing = true
	CoinsManager.mark_rebrand_shown()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_dialog, "scale", _dialog.scale * 0.88, 0.15) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(_dialog, "modulate:a", 0.0, 0.15)
	tw.tween_property(_backdrop, "modulate:a", 0.0, 0.15)
	tw.tween_property(_confetti_back, "modulate:a", 0.0, 0.15)
	tw.tween_property(_confetti_front, "modulate:a", 0.0, 0.15)
	tw.chain().tween_callback(queue_free)

func _layout() -> void:
	var sz := get_viewport_rect().size
	if _backdrop:
		_backdrop.position = Vector2.ZERO
		_backdrop.size = sz
		_backdrop.queue_redraw()
	if _dialog:
		# On a short viewport scale the whole dialog down rather than letting it
		# run off the top and bottom edges.
		_fit = minf(1.0, (sz.y - 24.0) / maxf(1.0, _dialog.size.y))
		_dialog.pivot_offset = _dialog.size * 0.5
		_dialog.scale = Vector2.ONE * _fit
		_dialog.position = (sz - _dialog.size) * 0.5
