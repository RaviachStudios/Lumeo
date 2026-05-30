extends Control

var game_manager: Node

const BG_TOP := Color(0.04, 0.04, 0.18)
const BG_BOT := Color(0.08, 0.03, 0.25)
const GOLD := Color(1.0, 0.85, 0.2)
const PANEL := Color(0.12, 0.10, 0.28)
const PANEL_ME := Color(0.30, 0.22, 0.0, 0.55)
const TEXT_DIM := Color(0.7, 0.7, 1.0)
const DIFFS: Array[String] = ["easy", "moderate", "hard"]
const TIMEOUT_SEC := 12.0

var _tab_row: HBoxContainer
var _content: VBoxContainer
var _scroll: ScrollContainer
var _status: Label
var _overlay: Panel
var _overlay_msg: Label
var _overlay_retry: Button

var _current_diff := "easy"
var _data: Dictionary = {}   # diff -> { rows, my_rank, total }
var _loaded := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_shell()
	_load_all()

func _draw() -> void:
	var sz := get_viewport_rect().size
	for y in range(0, int(sz.y), 4):
		var t := float(y) / sz.y
		draw_line(Vector2(0, y), Vector2(sz.x, y), BG_TOP.lerp(BG_BOT, t), 4.0)

# ---------------- shell ----------------

func _build_shell() -> void:
	var sz := get_viewport_rect().size

	var title := Label.new()
	title.text = "ALL-TIME BEST"
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", GOLD)
	title.add_theme_color_override("font_shadow_color", Color(0,0,0,0.5))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 3)
	title.position = Vector2(sz.x * 0.5 - 260, 22)
	title.size = Vector2(520, 56)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	_add_btn("< Back", Vector2(24, 28), Vector2(120, 48), Color(0.25, 0.25, 0.55),
		func(): game_manager.show_home())

	_tab_row = HBoxContainer.new()
	_tab_row.add_theme_constant_override("separation", 10)
	_tab_row.position = Vector2(sz.x * 0.5 - 240, 92)
	_tab_row.size = Vector2(480, 52)
	add_child(_tab_row)
	_rebuild_tabs()

	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(sz.x * 0.5 - 320, 158)
	_scroll.size = Vector2(640, sz.y - 220)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 6)
	_content.custom_minimum_size = Vector2(640, 0)
	_scroll.add_child(_content)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 18)
	_status.add_theme_color_override("font_color", TEXT_DIM)
	_status.position = Vector2(sz.x * 0.5 - 300, sz.y - 52)
	_status.size = Vector2(600, 32)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_status)

	_build_overlay()

func _rebuild_tabs() -> void:
	for c in _tab_row.get_children():
		c.queue_free()
	for diff in DIFFS:
		var active: bool = (diff == _current_diff)
		var b := Button.new()
		b.text = diff.to_upper()
		b.custom_minimum_size = Vector2(150, 46)
		b.add_theme_font_size_override("font_size", 20)
		_style_btn(b, GOLD.darkened(0.05) if active else PANEL)
		if active:
			b.add_theme_color_override("font_color", Color(0.1, 0.08, 0.0))
		b.pressed.connect(func(): _on_tab(diff))
		_tab_row.add_child(b)

func _on_tab(diff: String) -> void:
	if diff == _current_diff: return
	_current_diff = diff
	_rebuild_tabs()
	if _loaded:
		_render(_data.get(diff, {}))

# ---------------- data load ----------------

func _load_all() -> void:
	_show_loading()
	var done := false
	get_tree().create_timer(TIMEOUT_SEC).timeout.connect(func():
		if not done: _show_error())
	var result: Dictionary = await LeaderboardManager.load_all_globals()
	done = true
	_data = result
	_loaded = true
	_hide_overlay()
	_render(_data.get(_current_diff, {}))

func _render(d: Dictionary) -> void:
	for c in _content.get_children():
		c.queue_free()

	var rows: Array = d.get("rows", [])
	if rows.is_empty():
		var empty := Label.new()
		empty.text = "No scores yet — be the first!"
		empty.add_theme_font_size_override("font_size", 20)
		empty.add_theme_color_override("font_color", TEXT_DIM)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.custom_minimum_size = Vector2(620, 0)
		_content.add_child(empty)
		_status.text = "Play a game to claim the top spot."
		return

	var rank := 1
	for row in rows:
		_score_row(rank, row.get("name", "Player"), int(row.get("score", 0)),
			bool(row.get("is_me", false)))
		rank += 1

	var my_rank := int(d.get("my_rank", 0))
	var total := int(d.get("total", 0))
	if my_rank == 0:
		_status.text = "You're not ranked here yet."
	elif my_rank > rows.size():
		_status.text = "Your rank: #%d of %d" % [my_rank, total]
	else:
		_status.text = "You're ranked #%d of %d" % [my_rank, total]

func _score_row(rank: int, name: String, score: int, is_me: bool) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(636, 50)
	var ps := StyleBoxFlat.new()
	ps.bg_color = PANEL_ME if is_me else PANEL
	if rank <= 3:
		ps.border_color = [GOLD, Color(0.75, 0.75, 0.8), Color(0.8, 0.5, 0.2)][rank - 1]
		ps.border_width_left = 4
	ps.corner_radius_top_left = 10
	ps.corner_radius_top_right = 10
	ps.corner_radius_bottom_left = 10
	ps.corner_radius_bottom_right = 10
	ps.content_margin_left = 14
	ps.content_margin_right = 14
	ps.content_margin_top = 8
	ps.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", ps)

	var row := HBoxContainer.new()
	panel.add_child(row)

	var rank_lbl := Label.new()
	rank_lbl.text = "#%d" % rank
	rank_lbl.add_theme_font_size_override("font_size", 22)
	rank_lbl.add_theme_color_override("font_color",
		GOLD if rank <= 3 else Color(0.7, 0.7, 0.9))
	rank_lbl.custom_minimum_size = Vector2(90, 0)
	row.add_child(rank_lbl)

	var name_lbl := Label.new()
	name_lbl.text = name + ("  (you)" if is_me else "")
	name_lbl.add_theme_font_size_override("font_size", 20)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(name_lbl)

	var score_lbl := Label.new()
	score_lbl.text = str(score)
	score_lbl.add_theme_font_size_override("font_size", 24)
	score_lbl.add_theme_color_override("font_color",
		GOLD if is_me else Color(0.9, 0.9, 1.0))
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_lbl.custom_minimum_size = Vector2(90, 0)
	row.add_child(score_lbl)

	_content.add_child(panel)

# ---------------- overlay ----------------

func _build_overlay() -> void:
	var sz := get_viewport_rect().size
	_overlay = Panel.new()
	_overlay.position = Vector2.ZERO
	_overlay.size = sz
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0.55)
	_overlay.add_theme_stylebox_override("panel", s)
	add_child(_overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)

	_overlay_msg = Label.new()
	_overlay_msg.add_theme_font_size_override("font_size", 24)
	_overlay_msg.add_theme_color_override("font_color", GOLD)
	_overlay_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_overlay_msg.custom_minimum_size = Vector2(520, 0)
	box.add_child(_overlay_msg)

	_overlay_retry = Button.new()
	_overlay_retry.text = "Try Again"
	_overlay_retry.custom_minimum_size = Vector2(220, 56)
	_overlay_retry.add_theme_font_size_override("font_size", 22)
	_style_btn(_overlay_retry, Color(0.25, 0.45, 0.65))
	_overlay_retry.pressed.connect(_load_all)
	box.add_child(_overlay_retry)

	_overlay.visible = false

func _show_loading() -> void:
	_overlay.visible = true
	_overlay_msg.text = "Loading leaderboards..."
	_overlay_retry.visible = false

func _show_error() -> void:
	_overlay.visible = true
	_overlay_msg.text = "Our servers are currently down.\nPlease try again soon."
	_overlay_retry.visible = true

func _hide_overlay() -> void:
	_overlay.visible = false

# ---------------- button helpers ----------------

func _add_btn(txt: String, pos: Vector2, sz: Vector2, col: Color, cb: Callable) -> void:
	var btn := Button.new()
	btn.text = txt
	btn.position = pos
	btn.size = sz
	btn.add_theme_font_size_override("font_size", 20)
	_style_btn(btn, col)
	btn.pressed.connect(cb)
	add_child(btn)

func _style_btn(btn: Button, col: Color) -> void:
	var sn := StyleBoxFlat.new()
	sn.bg_color = col
	sn.corner_radius_top_left = 12
	sn.corner_radius_top_right = 12
	sn.corner_radius_bottom_left = 12
	sn.corner_radius_bottom_right = 12
	sn.content_margin_left = 12
	sn.content_margin_right = 12
	btn.add_theme_stylebox_override("normal", sn)
	var sh := sn.duplicate() as StyleBoxFlat
	sh.bg_color = col.lightened(0.15)
	btn.add_theme_stylebox_override("hover", sh)
	var sp := sn.duplicate() as StyleBoxFlat
	sp.bg_color = col.darkened(0.15)
	btn.add_theme_stylebox_override("pressed", sp)
	btn.add_theme_color_override("font_color", Color.WHITE)
