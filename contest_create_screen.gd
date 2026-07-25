extends Control

# Create a room — a small interactive 2-step wizard:
#   1) Name your room       (the field lifts above the on-screen keyboard)
#   2) Choose a difficulty + who can join (Public / Private) → Create
# Every room is a single synchronous race, so there's no "format" to pick anymore.
# On success we jump straight to the room lobby where the ID is shared.
# Wears the same "champions' antechamber" theme as the public lobby.

const ArenaUI := preload("res://arena_ui.gd")

var game_manager: Node

var _bg: ColorRect
var _deco: Control                # radial light + framing pillars + floating gold motes
var _back: Button
var _title: Control               # carved-gold CREATE ROOM banner (built locally)

# Step containers (only one visible at a time).
var _step1: Control
var _step2: Control

# Step 1 (name).
var _name_edit: LineEdit
var _field_deco: Control         # gold-frame ornaments over the field (gems, inner shadow)
var _name_base_bottom := 0.0     # resting bottom edge of the field (no keyboard)
var _name_shift := 0.0
var _suggest_row: Control        # funny-name suggestion chips + a 🎲 reshuffle
var _sug_chips: Array[Button] = []
var _sug_dice: Button
var _sug_deco: Control           # per-chip top highlight + inner shadow ornaments
var _sug_spark: Control          # magical sparkle overlay orbiting the Shuffle chip

# Ambient animation clock (floating motes + shuffle sparkle).
var _anim_t := 0.0
var _motes: Array = []           # drifting golden particles in the deco layer

# Step 2 selections.
var _diff_pills: Array[Dictionary] = []
# Step 2 also picks visibility (public = listed in the browse-lobby / private = ID only).
var _vis_cards: Array[Dictionary] = []
var _selected_public := true

# Bottom navigation.
var _primary_btn: Button
var _cta_art: Control             # child layer painting the premium CTA (frame + panel + engraved text)
var _msg: Label
var _overlay: Panel
var _overlay_lbl: Label

var _step := 0
var _selected_diff := "easy"
var _busy := false

const STEP_COUNT := 2

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Match the public lobby's room (the champions' antechamber).
	_bg = ArenaUI.make_lobby_bg()
	add_child(_bg)

	# A quiet decorative layer above the arena backdrop but behind every control:
	# soft radial hearth-light pooled behind the content, twin stone pillars framing
	# the edges, and slow golden motes drifting up the room.
	_deco = Control.new()
	_deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deco.draw.connect(_draw_deco.bind(_deco))
	add_child(_deco)
	_seed_motes()

	_back = ArenaUI.make_back_button()
	# Top-left arrow doubles as the step-back control (the old bottom Back pill is gone):
	# on step 2 it returns to the name step; on step 1 it leaves to the arena.
	_back.pressed.connect(func() -> void:
		if _step > 0:
			_on_prev()
		else:
			game_manager.show_arena())
	# Touch app — kill the default gray hover tint; the arrow keeps its resting look
	# until actually pressed.
	_back.add_theme_stylebox_override("hover", _back.get_theme_stylebox("normal"))
	add_child(_back)

	_title = _make_title_banner("CREATE ROOM")
	add_child(_title)

	_step1 = _make_step()
	_step2 = _make_step()
	_build_step1()
	_build_step2()

	# Bottom nav — just the hero CTA (stepping back is handled by the top-left arrow).
	_primary_btn = _make_cta_button("Next  ▶")
	_primary_btn.pressed.connect(_on_primary)
	add_child(_primary_btn)

	_msg = Label.new()
	_msg.add_theme_font_size_override("font_size", 16)
	_msg.add_theme_color_override("font_color", Color(1.0, 0.7, 0.6))
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_msg)

	_build_overlay()
	_refresh_diff_styles()
	_refresh_vis_styles()
	_show_step()
	_layout()
	get_viewport().size_changed.connect(_layout)

func _make_step() -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	return c

# ---------------- step 1: name ----------------

func _build_step1() -> void:
	var prompt := Label.new()
	prompt.name = "prompt"
	prompt.text = "Name your room"
	prompt.add_theme_font_size_override("font_size", 34)
	prompt.add_theme_color_override("font_color", Color(1.0, 0.98, 0.94))
	prompt.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.12, 0.8))
	prompt.add_theme_constant_override("outline_size", 3)
	prompt.add_theme_color_override("font_shadow_color", Color(0.20, 0.40, 1.0, 0.4))
	prompt.add_theme_constant_override("shadow_offset_y", 3)
	prompt.add_theme_constant_override("shadow_outline_size", 9)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_step1.add_child(prompt)

	var sub := Label.new()
	sub.name = "sub"
	sub.text = "This is how it'll appear to everyone who joins"
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", Color(0.74, 0.78, 1.0, 0.92))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_step1.add_child(sub)

	# A premium fantasy text box: a thick gold frame around a dark-navy interior,
	# with a subtle placeholder and a warm gold bloom when focused. The recessed
	# inner shadow, top highlight and corner gemstones are drawn by _field_deco.
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "e.g. Friday Rumble"
	_name_edit.max_length = ContestManager.TITLE_MAX
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_edit.add_theme_font_size_override("font_size", 26)
	_name_edit.add_theme_color_override("font_color", Color(1.0, 0.92, 0.66))
	_name_edit.add_theme_color_override("font_placeholder_color", Color(0.58, 0.62, 0.82, 0.5))
	_name_edit.add_theme_color_override("caret_color", ArenaUI.GOLD)
	_name_edit.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.10, 0.6))
	_name_edit.add_theme_constant_override("outline_size", 2)
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.07, 0.17, 0.96)          # deep navy interior
	s.set_corner_radius_all(18)
	s.corner_detail = 8
	# richer metallic gold frame: warm face + a slightly cooler bevel-toned edge blend
	s.border_color = Color(1.0, 0.82, 0.40, 0.95)       # thick warm-gold frame
	s.set_border_width_all(3)
	# a whisper of ambient bloom even at rest — the frame reads as lit metal, not paint
	s.shadow_color = Color(ArenaUI.GOLD.r, ArenaUI.GOLD.g, ArenaUI.GOLD.b, 0.10)
	s.shadow_size = 6
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	_name_edit.add_theme_stylebox_override("normal", s)
	# focused: the bloom lifts to a soft premium halo (~40% softer than before —
	# alpha 0.42→0.25, size 16→11) rather than a hard yellow flare.
	var sf := s.duplicate() as StyleBoxFlat
	sf.border_color = ArenaUI.GOLD.lightened(0.16)
	sf.shadow_color = Color(ArenaUI.GOLD.r, ArenaUI.GOLD.g, ArenaUI.GOLD.b, 0.25)
	sf.shadow_size = 11
	_name_edit.add_theme_stylebox_override("focus", sf)
	_name_edit.text_submitted.connect(_on_name_submitted)
	_step1.add_child(_name_edit)

	# Frame ornaments over the field: top-edge highlight, recessed inner shadow, and
	# a tiny blue gemstone set into each side of the gold frame. Mouse-transparent so
	# taps still reach the field beneath.
	_field_deco = Control.new()
	_field_deco.name = "field_deco"
	_field_deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_field_deco.draw.connect(_draw_field_deco.bind(_field_deco))
	_step1.add_child(_field_deco)

	# Funny-name suggestions: a hint, a row of tappable name chips, and a 🎲 that
	# reshuffles them. Sits under the field but lifts with the field on keyboard open.
	var hint := Label.new()
	hint.name = "sug_hint"
	hint.text = "Out of ideas? Tap one — or Shuffle for more:"
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color(0.72, 0.76, 1.0))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_step1.add_child(hint)

	_suggest_row = Control.new()
	_suggest_row.name = "sug_row"
	_suggest_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_step1.add_child(_suggest_row)
	_reshuffle_suggestions()

# An elegant outlined fantasy chip: a dark interior with a thin gold border. Tapping
# it fills the name field. `bright` makes the Shuffle chip stand apart — a brighter,
# thicker gold rim with a soft glow.
func _make_suggest_chip(text: String, bright := false) -> Button:
	var gold := ArenaUI.GOLD
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.08, 0.7))
	b.add_theme_constant_override("outline_size", 2)
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.07, 0.16, 0.86)          # dark navy interior
	s.set_corner_radius_all(16)
	s.corner_detail = 6
	# richer gold rim; ordinary chips lift from 0.5→0.62 for a cleaner metallic edge
	s.border_color = Color(gold.r, gold.g, gold.b, 0.95 if bright else 0.62)
	s.set_border_width_all(2 if bright else 1)
	s.content_margin_left = 15
	s.content_margin_right = 15
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	if bright:
		s.shadow_color = Color(gold.r, gold.g, gold.b, 0.32)
		s.shadow_size = 9
	else:
		# a soft downward contact shadow so plain chips sit on the surface, not float
		s.shadow_color = Color(0.0, 0.0, 0.0, 0.28)
		s.shadow_size = 4
		s.shadow_offset = Vector2(0, 2)
	b.add_theme_stylebox_override("normal", s)
	# No hover state (touch app) — hover matches the resting look; only a tap lights it up.
	b.add_theme_stylebox_override("hover", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = Color(gold.r, gold.g, gold.b, 0.20)
	sh.border_color = Color(gold.r, gold.g, gold.b, 1.0 if bright else 0.78)
	b.add_theme_stylebox_override("pressed", sh)
	b.add_theme_color_override("font_color", gold.lightened(0.45 if bright else 0.3))
	return b

# Repopulate the suggestion row with 3 fresh random funny names + a 🎲 chip.
func _reshuffle_suggestions() -> void:
	if _suggest_row == null:
		return
	for c in _suggest_row.get_children():
		c.queue_free()
	_sug_chips.clear()
	var pool: Array = ContestManager.FUNNY_NAMES.duplicate()
	pool.shuffle()
	for i in mini(3, pool.size()):
		var name_txt := String(pool[i])
		var chip := _make_suggest_chip(name_txt)
		chip.pressed.connect(func() -> void: _apply_suggestion(name_txt))
		_suggest_row.add_child(chip)
		_sug_chips.append(chip)
	_sug_dice = _make_suggest_chip("↻ Shuffle", true)
	_sug_dice.pressed.connect(_reshuffle_suggestions)
	_suggest_row.add_child(_sug_dice)
	# Material ornaments over every chip: a thin top-edge highlight + a recessed inner
	# shadow, so each chip reads as tooled metal rather than a flat rectangle.
	_sug_deco = Control.new()
	_sug_deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sug_deco.draw.connect(_draw_sug_deco)
	_suggest_row.add_child(_sug_deco)
	# Magical sparkle overlay orbiting the Shuffle chip (drawn on top, animated).
	_sug_spark = Control.new()
	_sug_spark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sug_spark.draw.connect(_draw_shuffle_sparkle)
	_suggest_row.add_child(_sug_spark)
	_position_suggestions()

# Fill the field with a chosen suggestion (and keep the keyboard where it is).
func _apply_suggestion(name_txt: String) -> void:
	if _name_edit:
		_name_edit.text = name_txt

# Center the suggestion chips + dice within the row (widths come from their content).
func _position_suggestions() -> void:
	if _suggest_row == null or _sug_chips.is_empty():
		return
	var gap := 10.0
	var total := 0.0
	var widths: Array[float] = []
	for chip in _sug_chips:
		var cw: float = chip.get_minimum_size().x
		widths.append(cw)
		total += cw
	var dice_w: float = _sug_dice.get_minimum_size().x if _sug_dice else 0.0
	total += dice_w + gap * float(_sug_chips.size())
	var x := (_suggest_row.size.x - total) * 0.5
	var h := 34.0
	for i in _sug_chips.size():
		var chip := _sug_chips[i]
		chip.position = Vector2(x, 0)
		chip.size = Vector2(widths[i], h)
		x += widths[i] + gap
	if _sug_dice:
		_sug_dice.position = Vector2(x, 0)
		_sug_dice.size = Vector2(dice_w, h)
	if _sug_deco:
		_sug_deco.position = Vector2.ZERO
		_sug_deco.size = _suggest_row.size
		_sug_deco.queue_redraw()
	if _sug_spark:
		_sug_spark.position = Vector2.ZERO
		_sug_spark.size = _suggest_row.size
		_sug_spark.queue_redraw()

# ---------------- step 2: difficulty + visibility ----------------

const DIFF_ORDER: Array[String] = ["easy", "moderate", "hard"]
const DIFF_ACCENT := {
	"easy": Color(0.28, 0.82, 0.45),
	"moderate": Color(1.00, 0.72, 0.25),
	"hard": Color(0.95, 0.32, 0.40),
}

func _build_step2() -> void:
	var cap := _section_caption("Choose a difficulty")
	cap.name = "cap"
	_step2.add_child(cap)

	for diff in DIFF_ORDER:
		var accent: Color = DIFF_ACCENT[diff]
		# A sculpted 3D pill (same material approach as the CTA): the Button is invisible
		# and only supplies the tap target + press state; the child "art" paints the bevel,
		# gradient, rim light and engraved label. No hover state — this is a touch app.
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.clip_contents = false
		var empty := StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			btn.add_theme_stylebox_override(st, empty)
		_step2.add_child(btn)

		var art := Control.new()
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.clip_contents = false
		art.set_meta("accent", accent)
		art.set_meta("label", ContestManager.diff_label(diff))
		art.set_meta("selected", diff == _selected_diff)
		art.set_meta("pressed", false)
		art.draw.connect(_draw_diff_pill.bind(art))
		art.resized.connect(art.queue_redraw)
		btn.add_child(art)

		# Physical press: the face sinks toward its shadow, then springs back on release.
		btn.button_down.connect(func() -> void:
			art.set_meta("pressed", true); art.queue_redraw())
		btn.button_up.connect(func() -> void:
			art.set_meta("pressed", false); art.queue_redraw())
		btn.pressed.connect(func() -> void:
			_selected_diff = diff
			_refresh_diff_styles())
		_diff_pills.append({"btn": btn, "diff": diff, "art": art, "accent": accent})

	# Visibility picker (public listed in the browse-lobby / private = ID only).
	var vcap := _section_caption("Who can join?")
	vcap.name = "vcap"
	_step2.add_child(vcap)
	var vis_opts := [
		{"public": true, "title": "Public", "desc": "Listed in the lobby —\nanyone can find & join"},
		{"public": false, "title": "Private", "desc": "Hidden — only people\nwith the ID can join"},
	]
	for opt in vis_opts:
		var is_pub: bool = opt["public"]
		var accent: Color = ArenaUI.ACCENT if is_pub else ArenaUI.SAND
		# Same sculpted-3D recipe as the difficulty pills: the Button is invisible and only
		# supplies the tap target + press state; the child "art" paints the bevel, gradient,
		# rim light, emblem and engraved title/description.
		var card := Button.new()
		card.focus_mode = Control.FOCUS_NONE
		card.clip_contents = false
		var empty := StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			card.add_theme_stylebox_override(st, empty)
		_step2.add_child(card)

		var art := Control.new()
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.clip_contents = false
		art.set_meta("accent", accent)
		art.set_meta("title", String(opt["title"]))
		art.set_meta("desc", String(opt["desc"]))
		art.set_meta("public", is_pub)
		art.set_meta("selected", is_pub == _selected_public)
		art.set_meta("pressed", false)
		art.draw.connect(_draw_vis_card.bind(art))
		art.resized.connect(art.queue_redraw)
		card.add_child(art)

		# Physical press: the face sinks toward its shadow, then springs back on release.
		card.button_down.connect(func() -> void:
			art.set_meta("pressed", true); art.queue_redraw())
		card.button_up.connect(func() -> void:
			art.set_meta("pressed", false); art.queue_redraw())
		card.pressed.connect(func() -> void:
			_selected_public = is_pub
			_refresh_vis_styles())
		_vis_cards.append({"btn": card, "public": is_pub, "art": art, "accent": accent})

func _refresh_vis_styles() -> void:
	for d in _vis_cards:
		var art: Control = d["art"]
		art.set_meta("selected", bool(d["public"]) == _selected_public)
		art.queue_redraw()

# A sculpted 3D visibility card, painted per-vertex to match the difficulty pills. Unselected
# reads as a dark bevelled tablet with a faint accent rim; selected lifts into a glossy
# accent-coloured cap with a hugging bloom, bright top specular and a convex sheen. A small
# forged emblem (a globe for Public, a padlock for Private) sits above the engraved title +
# description. Held → the whole face sinks 3px.
func _draw_vis_card(c: Control) -> void:
	var w := c.size.x
	var h := c.size.y
	if w <= 2.0 or h <= 2.0:
		return
	var accent: Color = c.get_meta("accent", Color.WHITE)
	var selected: bool = bool(c.get_meta("selected", false))
	var pressed: bool = bool(c.get_meta("pressed", false))
	var is_pub: bool = bool(c.get_meta("public", true))
	var dy := 3.0 if pressed else 0.0
	var R := 18.0

	# ---- soft contact shadow anchoring the card (stays put as the face sinks) ----
	for i in range(5):
		var t := float(i) / 5.0
		var sw: float = w - 26.0 + t * 30.0
		var sy: float = h - 6.0 + t * 5.0
		var srect := Rect2((w - sw) * 0.5, sy, sw, 13.0)
		var sa: float = (0.26 * (1.0 - t)) * (0.5 if pressed else 1.0)
		c.draw_colored_polygon(_rr_points(srect, 7.0), Color(0.0, 0.0, 0.02, sa))

	var body := Rect2(1.0, 1.0 + dy, w - 2.0, h - 5.0)
	var body_pts := _rr_points(body, R)

	# ---- selected: a tight accent bloom hugging the card ----
	if selected:
		for i in range(5):
			var g: float = 1.0 + i * 2.4
			var bpts := _rr_points(body.grow(g), R + g)
			bpts.append(bpts[0])
			c.draw_polyline(bpts, Color(accent.r, accent.g, accent.b, 0.16 * (1.0 - float(i) / 5.0)),
				3.0, true)

	# ---- bevelled body: a vertical gradient reads as a lit convex cap ----
	var top_col: Color
	var bot_col: Color
	if selected:
		top_col = accent.lightened(0.34)
		bot_col = accent.darkened(0.40)
	else:
		top_col = Color(0.15, 0.17, 0.30).lerp(accent, 0.14)
		bot_col = Color(0.05, 0.06, 0.14).lerp(accent, 0.07)
	_fill_grad_v(c, body_pts, body.position.y, body.position.y + body.size.y, top_col, bot_col)

	# ---- rim: a bright bevel edge tracing the card ----
	var rim: Color = accent.lightened(0.5) if selected else accent.lightened(0.15)
	var rim_pts := _rr_points(body, R)
	rim_pts.append(rim_pts[0])
	c.draw_polyline(rim_pts, Color(rim.r, rim.g, rim.b, 0.6 if selected else 0.30), 2.0, true)

	# ---- specular highlight riding the top edge + a darker shade line along the base ----
	c.draw_line(Vector2(R * 0.8, body.position.y + 2.8), Vector2(w - R * 0.8, body.position.y + 2.8),
		Color(1.0, 1.0, 1.0, 0.5 if selected else 0.18), 1.6, true)
	c.draw_line(Vector2(R, body.position.y + body.size.y - 2.4),
		Vector2(w - R, body.position.y + body.size.y - 2.4), Color(0.0, 0.0, 0.02, 0.36), 1.6, true)

	# ---- convex sheen pooled in the upper third so the surface bulges gently ----
	var sheen_ctr := Vector2(w * 0.5, body.position.y + body.size.y * 0.28)
	c.draw_set_transform(sheen_ctr, 0.0, Vector2(1.0, 0.42))
	for i in range(5):
		var t := float(i) / 5.0
		c.draw_circle(Vector2.ZERO, lerpf(body.size.y * 0.12, body.size.x * 0.40, t),
			Color(1.0, 1.0, 1.0, (0.10 if selected else 0.045) * (1.0 - t)))
	c.draw_set_transform_matrix(Transform2D.IDENTITY)

	# ---- forged emblem (globe / padlock) sitting above the title ----
	# On the bright gold selected face a white emblem washes out, so we stamp it in deep
	# engraved bronze with a light lower emboss; unselected keeps a bright accent tint.
	var emb_col: Color = Color(0.30, 0.17, 0.03) if selected else accent.lightened(0.28)
	var emb_edge: Color = Color(1.0, 0.97, 0.86, 0.55) if selected else Color(0.0, 0.0, 0.02, 0.5)
	_draw_vis_emblem(c, is_pub, Vector2(w * 0.5, body.position.y + 26.0), emb_col, emb_edge, selected)

	# ---- engraved title ----
	var font := ThemeDB.fallback_font
	var tfs := 22
	var title := String(c.get_meta("title", ""))
	var tw2 := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, tfs).x
	var title_y := body.position.y + 63.0
	var tbase := Vector2((w - tw2) * 0.5, title_y)
	# Deep-bronze engrave on the gold face (matches the emblem); bright accent when unselected.
	var title_col: Color = Color(0.26, 0.14, 0.02) if selected else accent.lightened(0.30)
	var title_hi: Color = Color(1.0, 0.98, 0.88, 0.55) if selected else Color(0.0, 0.0, 0.0, 0.38)
	c.draw_string_outline(font, tbase, title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, tfs, 5,
		(Color(1.0, 0.95, 0.80, 0.30) if selected else Color(0.0, 0.0, 0.02, 0.7)))
	c.draw_string(font, tbase + Vector2(0.0, 1.1), title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, tfs, title_hi)
	c.draw_string(font, tbase, title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, tfs, title_col)

	# ---- engraved description (2 short lines, centred) ----
	var dfs := 12
	var desc: String = String(c.get_meta("desc", ""))
	var desc_col: Color = Color(0.30, 0.17, 0.03, 0.94) if selected else Color(0.74, 0.78, 1.0, 0.88)
	var dy0 := title_y + 18.0
	for line in desc.split("\n"):
		var lw := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, dfs).x
		var lb := Vector2((w - lw) * 0.5, dy0 + font.get_ascent(dfs))
		c.draw_string_outline(font, lb, line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, dfs, 3,
			(Color(1.0, 0.96, 0.82, 0.28) if selected else Color(0.0, 0.0, 0.02, 0.55)))
		c.draw_string(font, lb, line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, dfs, desc_col)
		dy0 += 16.0

# A tiny forged pictograph for the visibility cards: an open globe (Public) or a padlock
# (Private), drawn from primitives so it reads as engraved metal in both states.
func _draw_vis_emblem(c: Control, is_pub: bool, ctr: Vector2, col: Color, edge: Color, _selected: bool) -> void:
	var shade := edge
	if is_pub:
		var r := 8.5
		c.draw_arc(ctr + Vector2(0, 1.0), r, 0.0, TAU, 28, shade, 2.6, true)
		c.draw_arc(ctr, r, 0.0, TAU, 28, col, 2.0, true)
		# meridian + two parallels for a globe read
		c.draw_line(ctr + Vector2(0, -r), ctr + Vector2(0, r), col, 1.6, true)
		c.draw_arc(ctr, r, -PI * 0.5, PI * 0.5, 16, col, 1.4, true)
		c.draw_line(ctr + Vector2(-r, 0), ctr + Vector2(r, 0), col, 1.4, true)
		c.draw_line(ctr + Vector2(-r * 0.86, -r * 0.5), ctr + Vector2(r * 0.86, -r * 0.5), col, 1.2, true)
		c.draw_line(ctr + Vector2(-r * 0.86, r * 0.5), ctr + Vector2(r * 0.86, r * 0.5), col, 1.2, true)
	else:
		# padlock: a rounded body with a shackle arc above
		var bw := 15.0
		var bh := 11.0
		var body := Rect2(ctr.x - bw * 0.5, ctr.y - 1.0, bw, bh)
		var body_shade := Rect2(body.position + Vector2(0, 1.4), body.size)
		c.draw_colored_polygon(_rr_points(body_shade, 3.0), shade)
		c.draw_colored_polygon(_rr_points(body, 3.0), col)
		# shackle
		var sh_ctr := Vector2(ctr.x, body.position.y)
		c.draw_arc(sh_ctr, 5.0, PI, TAU, 16, col, 2.2, true)
		c.draw_line(sh_ctr + Vector2(-5.0, 0), sh_ctr + Vector2(-5.0, -0.5), col, 2.2, true)
		c.draw_line(sh_ctr + Vector2(5.0, 0), sh_ctr + Vector2(5.0, -0.5), col, 2.2, true)
		# keyhole
		var kh := body.position + Vector2(bw * 0.5, bh * 0.5)
		c.draw_circle(kh, 1.8, shade)

func _refresh_diff_styles() -> void:
	for d in _diff_pills:
		var art: Control = d["art"]
		art.set_meta("selected", d["diff"] == _selected_diff)
		art.queue_redraw()

# A sculpted 3D difficulty pill painted per-vertex (no flat stylebox). Unselected reads as
# a dark bevelled tablet with a faint accent-tinted rim; selected lifts into a glossy,
# accent-coloured cap with a hugging bloom, a bright top specular and a convex sheen — so
# the chosen difficulty visibly pops off the panel. Held → the whole face sinks 3px.
func _draw_diff_pill(c: Control) -> void:
	var w := c.size.x
	var h := c.size.y
	if w <= 2.0 or h <= 2.0:
		return
	var accent: Color = c.get_meta("accent", Color.WHITE)
	var selected: bool = bool(c.get_meta("selected", false))
	var pressed: bool = bool(c.get_meta("pressed", false))
	var dy := 3.0 if pressed else 0.0
	var R: float = minf(h * 0.5, 28.0)

	# ---- soft contact shadow anchoring the pill to the panel (stays put as the face sinks) ----
	for i in range(5):
		var t := float(i) / 5.0
		var sw: float = w - 22.0 + t * 26.0
		var sy: float = h - 6.0 + t * 5.0
		var srect := Rect2((w - sw) * 0.5, sy, sw, 12.0)
		var sa: float = (0.26 * (1.0 - t)) * (0.5 if pressed else 1.0)
		c.draw_colored_polygon(_rr_points(srect, 6.0), Color(0.0, 0.0, 0.02, sa))

	var body := Rect2(1.0, 1.0 + dy, w - 2.0, h - 5.0)
	var body_pts := _rr_points(body, R)

	# ---- selected: a tight accent bloom hugging the pill ----
	if selected:
		for i in range(5):
			var g: float = 1.0 + i * 2.2
			var bpts := _rr_points(body.grow(g), R + g)
			bpts.append(bpts[0])
			c.draw_polyline(bpts, Color(accent.r, accent.g, accent.b, 0.16 * (1.0 - float(i) / 5.0)),
				3.0, true)

	# ---- bevelled body: a vertical gradient reads as a lit convex cap ----
	var top_col: Color
	var bot_col: Color
	if selected:
		top_col = accent.lightened(0.42)
		bot_col = accent.darkened(0.34)
	else:
		# deep navy tablet with just a whisper of the accent
		top_col = Color(0.15, 0.17, 0.30).lerp(accent, 0.16)
		bot_col = Color(0.05, 0.06, 0.14).lerp(accent, 0.08)
	_fill_grad_v(c, body_pts, body.position.y, body.position.y + body.size.y, top_col, bot_col)

	# ---- rim: a bright bevel edge tracing the pill ----
	var rim: Color = accent.lightened(0.5) if selected else accent.lightened(0.15)
	var rim_pts := _rr_points(body, R)
	rim_pts.append(rim_pts[0])
	c.draw_polyline(rim_pts, Color(rim.r, rim.g, rim.b, 0.6 if selected else 0.32), 2.0, true)

	# ---- specular highlight riding the top edge + a darker shade line along the base ----
	c.draw_line(Vector2(R * 0.8, body.position.y + 2.8), Vector2(w - R * 0.8, body.position.y + 2.8),
		Color(1.0, 1.0, 1.0, 0.5 if selected else 0.20), 1.6, true)
	c.draw_line(Vector2(R, body.position.y + body.size.y - 2.4),
		Vector2(w - R, body.position.y + body.size.y - 2.4), Color(0.0, 0.0, 0.02, 0.38), 1.6, true)

	# ---- convex sheen pooled in the upper third so the surface bulges gently ----
	var sheen_ctr := Vector2(w * 0.5, body.position.y + body.size.y * 0.32)
	c.draw_set_transform(sheen_ctr, 0.0, Vector2(1.0, 0.5))
	for i in range(5):
		var t := float(i) / 5.0
		c.draw_circle(Vector2.ZERO, lerpf(body.size.y * 0.14, body.size.x * 0.42, t),
			Color(1.0, 1.0, 1.0, (0.11 if selected else 0.05) * (1.0 - t)))
	c.draw_set_transform_matrix(Transform2D.IDENTITY)

	# ---- engraved label ----
	var font := ThemeDB.fallback_font
	var fs := 22
	var txt := String(c.get_meta("label", ""))
	var ts := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs)
	var base := Vector2((w - ts.x) * 0.5, (h - ts.y) * 0.5 + font.get_ascent(fs) + dy)
	var text_col: Color = Color(1.0, 1.0, 0.98) if selected else accent.lightened(0.28)
	c.draw_string_outline(font, base, txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, 5,
		Color(0.0, 0.0, 0.02, 0.7))
	c.draw_string(font, base + Vector2(0.0, 1.2), txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs,
		Color(0.0, 0.0, 0.0, 0.4))
	c.draw_string(font, base, txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, text_col)

func _section_caption(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 24)
	l.add_theme_color_override("font_color", ArenaUI.GOLD.lightened(0.1))
	l.add_theme_color_override("font_shadow_color", Color(0.20, 0.40, 1.0, 0.35))
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", 7)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# ---------------- step flow ----------------

func _show_step() -> void:
	_step1.visible = _step == 0
	_step2.visible = _step == 1
	_primary_btn.text = "Create Room" if _step == STEP_COUNT - 1 else "Next  ▶"
	if _cta_art:
		_cta_art.queue_redraw()
	_msg.text = ""
	if _step == 0 and _name_edit:
		_name_edit.grab_focus()
	else:
		if _name_edit:
			_name_edit.release_focus()

# Enter / "Done" on the name field advances to step 2 — it must NEVER create the
# room directly. Android's soft keyboard can emit a second text_submitted as focus
# is released during the step transition; without this guard that stray event would
# arrive with _step already at the final step and call _on_create(), creating the
# room before the player ever taps "Create Room".
func _on_name_submitted(_t: String) -> void:
	if _step == 0:
		_on_primary()

func _on_prev() -> void:
	if _step > 0:
		_step -= 1
		_show_step()

func _on_primary() -> void:
	if _step < STEP_COUNT - 1:
		_step += 1
		_show_step()
	else:
		_on_create()

# ---------------- layout ----------------

func _layout() -> void:
	var sz := get_viewport_rect().size
	ArenaUI.size_bg(_bg, sz)
	if _deco:
		_deco.position = Vector2.ZERO
		_deco.size = sz
		_deco.queue_redraw()
	var cx := sz.x * 0.5
	if _back:
		_back.position = Vector2(20, 20)
	if _title:
		_title.size = Vector2(sz.x, 66)
		_title.position = Vector2(0, 14)

	for c in [_step1, _step2]:
		c.position = Vector2.ZERO
		c.size = sz

	# Step 1 — centered name field.
	var name_w: float = minf(480.0, sz.x - 100.0)
	var field_y := sz.y * 0.42
	var prompt: Label = _step1.get_node("prompt")
	prompt.size = Vector2(sz.x, 44); prompt.position = Vector2(0, field_y - 116)
	var sub: Label = _step1.get_node("sub")
	sub.size = Vector2(sz.x, 24); sub.position = Vector2(0, field_y - 66)
	_name_edit.size = Vector2(name_w, 58)
	_name_edit.position = Vector2(cx - name_w * 0.5, field_y)
	_name_base_bottom = field_y + 58.0
	if _field_deco:
		_field_deco.position = _name_edit.position
		_field_deco.size = _name_edit.size
		_field_deco.queue_redraw()

	# Suggestions sit just below the field.
	var hint: Label = _step1.get_node("sug_hint")
	hint.size = Vector2(sz.x, 22); hint.position = Vector2(0, field_y + 82)
	if _suggest_row:
		_suggest_row.position = Vector2(cx - name_w * 0.5, field_y + 110)
		_suggest_row.size = Vector2(name_w, 34)
		_position_suggestions()

	var gap := 16.0

	# Step 2 — difficulty pills.
	var cap2: Label = _step2.get_node("cap")
	cap2.size = Vector2(sz.x, 30); cap2.position = Vector2(0, 150)
	var diff_top := 210.0
	var dw: float = clampf((sz.x - 100.0) / 3.0 - 16.0, 150.0, 190.0)
	var dh := 58.0
	var dtotal := dw * 3.0 + gap * 2.0
	var dx := cx - dtotal * 0.5
	for d in _diff_pills:
		(d["btn"] as Button).size = Vector2(dw, dh)
		(d["btn"] as Button).position = Vector2(dx, diff_top)
		dx += dw + gap

	# Step 2 — visibility cards, under the difficulty pills.
	var vcap: Label = _step2.get_node("vcap")
	var vis_top := diff_top + dh + 34.0
	vcap.size = Vector2(sz.x, 30); vcap.position = Vector2(0, vis_top)
	var vcard_top := vis_top + 44.0
	var vw: float = clampf((sz.x - 100.0) / 2.0 - 16.0, 170.0, 260.0)
	var vh := 122.0
	var vtotal := vw * 2.0 + gap
	var vx := cx - vtotal * 0.5
	for d in _vis_cards:
		var card: Button = d["btn"]
		card.size = Vector2(vw, vh)
		card.position = Vector2(vx, vcard_top)
		(d["art"] as Control).queue_redraw()
		vx += vw + gap

	# Bottom nav — the hero CTA, centered (stepping back lives on the top-left arrow).
	var nav_y := sz.y - 104.0
	_primary_btn.size = Vector2(318, 74)
	_primary_btn.position = Vector2(cx - 159, nav_y)
	_msg.size = Vector2(sz.x, 24)
	_msg.position = Vector2(0, nav_y + 78)

	if _overlay:
		_overlay.position = Vector2.ZERO
		_overlay.size = sz
	if _overlay_lbl:
		_overlay_lbl.size = Vector2(sz.x, 40)
		_overlay_lbl.position = Vector2(0, sz.y * 0.5 - 20)

# ---------------- keyboard lift (step 1) ----------------

const TOP_MARGIN := 96.0     # keep the field below the header while lifted

func _process(delta: float) -> void:
	# Ambient motion: drifting motes behind the content and the Shuffle sparkle.
	_anim_t += delta
	if _deco:
		_deco.queue_redraw()
	if _sug_spark and _step == 0 and _step1.visible:
		_sug_spark.queue_redraw()

	if _name_edit == null:
		return
	var target := 0.0
	var kb_h := float(DisplayServer.virtual_keyboard_get_height())
	if _step == 0 and kb_h > 0.0 and _name_edit.has_focus():
		var vsz := get_viewport_rect().size
		var win_h := float(get_window().size.y)
		var kb_design := kb_h * (vsz.y / maxf(win_h, 1.0))
		var keyboard_top := vsz.y - kb_design
		var overlap := _name_base_bottom - (keyboard_top - 16.0)
		var max_shift := maxf(_name_base_bottom - 56.0 - TOP_MARGIN, 0.0)
		target = clampf(overlap, 0.0, max_shift)
	_name_shift = lerpf(_name_shift, target, clampf(delta * 12.0, 0.0, 1.0))
	_step1.position.y = -_name_shift

# ---------------- create ----------------

func _on_create() -> void:
	if _busy:
		return
	_busy = true
	_msg.text = ""
	# Blank name? Give it a funny one (and show it) rather than a bland default.
	if _name_edit.text.strip_edges().is_empty():
		_name_edit.text = ContestManager.random_title()
	_set_overlay(true, "Creating…")
	var res: Dictionary = await ContestManager.create_contest(_selected_diff,
		_name_edit.text, _selected_public)
	if not is_inside_tree():
		return
	_set_overlay(false)
	_busy = false
	if bool(res.get("ok", false)):
		game_manager.show_contest_detail(String(res.get("id", "")))
		return
	match String(res.get("error", "")):
		"auth":         _msg.text = "Sign in and pick a name first."
		"in_room":      _msg.text = "You already have a room open."
		"id_collision": _msg.text = "Couldn't allocate an ID. Try again."
		_:              _msg.text = "Couldn't create the room. Try again."

func _build_overlay() -> void:
	_overlay = Panel.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.02, 0.02, 0.06, 0.72)
	_overlay.add_theme_stylebox_override("panel", s)
	_overlay.visible = false
	add_child(_overlay)
	_overlay_lbl = Label.new()
	_overlay_lbl.add_theme_font_size_override("font_size", 22)
	_overlay_lbl.add_theme_color_override("font_color", ArenaUI.TEXT)
	_overlay_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_overlay_lbl)

func _set_overlay(on: bool, msg: String = "") -> void:
	if _overlay:
		_overlay.visible = on
		_overlay_lbl.text = msg

# ================= premium presentation helpers =================

# ---- carved-gold title banner + gold divider ----

# A larger, premium "CREATE ROOM" wordmark: a sunken bronze shadow, a raised ivory
# highlight and a carved-gold face (the stacked layers read as a soft gold gradient),
# finished with a thin tapered gold divider + centre gem underneath.
func _make_title_banner(text: String) -> Control:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.clip_contents = false
	var up := text.to_upper()
	var fs := 46
	var sh := _title_layer(up, fs, Color(0.20, 0.09, 0.01, 0.95), 5, Color(0.10, 0.05, 0.0, 0.9))
	sh.position = Vector2(0, 3)
	root.add_child(sh)
	# a warm mid-gold under-layer beneath the highlight deepens the top-to-bottom
	# gradient so the face reads as polished gold rather than flat yellow
	var mid := _title_layer(up, fs, Color(0.86, 0.58, 0.16, 0.85), 0, Color(0, 0, 0, 0))
	mid.position = Vector2(0, 2)
	root.add_child(mid)
	var hi := _title_layer(up, fs, Color(1.0, 0.99, 0.86, 0.92), 0, Color(0, 0, 0, 0))
	hi.position = Vector2(0, -2)
	root.add_child(hi)
	var face := Label.new()
	face.text = up
	face.set_anchors_preset(Control.PRESET_FULL_RECT)
	face.add_theme_font_size_override("font_size", fs)
	face.add_theme_color_override("font_color", Color(1.0, 0.85, 0.44))
	face.add_theme_color_override("font_outline_color", Color(0.28, 0.15, 0.02, 0.95))
	face.add_theme_constant_override("outline_size", 5)
	face.add_theme_color_override("font_shadow_color", Color(1.0, 0.6, 0.2, 0.5))
	face.add_theme_constant_override("shadow_offset_y", 2)
	face.add_theme_constant_override("shadow_outline_size", 14)
	face.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	face.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(face)
	var div := Control.new()
	div.set_anchors_preset(Control.PRESET_FULL_RECT)
	div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	div.draw.connect(_draw_title_divider.bind(div, up, fs))
	root.add_child(div)
	return root

func _title_layer(text: String, fs: int, col: Color, outline: int, oc: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", oc)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _draw_title_divider(c: Control, up: String, fs: int) -> void:
	var f := ThemeDB.fallback_font
	var tw: float = f.get_string_size(up, HORIZONTAL_ALIGNMENT_CENTER, -1.0, fs).x
	var cx := c.size.x * 0.5
	var y := c.size.y * 0.5 + fs * 0.46 + 9.0
	var half: float = minf(tw * 0.52, 250.0)
	var gold := Color(1.0, 0.82, 0.36)
	var gold_hi := Color(1.0, 0.95, 0.72)
	# tapered rule fading out toward each tip, with a small gap either side of the gem
	for dir: float in [-1.0, 1.0]:
		var steps := 24
		for i in steps:
			var t0 := float(i) / steps
			var t1 := float(i + 1) / steps
			var x0 := cx + dir * (13.0 + t0 * half)
			var x1 := cx + dir * (13.0 + t1 * half)
			var a := (1.0 - t0) * 0.8
			c.draw_line(Vector2(x0, y), Vector2(x1, y), Color(gold.r, gold.g, gold.b, a), 2.2, true)
	# small elegant flanking ornaments — a tiny stud + a taper toward each tip — framing
	# the centre gem for a more finished, heraldic divider
	for dir: float in [-1.0, 1.0]:
		var ox := cx + dir * 13.0
		c.draw_circle(Vector2(ox, y), 1.7, Color(gold_hi.r, gold_hi.g, gold_hi.b, 0.85))
	# a soft glow pooled beneath the centre gem
	c.draw_circle(Vector2(cx, y), 9.0, Color(gold.r, gold.g, gold.b, 0.12))
	var r := 5.0
	var pts := PackedVector2Array([
		Vector2(cx, y - r), Vector2(cx + r, y), Vector2(cx, y + r), Vector2(cx - r, y)])
	c.draw_colored_polygon(pts, gold)
	c.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), gold_hi, 1.0, true)
	c.draw_circle(Vector2(cx - 1.2, y - 1.4), 1.2, Color(1, 1, 1, 0.85))

# ---- field frame ornaments (top highlight, inner shadow, corner gems) ----

func _draw_field_deco(c: Control) -> void:
	var w := c.size.x
	var h := c.size.y
	# a faint metallic sheen pooling in the upper interior — a soft reflected-light
	# gradient that gives the recessed navy face a lit, glassy read
	for i in range(7):
		var t := float(i) / 7.0
		var yy := 6.0 + t * (h * 0.42)
		var a := 0.05 * (1.0 - t)
		c.draw_line(Vector2(16.0, yy), Vector2(w - 16.0, yy), Color(0.55, 0.68, 1.0, a), 2.0, true)
	# recessed inner shadow fading down from the top interior
	for i in range(5):
		var yy := 4.0 + float(i) * 1.6
		var a := 0.20 * (1.0 - float(i) / 5.0)
		c.draw_line(Vector2(12.0, yy), Vector2(w - 12.0, yy), Color(0, 0, 0, a), 1.4)
	# a thin highlight across the top edge, just inside the gold frame
	c.draw_line(Vector2(15.0, 3.0), Vector2(w - 15.0, 3.0), Color(1.0, 0.97, 0.82, 0.5), 1.4, true)
	# blue gemstones set into the frame on each side, centred vertically
	_draw_gem(c, Vector2(2.0, h * 0.5))
	_draw_gem(c, Vector2(w - 2.0, h * 0.5))

func _draw_gem(c: Control, ctr: Vector2) -> void:
	var blue := Color(0.35, 0.62, 1.0)
	var blue_hi := Color(0.75, 0.90, 1.0)
	var r := 5.5
	c.draw_circle(ctr, r * 2.2, Color(blue.r, blue.g, blue.b, 0.16))
	c.draw_circle(ctr, r * 1.5, Color(blue.r, blue.g, blue.b, 0.16))
	var pts := PackedVector2Array([
		ctr + Vector2(0, -r), ctr + Vector2(r * 0.72, 0),
		ctr + Vector2(0, r), ctr + Vector2(-r * 0.72, 0)])
	c.draw_colored_polygon(pts, blue)
	c.draw_colored_polygon(PackedVector2Array([
		ctr + Vector2(0, -r), ctr + Vector2(r * 0.72, 0), ctr + Vector2(-r * 0.72, 0)]),
		Color(blue_hi.r, blue_hi.g, blue_hi.b, 0.7))
	c.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]),
		Color(0.9, 0.95, 1.0, 0.9), 1.0, true)
	c.draw_circle(ctr + Vector2(-1.0, -1.6), 1.0, Color(1, 1, 1, 0.9))

# ---- suggestion-chip material ornaments (top highlight + inner shadow) ----

func _draw_sug_deco() -> void:
	if _sug_deco == null:
		return
	var chips: Array = []
	chips.append_array(_sug_chips)
	if _sug_dice:
		chips.append(_sug_dice)
	for node in chips:
		var chip := node as Button
		if chip == null:
			continue
		var p := chip.position
		var w := chip.size.x
		var inset := 9.0
		# recessed inner shadow just under the top edge
		_sug_deco.draw_line(Vector2(p.x + inset, p.y + 4.0),
			Vector2(p.x + w - inset, p.y + 4.0), Color(0, 0, 0, 0.22), 1.4)
		# a soft warm highlight riding the very top edge, inside the gold rim
		var bright: bool = chip == _sug_dice
		_sug_deco.draw_line(Vector2(p.x + inset, p.y + 2.0),
			Vector2(p.x + w - inset, p.y + 2.0),
			Color(1.0, 0.96, 0.80, 0.42 if bright else 0.30), 1.4, true)

# ---- shuffle sparkle ----

func _draw_shuffle_sparkle() -> void:
	if _sug_dice == null or _sug_spark == null:
		return
	var r := Rect2(_sug_dice.position, _sug_dice.size)
	var ctr := r.position + r.size * 0.5
	var gold := Color(1.0, 0.9, 0.5)
	var count := 5
	for i in range(count):
		var fi := float(i)
		var tw := 0.5 + 0.5 * sin(_anim_t * 2.4 + fi * 1.7)
		var ang := fi / float(count) * TAU + _anim_t * 0.6
		var px := ctr.x + cos(ang) * (r.size.x * 0.5 + 8.0)
		var py := ctr.y + sin(ang) * (r.size.y * 0.5 + 5.0)
		_draw_star4c(_sug_spark, Vector2(px, py), 4.0 * tw, Color(gold.r, gold.g, gold.b, tw * 0.9))

func _draw_star4c(c: Control, ctr: Vector2, s: float, col: Color) -> void:
	if s <= 0.3:
		return
	c.draw_colored_polygon(PackedVector2Array([
		ctr + Vector2(0.0, -s), ctr + Vector2(s * 0.3, 0.0),
		ctr + Vector2(0.0, s), ctr + Vector2(-s * 0.3, 0.0)]), col)
	c.draw_colored_polygon(PackedVector2Array([
		ctr + Vector2(-s, 0.0), ctr + Vector2(0.0, s * 0.3),
		ctr + Vector2(s, 0.0), ctr + Vector2(0.0, -s * 0.3)]), col)
	c.draw_circle(ctr, s * 0.22, Color(1, 1, 1, col.a * 0.85))

# ---- premium primary (Next / Create) button ----

# A hand-crafted AAA call-to-action in the spirit of Supercell's buttons: a sculpted
# gold frame surrounds a slightly-convex warm-gold panel that sits recessed behind it,
# with an ambient-occlusion groove between them, engraved ivory-gold lettering, a tight
# bloom hugging the frame and a soft contact shadow anchoring it to the platform.
#
# The Button itself is invisible (transparent styleboxes, hidden text) and only supplies
# the tap target + press state; the child "art" Control paints every material detail so
# we control the bevel lighting, gradients and depth directly. It reads the button's
# `.text` so "Next  ▶" / "Create Room" both render engraved, arrow included.
func _make_cta_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.clip_contents = false
	b.add_theme_font_size_override("font_size", 27)
	b.add_theme_color_override("font_color", Color(0, 0, 0, 0))   # hide native text; art draws it
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, empty)
	var art := Control.new()
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.clip_contents = false
	art.draw.connect(_draw_cta.bind(art))
	art.resized.connect(art.queue_redraw)
	b.add_child(art)
	_cta_art = art
	# physical press: the whole face sinks toward its shadow, then springs back on release
	b.button_down.connect(func() -> void:
		art.set_meta("pressed", true); art.queue_redraw())
	b.button_up.connect(func() -> void:
		art.set_meta("pressed", false); art.queue_redraw())
	return b

# Trace a clockwise rounded-rectangle perimeter (used for gradient fills + outlines).
func _rr_points(rect: Rect2, r: float, seg := 6) -> PackedVector2Array:
	r = minf(r, minf(rect.size.x, rect.size.y) * 0.5)
	var pts := PackedVector2Array()
	var corners := [
		[rect.position + Vector2(rect.size.x - r, r), -PI * 0.5],            # top-right
		[rect.position + Vector2(rect.size.x - r, rect.size.y - r), 0.0],    # bottom-right
		[rect.position + Vector2(r, rect.size.y - r), PI * 0.5],             # bottom-left
		[rect.position + Vector2(r, r), PI],                                 # top-left
	]
	for cn in corners:
		var ctr: Vector2 = cn[0]
		var a0: float = cn[1]
		for i in seg + 1:
			var a: float = a0 + (float(i) / seg) * (PI * 0.5)
			pts.append(ctr + Vector2(cos(a), sin(a)) * r)
	return pts

# Fill a polygon with a smooth vertical (top→bottom) gradient via per-vertex colours.
func _fill_grad_v(c: Control, pts: PackedVector2Array, y0: float, y1: float, top: Color, bot: Color) -> void:
	var cols := PackedColorArray()
	var span: float = maxf(y1 - y0, 0.001)
	for p in pts:
		cols.append(top.lerp(bot, clampf((p.y - y0) / span, 0.0, 1.0)))
	c.draw_polygon(pts, cols)

func _draw_cta(c: Control) -> void:
	var w := c.size.x
	var h := c.size.y
	if w <= 2.0 or h <= 2.0:
		return
	var pressed: bool = bool(c.get_meta("pressed", false))
	var dy := 3.0 if pressed else 0.0        # the face sinks when held
	var R := 30.0                            # corner radius (rounder than before)
	var fw := 8.0                            # sculpted gold-frame thickness

	# ---- soft contact shadow, anchoring the button to the lit platform (stays put as
	# the face sinks into it — kills the "floating" read) ----
	for i in range(6):
		var t := float(i) / 6.0
		var sw: float = w - 26.0 + t * 30.0
		var sy: float = h - 7.0 + t * 6.0
		var srect := Rect2((w - sw) * 0.5, sy, sw, 15.0)
		var sa: float = (0.30 * (1.0 - t)) * (0.55 if pressed else 1.0)
		c.draw_colored_polygon(_rr_points(srect, 7.0), Color(0.0, 0.0, 0.02, sa))

	var frame := Rect2(1.0, 1.0 + dy, w - 2.0, h - 5.0)
	var frame_pts := _rr_points(frame, R)

	# ---- tight premium bloom hugging the frame: a few expanding outlines fading outward
	# make a snug warm aura (not the old big blurry glow) that the frame then paints over ----
	var bloom := Color(1.0, 0.82, 0.38)
	for i in range(5):
		var g: float = 1.0 + i * 2.3
		var bpts := _rr_points(frame.grow(g), R + g)
		bpts.append(bpts[0])
		c.draw_polyline(bpts, Color(bloom.r, bloom.g, bloom.b, 0.13 * (1.0 - float(i) / 5.0)), 3.0, true)

	# ---- sculpted gold frame: a bevelled vertical gradient reads as lit, polished metal ----
	_fill_grad_v(c, frame_pts, frame.position.y, frame.position.y + frame.size.y,
		Color(1.0, 0.93, 0.64), Color(0.42, 0.26, 0.05))
	# specular: a bright thin highlight riding the top edge + a soft second sheen beneath
	c.draw_line(Vector2(R * 0.7, frame.position.y + 2.6), Vector2(w - R * 0.7, frame.position.y + 2.6),
		Color(1.0, 0.99, 0.88, 0.7), 1.8, true)
	c.draw_line(Vector2(R, frame.position.y + 5.4), Vector2(w - R, frame.position.y + 5.4),
		Color(1.0, 0.94, 0.72, 0.28), 1.2, true)
	# a darker line skimming the bottom of the frame for weight
	c.draw_line(Vector2(R, frame.position.y + frame.size.y - 2.4),
		Vector2(w - R, frame.position.y + frame.size.y - 2.4), Color(0.26, 0.15, 0.02, 0.55), 1.6, true)

	# ---- ambient-occlusion groove: a dark ring set just outside the panel so the frame
	# clearly *surrounds* a recessed centre rather than being painted onto it ----
	var panel := frame.grow(-fw)
	var ao_pts := _rr_points(panel.grow(1.6), R - fw + 1.6)
	c.draw_colored_polygon(ao_pts, Color(0.20, 0.11, 0.01, 0.85))

	# ---- recessed centre panel: warm golden gradient, brighter up top, darker at the base ----
	var panel_pts := _rr_points(panel, R - fw)
	_fill_grad_v(c, panel_pts, panel.position.y, panel.position.y + panel.size.y,
		Color(1.0, 0.84, 0.45), Color(0.58, 0.34, 0.09))
	# convex rise: a soft light pooled in the upper third makes the surface bulge gently
	var sheen_ctr := Vector2(w * 0.5, panel.position.y + panel.size.y * 0.34)
	c.draw_set_transform(sheen_ctr, 0.0, Vector2(1.0, 0.46))
	for i in range(6):
		var t := float(i) / 6.0
		c.draw_circle(Vector2.ZERO, lerpf(panel.size.y * 0.16, panel.size.x * 0.46, t),
			Color(1.0, 0.93, 0.64, 0.11 * (1.0 - t)))
	c.draw_set_transform_matrix(Transform2D.IDENTITY)
	# a crisp bright band across the very top of the panel (upper-third highlight)
	c.draw_line(Vector2(panel.position.x + 14.0, panel.position.y + 3.5),
		Vector2(panel.end.x - 14.0, panel.position.y + 3.5), Color(1.0, 0.96, 0.80, 0.4), 2.0, true)

	# ---- small forged rivets set into the frame on each side (engraved craftsmanship) ----
	for sx in [fw + 1.0, w - fw - 1.0]:
		var rc := Vector2(sx, h * 0.5 + dy)
		c.draw_circle(rc, 3.4, Color(0.30, 0.18, 0.03))
		c.draw_circle(rc, 2.3, Color(1.0, 0.86, 0.44))
		c.draw_circle(rc - Vector2(0.5, 0.8), 0.9, Color(1.0, 0.99, 0.86, 0.9))

	# ---- engraved ivory-gold lettering (Next / Create Room, arrow included) ----
	var font := ThemeDB.fallback_font
	var fs := 27
	var txt := (c.get_parent() as Button).text
	var ts := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs)
	var base := Vector2((w - ts.x) * 0.5,
		(h - ts.y) * 0.5 + font.get_ascent(fs) + dy)
	# dark carved halo for depth + contrast on the golden panel
	c.draw_string_outline(font, base, txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, 6,
		Color(0.24, 0.12, 0.0, 0.92))
	# soft inner shadow just below, then the polished ivory-gold face, then a top bevel light
	c.draw_string(font, base + Vector2(0.0, 1.6), txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs,
		Color(0.50, 0.30, 0.06, 0.55))
	c.draw_string(font, base, txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, Color(1.0, 0.94, 0.76))
	c.draw_string(font, base + Vector2(0.0, -1.2), txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs,
		Color(1.0, 1.0, 0.94, 0.42))

# ---- background decoration: radial light, pillars, floating motes ----

func _seed_motes() -> void:
	_motes.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260719
	for i in range(22):
		_motes.append({
			"x": rng.randf(),
			"y": rng.randf(),
			# a touch slower overall so the drift stays calm and elegant
			"spd": rng.randf_range(0.008, 0.024),
			"amp": rng.randf_range(6.0, 20.0),
			"phase": rng.randf() * TAU,
			# a wider spread including finer dust — most are tiny, a few catch the light
			"r": rng.randf_range(0.8, 2.8),
		})

func _draw_deco(c: Control) -> void:
	var w := c.size.x
	var h := c.size.y
	# soft radial hearth-light pooled behind the content
	var warm := Color(1.0, 0.80, 0.40)
	var ctr := Vector2(w * 0.5, h * 0.42)
	for i in range(9):
		var t := float(i) / 9.0
		var rad: float = lerp(90.0, minf(w, h) * 0.62, t)
		var a := 0.05 * (1.0 - t) * (1.0 - t)
		c.draw_circle(ctr, rad, Color(warm.r, warm.g, warm.b, a))
	# a very soft circular arena-platform glow low on the screen, so the primary CTA
	# reads as resting on a lit magical floor rather than floating. Squashed into a
	# shallow ellipse and kept faint so it never competes with the button itself.
	var floor_ctr := Vector2(w * 0.5, h - 66.0)
	c.draw_set_transform(floor_ctr, 0.0, Vector2(1.0, 0.34))
	var floor_warm := Color(1.0, 0.82, 0.42)
	for i in range(9):
		var ft := float(i) / 9.0
		var frad: float = lerp(56.0, 250.0, ft)
		var fa := 0.075 * (1.0 - ft) * (1.0 - ft)
		c.draw_circle(Vector2.ZERO, frad, Color(floor_warm.r, floor_warm.g, floor_warm.b, fa))
	c.draw_set_transform_matrix(Transform2D.IDENTITY)
	# slow golden motes drifting up the room
	var gold := Color(1.0, 0.88, 0.5)
	for m in _motes:
		var spd := float(m["spd"])
		var amp := float(m["amp"])
		var phase := float(m["phase"])
		var yy: float = fposmod(float(m["y"]) - _anim_t * spd, 1.0)
		var xx: float = float(m["x"]) + sin(_anim_t * 0.5 + phase) * (amp / w)
		var pos := Vector2(xx * w, yy * h)
		var tw := 0.4 + 0.6 * (0.5 + 0.5 * sin(_anim_t * 1.5 + phase))
		var fade: float = clampf((1.0 - yy) * 2.0, 0.0, 1.0)
		var a := 0.32 * tw * fade
		var rr := float(m["r"])
		c.draw_circle(pos, rr * 1.9, Color(gold.r, gold.g, gold.b, a * 0.25))
		c.draw_circle(pos, rr, Color(gold.r, gold.g, gold.b, a))
