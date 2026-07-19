extends Control

# Public Rooms Lobby — a full-screen table of up to 10 open (still-in-lobby),
# public rooms that anyone can join without a request. The 10 rooms are a random
# slice pulled with a SINGLE cheap read (see ContestManager.load_lobby_contests);
# "Reshuffle" just re-rolls that slice. Each row shows the room's title, difficulty
# and how many players are already registered, with a Join button.
#
# Reads happen on open and on explicit Reshuffle only (Firebase I/O is expensive —
# no background polling), matching the rest of the Arena screens.

const ArenaUI := preload("res://arena_ui.gd")

var game_manager: Node

var _bg: ColorRect
var _back: Button
var _title: Label
var _subtitle: Label

var _header: Control            # column captions above the table
var _scroll: ScrollContainer
var _list: VBoxContainer
var _empty_lbl: Label

var _reshuffle_btn: Button
var _count_lbl: Label

var _overlay: Panel
var _overlay_lbl: Label
var _toast: Label

var _rows: Array = []
var _busy := false

# Column band widths (from the right edge inward); the title column takes the rest.
const JOIN_W := 108.0
const REG_W := 96.0
const LEVEL_W := 92.0
const ROW_H := 58.0
const ROW_SEP := 8.0
const HEADER_H := 34.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The lobby wears the champions' antechamber (same as create / contest lobby).
	_bg = ArenaUI.make_lobby_bg()
	add_child(_bg)

	_back = ArenaUI.make_back_button()
	_back.pressed.connect(func() -> void: game_manager.show_arena())
	add_child(_back)

	_title = ArenaUI.title("PUBLIC CONTESTS")
	add_child(_title)

	_subtitle = Label.new()
	_subtitle.text = "Open rooms anyone can join — no invite needed"
	_subtitle.add_theme_font_size_override("font_size", 16)
	_subtitle.add_theme_color_override("font_color", Color(0.72, 0.76, 1.0))
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_subtitle)

	_header = Control.new()
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_header)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", int(ROW_SEP))
	_scroll.add_child(_list)

	_empty_lbl = Label.new()
	_empty_lbl.text = "No public contests are open right now.\nReshuffle, or create your own!"
	_empty_lbl.add_theme_font_size_override("font_size", 19)
	_empty_lbl.add_theme_color_override("font_color", ArenaUI.MUTED)
	_empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_empty_lbl.visible = false
	add_child(_empty_lbl)

	_count_lbl = Label.new()
	_count_lbl.add_theme_font_size_override("font_size", 15)
	_count_lbl.add_theme_color_override("font_color", ArenaUI.MUTED)
	_count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_count_lbl)

	_reshuffle_btn = ArenaUI.pill_button("↻  Reshuffle", ArenaUI.ACCENT, true)
	_reshuffle_btn.pressed.connect(_reload)
	add_child(_reshuffle_btn)

	_build_overlay()
	_build_toast()
	_layout()
	get_viewport().size_changed.connect(_layout)
	_reload()

# ---------------- layout ----------------

func _table_width(sz: Vector2) -> float:
	return clampf(sz.x - 48.0, 320.0, 900.0)

func _layout() -> void:
	var sz := get_viewport_rect().size
	ArenaUI.size_bg(_bg, sz)
	var cx := sz.x * 0.5
	if _back:
		_back.position = Vector2(20, 20)
	if _title:
		_title.size = Vector2(sz.x, 52); _title.position = Vector2(0, 22)
	if _subtitle:
		_subtitle.size = Vector2(sz.x, 24); _subtitle.position = Vector2(0, 78)

	var tw := _table_width(sz)
	var tx := cx - tw * 0.5
	var table_top := 128.0
	var bottom_reserve := 96.0
	if _header:
		_header.position = Vector2(tx, table_top)
		_header.size = Vector2(tw, HEADER_H)
		_header.queue_redraw()
		_relabel_header(tw)
	var list_top := table_top + HEADER_H + 6.0
	var list_h := sz.y - list_top - bottom_reserve
	if _scroll:
		_scroll.position = Vector2(tx, list_top)
		_scroll.size = Vector2(tw, maxf(list_h, 120.0))
	if _list:
		_list.custom_minimum_size = Vector2(tw, 0)
	# Re-flow row widths so columns line up with the header at the new width.
	if _list and not _list.get_children().is_empty():
		_render()
	if _empty_lbl:
		_empty_lbl.position = Vector2(tx, list_top)
		_empty_lbl.size = Vector2(tw, maxf(list_h, 120.0))

	var by := sz.y - 74.0
	if _reshuffle_btn:
		_reshuffle_btn.size = Vector2(220, 54)
		_reshuffle_btn.position = Vector2(cx - 110, by)
	if _count_lbl:
		_count_lbl.size = Vector2(sz.x, 20)
		_count_lbl.position = Vector2(0, by - 26.0)

	if _overlay:
		_overlay.position = Vector2.ZERO; _overlay.size = sz
	if _overlay_lbl:
		_overlay_lbl.size = Vector2(sz.x, 40); _overlay_lbl.position = Vector2(0, sz.y * 0.5 - 20)
	if _toast:
		_toast.size = Vector2(sz.x, 30); _toast.position = Vector2(0, sz.y - 40)

# The x-offsets of each right-aligned column band (title fills what's left).
func _columns(row_w: float) -> Dictionary:
	var join_x := row_w - JOIN_W - 12.0
	var reg_x := join_x - REG_W
	var level_x := reg_x - LEVEL_W
	return {"join": join_x, "reg": reg_x, "level": level_x,
		"title_x": 16.0, "title_w": maxf(60.0, level_x - 16.0 - 8.0)}

func _relabel_header(tw: float) -> void:
	for c in _header.get_children():
		c.queue_free()
	var cols := _columns(tw)
	_header_cap("ROOM", cols["title_x"], cols["title_w"], HORIZONTAL_ALIGNMENT_LEFT)
	_header_cap("LEVEL", cols["level"], LEVEL_W, HORIZONTAL_ALIGNMENT_CENTER)
	_header_cap("PLAYERS", cols["reg"], REG_W, HORIZONTAL_ALIGNMENT_CENTER)

func _header_cap(text: String, x: float, w: float, align: int) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", ArenaUI.GOLD.lightened(0.1))
	l.position = Vector2(x, 0); l.size = Vector2(w, HEADER_H)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.add_child(l)

# ---------------- data ----------------

func _reload() -> void:
	if _busy:
		return
	_busy = true
	_set_overlay(true, "Finding contests…")
	# Explicit type: 4.6 won't infer a `:=` through `await` across an autoload.
	var rows: Array = await ContestManager.load_lobby_contests()
	if not is_inside_tree():
		return
	_rows = rows
	_render()
	_set_overlay(false)
	_busy = false

func _render() -> void:
	for c in _list.get_children():
		c.queue_free()
	var has := not _rows.is_empty()
	# The table always shows LOBBY_FETCH rows: real rooms first, then empty
	# placeholders so the layout stays a full, even grid even when few (or no)
	# public contests are open.
	_empty_lbl.visible = false
	_scroll.visible = true
	if _count_lbl:
		_count_lbl.text = ("%d open %s" % [_rows.size(), "room" if _rows.size() == 1 else "rooms"]) if has else ""
	var tw := _table_width(get_viewport_rect().size)
	for row: Dictionary in _rows:
		_list.add_child(_make_row(row, tw))
	for _i in range(ContestManager.LOBBY_FETCH - _rows.size()):
		_list.add_child(_make_empty_row(tw))

func _make_row(c: Dictionary, row_w: float) -> Control:
	var cols := _columns(row_w)
	var mine: bool = bool(c.get("is_creator", false))
	var count := int(c.get("member_count", 1))
	var is_full := count >= ContestManager.MAX_MEMBERS

	var row := Panel.new()
	row.custom_minimum_size = Vector2(row_w, ROW_H)
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.16, 0.13, 0.05, 0.5) if mine else Color(0.06, 0.08, 0.18, 0.55)
	s.set_corner_radius_all(12)
	var rim := ArenaUI.GOLD if mine else Color(0.42, 0.47, 0.75)
	s.border_color = Color(rim.r, rim.g, rim.b, 0.7 if mine else 0.20)
	s.set_border_width_all(2 if mine else 1)
	row.add_theme_stylebox_override("panel", s)

	# Title (+ a small "YOURS" tag for a contest I host).
	var nm := Label.new()
	nm.text = ArenaUI.clamp_title(String(c.get("title", "Contest")))
	nm.add_theme_font_size_override("font_size", 20)
	nm.add_theme_color_override("font_color", ArenaUI.GOLD.lightened(0.3) if mine else Color(0.90, 0.93, 1.0))
	nm.position = Vector2(cols["title_x"], 0); nm.size = Vector2(cols["title_w"], ROW_H)
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.clip_text = true
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(nm)

	_cell(row, ContestManager.diff_label(String(c.get("difficulty", "easy"))), cols["level"], LEVEL_W,
		_diff_color(String(c.get("difficulty", "easy"))), 16)
	_cell(row, "%d / %d" % [count, ContestManager.MAX_MEMBERS], cols["reg"], REG_W,
		Color(0.72, 0.80, 0.98), 16)

	# Join / View / Full button.
	var btn: Button
	if mine:
		btn = ArenaUI.pill_button("Join", Color(0.30, 0.80, 0.52), true)
	elif is_full:
		btn = ArenaUI.pill_button("Full", Color(0.5, 0.5, 0.55))
		btn.disabled = true
	else:
		btn = ArenaUI.pill_button("Join", Color(0.30, 0.80, 0.52), true)
	btn.add_theme_font_size_override("font_size", 17)
	btn.size = Vector2(JOIN_W, 42)
	btn.position = Vector2(cols["join"], (ROW_H - 42) * 0.5)
	var cid := String(c.get("id", ""))
	# A full room I don't host is the only un-actionable case; my own is always viewable.
	if mine or not is_full:
		btn.pressed.connect(func() -> void: _on_join(cid))
	row.add_child(btn)
	return row

# A dim, empty placeholder row — keeps the table a full grid when there aren't
# LOBBY_FETCH real rooms to show. Non-interactive and content-free.
func _make_empty_row(row_w: float) -> Control:
	var row := Panel.new()
	row.custom_minimum_size = Vector2(row_w, ROW_H)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.08, 0.18, 0.22)
	s.set_corner_radius_all(12)
	s.border_color = Color(0.42, 0.47, 0.75, 0.10)
	s.set_border_width_all(1)
	row.add_theme_stylebox_override("panel", s)
	return row

func _cell(row: Control, text: String, x: float, w: float, col: Color, fs: int) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.position = Vector2(x, 0); l.size = Vector2(w, ROW_H)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)

func _diff_color(diff: String) -> Color:
	match diff:
		"easy":     return Color(0.40, 0.85, 0.55)
		"moderate": return Color(1.00, 0.75, 0.35)
		"hard":     return Color(0.97, 0.45, 0.52)
	return Color(0.82, 0.86, 1.0)

# ---------------- join ----------------

func _on_join(cid: String) -> void:
	if _busy or cid.is_empty():
		return
	_busy = true
	_set_overlay(true, "Joining…")
	var res: Dictionary = await ContestManager.join_contest(cid)
	if not is_inside_tree():
		return
	_set_overlay(false)
	_busy = false
	if bool(res.get("ok", false)):
		game_manager.show_contest_detail(cid)
		return
	match String(res.get("error", "")):
		"not_found":     _show_toast("That room just closed.")
		"ended":         _show_toast("That race has already started.")
		"full":          _show_toast("That room is full.")
		"auth":          _show_toast("Sign in and pick a name first.")
		_:               _show_toast("Couldn't join. Try again.")
	# On a fatal state (gone/full/ended) drop the stale row so the list stays honest.
	var err := String(res.get("error", ""))
	if err == "not_found" or err == "full" or err == "ended":
		_rows = _rows.filter(func(r): return String(r.get("id", "")) != cid)
		_render()

# ---------------- overlay / toast chrome ----------------

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
