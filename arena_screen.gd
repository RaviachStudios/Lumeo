extends Control

# Arena hub (THE COLOSSEUM): the entry point into live multiplayer. Two choices —
# CREATE a room, or JOIN one. Join then asks Private (enter the shared ID) or
# Public (browse the open-rooms lobby). Rooms are live and synchronous, so there's
# no persistent "my contests" list here anymore — you create/join and drop straight
# into the room.

const ArenaUI := preload("res://arena_ui.gd")
const ArenaFX := preload("res://arena_fx.gd")

var game_manager: Node

var _bg: ColorRect
var _fx: ArenaFX
var _back: Button
var _title: Label
var _subtitle: Label

# Primary actions.
var _create_btn: Button
var _join_btn: Button

var _toast: Label

# Join-choice modal (Private / Public).
var _choice_modal: Panel

# Join-by-ID modal (private).
var _id_modal: Panel
var _id_edit: LineEdit
var _id_msg: Label
var _id_modal_base_y := 0.0      # resting Y of the modal (no keyboard)
var _id_modal_shift := 0.0       # current upward lift so the field clears the keyboard

var _busy := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg = ArenaUI.make_bg("hub")
	add_child(_bg)

	# Ambient flourish (spotlights / confetti / winged Simon fly-by) behind the UI.
	_fx = ArenaFX.new()
	add_child(_fx)
	_fx.setup(get_viewport_rect().size)

	_back = ArenaUI.make_back_button()
	_back.pressed.connect(func() -> void: game_manager.show_home())
	add_child(_back)

	_title = ArenaUI.title("ARENA")
	add_child(_title)

	_subtitle = Label.new()
	_subtitle.text = "Race friends in a live Simon showdown"
	_subtitle.add_theme_font_size_override("font_size", 18)
	_subtitle.add_theme_color_override("font_color", ArenaUI.MUTED)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_subtitle)

	_create_btn = ArenaUI.pill_button("＋  Create a Room", ArenaUI.ACCENT, true)
	_create_btn.pressed.connect(_on_create)
	add_child(_create_btn)

	_join_btn = ArenaUI.pill_button("⮕  Join a Room", ArenaUI.SAND)
	_join_btn.pressed.connect(_on_join)
	add_child(_join_btn)

	_build_toast()

	_layout()
	get_viewport().size_changed.connect(_layout)

# ---------------- layout ----------------

func _layout() -> void:
	var sz := get_viewport_rect().size
	ArenaUI.size_bg(_bg, sz)
	if _fx:
		_fx.relayout(sz)
	var cx := sz.x * 0.5
	if _back:
		_back.position = Vector2(20, 20)
	if _title:
		_title.size = Vector2(sz.x, 52)
		_title.position = Vector2(0, 60)
	if _subtitle:
		_subtitle.size = Vector2(sz.x, 26)
		_subtitle.position = Vector2(0, 120)

	# Two stacked action buttons, centered.
	var bw: float = minf(360.0, sz.x - 120.0)
	var bh := 72.0
	var gap := 26.0
	var group_h := bh * 2 + gap
	var top := sz.y * 0.5 - group_h * 0.5 + 20.0
	if _create_btn:
		_create_btn.size = Vector2(bw, bh)
		_create_btn.position = Vector2(cx - bw * 0.5, top)
	if _join_btn:
		_join_btn.size = Vector2(bw, bh)
		_join_btn.position = Vector2(cx - bw * 0.5, top + bh + gap)

	if _toast:
		_toast.size = Vector2(sz.x, 30)
		_toast.position = Vector2(0, sz.y - 40)
	_layout_choice_modal(sz)
	_layout_id_modal(sz)

# ---------------- create / join ----------------

func _on_create() -> void:
	if not _require_account():
		return
	game_manager.show_contest_create()

func _on_join() -> void:
	if not _require_account():
		return
	if _choice_modal == null:
		_build_choice_modal()
	_choice_modal.visible = true

# Both create and join need a signed-in player with a chosen name.
func _require_account() -> bool:
	if FirebaseManager.is_signed_in() and FirebaseManager.has_display_name():
		return true
	_show_toast("Sign in and pick a name to play the Arena.")
	return false

func _open_id_modal() -> void:
	if _choice_modal:
		_choice_modal.visible = false
	if _id_modal == null:
		_build_id_modal()
	_id_edit.text = ""
	_id_msg.text = ""
	_id_modal.visible = true
	_id_edit.grab_focus()

func _do_join() -> void:
	if _busy:
		return
	var code := _id_edit.text.strip_edges().to_upper()
	if code.length() != ContestManager.ID_LEN:
		_id_msg.text = "Enter the %d-character room ID." % ContestManager.ID_LEN
		return
	_busy = true
	_id_msg.text = "Joining…"
	var res: Dictionary = await ContestManager.join_contest(code)
	_busy = false
	if not is_inside_tree():
		return
	if bool(res.get("ok", false)):
		_id_modal.visible = false
		game_manager.show_contest_detail(code)
		return
	match String(res.get("error", "")):
		"not_found": _id_msg.text = "No room found with that ID."
		"ended":     _id_msg.text = "That room has already started."
		"full":      _id_msg.text = "That room is full."
		"auth":      _id_msg.text = "Sign in and pick a name first."
		_:           _id_msg.text = "Couldn't join. Try again."

# ---------------- toast ----------------

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

# ---------------- join-choice modal ----------------

func _build_choice_modal() -> void:
	_choice_modal = ArenaUI.stone_panel(ArenaUI.SAND)
	_choice_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_choice_modal.visible = false
	add_child(_choice_modal)

	var title := Label.new()
	title.text = "Join a Room"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", ArenaUI.TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 22)
	title.size = Vector2(400, 34)
	_choice_modal.add_child(title)

	var private_btn := ArenaUI.pill_button("🔒  Private — enter ID", ArenaUI.ACCENT, true)
	private_btn.size = Vector2(320, 54)
	private_btn.position = Vector2(40, 78)
	private_btn.pressed.connect(_open_id_modal)
	_choice_modal.add_child(private_btn)

	var public_btn := ArenaUI.pill_button("🌐  Public — browse rooms", ArenaUI.SAND)
	public_btn.size = Vector2(320, 54)
	public_btn.position = Vector2(40, 142)
	public_btn.pressed.connect(func() -> void:
		_choice_modal.visible = false
		game_manager.show_contest_lobby())
	_choice_modal.add_child(public_btn)

	var cancel := ArenaUI.pill_button("Cancel", Color(0.6, 0.4, 0.4))
	cancel.size = Vector2(320, 46)
	cancel.position = Vector2(40, 208)
	cancel.pressed.connect(func() -> void: _choice_modal.visible = false)
	_choice_modal.add_child(cancel)
	_layout_choice_modal(get_viewport_rect().size)

func _layout_choice_modal(sz: Vector2) -> void:
	if _choice_modal == null:
		return
	var w := 400.0
	var h := 280.0
	_choice_modal.size = Vector2(w, h)
	_choice_modal.position = Vector2(sz.x * 0.5 - w * 0.5, sz.y * 0.5 - h * 0.5)

# ---------------- join-by-ID modal (private) ----------------

func _build_id_modal() -> void:
	_id_modal = ArenaUI.stone_panel(ArenaUI.SAND)
	_id_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_id_modal.visible = false
	add_child(_id_modal)

	var title := Label.new()
	title.text = "Enter Room ID"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", ArenaUI.TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 22)
	title.size = Vector2(400, 34)
	_id_modal.add_child(title)

	_id_edit = LineEdit.new()
	_id_edit.placeholder_text = "ROOM ID"
	_id_edit.max_length = ContestManager.ID_LEN
	_id_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_id_edit.add_theme_font_size_override("font_size", 28)
	_id_edit.position = Vector2(50, 74)
	_id_edit.size = Vector2(300, 52)
	_id_edit.text_changed.connect(func(t: String) -> void:
		var up := t.to_upper()
		if up != t:
			_id_edit.text = up
			_id_edit.caret_column = up.length())
	_id_edit.text_submitted.connect(func(_t: String) -> void: _do_join())
	_id_modal.add_child(_id_edit)

	_id_msg = Label.new()
	_id_msg.add_theme_font_size_override("font_size", 15)
	_id_msg.add_theme_color_override("font_color", Color(1.0, 0.7, 0.6))
	_id_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_id_msg.position = Vector2(0, 134)
	_id_msg.size = Vector2(400, 22)
	_id_modal.add_child(_id_msg)

	var join := ArenaUI.pill_button("Join", ArenaUI.ACCENT, true)
	join.size = Vector2(150, 48)
	join.position = Vector2(210, 168)
	join.pressed.connect(_do_join)
	_id_modal.add_child(join)

	var cancel := ArenaUI.pill_button("Cancel", Color(0.6, 0.4, 0.4))
	cancel.size = Vector2(150, 48)
	cancel.position = Vector2(40, 168)
	cancel.pressed.connect(func() -> void: _id_modal.visible = false)
	_id_modal.add_child(cancel)
	_layout_id_modal(get_viewport_rect().size)

const ID_MODAL_H := 236.0
const ID_MODAL_TOP_MARGIN := 10.0   # modal top never lifts past this many px from the top

func _layout_id_modal(sz: Vector2) -> void:
	if _id_modal == null:
		return
	var w := 400.0
	var h := ID_MODAL_H
	_id_modal.size = Vector2(w, h)
	_id_modal_base_y = sz.y * 0.5 - h * 0.5
	_id_modal.position = Vector2(sz.x * 0.5 - w * 0.5, _id_modal_base_y - _id_modal_shift)

# Lift the ID modal so its field + buttons clear the on-screen keyboard, then ease
# it back down when the keyboard closes (mirrors the username / room-name inputs).
func _process(delta: float) -> void:
	if _id_modal == null:
		return
	var target := 0.0
	if _id_modal.visible:
		var kb_h := float(DisplayServer.virtual_keyboard_get_height())
		if kb_h > 0.0 and _id_edit != null and _id_edit.has_focus():
			var vsz := get_viewport_rect().size
			var win_h := float(get_window().size.y)
			var kb_design := kb_h * (vsz.y / maxf(win_h, 1.0))
			var keyboard_top := vsz.y - kb_design
			var modal_bottom := _id_modal_base_y + ID_MODAL_H
			var overlap := modal_bottom - (keyboard_top - 16.0)
			var max_shift := maxf(_id_modal_base_y - ID_MODAL_TOP_MARGIN, 0.0)
			target = clampf(overlap, 0.0, max_shift)
	_id_modal_shift = lerpf(_id_modal_shift, target, clampf(delta * 12.0, 0.0, 1.0))
	_id_modal.position.y = _id_modal_base_y - _id_modal_shift
