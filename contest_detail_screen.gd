extends Control

const ArenaUI := preload("res://arena_ui.gd")

# Contest detail — three faces driven by status:
#   lobby    : share ID, roster (+kick), Start (creator), Leave
#   active   : countdown (client-side) / "waiting", standings, PLAY, Leave,
#              creator: kick + End-now (one_game)
#   finished : podium + full standings table, Exit only
#
# Reads happen on open + explicit Refresh only. The countdown is read once and
# ticks locally; when it hits 0 we do a single reload to fetch the result.

var game_manager: Node
var contest_id: String = ""

var _bg: ColorRect
var _back: Button
var _title: Label
var _content: Control          # cleared + rebuilt per render
var _overlay: Panel
var _overlay_lbl: Label
var _toast: Label

# Confirm modal.
var _confirm: Panel
var _confirm_lbl: Label
var _confirm_yes_cb: Callable

var _data: Dictionary = {}
var _busy := false

# Client-side countdown (timed contests). 0 = none.
var _countdown_target := 0
var _countdown_lbl: Label
var _deadline_fired := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg = ArenaUI.make_bg()
	add_child(_bg)
	_back = ArenaUI.make_back_button()
	_back.pressed.connect(func() -> void: game_manager.show_arena())
	add_child(_back)
	_title = ArenaUI.title("CONTEST")
	add_child(_title)
	_content = Control.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)
	_build_overlay()
	_build_toast()
	_layout_static()
	get_viewport().size_changed.connect(_on_resize)
	_reload()

func _process(_dt: float) -> void:
	if _countdown_target > 0 and _countdown_lbl and is_instance_valid(_countdown_lbl):
		var secs := _countdown_target - int(Time.get_unix_time_from_system())
		if secs <= 0:
			_countdown_lbl.text = "Time's up!"
			if not _deadline_fired:
				_deadline_fired = true
				_countdown_target = 0
				_reload()
		else:
			_countdown_lbl.text = _fmt_countdown(secs)

func _fmt_countdown(secs: int) -> String:
	var h := secs / 3600
	var m := (secs % 3600) / 60
	var s := secs % 60
	if h > 0:
		return "%d:%02d:%02d left" % [h, m, s]
	return "%02d:%02d left" % [m, s]

func _on_resize() -> void:
	_layout_static()
	if not _data.is_empty():
		_render()

func _layout_static() -> void:
	var sz := get_viewport_rect().size
	ArenaUI.size_bg(_bg, sz)
	if _back:
		_back.position = Vector2(20, 20)
	if _title:
		_title.size = Vector2(sz.x, 52)
		_title.position = Vector2(0, 22)
	if _content:
		_content.position = Vector2(0, 90)
		_content.size = Vector2(sz.x, sz.y - 90)
	if _overlay:
		_overlay.position = Vector2.ZERO
		_overlay.size = sz
	if _overlay_lbl:
		_overlay_lbl.size = Vector2(sz.x, 40)
		_overlay_lbl.position = Vector2(0, sz.y * 0.5 - 20)
	if _toast:
		_toast.size = Vector2(sz.x, 30)
		_toast.position = Vector2(0, sz.y - 70)
	_layout_confirm(sz)

# ---------------- load ----------------

func _reload() -> void:
	if _busy:
		return
	_busy = true
	_countdown_target = 0
	_deadline_fired = false
	_set_overlay(true, "Loading…")
	var res: Dictionary = await ContestManager.load_contest(contest_id)
	if not is_inside_tree():
		return
	_data = res
	_set_overlay(false)
	_busy = false
	_render()

# ---------------- render dispatch ----------------

func _render() -> void:
	for c in _content.get_children():
		c.queue_free()
	_countdown_lbl = null
	_countdown_target = 0
	if not bool(_data.get("ok", false)):
		_render_message("This contest no longer exists.", "Back to Arena",
			func() -> void: game_manager.show_arena())
		return
	var meta: Dictionary = _data.get("meta", {})
	var status := String(meta.get("status", "lobby"))
	_title.text = "%s  ·  %s" % [ContestManager.type_label(String(meta.get("type", ""))),
		ContestManager.diff_label(String(meta.get("difficulty", "easy")))]

	if status == "finished":
		_render_finished(meta)
		return
	# Active/lobby but I'm not a member anymore (kicked / left elsewhere).
	if not bool(_data.get("i_am_member", false)):
		_render_message("You're no longer in this contest.", "Back to Arena",
			func() -> void: game_manager.show_arena())
		return
	if status == "lobby":
		_render_lobby(meta)
	else:
		_render_active(meta)

# ---------------- lobby ----------------

func _render_lobby(meta: Dictionary) -> void:
	var w := _content.size.x
	var cx := w * 0.5
	var is_creator := String(meta.get("creator_uid", "")) == FirebaseManager.uid
	var members: Array = _data.get("members", [])

	# Big shareable ID with a Copy button.
	var idbox := ArenaUI.glass_panel(Color(0.45, 0.62, 1.0))
	idbox.size = Vector2(360, 96)
	idbox.position = Vector2(cx - 180, 6)
	_content.add_child(idbox)
	var idcap := Label.new()
	idcap.text = "SHARE THIS ID"
	idcap.add_theme_font_size_override("font_size", 14)
	idcap.add_theme_color_override("font_color", ArenaUI.MUTED)
	idcap.position = Vector2(0, 10); idcap.size = Vector2(360, 18)
	idcap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	idcap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	idbox.add_child(idcap)
	var idlbl := Label.new()
	idlbl.text = contest_id
	idlbl.add_theme_font_size_override("font_size", 44)
	idlbl.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	idlbl.add_theme_constant_override("outline_size", 2)
	idlbl.position = Vector2(0, 30); idlbl.size = Vector2(360, 56)
	idlbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	idlbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	idbox.add_child(idlbl)

	var copy := ArenaUI.pill_button("Copy ID", Color(0.45, 0.62, 1.0))
	copy.size = Vector2(150, 44)
	copy.position = Vector2(cx - 75, 112)
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(contest_id)
		_show_toast("Contest ID copied!"))
	_content.add_child(copy)

	# Roster.
	var hint := Label.new()
	hint.text = "Players (%d)" % members.size()
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", ArenaUI.TEXT)
	hint.position = Vector2(cx - 260, 170); hint.size = Vector2(520, 24)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(hint)
	_add_roster(members, is_creator, Vector2(cx - 260, 200), 520)

	# Buttons at the bottom.
	var by := _content.size.y - 78.0
	if is_creator:
		var start := ArenaUI.pill_button("Start Contest", ArenaUI.ACCENT, true)
		start.size = Vector2(220, 56)
		start.position = Vector2(cx - 230, by)
		start.pressed.connect(_on_start)
		_content.add_child(start)
		var leave := ArenaUI.pill_button("Cancel", Color(0.7, 0.4, 0.4))
		leave.size = Vector2(220, 56)
		leave.position = Vector2(cx + 10, by)
		leave.pressed.connect(_on_leave)
		_content.add_child(leave)
	else:
		var leave := ArenaUI.pill_button("Leave Contest", Color(0.7, 0.4, 0.4))
		leave.size = Vector2(240, 56)
		leave.position = Vector2(cx - 120, by)
		leave.pressed.connect(_on_leave)
		_content.add_child(leave)

# ---------------- active ----------------

func _render_active(meta: Dictionary) -> void:
	var w := _content.size.x
	var cx := w * 0.5
	var type := String(meta.get("type", ""))
	var is_creator := String(meta.get("creator_uid", "")) == FirebaseManager.uid
	var members: Array = _data.get("members", [])
	var my_member: Dictionary = _data.get("my_member", {})

	# Status / countdown banner.
	_countdown_lbl = Label.new()
	_countdown_lbl.add_theme_font_size_override("font_size", 30)
	_countdown_lbl.add_theme_color_override("font_color", Color(0.55, 0.9, 0.7))
	_countdown_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_lbl.position = Vector2(0, 4); _countdown_lbl.size = Vector2(w, 40)
	_countdown_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_countdown_lbl)
	var now := int(Time.get_unix_time_from_system())
	var deadline := int(meta.get("deadline_at", 0))
	var past_deadline := type != "one_game" and deadline > 0 and now >= deadline
	if type == "one_game":
		var pending := 0
		for m in members:
			if not bool(m.get("done", false)):
				pending += 1
		_countdown_lbl.text = "Waiting for %d player%s to finish" % [pending, "" if pending == 1 else "s"]
	elif past_deadline:
		# Deadline passed but not finalized yet (someone finishing within grace).
		# Do NOT arm the countdown timer — that would auto-reload every frame.
		_countdown_lbl.text = "Time's up — finishing…"
	else:
		_countdown_target = deadline
		_countdown_lbl.text = _fmt_countdown(maxi(0, deadline - now))

	# Standings (live members, ranked). Manual refresh only.
	var ranked := members.duplicate()
	ranked.sort_custom(func(a, b): return int(a.get("best_score", 0)) > int(b.get("best_score", 0)))
	var refresh := ArenaUI.pill_button("⟳ Refresh", Color(0.55, 0.62, 0.85))
	refresh.size = Vector2(140, 40)
	refresh.position = Vector2(cx + 130, 52)
	refresh.pressed.connect(func() -> void: _reload())
	_content.add_child(refresh)
	var hdr := Label.new()
	hdr.text = "Standings"
	hdr.add_theme_font_size_override("font_size", 18)
	hdr.add_theme_color_override("font_color", ArenaUI.TEXT)
	hdr.position = Vector2(cx - 270, 56); hdr.size = Vector2(300, 24)
	hdr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(hdr)
	_add_active_standings(ranked, is_creator, Vector2(cx - 270, 86), 540)

	# Bottom action bar.
	var by := _content.size.y - 78.0
	var can_play := true
	var play_txt := "▶  Play"
	if type == "one_game" and bool(my_member.get("done", false)):
		can_play = false
	if past_deadline:
		can_play = false            # window closed; results are being finalized
	if type != "one_game":
		play_txt = "▶  Play  (best %d)" % int(my_member.get("best_score", 0))

	if can_play:
		var play := ArenaUI.pill_button(play_txt, Color(0.30, 0.80, 0.52), true)
		play.size = Vector2(240, 56)
		play.position = Vector2(cx - 250, by)
		play.pressed.connect(_on_play)
		_content.add_child(play)
	else:
		var doneb := ArenaUI.pill_button("✓ You've played", Color(0.4, 0.5, 0.5))
		doneb.disabled = true
		doneb.size = Vector2(240, 56)
		doneb.position = Vector2(cx - 250, by)
		_content.add_child(doneb)

	var leave := ArenaUI.pill_button("Leave", Color(0.7, 0.4, 0.4))
	leave.size = Vector2(150, 56)
	leave.position = Vector2(cx + 10, by)
	leave.pressed.connect(_on_leave)
	_content.add_child(leave)

	if is_creator and type == "one_game":
		var endnow := ArenaUI.pill_button("End now", Color(0.9, 0.6, 0.3))
		endnow.size = Vector2(150, 56)
		endnow.position = Vector2(cx + 170, by)
		endnow.pressed.connect(_on_finalize_now)
		_content.add_child(endnow)

# ---------------- finished ----------------

func _render_finished(meta: Dictionary) -> void:
	var w := _content.size.x
	var cx := w * 0.5
	var standings: Array = _data.get("standings", [])

	var champ := Label.new()
	champ.text = "🏆  Final Results"
	champ.add_theme_font_size_override("font_size", 26)
	champ.add_theme_color_override("font_color", ArenaUI.GOLD)
	champ.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	champ.position = Vector2(0, 0); champ.size = Vector2(w, 34)
	champ.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(champ)

	_add_podium(standings, Vector2(cx, 48))

	# Full table (scrollable) below the podium.
	var table_top := 250.0
	var tw: float = minf(620.0, w - 80.0)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.position = Vector2(cx - tw * 0.5, table_top)
	scroll.size = Vector2(tw, _content.size.y - table_top - 80.0)
	_content.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.custom_minimum_size = Vector2(tw, 0)
	scroll.add_child(vb)
	for r: Dictionary in standings:
		vb.add_child(_make_result_row(r, tw))

	var exit := ArenaUI.pill_button("Exit Contest", ArenaUI.ACCENT, true)
	exit.size = Vector2(240, 56)
	exit.position = Vector2(cx - 120, _content.size.y - 70.0)
	exit.pressed.connect(_on_exit)
	_content.add_child(exit)

func _add_podium(standings: Array, center: Vector2) -> void:
	# Three medal blocks: 2nd left, 1st center (tallest), 3rd right.
	var medal := [ArenaUI.GOLD, Color(0.78, 0.85, 0.98), Color(0.88, 0.55, 0.28)]
	var order := [1, 0, 2]                 # draw slots: left=rank2, center=rank1, right=rank3
	var heights := [150.0, 110.0, 92.0]    # by slot index
	var bw := 150.0
	var gap := 14.0
	var base_y := 190.0
	var start_x := center.x - (bw * 1.5 + gap)
	for slot in 3:
		var rank_idx: int = order[slot]     # 0-based rank
		var x := start_x + slot * (bw + gap)
		var col: Color = medal[rank_idx]
		var bh: float = heights[slot]
		var block := Panel.new()
		block.size = Vector2(bw, bh)
		block.position = Vector2(x, base_y - bh)
		block.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var s := StyleBoxFlat.new()
		s.bg_color = Color(col.r, col.g, col.b, 0.16)
		s.border_color = Color(col.r, col.g, col.b, 0.9)
		s.set_border_width_all(2)
		s.corner_radius_top_left = 12; s.corner_radius_top_right = 12
		s.shadow_color = Color(col.r, col.g, col.b, 0.35)
		s.shadow_size = 12
		block.add_theme_stylebox_override("panel", s)
		_content.add_child(block)

		var rnum := Label.new()
		rnum.text = str(rank_idx + 1)
		rnum.add_theme_font_size_override("font_size", 40)
		rnum.add_theme_color_override("font_color", col.lightened(0.3))
		rnum.position = Vector2(0, bh - 54); rnum.size = Vector2(bw, 48)
		rnum.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rnum.mouse_filter = Control.MOUSE_FILTER_IGNORE
		block.add_child(rnum)

		if rank_idx < standings.size():
			var e: Dictionary = standings[rank_idx]
			var nm := Label.new()
			nm.text = String(e.get("name", "Player"))
			nm.add_theme_font_size_override("font_size", 18)
			nm.add_theme_color_override("font_color",
				Color.WHITE if not bool(e.get("is_me", false)) else ArenaUI.GOLD.lightened(0.2))
			nm.position = Vector2(4, 12); nm.size = Vector2(bw - 8, 24)
			nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			nm.clip_text = true
			nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
			block.add_child(nm)
			var sc := Label.new()
			sc.text = str(int(e.get("score", 0)))
			sc.add_theme_font_size_override("font_size", 30)
			sc.add_theme_color_override("font_color", col.lightened(0.4))
			sc.position = Vector2(4, 40); sc.size = Vector2(bw - 8, 34)
			sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			sc.mouse_filter = Control.MOUSE_FILTER_IGNORE
			block.add_child(sc)

func _make_result_row(r: Dictionary, width: float) -> Control:
	var row := Panel.new()
	row.custom_minimum_size = Vector2(width, 44)
	var is_me: bool = bool(r.get("is_me", false))
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.16, 0.13, 0.05, 0.6) if is_me else Color(0.10, 0.10, 0.20, 0.5)
	s.set_corner_radius_all(10)
	if is_me:
		s.border_color = Color(ArenaUI.GOLD.r, ArenaUI.GOLD.g, ArenaUI.GOLD.b, 0.8)
		s.set_border_width_all(1)
	row.add_theme_stylebox_override("panel", s)
	var rank := Label.new()
	rank.text = "#%d" % int(r.get("rank", 0))
	rank.add_theme_font_size_override("font_size", 18)
	rank.add_theme_color_override("font_color", ArenaUI.MUTED)
	rank.position = Vector2(14, 0); rank.size = Vector2(56, 44)
	rank.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rank.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(rank)
	var nm := Label.new()
	nm.text = String(r.get("name", "Player")) + ("  (you)" if is_me else "")
	nm.add_theme_font_size_override("font_size", 18)
	nm.add_theme_color_override("font_color", Color.WHITE if not is_me else ArenaUI.GOLD.lightened(0.3))
	nm.position = Vector2(76, 0); nm.size = Vector2(width - 240, 44)
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nm.clip_text = true
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(nm)
	var sc := Label.new()
	sc.text = "%d  ·  %d game%s" % [int(r.get("score", 0)), int(r.get("games", 0)),
		"" if int(r.get("games", 0)) == 1 else "s"]
	sc.add_theme_font_size_override("font_size", 17)
	sc.add_theme_color_override("font_color", Color(0.8, 0.85, 1.0))
	sc.position = Vector2(width - 200, 0); sc.size = Vector2(186, 44)
	sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sc)
	return row

# ---------------- roster / standings rows ----------------

func _add_roster(members: Array, can_kick: bool, pos: Vector2, width: float) -> void:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.position = pos
	scroll.size = Vector2(width, _content.size.y - pos.y - 96.0)
	_content.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.custom_minimum_size = Vector2(width, 0)
	scroll.add_child(vb)
	for m: Dictionary in members:
		vb.add_child(_make_roster_row(m, can_kick, width))

func _make_roster_row(m: Dictionary, can_kick: bool, width: float) -> Control:
	var row := Panel.new()
	row.custom_minimum_size = Vector2(width, 46)
	var uid := String(m.get("uid", ""))
	var is_me := uid == FirebaseManager.uid
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.12, 0.12, 0.22, 0.55)
	s.set_corner_radius_all(10)
	row.add_theme_stylebox_override("panel", s)
	var nm := Label.new()
	nm.text = String(m.get("name", "Player"))
	if bool(m.get("is_creator", false)):
		nm.text = "👑 " + nm.text
	if is_me:
		nm.text += "  (you)"
	nm.add_theme_font_size_override("font_size", 18)
	nm.add_theme_color_override("font_color", Color.WHITE)
	nm.position = Vector2(16, 0); nm.size = Vector2(width - 80, 46)
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nm.clip_text = true
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(nm)
	# Creator may kick anyone but themselves.
	if can_kick and not is_me:
		var kick := Button.new()
		kick.text = "✕"
		kick.focus_mode = Control.FOCUS_NONE
		kick.add_theme_font_size_override("font_size", 18)
		var ks := StyleBoxFlat.new()
		ks.bg_color = Color(0.4, 0.12, 0.12, 0.8)
		ks.set_corner_radius_all(8)
		kick.add_theme_stylebox_override("normal", ks)
		var kh := ks.duplicate() as StyleBoxFlat
		kh.bg_color = Color(0.55, 0.15, 0.15, 0.9)
		kick.add_theme_stylebox_override("hover", kh)
		kick.add_theme_color_override("font_color", Color(1, 0.85, 0.85))
		kick.size = Vector2(40, 34)
		kick.position = Vector2(width - 52, 6)
		var target_name := String(m.get("name", "Player"))
		kick.pressed.connect(func() -> void: _on_kick(uid, target_name))
		row.add_child(kick)
	return row

func _add_active_standings(members: Array, can_kick: bool, pos: Vector2, width: float) -> void:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.position = pos
	scroll.size = Vector2(width, _content.size.y - pos.y - 96.0)
	_content.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.custom_minimum_size = Vector2(width, 0)
	scroll.add_child(vb)
	var rank := 0
	for m: Dictionary in members:
		rank += 1
		vb.add_child(_make_standing_row(m, rank, can_kick, width))

func _make_standing_row(m: Dictionary, rank: int, can_kick: bool, width: float) -> Control:
	var row := Panel.new()
	row.custom_minimum_size = Vector2(width, 46)
	var uid := String(m.get("uid", ""))
	var is_me := uid == FirebaseManager.uid
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.16, 0.13, 0.05, 0.55) if is_me else Color(0.11, 0.11, 0.21, 0.55)
	s.set_corner_radius_all(10)
	row.add_theme_stylebox_override("panel", s)
	var rlbl := Label.new()
	rlbl.text = "#%d" % rank
	rlbl.add_theme_font_size_override("font_size", 17)
	rlbl.add_theme_color_override("font_color", ArenaUI.MUTED)
	rlbl.position = Vector2(12, 0); rlbl.size = Vector2(48, 46)
	rlbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rlbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(rlbl)
	var nm := Label.new()
	var nm_text := String(m.get("name", "Player"))
	if bool(m.get("is_creator", false)):
		nm_text = "👑 " + nm_text
	if is_me:
		nm_text += "  (you)"
	if String(m.get("state", "")) == "in_progress":
		nm_text += "  · playing…"
	nm.text = nm_text
	nm.add_theme_font_size_override("font_size", 17)
	nm.add_theme_color_override("font_color", Color.WHITE)
	nm.position = Vector2(66, 0); nm.size = Vector2(width - 240, 46)
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nm.clip_text = true
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(nm)
	var sc := Label.new()
	sc.text = str(int(m.get("best_score", 0)))
	sc.add_theme_font_size_override("font_size", 20)
	sc.add_theme_color_override("font_color", Color(0.8, 0.85, 1.0))
	sc.position = Vector2(width - 170, 0); sc.size = Vector2(120, 46)
	sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sc)
	if can_kick and not is_me:
		var kick := Button.new()
		kick.text = "✕"
		kick.focus_mode = Control.FOCUS_NONE
		var ks := StyleBoxFlat.new()
		ks.bg_color = Color(0.4, 0.12, 0.12, 0.8)
		ks.set_corner_radius_all(8)
		kick.add_theme_stylebox_override("normal", ks)
		kick.add_theme_color_override("font_color", Color(1, 0.85, 0.85))
		kick.size = Vector2(36, 32)
		kick.position = Vector2(width - 44, 7)
		var target_name := String(m.get("name", "Player"))
		kick.pressed.connect(func() -> void: _on_kick(uid, target_name))
		row.add_child(kick)
	return row

func _render_message(msg: String, btn_text: String, cb: Callable) -> void:
	var w := _content.size.x
	var lbl := Label.new()
	lbl.text = msg
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", ArenaUI.TEXT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position = Vector2(0, _content.size.y * 0.4); lbl.size = Vector2(w, 40)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(lbl)
	var b := ArenaUI.pill_button(btn_text, ArenaUI.ACCENT, true)
	b.size = Vector2(220, 54)
	b.position = Vector2(w * 0.5 - 110, _content.size.y * 0.4 + 60)
	b.pressed.connect(cb)
	_content.add_child(b)

# ---------------- actions ----------------

func _on_start() -> void:
	var members: Array = _data.get("members", [])
	if members.size() < 2:
		_show_confirm("No one else has joined yet.\nStart the contest anyway?",
			func() -> void: _do_start())
	else:
		_do_start()

func _do_start() -> void:
	_set_overlay(true, "Starting…")
	var res: Dictionary = await ContestManager.start_contest(contest_id)
	if not is_inside_tree():
		return
	_set_overlay(false)
	if not bool(res.get("ok", false)):
		_show_toast("Couldn't start the contest.")
		return
	_reload()

func _on_play() -> void:
	var meta: Dictionary = _data.get("meta", {})
	var my_member: Dictionary = _data.get("my_member", {})
	# Re-verify the deadline locally so a stale screen can't launch a game after
	# time expired.
	var type := String(meta.get("type", ""))
	if type != "one_game":
		var dl := int(meta.get("deadline_at", 0))
		if dl > 0 and int(Time.get_unix_time_from_system()) >= dl:
			_show_toast("Time's up for this contest.")
			_reload()
			return
	await ContestManager.begin_contest_game(contest_id, type,
		String(meta.get("difficulty", "easy")),
		int(my_member.get("best_score", 0)), int(my_member.get("games_played", 0)))
	if not is_inside_tree():
		return
	game_manager.show_game()

func _on_kick(uid: String, nm: String) -> void:
	_show_confirm("Remove %s from the contest?" % nm, func() -> void:
		_set_overlay(true, "Removing…")
		await ContestManager.kick_member(contest_id, uid)
		if not is_inside_tree():
			return
		_set_overlay(false)
		_reload())

func _on_finalize_now() -> void:
	_show_confirm("End the contest now and lock in the results?", func() -> void:
		_set_overlay(true, "Finalizing…")
		await ContestManager.finalize_now(contest_id)
		if not is_inside_tree():
			return
		_set_overlay(false)
		_reload())

func _on_leave() -> void:
	var meta: Dictionary = _data.get("meta", {})
	var is_creator := String(meta.get("creator_uid", "")) == FirebaseManager.uid
	var status := String(meta.get("status", ""))
	var msg := "Leave this contest?"
	if is_creator and status != "finished":
		msg = "You're the host. Leaving ends the contest for everyone. Continue?"
	_show_confirm(msg, func() -> void: _do_leave())

func _do_leave() -> void:
	_set_overlay(true, "Leaving…")
	await ContestManager.leave_contest(contest_id)
	if not is_inside_tree():
		return
	game_manager.show_arena()

func _on_exit() -> void:
	_set_overlay(true, "Exiting…")
	await ContestManager.leave_contest(contest_id)
	if not is_inside_tree():
		return
	game_manager.show_arena()

# ---------------- overlay / toast / confirm ----------------

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

func _show_confirm(msg: String, on_yes: Callable) -> void:
	if _confirm == null:
		_build_confirm()
	_confirm_yes_cb = on_yes
	_confirm_lbl.text = msg
	_confirm.visible = true

func _build_confirm() -> void:
	_confirm = Panel.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.05, 0.14, 0.99)
	s.set_corner_radius_all(18)
	s.border_color = Color(0.6, 0.5, 1.0, 0.7)
	s.set_border_width_all(2)
	s.shadow_color = Color(0.4, 0.3, 1.0, 0.4)
	s.shadow_size = 20
	_confirm.add_theme_stylebox_override("panel", s)
	_confirm.visible = false
	add_child(_confirm)
	_confirm_lbl = Label.new()
	_confirm_lbl.add_theme_font_size_override("font_size", 20)
	_confirm_lbl.add_theme_color_override("font_color", Color.WHITE)
	_confirm_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_confirm_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_lbl.position = Vector2(24, 22); _confirm_lbl.size = Vector2(412, 96)
	_confirm.add_child(_confirm_lbl)
	var yes := ArenaUI.pill_button("Yes", ArenaUI.ACCENT, true)
	yes.size = Vector2(180, 50); yes.position = Vector2(240, 130)
	yes.pressed.connect(func() -> void:
		_confirm.visible = false
		if _confirm_yes_cb.is_valid():
			_confirm_yes_cb.call())
	_confirm.add_child(yes)
	var no := ArenaUI.pill_button("No", Color(0.6, 0.4, 0.4))
	no.size = Vector2(180, 50); no.position = Vector2(40, 130)
	no.pressed.connect(func() -> void: _confirm.visible = false)
	_confirm.add_child(no)
	_layout_confirm(get_viewport_rect().size)

func _layout_confirm(sz: Vector2) -> void:
	if _confirm == null:
		return
	var w := 460.0
	var h := 200.0
	_confirm.size = Vector2(w, h)
	_confirm.position = Vector2(sz.x * 0.5 - w * 0.5, sz.y * 0.5 - h * 0.5)
