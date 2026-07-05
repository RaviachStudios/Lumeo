extends Control

# First-run home-screen tour. A dim overlay with a moving "spotlight" hole that
# highlights one home widget at a time, plus a small coach card (a winged-Simon
# mascot + title + body + Next) that walks the player through: coins & the
# Shop, the START orb, the Leaderboard and the Arena. Steps whose target
# widget doesn't exist (e.g. the coin pill / daily claim for a signed-out
# guest) are simply omitted by the caller, so the tour adapts itself to
# whatever the screen is actually showing.
#
# One-shot: emits `finished` when the player taps through the last step or hits
# Skip. Persistence (a local bool for guests, a Firestore bool for signed-in
# users) is owned by the home screen — this node only runs the presentation.
#
# Steps are Dictionaries: {rect: Rect2 (empty/zero = a centered intro, no
# spotlight), title: String, body: String}. Rects are in viewport space.

const SimonFlyer := preload("res://simon_flyer.gd")

signal finished

const DIM := Color(0.02, 0.03, 0.09, 0.85)
const RING := Color(0.64, 0.62, 1.0)
const CARD_W := 470.0
const CARD_H := 196.0
const PAD := 14.0            # spotlight breathing room around the target rect

var _steps: Array = []
var _idx := 0
var _done := false

# Spotlight state (viewport space). Animated between steps.
var _spot := Rect2()
var _has_spot := false
var _spot_from := Rect2()
var _spot_to := Rect2()
var _phase := 0.0           # drives the gentle ring pulse

var _painter: Control       # draws the dim veil + hole + glowing ring
var _card: Panel
var _mascot: TextureRect
var _title_lbl: Label
var _body_lbl: Label
var _step_lbl: Label
var _skip_btn: Button
var _next_btn: Button
var _spot_tween: Tween

func _ready() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
	mouse_filter = Control.MOUSE_FILTER_STOP     # eat every tap meant for the menu

# Called by the home screen right after add_child.
func setup(steps: Array) -> void:
	_steps = steps
	if _steps.is_empty():
		_finish()
		return
	_build()
	_apply_step(false)

	# Gentle fade-in for the whole overlay.
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_SINE)
	set_process(true)

func _build() -> void:
	var sz := size

	# The veil + spotlight are painted by a full-screen child so its _draw stays
	# independent of the card / button children above it.
	_painter = Control.new()
	_painter.position = Vector2.ZERO
	_painter.size = sz
	_painter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_painter.draw.connect(_draw_overlay)
	add_child(_painter)

	# Tapping anywhere on the dimmed backdrop advances the tour (forgiving). The
	# card's own buttons sit above this and consume their taps first.
	var backdrop := Button.new()
	backdrop.position = Vector2.ZERO
	backdrop.size = sz
	backdrop.focus_mode = Control.FOCUS_NONE
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus"]:
		backdrop.add_theme_stylebox_override(s, empty)
	backdrop.pressed.connect(_advance)
	add_child(backdrop)

	_build_card()

func _build_card() -> void:
	_card = Panel.new()
	_card.size = Vector2(CARD_W, CARD_H)
	_card.mouse_filter = Control.MOUSE_FILTER_STOP     # not click-through to backdrop
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.05, 0.06, 0.16, 0.98)
	st.set_corner_radius_all(22)
	st.border_color = Color(0.45, 0.50, 1.0, 0.55)
	st.set_border_width_all(2)
	st.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	st.shadow_size = 20
	_card.add_theme_stylebox_override("panel", st)
	add_child(_card)

	# Winged-Simon mascot (baked, shared texture) as the friendly guide.
	_mascot = TextureRect.new()
	_mascot.texture = SimonFlyer.frames()[1]
	_mascot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_mascot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_mascot.size = Vector2(78, 78)
	_mascot.position = Vector2(16, 20)
	_mascot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(_mascot)
	# Idle bob so the guide feels alive.
	var bob := create_tween().set_loops()
	bob.tween_property(_mascot, "position:y", 14.0, 1.1) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property(_mascot, "position:y", 20.0, 1.1) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var tx := 108.0
	var tw := CARD_W - tx - 20.0

	_title_lbl = Label.new()
	_title_lbl.add_theme_font_size_override("font_size", 25)
	_title_lbl.add_theme_color_override("font_color", Color.WHITE)
	_title_lbl.add_theme_color_override("font_shadow_color", Color(0.35, 0.42, 1.0, 0.5))
	_title_lbl.add_theme_constant_override("shadow_offset_x", 0)
	_title_lbl.add_theme_constant_override("shadow_offset_y", 0)
	_title_lbl.add_theme_constant_override("shadow_outline_size", 6)
	_title_lbl.position = Vector2(tx, 22)
	_title_lbl.size = Vector2(tw, 34)
	_title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(_title_lbl)

	_body_lbl = Label.new()
	_body_lbl.add_theme_font_size_override("font_size", 16)
	_body_lbl.add_theme_color_override("font_color", Color(0.78, 0.82, 1.0, 0.92))
	_body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_lbl.position = Vector2(tx, 60)
	_body_lbl.size = Vector2(tw, 84)
	_body_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(_body_lbl)

	_step_lbl = Label.new()
	_step_lbl.add_theme_font_size_override("font_size", 14)
	_step_lbl.add_theme_color_override("font_color", Color(0.62, 0.64, 0.86, 0.8))
	_step_lbl.position = Vector2(CARD_W * 0.5 - 45, CARD_H - 44)
	_step_lbl.size = Vector2(90, 32)
	_step_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_step_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_step_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(_step_lbl)

	_skip_btn = _make_button("Skip", Vector2(16, CARD_H - 52), Vector2(92, 40),
		Color(0.16, 0.18, 0.34), _finish)
	_next_btn = _make_button("Next", Vector2(CARD_W - 16 - 140, CARD_H - 52), Vector2(140, 40),
		Color(0.20, 0.55, 0.96), _advance)
	_next_btn.add_theme_font_size_override("font_size", 20)

func _make_button(txt: String, pos: Vector2, size: Vector2, col: Color, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = txt
	btn.position = pos
	btn.size = size
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 18)
	var sn := StyleBoxFlat.new()
	sn.bg_color = col
	sn.set_corner_radius_all(13)
	btn.add_theme_stylebox_override("normal", sn)
	var sh := sn.duplicate() as StyleBoxFlat
	sh.bg_color = col.lightened(0.2)
	btn.add_theme_stylebox_override("hover", sh)
	var sp := sn.duplicate() as StyleBoxFlat
	sp.bg_color = col.darkened(0.2)
	btn.add_theme_stylebox_override("pressed", sp)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.pressed.connect(cb)
	_card.add_child(btn)
	return btn

# ---------------- stepping ----------------

func _advance() -> void:
	if _done:
		return
	if _idx >= _steps.size() - 1:
		_finish()
		return
	_idx += 1
	_apply_step(true)

func _apply_step(animate: bool) -> void:
	var step: Dictionary = _steps[_idx]
	var raw: Rect2 = step.get("rect", Rect2())
	var has := raw.size.x > 1.0 and raw.size.y > 1.0
	var target := Rect2()
	if has:
		target = Rect2(raw.position - Vector2(PAD, PAD), raw.size + Vector2(PAD, PAD) * 2.0)

	_title_lbl.text = String(step.get("title", ""))
	_body_lbl.text = String(step.get("body", ""))
	_step_lbl.text = "%d / %d" % [_idx + 1, _steps.size()]
	var last := _idx == _steps.size() - 1
	_next_btn.text = "Got it!" if last else "Next"
	_skip_btn.visible = not last

	if _spot_tween and _spot_tween.is_valid():
		_spot_tween.kill()

	if animate and _has_spot and has:
		# Slide the spotlight from where it is to the new target.
		_spot_from = _spot
		_spot_to = target
		_spot_tween = create_tween()
		_spot_tween.tween_method(_lerp_spot, 0.0, 1.0, 0.30) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		_has_spot = true
	else:
		_has_spot = has
		_spot = target
		_painter.queue_redraw()

	_place_card(has, target)

func _lerp_spot(t: float) -> void:
	_spot = Rect2(_spot_from.position.lerp(_spot_to.position, t),
		_spot_from.size.lerp(_spot_to.size, t))
	_painter.queue_redraw()

# Place the card clear of the spotlight: below it when there's room, otherwise
# above; centered on screen for the spotlight-less intro step.
func _place_card(has: bool, spot: Rect2) -> void:
	var sz := size
	var pos: Vector2
	if not has:
		pos = (sz - Vector2(CARD_W, CARD_H)) * 0.5
	else:
		var x: float = clampf(spot.get_center().x - CARD_W * 0.5, 20.0, sz.x - CARD_W - 20.0)
		var below := spot.end.y + 22.0
		var y: float
		if below + CARD_H <= sz.y - 20.0:
			y = below
		else:
			y = spot.position.y - CARD_H - 22.0
		y = clampf(y, 20.0, sz.y - CARD_H - 20.0)
		pos = Vector2(x, y)

	# Little pop each step so the eye follows the card.
	_card.pivot_offset = _card.size * 0.5
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_card, "position", pos, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_card.scale = Vector2(0.97, 0.97)
	tw.tween_property(_card, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _process(dt: float) -> void:
	_phase += dt
	if _has_spot:
		_painter.queue_redraw()

# ---------------- drawing ----------------

func _draw_overlay() -> void:
	var sz := _painter.size
	if not _has_spot:
		_painter.draw_rect(Rect2(Vector2.ZERO, sz), DIM)
		return

	var s := _spot
	# Four dim bands around the rectangular hole (leaves the target lit).
	_painter.draw_rect(Rect2(0, 0, sz.x, s.position.y), DIM)
	_painter.draw_rect(Rect2(0, s.end.y, sz.x, sz.y - s.end.y), DIM)
	_painter.draw_rect(Rect2(0, s.position.y, s.position.x, s.size.y), DIM)
	_painter.draw_rect(Rect2(s.end.x, s.position.y, sz.x - s.end.x, s.size.y), DIM)

	# Soft outer glow (a few expanding, fading outlines) + a crisp pulsing ring.
	var pulse := 0.75 + 0.25 * sin(_phase * 4.0)
	for i in range(4, 0, -1):
		var e := float(i) * 4.0
		_painter.draw_rect(Rect2(s.position - Vector2(e, e), s.size + Vector2(e, e) * 2.0),
			Color(RING.r, RING.g, RING.b, 0.05 * pulse), false, 3.0)
	_painter.draw_rect(s, Color(RING.r, RING.g, RING.b, pulse), false, 2.5)

# ---------------- finish ----------------

func _finish() -> void:
	if _done:
		return
	_done = true
	set_process(false)
	finished.emit()
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.20).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(queue_free)
