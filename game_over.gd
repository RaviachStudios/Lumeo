extends Control

# Game-over screen, restyled to match the rest of the game (home / difficulty /
# leaderboards): deep navy shader background, glowing white-outlined heading,
# subdued lavender support text, dark navy-glass pill buttons with glowing
# accent icons. The session's round count is the eye-catching focal point;
# personal best is de-emphasized to a thin muted pill underneath.
#
# A new high score is a celebration moment: heading switches to gold "NEW HIGH
# SCORE!", confetti rains, the big score pulses with a golden bloom, and once
# the leaderboard upload settles we slot in a "You're #N on the leaderboard!"
# pill so the player learns where their run landed.

var game_manager: Node
var rounds: int = 0

const GOLD := Color(1.0, 0.85, 0.2)
const ICON_BLUE := Color(0.23, 0.51, 0.96)
const ICON_GREEN := Color(0.18, 0.78, 0.39)

# Mirror of home_screen's background — same palette so the screen reads as part
# of the same world, not a popup.
const BG_SHADER := "
shader_type canvas_item;
uniform float aspect = 0.5;
void fragment() {
	vec2 uv = UV;
	vec3 top = vec3(0.012, 0.020, 0.070);
	vec3 mid = vec3(0.018, 0.035, 0.110);
	vec3 bot = vec3(0.045, 0.030, 0.105);
	vec3 col = mix(top, mid, clamp(uv.y / 0.5, 0.0, 1.0));
	col = mix(col, bot, clamp((uv.y - 0.5) / 0.5, 0.0, 1.0));
	col += vec3(0.10, 0.22, 0.58) * smoothstep(0.5, 0.0, distance(uv, vec2(0.0, 0.45))) * 0.30;
	col += vec3(0.55, 0.12, 0.22) * smoothstep(0.5, 0.0, distance(uv, vec2(1.0, 0.50))) * 0.22;
	vec2 p = (uv - vec2(0.5)) * vec2(aspect, 1.0);
	float breathe = 0.85 + 0.15 * sin(TIME * 0.6);
	col += vec3(0.10, 0.16, 0.42) * smoothstep(0.5, 0.0, length(p - vec2(0.0, -0.18))) * 0.20 * breathe;
	col *= mix(0.6, 1.0, smoothstep(1.1, 0.25, length(p)));
	COLOR = vec4(col, 1.0);
}
"

# Same dark navy-glass face used by the home menu pills (gradient + top
# highlight + blue rim + soft drop shadow). The +pad/-pad inset is what gives
# the shadow room to breathe outside the pill's footprint.
const BTN_PAD := 20.0
const BTN_SHADER := "
shader_type canvas_item;
uniform vec2 rect_size = vec2(400.0, 114.0);
uniform float pad = 20.0;
uniform float radius = 30.0;
uniform vec3 top_col = vec3(0.118, 0.153, 0.369);
uniform vec3 bot_col = vec3(0.078, 0.102, 0.259);
float sdf_round_box(vec2 pp, vec2 b, float r) {
	vec2 q = abs(pp) - b + vec2(r);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}
void fragment() {
	vec2 px = UV * rect_size;
	vec2 p = px - rect_size * 0.5;
	vec2 hb = (rect_size - vec2(pad * 2.0)) * 0.5;
	float d = sdf_round_box(p, hb, radius);
	float body = smoothstep(1.0, -1.0, d);
	float sd = sdf_round_box(p - vec2(0.0, 7.0), hb, radius);
	float shadow = smoothstep(pad, 0.0, sd) * 0.45;
	float ty = clamp((px.y - pad) / (rect_size.y - pad * 2.0), 0.0, 1.0);
	vec3 base = mix(top_col, bot_col, ty);
	base += vec3(0.55, 0.65, 0.95) * smoothstep(0.16, 0.0, ty) * 0.10;
	base += vec3(0.35, 0.55, 1.0) * smoothstep(-7.0, -0.5, d) * 0.16;
	base += vec3(0.20, 0.35, 0.80) * smoothstep(95.0, 0.0, length(p)) * 0.05;
	float a = max(shadow, body);
	vec3 rgb = mix(vec3(0.0, 0.01, 0.04), base, body);
	COLOR = vec4(rgb, a);
}
"

const BTN_W := 280.0
const BTN_H := 64.0
const BTN_GAP := 36.0

var _confetti: Array[Dictionary] = []
var _time: float = 0.0
var _is_new_high: bool = false

var _bg: ColorRect
var _bg_mat: ShaderMaterial
var _btn_face_mat: ShaderMaterial
var _score_label: Label
var _rank_slot: Control               # placeholder; the rank pill is added here once Firestore returns
var _rank_token := 0                  # bumped on free; awaited callbacks bail when stale

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_is_new_high = GameState.submit_score(rounds)
	_build_background()
	_spawn_confetti()
	_build_ui()
	AudioManager.play_win_sound()
	if _is_new_high:
		_pulse_score()
	# Upload the score and learn the world rank. We wait for submit so the
	# subsequent load_global reflects this run (no submission/load for guests).
	if FirebaseManager.is_signed_in() and FirebaseManager.has_display_name():
		_submit_and_show_rank()

func _exit_tree() -> void:
	# Invalidate any in-flight rank load; the node is about to be freed.
	_rank_token += 1

# ---------------- background ----------------

func _build_background() -> void:
	# When a shop theme is equipped, BackgroundManager paints the viewport
	# beneath us — skip our shader so the theme isn't hidden.
	if BackgroundManager.is_themed():
		return
	_bg = ColorRect.new()
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.color = Color(0.02, 0.03, 0.09)
	# show_behind_parent puts the bg render below this Control's own _draw, so
	# the confetti (drawn by self._draw) ends up sandwiched between the bg and
	# the UI children — which all render on top of self._draw as usual.
	_bg.show_behind_parent = true
	var sh := Shader.new()
	sh.code = BG_SHADER
	_bg_mat = ShaderMaterial.new()
	_bg_mat.shader = sh
	_bg.material = _bg_mat
	var sz := get_viewport_rect().size
	_bg.position = Vector2.ZERO
	_bg.size = sz
	_bg_mat.set_shader_parameter("aspect", sz.x / maxf(1.0, sz.y))
	add_child(_bg)

# ---------------- confetti ----------------

func _spawn_confetti() -> void:
	# A new high score recolors the whole storm to a warm gold palette so the
	# celebration reads as different from a regular run (which keeps the
	# rainbow Simon-colored confetti).
	var colors: Array
	if _is_new_high:
		colors = [
			Color(1.00, 0.85, 0.20),   # core gold
			Color(1.00, 0.75, 0.10),   # rich gold
			Color(1.00, 0.93, 0.55),   # pale gold
			Color(0.96, 0.62, 0.10),   # amber
			Color(1.00, 0.98, 0.78),   # cream highlight
		]
	else:
		colors = [
			Color(0.9, 0.15, 0.15), Color(0.15, 0.8, 0.15), Color(0.15, 0.35, 0.95),
			Color(0.95, 0.85, 0.1), Color(0.95, 0.5, 0.1), Color(0.95, 0.3, 0.7),
			Color.WHITE,
		]
	var sz := get_viewport_rect().size
	var count := 110 if _is_new_high else 70
	for _i in count:
		_confetti.append({
			"pos": Vector2(randf() * sz.x, randf_range(-120.0, 0.0)),
			"vel": Vector2(randf_range(-50.0, 50.0), randf_range(60.0, 200.0)),
			"col": colors[randi() % colors.size()],
			"size": randf_range(5.0, 14.0),
			"rot": randf() * TAU,
			"rot_speed": randf_range(-3.0, 3.0),
		})

func _process(dt: float) -> void:
	_time += dt
	if _confetti.is_empty():
		return
	var sz := get_viewport_rect().size
	for c: Dictionary in _confetti:
		c["pos"] = (c["pos"] as Vector2) + (c["vel"] as Vector2) * dt
		c["rot"] = (c["rot"] as float) + (c["rot_speed"] as float) * dt
		if (c["pos"] as Vector2).y > sz.y + 20:
			c["pos"] = Vector2(randf() * sz.x, -20.0)
	queue_redraw()

func _draw() -> void:
	if _confetti.is_empty():
		return
	for c: Dictionary in _confetti:
		var pos: Vector2 = c["pos"]
		var s: float = c["size"]
		var col: Color = c["col"]
		var fade := minf(1.0, _time * 2.0)
		draw_rect(Rect2(pos - Vector2(s,s)*0.5, Vector2(s,s)), col * Color(1,1,1,0.8 * fade))

# ---------------- main UI ----------------

func _build_ui() -> void:
	var sz := get_viewport_rect().size
	var cx := sz.x * 0.5
	var best: int = GameState.get_high_score()

	# --- Heading ------------------------------------------------------------
	# Style matches the difficulty/leaderboards titles: large white letters with
	# a subtle blue glow (or gold glow when celebrating a new high score).
	var heading := Label.new()
	heading.text = "NEW HIGH SCORE!" if _is_new_high else "Well played"
	var hfont := 56 if _is_new_high else 46
	heading.add_theme_font_size_override("font_size", hfont)
	heading.add_theme_color_override("font_color",
		Color(1.0, 0.93, 0.55) if _is_new_high else Color.WHITE)
	heading.add_theme_color_override("font_outline_color",
		Color(1.0, 0.93, 0.55) if _is_new_high else Color(1, 1, 1, 1))
	heading.add_theme_constant_override("outline_size", 2)
	heading.add_theme_color_override("font_shadow_color",
		Color(1.0, 0.70, 0.20, 0.55) if _is_new_high else Color(0.20, 0.40, 1.0, 0.45))
	heading.add_theme_constant_override("shadow_offset_x", 0)
	heading.add_theme_constant_override("shadow_offset_y", 4)
	heading.add_theme_constant_override("shadow_outline_size", 12 if _is_new_high else 9)
	heading.position = Vector2(cx - 400, sz.y * 0.06)
	heading.size = Vector2(800, 80)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(heading)

	# --- Small "YOU SCORED" caption ----------------------------------------
	var caption := Label.new()
	caption.text = "YOU SCORED"
	caption.add_theme_font_size_override("font_size", 18)
	caption.add_theme_color_override("font_color", Color(0.659, 0.714, 1.0, 0.85))  # #A8B6FF, lavender
	caption.position = Vector2(cx - 200, sz.y * 0.21)
	caption.size = Vector2(400, 24)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(caption)

	# --- Big score number (the focal point) --------------------------------
	# White (or gold on new high), heavy outline = bold feel, soft colored glow.
	_score_label = Label.new()
	_score_label.text = str(rounds)
	_score_label.add_theme_font_size_override("font_size", 140)
	_score_label.add_theme_color_override("font_color",
		Color(1.0, 0.93, 0.55) if _is_new_high else Color.WHITE)
	_score_label.add_theme_color_override("font_outline_color",
		Color(1.0, 0.93, 0.55) if _is_new_high else Color(1, 1, 1, 1))
	_score_label.add_theme_constant_override("outline_size", 3)
	_score_label.add_theme_color_override("font_shadow_color",
		Color(1.0, 0.55, 0.10, 0.65) if _is_new_high else Color(0.30, 0.55, 1.0, 0.45))
	_score_label.add_theme_constant_override("shadow_offset_x", 0)
	_score_label.add_theme_constant_override("shadow_offset_y", 6)
	_score_label.add_theme_constant_override("shadow_outline_size", 22 if _is_new_high else 14)
	_score_label.position = Vector2(cx - 300, sz.y * 0.25)
	_score_label.size = Vector2(600, 170)
	_score_label.pivot_offset = _score_label.size * 0.5
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_score_label)

	# "rounds" sub-label glued under the score; ties the big number to its unit.
	var rounds_lbl := Label.new()
	rounds_lbl.text = "round" if rounds == 1 else "rounds"
	rounds_lbl.add_theme_font_size_override("font_size", 22)
	rounds_lbl.add_theme_color_override("font_color", Color(0.659, 0.714, 1.0, 0.85))
	rounds_lbl.position = Vector2(cx - 200, sz.y * 0.51)
	rounds_lbl.size = Vector2(400, 28)
	rounds_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(rounds_lbl)

	# --- Subdued personal-best pill ---------------------------------------
	# Intentionally lower contrast than the score, so the eye lands on the
	# score first. Tiny "★ BEST" prefix, then the number — single-line.
	_build_best_pill(cx, sz.y * 0.60, best)

	# --- Rank slot (filled async on new high + signed in) -----------------
	_rank_slot = Control.new()
	_rank_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rank_slot.position = Vector2(cx - 220, sz.y * 0.69)
	_rank_slot.size = Vector2(440, 48)
	add_child(_rank_slot)

	# --- Coins-earned pill (signed-in only) --------------------------------
	if FirebaseManager.is_signed_in():
		_build_coins_earned_pill(cx, sz.y * 0.78, CoinsManager.session_earned)

	# --- Buttons (home / play again) --------------------------------------
	_build_btn_face_material()
	var btn_y := sz.y * 0.92 - BTN_H * 0.5
	var btn_total := BTN_W * 2.0 + BTN_GAP
	_make_pill_button("HOME", ICON_BLUE,
		Vector2(cx - btn_total * 0.5, btn_y),
		func() -> void: game_manager.show_home())
	_make_pill_button("PLAY AGAIN", ICON_GREEN,
		Vector2(cx - btn_total * 0.5 + BTN_W + BTN_GAP, btn_y),
		func() -> void: game_manager.show_difficulty())

# ---------------- personal best pill ----------------

# Thin lavender outline pill, intentionally muted vs. the big score above.
func _build_best_pill(cx: float, y: float, best: int) -> void:
	const PW := 220.0
	const PH := 36.0
	var pill := Panel.new()
	pill.position = Vector2(cx - PW * 0.5, y)
	pill.size = Vector2(PW, PH)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.08, 0.20, 0.55)
	s.set_corner_radius_all(int(PH * 0.5))
	s.border_color = Color(0.50, 0.55, 1.0, 0.30)
	s.set_border_width_all(1)
	pill.add_theme_stylebox_override("panel", s)
	add_child(pill)

	var lbl := Label.new()
	lbl.text = "★  Best  %d" % best
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(0.74, 0.78, 1.0, 0.85))
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(lbl)

# ---------------- rank pill (new-high celebration payoff) ----------------

func _submit_and_show_rank() -> void:
	_rank_token += 1
	var token := _rank_token
	await LeaderboardManager.submit_score(GameState.difficulty, rounds)
	if token != _rank_token or not is_inside_tree():
		return
	var data: Dictionary = await LeaderboardManager.load_global(GameState.difficulty)
	if token != _rank_token or not is_inside_tree():
		return
	if not bool(data.get("ok", false)):
		return
	var rank := int(data.get("my_rank", 0))
	if rank <= 0:
		return
	_show_rank_pill(rank)

# Pill animating in from below with a brief bloom, showing the player's
# current leaderboard place. Styled gold/celebratory on a new high (visually
# the loudest element after the score) and muted lavender otherwise so a
# non-improving run doesn't feel like a celebration it didn't earn.
func _show_rank_pill(rank: int) -> void:
	if not _rank_slot:
		return
	var slot_sz := _rank_slot.size
	var pill := Panel.new()
	pill.size = slot_sz
	pill.position = Vector2.ZERO
	pill.pivot_offset = slot_sz * 0.5
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := StyleBoxFlat.new()
	s.set_corner_radius_all(int(slot_sz.y * 0.5))
	if _is_new_high:
		s.bg_color = Color(0.18, 0.13, 0.04, 0.70)
		s.border_color = GOLD
		s.set_border_width_all(2)
		s.shadow_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.55)
		s.shadow_size = 18
	else:
		s.bg_color = Color(0.06, 0.08, 0.20, 0.55)
		s.border_color = Color(0.50, 0.55, 1.0, 0.30)
		s.set_border_width_all(1)
	pill.add_theme_stylebox_override("panel", s)
	_rank_slot.add_child(pill)

	var lbl := Label.new()
	lbl.text = ("🏅  You're #%d on the leaderboard!" % rank) if _is_new_high \
		else "#%d on the leaderboard" % rank
	lbl.add_theme_font_size_override("font_size", 20 if _is_new_high else 16)
	lbl.add_theme_color_override("font_color",
		Color(1.0, 0.92, 0.55) if _is_new_high else Color(0.74, 0.78, 1.0, 0.85))
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(lbl)

	# Enter: rise from a few px below + fade in + tiny scale-bounce.
	pill.modulate.a = 0.0
	pill.position.y = 12.0
	pill.scale = Vector2(0.92, 0.92)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(pill, "modulate:a", 1.0, 0.35).set_trans(Tween.TRANS_SINE)
	tw.tween_property(pill, "position:y", 0.0, 0.45) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(pill, "scale", Vector2.ONE, 0.45) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# ---------------- score pulse (new-high only) ----------------

# Subtle scale-bounce on entry — draws the eye to the score without screaming.
func _pulse_score() -> void:
	if not _score_label:
		return
	_score_label.scale = Vector2(0.6, 0.6)
	_score_label.modulate.a = 0.0
	var entry := create_tween().set_parallel(true)
	entry.tween_property(_score_label, "modulate:a", 1.0, 0.35).set_trans(Tween.TRANS_SINE)
	entry.tween_property(_score_label, "scale", Vector2.ONE, 0.55) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Then a forever-gentle breathing pulse.
	await get_tree().create_timer(0.6).timeout
	if not is_inside_tree() or not _score_label:
		return
	var breathe := create_tween().set_loops()
	breathe.tween_property(_score_label, "scale", Vector2.ONE * 1.04, 1.2) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	breathe.tween_property(_score_label, "scale", Vector2.ONE, 1.2) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

# ---------------- coins-earned pill ----------------

# Gold pill: "Coins earned  + N". Mirrors the in-game HUD coin styling so the
# player recognizes it at a glance.
func _build_coins_earned_pill(cx: float, y: float, earned: int) -> void:
	const PW := 280.0
	const PH := 48.0
	var pill := Panel.new()
	pill.position = Vector2(cx - PW * 0.5, y)
	pill.size = Vector2(PW, PH)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.06, 0.07, 0.18, 0.85)
	st.set_corner_radius_all(int(PH * 0.5))
	st.border_color = Color(1.0, 0.78, 0.20, 0.85)
	st.set_border_width_all(2)
	st.shadow_color = Color(1.0, 0.78, 0.20, 0.40)
	st.shadow_size = 12
	pill.add_theme_stylebox_override("panel", st)
	add_child(pill)

	var lbl := Label.new()
	lbl.text = "Coins earned   + %d" % earned
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45))
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(lbl)

# ---------------- pill buttons (home / play again) ----------------

func _build_btn_face_material() -> void:
	var sh := Shader.new()
	sh.code = BTN_SHADER
	_btn_face_mat = ShaderMaterial.new()
	_btn_face_mat.shader = sh
	_btn_face_mat.set_shader_parameter("rect_size",
		Vector2(BTN_W + BTN_PAD * 2.0, BTN_H + BTN_PAD * 2.0))
	_btn_face_mat.set_shader_parameter("pad", BTN_PAD)
	_btn_face_mat.set_shader_parameter("radius", 30.0)
	_btn_face_mat.set_shader_parameter("top_col", Vector3(0.118, 0.153, 0.369))
	_btn_face_mat.set_shader_parameter("bot_col", Vector3(0.078, 0.102, 0.259))

# Dark navy-glass pill: shader face + glowing colored icon on the leading edge
# + light label. Mirrors home_screen's _make_menu_button so the player reads
# this screen as part of the same UI language.
func _make_pill_button(txt: String, icon_col: Color, pos: Vector2, cb: Callable) -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(BTN_W, BTN_H)
	wrap.size = Vector2(BTN_W, BTN_H)
	wrap.position = pos
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wrap)

	var btn := Button.new()
	btn.size = Vector2(BTN_W, BTN_H)
	btn.pivot_offset = Vector2(BTN_W, BTN_H) * 0.5
	btn.focus_mode = Control.FOCUS_NONE
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(st, empty)
	wrap.add_child(btn)

	var face := ColorRect.new()
	face.material = _btn_face_mat
	face.position = Vector2(-BTN_PAD, -BTN_PAD)
	face.size = Vector2(BTN_W + BTN_PAD * 2.0, BTN_H + BTN_PAD * 2.0)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(face)

	var rtl := is_layout_rtl()
	var icon := Panel.new()
	var d := 40.0
	icon.size = Vector2(d, d)
	icon.position = Vector2(BTN_W - 18 - d if rtl else 18, (BTN_H - d) * 0.5)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := StyleBoxFlat.new()
	ic.bg_color = icon_col.lightened(0.12)
	ic.set_corner_radius_all(int(d * 0.5))
	ic.border_color = icon_col.lightened(0.45)
	ic.set_border_width_all(2)
	ic.shadow_color = Color(icon_col.r, icon_col.g, icon_col.b, 0.6)
	ic.shadow_size = 12
	icon.add_theme_stylebox_override("panel", ic)
	btn.add_child(icon)

	var lbl := Label.new()
	lbl.text = txt
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(0.93, 0.96, 1.0))
	lbl.position = Vector2(36 if rtl else 18 + d + 14, 0)
	lbl.size = Vector2(BTN_W - (18 + d + 14) - 36, BTN_H)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if rtl else HORIZONTAL_ALIGNMENT_LEFT
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(lbl)

	btn.mouse_entered.connect(_on_btn_hover.bind(btn, true))
	btn.mouse_exited.connect(_on_btn_hover.bind(btn, false))
	btn.button_down.connect(_on_btn_down.bind(btn))
	btn.button_up.connect(_on_btn_up.bind(btn))
	btn.pressed.connect(cb)
	return wrap

func _on_btn_hover(btn: Button, entered: bool) -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(btn, "scale", Vector2.ONE * (1.03 if entered else 1.0), 0.16) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(btn, "modulate",
		Color(1.10, 1.10, 1.10) if entered else Color.WHITE, 0.16)

func _on_btn_down(btn: Button) -> void:
	create_tween().tween_property(btn, "scale", Vector2.ONE * 0.98, 0.10) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _on_btn_up(btn: Button) -> void:
	create_tween().tween_property(btn, "scale", Vector2.ONE, 0.20) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
