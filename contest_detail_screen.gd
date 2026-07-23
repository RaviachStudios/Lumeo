extends Control

const ArenaUI := preload("res://arena_ui.gd")
const PodiumStage := preload("res://podium_stage.gd")
const SimonFlyer := preload("res://simon_flyer.gd")

# Live room — three faces driven by the room's status, kept in sync by a Firestore
# document listener (ContestManager.room_changed):
#   lobby    : share ID, live roster (+kick), Start (creator), Leave/Cancel
#   playing  : if I haven't raced yet -> jump straight into the game; otherwise a
#              live "who's still racing / who finished" board (+ creator Finish now)
#   finished : podium + full standings, Exit only
#
# When the creator presses Start, the status flips to "playing" for everyone at
# once and every client auto-launches its match on the shared seed.

var game_manager: Node
var contest_id: String = ""

var _bg: ColorRect              # amphitheatre (playing / finished)
var _lobby_bg: ColorRect        # the distinct champions' antechamber (lobby)
var _back: Button
var _corner_btn: Button         # playing/results: Cancel/Leave, top-right (mirrors Back)
var _title: Label               # the room's big carved name
var _subtitle: Label            # difficulty, under the name
var _content: Control          # cleared + rebuilt per render
var _overlay: Panel
var _overlay_lbl: Label
var _toast: Label

# Confirm modal.
var _confirm: Panel
var _confirm_lbl: Label
var _confirm_yes_cb: Callable

var _room: Dictionary = {}       # shaped room (see ContestManager._shape_room)
var _busy := false
var _launched := false           # guard: only auto-launch my match once
var _finalize_sent := false      # guard: only nudge the all-done finalize once
var _seen_uids := {}             # roster uids already animated in (slide-in only for newcomers)
var _host_popped := false        # host badge "pop" plays once, not on every re-render

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
	_title = ArenaUI.big_title("ROOM")
	add_child(_title)
	# Fancy difficulty plaque under the title.
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
	_initial_load()

func _exit_tree() -> void:
	if ContestManager.room_changed.is_connected(_on_room_changed):
		ContestManager.room_changed.disconnect(_on_room_changed)
	ContestManager.unwatch_room(contest_id)

func _on_resize() -> void:
	_layout_static()
	if not _room.is_empty():
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

# ---------------- load / live watch ----------------

func _initial_load() -> void:
	_busy = true
	_set_overlay(true, "Loading…")
	_room = await ContestManager.load_room(contest_id)
	if not is_inside_tree():
		return
	_set_overlay(false)
	_busy = false
	_render()
	# Go live: subsequent changes (joins, start, scores, finish) push in.
	if not ContestManager.room_changed.is_connected(_on_room_changed):
		ContestManager.room_changed.connect(_on_room_changed)
	ContestManager.watch_room(contest_id)

func _on_room_changed(cid: String, room: Dictionary) -> void:
	if cid != contest_id:
		return
	_room = room
	if is_inside_tree():
		_render()

# ---------------- render dispatch ----------------

func _render() -> void:
	for c in _content.get_children():
		c.queue_free()
	if _corner_btn:
		_corner_btn.queue_free()
		_corner_btn = null
	if _room.is_empty():
		_render_message("This room no longer exists.", "Back to Arena",
			func() -> void: game_manager.show_arena())
		return

	var status := String(_room.get("status", "lobby"))
	_title.text = ArenaUI.clamp_title(String(_room.get("title", "Room")))
	var diff := String(_room.get("difficulty", "easy"))
	_subtitle.text = "✦   %s   ✦" % ContestManager.diff_label(diff)
	var dcol := _diff_color(diff)
	_subtitle.add_theme_color_override("font_color", dcol)
	_subtitle.add_theme_color_override("font_outline_color", dcol.darkened(0.72))
	_subtitle.add_theme_color_override("font_shadow_color", Color(dcol.r, dcol.g, dcol.b, 0.4))
	# Lobby lives in its own room; playing/finished use the amphitheatre floor.
	var in_lobby := status == "lobby"
	# The lobby draws its own refined difficulty badge under the title, so the plain
	# outlined subtitle is hidden there (kept for the playing / finished faces).
	_subtitle.visible = not in_lobby
	_lobby_bg.visible = in_lobby
	_bg.visible = not in_lobby
	if not in_lobby:
		ArenaUI.set_bg_mode(_bg, "active")

	if status == "finished":
		_render_finished()
		return

	var players: Dictionary = _room.get("players", {})
	var my: Dictionary = players.get(FirebaseManager.uid, {})
	var i_am_member := not my.is_empty() and String(my.get("state", "")) != "left"
	if not i_am_member:
		_render_message("You're no longer in this room.", "Back to Arena",
			func() -> void: game_manager.show_arena())
		return

	if status == "lobby":
		_render_lobby()
	else:
		# status == "playing"
		if String(my.get("state", "")) == "done":
			_render_results()
		else:
			_route_into_game()

# Active (non-left) players as roster dicts: {uid, name, is_creator, state, score}.
func _active_players() -> Array:
	var players: Dictionary = _room.get("players", {})
	var out: Array = []
	for uid in players:
		var p: Dictionary = players[uid]
		if String(p.get("state", "")) == "left":
			continue
		out.append({
			"uid": uid, "name": String(p.get("name", "Player")),
			"is_creator": bool(p.get("is_creator", false)),
			"state": String(p.get("state", "lobby")), "score": int(p.get("score", 0)),
		})
	return out

# ---------------- lobby ----------------

func _render_lobby() -> void:
	var w := _content.size.x
	var h := _content.size.y
	var cx := w * 0.5
	var is_creator := String(_room.get("creator_uid", "")) == FirebaseManager.uid
	var members := _active_players()
	var is_full := members.size() >= ContestManager.MAX_MEMBERS

	# Calm ambience behind everything: a soft radial pool of warm light, a subtle glow
	# behind the centre of the screen, slow gold motes and faint twinkling stars (added
	# first so all widgets sit on top).
	_add_lobby_ambience(w, h)

	# The difficulty setting under the title: a tracked caption, the sculpted badge and a
	# short gold divider — the lobby's single, quiet secondary line (no tagline beneath).
	var diff := String(_room.get("difficulty", "easy"))
	var dcol := _diff_color(diff)
	# "DIFFICULTY" caption makes the badge read as an actual game setting, not a floating tag.
	var diff_cap := Label.new()
	diff_cap.text = "D I F F I C U L T Y"
	diff_cap.add_theme_font_size_override("font_size", 12)
	diff_cap.add_theme_color_override("font_color", Color(0.82, 0.86, 0.98, 0.60))
	diff_cap.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.12, 0.7))
	diff_cap.add_theme_constant_override("outline_size", 2)
	diff_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	diff_cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	diff_cap.position = Vector2(0, -24); diff_cap.size = Vector2(w, 16)
	_content.add_child(diff_cap)
	var badge := _make_diff_badge(ContestManager.diff_label(diff), dcol)
	var badge_y := -4.0
	badge.position = Vector2(cx - badge.size.x * 0.5, badge_y)
	_content.add_child(badge)
	var divider := _make_divider(240.0)
	var div_y := badge_y + badge.size.y + 12.0
	divider.position = Vector2(cx - 120.0, div_y)
	_content.add_child(divider)

	# --- a balanced two-column body: roster on the LEFT, Room-ID card on the RIGHT,
	# centred as a deliberate pair with a generous gutter between them ---
	var top := 122.0
	var by := h - 96.0                          # primary-action baseline
	var roster_bottom := by - 48.0              # clear of the bottom action buttons
	# Both main panels carry ~10% more presence than before (roster + Room-ID card).
	var plaque_w := 396.0
	var plaque_h := 134.0
	var roster_w: float = clampf(w * 0.396, 330.0, 418.0)
	var gutter: float = clampf(w * 0.08, 52.0, 104.0)
	var group_w := roster_w + gutter + plaque_w
	var max_group := w - 96.0
	if group_w > max_group:                       # shrink together to fit narrow screens
		var shrink := max_group / group_w
		roster_w *= shrink
		plaque_w *= shrink
		gutter *= shrink
		group_w = max_group
	var cols_x := (w - group_w) * 0.5
	var roster_x := cols_x - 24.0                # nudged left
	var right_cx := cols_x + roster_w + gutter + plaque_w * 0.5 + 28.0   # nudged right

	# The roster sits a touch higher than the Room-ID column so its title clears the divider.
	_add_roster(members, is_creator, Vector2(roster_x, top - 44.0), roster_w, roster_bottom)

	# The Room-ID cluster (plaque + Copy + hint) is vertically centred against the roster
	# so the two columns sit as an even, balanced pair — lifted a touch higher.
	var cluster_h := plaque_h + 18.0 + 54.0 + 42.0
	var cluster_top: float = maxf(top - 64.0, top + ((roster_bottom - top) - cluster_h) * 0.5 - 64.0)

	# A premium Room-ID card: a sculpted gold tablet (bevelled body, gold rim, outer bloom,
	# top specular, convex sheen) with the code as the hero element.
	var idbox := _make_plaque_3d(ArenaUI.SAND)
	idbox.size = Vector2(plaque_w, plaque_h)
	idbox.position = Vector2(right_cx - plaque_w * 0.5, cluster_top)
	_content.add_child(idbox)
	if is_full:
		var fcap := Label.new()
		fcap.text = "ROOM FULL"
		fcap.add_theme_font_size_override("font_size", 18)
		fcap.add_theme_color_override("font_color", ArenaUI.SAND.lightened(0.18))
		fcap.add_theme_color_override("font_outline_color", Color(0.10, 0.06, 0.02, 0.85))
		fcap.add_theme_constant_override("outline_size", 2)
		fcap.position = Vector2(0, 26); fcap.size = Vector2(plaque_w, 22)
		fcap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fcap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		idbox.add_child(fcap)
		var fmsg := Label.new()
		fmsg.text = "Ready to play!"
		fmsg.add_theme_font_size_override("font_size", 34)
		fmsg.add_theme_color_override("font_color", ArenaUI.GOLD.lightened(0.15))
		fmsg.add_theme_color_override("font_outline_color", Color(0.28, 0.16, 0.03))
		fmsg.add_theme_constant_override("outline_size", 4)
		fmsg.add_theme_color_override("font_shadow_color", Color(1.0, 0.6, 0.2, 0.4))
		fmsg.add_theme_constant_override("shadow_offset_y", 2)
		fmsg.add_theme_constant_override("shadow_outline_size", 9)
		fmsg.position = Vector2(0, 56); fmsg.size = Vector2(plaque_w, 44)
		fmsg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fmsg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		idbox.add_child(fmsg)
	else:
		var idcap := Label.new()
		# Flourished, letter-spaced caption with diamond bookends — reads as an engraved
		# banner rather than a plain label.
		idcap.text = "◆  R O O M   I D  ◆"
		idcap.add_theme_font_size_override("font_size", 19)
		idcap.add_theme_color_override("font_color", ArenaUI.GOLD.lightened(0.28))
		idcap.add_theme_color_override("font_outline_color", Color(0.24, 0.13, 0.02, 0.95))
		idcap.add_theme_constant_override("outline_size", 4)
		idcap.add_theme_color_override("font_shadow_color", Color(1.0, 0.66, 0.22, 0.55))
		idcap.add_theme_constant_override("shadow_offset_y", 1)
		idcap.add_theme_constant_override("shadow_outline_size", 8)
		idcap.position = Vector2(0, 12); idcap.size = Vector2(plaque_w, 24)
		idcap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		idcap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		idbox.add_child(idcap)
		# A gentle shimmer so the caption catches the eye without competing with the code.
		var cap_tw := idcap.create_tween().set_loops()
		cap_tw.tween_property(idcap, "modulate:a", 0.72, 1.4).set_trans(Tween.TRANS_SINE)
		cap_tw.tween_property(idcap, "modulate:a", 1.0, 1.4).set_trans(Tween.TRANS_SINE)
		# A warm gold glow pooled behind the ID that breathes on a loop — bright for 2s,
		# dark for 5s (see the tween below).
		var glow := Control.new()
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glow.position = Vector2(0, 34)
		glow.size = Vector2(plaque_w, 74)
		glow.draw.connect(_draw_id_glow.bind(glow))
		glow.modulate.a = 0.0
		idbox.add_child(glow)
		var gt := glow.create_tween().set_loops()
		gt.tween_property(glow, "modulate:a", 1.0, 0.55).set_trans(Tween.TRANS_SINE)
		gt.tween_interval(0.9)                                 # ~2s glowing in total
		gt.tween_property(glow, "modulate:a", 0.0, 0.55).set_trans(Tween.TRANS_SINE)
		gt.tween_interval(5.0)                                 # 5s fully dark
		# The room code is the hero of the card — big, bright, gold, centred.
		var idlbl := Label.new()
		idlbl.text = contest_id
		idlbl.add_theme_font_size_override("font_size", 54)
		idlbl.add_theme_color_override("font_color", ArenaUI.GOLD.lightened(0.15))
		idlbl.add_theme_color_override("font_outline_color", Color(0.28, 0.16, 0.03))
		idlbl.add_theme_constant_override("outline_size", 4)
		idlbl.add_theme_color_override("font_shadow_color", Color(1.0, 0.66, 0.22, 0.5))
		idlbl.add_theme_constant_override("shadow_offset_y", 2)
		idlbl.add_theme_constant_override("shadow_outline_size", 12)
		idlbl.position = Vector2(0, 34); idlbl.size = Vector2(plaque_w, 74)
		idlbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		idlbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		idlbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		idbox.add_child(idlbl)
		# A cleaner, tactile Copy button: quieter bloom, larger copy glyph, a shrink-pop
		# and a "Copied!" checkmark on press (see _on_copy_pressed).
		var copy := _make_button_3d("⧉  Copy ID", ArenaUI.SAND)
		copy.size = Vector2(220, 54)
		copy.position = Vector2(right_cx - 110, cluster_top + plaque_h + 18.0)
		copy.set_meta("copy_default", "⧉  Copy ID")
		copy.pressed.connect(_on_copy_pressed.bind(copy))
		_content.add_child(copy)
		# A soft light-sweep glides across Copy ID every ~9s (premium, unobtrusive).
		_add_shimmer(copy, 8.5, 0.16, 2.0)
		var hint := Label.new()
		hint.text = "Share this ID so friends can join."
		hint.add_theme_font_size_override("font_size", 15)
		hint.add_theme_color_override("font_color", Color(0.88, 0.82, 0.68))
		hint.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.02, 0.45))
		hint.add_theme_constant_override("shadow_offset_y", 1)
		hint.add_theme_constant_override("shadow_outline_size", 4)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hint.position = Vector2(right_cx - plaque_w * 0.5, cluster_top + plaque_h + 82.0)
		hint.size = Vector2(plaque_w, 22)
		_content.add_child(hint)

	# Two golden Simons rising up the far LEFT and RIGHT edge lanes.
	var lanes := [{"side": -1.0, "x": w * 0.05, "delay": 0.5},
		{"side": 1.0, "x": w * 0.95, "delay": 4.0}]
	for lane in lanes:
		var flyer := SimonFlyer.new()
		_content.add_child(flyer)
		flyer.setup(_content.size, {
			"mode": "rise", "scale": 0.5, "side": lane["side"],
			"anchor_x": lane["x"], "dur": 6.6, "delay": lane["delay"],
			"amp": 22.0, "top_pad": _content.position.y + 40.0})

	# Primary actions at the bottom. Start Race is the clear hero — larger, richly lit,
	# with a soft green bloom — while Cancel Room is a quiet ghost button that stays
	# legible without competing for attention.
	if is_creator:
		var sw := 262.0
		var sh := 72.0
		var cw := 150.0
		var ch := 52.0
		var group_gap := 44.0
		# Start Race is the screen's anchor: perfectly centred and dropped a touch lower.
		var drop := 26.0
		var start_y := by - (sh - 58.0) + drop
		var start_x := cx - sw * 0.5
		var start := _make_button_3d("▶  Start Race", Color(0.26, 0.80, 0.47), true)
		start.size = Vector2(sw, sh)
		start.position = Vector2(start_x, start_y)
		start.pressed.connect(_on_start)
		_content.add_child(start)
		# A very subtle breathing so the hero feels alive (~1.00 → 1.02 → 1.00 every ~4.4s).
		start.pivot_offset = Vector2(sw, sh) * 0.5
		var bt := start.create_tween().set_loops()
		bt.tween_property(start, "scale", Vector2(1.02, 1.02), 2.2).set_trans(Tween.TRANS_SINE)
		bt.tween_property(start, "scale", Vector2.ONE, 2.2).set_trans(Tween.TRANS_SINE)
		# Cancel Room is a quiet, muted grayish-red ghost that sits to the right and never
		# competes with the hero.
		var cancel := _make_ghost_button("Cancel Room", Color(0.52, 0.35, 0.35))
		cancel.size = Vector2(cw, ch)
		cancel.position = Vector2(start_x + sw + group_gap, start_y + (sh - ch) * 0.5)
		cancel.pressed.connect(_on_cancel)
		_content.add_child(cancel)
	else:
		var leave := _make_button_3d("Leave Room", Color(0.7, 0.4, 0.4))
		leave.size = Vector2(240, 58)
		leave.position = Vector2(cx - 120, by)
		leave.pressed.connect(_on_leave)
		_content.add_child(leave)

# ---------------- playing: auto-launch my match ----------------

func _route_into_game() -> void:
	if _launched:
		_set_overlay(true, "Get ready…")
		return
	_launched = true
	_set_overlay(true, "Get ready…")
	# Stop the lobby/menu music before the game.
	AudioManager.stop_bg_music()
	await ContestManager.begin_contest_game(contest_id,
		String(_room.get("difficulty", "easy")), int(_room.get("seed", 0)))
	if not is_inside_tree():
		return
	game_manager.show_game()

# ---------------- playing: live results / waiting board ----------------

func _render_results() -> void:
	var w := _content.size.x
	var h := _content.size.y
	var cx := w * 0.5
	var is_creator := String(_room.get("creator_uid", "")) == FirebaseManager.uid
	var members := _active_players()

	# An occasional golden Simon drifting across the floor.
	var flyer := SimonFlyer.new()
	_content.add_child(flyer)
	flyer.setup(_content.size, {"mode": "wander", "scale": 0.6})

	# Split: finished (ranked by score) then still racing.
	var done: Array = []
	var racing: Array = []
	for m: Dictionary in members:
		if String(m.get("state", "")) == "done":
			done.append(m)
		else:
			racing.append(m)
	done.sort_custom(func(a, b): return int(a.get("score", 0)) > int(b.get("score", 0)))

	# Safety net: if everyone's already done but the room hasn't flipped to finished
	# (e.g. the last finisher's read was stale), nudge it — any participant may.
	if racing.is_empty() and not _finalize_sent:
		_finalize_sent = true
		ContestManager.finalize_if_done(contest_id)

	# Status chip: "N of M finished".
	var chip := ArenaUI.stone_panel(ArenaUI.ACCENT)
	chip.size = Vector2(320, 52)
	chip.position = Vector2((w - 320) * 0.5, 6.0)
	_content.add_child(chip)
	var chip_lbl := Label.new()
	chip_lbl.text = "%d of %d finished" % [done.size(), members.size()]
	chip_lbl.add_theme_font_size_override("font_size", 24)
	chip_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7))
	chip_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	chip_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(chip_lbl)

	var top_y := chip.position.y + chip.size.y + 18.0
	var note := Label.new()
	note.text = "Waiting for everyone to finish their race…"
	note.add_theme_font_size_override("font_size", 16)
	note.add_theme_color_override("font_color", ArenaUI.MUTED)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.position = Vector2(0, top_y); note.size = Vector2(w, 22)
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(note)

	# One combined table: finished first (with score + rank), then still-racing.
	var ordered: Array = done.duplicate()
	ordered.append_array(racing)
	var row_h := 46.0
	var sep := 8.0
	var visible_rows := 7
	var tw: float = clampf(w * 0.6, 320.0, 560.0)
	var table_top := top_y + 34.0
	var table_h := visible_rows * row_h + (visible_rows - 1) * sep
	table_h = minf(table_h, h - table_top - 96.0)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.position = Vector2(cx - tw * 0.5, table_top)
	scroll.size = Vector2(tw, table_h)
	_content.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", int(sep))
	vb.custom_minimum_size = Vector2(tw, 0)
	scroll.add_child(vb)
	for i in ordered.size():
		var m: Dictionary = ordered[i]
		var is_done := String(m.get("state", "")) == "done"
		var rank := (i + 1) if is_done else -1
		vb.add_child(_make_status_row(m, rank, is_done, tw, row_h))
	for i in range(ordered.size(), visible_rows):
		vb.add_child(_make_empty_row(tw, row_h))

	# Cancel / Leave: top-right corner.
	_corner_btn = ArenaUI.pill_button("Cancel Room" if is_creator else "Leave",
		Color(0.80, 0.40, 0.40))
	var corner_w := 160.0 if is_creator else 120.0
	_corner_btn.size = Vector2(corner_w, 46)
	_corner_btn.position = Vector2(get_viewport_rect().size.x - corner_w - 24, 20)
	_corner_btn.pressed.connect(_on_cancel if is_creator else _on_leave)
	add_child(_corner_btn)

	# Creator may end the race early, locking in current scores.
	if is_creator and not racing.is_empty():
		var endnow := ArenaUI.pill_button("Finish now", Color(0.9, 0.6, 0.3))
		endnow.size = Vector2(180, 52)
		endnow.position = Vector2(cx - 90, h - 52 - 20)
		endnow.pressed.connect(_on_finish_now)
		_content.add_child(endnow)

# A results-board row: rank circle (or "•" while racing), name, and score or a
# "Racing…" tag.
func _make_status_row(m: Dictionary, rank: int, is_done: bool, width: float, rh: float) -> Control:
	var uid := String(m.get("uid", ""))
	var is_me := uid == FirebaseManager.uid
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
	var circle := _rank_circle(rd, "%d" % rank if is_done else "•", int(rd * 0.5),
		Color(0.82, 0.87, 1.0) if is_done else Color(0.6, 0.64, 0.85, 0.6))
	circle.position = Vector2(9, (rh - rd) * 0.5)
	row.add_child(circle)

	var name_x := 9.0 + rd + 10.0
	var nm := Label.new()
	nm.text = String(m.get("name", "Player")) + ("  (you)" if is_me else "")
	nm.add_theme_font_size_override("font_size", 17)
	nm.add_theme_color_override("font_color", ArenaUI.GOLD.lightened(0.3) if is_me else Color(0.84, 0.88, 0.98))
	nm.position = Vector2(name_x, 0); nm.size = Vector2(width - name_x - 116, rh)
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.clip_text = true
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(nm)

	var sc := Label.new()
	sc.text = str(int(m.get("score", 0))) if is_done else "Racing…"
	sc.add_theme_font_size_override("font_size", 18 if is_done else 15)
	sc.add_theme_color_override("font_color", Color(0.44, 0.86, 0.52) if is_done else Color(0.7, 0.75, 0.5, 0.9))
	sc.position = Vector2(width - 112, 0); sc.size = Vector2(100, rh)
	sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sc)
	return row

# Add the shared leaderboards-style podium centered at `center_x`, top near
# `top_y`, at `scale`.
func _add_stage(entries: Array, center_x: float, top_y: float, scale: float = 1.0) -> void:
	var stage := PodiumStage.new()
	stage.position = Vector2(center_x, top_y)
	stage.scale = Vector2.ONE * scale
	_content.add_child(stage)
	stage.setup(entries)
	stage.start_anim()

# A stroked rank circle (leaderboards style).
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

# An empty placeholder slot (faint row) so tables fill to a fixed height.
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

func _render_finished() -> void:
	var w := _content.size.x
	var cx := w * 0.5
	var standings: Array = ContestManager.standings_from_room(_room)

	# Award contest-placement badges (win / podium) from the player's final rank.
	for r: Dictionary in standings:
		if bool(r.get("is_me", false)):
			BadgeManager.note_contest_result(int(r.get("rank", 0)))
			break

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

	# Top 3 stand on the podium; the table lists places 4+.
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
	for i in range(rest.size(), res_visible):
		vb.add_child(_make_empty_row(tw, res_row_h))

	var exit := ArenaUI.pill_button("Exit", ArenaUI.ACCENT, true)
	exit.size = Vector2(240, 56)
	exit.position = Vector2(cx - 120, _content.size.y - 70.0)
	exit.pressed.connect(_on_exit)
	_content.add_child(exit)

func _add_finish_confetti() -> void:
	var cols: Array = SimonFlyer.SIMON_COLS.duplicate()
	cols.append(ArenaUI.GOLD)
	var flake := _confetti_flake()
	for col: Color in cols:
		var p := CPUParticles2D.new()
		p.texture = flake
		p.amount = 22
		p.lifetime = maxf(4.0, _content.size.y / 40.0)
		p.preprocess = p.lifetime
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
	nm.position = Vector2(76, 0); nm.size = Vector2(width - 200, 44)
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nm.clip_text = true
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(nm)
	var sc := Label.new()
	sc.text = "%d" % int(r.get("score", 0))
	sc.add_theme_font_size_override("font_size", 18)
	sc.add_theme_color_override("font_color", Color(0.44, 0.86, 0.52))
	sc.position = Vector2(width - 120, 0); sc.size = Vector2(106, 44)
	sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sc)
	return row

func _diff_color(diff: String) -> Color:
	match diff:
		"easy":     return Color(0.40, 0.85, 0.55)
		"moderate": return Color(1.00, 0.75, 0.35)
		"hard":     return Color(0.97, 0.45, 0.52)
	return ArenaUI.GOLD.lightened(0.2)

# ---------------- roster rows (lobby) ----------------

const ROSTER_VISIBLE := 5
const ROSTER_ROW_H := 46.0
const ROSTER_SEP := 8.0

func _add_roster(members: Array, can_kick: bool, pos: Vector2, width: float, bottom: float) -> void:
	const PAD := 14
	const HEADER_H := 46.0
	const SCROLL_GAP := 10.0
	const VB_SEP := 10.0
	# The table hugs its contents: one row per player, growing as people join. It only
	# starts scrolling once past ROSTER_VISIBLE players — below that it stays compact
	# (1 player → 1 row, 2 → 2 rows, … up to the cap).
	var visible_rows: int = clampi(members.size(), 1, ROSTER_VISIBLE)
	var rows_h := visible_rows * ROSTER_ROW_H + maxf(0.0, visible_rows - 1) * VB_SEP
	var panel_h := HEADER_H + SCROLL_GAP + rows_h + PAD
	# Never spill past the space available above the action buttons.
	var avail := bottom - pos.y
	if avail > 0.0:
		panel_h = minf(panel_h, avail)

	# Elegant dark panel with a thin gold frame + soft contact shadow enclosing the
	# whole roster — reads as a premium multiplayer room list, not loose rows.
	var panel := Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.position = pos
	panel.size = Vector2(width, panel_h)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.05, 0.06, 0.12, 0.62)
	ps.set_corner_radius_all(20)
	ps.border_color = Color(ArenaUI.GOLD.r, ArenaUI.GOLD.g, ArenaUI.GOLD.b, 0.46)
	ps.set_border_width_all(1)
	# A large, low-opacity contact shadow reads as soft depth rather than a hard drop.
	ps.shadow_color = Color(0.0, 0.0, 0.02, 0.4)
	ps.shadow_size = 26
	ps.shadow_offset = Vector2(0, 10)
	panel.add_theme_stylebox_override("panel", ps)
	_content.add_child(panel)

	# Header: caption on the left, a compact roster count on the right, a hairline rule.
	var cap := Label.new()
	cap.text = "PLAYERS IN LOBBY"
	cap.add_theme_font_size_override("font_size", 18)
	cap.add_theme_color_override("font_color", ArenaUI.GOLD.lightened(0.12))
	cap.add_theme_color_override("font_outline_color", Color(0.10, 0.06, 0.02, 0.75))
	cap.add_theme_constant_override("outline_size", 2)
	cap.position = Vector2(PAD + 2, 6); cap.size = Vector2(width - PAD * 2 - 74, HEADER_H - 8)
	cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(cap)

	var cnt := _make_chip("%d/%d" % [members.size(), ContestManager.MAX_MEMBERS], Color(0.55, 0.75, 1.0))
	cnt.position = Vector2(width - PAD - cnt.size.x, (HEADER_H - cnt.size.y) * 0.5 + 1.0)
	panel.add_child(cnt)

	var rule := Panel.new()
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rs := StyleBoxFlat.new()
	rs.bg_color = Color(ArenaUI.GOLD.r, ArenaUI.GOLD.g, ArenaUI.GOLD.b, 0.22)
	rule.add_theme_stylebox_override("panel", rs)
	rule.position = Vector2(PAD, HEADER_H); rule.size = Vector2(width - PAD * 2, 1.0)
	panel.add_child(rule)

	# Roster rows in a scroll below the header; comfortable spacing, snug padding.
	var row_w := width - PAD * 2
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.position = Vector2(PAD, HEADER_H + 10.0)
	scroll.size = Vector2(row_w, panel_h - HEADER_H - 10.0 - PAD)
	panel.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.custom_minimum_size = Vector2(row_w, 0)
	scroll.add_child(vb)
	# Only players who weren't in the roster last render slide in; everyone else appears
	# settled, so a routine re-render (score push, resize) doesn't re-animate the list.
	var current := {}
	for m: Dictionary in members:
		var uid := String(m.get("uid", ""))
		current[uid] = true
		var is_new := not _seen_uids.has(uid)
		_seen_uids[uid] = true
		vb.add_child(_make_roster_row(m, can_kick, row_w, is_new))
	# Forget players who have left so a later re-join animates in again.
	for uid in _seen_uids.keys():
		if not current.has(uid):
			_seen_uids.erase(uid)

const ROW_H := ROSTER_ROW_H

func _make_roster_row(m: Dictionary, can_kick: bool, width: float, animate := false) -> Control:
	var uid := String(m.get("uid", ""))
	var is_me := uid == FirebaseManager.uid
	var is_host := bool(m.get("is_creator", false))
	var pname := String(m.get("name", "Player"))
	var highlight := is_host or is_me
	var row := Panel.new()
	row.custom_minimum_size = Vector2(width, ROW_H)
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.16, 0.13, 0.05, 0.55) if highlight else Color(0.05, 0.07, 0.16, 0.5)
	s.set_corner_radius_all(12)
	var rim := ArenaUI.GOLD if highlight else Color(0.40, 0.45, 0.72)
	s.border_color = Color(rim.r, rim.g, rim.b, 0.8 if highlight else 0.16)
	s.set_border_width_all(2 if highlight else 1)
	# A soft contact shadow under highlighted rows gives the list layered depth.
	if highlight:
		s.shadow_color = Color(0.0, 0.0, 0.02, 0.35)
		s.shadow_size = 6
		s.shadow_offset = Vector2(0, 3)
	row.add_theme_stylebox_override("panel", s)

	# Circular avatar placeholder, tinted by role, carrying the player's initial.
	var av_d := ROW_H - 14.0
	var av := _avatar(av_d, pname, ArenaUI.GOLD if is_host else (Color(0.55, 0.75, 1.0) if is_me else Color(0.55, 0.60, 0.82)), false)
	av.position = Vector2(9.0, (ROW_H - av_d) * 0.5)
	row.add_child(av)

	var name_x := 9.0 + av_d + 12.0
	var nm := Label.new()
	nm.text = pname
	nm.add_theme_font_size_override("font_size", 18)
	nm.add_theme_color_override("font_color", ArenaUI.GOLD.lightened(0.3) if highlight else Color(0.84, 0.88, 0.98))
	nm.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.02, 0.4))
	nm.add_theme_constant_override("shadow_offset_y", 1)
	nm.position = Vector2(name_x, 0); nm.size = Vector2(width - name_x - 128, ROW_H)
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.clip_text = true
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(nm)

	if is_host:
		# A premium gold host badge (sculpted pill + crown) rather than a flat capsule.
		var hb := _make_host_badge()
		var hb_right: float = (width - 48.0) if (can_kick and not is_me) else (width - 14.0)
		hb.position = Vector2(hb_right - hb.size.x, (ROW_H - hb.size.y) * 0.5)
		row.add_child(hb)
		# Pop the badge the first time it's assigned (not on every routine re-render).
		if not _host_popped:
			_host_popped = true
			hb.pivot_offset = hb.size * 0.5
			hb.scale = Vector2(0.3, 0.3)
			var pt := hb.create_tween()
			pt.tween_interval(0.12)
			pt.tween_property(hb, "scale", Vector2(1.14, 1.14), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			pt.tween_property(hb, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_SINE)
	elif is_me:
		var chip := _make_chip("YOU", Color(0.55, 0.75, 1.0))
		var chip_right: float = (width - 48.0) if (can_kick and not is_me) else (width - 14.0)
		chip.position = Vector2(chip_right - chip.size.x, (ROW_H - 28) * 0.5)
		row.add_child(chip)

	if can_kick and not is_me:
		var kick := Button.new()
		kick.text = "✕"
		kick.focus_mode = Control.FOCUS_NONE
		kick.add_theme_font_size_override("font_size", 16)
		var ks := StyleBoxFlat.new()
		ks.bg_color = Color(0.4, 0.12, 0.12, 0.85)
		ks.set_corner_radius_all(8)
		kick.add_theme_stylebox_override("normal", ks)
		kick.add_theme_color_override("font_color", Color(1, 0.85, 0.85))
		kick.size = Vector2(30, 30)
		kick.position = Vector2(width - 38, (ROW_H - 30) * 0.5)
		var target_name := pname
		kick.pressed.connect(func() -> void: _on_kick(uid, target_name))
		row.add_child(kick)

	# Newcomers ease into place with a soft fade + rise. The row lives in a VBox, which
	# owns its position, so the "slide" is done with scale (which the container leaves
	# alone) pivoting from the bottom, never with position.
	if animate:
		row.pivot_offset = Vector2(width * 0.5, ROW_H)
		row.modulate.a = 0.0
		row.scale = Vector2(0.98, 0.6)
		var jt := row.create_tween().set_parallel(true)
		jt.tween_property(row, "modulate:a", 1.0, 0.30).set_trans(Tween.TRANS_SINE)
		jt.tween_property(row, "scale", Vector2.ONE, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return row

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

# A refined difficulty badge: a dark gold-trimmed pill flanked by two small ✦, tinted
# by the difficulty colour — the room's secondary caption under the title.
func _make_diff_badge(text: String, col: Color) -> Control:
	var font := ThemeDB.fallback_font
	var fs := 18
	var label := "✦   %s   ✦" % text.to_upper()
	var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1.0, fs).x
	var bw: float = tw + 46.0
	var bh := 40.0
	var badge := Panel.new()
	badge.custom_minimum_size = Vector2(bw, bh)
	badge.size = Vector2(bw, bh)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.05, 0.12, 0.78)
	s.set_corner_radius_all(20)
	s.border_color = Color(col.r, col.g, col.b, 0.72)
	s.set_border_width_all(1)
	s.shadow_color = Color(col.r, col.g, col.b, 0.22)
	s.shadow_size = 12
	badge.add_theme_stylebox_override("panel", s)
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col.lightened(0.2))
	l.add_theme_color_override("font_outline_color", col.darkened(0.72))
	l.add_theme_constant_override("outline_size", 1)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(l)
	return badge

# A short gold divider: a hairline that fades in from both ends to a bright centre
# diamond gem — the decorative rule under the title.
func _make_divider(width: float) -> Control:
	var d := Control.new()
	d.custom_minimum_size = Vector2(width, 12)
	d.size = Vector2(width, 12)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.draw.connect(func() -> void:
		var w := d.size.x
		var cy := d.size.y * 0.5
		var gold := Color(1.0, 0.82, 0.36)
		var edge := Color(gold.r, gold.g, gold.b, 0.0)
		var core := Color(gold.r, gold.g, gold.b, 0.8)
		var th := 1.6
		d.draw_polygon(PackedVector2Array([
			Vector2(0, cy - th * 0.5), Vector2(w * 0.5, cy - th * 0.5),
			Vector2(w * 0.5, cy + th * 0.5), Vector2(0, cy + th * 0.5)]),
			PackedColorArray([edge, core, core, edge]))
		d.draw_polygon(PackedVector2Array([
			Vector2(w * 0.5, cy - th * 0.5), Vector2(w, cy - th * 0.5),
			Vector2(w, cy + th * 0.5), Vector2(w * 0.5, cy + th * 0.5)]),
			PackedColorArray([core, edge, edge, core]))
		var g := Vector2(w * 0.5, cy)
		var r := 4.5
		d.draw_colored_polygon(PackedVector2Array([
			g + Vector2(0, -r), g + Vector2(r, 0), g + Vector2(0, r), g + Vector2(-r, 0)]), gold)
		d.draw_circle(g + Vector2(-1.2, -1.4), 1.3, Color(1, 1, 1, 0.85)))
	return d

# A circular avatar placeholder: a domed, rim-lit disc tinted by `accent`, carrying the
# player's initial. `dim` renders a faded empty seat (waiting slots).
func _avatar(d: float, name_txt: String, accent: Color, dim: bool) -> Control:
	var a := Control.new()
	a.custom_minimum_size = Vector2(d, d)
	a.size = Vector2(d, d)
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var initial := ""
	var stripped := name_txt.strip_edges()
	if stripped.length() > 0:
		initial = stripped.substr(0, 1).to_upper()
	a.draw.connect(func() -> void:
		var r := d * 0.5
		var ctr := Vector2(r, r)
		var base_a := 0.30 if dim else 1.0
		# soft contact shadow
		a.draw_circle(ctr + Vector2(0, 2.0), r, Color(0.0, 0.0, 0.02, 0.28 * base_a))
		# domed body: bright top → darker base via stacked discs
		var top := accent.lightened(0.30 if not dim else 0.05)
		var bot := accent.darkened(0.52)
		for i in range(8):
			var t := float(i) / 7.0
			a.draw_circle(ctr + Vector2(0.0, lerpf(-r * 0.28, r * 0.14, t)),
				r * (1.0 - t * 0.14), Color(top.r, top.g, top.b, 0.0).lerp(
					Color(top.lerp(bot, t).r, top.lerp(bot, t).g, top.lerp(bot, t).b, base_a), 1.0))
		# rim light
		a.draw_arc(ctr, r - 0.8, 0.0, TAU, 40, Color(accent.lightened(0.55).r,
			accent.lightened(0.55).g, accent.lightened(0.55).b, (0.7 if not dim else 0.3) * 1.0), 1.4, true)
		# a small specular kiss upper-left
		a.draw_circle(ctr + Vector2(-r * 0.32, -r * 0.34), r * 0.20, Color(1, 1, 1, 0.35 * base_a)))
	if initial != "":
		var l := Label.new()
		l.text = initial
		l.add_theme_font_size_override("font_size", int(d * 0.5))
		l.add_theme_color_override("font_color", Color(1.0, 0.98, 0.92))
		l.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.02, 0.6))
		l.add_theme_constant_override("outline_size", 3)
		l.set_anchors_preset(Control.PRESET_FULL_RECT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		a.add_child(l)
	return a

# A premium gold "HOST" badge: a sculpted gold pill (gradient body, bright rim, top
# specular) with a small crown ahead of the label.
func _make_host_badge() -> Control:
	var bw := 74.0
	var bh := 28.0
	var badge := Control.new()
	badge.custom_minimum_size = Vector2(bw, bh)
	badge.size = Vector2(bw, bh)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.clip_contents = false
	var gold := ArenaUI.GOLD
	badge.draw.connect(func() -> void:
		var rect := Rect2(0.0, 0.0, bw, bh)
		var pts := _rr_points(rect, bh * 0.5)
		# soft bloom
		var bp := _rr_points(rect.grow(2.5), bh * 0.5 + 2.5)
		bp.append(bp[0])
		badge.draw_polyline(bp, Color(gold.r, gold.g, gold.b, 0.22), 3.0, true)
		# gradient body
		_fill_grad_v(badge, pts, 0.0, bh, gold.lightened(0.34), gold.darkened(0.34))
		# bright rim
		var rp := _rr_points(rect, bh * 0.5)
		rp.append(rp[0])
		badge.draw_polyline(rp, Color(gold.lightened(0.5).r, gold.lightened(0.5).g, gold.lightened(0.5).b, 0.85), 1.4, true)
		# top specular
		badge.draw_line(Vector2(bh * 0.5, 2.6), Vector2(bw - bh * 0.5, 2.6), Color(1, 1, 1, 0.5), 1.4, true))
	var l := Label.new()
	l.text = "♛ HOST"
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.30, 0.20, 0.04))
	l.add_theme_color_override("font_shadow_color", Color(1.0, 0.95, 0.7, 0.5))
	l.add_theme_constant_override("shadow_offset_y", -1)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(l)
	# An occasional, very soft gold shine passing across the badge (unsynced start).
	_add_shimmer(badge, 8.0, 0.11, randf() * 5.0)
	return badge

# A quiet, secondary "ghost" button: transparent body, thin muted rim, subtle press
# feedback. Reads clearly as the lesser action next to a solid primary.
func _make_ghost_button(text: String, accent: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.clip_contents = false
	# Hide the native label in every draw state — the art child paints the text. Without
	# the hover/pressed/focus overrides, Godot repaints the real label in the theme's
	# hover colour on mouse-over, which read as an unwanted "hover" on the button.
	var clear := Color(0, 0, 0, 0)
	for fc in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color",
			"font_hover_pressed_color", "font_disabled_color"]:
		b.add_theme_color_override(fc, clear)
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, empty)
	var art := Control.new()
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_meta("accent", accent)
	art.set_meta("pressed", false)
	art.draw.connect(func() -> void:
		var w := art.size.x
		var hh := art.size.y
		if w <= 2.0 or hh <= 2.0:
			return
		var pressed: bool = bool(art.get_meta("pressed", false))
		var R: float = minf(hh * 0.5, 26.0)
		var rect := Rect2(1.0, 1.0, w - 2.0, hh - 2.0)
		var pts := _rr_points(rect, R)
		art.draw_colored_polygon(pts, Color(accent.r, accent.g, accent.b, 0.06 if not pressed else 0.11))
		var rp := _rr_points(rect, R)
		rp.append(rp[0])
		art.draw_polyline(rp, Color(accent.r, accent.g, accent.b, 0.40), 1.4, true)
		var font := ThemeDB.fallback_font
		var fs := 19
		var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs)
		var base := Vector2((w - ts.x) * 0.5, (hh - ts.y) * 0.5 + font.get_ascent(fs))
		art.draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs,
			Color(accent.r, accent.g, accent.b, 0.70)))
	art.resized.connect(art.queue_redraw)
	b.add_child(art)
	b.button_down.connect(func() -> void: art.set_meta("pressed", true); art.queue_redraw())
	b.button_up.connect(func() -> void: art.set_meta("pressed", false); art.queue_redraw())
	return b

# Copy the room ID, flash a "Copied!" checkmark on the button, and give it a quick
# shrink-pop for tactile feedback.
func _on_copy_pressed(btn: Button) -> void:
	if not is_instance_valid(btn):
		return
	DisplayServer.clipboard_set(contest_id)
	_show_toast("Room ID copied!")
	btn.pivot_offset = btn.size * 0.5
	var st := btn.create_tween()
	st.tween_property(btn, "scale", Vector2(0.9, 0.9), 0.08).set_trans(Tween.TRANS_SINE)
	st.tween_property(btn, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	btn.text = "✓  Copied!"
	if btn.get_child_count() > 0 and btn.get_child(0) is Control:
		(btn.get_child(0) as Control).queue_redraw()
	var tree := get_tree()
	if tree == null:
		return
	await tree.create_timer(1.3).timeout
	if not is_instance_valid(btn):
		return
	btn.text = String(btn.get_meta("copy_default", "⧉  Copy ID"))
	if btn.get_child_count() > 0 and btn.get_child(0) is Control:
		(btn.get_child(0) as Control).queue_redraw()

# A subtle, premium light-sweep that crosses `target` on a slow loop: it glides once
# across (~0.85s) then rests for `period` seconds. Clipped to the target's rect and
# drawn additively so it reads as a soft shimmer, never a hard band. An initial `delay`
# lets several sweeps run out of sync.
func _add_shimmer(target: Control, period: float, strength := 0.16, delay := 0.0) -> void:
	var sweep := Control.new()
	sweep.set_anchors_preset(Control.PRESET_FULL_RECT)
	sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sweep.clip_contents = true                       # keep the band inside the button/badge
	sweep.set_meta("p", -1.0)                         # <0 or >1 → nothing drawn (resting)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	sweep.material = mat
	sweep.draw.connect(func() -> void:
		var w := sweep.size.x
		var hh := sweep.size.y
		if w <= 2.0 or hh <= 2.0:
			return
		var p: float = float(sweep.get_meta("p", -1.0))
		if p < 0.0 or p > 1.0:
			return
		# a slanted bright band travelling left → right, brightest at its core
		var core := lerpf(-hh, w + hh, p)
		var band: float = maxf(16.0, w * 0.14)
		for i in range(7):
			var t := float(i) / 6.0
			var x := core + (t - 0.5) * band
			var a: float = (1.0 - absf(t - 0.5) * 2.0) * strength
			sweep.draw_line(Vector2(x + hh * 0.35, 0.0), Vector2(x - hh * 0.35, hh),
				Color(1.0, 0.98, 0.88, a), 2.4, true))
	target.add_child(sweep)
	var tw := sweep.create_tween().set_loops()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_method(_shimmer_step.bind(sweep), -0.05, 1.05, 0.85).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void: sweep.set_meta("p", -1.0); sweep.queue_redraw())
	tw.tween_interval(period)

# One step of a shimmer sweep: stash the progress and repaint. Bound to its sweep node
# so the tween can drive it (the interpolated value arrives first, the node second).
func _shimmer_step(v: float, sweep: Control) -> void:
	if not is_instance_valid(sweep):
		return
	sweep.set_meta("p", v)
	sweep.queue_redraw()

# Calm background layering for the lobby: a soft radial pool of warm light behind the
# upper content, a gentle glow behind the centre of the screen, slow gold motes drifting
# up the room and a scatter of faint twinkling stars.
func _add_lobby_ambience(w: float, h: float) -> void:
	var glow := Control.new()
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.position = Vector2.ZERO
	glow.size = Vector2(w, h)
	glow.draw.connect(func() -> void:
		var gold := Color(1.0, 0.86, 0.46)
		# warm pool behind the upper content
		var ctr := Vector2(w * 0.5, h * 0.14)
		glow.draw_set_transform(ctr, 0.0, Vector2(1.7, 1.0))
		for i in range(10):
			var t := float(i) / 10.0
			glow.draw_circle(Vector2.ZERO, lerpf(46.0, w * 0.44, t),
				Color(gold.r, gold.g, gold.b, 0.05 * (1.0 - t) * (1.0 - t)))
		# a soft, wide radial lift behind the very centre of the screen
		var mid := Vector2(w * 0.5, h * 0.5)
		glow.draw_set_transform(mid, 0.0, Vector2(1.3, 1.0))
		for i in range(9):
			var t := float(i) / 9.0
			glow.draw_circle(Vector2.ZERO, lerpf(90.0, w * 0.40, t),
				Color(gold.r, gold.g, gold.b, 0.028 * (1.0 - t) * (1.0 - t)))
		glow.draw_set_transform_matrix(Transform2D.IDENTITY))
	_content.add_child(glow)

	# A scatter of faint stars that slowly twinkle in and out behind everything.
	_add_lobby_stars(w, h)

	var motes := CPUParticles2D.new()
	motes.texture = _confetti_flake()
	motes.amount = 16
	motes.lifetime = 9.0
	motes.preprocess = 9.0
	motes.position = Vector2(w * 0.5, h + 10.0)
	motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	motes.emission_rect_extents = Vector2(w * 0.5, 6.0)
	motes.direction = Vector2(0, -1)
	motes.spread = 18.0
	motes.gravity = Vector2(0, -5.0)
	motes.initial_velocity_min = 8.0
	motes.initial_velocity_max = 20.0
	motes.scale_amount_min = 0.5
	motes.scale_amount_max = 1.3
	motes.color = Color(1.0, 0.86, 0.5, 0.5)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	motes.material = mat
	_content.add_child(motes)

# A single additive layer of small stars, each fading in and out on its own slow loop
# for a gentle twinkle. One node keeps it cheap; phases come from a fixed seed so the
# pattern is stable across re-renders.
func _add_lobby_stars(w: float, h: float) -> void:
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.position = Vector2.ZERO
	layer.size = Vector2(w, h)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	layer.material = mat
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5EED
	var stars: Array = []
	for i in range(26):
		stars.append({
			"p": Vector2(rng.randf() * w, rng.randf() * h),
			"r": rng.randf_range(0.7, 1.8),
			"ph": rng.randf() * TAU,
			"sp": rng.randf_range(0.6, 1.4),
		})
	layer.draw.connect(func() -> void:
		var t := float(Time.get_ticks_msec()) * 0.001
		for s: Dictionary in stars:
			var tw: float = 0.5 + 0.5 * sin(t * float(s["sp"]) + float(s["ph"]))
			var a: float = 0.10 + 0.34 * tw
			var col := Color(1.0, 0.95, 0.8, a)
			layer.draw_circle(s["p"], float(s["r"]), col)
			if tw > 0.7:
				# a faint sparkle cross on the brightest stars
				var pp: Vector2 = s["p"]
				var rr: float = float(s["r"]) * 2.6
				layer.draw_line(pp - Vector2(rr, 0), pp + Vector2(rr, 0), Color(1, 0.96, 0.82, a * 0.5), 1.0, true)
				layer.draw_line(pp - Vector2(0, rr), pp + Vector2(0, rr), Color(1, 0.96, 0.82, a * 0.5), 1.0, true))
	# Drive the twinkle by repainting each frame (cheap: one node, ~26 circles).
	var ticker := Timer.new()
	ticker.wait_time = 0.05
	ticker.autostart = true
	ticker.timeout.connect(layer.queue_redraw)
	layer.add_child(ticker)
	_content.add_child(layer)

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
	var members := _active_players()
	if members.size() < 2:
		_show_confirm("No one else has joined yet.\nStart the race anyway?",
			func() -> void: _do_start())
	else:
		_do_start()

func _do_start() -> void:
	_set_overlay(true, "Starting…")
	var res: Dictionary = await ContestManager.start_room(contest_id)
	if not is_inside_tree():
		return
	if not bool(res.get("ok", false)):
		_set_overlay(false)
		_show_toast("Couldn't start the race.")
	# On success the room_changed listener flips us to "playing" and auto-launches
	# the match for everyone (including the host).

func _on_kick(uid: String, nm: String) -> void:
	_show_confirm("Remove %s from the room?" % nm, func() -> void:
		await ContestManager.kick_member(contest_id, uid))

func _on_finish_now() -> void:
	_show_confirm("End the race now and lock in the results?", func() -> void:
		await ContestManager.finish_now(contest_id))

func _on_cancel() -> void:
	_show_confirm("Cancel this room for everyone?\nThis can't be undone.", func() -> void:
		_set_overlay(true, "Cancelling…")
		await ContestManager.cancel_room(contest_id)
		if not is_inside_tree():
			return
		game_manager.show_arena())

func _on_leave() -> void:
	var is_creator := String(_room.get("creator_uid", "")) == FirebaseManager.uid
	var status := String(_room.get("status", ""))
	var msg := "Leave this room?"
	if is_creator and status == "lobby":
		msg = "You're the host. Leaving cancels the room for everyone. Continue?"
	_show_confirm(msg, func() -> void: _do_leave())

func _do_leave() -> void:
	_set_overlay(true, "Leaving…")
	await ContestManager.leave_contest(contest_id)
	if not is_inside_tree():
		return
	game_manager.show_arena()

func _on_exit() -> void:
	# Simple post-view interstitial, same treatment as game-over: skipped for
	# players who bought the remove-ads entitlement.
	if not CoinsManager.has_remove_ads:
		AdManager.try_show_interstitial()
	game_manager.show_arena()

# ---------------- overlay / toast / confirm ----------------

func _build_overlay() -> void:
	_overlay = Panel.new()
	_overlay.z_index = 90
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

# ================= sculpted-3D material helpers =================
# Same recipe as the create-room screen: an invisible Button supplies the tap target +
# press state; a child "art" Control paints the bevel, gradient, rim light and engraved
# label per-vertex so we control the depth directly. Panels use the same body drawing.

# Trace a clockwise rounded-rectangle perimeter (used for gradient fills + outlines).
func _rr_points(rect: Rect2, r: float, seg := 6) -> PackedVector2Array:
	r = minf(r, minf(rect.size.x, rect.size.y) * 0.5)
	var pts := PackedVector2Array()
	var corners := [
		[rect.position + Vector2(rect.size.x - r, r), -PI * 0.5],
		[rect.position + Vector2(rect.size.x - r, rect.size.y - r), 0.0],
		[rect.position + Vector2(r, rect.size.y - r), PI * 0.5],
		[rect.position + Vector2(r, r), PI],
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

# A glossy sculpted-3D pill button. `primary` brightens the fill + bloom.
func _make_button_3d(text: String, accent: Color, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.clip_contents = false
	b.add_theme_color_override("font_color", Color(0, 0, 0, 0))   # hide native text; art draws it
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, empty)
	var art := Control.new()
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.clip_contents = false
	art.set_meta("accent", accent)
	art.set_meta("primary", primary)
	art.set_meta("pressed", false)
	art.draw.connect(_draw_button_3d.bind(art))
	art.resized.connect(art.queue_redraw)
	b.add_child(art)
	# physical press: the whole face sinks toward its shadow, then springs back on release
	b.button_down.connect(func() -> void:
		art.set_meta("pressed", true); art.queue_redraw())
	b.button_up.connect(func() -> void:
		art.set_meta("pressed", false); art.queue_redraw())
	return b

func _draw_button_3d(c: Control) -> void:
	var w := c.size.x
	var h := c.size.y
	if w <= 2.0 or h <= 2.0:
		return
	var accent: Color = c.get_meta("accent", Color.WHITE)
	var primary: bool = bool(c.get_meta("primary", false))
	var pressed: bool = bool(c.get_meta("pressed", false))
	var dy := 3.0 if pressed else 0.0
	var R: float = minf(h * 0.5, 30.0)

	# ---- soft contact shadow anchoring the pill (stays put as the face sinks) ----
	for i in range(5):
		var t := float(i) / 5.0
		var sw: float = w - 20.0 + t * 24.0
		var sy: float = h - 6.0 + t * 5.0
		var srect := Rect2((w - sw) * 0.5, sy, sw, 12.0)
		var sa: float = (0.28 * (1.0 - t)) * (0.5 if pressed else 1.0)
		c.draw_colored_polygon(_rr_points(srect, 6.0), Color(0.0, 0.0, 0.02, sa))

	var body := Rect2(1.0, 1.0 + dy, w - 2.0, h - 5.0)
	var body_pts := _rr_points(body, R)

	# ---- tight bloom hugging the pill ----
	for i in range(5):
		var g: float = 1.0 + i * 2.2
		var bpts := _rr_points(body.grow(g), R + g)
		bpts.append(bpts[0])
		c.draw_polyline(bpts, Color(accent.r, accent.g, accent.b,
			(0.16 if primary else 0.10) * (1.0 - float(i) / 5.0)), 3.0, true)

	# ---- bevelled body: a vertical gradient reads as a lit convex cap ----
	_fill_grad_v(c, body_pts, body.position.y, body.position.y + body.size.y,
		accent.lightened(0.34 if primary else 0.26), accent.darkened(0.40 if primary else 0.34))

	# ---- rim: a bright bevel edge tracing the pill ----
	var rim := accent.lightened(0.5)
	var rim_pts := _rr_points(body, R)
	rim_pts.append(rim_pts[0])
	c.draw_polyline(rim_pts, Color(rim.r, rim.g, rim.b, 0.6), 2.0, true)

	# ---- specular highlight riding the top edge + a darker shade line along the base ----
	c.draw_line(Vector2(R * 0.8, body.position.y + 2.8), Vector2(w - R * 0.8, body.position.y + 2.8),
		Color(1.0, 1.0, 1.0, 0.5), 1.6, true)
	c.draw_line(Vector2(R, body.position.y + body.size.y - 2.4),
		Vector2(w - R, body.position.y + body.size.y - 2.4), Color(0.0, 0.0, 0.02, 0.36), 1.6, true)

	# ---- convex sheen pooled in the upper third so the surface bulges gently ----
	var sheen_ctr := Vector2(w * 0.5, body.position.y + body.size.y * 0.32)
	c.draw_set_transform(sheen_ctr, 0.0, Vector2(1.0, 0.5))
	for i in range(5):
		var t := float(i) / 5.0
		c.draw_circle(Vector2.ZERO, lerpf(body.size.y * 0.14, body.size.x * 0.42, t),
			Color(1.0, 1.0, 1.0, 0.10 * (1.0 - t)))
	c.draw_set_transform_matrix(Transform2D.IDENTITY)

	# ---- engraved ivory label ----
	var font := ThemeDB.fallback_font
	var fs := 23
	var txt := (c.get_parent() as Button).text
	var ts := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs)
	var base := Vector2((w - ts.x) * 0.5, (h - ts.y) * 0.5 + font.get_ascent(fs) + dy)
	c.draw_string_outline(font, base, txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, 5,
		Color(0.0, 0.0, 0.02, 0.7))
	c.draw_string(font, base + Vector2(0.0, 1.2), txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs,
		Color(0.0, 0.0, 0.0, 0.35))
	c.draw_string(font, base, txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, Color(1.0, 0.98, 0.92))

# A sculpted 3D stone-gold tablet (for the SHARE-THIS-ID plaque): the child art paints a
# bevelled body, gold rim, top specular and a convex sheen; real Labels sit on top.
func _make_plaque_3d(accent: Color) -> Control:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.clip_contents = false
	var art := Control.new()
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.clip_contents = false
	art.draw.connect(_draw_plaque_3d.bind(art, accent))
	art.resized.connect(art.queue_redraw)
	root.add_child(art)
	return root

func _draw_plaque_3d(c: Control, accent: Color) -> void:
	var w := c.size.x
	var h := c.size.y
	if w <= 2.0 or h <= 2.0:
		return
	var R := 18.0

	# ---- soft contact shadow anchoring the tablet ----
	for i in range(5):
		var t := float(i) / 5.0
		var sw: float = w - 24.0 + t * 28.0
		var sy: float = h - 6.0 + t * 5.0
		var srect := Rect2((w - sw) * 0.5, sy, sw, 13.0)
		c.draw_colored_polygon(_rr_points(srect, 7.0), Color(0.0, 0.0, 0.02, 0.24 * (1.0 - t)))

	var body := Rect2(1.0, 1.0, w - 2.0, h - 5.0)
	var body_pts := _rr_points(body, R)

	# ---- soft gold bloom hugging the tablet, for a premium lit-card glow ----
	for i in range(6):
		var g: float = 2.0 + i * 3.0
		var bpts := _rr_points(body.grow(g), R + g)
		bpts.append(bpts[0])
		c.draw_polyline(bpts, Color(accent.r, accent.g, accent.b, 0.11 * (1.0 - float(i) / 6.0)), 3.0, true)

	# ---- bevelled body: a warmer gold-stone gradient ----
	_fill_grad_v(c, body_pts, body.position.y, body.position.y + body.size.y,
		Color(0.28, 0.22, 0.13).lerp(accent, 0.38), Color(0.08, 0.06, 0.04).lerp(accent, 0.14))

	# ---- gold rim tracing the tablet: a slightly finer line for a cleaner, elegant edge ----
	var rim := accent.lightened(0.35)
	var rim_pts := _rr_points(body, R)
	rim_pts.append(rim_pts[0])
	c.draw_polyline(rim_pts, Color(rim.r, rim.g, rim.b, 0.7), 1.65, true)

	# ---- specular highlight along the top edge + a darker shade line along the base ----
	c.draw_line(Vector2(R * 0.8, body.position.y + 2.8), Vector2(w - R * 0.8, body.position.y + 2.8),
		Color(1.0, 0.97, 0.86, 0.42), 1.6, true)
	c.draw_line(Vector2(R, body.position.y + body.size.y - 2.4),
		Vector2(w - R, body.position.y + body.size.y - 2.4), Color(0.0, 0.0, 0.02, 0.4), 1.6, true)

	# ---- convex sheen pooled in the upper third ----
	var sheen_ctr := Vector2(w * 0.5, body.position.y + body.size.y * 0.28)
	c.draw_set_transform(sheen_ctr, 0.0, Vector2(1.0, 0.4))
	for i in range(5):
		var t := float(i) / 5.0
		c.draw_circle(Vector2.ZERO, lerpf(body.size.y * 0.12, body.size.x * 0.42, t),
			Color(1.0, 0.95, 0.80, 0.06 * (1.0 - t)))
	c.draw_set_transform_matrix(Transform2D.IDENTITY)

# A warm gold radial glow pooled behind the ID number (its alpha is driven by a looping
# tween — bright ~2s, dark ~5s).
func _draw_id_glow(c: Control) -> void:
	var w := c.size.x
	var h := c.size.y
	if w <= 2.0 or h <= 2.0:
		return
	var gold := Color(1.0, 0.86, 0.40)
	var ctr := Vector2(w * 0.5, h * 0.5)
	c.draw_set_transform(ctr, 0.0, Vector2(1.0, 0.62))
	for i in range(8):
		var t := float(i) / 8.0
		var rad: float = lerpf(22.0, w * 0.5, t)
		c.draw_circle(Vector2.ZERO, rad, Color(gold.r, gold.g, gold.b, 0.15 * (1.0 - t) * (1.0 - t)))
	c.draw_set_transform_matrix(Transform2D.IDENTITY)
