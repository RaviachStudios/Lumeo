extends Control

const ArenaUI := preload("res://arena_ui.gd")
const PodiumStage := preload("res://podium_stage.gd")
const SimonFlyer := preload("res://simon_flyer.gd")

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

var _bg: ColorRect              # amphitheatre (active / finished)
var _lobby_bg: ColorRect        # the distinct champions' antechamber (lobby)
var _back: Button
var _corner_btn: Button         # active screen: Cancel/Leave, top-right (mirrors Back)
var _title: Label               # the contest's big carved name
var _subtitle: Label            # type · difficulty, under the name
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
	_lobby_bg = ArenaUI.make_lobby_bg()
	add_child(_lobby_bg)
	_bg = ArenaUI.make_bg("active")
	_bg.visible = false
	add_child(_bg)
	_back = ArenaUI.make_back_button()
	_back.pressed.connect(func() -> void: game_manager.show_arena())
	add_child(_back)
	_title = ArenaUI.big_title("CONTEST")
	add_child(_title)
	# Fancy "format · difficulty" plaque under the title (spaced away from it).
	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", 20)
	_subtitle.add_theme_color_override("font_color", ArenaUI.GOLD.lightened(0.2))
	_subtitle.add_theme_color_override("font_outline_color", Color(0.28, 0.16, 0.03))
	_subtitle.add_theme_constant_override("outline_size", 3)
	_subtitle.add_theme_color_override("font_shadow_color", Color(1.0, 0.6, 0.2, 0.4))
	_subtitle.add_theme_constant_override("shadow_offset_y", 2)
	_subtitle.add_theme_constant_override("shadow_outline_size", 8)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_subtitle)
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
	ArenaUI.size_bg(_lobby_bg, sz)
	if _back:
		_back.position = Vector2(20, 20)
	if _title:
		_title.size = Vector2(sz.x - 320, 60)
		_title.position = Vector2(160, 18)
	if _subtitle:
		_subtitle.size = Vector2(sz.x, 30)
		_subtitle.position = Vector2(0, 90)
	if _content:
		_content.position = Vector2(0, 124)
		_content.size = Vector2(sz.x, sz.y - 124)
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
	if _corner_btn:
		_corner_btn.queue_free()
		_corner_btn = null
	_countdown_lbl = null
	_countdown_target = 0
	if not bool(_data.get("ok", false)):
		_render_message("This contest no longer exists.", "Back to Arena",
			func() -> void: game_manager.show_arena())
		return
	var meta: Dictionary = _data.get("meta", {})
	var status := String(meta.get("status", "lobby"))
	_title.text = ArenaUI.clamp_title(String(meta.get("title", "Contest")))
	_subtitle.text = "✦   %s   ·   %s   ✦" % [ContestManager.type_label(String(meta.get("type", ""))),
		ContestManager.diff_label(String(meta.get("difficulty", "easy")))]
	# Lobby lives in its own room; active/finished use the amphitheatre floor.
	var in_lobby := status == "lobby"
	_lobby_bg.visible = in_lobby
	_bg.visible = not in_lobby
	if not in_lobby:
		ArenaUI.set_bg_mode(_bg, "active")

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
	var is_full := members.size() >= ContestManager.MAX_MEMBERS

	# Two-column layout inside the banner frame: roster on the LEFT, share-ID on the
	# RIGHT. Columns sit inside the drape lines (~11% / 89% of width) so the flyers
	# have clear edge lanes.
	var roster_x := w * 0.12
	var roster_w: float = clampf(w * 0.40, 240.0, 400.0)
	var right_cx := clampf(w * 0.73, roster_x + roster_w + 180.0, w - 180.0)

	# Roster of registered players ("Friends in Lobby") on the LEFT.
	_add_roster(members, is_creator, Vector2(roster_x, 4.0), roster_w)

	# Stone plaque on the RIGHT: the shareable ID while there's room; once full, the
	# code is hidden and the plaque says the contest is full and ready to play.
	var plaque_w := 330.0
	var idbox := ArenaUI.stone_panel(ArenaUI.SAND)
	idbox.size = Vector2(plaque_w, 104)
	idbox.position = Vector2(right_cx - plaque_w * 0.5, 40.0)
	_content.add_child(idbox)
	if is_full:
		var fcap := Label.new()
		fcap.text = "CONTEST FULL"
		fcap.add_theme_font_size_override("font_size", 18)
		fcap.add_theme_color_override("font_color", ArenaUI.MUTED)
		fcap.position = Vector2(0, 20); fcap.size = Vector2(plaque_w, 22)
		fcap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fcap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		idbox.add_child(fcap)
		var fmsg := Label.new()
		fmsg.text = "Ready to play!"
		fmsg.add_theme_font_size_override("font_size", 34)
		fmsg.add_theme_color_override("font_color", ArenaUI.GOLD.lightened(0.15))
		fmsg.add_theme_color_override("font_outline_color", Color(0.28, 0.16, 0.03))
		fmsg.add_theme_constant_override("outline_size", 4)
		fmsg.position = Vector2(0, 48); fmsg.size = Vector2(plaque_w, 44)
		fmsg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fmsg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		idbox.add_child(fmsg)
	else:
		var idcap := Label.new()
		idcap.text = "SHARE THIS ID"
		idcap.add_theme_font_size_override("font_size", 14)
		idcap.add_theme_color_override("font_color", ArenaUI.MUTED)
		idcap.position = Vector2(0, 12); idcap.size = Vector2(plaque_w, 18)
		idcap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		idcap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		idbox.add_child(idcap)
		var idlbl := Label.new()
		idlbl.text = contest_id
		idlbl.add_theme_font_size_override("font_size", 46)
		idlbl.add_theme_color_override("font_color", ArenaUI.GOLD.lightened(0.15))
		idlbl.add_theme_color_override("font_outline_color", Color(0.28, 0.16, 0.03))
		idlbl.add_theme_constant_override("outline_size", 4)
		idlbl.position = Vector2(0, 34); idlbl.size = Vector2(plaque_w, 58)
		idlbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		idlbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		idbox.add_child(idlbl)
		var copy := ArenaUI.pill_button("⧉  Copy ID", ArenaUI.SAND)
		copy.size = Vector2(180, 46)
		copy.position = Vector2(right_cx - 90, 160.0)
		copy.pressed.connect(func() -> void:
			DisplayServer.clipboard_set(contest_id)
			_show_toast("Contest ID copied!"))
		_content.add_child(copy)
		var hint := Label.new()
		hint.text = "Share this ID so friends can join."
		hint.add_theme_font_size_override("font_size", 15)
		hint.add_theme_color_override("font_color", ArenaUI.MUTED)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hint.position = Vector2(right_cx - plaque_w * 0.5, 220.0)
		hint.size = Vector2(plaque_w, 22)
		_content.add_child(hint)

	# Two golden Simons rising up the far LEFT and RIGHT edge lanes (between the
	# screen edge and the banner drape lines). Slow, infrequent, staggered.
	var lanes := [{"side": -1.0, "x": w * 0.05, "delay": 0.5},
		{"side": 1.0, "x": w * 0.95, "delay": 4.0}]
	for lane in lanes:
		var flyer := SimonFlyer.new()
		_content.add_child(flyer)
		flyer.setup(_content.size, {
			"mode": "rise", "scale": 0.5, "side": lane["side"],
			"anchor_x": lane["x"], "dur": 6.6, "delay": lane["delay"],
			"amp": 22.0, "top_pad": _content.position.y + 40.0})

	# Buttons at the bottom.
	var by := _content.size.y - 78.0
	if is_creator:
		var start := ArenaUI.pill_button("▶  Start Contest", Color(0.30, 0.80, 0.52), true)
		start.size = Vector2(240, 56)
		start.position = Vector2(cx - 250, by)
		start.pressed.connect(_on_start)
		_content.add_child(start)
		var cancel := ArenaUI.pill_button("Cancel Contest", Color(0.80, 0.34, 0.34))
		cancel.size = Vector2(200, 56)
		cancel.position = Vector2(cx + 10, by)
		cancel.pressed.connect(_on_delete)
		_content.add_child(cancel)
	else:
		var leave := ArenaUI.pill_button("Leave Contest", Color(0.7, 0.4, 0.4))
		leave.size = Vector2(240, 56)
		leave.position = Vector2(cx - 120, by)
		leave.pressed.connect(_on_leave)
		_content.add_child(leave)

# ---------------- active ----------------

func _render_active(meta: Dictionary) -> void:
	var w := _content.size.x
	var h := _content.size.y
	var type := String(meta.get("type", ""))
	var is_creator := String(meta.get("creator_uid", "")) == FirebaseManager.uid
	var members: Array = _data.get("members", [])
	var my_member: Dictionary = _data.get("my_member", {})

	# An occasional golden Simon drifting across the floor.
	var flyer := SimonFlyer.new()
	_content.add_child(flyer)
	flyer.setup(_content.size, {"mode": "wander", "scale": 0.6})

	var now := int(Time.get_unix_time_from_system())
	var deadline := int(meta.get("deadline_at", 0))
	var past_deadline := type != "one_game" and deadline > 0 and now >= deadline

	# ---- split: played (ranked by score) then the yet-to-play (shuffled) ----
	var played: Array = []
	var unplayed: Array = []
	for m: Dictionary in members:
		if int(m.get("games_played", 0)) > 0:
			played.append(m)
		else:
			unplayed.append(m)
	played.sort_custom(func(a, b): return int(a.get("best_score", 0)) > int(b.get("best_score", 0)))
	unplayed.shuffle()

	# ---- styled time-left / status chip, top area ----
	var chip := _make_countdown_chip()
	chip.position = Vector2((w - chip.size.x) * 0.5, 6.0)
	_content.add_child(chip)
	if type == "one_game":
		var pending := 0
		for m in members:
			if not bool(m.get("done", false)):
				pending += 1
		_countdown_lbl.text = "%d still to finish" % pending
	elif past_deadline:
		_countdown_lbl.text = "Finishing…"
	else:
		_countdown_target = deadline
		_countdown_lbl.text = _fmt_countdown(maxi(0, deadline - now))

	var top_y := chip.position.y + chip.size.y + 14.0

	# ---- podium on the RIGHT (top 3 of the played) ----
	var right_cx := w * 0.70
	var pod_scale: float = clampf((w * 0.52) / 600.0, 0.44, 0.86)
	_add_stage(_ranked_to_standings(played.slice(0, 3)), right_cx, top_y + 8.0, pod_scale)

	# ---- table on the LEFT (ranks 4..N + the yet-to-play); always 7 slots ----
	var rest: Array = played.slice(3)
	rest.append_array(unplayed)
	var tw: float = clampf(w * 0.44, 220.0, 300.0)
	var lx := 24.0
	var row_h := 46.0
	var sep := 8.0
	var visible_rows := 7
	var table_h := visible_rows * row_h + (visible_rows - 1) * sep
	table_h = minf(table_h, h - top_y - 96.0)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.position = Vector2(lx, top_y)
	scroll.size = Vector2(tw, table_h)
	_content.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", int(sep))
	vb.custom_minimum_size = Vector2(tw, 0)
	scroll.add_child(vb)
	var played_rest := played.size() - 3          # how many table rows carry a real rank
	for i in rest.size():
		var m: Dictionary = rest[i]
		var rank := (4 + i) if i < played_rest else -1     # -1 → "—" (not played yet)
		vb.add_child(_make_active_row(m, rank, is_creator, tw, row_h))
	# Pad with empty slots so the table always shows 7 rows.
	for i in range(rest.size(), visible_rows):
		vb.add_child(_make_empty_row(tw, row_h))

	# ---- Cancel / Leave: top-right of the SCREEN, its right edge aligned with the
	# Play button's right edge (both sit 24px from the screen edge).
	_corner_btn = ArenaUI.pill_button("Cancel Contest" if is_creator else "Leave",
		Color(0.80, 0.40, 0.40))
	var corner_w := 172.0 if is_creator else 120.0
	_corner_btn.size = Vector2(corner_w, 46)
	_corner_btn.position = Vector2(get_viewport_rect().size.x - corner_w - 24, 20)
	_corner_btn.pressed.connect(_on_delete if is_creator else _on_leave)
	add_child(_corner_btn)

	# ---- Play: big, bottom-right corner ----
	var can_play := true
	if type == "one_game" and bool(my_member.get("done", false)):
		can_play = false
	if past_deadline:
		can_play = false
	if can_play:
		var play := ArenaUI.pill_button("▶  Play", Color(0.30, 0.80, 0.52), true)
		play.add_theme_font_size_override("font_size", 26)
		play.size = Vector2(300, 74)
		play.position = Vector2(w - 300 - 24, h - 74 - 24)
		play.pressed.connect(_on_play)
		_content.add_child(play)
	else:
		var doneb := ArenaUI.pill_button("✓ You've played", Color(0.4, 0.5, 0.5))
		doneb.disabled = true
		doneb.size = Vector2(300, 74)
		doneb.position = Vector2(w - 300 - 24, h - 74 - 24)
		_content.add_child(doneb)

	# One-game hosts can still finalize early — small, unobtrusive, bottom-left.
	if is_creator and type == "one_game":
		var endnow := ArenaUI.pill_button("End now", Color(0.9, 0.6, 0.3))
		endnow.size = Vector2(150, 50)
		endnow.position = Vector2(24, h - 50 - 24)
		endnow.pressed.connect(_on_finalize_now)
		_content.add_child(endnow)

# Map ranked live-member rows to the {name, score} shape the podium expects.
func _ranked_to_standings(rows: Array) -> Array:
	var out: Array = []
	for m: Dictionary in rows:
		out.append({
			"name": String(m.get("name", "Player")),
			"score": int(m.get("best_score", 0)),
		})
	return out

# Add the shared leaderboards-style podium (stage + medal blocks + trophy cups +
# swaying spotlights) centered at `center_x`, stage top near `top_y`, at `scale`.
func _add_stage(entries: Array, center_x: float, top_y: float, scale: float = 1.0) -> void:
	var stage := PodiumStage.new()
	stage.position = Vector2(center_x, top_y)
	stage.scale = Vector2.ONE * scale
	_content.add_child(stage)
	stage.setup(entries)
	stage.start_anim()

# A styled "time left" chip: a stone plaque with a drawn clock and the countdown
# label (kept in _countdown_lbl so _process can tick it). Replaces the plain banner.
func _make_countdown_chip() -> Panel:
	var chip := ArenaUI.stone_panel(ArenaUI.ACCENT)
	chip.size = Vector2(300, 52)
	var clock := Control.new()
	clock.size = Vector2(30, 52)
	clock.position = Vector2(18, 0)
	clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clock.draw.connect(_draw_clock.bind(clock))
	chip.add_child(clock)
	_countdown_lbl = Label.new()
	_countdown_lbl.add_theme_font_size_override("font_size", 24)
	_countdown_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7))
	_countdown_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown_lbl.position = Vector2(44, 0)
	_countdown_lbl.size = Vector2(300 - 44 - 14, 52)
	_countdown_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(_countdown_lbl)
	return chip

# A simple clock face (rim + two hands) for the countdown chip.
func _draw_clock(c: Control) -> void:
	var ctr := Vector2(15, 26)
	var gold := ArenaUI.ACCENT.lightened(0.3)
	c.draw_arc(ctr, 11.0, 0.0, TAU, 28, gold, 2.4, true)
	c.draw_line(ctr, ctr + Vector2(0, -7), gold, 2.2)
	c.draw_line(ctr, ctr + Vector2(5, 2), gold, 2.2)

# A left-table row (rank 4+), styled like the leaderboards ranks-table: a stroked
# rank circle, the name, and a green score on the right. A not-yet-played row shows
# a "—" circle and "…". `rank` < 0 marks the not-yet-played state.
func _make_active_row(m: Dictionary, rank: int, can_kick: bool, width: float, rh: float) -> Control:
	var uid := String(m.get("uid", ""))
	var is_me := uid == FirebaseManager.uid
	var played := rank > 0
	var row := Panel.new()
	row.custom_minimum_size = Vector2(width, rh)
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.16, 0.13, 0.05, 0.55) if is_me else Color(0.05, 0.07, 0.16, 0.5)
	s.set_corner_radius_all(10)
	var rim := ArenaUI.GOLD if is_me else Color(0.40, 0.45, 0.72)
	s.border_color = Color(rim.r, rim.g, rim.b, 0.8 if is_me else 0.16)
	s.set_border_width_all(2 if is_me else 1)
	row.add_theme_stylebox_override("panel", s)

	var rd := rh - 12.0
	var circle := _rank_circle(rd, "%d" % rank if played else "—", int(rd * 0.5),
		Color(0.82, 0.87, 1.0) if played else Color(0.6, 0.64, 0.85, 0.5))
	circle.position = Vector2(9, (rh - rd) * 0.5)
	row.add_child(circle)

	var name_x := 9.0 + rd + 10.0
	var nm := Label.new()
	nm.text = String(m.get("name", "Player")) + ("  (you)" if is_me else "")
	nm.add_theme_font_size_override("font_size", 17)
	nm.add_theme_color_override("font_color", ArenaUI.GOLD.lightened(0.3) if is_me else Color(0.84, 0.88, 0.98))
	nm.position = Vector2(name_x, 0); nm.size = Vector2(width - name_x - 76, rh)
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.clip_text = true
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(nm)
	var sc := Label.new()
	sc.text = str(int(m.get("best_score", 0))) if played else "…"
	sc.add_theme_font_size_override("font_size", 18 if played else 16)
	sc.add_theme_color_override("font_color", Color(0.44, 0.86, 0.52) if played else Color(0.55, 0.60, 0.85, 0.5))
	sc.position = Vector2(width - 72, 0); sc.size = Vector2(60, rh)
	sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sc)
	# Kick sits behind the score column; keep it only where there's a real member.
	if can_kick and not is_me:
		var kick := Button.new()
		kick.text = "✕"
		kick.focus_mode = Control.FOCUS_NONE
		var ks := StyleBoxFlat.new()
		ks.bg_color = Color(0.4, 0.12, 0.12, 0.85)
		ks.set_corner_radius_all(8)
		kick.add_theme_stylebox_override("normal", ks)
		kick.add_theme_color_override("font_color", Color(1, 0.85, 0.85))
		kick.size = Vector2(30, 28)
		kick.position = Vector2(width - 34, (rh - 28) * 0.5)
		var target_name := String(m.get("name", "Player"))
		kick.pressed.connect(func() -> void: _on_kick(uid, target_name))
		row.add_child(kick)
	return row

# A stroked rank circle (leaderboards style): a navy disc with a bright rim and a
# centered rank number (or "—").
func _rank_circle(d: float, text: String, font_size: int, text_col: Color) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(d, d)
	p.size = Vector2(d, d)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.08, 0.10, 0.22, 0.55)
	s.set_corner_radius_all(int(d * 0.5))
	s.border_color = Color(0.82, 0.86, 1.0, 0.35)
	s.set_border_width_all(2)
	p.add_theme_stylebox_override("panel", s)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", text_col)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return p

# An empty placeholder slot (faint row) so the table always fills 7 rows.
func _make_empty_row(width: float, rh: float) -> Control:
	var row := Panel.new()
	row.custom_minimum_size = Vector2(width, rh)
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.07, 0.16, 0.22)
	s.set_corner_radius_all(10)
	s.border_color = Color(0.40, 0.45, 0.72, 0.10)
	s.set_border_width_all(1)
	row.add_theme_stylebox_override("panel", s)
	var dash := Label.new()
	dash.text = "—"
	dash.add_theme_font_size_override("font_size", 15)
	dash.add_theme_color_override("font_color", Color(0.55, 0.60, 0.85, 0.28))
	dash.set_anchors_preset(Control.PRESET_FULL_RECT)
	dash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dash.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(dash)
	return row

# ---------------- finished ----------------

func _render_finished(meta: Dictionary) -> void:
	var w := _content.size.x
	var cx := w * 0.5
	var standings: Array = _data.get("standings", [])

	# Award contest-placement badges (win / podium) from the player's final rank.
	for r: Dictionary in standings:
		if bool(r.get("is_me", false)):
			BadgeManager.note_contest_result(int(r.get("rank", 0)))
			break

	# Celebration FX (behind the podium/table): heavy multicoloured confetti, pulsing
	# flash lights, and several golden Simons drifting across — the same wander path
	# as the active-contest screen.
	_add_finish_confetti()
	_add_finish_flashes()
	for i in 3:
		var flyer := SimonFlyer.new()
		_content.add_child(flyer)
		flyer.setup(_content.size, {"mode": "wander", "scale": 0.58,
			"top_pad": _content.position.y + 40.0})

	var champ := Label.new()
	champ.text = "Final Results"
	champ.add_theme_font_size_override("font_size", 26)
	champ.add_theme_color_override("font_color", ArenaUI.GOLD)
	champ.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	champ.position = Vector2(0, 0); champ.size = Vector2(w, 34)
	champ.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(champ)

	_add_stage(standings, cx, 44.0)

	# The top 3 stand on the podium; the table lists places 4+ only. It shows 5 slots
	# at a time (scrolls when fuller), padding with empty rows when there aren't 8.
	var rest: Array = standings.slice(3)
	var res_row_h := 44.0
	var res_sep := 6.0
	var res_visible := 5
	var table_top := 300.0
	var tw: float = minf(620.0, w - 80.0)
	var table_h := res_visible * res_row_h + (res_visible - 1) * res_sep
	table_h = minf(table_h, _content.size.y - table_top - 80.0)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.position = Vector2(cx - tw * 0.5, table_top)
	scroll.size = Vector2(tw, table_h)
	_content.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", int(res_sep))
	vb.custom_minimum_size = Vector2(tw, 0)
	scroll.add_child(vb)
	for r: Dictionary in rest:
		vb.add_child(_make_result_row(r, tw))
	# Pad with empty slots so the table always shows at least res_visible rows.
	for i in range(rest.size(), res_visible):
		vb.add_child(_make_empty_row(tw, res_row_h))

	var exit := ArenaUI.pill_button("Exit Contest", ArenaUI.ACCENT, true)
	exit.size = Vector2(240, 56)
	exit.position = Vector2(cx - 120, _content.size.y - 70.0)
	exit.pressed.connect(_on_exit)
	_content.add_child(exit)

# Heavy celebration confetti: one emitter per Simon colour (+ gold) raining from the
# top, so particles come in a mix of colours all at once.
func _add_finish_confetti() -> void:
	var cols: Array = SimonFlyer.SIMON_COLS.duplicate()
	cols.append(ArenaUI.GOLD)
	var flake := _confetti_flake()
	for col: Color in cols:
		var p := CPUParticles2D.new()
		p.texture = flake
		p.amount = 22
		p.lifetime = maxf(4.0, _content.size.y / 40.0)
		p.preprocess = p.lifetime          # pre-fill so it starts mid-air
		p.position = Vector2(_content.size.x * 0.5, -20.0)
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		p.emission_rect_extents = Vector2(_content.size.x * 0.5, 8.0)
		p.direction = Vector2(0, 1)
		p.spread = 32.0
		p.gravity = Vector2(0, 42.0)
		p.initial_velocity_min = 40.0
		p.initial_velocity_max = 120.0
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.4
		p.angle_min = -180.0
		p.angle_max = 180.0
		p.angular_velocity_min = -220.0
		p.angular_velocity_max = 220.0
		p.color = col
		_content.add_child(p)

# Pulsing coloured flash lights across the top band — extra sparkle for the finish.
func _add_finish_flashes() -> void:
	var cols: Array = SimonFlyer.SIMON_COLS.duplicate()
	cols.append(ArenaUI.GOLD)
	var n := 7
	for i in n:
		var col: Color = cols[i % cols.size()]
		var b := Sprite2D.new()
		b.texture = SimonFlyer.radial()
		b.modulate = Color(col.r, col.g, col.b, 0.0)
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		b.material = mat
		var base_scale := randf_range(0.9, 1.6)
		b.scale = Vector2.ONE * base_scale
		b.position = Vector2(_content.size.x * (0.10 + 0.80 * float(i) / float(n - 1)),
			randf_range(30.0, 150.0))
		_content.add_child(b)
		# Random-phase looping flash + gentle breathe.
		var dur := randf_range(0.7, 1.3)
		var tw := b.create_tween().set_loops()
		tw.tween_interval(randf_range(0.0, 1.2))
		tw.tween_property(b, "modulate:a", 0.55, dur).set_trans(Tween.TRANS_SINE)
		tw.tween_property(b, "modulate:a", 0.0, dur).set_trans(Tween.TRANS_SINE)

func _confetti_flake() -> Texture2D:
	var px := 10
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	for y in px:
		for x in px:
			var u := absf((float(x) + 0.5) / px * 2.0 - 1.0)
			var v := absf((float(y) + 0.5) / px * 2.0 - 1.0)
			var a := clampf((1.0 - maxf(u, v)) / 0.25, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)

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

# The registered players, titled "Friends in Lobby": a leaderboards-style table
# (navy rounded rows, gold-rimmed host/you) showing just names + a HOST/YOU tag.
# Always 7 slots tall — empty rows pad the gaps — and scrolls once fuller.
const ROSTER_VISIBLE := 7
const ROSTER_ROW_H := 46.0
const ROSTER_SEP := 8.0

func _add_roster(members: Array, can_kick: bool, pos: Vector2, width: float) -> void:
	# Section title over the table.
	var cap := Label.new()
	cap.text = "FRIENDS IN LOBBY"
	cap.add_theme_font_size_override("font_size", 20)
	cap.add_theme_color_override("font_color", ArenaUI.GOLD.lightened(0.1))
	cap.add_theme_color_override("font_shadow_color", Color(0.20, 0.40, 1.0, 0.35))
	cap.add_theme_constant_override("shadow_offset_y", 2)
	cap.add_theme_constant_override("shadow_outline_size", 7)
	cap.position = pos; cap.size = Vector2(width, 28)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(cap)

	# Inset so each row's rim sits INSIDE the scroll rect and isn't clipped.
	const PAD := 8
	var row_w := width - PAD * 2
	# Exactly ROSTER_VISIBLE rows visible; capped to whatever height is available.
	var table_h := ROSTER_VISIBLE * ROSTER_ROW_H + (ROSTER_VISIBLE - 1) * ROSTER_SEP + PAD * 2
	table_h = minf(table_h, _content.size.y - (pos.y + 34.0) - 96.0)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.position = Vector2(pos.x, pos.y + 34.0)
	scroll.size = Vector2(width, table_h)
	_content.add_child(scroll)
	var margin := MarginContainer.new()
	for m_side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m_side, PAD)
	margin.custom_minimum_size = Vector2(width, 0)
	scroll.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", int(ROSTER_SEP))
	margin.add_child(vb)
	for m: Dictionary in members:
		vb.add_child(_make_roster_row(m, can_kick, row_w))
	# Pad with empty slots so the table always shows at least ROSTER_VISIBLE rows.
	for i in range(members.size(), ROSTER_VISIBLE):
		vb.add_child(_make_empty_row(row_w, ROSTER_ROW_H))

const ROW_H := ROSTER_ROW_H

# A leaderboards-style roster row: a navy rounded panel with the name and a
# HOST / YOU tag (no rank/score). Host & you rows carry a warm gold rim.
func _make_roster_row(m: Dictionary, can_kick: bool, width: float) -> Control:
	var uid := String(m.get("uid", ""))
	var is_me := uid == FirebaseManager.uid
	var is_host := bool(m.get("is_creator", false))
	var row := Panel.new()
	row.custom_minimum_size = Vector2(width, ROW_H)
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.16, 0.13, 0.05, 0.55) if (is_host or is_me) else Color(0.05, 0.07, 0.16, 0.5)
	s.set_corner_radius_all(10)
	var rim := ArenaUI.GOLD if (is_host or is_me) else Color(0.40, 0.45, 0.72)
	s.border_color = Color(rim.r, rim.g, rim.b, 0.8 if (is_host or is_me) else 0.16)
	s.set_border_width_all(2 if (is_host or is_me) else 1)
	row.add_theme_stylebox_override("panel", s)

	var nm := Label.new()
	nm.text = String(m.get("name", "Player"))
	nm.add_theme_font_size_override("font_size", 18)
	nm.add_theme_color_override("font_color", ArenaUI.GOLD.lightened(0.3) if is_host else (ArenaUI.GOLD.lightened(0.3) if is_me else Color(0.84, 0.88, 0.98)))
	nm.position = Vector2(14, 0); nm.size = Vector2(width - 14 - 120, ROW_H)
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.clip_text = true
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(nm)

	# HOST / YOU chip on the right.
	var chip_txt := ""
	if is_host:
		chip_txt = "HOST"
	elif is_me:
		chip_txt = "YOU"
	if chip_txt != "":
		var chip := _make_chip(chip_txt, ArenaUI.GOLD if is_host else Color(0.55, 0.75, 1.0))
		var chip_right: float = (width - 48.0) if (can_kick and not is_me) else (width - 14.0)
		chip.position = Vector2(chip_right - chip.size.x, (ROW_H - 28) * 0.5)
		row.add_child(chip)

	# Creator may kick anyone but themselves.
	if can_kick and not is_me:
		var kick := Button.new()
		kick.text = "✕"
		kick.focus_mode = Control.FOCUS_NONE
		kick.add_theme_font_size_override("font_size", 16)
		var ks := StyleBoxFlat.new()
		ks.bg_color = Color(0.4, 0.12, 0.12, 0.85)
		ks.set_corner_radius_all(8)
		kick.add_theme_stylebox_override("normal", ks)
		var kh := ks.duplicate() as StyleBoxFlat
		kh.bg_color = Color(0.55, 0.15, 0.15, 0.95)
		kick.add_theme_stylebox_override("hover", kh)
		kick.add_theme_color_override("font_color", Color(1, 0.85, 0.85))
		kick.size = Vector2(30, 30)
		kick.position = Vector2(width - 38, (ROW_H - 30) * 0.5)
		var target_name := String(m.get("name", "Player"))
		kick.pressed.connect(func() -> void: _on_kick(uid, target_name))
		row.add_child(kick)
	return row

# A small rounded pill chip with a bold label.
func _make_chip(text: String, accent: Color) -> Control:
	var w: float = 34.0 + text.length() * 10.0
	var chip := Panel.new()
	chip.size = Vector2(w, 28)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(accent.r, accent.g, accent.b, 0.20)
	cs.set_corner_radius_all(14)
	cs.border_color = Color(accent.r, accent.g, accent.b, 0.85)
	cs.set_border_width_all(1)
	chip.add_theme_stylebox_override("panel", cs)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", accent.lightened(0.4))
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(l)
	return chip

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
	# Stop the lobby/menu music before the game — otherwise it keeps playing over
	# gameplay (normal play stops it on the home screen's Start button).
	AudioManager.stop_bg_music()
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

func _on_delete() -> void:
	_show_confirm("Cancel this contest for everyone?\nThis can't be undone.", func() -> void:
		_set_overlay(true, "Deleting…")
		await ContestManager.delete_contest(contest_id)
		if not is_inside_tree():
			return
		game_manager.show_arena())

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
	_overlay.z_index = 90     # above spotlight beams (z_index = 1)
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
	_toast.z_index = 110
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
	# Draw above the podium spotlight beams (which carry z_index = 1).
	_confirm.z_index = 100
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
