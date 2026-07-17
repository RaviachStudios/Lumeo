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
var _back: Button
var _title: Label
var _dots: Control

# Step containers (only one visible at a time).
var _step1: Control
var _step2: Control

# Step 1 (name).
var _name_edit: LineEdit
var _name_base_bottom := 0.0     # resting bottom edge of the field (no keyboard)
var _name_shift := 0.0
var _suggest_row: Control        # funny-name suggestion chips + a 🎲 reshuffle
var _sug_chips: Array[Button] = []
var _sug_dice: Button

# Step 2 selections.
var _diff_pills: Array[Dictionary] = []
# Step 2 also picks visibility (public = listed in the browse-lobby / private = ID only).
var _vis_cards: Array[Dictionary] = []
var _selected_public := true

# Bottom navigation.
var _prev_btn: Button
var _primary_btn: Button
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

	_back = ArenaUI.make_back_button()
	_back.pressed.connect(func() -> void: game_manager.show_arena())
	add_child(_back)

	_title = ArenaUI.title("CREATE ROOM")
	add_child(_title)

	_dots = Control.new()
	_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dots.draw.connect(_draw_dots)
	add_child(_dots)

	_step1 = _make_step()
	_step2 = _make_step()
	_build_step1()
	_build_step2()

	# Bottom nav.
	_prev_btn = ArenaUI.pill_button("◀  Back", ArenaUI.SAND)
	_prev_btn.pressed.connect(_on_prev)
	add_child(_prev_btn)
	_primary_btn = ArenaUI.pill_button("Next  ▶", ArenaUI.ACCENT, true)
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
	prompt.add_theme_font_size_override("font_size", 32)
	prompt.add_theme_color_override("font_color", Color.WHITE)
	prompt.add_theme_color_override("font_shadow_color", Color(0.20, 0.40, 1.0, 0.4))
	prompt.add_theme_constant_override("shadow_offset_y", 3)
	prompt.add_theme_constant_override("shadow_outline_size", 9)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_step1.add_child(prompt)

	var sub := Label.new()
	sub.name = "sub"
	sub.text = "This is how it'll appear to everyone who joins"
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", Color(0.72, 0.76, 1.0))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_step1.add_child(sub)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "e.g. Friday Rumble"
	_name_edit.max_length = ContestManager.TITLE_MAX
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_edit.add_theme_font_size_override("font_size", 26)
	_name_edit.add_theme_color_override("font_color", ArenaUI.GOLD.lightened(0.15))
	_name_edit.add_theme_color_override("caret_color", ArenaUI.GOLD)
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.09, 0.10, 0.22, 0.92)
	s.set_corner_radius_all(16)
	s.border_color = Color(0.55, 0.60, 0.95, 0.7)
	s.set_border_width_all(2)
	s.content_margin_left = 16
	s.content_margin_right = 16
	_name_edit.add_theme_stylebox_override("normal", s)
	var sf := s.duplicate() as StyleBoxFlat
	sf.border_color = ArenaUI.GOLD
	sf.shadow_color = Color(ArenaUI.GOLD.r, ArenaUI.GOLD.g, ArenaUI.GOLD.b, 0.25)
	sf.shadow_size = 8
	_name_edit.add_theme_stylebox_override("focus", sf)
	_name_edit.text_submitted.connect(func(_t: String) -> void: _on_primary())
	_step1.add_child(_name_edit)

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

# A small tappable suggestion pill. Tapping it fills the name field.
func _make_suggest_chip(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 15)
	var s := StyleBoxFlat.new()
	s.bg_color = Color(ArenaUI.GOLD.r, ArenaUI.GOLD.g, ArenaUI.GOLD.b, 0.14)
	s.set_corner_radius_all(15)
	s.border_color = Color(ArenaUI.GOLD.r, ArenaUI.GOLD.g, ArenaUI.GOLD.b, 0.55)
	s.set_border_width_all(1)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	b.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = Color(ArenaUI.GOLD.r, ArenaUI.GOLD.g, ArenaUI.GOLD.b, 0.26)
	b.add_theme_stylebox_override("hover", sh)
	b.add_theme_stylebox_override("pressed", sh)
	b.add_theme_color_override("font_color", ArenaUI.GOLD.lightened(0.35))
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
	_sug_dice = _make_suggest_chip("↻ Shuffle")
	_sug_dice.pressed.connect(_reshuffle_suggestions)
	_suggest_row.add_child(_sug_dice)
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
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		var sb_off := StyleBoxFlat.new()
		sb_off.bg_color = Color(0.08, 0.09, 0.20, 0.72)
		sb_off.set_corner_radius_all(24)
		sb_off.border_color = Color(accent.r, accent.g, accent.b, 0.35)
		sb_off.set_border_width_all(1)
		var sb_on := StyleBoxFlat.new()
		sb_on.bg_color = Color(accent.r, accent.g, accent.b, 0.2)
		sb_on.set_corner_radius_all(24)
		sb_on.border_color = Color(accent.r, accent.g, accent.b, 0.95)
		sb_on.set_border_width_all(2)
		sb_on.shadow_color = Color(accent.r, accent.g, accent.b, 0.4)
		sb_on.shadow_size = 12
		for st in ["normal", "hover", "pressed", "focus"]:
			btn.add_theme_stylebox_override(st, sb_off)
		_step2.add_child(btn)

		var lbl := Label.new()
		lbl.text = ContestManager.diff_label(diff)
		lbl.add_theme_font_size_override("font_size", 20)
		lbl.add_theme_color_override("font_color", accent)
		lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(lbl)

		btn.pressed.connect(func() -> void:
			_selected_diff = diff
			_refresh_diff_styles())
		_diff_pills.append({"btn": btn, "diff": diff, "sb_on": sb_on, "sb_off": sb_off,
			"lbl": lbl, "accent": accent})

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
		var card := Button.new()
		card.focus_mode = Control.FOCUS_NONE
		var sb_off := StyleBoxFlat.new()
		sb_off.bg_color = Color(0.09, 0.10, 0.22, 0.72)
		sb_off.set_corner_radius_all(18)
		sb_off.border_color = Color(accent.r, accent.g, accent.b, 0.32)
		sb_off.set_border_width_all(1)
		var sb_on := StyleBoxFlat.new()
		sb_on.bg_color = Color(accent.r, accent.g, accent.b, 0.20)
		sb_on.set_corner_radius_all(18)
		sb_on.border_color = Color(accent.r, accent.g, accent.b, 0.95)
		sb_on.set_border_width_all(2)
		sb_on.shadow_color = Color(accent.r, accent.g, accent.b, 0.4)
		sb_on.shadow_size = 12
		for st in ["normal", "hover", "pressed", "focus"]:
			card.add_theme_stylebox_override(st, sb_off)
		_step2.add_child(card)

		var title_lbl := Label.new()
		title_lbl.text = String(opt["title"])
		title_lbl.add_theme_font_size_override("font_size", 22)
		title_lbl.add_theme_color_override("font_color", Color.WHITE)
		title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(title_lbl)
		var desc_lbl := Label.new()
		desc_lbl.text = String(opt["desc"])
		desc_lbl.add_theme_font_size_override("font_size", 13)
		desc_lbl.add_theme_color_override("font_color", Color(0.72, 0.76, 1.0))
		desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(desc_lbl)

		card.pressed.connect(func() -> void:
			_selected_public = is_pub
			_refresh_vis_styles())
		_vis_cards.append({"btn": card, "public": is_pub, "sb_on": sb_on, "sb_off": sb_off,
			"title_lbl": title_lbl, "desc_lbl": desc_lbl, "accent": accent})

func _refresh_vis_styles() -> void:
	for d in _vis_cards:
		var on: bool = bool(d["public"]) == _selected_public
		var sb: StyleBoxFlat = d["sb_on"] if on else d["sb_off"]
		for st in ["normal", "hover", "pressed", "focus"]:
			(d["btn"] as Button).add_theme_stylebox_override(st, sb)
		var accent: Color = d["accent"]
		(d["title_lbl"] as Label).add_theme_color_override("font_color",
			accent.lightened(0.45) if on else Color.WHITE)

func _refresh_diff_styles() -> void:
	for d in _diff_pills:
		var on: bool = d["diff"] == _selected_diff
		var sb: StyleBoxFlat = d["sb_on"] if on else d["sb_off"]
		for st in ["normal", "hover", "pressed", "focus"]:
			(d["btn"] as Button).add_theme_stylebox_override(st, sb)
		var accent: Color = d["accent"]
		(d["lbl"] as Label).add_theme_color_override("font_color",
			accent.lightened(0.4) if on else Color(accent.r, accent.g, accent.b, 0.75))

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
	_prev_btn.visible = _step > 0
	_primary_btn.text = "Create Room" if _step == STEP_COUNT - 1 else "Next  ▶"
	_msg.text = ""
	_dots.queue_redraw()
	if _step == 0 and _name_edit:
		_name_edit.grab_focus()
	else:
		if _name_edit:
			_name_edit.release_focus()

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
	var cx := sz.x * 0.5
	if _back:
		_back.position = Vector2(20, 20)
	if _title:
		_title.size = Vector2(sz.x, 52)
		_title.position = Vector2(0, 22)
	if _dots:
		_dots.position = Vector2(cx - 90, 84)
		_dots.size = Vector2(180, 22)
		_dots.queue_redraw()

	for c in [_step1, _step2]:
		c.position = Vector2.ZERO
		c.size = sz

	# Step 1 — centered name field.
	var name_w: float = minf(460.0, sz.x - 100.0)
	var field_y := sz.y * 0.42
	var prompt: Label = _step1.get_node("prompt")
	prompt.size = Vector2(sz.x, 40); prompt.position = Vector2(0, field_y - 120)
	var sub: Label = _step1.get_node("sub")
	sub.size = Vector2(sz.x, 24); sub.position = Vector2(0, field_y - 70)
	_name_edit.size = Vector2(name_w, 56)
	_name_edit.position = Vector2(cx - name_w * 0.5, field_y)
	_name_base_bottom = field_y + 56.0

	# Suggestions sit just below the field.
	var hint: Label = _step1.get_node("sug_hint")
	hint.size = Vector2(sz.x, 22); hint.position = Vector2(0, field_y + 78)
	if _suggest_row:
		_suggest_row.position = Vector2(cx - name_w * 0.5, field_y + 106)
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
	var vh := 92.0
	var vtotal := vw * 2.0 + gap
	var vx := cx - vtotal * 0.5
	for d in _vis_cards:
		var card: Button = d["btn"]
		card.size = Vector2(vw, vh)
		card.position = Vector2(vx, vcard_top)
		var title_lbl: Label = d["title_lbl"]
		title_lbl.position = Vector2(0, 16); title_lbl.size = Vector2(vw, 28)
		var desc_lbl: Label = d["desc_lbl"]
		desc_lbl.position = Vector2(8, 48); desc_lbl.size = Vector2(vw - 16, 40)
		vx += vw + gap

	# Bottom nav — primary centered, step-back to its left.
	var nav_y := sz.y - 96.0
	_primary_btn.size = Vector2(260, 58)
	_primary_btn.position = Vector2(cx - 130, nav_y)
	_prev_btn.size = Vector2(150, 58)
	_prev_btn.position = Vector2(cx - 130 - 150 - 16, nav_y)
	_msg.size = Vector2(sz.x, 24)
	_msg.position = Vector2(0, nav_y + 64)

	if _overlay:
		_overlay.position = Vector2.ZERO
		_overlay.size = sz
	if _overlay_lbl:
		_overlay_lbl.size = Vector2(sz.x, 40)
		_overlay_lbl.position = Vector2(0, sz.y * 0.5 - 20)

func _draw_dots() -> void:
	var gap := 30.0
	var x := _dots.size.x * 0.5 - gap * 0.5
	var y := _dots.size.y * 0.5
	for i in STEP_COUNT:
		var on: bool = i == _step
		var done: bool = i < _step
		var col: Color = ArenaUI.GOLD if (on or done) else Color(0.5, 0.55, 0.8)
		_dots.draw_circle(Vector2(x + i * gap, y), 7.0 if on else 5.0,
			Color(col.r, col.g, col.b, 1.0 if on else (0.7 if done else 0.4)))

# ---------------- keyboard lift (step 1) ----------------

const TOP_MARGIN := 96.0     # keep the field below the header while lifted

func _process(delta: float) -> void:
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
