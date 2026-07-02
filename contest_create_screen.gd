extends Control

# Create a contest: pick a TYPE + a DIFFICULTY, then create. On success we jump
# straight to the contest detail (lobby) where the ID can be shared.

const ArenaUI := preload("res://arena_ui.gd")

var game_manager: Node

var _bg: ColorRect
var _back: Button
var _title: Label
var _type_cards: Array[Dictionary] = []   # {btn, def, sb_on, sb_off, name_lbl, rule_lbl}
var _diff_pills: Array[Dictionary] = []    # {btn, diff, sb_on, sb_off, lbl}
var _create_btn: Button
var _overlay: Panel
var _overlay_lbl: Label
var _msg: Label

var _selected_type := "one_game"
var _selected_diff := "easy"
var _busy := false

const TYPE_ORDER: Array[String] = ["one_game", "one_hour", "one_day", "daily"]

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg = ArenaUI.make_bg()
	add_child(_bg)

	_back = ArenaUI.make_back_button()
	_back.pressed.connect(func() -> void: game_manager.show_arena())
	add_child(_back)

	_title = ArenaUI.title("CREATE CONTEST")
	add_child(_title)

	_build_type_cards()
	_build_diff_pills()

	_create_btn = ArenaUI.pill_button("Create Contest", ArenaUI.ACCENT, true)
	_create_btn.pressed.connect(_on_create)
	add_child(_create_btn)

	_msg = Label.new()
	_msg.add_theme_font_size_override("font_size", 16)
	_msg.add_theme_color_override("font_color", Color(1.0, 0.7, 0.6))
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_msg)

	_build_overlay()
	_refresh_type_styles()
	_refresh_diff_styles()
	_layout()
	get_viewport().size_changed.connect(_layout)

# ---------------- type cards ----------------

func _build_type_cards() -> void:
	for t in TYPE_ORDER:
		var card := Button.new()
		card.focus_mode = Control.FOCUS_NONE
		var sb_off := StyleBoxFlat.new()
		sb_off.bg_color = Color(0.09, 0.09, 0.19, 0.7)
		sb_off.set_corner_radius_all(18)
		sb_off.border_color = Color(ArenaUI.ACCENT.r, ArenaUI.ACCENT.g, ArenaUI.ACCENT.b, 0.3)
		sb_off.set_border_width_all(1)
		var sb_on := StyleBoxFlat.new()
		sb_on.bg_color = Color(ArenaUI.ACCENT.r, ArenaUI.ACCENT.g, ArenaUI.ACCENT.b, 0.22)
		sb_on.set_corner_radius_all(18)
		sb_on.border_color = Color(ArenaUI.ACCENT.r, ArenaUI.ACCENT.g, ArenaUI.ACCENT.b, 0.95)
		sb_on.set_border_width_all(2)
		sb_on.shadow_color = Color(ArenaUI.ACCENT.r, ArenaUI.ACCENT.g, ArenaUI.ACCENT.b, 0.4)
		sb_on.shadow_size = 14
		for st in ["normal", "hover", "pressed", "focus"]:
			card.add_theme_stylebox_override(st, sb_off)
		add_child(card)

		var name_lbl := Label.new()
		name_lbl.text = ContestManager.type_label(t)
		name_lbl.add_theme_font_size_override("font_size", 24)
		name_lbl.add_theme_color_override("font_color", Color.WHITE)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(name_lbl)

		var rule_lbl := Label.new()
		rule_lbl.text = ContestManager.type_rule(t)
		rule_lbl.add_theme_font_size_override("font_size", 13)
		rule_lbl.add_theme_color_override("font_color", ArenaUI.MUTED)
		rule_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rule_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rule_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(rule_lbl)

		var def := {"btn": card, "type": t, "sb_on": sb_on, "sb_off": sb_off,
			"name_lbl": name_lbl, "rule_lbl": rule_lbl}
		card.pressed.connect(func() -> void:
			_selected_type = t
			_refresh_type_styles())
		_type_cards.append(def)

func _refresh_type_styles() -> void:
	for d in _type_cards:
		var on: bool = d["type"] == _selected_type
		var sb: StyleBoxFlat = d["sb_on"] if on else d["sb_off"]
		for st in ["normal", "hover", "pressed", "focus"]:
			(d["btn"] as Button).add_theme_stylebox_override(st, sb)
		(d["name_lbl"] as Label).add_theme_color_override("font_color",
			ArenaUI.ACCENT.lightened(0.45) if on else Color.WHITE)

# ---------------- difficulty pills ----------------

const DIFF_ORDER: Array[String] = ["easy", "moderate", "hard"]
const DIFF_ACCENT := {
	"easy": Color(0.28, 0.82, 0.45),
	"moderate": Color(1.00, 0.72, 0.25),
	"hard": Color(0.95, 0.32, 0.40),
}

func _build_diff_pills() -> void:
	for diff in DIFF_ORDER:
		var accent: Color = DIFF_ACCENT[diff]
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		var sb_off := StyleBoxFlat.new()
		sb_off.bg_color = Color(0.08, 0.09, 0.18, 0.7)
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
		add_child(btn)

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

func _refresh_diff_styles() -> void:
	for d in _diff_pills:
		var on: bool = d["diff"] == _selected_diff
		var sb: StyleBoxFlat = d["sb_on"] if on else d["sb_off"]
		for st in ["normal", "hover", "pressed", "focus"]:
			(d["btn"] as Button).add_theme_stylebox_override(st, sb)
		var accent: Color = d["accent"]
		(d["lbl"] as Label).add_theme_color_override("font_color",
			accent.lightened(0.4) if on else Color(accent.r, accent.g, accent.b, 0.75))

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

	# TYPE section: a label + a row of 4 cards.
	var cards_top := 108.0
	var card_w: float = minf(220.0, (sz.x - 120.0) / 4.0 - 16.0)
	var card_h := 150.0
	var gap := 16.0
	var total := card_w * 4.0 + gap * 3.0
	var x := cx - total * 0.5
	for d in _type_cards:
		var card: Button = d["btn"]
		card.size = Vector2(card_w, card_h)
		card.position = Vector2(x, cards_top)
		var name_lbl: Label = d["name_lbl"]
		name_lbl.position = Vector2(0, 22)
		name_lbl.size = Vector2(card_w, 30)
		var rule_lbl: Label = d["rule_lbl"]
		rule_lbl.position = Vector2(12, 62)
		rule_lbl.size = Vector2(card_w - 24, card_h - 74)
		x += card_w + gap

	# DIFFICULTY section
	var diff_top := cards_top + card_h + 54.0
	var dw := 180.0
	var dh := 56.0
	var dtotal := dw * 3.0 + gap * 2.0
	var dx := cx - dtotal * 0.5
	for d in _diff_pills:
		(d["btn"] as Button).size = Vector2(dw, dh)
		(d["btn"] as Button).position = Vector2(dx, diff_top)
		dx += dw + gap

	if _create_btn:
		_create_btn.size = Vector2(280, 58)
		_create_btn.position = Vector2(cx - 140, diff_top + dh + 54.0)
	if _msg:
		_msg.size = Vector2(sz.x, 24)
		_msg.position = Vector2(0, diff_top + dh + 120.0)
	if _overlay:
		_overlay.position = Vector2.ZERO
		_overlay.size = sz
	if _overlay_lbl:
		_overlay_lbl.size = Vector2(sz.x, 40)
		_overlay_lbl.position = Vector2(0, sz.y * 0.5 - 20)

# ---------------- create ----------------

func _on_create() -> void:
	if _busy:
		return
	_busy = true
	_msg.text = ""
	_set_overlay(true, "Creating…")
	var res: Dictionary = await ContestManager.create_contest(_selected_type, _selected_diff)
	if not is_inside_tree():
		return
	_set_overlay(false)
	_busy = false
	if bool(res.get("ok", false)):
		game_manager.show_contest_detail(String(res.get("id", "")))
		return
	match String(res.get("error", "")):
		"at_create_limit": _msg.text = "You can only create one contest at a time."
		"auth":            _msg.text = "Sign in and pick a name first."
		"id_collision":    _msg.text = "Couldn't allocate an ID. Try again."
		_:                 _msg.text = "Couldn't create the contest. Try again."

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
