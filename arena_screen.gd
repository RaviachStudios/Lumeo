extends Control

# Arena hub: the player's active contests + entry points to create one or join by
# ID. Reads happen on open and on explicit refresh only (Firebase I/O is
# expensive — no background polling).

const ArenaUI := preload("res://arena_ui.gd")

var game_manager: Node

var _bg: ColorRect
var _back: Button
var _title: Label
var _caps_lbl: Label
var _create_btn: Button
var _join_btn: Button
var _refresh_btn: Button
var _list_panel: Panel
var _scroll: ScrollContainer
var _list: VBoxContainer
var _empty_lbl: Label
var _overlay: Panel
var _overlay_lbl: Label
var _toast: Label

# Join-by-ID modal.
var _join_modal: Panel
var _join_edit: LineEdit
var _join_msg: Label

var _counts: Dictionary = {"join": 0, "create": 0, "join_limit": 2, "create_limit": 1}
var _busy := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg = ArenaUI.make_bg()
	add_child(_bg)

	_back = ArenaUI.make_back_button()
	_back.pressed.connect(func() -> void: game_manager.show_home())
	add_child(_back)

	_title = ArenaUI.title("ARENA")
	add_child(_title)

	_caps_lbl = Label.new()
	_caps_lbl.add_theme_font_size_override("font_size", 16)
	_caps_lbl.add_theme_color_override("font_color", ArenaUI.MUTED)
	_caps_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caps_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_caps_lbl)

	_create_btn = ArenaUI.pill_button("＋  Create", ArenaUI.ACCENT, true)
	_create_btn.pressed.connect(_on_create)
	add_child(_create_btn)

	_join_btn = ArenaUI.pill_button("⮕  Join by ID", Color(0.40, 0.62, 1.0))
	_join_btn.pressed.connect(_open_join_modal)
	add_child(_join_btn)

	_refresh_btn = ArenaUI.pill_button("⟳", Color(0.55, 0.62, 0.85))
	_refresh_btn.add_theme_font_size_override("font_size", 22)
	_refresh_btn.pressed.connect(func() -> void: _refresh())
	add_child(_refresh_btn)

	_list_panel = ArenaUI.glass_panel()
	add_child(_list_panel)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 12)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)

	_empty_lbl = Label.new()
	_empty_lbl.text = "You're not in any contests yet.\nCreate one or join a friend's with their ID."
	_empty_lbl.add_theme_font_size_override("font_size", 18)
	_empty_lbl.add_theme_color_override("font_color", ArenaUI.MUTED)
	_empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_empty_lbl.visible = false
	add_child(_empty_lbl)

	_build_overlay()
	_build_toast()

	_layout()
	get_viewport().size_changed.connect(_layout)
	_refresh()

func _layout() -> void:
	var sz := get_viewport_rect().size
	ArenaUI.size_bg(_bg, sz)
	var cx := sz.x * 0.5
	if _back:
		_back.position = Vector2(20, 20)
	if _title:
		_title.size = Vector2(sz.x, 52)
		_title.position = Vector2(0, 22)
	if _caps_lbl:
		_caps_lbl.size = Vector2(sz.x, 22)
		_caps_lbl.position = Vector2(0, 76)

	# action row (create / join / refresh), centered
	var by := 112.0
	if _create_btn:
		_create_btn.size = Vector2(180, 50)
	if _join_btn:
		_join_btn.size = Vector2(200, 50)
	if _refresh_btn:
		_refresh_btn.size = Vector2(56, 50)
	var gap := 14.0
	var total := 180.0 + 200.0 + 56.0 + gap * 2.0
	var x := cx - total * 0.5
	if _create_btn:
		_create_btn.position = Vector2(x, by); x += 180.0 + gap
	if _join_btn:
		_join_btn.position = Vector2(x, by); x += 200.0 + gap
	if _refresh_btn:
		_refresh_btn.position = Vector2(x, by)

	# list panel fills the rest
	var top := 184.0
	var pw: float = minf(720.0, sz.x - 80.0)
	var px := cx - pw * 0.5
	var ph := sz.y - top - 30.0
	if _list_panel:
		_list_panel.position = Vector2(px, top)
		_list_panel.size = Vector2(pw, ph)
	if _scroll:
		_scroll.position = Vector2(px + 14, top + 14)
		_scroll.size = Vector2(pw - 28, ph - 28)
	if _list:
		_list.custom_minimum_size = Vector2(_scroll.size.x, 0)
	if _empty_lbl:
		_empty_lbl.position = Vector2(px, top + ph * 0.5 - 40)
		_empty_lbl.size = Vector2(pw, 80)
	if _overlay:
		_overlay.position = Vector2.ZERO
		_overlay.size = sz
	if _overlay_lbl:
		_overlay_lbl.size = Vector2(sz.x, 40)
		_overlay_lbl.position = Vector2(0, sz.y * 0.5 - 20)
	if _toast:
		_toast.size = Vector2(sz.x, 30)
		_toast.position = Vector2(0, sz.y - 96)
	_layout_join_modal(sz)

# ---------------- data ----------------

func _refresh() -> void:
	if _busy:
		return
	_busy = true
	_set_overlay(true, "Loading contests…")
	_counts = await ContestManager.get_my_counts()
	var contests := await ContestManager.load_my_contests()
	if not is_inside_tree():
		return
	_populate(contests)
	_update_caps()
	_set_overlay(false)
	_busy = false

func _update_caps() -> void:
	_caps_lbl.text = "Joined %d/%d   ·   Created %d/%d" % [
		int(_counts.get("join", 0)), int(_counts.get("join_limit", 2)),
		int(_counts.get("create", 0)), int(_counts.get("create_limit", 1))]
	var can_create: bool = int(_counts.get("create", 0)) < int(_counts.get("create_limit", 1))
	var can_join: bool = int(_counts.get("join", 0)) < int(_counts.get("join_limit", 2))
	if _create_btn:
		_create_btn.disabled = not can_create
	if _join_btn:
		_join_btn.disabled = not can_join

func _populate(contests: Array) -> void:
	for c in _list.get_children():
		c.queue_free()
	_empty_lbl.visible = contests.is_empty()
	for c: Dictionary in contests:
		_list.add_child(_make_row(c))

func _make_row(c: Dictionary) -> Control:
	var cid := String(c.get("id", ""))
	var status := String(c.get("status", "lobby"))
	var type := String(c.get("type", ""))
	var diff := String(c.get("difficulty", "easy"))

	var row := Button.new()
	row.custom_minimum_size = Vector2(0, 74)
	row.focus_mode = Control.FOCUS_NONE
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.10, 0.10, 0.20, 0.6)
	s.set_corner_radius_all(16)
	s.border_color = Color(ArenaUI.ACCENT.r, ArenaUI.ACCENT.g, ArenaUI.ACCENT.b, 0.35)
	s.set_border_width_all(1)
	row.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = Color(0.14, 0.14, 0.28, 0.75)
	row.add_theme_stylebox_override("hover", sh)
	var sp := s.duplicate() as StyleBoxFlat
	sp.bg_color = Color(0.08, 0.08, 0.16, 0.85)
	row.add_theme_stylebox_override("pressed", sp)
	row.pressed.connect(func() -> void: game_manager.show_contest_detail(cid))

	# Title line: "1 Hour · Moderate"  + ID
	var titlelbl := Label.new()
	titlelbl.text = "%s  ·  %s" % [ContestManager.type_label(type), ContestManager.diff_label(diff)]
	titlelbl.add_theme_font_size_override("font_size", 20)
	titlelbl.add_theme_color_override("font_color", ArenaUI.TEXT)
	titlelbl.position = Vector2(18, 10)
	titlelbl.size = Vector2(320, 26)
	titlelbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(titlelbl)

	var sub := Label.new()
	var sub_text := "ID %s   ·   %d player%s" % [cid, int(c.get("member_count", 1)),
		"" if int(c.get("member_count", 1)) == 1 else "s"]
	if bool(c.get("is_creator", false)):
		sub_text += "   ·   👑 You host"
	if status == "active":
		var tl := ArenaUI.time_left(int(c.get("deadline_at", 0)))
		if tl != "" and type != "one_game":
			sub_text += "   ·   " + tl
	sub.text = sub_text
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", ArenaUI.MUTED)
	sub.position = Vector2(18, 40)
	sub.size = Vector2(420, 22)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sub)

	# Status pill on the right. "YOUR TURN" overrides when the player still owes a
	# one_game play.
	var pill_txt := ArenaUI.status_text(status)
	var pill_acc := ArenaUI.status_accent(status)
	if status == "active" and type == "one_game" and not bool(c.get("my_done", false)):
		pill_txt = "YOUR TURN"
		pill_acc = Color(1.0, 0.72, 0.25)
	var pill := ArenaUI.status_pill(pill_txt, pill_acc, 118, 30)
	# Pin to the right-center of the row regardless of the row's dynamic width.
	pill.anchor_left = 1.0
	pill.anchor_right = 1.0
	pill.anchor_top = 0.5
	pill.anchor_bottom = 0.5
	pill.offset_left = -16.0 - 118.0
	pill.offset_right = -16.0
	pill.offset_top = -15.0
	pill.offset_bottom = 15.0
	row.add_child(pill)
	return row

# ---------------- create / join ----------------

func _on_create() -> void:
	if int(_counts.get("create", 0)) >= int(_counts.get("create_limit", 1)):
		_show_toast("You've reached your create limit (%d)." % int(_counts.get("create_limit", 1)))
		return
	game_manager.show_contest_create()

func _open_join_modal() -> void:
	if int(_counts.get("join", 0)) >= int(_counts.get("join_limit", 2)):
		_show_toast("You've reached your join limit (%d)." % int(_counts.get("join_limit", 2)))
		return
	if _join_modal == null:
		_build_join_modal()
	_join_edit.text = ""
	_join_msg.text = ""
	_join_modal.visible = true
	_join_edit.grab_focus()

func _do_join() -> void:
	var code := _join_edit.text.strip_edges().to_upper()
	if code.length() != ContestManager.ID_LEN:
		_join_msg.text = "Enter the %d-character contest ID." % ContestManager.ID_LEN
		return
	_join_msg.text = "Joining…"
	var res: Dictionary = await ContestManager.join_contest(code)
	if not is_inside_tree():
		return
	if bool(res.get("ok", false)):
		_join_modal.visible = false
		game_manager.show_contest_detail(code)
		return
	match String(res.get("error", "")):
		"not_found": _join_msg.text = "No contest found with that ID."
		"ended":     _join_msg.text = "That contest has already ended."
		"full":      _join_msg.text = "That contest is full."
		"at_join_limit": _join_msg.text = "You've reached your join limit."
		"auth":      _join_msg.text = "Sign in and pick a name first."
		_:           _join_msg.text = "Couldn't join. Try again."

# ---------------- overlay / toast / modal chrome ----------------

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

func _build_toast() -> void:
	_toast = Label.new()
	_toast.add_theme_font_size_override("font_size", 17)
	_toast.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.modulate.a = 0.0
	add_child(_toast)

func _show_toast(msg: String) -> void:
	_toast.text = msg
	_toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(2.0)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.6)

func _build_join_modal() -> void:
	_join_modal = Panel.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.05, 0.14, 0.98)
	s.set_corner_radius_all(20)
	s.border_color = Color(0.5, 0.6, 1.0, 0.7)
	s.set_border_width_all(2)
	s.shadow_color = Color(0.3, 0.4, 1.0, 0.4)
	s.shadow_size = 20
	_join_modal.add_theme_stylebox_override("panel", s)
	_join_modal.visible = false
	add_child(_join_modal)

	var title := Label.new()
	title.text = "Join a Contest"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 22)
	title.size = Vector2(400, 34)
	_join_modal.add_child(title)

	_join_edit = LineEdit.new()
	_join_edit.placeholder_text = "CONTEST ID"
	_join_edit.max_length = ContestManager.ID_LEN
	_join_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_join_edit.add_theme_font_size_override("font_size", 28)
	_join_edit.position = Vector2(50, 74)
	_join_edit.size = Vector2(300, 52)
	_join_edit.text_changed.connect(func(t: String) -> void:
		var up := t.to_upper()
		if up != t:
			_join_edit.text = up
			_join_edit.caret_column = up.length())
	_join_edit.text_submitted.connect(func(_t: String) -> void: _do_join())
	_join_modal.add_child(_join_edit)

	_join_msg = Label.new()
	_join_msg.add_theme_font_size_override("font_size", 15)
	_join_msg.add_theme_color_override("font_color", Color(1.0, 0.7, 0.6))
	_join_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_join_msg.position = Vector2(0, 134)
	_join_msg.size = Vector2(400, 22)
	_join_modal.add_child(_join_msg)

	var join := ArenaUI.pill_button("Join", ArenaUI.ACCENT, true)
	join.size = Vector2(150, 48)
	join.position = Vector2(210, 168)
	join.pressed.connect(_do_join)
	_join_modal.add_child(join)

	var cancel := ArenaUI.pill_button("Cancel", Color(0.6, 0.4, 0.4))
	cancel.size = Vector2(150, 48)
	cancel.position = Vector2(40, 168)
	cancel.pressed.connect(func() -> void: _join_modal.visible = false)
	_join_modal.add_child(cancel)
	_layout_join_modal(get_viewport_rect().size)

func _layout_join_modal(sz: Vector2) -> void:
	if _join_modal == null:
		return
	var w := 400.0
	var h := 236.0
	_join_modal.size = Vector2(w, h)
	_join_modal.position = Vector2(sz.x * 0.5 - w * 0.5, sz.y * 0.5 - h * 0.5)
