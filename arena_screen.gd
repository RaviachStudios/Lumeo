extends Control

# Arena hub (THE COLOSSEUM): the player's active contests + entry points to create
# one or join by ID. Contests show one-at-a-time in a centered carousel with
# ◀ ▶ arrows and page dots. Reads happen on open and on explicit refresh only
# (Firebase I/O is expensive — no background polling).

const ArenaUI := preload("res://arena_ui.gd")
const ArenaFX := preload("res://arena_fx.gd")

var game_manager: Node

var _bg: ColorRect
var _fx: ArenaFX
var _back: Button
var _title: Label
var _subtitle: Label             # "Fight for Glory" under the title
var _swords: Control             # crossed swords drawn faintly behind the title
var _lobby_btn: Button           # top-right: browse the public contests lobby
var _lobby_dot: Control          # the pulsing green "public" status dot on the badge

# Carousel.
var _card: Button
var _card_title: Label
var _card_info: Label            # bottom-left: "N registered | 1 Hour | Moderate"
var _card_host: Label            # bottom-right: "You host this contest"
var _prev_btn: Button
var _next_btn: Button
var _dots: Control
var _empty_lbl: Label

# Bottom actions.
var _create_btn: Button
var _join_btn: Button
var _create_cap: Label
var _join_cap: Label
var _create_shimmer: Control     # sweeping gloss highlight over the primary button
var _shimmer_x := 1.5            # sweep position, 0..1 across the button (idle: off-right)

var _overlay: Panel
var _overlay_lbl: Label
var _toast: Label

# Join-by-ID modal.
var _join_modal: Panel
var _join_edit: LineEdit
var _join_msg: Label
var _join_modal_base_y := 0.0    # resting Y of the modal (no keyboard)
var _join_modal_shift := 0.0     # current upward lift so the field clears the keyboard

var _contests: Array = []
var _idx := 0
var _counts: Dictionary = {"join": 0, "create": 0, "join_limit": 2, "create_limit": 1}
var _busy := false

const CARD_MAX_W := 520.0
const CARD_H := 296.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg = ArenaUI.make_bg("hub")
	add_child(_bg)

	# Ambient colosseum flourish (crowd / banners / torches / champion shield) behind the UI.
	_fx = ArenaFX.new()
	add_child(_fx)
	_fx.setup(get_viewport_rect().size)

	_back = ArenaUI.make_back_button()
	_back.pressed.connect(func() -> void: game_manager.show_home())
	add_child(_back)

	# Two crossed swords sit faintly behind the ARENA title (added before it so it
	# draws underneath the letters).
	_swords = Control.new()
	_swords.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_swords.draw.connect(_draw_title_swords)
	add_child(_swords)

	_title = ArenaUI.title("ARENA")
	add_child(_title)

	# Elegant tagline under the title.
	_subtitle = Label.new()
	_subtitle.text = "Fight for Glory"
	_subtitle.add_theme_font_size_override("font_size", 16)
	_subtitle.add_theme_color_override("font_color", Color(ArenaUI.GOLD.r, ArenaUI.GOLD.g, ArenaUI.GOLD.b, 0.72))
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_subtitle)

	# Top-right entry into the public contests lobby — styled as a status badge.
	_lobby_btn = _make_lobby_badge()
	_lobby_btn.pressed.connect(func() -> void: game_manager.show_contest_lobby())
	add_child(_lobby_btn)

	_build_carousel()

	_create_btn = ArenaUI.pill_button("＋  Create Contest", ArenaUI.ACCENT, true)
	_create_btn.pressed.connect(_on_create)
	# Subtle premium hover lift on the primary action (~1.03x).
	_create_btn.mouse_entered.connect(func() -> void: _hover_scale(_create_btn, 1.03))
	_create_btn.mouse_exited.connect(func() -> void: _hover_scale(_create_btn, 1.0))
	add_child(_create_btn)
	_create_cap = _make_cap()
	add_child(_create_cap)
	_build_create_shimmer()

	_join_btn = ArenaUI.pill_button("⮕  Join by ID", ArenaUI.SAND)
	_join_btn.pressed.connect(_open_join_modal)
	add_child(_join_btn)
	_join_cap = _make_cap()
	add_child(_join_cap)

	_build_overlay()
	_build_toast()

	_layout()
	get_viewport().size_changed.connect(_layout)
	_refresh()

# ---------------- carousel construction ----------------

func _build_carousel() -> void:
	_card = Button.new()
	_card.focus_mode = Control.FOCUS_NONE
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.09, 0.10, 0.20, 0.93)
	s.set_corner_radius_all(18)
	s.border_color = Color(ArenaUI.ACCENT.r, ArenaUI.ACCENT.g, ArenaUI.ACCENT.b, 0.85)
	s.set_border_width_all(2)
	s.shadow_color = Color(ArenaUI.ACCENT.r, ArenaUI.ACCENT.g, ArenaUI.ACCENT.b, 0.35)
	s.shadow_size = 18
	_card.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = Color(0.13, 0.15, 0.28, 0.96)
	_card.add_theme_stylebox_override("hover", sh)
	var sp := s.duplicate() as StyleBoxFlat
	sp.bg_color = Color(0.07, 0.08, 0.16, 0.96)
	_card.add_theme_stylebox_override("pressed", sp)
	_card.pressed.connect(func() -> void:
		if _idx >= 0 and _idx < _contests.size():
			game_manager.show_contest_detail(String(_contests[_idx].get("id", ""))))
	add_child(_card)

	_card_title = ArenaUI.big_title("")
	_card_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_card.add_child(_card_title)

	# Bottom-left: the compact stat line ("N registered  |  1 Hour  |  Moderate").
	_card_info = Label.new()
	_card_info.add_theme_font_size_override("font_size", 16)
	_card_info.add_theme_color_override("font_color", ArenaUI.MUTED)
	_card_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_card_info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_card_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(_card_info)

	# Bottom-right: host tag.
	_card_host = Label.new()
	_card_host.text = "You host this contest"
	_card_host.add_theme_font_size_override("font_size", 16)
	_card_host.add_theme_color_override("font_color", ArenaUI.GOLD)
	_card_host.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_card_host.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_card_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(_card_host)

	_prev_btn = _make_arrow(-1.0)
	_prev_btn.pressed.connect(func() -> void: _step(-1))
	add_child(_prev_btn)
	_next_btn = _make_arrow(1.0)
	_next_btn.pressed.connect(func() -> void: _step(1))
	add_child(_next_btn)

	_dots = Control.new()
	_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dots.draw.connect(_draw_dots)
	add_child(_dots)

	_empty_lbl = Label.new()
	_empty_lbl.text = "The Arena is waiting…\nCreate a contest or challenge a friend."
	_empty_lbl.add_theme_font_size_override("font_size", 19)
	_empty_lbl.add_theme_color_override("font_color", ArenaUI.MUTED)
	_empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_empty_lbl.visible = false
	add_child(_empty_lbl)

# A small muted caption shown under a bottom action button (its used/limit tally).
func _make_cap() -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", ArenaUI.MUTED)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.visible = false
	return l

func _make_arrow(dir: float) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.09, 0.10, 0.20, 0.9)
	s.set_corner_radius_all(30)
	s.border_color = Color(ArenaUI.ACCENT.r, ArenaUI.ACCENT.g, ArenaUI.ACCENT.b, 0.8)
	s.set_border_width_all(2)
	s.shadow_color = Color(ArenaUI.ACCENT.r, ArenaUI.ACCENT.g, ArenaUI.ACCENT.b, 0.35)
	s.shadow_size = 12
	b.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = Color(0.14, 0.16, 0.30, 0.95)
	b.add_theme_stylebox_override("hover", sh)
	var sp := s.duplicate() as StyleBoxFlat
	sp.bg_color = Color(0.06, 0.07, 0.15, 0.96)
	b.add_theme_stylebox_override("pressed", sp)
	var sd := s.duplicate() as StyleBoxFlat
	sd.bg_color = Color(0.08, 0.09, 0.14, 0.4)
	sd.border_color = Color(ArenaUI.ACCENT.r, ArenaUI.ACCENT.g, ArenaUI.ACCENT.b, 0.2)
	b.add_theme_stylebox_override("disabled", sd)
	# A drawn, glowing chevron arrow (much crisper than a font glyph).
	var icon := Control.new()
	icon.size = Vector2(60, 60)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.draw.connect(_draw_arrow_icon.bind(icon, dir))
	b.add_child(icon)
	return b

# A bold, gold, double-chevron arrow with a soft glow, pointing `dir` (−1 left / +1
# right). Drawn into a 60×60 icon box centred on the button.
func _draw_arrow_icon(c: Control, dir: float) -> void:
	var ctr := Vector2(30, 30)
	var gold := ArenaUI.ACCENT.lightened(0.35)
	var glow := Color(gold.r, gold.g, gold.b, 0.30)
	var core := Color(1.0, 0.95, 0.82)
	# two nested chevrons, tip leading in `dir`
	for k in 2:
		var off := dir * (k * 9.0 - 4.5)
		var tip := ctr + Vector2(off + dir * 8.0, 0)
		var top := ctr + Vector2(off - dir * 6.0, -11.0)
		var bot := ctr + Vector2(off - dir * 6.0, 11.0)
		c.draw_polyline(PackedVector2Array([top, tip, bot]), glow, 9.0, true)
		c.draw_polyline(PackedVector2Array([top, tip, bot]), gold, 5.0, true)
		c.draw_polyline(PackedVector2Array([top, tip, bot]), core, 1.6, true)

func _draw_dots() -> void:
	var n := _contests.size()
	if n <= 1:
		return
	var gap := 20.0
	var total := gap * (n - 1)
	var x := _dots.size.x * 0.5 - total * 0.5
	var y := _dots.size.y * 0.5
	for i in n:
		var on: bool = i == _idx
		var col: Color = ArenaUI.GOLD if on else ArenaUI.MUTED
		_dots.draw_circle(Vector2(x + i * gap, y), 6.0 if on else 4.0, Color(col.r, col.g, col.b, 1.0 if on else 0.5))

# ---------------- header chrome (swords / badge / shimmer) ----------------

# Two faint crossed swords behind the ARENA title — heraldic, low-opacity so the
# gold letters always stay dominant.
func _draw_title_swords() -> void:
	var ctr := _swords.size * 0.5
	var steel := Color(0.82, 0.86, 0.94)
	var a := 0.14
	for s in [-1.0, 1.0]:
		var ang: float = deg_to_rad(40.0) * s
		var dir := Vector2(sin(ang), -cos(ang))          # blade points up-and-out
		var perp := Vector2(-dir.y, dir.x)
		var tip := ctr + dir * 66.0
		var guard := ctr - dir * 4.0
		var grip := ctr - dir * 22.0
		var pommel := ctr - dir * 27.0
		# blade
		_swords.draw_line(guard, tip, Color(steel.r, steel.g, steel.b, a), 6.0)
		_swords.draw_line(guard, tip, Color(1, 1, 1, a * 0.8), 2.0)
		# crossguard
		_swords.draw_line(guard - perp * 12.0, guard + perp * 12.0, Color(ArenaUI.GOLD.r, ArenaUI.GOLD.g, ArenaUI.GOLD.b, a * 1.5), 4.0)
		# grip + pommel
		_swords.draw_line(guard, grip, Color(0.42, 0.30, 0.14, a * 1.8), 4.0)
		_swords.draw_circle(pommel, 3.6, Color(ArenaUI.GOLD.r, ArenaUI.GOLD.g, ArenaUI.GOLD.b, a * 1.5))

# The "Public Lobby" entry, restyled as a minimal status badge (pulsing green dot +
# label) rather than another glossy pill.
func _make_lobby_badge() -> Button:
	var b := Button.new()
	b.text = "Public Lobby"
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", ArenaUI.TEXT)
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.09, 0.10, 0.18, 0.74)
	s.set_corner_radius_all(16)
	s.border_color = Color(0.40, 0.82, 0.50, 0.55)   # faint green rim → "online / open"
	s.set_border_width_all(1)
	s.content_margin_left = 34                        # room for the status dot
	s.content_margin_right = 12
	b.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = Color(0.13, 0.15, 0.25, 0.88)
	b.add_theme_stylebox_override("hover", sh)
	var sp := s.duplicate() as StyleBoxFlat
	sp.bg_color = Color(0.06, 0.07, 0.13, 0.9)
	b.add_theme_stylebox_override("pressed", sp)
	_lobby_dot = Control.new()
	_lobby_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lobby_dot.draw.connect(_draw_lobby_dot)
	b.add_child(_lobby_dot)
	return b

func _draw_lobby_dot() -> void:
	var c := _lobby_dot.size * 0.5
	var t := float(Time.get_ticks_msec()) / 1000.0
	var p := 0.5 + 0.5 * sin(t * 2.4)
	var g := Color(0.36, 0.90, 0.46)
	_lobby_dot.draw_circle(c, 6.5 + p * 2.0, Color(g.r, g.g, g.b, 0.18))   # soft halo
	_lobby_dot.draw_circle(c, 4.0, g)
	_lobby_dot.draw_circle(c, 1.6, Color(0.85, 1.0, 0.88))

# A gloss highlight that sweeps across the primary Create button every few seconds.
func _build_create_shimmer() -> void:
	_create_shimmer = Control.new()
	_create_shimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_create_shimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_create_shimmer.clip_contents = true
	_create_shimmer.z_index = 2                       # above the button's sheen child
	_create_shimmer.draw.connect(_draw_create_shimmer)
	_create_btn.add_child(_create_shimmer)
	var tw := create_tween().set_loops()
	tw.tween_interval(4.5)
	tw.tween_method(_set_shimmer, -0.35, 1.45, 0.7)

func _set_shimmer(v: float) -> void:
	_shimmer_x = v
	if _create_shimmer:
		_create_shimmer.queue_redraw()

func _draw_create_shimmer() -> void:
	if _create_btn == null or _create_btn.disabled:
		return
	var w := _create_shimmer.size.x
	var h := _create_shimmer.size.y
	if w <= 0.0:
		return
	var cx := _shimmer_x * w
	var half := 18.0
	var skew := h * 0.35
	var band := PackedVector2Array([
		Vector2(cx - half + skew, 0), Vector2(cx + half + skew, 0),
		Vector2(cx + half - skew, h), Vector2(cx - half - skew, h)])
	_create_shimmer.draw_colored_polygon(band, Color(1, 1, 1, 0.13))

# Smoothly ease a button toward a target scale (used for the primary hover lift).
func _hover_scale(b: Button, to: float) -> void:
	if b == null:
		return
	b.pivot_offset = b.size * 0.5
	var tw := create_tween()
	tw.tween_property(b, "scale", Vector2(to, to), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

# ---------------- layout ----------------

func _layout() -> void:
	var sz := get_viewport_rect().size
	ArenaUI.size_bg(_bg, sz)
	if _fx:
		_fx.relayout(sz)
	var cx := sz.x * 0.5
	if _back:
		_back.position = Vector2(20, 20)
	if _lobby_btn:
		var lw := 186.0
		_lobby_btn.size = Vector2(lw, 46)
		_lobby_btn.position = Vector2(sz.x - lw - 20, 20)
		if _lobby_dot:
			_lobby_dot.size = Vector2(24, 46)
			_lobby_dot.position = Vector2(6, 0)
	if _swords:
		var swd := 300.0
		_swords.size = Vector2(swd, 96)
		_swords.position = Vector2(cx - swd * 0.5, 4)
		_swords.queue_redraw()
	if _title:
		_title.size = Vector2(sz.x, 52)
		_title.position = Vector2(0, 22)
	if _subtitle:
		_subtitle.size = Vector2(sz.x, 22)
		_subtitle.position = Vector2(0, 74)

	var card_w: float = minf(CARD_MAX_W, sz.x - 200.0)
	var card_top := 150.0
	if _card:
		_card.size = Vector2(card_w, CARD_H)
		_card.position = Vector2(cx - card_w * 0.5, card_top)
		# card inner content: title centred, stat line bottom-left, host tag bottom-right
		_card_title.position = Vector2(24, CARD_H * 0.5 - 44)
		_card_title.size = Vector2(card_w - 48, 88)
		_card_info.position = Vector2(24, CARD_H - 44)
		_card_info.size = Vector2(card_w * 0.55 - 24, 26)
		_card_host.position = Vector2(card_w * 0.45, CARD_H - 44)
		_card_host.size = Vector2(card_w * 0.55 - 24, 26)
	if _prev_btn:
		_prev_btn.size = Vector2(60, 60)
		_prev_btn.position = Vector2(cx - card_w * 0.5 - 74, card_top + CARD_H * 0.5 - 30)
	if _next_btn:
		_next_btn.size = Vector2(60, 60)
		_next_btn.position = Vector2(cx + card_w * 0.5 + 14, card_top + CARD_H * 0.5 - 30)
	if _dots:
		_dots.position = Vector2(cx - 150, card_top + CARD_H + 12)
		_dots.size = Vector2(300, 24)
		_dots.queue_redraw()
	if _empty_lbl:
		# Sit the message in the upper half of the card zone so it reads clearly
		# ABOVE the champion-shield platform (which the FX layer centres lower down).
		_empty_lbl.position = Vector2(cx - card_w * 0.5, card_top + 44)
		_empty_lbl.size = Vector2(card_w, 72)

	# bottom action row (create / join), centered
	var by := card_top + CARD_H + 56.0
	by = minf(by, sz.y - 88.0)
	# Primary (Create) is a touch wider than the secondary (Join) to signal hierarchy,
	# while both keep the same height for a clean, consistent action row.
	var create_w := 256.0
	var join_w := 216.0
	if _create_btn:
		_create_btn.size = Vector2(create_w, 60)
		_create_btn.pivot_offset = _create_btn.size * 0.5   # scale from the centre on hover
	if _join_btn:
		_join_btn.size = Vector2(join_w, 60)
	var gap := 18.0
	var total := create_w + join_w + gap
	var x := cx - total * 0.5
	var cap_y := by + 60.0 + 6.0
	if _create_btn:
		_create_btn.position = Vector2(x, by)
		if _create_cap:
			_create_cap.position = Vector2(x, cap_y)
			_create_cap.size = Vector2(create_w, 20)
		x += create_w + gap
	if _join_btn:
		_join_btn.position = Vector2(x, by)
		if _join_cap:
			_join_cap.position = Vector2(x, cap_y)
			_join_cap.size = Vector2(join_w, 20)

	if _overlay:
		_overlay.position = Vector2.ZERO
		_overlay.size = sz
	if _overlay_lbl:
		_overlay_lbl.size = Vector2(sz.x, 40)
		_overlay_lbl.position = Vector2(0, sz.y * 0.5 - 20)
	if _toast:
		_toast.size = Vector2(sz.x, 30)
		_toast.position = Vector2(0, sz.y - 40)
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
	_contests = contests
	_idx = clampi(_idx, 0, maxi(0, _contests.size() - 1))
	_show_current()
	_update_caps()
	_set_overlay(false)
	_busy = false

func _update_caps() -> void:
	var created := int(_counts.get("create", 0))
	var create_limit := int(_counts.get("create_limit", 1))
	var joined := int(_counts.get("join", 0))
	var join_limit := int(_counts.get("join_limit", 2))
	# Create tally shows once anything is created; join tally only when it's maxed out.
	if _create_cap:
		_create_cap.visible = created > 0
		_create_cap.text = "You've already created %d/%d contests" % [created, create_limit]
	if _join_cap:
		_join_cap.visible = joined >= join_limit
		_join_cap.text = "You've already joined %d/%d contests" % [joined, join_limit]
	var can_create: bool = created < create_limit
	var can_join: bool = joined < join_limit
	if _create_btn:
		_create_btn.disabled = not can_create
	if _join_btn:
		_join_btn.disabled = not can_join

func _step(dir: int) -> void:
	var n := _contests.size()
	if n <= 1:
		return
	_idx = (_idx + dir + n) % n
	_show_current()

func _show_current() -> void:
	var has := not _contests.is_empty()
	_card.visible = has
	_empty_lbl.visible = not has
	var multi := _contests.size() > 1
	_prev_btn.visible = has
	_next_btn.visible = has
	_prev_btn.disabled = not multi
	_next_btn.disabled = not multi
	_prev_btn.modulate.a = 1.0 if multi else 0.4      # dim the drawn chevron when idle
	_next_btn.modulate.a = 1.0 if multi else 0.4
	_dots.queue_redraw()
	if not has:
		return

	var c: Dictionary = _contests[_idx]
	var type := String(c.get("type", ""))
	var diff := String(c.get("difficulty", "easy"))
	var count := int(c.get("member_count", 1))

	_card_title.text = ArenaUI.clamp_title(String(c.get("title", "Contest")))
	# Bottom-left stat line: registered · duration · difficulty.
	_card_info.text = "%d registered   |   %s   |   %s" % [
		count, ContestManager.type_label(type), ContestManager.diff_label(diff)]
	_card_host.visible = bool(c.get("is_creator", false))

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
	s.bg_color = Color(0.03, 0.02, 0.01, 0.72)
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
	_join_modal = ArenaUI.stone_panel(ArenaUI.SAND)
	_join_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_join_modal.visible = false
	add_child(_join_modal)

	var title := Label.new()
	title.text = "Join a Contest"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", ArenaUI.TEXT)
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
	var h := JOIN_MODAL_H
	_join_modal.size = Vector2(w, h)
	_join_modal_base_y = sz.y * 0.5 - h * 0.5
	_join_modal.position = Vector2(sz.x * 0.5 - w * 0.5, _join_modal_base_y - _join_modal_shift)

# Lift the join modal so its bottom edge (ID field + buttons) clears the on-screen
# keyboard, then ease it back down when the keyboard closes. Mirrors the behaviour of
# the username and contest-name inputs so the modal never sits behind the keyboard.
const JOIN_MODAL_H := 236.0
const JOIN_MODAL_TOP_MARGIN := 10.0   # modal top never lifts past this many px from the top

func _process(delta: float) -> void:
	if _lobby_dot:
		_lobby_dot.queue_redraw()      # keep the "public" status dot gently pulsing
	if _join_modal == null:
		return
	var target := 0.0
	if _join_modal.visible:
		var kb_h := float(DisplayServer.virtual_keyboard_get_height())
		if kb_h > 0.0 and _join_edit != null and _join_edit.has_focus():
			var vsz := get_viewport_rect().size
			# The keyboard height is reported in real device pixels; the modal lives in
			# the stretched design space, so convert it before comparing.
			var win_h := float(get_window().size.y)
			var kb_design := kb_h * (vsz.y / maxf(win_h, 1.0))
			var keyboard_top := vsz.y - kb_design
			var modal_bottom := _join_modal_base_y + JOIN_MODAL_H
			var overlap := modal_bottom - (keyboard_top - 16.0)
			# Clamp so the modal top stays at least the margin below the screen top.
			var max_shift := maxf(_join_modal_base_y - JOIN_MODAL_TOP_MARGIN, 0.0)
			target = clampf(overlap, 0.0, max_shift)
	_join_modal_shift = lerpf(_join_modal_shift, target, clampf(delta * 12.0, 0.0, 1.0))
	_join_modal.position.y = _join_modal_base_y - _join_modal_shift
