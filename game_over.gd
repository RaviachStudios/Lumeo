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

# Glass pill face shared by both game-over buttons (gradient body + top highlight
# + tunable accent rim glow + soft drop shadow). Mirrors the difficulty screen's
# card face so the whole game reads as one design language. The +pad/-pad inset
# gives the shadow room to breathe outside the pill's footprint. The primary
# (PLAY AGAIN) button drives the rim/fill hot; HOME stays a subdued glass pill.
const BTN_PAD := 22.0
const BTN_SHADER := "
shader_type canvas_item;
uniform vec2 rect_size = vec2(400.0, 114.0);
uniform float pad = 22.0;
uniform float radius = 32.0;
uniform vec3 top_col = vec3(0.118, 0.153, 0.369);
uniform vec3 bot_col = vec3(0.078, 0.102, 0.259);
uniform vec3 rim_col = vec3(0.35, 0.55, 1.0);
uniform float rim_boost = 1.0;
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
	float sd = sdf_round_box(p - vec2(0.0, 8.0), hb, radius);
	float shadow = smoothstep(pad, 0.0, sd) * 0.50;
	float ty = clamp((px.y - pad) / (rect_size.y - pad * 2.0), 0.0, 1.0);
	vec3 base = mix(top_col, bot_col, ty);
	base += vec3(0.65, 0.75, 1.0) * smoothstep(0.18, 0.0, ty) * 0.12;          // top sheen
	base += rim_col * smoothstep(-7.0, -0.5, d) * 0.34 * rim_boost;            // accent rim
	base += rim_col * smoothstep(120.0, 0.0, length(p)) * 0.06 * rim_boost;    // inner glow
	float a = max(shadow, body);
	vec3 rgb = mix(vec3(0.0, 0.01, 0.04), base, body);
	COLOR = vec4(rgb, a);
}
"

const BTN_W := 280.0
const BTN_H := 68.0
const BTN_GAP := 36.0

var _confetti: Array[Dictionary] = []
var _time: float = 0.0
var _is_new_high: bool = false

var _bg: ColorRect
var _bg_mat: ShaderMaterial
var _score_label: Label
var _rank_slot: Control               # placeholder; the rank pill is added here once Firestore returns
var _rank_token := 0                  # bumped on free; awaited callbacks bail when stale
# Captured Arena contest context (empty for normal play). Captured + cleared at
# the very top of _ready so nothing downstream sees a stale global context.
var _contest_ctx: Dictionary = {}

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Capture the contest context (if any) before it can leak into a later game.
	_contest_ctx = GameState.contest_context.duplicate(true)
	GameState.contest_context = {}
	_is_new_high = GameState.submit_score(rounds)
	# Badges: a finished game (+ its score milestones) is always worth evaluating.
	BadgeManager.note_game_played(GameState.difficulty)
	BadgeManager.note_score(GameState.difficulty, rounds)
	_build_background()
	_spawn_confetti()
	_build_ui()
	AudioManager.play_win_sound()
	if _is_new_high:
		_pulse_score()
	# Daily submit happens on EVERY signed-in finish — the daily best is a
	# different bar than the all-time best (a "non-personal-best" run can still
	# be a today's-best), so we don't gate on _is_new_high here. The manager
	# itself only writes if the score beats today's existing row, so this is
	# safe to call unconditionally.
	if FirebaseManager.is_signed_in() and FirebaseManager.has_display_name():
		LeaderboardManager.submit_score_daily(GameState.difficulty, rounds)
	# All-time submit + rank pill, only on personal best — see _submit_and_show_rank
	# for why the rank reveal is gated.
	if _is_new_high and FirebaseManager.is_signed_in() and FirebaseManager.has_display_name():
		_submit_and_show_rank()
	# Record the result for the Arena contest this game belonged to. Independent of
	# the leaderboard submits above (which still run — a contest game updates the
	# player's global/daily bests exactly like a normal game).
	if not _contest_ctx.is_empty():
		ContestManager.submit_contest_result(_contest_ctx, rounds)

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

	# --- Rank slot (filled async on new high + signed in) -----------------
	_rank_slot = Control.new()
	_rank_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rank_slot.position = Vector2(cx - 220, sz.y * 0.65)
	_rank_slot.size = Vector2(440, 48)
	add_child(_rank_slot)

	# --- Coins-earned pill (signed-in only) --------------------------------
	if FirebaseManager.is_signed_in():
		_build_coins_earned_pill(cx, sz.y * 0.73, CoinsManager.session_earned)

	# --- Buttons (home / play again) --------------------------------------
	# HOME is the calm secondary glass pill; PLAY AGAIN is the primary call to
	# action — brighter fill, a live green rim glow and a replay icon so the eye
	# lands on it first.
	var btn_y := sz.y * 0.92 - BTN_H * 0.5
	var btn_total := BTN_W * 2.0 + BTN_GAP
	if not _contest_ctx.is_empty():
		# Contest game: return to the contest (primary) instead of replaying, since
		# whether the player may play again depends on the contest state.
		var cid := String(_contest_ctx.get("id", ""))
		_make_pill_button("HOME", "home", Color(0.40, 0.58, 1.0), false,
			Vector2(cx - btn_total * 0.5, btn_y),
			func() -> void: game_manager.show_home())
		_make_pill_button("BACK TO ARENA", "replay", Color(0.30, 0.80, 0.52), true,
			Vector2(cx - btn_total * 0.5 + BTN_W + BTN_GAP, btn_y),
			func() -> void: game_manager.show_contest_detail(cid))
	else:
		_make_pill_button("HOME", "home", Color(0.40, 0.58, 1.0), false,
			Vector2(cx - btn_total * 0.5, btn_y),
			func() -> void: game_manager.show_home())
		_make_pill_button("PLAY AGAIN", "replay", Color(0.30, 0.80, 0.52), true,
			Vector2(cx - btn_total * 0.5 + BTN_W + BTN_GAP, btn_y),
			func() -> void: game_manager.show_difficulty())

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
	BadgeManager.note_rank(rank, false)   # leaderboard-placement badges
	_show_rank_pill(rank)

# Pill animating in from below with a brief bloom, showing the player's current
# leaderboard place. Only reached on a new personal best, so it's styled
# gold/celebratory — visually the loudest element after the score.
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
	s.bg_color = Color(0.18, 0.13, 0.04, 0.70)
	s.border_color = GOLD
	s.set_border_width_all(2)
	s.shadow_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.55)
	s.shadow_size = 18
	pill.add_theme_stylebox_override("panel", s)
	_rank_slot.add_child(pill)

	var lbl := Label.new()
	lbl.text = "🏅  You're #%d on the leaderboard!" % rank
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
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

# A per-button glass face. `accent` tints the rim; `primary` brightens the fill
# and the resting rim so PLAY AGAIN reads as the dominant action.
func _pill_face_material(accent: Color, primary: bool) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = BTN_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("rect_size",
		Vector2(BTN_W + BTN_PAD * 2.0, BTN_H + BTN_PAD * 2.0))
	mat.set_shader_parameter("pad", BTN_PAD)
	mat.set_shader_parameter("radius", 32.0)
	if primary:
		# A filled, lifted body — distinctly brighter than the navy glass.
		mat.set_shader_parameter("top_col", Vector3(0.10, 0.34, 0.24))
		mat.set_shader_parameter("bot_col", Vector3(0.05, 0.20, 0.15))
	else:
		mat.set_shader_parameter("top_col", Vector3(0.118, 0.153, 0.369))
		mat.set_shader_parameter("bot_col", Vector3(0.063, 0.086, 0.227))
	mat.set_shader_parameter("rim_col", Vector3(accent.r, accent.g, accent.b))
	mat.set_shader_parameter("rim_boost", 1.5 if primary else 0.9)
	return mat

# Glass pill: shader face + an accent icon + label. PLAY AGAIN (primary) carries
# a live breathing rim glow so it's clearly the main action.
func _make_pill_button(txt: String, icon_kind: String, accent: Color,
		primary: bool, pos: Vector2, cb: Callable) -> Control:
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

	var mat := _pill_face_material(accent, primary)
	var face := ColorRect.new()
	face.material = mat
	face.position = Vector2(-BTN_PAD, -BTN_PAD)
	face.size = Vector2(BTN_W + BTN_PAD * 2.0, BTN_H + BTN_PAD * 2.0)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(face)

	# Icon + label as a centered group. Measure the text with the real font so
	# the pair sits truly centered — a char-count approximation drifts (e.g. the
	# short "HOME" ended up hanging right of center), so use get_string_size.
	var icon_sz := 24.0
	var gap := 14.0
	var font_size := 23
	var font := ThemeDB.fallback_font
	var text_w := font.get_string_size(
		txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	var group_w := icon_sz + gap + text_w
	var gx := (BTN_W - group_w) * 0.5
	var fg := accent.lightened(0.5) if primary else Color(0.86, 0.90, 1.0)

	var icon := _btn_icon(icon_kind, icon_sz * 0.5, fg)
	icon.position = Vector2(gx + icon_sz * 0.5, BTN_H * 0.5)
	btn.add_child(icon)

	var lbl := Label.new()
	lbl.text = txt
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", Color(0.96, 1.0, 0.97) if primary else Color(0.86, 0.90, 1.0))
	lbl.position = Vector2(gx + icon_sz + gap, 0)
	lbl.size = Vector2(text_w + 4.0, BTN_H)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(lbl)

	btn.mouse_entered.connect(_on_btn_hover.bind(btn, true))
	btn.mouse_exited.connect(_on_btn_hover.bind(btn, false))
	btn.button_down.connect(_on_btn_down.bind(btn))
	btn.button_up.connect(_on_btn_up.bind(btn))
	btn.pressed.connect(cb)

	# Primary button: a gentle forever-pulse on the rim so it feels alive.
	if primary:
		var set_rim := func(v: float) -> void:
			if is_instance_valid(mat):
				mat.set_shader_parameter("rim_boost", v)
		var pulse := create_tween().set_loops()
		pulse.tween_method(set_rim, 1.5, 2.1, 1.1) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		pulse.tween_method(set_rim, 2.1, 1.5, 1.1) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return wrap

func _on_btn_hover(btn: Button, entered: bool) -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(btn, "scale", Vector2.ONE * (1.04 if entered else 1.0), 0.16) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(btn, "position:y", -3.0 if entered else 0.0, 0.16) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

# ---------------- button icons (procedural) ----------------

func _btn_icon(kind: String, s: float, col: Color) -> Node2D:
	if kind == "replay":
		return _replay_icon(s, col)
	return _home_icon(s, col)

# Little house: roof triangle over a body, with a doorway notched out via the
# pill's dark fill color so it reads as a home even at small size.
func _home_icon(s: float, col: Color) -> Node2D:
	var n := Node2D.new()
	var roof := Polygon2D.new()
	roof.polygon = PackedVector2Array([
		Vector2(0, -s), Vector2(s * 1.05, -s * 0.05), Vector2(-s * 1.05, -s * 0.05)])
	roof.color = col
	n.add_child(roof)
	var w := s * 0.66
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(-w, -s * 0.05), Vector2(w, -s * 0.05),
		Vector2(w, s * 0.85), Vector2(-w, s * 0.85)])
	body.color = col
	n.add_child(body)
	var door := Polygon2D.new()
	var dw := s * 0.22
	door.polygon = PackedVector2Array([
		Vector2(-dw, s * 0.85), Vector2(dw, s * 0.85),
		Vector2(dw, s * 0.28), Vector2(-dw, s * 0.28)])
	door.color = Color(0.09, 0.12, 0.26)   # matches the navy pill fill behind it
	n.add_child(door)
	return n

# Circular replay arrow: a near-full ring with a gap, capped by an arrowhead.
func _replay_icon(s: float, col: Color) -> Node2D:
	var n := Node2D.new()
	var arc := Line2D.new()
	arc.width = maxf(2.6, s * 0.30)
	arc.default_color = col
	arc.antialiased = true
	arc.begin_cap_mode = Line2D.LINE_CAP_ROUND
	arc.end_cap_mode = Line2D.LINE_CAP_ROUND
	var start := deg_to_rad(-50.0)
	var end := deg_to_rad(210.0)
	var pts := PackedVector2Array()
	var steps := 26
	for i in steps + 1:
		var a: float = lerp(start, end, float(i) / steps)
		pts.append(Vector2(cos(a), sin(a)) * s)
	arc.points = pts
	n.add_child(arc)
	# Arrowhead at the arc's start. The arc sweeps with increasing angle, so the
	# tip must point *against* that (decreasing angle) to read as the rotation
	# flowing into the gap — the previous tip pointed the wrong way.
	var tip := Vector2(cos(start), sin(start)) * s
	var tangent := Vector2(-sin(start), cos(start))    # direction of increasing angle
	var radial := Vector2(cos(start), sin(start))
	var ah := s * 0.62
	var head := Polygon2D.new()
	head.color = col
	head.polygon = PackedVector2Array([
		tip - tangent * ah * 0.9,
		tip - radial * ah * 0.7,
		tip + radial * ah * 0.7])
	n.add_child(head)
	# Rotate the whole glyph a quarter turn counter-clockwise (negative angle in
	# Godot's y-down 2D space). Geometry is centred on the node origin, so it
	# spins in place without shifting off the button.
	n.rotation = -PI * 0.5
	return n

func _on_btn_down(btn: Button) -> void:
	create_tween().tween_property(btn, "scale", Vector2.ONE * 0.98, 0.10) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _on_btn_up(btn: Button) -> void:
	create_tween().tween_property(btn, "scale", Vector2.ONE, 0.20) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
