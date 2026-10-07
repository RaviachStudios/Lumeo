extends Control

# The Class Game screen. One screen, many faces, picked from ClassManager's state:
#
#   TEACHER  lobby     : the class code on a big chalkboard (for the projector), the
#                        live list of students (tap to remove), START / CANCEL
#            playing   : round + clock, who's done / still playing / out, END GAME
#            finished  : podium + full ranking, CLOSE
#            cancelled : a short message, HOME
#   STUDENT  lobby     : "you're in <teacher>'s class, waiting for the teacher"
#            playing   : launches the game straight away (game.gd class mode)
#            out       : spectator — why you're out, your result, the live round
#            finished  : podium + full ranking with your row highlighted
#            kicked / cancelled / gone / not_in_roster / other_device : a message
#
# This screen never polls: it re-renders on ClassManager.changed. The only per-frame
# work is the teacher's round clock bar (local maths, no reads).

const ArenaUI := preload("res://arena_ui.gd")
const PodiumStage := preload("res://podium_stage.gd")
const SimonFlyer := preload("res://simon_flyer.gd")
const ClassArt := preload("res://class_art.gd")
const ClassRules := preload("res://class_rules.gd")

const CHALK := Color(0.95, 0.96, 0.90)
const OK_GREEN := Color(0.35, 0.85, 0.45)
const OUT_GREY := Color(0.55, 0.55, 0.62)
const FAIL_ORANGE := Color(1.0, 0.62, 0.28)
const CLASS_ACCENT := Color(0.40, 0.85, 0.55)

var game_manager: Node

var _bg: ColorRect
var _back: Button
var _title: Label
var _content: Control
var _toast: Label
var _confirm: Panel
var _confirm_lbl: Label
var _confirm_cb: Callable

var _face := ""                     # last rendered face, to keep one-shot effects one-shot
var _render_queued := false
var _launching := false
var _clock_bar: Panel
var _clock_fill: Panel
var _clock_lbl: Label
var _busy := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg = ArenaUI.make_lobby_bg()
	add_child(_bg)
	_back = ArenaUI.make_back_button()
	_back.pressed.connect(_on_back)
	add_child(_back)
	_title = ArenaUI.title("CLASS GAME")
	add_child(_title)
	_content = Control.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)
	_build_toast()
	_build_confirm()
	_layout()
	get_viewport().size_changed.connect(_on_resize)
	# The class screen is the one a teacher projects, and the one a student stares at
	# while waiting — neither should let the phone fall asleep under it.
	DisplayServer.screen_set_keep_on(true)
	ClassManager.changed.connect(_queue_render)
	ClassManager.round_started.connect(_on_round_started)
	ClassManager.notice.connect(_show_toast)
	AudioManager.play_bg_music()
	_enter()

func _exit_tree() -> void:
	DisplayServer.screen_set_keep_on(false)

# Attach to our class if we aren't already (e.g. straight from the loading screen).
func _enter() -> void:
	if ClassManager.class_id.is_empty():
		var pid := ClassManager.pointer_id()
		if pid.is_empty():
			_render()
			return
		_render_message("Loading your class...", "", false)
		await ClassManager.attach(pid)
	if not is_inside_tree():
		return
	_render()
	_maybe_launch()

func _on_back() -> void:
	# Back never leaves the class: a teacher's referee keeps running, and a student
	# can return from the Arena card. Ending/leaving is an explicit button.
	game_manager.show_home()

func _on_resize() -> void:
	_layout()
	_render()

func _layout() -> void:
	var sz := get_viewport_rect().size
	ArenaUI.size_bg(_bg, sz)
	_back.position = Vector2(20, 20)
	_title.size = Vector2(sz.x, 52)
	_title.position = Vector2(0, 18)
	_content.position = Vector2(0, 78)
	_content.size = Vector2(sz.x, sz.y - 78)
	_toast.size = Vector2(sz.x, 30)
	_toast.position = Vector2(0, sz.y - 40)
	_confirm.position = sz * 0.5 - _confirm.size * 0.5

func _queue_render() -> void:
	if _render_queued:
		return
	_render_queued = true
	call_deferred("_flush_render")

func _flush_render() -> void:
	_render_queued = false
	if is_inside_tree():
		_render()
		_maybe_launch()

func _process(_dt: float) -> void:
	if _clock_bar == null or not is_instance_valid(_clock_bar):
		return
	var r := int(ClassManager.doc.get("round", 1))
	var lim := ClassRules.banner(r) + ClassRules.playback(r) + ClassRules.limit(r)
	var left := float(ClassManager.round_expected_end_ms() - ClassManager.server_ms()) / 1000.0
	var frac := clampf(left / lim, 0.0, 1.0)
	_clock_fill.size.x = maxf(0.0, (_clock_bar.size.x - 6.0) * frac)
	if left > 0.0:
		_clock_lbl.text = "%ds" % int(ceil(left))
	elif ClassManager.server_ms() < ClassManager.round_deadline_ms():
		_clock_lbl.text = "wrapping up..."
	else:
		_clock_lbl.text = "..."

# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

func _clear() -> void:
	for c in _content.get_children():
		c.queue_free()
	_clock_bar = null

func _render() -> void:
	_clear()
	if ClassManager.load_failed:
		_render_retry()
		return
	if ClassManager.class_id.is_empty():
		if ClassManager.gone:
			_render_message("This class has ended.", "", true)
		else:
			_render_message("You're not in a class right now.", "", true)
		return
	if ClassManager.is_host:
		_render_teacher()
	else:
		_render_student()

func _render_teacher() -> void:
	if ClassManager.gone:
		_set_face("t_gone")
		_render_message("This class has ended.", "It was closed after a long time without activity.", true, true)
		return
	match String(ClassManager.doc.get("status", "")):
		"lobby":
			_set_face("t_lobby")
			_render_teacher_lobby()
		"playing":
			_set_face("t_play")
			_render_teacher_live()
		"finished":
			_set_face("t_done")
			_render_podium(true)
		"cancelled":
			_set_face("t_cancel")
			_render_message("Class cancelled.", "", true, true)

func _render_student() -> void:
	var phase := ClassManager.student_phase()
	_set_face("s_" + phase)
	match phase:
		"lobby":
			_render_student_lobby()
		"playing":
			_render_get_ready()
		"out":
			_render_spectator()
		"finished":
			_render_podium(false)
		"kicked":
			_render_message("Your teacher removed you from this class.", "", true, true)
		"cancelled":
			_render_message("Your teacher ended the class.", "", true, true)
		"gone":
			_render_message("This class has ended.", "", true, true)
		"not_in_roster":
			_render_message("This class game started without you.",
				"The class was full when the game began.", true, true)
		"other_device":
			_render_message("You're playing on another device.",
				"This class game is running on the device you joined from last.", true, true)
		_:
			_render_message("Loading your class...", "", false)

func _set_face(f: String) -> void:
	_face = f

# Student: a round is waiting -> into the game.
func _maybe_launch() -> void:
	if _launching or ClassManager.is_host or ClassManager.class_id.is_empty():
		return
	if ClassManager.student_phase() != "playing" or not ClassManager.has_pending_round():
		return
	_launching = true
	ClassManager.prepare_game()
	AudioManager.stop_bg_music()
	game_manager.show_game()

func _on_round_started(_r: int) -> void:
	_maybe_launch()

# ---------------------------------------------------------------------------
# Teacher: lobby
# ---------------------------------------------------------------------------

func _render_teacher_lobby() -> void:
	var w := _content.size.x
	var h := _content.size.y
	var pid := ClassManager.class_id
	var students := ClassManager.lobby_students()

	# The chalkboard with the class code, left.
	var bw := minf(520.0, w * 0.46)
	var bh := minf(330.0, h - 120.0)
	var board := _board(Rect2(Vector2(w * 0.04, 6), Vector2(bw, bh)))
	_chalk_label(board, "CLASS CODE", 22, Vector2(0, bh * 0.15), bw, 0.75)
	var code := _chalk_label(board, " ".join(pid.split("")), 84, Vector2(0, bh * 0.28), bw, 1.0)
	code.add_theme_constant_override("outline_size", 2)
	code.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.25))
	_chalk_label(board, "Students: open ARENA  >  JOIN YOUR CLASS", 17, Vector2(0, bh * 0.62), bw, 0.8)
	_chalk_label(board, "%s's class" % String(ClassManager.doc.get("teacher_name", "")), 17,
		Vector2(0, bh * 0.72), bw, 0.6)

	# Student list, right.
	var lx := w * 0.04 + bw + 24.0
	var lw := w - lx - w * 0.04
	var panel := ArenaUI.glass_panel(CLASS_ACCENT)
	panel.position = Vector2(lx, 6)
	panel.size = Vector2(lw, bh)
	_content.add_child(panel)
	var head := _label("STUDENTS  %d / %d" % [students.size(), ClassRules.MAX_STUDENTS], 22,
		ArenaUI.GOLD, Vector2(0, 12), lw)
	panel.add_child(head)
	if students.is_empty():
		panel.add_child(_label("Waiting for students to join...", 18, ArenaUI.MUTED,
			Vector2(0, bh * 0.45), lw))
	else:
		panel.add_child(_label("Tap a name to remove a student", 13, ArenaUI.MUTED,
			Vector2(0, 40), lw))
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.position = Vector2(14, 64)
		scroll.size = Vector2(lw - 28, bh - 78)
		panel.add_child(scroll)
		var grid := GridContainer.new()
		grid.columns = maxi(1, int((lw - 28) / 150.0))
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		scroll.add_child(grid)
		var cw := (lw - 28 - (grid.columns - 1) * 8) / float(grid.columns)
		for s: Dictionary in students:
			var chip := _chip(String(s["n"]), Color(0.85, 0.90, 1.0), Vector2(cw, 38))
			var uid := String(s["uid"])
			var nm := String(s["n"])
			chip.pressed.connect(func() -> void:
				_ask("Remove %s from the class?" % nm, func() -> void: ClassManager.kick(uid)))
			grid.add_child(chip)

	# Buttons.
	var by := bh + 26.0
	var start := ArenaUI.pill_button("START GAME", CLASS_ACCENT, true)
	start.size = Vector2(280, 60)
	start.position = Vector2(w * 0.5 + 10, by)
	start.disabled = students.size() < ClassRules.MIN_STUDENTS
	start.pressed.connect(_on_start)
	_content.add_child(start)
	var cancel := ArenaUI.pill_button("Cancel Class", Color(0.95, 0.35, 0.35))
	cancel.size = Vector2(220, 60)
	cancel.position = Vector2(w * 0.5 - 230, by)
	cancel.pressed.connect(func() -> void:
		_ask("Cancel this class game?", func() -> void:
			ClassManager.cancel_class()))
	_content.add_child(cancel)
	# How many rounds: the teacher's 10 / 15 pick, sent with START.
	var px := w * 0.04
	var pl := _label("ROUNDS", 15, ArenaUI.MUTED, Vector2(px, by + 18), 80)
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_content.add_child(pl)
	for i in ClassRules.ROUND_CHOICES.size():
		var n: int = ClassRules.ROUND_CHOICES[i]
		var on := ClassManager.lobby_rounds == n
		var b := _chip(str(n), CLASS_ACCENT if on else Color(0.75, 0.75, 0.85), Vector2(78, 52))
		b.add_theme_font_size_override("font_size", 24)
		if on:
			var sel := _flat(Color(CLASS_ACCENT.r, CLASS_ACCENT.g, CLASS_ACCENT.b, 0.35), 12, CLASS_ACCENT.lightened(0.2))
			sel.set_border_width_all(2)
			b.add_theme_stylebox_override("normal", sel)
			b.add_theme_stylebox_override("hover", sel)
		b.position = Vector2(px + 78 + i * 88, by + 4)
		b.size = Vector2(78, 52)
		b.pressed.connect(func() -> void:
			ClassManager.lobby_rounds = n
			_render())
		_content.add_child(b)
	if students.size() < ClassRules.MIN_STUDENTS:
		_content.add_child(_label("At least %d students are needed to start" % ClassRules.MIN_STUDENTS,
			14, ArenaUI.MUTED, Vector2(w * 0.5 + 10, by + 64), 280))
	elif students.size() > ClassRules.MAX_STUDENTS:
		_content.add_child(_label("Only the first %d will play" % ClassRules.MAX_STUDENTS,
			14, FAIL_ORANGE, Vector2(w * 0.5 + 10, by + 64), 280))

func _on_start() -> void:
	if _busy:
		return
	_busy = true
	var res := ClassManager.start_class(ClassManager.lobby_rounds)
	_busy = false
	if not bool(res.get("ok", false)):
		match String(res.get("error", "")):
			"too_few": _show_toast("At least %d students are needed" % ClassRules.MIN_STUDENTS)
			_: _show_toast("Couldn't start the game")

# ---------------------------------------------------------------------------
# Teacher: live board
# ---------------------------------------------------------------------------

func _render_teacher_live() -> void:
	var w := _content.size.x
	var h := _content.size.y
	var p := ClassManager.progress()
	var r := int(p.get("round", 1))

	var top := _label("ROUND %d / %d" % [r, int(p.get("max", ClassRules.DEFAULT_ROUNDS))], 40, ArenaUI.GOLD, Vector2(0, 0), w)
	_content.add_child(top)
	if not ClassManager.teacher_offline:
		_content.add_child(_label("%ds to complete the sequence" % int(ClassRules.limit(r)), 15,
			ArenaUI.MUTED, Vector2(0, 46), w))

	# Round clock.
	var cw := minf(560.0, w * 0.6)
	_clock_bar = Panel.new()
	_clock_bar.position = Vector2(w * 0.5 - cw * 0.5, 74)
	_clock_bar.size = Vector2(cw, 18)
	_clock_bar.add_theme_stylebox_override("panel", _flat(Color(0, 0, 0, 0.45), 9, Color(1, 1, 1, 0.15)))
	_content.add_child(_clock_bar)
	_clock_fill = Panel.new()
	_clock_fill.position = Vector2(3, 3)
	_clock_fill.size = Vector2(cw - 6, 12)
	_clock_fill.add_theme_stylebox_override("panel", _flat(CLASS_ACCENT, 6))
	_clock_bar.add_child(_clock_fill)
	_clock_lbl = _label("", 15, ArenaUI.TEXT, Vector2(w * 0.5 + cw * 0.5 + 10, 72), 160)
	_clock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_content.add_child(_clock_lbl)

	var stats := "%d completed   ·   %d missed   ·   %d still playing" % [
		int(p.get("done", 0)), int(p.get("missed", 0)), int(p.get("pending", 0))]
	if int(p.get("out", 0)) > 0:
		stats += "   ·   %d left" % int(p.get("out", 0))
	_content.add_child(_label(stats, 18, ArenaUI.TEXT, Vector2(0, 100), w))

	if ClassManager.teacher_offline:
		var off := _label("Connection lost - the game is paused until you're back online", 16,
			Color(1.0, 0.55, 0.45), Vector2(0, 46), w)
		off.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		off.add_theme_constant_override("outline_size", 4)
		_content.add_child(off)

	# Everyone, as chips.
	var rows := ClassManager.board_rows()
	var gw := w - 80.0
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.position = Vector2(40, 134)
	scroll.size = Vector2(gw, h - 134 - 84)
	_content.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = maxi(1, int(gw / 170.0))
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	var chip_w := (gw - (grid.columns - 1) * 8) / float(grid.columns)
	for e: Dictionary in rows:
		var st := String(e["state"])
		var txt := "%s   %d" % [String(e["n"]), int(e.get("s", 0))]
		var col := Color(0.85, 0.90, 1.0)
		match st:
			"done":
				txt = "✓ " + txt
				col = OK_GREEN
			"missed":
				txt = "✗ " + txt
				col = FAIL_ORANGE
			"left", "out":
				txt = "%s  (left)" % String(e["n"])
				col = OUT_GREY
				st = "out"
		var chip := _chip(txt, col, Vector2(chip_w, 36))
		var uid := String(e["uid"])
		var nm := String(e["n"])
		if st != "out":
			chip.pressed.connect(func() -> void:
				_ask("Remove %s from the game?" % nm, func() -> void: ClassManager.kick(uid)))
		else:
			chip.disabled = true
		grid.add_child(chip)

	var end := ArenaUI.pill_button("End Game", Color(0.95, 0.35, 0.35))
	end.size = Vector2(220, 56)
	end.position = Vector2(w * 0.5 - 110, h - 74)
	end.pressed.connect(func() -> void:
		_ask("End the game now? Results will be shown with the scores so far.", func() -> void:
			ClassManager.end_game()))
	_content.add_child(end)

# ---------------------------------------------------------------------------
# Student faces
# ---------------------------------------------------------------------------

func _render_student_lobby() -> void:
	var w := _content.size.x
	var h := _content.size.y
	var bw := minf(640.0, w - 80.0)
	var bh := minf(320.0, h - 110.0)
	var board := _board(Rect2(Vector2(w * 0.5 - bw * 0.5, 6), Vector2(bw, bh)))
	_chalk_label(board, "Welcome to", 22, Vector2(0, bh * 0.13), bw, 0.75)
	_chalk_label(board, "%s's class!" % String(ClassManager.doc.get("teacher_name", "your teacher")),
		40, Vector2(0, bh * 0.23), bw, 1.0)
	_chalk_label(board, "Class code  %s" % ClassManager.class_id, 20, Vector2(0, bh * 0.45), bw, 0.7)
	var wait := _chalk_label(board, "Waiting for your teacher to start...", 22, Vector2(0, bh * 0.60), bw, 0.95)
	var tw := wait.create_tween().set_loops()
	tw.tween_property(wait, "modulate:a", 0.45, 0.9).set_trans(Tween.TRANS_SINE)
	tw.tween_property(wait, "modulate:a", 1.0, 0.9).set_trans(Tween.TRANS_SINE)
	_add_flyers(2)
	var leave := ArenaUI.pill_button("Leave Class", Color(0.95, 0.35, 0.35))
	leave.size = Vector2(220, 56)
	leave.position = Vector2(w * 0.5 - 110, bh + 26)
	leave.pressed.connect(func() -> void:
		_ask("Leave this class?", func() -> void:
			ClassManager.leave_class()
			game_manager.show_home()))
	_content.add_child(leave)

# A student whose round is about to start (e.g. back from a restart between rounds).
func _render_get_ready() -> void:
	var w := _content.size.x
	_content.add_child(_label("Get ready!", 44, ArenaUI.GOLD, Vector2(0, 120), w))
	_content.add_child(_label("The next round starts in a moment...", 20, ArenaUI.TEXT,
		Vector2(0, 180), w))
	if ClassManager.teacher_late:
		_content.add_child(_label("Waiting for your teacher...", 18, ArenaUI.MUTED,
			Vector2(0, 216), w))
	_add_flyers(1)

# A student who left the game (from another device) or was removed: their banked
# result, and the live round, until the podium.
func _render_spectator() -> void:
	var w := _content.size.x
	var h := _content.size.y
	var r := ClassManager.my_out_round()
	var why := "Your teacher removed you." if ClassManager.my_out_reason() == "kicked" \
		else "You left the game in round %d." % r
	var pw := minf(620.0, w - 80.0)
	var panel := ArenaUI.glass_panel(FAIL_ORANGE)
	panel.position = Vector2(w * 0.5 - pw * 0.5, 10)
	panel.size = Vector2(pw, 250)
	_content.add_child(panel)
	panel.add_child(_label("You're out of the game", 36, FAIL_ORANGE.lightened(0.2), Vector2(0, 18), pw))
	panel.add_child(_label(why, 18, ArenaUI.TEXT, Vector2(0, 76), pw))
	panel.add_child(_label("%s completed  ·  %d points" % [_rounds_txt(ClassManager.my_rounds()), ClassManager.my_score()],
		24, ArenaUI.GOLD, Vector2(0, 118), pw))
	if ClassManager.coins_earned > 0:
		panel.add_child(_label("+%d coins" % ClassManager.coins_earned, 18, ArenaUI.GOLD.lightened(0.2),
			Vector2(0, 156), pw))
	var live := "Round %d / %d" % [int(ClassManager.doc.get("round", 0)), ClassManager.max_rounds()]
	if ClassManager.teacher_late:
		live += "  ·  waiting for your teacher..."
	panel.add_child(_label(live, 17, ArenaUI.MUTED, Vector2(0, 198), pw))
	_content.add_child(_label("Stay here to see the podium when the game ends.", 16, ArenaUI.MUTED,
		Vector2(0, 280), w))
	var home := ArenaUI.pill_button("Home", ArenaUI.ACCENT)
	home.size = Vector2(200, 54)
	home.position = Vector2(w * 0.5 - 100, h - 80)
	home.pressed.connect(func() -> void: game_manager.show_home())
	_content.add_child(home)

# ---------------------------------------------------------------------------
# Podium (both)
# ---------------------------------------------------------------------------

func _render_podium(teacher: bool) -> void:
	var w := _content.size.x
	var h := _content.size.y
	var cx := w * 0.5
	var standings := ClassManager.standings()
	var title := "Final Results"
	if bool(ClassManager.doc.get("ended_early", false)):
		title = "Final Results (ended early)"
	elif String(ClassManager.doc.get("end_reason", "")) == "none_completed":
		title = "Final Results - nobody completed round %d" % int(ClassManager.doc.get("round", 0))
	_content.add_child(_label(title, 26, ArenaUI.GOLD, Vector2(0, -4), w))

	var entries: Array = []
	for e: Dictionary in standings.slice(0, 3):
		entries.append({"name": String(e["n"]), "score": int(e["s"])})
	var stage := PodiumStage.new()
	stage.position = Vector2(cx * 0.62 if w > 1000 else cx, 26)
	stage.scale = Vector2.ONE * 0.92
	_content.add_child(stage)
	stage.setup(entries)
	stage.start_anim()

	# Full ranking on the right (wide screens) or under the podium.
	var lx := cx * 0.62 + 300.0 if w > 1000 else 40.0
	var ly := 30.0 if w > 1000 else 330.0
	var lw := (w - lx - 40.0) if w > 1000 else (w - 80.0)
	var lh := h - ly - 90.0
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.position = Vector2(lx, ly)
	scroll.size = Vector2(lw, lh)
	_content.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.custom_minimum_size = Vector2(lw, 0)
	scroll.add_child(vb)
	var mine: Dictionary = {}
	for e: Dictionary in standings:
		vb.add_child(_result_row(e, lw))
		if bool(e["is_me"]):
			mine = e

	if not teacher and not mine.is_empty():
		var txt := "You placed #%d  ·  %d points  ·  %d of %d rounds" % [int(mine["p"]), int(mine["s"]),
			int(mine["c"]), _rounds_played()]
		if ClassManager.coins_earned > 0:
			txt += "  ·  +%d coins" % ClassManager.coins_earned
		_content.add_child(_label(txt, 20, ArenaUI.GOLD.lightened(0.25), Vector2(0, h - 120), w))
		if int(mine["p"]) == 1 and _face_once("win_fx"):
			AudioManager.play_win_sound()
	_add_confetti()
	var done := ArenaUI.pill_button("Close Class" if teacher else "Done", ArenaUI.ACCENT, true)
	done.size = Vector2(240, 56)
	done.position = Vector2(cx - 120, h - 74)
	done.pressed.connect(func() -> void:
		ClassManager.close_out()
		game_manager.show_home())
	_content.add_child(done)

# Rounds the game actually ran (it can stop early when nobody completes one).
func _rounds_played() -> int:
	return maxi(1, int(ClassManager.doc.get("round", 1)))

static func _rounds_txt(n: int) -> String:
	return "1 round" if n == 1 else "%d rounds" % n

var _once: Dictionary = {}
func _face_once(key: String) -> bool:
	if _once.has(key):
		return false
	_once[key] = true
	return true

func _result_row(e: Dictionary, w: float) -> Control:
	var me := bool(e["is_me"])
	var p := int(e["p"])
	var row := Panel.new()
	row.custom_minimum_size = Vector2(w, 40)
	var accent: Color = [ArenaUI.GOLD, Color(0.78, 0.85, 0.98), Color(0.88, 0.55, 0.28)][p - 1] \
		if p >= 1 and p <= 3 else Color(0.55, 0.60, 0.85)
	row.add_theme_stylebox_override("panel", _flat(
		Color(0.25, 0.20, 0.05, 0.75) if me else Color(0.06, 0.07, 0.15, 0.55), 10,
		Color(ArenaUI.GOLD.r, ArenaUI.GOLD.g, ArenaUI.GOLD.b, 0.9) if me else Color(accent.r, accent.g, accent.b, 0.35)))
	var place := _label("#%d" % p, 18, accent, Vector2(8, 0), 50)
	place.size.y = 40
	row.add_child(place)
	var nm := _label(String(e["n"]) + ("  (you)" if me else ""), 18, ArenaUI.TEXT, Vector2(62, 0), w * 0.5)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	nm.size.y = 40
	nm.clip_text = true
	row.add_child(nm)
	var stats := _label("%d pts  ·  %d/%d rounds" % [int(e["s"]), int(e["c"]), _rounds_played()], 16, ArenaUI.MUTED,
		Vector2(w * 0.5, 0), w * 0.5 - 14)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stats.size.y = 40
	row.add_child(stats)
	return row

# ---------------------------------------------------------------------------
# Generic message face
# ---------------------------------------------------------------------------

func _render_message(msg: String, sub: String, show_home: bool, closes: bool = false) -> void:
	_clear()
	var w := _content.size.x
	var bw := minf(620.0, w - 80.0)
	var bh := 220.0
	var board := _board(Rect2(Vector2(w * 0.5 - bw * 0.5, 40), Vector2(bw, bh)), false)
	_chalk_label(board, msg, 28, Vector2(0, bh * 0.30), bw, 1.0)
	if not sub.is_empty():
		_chalk_label(board, sub, 17, Vector2(0, bh * 0.52), bw, 0.7)
	if show_home:
		var home := ArenaUI.pill_button("Home", ArenaUI.ACCENT, true)
		home.size = Vector2(220, 56)
		home.position = Vector2(w * 0.5 - 110, 40 + bh + 30)
		home.pressed.connect(func() -> void:
			if closes:
				ClassManager.close_out()
			game_manager.show_home())
		_content.add_child(home)

# Couldn't reach Firestore to load the class: nothing is known to be wrong with it,
# so offer a retry rather than declaring it over.
func _render_retry() -> void:
	_render_message("Can't reach your class right now.", "Check your internet connection.", false)
	var w := _content.size.x
	var retry := ArenaUI.pill_button("Try Again", CLASS_ACCENT, true)
	retry.size = Vector2(220, 56)
	retry.position = Vector2(w * 0.5 - 230, 300)
	retry.pressed.connect(func() -> void:
		var pid := ClassManager.class_id
		ClassManager.detach()
		_render_message("Loading your class...", "", false)
		await ClassManager.attach(pid)
		if is_inside_tree():
			_render()
			_maybe_launch())
	_content.add_child(retry)
	var home := ArenaUI.pill_button("Home", ArenaUI.ACCENT)
	home.size = Vector2(220, 56)
	home.position = Vector2(w * 0.5 + 10, 300)
	home.pressed.connect(func() -> void: game_manager.show_home())
	_content.add_child(home)

# ---------------------------------------------------------------------------
# Small builders
# ---------------------------------------------------------------------------

# A chalkboard Control in content space; returns it so labels can be added on top.
func _board(rect: Rect2, doodles: bool = true) -> Control:
	var c := Control.new()
	c.position = rect.position
	c.size = rect.size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void:
		ClassArt.draw_chalkboard(c, Rect2(Vector2.ZERO, c.size), Time.get_ticks_msec() / 1000.0, doodles))
	var t := Timer.new()
	t.wait_time = 0.1
	t.autostart = true
	t.timeout.connect(c.queue_redraw)
	c.add_child(t)
	_content.add_child(c)
	return c

func _chalk_label(parent: Control, txt: String, fs: int, pos: Vector2, w: float, alpha: float) -> Label:
	var l := _label(txt, fs, Color(CHALK.r, CHALK.g, CHALK.b, alpha), pos, w)
	l.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.12))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	parent.add_child(l)
	return l

func _label(txt: String, fs: int, col: Color, pos: Vector2, w: float) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.position = pos
	l.size = Vector2(w, fs * 1.5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _flat(col: Color, rad: int, border: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.set_corner_radius_all(rad)
	if border.a > 0.0:
		s.border_color = border
		s.set_border_width_all(1)
	return s

func _chip(txt: String, col: Color, sz: Vector2) -> Button:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = sz
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = true
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", col.lightened(0.2))
	b.add_theme_color_override("font_disabled_color", col)
	var n := _flat(Color(col.r * 0.18, col.g * 0.18, col.b * 0.22, 0.85), 10, Color(col.r, col.g, col.b, 0.55))
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", n)
	b.add_theme_stylebox_override("disabled", n)
	b.add_theme_stylebox_override("focus", n)
	var pr := n.duplicate() as StyleBoxFlat
	pr.bg_color = pr.bg_color.lightened(0.15)
	b.add_theme_stylebox_override("pressed", pr)
	return b

func _add_flyers(n: int) -> void:
	for i in n:
		var flyer := SimonFlyer.new()
		_content.add_child(flyer)
		flyer.setup(_content.size, {"mode": "wander", "scale": 0.55,
			"top_pad": 40.0,
			"button_color": SimonFlyer.BUTTON_COLS[(i * 2) % SimonFlyer.BUTTON_COLS.size()]})

func _add_confetti() -> void:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var tex := ImageTexture.create_from_image(img)
	var cols: Array = SimonFlyer.BUTTON_COLS.duplicate()
	cols.append(ArenaUI.GOLD)
	for col: Color in cols:
		var p := CPUParticles2D.new()
		p.texture = tex
		p.amount = 14
		p.lifetime = maxf(4.0, _content.size.y / 40.0)
		p.preprocess = p.lifetime
		p.position = Vector2(_content.size.x * 0.5, -20.0)
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		p.emission_rect_extents = Vector2(_content.size.x * 0.5, 8.0)
		p.direction = Vector2(0, 1)
		p.spread = 30.0
		p.gravity = Vector2(0, 40.0)
		p.initial_velocity_min = 40.0
		p.initial_velocity_max = 110.0
		p.scale_amount_min = 0.5
		p.scale_amount_max = 1.2
		p.angle_min = -180.0
		p.angle_max = 180.0
		p.color = col
		_content.add_child(p)

# ---------------------------------------------------------------------------
# Toast + confirm
# ---------------------------------------------------------------------------

func _build_toast() -> void:
	_toast = Label.new()
	_toast.add_theme_font_size_override("font_size", 18)
	_toast.add_theme_color_override("font_color", ArenaUI.TEXT)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_toast.add_theme_constant_override("outline_size", 4)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.modulate.a = 0.0
	add_child(_toast)

func _show_toast(msg: String) -> void:
	_toast.text = msg
	_toast.modulate.a = 1.0
	var tw := _toast.create_tween()
	tw.tween_interval(2.6)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.5)

func _build_confirm() -> void:
	_confirm = ArenaUI.stone_panel(ArenaUI.ACCENT)
	_confirm.size = Vector2(440, 200)
	_confirm.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm.visible = false
	_confirm.z_index = 10
	add_child(_confirm)
	_confirm_lbl = _label("", 21, ArenaUI.TEXT, Vector2(20, 28), 400)
	_confirm_lbl.size.y = 80
	_confirm.add_child(_confirm_lbl)
	var yes := ArenaUI.pill_button("Yes", Color(0.95, 0.35, 0.35), true)
	yes.size = Vector2(170, 52)
	yes.position = Vector2(30, 128)
	yes.pressed.connect(func() -> void:
		_confirm.visible = false
		if _confirm_cb.is_valid():
			_confirm_cb.call())
	_confirm.add_child(yes)
	var no := ArenaUI.pill_button("No", ArenaUI.ACCENT)
	no.size = Vector2(170, 52)
	no.position = Vector2(240, 128)
	no.pressed.connect(func() -> void: _confirm.visible = false)
	_confirm.add_child(no)

func _ask(msg: String, cb: Callable) -> void:
	_confirm_lbl.text = msg
	_confirm_cb = cb
	_confirm.visible = true

func handle_back() -> bool:
	if _confirm.visible:
		_confirm.visible = false
		return true
	return false
